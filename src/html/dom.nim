{.push raises: [].}

import std/algorithm
import std/hashes
import std/math
import std/options
import std/setutils
import std/times

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
import js/fromjs
import js/jsbind
import js/jsnull
import js/jsopaque
import js/jspropenumlist
import js/jsref
import js/jstypes
import js/jsutils
import js/quickjs
import js/tojs
import server/headers
import server/loaderiface
import server/request
import types/bitmap
import types/blob
import types/color
import js/jsopt
import types/opt
import types/refstring
import types/url
import types/winattrs
import utils/dtoawrap
import utils/tabutil
import utils/twtstr

type
  DocumentReadyState* = enum
    rsLoading = "loading"
    rsInteractive = "interactive"
    rsComplete = "complete"

type
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

  DependencyItem = object
    key: ptr ElementObj
    value: ptr ElementObj
    hcache: Hash

  DependencyMap = object
    tab: seq[DependencyItem]
    load: int

  DependencyMapPair = object
    dependsOn: DependencyMap
    dependedBy: DependencyMap

  DependencyInfo* = array[DependencyType, seq[Element]]

  LoadSheetResult = object
    head: CSSStylesheet
    tail: CSSStylesheet

  CachedURLImage* {.final.} = ref object of StrMapItem
    window*: Window #TODO weak?
    expiry: int64
    loading: bool
    shared*: seq[HTMLImageElement]
    bmp: NetworkBitmap
    cacheId: int
    subtype: string

  CachedSVG* {.final.} = ref object of StrMapItem
    window*: Window #TODO weak?
    shared*: seq[SVGSVGElement] # elements that serialize to the same string
    bmp: NetworkBitmap
    cacheId: int
    imageId: int

  Window* = JSRef[WindowObj]

  WindowObj* {.pure, final.} = object of EventTargetObj
    bc*: RootRef # backref to BufferContext
    console*: Console
    event*: Event
    settings*: EnvironmentSettings
    loader*: FileLoader
    jsctx*: JSContext
    document*: Document
    timeouts*: TimeoutState
    importMapsAllowed*: bool
    inMicrotaskCheckpoint*: bool
    dangerAlwaysSameOrigin*: bool # for client, insecure if Window sets true
    remoteSheetNum*: uint32
    loadedSheetNum*: uint32
    remoteImageNum*: uint32
    loadedImageNum*: uint32
    imageURLCache*: StrMap
    svgCache*: StrMap
    # ID of the next image
    imageId*: int
    # list of streams that must be closed for canvas rendering on load
    pendingCanvasCtls*: seq[CanvasRenderingContext2D]
    imageTypes*: MimeTypesImages
    userAgent*: string
    referrer*: string
    performance*: Performance
    customElements*: CustomElementRegistry
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

  CECallbackMap = array[CECallbackType, JSCallback]

  CustomElementFlag = enum
    cefFormAssociated, cefInternals, cefShadow

  CustomElementDef = ref object
    name: CAtom
    localName: CAtom
    ctor: JSObject
    observedAttrs: seq[CAtom]
    callbacks: CECallbackMap
    flags: set[CustomElementFlag]
    next: CustomElementDef

  CustomElementRegistryObj* = object
    defsHead: CustomElementDef
    defsTail: CustomElementDef
    inDefine: bool
    scoped: bool
    scopedDocuments: seq[Document]

  CustomElementRegistry = JSRef[CustomElementRegistryObj]

  ElementAccessor = JSRef[ElementAccessorObj]

  ElementAccessorObj {.pure.} = object of JSRootObj
    nextAccessor: ElementAccessor

  NamedNodeMap = JSRef[NamedNodeMapObj]

  NamedNodeMapObj {.pure, final.} = object of ElementAccessorObj
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

  ParseSheetEnv = ref object
    sheet: CSSStylesheet
    sheets: seq[LoadSheetResult]
    loaded: int
    finish: LoadSheetFinish
    parent: ParseSheetEnv
    i: int

  LoadSheetFinish = proc(window: Window; this: SheetElement;
    res: LoadSheetResult; env: ParseSheetEnv; i: int) {.  nimcall, raises: [].}

  CollectionName* = enum
    cnUnknown # reserved for unmarked collections
    cnChildren
    cnChildNodes
    cnForms
    cnLinks
    cnImages
    cnGetElementsByName
    cnGetElementsByTagName
    cnGetElementsByClassName
    cnGetElementsById
    cnSelectedOptions
    cnTBodies
    cnRows
    cnCells
    cnOptions
    cnAll
    cnElements

  CollectionLike = JSRef[CollectionLikeObj]

  CollectionLikeObj {.pure.} = object of JSRootObj
    hcache: Hash
    root*: Node
    # If not nil, this is a live collection.
    document: ptr DocumentObj

  Collection* = JSRef[CollectionObj]

  CollectionMode* = enum
    cmSubtree, cmChildren, cmTree

  CollectionObj {.pure.} = object of CollectionLikeObj
    mode*: CollectionMode
    invalid*: bool
    match*: CollectionMatchFun
    snapshot*: seq[Node]
    atoms*: seq[CAtom]

  NodeIteratorLike = JSRef[NodeIteratorLikeObj]

  NodeIteratorLikeObj {.pure.} = object of CollectionLikeObj
    active: bool
    whatToShow: uint32
    filter: JSObject
    currentNode: Node

  NodeIteratorObj {.pure, final.} = object of NodeIteratorLikeObj
    iterNode: Node
    before: bool
    iterBefore: bool

  NodeIterator = JSRef[NodeIteratorObj]

  TreeWalkerObj {.pure, final.} = object of NodeIteratorLikeObj

  TreeWalker = JSRef[TreeWalkerObj]

  NodeListObj* {.pure.} = object of CollectionObj

  NodeList = JSRef[NodeListObj]

  HTMLCollectionObj* {.pure.} = object of CollectionObj

  HTMLCollection* = JSRef[HTMLCollectionObj]

  HTMLAllCollectionObj {.pure, final.} = object of CollectionObj

  HTMLAllCollection = JSRef[HTMLAllCollectionObj]

  DOMTokenList* = JSRef[DOMTokenListObj]

  DOMTokenListObj {.pure, final.} = object of ElementAccessorObj
    toks: DOMTokenArrayView
    element: Element

  DOMStringMapObj {.pure, final.} = object of ElementAccessorObj
    target: HTMLElement

  DOMStringMap = JSRef[DOMStringMapObj]

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
  Node* = JSRef[NodeObj]

  NodeNil = JSNullRef[NodeObj]

  NodeObj {.pure.} = object of EventTargetObj
    parentNode*: ParentNode
    internalNext: Node # either nextSibling, rootNode or ownerDocument
    internalPrev: Node # either previousSibling or parentNode.lastChild

  ParentNode* = JSRef[ParentNodeObj]

  ParentNodeObj {.pure.} = object of NodeObj
    internalFirst: Node # either firstChild or shadow root

  RootNode = JSRef[RootNodeObj]

  RootNodeObj {.pure.} = object of ParentNodeObj
    elementIdMap: seq[ptr ElementObj]
    elementIdMapLoad: int

  Attr = JSRef[AttrObj]

  AttrObj* {.final.} = object of NodeObj
    dataIdx: int
    ownerElement: Element

  DOMImplementation = distinct Document # strong ref

  DocumentWriteBuffer* = ref object
    data*: string
    i*: int
    prev*: DocumentWriteBuffer

  Document* = JSRef[DocumentObj]

  DocumentObj {.pure.} = object of RootNodeObj
    activeParserWasAborted: bool
    invalid*: bool # whether the document must be rendered again
    charset*: Charset
    quirksMode*: QuirksMode
    readyState*: DocumentReadyState
    contentType*: StaticAtom
    window*: Window
    url*: URL # not nil
    currentScript: HTMLScriptElement
    implementation: JSObject
    origin: Origin
    # document.write
    ignoreDestructiveWrites: int
    throwOnDynamicMarkupInsertion*: int
    writeBuffersTop*: DocumentWriteBuffer
    styleDependencies: array[DependencyType, DependencyMapPair]
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
    parser*: RootRef
    liveCollections: seq[ptr CollectionLikeObj]
    liveCollectionsLoad: int
    customElements: CustomElementRegistry #TODO ?

  XMLDocumentObj {.pure, final.} = object of DocumentObj

  XMLDocument = JSRef[XMLDocumentObj]

  CharacterDataObj {.pure.} = object of NodeObj
    # Note: layout assumes this is only modified directly by appending text.
    data*: RefString

  CharacterData* = JSRef[CharacterDataObj]

  TextObj {.pure.} = object of CharacterDataObj

  Text* = JSRef[TextObj]

  CommentObj* {.pure, final.} = object of CharacterDataObj

  Comment* = JSRef[CommentObj]

  CDATASectionObj {.pure, final.} = object of TextObj

  CDATASection = JSRef[CDATASectionObj]

  ProcessingInstructionObj {.final.} = object of CharacterDataObj
    target: string

  ProcessingInstruction = JSRef[ProcessingInstructionObj]

  DocumentFragmentObj = object of RootNodeObj
    host*: Element

  DocumentFragment* = JSRef[DocumentFragmentObj]

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

  ShadowRootObj {.pure, final.} = object of DocumentFragmentObj
    mode: ShadowRootMode
    delegatesFocus: bool
    slotAssignment: SlotAssignmentMode
    clonable: bool
    serializable: bool
    declarative: bool
    unsetCustomElements: bool
    customElements: CustomElementRegistry
    #TODO onslotchange

  ShadowRoot = JSRef[ShadowRootObj]

  DocumentTypeObj {.pure, final.} = object of NodeObj
    name*: string
    publicId*: string
    systemId*: string

  DocumentType = JSRef[DocumentTypeObj]

  # Note: the `name` field in AttrData is treated as the qualified name.
  AttrData* = ParsedAttr[CAtom]

  CustomElementState = enum
    cesUndefined = "undefined"
    cesFailed = "failed"
    cesUncustomized = "uncustomized"
    cesPrecustomized = "precustomized"
    cesCustom = "custom"

  ElementFlag = enum
    efHint, efHover, efShadowRoot, efChildElIndicesInvalid, efRestyle,
    efQuirks

  CSSStyleDeclarationObj* = object
    computed: bool
    readonly: bool
    updating: bool
    decls*: seq[CSSDeclaration]
    element: Element

  CSSStyleDeclaration* = JSRef[CSSStyleDeclarationObj]

  Element* = JSRef[ElementObj]

  ElementObj* {.pure.} = object of ParentNodeObj
    # magic is internalElIndex
    namespaceURI*: CAtom # 4
    tagName: CAtom # 8
    relayout*: set[PseudoElement] # 9
    flags: set[ElementFlag] # 10
    selfDepends: set[DependencyType] # 11
    custom: CustomElementState # 12
    localName*: CAtom # 16
    id*: CAtom # 20
    name*: CAtom # 24
    classList*: DOMTokenArray # 32
    attrs*: seq[AttrData] # 48, sorted by int(qualifiedName)
    cachedStyle*: CSSStyleDeclaration # 56
    computed*: CSSValues # 64
    box*: RootRef # 72, CSSBox
    accessorsHead: ElementAccessor # 80, JS-specific helper objects

  AttrDummyElementObj {.pure, final.} = object of ElementObj

  AttrDummyElement = JSRef[AttrDummyElementObj]

  HTMLElementObj* {.pure.} = object of ElementObj

  HTMLElement* = JSRef[HTMLElementObj]

  SVGElementObj {.pure.} = object of ElementObj

  SVGElement = JSRef[SVGElementObj]

  SVGSVGElement* = JSRef[SVGSVGElementObj]

  SVGSVGElementObj {.pure, final.} = object of SVGElementObj
    bitmap*: NetworkBitmap
    parserDocument*: Document
    fetchStarted: bool

  HTMLAnchorElement* = JSRef[HTMLAnchorElementObj]

  HTMLAnchorElementObj* {.pure, final.} = object of HTMLElementObj
    relList: DOMTokenArray

  SheetElement = JSRef[SheetElementObj]

  SheetElementObj {.pure.} = object of HTMLElementObj
    sheetHead: CSSStylesheet
    sheetTail: CSSStylesheet

  HTMLStyleElement* = JSRef[HTMLStyleElementObj]

  HTMLStyleElementObj {.pure, final.} = object of SheetElementObj

  HTMLLinkElement* = JSRef[HTMLLinkElementObj]

  HTMLLinkElementObj {.pure, final.} = object of SheetElementObj
    relList: DOMTokenArray
    fetchStarted: bool
    enabled: Option[bool]

  HTMLTemplateElement* = JSRef[HTMLTemplateElementObj]

  HTMLTemplateElementObj {.pure, final.} = object of HTMLElementObj
    content*: DocumentFragment

  HTMLScriptElement* = JSRef[HTMLScriptElementObj]

  HTMLScriptElementObj {.pure, final.} = object of HTMLElementObj
    parserDocument*: Document
    preparationTimeDocument*: Document
    forceAsync*: bool
    external*: bool
    readyForParserExec*: bool
    alreadyStarted*: bool
    delayingTheLoadEvent: bool
    scriptType: ScriptType
    internalNonce: string
    scriptResult*: ScriptResult
    onReady: (proc(element: HTMLScriptElement) {.nimcall, raises: [].})
    next*: HTMLScriptElement # scriptsToExecSoon/InOrder/OnLoad

  OnCompleteProc = proc(element: HTMLScriptElement; res: ScriptResult)

  HTMLBaseElement = JSRef[HTMLBaseElementObj]

  HTMLBaseElementObj {.pure, final.} = object of HTMLElementObj

  HTMLCanvasElement* = JSRef[HTMLCanvasElementObj]

  HTMLCanvasElementObj {.pure, final.} = object of HTMLElementObj
    ctx2d*: CanvasRenderingContext2D
    bitmap*: NetworkBitmap

  HTMLImageElement* = JSRef[HTMLImageElementObj]

  HTMLImageElementObj {.pure, final.} = object of HTMLElementObj
    bitmap*: NetworkBitmap
    fetchStarted: bool

  HTMLVideoElement* = JSRef[HTMLVideoElementObj]

  HTMLVideoElementObj {.pure, final.} = object of HTMLElementObj

  HTMLAudioElement* = JSRef[HTMLAudioElementObj]

  HTMLAudioElementObj {.pure, final.} = object of HTMLElementObj

  HTMLIFrameElement = JSRef[HTMLIFrameElementObj]

  HTMLIFrameElementObj {.pure, final.} = object of HTMLElementObj

  HTMLTableElement = JSRef[HTMLTableElementObj]

  HTMLTableElementObj {.pure, final.} = object of HTMLElementObj

  HTMLTableSectionElement = JSRef[HTMLTableSectionElementObj]

  HTMLTableSectionElementObj {.pure, final.} = object of HTMLElementObj

  HTMLTableRowElement = JSRef[HTMLTableRowElementObj]

  HTMLTableRowElementObj {.pure, final.} = object of HTMLElementObj

  HTMLFrameElement = JSRef[HTMLFrameElementObj]

  HTMLFrameElementObj {.pure, final.} = object of HTMLElementObj

  HTMLHeadElement = JSRef[HTMLHeadElementObj]

  HTMLHeadElementObj {.pure, final.} = object of HTMLElementObj

  HTMLObjectElement = JSRef[HTMLObjectElementObj]

  HTMLObjectElementObj {.pure, final.} = object of HTMLElementObj

  HTMLSlotElement = JSRef[HTMLSlotElementObj]

  HTMLSlotElementObj {.pure, final.} = object of HTMLElementObj

# Forward declarations
proc loadSheet(window: Window; this: SheetElement; url: URL; charset: Charset;
  layer: CAtom; finish: LoadSheetFinish; i: int; parseEnv: ParseSheetEnv)

proc newCDATASection(document: Document; data: RefString): CDATASection
proc newComment*(document: Document; data: RefString): Comment
proc newText*(document: Document; data: sink string): Text
proc newText*(document: Document; data: DOMString): Text
proc newText(ctx: JSContext; data = initDOMStringLit("")): Text
proc newDocument*(url: URL): Document
proc newDOMImplementation(ctx: JSContext; document: Document): JSValue
proc newDocumentType*(document: Document; name, publicId, systemId: string):
  DocumentType
proc newDocumentFragment(document: Document): DocumentFragment
proc newProcessingInstruction(document: Document; target: string;
  data: RefString): ProcessingInstruction
proc newElement*(document: Document; localName: CAtom;
  namespace = satNamespaceHTML): Element
proc newElement(document: Document;
  localName, namespaceURI, tagName: sink CAtom): Element
proc newHTMLElement*(document: Document; tagType: TagType): HTMLElement
proc newHTMLCollection(root: Node; match: CollectionMatchFun;
  mode: CollectionMode; name: CollectionName): HTMLCollection
proc newEmptyNodeList(): NodeList
proc newNodeList(nodes: openArray[Node]): NodeList
proc newNodeList(root: Node; match: CollectionMatchFun; mode: CollectionMode;
  name: CollectionName): NodeList
proc newCSSStyleDeclaration(element: Element; value: string; computed = false;
  readonly = false): CSSStyleDeclaration

proc isConnected*(node: Node): bool
proc lastChild(node: Node): Node
proc nextDescendant(node, start: Node): Node
proc nextDescendantShadow(node, start: Node): Node
proc parentElement*(node: Node): Element
proc parentNodeHost(node: Node): Node
proc previousSibling*(node: Node): Node
proc serializeFragment(res: var string; node: Node; writeShadow: bool)
proc serializeFragmentInner(res: var string; child: Node; parentType: TagType;
  writeShadow: bool)

proc getChildList*(node: ParentNode): seq[Node]
proc insert*(parent: ParentNode; ctx: JSContext; node, before: Node;
  suppressObservers = false)
proc replaceAll(parent: ParentNode; ctx: JSContext; node: Node)
proc replaceAll*(parent: ParentNode; ctx: JSContext; ds: DOMString)
proc firstChild(parent: ParentNode): lent Node
proc lastChild*(parent: ParentNode): lent Node
proc firstChildShadow(parent: ParentNode): lent Node
proc nextSibling(node: Node): Node
proc previousElementSiblingImpl(this: Node): Element
proc setFirstChild(node: ParentNode; child: Node)

proc addElementId(this: RootNode; element: Element)
proc removeElementId(this: RootNode; element: Element)

proc setData(ctx: JSContext; this: CharacterData; data: DOMStringNull)

proc addLiveCollection(document: Document; collection: CollectionLike)
proc removeLiveCollection(document: Document; collection: CollectionLike)
proc adopt(document: Document; node: Node; ctx: JSContext)
proc applyStyleDependencies*(document: Document; element: Element;
  depends: DependencyInfo)
proc baseURL*(document: Document): URL
proc documentElement*(document: Document): Element
proc findFirst*(document: Document; tagType: TagType): HTMLElement
proc focus*(document: Document): Element
proc invalidateCollections*(document: Document)
proc invalidateCollectionsRemove(document: Document; node: Node)
proc parseURL0*(document: Document; s: string): URL
proc parseURL*(document: Document; s: string): Opt[URL]

proc adjustForRemoval(iter: NodeIterator; node: Node)

proc newAttr(document: Document; data: AttrData): Attr
proc data(attr: Attr): lent AttrData
proc setValue(ctx: JSContext; attr: Attr; ds: DOMString)

proc attachShadow(ctx: JSContext; this: Element; init: ShadowRootInit):
  Opt[ShadowRoot]
proc setAttr(element: Element; ctx: JSContext; name: CAtom;
  value: DOMString)
proc setAttr*(element: Element; ctx: JSContext; name: StaticAtom;
  value: DOMString)
proc setAttr(element: Element; ctx: JSContext; name: CAtom;
  value: sink string)
proc setAttr*(element: Element; ctx: JSContext; name: StaticAtom;
  value: sink string)
proc attr*(element: Element; s: StaticAtom): lent string
proc attrb*(element: Element; at: StaticAtom): bool
proc delAttr(element: Element; ctx: JSContext; i: int)
proc delAttr(element: Element; ctx: JSContext; name: CAtom)
proc elIndex*(this: Element): uint32
proc ensureStyle*(element: Element)
proc findAttr(element: Element; qualifiedName: CAtom): int
proc findAttrNS(element: Element; namespace, localName: CAtom): int
proc getCachedAttributes(element: Element): NamedNodeMap
proc getBoundingClientRect(element: Element): DOMRect
proc getCharset(element: Element): Charset
proc getComputedStyle*(element: Element; pseudo: PseudoElement): CSSValues
proc hasClass*(element: Element; class: CAtom): bool
proc hasInsertionSteps(element: Element): bool
proc insertionSteps(element: Element): bool
proc invalidate*(element: Element)
proc invalidate*(element: Element; dep: DependencyType)
proc nextDisplayedElement(element: Element): Element
proc nextElementSibling*(element: Element): Element
proc outerHTML(element: Element): string
proc postConnectionSteps(element: Element; ctx: JSContext)
proc precedes(this, other: Element): bool
proc previousElementSibling*(element: Element): Element
proc reflectTokens*(element: Element; arr: var DOMTokenArray; name: StaticAtom;
  value: string)
proc removingSteps(element: Element)
proc scriptingEnabled(element: Element): bool
proc shadowRoot(this: Element): ShadowRoot
proc tagType*(element: Element; namespace = satNamespaceHTML): TagType

proc globalCustomElements(this: ShadowRoot): CustomElementRegistry

proc tagType*(element: HTMLElement): TagType

proc removeSheet(this: SheetElement)
proc updateSheet(this: SheetElement; head, tail: CSSStylesheet)
proc toBlob(ctx: JSContext; this: HTMLCanvasElement; callback: JSCallback;
  contentType = "image/png"; qualityVal: JSValueConst = JS_UNDEFINED)
proc getImageRect(this: HTMLImageElement): tuple[w, h: float64]
proc isDisabled(link: HTMLLinkElement): bool
proc execute*(element: HTMLScriptElement)
proc prepare*(element: HTMLScriptElement; ctx: JSContext)
proc fetchDescendantsAndLink(element: HTMLScriptElement; script: Script;
  destination: RequestDestination; onComplete: OnCompleteProc)
proc fetchSingleModule(element: HTMLScriptElement; url: URL;
  destination: RequestDestination; options: ScriptOptions; referrer: URL;
  isTopLevel: bool; onComplete: OnCompleteProc)
proc updateSheet*(this: HTMLStyleElement)

proc cssText(this: CSSStyleDeclaration): string

proc getClassID(t: typedesc[AttrDummyElement]): JSClassID
proc getClassID(t: typedesc[Attr]): JSClassID
proc getClassID(t: typedesc[CDATASection]): JSClassID
proc getClassID(t: typedesc[CSSStyleDeclaration]): JSClassID
proc getClassID(t: typedesc[CharacterData]): JSClassID
proc getClassID(t: typedesc[Collection]): JSClassID
proc getClassID(t: typedesc[Comment]): JSClassID
proc getClassID(t: typedesc[DOMStringMap]): JSClassID
proc getClassID(t: typedesc[DOMTokenList]): JSClassID
proc getClassID(t: typedesc[DocumentFragment]): JSClassID
proc getClassID(t: typedesc[DocumentType]): JSClassID
proc getClassID(t: typedesc[HTMLAllCollection]): JSClassID
proc getClassID(t: typedesc[HTMLHeadElement]): JSClassID
proc getClassID(t: typedesc[HTMLLinkElement]): JSClassID
proc getClassID(t: typedesc[HTMLTableRowElement]): JSClassID
proc getClassID(t: typedesc[HTMLTableSectionElement]): JSClassID
proc getClassID(t: typedesc[NamedNodeMap]): JSClassID
proc getClassID(t: typedesc[NodeIterator]): JSClassID
proc getClassID(t: typedesc[ProcessingInstruction]): JSClassID
proc getClassID(t: typedesc[RootNode]): JSClassID
proc getClassID(t: typedesc[ShadowRoot]): JSClassID
proc getClassID(t: typedesc[SheetElement]): JSClassID
proc getClassID(t: typedesc[TreeWalker]): JSClassID
proc getClassID(t: typedesc[XMLDocument]): JSClassID
proc getClassID*(t: typedesc[Document]): JSClassID
proc getClassID*(t: typedesc[Element]): JSClassID
proc getClassID*(t: typedesc[HTMLAnchorElement]): JSClassID
proc getClassID*(t: typedesc[HTMLCanvasElement]): JSClassID
proc getClassID*(t: typedesc[HTMLCollection]): JSClassID
proc getClassID*(t: typedesc[HTMLElement]): JSClassID
proc getClassID*(t: typedesc[HTMLImageElement]): JSClassID
proc getClassID*(t: typedesc[HTMLScriptElement]): JSClassID
proc getClassID*(t: typedesc[HTMLStyleElement]): JSClassID
proc getClassID*(t: typedesc[HTMLTemplateElement]): JSClassID
proc getClassID*(t: typedesc[NodeList]): JSClassID
proc getClassID*(t: typedesc[Node]): JSClassID
proc getClassID*(t: typedesc[ParentNode]): JSClassID
proc getClassID*(t: typedesc[SVGSVGElement]): JSClassID
proc getClassID*(t: typedesc[Text]): JSClassID

# Forward declaration hacks
proc matchesList(element: Element; cxsels: SelectorList): bool {.
  importc: "cha_$1".}
proc parseHTMLFragment(ctx: JSContext; element: Element; s: openArray[char]):
  seq[Node] {.importc: "cha_$1".}
proc parseDocumentWriteChunk(wrapper: RootRef) {.importc: "cha_$1".}
proc applyStyle(element: Element) {.importc: "cha_$1".}
proc getClientRects(element: Element; firstOnly, blockOnly: bool): seq[DOMRect]
  {.importc: "cha_$1".}
proc sheetLoaded(bc: RootRef) {.importc: "cha_$1".}
proc imageLoaded(bc: RootRef) {.importc: "cha_$1".}
proc navigate(bc: RootRef; url: URL) {.importc: "cha_$1".}
proc ensureLayout(bc: RootRef; element: Element) {.importc: "cha_$1".}
proc clickCallback(bc: RootRef; element: HTMLElement) {.importc: "cha_$1".}
proc unlinkElementBox(element: Element) {.importc: "cha_$1".}
proc insertionStepsForm(element: Element) {.importc: "cha_$1".}
proc removingStepsForm(element: Element) {.importc: "cha_$1".}
proc cloningStepsForm(old, clone: Element) {.importc: "cha_$1".}
proc reflectAttributeForm(element: Element; name: StaticAtom; has: bool;
  value: string) {.importc: "cha_$1".}
proc hasInsertionStepsForm(element: Element): bool {.importc: "cha_$1".}
proc getElementForm(element: Element): HTMLElement {.importc: "cha_$1".}
proc getFormMethodAttr(element: Element; name: StaticAtom): string {.
  importc: "cha_$1".}
proc newHTMLElementForm(tagType: TagType): HTMLElement {.importc: "cha_$1".}

const VoidElements = {
  ttArea, ttBase, ttBr, ttCol, ttEmbed, ttHr, ttImg, ttInput,
  ttLink, ttMeta, ttSource, ttTrack, ttWbr
}

# Converters
template asNode*[T: NodeObj](x: JSRef[T]): Node =
  Node(x)

template asParentNode*[T: ParentNodeObj](x: JSRef[T]): ParentNode =
  ParentNode(x)

template asRootNode*[T: RootNodeObj](x: JSRef[T]): RootNode =
  RootNode(x)

template asElement*[T: ElementObj](x: JSRef[T]): Element =
  Element(x)

template asSheetElement[T: SheetElementObj](x: JSRef[T]): SheetElement =
  SheetElement(x)

template asHTMLElement*[T: HTMLElementObj](x: JSRef[T]): HTMLElement =
  HTMLElement(x)

template asElementAccessor[T: ElementAccessorObj](x: JSRef[T]):
    ElementAccessor =
  ElementAccessor(x)

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
      it = (it as ParentNode).firstChildShadow
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
    if (let child = child as Element; child != nil):
      yield child

iterator relementList*(node: ParentNode): Element {.inline.} =
  for child in node.rchildList:
    if (let child = child as Element; child != nil):
      yield child

iterator ancestors*(node: Node): Element {.inline.} =
  var element = node.parentElement
  while element != nil:
    yield element
    element = element.asNode.parentElement

# inclusive ancestors
iterator branch*(node: Node): Node {.inline.} =
  var node = node
  while node != nil:
    yield node
    node = node.parentNode.asNode

iterator branchHost(node: Node): Node {.inline.} =
  var node = node.parentNodeHost
  while node != nil:
    yield node
    node = node.parentNodeHost

iterator branchElems*(element: Element): Element {.inline.} =
  var element = element
  while element != nil:
    yield element
    element = element.asNode.parentElement

iterator descendants*(node: ParentNode): Node {.inline.} =
  var it = node.firstChild
  while it != nil:
    yield it
    it = it.nextDescendant(node.asNode)

iterator descendantsShadowIncl(node: Node): Node {.inline.} =
  var it = node
  while it != nil:
    yield it
    it = it.nextDescendantShadow(node)

iterator elementDescendants*(node: ParentNode): Element {.inline.} =
  for child in node.descendants:
    if (let child = child as Element; child != nil):
      yield child

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

iterator sheets(this: SheetElement): CSSStylesheet {.inline.} =
  var sheet = this.sheetHead
  let tail = this.sheetTail
  while sheet != nil:
    yield sheet
    if sheet == tail:
      break
    sheet = sheet.next

proc tabIsEmpty(collection: ptr CollectionLikeObj): bool =
  collection == nil

proc tabKeyEq(collection: ptr CollectionLikeObj; node: Node): bool =
  collection.root == node

proc tabKeyEq(a, b: ptr CollectionLikeObj): bool =
  a == b

proc tabHashFast(collection: ptr CollectionLikeObj): Hash =
  collection.hcache

proc hash(node: Node): Hash =
  hash(cast[pointer](node))

iterator liveCollections(document: Document; node: Node): CollectionLike =
  for it in document.liveCollections.tabGetAll(node):
    yield CollectionLike(it)

# Window/Global
# For now, these are the same; on an API level however, getGlobal is
# guaranteed to be non-null, while getWindow may return null in the
# future.  (This is in preparation for Worker support.)
proc getGlobal*(ctx: JSContext): Window =
  cast[Window](ctx.getOpaque().globalObj)

proc getWindow*(ctx: JSContext): Window =
  cast[Window](ctx.getOpaque().globalObj)

proc getAPIBaseURL(ctx: JSContext): URL {.exportc: "cha_$1".} =
  let window = ctx.getWindow()
  if window == nil or window.document == nil:
    return URL(nil)
  return window.document.baseURL

proc getOrigin(ctx: JSContext): Origin {.exportc: "cha_$1".} =
  ctx.getGlobal().settings.origin

proc consoleError(ctx: JSContext; ss: varargs[string]) {.exportc: "cha_$1".} =
  ctx.getGlobal().console.error(ss)

proc setEvent(ctx: JSContext; event: Event): Event {.exportc: "cha_$1".} =
  let window = ctx.getWindow()
  if window != nil:
    let res = move(window.event)
    window.event = event
    return res
  Event(nil)

const WindowEvents* = [satError, satLoad, satFocus, satBlur]

proc isHTMLElementOf(this: Collection; node: Node): bool =
  let element = node as HTMLElement
  element != nil and element.localName in this.atoms

proc isRowOf(this: Collection; node: Node): bool =
  if node.parentNode.asNode == this.root or
      node.parentNode.parentNode.asNode == this.root:
    return node of HTMLTableRowElement
  false

proc isElement(this: Collection; node: Node): bool =
  node of Element

proc isElementOf(this: Collection; node: Node): bool =
  let node = node as Element
  if node != nil:
    let atom = this.atoms[0]
    if node.namespaceURI == satNamespaceHTML:
      return node.localName == atom or node.tagName.equalsIgnoreCase(atom)
    return node.tagName == atom
  return false

proc isElementWithClass(this: Collection; node: Node): bool =
  let element = node as Element
  if element == nil:
    return false
  for i in 1 ..< this.atoms.len:
    if not element.hasClass(this.atoms[i]):
      return false
  true

proc isLink(this: Collection; node: Node): bool =
  let element = node as HTMLElement
  element != nil and element.tagType in {ttA, ttArea} and
    element.asElement.attrb(satHref)

proc logException(window: Window; url: URL) =
  #TODO excludepassword seems pointless?
  window.console.error("Exception in document",
    url.serialize(excludepassword = true), window.jsctx.getExceptionMsg())

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
    finish(opaque, Response(nil))
    return
  window.loader.fetch(input, finish, opaque)

proc sheetLoaded(window: Window) =
  inc window.loadedSheetNum
  if window.bc != nil:
    sheetLoaded(window.bc)

proc imageLoaded(window: Window) =
  inc window.loadedImageNum
  if window.bc != nil:
    imageLoaded(window.bc)

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
    baseURL: URL; charset: Charset; layer: CAtom;
    finish: LoadSheetFinish; parseEnv: ParseSheetEnv; i: int) =
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
      inc window.remoteSheetNum
      window.loadSheet(this, it.url, charset, it.layer, importSheetFinish,
        i, env)

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

type
  LoadSheetEnv* {.final.} = ref object of BlobOpaque
    window: Window
    this: SheetElement
    url: URL
    finish: LoadSheetFinish
    charset: Charset
    layer: CAtom
    i: int
    parseEnv: ParseSheetEnv

proc mark*(rt: JSRuntime; env: LoadSheetEnv; markFunc: JS_MarkFunc) =
  rt.markObj(env.window, markFunc)
  rt.markObj(env.this, markFunc)
  rt.markObj(env.url, markFunc)

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
    layer: CAtom; finish: LoadSheetFinish; i: int;
    parseEnv: ParseSheetEnv) =
  let env = LoadSheetEnv(
    window: window,
    this: this,
    url: url,
    charset: charset,
    layer: layer,
    parseEnv: parseEnv,
    i: i,
    finish: finish
  )
  window.corsFetch(newRequest(url), loadSheet0, env)

proc loadSheet(window: Window; this: SheetElement; url: URL;
    finish: LoadSheetFinish) =
  let charset = this.asElement.getCharset()
  window.loadSheet(this, url, charset, CAtomNull, finish, 0, nil)

proc loadLinkFinish(window: Window; this: SheetElement;
    res: LoadSheetResult; env: ParseSheetEnv; i: int) =
  let link = this as HTMLLinkElement
  let media = link.asElement.attr(satMedia)
  var applies = true
  if media != "":
    var ctx = initCSSParser(media)
    let media = ctx.parseMediaQueryList(window.settings.attrsp)
    applies = media.applies(addr window.settings)
  # Note: we intentionally load all sheets first and *then* check
  # whether media applies, to prevent media query based tracking.
  #TODO should we really keep the current sheet if the result is nil?
  if res.head != nil:
    link.asSheetElement.updateSheet(res.head, res.tail)
    let disabled = link.isDisabled()
    for sheet in link.asSheetElement.sheets:
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
  let href = link.asElement.attr(satHref)
  if href == "":
    return
  if url := parseURL(href, window.document.url):
    inc window.remoteSheetNum
    window.loadSheet(link.asSheetElement, url, loadLinkFinish)

proc getImageId(window: Window): int =
  result = window.imageId
  inc window.imageId

proc fireEvent*(ctx: JSContext; event: Event; target: EventTarget) =
  discard ctx.dispatch(target, event)

proc fireEvent*(window: Window; event: Event; target: EventTarget) =
  window.jsctx.fireEvent(event, target)

proc fireEvent*(window: Window; name: StaticAtom; target: EventTarget;
    bubbles, cancelable, trusted: bool) =
  let event = newTrustedEvent(name, target, bubbles, cancelable)
  window.fireEvent(event, target)

proc loadImageFinish(opaque: RootRef; response: Response) =
  let cachedURL = CachedURLImage(opaque)
  let window = move(cachedURL.window)
  let shared = move(cachedURL.shared)
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
    contentType: "image/" & cachedURL.subtype,
    vector: cachedURL.subtype == "svg+xml"
  )
  cachedURL.bmp = bmp
  for share in shared:
    share.bitmap = bmp
    share.asElement.invalidate()
    #TODO fire error on error
    if window.settings.scripting != smFalse:
      window.fireEvent(satLoad, share.asEventTarget, bubbles = false,
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
    internal = true
  )
  cachedURL.subtype = subtype
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
  let cachedURL = CachedURLImage(window.imageURLCache.getOrDefault(surl))
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
      image.asElement.invalidate()
      image.bitmap = nil
    image.fetchStarted = false
    return
  if image.fetchStarted:
    return
  image.fetchStarted = true
  let src = image.asElement.attr(satSrc)
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
  var surl = $url
  if window.loadImageFromCache(image, surl):
    return
  let cachedURL = CachedURLImage(
    s: move(surl),
    cacheId: -1,
    window: window,
    expiry: -1,
    loading: true,
    shared: @[image]
  )
  window.imageURLCache.put(cachedURL)
  let headers = newHeaders(hgRequest, {"Accept": "*/*"})
  inc window.remoteImageNum
  let request = newRequest(url, headers = headers)
  window.corsFetch(request, loadImage0, cachedURL)

proc loadSVGFinish(opaque: RootRef; response: Response) =
  let env = CachedSVG(opaque)
  let window = move(env.window)
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
  let bitmap = NetworkBitmap(
    width: width,
    height: height,
    cacheId: env.cacheId,
    imageId: env.imageId,
    contentType: "image/svg+xml",
    vector: true
  )
  for svg in env.shared:
    svg.bitmap = bitmap
    svg.asElement.invalidate()
  window.imageLoaded()

proc loadSVG*(window: Window; svg: SVGSVGElement) =
  if not window.settings.images:
    if svg.bitmap != nil:
      svg.asElement.invalidate()
      svg.bitmap = nil
    svg.fetchStarted = false
    return
  if svg.fetchStarted:
    return
  svg.fetchStarted = true
  var s = svg.asElement.outerHTML
  if s.len <= 4096: # try to dedupe if the SVG is small enough.
    let item = CachedSVG(window.svgCache.getOrDefault(s))
    if item != nil:
      svg.bitmap = item.bmp
      if svg.bitmap != nil: # already decoded
        svg.asElement.invalidate()
      else: # tell me when you're done
        item.shared.add(svg)
      return
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
    body = RequestBody(t: rbtOutput, outputId: svgres.outputId),
    internal = true
  )
  let env = CachedSVG(
    window: window,
    shared: @[svg],
    cacheId: cacheId,
    imageId: imageId
  )
  if s.len <= 4096:
    env.s = move(s)
    window.svgCache.put(env)
  inc window.remoteImageNum
  loader.fetch(request, loadSVGFinish, env)
  loader.close(svgres)

proc navigate*(window: Window; url: URL) =
  if window.bc != nil:
    navigate(window.bc, url)

proc ensureLayout(window: Window; element: Element) =
  if window.bc != nil:
    ensureLayout(window.bc, element)

proc click(window: Window; element: HTMLElement) =
  if window.bc != nil:
    clickCallback(window.bc, element)

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
  if not element.asNode.isConnected():
    return ok(newCSSStyleDeclaration(Element(nil), ""))
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
        return ok(newCSSStyleDeclaration(Element(nil), ""))
  if window.settings.scripting == smApp:
    element.ensureStyle()
    return ok(newCSSStyleDeclaration(element, $element.getComputedStyle(pseudo),
      computed = true, readonly = true))
  # In lite mode, we just parse the "style" attribute and hope for
  # the best.
  ok(newCSSStyleDeclaration(element, element.attr(satStyle), computed = true,
    readonly = true))

# CustomElementRegistry
iterator defs(this: CustomElementRegistry): CustomElementDef =
  var def = this.defsHead
  while def != nil:
    yield def
    def = def.next

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
    if ctx.strictEquals(it.ctor.value, ctor):
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
    ?ctx.fromJSFree(val, callbacks[t])
  ok()

proc define0(ctx: JSContext; this: CustomElementRegistry; name: CAtom;
    ctor, proto: JSValueConst; def: CustomElementDef): Opt[void] =
  if not JS_IsObject(proto):
    JS_ThrowTypeError(ctx, "prototype is not an object")
    return err()
  for t in cctConnected..cctAttributeChanged:
    ?ctx.tryGetCallback(proto, t, def.callbacks)
  if def.callbacks[cctAttributeChanged] != nil:
    ?ctx.tryGetStrSeq(ctor, "observedAttributes", def.observedAttrs)
  var disabled: seq[CAtom]
  ?ctx.tryGetStrSeq(ctor, "disabledFeatures", disabled)
  if satInternals in disabled:
    def.flags.excl(cefInternals)
  if satShadow in disabled:
    def.flags.excl(cefShadow)
  var formAssociated: bool
  discard ?ctx.fromJSGetProp(ctor, "formAssociated", formAssociated)
  if formAssociated:
    def.flags.incl(cefFormAssociated)
    for t in cctFormAssociated..cctFormStateRestore:
      ?ctx.tryGetCallback(proto, t, def.callbacks)
  ok()

proc newCustomElementDef(name, localName: CAtom): CustomElementDef =
  CustomElementDef(
    name: name,
    localName: localName,
    flags: {cefInternals, cefShadow}
  )

proc addScopedDocument(this: CustomElementRegistry; document: Document) =
  if document notin this.scopedDocuments:
    this.scopedDocuments.add(document)

jsClassDef(CustomElementRegistry):
  proc newCustomElementRegistry*(): CustomElementRegistry {.jsctor.} =
    jsNew CustomElementRegistryObj(scoped: true)

  proc mark(rt: JSRuntime; this: CustomElementRegistry; markFunc: JS_MarkFunc)
      {.jsmark.} =
    for def in this.defs:
      JS_MarkValue(rt, def.ctor.value, markFunc)
      for cb in def.callbacks.myitems:
        if cb != nil:
          JS_MarkValue(rt, cb.value, markFunc)
    for document in this.scopedDocuments:
      rt.markObj(document, markFunc)

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
      return JS_EXCEPTION
    def.ctor = ctx.dupTraceObj(ctor)
    if this.defsTail == nil:
      this.defsHead = def
    else:
      this.defsTail.next = def
    this.defsTail = def
    #TODO is scoped
    #TODO upgrade
    #TODO when-defined
    return JS_UNDEFINED

  proc get(ctx: JSContext; this: CustomElementRegistry; name: CAtom):
      JSValue {.jsfunc.} =
    let def = this.find(name)
    if def != nil:
      return JS_DupValue(ctx, def.ctor.value)
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
    if node of Document:
      return "Document"
    result = ""
    result.serializeFragmentInner(node, ttUnknown, writeShadow = true)

proc document*(node: Node): Document =
  # Return the owner document, or node itself if it is a document.
  var node = (ptr NodeObj)(node) # skip some refcounts
  while true:
    if node.parentNode != nil:
      node = (ptr NodeObj)(node.parentNode.lastChild.internalNext)
    if Node(node) of Document:
      break
    if not (Node(node) of ShadowRoot):
      return node.internalNext as Document
    node = (ptr NodeObj)(ShadowRoot(node).host)
  cast[Document](node)

proc parentNodeShadow(node: Node): lent Node =
  if node.parentNode == nil:
    let shadow = node as ShadowRoot
    if shadow != nil:
      return shadow.host.asNode
  return node.parentNode.asNode

proc parentNodeHost(node: Node): Node =
  let parent = node.parentNode
  if parent == nil:
    let shadow = node as DocumentFragment
    if shadow != nil:
      return shadow.host.asNode
  return parent.asNode

proc nextSiblingShadow(node: Node): lent Node =
  let next = node.internalNext
  if next == nil:
    # node is a Document.
    return node.internalNext
  if next.parentNode == nil:
    # next is the root, return nil.
    return next.parentNode.asNode
  return node.internalNext

# performance-sensitive, so we inline this with a template
template nextDescendantExclImpl(node, start: Node): Node =
  # climb up until we find a non-last leaf (this might be node itself)
  var it = node
  while it != start:
    let next = it.nextSibling
    if next != nil:
      return next
    it = it.parentNode.asNode
  # done
  Node(nil)

# Return the next descendant if it isn't `start', and nil otherwise.
# Note: `start' must be either an ancestor of `node', `node` itself, or nil.
#TODO start should be ParentNode
proc nextDescendant(node, start: Node): Node =
  let parent = node as ParentNode
  if parent != nil:
    let first = parent.firstChild
    if first != nil:
      return first
  node.nextDescendantExclImpl(start)

# Like nextDescendant, but skip children when `skip` is true.
proc nextDescendant(node, start: Node; skip: bool): Node =
  if not skip and (let node = node as ParentNode; node != nil):
    let first = node.firstChild
    if first != nil:
      return first
  node.nextDescendantExclImpl(start)

proc nextDescendantShadow(node, start: Node): Node =
  if (let node = node as ParentNode; node != nil):
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
  Node(nil)

proc nextElementDescendantShadow(element: Element; start: Node): Element =
  var node = element.asNode
  while true:
    node = node.nextDescendantShadow(start)
    if node == nil:
      break
    let element = node as Element
    if element != nil:
      return element
  Element(nil)

proc previousDescendant(node: Node): Node =
  var prev = node.previousSibling
  if prev == nil:
    return node.parentNode.asNode
  while (let pnode = prev as ParentNode; pnode != nil):
    if pnode.firstChild == nil:
      break
    prev = pnode.lastChild
  prev

proc previousDescendant(node, start: Node): Node =
  if node == start:
    return Node(nil)
  node.previousDescendant()

proc nodeTypeEnum(node: Node): NodeType =
  if node of CDATASection:
    return ntCdataSection
  elif node of Comment:
    return ntComment
  elif node of Text:
    return ntText
  elif node of Element:
    return ntElement
  elif node of Document:
    return ntDocument
  elif node of DocumentType:
    return ntDocumentType
  elif node of Attr:
    return ntAttribute
  elif node of DocumentFragment:
    return ntDocumentFragment
  else: # ProcessingInstruction
    return ntProcessingInstruction

proc isValidChild(node: Node): bool =
  return node of Element or node of CharacterData or
    node of DocumentFragment or node of DocumentType

proc checkParentValidity(parent: Node): Result[ParentNode, cstring] =
  if (let parent = parent as ParentNode; parent != nil):
    return ok(parent)
  return err("parent must be a document, a document fragment, or an element")

proc rootNode(node: Node): Node =
  # If connected, return root; otherwise, return the owner document.
  let parent = node.parentNode
  if parent == nil:
    return node
  parent.lastChild.internalNext

proc rootNodeShadow(node: Node): Node =
  var node = node.rootNode
  while (let shadow = node as ShadowRoot; shadow != nil):
    node = shadow.host.asNode.rootNode
  node

proc isInclusiveAncestorHost(a, b: Node): bool =
  for it in b.branchHost:
    if it == a:
      return true
  return false

proc textContent*(node: Node): string =
  var res = ""
  if (let characterData = node as CharacterData; characterData != nil):
    res = characterData.data.s
  elif (let node = node as ParentNode; node != nil):
    for child in node.childList:
      if not (child of Comment):
        res &= child.textContent
  move(res)

proc inSameTree*(a, b: Node): bool =
  assert a != nil
  assert b != nil
  a.rootNode == b.rootNode

# a == b or a in b's ancestors
proc contains*(a, b: Node): bool =
  for node in b.branch:
    if node == a:
      return true
  return false

type ObserverItem = object
  observer: MutationObserver
  oldValue: bool

proc find(observers: openArray[ObserverItem]; observer: MutationObserver):
    int =
  for i in 0 ..< observers.len:
    if observers[i].observer == observer:
      return i
  -1

#TODO put this in runtime opaque
var pendingObservers {.global.}: seq[MutationObserver]
var mutationJobQueued {.global.}: bool

proc mutationJob(ctx: JSContext; argc: cint; argv: JSValueConstArray):
    JSValue {.cdecl.} =
  mutationJobQueued = false
  let observers = move(pendingObservers)
  #TODO signal slots
  for observer in observers:
    let records = move(observer.records)
    #TODO remove transient registered observers for observer.nodes
    if records.len > 0:
      let records = ctx.toJS(records)
      if JS_IsException(records):
        return records
      let this = ctx.toJS(observer) # cannot fail
      #TODO invoke (with all the ceremony that entails)
      let callback = JS_DupValue(ctx, observer.callback.value)
      let res = ctx.callSinkThisFree(callback, this, records)
      if JS_IsException(res):
        return res
      JS_FreeValue(ctx, res)
  return JS_UNDEFINED

proc queueMutationJob(ctx: JSContext) =
  if not mutationJobQueued:
    if ctx.enqueueJob(mutationJob) >= 0:
      mutationJobQueued = true

proc queueMutationRecord(target: Node; ctx: JSContext; t: MutationRecordType;
    name, namespace: CAtom; oldValue: RefString; hasOldValue2: bool;
    oldValue2: string; added, removed: openArray[Node];
    previousSibling, nextSibling: Node) =
  if ctx.getOpaque() == nil:
    return # no scripting
  # the oldValue mess is a workaround to the fact that we can pass the old
  # data from CharacterData but not from AttrData.  but maybe AttrData
  # should be refcounted too...
  var observers: seq[ObserverItem] = @[]
  #TODO can we do this without actually traversing ancestors somehow?
  # (maybe link the last observer with parent's first observer?)
  for it in target.branch:
    for el in target.asEventTarget.mutationObservers:
      var oldValue = false
      if oifSubtree notin el.flags and it != target:
        continue
      case t
      of mrtAttributes:
        if oifAttributes notin el.flags or
            oifAttributeFilter in el.flags and (namespace != CAtomNull or
            name notin el.attributeFilter):
          continue
        oldValue = oifAttributeOldValue in el.flags
      of mrtCharacterData:
        if oifCharacterData notin el.flags:
          continue
        oldValue = oifCharacterDataOldValue in el.flags
      of mrtChildList:
        if oifChildList notin el.flags:
          continue
      let i = observers.find(el.observer)
      if i < 0:
        observers.add(ObserverItem(observer: el.observer, oldValue: oldValue))
      elif oldValue:
        observers[i].oldValue = true
  for it in observers:
    let oldValue = if it.oldValue:
      if hasOldValue2:
        newRefString(oldValue2)
      else:
        oldValue
    else:
      nil
    let addedNodes = newNodeList(added)
    let removedNodes = newNodeList(removed)
    it.observer.queueRecord(target.asEventTarget, t, name, namespace, oldValue,
      addedNodes.asRootRef, removedNodes.asRootRef,
      previousSibling.asEventTarget, nextSibling.asEventTarget)
    pendingObservers.add(it.observer)
  ctx.queueMutationJob()

proc queueTreeMutationRecord(parent: ParentNode; ctx: JSContext;
    added, removed: openArray[Node]; previousSibling, nextSibling: Node) =
  parent.asNode.queueMutationRecord(ctx, mrtChildList, CAtomNull,
    CAtomNull, nil, true, "", added, removed, previousSibling,
    nextSibling)

type PreInsertExclude = enum
  pieNone, pieBefore, pieChildren

proc canInsertIntoDocument(parent: ParentNode; node, before: Node;
    t: NodeType; excl: PreInsertExclude): bool =
  var beforeSeen = false
  for child in parent.childList:
    if (before == nil or t == ntElement) and child of Element or
        t == ntDocumentType and child of DocumentType:
      if excl == pieNone or excl == pieBefore and child != before:
        return false # document would have two element/doctype children
    if beforeSeen and t == ntElement and child of DocumentType:
      return false # a doctype is following before
    if child == before:
      beforeSeen = true
  if before != nil:
    if t == ntDocumentType:
      return before.previousElementSiblingImpl == nil
    # if excl is before or children, then before must have been excluded,
    # so its type does not matter
    if excl == pieNone and before of DocumentType:
      return false
  return true

# Note: the ordering of the arguments in the standard is whack so this
# doesn't match that.  Also, in the spec, "before" is called "child".
proc checkPreInsertValidity(parent, node, before: Node;
    excl: PreInsertExclude): Result[ParentNode, cstring] =
  let parent = ?parent.checkParentValidity()
  if node.isInclusiveAncestorHost(parent.asNode):
    return err("parent must be an ancestor")
  if before != nil and before.parentNode != parent:
    return err(nil)
  if not node.isValidChild():
    return err("node is not a valid child")
  if parent of Document:
    if (let node = node as DocumentFragment; node != nil):
      var elemSeen = false
      for child in node.asParentNode.childList:
        if child of Element:
          if elemSeen:
            return err("cannot insert two elements into document")
          if not parent.canInsertIntoDocument(node.asNode, before, ntElement,
              excl):
            return err("cannot insert fragment into document here")
          elemSeen = true
        if child of Text:
          return err("cannot insert text into document")
    elif (let node = node as Element; node != nil):
      if not parent.canInsertIntoDocument(node.asNode, before, ntElement,
          excl):
        return err("cannot insert element into document here")
    elif (let node = node as DocumentType; node != nil):
      if not parent.canInsertIntoDocument(node.asNode, before, ntDocumentType,
          excl):
        return err("cannot insert document type before an element node")
    elif node of Text:
      return err("cannot insert text into document")
    else: discard
  elif node of DocumentType:
    return err("document type can only be inserted into document")
  ok(parent)

# Pass an index to avoid searching for the node in parent's child list.
proc removeImpl*(node: Node; ctx: JSContext; suppressObservers = false) =
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
  let element = node as Element
  let parentElement = node.parentElement
  if parentElement != nil:
    parentElement.invalidate()
  else:
    # we're removing all elements; the document must still be invalidated
    document.invalid = true
  var prev = node.internalPrev # we turn this into previousSibling
  let next = node.internalNext
  let oldNextSibling = node.nextSibling
  if next != nil and next.parentNode != nil:
    next.internalPrev = prev
  else:
    parent.firstChild.internalPrev = prev
  if parent.firstChild == node:
    prev = Node(nil)
    if next != nil and next.parentNode != nil:
      parent.setFirstChild(next)
    else:
      parent.setFirstChild(Node(nil))
  else:
    prev.internalNext = next
  node.internalPrev = Node(nil)
  node.internalNext = document.asNode
  node.parentNode = ParentNode(nil)
  document.invalidateCollections()
  if element != nil:
    if parentElement != nil and next.parentNode == parent:
      parentElement.flags.incl(efChildElIndicesInvalid)
    element.setMagic(0)
  #TODO assigned
  if oldRootNode of ShadowRoot:
    let shadow = ShadowRoot(oldRootNode)
    discard shadow
    #TODO signal slot change if parent is slot without assigned nodes
  let parentConnected = oldRootNode.isConnected
  let oldRootDocumentLike = oldRootNode as RootNode
  for desc in node.descendantsShadowIncl:
    #TODO assign slottables with parent's root & node
    let last = desc.lastChild
    if last != nil and last.internalNext == oldRootNode: # update root
      last.internalNext = node
    if (let element = desc as Element; element != nil):
      if element.id != satUempty:
        # try to remove from the old root; this might not do anything if
        # this is a descendant of a shadow root
        if oldRootDocumentLike != nil:
          oldRootDocumentLike.removeElementId(element)
      document.applyStyleDependencies(element, DependencyInfo.default)
      element.removingSteps()
      if element.custom == cesCustom and parentConnected:
        discard #TODO queue disconnectedCallback
  #TODO transient registered observers
  if not suppressObservers:
    parent.queueTreeMutationRecord(ctx, [], [node], prev, oldNextSibling)
  #TODO children changed steps

# e may be nil
proc insertThrow*(ctx: JSContext; e: cstring): JSValue =
  if e == nil:
    return JS_ThrowDOMException(ctx, "NotFoundError",
      "reference node is not a child of parent")
  return JS_ThrowDOMException(ctx, "HierarchyRequestError", e)

# before may be nil
proc insertBefore(parent: Node; ctx: JSContext; node, before: Node):
    Err[cstring] =
  let parent = ?parent.checkPreInsertValidity(node, before, pieNone)
  let referenceChild = if before == node:
    node.nextSibling
  else:
    before
  parent.insert(ctx, node, referenceChild)
  ok()

proc insertBeforeUndefined*(ctx: JSContext; parent, node: Node;
    before: NodeNil): JSValue =
  let res = parent.insertBefore(ctx, node, before.get)
  if res.isErr:
    return ctx.insertThrow(res.error)
  return JS_UNDEFINED

proc append*(parent: ParentNode; ctx: JSContext; node: Node) =
  parent.insert(ctx, node, Node(nil))

# Replace child with node.
# Note: the argument ordering here is the opposite of replaceChild.
proc replaceChildWith*(parent: Node; ctx: JSContext; child, node: Node):
    Err[cstring] =
  let parent = ?parent.checkPreInsertValidity(node, child, pieBefore)
  let childNextSibling = child.nextSibling
  let childPreviousSibling = child.previousSibling
  let referenceChild = if childNextSibling == node:
    node.nextSibling
  else:
    childNextSibling
  parent.asNode.document.adopt(node, ctx)
  var removedIdx = -1
  if child.parentNode != nil:
    removedIdx = 0
  var nodes: seq[Node] = @[]
  let fragment = node as DocumentFragment
  if fragment != nil:
    nodes = fragment.asParentNode.getChildList()
  child.removeImpl(ctx, suppressObservers = true)
  parent.insert(ctx, node, referenceChild, suppressObservers = true)
  if fragment != nil:
    parent.queueTreeMutationRecord(ctx, nodes, [child], childPreviousSibling,
      referenceChild)
  else:
    parent.queueTreeMutationRecord(ctx, [node],
      [child].toOpenArray(0, removedIdx), childPreviousSibling,
      referenceChild)
  ok()

proc replaceChildWithThrow*(ctx: JSContext; parent, child, node: Node):
    JSValue =
  let res = parent.replaceChildWith(ctx, child, node)
  if res.isErr:
    return ctx.insertThrow(res.error)
  return JS_UNDEFINED

proc clone(node: Node; document: Document; deep: bool;
    fallbackRegistry: CustomElementRegistry): Node =
  let copy = if (let element = node as Element; element != nil):
    #TODO is value
    let x = document.newElement(element.localName, element.namespaceURI,
      element.tagName)
    x.id = element.id
    x.name = element.name
    x.classList = element.classList
    x.attrs = element.attrs
    # Cloning steps
    if (let x = x as HTMLScriptElement; x != nil):
      let element = element as HTMLScriptElement
      x.alreadyStarted = element.alreadyStarted
    else:
      cloningStepsForm(element, x)
    x.asNode
  elif (let attr = node as Attr; attr != nil):
    newAttr(attr.asNode.document, attr.data).asNode
  elif (let node = node as Text; node != nil):
    if node of CDATASection:
      document.newCDATASection(newRefString(node.data.s)).asNode
    else:
      document.newText(node.data.s).asNode
  elif (let node = node as Comment; node != nil):
    document.newComment(newRefString(node.data.s)).asNode
  elif (let node = node as ProcessingInstruction; node != nil):
    let clone = document.newProcessingInstruction(node.target,
      newRefString(node.data.s))
    clone.asNode
  elif (let document = node as Document; document != nil):
    let x = newDocument(document.url)
    x.charset = document.charset
    x.contentType = document.contentType
    x.origin = document.origin
    x.quirksMode = document.quirksMode
    x.asNode
  elif (let node = node as DocumentType; node != nil):
    document.newDocumentType(node.name, node.publicId, node.systemId).asNode
  elif node of DocumentFragment:
    document.newDocumentFragment().asNode
  else:
    assert false
    Node(nil)
  copy

proc cloneNodeImpl(ctx: JSContext; node: Node; document: Document; deep: bool;
    parent: ParentNode; fallbackRegistry: CustomElementRegistry): Opt[Node] =
  let copy = node.clone(document, deep, fallbackRegistry)
  if copy == nil:
    JS_ThrowOutOfMemory(ctx)
    return err()
  if parent != nil:
    parent.append(ctx, copy)
  if deep:
    let node = node as ParentNode
    if node != nil:
      for child in node.childList:
        discard ?ctx.cloneNodeImpl(child, document, deep, copy as ParentNode,
          fallbackRegistry)
  if (let element = node as Element; element != nil):
    let shadow = element.shadowRoot
    if shadow != nil:
      let customElements = shadow.globalCustomElements
      let copyShadow = ?ctx.attachShadow(copy as Element, ShadowRootInit(
        mode: shadow.mode,
        serializable: shadow.serializable,
        delegatesFocus: shadow.delegatesFocus,
        slotAssignment: shadow.slotAssignment,
        customElementRegistry: customElements
      ))
      copyShadow.declarative = shadow.declarative
      copyShadow.unsetCustomElements = shadow.unsetCustomElements
      for child in shadow.asParentNode.childList:
        discard ?ctx.cloneNodeImpl(child, document, deep = true,
          copyShadow.asParentNode, CustomElementRegistry(nil))
  ok(copy)

proc previousElementSiblingImpl(this: Node): Element =
  for it in this.precedingSiblings:
    if (let element = it as Element; element != nil):
      return element
  Element(nil)

proc nextElementSiblingImpl(this: Node): Element =
  for it in this.subsequentSiblings:
    if (let element = it as Element; element != nil):
      return element
  Element(nil)

proc serializeFragmentInner(res: var string; child: Node; parentType: TagType;
    writeShadow: bool) =
  if (let element = child as Element; element != nil):
    const LocalNamespace = [
      satNamespaceHTML, satNamespaceMathML, satNamespaceSVG
    ]
    let tag = if element.namespaceURI in LocalNamespace:
      element.localName
    else:
      element.tagName
    res &= '<'
    res &= $tag
    #TODO custom elements
    for attr in element.attrs:
      res &= ' '
      let namespace = attr.namespace.toStaticAtom()
      var local = false
      case namespace
      of satNamespaceXML:
        res &= "xml:"
        local = true
      of satNamespaceXMLNS:
        if not attr.name.matchesLocalName(satXmlns.view()):
          res &= "xmlns:"
        local = true
      of satNamespaceXLink:
        res &= "xlink:"
        local = true
      else:
        res &= $attr.name
      if local:
        let i = attr.name.find(':') + 1
        res &= ($attr.name).substr(i)
      res &= "=\"" & attr.value.htmlEscape(mode = emAttribute) & "\""
    res &= '>'
    res.serializeFragment(element.asNode, writeShadow)
    res &= "</" & $tag & '>'
  elif (let text = child as Text; text != nil):
    const LiteralTags = {
      ttStyle, ttScript, ttXmp, ttIframe, ttNoembed, ttNoframes,
      ttPlaintext, ttNoscript
    }
    if parentType in LiteralTags:
      res &= text.data.s
    else:
      res &= text.data.s.htmlEscape(mode = emText)
  elif (let comment = child as Comment; comment != nil):
    res &= "<!--" & comment.data.s & "-->"
  elif (let inst = child as ProcessingInstruction; inst != nil):
    res &= "<?" & inst.target & " " & inst.data.s & '>'
  elif (let child = child as DocumentType; child != nil):
    res &= "<!DOCTYPE " & child.name & '>'

proc serializeFragment(res: var string; node: Node; writeShadow: bool) =
  var node = node
  var parentType = ttUnknown
  if (let element = node as Element; element != nil):
    const Extra = {ttBasefont, ttBgsound, ttFrame, ttKeygen, ttParam}
    if element.tagType in VoidElements + Extra:
      return
    if (let templ = element as HTMLTemplateElement; templ != nil):
      node = templ.content.asNode
    else:
      parentType = element.tagType
      if parentType == ttNoscript and not element.scriptingEnabled:
        # Pretend parentType is not noscript, so we do not append literally
        # in serializeFragmentInner.
        parentType = ttUnknown
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
        res.serializeFragment(shadow.asNode, writeShadow)
        res &= "</template>"
  if (let node = node as ParentNode; node != nil):
    for child in node.childList:
      res.serializeFragmentInner(child, parentType, writeShadow)

proc serializeFragment*(node: Node; writeShadow: bool): string =
  result = ""
  result.serializeFragment(node, writeShadow)

proc findAncestor*(node: Node; tagType: TagType): Element =
  for element in node.ancestors:
    if element.tagType == tagType:
      return element
  return Element(nil)

proc assignSlot(node: Node) =
  discard

proc getLiveCollection*(node: Node; name: CollectionName): CollectionLike =
  # Returns the live collection with magic `name' rooted at `node'.
  let document = node.document
  for collection in document.liveCollections(node):
    if collection.getMagic() == uint32(name):
      return collection
  CollectionLike(nil)

proc getHTMLCollection*(node: ParentNode; match: CollectionMatchFun;
    mode: CollectionMode; name: CollectionName): HTMLCollection =
  let collection = node.asNode.getLiveCollection(name)
  if collection != nil:
    return collection as HTMLCollection
  newHTMLCollection(node.asNode, match, mode, name)

proc childrenImpl(node: ParentNode): HTMLCollection =
  node.getHTMLCollection(isElement, cmChildren, cnChildren)

proc isDefaultPassive(target: EventTarget): bool {.exportc: "cha_$1".} =
  let node = target as Node
  if node == nil:
    return false
  #TODO what with Window?
  let document = node.document
  return document.asEventTarget == target or
    document.documentElement.asEventTarget == target or
    document.findFirst(ttBody).asEventTarget == target

proc getParentImpl(eventTarget: EventTarget; isLoad: bool): EventTarget {.
    exportc: "cha_$1".} =
  let node = eventTarget as Node
  if node != nil:
    let document = node as Document
    if document != nil:
      if isLoad:
        return EventTarget(nil)
      # if no browsing context, then window will be nil anyway
      return document.window.asEventTarget
    if eventTarget of ShadowRoot:
      let shadow = ShadowRoot(eventTarget)
      #TODO composed
      return shadow.host.asEventTarget
    return node.parentNode.asEventTarget
  return EventTarget(nil)

type GetRootNodeOptions {.pure.} = object of JSDict
  composed {.jsdefault.}: bool

jsClassDef(Node):
  jsextends EventTargetDef

  event.nodeClassID = classDef.id

  jsget Node, parentNode

  proc baseURI(node: Node): string {.jsfget.} =
    return $node.document.baseURL

  proc getRootNode(node: Node; options = GetRootNodeOptions()): Node
      {.jsfunc.} =
    if options.composed:
      return node.rootNodeShadow
    node.rootNode

  proc parentElement*(node: Node): Element {.jsfget.} =
    node.parentNode as Element

  proc nextSibling(node: Node): Node {.jsfget.} =
    if node.parentNode == nil:
      # if parent is nil, then may be a shadow root
      return Node(nil)
    return node.nextSiblingShadow

  proc previousSibling*(node: Node): Node {.jsfget.} =
    if node.parentNode == nil or node == node.parentNode.firstChild:
      return Node(nil)
    return node.internalPrev

  proc ownerDocument(node: Node): Document {.jsfget.} =
    if node of Document:
      return Document(nil)
    return node.document

  proc nodeType(node: Node): uint16 {.jsfget.} =
    return uint16(node.nodeTypeEnum)

  proc nodeName(ctx: JSContext; node: Node): JSValue {.jsfget.} =
    if (let node = node as Element; node != nil):
      return ctx.toJS(node.tagName)
    if (let node = node as Attr; node != nil):
      return ctx.toJS(node.data.name)
    if (let node = node as DocumentType; node != nil):
      return ctx.toJS(node.name)
    if node of CDATASection:
      return JS_NewString(ctx, "#cdata-section")
    if node of Comment:
      return JS_NewString(ctx, "#comment")
    if node of Document:
      return JS_NewString(ctx, "#document")
    if node of DocumentFragment:
      return JS_NewString(ctx, "#document-fragment")
    if (let node = node as ProcessingInstruction; node != nil):
      return ctx.toJS(node.target)
    return JS_NewString(ctx, "#text")

  proc nodeValue(ctx: JSContext; node: Node): JSValue {.jsfget.} =
    if (let node = node as CharacterData; node != nil):
      return ctx.toJS(node.data)
    elif (let node = node as Attr; node != nil):
      return ctx.toJS(node.data.value)
    return JS_NULL

  proc textContent(ctx: JSContext; node: Node): JSValue {.jsfget.} =
    if node of Document or node of DocumentType:
      return JS_NULL
    return ctx.toJS(node.textContent)

  proc isConnected*(node: Node): bool {.jsfget.} =
    return node.rootNodeShadow of Document

  proc contains(a: Node; b: NodeNil): bool {.jsfunc.} =
    let b = b.get
    if b == nil:
      return false
    a.contains(b)

  proc firstChild(node: Node): Node {.jsfget.} =
    if (let node = node as ParentNode; node != nil):
      return node.firstChild
    Node(nil)

  proc lastChild(node: Node): Node {.jsfget.} =
    if (let node = node as ParentNode; node != nil):
      return node.lastChild
    Node(nil)

  proc hasChildNodes(node: Node): bool {.jsfunc.} =
    return node.firstChild != nil

  proc removeChild(ctx: JSContext; parent, node: Node): JSValue {.jsfunc.} =
    if node.parentNode.asNode != parent:
      return ctx.insertThrow(nil)
    node.removeImpl(ctx)
    return ctx.toJS(node)

  proc insertBefore(ctx: JSContext; parent, node: Node; before: NodeNil):
      JSValue {.jsfunc.} =
    let res = parent.insertBefore(ctx, node, before.get)
    if res.isErr:
      return ctx.insertThrow(res.error)
    return ctx.toJS(node)

  proc appendChild(ctx: JSContext; parent, node: Node): JSValue {.jsfunc.} =
    return ctx.insertBefore(parent, node, jsNull(Node))

  # Warning: the ordering is counter-intuitive here.
  proc jsReplaceChild(ctx: JSContext; parent, node, child: Node): JSValue {.
      jsfunc: "replaceChild".} =
    let res = parent.replaceChildWith(ctx, child, node)
    if res.isErr:
      return ctx.insertThrow(res.error)
    return ctx.toJS(child)

  proc cloneNode(ctx: JSContext; node: Node; deep = false): Opt[Node]
      {.jsfunc.} =
    if node of ShadowRoot:
      JS_ThrowDOMException(ctx, "NotSupportedError",
        "cannot clone shadow roots")
      return err()
    ctx.cloneNodeImpl(node, node.document, deep, ParentNode(nil),
      CustomElementRegistry(nil))

  proc isSameNode(node, other: Node): bool {.jsfunc.} =
    return node == other

  proc childNodes(node: Node): NodeList {.jsfget.} =
    var list = node.getLiveCollection(cnChildNodes) as NodeList
    if list == nil:
      list = newNodeList(node, match = nil, cmChildren, cnChildNodes)
    move(list)

  proc isEqualNode(node, other: Node): bool {.jsfunc.} =
    if (let node = node as DocumentType; node != nil):
      let other = other as DocumentType
      if other == nil:
        return false
      if node.name != other.name or node.publicId != other.publicId or
          node.systemId != other.systemId:
        return false
    elif (let node = node as ParentNode; node != nil):
      if (let node = node as Element; node != nil):
        let other = other as Element
        if other == nil:
          return false
        if node.namespaceURI != other.namespaceURI or
            node.tagName != other.tagName or node.attrs.len != other.attrs.len:
          return false
        for i, attr in node.attrs.mypairs:
          if attr != other.attrs[i]:
            return false
      elif node of Document and not (other of Document):
        return false
      elif node of DocumentFragment and not (other of DocumentFragment):
        return false
      var it = other.firstChild
      for child in node.childList:
        if it == nil or not child.isEqualNode(it):
          return false
        it = it.nextSibling
    elif (let node = node as Attr; node != nil):
      let other = other as Attr
      if other == nil or node.data != other.data:
        return false
    elif (let node = node as ProcessingInstruction; node != nil):
      let other = other as ProcessingInstruction
      if other == nil or node.target != other.target or
          node.data.s != other.data.s:
        return false
    elif (let node = node as CharacterData; node != nil):
      let other = other as CharacterData
      if other == nil or not node.sameClass(other):
        return false
      return node.data.s == other.data.s
    true

  proc setNodeValue(ctx: JSContext; node: Node; data: DOMStringNull): Opt[void]
      {.jsfset: "nodeValue".} =
    if (let node = node as CharacterData; node != nil):
      ctx.setData(node, data)
    elif (let node = node as Attr; node != nil):
      ctx.setValue(node, data)
    return ok()

  proc setTextContent(ctx: JSContext; node: Node; data: DOMStringNull):
      Opt[void] {.jsfset: "textContent".} =
    if node of Element or node of DocumentFragment:
      let node = node as ParentNode
      node.replaceAll(ctx, data)
      return ok()
    return ctx.setNodeValue(node, data)

#TODO mixin?
proc toNodes(ctx: JSContext; nodes: openArray[JSValueConst];
    res: var seq[Node]): Opt[void] =
  for it in nodes:
    var node: Node
    if ctx.fromJS(it, node).isOk:
      res.add(node)
    else:
      var ds: DOMString
      ?ctx.fromJS(it, ds)
      let text = ctx.newText(ds)
      if text == nil:
        JS_ThrowOutOfMemory(ctx)
        return err()
      res.add(text.asNode)
  ok()

proc toNode(ctx: JSContext; nodes: openArray[Node]; document: Document): Node =
  if nodes.len == 1:
    return nodes[0]
  let fragment = document.newDocumentFragment()
  if fragment != nil:
    for node in nodes:
      fragment.asParentNode.append(ctx, node)
  fragment.asNode

proc toNode(ctx: JSContext; argv: openArray[JSValueConst];
    document: Document): Opt[Node] =
  var nodes: seq[Node] = @[]
  ?ctx.toNodes(argv, nodes)
  let fragment = ctx.toNode(nodes, document)
  if fragment == nil:
    JS_ThrowOutOfMemory(ctx)
    return err()
  ok(fragment)

proc prependImpl(ctx: JSContext; parent: Node; nodes: openArray[JSValueConst]):
    JSValue =
  let node = ?ctx.toNode(nodes, parent.document)
  return ctx.insertBeforeUndefined(parent, node, jsNull(parent.firstChild))

proc appendImpl(ctx: JSContext; parent: Node; nodes: openArray[JSValueConst]):
    JSValue =
  let node = ?ctx.toNode(nodes, parent.document)
  return ctx.insertBeforeUndefined(parent, node, jsNull(Node))

proc replaceChildrenImpl(ctx: JSContext; parent: Node;
    nodes: openArray[JSValueConst]): JSValue =
  let node = ?ctx.toNode(nodes, parent.document)
  let x = parent.checkPreInsertValidity(node, Node(nil), pieChildren)
  if x.isErr:
    return ctx.insertThrow(x.error)
  let parent = x.get
  parent.replaceAll(ctx, node)
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
    parent.insert(ctx, node, before)
  ok()

proc afterImpl(ctx: JSContext; this: Node; argv: varargs[JSValueConst]):
    Opt[void] =
  var nodes: seq[Node]
  ?ctx.toNodes(argv, nodes)
  let parent = this.parentNode
  if parent != nil:
    let before = this.nextSiblingExcept(nodes)
    let node = ctx.toNode(nodes, this.document)
    parent.insert(ctx, node, before)
  ok()

proc replaceWithImpl(ctx: JSContext; this: Node; argv: varargs[JSValueConst]):
    JSValue =
  var nodes: seq[Node]
  ?ctx.toNodes(argv, nodes)
  let parent = this.parentNode
  if parent != nil:
    let before = this.nextSiblingExcept(nodes)
    let node = ctx.toNode(nodes, this.document)
    if this.parentNode == parent:
      return ctx.replaceChildWithThrow(parent.asNode, this, node)
    parent.insert(ctx, node, before)
  return JS_UNDEFINED

# ParentNode
proc firstChild(parent: ParentNode): lent Node =
  let child = parent.internalFirst
  if child != nil and child.parentNode == nil:
    when defined(debug):
      assert child of ShadowRoot
    return child.internalNext
  return parent.internalFirst

proc firstChildShadow(parent: ParentNode): lent Node =
  return parent.internalFirst

proc setFirstChild(node: ParentNode; child: Node) =
  let first = node.internalFirst
  if first != nil and first.parentNode == nil: # shadow root
    first.internalNext = child
  else:
    node.internalFirst = child

proc lastChild*(parent: ParentNode): lent Node =
  let first = parent.internalFirst
  if first == nil:
    return parent.internalFirst
  if first.parentNode == nil:
    # skip shadow root
    let next = first.internalNext
    if next == nil:
      return first.internalNext
    return next.internalPrev
  return first.internalPrev

proc lastChildBefore*(parent: ParentNode; before: Node): Node =
  if before != nil:
    before.previousSibling
  else:
    parent.lastChild

proc firstElementChild*(node: ParentNode): Element =
  for child in node.elementList:
    return child
  return Element(nil)

proc lastElementChild*(node: ParentNode): Element =
  for child in node.relementList:
    return child
  return Element(nil)

proc findFirstChildOf(node: ParentNode; tagType: TagType): Element =
  for element in node.elementList:
    if element.tagType == tagType:
      return element
  return Element(nil)

proc findFirstChildOf(node: ParentNode; localName, namespace: StaticAtom):
    Element =
  for element in node.elementList:
    if element.localName == localName and element.namespaceURI == namespace:
      return element
  return Element(nil)

proc findLastChildOf(node: ParentNode; tagType: TagType): Element =
  for element in node.relementList:
    if element.tagType == tagType:
      return element
  return Element(nil)

proc findFirstChildNotOf(node: ParentNode; tagType: set[TagType]): Element =
  for element in node.elementList:
    if element.tagType notin tagType:
      return element
  return Element(nil)

proc getChildList*(node: ParentNode): seq[Node] =
  result = @[]
  for child in node.childList:
    result.add(child)

proc replaceAll(parent: ParentNode; ctx: JSContext; node: Node) =
  let removedNodes = parent.getChildList()
  for child in removedNodes:
    child.removeImpl(ctx, true)
  if node != nil:
    if (let fragment = node as DocumentFragment; fragment != nil):
      let nodes = fragment.asParentNode.getChildList()
      for it in nodes:
        parent.insert(ctx, it, Node(nil), suppressObservers = true)
    else:
      parent.insert(ctx, node, Node(nil), suppressObservers = true)
  if node != nil:
    parent.queueTreeMutationRecord(ctx, [node], removedNodes, Node(nil),
      Node(nil))
  elif removedNodes.len > 0:
    parent.queueTreeMutationRecord(ctx, [], removedNodes, Node(nil), Node(nil))

proc replaceAll*(parent: ParentNode; ctx: JSContext; ds: DOMString) =
  let text = if ds.len > 0: parent.asNode.document.newText(ds) else: Text(nil)
  parent.replaceAll(ctx, text.asNode)

proc childElementCountImpl(node: ParentNode): uint32 =
  let last = node.lastElementChild
  if last == nil:
    return 0
  return last.elIndex + 1

proc childTextContent*(node: ParentNode): string =
  result = ""
  for child in node.childList:
    if (let child = child as Text; child != nil):
      result &= child.data.s

proc getParamCollection(root: ParentNode; name: CollectionName; param: CAtom):
    Collection =
  let document = root.asNode.document
  for collection in document.liveCollections(root.asNode):
    if collection.getMagic() == uint32(name):
      let collection = collection as Collection
      if collection.atoms[0] == param:
        return collection
  Collection(nil)

proc getElementsByTagNameImpl(root: ParentNode; tagName: CAtom):
    HTMLCollection =
  let collection = root.getParamCollection(cnGetElementsByTagName, tagName)
  if collection != nil:
    return collection as HTMLCollection
  let match = if $tagName == "*": isElement else: isElementOf
  let this = newHTMLCollection(root.asNode, match, cmSubtree,
    cnGetElementsByTagName)
  if this != nil:
    this.atoms = @[tagName]
  this

proc getElementsByClassNameImpl(root: ParentNode; classNames: DOMString):
    HTMLCollection =
  let param = classNames.toAtom()
  let collection = root.getParamCollection(cnGetElementsByClassName, param)
  if collection != nil:
    return collection as HTMLCollection
  let this = newHTMLCollection(root.asNode, isElementWithClass, cmSubtree,
    cnGetElementsByClassName)
  if this != nil:
    this.atoms.add(param)
    for class in classNames.toOpenArray().split(AsciiWhitespace):
      this.atoms.add(class.toAtom())
  this

proc insert1(parent: ParentNode; ctx: JSContext; node, before: Node;
    postConnectionNodes: var seq[Element]) =
  let parentDocument = parent.asNode.document
  parentDocument.adopt(node, ctx)
  let rootNode = parent.asNode.rootNode
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
  let element = node as Element
  if element != nil:
    #TODO same as before != nil?
    if node.nextSibling != nil and parentElement != nil:
      parentElement.flags.incl(efChildElIndicesInvalid)
    elif (let prev = element.previousElementSibling; prev != nil):
      element.setMagic(prev.getMagic() + 1)
    else:
      element.setMagic(0)
  parentDocument.invalidateCollections()
  if parentElement != nil:
    let shadow = parentElement.shadowRoot
    if shadow != nil and shadow.slotAssignment == samNamed and
        (element != nil or node of Text):
      node.assignSlot()
    if parentElement.tagType == ttSlot and rootNode of ShadowRoot:
      discard #TODO signal a slot change
    #TODO assign slottables for a tree with root
  if node.nextSibling == nil:
    node.internalNext = rootNode
  let rootDocumentLike = rootNode as RootNode
  var specialElement: Element
  for desc in node.descendantsShadowIncl:
    let last = desc.lastChild
    if last != nil and last.internalNext == node:
      # update root (but only if it isn't a shadow root inside node)
      last.internalNext = rootNode
    if (let element = desc as Element; element != nil):
      if element.id != satUempty:
        if element.asNode.rootNode == rootDocumentLike.asNode:
          # rootNode cannot be nil, so neither can rootDocumentLike here
          rootDocumentLike.addElementId(element)
      if specialElement == nil and element.hasInsertionSteps():
        specialElement = element
      if element.custom == cesCustom:
        #TODO append parentDocument to element custom registry
        #TODO enqueue connectedCallback (custom elements)
        discard
      else:
        discard #TODO try to upgrade (custom elements)
    elif (let shadow = desc as ShadowRoot; shadow != nil):
      let customElements = shadow.customElements
      if customElements != nil and customElements.scoped:
        customElements.addScopedDocument(parentDocument)
  # Insertion steps have a tendency to traverse the dom, which has
  # disastrous consequences in the above loop as the root node is still
  # inconsistent.  So we just cache the first node with insertion steps
  # and traverse the tree again if needed.
  while specialElement != nil:
    if specialElement.insertionSteps():
      postConnectionNodes.add(specialElement)
    specialElement = specialElement.nextElementDescendantShadow(node)

# WARNING ditto
proc insert0(parent: ParentNode; ctx: JSContext; nodes: openArray[Node];
    before: Node; suppressObservers: bool) =
  if before != nil:
    #TODO live ranges
    discard
  if (let parent = parent as Element; parent != nil):
    parent.invalidate()
  let beforeBefore = parent.lastChildBefore(before)
  var postConnectionNodes: seq[Element] = @[]
  for node in nodes:
    parent.insert1(ctx, node, before, postConnectionNodes)
  #TODO children changed steps for parent
  if not suppressObservers:
    parent.queueTreeMutationRecord(ctx, nodes, [], beforeBefore, before)
  for el in postConnectionNodes:
    el.postConnectionSteps(ctx)

proc insert*(parent: ParentNode; ctx: JSContext; node, before: Node;
    suppressObservers = false) =
  if (let fragment = node as DocumentFragment; fragment != nil):
    let nodes = fragment.asParentNode.getChildList()
    if nodes.len > 0:
      for child in nodes:
        child.removeImpl(ctx, suppressObservers = true)
      fragment.asParentNode.queueTreeMutationRecord(ctx, nodes, [], Node(nil),
        Node(nil))
      parent.insert0(ctx, nodes, before, suppressObservers)
  else:
    parent.insert0(ctx, [node], before, suppressObservers)

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
    if element.matchesList(selectors):
      return ctx.toJS(element)
  return JS_NULL

proc querySelectorAllImpl(ctx: JSContext; node: ParentNode; q: DOMString):
    JSValue =
  let selectors = ctx.parseSelectors(q)
  if selectors.len == 0:
    return JS_EXCEPTION
  let this = newEmptyNodeList()
  if this == nil:
    return JS_ThrowOutOfMemory(ctx)
  for element in node.elementDescendants:
    if element.matchesList(selectors):
      this.snapshot.add(element.asNode)
  return ctx.toJS(this)

proc getChildrenOf(node: ParentNode; name: CollectionName;
    mode: CollectionMode; tags: varargs[TagType]): HTMLCollection =
  var collection = node.asNode.getLiveCollection(name) as HTMLCollection
  if collection == nil:
    collection = newHTMLCollection(node.asNode, isHTMLElementOf, mode, name)
    if collection != nil:
      for tag in tags:
        collection.atoms.add(tag.view())
  collection

jsClassPublicDef(ParentNode): # fake class
  jsextends NodeDef

# RootNode
proc addElementId0(this: RootNode; element: ptr ElementObj) =
  let mask = this.elementIdMap.len - 1
  var element = element
  let hcache = element.id.hash()
  var home = hcache and mask
  for i, it in this.elementIdMap.mtabPairs(hcache):
    if it == nil:
      it = element
      break
    # if either
    # * "it"'s id is closer to its home than element's id
    # * or if "it" has the same id as element, but element comes earlier
    # then swap out "it" for element.
    let ihash = it.id.hash()
    if tabSwap(home, ihash, i, mask) or
        it.id == element.id and Element(element).precedes(Element(it)):
      swap(it, element)
      home = ihash and mask

proc addElementId(this: RootNode; element: Element) =
  let oldLoad = this.elementIdMapLoad
  for it in this.elementIdMap.prepareTableAdd(oldLoad, init = 32):
    if it != nil:
      this.addElementId0(it)
  inc this.elementIdMapLoad
  this.addElementId0(addr element[])

proc tabHashFast(element: ptr ElementObj): Hash =
  element.id.hash()

proc tabIsEmpty(element: ptr ElementObj): bool =
  element == nil

proc tabKeyEq(element: ptr ElementObj; id: CAtom): bool =
  element.id == id

proc tabKeyEq(a, b: ptr ElementObj): bool =
  a == b

proc getElementById*(this: RootNode; id: CAtom): Element =
  if id != satUempty:
    for it in this.elementIdMap.tabGetAll(id):
      return Element(it)
  Element(nil)

proc getElementById(this: RootNode; ctx: JSContext; val: JSValueConst):
    JSValue =
  let atom = JS_ValueToAtom(ctx, val)
  if atom == JS_ATOM_NULL:
    return JS_EXCEPTION
  var id: CAtomRaw
  let status = ctx.fromJSView(atom, id)
  JS_FreeAtom(ctx, atom)
  if status == fjErr:
    return JS_EXCEPTION
  ctx.toJS(this.getElementById(id.view()))

proc removeElementId(this: RootNode; element: Element) =
  tabDelImpl(this.elementIdMap, this.elementIdMapLoad, addr element[],
    element.id.hash())

jsClassDef(RootNode): # fake class
  jsextends ParentNodeDef

# ElementAccessor
jsClassDef(ElementAccessor): # fake class
  discard

# Collection
template asCollection*[T: CollectionObj](x: JSRef[T]): Collection =
  Collection(x)

template asCollectionLike*[T: CollectionLikeObj](x: JSRef[T]): CollectionLike =
  CollectionLike(x)

proc populateCollection(this: Collection) =
  let root = this.root as ParentNode
  if root != nil:
    case this.mode
    of cmChildren:
      for child in root.childList:
        if this.match == nil or this[].match(this, child):
          this.snapshot.add(child)
    of cmSubtree:
      for desc in root.descendants:
        if this.match == nil or this[].match(this, desc):
          this.snapshot.add(desc)
    of cmTree:
      let root = root.asNode.rootNode as ParentNode
      if root != nil:
        for desc in root.descendants:
          if this.match == nil or this[].match(this, desc):
            this.snapshot.add(desc)

proc refreshCollection(this: Collection) =
  if this.invalid:
    assert this.document != nil
    this.snapshot.setLen(0)
    this.populateCollection()
    this.invalid = false

proc getLength*(this: Collection): uint32 =
  this.refreshCollection()
  uint32(min(uint64(this.snapshot.len), uint32.high))

proc findNode(this: Collection; node: Node): int =
  this.refreshCollection()
  this.snapshot.find(node)

proc attach*(collection: CollectionLike) =
  let document = collection.root.document
  document.addLiveCollection(collection)

proc newEmptyNodeList(): NodeList =
  jsNew NodeListObj(match: nil, document: nil)

proc newNodeList(nodes: openArray[Node]): NodeList =
  let list = newEmptyNodeList()
  if list != nil:
    list.snapshot = @nodes
  list

proc newHTMLCollection(root: Node; match: CollectionMatchFun;
    mode: CollectionMode; name: CollectionName): HTMLCollection =
  let this = jsNew HTMLCollectionObj(
    mode: mode,
    match: match,
    root: root,
    invalid: true
  )
  if this != nil:
    this.asCollectionLike.attach()
    this.setMagic(uint32(name))
  this

proc newNodeList(root: Node; match: CollectionMatchFun; mode: CollectionMode;
    name: CollectionName): NodeList =
  # returns a live node list
  let this = jsNew NodeListObj(
    mode: mode,
    match: match,
    root: root,
    invalid: true
  )
  if this != nil:
    this.asCollectionLike.attach()
    this.setMagic(uint32(name))
  this

jsClassDef(CollectionLike): # fake class
  proc finalize(rt: JSRuntime; collection: CollectionLike) {.jsfin.} =
    if collection.document != nil:
      # Note that document may point to a zombie object; in that case
      # the liveCollections seq is automatically cleared, and this won't
      # do anything.
      cast[Document](collection.document).removeLiveCollection(collection)

jsClassDef(Collection): # fake class
  jsextends CollectionLikeDef

  proc mark(rt: JSRuntime; this: Collection; markFunc: JS_MarkFunc)
      {.jsmark.} =
    for node in this.snapshot:
      rt.markObj(node, markFunc)

# CharacterData
jsClassDef(CharacterData):
  jsextends NodeDef

  jsget CharacterData, data

  proc setData(ctx: JSContext; this: CharacterData; data: DOMStringNull) {.
      jsfset: "data".} =
    this.asNode.queueMutationRecord(ctx, mrtCharacterData, CAtomNull,
      CAtomNull, this.data, true, "", [], [], Node(nil), Node(nil))
    this.data = newRefString(data)

  proc length(this: CharacterData): int {.jsfget.} =
    return ($this.data).utf16Len

  proc previousElementSibling(this: CharacterData): Element {.jsfget.} =
    return this.asNode.previousElementSiblingImpl

  proc nextElementSibling(this: CharacterData): Element {.jsfget.} =
    return this.asNode.nextElementSiblingImpl

  proc before(ctx: JSContext; this: CharacterData;
      nodes: varargs[JSValueConst]): Opt[void] {.jsfunc.} =
    ctx.beforeImpl(this.asNode, nodes)

  proc after(ctx: JSContext; this: CharacterData; nodes: varargs[JSValueConst]):
      Opt[void] {.jsfunc.} =
    ctx.afterImpl(this.asNode, nodes)

  proc replaceWith(ctx: JSContext; this: CharacterData;
      nodes: varargs[JSValueConst]): JSValue {.jsfunc.} =
    ctx.replaceWithImpl(this.asNode, nodes)

  proc remove(ctx: JSContext; this: CharacterData) {.jsfunc.} =
    this.asNode.removeImpl(ctx)

# Text
proc newText*(document: Document; data: sink string): Text =
  jsNew TextObj(internalNext: document.asNode, data: newRefString(move(data)))

proc newText*(document: Document; data: DOMString): Text =
  jsNew TextObj(internalNext: document.asNode, data: newRefString(data))

jsClassPublicDef(Text):
  jsextends CharacterDataDef

  proc newText(ctx: JSContext; data = initDOMStringLit("")): Text {.jsctor.} =
    let window = ctx.getGlobal()
    return window.document.newText(data)

# CDATASection
proc newCDATASection(document: Document; data: RefString): CDATASection =
  jsNew CDATASectionObj(internalNext: document.asNode, data: data)

jsClassDef(CDATASection):
  jsextends TextDef

# ProcessingInstruction
proc newProcessingInstruction(document: Document; target: string;
    data: RefString): ProcessingInstruction =
  jsNew ProcessingInstructionObj(
    internalNext: document.asNode,
    target: target,
    data: data
  )

jsClassDef(ProcessingInstruction):
  jsextends CharacterDataDef

  jsget ProcessingInstruction, target

# Comment
proc newComment*(document: Document; data: RefString): Comment =
  jsNew CommentObj(internalNext: document.asNode, data: data)

jsClassDef(Comment):
  jsextends CharacterDataDef

  proc newComment(ctx: JSContext; data = initDOMStringLit("")): Comment {.
      jsctor.} =
    let window = ctx.getWindow()
    return window.document.newComment(newRefString(data))

# DocumentFragment
template asDocumentFragment[T: DocumentFragmentObj](x: JSRef[T]):
    DocumentFragment =
  DocumentFragment(x)

proc getDocument*(ctx: JSContext): Document =
  return ctx.getWindow().document

proc newDocumentFragment(document: Document): DocumentFragment =
  jsNew DocumentFragmentObj(internalNext: document.asNode)

jsClassDef(DocumentFragment):
  jsextends RootNodeDef

  proc newDocumentFragment(ctx: JSContext): DocumentFragment {.jsctor.} =
    let window = ctx.getGlobal()
    return window.document.newDocumentFragment()

  proc firstElementChild(this: DocumentFragment): Element {.jsfget.} =
    return this.asParentNode.firstElementChild

  proc lastElementChild(this: DocumentFragment): Element {.jsfget.} =
    return this.asParentNode.lastElementChild

  proc childElementCount(this: DocumentFragment): uint32 {.jsfget.} =
    return this.asParentNode.childElementCountImpl

  proc querySelector(ctx: JSContext; this: DocumentFragment; q: DOMString):
      JSValue {.jsfunc.} =
    return ctx.querySelectorImpl(this.asParentNode, q)

  proc querySelectorAll(ctx: JSContext; this: DocumentFragment; q: DOMString):
      JSValue {.jsfunc.} =
    return ctx.querySelectorAllImpl(this.asParentNode, q)

  proc prepend(ctx: JSContext; this: DocumentFragment;
      nodes: varargs[JSValueConst]): JSValue {.jsfunc.} =
    return ctx.prependImpl(this.asNode, nodes)

  proc append(ctx: JSContext; this: DocumentFragment;
      nodes: varargs[JSValueConst]): JSValue {.jsfunc.} =
    return ctx.appendImpl(this.asNode, nodes)

  proc replaceChildren(ctx: JSContext; this: DocumentFragment;
      nodes: varargs[JSValueConst]): JSValue {.jsfunc.} =
    return ctx.replaceChildrenImpl(this.asNode, nodes)

  proc children(this: DocumentFragment): HTMLCollection {.jsnfget.} =
    this.asParentNode.childrenImpl

  proc getElementById(ctx: JSContext; this: DocumentFragment;
      val: JSValueConst): JSValue {.jsfunc.} =
    this.asRootNode.getElementById(ctx, val)

# Document
template asDocument[T: DocumentObj](x: JSRef[T]): Document =
  Document(x)

proc newXMLDocument(): XMLDocument =
  jsNew XMLDocumentObj(
    url: parseURL0("about:blank"),
    contentType: satApplicationXml,
    charset: csUtf8
  )

proc newDocument*(url: URL): Document =
  jsNew DocumentObj(
    url: url,
    contentType: satApplicationXml,
    origin: url.origin,
    charset: csUtf8
  )

proc newDocumentType*(document: Document; name, publicId, systemId: string):
    DocumentType =
  jsNew DocumentTypeObj(
    internalNext: document.asNode,
    name: name,
    publicId: publicId,
    systemId: systemId
  )

proc isxml(document: Document): bool =
  return document.contentType != satTextHtml

proc globalCustomElements(document: Document): CustomElementRegistry =
  if document.customElements != nil and not document.customElements.scoped:
    return document.customElements
  CustomElementRegistry(nil)

proc addLiveCollection0(document: Document;
    collection: ptr CollectionLikeObj) =
  let mask = document.liveCollections.len - 1
  var home = collection.hcache and mask
  var collection = collection
  let hcache = collection.hcache
  for i, it in document.liveCollections.mtabPairs(hcache):
    if it == nil:
      it = collection
      break
    if tabSwap(home, it.hcache, i, mask):
      swap(it, collection)

proc addLiveCollection(document: Document; collection: CollectionLike) =
  let oldLoad = document.liveCollectionsLoad
  for it in document.liveCollections.prepareTableAdd(oldLoad, init = 32):
    if it != nil:
      document.addLiveCollection0(it)
  inc document.liveCollectionsLoad
  collection.hcache = hash(cast[pointer](collection.root))
  collection.document = addr document[]
  document.addLiveCollection0(addr collection[])

proc removeLiveCollection(document: Document; collection: CollectionLike) =
  tabDelImpl(document.liveCollections, document.liveCollectionsLoad,
    addr collection[], collection.hcache)

proc getLiveCollections(document: Document; node: Node): seq[CollectionLike] =
  # Returns all live collections rooted at `node'.
  var res: seq[CollectionLike] = @[]
  for collection in document.liveCollections(node):
    if collection.root == node:
      res.add(collection)
  move(res)

proc adopt(document: Document; node: Node; ctx: JSContext) =
  let oldDocument = node.document
  node.removeImpl(ctx)
  if oldDocument != document:
    # node is detached from the tree, so its internalNext is guaranteed to
    # be oldDocument; we want to override that.
    node.internalNext = document.asNode
    if (let node = node as ParentNode; node != nil):
      # The node document is already set, so we must update collections
      # before doing anything that might be observable.
      # (In principle we could do this without the seq but it seems like
      # a pain.)
      let collections = oldDocument.getLiveCollections(node.asNode)
      for collection in collections:
        oldDocument.removeLiveCollection(collection)
        document.addLiveCollection(collection)
      let quirks = document.quirksMode
      for desc in node.asNode.descendantsShadowIncl:
        if (let root = desc as ShadowRoot; root != nil):
          if root.customElements == nil and not root.unsetCustomElements or
              root.customElements != nil and not root.customElements.scoped:
            root.customElements = document.globalCustomElements
        elif (let element = desc as Element; element != nil):
          if quirks == qmQuirks:
            element.flags.incl(efQuirks)
          else:
            element.flags.excl(efQuirks)
          let map = element.getCachedAttributes()
          if map != nil:
            for it in map.attrlist:
              it.internalNext = document.asNode
          #TODO custom element registry, img relevant mutations, adoptedCallback
          if (let templ = element as HTMLTemplateElement; templ != nil):
            document.adopt(templ.content.asNode, ctx)

proc getCookieWindow(ctx: JSContext; document: Document): Opt[Window] =
  let window = document.window
  if window == nil or document.url.schemeType notin {stHttp, stHttps}:
    return ok(Window(nil))
  if document.origin.t == otOpaque:
    JS_ThrowDOMException(ctx, "SecurityError",
      "sandboxed iframe cannot access cookies")
    return err()
  ok(window)

proc setFocus*(document: Document; element: Element) =
  if document.focus != nil:
    document.focus.invalidate(dtFocus)
  document.internalFocus = element
  if element != nil:
    element.invalidate(dtFocus)

proc findAutoFocus*(document: Document): Element =
  for child in document.asParentNode.elementDescendants:
    if child.attrb(satAutofocus):
      return child
  Element(nil)

proc target*(document: Document): Element =
  return document.internalTarget

proc setTarget*(document: Document; element: Element) =
  if document.target != nil:
    document.target.invalidate(dtTarget)
  document.internalTarget = element
  if element != nil:
    element.invalidate(dtTarget)

proc scriptingEnabled*(document: Document): bool =
  if document.window == nil:
    return false
  return document.window.settings.scripting != smFalse

proc getElementsById*(document: Document; id: CAtom): JSRootRef =
  # for WindowProperties
  if id != satUempty and document.elementIdMap.len > 0:
    let mask = document.elementIdMap.len - 1
    let hcache = id.hash()
    for i, it in document.elementIdMap.tabPairs(hcache):
      if it == nil:
        break
      if it.id == id:
        let next = document.elementIdMap[(i + 1) and mask]
        if next != nil and next.id == id:
          # sad, but what can you do
          let collection = newHTMLCollection(
            document.asNode,
            match = proc(this: Collection; node: Node): bool {.nimcall.} =
              let element = node as Element
              if element != nil:
                return element.id == this.atoms[0]
              false,
            cmSubtree,
            cnGetElementsById
          )
          if collection != nil:
            collection.atoms = @[id]
          return collection.asRootRef
        return cast[Element](it).asRootRef
  JSRootRef(nil)

proc baseURL*(document: Document): URL =
  #TODO frozen base url...
  var href = ""
  for base in document.asParentNode.elementDescendants(ttBase):
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

proc invalidateCollections*(document: Document) =
  for collection in document.liveCollections:
    if collection != nil and cast[CollectionLike](collection) of Collection:
      cast[Collection](collection).invalid = true
      cast[Collection](collection).snapshot = @[]

proc invalidateCollectionsRemove(document: Document; node: Node) =
  # node will be removed
  for collection in document.liveCollections:
    if cast[CollectionLike](collection) of NodeIterator:
      cast[NodeIterator](collection).adjustForRemoval(node)
    elif cast[CollectionLike](collection) of Collection:
      cast[Collection](collection).invalid = true

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

proc validateElementName(ctx: JSContext; s: openArray[char]): Opt[void] =
  if s.len > 0:
    let c = s[0]
    if c in AsciiAlpha:
      if AsciiWhitespace + {'\0', '/', '>'} notin s:
        return ok()
    elif c notin AsciiDigit + {'-', '.'}:
      if Ascii - AsciiAlphaNumeric - {'-', '.', ':', '_'} notin s:
        return ok()
  JS_ThrowDOMException(ctx, "InvalidCharacterError", "invalid tag local name")
  err()

proc validateAttrName(ctx: JSContext; name: openArray[char]): Opt[void] =
  const AttrDisallowed = AsciiWhitespace + {'\0', '/', '=', '>'}
  if name.len > 0 and AttrDisallowed notin name:
    return ok()
  JS_ThrowDOMException(ctx, "InvalidCharacterError", "invalid attribute name")
  return err()

type NameValidator = enum
  nvAttribute, nvElement

# localName must be set to the qualified name before the call
proc validateAndExtract(ctx: JSContext; namespace, localName: var CAtom;
    t: NameValidator): Opt[void] =
  if namespace == satUempty:
    namespace = CAtomNull
  var prefix = CAtomNull
  let i = localName.find(':')
  if i >= 0:
    prefix = localName.substr(0, i - 1)
    localName = localName.substr(i + 1)
    if prefix == satUempty or AsciiWhitespace + {'\0', '/', '>'} in prefix:
      JS_ThrowDOMException(ctx, "InvalidCharacterError", "invalid prefix")
      return err()
  case t
  of nvAttribute: ?ctx.validateAttrName($localName)
  of nvElement: ?ctx.validateElementName($localName)
  let sns = namespace.toStaticAtom()
  let isXmlns = prefix == satXmlns or
    prefix == CAtomNull and localName == satXmlns
  if namespace == CAtomNull and prefix != CAtomNull or
      prefix == satXml and sns != satNamespaceXML or
      isXmlns != (sns == satNamespaceXMLNS):
    JS_ThrowDOMException(ctx, "NamespaceError", "unexpected namespace")
    return err()
  ok()

proc getReflectElement(ctx: JSContext; this: JSValueConst; magic: cint):
    ptr HTMLElementObj =
  let magic = uint16(magic)
  let class = JSClassID(uint32(magic shr 9) + uint32(getClassID(HTMLElement)))
  var p: pointer
  if ctx.fromJS(this, class, p).isErr:
    return nil
  return cast[ptr HTMLElementObj](p)

proc getEventTarget(element: Element; name: StaticAtom): EventTarget =
  if element.tagType in {ttBody, ttFrameset} and name in WindowEvents:
    let window = element.asNode.document.window
    if window == nil:
      return EventTarget(nil)
    return window.asEventTarget
  element.asEventTarget

proc reflectEvent(document: Document; target: EventTarget;
    name, eventType: StaticAtom; value: string) =
  let ctx = document.window.jsctx
  let fun = ctx.newFunction(["event"], value)
  assert ctx != nil
  if JS_IsException(fun):
    document.window.logException(document.baseURL)
  else:
    let res = ctx.eventReflectSetImpl(target, fun, eventType)
    if JS_IsException(res):
      document.window.logException(document.baseURL)
    JS_FreeValue(ctx, res)
    JS_FreeValue(ctx, fun)

proc applyUASheet*(document: Document) =
  const ua = staticRead"res/ua.css"
  let sheet = parseStylesheet(ua, URL(nil), addr document.window.settings,
    coUserAgent, CAtomNull)
  document.uaSheetsHead = sheet
  if document.documentElement != nil:
    document.documentElement.invalidate()

proc applyQuirksSheet*(document: Document) =
  if document.window == nil:
    return
  const quirks = staticRead"res/quirk.css"
  let sheet = parseStylesheet(quirks, URL(nil), addr document.window.settings,
    coUserAgent, CAtomNull)
  document.uaSheetsHead.next = sheet
  sheet.prev = document.uaSheetsHead
  if document.documentElement != nil:
    document.documentElement.invalidate()

proc applyUserSheet*(document: Document; user: string) =
  document.userSheet = parseStylesheet(user, URL(nil),
    addr document.window.settings, coUser, CAtomNull)
  if document.documentElement != nil:
    document.documentElement.invalidate()

proc getRuleMap*(document: Document): CSSRuleMap =
  if document.ruleMap == nil:
    let map = newCSSRuleMap(document.quirksMode == qmQuirks)
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

proc findAnchor*(document: Document; id: string): Element =
  if id.len == 0:
    return Element(nil)
  let id = id.toAtom()
  for child in document.asParentNode.elementDescendants:
    if child.id == id:
      return child
    if child.tagType == ttA and child.name == id:
      return child
  return Element(nil)

proc findMetaRefresh*(document: Document): Element =
  for child in document.asParentNode.elementDescendants(ttMeta):
    if child.attr(satHttpEquiv).equalsIgnoreCase("refresh"):
      return child
  return Element(nil)

proc checkRegistryScope(ctx: JSContext; document: Document;
    registry: CustomElementRegistry): Opt[void] =
  if not registry.scoped and registry != document.customElements:
    JS_ThrowDOMException(ctx, "NotSupportedError",
      "wrong custom element registry scope")
    return err()
  ok()

proc findFirst*(document: Document; tagType: TagType): HTMLElement =
  for element in document.asParentNode.elementDescendants(tagType):
    return element as HTMLElement
  HTMLElement(nil)

jsClassPublicDef(Document):
  jsextends RootNodeDef

  jsget Document, charset, "charset", "characterSet", "inputEncoding"
  jsget Document, readyState
  jsget Document, contentType
  jsget Document, window, "defaultView"
  jsget Document, currentScript

  proc finalize(rt: JSRuntime; document: Document) {.jsfin.} =
    var sheet = move(document.uaSheetsHead)
    while sheet != nil:
      let next = move(sheet.next)
      sheet.prev = nil
      sheet = next
    sheet = move(document.authorSheetsHead)
    while sheet != nil:
      let next = move(sheet.next)
      sheet.prev = nil
      sheet = next

  proc mark(rt: JSRuntime; document: Document; markFunc: JS_MarkFunc)
      {.jsmark.} =
    for element in document.renderBlockingElements:
      rt.markObj(element, markFunc)

  proc newDocument(ctx: JSContext): Document {.jsctor.} =
    let global = ctx.getWindow()
    jsNew DocumentObj(
      url: parseURL0("about:blank"),
      contentType: satApplicationXml,
      origin: global.document.origin,
      charset: csUtf8
    )

  proc getImplementation(ctx: JSContext; document: Document): JSValue
      {.jsfget: "implementation".} =
    if document.implementation == nil:
      let impl = newDOMImplementation(ctx, document)
      if JS_IsException(impl):
        return impl
      document.implementation = traceObj(impl)
    return JS_DupValue(ctx, document.implementation.value)

  proc firstElementChild(this: Document): Element {.jsfget.} =
    return this.asParentNode.firstElementChild

  proc lastElementChild(this: Document): Element {.jsfget.} =
    return this.asParentNode.lastElementChild

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

  proc importNode(ctx: JSContext; document: Document; node: Node;
      options: JSValueConst = JS_UNDEFINED): Opt[Node] {.jsfunc.} =
    if node of Document or node of ShadowRoot:
      JS_ThrowDOMException(ctx, "NotSupportedError",
        "node cannot be adopted")
      return err()
    var deep = false
    var registry = document.customElements
    if JS_IsBool(options):
      ?ctx.fromJS(options, deep)
    else:
      var selfOnly: bool
      discard ?ctx.fromJSGetProp(options, "selfOnly", selfOnly)
      deep = not selfOnly
      discard ?ctx.fromJSGetProp(options, "customElementRegistry", registry)
      ?ctx.checkRegistryScope(document, registry)
    ctx.cloneNodeImpl(node, document, deep, ParentNode(nil), registry)

  proc compatMode(document: Document): string {.jsfget.} =
    if document.quirksMode == qmQuirks:
      return "BackCompat"
    return "CSS1Compat"

  proc forms(document: Document): HTMLCollection {.jsnfget.} =
    document.asParentNode.getChildrenOf(cnForms, cmSubtree, ttForm)

  proc links(document: Document): HTMLCollection {.jsnfget.} =
    document.asParentNode.getHTMLCollection(isLink, cmSubtree, cnLinks)

  proc images(document: Document): HTMLCollection {.jsnfget.} =
    document.asParentNode.getChildrenOf(cnImages, cmSubtree, ttImg)

  proc getURL(ctx: JSContext; document: Document): JSValue {.
      jsfget: "URL", jsfget: "documentURI".} =
    return ctx.toJS($document.url)

  proc cookie(ctx: JSContext; document: Document): JSValue {.jsfget.} =
    let window = ?ctx.getCookieWindow(document)
    if window == nil:
      return ctx.toJS("")
    let request = newRequest("x-cha-cookie:get-all", internal = true)
    let response = window.loader.doRequest(request)
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
    let request = newRequest("x-cha-cookie:set", hmPost, headers,
      credentials = cmOmit, internal = true)
    let response = window.loader.doRequest(request)
    window.loader.close(response)
    ok()

  proc focus*(document: Document): Element {.jsfget: "activeElement".} =
    return document.internalFocus

  proc hasFocus(document: Document): bool {.jsfunc.} =
    document.internalFocus != nil

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
    return ctx.toJSNew(newCDATASection(document, newRefString(data)))

  proc createComment(document: Document; data: DOMString): Comment
      {.jsnfunc.} =
    return newComment(document, newRefString(data))

  proc createProcessingInstruction(ctx: JSContext; document: Document;
      target, data: DOMString): JSValue {.jsfunc.} =
    if not target.toOpenArray().matchNameProduction() or
        "?>" in data.toOpenArray():
      return JS_ThrowDOMException(ctx, "InvalidCharacterError",
        "invalid data for processing instruction")
    let pi = newProcessingInstruction(document, $target, newRefString(data))
    ctx.toJSNew(pi)

  proc createEvent(ctx: JSContext; document: Document; atom: CAtom):
      JSValue {.jsfunc.} =
    case atom.toStaticAtomLower()
    of satCustomevent:
      return ctx.toJSNew(ctx.newCustomEvent(satUempty.view()))
    of satEvent, satEvents, satHtmlevents, satSvgevents:
      return ctx.toJSNew(newEvent(satUempty, EventTarget(nil), bubbles = false,
        cancelable = false))
    of satUievent, satUievents:
      return ctx.toJSNew(newUIEvent(satUempty.view()))
    of satMouseevent, satMouseevents:
      return ctx.toJSNew(newMouseEvent(satUempty.view()))
    else:
      return JS_ThrowDOMException(ctx, "NotSupportedError", "event not supported")

  proc location(ctx: JSContext; document: Document): JSValue {.jsuffget.} =
    if document.window == nil:
      return JS_NULL
    return JS_GetPropertyStr(ctx, ctx.getOpaque().global, "location")

  proc setLocation*(ctx: JSContext; document: Document; s: string): JSValue
      {.jsfset: "location".} =
    let obj = ctx.location(document)
    if JS_IsException(obj):
      return obj
    let res = JS_SetPropertyStr(ctx, obj, "href", ctx.toJS(s))
    JS_FreeValue(ctx, obj)
    if res < 0:
      return JS_EXCEPTION
    return JS_UNDEFINED

  proc head(document: Document): HTMLHeadElement {.jsfget.} =
    let html = document.documentElement
    if html != nil:
      for element in html.asParentNode.elementList:
        let head = element as HTMLHeadElement
        if head != nil:
          return head
    HTMLHeadElement(nil)

  proc body(document: Document): HTMLElement {.jsfget.} =
    let html = document.documentElement
    if html != nil:
      for element in html.asParentNode.elementList:
        if element.tagType in {ttBody, ttFrameset}:
          return element as HTMLElement
    HTMLElement(nil)

  proc title*(document: Document): string {.jsfget.} =
    let svg = document.documentElement as SVGSVGElement
    let title = if svg != nil:
      svg.asParentNode.findFirstChildOf(satTitle, satNamespaceSVG)
    else:
      document.findFirst(ttTitle).asElement
    if title != nil:
      return title.asParentNode.childTextContent.stripAndCollapse()
    return ""

  proc setTitle(ctx: JSContext; document: Document; ds: DOMString) {.
      jsfset: "title".} =
    let root = document.documentElement
    let svg = root as SVGSVGElement
    var title = if svg != nil:
      root.asParentNode.findFirstChildOf(satTitle, satNamespaceSVG)
    elif root != nil and root.namespaceURI == satNamespaceHTML:
      document.findFirst(ttTitle).asElement
    else:
      return
    if title == nil:
      let namespace = if svg != nil: satNamespaceSVG else: satNamespaceHTML
      let head = if svg != nil: svg.asElement else: document.head.asElement
      if head != nil:
        title = document.newElement(satTitle.view(), namespace)
        if title != nil:
          var before = Node(nil)
          if svg != nil:
            before = svg.asParentNode.firstChild
          head.asParentNode.insert(ctx, title.asNode, before)
    if title != nil:
      title.asParentNode.replaceAll(ctx, ds)

  proc getElementById(ctx: JSContext; document: Document; val: JSValueConst):
      JSValue {.jsfunc.} =
    document.asRootNode.getElementById(ctx, val)

  proc getElementsByName(document: Document; name: CAtom): NodeList
      {.jsnfunc.} =
    let collection = document.asParentNode.getParamCollection(
      cnGetElementsByName, name
    )
    if collection != nil:
      return collection as NodeList
    let this = newNodeList(
      document.asNode,
      proc(this: Collection; node: Node): bool {.nimcall.} =
        let element = node as Element
        element != nil and element.name == this.atoms[0],
      cmSubtree,
      cnGetElementsByName
    )
    if this != nil:
      this.atoms = @[name]
    this

  proc getElementsByTagName(document: Document; tagName: CAtom):
      HTMLCollection {.jsnfunc.} =
    document.asParentNode.getElementsByTagNameImpl(tagName)

  proc getElementsByClassName(document: Document; classNames: DOMString):
      HTMLCollection {.jsnfunc.} =
    document.asParentNode.getElementsByClassNameImpl(classNames)

  proc children(this: Document): HTMLCollection {.jsnfget.} =
    this.asParentNode.childrenImpl

  proc querySelector(ctx: JSContext; this: Document; q: DOMString): JSValue
      {.jsfunc.} =
    return ctx.querySelectorImpl(this.asParentNode, q)

  proc querySelectorAll(ctx: JSContext; this: Document; q: DOMString): JSValue
      {.jsfunc.} =
    return ctx.querySelectorAllImpl(this.asParentNode, q)

  #TODO options/custom elements
  proc createElement(ctx: JSContext; document: Document; localName: DOMString):
      JSValue {.jsfunc.} =
    ?ctx.validateElementName(localName.toOpenArray())
    let localName = if not document.isxml:
      localName.toAtomLower()
    else:
      localName.toAtom()
    let namespace = if not document.isxml or
        document.contentType == satApplicationXmlHtml:
      satNamespaceHTML
    else:
      satUempty
    ctx.toJSNew(document.newElement(localName, namespace))

  proc createElementNS(ctx: JSContext; document: Document;
      namespace, qualifiedName: CAtom): Opt[Element] {.jsnfunc.} =
    var namespace = namespace
    var localName = qualifiedName
    ?ctx.validateAndExtract(namespace, localName, nvElement)
    #TODO custom elements (is)
    ok(document.newElement(localName, namespace, qualifiedName))

  proc createDocumentFragment(document: Document): DocumentFragment
      {.jsnfunc.} =
    return newDocumentFragment(document)

  proc createTextNode(document: Document; data: DOMString): Text {.jsnfunc.} =
    return newText(document, data)

  proc prepend(ctx: JSContext; this: Document; nodes: varargs[JSValueConst]):
      JSValue {.jsfunc.} =
    return ctx.prependImpl(this.asNode, nodes)

  proc append(ctx: JSContext; this: Document; nodes: varargs[JSValueConst]):
      JSValue {.jsfunc.} =
    return ctx.appendImpl(this.asNode, nodes)

  proc replaceChildren(ctx: JSContext; this: Document;
      nodes: varargs[JSValueConst]): JSValue {.jsfunc.} =
    return ctx.replaceChildrenImpl(this.asNode, nodes)

  # https://html.spec.whatwg.org/multipage/dynamic-markup-insertion.html#document-write-steps
  proc write(ctx: JSContext; document: Document; args: varargs[JSValueConst]):
      JSValue {.jsfunc.} =
    var text = ""
    for arg in args:
      var s: DOMString
      ?ctx.fromJS(arg, s)
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
    if document.parser == nil:
      #TODO document.open
      return JS_UNDEFINED
    let buffer = document.writeBuffersTop
    if buffer == nil:
      return JS_UNDEFINED #TODO (probably covered by open above)
    buffer.data &= text
    if document.parserBlockingScript == nil:
      parseDocumentWriteChunk(document.parser)
    return JS_UNDEFINED

  proc childElementCount(this: Document): uint32 {.jsfget.} =
    return this.asParentNode.childElementCountImpl

  proc doctype(document: Document): DocumentType {.jsfget.} =
    document.asParentNode.firstChild as DocumentType

  proc documentElement*(document: Document): Element {.jsfget.} =
    return document.firstElementChild()

  proc scrollingElement(document: Document): Element {.jsfget.} =
    let window = document.window
    if document.quirksMode == qmQuirks and window != nil and
        window.settings.scripting == smApp:
      let body = document.body.asElement
      if body != nil:
        body.ensureStyle()
        window.ensureLayout(body)
        if body.box == nil:
          return body
        const NoScroll = {OverflowVisible, OverflowClip}
        const NoScroll2 = NoScroll + {OverflowHidden}
        let parent = body.asNode.parentElement
        parent.ensureStyle()
        if (parent.computed{"overflow-x"} in NoScroll2 or
            body.computed{"overflow-x"} in NoScroll) and
            (parent.computed{"overflow-y"} in NoScroll2 or
            body.computed{"overflow-y"} in NoScroll):
          return body
    document.documentElement

  proc names(ctx: JSContext; document: Document): JSPropertyEnumList
      {.jspropnames.} =
    var list = newJSPropertyEnumList(ctx, 0)
    #TODO exposed embed, exposed object
    const Tags = {ttForm, ttIframe, ttImg}
    for child in document.asParentNode.elementDescendants(Tags):
      if child.name != CAtomNull and child.name != satUempty:
        if child.tagType == ttImg and child.id != satUempty:
          list.incl($child.id)
        list.incl($child.name)
    return list

  proc getter(ctx: JSContext; document: Document; atom: JSAtom): JSValue
      {.jsgetownprop.} =
    var id: CAtomRaw
    ?ctx.fromJSView(atom, id)
    if id != CAtomNull and id != satUempty:
      #TODO exposed embed, exposed object
      const Tags = {ttForm, ttIframe, ttImg}
      for child in document.asParentNode.elementDescendants(Tags):
        if child.tagType == ttImg and child.id == id and
            child.name != CAtomNull and child.name != satUempty:
          return ctx.toJS(child)
        if child.name == id:
          return ctx.toJS(child)
    return JS_UNINITIALIZED

  proc all(ctx: JSContext; document: Document): JSValue {.jsfget.} =
    var collection = document.asNode.getLiveCollection(cnAll) as
      HTMLAllCollection
    if collection == nil:
      collection = jsNew HTMLAllCollectionObj(
        match: isElement,
        root: document.asNode,
        invalid: true
      )
      let val = ctx.toJSNew(collection)
      if JS_IsException(val):
        return val
      collection.asCollectionLike.attach()
      JS_SetIsHTMLDDA(ctx, val)
      return val
    return ctx.toJS(collection)

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

  proc referrer(ctx: JSContext; document: Document): JSValue {.jsfget.} =
    if document.window != nil:
      return ctx.toJS(document.window.referrer)
    return ctx.toJS("")

  proc createNodeIterator(ctx: JSContext; document: Document; root: Node;
      whatToShow = 0xFFFFFFFFu32; filter: JSValueConst = JS_NULL):
      JSValue {.jsfunc.} =
    if not JS_IsObject(filter) and not JS_IsNull(filter):
      return JS_ThrowTypeError(ctx, "filter is not an object")
    let this = jsNew NodeIteratorObj(
      root: root,
      currentNode: root,
      iterNode: root,
      whatToShow: whatToShow,
      before: true
    )
    if this != nil:
      if not JS_IsNull(filter):
        this.filter = ctx.dupTraceObj(filter)
      this.asCollectionLike.attach()
    ctx.toJSNew(this)

  proc createTreeWalker(ctx: JSContext; document: Document; root: Node;
      whatToShow = 0xFFFFFFFFu32; filter: JSValueConst = JS_NULL):
      JSValue {.jsfunc.} =
    if not JS_IsObject(filter) and not JS_IsNull(filter):
      return JS_ThrowTypeError(ctx, "filter is not an object")
    let this = jsNew TreeWalkerObj(
      root: root,
      currentNode: root,
      whatToShow: whatToShow
    )
    if this != nil and not JS_IsNull(filter):
      this.filter = ctx.dupTraceObj(filter)
    ctx.toJSNew(this)

# XMLDocument
jsClassDef(XMLDocument):
  jsextends DocumentDef

# DOMImplementation
jsClassRaw(DOMImplementationDef, "DOMImplementation"):
  # A JSObject holding a strong reference to the Document it originates
  # from.
  proc newDOMImplementation(ctx: JSContext; document: Document): JSValue =
    let this = JS_NewObjectFromCtor(ctx, JS_UNDEFINED, classDef.id)
    if JS_IsException(this):
      return this
    let rt = JS_GetRuntime(ctx)
    JS_SetOpaque(this, JS_DupForeignObject(rt, cast[pointer](document)))
    return this

  proc finalizeDOMImpl(rt: JSRuntime; this: pointer) {.jsfin.} =
    JS_FreeForeignObject(rt, this)

  proc markDOMImpl(rt: JSRuntime; this: pointer; markFunc: JS_MarkFunc)
      {.jsmark.} =
    JS_MarkForeignObject(rt, this, markFunc)

  proc createDocument(ctx: JSContext; implementation: DOMImplementation;
      namespace: CAtom; qualifiedName: DOMStringNull;
      doctype = none(DocumentType)): JSValue {.jsfunc.} =
    let document = newXMLDocument()
    if document == nil:
      return JS_ThrowOutOfMemory(ctx)
    let qualifiedName = qualifiedName.toAtom()
    let element = if qualifiedName != satUempty:
      ?ctx.createElementNS(document.asDocument, namespace, qualifiedName)
    else:
      Element(nil)
    if doctype.isSome:
      document.asParentNode.append(ctx, doctype.get.asNode)
    if element != nil:
      document.asParentNode.append(ctx, element.asNode)
    document.origin = Document(implementation).origin
    case namespace.toStaticAtom()
    of satNamespaceHTML: document.contentType = satApplicationXmlHtml
    of satNamespaceSVG: document.contentType = satImageSvgXml
    else: discard
    ctx.toJS(document)

  proc createHTMLDocument(ctx: JSContext; implementation: DOMImplementation;
      title: JSValueConst = JS_UNDEFINED): JSValue {.jsfunc.} =
    let doc = newDocument(ctx)
    doc.contentType = satTextHtml
    let doctype = doc.newDocumentType("html", "", "")
    let html = doc.newHTMLElement(ttHtml)
    let head = doc.newHTMLElement(ttHead)
    let body = doc.newHTMLElement(ttBody)
    if doctype == nil or html == nil or head == nil or body == nil:
      return JS_ThrowOutOfMemory(ctx)
    doc.asParentNode.append(ctx, doctype.asNode)
    doc.asParentNode.append(ctx, html.asNode)
    html.asParentNode.append(ctx, head.asNode)
    if not JS_IsUndefined(title):
      var ds: DOMString
      ?ctx.fromJS(title, ds)
      let titleElement = doc.newHTMLElement(ttTitle)
      let text = doc.newText(ds)
      if titleElement == nil or text == nil:
        return JS_ThrowOutOfMemory(ctx)
      titleElement.asParentNode.append(ctx, text.asNode)
      head.asParentNode.append(ctx, titleElement.asNode)
    html.asParentNode.append(ctx, body.asNode)
    doc.origin = Document(implementation).origin
    ctx.toJS(doc)

  proc createDocumentType(ctx: JSContext; implementation: DOMImplementation;
      qualifiedName, publicId, systemId: DOMString): JSValue {.jsfunc.} =
    if AsciiWhitespace + {'\0', '>'} in qualifiedName.toOpenArray():
      return JS_ThrowDOMException(ctx, "InvalidCharacterError",
        "invalid character in qualified name")
    let document = Document(implementation)
    ctx.toJS(document.newDocumentType($qualifiedName, $publicId, $systemId))

  proc hasFeature(implementation: DOMImplementation): bool {.jsfunc.} =
    return true

# DocumentType
jsClassDef(DocumentType):
  jsextends NodeDef

  jsget DocumentType, name
  jsget DocumentType, publicId
  jsget DocumentType, systemId

  proc before(ctx: JSContext; this: DocumentType;
      nodes: varargs[JSValueConst]): Opt[void] {.jsfunc.} =
    ctx.beforeImpl(this.asNode, nodes)

  proc after(ctx: JSContext; this: DocumentType; nodes: varargs[JSValueConst]):
      Opt[void] {.jsfunc.} =
    ctx.afterImpl(this.asNode, nodes)

  proc replaceWith(ctx: JSContext; this: DocumentType;
      nodes: varargs[JSValueConst]): JSValue {.jsfunc.} =
    ctx.replaceWithImpl(this.asNode, nodes)

  proc remove(ctx: JSContext; this: DocumentType) {.jsfunc.} =
    this.asNode.removeImpl(ctx)

# NodeIterator
jsClassDef(NodeIteratorLike): # fake class
  jsextends CollectionLikeDef

proc filter(ctx: JSContext; this: NodeIteratorLike; node: Node): Opt[uint32] =
  if this.active:
    JS_ThrowDOMException(ctx, "InvalidStateError", "nested filter call")
    return err()
  let n = 1u32 shl (uint32(node.nodeType) - 1)
  if (this.whatToShow and n) == 0:
    return ok(uint32(nfrSkip))
  if this.filter == nil:
    return ok(uint32(nfrAccept))
  let node = ctx.toJS(node)
  if JS_IsException(node):
    return err()
  this.active = true
  #TODO call user object's operation (prepare etc.)
  let filter = JS_DupValue(ctx, this.filter.value)
  let val = if JS_IsFunction(ctx, filter):
    ctx.callSink(filter, JS_UNDEFINED, node)
  else:
    let atom = ctx.getOpaque().strRefs[jstAcceptNode]
    ctx.invokeSink(filter, atom, node)
  JS_FreeValue(ctx, filter)
  if JS_IsException(val):
    this.active = false
    return err()
  var res: uint32
  let status = ctx.fromJSFree(val, res)
  this.active = false
  if status.isErr:
    return err()
  ok(res)

template asNodeIteratorLike*[T: NodeIteratorLikeObj](x: JSRef[T]):
    NodeIteratorLike =
  NodeIteratorLike(x)

template filter(ctx: JSContext; this: NodeIterator; node: Node): Opt[uint32] =
  ctx.filter(this.asNodeIteratorLike, node)

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
  iter.adjustForRemovalImpl(node, iter.currentNode, iter.before)
  if iter.iterNode != nil:
    iter.adjustForRemovalImpl(node, iter.iterNode, iter.iterBefore)

jsClassDef(NodeIterator):
  jsextends NodeIteratorLikeDef

  jsget NodeIterator, currentNode, "referenceNode"
  jsget NodeIterator, before, "pointerBeforeReferenceNode"
  jsget NodeIterator, root
  jsget NodeIterator, whatToShow
  jsget NodeIterator, filter

  proc traverse(ctx: JSContext; this: NodeIterator; next: bool): Opt[Node] {.
      jsmfunc("previousNode", false), jsmfunc("nextNode", true).} =
    var resultNode = Node(nil)
    this.iterNode = this.currentNode
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
          return ok(Node(nil))
      resultNode = this.iterNode
      let res = ctx.filter(this, resultNode)
      if res.isErr:
        this.iterNode = Node(nil)
        return err()
      if res.get == uint32(nfrAccept):
        break
    this.currentNode = move(this.iterNode)
    this.before = this.iterBefore
    ok(move(resultNode))

  proc detach(this: NodeIterator) {.jsfunc.} =
    discard

# TreeWalker
template filter(ctx: JSContext; this: TreeWalker; node: Node): Opt[uint32] =
  ctx.filter(this.asNodeIteratorLike, node)

jsClassDef(TreeWalker):
  jsextends NodeIteratorLikeDef

  jsget TreeWalker, root
  jsget TreeWalker, whatToShow
  jsget TreeWalker, filter
  jsgetset TreeWalker, currentNode

  proc parentNode(ctx: JSContext; this: TreeWalker): Opt[Node] {.jsfunc.} =
    var node = this.currentNode
    while node != nil and node != this.root:
      node = node.parentNode.asNode
      if node != nil and ?ctx.filter(this, node) == uint32(nfrAccept):
        this.currentNode = node
        return ok(node)
    ok(Node(nil))

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
        let parent = node.parentNode.asNode
        if parent == this.root or parent == currentNode:
          node = Node(nil)
        else:
          node = parent
    ok(Node(nil))

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
        node = node.parentNode.asNode
        if node == this.root or node == nil or
            ?ctx.filter(this, node) == uint32(nfrAccept):
          return ok(Node(nil))
    ok(Node(nil))

  proc nextNode(ctx: JSContext; this: TreeWalker): Opt[Node] {.jsfunc.} =
    var node = this.currentNode.nextDescendant(this.root)
    while node != nil:
      let res = ?ctx.filter(this, node)
      if res == uint32(nfrAccept):
        this.currentNode = node
        return ok(node)
      let skip = res == uint32(nfrReject)
      node = node.nextDescendant(this.root, skip)
    ok(Node(nil))

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
        return ok(Node(nil))
      node = parent.asNode
      if ?ctx.filter(this, node) == uint32(nfrAccept):
        this.currentNode = node
        return ok(node)
    ok(Node(nil))

# DOMTokenList
proc localName(this: DOMTokenList): StaticAtom =
  StaticAtom(this.getMagic())

proc update(this: DOMTokenList; ctx: JSContext; value: sink string) =
  this.element.setAttr(ctx, this.localName, move(value))

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

proc remove(this: DOMTokenList; ctx: JSContext; toks: varargs[CAtom]) =
  var buf = ""
  for tok in this.toks:
    if tok in toks:
      continue
    if buf.len > 0:
      buf &= ' '
    buf &= $tok
  this.update(ctx, move(buf))

proc add(this: DOMTokenList; ctx: JSContext; toks: varargs[CAtom]) =
  var buf = ""
  for tok in this.toks:
    if buf.len > 0:
      buf &= ' '
    buf &= $tok
  for tok in toks:
    if tok notin this.toks:
      if buf.len > 0:
        buf &= ' '
      buf &= $tok
  this.update(ctx, move(buf))

jsClassDef(DOMTokenList):
  jsextends ElementAccessorDef

  classDef.iterable = jitValue

  proc length(this: DOMTokenList): uint32 {.jsfget.} =
    return this.toks.len

  proc item(ctx: JSContext; this: DOMTokenList; u: uint32): JSValue
      {.jsfunc.} =
    if u < this.toks.len:
      return ctx.toJS(this.toks[u])
    return JS_NULL

  proc contains(this: DOMTokenList; s: CAtom): bool {.jsfunc.} =
    return s in this.toks

  proc `$`(this: DOMTokenList): string {.jsfunc: "toString",
      jsfget: "value".} =
    var s = ""
    for i, tok in this.toks:
      if i != 0:
        s &= ' '
      s &= $tok
    move(s)

  proc add(ctx: JSContext; this: DOMTokenList; argv: varargs[JSValueConst]):
      Opt[void] {.jsfunc.} =
    var toks: seq[CAtom]
    ?ctx.fromJS(argv, toks)
    ?ctx.validateDOMTokens(toks)
    this.add(ctx, toks)
    ok()

  proc remove(ctx: JSContext; this: DOMTokenList; argv: varargs[JSValueConst]):
      Opt[void] {.jsfunc.} =
    var toks: seq[CAtom]
    ?ctx.fromJS(argv, toks)
    ?ctx.validateDOMTokens(toks)
    this.remove(ctx, toks)
    ok()

  proc toggle(ctx: JSContext; this: DOMTokenList; token: CAtom;
      force: JSValueConst = JS_UNDEFINED): Opt[bool] {.jsfunc.} =
    ?ctx.validateDOMTokens(token)
    let forceBool = JS_ToBool(ctx, force)
    if forceBool < 0:
      return err()
    if this.contains(token):
      if JS_IsUndefined(force) or forceBool == 0:
        this.remove(ctx, token)
        return ok(false)
      return ok(true)
    if JS_IsUndefined(force) or forceBool == 1:
      this.add(ctx, token)
      return ok(true)
    ok(false)

  proc replace(ctx: JSContext; this: DOMTokenList; token, newToken: CAtom):
      Opt[bool] {.jsfunc.} =
    ?ctx.validateDOMTokens(token, newToken)
    if not this.contains(token):
      return ok(false)
    var buf = ""
    for tok in this.toks:
      if buf.len > 0:
        buf &= ' '
      if tok == token:
        buf &= $newToken
      else:
        buf &= $tok
    this.update(ctx, move(buf))
    return ok(true)

  proc supports(ctx: JSContext; this: DOMTokenList; token: DOMString): JSValue
      {.jsfunc.} =
    case this.localName
    of satRel:
      const SupportedTokens = [satAlternate, satStylesheet]
      let lower = token.toOpenArray().toLowerAscii()
      return ctx.toJS(lower.toStaticAtom() in SupportedTokens)
    else:
      return JS_ThrowTypeError(ctx,
        "no supported tokens defined for attribute")

  proc getter(ctx: JSContext; this: DOMTokenList; atom: JSAtom): JSValue
      {.jsgetownprop.} =
    var u: uint32
    case ctx.fromIdx(atom, u)
    of fiIdx: ctx.item(this, u).uninitIfNull()
    of fiStr: JS_UNINITIALIZED
    of fiErr: JS_EXCEPTION

# DOMStringMap
proc toDataStr(name: DOMString): CAtom =
  let s = "data-" & name.toOpenArray().camelToKebabCase()
  s.toAtom()

jsClassDef(DOMStringMap):
  jsextends ElementAccessorDef

  proc delete(ctx: JSContext; map: DOMStringMap; name: DOMString): bool {.
      jsfunc.} =
    let name = name.toDataStr()
    let i = map.target.asElement.findAttr(name)
    if i >= 0:
      map.target.asElement.delAttr(ctx, i)
    return i >= 0

  proc getter(ctx: JSContext; map: DOMStringMap; name: DOMString): JSValue
      {.jsgetownprop.} =
    let name = name.toDataStr()
    let i = map.target.asElement.findAttr(name)
    if i >= 0:
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
    ?ctx.validateAttrName($name)
    map.target.asElement.setAttr(ctx, name, value)
    ok()

  proc names(ctx: JSContext; map: DOMStringMap): JSPropertyEnumList
      {.jspropnames.} =
    var list = newJSPropertyEnumList(ctx, uint32(map.target.attrs.len))
    for attr in map.target.attrs:
      let k = $attr.name
      if k.startsWith("data-") and AsciiUpperAlpha notin k:
        list.incl(k["data-".len .. ^1].kebabToCamelCase())
    return list

# NodeList
jsClassPublicDef(NodeList):
  jsextends CollectionDef

  classDef.iterable = jitValue

  proc length(this: NodeList): uint32 {.jsfget.} =
    return this.asCollection.getLength()

  proc item(ctx: JSContext; this: NodeList; u: uint32): Node {.jsfunc.} =
    if u < this.length:
      return this.snapshot[u]
    Node(nil)

  proc getter(ctx: JSContext; this: NodeList; atom: JSAtom): JSValue
      {.jsgetownprop.} =
    var u: uint32
    case ctx.fromIdx(atom, u)
    of fiIdx: ctx.toJS(ctx.item(this, u)).uninitIfNull()
    of fiStr: JS_UNINITIALIZED
    of fiErr: JS_EXCEPTION

  proc names(ctx: JSContext; this: NodeList): JSPropertyEnumList
      {.jspropnames.} =
    let L = this.length
    var list = newJSPropertyEnumList(ctx, L)
    for u in 0 ..< L:
      list.add(u)
    return list

# HTMLCollection
template asHTMLCollection*[T: HTMLCollectionObj](x: JSRef[T]): HTMLCollection =
  HTMLCollection(x)

jsClassPublicDef(HTMLCollection):
  jsextends CollectionDef

  classDef.iterable = jitIndexed

  proc length(this: HTMLCollection): uint32 {.jsfget.} =
    return this.asCollection.getLength()

  proc item*(this: HTMLCollection; u: uint32): Element {.jsfunc.} =
    if u < this.length:
      return this.snapshot[int(u)] as Element
    Element(nil)

  proc namedItem*(this: HTMLCollection; atom: CAtom): Element {.jsfunc.} =
    if atom != satUempty:
      this.asCollection.refreshCollection()
      for it in this.snapshot:
        let it = it as Element
        if it.id == atom or
            it.namespaceURI == satNamespaceHTML and it.name == atom:
          return it
    Element(nil)

  proc getter*(ctx: JSContext; this: HTMLCollection; atom: JSAtom): JSValue
      {.jsgetownprop.} =
    var u: uint32
    var s: CAtom
    case ctx.fromIdx(atom, u, s)
    of fiIdx: ctx.toJS(this.item(u)).uninitIfNull()
    of fiStr: ctx.toJS(this.namedItem(s)).uninitIfNull()
    of fiErr: JS_EXCEPTION

  proc names*(ctx: JSContext; this: HTMLCollection): JSPropertyEnumList
      {.jspropnames.} =
    let L = this.length
    var list = newJSPropertyEnumList(ctx, L)
    for u in 0 ..< L:
      list.add(u)
    for u in 0 ..< L:
      let element = this.item(u)
      if element == nil:
        continue
      if element.id != satUempty:
        list.incl($element.id)
      if element.namespaceURI == satNamespaceHTML and
          element.name != CAtomNull and element.name != satUempty:
        list.incl($element.name)
    return list

# HTMLAllCollection
jsClassDef(HTMLAllCollection):
  jsextends CollectionDef

  proc length(this: HTMLAllCollection): uint32 {.jsfget.} =
    this.asCollection.getLength()

  proc item(this: HTMLAllCollection; u: uint32): Element {.jsfunc.} =
    if u < this.length:
      return this.snapshot[u] as Element
    Element(nil)

  proc getter(ctx: JSContext; this: HTMLAllCollection; atom: JSAtom): JSValue
      {.jsgetownprop.} =
    var u: uint32
    case ctx.fromIdx(atom, u)
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

# Attr
proc newAttr(element: Element; dataIdx: int): Attr =
  jsNew AttrObj(
    internalNext: element.asNode.document.asNode,
    dataIdx: dataIdx,
    ownerElement: element,
  )

proc newAttr(document: Document; data: AttrData): Attr =
  let dummy = jsNew AttrDummyElementObj(
    internalNext: document.asNode,
    attrs: @[data]
  )
  if dummy == nil:
    return Attr(nil)
  newAttr(dummy.asElement, 0)

proc data(attr: Attr): lent AttrData =
  return attr.ownerElement.attrs[attr.dataIdx]

jsClassDef(Attr):
  jsextends NodeDef

  proc name(attr: Attr): lent CAtom {.jsfget.} =
    return attr.data.name

  proc namespaceURI(attr: Attr): lent CAtom {.jsfget.} =
    return attr.data.namespace

  proc prefix(ctx: JSContext; attr: Attr): JSValue {.jsfget.} =
    if attr.namespaceURI != CAtomNull:
      let name = attr.name
      let i = name.find(':')
      if i >= 0:
        return ctx.toJS(($name).toOpenArray(0, i - 1))
    return JS_NULL

  proc localName(ctx: JSContext; attr: Attr): JSValue {.jsfget.} =
    let name = attr.name
    if attr.namespaceURI != CAtomNull:
      let i = name.find(':')
      if i >= 0:
        return ctx.toJS(($name).toOpenArray(i + 1, name.len - 1))
    return ctx.toJS(name)

  proc value(attr: Attr): string {.jsfget.} =
    return attr.data.value

  proc setValue(ctx: JSContext; attr: Attr; ds: DOMString) {.
      jsfset: "value".} =
    attr.ownerElement.setAttr(ctx, attr.data.name, ds)

  proc jsOwnerElement(attr: Attr): Element {.jsfget: "ownerElement".} =
    if attr.ownerElement of AttrDummyElement:
      return Element(nil)
    return attr.ownerElement

# NamedNodeMap
proc findAttr(map: NamedNodeMap; dataIdx: int): int =
  for i, attr in map.attrlist.mypairs:
    if attr.dataIdx == dataIdx:
      return i
  return -1

proc getAttr(map: NamedNodeMap; dataIdx: int): Attr =
  let i = map.findAttr(dataIdx)
  if i >= 0:
    return map.attrlist[i]
  let attr = map.element.newAttr(dataIdx)
  if attr != nil:
    map.attrlist.add(attr)
  return attr

jsClassDef(NamedNodeMap):
  jsextends ElementAccessorDef

  proc mark(rt: JSRuntime; map: NamedNodeMap; markFunc: JS_MarkFunc)
      {.jsmark.} =
    for attr in map.attrlist:
      rt.markObj(attr, markFunc)

  proc getNamedItem(map: NamedNodeMap; qualifiedName: CAtom): Attr {.
      jsfunc.} =
    let i = map.element.findAttr(qualifiedName)
    if i >= 0:
      return map.getAttr(i)
    return Attr(nil)

  proc getNamedItemNS(map: NamedNodeMap; namespace, localName: CAtom):
      Attr {.jsfunc.} =
    let i = map.element.findAttrNS(namespace, localName)
    if i >= 0:
      return map.getAttr(i)
    return Attr(nil)

  proc length(map: NamedNodeMap): uint32 {.jsfget.} =
    return uint32(map.element.attrs.len)

  proc item(map: NamedNodeMap; u: uint32): Attr {.jsfunc.} =
    if int64(u) < int64(map.element.attrs.len):
      return map.getAttr(int(u))
    return Attr(nil)

  proc getter(ctx: JSContext; this: NamedNodeMap; atom: JSAtom): JSValue
      {.jsgetownprop.} =
    var u: uint32
    var s: CAtom
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
      let name = attr.name
      if element.namespaceURI == satNamespaceHTML and AsciiUpperAlpha in name:
        continue
      list.incl($name)
    return list

# Element
proc hash(element: Element): Hash =
  hash(cast[pointer](element))

proc isFirstVisualNode*(element: Element): bool =
  let parent = element.parentNode
  if parent != nil and element.elIndex == 0:
    for child in parent.childList:
      if child == element:
        return true
      if (let text = child as Text; text != nil):
        if not text.data.s.onlyWhitespace():
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
      if (let text = child as Text; text != nil):
        if not text.data.s.onlyWhitespace():
          break
  return false

proc isVisuallyEmpty*(element: Element): bool =
  for child in element.asParentNode.childList:
    if child of Element:
      return false
    if (let text = child as Text; text != nil):
      if not text.data.s.onlyWhitespace():
        return false
  true

proc tagTypeNoNS*(element: Element): TagType =
  return element.localName.toTagType()

proc tagType*(element: Element; namespace = satNamespaceHTML): TagType =
  if element.namespaceURI != namespace:
    return ttUnknown
  return element.tagTypeNoNS

proc normalizeAttrQName(element: Element; qualifiedName: CAtom):
    CAtom =
  if element.namespaceURI == satNamespaceHTML and
      not element.asNode.document.isxml:
    return qualifiedName.toLowerAscii()
  return qualifiedName

proc cmpAttrName(a: AttrData; b: CAtom): int =
  return cmp(a.name, b)

proc findAttr(element: Element; qualifiedName: CAtom): int =
  let qualifiedName = element.normalizeAttrQName(qualifiedName)
  let n = element.attrs.lowerBound(qualifiedName, cmpAttrName)
  if n < element.attrs.len and element.attrs[n].name == qualifiedName:
    return n
  return -1

proc findAttr*(element: Element; name: StaticAtom): int =
  element.findAttr(name.view())

proc getAttr*(element: Element; i: int): lent string =
  element.attrs[i].value

proc findAttrNS(element: Element; namespace, localName: CAtom): int =
  if namespace == CAtomNull:
    for i, attr in element.attrs.mypairs:
      if attr.namespace == CAtomNull and attr.name == localName:
        return i
    return -1
  # Potentially slow path, since we don't store namespace prefixes separately.
  # Still preferable to wasting memory on XML brain damage.
  for i, attr in element.attrs.mypairs:
    if attr.namespace == namespace and attr.name.matchesLocalName(localName):
      return i
  return -1

proc getAccessor(element: Element; magic: StaticAtom): ElementAccessor =
  var it = element.accessorsHead
  while it != nil:
    if it.getMagic() == uint32(magic):
      return it
    it = it.nextAccessor
  ElementAccessor(nil)

proc addAccessor(element: Element; accessor: ElementAccessor;
    name: StaticAtom) =
  accessor.setMagic(uint32(name))
  accessor.nextAccessor = move(element.accessorsHead)
  element.accessorsHead = accessor

proc getCachedAttributes(element: Element): NamedNodeMap =
  element.getAccessor(satAttributes) as NamedNodeMap

proc attr*(element: Element; s: CAtom): lent string =
  let i = element.findAttr(s)
  if i >= 0:
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

proc attrb*(element: Element; s: CAtom): bool =
  return element.findAttr(s) >= 0

proc attrb*(element: Element; at: StaticAtom): bool =
  return element.attrb(at.view())

proc isDisplayed(element: Element): bool =
  element.ensureStyle()
  return element.computed{"display"} != DisplayNone

proc nextDisplayedElement(element: Element): Element =
  for child in element.asParentNode.elementList:
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
    element = element.asNode.parentElement
    if element == nil:
      break
  # done
  Element(nil)

# Does this precede other?
proc precedes(this, other: Element): bool =
  var other = other
  while other != nil:
    if other == this:
      return true
    let otherParent = other.asNode.parentElement
    var this = this
    while this != nil:
      let thisParent = this.asNode.parentElement
      if thisParent == otherParent:
        return this.elIndex < other.elIndex
      this = thisParent
    other = otherParent
  false

proc findAncestorIncl*(element: Element; tagType: TagType): Element =
  for element in element.branchElems:
    if element.tagType == tagType:
      return element
  Element(nil)

proc scriptingEnabled(element: Element): bool =
  return element.asNode.document.scriptingEnabled

proc parseFragment*(ctx: JSContext; target: ParentNode; s: openArray[char]):
    DocumentFragment =
  # target is DocumentFragment or Element
  #TODO xml
  var element = target as Element
  if element == nil:
    element = (target as DocumentFragment).host
  let newChildren = parseHTMLFragment(ctx, element, s)
  let fragment = target.asNode.document.newDocumentFragment()
  if fragment != nil:
    for child in newChildren:
      fragment.asParentNode.append(ctx, child)
  return fragment

type InsertAdjacentPosition = enum
  iapBeforeBegin = "beforebegin"
  iapAfterEnd = "afterend"
  iapAfterBegin = "afterbegin"
  iapBeforeEnd = "beforeend"

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
      ctx.insertBefore(this.parentNode.asNode, node, jsNull(this))
  of iapAfterBegin: ctx.insertBefore(this, node, jsNull(this.firstChild))
  of iapBeforeEnd: ctx.insertBefore(this, node, jsNull(Node))
  of iapAfterEnd:
    ctx.insertBefore(this.parentNode.asNode, node, jsNull(this.nextSibling))

proc hover*(element: Element): bool =
  return efHover in element.flags

proc setHover*(element: Element; hover: bool) =
  if element.hover != hover:
    element.flags.toggle({efHover})
    element.invalidate(dtHover)

proc parseColor(element: Element; s: DOMString): Opt[ARGBColor] =
  var ctx = initCSSParser(s)
  if color := ctx.parseColor():
    case color.t
    of cctArgb, cctOklab: return ok(color.argb())
    of cctCurrent:
      let window = element.asNode.document.window
      if window != nil and window.settings.scripting == smApp and
          element.asNode.isConnected():
        element.ensureStyle()
        if element.computed{"color"}.t in {cctArgb, cctOklab}:
          return ok(element.computed{"color"}.argb())
      return ok(rgba(0, 0, 0, 255))
    of cctCell: discard
  return err()

proc parseColorImpl(target: EventTarget; s: DOMString): Opt[ARGBColor] {.
    exportc: "cha_$1".} =
  return (target as Element).parseColor(s)

proc getBlockRect(element: Element): DOMRect =
  let window = element.asNode.document.window
  if window != nil:
    if window.settings.scripting != smApp:
      return element.getBoundingClientRect()
    window.ensureLayout(element)
    let res = element.getClientRects(firstOnly = true, blockOnly = true)
    if res.len > 0:
      return res[0]
  return DOMRect(nil)

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

proc reflectScriptAttr(element: Element; name: StaticAtom; value: string):
    bool =
  let document = element.asNode.document
  for (n, t) in ScriptEventMap:
    if n == name:
      let target = element.getEventTarget(t)
      if target != nil:
        document.reflectEvent(target, n, t, value)
      return true
  false

proc reflectLocalAttr(element: Element; name: StaticAtom; has: bool;
    value: string) =
  case element.tagType
  of ttLink:
    let link = element as HTMLLinkElement
    if name == satRel:
      link.asElement.reflectTokens(link.relList, satRel, value) # do not return
    let document = link.asNode.document
    let connected = link.asNode.isConnected()
    if name == satDisabled:
      let wasDisabled = link.isDisabled()
      link.enabled = some(not has)
      let disabled = link.isDisabled()
      if wasDisabled != disabled:
        for sheet in link.asSheetElement.sheets:
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
  of ttA:
    let anchor = element as HTMLAnchorElement
    if name == satRel:
      anchor.asElement.reflectTokens(anchor.relList, satRel, value)
  of ttCanvas:
    if element.scriptingEnabled and name in {satWidth, satHeight}:
      let w = element.attrul(satWidth).get(300)
      let h = element.attrul(satHeight).get(150)
      if w <= uint64(int.high) and h <= uint64(int.high):
        let w = int(w)
        let h = int(h)
        let canvas = element as HTMLCanvasElement
        if canvas.bitmap == nil or canvas.bitmap.width != w or
            canvas.bitmap.height != h:
          let window = element.asNode.document.window
          if canvas.ctx2d != nil and canvas.ctx2d.ps != nil:
            let i = window.pendingCanvasCtls.find(canvas.ctx2d)
            window.pendingCanvasCtls.del(i)
            canvas.ctx2d.ps.sclose()
            canvas.ctx2d = CanvasRenderingContext2D(nil)
          canvas.bitmap = NetworkBitmap(
            contentType: "image/x-cha-canvas",
            imageId: window.getImageId(),
            cacheId: -1,
            width: w,
            height: h
          )
  of ttImg:
    let image = element as HTMLImageElement
    # https://html.spec.whatwg.org/multipage/images.html#relevant-mutations
    if name == satSrc:
      image.fetchStarted = false
      let window = image.asNode.document.window
      if window != nil:
        window.loadImage(image)
  else:
    element.reflectAttributeForm(name, has, value)

# Called whenever an attribute changes on the element.
# If `has' is false, then value is "".  Otherwise, value is the new
# attribute value.
proc reflectAttr0(element: Element; name: CAtom; has: bool;
    value: string) =
  let name = name.toStaticAtom()
  case name
  of satId:
    let root = element.asNode.rootNode as RootNode
    if element.id != satUempty and root != nil:
      root.removeElementId(element)
    if has:
      element.id = value.toAtom()
    else:
      element.id = satUempty.view()
    if element.id != satUempty and root != nil:
      root.addElementId(element)
  of satName:
    if has:
      element.name = value.toAtom()
    else:
      element.name = CAtomNull
  of satClass:
    element.reflectTokens(element.classList, satClass, value)
  #TODO internalNonce
  of satStyle:
    if has:
      if element.cachedStyle == nil:
        element.cachedStyle = newCSSStyleDeclaration(element, value)
      elif element.cachedStyle.updating: # no need to re-parse
        element.cachedStyle.updating = false
      else:
        element.cachedStyle.decls = value.parseDeclarations()
    else:
      element.cachedStyle.decls.setLen(0)
  of satUnknown: discard # early return
  elif element.scriptingEnabled and element.reflectScriptAttr(name, value):
    discard
  else:
    element.reflectLocalAttr(name, has, value)

proc reflectAttr(element: Element; name: CAtom; has: bool;
    value: string) =
  element.reflectAttr0(name, has, value)
  element.asNode.document.invalidateCollections()
  element.invalidate()

proc reflectAttrDel(element: Element; name: CAtom) =
  element.reflectAttr(name, false, "")

proc reflectAttr(element: Element; attr: AttrData) =
  element.reflectAttr(attr.name, true, attr.value)

proc elIndex*(this: Element): uint32 =
  if this.parentNode == nil:
    return 0
  let parent = this.asNode.parentElement
  if parent == nil:
    return 0 # <html>
  if parent.asNode.firstChild == this:
    return 0
  if efChildElIndicesInvalid in parent.flags:
    var n = 0'u32
    for element in parent.asParentNode.elementList:
      element.setMagic(n)
      inc n
    parent.flags.excl(efChildElIndicesInvalid)
  return this.getMagic()

proc isPreviousSiblingOf*(this, other: Element): bool =
  return this.parentNode == other.parentNode and this.elIndex <= other.elIndex

proc isDisabled*(this: Element): bool =
  case this.tagType
  of ttButton, ttInput, ttSelect, ttTextarea, ttFieldset:
    if this.attrb(satDisabled):
      return true
    var lastLegend: Element
    for it in this.asNode.ancestors:
      case it.tagType
      of ttLegend: lastLegend = it
      of ttFieldset:
        if it.attrb(satDisabled):
          return it.asNode.firstChild != lastLegend
      else: discard
    return false
  of ttOptgroup:
    return this.attrb(satDisabled)
  of ttOption:
    let parent = this.asNode.parentElement
    return (parent != nil and parent.tagType == ttOptgroup and
      parent.attrb(satDisabled)) or this.attrb(satDisabled)
  else: #TODO form-associated custom element
    return false

proc newElement*(document: Document; localName: CAtom;
    namespace = satNamespaceHTML): Element =
  let tagName = ($localName).toUpperAscii().toAtom()
  return document.newElement(localName, namespace.view(), tagName)

proc isRenderBlocking(element: Element): bool =
  if element.attr(satBlocking).containsToken("render"):
    return true
  let script = element as HTMLScriptElement
  if script != nil:
    if script.scriptType == stClassic and script.parserDocument != nil and
        not element.attrb(satAsync) and not element.attrb(satDefer):
      return true
  return false

proc blockRendering(element: Element) =
  let document = element.asNode.document
  if document.contentType == satTextHtml and document.findFirst(ttBody) == nil:
    document.renderBlockingElements.add(element)

proc invalidate*(element: Element) =
  element.asNode.document.invalid = true
  var node = element.asNode
  while node != nil:
    var skip = false
    let desc = node as Element
    if desc != nil:
      skip = desc.computed == nil or efRestyle in desc.flags
      desc.flags.incl(efRestyle)
    node = node.nextDescendant(element.asNode, skip)

proc ensureStyle*(element: Element) =
  if element.computed == nil or efRestyle in element.flags:
    element.flags.excl(efRestyle)
    element.applyStyle()

proc hasInsertionSteps(element: Element): bool =
  element.tagType in {ttLink, ttImg, ttStyle, ttScript} or
    element.tagType(satNamespaceSVG) == ttSvg or
    element.hasInsertionStepsForm()

proc hasClass*(element: Element; class: CAtom): bool =
  if efQuirks in element.flags:
    return element.classList.containsIgnoreCase(class)
  return element.classList.contains(class)

proc hasId*(element: Element; id: CAtom): bool =
  if efQuirks in element.flags:
    return element.id.equalsIgnoreCase(id)
  return element.id == id

# Returns true if has post-connection steps.
proc insertionSteps(element: Element): bool =
  case element.tagType
  of ttLink:
    let link = element as HTMLLinkElement
    let document = link.asNode.document
    if link.asNode.isConnected() and document.sheetTitle == "" and
        link.enabled.get(true) and
        not link.relList.containsIgnoreCase(satAlternate):
      document.sheetTitle = link.asElement.attr(satTitle)
    let window = document.window
    if window != nil:
      window.loadLink(link)
  of ttImg:
    let window = element.asNode.document.window
    if window != nil:
      let image = element as HTMLImageElement
      window.loadImage(image)
  of ttStyle:
    let style = element as HTMLStyleElement
    if style.asNode.isConnected():
      let document = style.asNode.document
      if document.sheetTitle == "":
        document.sheetTitle = style.asElement.attr(satTitle)
      style.updateSheet()
  of ttScript:
    return true
  elif element.tagType(satNamespaceSVG) == ttSvg:
    #TODO this doesn't work if JS adds descendants to the SVG tag
    let svg = element as SVGSVGElement
    let document = svg.asNode.document
    if svg.parserDocument != document:
      let window = document.window
      if window != nil:
        window.loadSVG(svg)
  else:
    element.insertionStepsForm()
  false

proc removingSteps(element: Element) =
  # We'll have to restyle on insert anyway, so don't keep style/layout data
  # alive for out-of-tree elements.
  unlinkElementBox(element)
  element.box = nil
  element.computed = nil
  if (let element = element as SheetElement; element != nil):
    element.removeSheet()
  else:
    element.removingStepsForm()

proc postConnectionSteps(element: Element; ctx: JSContext) =
  let script = element as HTMLScriptElement
  if script.asNode.isConnected and script.parserDocument == nil:
    script.prepare(ctx)

proc delAttr(element: Element; ctx: JSContext; i: int) =
  let name = element.attrs[i].name
  element.asNode.queueMutationRecord(ctx, mrtAttributes, name, CAtomNull,
    nil, true, element.attrs[i].value, [], [], Node(nil), Node(nil))
  let map = element.getCachedAttributes()
  if map != nil:
    # delete from attrlist + adjust indices invalidated
    var j = -1
    for k, attr in map.attrlist.mypairs:
      if attr.dataIdx == i:
        j = k
      elif attr.dataIdx > i:
        dec attr.dataIdx
    if j >= 0:
      let attr = map.attrlist[j]
      #TODO OOM
      attr.ownerElement = (jsNew AttrDummyElementObj(
        internalNext: attr.asNode.document.asNode,
        attrs: @[attr.data]
      )).asElement
      attr.dataIdx = 0
      map.attrlist.del(j) # ordering does not matter
  element.attrs.delete(i) # ordering matters
  element.reflectAttrDel(name)

proc delAttr(element: Element; ctx: JSContext; name: CAtom) =
  let i = element.findAttr(name)
  if i >= 0:
    element.delAttr(ctx, i)

proc setAttr(element: Element; ctx: JSContext; name: CAtom;
    value: sink string) =
  var i = element.attrs.upperBound(name, cmpAttrName)
  if i > 0 and element.attrs[i - 1].name == name:
    dec i
    element.asNode.queueMutationRecord(ctx, mrtAttributes, name,
      CAtomNull, nil, true, element.attrs[i].value, [], [], Node(nil),
      Node(nil))
    element.attrs[i].value = value
  else:
    element.asNode.queueMutationRecord(ctx, mrtAttributes, name,
      CAtomNull, nil, false, "", [], [], Node(nil), Node(nil))
    element.attrs.insert(AttrData(name: name, value: value), i)
  element.reflectAttr(element.attrs[i])

proc setAttr*(element: Element; ctx: JSContext; name: StaticAtom;
    value: sink string) =
  element.setAttr(ctx, name.view(), value)

proc setAttr(element: Element; ctx: JSContext; name: CAtom;
    value: DOMString) =
  var i = element.attrs.upperBound(name, cmpAttrName)
  if i > 0 and element.attrs[i - 1].name == name:
    dec i
    element.asNode.queueMutationRecord(ctx, mrtAttributes, name,
      CAtomNull, nil, true, element.attrs[i].value, [], [], Node(nil),
      Node(nil))
    element.attrs[i].value = $value
  else:
    element.asNode.queueMutationRecord(ctx, mrtAttributes, name,
      CAtomNull, nil, false, "", [], [], Node(nil), Node(nil))
    element.attrs.insert(AttrData(name: name, value: $value), i)
  element.reflectAttr(element.attrs[i])

proc setAttr*(element: Element; ctx: JSContext; name: StaticAtom;
    value: DOMString) =
  element.setAttr(ctx, name.view(), value)

proc sinkAttrs*(element: Element; attrs: sink seq[AttrData]) =
  element.attrs = move(attrs)
  for attr in element.attrs:
    element.reflectAttr(attr)

proc addAttrsIfMissing*(element: Element; attrs: seq[AttrData]) =
  for attr in attrs:
    var i = element.attrs.upperBound(attr.name, cmpAttrName)
    if i <= 0 or element.attrs[i - 1].name != attr.name:
      element.attrs.insert(attr, i)
      element.reflectAttr(element.attrs[i])

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
  return element.asNode.document.charset

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
  of ttImg:
    return (element as HTMLImageElement).bitmap
  of ttCanvas:
    let bmp = (element as HTMLCanvasElement).bitmap
    if bmp != nil and bmp.cacheId != -1:
      return bmp
    return nil
  elif element.tagType(satNamespaceSVG) == ttSvg:
    return (element as SVGSVGElement).bitmap
  else:
    return nil

proc setShadowRoot(this: Element; shadow: ShadowRoot) =
  if this.internalFirst != nil:
    shadow.internalNext = move(this.internalFirst)
  this.internalFirst = shadow.asNode

proc getComputedStyle*(element: Element; pseudo: PseudoElement): CSSValues =
  var computed = element.computed
  while computed != nil:
    if computed.pseudo == pseudo:
      return computed
    computed = computed.next
  nil

proc getDOMTokenList*(element: Element; arr: DOMTokenArray; name: StaticAtom):
    DOMTokenList =
  var list = element.getAccessor(name) as DOMTokenList
  if list == nil:
    list = jsNew DOMTokenListObj(
      element: element,
      toks: DOMTokenArrayView(arr)
    )
    if list == nil:
      return list
    element.addAccessor(list.asElementAccessor, name)
  list

proc reflectTokens*(element: Element; arr: var DOMTokenArray; name: StaticAtom;
    value: string) =
  if value == "":
    arr = DOMTokenArray(nil)
  else:
    var toks = newSeqOfCap[CAtom](16)
    for x in value.split(AsciiWhitespace):
      if x != "":
        let a = x.toAtom()
        if a notin toks:
          toks.add(a)
    arr = newDOMTokenArray(toks)
    let list = element.getAccessor(name) as DOMTokenList
    if list != nil:
      # arr is guaranteed to outlive the DOMTokenList because the latter
      # references element
      list.toks = DOMTokenArrayView(arr)

proc shadowRoot(this: Element): ShadowRoot =
  this.internalFirst as ShadowRoot

jsClassPublicDef(Element):
  jsextends ParentNodeDef

  jsget Element, namespaceURI
  jsget Element, localName
  jsget Element, id
  jsget Element, tagName

  proc finalize(rt: JSRuntime; element: Element) {.jsfin.} =
    unlinkElementBox(element)

  proc getClassList(this: Element): DOMTokenList {.jsnfget: "classList".} =
    this.getDOMTokenList(this.classList, satClass)

  proc firstElementChild*(this: Element): Element {.jsfget.} =
    return this.asParentNode.firstElementChild

  proc lastElementChild*(this: Element): Element {.jsfget.} =
    return this.asParentNode.lastElementChild

  proc childElementCount(this: Element): uint32 {.jsfget.} =
    return this.asParentNode.childElementCountImpl

  proc innerHTML(element: Element): string {.jsfget.} =
    #TODO xml
    return element.asNode.serializeFragment(writeShadow = true)

  proc outerHTML(element: Element): string {.jsfget.} =
    #TODO xml
    result = ""
    result.serializeFragmentInner(element.asNode, ttUnknown,
      writeShadow = true)

  proc prefix(element: Element): string {.jsfget.} =
    let i = element.tagName.find(':')
    if i < 0:
      return ""
    return ($element.tagName).substr(0, i - 1)

  proc hasAttributes(element: Element): bool {.jsfunc.} =
    return element.attrs.len > 0

  proc attributes(element: Element): NamedNodeMap {.jsnfget.} =
    var map = element.getCachedAttributes()
    if map == nil:
      map = jsNew NamedNodeMapObj(element: element)
      if map != nil:
        element.addAccessor(map.asElementAccessor, satAttributes)
    map

  proc hasAttribute(element: Element; qualifiedName: CAtom): bool
      {.jsfunc.} =
    return element.findAttr(qualifiedName) >= 0

  proc hasAttributeNS(element: Element; namespace, localName: CAtom):
      bool {.jsfunc.} =
    return element.findAttrNS(namespace, localName) >= 0

  proc getAttributeNames(ctx: JSContext; element: Element): JSValue
      {.jsfunc.} =
    var s = newSeqOfCap[JSValue](element.attrs.len)
    for it in element.attrs:
      s.add(ctx.toJS(it.name))
    return ctx.newArrayFrom(s)

  proc getAttribute(ctx: JSContext; element: Element;
      qualifiedName: CAtom): JSValue {.jsfunc.} =
    let i = element.findAttr(qualifiedName)
    if i >= 0:
      return ctx.toJS(element.attrs[i].value)
    return JS_NULL

  proc getAttributeNS(ctx: JSContext; element: Element;
      namespace, localName: CAtom): JSValue {.jsfunc.} =
    let i = element.findAttrNS(namespace, localName)
    if i >= 0:
      return ctx.toJS(element.attrs[i].value)
    return JS_NULL

  proc getElementsByTagName(element: Element; tagName: CAtom):
      HTMLCollection {.jsnfunc.} =
    element.asParentNode.getElementsByTagNameImpl(tagName)

  proc getElementsByClassName(element: Element; classNames: DOMString):
      HTMLCollection {.jsnfunc.} =
    element.asParentNode.getElementsByClassNameImpl(classNames)

  proc children(element: Element): HTMLCollection {.jsnfget.} =
    element.asParentNode.childrenImpl

  proc previousElementSibling*(element: Element): Element {.jsfget.} =
    return element.asNode.previousElementSiblingImpl

  proc nextElementSibling*(element: Element): Element {.jsfget.} =
    return element.asNode.nextElementSiblingImpl

  proc before(ctx: JSContext; this: Element; nodes: varargs[JSValueConst]):
      Opt[void] {.jsfunc.} =
    ctx.beforeImpl(this.asNode, nodes)

  proc after(ctx: JSContext; this: Element; nodes: varargs[JSValueConst]):
      Opt[void] {.jsfunc.} =
    ctx.afterImpl(this.asNode, nodes)

  proc replaceWith(ctx: JSContext; this: Element;
      nodes: varargs[JSValueConst]): JSValue {.jsfunc.} =
    ctx.replaceWithImpl(this.asNode, nodes)

  proc remove(ctx: JSContext; this: Element) {.jsfunc.} =
    this.asNode.removeImpl(ctx)

  proc scrollTo(element: Element) {.jsfunc.} =
    discard #TODO maybe in app mode?

  proc scrollIntoView(element: Element) {.jsfunc.} =
    discard #TODO ditto

  proc setInnerHTML(ctx: JSContext; element: Element; s: DOMStringNull)
      {.jsfset: "innerHTML".} =
    let fragment = ctx.parseFragment(element.asParentNode,
      s.toOpenArray()).asNode
    if fragment != nil:
      let templ = element as HTMLTemplateElement
      let nodeCtx = if templ != nil:
        templ.content.asParentNode
      else:
        element.asParentNode
      nodeCtx.replaceAll(ctx, fragment)

  proc outerHTML(ctx: JSContext; element: Element; s: DOMStringNull): JSValue
      {.jsfset.} =
    let parent0 = element.parentNode
    if parent0 == nil:
      return JS_UNDEFINED
    if parent0 of Document:
      return JS_ThrowDOMException(ctx, "NoModificationAllowedError",
        "outerHTML is disallowed for document elements")
    let parent = if parent0 of DocumentFragment:
      element.asNode.document.newHTMLElement(ttBody).asElement
    else:
      # neither a document, nor a document fragment => parent must be an
      # element node
      parent0 as Element
    let fragment = ctx.parseFragment(parent.asParentNode, s.toOpenArray())
    if fragment == nil:
      return JS_ThrowOutOfMemory(ctx)
    ctx.replaceChildWithThrow(parent.asNode, element.asNode, fragment.asNode)

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
      nodeCtx = this.asNode.parentElement
    if nodeCtx == nil or
        not this.asNode.document.isxml and nodeCtx.tagType == ttHtml:
      nodeCtx = this.asNode.document.newHTMLElement(ttBody).asElement
      if nodeCtx == nil:
        return JS_ThrowOutOfMemory(ctx)
    let fragment = ctx.parseFragment(nodeCtx.asParentNode,
      text.toOpenArray()).asNode
    if fragment == nil:
      return JS_ThrowOutOfMemory(ctx)
    case position
    of iapBeforeBegin: this.parentNode.insert(ctx, fragment, this.asNode)
    of iapAfterBegin:
      this.asParentNode.insert(ctx, fragment, this.asNode.firstChild)
    of iapBeforeEnd: this.asParentNode.append(ctx, fragment)
    of iapAfterEnd:
      this.parentNode.insert(ctx, fragment, this.asNode.nextSibling)
    return JS_UNDEFINED

  proc insertAdjacentElement(ctx: JSContext; this: Element;
      position: DOMString; element: Element): JSValue {.jsfunc.} =
    ctx.insertAdjacent(this.asNode, position, element.asNode)

  proc insertAdjacentText(ctx: JSContext; this: Element;
      position, s: DOMString): JSValue {.jsfunc.} =
    let text = this.asNode.document.newText(s).asNode
    if text == nil:
      return JS_ThrowOutOfMemory(ctx)
    ctx.toUndefined(ctx.insertAdjacent(this.asNode, position, text))

  proc getBoundingClientRect(element: Element): DOMRect {.jsfunc.} =
    let window = element.asNode.document.window
    if window == nil:
      return jsNew DOMRectObj()
    if window.settings.scripting == smApp:
      window.ensureLayout(element)
      let objs = getClientRects(element, firstOnly = true, blockOnly = false)
      if objs.len > 0:
        return objs[0]
      return jsNew DOMRectObj()
    var width = float64(dummyAttrs.ppc)
    var height = float64(dummyAttrs.ppl)
    let img = element as HTMLImageElement
    if img != nil:
      (width, height) = img.getImageRect()
    jsNew DOMRectObj(width: width, height: height)

  proc getClientRects(element: Element): DOMRectList {.jsnfunc.} =
    let res = jsNew DOMRectListObj()
    if res != nil:
      let window = element.asNode.document.window
      if window != nil:
        if window.settings.scripting == smApp:
          window.ensureLayout(element)
          res.list = getClientRects(element, firstOnly = false,
            blockOnly = false)
        else:
          res.list.add(element.getBoundingClientRect())
    res

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

  proc querySelector(ctx: JSContext; this: Element; q: DOMString): JSValue
      {.jsfunc.} =
    return ctx.querySelectorImpl(this.asParentNode, q)

  proc querySelectorAll(ctx: JSContext; this: Element; q: DOMString): JSValue
      {.jsfunc.} =
    return ctx.querySelectorAllImpl(this.asParentNode, q)

  proc prepend(ctx: JSContext; this: Element; nodes: varargs[JSValueConst]):
      JSValue {.jsfunc.} =
    return ctx.prependImpl(this.asNode, nodes)

  proc append(ctx: JSContext; this: Element; nodes: varargs[JSValueConst]):
      JSValue {.jsfunc.} =
    return ctx.appendImpl(this.asNode, nodes)

  proc replaceChildren(ctx: JSContext; this: Element;
      nodes: varargs[JSValueConst]): JSValue {.jsfunc.} =
    return ctx.replaceChildrenImpl(this.asNode, nodes)

  proc setAttribute(ctx: JSContext; element: Element;
      qualifiedName, value: DOMString): Opt[void] {.jsfunc.} =
    ?ctx.validateAttrName(qualifiedName.toOpenArray())
    let qualifiedName = if element.namespaceURI == satNamespaceHTML and
        not element.asNode.document.isxml:
      qualifiedName.toAtomLower()
    else:
      qualifiedName.toAtom()
    element.setAttr(ctx, qualifiedName, value)
    ok()

  proc setAttributeNS(ctx: JSContext; element: Element;
      namespace, qualifiedName: CAtom; value: DOMString): Opt[void]
      {.jsfunc.} =
    var namespace = namespace
    var localName = qualifiedName
    ?ctx.validateAndExtract(namespace, localName, nvAttribute)
    var i = element.findAttrNS(namespace, localName)
    if i >= 0:
      element.asNode.queueMutationRecord(ctx, mrtAttributes, qualifiedName,
        namespace, nil, true, element.attrs[i].value, [], [], Node(nil),
        Node(nil))
      element.attrs[i].value = $value
    else:
      element.asNode.queueMutationRecord(ctx, mrtAttributes, qualifiedName,
        namespace, nil, false, "", [], [], Node(nil), Node(nil))
      i = element.attrs.upperBound(qualifiedName, cmpAttrName)
      element.attrs.insert(AttrData(
        namespace: namespace,
        name: qualifiedName,
        value: $value
      ), i)
    element.reflectAttr(element.attrs[i])
    ok()

  proc removeAttribute(ctx: JSContext; element: Element;
      qualifiedName: CAtom) {.jsfunc.} =
    element.delAttr(ctx, qualifiedName)

  proc removeAttributeNS(ctx: JSContext; element: Element;
      namespace, localName: CAtom) {.jsfunc.} =
    let i = element.findAttrNS(namespace, localName)
    if i >= 0:
      element.delAttr(ctx, i)

  proc toggleAttribute(ctx: JSContext; element: Element;
      qualifiedName: DOMString; force: JSValueConst = JS_UNDEFINED): Opt[bool]
      {.jsfunc.} =
    let forceBool = JS_ToBool(ctx, force)
    if forceBool < 0:
      return err()
    ?ctx.validateAttrName(qualifiedName.toOpenArray())
    let qualifiedName = element.normalizeAttrQName(qualifiedName.toAtom())
    let i = element.findAttr(qualifiedName)
    if i < 0:
      if JS_IsUndefined(force) or forceBool == 1:
        element.setAttr(ctx, qualifiedName, "")
        return ok(true)
      return ok(false)
    if JS_IsUndefined(force) or forceBool == 0:
      element.delAttr(ctx, i)
      return ok(false)
    return ok(true)

  proc setId(ctx: JSContext; element: Element; id: DOMString) {.
      jsfset: "id".} =
    element.setAttr(ctx, satId, id)

  proc focus*(element: Element) {.jsfunc.} =
    let document = element.asNode.document
    let window = document.window
    if window != nil and window.settings.autofocus:
      document.setFocus(element)

  proc blur(element: Element) {.jsfunc.} =
    let document = element.asNode.document
    let window = document.window
    if window != nil and window.settings.autofocus:
      if document.focus == element:
        document.setFocus(Element(nil))

  proc requestFullscreen(ctx: JSContext; element: Element): JSValue
      {.jsfunc.} =
    JS_ThrowTypeError(ctx, "fullscreen is not supported")
    return ctx.newRejectedPromise()

  proc getOpenShadowRoot(this: Element): ShadowRoot {.jsfget: "shadowRoot".} =
    let shadow = this.shadowRoot
    if shadow == nil or shadow.mode == srmClosed:
      return ShadowRoot(nil)
    shadow

  proc attachShadow(ctx: JSContext; this: Element; init: ShadowRootInit):
      Opt[ShadowRoot] {.jsnfunc.} =
    let document = this.asNode.document
    let customElements = if init.customElementRegistry != nil:
      init.customElementRegistry
    else:
      document.customElements
    if customElements != nil:
      ?ctx.checkRegistryScope(document, customElements)
    if this.namespaceURI != satNamespaceHTML:
      JS_ThrowDOMException(ctx, "NotSupportedError",
        "only HTML elements can have shadow trees")
      return err()
    const AllowedTags = {
      ttArticle, ttAside, ttBlockquote, ttBody, ttDiv, ttFooter,
      ttH1, ttH2, ttH3, ttH4, ttH5, ttH6, ttHeader, ttMain,
      ttNav, ttP, ttSection, ttSpan
    }
    let validCustom = this.localName.isValidCustomElementName()
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
      let removedNodes = old.asParentNode.getChildList()
      for child in removedNodes:
        child.removeImpl(ctx)
      old.declarative = false
      return ok(old)
    let shadow = jsNew ShadowRootObj(
      host: this,
      mode: init.mode,
      delegatesFocus: init.delegatesFocus,
      #TODO available to internals
      slotAssignment: init.slotAssignment,
      clonable: init.clonable,
      serializable: init.serializable,
      customElements: customElements
    )
    if shadow != nil:
      this.setShadowRoot(shadow)
    ok(shadow)

  proc closest(ctx: JSContext; this: Element; q: DOMString): JSValue
      {.jsfunc.} =
    let selectors = ctx.parseSelectors(q)
    if selectors.len == 0:
      return JS_EXCEPTION
    for element in this.branchElems:
      if element.matchesList(selectors):
        return ctx.toJS(element)
    return JS_NULL

  proc matches(ctx: JSContext; this: Element; q: DOMString): JSValue
      {.jsfunc.} =
    let selectors = ctx.parseSelectors(q)
    if selectors.len == 0:
      return JS_EXCEPTION
    return ctx.toJS(this.matchesList(selectors))

  proc style(element: Element): CSSStyleDeclaration {.jsnfget.} =
    if element.cachedStyle == nil:
      element.cachedStyle = newCSSStyleDeclaration(element, "")
    return element.cachedStyle

  proc setStyle(ctx: JSContext; element: Element; s: CSSOMString) {.
      jsfset: "style".} =
    element.setAttr(ctx, satStyle, s)

  #TODO slot should be unscopable
  proc getAttrMagic(element: Element; magic: StaticAtom): lent string {.
      jsmfget("className", satClass), jsmfget("slot", satSlot).} =
    element.attr(magic)

  proc setAttrMagic(ctx: JSContext; element: Element; magic: StaticAtom;
      name: DOMString) {.jsmfset("className", satClass),
      jsmfset("slot", satSlot).} =
    element.setAttr(ctx, magic, name)

# AttrDummyElement
jsClassDef(AttrDummyElement): # fake class
  jsextends ElementDef

# XMLSerializer
jsClassRaw(XMLSerializerDef, "XMLSerializer"):
  proc newXMLSerializer(ctx: JSContext; ctor: JSValueConst): JSValue
      {.jsctor2.} =
    return JS_NewObjectFromCtor(ctx, ctor, classDef.id)

  proc serializeToString(ctx: JSContext; this: JSValueConst; root: Node):
      JSValue {.jsfunc.} =
    #TODO ...yeah
    var res = ""
    res.serializeFragmentInner(root, ttUnknown, writeShadow = true)
    ctx.toJS(res)

# ShadowRoot
proc globalCustomElements(this: ShadowRoot): CustomElementRegistry =
  if not this.customElements.scoped:
    return this.customElements
  let document = this.asNode.document
  if not document.customElements.scoped:
    return document.customElements
  return CustomElementRegistry(nil)

jsClassDef(ShadowRoot):
  jsextends DocumentFragmentDef

  jsget ShadowRoot, mode
  jsget ShadowRoot, delegatesFocus
  jsget ShadowRoot, slotAssignment
  jsget ShadowRoot, clonable
  jsget ShadowRoot, serializable

  proc host(this: ShadowRoot): Element {.jsfget.} =
    this.asDocumentFragment.host

  proc innerHTML(this: ShadowRoot): string {.jsfget.} =
    return this.asNode.serializeFragment(writeShadow = true)

  proc setInnerHTML(ctx: JSContext; this: ShadowRoot; s: DOMStringNull)
      {.jsfset: "innerHTML".} =
    let fragment = ctx.parseFragment(this.asParentNode, s.toOpenArray()).asNode
    if fragment != nil:
      this.asParentNode.replaceAll(ctx, fragment)

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

proc tabIsEmpty(item: DependencyItem): bool =
  item.key == nil

proc tabKeyEq(item: DependencyItem; element: Element): bool =
  item.key == (ptr ElementObj)(element)

proc tabHashFast(item: DependencyItem): Hash =
  item.hcache

proc tabKeyEq(a, b: DependencyItem): bool =
  a == b

iterator getAll(map: DependencyMap; element: Element): lent Element =
  for it in map.tab.tabGetAll(element):
    yield Element(it.value)

iterator popAll(map: var DependencyMap; element: Element): Element =
  for it in map.tab.tabPopAll(element, hash(element)):
    yield cast[Element](it.value)

proc del(map: var DependencyMap; key, value: Element) =
  let item = DependencyItem(
    key: (ptr ElementObj)(key),
    value: (ptr ElementObj)(value),
    hcache: hash(cast[pointer](key))
  )
  tabDelImpl(map.tab, map.load, item, item.hcache)

proc add0(map: var DependencyMap; item: DependencyItem) =
  let mask = map.tab.len - 1
  var item = item
  let hcache = item.hcache
  var home = hcache and mask
  for i, it in map.tab.mtabPairs(hcache):
    if it.key == nil:
      it = item
      break
    if tabSwap(home, it.hcache, i, mask): # displace
      swap(it, item)

proc add(map: var DependencyMap; key, value: Element) =
  let item = DependencyItem(
    key: (ptr ElementObj)(key),
    value: (ptr ElementObj)(value),
    hcache: hash(cast[pointer](key))
  )
  for it in map.tab.prepareTableAdd(map.load, init = 4):
    if it.key != nil:
      map.add0(it)
  map.add0(item)
  inc map.load

proc invalidate*(element: Element; dep: DependencyType) =
  if dep in element.selfDepends:
    element.invalidate()
  let document = element.asNode.document
  for it in document.styleDependencies[dep].dependedBy.getAll(element):
    it.invalidate()

proc applyStyleDependencies*(document: Document; element: Element;
    depends: DependencyInfo) =
  element.selfDepends = {}
  for t, map in document.styleDependencies.mpairs:
    for it in map.dependsOn.popAll(element):
      map.dependedBy.del(element, it)
    for el in depends[t]:
      if el == element:
        element.selfDepends.incl(t)
        continue
      map.dependedBy.add(el, element)
      map.dependsOn.add(element, el)

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
  jsNew CSSStyleDeclarationObj(
    decls: value.parseDeclarations(),
    element: element,
    computed: computed,
    readonly: readonly
  )

proc checkReadOnly(ctx: JSContext; this: CSSStyleDeclaration): Opt[void] =
  if this.readonly:
    JS_ThrowDOMException(ctx, "NoModificationAllowedError",
      "cannot modify read-only declaration")
    return err()
  ok()

proc find(this: CSSStyleDeclaration; p: CSSPropertyType): int =
  for i, decl in this.decls.mypairs:
    if decl.t == cdtProperty and decl.p.sh == cstNone and decl.p.p == p:
      return i
  return -1

proc find(this: CSSStyleDeclaration; s: openArray[char]): int =
  if s.startsWith("--"):
    let v = s.toOpenArray(2, s.high).toAtom()
    for i, decl in this.decls.mypairs:
      if decl.t == cdtVariable and decl.v == v:
        return i
    return -1
  if p := propertyType(s):
    return this.find(p)
  return -1

# Consumes toks.
proc parseDeclValue(decl: var CSSDeclaration; value: CSSOMString): Opt[void] =
  var toks = parseComponentValues(value)
  case decl.t
  of cdtProperty:
    var ctx = initCSSParser(toks)
    var dummy: seq[CSSComputedEntry] = @[]
    ?ctx.parseComputedValues0(decl.p, dummyAttrs, dummy)
  of cdtNestedRule:
    return err()
  of cdtVariable:
    if parseDeclWithVar1(toks).len == 0:
      return err()
  decl.value = move(toks)
  ok()

proc updateStyleAttr(this: CSSStyleDeclaration; ctx: JSContext) =
  this.updating = true
  this.element.setAttr(ctx, satStyle, this.cssText)

jsClassDef(CSSStyleDeclaration):
  proc cssText(this: CSSStyleDeclaration): string {.jsfget.} =
    result = ""
    if not this.computed:
      for it in this.decls:
        if result.len > 0:
          result &= ' '
        result &= $it

  proc setCSSText(ctx: JSContext; this: CSSStyleDeclaration; s: CSSOMString):
      Opt[void] {.jsfset: "cssText".} =
    ?ctx.checkReadOnly(this)
    this.element.setAttr(ctx, satStyle, s)
    ok()

  proc length(this: CSSStyleDeclaration): uint32 =
    return uint32(this.decls.len)

  proc item(ctx: JSContext; this: CSSStyleDeclaration; u: uint32): JSValue
      {.jsfunc.} =
    if u < this.length:
      return ctx.toJS(this.decls[int(u)].name)
    return ctx.toJS("")

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

  proc removeProperty(ctx: JSContext; this: CSSStyleDeclaration;
      name: CSSOMString): JSValue {.jsfunc.} =
    ?ctx.checkReadOnly(this)
    let name = name.toOpenArray().toLowerAscii()
    let value = this.getPropertyValue(name.toDOMStringView())
    let sh = shorthandType(name)
    if sh != cstNone:
      for t in ShorthandMap[sh]:
        let i = this.find(t)
        if i >= 0:
          this.decls.delete(i)
    else:
      let i = this.find(name)
      if i >= 0:
        this.decls.delete(i)
    this.updateStyleAttr(ctx)
    return ctx.toJS(value)

  proc setProperty(ctx: JSContext; this: CSSStyleDeclaration;
      name, value: CSSOMString): JSValue {.jsfunc.} =
    ?ctx.checkReadOnly(this)
    if not name.toOpenArray().isSupportedProperty():
      return JS_UNDEFINED
    if value.len == 0:
      return ctx.removeProperty(this, name)
    let name = name.toOpenArray().toLowerAscii()
    if (let i = this.find(name); i >= 0):
      if this.decls[i].parseDeclValue(value).isErr:
        return JS_UNDEFINED # ignore
    else:
      let x = initCSSDeclaration(name)
      if x.isErr:
        return JS_UNDEFINED # ignore
      var decl = x.get
      if decl.parseDeclValue(value).isErr:
        return JS_UNDEFINED # ignore
      this.decls.add(move(decl))
    this.updateStyleAttr(ctx)
    return JS_UNDEFINED

  proc setter(ctx: JSContext; this: CSSStyleDeclaration; atom: JSAtom;
      value: CSSOMString): JSValue {.jssetprop.} =
    ?ctx.checkReadOnly(this)
    var u: uint32
    var ds: DOMString
    case ctx.fromIdx(atom, u, ds)
    of fiIdx: return JS_UNINITIALIZED
    of fiStr:
      var name = $ds
      if name == "cssFloat":
        name = "float"
      name = camelToKebabCase(name)
      return ctx.setProperty(this, name.toDOMStringView(), value)
    of fiErr:
      return JS_EXCEPTION

# HTMLElement
proc newHTMLElement*(document: Document; tagType: TagType): HTMLElement =
  let element = document.newElement(tagType.toStaticAtom().view(),
    satNamespaceHTML)
  return element as HTMLElement

proc crossOrigin(element: HTMLElement): CORSAttribute =
  if not element.asElement.attrb(satCrossorigin):
    return caNoCors
  let s = element.asElement.attr(satCrossorigin)
  if s.equalsIgnoreCase("use-credentials"):
    return caUseCredentials
  caAnonymous

proc referrerPolicy(element: HTMLElement): Opt[ReferrerPolicy] =
  parseEnumNoCase[ReferrerPolicy](element.asElement.attr(satReferrerpolicy))

proc getSrc*(this: HTMLElement): tuple[src, contentType: string] =
  let src = this.asElement.attr(satSrc)
  if src != "":
    return (src, "")
  for el in this.asParentNode.elementDescendants(ttSource):
    let src = el.attr(satSrc)
    if src != "":
      return (src, el.attr(satType))
  return ("", "")

proc tagType*(element: HTMLElement): TagType =
  return element.asElement.tagTypeNoNS

type
  ReflectType = enum
    rtStr, rtStrNull, rtUrl, rtBool, rtLong, rtUlongGz, rtUlong, rtDoubleGz,
    rtReferrerPolicy, rtCrossOrigin, rtMethod, rtForm, rtDir

  ReflectEntry = object
    attrname: StaticAtom
    t: ReflectType
    u: uint32 # 32 bits of opaque associated data (mostly default values)

template makes(name: StaticAtom): ReflectEntry =
  ReflectEntry(attrname: name, t: rtStr)

template makesnull(name: StaticAtom): ReflectEntry =
  ReflectEntry(attrname: name, t: rtStrNull)

template makeurl(name: StaticAtom): ReflectEntry =
  ReflectEntry(attrname: name, t: rtUrl)

template makeb(name: StaticAtom): ReflectEntry =
  ReflectEntry(attrname: name, t: rtBool)

template makel(name: StaticAtom; default = 0'u32): ReflectEntry =
  ReflectEntry(attrname: name, t: rtLong, u: default)

template makeul(name: StaticAtom; default = 0'u32): ReflectEntry =
  ReflectEntry(attrname: name, t: rtUlong, u: default)

template makeulgz(name: StaticAtom; default = 0'u32): ReflectEntry =
  ReflectEntry(attrname: name, t: rtUlongGz, u: default)

template makerp(name: StaticAtom): ReflectEntry =
  ReflectEntry(attrname: name, t: rtReferrerPolicy)

template makeco(name: StaticAtom): ReflectEntry =
  ReflectEntry(attrname: name, t: rtCrossOrigin)

template makem(name: StaticAtom): ReflectEntry =
  ReflectEntry(attrname: name, t: rtMethod)

template makedgz(name: StaticAtom; default: uint32): ReflectEntry =
  ReflectEntry(attrname: name, t: rtDoubleGz, u: default)

template makeform(): ReflectEntry =
  ReflectEntry(attrname: satForm, t: rtForm)

template makedir(): ReflectEntry =
  ReflectEntry(attrname: satDir, t: rtDir)

# Note: this table only works for tag types with a registered interface.
type ReflectedAttr* = enum
  raTarget = "target"
  raColor = "color"
  raFace = "face"
  raSizeStr = "size"
  raValueStr = "value"
  raValueLong = "value"
  raRequired = "required"
  raReversed = "reversed"
  raName = "name"
  raOpen = "open"
  raNovalidate = "novalidate"
  raSelected = "selected"
  raRel = "rel"
  raFor = "for"
  raHttpequiv = "http-equiv"
  raContent = "content"
  raMedia = "media"
  raDatetime = "datetime"
  raType = "type"
  raCols = "cols"
  raRows = "rows"
  raSizeSelect = "size"
  raSizeInput = "size"
  raWidth = "width"
  raHeight = "height"
  raAlt = "alt"
  raSrcset = "srcset"
  raSizes = "sizes"
  raCrossorigin = "crossorigin"
  raReferrerpolicy = "referrerpolicy"
  raMethod = "method"
  raFormmethod = "formmethod"
  raUsemap = "usemap"
  raIsmap = "ismap"
  raDisabled = "disabled"
  raSrc = "src"
  raCite = "cite"
  raHref = "href"
  raData = "data"
  raValueDoubleGz = "value"
  raValuetype = "valuetype"
  raMax = "max"
  raForm = "form"
  # super-global attributes
  raTitle = "title"
  raLang = "lang"
  raDir = "dir"
  raHidden = "hidden"

const ReflectMap = [
  # non-global attributes
  raTarget: makes(satTarget),
  raColor: makesnull(satColor),
  raFace: makes(satFace),
  raSizeStr: makes(satSize),
  raValueStr: makes(satValue),
  raValueLong: makel(satValue),
  raRequired: makeb(satRequired),
  raReversed: makeb(satReversed),
  raName: makes(satName),
  raOpen: makes(satOpen),
  raNovalidate: makeb(satNovalidate),
  raSelected: makeb(satSelected),
  raRel: makes(satRel),
  raFor: makes(satFor),
  raHttpequiv: makes(satHttpEquiv),
  raContent: makes(satContent),
  raMedia: makes(satMedia),
  raDatetime: makes(satDatetime),
  raType: makes(satType),
  raCols: makeul(satCols, 20u32),
  raRows: makeul(satRows, 1u32),
  raSizeSelect: makeulgz(satSize, 0u32),
  raSizeInput: makeulgz(satSize, 20u32),
  raWidth: makeul(satWidth, 300u32),
  raHeight: makeul(satHeight, 150u32),
  raAlt: makes(satAlt),
  raSrcset: makes(satSrcset),
  raSizes: makes(satSizes),
  raCrossorigin: makeco(satCrossorigin),
  raReferrerpolicy: makerp(satReferrerpolicy),
  raMethod: makem(satMethod),
  raFormmethod: makem(satFormmethod),
  raUsemap: makes(satUsemap),
  raIsmap: makeb(satIsmap),
  raDisabled: makeb(satDisabled),
  raSrc: makeurl(satSrc),
  raCite: makeurl(satCite),
  raHref: makeurl(satHref),
  raData: makeurl(satData),
  raValueDoubleGz: makedgz(satValue, 0),
  raValuetype: makedgz(satValue, 0),
  raMax: makedgz(satMax, 1),
  raForm: makeform(),
  # super-global attributes
  raTitle: makes(satTitle),
  raLang: makes(satLang),
  raDir: makedir(),
  raHidden: makeb(satHidden)
]

const SuperGlobalAttrs = [raTitle, raLang, raDir, raHidden]

static:
  # In the reflection magic we allocate 9 bits to attribute names and 7 bits
  # to class names.
  doAssert ReflectMap.len < 512

proc jsReflectGet0(ctx: JSContext; htmlElement: HTMLElement; magic: cint):
    JSValue =
  let element = htmlElement.asElement
  let entry = ReflectMap[ReflectedAttr(uint16(magic) and 0x1FF)]
  let name = entry.attrname
  case entry.t
  of rtStr, rtStrNull: return ctx.toJS(element.attr(name))
  of rtUrl:
    let s = element.attr(name)
    if url := element.asNode.document.parseURL(s):
      return ctx.toJS($url)
    return ctx.toJS(s)
  of rtReferrerPolicy:
    if s := htmlElement.referrerPolicy:
      return ctx.toJS($s)
    return ctx.toJS("")
  of rtCrossOrigin:
    case (let co = htmlElement.crossOrigin; co)
    of caNoCors: return JS_NULL
    else: return ctx.toJS($co)
  of rtMethod:
    return ctx.toJS(element.getFormMethodAttr(name))
  of rtDir:
    let value = element.attr(name)
    if value in ["ltr", "rtl", "auto"]:
      return ctx.toJS(value)
    return ctx.toJS("")
  of rtForm: return ctx.toJS(element.getElementForm())
  of rtBool: return ctx.toJS(element.attrb(name))
  of rtLong:
    let i = cast[int32](entry.u)
    return ctx.toJS(element.attrl(name).get(i))
  of rtUlong: return ctx.toJS(element.attrul(name).get(entry.u))
  of rtUlongGz: return ctx.toJS(element.attrulgz(name).get(entry.u))
  of rtDoubleGz:
    # we do not have fractional default values, so we actually store them
    # as uint32 and convert here.
    let f = float32(entry.u)
    return ctx.toJS(element.attrdgz(name).get(f))

proc jsReflectSet0(ctx: JSContext; htmlElement: HTMLElement; val: JSValueConst;
    magic: cint): JSValue {.cdecl.} =
  let element = htmlElement.asElement
  let entry = ReflectMap[ReflectedAttr(uint16(magic) and 0x1FF)]
  let name = entry.attrname
  case entry.t
  of rtStr, rtUrl, rtReferrerPolicy, rtMethod, rtDir:
    var x: DOMString
    ?ctx.fromJS(val, x)
    element.setAttr(ctx, name, x)
  of rtStrNull:
    var x: DOMStringNull
    ?ctx.fromJS(val, x)
    element.setAttr(ctx, name, x)
  of rtCrossOrigin:
    if JS_IsNull(val):
      element.delAttr(ctx, name.view())
    else:
      var x: DOMString
      ?ctx.fromJS(val, x)
      element.setAttr(ctx, name, x)
  of rtBool:
    var x: bool
    ?ctx.fromJS(val, x)
    if x:
      element.setAttr(ctx, name, "")
    else:
      element.delAttr(ctx, name.view())
  of rtLong:
    var x: int32
    ?ctx.fromJS(val, x)
    element.setAttr(ctx, name, $x)
  of rtUlong:
    var x: uint32
    ?ctx.fromJS(val, x)
    element.setAttr(ctx, name, $x)
  of rtUlongGz:
    var x: uint32
    ?ctx.fromJS(val, x)
    if x > 0:
      element.setAttr(ctx, name, $x)
  of rtDoubleGz:
    var x: float64
    ?ctx.fromJS(val, x)
    if classify(x) in {fcInf, fcNegInf, fcNan}:
      return JS_ThrowTypeError(ctx, "double expected")
    element.setAttr(ctx, name, dtoa(x))
  of rtForm: discard
  return JS_UNDEFINED

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

proc jsReflectEventGet(ctx: JSContext; this: JSValueConst; magic: cint):
    JSValue {.cdecl.} =
  var element: ptr HTMLElementObj
  ?ctx.fromJS(this, element)
  let name = StaticAtom(magic)
  let this = Element(element).getEventTarget(name)
  if this == nil:
    return JS_UNDEFINED
  return ctx.eventReflectGetImpl(this, name)

proc jsReflectEventSet(ctx: JSContext; this, val: JSValueConst; magic: cint):
    JSValue {.cdecl.} =
  var element: ptr HTMLElementObj
  ?ctx.fromJS(this, element)
  let name = StaticAtom(magic)
  let target = Element(element).getEventTarget(name)
  if target == nil:
    return JS_UNDEFINED
  return ctx.eventReflectSetImpl(target, val, name)

jsClassPublicDef(HTMLElement):
  jsextends ElementDef

  event.htmlElementClassID = classDef.id

  proc dataset(element: HTMLElement): DOMStringMap {.jsnfget.} =
    var dataset = element.asElement.getAccessor(satDataset) as DOMStringMap
    if dataset == nil:
      dataset = jsNew DOMStringMapObj(target: element)
      if dataset != nil:
        element.asElement.addAccessor(dataset.asElementAccessor, satDataset)
    move(dataset)

  proc click(ctx: JSContext; element: HTMLElement) {.jsfunc.} =
    let event = newEvent(satClick, element.asEventTarget, bubbles = true,
      cancelable = true)
    if event != nil:
      let canceled = ctx.dispatch(element.asEventTarget, event)
      if not canceled:
        let window = ctx.getWindow()
        if window != nil:
          window.click(element)

template htmlClassDef(name: untyped) =
  jsClassDef(name):
    jsextends HTMLElementDef

# HTMLHyperlinkElementUtils (for <a> and <area>)
proc reinitURL*(element: Element): Opt[URL] =
  if element.attrb(satHref):
    let url = element.asNode.document.parseURL(element.attr(satHref))
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
      element.setAttr(ctx, satHref, s)
      return JS_DupValue(ctx, val)
    return JS_EXCEPTION
  if url := element.reinitURL():
    let href = ctx.toJS(url)
    let res = JS_SetPropertyStr(ctx, href, cstring($sa), JS_DupValue(ctx, val))
    if res < 0:
      return JS_EXCEPTION
    var ds: DOMString
    if ctx.fromJSFree(href, ds).isOk:
      element.setAttr(ctx, satHref, ds)
  return JS_DupValue(ctx, val)

# <a>
jsClassPublicDef(HTMLAnchorElement):
  jsextends HTMLElementDef

  proc toString(this: HTMLAnchorElement): string {.jsfunc.} =
    if href := this.asElement.reinitURL():
      return $href
    return ""

  proc getRelList(this: HTMLAnchorElement): DOMTokenList {.
      jsnfget: "relList".} =
    this.asElement.getDOMTokenList(this.relList, satRel)

  proc setRelList(ctx: JSContext; this: HTMLAnchorElement; ds: DOMString) {.
      jsfset: "relList".} =
    this.asElement.setAttr(ctx, satRel, ds)

# <audio>
proc newAudio(ctx: JSContext; this_target: JSValueConst; argc: cint;
    argv: JSValueConstArray): JSValue {.cdecl.} =
  let document = ctx.getDocument()
  let this = document.newHTMLElement(ttAudio)
  if argc >= 1 and not JS_IsUndefined(argv[0]):
    var ds: DOMString
    ?ctx.fromJS(argv[0], ds)
    this.asElement.setAttr(ctx, satSrc, ds)
  ctx.toJS(this)

# <base>
jsClassDef(HTMLBaseElement):
  jsextends HTMLElementDef

  proc href(base: HTMLBaseElement): string {.jsfget.} =
    #TODO with fallback base url
    if url := parseURL(base.asElement.attr(satHref)):
      return $url
    return ""

# <canvas>
type ToBlobEnv* {.final.} = ref object of BlobOpaque
  ctx: JSContext
  callback: JSCallback
  isPNG: bool
  this: HTMLCanvasElement
  url: URL

proc mark*(rt: JSRuntime; env: ToBlobEnv; markFunc: JS_MarkFunc) =
  JS_MarkValue(rt, env.callback, markFunc)
  rt.markObj(env.this, markFunc)
  rt.markObj(env.url, markFunc)

proc onFinishToBlob(response: Response; success: bool) =
  let env = ToBlobEnv(response.opaque)
  let ctx = env.ctx
  let callback = move(env.callback)
  let this = env.this
  let blob = response.onFinishBlob(success)
  if blob == nil:
    JS_FreeContext(ctx)
    return
  let jsBlob = ctx.toJS(blob)
  if JS_IsException(jsBlob):
    JS_FreeContext(ctx)
    return
  let window = this.asNode.document.window
  let res = ctx.callSink(callback.value, JS_UNDEFINED, jsBlob)
  if JS_IsException(res):
    window.console.error("Exception in canvas toBlob:",
      ctx.getExceptionMsg())
  else:
    JS_FreeValue(ctx, res)
  JS_FreeContext(ctx)

proc toBlob1(opaque: RootRef; response: Response) =
  let env = ToBlobEnv(opaque)
  let ctx = env.ctx
  let this = env.this
  if response == nil:
    let callback = move(env.callback)
    if not env.isPNG:
      # Redo as PNG.  (Yes, this is spec-mandated.)
      ctx.toBlob(this, callback, "image/png")
    else: # the png encoder doesn't work...
      let window = this.asNode.document.window
      window.console.error("missing/broken PNG encoder")
    JS_FreeContext(ctx)
  else:
    response.onFinish = onFinishToBlob
    let window = env.ctx.getGlobal()
    window.loader.blob(response, env)

proc toBlob0(opaque: RootRef; response: Response) =
  let env = ToBlobEnv(opaque)
  let ctx = env.ctx
  if response == nil:
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
  let window = this.asNode.document.window
  window.corsFetch(request, toBlob1, env)
  window.loader.close(response)

jsClassDef(HTMLCanvasElement):
  jsextends HTMLElementDef

  proc getContext*(jctx: JSContext; this: HTMLCanvasElement;
      contextId: DOMString; options: JSValueConst = JS_UNDEFINED):
      CanvasRenderingContext2D {.jsfunc.} =
    if contextId.toOpenArray() == "2d":
      if this.ctx2d == nil:
        let window = jctx.getWindow()
        let loader = window.loader
        let ctx2d = create2DContext(loader, this.asEventTarget, this.bitmap,
          options)
        if ctx2d != nil:
          this.ctx2d = ctx2d
          window.pendingCanvasCtls.add(ctx2d)
      return this.ctx2d
    return CanvasRenderingContext2D(nil)

  proc toBlob(ctx: JSContext; this: HTMLCanvasElement;
      callback: JSCallback; contentType = "image/png";
      qualityVal: JSValueConst = JS_UNDEFINED) {.jsfunc.} =
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
      if ctx.fromJS(qualityVal, quality).isOk and
          0 <= quality and quality <= 1:
        quality *= 99
        quality += 1
        headers.add("Cha-Image-Quality", dtoa(quality))
    let request = newRequest(
      "img-codec+x-cha-canvas:decode",
      httpMethod = hmPost,
      body = RequestBody(t: rbtCache, cacheId: this.bitmap.cacheId),
      internal = true
    )
    let env = ToBlobEnv(
      ctx: JS_DupContext(ctx),
      callback: callback,
      isPNG: contentType == "image/png",
      this: this,
      url: url
    )
    let window = this.asNode.document.window
    window.corsFetch(request, toBlob0, env)

# <img>
proc newImage(ctx: JSContext; _: JSValueConst; argc: cint;
    argv: JSValueConstArray): JSValue {.cdecl.} =
  let document = ctx.getDocument()
  let this = document.newHTMLElement(ttImg)
  if argc >= 1 and not JS_IsUndefined(argv[0]):
    var x: uint32
    ?ctx.fromJS(argv[0], x)
    this.asElement.setAttr(ctx, satWidth, $x)
  if argc >= 2 and not JS_IsUndefined(argv[1]):
    var x: uint32
    ?ctx.fromJS(argv[1], x)
    this.asElement.setAttr(ctx, satHeight, $x)
  ctx.toJS(this)

proc getImageRect(this: HTMLImageElement): tuple[w, h: float64] =
  let window = this.asNode.document.window
  if window != nil and window.settings.scripting == smApp:
    window.ensureLayout(this.asElement)
    let objs = getClientRects(this.asElement, firstOnly = true,
      blockOnly = false)
    if objs.len > 0:
      return (objs[0].width, objs[0].height)
  let bitmap = this.bitmap
  if bitmap == nil:
    return (0'f64, 0'f64)
  let this = this.asElement
  let width = float64(this.attrul(satWidth).get(uint32(bitmap.width)))
  let height = float64(this.attrul(satHeight).get(uint32(bitmap.height)))
  return (width, height)

jsClassPublicDef(HTMLImageElement):
  jsextends HTMLElementDef

  proc width(this: HTMLImageElement): uint32 {.jsfget.} =
    return uint32(this.getImageRect().w)

  proc setWidth(ctx: JSContext; this: HTMLImageElement; u: uint32) {.
      jsfset: "width".} =
    this.asElement.setAttr(ctx, satWidth, $u)

  proc height(this: HTMLImageElement): uint32 {.jsfget.} =
    return uint32(this.getImageRect().h)

  proc setHeight(ctx: JSContext; this: HTMLImageElement; u: uint32) {.
      jsfset: "height".} =
    this.asElement.setAttr(ctx, satHeight, $u)

# SheetElement
proc findPrevSheet(this: SheetElement): CSSStylesheet =
  var node = this.asNode.previousDescendant()
  while node != nil:
    if node of SheetElement:
      let element = SheetElement(node)
      if element.sheetTail != nil:
        return element.sheetTail
    node = node.previousDescendant()
  nil

proc findNextSheet(this: SheetElement): CSSStylesheet =
  var node = this.asNode.nextDescendant(Node(nil))
  while node != nil:
    let element = node as SheetElement
    if element != nil and element.sheetHead != nil:
      return element.sheetHead
    node = node.nextDescendant(Node(nil))
  nil

proc isDisabled(this: SheetElement): bool =
  let link = this as HTMLLinkElement
  link != nil and link.isDisabled()

proc insertSheet(this: SheetElement) =
  if this.sheetHead != nil:
    assert this.sheetHead.prev == nil and this.sheetTail.next == nil
    let document = this.asNode.document
    let prev = this.findPrevSheet()
    let next = this.findNextSheet()
    if prev != nil:
      prev.next = this.sheetHead
      this.sheetHead.prev = prev
    else:
      document.authorSheetsHead = this.sheetHead
    this.sheetTail.next = next
    if next != nil:
      next.prev = this.sheetTail
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
    let document = this.asNode.document
    let prev = this.sheetHead.prev
    let next = this.sheetTail.next
    if prev == nil:
      document.authorSheetsHead = next
    else:
      prev.next = next
    if next != nil:
      next.prev = prev
    if not this.isDisabled():
      document.ruleMap = nil
    this.sheetHead.prev = nil
    this.sheetTail.next = nil
    let html = document.documentElement
    if html != nil:
      html.invalidate()

proc updateSheet(this: SheetElement; head, tail: CSSStylesheet) =
  this.removeSheet()
  this.sheetHead = head
  this.sheetTail = tail
  if this.asNode.isConnected():
    this.insertSheet()

jsClassDef(SheetElement): # fake class
  jsextends HTMLElementDef

# <link>
proc isDisabled(link: HTMLLinkElement): bool =
  let title = link.asElement.attr(satTitle)
  if title == "":
    return link.relList.containsIgnoreCase(satAlternate) or
      not link.enabled.get(true)
  if link.enabled.isSome:
    return not link.enabled.get
  return link.asNode.document.sheetTitle != title

jsClassDef(HTMLLinkElement):
  jsextends SheetElementDef

  proc getRelList(this: HTMLLinkElement): DOMTokenList {.jsfget: "relList".} =
    this.asElement.getDOMTokenList(this.relList, satRel)

  proc setRelList(ctx: JSContext; this: HTMLLinkElement; s: DOMString) {.
      jsfset: "relList".} =
    this.asElement.setAttr(ctx, satRel, s)

# <progress>
jsClassRaw(HTMLProgressElementDef, "HTMLProgressElement"):
  jsextends HTMLElementDef

  proc position(this: Element): float64 {.jsfget.} =
    return this.getProgressPosition()

# <style>
proc updateSheetFinish(window: Window; this: SheetElement; res: LoadSheetResult;
    env: ParseSheetEnv; i: int) =
  this.updateSheet(res.head, res.tail)
  if this.asNode.isConnected():
    let title = this.asElement.attr(satTitle)
    let document = this.asNode.document
    for sheet in this.sheets:
      sheet.disabled = title != "" and title != document.sheetTitle

proc updateSheet*(this: HTMLStyleElement) =
  let document = this.asNode.document
  let window = document.window
  if window != nil:
    window.parseStylesheet(this.asSheetElement, this.asNode.textContent,
      document.baseURL, DefaultCharset, CAtomNull, updateSheetFinish,
      nil, 0)

jsClassPublicDef(HTMLStyleElement):
  jsextends SheetElementDef

# <script>
proc markAsReady(element: HTMLScriptElement; res: ScriptResult) =
  element.scriptResult = res
  if element.onReady != nil:
    element[].onReady(element)
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
        prepdoc.scriptsToExecInOrderTail = HTMLScriptElement(nil)

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
  if not element.asElement.scriptingEnabled:
    element.markAsReady(ScriptResult(t: srtNull))
    return Response(nil)
  let window = element.asNode.document.window
  let request = createPotentialCORSRequest(url, rdScript, cors)
  request.client = window.settings
  return window.loader.doRequest(request)

#TODO settings object
proc fetchExternalModuleGraph(element: HTMLScriptElement; url: URL;
    options: ScriptOptions; onComplete: OnCompleteProc) =
  let window = element.asNode.document.window
  if not element.asElement.scriptingEnabled:
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
  let window = element.asNode.document.window
  let ctx = window.jsctx
  let res = ctx.newJSModuleScript(sourceText, url, options, window.settings)
  if JS_IsException(res.script.record):
    window.logException(res.script.baseURL)
    element.onComplete(ScriptResult(t: srtNull))
  else:
    element.fetchDescendantsAndLink(res.script, rdScript, onComplete)

proc fetchDescendantsAndLink(element: HTMLScriptElement; script: Script;
    destination: RequestDestination; onComplete: OnCompleteProc) =
  let window = element.asNode.document.window
  let ctx = window.jsctx
  let record = script.record
  if JS_ResolveModule(ctx, record) < 0:
    window.logException(script.baseURL)
    script.free()
    return
  ctx.setImportMeta(record, true)
  script.record = JS_UNINITIALIZED
  let res = JS_EvalFunction(ctx, record) # consumes record
  if JS_IsException(res):
    window.logException(script.baseURL)
  JS_FreeValue(ctx, res)

type
  FetchModuleEnv* {.final.} = ref object of BlobOpaque
    window: Window
    element: HTMLScriptElement
    settings: EnvironmentSettings
    url: URL
    moduleType: ModuleType
    referrerPolicy: Opt[ReferrerPolicy]
    onComplete: OnCompleteProc
    options: ScriptOptions

proc mark*(rt: JSRuntime; env: FetchModuleEnv; markFunc: JS_MarkFunc) =
  rt.markObj(env.url, markFunc)
  rt.markObj(env.window, markFunc)
  rt.markObj(env.element, markFunc)

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
  elif contentType.isJavaScriptType():
    let source = blob.toOpenArray().toValidUTF8()
    let res = ctx.newJSModuleScript(source, url, env.options, settings)
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
  if response == nil:
    let res = ScriptResult(t: srtNull)
    env.settings.moduleMap.put(env.url, env.moduleType, res)
    env.onComplete(env.element, res)
  else:
    env.referrerPolicy = response.getReferrerPolicy()
    response.onFinish = onFinishFetchModule
    env.window.loader.blob(response, env)

#TODO settings object
proc fetchSingleModule(element: HTMLScriptElement; url: URL;
    destination: RequestDestination; options: ScriptOptions;
    referrer: URL; isTopLevel: bool; onComplete: OnCompleteProc) =
  let moduleType = mtJavascript
  #TODO moduleRequest
  let window = element.asNode.document.window
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
  let document = element.asNode.document
  let window = document.window #TODO this is wrong
  if document != element.preparationTimeDocument or window == nil:
    return
  let i = document.renderBlockingElements.find(element)
  if i >= 0:
    document.renderBlockingElements.delete(i)
  #TODO this should work eventually (when module & importmap are implemented)
  #assert element.scriptResult != nil
  if element.scriptResult == nil:
    return
  if element.scriptResult.t == srtNull:
    window.fireEvent(satError, element.asEventTarget, bubbles = false,
      cancelable = false, trusted = true)
    return
  let needsInc = element.external or element.scriptType == stModule
  if needsInc:
    inc document.ignoreDestructiveWrites
  case element.scriptType
  of stClassic:
    let oldCurrentScript = document.currentScript
    document.currentScript = if not (element.asNode.rootNode of ShadowRoot):
      element
    else:
      HTMLScriptElement(nil)
    let script = element.scriptResult.script
    if JS_IsException(script.record):
      window.logException(script.baseURL)
    else:
      let ctx = window.jsctx
      if window.settings.scripting != smFalse:
        element.prepare(ctx)
        let record = script.record
        script.record = JS_UNINITIALIZED
        let ret = JS_EvalFunction(ctx, record) # consumes record
        if JS_IsException(ret):
          window.logException(script.baseURL)
        JS_FreeValue(ctx, ret)
    document.currentScript = oldCurrentScript
  else: discard #TODO
  if needsInc:
    dec document.ignoreDestructiveWrites
  if element.external:
    window.fireEvent(satLoad, element.asEventTarget, bubbles = false,
      cancelable = false, trusted = true)

# https://html.spec.whatwg.org/multipage/scripting.html#prepare-the-script-element
proc prepare*(element: HTMLScriptElement; ctx: JSContext) =
  if element.alreadyStarted:
    return
  let parserDocument = element.parserDocument
  element.parserDocument = Document(nil)
  if parserDocument != nil and not element.asElement.attrb(satAsync):
    element.forceAsync = true
  let window = element.asNode.document.window
  let sourceText = element.asParentNode.childTextContent
  if not element.asElement.attrb(satSrc) and sourceText == "" or
      not element.asNode.isConnected or window == nil:
    return
  let t = element.asElement.attr(satType)
  let typeString = if t != "":
    t.strip(chars = AsciiWhitespace)
  elif (let l = element.asElement.attr(satLanguage); l != ""):
    "text/" & l
  else:
    "text/javascript"
  if typeString.isJavaScriptType():
    element.scriptType = stClassic
  elif typeString.equalsIgnoreCase("module"):
    element.scriptType = stModule
  elif typeString.equalsIgnoreCase("importmap"):
    element.scriptType = stImportMap
  else:
    return
  if parserDocument != nil:
    element.parserDocument = parserDocument
    element.forceAsync = false
  element.alreadyStarted = true
  let document = element.asNode.document
  element.preparationTimeDocument = document
  if parserDocument != nil and parserDocument != document or
      not element.asElement.scriptingEnabled or
      element.asElement.attrb(satNomodule) and element.scriptType == stClassic:
    return
  #TODO content security policy
  if element.scriptType == stClassic and element.asElement.attrb(satEvent) and
      element.asElement.attrb(satFor):
    let f = element.asElement.attr(satFor).strip(chars = AsciiWhitespace)
    let event = element.asElement.attr(satEvent).strip(chars = AsciiWhitespace)
    if not f.equalsIgnoreCase("window") or
        not event.equalsIgnoreCase("onload") and
        not event.equalsIgnoreCase("onload()"):
      return
  let encoding = element.asElement.getCharset()
  let classicCORS = element.asHTMLElement.crossOrigin
  let parserMetadata = if element.parserDocument != nil:
    pmParserInserted
  else:
    pmNotParserInserted
  var options = ScriptOptions(
    nonce: element.internalNonce,
    integrity: element.asElement.attr(satIntegrity),
    parserMetadata: parserMetadata,
    referrerPolicy: element.asHTMLElement.referrerPolicy
  )
  let settings = window.settings #TODO pass it as param instead
  var response: Response
  if element.asElement.attrb(satSrc):
    let src = element.asElement.attr(satSrc)
    let url = document.parseURL0(src)
    element.external = src != "" and element.scriptType != stImportMap
    if element.scriptType == stImportMap or url == nil:
      window.fireEvent(satError, element.asEventTarget, bubbles = false,
        cancelable = false, trusted = true)
      return
    if element.asElement.isRenderBlocking():
      element.asElement.blockRendering()
    element.delayingTheLoadEvent = true
    if element.asElement in document.renderBlockingElements:
      options.renderBlocking = true
    if element.scriptType == stClassic:
      response = element.fetchClassicScript(url, classicCORS, markAsReady)
    else: # stModule
      element.fetchExternalModuleGraph(url, options, markAsReady)
  else:
    let baseURL = document.baseURL
    case element.scriptType
    of stClassic:
      let script = ctx.newClassicScript(sourceText, baseURL, options, settings)
      element.markAsReady(script)
    of stModule:
      element.delayingTheLoadEvent = true
      if element.asElement.isRenderBlocking():
        element.asElement.blockRendering()
        options.renderBlocking = true
      element.fetchInlineModuleGraph(sourceText, baseURL, options, markAsReady)
    of stImportMap:
      #TODO
      element.markAsReady(ScriptResult(t: srtNull))
  if element.scriptType == stClassic and element.asElement.attrb(satSrc) or
      element.scriptType == stModule:
    let prepdoc = element.preparationTimeDocument
    if element.asElement.attrb(satAsync) or element.forceAsync:
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
    elif element.scriptType == stModule or element.asElement.attrb(satDefer):
      let tail = element.parserDocument.scriptsToExecOnLoadTail
      if tail != nil:
        tail.next = element
      else:
        element.parserDocument.scriptsToExecOnLoad = element
      element.parserDocument.scriptsToExecOnLoadTail = element
      element.onReady = scriptOnReadyRunInParser
    else:
      element.parserDocument.parserBlockingScript = element
      element.asElement.blockRendering()
      element.onReady = scriptOnReadyRunInParser
    if response != nil:
      if response.stream == nil:
        element.markAsReady(ScriptResult(t: srtNull))
      else:
        window.loader.resume(response)
        let source = response.stream.readAll().decodeAll(encoding)
        response.stream.sclose()
        let script = ctx.newClassicScript(source, response.url, options,
          settings, mutedErrors = false)
        element.markAsReady(script)
  else:
    #TODO if stClassic, parserDocument != nil, parserDocument has a style sheet
    # that is blocking scripts, either the parser is an XML parser or a HTML
    # parser with a script level <= 1
    element.execute()

jsClassPublicDef(HTMLScriptElement):
  jsextends HTMLElementDef

  proc finalize(rt: JSRuntime; element: HTMLScriptElement) {.jsfin.} =
    if element.scriptResult != nil and element.scriptResult.t == srtScript:
      let script = element.scriptResult.script
      if not JS_IsUninitialized(script.record):
        script.free()

  proc mark(rt: JSRuntime; element: HTMLScriptElement; markFunc: JS_MarkFunc)
      {.jsmark.} =
    if element.scriptResult != nil:
      rt.mark(element.scriptResult, markFunc)

  proc text(this: HTMLScriptElement): string {.jsfget.} =
    this.asParentNode.childTextContent

  proc setText(ctx: JSContext; this: HTMLScriptElement; ds: DOMString)
      {.jsfset.} =
    this.asParentNode.replaceAll(ctx, ds)

# <table>
proc deleteRow(ctx: JSContext; rows: HTMLCollection; index: int32): Opt[void] =
  let nrows = rows.length
  if index < -1 or index >= int64(nrows):
    JS_ThrowDOMException(ctx, "IndexSizeError", "index out of bounds")
    return err()
  if index == -1:
    let it = rows.item(uint32(nrows - 1))
    it.asNode.removeImpl(ctx)
  elif nrows > 0:
    let it = rows.item(uint32(index))
    it.asNode.removeImpl(ctx)
  ok()

jsClassDef(HTMLTableElement):
  jsextends HTMLElementDef

  proc getTableChild(this: HTMLTableElement; tagType: TagType): Element {.
      jsmfget("caption", ttCaption), jsmfget("tHead", ttThead),
      jsmfget("tFoot", ttTfoot).} =
    this.asParentNode.findFirstChildOf(tagType)

  proc setTableChild(ctx: JSContext; this: HTMLTableElement; tagType: TagType;
      sectVal: JSValueConst): JSValue {.jsmfset("caption", ttCaption),
      jsmfset("tHead", ttThead), jsmfset("tFoot", ttTfoot).} =
    var sect: HTMLElement
    if not JS_IsNull(sectVal):
      ?ctx.fromJS(sectVal, sect)
    if sect != nil and sect.tagType != tagType:
      if tagType != ttCaption and sect of HTMLTableSectionElement:
        return ctx.insertThrow("wrong element type")
      return JS_ThrowTypeError(ctx, "%s tag expected", cstring($tagType))
    let old = this.asParentNode.findFirstChildOf(tagType)
    if old != nil:
      ctx.remove(old)
    if sect == nil:
      return JS_UNDEFINED
    return ctx.insertBeforeUndefined(this.asNode, sect.asNode,
      jsNull(this.asParentNode.firstChild))

  proc tBodies(this: HTMLTableElement): HTMLCollection {.jsnfget.} =
    this.asParentNode.getChildrenOf(cnTBodies, cmChildren, ttTbody)

  proc rows(this: HTMLTableElement): HTMLCollection {.jsnfget.} =
    this.asParentNode.getHTMLCollection(isRowOf, cmSubtree, cnRows)

  proc createTableChild(ctx: JSContext; this: HTMLTableElement;
      tagType: TagType): Element {.jsmfunc("createCaption", ttCaption),
      jsmfunc("createTHead", ttThead), jsmfunc("createTBody", ttTbody),
      jsmfunc("createTFoot", ttTfoot).} =
    let before = case tagType
    of ttCaption: this.asParentNode.firstChild
    of ttThead:
      this.asParentNode.findFirstChildNotOf({ttCaption, ttColgroup}).asNode
    of ttTbody: this.asParentNode.findLastChildOf(ttTbody).asNode
    else: Node(nil) # tfoot
    var element = this.asParentNode.findFirstChildOf(tagType)
    if element == nil:
      element = this.asNode.document.newHTMLElement(tagType).asElement
      if element != nil:
        this.asParentNode.insert(ctx, element.asNode, before)
    return element

  proc deleteTableChild(ctx: JSContext; this: HTMLTableElement; tag: TagType)
      {.jsmfunc("deleteCaption", ttCaption), jsmfunc("deleteTHead", ttThead),
        jsmfunc("deleteTFoot", ttTfoot).} =
    let element = this.asParentNode.findFirstChildOf(tag)
    if element != nil:
      ctx.remove(element)

  proc insertRow(ctx: JSContext; this: HTMLTableElement; index: int32 = -1):
      Opt[HTMLElement] {.jsfunc.} =
    let rows = this.rows()
    if rows == nil:
      JS_ThrowOutOfMemory(ctx)
      return err()
    let nrows = rows.asCollection.getLength()
    if index < -1 or index > int64(nrows):
      JS_ThrowDOMException(ctx, "IndexSizeError", "index out of bounds")
      return err()
    let tr = this.asNode.document.newHTMLElement(ttTr)
    if nrows == 0:
      let tbody = ctx.createTableChild(this, ttTbody)
      if tbody != nil:
        tbody.asParentNode.append(ctx, tr.asNode)
    elif index == -1 or uint32(index) == nrows:
      let it = rows.item(nrows - 1)
      it.parentNode.append(ctx, tr.asNode)
    else:
      let it = rows.item(uint32(index))
      it.parentNode.insert(ctx, tr.asNode, it.asNode)
    ok(tr)

  proc deleteRow(ctx: JSContext; this: HTMLTableElement; index: int32 = -1):
      Opt[void] {.jsfunc.} =
    let rows = this.rows()
    if rows == nil:
      JS_ThrowOutOfMemory(ctx)
      return err()
    return ctx.deleteRow(rows, index)

# <tbody>
jsClassDef(HTMLTableSectionElement):
  jsextends HTMLElementDef

  proc rows(this: HTMLTableSectionElement): HTMLCollection {.jsnfget.} =
    this.asParentNode.getChildrenOf(cnRows, cmChildren, ttTr)

  proc insertRow(ctx: JSContext; this: HTMLTableSectionElement;
      index: int32 = -1): Opt[HTMLElement] {.jsfunc.} =
    let rows = this.rows()
    let nrows = rows.asCollection.getLength()
    if index < -1 or index > int64(nrows):
      JS_ThrowDOMException(ctx, "index out of bounds", "IndexSizeError")
      return err()
    let tr = this.asNode.document.newHTMLElement(ttTr)
    let before = if index == -1 or index == int64(nrows):
      Node(nil)
    else:
      rows.item(uint32(index)).asNode
    this.asParentNode.insert(ctx, tr.asNode, before)
    ok(tr)

  proc deleteRow(ctx: JSContext; this: HTMLTableSectionElement;
      index: int32 = -1): Opt[void] {.jsfunc.} =
    let rows = this.rows()
    if rows == nil:
      JS_ThrowOutOfMemory(ctx)
      return err()
    return ctx.deleteRow(rows, index)

# <tr>
jsClassDef(HTMLTableRowElement):
  jsextends HTMLElementDef

  proc cells(this: HTMLTableRowElement): HTMLCollection {.jsnfget.} =
    this.asParentNode.getChildrenOf(cnCells, cmChildren, ttTd, ttTh)

  proc rowIndex(this: HTMLTableRowElement): int {.jsfget.} =
    let table = this.asNode.findAncestor(ttTable) as HTMLTableElement
    if table == nil:
      return -1
    let rows = table.rows()
    rows.asCollection.findNode(this.asNode)

  proc sectionRowIndex(this: HTMLTableRowElement): int {.jsfget.} =
    let parent = this.asNode.parentElement
    if parent.tagType == ttTable:
      return this.rowIndex()
    if (let parent = parent as HTMLTableSectionElement; parent != nil):
      let rows = parent.rows()
      return rows.asCollection.findNode(this.asNode)
    return -1

# <template>
jsClassPublicDef(HTMLTemplateElement):
  jsextends HTMLElementDef

  jsget HTMLTemplateElement, content

# <title>
jsClassRaw(HTMLTitleElementDef, "HTMLTitleElement"):
  jsextends HTMLElementDef

  proc titleText(this: HTMLElement): string {.jsfget: "text".} =
    this.asParentNode.childTextContent

  proc setTitleText(ctx: JSContext; this: HTMLElement; ds: DOMString) {.
      jsfset: "text".} =
    this.asParentNode.replaceAll(ctx, ds)

# misc
htmlClassDef(HTMLVideoElement)
htmlClassDef(HTMLAudioElement)
htmlClassDef(HTMLIFrameElement)
htmlClassDef(HTMLFrameElement)
htmlClassDef(HTMLHeadElement)
htmlClassDef(HTMLObjectElement)
htmlClassDef(HTMLSlotElement)

template htmlClassRaw(name: untyped) =
  jsClassRaw(`name Def`, astToStr(name)):
    jsextends HTMLElementDef

htmlClassRaw(HTMLSpanElement)
htmlClassRaw(HTMLHeadingElement)
htmlClassRaw(HTMLBRElement)
htmlClassRaw(HTMLHtmlElement)
htmlClassRaw(HTMLModElement)
htmlClassRaw(HTMLParagraphElement)
htmlClassRaw(HTMLParamElement)
htmlClassRaw(HTMLDivElement)
htmlClassRaw(HTMLDListElement)
htmlClassRaw(HTMLFontElement)
htmlClassRaw(HTMLBodyElement)
htmlClassRaw(HTMLHRElement)
htmlClassRaw(HTMLUnknownElement)
htmlClassRaw(HTMLPreElement)
htmlClassRaw(HTMLTableColElement)
htmlClassRaw(HTMLTableCellElement)
htmlClassRaw(HTMLDataListElement)
htmlClassRaw(HTMLMeterElement)
htmlClassRaw(HTMLFieldSetElement)
htmlClassRaw(HTMLLegendElement)
htmlClassRaw(HTMLSelectedContentElement)
htmlClassRaw(HTMLOptGroupElement)
htmlClassRaw(HTMLMenuElement)
htmlClassRaw(HTMLUListElement)
htmlClassRaw(HTMLOListElement)
htmlClassRaw(HTMLLIElement)
htmlClassRaw(HTMLTableCaptionElement)
htmlClassRaw(HTMLMetaElement)
htmlClassRaw(HTMLTimeElement)
htmlClassRaw(HTMLQuoteElement)
htmlClassRaw(HTMLDialogElement)
htmlClassRaw(HTMLDataElement)
htmlClassRaw(HTMLTrackElement)
htmlClassRaw(HTMLPictureElement)
htmlClassRaw(HTMLSourceElement)
htmlClassRaw(HTMLMapElement)
htmlClassRaw(HTMLDetailsElement)
htmlClassRaw(HTMLEmbedElement)

jsClassDef(SVGElement):
  jsextends ElementDef

jsClassPublicDef(SVGSVGElement):
  jsextends SVGElementDef

# this is here so that we have access to all class ids
proc newHTMLElementInternal(tagType: TagType; document: Document):
    HTMLElement =
  case tagType
  of ttTemplate:
    let content = newDocumentFragment(document)
    if content == nil:
      return HTMLElement(nil)
    let templ = jsNew HTMLTemplateElementObj(content: content)
    if templ != nil:
      templ.content.host = templ.asElement
    return templ.asHTMLElement
  of ttCanvas:
    let imageId = if document.window != nil:
      document.window.getImageId()
    else:
      -1
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
    return (jsNew HTMLCanvasElementObj(bitmap: bitmap)).asHTMLElement
  of ttA: return (jsNew HTMLAnchorElementObj()).asHTMLElement
  of ttLink: return (jsNew HTMLLinkElementObj()).asHTMLElement
  of ttStyle: return (jsNew HTMLStyleElementObj()).asHTMLElement
  of ttScript:
    return (jsNew HTMLScriptElementObj(forceAsync: true)).asHTMLElement
  of ttBase: return (jsNew HTMLBaseElementObj()).asHTMLElement
  of ttImg: return (jsNew HTMLImageElementObj()).asHTMLElement
  of ttVideo: return (jsNew HTMLVideoElementObj()).asHTMLElement
  of ttAudio: return (jsNew HTMLAudioElementObj()).asHTMLElement
  of ttTable: return (jsNew HTMLTableElementObj()).asHTMLElement
  of ttTr: return (jsNew HTMLTableRowElementObj()).asHTMLElement
  of ttTbody, ttThead, ttTfoot:
    return (jsNew HTMLTableSectionElementObj()).asHTMLElement
  of ttIframe: return (jsNew HTMLIFrameElementObj()).asHTMLElement
  of ttFrame: return (jsNew HTMLFrameElementObj()).asHTMLElement
  of ttObject: return (jsNew HTMLObjectElementObj()).asHTMLElement
  of ttSlot: return (jsNew HTMLSlotElementObj()).asHTMLElement
  of ttHead: return (jsNew HTMLHeadElementObj()).asHTMLElement
  of ttForm, ttInput, ttSelect, ttOption, ttButton, ttTextarea, ttOutput,
      ttLabel, ttArea:
    return newHTMLElementForm(tagType)
  else: discard
  # These interfaces only have reflectors, which we can implement without a
  # Nim type.
  #TODO probably we could do this for a lot more by taking HTMLElement as
  # `this'; then, fromJSThis will still work as expected as we are passing
  # the class id there.
  let classid = case tagType
  of ttOptgroup: HTMLOptGroupElementDef.id
  of ttH1, ttH2, ttH3, ttH4, ttH5, ttH6: HTMLHeadingElementDef.id
  of ttBr: HTMLBRElementDef.id
  of ttSpan: HTMLSpanElementDef.id
  of ttOl: HTMLOListElementDef.id
  of ttUl: HTMLUListElementDef.id
  of ttMenu: HTMLMenuElementDef.id
  of ttLi: HTMLLIElementDef.id
  of ttCaption: HTMLTableCaptionElementDef.id
  of ttMeta: HTMLMetaElementDef.id
  of ttQ, ttBlockquote: HTMLQuoteElementDef.id
  of ttTime: HTMLTimeElementDef.id
  of ttData: HTMLDataElementDef.id
  of ttIns, ttDel: HTMLModElementDef.id
  of ttHtml: HTMLHtmlElementDef.id
  of ttP: HTMLParagraphElementDef.id
  of ttParam: HTMLParamElementDef.id
  of ttProgress: HTMLProgressElementDef.id
  of ttDiv: HTMLDivElementDef.id
  of ttDl: HTMLDListElementDef.id
  of ttFont: HTMLFontElementDef.id
  of ttBody: HTMLBodyElementDef.id
  of ttHr: HTMLHRElementDef.id
  of ttTrack: HTMLTrackElementDef.id
  of ttPre: HTMLPreElementDef.id
  of ttCol, ttColgroup: HTMLTableColElementDef.id
  of ttTd, ttTh: HTMLTableCellElementDef.id
  of ttDatalist: HTMLDataListElementDef.id
  of ttMeter: HTMLMeterElementDef.id
  of ttFieldset: HTMLFieldSetElementDef.id
  of ttLegend: HTMLLegendElementDef.id
  of ttSelectedcontent: HTMLSelectedContentElementDef.id
  of ttDialog: HTMLDialogElementDef.id
  of ttPicture: HTMLPictureElementDef.id
  of ttSource: HTMLSourceElementDef.id
  of ttTitle: HTMLTitleElementDef.id
  of ttMap: HTMLMapElementDef.id
  of ttDetails: HTMLDetailsElementDef.id
  of ttEmbed: HTMLEmbedElementDef.id
  of ttArticle, ttSection, ttNav, ttAside, ttHgroup, ttHeader, ttFooter,
      ttAddress, ttDt, ttDd, ttFigure, ttFigcaption, ttMain, ttSearch, ttEm,
      ttStrong, ttSmall, ttS, ttCite, ttDfn, ttAbbr, ttRuby, ttRt, ttRp,
      ttCode, ttVar, ttSamp, ttKbd, ttSub, ttSup, ttI, ttB, ttU, ttMark,
      ttBdi, ttBdo, ttWbr, ttSummary, ttNoscript:
    HTMLElementDef.id
  else:
    HTMLUnknownElementDef.id
  var p: HTMLElement
  jsNew0(cast[ptr pointer](addr p), classid, csize_t(sizeof(HTMLElementObj)))
  move(p)

#TODO custom elements
proc newElement(document: Document;
    localName, namespaceURI, tagName: sink CAtom): Element =
  let tagType = localName.toTagType()
  let element = if namespaceURI == satNamespaceHTML:
    newHTMLElementInternal(tagType, document).asElement
  elif namespaceURI == satNamespaceSVG:
    if tagType == ttSvg:
      (jsNew SVGSVGElementObj()).asElement
    else:
      (jsNew SVGElementObj()).asElement
  else:
    jsNew ElementObj()
  element.id = satUempty.view()
  element.localName = localName
  element.namespaceURI = namespaceURI
  element.tagName = tagName
  element.internalNext = document.asNode
  if document.quirksMode == qmQuirks:
    element.flags.incl(efQuirks)
  element.custom = if localName.isValidCustomElementName():
    cesUndefined
  else:
    cesUncustomized
  element

proc addHTMLElementReflection(ctx: JSContext): Opt[void] =
  if ctx.getOpaque() == nil:
    return ok()
  let proto = JS_GetClassProto(ctx, HTMLElementDef.id)
  for i in SuperGlobalAttrs:
    if ctx.addReflectFunction(proto, cstring($ReflectMap[i].attrname),
        jsReflectGet, jsReflectSet, cint(i)).isErr:
      JS_FreeValue(ctx, proto)
      return err()
  for (name, eventType) in ScriptEventMap:
    if ctx.definePropertyGetSetCE(proto, cstring($name), jsReflectEventGet,
        jsReflectEventSet, cint(eventType)).isErr:
      JS_FreeValue(ctx, proto)
      return err()
  JS_FreeValue(ctx, proto)
  ok()

proc reflectAttributes*(ctx: JSContext; class: JSClassID;
    attrs: varargs[ReflectedAttr]): Opt[void] =
  let proto = JS_GetClassProto(ctx, class)
  let diff = (uint16(class) - uint16(HTMLElementDef.id)) shl 9
  for i in attrs:
    let name = ReflectMap[i].attrname
    let nameStr = $name
    let nameCStr = case name
    of satFor: cstring"htmlFor"
    of satValuetype: cstring"valueType"
    of satNovalidate: cstring"noValidate"
    of satSelected: cstring"defaultSelected"
    of satHttpEquiv: cstring"httpEquiv"
    of satDatetime: cstring"dateTime"
    of satCrossorigin: cstring"crossOrigin"
    of satReferrerpolicy: cstring"referrerPolicy"
    of satFormmethod: cstring"formMethod"
    of satIsmap: cstring"isMap"
    of satUsemap: cstring"useMap"
    else: cstring(nameStr)
    if ctx.addReflectFunction(proto, nameCStr, jsReflectGet, jsReflectSet,
        cint(diff or uint16(i))).isErr:
      JS_FreeValue(ctx, proto)
      return err()
  JS_FreeValue(ctx, proto)
  ok()

proc addConstructorAlias*(ctx: JSContext; fun: JSCFunction; class: JSClassID;
    name: cstring): Opt[void] =
  let val = JS_NewCFunction2(ctx, fun, cstringConst(name), 0,
    JS_CFUNC_constructor, 0)
  if JS_IsException(val):
    return err()
  let proto = JS_GetClassProto(ctx, class)
  if ctx.defineProperty(val, "prototype", proto).isErr:
    JS_FreeValue(ctx, val)
    return err()
  ?ctx.definePropertyCW(ctx.getOpaque().global, name, val)
  ok()

proc addHyperlinkUtils*(ctx: JSContext; class: JSClassID): Opt[void] =
  const atoms = [
    satHref, satOrigin, satProtocol, satUsername, satPassword, satHost,
    satHostname, satPort, satPathname, satSearch, satHash
  ]
  let proto = JS_GetClassProto(ctx, class)
  for atom in atoms:
    if ctx.definePropertyGetSetCE(proto, cstring($atom), hyperlinkGet,
        hyperlinkSet, cint(atom)).isErr:
      JS_FreeValue(ctx, proto)
      return err()
  JS_FreeValue(ctx, proto)
  ok()

proc registerElements(ctx: JSContext): Opt[void] =
  ?ctx.registerClass(ElementDef)
  ?ctx.registerFakeClass(AttrDummyElementDef)
  ?ctx.registerClass(HTMLElementDef)
  ?ctx.addHTMLElementReflection()
  ?ctx.registerFakeClass(SheetElementDef)
  ?ctx.registerClass(HTMLAnchorElementDef)
  ?ctx.registerClass(HTMLSpanElementDef)
  ?ctx.registerClass(HTMLOptGroupElementDef)
  ?ctx.registerClass(HTMLHeadingElementDef)
  ?ctx.registerClass(HTMLBRElementDef)
  ?ctx.registerClass(HTMLMenuElementDef)
  ?ctx.registerClass(HTMLUListElementDef)
  ?ctx.registerClass(HTMLOListElementDef)
  ?ctx.registerClass(HTMLLIElementDef)
  ?ctx.registerClass(HTMLStyleElementDef)
  ?ctx.registerClass(HTMLLinkElementDef)
  ?ctx.registerClass(HTMLTemplateElementDef)
  ?ctx.registerClass(HTMLUnknownElementDef)
  ?ctx.registerClass(HTMLScriptElementDef)
  ?ctx.registerClass(HTMLBaseElementDef)
  ?ctx.registerClass(HTMLCanvasElementDef)
  ?ctx.registerClass(HTMLImageElementDef)
  ?ctx.registerClass(HTMLVideoElementDef)
  ?ctx.registerClass(HTMLAudioElementDef)
  ?ctx.registerClass(HTMLIFrameElementDef)
  ?ctx.registerClass(HTMLTableElementDef)
  ?ctx.registerClass(HTMLTableCaptionElementDef)
  ?ctx.registerClass(HTMLTableRowElementDef)
  ?ctx.registerClass(HTMLTableSectionElementDef)
  ?ctx.registerClass(HTMLMetaElementDef)
  ?ctx.registerClass(HTMLDetailsElementDef)
  ?ctx.registerClass(HTMLFrameElementDef)
  ?ctx.registerClass(HTMLTimeElementDef)
  ?ctx.registerClass(HTMLQuoteElementDef)
  ?ctx.registerClass(HTMLDataElementDef)
  ?ctx.registerClass(HTMLHeadElementDef)
  ?ctx.registerClass(HTMLTitleElementDef)
  ?ctx.registerClass(HTMLObjectElementDef)
  ?ctx.registerClass(HTMLSourceElementDef)
  ?ctx.registerClass(HTMLModElementDef)
  ?ctx.registerClass(HTMLProgressElementDef)
  ?ctx.registerClass(HTMLSlotElementDef)
  ?ctx.registerClass(HTMLHtmlElementDef)
  ?ctx.registerClass(HTMLParagraphElementDef)
  ?ctx.registerClass(HTMLParamElementDef)
  ?ctx.registerClass(HTMLDivElementDef)
  ?ctx.registerClass(HTMLDListElementDef)
  ?ctx.registerClass(HTMLFontElementDef)
  ?ctx.registerClass(HTMLBodyElementDef)
  ?ctx.registerClass(HTMLHRElementDef)
  ?ctx.registerClass(HTMLPreElementDef)
  ?ctx.registerClass(HTMLPictureElementDef)
  ?ctx.registerClass(HTMLEmbedElementDef)
  ?ctx.registerClass(HTMLTrackElementDef)
  ?ctx.registerClass(HTMLMapElementDef)
  ?ctx.registerClass(HTMLTableColElementDef)
  ?ctx.registerClass(HTMLTableCellElementDef)
  ?ctx.registerClass(HTMLDataListElementDef)
  ?ctx.registerClass(HTMLMeterElementDef)
  ?ctx.registerClass(HTMLFieldSetElementDef)
  ?ctx.registerClass(HTMLLegendElementDef)
  ?ctx.registerClass(HTMLSelectedContentElementDef)
  ?ctx.registerClass(HTMLDialogElementDef)
  # 69/127 (warning: the 128th interface won't fit in the top 7 bits of
  # the getter/setter magic)
  ?ctx.registerClass(SVGElementDef)
  ?ctx.registerClass(SVGSVGElementDef)
  if ctx.getOpaque() != nil:
    ?ctx.addConstructorAlias(newAudio, HTMLAudioElementDef.id, "Audio")
    ?ctx.addConstructorAlias(newImage, HTMLImageElementDef.id, "Image")
    ?ctx.addHyperlinkUtils(HTMLAnchorElementDef.id)
    ?ctx.reflectAttributes(HTMLAnchorElementDef.id, raTarget, raName, raRel,
      raType)
    ?ctx.reflectAttributes(HTMLOptGroupElementDef.id, raDisabled)
    ?ctx.reflectAttributes(HTMLOListElementDef.id, raReversed, raType)
    ?ctx.reflectAttributes(HTMLLIElementDef.id, raValueLong)
    ?ctx.reflectAttributes(HTMLLinkElementDef.id, raTarget, raRel, raType,
      raDisabled, raHref)
    ?ctx.reflectAttributes(HTMLScriptElementDef.id, raType, raCrossorigin,
      raReferrerpolicy, raSrc)
    ?ctx.reflectAttributes(HTMLBaseElementDef.id, raTarget)
    ?ctx.reflectAttributes(HTMLCanvasElementDef.id, raWidth, raHeight)
    ?ctx.reflectAttributes(HTMLImageElementDef.id, raName, raAlt, raSrcset,
      raSizes, raCrossorigin, raReferrerpolicy, raUsemap, raIsmap, raSrc)
    ?ctx.reflectAttributes(HTMLIFrameElementDef.id, raName, raSrc)
    ?ctx.reflectAttributes(HTMLMetaElementDef.id, raName, raHttpequiv,
      raContent, raMedia)
    ?ctx.reflectAttributes(HTMLDetailsElementDef.id, raName, raOpen)
    ?ctx.reflectAttributes(HTMLFrameElementDef.id, raName, raSrc)
    ?ctx.reflectAttributes(HTMLTimeElementDef.id, raDatetime)
    ?ctx.reflectAttributes(HTMLQuoteElementDef.id, raCite)
    ?ctx.reflectAttributes(HTMLDataElementDef.id, raValueStr)
    ?ctx.reflectAttributes(HTMLObjectElementDef.id, raName, raType, raData)
    ?ctx.reflectAttributes(HTMLSourceElementDef.id, raMedia, raType, raWidth,
      raHeight, raSrc, raSrcset, raSizes)
    ?ctx.reflectAttributes(HTMLModElementDef.id, raDatetime, raCite)
    ?ctx.reflectAttributes(HTMLProgressElementDef.id, raValueDoubleGz, raMax)
    ?ctx.reflectAttributes(HTMLSlotElementDef.id, raName)
    ?ctx.reflectAttributes(HTMLParamElementDef.id, raName, raValueStr, raType,
      raValuetype)
    ?ctx.reflectAttributes(HTMLFontElementDef.id, raColor, raFace, raSizeStr)
    ?ctx.reflectAttributes(HTMLFieldSetElementDef.id, raName, raDisabled)
    ?ctx.reflectAttributes(HTMLDialogElementDef.id, raOpen)
  ok()

proc addDOMModule*(ctx: JSContext): JSCode =
  ?ctx.registerClass(NodeDef)
  ?ctx.defineConsts(NodeDef.id, NodeType)
  ?ctx.registerFakeClass(ParentNodeDef)
  ?ctx.registerFakeClass(RootNodeDef)
  ?ctx.registerFakeClass(ElementAccessorDef)
  ?ctx.registerFakeClass(CollectionLikeDef)
  ?ctx.registerFakeClass(CollectionDef)
  ?ctx.registerClass(NodeListDef)
  ?ctx.registerClass(HTMLCollectionDef)
  ?ctx.registerClass(HTMLAllCollectionDef)
  ?ctx.registerFakeClass(NodeIteratorLikeDef)
  ?ctx.registerClass(NodeIteratorDef)
  ?ctx.registerClass(TreeWalkerDef)
  ?ctx.registerClass(DocumentDef)
  ?ctx.registerClass(XMLDocumentDef)
  ?ctx.registerClass(DOMImplementationDef)
  ?ctx.registerClass(DOMTokenListDef)
  ?ctx.registerClass(DOMStringMapDef)
  ?ctx.registerClass(CharacterDataDef)
  ?ctx.registerClass(CommentDef)
  ?ctx.registerClass(DocumentFragmentDef)
  ?ctx.registerClass(ProcessingInstructionDef)
  ?ctx.registerClass(TextDef)
  ?ctx.registerClass(CDATASectionDef)
  ?ctx.registerClass(DocumentTypeDef)
  ?ctx.registerClass(AttrDef)
  ?ctx.registerClass(NamedNodeMapDef)
  ?ctx.registerClass(CSSStyleDeclarationDef)
  ?ctx.registerClass(CustomElementRegistryDef)
  ?ctx.registerClass(XMLSerializerDef)
  ?ctx.registerClass(ShadowRootDef)
  ?ctx.registerElements()
  let ctxOpaque = ctx.getOpaque()
  if ctxOpaque == nil:
    return ok()
  let global = ctxOpaque.global
  let document = JS_GetPropertyStr(ctx, global, "Document")
  if JS_IsException(document):
    return err()
  ?ctx.definePropertyCW(global, "HTMLDocument", document)
  let nodeFilter = JS_NewObject(ctx)
  if JS_IsException(nodeFilter):
    return err()
  for e in NodeFilterNode:
    let n = ctx.toJS(1u32 shl uint32(e))
    ?ctx.definePropertyE(nodeFilter, $e, n)
  for e in NodeFilterResult:
    let n = ctx.toJS(uint32(e))
    ?ctx.definePropertyE(nodeFilter, $e, n)
  ?ctx.definePropertyE(nodeFilter, "SHOW_ALL", ctx.toJS(0xFFFFFFFFu32))
  ctx.definePropertyCW(global, "NodeFilter", nodeFilter)

{.pop.} # raises: []
