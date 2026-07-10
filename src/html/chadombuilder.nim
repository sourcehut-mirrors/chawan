{.push raises: [].}

import std/algorithm
import std/options

import chame/htmlparser
import chame/tags
import config/conftypes
import encoding/charset
import html/catom
import html/dom
import monoucha/fromjs
import monoucha/jsbind
import monoucha/quickjs
import monoucha/tojs
import types/refstring
import types/url
import utils/twtstr

# DOMBuilder implementation for Chawan.

type CharsetConfidence* = enum
  ccTentative, ccCertain, ccIrrelevant

type
  HTML5ParserWrapper* {.final.} = ref object of RootObj
    parser: HTML5Parser[ParentNode, CAtom]
    builder*: ChaDOMBuilder
    opts: HTML5ParserOpts[ParentNode, CAtom]
    stoppedFromScript: bool

  ChaDOMBuilder {.final.} = ref object of DOMBuilder[ParentNode, CAtom]
    charset*: Charset
    confidence*: CharsetConfidence
    document*: Document
    poppedScript: HTMLScriptElement

  DOMBuilderImpl = ChaDOMBuilder
  HandleImpl = ParentNode
  AtomImpl = CAtom

include chame/htmlparseriface

type DOMParser = ref object # JS interface

jsDestructor(DOMParser)

proc setActiveParser(document: Document; wrapper: HTML5ParserWrapper) =
  document.parser = wrapper

proc getDocumentImpl(builder: ChaDOMBuilder): ParentNode =
  return builder.document

proc atomToTagTypeImpl(builder: ChaDOMBuilder; atom: CAtom): TagType =
  return atom.toTagType()

proc tagTypeToAtomImpl(builder: ChaDOMBuilder; tagType: TagType): CAtom =
  return tagType.toAtom()

proc namespaceToAtomImpl(builder: ChaDOMBuilder; ns: Namespace): CAtom =
  return ns.toStaticAtom().toAtom()

proc strToAtomImpl(builder: ChaDOMBuilder; s: string): CAtom =
  return s.toAtom()

proc finish(builder: ChaDOMBuilder) =
  let document = builder.document
  while document.scriptsToExecOnLoad != nil:
    #TODO spin event loop
    let script = document.scriptsToExecOnLoad
    script.execute()
    let next = script.next
    document.scriptsToExecOnLoad = next
    if next == nil:
      document.scriptsToExecOnLoadTail = nil
  let window = document.window
  if document.scriptingEnabled:
    #TODO queue DOM task, then spin event loop
    window.fireEvent(satDOMContentLoaded, document, bubbles = true,
      cancelable = false, trusted = true)
  #TODO ServiceWorkerContainer etc.

proc restart*(wrapper: HTML5ParserWrapper; charset: Charset) =
  let builder = wrapper.builder
  let oldDocument = builder.document
  let document = newDocument(oldDocument.url)
  document.charset = charset
  document.setActiveParser(wrapper)
  document.contentType = satTextHtml
  let window = oldDocument.window
  if window != nil:
    document.window = window
    window.document = document
  builder.document = document
  builder.charset = charset
  wrapper.parser = initHTML5Parser(builder, wrapper.opts)

proc setQuirksModeImpl(builder: ChaDOMBuilder; quirksMode: QuirksMode) =
  builder.document.mode = quirksMode
  if quirksMode == qmQuirks:
    builder.document.applyQuirksSheet()

proc setEncodingImpl(builder: ChaDOMBuilder; encoding: string):
    SetEncodingResult =
  if builder.confidence != ccTentative:
    return seContinue
  if builder.charset in {csUtf16le, csUtf16be}:
    builder.confidence = ccCertain
    return seContinue
  let charset = getCharset(encoding)
  if charset == csUnknown:
    return seContinue
  builder.confidence = ccCertain
  if charset == builder.charset:
    return seContinue
  builder.charset = if charset == csXUserDefined:
    csWindows1252
  else:
    charset
  return seStop

proc getTemplateContentImpl(builder: ChaDOMBuilder; handle: ParentNode):
    ParentNode =
  return HTMLTemplateElement(handle).content

proc getParentNodeImpl(builder: ChaDOMBuilder; handle: ParentNode):
    Option[ParentNode] =
  return option(handle.parentNode)

proc getLocalNameImpl(builder: ChaDOMBuilder; handle: ParentNode): CAtom =
  return Element(handle).localName

proc getNamespaceImpl(builder: ChaDOMBuilder; handle: ParentNode): Namespace =
  return Element(handle).namespaceURI.toNamespace()

proc createHTMLElementImpl(builder: ChaDOMBuilder): ParentNode =
  return builder.document.newHTMLElement(ttHtml)

proc createElementForTokenImpl(builder: ChaDOMBuilder; localName: CAtom;
    namespace: Namespace; intendedParent: ParentNode;
    attrs: sink seq[ParsedAttr[CAtom]]): ParentNode =
  let document = builder.document
  let element = document.newElement(localName.view(), namespace.toStaticAtom())
  element.sinkAttrs(move(attrs))
  element.resetElement(nil)
  if element of HTMLScriptElement:
    let script = HTMLScriptElement(element)
    script.parserDocument = document
    script.forceAsync = false
    # Note: per standard, we could set already started to true here when we
    # are parsing from document.write, but that sounds like a horrible idea.
  elif namespace == nsSVG and localName == satSvg:
    # hack to distinguish between parser-inserted SVG and dynamically added
    # SVG; TODO get rid of this
    let svg = SVGSVGElement(element)
    svg.parserDocument = document
  return element

proc insertCommentImpl(builder: ChaDOMBuilder; parent: ParentNode;
    text: string; before: Option[ParentNode]) =
  let comment = builder.document.createComment(text)
  parent.insert(comment, before.get(nil), nil)

proc appendDocumentTypeImpl(builder: ChaDOMBuilder;
    name, publicId, systemId: string) =
  let doctype = builder.document.newDocumentType(name, publicId, systemId)
  builder.document.insert(doctype, nil, nil)

proc insertBeforeImpl(builder: ChaDOMBuilder; parent, child: ParentNode;
    before: Option[ParentNode]) =
  parent.insert(child, before.get(nil), nil)

proc insertTextImpl(builder: ChaDOMBuilder; parent: ParentNode; text: string;
    before: Option[ParentNode]) =
  let before = before.get(nil)
  let prevSibling = if before != nil:
    before.previousSibling
  else:
    parent.lastChild
  if prevSibling != nil and prevSibling of Text:
    Text(prevSibling).data &= text
    if parent of Element:
      Element(parent).invalidate()
  else:
    let text = builder.document.newText(text)
    parent.insert(text, before, nil)

proc removeImpl(builder: ChaDOMBuilder; child: ParentNode) =
  if child.parentNode != nil:
    child.removeImpl(suppressObservers = true)

proc moveChildrenImpl(builder: ChaDOMBuilder; fromNode, toNode: ParentNode) =
  let toMove = fromNode.getChildList()
  for node in toMove:
    node.removeImpl(suppressObservers = true)
  for child in toMove:
    toNode.insert(child, nil, nil)

proc sortAttrsImpl(builder: ChaDOMBuilder; attrs: var seq[ParsedAttr[CAtom]]) =
  if attrs.len > 1:
    attrs.sort(proc(a, b: ParsedAttr[CAtom]): int {.nimcall.} =
      cmp(uint32(a.name), uint32(b.name))
    )
    var j = 1
    var prev = attrs[0].name
    for i in 1 ..< attrs.len:
      let name = attrs[i].name
      if name != prev:
        if j < i:
          attrs[j] = move(attrs[i])
        inc j
      prev = name
    attrs.setLen(j)

proc addAttrsIfMissingImpl(builder: ChaDOMBuilder; handle: ParentNode;
    attrs: seq[ParsedAttr[CAtom]]) =
  let element = Element(handle)
  for attr in attrs:
    if not element.attrb(attr.name.view()):
      element.attr(attr.name.view(), attr.value)

proc setScriptAlreadyStartedImpl(builder: ChaDOMBuilder; script: ParentNode) =
  HTMLScriptElement(script).alreadyStarted = true

proc associateWithFormImpl(builder: ChaDOMBuilder;
    element, form, intendedParent: ParentNode) =
  if form.inSameTree(intendedParent):
    #TODO remove following test eventually
    if element of FormAssociatedElement:
      let element = FormAssociatedElement(element)
      element.setForm(HTMLFormElement(form))
      element.parserInserted = true

proc elementPoppedImpl(builder: ChaDOMBuilder; element: ParentNode) =
  let element = Element(element)
  let document = builder.document
  if element.tagType == ttTextarea:
    element.resetElement(nil)
  elif element of HTMLScriptElement:
    if document.scriptingEnabled:
      assert builder.poppedScript == nil
      inc document.throwOnDynamicMarkupInsertion
      #TODO I think this has to be moved for custom elements
      document.window.performMicrotaskCheckpoint()
      dec document.throwOnDynamicMarkupInsertion
    builder.poppedScript = HTMLScriptElement(element)
  elif element of SVGSVGElement:
    let window = document.window
    if window != nil:
      let svg = SVGSVGElement(element)
      window.loadSVG(svg)
  elif element of HTMLStyleElement:
    HTMLStyleElement(element).updateSheet()

proc newChaDOMBuilder(url: URL; window: Window; confidence: CharsetConfidence;
    charset = DefaultCharset): ChaDOMBuilder =
  let document = newDocument(url)
  document.charset = charset
  document.contentType = satTextHtml
  if window != nil:
    document.window = window
    window.document = document
  return ChaDOMBuilder(
    document: document,
    confidence: confidence,
    charset: charset
  )

# https://html.spec.whatwg.org/multipage/parsing.html#parsing-html-fragments
proc parseHTMLFragment*(element: Element; s: openArray[char]): seq[Node] =
  let url = parseURL0("about:blank")
  let builder = newChaDOMBuilder(url, nil, ccIrrelevant)
  let document = builder.document
  document.mode = element.document.mode
  let root = document.newHTMLElement(ttHtml)
  document.insert(root, nil, nil)
  let form = element.findAncestorIncl(ttForm)
  var opts = HTML5ParserOpts[ParentNode, CAtom](
    isIframeSrcdoc: false, #TODO?
    scripting: false,
    ctx: option(ParentNode(element)),
    openElementsInit: option(ParentNode(root)),
    formInit: option(ParentNode(form))
  )
  if element.namespaceURI == satNamespaceMathML and
      element.localName == satAnnotationXml:
    let encoding = element.attr(satEncoding)
    opts.ctxIsIntegrationPoint =
      encoding.equalsIgnoreCase("text/html") or
      encoding.equalsIgnoreCase("application/xhtml+xml")
  var parser = initHTML5Parser(builder, opts)
  let res = parser.parseChunk(s)
  # scripting is false and confidence is certain -> this must be continue
  assert res == pcrContinue
  parser.finish()
  builder.finish()
  return root.getChildList()

proc newHTML5ParserWrapper*(window: Window; url: URL;
    confidence: CharsetConfidence; charset: Charset): HTML5ParserWrapper =
  let opts = HTML5ParserOpts[ParentNode, CAtom](
    scripting: window.settings.scripting != smFalse
  )
  let builder = newChaDOMBuilder(url, window, confidence, charset)
  let wrapper = HTML5ParserWrapper(
    builder: builder,
    opts: opts,
    parser: initHTML5Parser(builder, opts)
  )
  builder.document.setActiveParser(wrapper)
  return wrapper

template toOpenArray(writeBuffer: DocumentWriteBuffer): openArray[char] =
  writeBuffer.data.toOpenArray(writeBuffer.i, writeBuffer.data.high)

proc addWriteBuffer(document: Document) =
  let buffer = DocumentWriteBuffer(prev: document.writeBuffersTop)
  document.writeBuffersTop = buffer

proc parseBuffer*(wrapper: HTML5ParserWrapper; buffer: openArray[char]):
    ParseChunkResult =
  let builder = wrapper.builder
  let document = builder.document
  var res = wrapper.parser.parseChunk(buffer)
  # set insertion point for when it's needed
  var ip = wrapper.parser.getInsertionPoint()
  while res == pcrScript:
    let script = builder.poppedScript
    if script != nil: # SVG script?
      builder.poppedScript = nil
      document.addWriteBuffer()
      script.prepare()
      while document.parserBlockingScript != nil:
        let script = document.parserBlockingScript
        document.parserBlockingScript = nil
        #TODO style sheet
        script.execute()
        assert document.parserBlockingScript != script
      if wrapper.stoppedFromScript:
        # document.write inserted a meta charset tag
        break
      assert document.writeBuffersTop.toOpenArray().len == 0
      document.writeBuffersTop = document.writeBuffersTop.prev
      assert document.writeBuffersTop == nil
      if ip == buffer.len:
        # script was at the end of the buffer; nothing to parse
        break
    # parse rest of input buffer
    res = wrapper.parser.parseChunk(buffer.toOpenArray(ip, buffer.high))
    ip += wrapper.parser.getInsertionPoint() # move insertion point
  return res

# Called from dom whenever document.write is executed.
# We consume everything pushed into the top buffer.
proc parseDocumentWriteChunk(wrapper: RootRef) =
  let wrapper = HTML5ParserWrapper(wrapper)
  let builder = wrapper.builder
  let document = builder.document
  let buffer = document.writeBuffersTop
  var res = wrapper.parser.parseChunk(buffer.toOpenArray())
  if res == pcrScript:
    document.addWriteBuffer()
    while true:
      buffer.i += wrapper.parser.getInsertionPoint()
      let script = builder.poppedScript
      if script != nil: # SVG script?
        builder.poppedScript = nil
        script.prepare()
        while document.parserBlockingScript != nil:
          let script = document.parserBlockingScript
          document.parserBlockingScript = nil
          #TODO style sheet
          script.execute()
          assert document.parserBlockingScript != script
      res = wrapper.parser.parseChunk(buffer.toOpenArray())
      if res != pcrScript:
        break
    assert document.writeBuffersTop.i == document.writeBuffersTop.data.len
    document.writeBuffersTop = document.writeBuffersTop.prev
  assert builder.poppedScript == nil
  buffer.i = buffer.data.len
  if res == pcrStop:
    wrapper.stoppedFromScript = true

proc finish*(wrapper: HTML5ParserWrapper) =
  wrapper.parser.finish()
  wrapper.builder.finish()

proc newDOMParser*(): DOMParser {.jsctor.} =
  return DOMParser()

proc parseFromString*(ctx: JSContext; parser: DOMParser; str, t: string):
    JSValue {.jsfunc.} =
  case t
  of "text/html":
    let window = ctx.getWindow()
    let url = if window.document != nil:
      window.document.url
    else:
      parseURL0("about:blank")
    let builder = newChaDOMBuilder(url, nil, ccIrrelevant)
    var parser = initHTML5Parser(builder, HTML5ParserOpts[ParentNode, CAtom]())
    let res = parser.parseChunk(str)
    assert res == pcrContinue
    parser.finish()
    builder.finish()
    return ctx.toJS(builder.document)
  of "text/xml", "application/xml", "application/xhtml+xml", "image/svg+xml":
    return JS_ThrowInternalError(ctx, "XML parsing is not supported yet")
  else:
    return JS_ThrowTypeError(ctx, "invalid mime type")

# Forward declaration hack
parseHTMLFragmentImpl = parseHTMLFragment
parseDocumentWriteChunkImpl = parseDocumentWriteChunk

proc addHTMLModule*(ctx: JSContext): JSClassID =
  return ctx.registerType(DOMParser)

{.pop.} # raises: []
