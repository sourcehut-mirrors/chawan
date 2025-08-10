{.push raises: [].}

import std/options
import std/tables

import chagashi/charset
import chame/htmlparser
import chame/tags
import config/conftypes
import html/catom
import html/dom
import html/enums
import monoucha/fromjs
import monoucha/javascript
import monoucha/jserror
import types/opt
import types/refstring
import types/url

export htmlparser.ParseResult

# DOMBuilder implementation for Chawan.

type CharsetConfidence* = enum
  ccTentative, ccCertain, ccIrrelevant

type
  HTML5ParserWrapper* = ref object of RootObj
    parser: HTML5Parser[Node, CAtom]
    builder*: ChaDOMBuilder
    opts: HTML5ParserOpts[Node, CAtom]
    stoppedFromScript: bool

  ChaDOMBuilder = ref object of DOMBuilder[Node, CAtom]
    charset*: Charset
    confidence*: CharsetConfidence
    document*: Document
    poppedScript: HTMLScriptElement

  DOMBuilderImpl = ChaDOMBuilder
  HandleImpl = Node
  AtomImpl = CAtom

include chame/htmlparseriface

type DOMParser = ref object # JS interface

jsDestructor(DOMParser)

proc setActiveParser(document: Document; wrapper: HTML5ParserWrapper) =
  document.parser = wrapper

proc getDocumentImpl(builder: ChaDOMBuilder): Node =
  return builder.document

proc atomToTagTypeImpl(builder: ChaDOMBuilder; atom: CAtom): TagType =
  return atom.toTagType()

proc tagTypeToAtomImpl(builder: ChaDOMBuilder; tagType: TagType): CAtom =
  return tagType.toAtom()

proc strToAtomImpl(builder: ChaDOMBuilder; s: string): CAtom =
  return s.toAtom()

proc finish(builder: ChaDOMBuilder) =
  while builder.document.scriptsToExecOnLoad != nil:
    #TODO spin event loop
    let script = builder.document.scriptsToExecOnLoad
    script.execute()
    let next = script.next
    builder.document.scriptsToExecOnLoad = next
    if next == nil:
      builder.document.scriptsToExecOnLoadTail = nil
  #TODO events

proc restart*(wrapper: HTML5ParserWrapper; charset: Charset) =
  let builder = wrapper.builder
  let document = newDocument()
  document.charset = charset
  document.setActiveParser(wrapper)
  document.contentType = "text/html"
  let oldDocument = builder.document
  document.url = oldDocument.url
  let window = oldDocument.window
  if window != nil:
    document.window = window
    window.document = document
  builder.document = document
  builder.charset = charset
  wrapper.parser = initHTML5Parser(builder, wrapper.opts)

proc setQuirksModeImpl(builder: ChaDOMBuilder; quirksMode: QuirksMode) =
  if not builder.document.parserCannotChangeModeFlag:
    builder.document.mode = quirksMode
    builder.document.applyQuirksSheet()

proc setEncodingImpl(builder: ChaDOMBuilder; encoding: string):
    SetEncodingResult =
  if builder.confidence != ccTentative:
    return SET_ENCODING_CONTINUE
  if builder.charset in {CHARSET_UTF_16_LE, CHARSET_UTF_16_BE}:
    builder.confidence = ccCertain
    return SET_ENCODING_CONTINUE
  let charset = getCharset(encoding)
  if charset == CHARSET_UNKNOWN:
    return SET_ENCODING_CONTINUE
  builder.confidence = ccCertain
  if charset == builder.charset:
    return SET_ENCODING_CONTINUE
  builder.charset = if charset == CHARSET_X_USER_DEFINED:
    CHARSET_WINDOWS_1252
  else:
    charset
  return SET_ENCODING_STOP

proc getTemplateContentImpl(builder: ChaDOMBuilder; handle: Node): Node =
  return HTMLTemplateElement(handle).content

proc getParentNodeImpl(builder: ChaDOMBuilder; handle: Node): Option[Node] =
  return option(handle.parentNode)

proc getLocalNameImpl(builder: ChaDOMBuilder; handle: Node): CAtom =
  return Element(handle).localName

proc getNamespaceImpl(builder: ChaDOMBuilder; handle: Node): Namespace =
  return Element(handle).namespaceURI.toNamespace()

proc createHTMLElementImpl(builder: ChaDOMBuilder): Node =
  return builder.document.newHTMLElement(TAG_HTML)

proc createElementForTokenImpl(builder: ChaDOMBuilder; localName: CAtom;
    namespace: Namespace; intendedParent: Node; htmlAttrs: Table[CAtom, string];
    xmlAttrs: seq[ParsedAttr[CAtom]]): Node =
  let document = builder.document
  let element = document.newElement(localName, namespace)
  for k, v in htmlAttrs:
    element.attr(k, v)
  for attr in xmlAttrs:
    element.attrns(attr.name, attr.prefix, attr.namespace, attr.value)
  if element.tagType in ResettableElements:
    element.resetElement()
  if element of HTMLScriptElement:
    let script = HTMLScriptElement(element)
    script.parserDocument = document
    script.forceAsync = false
    # Note: per standard, we could set already started to true here when we
    # are parsing from document.write, but that sounds like a horrible idea.
  return element

proc createCommentImpl(builder: ChaDOMBuilder; text: string): Node =
  return builder.document.createComment(text)

proc createDocumentTypeImpl(builder: ChaDOMBuilder; name, publicId,
    systemId: string): Node =
  return builder.document.newDocumentType(name, publicId, systemId)

proc insertBeforeImpl(builder: ChaDOMBuilder; parent, child: Node;
    before: Option[Node]) =
  discard parent.insertBefore(child, before)

proc insertTextImpl(builder: ChaDOMBuilder; parent: Node; text: string;
    before: Option[Node]) =
  let prevSibling = if before.isSome:
    before.get.previousSibling
  else:
    parent.lastChild
  if prevSibling != nil and prevSibling of Text:
    Text(prevSibling).data &= text
    if parent of Element:
      Element(parent).invalidate()
  else:
    let text = builder.document.newText(text)
    discard parent.insertBefore(text, before)

proc removeImpl(builder: ChaDOMBuilder; child: Node) =
  if child.parentNode != nil:
    child.remove(suppressObservers = true)

proc moveChildrenImpl(builder: ChaDOMBuilder; fromNode, toNode: Node) =
  let toMove = fromNode.getChildList()
  for node in toMove:
    node.remove(suppressObservers = true)
  for child in toMove:
    toNode.insert(child, nil)

proc addAttrsIfMissingImpl(builder: ChaDOMBuilder; handle: Node;
    attrs: Table[CAtom, string]) =
  let element = Element(handle)
  for k, v in attrs:
    if not element.attrb(k):
      element.attr(k, v)

proc setScriptAlreadyStartedImpl(builder: ChaDOMBuilder; script: Node) =
  HTMLScriptElement(script).alreadyStarted = true

proc associateWithFormImpl(builder: ChaDOMBuilder;
    element, form, intendedParent: Node) =
  if form.inSameTree(intendedParent):
    #TODO remove following test eventually
    if element of FormAssociatedElement:
      let element = FormAssociatedElement(element)
      element.setForm(HTMLFormElement(form))
      element.parserInserted = true

proc elementPoppedImpl(builder: ChaDOMBuilder; element: Node) =
  let element = Element(element)
  let document = builder.document
  if element of HTMLTextAreaElement:
    element.resetElement()
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
      window.loadResource(svg)
  elif element of HTMLStyleElement:
    HTMLStyleElement(element).updateSheet()

proc newChaDOMBuilder(url: URL; window: Window; confidence: CharsetConfidence;
    charset = DefaultCharset): ChaDOMBuilder =
  let document = newDocument()
  document.charset = charset
  document.contentType = "text/html"
  document.url = url
  if window != nil:
    document.window = window
    window.document = document
  return ChaDOMBuilder(
    document: document,
    confidence: confidence,
    charset: charset
  )

# https://html.spec.whatwg.org/multipage/parsing.html#parsing-html-fragments
proc parseHTMLFragment*(element: Element; s: string): seq[Node] =
  let url = parseURL("about:blank").get
  let builder = newChaDOMBuilder(url, nil, ccIrrelevant)
  let document = builder.document
  document.mode = element.document.mode
  let state = case element.tagType
  of TAG_TITLE, TAG_TEXTAREA: RCDATA
  of TAG_STYLE, TAG_XMP, TAG_IFRAME, TAG_NOEMBED, TAG_NOFRAMES: RAWTEXT
  of TAG_SCRIPT: SCRIPT_DATA
  of TAG_NOSCRIPT:
    if element.document != nil and element.document.scriptingEnabled:
      RAWTEXT
    else:
      DATA
  of TAG_PLAINTEXT:
    PLAINTEXT
  else: DATA
  let root = document.newHTMLElement(TAG_HTML)
  document.append(root)
  let opts = HTML5ParserOpts[Node, CAtom](
    isIframeSrcdoc: false, #TODO?
    scripting: false,
    ctx: some((Node(element), element.localName)),
    initialTokenizerState: state,
    openElementsInit: @[(Node(root), root.localName)],
    pushInTemplate: element.tagType == TAG_TEMPLATE
  )
  var parser = initHTML5Parser(builder, opts)
  let res = parser.parseChunk(s.toOpenArray(0, s.high))
  # scripting is false and confidence is certain -> this must be continue
  assert res == PRES_CONTINUE
  parser.finish()
  builder.finish()
  return root.getChildList()

proc newHTML5ParserWrapper*(window: Window; url: URL;
    confidence: CharsetConfidence; charset: Charset): HTML5ParserWrapper =
  let opts = HTML5ParserOpts[Node, CAtom](
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

template toOA(writeBuffer: DocumentWriteBuffer): openArray[char] =
  writeBuffer.data.toOpenArray(writeBuffer.i, writeBuffer.data.high)

proc parseBuffer*(wrapper: HTML5ParserWrapper; buffer: openArray[char]):
    ParseResult =
  let builder = wrapper.builder
  let document = builder.document
  var res = wrapper.parser.parseChunk(buffer)
  # set insertion point for when it's needed
  var ip = wrapper.parser.getInsertionPoint()
  while res == PRES_SCRIPT:
    let script = builder.poppedScript
    builder.poppedScript = nil
    document.writeBuffers.add(DocumentWriteBuffer())
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
    assert document.writeBuffers[^1].toOA().len == 0
    discard document.writeBuffers.pop()
    assert document.writeBuffers.len == 0
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
  let buffer = document.writeBuffers[^1]
  var res = wrapper.parser.parseChunk(buffer.toOA())
  if res == PRES_SCRIPT:
    document.writeBuffers.add(DocumentWriteBuffer())
    while true:
      buffer.i += wrapper.parser.getInsertionPoint()
      let script = builder.poppedScript
      builder.poppedScript = nil
      script.prepare()
      while document.parserBlockingScript != nil:
        let script = document.parserBlockingScript
        document.parserBlockingScript = nil
        #TODO style sheet
        script.execute()
        assert document.parserBlockingScript != script
      res = wrapper.parser.parseChunk(buffer.toOA())
      if res != PRES_SCRIPT:
        break
    assert document.writeBuffers[^1].i == document.writeBuffers[^1].data.len
    discard document.writeBuffers.pop()
  assert builder.poppedScript == nil
  buffer.i = buffer.data.len
  if res == PRES_STOP:
    wrapper.stoppedFromScript = true

proc finish*(wrapper: HTML5ParserWrapper) =
  wrapper.parser.finish()
  wrapper.builder.finish()

proc newDOMParser*(): DOMParser {.jsctor.} =
  return DOMParser()

proc parseFromString*(ctx: JSContext; parser: DOMParser; str, t: string):
    JSResult[Document] {.jsfunc.} =
  case t
  of "text/html":
    let window = ctx.getWindow()
    let url = if window.document != nil:
      window.document.url
    else:
      newURL("about:blank").get
    let builder = newChaDOMBuilder(url, window, ccIrrelevant)
    var parser = initHTML5Parser(builder, HTML5ParserOpts[Node, CAtom]())
    let res = parser.parseChunk(str)
    assert res == PRES_CONTINUE
    parser.finish()
    builder.finish()
    return ok(builder.document)
  of "text/xml", "application/xml", "application/xhtml+xml", "image/svg+xml":
    return errInternalError("XML parsing is not supported yet")
  else:
    return errTypeError("Invalid mime type")

# Forward declaration hack
parseHTMLFragmentImpl = parseHTMLFragment
parseDocumentWriteChunkImpl = parseDocumentWriteChunk

proc addHTMLModule*(ctx: JSContext) =
  ctx.registerType(DOMParser)

{.pop.} # raises: []
