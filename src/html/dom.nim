import std/algorithm
import std/deques
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
import css/sheet
import html/catom
import html/domexception
import html/enums
import html/event
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
    dtHover, dtChecked, dtFocus

  Location = ref object
    window: Window

  CachedURLImage = ref object
    expiry: int64
    loading: bool
    shared: seq[HTMLImageElement]
    bmp: NetworkBitmap

  Window* = ref object of EventTarget
    attrs*: WindowAttributes
    internalConsole*: Console
    navigator* {.jsget.}: Navigator
    screen* {.jsget.}: Screen
    history* {.jsget.}: History
    localStorage* {.jsget.}: Storage
    sessionStorage* {.jsget.}: Storage
    settings*: EnvironmentSettings
    loader*: FileLoader
    location* {.jsget.}: Location
    jsrt*: JSRuntime
    jsctx*: JSContext
    document* {.jsufget.}: Document
    timeouts*: TimeoutState
    navigate*: proc(url: URL)
    importMapsAllowed*: bool
    factory*: CAtomFactory
    pendingResources*: seq[EmptyPromise]
    imageURLCache: Table[string, CachedURLImage]
    images*: bool
    styling*: bool
    # ID of the next image
    imageId: int
    # list of streams that must be closed for canvas rendering on load
    pendingCanvasCtls*: seq[CanvasRenderingContext2D]
    urandom*: PosixStream
    imageTypes*: Table[string, string]

  # Navigator stuff
  Navigator* = object
    plugins: PluginArray

  PluginArray* = object

  MimeTypeArray* = object

  Screen* = object

  History* = object

  Storage* = object
    map*: seq[tuple[key, value: string]]

  NamedNodeMap = ref object
    element: Element
    attrlist: seq[Attr]

  Collection = ref object of RootObj
    islive: bool
    childonly: bool
    root: Node
    match: proc(node: Node): bool {.noSideEffect.}
    snapshot: seq[Node]
    livelen: int

  NodeList = ref object of Collection

  HTMLCollection = ref object of Collection

  HTMLFormControlsCollection = ref object of HTMLCollection

  HTMLOptionsCollection = ref object of HTMLCollection

  RadioNodeList = ref object of NodeList

  HTMLAllCollection = ref object of Collection

  DOMTokenList = ref object
    toks*: seq[CAtom]
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
    factory*: CAtomFactory
    charset*: Charset
    window* {.jsget: "defaultView".}: Window
    url* {.jsget: "URL".}: URL
    mode*: QuirksMode
    currentScript: HTMLScriptElement
    isxml*: bool
    implementation {.jsget.}: DOMImplementation
    origin: Origin
    readyState* {.jsget.}: DocumentReadyState
    # document.write
    ignoreDestructiveWrites: int
    throwOnDynamicMarkupInsertion: int
    activeParserWasAborted: bool
    writeBuffers*: seq[DocumentWriteBuffer]

    scriptsToExecSoon*: seq[HTMLScriptElement]
    scriptsToExecInOrder*: Deque[HTMLScriptElement]
    scriptsToExecOnLoad*: Deque[HTMLScriptElement]
    parserBlockingScript*: HTMLScriptElement

    parserCannotChangeModeFlag*: bool
    internalFocus: Element
    contentType* {.jsget.}: string
    renderBlockingElements: seq[Element]

    invalidCollections: HashSet[pointer] # pointers to Collection objects
    invalid*: bool # whether the document must be rendered again

    cachedAll: HTMLAllCollection
    cachedSheets: seq[CSSStylesheet]
    cachedSheetsInvalid*: bool
    cachedForms: HTMLCollection
    parser*: RootRef

  CharacterData* = ref object of Node
    data* {.jsget.}: string

  Text* = ref object of CharacterData

  Comment* = ref object of CharacterData

  CDATASection = ref object of CharacterData

  ProcessingInstruction = ref object of CharacterData
    target {.jsget.}: string

  DocumentFragment* = ref object of Node
    host*: Element

  DocumentType* = ref object of Node
    name*: string
    publicId*: string
    systemId*: string

  AttrData* = object
    qualifiedName*: CAtom
    localName*: CAtom
    prefix*: CAtom
    namespace*: CAtom
    value*: string

  Element* = ref object of Node
    namespace*: Namespace
    namespacePrefix*: NamespacePrefix
    internalHover: bool
    invalid*: bool
    # The owner StyledNode is marked as invalid when one of these no longer
    # matches the DOM value.
    invalidDeps*: set[DependencyType]
    localName* {.jsget.}: CAtom
    id* {.jsget.}: CAtom
    name {.jsget.}: CAtom
    classList* {.jsget.}: DOMTokenList
    attrs*: seq[AttrData] # sorted by int(qualifiedName)
    cachedAttributes: NamedNodeMap
    cachedStyle*: CSSStyleDeclaration

  AttrDummyElement = ref object of Element

  CSSStyleDeclaration* = ref object
    decls*: seq[CSSDeclaration]
    element: Element

  HTMLElement* = ref object of Element
    dataset {.jsget.}: DOMStringMap

  FormAssociatedElement* = ref object of HTMLElement
    form*: HTMLFormElement
    parserInserted*: bool

  HTMLInputElement* = ref object of FormAssociatedElement
    inputType*: InputType
    value* {.jsget.}: string
    internalChecked {.jsget: "checked".}: bool
    xcoord*: int
    ycoord*: int
    file*: WebFile

  HTMLAnchorElement* = ref object of HTMLElement
    relList {.jsget.}: DOMTokenList

  HTMLSelectElement* = ref object of FormAssociatedElement
    cachedOptions: HTMLOptionsCollection
    cachedSelectedOptions: HTMLCollection

  HTMLSpanElement* = ref object of HTMLElement

  HTMLOptGroupElement* = ref object of HTMLElement

  HTMLOptionElement* = ref object of HTMLElement
    selected*: bool

  HTMLHeadingElement* = ref object of HTMLElement

  HTMLBRElement* = ref object of HTMLElement

  HTMLMenuElement* = ref object of HTMLElement

  HTMLUListElement* = ref object of HTMLElement

  HTMLOListElement* = ref object of HTMLElement

  HTMLLIElement* = ref object of HTMLElement
    value* {.jsget.}: Option[int32]

  HTMLStyleElement* = ref object of HTMLElement
    sheet: CSSStylesheet

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
    content*: DocumentFragment

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
    ctype*: ButtonType
    value* {.jsget, jsset.}: string

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

jsDestructor(Navigator)
jsDestructor(PluginArray)
jsDestructor(MimeTypeArray)
jsDestructor(Screen)
jsDestructor(History)
jsDestructor(Storage)

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
jsDestructor(Node)
jsDestructor(NodeList)
jsDestructor(HTMLCollection)
jsDestructor(HTMLFormControlsCollection)
jsDestructor(RadioNodeList)
jsDestructor(HTMLAllCollection)
jsDestructor(HTMLOptionsCollection)
jsDestructor(Location)
jsDestructor(Document)
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
func attr*(element: Element; s: StaticAtom): string
func attrb*(element: Element; s: CAtom): bool
proc baseURL*(document: Document): URL
proc attr*(element: Element; name: CAtom; value: string)
proc attr*(element: Element; name: StaticAtom; value: string)
proc delAttr(element: Element; i: int; keep = false)
proc getImageId(window: Window): int
proc parseColor(element: Element; s: string): ARGBColor
proc reflectAttr(element: Element; name: CAtom; value: Option[string])
proc setInvalid*(element: Element)
func value*(option: HTMLOptionElement): string

# Forward declaration hacks
# set in css/cascade
var appliesImpl*: proc(mqlist: MediaQueryList; window: Window): bool
  {.nimcall, noSideEffect.}
# set in css/match
var querySelectorAllImpl*: proc (node: Node; q: string): seq[Element]
  {.nimcall.} = nil
var querySelectorImpl*: proc (node: Node; q: string): Element
  {.nimcall.} = nil
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
  var pipefd: array[2, cint]
  if pipe(pipefd) == -1:
    return
  let window = jctx.getWindow()
  let imageId = target.bitmap.imageId
  let loader = window.loader
  loader.passFd("canvas-ctl-" & $imageId, pipefd[0])
  discard close(pipefd[0])
  let ps = newPosixStream(pipefd[1])
  let ctlreq = newRequest(newURL("stream:canvas-ctl-" & $imageId).get)
  let ctlres = loader.doRequest(ctlreq)
  doAssert ctlres.res == 0
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
    ctlres.resume()
    ctlres.close()
    return
  ctlres.resume()
  ctlres.close()
  response.resume()
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
    funcname: string
    tags: set[TagType]
    case t: ReflectType
    of rtLong:
      i: int32
    of rtUlong, rtUlongGz:
      u: uint32
    of rtFunction:
      ctype: StaticAtom
    else: discard

func attrType0(s: static string): StaticAtom {.compileTime.} =
  return strictParseEnum[StaticAtom](s).get

template toset(ts: openArray[TagType]): set[TagType] =
  var tags: system.set[TagType]
  for tag in ts:
    tags.incl(tag)
  tags

func makes(name: static string; ts: set[TagType]): ReflectEntry =
  const attrname = attrType0(name)
  ReflectEntry(
    attrname: attrname,
    funcname: name,
    t: rtStr,
    tags: ts
  )

func makes(attrname, funcname: static string; ts: set[TagType]):
    ReflectEntry =
  const attrname = attrType0(attrname)
  ReflectEntry(
    attrname: attrname,
    funcname: funcname,
    t: rtStr,
    tags: ts
  )

func makes(name: static string; ts: varargs[TagType]): ReflectEntry =
  makes(name, toset(ts))

func makes(attrname, funcname: static string; ts: varargs[TagType]):
    ReflectEntry =
  makes(attrname, funcname, toset(ts))

func makeb(attrname, funcname: static string; ts: varargs[TagType]):
    ReflectEntry =
  const attrname = attrType0(attrname)
  ReflectEntry(
    attrname: attrname,
    funcname: funcname,
    t: rtBool,
    tags: toset(ts)
  )

func makeb(name: static string; ts: varargs[TagType]): ReflectEntry =
  makeb(name, name, ts)

func makeul(name: static string; ts: varargs[TagType]; default = 0u32):
    ReflectEntry =
  const attrname = attrType0(name)
  ReflectEntry(
    attrname: attrname,
    funcname: name,
    t: rtUlong,
    tags: toset(ts),
    u: default
  )

func makeulgz(name: static string; ts: varargs[TagType]; default = 0u32):
    ReflectEntry =
  const attrname = attrType0(name)
  ReflectEntry(
    attrname: attrname,
    funcname: name,
    t: rtUlongGz,
    tags: toset(ts),
    u: default
  )

func makef(name: static string; ts: set[TagType]; ctype: static string): ReflectEntry =
  const attrname = attrType0(name)
  ReflectEntry(
    attrname: attrname,
    funcname: name,
    t: rtFunction,
    tags: ts,
    ctype: attrType0(ctype)
  )

const ReflectTable0 = [
  # non-global attributes
  makes("target", TAG_A, TAG_AREA, TAG_LABEL, TAG_LINK),
  makes("href", TAG_LINK),
  makeb("required", TAG_INPUT, TAG_SELECT, TAG_TEXTAREA),
  makeb("novalidate", "noValidate", TAG_FORM),
  makes("rel", TAG_A, TAG_LINK, TAG_LABEL),
  makes("for", "htmlFor", TAG_LABEL),
  makeul("cols", TAG_TEXTAREA, 20u32),
  makeul("rows", TAG_TEXTAREA, 1u32),
# <SELECT>:
#> For historical reasons, the default value of the size IDL attribute does
#> not return the actual size used, which, in the absence of the size content
#> attribute, is either 1 or 4 depending on the presence of the multiple
#> attribute.
  makeulgz("size", TAG_SELECT, 0u32),
  makeulgz("size", TAG_INPUT, 20u32),
  makeul("width", TAG_CANVAS, 300u32),
  makeul("height", TAG_CANVAS, 150u32),
  makes("alt", TAG_IMG),
  makes("src", TAG_IMG, TAG_SCRIPT),
  makes("srcset", TAG_IMG),
  makes("sizes", TAG_IMG),
  #TODO can we add crossOrigin here?
  makes("usemap", "useMap", TAG_IMG),
  makeb("ismap", "isMap", TAG_IMG),
  makeb("disabled", TAG_LINK),
  # "super-global" attributes
  makes("slot", AllTagTypes),
  makes("class", "className", AllTagTypes),
  makef("onclick", AllTagTypes, "click"),
]

func document*(node: Node): Document =
  if node of Document:
    return Document(node)
  return node.internalDocument

proc toAtom*(window: Window; atom: StaticAtom): CAtom =
  return window.factory.toAtom(atom)

proc toAtom*(window: Window; s: string): CAtom =
  return window.factory.toAtom(s)

proc toStr*(window: Window; atom: CAtom): string =
  return window.factory.toStr(atom)

proc toAtom*(document: Document; s: string): CAtom =
  return document.factory.toAtom(s)

proc toAtom*(document: Document; at: StaticAtom): CAtom =
  return document.factory.toAtom(at)

proc toStr(document: Document; atom: CAtom): string =
  return document.factory.toStr(atom)

proc toTagType*(document: Document; atom: CAtom): TagType =
  return document.factory.toTagType(atom)

proc toStaticAtom(document: Document; atom: CAtom): StaticAtom =
  return document.factory.toStaticAtom(atom)

proc toAtom*(document: Document; tagType: TagType): CAtom =
  return document.factory.toAtom(tagType)

proc toAtom(document: Document; namespace: Namespace): CAtom =
  #TODO optimize
  assert namespace != NO_NAMESPACE
  return document.toAtom($namespace)

proc toAtom(document: Document; prefix: NamespacePrefix): CAtom =
  #TODO optimize
  assert prefix != NO_PREFIX
  return document.toAtom($prefix)

func tagTypeNoNS(element: Element): TagType =
  return element.document.toTagType(element.localName)

func tagType*(element: Element): TagType =
  if element.namespace != Namespace.HTML:
    return TAG_UNKNOWN
  return element.tagTypeNoNS

func findAttr(element: Element; qualifiedName: CAtom): int =
  for i, attr in element.attrs.mypairs:
    if attr.qualifiedName == qualifiedName:
      return i
  return -1

func findAttr(element: Element; qualifiedName: StaticAtom): int =
  return element.findAttr(element.document.toAtom(qualifiedName))

func findAttrNS(element: Element; namespace, qualifiedName: CAtom): int =
  for i, attr in element.attrs.mypairs:
    if attr.namespace == namespace and attr.qualifiedName == qualifiedName:
      return i
  return -1

func escapeText(s: string; attribute_mode = false): string =
  var nbsp_mode = false
  var nbsp_prev: char
  for c in s:
    if nbsp_mode:
      if c == char(0xA0):
        result &= "&nbsp;"
      else:
        result &= nbsp_prev & c
      nbsp_mode = false
    elif c == '&':
      result &= "&amp;"
    elif c == char(0xC2):
      nbsp_mode = true
      nbsp_prev = c
    elif attribute_mode and c == '"':
      result &= "&quot;"
    elif not attribute_mode and c == '<':
      result &= "&lt;"
    elif not attribute_mode and c == '>':
      result &= "&gt;"
    else:
      result &= c

when defined(debug):
  func localNameStr*(element: Element): string =
    return element.document.toStr(element.localName)

  func `$`*(node: Node): string =
    if node == nil:
      return "null"
    if node of Element:
      let element = Element(node)
      result = "<" & element.localNameStr
      for attr in element.attrs:
        let k = element.document.toStr(attr.localName)
        result &= ' ' & k & "=\"" & attr.value.escapeText(true) & "\""
      result &= ">\n"
      for node in element.childList:
        for line in ($node).split('\n'):
          result &= "\t" & line & "\n"
      result &= "</" & element.localNameStr & ">"
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

iterator inputs(form: HTMLFormElement): HTMLInputElement {.inline.} =
  for control in form.controls:
    if control of HTMLInputElement:
      yield HTMLInputElement(control)

iterator radiogroup(form: HTMLFormElement): HTMLInputElement {.inline.} =
  for input in form.inputs:
    if input.inputType == itRadio:
      yield input

iterator radiogroup(document: Document): HTMLInputElement {.inline.} =
  for input in document.elements(TAG_INPUT):
    let input = HTMLInputElement(input)
    if input.form == nil and input.inputType == itRadio:
      yield input

iterator radiogroup*(input: HTMLInputElement): HTMLInputElement {.inline.} =
  if input.form != nil:
    for input in input.form.radiogroup:
      yield input
  else:
    for input in input.document.radiogroup:
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

func id(collection: Collection): pointer =
  return cast[pointer](collection)

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
      child.liveCollections.add(collection.id)
    collection.root.liveCollections.add(collection.id)

proc refreshCollection(collection: Collection) =
  let document = collection.root.document
  if collection.id in document.invalidCollections:
    for child in collection.snapshot:
      let i = child.liveCollections.find(collection.id)
      assert i != -1
      child.liveCollections.del(i)
    collection.snapshot.setLen(0)
    collection.populateCollection()
    document.invalidCollections.excl(collection.id)

proc finalize0(collection: Collection) =
  if collection.islive:
    for child in collection.snapshot:
      let i = child.liveCollections.find(collection.id)
      assert i != -1
      child.liveCollections.del(i)
    collection.root.document.invalidCollections.excl(collection.id)

proc finalize(collection: HTMLCollection) {.jsfin.} =
  collection.finalize0()

proc finalize(collection: NodeList) {.jsfin.} =
  collection.finalize0()

proc finalize(collection: HTMLFormControlsCollection) {.jsfin.} =
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

type CollectionMatchFun = proc(node: Node): bool {.noSideEffect.}

func newCollection[T: Collection](root: Node; match: CollectionMatchFun;
    islive, childonly: bool): T =
  result = T(
    islive: islive,
    childonly: childonly,
    match: match,
    root: root
  )
  result.populateCollection()

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

template parentNodeChildrenImpl(ctx: JSContext; parentNode: typed) =
  let children = ctx.toJS(newCollection[HTMLCollection](
    root = parentNode,
    match = isElement,
    islive = true,
    childonly = true
  ))
  let this = ctx.toJS(parentNode)
  ctx.definePropertyCW(this, "children", JS_DupValue(ctx, children))
  JS_FreeValue(ctx, this)
  return children

func children(ctx: JSContext; parentNode: Document): JSValue {.jsfget.} =
  parentNodeChildrenImpl(ctx, parentNode)

func children(ctx: JSContext; parentNode: DocumentFragment): JSValue
    {.jsfget.} =
  parentNodeChildrenImpl(ctx, parentNode)

func children(ctx: JSContext; parentNode: Element): JSValue {.jsfget.} =
  parentNodeChildrenImpl(ctx, parentNode)

func childNodes(ctx: JSContext; node: Node): JSValue {.jsfget.} =
  let childNodes = ctx.toJS(newCollection[NodeList](
    root = node,
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
    document.cachedForms = newCollection[HTMLCollection](
      root = document,
      match = isForm,
      islive = true,
      childonly = false
    )
  return document.cachedForms

func cookie(document: Document): string {.jsfget.} =
  return ""

# DOMTokenList
func length(tokenList: DOMTokenList): uint32 {.jsfget.} =
  return uint32(tokenList.toks.len)

proc item(ctx: JSContext; tokenList: DOMTokenList; i: int): JSValue {.jsfunc.} =
  if i < tokenList.toks.len:
    return ctx.toJS(tokenList.toks[i])
  return JS_NULL

func contains*(tokenList: DOMTokenList; a: CAtom): bool =
  return a in tokenList.toks

func contains(tokenList: DOMTokenList; a: StaticAtom): bool =
  return tokenList.element.document.toAtom(a) in tokenList.toks

func jsContains(tokenList: DOMTokenList; s: string): bool
    {.jsfunc: "contains".} =
  return tokenList.element.document.toAtom(s) in tokenList

func `$`(tokenList: DOMTokenList): string {.jsfunc.} =
  var s = ""
  for i, tok in tokenList.toks:
    if i != 0:
      s &= ' '
    s &= tokenList.element.document.toStr(tok)
  return s

proc update(tokenList: DOMTokenList) =
  if not tokenList.element.attrb(tokenList.localName) and
      tokenList.toks.len == 0:
    return
  tokenList.element.attr(tokenList.localName, $tokenList)

func validateDOMToken(ctx: JSContext; document: Document; tok: JSValue):
    DOMResult[CAtom] =
  var res: string
  ?ctx.fromJS(tok, res)
  if res == "":
    return errDOMException("Got an empty string", "SyntaxError")
  if AsciiWhitespace in res:
    return errDOMException("Got a string containing whitespace",
      "InvalidCharacterError")
  return ok(document.toAtom(res))

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
  let localName = tokenList.element.document.toStaticAtom(tokenList.localName)
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
    return ctx.item(this, int(u)).uninitIfNull()
  return JS_UNINITIALIZED

# DOMStringMap
func validateAttributeName(name: string): Err[DOMException] =
  if name.matchNameProduction():
    return ok()
  return errDOMException("Invalid character in attribute name",
    "InvalidCharacterError")

func validateAttributeQName(name: string): Err[DOMException] =
  if name.matchQNameProduction():
    return ok()
  return errDOMException("Invalid character in attribute name",
    "InvalidCharacterError")

proc delete(map: var DOMStringMap; name: string): bool {.jsfunc.} =
  let name = map.target.document.toAtom("data-" & name.camelToKebabCase())
  let i = map.target.findAttr(name)
  if i != -1:
    map.target.delAttr(i)
  return i != -1

func getter(ctx: JSContext; map: var DOMStringMap; name: string): JSValue
    {.jsgetownprop.} =
  let name = map.target.document.toAtom("data-" & name.camelToKebabCase())
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
  ?name.validateAttributeName()
  let aname = map.target.document.toAtom(name)
  map.target.attr(aname, value)
  return ok()

func names(ctx: JSContext; map: var DOMStringMap): JSPropertyEnumList
    {.jspropnames.} =
  var list = newJSPropertyEnumList(ctx, uint32(map.target.attrs.len))
  for attr in map.target.attrs:
    let k = map.target.document.toStr(attr.localName)
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
  let empty = ctx.toAtom("")
  for u in 0 ..< L:
    list.add(u)
    let element = collection.item(u)
    if element.id != CAtomNull and element.id != empty:
      ids.incl(element.id)
    if element.namespace == Namespace.HTML:
      ids.incl(element.name)
  for id in ids:
    list.add(collection.root.document.toStr(id))
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
proc `$`(location: Location): string {.jsuffunc.} =
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

func normalizeAttrQName(element: Element; qualifiedName: string): CAtom =
  if element.namespace == Namespace.HTML and not element.document.isxml:
    return element.document.toAtom(qualifiedName.toLowerAscii())
  return element.document.toAtom(qualifiedName)

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

func findAttr(element: Element; qualifiedName: string): int =
  return element.findAttr(element.normalizeAttrQName(qualifiedName))

func findAttrNS(element: Element; namespace, localName: string): int =
  let namespace = element.document.toAtom(namespace)
  let localName = element.document.toAtom(localName)
  return element.findAttrNS(namespace, localName)

func hasAttribute(element: Element; qualifiedName: string): bool {.jsfunc.} =
  return element.findAttr(qualifiedName) != -1

func hasAttributeNS(element: Element; namespace, localName: string): bool
    {.jsfunc.} =
  return element.findAttrNS(namespace, localName) != -1

func getAttribute(element: Element; qualifiedName: string): Option[string]
    {.jsfunc.} =
  let i = element.findAttr(qualifiedName)
  if i != -1:
    return some(element.attrs[i].value)
  return none(string)

func getAttributeNS(element: Element; namespace, localName: string):
    Option[string] {.jsfunc.} =
  let i = element.findAttrNS(namespace, localName)
  if i != -1:
    return some(element.attrs[i].value)
  return none(string)

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

func getter(ctx: JSContext; map: NamedNodeMap; atom: JSAtom): Opt[Attr]
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
    let name = element.document.toStr(attr.qualifiedName)
    if element.namespace == Namespace.HTML and AsciiUpperAlpha in name:
      continue
    if name in names:
      continue
    names.incl(name)
    list.add(name)
  return list

func length(characterData: CharacterData): uint32 {.jsfget.} =
  return uint32(characterData.data.utf16Len)

func tagName(element: Element): string {.jsfget.} =
  if element.namespace == Namespace.HTML:
    return element.document.toStr(element.localName).toUpperAscii()
  return element.document.toStr(element.localName)

func nodeName(node: Node): string {.jsfget.} =
  if node of Element:
    return Element(node).tagName
  if node of Attr:
    let attr = Attr(node)
    return attr.ownerElement.document.toStr(attr.data.qualifiedName)
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
  return document.window.settings.scripting

func scriptingEnabled(element: Element): bool =
  return element.document.scriptingEnabled

func isSubmitButton*(element: Element): bool =
  if element of HTMLButtonElement:
    return element.attr(satType).equalsIgnoreCase("submit")
  elif element of HTMLInputElement:
    let element = HTMLInputElement(element)
    return element.inputType in {itSubmit, itImage}
  return false

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

func select*(option: HTMLOptionElement): HTMLSelectElement =
  for anc in option.ancestors:
    if anc of HTMLSelectElement:
      return HTMLSelectElement(anc)
  return nil

func countChildren(node: Node; nodeType: type): int =
  for child in node.childList:
    if child of nodeType:
      inc result

func hasChild(node: Node; nodeType: type): bool =
  for child in node.childList:
    if child of nodeType:
      return true

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

func nodeValue(node: Node): Option[string] {.jsfget.} =
  if node of CharacterData:
    return some(CharacterData(node).data)
  elif node of Attr:
    return some(Attr(node).data.value)
  return none(string)

func textContent*(node: Node): string =
  if node of CharacterData:
    result = CharacterData(node).data
  else:
    result = ""
    for child in node.childList:
      if not (child of Comment):
        result &= child.textContent

func jsTextContent(node: Node): Option[string] {.jsfget: "textContent".} =
  if node of Document or node of DocumentType:
    return none(string) # null
  return some(node.textContent)

func childTextContent*(node: Node): string =
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

func firstElementChild*(node: Node): Element {.jsfget.} =
  for child in node.elementList:
    return child
  return nil

func lastElementChild*(node: Node): Element {.jsfget.} =
  for child in node.elementList_rev:
    return child
  return nil

func isFirstVisualNode*(element: Element): bool =
  let parent = element.parentNode
  for child in parent.childList:
    if child == element:
      return true
    if child of Element:
      break
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

func findAncestor*(node: Node; tagTypes: set[TagType]): Element =
  for element in node.ancestors:
    if element.tagType in tagTypes:
      return element
  return nil

func getElementById(document: Document; id: string): Element {.jsfunc.} =
  if id.len == 0:
    return nil
  let id = document.toAtom(id)
  for child in document.elements:
    if child.id == id:
      return child
  return nil

func getElementsByName(document: Document; name: CAtom): NodeList {.jsfunc.} =
  return newCollection[NodeList](
    document,
    func(node: Node): bool =
      return node of Element and Element(node).name == name,
    islive = true,
    childonly = false
  )

func getElementsByTagName0(root: Node; tagName: string): HTMLCollection =
  if tagName == "*":
    return newCollection[HTMLCollection](
      root,
      isElement,
      islive = true,
      childonly = false
    )
  let localName = root.document.toAtom(tagName)
  let localNameLower = root.document.toAtom(tagName.toLowerAscii())
  return newCollection[HTMLCollection](
    root,
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

func getElementsByTagName(document: Document; tagName: string): HTMLCollection
    {.jsfunc.} =
  return document.getElementsByTagName0(tagName)

func getElementsByTagName(element: Element; tagName: string): HTMLCollection
    {.jsfunc.} =
  return element.getElementsByTagName0(tagName)

func getElementsByClassName0(node: Node; classNames: string): HTMLCollection =
  var classAtoms = newSeq[CAtom]()
  let document = node.document
  let isquirks = document.mode == QUIRKS
  if isquirks:
    for class in classNames.split(AsciiWhitespace):
      classAtoms.add(document.toAtom(class.toLowerAscii()))
  else:
    for class in classNames.split(AsciiWhitespace):
      classAtoms.add(document.toAtom(class))
  return newCollection[HTMLCollection](node,
    func(node: Node): bool =
      if node of Element:
        let element = Element(node)
        if isquirks:
          var cl = newSeq[CAtom]()
          for tok in element.classList.toks:
            let s = document.toStr(tok)
            cl.add(document.toAtom(s.toLowerAscii()))
          for class in classAtoms:
            if class notin cl:
              return false
        else:
          for class in classAtoms:
            if class notin element.classList.toks:
              return false
        return true,
    islive = true,
    childonly = false
  )

func getElementsByClassName(document: Document; classNames: string):
    HTMLCollection {.jsfunc.} =
  return document.getElementsByClassName0(classNames)

func getElementsByClassName(element: Element; classNames: string):
    HTMLCollection {.jsfunc.} =
  return element.getElementsByClassName0(classNames)

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
  let empty = ctx.toAtom("")
  #TODO exposed embed, exposed object
  for child in document.elements({TAG_FORM, TAG_IFRAME, TAG_IMG}):
    if child.name != CAtomNull and child.name != empty:
      if child.tagType == TAG_IMG and child.id != CAtomNull and
          child.id != empty:
        list.add(ctx.toStr(child.id))
      list.add(ctx.toStr(child.name))
  return list

proc getter(ctx: JSContext; document: Document; s: string): JSValue
    {.jsgetownprop.} =
  if s.len != 0:
    let id = ctx.toAtom(s)
    let empty = ctx.toAtom("")
    #TODO exposed embed, exposed object
    for child in document.elements({TAG_FORM, TAG_IFRAME, TAG_IMG}):
      if child.tagType == TAG_IMG and child.id == id and
          child.name != CAtomNull and child.name != empty:
        return ctx.toJS(child)
      if child.name == id:
        return ctx.toJS(child)
  return JS_UNINITIALIZED

func attr*(element: Element; s: CAtom): string =
  let i = element.findAttr(s)
  if i != -1:
    return element.attrs[i].value
  return ""

func attr*(element: Element; s: StaticAtom): string =
  return element.attr(element.document.toAtom(s))

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
  let atom = element.document.toAtom(at)
  return element.attrb(atom)

# https://html.spec.whatwg.org/multipage/parsing.html#serialising-html-fragments
func serializesAsVoid(element: Element): bool =
  const Extra = {TAG_BASEFONT, TAG_BGSOUND, TAG_FRAME, TAG_KEYGEN, TAG_PARAM}
  return element.tagType in VoidElements + Extra

func serializeFragment*(node: Node): string

func serializeFragmentInner(child: Node; parentType: TagType): string =
  result = ""
  if child of Element:
    let element = Element(child)
    let tags = element.document.toStr(element.localName)
    result &= '<'
    #TODO qualified name if not HTML, SVG or MathML
    result &= tags
    #TODO custom elements
    for attr in element.attrs:
      #TODO namespaced attrs
      let k = element.document.toStr(attr.localName)
      result &= ' ' & k & "=\"" & attr.value.escapeText(true) & "\""
    result &= '>'
    result &= element.serializeFragment()
    result &= "</"
    result &= tags
    result &= '>'
  elif child of Text:
    let text = Text(child)
    const LiteralTags = {
      TAG_STYLE, TAG_SCRIPT, TAG_XMP, TAG_IFRAME, TAG_NOEMBED, TAG_NOFRAMES,
      TAG_PLAINTEXT, TAG_NOSCRIPT
    }
    result = if parentType in LiteralTags:
      text.data
    else:
      text.data.escapeText()
  elif child of Comment:
    result &= "<!--" & Comment(child).data & "-->"
  elif child of ProcessingInstruction:
    let inst = ProcessingInstruction(child)
    result &= "<?" & inst.target & " " & inst.data & '>'
  elif child of DocumentType:
    result &= "<!DOCTYPE " & DocumentType(child).name & '>'

func serializeFragment*(node: Node): string =
  var node = node
  var parentType = TAG_UNKNOWN
  if node of Element:
    let element = Element(node)
    if element.serializesAsVoid():
      return ""
    if element of HTMLTemplateElement:
      node = HTMLTemplateElement(element).content
    else:
      parentType = element.tagType
      if parentType == TAG_NOSCRIPT and not element.scriptingEnabled:
        # Pretend parentType is not noscript, so we do not append literally
        # in serializeFragmentInner.
        parentType = TAG_UNKNOWN
  var s = ""
  for child in node.childList:
    s &= child.serializeFragmentInner(parentType)
  return s

# Element attribute reflection (getters)
func innerHTML(element: Element): string {.jsfget.} =
  #TODO xml
  return element.serializeFragment()

func outerHTML(element: Element): string {.jsfget.} =
  #TODO xml
  return element.serializeFragmentInner(TAG_UNKNOWN)

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

proc sheets*(document: Document): seq[CSSStylesheet] =
  if document.cachedSheetsInvalid and document.window.styling:
    document.cachedSheets.setLen(0)
    for elem in document.documentElement.descendants:
      if elem of HTMLStyleElement:
        let style = HTMLStyleElement(elem)
        style.sheet = parseStylesheet(style.textContent, document.factory,
          document.baseURL)
        document.cachedSheets.add(style.sheet)
      elif elem of HTMLLinkElement:
        let link = HTMLLinkElement(elem)
        if link.enabled.get(satAlternate notin link.relList):
          document.cachedSheets.add(link.sheets)
      else: discard
    document.cachedSheetsInvalid = false
  return document.cachedSheets

func checked*(input: HTMLInputElement): bool {.inline.} =
  return input.internalChecked

proc setChecked*(input: HTMLInputElement; b: bool) {.inline.} =
  input.invalidDeps.incl(dtChecked)
  input.internalChecked = b

func inputString*(input: HTMLInputElement): string =
  case input.inputType
  of itCheckbox, itRadio:
    if input.checked:
      "*"
    else:
      " "
  of itSearch, itText, itEmail, itURL, itTel:
    input.value.padToWidth(int(input.attrulgz(satSize).get(20)))
  of itPassword:
    '*'.repeat(input.value.len).padToWidth(int(input.attrulgz(satSize).get(20)))
  of itReset:
    if input.value != "":
      input.value
    else:
      "RESET"
  of itSubmit, itButton:
    if input.value != "":
      input.value
    else:
      "SUBMIT"
  of itFile:
    let s = if input.file != nil: input.file.name else: ""
    s.padToWidth(int(input.attrulgz(satSize).get(20)))
  else: input.value

func textAreaString*(textarea: HTMLTextAreaElement): string =
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

func findAnchor*(document: Document; id: string): Element =
  if id.len == 0:
    return nil
  let id = document.toAtom(id)
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

func focus*(document: Document): Element =
  return document.internalFocus

proc setFocus*(document: Document; element: Element) =
  if document.focus != nil:
    document.focus.invalidDeps.incl(dtFocus)
  document.internalFocus = element
  if element != nil:
    element.invalidDeps.incl(dtFocus)

func hover*(element: Element): bool =
  return element.internalHover

proc setHover*(element: Element; hover: bool) =
  element.invalidDeps.incl(dtHover)
  element.internalHover = hover

func findAutoFocus*(document: Document): Element =
  for child in document.elements:
    if child.attrb(satAutofocus):
      return child
  return nil

proc fireEvent*(window: Window; name: StaticAtom; target: EventTarget) =
  let event = newEvent(window.toAtom(name), target)
  discard window.jsctx.dispatch(target, event)

proc parseColor(element: Element; s: string): ARGBColor =
  let cval = parseComponentValue(s)
  #TODO return element style
  # For now we just use white.
  let ec = rgba(255, 255, 255, 255)
  if cval.isNone:
    return ec
  let color0 = cssColor(cval.get)
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
    let s = ctx.toStr(sa)
    let res = JS_GetPropertyStr(ctx, href, cstring(s))
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
    let s = ctx.toStr(sa)
    let res = JS_SetPropertyStr(ctx, href, cstring(s), JS_DupValue(ctx, val))
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
    let sa = ctx.toStaticAtom(ctx.toAtom(s))
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

# <base>
proc href(base: HTMLBaseElement): string {.jsfget.} =
  #TODO with fallback base url
  let url = parseURL(base.attr(satHref))
  if url.isSome:
    return $url.get
  return ""

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

# <label>
func control*(label: HTMLLabelElement): FormAssociatedElement {.jsfget.} =
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

func form(label: HTMLLabelElement): HTMLFormElement {.jsfget.} =
  let control = label.control
  if control != nil:
    return control.form
  return nil

# <link>
proc setRelList(link: HTMLLinkElement; s: string) {.jsfset: "relList".} =
  link.attr(satRel, s)

# <form>
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

# <input>
func jsForm(this: HTMLInputElement): HTMLFormElement {.jsfget: "form".} =
  return this.form

proc setValue(this: HTMLInputElement; value: string) {.jsfset: "value".} =
  this.value = value
  this.setInvalid()

# <select>
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

#TODO length setter

proc getter(ctx: JSContext; this: HTMLSelectElement; u: JSAtom): JSValue
    {.jsgetownprop.} =
  return ctx.getter(this.jsOptions, u)

proc item(this: HTMLSelectElement; u: uint32): Node {.jsfunc.} =
  return this.jsOptions.item(u)

func namedItem(this: HTMLSelectElement; atom: CAtom): Element {.jsfunc.} =
  return this.jsOptions.namedItem(atom)

proc selectedOptions(this: HTMLSelectElement): HTMLCollection {.jsfget.} =
  if this.cachedSelectedOptions == nil:
    this.cachedSelectedOptions = newCollection[HTMLCollection](
      root = this,
      match = func(node: Node): bool =
        return node.isOptionOf(this) and HTMLOptionElement(node).selected,
      islive = true,
      childonly = false
    )
  return this.cachedSelectedOptions

proc value(this: HTMLSelectElement): string {.jsfget.} =
  let first = this.selectedOptions.item(0)
  if first != nil:
    return HTMLOptionElement(first).value
  return ""

#TODO add, selectedIndex, value setter, showPicker

# <button>
func jsForm(this: HTMLButtonElement): HTMLFormElement {.jsfget: "form".} =
  return this.form

# <textarea>
func jsForm(this: HTMLTextAreaElement): HTMLFormElement {.jsfget: "form".} =
  return this.form

# <video>
func getSrc*(this: HTMLElement): string =
  let src = this.attr(satSrc)
  if src != "":
    return src
  for el in this.elements(TAG_SOURCE):
    let src = el.attr(satSrc)
    if src != "":
      return src
  return ""

func newText*(document: Document; data: string): Text =
  return Text(
    internalDocument: document,
    data: data,
    index: -1
  )

func newText(ctx: JSContext; data = ""): Text {.jsctor.} =
  let window = ctx.getGlobal()
  return window.document.newText(data)

func newCDATASection(document: Document; data: string): CDATASection =
  return CDATASection(
    internalDocument: document,
    data: data,
    index: -1
  )

func newProcessingInstruction(document: Document; target, data: string):
    ProcessingInstruction =
  return ProcessingInstruction(
    internalDocument: document,
    target: target,
    data: data,
    index: -1
  )

func newDocumentFragment(document: Document): DocumentFragment =
  return DocumentFragment(internalDocument: document, index: -1)

func newDocumentFragment(ctx: JSContext): DocumentFragment {.jsctor.} =
  let window = ctx.getGlobal()
  return window.document.newDocumentFragment()

func newComment(document: Document; data: string): Comment =
  return Comment(
    internalDocument: document,
    data: data,
    index: -1
  )

func newComment(ctx: JSContext; data: string = ""): Comment {.jsctor.} =
  let window = ctx.getGlobal()
  return window.document.newComment(data)

#TODO custom elements
proc newHTMLElement*(document: Document; localName: CAtom;
    namespace = Namespace.HTML; prefix = NO_PREFIX): HTMLElement =
  let tagType = document.toTagType(localName)
  case tagType
  of TAG_INPUT:
    result = HTMLInputElement()
  of TAG_A:
    let anchor = HTMLAnchorElement()
    let localName = document.toAtom(satRel)
    anchor.relList = DOMTokenList(element: anchor, localName: localName)
    result = anchor
  of TAG_SELECT:
    result = HTMLSelectElement()
  of TAG_OPTGROUP:
    result = HTMLOptGroupElement()
  of TAG_OPTION:
    result = HTMLOptionElement()
  of TAG_H1, TAG_H2, TAG_H3, TAG_H4, TAG_H5, TAG_H6:
    result = HTMLHeadingElement()
  of TAG_BR:
    result = HTMLBRElement()
  of TAG_SPAN:
    result = HTMLSpanElement()
  of TAG_OL:
    result = HTMLOListElement()
  of TAG_UL:
    result = HTMLUListElement()
  of TAG_MENU:
    result = HTMLMenuElement()
  of TAG_LI:
    result = HTMLLIElement()
  of TAG_STYLE:
    result = HTMLStyleElement()
  of TAG_LINK:
    let link = HTMLLinkElement()
    let localName = document.toAtom(satRel)
    link.relList = DOMTokenList(element: link, localName: localName)
    result = link
  of TAG_FORM:
    let form = HTMLFormElement()
    let localName = document.toAtom(satRel)
    form.relList = DOMTokenList(element: form, localName: localName)
    result = form
  of TAG_TEMPLATE:
    result = HTMLTemplateElement(
      content: DocumentFragment(internalDocument: document, host: result)
    )
  of TAG_UNKNOWN:
    result = HTMLUnknownElement()
  of TAG_SCRIPT:
    result = HTMLScriptElement(forceAsync: true)
  of TAG_BASE:
    result = HTMLBaseElement()
  of TAG_BUTTON:
    result = HTMLButtonElement()
  of TAG_TEXTAREA:
    result = HTMLTextAreaElement()
  of TAG_LABEL:
    result = HTMLLabelElement()
  of TAG_CANVAS:
    let bitmap = if document.scriptingEnabled:
      NetworkBitmap(
        contentType: "image/x-cha-canvas",
        imageId: document.window.getImageId(),
        width: 300,
        height: 150
      )
    else:
      nil
    result = HTMLCanvasElement(bitmap: bitmap)
  of TAG_IMG:
    result = HTMLImageElement()
  of TAG_VIDEO:
    result = HTMLVideoElement()
  of TAG_AUDIO:
    result = HTMLAudioElement()
  of TAG_AREA:
    let area = HTMLAreaElement()
    let localName = document.toAtom(satRel)
    area.relList = DOMTokenList(element: area, localName: localName)
    result = area
  else:
    result = HTMLElement()
  result.localName = localName
  result.namespace = namespace
  result.namespacePrefix = prefix
  result.internalDocument = document
  let localName = document.toAtom(satClassList)
  result.classList = DOMTokenList(element: result, localName: localName)
  result.index = -1
  result.dataset = DOMStringMap(target: result)

proc newHTMLElement*(document: Document; tagType: TagType): HTMLElement =
  let localName = document.toAtom(tagType)
  return document.newHTMLElement(localName, Namespace.HTML, NO_PREFIX)

proc newDocument*(factory: CAtomFactory): Document =
  assert factory != nil
  let document = Document(
    url: newURL("about:blank").get,
    index: -1,
    factory: factory,
    contentType: "application/xml"
  )
  document.implementation = DOMImplementation(document: document)
  return document

proc newDocument(ctx: JSContext): Document {.jsctor.} =
  return newDocument(ctx.getGlobal().factory)

func newDocumentType*(document: Document; name, publicId, systemId: string):
    DocumentType =
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
  if document.url == nil:
    return newURL("about:blank").get #TODO ???
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

proc invalidateCollections(node: Node) =
  for id in node.liveCollections:
    node.document.invalidCollections.incl(id)

proc setInvalid*(element: Element) =
  element.invalid = true
  if element.document != nil:
    element.document.invalid = true

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
          attrs: @[data]
        )
        attr.dataIdx = 0
      map.attrlist.del(j) # ordering does not matter
  element.reflectAttr(name, none(string))
  element.invalidateCollections()
  element.setInvalid()

proc newCSSStyleDeclaration(element: Element; value: string):
    CSSStyleDeclaration =
  let inlineRules = value.parseDeclarations()
  var decls: seq[CSSDeclaration] = @[]
  for rule in inlineRules:
    if rule.name.isSupportedProperty():
      decls.add(rule)
  return CSSStyleDeclaration(decls: inlineRules, element: element)

proc cssText(this: CSSStyleDeclaration): string {.jsfunc.} =
  #TODO this is incorrect
  return $this.decls

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

proc getPropertyValue(this: CSSStyleDeclaration; s: string): string =
  if (let i = this.find(s); i != -1):
    return $this.decls[i].value
  return ""

# https://drafts.csswg.org/cssom/#idl-attribute-to-css-property
func IDLAttributeToCSSProperty(s: string; dashPrefix = false): string =
  result = if dashPrefix: "-" else: ""
  for c in s:
    if c in AsciiUpperAlpha:
      result &= '-'
      result &= c.toLowerAscii()
    else:
      result &= c

proc getter(ctx: JSContext; this: CSSStyleDeclaration; atom: JSAtom):
    JSValue {.jsgetownprop.} =
  var u: uint32
  if ctx.fromJS(atom, u).isSome:
    return ctx.toJS(this.item(u)).uninitIfNull()
  var s: string
  if ctx.fromJS(atom, s).isNone:
    return JS_EXCEPTION
  if s.isSupportedProperty():
    return ctx.toJS(this.getPropertyValue(s))
  s = IDLAttributeToCSSProperty(s)
  if s.isSupportedProperty():
    return ctx.toJS(this.getPropertyValue(s))
  return JS_UNINITIALIZED

proc setValue(this: CSSStyleDeclaration; i: int; cvals: seq[CSSComponentValue]):
    Err[void] =
  if i notin 0 .. this.decls.high:
    return err()
  var dummy: seq[CSSComputedEntry]
  ?parseComputedValues(dummy, this.decls[i].name, cvals)
  this.decls[i].value = cvals
  return ok()

proc setter(ctx: JSContext; this: CSSStyleDeclaration; atom: JSAtom;
    value: string): Opt[void] {.jssetprop.} =
  let cvals = parseComponentValues(value)
  var u: uint32
  if ctx.fromJS(atom, u).isSome:
    if this.setValue(int(u), cvals).isNone:
      return ok()
  else:
    var s: string
    ?ctx.fromJS(atom, s)
    if (let i = this.find(s); i != -1):
      if this.setValue(i, cvals).isNone:
        # not err! this does not throw.
        return ok()
    else:
      var dummy: seq[CSSComputedEntry]
      let val0 = parseComputedValues(dummy, s, cvals)
      if val0.isNone:
        return ok()
      this.decls.add(CSSDeclaration(name: s, value: cvals))
  this.element.attr(satStyle, $this.decls)
  ok()

proc style*(element: Element): CSSStyleDeclaration {.jsfget.} =
  if element.cachedStyle == nil:
    element.cachedStyle = CSSStyleDeclaration(element: element)
  return element.cachedStyle

proc corsFetch(window: Window; input: Request): FetchPromise =
  if not window.images and input.url.scheme.startsWith("img-codec+"):
    return newResolvedPromise(JSResult[Response].err(newFetchTypeError()))
  return window.loader.fetch(input)

proc loadSheet(window: Window; link: HTMLLinkElement; url: URL; applies: bool) =
  let p = window.corsFetch(
    newRequest(url)
  ).then(proc(res: JSResult[Response]): Promise[JSResult[string]] =
    if res.isSome:
      let res = res.get
      if res.getContentType() == "text/css":
        return res.text()
      res.close()
    return newResolvedPromise(JSResult[string].err(nil))
  ).then(proc(s: JSResult[string]) =
    # Check applies here, to avoid leaking the window size.
    if s.isSome:
      let sheet = s.get.parseStylesheet(window.factory, url)
      if applies:
        # Note: we intentionally load all sheets to prevent media query
        # based tracking.
        link.sheets.add(sheet)
        window.document.cachedSheetsInvalid = true
      for url in sheet.importList:
        window.loadSheet(link, url, true) #TODO media query
  )
  window.pendingResources.add(p)

# see https://html.spec.whatwg.org/multipage/links.html#link-type-stylesheet
#TODO make this somewhat compliant with ^this
proc loadResource(window: Window; link: HTMLLinkElement) =
  if not window.styling or satStylesheet notin link.relList or
      link.fetchStarted or
      not link.enabled.get(satAlternate notin link.relList):
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
      let media = parseMediaQueryList(cvals)
      applies = media.appliesImpl(window)
    window.loadSheet(link, url, applies)

proc getImageId(window: Window): int =
  result = window.imageId
  inc window.imageId

proc loadResource*(window: Window; image: HTMLImageElement) =
  if not window.images:
    image.invalid = image.invalid or image.bitmap != nil
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
      if p[].expiry > getTime().utc().toTime().toUnix():
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
          response.resume()
          response.close()
          if "Cha-Image-Dimensions" notin response.headers.table:
            window.console.error("Cha-Image-Dimensions missing in",
              $response.url)
            return
          let dims = response.headers.table["Cha-Image-Dimensions"][0]
          let width = parseIntP(dims.until('x'))
          let height = parseIntP(dims.after('x'))
          if width.get(-1) < 0 or height.get(-1) < 0:
            window.console.error("wrong Cha-Image-Dimensions in", $response.url)
            return
          let bmp = NetworkBitmap(
            width: width.get,
            height: height.get,
            cacheId: cacheId,
            imageId: window.getImageId(),
            contentType: contentType
          )
          image.bitmap = bmp
          cachedURL.bmp = bmp
          for share in cachedURL.shared:
            share.bitmap = bmp
            share.setInvalid()
          image.setInvalid()
        )
      )
    window.pendingResources.add(p)

proc reflectEvent(element: Element; target: EventTarget; name, ctype: StaticAtom;
    value: string) =
  let document = element.document
  let ctx = document.window.jsctx
  let urls = document.baseURL.serialize(excludepassword = true)
  let fun = ctx.newFunction(["event"], value)
  assert ctx != nil
  if JS_IsException(fun):
    document.window.console.error("Exception in body content attribute of",
      urls, ctx.getExceptionMsg())
  else:
    let jsTarget = ctx.toJS(target)
    ctx.definePropertyC(jsTarget, $name, JS_DupValue(ctx, fun))
    JS_FreeValue(ctx, jsTarget)
    #TODO this is subtly wrong. In fact, we should not pass `fun'
    # directly here, but a wrapper function that calls fun. Currently
    # you can run removeEventListener with element.onclick, that should
    # not work.
    doAssert ctx.addEventListener(target, document.toAtom(ctype), fun).isSome
  JS_FreeValue(ctx, fun)

proc reflectAttr(element: Element; name: CAtom; value: Option[string]) =
  let name = element.document.toStaticAtom(name)
  template reflect_str(element: Element; n: StaticAtom; val: untyped) =
    if name == n:
      element.val = value.get("")
      return
  template reflect_atom(element: Element; n: StaticAtom; val: untyped) =
    if name == n:
      if value.isSome:
        element.val = element.document.toAtom(value.get)
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
          let a = element.document.toAtom(x)
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
      element.reflectEvent(element.document.window, name, satLoad, value.get(""))
      return
  of TAG_INPUT:
    let input = HTMLInputElement(element)
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
    button.reflect_str satValue, value
    if name == satType:
      button.ctype = parseEnumNoCase[ButtonType](value.get("")).get(btSubmit)
  of TAG_LINK:
    let link = HTMLLinkElement(element)
    if name == satRel:
      link.reflect_domtoklist0 relList # do not return
    if name == satDisabled:
      # IE won :(
      if link.enabled.isNone:
        link.document.cachedSheetsInvalid = true
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

proc attr*(element: Element; name: CAtom; value: string) =
  let i = element.findAttrOrNext(name)
  if i >= 0:
    element.attrs[i].value = value
    element.invalidateCollections()
    element.setInvalid()
  else:
    element.attrs.insert(AttrData(
      qualifiedName: name,
      localName: name,
      value: value
    ), -(i + 1))
  element.reflectAttr(name, some(value))

proc attr*(element: Element; name: StaticAtom; value: string) =
  element.attr(element.document.toAtom(name), value)

proc attrns*(element: Element; localName: CAtom; prefix: NamespacePrefix;
    namespace: Namespace; value: sink string) =
  if prefix == NO_PREFIX and namespace == NO_NAMESPACE:
    element.attr(localName, value)
    return
  let namespace = element.document.toAtom(namespace)
  let i = element.findAttrNS(namespace, localName)
  var prefixAtom, qualifiedName: CAtom
  if prefix != NO_PREFIX:
    prefixAtom = element.document.toAtom(prefix)
    let tmp = $prefix & ':' & element.document.toStr(localName)
    qualifiedName = element.document.toAtom(tmp)
  else:
    qualifiedName = localName
  if i != -1:
    element.attrs[i].prefix = prefixAtom
    element.attrs[i].qualifiedName = qualifiedName
    element.attrs[i].value = value
    element.invalidateCollections()
    element.setInvalid()
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

proc setAttribute(element: Element; qualifiedName, value: string):
    Err[DOMException] {.jsfunc.} =
  ?validateAttributeName(qualifiedName)
  let qualifiedName = if element.namespace == Namespace.HTML and
      not element.document.isxml:
    element.document.toAtom(qualifiedName.toLowerAscii())
  else:
    element.document.toAtom(qualifiedName)
  element.attr(qualifiedName, value)
  return ok()

proc setAttributeNS(element: Element; namespace, qualifiedName,
    value: string): Err[DOMException] {.jsfunc.} =
  ?validateAttributeQName(qualifiedName)
  let ps = qualifiedName.until(':')
  let prefix = if ps.len < qualifiedName.len: ps else: ""
  let localName = element.document.toAtom(qualifiedName.substr(prefix.len))
  #TODO atomize here
  if prefix != "" and namespace == "" or
      prefix == "xml" and namespace != $Namespace.XML or
      (qualifiedName == "xmlns" or prefix == "xmlns") and
        namespace != $Namespace.XMLNS or
      namespace == $Namespace.XMLNS and qualifiedName != "xmlns" and
        prefix != "xmlns":
    return errDOMException("Unexpected namespace", "NamespaceError")
  let qualifiedName = element.document.toAtom(qualifiedName)
  let namespace = element.document.toAtom(namespace)
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
  ?validateAttributeName(qualifiedName)
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
  for i in node.index ..< parent.childList.len - 1:
    parent.childList[i] = parent.childList[i + 1]
    parent.childList[i].index = i
  parent.childList.setLen(parent.childList.len - 1)
  parent.invalidateCollections()
  node.invalidateCollections()
  if parent of Element:
    Element(parent).setInvalid()
  node.parentNode = nil
  node.index = -1
  if node.document != nil and (node of HTMLStyleElement or
      node of HTMLLinkElement):
    node.document.cachedSheetsInvalid = true

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
      input.file = nil
    else:
      input.value = input.attr(satValue)
    input.setInvalid()
  of TAG_SELECT:
    let select = HTMLSelectElement(element)
    var firstOption: HTMLOptionElement = nil
    var prevSelected: HTMLOptionElement = nil
    let multiple = select.attrb(satMultiple)
    for option in select.options:
      if firstOption == nil:
        firstOption = option
      option.selected = option.attrb(satSelected)
      if option.selected:
        if not multiple and prevSelected != nil:
          prevSelected.selected = false
        prevSelected = option
    if not multiple and select.attrul(satSize).get(1) == 1 and
        prevSelected == nil and firstOption != nil:
      firstOption.selected = true
  of TAG_TEXTAREA:
    let textarea = HTMLTextAreaElement(element)
    textarea.value = textarea.childTextContent()
    textarea.setInvalid()
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

proc resetFormOwner(element: FormAssociatedElement) =
  element.parserInserted = false
  if element.form != nil:
    if element.tagType notin ListedElements:
      return
    let lastForm = element.findAncestor({TAG_FORM})
    if not element.attrb(satForm) and lastForm == element.form:
      return
  element.form = nil
  if element.tagType in ListedElements and element.isConnected:
    let form = element.document.getElementById(element.attr(satForm))
    if form of HTMLFormElement:
      element.setForm(HTMLFormElement(form))

proc elementInsertionSteps(element: Element) =
  if element of HTMLOptionElement:
    if element.parentElement != nil:
      let parent = element.parentElement
      var select: HTMLSelectElement
      if parent of HTMLSelectElement:
        select = HTMLSelectElement(parent)
      elif parent.tagType == TAG_OPTGROUP and parent.parentElement != nil and
          parent.parentElement of HTMLSelectElement:
        select = HTMLSelectElement(parent.parentElement)
      if select != nil:
        select.resetElement()
  elif element of FormAssociatedElement:
    let element = FormAssociatedElement(element)
    if element.parserInserted:
      return
    element.resetFormOwner()
  elif element of HTMLLinkElement:
    let window = element.document.window
    if window != nil:
      let link = HTMLLinkElement(element)
      window.loadResource(link)
  elif element of HTMLImageElement:
    let window = element.document.window
    if window != nil:
      let image = HTMLImageElement(element)
      window.loadResource(image)

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
  if before == nil:
    node.index = parent.childList.high
  else:
    node.index = before.index
    for i in countdown(parent.childList.high - 1, node.index):
      parent.childList[i + 1] = parent.childList[i]
      parent.childList[i + 1].index = i + 1
  parent.childList[node.index] = node
  node.parentNode = parent
  node.invalidateCollections()
  parent.invalidateCollections()
  if node.document != nil and (node of HTMLStyleElement or
      node of HTMLLinkElement):
    node.document.cachedSheetsInvalid = true
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
    Element(parent).setInvalid()
  for node in nodes:
    insertNode(parent, node, before)

proc insertBefore*(parent, node, before: Node): DOMResult[Node] {.jsfunc.} =
  ?parent.preInsertionValidity(node, before)
  let referenceChild = if before == node:
    node.nextSibling
  else:
    before
  parent.insert(node, referenceChild)
  return ok(node)

proc appendChild(parent, node: Node): DOMResult[Node] {.jsfunc.} =
  return parent.insertBefore(node, nil)

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

proc replaceChild(parent, node, child: Node): DOMResult[Node] {.jsfunc.} =
  ?parent.replace(child, node)
  return ok(child)

proc createTextNode*(document: Document; data: string): Text {.jsfunc.} =
  return newText(document, data)

proc textContent*(node: Node; data: Option[string]) {.jsfset.} =
  if node of Element or node of DocumentFragment:
    let x = if data.isSome:
      node.document.createTextNode(data.get)
    else:
      nil
    node.replaceAll(x)
  elif node of CharacterData:
    CharacterData(node).data = data.get("")
  elif node of Attr:
    value(Attr(node), data.get(""))

proc reset*(form: HTMLFormElement) =
  for control in form.controls:
    control.resetElement()
    control.setInvalid()

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

proc fetchDescendantsAndLink(element: HTMLScriptElement; script: Script;
    destination: RequestDestination; onComplete: OnCompleteProc) =
  discard

#TODO settings object
proc fetchSingleModule(element: HTMLScriptElement; url: URL;
    destination: RequestDestination; options: ScriptOptions,
    referrer: URL; isTopLevel: bool; onComplete: OnCompleteProc) =
  discard #TODO implement
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
          let res = ctx.newJSModuleScript(s.get, element.document.baseURL,
            options)
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
      let urls = script.baseURL.serialize(excludepassword = true)
      let ctx = window.jsctx
      if JS_IsException(script.record):
        window.console.error("Exception in document", urls,
          ctx.getExceptionMsg())
      else:
        let ret = ctx.evalFunction(script.record)
        if JS_IsException(ret):
          window.console.error("Exception in document", urls,
            ctx.getExceptionMsg())
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
    else:
      element.fetchExternalModuleGraph(url.get, options, markAsReady)
  else:
    let baseURL = element.document.baseURL
    if element.ctype == stClassic:
      let ctx = element.document.window.jsctx
      let script = ctx.newClassicScript(sourceText, baseURL, options)
      element.markAsReady(script)
    else:
      #TODO stModule, stImportMap
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
proc createElement(document: Document; localName: string):
    DOMResult[Element] {.jsfunc.} =
  if not localName.matchNameProduction():
    return errDOMException("Invalid character in element name",
      "InvalidCharacterError")
  let localName = if not document.isxml:
    document.toAtom(localName.toLowerAscii())
  else:
    document.toAtom(localName)
  let namespace = if not document.isxml:
    #TODO or content type is application/xhtml+xml
    Namespace.HTML
  else:
    NO_NAMESPACE
  return ok(document.newHTMLElement(localName, namespace))

#TODO createElementNS

proc createDocumentFragment(document: Document): DocumentFragment {.jsfunc.} =
  return newDocumentFragment(document)

proc createDocumentType(implementation: var DOMImplementation; qualifiedName,
    publicId, systemId: string): DOMResult[DocumentType] {.jsfunc.} =
  if not qualifiedName.matchQNameProduction():
    return errDOMException("Invalid character in document type name",
      "InvalidCharacterError")
  let document = implementation.document
  return ok(document.newDocumentType(qualifiedName, publicId, systemId))

proc createHTMLDocument(ctx: JSContext; implementation: var DOMImplementation;
    title = none(string)): Document {.jsfunc.} =
  let doc = newDocument(ctx)
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
  #TODO set origin
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

proc createEvent(ctx: JSContext; document: Document; t: StaticAtom):
    DOMResult[Event] {.jsfunc.} =
  if t notin {satUEvent, satEvent, satEvents, satSvgevents}:
    return errDOMException("Event not supported", "NotSupportedError")
  return ok(newEvent(ctx.toAtom(""), nil))

proc clone(node: Node; document = none(Document), deep = false): Node =
  let document = document.get(node.document)
  let copy = if node of Element:
    #TODO is value
    let element = Element(node)
    let x = document.newHTMLElement(element.localName, element.namespace,
      element.namespacePrefix)
    x.id = element.id
    x.name = element.name
    x.classList = DOMTokenList(element: x, localName: element.localName)
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
    let x = newDocument(document.factory)
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
    if node.namespace != other.namespace or
        node.namespacePrefix != other.namespacePrefix or
        node.localName != other.localName or
        node.attrs.len != other.attrs.len:
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

proc querySelectorAll(node: Node; q: string): seq[Element] {.jsfunc.} =
  return node.querySelectorAllImpl(q)

proc querySelector(node: Node; q: string): Element {.jsfunc.} =
  return node.querySelectorImpl(q)

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
  of rtFunction:
    let val = ctx.toJS(entry.attrname)
    let atom = JS_ValueToAtom(ctx, val)
    var res = JS_NULL
    var desc: JSPropertyDescriptor
    if JS_GetOwnProperty(ctx, addr desc, this, atom) > 0:
      JS_FreeValue(ctx, desc.setter)
      JS_FreeValue(ctx, desc.getter)
      res = desc.value
    JS_FreeValue(ctx, val)
    JS_FreeAtom(ctx, atom)
    return res

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
    if JS_IsFunction(ctx, val):
      var target: EventTarget
      assert ctx.fromJS(this, target).isSome
      ctx.definePropertyC(this, $entry.attrname, JS_DupValue(ctx, val))
      #TODO I haven't checked but this might also be wrong
      let ctype = ctx.getGlobal().toAtom(entry.ctype)
      doAssert ctx.addEventListener(target, ctype, val).isSome
  return JS_DupValue(ctx, val)

func getReflectFunctions(tags: set[TagType]): seq[TabGetSet] =
  result = @[]
  for tag in tags:
    if tag in TagReflectMap:
      for i in TagReflectMap[tag]:
        result.add(TabGetSet(
          name: ReflectTable[i].funcname,
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
      name: ReflectTable[i].funcname,
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
    res.resume()
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

proc outerHTML(element: Element; s: string): Err[DOMException] {.jsfset.} =
  let parent0 = element.parentNode
  if parent0 == nil:
    return ok()
  if parent0 of Document:
    let ex = newDOMException("outerHTML is disallowed for Document children",
      "NoModificationAllowedError")
    return err(ex)
  let parent = if parent0 of DocumentFragment:
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
    ctx.registerType(t, parent = htmlElementCID,
      hasExtraGetSet = true, extraGetSet = extra_getset)
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

proc addDOMModule*(ctx: JSContext) =
  let eventTargetCID = ctx.getClass("EventTarget")
  let nodeCID = ctx.registerType(Node, parent = eventTargetCID)
  ctx.defineConsts(nodeCID, NodeType, uint16)
  let nodeListCID = ctx.registerType(NodeList)
  let htmlCollectionCID = ctx.registerType(HTMLCollection)
  ctx.registerType(HTMLAllCollection, ishtmldda = true)
  ctx.registerType(HTMLFormControlsCollection, parent = htmlCollectionCID)
  ctx.registerType(HTMLOptionsCollection, parent = htmlCollectionCID)
  ctx.registerType(RadioNodeList, parent = nodeListCID)
  ctx.registerType(Location)
  ctx.registerType(Document, parent = nodeCID)
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
  doAssert JS_SetConstructorBit(ctx, imageFun, true)
  let jsWindow = JS_GetGlobalObject(ctx)
  ctx.definePropertyCW(jsWindow, "Image", imageFun)
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
      if event.ctype == ctx.toAtom(satLoad):
        return nil
      # if no browsing context, then window will be nil anyway
      return Document(eventTarget).window
    return Node(eventTarget).parentNode
  return nil

getFactoryImpl = proc(ctx: JSContext): CAtomFactory =
  return ctx.getGlobal().factory

errorImpl = proc(ctx: JSContext; ss: varargs[string]) =
  ctx.getGlobal().console.error(ss)

getAPIBaseURLImpl = proc(ctx: JSContext): URL =
  let window = ctx.getWindow()
  if window == nil or window.document == nil:
    return nil
  return window.document.baseURL
