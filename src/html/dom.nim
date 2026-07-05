{.push raises: [].}

import std/algorithm
import std/hashes
import std/math
import std/options
import std/sets
import std/setutils
import std/tables
import std/times
import std/typetraits

import chame/tags
import config/conftypes
import config/mimetypes
import css/cssparser
import css/cssvalues
import css/mediaquery
import css/sheet
import encoding/charset
import encoding/decoder
import html/catom
import html/domcanvas
import html/domexception
import html/domrect
import html/event
import html/performance
import html/script
import io/console
import io/dynstream
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
import utils/tabutil
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

  CachedURLImage {.final.} = ref object of RootObj
    window: Window
    expiry: int64
    loading: bool
    shared: seq[HTMLImageElement]
    bmp: NetworkBitmap
    cacheId: int
    t: string

  WindowWeakMap* = enum
    wwmChildren, wwmChildNodes, wwmSelectedOptions, wwmTBodies, wwmCells,
    wwmDataset, wwmAttributes

  Window* {.final.} = ref object of EventTarget
    bc*: RootRef # backref to BufferContext
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
    jsctx*: JSContext
    document* {.jsufget.}: Document
    timeouts*: TimeoutState
    importMapsAllowed*: bool
    inMicrotaskCheckpoint: bool
    dangerAlwaysSameOrigin*: bool # for client, insecure if Window sets true
    remoteSheetNum*: uint32
    loadedSheetNum*: uint32
    remoteImageNum*: uint32
    loadedImageNum*: uint32
    imageURLCache: Table[string, CachedURLImage]
    svgCache*: Table[string, SVGSVGElement]
    # ID of the next image
    imageId: int
    # list of streams that must be closed for canvas rendering on load
    pendingCanvasCtls*: seq[CanvasRenderingContext2D]
    imageTypes*: MimeTypesImages
    userAgent*: string
    referrer* {.jsget.}: string
    performance* {.jsget.}: Performance
    weakMap*: array[WindowWeakMap, JSValue]
    customElements* {.jsget.}: CustomElementRegistry

  # Navigator stuff
  # (most of these are just shims; really there should be a framework for
  # this so we generate less code)
  Navigator* = ref object
    plugins* {.jsget.}: PluginArray
    mimeTypes* {.jsget.}: MimeTypeArray
    permissions* {.jsget.}: Permissions

  PluginArray* = ref object

  MimeTypeArray* = ref object

  Screen* = ref object

  History* = ref object

  Storage* = ref object
    map*: seq[tuple[key, value: string]]

  Crypto* = ref object
    urandom*: PosixStream

  Notification* = ref object

  Permissions* = ref object

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
    observedAttrs: seq[CAtom]
    callbacks: CECallbackMap
    flags: set[CustomElementFlag]
    next: CustomElementDef

  CustomElementRegistry* = ref object
    rt*: JSRuntime
    defsHead: CustomElementDef
    defsTail: CustomElementDef
    inDefine: bool
    scoped: bool
    scopedDocuments: seq[Document]

  NamedNodeMap = ref object
    element: Element
    attrlist: seq[Attr]

  NodeFilterResult = enum
    nfrAccept = (1, "FILTER_ACCEPT")
    nfrReject = (2, "FILTER_REJECT")
    nfrSkip = (3, "FILTER_SKIP")

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

  CollectionMatchFun = proc(this: Collection; node: Node): bool {.
    nimcall, raises: [].}

  LoadSheetEnv {.final.} = ref object of BlobOpaque
    window: Window
    this: SheetElement
    url: URL
    finish: LoadSheetFinish
    charset: Charset
    layer: CAtom
    i: int
    parseEnv: ParseSheetEnv

  ParseSheetEnv = ref object
    sheet: CSSStylesheet
    sheets: seq[LoadSheetResult]
    loaded: int
    finish: LoadSheetFinish
    parent: ParseSheetEnv
    i: int

  LoadSheetFinish = proc(window: Window; this: SheetElement;
    res: LoadSheetResult; env: ParseSheetEnv; i: int) {.  nimcall, raises: [].}

  CollectionLikeObj = object of JSRootObj
    root: Node
    # if not nil, this is a live collection.  (uses a ptr instead of a ref
    # because ORC likes to set refs to nil before the destructor is called)
    document: ptr DocumentObj
    prev: ptr CollectionLikeObj
    next: ptr CollectionLikeObj

  CollectionLike = ref CollectionLikeObj

  Collection = ref object of CollectionLikeObj
    childonly: bool
    invalid: bool
    match: CollectionMatchFun
    snapshot: seq[Node]
    atoms: seq[CAtom]

  NodeIteratorLike = ref object of CollectionLikeObj
    active: bool
    whatToShow: uint32
    filter: JSValue

  NodeIterator {.final.} = ref object of NodeIteratorLike
    referenceNode {.jsget.}: Node
    iterNode: Node
    before {.jsget: "pointerBeforeReferenceNode".}: bool
    iterBefore: bool

  TreeWalker {.final.} = ref object of NodeIteratorLike
    currentNode {.jsgetset.}: Node

  NodeList = ref object of Collection

  HTMLCollection = ref object of Collection

  HTMLFormControlsCollection {.final.} = ref object of HTMLCollection
    form: HTMLFormElement

  HTMLOptionsCollection {.final.} = ref object of HTMLCollection

  RadioNodeList {.final.} = ref object of NodeList
    parent: HTMLFormControlsCollection

  HTMLAllCollection {.final.} = ref object of Collection

  DOMTokenList = ref object
    toks: seq[CAtom]
    element: Element
    localName: StaticAtom

  DOMStringMap = ref object
    target: HTMLElement

  # Nodes are organized as doubly linked lists, which normally have
  # two unused pointers (prev of head, next of tail).  We exploit this
  # property to elide two other pointers as follows:
  # * The tail of the child linked list is stored as the prev pointer of
  #   the first child.
  # * The root of the tree is stored as the next pointer of the last
  #   child.  The root in turn stores either the owner document (detached
  #   tree) or nil (ShadowRoot, Document).
  #
  # Since a root always has a nil parentNode, it can be distinguished from
  # the next sibling by testing its parent against 0.  Do note that this
  # is also true for internalFirst if it holds a shadow root, but the two
  # cases do not conflict because a root node cannot be firstChild.
  Node* = ref object of EventTarget
    parentNode*: ParentNode
    internalNext: Node # either nextSibling, rootNode or ownerDocument
    internalPrev: Node # either previousSibling or parentNode.lastChild

  ParentNode* = ref object of Node
    internalFirst: Node # either firstChild or shadow root

  Attr {.final.} = ref object of Node
    dataIdx: int
    ownerElement: Element
    prefix {.jsget.}: CAtom
    localName {.jsget.}: CAtom

  DOMImplementation = ref object
    document: Document

  DocumentWriteBuffer* = ref object
    data*: string
    i*: int
    prev*: DocumentWriteBuffer

  Document* = ref DocumentObj

  DocumentObj = object of ParentNode
    activeParserWasAborted: bool
    invalid*: bool # whether the document must be rendered again
    charset* {.jsget, jsget: "characterSet", jsget: "inputEncoding".}: Charset
    mode*: QuirksMode
    readyState* {.jsget.}: DocumentReadyState
    contentType* {.jsget.}: StaticAtom
    window* {.jsget: "defaultView".}: Window
    url*: URL # not nil
    currentScript {.jsget.}: HTMLScriptElement
    implementation {.jsget.}: DOMImplementation
    elementIdMap: seq[Element]
    elementIdMapLoad: int
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
    computedMap: CSSValuesMap
    cachedForms: HTMLCollection
    cachedLinks: HTMLCollection
    cachedImages: HTMLCollection
    parser*: RootRef
    liveCollectionsHead: ptr CollectionLikeObj
    cachedAll: HTMLAllCollection
    customElements: CustomElementRegistry #TODO ?

  XMLDocument {.final.} = ref object of Document

  CharacterData* = ref object of Node
    # Note: layout assumes this is only modified directly by appending text.
    data* {.jsgetset.}: RefString

  Text* = ref object of CharacterData

  Comment* {.final.} = ref object of CharacterData

  CDATASection {.final.} = ref object of Text

  ProcessingInstruction {.final.} = ref object of CharacterData
    target {.jsget.}: string

  DocumentFragment* = ref object of ParentNode
    host*: Element

  ShadowRootInit = object of JSDict
    mode: ShadowRootMode
    delegatesFocus {.jsdefault.}: bool
    slotAssignment {.jsdefault.}: SlotAssignmentMode
    clonable {.jsdefault.}: bool
    serializable {.jsdefault.}: bool
    customElementRegistry {.jsdefault.}: CustomElementRegistry

  ShadowRootMode = enum
    srmOpen = "open", srmClosed = "closed"

  SlotAssignmentMode = enum
    samNamed = "named", samManual = "manual"

  ShadowRoot {.final.} = ref object of DocumentFragment
    mode {.jsget.}: ShadowRootMode
    delegatesFocus {.jsget.}: bool
    slotAssignment {.jsget.}: SlotAssignmentMode
    clonable {.jsget.}: bool
    serializable {.jsget.}: bool
    declarative: bool
    unsetCustomElements: bool
    customElements: CustomElementRegistry
    #TODO onslotchange

  DocumentType* {.final.} = ref object of Node
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
    efHint, efHover, efShadowRoot, efChildElIndicesInvalid, efRestyle

  Element* = ref object of ParentNode
    namespaceURI* {.jsget.}: CAtom # 4
    tagName: CAtom # 8, like DOM tagName but not upper-cased
    relayout*: set[PseudoElement] # 9
    flags: set[ElementFlag] # 10
    selfDepends: set[DependencyType] # 11
    custom: CustomElementState # 12
    localName* {.jsget.}: CAtom # 16
    id* {.jsget.}: CAtom # 20
    name: CAtom # 24
    internalElIndex: uint32 # 28
    # 4 bytes free
    classList* {.jsget.}: DOMTokenList # 40
    attrs*: seq[AttrData] # 48, sorted by int(qualifiedName)
    cachedStyle*: CSSStyleDeclaration # 56
    computed*: CSSValues # 64
    box*: RootRef # 72, CSSBox

  AttrDummyElement {.final.} = ref object of Element

  CSSStyleDeclaration* = ref object
    computed: bool
    readonly: bool
    decls*: seq[CSSDeclaration]
    element: Element

  HTMLElement* = ref object of Element

  SVGElement = ref object of Element

  SVGSVGElement* {.final.} = ref object of SVGElement
    bitmap*: NetworkBitmap
    parserDocument*: Document
    shared: seq[SVGSVGElement] # elements that serialize to the same string
    fetchStarted: bool

  FormAssociatedElement* = ref object of HTMLElement
    form*: HTMLFormElement
    prev: FormAssociatedElement # previous control in form
    next: FormAssociatedElement # next control in form
    parserInserted*: bool

  HTMLInputElement* {.final.} = ref object of FormAssociatedElement
    inputType* {.jsget: "type".}: InputType
    internalValue: RefString
    internalChecked {.jsget: "checked".}: bool
    internalFiles: FileList # may be nil
    xcoord*: int
    ycoord*: int

  HTMLAnchorElement* {.final.} = ref object of HTMLElement
    relList {.jsget.}: DOMTokenList

  HTMLSelectElement* {.final.} = ref object of FormAssociatedElement
    userValidity: bool
    cachedOptions: HTMLOptionsCollection

  HTMLSpanElement {.final.} = ref object of HTMLElement

  HTMLOptGroupElement {.final.} = ref object of HTMLElement

  HTMLOptionElement* {.final.} = ref object of HTMLElement
    selected* {.jsget.}: bool
    dirty: bool

  HTMLHeadingElement {.final.} = ref object of HTMLElement

  HTMLBRElement {.final.} = ref object of HTMLElement

  HTMLMenuElement {.final.} = ref object of HTMLElement

  HTMLUListElement {.final.} = ref object of HTMLElement

  HTMLOListElement {.final.} = ref object of HTMLElement

  HTMLLIElement* {.final.} = ref object of HTMLElement

  SheetElement = ref object of HTMLElement
    sheetHead: CSSStylesheet
    sheetTail: CSSStylesheet

  HTMLStyleElement* {.final.} = ref object of SheetElement

  HTMLLinkElement* {.final.} = ref object of SheetElement
    relList {.jsget.}: DOMTokenList
    fetchStarted: bool
    enabled: Option[bool]

  HTMLFormElement* {.final.} = ref object of HTMLElement
    constructingEntryList*: bool
    firing*: bool
    controlsHead: FormAssociatedElement
    controlsTail: FormAssociatedElement
    cachedElements: HTMLFormControlsCollection
    relList {.jsget.}: DOMTokenList

  HTMLTemplateElement* {.final.} = ref object of HTMLElement
    content* {.jsget.}: DocumentFragment

  HTMLScriptElement* {.final.} = ref object of HTMLElement
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

  HTMLBaseElement {.final.} = ref object of HTMLElement

  HTMLAreaElement {.final.} = ref object of HTMLElement
    relList {.jsget.}: DOMTokenList

  HTMLButtonElement* {.final.} = ref object of FormAssociatedElement
    ctype* {.jsget: "type".}: ButtonType

  HTMLTextAreaElement* {.final.} = ref object of FormAssociatedElement
    dirty: bool
    internalValue: string

  HTMLLabelElement* {.final.} = ref object of HTMLElement

  HTMLOutputElement {.final.} = ref object of FormAssociatedElement
    dirty: bool
    internalValue: string

  HTMLCanvasElement* {.final.} = ref object of HTMLElement
    ctx2d*: CanvasRenderingContext2D
    bitmap*: NetworkBitmap

  HTMLImageElement* {.final.} = ref object of HTMLElement
    bitmap*: NetworkBitmap
    fetchStarted: bool

  HTMLVideoElement* {.final.} = ref object of HTMLElement

  HTMLAudioElement* {.final.} = ref object of HTMLElement

  HTMLIFrameElement {.final.} = ref object of HTMLElement

  HTMLTableElement {.final.} = ref object of HTMLElement
    cachedRows: HTMLCollection

  HTMLTableCaptionElement {.final.} = ref object of HTMLElement

  HTMLTableSectionElement {.final.} = ref object of HTMLElement
    cachedRows: HTMLCollection

  HTMLTableRowElement {.final.} = ref object of HTMLElement

  HTMLMetaElement {.final.} = ref object of HTMLElement

  HTMLDetailsElement {.final.} = ref object of HTMLElement

  HTMLFrameElement {.final.} = ref object of HTMLElement

  HTMLTimeElement {.final.} = ref object of HTMLElement

  HTMLQuoteElement {.final.} = ref object of HTMLElement

  HTMLDataElement {.final.} = ref object of HTMLElement

  HTMLHeadElement {.final.} = ref object of HTMLElement

  HTMLTitleElement {.final.} = ref object of HTMLElement

  HTMLObjectElement {.final.} = ref object of HTMLElement

  HTMLSourceElement {.final.} = ref object of HTMLElement

  HTMLModElement {.final.} = ref object of HTMLElement

  HTMLProgressElement {.final.} = ref object of HTMLElement

  HTMLSlotElement {.final.} = ref object of HTMLElement

  HTMLUnknownElement {.final.} = ref object of HTMLElement

jsDestructor(Navigator)
jsDestructor(PluginArray)
jsDestructor(MimeTypeArray)
jsDestructor(Screen)
jsDestructor(History)
jsDestructor(Storage)
jsDestructor(Crypto)
jsDestructor(Notification)
jsDestructor(Permissions)

jsDestructor(Location)
jsDestructor(DOMImplementation)
jsDestructor(DOMTokenList)
jsDestructor(DOMStringMap)
jsDestructor(NamedNodeMap)
jsDestructor(CSSStyleDeclaration)
jsDestructor(CustomElementRegistry)

# Forward declarations
proc loadSheet(window: Window; this: SheetElement; url: URL; charset: Charset;
  layer: CAtom; finish: LoadSheetFinish; i: int; parseEnv: ParseSheetEnv)

proc newCDATASection(document: Document; data: RefString): CDATASection
proc newComment(document: Document; data: RefString): Comment
proc newText*(document: Document; data: string): Text
proc newText(document: Document; data: DOMString): Text
proc newText(ctx: JSContext; data = initDOMStringLit("")): Text
proc newDocument*(url: URL): Document
proc newDocumentType*(document: Document; name, publicId, systemId: string):
  DocumentType
proc newDocumentFragment(document: Document): DocumentFragment
proc newProcessingInstruction(document: Document; target: string;
  data: RefString): ProcessingInstruction
proc newElement*(document: Document; localName: CAtomTraced;
  namespace = satNamespaceHTML): Element
proc newElement(document: Document;
  localName, namespaceURI, tagName: CAtomTraced): Element
proc newHTMLElement*(document: Document; tagType: TagType): HTMLElement
proc newHTMLCollection(root: Node; match: CollectionMatchFun;
  islive, childonly: bool): HTMLCollection
proc newEmptyNodeList(): NodeList
proc newNodeList(root: Node; match: CollectionMatchFun;
  islive, childonly: bool): NodeList
proc newDOMTokenList(element: Element; name: StaticAtom): DOMTokenList
proc newCSSStyleDeclaration(element: Element; value: string; computed = false;
  readonly = false): CSSStyleDeclaration

proc document*(node: Node): Document
proc isConnected(node: Node): bool
proc lastChild*(node: Node): Node
proc nextDescendant(node, start: Node): Node
proc nextDescendantShadow(node, start: Node): Node
proc parentElement*(node: Node): Element
proc parentNodeHost(node: Node): Node
proc parentNodeShadow(node: Node): Node
proc serializeFragment(res: var string; node: Node; writeShadow: bool)
proc serializeFragmentInner(res: var string; child: Node; parentType: TagType;
  writeShadow: bool)

proc countChildren(node: ParentNode; t: NodeType): int
proc hasChild(node: ParentNode; t: NodeType): bool
proc hasChildExcept(node: ParentNode; t: NodeType; ex: Node): bool
proc insert*(parent: ParentNode; node, before: Node; ctx: JSContext;
  suppressObservers = false)
proc replaceAll(parent: ParentNode; node: Node; ctx: JSContext)
proc replaceAll(parent: ParentNode; ds: DOMString; ctx: JSContext)
proc firstChild(parent: ParentNode): Node
proc firstChildShadow(parent: ParentNode): Node
proc nextSibling(node: Node): Node
proc setFirstChild(node: ParentNode; child: Node)

proc addElementId(document: Document; element: Element)
proc adopt(document: Document; node: Node; ctx: JSContext)
proc applyStyleDependencies*(document: Document; element: Element;
  depends: DependencyInfo)
proc baseURL*(document: Document): URL
proc documentElement*(document: Document): Element
proc getElementById*(document: Document; id: CAtomTraced): Element
proc invalidateCollections(document: Document)
proc invalidateCollectionsRemove(document: Document; node: Node)
proc parseURL0*(document: Document; s: string): URL
proc parseURL*(document: Document; s: string): Opt[URL]
proc reflectEvent(document: Document; target: EventTarget;
  name, ctype: StaticAtom; value: string; target2 = none(EventTarget))
proc removeElementId(document: Document; element: Element)

proc adjustForRemoval(iter: NodeIterator; node: Node)

proc containsIgnoreCase(tokenList: DOMTokenList; a: StaticAtom): bool

proc newAttr(element: Element; dataIdx: int): Attr
proc data(attr: Attr): lent AttrData
proc setValue(attr: Attr; ds: DOMString)

proc attachShadow(ctx: JSContext; this: Element; init: ShadowRootInit):
  Opt[ShadowRoot]
proc attr*(element: Element; name: CAtomTraced; value: sink string)
proc attr(element: Element; name: StaticAtom; value: sink string)
proc attr(element: Element; name: CAtomTraced; value: DOMString)
proc attr(element: Element; name: StaticAtom; value: DOMString)
proc attr*(element: Element; s: StaticAtom): lent string
proc attrb*(element: Element; at: StaticAtom): bool
proc attrb*(element: Element; s: CAtomTraced): bool
proc attrd(element: Element; name: StaticAtom; value: float64)
proc attrd*(element: Element; s: StaticAtom): Opt[float64]
proc attrdgz*(element: Element; s: StaticAtom): Opt[float64]
proc attrl(element: Element; name: StaticAtom; value: int32)
proc attrl*(element: Element; s: StaticAtom): Opt[int32]
proc attrul(element: Element; name: StaticAtom; value: uint32)
proc attrul*(element: Element; s: StaticAtom): Opt[uint32]
proc attrulgz(element: Element; name: StaticAtom; value: uint32)
proc attrulgz*(element: Element; s: StaticAtom): Opt[uint32]
proc delAttr(ctx: JSContext; element: Element; i: int)
proc dupAttrs(element: Element): seq[AttrData]
proc elIndex*(this: Element): uint32
proc ensureStyle*(element: Element)
proc findAttr(element: Element; qualifiedName: CAtomTraced): int
proc findAttrNS(element: Element; namespace, localName: CAtomTraced): int
proc getCharset(element: Element): Charset
proc getComputedStyle*(element: Element; pseudo: PseudoElement): CSSValues
proc insertionSteps(element: Element): bool
proc invalidate*(element: Element)
proc invalidate*(element: Element; dep: DependencyType)
proc jsTagName(ctx: JSContext; element: Element): JSValue
proc nextDisplayedElement(element: Element): Element
proc outerHTML(element: Element): string
proc postConnectionSteps(element: Element)
proc precedes(this, other: Element): bool
proc previousElementSibling*(element: Element): Element
proc removingSteps(element: Element)
proc scriptingEnabled(element: Element): bool
proc shadowRoot(this: Element): ShadowRoot
proc tagType*(element: Element; namespace = satNamespaceHTML): TagType

proc globalCustomElements(this: ShadowRoot): CustomElementRegistry

proc crossOrigin(element: HTMLElement): CORSAttribute
proc jsReflectSet(ctx: JSContext; this, val: JSValueConst; magic: cint):
  JSValue {.cdecl.}
proc referrerPolicy(element: HTMLElement): Opt[ReferrerPolicy]

proc resetFormOwner(element: FormAssociatedElement)
proc insertSheet(this: SheetElement)
proc removeSheet(this: SheetElement)
proc updateSheet(this: SheetElement; head, tail: CSSStylesheet)
proc toBlob(ctx: JSContext; this: HTMLCanvasElement; callback: JSValueConst;
  contentType = "image/png"; qualityVal: JSValueConst = JS_UNDEFINED)
proc getImageRect(this: HTMLImageElement): tuple[w, h: float64]
proc checked*(input: HTMLInputElement): bool {.inline.}
proc setChecked*(input: HTMLInputElement; b: bool)
proc value*(this: HTMLInputElement): lent string
proc setValue*(this: HTMLInputElement; value: sink string)
proc isDisabled(link: HTMLLinkElement): bool
proc value*(option: HTMLOptionElement): string
proc defaultValue(this: HTMLOutputElement): string
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
var parseHTMLFragmentImpl*: proc(element: Element; s: openArray[char]):
  seq[Node] {.nimcall, raises: [].}
var parseDocumentWriteChunkImpl*: proc(wrapper: RootRef) {.nimcall, raises: [].}
var applyStyleImpl*: proc(element: Element) {.nimcall, raises: [].}
var getClientRectsImpl*: proc(element: Element; firstOnly, blockOnly: bool):
  seq[DOMRect] {.nimcall, raises: [].}
# set in server/buffer
var sheetLoadedImpl*: proc(bc: RootRef) {.nimcall, raises: [].}
var imageLoadedImpl*: proc(bc: RootRef) {.nimcall, raises: [].}
var navigateImpl*: proc(bc: RootRef; url: URL) {.nimcall, raises: [].}
var ensureLayoutImpl*: proc(bc: RootRef; element: Element) {.
  nimcall, raises: [].}
var clickImpl*: proc(bc: RootRef; element: HTMLElement) {.nimcall, raises: [].}

# Reflected attributes.
type
  ReflectType = enum
    rtStr, rtUrl, rtBool, rtLong, rtUlongGz, rtUlong, rtDoubleGz, rtFunction,
    rtReferrerPolicy, rtCrossOrigin, rtMethod, rtForm

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

proc makel(name: StaticAtom; ts: varargs[TagType]; default = 0u32):
    ReflectEntryTag =
  ReflectEntryTag(
    tags: @ts,
    e: ReflectEntry(
      attrname: name,
      funcname: name,
      t: rtLong,
      u: default
    )
  )

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

proc makeform(ts: varargs[TagType]): ReflectEntryTag =
  ReflectEntryTag(
    tags: @ts,
    e: ReflectEntry(attrname: satForm, funcname: satForm, t: rtForm)
  )

# Note: this table only works for tag types with a registered interface.
const ReflectMap0 = [
  # non-global attributes
  makes(satTarget, TAG_A, TAG_AREA, TAG_LABEL, TAG_LINK),
  makes(satHref, TAG_LINK),
  makes(satValue, TAG_BUTTON, TAG_DATA),
  makel(satValue, TAG_LI),
  makeb(satRequired, TAG_INPUT, TAG_SELECT, TAG_TEXTAREA),
  makes(satName, TAG_A, TAG_INPUT, TAG_SELECT, TAG_TEXTAREA, TAG_META,
    TAG_IFRAME, TAG_FRAME, TAG_IMG, TAG_OBJECT, TAG_PARAM, TAG_OBJECT, TAG_MAP,
    TAG_FORM, TAG_OUTPUT, TAG_FIELDSET, TAG_DETAILS, TAG_SLOT, TAG_OUTPUT),
  makes(satOpen, TAG_DETAILS),
  makeb(satNovalidate, satHNoValidate, TAG_FORM),
  makeb(satSelected, satDefaultSelected, TAG_OPTION),
  makes(satRel, TAG_A, TAG_LINK, TAG_LABEL),
  makes(satFor, satHtmlFor, TAG_LABEL, TAG_OUTPUT),
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
  makeform(TAG_BUTTON, TAG_INPUT, TAG_OUTPUT, TAG_SELECT, TAG_TEXTAREA),
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
      if it.parentNode == nil:
        break # found root

iterator safeChildList*(node: ParentNode): Node {.inline.} =
  var node = node.firstChild
  while node != nil:
    let next = node.nextSibling
    yield node
    node = next

# either the shadow root, or our child list
iterator shadowChildList*(node: ParentNode): Node {.inline.} =
  var it = node.firstChildShadow
  if it != nil:
    if it.parentNode == nil: # shadow root
      it = ParentNode(it).firstChildShadow
    if it != nil:
      while true:
        yield it
        it = it.internalNext
        if it.parentNode == nil:
          break # found root

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
    while it.parentNode != nil:
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

# inclusive ancestors
iterator branch*(node: Node): Node {.inline.} =
  var node = node
  while node != nil:
    yield node
    node = node.parentNode

iterator branchHost(node: Node): Node {.inline.} =
  var node = node.parentNodeHost
  while node != nil:
    yield node
    node = node.parentNodeHost

iterator branchElems*(element: Element): Element {.inline.} =
  var element = element
  while element != nil:
    yield element
    element = element.parentElement

iterator descendants*(node: ParentNode): Node {.inline.} =
  var it = node.firstChild
  while it != nil:
    yield it
    it = it.nextDescendant(node)

iterator descendantsShadowIncl(node: Node): Node {.inline.} =
  var it = node
  while it != nil:
    yield it
    it = it.nextDescendantShadow(node)

iterator elementDescendants*(node: ParentNode): Element {.inline.} =
  for child in node.descendants:
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

iterator controls*(form: HTMLFormElement): FormAssociatedElement {.inline.} =
  var control = form.controlsHead
  while control != nil:
    yield control
    control = control.next

iterator inputs(form: HTMLFormElement): HTMLInputElement {.inline.} =
  for control in form.controls:
    if control of HTMLInputElement:
      yield HTMLInputElement(control)

iterator radiogroup*(input: HTMLInputElement): HTMLInputElement {.inline.} =
  let name = input.name
  if name != satUempty:
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
    elif child.tagType == TAG_OPTGROUP:
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
  let res = ctx.invokeSink(global.weakMap[wwm], ctx.getOpaque().strRefs[jstSet],
    key, val)
  if JS_IsException(res):
    return err()
  JS_FreeValue(ctx, res)
  ok()

proc getWeak(ctx: JSContext; wwm: WindowWeakMap; key: JSValueConst): JSValue =
  let global = ctx.getGlobal()
  return ctx.invoke(global.weakMap[wwm], ctx.getOpaque().strRefs[jstGet], key)

proc isCell(this: Collection; node: Node): bool =
  node of Element and Element(node).tagType in {TAG_TD, TAG_TH}

proc isTBody(this: Collection; node: Node): bool =
  node of Element and Element(node).tagType == TAG_TBODY

proc isRow(this: Collection; node: Node): bool =
  node of HTMLTableRowElement

proc isOptionOf(node, select: Node): bool =
  if node of HTMLOptionElement:
    let parent = node.parentElement
    return Node(parent) == select or
      parent.tagType == TAG_OPTGROUP and Node(parent.parentNode) == select
  return false

proc isElement(this: Collection; node: Node): bool =
  node of Element

proc isForm(this: Collection; node: Node): bool =
  node of HTMLFormElement

proc isLink(this: Collection; node: Node): bool =
  if not (node of Element):
    return false
  let element = Element(node)
  element.tagType in {TAG_A, TAG_AREA} and element.attrb(satHref)

proc isImage(this: Collection; node: Node): bool =
  node of HTMLImageElement

proc logException(window: Window; url: URL) =
  #TODO excludepassword seems pointless?
  window.console.error("Exception in document",
    url.serialize(excludepassword = true), window.jsctx.getExceptionMsg())

proc newWeakCollection(ctx: JSContext; this: Node; wwm: WindowWeakMap):
    JSValue =
  case wwm
  of wwmChildren:
    return ctx.toJS(newHTMLCollection(
      this,
      match = isElement,
      islive = true,
      childonly = true
    ))
  of wwmChildNodes:
    return ctx.toJS(newNodeList(
      this,
      match = nil,
      islive = true,
      childonly = true
    ))
  of wwmSelectedOptions:
    let this = HTMLSelectElement(this)
    return ctx.toJS(newHTMLCollection(
      this,
      match = proc(this: Collection; node: Node): bool =
        node.isOptionOf(this.root) and HTMLOptionElement(node).selected,
      islive = true,
      childonly = false
    ))
  of wwmTBodies:
    return ctx.toJS(newHTMLCollection(
      this,
      match = isTBody,
      islive = true,
      childonly = true
    ))
  of wwmCells:
    return ctx.toJS(newHTMLCollection(
      this,
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
  if JS_IsException(jsThis):
    return JS_EXCEPTION
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

proc isSameOrigin*(window: Window; origin: Origin): bool =
  if window.dangerAlwaysSameOrigin: # for client
    return true
  return window.settings.origin.isSameOrigin(origin)

proc fetch*(window: Window; input: Request; finish: FetchFinish;
    opaque: RootRef) =
  #TODO cors requests?
  if input.url.schemeType != stData and
      not window.isSameOrigin(input.url.origin):
    return
  window.loader.fetch(input, finish, opaque)

proc corsFetch(window: Window; input: Request; finish: FetchFinish;
    opaque: RootRef) =
  if not window.settings.images and input.url.scheme.startsWith("img-codec+"):
    finish(opaque, nil)
    return
  window.loader.fetch(input, finish, opaque)

proc sheetLoaded(window: Window) =
  inc window.loadedSheetNum
  if window.bc != nil:
    sheetLoadedImpl(window.bc)

proc imageLoaded(window: Window) =
  inc window.loadedImageNum
  if window.bc != nil:
    imageLoadedImpl(window.bc)

proc importSheetFinish(window: Window; this: SheetElement;
    res: LoadSheetResult; env: ParseSheetEnv; i: int) =
  env.sheets[i] = res
  inc env.loaded
  if env.loaded == env.sheets.len:
    var head: CSSStylesheet = env.sheet
    var tail: CSSStylesheet = env.sheet
    for res in env.sheets:
      if res.head != nil:
        #TODO check import media query here
        if tail == nil:
          head = res.head
        else:
          tail.next = res.head
        tail = res.tail
    env.finish(window, this, LoadSheetResult(head: head, tail: tail),
      env.parent, env.i)
  window.sheetLoaded()

proc parseStylesheet(window: Window; this: SheetElement; s: string;
    baseURL: URL; charset: Charset; layer: CAtom; finish: LoadSheetFinish;
    parseEnv: ParseSheetEnv; i: int) =
  let sheet = s.parseStylesheet(baseURL, addr window.settings, coAuthor, layer)
  if sheet.s.importList.len == 0:
    let res = LoadSheetResult(head: sheet, tail: sheet)
    finish(window, this, res, parseEnv, i)
  else:
    var env = ParseSheetEnv(
      sheet: sheet,
      sheets: newSeq[LoadSheetResult](sheet.s.importList.len),
      finish: finish,
      parent: parseEnv,
      i: i
    )
    for i, it in sheet.s.importList.mypairs:
      let url = it.url
      let layer = it.layer
      inc window.remoteSheetNum
      window.loadSheet(this, url, charset, layer, importSheetFinish, i, env)
      freeAtom(layer)

proc cssDecode(iq: openArray[char]; fallback: Charset): string =
  var charset = fallback
  var offset = 0
  const charsetRule = "@charset \""
  if iq.startsWith("\xFE\xFF"):
    charset = csUtf16be
    offset = 2
  elif iq.startsWith("\xFF\xFE"):
    charset = csUtf16le
    offset = 2
  elif iq.startsWith("\xEF\xBB\xBF"):
    charset = csUtf8
    offset = 3
  elif iq.startsWith(charsetRule):
    let s = iq.toOpenArray(charsetRule.len, min(1024, iq.high)).until('"')
    let n = charsetRule.len + s.len
    if n >= 0 and n + 1 < iq.len and iq[n] == '"' and iq[n + 1] == ';':
      charset = getCharset(s)
      if charset in {csUtf16le, csUtf16be}:
        charset = csUtf8
  iq.toOpenArray(offset, iq.high).decodeAll(charset)

proc onFinishCSSText(response: Response; success: bool) =
  let blob = response.onFinishBlob(success)
  let env = LoadSheetEnv(response.opaque)
  let window = env.window
  let this = env.this
  let finish = env.finish
  if blob != nil:
    let charset = env.charset
    let s = blob.toOpenArray().cssDecode(charset)
    window.parseStylesheet(this, s, env.url, charset, env.layer, finish,
      env.parseEnv, env.i)
  else:
    finish(window, this, LoadSheetResult(), env.parseEnv, env.i)
  freeAtom(env.layer)

proc loadSheet0(opaque: RootRef; response: Response) =
  let env = LoadSheetEnv(opaque)
  let window = env.window
  if response != nil:
    if response.getContentType().equalsIgnoreCase("text/css"):
      response.onFinish = onFinishCSSText
      window.loader.blob(response, env)
      return
    window.loader.close(response)
  env.finish(window, env.this, LoadSheetResult(), env.parseEnv, env.i)

proc loadSheet(window: Window; this: SheetElement; url: URL; charset: Charset;
    layer: CAtom; finish: LoadSheetFinish; i: int; parseEnv: ParseSheetEnv) =
  let env = LoadSheetEnv(
    window: window,
    this: this,
    url: url,
    charset: charset,
    layer: layer.dup(),
    parseEnv: parseEnv,
    i: i,
    finish: finish
  )
  window.corsFetch(newRequest(url), loadSheet0, env)

proc loadSheet(window: Window; this: SheetElement; url: URL;
    finish: LoadSheetFinish) =
  let charset = this.getCharset()
  window.loadSheet(this, url, charset, CAtomNull, finish, 0, nil)

proc loadLinkFinish(window: Window; this: SheetElement;
    res: LoadSheetResult; env: ParseSheetEnv; i: int) =
  let link = HTMLLinkElement(this)
  let media = link.attr(satMedia)
  var applies = true
  if media != "":
    var ctx = initCSSParser(media)
    let media = ctx.parseMediaQueryList(window.settings.attrsp)
    applies = media.applies(addr window.settings)
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
  window.sheetLoaded()

proc loadLink(window: Window; link: HTMLLinkElement) =
  if not window.settings.styling or
      not link.relList.containsIgnoreCase(satStylesheet) or
      link.fetchStarted or link.isDisabled():
    return
  link.fetchStarted = true
  let href = link.attr(satHref)
  if href == "":
    return
  if url := parseURL(href, window.document.url):
    inc window.remoteSheetNum
    window.loadSheet(link, url, loadLinkFinish)

proc getImageId(window: Window): int =
  result = window.imageId
  inc window.imageId

proc fireEvent*(window: Window; event: Event; target: EventTarget) =
  discard window.jsctx.dispatch(target, event)

proc fireEvent*(window: Window; name: StaticAtom; target: EventTarget;
    bubbles, cancelable, trusted: bool) =
  let event = newTrustedEvent(name, target, bubbles, cancelable)
  window.fireEvent(event, target)

proc loadImageFinish(opaque: RootRef; response: Response) =
  let cachedURL = CachedURLImage(opaque)
  let window = cachedURL.window
  if response == nil:
    window.imageLoaded()
    return
  # close immediately; all data we're interested in is in the headers.
  window.loader.close(response)
  let headers = response.headers
  let dims = headers.getFirst("Cha-Image-Dimensions")
  let width = parseIntP(dims.until('x')).get(-1)
  let height = parseIntP(dims.after('x')).get(-1)
  if width < 0 or height < 0:
    window.console.error("wrong Cha-Image-Dimensions in", $response.url)
    window.imageLoaded()
    return
  let bmp = NetworkBitmap(
    width: width,
    height: height,
    cacheId: cachedURL.cacheId,
    imageId: window.getImageId(),
    contentType: "image/" & cachedURL.t,
    vector: cachedURL.t == "image/svg+xml"
  )
  cachedURL.bmp = bmp
  for share in cachedURL.shared:
    share.bitmap = bmp
    share.invalidate()
    #TODO fire error on error
    if window.settings.scripting != smFalse:
      window.fireEvent(satLoad, share, bubbles = false,
        cancelable = false, trusted = true)
  window.imageLoaded()

proc loadImage0(opaque: RootRef; response: Response) =
  let cachedURL = CachedURLImage(opaque)
  let window = cachedURL.window
  if response == nil:
    window.imageLoaded()
    return
  let contentType = response.getContentType("image/x-unknown")
  if not contentType.startsWith("image/"):
    window.loader.close(response)
    window.imageLoaded()
    return
  var subtype = contentType.after('/')
  if subtype == "x-unknown":
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
    let i = window.imageTypes.binarySearch(ext,
      proc(x: MimeTypesImageItem; ext: string): int {.nimcall.} =
        cmp(x.ext, ext)
    )
    if i >= 0:
      subtype = window.imageTypes[i].subtype
  cachedURL.cacheId = window.loader.addCacheFile(response.outputId)
  let url = parseURL0("img-codec+" & subtype & ":decode")
  if url == nil:
    window.loader.close(response)
    window.imageLoaded()
    return
  let request = newRequest(
    url,
    httpMethod = hmPost,
    headers = newHeaders(hgRequest, {"Cha-Image-Info-Only": "1"}),
    body = RequestBody(t: rbtOutput, outputId: response.outputId),
  )
  cachedURL.t = subtype
  window.corsFetch(request, loadImageFinish, opaque)
  window.loader.close(response)
  var expiry = -1i64
  for s in response.headers.getAllCommaSplit("Cache-Control"):
    if s.startsWithIgnoreCase("max-age="):
      let i = s.skipBlanks("max-age=".len)
      let s = s.until(NonDigit, i)
      if pi := parseInt64(s):
        expiry = getTime().toUnix() + pi
      break
  cachedURL.loading = false
  cachedURL.expiry = expiry

proc loadImageFromCache(window: Window; image: HTMLImageElement; surl: string):
    bool =
  let cachedURL = window.imageURLCache.getOrDefault(surl)
  if cachedURL == nil:
    return false
  if cachedURL.expiry > getTime().toUnix():
    image.bitmap = cachedURL.bmp
    return true
  if cachedURL.loading:
    cachedURL.shared.add(image)
    return true
  false

proc loadImage*(window: Window; image: HTMLImageElement) =
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
  let url0 = parseURL(src, window.document.url)
  if url0.isErr:
    return
  let url = url0.get
  if window.document.url.schemeType == stHttps and url.schemeType == stHttp:
    # mixed content :/
    #TODO maybe do this in loader?
    url.setProtocol("https")
  let surl = $url
  if window.loadImageFromCache(image, surl):
    return
  let cachedURL = CachedURLImage(
    cacheId: -1,
    window: window,
    expiry: -1,
    loading: true,
    shared: @[image]
  )
  window.imageURLCache[surl] = cachedURL
  let headers = newHeaders(hgRequest, {"Accept": "*/*"})
  inc window.remoteImageNum
  let request = newRequest(url, headers = headers)
  window.corsFetch(request, loadImage0, cachedURL)

type LoadSVGEnv {.final.} = ref object of RootObj
  window: Window
  svg: SVGSVGElement
  cacheId: int
  imageId: int

proc loadSVGFinish(opaque: RootRef; response: Response) =
  let env = LoadSVGEnv(opaque)
  let window = env.window
  let svg = env.svg
  if response == nil: # no SVG module; give up
    window.imageLoaded()
    return
  let loader = window.loader
  # close immediately; all data we're interested in is in the headers.
  loader.close(response)
  let dims = response.headers.getFirst("Cha-Image-Dimensions")
  let width = parseIntP(dims.until('x')).get(-1)
  let height = parseIntP(dims.after('x')).get(-1)
  if width < 0 or height < 0:
    window.console.error("wrong Cha-Image-Dimensions in", $response.url)
    window.imageLoaded()
    return
  svg.bitmap = NetworkBitmap(
    width: width,
    height: height,
    cacheId: env.cacheId,
    imageId: env.imageId,
    contentType: "image/svg+xml",
    vector: true
  )
  for share in svg.shared:
    share.bitmap = svg.bitmap
    share.invalidate()
  svg.invalidate()
  window.imageLoaded()

proc loadSVG*(window: Window; svg: SVGSVGElement) =
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
  let res = ps.writeLoop(s)
  ps.sclose()
  if res.isErr:
    return
  let request = newRequest(
    "img-codec+svg+xml:decode",
    httpMethod = hmPost,
    headers = newHeaders(hgRequest, {"Cha-Image-Info-Only": "1"}),
    body = RequestBody(t: rbtOutput, outputId: svgres.outputId)
  )
  let env = LoadSVGEnv(
    window: window,
    svg: svg,
    cacheId: cacheId,
    imageId: imageId
  )
  inc window.remoteImageNum
  loader.fetch(request, loadSVGFinish, env)
  loader.close(svgres)

proc navigate*(window: Window; url: URL) =
  if window.bc != nil:
    navigateImpl(window.bc, url)

proc ensureLayout(window: Window; element: Element) =
  if window.bc != nil:
    ensureLayoutImpl(window.bc, element)

proc click(window: Window; element: HTMLElement) =
  if window.bc != nil:
    clickImpl(window.bc, element)

proc runJSJobs*(window: Window) =
  let rt = JS_GetRuntime(window.jsctx)
  while true:
    let ctx = rt.runJSJobs()
    if ctx == nil:
      break
    window.console.writeException(ctx)

proc performMicrotaskCheckpoint*(window: Window) =
  if window.inMicrotaskCheckpoint:
    return
  window.inMicrotaskCheckpoint = true
  window.runJSJobs()
  window.inMicrotaskCheckpoint = false

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

proc getComputedStyle0*(ctx: JSContext; window: Window; element: Element;
    pseudoElt: JSValueConst): Opt[CSSStyleDeclaration] =
  if not element.isConnected():
    return ok(newCSSStyleDeclaration(nil, ""))
  var pseudo = peNone
  if not JS_IsUndefined(pseudoElt):
    # This isn't what the spec says, but it seems to be what others do.
    # Note: in Gecko this is case-sensitive, in Blink it isn't.  CSS itself
    # is case-insensitive so I assume it's a Gecko bug.
    var ds: DOMString
    ?ctx.fromJS(pseudoElt, ds)
    let i = if ds.p[0] != ':': 0 elif ds.p[1] != ':': 1 else: 2
    if i != 0: # if no : at the beginning, ignore pseudoElt
      pseudo = parseEnumNoCase[PseudoElement](ds.toOpenArray(i)).get(peNone)
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
  let rt = this.rt
  for def in this.defs:
    freeAtom(def.name)
    freeAtom(def.localName)
    JS_FreeValueRT(rt, def.ctor)
    freeAtoms(def.observedAttrs)
    rt.freeValues(def.callbacks)

type CustomElementDefinitionOptions = object of JSDict
  extends {.jsdefault.}: Option[string]

proc find(this: CustomElementRegistry; name: CAtomTraced): CustomElementDef =
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
    res: var seq[CAtom]): Opt[void] =
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
      JS_ThrowTypeError(ctx, "not a function")
      return err()
  ok()

proc define0(ctx: JSContext; this: CustomElementRegistry; name: CAtomTraced;
    ctor, proto: JSValueConst; def: CustomElementDef): Opt[void] =
  if not JS_IsObject(proto):
    JS_ThrowTypeError(ctx, "prototype is not an object")
    return err()
  for t in cctConnected..cctAttributeChanged:
    ?ctx.tryGetCallback(proto, t, def.callbacks)
  if not JS_IsNull(def.callbacks[cctAttributeChanged]):
    ?ctx.tryGetStrSeq(ctor, "observedAttributes", def.observedAttrs)
  var disabled: seq[CAtom]
  ?ctx.tryGetStrSeq(ctor, "disabledFeatures", disabled)
  if satInternals in disabled:
    def.flags.excl(cefInternals)
  if satShadow in disabled:
    def.flags.excl(cefShadow)
  freeAtoms(disabled)
  var formAssociated: bool
  discard ?ctx.fromJSGetProp(ctor, "formAssociated", formAssociated)
  if formAssociated:
    def.flags.incl(cefFormAssociated)
    for t in cctFormAssociated..cctFormStateRestore:
      ?ctx.tryGetCallback(proto, t, def.callbacks)
  ok()

proc newCustomElementDef(name, localName: CAtomTraced): CustomElementDef =
  let def = CustomElementDef(
    name: name.dup(),
    localName: localName.dup(),
    flags: {cefInternals, cefShadow}
  )
  for it in def.callbacks.mitems:
    it = JS_NULL
  return def

proc define(ctx: JSContext; this: CustomElementRegistry; name: CAtomTraced;
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
    ctx.freeValues(def.callbacks)
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

proc get(ctx: JSContext; this: CustomElementRegistry; name: CAtomTraced):
    JSValue {.jsfunc.} =
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

proc addScopedDocument(this: CustomElementRegistry; document: Document) =
  if document notin this.scopedDocuments:
    this.scopedDocuments.add(document)

# Node
when defined(debug):
  proc `$`*(node: Node): string =
    if node == nil:
      return "null"
    if node of Document:
      return "Document"
    result = ""
    result.serializeFragmentInner(node, TAG_UNKNOWN, writeShadow = true)

proc baseURI(node: Node): string {.jsfget.} =
  return $node.document.baseURL

proc rootNode(node: Node): Node {.jsfunc.} =
  # If connected, return root; otherwise, return the owner document.
  let parent = node.parentNode
  if parent == nil:
    return node
  parent.lastChild.internalNext

proc document*(node: Node): Document =
  # Return the owner document, or node itself if it is a document.
  var node = node
  while true:
    node = node.rootNode
    if node of Document:
      break
    if node of ShadowRoot:
      node = ShadowRoot(node).host
    else:
      node = node.internalNext
      break
  Document(node)

proc parentNodeShadow(node: Node): Node =
  let parent = node.parentNode
  if parent == nil and node of ShadowRoot:
    return ShadowRoot(node).host
  return parent

proc parentNodeHost(node: Node): Node =
  let parent = node.parentNode
  if parent == nil and node of DocumentFragment:
    return DocumentFragment(node).host
  return parent

proc parentElement*(node: Node): Element {.jsfget.} =
  let p = node.parentNode
  if p != nil and p of Element:
    return Element(p)
  return nil

proc nextSiblingShadow(node: Node): Node =
  let next = node.internalNext
  if next == nil or next.parentNode == nil:
    # if next is nil, then node is a Document.
    # if next.parentNode is nil, then next is the root.
    return nil
  return next

proc nextSibling(node: Node): Node {.jsfget.} =
  if node.parentNode == nil:
    # if parent is nil, then may be a shadow root
    return nil
  return node.nextSiblingShadow

proc previousSibling*(node: Node): Node {.jsfget.} =
  if node.parentNode == nil or node == node.parentNode.firstChild:
    return nil
  return node.internalPrev

# performance-sensitive, so we inline this with a template
template nextDescendantExclImpl(node, start: Node): Node =
  # climb up until we find a non-last leaf (this might be node itself)
  var it = node
  while it != start:
    let next = it.nextSibling
    if next != nil:
      return next
    it = it.parentNode
  # done
  nil

# Return the next descendant if it isn't `start', and nil otherwise.
# Note: `start' must be either an ancestor of `node', `node` itself, or nil.
proc nextDescendant(node, start: Node): Node =
  if node of ParentNode: # parent
    let first = cast[ParentNode](node).firstChild
    if first != nil:
      return first
  node.nextDescendantExclImpl(start)

# Like nextDescendant, but skip children when `skip` is true.
proc nextDescendant(node, start: Node; skip: bool): Node =
  if not skip and node of ParentNode: # parent
    let first = cast[ParentNode](node).firstChild
    if first != nil:
      return first
  node.nextDescendantExclImpl(start)

proc nextDescendantShadow(node, start: Node): Node =
  if node of ParentNode: # parent
    let node = cast[ParentNode](node)
    if node.firstChildShadow != nil:
      return node.firstChildShadow
  # climb up until we find a non-last leaf (this might be node itself)
  var node = node
  while node != start:
    let next = node.nextSiblingShadow
    if next != nil:
      return next
    node = node.parentNodeShadow
  # done
  return nil

proc previousDescendant(node: Node): Node =
  var prev = node.previousSibling
  if prev == nil:
    return node.parentNode
  while prev of ParentNode:
    let pnode = cast[ParentNode](prev)
    if pnode.firstChild == nil:
      break
    prev = pnode.lastChild
  prev

proc previousDescendant(node, start: Node): Node =
  if node == start:
    return nil
  var prev = node.previousSibling
  if prev == nil:
    return node.parentNode
  while prev of ParentNode:
    let pnode = cast[ParentNode](prev)
    if pnode.firstChild == nil:
      break
    prev = pnode.lastChild
  return prev

proc ownerDocument(node: Node): Document {.jsfget.} =
  if node of Document:
    return nil
  return node.document

proc nodeTypeEnum(node: Node): NodeType =
  if node of CharacterData:
    if node of CDATASection:
      return ntCdataSection
    elif node of Comment:
      return ntComment
    elif node of ProcessingInstruction:
      return ntProcessingInstruction
    else: # Text
      return ntText
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
  return uint16(node.nodeTypeEnum)

proc nodeName(ctx: JSContext; node: Node): JSValue {.jsfget.} =
  if node of Element:
    return ctx.jsTagName(Element(node))
  if node of Attr:
    return ctx.toJS(Attr(node).data.qualifiedName)
  if node of DocumentType:
    return ctx.toJS(DocumentType(node).name)
  if node of CDATASection:
    return JS_NewString(ctx, "#cdata-section")
  if node of Comment:
    return JS_NewString(ctx, "#comment")
  if node of Document:
    return JS_NewString(ctx, "#document")
  if node of DocumentFragment:
    return JS_NewString(ctx, "#document-fragment")
  if node of ProcessingInstruction:
    return ctx.toJS(ProcessingInstruction(node).target)
  return JS_NewString(ctx, "#text")

proc isValidChild(node: Node): bool =
  return node of DocumentFragment or node of DocumentType or node of Element or
    node of CharacterData

proc checkParentValidity(parent: Node): Result[ParentNode, cstring] =
  if parent of ParentNode:
    return ok(cast[ParentNode](parent))
  return err("parent must be a document, a document fragment, or an element")

proc rootNodeShadow(node: Node): Node =
  var node = node.rootNode
  while node of ShadowRoot:
    node = ShadowRoot(node).host.rootNode
  node

proc isInclusiveAncestorHost(a, b: Node): bool =
  for it in b.branchHost:
    if it == a:
      return true
  return false

proc hasNextSibling(node: Node; t: NodeType): bool =
  var node = node.nextSibling
  while node != nil:
    if node.nodeTypeEnum == t:
      return true
    node = node.nextSibling
  return false

proc hasPreviousSibling(node: Node; t: NodeType): bool =
  var node = node.previousSibling
  while node != nil:
    if node.nodeTypeEnum == t:
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
  return node.rootNodeShadow of Document

proc inSameTree*(a, b: Node): bool =
  a.rootNode == b.rootNode

# a == b or a in b's ancestors
proc contains(a, b: Node): bool =
  for node in b.branch:
    if node == a:
      return true
  return false

proc contains(a: Node; b: Option[Node]): bool {.jsfunc.} =
  let b = b.get(nil)
  if b == nil:
    return false
  a.contains(b)

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
  if node.isInclusiveAncestorHost(parent):
    return err("parent must be an ancestor")
  if before != nil and before.parentNode != parent:
    return err(nil)
  if not node.isValidChild():
    return err("node is not a valid child")
  if parent of Document:
    if node of DocumentFragment:
      let node = DocumentFragment(node)
      let elems = node.countChildren(ntElement)
      if elems > 1 or node.hasChild(ntText):
        return err("document fragment has invalid children")
      elif elems == 1 and (parent.hasChild(ntElement) or
          before != nil and (before of DocumentType or
          before.hasNextSibling(ntDocumentType))):
        return err("document fragment has invalid children")
    elif node of Element:
      if parent.hasChild(ntElement):
        return err("document already has an element child")
      elif before != nil and (before of DocumentType or
            before.hasNextSibling(ntDocumentType)):
        return err("cannot insert element before document type")
    elif node of DocumentType:
      if parent.hasChild(ntDocumentType) or
          before != nil and before.hasPreviousSibling(ntElement) or
          before == nil and parent.hasChild(ntElement):
        return err("cannot insert document type before an element node")
    elif node of Text:
      return err("cannot insert text into document")
    else: discard
  elif node of DocumentType:
    return err("document type can only be inserted into document")
  ok(parent)

# Pass an index to avoid searching for the node in parent's child list.
proc removeImpl*(node: Node; suppressObservers = false) =
  let parent = node.parentNode
  if parent == nil:
    return
  let oldRootNode = node.rootNode
  let document = oldRootNode.document
  # document is only nil for Document nodes, but those cannot call
  # remove().
  assert document != nil
  #TODO live ranges
  document.invalidateCollectionsRemove(node)
  let element = if node of Element: Element(node) else: nil
  let parentElement = node.parentElement
  if parentElement != nil:
    parentElement.invalidate()
  let prev = node.internalPrev
  let next = node.internalNext
  if next != nil and next.parentNode != nil:
    next.internalPrev = prev
  else:
    parent.firstChild.internalPrev = prev
  if parent.firstChild == node:
    if next != nil and next.parentNode != nil:
      parent.setFirstChild(next)
    else:
      parent.setFirstChild(nil)
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
    if parentElement != nil and next.parentNode == parent:
      parentElement.flags.incl(efChildElIndicesInvalid)
    element.internalElIndex = 0
    if element of SheetElement:
      SheetElement(element).removeSheet()
  #TODO assigned
  if oldRootNode of ShadowRoot:
    let shadow = ShadowRoot(oldRootNode)
    discard shadow
    #TODO signal slot change if parent is slot without assigned nodes
  let parentConnected = oldRootNode.isConnected
  for desc in node.descendantsShadowIncl:
    #TODO assign slottables with parent's root & node
    let last = desc.lastChild
    if last != nil: # update root
      last.internalNext = node
    if desc of Element:
      let element = Element(desc)
      if element.id != satUempty and oldRootNode == document:
        document.removeElementId(element)
      document.applyStyleDependencies(element, DependencyInfo.default)
      element.removingSteps()
      if element.custom == cesCustom and parentConnected:
        discard #TODO call disconnectedCallback
  #TODO registered observers
  if not suppressObservers:
    discard #TODO queue tree mutation record
  #TODO children changed steps

# e may be nil
proc insertThrow(ctx: JSContext; e: cstring): JSValue =
  if e == nil:
    return JS_ThrowDOMException(ctx, "NotFoundError",
      "reference node is not a child of parent")
  return JS_ThrowDOMException(ctx, "HierarchyRequestError", e)

proc removeChild(ctx: JSContext; parent, node: Node): JSValue {.jsfunc.} =
  if Node(node.parentNode) != parent:
    return ctx.insertThrow(nil)
  node.removeImpl()
  return ctx.toJS(node)

# before may be nil
proc insertBefore(parent, node, before: Node; ctx: JSContext): Err[cstring] =
  let parent = ?parent.preInsertionValidity(node, before)
  let referenceChild = if before == node:
    node.nextSibling
  else:
    before
  parent.insert(node, referenceChild, ctx)
  ok()

proc insertBefore(ctx: JSContext; parent, node: Node; before: Option[Node]):
    JSValue {.jsfunc.} =
  let res = parent.insertBefore(node, before.get(nil), ctx)
  if res.isErr:
    return ctx.insertThrow(res.error)
  return ctx.toJS(node)

proc insertBeforeUndefined(ctx: JSContext; parent, node: Node;
    before: Option[Node]): JSValue =
  let res = parent.insertBefore(node, before.get(nil), ctx)
  if res.isErr:
    return ctx.insertThrow(res.error)
  return JS_UNDEFINED

proc appendChild(ctx: JSContext; parent, node: Node): JSValue {.jsfunc.} =
  return ctx.insertBefore(parent, node, none(Node))

#TODO this looks wrong. either pre-insert and throw or just insert...
proc append(parent, node: Node; ctx: JSContext) =
  discard parent.insertBefore(node, nil, ctx)

# Replace child with node.
# Note: the argument ordering here is the opposite of replaceChild.
proc replaceChildWith*(parent, child, node: Node; ctx: JSContext):
    Err[cstring] =
  let parent = ?parent.checkParentValidity()
  if node.isInclusiveAncestorHost(parent):
    return err("parent must be an ancestor")
  if child.parentNode != parent:
    return err(nil)
  if not node.isValidChild():
    return err("node is not a valid child")
  let childNextSibling = child.nextSibling
  let childPreviousSibling = child.previousSibling
  if parent of Document:
    if node of DocumentFragment:
      let node = DocumentFragment(node)
      let elems = node.countChildren(ntElement)
      if elems > 1 or node.hasChild(ntText):
        return err("document fragment has invalid children")
      elif elems == 1 and (parent.hasChildExcept(ntElement, child) or
          childNextSibling != nil and childNextSibling of DocumentType):
        return err("document fragment has invalid children")
    elif node of Element:
      if parent.hasChildExcept(ntElement, child):
        return err("document already has an element child")
      elif childNextSibling != nil and childNextSibling of DocumentType:
        return err("cannot insert element before document type")
    elif node of DocumentType:
      if parent.hasChildExcept(ntDocumentType, child) or
          childPreviousSibling != nil and childPreviousSibling of DocumentType:
        return err("cannot insert document type before an element node")
    elif node of Text:
      return err("replacement cannot be placed in parent")
  elif node of DocumentType:
    return err("replacement cannot be placed in parent")
  let referenceChild = if childNextSibling == node:
    node.nextSibling
  else:
    childNextSibling
  #NOTE the standard says "if parent is not null", but the adoption step
  # that made it necessary has been removed.
  child.removeImpl(suppressObservers = true)
  parent.insert(node, referenceChild, ctx, suppressObservers = true)
  #TODO tree mutation record
  ok()

# Warning: the ordering is counter-intuitive here.
proc jsReplaceChild(ctx: JSContext; parent, node, child: Node): JSValue {.
    jsfunc: "replaceChild".} =
  let res = parent.replaceChildWith(child, node, ctx)
  if res.isErr:
    return ctx.insertThrow(res.error)
  return ctx.toJS(child)

proc replaceChildWithThrow(ctx: JSContext; parent, child, node: Node):
    JSValue =
  let res = parent.replaceChildWith(child, node, ctx)
  if res.isErr:
    return ctx.insertThrow(res.error)
  return JS_UNDEFINED

proc clone(node: Node; ctx: JSContext; document = none(Document);
    deep = false): Node =
  let document = document.get(node.document)
  let copy = if node of Element:
    #TODO is value
    let element = Element(node)
    let x = document.newElement(element.localName.view(),
      element.namespaceURI.view(), element.tagName.view())
    x.id = element.id.dup()
    x.name = element.name.dup()
    for it in element.classList.toks:
      x.classList.toks.add(it.dup())
    x.attrs = element.dupAttrs()
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
      attrs: @[data]
    )
    Node(dummy.newAttr(0))
  elif node of Text:
    let node = Text(node)
    if node of CDATASection:
      Node(document.newCDATASection(newRefString(node.data.s)))
    else:
      Node(document.newText(node.data.s))
  elif node of Comment:
    let comment = Comment(node)
    let x = document.newComment(newRefString(comment.data.s))
    Node(x)
  elif node of ProcessingInstruction:
    let pi = ProcessingInstruction(node)
    let clone = document.newProcessingInstruction(pi.target,
      newRefString(pi.data.s))
    Node(clone)
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
      copy.append(child.clone(ctx, deep = true), ctx)
  copy

proc cloneNode(ctx: JSContext; node: Node; deep = false): JSValue {.jsfunc.} =
  if node of ShadowRoot:
    return JS_ThrowDOMException(ctx, "NotSupportedError",
      "cannot clone shadow roots")
  let copy = node.clone(ctx, deep = deep)
  if node of Element:
    let element = Element(node)
    let shadow = element.shadowRoot
    if shadow != nil:
      let customElements = shadow.globalCustomElements
      let x = ctx.attachShadow(Element(copy), ShadowRootInit(
        mode: shadow.mode,
        serializable: shadow.serializable,
        delegatesFocus: shadow.delegatesFocus,
        slotAssignment: shadow.slotAssignment,
        customElementRegistry: customElements
      ))
      if x.isErr:
        return JS_EXCEPTION
      let copyShadow = x.get
      copyShadow.declarative = shadow.declarative
      copyShadow.unsetCustomElements = shadow.unsetCustomElements
      for child in shadow.childList:
        copyShadow.append(child.clone(ctx, deep = deep), ctx)
  return ctx.toJS(copy)

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
      if node.namespaceURI != other.namespaceURI or
          node.tagName != other.tagName or node.attrs.len != other.attrs.len:
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
    if node.target != other.target or node.data.s != other.data.s:
      return false
  elif node of CharacterData:
    if node of Text and not (other of Text) or
        node of Comment and not (other of Comment) or
        node of CDATASection and not (other of CDATASection):
      return false
    return CharacterData(node).data.s == CharacterData(other).data.s
  true

proc serializeFragmentInner(res: var string; child: Node; parentType: TagType;
    writeShadow: bool) =
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
    res.serializeFragment(element, writeShadow)
    res &= "</" & tags & '>'
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

proc serializeFragment(res: var string; node: Node; writeShadow: bool) =
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
      let shadow = element.shadowRoot
      if shadow != nil and writeShadow and shadow.serializable:
        res &= "<template shadowrootmode=\"" & $shadow.mode & '"'
        if shadow.delegatesFocus:
          res &= " shadowrootdelegatesfocus=\"\""
        if shadow.serializable:
          res &= " shadowrootserializable=\"\""
        if shadow.clonable:
          res &= " shadowrootclonable=\"\""
        let docCustomElements = node.document.customElements
        let shadowCustomElements = shadow.customElements
        if docCustomElements != nil and not docCustomElements.scoped or
            shadowCustomElements != nil and not shadowCustomElements.scoped:
          res &= " shadowrootcustomelementregistry=\"\""
        res &= '>'
        res.serializeFragment(shadow, writeShadow)
        res &= "</template>"
  if node of ParentNode:
    let node = ParentNode(node)
    for child in node.childList:
      res.serializeFragmentInner(child, parentType, writeShadow)

proc serializeFragment*(node: Node; writeShadow: bool): string =
  result = ""
  result.serializeFragment(node, writeShadow)

proc findAncestor*(node: Node; tagType: TagType): Element =
  for element in node.ancestors:
    if element.tagType == tagType:
      return element
  return nil

proc setNodeValue(ctx: JSContext; node: Node; data: DOMStringNull): Opt[void]
    {.jsfset: "nodeValue".} =
  if node of CharacterData:
    let node = CharacterData(node)
    node.data = newRefString(data)
  elif node of Attr:
    Attr(node).setValue(data)
  return ok()

proc setTextContent(ctx: JSContext; node: Node; data: DOMStringNull): Opt[void]
    {.jsfset: "textContent".} =
  if node of Element or node of DocumentFragment:
    let node = ParentNode(node)
    node.replaceAll(data, ctx)
    return ok()
  return ctx.setNodeValue(node, data)

proc toNodes(ctx: JSContext; nodes: openArray[JSValueConst];
    res: var seq[Node]): Opt[void] =
  for it in nodes:
    var node: Node
    if ctx.fromJS(it, node).isOk:
      res.add(node)
    else:
      var ds: DOMString
      ?ctx.fromJS(it, ds)
      res.add(ctx.newText(ds))
  ok()

proc toNode(ctx: JSContext; nodes: openArray[Node]; document: Document): Node =
  if nodes.len == 1:
    return nodes[0]
  let fragment = document.newDocumentFragment()
  for node in nodes:
    fragment.append(node, ctx)
  fragment

proc toNode(ctx: JSContext; argv: openArray[JSValueConst];
    document: Document): Opt[Node] =
  var nodes: seq[Node] = @[]
  ?ctx.toNodes(argv, nodes)
  ok(ctx.toNode(nodes, document))

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
  parent.replaceAll(node, ctx)
  return JS_UNDEFINED

proc previousSiblingExcept(this: Node; nodes: openArray[Node]): Node =
  var node = this
  while node != nil:
    if node notin nodes:
      break
    node = node.previousSibling
  node

proc nextSiblingExcept(this: Node; nodes: openArray[Node]): Node =
  var node = this
  while node != nil:
    if node notin nodes:
      break
    node = node.nextSibling
  node

proc beforeImpl(ctx: JSContext; this: Node; argv: varargs[JSValueConst]):
    Opt[void] =
  var nodes: seq[Node]
  ?ctx.toNodes(argv, nodes)
  let parent = this.parentNode
  if parent != nil:
    let prev = this.previousSiblingExcept(nodes)
    let node = ctx.toNode(nodes, this.document)
    let before = if prev != nil: prev.nextSibling else: parent.firstChild
    parent.insert(node, before, ctx)
  ok()

proc afterImpl(ctx: JSContext; this: Node; argv: varargs[JSValueConst]):
    Opt[void] =
  var nodes: seq[Node]
  ?ctx.toNodes(argv, nodes)
  let parent = this.parentNode
  if parent != nil:
    let before = this.nextSiblingExcept(nodes)
    let node = ctx.toNode(nodes, this.document)
    parent.insert(node, before, ctx)
  ok()

proc replaceWithImpl(ctx: JSContext; this: Node; argv: varargs[JSValueConst]):
    JSValue =
  var nodes: seq[Node]
  if ctx.toNodes(argv, nodes).isErr:
    return JS_EXCEPTION
  let parent = this.parentNode
  if parent != nil:
    let before = this.nextSiblingExcept(nodes)
    let node = ctx.toNode(nodes, this.document)
    if this.parentNode == parent:
      return ctx.replaceChildWithThrow(parent, this, node)
    parent.insert(node, before, ctx)
  return JS_UNDEFINED

proc assignSlot(node: Node) =
  discard

# ParentNode
proc firstChild(parent: ParentNode): Node =
  let child = parent.internalFirst
  if child != nil and child.parentNode == nil:
    when defined(debug):
      assert child of ShadowRoot
    return child.internalNext
  return child

proc firstChildShadow(parent: ParentNode): Node =
  return parent.internalFirst

proc setFirstChild(node: ParentNode; child: Node) =
  let first = node.internalFirst
  if first != nil and first.parentNode == nil: # shadow root
    first.internalNext = child
  else:
    node.internalFirst = child

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

proc replaceAll(parent: ParentNode; node: Node; ctx: JSContext) =
  let removedNodes = parent.getChildList()
  for child in removedNodes:
    child.removeImpl(true)
  if node != nil:
    if node of DocumentFragment:
      let nodes = DocumentFragment(node).getChildList()
      for it in nodes:
        parent.insert(it, nil, ctx, suppressObservers = true)
    else:
      parent.insert(node, nil, ctx, suppressObservers = true)
  #TODO tree mutation record

proc replaceAll(parent: ParentNode; ds: DOMString; ctx: JSContext) =
  let node = if ds.len > 0: parent.document.newText(ds) else: nil
  parent.replaceAll(node, ctx)

proc childrenImpl(ctx: JSContext; node: ParentNode): JSValue =
  return ctx.getWeakCollection(node, wwmChildren)

proc childElementCountImpl(node: ParentNode): uint32 =
  let last = node.lastElementChild
  if last == nil:
    return 0
  return last.elIndex + 1

proc countChildren(node: ParentNode; t: NodeType): int =
  result = 0
  for child in node.childList:
    if child.nodeTypeEnum == t:
      inc result

proc hasChild(node: ParentNode; t: NodeType): bool =
  for child in node.childList:
    if child.nodeTypeEnum == t:
      return true
  return false

proc hasChildExcept(node: ParentNode; t: NodeType; ex: Node): bool =
  for child in node.childList:
    if child == ex:
      continue
    if child.nodeTypeEnum == t:
      return true
  return false

proc childTextContent*(node: ParentNode): string =
  result = ""
  for child in node.childList:
    if child of Text:
      result &= Text(child).data.s

proc getElementsByTagNameImpl(root: ParentNode; tagName: CAtomTraced):
    HTMLCollection =
  if tagName == satUstar:
    return newHTMLCollection(root, isElement, islive = true, childonly = false)
  let this = newHTMLCollection(
    root,
    proc(this: Collection; node: Node): bool =
      if node of Element:
        let element = Element(node)
        let atom = this.atoms[0]
        if element.namespaceURI == satNamespaceHTML:
          return element.tagName.equalsIgnoreCase(atom)
        return element.tagName == atom
      return false,
    islive = true,
    childonly = false
  )
  this.atoms = @[tagName.dup()]
  this

proc getElementsByClassNameImpl(node: ParentNode; classNames: DOMString):
    HTMLCollection =
  let this = newHTMLCollection(
    node,
    proc(this: Collection; node: Node): bool =
      if not (node of Element):
        return false
      let element = Element(node)
      if element.document.mode == QUIRKS:
        for class in this.atoms:
          if not element.classList.toks.containsIgnoreCase(class):
            return false
      else:
        for class in this.atoms:
          if class notin element.classList.toks:
            return false
      true,
    islive = true,
    childonly = false
  )
  for class in classNames.toOpenArray().split(AsciiWhitespace):
    this.atoms.add(class.toAtom())
  this

proc insert0(parent: ParentNode; node, before: Node;
    postConnectionNodes: var seq[Element]; ctx: JSContext) =
  let parentDocument = parent.document
  parentDocument.adopt(node, ctx)
  let rootNode = parent.rootNode
  let element = if node of Element: Element(node) else: nil
  let first = parent.firstChild
  if before == nil:
    if first != nil:
      let last = first.internalPrev
      last.internalNext = node
      node.internalPrev = last
      first.internalPrev = node
    else:
      parent.setFirstChild(node)
      node.internalPrev = node
  else:
    node.internalNext = before
    let prev = before.internalPrev
    node.internalPrev = prev
    if prev.nextSibling != nil:
      prev.internalNext = node
    before.internalPrev = node
    if before == first:
      parent.setFirstChild(node)
  node.parentNode = parent
  let parentElement = node.parentElement
  if element != nil:
    if element.nextSibling != nil and parentElement != nil:
      parentElement.flags.incl(efChildElIndicesInvalid)
    elif (let prev = element.previousElementSibling; prev != nil):
      element.internalElIndex = prev.internalElIndex + 1
    else:
      element.internalElIndex = 0
  parentDocument.invalidateCollections()
  if parentElement != nil:
    let shadow = parentElement.shadowRoot
    if shadow != nil and shadow.slotAssignment == samNamed and
        (element != nil or node of Text):
      node.assignSlot()
    if parentElement.tagType == TAG_SLOT and rootNode of ShadowRoot:
      discard #TODO signal a slot change
    #TODO assign slottables for a tree with root
  if node.nextSibling == nil:
    node.internalNext = rootNode
  for desc in node.descendantsShadowIncl:
    let last = desc.lastChild
    if last != nil: # update root
      last.internalNext = rootNode
    if desc of Element:
      let el = Element(desc)
      if el.id != satUempty and desc.rootNode == parentDocument:
        parentDocument.addElementId(el)
      if el.insertionSteps():
        postConnectionNodes.add(el)
      if el.custom == cesCustom:
        #TODO append parentDocument to element custom registry
        #TODO enqueue connectedCallback (custom elements)
        discard
      else:
        discard #TODO try to upgrade (custom elements)
    elif desc of ShadowRoot:
      let shadow = ShadowRoot(desc)
      let customElements = shadow.customElements
      if customElements != nil and customElements.scoped:
        customElements.addScopedDocument(parentDocument)

# WARNING ditto
proc insert*(parent: ParentNode; node, before: Node; ctx: JSContext;
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
      child.removeImpl(suppressObservers = true)
    #TODO tree mutation record
  if before != nil:
    #TODO live ranges
    discard
  if parent of Element:
    Element(parent).invalidate()
  var postConnectionNodes: seq[Element] = @[]
  for node in nodes:
    parent.insert0(node, before, postConnectionNodes, ctx)
  #TODO children changed steps for parent
  if not suppressObservers:
    discard #TODO queue tree mutation record
  for el in postConnectionNodes:
    el.postConnectionSteps()

proc parseSelectors(ctx: JSContext; ds: DOMString): SelectorList =
  result = parseSelectors(ds)
  if result.len == 0:
    JS_ThrowDOMException(ctx, "SyntaxError", "invalid selector: %s", ds.p)

proc querySelectorImpl(ctx: JSContext; node: ParentNode; q: DOMString):
    JSValue =
  let selectors = ctx.parseSelectors(q)
  if selectors.len == 0:
    return JS_EXCEPTION
  for element in node.elementDescendants:
    if element.matchesImpl(selectors):
      return ctx.toJS(element)
  return JS_NULL

proc querySelectorAllImpl(ctx: JSContext; node: ParentNode; q: DOMString):
    JSValue =
  let selectors = ctx.parseSelectors(q)
  if selectors.len == 0:
    return JS_EXCEPTION
  let this = newEmptyNodeList()
  for element in node.elementDescendants:
    if element.matchesImpl(selectors):
      this.snapshot.add(element)
  return ctx.toJS(this)

# Collection
proc populateCollection(this: Collection) =
  if this.root of ParentNode:
    let root = ParentNode(this.root)
    if this.childonly:
      for child in root.childList:
        if this.match == nil or this.match(this, child):
          this.snapshot.add(child)
    else:
      for desc in root.descendants:
        if this.match == nil or this.match(this, desc):
          this.snapshot.add(desc)

proc refreshCollection(this: Collection) =
  if this.invalid:
    assert this.document != nil
    this.snapshot.setLen(0)
    this.populateCollection()
    this.invalid = false

proc finalize0(collection: CollectionLike) =
  if collection.document != nil:
    let collection = cast[ptr CollectionLikeObj](collection)
    if collection.prev != nil:
      collection.prev.next = collection.next
    else:
      collection.document.liveCollectionsHead = collection.next
    if collection.next != nil:
      collection.next.prev = collection.prev

proc finalize(collection: HTMLCollection) {.jsfin.} =
  collection.finalize0()
  freeAtoms(collection.atoms)

proc finalize(collection: NodeList) {.jsfin.} =
  collection.finalize0()
  freeAtoms(collection.atoms)

proc finalize(rt: JSRuntime; this: NodeIterator) {.jsfin.} =
  this.finalize0()
  JS_FreeValueRT(rt, this.filter)

proc finalize(rt: JSRuntime; this: TreeWalker) {.jsfin.} =
  JS_FreeValueRT(rt, this.filter)

proc mark(rt: JSRuntime; this: NodeIterator; markFun: JS_MarkFunc) {.jsmark.} =
  JS_MarkValue(rt, this.filter, markFun)

proc finalize(collection: HTMLAllCollection) {.jsfin.} =
  collection.finalize0()
  freeAtoms(collection.atoms)

proc finalize(document: Document) {.jsfin.} =
  var it = document.liveCollectionsHead
  while it != nil:
    it.document = nil
    it = it.next

proc getLength(this: Collection): uint32 =
  this.refreshCollection()
  uint32(min(uint64(this.snapshot.len), uint32.high))

proc findNode(this: Collection; node: Node): int =
  this.refreshCollection()
  this.snapshot.find(node)

proc attachLiveCollection(root: Node; collection: CollectionLike) =
  let document = root.document
  if document.liveCollectionsHead != nil:
    document.liveCollectionsHead.prev = addr collection[]
    collection.next = document.liveCollectionsHead
  document.liveCollectionsHead = addr collection[]
  collection.document = addr document[]

proc newCollection[T: Collection](root: Node; match: CollectionMatchFun;
    islive, childonly: bool): T =
  let this = T(
    childonly: childonly,
    match: match,
    root: root,
    invalid: islive
  )
  if islive:
    root.attachLiveCollection(this)
  else:
    this.populateCollection()
  this

proc newEmptyNodeList(): NodeList =
  return NodeList(
    childonly: false,
    match: nil,
    document: nil
  )

proc newHTMLCollection(root: Node; match: CollectionMatchFun;
    islive, childonly: bool): HTMLCollection =
  newCollection[HTMLCollection](root, match, islive, childonly)

proc newNodeList(root: Node; match: CollectionMatchFun;
    islive, childonly: bool): NodeList =
  newCollection[NodeList](root, match, islive, childonly)

# Text
proc newText*(document: Document; data: string): Text =
  return Text(internalNext: document, data: newRefString(data))

proc newText(document: Document; data: DOMString): Text =
  return Text(internalNext: document, data: newRefString(data))

proc newText(ctx: JSContext; data = initDOMStringLit("")): Text {.jsctor.} =
  let window = ctx.getGlobal()
  return window.document.newText(data)

# CDATASection
proc newCDATASection(document: Document; data: RefString): CDATASection =
  return CDATASection(internalNext: document, data: data)

# ProcessingInstruction
proc newProcessingInstruction(document: Document; target: string;
    data: RefString): ProcessingInstruction =
  ProcessingInstruction(internalNext: document, target: target, data: data)

# Comment
proc newComment(document: Document; data: RefString): Comment =
  return Comment(internalNext: document, data: data)

proc newComment(ctx: JSContext; data = initDOMStringLit("")): Comment {.
    jsctor.} =
  let window = ctx.getWindow()
  return window.document.newComment(newRefString(data))

# DocumentFragment
proc getDocument(ctx: JSContext): Document =
  return ctx.getWindow().document

proc newDocumentFragment(document: Document): DocumentFragment =
  return DocumentFragment(internalNext: document)

proc newDocumentFragment(ctx: JSContext): DocumentFragment {.jsctor.} =
  let window = ctx.getGlobal()
  return window.document.newDocumentFragment()

proc firstElementChild(this: DocumentFragment): Element {.jsfget.} =
  return ParentNode(this).firstElementChild

proc lastElementChild(this: DocumentFragment): Element {.jsfget.} =
  return ParentNode(this).lastElementChild

proc childElementCount(this: DocumentFragment): uint32 {.jsfget.} =
  return this.childElementCountImpl

proc querySelector(ctx: JSContext; this: DocumentFragment; q: DOMString):
    JSValue {.jsfunc.} =
  return ctx.querySelectorImpl(this, q)

proc querySelectorAll(ctx: JSContext; this: DocumentFragment; q: DOMString):
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
    contentType: satApplicationXml,
    charset: csUtf8
  )
  document.implementation = DOMImplementation(document: document)
  return document

proc newDocument*(url: URL): Document =
  let document = Document(
    url: url,
    contentType: satApplicationXml,
    origin: url.origin,
    charset: csUtf8
  )
  document.implementation = DOMImplementation(document: document)
  return document

proc newDocument(ctx: JSContext): Document {.jsctor.} =
  let global = ctx.getWindow()
  let document = Document(
    url: parseURL0("about:blank"),
    contentType: satApplicationXml,
    origin: global.document.origin,
    charset: csUtf8
  )
  document.implementation = DOMImplementation(document: document)
  return document

proc newDocumentType*(document: Document; name, publicId, systemId: string):
    DocumentType =
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

proc globalCustomElements(document: Document): CustomElementRegistry =
  if document.customElements != nil and not document.customElements.scoped:
    return document.customElements
  nil

proc adopt(document: Document; node: Node; ctx: JSContext) =
  let oldDocument = node.document
  node.removeImpl()
  if oldDocument != document:
    # node is detached from the tree, so its internalNext is guaranteed to
    # be oldDocument; we want to override that.
    node.internalNext = document
    if node of ParentNode:
      let node = ParentNode(node)
      # The node document is already set, so we must update collections
      # before doing anything that might be observable.
      var collection = oldDocument.liveCollectionsHead
      while collection != nil:
        let next = collection.next
        if collection.root == node:
          collection.document = addr document[]
          collection.prev = nil
          collection.next = document.liveCollectionsHead
          if document.liveCollectionsHead != nil:
            document.liveCollectionsHead.prev = collection
          document.liveCollectionsHead = collection
        collection = next
      for desc in node.descendantsShadowIncl:
        if desc of ShadowRoot:
          let root = ShadowRoot(desc)
          if root.customElements == nil and not root.unsetCustomElements or
              root.customElements != nil and not root.customElements.scoped:
            root.customElements = document.globalCustomElements
        if node of Element:
          let element = Element(node)
          if ctx != nil and element.attrs.len > 0:
            let scriptAttrs = ctx.getWeakCollection(element, wwmAttributes)
            var attributes: NamedNodeMap
            discard ctx.fromJS(scriptAttrs, attributes)
            JS_FreeValue(ctx, scriptAttrs)
            if attributes != nil:
              for it in attributes.attrlist:
                it.internalNext = document
          #TODO custom element registry, img relevant mutations, adoptedCallback
          if element.tagType == TAG_TEMPLATE:
            document.adopt(HTMLTemplateElement(element).content, ctx)

proc addElementId0(document: Document; element: Element) =
  let mask = document.elementIdMap.len - 1
  var home = element.id.hash() and mask
  var i = home
  var element = element
  while true:
    let it = document.elementIdMap[i]
    if it == nil:
      document.elementIdMap[i] = element
      break
    # if either
    # * "it"'s id is closer to its home than element's id
    # * or if "it" has the same id as element, but element comes earlier
    # then swap out "it" for element.
    let ihash = it.id.hash()
    if tabSwap(home, ihash, i, mask) or
        it.id == element.id and element.precedes(it):
      swap(document.elementIdMap[i], element)
      home = ihash and mask
    i = (i + 1) and mask

proc addElementId(document: Document; element: Element) =
  let oldLoad = document.elementIdMapLoad
  for it in document.elementIdMap.prepareTableAdd(oldLoad, init = 32):
    if it != nil:
      document.addElementId0(it)
  inc document.elementIdMapLoad
  document.addElementId0(element)

proc removeElementId(document: Document; element: Element) =
  if document.elementIdMap.len == 0:
    return
  let mask = document.elementIdMap.len - 1
  var i = element.id.hash() and mask
  while true:
    let it = document.elementIdMap[i]
    if it == nil:
      return # not found
    if it == element:
      dec document.elementIdMapLoad
      document.elementIdMap[i] = nil
      break
    i = (i + 1) and mask
  var j = i
  while true:
    j = (j + 1) and mask
    let it = document.elementIdMap[j]
    if it == nil:
      break
    let k = it.id.hash() and mask
    if j == k: # already at home
      break
    # backwards shift
    document.elementIdMap[i] = move(document.elementIdMap[j])
    i = j

proc adoptNode(ctx: JSContext; document: Document; node: Node): JSValue
    {.jsfunc.} =
  if node of Document:
    return JS_ThrowDOMException(ctx, "NotSupportedError",
      "document nodes cannot be adopted")
  if node of ShadowRoot:
    return JS_ThrowDOMException(ctx, "HierarchyRequestError",
      "shadow root nodes cannot be adopted")
  document.adopt(node, ctx)
  return ctx.toJS(node)

proc compatMode(document: Document): string {.jsfget.} =
  if document.mode == QUIRKS:
    return "BackCompat"
  return "CSS1Compat"

proc forms(ctx: JSContext; document: Document): HTMLCollection {.jsfget.} =
  if document.cachedForms == nil:
    document.cachedForms = newHTMLCollection(
      document,
      match = isForm,
      islive = true,
      childonly = false
    )
  document.cachedForms

proc links(ctx: JSContext; document: Document): HTMLCollection {.jsfget.} =
  if document.cachedLinks == nil:
    document.cachedLinks = newHTMLCollection(
      document,
      match = isLink,
      islive = true,
      childonly = false
    )
  document.cachedLinks

proc images(ctx: JSContext; document: Document): HTMLCollection {.jsfget.} =
  if document.cachedImages == nil:
    document.cachedImages = newHTMLCollection(
      document,
      match = isImage,
      islive = true,
      childonly = false
    )
  document.cachedImages

proc getURL(ctx: JSContext; document: Document): JSValue {.
    jsfget: "URL", jsfget: "documentURI".} =
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
  if response.stream == nil:
    return JS_ThrowInternalError(ctx, "internal error in cookie getter")
  window.loader.resume(response)
  let cookie = response.stream.readAll()
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
  window.loader.close(response)
  ok()

proc focus*(document: Document): Element {.jsfget: "activeElement".} =
  return document.internalFocus

proc hasFocus(document: Document): bool {.jsfunc.} =
  document.internalFocus != nil

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

proc createCDATASection(ctx: JSContext; document: Document; data: DOMString):
    JSValue {.jsfunc.} =
  if not document.isxml:
    return JS_ThrowDOMException(ctx, "NotSupportedError",
      "CDATA sections are not supported in HTML")
  if "]]>" in data.toOpenArray():
    return JS_ThrowDOMException(ctx, "InvalidCharacterError",
      "CDATA sections may not contain the string ]]>")
  return ctx.toJS(newCDATASection(document, newRefString(data)))

proc createComment*(document: Document; data: string): Comment {.jsfunc.} =
  return newComment(document, newRefString(data))

proc createProcessingInstruction(ctx: JSContext; document: Document;
    target, data: DOMString): JSValue {.jsfunc.} =
  if not target.toOpenArray().matchNameProduction() or
      "?>" in data.toOpenArray():
    return JS_ThrowDOMException(ctx, "InvalidCharacterError",
      "invalid data for processing instruction")
  let pi = newProcessingInstruction(document, $target, newRefString(data))
  ctx.toJS(pi)

proc createEvent(ctx: JSContext; document: Document; atom: CAtomTraced):
    JSValue {.jsfunc.} =
  case atom.toStaticAtomLower()
  of satCustomevent:
    return ctx.toJS(ctx.newCustomEvent(satUempty.view()))
  of satEvent, satEvents, satHtmlevents, satSvgevents:
    return ctx.toJS(newEvent(satUempty, nil, bubbles = false,
      cancelable = false))
  of satUievent, satUievents:
    return ctx.toJS(newUIEvent(satUempty.view()))
  of satMouseevent, satMouseevents:
    return ctx.toJS(newMouseEvent(satUempty.view()))
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
    return JS_ThrowDOMException(ctx, "SyntaxError", "invalid URL")
  document.window.navigate(url)
  return JS_UNDEFINED

proc scriptingEnabled*(document: Document): bool =
  if document.window == nil:
    return false
  return document.window.settings.scripting != smFalse

proc findFirst*(document: Document; tagType: TagType): HTMLElement {.
    jsmfget("head", TAG_HEAD), jsmfget("body", TAG_BODY).} =
  for element in document.elementDescendants(tagType):
    return HTMLElement(element)
  nil

proc getElementById*(document: Document; id: CAtomTraced): Element =
  if id != satUempty and document.elementIdMap.len > 0:
    let mask = document.elementIdMap.len - 1
    var i = id.view().hash() and mask
    while true:
      let it = document.elementIdMap[i]
      if it == nil:
        break
      if it.id == id:
        return it
      i = (i + 1) and mask
  nil

proc getElementById(ctx: JSContext; document: Document; val: JSValueConst):
    JSValue {.jsfunc.} =
  let atom = JS_ValueToAtom(ctx, val)
  var id: CAtom
  let status = ctx.fromJSView(atom, id)
  JS_FreeAtom(ctx, atom)
  if status == fjErr:
    return JS_EXCEPTION
  if id == CAtomNull:
    return JS_NULL
  ctx.toJS(document.getElementById(id.view()))

proc getElementsByName(document: Document; name: CAtomTraced): NodeList
    {.jsfunc.} =
  if name == satUempty:
    return newEmptyNodeList()
  let this = newNodeList(
    document,
    proc(this: Collection; node: Node): bool =
      node of Element and Element(node).name == this.atoms[0],
    islive = true,
    childonly = false
  )
  this.atoms = @[name.dup()]
  this

proc getElementsByTagName(document: Document; tagName: CAtomTraced):
    HTMLCollection {.jsfunc.} =
  return getElementsByTagNameImpl(document, tagName)

proc getElementsByClassName(document: Document; classNames: DOMString):
    HTMLCollection {.jsfunc.} =
  return getElementsByClassNameImpl(document, classNames)

proc children(ctx: JSContext; parentNode: Document): JSValue {.jsfget.} =
  return childrenImpl(ctx, parentNode)

proc querySelector(ctx: JSContext; this: Document; q: DOMString): JSValue
    {.jsfunc.} =
  return ctx.querySelectorImpl(this, q)

proc querySelectorAll(ctx: JSContext; this: Document; q: DOMString): JSValue
    {.jsfunc.} =
  return ctx.querySelectorAllImpl(this, q)

proc validateName(ctx: JSContext; name: openArray[char]): Opt[void] =
  if not name.matchNameProduction():
    JS_ThrowDOMException(ctx, "InvalidCharacterError",
      "invalid character in name")
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

proc setTitle(ctx: JSContext; document: Document; ds: DOMString) {.
    jsfset: "title".} =
  var title = document.findFirst(TAG_TITLE)
  if title == nil:
    let head = document.findFirst(TAG_HEAD)
    if head == nil:
      return
    title = document.newHTMLElement(TAG_TITLE)
    head.append(title, ctx)
  title.replaceAll(ds, ctx)

proc invalidateCollections(document: Document) =
  var collection = document.liveCollectionsHead
  while collection != nil:
    if collection of Collection:
      cast[Collection](collection).invalid = true
    collection = collection.next

proc invalidateCollectionsRemove(document: Document; node: Node) =
  # node will be removed
  var collection = document.liveCollectionsHead
  while collection != nil:
    if cast[CollectionLike](collection) of NodeIterator:
      cast[NodeIterator](collection).adjustForRemoval(node)
    elif cast[CollectionLike](collection) of Collection:
      cast[Collection](collection).invalid = true
    collection = collection.next

proc isValidCustomElementName(atom: CAtomTraced): bool =
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

proc isValidElementName(s: openArray[char]): bool =
  if s.len <= 0:
    return false
  let c = s[0]
  if c in AsciiAlpha:
    return AsciiWhitespace + {'\0', '/', '>'} notin s
  if c in AsciiDigit + {'-', '.'}:
    return false
  return Ascii - AsciiAlphaNumeric - {'-', '.', ':', '_'} notin s

#TODO options/custom elements
proc createElement(ctx: JSContext; document: Document; localName: DOMString):
    JSValue {.jsfunc.} =
  if not isValidElementName(localName.toOpenArray()):
    return JS_ThrowDOMException(ctx, "InvalidCharacterError",
      "invalid local name")
  let localName = if not document.isxml:
    localName.toAtomLowerTrace()
  else:
    localName.toAtomTrace()
  let namespace = if not document.isxml:
    #TODO or content type is application/xhtml+xml
    satNamespaceHTML
  else:
    satUempty
  ctx.toJS(document.newElement(localName, namespace))

proc isValidAttributeName(s: string): bool =
  const AttrDisallowed = AsciiWhitespace + {'\0', '/', '=', '>'}
  s.len > 0 and AttrDisallowed notin s

type NameValidator = enum
  nvAttribute, nvElement

# localName must be set to the qualified name before the call
proc validateAndExtract(ctx: JSContext; namespace, localName: var CAtomTraced;
    t: NameValidator): Opt[void] =
  if namespace == satUempty:
    namespace = CAtomNull.dupTrace()
  var prefix = CAtomNull.dupTrace()
  let i = localName.find(':')
  if i >= 0:
    prefix = localName.substrTrace(0, i - 1)
    localName = localName.substrTrace(i + 1)
    if prefix == satUempty or AsciiWhitespace + {'\0', '/', '>'} in prefix:
      JS_ThrowDOMException(ctx, "InvalidCharacterError", "invalid prefix")
      return err()
  let nameOk = case t
  of nvAttribute:
    isValidAttributeName($localName)
  of nvElement:
    isValidElementName($localName)
  if not nameOk:
    JS_ThrowDOMException(ctx, "InvalidCharacterError", "invalid local name")
    return err()
  let sns = namespace.toStaticAtom()
  let isXmlns = prefix == satXmlns or
    prefix == CAtomNull and localName == satXmlns
  if namespace == CAtomNull and prefix != satUempty or
      prefix == satXml and sns != satNamespaceXML or
      isXmlns != (sns == satNamespaceXMLNS):
    JS_ThrowDOMException(ctx, "NamespaceError", "unexpected namespace")
    return err()
  ok()

proc createElementNS(ctx: JSContext; document: Document;
    namespace: CAtomTraced; qualifiedName: CAtomTraced): Opt[Element] {.
    jsfunc.} =
  var namespace = namespace.dupTrace()
  var localName = qualifiedName.dupTrace()
  ?ctx.validateAndExtract(namespace, localName, nvElement)
  #TODO custom elements (is)
  ok(document.newElement(localName, namespace, qualifiedName))

proc createDocumentFragment(document: Document): DocumentFragment {.jsfunc.} =
  return newDocumentFragment(document)

proc createDocumentType(ctx: JSContext; implementation: DOMImplementation;
    qualifiedName, publicId, systemId: DOMString): JSValue {.jsfunc.} =
  if AsciiWhitespace + {'\0', '>'} in qualifiedName.toOpenArray():
    return JS_ThrowDOMException(ctx, "InvalidCharacterError",
      "invalid character in qualified name")
  let document = implementation.document
  ctx.toJS(document.newDocumentType($qualifiedName, $publicId, $systemId))

proc createDocument(ctx: JSContext; implementation: DOMImplementation;
    namespace: CAtomTraced; qualifiedName: DOMStringNull;
    doctype = none(DocumentType)): Opt[XMLDocument] {.jsfunc.} =
  let document = newXMLDocument()
  let qualifiedName = qualifiedName.toAtomTrace()
  let element = if qualifiedName != satUempty:
    ?ctx.createElementNS(document, namespace, qualifiedName)
  else:
    nil
  if doctype.isSome:
    document.append(doctype.get, ctx)
  if element != nil:
    document.append(element, ctx)
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
  doc.append(doc.newDocumentType("html", "", ""), ctx)
  let html = doc.newHTMLElement(TAG_HTML)
  doc.append(html, ctx)
  let head = doc.newHTMLElement(TAG_HEAD)
  html.append(head, ctx)
  if not JS_IsUndefined(title):
    var ds: DOMString
    ?ctx.fromJS(title, ds)
    let titleElement = doc.newHTMLElement(TAG_TITLE)
    titleElement.append(doc.newText(ds), ctx)
    head.append(titleElement, ctx)
  html.append(doc.newHTMLElement(TAG_BODY), ctx)
  doc.origin = implementation.document.origin
  ok(doc)

proc hasFeature(implementation: DOMImplementation): bool {.jsfunc.} =
  return true

proc createTextNode(document: Document; data: DOMString): Text {.jsfunc.} =
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
    ptr HTMLElement.pointerBase =
  let rtOpaque = JS_GetRuntime(ctx).getOpaque()
  let magic = uint16(magic)
  let myClass = JS_GetClassID(this)
  let parent = rtOpaque.classes[myClass].parent
  let class = JSClassID(magic shr 9) + parent
  if class != parent and class != myClass:
    JS_ThrowTypeError(ctx, "invalid tag type")
    return nil
  var element: ptr HTMLElement.pointerBase
  if ctx.fromJS(this, element).isErr:
    return nil
  return element

proc jsReflectGet0(ctx: JSContext; element: HTMLElement; magic: cint):
    JSValue =
  let entry = ReflectMap[uint16(magic) and 0x1FF]
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
  of rtForm: return ctx.toJS(FormAssociatedElement(element).form)
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

proc jsReflectSet0(ctx: JSContext; element: HTMLElement; val: JSValueConst;
    magic: cint): JSValue {.cdecl.} =
  let entry = ReflectMap[uint16(magic) and 0x1FF]
  case entry.t
  of rtStr, rtUrl, rtReferrerPolicy, rtMethod:
    var x: DOMString
    ?ctx.fromJS(val, x)
    element.attr(entry.attrname, x)
  of rtCrossOrigin:
    if JS_IsNull(val):
      let i = element.findAttr(entry.attrname.view())
      if i != -1:
        ctx.delAttr(element, i)
    else:
      var x: DOMString
      ?ctx.fromJS(val, x)
      element.attr(entry.attrname, x)
  of rtBool:
    var x: bool
    ?ctx.fromJS(val, x)
    if x:
      element.attr(entry.attrname, "")
    else:
      let i = element.findAttr(entry.attrname.view())
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
  of rtForm: discard
  return JS_DupValue(ctx, val)

proc jsReflectGet(ctx: JSContext; this: JSValueConst; magic: cint): JSValue
    {.cdecl.} =
  let element = ctx.getReflectElement(this, magic)
  if element == nil:
    return JS_EXCEPTION
  ctx.jsReflectGet0(cast[HTMLElement](element), magic)

proc jsReflectSet(ctx: JSContext; this, val: JSValueConst; magic: cint):
    JSValue {.cdecl.} =
  let element = ctx.getReflectElement(this, magic)
  if element == nil:
    return JS_EXCEPTION
  ctx.jsReflectSet0(cast[HTMLElement](element), val, magic)

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
    let map = newCSSRuleMap(document.mode == QUIRKS)
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

proc getComputedMap*(document: Document): CSSValuesMap =
  if document.computedMap == nil:
    document.computedMap = CSSValuesMap()
  document.computedMap

proc findAnchor*(document: Document; id: string): Element =
  if id.len == 0:
    return nil
  let id = id.toAtomTrace()
  for child in document.elementDescendants:
    if child.id == id:
      return child
    if child.tagType == TAG_A and child.name == id:
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
    var s: DOMString
    if ctx.fromJS(arg, s).isErr:
      return JS_EXCEPTION
    text &= s.toOpenArray()
  # Note: this diverges from behavior in other browsers, but I'm not
  # convinced that modifying the parser to adjust for this edge case is
  # worth the trouble.
  text.replaceSurrogates()
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

proc childElementCount(this: Document): uint32 {.jsfget.} =
  return this.childElementCountImpl

proc doctype(document: Document): DocumentType {.jsfget.} =
  let first = document.firstChild
  if first of DocumentType:
    return DocumentType(first)
  nil

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
    if child.name != satUempty:
      if child.tagType == TAG_IMG and child.id != satUempty:
        list.add($child.id)
      list.add($child.name)
  return list

proc getter(ctx: JSContext; document: Document; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var id: CAtom
  ?ctx.fromJSView(atom, id)
  if id != CAtomNull and id != satUempty:
    #TODO exposed embed, exposed object
    for child in document.elementDescendants({TAG_FORM, TAG_IFRAME, TAG_IMG}):
      if child.tagType == TAG_IMG and child.id == id and
          child.name != satUempty:
        return ctx.toJS(child)
      if child.name == id:
        return ctx.toJS(child)
  return JS_UNINITIALIZED

proc fullscreen(document: Document): bool {.
    jsfget, jsfget: "fullscreenEnabled".} =
  false

# "lenient setter"
proc setFullscreen(document: Document; b: bool) {.
    jsfset: "fullscreen", jsfset: "fullscreenEnabled".} =
  discard

proc fullscreenElement(document: Document): JSValue {.jsfget.} =
  return JS_NULL

proc exitFullscreen(ctx: JSContext; document: Document): JSValue {.jsfunc.} =
  JS_ThrowTypeError(ctx, "fullscreen is not supported")
  return ctx.newRejectedPromise()

# DocumentType
proc before(ctx: JSContext; this: DocumentType; nodes: varargs[JSValueConst]):
    Opt[void] {.jsfunc.} =
  ctx.beforeImpl(this, nodes)

proc after(ctx: JSContext; this: DocumentType; nodes: varargs[JSValueConst]):
    Opt[void] {.jsfunc.} =
  ctx.afterImpl(this, nodes)

proc replaceWith(ctx: JSContext; this: DocumentType;
    nodes: varargs[JSValueConst]): JSValue {.jsfunc.} =
  ctx.replaceWithImpl(this, nodes)

proc remove(this: DocumentType) {.jsfunc.} =
  this.removeImpl()

# NodeIterator
proc createNodeIterator(ctx: JSContext; document: Document; root: Node;
    whatToShow = 0xFFFFFFFFu32; filter: JSValueConst = JS_NULL):
    JSValue {.jsfunc.} =
  if not JS_IsObject(filter) and not JS_IsNull(filter):
    return JS_ThrowTypeError(ctx, "filter is not an object")
  let this = NodeIterator(
    root: root,
    referenceNode: root,
    iterNode: root,
    whatToShow: whatToShow,
    filter: JS_DupValue(ctx, filter),
    before: true
  )
  root.attachLiveCollection(this)
  ctx.toJS(this)

proc jsRoot(this: NodeIterator): Node {.jsfget: "root".} =
  this.root

proc jsWhatToShow(this: NodeIterator): uint32 {.jsfget: "whatToShow".} =
  this.whatToShow

proc jsFilter(ctx: JSContext; this: NodeIterator): JSValue {.
    jsfget: "filter".} =
  JS_DupValue(ctx, this.filter)

proc filter(ctx: JSContext; this: NodeIteratorLike; node: Node): Opt[uint32] =
  if this.active:
    JS_ThrowDOMException(ctx, "InvalidStateError", "nested filter call")
    return err()
  let n = 1u32 shl (uint32(node.nodeType) - 1)
  if (this.whatToShow and n) == 0:
    return ok(uint32(nfrSkip))
  if JS_IsNull(this.filter):
    return ok(uint32(nfrAccept))
  let filter = this.filter
  let node = ctx.toJS(node)
  if JS_IsException(node):
    return err()
  this.active = true
  #TODO call user object's operation (prepare etc.)
  let val = if JS_IsFunction(ctx, filter):
    ctx.callSink(filter, JS_UNDEFINED, node)
  else:
    let atom = JS_NewAtom(ctx, cstringConst"acceptNode")
    let val = ctx.invokeSink(filter, atom, node)
    JS_FreeAtom(ctx, atom)
    val
  if JS_IsException(val):
    this.active = false
    return err()
  var res: uint32
  let status = ctx.fromJSFree(val, res)
  this.active = false
  if status.isErr:
    return err()
  ok(res)

proc traverse(ctx: JSContext; this: NodeIterator; next: bool): Opt[Node] {.
    jsmfunc("previousNode", false), jsmfunc("nextNode", true).} =
  this.iterNode = this.referenceNode
  this.iterBefore = this.before
  while true:
    if this.iterBefore == next:
      this.iterBefore = not next
    else:
      this.iterNode = if next:
        this.iterNode.nextDescendant(this.root)
      else:
        this.iterNode.previousDescendant(this.root)
      if this.iterNode == nil:
        return ok(nil)
    let res = ctx.filter(this, this.iterNode)
    if res.isErr:
      this.iterNode = nil
      return err()
    if res.get == uint32(nfrAccept):
      break
  this.referenceNode = this.iterNode
  this.before = this.iterBefore
  ok(move(this.iterNode))

proc detach(this: NodeIterator) {.jsfunc.} =
  discard

proc adjustForRemovalImpl(iter: NodeIterator; node: Node;
    referenceNode: var Node; before: var bool) =
  if not node.contains(iter.root) and node.contains(referenceNode):
    if before:
      let next = node.nextDescendant(iter.root, skip = true)
      if next != nil:
        referenceNode = next
        return
      before = false
    referenceNode = node.previousDescendant(iter.root)

proc adjustForRemoval(iter: NodeIterator; node: Node) =
  iter.adjustForRemovalImpl(node, iter.referenceNode, iter.before)
  if iter.iterNode != nil:
    iter.adjustForRemovalImpl(node, iter.iterNode, iter.iterBefore)

# TreeWalker
proc createTreeWalker(ctx: JSContext; document: Document; root: Node;
    whatToShow = 0xFFFFFFFFu32; filter: JSValueConst = JS_NULL):
    JSValue {.jsfunc.} =
  if not JS_IsObject(filter) and not JS_IsNull(filter):
    return JS_ThrowTypeError(ctx, "filter is not an object")
  ctx.toJS(TreeWalker(
    root: root,
    currentNode: root,
    whatToShow: whatToShow,
    filter: JS_DupValue(ctx, filter)
  ))

proc jsRoot(this: TreeWalker): Node {.jsfget: "root".} =
  this.root

proc jsWhatToShow(this: TreeWalker): uint32 {.jsfget: "whatToShow".} =
  this.whatToShow

proc jsFilter(ctx: JSContext; this: TreeWalker): JSValue {.jsfget: "filter".} =
  JS_DupValue(ctx, this.filter)

proc parentNode(ctx: JSContext; this: TreeWalker): Opt[Node] {.jsfunc.} =
  var node = this.currentNode
  while node != nil and node != this.root:
    node = node.parentNode
    if node != nil and ?ctx.filter(this, node) == uint32(nfrAccept):
      this.currentNode = node
      return ok(node)
  ok(nil)

proc traverse(ctx: JSContext; this: TreeWalker; last: bool): Opt[Node] {.
    jsmfunc("firstChild", false), jsmfunc("lastChild", true).} =
  let currentNode = this.currentNode
  var node = if last: currentNode.lastChild else: currentNode.firstChild
  while node != nil:
    let res = ?ctx.filter(this, node)
    if res == uint32(nfrAccept):
      this.currentNode = node
      return ok(node)
    if res == uint32(nfrSkip):
      let child = if last: node.lastChild else: node.firstChild
      if child != nil:
        node = child
        continue
    while node != nil:
      let sibling = if last: node.previousSibling else: node.nextSibling
      if sibling != nil:
        node = sibling
        break
      let parent = Node(node.parentNode)
      if parent == this.root or parent == currentNode:
        node = nil
      else:
        node = parent
  ok(nil)

proc traverseSibling(ctx: JSContext; this: TreeWalker; next: bool): Opt[Node]
    {.jsmfunc("previousSibling", false), jsmfunc("nextSibling", true).} =
  var node = this.currentNode
  if node != this.root:
    while true:
      var sibling = if next: node.nextSibling else: node.previousSibling
      while sibling != nil:
        node = sibling
        let res = ?ctx.filter(this, node)
        if res == uint32(nfrAccept):
          this.currentNode = node
          return ok(node)
        sibling = if next: node.firstChild else: node.lastChild
        if res == uint32(nfrReject) or sibling == nil:
          sibling = if next: node.nextSibling else: node.previousSibling
      node = node.parentNode
      if node == this.root or node == nil or
          ?ctx.filter(this, node) == uint32(nfrAccept):
        return ok(nil)
  ok(nil)

proc nextNode(ctx: JSContext; this: TreeWalker): Opt[Node] {.jsfunc.} =
  var node = this.currentNode.nextDescendant(this.root)
  while node != nil:
    let res = ?ctx.filter(this, node)
    if res == uint32(nfrAccept):
      this.currentNode = node
      return ok(node)
    let skip = res == uint32(nfrReject)
    node = node.nextDescendant(this.root, skip)
  ok(nil)

proc previousNode(ctx: JSContext; this: TreeWalker): Opt[Node] {.jsfunc.} =
  var node = this.currentNode
  while node != this.root:
    while (let sibling = node.previousSibling; sibling != nil):
      node = sibling
      var res = ?ctx.filter(this, node)
      while res != uint32(nfrReject):
        let last = node.lastChild
        if last == nil:
          break
        res = ?ctx.filter(this, last)
        node = last
      if res == uint32(nfrAccept):
        this.currentNode = node
        return ok(node)
    let parent = node.parentNode
    if node == this.root or parent == nil:
      return ok(nil)
    node = parent
    if ?ctx.filter(this, node) == uint32(nfrAccept):
      this.currentNode = node
      return ok(node)
  ok(nil)

# DOMTokenList
proc newDOMTokenList(element: Element; name: StaticAtom): DOMTokenList =
  return DOMTokenList(element: element, localName: name)

proc finalize(tokenList: DOMTokenList) {.jsfin.} =
  freeAtoms(tokenList.toks)

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

proc containsIgnoreCase(tokenList: DOMTokenList; a: StaticAtom): bool =
  return tokenList.toks.containsIgnoreCase(a)

proc contains(tokenList: DOMTokenList; s: CAtomTraced): bool {.jsfunc.} =
  return s in tokenList.toks

proc `$`(tokenList: DOMTokenList): string {.jsfunc: "toString",
    jsfget: "value".} =
  var s = ""
  for i, tok in tokenList.toks:
    if i != 0:
      s &= ' '
    s &= $tok
  move(s)

proc update(tokenList: DOMTokenList) =
  if tokenList.element.attrb(tokenList.localName.view()) or
      tokenList.toks.len > 0:
    tokenList.element.attr(tokenList.localName.view(), $tokenList)

proc validateDOMTokens(ctx: JSContext; toks: varargs[CAtom]): Opt[void] =
  for tok in toks:
    if tok == satUempty:
      JS_ThrowDOMException(ctx, "SyntaxError", "got an empty string")
      return err()
    if AsciiWhitespace in tok:
      JS_ThrowDOMException(ctx, "InvalidCharacterError",
        "got a string containing whitespace")
      return err()
  ok()

proc add(ctx: JSContext; tokenList: DOMTokenList;
    argv: varargs[JSValueConst]): Opt[void] {.jsfunc.} =
  var toks: seq[CAtom]
  ?ctx.fromJS(argv, toks)
  if ctx.validateDOMTokens(toks).isErr:
    freeAtoms(toks)
    return err()
  tokenList.toks.add(toks)
  tokenList.update()
  ok()

proc remove(ctx: JSContext; tokenList: DOMTokenList;
    argv: varargs[JSValueConst]): Opt[void] {.jsfunc.} =
  var toks: seq[CAtom]
  ?ctx.fromJS(argv, toks)
  if ctx.validateDOMTokens(toks).isErr:
    freeAtoms(toks)
    return err()
  for tok in toks:
    let i = tokenList.toks.find(tok)
    if i != -1:
      tokenList.toks.delete(i)
  tokenList.update()
  freeAtoms(toks)
  ok()

proc toggle(ctx: JSContext; tokenList: DOMTokenList; token: CAtomTraced;
    force: JSValueConst = JS_UNDEFINED): Opt[bool] {.jsfunc.} =
  ?ctx.validateDOMTokens(token.view())
  let forceBool = JS_ToBool(ctx, force)
  if forceBool < 0:
    return err()
  let i = tokenList.toks.find(token.view())
  if i != -1:
    if JS_IsUndefined(force) or forceBool == 0:
      tokenList.toks.delete(i)
      tokenList.update()
      return ok(false)
    return ok(true)
  if JS_IsUndefined(force) or forceBool == 1:
    tokenList.toks.add(token.dup())
    tokenList.update()
    return ok(true)
  ok(false)

proc replace(ctx: JSContext; tokenList: DOMTokenList;
    token, newToken: CAtomTraced): Opt[bool] {.jsfunc.} =
  ?ctx.validateDOMTokens(token.view(), newToken.view())
  let i = tokenList.toks.find(token.view())
  if i == -1:
    return ok(false)
  freeAtom(tokenList.toks[i])
  tokenList.toks[i] = newToken.dup()
  tokenList.update()
  return ok(true)

proc supports(ctx: JSContext; tokenList: DOMTokenList; token: DOMString):
    JSValue {.jsfunc.} =
  case tokenList.localName
  of satRel:
    const SupportedTokens = [satAlternate, satStylesheet]
    let lower = token.toOpenArray().toLowerAscii()
    return ctx.toJS(lower.toStaticAtom() in SupportedTokens)
  else:
    return JS_ThrowTypeError(ctx, "no supported tokens defined for attribute")

proc getter(ctx: JSContext; this: DOMTokenList; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  case ctx.fromIdx(atom, u)
  of fiIdx: ctx.item(this, u).uninitIfNull()
  of fiStr: JS_UNINITIALIZED
  of fiErr: JS_EXCEPTION

proc reflectTokens(this: DOMTokenList; value: string) =
  this.toks.setLen(0)
  for x in value.split(AsciiWhitespace):
    if x != "":
      let a = x.toAtomTrace()
      if a notin this:
        this.toks.add(a.dup())

# DOMStringMap
proc toDataStr(name: DOMString): CAtomTraced =
  let s = "data-" & name.toOpenArray().camelToKebabCase()
  s.toAtomTrace()

proc delete(ctx: JSContext; map: DOMStringMap; name: DOMString): bool {.
    jsfunc.} =
  let name = name.toDataStr()
  let i = map.target.findAttr(name)
  if i != -1:
    ctx.delAttr(map.target, i)
  return i != -1

proc getter(ctx: JSContext; map: DOMStringMap; name: DOMString): JSValue
    {.jsgetownprop.} =
  let name = name.toDataStr()
  let i = map.target.findAttr(name)
  if i != -1:
    return ctx.toJS(map.target.attrs[i].value)
  return JS_UNINITIALIZED

proc setter(ctx: JSContext; map: DOMStringMap; name, value: DOMString):
    Opt[void] {.jssetprop.} =
  var washy = false
  for c in name.toOpenArray():
    if not washy or c notin AsciiLowerAlpha:
      washy = c == '-'
      continue
    JS_ThrowDOMException(ctx, "InvalidCharacterError",
      "lower case after hyphen is not allowed in dataset")
    return err()
  let name = name.toDataStr()
  ?ctx.validateName($name)
  map.target.attr(name, value)
  ok()

proc names(ctx: JSContext; map: DOMStringMap): JSPropertyEnumList
    {.jspropnames.} =
  var list = newJSPropertyEnumList(ctx, uint32(map.target.attrs.len))
  for attr in map.target.attrs:
    let k = $attr.qualifiedName
    if k.startsWith("data-") and AsciiUpperAlpha notin k:
      list.add(k["data-".len .. ^1].kebabToCamelCase())
  return list

# NodeList
proc length(this: NodeList): uint32 {.jsfget.} =
  return this.getLength()

proc item(ctx: JSContext; this: NodeList; u: uint32): Node {.jsfunc.} =
  if u < this.getLength():
    return this.snapshot[u]
  nil

proc getter(ctx: JSContext; this: NodeList; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  case ctx.fromIdx(atom, u)
  of fiIdx: ctx.toJS(ctx.item(this, u)).uninitIfNull()
  of fiStr: JS_UNINITIALIZED
  of fiErr: JS_EXCEPTION

proc names(ctx: JSContext; this: NodeList): JSPropertyEnumList {.jspropnames.} =
  let L = this.getLength()
  var list = newJSPropertyEnumList(ctx, L)
  for u in 0 ..< L:
    list.add(u)
  return list

# HTMLCollection
proc length(this: HTMLCollection): uint32 {.jsfget.} =
  return this.getLength()

proc item(this: HTMLCollection; u: uint32): Element {.jsfunc.} =
  if u < this.getLength():
    return Element(this.snapshot[int(u)])
  nil

proc namedItem(this: HTMLCollection; atom: CAtomTraced): Element {.jsfunc.} =
  this.refreshCollection()
  for it in this.snapshot:
    let it = Element(it)
    if it.id == atom or it.namespaceURI == satNamespaceHTML and it.name == atom:
      return it
  nil

proc getter(ctx: JSContext; this: HTMLCollection; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  var s: CAtomTraced
  case ctx.fromIdx(atom, u, s)
  of fiIdx: ctx.toJS(this.item(u)).uninitIfNull()
  of fiStr: ctx.toJS(this.namedItem(s)).uninitIfNull()
  of fiErr: JS_EXCEPTION

proc names(ctx: JSContext; this: HTMLCollection): JSPropertyEnumList
    {.jspropnames.} =
  let L = this.getLength()
  var list = newJSPropertyEnumList(ctx, L)
  var ids = initOrderedSet[CAtom]()
  for u in 0 ..< L:
    list.add(u)
    let element = this.item(u)
    if element == nil:
      continue
    if element.id != satUempty:
      ids.incl(element.id)
    if element.namespaceURI == satNamespaceHTML and
        element.name != satUempty:
      ids.incl(element.name)
  for id in ids:
    list.add($id)
  return list

# HTMLFormControlsCollection
proc namedItem(ctx: JSContext; this: HTMLFormControlsCollection;
    name: CAtomTraced): JSValue {.jsfunc.} =
  let nodes = newCollection[RadioNodeList](
    this.root,
    proc(this: Collection; node: Node): bool =
      let this = RadioNodeList(this)
      if not this.parent.match(this.parent, node):
        return false
      let element = Element(node)
      let name = this.atoms[0]
      element.id == name or
        element.namespaceURI == satNamespaceHTML and element.name == name,
    islive = true,
    childonly = false
  )
  nodes.parent = this
  nodes.atoms = @[name.dup()]
  let len = nodes.getLength()
  if len == 0:
    return JS_NULL
  if len == 1:
    return ctx.toJS(nodes.snapshot[0])
  return ctx.toJS(nodes)

proc names(ctx: JSContext; this: HTMLFormControlsCollection): JSPropertyEnumList
    {.jspropnames.} =
  return ctx.names(HTMLCollection(this))

proc getter(ctx: JSContext; this: HTMLFormControlsCollection; atom: JSAtom):
    JSValue {.jsgetownprop.} =
  var u: uint32
  var s: CAtomTraced
  case ctx.fromIdx(atom, u, s)
  of fiIdx: ctx.toJS(this.item(u)).uninitIfNull()
  of fiStr: ctx.namedItem(this, s).uninitIfNull()
  of fiErr: JS_EXCEPTION

# HTMLAllCollection
proc length(this: HTMLAllCollection): uint32 {.jsfget.} =
  this.getLength()

proc item(this: HTMLAllCollection; u: uint32): Element {.jsfunc.} =
  if u < this.getLength():
    return Element(this.snapshot[u])
  nil

proc getter(ctx: JSContext; this: HTMLAllCollection; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  case ctx.fromIdx(atom, u)
  of fiIdx: ctx.toJS(this.item(u)).uninitIfNull()
  of fiStr: JS_UNINITIALIZED
  of fiErr: JS_EXCEPTION

proc names(ctx: JSContext; this: HTMLAllCollection): JSPropertyEnumList
    {.jspropnames.} =
  let L = this.getLength()
  var list = newJSPropertyEnumList(ctx, L)
  for u in 0 ..< L:
    list.add(u)
  return list

proc all(ctx: JSContext; document: Document): JSValue {.jsfget.} =
  if document.cachedAll == nil:
    let res = newCollection[HTMLAllCollection](
      root = document,
      match = isElement,
      islive = true,
      childonly = false
    )
    document.cachedAll = res
    let val = ctx.toJS(res)
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

#TODO CORS (SecurityError)
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

proc protocol(ctx: JSContext; location: Location): JSValue {.jsuffget.} =
  return ctx.protocol(location.url)

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
  let namespace = attr.data.namespace.dup()
  let qualifiedName = attr.data.qualifiedName.dupTrace()
  if namespace == CAtomNull: # no namespace -> qualifiedName == localName
    attr.prefix = CAtomNull
    attr.localName = qualifiedName.dup()
  else: # namespace -> qualifiedName == prefix & ':' & localName
    let prefixs = ($qualifiedName).until(':')
    let prefixLen = prefixs.len
    attr.prefix = prefixs.toAtom()
    attr.localName = qualifiedName.view().substr(prefixLen + 1)
  return attr

proc finalize(attr: Attr) {.jsfin.} =
  freeAtom(attr.prefix)
  freeAtom(attr.localName)

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

proc setValue(attr: Attr; ds: DOMString) {.jsfset: "value".} =
  attr.ownerElement.attr(attr.data.qualifiedName.view(), ds)

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

proc getNamedItem(map: NamedNodeMap; qualifiedName: CAtomTraced): Attr {.
    jsfunc.} =
  let i = map.element.findAttr(qualifiedName)
  if i != -1:
    return map.getAttr(i)
  return nil

proc getNamedItemNS(map: NamedNodeMap; namespace, localName: CAtomTraced): Attr
    {.jsfunc.} =
  let i = map.element.findAttrNS(namespace, localName)
  if i != -1:
    return map.getAttr(i)
  return nil

proc length(map: NamedNodeMap): uint32 {.jsfget.} =
  return uint32(map.element.attrs.len)

proc item(map: NamedNodeMap; u: uint32): Attr {.jsfunc.} =
  if int64(u) < int64(map.element.attrs.len):
    return map.getAttr(int(u))
  return nil

proc getter(ctx: JSContext; this: NamedNodeMap; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  var s: CAtomTraced
  case ctx.fromIdx(atom, u, s)
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
    if element.namespaceURI == satNamespaceHTML and AsciiUpperAlpha in name:
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

proc before(ctx: JSContext; this: CharacterData; nodes: varargs[JSValueConst]):
    Opt[void] {.jsfunc.} =
  ctx.beforeImpl(this, nodes)

proc after(ctx: JSContext; this: CharacterData; nodes: varargs[JSValueConst]):
    Opt[void] {.jsfunc.} =
  ctx.afterImpl(this, nodes)

proc replaceWith(ctx: JSContext; this: CharacterData;
    nodes: varargs[JSValueConst]): JSValue {.jsfunc.} =
  ctx.replaceWithImpl(this, nodes)

proc remove*(this: CharacterData) {.jsfunc.} =
  this.removeImpl()

# Element
proc freeAttr(data: AttrData) =
  freeAtom(data.qualifiedName)
  freeAtom(data.namespace)

proc finalize(element: Element) {.jsfin.} =
  freeAtom(element.namespaceURI)
  freeAtom(element.localName)
  freeAtom(element.tagName)
  freeAtom(element.id)
  freeAtom(element.name)
  for it in element.attrs:
    freeAttr(it)

proc dupAttrs(element: Element): seq[AttrData] =
  result = newSeqOfCap[AttrData](element.attrs.len)
  for attr in element.attrs:
    result.add(AttrData(
      qualifiedName: attr.qualifiedName.dup(),
      namespace: attr.namespace.dup(),
      value: attr.value
    ))

proc deleteAttr(element: Element; i: int) =
  freeAttr(element.attrs[i])
  element.attrs.delete(i)

proc hash(element: Element): Hash =
  return hash(cast[pointer](element))

proc firstElementChild(this: Element): Element {.jsfget.} =
  return ParentNode(this).firstElementChild

proc lastElementChild(this: Element): Element {.jsfget.} =
  return ParentNode(this).lastElementChild

proc childElementCount(this: Element): uint32 {.jsfget.} =
  return this.childElementCountImpl

proc isFirstVisualNode*(element: Element): bool =
  let parent = element.parentNode
  if parent != nil and element.elIndex == 0:
    for child in parent.childList:
      if child == element:
        return true
      if child of Text and not Text(child).data.s.onlyWhitespace():
        break
  return false

proc isLastVisualNode*(element: Element): bool =
  let parent = element.parentNode
  if parent != nil:
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
  return element.serializeFragment(writeShadow = true)

proc outerHTML(element: Element): string {.jsfget.} =
  #TODO xml
  result = ""
  result.serializeFragmentInner(element, TAG_UNKNOWN, writeShadow = true)

proc tagTypeNoNS(element: Element): TagType =
  return element.localName.toTagType()

proc tagType*(element: Element; namespace = satNamespaceHTML): TagType =
  if element.namespaceURI != namespace:
    return TAG_UNKNOWN
  return element.tagTypeNoNS

proc prefix(element: Element): string {.jsfget.} =
  let i = element.tagName.find(':')
  if i < 0:
    return ""
  return ($element.tagName).substr(0, i - 1)

proc jsTagName(ctx: JSContext; element: Element): JSValue {.
    jsfget: "tagName".} =
  if element.namespaceURI == satNamespaceHTML:
    return ctx.toJS(($element.tagName).toUpperAscii())
  return ctx.toJS(element.tagName)

proc normalizeAttrQName(element: Element; qualifiedName: CAtomTraced):
    CAtomTraced =
  if element.namespaceURI == satNamespaceHTML and not element.document.isxml:
    return qualifiedName.toLowerAscii()
  return qualifiedName.dupTrace()

proc cmpAttrName(a: AttrData; b: CAtomTraced): int =
  return cmp(uint32(a.qualifiedName), uint32(b))

proc findAttr(element: Element; qualifiedName: CAtomTraced): int =
  let qualifiedName = element.normalizeAttrQName(qualifiedName)
  let n = element.attrs.lowerBound(qualifiedName, cmpAttrName)
  if n < element.attrs.len and element.attrs[n].qualifiedName == qualifiedName:
    return n
  return -1

proc matchesLocalName(qualifiedName: CAtom; localName: CAtomTraced): bool =
  let i = qualifiedName.find(':') + 1
  if i == 0:
    return qualifiedName == localName
  return ($qualifiedName).toOpenArray(i, ($qualifiedName).high) == $localName

proc findAttrNS(element: Element; namespace, localName: CAtomTraced): int =
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
  if JS_IsException(this):
    return nil
  let res = ctx.getWeak(wwmAttributes, this)
  JS_FreeValue(ctx, this)
  var map: NamedNodeMap
  if ctx.fromJSFree(res, map).isErr:
    return nil
  return map

proc hasAttribute(element: Element; qualifiedName: CAtomTraced): bool
    {.jsfunc.} =
  return element.findAttr(qualifiedName) != -1

proc hasAttributeNS(element: Element; namespace, localName: CAtomTraced): bool
    {.jsfunc.} =
  return element.findAttrNS(namespace, localName) != -1

proc getAttributeNames(ctx: JSContext; element: Element): JSValue {.jsfunc.} =
  var s = newSeqOfCap[JSValue](element.attrs.len)
  for it in element.attrs:
    s.add(ctx.toJS(it.qualifiedName))
  return ctx.newArrayFrom(s)

proc getAttribute(ctx: JSContext; element: Element;
    qualifiedName: CAtomTraced): JSValue {.jsfunc.} =
  let i = element.findAttr(qualifiedName)
  if i != -1:
    return ctx.toJS(element.attrs[i].value)
  return JS_NULL

proc getAttributeNS(ctx: JSContext; element: Element;
    namespace, localName: CAtomTraced): JSValue {.jsfunc.} =
  let i = element.findAttrNS(namespace, localName)
  if i != -1:
    return ctx.toJS(element.attrs[i].value)
  return JS_NULL

proc attr*(element: Element; s: CAtomTraced): lent string =
  let i = element.findAttr(s)
  if i != -1:
    return element.attrs[i].value
  # the compiler cries if I return string literals :/
  let emptyStr {.global.} = ""
  return emptyStr

proc attr*(element: Element; s: StaticAtom): lent string =
  return element.attr(s.view())

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

proc attrb*(element: Element; s: CAtomTraced): bool =
  return element.findAttr(s) != -1

proc attrb*(element: Element; at: StaticAtom): bool =
  return element.attrb(at.view())

proc getElementsByTagName(element: Element; tagName: CAtomTraced):
    HTMLCollection {.jsfunc.} =
  return getElementsByTagNameImpl(element, tagName)

proc getElementsByClassName(element: Element; classNames: DOMString):
    HTMLCollection {.jsfunc.} =
  return getElementsByClassNameImpl(element, classNames)

proc children(ctx: JSContext; parentNode: Element): JSValue {.jsfget.} =
  return childrenImpl(ctx, parentNode)

proc previousElementSibling*(element: Element): Element {.jsfget.} =
  return element.previousElementSiblingImpl

proc nextElementSibling*(element: Element): Element {.jsfget.} =
  return element.nextElementSiblingImpl

proc before(ctx: JSContext; this: Element; nodes: varargs[JSValueConst]):
    Opt[void] {.jsfunc.} =
  ctx.beforeImpl(this, nodes)

proc after(ctx: JSContext; this: Element; nodes: varargs[JSValueConst]):
    Opt[void] {.jsfunc.} =
  ctx.afterImpl(this, nodes)

proc replaceWith(ctx: JSContext; this: Element;
    nodes: varargs[JSValueConst]): JSValue {.jsfunc.} =
  ctx.replaceWithImpl(this, nodes)

proc remove*(this: Element) {.jsfunc.} =
  this.removeImpl()

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

# Does this precede other?
proc precedes(this, other: Element): bool =
  var other = other
  while other != nil:
    if other == this:
      return true
    let otherParent = other.parentElement
    var this = this
    while this != nil:
      let thisParent = this.parentElement
      if thisParent == otherParent:
        return this.elIndex < other.elIndex
      this = thisParent
    other = otherParent
  false

proc findAncestorIncl*(element: Element; tagType: TagType): Element =
  for element in element.branchElems:
    if element.tagType == tagType:
      return element
  return nil

proc scriptingEnabled(element: Element): bool =
  return element.document.scriptingEnabled

proc isSubmitButton*(element: Element): bool =
  if element.tagType == TAG_BUTTON:
    return element.attr(satType).equalsIgnoreCase("submit")
  elif element of HTMLInputElement:
    let element = HTMLInputElement(element)
    return element.inputType in {itSubmit, itImage}
  return false

proc isButton*(element: Element): bool =
  if element.tagType == TAG_BUTTON:
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
  if element.tagType == TAG_FORM:
    return element.attr(satAction)
  return ""

proc enctype*(element: Element): FormEncodingType =
  if element.tagType == TAG_FORM:
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

proc parseFragment*(ctx: JSContext; element: Element; s: openArray[char]):
    DocumentFragment =
  #TODO xml
  let newChildren = parseHTMLFragmentImpl(element, s)
  let fragment = element.document.newDocumentFragment()
  for child in newChildren:
    fragment.append(child, ctx)
  return fragment

proc innerHTML(ctx: JSContext; element: Element; s: DOMStringNull) {.jsfset.} =
  #TODO shadow root
  let fragment = ctx.parseFragment(element, s.toOpenArray())
  let nodeCtx = if element of HTMLTemplateElement:
    HTMLTemplateElement(element).content
  else:
    element
  nodeCtx.replaceAll(fragment, ctx)

proc outerHTML(ctx: JSContext; element: Element; s: DOMStringNull): JSValue
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
  let fragment = ctx.parseFragment(parent, s.toOpenArray())
  ctx.replaceChildWithThrow(parent, element, fragment)

type InsertAdjacentPosition = enum
  iapBeforeBegin = "beforebegin"
  iapAfterEnd = "afterend"
  iapAfterBegin = "afterbegin"
  iapBeforeEnd = "beforeend"

proc insertAdjacentHTML(ctx: JSContext; this: Element;
    position, text: DOMString): JSValue {.jsfunc.} =
  let pos0 = parseEnumNoCase[InsertAdjacentPosition](position.toOpenArray())
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
  let fragment = ctx.parseFragment(nodeCtx, text.toOpenArray())
  case position
  of iapBeforeBegin: this.parentNode.insert(fragment, this, ctx)
  of iapAfterBegin: this.insert(fragment, this.firstChild, ctx)
  of iapBeforeEnd: this.append(fragment, ctx)
  of iapAfterEnd: this.parentNode.insert(fragment, this.nextSibling, ctx)
  return JS_UNDEFINED

proc insertAdjacent(ctx: JSContext; this: Node; position: DOMString;
    node: Node): JSValue =
  let pos0 = parseEnumNoCase[InsertAdjacentPosition](position.toOpenArray())
  if pos0.isErr:
    return JS_ThrowDOMException(ctx, "SyntaxError", "invalid position")
  case pos0.get
  of iapBeforeBegin:
    if this.parentNode == nil:
      JS_NULL
    else:
      ctx.insertBefore(this.parentNode, node, option(this))
  of iapAfterBegin: ctx.insertBefore(this, node, option(this.firstChild))
  of iapBeforeEnd: ctx.insertBefore(this, node, none(Node))
  of iapAfterEnd:
    ctx.insertBefore(this.parentNode, node, option(this.nextSibling))

proc insertAdjacentElement(ctx: JSContext; this: Element; position: DOMString;
    element: Element): JSValue {.jsfunc.} =
  ctx.insertAdjacent(this, position, element)

proc insertAdjacentText(ctx: JSContext; this: Element; position, s: DOMString):
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

#TODO clientLeft, clientTop, offsetLeft, offsetTop

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

#TODO these should add the border too
proc offsetWidth(element: Element): int32 {.jsfget.} =
  let rect = element.getBlockRect()
  if rect != nil and rect.width <= float64(int32.high):
    return int32(rect.width)
  0

proc offsetHeight(element: Element): int32 {.jsfget.} =
  let rect = element.getBlockRect()
  if rect != nil and rect.height <= float64(int32.high):
    return int32(rect.height)
  0

const WindowEvents* = [satError, satLoad, satFocus, satBlur]

proc reflectScriptAttr(element: Element; name: StaticAtom; value: string):
    bool =
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
      document.reflectEvent(target, n, t, value, target2)
      return true
  false

proc reflectLocalAttr(element: Element; name: StaticAtom; has: bool;
    value: string) =
  case element.tagType
  of TAG_INPUT:
    let input = HTMLInputElement(element)
    case name
    of satValue: input.setValue(value)
    of satChecked: input.setChecked(has)
    of satType:
      input.inputType = parseEnumNoCase[InputType](value).get(itText)
    else: discard
  of TAG_OPTION:
    let option = HTMLOptionElement(element)
    if name == satSelected:
      option.selected = has
  of TAG_BUTTON:
    let button = HTMLButtonElement(element)
    if name == satType:
      button.ctype = parseEnumNoCase[ButtonType](value).get(btSubmit)
  of TAG_LINK:
    let link = HTMLLinkElement(element)
    if name == satRel:
      link.relList.reflectTokens(value) # do not return
    let document = link.document
    let connected = link.isConnected()
    if name == satDisabled:
      let wasDisabled = link.isDisabled()
      link.enabled = some(not has)
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
        window.loadLink(link)
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
        window.loadImage(image)
  else: discard

# Called whenever an attribute changes on the element.
# If `has' is false, then value is "".  Otherwise, value is the new
# attribute value.
proc reflectAttr0(element: Element; name: CAtomTraced; has: bool;
    value: string) =
  let name = name.toStaticAtom()
  case name
  of satId:
    if element.id != satUempty:
      freeAtom(element.id)
      element.document.removeElementId(element)
    if has:
      element.id = value.toAtom()
    else:
      element.id = satUempty.toAtom()
    if element.id != satUempty:
      let root = element.rootNode
      if root of Document:
        Document(root).addElementId(element)
  of satName:
    freeAtom(element.name)
    if has:
      element.name = value.toAtom()
    else:
      element.name = satUempty.toAtom()
  of satClass: element.classList.reflectTokens(value)
  #TODO internalNonce
  of satStyle:
    if has:
      element.cachedStyle = newCSSStyleDeclaration(element, value)
    else:
      element.cachedStyle = nil
  of satUnknown: discard # early return
  elif element.scriptingEnabled and element.reflectScriptAttr(name, value):
    discard
  else:
    element.reflectLocalAttr(name, has, value)

proc reflectAttr(element: Element; name: CAtomTraced; has: bool;
    value: string) =
  element.reflectAttr0(name, has, value)
  element.document.invalidateCollections()
  element.invalidate()

proc reflectAttrDel(element: Element; name: CAtomTraced) =
  element.reflectAttr(name, false, "")

proc reflectAttr(element: Element; attr: AttrData) =
  element.reflectAttr(attr.qualifiedName.view(), true, attr.value)

proc elIndex*(this: Element): uint32 =
  if this.parentNode == nil:
    return 0
  let parent = this.parentElement
  if parent == nil:
    return 0 # <html>
  if parent.firstChild == this:
    return 0
  if efChildElIndicesInvalid in parent.flags:
    var n = 0'u32
    for element in parent.elementList:
      element.internalElIndex = n
      inc n
    parent.flags.excl(efChildElIndicesInvalid)
  return this.internalElIndex

proc isPreviousSiblingOf*(this, other: Element): bool =
  return this.parentNode == other.parentNode and this.elIndex <= other.elIndex

proc querySelector(ctx: JSContext; this: Element; q: DOMString): JSValue
    {.jsfunc.} =
  return ctx.querySelectorImpl(this, q)

proc querySelectorAll(ctx: JSContext; this: Element; q: DOMString): JSValue
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
proc newElement(document: Document;
    localName, namespaceURI, tagName: CAtomTraced): Element =
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
  of TAG_SLOT:
    HTMLSlotElement()
  of TAG_OUTPUT:
    HTMLOutputElement()
  elif sns == satNamespaceSVG:
    if tagType == TAG_SVG:
      SVGSVGElement()
    else:
      SVGElement()
  else:
    HTMLElement()
  element.id = satUempty.toAtom()
  element.name = satUempty.toAtom()
  element.localName = localName.dup()
  element.namespaceURI = namespaceURI.dup()
  element.tagName = tagName.dup()
  element.internalNext = document
  element.classList = element.newDOMTokenList(satClass)
  element.custom = if localName.isValidCustomElementName():
    cesUndefined
  else:
    cesUncustomized
  element

proc newElement*(document: Document; localName: CAtomTraced;
    namespace = satNamespaceHTML): Element =
  return document.newElement(localName, namespace.view(), localName.dupTrace())

proc renderBlocking(element: Element): bool =
  if element.attr(satBlocking).containsToken("render"):
    return true
  if element of HTMLScriptElement:
    let element = HTMLScriptElement(element)
    if element.ctype == stClassic and element.parserDocument != nil and
        not element.attrb(satAsync) and not element.attrb(satDefer):
      return true
  return false

proc blockRendering(element: Element) =
  let document = element.document
  if document.contentType == satTextHtml and
      document.findFirst(TAG_BODY) == nil:
    element.document.renderBlockingElements.add(element)

proc invalidate*(element: Element) =
  element.document.invalid = true
  var node = Node(element)
  while node != nil:
    var skip = false
    if node of Element:
      let desc = Element(node)
      skip = desc.computed == nil or efRestyle in desc.flags
      desc.flags.incl(efRestyle)
    node = node.nextDescendant(Node(element), skip)

proc ensureStyle*(element: Element) =
  if element.computed == nil or efRestyle in element.flags:
    element.flags.excl(efRestyle)
    element.applyStyleImpl()

proc resetElement*(element: Element; ctx: JSContext) =
  case element.tagType
  of TAG_INPUT:
    let input = HTMLInputElement(element)
    case input.inputType
    of itCheckbox, itRadio:
      input.setChecked(input.attrb(satChecked))
    of itFile:
      if input.internalFiles != nil:
        input.internalFiles.clear()
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
  of TAG_OUTPUT:
    let output = HTMLOutputElement(element)
    output.replaceAll(output.defaultValue.toDOMStringView(), ctx)
    output.dirty = false
    output.internalValue = ""
  else: discard

# Returns true if has post-connection steps.
proc insertionSteps(element: Element): bool =
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
      window.loadLink(link)
  of TAG_IMG:
    let window = element.document.window
    if window != nil:
      let image = HTMLImageElement(element)
      window.loadImage(image)
  of TAG_STYLE:
    let style = HTMLStyleElement(element)
    if style.isConnected():
      let document = style.document
      if document.sheetTitle == "":
        document.sheetTitle = style.attr(satTitle)
      style.updateSheet()
  of TAG_SCRIPT:
    return true
  elif element.tagType(satNamespaceSVG) == TAG_SVG:
    return true
  elif element of FormAssociatedElement:
    let element = FormAssociatedElement(element)
    if not element.parserInserted:
      element.resetFormOwner()
  false

proc removingSteps(element: Element) =
  if element of FormAssociatedElement:
    let element = FormAssociatedElement(element)
    element.resetFormOwner()

proc postConnectionSteps(element: Element) =
  case element.tagType
  of TAG_SCRIPT:
    let script = HTMLScriptElement(element)
    if script.isConnected and script.parserDocument == nil:
      script.prepare()
  elif element.tagType(satNamespaceSVG) == TAG_SVG:
    # we invoke loadSVG here to avoid the case where the descendants still
    # point to an already inserted node
    #TODO this doesn't work if JS adds descendants to the SVG tag
    let svg = SVGSVGElement(element)
    if svg.parserDocument != svg.document:
      let window = svg.document.window
      if window != nil:
        window.loadSVG(svg)
  else: discard

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
  let name = element.attrs[i].qualifiedName.dupTrace()
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
        attrs: @[data]
      )
      attr.dataIdx = 0
      map.attrlist.del(j) # ordering does not matter
  element.deleteAttr(i) # ordering matters
  element.reflectAttrDel(name)

proc attr(element: Element; name: CAtomTraced; value: DOMString) =
  var i = element.attrs.upperBound(name, cmpAttrName)
  if i > 0 and element.attrs[i - 1].qualifiedName == name:
    dec i
    element.attrs[i].value = $value
  else:
    element.attrs.insert(AttrData(
      namespace: CAtomNull,
      qualifiedName: name.dup(),
      value: $value
    ), i)
  element.reflectAttr(element.attrs[i])

proc attr(element: Element; name: StaticAtom; value: DOMString) =
  element.attr(name.view(), value)

proc attr*(element: Element; name: CAtomTraced; value: sink string) =
  var i = element.attrs.upperBound(name, cmpAttrName)
  if i > 0 and element.attrs[i - 1].qualifiedName == name:
    dec i
    element.attrs[i].value = value
  else:
    element.attrs.insert(AttrData(
      namespace: CAtomNull,
      qualifiedName: name.dup(),
      value: value
    ), i)
  element.reflectAttr(element.attrs[i])

proc attr(element: Element; name: StaticAtom; value: sink string) =
  element.attr(name.view(), value)

proc attrns0(element: Element;
    namespace, localName, qualifiedName: CAtomTraced; value: sink string) =
  var i = element.findAttrNS(namespace, localName)
  if i != -1:
    element.attrs[i].value = value
  else:
    i = element.attrs.upperBound(qualifiedName, cmpAttrName)
    element.attrs.insert(AttrData(
      namespace: namespace.dup(),
      qualifiedName: qualifiedName.dup(),
      value: value
    ), i)
  element.reflectAttr(element.attrs[i])

proc attrns*(element: Element; localName: CAtomTraced; prefix: NamespacePrefix;
    namespace: CAtomTraced; value: sink string) =
  if prefix == NO_PREFIX and namespace == satUempty:
    element.attr(localName, value)
    return
  let qualifiedName = if prefix != NO_PREFIX:
    ($prefix & ':' & $localName).toAtomTrace()
  else:
    localName.dupTrace()
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

proc setAttribute(ctx: JSContext; element: Element;
    qualifiedName, value: DOMString): Opt[void] {.jsfunc.} =
  ?ctx.validateName(qualifiedName.toOpenArray())
  let qualifiedName = if element.namespaceURI == satNamespaceHTML and
      not element.document.isxml:
    qualifiedName.toAtomLowerTrace()
  else:
    qualifiedName.toAtomTrace()
  element.attr(qualifiedName, value)
  ok()

proc setAttributeNS(ctx: JSContext; element: Element; namespace: CAtomTraced;
    qualifiedName: CAtomTraced; value: DOMString): Opt[void] {.jsfunc.} =
  var namespace = namespace.dupTrace()
  var localName = qualifiedName.dupTrace()
  ?ctx.validateAndExtract(namespace, localName, nvAttribute)
  element.attrns0(namespace, localName, qualifiedName, $value)
  ok()

proc removeAttribute(ctx: JSContext; element: Element;
    qualifiedName: CAtomTraced) {.jsfunc.} =
  let i = element.findAttr(qualifiedName)
  if i != -1:
    ctx.delAttr(element, i)

proc removeAttributeNS(ctx: JSContext; element: Element;
    namespace, localName: CAtomTraced) {.jsfunc.} =
  let i = element.findAttrNS(namespace, localName)
  if i != -1:
    ctx.delAttr(element, i)

proc toggleAttribute(ctx: JSContext; element: Element;
    qualifiedName: DOMString; force: JSValueConst = JS_UNDEFINED): Opt[bool]
    {.jsfunc.} =
  let forceBool = JS_ToBool(ctx, force)
  if forceBool < 0:
    return err()
  ?ctx.validateName(qualifiedName.toOpenArray())
  let qualifiedName = element.normalizeAttrQName(qualifiedName.toAtomTrace())
  if not element.attrb(qualifiedName):
    if JS_IsUndefined(force) or forceBool == 1:
      element.attr(qualifiedName, "")
      return ok(true)
    return ok(false)
  if JS_IsUndefined(force) or forceBool == 0:
    let i = element.findAttr(qualifiedName)
    if i != -1:
      ctx.delAttr(element, i)
    return ok(false)
  return ok(true)

proc setId(element: Element; id: DOMString) {.jsfset: "id".} =
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
  if charset != csUnknown:
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

proc requestFullscreen(ctx: JSContext; element: Element): JSValue {.jsfunc.} =
  JS_ThrowTypeError(ctx, "fullscreen is not supported")
  return ctx.newRejectedPromise()

proc getBitmap*(element: Element): NetworkBitmap =
  case element.tagType
  of TAG_IMG:
    return HTMLImageElement(element).bitmap
  of TAG_CANVAS:
    let bmp = HTMLCanvasElement(element).bitmap
    if bmp != nil and bmp.cacheId != -1:
      return bmp
    return nil
  elif element.tagType(satNamespaceSVG) == TAG_SVG:
    return SVGSVGElement(element).bitmap
  else:
    return nil

proc shadowRoot(this: Element): ShadowRoot {.jsfget.} =
  let first = this.internalFirst
  if first of ShadowRoot:
    return ShadowRoot(first)
  return nil

proc setShadowRoot(this: Element; shadow: ShadowRoot) =
  if this.internalFirst != nil:
    shadow.internalNext = move(this.internalFirst)
  this.internalFirst = shadow

proc attachShadow(ctx: JSContext; this: Element; init: ShadowRootInit):
    Opt[ShadowRoot] {.jsfunc.} =
  let document = this.document
  let customElements = if init.customElementRegistry != nil:
    init.customElementRegistry
  else:
    document.customElements
  if customElements != nil and not customElements.scoped and
      customElements != document.customElements:
    JS_ThrowDOMException(ctx, "NotSupportedError",
      "custom element registry is not scoped")
    return err()
  if this.namespaceURI != satNamespaceHTML:
    JS_ThrowDOMException(ctx, "NotSupportedError",
      "only HTML elements can have shadow trees")
    return err()
  const AllowedTags = {
    TAG_ARTICLE, TAG_ASIDE, TAG_BLOCKQUOTE, TAG_BODY, TAG_DIV, TAG_FOOTER,
    TAG_H1, TAG_H2, TAG_H3, TAG_H4, TAG_H5, TAG_H6, TAG_HEADER, TAG_MAIN,
    TAG_NAV, TAG_P, TAG_SECTION, TAG_SPAN
  }
  let validCustom = this.localName.view().isValidCustomElementName()
  if not validCustom and this.tagType notin AllowedTags:
    JS_ThrowDOMException(ctx, "NotSupportedError", "invalid tag name")
    return err()
  if validCustom: #TODO or is value is non-null
    #TODO check for disable shadow
    discard
  let old = this.shadowRoot
  if old != nil:
    if not old.declarative or old.mode != init.mode:
      JS_ThrowDOMException(ctx, "NotSupportedError",
        "cannot replace old shadow root")
      return err()
    let removedNodes = old.getChildList()
    for child in removedNodes:
      child.removeImpl()
    old.declarative = false
    return ok(old)
  let shadow = ShadowRoot(
    host: this,
    mode: init.mode,
    delegatesFocus: init.delegatesFocus,
    #TODO available to internals
    slotAssignment: init.slotAssignment,
    clonable: init.clonable,
    serializable: init.serializable,
    customElements: customElements
  )
  this.setShadowRoot(shadow)
  ok(shadow)

proc closest(ctx: JSContext; this: Element; q: DOMString): JSValue {.jsfunc.} =
  let selectors = ctx.parseSelectors(q)
  if selectors.len == 0:
    return JS_EXCEPTION
  for element in this.branchElems:
    if element.matchesImpl(selectors):
      return ctx.toJS(element)
  return JS_NULL

proc matches(ctx: JSContext; this: Element; q: DOMString): JSValue {.jsfunc.} =
  let selectors = ctx.parseSelectors(q)
  if selectors.len == 0:
    return JS_EXCEPTION
  return ctx.toJS(this.matchesImpl(selectors))

# ShadowRoot
proc host(this: ShadowRoot): Element {.jsfget.} =
  DocumentFragment(this).host

proc globalCustomElements(this: ShadowRoot): CustomElementRegistry =
  if not this.customElements.scoped:
    return this.customElements
  let document = this.document
  if not document.customElements.scoped:
    return document.customElements
  return nil

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

proc applyStyleDependencies*(document: Document; element: Element;
    depends: DependencyInfo) =
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

proc find(this: CSSStyleDeclaration; p: CSSPropertyType): int =
  for i, decl in this.decls.mypairs:
    if decl.t == cdtProperty and decl.p.sh == cstNone and decl.p.p == p:
      return i
  return -1

proc find(this: CSSStyleDeclaration; s: openArray[char]): int =
  if s.startsWith("--"):
    let v = s.toOpenArray(2, s.high).toAtomTrace()
    for i, decl in this.decls.mypairs:
      if decl.t == cdtVariable and decl.v == v:
        return i
    return -1
  if p := propertyType(s):
    return this.find(p)
  return -1

proc getPropertyValue(this: CSSStyleDeclaration; s: CSSOMString): string
    {.jsfunc.} =
  var res = ""
  if (let sh = shorthandType(s.toOpenArray()); sh != cstNone):
    var flags: array[CSSImportantFlag, bool]
    for p in ShorthandMap[sh]:
      let i = this.find(p)
      if i < 0:
        return ""
      flags[this.decls[i].f] = true
      if flags[cifNormal] and flags[cifImportant]:
        return ""
      for it in this.decls[i].value:
        res &= $it
      res &= ' '
    if res.len > 0:
      res.setLen(res.high)
  elif (let i = this.find(s.toOpenArray()); i >= 0):
    for it in this.decls[i].value:
      res &= $it
  move(res)

proc getter(ctx: JSContext; this: CSSStyleDeclaration; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  var ds: DOMString
  case ctx.fromIdx(atom, u, ds)
  of fiIdx:
    if u < this.length:
      return ctx.toJS(this.decls[int(u)].name)
    return JS_UNINITIALIZED
  of fiStr:
    if ds.toOpenArray() == "cssFloat":
      return ctx.toJS(this.getPropertyValue(initDOMStringLit("float")))
    if ds.toOpenArray().isSupportedProperty():
      return ctx.toJS(this.getPropertyValue(ds))
    let s = ds.toOpenArray().camelToKebabCase()
    if s.isSupportedProperty():
      return ctx.toJS(this.getPropertyValue(s.toDOMStringView()))
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
  of cdtNestedRule: return err()
  of cdtVariable:
    if parseDeclWithVar1(toks).len == 0:
      return err()
  this.decls[i].value = move(toks)
  return ok()

proc checkReadOnly(ctx: JSContext; this: CSSStyleDeclaration): Opt[void] =
  if this.readonly:
    JS_ThrowDOMException(ctx, "NoModificationAllowedError",
      "cannot modify read-only declaration")
    return err()
  ok()

proc removeProperty(ctx: JSContext; this: CSSStyleDeclaration;
    name: CSSOMString): JSValue {.jsfunc.} =
  if ctx.checkReadOnly(this).isErr:
    return JS_EXCEPTION
  let name = name.toOpenArray().toLowerAscii()
  let value = this.getPropertyValue(name.toDOMStringView())
  let sh = shorthandType(name)
  if sh != cstNone:
    for t in ShorthandMap[sh]:
      let i = this.find(t)
      if i != -1:
        this.decls.delete(i)
  else:
    let i = this.find(name)
    if i != -1:
      this.decls.delete(i)
  return ctx.toJS(value)

proc setProperty(ctx: JSContext; this: CSSStyleDeclaration;
    name, value: CSSOMString): JSValue {.jsfunc.} =
  if ctx.checkReadOnly(this).isErr:
    return JS_EXCEPTION
  if not name.toOpenArray().isSupportedProperty():
    return JS_UNDEFINED
  if value.len == 0:
    return ctx.removeProperty(this, name)
  let name = name.toOpenArray().toLowerAscii()
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
    of cdtNestedRule:
      return JS_UNDEFINED
    of cdtVariable:
      if parseDeclWithVar1(toks).len == 0:
        return JS_UNDEFINED
    decl.value = move(toks)
    this.decls.add(move(decl))
  this.element.attr(satStyle, this.cssText)
  return JS_UNDEFINED

proc setter(ctx: JSContext; this: CSSStyleDeclaration; atom: JSAtom;
    value: CSSOMString): JSValue {.jssetprop.} =
  if ctx.checkReadOnly(this).isErr:
    return JS_EXCEPTION
  var u: uint32
  var ds: DOMString
  case ctx.fromIdx(atom, u, ds)
  of fiIdx:
    var toks = parseComponentValues(value)
    if this.setValue(int(u), toks).isErr:
      this.element.attr(satStyle, this.cssText)
    return JS_UNDEFINED
  of fiStr:
    var name = $ds
    if name == "cssFloat":
      name = "float"
    name = camelToKebabCase(name)
    return ctx.setProperty(this, name.toDOMStringView(), value)
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
  #TODO take StaticAtom for tagType
  let element = document.newElement(tagType.toStaticAtom().view(),
    satNamespaceHTML)
  return HTMLElement(element)

proc crossOrigin(element: HTMLElement): CORSAttribute =
  if not element.attrb(satCrossorigin):
    return caNoCors
  let s = element.attr(satCrossorigin)
  if s.equalsIgnoreCase("use-credentials"):
    return caUseCredentials
  caAnonymous

proc referrerPolicy(element: HTMLElement): Opt[ReferrerPolicy] =
  parseEnumNoCase[ReferrerPolicy](element.attr(satReferrerpolicy))

proc dataset(ctx: JSContext; element: HTMLElement): JSValue {.jsfget.} =
  return ctx.getWeakCollection(element, wwmDataset)

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
    if JS_IsException(href):
      return JS_EXCEPTION
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
    var s: DOMString
    if ctx.fromJS(val, s).isOk:
      element.attr(satHref, s)
      return JS_DupValue(ctx, val)
    return JS_EXCEPTION
  if url := element.reinitURL():
    let href = ctx.toJS(url)
    let res = JS_SetPropertyStr(ctx, href, cstring($sa), JS_DupValue(ctx, val))
    if res < 0:
      return JS_EXCEPTION
    var ds: DOMString
    if ctx.fromJSFree(href, ds).isOk:
      element.attr(satHref, ds)
  return JS_DupValue(ctx, val)

proc click(ctx: JSContext; element: HTMLElement) {.jsfunc.} =
  let event = newEvent(satClick, element, bubbles = true, cancelable = true)
  let canceled = ctx.dispatch(element, event)
  if not canceled:
    let window = ctx.getWindow()
    if window != nil:
      window.click(element)

# <a>
proc toString(anchor: HTMLAnchorElement): string {.jsfunc.} =
  if href := anchor.reinitURL():
    return $href
  return ""

proc setRelList(anchor: HTMLAnchorElement; ds: DOMString) {.
    jsfset: "relList".} =
  anchor.attr(satRel, ds)

# <area>
proc toString(area: HTMLAreaElement): string {.jsfunc.} =
  if href := area.reinitURL():
    return $href
  return ""

proc setRelList(area: HTMLAreaElement; ds: DOMString) {.jsfset: "relList".} =
  area.attr(satRel, ds)

# <audio>
proc newAudio(ctx: JSContext; this_target: JSValueConst; argc: cint;
    argv: JSValueConstArray): JSValue {.cdecl.} =
  let document = ctx.getDocument()
  let this = document.newHTMLElement(TAG_AUDIO)
  if argc >= 1 and not JS_IsUndefined(argv[0]):
    var ds: DOMString
    ?ctx.fromJS(argv[0], ds)
    this.attr(satSrc, ds)
  ctx.toJS(this)

# <base>
proc href(base: HTMLBaseElement): string {.jsfget.} =
  #TODO with fallback base url
  if url := parseURL(base.attr(satHref)):
    return $url
  return ""

# <button>
proc setType(this: HTMLButtonElement; s: DOMString) {.jsfset: "type".} =
  this.attr(satType, s)

# <canvas>
proc getContext*(jctx: JSContext; this: HTMLCanvasElement;
    contextId: DOMString; options: JSValueConst = JS_UNDEFINED):
    CanvasRenderingContext2D {.jsfunc.} =
  if contextId.toOpenArray() == "2d":
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

type ToBlobEnv {.final.} = ref object of BlobOpaque
  ctx: JSContext
  callback: JSValue
  isPNG: bool
  this: HTMLCanvasElement
  url: URL

proc onFinishToBlob(response: Response; success: bool) =
  let env = ToBlobEnv(response.opaque)
  let ctx = env.ctx
  let callback = env.callback
  let this = env.this
  let blob = response.onFinishBlob(success)
  if blob == nil:
    JS_FreeValue(ctx, callback)
    JS_FreeContext(ctx)
    return
  let jsBlob = ctx.toJS(blob)
  if JS_IsException(jsBlob):
    JS_FreeValue(ctx, callback)
    JS_FreeContext(ctx)
    return
  let window = this.document.window
  let res = ctx.callSinkFree(callback, JS_UNDEFINED, jsBlob)
  if JS_IsException(res):
    window.console.error("Exception in canvas toBlob:",
      ctx.getExceptionMsg())
  else:
    JS_FreeValue(ctx, res)
  JS_FreeContext(ctx)

proc toBlob1(opaque: RootRef; response: Response) =
  let env = ToBlobEnv(opaque)
  let ctx = env.ctx
  let callback = env.callback
  let this = env.this
  if response == nil:
    if not env.isPNG:
      # Redo as PNG.  (Yes, this is spec-mandated.)
      ctx.toBlob(this, callback, "image/png")
    else: # the png encoder doesn't work...
      let window = this.document.window
      window.console.error("missing/broken PNG encoder")
    JS_FreeValue(ctx, callback)
    JS_FreeContext(ctx)
  else:
    response.onFinish = onFinishToBlob
    let window = env.ctx.getGlobal()
    window.loader.blob(response, env)

proc toBlob0(opaque: RootRef; response: Response) =
  let env = ToBlobEnv(opaque)
  let ctx = env.ctx
  if response == nil:
    JS_FreeValue(ctx, env.callback)
    JS_FreeContext(ctx)
    return
  let this = env.this
  let headers = newHeaders(hgRequest, {
    "Cha-Image-Dimensions": $this.bitmap.width & 'x' & $this.bitmap.height
  })
  let request = newRequest(
    env.url,
    httpMethod = hmPost,
    headers = headers,
    body = RequestBody(t: rbtOutput, outputId: response.outputId)
  )
  let window = this.document.window
  window.corsFetch(request, toBlob1, env)
  window.loader.close(response)

proc toBlob(ctx: JSContext; this: HTMLCanvasElement; callback: JSValueConst;
    contentType = "image/png"; qualityVal: JSValueConst = JS_UNDEFINED)
    {.jsfunc.} =
  let contentType = contentType.toLowerAscii()
  if not contentType.startsWith("image/") or this.bitmap.cacheId == 0:
    return
  let url = parseURL0("img-codec+" & contentType.after('/') & ":encode")
  if url == nil:
    return
  let headers = newHeaders(hgRequest, {
    "Cha-Image-Dimensions": $this.bitmap.width & 'x' & $this.bitmap.height
  })
  if JS_IsNumber(qualityVal):
    # standard-compliant special case; it also means that we don't have to
    # propagate exceptions here (as nothing can throw one)
    var quality: float64
    if ctx.fromJS(qualityVal, quality).isOk and 0 <= quality and quality <= 1:
      quality *= 99
      quality += 1
      headers.add("Cha-Image-Quality", dtoa(quality))
  # callback will go out of scope when we return, so capture a new reference.
  let callback = JS_DupValue(ctx, callback)
  let request = newRequest(
    "img-codec+x-cha-canvas:decode",
    httpMethod = hmPost,
    body = RequestBody(t: rbtCache, cacheId: this.bitmap.cacheId)
  )
  let env = ToBlobEnv(
    ctx: JS_DupContext(ctx),
    callback: JS_DupValue(ctx, callback),
    isPNG: contentType == "image/png",
    this: this,
    url: url
  )
  let window = this.document.window
  window.corsFetch(request, toBlob0, env)

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

proc setRelList(form: HTMLFormElement; s: DOMString) {.jsfset: "relList".} =
  form.attr(satRel, s)

proc elements(form: HTMLFormElement): HTMLFormControlsCollection {.jsfget.} =
  if form.cachedElements == nil:
    form.cachedElements = newCollection[HTMLFormControlsCollection](
      root = form.rootNode,
      match = proc(this: Collection; node: Node): bool =
        if node of FormAssociatedElement:
          let element = FormAssociatedElement(node)
          if element.tagType in ListedElements:
            let this = HTMLFormControlsCollection(this)
            return element.form == this.form
        return false,
      islive = true,
      childonly = false
    )
    form.cachedElements.form = form
  form.cachedElements

proc getter(ctx: JSContext; this: HTMLFormElement; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  let elements = this.elements()
  return ctx.getter(elements, atom)

proc length(this: HTMLFormElement): uint32 {.jsfget.} =
  let elements = this.elements()
  elements.getLength()

proc resetForm*(form: HTMLFormElement; ctx: JSContext) =
  for control in form.controls:
    control.resetElement(ctx)
    control.invalidate()

# FormAssociatedElement
proc setForm*(element: FormAssociatedElement; form: HTMLFormElement) =
  element.form = form
  if form.controlsTail == nil:
    form.controlsHead = element
  else:
    form.controlsTail.next = element
  element.prev = form.controlsTail
  form.controlsTail = element
  form.document.invalidateCollections()

proc resetFormOwner(element: FormAssociatedElement) =
  element.parserInserted = false
  if element.form != nil:
    if element.tagType notin ListedElements:
      return
    let lastForm = element.findAncestor(TAG_FORM)
    if not element.attrb(satForm) and lastForm == element.form:
      return
  let form = element.form
  if form != nil:
    if element.prev == nil:
      form.controlsHead = element.next
    else:
      element.prev.next = element.next
    if element.next == nil:
      form.controlsTail = element.prev
    else:
      element.next.prev = element.prev
    element.prev = nil
    element.next = nil
    element.form = nil
  if element.tagType in ListedElements and element.isConnected:
    let id = element.attr(satForm).toAtomTrace()
    let form = element.document.getElementById(id)
    if form of HTMLFormElement:
      element.setForm(HTMLFormElement(form))
  if element.form == nil:
    for ancestor in element.ancestors:
      if ancestor of HTMLFormElement:
        element.setForm(HTMLFormElement(ancestor))

# <img>
proc newImage(ctx: JSContext; _: JSValueConst; argc: cint;
    argv: JSValueConstArray): JSValue {.cdecl.} =
  let document = ctx.getDocument()
  let this = document.newHTMLElement(TAG_IMG)
  if argc >= 1 and not JS_IsUndefined(argv[0]):
    var x: uint32
    ?ctx.fromJS(argv[0], x)
    this.attrul(satWidth, x)
  if argc >= 2 and not JS_IsUndefined(argv[1]):
    var x: uint32
    ?ctx.fromJS(argv[1], x)
    this.attrul(satHeight, x)
  ctx.toJS(this)

proc getImageRect(this: HTMLImageElement): tuple[w, h: float64] =
  let window = this.document.window
  if window != nil and window.settings.scripting == smApp:
    window.ensureLayout(this)
    let objs = getClientRectsImpl(this, firstOnly = true, blockOnly = false)
    if objs.len > 0:
      return (objs[0].width, objs[0].height)
  let bitmap = this.bitmap
  if bitmap == nil:
    return (0'f64, 0'f64)
  let width = float64(this.attrul(satWidth).get(uint32(bitmap.width)))
  let height = float64(this.attrul(satHeight).get(uint32(bitmap.height)))
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
proc value*(this: HTMLInputElement): lent string {.jsfget.} =
  if this.internalValue == nil:
    this.internalValue = newRefString("")
  return this.internalValue.s

proc setValue*(this: HTMLInputElement; value: sink string) =
  this.internalValue = newRefString(value)
  this.invalidate()

proc setValue(this: HTMLInputElement; ds: DOMString) {.jsfset: "value".} =
  this.setValue($ds)

proc setType(this: HTMLInputElement; s: DOMString) {.jsfset: "type".} =
  this.attr(satType, s)

proc checked*(input: HTMLInputElement): bool {.inline.} =
  return input.internalChecked

proc setChecked*(input: HTMLInputElement; b: bool) {.jsfset: "checked".} =
  # Note: input elements are implemented as a replaced text, so we must
  # fully invalidate them on checked change.
  if input.inputType == itRadio and b:
    for radio in input.radiogroup:
      radio.invalidate(dtChecked)
      radio.invalidate()
      radio.internalChecked = false
  input.invalidate(dtChecked)
  input.invalidate()
  input.internalChecked = b

proc files*(this: HTMLInputElement): FileList {.jsfget.} =
  if this.internalFiles == nil:
    this.internalFiles = newFileList()
  this.internalFiles

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
    return newRefString(input.files.getName())
  else:
    return input.internalValue

proc select(ctx: JSContext; input: HTMLInputElement) {.jsfunc.} =
  ctx.focus(input)

proc addFile*(this: HTMLInputElement; file: WebFile) =
  this.files.add(file)
  this.invalidate()

# <label>
proc control*(label: HTMLLabelElement): FormAssociatedElement {.jsfget.} =
  let f = label.attr(satFor)
  if f != "":
    let id = f.toAtomTrace()
    let elem = label.document.getElementById(id)
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

proc setRelList(link: HTMLLinkElement; s: DOMString) {.jsfset: "relList".} =
  link.attr(satRel, s)

# <option>
proc newOption(ctx: JSContext; _: JSValueConst; argc: cint;
    argv: JSValueConstArray): JSValue {.cdecl.} =
  let document = ctx.getDocument()
  let this = HTMLOptionElement(document.newHTMLElement(TAG_OPTION))
  if argc >= 1 and not JS_IsUndefined(argv[0]):
    var text: DOMString
    ?ctx.fromJS(argv[0], text)
    if text.len > 0:
      this.insert(document.newText(text), nil, ctx)
  if argc >= 2 and not JS_IsUndefined(argv[1]):
    var value: DOMString
    ?ctx.fromJS(argv[1], value)
    this.attr(satValue, value)
  if argc >= 3:
    var defaultSelected: bool
    ?ctx.fromJS(argv[2], defaultSelected)
    if defaultSelected:
      this.attr(satSelected, "")
  if argc >= 4:
    ?ctx.fromJS(argv[3], this.selected)
  ctx.toJS(this)

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

proc setValue(option: HTMLOptionElement; ds: DOMString) {.jsfset: "value".} =
  option.attr(satValue, ds)

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

# <output>
proc getType(this: HTMLOutputElement): string {.jsfget: "type".} =
  return "output"

proc defaultValue(this: HTMLOutputElement): string {.jsfget.} =
  if this.dirty:
    return this.internalValue
  return this.textContent

proc setDefaultValue(ctx: JSContext; this: HTMLOutputElement; ds: DOMString)
    {.jsfset: "defaultValue".} =
  if this.dirty:
    this.dirty = true
    this.internalValue = $ds
  else:
    this.replaceAll(ds, ctx)

proc value(this: HTMLOutputElement): string {.jsfget.} =
  return this.textContent

proc setValue(ctx: JSContext; this: HTMLOutputElement; ds: DOMString) {.
    jsfset: "value".} =
  if not this.dirty:
    this.dirty = true
    this.internalValue = this.textContent
  this.replaceAll(ds, ctx)

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
  if element.tagType notin {TAG_OPTION, TAG_OPTGROUP}:
    return JS_ThrowTypeError(ctx, "expected option or optgroup element")
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

proc length(this: HTMLOptionsCollection): uint32 {.jsfget.} =
  this.getLength()

proc setLength(this: HTMLOptionsCollection; n: uint32) {.jsfset: "length".} =
  let len = this.getLength()
  if n > len:
    if n <= 100_000: # LOL
      let parent = this.root
      let document = parent.document
      for i in 0 ..< n - len:
        parent.append(document.newHTMLElement(TAG_OPTION), nil)
  else:
    for i in 0 ..< len - n:
      let it = this.item(uint32(i))
      it.remove()

proc options(this: HTMLSelectElement): HTMLOptionsCollection {.jsfget.} =
  if this.cachedOptions == nil:
    this.cachedOptions = newCollection[HTMLOptionsCollection](
      root = this,
      match = proc(this: Collection; node: Node): bool =
        node.isOptionOf(this.root),
      islive = true,
      childonly = false
    )
  this.cachedOptions

proc setter(ctx: JSContext; this: HTMLOptionsCollection; atom: JSAtom;
    value: Option[HTMLOptionElement]): JSValue {.jssetprop.} =
  var u: uint32
  case ctx.fromIdx(atom, u)
  of fiIdx: discard
  of fiStr: return JS_UNINITIALIZED
  of fiErr: return JS_EXCEPTION
  let element = this.item(u)
  let value = value.get(nil)
  if value == nil:
    if element != nil:
      element.remove()
    return JS_UNDEFINED
  let parent = this.root
  if element != nil:
    return ctx.replaceChildWithThrow(parent, element, value)
  let len = this.getLength()
  let document = parent.document
  for i in len ..< u:
    let res = parent.insertBefore(document.newHTMLElement(TAG_OPTION), nil,
      ctx)
    if res.isErr:
      return ctx.insertThrow(res.error)
  return ctx.insertBeforeUndefined(parent, value, none(Node))

proc length(ctx: JSContext; this: HTMLSelectElement): uint32 {.jsfget.} =
  let options = this.options()
  options.getLength()

proc setLength(ctx: JSContext; this: HTMLSelectElement; n: uint32) {.
    jsfset: "length".} =
  let options = this.options()
  options.setLength(n)

proc getter(ctx: JSContext; this: HTMLSelectElement; u: JSAtom): JSValue
    {.jsgetownprop.} =
  let options = this.options()
  return ctx.getter(options, u)

proc item(this: HTMLSelectElement; u: uint32): Element {.jsfunc.} =
  let options = this.options()
  options.item(u)

proc namedItem(ctx: JSContext; this: HTMLSelectElement; atom: CAtomTraced):
    Element {.jsfunc.} =
  let options = this.options()
  options.namedItem(atom)

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

proc setValue(this: HTMLSelectElement; value: DOMString) {.jsfset: "value".} =
  var found = false
  for it in this.options:
    if not found and it.value == value.toOpenArray():
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
  let options = this.options()
  return ctx.add(options, element, before)

proc remove(ctx: JSContext; this: HTMLSelectElement;
    idx: varargs[JSValueConst]): Opt[void] {.jsfunc.} =
  if idx.len > 0:
    var i: int32
    ?ctx.fromJS(idx[0], i)
    let options = this.options()
    options.remove(i)
  else:
    this.remove()
  ok()

# <style>
proc updateSheetFinish(window: Window; this: SheetElement; res: LoadSheetResult;
    env: ParseSheetEnv; i: int) =
  this.updateSheet(res.head, res.tail)
  if this.isConnected():
    let title = this.attr(satTitle)
    let document = this.document
    for sheet in this.sheets:
      sheet.disabled = title != "" and title != document.sheetTitle

proc updateSheet*(this: HTMLStyleElement) =
  let document = this.document
  let window = document.window
  if window != nil:
    window.parseStylesheet(this, this.textContent, document.baseURL,
      DefaultCharset, CAtomNull, updateSheetFinish, nil, 0)

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
  return window.loader.doRequest(request)

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

type
  FetchModuleEnv {.final.} = ref object of BlobOpaque
    window: Window
    element: HTMLScriptElement
    settings: EnvironmentSettings
    url: URL
    moduleType: ModuleType
    referrerPolicy: Opt[ReferrerPolicy]
    onComplete: OnCompleteProc
    options: ScriptOptions

proc onFinishFetchModule(response: Response; success: bool) =
  let env = FetchModuleEnv(response.opaque)
  let url = env.url
  let window = env.window
  let settings = env.settings
  let element = env.element
  let moduleType = env.moduleType
  let onComplete = env.onComplete
  let contentType = env.contentType
  let ctx = window.jsctx
  let blob = response.onFinishBlob(success)
  if blob == nil:
    let res = ScriptResult(t: srtNull)
    settings.moduleMap.put(url, moduleType, res)
    element.onComplete(res)
    return
  if contentType.isJavaScriptType():
    let source = blob.toOpenArray().toValidUTF8()
    let res = ctx.newJSModuleScript(source, url, env.options)
    #TODO can't we just return null from newJSModuleScript?
    if JS_IsException(res.script.record):
      window.logException(res.script.baseURL)
      element.onComplete(ScriptResult(t: srtNull))
    else:
      if env.referrerPolicy.isOk:
        res.script.options.referrerPolicy = env.referrerPolicy
      # set & onComplete both take ownership
      settings.moduleMap.put(url, moduleType, res.clone())
      element.onComplete(res)
  else:
    #TODO non-JS modules
    discard

proc fetchSingleModuleResponse(opaque: RootRef; response: Response) =
  let env = FetchModuleEnv(opaque)
  let settings = env.settings
  let url = env.url
  let moduleType = env.moduleType
  let element = env.element
  let onComplete = env.onComplete
  let window = env.window
  if response == nil:
    let res = ScriptResult(t: srtNull)
    settings.moduleMap.put(url, moduleType, res)
    element.onComplete(res)
    return
  env.referrerPolicy = response.getReferrerPolicy()
  response.onFinish = onFinishFetchModule
  window.loader.blob(response, env)

#TODO settings object
proc fetchSingleModule(element: HTMLScriptElement; url: URL;
    destination: RequestDestination; options: ScriptOptions;
    referrer: URL; isTopLevel: bool; onComplete: OnCompleteProc) =
  let moduleType = mtJavascript
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
  let request = newRequest(
    url,
    referrer = referrer,
    destination = destination,
    mode = mode
  )
  #TODO set up module script request
  #TODO performFetch
  let opaque = FetchModuleEnv(
    window: window,
    element: element,
    url: url,
    settings: settings,
    moduleType: moduleType,
    onComplete: onComplete,
    options: options,
  )
  window.fetch(request, fetchSingleModuleResponse, opaque)

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
    document.currentScript = if not (element.rootNode of ShadowRoot):
      element
    else:
      nil
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
      if response.stream == nil:
        element.markAsReady(ScriptResult(t: srtNull))
      else:
        window.loader.resume(response)
        let source = response.stream.readAll().decodeAll(encoding)
        response.stream.sclose()
        let script = window.jsctx.newClassicScript(source, response.url,
          options, false)
        element.markAsReady(script)
  else:
    #TODO if stClassic, parserDocument != nil, parserDocument has a style sheet
    # that is blocking scripts, either the parser is an XML parser or a HTML
    # parser with a script level <= 1
    element.execute()

# <table>
proc getTableChild(this: HTMLTableElement; tagType: TagType): Element {.
    jsmfget("caption", TAG_CAPTION), jsmfget("tHead", TAG_THEAD),
    jsmfget("tFoot", TAG_TFOOT).} =
  this.findFirstChildOf(tagType)

proc setTableChild(ctx: JSContext; this: HTMLTableElement; tagType: TagType;
    sectVal: JSValueConst): JSValue {.jsmfset("caption", TAG_CAPTION),
    jsmfset("tHead", TAG_THEAD), jsmfset("tFoot", TAG_TFOOT).} =
  var sect: HTMLElement
  if not JS_IsNull(sectVal):
    ?ctx.fromJS(sectVal, sect)
  if sect != nil and sect.tagType != tagType:
    if tagType != TAG_CAPTION and sect of HTMLTableSectionElement:
      return ctx.insertThrow("wrong element type")
    return JS_ThrowTypeError(ctx, "%s tag expected", cstring($tagType))
  let old = this.findFirstChildOf(tagType)
  if old != nil:
    old.remove()
  if sect == nil:
    return JS_UNDEFINED
  return ctx.insertBeforeUndefined(this, sect, option(this.firstChild))

proc tBodies(ctx: JSContext; this: HTMLTableElement): JSValue {.jsfget.} =
  return ctx.getWeakCollection(this, wwmTBodies)

proc rows(this: HTMLTableElement): HTMLCollection {.jsfget.} =
  if this.cachedRows == nil:
    this.cachedRows = newHTMLCollection(
      this,
      match = proc(this: Collection; node: Node): bool =
        if Node(node.parentNode) == this.root or
            Node(node.parentNode.parentNode) == this.root:
          return this.isRow(node)
        false,
      islive = true,
      childonly = false
    )
  this.cachedRows

proc createTableChild(this: HTMLTableElement; tagType: TagType): Element {.
    jsmfunc("createCaption", TAG_CAPTION), jsmfunc("createTHead", TAG_THEAD),
    jsmfunc("createTBody", TAG_TBODY), jsmfunc("createTFoot", TAG_TFOOT).} =
  let tagType = cast[TagType](tagType)
  let before = case tagType
  of TAG_CAPTION: this.firstChild
  of TAG_THEAD: this.findFirstChildNotOf({TAG_CAPTION, TAG_COLGROUP})
  of TAG_TBODY: this.findLastChildOf(TAG_TBODY)
  else: nil # tfoot
  var element = this.findFirstChildOf(tagType)
  if element == nil:
    element = this.document.newHTMLElement(tagType)
    this.insert(element, before, nil)
  return element

proc deleteTableChild(this: HTMLTableElement; tag: TagType) {.
    jsmfunc("deleteCaption", TAG_CAPTION), jsmfunc("deleteTHead", TAG_THEAD),
    jsmfunc("deleteTFoot", TAG_TFOOT).} =
  let element = this.findFirstChildOf(cast[TagType](tag))
  if element != nil:
    element.remove()

proc insertRow(ctx: JSContext; this: HTMLTableElement; index: int32 = -1):
    Opt[HTMLElement] {.jsfunc.} =
  let rows = this.rows()
  let nrows = rows.getLength()
  if index < -1 or index > int64(nrows):
    JS_ThrowDOMException(ctx, "IndexSizeError", "index out of bounds")
    return err()
  let tr = this.document.newHTMLElement(TAG_TR)
  if nrows == 0:
    this.createTableChild(TAG_TBODY).append(tr, ctx)
  elif index == -1 or uint32(index) == nrows:
    let it = rows.item(nrows - 1)
    it.parentNode.append(tr, ctx)
  else:
    let it = rows.item(uint32(index))
    it.parentNode.insert(tr, it, ctx)
  ok(tr)

proc deleteRow(ctx: JSContext; rows: HTMLCollection; index: int32): Opt[void] =
  let nrows = rows.getLength()
  if index < -1 or index >= int64(nrows):
    JS_ThrowDOMException(ctx, "IndexSizeError", "index out of bounds")
    return err()
  if index == -1:
    let it = rows.item(uint32(nrows - 1))
    it.remove()
  elif nrows > 0:
    let it = rows.item(uint32(index))
    it.remove()
  ok()

proc deleteRow(ctx: JSContext; this: HTMLTableElement; index: int32 = -1):
    Opt[void] {.jsfunc.} =
  let rows = this.rows()
  return ctx.deleteRow(rows, index)

# <tbody>
proc rows(this: HTMLTableSectionElement): HTMLCollection {.jsfget.} =
  if this.cachedRows == nil:
    this.cachedRows = newHTMLCollection(
      this,
      match = isRow,
      islive = true,
      childonly = true
    )
  this.cachedRows

proc insertRow(ctx: JSContext; this: HTMLTableSectionElement;
    index: int32 = -1): Opt[HTMLElement] {.jsfunc.} =
  let rows = this.rows()
  let nrows = rows.getLength()
  if index < -1 or index > int64(nrows):
    JS_ThrowDOMException(ctx, "index out of bounds", "IndexSizeError")
    return err()
  let tr = this.document.newHTMLElement(TAG_TR)
  if index == -1 or index == int64(nrows):
    this.append(tr, ctx)
  else:
    let it = rows.item(uint32(index))
    this.insert(tr, it, ctx)
  ok(tr)

proc deleteRow(ctx: JSContext; this: HTMLTableSectionElement;
    index: int32 = -1): Opt[void] {.jsfunc.} =
  let rows = this.rows()
  return ctx.deleteRow(rows, index)

# <tr>
proc cells(ctx: JSContext; this: HTMLTableRowElement): JSValue {.jsfget.} =
  return ctx.getWeakCollection(this, wwmCells)

proc rowIndex(this: HTMLTableRowElement): int {.jsfget.} =
  let table = HTMLTableElement(this.findAncestor(TAG_TABLE))
  if table == nil:
    return -1
  let rows = table.rows()
  rows.findNode(this)

proc sectionRowIndex(this: HTMLTableRowElement): int {.jsfget.} =
  let parent = this.parentElement
  if parent.tagType == TAG_TABLE:
    return this.rowIndex()
  if parent of HTMLTableSectionElement:
    let parent = HTMLTableSectionElement(parent)
    let rows = parent.rows()
    return rows.findNode(this)
  return -1

# <textarea>
proc value*(this: HTMLTextAreaElement): string {.jsfget.} =
  if this.dirty:
    return this.internalValue
  return this.childTextContent

proc setValue*(this: HTMLTextAreaElement; s: sink string) =
  this.dirty = true
  this.internalValue = s
  this.invalidate()

proc setValue(this: HTMLTextAreaElement; ds: DOMString) {.jsfset: "value".} =
  this.setValue($ds)

proc defaultValue(this: HTMLTextAreaElement): string {.jsfget.} =
  this.textContent

proc setDefaultValue(ctx: JSContext; this: HTMLTextAreaElement; ds: DOMString)
    {.jsfset: "defaultValue".} =
  this.replaceAll(ds, ctx)

# <title>
proc text(this: HTMLTitleElement): string {.jsfget.} =
  return this.textContent

proc setText(ctx: JSContext; this: HTMLTitleElement; ds: DOMString) {.
    jsfset: "text".} =
  this.replaceAll(ds, ctx)

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

proc addElementReflection(ctx: JSContext; class: JSClassID): Opt[void] =
  let proto = JS_GetClassProto(ctx, class)
  for i in ReflectAllStartIndex ..< int16(ReflectMap.len):
    let name = $ReflectMap[i].funcname
    if ctx.addReflectFunction(proto, cstring(name), jsReflectGet, jsReflectSet,
        cint(i)).isErr:
      JS_FreeValue(ctx, proto)
      return err()
  JS_FreeValue(ctx, proto)
  ok()

proc addAttributeReflection(ctx: JSContext; class: JSClassID;
    attrs: openArray[int16]; base: JSClassID): Opt[void] =
  let proto = JS_GetClassProto(ctx, class)
  let diff = (uint16(class) - uint16(base)) shl 9
  for i in attrs:
    if ctx.addReflectFunction(proto, cstring($ReflectMap[i].funcname),
        jsReflectGet, jsReflectSet, cint(diff or uint16(i))).isErr:
      JS_FreeValue(ctx, proto)
      return err()
  JS_FreeValue(ctx, proto)
  ok()

proc addConstructorAlias(ctx: JSContext; fun: JSCFunction; class: JSClassID;
    name: string): Opt[void] =
  let val = JS_NewCFunction2(ctx, fun, name, 0, JS_CFUNC_constructor, 0)
  if JS_IsException(val):
    return err()
  discard JS_SetConstructorBit(ctx, val, true)
  let proto = JS_GetClassProto(ctx, class)
  if ctx.defineProperty(val, "prototype", proto) == dprException:
    JS_FreeValue(ctx, val)
    return err()
  let global = JS_GetGlobalObject(ctx)
  let res = ctx.definePropertyCW(global, name, val)
  JS_FreeValue(ctx, global)
  if res == dprException:
    return err()
  ok()

proc addHyperlinkUtils(ctx: JSContext; class: JSClassID): Opt[void] =
  const atoms = [
    satHref, satOrigin, satProtocol, satUsername, satPassword, satHost,
    satHostname, satPort, satPathname, satSearch, satHash
  ]
  let proto = JS_GetClassProto(ctx, class)
  for atom in atoms:
    if ctx.definePropertyGetSetCE(proto, cstring($atom), hyperlinkGet,
        hyperlinkSet, cint(atom)) == dprException:
      JS_FreeValue(ctx, proto)
      return err()
  JS_FreeValue(ctx, proto)
  ok()

proc registerElements(ctx: JSContext; nodeCID: JSClassID): Opt[void] =
  let elementCID = ctx.registerType(Element, parent = nodeCID)
  if elementCID == 0:
    return err()
  let htmlElementCID = ctx.registerType(HTMLElement, parent = elementCID)
  if htmlElementCID == 0:
    return err()
  ?ctx.addElementReflection(htmlElementCID)
  template register(t: typed; tags: openArray[TagType]) =
    let class = ctx.registerType(t, parent = htmlElementCID)
    if class == 0:
      return err()
    const attrs = TagReflectMap[tags[0]]
    when attrs.len > 0:
      ?ctx.addAttributeReflection(class, attrs, htmlElementCID)
  template register2(t: typed; tag: TagType): JSClassID =
    let class = ctx.registerType(t, parent = htmlElementCID)
    if class == 0:
      return err()
    const attrs = TagReflectMap[tag]
    when attrs.len > 0:
      ?ctx.addAttributeReflection(class, attrs, htmlElementCID)
    class
  template register(t: typed; tag: TagType) =
    register(t, [tag])
  register(HTMLInputElement, TAG_INPUT)
  let anchorCID = register2(HTMLAnchorElement, TAG_A)
  register(HTMLSelectElement, TAG_SELECT)
  register(HTMLSpanElement, TAG_SPAN)
  register(HTMLOptGroupElement, TAG_OPTGROUP)
  let optionCID = register2(HTMLOptionElement, TAG_OPTION)
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
  let areaCID = register2(HTMLAreaElement, TAG_AREA)
  register(HTMLButtonElement, TAG_BUTTON)
  register(HTMLTextAreaElement, TAG_TEXTAREA)
  register(HTMLLabelElement, TAG_LABEL)
  register(HTMLCanvasElement, TAG_CANVAS)
  let imageCID = register2(HTMLImageElement, TAG_IMG)
  register(HTMLVideoElement, TAG_VIDEO)
  let audioCID = register2(HTMLAudioElement, TAG_AUDIO)
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
  register(HTMLSlotElement, TAG_SLOT)
  register(HTMLOutputElement, TAG_OUTPUT)
  # 46/127 (warning: the 128th interface won't fit in the top 7 bits of
  # the getter/setter magic)
  let svgElementCID = ctx.registerType(SVGElement, parent = elementCID)
  if svgElementCID == 0:
    return err()
  ?ctx.registerType(SVGSVGElement, parent = svgElementCID)
  ?ctx.addConstructorAlias(newAudio, audioCID, "Audio")
  ?ctx.addConstructorAlias(newImage, imageCID, "Image")
  ?ctx.addConstructorAlias(newOption, optionCID, "Option")
  ?ctx.addHyperlinkUtils(anchorCID)
  ctx.addHyperlinkUtils(areaCID)

proc addDOMModule*(ctx: JSContext; eventTargetCID: JSClassID): Opt[void] =
  let nodeCID = ctx.registerType(Node, parent = eventTargetCID)
  if nodeCID == 0:
    return err()
  if ctx.defineConsts(nodeCID, NodeType) == dprException:
    return err()
  let nodeListCID = ctx.registerType(NodeList, iterable = jitValue)
  if nodeListCID == 0:
    return err()
  let htmlCollectionCID = ctx.registerType(HTMLCollection, iterable = jitIndexed)
  if htmlCollectionCID == 0:
    return err()
  ?ctx.registerType(HTMLAllCollection)
  ?ctx.registerType(HTMLFormControlsCollection, parent = htmlCollectionCID)
  ?ctx.registerType(HTMLOptionsCollection, parent = htmlCollectionCID)
  ?ctx.registerType(RadioNodeList, parent = nodeListCID)
  ?ctx.registerType(NodeIterator)
  ?ctx.registerType(TreeWalker)
  ?ctx.registerType(Location)
  let documentCID = ctx.registerType(Document, parent = nodeCID)
  if documentCID == 0:
    return err()
  ?ctx.registerType(XMLDocument, parent = documentCID)
  ?ctx.registerType(DOMImplementation)
  ?ctx.registerType(DOMTokenList, iterable = jitValue)
  ?ctx.registerType(DOMStringMap)
  let characterDataCID = ctx.registerType(CharacterData, parent = nodeCID)
  if characterDataCID == 0:
    return err()
  ?ctx.registerType(Comment, parent = characterDataCID)
  let documentFragmentCID = ctx.registerType(DocumentFragment, parent = nodeCID)
  if documentFragmentCID == 0:
    return err()
  ?ctx.registerType(ProcessingInstruction, parent = characterDataCID)
  let textCID = ctx.registerType(Text, parent = characterDataCID)
  if textCID == 0:
    return err()
  ?ctx.registerType(CDATASection, parent = textCID)
  ?ctx.registerType(DocumentType, parent = nodeCID)
  ?ctx.registerType(Attr, parent = nodeCID)
  ?ctx.registerType(NamedNodeMap)
  ?ctx.registerType(CSSStyleDeclaration)
  ?ctx.registerType(CustomElementRegistry)
  ?ctx.registerType(ShadowRoot, parent = documentFragmentCID)
  ?ctx.registerElements(nodeCID)
  let global = JS_GetGlobalObject(ctx)
  let document = JS_GetPropertyStr(ctx, global, "Document")
  if ctx.definePropertyCW(global, "HTMLDocument", document) == dprException:
    return err()
  let nodeFilter = JS_NewObject(ctx)
  if JS_IsException(nodeFilter):
    return err()
  for e in NodeFilterNode:
    let n = ctx.toJS(1u32 shl uint32(e))
    if ctx.definePropertyE(nodeFilter, $e, n) == dprException:
      return err()
  for e in NodeFilterResult:
    let n = ctx.toJS(uint32(e))
    if ctx.definePropertyE(nodeFilter, $e, n) == dprException:
      return err()
  case ctx.definePropertyE(nodeFilter, "SHOW_ALL", ctx.toJS(0xFFFFFFFFu32))
  of dprException: return err()
  else: discard
  if ctx.definePropertyCW(global, "NodeFilter", nodeFilter) == dprException:
    return err()
  JS_FreeValue(ctx, global)
  ok()

# Forward declaration hack
isDefaultPassiveImpl = proc(target: EventTarget): bool =
  if not (target of Node):
    return false
  let node = Node(target)
  return target of Window or EventTarget(node.document) == target or
    EventTarget(node.document.documentElement) == target or
    EventTarget(node.document.findFirst(TAG_BODY)) == target

getParentImpl = proc(ctx: JSContext; eventTarget: EventTarget; isLoad: bool):
    EventTarget =
  if eventTarget of Node:
    if eventTarget of Document:
      if isLoad:
        return nil
      # if no browsing context, then window will be nil anyway
      return Document(eventTarget).window
    if eventTarget of ShadowRoot:
      let shadow = ShadowRoot(eventTarget)
      #TODO composed
      return shadow.host
    return Node(eventTarget).parentNode
  return nil

errorImpl = proc(ctx: JSContext; ss: varargs[string]) =
  ctx.getGlobal().console.error(ss)

getAPIBaseURLImpl = proc(ctx: JSContext): URL =
  let window = ctx.getWindow()
  if window == nil or window.document == nil:
    return nil
  return window.document.baseURL

getOriginImpl = proc(ctx: JSContext): Origin =
  ctx.getGlobal().settings.origin

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
