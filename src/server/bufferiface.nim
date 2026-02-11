{.push raises: [].}

import std/posix

import css/render
import io/dynstream
import io/packetreader
import io/packetwriter
import io/promise
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
import types/bitmap
import types/blob
import types/cell
import types/color
import types/jsopt
import types/opt
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

  BufferIfaceItem* = object
    id*: int
    p*: EmptyPromise
    get*: GetValueProc

  GetValueProc* = proc(iface: BufferInterface; promise: EmptyPromise) {.
    nimcall, raises: [].}

  HighlightType* = enum
    hltSearch, hltSelect

  Highlight* = ref object
    t* {.jsget.}: HighlightType
    selectionType* {.jsget.}: SelectionType
    mouse* {.jsget.}: bool
    x1*: int
    y1*: int
    x2*: int
    y2*: int

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

  GetLinesResult* = object
    numLines*: int
    bgcolor*: CellColor
    lines*: seq[SimpleFlexibleLine]
    images*: seq[PosBitmap]

  SelectionType* = enum
    stNormal = "normal"
    stBlock = "block"
    stLine = "line"

  ProcessHandle* = ref object
    process*: int
    refc*: int

  CursorState* = object
    cursor*: PagePos
    xend*: int
    fromx*: int
    fromy*: int
    setx*: int
    setxrefresh*: bool
    setxsave*: bool

  BufferInterface* = ref object
    map*: seq[BufferIfaceItem]
    packetid*: int
    len*: int
    nfds*: int
    width*: int
    height*: int
    stream*: BufStream
    lines*: SimpleFlexibleGrid
    lineShift*: int
    numLines* {.jsget.}: int
    pos*: CursorState
    highlights: seq[Highlight]
    images*: seq[PosBitmap]
    phandle*: ProcessHandle
    imageCache: ImageCache
    attrsp: ptr WindowAttributes
    bgcolor*: CellColor
    redraw*: bool
    gotLines* {.jsget.}: bool

jsDestructor(BufferInterface)
jsDestructor(Highlight)

# Forward declarations
proc queueDraw*(iface: BufferInterface)

proc newBufferInterface*(stream: BufStream; phandle: ProcessHandle;
    attrsp: ptr WindowAttributes): BufferInterface =
  inc phandle.refc
  return BufferInterface(
    phandle: phandle,
    packetid: 1, # ids below 1 are invalid
    stream: stream,
    redraw: true,
    attrsp: attrsp,
    width: attrsp.width,
    height: attrsp.height - 1,
    pos: CursorState(setx: -1)
  )

proc newProcessHandle*(pid: int): ProcessHandle =
  ProcessHandle(process: pid)

proc process*(iface: BufferInterface): int {.jsfunc.} =
  return iface.phandle.process

proc cursorx*(iface: BufferInterface): int {.jsfunc.} =
  return iface.pos.cursor.x

proc cursory*(iface: BufferInterface): int {.jsfunc.} =
  return iface.pos.cursor.y

proc fromx*(iface: BufferInterface): int {.jsfunc.} =
  return iface.pos.fromx

proc fromy*(iface: BufferInterface): int {.jsfunc.} =
  return iface.pos.fromy

proc lineWindow*(iface: BufferInterface): Slice[int] =
  if iface.numLines == 0: # not loaded
    return 0 .. iface.height * 5
  let n = (iface.height * 5) div 2
  var x = iface.fromy - n + iface.height div 2
  var y = iface.fromy + n + iface.height div 2
  if y >= iface.numLines:
    x -= y - iface.numLines
    y = iface.numLines
  if x < 0:
    y += -x
    x = 0
  return x .. y

proc lastVisibleLine*(iface: BufferInterface): int =
  min(iface.fromy + iface.height, iface.numLines) - 1

proc lineLoaded*(iface: BufferInterface; y: int): bool =
  let dy = y - iface.lineShift
  return dy in 0 ..< iface.lines.len

proc getLine*(iface: BufferInterface; y: int): lent SimpleFlexibleLine =
  if iface.lineLoaded(y):
    return iface.lines[y - iface.lineShift]
  let line {.global.} = SimpleFlexibleLine()
  return line

proc getLineStr(iface: BufferInterface; y: int): lent string =
  return iface.getLine(y).str

proc maxScreenWidth(iface: BufferInterface): int {.jsfunc.} =
  result = 0
  for y in iface.fromy..iface.lastVisibleLine:
    result = max(iface.getLineStr(y).width(), result)

proc maxfromx*(iface: BufferInterface): int =
  return max(iface.maxScreenWidth() - iface.width, 0)

proc maxfromy*(iface: BufferInterface): int =
  return max(iface.numLines - iface.height, 0)

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

proc toJS(ctx: JSContext; res: CheckRefreshResult): JSValue =
  let n = ctx.toJS(res.n)
  if JS_IsException(n):
    return JS_EXCEPTION
  let url = ctx.toJS(res.url)
  if JS_IsException(url):
    JS_FreeValue(ctx, url)
    return JS_EXCEPTION
  return ctx.newArrayFrom(n, url)

proc toJS*(ctx: JSContext; x: CursorXY): JSValue =
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
  let x = ctx.toJS(match.x)
  let y = ctx.toJS(match.y)
  let w = ctx.toJS(match.w)
  if JS_IsException(x) or JS_IsException(y) or JS_IsException(w):
    JS_FreeValue(ctx, x)
    JS_FreeValue(ctx, y)
    JS_FreeValue(ctx, w)
    return JS_EXCEPTION
  return ctx.newArrayFrom([x, y, w])

proc addPromise*(iface: BufferInterface; promise: EmptyPromise;
    get: GetValueProc) =
  iface.map.add(BufferIfaceItem(id: iface.packetid, p: promise, get: get))
  inc iface.packetid

proc addEmptyPromise*(iface: BufferInterface): EmptyPromise =
  let promise = EmptyPromise()
  iface.addPromise(promise, nil)
  return promise

proc getFromStream*[T](iface: BufferInterface; promise: EmptyPromise) =
  if iface.len != 0:
    let promise = Promise[T](promise)
    var r: PacketReader
    if iface.stream.initReader(r, iface.len, iface.nfds):
      r.sread(promise.res)
    iface.len = 0
    iface.nfds = 0

proc addPromise*[T](iface: BufferInterface): Promise[T] =
  let promise = Promise[T]()
  iface.addPromise(promise, getFromStream[T])
  return promise

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

#TODO probably we need some mechanism to block sending packets after a
# buffer is deleted

template withPacketWriterFire(iface: BufferInterface; cmd: BufferCommand;
    w, body: untyped) =
  iface.stream.withPacketWriterFire w:
    w.swrite(cmd)
    w.swrite(iface.packetid)
    body

proc cancel*(iface: BufferInterface): EmptyPromise {.jsfunc.} =
  iface.withPacketWriterFire bcCancel, w:
    discard
  return addEmptyPromise(iface)

proc checkRefresh(iface: BufferInterface): Promise[CheckRefreshResult]
    {.jsfunc.} =
  iface.withPacketWriterFire bcCheckRefresh, w:
    discard
  return addPromise[CheckRefreshResult](iface)

proc click(iface: BufferInterface; x, y, n: int): Promise[ClickResult] {.
    jsfunc.} =
  iface.withPacketWriterFire bcClick, w:
    w.swrite(x)
    w.swrite(y)
    w.swrite(n)
  return addPromise[ClickResult](iface)

proc clone*(iface: BufferInterface; newurl: URL; pstreamFd: cint):
    Promise[int] =
  if iface.stream.flush().isErr:
    return nil
  iface.stream.source.withPacketWriter w:
    w.swrite(bcClone)
    w.swrite(iface.packetid)
    w.swrite(newurl)
    w.sendFd(pstreamFd)
  do:
    return nil
  return addPromise[int](iface)

proc contextMenu(iface: BufferInterface; cursorx, cursory: int):
    Promise[bool] {.jsfunc.} =
  iface.withPacketWriterFire bcContextMenu, w:
    w.swrite(cursorx)
    w.swrite(cursory)
  return addPromise[bool](iface)

proc findNextLink(iface: BufferInterface; x, y, n: int): Promise[PagePos]
    {.jsfunc.} =
  iface.withPacketWriterFire bcFindNextLink, w:
    w.swrite(x)
    w.swrite(y)
    w.swrite(n)
  return addPromise[PagePos](iface)

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
      iface.withPacketWriterFire bcFindNextMatch, w:
        w.swrite(regex)
        w.swrite(x)
        w.swrite(y)
        w.swrite(endy)
        w.swrite(wrap)
        w.swrite(n)
      return ctx.toJS(addPromise[BufferMatch](iface))
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

proc findNextParagraph(iface: BufferInterface; y, n: int): Promise[int]
    {.jsfunc.} =
  iface.withPacketWriterFire bcFindNextParagraph, w:
    w.swrite(y)
    w.swrite(n)
  return addPromise[int](iface)

#TODO findPrevLink & findRevNthLink should probably be merged into findNextLink
proc findPrevLink(iface: BufferInterface; x, y, n: int): Promise[PagePos]
    {.jsfunc.} =
  iface.withPacketWriterFire bcFindPrevLink, w:
    w.swrite(x)
    w.swrite(y)
    w.swrite(n)
  return addPromise[PagePos](iface)

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
      iface.withPacketWriterFire bcFindPrevMatch, w:
        w.swrite(regex)
        w.swrite(x)
        w.swrite(y)
        w.swrite(endy)
        w.swrite(wrap)
        w.swrite(n)
      return ctx.toJS(addPromise[BufferMatch](iface))
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

proc findRevNthLink(iface: BufferInterface; x, y, n: int): Promise[PagePos]
    {.jsfunc.} =
  iface.withPacketWriterFire bcFindPrevLink, w:
    w.swrite(x)
    w.swrite(y)
    w.swrite(n)
  return addPromise[PagePos](iface)

proc forceReshape(iface: BufferInterface): EmptyPromise {.jsfunc.} =
  iface.withPacketWriterFire bcForceReshape, w:
    discard
  return addEmptyPromise(iface)

proc getLines*(iface: BufferInterface; slice: Slice[int]):
    Promise[GetLinesResult] =
  iface.withPacketWriterFire bcGetLines, w:
    w.swrite(slice)
  return addPromise[GetLinesResult](iface)

proc getSelectionText(iface: BufferInterface; sx, sy, ex, ey: int;
    t: SelectionType): Promise[string] {.jsfunc.} =
  iface.withPacketWriterFire bcGetSelectionText, w:
    w.swrite(sx)
    w.swrite(sy)
    w.swrite(ex)
    w.swrite(ey)
    w.swrite(t)
  return addPromise[string](iface)

proc getTitle(iface: BufferInterface): Promise[string] {.jsfunc.} =
  iface.withPacketWriterFire bcGetTitle, w:
    discard
  return addPromise[string](iface)

proc gotoAnchor(iface: BufferInterface; anchor: string;
    autofocus, target: bool): Promise[GotoAnchorResult] {.jsfunc.} =
  iface.withPacketWriterFire bcGotoAnchor, w:
    w.swrite(anchor)
    w.swrite(autofocus)
    w.swrite(target)
  return addPromise[GotoAnchorResult](iface)

proc hideHints(iface: BufferInterface): EmptyPromise {.jsfunc.} =
  iface.withPacketWriterFire bcHideHints, w:
    discard
  return addEmptyPromise(iface)

proc load(iface: BufferInterface): Promise[LoadResult] {.jsfunc.} =
  iface.withPacketWriterFire bcLoad, w:
    discard
  return addPromise[LoadResult](iface)

proc markURL(iface: BufferInterface): EmptyPromise {.jsfunc.} =
  iface.withPacketWriterFire bcMarkURL, w:
    discard
  return addEmptyPromise(iface)

proc onReshape(iface: BufferInterface): EmptyPromise {.jsfunc.} =
  iface.withPacketWriterFire bcOnReshape, w:
    discard
  return iface.addEmptyPromise()

proc readCanceled(iface: BufferInterface): EmptyPromise {.jsfunc.} =
  iface.withPacketWriterFire bcReadCanceled, w:
    discard
  return addEmptyPromise(iface)

proc readSuccess(iface: BufferInterface; s: string; fd: cint):
    Promise[ClickResult] {.jsfunc.} =
  if iface.stream.flush().isErr:
    return newResolvedPromise[ClickResult](initClickResult())
  iface.withPacketWriterFire bcReadSuccess, w:
    w.swrite(s)
    let hasfd = fd != -1
    w.swrite(hasfd)
    if hasfd:
      w.sendFd(fd)
  discard close(fd)
  return addPromise[ClickResult](iface)

proc select(iface: BufferInterface; selected: int): Promise[ClickResult] {.
    jsfunc.} =
  iface.withPacketWriterFire bcSelect, w:
    w.swrite(selected)
  return addPromise[ClickResult](iface)

proc showHints(iface: BufferInterface; sx, sy, ex, ey: int):
    Promise[HintResult] {.jsfunc.} =
  iface.withPacketWriterFire bcShowHints, w:
    w.swrite(sx)
    w.swrite(sy)
    w.swrite(ex)
    w.swrite(ey)
  return addPromise[HintResult](iface)

proc submitForm(iface: BufferInterface; x, y: int): Promise[ClickResult] {.
    jsfunc.} =
  iface.withPacketWriterFire bcSubmitForm, w:
    w.swrite(x)
    w.swrite(y)
  return addPromise[ClickResult](iface)

proc windowChange(iface: BufferInterface; x, y: int): Promise[PagePos]
    {.jsfunc.} =
  var attrs = iface.attrsp[]
  # subtract status line height
  attrs.height -= 1
  attrs.heightPx -= attrs.ppl
  iface.withPacketWriterFire bcWindowChange, w:
    w.swrite(attrs)
    w.swrite(x)
    w.swrite(y)
  return addPromise[PagePos](iface)

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
  ?ctx.registerType(Highlight)
  ?ctx.registerType(BufferInterface)
  ok()

{.pop.}
