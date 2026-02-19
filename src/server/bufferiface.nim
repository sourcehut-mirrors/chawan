{.push raises: [].}

import std/options
import std/posix
import std/tables

import chagashi/charset
import config/config
import config/conftypes
import config/cookie
import config/mimetypes
import css/render
import io/dynstream
import io/packetreader
import io/packetwriter
import local/select
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsutils
import monoucha/libregexp
import monoucha/quickjs
import monoucha/tojs
import server/headers
import server/loaderiface
import server/request
import server/response
import types/bitmap
import types/blob
import types/cell
import types/color
import types/jsopt
import types/opt
import types/referrer
import types/refstring
import types/url
import types/winattrs
import utils/lrewrap
import utils/strwidth
import utils/twtstr

type
  BufferCommand* = enum
    bcCancel = "cancel"
    bcCheckRefresh = "checkRefresh"
    bcClick = "click"
    bcClone = "clone"
    bcContextMenu = "contextMenu"
    bcFindNextLink = "findNextLink"
    bcFindNextMatch = "findNextMatch"
    bcFindNextParagraph = "findNextParagraph"
    bcFindPrevLink = "findPrevLink"
    bcFindPrevMatch = "findPrevMatch"
    bcFindRevNthLink = "findRevNthLink"
    bcForceReshape = "forceReshape"
    bcGetLines = "getLines"
    bcGetLinks = "getLinks"
    bcGetSelectionText = "getSelectionText"
    bcGetTitle = "getTitle"
    bcGotoAnchor = "gotoAnchor"
    bcHideHints = "hideHints"
    bcLoad = "load"
    bcMarkURL = "markURL"
    bcOnReshape = "onReshape"
    bcReadCanceled = "readCanceled"
    bcReadSuccess = "readSuccess"
    bcSelect = "select"
    bcShowHints = "showHints"
    bcSubmitForm = "submitForm"
    bcToggleImages = "toggleImages"
    bcUpdateHover = "updateHover"
    bcWindowChange = "windowChange"

  HoverType* = enum
    htTitle, htLink, htImage, htCachedImage

  UpdateHoverResult* = seq[tuple[t: HoverType, s: string]]

  GetValueProc = proc(ctx: JSContext; iface: BufferInterface;
    r: var PacketReader): JSValue {.nimcall, raises: [].}

  BufferIfaceItem* = object
    id*: int
    fun: pointer
    get: GetValueProc

  HighlightType* = enum
    hltSearch, hltSelect

  Highlight* = ref object
    t* {.jsget.}: HighlightType
    selectionType* {.jsget.}: SelectionType
    mouse* {.jsget.}: bool
    x1*: int
    y1*: int
    x2* {.jsgetset.}: int
    y2* {.jsgetset.}: int

  CachedImageState* = enum
    cisLoading, cisCanceled, cisLoaded

  CachedImage* = ref object
    state*: CachedImageState
    width*: int
    height*: int
    data*: Blob # mmapped blob of image data
    cacheId*: int # cache id of the file backing "data"
    bmp*: NetworkBitmap
    # Following variables are always 0 in kitty mode; they exist to support
    # sixel cropping.
    # We can easily crop images where we just have to exclude some lines prior
    # to/after the image, but we must re-encode if
    # * offx > 0, dispw < width or
    # * offy % 6 != previous offy % 6 (currently only happens when cell height
    #   is not a multiple of 6).
    offx*: int # same as CanvasImage.offx
    dispw*: int # same as CanvasImage.dispw
    erry*: int # same as CanvasImage.offy % 6
    # whether the image has transparency, *disregarding the last row*
    transparent*: bool
    # length of introducer, raster, palette data before pixel data
    preludeLen*: int
    next: CachedImage

  ImageCache = object
    head: CachedImage
    tail: CachedImage

  BufferState* = enum
    bsLoadingPage = "loadingPage"
    bsLoadingResources = "loadingResources"
    bsLoadingImages = "loadingImages"
    bsLoaded = "loaded"

  LoadResult* = tuple
    n: uint64
    len: uint64
    bs: BufferState

  GotoAnchorResult* = object
    x*: int
    y*: int
    focus*: ClickResult

  PagePos* = tuple
    x: int
    y: int

  CursorXY* = object
    x*: int
    y*: int

  #TODO probably this should be PagePos instead
  HintResult* = seq[CursorXY]

  ClickResultType* = enum
    crtNone = "none"
    crtOpen = "open"
    crtReadText = "read-text"
    crtReadPassword = "read-password"
    crtReadArea = "read-area"
    crtReadFile = "read-file"
    crtSelect = "select"

  BufferMatch* = object
    x*: int
    y*: int
    w*: int

  ClickResult* = object
    case t*: ClickResultType
    of crtNone: discard
    of crtOpen:
      open*: Request
      contentType*: string
    of crtReadArea, crtReadText, crtReadPassword, crtReadFile:
      prompt*: string
      value*: string
    of crtSelect:
      options*: seq[SelectOption]
      selected*: int

  SelectionType* = enum
    stNormal = "normal"
    stBlock = "block"
    stLine = "line"

  ProcessHandle* = ref object
    process*: int
    refc*: int

  CursorState = object
    cursor: PagePos
    xend: int
    fromx: int
    fromy: int
    setx: int
    setxrefresh: bool
    setxsave: bool

  BufferConfig* = object
    refererFrom*: bool
    styling*: bool
    scripting*: ScriptingMode
    images*: bool
    headless*: HeadlessMode
    autofocus*: bool
    history*: bool
    markLinks*: bool
    charsetOverride*: Charset
    metaRefresh*: MetaRefresh
    charsets*: seq[Charset]
    imageTypes*: Table[string, string]
    userAgent*: string
    referrer*: string
    userStyle*: string

  BufferInitFlag* = enum
    bifSave, bifHTML, bifHistory, bifTailOnLoad, bifCrashed, bifHasStart,
    bifRedirected, bifMailcapCancel

  LoadState* = enum
    lsLoading = "loading"
    lsCanceled = "canceled"
    lsLoaded = "loaded"

  BufferConnectionResult* = enum
    bcrFail = "fail"
    bcrCancel = "cancel"
    bcrConnected = "connected"
    bcrSave = "save"
    bcrRedirect = "redirect"
    bcrUnauthorized = "unauthorized"
    bcrMailcap = "mailcap"

  Mark = object
    id: string
    pos: PagePos

  BufferInterface* = ref object of MapData
    map: seq[BufferIfaceItem]
    packetid: int
    packetBuffer: PacketBuffer
    lines: SimpleFlexibleGrid
    lineShift: int
    numLines* {.jsget.}: int
    pos: CursorState
    highlights: seq[Highlight]
    images*: seq[PosBitmap]
    hoverText*: array[HoverType, string]
    phandle*: ProcessHandle
    imageCache: ImageCache
    attrsp: ptr WindowAttributes
    requestedLines: Slice[int]
    bgcolor*: CellColor
    lastPeek: HoverType
    redraw*: bool
    refreshStatus*: bool
    dead* {.jsget.}: bool
    gotLines {.jsget.}: bool
    loadState* {.jsgetset.}: LoadState # private
    #TODO copy marks on clone
    tmpJumpMark: PagePos
    jumpMark: PagePos
    marks: seq[Mark]
    init*: BufferInit

  BufferInit* = ref object
    config*: BufferConfig
    loaderConfig*: LoaderClientConfig
    filterCmd*: string # filter command (called on load)
    startpos*: Option[CursorState]
    title: string
    # if set, this *overrides* any content type received from the network.
    # (this is because it stores the content type from the -T flag.)
    # beware, this string may include content type attributes, if you want
    # to match it you'll have to use contentType.untilLower(';').
    contentType* {.jsget.}: string
    loadInfo* {.jsgetset.}: string
    request*: Request # source request
    # note: this is not the same as request.url (but should be synced
    # with buffer.url)
    url* {.jsget.}: URL
    # note: this is *not* the same as Buffer.cacheId. buffer has the cache ID of
    # the output, while iface holds that of the input. Thus pager can
    # re-interpret the original input, and buffer can rewind the (potentially
    # mailcap) output.
    cacheId* {.jsget.}: int
    redirectDepth {.jsget.}: int
    width* {.jsgetset.}: int
    height* {.jsgetset.}: int
    flags*: set[BufferInitFlag]
    #TODO this is inaccurate, because charsetStack can desync
    charset*: Charset
    charsetStack*: seq[Charset]
    refreshUrl: URL
    refreshMillis: int
    connectedPtr: pointer # JSObject *
    # this really doesn't belong in here, but I don't want to expose
    # PosixStream to JS so instead I'll just smuggle it through init
    ostream*: PosixStream
    istreamOutputId*: int
    ostreamOutputId*: int

jsDestructor(BufferInterface)
jsDestructor(BufferInit)
jsDestructor(Highlight)

# Forward declarations
proc queueDraw*(iface: BufferInterface)
proc sendCursorPosition(iface: BufferInterface)
proc requestLinesFast*(iface: BufferInterface; force = false)

proc finalize(rt: JSRuntime; iface: BufferInterface) {.jsfin.} =
  for it in iface.map:
    if it.fun != nil:
      JS_FreeValueRT(rt, JS_MKPTR(JS_TAG_OBJECT, it.fun))

proc mark(rt: JSRuntime; iface: BufferInterface; markFunc: JS_MarkFunc)
    {.jsmark.} =
  for it in iface.map:
    if it.fun != nil:
      JS_MarkValue(rt, JS_MKPTR(JS_TAG_OBJECT, it.fun), markFunc)

proc finalize(rt: JSRuntime; init: BufferInit) {.jsfin.} =
  if init.connectedPtr != nil:
    JS_FreeValueRT(rt, JS_MKPTR(JS_TAG_OBJECT, init.connectedPtr))

proc mark(rt: JSRuntime; init: BufferInit; markFunc: JS_MarkFunc) {.jsmark.} =
  if init.connectedPtr != nil:
    JS_MarkValue(rt, JS_MKPTR(JS_TAG_OBJECT, init.connectedPtr), markFunc)

# BufferInit
proc newBufferInit*(config: BufferConfig; loaderConfig: LoaderClientConfig;
    url: URL; request: Request; attrs: WindowAttributes; title: string;
    redirectDepth: int; flags: set[BufferInitFlag];
    contentType, filterCmd: string; charsetStack: seq[Charset]): BufferInit =
  let cacheId = if request.url.schemeType == stCache:
    parseInt32(request.url.pathname).get(-1)
  else:
    -1
  let host = request.url.host
  let loadInfo = (if host != "":
    "Connecting to " & host
  else:
    "Loading " & $request.url) & "..."
  BufferInit(
    config: config,
    loaderConfig: loaderConfig,
    title: title,
    url: url,
    cacheId: cacheId,
    redirectDepth: redirectDepth,
    flags: flags,
    contentType: contentType,
    width: attrs.width,
    height: attrs.height - 1,
    request: request,
    charsetStack: charsetStack,
    loadInfo: loadInfo,
    refreshMillis: -1,
    filterCmd: filterCmd,
    istreamOutputId: -1
  )

proc newBufferInit*(url: URL; init: BufferInit): BufferInit {.jsctor.} =
  BufferInit(
    config: init.config,
    loaderConfig: init.loaderConfig,
    title: init.title,
    url: url,
    cacheId: init.cacheId,
    redirectDepth: init.redirectDepth,
    flags: init.flags,
    contentType: init.contentType,
    width: init.width,
    height: init.height,
    request: init.request,
    charsetStack: init.charsetStack,
    refreshMillis: -1,
    istreamOutputId: -1
  )

proc copyCursorPos(ctx: JSContext; this: BufferInit; val: JSValueConst):
    Opt[void] {.jsfunc.} =
  var iface: BufferInterface
  if ctx.fromJS(val, iface).isOk:
    if iface.init.startpos.isSome:
      this.startpos = iface.init.startpos
    else:
      this.startpos = some(iface.pos)
  else:
    var init: BufferInit
    ?ctx.fromJS(val, init)
    this.startpos = init.startpos
  # set a separate flag, because startpos may be already used (and
  # therefore unset) by the time hasStart is checked
  this.flags.incl(bifHasStart)
  ok()

proc hasStart(init: BufferInit): bool {.jsfget.} =
  bifHasStart in init.flags

proc history(init: BufferInit): bool {.jsfget.} =
  bifHistory in init.flags

proc scripting(init: BufferInit): ScriptingMode {.jsfget.} =
  init.config.scripting

proc charsetOverride(ctx: JSContext; init: BufferInit): JSValue {.jsfget.} =
  let charset = init.config.charsetOverride
  if charset != CHARSET_UNKNOWN:
    return ctx.toJS(charset)
  return JS_NULL

proc save(init: BufferInit): bool {.jsfget.} =
  bifSave in init.flags

proc setSave(init: BufferInit; b: bool) {.jsfset: "save".} =
  if b:
    init.flags.incl(bifSave)
  else:
    init.flags.excl(bifSave)

proc shortContentType(init: BufferInit): string {.jsfget.} =
  init.contentType.untilLower(';')

proc ishtml(init: BufferInit): bool {.jsfget.} =
  bifHTML in init.flags

proc cookie(init: BufferInit): CookieMode {.jsfget.} =
  init.loaderConfig.cookieMode

proc headless(init: BufferInit): HeadlessMode {.jsfget.} =
  init.config.headless

proc metaRefresh(init: BufferInit): MetaRefresh {.jsfget.} =
  init.config.metaRefresh

proc autofocus(init: BufferInit): bool {.jsfget.} =
  init.config.autofocus

proc images(init: BufferInit): bool {.jsfget.} =
  init.config.images

proc setImages(init: BufferInit; images: bool) {.jsfset: "images".} =
  init.config.images = images

proc title*(init: BufferInit): string {.jsfget.} =
  if init.title != "":
    return init.title
  return init.url.serialize(excludepassword = true)

proc setTitle(init: BufferInit; title: string) {.jsfset: "title".} =
  init.title = title

proc connected*(ctx: JSContext; init: BufferInit; res: BufferConnectionResult;
    arg1: JSValue): JSValue =
  if init.connectedPtr == nil:
    JS_FreeValue(ctx, arg1)
    return JS_UNDEFINED
  let fun = JS_MKPTR(JS_TAG_OBJECT, init.connectedPtr)
  init.connectedPtr = nil
  let this = ctx.toJS(init)
  if JS_IsException(this):
    ctx.freeValues(fun, arg1)
    return JS_EXCEPTION
  let arg0 = ctx.toJS(res)
  if JS_IsException(arg0):
    ctx.freeValues(fun, this, arg1)
    return JS_EXCEPTION
  return ctx.callSinkThisFree(fun, this, arg0, arg1)

proc setConnected(ctx: JSContext; init: BufferInit; connected: JSValueConst):
      JSValue {.jsfset: "connected".} =
  if not JS_IsFunction(ctx, connected):
    return JS_ThrowTypeError(ctx, "not a function")
  if init.connectedPtr != nil:
    return JS_ThrowTypeError(ctx, "connected is already set")
  let val = JS_DupValue(ctx, connected)
  init.connectedPtr = JS_VALUE_GET_PTR(val)
  return JS_DupValue(ctx, connected)

proc closeMailcap*(init: BufferInit) {.jsfunc.} =
  if init.ostream != nil:
    init.ostream.sclose()
    init.ostream = nil
  init.istreamOutputId = -1
  init.flags.incl(bifMailcapCancel)

# Apply data received in response.
# Note: pager must call this before checkMailcap.
proc applyResponse*(init: BufferInit; response: Response;
    mimeTypes: MimeTypesTable) =
  # accept cookies
  let cookieJar = init.loaderConfig.cookieJar
  if cookieJar != nil:
    cookieJar.setCookie(response.headers.getAllNoComma("Set-Cookie"),
      response.url, init.loaderConfig.cookieMode == cmSave, http = true)
  # set referrer policy, if any
  if init.config.refererFrom:
    let referrerPolicy = response.getReferrerPolicy()
    init.loaderConfig.referrerPolicy = referrerPolicy.get(DefaultPolicy)
  else:
    init.loaderConfig.referrerPolicy = rpNoReferrer
  # setup content type; note that isSome means an override so we skip it
  if init.contentType == "":
    var contentType = response.getLongContentType("application/octet-stream")
    if contentType.until(';') == "application/octet-stream":
      contentType = mimeTypes.guessContentType(init.url.pathname, "text/plain")
    init.contentType = move(contentType)
  # setup charsets:
  # * override charset
  # * network charset
  # * default charset guesses
  # HTML may override the last two (but not the override charset).
  if init.config.charsetOverride != CHARSET_UNKNOWN:
    init.charsetStack = @[init.config.charsetOverride]
  elif (let charset = response.getCharset(CHARSET_UNKNOWN);
      charset != CHARSET_UNKNOWN):
    init.charsetStack = @[charset]
  else:
    init.charsetStack = @[]
    for charset in init.config.charsets.ritems:
      init.charsetStack.add(charset)
    if init.charsetStack.len == 0:
      init.charsetStack.add(DefaultCharset)
  init.charset = init.charsetStack[^1]
  let refresh = parseRefresh(response.headers.getFirst("Refresh"), init.url)
  init.refreshUrl = refresh.url
  init.refreshMillis = refresh.n

# BufferInterface
proc newBufferInterface*(stream: SocketStream; register: BufferPacketFun;
    opaque: RootRef; phandle: ProcessHandle; attrsp: ptr WindowAttributes;
    init: BufferInit): BufferInterface =
  inc phandle.refc
  return BufferInterface(
    phandle: phandle,
    packetid: 1, # ids below 1 are invalid
    stream: stream,
    redraw: true,
    attrsp: attrsp,
    init: init,
    pos: CursorState(setx: -1),
    lastPeek: HoverType.high,
    packetBuffer: initPacketBuffer(register, opaque)
  )

proc newProcessHandle*(pid: int): ProcessHandle =
  ProcessHandle(process: pid)

proc process*(iface: BufferInterface): int {.jsfget.} =
  return iface.phandle.process

proc cursorx(iface: BufferInterface): int {.jsfget.} =
  return iface.pos.cursor.x

proc cursory*(iface: BufferInterface): int {.jsfget.} =
  return iface.pos.cursor.y

proc fromx*(iface: BufferInterface): int {.jsfget.} =
  return iface.pos.fromx

proc fromy*(iface: BufferInterface): int {.jsfget.} =
  return iface.pos.fromy

proc lineWindow(iface: BufferInterface): Slice[int] =
  let height = iface.init.height
  if iface.numLines == 0: # not loaded
    return 0 .. height * 5
  let n = (height * 5) div 2
  var x = iface.fromy - n + height div 2
  var y = iface.fromy + n + height div 2
  if y >= iface.numLines:
    x -= y - iface.numLines
    y = iface.numLines
  if x < 0:
    y += -x
    x = 0
  return x .. y

proc lastVisibleLine(iface: BufferInterface): int =
  min(iface.fromy + iface.init.height, iface.numLines) - 1

proc lineLoaded(iface: BufferInterface; y: int): bool =
  let dy = y - iface.lineShift
  return dy in 0 ..< iface.lines.len

proc getLine(iface: BufferInterface; y: int): lent SimpleFlexibleLine =
  if iface.lineLoaded(y):
    return iface.lines[y - iface.lineShift]
  let line {.global.} = SimpleFlexibleLine()
  return line

proc getLineStr(iface: BufferInterface; y: int): lent string =
  return iface.getLine(y).str

#TODO following procs should probably be computed on setCursorX for
# efficiency
# Returns the X position of the first cell occupied by the character the cursor
# currently points to.
proc cursorFirstX(iface: BufferInterface): int {.jsfget.} =
  let y = iface.cursory
  if not iface.lineLoaded(y):
    return 0
  let line = iface.getLineStr(y)
  var w = 0
  var i = 0
  let cc = iface.cursorx
  while i < line.len:
    let u = line.nextUTF8(i)
    let tw = u.width()
    if w + tw > cc:
      return w
    w += tw
  return w

# Returns the X position of the last cell occupied by the character the cursor
# currently points to.
proc cursorLastX(iface: BufferInterface): int {.jsfget.} =
  let y = iface.cursory
  if not iface.lineLoaded(y):
    return 0
  let line = iface.getLineStr(y)
  var w = 0
  var i = 0
  let cc = iface.cursorx
  while i < line.len and w <= cc:
    let u = line.nextUTF8(i)
    w += u.width()
  return max(w - 1, 0)

# Last cell for tab, first cell for everything else (e.g. double width.)
# This is needed because moving the cursor to the 2nd cell of a double
# width character clears it on some terminals.
proc cursorDispX(iface: BufferInterface): int =
  let y = iface.cursory
  if not iface.lineLoaded(y):
    return 0
  let line = iface.getLineStr(y)
  if line.len == 0:
    return 0
  var w = 0
  var pw = 0
  var i = 0
  var u = 0u32
  let cc = iface.cursorx
  while i < line.len and w <= cc:
    u = line.nextUTF8(i)
    pw = w
    w += u.width()
  if u == uint32('\t'):
    return max(w - 1, 0)
  return pw

#TODO cache
proc maxScreenWidth(iface: BufferInterface): int {.jsfunc.} =
  result = 0
  for y in iface.fromy..iface.lastVisibleLine:
    result = max(iface.getLineStr(y).width(), result)

proc currentLineWidth(iface: BufferInterface; s = 0; e = int.high): int
    {.jsfunc.} =
  let y = iface.cursory
  if not iface.lineLoaded(y):
    return 0
  return iface.getLineStr(y).width(s, e)

proc acursorx*(iface: BufferInterface): int {.jsfget.} =
  max(0, iface.cursorDispX() - iface.fromx)

proc acursory*(iface: BufferInterface): int {.jsfget.} =
  iface.cursory - iface.fromy

proc maxfromx(iface: BufferInterface): int =
  return max(iface.maxScreenWidth() - iface.init.width, 0)

proc maxfromy(iface: BufferInterface): int =
  return max(iface.numLines - iface.init.height, 0)

proc getHoverText*(iface: BufferInterface): string =
  for s in iface.hoverText:
    if s != "":
      return s
  ""

proc hoverLink(iface: BufferInterface): lent string {.jsfget.} =
  iface.hoverText[htLink]

proc hoverTitle(iface: BufferInterface): lent string {.jsfget.} =
  iface.hoverText[htTitle]

proc hoverImage(iface: BufferInterface): lent string {.jsfget.} =
  iface.hoverText[htImage]

proc hoverCachedImage(iface: BufferInterface): lent string {.jsfget.} =
  iface.hoverText[htCachedImage]

proc clearHover*(iface: BufferInterface) =
  iface.lastPeek = HoverType.high

proc getPeekCursorStr*(iface: BufferInterface): string =
  var p = iface.lastPeek
  while true:
    if p < HoverType.high:
      inc p
    else:
      p = HoverType.low
    if iface.hoverText[p] != "" or p == iface.lastPeek:
      break
  let s = iface.hoverText[p]
  iface.lastPeek = p
  s

# Marks
proc markPos0(iface: BufferInterface) {.jsfunc.} =
  iface.tmpJumpMark = (iface.cursorx, iface.cursory)

proc markPos(iface: BufferInterface) {.jsfunc.} =
  let pos = iface.tmpJumpMark
  if iface.cursorx != pos.x or iface.cursory != pos.y:
    iface.jumpMark = pos

proc findMark(iface: BufferInterface; id: string): int =
  for i, it in iface.marks.mypairs:
    if it.id == id:
      return i
  -1

proc setMark(iface: BufferInterface; id: string; x, y: int): bool {.jsfunc.} =
  let i = iface.findMark(id)
  if i != -1:
    iface.marks[i].pos = (x, y)
  else:
    iface.marks.add(Mark(id: id, pos: (x, y)))
  iface.queueDraw()
  i == -1

proc clearMark(iface: BufferInterface; id: string): bool {.jsfunc.} =
  let i = iface.findMark(id)
  if i != -1:
    iface.marks.del(i)
    iface.queueDraw()
  i != -1

proc getMarkPos(ctx: JSContext; iface: BufferInterface; id: string): JSValue
    {.jsfunc.} =
  if id == "`" or id == "'":
    return ctx.toJS(iface.jumpMark)
  let i = iface.findMark(id)
  if i != -1:
    return ctx.toJS(iface.marks[i].pos)
  return JS_NULL

proc findNextMark(ctx: JSContext; iface: BufferInterface; x, y: int): JSValue
    {.jsfunc.} =
  var best: PagePos = (int.high, int.high)
  var j = -1
  for i, mark in iface.marks.mypairs:
    if mark.pos.y < y or mark.pos.y == y and mark.pos.x <= x:
      continue
    if mark.pos.y < best.y or mark.pos.y == best.y and mark.pos.x < best.x:
      best = mark.pos
      j = i
  if j != -1:
    return ctx.toJS(iface.marks[j].id)
  return JS_NULL

proc findPrevMark(ctx: JSContext; iface: BufferInterface; x, y: int): JSValue
    {.jsfunc.} =
  var best: PagePos = (-1, -1)
  var j = -1
  for i, mark in iface.marks.mypairs:
    if mark.pos.y > y or mark.pos.y == y and mark.pos.x >= x:
      continue
    if mark.pos.y > best.y or mark.pos.y == best.y and mark.pos.x > best.x:
      best = mark.pos
      j = i
  if j != -1:
    return ctx.toJS(iface.marks[j].id)
  return JS_NULL

proc setFromY(iface: BufferInterface; y: int) {.jsfunc.} =
  if iface.pos.fromy != y:
    iface.pos.fromy = max(min(y, iface.maxfromy), 0)
    iface.requestLinesFast()
    iface.queueDraw()

proc setFromX(iface: BufferInterface; x: int; refresh = true) {.jsfunc.} =
  if iface.pos.fromx != x:
    iface.pos.fromx = max(min(x, iface.maxfromx), 0)
    if iface.pos.fromx > iface.cursorx:
      iface.pos.cursor.x = min(iface.pos.fromx, iface.currentLineWidth())
      if refresh:
        iface.sendCursorPosition()
    iface.queueDraw()

# Set the cursor to the xth column. 0-based.
# * `refresh = false' inhibits reporting of the cursor position to the buffer.
# * `save = false' inhibits cursor movement if it is currently outside the
#   screen, and makes it so cursorx is not saved for restoration on cursory
#   movement.
proc setCursorX(iface: BufferInterface; x: int; refresh, save: bool)
    {.jsfunc.} =
  if not iface.lineLoaded(iface.cursory):
    iface.pos.setx = x
    iface.pos.setxrefresh = refresh
    iface.pos.setxsave = save
    return
  iface.pos.setx = -1
  let cw = iface.currentLineWidth()
  let x2 = x
  let x = max(min(x, cw - 1), 0)
  # we check for save here, because it is only set by restoreCursorX where
  # we do not want to move the cursor just because it is outside the window.
  if not save or iface.fromx <= x and x < iface.fromx + iface.init.width:
    iface.pos.cursor.x = x
  elif save and iface.fromx > x:
    # target x is before the screen start
    if x2 < iface.cursorx:
      # desired X position is lower than cursor X; move screen back to the
      # desired position if valid, to 0 if the desired position is less than 0,
      # otherwise the last cell of the current line.
      if x2 <= x:
        iface.setFromX(x, false)
      else:
        iface.setFromX(cw - 1, false)
    # take whatever position the jump has resulted in.
    iface.pos.cursor.x = iface.fromx
  elif x > iface.cursorx:
    # target x is greater than current x; a simple case, just shift fromx too
    # accordingly
    iface.setFromX(max(x - iface.init.width + 1, iface.fromx), false)
    iface.pos.cursor.x = x
  if save:
    iface.pos.xend = iface.cursorx
  if refresh:
    iface.sendCursorPosition()

proc setCursorY(iface: BufferInterface; y: int; refresh = true) {.jsfunc.} =
  let y = max(min(y, iface.numLines - 1), 0)
  if y >= iface.fromy and y - iface.init.height < iface.fromy:
    discard
  elif y > iface.cursory:
    iface.setFromY(y - iface.init.height + 1)
  else:
    iface.setFromY(y)
  if iface.cursory != y:
    iface.pos.cursor.y = y
    iface.setCursorX(iface.pos.xend, false, false)
    if refresh:
      iface.sendCursorPosition()

# Send/receive packets
const ClickResultReadLine* = {crtReadText, crtReadPassword, crtReadFile}

proc initClickResult*(): ClickResult =
  ClickResult(t: crtNone)

proc initClickResult*(open: Request; contentType = ""): ClickResult =
  if open == nil:
    return initClickResult()
  return ClickResult(t: crtOpen, open: open, contentType: contentType)

proc initClickResult*(options: seq[SelectOption]; selected: int):
    ClickResult =
  if options.len == 0:
    return initClickResult()
  return ClickResult(t: crtSelect, options: options, selected: selected)

proc sread*(r: var PacketReader; x: var ClickResult) =
  var t0: ClickResultType
  r.sread(t0)
  let t = t0
  case t
  of crtNone: x = initClickResult()
  of crtOpen:
    var open: Request
    var contentType: string
    r.sread(open)
    r.sread(contentType)
    x = initClickResult(open, contentType)
  of crtReadArea, crtReadText, crtReadPassword, crtReadFile:
    var prompt: string
    var value: string
    r.sread(prompt)
    r.sread(value)
    x = ClickResult(t: t, prompt: prompt, value: value)
  of crtSelect:
    var options: seq[SelectOption]
    var selected: int
    r.sread(options)
    r.sread(selected)
    x = initClickResult(options, selected)

proc swrite*(w: var PacketWriter; x: ClickResult) =
  w.swrite(x.t)
  case x.t
  of crtNone: discard
  of crtOpen:
    w.swrite(x.open)
    w.swrite(x.contentType)
  of crtReadArea, crtReadText, crtReadPassword, crtReadFile:
    w.swrite(x.prompt)
    w.swrite(x.value)
  of crtSelect:
    w.swrite(x.options)
    w.swrite(x.selected)

proc toJS(ctx: JSContext; x: ClickResult): JSValue =
  if x.t == crtNone:
    return JS_NULL
  let obj = JS_NewObject(ctx)
  if JS_IsException(obj):
    return JS_EXCEPTION
  block good:
    if ctx.definePropertyConvert(obj, "t", x.t) == dprException:
      break good
    case x.t
    of crtNone: discard
    of crtOpen:
      let open = x.open.toPagerJSRequest()
      if ctx.definePropertyConvert(obj, "open", open) == dprException:
        break good
      if ctx.definePropertyConvert(obj, "contentType", x.contentType) ==
          dprException:
        break good
    of crtSelect:
      if ctx.definePropertyConvert(obj, "selected", x.selected) == dprException:
        break good
      if ctx.definePropertyConvert(obj, "options", x.options) == dprException:
        break good
    of crtReadText, crtReadPassword, crtReadArea, crtReadFile:
      if ctx.definePropertyConvert(obj, "prompt", x.prompt) == dprException:
        break good
      if ctx.definePropertyConvert(obj, "value", x.value) == dprException:
        break good
    return obj
  JS_FreeValue(ctx, obj)
  return JS_EXCEPTION

proc toJS(ctx: JSContext; res: GotoAnchorResult): JSValue =
  var init = [JS_UNDEFINED, JS_UNDEFINED, JS_UNDEFINED]
  block good:
    init[0] = ctx.toJS(res.x)
    if JS_IsException(init[0]):
      break good
    init[1] = ctx.toJS(res.y)
    if JS_IsException(init[1]):
      break good
    init[2] = ctx.toJS(res.focus)
    if JS_IsException(init[2]):
      break good
    return ctx.newArrayFrom(init)
  ctx.freeValues(init)
  return JS_EXCEPTION

proc toJS(ctx: JSContext; x: CursorXY): JSValue =
  let obj = JS_NewObject(ctx)
  if JS_IsException(obj):
    return JS_EXCEPTION
  block good:
    if ctx.definePropertyCWE(obj, "x", ctx.toJS(x.x)) == dprException:
      break good
    if ctx.definePropertyCWE(obj, "y", ctx.toJS(x.y)) == dprException:
      break good
    return obj
  JS_FreeValue(ctx, obj)
  return JS_EXCEPTION

proc toJS(ctx: JSContext; match: BufferMatch): JSValue =
  var init = [JS_UNDEFINED, JS_UNDEFINED, JS_UNDEFINED]
  block good:
    init[0] = ctx.toJS(match.x)
    if JS_IsException(init[0]):
      break good
    init[1] = ctx.toJS(match.y)
    if JS_IsException(init[1]):
      break good
    init[2] = ctx.toJS(match.w)
    if JS_IsException(init[2]):
      break good
    return ctx.newArrayFrom(init)
  ctx.freeValues(init)
  return JS_EXCEPTION

proc findPromise(iface: BufferInterface; id: int): int =
  for i, it in iface.map.mypairs:
    if it.id == id:
      return i
  return -1

type IfaceResult* = enum
  irOk, irException, irEOF

# Returns false on I/O error, err on JS error.
proc handleCommand*(ctx: JSContext; iface: BufferInterface): IfaceResult =
  assert not iface.dead
  iface.stream.withPacketReader r:
    var packetid: int
    r.sread(packetid)
    let i = iface.findPromise(packetid)
    var res = irOk
    if i != -1:
      let it = iface.map[i]
      let val = if it.get == nil:
        JS_UNDEFINED
      else:
        it.get(ctx, iface, r)
      if not JS_IsException(val) and it.fun != nil:
        let fun = JS_MKPTR(JS_TAG_OBJECT, it.fun)
        let ret = ctx.callSinkFree(fun, JS_UNDEFINED, val)
        if JS_IsException(ret):
          res = irException
        JS_FreeValue(ctx, ret)
      else:
        if it.fun != nil:
          JS_FreeValue(ctx, JS_MKPTR(JS_TAG_OBJECT, it.fun))
        res = irException
      iface.map.del(i)
  do:
    return irEOF
  irOk

proc flushWrite*(iface: BufferInterface): bool =
  iface.packetBuffer.registered = false
  return iface.packetBuffer.flush(iface.stream)

proc hasPromises(iface: BufferInterface): bool =
  return iface.map.len > 0

proc getFromStream[T](ctx: JSContext; iface: BufferInterface;
    r: var PacketReader): JSValue =
  var res: T
  r.sread(res)
  return ctx.toJS(res)

proc addPromise(ctx: JSContext; iface: BufferInterface; get: GetValueProc):
    JSValue =
  var resolvingFuncs {.noinit.}: array[2, JSValue]
  let res = JS_NewPromiseCapability(ctx, resolvingFuncs.toJSValueArray())
  if JS_IsException(res):
    return res
  JS_FreeValue(ctx, resolvingFuncs[1])
  iface.map.add(BufferIfaceItem(
    id: iface.packetid,
    fun: JS_VALUE_GET_PTR(resolvingFuncs[0]),
    get: get
  ))
  inc iface.packetid
  return res

proc addPromise(iface: BufferInterface; get: GetValueProc) =
  iface.map.add(BufferIfaceItem(
    id: iface.packetid,
    fun: nil,
    get: get
  ))
  inc iface.packetid

proc addPromise[T](ctx: JSContext; iface: BufferInterface): JSValue =
  return ctx.addPromise(iface, getFromStream[T])

proc addEmptyPromise(ctx: JSContext; iface: BufferInterface): JSValue =
  return ctx.addPromise(iface, nil)

iterator ilines(iface: BufferInterface; slice: Slice[int]):
    lent SimpleFlexibleLine {.inline.} =
  for y in slice:
    yield iface.getLine(y)

proc findColStartByte(s: string; endx: int): int =
  var w = 0
  var i = 0
  while i < s.len and w < endx:
    let pi = i
    let u = s.nextUTF8(i)
    w += u.width()
    if w > endx:
      return pi
  return i

proc cursorStartByte(iface: BufferInterface; y, cc: int): int =
  return iface.getLineStr(y).findColStartByte(cc)

proc findColBytes*(s: string; endx: int; startx = 0; starti = 0): int =
  var w = startx
  var i = starti
  while i < s.len and w < endx:
    let u = s.nextUTF8(i)
    w += u.width()
  return i

proc cursorBytes(iface: BufferInterface; y, cc: int): int {.jsfunc.} =
  return iface.getLineStr(y).findColBytes(cc, 0, 0)

proc atPercentOf*(iface: BufferInterface): int =
  if iface.numLines == 0:
    return 100
  return (100 * (iface.cursory + 1)) div iface.numLines

proc initPacketWriter(iface: BufferInterface; cmd: BufferCommand):
    PacketWriter =
  result = initPacketWriter()
  result.swrite(cmd)
  result.swrite(iface.packetid)

proc flush(ctx: JSContext; iface: BufferInterface; w: var PacketWriter): bool =
  if iface.dead or not iface.packetBuffer.flush(w, iface.stream):
    JS_ThrowTypeError(ctx, "buffer %d disconnected", cint(iface.phandle.process))
    return false
  return true

template withPacketWriter(ctx: JSContext; iface: BufferInterface;
    cmd: BufferCommand; w, body: untyped) =
  var w = iface.initPacketWriter(cmd)
  body
  if not flush(ctx, iface, w):
    return JS_EXCEPTION

template withPacketWriter(iface: BufferInterface; cmd: BufferCommand;
    w, body, fallback: untyped) =
  var w = iface.initPacketWriter(cmd)
  body
  if iface.dead or not iface.packetBuffer.flush(w, iface.stream):
    fallback

template withPacketWriterSync(iface: BufferInterface; cmd: BufferCommand;
    w, body, fallback: untyped) =
  var w = iface.initPacketWriter(cmd)
  body
  if iface.dead or not w.flush(iface.stream):
    fallback

proc cancel*(iface: BufferInterface) {.jsfunc.} =
  iface.withPacketWriter bcCancel, w:
    discard
  do:
    return
  iface.addPromise(nil)

proc checkRefresh(ctx: JSContext; iface: BufferInterface): JSValue {.jsfunc.} =
  let refreshMillis = iface.init.refreshMillis
  if refreshMillis >= 0:
    iface.init.refreshMillis = -1
    return ctx.toJS((n: refreshMillis, url: move(iface.init.refreshUrl)))
  ctx.withPacketWriter iface, bcCheckRefresh, w:
    discard
  return addPromise[CheckRefreshResult](ctx, iface)

proc click(ctx: JSContext; iface: BufferInterface; x, y, n: int): JSValue {.
    jsfunc.} =
  ctx.withPacketWriter iface, bcClick, w:
    w.swrite(x)
    w.swrite(y)
    w.swrite(n)
  return addPromise[ClickResult](ctx, iface)

proc clone*(iface: BufferInterface; newurl: URL; pstreamFd: cint): Opt[void] =
  iface.withPacketWriter bcClone, w:
    w.swrite(newurl)
    w.sendFd(pstreamFd)
  do:
    return err()
  iface.addPromise(nil)
  ok()

proc contextMenu(ctx: JSContext; iface: BufferInterface; cursorx, cursory: int):
    JSValue {.jsfunc.} =
  ctx.withPacketWriter iface, bcContextMenu, w:
    w.swrite(cursorx)
    w.swrite(cursory)
  return addPromise[bool](ctx, iface)

proc findNextLink(ctx: JSContext; iface: BufferInterface; x, y, n: int): JSValue
    {.jsfunc.} =
  ctx.withPacketWriter iface, bcFindNextLink, w:
    w.swrite(x)
    w.swrite(y)
    w.swrite(n)
  return addPromise[PagePos](ctx, iface)

proc findNextMatch(ctx: JSContext; iface: BufferInterface; re: JSValueConst;
    x, y: int; wrap: bool; n: int): JSValue {.jsfunc.} =
  var bytecodeLen: csize_t
  let p = JS_GetRegExpBytecode(ctx, re, bytecodeLen)
  if p == nil:
    return JS_EXCEPTION
  let bytecode = cast[REBytecode](p)
  var wrap = wrap
  let endy = y
  var y = y
  var n = n
  var b = iface.cursorBytes(y, x + 1)
  var first = true
  while true:
    if y >= iface.numLines:
      if not wrap:
        break
      wrap = false
      y = 0
    if not iface.lineLoaded(y):
      let regex = bytecodeToRegex(bytecode, bytecodeLen)
      ctx.withPacketWriter iface, bcFindNextMatch, w:
        w.swrite(regex)
        w.swrite(x)
        w.swrite(y)
        w.swrite(endy)
        w.swrite(wrap)
        w.swrite(n)
      return addPromise[BufferMatch](ctx, iface)
    let s = iface.getLineStr(y)
    let cap = bytecode.matchFirst(s, b)
    if cap.s >= 0:
      let x = s.width(0, cap.s)
      let w = s.toOpenArray(cap.s, cap.e - 1).width()
      dec n
      if n == 0:
        return ctx.toJS(BufferMatch(x: x, y: y, w: w))
    b = 0
    if y == endy and not first:
      break
    first = false
    inc y
  return ctx.toJS(BufferMatch(x: -1, y: -1))

proc findNextParagraph(ctx: JSContext; iface: BufferInterface; y, n: int):
    JSValue {.jsfunc.} =
  ctx.withPacketWriter iface, bcFindNextParagraph, w:
    w.swrite(y)
    w.swrite(n)
  return addPromise[int](ctx, iface)

#TODO findPrevLink & findRevNthLink should probably be merged into findNextLink
proc findPrevLink(ctx: JSContext; iface: BufferInterface; x, y, n: int):
    JSValue {.jsfunc.} =
  ctx.withPacketWriter iface, bcFindPrevLink, w:
    w.swrite(x)
    w.swrite(y)
    w.swrite(n)
  return addPromise[PagePos](ctx, iface)

proc findPrevMatch(ctx: JSContext; iface: BufferInterface; re: JSValueConst;
    x, y: int; wrap: bool; n: int): JSValue {.jsfunc.} =
  var bytecodeLen: csize_t
  let p = JS_GetRegExpBytecode(ctx, re, bytecodeLen)
  if p == nil:
    return JS_EXCEPTION
  let bytecode = cast[REBytecode](p)
  var wrap = wrap
  let endy = y
  var n = n
  var y = y
  var b = iface.cursorStartByte(y, x)
  var first = true
  while true:
    if y < 0:
      if not wrap:
        break
      y = iface.numLines - 1
      wrap = false
    if not iface.lineLoaded(y):
      let regex = bytecodeToRegex(bytecode, bytecodeLen)
      ctx.withPacketWriter iface, bcFindPrevMatch, w:
        w.swrite(regex)
        w.swrite(x)
        w.swrite(y)
        w.swrite(endy)
        w.swrite(wrap)
        w.swrite(n)
      return addPromise[BufferMatch](ctx, iface)
    let s = iface.getLineStr(y)
    if b < 0:
      b = s.len
    let cap = bytecode.matchLast(s.toOpenArray(0, b - 1))
    if cap.s >= 0:
      let x = s.width(0, cap.s)
      let w = s.toOpenArray(cap.s, cap.e - 1).width()
      dec n
      if n == 0:
        return ctx.toJS(BufferMatch(x: x, y: y, w: w))
    dec y
    if y == endy and not first:
      break
    first = false
    b = -1
  return ctx.toJS(BufferMatch(x: -1, y: -1))

proc findRevNthLink(ctx: JSContext; iface: BufferInterface; x, y, n: int):
    JSValue {.jsfunc.} =
  ctx.withPacketWriter iface, bcFindPrevLink, w:
    w.swrite(x)
    w.swrite(y)
    w.swrite(n)
  return addPromise[PagePos](ctx, iface)

proc forceReshape(ctx: JSContext; iface: BufferInterface): JSValue {.jsfunc.} =
  ctx.withPacketWriter iface, bcForceReshape, w:
    discard
  return addEmptyPromise(ctx, iface)

proc getLinesFromStream(ctx: JSContext; iface: BufferInterface;
    r: var PacketReader): JSValue =
  iface.gotLines = true
  let oldBgcolor = iface.bgcolor
  let oldNumLines = iface.numLines
  r.sread(iface.lineShift)
  r.sread(iface.numLines)
  r.sread(iface.bgcolor)
  r.sread(iface.lines)
  r.sread(iface.images)
  if iface.pos.setx >= 0:
    iface.setCursorX(iface.pos.setx, iface.pos.setxrefresh, iface.pos.setxsave)
  if oldNumLines != iface.numLines:
    if iface.fromy > iface.maxfromy:
      iface.setFromY(iface.maxfromy)
    if iface.cursory >= iface.numLines:
      let n = max(iface.lastVisibleLine, 0)
      if iface.cursory != n:
        iface.setCursorY(n)
        iface.refreshStatus = true
    if iface.init.startpos.isSome and
        iface.numLines >= iface.init.startpos.get.cursor.y:
      iface.pos = iface.init.startpos.get
      iface.requestLinesFast()
      iface.init.startpos = none(CursorState)
      iface.sendCursorPosition()
    if iface.loadState != lsLoading:
      iface.refreshStatus = true
    if bifTailOnLoad in iface.init.flags:
      iface.setCursorY(int.high)
      iface.refreshStatus = true
      iface.init.flags.excl(bifTailOnLoad)
  let slice = iface.lineShift ..< iface.lineShift + iface.lines.len
  if slice.b >= iface.fromy and slice.a <= iface.fromy + iface.init.height or
      oldBgcolor != iface.bgcolor:
    iface.queueDraw()
  return JS_UNDEFINED

proc requestLinesFast*(iface: BufferInterface; force = false) =
  let slice = iface.lineWindow
  if not force and iface.requestedLines == slice:
    return
  iface.requestedLines = slice
  iface.withPacketWriter bcGetLines, w:
    w.swrite(slice)
  do:
    return
  iface.addPromise(getLinesFromStream)

proc requestLines(ctx: JSContext; iface: BufferInterface; force = false):
    JSValue {.jsfunc.} =
  let slice = iface.lineWindow
  if not force and iface.requestedLines == slice:
    return JS_UNDEFINED
  iface.requestedLines = slice
  ctx.withPacketWriter iface, bcGetLines, w:
    w.swrite(slice)
  return ctx.addPromise(iface, getLinesFromStream)

# dump mode
type HandleReadLine = proc(line: SimpleFlexibleLine): Opt[void]

# Synchronously read all lines in the buffer.
proc requestLinesSync*(ctx: JSContext; iface: BufferInterface;
    handle: HandleReadLine): IfaceResult =
  if iface.dead:
    return irEOF
  iface.stream.setBlocking(true)
  while iface.hasPromises:
    # fulfill all promises
    let res = ctx.handleCommand(iface)
    if res != irOk:
      return res
  var slice = 0 .. 23
  while true:
    let packetid = iface.packetid
    iface.withPacketWriterSync bcGetLines, w:
      w.swrite(slice)
    do:
      return irEOF
    inc iface.packetid
    iface.stream.withPacketReader r:
      var packetid2: int
      r.sread(packetid2)
      assert packetid == packetid2
      r.sread(iface.lineShift)
      r.sread(iface.numLines)
      r.sread(iface.bgcolor)
      r.sread(iface.lines)
      r.sread(iface.images)
    do:
      return irEOF
    for line in iface.lines:
      if handle(line).isErr:
        return irEOF
    if iface.numLines <= slice.b:
      break
    slice.a += 24
    slice.b += 24
  if iface.init.config.markLinks:
    # avoid coloring link markers
    iface.bgcolor = defaultColor
    if handle(SimpleFlexibleLine()).isErr:
      return irEOF
    let packetid = iface.packetid
    iface.withPacketWriterSync bcGetLinks, w:
      discard
    do:
      return irEOF
    inc iface.packetid
    var links: seq[string]
    iface.stream.withPacketReaderFire r:
      var packetid2: int
      r.sread(packetid2)
      assert packetid == packetid2
      r.sread(links)
    for i, link in links.mypairs:
      var s = "[" & $(i + 1) & "] " & link
      if handle(SimpleFlexibleLine(str: move(s))).isErr:
        return irEOF
  irOk

proc getSelectionText(ctx: JSContext; iface: BufferInterface;
    sx, sy, ex, ey: int; t: SelectionType): JSValue {.jsfunc.} =
  ctx.withPacketWriter iface, bcGetSelectionText, w:
    w.swrite(sx)
    w.swrite(sy)
    w.swrite(ex)
    w.swrite(ey)
    w.swrite(t)
  return addPromise[string](ctx, iface)

proc getTitle(ctx: JSContext; iface: BufferInterface): JSValue {.jsfunc.} =
  ctx.withPacketWriter iface, bcGetTitle, w:
    discard
  return addPromise[string](ctx, iface)

proc gotoAnchor(ctx: JSContext; iface: BufferInterface; anchor: string;
    autofocus, target: bool): JSValue {.jsfunc.} =
  ctx.withPacketWriter iface, bcGotoAnchor, w:
    w.swrite(anchor)
    w.swrite(autofocus)
    w.swrite(target)
  return addPromise[GotoAnchorResult](ctx, iface)

proc hideHints(ctx: JSContext; iface: BufferInterface): JSValue {.jsfunc.} =
  ctx.withPacketWriter iface, bcHideHints, w:
    discard
  return addEmptyPromise(ctx, iface)

proc load(ctx: JSContext; iface: BufferInterface): JSValue {.jsfunc.} =
  ctx.withPacketWriter iface, bcLoad, w:
    discard
  return addPromise[LoadResult](ctx, iface)

proc markURL(ctx: JSContext; iface: BufferInterface): JSValue {.jsfunc.} =
  ctx.withPacketWriter iface, bcMarkURL, w:
    discard
  return addEmptyPromise(ctx, iface)

proc onReshape(ctx: JSContext; iface: BufferInterface): JSValue {.jsfunc.} =
  ctx.withPacketWriter iface, bcOnReshape, w:
    discard
  return addEmptyPromise(ctx, iface)

proc readCanceled(ctx: JSContext; iface: BufferInterface): JSValue {.jsfunc.} =
  ctx.withPacketWriter iface, bcReadCanceled, w:
    discard
  return addEmptyPromise(ctx, iface)

proc readSuccess(ctx: JSContext; iface: BufferInterface; s: string; fd: cint):
    JSValue {.jsfunc.} =
  if iface.stream.flush().isErr:
    return JS_UNDEFINED
  ctx.withPacketWriter iface, bcReadSuccess, w:
    w.swrite(s)
    let hasfd = fd != -1
    w.swrite(hasfd)
    if hasfd:
      w.sendFd(fd)
  return addPromise[ClickResult](ctx, iface)

proc select(ctx: JSContext; iface: BufferInterface; selected: int): JSValue
    {.jsfunc.} =
  ctx.withPacketWriter iface, bcSelect, w:
    w.swrite(selected)
  return addPromise[ClickResult](ctx, iface)

proc showHints(ctx: JSContext; iface: BufferInterface; sx, sy, ex, ey: int):
    JSValue {.jsfunc.} =
  ctx.withPacketWriter iface, bcShowHints, w:
    w.swrite(sx)
    w.swrite(sy)
    w.swrite(ex)
    w.swrite(ey)
  return addPromise[HintResult](ctx, iface)

proc submitForm(ctx: JSContext; iface: BufferInterface; x, y: int): JSValue {.
    jsfunc.} =
  ctx.withPacketWriter iface, bcSubmitForm, w:
    w.swrite(x)
    w.swrite(y)
  return addPromise[ClickResult](ctx, iface)

proc toggleImages(ctx: JSContext; iface: BufferInterface): JSValue {.jsfunc.} =
  ctx.withPacketWriter iface, bcToggleImages, w:
    discard
  return addPromise[bool](ctx, iface)

proc updateHoverFromStream(ctx: JSContext; iface: BufferInterface;
    r: var PacketReader): JSValue =
  var res: UpdateHoverResult
  r.sread(res)
  if res.len > 0:
    assert res.high <= int(HoverType.high)
    for (ht, s) in res:
      iface.hoverText[ht] = s
    iface.refreshStatus = true
  return JS_UNDEFINED

proc sendCursorPosition(iface: BufferInterface) {.jsfunc.} =
  iface.withPacketWriter bcUpdateHover, w:
    w.swrite(iface.cursorx)
    w.swrite(iface.cursory)
  do:
    return
  iface.addPromise(updateHoverFromStream)

proc windowChange(ctx: JSContext; iface: BufferInterface; x, y: int): JSValue
    {.jsfunc.} =
  var attrs = iface.attrsp[]
  # subtract status line height
  attrs.height -= 1
  attrs.heightPx -= attrs.ppl
  ctx.withPacketWriter iface, bcWindowChange, w:
    w.swrite(attrs)
    w.swrite(x)
    w.swrite(y)
  return addPromise[PagePos](ctx, iface)

proc matchFirst(ctx: JSContext; iface: BufferInterface; re: JSValueConst;
    y: int): JSValue {.jsfunc.} =
  if not iface.lineLoaded(y):
    return ctx.toJS((-1, -1))
  var plen: csize_t
  let p = JS_GetRegExpBytecode(ctx, re, plen)
  if p == nil:
    return JS_EXCEPTION
  return ctx.toJS(cast[REBytecode](p).matchFirst(iface.getLineStr(y)))

# Highlight (search/selection)
proc startx(hl: Highlight): int {.jsfget.} =
  if hl.y1 < hl.y2:
    hl.x1
  elif hl.y2 < hl.y1:
    hl.x2
  else:
    min(hl.x1, hl.x2)

proc starty(hl: Highlight): int {.jsfget.} =
  return min(hl.y1, hl.y2)

proc endx(hl: Highlight): int {.jsfget.} =
  if hl.y1 > hl.y2:
    hl.x1
  elif hl.y2 > hl.y1:
    hl.x2
  else:
    max(hl.x1, hl.x2)

proc endy(hl: Highlight): int {.jsfget.} =
  return max(hl.y1, hl.y2)

proc clearSearchHighlights(iface: BufferInterface) {.jsfunc.} =
  for i in countdown(iface.highlights.high, 0):
    if iface.highlights[i].t == hltSearch:
      iface.highlights.del(i)
  iface.queueDraw()

proc addSearchHighlight(iface: BufferInterface; x1, y1, x2, y2: int) {.
    jsfunc.} =
  iface.highlights.add(Highlight(
    t: hltSearch,
    x1: x1,
    y1: y1,
    x2: x2,
    y2: y2
  ))
  iface.queueDraw()

proc startSelection(iface: BufferInterface; t: SelectionType; mouse: bool;
    x1, y1, x2, y2: int): Highlight {.jsfunc.} =
  let highlight = Highlight(
    t: hltSelect,
    selectionType: t,
    x1: x1,
    y1: y1,
    x2: x2,
    y2: y2,
    mouse: mouse
  )
  iface.highlights.add(highlight)
  iface.queueDraw()
  return highlight

proc removeHighlight(iface: BufferInterface; highlight: Highlight) {.jsfunc.} =
  let i = iface.highlights.find(highlight)
  if i != -1:
    iface.highlights.delete(i)
  iface.queueDraw()

# Image
iterator cachedImages(iface: BufferInterface): CachedImage =
  var it = iface.imageCache.head
  while it != nil:
    yield it
    it = it.next

proc findCachedImage*(iface: BufferInterface;
    imageId, width, height, offx, erry, dispw: int): CachedImage =
  for it in iface.cachedImages:
    if it.bmp.imageId == imageId and it.width == width and
        it.height == height and it.offx == offx and it.erry == erry and
        it.dispw == dispw:
      return it
  return nil

proc clearCachedImages*(iface: BufferInterface; loader: FileLoader) =
  for cachedImage in iface.cachedImages:
    if cachedImage.state == cisLoaded:
      loader.removeCachedItem(cachedImage.cacheId)
    cachedImage.state = cisCanceled
  iface.imageCache.head = nil
  iface.imageCache.tail = nil

proc addCachedImage*(iface: BufferInterface; image: CachedImage) =
  if iface.imageCache.tail == nil:
    iface.imageCache.head = image
  else:
    iface.imageCache.tail.next = image
  iface.imageCache.tail = image

# Display
proc queueDraw*(iface: BufferInterface) {.jsfunc.} =
  iface.redraw = true

proc colorNormal(iface: BufferInterface; hl: Highlight; y: int;
    limitx: Slice[int]): Slice[int] =
  let starty = hl.starty
  let endy = hl.endy
  if y in starty + 1 .. endy - 1:
    let w = iface.getLineStr(y).width()
    return min(limitx.a, w) .. min(limitx.b, w)
  if y == starty and y == endy:
    return max(hl.startx, limitx.a) .. min(hl.endx, limitx.b)
  if y == starty:
    let w = iface.getLineStr(y).width()
    return max(hl.startx, limitx.a) .. min(limitx.b, w)
  if y == endy:
    let w = iface.getLineStr(y).width()
    return min(limitx.a, w) .. min(hl.endx, limitx.b)
  0 .. 0

proc colorArea(iface: BufferInterface; hl: Highlight; y: int;
    limitx: Slice[int]): Slice[int] =
  case hl.selectionType
  of stNormal:
    return iface.colorNormal(hl, y, limitx)
  of stBlock:
    if y in hl.starty .. hl.endy:
      return max(hl.startx, limitx.a) .. min(hl.endx, limitx.b)
    return 0 .. 0
  of stLine:
    if y in hl.starty .. hl.endy:
      let w = iface.getLineStr(y).width()
      return min(limitx.a, w) .. min(limitx.b, w)
    return 0 .. 0

proc highlightMarks*(iface: BufferInterface; display: var FixedGrid;
    hlcolor: CellColor) =
  for mark in iface.marks:
    if mark.pos.x in iface.fromx ..< iface.fromx + display.width and
        mark.pos.y in iface.fromy ..< iface.fromy + display.height:
      let x = mark.pos.x - iface.fromx
      let y = mark.pos.y - iface.fromy
      let n = y * display.width + x
      if hlcolor != defaultColor:
        display[n].format.bgcolor = hlcolor
      else:
        display[n].format.incl(ffReverse)

proc setFormat(cell: var FixedCell; cf: SimpleFormatCell; bgcolor: CellColor) =
  cell.format = cf.format
  if bgcolor != defaultColor and cell.format.bgcolor == defaultColor:
    cell.format.bgcolor = bgcolor

proc setText(cell: var FixedCell; u: uint32; i, pi, uw: int; s: string) =
  if u.isControlChar():
    cell.str = u.controlToVisual()
  elif u in TabPUARange:
    cell.str = ' '.repeat(uw)
  else:
    cell.str = s.substr(pi, i - 1)

proc drawLines*(iface: BufferInterface; display: var FixedGrid;
    hlcolor: CellColor) =
  let bgcolor = iface.bgcolor
  var by = 0
  let endy = min(iface.pos.fromy + display.height, iface.numLines)
  let maxw = iface.pos.fromx + display.width
  for line in iface.ilines(iface.pos.fromy ..< endy):
    var w = 0 # width of the row so far
    var i = 0 # byte in line.str
    # Skip cells till fromx.
    while w < iface.pos.fromx and i < line.str.len:
      let u = line.str.nextUTF8(i)
      w += u.width()
    let dls = by * display.width # starting position of row in display
    # Fill in the gap in case we skipped more cells than fromx mandates (i.e.
    # we encountered a double-width character.)
    var cf = line.findFormat(w)
    var nf = line.findNextFormat(w)
    var k = 0
    while k < w - iface.pos.fromx:
      display[dls + k] = FixedCell(str: " ")
      display[dls + k].setFormat(cf, bgcolor)
      inc k
    let startw = w # save this for later
    # Now fill in the visible part of the row.
    while i < line.str.len:
      let pw = w
      let pi = i
      let u = line.str.nextUTF8(i)
      let uw = u.width()
      w += uw
      if w > maxw:
        break
      if nf.pos != -1 and nf.pos <= pw:
        cf = nf
        nf = line.findNextFormat(pw)
      display[dls + k].setText(u, i, pi, uw, line.str)
      display[dls + k].setFormat(cf, bgcolor)
      inc k
      for i in 1 ..< uw:
        display[dls + k] = FixedCell()
        inc k
    if bgcolor != defaultColor:
      # Fill the screen if bgcolor is not default.
      let format = initFormat(bgcolor, defaultColor, {})
      for cell in display.mline(by, k):
        cell = FixedCell(str: " ", format: format)
    else:
      for cell in display.mline(by, k):
        cell = FixedCell()
    # Finally, override cell formatting for highlighted cells.
    let aw = display.width - (startw - iface.pos.fromx) # actual width
    let y = iface.pos.fromy + by
    for hl in iface.highlights:
      if y notin hl.starty .. hl.endy:
        continue
      let area = iface.colorArea(hl, iface.pos.fromy + by, startw .. startw + aw)
      for i in area:
        if i - startw >= display.width:
          break
        let n = dls + i - startw
        if hlcolor != defaultColor:
          display[n].format.bgcolor = hlcolor
        else:
          display[n].format.incl(ffReverse)
    inc by
  for y in by ..< display.height: # clear the rest
    for cell in display.mline(y):
      cell = FixedCell()

proc addBufferInterfaceModule*(ctx: JSContext): Opt[void] =
  ?ctx.registerType(BufferInterface)
  ?ctx.registerType(BufferInit)
  ?ctx.registerType(Highlight)
  ok()

{.pop.}
