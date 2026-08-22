{.push raises: [].}

import std/algorithm

import chame/dombuilder
import chame/htmlparser
import chame/tags
import config/conftypes
import encoding/charset
import html/catom
import html/dom
import html/event
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsref
import monoucha/jstypes
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
    parser: HTML5Parser[ParentNode, CAtomTraced]
    builder*: ChaDOMBuilder
    opts: HTML5ParserOpts[ParentNode]
    stoppedFromScript: bool

  ChaDOMBuilder {.final.} = ref object of DOMBuilder[ParentNode, CAtomTraced]
    ctx: JSContext
    charset*: Charset
    confidence*: CharsetConfidence
    document*: Document
    poppedScript: HTMLScriptElement

  DOMBuilderImpl = ChaDOMBuilder
  HandleImpl = ParentNode
  AtomImpl = CAtomTraced

include chame/htmlparseriface

proc setActiveParser(document: Document; wrapper: HTML5ParserWrapper) =
  document.parser = wrapper

proc getDocumentImpl(builder: ChaDOMBuilder): ParentNode =
  return builder.document.asParentNode

proc atomToTagTypeImpl(builder: ChaDOMBuilder; atom: CAtomTraced): TagType =
  return atom.toTagType()

proc tagTypeToAtomImpl(builder: ChaDOMBuilder; tagType: TagType): CAtomTraced =
  return tagType.toStaticAtom().toAtomTrace()

proc namespaceToAtomImpl(builder: ChaDOMBuilder; ns: Namespace): CAtomTraced =
  return ns.toStaticAtom().toAtomTrace()

proc strToAtomImpl(builder: ChaDOMBuilder; s: string): CAtomTraced =
  return s.toAtomTrace()

proc finish(builder: ChaDOMBuilder) =
  let document = builder.document
  while document.scriptsToExecOnLoad != nil:
    #TODO spin event loop
    let script = document.scriptsToExecOnLoad
    script.execute()
    let next = script.next
    document.scriptsToExecOnLoad = next
    if next == nil:
      document.scriptsToExecOnLoadTail = HTMLScriptElement(nil)
  let window = document.window
  if document.scriptingEnabled:
    #TODO queue DOM task, then spin event loop
    window.fireEvent(satDOMContentLoaded, document.asEventTarget,
      bubbles = true, cancelable = false, trusted = true)
  #TODO ServiceWorkerContainer etc.
  document.setActiveParser(nil)

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
  return (handle as HTMLTemplateElement).content.asParentNode

proc getParentNodeImpl(builder: ChaDOMBuilder; handle: ParentNode):
    ParentNode =
  return handle.parentNode

proc getLocalNameImpl(builder: ChaDOMBuilder; handle: ParentNode):
    CAtomTraced =
  return (handle as Element).localName

proc getNamespaceImpl(builder: ChaDOMBuilder; handle: ParentNode): Namespace =
  return (handle as Element).namespaceURI.toNamespace()

proc createHTMLElementImpl(builder: ChaDOMBuilder): ParentNode =
  return builder.document.newHTMLElement(ttHtml).asParentNode

proc createElementForTokenImpl(builder: ChaDOMBuilder; localName: CAtomTraced;
    namespace: Namespace; intendedParent: ParentNode;
    attrs: sink seq[ParsedAttr[CAtomTraced]]): ParentNode =
  let document = builder.document
  let element = document.newElement(localName, namespace.toStaticAtom())
  element.sinkAttrs(move(attrs))
  element.resetElement(nil)
  if (let script = element as HTMLScriptElement; script != nil):
    script.parserDocument = document
    script.forceAsync = false
    # Note: per standard, we could set already started to true here when we
    # are parsing from document.write, but that sounds like a horrible idea.
  elif namespace == nsSVG and localName == satSvg:
    # hack to distinguish between parser-inserted SVG and dynamically added
    # SVG; TODO get rid of this
    let svg = (element as SVGSVGElement)
    svg.parserDocument = document
  element.asParentNode

proc insertBefore(builder: ChaDOMBuilder; parent: ParentNode; child: Node;
    before: ParentNode) =
  parent.insert(builder.ctx, child, before.asNode, suppressObservers = true)

proc insertCommentImpl(builder: ChaDOMBuilder; parent: ParentNode;
    text: string; before: ParentNode) =
  let comment = builder.document.createComment(text)
  builder.insertBefore(parent, comment.asNode, before)

proc appendDocumentTypeImpl(builder: ChaDOMBuilder;
    name, publicId, systemId: string) =
  let doctype = builder.document.newDocumentType(name, publicId, systemId)
  builder.insertBefore(builder.document.asParentNode, doctype.asNode,
    ParentNode(nil))

proc insertBeforeImpl(builder: ChaDOMBuilder; parent, child: ParentNode;
    before: ParentNode) =
  builder.insertBefore(parent, child.asNode, before)

proc insertTextImpl(builder: ChaDOMBuilder; parent: ParentNode; text: string;
    before: ParentNode) =
  let prevSibling = if before != nil:
    before.asNode.previousSibling
  else:
    parent.asNode.lastChild
  let prevText = prevSibling as Text
  if prevText != nil:
    prevText.data &= text
    let parent = parent as Element
    if parent != nil:
      parent.invalidate()
  else:
    let text = builder.document.newText(text)
    if text != nil:
      builder.insertBefore(parent, text.asNode, before)

proc removeImpl(builder: ChaDOMBuilder; child: ParentNode) =
  child.asNode.removeImpl(builder.ctx, suppressObservers = true)

proc moveChildrenImpl(builder: ChaDOMBuilder; fromNode, toNode: ParentNode) =
  let toMove = fromNode.getChildList()
  for node in toMove:
    node.removeImpl(builder.ctx, suppressObservers = true)
  for child in toMove:
    builder.insertBefore(toNode, child, ParentNode(nil))

proc sortAttrsImpl(builder: ChaDOMBuilder;
    attrs: var seq[ParsedAttr[CAtomTraced]]) =
  if attrs.len > 1:
    attrs.sort(proc(a, b: ParsedAttr[CAtomTraced]): int {.nimcall.} =
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
    attrs: seq[ParsedAttr[CAtomTraced]]) =
  let element = handle as Element
  element.addAttrsIfMissing(attrs)

proc setScriptAlreadyStartedImpl(builder: ChaDOMBuilder; script: ParentNode) =
  (script as HTMLScriptElement).alreadyStarted = true

proc associateWithFormImpl(builder: ChaDOMBuilder;
    element, form, intendedParent: ParentNode) =
  if form.asNode.inSameTree(intendedParent.asNode):
    let element = element as FormAssociatedElement
    if element != nil:
      element.setForm(form as HTMLFormElement)
      element.parserInserted = true

proc elementPoppedImpl(builder: ChaDOMBuilder; element: ParentNode) =
  let element = element as Element
  let document = builder.document
  if element.tagType == ttTextarea:
    element.resetElement(nil)
  elif (let script = element as HTMLScriptElement; script != nil):
    if document.scriptingEnabled:
      assert builder.poppedScript == nil
      inc document.throwOnDynamicMarkupInsertion
      #TODO I think this has to be moved for custom elements
      document.window.performMicrotaskCheckpoint()
      dec document.throwOnDynamicMarkupInsertion
    builder.poppedScript = script
  elif (let svg = element as SVGSVGElement; svg != nil):
    let window = document.window
    if window != nil:
      window.loadSVG(svg)
  elif (let style = element as HTMLStyleElement; style != nil):
    style.updateSheet()

proc newChaDOMBuilder(url: URL; window: Window; confidence: CharsetConfidence;
    ctx: JSContext; charset = DefaultCharset): ChaDOMBuilder =
  #TODO OOM
  let document = newDocument(url)
  document.charset = charset
  document.contentType = satTextHtml
  if window != nil:
    document.window = window
    window.document = document
  return ChaDOMBuilder(
    document: document,
    confidence: confidence,
    charset: charset,
    ctx: ctx #TODO dup context?
  )

# https://html.spec.whatwg.org/multipage/parsing.html#parsing-html-fragments
proc parseHTMLFragment(ctx: JSContext; element: Element; s: openArray[char]):
    seq[Node] =
  let url = parseURL0("about:blank")
  if url == nil:
    return @[]
  let builder = newChaDOMBuilder(url, Window(nil), ccIrrelevant, ctx)
  let document = builder.document
  document.mode = element.asNode.document.mode
  let root = document.newHTMLElement(ttHtml)
  if root == nil:
    return @[]
  document.asParentNode.append(ctx, root.asNode)
  let form = element.findAncestorIncl(ttForm)
  var opts = HTML5ParserOpts[ParentNode](
    isIframeSrcdoc: false, #TODO?
    scripting: false,
    ctx: element.asParentNode,
    openElementsInit: root.asParentNode,
    formInit: form.asParentNode
  )
  if element.namespaceURI == satNamespaceMathML and
      element.localName == satAnnotationXml:
    let encoding = element.attr(satEncoding)
    opts.ctxIsIntegrationPoint =
      encoding.equalsIgnoreCase("text/html") or
      encoding.equalsIgnoreCase("application/xhtml+xml")
  elif element.namespaceURI == satNamespaceSVG:
    let tagType = element.localName.toTagType()
    opts.ctxIsIntegrationPoint = tagType in {ttForeignObject, ttDesc, ttTitle}
  var parser = initHTML5Parser(builder, opts)
  let res = parser.parseChunk(s)
  # scripting is false and confidence is certain -> this must be continue
  assert res == pcrContinue
  parser.finish()
  builder.finish()
  return root.asParentNode.getChildList()

proc newHTML5ParserWrapper*(window: Window; url: URL;
    confidence: CharsetConfidence; charset: Charset): HTML5ParserWrapper =
  let opts = HTML5ParserOpts[ParentNode](
    scripting: window.settings.scripting != smFalse
  )
  let builder = newChaDOMBuilder(url, window, confidence, window.jsctx,
    charset)
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
      builder.poppedScript = HTMLScriptElement(nil)
      document.addWriteBuffer()
      script.prepare(builder.ctx)
      while document.parserBlockingScript != nil:
        let script = document.parserBlockingScript
        document.parserBlockingScript = HTMLScriptElement(nil)
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
        builder.poppedScript = HTMLScriptElement(nil)
        script.prepare(builder.ctx)
        while document.parserBlockingScript != nil:
          let script = document.parserBlockingScript
          document.parserBlockingScript = HTMLScriptElement(nil)
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

proc parseHTMLDocument*(ctx: JSContext; str: openArray[char]; url: URL):
    Document =
  let builder = newChaDOMBuilder(url, Window(nil), ccIrrelevant, ctx)
  var parser = initHTML5Parser(builder, HTML5ParserOpts[ParentNode]())
  let res = parser.parseChunk(str)
  assert res == pcrContinue
  parser.finish()
  builder.finish()
  return builder.document

jsClassRaw(DOMParserDef, "DOMParser"):
  type DOMParser = distinct pointer

  proc newDOMParser*(ctx: JSContext; ctor: JSValueConst): JSValue {.jsctor2.} =
    return JS_NewObjectFromCtor(ctx, ctor, classDef.id)

  type DOMParserSupportedType = enum
    dtHtml = "text/html"
    dtXml = "text/xml"
    dtXml2 = "application/xml"
    dtXml3 = "application/xhtml+xml"
    dtSvg = "image/svg+xml"

  proc parseFromString*(ctx: JSContext; parser: DOMParser; str: DOMString;
      t: DOMParserSupportedType): JSValue {.jsfunc.} =
    case t
    of dtHtml:
      let window = ctx.getWindow()
      let url = if window.document != nil:
        window.document.url
      else:
        parseURL0("about:blank")
      let document = ctx.parseHTMLDocument(str.toOpenArray(), url)
      return ctx.toJS(document)
    else:
      return JS_ThrowInternalError(ctx, "XML parsing is not supported yet")

# Forward declaration hack
parseHTMLFragmentImpl = parseHTMLFragment
parseDocumentWriteChunkImpl = parseDocumentWriteChunk

proc addHTMLModule*(ctx: JSContext): FromJSResult =
  ctx.registerClass(DOMParserDef)

{.pop.} # raises: []
