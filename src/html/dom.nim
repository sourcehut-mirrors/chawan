import std/algorithm
import std/deques
import std/hashes
import std/math
import std/options
import std/posix
import std/sets
import std/strutils
import std/tables
import std/times

import chagashi/charset
import chagashi/decoder
import chame/tags
import config/mimetypes
import css/cssparser
import css/cssvalues
import css/mediaquery
import css/selectorparser
import css/sheet
import html/catom
import html/domexception
import html/enums
import html/event
import html/performance
import html/script
import io/bufwriter
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
import types/canvastypes
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

  Window* = ref object of EventTarget
    attrsp*: ptr WindowAttributes
    # In app mode, attrsp == scriptAttrsp.
    # In lite mode, scriptAttrsp == addr dummyAttrs.
    scriptAttrsp*: ptr WindowAttributes
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
    pendingResources*: seq[EmptyPromise]
    imageURLCache: Table[string, CachedURLImage]
    svgCache*: Table[string, SVGSVGElement]
    images*: bool
    styling*: bool
    autofocus*: bool
    inMicrotaskCheckpoint: bool
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

  CollectionMatchFun = proc(node: Node): bool {.noSideEffect.}

  Collection = ref object of RootObj
    islive: bool
    childonly: bool
    root: Node
    match: CollectionMatchFun
    snapshot: seq[Node]
    livelen: int

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

  DOMStringMap = object
    target {.cursor.}: HTMLElement

  Node* = ref object of EventTarget
    childList*: seq[Node]
    parentNode* {.jsget.}: Node
    index*: int # Index in parents children. -1 for nodes without a parent.
    # Live collection cache: pointers to live collections are saved in all
    # nodes they refer to. These are removed when the collection is destroyed,
    # and invalidated when the owner node's children or attributes change.
    liveCollections: seq[pointer]
    internalDocument: Document # not nil

  Attr* = ref object of Node
    dataIdx: int
    ownerElement*: Element

  DOMImplementation = object
    document: Document

  DocumentWriteBuffer* = ref object
    data*: string
    i*: int

  Document* = ref object of Node
    charset*: Charset
    window* {.jsget: "defaultView".}: Window
    url* {.jsget: "URL".}: URL # not nil
    mode*: QuirksMode
    currentScript {.jsget.}: HTMLScriptElement
    isxml*: bool
    implementation {.jsget.}: DOMImplementation
    origin: Origin
    readyState* {.jsget.}: DocumentReadyState
    # document.write
    ignoreDestructiveWrites: int
    throwOnDynamicMarkupInsertion*: int
    activeParserWasAborted: bool
    writeBuffers*: seq[DocumentWriteBuffer]
    styleDependencies: array[DependencyType, DependencyMap]

    scriptsToExecSoon*: seq[HTMLScriptElement]
    scriptsToExecInOrder*: Deque[HTMLScriptElement]
    scriptsToExecOnLoad*: Deque[HTMLScriptElement]
    parserBlockingScript*: HTMLScriptElement

    parserCannotChangeModeFlag*: bool
    internalFocus: Element
    internalTarget: Element
    contentType* {.jsget.}: string
    renderBlockingElements: seq[Element]

    invalidCollections: HashSet[pointer] # pointers to Collection objects
    invalid*: bool # whether the document must be rendered again

    cachedAll: HTMLAllCollection

    uaSheets*: seq[CSSStylesheet]
    userSheet*: CSSStylesheet
    authorSheets*: seq[CSSStylesheet]
    cachedForms: HTMLCollection
    parser*: RootRef

    internalCookie: string

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
    namespaceURI {.jsget.}: CAtom
    prefix {.jsget.}: CAtom
    internalHover: bool
    selfDepends: set[DependencyType]
    localName* {.jsget.}: CAtom
    id* {.jsget.}: CAtom
    name {.jsget.}: CAtom
    elIndex*: int # like index, but for elements only.
    classList* {.jsget.}: DOMTokenList
    attrs*: seq[AttrData] # sorted by int(qualifiedName)
    cachedAttributes: NamedNodeMap
    cachedStyle*: CSSStyleDeclaration
    computed*: CSSValues
    computedMap*: seq[tuple[pseudo: PseudoElement; computed: CSSValues]]

  AttrDummyElement = ref object of Element

  CSSStyleDeclaration* = ref object
    computed: bool
    readonly: bool
    decls*: seq[CSSDeclaration]
    element: Element

  HTMLElement* = ref object of Element
    dataset {.jsget.}: DOMStringMap

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
    onReady: (proc())

  HTMLBaseElement* = ref object of HTMLElement

  HTMLAreaElement* = ref object of HTMLElement
    relList {.jsget.}: DOMTokenList

  HTMLButtonElement* = ref object of FormAssociatedElement
    ctype* {.jsget: "type".}: ButtonType

  HTMLTextAreaElement* = ref object of FormAssociatedElement
    value* {.jsget.}: string

  HTMLLabelElement* = ref object of HTMLElement

  HTMLCanvasElement* = ref object of HTMLElement
    ctx2d*: CanvasRenderingContext2D
    bitmap*: NetworkBitmap

  DrawingState = object
    # CanvasTransform
    transformMatrix: Matrix
    # CanvasFillStrokeStyles
    fillStyle: ARGBColor
    strokeStyle: ARGBColor
    # CanvasPathDrawingStyles
    lineWidth: float64
    # CanvasTextDrawingStyles
    textAlign: CanvasTextAlign
    # CanvasPath
    path: Path

  RenderingContext = ref object of RootObj

  CanvasRenderingContext2D = ref object of RenderingContext
    canvas {.jsget.}: HTMLCanvasElement
    bitmap: NetworkBitmap
    state: DrawingState
    stateStack: seq[DrawingState]
    ps*: PosixStream

  TextMetrics = ref object
    # x-direction
    width {.jsget.}: float64
    actualBoundingBoxLeft {.jsget.}: float64
    actualBoundingBoxRight {.jsget.}: float64
    # y-direction
    fontBoundingBoxAscent {.jsget.}: float64
    fontBoundingBoxDescent {.jsget.}: float64
    actualBoundingBoxAscent {.jsget.}: float64
    actualBoundingBoxDescent {.jsget.}: float64
    emHeightAscent {.jsget.}: float64
    emHeightDescent {.jsget.}: float64
    hangingBaseline {.jsget.}: float64
    alphabeticBaseline {.jsget.}: float64
    ideographicBaseline {.jsget.}: float64

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
jsDestructor(SVGElement)
jsDestructor(SVGSVGElement)
jsDestructor(Node)
jsDestructor(NodeList)
jsDestructor(HTMLCollection)
jsDestructor(HTMLFormControlsCollection)
jsDestructor(RadioNodeList)
jsDestructor(HTMLAllCollection)
jsDestructor(HTMLOptionsCollection)
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
jsDestructor(CanvasRenderingContext2D)
jsDestructor(TextMetrics)
jsDestructor(CSSStyleDeclaration)

# Forward declarations
func attr*(element: Element; s: StaticAtom): lent string
func attrb*(element: Element; s: CAtom): bool
func serializeFragment(res: var string; node: Node)
func value*(option: HTMLOptionElement): string
proc append*(parent, node: Node)
proc attr*(element: Element; name: CAtom; value: sink string)
proc attr*(element: Element; name: StaticAtom; value: sink string)
proc baseURL*(document: Document): URL
proc delAttr(element: Element; i: int; keep = false)
proc getImageId(window: Window): int
proc insertBefore*(parent, node: Node; before: Option[Node]): DOMResult[Node]
proc invalidate*(element: Element)
proc invalidate*(element: Element; dep: DependencyType)
proc invalidateCollections(node: Node)
proc newHTMLElement*(document: Document; tagType: TagType): HTMLElement
proc parseColor(element: Element; s: string): ARGBColor
proc reflectAttr(element: Element; name: CAtom; value: Option[string])
proc remove*(node: Node)
proc replaceAll(parent: Node; s: sink string)
proc attrl(element: Element; name: StaticAtom; value: int32)
proc attrul(element: Element; name: StaticAtom; value: uint32)
proc attrulgz(element: Element; name: StaticAtom; value: uint32)

# Forward declaration hacks
# set in css/match
var matchesImpl*: proc(element: Element; cxsels: seq[ComplexSelector]): bool
  {.nimcall, noSideEffect.} = nil
# set in html/chadombuilder
var parseHTMLFragmentImpl*: proc(element: Element; s: string): seq[Node]
  {.nimcall.}
var parseDocumentWriteChunkImpl*: proc(wrapper: RootRef) {.nimcall.}
# set in html/env
var fetchImpl*: proc(window: Window; input: JSValue;
  init = RequestInit(window: JS_UNDEFINED)): JSResult[FetchPromise]
  {.nimcall.} = nil

# For now, these are the same; on an API level however, getGlobal is guaranteed
# to be non-null, while getWindow may return null in the future. (This is in
# preparation for Worker support.)
func getGlobal*(ctx: JSContext): Window =
  let global = JS_GetGlobalObject(ctx)
  var window: Window
  assert ctx.fromJS(global, window).isSome
  JS_FreeValue(ctx, global)
  return window

func getWindow*(ctx: JSContext): Window =
  let global = JS_GetGlobalObject(ctx)
  var window: Window
  assert ctx.fromJS(global, window).isSome
  JS_FreeValue(ctx, global)
  return window

func console(window: Window): Console =
  return window.internalConsole

proc resetTransform(state: var DrawingState) =
  state.transformMatrix = newIdentityMatrix(3)

proc reset(state: var DrawingState) =
  state.resetTransform()
  state.fillStyle = rgba(0, 0, 0, 255)
  state.strokeStyle = rgba(0, 0, 0, 255)
  state.path = newPath()

proc create2DContext(jctx: JSContext; target: HTMLCanvasElement;
    options = JS_UNDEFINED) =
  let window = jctx.getWindow()
  let imageId = target.bitmap.imageId
  let loader = window.loader
  let (ps, ctlres) = loader.doPipeRequest("canvas-ctl-" & $imageId)
  if ps == nil:
    return
  let cacheId = loader.addCacheFile(ctlres.outputId, loader.clientPid)
  target.bitmap.cacheId = cacheId
  let request = newRequest(
    newURL("img-codec+x-cha-canvas:decode").get,
    httpMethod = hmPost,
    headers = newHeaders({"Cha-Image-Info-Only": "1"}),
    body = RequestBody(t: rbtOutput, outputId: ctlres.outputId)
  )
  let response = loader.doRequest(request)
  if response.res != 0:
    # no canvas module; give up
    ps.sclose()
    ctlres.close()
    return
  ctlres.close()
  response.close()
  target.ctx2d = CanvasRenderingContext2D(
    bitmap: target.bitmap,
    canvas: target,
    ps: ps
  )
  window.pendingCanvasCtls.add(target.ctx2d)
  ps.withPacketWriter w:
    w.swrite(pcSetDimensions)
    w.swrite(target.bitmap.width)
    w.swrite(target.bitmap.height)
  target.ctx2d.state.reset()

proc fillRect(ctx: CanvasRenderingContext2D; x1, y1, x2, y2: int;
    color: ARGBColor) =
  if ctx.ps != nil:
    ctx.ps.withPacketWriter w:
      w.swrite(pcFillRect)
      w.swrite(x1)
      w.swrite(y1)
      w.swrite(x2)
      w.swrite(y2)
      w.swrite(color)

proc strokeRect(ctx: CanvasRenderingContext2D; x1, y1, x2, y2: int;
    color: ARGBColor) =
  if ctx.ps != nil:
    ctx.ps.withPacketWriter w:
      w.swrite(pcStrokeRect)
      w.swrite(x1)
      w.swrite(y1)
      w.swrite(x2)
      w.swrite(y2)
      w.swrite(color)

proc fillPath(ctx: CanvasRenderingContext2D; path: Path; color: ARGBColor;
    fillRule: CanvasFillRule) =
  if ctx.ps != nil:
    let lines = path.getLineSegments()
    ctx.ps.withPacketWriter w:
      w.swrite(pcFillPath)
      w.swrite(lines)
      w.swrite(color)
      w.swrite(fillRule)

proc strokePath(ctx: CanvasRenderingContext2D; path: Path; color: ARGBColor) =
  if ctx.ps != nil:
    let lines = path.getLines()
    ctx.ps.withPacketWriter w:
      w.swrite(pcStrokePath)
      w.swrite(lines)
      w.swrite(color)

proc fillText(ctx: CanvasRenderingContext2D; text: string; x, y: float64;
    color: ARGBColor; align: CanvasTextAlign) =
  if ctx.ps != nil:
    ctx.ps.withPacketWriter w:
      w.swrite(pcFillText)
      w.swrite(text)
      w.swrite(x)
      w.swrite(y)
      w.swrite(color)
      w.swrite(align)

proc strokeText(ctx: CanvasRenderingContext2D; text: string; x, y: float64;
    color: ARGBColor; align: CanvasTextAlign) =
  if ctx.ps != nil:
    ctx.ps.withPacketWriter w:
      w.swrite(pcStrokeText)
      w.swrite(text)
      w.swrite(x)
      w.swrite(y)
      w.swrite(color)
      w.swrite(align)

proc clearRect(ctx: CanvasRenderingContext2D; x1, y1, x2, y2: int) =
  ctx.fillRect(0, 0, ctx.bitmap.width, ctx.bitmap.height, rgba(0, 0, 0, 0))

proc clear(ctx: CanvasRenderingContext2D) =
  ctx.clearRect(0, 0, ctx.bitmap.width, ctx.bitmap.height)

# CanvasState
proc save(ctx: CanvasRenderingContext2D) {.jsfunc.} =
  ctx.stateStack.add(ctx.state)

proc restore(ctx: CanvasRenderingContext2D) {.jsfunc.} =
  if ctx.stateStack.len > 0:
    ctx.state = ctx.stateStack.pop()

proc reset(ctx: CanvasRenderingContext2D) {.jsfunc.} =
  ctx.clear()
  ctx.stateStack.setLen(0)
  ctx.state.reset()

# CanvasTransform
#TODO scale
proc rotate(ctx: CanvasRenderingContext2D; angle: float64) {.jsfunc.} =
  if classify(angle) in {fcInf, fcNegInf, fcNan}:
    return
  ctx.state.transformMatrix *= newMatrix(
    me = @[
      cos(angle), -sin(angle), 0,
      sin(angle), cos(angle), 0,
      0, 0, 1
    ],
    w = 3,
    h = 3
  )

proc translate(ctx: CanvasRenderingContext2D; x, y: float64) {.jsfunc.} =
  for v in [x, y]:
    if classify(v) in {fcInf, fcNegInf, fcNan}:
      return
  ctx.state.transformMatrix *= newMatrix(
    me = @[
      1f64, 0, x,
      0, 1, y,
      0, 0, 1
    ],
    w = 3,
    h = 3
  )

proc transform(ctx: CanvasRenderingContext2D; a, b, c, d, e, f: float64)
    {.jsfunc.} =
  for v in [a, b, c, d, e, f]:
    if classify(v) in {fcInf, fcNegInf, fcNan}:
      return
  ctx.state.transformMatrix *= newMatrix(
    me = @[
      a, c, e,
      b, d, f,
      0, 0, 1
    ],
    w = 3,
    h = 3
  )

#TODO getTransform, setTransform with DOMMatrix (i.e. we're missing DOMMatrix)
proc setTransform(ctx: CanvasRenderingContext2D; a, b, c, d, e, f: float64)
    {.jsfunc.} =
  for v in [a, b, c, d, e, f]:
    if classify(v) in {fcInf, fcNegInf, fcNan}:
      return
  ctx.state.resetTransform()
  ctx.transform(a, b, c, d, e, f)

proc resetTransform(ctx: CanvasRenderingContext2D) {.jsfunc.} =
  ctx.state.resetTransform()

func transform(ctx: CanvasRenderingContext2D; v: Vector2D): Vector2D =
  let mul = ctx.state.transformMatrix * newMatrix(@[v.x, v.y, 1], 1, 3)
  return Vector2D(x: mul.me[0], y: mul.me[1])

# CanvasFillStrokeStyles
proc fillStyle(ctx: CanvasRenderingContext2D): string {.jsfget.} =
  return ctx.state.fillStyle.serialize()

proc fillStyle(ctx: CanvasRenderingContext2D; s: string) {.jsfset.} =
  #TODO gradient, pattern
  ctx.state.fillStyle = ctx.canvas.parseColor(s)

proc strokeStyle(ctx: CanvasRenderingContext2D): string {.jsfget.} =
  return ctx.state.strokeStyle.serialize()

proc strokeStyle(ctx: CanvasRenderingContext2D; s: string) {.jsfset.} =
  #TODO gradient, pattern
  ctx.state.strokeStyle = ctx.canvas.parseColor(s)

# CanvasRect
proc clearRect(ctx: CanvasRenderingContext2D; x, y, w, h: float64) {.jsfunc.} =
  for v in [x, y, w, h]:
    if classify(v) in {fcInf, fcNegInf, fcNan}:
      return
  #TODO clipping regions (right now we just clip to default)
  let bw = float64(ctx.bitmap.width)
  let bh = float64(ctx.bitmap.height)
  let x1 = int(min(max(x, 0), bw))
  let y1 = int(min(max(y, 0), bh))
  let x2 = int(min(max(x + w, 0), bw))
  let y2 = int(min(max(y + h, 0), bh))
  ctx.clearRect(x1, y1, x2, y2)

proc fillRect(ctx: CanvasRenderingContext2D; x, y, w, h: float64) {.jsfunc.} =
  for v in [x, y, w, h]:
    if classify(v) in {fcInf, fcNegInf, fcNan}:
      return
  #TODO do we have to clip here?
  if w == 0 or h == 0:
    return
  let bw = float64(ctx.bitmap.width)
  let bh = float64(ctx.bitmap.height)
  let x1 = int(min(max(x, 0), bw))
  let y1 = int(min(max(y, 0), bh))
  let x2 = int(min(max(x + w, 0), bw))
  let y2 = int(min(max(y + h, 0), bh))
  ctx.fillRect(x1, y1, x2, y2, ctx.state.fillStyle)

proc strokeRect(ctx: CanvasRenderingContext2D; x, y, w, h: float64) {.jsfunc.} =
  for v in [x, y, w, h]:
    if classify(v) in {fcInf, fcNegInf, fcNan}:
      return
  #TODO do we have to clip here?
  if w == 0 or h == 0:
    return
  let bw = float64(ctx.bitmap.width)
  let bh = float64(ctx.bitmap.height)
  let x1 = int(min(max(x, 0), bw))
  let y1 = int(min(max(y, 0), bh))
  let x2 = int(min(max(x + w, 0), bw))
  let y2 = int(min(max(y + h, 0), bh))
  ctx.strokeRect(x1, y1, x2, y2, ctx.state.strokeStyle)

# CanvasDrawPath
proc beginPath(ctx: CanvasRenderingContext2D) {.jsfunc.} =
  ctx.state.path.beginPath()

proc fill(ctx: CanvasRenderingContext2D; fillRule = cfrNonZero) {.jsfunc.} =
  #TODO path
  ctx.state.path.tempClosePath()
  ctx.fillPath(ctx.state.path, ctx.state.fillStyle, fillRule)
  ctx.state.path.tempOpenPath()

proc stroke(ctx: CanvasRenderingContext2D) {.jsfunc.} = #TODO path
  ctx.strokePath(ctx.state.path, ctx.state.strokeStyle)

proc clip(ctx: CanvasRenderingContext2D; fillRule = cfrNonZero) {.jsfunc.} =
  #TODO path
  discard #TODO implement

#TODO clip, ...

# CanvasUserInterface

# CanvasText
#TODO maxwidth
proc fillText(ctx: CanvasRenderingContext2D; text: string; x, y: float64)
    {.jsfunc.} =
  for v in [x, y]:
    if classify(v) in {fcInf, fcNegInf, fcNan}:
      return
  let vec = ctx.transform(Vector2D(x: x, y: y))
  ctx.fillText(text, vec.x, vec.y, ctx.state.fillStyle, ctx.state.textAlign)

#TODO maxwidth
proc strokeText(ctx: CanvasRenderingContext2D; text: string; x, y: float64)
    {.jsfunc.} =
  for v in [x, y]:
    if classify(v) in {fcInf, fcNegInf, fcNan}:
      return
  let vec = ctx.transform(Vector2D(x: x, y: y))
  ctx.strokeText(text, vec.x, vec.y, ctx.state.strokeStyle, ctx.state.textAlign)

proc measureText(ctx: CanvasRenderingContext2D; text: string): TextMetrics
    {.jsfunc.} =
  let tw = text.width()
  return TextMetrics(
    width: 8 * float64(tw),
    actualBoundingBoxLeft: 0,
    actualBoundingBoxRight: 8 * float64(tw),
    #TODO and the rest...
  )

# CanvasDrawImage

# CanvasImageData

# CanvasPathDrawingStyles
proc lineWidth(ctx: CanvasRenderingContext2D): float64 {.jsfget.} =
  return ctx.state.lineWidth

proc lineWidth(ctx: CanvasRenderingContext2D; f: float64) {.jsfset.} =
  if classify(f) in {fcZero, fcNegZero, fcInf, fcNegInf, fcNan}:
    return
  ctx.state.lineWidth = f

proc setLineDash(ctx: CanvasRenderingContext2D; segments: seq[float64])
    {.jsfunc.} =
  discard #TODO implement

proc getLineDash(ctx: CanvasRenderingContext2D): seq[float64] {.jsfunc.} =
  discard #TODO implement

# CanvasTextDrawingStyles
proc textAlign(ctx: CanvasRenderingContext2D): string {.jsfget.} =
  return $ctx.state.textAlign

proc textAlign(ctx: CanvasRenderingContext2D; s: string) {.jsfset.} =
  let x = parseEnumNoCase[CanvasTextAlign](s)
  if x.isSome:
    ctx.state.textAlign = x.get

# CanvasPath
proc closePath(ctx: CanvasRenderingContext2D) {.jsfunc.} =
  ctx.state.path.closePath()

proc moveTo(ctx: CanvasRenderingContext2D; x, y: float64) {.jsfunc.} =
  ctx.state.path.moveTo(x, y)

proc lineTo(ctx: CanvasRenderingContext2D; x, y: float64) {.jsfunc.} =
  ctx.state.path.lineTo(x, y)

proc quadraticCurveTo(ctx: CanvasRenderingContext2D; cpx, cpy, x,
    y: float64) {.jsfunc.} =
  ctx.state.path.quadraticCurveTo(cpx, cpy, x, y)

proc arcTo(ctx: CanvasRenderingContext2D; x1, y1, x2, y2, radius: float64):
    Err[DOMException] {.jsfunc.} =
  if radius < 0:
    return errDOMException("Expected positive radius, but got negative",
      "IndexSizeError")
  ctx.state.path.arcTo(x1, y1, x2, y2, radius)
  return ok()

proc arc(ctx: CanvasRenderingContext2D; x, y, radius, startAngle,
    endAngle: float64; counterclockwise = false): Err[DOMException]
    {.jsfunc.} =
  if radius < 0:
    return errDOMException("Expected positive radius, but got negative",
      "IndexSizeError")
  ctx.state.path.arc(x, y, radius, startAngle, endAngle, counterclockwise)
  return ok()

proc ellipse(ctx: CanvasRenderingContext2D; x, y, radiusX, radiusY, rotation,
    startAngle, endAngle: float64; counterclockwise = false): Err[DOMException]
    {.jsfunc.} =
  if radiusX < 0 or radiusY < 0:
    return errDOMException("Expected positive radius, but got negative",
      "IndexSizeError")
  ctx.state.path.ellipse(x, y, radiusX, radiusY, rotation, startAngle, endAngle,
    counterclockwise)
  return ok()

proc rect(ctx: CanvasRenderingContext2D; x, y, w, h: float64) {.jsfunc.} =
  ctx.state.path.rect(x, y, w, h)

proc roundRect(ctx: CanvasRenderingContext2D; x, y, w, h, radii: float64)
    {.jsfunc.} =
  ctx.state.path.roundRect(x, y, w, h, radii)

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

func makes(name: string; ts: set[TagType]): ReflectEntry =
  let name = name.toStaticAtom()
  ReflectEntry(
    attrname: name,
    funcname: name,
    t: rtStr,
    tags: ts
  )

func makes(attrname, funcname: string; ts: set[TagType]): ReflectEntry =
  ReflectEntry(
    attrname: attrname.toStaticAtom(),
    funcname: funcname.toStaticAtom(),
    t: rtStr,
    tags: ts
  )

func makes(name: string; ts: varargs[TagType]): ReflectEntry =
  makes(name, toset(ts))

func makes(attrname, funcname: string; ts: varargs[TagType]): ReflectEntry =
  makes(attrname, funcname, toset(ts))

func makeb(attrname, funcname: string; ts: varargs[TagType]): ReflectEntry =
  ReflectEntry(
    attrname: attrname.toStaticAtom(),
    funcname: funcname.toStaticAtom(),
    t: rtBool,
    tags: toset(ts)
  )

func makeb(name: static string; ts: varargs[TagType]): ReflectEntry =
  makeb(name, name, ts)

func makeul(name: string; ts: varargs[TagType]; default = 0u32): ReflectEntry =
  let name = name.toStaticAtom()
  ReflectEntry(
    attrname: name,
    funcname: name,
    t: rtUlong,
    tags: toset(ts),
    u: default
  )

func makeulgz(name: string; ts: varargs[TagType]; default = 0u32):
    ReflectEntry =
  let name = name.toStaticAtom()
  ReflectEntry(
    attrname: name,
    funcname: name,
    t: rtUlongGz,
    tags: toset(ts),
    u: default
  )

func makef(name: string; ctype: string): ReflectEntry =
  let name = name.toStaticAtom()
  ReflectEntry(
    attrname: name,
    funcname: name,
    t: rtFunction,
    tags: AllTagTypes,
    ctype: ctype.toStaticAtom()
  )

# Note: this table only works for tag types with a registered interface.
const ReflectTable0 = [
  # non-global attributes
  makes("target", TAG_A, TAG_AREA, TAG_LABEL, TAG_LINK),
  makes("href", TAG_LINK),
  makes("value", TAG_BUTTON),
  makeb("required", TAG_INPUT, TAG_SELECT, TAG_TEXTAREA),
  makes("name", TAG_INPUT, TAG_SELECT, TAG_TEXTAREA, TAG_META, TAG_IFRAME),
  makeb("novalidate", "noValidate", TAG_FORM),
  makeb("selected", "defaultSelected", TAG_OPTION),
  makes("rel", TAG_A, TAG_LINK, TAG_LABEL),
  makes("for", "htmlFor", TAG_LABEL),
  makes("http-equiv", "httpEquiv", TAG_META),
  makes("content", TAG_META),
  makes("media", TAG_META),
  makeul("cols", TAG_TEXTAREA, 20u32),
  makeul("rows", TAG_TEXTAREA, 1u32),
# > For historical reasons, the default value of the size IDL attribute
# > does not return the actual size used, which, in the absence of the
# > size content attribute, is either 1 or 4 depending on the presence
# > of the multiple attribute.
  makeulgz("size", TAG_SELECT, 0u32),
  makeulgz("size", TAG_INPUT, 20u32),
  makeul("width", TAG_CANVAS, 300u32),
  makeul("height", TAG_CANVAS, 150u32),
  makes("alt", TAG_IMG),
  makes("src", TAG_IMG, TAG_SCRIPT, TAG_IFRAME),
  makes("srcset", TAG_IMG),
  makes("sizes", TAG_IMG),
  #TODO can we add crossOrigin here?
  makes("usemap", "useMap", TAG_IMG),
  makeb("ismap", "isMap", TAG_IMG),
  makeb("disabled", TAG_LINK, TAG_OPTION, TAG_SELECT, TAG_OPTGROUP),
  # super-global attributes
  makes("class", "className", AllTagTypes),
  makef("onclick", "click"),
  makef("oninput", "input"),
  makef("onchange", "change"),
  makef("onload", "load"),
  makes("slot", AllTagTypes),
  makes("title", AllTagTypes),
]

func document*(node: Node): Document =
  if node of Document:
    return Document(node)
  return node.internalDocument

template document*(element: Element): Document =
  element.internalDocument

func namespace*(element: Element): Namespace =
  return element.namespaceURI.toNamespace()

func tagTypeNoNS(element: Element): TagType =
  return element.localName.toTagType()

func tagType*(element: Element; namespace = Namespace.HTML): TagType =
  if element.namespace != namespace:
    return TAG_UNKNOWN
  return element.tagTypeNoNS

func findAttr(element: Element; qualifiedName: CAtom): int =
  for i, attr in element.attrs.mypairs:
    if attr.qualifiedName == qualifiedName:
      return i
  return -1

func findAttr(element: Element; qualifiedName: StaticAtom): int =
  return element.findAttr(qualifiedName.toAtom())

func findAttrNS(element: Element; namespace, qualifiedName: CAtom): int =
  for i, attr in element.attrs.mypairs:
    if attr.namespace == namespace and attr.qualifiedName == qualifiedName:
      return i
  return -1

func escapeText(s: string; attributeMode = false): string =
  result = newStringOfCap(s.len)
  var nbspMode = false
  var nbspPrev = '\0'
  for c in s:
    if nbspMode:
      if c == '\xA0':
        result &= "&nbsp;"
      else:
        result &= nbspPrev & c
      nbspMode = false
    elif c == '&':
      result &= "&amp;"
    elif c == '\xC2':
      nbspMode = true
      nbspPrev = c
    elif attributeMode and c == '"':
      result &= "&quot;"
    elif not attributeMode and c == '<':
      result &= "&lt;"
    elif not attributeMode and c == '>':
      result &= "&gt;"
    else:
      result &= c

when defined(debug):
  func `$`*(node: Node): string =
    if node == nil:
      return "null"
    if node of Element:
      let element = Element(node)
      result = "<" & $element.localName
      for attr in element.attrs:
        let k = $attr.localName
        result &= ' ' & k & "=\"" & attr.value.escapeText(true) & "\""
      result &= ">\n"
      for node in element.childList:
        for line in ($node).split('\n'):
          result &= "\t" & line & "\n"
      result &= "</" & $element.localName & ">"
    elif node of Text:
      let text = Text(node)
      result = text.data.escapeText()
    elif node of Comment:
      result = "<!-- " & Comment(node).data & "-->"
    elif node of ProcessingInstruction:
      result = "" #TODO
    elif node of DocumentType:
      result = "<!DOCTYPE" & ' ' & DocumentType(node).name & ">"
    elif node of Document:
      result = "Node of Document"
    elif node of DocumentFragment:
      result = "Node of DocumentFragment"
    else:
      result = "Unknown node"

func parentElement*(node: Node): Element {.jsfget.} =
  let p = node.parentNode
  if p != nil and p of Element:
    return Element(p)
  return nil

iterator elementList*(node: Node): Element {.inline.} =
  for child in node.childList:
    if child of Element:
      yield Element(child)

iterator elementList_rev*(node: Node): Element {.inline.} =
  for i in countdown(node.childList.high, 0):
    let child = node.childList[i]
    if child of Element:
      yield Element(child)

# Returns the node's ancestors
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

# Returns the node itself and its ancestors
iterator branch*(node: Node): Node {.inline.} =
  var node = node
  while node != nil:
    yield node
    node = node.parentNode

iterator branchElems*(node: Node): Element {.inline.} =
  for node in node.branch:
    if node of Element:
      yield Element(node)

# Returns the node's descendants
iterator descendants*(node: Node): Node {.inline.} =
  var stack: seq[Node] = @[]
  for i in countdown(node.childList.high, 0):
    stack.add(node.childList[i])
  while stack.len > 0:
    let node = stack.pop()
    yield node
    for i in countdown(node.childList.high, 0):
      stack.add(node.childList[i])

# Descendants, and the node itself.
iterator descendantsIncl(node: Node): Node {.inline.} =
  var stack = @[node]
  while stack.len > 0:
    let node = stack.pop()
    yield node
    for i in countdown(node.childList.high, 0):
      stack.add(node.childList[i])

# Element descendants.
iterator elements*(node: Node): Element {.inline.} =
  for child in node.descendants:
    if child of Element:
      yield Element(child)

# Element descendants, and the node itself (if it's an element).
iterator elementsIncl(node: Node): Element {.inline.} =
  for child in node.descendantsIncl:
    if child of Element:
      yield Element(child)

iterator elements(node: Node; tag: TagType): Element {.inline.} =
  for desc in node.elements:
    if desc.tagType == tag:
      yield desc

iterator elements*(node: Node; tag: set[TagType]): Element {.inline.} =
  for desc in node.elements:
    if desc.tagType in tag:
      yield desc

iterator displayedElements*(window: Window; tag: TagType): Element
    {.inline.} =
  let node = window.document
  var stack: seq[Node] = @[]
  for i in countdown(node.childList.high, 0):
    stack.add(node.childList[i])
  while stack.len > 0:
    let node = stack.pop()
    if node of Element:
      let element = Element(node)
      window.maybeRestyle(element)
      if element.computed{"display"} != DisplayNone:
        yield element
        for i in countdown(node.childList.high, 0):
          stack.add(node.childList[i])

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
      for input in input.document.elements(TAG_INPUT):
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

template id(collection: Collection): pointer =
  cast[pointer](addr collection[])

proc addCollection(node: Node; collection: Collection) =
  let i = node.liveCollections.find(nil)
  if i != -1:
    node.liveCollections[i] = collection.id
  else:
    node.liveCollections.add(collection.id)

proc populateCollection(collection: Collection) =
  if collection.childonly:
    for child in collection.root.childList:
      if collection.match == nil or collection.match(child):
        collection.snapshot.add(child)
  else:
    for desc in collection.root.descendants:
      if collection.match == nil or collection.match(desc):
        collection.snapshot.add(desc)
  if collection.islive:
    for child in collection.snapshot:
      child.addCollection(collection)
    collection.root.addCollection(collection)

proc refreshCollection(collection: Collection) =
  let document = collection.root.document
  if not document.invalidCollections.missingOrExcl(collection.id):
    assert collection.islive
    for child in collection.snapshot:
      let i = child.liveCollections.find(collection.id)
      assert i != -1
      child.liveCollections.del(i)
    collection.snapshot.setLen(0)
    collection.populateCollection()

proc finalize0(collection: Collection) =
  if collection.islive:
    # Do not del() liveCollections here, so that it remains valid to
    # iterate over them while allocating anything.
    # (Otherwise, we could modify the length of the seq if the finalizer
    # gets called as a result of the invalidateCollections incl call,
    # thereby breaking the iteration.)
    for child in collection.snapshot:
      let i = child.liveCollections.find(collection.id)
      assert i != -1
      child.liveCollections[i] = nil
      assert child.liveCollections.find(collection.id) == -1
    let i = collection.root.liveCollections.find(collection.id)
    assert i != -1
    collection.root.liveCollections[i] = nil
    collection.root.document.invalidCollections.excl(collection.id)

proc finalize(collection: HTMLCollection) {.jsfin.} =
  collection.finalize0()

proc finalize(collection: NodeList) {.jsfin.} =
  collection.finalize0()

proc finalize(collection: HTMLFormControlsCollection) {.jsfin.} =
  collection.finalize0()

proc finalize(collection: HTMLOptionsCollection) {.jsfin.} =
  collection.finalize0()

proc finalize(collection: RadioNodeList) {.jsfin.} =
  collection.finalize0()

proc finalize(collection: HTMLAllCollection) {.jsfin.} =
  collection.finalize0()

func ownerDocument(node: Node): Document {.jsfget.} =
  if node of Document:
    return nil
  return node.document

func hasChildNodes(node: Node): bool {.jsfunc.} =
  return node.childList.len > 0

proc getLength(collection: Collection): int =
  collection.refreshCollection()
  return collection.snapshot.len

proc findNode(collection: Collection; node: Node): int =
  collection.refreshCollection()
  return collection.snapshot.find(node)

func newCollection[T: Collection](root: Node; match: CollectionMatchFun;
    islive, childonly: bool): T =
  result = T(
    islive: islive,
    childonly: childonly,
    match: match,
    root: root
  )
  result.populateCollection()

func newHTMLCollection(root: Node; match: CollectionMatchFun;
    islive, childonly: bool): HTMLCollection =
  return newCollection[HTMLCollection](root, match, islive, childonly)

func newNodeList(root: Node; match: CollectionMatchFun;
    islive, childonly: bool): NodeList =
  return newCollection[NodeList](root, match, islive, childonly)

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

func jsNodeType(node: Node): uint16 {.jsfget: "nodeType".} =
  return uint16(node.jsNodeType0)

func isElement(node: Node): bool =
  return node of Element

proc parentNodeChildrenImpl(ctx: JSContext; parentNode: Node): JSValue =
  let children = ctx.toJS(parentNode.newHTMLCollection(
    match = isElement,
    islive = true,
    childonly = true
  ))
  let this = ctx.toJS(parentNode)
  ctx.definePropertyCW(this, "children", JS_DupValue(ctx, children))
  JS_FreeValue(ctx, this)
  return children

func children(ctx: JSContext; parentNode: Document): JSValue {.jsfget.} =
  return parentNodeChildrenImpl(ctx, parentNode)

func children(ctx: JSContext; parentNode: DocumentFragment): JSValue
    {.jsfget.} =
  return parentNodeChildrenImpl(ctx, parentNode)

func children(ctx: JSContext; parentNode: Element): JSValue {.jsfget.} =
  return parentNodeChildrenImpl(ctx, parentNode)

func childNodes(ctx: JSContext; node: Node): JSValue {.jsfget.} =
  let childNodes = ctx.toJS(node.newNodeList(
    match = nil,
    islive = true,
    childonly = true
  ))
  let this = ctx.toJS(node)
  ctx.definePropertyCW(this, "childNodes", JS_DupValue(ctx, childNodes))
  JS_FreeValue(ctx, this)
  return childNodes

func isForm(node: Node): bool =
  return node of HTMLFormElement

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

#TODO take cookie jar from loader
func cookie(document: Document): string {.jsfget.} =
  return document.internalCookie

proc setCookie(document: Document; cookie: string) {.jsfset: "cookie".} =
  document.internalCookie = cookie

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
  return move(s)

proc update(tokenList: DOMTokenList) =
  if not tokenList.element.attrb(tokenList.localName) and
      tokenList.toks.len == 0:
    return
  tokenList.element.attr(tokenList.localName, $tokenList)

proc validateDOMToken(ctx: JSContext; document: Document; tok: JSValue):
    DOMResult[CAtom] =
  var res: string
  ?ctx.fromJS(tok, res)
  if res == "":
    return errDOMException("Got an empty string", "SyntaxError")
  if AsciiWhitespace in res:
    return errDOMException("Got a string containing whitespace",
      "InvalidCharacterError")
  return ok(res.toAtom())

proc add(ctx: JSContext; tokenList: DOMTokenList; tokens: varargs[JSValue]):
    Err[DOMException] {.jsfunc.} =
  var toks: seq[CAtom] = @[]
  for tok in tokens:
    toks.add(?ctx.validateDOMToken(tokenList.element.document, tok))
  tokenList.toks.add(toks)
  tokenList.update()
  return ok()

proc remove(ctx: JSContext; tokenList: DOMTokenList; tokens: varargs[JSValue]):
    Err[DOMException] {.jsfunc.} =
  var toks: seq[CAtom] = @[]
  for tok in tokens:
    toks.add(?ctx.validateDOMToken(tokenList.element.document, tok))
  for tok in toks:
    let i = tokenList.toks.find(tok)
    if i != -1:
      tokenList.toks.delete(i)
  tokenList.update()
  return ok()

proc toggle(ctx: JSContext; tokenList: DOMTokenList; token: JSValue;
    force = none(bool)): DOMResult[bool] {.jsfunc.} =
  let token = ?ctx.validateDOMToken(tokenList.element.document, token)
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

proc replace(ctx: JSContext; tokenList: DOMTokenList; token, newToken: JSValue):
    DOMResult[bool] {.jsfunc.} =
  let token = ?ctx.validateDOMToken(tokenList.element.document, token)
  let newToken = ?ctx.validateDOMToken(tokenList.element.document, newToken)
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
  if ctx.fromJS(atom, u).isSome:
    return ctx.item(this, u).uninitIfNull()
  return JS_UNINITIALIZED

proc validateName(name: string): DOMResult[void] =
  if not name.matchNameProduction():
    return errDOMException("Invalid character in name", "InvalidCharacterError")
  ok()

proc validateQName(qname: string): DOMResult[void] =
  if not qname.matchQNameProduction():
    return errDOMException("Invalid character in qualified name",
      "InvalidCharacterError")
  ok()

# DOMStringMap
proc delete(map: var DOMStringMap; name: string): bool {.jsfunc.} =
  let name = ("data-" & name.camelToKebabCase()).toAtom()
  let i = map.target.findAttr(name)
  if i != -1:
    map.target.delAttr(i)
  return i != -1

proc getter(ctx: JSContext; map: var DOMStringMap; name: string): JSValue
    {.jsgetownprop.} =
  let name = ("data-" & name.camelToKebabCase()).toAtom()
  let i = map.target.findAttr(name)
  if i != -1:
    return ctx.toJS(map.target.attrs[i].value)
  return JS_UNINITIALIZED

proc setter(map: var DOMStringMap; name, value: string): Err[DOMException]
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

func names(ctx: JSContext; map: var DOMStringMap): JSPropertyEnumList
    {.jspropnames.} =
  var list = newJSPropertyEnumList(ctx, uint32(map.target.attrs.len))
  for attr in map.target.attrs:
    let k = $attr.localName
    if k.startsWith("data-") and AsciiUpperAlpha notin k:
      list.add(k["data-".len .. ^1].kebabToCamelCase())
  return list

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
  if ctx.fromJS(atom, u).isSome:
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
    if it.id == atom or it.namespace == Namespace.HTML and it.name == atom:
      return it
  return nil

proc getter(ctx: JSContext; this: HTMLCollection; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  if ctx.fromJS(atom, u).isSome:
    return ctx.toJS(this.item(u)).uninitIfNull()
  var s: CAtom
  if ctx.fromJS(atom, s).isSome:
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
    if element.namespace == Namespace.HTML:
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
        element.namespace == Namespace.HTML and element.name == name,
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
  if ctx.fromJS(atom, u).isSome:
    return ctx.toJS(this.item(u)).uninitIfNull()
  var s: CAtom
  if ctx.fromJS(atom, s).isSome:
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
  if ctx.fromJS(atom, u).isSome:
    return ctx.toJS(this.item(u)).uninitIfNull()
  return JS_UNINITIALIZED

func names(ctx: JSContext; this: HTMLAllCollection): JSPropertyEnumList
    {.jspropnames.} =
  let L = this.length
  var list = newJSPropertyEnumList(ctx, L)
  for u in 0 ..< L:
    list.add(u)
  return list

proc all(document: Document): HTMLAllCollection {.jsfget.} =
  if document.cachedAll == nil:
    document.cachedAll = newCollection[HTMLAllCollection](
      root = document,
      match = isElement,
      islive = true,
      childonly = false
    )
  return document.cachedAll

# Location
proc newLocation*(window: Window): Location =
  let location = Location(window: window)
  let ctx = window.jsctx
  if ctx != nil:
    let val = toJS(ctx, location)
    let valueOf = ctx.getOpaque().valRefs[jsvObjectPrototypeValueOf]
    defineProperty(ctx, val, "valueOf", JS_DupValue(ctx, valueOf))
    defineProperty(ctx, val, "toPrimitive", JS_UNDEFINED)
    #TODO [[DefaultProperties]]
    JS_FreeValue(ctx, val)
  return location

func location(document: Document): Location {.jsfget.} =
  if document.window == nil:
    return nil
  return document.window.location

func document(location: Location): Document =
  return location.window.document

proc url(location: Location): URL =
  let document = location.document
  if document != nil:
    return document.url
  return newURL("about:blank").get

proc setLocation*(document: Document; s: string): Err[JSError]
    {.jsfset: "location".} =
  if document.location == nil:
    return errTypeError("document.location is not an object")
  let url = parseURL(s)
  if url.isNone:
    return errDOMException("Invalid URL", "SyntaxError")
  document.window.navigate(url.get)
  return ok()

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
  if copyURL.scheme != "http" and copyURL.scheme != "https":
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

func jsOwnerElement(attr: Attr): Element {.jsfget: "ownerElement".} =
  if attr.ownerElement of AttrDummyElement:
    return nil
  return attr.ownerElement

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
    internalDocument: map.element.document,
    index: -1,
    dataIdx: dataIdx,
    ownerElement: map.element
  )
  map.attrlist.add(attr)
  return attr

proc normalizeAttrQName(element: Element; qualifiedName: string): CAtom =
  if element.namespace == Namespace.HTML and not element.document.isxml:
    return qualifiedName.toAtomLower()
  return qualifiedName.toAtom()

func hasAttributes(element: Element): bool {.jsfunc.} =
  return element.attrs.len > 0

func attributes(element: Element): NamedNodeMap {.jsfget.} =
  if element.cachedAttributes != nil:
    return element.cachedAttributes
  element.cachedAttributes = NamedNodeMap(element: element)
  for i, attr in element.attrs.mypairs:
    element.cachedAttributes.attrlist.add(Attr(
      internalDocument: element.document,
      index: -1,
      dataIdx: i,
      ownerElement: element
    ))
  return element.cachedAttributes

proc findAttr(element: Element; qualifiedName: string): int =
  return element.findAttr(element.normalizeAttrQName(qualifiedName))

proc findAttrNS(element: Element; namespace, localName: string): int =
  let namespace = namespace.toAtom()
  let localName = localName.toAtom()
  return element.findAttrNS(namespace, localName)

proc hasAttribute(element: Element; qualifiedName: string): bool {.jsfunc.} =
  return element.findAttr(qualifiedName) != -1

proc hasAttributeNS(element: Element; namespace, localName: string): bool
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

proc getNamedItem(map: NamedNodeMap; qualifiedName: string): Attr
    {.jsfunc.} =
  let i = map.element.findAttr(qualifiedName)
  if i != -1:
    return map.getAttr(i)
  return nil

proc getNamedItemNS(map: NamedNodeMap; namespace, localName: string):
    Attr {.jsfunc.} =
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
  if ctx.fromJS(atom, u).isSome:
    return ok(map.item(u))
  var s: string
  ?ctx.fromJS(atom, s)
  return ok(map.getNamedItem(s))

func names(ctx: JSContext; map: NamedNodeMap): JSPropertyEnumList
    {.jspropnames.} =
  let len = if map.element.namespace == Namespace.HTML:
    uint32(map.attrlist.len + map.element.attrs.len)
  else:
    uint32(map.attrlist.len)
  var list = newJSPropertyEnumList(ctx, len)
  for u in 0 ..< len:
    list.add(u)
  var names: HashSet[string]
  let element = map.element
  for attr in element.attrs:
    let name = $attr.qualifiedName
    if element.namespace == Namespace.HTML and AsciiUpperAlpha in name:
      continue
    if name in names:
      continue
    names.incl(name)
    list.add(name)
  return list

func length(characterData: CharacterData): uint32 {.jsfget.} =
  return uint32(($characterData.data).utf16Len)

func tagName(element: Element): string {.jsfget.} =
  result = $element.prefix
  if result.len > 0:
    result &= ':'
  result &= $element.localName
  if element.namespace == Namespace.HTML:
    result = result.toUpperAscii()

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

func scriptingEnabled*(document: Document): bool =
  if document.window == nil:
    return false
  return document.window.settings.scripting != smFalse

func scriptingEnabled(element: Element): bool =
  return element.document.scriptingEnabled

func isSubmitButton*(element: Element): bool =
  if element of HTMLButtonElement:
    return element.attr(satType).equalsIgnoreCase("submit")
  elif element of HTMLInputElement:
    let element = HTMLInputElement(element)
    return element.inputType in {itSubmit, itImage}
  return false

# https://html.spec.whatwg.org/multipage/dynamic-markup-insertion.html#document-write-steps
proc write(ctx: JSContext; document: Document; args: varargs[JSValue]):
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

func findFirst*(document: Document; tagType: TagType): HTMLElement =
  for element in document.elements(tagType):
    return HTMLElement(element)
  nil

func head*(document: Document): HTMLElement {.jsfget.} =
  return document.findFirst(TAG_HEAD)

func body*(document: Document): HTMLElement {.jsfget.} =
  return document.findFirst(TAG_BODY)

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

func hasChildExcept(node: Node; nodeType: type; ex: Node): bool =
  for child in node.childList:
    if child == ex:
      continue
    if child of nodeType:
      return true
  return false

func previousSibling*(node: Node): Node {.jsfget.} =
  let i = node.index - 1
  if node.parentNode == nil or i < 0:
    return nil
  return node.parentNode.childList[i]

func nextSibling*(node: Node): Node {.jsfget.} =
  let i = node.index + 1
  if node.parentNode == nil or i >= node.parentNode.childList.len:
    return nil
  return node.parentNode.childList[i]

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

func rootNode(node: Node): Node =
  var node = node
  while node.parentNode != nil:
    node = node.parentNode
  return node

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

func firstChild*(node: Node): Node {.jsfget.} =
  if node.childList.len == 0:
    return nil
  return node.childList[0]

func lastChild*(node: Node): Node {.jsfget.} =
  if node.childList.len == 0:
    return nil
  return node.childList[^1]

func firstElementChild*(node: Node): Element =
  for child in node.elementList:
    return child
  return nil

func firstElementChild(this: Element): Element {.jsfget.} =
  return Node(this).firstElementChild

func firstElementChild(this: Document): Element {.jsfget.} =
  return Node(this).firstElementChild

func firstElementChild(this: DocumentFragment): Element {.jsfget.} =
  return Node(this).firstElementChild

func lastElementChild*(node: Node): Element =
  for child in node.elementList_rev:
    return child
  return nil

func lastElementChild(this: Element): Element {.jsfget.} =
  return Node(this).lastElementChild

func lastElementChild(this: Document): Element {.jsfget.} =
  return Node(this).lastElementChild

func lastElementChild(this: DocumentFragment): Element {.jsfget.} =
  return Node(this).lastElementChild

func childElementCountImpl(node: Node): int =
  let last = node.lastElementChild
  if last == nil:
    return 0
  return last.elIndex + 1

func childElementCount(this: Element): int {.jsfget.} =
  return this.childElementCountImpl

func childElementCount(this: Document): int {.jsfget.} =
  return this.childElementCountImpl

func childElementCount(this: DocumentFragment): int {.jsfget.} =
  return this.childElementCountImpl

func isFirstVisualNode*(element: Element): bool =
  if element.elIndex == 0:
    let parent = element.parentNode
    for child in parent.childList:
      if child == element:
        return true
      if child of Text and not Text(child).data.onlyWhitespace():
        break
  return false

func isLastVisualNode*(element: Element): bool =
  let parent = element.parentNode
  for i in countdown(parent.childList.high, 0):
    let child = parent.childList[i]
    if child == element:
      return true
    if child of Element:
      break
    if child of Text and not Text(child).data.onlyWhitespace():
      break
  return false

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
  for element in node.elementList_rev:
    if element.tagType == tagType:
      return element
  return nil

func findFirstChildNotOf(node: Node; tagType: set[TagType]): Element =
  for element in node.elementList:
    if element.tagType notin tagType:
      return element
  return nil

proc getElementById(document: Document; id: string): Element {.jsfunc.} =
  if id.len == 0:
    return nil
  let id = id.toAtom()
  for child in document.elements:
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

proc getElementsByTagNameImpl(root: Node; tagName: string): HTMLCollection =
  if tagName == "*":
    return root.newHTMLCollection(isElement, islive = true, childonly = false)
  let localName = tagName.toAtom()
  let localNameLower = localName.toLowerAscii()
  return root.newHTMLCollection(
    func(node: Node): bool =
      if node of Element:
        let element = Element(node)
        if element.namespace == Namespace.HTML:
          return element.localName == localNameLower
        return element.localName == localName
      return false,
    islive = true,
    childonly = false
  )

proc getElementsByTagName(document: Document; tagName: string): HTMLCollection
    {.jsfunc.} =
  return document.getElementsByTagNameImpl(tagName)

proc getElementsByTagName(element: Element; tagName: string): HTMLCollection
    {.jsfunc.} =
  return element.getElementsByTagNameImpl(tagName)

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
        return true,
    islive = true,
    childonly = false
  )

proc getElementsByClassName(document: Document; classNames: string):
    HTMLCollection {.jsfunc.} =
  return document.getElementsByClassNameImpl(classNames)

proc getElementsByClassName(element: Element; classNames: string):
    HTMLCollection {.jsfunc.} =
  return element.getElementsByClassNameImpl(classNames)

func previousElementSibling*(elem: Element): Element {.jsfget.} =
  let p = elem.parentNode
  if p == nil: return nil
  for i in countdown(elem.index - 1, 0):
    let node = p.childList[i]
    if node of Element:
      return Element(node)
  return nil

func nextElementSibling*(elem: Element): Element {.jsfget.} =
  let p = elem.parentNode
  if p == nil: return nil
  for i in elem.index + 1 .. p.childList.high:
    let node = p.childList[i]
    if node of Element:
      return Element(node)
  return nil

func documentElement*(document: Document): Element {.jsfget.} =
  return document.firstElementChild()

proc names(ctx: JSContext; document: Document): JSPropertyEnumList
    {.jspropnames.} =
  var list = newJSPropertyEnumList(ctx, 0)
  #TODO I'm not quite sure why location isn't added, so I'll add it
  # manually for now.
  list.add("location")
  #TODO exposed embed, exposed object
  for child in document.elements({TAG_FORM, TAG_IFRAME, TAG_IMG}):
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
    for child in document.elements({TAG_FORM, TAG_IFRAME, TAG_IMG}):
      if child.tagType == TAG_IMG and child.id == id and
          child.name != CAtomNull and child.name != satUempty.toAtom():
        return ctx.toJS(child)
      if child.name == id:
        return ctx.toJS(child)
  return JS_UNINITIALIZED

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

func attrl*(element: Element; s: StaticAtom): Option[int32] =
  return parseInt32(element.attr(s))

func attrulgz*(element: Element; s: StaticAtom): Option[uint32] =
  let x = parseUInt32(element.attr(s), allowSign = true)
  if x.isSome and x.get > 0:
    return x
  return none(uint32)

func attrul*(element: Element; s: StaticAtom): Option[uint32] =
  let x = parseUInt32(element.attr(s), allowSign = true)
  if x.isSome and x.get >= 0:
    return x
  return none(uint32)

func attrb*(element: Element; s: CAtom): bool =
  return element.findAttr(s) != -1

func attrb*(element: Element; at: StaticAtom): bool =
  return element.attrb(at.toAtom())

# https://html.spec.whatwg.org/multipage/parsing.html#serialising-html-fragments
func serializesAsVoid(element: Element): bool =
  const Extra = {TAG_BASEFONT, TAG_BGSOUND, TAG_FRAME, TAG_KEYGEN, TAG_PARAM}
  return element.tagType in VoidElements + Extra

func serializeFragmentInner(res: var string; child: Node; parentType: TagType) =
  if child of Element:
    let element = Element(child)
    let tags = $element.localName
    res &= '<'
    #TODO qualified name if not HTML, SVG or MathML
    res &= tags
    #TODO custom elements
    for attr in element.attrs:
      let k = $attr.qualifiedName
      res &= ' ' & k & "=\"" & attr.value.escapeText(true) & "\""
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
      res &= text.data.escapeText()
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
    if element.serializesAsVoid():
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

# HTMLElement
func crossOrigin0(element: HTMLElement): CORSAttribute =
  if not element.attrb(satCrossorigin):
    return caNoCors
  case element.attr(satCrossorigin)
  of "anonymous", "":
    return caAnonymous
  of "use-credentials":
    return caUseCredentials
  else:
    return caAnonymous

func crossOrigin(element: HTMLScriptElement): CORSAttribute {.jsfget.} =
  return element.crossOrigin0

func crossOrigin(element: HTMLImageElement): CORSAttribute {.jsfget.} =
  return element.crossOrigin0

func referrerpolicy(element: HTMLScriptElement): Option[ReferrerPolicy] =
  return strictParseEnum[ReferrerPolicy](element.attr(satReferrerpolicy))

func applyMediaQuery(ss: CSSStylesheet; window: Window): CSSStylesheet =
  if ss == nil:
    return nil
  var res = CSSStylesheet()
  res[] = ss[]
  for mq in ss.mqList:
    if mq.query.applies(window.settings.scripting, window.attrsp):
      res.add(mq.children.applyMediaQuery(window))
  return move(res)

proc applyUASheet*(document: Document) =
  const ua = staticRead"res/ua.css"
  document.uaSheets.add(ua.parseStylesheet(nil, document.window.attrsp)
    .applyMediaQuery(document.window))
  if document.documentElement != nil:
    document.documentElement.invalidate()

proc applyQuirksSheet*(document: Document) =
  if document.window == nil:
    return
  const quirks = staticRead"res/quirk.css"
  document.uaSheets.add(quirks.parseStylesheet(nil, document.window.attrsp)
    .applyMediaQuery(document.window))
  if document.documentElement != nil:
    document.documentElement.invalidate()

proc applyUserSheet*(document: Document; user: string) =
  document.userSheet = user.parseStylesheet(nil, document.window.attrsp)
    .applyMediaQuery(document.window)
  if document.documentElement != nil:
    document.documentElement.invalidate()

#TODO this should be cached & called incrementally
proc applyAuthorSheets*(document: Document) =
  let window = document.window
  if window != nil and window.styling and document.documentElement != nil:
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

proc findAnchor*(document: Document; id: string): Element =
  if id.len == 0:
    return nil
  let id = id.toAtom()
  for child in document.elements:
    if child.id == id:
      return child
    if child of HTMLAnchorElement and child.name == id:
      return child
  return nil

proc findMetaRefresh*(document: Document): Element =
  for child in document.elements(TAG_META):
    if child.attr(satHttpEquiv).equalsIgnoreCase("refresh"):
      return child
  return nil

func focus*(document: Document): Element {.jsfget: "activeElement".} =
  return document.internalFocus

proc setFocus*(document: Document; element: Element) =
  if document.focus != nil:
    document.focus.invalidate(dtFocus)
  document.internalFocus = element
  if element != nil:
    element.invalidate(dtFocus)

proc focus(ctx: JSContext; element: Element) {.jsfunc.} =
  let window = ctx.getWindow()
  if window != nil and window.autofocus:
    element.document.setFocus(element)

proc blur(ctx: JSContext; element: Element) {.jsfunc.} =
  let window = ctx.getWindow()
  if window != nil and window.autofocus:
    if element.document.focus == element:
      element.document.setFocus(nil)

proc scrollTo(element: Element) {.jsfunc.} =
  discard #TODO maybe in app mode?

proc scrollIntoView(element: Element) {.jsfunc.} =
  discard #TODO ditto

func target*(document: Document): Element =
  return document.internalTarget

proc setTarget*(document: Document; element: Element) =
  if document.target != nil:
    document.target.invalidate(dtTarget)
  document.internalTarget = element
  if element != nil:
    element.invalidate(dtTarget)

func hover*(element: Element): bool =
  return element.internalHover

proc setHover*(element: Element; hover: bool) =
  element.invalidate(dtHover)
  element.internalHover = hover

func findAutoFocus*(document: Document): Element =
  for child in document.elements:
    if child.attrb(satAutofocus):
      return child
  return nil

proc fireEvent*(window: Window; event: Event; target: EventTarget) =
  discard window.jsctx.dispatch(target, event)

proc fireEvent*(window: Window; name: StaticAtom; target: EventTarget) =
  let event = newEvent(name.toAtom(), target)
  event.isTrusted = true
  window.fireEvent(event, target)

proc parseColor(element: Element; s: string): ARGBColor =
  let cval = parseComponentValue(s)
  #TODO return element style
  # For now we just use white.
  let ec = rgba(255, 255, 255, 255)
  if cval.isNone:
    return ec
  let color0 = parseColor(cval.get)
  if color0.isNone:
    return ec
  let color = color0.get
  if color.isCell:
    return ec
  return color.argb

# HTMLHyperlinkElementUtils (for <a> and <area>)
proc reinitURL*(element: Element): Option[URL] =
  if element.attrb(satHref):
    let url = parseURL(element.attr(satHref), some(element.document.baseURL))
    if url.isSome and url.get.scheme != "blob":
      return url
  return none(URL)

proc hyperlinkGet(ctx: JSContext; this: JSValue; magic: cint): JSValue
    {.cdecl.} =
  var element: Element
  if ctx.fromJS(this, element).isNone:
    return JS_EXCEPTION
  let sa = StaticAtom(magic)
  let url = element.reinitURL()
  if url.isSome:
    let href = ctx.toJS(url.get)
    let res = JS_GetPropertyStr(ctx, href, cstring($sa))
    JS_FreeValue(ctx, href)
    return res
  if sa == satProtocol:
    return ctx.toJS(":")
  return ctx.toJS("")

proc hyperlinkSet(ctx: JSContext; this, val: JSValue; magic: cint): JSValue
    {.cdecl.} =
  var element: Element
  if ctx.fromJS(this, element).isNone:
    return JS_EXCEPTION
  let sa = StaticAtom(magic)
  if sa == satHref:
    var s: string
    if ctx.fromJS(val, s).isSome:
      element.attr(satHref, s)
      return JS_DupValue(ctx, val)
    return JS_EXCEPTION
  let url = element.reinitURL()
  if url.isSome:
    let href = ctx.toJS(url)
    let res = JS_SetPropertyStr(ctx, href, cstring($sa), JS_DupValue(ctx, val))
    if res < 0:
      return JS_EXCEPTION
    var outs: string
    if ctx.fromJS(href, outs).isSome:
      element.attr(satHref, outs)
    JS_FreeValue(ctx, href)
  return JS_DupValue(ctx, val)

proc hyperlinkGetProp(ctx: JSContext; element: HTMLElement; a: JSAtom;
    desc: ptr JSPropertyDescriptor): JSValue =
  var s: string
  if ctx.fromJS(a, s).isSome:
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
  let href = anchor.reinitURL()
  if href.isSome:
    return $href.get
  return ""

proc setRelList(anchor: HTMLAnchorElement; s: string) {.jsfset: "relList".} =
  anchor.attr(satRel, s)

# <area>
proc getter(ctx: JSContext; this: HTMLAreaElement; a: JSAtom;
    desc: ptr JSPropertyDescriptor): JSValue {.jsgetownprop.} =
  return ctx.hyperlinkGetProp(this, a, desc)

proc toString(area: HTMLAreaElement): string {.jsfunc.} =
  let href = area.reinitURL()
  if href.isSome:
    return $href.get
  return ""

proc setRelList(area: HTMLAreaElement; s: string) {.jsfset: "relList".} =
  area.attr(satRel, s)

# <base>
proc href(base: HTMLBaseElement): string {.jsfget.} =
  #TODO with fallback base url
  let url = parseURL(base.attr(satHref))
  if url.isSome:
    return $url.get
  return ""

# <button>
func jsForm(this: HTMLButtonElement): HTMLFormElement {.jsfget: "form".} =
  return this.form

proc setType(this: HTMLButtonElement; s: string) {.jsfset: "type".} =
  this.attr(satType, s)

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

proc `value=`*(this: HTMLInputElement; value: sink string) {.jsfset: "value".} =
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
      input.value.padToWidth(int(input.attrulgz(satSize).get(20)))
    )
  of itPassword:
    let n = int(input.attrulgz(satSize).get(20))
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
    return newRefString(s.padToWidth(int(input.attrulgz(satSize).get(20))))
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
  for elem in label.elements(LabelableElements):
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
        parent.namespace notin {Namespace.HTML, Namespace.SVG}):
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

func isOptionOf(node: Node; select: HTMLSelectElement): bool =
  if node of HTMLOptionElement:
    let parent = node.parentNode
    return parent == select or
      parent of HTMLOptGroupElement and parent.parentNode == select
  return false

proc names(ctx: JSContext; this: HTMLOptionsCollection): JSPropertyEnumList
    {.jspropnames.} =
  return ctx.names(HTMLCollection(this))

proc getter(ctx: JSContext; this: HTMLOptionsCollection; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  return ctx.getter(HTMLCollection(this), atom)

proc add(ctx: JSContext; this: HTMLOptionsCollection; element: Element;
    before = JS_NULL): JSValue {.jsfunc.} =
  if not (element of HTMLOptionElement or element of HTMLOptGroupElement):
    return JS_ThrowTypeError(ctx, "Expected option or optgroup element")
  var beforeEl: HTMLElement = nil
  var beforeIdx = -1
  if not JS_IsNull(before) and ctx.fromJS(before, beforeEl).isNone and
      ctx.fromJS(before, beforeIdx).isNone:
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
  let selectedOptions = ctx.toJS(this.newHTMLCollection(
    match = func(node: Node): bool =
      return node.isOptionOf(this) and HTMLOptionElement(node).selected,
    islive = true,
    childonly = false
  ))
  let this = ctx.toJS(this)
  ctx.definePropertyCW(this, "selectedOptions",
    JS_DupValue(ctx, selectedOptions))
  JS_FreeValue(ctx, this)
  return selectedOptions

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
    it.invalidateCollections()
    inc i

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
    it.invalidateCollections()

proc showPicker(this: HTMLSelectElement): Err[DOMException] {.jsfunc.} =
  # Per spec, we should do something if it's being rendered and on
  # transient user activation.
  # If this is ever implemented, then the "is rendered" check must
  # be app mode only.
  return errDOMException("not allowed", "NotAllowedError")

proc add(ctx: JSContext; this: HTMLSelectElement; element: Element;
    before = JS_NULL): JSValue {.jsfunc.} =
  return ctx.add(this.jsOptions, element, before)

proc remove(ctx: JSContext; this: HTMLSelectElement; idx: varargs[JSValue]):
    Opt[void] {.jsfunc.} =
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
    this.sheet = this.textContent.parseStylesheet(document.baseURL,
      window.attrsp).applyMediaQuery(window)
    document.applyAuthorSheets()

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

func isTBody(this: Node): bool =
  return this of Element and Element(this).tagType == TAG_TBODY

proc tBodies(ctx: JSContext; this: HTMLTableElement): JSValue {.jsfget.} =
  let tBodies = ctx.toJS(this.newHTMLCollection(
    match = isTBody,
    islive = true,
    childonly = true
  ))
  let this = ctx.toJS(this)
  ctx.definePropertyCW(this, "tBodies", JS_DupValue(ctx, tBodies))
  JS_FreeValue(ctx, this)
  return tBodies

func isRow(this: Node): bool =
  return this of Element and Element(this).tagType == TAG_TR

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

proc deleteTFoot(this: HTMLTableElement): Element {.jsfunc.} =
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
proc isCell(this: Node): bool =
  return this of Element and Element(this).tagType in {TAG_TD, TAG_TH}

proc cells(ctx: JSContext; this: HTMLTableRowElement): JSValue {.jsfget.} =
  let cells = ctx.toJS(this.newHTMLCollection(
    match = isCell,
    islive = true,
    childonly = true
  ))
  let this = ctx.toJS(this)
  ctx.definePropertyCW(this, "cells", JS_DupValue(ctx, cells))
  JS_FreeValue(ctx, this)
  return cells

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

func textAreaString*(textarea: HTMLTextAreaElement): string =
  result = ""
  let split = textarea.value.split('\n')
  let rows = int(textarea.attrul(satRows).get(1))
  for i in 0 ..< rows:
    let cols = int(textarea.attrul(satCols).get(20))
    if cols > 2:
      if i < split.len:
        result &= '[' & split[i].padToWidth(cols - 2) & "]\n"
      else:
        result &= '[' & ' '.repeat(cols - 2) & "]\n"
    else:
      result &= "[]\n"

# <video>
func getSrc*(this: HTMLElement): tuple[src, contentType: string] =
  let src = this.attr(satSrc)
  if src != "":
    return (src, "")
  for el in this.elements(TAG_SOURCE):
    let src = el.attr(satSrc)
    if src != "":
      return (src, el.attr(satType))
  return ("", "")

func newText*(document: Document; data: sink string): Text =
  return Text(
    internalDocument: document,
    data: newRefString(data),
    index: -1
  )

func newText(ctx: JSContext; data: sink string = ""): Text {.jsctor.} =
  let window = ctx.getGlobal()
  return window.document.newText(data)

func newCDATASection(document: Document; data: string): CDATASection =
  return CDATASection(
    internalDocument: document,
    data: newRefString(data),
    index: -1
  )

func newProcessingInstruction(document: Document; target: string;
    data: sink string): ProcessingInstruction =
  return ProcessingInstruction(
    internalDocument: document,
    target: target,
    data: newRefString(data),
    index: -1
  )

func newDocumentFragment(document: Document): DocumentFragment =
  return DocumentFragment(internalDocument: document, index: -1)

func newDocumentFragment(ctx: JSContext): DocumentFragment {.jsctor.} =
  let window = ctx.getGlobal()
  return window.document.newDocumentFragment()

func newComment(document: Document; data: sink string): Comment =
  return Comment(
    internalDocument: document,
    data: newRefString(data),
    index: -1
  )

func newComment(ctx: JSContext; data: sink string = ""): Comment {.jsctor.} =
  let window = ctx.getGlobal()
  return window.document.newComment(data)

#TODO custom elements
proc newElement*(document: Document; localName, namespaceURI, prefix: CAtom):
    Element =
  let tagType = localName.toTagType()
  let sns = namespaceURI.toStaticAtom()
  let element: Element = case tagType
  of TAG_INPUT:
    HTMLInputElement()
  of TAG_A:
    let anchor = HTMLAnchorElement(internalDocument: document)
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
    let link = HTMLLinkElement(internalDocument: document)
    link.relList = link.newDOMTokenList(satRel)
    link
  of TAG_FORM:
    let form = HTMLFormElement(internalDocument: document)
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
    let area = HTMLAreaElement(internalDocument: document)
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
  element.internalDocument = document
  element.classList = element.newDOMTokenList(satClassList)
  element.index = -1
  element.elIndex = -1
  if sns == satNamespaceHTML:
    let element = HTMLElement(element)
    element.dataset = DOMStringMap(target: element)
  return element

proc newElement*(document: Document; localName: CAtom;
    namespace = Namespace.HTML; prefix = NO_PREFIX): Element =
  return document.newElement(localName, namespace.toAtom(), prefix.toAtom())

proc newHTMLElement*(document: Document; tagType: TagType): HTMLElement =
  let localName = tagType.toAtom()
  return HTMLElement(document.newElement(localName, Namespace.HTML, NO_PREFIX))

proc newDocument*(): Document {.jsctor.} =
  let document = Document(
    url: newURL("about:blank").get,
    index: -1,
    contentType: "application/xml"
  )
  document.implementation = DOMImplementation(document: document)
  return document

proc newXMLDocument(): XMLDocument =
  let document = XMLDocument(
    url: newURL("about:blank").get,
    index: -1,
    contentType: "application/xml"
  )
  document.implementation = DOMImplementation(document: document)
  return document

func newDocumentType*(document: Document;
    name, publicId, systemId: sink string): DocumentType =
  return DocumentType(
    internalDocument: document,
    name: name,
    publicId: publicId,
    systemId: systemId,
    index: -1
  )

func isHostIncludingInclusiveAncestor*(a, b: Node): bool =
  for parent in b.branch:
    if parent == a:
      return true
  let root = b.rootNode
  if root of DocumentFragment and DocumentFragment(root).host != nil:
    for parent in root.branch:
      if parent == a:
        return true
  return false

proc baseURL*(document: Document): URL =
  #TODO frozen base url...
  var href = ""
  for base in document.elements(TAG_BASE):
    if base.attrb(satHref):
      href = base.attr(satHref)
  if href == "":
    return document.url
  let url = parseURL(href, some(document.url))
  if url.isNone:
    return document.url
  return url.get

proc baseURI(node: Node): string {.jsfget.} =
  return $node.document.baseURL

proc parseURL*(document: Document; s: string): Option[URL] =
  #TODO encodings
  return parseURL(s, some(document.baseURL))

func media*(element: HTMLElement): string =
  return element.attr(satMedia)

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

proc invalidateCollections(node: Node) =
  for id in node.liveCollections:
    if id != nil: # may be nil if finalizer removed it
      node.document.invalidCollections.incl(id)

proc delAttr(element: Element; i: int; keep = false) =
  let map = element.cachedAttributes
  let name = element.attrs[i].qualifiedName
  element.attrs.delete(i) # ordering matters
  if map != nil:
    # delete from attrlist + adjust indices invalidated
    var j = -1
    for i, attr in map.attrlist.mypairs:
      if attr.dataIdx == i:
        j = i
      elif attr.dataIdx > i:
        dec attr.dataIdx
    if j != -1:
      if keep:
        let attr = map.attrlist[j]
        let data = attr.data
        attr.ownerElement = AttrDummyElement(
          internalDocument: attr.ownerElement.document,
          index: -1,
          elIndex: -1,
          attrs: @[data]
        )
        attr.dataIdx = 0
      map.attrlist.del(j) # ordering does not matter
  element.reflectAttr(name, none(string))
  element.invalidateCollections()
  element.invalidate()

# Styles.
proc invalidate*(element: Element) =
  let valid = element.computed != nil
  element.computed = nil
  element.computedMap.setLen(0)
  if element.document != nil:
    element.document.invalid = true
  if valid:
    for it in element.elementList:
      it.invalidate()

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

proc applyStyleDependencies*(element: Element; depends: DependencyInfo) =
  let document = element.document
  element.selfDepends = {}
  for t, map in document.styleDependencies.mpairs:
    map.dependsOn.withValue(element, p):
      for it in p[]:
        map.dependedBy.del(it)
      document.styleDependencies[t].dependsOn.del(element)
    for el in depends[t]:
      if el == element:
        element.selfDepends.incl(t)
        continue
      document.styleDependencies[t].dependedBy.mgetOrPut(el, @[]).add(element)
      document.styleDependencies[t].dependsOn.mgetOrPut(element, @[]).add(el)

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
    if rule.name.isSupportedProperty():
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

func find(this: CSSStyleDeclaration; s: string): int =
  for i, decl in this.decls:
    if decl.name == s:
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
  if ctx.fromJS(atom, u).isSome:
    return ctx.toJS(this.item(u)).uninitIfNull()
  var s: string
  if ctx.fromJS(atom, s).isNone:
    return JS_EXCEPTION
  if s == "cssFloat":
    s = "float"
  if s.isSupportedProperty():
    return ctx.toJS(this.getPropertyValue(s))
  s = camelToKebabCase(s)
  if s.isSupportedProperty():
    return ctx.toJS(this.getPropertyValue(s))
  return JS_UNINITIALIZED

proc setValue(this: CSSStyleDeclaration; i: int; cvals: seq[CSSComponentValue]):
    Err[void] =
  if i notin 0 .. this.decls.high:
    return err()
  # dummyAttrs can be safely used because the result is discarded.
  var dummy: seq[CSSComputedEntry] = @[]
  ?dummy.parseComputedValues(this.decls[i].name, cvals, dummyAttrs)
  this.decls[i].value = cvals
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
  let cvals = parseComponentValues(value)
  if (let i = this.find(name); i != -1):
    if this.setValue(i, cvals).isNone:
      # not err! this does not throw.
      return ok()
  else:
    var dummy: seq[CSSComputedEntry] = @[]
    let val0 = dummy.parseComputedValues(name, cvals, dummyAttrs)
    if val0.isNone:
      return ok()
    this.decls.add(CSSDeclaration(name: name, value: cvals))
  this.element.attr(satStyle, $this.decls)
  ok()

proc setter(ctx: JSContext; this: CSSStyleDeclaration; atom: JSAtom;
    value: string): DOMResult[void] {.jssetprop.} =
  ?this.checkReadOnly()
  var u: uint32
  if ctx.fromJS(atom, u).isSome:
    let cvals = parseComponentValues(value)
    if this.setValue(int(u), cvals).isNone:
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
  if pseudo == peNone:
    return element.computed
  for it in element.computedMap:
    if it.pseudo == pseudo:
      return it.computed
  return nil

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

proc corsFetch(window: Window; input: Request): FetchPromise =
  if not window.images and input.url.scheme.startsWith("img-codec+"):
    return newResolvedPromise(JSResult[Response].err(newFetchTypeError()))
  return window.loader.fetch(input)

proc loadSheet(window: Window; link: HTMLLinkElement; url: URL):
    Promise[CSSStylesheet] =
  let p = window.corsFetch(
    newRequest(url)
  ).then(proc(res: JSResult[Response]): Promise[JSResult[string]] =
    if res.isSome:
      let res = res.get
      if res.getContentType().equalsIgnoreCase("text/css"):
        return res.text()
      res.close()
    return newResolvedPromise(JSResult[string].err(nil))
  ).then(proc(s: JSResult[string]): Promise[CSSStylesheet] =
    if s.isSome:
      let sheet = s.get.parseStylesheet(url, window.attrsp)
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
        return sheet.applyMediaQuery(window)
      )
    return newResolvedPromise[CSSStylesheet](nil)
  )
  return p

# see https://html.spec.whatwg.org/multipage/links.html#link-type-stylesheet
#TODO make this somewhat compliant with ^this
proc loadResource(window: Window; link: HTMLLinkElement) =
  if not window.styling or not link.relList.containsIgnoreCase(satStylesheet) or
      link.fetchStarted or
      not link.enabled.get(not link.relList.containsIgnoreCase(satAlternate)):
    return
  link.fetchStarted = true
  let href = link.attr(satHref)
  if href == "":
    return
  let url = parseURL(href, window.document.url.some)
  if url.isSome:
    let url = url.get
    let media = link.media
    var applies = true
    if media != "":
      let cvals = parseComponentValues(media)
      let media = parseMediaQueryList(cvals, window.attrsp)
      applies = media.applies(window.settings.scripting, window.attrsp)
    let p = window.loadSheet(link, url).then(proc(sheet: CSSStylesheet) =
      # Note: we intentionally load all sheets first and *then* check
      # whether media applies, to prevent media query based tracking.
      if sheet != nil and applies:
        link.sheets.add(sheet)
        window.document.applyAuthorSheets()
        if window.document.documentElement != nil:
          window.document.documentElement.invalidate()
    )
    window.pendingResources.add(p)

proc getImageId(window: Window): int =
  result = window.imageId
  inc window.imageId

proc loadResource*(window: Window; image: HTMLImageElement) =
  if not window.images:
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
  let url = parseURL(src, window.document.url.some)
  if url.isSome:
    let url = url.get
    if window.document.url.scheme == "https" and url.scheme == "http":
      # mixed content :/
      #TODO maybe do this in loader?
      url.scheme = "https"
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
    let headers = newHeaders({"Accept": "*/*"})
    let p = window.corsFetch(newRequest(url, headers = headers)).then(
      proc(res: JSResult[Response]): EmptyPromise =
        if res.isNone:
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
        let cacheId = window.loader.addCacheFile(response.outputId,
          window.loader.clientPid)
        let url = newURL("img-codec+" & t & ":decode")
        if url.isNone:
          return newResolvedPromise()
        let request = newRequest(
          url.get,
          httpMethod = hmPost,
          headers = newHeaders({"Cha-Image-Info-Only": "1"}),
          body = RequestBody(t: rbtOutput, outputId: response.outputId),
        )
        let r = window.corsFetch(request)
        response.resume()
        response.close()
        var expiry = -1i64
        if "Cache-Control" in response.headers:
          for hdr in response.headers.table["Cache-Control"]:
            var i = hdr.find("max-age=")
            if i != -1:
              i = hdr.skipBlanks(i + "max-age=".len)
              let s = hdr.until(AllChars - AsciiDigit, i)
              let pi = parseInt64(s)
              if pi.isSome:
                expiry = getTime().utc().toTime().toUnix() + pi.get
              break
        cachedURL.loading = false
        cachedURL.expiry = expiry
        return r.then(proc(res: JSResult[Response]) =
          if res.isNone:
            return
          let response = res.get
          # close immediately; all data we're interested in is in the headers.
          response.close()
          let headers = response.headers
          let dims = headers.getOrDefault("Cha-Image-Dimensions")
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
            window.fireEvent(satLoad, image)
        )
      )
    window.pendingResources.add(p)

proc loadResource*(window: Window; svg: SVGSVGElement) =
  if not window.images:
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
  let cacheId = loader.addCacheFile(svgres.outputId, loader.clientPid)
  try:
    ps.sendDataLoop(s)
  except IOError:
    return
  finally:
    ps.sclose()
  let request = newRequest(
    newURL("img-codec+svg+xml:decode").get,
    httpMethod = hmPost,
    headers = newHeaders({"Cha-Image-Info-Only": "1"}),
    body = RequestBody(t: rbtOutput, outputId: svgres.outputId)
  )
  let p = loader.fetch(request).then(proc(res: JSResult[Response]) =
    svgres.close()
    if res.isNone: # no SVG module; give up
      return
    let response = res.get
    # close immediately; all data we're interested in is in the headers.
    response.close()
    let dims = response.headers.getOrDefault("Cha-Image-Dimensions")
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
  window.pendingResources.add(p)

proc runJSJobs*(window: Window) =
  while true:
    let r = window.jsrt.runJSJobs()
    if r.isSome:
      break
    let ctx = r.error
    ctx.writeException(window.console.err)

proc performMicrotaskCheckpoint*(window: Window) =
  if window.inMicrotaskCheckpoint:
    return
  window.inMicrotaskCheckpoint = true
  window.runJSJobs()
  window.inMicrotaskCheckpoint = false

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
      if tag notin result[1]:
        result[1][tag] = newSeq[int16]()
      result[1][tag].add(i)
    assert result[0][i].tags.len != 0
    inc i
  result[2] = i
  while i < ReflectTable0.len:
    let x = ReflectTable0[i]
    assert x.tags == AllTagTypes
    result[0].add(x)
    inc i
)()

proc jsReflectGet(ctx: JSContext; this: JSValue; magic: cint): JSValue
    {.cdecl.} =
  let entry = ReflectTable[uint16(magic)]
  let op = this.getOpaque()
  if unlikely(not ctx.isInstanceOf(this, "Element") or op == nil):
    return JS_ThrowTypeError(ctx,
      "Reflected getter called on a value that is not an element")
  let element = cast[Element](op)
  if element.tagType notin entry.tags:
    return JS_ThrowTypeError(ctx, "Invalid tag type %s", element.tagType)
  case entry.t
  of rtStr: return ctx.toJS(element.attr(entry.attrname))
  of rtBool: return ctx.toJS(element.attrb(entry.attrname))
  of rtLong: return ctx.toJS(element.attrl(entry.attrname).get(entry.i))
  of rtUlong: return ctx.toJS(element.attrul(entry.attrname).get(entry.u))
  of rtUlongGz: return ctx.toJS(element.attrulgz(entry.attrname).get(entry.u))
  of rtFunction: return JS_NULL

proc jsReflectSet(ctx: JSContext; this, val: JSValue; magic: cint): JSValue
    {.cdecl.} =
  if unlikely(not ctx.isInstanceOf(this, "Element")):
    return JS_ThrowTypeError(ctx,
      "Reflected getter called on a value that is not an element")
  let entry = ReflectTable[uint16(magic)]
  let op = this.getOpaque()
  assert op != nil
  let element = cast[Element](op)
  if element.tagType notin entry.tags:
    return JS_ThrowTypeError(ctx, "Invalid tag type %s", element.tagType)
  case entry.t
  of rtStr:
    var x: string
    if ctx.fromJS(val, x).isSome:
      element.attr(entry.attrname, x)
  of rtBool:
    var x: bool
    if ctx.fromJS(val, x).isSome:
      if x:
        element.attr(entry.attrname, "")
      else:
        let i = element.findAttr(entry.attrname)
        if i != -1:
          element.delAttr(i)
  of rtLong:
    var x: int32
    if ctx.fromJS(val, x).isSome:
      element.attrl(entry.attrname, x)
  of rtUlong:
    var x: uint32
    if ctx.fromJS(val, x).isSome:
      element.attrul(entry.attrname, x)
  of rtUlongGz:
    var x: uint32
    if ctx.fromJS(val, x).isSome:
      element.attrulgz(entry.attrname, x)
  of rtFunction:
    return ctx.eventReflectSet0(this, val, magic, jsReflectSet, entry.ctype)
  return JS_DupValue(ctx, val)

func findMagic(ctype: StaticAtom): cint =
  for i in ReflectAllStartIndex ..< int16(ReflectTable.len):
    let entry = ReflectTable[i]
    assert entry.tags == AllTagTypes
    if ReflectTable[i].t == rtFunction and ReflectTable[i].ctype == ctype:
      return cint(i)
  assert false

proc reflectEvent(element: Element; target: EventTarget;
    name, ctype: StaticAtom; value: string) =
  let document = element.document
  let ctx = document.window.jsctx
  let urls = document.baseURL.serialize(excludepassword = true)
  let fun = ctx.newFunction(["event"], value)
  assert ctx != nil
  if JS_IsException(fun):
    document.window.console.error("Exception in body content attribute of",
      urls, ctx.getExceptionMsg())
  else:
    let magic = findMagic(ctype)
    let this = ctx.toJS(target)
    JS_FreeValue(ctx, ctx.eventReflectSet0(this, fun, magic, jsReflectSet,
      ctype))
    JS_FreeValue(ctx, this)
    JS_FreeValue(ctx, fun)

proc reflectAttr(element: Element; name: CAtom; value: Option[string]) =
  let name = name.toStaticAtom()
  template reflect_str(element: Element; n: StaticAtom; val: untyped) =
    if name == n:
      element.val = value.get("")
      return
  template reflect_atom(element: Element; n: StaticAtom; val: untyped) =
    if name == n:
      if value.isSome:
        element.val = value.get.toAtom()
      else:
        element.val = CAtomNull
      return
  template reflect_bool(element: Element; n: StaticAtom; val: untyped) =
    if name == n:
      element.val = true
      return
  template reflect_domtoklist0(element: Element; val: untyped) =
    element.val.toks.setLen(0)
    if value.isSome:
      for x in value.get.split(AsciiWhitespace):
        if x != "":
          let a = x.toAtom()
          if a notin element.val:
            element.val.toks.add(a)
  template reflect_domtoklist(element: Element; n: StaticAtom; val: untyped) =
    if name == n:
      element.reflect_domtoklist0 val
      return
  element.reflect_atom satId, id
  element.reflect_atom satName, name
  element.reflect_domtoklist satClass, classList
  #TODO internalNonce
  if name == satStyle:
    if value.isSome:
      element.cachedStyle = newCSSStyleDeclaration(element, value.get)
    else:
      element.cachedStyle = nil
    return
  if name == satOnclick and element.scriptingEnabled:
    element.reflectEvent(element, name, satClick, value.get(""))
    return
  case element.tagType
  of TAG_BODY:
    if name == satOnload and element.scriptingEnabled:
      element.reflectEvent(element.document.window, name, satLoad,
        value.get(""))
      return
  of TAG_INPUT:
    let input = HTMLInputElement(element)
    if name == satOninput and element.scriptingEnabled:
      input.reflectEvent(input.document.window, name, satInput, value.get(""))
    input.reflect_str satValue, value
    if name == satChecked:
      input.setChecked(value.isSome)
    elif name == satType:
      input.inputType = parseEnumNoCase[InputType](value.get("")).get(itText)
  of TAG_OPTION:
    let option = HTMLOptionElement(element)
    option.reflect_bool satSelected, selected
  of TAG_BUTTON:
    let button = HTMLButtonElement(element)
    if name == satType:
      button.ctype = parseEnumNoCase[ButtonType](value.get("")).get(btSubmit)
  of TAG_LINK:
    let link = HTMLLinkElement(element)
    if name == satRel:
      link.reflect_domtoklist0 relList # do not return
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
    anchor.reflect_domtoklist satRel, relList
  of TAG_AREA:
    let area = HTMLAreaElement(element)
    area.reflect_domtoklist satRel, relList
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
  of TAG_SELECT:
    if name == satOnchange and element.scriptingEnabled:
      element.reflectEvent(element.document.window, name, satChange,
        value.get(""))
  else: discard

func cmpAttrName(a: AttrData; b: CAtom): int =
  return cmp(int(a.qualifiedName), int(b))

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
    element.invalidateCollections()
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
    element.invalidateCollections()
    element.invalidate()
  else:
    element.attrs.insert(AttrData(
      prefix: prefixAtom,
      localName: localName,
      qualifiedName: qualifiedName,
      namespace: namespace,
      value: value
    ), element.attrs.upperBound(qualifiedName, cmpAttrName))
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
  let qualifiedName = if element.namespace == Namespace.HTML and
      not element.document.isxml:
    qualifiedName.toAtomLower()
  else:
    qualifiedName.toAtom()
  element.attr(qualifiedName, value)
  return ok()

proc setAttributeNS(element: Element; namespace, qualifiedName,
    value: sink string): Err[DOMException] {.jsfunc.} =
  ?qualifiedName.validateQName()
  let ps = qualifiedName.until(':')
  let prefix = if ps.len < qualifiedName.len: ps else: ""
  let localName = qualifiedName.substr(prefix.len).toAtom()
  #TODO atomize here
  if prefix != "" and namespace == "" or
      prefix == "xml" and namespace != $Namespace.XML or
      (qualifiedName == "xmlns" or prefix == "xmlns") and
        namespace != $Namespace.XMLNS or
      namespace == $Namespace.XMLNS and qualifiedName != "xmlns" and
        prefix != "xmlns":
    return errDOMException("Unexpected namespace", "NamespaceError")
  let qualifiedName = qualifiedName.toAtom()
  let namespace = namespace.toAtom()
  let i = element.findAttrNS(namespace, localName)
  if i != -1:
    element.attrs[i].value = value
  else:
    element.attrs.add(AttrData(
      localName: localName,
      namespace: namespace,
      qualifiedName: qualifiedName,
      value: value
    ))
  return ok()

proc removeAttribute(element: Element; qualifiedName: string) {.jsfunc.} =
  let i = element.findAttr(qualifiedName)
  if i != -1:
    element.delAttr(i)

proc removeAttributeNS(element: Element; namespace, localName: string)
    {.jsfunc.} =
  let i = element.findAttrNS(namespace, localName)
  if i != -1:
    element.delAttr(i)

proc toggleAttribute(element: Element; qualifiedName: string;
    force = none(bool)): DOMResult[bool] {.jsfunc.} =
  ?qualifiedName.validateName()
  let qualifiedName = element.normalizeAttrQName(qualifiedName)
  if not element.attrb(qualifiedName):
    if force.get(true):
      element.attr(qualifiedName, "")
      return ok(true)
    return ok(false)
  if not force.get(false):
    let i = element.findAttr(qualifiedName)
    if i != -1:
      element.delAttr(i)
    return ok(false)
  return ok(true)

proc value(attr: Attr; s: string) {.jsfset.} =
  attr.ownerElement.attr(attr.data.qualifiedName, s)

proc setNamedItem(map: NamedNodeMap; attr: Attr): DOMResult[Attr]
    {.jsfunc.} =
  if attr.ownerElement == map.element:
    # Setting attr on its owner element does nothing, since the "get an
    # attribute by namespace and local name" step is used for retrieval
    # (which will always return self).
    return
  if attr.jsOwnerElement != nil:
    return errDOMException("Attribute is currently in use",
      "InUseAttributeError")
  let i = map.element.findAttrNS(attr.data.namespace, attr.data.localName)
  attr.ownerElement = map.element
  if i != -1:
    map.element.attrs[i] = attr.data
    return ok(attr)
  map.element.attrs.add(attr.data)
  return ok(nil)

proc setNamedItemNS(map: NamedNodeMap; attr: Attr): DOMResult[Attr]
    {.jsfunc.} =
  return map.setNamedItem(attr)

proc removeNamedItem(map: NamedNodeMap; qualifiedName: string):
    DOMResult[Attr] {.jsfunc.} =
  let i = map.element.findAttr(qualifiedName)
  if i != -1:
    let attr = map.getAttr(i)
    map.element.delAttr(i, keep = true)
    return ok(attr)
  return errDOMException("Item not found", "NotFoundError")

proc removeNamedItemNS(map: NamedNodeMap; namespace, localName: string):
    DOMResult[Attr] {.jsfunc.} =
  let i = map.element.findAttrNS(namespace, localName)
  if i != -1:
    let attr = map.getAttr(i)
    map.element.delAttr(i, keep = true)
    return ok(attr)
  return errDOMException("Item not found", "NotFoundError")

proc jsId(element: Element; id: string) {.jsfset: "id".} =
  element.attr(satId, id)

# Pass an index to avoid searching for the node in parent's child list.
proc remove*(node: Node; suppressObservers: bool) =
  let parent = node.parentNode
  assert parent != nil
  assert node.index != -1
  #TODO live ranges
  #TODO NodeIterator
  let element = if node of Element: Element(node) else: nil
  for i in node.index ..< parent.childList.len - 1:
    let it = parent.childList[i + 1]
    it.index = i
    if element != nil and it of Element:
      dec Element(it).elIndex
    parent.childList[i] = it
  parent.childList.setLen(parent.childList.len - 1)
  parent.invalidateCollections()
  node.invalidateCollections()
  if parent of Element:
    Element(parent).invalidate()
  node.parentNode = nil
  node.index = -1
  if element != nil:
    element.elIndex = -1
    if element.document != nil:
      if element of HTMLStyleElement or element of HTMLLinkElement:
        element.document.applyAuthorSheets()
      element.applyStyleDependencies(DependencyInfo.default)
  #TODO assigned, shadow root, shadow root again, custom nodes, registered
  # observers
  #TODO not suppress observers => queue tree mutation record

proc remove*(node: Node) {.jsfunc.} =
  if node.parentNode != nil:
    node.remove(suppressObservers = false)

proc adopt(document: Document; node: Node) =
  let oldDocument = node.document
  if node.parentNode != nil:
    remove(node)
  if oldDocument != document:
    #TODO shadow root
    for desc in node.descendantsIncl:
      desc.internalDocument = document
      if desc of Element:
        let desc = Element(desc)
        if desc.cachedAttributes != nil:
          for attr in desc.cachedAttributes.attrlist:
            attr.internalDocument = document
    #TODO custom elements
    #..adopting steps

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
      input.value = input.attr(satValue)
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
    textarea.value = textarea.childTextContent()
    textarea.invalidate()
  else: discard

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
  form.invalidateCollections()

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

proc elementInsertionSteps(element: Element) =
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
  elif element of FormAssociatedElement:
    let element = FormAssociatedElement(element)
    if element.parserInserted:
      return
    element.resetFormOwner()

func isValidParent(node: Node): bool =
  return node of Element or node of Document or node of DocumentFragment

func isValidChild(node: Node): bool =
  return node.isValidParent or node of DocumentType or node of CharacterData

func checkParentValidity(parent: Node): Err[DOMException] =
  if parent.isValidParent():
    return ok()
  const msg = "Parent must be a document, a document fragment, or an element."
  return errDOMException(msg, "HierarchyRequestError")

# WARNING the ordering of the arguments in the standard is whack so this
# doesn't match that
func preInsertionValidity*(parent, node, before: Node): Err[DOMException] =
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
  parent.childList.setLen(parent.childList.len + 1)
  let element = if node of Element: Element(node) else: nil
  if before == nil:
    node.index = parent.childList.high
  else:
    node.index = before.index
    if element != nil and before of Element:
      element.elIndex = Element(before).elIndex
    for i in countdown(parent.childList.high - 1, node.index):
      let it = parent.childList[i]
      let j = i + 1
      it.index = j
      if element != nil and it of Element:
        let it = Element(it)
        if element.elIndex == -1:
          element.elIndex = it.elIndex
        inc it.elIndex
      parent.childList[j] = it
  if element != nil and element.elIndex == -1:
    element.elIndex = 0
    let last = parent.lastElementChild
    if last != nil:
      element.elIndex = last.elIndex + 1
  parent.childList[node.index] = node
  node.parentNode = parent
  node.invalidateCollections()
  parent.invalidateCollections()
  if node.document != nil and (node of HTMLStyleElement or
      node of HTMLLinkElement):
    node.document.applyAuthorSheets()
  for el in node.elementsIncl:
    #TODO shadow root
    el.elementInsertionSteps()

# WARNING ditto
proc insert*(parent, node, before: Node; suppressObservers = false) =
  var nodes = if node of DocumentFragment:
    node.childList
  else:
    @[node]
  let count = nodes.len
  if count == 0:
    return
  if node of DocumentFragment:
    for i in countdown(node.childList.high, 0):
      node.childList[i].remove(true)
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

proc removeChild(parent, node: Node): DOMResult[Node] {.jsfunc.} =
  if node.parentNode != parent:
    return errDOMException("Node is not a child of parent", "NotFoundError")
  node.remove()
  return ok(node)

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
  var removedNodes = parent.childList # copy
  for child in removedNodes:
    child.remove(true)
  assert parent != node
  if node != nil:
    if node of DocumentFragment:
      var addedNodes = node.childList # copy
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

proc toNode(ctx: JSContext; nodes: openArray[JSValue]; document: Document):
    Node =
  var ns: seq[Node] = @[]
  for it in nodes:
    var node: Node
    if ctx.fromJS(it, node).isSome:
      ns.add(node)
    else:
      var s: string
      if ctx.fromJS(it, s).isSome:
        ns.add(ctx.newText(s))
  if ns.len == 1:
    return ns[0]
  let fragment = document.newDocumentFragment()
  for node in ns:
    fragment.append(node)
  return fragment

proc prependImpl(ctx: JSContext; parent: Node; nodes: openArray[JSValue]):
    Err[DOMException] =
  let node = ctx.toNode(nodes, parent.document)
  discard ?parent.insertBefore(node, option(parent.firstChild))
  ok()

proc prepend(ctx: JSContext; this: Element; nodes: varargs[JSValue]):
    Err[DOMException] {.jsfunc.} =
  return ctx.prependImpl(this, nodes)

proc prepend(ctx: JSContext; this: Document; nodes: varargs[JSValue]):
    Err[DOMException] {.jsfunc.} =
  return ctx.prependImpl(this, nodes)

proc prepend(ctx: JSContext; this: DocumentFragment; nodes: varargs[JSValue]):
    Err[DOMException] {.jsfunc.} =
  return ctx.prependImpl(this, nodes)

proc appendImpl(ctx: JSContext; parent: Node; nodes: openArray[JSValue]):
    Err[DOMException] =
  let node = ctx.toNode(nodes, parent.document)
  discard ?parent.appendChild(node)
  ok()

proc append(ctx: JSContext; this: Element; nodes: varargs[JSValue]):
    Err[DOMException] {.jsfunc.} =
  return ctx.appendImpl(this, nodes)

proc append(ctx: JSContext; this: Document; nodes: varargs[JSValue]):
    Err[DOMException] {.jsfunc.} =
  return ctx.appendImpl(this, nodes)

proc append(ctx: JSContext; this: DocumentFragment; nodes: varargs[JSValue]):
    Err[DOMException] {.jsfunc.} =
  return ctx.appendImpl(this, nodes)

proc replaceChildrenImpl(ctx: JSContext; parent: Node;
    nodes: openArray[JSValue]): Err[DOMException] =
  let node = ctx.toNode(nodes, parent.document)
  ?parent.preInsertionValidity(node, nil)
  parent.replaceAll(node)
  ok()

proc replaceChildren(ctx: JSContext; this: Element; nodes: varargs[JSValue]):
    Err[DOMException] {.jsfunc.} =
  return ctx.replaceChildrenImpl(this, nodes)

proc replaceChildren(ctx: JSContext; this: Document; nodes: varargs[JSValue]):
    Err[DOMException] {.jsfunc.} =
  return ctx.replaceChildrenImpl(this, nodes)

proc replaceChildren(ctx: JSContext; this: DocumentFragment;
    nodes: varargs[JSValue]): Err[DOMException] {.jsfunc.} =
  return ctx.replaceChildrenImpl(this, nodes)

proc createTextNode(document: Document; data: sink string): Text {.jsfunc.} =
  return newText(document, data)

proc setNodeValue(ctx: JSContext; node: Node; data: JSValue): Err[void]
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
    Attr(node).value(move(res))
  return ok()

proc setTextContent(ctx: JSContext; node: Node; data: JSValue): Err[void]
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

proc reset*(form: HTMLFormElement) =
  for control in form.controls:
    control.resetElement()
    control.invalidate()

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
  if document.contentType == "text/html" and document.body == nil:
    element.document.renderBlockingElements.add(element)

proc markAsReady(element: HTMLScriptElement; res: ScriptResult) =
  element.scriptResult = res
  if element.onReady != nil:
    element.onReady()
    element.onReady = nil
  element.delayingTheLoadEvent = false

type OnCompleteProc = proc(element: HTMLScriptElement, res: ScriptResult)

proc fetchClassicScript(element: HTMLScriptElement; url: URL;
    options: ScriptOptions; cors: CORSAttribute; cs: Charset;
    onComplete: OnCompleteProc) =
  let window = element.document.window
  if not element.scriptingEnabled:
    element.onComplete(ScriptResult(t: srtNull))
    return
  let request = createPotentialCORSRequest(url, rdScript, cors)
  request.client = some(window.settings)
  #TODO make this non-blocking somehow
  let response = window.loader.doRequest(request.request)
  if response.res != 0:
    element.onComplete(ScriptResult(t: srtNull))
    return
  response.resume()
  let s = response.body.recvAll()
  let cs = if cs == CHARSET_UNKNOWN: CHARSET_UTF_8 else: cs
  let source = s.decodeAll(cs)
  response.body.sclose()
  let script = window.jsctx.newClassicScript(source, url, options, false)
  element.onComplete(script)

#TODO settings object
proc fetchDescendantsAndLink(element: HTMLScriptElement; script: Script;
    destination: RequestDestination; onComplete: OnCompleteProc)
proc fetchSingleModule(element: HTMLScriptElement; url: URL;
    destination: RequestDestination; options: ScriptOptions;
    referrer: URL; isTopLevel: bool; onComplete: OnCompleteProc)

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
  if JS_ResolveModule(ctx, script.record) < 0:
    window.logException(script.baseURL)
    return
  ctx.setImportMeta(script.record, true)
  let res = JS_EvalFunction(ctx, script.record)
  if JS_IsException(res):
    window.logException(script.baseURL)
    return
  var p: Promise[JSValue]
  if ctx.fromJS(res, p).isSome:
    p.then(proc(res: JSValue) =
      if JS_IsException(res):
        window.logException(script.baseURL)
    )
  JS_FreeValue(ctx, res)

#TODO settings object
proc fetchSingleModule(element: HTMLScriptElement; url: URL;
    destination: RequestDestination; options: ScriptOptions,
    referrer: URL; isTopLevel: bool; onComplete: OnCompleteProc) =
  let moduleType = "javascript"
  #TODO moduleRequest
  let window = element.document.window
  let settings = window.settings
  let i = settings.moduleMap.find(url, moduleType)
  if i != -1:
    if settings.moduleMap[i].value.t == srtFetching:
      #TODO await value
      assert false
    element.onComplete(settings.moduleMap[i].value)
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
  let ctx = window.jsctx
  let v = ctx.toJS(request)
  let p = window.fetchImpl(v)
  JS_FreeValue(ctx, v)
  if p.isSome:
    p.get.then(proc(res: JSResult[Response]) =
      if res.isNone:
        let res = ScriptResult(t: srtNull)
        settings.moduleMap.set(url, moduleType, res, ctx)
        element.onComplete(res)
        return
      let res = res.get
      let contentType = res.getContentType()
      let referrerPolicy = res.getReferrerPolicy()
      res.text().then(proc(s: JSResult[string]) =
        if s.isNone:
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
            settings.moduleMap.set(url, moduleType, res, ctx)
            element.onComplete(res)
        else:
          #TODO non-JS modules
          discard
      )
    )

proc execute*(element: HTMLScriptElement) =
  let document = element.document
  if document != element.preparationTimeDocument:
    return
  let i = document.renderBlockingElements.find(element)
  if i != -1:
    document.renderBlockingElements.delete(i)
  #TODO this should work eventually (when module & importmap are implemented)
  #assert element.scriptResult != nil
  if element.scriptResult == nil:
    return
  if element.scriptResult.t == srtNull:
    #TODO fire error event
    return
  let needsInc = element.external or element.ctype == stModule
  if needsInc:
    inc document.ignoreDestructiveWrites
  case element.ctype
  of stClassic:
    let oldCurrentScript = document.currentScript
    #TODO not if shadow root
    document.currentScript = element
    let window = document.window
    if window != nil and window.jsctx != nil:
      let script = element.scriptResult.script
      let ctx = window.jsctx
      if JS_IsException(script.record):
        window.logException(script.baseURL)
      else:
        let ret = ctx.evalFunction(script.record)
        if JS_IsException(ret):
          window.logException(script.baseURL)
        JS_FreeValue(ctx, ret)
    document.currentScript = oldCurrentScript
  else: discard #TODO
  if needsInc:
    dec document.ignoreDestructiveWrites

# https://html.spec.whatwg.org/multipage/scripting.html#prepare-the-script-element
proc prepare*(element: HTMLScriptElement) =
  if element.alreadyStarted:
    return
  let parserDocument = element.parserDocument
  element.parserDocument = nil
  if parserDocument != nil and not element.attrb(satAsync):
    element.forceAsync = true
  let sourceText = element.childTextContent
  if not element.attrb(satSrc) and sourceText == "":
    return
  if not element.isConnected:
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
  if parserDocument != nil and
      parserDocument != element.preparationTimeDocument:
    return
  if not element.scriptingEnabled:
    return
  if element.attrb(satNomodule) and element.ctype == stClassic:
    return
  #TODO content security policy
  if element.ctype == stClassic and element.attrb(satEvent) and
      element.attrb(satFor):
    let f = element.attr(satFor).strip(chars = AsciiWhitespace)
    let event = element.attr(satEvent).strip(chars = AsciiWhitespace)
    if not f.equalsIgnoreCase("window"):
      return
    if not event.equalsIgnoreCase("onload") and
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
  if element.attrb(satSrc):
    if element.ctype == stImportMap:
      #TODO fire error event
      return
    let src = element.attr(satSrc)
    if src == "":
      #TODO fire error event
      return
    element.external = true
    let url = element.document.parseURL(src)
    if url.isNone:
      #TODO fire error event
      return
    if element.renderBlocking:
      element.blockRendering()
    element.delayingTheLoadEvent = true
    if element in element.document.renderBlockingElements:
      options.renderBlocking = true
    if element.ctype == stClassic:
      element.fetchClassicScript(url.get, options, classicCORS, encoding,
        markAsReady)
    else: # stModule
      element.fetchExternalModuleGraph(url.get, options, markAsReady)
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
    if element.attrb(satAsync):
      prepdoc.scriptsToExecSoon.add(element)
      element.onReady = (proc() =
        element.execute()
        let i = prepdoc.scriptsToExecSoon.find(element)
        element.preparationTimeDocument.scriptsToExecSoon.delete(i)
      )
    elif element.parserDocument == nil:
      prepdoc.scriptsToExecInOrder.addFirst(element)
      element.onReady = (proc() =
        if prepdoc.scriptsToExecInOrder.len > 0 and
            prepdoc.scriptsToExecInOrder[0] != element:
          while prepdoc.scriptsToExecInOrder.len > 0:
            let script = prepdoc.scriptsToExecInOrder[0]
            if script.scriptResult == nil:
              break
            script.execute()
            prepdoc.scriptsToExecInOrder.shrink(1)
      )
    elif element.ctype == stModule or element.attrb(satDefer):
      element.parserDocument.scriptsToExecOnLoad.addFirst(element)
      element.onReady = (proc() =
        element.readyForParserExec = true
      )
    else:
      element.parserDocument.parserBlockingScript = element
      element.blockRendering()
      element.onReady = (proc() =
        element.readyForParserExec = true
      )
  else:
    #TODO if stClassic, parserDocument != nil, parserDocument has a style sheet
    # that is blocking scripts, either the parser is an XML parser or a HTML
    # parser with a script level <= 1
    element.execute()

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
    namespace: CAtom; qname0 = JS_NULL; doctype = none(DocumentType)):
    DOMResult[XMLDocument] {.jsfunc.} =
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
  of satNamespaceHTML: document.contentType = "application/xml+html"
  of satNamespaceSVG: document.contentType = "image/svg+xml"
  else: discard
  return ok(document)

proc createHTMLDocument(implementation: var DOMImplementation;
    title = none(string)): Document {.jsfunc.} =
  let doc = newDocument()
  doc.contentType = "text/html"
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
  of satEvent, satEvents, satSvgevents:
    return ok(newEvent(satUempty.toAtom(), nil))
  else:
    return errDOMException("Event not supported", "NotSupportedError")

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
      x.value = element.value
      #TODO dirty value flag
      x.setChecked(element.checked)
      #TODO dirty checkedness flag
    Node(x)
  elif node of Attr:
    let attr = Attr(node)
    let data = attr.data
    let x = Attr(
      ownerElement: AttrDummyElement(
        internalDocument: attr.ownerElement.document,
        index: -1,
        elIndex: -1,
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
    x.isxml = document.isxml
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

func equals(a, b: AttrData): bool =
  return a.qualifiedName == b.qualifiedName and
    a.namespace == b.namespace and
    a.value == b.value

func isEqualNode(node, other: Node): bool {.jsfunc.} =
  if node.childList.len != other.childList.len:
    return false
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
    if node.namespace != other.namespace or node.prefix != other.prefix or
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
  for i, child in node.childList.mypairs:
    if not child.isEqualNode(other.childList[i]):
      return false
  true

func isSameNode(node, other: Node): bool {.jsfunc.} =
  return node == other

proc querySelectorImpl(node: Node; q: string): DOMResult[Element] =
  let selectors = parseSelectors(q)
  if selectors.len == 0:
    return errDOMException("Invalid selector: " & q, "SyntaxError")
  for element in node.elements:
    if element.matchesImpl(selectors):
      return ok(element)
  return ok(nil)

proc querySelector(this: Element; q: string): DOMResult[Element] {.jsfunc.} =
  return this.querySelectorImpl(q)

proc querySelector(this: Document; q: string): DOMResult[Element] {.jsfunc.} =
  return this.querySelectorImpl(q)

proc querySelector(this: DocumentFragment; q: string): DOMResult[Element]
    {.jsfunc.} =
  return this.querySelectorImpl(q)

proc querySelectorAllImpl(node: Node; q: string): DOMResult[NodeList] =
  let selectors = parseSelectors(q)
  if selectors.len == 0:
    return errDOMException("Invalid selector: " & q, "SyntaxError")
  return ok(node.newNodeList(
    match = func(node: Node): bool =
      if node of Element:
        {.cast(noSideEffect).}:
          return Element(node).matchesImpl(selectors),
    islive = false,
    childonly = false
  ))

proc querySelectorAll(this: Element; q: string): DOMResult[NodeList]
    {.jsfunc.} =
  return this.querySelectorAllImpl(q)

proc querySelectorAll(this: Document; q: string): DOMResult[NodeList]
    {.jsfunc.} =
  return this.querySelectorAllImpl(q)

proc querySelectorAll(this: DocumentFragment; q: string): DOMResult[NodeList]
    {.jsfunc.} =
  return this.querySelectorAllImpl(q)

func getReflectFunctions(tags: set[TagType]): seq[TabGetSet] =
  result = @[]
  for tag in tags:
    if tag in TagReflectMap:
      for i in TagReflectMap[tag]:
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

proc getContext*(jctx: JSContext; this: HTMLCanvasElement; contextId: string;
    options = JS_UNDEFINED): RenderingContext {.jsfunc.} =
  if contextId == "2d":
    if this.ctx2d == nil:
      create2DContext(jctx, this, options)
    return this.ctx2d
  return nil

# Note: the standard says quality should be converted in a strange way for
# backwards compat, but I don't care.
proc toBlob(ctx: JSContext; this: HTMLCanvasElement; callback: JSValue;
    contentType = "image/png"; quality = none(float64)) {.jsfunc.} =
  let contentType = contentType.toLowerAscii()
  if not contentType.startsWith("image/") or this.bitmap.cacheId == 0:
    return
  let url0 = newURL("img-codec+" & contentType.after('/') & ":encode")
  if url0.isNone:
    return
  let url = url0.get
  let headers = newHeaders({
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
    if res.isNone:
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
    if res.isNone:
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
      let res = JS_Call(ctx, callback, JS_UNDEFINED, 1, jsBlob.toJSValueArray())
      if JS_IsException(res):
        window.console.error("Exception in canvas toBlob:",
          ctx.getExceptionMsg())
      else:
        JS_FreeValue(ctx, res)
      JS_FreeValue(ctx, callback)
    )
  )

# https://w3c.github.io/DOM-Parsing/#dfn-fragment-parsing-algorithm
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

# https://w3c.github.io/DOM-Parsing/#dom-element-insertadjacenthtml
proc insertAdjacentHTML(this: Element; position, text: string):
    Err[DOMException] {.jsfunc.} =
  let pos0 = parseEnumNoCase[InsertAdjacentPosition](position)
  if pos0.isNone:
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

proc registerElements(ctx: JSContext; nodeCID: JSClassID) =
  let elementCID = ctx.registerType(Element, parent = nodeCID)
  const extraGetSet = getElementReflectFunctions()
  let htmlElementCID = ctx.registerType(HTMLElement, parent = elementCID,
    hasExtraGetSet = true, extraGetSet = extraGetSet)
  template register(t: typed; tags: set[TagType]) =
    const extraGetSet = getReflectFunctions(tags)
    ctx.registerType(t, parent = htmlElementCID, hasExtraGetSet = true,
      extraGetSet = extraGetSet)
  template register(t: typed; tag: TagType) =
    register(t, {tag})
  register(HTMLInputElement, TAG_INPUT)
  register(HTMLAnchorElement, TAG_A)
  register(HTMLSelectElement, TAG_SELECT)
  register(HTMLSpanElement, TAG_SPAN)
  register(HTMLOptGroupElement, TAG_OPTGROUP)
  register(HTMLOptionElement, TAG_OPTION)
  register(HTMLHeadingElement, {TAG_H1, TAG_H2, TAG_H3, TAG_H4, TAG_H5, TAG_H6})
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
  register(HTMLTableSectionElement, {TAG_TBODY, TAG_THEAD, TAG_TFOOT})
  register(HTMLMetaElement, TAG_META)
  let svgElementCID = ctx.registerType(SVGElement, parent = elementCID)
  ctx.registerType(SVGSVGElement, parent = svgElementCID)

proc addDOMModule*(ctx: JSContext) =
  let eventTargetCID = ctx.getClass("EventTarget")
  let nodeCID = ctx.registerType(Node, parent = eventTargetCID)
  ctx.defineConsts(nodeCID, NodeType)
  let nodeListCID = ctx.registerType(NodeList)
  let htmlCollectionCID = ctx.registerType(HTMLCollection)
  ctx.registerType(HTMLAllCollection, ishtmldda = true)
  ctx.registerType(HTMLFormControlsCollection, parent = htmlCollectionCID)
  ctx.registerType(HTMLOptionsCollection, parent = htmlCollectionCID)
  ctx.registerType(RadioNodeList, parent = nodeListCID)
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
  ctx.registerType(CanvasRenderingContext2D)
  ctx.registerType(TextMetrics)
  ctx.registerType(CSSStyleDeclaration)
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
  ctx.definePropertyCW(jsWindow, "Image", imageFun)
  ctx.definePropertyCW(jsWindow, "Option", optionFun)
  ctx.definePropertyCW(jsWindow, "HTMLDocument",
    JS_GetPropertyStr(ctx, jsWindow, "Document"))
  JS_FreeValue(ctx, jsWindow)

# Forward declaration hack
isDefaultPassiveImpl = func(target: EventTarget): bool =
  if target of Window:
    return true
  if not (target of Node):
    return false
  let node = Node(target)
  return EventTarget(node.document) == target or
    EventTarget(node.document.documentElement) == target or
    EventTarget(node.document.body) == target

getParentImpl = proc(ctx: JSContext; eventTarget: EventTarget; event: Event):
    EventTarget =
  if eventTarget of Node:
    if eventTarget of Document:
      if event.ctype == satLoad.toAtom():
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
