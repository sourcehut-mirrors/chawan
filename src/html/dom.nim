{.push raises: [].}

import std/algorithm
import std/hashes
import std/options
import std/posix
import std/sets
import std/strutils
import std/tables
import std/times

import chagashi/charset
import chagashi/decoder
import chame/tags
import config/conftypes
import config/mimetypes
import css/cssparser
import css/cssvalues
import css/mediaquery
import css/sheet
import html/catom
import html/domcanvas
import html/domexception
import html/enums
import html/event
import html/performance
import html/script
import io/console
import io/dynstream
import io/promise
import io/timeout
import monoucha/fromjs
import monoucha/javascript
import monoucha/jserror
import monoucha/jsopaque
import monoucha/jspropenumlist
import monoucha/jsutils
import monoucha/quickjs
import monoucha/tojs
import server/headers
import server/loaderiface
import server/request
import server/response
import types/bitmap
import types/blob
import types/color
import types/opt
import types/path
import types/referrer
import types/refstring
import types/url
import types/winattrs
import utils/strwidth
import utils/twtstr

type
  FormMethod* = enum
    fmGet = "get"
    fmPost = "post"
    fmDialog = "dialog"

  FormEncodingType* = enum
    fetUrlencoded = "application/x-www-form-urlencoded",
    fetMultipart = "multipart/form-data",
    fetTextPlain = "text/plain"

  DocumentReadyState* = enum
    rsLoading = "loading"
    rsInteractive = "interactive"
    rsComplete = "complete"

type
  DependencyType* = enum
    dtHover, dtChecked, dtFocus, dtTarget

  DependencyMap = object
    dependsOn: Table[Element, seq[Element]]
    dependedBy: Table[Element, seq[Element]]

  DependencyInfo* = array[DependencyType, seq[Element]]

  Location = ref object
    window: Window

  CachedURLImage = ref object
    expiry: int64
    loading: bool
    shared: seq[HTMLImageElement]
    bmp: NetworkBitmap

  WindowWeakMap* = enum
    wwmChildren, wwmChildNodes, wwmSelectedOptions, wwmTBodies, wwmCells,
    wwmDatalist, wwmAttributes

  Window* = ref object of EventTarget
    internalConsole*: Console
    navigator* {.jsget.}: Navigator
    screen* {.jsget.}: Screen
    history* {.jsget.}: History
    localStorage* {.jsget.}: Storage
    sessionStorage* {.jsget.}: Storage
    crypto* {.jsget.}: Crypto
    settings*: EnvironmentSettings
    loader*: FileLoader
    location* {.jsget.}: Location
    jsrt*: JSRuntime
    jsctx*: JSContext
    document* {.jsufget.}: Document
    timeouts*: TimeoutState
    navigate*: proc(url: URL)
    importMapsAllowed*: bool
    inMicrotaskCheckpoint: bool
    pendingResources*: seq[EmptyPromise]
    pendingImages*: seq[EmptyPromise]
    imageURLCache: Table[string, CachedURLImage]
    svgCache*: Table[string, SVGSVGElement]
    # ID of the next image
    imageId: int
    # list of streams that must be closed for canvas rendering on load
    pendingCanvasCtls*: seq[CanvasRenderingContext2D]
    imageTypes*: Table[string, string]
    userAgent*: string
    referrer* {.jsget.}: string
    maybeRestyle*: proc(element: Element)
    performance* {.jsget.}: Performance
    currentModuleURL*: URL
    jsStore*: seq[JSValue]
    jsStoreFree*: int
    weakMap*: array[WindowWeakMap, JSValue]

  # Navigator stuff
  Navigator* = object
    plugins: PluginArray

  PluginArray* = object

  MimeTypeArray* = object

  Screen* = object

  History* = object

  Storage* = object
    map*: seq[tuple[key, value: string]]

  Crypto* = object
    urandom*: PosixStream

  NamedNodeMap = ref object
    element: Element
    attrlist: seq[Attr]

  NodeFilterType = enum
    nftAccept = (1, "FILTER_ACCEPT")
    nftReject = (2, "FILTER_REJECT")
    nftSkip = (3, "FILTER_SKIP")

  NodeFilterNode = enum
    SHOW_ELEMENT = 0
    SHOW_ATTRIBUTE = 1
    SHOW_TEXT = 2
    SHOW_CDATA_SECTION = 3
    SHOW_ENTITY_REFERENCE = 4
    SHOW_ENTITY = 5
    SHOW_PROCESSING_INSTRUCTION = 6
    SHOW_COMMENT = 7
    SHOW_DOCUMENT = 8
    SHOW_DOCUMENT_TYPE = 9
    SHOW_DOCUMENT_FRAGMENT = 10
    SHOW_NOTATION = 11

  CollectionMatchFun = proc(node: Node): bool {.noSideEffect, raises: [].}

  Collection = ref object of RootObj
    islive: bool
    childonly: bool
    invalid: bool
    inclusive: bool
    root: Node
    match: CollectionMatchFun
    snapshot: seq[Node]

  NodeIterator = ref object of Collection
    ctx: JSContext
    filter: JSValue
    u: uint32

  NodeList = ref object of Collection

  HTMLCollection = ref object of Collection

  HTMLFormControlsCollection = ref object of HTMLCollection

  HTMLOptionsCollection = ref object of HTMLCollection

  RadioNodeList = ref object of NodeList

  HTMLAllCollection = ref object of Collection

  DOMTokenList = ref object
    toks: seq[CAtom]
    element: Element
    localName: CAtom

  DOMStringMap = ref object
    target: HTMLElement

  # Nodes are organized as doubly linked lists, which normally have
  # two unused pointers (prev of head, next of tail).  We exploit this
  # property to elide two other pointers as follows:
  # * The tail of the child linked list is stored as the prev pointer of
  #   the first child.
  # * The owner document is stored as the next pointer of the last
  #   child.  (However, a Document has no owner document, so its
  #   internalNext is always nil.)
  Node* = ref object of EventTarget
    parentNode* {.jsget.}: Node
    firstChild* {.jsget.}: Node
    internalNext: Node # either nextSibling or ownerDocument
    internalPrev: Node # either previousSibling or parentNode.lastChild

  Attr* = ref object of Node
    dataIdx: int
    ownerElement*: Element

  DOMImplementation = object
    document: Document

  DOMRect = ref object
    x {.jsgetset.}: float64
    y {.jsgetset.}: float64
    width {.jsgetset.}: float64
    height {.jsgetset.}: float64

  DocumentWriteBuffer* = ref object
    data*: string
    i*: int

  Document* = ref object of Node
    activeParserWasAborted: bool
    invalid*: bool # whether the document must be rendered again
    charset*: Charset
    mode*: QuirksMode
    readyState* {.jsget.}: DocumentReadyState
    contentType* {.jsget.}: StaticAtom
    window* {.jsget: "defaultView".}: Window
    url*: URL # not nil
    currentScript {.jsget.}: HTMLScriptElement
    implementation {.jsget.}: DOMImplementation
    origin: Origin
    # document.write
    ignoreDestructiveWrites: int
    throwOnDynamicMarkupInsertion*: int
    writeBuffers*: seq[DocumentWriteBuffer]
    styleDependencies: array[DependencyType, DependencyMap]
    scriptsToExecSoon: HTMLScriptElement
    scriptsToExecInOrder: HTMLScriptElement
    scriptsToExecInOrderTail: HTMLScriptElement
    scriptsToExecOnLoad*: HTMLScriptElement
    scriptsToExecOnLoadTail*: HTMLScriptElement
    parserBlockingScript*: HTMLScriptElement
    internalFocus: Element
    internalTarget: Element
    renderBlockingElements: seq[Element]
    uaSheets*: seq[CSSStylesheet]
    userSheet*: CSSStylesheet
    authorSheets*: seq[CSSStylesheet]
    cachedForms: HTMLCollection
    cachedLinks: HTMLCollection
    parser*: RootRef
    internalCookie: string
    liveCollections: seq[pointer]
    cachedAll: HTMLAllCollection

  XMLDocument = ref object of Document

  CharacterData* = ref object of Node
    data* {.jsgetset.}: RefString

  Text* = ref object of CharacterData

  Comment* = ref object of CharacterData

  CDATASection = ref object of CharacterData

  ProcessingInstruction = ref object of CharacterData
    target {.jsget.}: string

  DocumentFragment* = ref object of Node
    host*: Element

  DocumentType* = ref object of Node
    name* {.jsget.}: string
    publicId* {.jsget.}: string
    systemId* {.jsget.}: string

  AttrData* = object
    qualifiedName*: CAtom
    localName*: CAtom
    prefix*: CAtom
    namespace*: CAtom
    value*: string

  Element* = ref object of Node
    namespaceURI* {.jsget.}: CAtom
    prefix {.jsget.}: CAtom
    internalHover: bool
    childElIndicesInvalid: bool
    selfDepends: set[DependencyType]
    localName* {.jsget.}: CAtom
    id* {.jsget.}: CAtom
    name: CAtom
    internalElIndex: int
    classList* {.jsget.}: DOMTokenList
    attrs*: seq[AttrData] # sorted by int(qualifiedName)
    cachedStyle*: CSSStyleDeclaration
    computed*: CSSValues

  AttrDummyElement = ref object of Element

  CSSStyleDeclaration* = ref object
    computed: bool
    readonly: bool
    decls*: seq[CSSDeclaration]
    element: Element

  HTMLElement* = ref object of Element

  SVGElement = ref object of Element

  SVGSVGElement* = ref object of SVGElement
    bitmap*: NetworkBitmap
    shared: seq[SVGSVGElement] # elements that serialize to the same string
    fetchStarted: bool

  FormAssociatedElement* = ref object of HTMLElement
    form*: HTMLFormElement
    parserInserted*: bool

  HTMLInputElement* = ref object of FormAssociatedElement
    inputType* {.jsget: "type".}: InputType
    internalValue: RefString
    internalChecked {.jsget: "checked".}: bool
    files* {.jsget.}: seq[WebFile]
    xcoord*: int
    ycoord*: int

  HTMLAnchorElement* = ref object of HTMLElement
    relList {.jsget.}: DOMTokenList

  HTMLSelectElement* = ref object of FormAssociatedElement
    userValidity: bool
    cachedOptions: HTMLOptionsCollection

  HTMLSpanElement* = ref object of HTMLElement

  HTMLOptGroupElement* = ref object of HTMLElement

  HTMLOptionElement* = ref object of HTMLElement
    selected* {.jsget.}: bool
    dirty: bool

  HTMLHeadingElement* = ref object of HTMLElement

  HTMLBRElement* = ref object of HTMLElement

  HTMLMenuElement* = ref object of HTMLElement

  HTMLUListElement* = ref object of HTMLElement

  HTMLOListElement* = ref object of HTMLElement

  HTMLLIElement* = ref object of HTMLElement
    value* {.jsget.}: Option[int32]

  HTMLStyleElement* = ref object of HTMLElement
    sheet*: CSSStylesheet

  HTMLLinkElement* = ref object of HTMLElement
    sheets: seq[CSSStylesheet]
    relList {.jsget.}: DOMTokenList
    fetchStarted: bool
    enabled: Option[bool]

  HTMLFormElement* = ref object of HTMLElement
    constructingEntryList*: bool
    controls*: seq[FormAssociatedElement]
    cachedElements: HTMLFormControlsCollection
    relList {.jsget.}: DOMTokenList

  HTMLTemplateElement* = ref object of HTMLElement
    content* {.jsget.}: DocumentFragment

  HTMLUnknownElement* = ref object of HTMLElement

  HTMLScriptElement* = ref object of HTMLElement
    parserDocument*: Document
    preparationTimeDocument*: Document
    forceAsync*: bool
    external*: bool
    readyForParserExec*: bool
    alreadyStarted*: bool
    delayingTheLoadEvent: bool
    ctype: ScriptType
    internalNonce: string
    scriptResult*: ScriptResult
    onReady: (proc(element: HTMLScriptElement) {.nimcall, raises: [].})
    next*: HTMLScriptElement # scriptsToExecSoon/InOrder/OnLoad

  OnCompleteProc = proc(element: HTMLScriptElement, res: ScriptResult)

  HTMLBaseElement* = ref object of HTMLElement

  HTMLAreaElement* = ref object of HTMLElement
    relList {.jsget.}: DOMTokenList

  HTMLButtonElement* = ref object of FormAssociatedElement
    ctype* {.jsget: "type".}: ButtonType

  HTMLTextAreaElement* = ref object of FormAssociatedElement
    dirty: bool
    internalValue: string

  HTMLLabelElement* = ref object of HTMLElement

  HTMLCanvasElement* = ref object of HTMLElement
    ctx2d*: CanvasRenderingContext2D
    bitmap*: NetworkBitmap

  HTMLImageElement* = ref object of HTMLElement
    bitmap*: NetworkBitmap
    fetchStarted: bool

  HTMLVideoElement* = ref object of HTMLElement

  HTMLAudioElement* = ref object of HTMLElement

  HTMLIFrameElement* = ref object of HTMLElement

  HTMLTableElement = ref object of HTMLElement
    cachedRows: HTMLCollection

  HTMLTableCaptionElement = ref object of HTMLElement

  HTMLTableSectionElement = ref object of HTMLElement
    cachedRows: HTMLCollection

  HTMLTableRowElement = ref object of HTMLElement

  HTMLMetaElement = ref object of HTMLElement

  HTMLDetailsElement = ref object of HTMLElement

  HTMLFrameElement = ref object of HTMLElement

  HTMLTimeElement = ref object of HTMLElement

  HTMLQuoteElement = ref object of HTMLElement

  HTMLDataElement = ref object of HTMLElement

  HTMLHeadElement = ref object of HTMLElement

  HTMLTitleElement = ref object of HTMLElement

jsDestructor(Navigator)
jsDestructor(PluginArray)
jsDestructor(MimeTypeArray)
jsDestructor(Screen)
jsDestructor(History)
jsDestructor(Storage)
jsDestructor(Crypto)

jsDestructor(Element)
jsDestructor(HTMLElement)
jsDestructor(HTMLInputElement)
jsDestructor(HTMLAnchorElement)
jsDestructor(HTMLSelectElement)
jsDestructor(HTMLSpanElement)
jsDestructor(HTMLOptGroupElement)
jsDestructor(HTMLOptionElement)
jsDestructor(HTMLHeadingElement)
jsDestructor(HTMLBRElement)
jsDestructor(HTMLMenuElement)
jsDestructor(HTMLUListElement)
jsDestructor(HTMLOListElement)
jsDestructor(HTMLLIElement)
jsDestructor(HTMLStyleElement)
jsDestructor(HTMLLinkElement)
jsDestructor(HTMLFormElement)
jsDestructor(HTMLTemplateElement)
jsDestructor(HTMLUnknownElement)
jsDestructor(HTMLScriptElement)
jsDestructor(HTMLBaseElement)
jsDestructor(HTMLAreaElement)
jsDestructor(HTMLButtonElement)
jsDestructor(HTMLTextAreaElement)
jsDestructor(HTMLLabelElement)
jsDestructor(HTMLCanvasElement)
jsDestructor(HTMLImageElement)
jsDestructor(HTMLVideoElement)
jsDestructor(HTMLAudioElement)
jsDestructor(HTMLIFrameElement)
jsDestructor(HTMLTableElement)
jsDestructor(HTMLTableCaptionElement)
jsDestructor(HTMLTableRowElement)
jsDestructor(HTMLTableSectionElement)
jsDestructor(HTMLMetaElement)
jsDestructor(HTMLDetailsElement)
jsDestructor(HTMLFrameElement)
jsDestructor(HTMLTimeElement)
jsDestructor(HTMLQuoteElement)
jsDestructor(HTMLDataElement)
jsDestructor(HTMLHeadElement)
jsDestructor(HTMLTitleElement)
jsDestructor(SVGElement)
jsDestructor(SVGSVGElement)
jsDestructor(Node)
jsDestructor(NodeList)
jsDestructor(HTMLCollection)
jsDestructor(HTMLFormControlsCollection)
jsDestructor(RadioNodeList)
jsDestructor(HTMLAllCollection)
jsDestructor(HTMLOptionsCollection)
jsDestructor(NodeIterator)
jsDestructor(Location)
jsDestructor(Document)
jsDestructor(XMLDocument)
jsDestructor(DOMImplementation)
jsDestructor(DOMTokenList)
jsDestructor(DOMStringMap)
jsDestructor(Comment)
jsDestructor(CDATASection)
jsDestructor(DocumentFragment)
jsDestructor(ProcessingInstruction)
jsDestructor(CharacterData)
jsDestructor(Text)
jsDestructor(DocumentType)
jsDestructor(Attr)
jsDestructor(NamedNodeMap)
jsDestructor(CSSStyleDeclaration)
jsDestructor(DOMRect)

# Forward declarations
func newCDATASection(document: Document; data: string): CDATASection
func newComment(document: Document; data: sink string): Comment
func newText*(document: Document; data: sink string): Text
func newText(ctx: JSContext; data: sink string = ""): Text
proc newDocument*(): Document
func newDocumentType*(document: Document;
  name, publicId, systemId: sink string): DocumentType
func newDocumentFragment(document: Document): DocumentFragment
func newProcessingInstruction(document: Document; target: string;
  data: sink string): ProcessingInstruction
proc newElement*(document: Document; localName: CAtom;
  namespace = Namespace.HTML; prefix = NO_PREFIX): Element
proc newElement*(document: Document; localName, namespaceURI, prefix: CAtom):
  Element
proc newHTMLElement*(document: Document; tagType: TagType): HTMLElement
func newHTMLCollection(root: Node; match: CollectionMatchFun;
  islive, childonly: bool): HTMLCollection
func newNodeList(root: Node; match: CollectionMatchFun;
  islive, childonly: bool): NodeList
proc newDOMTokenList(element: Element; name: StaticAtom): DOMTokenList
proc newCSSStyleDeclaration(element: Element; value: string; computed = false;
  readonly = false): CSSStyleDeclaration

proc getImageId(window: Window): int
proc loadResource(window: Window; link: HTMLLinkElement)
proc loadResource*(window: Window; image: HTMLImageElement)
proc logException(window: Window; url: URL)

proc adopt(document: Document; node: Node)
proc applyAuthorSheets*(document: Document)
proc applyStyleDependencies*(element: Element; depends: DependencyInfo)
proc baseURL*(document: Document): URL
func documentElement*(document: Document): Element
proc invalidateCollections(document: Document)
proc parseURL0*(document: Document; s: string): URL
proc parseURL*(document: Document; s: string): Opt[URL]
proc reflectEvent(document: Document; target: EventTarget;
  name, ctype: StaticAtom; value: string; target2 = none(EventTarget))

func document*(node: Node): Document
proc insertBefore*(parent, node: Node; before: Option[Node]): DOMResult[Node]
func parentElement*(node: Node): Element
proc remove*(node: Node)
proc replace*(parent, child, node: Node): Err[DOMException]
proc replaceAll(parent: Node; s: sink string)
func serializeFragment(res: var string; node: Node)
func serializeFragmentInner(res: var string; child: Node; parentType: TagType)

func containsIgnoreCase(tokenList: DOMTokenList; a: StaticAtom): bool

func data(attr: Attr): lent AttrData
proc setValue(attr: Attr; s: string)

proc attr*(element: Element; name: CAtom; value: sink string)
proc attr*(element: Element; name: StaticAtom; value: sink string)
func attr*(element: Element; s: StaticAtom): lent string
func attrb*(element: Element; s: CAtom): bool
func attrb*(element: Element; at: StaticAtom): bool
func attrl*(element: Element; s: StaticAtom): Opt[int32]
func attrul*(element: Element; s: StaticAtom): Opt[uint32]
func attrulgz*(element: Element; s: StaticAtom): Opt[uint32]
proc attrl(element: Element; name: StaticAtom; value: int32)
proc attrul(element: Element; name: StaticAtom; value: uint32)
proc attrulgz(element: Element; name: StaticAtom; value: uint32)
proc delAttr(ctx: JSContext; element: Element; i: int)
proc elementInsertionSteps(element: Element): bool
proc elIndex*(this: Element): int
func findAttr(element: Element; qualifiedName: CAtom): int
func findAttrNS(element: Element; namespace, localName: CAtom): int
proc getComputedStyle*(element: Element; pseudo: PseudoElement): CSSValues
proc invalidate*(element: Element)
proc invalidate*(element: Element; dep: DependencyType)
func outerHTML(element: Element): string
proc postConnectionSteps(element: Element)
func previousElementSibling*(element: Element): Element
proc reflectAttr(element: Element; name: CAtom; value: Option[string])
func scriptingEnabled(element: Element): bool
func tagName(element: Element): string
func tagType*(element: Element; namespace = satNamespaceHTML): TagType

proc resetFormOwner(element: FormAssociatedElement)
func checked*(input: HTMLInputElement): bool {.inline.}
proc setChecked*(input: HTMLInputElement; b: bool)
func value*(this: HTMLInputElement): lent string
proc setValue*(this: HTMLInputElement; value: sink string)
func value*(option: HTMLOptionElement): string
proc setSelectedness(select: HTMLSelectElement)
proc updateSheet*(this: HTMLStyleElement)
proc execute*(element: HTMLScriptElement)
proc prepare*(element: HTMLScriptElement)
proc fetchDescendantsAndLink(element: HTMLScriptElement; script: Script;
  destination: RequestDestination; onComplete: OnCompleteProc)
proc fetchSingleModule(element: HTMLScriptElement; url: URL;
  destination: RequestDestination; options: ScriptOptions; referrer: URL;
  isTopLevel: bool; onComplete: OnCompleteProc)

# Forward declaration hacks
# set in css/match
var matchesImpl*: proc(element: Element; cxsels: seq[ComplexSelector]): bool
  {.nimcall, raises: [].}
# set in html/chadombuilder
var parseHTMLFragmentImpl*: proc(element: Element; s: string): seq[Node]
  {.nimcall, raises: [].}
var parseDocumentWriteChunkImpl*: proc(wrapper: RootRef) {.nimcall, raises: [].}
# set in html/env
var fetchImpl*: proc(window: Window; input: JSRequest): JSResult[FetchPromise]
  {.nimcall, raises: [].}

# Reflected attributes.
type
  ReflectType = enum
    rtStr, rtBool, rtLong, rtUlongGz, rtUlong, rtFunction

  ReflectEntry = object
    attrname: StaticAtom
    funcname: StaticAtom
    tags: set[TagType]
    case t: ReflectType
    of rtLong:
      i: int32
    of rtUlong, rtUlongGz:
      u: uint32
    of rtFunction:
      ctype: StaticAtom
    else: discard

template toset(ts: openArray[TagType]): set[TagType] =
  var tags: system.set[TagType] = {}
  for tag in ts:
    tags.incl(tag)
  tags

func makes(name: StaticAtom; ts: set[TagType]): ReflectEntry =
  ReflectEntry(
    attrname: name,
    funcname: name,
    t: rtStr,
    tags: ts
  )

func makes(attrname, funcname: StaticAtom; ts: set[TagType]): ReflectEntry =
  ReflectEntry(
    attrname: attrname,
    funcname: funcname,
    t: rtStr,
    tags: ts
  )

func makes(name: StaticAtom; ts: varargs[TagType]): ReflectEntry =
  makes(name, toset(ts))

func makes(attrname, funcname: StaticAtom; ts: varargs[TagType]): ReflectEntry =
  makes(attrname, funcname, toset(ts))

func makeb(attrname, funcname: StaticAtom; ts: varargs[TagType]): ReflectEntry =
  ReflectEntry(
    attrname: attrname,
    funcname: funcname,
    t: rtBool,
    tags: toset(ts)
  )

func makeb(name: StaticAtom; ts: varargs[TagType]): ReflectEntry =
  makeb(name, name, ts)

func makeul(name: StaticAtom; ts: varargs[TagType]; default = 0u32):
    ReflectEntry =
  ReflectEntry(
    attrname: name,
    funcname: name,
    t: rtUlong,
    tags: toset(ts),
    u: default
  )

func makeulgz(name: StaticAtom; ts: varargs[TagType]; default = 0u32):
    ReflectEntry =
  ReflectEntry(
    attrname: name,
    funcname: name,
    t: rtUlongGz,
    tags: toset(ts),
    u: default
  )

func makef(name, ctype: StaticAtom): ReflectEntry =
  ReflectEntry(
    attrname: name,
    funcname: name,
    t: rtFunction,
    tags: AllTagTypes,
    ctype: ctype
  )

# Note: this table only works for tag types with a registered interface.
const ReflectTable0 = [
  # non-global attributes
  makes(satTarget, TAG_A, TAG_AREA, TAG_LABEL, TAG_LINK),
  makes(satHref, TAG_LINK),
  makes(satValue, TAG_BUTTON, TAG_DATA),
  makeb(satRequired, TAG_INPUT, TAG_SELECT, TAG_TEXTAREA),
  makes(satName, TAG_A, TAG_INPUT, TAG_SELECT, TAG_TEXTAREA, TAG_META,
    TAG_IFRAME, TAG_FRAME, TAG_IMG, TAG_OBJECT, TAG_PARAM, TAG_OBJECT, TAG_MAP,
    TAG_FORM, TAG_OUTPUT, TAG_FIELDSET, TAG_DETAILS),
  makes(satOpen, TAG_DETAILS),
  makeb(satNovalidate, satHNoValidate, TAG_FORM),
  makeb(satSelected, satDefaultSelected, TAG_OPTION),
  makes(satRel, TAG_A, TAG_LINK, TAG_LABEL),
  makes(satFor, satHtmlFor, TAG_LABEL),
  makes(satHttpEquiv, satHHttpEquiv, TAG_META),
  makes(satContent, TAG_META),
  makes(satMedia, TAG_META),
  makes(satDatetime, satHDateTime, TAG_TIME),
  makeul(satCols, TAG_TEXTAREA, 20u32),
  makeul(satRows, TAG_TEXTAREA, 1u32),
# > For historical reasons, the default value of the size IDL attribute
# > does not return the actual size used, which, in the absence of the
# > size content attribute, is either 1 or 4 depending on the presence
# > of the multiple attribute.
  makeulgz(satSize, TAG_SELECT, 0u32),
  makeulgz(satSize, TAG_INPUT, 20u32),
  makeul(satWidth, TAG_CANVAS, 300u32),
  makeul(satHeight, TAG_CANVAS, 150u32),
  makes(satAlt, TAG_IMG),
  makes(satSrc, TAG_IMG, TAG_SCRIPT, TAG_IFRAME, TAG_FRAME, TAG_INPUT),
  makes(satSrcset, TAG_IMG),
  makes(satSizes, TAG_IMG),
  #TODO can we add crossOrigin here?
  makes(satUsemap, satHUseMap, TAG_IMG),
  makeb(satIsmap, satHIsMap, TAG_IMG),
  makeb(satDisabled, TAG_LINK, TAG_OPTION, TAG_SELECT, TAG_OPTGROUP),
  # super-global attributes
  makes(satClass, satClassName, AllTagTypes),
  makef(satOnclick, satClick),
  makef(satOninput, satInput),
  makef(satOnchange, satChange),
  makef(satOnload, satLoad),
  makef(satOnerror, satError),
  makef(satOnblur, satBlur),
  makef(satOnfocus, satFocus),
  makes(satSlot, AllTagTypes),
  makes(satTitle, AllTagTypes),
  makes(satLang, AllTagTypes),
]

# Iterators
iterator childList*(node: Node): Node {.inline.} =
  var it {.cursor.} = node.firstChild
  if it != nil:
    while true:
      yield it
      it = it.internalNext
      if it.internalNext == nil:
        break # it is ownerDocument

iterator rchildList*(node: Node): Node {.inline.} =
  let first = node.firstChild
  if first != nil:
    var it {.cursor.} = first.internalPrev
    while true:
      yield it
      if it == first:
        break
      it = it.internalPrev

iterator precedingSiblings*(node: Node): Node {.inline.} =
  let parent = node.parentNode
  if parent != nil:
    let first = parent.firstChild
    if node != first:
      var it = node.internalPrev
      while true:
        yield it
        if it == first:
          break
        it = it.internalPrev

iterator subsequentSiblings*(node: Node): Node {.inline.} =
  var it = node.internalNext
  if it != nil:
    while true:
      yield it
      it = it.internalNext

iterator elementList*(node: Node): Element {.inline.} =
  for child in node.childList:
    if child of Element:
      yield Element(child)

iterator relementList*(node: Node): Element {.inline.} =
  for child in node.rchildList:
    if child of Element:
      yield Element(child)

iterator ancestors*(node: Node): Element {.inline.} =
  var element = node.parentElement
  while element != nil:
    yield element
    element = element.parentElement

iterator nodeAncestors*(node: Node): Node {.inline.} =
  var node = node.parentNode
  while node != nil:
    yield node
    node = node.parentNode

# inclusive ancestors
iterator branch*(node: Node): Node {.inline.} =
  var node = node
  while node != nil:
    yield node
    node = node.parentNode

iterator branchElems*(node: Node): Element {.inline.} =
  for node in node.branch:
    if node of Element:
      yield Element(node)

iterator descendants*(node: Node): Node {.inline.} =
  var stack: seq[Node] = @[]
  for child in node.rchildList:
    stack.add(child)
  while stack.len > 0:
    let node = stack.pop()
    yield node
    for child in node.rchildList:
      stack.add(child)

iterator descendantsIncl(node: Node): Node {.inline.} =
  var stack = @[node]
  while stack.len > 0:
    let node = stack.pop()
    yield node
    for child in node.rchildList:
      stack.add(child)

iterator elementDescendants*(node: Node): Element {.inline.} =
  for child in node.descendants:
    if child of Element:
      yield Element(child)

iterator elementDescendantsIncl(node: Node): Element {.inline.} =
  for child in node.descendantsIncl:
    if child of Element:
      yield Element(child)

iterator elementDescendants(node: Node; tag: TagType): Element {.inline.} =
  for desc in node.elementDescendants:
    if desc.tagType == tag:
      yield desc

iterator elementDescendants*(node: Node; tag: set[TagType]): Element
    {.inline.} =
  for desc in node.elementDescendants:
    if desc.tagType in tag:
      yield desc

iterator displayedElements*(window: Window; tag: TagType): Element
    {.inline.} =
  let node = window.document
  var stack: seq[Node] = @[]
  for child in node.rchildList:
    stack.add(child)
  while stack.len > 0:
    let node = stack.pop()
    if node of Element:
      let element = Element(node)
      window.maybeRestyle(element)
      if element.computed{"display"} != DisplayNone:
        yield element
        for child in node.rchildList:
          stack.add(child)

iterator inputs(form: HTMLFormElement): HTMLInputElement {.inline.} =
  for control in form.controls:
    if control of HTMLInputElement:
      yield HTMLInputElement(control)

iterator radiogroup*(input: HTMLInputElement): HTMLInputElement {.inline.} =
  let name = input.name
  if name != CAtomNull and name != satUempty.toAtom():
    if input.form != nil:
      for input in input.form.inputs:
        if input.name == name and input.inputType == itRadio:
          yield input
    else:
      for input in input.document.elementDescendants(TAG_INPUT):
        let input = HTMLInputElement(input)
        if input.form == nil and input.name == name and
            input.inputType == itRadio:
          yield input

iterator textNodes*(node: Node): Text {.inline.} =
  for node in node.childList:
    if node of Text:
      yield Text(node)

iterator options*(select: HTMLSelectElement): HTMLOptionElement {.inline.} =
  for child in select.elementList:
    if child of HTMLOptionElement:
      yield HTMLOptionElement(child)
    elif child of HTMLOptGroupElement:
      for opt in child.elementList:
        if opt of HTMLOptionElement:
          yield HTMLOptionElement(opt)

# Window/Global
# For now, these are the same; on an API level however, getGlobal is
# guaranteed to be non-null, while getWindow may return null in the
# future.  (This is in preparation for Worker support.)
func getGlobal*(ctx: JSContext): Window =
  let global = JS_GetGlobalObject(ctx)
  var window: Window
  doAssert ctx.fromJSFree(global, window).isOk
  return window

func getWindow*(ctx: JSContext): Window =
  let global = JS_GetGlobalObject(ctx)
  var window: Window
  doAssert ctx.fromJSFree(global, window).isOk
  return window

func console(window: Window): Console =
  return window.internalConsole

proc setWeak(ctx: JSContext; wwm: WindowWeakMap; key, val: JSValue): Opt[void] =
  let global = ctx.getGlobal()
  let argv = [key, val]
  let res = JS_Invoke(ctx, global.weakMap[wwm], ctx.getOpaque().strRefs[jstSet],
    2, argv.toJSValueConstArray())
  let e = JS_IsException(res)
  JS_FreeValue(ctx, res)
  JS_FreeValue(ctx, key)
  JS_FreeValue(ctx, val)
  if e:
    return err()
  ok()

proc getWeak(ctx: JSContext; wwm: WindowWeakMap; key: JSValueConst): JSValue =
  let global = ctx.getGlobal()
  return JS_Invoke(ctx, global.weakMap[wwm], ctx.getOpaque().strRefs[jstGet],
    1, key.toJSValueConstArray())

func isCell(this: Node): bool =
  return this of Element and Element(this).tagType in {TAG_TD, TAG_TH}

func isTBody(this: Node): bool =
  return this of Element and Element(this).tagType == TAG_TBODY

func isRow(this: Node): bool =
  return this of Element and Element(this).tagType == TAG_TR

func isOptionOf(node: Node; select: HTMLSelectElement): bool =
  if node of HTMLOptionElement:
    let parent = node.parentNode
    return parent == select or
      parent of HTMLOptGroupElement and parent.parentNode == select
  return false

func isElement(node: Node): bool =
  return node of Element

func isForm(node: Node): bool =
  return node of HTMLFormElement

proc isLink(node: Node): bool =
  if not (node of Element):
    return false
  let element = Element(node)
  return element.tagType in {TAG_A, TAG_AREA} and element.attrb(satHref)

proc newWeakCollection(ctx: JSContext; this: Node; wwm: WindowWeakMap):
    JSValue =
  case wwm
  of wwmChildren:
    return ctx.toJS(this.newHTMLCollection(
      match = isElement,
      islive = true,
      childonly = true
    ))
  of wwmChildNodes:
    return ctx.toJS(this.newNodeList(
      match = nil,
      islive = true,
      childonly = true
    ))
  of wwmSelectedOptions:
    let this = HTMLSelectElement(this)
    return ctx.toJS(this.newHTMLCollection(
      match = func(node: Node): bool =
        return node.isOptionOf(this) and HTMLOptionElement(node).selected,
      islive = true,
      childonly = false
    ))
  of wwmTBodies:
    return ctx.toJS(this.newHTMLCollection(
      match = isTBody,
      islive = true,
      childonly = true
    ))
  of wwmCells:
    return ctx.toJS(this.newHTMLCollection(
      match = isCell,
      islive = true,
      childonly = true
    ))
  of wwmDatalist:
    return ctx.toJS(DOMStringMap(target: HTMLElement(this)))
  of wwmAttributes:
    let element = Element(this)
    let map = NamedNodeMap(element: element)
    let document = element.document
    for i, attr in element.attrs.mypairs:
      map.attrlist.add(Attr(
        internalNext: document,
        dataIdx: i,
        ownerElement: element
      ))
    return ctx.toJS(map)

proc getWeakCollection(ctx: JSContext; this: Node; wwm: WindowWeakMap):
    JSValue =
  let jsThis = ctx.toJS(this)
  let res = ctx.getWeak(wwm, jsThis)
  if JS_IsUndefined(res):
    let collection = ctx.newWeakCollection(this, wwm)
    if JS_IsException(collection):
      return JS_EXCEPTION
    if ctx.setWeak(wwm, jsThis, JS_DupValue(ctx, collection)).isErr:
      return JS_EXCEPTION
    return collection
  JS_FreeValue(ctx, jsThis)
  return res

proc corsFetch(window: Window; input: Request): FetchPromise =
  if not window.settings.images and input.url.scheme.startsWith("img-codec+"):
    return newResolvedPromise(JSResult[Response].err(newFetchTypeError()))
  return window.loader.fetch(input)

proc parseStylesheet(window: Window; s: openArray[char]; baseURL: URL):
    CSSStylesheet =
  s.parseStylesheet(baseURL, addr window.settings)

proc loadSheet(window: Window; link: HTMLLinkElement; url: URL):
    Promise[CSSStylesheet] =
  let p = window.corsFetch(
    newRequest(url)
  ).then(proc(res: JSResult[Response]): Promise[JSResult[string]] =
    if res.isOk:
      let res = res.get
      if res.getContentType().equalsIgnoreCase("text/css"):
        return res.text()
      res.close()
    return newResolvedPromise(JSResult[string].err(nil))
  ).then(proc(s: JSResult[string]): Promise[CSSStylesheet] =
    if s.isOk:
      let sheet = window.parseStylesheet(s.get, url)
      var promises: seq[EmptyPromise] = @[]
      var sheets = newSeq[CSSStylesheet](sheet.importList.len)
      for i, url in sheet.importList:
        (proc(i: int) =
          let p = window.loadSheet(link, url).then(proc(sheet: CSSStylesheet) =
            sheets[i] = sheet
          )
          promises.add(p)
        )(i)
      return promises.all().then(proc(): CSSStylesheet =
        for sheet in sheets:
          if sheet != nil:
            #TODO check import media query here
            link.sheets.add(sheet)
        return sheet
      )
    return newResolvedPromise[CSSStylesheet](nil)
  )
  return p

# see https://html.spec.whatwg.org/multipage/links.html#link-type-stylesheet
#TODO make this somewhat compliant with ^this
proc loadResource(window: Window; link: HTMLLinkElement) =
  if not window.settings.styling or
      not link.relList.containsIgnoreCase(satStylesheet) or
      link.fetchStarted or
      not link.enabled.get(not link.relList.containsIgnoreCase(satAlternate)):
    return
  link.fetchStarted = true
  let href = link.attr(satHref)
  if href == "":
    return
  if url := parseURL(href, window.document.url.some):
    let media = link.attr(satMedia)
    var applies = true
    if media != "":
      let cvals = parseComponentValues(media)
      let media = parseMediaQueryList(cvals, window.settings.attrsp)
      applies = media.applies(addr window.settings)
    link.sheets.setLen(0)
    let p = window.loadSheet(link, url).then(proc(sheet: CSSStylesheet) =
      # Note: we intentionally load all sheets first and *then* check
      # whether media applies, to prevent media query based tracking.
      if sheet != nil and applies:
        link.sheets.add(sheet)
        window.document.applyAuthorSheets()
        let html = window.document.documentElement
        if html != nil:
          html.invalidate()
    )
    window.pendingResources.add(p)

proc getImageId(window: Window): int =
  result = window.imageId
  inc window.imageId

proc fireEvent*(window: Window; event: Event; target: EventTarget) =
  discard window.jsctx.dispatch(target, event)

proc fireEvent*(window: Window; name: StaticAtom; target: EventTarget;
    bubbles, cancelable, trusted: bool) =
  let event = newEvent(name.toAtom(), target, bubbles, cancelable)
  event.isTrusted = trusted
  window.fireEvent(event, target)

proc loadResource*(window: Window; image: HTMLImageElement) =
  if not window.settings.images:
    if image.bitmap != nil:
      image.invalidate()
      image.bitmap = nil
    image.fetchStarted = false
    return
  if image.fetchStarted:
    return
  image.fetchStarted = true
  let src = image.attr(satSrc)
  if src == "":
    return
  if url := parseURL(src, window.document.url.some):
    if window.document.url.schemeType == stHttps and url.schemeType == stHttp:
      # mixed content :/
      #TODO maybe do this in loader?
      url.setProtocol("https")
    let surl = $url
    window.imageURLCache.withValue(surl, p):
      if p[].expiry > getTime().toUnix():
        image.bitmap = p[].bmp
        return
      elif p[].loading:
        p[].shared.add(image)
        return
    let cachedURL = CachedURLImage(expiry: -1, loading: true)
    window.imageURLCache[surl] = cachedURL
    let headers = newHeaders(hgRequest, {"Accept": "*/*"})
    let p = window.corsFetch(newRequest(url, headers = headers)).then(
      proc(res: JSResult[Response]): EmptyPromise =
        if res.isErr:
          return newResolvedPromise()
        let response = res.get
        let contentType = response.getContentType("image/x-unknown")
        if not contentType.startsWith("image/"):
          return newResolvedPromise()
        var t = contentType.after('/')
        if t == "x-unknown":
          let ext = response.url.pathname.getFileExt()
          # Note: imageTypes is taken from mime.types.
          # To avoid fingerprinting, we
          # a) always download the entire image (through addCacheFile) -
          #    this prevents the server from knowing what content type
          #    is supported
          # b) prevent mime.types extensions for images defined by
          #    ourselves
          # In fact, a) would by itself be enough, but I'm not sure if
          # it's the best way, so I added b) as a fallback measure.
          t = window.imageTypes.getOrDefault(ext, "x-unknown")
        let cacheId = window.loader.addCacheFile(response.outputId)
        let url = newURL("img-codec+" & t & ":decode").get(nil)
        if url == nil:
          return newResolvedPromise()
        let request = newRequest(
          url,
          httpMethod = hmPost,
          headers = newHeaders(hgRequest, {"Cha-Image-Info-Only": "1"}),
          body = RequestBody(t: rbtOutput, outputId: response.outputId),
        )
        let r = window.corsFetch(request)
        response.resume()
        response.close()
        var expiry = -1i64
        for s in response.headers.getAllCommaSplit("Cache-Control"):
          let s = s.strip()
          if s.startsWithIgnoreCase("max-age="):
            let i = s.skipBlanks("max-age=".len)
            let s = s.until(AllChars - AsciiDigit, i)
            let pi = parseInt64(s)
            if pi.isOk:
              expiry = getTime().toUnix() + pi.get
            break
        cachedURL.loading = false
        cachedURL.expiry = expiry
        return r.then(proc(res: JSResult[Response]) =
          if res.isErr:
            return
          let response = res.get
          # close immediately; all data we're interested in is in the headers.
          response.close()
          let headers = response.headers
          let dims = headers.getFirst("Cha-Image-Dimensions")
          let width = parseIntP(dims.until('x')).get(-1)
          let height = parseIntP(dims.after('x')).get(-1)
          if width < 0 or height < 0:
            window.console.error("wrong Cha-Image-Dimensions in", $response.url)
            return
          let bmp = NetworkBitmap(
            width: width,
            height: height,
            cacheId: cacheId,
            imageId: window.getImageId(),
            contentType: "image/" & t
          )
          image.bitmap = bmp
          cachedURL.bmp = bmp
          for share in cachedURL.shared:
            share.bitmap = bmp
            share.invalidate()
          image.invalidate()
          #TODO fire error on error
          if window.settings.scripting != smFalse:
            window.fireEvent(satLoad, image, bubbles = false,
              cancelable = false, trusted = true)
        )
      )
    window.pendingImages.add(p)

proc loadResource*(window: Window; svg: SVGSVGElement) =
  if not window.settings.images:
    if svg.bitmap != nil:
      svg.invalidate()
      svg.bitmap = nil
    svg.fetchStarted = false
    return
  if svg.fetchStarted:
    return
  svg.fetchStarted = true
  let s = svg.outerHTML
  if s.len <= 4096: # try to dedupe if the SVG is small enough.
    window.svgCache.withValue(s, elp):
      svg.bitmap = elp.bitmap
      if svg.bitmap != nil: # already decoded
        svg.invalidate()
      else: # tell me when you're done
        elp.shared.add(svg)
      return
    window.svgCache[s] = svg
  let imageId = window.getImageId()
  let loader = window.loader
  let (ps, svgres) = loader.doPipeRequest("svg-" & $imageId)
  if ps == nil:
    return
  let cacheId = loader.addCacheFile(svgres.outputId)
  if not ps.writeDataLoop(s):
    ps.sclose()
    return
  ps.sclose()
  let request = newRequest(
    newURL("img-codec+svg+xml:decode").get,
    httpMethod = hmPost,
    headers = newHeaders(hgRequest, {"Cha-Image-Info-Only": "1"}),
    body = RequestBody(t: rbtOutput, outputId: svgres.outputId)
  )
  let p = loader.fetch(request).then(proc(res: JSResult[Response]) =
    svgres.close()
    if res.isErr: # no SVG module; give up
      return
    let response = res.get
    # close immediately; all data we're interested in is in the headers.
    response.close()
    let dims = response.headers.getFirst("Cha-Image-Dimensions")
    let width = parseIntP(dims.until('x')).get(-1)
    let height = parseIntP(dims.after('x')).get(-1)
    if width < 0 or height < 0:
      window.console.error("wrong Cha-Image-Dimensions in", $response.url)
      return
    svg.bitmap = NetworkBitmap(
      width: width,
      height: height,
      cacheId: cacheId,
      imageId: imageId,
      contentType: "image/svg+xml"
    )
    for share in svg.shared:
      share.bitmap = svg.bitmap
      share.invalidate()
    svg.invalidate()
  )
  window.pendingImages.add(p)

proc runJSJobs*(window: Window) =
  while true:
    let r = window.jsrt.runJSJobs()
    if r.isOk:
      break
    let ctx = r.error
    window.console.writeException(ctx)

proc performMicrotaskCheckpoint*(window: Window) =
  if window.inMicrotaskCheckpoint:
    return
  window.inMicrotaskCheckpoint = true
  window.runJSJobs()
  window.inMicrotaskCheckpoint = false

proc getComputedStyle0*(window: Window; element: Element;
    pseudoElt: Option[string]): CSSStyleDeclaration =
  let pseudo = case pseudoElt.get("")
  of ":before", "::before": peBefore
  of ":after", "::after": peAfter
  of "": peNone
  else: return newCSSStyleDeclaration(nil, "")
  if window.settings.scripting == smApp:
    window.maybeRestyle(element)
    return newCSSStyleDeclaration(element, $element.getComputedStyle(pseudo),
      computed = true, readonly = true)
  # In lite mode, we just parse the "style" attribute and hope for
  # the best.
  return newCSSStyleDeclaration(element, element.attr(satStyle),
    computed = true, readonly = true)

# Node
when defined(debug):
  func `$`*(node: Node): string =
    if node == nil:
      return "null"
    result = ""
    result.serializeFragmentInner(node, TAG_UNKNOWN)

proc baseURI(node: Node): string {.jsfget.} =
  return $node.document.baseURL

func document*(node: Node): Document =
  let next = node.internalNext
  if next == nil:
    return Document(node)
  if next.internalNext == nil:
    return Document(next)
  return Document(node.parentNode.firstChild.internalPrev.internalNext)

func parentElement*(node: Node): Element {.jsfget.} =
  let p = node.parentNode
  if p != nil and p of Element:
    return Element(p)
  return nil

func nextSibling*(node: Node): Node {.jsfget.} =
  if node.internalNext == nil or node.internalNext.internalNext == nil:
    # if next is nil, then node is a Document.
    # if next.next is nil, then next is ownerDocument.
    return nil
  return node.internalNext

func previousSibling*(node: Node): Node {.jsfget.} =
  if node.parentNode == nil or node == node.parentNode.firstChild:
    return nil
  return node.internalPrev

proc getChildList*(node: Node): seq[Node] =
  result = @[]
  for child in node.childList:
    result.add(child)

func hasChildNodes(node: Node): bool {.jsfunc.} =
  return node.firstChild != nil

func ownerDocument(node: Node): Document {.jsfget.} =
  if node of Document:
    return nil
  return node.document

func jsNodeType0(node: Node): NodeType =
  if node of CharacterData:
    if node of Text:
      return TEXT_NODE
    elif node of Comment:
      return COMMENT_NODE
    elif node of CDATASection:
      return CDATA_SECTION_NODE
    elif node of ProcessingInstruction:
      return PROCESSING_INSTRUCTION_NODE
    assert false
  elif node of Element:
    return ELEMENT_NODE
  elif node of Document:
    return DOCUMENT_NODE
  elif node of DocumentType:
    return DOCUMENT_TYPE_NODE
  elif node of Attr:
    return ATTRIBUTE_NODE
  elif node of DocumentFragment:
    return DOCUMENT_FRAGMENT_NODE
  assert false
  ENTITY_NODE

func nodeType(node: Node): uint16 {.jsfget.} =
  return uint16(node.jsNodeType0)

func nodeName(node: Node): string {.jsfget.} =
  if node of Element:
    return Element(node).tagName
  if node of Attr:
    return $Attr(node).data.qualifiedName
  if node of DocumentType:
    return DocumentType(node).name
  if node of CDATASection:
    return "#cdata-section"
  if node of Comment:
    return "#comment"
  if node of Document:
    return "#document"
  if node of DocumentFragment:
    return "#document-fragment"
  if node of ProcessingInstruction:
    return ProcessingInstruction(node).target
  assert node of Text
  return "#text"

func isValidParent(node: Node): bool =
  return node of Element or node of Document or node of DocumentFragment

func isValidChild(node: Node): bool =
  return node.isValidParent or node of DocumentType or node of CharacterData

func checkParentValidity(parent: Node): Err[DOMException] =
  if parent.isValidParent():
    return ok()
  const msg = "Parent must be a document, a document fragment, or an element."
  return errDOMException(msg, "HierarchyRequestError")

func rootNode(node: Node): Node =
  var node = node
  while node.parentNode != nil:
    node = node.parentNode
  return node

func countChildren(node: Node; nodeType: type): int =
  result = 0
  for child in node.childList:
    if child of nodeType:
      inc result

func hasChild(node: Node; nodeType: type): bool =
  for child in node.childList:
    if child of nodeType:
      return true
  return false

func isHostIncludingInclusiveAncestor(a, b: Node): bool =
  for parent in b.branch:
    if parent == a:
      return true
  let root = b.rootNode
  if root of DocumentFragment and DocumentFragment(root).host != nil:
    for parent in root.branch:
      if parent == a:
        return true
  return false

func hasNextSibling(node: Node; nodeType: type): bool =
  var node = node.nextSibling
  while node != nil:
    if node of nodeType:
      return true
    node = node.nextSibling
  return false

func hasPreviousSibling(node: Node; nodeType: type): bool =
  var node = node.previousSibling
  while node != nil:
    if node of nodeType:
      return true
    node = node.previousSibling
  return false

func hasChildExcept(node: Node; nodeType: type; ex: Node): bool =
  for child in node.childList:
    if child == ex:
      continue
    if child of nodeType:
      return true
  return false

func nodeValue(ctx: JSContext; node: Node): JSValue {.jsfget.} =
  if node of CharacterData:
    return ctx.toJS(CharacterData(node).data)
  elif node of Attr:
    return ctx.toJS(Attr(node).data.value)
  return JS_NULL

func textContent*(node: Node): string =
  if node of CharacterData:
    result = CharacterData(node).data
  else:
    result = ""
    for child in node.childList:
      if not (child of Comment):
        result &= child.textContent

func textContent(ctx: JSContext; node: Node): JSValue {.jsfget.} =
  if node of Document or node of DocumentType:
    return JS_NULL
  return ctx.toJS(node.textContent)

func childTextContent*(node: Node): string =
  result = ""
  for child in node.childList:
    if child of Text:
      result &= Text(child).data

func isConnected(node: Node): bool {.jsfget.} =
  return node.rootNode of Document #TODO shadow root

func inSameTree*(a, b: Node): bool =
  a.rootNode == b.rootNode

# a == b or a in b's ancestors
func contains*(a, b: Node): bool {.jsfunc.} =
  if b != nil:
    for node in b.branch:
      if node == a:
        return true
  return false

func lastChild*(node: Node): Node {.jsfget.} =
  if node.firstChild != nil:
    return node.firstChild.internalPrev
  nil

func firstElementChild*(node: Node): Element =
  for child in node.elementList:
    return child
  return nil

# WARNING the ordering of the arguments in the standard is whack so this
# doesn't match that
func preInsertionValidity(parent, node, before: Node): Err[DOMException] =
  ?checkParentValidity(parent)
  if node.isHostIncludingInclusiveAncestor(parent):
    return errDOMException("Parent must be an ancestor",
      "HierarchyRequestError")
  if before != nil and before.parentNode != parent:
    return errDOMException("Reference node is not a child of parent",
      "NotFoundError")
  if not node.isValidChild():
    return errDOMException("Node is not a valid child", "HierarchyRequestError")
  if node of Text and parent of Document:
    return errDOMException("Cannot insert text into document",
      "HierarchyRequestError")
  if node of DocumentType and not (parent of Document):
    return errDOMException("Document type can only be inserted into document",
      "HierarchyRequestError")
  if parent of Document:
    if node of DocumentFragment:
      let elems = node.countChildren(Element)
      if elems > 1 or node.hasChild(Text):
        return errDOMException("Document fragment has invalid children",
          "HierarchyRequestError")
      elif elems == 1 and (parent.hasChild(Element) or
          before != nil and (before of DocumentType or
          before.hasNextSibling(DocumentType))):
        return errDOMException("Document fragment has invalid children",
          "HierarchyRequestError")
    elif node of Element:
      if parent.hasChild(Element):
        return errDOMException("Document already has an element child",
          "HierarchyRequestError")
      elif before != nil and (before of DocumentType or
            before.hasNextSibling(DocumentType)):
        return errDOMException("Cannot insert element before document type",
          "HierarchyRequestError")
    elif node of DocumentType:
      if parent.hasChild(DocumentType) or
          before != nil and before.hasPreviousSibling(Element) or
          before == nil and parent.hasChild(Element):
        const msg = "Cannot insert document type before an element node"
        return errDOMException(msg, "HierarchyRequestError")
    else: discard
  return ok() # no exception reached

proc insertNode(parent, node, before: Node) =
  parent.document.adopt(node)
  let element = if node of Element: Element(node) else: nil
  if before == nil:
    let first = parent.firstChild
    if first != nil:
      let last = first.internalPrev
      last.internalNext = node
      node.internalPrev = last
    else:
      parent.firstChild = node
    parent.firstChild.internalPrev = node
  else:
    node.internalNext = before
    let prev = before.internalPrev
    node.internalPrev = prev
    if prev.nextSibling != nil:
      prev.internalNext = node
    before.internalPrev = node
    if before == parent.firstChild:
      parent.firstChild = node
  node.parentNode = parent
  if element != nil:
    if element.nextSibling != nil and parent of Element:
      let parent = Element(parent)
      parent.childElIndicesInvalid = true
    elif (let prev = element.previousElementSibling; prev != nil):
      element.internalElIndex = prev.internalElIndex + 1
    else:
      element.internalElIndex = 0
  node.document.invalidateCollections()
  if node.document != nil and (node of HTMLStyleElement or
      node of HTMLLinkElement):
    node.document.applyAuthorSheets()
  var nodes: seq[Element] = @[]
  for el in node.elementDescendantsIncl:
    #TODO shadow root
    if el.elementInsertionSteps():
      nodes.add(el)
  for el in nodes:
    el.postConnectionSteps()

# Pass an index to avoid searching for the node in parent's child list.
proc remove*(node: Node; suppressObservers: bool) =
  let parent = node.parentNode
  let document = node.document
  # document is only nil for Document nodes, but those cannot call
  # remove().
  assert parent != nil and document != nil
  #TODO live ranges
  #TODO NodeIterator
  let element = if node of Element: Element(node) else: nil
  let parentElement = node.parentElement
  let prev = node.internalPrev
  let next = node.internalNext
  if next != nil and next.internalNext != nil:
    next.internalPrev = prev
  else:
    parent.firstChild.internalPrev = prev
  if parent.firstChild == node:
    if next != nil and next.internalNext != nil:
      parent.firstChild = next
    else:
      parent.firstChild = nil
  else:
    prev.internalNext = next
  if parentElement != nil:
    parentElement.invalidate()
  node.internalPrev = nil
  node.internalNext = document
  node.parentNode = nil
  document.invalidateCollections()
  if element != nil:
    if element.internalElIndex == 0 and parentElement != nil:
      parentElement.childElIndicesInvalid = true
    element.internalElIndex = -1
    if element.document != nil:
      if element of HTMLStyleElement or element of HTMLLinkElement:
        element.document.applyAuthorSheets()
      for desc in element.elementDescendantsIncl:
        desc.applyStyleDependencies(DependencyInfo.default)
  #TODO assigned, shadow root, shadow root again, custom nodes, registered
  # observers
  #TODO not suppress observers => queue tree mutation record

proc remove*(node: Node) {.jsfunc.} =
  if node.parentNode != nil:
    node.remove(suppressObservers = false)

proc removeChild(parent, node: Node): DOMResult[Node] {.jsfunc.} =
  if node.parentNode != parent:
    return errDOMException("Node is not a child of parent", "NotFoundError")
  node.remove()
  return ok(node)

# WARNING ditto
proc insert*(parent, node, before: Node; suppressObservers = false) =
  let nodes = if node of DocumentFragment: node.getChildList() else: @[node]
  let count = nodes.len
  if count == 0:
    return
  if node of DocumentFragment:
    for child in nodes:
      child.remove(true)
    #TODO tree mutation record
  if before != nil:
    #TODO live ranges
    discard
  if parent of Element:
    Element(parent).invalidate()
  for node in nodes:
    insertNode(parent, node, before)

proc insertBefore*(parent, node: Node; before: Option[Node]): DOMResult[Node]
    {.jsfunc.} =
  let before = before.get(nil)
  ?parent.preInsertionValidity(node, before)
  let referenceChild = if before == node:
    node.nextSibling
  else:
    before
  parent.insert(node, referenceChild)
  return ok(node)

proc appendChild(parent, node: Node): DOMResult[Node] {.jsfunc.} =
  return parent.insertBefore(node, none(Node))

proc append*(parent, node: Node) =
  discard parent.appendChild(node)

# WARNING the ordering of the arguments in the standard is whack so this
# doesn't match that
# Note: the standard returns child if not err. We don't, it's just a
# pointless copy.
proc replace*(parent, child, node: Node): Err[DOMException] =
  ?checkParentValidity(parent)
  if node.isHostIncludingInclusiveAncestor(parent):
    return errDOMException("Parent must be an ancestor",
      "HierarchyRequestError")
  if child.parentNode != parent:
    return errDOMException("Node to replace is not a child of parent",
      "NotFoundError")
  if not node.isValidChild():
    return errDOMException("Node is not a valid child", "HierarchyRequesError")
  if node of Text and parent of Document or
      node of DocumentType and not (parent of Document):
    return errDOMException("Replacement cannot be placed in parent",
      "HierarchyRequesError")
  let childNextSibling = child.nextSibling
  let childPreviousSibling = child.previousSibling
  if parent of Document:
    if node of DocumentFragment:
      let elems = node.countChildren(Element)
      if elems > 1 or node.hasChild(Text):
        return errDOMException("Document fragment has invalid children",
          "HierarchyRequestError")
      elif elems == 1 and (parent.hasChildExcept(Element, child) or
          childNextSibling != nil and childNextSibling of DocumentType):
        return errDOMException("Document fragment has invalid children",
          "HierarchyRequestError")
    elif node of Element:
      if parent.hasChildExcept(Element, child):
        return errDOMException("Document already has an element child",
          "HierarchyRequestError")
      elif childNextSibling != nil and childNextSibling of DocumentType:
        return errDOMException("Cannot insert element before document type ",
          "HierarchyRequestError")
    elif node of DocumentType:
      if parent.hasChildExcept(DocumentType, child) or
          childPreviousSibling != nil and childPreviousSibling of DocumentType:
        const msg = "Cannot insert document type before an element node"
        return errDOMException(msg, "HierarchyRequestError")
  let referenceChild = if childNextSibling == node:
    node.nextSibling
  else:
    childNextSibling
  #NOTE the standard says "if parent is not null", but the adoption step
  # that made it necessary has been removed.
  child.remove(suppressObservers = true)
  parent.insert(node, referenceChild, suppressObservers = true)
  #TODO tree mutation record
  return ok()

proc replaceAll(parent, node: Node) =
  let removedNodes = parent.getChildList()
  for child in removedNodes:
    child.remove(true)
  assert parent != node
  if node != nil:
    if node of DocumentFragment:
      let addedNodes = node.getChildList()
      for child in addedNodes:
        parent.append(child)
    else:
      parent.append(node)
  #TODO tree mutation record

proc replaceAll(parent: Node; s: sink string) =
  parent.replaceAll(parent.document.newText(s))

proc replaceChild(parent, node, child: Node): DOMResult[Node] {.jsfunc.} =
  ?parent.replace(child, node)
  return ok(child)

proc clone(node: Node; document = none(Document), deep = false): Node =
  let document = document.get(node.document)
  let copy = if node of Element:
    #TODO is value
    let element = Element(node)
    let x = document.newElement(element.localName, element.namespaceURI,
      element.prefix)
    x.id = element.id
    x.name = element.name
    x.classList = x.newDOMTokenList(satClassList)
    x.attrs = element.attrs
    #TODO namespaced attrs?
    # Cloning steps
    if x of HTMLScriptElement:
      let x = HTMLScriptElement(x)
      let element = HTMLScriptElement(element)
      x.alreadyStarted = element.alreadyStarted
    elif x of HTMLInputElement:
      let x = HTMLInputElement(x)
      let element = HTMLInputElement(element)
      x.inputType = element.inputType
      x.setValue(element.value)
      #TODO dirty value flag
      x.setChecked(element.checked)
      #TODO dirty checkedness flag
    Node(x)
  elif node of Attr:
    let attr = Attr(node)
    let data = attr.data
    let x = Attr(
      ownerElement: AttrDummyElement(
        internalNext: attr.ownerElement.document,
        internalElIndex: -1,
        attrs: @[data]
      ),
      dataIdx: 0
    )
    Node(x)
  elif node of Text:
    let text = Text(node)
    let x = document.newText(text.data)
    Node(x)
  elif node of CDATASection:
    let x = document.newCDATASection("")
    #TODO is this really correct??
    # really, I don't know. only relevant with xhtml anyway...
    Node(x)
  elif node of Comment:
    let comment = Comment(node)
    let x = document.newComment(comment.data)
    Node(x)
  elif node of ProcessingInstruction:
    let procinst = ProcessingInstruction(node)
    let x = document.newProcessingInstruction(procinst.target, procinst.data)
    Node(x)
  elif node of Document:
    let document = Document(node)
    let x = newDocument()
    x.charset = document.charset
    x.contentType = document.contentType
    x.url = document.url
    x.mode = document.mode
    Node(x)
  elif node of DocumentType:
    let doctype = DocumentType(node)
    let x = document.newDocumentType(doctype.name, doctype.publicId,
      doctype.systemId)
    Node(x)
  elif node of DocumentFragment:
    let x = document.newDocumentFragment()
    Node(x)
  else:
    assert false
    Node(nil)
  if deep:
    for child in node.childList:
      copy.append(child.clone(deep = true))
  return copy

proc cloneNode(node: Node; deep = false): Node {.jsfunc.} =
  #TODO shadow root
  return node.clone(deep = deep)

func isSameNode(node, other: Node): bool {.jsfunc.} =
  return node == other

proc getElementsByTagNameImpl(root: Node; tagName: string): HTMLCollection =
  if tagName == "*":
    return root.newHTMLCollection(isElement, islive = true, childonly = false)
  let localName = tagName.toAtom()
  let localNameLower = localName.toLowerAscii()
  return root.newHTMLCollection(
    func(node: Node): bool =
      if node of Element:
        let element = Element(node)
        if element.namespaceURI == satNamespaceHTML:
          return element.localName == localNameLower
        return element.localName == localName
      return false,
    islive = true,
    childonly = false
  )

proc getElementsByClassNameImpl(node: Node; classNames: string):
    HTMLCollection =
  var classAtoms = newSeq[CAtom]()
  for class in classNames.split(AsciiWhitespace):
    classAtoms.add(class.toAtom())
  return node.newHTMLCollection(
    func(node: Node): bool =
      if node of Element:
        let element = Element(node)
        if element.document.mode == QUIRKS:
          for class in classAtoms:
            if not element.classList.toks.containsIgnoreCase(class):
              return false
        else:
          for class in classAtoms:
            if class notin element.classList.toks:
              return false
        return true
      false,
    islive = true,
    childonly = false
  )

func previousElementSiblingImpl(this: Node): Element =
  for it in this.precedingSiblings:
    if it of Element:
      return Element(it)
  nil

func nextElementSiblingImpl(this: Node): Element =
  for it in this.subsequentSiblings:
    if it of Element:
      return Element(it)
  nil

proc querySelectorImpl(node: Node; q: string): DOMResult[Element] =
  let selectors = parseSelectors(q)
  if selectors.len == 0:
    return errDOMException("Invalid selector: " & q, "SyntaxError")
  for element in node.elementDescendants:
    if element.matchesImpl(selectors):
      return ok(element)
  return ok(nil)

proc querySelectorAllImpl(node: Node; q: string): DOMResult[NodeList] =
  let selectors = parseSelectors(q)
  if selectors.len == 0:
    return errDOMException("Invalid selector: " & q, "SyntaxError")
  return ok(node.newNodeList(
    match = func(node: Node): bool =
      if node of Element:
        {.cast(noSideEffect).}:
          return Element(node).matchesImpl(selectors)
      false,
    islive = false,
    childonly = false
  ))

proc parentNodeChildrenImpl(ctx: JSContext; parentNode: Node): JSValue =
  return ctx.getWeakCollection(parentNode, wwmChildren)

func childNodes(ctx: JSContext; node: Node): JSValue {.jsfget.} =
  return ctx.getWeakCollection(node, wwmChildNodes)

func equals(a, b: AttrData): bool =
  return a.qualifiedName == b.qualifiedName and
    a.namespace == b.namespace and
    a.value == b.value

func isEqualNode(node, other: Node): bool {.jsfunc.} =
  if node of DocumentType:
    if not (other of DocumentType):
      return false
    let node = DocumentType(node)
    let other = DocumentType(other)
    if node.name != other.name or node.publicId != other.publicId or
        node.systemId != other.systemId:
      return false
  elif node of Element:
    if not (other of Element):
      return false
    let node = Element(node)
    let other = Element(other)
    if node.namespaceURI != other.namespaceURI or node.prefix != other.prefix or
        node.localName != other.localName or node.attrs.len != other.attrs.len:
      return false
    for i, attr in node.attrs.mypairs:
      if not attr.equals(other.attrs[i]):
        return false
  elif node of Attr:
    if not (other of Attr):
      return false
    if not Attr(node).data.equals(Attr(other).data):
      return false
  elif node of ProcessingInstruction:
    if not (other of ProcessingInstruction):
      return false
    let node = ProcessingInstruction(node)
    let other = ProcessingInstruction(other)
    if node.target != other.target or node.data != other.data:
      return false
  elif node of CharacterData:
    if node of Text and not (other of Text) or
        node of Comment and not (other of Comment):
      return false
    return CharacterData(node).data == CharacterData(other).data
  var it {.cursor.} = other.firstChild
  for child in node.childList:
    if it == nil or not child.isEqualNode(it):
      return false
    it = it.nextSibling
  true

func serializeFragmentInner(res: var string; child: Node; parentType: TagType) =
  if child of Element:
    let element = Element(child)
    let tags = $element.localName
    res &= '<'
    #TODO qualified name if not HTML, SVG or MathML
    res &= tags
    #TODO custom elements
    for attr in element.attrs:
      res &= ' ' & $attr.qualifiedName & "=\"" &
        attr.value.htmlEscape(mode = emAttribute) & "\""
    res &= '>'
    res.serializeFragment(element)
    res &= "</"
    res &= tags
    res &= '>'
  elif child of Text:
    let text = Text(child)
    const LiteralTags = {
      TAG_STYLE, TAG_SCRIPT, TAG_XMP, TAG_IFRAME, TAG_NOEMBED, TAG_NOFRAMES,
      TAG_PLAINTEXT, TAG_NOSCRIPT
    }
    if parentType in LiteralTags:
      res &= text.data
    else:
      res &= ($text.data).htmlEscape(mode = emText)
  elif child of Comment:
    res &= "<!--" & Comment(child).data & "-->"
  elif child of ProcessingInstruction:
    let inst = ProcessingInstruction(child)
    res &= "<?" & inst.target & " " & inst.data & '>'
  elif child of DocumentType:
    res &= "<!DOCTYPE " & DocumentType(child).name & '>'

func serializeFragment(res: var string; node: Node) =
  var node = node
  var parentType = TAG_UNKNOWN
  if node of Element:
    let element = Element(node)
    const Extra = {TAG_BASEFONT, TAG_BGSOUND, TAG_FRAME, TAG_KEYGEN, TAG_PARAM}
    if element.tagType in VoidElements + Extra:
      return
    if element of HTMLTemplateElement:
      node = HTMLTemplateElement(element).content
    else:
      parentType = element.tagType
      if parentType == TAG_NOSCRIPT and not element.scriptingEnabled:
        # Pretend parentType is not noscript, so we do not append literally
        # in serializeFragmentInner.
        parentType = TAG_UNKNOWN
  for child in node.childList:
    res.serializeFragmentInner(child, parentType)

func serializeFragment*(node: Node): string =
  result = ""
  result.serializeFragment(node)

func lastElementChild*(node: Node): Element =
  for child in node.relementList:
    return child
  return nil

proc childElementCountImpl(node: Node): int =
  let last = node.lastElementChild
  if last == nil:
    return 0
  return last.elIndex + 1

func findAncestor*(node: Node; tagType: TagType): Element =
  for element in node.ancestors:
    if element.tagType == tagType:
      return element
  return nil

func findFirstChildOf(node: Node; tagType: TagType): Element =
  for element in node.elementList:
    if element.tagType == tagType:
      return element
  return nil

func findLastChildOf(node: Node; tagType: TagType): Element =
  for element in node.relementList:
    if element.tagType == tagType:
      return element
  return nil

func findFirstChildNotOf(node: Node; tagType: set[TagType]): Element =
  for element in node.elementList:
    if element.tagType notin tagType:
      return element
  return nil

proc setNodeValue(ctx: JSContext; node: Node; data: JSValueConst): Err[void]
    {.jsfset: "nodeValue".} =
  if node of CharacterData:
    var res = ""
    if not JS_IsNull(data):
      ?ctx.fromJS(data, res)
    CharacterData(node).data = newRefString(move(res))
  elif node of Attr:
    var res = ""
    if not JS_IsNull(data):
      ?ctx.fromJS(data, res)
    Attr(node).setValue(move(res))
  return ok()

proc setTextContent(ctx: JSContext; node: Node; data: JSValueConst): Err[void]
    {.jsfset: "textContent".} =
  if node of Element or node of DocumentFragment:
    if JS_IsNull(data):
      node.replaceAll(nil)
    else:
      var res: string
      ?ctx.fromJS(data, res)
      node.replaceAll(move(res))
    return ok()
  return ctx.setNodeValue(node, data)

proc toNode(ctx: JSContext; nodes: openArray[JSValueConst]; document: Document):
    Node =
  var ns: seq[Node] = @[]
  for it in nodes:
    var node: Node
    if ctx.fromJS(it, node).isOk:
      ns.add(node)
    else:
      var s: string
      if ctx.fromJS(it, s).isOk:
        ns.add(ctx.newText(s))
  if ns.len == 1:
    return ns[0]
  let fragment = document.newDocumentFragment()
  for node in ns:
    fragment.append(node)
  return fragment

proc prependImpl(ctx: JSContext; parent: Node; nodes: openArray[JSValueConst]):
    Err[DOMException] =
  let node = ctx.toNode(nodes, parent.document)
  discard ?parent.insertBefore(node, option(parent.firstChild))
  ok()

proc appendImpl(ctx: JSContext; parent: Node; nodes: openArray[JSValueConst]):
    Err[DOMException] =
  let node = ctx.toNode(nodes, parent.document)
  discard ?parent.appendChild(node)
  ok()

proc replaceChildrenImpl(ctx: JSContext; parent: Node;
    nodes: openArray[JSValueConst]): Err[DOMException] =
  let node = ctx.toNode(nodes, parent.document)
  ?parent.preInsertionValidity(node, nil)
  parent.replaceAll(node)
  ok()

# Collection
template id(collection: Collection): pointer =
  cast[pointer](collection)

proc populateCollection(collection: Collection) =
  if collection.inclusive:
    if collection.match == nil or collection.match(collection.root):
      collection.snapshot.add(collection.root)
  if collection.childonly:
    for child in collection.root.childList:
      if collection.match == nil or collection.match(child):
        collection.snapshot.add(child)
  else:
    for desc in collection.root.descendants:
      if collection.match == nil or collection.match(desc):
        collection.snapshot.add(desc)

proc refreshCollection(collection: Collection) =
  if collection.invalid:
    assert collection.islive
    collection.snapshot.setLen(0)
    collection.populateCollection()
    collection.invalid = false

proc finalize0(collection: Collection) =
  if collection.islive:
    let i = collection.root.document.liveCollections.find(collection.id)
    assert i != -1
    collection.root.document.liveCollections.del(i)

proc finalize(collection: HTMLCollection) {.jsfin.} =
  collection.finalize0()

proc finalize(collection: NodeList) {.jsfin.} =
  collection.finalize0()

proc finalize(collection: NodeIterator) {.jsfin.} =
  collection.finalize0()
  JS_FreeValue(collection.ctx, collection.filter)

proc finalize(collection: HTMLAllCollection) {.jsfin.} =
  collection.finalize0()

proc getLength(collection: Collection): int =
  collection.refreshCollection()
  return collection.snapshot.len

proc findNode(collection: Collection; node: Node): int =
  collection.refreshCollection()
  return collection.snapshot.find(node)

func newCollection[T: Collection](root: Node; match: CollectionMatchFun;
    islive, childonly: bool; inclusive = false): T =
  let collection = T(
    islive: islive,
    childonly: childonly,
    inclusive: inclusive,
    match: match,
    root: root
  )
  if islive:
    root.document.liveCollections.add(collection.id)
    collection.invalid =  true
  else:
    collection.populateCollection()
  return collection

func newHTMLCollection(root: Node; match: CollectionMatchFun;
    islive, childonly: bool): HTMLCollection =
  return newCollection[HTMLCollection](root, match, islive, childonly)

func newNodeList(root: Node; match: CollectionMatchFun;
    islive, childonly: bool): NodeList =
  return newCollection[NodeList](root, match, islive, childonly)

# Text
func newText*(document: Document; data: sink string): Text =
  return Text(internalNext: document, data: newRefString(data))

func newText(ctx: JSContext; data: sink string = ""): Text {.jsctor.} =
  let window = ctx.getGlobal()
  return window.document.newText(data)

# CDATASection
func newCDATASection(document: Document; data: string): CDATASection =
  return CDATASection(internalNext: document, data: newRefString(data))

# ProcessingInstruction
func newProcessingInstruction(document: Document; target: string;
    data: sink string): ProcessingInstruction =
  return ProcessingInstruction(
    internalNext: document,
    target: target,
    data: newRefString(data)
  )

# Comment
func newComment(document: Document; data: sink string): Comment =
  return Comment(
    internalNext: document,
    data: newRefString(data)
  )

func newComment(ctx: JSContext; data: sink string = ""): Comment {.jsctor.} =
  let window = ctx.getGlobal()
  return window.document.newComment(data)

# DocumentFragment
func newDocumentFragment(document: Document): DocumentFragment =
  return DocumentFragment(internalNext: document)

func newDocumentFragment(ctx: JSContext): DocumentFragment {.jsctor.} =
  let window = ctx.getGlobal()
  return window.document.newDocumentFragment()

func firstElementChild(this: DocumentFragment): Element {.jsfget.} =
  return Node(this).firstElementChild

proc querySelector(this: DocumentFragment; q: string): DOMResult[Element]
    {.jsfunc.} =
  return this.querySelectorImpl(q)

proc querySelectorAll(this: DocumentFragment; q: string): DOMResult[NodeList]
    {.jsfunc.} =
  return this.querySelectorAllImpl(q)

proc prepend(ctx: JSContext; this: DocumentFragment;
    nodes: varargs[JSValueConst]): Err[DOMException] {.jsfunc.} =
  return ctx.prependImpl(this, nodes)

proc append(ctx: JSContext; this: DocumentFragment;
    nodes: varargs[JSValueConst]): Err[DOMException] {.jsfunc.} =
  return ctx.appendImpl(this, nodes)

proc replaceChildren(ctx: JSContext; this: DocumentFragment;
    nodes: varargs[JSValueConst]): Err[DOMException] {.jsfunc.} =
  return ctx.replaceChildrenImpl(this, nodes)

func children(ctx: JSContext; parentNode: DocumentFragment): JSValue
    {.jsfget.} =
  return parentNodeChildrenImpl(ctx, parentNode)

# Document
proc newXMLDocument(): XMLDocument =
  let document = XMLDocument(
    url: newURL("about:blank").get,
    contentType: satApplicationXml
  )
  document.implementation = DOMImplementation(document: document)
  return document

proc newDocument*(): Document {.jsctor.} =
  let document = Document(
    url: newURL("about:blank").get,
    contentType: satApplicationXml
  )
  document.implementation = DOMImplementation(document: document)
  return document

func newDocumentType*(document: Document;
    name, publicId, systemId: sink string): DocumentType =
  return DocumentType(
    internalNext: document,
    name: name,
    publicId: publicId,
    systemId: systemId
  )

func isxml(document: Document): bool =
  return document.contentType != satTextHtml

proc adopt(document: Document; node: Node) =
  let oldDocument = node.document
  if node.parentNode != nil:
    remove(node)
  if oldDocument != document:
    #TODO shadow root
    for desc in node.descendantsIncl:
      if desc.nextSibling == nil:
        desc.internalNext = document
    for i in countdown(oldDocument.liveCollections.high, 0):
      let id = oldDocument.liveCollections[i]
      if cast[Collection](id).root.document == document:
        node.document.liveCollections.add(id)
        oldDocument.liveCollections.del(i)
    #TODO custom elements
    #..adopting steps

func compatMode(document: Document): string {.jsfget.} =
  if document.mode == QUIRKS:
    return "BackCompat"
  return "CSS1Compat"

func forms(document: Document): HTMLCollection {.jsfget.} =
  if document.cachedForms == nil:
    document.cachedForms = document.newHTMLCollection(
      match = isForm,
      islive = true,
      childonly = false
    )
  return document.cachedForms

proc links(document: Document): HTMLCollection {.jsfget.} =
  if document.cachedLinks == nil:
    document.cachedLinks = document.newHTMLCollection(
      match = isLink,
      islive = true,
      childonly = false
    )
  return document.cachedLinks

func getURL(ctx: JSContext; document: Document): JSValue {.jsfget: "URL".} =
  return ctx.toJS($document.url)

#TODO take cookie jar from loader
func cookie(document: Document): string {.jsfget.} =
  return document.internalCookie

proc setCookie(document: Document; cookie: string) {.jsfset: "cookie".} =
  document.internalCookie = cookie

func focus*(document: Document): Element {.jsfget: "activeElement".} =
  return document.internalFocus

proc setFocus*(document: Document; element: Element) =
  if document.focus != nil:
    document.focus.invalidate(dtFocus)
  document.internalFocus = element
  if element != nil:
    element.invalidate(dtFocus)

func findAutoFocus*(document: Document): Element =
  for child in document.elementDescendants:
    if child.attrb(satAutofocus):
      return child
  return nil

func target*(document: Document): Element =
  return document.internalTarget

proc setTarget*(document: Document; element: Element) =
  if document.target != nil:
    document.target.invalidate(dtTarget)
  document.internalTarget = element
  if element != nil:
    element.invalidate(dtTarget)

func queryCommandSupported(document: Document): bool {.jsfunc.} =
  return false

proc createCDATASection(document: Document; data: string):
    DOMResult[CDATASection] {.jsfunc.} =
  if not document.isxml:
    return errDOMException("CDATA sections are not supported in HTML",
      "NotSupportedError")
  if "]]>" in data:
    return errDOMException("CDATA sections may not contain the string ]]>",
      "InvalidCharacterError")
  return ok(newCDATASection(document, data))

proc createComment*(document: Document; data: string): Comment {.jsfunc.} =
  return newComment(document, data)

proc createProcessingInstruction(document: Document; target, data: string):
    DOMResult[ProcessingInstruction] {.jsfunc.} =
  if not target.matchNameProduction() or "?>" in data:
    return errDOMException("Invalid data for processing instruction",
      "InvalidCharacterError")
  return ok(newProcessingInstruction(document, target, data))

proc createEvent(ctx: JSContext; document: Document; atom: CAtom):
    DOMResult[Event] {.jsfunc.} =
  case atom.toLowerAscii().toStaticAtom()
  of satCustomevent:
    return ok(ctx.newCustomEvent(satUempty.toAtom()))
  of satEvent, satEvents, satHtmlevents, satSvgevents:
    return ok(newEvent(satUempty.toAtom(), nil,
      bubbles = false, cancelable = false))
  of satUievent, satUievents:
    return ok(newUIEvent(satUempty.toAtom()))
  of satMouseevent, satMouseevents:
    return ok(newMouseEvent(satUempty.toAtom()))
  else:
    return errDOMException("Event not supported", "NotSupportedError")

func location(document: Document): Location {.jsfget.} =
  if document.window == nil:
    return nil
  return document.window.location

proc setLocation*(document: Document; s: string): Err[JSError]
    {.jsfset: "location".} =
  if document.location == nil:
    return errTypeError("document.location is not an object")
  let url = document.parseURL0(s)
  if url == nil:
    return errDOMException("Invalid URL", "SyntaxError")
  document.window.navigate(url)
  return ok()

func scriptingEnabled*(document: Document): bool =
  if document.window == nil:
    return false
  return document.window.settings.scripting != smFalse

func findFirst*(document: Document; tagType: TagType): HTMLElement =
  for element in document.elementDescendants(tagType):
    return HTMLElement(element)
  nil

func head*(document: Document): HTMLElement {.jsfget.} =
  return document.findFirst(TAG_HEAD)

func body*(document: Document): HTMLElement {.jsfget.} =
  return document.findFirst(TAG_BODY)

proc getElementById(document: Document; id: string): Element {.jsfunc.} =
  if id.len == 0:
    return nil
  let id = id.toAtom()
  for child in document.elementDescendants:
    if child.id == id:
      return child
  return nil

proc getElementsByName(document: Document; name: CAtom): NodeList {.jsfunc.} =
  if name == satUempty.toAtom():
    return document.newNodeList(
      func(node: Node): bool =
        return false,
      islive = false,
      childonly = true
    )
  return document.newNodeList(
    func(node: Node): bool =
      return node of Element and Element(node).name == name,
    islive = true,
    childonly = false
  )

proc getElementsByTagName(document: Document; tagName: string): HTMLCollection
    {.jsfunc.} =
  return document.getElementsByTagNameImpl(tagName)

proc getElementsByClassName(document: Document; classNames: string):
    HTMLCollection {.jsfunc.} =
  return document.getElementsByClassNameImpl(classNames)

func children(ctx: JSContext; parentNode: Document): JSValue {.jsfget.} =
  return parentNodeChildrenImpl(ctx, parentNode)

proc querySelector(this: Document; q: string): DOMResult[Element] {.jsfunc.} =
  return this.querySelectorImpl(q)

proc querySelectorAll(this: Document; q: string): DOMResult[NodeList]
    {.jsfunc.} =
  return this.querySelectorAllImpl(q)

proc validateName(name: string): DOMResult[void] =
  if not name.matchNameProduction():
    return errDOMException("Invalid character in name", "InvalidCharacterError")
  ok()

proc validateQName(qname: string): DOMResult[void] =
  if not qname.matchQNameProduction():
    return errDOMException("Invalid character in qualified name",
      "InvalidCharacterError")
  ok()

proc baseURL*(document: Document): URL =
  #TODO frozen base url...
  var href = ""
  for base in document.elementDescendants(TAG_BASE):
    if base.attrb(satHref):
      href = base.attr(satHref)
  if href == "":
    return document.url
  let url = parseURL0(href, some(document.url))
  if url == nil:
    return document.url
  return url

proc parseURL0*(document: Document; s: string): URL =
  #TODO encodings
  return parseURL0(s, some(document.baseURL))

proc parseURL*(document: Document; s: string): Opt[URL] =
  #TODO encodings
  let url = document.parseURL0(s)
  if url == nil:
    return err()
  ok(url)

func title*(document: Document): string {.jsfget.} =
  if (let title = document.findFirst(TAG_TITLE); title != nil):
    return title.childTextContent.stripAndCollapse()
  return ""

proc `title=`(document: Document; s: sink string) {.jsfset: "title".} =
  var title = document.findFirst(TAG_TITLE)
  if title == nil:
    let head = document.head
    if head == nil:
      return
    title = document.newHTMLElement(TAG_TITLE)
    head.append(title)
  title.replaceAll(s)

proc invalidateCollections(document: Document) =
  for id in document.liveCollections:
    cast[Collection](id).invalid = true

#TODO options/custom elements
proc createElement(document: Document; localName: string): DOMResult[Element]
    {.jsfunc.} =
  ?localName.validateName()
  let localName = if not document.isxml:
    localName.toAtomLower()
  else:
    localName.toAtom()
  let namespace = if not document.isxml:
    #TODO or content type is application/xhtml+xml
    Namespace.HTML
  else:
    NO_NAMESPACE
  return ok(document.newElement(localName, namespace))

proc validateAndExtract(ctx: JSContext; document: Document; qname: string;
    namespace, prefixOut, localNameOut: var CAtom): DOMResult[void] =
  ?qname.validateQName()
  if namespace == satUempty.toAtom():
    namespace = CAtomNull
  var prefix = ""
  var localName = qname.until(':')
  if localName.len < qname.len:
    prefix = move(localName)
    localName = qname.substr(prefix.len + 1)
  if namespace == CAtomNull and prefix != "":
    return errDOMException("Got namespace prefix, but no namespace",
      "NamespaceError")
  let sns = namespace.toStaticAtom()
  if prefix == "xml" and sns != satNamespaceXML:
    return errDOMException("Expected XML namespace", "NamespaceError")
  if (qname == "xmlns" or prefix == "xmlns") != (sns == satNamespaceXMLNS):
    return errDOMException("Expected XMLNS namespace", "NamespaceError")
  prefixOut = if prefix == "": CAtomNull else: prefix.toAtom()
  localNameOut = localName.toAtom()
  ok()

proc createElementNS(ctx: JSContext; document: Document; namespace: CAtom;
    qname: string): DOMResult[Element] {.jsfunc.} =
  var namespace = namespace
  var prefix, localName: CAtom
  ?ctx.validateAndExtract(document, qname, namespace, prefix, localName)
  #TODO custom elements (is)
  return ok(document.newElement(localName, namespace, prefix))

proc createDocumentFragment(document: Document): DocumentFragment {.jsfunc.} =
  return newDocumentFragment(document)

proc createDocumentType(implementation: var DOMImplementation; qualifiedName,
    publicId, systemId: string): DOMResult[DocumentType] {.jsfunc.} =
  ?qualifiedName.validateQName()
  let document = implementation.document
  return ok(document.newDocumentType(qualifiedName, publicId, systemId))

proc createDocument(ctx: JSContext; implementation: var DOMImplementation;
    namespace: CAtom; qname0: JSValueConst = JS_NULL;
    doctype = none(DocumentType)): DOMResult[XMLDocument] {.jsfunc.} =
  let document = newXMLDocument()
  var qname = ""
  if not JS_IsNull(qname0):
    ?ctx.fromJS(qname0, qname)
  let element = if qname != "":
    ?ctx.createElementNS(document, namespace, qname)
  else:
    nil
  if doctype.isSome:
    document.append(doctype.get)
  if element != nil:
    document.append(element)
  document.origin = implementation.document.origin
  case namespace.toStaticAtom()
  of satNamespaceHTML: document.contentType = satApplicationXmlHtml
  of satNamespaceSVG: document.contentType = satImageSvgXml
  else: discard
  return ok(document)

proc createHTMLDocument(implementation: var DOMImplementation;
    title = none(string)): Document {.jsfunc.} =
  let doc = newDocument()
  doc.contentType = satTextHtml
  doc.append(doc.newDocumentType("html", "", ""))
  let html = doc.newHTMLElement(TAG_HTML)
  doc.append(html)
  let head = doc.newHTMLElement(TAG_HEAD)
  html.append(head)
  if title.isSome:
    let titleElement = doc.newHTMLElement(TAG_TITLE)
    titleElement.append(doc.newText(title.get))
    head.append(titleElement)
  html.append(doc.newHTMLElement(TAG_BODY))
  doc.origin = implementation.document.origin
  return doc

proc hasFeature(implementation: var DOMImplementation): bool {.jsfunc.} =
  return true

proc createTextNode(document: Document; data: sink string): Text {.jsfunc.} =
  return newText(document, data)

proc append(ctx: JSContext; this: Document; nodes: varargs[JSValueConst]):
    Err[DOMException] {.jsfunc.} =
  return ctx.appendImpl(this, nodes)

proc replaceChildren(ctx: JSContext; this: Document;
    nodes: varargs[JSValueConst]): Err[DOMException] {.jsfunc.} =
  return ctx.replaceChildrenImpl(this, nodes)

const (ReflectTable, TagReflectMap, ReflectAllStartIndex) = (func(): (
    seq[ReflectEntry],
    Table[TagType, seq[int16]],
    int16) =
  var i: int16 = 0
  while i < ReflectTable0.len:
    let x = ReflectTable0[i]
    result[0].add(x)
    if x.tags == AllTagTypes:
      break
    for tag in result[0][i].tags:
      result[1].mgetOrPut(tag, @[]).add(i)
    assert result[0][i].tags.len != 0
    inc i
  result[2] = i
  while i < ReflectTable0.len:
    let x = ReflectTable0[i]
    assert x.tags == AllTagTypes
    result[0].add(x)
    inc i
)()

proc jsReflectGet(ctx: JSContext; this: JSValueConst; magic: cint): JSValue
    {.cdecl.} =
  let entry = ReflectTable[uint16(magic)]
  var element: Element
  if ctx.fromJS(this, element).isErr:
    return JS_EXCEPTION
  if element.tagType notin entry.tags:
    return JS_ThrowTypeError(ctx, "Invalid tag type %s", element.tagType)
  case entry.t
  of rtStr: return ctx.toJS(element.attr(entry.attrname))
  of rtBool: return ctx.toJS(element.attrb(entry.attrname))
  of rtLong: return ctx.toJS(element.attrl(entry.attrname).get(entry.i))
  of rtUlong: return ctx.toJS(element.attrul(entry.attrname).get(entry.u))
  of rtUlongGz: return ctx.toJS(element.attrulgz(entry.attrname).get(entry.u))
  of rtFunction: return JS_NULL

proc jsReflectSet(ctx: JSContext; this, val: JSValueConst; magic: cint): JSValue
    {.cdecl.} =
  var element: Element
  if ctx.fromJS(this, element).isErr:
    return JS_EXCEPTION
  let entry = ReflectTable[uint16(magic)]
  if element.tagType notin entry.tags:
    return JS_ThrowTypeError(ctx, "Invalid tag type %s", element.tagType)
  case entry.t
  of rtStr:
    var x: string
    if ctx.fromJS(val, x).isOk:
      element.attr(entry.attrname, x)
  of rtBool:
    var x: bool
    if ctx.fromJS(val, x).isOk:
      if x:
        element.attr(entry.attrname, "")
      else:
        let i = element.findAttr(entry.attrname.toAtom())
        if i != -1:
          ctx.delAttr(element, i)
  of rtLong:
    var x: int32
    if ctx.fromJS(val, x).isOk:
      element.attrl(entry.attrname, x)
  of rtUlong:
    var x: uint32
    if ctx.fromJS(val, x).isOk:
      element.attrul(entry.attrname, x)
  of rtUlongGz:
    var x: uint32
    if ctx.fromJS(val, x).isOk:
      element.attrulgz(entry.attrname, x)
  of rtFunction:
    return ctx.eventReflectSet0(element, val, magic, jsReflectSet, entry.ctype)
  return JS_DupValue(ctx, val)

func findMagic(ctype: StaticAtom): cint =
  for i in ReflectAllStartIndex ..< int16(ReflectTable.len):
    let entry = ReflectTable[i]
    assert entry.tags == AllTagTypes
    if ReflectTable[i].t == rtFunction and ReflectTable[i].ctype == ctype:
      return cint(i)
  -1

proc reflectEvent(document: Document; target: EventTarget;
    name, ctype: StaticAtom; value: string; target2 = none(EventTarget)) =
  let ctx = document.window.jsctx
  let fun = ctx.newFunction(["event"], value)
  assert ctx != nil
  if JS_IsException(fun):
    document.window.logException(document.baseURL)
  else:
    let magic = findMagic(ctype)
    assert magic != -1
    let res = ctx.eventReflectSet0(target, fun, magic, jsReflectSet, ctype,
      target2)
    if JS_IsException(res):
      document.window.logException(document.baseURL)
    JS_FreeValue(ctx, res)
    JS_FreeValue(ctx, fun)

proc applyUASheet*(document: Document) =
  const ua = staticRead"res/ua.css"
  document.uaSheets.add(document.window.parseStylesheet(ua, nil))
  if document.documentElement != nil:
    document.documentElement.invalidate()

proc applyQuirksSheet*(document: Document) =
  if document.window == nil:
    return
  const quirks = staticRead"res/quirk.css"
  document.uaSheets.add(document.window.parseStylesheet(quirks, nil))
  if document.documentElement != nil:
    document.documentElement.invalidate()

proc applyUserSheet*(document: Document; user: string) =
  document.userSheet = document.window.parseStylesheet(user, nil)
  if document.documentElement != nil:
    document.documentElement.invalidate()

#TODO this should be cached & called incrementally
proc applyAuthorSheets*(document: Document) =
  let window = document.window
  if window != nil and window.settings.styling and
      document.documentElement != nil:
    document.authorSheets = @[]
    for elem in document.documentElement.descendants:
      if elem of HTMLStyleElement:
        let style = HTMLStyleElement(elem)
        document.authorSheets.add(style.sheet)
      elif elem of HTMLLinkElement:
        let link = HTMLLinkElement(elem)
        if link.enabled.get(not link.relList.containsIgnoreCase(satAlternate)):
          document.authorSheets.add(link.sheets)
    document.documentElement.invalidate()

proc findAnchor*(document: Document; id: string): Element =
  if id.len == 0:
    return nil
  let id = id.toAtom()
  for child in document.elementDescendants:
    if child.id == id:
      return child
    if child of HTMLAnchorElement and child.name == id:
      return child
  return nil

proc findMetaRefresh*(document: Document): Element =
  for child in document.elementDescendants(TAG_META):
    if child.attr(satHttpEquiv).equalsIgnoreCase("refresh"):
      return child
  return nil

# NodeIterator
proc createNodeIterator(ctx: JSContext; document: Document; root: Node;
    whatToShow = 0xFFFFFFFFu32; filter: JSValueConst = JS_NULL): NodeIterator
    {.jsfunc.} =
  let collection = newCollection[NodeIterator](
    root = root,
    match = nil,
    islive = true,
    childonly = false,
    inclusive = true
  )
  collection.filter = JS_DupValue(ctx, filter)
  collection.ctx = ctx
  collection.match =
    proc(node: Node): bool =
      let n = 1u32 shl (uint32(node.nodeType) - 1)
      if (whatToShow and n) == 0:
        return false
      if JS_IsNull(collection.filter):
        return true
      let ctx = collection.ctx
      let filter = collection.filter
      let node = ctx.toJS(node)
      let val = if JS_IsFunction(ctx, filter):
        JS_Call(ctx, filter, JS_UNDEFINED, 1, node.toJSValueArray())
      else:
        let atom = JS_NewAtom(ctx, cstringConst"acceptNode")
        let val = JS_Invoke(ctx, filter, atom, 1, node.toJSValueArray())
        JS_FreeAtom(ctx, atom)
        val
      JS_FreeValue(ctx, node)
      if JS_IsException(val):
        return false
      var res: uint32
      if ctx.fromJSFree(val, res).isErr:
        return false
      res == uint32(nftAccept)
  return collection

proc referenceNode(this: NodeIterator): Node {.jsfget.} =
  if this.u < uint32(this.getLength()):
    return this.snapshot[this.u]
  nil

proc nextNode(this: NodeIterator): Node {.jsfunc.} =
  let res = this.referenceNode
  if res != nil:
    inc this.u
  return res

proc previousNode(this: NodeIterator): Node {.jsfunc.} =
  if this.u > 0:
    dec this.u
    return this.snapshot[this.u]
  nil

proc detach(this: NodeIterator) {.jsfunc.} =
  discard

# DOMTokenList
proc newDOMTokenList(element: Element; name: StaticAtom): DOMTokenList =
  return DOMTokenList(element: element, localName: name.toAtom())

iterator items*(tokenList: DOMTokenList): CAtom {.inline.} =
  for tok in tokenList.toks:
    yield tok

func length(tokenList: DOMTokenList): int {.jsfget.} =
  return tokenList.toks.len

proc item(ctx: JSContext; tokenList: DOMTokenList; u: uint32): JSValue
    {.jsfunc.} =
  if int64(u) < int64(int.high):
    let i = int(u)
    if i < tokenList.toks.len:
      return ctx.toJS(tokenList.toks[i])
  return JS_NULL

func contains(tokenList: DOMTokenList; a: CAtom): bool =
  return a in tokenList.toks

func containsIgnoreCase(tokenList: DOMTokenList; a: StaticAtom): bool =
  return tokenList.toks.containsIgnoreCase(a)

proc jsContains(tokenList: DOMTokenList; s: string): bool
    {.jsfunc: "contains".} =
  return s.toAtom() in tokenList.toks

func `$`(tokenList: DOMTokenList): string {.jsfunc: "toString".} =
  var s = ""
  for i, tok in tokenList.toks:
    if i != 0:
      s &= ' '
    s &= $tok
  move(s)

proc update(tokenList: DOMTokenList) =
  if not tokenList.element.attrb(tokenList.localName) and
      tokenList.toks.len == 0:
    return
  tokenList.element.attr(tokenList.localName, $tokenList)

proc validateDOMToken(ctx: JSContext; tok: JSValueConst): DOMResult[CAtom] =
  var res: string
  ?ctx.fromJS(tok, res)
  if res == "":
    return errDOMException("Got an empty string", "SyntaxError")
  if AsciiWhitespace in res:
    return errDOMException("Got a string containing whitespace",
      "InvalidCharacterError")
  return ok(res.toAtom())

proc add(ctx: JSContext; tokenList: DOMTokenList;
    tokens: varargs[JSValueConst]): Err[DOMException] {.jsfunc.} =
  var toks: seq[CAtom] = @[]
  for tok in tokens:
    toks.add(?ctx.validateDOMToken(tok))
  tokenList.toks.add(toks)
  tokenList.update()
  return ok()

proc remove(ctx: JSContext; tokenList: DOMTokenList;
    tokens: varargs[JSValueConst]): Err[DOMException] {.jsfunc.} =
  var toks: seq[CAtom] = @[]
  for tok in tokens:
    toks.add(?ctx.validateDOMToken(tok))
  for tok in toks:
    let i = tokenList.toks.find(tok)
    if i != -1:
      tokenList.toks.delete(i)
  tokenList.update()
  return ok()

proc toggle(ctx: JSContext; tokenList: DOMTokenList; token: JSValueConst;
    force = none(bool)): DOMResult[bool] {.jsfunc.} =
  let token = ?ctx.validateDOMToken(token)
  let i = tokenList.toks.find(token)
  if i != -1:
    if not force.get(false):
      tokenList.toks.delete(i)
      tokenList.update()
      return ok(false)
    return ok(true)
  if force.get(true):
    tokenList.toks.add(token)
    tokenList.update()
    return ok(true)
  return ok(false)

proc replace(ctx: JSContext; tokenList: DOMTokenList;
    token, newToken: JSValueConst): DOMResult[bool] {.jsfunc.} =
  let token = ?ctx.validateDOMToken(token)
  let newToken = ?ctx.validateDOMToken(newToken)
  let i = tokenList.toks.find(token)
  if i == -1:
    return ok(false)
  tokenList.toks[i] = newToken
  tokenList.update()
  return ok(true)

const SupportedTokensMap = {
  satRel: @[
    "alternate", "dns-prefetch", "icon", "manifest", "modulepreload",
    "next", "pingback", "preconnect", "prefetch", "preload", "search",
    "stylesheet"
  ]
}

func supports(tokenList: DOMTokenList; token: string):
    JSResult[bool] {.jsfunc.} =
  let localName = tokenList.localName.toStaticAtom()
  for it in SupportedTokensMap:
    if it[0] == localName:
      let lowercase = token.toLowerAscii()
      return ok(lowercase in it[1])
  return errTypeError("No supported tokens defined for attribute")

func value(tokenList: DOMTokenList): string {.jsfget.} =
  return $tokenList

proc getter(ctx: JSContext; this: DOMTokenList; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  if ctx.fromJS(atom, u).isOk:
    return ctx.item(this, u).uninitIfNull()
  return JS_UNINITIALIZED

proc reflectTokens(this: DOMTokenList; value: Option[string]) =
  this.toks.setLen(0)
  if value.isSome:
    for x in value.get.split(AsciiWhitespace):
      if x != "":
        let a = x.toAtom()
        if a notin this:
          this.toks.add(a)

# DOMStringMap
proc delete(ctx: JSContext; map: DOMStringMap; name: string): bool {.jsfunc.} =
  let name = ("data-" & name.camelToKebabCase()).toAtom()
  let i = map.target.findAttr(name)
  if i != -1:
    ctx.delAttr(map.target, i)
  return i != -1

proc getter(ctx: JSContext; map: DOMStringMap; name: string): JSValue
    {.jsgetownprop.} =
  let name = ("data-" & name.camelToKebabCase()).toAtom()
  let i = map.target.findAttr(name)
  if i != -1:
    return ctx.toJS(map.target.attrs[i].value)
  return JS_UNINITIALIZED

proc setter(map: DOMStringMap; name, value: string): Err[DOMException]
    {.jssetprop.} =
  var washy = false
  for c in name:
    if not washy or c notin AsciiLowerAlpha:
      washy = c == '-'
      continue
    return errDOMException("Lower case after hyphen is not allowed in dataset",
      "InvalidCharacterError")
  let name = "data-" & name.camelToKebabCase()
  ?name.validateName()
  let aname = name.toAtom()
  map.target.attr(aname, value)
  return ok()

func names(ctx: JSContext; map: DOMStringMap): JSPropertyEnumList
    {.jspropnames.} =
  var list = newJSPropertyEnumList(ctx, uint32(map.target.attrs.len))
  for attr in map.target.attrs:
    let k = $attr.localName
    if k.startsWith("data-") and AsciiUpperAlpha notin k:
      list.add(k["data-".len .. ^1].kebabToCamelCase())
  return list

proc dataset(ctx: JSContext; element: HTMLElement): JSValue {.jsfget.} =
  return ctx.getWeakCollection(element, wwmDatalist)

# NodeList
func length(this: NodeList): uint32 {.jsfget.} =
  return uint32(this.getLength())

func item(this: NodeList; u: uint32): Node {.jsfunc.} =
  let i = int(u)
  if i < this.getLength():
    return this.snapshot[i]
  return nil

func getter(ctx: JSContext; this: NodeList; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  if ctx.fromJS(atom, u).isOk:
    return ctx.toJS(this.item(u)).uninitIfNull()
  return JS_UNINITIALIZED

func names(ctx: JSContext; this: NodeList): JSPropertyEnumList {.jspropnames.} =
  let L = this.length
  var list = newJSPropertyEnumList(ctx, L)
  for u in 0 ..< L:
    list.add(u)
  return list

# HTMLCollection
proc length(this: HTMLCollection): uint32 {.jsfget.} =
  return uint32(this.getLength())

func item(this: HTMLCollection; u: uint32): Element {.jsfunc.} =
  if u < this.length:
    return Element(this.snapshot[int(u)])
  return nil

func namedItem(this: HTMLCollection; atom: CAtom): Element {.jsfunc.} =
  this.refreshCollection()
  for it in this.snapshot:
    let it = Element(it)
    if it.id == atom or it.namespaceURI == satNamespaceHTML and it.name == atom:
      return it
  return nil

proc getter(ctx: JSContext; this: HTMLCollection; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  if ctx.fromJS(atom, u).isOk:
    return ctx.toJS(this.item(u)).uninitIfNull()
  var s: CAtom
  if ctx.fromJS(atom, s).isOk:
    return ctx.toJS(this.namedItem(s)).uninitIfNull()
  return JS_UNINITIALIZED

proc names(ctx: JSContext; collection: HTMLCollection): JSPropertyEnumList
    {.jspropnames.} =
  let L = collection.length
  var list = newJSPropertyEnumList(ctx, L)
  var ids = initOrderedSet[CAtom]()
  for u in 0 ..< L:
    list.add(u)
    let element = collection.item(u)
    if element.id != CAtomNull and element.id != satUempty.toAtom():
      ids.incl(element.id)
    if element.namespaceURI == satNamespaceHTML:
      ids.incl(element.name)
  for id in ids:
    list.add($id)
  return list

# HTMLFormControlsCollection
proc namedItem(ctx: JSContext; this: HTMLFormControlsCollection; name: CAtom):
    JSValue {.jsfunc.} =
  let nodes = newCollection[RadioNodeList](
    this.root,
    func(node: Node): bool =
      if not this.match(node):
        return false
      let element = Element(node)
      return element.id == name or
        element.namespaceURI == satNamespaceHTML and element.name == name,
    islive = true,
    childonly = false
  )
  if nodes.getLength() == 0:
    return JS_NULL
  if nodes.getLength() == 1:
    return ctx.toJS(nodes.snapshot[0])
  return ctx.toJS(nodes)

proc names(ctx: JSContext; this: HTMLFormControlsCollection): JSPropertyEnumList
    {.jspropnames.} =
  return ctx.names(HTMLCollection(this))

proc getter(ctx: JSContext; this: HTMLFormControlsCollection; atom: JSAtom):
    JSValue {.jsgetownprop.} =
  var u: uint32
  if ctx.fromJS(atom, u).isOk:
    return ctx.toJS(this.item(u)).uninitIfNull()
  var s: CAtom
  if ctx.fromJS(atom, s).isOk:
    return ctx.toJS(ctx.namedItem(this, s)).uninitIfNull()
  return JS_UNINITIALIZED

# HTMLAllCollection
proc length(this: HTMLAllCollection): uint32 {.jsfget.} =
  return uint32(this.getLength())

func item(this: HTMLAllCollection; u: uint32): Element {.jsfunc.} =
  let i = int(u)
  if i < this.getLength():
    return Element(this.snapshot[i])
  return nil

func getter(ctx: JSContext; this: HTMLAllCollection; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  if ctx.fromJS(atom, u).isOk:
    return ctx.toJS(this.item(u)).uninitIfNull()
  return JS_UNINITIALIZED

func names(ctx: JSContext; this: HTMLAllCollection): JSPropertyEnumList
    {.jspropnames.} =
  let L = this.length
  var list = newJSPropertyEnumList(ctx, L)
  for u in 0 ..< L:
    list.add(u)
  return list

proc all(ctx: JSContext; document: Document): JSValue {.jsfget.} =
  if document.cachedAll == nil:
    document.cachedAll = newCollection[HTMLAllCollection](
      root = document,
      match = isElement,
      islive = true,
      childonly = false
    )
    let val = ctx.toJS(document.cachedAll)
    JS_SetIsHTMLDDA(ctx, val)
    return val
  return ctx.toJS(document.cachedAll)

# Location
proc newLocation*(window: Window): Location =
  let location = Location(window: window)
  let ctx = window.jsctx
  if ctx != nil:
    let val = ctx.toJS(location)
    let valueOf0 = ctx.getOpaque().valRefs[jsvObjectPrototypeValueOf]
    let valueOf = JS_DupValue(ctx, valueOf0)
    doAssert ctx.defineProperty(val, "valueOf", valueOf) != dprException
    doAssert ctx.defineProperty(val, "toPrimitive",
      JS_UNDEFINED) != dprException
    #TODO [[DefaultProperties]]
    JS_FreeValue(ctx, val)
  return location

func document(location: Location): Document =
  return location.window.document

proc url(location: Location): URL =
  let document = location.document
  if document != nil:
    return document.url
  return newURL("about:blank").get

# Note: we do not implement security checks (as documents are in separate
# windows anyway).
proc `$`(location: Location): string {.jsuffunc: "toString".} =
  return location.url.serialize()

proc href(location: Location): string {.jsuffget.} =
  return $location

proc setHref(location: Location; s: string): Err[JSError]
    {.jsfset: "href".} =
  if location.document == nil:
    return ok()
  return location.document.setLocation(s)

proc assign(location: Location; s: string): Err[JSError] {.jsuffunc.} =
  location.setHref(s)

proc replace(location: Location; s: string): Err[JSError] {.jsuffunc.} =
  location.setHref(s)

proc reload(location: Location) {.jsuffunc.} =
  if location.document == nil:
    return
  location.document.window.navigate(location.url)

proc origin(location: Location): string {.jsuffget.} =
  return location.url.jsOrigin

proc protocol(location: Location): string {.jsuffget.} =
  return location.url.protocol

proc protocol(location: Location; s: string): Err[DOMException] {.jsfset.} =
  let document = location.document
  if document == nil:
    return
  let copyURL = newURL(location.url)
  copyURL.setProtocol(s)
  if copyURL.schemeType notin {stHttp, stHttps}:
    return errDOMException("Invalid URL", "SyntaxError")
  document.window.navigate(copyURL)
  return ok()

proc host(location: Location): string {.jsuffget.} =
  return location.url.host

proc setHost(location: Location; s: string) {.jsfset: "host".} =
  let document = location.document
  if document == nil:
    return
  let copyURL = newURL(location.url)
  copyURL.setHost(s)
  document.window.navigate(copyURL)

proc hostname(location: Location): string {.jsuffget.} =
  return location.url.hostname

proc setHostname(location: Location; s: string) {.jsfset: "hostname".} =
  let document = location.document
  if document == nil:
    return
  let copyURL = newURL(location.url)
  copyURL.setHostname(s)
  document.window.navigate(copyURL)

proc port(location: Location): string {.jsuffget.} =
  return location.url.port

proc setPort(location: Location; s: string) {.jsfset: "port".} =
  let document = location.document
  if document == nil:
    return
  let copyURL = newURL(location.url)
  copyURL.setPort(s)
  document.window.navigate(copyURL)

proc pathname(location: Location): string {.jsuffget.} =
  return location.url.pathname

proc setPathname(location: Location; s: string) {.jsfset: "pathname".} =
  let document = location.document
  if document == nil:
    return
  let copyURL = newURL(location.url)
  copyURL.setPathname(s)
  document.window.navigate(copyURL)

proc search(location: Location): string {.jsuffget.} =
  return location.url.search

proc setSearch(location: Location; s: string) {.jsfset: "search".} =
  let document = location.document
  if document == nil:
    return
  let copyURL = newURL(location.url)
  copyURL.setSearch(s)
  document.window.navigate(copyURL)

proc hash(location: Location): string {.jsuffget.} =
  return location.url.hash

proc setHash(location: Location; s: string) {.jsfset: "hash".} =
  let document = location.document
  if document == nil:
    return
  let copyURL = newURL(location.url)
  copyURL.setHash(s)
  document.window.navigate(copyURL)

# Attr
func jsOwnerElement(attr: Attr): Element {.jsfget: "ownerElement".} =
  if attr.ownerElement of AttrDummyElement:
    return nil
  return attr.ownerElement

func ownerDocument(attr: Attr): Document {.jsfget.} =
  return attr.ownerElement.ownerDocument

func data(attr: Attr): lent AttrData =
  return attr.ownerElement.attrs[attr.dataIdx]

proc namespaceURI(attr: Attr): CAtom {.jsfget.} =
  return attr.data.namespace

proc prefix(attr: Attr): CAtom {.jsfget.} =
  return attr.data.prefix

proc localName(attr: Attr): CAtom {.jsfget.} =
  return attr.data.localName

proc value(attr: Attr): string {.jsfget.} =
  return attr.data.value

func name(attr: Attr): CAtom {.jsfget.} =
  return attr.data.qualifiedName

proc setValue(attr: Attr; s: string) {.jsfset: "value".} =
  attr.ownerElement.attr(attr.data.qualifiedName, s)

# NamedNodeMap
func findAttr(map: NamedNodeMap; dataIdx: int): int =
  for i, attr in map.attrlist.mypairs:
    if attr.dataIdx == dataIdx:
      return i
  return -1

proc getAttr(map: NamedNodeMap; dataIdx: int): Attr =
  let i = map.findAttr(dataIdx)
  if i != -1:
    return map.attrlist[i]
  let attr = Attr(
    internalNext: map.element.document,
    dataIdx: dataIdx,
    ownerElement: map.element
  )
  map.attrlist.add(attr)
  return attr

proc getNamedItem(map: NamedNodeMap; qualifiedName: CAtom): Attr {.jsfunc.} =
  let i = map.element.findAttr(qualifiedName)
  if i != -1:
    return map.getAttr(i)
  return nil

proc getNamedItemNS(map: NamedNodeMap; namespace, localName: CAtom): Attr
    {.jsfunc.} =
  let i = map.element.findAttrNS(namespace, localName)
  if i != -1:
    return map.getAttr(i)
  return nil

func length(map: NamedNodeMap): uint32 {.jsfget.} =
  return uint32(map.element.attrs.len)

proc item(map: NamedNodeMap; i: uint32): Attr {.jsfunc.} =
  if int(i) < map.element.attrs.len:
    return map.getAttr(int(i))
  return nil

proc getter(ctx: JSContext; map: NamedNodeMap; atom: JSAtom): Opt[Attr]
    {.jsgetownprop.} =
  var u: uint32
  if ctx.fromJS(atom, u).isOk:
    return ok(map.item(u))
  var s: CAtom
  ?ctx.fromJS(atom, s)
  return ok(map.getNamedItem(s))

func names(ctx: JSContext; map: NamedNodeMap): JSPropertyEnumList
    {.jspropnames.} =
  let len = if map.element.namespaceURI == satNamespaceHTML:
    uint32(map.attrlist.len + map.element.attrs.len)
  else:
    uint32(map.attrlist.len)
  var list = newJSPropertyEnumList(ctx, len)
  for u in 0 ..< len:
    list.add(u)
  let element = map.element
  for attr in element.attrs:
    let name = attr.qualifiedName
    if element.namespaceURI == satNamespaceHTML and name.toLowerAscii() != name:
      continue
    list.add($name)
  return list

# CharacterData
func length(this: CharacterData): int {.jsfget.} =
  return ($this.data).utf16Len

func previousElementSibling(this: CharacterData): Element {.jsfget.} =
  return this.previousElementSiblingImpl

func nextElementSibling(this: CharacterData): Element {.jsfget.} =
  return this.nextElementSiblingImpl

# https://html.spec.whatwg.org/multipage/dynamic-markup-insertion.html#document-write-steps
proc write(ctx: JSContext; document: Document; args: varargs[JSValueConst]):
    Err[DOMException] {.jsfunc.} =
  if document.isxml:
    return errDOMException("document.write not supported in XML documents",
      "InvalidStateError")
  if document.throwOnDynamicMarkupInsertion > 0:
    return errDOMException("throw-on-dynamic-markup-insertion counter > 0",
      "InvalidStateError")
  if document.activeParserWasAborted:
    return ok()
  assert document.parser != nil
  #TODO if insertion point is undefined... (open document)
  if document.writeBuffers.len == 0:
    return ok() #TODO (probably covered by open above)
  let buffer = document.writeBuffers[^1]
  var text = ""
  for arg in args:
    var s: string
    ?ctx.fromJS(arg, s)
    text &= s
  buffer.data &= text
  if document.parserBlockingScript == nil:
    parseDocumentWriteChunkImpl(document.parser)
  return ok()

func firstElementChild(this: Element): Element {.jsfget.} =
  return Node(this).firstElementChild

func firstElementChild(this: Document): Element {.jsfget.} =
  return Node(this).firstElementChild

func lastElementChild(this: Element): Element {.jsfget.} =
  return Node(this).lastElementChild

func lastElementChild(this: Document): Element {.jsfget.} =
  return Node(this).lastElementChild

func lastElementChild(this: DocumentFragment): Element {.jsfget.} =
  return Node(this).lastElementChild

proc childElementCount(this: Element): int {.jsfget.} =
  return this.childElementCountImpl

proc childElementCount(this: Document): int {.jsfget.} =
  return this.childElementCountImpl

proc childElementCount(this: DocumentFragment): int {.jsfget.} =
  return this.childElementCountImpl

proc isFirstVisualNode*(element: Element): bool =
  if element.elIndex == 0:
    let parent = element.parentNode
    for child in parent.childList:
      if child == element:
        return true
      if child of Text and not Text(child).data.onlyWhitespace():
        break
  return false

proc isLastVisualNode*(element: Element): bool =
  let parent = element.parentNode
  for child in parent.rchildList:
    if child == element:
      return true
    if child of Element:
      break
    if child of Text and not Text(child).data.onlyWhitespace():
      break
  return false

func documentElement*(document: Document): Element {.jsfget.} =
  return document.firstElementChild()

proc names(ctx: JSContext; document: Document): JSPropertyEnumList
    {.jspropnames.} =
  var list = newJSPropertyEnumList(ctx, 0)
  #TODO I'm not quite sure why location isn't added, so I'll add it
  # manually for now.
  list.add("location")
  #TODO exposed embed, exposed object
  for child in document.elementDescendants({TAG_FORM, TAG_IFRAME, TAG_IMG}):
    if child.name != CAtomNull and child.name != satUempty.toAtom():
      if child.tagType == TAG_IMG and child.id != CAtomNull and
          child.id != satUempty.toAtom():
        list.add($child.id)
      list.add($child.name)
  return list

proc getter(ctx: JSContext; document: Document; s: string): JSValue
    {.jsgetownprop.} =
  if s.len != 0:
    let id = s.toAtom()
    #TODO exposed embed, exposed object
    for child in document.elementDescendants({TAG_FORM, TAG_IFRAME, TAG_IMG}):
      if child.tagType == TAG_IMG and child.id == id and
          child.name != CAtomNull and child.name != satUempty.toAtom():
        return ctx.toJS(child)
      if child.name == id:
        return ctx.toJS(child)
  return JS_UNINITIALIZED

# Element
proc hash(element: Element): Hash =
  return hash(cast[pointer](element))

func innerHTML(element: Element): string {.jsfget.} =
  #TODO xml
  return element.serializeFragment()

func outerHTML(element: Element): string {.jsfget.} =
  #TODO xml
  result = ""
  result.serializeFragmentInner(element, TAG_UNKNOWN)

func tagTypeNoNS(element: Element): TagType =
  return element.localName.toTagType()

func tagType*(element: Element; namespace = satNamespaceHTML): TagType =
  if element.namespaceURI != namespace:
    return TAG_UNKNOWN
  return element.tagTypeNoNS

func tagName(element: Element): string {.jsfget.} =
  result = $element.prefix
  if result.len > 0:
    result &= ':'
  result &= $element.localName
  if element.namespaceURI == satNamespaceHTML:
    result = result.toUpperAscii()

proc normalizeAttrQName(element: Element; qualifiedName: CAtom): CAtom =
  if element.namespaceURI == satNamespaceHTML and not element.document.isxml:
    return qualifiedName.toLowerAscii()
  return qualifiedName

func findAttr(element: Element; qualifiedName: CAtom): int =
  let qualifiedName = element.normalizeAttrQName(qualifiedName)
  for i, attr in element.attrs.mypairs:
    if attr.qualifiedName == qualifiedName:
      return i
  return -1

func findAttrNS(element: Element; namespace, localName: CAtom): int =
  for i, attr in element.attrs.mypairs:
    if attr.namespace == namespace and attr.localName == localName:
      return i
  return -1

func hasAttributes(element: Element): bool {.jsfunc.} =
  return element.attrs.len > 0

proc attributes(ctx: JSContext; element: Element): JSValue {.jsfget.} =
  return ctx.getWeakCollection(element, wwmAttributes)

proc cachedAttributes(ctx: JSContext; element: Element): NamedNodeMap =
  let this = ctx.toJS(element)
  let res = ctx.getWeak(wwmAttributes, this)
  JS_FreeValue(ctx, this)
  var map: NamedNodeMap
  if ctx.fromJSFree(res, map).isErr:
    return nil
  return map

proc hasAttribute(element: Element; qualifiedName: CAtom): bool {.jsfunc.} =
  return element.findAttr(qualifiedName) != -1

proc hasAttributeNS(element: Element; namespace, localName: CAtom): bool
    {.jsfunc.} =
  return element.findAttrNS(namespace, localName) != -1

func getAttribute(ctx: JSContext; element: Element; qualifiedName: CAtom):
    JSValue {.jsfunc.} =
  let i = element.findAttr(qualifiedName)
  if i != -1:
    return ctx.toJS(element.attrs[i].value)
  return JS_NULL

func getAttributeNS(ctx: JSContext; element: Element;
    namespace, localName: CAtom): JSValue {.jsfunc.} =
  let i = element.findAttrNS(namespace, localName)
  if i != -1:
    return ctx.toJS(element.attrs[i].value)
  return JS_NULL

func attr*(element: Element; s: CAtom): lent string =
  let i = element.findAttr(s)
  if i != -1:
    return element.attrs[i].value
  {.cast(noSideEffect).}:
    # the compiler cries if I return string literals :/
    let emptyStr {.global.} = ""
    return emptyStr

func attr*(element: Element; s: StaticAtom): lent string =
  return element.attr(s.toAtom())

func attrl*(element: Element; s: StaticAtom): Opt[int32] =
  return parseInt32(element.attr(s))

func attrulgz*(element: Element; s: StaticAtom): Opt[uint32] =
  let x = parseUInt32(element.attr(s), allowSign = true).get(0)
  if x > 0:
    return ok(x)
  err()

func attrul*(element: Element; s: StaticAtom): Opt[uint32] =
  return parseUInt32(element.attr(s), allowSign = true)

func attrb*(element: Element; s: CAtom): bool =
  return element.findAttr(s) != -1

func attrb*(element: Element; at: StaticAtom): bool =
  return element.attrb(at.toAtom())

proc getElementsByTagName(element: Element; tagName: string): HTMLCollection
    {.jsfunc.} =
  return element.getElementsByTagNameImpl(tagName)

proc getElementsByClassName(element: Element; classNames: string):
    HTMLCollection {.jsfunc.} =
  return element.getElementsByClassNameImpl(classNames)

func children(ctx: JSContext; parentNode: Element): JSValue {.jsfget.} =
  return parentNodeChildrenImpl(ctx, parentNode)

func previousElementSibling*(element: Element): Element {.jsfget.} =
  return element.previousElementSiblingImpl

func nextElementSibling*(element: Element): Element {.jsfget.} =
  return element.nextElementSiblingImpl

func scriptingEnabled(element: Element): bool =
  return element.document.scriptingEnabled

func isSubmitButton*(element: Element): bool =
  if element of HTMLButtonElement:
    return element.attr(satType).equalsIgnoreCase("submit")
  elif element of HTMLInputElement:
    let element = HTMLInputElement(element)
    return element.inputType in {itSubmit, itImage}
  return false

func isButton*(element: Element): bool =
  if element of HTMLButtonElement:
    return true
  if element of HTMLInputElement:
    let element = HTMLInputElement(element)
    return element.inputType in {itSubmit, itButton, itReset, itImage}
  return false

func action*(element: Element): string =
  if element.isSubmitButton():
    if element.attrb(satFormaction):
      return element.attr(satFormaction)
  if element of FormAssociatedElement:
    let element = FormAssociatedElement(element)
    if element.form != nil:
      if element.form.attrb(satAction):
        return element.form.attr(satAction)
  if element of HTMLFormElement:
    return element.attr(satAction)
  return ""

func enctype*(element: Element): FormEncodingType =
  if element of HTMLFormElement:
    # Note: see below, this is not in the standard.
    if element.attrb(satEnctype):
      let s = element.attr(satEnctype)
      return parseEnumNoCase[FormEncodingType](s).get(fetUrlencoded)
  if element.isSubmitButton():
    if element.attrb(satFormenctype):
      let s = element.attr(satFormenctype)
      return parseEnumNoCase[FormEncodingType](s).get(fetUrlencoded)
  if element of FormAssociatedElement:
    let element = FormAssociatedElement(element)
    if (let form = element.form; form != nil):
      if form.attrb(satEnctype):
        let s = form.attr(satEnctype)
        return parseEnumNoCase[FormEncodingType](s).get(fetUrlencoded)
  return fetUrlencoded

func parseFormMethod(s: string): FormMethod =
  return parseEnumNoCase[FormMethod](s).get(fmGet)

func formmethod*(element: Element): FormMethod =
  if element of HTMLFormElement:
    # The standard says nothing about this, but this code path is reached
    # on implicit form submission and other browsers seem to agree on this
    # behavior.
    return parseFormMethod(element.attr(satMethod))
  if element.isSubmitButton():
    if element.attrb(satFormmethod):
      return parseFormMethod(element.attr(satFormmethod))
  if element of FormAssociatedElement:
    let element = FormAssociatedElement(element)
    if element.form != nil:
      if element.form.attrb(satMethod):
        return parseFormMethod(element.form.attr(satMethod))
  return fmGet

proc scrollTo(element: Element) {.jsfunc.} =
  discard #TODO maybe in app mode?

proc scrollIntoView(element: Element) {.jsfunc.} =
  discard #TODO ditto

proc fragmentParsingAlgorithm*(element: Element; s: string): DocumentFragment =
  #TODO xml
  let newChildren = parseHTMLFragmentImpl(element, s)
  let fragment = element.document.newDocumentFragment()
  for child in newChildren:
    fragment.append(child)
  return fragment

proc innerHTML(element: Element; s: string) {.jsfset.} =
  #TODO shadow root
  let fragment = fragmentParsingAlgorithm(element, s)
  let ctx = if element of HTMLTemplateElement:
    HTMLTemplateElement(element).content
  else:
    element
  ctx.replaceAll(fragment)

proc outerHTML(element: Element; s: string): DOMResult[void] {.jsfset.} =
  let parent0 = element.parentNode
  if parent0 == nil:
    return ok()
  if parent0 of Document:
    return errDOMException("outerHTML is disallowed for Document children",
      "NoModificationAllowedError")
  let parent: Element = if parent0 of DocumentFragment:
    element.document.newHTMLElement(TAG_BODY)
  else:
    # neither a document, nor a document fragment => parent must be an
    # element node
    Element(parent0)
  let fragment = fragmentParsingAlgorithm(parent, s)
  return parent.replace(element, fragment)

type InsertAdjacentPosition = enum
  iapBeforeBegin = "beforebegin"
  iapAfterEnd = "afterend"
  iapAfterBegin = "afterbegin"
  iapBeforeEnd = "beforeend"

proc insertAdjacentHTML(this: Element; position, text: string):
    Err[DOMException] {.jsfunc.} =
  let pos0 = parseEnumNoCase[InsertAdjacentPosition](position)
  if pos0.isErr:
    return errDOMException("Invalid position", "SyntaxError")
  let position = pos0.get
  var ctx = this
  if position in {iapBeforeBegin, iapAfterEnd}:
    if this.parentNode of Document or this.parentNode == nil:
      return errDOMException("Parent is not a valid element",
        "NoModificationAllowedError")
    ctx = this.parentElement
  if ctx == nil or not this.document.isxml and ctx.tagType == TAG_HTML:
    ctx = this.document.newHTMLElement(TAG_BODY)
  let fragment = ctx.fragmentParsingAlgorithm(text)
  case position
  of iapBeforeBegin: this.parentNode.insert(fragment, this)
  of iapAfterBegin: this.insert(fragment, this.firstChild)
  of iapBeforeEnd: this.append(fragment)
  of iapAfterEnd: this.parentNode.insert(fragment, this.nextSibling)
  ok()

func hover*(element: Element): bool =
  return element.internalHover

proc setHover*(element: Element; hover: bool) =
  element.internalHover = hover
  element.invalidate(dtHover)

proc parseColor(element: Element; s: string): ARGBColor =
  var ctx = initCSSParser(s)
  #TODO return element style
  # For now we just use white.
  let ec = rgba(255, 255, 255, 255)
  if color := ctx.parseColor():
    if not color.isCell:
      return color.argb
  return ec

proc getBoundingClientRect(element: Element): DOMRect {.jsfunc.} =
  #TODO should be implemented properly in app mode.
  return DOMRect(
    x: 0,
    y: 0,
    width: float64(dummyAttrs.ppc),
    height: float64(dummyAttrs.ppl)
  )

const WindowEvents* = [satLoad, satError, satFocus, satBlur]

proc reflectScriptAttr(element: Element; name: StaticAtom;
    value: Option[string]): bool =
  let document = element.document
  const ScriptEventMap = {
    satOnclick: satClick,
    satOninput: satInput,
    satOnchange: satChange,
    satOnload: satLoad,
    satOnerror: satError,
    satOnfocus: satFocus,
    satOnblur: satBlur,
  }
  for (n, t) in ScriptEventMap:
    if n == name:
      var target = EventTarget(element)
      var target2 = none(EventTarget)
      if element.tagType == TAG_BODY and t in WindowEvents:
        target = document.window
        target2 = option(EventTarget(element))
      document.reflectEvent(target, n, t, value.get(""), target2)
      return true
  false

proc reflectLocalAttr(element: Element; name: StaticAtom;
    value: Option[string]) =
  case element.tagType
  of TAG_INPUT:
    let input = HTMLInputElement(element)
    case name
    of satValue: input.setValue(value.get(""))
    of satChecked: input.setChecked(value.isSome)
    of satType:
      input.inputType = parseEnumNoCase[InputType](value.get("")).get(itText)
    else: discard
  of TAG_OPTION:
    let option = HTMLOptionElement(element)
    if name == satSelected:
      option.selected = value.isSome
  of TAG_BUTTON:
    let button = HTMLButtonElement(element)
    if name == satType:
      button.ctype = parseEnumNoCase[ButtonType](value.get("")).get(btSubmit)
  of TAG_LINK:
    let link = HTMLLinkElement(element)
    if name == satRel:
      link.relList.reflectTokens(value) # do not return
    if name == satDisabled:
      # IE won :(
      if link.enabled.isNone:
        link.document.applyAuthorSheets()
      link.enabled = some(value.isNone)
    if link.isConnected and name in {satHref, satRel, satDisabled}:
      link.fetchStarted = false
      let window = link.document.window
      if window != nil:
        window.loadResource(link)
  of TAG_A:
    let anchor = HTMLAnchorElement(element)
    if name == satRel:
      anchor.relList.reflectTokens(value)
  of TAG_AREA:
    let area = HTMLAreaElement(element)
    if name == satRel:
      area.relList.reflectTokens(value)
  of TAG_CANVAS:
    if element.scriptingEnabled and name in {satWidth, satHeight}:
      let w = element.attrul(satWidth).get(300)
      let h = element.attrul(satHeight).get(150)
      if w <= uint64(int.high) and h <= uint64(int.high):
        let w = int(w)
        let h = int(h)
        let canvas = HTMLCanvasElement(element)
        if canvas.bitmap == nil or canvas.bitmap.width != w or
            canvas.bitmap.height != h:
          let window = element.document.window
          if canvas.ctx2d != nil and canvas.ctx2d.ps != nil:
            let i = window.pendingCanvasCtls.find(canvas.ctx2d)
            window.pendingCanvasCtls.del(i)
            canvas.ctx2d.ps.sclose()
            canvas.ctx2d = nil
          canvas.bitmap = NetworkBitmap(
            contentType: "image/x-cha-canvas",
            imageId: window.getImageId(),
            cacheId: -1,
            width: w,
            height: h
          )
  of TAG_IMG:
    let image = HTMLImageElement(element)
    # https://html.spec.whatwg.org/multipage/images.html#relevant-mutations
    if name == satSrc:
      image.fetchStarted = false
      let window = image.document.window
      if window != nil:
        window.loadResource(image)
  else: discard

proc reflectAttr(element: Element; name: CAtom; value: Option[string]) =
  let name = name.toStaticAtom()
  case name
  of satId: element.id = value.toAtom()
  of satName: element.name = value.toAtom()
  of satClass: element.classList.reflectTokens(value)
  #TODO internalNonce
  of satStyle:
    if value.isSome:
      element.cachedStyle = newCSSStyleDeclaration(element, value.get)
    else:
      element.cachedStyle = nil
  of satUnknown: discard # early return
  elif element.scriptingEnabled and element.reflectScriptAttr(name, value):
    discard
  else:
    element.reflectLocalAttr(name, value)

proc elIndex*(this: Element): int =
  if this.parentNode == nil:
    return -1
  let parent = this.parentElement
  if parent == nil:
    return 0 # <html>
  if parent.childElIndicesInvalid:
    var n = 0
    for element in parent.elementList:
      element.internalElIndex = n
      inc n
    parent.childElIndicesInvalid = false
  return this.internalElIndex

func isPreviousSiblingOf*(this, other: Element): bool =
  return this.parentNode == other.parentNode and this.elIndex <= other.elIndex

proc querySelector(this: Element; q: string): DOMResult[Element] {.jsfunc.} =
  return this.querySelectorImpl(q)

proc querySelectorAll(this: Element; q: string): DOMResult[NodeList]
    {.jsfunc.} =
  return this.querySelectorAllImpl(q)

#TODO custom elements
proc newElement*(document: Document; localName, namespaceURI, prefix: CAtom):
    Element =
  let tagType = localName.toTagType()
  let sns = namespaceURI.toStaticAtom()
  let element: Element = case tagType
  of TAG_INPUT:
    HTMLInputElement()
  of TAG_A:
    let anchor = HTMLAnchorElement(internalNext: document)
    anchor.relList = anchor.newDOMTokenList(satRel)
    anchor
  of TAG_SELECT:
    HTMLSelectElement()
  of TAG_OPTGROUP:
    HTMLOptGroupElement()
  of TAG_OPTION:
    HTMLOptionElement()
  of TAG_H1, TAG_H2, TAG_H3, TAG_H4, TAG_H5, TAG_H6:
    HTMLHeadingElement()
  of TAG_BR:
    HTMLBRElement()
  of TAG_SPAN:
    HTMLSpanElement()
  of TAG_OL:
    HTMLOListElement()
  of TAG_UL:
    HTMLUListElement()
  of TAG_MENU:
    HTMLMenuElement()
  of TAG_LI:
    HTMLLIElement()
  of TAG_STYLE:
    HTMLStyleElement()
  of TAG_LINK:
    let link = HTMLLinkElement(internalNext: document)
    link.relList = link.newDOMTokenList(satRel)
    link
  of TAG_FORM:
    let form = HTMLFormElement(internalNext: document)
    form.relList = form.newDOMTokenList(satRel)
    form
  of TAG_TEMPLATE:
    let templ = HTMLTemplateElement(content: newDocumentFragment(document))
    templ.content.host = templ
    templ
  of TAG_UNKNOWN:
    HTMLUnknownElement()
  of TAG_SCRIPT:
    HTMLScriptElement(forceAsync: true)
  of TAG_BASE:
    HTMLBaseElement()
  of TAG_BUTTON:
    HTMLButtonElement()
  of TAG_TEXTAREA:
    HTMLTextAreaElement()
  of TAG_LABEL:
    HTMLLabelElement()
  of TAG_CANVAS:
    let imageId = if document.window != nil:
      -1
    else:
      document.window.getImageId()
    let bitmap = if document.scriptingEnabled:
      NetworkBitmap(
        contentType: "image/x-cha-canvas",
        imageId: imageId,
        cacheId: -1,
        width: 300,
        height: 150
      )
    else:
      nil
    HTMLCanvasElement(bitmap: bitmap)
  of TAG_IMG:
    HTMLImageElement()
  of TAG_VIDEO:
    HTMLVideoElement()
  of TAG_AUDIO:
    HTMLAudioElement()
  of TAG_AREA:
    let area = HTMLAreaElement(internalNext: document)
    area.relList = area.newDOMTokenList(satRel)
    area
  of TAG_TABLE:
    HTMLTableElement()
  of TAG_CAPTION:
    HTMLTableCaptionElement()
  of TAG_TR:
    HTMLTableRowElement()
  of TAG_TBODY, TAG_THEAD, TAG_TFOOT:
    HTMLTableSectionElement()
  of TAG_META:
    HTMLMetaElement()
  of TAG_IFRAME:
    HTMLIFrameElement()
  of TAG_DETAILS:
    HTMLDetailsElement()
  of TAG_FRAME:
    HTMLFrameElement()
  of TAG_Q, TAG_BLOCKQUOTE:
    HTMLQuoteElement()
  of TAG_DATA:
    HTMLDataElement()
  of TAG_HEAD:
    HTMLHeadElement()
  of TAG_TITLE:
    HTMLTitleElement()
  elif sns == satNamespaceSVG:
    if tagType == TAG_SVG:
      SVGSVGElement()
    else:
      SVGElement()
  else:
    HTMLElement()
  element.localName = localName
  element.namespaceURI = namespaceURI
  element.prefix = prefix
  element.internalNext = document
  element.classList = element.newDOMTokenList(satClassList)
  element.internalElIndex = -1
  return element

proc newElement*(document: Document; localName: CAtom;
    namespace = Namespace.HTML; prefix = NO_PREFIX): Element =
  return document.newElement(localName, namespace.toAtom(), prefix.toAtom())

proc renderBlocking(element: Element): bool =
  if "render" in element.attr(satBlocking).split(AsciiWhitespace):
    return true
  if element of HTMLScriptElement:
    let element = HTMLScriptElement(element)
    if element.ctype == stClassic and element.parserDocument != nil and
        not element.attrb(satAsync) and not element.attrb(satDefer):
      return true
  return false

proc blockRendering(element: Element) =
  let document = element.document
  if document.contentType == satTextHtml and document.body == nil:
    element.document.renderBlockingElements.add(element)

proc invalidate*(element: Element) =
  let valid = element.computed != nil
  element.computed = nil
  if element.document != nil:
    element.document.invalid = true
  if valid:
    for it in element.elementList:
      it.invalidate()

proc resetElement*(element: Element) =
  case element.tagType
  of TAG_INPUT:
    let input = HTMLInputElement(element)
    case input.inputType
    of itCheckbox, itRadio:
      input.setChecked(input.attrb(satChecked))
    of itFile:
      input.files.setLen(0)
    else:
      input.setValue(input.attr(satValue))
    input.invalidate()
  of TAG_SELECT:
    let select = HTMLSelectElement(element)
    select.userValidity = false
    for option in select.options:
      if option.attrb(satSelected):
        option.selected = true
      else:
        option.selected = false
      option.dirty = false
      option.invalidate(dtChecked)
    select.setSelectedness()
  of TAG_TEXTAREA:
    let textarea = HTMLTextAreaElement(element)
    textarea.dirty = false
    textarea.invalidate()
  else: discard

# Returns true if has post-connection steps.
proc elementInsertionSteps(element: Element): bool =
  case element.tagType
  of TAG_OPTION:
    if element.parentElement != nil:
      let parent = element.parentElement
      var select: HTMLSelectElement
      if parent of HTMLSelectElement:
        select = HTMLSelectElement(parent)
      elif parent.tagType == TAG_OPTGROUP and parent.parentElement != nil and
          parent.parentElement of HTMLSelectElement:
        select = HTMLSelectElement(parent.parentElement)
      if select != nil:
        select.setSelectedness()
  of TAG_LINK:
    let window = element.document.window
    if window != nil:
      let link = HTMLLinkElement(element)
      window.loadResource(link)
  of TAG_IMG:
    let window = element.document.window
    if window != nil:
      let image = HTMLImageElement(element)
      window.loadResource(image)
  of TAG_STYLE:
    HTMLStyleElement(element).updateSheet()
  of TAG_SCRIPT:
    return true
  elif element of FormAssociatedElement:
    let element = FormAssociatedElement(element)
    if element.parserInserted:
      return
    element.resetFormOwner()
  false

proc postConnectionSteps(element: Element) =
  let script = HTMLScriptElement(element)
  if script.isConnected and script.parserDocument == nil:
    script.prepare()

proc prepend(ctx: JSContext; this: Element; nodes: varargs[JSValueConst]):
    Err[DOMException] {.jsfunc.} =
  return ctx.prependImpl(this, nodes)

proc append(ctx: JSContext; this: Element; nodes: varargs[JSValueConst]):
    Err[DOMException] {.jsfunc.} =
  return ctx.appendImpl(this, nodes)

proc replaceChildren(ctx: JSContext; this: Element;
    nodes: varargs[JSValueConst]): Err[DOMException] {.jsfunc.} =
  return ctx.replaceChildrenImpl(this, nodes)

proc prepend(ctx: JSContext; this: Document; nodes: varargs[JSValueConst]):
    Err[DOMException] {.jsfunc.} =
  return ctx.prependImpl(this, nodes)

proc delAttr(ctx: JSContext; element: Element; i: int) =
  let name = element.attrs[i].qualifiedName
  let map = ctx.cachedAttributes(element)
  if map != nil:
    # delete from attrlist + adjust indices invalidated
    var j = -1
    for i, attr in map.attrlist.mypairs:
      if attr.dataIdx == i:
        j = i
      elif attr.dataIdx > i:
        dec attr.dataIdx
    if j != -1:
      let attr = map.attrlist[j]
      let data = attr.data
      attr.ownerElement = AttrDummyElement(
        internalNext: attr.ownerElement.document,
        internalElIndex: -1,
        attrs: @[data]
      )
      attr.dataIdx = 0
      map.attrlist.del(j) # ordering does not matter
  element.attrs.delete(i) # ordering matters
  element.reflectAttr(name, none(string))
  element.document.invalidateCollections()
  element.invalidate()

# Returns the attr index if found, or the negation - 1 of an upper bound
# (where a new attr with the passed name may be inserted).
func findAttrOrNext(element: Element; qualName: CAtom): int =
  for i, data in element.attrs.mypairs:
    if data.qualifiedName == qualName:
      return i
    if int(data.qualifiedName) > int(qualName):
      return -(i + 1)
  return -(element.attrs.len + 1)

proc attr*(element: Element; name: CAtom; value: sink string) =
  var i = element.findAttrOrNext(name)
  if i >= 0:
    element.attrs[i].value = value
    element.document.invalidateCollections()
    element.invalidate()
  else:
    i = -(i + 1)
    element.attrs.insert(AttrData(
      qualifiedName: name,
      localName: name,
      value: value
    ), i)
  element.reflectAttr(name, some(element.attrs[i].value))

proc attr*(element: Element; name: StaticAtom; value: sink string) =
  element.attr(name.toAtom(), value)

func cmpAttrName(a: AttrData; b: CAtom): int =
  return cmp(int(a.qualifiedName), int(b))

proc attrns*(element: Element; localName: CAtom; prefix: NamespacePrefix;
    namespace: Namespace; value: sink string) =
  if prefix == NO_PREFIX and namespace == NO_NAMESPACE:
    element.attr(localName, value)
    return
  let namespace = namespace.toAtom()
  let i = element.findAttrNS(namespace, localName)
  var prefixAtom, qualifiedName: CAtom
  if prefix != NO_PREFIX:
    prefixAtom = prefix.toAtom()
    let tmp = $prefix & ':' & $localName
    qualifiedName = tmp.toAtom()
  else:
    qualifiedName = localName
  if i != -1:
    element.attrs[i].prefix = prefixAtom
    element.attrs[i].qualifiedName = qualifiedName
    element.attrs[i].value = value
  else:
    element.attrs.insert(AttrData(
      prefix: prefixAtom,
      localName: localName,
      qualifiedName: qualifiedName,
      namespace: namespace,
      value: value
    ), element.attrs.upperBound(qualifiedName, cmpAttrName))
  element.document.invalidateCollections()
  element.invalidate()
  element.reflectAttr(qualifiedName, some(value))

proc attrl(element: Element; name: StaticAtom; value: int32) =
  element.attr(name, $value)

proc attrul(element: Element; name: StaticAtom; value: uint32) =
  element.attr(name, $value)

proc attrulgz(element: Element; name: StaticAtom; value: uint32) =
  if value > 0:
    element.attrul(name, value)

proc setAttribute(element: Element; qualifiedName: string; value: sink string):
    Err[DOMException] {.jsfunc.} =
  ?qualifiedName.validateName()
  let qualifiedName = if element.namespaceURI == satNamespaceHTML and
      not element.document.isxml:
    qualifiedName.toAtomLower()
  else:
    qualifiedName.toAtom()
  element.attr(qualifiedName, value)
  return ok()

proc setAttributeNS(element: Element; namespace: CAtom; qualifiedName: string;
    value: sink string): Err[DOMException] {.jsfunc.} =
  ?qualifiedName.validateQName()
  let j = qualifiedName.find(':')
  let sprefix = if j != -1: qualifiedName.substr(0, j - 1) else: ""
  let qualifiedName = qualifiedName.toAtom()
  let prefix = sprefix.toAtom()
  let localName = if j == -1:
    qualifiedName
  else:
    ($qualifiedName).substr(j + 1).toAtom()
  if prefix != satUempty and namespace == satUempty or
      prefix == satXml and namespace != satNamespaceXML or
      satXmlns in [prefix, qualifiedName] and namespace != satNamespaceXMLNS or
      satXmlns notin [prefix, qualifiedName] and namespace == satNamespaceXMLNS:
    return errDOMException("Unexpected namespace", "NamespaceError")
  let i = element.findAttrNS(namespace, localName)
  if i != -1:
    element.attrs[i].value = value
  else:
    element.attrs.add(AttrData(
      prefix: prefix,
      localName: localName,
      namespace: namespace,
      qualifiedName: qualifiedName,
      value: value
    ))
  return ok()

proc removeAttribute(ctx: JSContext; element: Element; qualifiedName: CAtom)
    {.jsfunc.} =
  let i = element.findAttr(qualifiedName)
  if i != -1:
    ctx.delAttr(element, i)

proc removeAttributeNS(ctx: JSContext; element: Element;
    namespace, localName: CAtom) {.jsfunc.} =
  let i = element.findAttrNS(namespace, localName)
  if i != -1:
    ctx.delAttr(element, i)

proc toggleAttribute(ctx: JSContext; element: Element; qualifiedName: string;
    force = none(bool)): DOMResult[bool] {.jsfunc.} =
  ?qualifiedName.validateName()
  let qualifiedName = element.normalizeAttrQName(qualifiedName.toAtom())
  if not element.attrb(qualifiedName):
    if force.get(true):
      element.attr(qualifiedName, "")
      return ok(true)
    return ok(false)
  if not force.get(false):
    let i = element.findAttr(qualifiedName)
    if i != -1:
      ctx.delAttr(element, i)
    return ok(false)
  return ok(true)

proc setId(element: Element; id: string) {.jsfset: "id".} =
  element.attr(satId, id)

proc focus(ctx: JSContext; element: Element) {.jsfunc.} =
  let window = ctx.getWindow()
  if window != nil and window.settings.autofocus:
    element.document.setFocus(element)

proc blur(ctx: JSContext; element: Element) {.jsfunc.} =
  let window = ctx.getWindow()
  if window != nil and window.settings.autofocus:
    if element.document.focus == element:
      element.document.setFocus(nil)

proc click(ctx: JSContext; element: Element) {.jsfunc.} =
  #TODO should also trigger click on inputs.
  let event = newEvent(satClick.toAtom(), element, bubbles = true,
    cancelable = true)
  discard ctx.dispatch(element, event)

# DOMRect
func left(rect: DOMRect): float64 {.jsfget.} =
  return min(rect.x, rect.x + rect.width)

func right(rect: DOMRect): float64 {.jsfget.} =
  return max(rect.x, rect.x + rect.width)

func top(rect: DOMRect): float64 {.jsfget.} =
  return min(rect.y, rect.y + rect.height)

func bottom(rect: DOMRect): float64 {.jsfget.} =
  return max(rect.y, rect.y + rect.height)

# CSSStyleDeclaration
#
# To avoid having to invalidate the entire tree on pseudo-class changes,
# each element holds a list of elements their CSS values depend on.
# (This list may include the element itself.) In addition, elements
# store each value valid for dependency d. These are then used for
# checking the validity of StyledNodes.
#
# In other words - say we have to apply the author stylesheets of the
# following document:
#
# <style>
# div:hover { color: red; }
# :not(input:checked) + p { display: none; }
# </style>
# <div>This div turns red on hover.</div>
# <input type=checkbox>
# <p>This paragraph is only shown when the checkbox above is checked.
#
# That produces the following dependency graph (simplified):
# div -> div (hover)
# p -> input (checked)
#
# Then, to check if a node has been invalidated, we just iterate over
# all recorded dependencies of each StyledNode, and check if their
# registered value of the pseudo-class still matches that of its
# associated element.
#
# So in our example, for div we check if div's :hover pseudo-class has
# changed, for p we check whether input's :checked pseudo-class has
# changed.

proc invalidate*(element: Element; dep: DependencyType) =
  if dep in element.selfDepends:
    element.invalidate()
  element.document.styleDependencies[dep].dependedBy.withValue(element, p):
    for it in p[]:
      it.invalidate()

proc findAndDelete(map: var seq[Element]; element: Element) =
  map.del(map.find(element))

proc applyStyleDependencies*(element: Element; depends: DependencyInfo) =
  let document = element.document
  element.selfDepends = {}
  for t, map in document.styleDependencies.mpairs:
    map.dependsOn.withValue(element, p):
      for it in p[]:
        map.dependedBy.mgetOrPut(it, @[]).findAndDelete(element)
      map.dependsOn.del(element)
    for el in depends[t]:
      if el == element:
        element.selfDepends.incl(t)
        continue
      map.dependedBy.mgetOrPut(el, @[]).add(element)
      map.dependsOn.mgetOrPut(element, @[]).add(el)

proc add*(depends: var DependencyInfo; element: Element; t: DependencyType) =
  depends[t].add(element)

proc merge*(a: var DependencyInfo; b: DependencyInfo) =
  for t, it in b:
    for x in it:
      if x notin a[t]:
        a[t].add(x)

proc newCSSStyleDeclaration(element: Element; value: string; computed = false;
    readonly = false): CSSStyleDeclaration =
  # Note: element may be nil
  let inlineRules = value.parseDeclarations()
  var decls: seq[CSSDeclaration] = @[]
  for rule in inlineRules:
    if rule.t != cdtUnknown:
      decls.add(rule)
  return CSSStyleDeclaration(
    decls: inlineRules,
    element: element,
    computed: computed,
    readonly: readonly
  )

proc cssText(this: CSSStyleDeclaration): string {.jsfget.} =
  if this.computed:
    return ""
  result = ""
  for it in this.decls:
    if result.len > 0:
      result &= ' '
    result &= $it

func length(this: CSSStyleDeclaration): uint32 =
  return uint32(this.decls.len)

func item(this: CSSStyleDeclaration; u: uint32): Option[string] =
  if u < this.length:
    return some(this.decls[int(u)].name)
  return none(string)

proc find(this: CSSStyleDeclaration; s: string): int =
  if s.startsWith("--"):
    let v = s.toOpenArray(2, s.high).toAtom()
    for i, decl in this.decls.mypairs:
      if decl.t == cdtVariable and decl.v == v:
        return i
    return -1
  if p := anyPropertyType(s):
    for i, decl in this.decls.mypairs:
      if decl.t == cdtProperty and decl.p == p:
        return i
  return -1

proc getPropertyValue(this: CSSStyleDeclaration; s: string): string {.jsfunc.} =
  if (let i = this.find(s); i != -1):
    var s = ""
    for it in this.decls[i].value:
      s &= $it
    return move(s)
  return ""

proc getter(ctx: JSContext; this: CSSStyleDeclaration; atom: JSAtom):
    JSValue {.jsgetownprop.} =
  var u: uint32
  if ctx.fromJS(atom, u).isOk:
    return ctx.toJS(this.item(u)).uninitIfNull()
  var s: string
  if ctx.fromJS(atom, s).isErr:
    return JS_EXCEPTION
  if s == "cssFloat":
    s = "float"
  if s.isSupportedProperty():
    return ctx.toJS(this.getPropertyValue(s))
  s = camelToKebabCase(s)
  if s.isSupportedProperty():
    return ctx.toJS(this.getPropertyValue(s))
  return JS_UNINITIALIZED

# Consumes toks.
proc setValue(this: CSSStyleDeclaration; i: int; toks: var seq[CSSToken]):
    Err[void] =
  if i notin 0 .. this.decls.high:
    return err()
  # dummyAttrs can be safely used because the result is discarded.
  case this.decls[i].t
  of cdtUnknown: discard
  of cdtProperty:
    var ctx = initCSSParser(toks)
    var dummy: seq[CSSComputedEntry] = @[]
    ?ctx.parseComputedValues0(this.decls[i].p, dummyAttrs, dummy)
  of cdtVariable:
    if parseDeclWithVar0(toks).len == 0:
      return err()
  this.decls[i].value = move(toks)
  return ok()

proc removeProperty(this: CSSStyleDeclaration; name: string): DOMResult[string]
    {.jsfunc.} =
  if this.readonly:
    return errDOMException("Cannot modify read-only declaration",
      "NoModificationAllowedError")
  let name = name.toLowerAscii()
  let value = this.getPropertyValue(name)
  #TODO shorthand
  let i = this.find(name)
  if i != -1:
    this.decls.delete(i)
  return ok(value)

proc checkReadOnly(this: CSSStyleDeclaration): DOMResult[void] =
  if this.readonly:
    return errDOMException("Cannot modify read-only declaration",
      "NoModificationAllowedError")
  ok()

proc setProperty(this: CSSStyleDeclaration; name, value: string):
    DOMResult[void] {.jsfunc.} =
  ?this.checkReadOnly()
  let name = name.toLowerAscii()
  if not name.isSupportedProperty():
    return ok()
  if value == "":
    discard ?this.removeProperty(name)
    return ok()
  var toks = parseComponentValues(value)
  if (let i = this.find(name); i != -1):
    if this.setValue(i, toks).isErr:
      # not err! this does not throw.
      return ok()
  else:
    var decl = initCSSDeclaration(name)
    case decl.t
    of cdtUnknown:
      return ok()
    of cdtProperty:
      var ctx = initCSSParser(toks)
      var dummy: seq[CSSComputedEntry] = @[]
      if ctx.parseComputedValues0(decl.p, dummyAttrs, dummy).isErr:
        return ok()
    of cdtVariable:
      if parseDeclWithVar0(toks).len == 0:
        return err()
    decl.value = move(toks)
    this.decls.add(move(decl))
  this.element.attr(satStyle, $this.decls)
  ok()

proc setter(ctx: JSContext; this: CSSStyleDeclaration; atom: JSAtom;
    value: string): DOMResult[void] {.jssetprop.} =
  ?this.checkReadOnly()
  var u: uint32
  if ctx.fromJS(atom, u).isOk:
    var toks = parseComponentValues(value)
    if this.setValue(int(u), toks).isErr:
      this.element.attr(satStyle, $this.decls)
    return ok()
  var name: string
  ?ctx.fromJS(atom, name)
  if name == "cssFloat":
    name = "float"
  return this.setProperty(name, value)

proc style*(element: Element): CSSStyleDeclaration {.jsfget.} =
  if element.cachedStyle == nil:
    element.cachedStyle = newCSSStyleDeclaration(element, "")
  return element.cachedStyle

proc getComputedStyle*(element: Element; pseudo: PseudoElement): CSSValues =
  var computed = element.computed
  while computed != nil:
    if computed.pseudo == pseudo:
      return computed
    computed = computed.next
  nil

# HTMLElement
proc newHTMLElement*(document: Document; tagType: TagType): HTMLElement =
  let localName = tagType.toAtom()
  return HTMLElement(document.newElement(localName, Namespace.HTML, NO_PREFIX))

func crossOriginImpl(element: HTMLElement): CORSAttribute =
  if not element.attrb(satCrossorigin):
    return caNoCors
  case element.attr(satCrossorigin)
  of "anonymous", "":
    return caAnonymous
  of "use-credentials":
    return caUseCredentials
  else:
    return caAnonymous

# HTMLHyperlinkElementUtils (for <a> and <area>)
proc reinitURL*(element: Element): Opt[URL] =
  if element.attrb(satHref):
    let url = element.document.parseURL(element.attr(satHref))
    if url.isOk and url.get.schemeType != stBlob:
      return url
  return err()

proc hyperlinkGet(ctx: JSContext; this: JSValueConst; magic: cint): JSValue
    {.cdecl.} =
  var element: Element
  if ctx.fromJS(this, element).isErr:
    return JS_EXCEPTION
  let sa = StaticAtom(magic)
  if url := element.reinitURL():
    let href = ctx.toJS(url)
    let res = JS_GetPropertyStr(ctx, href, cstring($sa))
    JS_FreeValue(ctx, href)
    return res
  if sa == satProtocol:
    return ctx.toJS(":")
  return ctx.toJS("")

proc hyperlinkSet(ctx: JSContext; this, val: JSValueConst; magic: cint): JSValue
    {.cdecl.} =
  var element: Element
  if ctx.fromJS(this, element).isErr:
    return JS_EXCEPTION
  let sa = StaticAtom(magic)
  if sa == satHref:
    var s: string
    if ctx.fromJS(val, s).isOk:
      element.attr(satHref, s)
      return JS_DupValue(ctx, val)
    return JS_EXCEPTION
  if url := element.reinitURL():
    let href = ctx.toJS(url)
    let res = JS_SetPropertyStr(ctx, href, cstring($sa), JS_DupValue(ctx, val))
    if res < 0:
      return JS_EXCEPTION
    var outs: string
    if ctx.fromJSFree(href, outs).isOk:
      element.attr(satHref, outs)
  return JS_DupValue(ctx, val)

proc hyperlinkGetProp(ctx: JSContext; element: HTMLElement; a: JSAtom;
    desc: ptr JSPropertyDescriptor): JSValue =
  var s: string
  if ctx.fromJS(a, s).isOk:
    let sa = s.toStaticAtom()
    if sa in {satHref, satOrigin, satProtocol, satUsername, satPassword,
        satHost, satHostname, satPort, satPathname, satSearch, satHash}:
      if desc != nil:
        let u1 = JSCFunctionType(getter_magic: hyperlinkGet)
        let u2 = JSCFunctionType(setter_magic: hyperlinkSet)
        desc.getter = JS_NewCFunction2(ctx, u1.generic,
          cstring(s), 0, JS_CFUNC_getter_magic, cint(sa))
        desc.setter = JS_NewCFunction2(ctx, u2.generic,
          cstring(s), 0, JS_CFUNC_setter_magic, cint(sa))
        desc.value = JS_UNDEFINED
        desc.flags = JS_PROP_GETSET
      return JS_TRUE # dummy value
  return JS_UNINITIALIZED

# <a>
proc getter(ctx: JSContext; this: HTMLAnchorElement; a: JSAtom;
    desc: ptr JSPropertyDescriptor): JSValue {.jsgetownprop.} =
  return ctx.hyperlinkGetProp(this, a, desc)

proc toString(anchor: HTMLAnchorElement): string {.jsfunc.} =
  if href := anchor.reinitURL():
    return $href
  return ""

proc setRelList(anchor: HTMLAnchorElement; s: string) {.jsfset: "relList".} =
  anchor.attr(satRel, s)

# <area>
proc getter(ctx: JSContext; this: HTMLAreaElement; a: JSAtom;
    desc: ptr JSPropertyDescriptor): JSValue {.jsgetownprop.} =
  return ctx.hyperlinkGetProp(this, a, desc)

proc toString(area: HTMLAreaElement): string {.jsfunc.} =
  if href := area.reinitURL():
    return $href
  return ""

proc setRelList(area: HTMLAreaElement; s: string) {.jsfset: "relList".} =
  area.attr(satRel, s)

# <base>
proc href(base: HTMLBaseElement): string {.jsfget.} =
  #TODO with fallback base url
  if url := parseURL(base.attr(satHref)):
    return $url
  return ""

# <button>
func jsForm(this: HTMLButtonElement): HTMLFormElement {.jsfget: "form".} =
  return this.form

proc setType(this: HTMLButtonElement; s: string) {.jsfset: "type".} =
  this.attr(satType, s)

# <canvas>
proc getContext*(jctx: JSContext; this: HTMLCanvasElement; contextId: string;
    options: JSValueConst = JS_UNDEFINED): CanvasRenderingContext2D {.jsfunc.} =
  if contextId == "2d":
    if this.ctx2d == nil:
      let window = jctx.getWindow()
      let loader = window.loader
      let ctx2d = create2DContext(loader, this, this.bitmap, options)
      if ctx2d == nil:
        return nil
      this.ctx2d = ctx2d
      window.pendingCanvasCtls.add(ctx2d)
    return this.ctx2d
  return nil

# Note: the standard says quality should be converted in a strange way for
# backwards compat, but I don't care.
proc toBlob(ctx: JSContext; this: HTMLCanvasElement; callback: JSValueConst;
    contentType = "image/png"; quality = none(float64)) {.jsfunc.} =
  let contentType = contentType.toLowerAscii()
  if not contentType.startsWith("image/") or this.bitmap.cacheId == 0:
    return
  let url0 = newURL("img-codec+" & contentType.after('/') & ":encode")
  if url0.isErr:
    return
  let url = url0.get
  let headers = newHeaders(hgRequest, {
    "Cha-Image-Dimensions": $this.bitmap.width & 'x' & $this.bitmap.height
  })
  if (var quality = quality.get(-1); 0 <= quality and quality <= 1):
    quality *= 99
    quality += 1
    headers.add("Cha-Image-Quality", $quality)
  # callback will go out of scope when we return, so capture a new reference.
  let callback = JS_DupValue(ctx, callback)
  let window = this.document.window
  window.corsFetch(newRequest(
    newURL("img-codec+x-cha-canvas:decode").get,
    httpMethod = hmPost,
    body = RequestBody(t: rbtCache, cacheId: this.bitmap.cacheId)
  )).then(proc(res: JSResult[Response]): FetchPromise =
    if res.isErr:
      return newResolvedPromise(res)
    let res = res.get
    let p = window.corsFetch(newRequest(
      url,
      httpMethod = hmPost,
      headers = headers,
      body = RequestBody(t: rbtOutput, outputId: res.outputId)
    ))
    res.close()
    return p
  ).then(proc(res: JSResult[Response]) =
    if res.isErr:
      if contentType != "image/png":
        # redo as PNG.
        # Note: this sounds dumb, and is dumb, but also standard mandated so
        # whatever.
        ctx.toBlob(this, callback, "image/png") # PNG doesn't understand quality
      else: # the png encoder doesn't work...
        window.console.error("missing/broken PNG encoder")
      JS_FreeValue(ctx, callback)
      return
    res.get.blob().then(proc(blob: JSResult[Blob]) =
      let jsBlob = ctx.toJS(blob)
      let res = JS_CallFree(ctx, callback, JS_UNDEFINED, 1,
        jsBlob.toJSValueArray())
      if JS_IsException(res):
        window.console.error("Exception in canvas toBlob:",
          ctx.getExceptionMsg())
      else:
        JS_FreeValue(ctx, res)
    )
  )

# <form>
func canSubmitImplicitly*(form: HTMLFormElement): bool =
  const BlocksImplicitSubmission = {
    itText, itSearch, itURL, itTel, itEmail, itPassword, itDate, itMonth,
    itWeek, itTime, itDatetimeLocal, itNumber
  }
  var found = false
  for control in form.controls:
    if control of HTMLInputElement:
      let input = HTMLInputElement(control)
      if input.inputType in BlocksImplicitSubmission:
        if found:
          return false
        found = true
    elif control.isSubmitButton():
      return false
  return true

proc setRelList(form: HTMLFormElement; s: string) {.jsfset: "relList".} =
  form.attr(satRel, s)

func elements(form: HTMLFormElement): HTMLFormControlsCollection {.jsfget.} =
  if form.cachedElements == nil:
    form.cachedElements = newCollection[HTMLFormControlsCollection](
      root = form.rootNode,
      match = func(node: Node): bool =
        if node of FormAssociatedElement:
          let element = FormAssociatedElement(node)
          if element.tagType in ListedElements:
            return element.form == form
        return false,
      islive = true,
      childonly = false
    )
  return form.cachedElements

proc getter(ctx: JSContext; this: HTMLFormElement; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  return ctx.getter(this.elements, atom)

func length(this: HTMLFormElement): int {.jsfget.} =
  return this.elements.getLength()

proc reset*(form: HTMLFormElement) =
  for control in form.controls:
    control.resetElement()
    control.invalidate()

# FormAssociatedElement
proc setForm*(element: FormAssociatedElement; form: HTMLFormElement) =
  case element.tagType
  of TAG_INPUT:
    let input = HTMLInputElement(element)
    input.form = form
    form.controls.add(input)
  of TAG_SELECT:
    let select = HTMLSelectElement(element)
    select.form = form
    form.controls.add(select)
  of TAG_BUTTON:
    let button = HTMLButtonElement(element)
    button.form = form
    form.controls.add(button)
  of TAG_TEXTAREA:
    let textarea = HTMLTextAreaElement(element)
    textarea.form = form
    form.controls.add(textarea)
  of TAG_FIELDSET, TAG_OBJECT, TAG_OUTPUT, TAG_IMG:
    discard #TODO
  else: assert false
  form.document.invalidateCollections()

proc resetFormOwner(element: FormAssociatedElement) =
  element.parserInserted = false
  if element.form != nil:
    if element.tagType notin ListedElements:
      return
    let lastForm = element.findAncestor(TAG_FORM)
    if not element.attrb(satForm) and lastForm == element.form:
      return
  element.form = nil
  if element.tagType in ListedElements and element.isConnected:
    let form = element.document.getElementById(element.attr(satForm))
    if form of HTMLFormElement:
      element.setForm(HTMLFormElement(form))
  if element.form == nil:
    for ancestor in element.ancestors:
      if ancestor of HTMLFormElement:
        element.setForm(HTMLFormElement(ancestor))

# <img>
func crossOrigin(element: HTMLImageElement): CORSAttribute {.jsfget.} =
  return element.crossOriginImpl

# <input>
func jsForm(this: HTMLInputElement): HTMLFormElement {.jsfget: "form".} =
  return this.form

func value*(this: HTMLInputElement): lent string =
  if this.internalValue == nil:
    this.internalValue = newRefString("")
  return this.internalValue

func jsValue(ctx: JSContext; this: HTMLInputElement): JSValue
    {.jsfget: "value".} =
  #TODO wat
  return ctx.toJS(this.value)

proc setValue*(this: HTMLInputElement; value: sink string) {.jsfset: "value".} =
  if this.internalValue == nil:
    this.internalValue = newRefString("")
  this.internalValue.s = value
  this.invalidate()

proc setType(this: HTMLInputElement; s: string) {.jsfset: "type".} =
  this.attr(satType, s)

func checked*(input: HTMLInputElement): bool {.inline.} =
  return input.internalChecked

proc setChecked*(input: HTMLInputElement; b: bool) {.jsfset: "checked".} =
  # Note: input elements are implemented as a replaced text, so we must
  # fully invalidate them on checked change.
  if input.inputType == itRadio:
    for radio in input.radiogroup:
      radio.invalidate(dtChecked)
      radio.invalidate()
      radio.internalChecked = false
  input.invalidate(dtChecked)
  input.invalidate()
  input.internalChecked = b

func inputString*(input: HTMLInputElement): RefString =
  case input.inputType
  of itCheckbox, itRadio:
    if input.checked:
      return newRefString("*")
    return newRefString(" ")
  of itSearch, itText, itEmail, itURL, itTel:
    if input.value.len == 20:
      return input.internalValue
    return newRefString(
      input.value.padToWidth(input.attrulgz(satSize).get(20))
    )
  of itPassword:
    let n = input.attrulgz(satSize).get(20)
    return newRefString('*'.repeat(input.value.len).padToWidth(n))
  of itReset:
    if input.attrb(satValue):
      return input.internalValue
    return newRefString("RESET")
  of itSubmit, itButton:
    if input.attrb(satValue):
      return input.internalValue
    return newRefString("SUBMIT")
  of itFile:
    #TODO multiple files?
    let s = if input.files.len > 0: input.files[0].name else: ""
    return newRefString(s.padToWidth(input.attrulgz(satSize).get(20)))
  else:
    return input.internalValue

# <label>
proc control*(label: HTMLLabelElement): FormAssociatedElement {.jsfget.} =
  let f = label.attr(satFor)
  if f != "":
    let elem = label.document.getElementById(f)
    #TODO the supported check shouldn't be needed, just labelable
    if elem of FormAssociatedElement and elem.tagType in LabelableElements:
      return FormAssociatedElement(elem)
    return nil
  for elem in label.elementDescendants(LabelableElements):
    if elem of FormAssociatedElement: #TODO remove this
      return FormAssociatedElement(elem)
    return nil
  return nil

proc form(label: HTMLLabelElement): HTMLFormElement {.jsfget.} =
  let control = label.control
  if control != nil:
    return control.form
  return nil

# <link>
proc setRelList(link: HTMLLinkElement; s: string) {.jsfset: "relList".} =
  link.attr(satRel, s)

# <option>
# https://html.spec.whatwg.org/multipage/form-elements.html#concept-option-disabled
func isDisabled*(option: HTMLOptionElement): bool =
  if option.parentElement of HTMLOptGroupElement and
      option.parentElement.attrb(satDisabled):
    return true
  return option.attrb(satDisabled)

func text(option: HTMLOptionElement): string {.jsfget.} =
  var s = ""
  for child in option.descendants:
    let parent = child.parentElement
    if child of Text and (parent.tagTypeNoNS != TAG_SCRIPT or
        parent.namespaceURI notin [satNamespaceHTML, satNamespaceSVG]):
      s &= Text(child).data
  return s.stripAndCollapse()

func value*(option: HTMLOptionElement): string {.jsfget.} =
  if option.attrb(satValue):
    return option.attr(satValue)
  return option.text

proc setValue(option: HTMLOptionElement; s: string) {.jsfset: "value".} =
  option.attr(satValue, s)

func select*(option: HTMLOptionElement): HTMLSelectElement =
  for anc in option.ancestors:
    if anc of HTMLSelectElement:
      return HTMLSelectElement(anc)
  return nil

proc setSelected*(option: HTMLOptionElement; selected: bool)
    {.jsfset: "selected".} =
  option.invalidate(dtChecked)
  option.selected = selected
  let select = option.select
  if select != nil and not select.attrb(satMultiple):
    var firstOption: HTMLOptionElement = nil
    var prevSelected: HTMLOptionElement = nil
    for option in select.options:
      if firstOption == nil:
        firstOption = option
      if option.selected:
        if prevSelected != nil:
          prevSelected.selected = false
          prevSelected.invalidate(dtChecked)
        prevSelected = option
    if select.attrul(satSize).get(1) == 1 and
        prevSelected == nil and firstOption != nil:
      firstOption.selected = true
      firstOption.invalidate(dtChecked)

# <q>, <blockquote>
proc cite(this: HTMLQuoteElement): string {.jsfget.} =
  var s = this.attr(satCite)
  if url := parseURL(s, some(this.document.url)):
    return $url
  move(s)

proc `cite=`(this: HTMLQuoteElement; s: sink string) {.jsfset: "cite".} =
  this.attr(satCite, s)

# <select>
func displaySize(select: HTMLSelectElement): uint32 =
  return select.attrul(satSize).get(1)

proc setSelectedness(select: HTMLSelectElement) =
  var firstOption: HTMLOptionElement = nil
  var prevSelected: HTMLOptionElement = nil
  if not select.attrb(satMultiple):
    let displaySize = select.displaySize
    for option in select.options:
      if firstOption == nil:
        firstOption = option
      if option.selected:
        if prevSelected != nil:
          prevSelected.selected = false
          prevSelected.invalidate(dtChecked)
        prevSelected = option
    if select.displaySize == 1 and prevSelected == nil and firstOption != nil:
      firstOption.selected = true

func jsForm(this: HTMLSelectElement): HTMLFormElement {.jsfget: "form".} =
  return this.form

func jsType(this: HTMLSelectElement): string {.jsfget: "type".} =
  if this.attrb(satMultiple):
    return "select-multiple"
  return "select-one"

proc names(ctx: JSContext; this: HTMLOptionsCollection): JSPropertyEnumList
    {.jspropnames.} =
  return ctx.names(HTMLCollection(this))

proc getter(ctx: JSContext; this: HTMLOptionsCollection; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  return ctx.getter(HTMLCollection(this), atom)

proc add(ctx: JSContext; this: HTMLOptionsCollection; element: Element;
    before: JSValueConst = JS_NULL): JSValue {.jsfunc.} =
  if not (element of HTMLOptionElement or element of HTMLOptGroupElement):
    return JS_ThrowTypeError(ctx, "Expected option or optgroup element")
  var beforeEl: HTMLElement = nil
  var beforeIdx = -1
  if not JS_IsNull(before) and ctx.fromJS(before, beforeEl).isErr and
      ctx.fromJS(before, beforeIdx).isErr:
    return JS_EXCEPTION
  for it in this.root.ancestors:
    if element == it:
      return JS_ThrowDOMException(ctx, "Can't add ancestor of select",
        "HierarchyRequestError")
  if beforeEl != nil and this.root notin beforeEl:
    return JS_ThrowDOMException(ctx, "select is not a descendant of before",
      "NotFoundError")
  if element != beforeEl:
    if beforeEl == nil:
      let it = this.item(uint32(beforeIdx))
      if it of HTMLElement:
        beforeEl = HTMLElement(it)
    let parent = if beforeEl != nil: beforeEl.parentNode else: this.root
    let res = ctx.toJS(parent.insertBefore(element, option(Node(beforeEl))))
    if JS_IsException(res):
      return res
    JS_FreeValue(ctx, res)
  return JS_UNDEFINED

proc remove(this: HTMLOptionsCollection; i: int32) {.jsfunc.} =
  let element = this.item(uint32(i))
  if element != nil:
    element.remove()

proc length(this: HTMLOptionsCollection): int {.jsfget.} =
  return this.getLength()

proc setLength(this: HTMLOptionsCollection; n: uint32) {.jsfset: "length".} =
  let len = uint32(this.getLength())
  if n > len:
    if n <= 100_000: # LOL
      let parent = this.root
      let document = parent.document
      for i in 0 ..< n - len:
        parent.append(document.newHTMLElement(TAG_OPTION))
  else:
    for i in 0 ..< len - n:
      this.item(uint32(i)).remove()

func jsOptions(this: HTMLSelectElement): HTMLOptionsCollection
    {.jsfget: "options".} =
  if this.cachedOptions == nil:
    this.cachedOptions = newCollection[HTMLOptionsCollection](
      root = this,
      match = func(node: Node): bool =
        return node.isOptionOf(this),
      islive = true,
      childonly = false
    )
  return this.cachedOptions

proc setter(ctx: JSContext; this: HTMLOptionsCollection; u: uint32;
    value: Option[HTMLOptionElement]): DOMResult[void] {.jssetprop.} =
  let element = this.item(u)
  if value.isNone:
    if element != nil:
      element.remove()
    return ok()
  let value = value.get
  let parent = this.root
  if element != nil:
    ?parent.replace(element, value)
  else:
    let L = uint32(this.getLength())
    let document = parent.document
    for i in L ..< u:
      parent.append(document.newHTMLElement(TAG_OPTION))
    parent.append(value)
  return ok()

proc length(this: HTMLSelectElement): int {.jsfget.} =
  return this.jsOptions.getLength()

proc setLength(this: HTMLSelectElement; n: uint32) {.jsfset: "length".} =
  this.jsOptions.setLength(n)

proc getter(ctx: JSContext; this: HTMLSelectElement; u: JSAtom): JSValue
    {.jsgetownprop.} =
  return ctx.getter(this.jsOptions, u)

proc item(this: HTMLSelectElement; u: uint32): Node {.jsfunc.} =
  return this.jsOptions.item(u)

func namedItem(this: HTMLSelectElement; atom: CAtom): Element {.jsfunc.} =
  return this.jsOptions.namedItem(atom)

proc selectedOptions(ctx: JSContext; this: HTMLSelectElement): JSValue
    {.jsfget.} =
  return ctx.getWeakCollection(this, wwmSelectedOptions)

proc selectedIndex*(this: HTMLSelectElement): int {.jsfget.} =
  var i = 0
  for it in this.options:
    if it.selected:
      return i
    inc i
  return -1

proc selectedIndex(this: HTMLOptionsCollection): int {.jsfget.} =
  return HTMLSelectElement(this.root).selectedIndex

proc setSelectedIndex*(this: HTMLSelectElement; n: int)
    {.jsfset: "selectedIndex".} =
  var i = 0
  for it in this.options:
    if i == n:
      it.selected = true
      it.dirty = true
    else:
      it.selected = false
    it.invalidate(dtChecked)
    inc i
  this.document.invalidateCollections()

proc value(this: HTMLSelectElement): string {.jsfget.} =
  for it in this.options:
    if it.selected:
      return it.value
  return ""

proc setValue(this: HTMLSelectElement; value: string) {.jsfset: "value".} =
  var found = false
  for it in this.options:
    if not found and it.value == value:
      found = true
      it.selected = true
      it.dirty = true
    else:
      it.selected = false
    it.invalidate(dtChecked)
  this.document.invalidateCollections()

proc showPicker(this: HTMLSelectElement): Err[DOMException] {.jsfunc.} =
  # Per spec, we should do something if it's being rendered and on
  # transient user activation.
  # If this is ever implemented, then the "is rendered" check must
  # be app mode only.
  return errDOMException("not allowed", "NotAllowedError")

proc add(ctx: JSContext; this: HTMLSelectElement; element: Element;
    before: JSValueConst = JS_NULL): JSValue {.jsfunc.} =
  return ctx.add(this.jsOptions, element, before)

proc remove(ctx: JSContext; this: HTMLSelectElement;
    idx: varargs[JSValueConst]): Opt[void] {.jsfunc.} =
  if idx.len > 0:
    var i: int32
    ?ctx.fromJS(idx[0], i)
    this.jsOptions.remove(i)
  else:
    this.remove()
  ok()

# <style>
proc updateSheet*(this: HTMLStyleElement) =
  let document = this.document
  let window = document.window
  if window != nil:
    this.sheet = window.parseStylesheet(this.textContent, document.baseURL)
    document.applyAuthorSheets()

# <script>
proc finalize(element: HTMLScriptElement) {.jsfin.} =
  if element.scriptResult != nil and element.scriptResult.t == srtScript:
    let script = element.scriptResult.script
    if script.rt != nil and not JS_IsUninitialized(script.record):
      script.free()

proc mark(rt: JSRuntime; element: HTMLScriptElement; markFunc: JS_MarkFunc)
    {.jsmark.} =
  if element.scriptResult != nil and element.scriptResult.t == srtScript:
    let script = element.scriptResult.script
    if script.rt != nil and not JS_IsUninitialized(script.record):
      JS_MarkValue(rt, script.record, markFunc)

func crossOrigin(element: HTMLScriptElement): CORSAttribute {.jsfget.} =
  return element.crossOriginImpl

func referrerpolicy(element: HTMLScriptElement): Option[ReferrerPolicy] =
  if o := strictParseEnum[ReferrerPolicy](element.attr(satReferrerpolicy)):
    return some(o)
  none(ReferrerPolicy)

proc markAsReady(element: HTMLScriptElement; res: ScriptResult) =
  element.scriptResult = res
  if element.onReady != nil:
    element.onReady(element)
    element.onReady = nil
  element.delayingTheLoadEvent = false

proc scriptOnReadyRunInParser(element: HTMLScriptElement) =
  element.readyForParserExec = true

proc scriptOnReadyNoParser(element: HTMLScriptElement) =
  let prepdoc = element.preparationTimeDocument
  if prepdoc.scriptsToExecInOrder == element:
    while prepdoc.scriptsToExecInOrder != nil:
      let script = prepdoc.scriptsToExecInOrder
      if script.scriptResult == nil:
        break
      script.execute()
      let next = prepdoc.scriptsToExecInOrder.next
      prepdoc.scriptsToExecInOrder = next
      if next == nil:
        prepdoc.scriptsToExecInOrderTail = nil

proc scriptOnReadyAsync(element: HTMLScriptElement) =
  let prepdoc = element.preparationTimeDocument
  element.execute()
  var it {.cursor.} = prepdoc.scriptsToExecSoon
  if it == element:
    prepdoc.scriptsToExecSoon = element.next
  else:
    while it != nil:
      if it.next == element:
        it.next = element.next
        break
      it = it.next

proc fetchClassicScript(element: HTMLScriptElement; url: URL;
    cors: CORSAttribute; onComplete: OnCompleteProc): Response =
  if not element.scriptingEnabled:
    element.markAsReady(ScriptResult(t: srtNull))
    return nil
  let window = element.document.window
  let request = createPotentialCORSRequest(url, rdScript, cors)
  request.client = some(window.settings)
  return window.loader.doRequest(request.request)

#TODO settings object
proc fetchExternalModuleGraph(element: HTMLScriptElement; url: URL;
    options: ScriptOptions; onComplete: OnCompleteProc) =
  let window = element.document.window
  if not element.scriptingEnabled:
    element.onComplete(ScriptResult(t: srtNull))
    return
  window.importMapsAllowed = false
  element.fetchSingleModule(
    url,
    rdScript,
    options,
    parseURL("about:client").get,
    isTopLevel = true,
    onComplete = proc(element: HTMLScriptElement; res: ScriptResult) =
      if res.t == srtNull:
        element.onComplete(res)
      else:
        element.fetchDescendantsAndLink(res.script, rdScript, onComplete)
  )

proc logException(window: Window; url: URL) =
  #TODO excludepassword seems pointless?
  window.console.error("Exception in document",
    url.serialize(excludepassword = true), window.jsctx.getExceptionMsg())

proc fetchInlineModuleGraph(element: HTMLScriptElement; sourceText: string;
    url: URL; options: ScriptOptions; onComplete: OnCompleteProc) =
  let window = element.document.window
  let ctx = window.jsctx
  let res = ctx.newJSModuleScript(sourceText, url, options)
  if JS_IsException(res.script.record):
    window.logException(res.script.baseURL)
    element.onComplete(ScriptResult(t: srtNull))
  else:
    element.fetchDescendantsAndLink(res.script, rdScript, onComplete)

proc fetchDescendantsAndLink(element: HTMLScriptElement; script: Script;
    destination: RequestDestination; onComplete: OnCompleteProc) =
  #TODO ummm...
  let window = element.document.window
  let ctx = window.jsctx
  let record = script.record
  if JS_ResolveModule(ctx, record) < 0:
    window.logException(script.baseURL)
    script.free()
    return
  ctx.setImportMeta(record, true)
  script.record = JS_UNINITIALIZED
  script.rt = nil
  let res = JS_EvalFunction(ctx, record) # consumes record
  if JS_IsException(res):
    window.logException(script.baseURL)
    return
  var p: Promise[JSValueConst]
  if ctx.fromJSFree(res, p).isOk:
    p.then(proc(res: JSValueConst) =
      if JS_IsException(res):
        window.logException(script.baseURL)
    )

#TODO settings object
proc fetchSingleModule(element: HTMLScriptElement; url: URL;
    destination: RequestDestination; options: ScriptOptions,
    referrer: URL; isTopLevel: bool; onComplete: OnCompleteProc) =
  let moduleType = "javascript"
  #TODO moduleRequest
  let window = element.document.window
  let settings = window.settings
  let res = settings.moduleMap.get(url, moduleType)
  if res != nil:
    if res.t == srtFetching:
      #TODO await value
      assert false
    element.onComplete(res)
    return
  let destination = moduleType.moduleTypeToRequestDest(destination)
  let mode = if destination in {rdWorker, rdSharedworker, rdServiceworker}:
    rmSameOrigin
  else:
    rmCors
  #TODO client
  #TODO initiator type
  let request = JSRequest(
    request: newRequest(
      url,
      referrer = referrer,
    ),
    destination: destination,
    mode: mode
  )
  #TODO set up module script request
  #TODO performFetch
  let p = window.fetchImpl(request)
  if p.isOk:
    p.get.then(proc(res: JSResult[Response]) =
      let ctx = window.jsctx
      if res.isErr:
        let res = ScriptResult(t: srtNull)
        settings.moduleMap.set(url, moduleType, res, ctx)
        element.onComplete(res)
        return
      let res = res.get
      let contentType = res.getContentType()
      let referrerPolicy = res.getReferrerPolicy()
      res.text().then(proc(s: JSResult[string]) =
        if s.isErr:
          let res = ScriptResult(t: srtNull)
          settings.moduleMap.set(url, moduleType, res, ctx)
          element.onComplete(res)
          return
        if contentType.isJavaScriptType():
          window.currentModuleURL = url
          let res = ctx.newJSModuleScript(s.get, url, options)
          #TODO can't we just return null from newJSModuleScript?
          if JS_IsException(res.script.record):
            window.logException(res.script.baseURL)
            element.onComplete(ScriptResult(t: srtNull))
          else:
            if referrerPolicy.isSome:
              res.script.options.referrerPolicy = referrerPolicy
            # set & onComplete both take ownership
            settings.moduleMap.set(url, moduleType, res.clone(), ctx)
            element.onComplete(res)
        else:
          #TODO non-JS modules
          discard
      )
    )

proc execute*(element: HTMLScriptElement) =
  let document = element.document
  let window = document.window
  if document != element.preparationTimeDocument or window == nil:
    return
  let i = document.renderBlockingElements.find(element)
  if i != -1:
    document.renderBlockingElements.delete(i)
  #TODO this should work eventually (when module & importmap are implemented)
  #assert element.scriptResult != nil
  if element.scriptResult == nil:
    return
  if element.scriptResult.t == srtNull:
    window.fireEvent(satError, element, bubbles = false,
      cancelable = false, trusted = true)
    return
  let needsInc = element.external or element.ctype == stModule
  if needsInc:
    inc document.ignoreDestructiveWrites
  case element.ctype
  of stClassic:
    let oldCurrentScript = document.currentScript
    #TODO not if shadow root
    document.currentScript = element
    if window.jsctx != nil:
      let script = element.scriptResult.script
      let ctx = window.jsctx
      if JS_IsException(script.record):
        window.logException(script.baseURL)
      else:
        let record = script.record
        script.record = JS_UNINITIALIZED
        script.rt = nil
        let ret = JS_EvalFunction(ctx, record) # consumes record
        if JS_IsException(ret):
          window.logException(script.baseURL)
        JS_FreeValue(ctx, ret)
    document.currentScript = oldCurrentScript
  else: discard #TODO
  if needsInc:
    dec document.ignoreDestructiveWrites
  if element.external:
    window.fireEvent(satLoad, element, bubbles = false, cancelable = false,
      trusted = true)

# https://html.spec.whatwg.org/multipage/scripting.html#prepare-the-script-element
proc prepare*(element: HTMLScriptElement) =
  if element.alreadyStarted:
    return
  let parserDocument = element.parserDocument
  element.parserDocument = nil
  if parserDocument != nil and not element.attrb(satAsync):
    element.forceAsync = true
  let window = element.document.window
  let sourceText = element.childTextContent
  if not element.attrb(satSrc) and sourceText == "" or
      not element.isConnected or window == nil:
    return
  let t = element.attr(satType)
  let typeString = if t != "":
    t.strip(chars = AsciiWhitespace)
  elif (let l = element.attr(satLanguage); l != ""):
    "text/" & l
  else:
    "text/javascript"
  if typeString.isJavaScriptType():
    element.ctype = stClassic
  elif typeString.equalsIgnoreCase("module"):
    element.ctype = stModule
  elif typeString.equalsIgnoreCase("importmap"):
    element.ctype = stImportMap
  else:
    return
  if parserDocument != nil:
    element.parserDocument = parserDocument
    element.forceAsync = false
  element.alreadyStarted = true
  element.preparationTimeDocument = element.document
  if parserDocument != nil and parserDocument != element.document or
      not element.scriptingEnabled or
      element.attrb(satNomodule) and element.ctype == stClassic:
    return
  #TODO content security policy
  if element.ctype == stClassic and element.attrb(satEvent) and
      element.attrb(satFor):
    let f = element.attr(satFor).strip(chars = AsciiWhitespace)
    let event = element.attr(satEvent).strip(chars = AsciiWhitespace)
    if not f.equalsIgnoreCase("window") or
        not event.equalsIgnoreCase("onload") and
        not event.equalsIgnoreCase("onload()"):
      return
  let cs = getCharset(element.attr(satCharset))
  let encoding = if cs != CHARSET_UNKNOWN: cs else: element.document.charset
  let classicCORS = element.crossOrigin
  let parserMetadata = if element.parserDocument != nil:
    pmParserInserted
  else:
    pmNotParserInserted
  var options = ScriptOptions(
    nonce: element.internalNonce,
    integrity: element.attr(satIntegrity),
    parserMetadata: parserMetadata,
    referrerpolicy: element.referrerpolicy
  )
  #TODO settings object
  var response: Response = nil
  if element.attrb(satSrc):
    let src = element.attr(satSrc)
    let url = element.document.parseURL0(src)
    element.external = src != "" and element.ctype != stImportMap
    if element.ctype == stImportMap or url == nil:
      window.fireEvent(satError, element, bubbles = false,
        cancelable = false, trusted = true)
      return
    if element.renderBlocking:
      element.blockRendering()
    element.delayingTheLoadEvent = true
    if element in element.document.renderBlockingElements:
      options.renderBlocking = true
    if element.ctype == stClassic:
      response = element.fetchClassicScript(url, classicCORS, markAsReady)
    else: # stModule
      element.fetchExternalModuleGraph(url, options, markAsReady)
  else:
    let baseURL = element.document.baseURL
    case element.ctype
    of stClassic:
      let ctx = element.document.window.jsctx
      let script = ctx.newClassicScript(sourceText, baseURL, options)
      element.markAsReady(script)
    of stModule:
      element.delayingTheLoadEvent = true
      if element.renderBlocking:
        element.blockRendering()
        options.renderBlocking = true
      element.fetchInlineModuleGraph(sourceText, baseURL, options, markAsReady)
    of stImportMap:
      #TODO
      element.markAsReady(ScriptResult(t: srtNull))
  if element.ctype == stClassic and element.attrb(satSrc) or
      element.ctype == stModule:
    let prepdoc = element.preparationTimeDocument
    if element.attrb(satAsync) or element.forceAsync:
      element.next = prepdoc.scriptsToExecSoon
      prepdoc.scriptsToExecSoon = element
      element.onReady = scriptOnReadyAsync
    elif element.parserDocument == nil:
      let tail = prepdoc.scriptsToExecInOrderTail
      if tail != nil:
        tail.next = element
      else:
        prepdoc.scriptsToExecInOrder = element
      prepdoc.scriptsToExecInOrderTail = element
      element.onReady = scriptOnReadyNoParser
    elif element.ctype == stModule or element.attrb(satDefer):
      let tail = element.parserDocument.scriptsToExecOnLoadTail
      if tail != nil:
        tail.next = element
      else:
        element.parserDocument.scriptsToExecOnLoad = element
      element.parserDocument.scriptsToExecOnLoadTail = element
      element.onReady = scriptOnReadyRunInParser
    else:
      element.parserDocument.parserBlockingScript = element
      element.blockRendering()
      element.onReady = scriptOnReadyRunInParser
    if response != nil:
      if response.res != 0:
        element.markAsReady(ScriptResult(t: srtNull))
      else:
        response.resume()
        let source = response.body.readAll().decodeAll(encoding)
        response.body.sclose()
        let script = window.jsctx.newClassicScript(source, response.url,
          options, false)
        element.markAsReady(script)
  else:
    #TODO if stClassic, parserDocument != nil, parserDocument has a style sheet
    # that is blocking scripts, either the parser is an XML parser or a HTML
    # parser with a script level <= 1
    element.execute()

# <table>
func caption(this: HTMLTableElement): Element {.jsfget.} =
  return this.findFirstChildOf(TAG_CAPTION)

proc setCaption(this: HTMLTableElement; caption: HTMLTableCaptionElement):
    DOMResult[void] {.jsfset: "caption".} =
  let old = this.caption
  if old != nil:
    old.remove()
  discard ?this.insertBefore(caption, option(this.firstChild))
  ok()

func tHead(this: HTMLTableElement): Element {.jsfget.} =
  return this.findFirstChildOf(TAG_THEAD)

func tFoot(this: HTMLTableElement): Element {.jsfget.} =
  return this.findFirstChildOf(TAG_TFOOT)

proc setTSectImpl(this: HTMLTableElement; sect: HTMLTableSectionElement;
    tagType: TagType): DOMResult[void] =
  if sect != nil and sect.tagType != tagType:
    return errDOMException("Wrong element type", "HierarchyRequestError")
  let old = this.findFirstChildOf(tagType)
  if old != nil:
    old.remove()
  discard ?this.insertBefore(sect, option(this.firstChild))
  ok()

proc setTHead(this: HTMLTableElement; tHead: HTMLTableSectionElement):
    DOMResult[void] {.jsfset: "tHead".} =
  return this.setTSectImpl(tHead, TAG_THEAD)

proc setTFoot(this: HTMLTableElement; tFoot: HTMLTableSectionElement):
    DOMResult[void] {.jsfset: "tFoot".} =
  return this.setTSectImpl(tFoot, TAG_TFOOT)

proc tBodies(ctx: JSContext; this: HTMLTableElement): JSValue {.jsfget.} =
  return ctx.getWeakCollection(this, wwmTBodies)

proc rows(this: HTMLTableElement): HTMLCollection {.jsfget.} =
  if this.cachedRows == nil:
    this.cachedRows = this.newHTMLCollection(
      match = proc(node: Node): bool =
        if node.parentNode == this or node.parentNode.parentNode == this:
          return node.isRow()
        return false,
      islive = true,
      childonly = false
    )
  return this.cachedRows

proc create(this: HTMLTableElement; tagType: TagType; before: Node):
    Element =
  var element = this.findFirstChildOf(tagType)
  if element == nil:
    element = this.document.newHTMLElement(tagType)
    discard this.insertBefore(element, option(before))
  return element

proc delete(this: HTMLTableElement; tagType: TagType) =
  let element = this.findFirstChildOf(tagType)
  if element != nil:
    element.remove()

proc createCaption(this: HTMLTableElement): Element {.jsfunc.} =
  return this.create(TAG_CAPTION, this.firstChild)

proc createTHead(this: HTMLTableElement): Element {.jsfunc.} =
  let before = this.findFirstChildNotOf({TAG_CAPTION, TAG_COLGROUP})
  return this.create(TAG_THEAD, before)

proc createTBody(this: HTMLTableElement): Element {.jsfunc.} =
  let before = this.findLastChildOf(TAG_TBODY)
  return this.create(TAG_TBODY, before)

proc createTFoot(this: HTMLTableElement): Element {.jsfunc.} =
  return this.create(TAG_TFOOT, nil)

proc deleteCaption(this: HTMLTableElement) {.jsfunc.} =
  this.delete(TAG_CAPTION)

proc deleteTHead(this: HTMLTableElement) {.jsfunc.} =
  this.delete(TAG_THEAD)

proc deleteTFoot(this: HTMLTableElement) {.jsfunc.} =
  this.delete(TAG_TFOOT)

proc insertRow(this: HTMLTableElement; index = -1): DOMResult[Element]
    {.jsfunc.} =
  let nrows = this.rows.getLength()
  if index < -1 or index > nrows:
    return errDOMException("Index out of bounds", "IndexSizeError")
  let tr = this.document.newHTMLElement(TAG_TR)
  if nrows == 0:
    this.createTBody().append(tr)
  elif index == -1 or index == nrows:
    this.rows.item(uint32(nrows) - 1).parentNode.append(tr)
  else:
    let it = this.rows.item(uint32(index))
    discard it.parentNode.insertBefore(tr, option(Node(it)))
  return ok(tr)

proc deleteRow(rows: HTMLCollection; index: int): DOMResult[void] =
  let nrows = rows.getLength()
  if index < -1 or index >= nrows:
    return errDOMException("Index out of bounds", "IndexSizeError")
  if index == -1:
    rows.item(uint32(nrows - 1)).remove()
  elif nrows > 0:
    rows.item(uint32(index)).remove()
  ok()

proc deleteRow(this: HTMLTableElement; index = -1): DOMResult[void] {.jsfunc.} =
  return this.rows.deleteRow(index)

# <tbody>
proc rows(this: HTMLTableSectionElement): HTMLCollection {.jsfget.} =
  if this.cachedRows == nil:
    this.cachedRows = this.newHTMLCollection(
      match = isRow,
      islive = true,
      childonly = true
    )
  return this.cachedRows

proc insertRow(this: HTMLTableSectionElement; index = -1): DOMResult[Element]
    {.jsfunc.} =
  let nrows = this.rows.getLength()
  if index < -1 or index > nrows:
    return errDOMException("Index out of bounds", "IndexSizeError")
  let tr = this.document.newHTMLElement(TAG_TR)
  if index == -1 or index == nrows:
    this.append(tr)
  else:
    discard this.insertBefore(tr, option(Node(this.rows.item(uint32(index)))))
  return ok(tr)

proc deleteRow(this: HTMLTableSectionElement; index = -1): DOMResult[void]
    {.jsfunc.} =
  return this.rows.deleteRow(index)

# <tr>
proc cells(ctx: JSContext; this: HTMLTableRowElement): JSValue {.jsfget.} =
  return ctx.getWeakCollection(this, wwmCells)

func rowIndex(this: HTMLTableRowElement): int {.jsfget.} =
  let table = this.findAncestor(TAG_TABLE)
  if table != nil:
    return HTMLTableElement(table).rows.findNode(this)
  return -1

func sectionRowIndex(this: HTMLTableRowElement): int {.jsfget.} =
  let parent = this.parentElement
  if parent of HTMLTableElement:
    return this.rowIndex
  if parent of HTMLTableSectionElement:
    return HTMLTableSectionElement(parent).rows.findNode(this)
  return -1

# <textarea>
func jsForm(this: HTMLTextAreaElement): HTMLFormElement {.jsfget: "form".} =
  return this.form

proc value*(textarea: HTMLTextAreaElement): string {.jsfget.} =
  if textarea.dirty:
    return textarea.internalValue
  return textarea.childTextContent

proc `value=`*(textarea: HTMLTextAreaElement; s: sink string)
    {.jsfset: "value".} =
  textarea.dirty = true
  textarea.internalValue = s

func textAreaString*(textarea: HTMLTextAreaElement): string =
  result = ""
  let split = textarea.value.split('\n')
  let rows = int(textarea.attrul(satRows).get(1))
  for i in 0 ..< rows:
    let cols = textarea.attrul(satCols).get(20)
    if cols > 2:
      if i < split.len:
        result &= '[' & split[i].padToWidth(cols - 2) & "]\n"
      else:
        result &= '[' & ' '.repeat(cols - 2) & "]\n"
    else:
      result &= "[]\n"

proc defaultValue(textarea: HTMLTextAreaElement): string {.jsfget.} =
  return textarea.textContent

proc `defaultValue=`(textarea: HTMLTextAreaElement; s: sink string)
    {.jsfset: "defaultValue".} =
  textarea.replaceAll(s)

# <title>
proc text(this: HTMLTitleElement): string {.jsfget.} =
  return this.textContent

proc `text=`(this: HTMLTitleElement; s: sink string) {.jsfset: "text".} =
  this.replaceAll(s)

# <video>
func getSrc*(this: HTMLElement): tuple[src, contentType: string] =
  let src = this.attr(satSrc)
  if src != "":
    return (src, "")
  for el in this.elementDescendants(TAG_SOURCE):
    let src = el.attr(satSrc)
    if src != "":
      return (src, el.attr(satType))
  return ("", "")

func getReflectFunctions(tags: openArray[TagType]): seq[TabGetSet] =
  result = @[]
  for tag in tags:
    for i in TagReflectMap.getOrDefault(tag):
      result.add(TabGetSet(
        name: $ReflectTable[i].funcname,
        get: jsReflectGet,
        set: jsReflectSet,
        magic: i
      ))

func getElementReflectFunctions(): seq[TabGetSet] =
  result = @[]
  for i in ReflectAllStartIndex ..< int16(ReflectTable.len):
    let entry = ReflectTable[i]
    assert entry.tags == AllTagTypes
    result.add(TabGetSet(
      name: $ReflectTable[i].funcname,
      get: jsReflectGet,
      set: jsReflectSet,
      magic: i
    ))

proc registerElements(ctx: JSContext; nodeCID: JSClassID) =
  let elementCID = ctx.registerType(Element, parent = nodeCID)
  const extraGetSet = getElementReflectFunctions()
  let htmlElementCID = ctx.registerType(HTMLElement, parent = elementCID,
    hasExtraGetSet = true, extraGetSet = extraGetSet)
  template register(t: typed; tags: openArray[TagType]) =
    const extraGetSet = getReflectFunctions(tags)
    ctx.registerType(t, parent = htmlElementCID, hasExtraGetSet = true,
      extraGetSet = extraGetSet)
  template register(t: typed; tag: TagType) =
    register(t, [tag])
  register(HTMLInputElement, TAG_INPUT)
  register(HTMLAnchorElement, TAG_A)
  register(HTMLSelectElement, TAG_SELECT)
  register(HTMLSpanElement, TAG_SPAN)
  register(HTMLOptGroupElement, TAG_OPTGROUP)
  register(HTMLOptionElement, TAG_OPTION)
  register(HTMLHeadingElement, [TAG_H1, TAG_H2, TAG_H3, TAG_H4, TAG_H5, TAG_H6])
  register(HTMLBRElement, TAG_BR)
  register(HTMLMenuElement, TAG_MENU)
  register(HTMLUListElement, TAG_UL)
  register(HTMLOListElement, TAG_OL)
  register(HTMLLIElement, TAG_LI)
  register(HTMLStyleElement, TAG_STYLE)
  register(HTMLLinkElement, TAG_LINK)
  register(HTMLFormElement, TAG_FORM)
  register(HTMLTemplateElement, TAG_TEMPLATE)
  register(HTMLUnknownElement, TAG_UNKNOWN)
  register(HTMLScriptElement, TAG_SCRIPT)
  register(HTMLBaseElement, TAG_BASE)
  register(HTMLAreaElement, TAG_AREA)
  register(HTMLButtonElement, TAG_BUTTON)
  register(HTMLTextAreaElement, TAG_TEXTAREA)
  register(HTMLLabelElement, TAG_LABEL)
  register(HTMLCanvasElement, TAG_CANVAS)
  register(HTMLImageElement, TAG_IMG)
  register(HTMLVideoElement, TAG_VIDEO)
  register(HTMLAudioElement, TAG_AUDIO)
  register(HTMLIFrameElement, TAG_IFRAME)
  register(HTMLTableElement, TAG_TABLE)
  register(HTMLTableCaptionElement, TAG_CAPTION)
  register(HTMLTableRowElement, TAG_TR)
  register(HTMLTableSectionElement, [TAG_TBODY, TAG_THEAD, TAG_TFOOT])
  register(HTMLMetaElement, TAG_META)
  register(HTMLDetailsElement, TAG_DETAILS)
  register(HTMLFrameElement, TAG_FRAME)
  register(HTMLTimeElement, TAG_TIME)
  register(HTMLQuoteElement, [TAG_BLOCKQUOTE, TAG_Q])
  register(HTMLDataElement, TAG_DATA)
  register(HTMLHeadElement, TAG_HEAD)
  register(HTMLTitleElement, TAG_TITLE)
  let svgElementCID = ctx.registerType(SVGElement, parent = elementCID)
  ctx.registerType(SVGSVGElement, parent = svgElementCID)

proc addDOMModule*(ctx: JSContext; eventTargetCID: JSClassID) =
  let nodeCID = ctx.registerType(Node, parent = eventTargetCID)
  doAssert ctx.defineConsts(nodeCID, NodeType) == dprSuccess
  let nodeListCID = ctx.registerType(NodeList)
  let htmlCollectionCID = ctx.registerType(HTMLCollection)
  ctx.registerType(HTMLAllCollection)
  ctx.registerType(HTMLFormControlsCollection, parent = htmlCollectionCID)
  ctx.registerType(HTMLOptionsCollection, parent = htmlCollectionCID)
  ctx.registerType(RadioNodeList, parent = nodeListCID)
  ctx.registerType(NodeIterator)
  ctx.registerType(Location)
  let documentCID = ctx.registerType(Document, parent = nodeCID)
  ctx.registerType(XMLDocument, parent = documentCID)
  ctx.registerType(DOMImplementation)
  ctx.registerType(DOMTokenList)
  ctx.registerType(DOMStringMap)
  let characterDataCID = ctx.registerType(CharacterData, parent = nodeCID)
  ctx.registerType(Comment, parent = characterDataCID)
  ctx.registerType(CDATASection, parent = characterDataCID)
  ctx.registerType(DocumentFragment, parent = nodeCID)
  ctx.registerType(ProcessingInstruction, parent = characterDataCID)
  ctx.registerType(Text, parent = characterDataCID)
  ctx.registerType(DocumentType, parent = nodeCID)
  ctx.registerType(Attr, parent = nodeCID)
  ctx.registerType(NamedNodeMap)
  ctx.registerType(CSSStyleDeclaration)
  ctx.registerType(DOMRect)
  ctx.registerElements(nodeCID)
  let imageFun = ctx.newFunction(["width", "height"], """
const x = document.createElement("img");
x.width = width;
x.height = height;
return x;
""")
  let optionFun = ctx.newFunction(
    ["text", "value", "defaultSelected", "selected"], """
text = text ? text + "" : "";
const option = document.createElement("option");
if (text !== "")
  option.appendChild(new Text(text));
option.value = value;
option.defaultSelected = defaultSelected;
option.selected = selected;
return option;
""")
  doAssert JS_SetConstructorBit(ctx, imageFun, true)
  doAssert JS_SetConstructorBit(ctx, optionFun, true)
  let jsWindow = JS_GetGlobalObject(ctx)
  doAssert ctx.definePropertyCW(jsWindow, "Image", imageFun) != dprException
  doAssert ctx.definePropertyCW(jsWindow, "Option", optionFun) != dprException
  doAssert ctx.definePropertyCW(jsWindow, "HTMLDocument",
    JS_GetPropertyStr(ctx, jsWindow, "Document")) != dprException
  let nodeFilter = JS_NewObject(ctx)
  for e in NodeFilterNode:
    let n = 1u32 shl uint32(e)
    if (let res = ctx.definePropertyE(nodeFilter, $e, n); res != dprSuccess):
      doAssert false
  doAssert ctx.definePropertyE(nodeFilter, "SHOW_ALL", 0xFFFFFFFFu32) !=
    dprException
  doAssert ctx.definePropertyCW(jsWindow, "NodeFilter", nodeFilter) !=
    dprException
  JS_FreeValue(ctx, jsWindow)

# Forward declaration hack
isDefaultPassiveImpl = func(target: EventTarget): bool =
  if not (target of Node):
    return false
  let node = Node(target)
  return target of Window or EventTarget(node.document) == target or
    EventTarget(node.document.documentElement) == target or
    EventTarget(node.document.body) == target

getParentImpl = proc(ctx: JSContext; eventTarget: EventTarget; isLoad: bool):
    EventTarget =
  if eventTarget of Node:
    if eventTarget of Document:
      if isLoad:
        return nil
      # if no browsing context, then window will be nil anyway
      return Document(eventTarget).window
    return Node(eventTarget).parentNode
  return nil

errorImpl = proc(ctx: JSContext; ss: varargs[string]) =
  ctx.getGlobal().console.error(ss)

getAPIBaseURLImpl = proc(ctx: JSContext): URL =
  let window = ctx.getWindow()
  if window == nil or window.document == nil:
    return nil
  return window.document.baseURL

isWindowImpl = proc(target: EventTarget): bool {.noSideEffect.} =
  return target of Window

parseColorImpl = proc(target: EventTarget; s: string): ARGBColor =
  return Element(target).parseColor(s)

{.pop.} # raises: []
