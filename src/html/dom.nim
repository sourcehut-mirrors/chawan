{.push raises: [].}

import std/algorithm
import std/hashes
import std/math
import std/options
import std/posix
import std/sets
import std/setutils
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
import html/event
import html/performance
import html/script
import io/console
import io/dynstream
import io/promise
import io/timeout
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsnull
import monoucha/jsopaque
import monoucha/jspropenumlist
import monoucha/jstypes
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
import types/jsopt
import types/opt
import types/path
import types/referrer
import types/refstring
import types/url
import types/winattrs
import utils/dtoawrap
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
  InputType* = enum
    itText = "text"
    itButton = "button"
    itCheckbox = "checkbox"
    itColor = "color"
    itDate = "date"
    itDatetimeLocal = "datetime-local"
    itEmail = "email"
    itFile = "file"
    itHidden = "hidden"
    itImage = "image"
    itMonth = "month"
    itNumber = "number"
    itPassword = "password"
    itRadio = "radio"
    itRange = "range"
    itReset = "reset"
    itSearch = "search"
    itSubmit = "submit"
    itTel = "tel"
    itTime = "time"
    itURL = "url"
    itWeek = "week"

  ButtonType* = enum
    btSubmit = "submit"
    btReset = "reset"
    btButton = "button"

  NodeType = enum
    ntElement = (1u16, "ELEMENT_NODE")
    ntAttribute = (2u16, "ATTRIBUTE_NODE")
    ntText = (3u16, "TEXT_NODE")
    ntCdataSection = (4u16, "CDATA_SECTION_NODE")
    ntEntityReference = (5u16, "ENTITY_REFERENCE_NODE")
    ntEntity = (6u16, "ENTITY_NODE")
    ntProcessingInstruction = (7u16, "PROCESSING_INSTRUCTION_NODE")
    ntComment = (8u16, "COMMENT_NODE")
    ntDocument = (9u16, "DOCUMENT_NODE")
    ntDocumentType = (10u16, "DOCUMENT_TYPE_NODE")
    ntDocumentFragment = (11u16, "DOCUMENT_FRAGMENT_NODE")
    ntNotation = (12u16, "NOTATION_NODE")

type
  DependencyType* = enum
    dtHover, dtChecked, dtFocus, dtTarget

  DependencyMap = object
    dependsOn: Table[Element, seq[Element]]
    dependedBy: Table[Element, seq[Element]]

  DependencyInfo* = array[DependencyType, seq[Element]]

  LoadSheetResult = object
    head: CSSStylesheet
    tail: CSSStylesheet

  Location = ref object
    window: Window

  CachedURLImage = ref object
    expiry: int64
    loading: bool
    shared: seq[HTMLImageElement]
    bmp: NetworkBitmap

  WindowWeakMap* = enum
    wwmChildren, wwmChildNodes, wwmSelectedOptions, wwmTBodies, wwmCells,
    wwmDataset, wwmAttributes

  Window* = ref object of EventTarget
    console*: Console
    navigator* {.jsget.}: Navigator
    screen* {.jsget.}: Screen
    history* {.jsget.}: History
    localStorage* {.jsget.}: Storage
    sessionStorage* {.jsget.}: Storage
    crypto* {.jsget.}: Crypto
    event*: Event
    settings*: EnvironmentSettings
    loader*: FileLoader
    location* {.jsget.}: Location
    jsrt*: JSRuntime
    jsctx*: JSContext
    document* {.jsufget.}: Document
    timeouts*: TimeoutState
    navigate*: proc(url: URL)
    ensureLayout*: proc(element: Element)
    click*: proc(element: HTMLElement)
    importMapsAllowed*: bool
    inMicrotaskCheckpoint: bool
    dangerAlwaysSameOrigin*: bool # for client, insecure if Window sets true
    remoteSheetNum*: uint32
    loadedSheetNum*: uint32
    remoteImageNum*: uint32
    loadedImageNum*: uint32
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
    performance* {.jsget.}: Performance
    jsStore*: seq[JSValue]
    jsStoreFree*: int
    weakMap*: array[WindowWeakMap, JSValue]
    customElements* {.jsget.}: CustomElementRegistry

  # Navigator stuff
  Navigator* = ref object
    plugins* {.jsget.}: PluginArray
    mimeTypes* {.jsget.}: MimeTypeArray

  PluginArray* = ref object

  MimeTypeArray* = ref object

  Screen* = ref object

  History* = ref object

  Storage* = ref object
    map*: seq[tuple[key, value: string]]

  Crypto* = ref object
    urandom*: PosixStream

  CECallbackType = enum
    cctConnected = "connectedCallback"
    cctDisconnected = "disconnectedCallback"
    cctAdopted = "adoptedCallback"
    cctConnectedMove = "connectedMoveCallback"
    cctAttributeChanged = "attributeChangedCallback"
    # note: if you add more, update define0 too
    cctFormAssociated = "formAssociatedCallback"
    cctFormReset = "formResetCallback"
    cctFormDisabled = "formDisabledCallback"
    cctFormStateRestore = "formStateRestoreCallback"

  CECallbackMap = array[CECallbackType, JSValue]

  CustomElementFlag = enum
    cefFormAssociated, cefInternals, cefShadow

  CustomElementDef = ref object
    name: CAtom
    localName: CAtom
    ctor: JSValue
    observedAttrs: seq[string] #TODO CAtom?
    callbacks: CECallbackMap
    flags: set[CustomElementFlag]
    next: CustomElementDef

  CustomElementRegistry* = ref object
    rt*: JSRuntime
    defsHead: CustomElementDef
    defsTail: CustomElementDef
    inDefine: bool
    scoped: bool

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

  CollectionMatchFun = proc(node: Node): bool {.raises: [].}

  CollectionObj = object of RootObj
    childonly: bool
    invalid: bool
    inclusive: bool
    root: Node
    match: CollectionMatchFun
    snapshot: seq[Node]
    # if not nil, this is a live collection.  (uses a ptr instead of a ref
    # because ORC likes to set refs to nil before the destructor is called)
    document: ptr DocumentObj

  Collection = ref CollectionObj

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
  # Additionally, we separate out the firstChild property into a subtype
  # (ParentNode) so that it doesn't take up space in e.g. Text nodes.
  Node* = ref object of EventTarget
    parentNode*: ParentNode
    internalNext: Node # either nextSibling or ownerDocument
    internalPrev: Node # either previousSibling or parentNode.lastChild

  ParentNode* = ref object of Node
    firstChild*: Node

  Attr = ref object of Node
    dataIdx: int
    ownerElement: Element
    prefix {.jsget.}: CAtom
    localName {.jsget.}: CAtom

  DOMImplementation = ref object
    document: Document

  DOMRect* = ref object
    x* {.jsgetset.}: float64
    y* {.jsgetset.}: float64
    width* {.jsgetset.}: float64
    height* {.jsgetset.}: float64

  DOMRectList = ref object
    list: seq[DOMRect]

  DocumentWriteBuffer* = ref object
    data*: string
    i*: int
    prev*: DocumentWriteBuffer

  Document* = ref DocumentObj

  DocumentObj = object of ParentNode
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
    writeBuffersTop*: DocumentWriteBuffer
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
    uaSheetsHead: CSSStylesheet
    userSheet: CSSStylesheet
    authorSheetsHead: CSSStylesheet
    sheetTitle: string
    ruleMap: CSSRuleMap
    cachedForms: HTMLCollection
    cachedLinks: HTMLCollection
    cachedImages: HTMLCollection
    parser*: RootRef
    liveCollections: seq[ptr CollectionObj]
    cachedAll: HTMLAllCollection

  XMLDocument = ref object of Document

  CharacterData* = ref object of Node
    # Note: layout assumes this is only modified directly by appending text.
    data* {.jsgetset.}: RefString

  Text* = ref object of CharacterData

  Comment* = ref object of CharacterData

  CDATASection = ref object of CharacterData

  ProcessingInstruction = ref object of CharacterData
    target {.jsget.}: string

  DocumentFragment* = ref object of ParentNode
    host*: Element

  DocumentType* = ref object of Node
    name* {.jsget.}: string
    publicId* {.jsget.}: string
    systemId* {.jsget.}: string

  AttrData* = object
    qualifiedName*: CAtom
    namespace*: CAtom
    value*: string

  CustomElementState = enum
    cesUndefined = "undefined"
    cesFailed = "failed"
    cesUncustomized = "uncustomized"
    cesPrecustomized = "precustomized"
    cesCustom = "custom"

  ElementFlag = enum
    efHint, efHover

  Element* = ref object of ParentNode
    namespaceURI* {.jsget.}: CAtom # 4
    prefix {.jsget.}: CAtom # 8
    childElIndicesInvalid: bool # 9
    flags: set[ElementFlag] # 10
    selfDepends: set[DependencyType] # 11
    custom: CustomElementState # 12
    localName* {.jsget.}: CAtom # 16
    id* {.jsget.}: CAtom # 20
    name: CAtom # 24
    internalElIndex: int # 32
    classList* {.jsget.}: DOMTokenList # 40
    attrs*: seq[AttrData] # 48, sorted by int(qualifiedName)
    cachedStyle*: CSSStyleDeclaration # 56
    computed*: CSSValues # 64
    box*: RootRef # 72, CSSBox

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

  HTMLSpanElement = ref object of HTMLElement

  HTMLOptGroupElement = ref object of HTMLElement

  HTMLOptionElement* = ref object of HTMLElement
    selected* {.jsget.}: bool
    dirty: bool

  HTMLHeadingElement = ref object of HTMLElement

  HTMLBRElement = ref object of HTMLElement

  HTMLMenuElement = ref object of HTMLElement

  HTMLUListElement = ref object of HTMLElement

  HTMLOListElement = ref object of HTMLElement

  HTMLLIElement* = ref object of HTMLElement
    value* {.jsget.}: Option[int32]

  SheetElement = ref object of HTMLElement
    sheetHead: CSSStylesheet
    sheetTail: CSSStylesheet

  HTMLStyleElement* = ref object of SheetElement

  HTMLLinkElement* = ref object of SheetElement
    relList {.jsget.}: DOMTokenList
    fetchStarted: bool
    enabled: Option[bool]

  HTMLFormElement* = ref object of HTMLElement
    constructingEntryList*: bool
    firing*: bool
    controls*: seq[FormAssociatedElement]
    cachedElements: HTMLFormControlsCollection
    relList {.jsget.}: DOMTokenList

  HTMLTemplateElement* = ref object of HTMLElement
    content* {.jsget.}: DocumentFragment

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

  OnCompleteProc = proc(element: HTMLScriptElement; res: ScriptResult)

  HTMLBaseElement = ref object of HTMLElement

  HTMLAreaElement = ref object of HTMLElement
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

  HTMLIFrameElement = ref object of HTMLElement

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

  HTMLObjectElement = ref object of HTMLElement

  HTMLSourceElement = ref object of HTMLElement

  HTMLModElement = ref object of HTMLElement

  HTMLProgressElement = ref object of HTMLElement

  HTMLUnknownElement = ref object of HTMLElement

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
jsDestructor(HTMLObjectElement)
jsDestructor(HTMLSourceElement)
jsDestructor(HTMLModElement)
jsDestructor(HTMLProgressElement)
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
jsDestructor(DOMRectList)
jsDestructor(CustomElementRegistry)

# Forward declarations
proc loadSheet(window: Window; url: URL; charset: Charset; layer: CAtom):
  Promise[LoadSheetResult]

proc newCDATASection(document: Document; data: string): CDATASection
proc newComment(document: Document; data: sink string): Comment
proc newText*(document: Document; data: sink string): Text
proc newText(ctx: JSContext; data: sink string = ""): Text
proc newDocument*(url: URL): Document
proc newDocumentType*(document: Document;
  name, publicId, systemId: sink string): DocumentType
proc newDocumentFragment(document: Document): DocumentFragment
proc newProcessingInstruction(document: Document; target: string;
  data: sink string): ProcessingInstruction
proc newElement*(document: Document; localName: CAtom;
  namespace = Namespace.HTML; prefix = NO_PREFIX): Element
proc newElement*(document: Document; localName, namespaceURI, prefix: CAtom):
  Element
proc newHTMLElement*(document: Document; tagType: TagType): HTMLElement
proc newHTMLCollection(root: Node; match: CollectionMatchFun;
  islive, childonly: bool): HTMLCollection
proc newNodeList(root: Node; match: CollectionMatchFun;
  islive, childonly: bool): NodeList
proc newDOMTokenList(element: Element; name: StaticAtom): DOMTokenList
proc newCSSStyleDeclaration(element: Element; value: string; computed = false;
  readonly = false): CSSStyleDeclaration

proc adopt(document: Document; node: Node)
proc applyStyleDependencies*(element: Element; depends: DependencyInfo)
proc baseURL*(document: Document): URL
proc documentElement*(document: Document): Element
proc invalidateCollections(document: Document)
proc isConnected(node: Node): bool
proc lastChild*(node: Node): Node
proc parseURL0*(document: Document; s: string): URL
proc parseURL*(document: Document; s: string): Opt[URL]
proc reflectEvent(document: Document; target: EventTarget;
  name, ctype: StaticAtom; value: string; target2 = none(EventTarget))

proc document*(node: Node): Document
proc nextDescendant(node, start: Node): Node
proc parentElement*(node: Node): Element
proc serializeFragment(res: var string; node: Node)
proc serializeFragmentInner(res: var string; child: Node; parentType: TagType)

proc countChildren(node: ParentNode; nodeType: type): int
proc hasChild(node: ParentNode; nodeType: type): bool
proc hasChildExcept(node: ParentNode; nodeType: type; ex: Node): bool
proc insert*(parent: ParentNode; node, before: Node; suppressObservers = false)
proc replaceAll(parent: ParentNode; node: Node)
proc replaceAll(parent: ParentNode; s: sink string)

proc containsIgnoreCase(tokenList: DOMTokenList; a: StaticAtom): bool

proc newAttr(element: Element; dataIdx: int): Attr
proc data(attr: Attr): lent AttrData
proc setValue(attr: Attr; s: string)

proc attr*(element: Element; name: CAtom; value: sink string)
proc attr*(element: Element; name: StaticAtom; value: sink string)
proc attr*(element: Element; s: StaticAtom): lent string
proc attrb*(element: Element; s: CAtom): bool
proc attrb*(element: Element; at: StaticAtom): bool
proc attrl*(element: Element; s: StaticAtom): Opt[int32]
proc attrul*(element: Element; s: StaticAtom): Opt[uint32]
proc attrulgz*(element: Element; s: StaticAtom): Opt[uint32]
proc attrd*(element: Element; s: StaticAtom): Opt[float64]
proc attrdgz*(element: Element; s: StaticAtom): Opt[float64]
proc attrl(element: Element; name: StaticAtom; value: int32)
proc attrul(element: Element; name: StaticAtom; value: uint32)
proc attrulgz(element: Element; name: StaticAtom; value: uint32)
proc attrd(element: Element; name: StaticAtom; value: float64)
proc delAttr(ctx: JSContext; element: Element; i: int)
proc elementInsertionSteps(element: Element): bool
proc elIndex*(this: Element): int
proc ensureStyle(element: Element)
proc findAttr(element: Element; qualifiedName: CAtom): int
proc findAttrNS(element: Element; namespace, localName: CAtom): int
proc getCharset(element: Element): Charset
proc getComputedStyle*(element: Element; pseudo: PseudoElement): CSSValues
proc invalidate*(element: Element)
proc invalidate*(element: Element; dep: DependencyType)
proc nextDisplayedElement(element: Element): Element
proc outerHTML(element: Element): string
proc postConnectionSteps(element: Element)
proc previousElementSibling*(element: Element): Element
proc reflectAttr(element: Element; name: CAtom; value: Option[string])
proc scriptingEnabled(element: Element): bool
proc tagName(element: Element): string
proc tagType*(element: Element; namespace = satNamespaceHTML): TagType

proc crossOrigin(element: HTMLElement): CORSAttribute
proc referrerPolicy(element: HTMLElement): Opt[ReferrerPolicy]

proc resetFormOwner(element: FormAssociatedElement)
proc insertSheet(this: SheetElement)
proc removeSheet(this: SheetElement)
proc updateSheet(this: SheetElement; head, tail: CSSStylesheet)
proc getImageRect(this: HTMLImageElement): tuple[w, h: float64]
proc checked*(input: HTMLInputElement): bool {.inline.}
proc setChecked*(input: HTMLInputElement; b: bool)
proc value*(this: HTMLInputElement): lent string
proc setValue*(this: HTMLInputElement; value: sink string)
proc isDisabled(link: HTMLLinkElement): bool
proc value*(option: HTMLOptionElement): string
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
var matchesImpl*: proc(element: Element; cxsels: SelectorList): bool {.nimcall,
  raises: [].}
# set in html/chadombuilder
var parseHTMLFragmentImpl*: proc(element: Element; s: string): seq[Node]
  {.nimcall, raises: [].}
var parseDocumentWriteChunkImpl*: proc(wrapper: RootRef) {.nimcall, raises: [].}
# set in html/env
var fetchImpl*: proc(window: Window; input: JSRequest): FetchPromise {.
  nimcall, raises: [].}
var applyStyleImpl*: proc(element: Element) {.nimcall, raises: [].}
var getClientRectsImpl*: proc(element: Element; firstOnly, blockOnly: bool):
  seq[DOMRect] {.nimcall, raises: [].}

# Reflected attributes.
type
  ReflectType = enum
    rtStr, rtUrl, rtBool, rtLong, rtUlongGz, rtUlong, rtDoubleGz, rtFunction,
    rtReferrerPolicy, rtCrossOrigin, rtMethod

  ReflectEntry = object
    attrname: StaticAtom
    funcname: StaticAtom
    t: ReflectType
    u: uint32 # 32 bits of opaque associated data (mostly default values)

  ReflectEntryTag = object
    tags: seq[TagType]
    e: ReflectEntry

proc makes(attrname, funcname: StaticAtom; ts: varargs[TagType]):
    ReflectEntryTag =
  ReflectEntryTag(
    tags: @ts,
    e: ReflectEntry(
      attrname: attrname,
      funcname: funcname,
      t: rtStr,
    )
  )

proc makes(name: StaticAtom; ts: varargs[TagType]): ReflectEntryTag =
  makes(name, name, ts)

proc makeurl(name: StaticAtom; ts: varargs[TagType]): ReflectEntryTag =
  ReflectEntryTag(
    tags: @ts,
    e: ReflectEntry(
      attrname: name,
      funcname: name,
      t: rtUrl,
    )
  )

proc makeb(attrname, funcname: StaticAtom; ts: varargs[TagType]):
    ReflectEntryTag =
  ReflectEntryTag(
    tags: @ts,
    e: ReflectEntry(
      attrname: attrname,
      funcname: funcname,
      t: rtBool,
    )
  )

proc makeb(name: StaticAtom; ts: varargs[TagType]): ReflectEntryTag =
  makeb(name, name, ts)

proc makeul(name: StaticAtom; ts: varargs[TagType]; default = 0u32):
    ReflectEntryTag =
  ReflectEntryTag(
    tags: @ts,
    e: ReflectEntry(
      attrname: name,
      funcname: name,
      t: rtUlong,
      u: default
    )
  )

proc makeulgz(name: StaticAtom; ts: varargs[TagType]; default = 0u32):
    ReflectEntryTag =
  ReflectEntryTag(
    tags: @ts,
    e: ReflectEntry(
      attrname: name,
      funcname: name,
      t: rtUlongGz,
      u: default
    )
  )

proc makef(name, ctype: StaticAtom): ReflectEntryTag =
  ReflectEntryTag(
    tags: @[],
    e: ReflectEntry(
      attrname: name,
      funcname: name,
      t: rtFunction,
      u: uint32(ctype)
    )
  )

proc makerp(attrName, funcName: StaticAtom; ts: varargs[TagType]):
    ReflectEntryTag =
  ReflectEntryTag(
    tags: @ts,
    e: ReflectEntry(
      attrname: attrName,
      funcname: funcName,
      t: rtReferrerPolicy,
    )
  )

proc makeco(attrName, funcName: StaticAtom; ts: varargs[TagType]):
    ReflectEntryTag =
  ReflectEntryTag(
    tags: @ts,
    e: ReflectEntry(
      attrname: attrName,
      funcname: funcName,
      t: rtCrossOrigin,
    )
  )

proc makem(attrname, funcname: StaticAtom; ts: varargs[TagType]):
    ReflectEntryTag =
  ReflectEntryTag(
    tags: @ts,
    e: ReflectEntry(
      attrname: attrname,
      funcname: funcname,
      t: rtMethod
    )
  )

proc makedgz(name: StaticAtom; t: TagType; u: uint32): ReflectEntryTag =
  ReflectEntryTag(
    tags: @[t],
    e: ReflectEntry(
      attrname: name,
      funcname: name,
      t: rtDoubleGz,
      u: u,
    )
  )

proc makem(name: StaticAtom; ts: varargs[TagType]): ReflectEntryTag =
  makem(name, name, ts)

# Note: this table only works for tag types with a registered interface.
const ReflectMap0 = [
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
  makes(satMedia, TAG_META, TAG_SOURCE),
  makes(satDatetime, satHDateTime, TAG_TIME, TAG_INS, TAG_DEL),
  makes(satType, TAG_SOURCE, TAG_A, TAG_OL, TAG_LINK, TAG_SCRIPT, TAG_OBJECT),
  makeul(satCols, TAG_TEXTAREA, 20u32),
  makeul(satRows, TAG_TEXTAREA, 1u32),
  makeulgz(satSize, TAG_SELECT, 0u32),
  makeulgz(satSize, TAG_INPUT, 20u32),
  makeul(satWidth, TAG_CANVAS, TAG_SOURCE, 300u32),
  makeul(satHeight, TAG_CANVAS, TAG_SOURCE, 150u32),
  makes(satAlt, TAG_IMG),
  makes(satSrcset, TAG_IMG, TAG_SOURCE),
  makes(satSizes, TAG_IMG, TAG_SOURCE),
  makeco(satCrossorigin, satHCrossOrigin, TAG_IMG, TAG_SCRIPT),
  makerp(satReferrerpolicy, satHReferrerPolicy, TAG_IMG, TAG_SCRIPT),
  makem(satMethod, TAG_FORM),
  makem(satFormmethod, satHFormMethod, TAG_INPUT, TAG_BUTTON),
  makes(satUsemap, satHUseMap, TAG_IMG),
  makeb(satIsmap, satHIsMap, TAG_IMG),
  makeb(satDisabled, TAG_LINK, TAG_OPTION, TAG_SELECT, TAG_OPTGROUP),
  makeurl(satSrc, TAG_IMG, TAG_SCRIPT, TAG_IFRAME, TAG_FRAME, TAG_INPUT,
    TAG_SOURCE),
  makeurl(satCite, TAG_BLOCKQUOTE, TAG_Q, TAG_INS, TAG_DEL),
  makeurl(satHref, TAG_LINK),
  makeurl(satData, TAG_OBJECT),
  makedgz(satValue, TAG_PROGRESS, 0),
  makedgz(satMax, TAG_PROGRESS, 1),
  # super-global attributes
  makes(satClass, satClassName),
  makef(satOnclick, satClick),
  makef(satOninput, satInput),
  makef(satOnchange, satChange),
  makef(satOnload, satLoad),
  makef(satOnerror, satError),
  makef(satOnblur, satBlur),
  makef(satOnfocus, satFocus),
  makef(satOnsubmit, satSubmit),
  makef(satOncontextmenu, satContextmenu),
  makef(satOndblclick, satDblclick),
  makes(satSlot),
  makes(satTitle),
  makes(satLang),
]

static:
  # In the reflection magic we allocate 9 bits to attribute names and 7 bits
  # to class names.
  doAssert ReflectMap0.len < 512

const LabelableElements = {
  # input only if type not hidden
  TAG_BUTTON, TAG_INPUT, TAG_METER, TAG_OUTPUT, TAG_PROGRESS, TAG_SELECT,
  TAG_TEXTAREA
}

const VoidElements = {
  TAG_AREA, TAG_BASE, TAG_BR, TAG_COL, TAG_EMBED, TAG_HR, TAG_IMG, TAG_INPUT,
  TAG_LINK, TAG_META, TAG_SOURCE, TAG_TRACK, TAG_WBR
}

# Iterators
iterator childList*(node: ParentNode): Node {.inline.} =
  var it = node.firstChild
  if it != nil:
    while true:
      yield it
      it = it.internalNext
      if it.internalNext == nil:
        break # it is ownerDocument

iterator rchildList*(node: ParentNode): Node {.inline.} =
  let first = node.firstChild
  if first != nil:
    var it = first.internalPrev
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
    while it.internalNext != nil:
      yield it
      it = it.internalNext

iterator elementList*(node: ParentNode): Element {.inline.} =
  for child in node.childList:
    if child of Element:
      yield Element(child)

iterator relementList*(node: ParentNode): Element {.inline.} =
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

iterator descendants*(node: ParentNode): Node {.inline.} =
  var it = node.firstChild
  while it != nil:
    yield it
    it = it.nextDescendant(node)

iterator descendantsIncl(node: Node): Node {.inline.} =
  var it = node
  while it != nil:
    yield it
    it = it.nextDescendant(node)

iterator elementDescendants*(node: ParentNode): Element {.inline.} =
  for child in node.descendants:
    if child of Element:
      yield Element(child)

iterator elementDescendantsIncl(node: Node): Element {.inline.} =
  for child in node.descendantsIncl:
    if child of Element:
      yield Element(child)

iterator elementDescendants*(node: ParentNode; tag: TagType): Element
    {.inline.} =
  for desc in node.elementDescendants:
    if desc.tagType == tag:
      yield desc

iterator elementDescendants*(node: ParentNode; tag: set[TagType]): Element
    {.inline.} =
  for desc in node.elementDescendants:
    if desc.tagType in tag:
      yield desc

iterator displayedElements*(window: Window): Element
    {.inline.} =
  var element = window.document.documentElement
  while element != nil:
    yield element
    element = element.nextDisplayedElement

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

iterator textNodes*(node: ParentNode): Text {.inline.} =
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

iterator sheets(this: SheetElement): CSSStylesheet {.inline.} =
  var sheet = this.sheetHead
  let tail = this.sheetTail
  while sheet != nil:
    yield sheet
    if sheet == tail:
      break
    sheet = sheet.next

# Window/Global
# For now, these are the same; on an API level however, getGlobal is
# guaranteed to be non-null, while getWindow may return null in the
# future.  (This is in preparation for Worker support.)
proc getGlobal*(ctx: JSContext): Window =
  let global = JS_GetGlobalObject(ctx)
  var window: Window
  doAssert ctx.fromJSFree(global, window).isOk
  return window

proc getWindow*(ctx: JSContext): Window =
  let global = JS_GetGlobalObject(ctx)
  var window: Window
  doAssert ctx.fromJSFree(global, window).isOk
  return window

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

proc isCell(this: Node): bool =
  return this of Element and Element(this).tagType in {TAG_TD, TAG_TH}

proc isTBody(this: Node): bool =
  return this of Element and Element(this).tagType == TAG_TBODY

proc isRow(this: Node): bool =
  return this of Element and Element(this).tagType == TAG_TR

proc isOptionOf(node: Node; select: HTMLSelectElement): bool =
  if node of HTMLOptionElement:
    let parent = node.parentNode
    return parent == select or
      parent of HTMLOptGroupElement and parent.parentNode == select
  return false

proc isElement(node: Node): bool =
  return node of Element

proc isForm(node: Node): bool =
  return node of HTMLFormElement

proc isLink(node: Node): bool =
  if not (node of Element):
    return false
  let element = Element(node)
  return element.tagType in {TAG_A, TAG_AREA} and element.attrb(satHref)

proc isImage(node: Node): bool =
  if not (node of Element):
    return false
  let element = Element(node)
  return element.tagType == TAG_IMG

proc logException(window: Window; url: URL) =
  #TODO excludepassword seems pointless?
  window.console.error("Exception in document",
    url.serialize(excludepassword = true), window.jsctx.getExceptionMsg())

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
      match = proc(node: Node): bool =
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
  of wwmDataset:
    return ctx.toJS(DOMStringMap(target: HTMLElement(this)))
  of wwmAttributes:
    let element = Element(this)
    let map = NamedNodeMap(element: element)
    for i, attr in element.attrs.mypairs:
      map.attrlist.add(element.newAttr(i))
    return ctx.toJS(map)

proc getWeakCollection(ctx: JSContext; this: Node; wwm: WindowWeakMap):
    JSValue =
  let jsThis = ctx.toJS(this)
  let res = ctx.getWeak(wwm, jsThis)
  if JS_IsUndefined(res):
    let collection = ctx.newWeakCollection(this, wwm)
    if JS_IsException(collection):
      JS_FreeValue(ctx, jsThis)
      return JS_EXCEPTION
    if ctx.setWeak(wwm, jsThis, JS_DupValue(ctx, collection)).isErr:
      return JS_EXCEPTION
    return collection
  JS_FreeValue(ctx, jsThis)
  return res

proc corsFetch(window: Window; input: Request): FetchPromise =
  if not window.settings.images and input.url.scheme.startsWith("img-codec+"):
    return newResolvedPromise(FetchResult.err())
  return window.loader.fetch(input)

proc parseStylesheet(window: Window; s: string; baseURL: URL; charset: Charset;
    layer: CAtom): Promise[LoadSheetResult] =
  let sheet = s.parseStylesheet(baseURL, addr window.settings, coAuthor, layer)
  var promises: seq[EmptyPromise] = @[]
  var sheets = newSeq[LoadSheetResult](sheet.s.importList.len)
  for i, it in sheet.s.importList.mypairs:
    let url = it.url
    let layer = it.layer
    (proc(i: int) =
      inc window.remoteSheetNum
      let p = window.loadSheet(url, charset, layer).then(
        proc(res: LoadSheetResult) =
          inc window.loadedSheetNum
          sheets[i] = res
      )
      promises.add(p)
    )(i)
  return promises.all().then(proc(): LoadSheetResult =
    var head: CSSStylesheet = sheet
    var tail: CSSStylesheet = sheet
    for res in sheets:
      if res.head != nil:
        #TODO check import media query here
        if tail == nil:
          head = res.head
        else:
          tail.next = res.head
        tail = res.tail
    return LoadSheetResult(head: head, tail: tail)
  )

proc loadSheet(window: Window; url: URL; charset: Charset; layer: CAtom):
    Promise[LoadSheetResult] =
  return window.corsFetch(
    newRequest(url)
  ).then(proc(res: FetchResult): Promise[TextResult] =
    if res.isOk:
      let res = res.get
      if res.getContentType().equalsIgnoreCase("text/css"):
        return res.cssText(charset)
      res.close()
    return newResolvedPromise(TextResult.err())
  ).then(proc(s: TextResult): Promise[LoadSheetResult] =
    if s.isErr:
      return newResolvedPromise(LoadSheetResult())
    return window.parseStylesheet(s.get, url, charset, layer)
  )

proc loadSheet(window: Window; link: HTMLLinkElement; url: URL):
    Promise[LoadSheetResult] =
  let charset = link.getCharset()
  return window.loadSheet(url, charset, CAtomNull)

proc loadResource(window: Window; link: HTMLLinkElement) =
  if not window.settings.styling or
      not link.relList.containsIgnoreCase(satStylesheet) or
      link.fetchStarted or link.isDisabled():
    return
  link.fetchStarted = true
  let href = link.attr(satHref)
  if href == "":
    return
  if url := parseURL(href, window.document.url):
    let media = link.attr(satMedia)
    var applies = true
    if media != "":
      var ctx = initCSSParser(media)
      let media = ctx.parseMediaQueryList(window.settings.attrsp)
      applies = media.applies(addr window.settings)
    inc window.remoteSheetNum
    let p = window.loadSheet(link, url).then(proc(res: LoadSheetResult) =
      # Note: we intentionally load all sheets first and *then* check
      # whether media applies, to prevent media query based tracking.
      #TODO should we really keep the current sheet if the result is nil?
      if res.head != nil:
        link.updateSheet(res.head, res.tail)
        let disabled = link.isDisabled()
        for sheet in link.sheets:
          sheet.disabled = disabled
          sheet.applies = applies
          sheet.media = media
      inc window.loadedSheetNum
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
  if url := parseURL(src, window.document.url):
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
    inc window.remoteImageNum
    let p = window.corsFetch(newRequest(url, headers = headers)).then(
      proc(res: FetchResult): EmptyPromise =
        inc window.loadedImageNum
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
        let url = parseURL0("img-codec+" & t & ":decode")
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
          if s.startsWithIgnoreCase("max-age="):
            let i = s.skipBlanks("max-age=".len)
            let s = s.until(AllChars - AsciiDigit, i)
            if pi := parseInt64(s):
              expiry = getTime().toUnix() + pi
            break
        cachedURL.loading = false
        cachedURL.expiry = expiry
        return r.then(proc(res: FetchResult) =
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
            contentType: "image/" & t,
            vector: t == "svg+xml"
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
  if ps.writeLoop(s).isErr:
    ps.sclose()
    return
  ps.sclose()
  let request = newRequest(
    "img-codec+svg+xml:decode",
    httpMethod = hmPost,
    headers = newHeaders(hgRequest, {"Cha-Image-Info-Only": "1"}),
    body = RequestBody(t: rbtOutput, outputId: svgres.outputId)
  )
  let p = loader.fetch(request).then(proc(res: FetchResult) =
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
      contentType: "image/svg+xml",
      vector: true
    )
    for share in svg.shared:
      share.bitmap = svg.bitmap
      share.invalidate()
    svg.invalidate()
  )
  window.pendingImages.add(p)

proc runJSJobs*(window: Window) =
  while true:
    let ctx = window.jsrt.runJSJobs()
    if ctx == nil:
      break
    window.console.writeException(ctx)

proc performMicrotaskCheckpoint*(window: Window) =
  if window.inMicrotaskCheckpoint:
    return
  window.inMicrotaskCheckpoint = true
  window.runJSJobs()
  window.inMicrotaskCheckpoint = false

proc getComputedStyle0*(ctx: JSContext; window: Window; element: Element;
    pseudoElt: JSValueConst): Opt[CSSStyleDeclaration] =
  if not element.isConnected():
    return ok(newCSSStyleDeclaration(nil, ""))
  var pseudo = peNone
  if not JS_IsUndefined(pseudoElt):
    # This isn't what the spec says, but it seems to be what others do.
    # Note: in Gecko this is case-sensitive, in Blink it isn't.  CSS itself
    # is case-insensitive so I assume it's a Gecko bug.
    var s: string
    ?ctx.fromJS(pseudoElt, s)
    let i = if s.startsWith("::"): 2 elif s.startsWith(":"): 1 else: 0
    if i != 0: # if no : at the beginning, ignore pseudoElt
      pseudo = parseEnumNoCase[PseudoElement](s.substr(i)).get(peNone)
      if pseudo == peNone or pseudo notin {peBefore, peAfter} and i == 1:
        return ok(newCSSStyleDeclaration(nil, ""))
  if window.settings.scripting == smApp:
    element.ensureStyle()
    return ok(newCSSStyleDeclaration(element, $element.getComputedStyle(pseudo),
      computed = true, readonly = true))
  # In lite mode, we just parse the "style" attribute and hope for
  # the best.
  ok(newCSSStyleDeclaration(element, element.attr(satStyle), computed = true,
    readonly = true))

proc addCustomElementRegistry*(window: Window; rt: JSRuntime) =
  window.customElements = CustomElementRegistry(rt: rt)

# CustomElementRegistry
iterator defs(this: CustomElementRegistry): CustomElementDef =
  var def = this.defsHead
  while def != nil:
    yield def
    def = def.next

proc newCustomElementRegistry(ctx: JSContext): CustomElementRegistry
    {.jsctor.} =
  return CustomElementRegistry(rt: JS_GetRuntime(ctx), scoped: true)

proc mark(rt: JSRuntime; this: CustomElementRegistry; markFunc: JS_MarkFunc)
    {.jsmark.} =
  for def in this.defs:
    JS_MarkValue(rt, def.ctor, markFunc)
    for val in def.callbacks:
      JS_MarkValue(rt, val, markFunc)

proc finalize(this: CustomElementRegistry) {.jsfin.} =
  for def in this.defs:
    JS_FreeValueRT(this.rt, def.ctor)
    for val in def.callbacks:
      JS_FreeValueRT(this.rt, val)

type CustomElementDefinitionOptions = object of JSDict
  extends {.jsdefault.}: Option[string]

proc find(this: CustomElementRegistry; name: CAtom): CustomElementDef =
  for it in this.defs:
    if it.name == name:
      return it
  return nil

proc find(this: CustomElementRegistry; ctx: JSContext; ctor: JSValueConst):
    CustomElementDef =
  for it in this.defs:
    if ctx.strictEquals(it.ctor, ctor):
      return it
  return nil

proc tryGetStrSeq(ctx: JSContext; ctor: JSValueConst; name: cstring;
    res: var seq[string]): Opt[void] =
  let val = JS_GetPropertyStr(ctx, ctor, name)
  if JS_IsException(val):
    return err()
  if not JS_IsUndefined(val):
    ?ctx.fromJSFree(val, res)
  ok()

proc tryGetCallback(ctx: JSContext; proto: JSValueConst; t: CECallbackType;
    callbacks: var CECallbackMap): Opt[void] =
  let val = JS_GetPropertyStr(ctx, proto, cstring($t))
  if JS_IsException(val):
    return err()
  if not JS_IsUndefined(val):
    callbacks[t] = val # val is freed by caller
    if not JS_IsFunction(ctx, val):
      JS_ThrowTypeError(ctx, "lifecycle callback is not a function")
      return err()
  ok()

proc define0(ctx: JSContext; this: CustomElementRegistry; name: CAtom;
    ctor, proto: JSValueConst; def: CustomElementDef): Opt[void] =
  if not JS_IsObject(proto):
    JS_ThrowTypeError(ctx, "prototype is not an object")
    return err()
  for t in cctConnected..cctAttributeChanged:
    ?ctx.tryGetCallback(proto, t, def.callbacks)
  if not JS_IsNull(def.callbacks[cctAttributeChanged]):
    ?ctx.tryGetStrSeq(ctor, "observedAttributes", def.observedAttrs)
  var disabled: seq[string]
  ?ctx.tryGetStrSeq(ctor, "disabledFeatures", disabled)
  if "internals" in disabled:
    def.flags.excl(cefInternals)
  if "shadow" in disabled:
    def.flags.excl(cefShadow)
  var formAssociated: bool
  let val = JS_GetPropertyStr(ctx, ctor, "formAssociated")
  ?ctx.fromJS(val, formAssociated)
  if formAssociated:
    def.flags.incl(cefFormAssociated)
    for t in cctFormAssociated..cctFormStateRestore:
      ?ctx.tryGetCallback(proto, t, def.callbacks)
  ok()

proc newCustomElementDef(name, localName: CAtom): CustomElementDef =
  let def = CustomElementDef(
    name: name,
    localName: localName,
    flags: {cefInternals, cefShadow}
  )
  for it in def.callbacks.mitems:
    it = JS_NULL
  return def

proc define(ctx: JSContext; this: CustomElementRegistry; name: CAtom;
    ctor: JSValueConst; options = CustomElementDefinitionOptions()): JSValue
    {.jsfunc.} =
  if not JS_IsConstructor(ctx, ctor):
    return JS_ThrowTypeError(ctx, "constructor expected")
  if this.find(name) != nil or this.find(ctx, ctor) != nil:
    return JS_ThrowDOMException(ctx, "NotSupportedError",
      "a custom element with this name/constructor is already defined")
  if options.extends.isSome:
    #TODO extends
    return JS_ThrowDOMException(ctx, "NotSupportedError",
      "extends not supported yet")
  if this.inDefine:
    return JS_ThrowDOMException(ctx, "NotSupportedError",
      "recursive custom element definition is not allowed")
  this.inDefine = true
  let proto = JS_GetPropertyStr(ctx, ctor, "prototype")
  if JS_IsException(proto):
    this.inDefine = false
    return JS_EXCEPTION
  let def = newCustomElementDef(name, name) #TODO extends/localName
  let res = ctx.define0(this, name, ctor, proto, def)
  JS_FreeValue(ctx, proto)
  this.inDefine = false
  if res.isErr:
    for it in def.callbacks:
      JS_FreeValue(ctx, it)
    return JS_EXCEPTION
  def.ctor = JS_DupValue(ctx, ctor)
  if this.defsTail == nil:
    this.defsHead = def
  else:
    this.defsTail.next = def
  this.defsTail = def
  #TODO is scoped
  #TODO upgrade
  #TODO when-defined
  return JS_UNDEFINED

proc get(ctx: JSContext; this: CustomElementRegistry; name: CAtom): JSValue
    {.jsfunc.} =
  let def = this.find(name)
  if def != nil:
    return JS_DupValue(ctx, def.ctor)
  return JS_UNDEFINED

proc getName(ctx: JSContext; this: CustomElementRegistry; ctor: JSValueConst):
    CAtom {.jsfunc.} =
  let def = this.find(ctx, ctor)
  if def != nil:
    return def.name
  return CAtomNull

#TODO whenDefined, initialize

# Node
when defined(debug):
  proc `$`*(node: Node): string =
    if node == nil:
      return "null"
    result = ""
    result.serializeFragmentInner(node, TAG_UNKNOWN)

proc baseURI(node: Node): string {.jsfget.} =
  return $node.document.baseURL

proc document*(node: Node): Document =
  let next = node.internalNext
  if next == nil:
    return Document(node)
  if next.internalNext == nil:
    return Document(next)
  return Document(node.parentNode.firstChild.internalPrev.internalNext)

proc parentElement*(node: Node): Element {.jsfget.} =
  let p = node.parentNode
  if p != nil and p of Element:
    return Element(p)
  return nil

proc nextSibling*(node: Node): Node {.jsfget.} =
  if node.internalNext == nil or node.internalNext.internalNext == nil:
    # if next is nil, then node is a Document.
    # if next.next is nil, then next is ownerDocument.
    return nil
  return node.internalNext

proc previousSibling*(node: Node): Node {.jsfget.} =
  if node.parentNode == nil or node == node.parentNode.firstChild:
    return nil
  return node.internalPrev

# Return the next descendant if it isn't `start', and nil otherwise.
# Note: `start' must be either an ancestor of `node', `node` itself, or nil.
proc nextDescendant(node, start: Node): Node =
  if node of ParentNode: # parent
    let node = cast[ParentNode](node)
    if node.firstChild != nil:
      return node.firstChild
  # climb up until we find a non-last leaf (this might be node itself)
  var node = node
  while node != start:
    let next = node.nextSibling
    if next != nil:
      return next
    node = node.parentNode
  # done
  return nil

proc previousDescendant(node: Node): Node =
  let prev = node.previousSibling
  if prev == nil:
    return node.parentNode
  var node = prev
  while node of ParentNode:
    let pnode = cast[ParentNode](node)
    if pnode.firstChild == nil:
      break
    node = pnode.lastChild
  return node

proc ownerDocument(node: Node): Document {.jsfget.} =
  if node of Document:
    return nil
  return node.document

proc jsNodeType0(node: Node): NodeType =
  if node of CharacterData:
    if node of Text:
      return ntText
    elif node of Comment:
      return ntComment
    elif node of CDATASection:
      return ntCdataSection
    else: # ProcessingInstruction
      return ntProcessingInstruction
  elif node of Element:
    return ntElement
  elif node of Document:
    return ntDocument
  elif node of DocumentType:
    return ntDocumentType
  elif node of Attr:
    return ntAttribute
  else: # DocumentFragment
    return ntDocumentFragment

proc nodeType(node: Node): uint16 {.jsfget.} =
  return uint16(node.jsNodeType0)

proc nodeName(node: Node): string {.jsfget.} =
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

proc isValidChild(node: Node): bool =
  return node of DocumentFragment or node of DocumentType or node of Element or
    node of CharacterData

proc checkParentValidity(parent: Node): Result[ParentNode, cstring] =
  if parent of ParentNode:
    return ok(cast[ParentNode](parent))
  return err("parent must be a document, a document fragment, or an element")

proc rootNode(node: Node): Node =
  var node = node
  while node.parentNode != nil:
    node = node.parentNode
  return node

proc isHostIncludingInclusiveAncestor(a, b: Node): bool =
  for parent in b.branch:
    if parent == a:
      return true
  let root = b.rootNode
  if root of DocumentFragment and DocumentFragment(root).host != nil:
    for parent in root.branch:
      if parent == a:
        return true
  return false

proc hasNextSibling(node: Node; nodeType: type): bool =
  var node = node.nextSibling
  while node != nil:
    if node of nodeType:
      return true
    node = node.nextSibling
  return false

proc hasPreviousSibling(node: Node; nodeType: type): bool =
  var node = node.previousSibling
  while node != nil:
    if node of nodeType:
      return true
    node = node.previousSibling
  return false

proc nodeValue(ctx: JSContext; node: Node): JSValue {.jsfget.} =
  if node of CharacterData:
    return ctx.toJS(CharacterData(node).data)
  elif node of Attr:
    return ctx.toJS(Attr(node).data.value)
  return JS_NULL

proc textContent*(node: Node): string =
  result = ""
  if node of CharacterData:
    result = CharacterData(node).data.s
  elif node of ParentNode:
    let node = ParentNode(node)
    for child in node.childList:
      if not (child of Comment):
        result &= child.textContent

proc textContent(ctx: JSContext; node: Node): JSValue {.jsfget.} =
  if node of Document or node of DocumentType:
    return JS_NULL
  return ctx.toJS(node.textContent)

proc isConnected(node: Node): bool {.jsfget.} =
  return node.rootNode of Document #TODO shadow root

proc inSameTree*(a, b: Node): bool =
  a.rootNode == b.rootNode

# a == b or a in b's ancestors
proc contains*(a, b: Node): bool {.jsfunc.} =
  if b != nil:
    for node in b.branch:
      if node == a:
        return true
  return false

proc jsParentNode(node: Node): Node {.jsfget: "parentNode".} =
  return node.parentNode

proc firstChild(node: Node): Node {.jsfget.} =
  if node of ParentNode:
    return cast[ParentNode](node).firstChild
  nil

proc lastChild*(node: Node): Node {.jsfget.} =
  let first = node.firstChild
  if first != nil:
    return first.internalPrev
  nil

proc hasChildNodes(node: Node): bool {.jsfunc.} =
  return node.firstChild != nil

# WARNING the ordering of the arguments in the standard is whack so this
# doesn't match that
proc preInsertionValidity(parent, node, before: Node):
    Result[ParentNode, cstring] =
  let parent = ?parent.checkParentValidity()
  if node.isHostIncludingInclusiveAncestor(parent):
    return err("parent must be an ancestor")
  if before != nil and before.parentNode != parent:
    return err(nil)
  if not node.isValidChild():
    return err("node is not a valid child")
  if node of Text and parent of Document:
    return err("cannot insert text into document")
  if node of DocumentType and not (parent of Document):
    return err("document type can only be inserted into document")
  if parent of Document:
    if node of DocumentFragment:
      let node = DocumentFragment(node)
      let elems = node.countChildren(Element)
      if elems > 1 or node.hasChild(Text):
        return err("document fragment has invalid children")
      elif elems == 1 and (parent.hasChild(Element) or
          before != nil and (before of DocumentType or
          before.hasNextSibling(DocumentType))):
        return err("document fragment has invalid children")
    elif node of Element:
      if parent.hasChild(Element):
        return err("document already has an element child")
      elif before != nil and (before of DocumentType or
            before.hasNextSibling(DocumentType)):
        return err("cannot insert element before document type")
    elif node of DocumentType:
      if parent.hasChild(DocumentType) or
          before != nil and before.hasPreviousSibling(Element) or
          before == nil and parent.hasChild(Element):
        return err("cannot insert document type before an element node")
    else: discard
  ok(parent)

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
  if parentElement != nil:
    parentElement.invalidate()
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
  node.internalPrev = nil
  node.internalNext = document
  node.parentNode = nil
  document.invalidateCollections()
  if element != nil:
    if parentElement == nil:
      element.invalidate()
    element.box = nil
    if element.internalElIndex == 0 and parentElement != nil:
      parentElement.childElIndicesInvalid = true
    element.internalElIndex = -1
    if element of SheetElement:
      SheetElement(element).removeSheet()
    for desc in element.elementDescendantsIncl:
      desc.applyStyleDependencies(DependencyInfo.default)
  #TODO assigned, shadow root, shadow root again, custom nodes, registered
  # observers
  #TODO not suppress observers => queue tree mutation record

proc remove*(node: Node) =
  if node.parentNode != nil:
    node.remove(suppressObservers = false)

# e may be nil
proc insertThrow(ctx: JSContext; e: cstring): JSValue =
  if e == nil:
    return JS_ThrowDOMException(ctx, "NotFoundError",
      "reference node is not a child of parent")
  return JS_ThrowDOMException(ctx, "HierarchyRequestError", e)

proc removeChild(ctx: JSContext; parent, node: Node): JSValue {.jsfunc.} =
  if Node(node.parentNode) != parent:
    return ctx.insertThrow(nil)
  node.remove()
  return ctx.toJS(node)

# before may be nil
proc insertBefore(parent, node, before: Node): Err[cstring] =
  let parent = ?parent.preInsertionValidity(node, before)
  let referenceChild = if before == node:
    node.nextSibling
  else:
    before
  parent.insert(node, referenceChild)
  ok()

proc insertBefore(ctx: JSContext; parent, node: Node; before: Option[Node]):
    JSValue {.jsfunc.} =
  let res = parent.insertBefore(node, before.get(nil))
  if res.isErr:
    return ctx.insertThrow(res.error)
  return ctx.toJS(node)

proc insertBeforeUndefined(ctx: JSContext; parent, node: Node;
    before: Option[Node]): JSValue =
  let res = parent.insertBefore(node, before.get(nil))
  if res.isErr:
    return ctx.insertThrow(res.error)
  return JS_UNDEFINED

proc appendChild(ctx: JSContext; parent, node: Node): JSValue {.jsfunc.} =
  return ctx.insertBefore(parent, node, none(Node))

#TODO this looks wrong. either pre-insert and throw or just insert...
proc append(parent, node: Node) =
  discard parent.insertBefore(node, nil)

# WARNING the ordering of the arguments in the standard is whack so this
# doesn't match that
# Note: the standard returns child if not err. We don't, it's just a
# pointless copy.
proc replace*(parent, child, node: Node): Err[cstring] =
  let parent = ?parent.checkParentValidity()
  if node.isHostIncludingInclusiveAncestor(parent):
    return err("parent must be an ancestor")
  if child.parentNode != parent:
    return err(nil)
  if not node.isValidChild():
    return err("node is not a valid child")
  if node of Text and parent of Document or
      node of DocumentType and not (parent of Document):
    return err("replacement cannot be placed in parent")
  let childNextSibling = child.nextSibling
  let childPreviousSibling = child.previousSibling
  if parent of Document:
    if node of DocumentFragment:
      let node = DocumentFragment(node)
      let elems = node.countChildren(Element)
      if elems > 1 or node.hasChild(Text):
        return err("document fragment has invalid children")
      elif elems == 1 and (parent.hasChildExcept(Element, child) or
          childNextSibling != nil and childNextSibling of DocumentType):
        return err("document fragment has invalid children")
    elif node of Element:
      if parent.hasChildExcept(Element, child):
        return err("document already has an element child")
      elif childNextSibling != nil and childNextSibling of DocumentType:
        return err("cannot insert element before document type")
    elif node of DocumentType:
      if parent.hasChildExcept(DocumentType, child) or
          childPreviousSibling != nil and childPreviousSibling of DocumentType:
        return err("cannot insert document type before an element node")
  let referenceChild = if childNextSibling == node:
    node.nextSibling
  else:
    childNextSibling
  #NOTE the standard says "if parent is not null", but the adoption step
  # that made it necessary has been removed.
  child.remove(suppressObservers = true)
  parent.insert(node, referenceChild, suppressObservers = true)
  #TODO tree mutation record
  ok()

proc replaceChild(ctx: JSContext; parent, node, child: Node): JSValue {.jsfunc.} =
  let res = parent.replace(child, node)
  if res.isErr:
    return ctx.insertThrow(res.error)
  return ctx.toJS(child)

proc replaceChildUndefined(ctx: JSContext; parent, node, child: Node): JSValue =
  let res = parent.replace(child, node)
  if res.isErr:
    return ctx.insertThrow(res.error)
  return JS_UNDEFINED

proc clone(node: Node; document = none(Document); deep = false): Node =
  let document = document.get(node.document)
  let copy = if node of Element:
    #TODO is value
    let element = Element(node)
    let x = document.newElement(element.localName, element.namespaceURI,
      element.prefix)
    x.id = element.id
    x.name = element.name
    x.classList = x.newDOMTokenList(satClass)
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
    let dummy = AttrDummyElement(
      internalNext: attr.ownerElement.document,
      internalElIndex: -1,
      attrs: @[data]
    )
    Node(dummy.newAttr(0))
  elif node of Text:
    let text = Text(node)
    let x = document.newText(text.data.s)
    Node(x)
  elif node of CDATASection:
    let x = document.newCDATASection("")
    #TODO is this really correct??
    # really, I don't know. only relevant with xhtml anyway...
    Node(x)
  elif node of Comment:
    let comment = Comment(node)
    let x = document.newComment(comment.data.s)
    Node(x)
  elif node of ProcessingInstruction:
    let procinst = ProcessingInstruction(node)
    let x = document.newProcessingInstruction(procinst.target, procinst.data.s)
    Node(x)
  elif node of Document:
    let document = Document(node)
    let x = newDocument(document.url)
    x.charset = document.charset
    x.contentType = document.contentType
    x.origin = document.origin
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
  if deep and node of ParentNode:
    let node = ParentNode(node)
    for child in node.childList:
      copy.append(child.clone(deep = true))
  return copy

proc cloneNode(node: Node; deep = false): Node {.jsfunc.} =
  #TODO shadow root
  return node.clone(deep = deep)

proc isSameNode(node, other: Node): bool {.jsfunc.} =
  return node == other

proc previousElementSiblingImpl(this: Node): Element =
  for it in this.precedingSiblings:
    if it of Element:
      return Element(it)
  nil

proc nextElementSiblingImpl(this: Node): Element =
  for it in this.subsequentSiblings:
    if it of Element:
      return Element(it)
  nil

proc childNodes(ctx: JSContext; node: Node): JSValue {.jsfget.} =
  return ctx.getWeakCollection(node, wwmChildNodes)

proc isEqualNode(node, other: Node): bool {.jsfunc.} =
  if node of DocumentType:
    if not (other of DocumentType):
      return false
    let node = DocumentType(node)
    let other = DocumentType(other)
    if node.name != other.name or node.publicId != other.publicId or
        node.systemId != other.systemId:
      return false
  elif node of ParentNode:
    let node = ParentNode(node)
    if node of Element:
      let node = Element(node)
      if not (other of ParentNode):
        return false
      let other = Element(other)
      if node.namespaceURI != other.namespaceURI or node.prefix != other.prefix or
          node.localName != other.localName or node.attrs.len != other.attrs.len:
        return false
      for i, attr in node.attrs.mypairs:
        if attr != other.attrs[i]:
          return false
    var it = other.firstChild
    for child in node.childList:
      if it == nil or not child.isEqualNode(it):
        return false
      it = it.nextSibling
  elif node of Attr:
    if not (other of Attr):
      return false
    if Attr(node).data != Attr(other).data:
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
  true

proc serializeFragmentInner(res: var string; child: Node; parentType: TagType) =
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
      res &= text.data.s
    else:
      res &= text.data.s.htmlEscape(mode = emText)
  elif child of Comment:
    res &= "<!--" & Comment(child).data.s & "-->"
  elif child of ProcessingInstruction:
    let inst = ProcessingInstruction(child)
    res &= "<?" & inst.target & " " & inst.data.s & '>'
  elif child of DocumentType:
    res &= "<!DOCTYPE " & DocumentType(child).name & '>'

proc serializeFragment(res: var string; node: Node) =
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
  if node of ParentNode:
    let node = ParentNode(node)
    for child in node.childList:
      res.serializeFragmentInner(child, parentType)

proc serializeFragment*(node: Node): string =
  result = ""
  result.serializeFragment(node)

proc findAncestor*(node: Node; tagType: TagType): Element =
  for element in node.ancestors:
    if element.tagType == tagType:
      return element
  return nil

proc setNodeValue(ctx: JSContext; node: Node; data: JSValueConst): Opt[void]
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

proc setTextContent(ctx: JSContext; node: Node; data: JSValueConst): Opt[void]
    {.jsfset: "textContent".} =
  if node of Element or node of DocumentFragment:
    let node = ParentNode(node)
    if JS_IsNull(data):
      node.replaceAll(nil)
    else:
      var res: string
      ?ctx.fromJS(data, res)
      node.replaceAll(move(res))
    return ok()
  return ctx.setNodeValue(node, data)

proc toNode(ctx: JSContext; nodes: openArray[JSValueConst]; document: Document):
    Opt[Node] =
  var node: Node = nil
  var fragment = false
  for it in nodes:
    var node0: Node
    if ctx.fromJS(it, node0).isErr:
      var s: string
      ?ctx.fromJS(it, s)
      node0 = ctx.newText(s)
    if node == nil:
      node = node0
    else:
      if not fragment:
        let fragment = document.newDocumentFragment()
        fragment.append(node)
        node = fragment
      node.append(node0)
  if node == nil:
    node = document.newDocumentFragment()
  ok(node)

proc prependImpl(ctx: JSContext; parent: Node; nodes: openArray[JSValueConst]):
    JSValue =
  let node = ctx.toNode(nodes, parent.document)
  if node.isErr:
    return JS_EXCEPTION
  return ctx.insertBeforeUndefined(parent, node.get, option(parent.firstChild))

proc appendImpl(ctx: JSContext; parent: Node; nodes: openArray[JSValueConst]):
    JSValue =
  let node = ctx.toNode(nodes, parent.document)
  if node.isErr:
    return JS_EXCEPTION
  return ctx.insertBeforeUndefined(parent, node.get, none(Node))

proc replaceChildrenImpl(ctx: JSContext; parent: Node;
    nodes: openArray[JSValueConst]): JSValue =
  let node0 = ctx.toNode(nodes, parent.document)
  if node0.isErr:
    return JS_EXCEPTION
  let node = node0.get
  let x = parent.preInsertionValidity(node, nil)
  if x.isErr:
    return ctx.insertThrow(x.error)
  let parent = x.get
  parent.replaceAll(node)
  return JS_UNDEFINED

# ParentNode
proc firstElementChild*(node: ParentNode): Element =
  for child in node.elementList:
    return child
  return nil

proc lastElementChild*(node: ParentNode): Element =
  for child in node.relementList:
    return child
  return nil

proc findFirstChildOf(node: ParentNode; tagType: TagType): Element =
  for element in node.elementList:
    if element.tagType == tagType:
      return element
  return nil

proc findLastChildOf(node: ParentNode; tagType: TagType): Element =
  for element in node.relementList:
    if element.tagType == tagType:
      return element
  return nil

proc findFirstChildNotOf(node: ParentNode; tagType: set[TagType]): Element =
  for element in node.elementList:
    if element.tagType notin tagType:
      return element
  return nil

proc getChildList*(node: ParentNode): seq[Node] =
  result = @[]
  for child in node.childList:
    result.add(child)

proc replaceAll(parent: ParentNode; node: Node) =
  let removedNodes = parent.getChildList()
  for child in removedNodes:
    child.remove(true)
  if node != nil:
    if node of DocumentFragment:
      let nodes = DocumentFragment(node).getChildList()
      for it in nodes:
        parent.insert(it, nil, suppressObservers = true)
    else:
      parent.insert(node, nil, suppressObservers = true)
  #TODO tree mutation record

proc replaceAll(parent: ParentNode; s: sink string) =
  let node = if s != "": parent.document.newText(s) else: nil
  parent.replaceAll(node)

proc childrenImpl(ctx: JSContext; node: ParentNode): JSValue =
  return ctx.getWeakCollection(node, wwmChildren)

proc childElementCountImpl(node: ParentNode): int =
  let last = node.lastElementChild
  if last == nil:
    return 0
  return last.elIndex + 1

proc countChildren(node: ParentNode; nodeType: type): int =
  result = 0
  for child in node.childList:
    if child of nodeType:
      inc result

proc hasChild(node: ParentNode; nodeType: type): bool =
  for child in node.childList:
    if child of nodeType:
      return true
  return false

proc hasChildExcept(node: ParentNode; nodeType: type; ex: Node): bool =
  for child in node.childList:
    if child == ex:
      continue
    if child of nodeType:
      return true
  return false

proc childTextContent*(node: ParentNode): string =
  result = ""
  for child in node.childList:
    if child of Text:
      result &= Text(child).data.s

proc getElementsByTagNameImpl(root: ParentNode; tagName: string):
    HTMLCollection =
  if tagName == "*":
    return root.newHTMLCollection(isElement, islive = true, childonly = false)
  let localName = tagName.toAtom()
  let localNameLower = localName.toLowerAscii()
  return root.newHTMLCollection(
    proc(node: Node): bool =
      if node of Element:
        let element = Element(node)
        if element.namespaceURI == satNamespaceHTML:
          return element.localName == localNameLower
        return element.localName == localName
      return false,
    islive = true,
    childonly = false
  )

proc getElementsByClassNameImpl(node: ParentNode; classNames: string):
    HTMLCollection =
  var classAtoms = newSeq[CAtom]()
  for class in classNames.split(AsciiWhitespace):
    classAtoms.add(class.toAtom())
  return node.newHTMLCollection(
    proc(node: Node): bool =
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

proc insertNode(parent: ParentNode; node, before: Node) =
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
  var nodes: seq[Element] = @[]
  for el in node.elementDescendantsIncl:
    #TODO shadow root
    if el.elementInsertionSteps():
      nodes.add(el)
  for el in nodes:
    el.postConnectionSteps()

# WARNING ditto
proc insert*(parent: ParentNode; node, before: Node;
    suppressObservers = false) =
  let nodes = if node of DocumentFragment:
    DocumentFragment(node).getChildList()
  else:
    @[node]
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
    parent.insertNode(node, before)

proc querySelectorImpl(ctx: JSContext; node: ParentNode; q: string): JSValue =
  let selectors = parseSelectors(q)
  if selectors.len == 0:
    return JS_ThrowDOMException(ctx, "SyntaxError", "invalid selector: %s",
      cstring(q))
  for element in node.elementDescendants:
    if element.matchesImpl(selectors):
      return ctx.toJS(element)
  return JS_NULL

proc querySelectorAllImpl(ctx: JSContext; node: ParentNode; q: string): JSValue =
  let selectors = parseSelectors(q)
  if selectors.len == 0:
    return JS_ThrowDOMException(ctx, "SyntaxError", "invalid selector: %s",
      cstring(q))
  return ctx.toJS(node.newNodeList(
    match = proc(node: Node): bool =
      if node of Element:
        return Element(node).matchesImpl(selectors)
      false,
    islive = false,
    childonly = false
  ))

# Collection
proc populateCollection(collection: Collection) =
  if collection.inclusive:
    if collection.match == nil or collection.match(collection.root):
      collection.snapshot.add(collection.root)
  if collection.root of ParentNode:
    let root = ParentNode(collection.root)
    if collection.childonly:
      for child in root.childList:
        if collection.match == nil or collection.match(child):
          collection.snapshot.add(child)
    else:
      for desc in root.descendants:
        if collection.match == nil or collection.match(desc):
          collection.snapshot.add(desc)

proc refreshCollection(collection: Collection) =
  if collection.invalid:
    assert collection.document != nil
    collection.snapshot.setLen(0)
    collection.populateCollection()
    collection.invalid = false

proc finalize0(collection: Collection) =
  if collection.document != nil:
    let document = collection.document
    let i = document.liveCollections.find(cast[ptr CollectionObj](collection))
    assert i != -1
    document.liveCollections.del(i)

proc finalize(collection: HTMLCollection) {.jsfin.} =
  collection.finalize0()

proc finalize(collection: NodeList) {.jsfin.} =
  collection.finalize0()

proc finalize(collection: NodeIterator) {.jsfin.} =
  collection.finalize0()
  JS_FreeValue(collection.ctx, collection.filter)

proc mark(rt: JSRuntime; this: NodeIterator; markFun: JS_MarkFunc) {.jsmark.} =
  JS_MarkValue(rt, this.filter, markFun)

proc finalize(collection: HTMLAllCollection) {.jsfin.} =
  collection.finalize0()

proc finalize(document: Document) {.jsfin.} =
  for it in document.liveCollections:
    cast[Collection](it).document = nil

proc getLength(collection: Collection): int =
  collection.refreshCollection()
  return collection.snapshot.len

proc findNode(collection: Collection; node: Node): int =
  collection.refreshCollection()
  return collection.snapshot.find(node)

proc newCollection[T: Collection](root: Node; match: CollectionMatchFun;
    islive, childonly: bool; inclusive = false): T =
  let document = root.document
  let collection = T(
    childonly: childonly,
    inclusive: inclusive,
    match: match,
    root: root,
    document: if islive: cast[ptr DocumentObj](document) else: nil
  )
  if islive:
    document.liveCollections.add(cast[ptr CollectionObj](collection))
    collection.invalid =  true
  else:
    collection.populateCollection()
  return collection

proc newHTMLCollection(root: Node; match: CollectionMatchFun;
    islive, childonly: bool): HTMLCollection =
  return newCollection[HTMLCollection](root, match, islive, childonly)

proc newNodeList(root: Node; match: CollectionMatchFun;
    islive, childonly: bool): NodeList =
  return newCollection[NodeList](root, match, islive, childonly)

# Text
proc newText*(document: Document; data: sink string): Text =
  return Text(internalNext: document, data: newRefString(data))

proc newText(ctx: JSContext; data: sink string = ""): Text {.jsctor.} =
  let window = ctx.getGlobal()
  return window.document.newText(data)

# CDATASection
proc newCDATASection(document: Document; data: string): CDATASection =
  return CDATASection(internalNext: document, data: newRefString(data))

# ProcessingInstruction
proc newProcessingInstruction(document: Document; target: string;
    data: sink string): ProcessingInstruction =
  return ProcessingInstruction(
    internalNext: document,
    target: target,
    data: newRefString(data)
  )

# Comment
proc newComment(document: Document; data: sink string): Comment =
  return Comment(
    internalNext: document,
    data: newRefString(data)
  )

proc newComment(ctx: JSContext; data: sink string = ""): Comment {.jsctor.} =
  let window = ctx.getGlobal()
  return window.document.newComment(data)

# DocumentFragment
proc newDocumentFragment(document: Document): DocumentFragment =
  return DocumentFragment(internalNext: document)

proc newDocumentFragment(ctx: JSContext): DocumentFragment {.jsctor.} =
  let window = ctx.getGlobal()
  return window.document.newDocumentFragment()

proc firstElementChild(this: DocumentFragment): Element {.jsfget.} =
  return ParentNode(this).firstElementChild

proc lastElementChild(this: DocumentFragment): Element {.jsfget.} =
  return ParentNode(this).lastElementChild

proc childElementCount(this: DocumentFragment): int {.jsfget.} =
  return this.childElementCountImpl

proc querySelector(ctx: JSContext; this: DocumentFragment; q: string): JSValue
    {.jsfunc.} =
  return ctx.querySelectorImpl(this, q)

proc querySelectorAll(ctx: JSContext; this: DocumentFragment; q: string):
    JSValue {.jsfunc.} =
  return ctx.querySelectorAllImpl(this, q)

proc prepend(ctx: JSContext; this: DocumentFragment;
    nodes: varargs[JSValueConst]): JSValue {.jsfunc.} =
  return ctx.prependImpl(this, nodes)

proc append(ctx: JSContext; this: DocumentFragment;
    nodes: varargs[JSValueConst]): JSValue {.jsfunc.} =
  return ctx.appendImpl(this, nodes)

proc replaceChildren(ctx: JSContext; this: DocumentFragment;
    nodes: varargs[JSValueConst]): JSValue {.jsfunc.} =
  return ctx.replaceChildrenImpl(this, nodes)

proc children(ctx: JSContext; parentNode: DocumentFragment): JSValue
    {.jsfget.} =
  return childrenImpl(ctx, parentNode)

# Document
proc newXMLDocument(): XMLDocument =
  let document = XMLDocument(
    url: parseURL0("about:blank"),
    contentType: satApplicationXml
  )
  document.implementation = DOMImplementation(document: document)
  return document

proc newDocument*(url: URL): Document =
  let document = Document(
    url: url,
    contentType: satApplicationXml,
    origin: url.origin
  )
  document.implementation = DOMImplementation(document: document)
  return document

proc newDocument(ctx: JSContext): Document {.jsctor.} =
  let global = ctx.getGlobal()
  let document = Document(
    url: parseURL0("about:blank"),
    contentType: satApplicationXml,
    origin: global.document.origin
  )
  document.implementation = DOMImplementation(document: document)
  return document

proc newDocumentType*(document: Document;
    name, publicId, systemId: sink string): DocumentType =
  return DocumentType(
    internalNext: document,
    name: name,
    publicId: publicId,
    systemId: systemId
  )

proc firstElementChild(this: Document): Element {.jsfget.} =
  return ParentNode(this).firstElementChild

proc lastElementChild(this: Document): Element {.jsfget.} =
  return ParentNode(this).lastElementChild

proc isxml(document: Document): bool =
  return document.contentType != satTextHtml

proc adopt(document: Document; node: Node) =
  let oldDocument = node.document
  if node.parentNode != nil:
    remove(node)
  if oldDocument != document:
    #TODO shadow root
    node.internalNext = document
    if node of ParentNode:
      let node = ParentNode(node)
      for desc in node.descendants:
        if desc.nextSibling == nil:
          desc.internalNext = document
    for i in countdown(oldDocument.liveCollections.high, 0):
      let collection = oldDocument.liveCollections[i]
      if collection.document == cast[ptr DocumentObj](document):
        collection.document = cast[ptr DocumentObj](document)
        document.liveCollections.add(collection)
        oldDocument.liveCollections.del(i)
    #TODO custom elements
    #..adopting steps

proc compatMode(document: Document): string {.jsfget.} =
  if document.mode == QUIRKS:
    return "BackCompat"
  return "CSS1Compat"

proc forms(document: Document): HTMLCollection {.jsfget.} =
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

proc images(document: Document): HTMLCollection {.jsfget.} =
  if document.cachedImages == nil:
    document.cachedImages = document.newHTMLCollection(
      match = isImage,
      islive = true,
      childonly = false
    )
  return document.cachedImages

proc getURL(ctx: JSContext; document: Document): JSValue {.jsfget: "URL".} =
  return ctx.toJS($document.url)

proc getCookieWindow(ctx: JSContext; document: Document): Opt[Window] =
  let window = document.window
  if window == nil or document.url.schemeType notin {stHttp, stHttps}:
    return ok(nil)
  if document.origin.t == otOpaque:
    JS_ThrowDOMException(ctx, "SecurityError",
      "sandboxed iframe cannot access cookies")
    return err()
  ok(window)

proc cookie(ctx: JSContext; document: Document): JSValue {.jsfget.} =
  let window0 = ctx.getCookieWindow(document)
  if window0.isErr:
    return JS_EXCEPTION
  let window = window0.get
  if window == nil:
    return ctx.toJS("")
  let response = window.loader.doRequest(newRequest("x-cha-cookie:get-all"))
  if response.res != 0:
    return JS_ThrowInternalError(ctx, "internal error in cookie getter")
  response.resume()
  let cookie = response.body.readAll()
  return ctx.toJS(cookie)

proc setCookie(ctx: JSContext; document: Document; cookie: string):
    Opt[void] {.jsfset: "cookie".} =
  let window = ?ctx.getCookieWindow(document)
  if window == nil:
    return ok()
  let headers = newHeaders(hgRequest, {"Set-Cookie": cookie})
  let req = newRequest("x-cha-cookie:set", hmPost, headers,
    credentials = cmOmit)
  let response = window.loader.doRequest(req)
  if response.res == 0:
    response.close()
  ok()

proc focus*(document: Document): Element {.jsfget: "activeElement".} =
  return document.internalFocus

proc setFocus*(document: Document; element: Element) =
  if document.focus != nil:
    document.focus.invalidate(dtFocus)
  document.internalFocus = element
  if element != nil:
    element.invalidate(dtFocus)

proc findAutoFocus*(document: Document): Element =
  for child in document.elementDescendants:
    if child.attrb(satAutofocus):
      return child
  return nil

proc target*(document: Document): Element =
  return document.internalTarget

proc setTarget*(document: Document; element: Element) =
  if document.target != nil:
    document.target.invalidate(dtTarget)
  document.internalTarget = element
  if element != nil:
    element.invalidate(dtTarget)

proc queryCommandSupported(document: Document): bool {.jsfunc.} =
  return false

proc createCDATASection(ctx: JSContext; document: Document; data: string):
    JSValue {.jsfunc.} =
  if not document.isxml:
    return JS_ThrowDOMException(ctx, "NotSupportedError",
      "CDATA sections are not supported in HTML")
  if "]]>" in data:
    return JS_ThrowDOMException(ctx, "InvalidCharacterError",
      "CDATA sections may not contain the string ]]>")
  return ctx.toJS(newCDATASection(document, data))

proc createComment*(document: Document; data: string): Comment {.jsfunc.} =
  return newComment(document, data)

proc createProcessingInstruction(ctx: JSContext; document: Document;
    target, data: string): JSValue {.jsfunc.} =
  if not target.matchNameProduction() or "?>" in data:
    return JS_ThrowDOMException(ctx, "InvalidCharacterError",
      "invalid data for processing instruction")
  return ctx.toJS(newProcessingInstruction(document, target, data))

proc createEvent(ctx: JSContext; document: Document; atom: CAtom):
    JSValue {.jsfunc.} =
  case atom.toLowerAscii().toStaticAtom()
  of satCustomevent:
    return ctx.toJS(ctx.newCustomEvent(satUempty.toAtom()))
  of satEvent, satEvents, satHtmlevents, satSvgevents:
    return ctx.toJS(newEvent(satUempty.toAtom(), nil,
      bubbles = false, cancelable = false))
  of satUievent, satUievents:
    return ctx.toJS(newUIEvent(satUempty.toAtom()))
  of satMouseevent, satMouseevents:
    return ctx.toJS(newMouseEvent(satUempty.toAtom()))
  else:
    return JS_ThrowDOMException(ctx, "NotSupportedError", "event not supported")

proc location(document: Document): Location {.jsfget.} =
  if document.window == nil:
    return nil
  return document.window.location

proc setLocation*(ctx: JSContext; document: Document; s: string): JSValue
    {.jsfset: "location".} =
  if document.location == nil:
    return JS_ThrowTypeError(ctx, "document.location is not an object")
  let url = document.parseURL0(s)
  if url == nil:
    return JS_ThrowDOMException(ctx, "Invalid URL", "SyntaxError")
  document.window.navigate(url)
  return JS_UNDEFINED

proc scriptingEnabled*(document: Document): bool =
  if document.window == nil:
    return false
  return document.window.settings.scripting != smFalse

proc findFirst*(document: Document; tagType: TagType): HTMLElement =
  for element in document.elementDescendants(tagType):
    return HTMLElement(element)
  nil

proc head*(document: Document): HTMLElement {.jsfget.} =
  return document.findFirst(TAG_HEAD)

proc body*(document: Document): HTMLElement {.jsfget.} =
  return document.findFirst(TAG_BODY)

proc getElementById*(document: Document; id: string): Element {.jsfunc.} =
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
      proc(node: Node): bool =
        return false,
      islive = false,
      childonly = true
    )
  return document.newNodeList(
    proc(node: Node): bool =
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

proc children(ctx: JSContext; parentNode: Document): JSValue {.jsfget.} =
  return childrenImpl(ctx, parentNode)

proc querySelector(ctx: JSContext; this: Document; q: string): JSValue
    {.jsfunc.} =
  return ctx.querySelectorImpl(this, q)

proc querySelectorAll(ctx: JSContext; this: Document; q: string): JSValue
    {.jsfunc.} =
  return ctx.querySelectorAllImpl(this, q)

proc validateName(ctx: JSContext; name: string): Opt[void] =
  if not name.matchNameProduction():
    JS_ThrowDOMException(ctx, "InvalidCharacterError",
      "invalid character in name")
    return err()
  ok()

proc validateQName(ctx: JSContext; qname: string): Opt[void] =
  if not qname.matchQNameProduction():
    JS_ThrowDOMException(ctx, "InvalidCharacterError",
      "invalid character in qualified name")
    return err()
  ok()

proc baseURL*(document: Document): URL =
  #TODO frozen base url...
  var href = ""
  for base in document.elementDescendants(TAG_BASE):
    if base.attrb(satHref):
      href = base.attr(satHref)
  if href == "":
    return document.url
  let url = parseURL0(href, document.url)
  if url == nil:
    return document.url
  return url

proc parseURL0*(document: Document; s: string): URL =
  #TODO encodings
  return parseURL0(s, document.baseURL)

proc parseURL*(document: Document; s: string): Opt[URL] =
  #TODO encodings
  let url = document.parseURL0(s)
  if url == nil:
    return err()
  ok(url)

proc title*(document: Document): string {.jsfget.} =
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
  for collection in document.liveCollections:
    collection.invalid = true

proc isValidCustomElementName(atom: CAtom): bool =
  const Disallowed = [
    satAnnotationXml, satColorDashProfile, satFontDashFace,
    satFontDashFaceDashSrc, satFontDashFaceDashUri, satFontDashFaceDashFormat,
    satFontDashFaceDashName, satMissingDashGlyph
  ]
  if atom.toStaticAtom() in Disallowed:
    return false
  let s = $atom
  if s.len <= 0 or s[0] notin AsciiLowerAlpha:
    return false
  var dash = false
  for c in s:
    if c in AsciiUpperAlpha:
      return false
    dash = dash or c == '-'
  dash

#TODO options/custom elements
proc createElement(ctx: JSContext; document: Document; localName: string):
    Opt[Element] {.jsfunc.} =
  ?ctx.validateName(localName)
  let localName = if not document.isxml:
    localName.toAtomLower()
  else:
    localName.toAtom()
  let namespace = if not document.isxml:
    #TODO or content type is application/xhtml+xml
    Namespace.HTML
  else:
    NO_NAMESPACE
  let element = document.newElement(localName, namespace)
  ok(element)

proc validateAndExtract(ctx: JSContext; document: Document; qname: string;
    namespace, prefixOut, localNameOut: var CAtom): Opt[void] =
  ?ctx.validateQName(qname)
  if namespace == satUempty.toAtom():
    namespace = CAtomNull
  var prefix = ""
  var localName = qname.until(':')
  if localName.len < qname.len:
    prefix = move(localName)
    localName = qname.substr(prefix.len + 1)
  if namespace == CAtomNull and prefix != "":
    JS_ThrowDOMException(ctx, "NamespaceError",
      "got namespace prefix, but no namespace")
    return err()
  let sns = namespace.toStaticAtom()
  if prefix == "xml" and sns != satNamespaceXML:
    JS_ThrowDOMException(ctx, "NamespaceError", "expected XML namespace")
    return err()
  if (qname == "xmlns" or prefix == "xmlns") != (sns == satNamespaceXMLNS):
    JS_ThrowDOMException(ctx, "NamespaceError", "expected XMLNS namespace")
    return err()
  prefixOut = if prefix == "": CAtomNull else: prefix.toAtom()
  localNameOut = localName.toAtom()
  ok()

proc createElementNS(ctx: JSContext; document: Document; namespace: CAtom;
    qname: string): Opt[Element] {.jsfunc.} =
  var namespace = namespace
  var prefix, localName: CAtom
  ?ctx.validateAndExtract(document, qname, namespace, prefix, localName)
  #TODO custom elements (is)
  return ok(document.newElement(localName, namespace, prefix))

proc createDocumentFragment(document: Document): DocumentFragment {.jsfunc.} =
  return newDocumentFragment(document)

proc createDocumentType(ctx: JSContext; implementation: DOMImplementation;
    qualifiedName, publicId, systemId: string): Opt[DocumentType] {.jsfunc.} =
  ?ctx.validateQName(qualifiedName)
  let document = implementation.document
  ok(document.newDocumentType(qualifiedName, publicId, systemId))

proc createDocument(ctx: JSContext; implementation: DOMImplementation;
    namespace: CAtom; qname0: JSValueConst = JS_NULL;
    doctype = none(DocumentType)): Opt[XMLDocument] {.jsfunc.} =
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

proc createHTMLDocument(ctx: JSContext; implementation: DOMImplementation;
    title: JSValueConst = JS_UNDEFINED): Opt[Document] {.jsfunc.} =
  let doc = newDocument(ctx)
  doc.contentType = satTextHtml
  doc.append(doc.newDocumentType("html", "", ""))
  let html = doc.newHTMLElement(TAG_HTML)
  doc.append(html)
  let head = doc.newHTMLElement(TAG_HEAD)
  html.append(head)
  if not JS_IsUndefined(title):
    var s: string
    ?ctx.fromJS(title, s)
    let titleElement = doc.newHTMLElement(TAG_TITLE)
    titleElement.append(doc.newText(s))
    head.append(titleElement)
  html.append(doc.newHTMLElement(TAG_BODY))
  doc.origin = implementation.document.origin
  ok(doc)

proc hasFeature(implementation: DOMImplementation): bool {.jsfunc.} =
  return true

proc createTextNode(document: Document; data: sink string): Text {.jsfunc.} =
  return newText(document, data)

proc prepend(ctx: JSContext; this: Document; nodes: varargs[JSValueConst]):
    JSValue {.jsfunc.} =
  return ctx.prependImpl(this, nodes)

proc append(ctx: JSContext; this: Document; nodes: varargs[JSValueConst]):
    JSValue {.jsfunc.} =
  return ctx.appendImpl(this, nodes)

proc replaceChildren(ctx: JSContext; this: Document;
    nodes: varargs[JSValueConst]): JSValue {.jsfunc.} =
  return ctx.replaceChildrenImpl(this, nodes)

const (ReflectMap, TagReflectMap, ReflectAllStartIndex) = (proc(): (
    seq[ReflectEntry],
    array[TagType, seq[int16]],
    int16) =
  var i: int16 = 0
  while i < ReflectMap0.len:
    let x = ReflectMap0[i]
    result[0].add(x.e)
    if x.tags.len == 0:
      break
    for tag in x.tags:
      result[1][tag].add(i)
    inc i
  result[2] = i
  while i < ReflectMap0.len:
    let x = ReflectMap0[i]
    assert x.tags.len == 0
    result[0].add(x.e)
    inc i
)()

proc parseFormMethod(s: string): FormMethod =
  return parseEnumNoCase[FormMethod](s).get(fmGet)

proc getReflectElement(ctx: JSContext; this: JSValueConst; magic: cint):
    HTMLElement =
  let rtOpaque = JS_GetRuntime(ctx).getOpaque()
  let magic = uint16(magic)
  let myClass = JS_GetClassID(this)
  let parent = rtOpaque.classes[myClass].parent
  let class = JSClassID(magic shr 9) + parent
  if class != parent and class != myClass:
    JS_ThrowTypeError(ctx, "invalid tag type")
    return nil
  var element: HTMLElement
  if ctx.fromJS(this, element).isErr:
    return nil
  return element

proc jsReflectGet(ctx: JSContext; this: JSValueConst; magic: cint): JSValue
    {.cdecl.} =
  let entry = ReflectMap[uint16(magic) and 0x1FF]
  let element = ctx.getReflectElement(this, magic)
  if element == nil:
    return JS_EXCEPTION
  case entry.t
  of rtStr: return ctx.toJS(element.attr(entry.attrname))
  of rtUrl:
    let s = element.attr(entry.attrname)
    if url := element.document.parseURL(s):
      return ctx.toJS($url)
    return ctx.toJS(s)
  of rtReferrerPolicy:
    if s := element.referrerPolicy:
      return ctx.toJS($s)
    return ctx.toJS("")
  of rtCrossOrigin:
    case (let co = element.crossOrigin; co)
    of caNoCors: return JS_NULL
    else: return ctx.toJS($co)
  of rtMethod:
    let s = element.attr(entry.attrname)
    if entry.attrname == satFormmethod and s == "":
      return ctx.toJS("")
    return ctx.toJS($parseFormMethod(s))
  of rtBool: return ctx.toJS(element.attrb(entry.attrname))
  of rtLong:
    let i = cast[int32](entry.u)
    return ctx.toJS(element.attrl(entry.attrname).get(i))
  of rtUlong: return ctx.toJS(element.attrul(entry.attrname).get(entry.u))
  of rtUlongGz: return ctx.toJS(element.attrulgz(entry.attrname).get(entry.u))
  of rtDoubleGz:
    # we do not have fractional default values, so we actually store them
    # as uint32 and convert here.
    let f = float32(entry.u)
    return ctx.toJS(element.attrdgz(entry.attrname).get(f))
  of rtFunction: return JS_NULL

proc jsReflectSet(ctx: JSContext; this, val: JSValueConst; magic: cint):
    JSValue {.cdecl.} =
  let entry = ReflectMap[uint16(magic) and 0x1FF]
  let element = ctx.getReflectElement(this, magic)
  if element == nil:
    return JS_EXCEPTION
  case entry.t
  of rtStr, rtUrl, rtReferrerPolicy, rtMethod:
    var x: string
    ?ctx.fromJS(val, x)
    element.attr(entry.attrname, x)
  of rtCrossOrigin:
    if JS_IsNull(val):
      let i = element.findAttr(entry.attrname.toAtom())
      if i != -1:
        ctx.delAttr(element, i)
    else:
      var x: string
      ?ctx.fromJS(val, x)
      element.attr(entry.attrname, x)
  of rtBool:
    var x: bool
    ?ctx.fromJS(val, x)
    if x:
      element.attr(entry.attrname, "")
    else:
      let i = element.findAttr(entry.attrname.toAtom())
      if i != -1:
        ctx.delAttr(element, i)
  of rtLong:
    var x: int32
    ?ctx.fromJS(val, x)
    element.attrl(entry.attrname, x)
  of rtUlong:
    var x: uint32
    ?ctx.fromJS(val, x)
    element.attrul(entry.attrname, x)
  of rtUlongGz:
    var x: uint32
    ?ctx.fromJS(val, x)
    element.attrulgz(entry.attrname, x)
  of rtDoubleGz:
    var x: float64
    ?ctx.fromJS(val, x)
    if classify(x) in {fcInf, fcNegInf, fcNan}:
      return JS_ThrowTypeError(ctx, "double expected")
    element.attrd(entry.attrname, x)
  of rtFunction:
    let ctype = cast[StaticAtom](entry.u)
    return ctx.eventReflectSet0(element, val, magic, jsReflectSet, ctype)
  return JS_DupValue(ctx, val)

proc findMagic(ctype: StaticAtom): cint =
  for i in ReflectAllStartIndex ..< int16(ReflectMap.len):
    if ReflectMap[i].t == rtFunction and ReflectMap[i].u == uint32(ctype):
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
  let sheet = parseStylesheet(ua, nil, addr document.window.settings,
    coUserAgent, CAtomNull)
  document.uaSheetsHead = sheet
  if document.documentElement != nil:
    document.documentElement.invalidate()

proc applyQuirksSheet*(document: Document) =
  if document.window == nil:
    return
  const quirks = staticRead"res/quirk.css"
  let sheet = parseStylesheet(quirks, nil, addr document.window.settings,
    coUserAgent, CAtomNull)
  document.uaSheetsHead.next = sheet
  if document.documentElement != nil:
    document.documentElement.invalidate()

proc applyUserSheet*(document: Document; user: string) =
  document.userSheet = parseStylesheet(user, nil,
    addr document.window.settings, coUser, CAtomNull)
  if document.documentElement != nil:
    document.documentElement.invalidate()

proc getRuleMap*(document: Document): CSSRuleMap =
  if document.ruleMap == nil:
    let map = CSSRuleMap()
    var sheet = document.uaSheetsHead
    while sheet != nil:
      map.add(sheet)
      sheet = sheet.next
    map.add(document.userSheet)
    sheet = document.authorSheetsHead
    while sheet != nil:
      if not sheet.disabled and sheet.applies:
        map.add(sheet)
      sheet = sheet.next
    document.ruleMap = map
  return document.ruleMap

proc windowChange*(window: Window) =
  let document = window.document
  document.ruleMap = nil
  if document.documentElement != nil:
    document.documentElement.invalidate()
  let baseURL = document.baseURL
  var sheet = document.uaSheetsHead
  while sheet != nil:
    sheet.windowChange(baseURL)
    sheet = sheet.next
  if document.userSheet != nil:
    document.userSheet.windowChange(baseURL)
  sheet = document.authorSheetsHead
  while sheet != nil:
    sheet.windowChange(baseURL)
    if sheet.media != "":
      var ctx = initCSSParser(sheet.media)
      let media = ctx.parseMediaQueryList(window.settings.attrsp)
      sheet.applies = media.applies(addr window.settings)
    sheet = sheet.next

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

# https://html.spec.whatwg.org/multipage/dynamic-markup-insertion.html#document-write-steps
proc write(ctx: JSContext; document: Document; args: varargs[JSValueConst]):
    JSValue {.jsfunc.} =
  var text = ""
  for arg in args:
    var s: string
    if ctx.fromJS(arg, s).isErr:
      return JS_EXCEPTION
    text &= s
  if document.isxml:
    return JS_ThrowDOMException(ctx, "InvalidStateError",
      "document.write not supported in XML documents")
  if document.throwOnDynamicMarkupInsertion > 0:
    return JS_ThrowDOMException(ctx, "InvalidStateError",
      "throw-on-dynamic-markup-insertion counter > 0")
  if document.activeParserWasAborted:
    return JS_UNDEFINED
  assert document.parser != nil
  #TODO if insertion point is undefined... (open document)
  let buffer = document.writeBuffersTop
  if buffer == nil:
    return JS_UNDEFINED #TODO (probably covered by open above)
  buffer.data &= text
  if document.parserBlockingScript == nil:
    parseDocumentWriteChunkImpl(document.parser)
  return JS_UNDEFINED

proc childElementCount(this: Document): int {.jsfget.} =
  return this.childElementCountImpl

proc documentElement*(document: Document): Element {.jsfget.} =
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

# DocumentType
proc remove(this: DocumentType) {.jsfunc.} =
  Node(this).remove()

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
        ctx.call(filter, JS_UNDEFINED, node)
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

proc length(tokenList: DOMTokenList): int {.jsfget.} =
  return tokenList.toks.len

proc item(ctx: JSContext; tokenList: DOMTokenList; u: uint32): JSValue
    {.jsfunc.} =
  if int64(u) < int64(int.high):
    let i = int(u)
    if i < tokenList.toks.len:
      return ctx.toJS(tokenList.toks[i])
  return JS_NULL

proc contains(tokenList: DOMTokenList; a: CAtom): bool =
  return a in tokenList.toks

proc containsIgnoreCase(tokenList: DOMTokenList; a: StaticAtom): bool =
  return tokenList.toks.containsIgnoreCase(a)

proc jsContains(tokenList: DOMTokenList; s: string): bool
    {.jsfunc: "contains".} =
  return s.toAtom() in tokenList.toks

proc `$`(tokenList: DOMTokenList): string {.jsfunc: "toString".} =
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

proc validateDOMToken(ctx: JSContext; tok: JSValueConst): Opt[CAtom] =
  var res: string
  ?ctx.fromJS(tok, res)
  if res == "":
    JS_ThrowDOMException(ctx, "SyntaxError", "got an empty string")
    return err()
  if AsciiWhitespace in res:
    JS_ThrowDOMException(ctx, "InvalidCharacterError",
      "got a string containing whitespace")
    return err()
  ok(res.toAtom())

proc add(ctx: JSContext; tokenList: DOMTokenList;
    tokens: varargs[JSValueConst]): Opt[void] {.jsfunc.} =
  var toks = newSeqOfCap[CAtom](tokens.len)
  for tok in tokens:
    toks.add(?ctx.validateDOMToken(tok))
  tokenList.toks.add(toks)
  tokenList.update()
  ok()

proc remove(ctx: JSContext; tokenList: DOMTokenList;
    tokens: varargs[JSValueConst]): Opt[void] {.jsfunc.} =
  var toks = newSeqOfCap[CAtom](tokens.len)
  for tok in tokens:
    toks.add(?ctx.validateDOMToken(tok))
  for tok in toks:
    let i = tokenList.toks.find(tok)
    if i != -1:
      tokenList.toks.delete(i)
  tokenList.update()
  ok()

proc toggle(ctx: JSContext; tokenList: DOMTokenList; token: JSValueConst;
    force = none(bool)): Opt[bool] {.jsfunc.} =
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
  ok(false)

proc replace(ctx: JSContext; tokenList: DOMTokenList;
    token, newToken: JSValueConst): Opt[bool] {.jsfunc.} =
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

proc supports(ctx: JSContext; tokenList: DOMTokenList; token: string): JSValue
    {.jsfunc.} =
  let localName = tokenList.localName.toStaticAtom()
  for it in SupportedTokensMap:
    if it[0] == localName:
      let lowercase = token.toLowerAscii()
      if lowercase in it[1]:
        return JS_TRUE
      return JS_FALSE
  return JS_ThrowTypeError(ctx, "No supported tokens defined for attribute")

proc value(tokenList: DOMTokenList): string {.jsfget.} =
  return $tokenList

proc getter(ctx: JSContext; this: DOMTokenList; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  return case ctx.fromIdx(atom, u)
  of fiIdx: ctx.item(this, u).uninitIfNull()
  of fiStr: JS_UNINITIALIZED
  of fiErr: JS_EXCEPTION

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

proc setter(ctx: JSContext; map: DOMStringMap; name, value: string): Opt[void]
    {.jssetprop.} =
  var washy = false
  for c in name:
    if not washy or c notin AsciiLowerAlpha:
      washy = c == '-'
      continue
    JS_ThrowDOMException(ctx, "InvalidCharacterError",
      "lower case after hyphen is not allowed in dataset")
    return err()
  let name = "data-" & name.camelToKebabCase()
  ?ctx.validateName(name)
  let aname = name.toAtom()
  map.target.attr(aname, value)
  ok()

proc names(ctx: JSContext; map: DOMStringMap): JSPropertyEnumList
    {.jspropnames.} =
  var list = newJSPropertyEnumList(ctx, uint32(map.target.attrs.len))
  for attr in map.target.attrs:
    let k = $attr.qualifiedName
    if k.startsWith("data-") and AsciiUpperAlpha notin k:
      list.add(k["data-".len .. ^1].kebabToCamelCase())
  return list

proc dataset(ctx: JSContext; element: HTMLElement): JSValue {.jsfget.} =
  return ctx.getWeakCollection(element, wwmDataset)

# NodeList
proc length(this: NodeList): uint32 {.jsfget.} =
  return uint32(this.getLength())

proc item(this: NodeList; u: uint32): Node {.jsfunc.} =
  let i = int(u)
  if i < this.getLength():
    return this.snapshot[i]
  return nil

proc getter(ctx: JSContext; this: NodeList; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  var s: string
  return case ctx.fromIdx(atom, u, s)
  of fiIdx: ctx.toJS(this.item(u)).uninitIfNull()
  of fiStr: JS_UNINITIALIZED
  of fiErr: JS_EXCEPTION

proc names(ctx: JSContext; this: NodeList): JSPropertyEnumList {.jspropnames.} =
  let L = this.length
  var list = newJSPropertyEnumList(ctx, L)
  for u in 0 ..< L:
    list.add(u)
  return list

# HTMLCollection
proc length(this: HTMLCollection): uint32 {.jsfget.} =
  return uint32(this.getLength())

proc item(this: HTMLCollection; u: uint32): Element {.jsfunc.} =
  if u < this.length:
    return Element(this.snapshot[int(u)])
  return nil

proc namedItem(this: HTMLCollection; atom: CAtom): Element {.jsfunc.} =
  this.refreshCollection()
  for it in this.snapshot:
    let it = Element(it)
    if it.id == atom or it.namespaceURI == satNamespaceHTML and it.name == atom:
      return it
  return nil

proc getter(ctx: JSContext; this: HTMLCollection; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  var s: CAtom
  return case ctx.fromIdx(atom, u, s)
  of fiIdx: ctx.toJS(this.item(u)).uninitIfNull()
  of fiStr: ctx.toJS(this.namedItem(s)).uninitIfNull()
  of fiErr: JS_EXCEPTION

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
    proc(node: Node): bool =
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
  var s: CAtom
  return case ctx.fromIdx(atom, u, s)
  of fiIdx: ctx.toJS(this.item(u)).uninitIfNull()
  of fiStr: ctx.namedItem(this, s).uninitIfNull()
  of fiErr: JS_EXCEPTION

# HTMLAllCollection
proc length(this: HTMLAllCollection): uint32 {.jsfget.} =
  return uint32(this.getLength())

proc item(this: HTMLAllCollection; u: uint32): Element {.jsfunc.} =
  let i = int(u)
  if i < this.getLength():
    return Element(this.snapshot[i])
  return nil

proc getter(ctx: JSContext; this: HTMLAllCollection; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  return case ctx.fromIdx(atom, u)
  of fiIdx: ctx.toJS(this.item(u)).uninitIfNull()
  of fiStr: JS_UNINITIALIZED
  of fiErr: JS_EXCEPTION

proc names(ctx: JSContext; this: HTMLAllCollection): JSPropertyEnumList
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

proc document(location: Location): Document =
  return location.window.document

proc url(location: Location): URL =
  let document = location.document
  if document != nil:
    return document.url
  return parseURL0("about:blank")

# Note: we do not implement security checks (as documents are in separate
# windows anyway).
proc `$`(location: Location): string {.jsuffunc: "toString".} =
  return location.url.serialize()

proc href(location: Location): string {.jsuffget.} =
  return $location

proc setHref(ctx: JSContext; location: Location; s: string): JSValue {.
    jsfset: "href", jsuffunc: "assign", jsuffunc: "replace".} =
  if location.document == nil:
    return JS_UNDEFINED
  return ctx.setLocation(location.document, s)

proc reload(location: Location) {.jsuffunc.} =
  if location.document == nil:
    return
  location.document.window.navigate(location.url)

proc origin*(location: Location): string {.jsuffget.} =
  return location.url.jsOrigin

proc protocol(location: Location): string {.jsuffget.} =
  return location.url.protocol

proc setProtocol(ctx: JSContext; location: Location; s: string): JSValue
    {.jsfset: "protocol".} =
  let document = location.document
  if document == nil:
    return JS_UNDEFINED
  let copyURL = newURL(location.url)
  copyURL.setProtocol(s)
  if copyURL.schemeType notin {stHttp, stHttps}:
    return JS_ThrowDOMException(ctx, "SyntaxError", "invalid URL")
  document.window.navigate(copyURL)
  return JS_UNDEFINED

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
proc newAttr(element: Element; dataIdx: int): Attr =
  let attr = Attr(
    internalNext: element.document,
    dataIdx: dataIdx,
    ownerElement: element,
  )
  let namespace = attr.data.namespace
  let qualifiedName = attr.data.qualifiedName
  if namespace == CAtomNull: # no namespace -> qualifiedName == localName
    attr.prefix = CAtomNull
    attr.localName = qualifiedName
  else: # namespace -> qualifiedName == prefix & ':' & localName
    let prefixs = ($qualifiedName).until(':')
    let prefixLen = prefixs.len
    attr.prefix = prefixs.toAtom()
    attr.localName = ($qualifiedName).substr(prefixLen + 1).toAtom()
  return attr

proc jsOwnerElement(attr: Attr): Element {.jsfget: "ownerElement".} =
  if attr.ownerElement of AttrDummyElement:
    return nil
  return attr.ownerElement

proc ownerDocument(attr: Attr): Document {.jsfget.} =
  return attr.ownerElement.ownerDocument

proc data(attr: Attr): lent AttrData =
  return attr.ownerElement.attrs[attr.dataIdx]

proc namespaceURI(attr: Attr): CAtom {.jsfget.} =
  return attr.data.namespace

proc value(attr: Attr): string {.jsfget.} =
  return attr.data.value

proc name(attr: Attr): CAtom {.jsfget.} =
  return attr.data.qualifiedName

proc setValue(attr: Attr; s: string) {.jsfset: "value".} =
  attr.ownerElement.attr(attr.data.qualifiedName, s)

# NamedNodeMap
proc findAttr(map: NamedNodeMap; dataIdx: int): int =
  for i, attr in map.attrlist.mypairs:
    if attr.dataIdx == dataIdx:
      return i
  return -1

proc getAttr(map: NamedNodeMap; dataIdx: int): Attr =
  let i = map.findAttr(dataIdx)
  if i != -1:
    return map.attrlist[i]
  let attr = map.element.newAttr(dataIdx)
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

proc length(map: NamedNodeMap): uint32 {.jsfget.} =
  return uint32(map.element.attrs.len)

proc item(map: NamedNodeMap; i: uint32): Attr {.jsfunc.} =
  if int(i) < map.element.attrs.len:
    return map.getAttr(int(i))
  return nil

proc getter(ctx: JSContext; this: NamedNodeMap; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  var s: CAtom
  return case ctx.fromIdx(atom, u, s)
  of fiIdx: ctx.toJS(this.item(u)).uninitIfNull()
  of fiStr: ctx.toJS(this.getNamedItem(s)).uninitIfNull()
  of fiErr: JS_EXCEPTION

proc names(ctx: JSContext; map: NamedNodeMap): JSPropertyEnumList
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
proc length(this: CharacterData): int {.jsfget.} =
  return ($this.data).utf16Len

proc previousElementSibling(this: CharacterData): Element {.jsfget.} =
  return this.previousElementSiblingImpl

proc nextElementSibling(this: CharacterData): Element {.jsfget.} =
  return this.nextElementSiblingImpl

proc remove(this: CharacterData) {.jsfunc.} =
  Node(this).remove()

# Element
proc hash(element: Element): Hash =
  return hash(cast[pointer](element))

proc firstElementChild(this: Element): Element {.jsfget.} =
  return ParentNode(this).firstElementChild

proc lastElementChild(this: Element): Element {.jsfget.} =
  return ParentNode(this).lastElementChild

proc childElementCount(this: Element): int {.jsfget.} =
  return this.childElementCountImpl

proc isFirstVisualNode*(element: Element): bool =
  if element.elIndex == 0:
    let parent = element.parentNode
    for child in parent.childList:
      if child == element:
        return true
      if child of Text and not Text(child).data.s.onlyWhitespace():
        break
  return false

proc isLastVisualNode*(element: Element): bool =
  let parent = element.parentNode
  for child in parent.rchildList:
    if child == element:
      return true
    if child of Element:
      break
    if child of Text and not Text(child).data.s.onlyWhitespace():
      break
  return false

proc innerHTML(element: Element): string {.jsfget.} =
  #TODO xml
  return element.serializeFragment()

proc outerHTML(element: Element): string {.jsfget.} =
  #TODO xml
  result = ""
  result.serializeFragmentInner(element, TAG_UNKNOWN)

proc tagTypeNoNS(element: Element): TagType =
  return element.localName.toTagType()

proc tagType*(element: Element; namespace = satNamespaceHTML): TagType =
  if element.namespaceURI != namespace:
    return TAG_UNKNOWN
  return element.tagTypeNoNS

proc tagName(element: Element): string {.jsfget.} =
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

proc cmpAttrName(a: AttrData; b: CAtom): int =
  return cmp(uint32(a.qualifiedName), uint32(b))

proc findAttr(element: Element; qualifiedName: CAtom): int =
  let qualifiedName = element.normalizeAttrQName(qualifiedName)
  let n = element.attrs.lowerBound(qualifiedName, cmpAttrName)
  if n < element.attrs.len and element.attrs[n].qualifiedName == qualifiedName:
    return n
  return -1

proc matchesLocalName(qualifiedName, localName: CAtom): bool =
  let i = ($qualifiedName).find(':') + 1
  if i == 0:
    return qualifiedName == localName
  return ($qualifiedName).toOpenArray(i, ($qualifiedName).high) == $localName

proc findAttrNS(element: Element; namespace, localName: CAtom): int =
  if namespace == CAtomNull:
    for i, attr in element.attrs.mypairs:
      if attr.namespace == CAtomNull and attr.qualifiedName == localName:
        return i
    return -1
  # Potentially slow path, since we don't store namespace prefixes separately.
  # Still preferable to wasting memory for XML brain damage.
  for i, attr in element.attrs.mypairs:
    if attr.namespace == namespace and
        attr.qualifiedName.matchesLocalName(localName):
      return i
  return -1

proc hasAttributes(element: Element): bool {.jsfunc.} =
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

proc getAttribute(ctx: JSContext; element: Element; qualifiedName: CAtom):
    JSValue {.jsfunc.} =
  let i = element.findAttr(qualifiedName)
  if i != -1:
    return ctx.toJS(element.attrs[i].value)
  return JS_NULL

proc getAttributeNS(ctx: JSContext; element: Element;
    namespace, localName: CAtom): JSValue {.jsfunc.} =
  let i = element.findAttrNS(namespace, localName)
  if i != -1:
    return ctx.toJS(element.attrs[i].value)
  return JS_NULL

proc attr*(element: Element; s: CAtom): lent string =
  let i = element.findAttr(s)
  if i != -1:
    return element.attrs[i].value
  # the compiler cries if I return string literals :/
  let emptyStr {.global.} = ""
  return emptyStr

proc attr*(element: Element; s: StaticAtom): lent string =
  return element.attr(s.toAtom())

proc attrl*(element: Element; s: StaticAtom): Opt[int32] =
  return parseInt32(element.attr(s))

proc attrulgz*(element: Element; s: StaticAtom): Opt[uint32] =
  let x = parseUInt32(element.attr(s), allowSign = true).get(0)
  if x > 0:
    return ok(x)
  err()

proc attrul*(element: Element; s: StaticAtom): Opt[uint32] =
  return parseUInt32(element.attr(s), allowSign = true)

proc attrd*(element: Element; s: StaticAtom): Opt[float64] =
  let d = parseFloat64(element.attr(s))
  if isNaN(d):
    return err()
  ok(d)

proc attrdgz*(element: Element; s: StaticAtom): Opt[float64] =
  let d = element.attrd(s).get(0)
  if d <= 0:
    return err()
  ok(d)

proc attrb*(element: Element; s: CAtom): bool =
  return element.findAttr(s) != -1

proc attrb*(element: Element; at: StaticAtom): bool =
  return element.attrb(at.toAtom())

proc getElementsByTagName(element: Element; tagName: string): HTMLCollection
    {.jsfunc.} =
  return element.getElementsByTagNameImpl(tagName)

proc getElementsByClassName(element: Element; classNames: string):
    HTMLCollection {.jsfunc.} =
  return element.getElementsByClassNameImpl(classNames)

proc children(ctx: JSContext; parentNode: Element): JSValue {.jsfget.} =
  return childrenImpl(ctx, parentNode)

proc previousElementSibling*(element: Element): Element {.jsfget.} =
  return element.previousElementSiblingImpl

proc nextElementSibling*(element: Element): Element {.jsfget.} =
  return element.nextElementSiblingImpl

proc remove(element: Element) {.jsfunc.} =
  Node(element).remove()

proc isDisplayed(element: Element): bool =
  element.ensureStyle()
  return element.computed{"display"} != DisplayNone

proc nextDisplayedElement(element: Element): Element =
  for child in element.elementList:
    if child.isDisplayed():
      return child
  # climb up until we find a non-last leaf (this might be node itself)
  var element = element
  while true:
    var next = element.nextElementSibling
    while next != nil:
      if next.isDisplayed():
        return next
      next = next.nextElementSibling
    element = element.parentElement
    if element == nil:
      break
  # done
  return nil

proc scriptingEnabled(element: Element): bool =
  return element.document.scriptingEnabled

proc isSubmitButton*(element: Element): bool =
  if element of HTMLButtonElement:
    return element.attr(satType).equalsIgnoreCase("submit")
  elif element of HTMLInputElement:
    let element = HTMLInputElement(element)
    return element.inputType in {itSubmit, itImage}
  return false

proc isButton*(element: Element): bool =
  if element of HTMLButtonElement:
    return true
  if element of HTMLInputElement:
    let element = HTMLInputElement(element)
    return element.inputType in {itSubmit, itButton, itReset, itImage}
  return false

proc action*(element: Element): string =
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

proc enctype*(element: Element): FormEncodingType =
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

proc getFormMethod*(element: Element): FormMethod =
  if element.tagType == TAG_FORM:
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

proc outerHTML(ctx: JSContext; element: Element; s: string): JSValue
    {.jsfset.} =
  let parent0 = element.parentNode
  if parent0 == nil:
    return JS_UNDEFINED
  if parent0 of Document:
    return JS_ThrowDOMException(ctx, "NoModificationAllowedError",
      "outerHTML is disallowed for document elements")
  let parent: Element = if parent0 of DocumentFragment:
    element.document.newHTMLElement(TAG_BODY)
  else:
    # neither a document, nor a document fragment => parent must be an
    # element node
    Element(parent0)
  let fragment = fragmentParsingAlgorithm(parent, s)
  return ctx.replaceChildUndefined(parent, element, fragment)

type InsertAdjacentPosition = enum
  iapBeforeBegin = "beforebegin"
  iapAfterEnd = "afterend"
  iapAfterBegin = "afterbegin"
  iapBeforeEnd = "beforeend"

proc insertAdjacentHTML(ctx: JSContext; this: Element; position, text: string):
    JSValue {.jsfunc.} =
  let pos0 = parseEnumNoCase[InsertAdjacentPosition](position)
  if pos0.isErr:
    return JS_ThrowDOMException(ctx, "SyntaxError", "invalid position")
  let position = pos0.get
  var nodeCtx = this
  if position in {iapBeforeBegin, iapAfterEnd}:
    if this.parentNode of Document or this.parentNode == nil:
      return JS_ThrowDOMException(ctx, "NoModificationAllowedError",
        "parent is not a valid element")
    nodeCtx = this.parentElement
  if nodeCtx == nil or not this.document.isxml and nodeCtx.tagType == TAG_HTML:
    nodeCtx = this.document.newHTMLElement(TAG_BODY)
  let fragment = nodeCtx.fragmentParsingAlgorithm(text)
  case position
  of iapBeforeBegin: this.parentNode.insert(fragment, this)
  of iapAfterBegin: this.insert(fragment, this.firstChild)
  of iapBeforeEnd: this.append(fragment)
  of iapAfterEnd: this.parentNode.insert(fragment, this.nextSibling)
  return JS_UNDEFINED

proc insertAdjacent(ctx: JSContext; this: Node; position: string; node: Node):
    JSValue =
  let pos0 = parseEnumNoCase[InsertAdjacentPosition](position)
  if pos0.isErr:
    return JS_ThrowDOMException(ctx, "SyntaxError", "invalid position")
  let position = pos0.get
  return case position
  of iapBeforeBegin:
    if this.parentNode == nil:
      JS_NULL
    else:
      ctx.insertBefore(this.parentNode, node, option(this))
  of iapAfterBegin: ctx.insertBefore(this, node, option(this.firstChild))
  of iapBeforeEnd: ctx.insertBefore(this, node, none(Node))
  of iapAfterEnd:
    ctx.insertBefore(this.parentNode, node, option(this.nextSibling))

proc insertAdjacentElement(ctx: JSContext; this: Element; position: string;
    element: Element): JSValue {.jsfunc.} =
  ctx.insertAdjacent(this, position, element)

proc insertAdjacentText(ctx: JSContext; this: Element; position, s: string):
    JSValue {.jsfunc.} =
  ctx.toUndefined(ctx.insertAdjacent(this, position, this.document.newText(s)))

proc hover*(element: Element): bool =
  return efHover in element.flags

proc setHover*(element: Element; hover: bool) =
  if element.hover != hover:
    element.flags.toggle({efHover})
    element.invalidate(dtHover)

proc parseColor(element: Element; s: string): Opt[ARGBColor] =
  var ctx = initCSSParser(s)
  if color := ctx.parseColor():
    case color.t
    of cctARGB: return ok(color.argb)
    of cctCurrent:
      let window = element.document.window
      if window != nil and window.settings.scripting == smApp and
          element.isConnected():
        element.ensureStyle()
        if element.computed{"color"}.t == cctARGB:
          return ok(element.computed{"color"}.argb)
      return ok(rgba(0, 0, 0, 255))
    of cctCell: discard
  return err()

proc getBoundingClientRect(element: Element): DOMRect {.jsfunc.} =
  let window = element.document.window
  if window == nil:
    return DOMRect()
  if window.settings.scripting == smApp:
    window.ensureLayout(element)
    let objs = getClientRectsImpl(element, firstOnly = true, blockOnly = false)
    if objs.len > 0:
      return objs[0]
    return DOMRect()
  var width = float64(dummyAttrs.ppc)
  var height = float64(dummyAttrs.ppl)
  if element of HTMLImageElement:
    (width, height) = HTMLImageElement(element).getImageRect()
  return DOMRect(width: width, height: height)

proc getClientRects(element: Element): DOMRectList {.jsfunc.} =
  let res = DOMRectList()
  let window = element.document.window
  if window != nil:
    if window.settings.scripting == smApp:
      window.ensureLayout(element)
      res.list = getClientRectsImpl(element, firstOnly = false,
        blockOnly = false)
    else:
      res.list.add(element.getBoundingClientRect())
  res

proc getBlockRect(element: Element): DOMRect =
  let window = element.document.window
  if window != nil:
    if window.settings.scripting != smApp:
      return element.getBoundingClientRect()
    window.ensureLayout(element)
    let res = element.getClientRectsImpl(firstOnly = true, blockOnly = true)
    if res.len > 0:
      return res[0]
  return DOMRect()

proc clientWidth(element: Element): int32 {.jsfget.} =
  let rect = element.getBlockRect()
  if rect != nil and rect.width <= float64(int32.high):
    return int32(rect.width)
  0

proc clientHeight(element: Element): int32 {.jsfget.} =
  let rect = element.getBlockRect()
  if rect != nil and rect.height <= float64(int32.high):
    return int32(rect.height)
  0

const WindowEvents* = [satError, satLoad, satFocus, satBlur]

proc reflectScriptAttr(element: Element; name: StaticAtom;
    value: Option[string]): bool =
  let document = element.document
  const ScriptEventMap = {
    satOnclick: satClick,
    satOninput: satInput,
    satOnchange: satChange,
    satOnload: satLoad,
    satOnerror: satError,
    satOnblur: satBlur,
    satOnfocus: satFocus,
    satOnsubmit: satSubmit,
    satOncontextmenu: satContextmenu,
    satOndblclick: satDblclick,
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
    let document = link.document
    let connected = link.isConnected()
    if name == satDisabled:
      let wasDisabled = link.isDisabled()
      link.enabled = some(value.isNone)
      let disabled = link.isDisabled()
      if wasDisabled != disabled:
        for sheet in link.sheets:
          sheet.disabled = disabled
        if connected:
          document.ruleMap = nil
          let html = document.documentElement
          if html != nil:
            html.invalidate()
    if connected and name in {satHref, satRel, satDisabled}:
      link.fetchStarted = false
      let window = document.window
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

proc isPreviousSiblingOf*(this, other: Element): bool =
  return this.parentNode == other.parentNode and this.elIndex <= other.elIndex

proc querySelector(ctx: JSContext; this: Element; q: string): JSValue
    {.jsfunc.} =
  return ctx.querySelectorImpl(this, q)

proc querySelectorAll(ctx: JSContext; this: Element; q: string): JSValue
    {.jsfunc.} =
  return ctx.querySelectorAllImpl(this, q)

proc isDisabled*(this: Element): bool =
  case this.tagType
  of TAG_BUTTON, TAG_INPUT, TAG_SELECT, TAG_TEXTAREA, TAG_FIELDSET:
    if this.attrb(satDisabled):
      return true
    var lastLegend: Element = nil
    for it in this.ancestors:
      case it.tagType
      of TAG_LEGEND: lastLegend = it
      of TAG_FIELDSET:
        if it.attrb(satDisabled):
          return it.firstChild != lastLegend
      else: discard
    return false
  of TAG_OPTGROUP:
    return this.attrb(satDisabled)
  of TAG_OPTION:
    let parent = this.parentElement
    return parent.tagType == TAG_OPTGROUP and parent.attrb(satDisabled) or
      this.attrb(satDisabled)
  else: #TODO form-associated custom element
    return false

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
  of TAG_OBJECT:
    HTMLObjectElement()
  of TAG_SOURCE:
    HTMLSourceElement()
  of TAG_INS, TAG_DEL:
    HTMLModElement()
  of TAG_PROGRESS:
    HTMLProgressElement()
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
  element.classList = element.newDOMTokenList(satClass)
  element.internalElIndex = -1
  element.custom = if localName.isValidCustomElementName():
    cesUndefined
  else:
    cesUncustomized
  element

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
  let valid = element.computed != nil and not element.computed.invalid
  if element.computed != nil:
    element.computed.invalid = true
  element.document.invalid = true
  if valid:
    for it in element.elementList:
      it.invalidate()

proc ensureStyle(element: Element) =
  if element.computed == nil or element.computed.invalid:
    element.applyStyleImpl()

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
    let link = HTMLLinkElement(element)
    let document = link.document
    if link.isConnected() and document.sheetTitle == "" and
        link.enabled.get(true) and
        not link.relList.containsIgnoreCase(satAlternate):
      document.sheetTitle = link.attr(satTitle)
    let window = document.window
    if window != nil:
      window.loadResource(link)
  of TAG_IMG:
    let window = element.document.window
    if window != nil:
      let image = HTMLImageElement(element)
      window.loadResource(image)
  of TAG_STYLE:
    let style = HTMLStyleElement(element)
    if style.isConnected():
      let document = style.document
      if document.sheetTitle == "":
        document.sheetTitle = style.attr(satTitle)
      style.updateSheet()
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
    JSValue {.jsfunc.} =
  return ctx.prependImpl(this, nodes)

proc append(ctx: JSContext; this: Element; nodes: varargs[JSValueConst]):
    JSValue {.jsfunc.} =
  return ctx.appendImpl(this, nodes)

proc replaceChildren(ctx: JSContext; this: Element;
    nodes: varargs[JSValueConst]): JSValue {.jsfunc.} =
  return ctx.replaceChildrenImpl(this, nodes)

proc delAttr(ctx: JSContext; element: Element; i: int) =
  let name = element.attrs[i].qualifiedName
  let map = ctx.cachedAttributes(element)
  if map != nil:
    # delete from attrlist + adjust indices invalidated
    var j = -1
    for k, attr in map.attrlist.mypairs:
      if attr.dataIdx == i:
        j = k
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
proc findAttrOrNext(element: Element; qualName: CAtom): int =
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
  else:
    i = -(i + 1)
    element.attrs.insert(AttrData(
      namespace: CAtomNull,
      qualifiedName: name,
      value: value
    ), i)
  element.reflectAttr(name, some(element.attrs[i].value))
  element.document.invalidateCollections()
  element.invalidate()

proc attr*(element: Element; name: StaticAtom; value: sink string) =
  element.attr(name.toAtom(), value)

proc attrns0(element: Element; namespace, localName, qualifiedName: CAtom;
    value: sink string) =
  let i = element.findAttrNS(namespace, localName)
  if i != -1:
    element.attrs[i].value = value
  else:
    element.attrs.insert(AttrData(
      namespace: namespace,
      qualifiedName: qualifiedName,
      value: value
    ), element.attrs.upperBound(qualifiedName, cmpAttrName))
  element.reflectAttr(qualifiedName, some(value))
  element.document.invalidateCollections()
  element.invalidate()

proc attrns*(element: Element; localName: CAtom; prefix: NamespacePrefix;
    namespace: Namespace; value: sink string) =
  if prefix == NO_PREFIX and namespace == NO_NAMESPACE:
    element.attr(localName, value)
    return
  let namespace = namespace.toAtom()
  let qualifiedName = if prefix != NO_PREFIX:
    ($prefix & ':' & $localName).toAtom()
  else:
    localName
  element.attrns0(namespace, localName, qualifiedName, value)

proc attrl(element: Element; name: StaticAtom; value: int32) =
  element.attr(name, $value)

proc attrul(element: Element; name: StaticAtom; value: uint32) =
  element.attr(name, $value)

proc attrulgz(element: Element; name: StaticAtom; value: uint32) =
  if value > 0:
    element.attrul(name, value)

proc attrd(element: Element; name: StaticAtom; value: float64) =
  element.attr(name, dtoa(value))

proc setAttribute(ctx: JSContext; element: Element; qualifiedName: string;
    value: sink string): Opt[void] {.jsfunc.} =
  ?ctx.validateName(qualifiedName)
  let qualifiedName = if element.namespaceURI == satNamespaceHTML and
      not element.document.isxml:
    qualifiedName.toAtomLower()
  else:
    qualifiedName.toAtom()
  element.attr(qualifiedName, value)
  ok()

proc setAttributeNS(ctx: JSContext; element: Element; namespace: CAtom;
    qualifiedName: string; value: sink string): Opt[void] {.jsfunc.} =
  ?ctx.validateQName(qualifiedName)
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
    JS_ThrowDOMException(ctx, "NamespaceError", "unexpected namespace")
    return err()
  element.attrns0(namespace, localName, qualifiedName, value)
  ok()

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
    force = none(bool)): Opt[bool] {.jsfunc.} =
  ?ctx.validateName(qualifiedName)
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

proc hint*(element: Element): bool =
  efHint in element.flags

proc setHint*(element: Element; hint: bool) =
  if element.hint != hint:
    element.flags.toggle({efHint})
    element.invalidate()

proc getCharset(element: Element): Charset =
  let charset = getCharset(element.attr(satCharset))
  if charset != CHARSET_UNKNOWN:
    return charset
  return element.document.charset

proc isDefined*(element: Element): bool =
  element.custom in {cesUncustomized, cesCustom}

proc getProgressPosition*(element: Element): float64 =
  if not element.attrb(satValue):
    return -1
  let value = element.attrdgz(satValue).get(0)
  let max = element.attrdgz(satMax).get(1)
  return min(value, max) / max

proc getBitmap*(element: Element): NetworkBitmap =
  case element.tagType
  of TAG_IMG:
    return HTMLImageElement(element).bitmap
  of TAG_CANVAS:
    return HTMLCanvasElement(element).bitmap
  elif element.tagType(satNamespaceSVG) == TAG_SVG:
    return SVGSVGElement(element).bitmap
  else:
    return nil

# DOMRect
proc left(rect: DOMRect): float64 {.jsfget.} =
  return min(rect.x, rect.x + rect.width)

proc right(rect: DOMRect): float64 {.jsfget.} =
  return max(rect.x, rect.x + rect.width)

proc top(rect: DOMRect): float64 {.jsfget.} =
  return min(rect.y, rect.y + rect.height)

proc bottom(rect: DOMRect): float64 {.jsfget.} =
  return max(rect.y, rect.y + rect.height)

# DOMRectList
proc length(this: DOMRectList): int {.jsfget.} =
  this.list.len

proc getter(ctx: JSContext; this: DOMRectList; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  return case ctx.fromIdx(atom, u)
  of fiIdx:
    if int64(u) < int64(this.list.len):
      ctx.toJS(this.list[int(u)]).uninitIfNull()
    else:
      JS_UNINITIALIZED
  of fiStr: JS_UNINITIALIZED
  of fiErr: JS_EXCEPTION

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
  return CSSStyleDeclaration(
    decls: value.parseDeclarations(),
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

proc length(this: CSSStyleDeclaration): uint32 =
  return uint32(this.decls.len)

proc item(ctx: JSContext; this: CSSStyleDeclaration; u: uint32): JSValue
    {.jsfunc.} =
  if u < this.length:
    return ctx.toJS(this.decls[int(u)].name)
  return ctx.toJS("")

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

proc getter(ctx: JSContext; this: CSSStyleDeclaration; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  var s: string
  case ctx.fromIdx(atom, u, s)
  of fiIdx:
    if u < this.length:
      return ctx.toJS(this.decls[int(u)].name)
    return JS_UNINITIALIZED
  of fiStr:
    if s == "cssFloat":
      s = "float"
    if s.isSupportedProperty():
      return ctx.toJS(this.getPropertyValue(s))
    s = camelToKebabCase(s)
    if s.isSupportedProperty():
      return ctx.toJS(this.getPropertyValue(s))
    return JS_UNINITIALIZED
  of fiErr: return JS_EXCEPTION

# Consumes toks.
proc setValue(this: CSSStyleDeclaration; i: int; toks: var seq[CSSToken]):
    Opt[void] =
  if i notin 0 .. this.decls.high:
    return err()
  # dummyAttrs can be safely used because the result is discarded.
  case this.decls[i].t
  of cdtProperty:
    var ctx = initCSSParser(toks)
    var dummy: seq[CSSComputedEntry] = @[]
    ?ctx.parseComputedValues0(this.decls[i].p, dummyAttrs, dummy)
  of cdtVariable:
    if parseDeclWithVar0(toks).len == 0:
      return err()
  this.decls[i].value = move(toks)
  return ok()

proc removeProperty(ctx: JSContext; this: CSSStyleDeclaration; name: string):
    JSValue {.jsfunc.} =
  if this.readonly:
    return JS_ThrowDOMException(ctx, "NoModificationAllowedError",
      "cannot modify read-only declaration")
  let name = name.toLowerAscii()
  let value = this.getPropertyValue(name)
  #TODO shorthand
  let i = this.find(name)
  if i != -1:
    this.decls.delete(i)
  return ctx.toJS(value)

proc checkReadOnly(ctx: JSContext; this: CSSStyleDeclaration): Opt[void] =
  if this.readonly:
    JS_ThrowDOMException(ctx, "NoModificationAllowedError",
      "cannot modify read-only declaration")
    return err()
  ok()

proc setProperty(ctx: JSContext; this: CSSStyleDeclaration;
    name, value: string): JSValue {.jsfunc.} =
  if ctx.checkReadOnly(this).isErr:
    return JS_EXCEPTION
  let name = name.toLowerAscii()
  if not name.isSupportedProperty():
    return JS_UNDEFINED
  if value == "":
    return ctx.removeProperty(this, name)
  var toks = parseComponentValues(value)
  if (let i = this.find(name); i != -1):
    if this.setValue(i, toks).isErr:
      # this does not throw.
      return JS_UNDEFINED
  else:
    let x = initCSSDeclaration(name)
    if x.isErr:
      return JS_UNDEFINED # ignore
    var decl = x.get
    case decl.t
    of cdtProperty:
      var ctx = initCSSParser(toks)
      var dummy = newSeq[CSSComputedEntry]()
      if ctx.parseComputedValues0(decl.p, dummyAttrs, dummy).isErr:
        return JS_UNDEFINED
    of cdtVariable:
      if parseDeclWithVar0(toks).len == 0:
        return JS_UNDEFINED
    decl.value = move(toks)
    this.decls.add(move(decl))
  this.element.attr(satStyle, this.cssText)
  return JS_UNDEFINED

proc setter(ctx: JSContext; this: CSSStyleDeclaration; atom: JSAtom;
    value: string): JSValue {.jssetprop.} =
  if ctx.checkReadOnly(this).isErr:
    return JS_EXCEPTION
  var u: uint32
  var name: string
  case ctx.fromIdx(atom, u, name)
  of fiIdx:
    var toks = parseComponentValues(value)
    if this.setValue(int(u), toks).isErr:
      this.element.attr(satStyle, this.cssText)
    return JS_UNDEFINED
  of fiStr:
    if name == "cssFloat":
      name = "float"
    name = camelToKebabCase(name)
    return ctx.setProperty(this, name, value)
  of fiErr:
    return JS_EXCEPTION

proc style(element: Element): CSSStyleDeclaration {.jsfget.} =
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

proc crossOrigin(element: HTMLElement): CORSAttribute =
  if not element.attrb(satCrossorigin):
    return caNoCors
  let s = element.attr(satCrossorigin)
  if s.equalsIgnoreCase("use-credentials"):
    return caUseCredentials
  caAnonymous

proc referrerPolicy(element: HTMLElement): Opt[ReferrerPolicy] =
  parseEnumNoCase[ReferrerPolicy](element.attr(satReferrerpolicy))

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
  ?ctx.fromJS(this, element)
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
  ?ctx.fromJS(this, element)
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

proc click(ctx: JSContext; element: HTMLElement) {.jsfunc.} =
  let event = newEvent(satClick.toAtom(), element, bubbles = true,
    cancelable = true)
  let canceled = ctx.dispatch(element, event)
  if not canceled:
    let window = ctx.getWindow()
    if window != nil:
      window.click(element)

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
proc jsForm(this: HTMLButtonElement): HTMLFormElement {.jsfget: "form".} =
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
  let url = parseURL0("img-codec+" & contentType.after('/') & ":encode")
  if url == nil:
    return
  let headers = newHeaders(hgRequest, {
    "Cha-Image-Dimensions": $this.bitmap.width & 'x' & $this.bitmap.height
  })
  if (var quality = quality.get(-1); 0 <= quality and quality <= 1):
    quality *= 99
    quality += 1
    headers.add("Cha-Image-Quality", dtoa(quality))
  # callback will go out of scope when we return, so capture a new reference.
  let callback = JS_DupValue(ctx, callback)
  let window = this.document.window
  window.corsFetch(newRequest(
    "img-codec+x-cha-canvas:decode",
    httpMethod = hmPost,
    body = RequestBody(t: rbtCache, cacheId: this.bitmap.cacheId)
  )).then(proc(res: FetchResult): FetchPromise =
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
  ).then(proc(res: FetchResult) =
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
    res.get.blob().then(proc(blob: BlobResult) =
      let jsBlob = ctx.toJS(blob)
      let res = ctx.callFree(callback, JS_UNDEFINED, jsBlob)
      JS_FreeValue(ctx, jsBlob)
      if JS_IsException(res):
        window.console.error("Exception in canvas toBlob:",
          ctx.getExceptionMsg())
      else:
        JS_FreeValue(ctx, res)
    )
  )

# <form>
proc canSubmitImplicitly*(form: HTMLFormElement): bool =
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

proc elements(form: HTMLFormElement): HTMLFormControlsCollection {.jsfget.} =
  if form.cachedElements == nil:
    form.cachedElements = newCollection[HTMLFormControlsCollection](
      root = form.rootNode,
      match = proc(node: Node): bool =
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

proc length(this: HTMLFormElement): int {.jsfget.} =
  return this.elements.getLength()

proc reset*(form: HTMLFormElement) =
  for control in form.controls:
    control.resetElement()
    control.invalidate()

# FormAssociatedElement
proc setForm*(element: FormAssociatedElement; form: HTMLFormElement) =
  element.form = form
  form.controls.add(element)
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
proc getImageRect(this: HTMLImageElement): tuple[w, h: float64] =
  let window = this.document.window
  if window != nil and window.settings.scripting == smApp:
    window.ensureLayout(this)
    let objs = getClientRectsImpl(this, firstOnly = true, blockOnly = false)
    if objs.len > 0:
      return (objs[0].width, objs[0].height)
  let width = float64(this.attrul(satWidth).get(uint32(this.bitmap.width)))
  let height = float64(this.attrul(satHeight).get(uint32(this.bitmap.height)))
  return (width, height)

proc width(this: HTMLImageElement): uint32 {.jsfget.} =
  return uint32(this.getImageRect().w)

proc setWidth(this: HTMLImageElement; u: uint32) {.jsfset: "width".} =
  this.attrul(satWidth, u)

proc height(this: HTMLImageElement): uint32 {.jsfget.} =
  return uint32(this.getImageRect().h)

proc setHeight(this: HTMLImageElement; u: uint32) {.jsfset: "height".} =
  this.attrul(satHeight, u)

# <input>
proc jsForm(this: HTMLInputElement): HTMLFormElement {.jsfget: "form".} =
  return this.form

proc value*(this: HTMLInputElement): lent string {.jsfget.} =
  if this.internalValue == nil:
    this.internalValue = newRefString("")
  return this.internalValue.s

proc setValue*(this: HTMLInputElement; value: sink string) {.jsfset: "value".} =
  this.internalValue = newRefString(value)
  this.invalidate()

proc setType(this: HTMLInputElement; s: string) {.jsfset: "type".} =
  this.attr(satType, s)

proc checked*(input: HTMLInputElement): bool {.inline.} =
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

proc inputString*(input: HTMLInputElement): RefString =
  case input.inputType
  of itCheckbox, itRadio:
    if input.checked:
      return newRefString("*")
    return newRefString(" ")
  of itPassword:
    return newRefString('*'.repeat(input.value.pointLen))
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
    return newRefString(s)
  else:
    return input.internalValue

proc select(ctx: JSContext; input: HTMLInputElement) {.jsfunc.} =
  ctx.focus(input)

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

# SheetElement
proc findPrevSheet(this: SheetElement): CSSStylesheet =
  var node = this.previousDescendant()
  while node != nil:
    if node of SheetElement:
      let element = SheetElement(node)
      if element.sheetTail != nil:
        return element.sheetTail
    node = node.previousDescendant()
  nil

proc findNextSheet(this: SheetElement): CSSStylesheet =
  var node = Node(this).nextDescendant(nil)
  while node != nil:
    if node of SheetElement:
      let element = SheetElement(node)
      if element.sheetHead != nil:
        return element.sheetHead
    node = node.nextDescendant(nil)
  nil

proc isDisabled(this: SheetElement): bool =
  this of HTMLLinkElement and HTMLLinkElement(this).isDisabled()

proc insertSheet(this: SheetElement) =
  if this.sheetHead != nil:
    let document = this.document
    let prev = this.findPrevSheet()
    let next = this.findNextSheet()
    if prev != nil:
      prev.next = this.sheetHead
    else:
      document.authorSheetsHead = this.sheetHead
    this.sheetTail.next = next
    if document.ruleMap != nil and not this.isDisabled():
      if next == nil:
        for sheet in this.sheets:
          document.ruleMap.add(sheet)
      else:
        document.ruleMap = nil
    let html = document.documentElement
    if html != nil:
      html.invalidate()

proc removeSheet(this: SheetElement) =
  if this.sheetHead != nil:
    let document = this.document
    let next = this.sheetTail.next
    let prev = this.findPrevSheet()
    if prev == nil:
      document.authorSheetsHead = next
    else:
      prev.next = next
    if not this.isDisabled():
      document.ruleMap = nil
    this.sheetTail.next = nil
    let html = document.documentElement
    if html != nil:
      html.invalidate()

proc updateSheet(this: SheetElement; head, tail: CSSStylesheet) =
  this.removeSheet()
  this.sheetHead = head
  this.sheetTail = tail
  if this.isConnected():
    this.insertSheet()

# <link>
proc isDisabled(link: HTMLLinkElement): bool =
  let title = link.attr(satTitle)
  if title == "":
    return link.relList.containsIgnoreCase(satAlternate) or
      not link.enabled.get(true)
  if link.enabled.isSome:
    return not link.enabled.get
  return link.document.sheetTitle != title

proc setRelList(link: HTMLLinkElement; s: string) {.jsfset: "relList".} =
  link.attr(satRel, s)

# <option>
proc text(option: HTMLOptionElement): string {.jsfget.} =
  var s = ""
  for child in option.descendants:
    let parent = child.parentElement
    if child of Text and (parent.tagTypeNoNS != TAG_SCRIPT or
        parent.namespaceURI notin [satNamespaceHTML, satNamespaceSVG]):
      s &= Text(child).data.s
  return s.stripAndCollapse()

proc value*(option: HTMLOptionElement): string {.jsfget.} =
  if option.attrb(satValue):
    return option.attr(satValue)
  return option.text

proc setValue(option: HTMLOptionElement; s: string) {.jsfset: "value".} =
  option.attr(satValue, s)

proc select*(option: HTMLOptionElement): HTMLSelectElement =
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

# <progress>
proc position(this: HTMLProgressElement): float64 {.jsfget.} =
  return this.getProgressPosition()

# <select>
proc displaySize(select: HTMLSelectElement): uint32 =
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

proc jsForm(this: HTMLSelectElement): HTMLFormElement {.jsfget: "form".} =
  return this.form

proc jsType(this: HTMLSelectElement): string {.jsfget: "type".} =
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
      return ctx.insertThrow("can't add ancestor of select")
  if beforeEl != nil and this.root notin beforeEl:
    return ctx.insertThrow(nil)
  if element != beforeEl:
    if beforeEl == nil:
      let it = this.item(uint32(beforeIdx))
      if it of HTMLElement:
        beforeEl = HTMLElement(it)
    let parent = if beforeEl != nil: beforeEl.parentNode else: this.root
    return ctx.insertBeforeUndefined(parent, element, option(Node(beforeEl)))
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

proc jsOptions(this: HTMLSelectElement): HTMLOptionsCollection
    {.jsfget: "options".} =
  if this.cachedOptions == nil:
    this.cachedOptions = newCollection[HTMLOptionsCollection](
      root = this,
      match = proc(node: Node): bool =
        return node.isOptionOf(this),
      islive = true,
      childonly = false
    )
  return this.cachedOptions

proc setter(ctx: JSContext; this: HTMLOptionsCollection; atom: JSAtom;
    value: Option[HTMLOptionElement]): JSValue {.jssetprop.} =
  var u: uint32
  case ctx.fromIdx(atom, u)
  of fiIdx: discard
  of fiStr: return JS_UNINITIALIZED
  of fiErr: return JS_EXCEPTION
  let element = this.item(u)
  if value.isNone:
    let element = this.item(u)
    if element != nil:
      element.remove()
    return JS_UNDEFINED
  let value = value.get
  let parent = this.root
  if element != nil:
    return ctx.replaceChild(parent, element, value)
  let L = uint32(this.getLength())
  let document = parent.document
  for i in L ..< u:
    let res = parent.insertBefore(document.newHTMLElement(TAG_OPTION), nil)
    if res.isErr:
      return ctx.insertThrow(res.error)
  return ctx.insertBeforeUndefined(parent, value, none(Node))

proc length(this: HTMLSelectElement): int {.jsfget.} =
  return this.jsOptions.getLength()

proc setLength(this: HTMLSelectElement; n: uint32) {.jsfset: "length".} =
  this.jsOptions.setLength(n)

proc getter(ctx: JSContext; this: HTMLSelectElement; u: JSAtom): JSValue
    {.jsgetownprop.} =
  return ctx.getter(this.jsOptions, u)

proc item(this: HTMLSelectElement; u: uint32): Node {.jsfunc.} =
  return this.jsOptions.item(u)

proc namedItem(this: HTMLSelectElement; atom: CAtom): Element {.jsfunc.} =
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

proc showPicker(ctx: JSContext; this: HTMLSelectElement): JSValue {.jsfunc.} =
  # Per spec, we should do something if it's being rendered and on
  # transient user activation.
  # If this is ever implemented, then the "is rendered" check must
  # be app mode only.
  return JS_ThrowDOMException(ctx, "NotAllowedError", "not allowed")

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
    let p = window.parseStylesheet(this.textContent, document.baseURL,
        DefaultCharset, CAtomNull).then(proc(res: LoadSheetResult) =
      this.updateSheet(res.head, res.tail)
      if this.isConnected():
        let title = this.attr(satTitle)
        for sheet in this.sheets:
          sheet.disabled = title != "" and title != document.sheetTitle
    )
    window.pendingResources.add(p)

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
  var it = prepdoc.scriptsToExecSoon
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
  request.client = window.settings
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
    parseURL0("about:client"),
    isTopLevel = true,
    onComplete = proc(element: HTMLScriptElement; res: ScriptResult) =
      if res.t == srtNull:
        element.onComplete(res)
      else:
        element.fetchDescendantsAndLink(res.script, rdScript, onComplete)
  )

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
  JS_FreeValue(ctx, res)

#TODO settings object
proc fetchSingleModule(element: HTMLScriptElement; url: URL;
    destination: RequestDestination; options: ScriptOptions;
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
  p.then(proc(res: FetchResult) =
    let ctx = window.jsctx
    if res.isErr:
      let res = ScriptResult(t: srtNull)
      settings.moduleMap.set(url, moduleType, res, ctx)
      element.onComplete(res)
      return
    let res = res.get
    let contentType = res.getContentType()
    let referrerPolicy = res.getReferrerPolicy()
    res.text().then(proc(s: TextResult) =
      if s.isErr:
        let res = ScriptResult(t: srtNull)
        settings.moduleMap.set(url, moduleType, res, ctx)
        element.onComplete(res)
        return
      if contentType.isJavaScriptType():
        let res = ctx.newJSModuleScript(s.get, url, options)
        #TODO can't we just return null from newJSModuleScript?
        if JS_IsException(res.script.record):
          window.logException(res.script.baseURL)
          element.onComplete(ScriptResult(t: srtNull))
        else:
          if referrerPolicy.isOk:
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
  let encoding = element.getCharset()
  let classicCORS = element.crossOrigin
  let parserMetadata = if element.parserDocument != nil:
    pmParserInserted
  else:
    pmNotParserInserted
  var options = ScriptOptions(
    nonce: element.internalNonce,
    integrity: element.attr(satIntegrity),
    parserMetadata: parserMetadata,
    referrerPolicy: element.referrerPolicy
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
proc caption(this: HTMLTableElement): Element {.jsfget.} =
  return this.findFirstChildOf(TAG_CAPTION)

proc setCaption(ctx: JSContext; this: HTMLTableElement;
    caption: HTMLTableCaptionElement): JSValue {.jsfset: "caption".} =
  let old = this.caption
  if old != nil:
    old.remove()
  return ctx.insertBeforeUndefined(this, caption, option(this.firstChild))

proc tHead(this: HTMLTableElement): Element {.jsfget.} =
  return this.findFirstChildOf(TAG_THEAD)

proc tFoot(this: HTMLTableElement): Element {.jsfget.} =
  return this.findFirstChildOf(TAG_TFOOT)

proc setTSectImpl(ctx: JSContext; this: HTMLTableElement;
    sect: HTMLTableSectionElement; tagType: TagType): JSValue =
  if sect != nil and sect.tagType != tagType:
    return ctx.insertThrow("wrong element type")
  let old = this.findFirstChildOf(tagType)
  if old != nil:
    old.remove()
  return ctx.insertBeforeUndefined(this, sect, option(this.firstChild))

proc setTHead(ctx: JSContext; this: HTMLTableElement;
    tHead: HTMLTableSectionElement): JSValue {.jsfset: "tHead".} =
  return ctx.setTSectImpl(this, tHead, TAG_THEAD)

proc setTFoot(ctx: JSContext; this: HTMLTableElement;
    tFoot: HTMLTableSectionElement): JSValue {.jsfset: "tFoot".} =
  return ctx.setTSectImpl(this, tFoot, TAG_TFOOT)

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
    this.insert(element, before)
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

proc insertRow(ctx: JSContext; this: HTMLTableElement; index = -1): JSValue
    {.jsfunc.} =
  let nrows = this.rows.getLength()
  if index < -1 or index > nrows:
    return JS_ThrowDOMException(ctx, "IndexSizeError", "index out of bounds")
  let tr = this.document.newHTMLElement(TAG_TR)
  if nrows == 0:
    this.createTBody().append(tr)
  elif index == -1 or index == nrows:
    this.rows.item(uint32(nrows) - 1).parentNode.append(tr)
  else:
    let it = this.rows.item(uint32(index))
    it.parentNode.insert(tr, it)
  return ctx.toJS(tr)

proc deleteRow(ctx: JSContext; rows: HTMLCollection; index: int): JSValue =
  let nrows = rows.getLength()
  if index < -1 or index >= nrows:
    return JS_ThrowDOMException(ctx, "IndexSizeError", "index out of bounds")
  if index == -1:
    rows.item(uint32(nrows - 1)).remove()
  elif nrows > 0:
    rows.item(uint32(index)).remove()
  return JS_UNDEFINED

proc deleteRow(ctx: JSContext; this: HTMLTableElement; index = -1): JSValue
    {.jsfunc.} =
  return ctx.deleteRow(this.rows, index)

# <tbody>
proc rows(this: HTMLTableSectionElement): HTMLCollection {.jsfget.} =
  if this.cachedRows == nil:
    this.cachedRows = this.newHTMLCollection(
      match = isRow,
      islive = true,
      childonly = true
    )
  return this.cachedRows

proc insertRow(ctx: JSContext; this: HTMLTableSectionElement; index = -1):
    JSValue {.jsfunc.} =
  let nrows = this.rows.getLength()
  if index < -1 or index > nrows:
    return JS_ThrowDOMException(ctx, "index out of bounds", "IndexSizeError")
  let tr = this.document.newHTMLElement(TAG_TR)
  if index == -1 or index == nrows:
    this.append(tr)
  else:
    this.insert(tr, this.rows.item(uint32(index)))
  return ctx.toJS(tr)

proc deleteRow(ctx: JSContext; this: HTMLTableSectionElement; index = -1):
    JSValue {.jsfunc.} =
  return ctx.deleteRow(this.rows, index)

# <tr>
proc cells(ctx: JSContext; this: HTMLTableRowElement): JSValue {.jsfget.} =
  return ctx.getWeakCollection(this, wwmCells)

proc rowIndex(this: HTMLTableRowElement): int {.jsfget.} =
  let table = this.findAncestor(TAG_TABLE)
  if table != nil:
    return HTMLTableElement(table).rows.findNode(this)
  return -1

proc sectionRowIndex(this: HTMLTableRowElement): int {.jsfget.} =
  let parent = this.parentElement
  if parent of HTMLTableElement:
    return this.rowIndex
  if parent of HTMLTableSectionElement:
    return HTMLTableSectionElement(parent).rows.findNode(this)
  return -1

# <textarea>
proc jsForm(this: HTMLTextAreaElement): HTMLFormElement {.jsfget: "form".} =
  return this.form

proc value*(textarea: HTMLTextAreaElement): string {.jsfget.} =
  if textarea.dirty:
    return textarea.internalValue
  return textarea.childTextContent

proc `value=`*(textarea: HTMLTextAreaElement; s: sink string)
    {.jsfset: "value".} =
  textarea.dirty = true
  textarea.internalValue = s

proc textAreaString*(textarea: HTMLTextAreaElement): string =
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
proc getSrc*(this: HTMLElement): tuple[src, contentType: string] =
  let src = this.attr(satSrc)
  if src != "":
    return (src, "")
  for el in this.elementDescendants(TAG_SOURCE):
    let src = el.attr(satSrc)
    if src != "":
      return (src, el.attr(satType))
  return ("", "")

proc addElementReflection(ctx: JSContext; class: JSClassID) =
  let proto = JS_GetClassProto(ctx, class)
  for i in ReflectAllStartIndex ..< int16(ReflectMap.len):
    let name = $ReflectMap[i].funcname
    if ctx.addReflectFunction(proto, name, jsReflectGet, jsReflectSet,
        cint(i)).isErr:
      JS_FreeValue(ctx, proto)
      return
  JS_FreeValue(ctx, proto)

proc addAttributeReflection(ctx: JSContext; class: JSClassID;
    attrs: openArray[int16]; base: JSClassID) =
  let proto = JS_GetClassProto(ctx, class)
  let diff = (uint16(class) - uint16(base)) shl 9
  for i in attrs:
    if ctx.addReflectFunction(proto, $ReflectMap[i].funcname, jsReflectGet,
        jsReflectSet, cint(diff or uint16(i))).isErr:
      JS_FreeValue(ctx, proto)
      return
  JS_FreeValue(ctx, proto)

proc registerElements(ctx: JSContext; nodeCID: JSClassID) =
  let elementCID = ctx.registerType(Element, parent = nodeCID)
  let htmlElementCID = ctx.registerType(HTMLElement, parent = elementCID)
  ctx.addElementReflection(htmlElementCID)
  template register(t: typed; tags: openArray[TagType]) =
    let class = ctx.registerType(t, parent = htmlElementCID)
    discard class
    const attrs = TagReflectMap[tags[0]]
    when attrs.len > 0:
      ctx.addAttributeReflection(class, attrs, htmlElementCID)
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
  register(HTMLObjectElement, TAG_OBJECT)
  register(HTMLSourceElement, TAG_SOURCE)
  register(HTMLModElement, [TAG_INS, TAG_DEL])
  register(HTMLProgressElement, TAG_PROGRESS)
  # 44/127 (warning: the 128th interface doesn't fit in the top 7 bits of
  # the getter/setter magic)
  let svgElementCID = ctx.registerType(SVGElement, parent = elementCID)
  ctx.registerType(SVGSVGElement, parent = svgElementCID)

proc addDOMModule*(ctx: JSContext; eventTargetCID: JSClassID) =
  let nodeCID = ctx.registerType(Node, parent = eventTargetCID)
  doAssert ctx.defineConsts(nodeCID, NodeType) == dprSuccess
  let nodeListCID = ctx.registerType(NodeList, iterable = jitValue)
  let htmlCollectionCID = ctx.registerType(HTMLCollection, iterable = jitPair)
  ctx.registerType(HTMLAllCollection)
  ctx.registerType(HTMLFormControlsCollection, parent = htmlCollectionCID)
  ctx.registerType(HTMLOptionsCollection, parent = htmlCollectionCID)
  ctx.registerType(RadioNodeList, parent = nodeListCID)
  ctx.registerType(NodeIterator)
  ctx.registerType(Location)
  let documentCID = ctx.registerType(Document, parent = nodeCID)
  ctx.registerType(XMLDocument, parent = documentCID)
  ctx.registerType(DOMImplementation)
  ctx.registerType(DOMTokenList, iterable = jitValue)
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
  ctx.registerType(DOMRectList)
  ctx.registerType(CustomElementRegistry)
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
    let n = ctx.toJS(1u32 shl uint32(e))
    if (let res = ctx.definePropertyE(nodeFilter, $e, n); res != dprSuccess):
      doAssert false
  doAssert ctx.definePropertyE(nodeFilter, "SHOW_ALL",
    ctx.toJS(0xFFFFFFFFu32)) != dprException
  doAssert ctx.definePropertyCW(jsWindow, "NodeFilter",
    ctx.toJS(nodeFilter)) != dprException
  JS_FreeValue(ctx, jsWindow)

# Forward declaration hack
isDefaultPassiveImpl = proc(target: EventTarget): bool =
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

isWindowImpl = proc(target: EventTarget): bool =
  return target of Window

isHTMLElementImpl = proc(target: EventTarget): bool =
  return target of HTMLElement

parseColorImpl = proc(target: EventTarget; s: string): Opt[ARGBColor] =
  return Element(target).parseColor(s)

setEventImpl = proc(ctx: JSContext; event: Event): Event =
  let window = ctx.getWindow()
  if window != nil:
    let res = window.event
    window.event = event
    return res
  nil

{.pop.} # raises: []
