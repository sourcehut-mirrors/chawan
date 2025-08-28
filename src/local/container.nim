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
import html/script
import io/dynstream
import io/packetwriter
import io/promise
import local/select
import monoucha/fromjs
import monoucha/javascript
import monoucha/jsregex
import monoucha/jstypes
import monoucha/quickjs
import monoucha/tojs
import server/buffer
import server/headers
import server/loaderiface
import server/request
import server/response
import types/bitmap
import types/blob
import types/cell
import types/color
import types/opt
import types/referrer
import types/url
import types/winattrs
import utils/luwrap
import utils/strwidth
import utils/twtstr
import utils/wordbreak

type
  CursorPosition* = object
    cursorx*: int
    cursory*: int
    xend*: int
    fromx*: int
    fromy*: int
    setx: int
    setxrefresh: bool
    setxsave: bool

  ContainerEventType* = enum
    cetReadLine, cetReadArea, cetReadFile, cetOpen, cetSetLoadInfo, cetStatus,
    cetAlert, cetLoaded, cetTitle, cetCancel, cetMetaRefresh

  ContainerEvent* = ref object
    case t*: ContainerEventType
    of cetReadLine:
      prompt*: string
      value*: string
      password*: bool
    of cetReadArea:
      tvalue*: string
    of cetOpen:
      save*: bool
      request*: Request
      url*: URL
      contentType*: string
    of cetAlert:
      msg*: string
    of cetMetaRefresh:
      refreshIn*: int
      refreshURL*: URL
    else: discard
    next: ContainerEvent

  HighlightType = enum
    hltSearch, hltSelect

  SelectionType = enum
    stNormal = "normal"
    stBlock = "block"
    stLine = "line"

  Highlight = ref object
    case t: HighlightType
    of hltSearch: discard
    of hltSelect:
      selectionType {.jsget.}: SelectionType
    x1, y1: int
    x2, y2: int

  PagePos = tuple
    x: int
    y: int

  BufferFilter* = ref object
    cmd*: string

  LoadState* = enum
    lsLoading, lsCanceled, lsLoaded

  ContainerFlag* = enum
    cfCloned, cfUserRequested, cfHasStart, cfCanReinterpret, cfSave, cfIsHTML,
    cfHistory, cfHighlight, cfTailOnLoad

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

  Container* = ref object of RootObj
    # note: this is not the same as source.request.url (but should be synced
    # with buffer.url)
    url* {.jsget.}: URL
    # note: this is *not* the same as Buffer.cacheId. buffer has the cache ID of
    # the output, while container holds that of the input. Thus pager can
    # re-interpret the original input, and buffer can rewind the (potentially
    # mailcap) output.
    cacheId* {.jsget.}: int
    parent* {.jsget.}: Container
    children* {.jsget.}: seq[Container]
    config*: BufferConfig
    loaderConfig*: LoaderClientConfig
    iface*: BufferInterface
    width* {.jsget.}: int
    height {.jsget.}: int
    title: string # used in status msg
    hoverText: array[HoverType, string]
    request*: Request # source request
    # if set, this *overrides* any content type received from the network. (this
    # is because it stores the content type from the -T flag.)
    contentType* {.jsget.}: string
    pos: CursorPosition
    bpos: seq[CursorPosition]
    highlights: seq[Highlight]
    process* {.jsget.}: int
    clonedFrom*: int
    loadinfo*: string
    lines: SimpleFlexibleGrid
    lineshift: int
    numLines* {.jsget.}: int
    replace*: Container
    replaceBackup*: Container # for redirection; when set, we get discarded
    # if we are referenced by another container, replaceRef is set so that we
    # can clear ourselves on discard
    #TODO this is a mess :(
    replaceRef*: Container
    retry*: seq[URL]
    sourcepair*: Container # pointer to buffer with a source view (may be nil)
    loadState*: LoadState
    event: ContainerEvent
    lastEvent: ContainerEvent
    startpos: Option[CursorPosition]
    redirectDepth*: int
    select* {.jsget.}: Select
    currentSelection {.jsget.}: Highlight
    tmpJumpMark: PagePos
    jumpMark: PagePos
    marks: Table[string, PagePos]
    filter*: BufferFilter
    bgcolor*: CellColor
    redraw*: bool
    needslines: bool
    lastPeek: HoverType
    flags*: set[ContainerFlag]
    #TODO this is inaccurate, because charsetStack can desync
    charset*: Charset
    charsetStack*: seq[Charset]
    mainConfig: Config
    images*: seq[PosBitmap]
    cachedImages*: seq[CachedImage]
    luctx: LUContext
    refreshHeader: string

  NavDirection* = enum
    ndPrev = "prev"
    ndNext = "next"
    ndPrevSibling = "prev-sibling"
    ndNextSibling = "next-sibling"
    ndParent = "parent"
    ndFirstChild
    ndAny = "any"

jsDestructor(Highlight)
jsDestructor(Container)

# Forward declarations
proc onclick(container: Container; res: ClickResult; save: bool)
proc updateCursor(container: Container)
proc cursorLastLine*(container: Container)
proc triggerEvent(container: Container; t: ContainerEventType)

proc newContainer*(config: BufferConfig; loaderConfig: LoaderClientConfig;
    url: URL; request: Request; luctx: LUContext; attrs: WindowAttributes;
    title: string; redirectDepth: int; flags: set[ContainerFlag];
    contentType: string; charsetStack: seq[Charset]; cacheId: int;
    mainConfig: Config): Container =
  return Container(
    url: url,
    request: request,
    contentType: contentType,
    width: attrs.width,
    height: attrs.height - 1,
    title: title,
    config: config,
    loaderConfig: loaderConfig,
    redirectDepth: redirectDepth,
    pos: CursorPosition(
      setx: -1
    ),
    loadinfo: "Connecting to " & request.url.host & "...",
    cacheId: cacheId,
    process: -1,
    clonedFrom: -1,
    mainConfig: mainConfig,
    flags: flags,
    luctx: luctx,
    redraw: true,
    lastPeek: HoverType.high
  )

proc clone*(container: Container; newurl: URL; loader: FileLoader):
    Promise[tuple[c: Container; fd: cint]] =
  if container.iface == nil:
    return nil
  let url = if newurl != nil:
    newurl
  else:
    container.url
  let p = container.iface.clone(url)
  var sv {.noinit.}: array[2, cint]
  if socketpair(AF_UNIX, SOCK_STREAM, IPPROTO_IP, sv) != 0:
    return nil
  # Send a pipe for synchronization in the clone proc.
  # (Do it here, so buffers do not need pipe rights.)
  var pipefd {.noinit.}: array[2, cint]
  if pipe(pipefd) == -1:
    discard close(sv[0])
    discard close(sv[1])
    return nil
  var fail = false
  container.iface.stream.source.withPacketWriter w:
    w.sendFd(sv[1])
    w.sendFd(pipefd[0])
    w.sendFd(pipefd[1])
  do:
    fail = true
  discard close(sv[1])
  discard close(pipefd[0])
  discard close(pipefd[1])
  if fail:
    return nil
  return p.then(proc(pid: int): tuple[c: Container; fd: cint] =
    if pid == -1:
      discard close(sv[0])
      return (nil, cint(-1))
    let nc = Container()
    nc[] = container[]
    nc.url = url
    nc.process = pid
    nc.clonedFrom = container.process
    nc.flags.incl(cfCloned)
    nc.retry = @[]
    nc.parent = nil
    nc.children = @[]
    nc.cachedImages = @[]
    return (nc, sv[0])
  )

proc lineLoaded(container: Container; y: int): bool =
  return y - container.lineshift in 0..container.lines.high

proc getLine(container: Container; y: int): lent SimpleFlexibleLine =
  if container.lineLoaded(y):
    return container.lines[y - container.lineshift]
  let line {.global.} = SimpleFlexibleLine()
  return line

proc getLineStr(container: Container; y: int): lent string =
  return container.getLine(y).str

iterator ilines(container: Container; slice: Slice[int]):
    lent SimpleFlexibleLine {.inline.} =
  for y in slice:
    yield container.getLine(y)

proc alive(container: Container): bool {.jsfget.} =
  return container.iface != nil

proc history(container: Container): bool {.jsfget.} =
  return cfHistory in container.flags

proc scripting(ctx: JSContext; container: Container): ScriptingMode {.jsfget.} =
  return container.config.scripting

proc cookie(ctx: JSContext; container: Container): CookieMode {.jsfget.} =
  return container.loaderConfig.cookieMode

proc cursorx*(container: Container): int {.jsfget.} =
  container.pos.cursorx

proc cursory*(container: Container): int {.jsfget.} =
  container.pos.cursory

proc fromx*(container: Container): int {.jsfget.} =
  container.pos.fromx

proc fromy*(container: Container): int {.jsfget.} =
  container.pos.fromy

proc xend(container: Container): int {.inline.} =
  container.pos.xend

proc lastVisibleLine(container: Container): int =
  min(container.fromy + container.height, container.numLines) - 1

proc currentLine(container: Container): lent string =
  return container.getLineStr(container.cursory)

proc findColBytes(s: string; endx: int; startx = 0; starti = 0): int =
  var w = startx
  var i = starti
  while i < s.len and w < endx:
    let u = s.nextUTF8(i)
    w += u.width()
  return i

proc cursorBytes(container: Container; y: int; cc = container.cursorx): int =
  return container.getLineStr(y).findColBytes(cc, 0, 0)

proc currentCursorBytes(container: Container; cc = container.cursorx): int =
  return container.cursorBytes(container.cursory, cc)

# Returns the X position of the first cell occupied by the character the cursor
# currently points to.
proc cursorFirstX(container: Container): int =
  if container.numLines == 0: return 0
  let line = container.currentLine
  var w = 0
  var i = 0
  let cc = container.cursorx
  while i < line.len:
    let u = line.nextUTF8(i)
    let tw = u.width()
    if w + tw > cc:
      return w
    w += tw
  return w

# Returns the X position of the last cell occupied by the character the cursor
# currently points to.
proc cursorLastX(container: Container): int =
  if container.numLines == 0: return 0
  let line = container.currentLine
  var w = 0
  var i = 0
  let cc = container.cursorx
  while i < line.len and w <= cc:
    let u = line.nextUTF8(i)
    w += u.width()
  return max(w - 1, 0)

# Last cell for tab, first cell for everything else (e.g. double width.)
# This is needed because moving the cursor to the 2nd cell of a double
# width character clears it on some terminals.
proc cursorDispX(container: Container): int =
  if container.numLines == 0: return 0
  let line = container.currentLine
  if line.len == 0: return 0
  var w = 0
  var pw = 0
  var i = 0
  var u = 0u32
  let cc = container.cursorx
  while i < line.len and w <= cc:
    u = line.nextUTF8(i)
    pw = w
    w += u.width()
  if u == uint32('\t'):
    return max(w - 1, 0)
  return pw

proc acursorx*(container: Container): int =
  max(0, container.cursorDispX() - container.fromx)

proc acursory*(container: Container): int =
  container.cursory - container.fromy

proc maxScreenWidth(container: Container): int =
  result = 0
  for y in container.fromy..container.lastVisibleLine:
    result = max(container.getLineStr(y).width(), result)

proc getTitle*(container: Container): string {.jsfget: "title".} =
  if container.title != "":
    return container.title
  return container.url.serialize(excludepassword = true)

proc currentLineWidth(container: Container): int =
  if container.numLines == 0: return 0
  return container.currentLine.width()

proc maxfromy(container: Container): int =
  return max(container.numLines - container.height, 0)

proc maxfromx(container: Container): int =
  return max(container.maxScreenWidth() - container.width, 0)

proc atPercentOf*(container: Container): int =
  if container.numLines == 0: return 100
  return (100 * (container.cursory + 1)) div container.numLines

proc lineWindow(container: Container): Slice[int] =
  if container.numLines == 0: # not loaded
    return 0..container.height * 5
  let n = (container.height * 5) div 2
  var x = container.fromy - n + container.height div 2
  var y = container.fromy + n + container.height div 2
  if y >= container.numLines:
    x -= y - container.numLines
    y = container.numLines
  if x < 0:
    y += -x
    x = 0
  return x .. y

proc startx(hl: Highlight): int =
  if hl.y1 < hl.y2:
    hl.x1
  elif hl.y2 < hl.y1:
    hl.x2
  else:
    min(hl.x1, hl.x2)

proc starty(hl: Highlight): int =
  return min(hl.y1, hl.y2)

proc endx(hl: Highlight): int =
  if hl.y1 > hl.y2:
    hl.x1
  elif hl.y2 > hl.y1:
    hl.x2
  else:
    max(hl.x1, hl.x2)

proc endy(hl: Highlight): int =
  return max(hl.y1, hl.y2)

proc colorNormal(container: Container; hl: Highlight; y: int;
    limitx: Slice[int]): Slice[int] =
  let starty = hl.starty
  let endy = hl.endy
  if y in starty + 1 .. endy - 1:
    let w = container.getLineStr(y).width()
    return min(limitx.a, w) .. min(limitx.b, w)
  if y == starty and y == endy:
    return max(hl.startx, limitx.a) .. min(hl.endx, limitx.b)
  if y == starty:
    let w = container.getLineStr(y).width()
    return max(hl.startx, limitx.a) .. min(limitx.b, w)
  if y == endy:
    let w = container.getLineStr(y).width()
    return min(limitx.a, w) .. min(hl.endx, limitx.b)
  0 .. 0

proc colorArea(container: Container; hl: Highlight; y: int;
    limitx: Slice[int]): Slice[int] =
  case hl.t
  of hltSelect:
    case hl.selectionType
    of stNormal:
      return container.colorNormal(hl, y, limitx)
    of stBlock:
      if y in hl.starty .. hl.endy:
        let (x, endx) = if hl.x1 < hl.x2:
          (hl.x1, hl.x2)
        else:
          (hl.x2, hl.x1)
        return max(x, limitx.a) .. min(endx, limitx.b)
      return 0 .. 0
    of stLine:
      if y in hl.starty .. hl.endy:
        let w = container.getLineStr(y).width()
        return min(limitx.a, w) .. min(limitx.b, w)
      return 0 .. 0
  else:
    return container.colorNormal(hl, y, limitx)

proc findHighlights*(container: Container; y: int): seq[Highlight] =
  result = @[]
  for hl in container.highlights:
    if y in hl.starty .. hl.endy:
      result.add(hl)

proc getHoverText*(container: Container): string =
  for t in HoverType:
    if container.hoverText[t] != "":
      return container.hoverText[t]
  ""

proc isHoverURL*(container: Container; url: URL): bool =
  if hoverUrl := parseURL(container.hoverText[htLink]):
    return url.authOrigin.isSameOrigin(hoverUrl.authOrigin)
  return false

proc triggerEvent(container: Container; event: ContainerEvent) =
  if container.lastEvent == nil:
    container.event = event
    container.lastEvent = event
  else:
    container.lastEvent.next = event
    container.lastEvent = event

proc triggerEvent(container: Container; t: ContainerEventType) =
  container.triggerEvent(ContainerEvent(t: t))

proc popEvent*(container: Container): ContainerEvent =
  if container.event == nil:
    return nil
  let res = container.event
  container.event = res.next
  if res.next == nil:
    container.lastEvent = nil
  return res

proc queueDraw*(container: Container) =
  container.redraw = true

proc requestLines(container: Container): EmptyPromise {.discardable.} =
  if container.iface == nil:
    return newResolvedPromise()
  let w = container.lineWindow
  return container.iface.getLines(w).then(proc(res: GetLinesResult) =
    container.lines.setLen(w.len)
    container.lineshift = w.a
    for y in 0 ..< min(res.lines.len, w.len):
      container.lines[y] = res.lines[y]
    let isBgNew = container.bgcolor != res.bgcolor
    if isBgNew:
      container.bgcolor = res.bgcolor
    if res.numLines != container.numLines:
      container.numLines = res.numLines
      container.updateCursor()
      if container.startpos.isSome and
          res.numLines >= container.startpos.get.cursory:
        container.pos = container.startpos.get
        container.needslines = true
        container.startpos = none(CursorPosition)
      if container.loadState != lsLoading:
        container.triggerEvent(cetStatus)
    if res.numLines > 0:
      container.updateCursor()
      if cfTailOnLoad in container.flags:
        container.flags.excl(cfTailOnLoad)
        container.cursorLastLine()
    let cw = container.fromy ..< container.fromy + container.height
    if w.a in cw or w.b in cw or cw.a in w or cw.b in w or isBgNew:
      container.queueDraw()
    container.images.setLen(0)
    for image in res.images:
      if image.width > 0 and image.height > 0 and
          image.bmp.width > 0 and image.bmp.height > 0:
        container.images.add(image)
  )

proc repaintLoop(container: Container) =
  if container.iface == nil:
    return
  container.iface.onReshape().then(proc() =
    container.requestLines().then(proc() = container.repaintLoop())
  )

proc sendCursorPosition*(container: Container): EmptyPromise {.discardable.} =
  if container.iface == nil:
    return newResolvedPromise()
  return container.iface.updateHover(container.cursorx, container.cursory)
      .then(proc(res: UpdateHoverResult) =
    if res.len > 0:
      assert res.high <= int(HoverType.high)
      for (ht, s) in res:
        container.hoverText[ht] = s
      container.triggerEvent(cetStatus)
  )

proc setFromY(container: Container; y: int) {.jsfunc.} =
  if container.pos.fromy != y:
    container.pos.fromy = max(min(y, container.maxfromy), 0)
    container.needslines = true
    container.queueDraw()

proc setFromX(container: Container; x: int; refresh = true) {.jsfunc.} =
  if container.pos.fromx != x:
    container.pos.fromx = max(min(x, container.maxfromx), 0)
    if container.pos.fromx > container.cursorx:
      container.pos.cursorx = min(container.pos.fromx,
        container.currentLineWidth())
      if refresh:
        container.sendCursorPosition()
    container.queueDraw()

proc setFromXY(container: Container; x, y: int) {.jsfunc.} =
  container.setFromY(y)
  container.setFromX(x)

# Set the cursor to the xth column. 0-based.
# * `refresh = false' inhibits reporting of the cursor position to the buffer.
# * `save = false' inhibits cursor movement if it is currently outside the
#   screen, and makes it so cursorx is not saved for restoration on cursory
#   movement.
proc setCursorX(container: Container; x: int; refresh = true; save = true)
    {.jsfunc.} =
  if not container.lineLoaded(container.cursory):
    container.pos.setx = x
    container.pos.setxrefresh = refresh
    container.pos.setxsave = save
    return
  container.pos.setx = -1
  let cw = container.currentLineWidth()
  let x2 = x
  let x = max(min(x, cw - 1), 0)
  # we check for save here, because it is only set by restoreCursorX where
  # we do not want to move the cursor just because it is outside the window.
  if not save or container.fromx <= x and x < container.fromx + container.width:
    container.pos.cursorx = x
  elif save and container.fromx > x:
    # target x is before the screen start
    if x2 < container.cursorx:
      # desired X position is lower than cursor X; move screen back to the
      # desired position if valid, to 0 if the desired position is less than 0,
      # otherwise the last cell of the current line.
      if x2 <= x:
        container.setFromX(x, false)
      else:
        container.setFromX(cw - 1, false)
    # take whatever position the jump has resulted in.
    container.pos.cursorx = container.fromx
  elif x > container.cursorx:
    # target x is greater than current x; a simple case, just shift fromx too
    # accordingly
    container.setFromX(max(x - container.width + 1, container.fromx), false)
    container.pos.cursorx = x
  if container.cursorx == x and container.currentSelection != nil and
      container.currentSelection.x2 != x:
    container.currentSelection.x2 = x
    container.queueDraw()
  if refresh:
    container.sendCursorPosition()
  if save:
    container.pos.xend = container.cursorx

proc restoreCursorX(container: Container) {.jsfunc.} =
  let x = clamp(container.currentLineWidth() - 1, 0, container.xend)
  container.setCursorX(x, false, false)

proc setCursorY(container: Container; y: int; refresh = true) {.jsfunc.} =
  let y = max(min(y, container.numLines - 1), 0)
  if container.cursory == y: return
  if y - container.fromy >= 0 and y - container.height < container.fromy:
    container.pos.cursory = y
  else:
    if y > container.cursory:
      container.setFromY(y - container.height + 1)
    else:
      container.setFromY(y)
    container.pos.cursory = y
  if container.currentSelection != nil and container.currentSelection.y2 != y:
    container.queueDraw()
    container.currentSelection.y2 = y
  container.restoreCursorX()
  if refresh:
    container.sendCursorPosition()

proc setCursorXY*(container: Container; x, y: int; refresh = true) {.jsfunc.} =
  container.setCursorY(y, refresh)
  container.setCursorX(x, refresh)

proc cursorLineTextStart(container: Container) {.jsfunc.} =
  if container.numLines == 0: return
  var x = 0
  for u in container.currentLine.points:
    if not container.luctx.isWhiteSpace(u):
      break
    x += u.width()
  if x == 0:
    dec x
  container.setCursorX(x)

# zb
proc lowerPage(container: Container; n = 0) {.jsfunc.} =
  if n != 0:
    container.setCursorY(n - 1)
  container.setFromY(container.cursory - container.height + 1)

# z-
proc lowerPageBegin(container: Container; n = 0) {.jsfunc.} =
  container.lowerPage(n)
  container.cursorLineTextStart()

# zz
proc centerLine(container: Container; n = 0) {.jsfunc.} =
  if n != 0:
    container.setCursorY(n - 1)
  container.setFromY(container.cursory - container.height div 2)

# z.
proc centerLineBegin(container: Container; n = 0) {.jsfunc.} =
  container.centerLine(n)
  container.cursorLineTextStart()

# zt
proc raisePage(container: Container; n = 0) {.jsfunc.} =
  if n != 0:
    container.setCursorY(n - 1)
  container.setFromY(container.cursory)

# z^M
proc raisePageBegin(container: Container; n = 0) {.jsfunc.} =
  container.raisePage(n)
  container.cursorLineTextStart()

# z+
proc nextPageBegin(container: Container; n = 0) {.jsfunc.} =
  if n == 0:
    container.setCursorY(container.fromy + container.height)
  else:
    container.setCursorY(n - 1)
  container.cursorLineTextStart()
  container.raisePage()

# z^
proc previousPageBegin(container: Container; n = 0) {.jsfunc.} =
  if n == 0:
    container.setCursorY(container.fromy - 1)
  else:
    container.setCursorY(n - container.height) # +- 1 cancels out
  container.cursorLineTextStart()
  container.lowerPage()

proc centerColumn(container: Container) {.jsfunc.} =
  container.setFromX(container.cursorx - container.width div 2)

proc setCursorYCenter(container: Container; y: int; refresh = true)
    {.jsfunc.} =
  let fy = container.fromy
  container.setCursorY(y, refresh)
  if fy != container.fromy:
    container.centerLine()

proc setCursorXCenter(container: Container; x: int; refresh = true) {.jsfunc.} =
  let fx = container.fromx
  container.setCursorX(x, refresh)
  if fx != container.fromx:
    container.centerColumn()

proc setCursorXYCenter*(container: Container; x, y: int; refresh = true)
    {.jsfunc.} =
  let fy = container.fromy
  let fx = container.fromx
  container.setCursorXY(x, y, refresh)
  if fy != container.fromy:
    container.centerLine()
  if fx != container.fromx:
    container.centerColumn()

proc cursorDown(container: Container; n = 1) {.jsfunc.} =
  container.setCursorY(container.cursory + n)

proc cursorUp(container: Container; n = 1) {.jsfunc.} =
  container.setCursorY(container.cursory - n)

proc cursorLeft(container: Container; n = 1) {.jsfunc.} =
  container.setCursorX(container.cursorFirstX() - n)

proc cursorRight(container: Container; n = 1) {.jsfunc.} =
  container.setCursorX(container.cursorLastX() + n)

proc cursorLineBegin(container: Container) {.jsfunc.} =
  container.setCursorX(-1)

proc cursorLineEnd(container: Container) {.jsfunc.} =
  container.setCursorX(container.currentLineWidth() - 1)

type BreakFunc = proc(ctx: LUContext; r: uint32): BreakCategory {.
  nimcall, raises: [].}

# move to first char that is not in this category
proc skipCat(container: Container; b, x: var int; breakFunc: BreakFunc;
    cat: BreakCategory) =
  while b < container.currentLine.len:
    let pb = b
    let u = container.currentLine.nextUTF8(b)
    if container.luctx.breakFunc(u) != cat:
      b = pb
      break
    x += u.width()

proc skipSpace(container: Container; b, x: var int; breakFunc: BreakFunc) =
  container.skipCat(b, x, breakFunc, bcSpace)

# move to last char in category, backwards
proc lastCatRev(container: Container; b, x: var int; breakFunc: BreakFunc;
    cat: BreakCategory) =
  while b > 0:
    let pb = b
    let u = container.currentLine.prevUTF8(b)
    if container.luctx.breakFunc(u) != cat:
      b = pb
      break
    x -= u.width()

# move to first char that is not in this category, backwards
proc skipCatRev(container: Container; b, x: var int; breakFunc: BreakFunc;
    cat: BreakCategory): BreakCategory =
  while b > 0:
    let u = container.currentLine.prevUTF8(b)
    x -= u.width()
    let it = container.luctx.breakFunc(u)
    if it != cat:
      return it
  b = -1
  return cat

proc skipSpaceRev(container: Container; b, x: var int; breakFunc: BreakFunc):
    BreakCategory =
  return container.skipCatRev(b, x, breakFunc, bcSpace)

proc cursorNextWord(container: Container; breakFunc: BreakFunc) =
  if container.numLines == 0: return
  var b = container.currentCursorBytes()
  var x = container.cursorx
  # meow
  let currentCat = if b < container.currentLine.len:
    var tmp = b
    container.luctx.breakFunc(container.currentLine.nextUTF8(tmp))
  else:
    bcSpace
  if currentCat != bcSpace:
    # not in space, skip chars that have the same category
    container.skipCat(b, x, breakFunc, currentCat)
  container.skipSpace(b, x, breakFunc)
  if b < container.currentLine.len:
    container.setCursorX(x)
  else:
    if container.cursory < container.numLines - 1:
      container.cursorDown()
      container.cursorLineBegin()
    else:
      container.cursorLineEnd()

proc cursorNextWord(container: Container) {.jsfunc.} =
  container.cursorNextWord(breaksWordCat)

proc cursorNextViWord(container: Container) {.jsfunc.} =
  container.cursorNextWord(breaksViWordCat)

proc cursorNextBigWord(container: Container) {.jsfunc.} =
  container.cursorNextWord(breaksBigWordCat)

proc cursorPrevWord(container: Container; breakFunc: BreakFunc) =
  if container.numLines == 0: return
  var b = container.currentCursorBytes()
  var x = container.cursorx
  if container.currentLine.len > 0:
    b = min(b, container.currentLine.len - 1)
    var currentCat = if b >= 0:
      var tmp = b
      container.luctx.breakFunc(container.currentLine.nextUTF8(tmp))
    else:
      bcSpace
    if currentCat != bcSpace:
      # not in space, skip chars that have the same category
      currentCat = container.skipCatRev(b, x, breakFunc, currentCat)
    if currentCat == bcSpace:
      discard container.skipSpaceRev(b, x, breakFunc)
  else:
    b = -1
  if b >= 0:
    container.setCursorX(x)
  else:
    if container.cursory > 0:
      container.cursorUp()
      container.cursorLineEnd()
    else:
      container.cursorLineBegin()

proc cursorPrevWord(container: Container) {.jsfunc.} =
  container.cursorPrevWord(breaksWordCat)

proc cursorPrevViWord(container: Container) {.jsfunc.} =
  container.cursorPrevWord(breaksViWordCat)

proc cursorPrevBigWord(container: Container) {.jsfunc.} =
  container.cursorPrevWord(breaksBigWordCat)

proc cursorWordEnd(container: Container; breakFunc: BreakFunc) =
  if container.numLines == 0: return
  var b = container.currentCursorBytes()
  var x = container.cursorx
  var px = x
  # if not in space, move to the right by one
  if b < container.currentLine.len:
    let pb = b
    let u = container.currentLine.nextUTF8(b)
    if container.luctx.breakFunc(u) == bcSpace:
      b = pb
    else:
      px = x
      x += u.width()
  container.skipSpace(b, x, breakFunc)
  # move to the last char in the current category
  let ob = b
  if b < container.currentLine.len:
    var tmp = b
    let u = container.currentLine.nextUTF8(tmp)
    let currentCat = container.luctx.breakFunc(u)
    while b < container.currentLine.len:
      let pb = b
      let u = container.currentLine.nextUTF8(b)
      if container.luctx.breakFunc(u) != currentCat:
        b = pb
        break
      px = x
      x += u.width()
    x = px
  if b < container.currentLine.len or ob != b:
    container.setCursorX(x)
  else:
    if container.cursory < container.numLines - 1:
      container.cursorDown()
      container.cursorLineBegin()
    else:
      container.cursorLineEnd()

proc cursorWordEnd(container: Container) {.jsfunc.} =
  container.cursorWordEnd(breaksWordCat)

proc cursorViWordEnd(container: Container) {.jsfunc.} =
  container.cursorWordEnd(breaksViWordCat)

proc cursorBigWordEnd(container: Container) {.jsfunc.} =
  container.cursorWordEnd(breaksBigWordCat)

proc cursorWordBegin(container: Container; breakFunc: BreakFunc) =
  if container.numLines == 0: return
  var b = container.currentCursorBytes()
  var x = container.cursorx
  if container.currentLine.len > 0:
    b = min(b, container.currentLine.len - 1)
    if b >= 0:
      var tmp = b
      var u = container.currentLine.nextUTF8(tmp)
      var currentCat = container.luctx.breakFunc(u)
      # if not in space, move to the left by one
      if currentCat != bcSpace:
        if b > 0:
          u = container.currentLine.prevUTF8(b)
          x -= u.width()
          currentCat = container.luctx.breakFunc(u)
        else:
          b = -1
      if container.luctx.breakFunc(u) == bcSpace:
        currentCat = container.skipSpaceRev(b, x, breakFunc)
      # move to the first char in the current category
      container.lastCatRev(b, x, breakFunc, currentCat)
  else:
    b = -1
  if b >= 0:
    container.setCursorX(x)
  else:
    if container.cursory > 0:
      container.cursorUp()
      container.cursorLineEnd()
    else:
      container.cursorLineBegin()

proc cursorWordBegin(container: Container) {.jsfunc.} =
  container.cursorWordBegin(breaksWordCat)

proc cursorViWordBegin(container: Container) {.jsfunc.} =
  container.cursorWordBegin(breaksViWordCat)

proc cursorBigWordBegin(container: Container) {.jsfunc.} =
  container.cursorWordBegin(breaksBigWordCat)

proc pageDown(container: Container; n = 1) {.jsfunc.} =
  container.setFromY(container.fromy + container.height * n)
  container.setCursorY(container.cursory + container.height * n)
  container.restoreCursorX()

proc pageUp(container: Container; n = 1) {.jsfunc.} =
  container.setFromY(container.fromy - container.height * n)
  container.setCursorY(container.cursory - container.height * n)
  container.restoreCursorX()

proc pageLeft(container: Container; n = 1) {.jsfunc.} =
  container.setFromX(container.fromx - container.width * n)

proc pageRight(container: Container; n = 1) {.jsfunc.} =
  container.setFromX(container.fromx + container.width * n)

# I am not cloning the vi behavior here because it is counter-intuitive
# and annoying.
# Users who disagree are free to implement it themselves. (It is about
# 5 lines of JS.)
proc halfPageUp(container: Container; n = 1) {.jsfunc.} =
  container.setFromY(container.fromy - (container.height + 1) div 2 * n)
  container.setCursorY(container.cursory - (container.height + 1) div 2 * n)
  container.restoreCursorX()

proc halfPageDown(container: Container; n = 1) {.jsfunc.} =
  container.setFromY(container.fromy + (container.height + 1) div 2 * n)
  container.setCursorY(container.cursory + (container.height + 1) div 2 * n)
  container.restoreCursorX()

proc halfPageLeft(container: Container; n = 1) {.jsfunc.} =
  container.setFromX(container.fromx - (container.width + 1) div 2 * n)

proc halfPageRight(container: Container; n = 1) {.jsfunc.} =
  container.setFromX(container.fromx + (container.width + 1) div 2 * n)

proc markPos0*(container: Container) =
  container.tmpJumpMark = (container.cursorx, container.cursory)

proc markPos*(container: Container) =
  let pos = container.tmpJumpMark
  if container.cursorx != pos.x or container.cursory != pos.y:
    container.jumpMark = pos

proc cursorFirstLine(container: Container) {.jsfunc.} =
  container.markPos0()
  container.setCursorY(0)
  container.markPos()

proc cursorLastLine*(container: Container) {.jsfunc.} =
  container.markPos0()
  container.setCursorY(container.numLines - 1)
  container.markPos()

proc cursorTop(container: Container; i = 1) {.jsfunc.} =
  container.markPos0()
  let i = clamp(i - 1, 0, container.height - 1)
  container.setCursorY(container.fromy + i)
  container.markPos()

proc cursorMiddle(container: Container) {.jsfunc.} =
  container.markPos0()
  container.setCursorY(container.fromy + (container.height - 2) div 2)
  container.markPos()

proc cursorBottom(container: Container; i = 1) {.jsfunc.} =
  container.markPos0()
  let i = clamp(i, 0, container.height)
  container.setCursorY(container.fromy + container.height - i)
  container.markPos()

proc cursorLeftEdge(container: Container) {.jsfunc.} =
  container.setCursorX(container.fromx)

proc cursorMiddleColumn(container: Container) {.jsfunc.} =
  container.setCursorX(container.fromx + (container.width - 2) div 2)

proc cursorRightEdge(container: Container) {.jsfunc.} =
  container.setCursorX(container.fromx + container.width - 1)

proc scrollDown*(container: Container; n = 1) {.jsfunc.} =
  let H = container.numLines
  let y = min(container.fromy + container.height + n, H) - container.height
  if y > container.fromy:
    container.setFromY(y)
    if container.fromy > container.cursory:
      container.cursorDown(container.fromy - container.cursory)
  else:
    container.cursorDown(n)

proc scrollUp*(container: Container; n = 1) {.jsfunc.} =
  let y = max(container.fromy - n, 0)
  if y < container.fromy:
    container.setFromY(y)
    if container.fromy + container.height <= container.cursory:
      container.cursorUp(container.cursory - container.fromy -
        container.height + 1)
  else:
    container.cursorUp(n)

proc scrollRight*(container: Container; n = 1) {.jsfunc.} =
  let msw = container.maxScreenWidth()
  let x = min(container.fromx + container.width + n, msw) - container.width
  if x > container.fromx:
    container.setFromX(x)

proc scrollLeft*(container: Container; n = 1) {.jsfunc.} =
  let x = max(container.fromx - n, 0)
  if x < container.fromx:
    container.setFromX(x)

proc alert(container: Container; msg: string) =
  container.triggerEvent(ContainerEvent(t: cetAlert, msg: msg))

proc lineInfo(container: Container) {.jsfunc.} =
  container.alert("line " & $(container.cursory + 1) & "/" &
    $container.numLines & " (" & $container.atPercentOf() & "%) col " &
    $(container.cursorx + 1) & "/" & $container.currentLineWidth &
    " (byte " & $container.currentCursorBytes & ")")

proc updateCursor(container: Container) =
  if container.pos.setx > -1:
    container.setCursorX(container.pos.setx, container.pos.setxrefresh,
      container.pos.setxsave)
  if container.fromy > container.maxfromy:
    container.setFromY(container.maxfromy)
  if container.cursory >= container.numLines:
    let n = max(container.lastVisibleLine, 0)
    if container.cursory != n:
      container.setCursorY(n)
      container.alert("Last line is #" & $container.numLines)

proc gotoLine*(container: Container; n: int) =
  container.markPos0()
  container.setCursorY(n - 1)
  container.markPos()

proc gotoLine*(container: Container; s: string) =
  if s != "":
    let c = s[0]
    if c == '^':
      container.cursorFirstLine()
    elif c == '$':
      container.cursorLastLine()
    elif (let n = parseIntP(s).get(0); n > 0):
      container.gotoLine(n)
    else:
      container.alert("First line is #1") # :)

proc pushCursorPos*(container: Container) =
  if container.select != nil:
    container.select.pushCursorPos()
  else:
    container.bpos.add(container.pos)

proc popCursorPos*(container: Container; nojump = false) =
  if container.select != nil:
    container.select.popCursorPos(nojump)
  elif container.bpos.len > 0:
    container.pos = container.bpos.pop()
    if not nojump:
      container.updateCursor()
      container.sendCursorPosition()
    container.needslines = true

proc copyCursorPos*(container, c2: Container) {.jsfunc.} =
  if c2.startpos.isSome:
    container.startpos = c2.startpos
  else:
    container.startpos = some(c2.pos)
  container.flags.incl(cfHasStart)

proc cursorNextLink(container: Container; n = 1) {.jsfunc.} =
  if container.iface == nil:
    return
  container.markPos0()
  container.iface
    .findNextLink(container.cursorx, container.cursory, n)
    .then(proc(res: tuple[x, y: int]) =
      if res.x > -1 and res.y != -1:
        container.setCursorXYCenter(res.x, res.y)
        container.markPos()
    )

proc cursorPrevLink(container: Container; n = 1) {.jsfunc.} =
  if container.iface == nil:
    return
  container.markPos0()
  container.iface
    .findPrevLink(container.cursorx, container.cursory, n)
    .then(proc(res: tuple[x, y: int]) =
      if res.x > -1 and res.y != -1:
        container.setCursorXYCenter(res.x, res.y)
        container.markPos()
    )

proc cursorLinkNavDown(container: Container; n = 1) {.jsfunc.} =
  if container.iface == nil:
    return
  container.markPos0()
  container.iface
    .findNextLink(container.cursorx, container.cursory, n)
    .then(proc(res: tuple[x, y: int]) =
      if res.x == -1 and res.y == -1:
        if container.numLines <= container.height:
          container.iface
            .findNextLink(-1, 0, n = 1).then(proc(res2: tuple[x, y: int]) =
              container.setCursorXYCenter(res2.x, res2.y)
              container.markPos()
            )
        else:
          container.pageDown()
          container.markPos()
      elif res.y < container.fromy + container.height:
        container.setCursorXYCenter(res.x, res.y)
        container.markPos()
      else:
        container.pageDown()
        if res.y < container.fromy + container.height:
          container.setCursorXYCenter(res.x, res.y)
          container.markPos()
    )

proc cursorLinkNavUp(container: Container; n = 1) {.jsfunc.} =
  if container.iface == nil:
    return
  container.markPos0()
  container.iface
    .findPrevLink(container.cursorx, container.cursory, n)
    .then(proc(res: tuple[x, y: int]) =
      if res.x == -1 and res.y == -1:
        if container.numLines <= container.height:
          container.iface
            .findPrevLink(int.high, container.numLines - 1, n = 1)
            .then(proc(res2: tuple[x, y: int]) =
              container.setCursorXYCenter(res2.x, res2.y)
              container.markPos()
            )
        else:
          container.pageUp()
          container.markPos()
      elif res.y >= container.fromy:
        container.setCursorXYCenter(res.x, res.y)
        container.markPos()
      else:
        container.pageUp()
        if res.y >= container.fromy:
          container.setCursorXYCenter(res.x, res.y)
          container.markPos()
    )

proc cursorNextParagraph(container: Container; n = 1) {.jsfunc.} =
  if container.iface == nil:
    return
  container.markPos0()
  container.iface
    .findNextParagraph(container.cursory, n)
    .then(proc(res: int) =
      container.setCursorY(res)
      container.markPos()
    )

proc cursorPrevParagraph(container: Container; n = 1) {.jsfunc.} =
  if container.iface == nil:
    return
  container.markPos0()
  container.iface
    .findPrevParagraph(container.cursory, n)
    .then(proc(res: int) =
      container.setCursorY(res)
      container.markPos()
    )

proc setMark(container: Container; id: string; x = none(int); y = none(int)):
    bool {.jsfunc.} =
  let x = x.get(container.cursorx)
  let y = y.get(container.cursory)
  container.marks.withValue(id, p):
    p[] = (x, y)
    container.queueDraw()
    return false
  do:
    container.marks[id] = (x, y)
    container.queueDraw()
    return true

proc clearMark(container: Container; id: string): bool {.jsfunc.} =
  result = id in container.marks
  container.marks.del(id)
  container.queueDraw()

proc getMarkPos(container: Container; id: string): Opt[PagePos] {.jsfunc.} =
  if id == "`" or id == "'":
    return ok(container.jumpMark)
  container.marks.withValue(id, p):
    return ok(p[])
  return err()

proc gotoMark(container: Container; id: string): bool {.jsfunc.} =
  container.markPos0()
  if mark := container.getMarkPos(id):
    container.setCursorXYCenter(mark.x, mark.y)
    container.markPos()
    return true
  return false

proc gotoMarkY(container: Container; id: string): bool {.jsfunc.} =
  container.markPos0()
  if mark := container.getMarkPos(id):
    container.setCursorXYCenter(0, mark.y)
    container.markPos()
    return true
  return false

proc findNextMark(container: Container; x = none(int); y = none(int)):
    Option[string] {.jsfunc.} =
  #TODO optimize (maybe store marks in an OrderedTable and sort on insert?)
  let x = x.get(container.cursorx)
  let y = y.get(container.cursory)
  var best: PagePos = (high(int), high(int))
  var bestid = none(string)
  for id, mark in container.marks:
    if mark.y < y or mark.y == y and mark.x <= x:
      continue
    if mark.y < best.y or mark.y == best.y and mark.x < best.x:
      best = mark
      bestid = some(id)
  return bestid

proc findPrevMark(container: Container; x = none(int); y = none(int)):
    Option[string] {.jsfunc.} =
  #TODO optimize (maybe store marks in an OrderedTable and sort on insert?)
  let x = x.get(container.cursorx)
  let y = y.get(container.cursory)
  var best: PagePos = (-1, -1)
  var bestid = none(string)
  for id, mark in container.marks:
    if mark.y > y or mark.y == y and mark.x >= x:
      continue
    if mark.y > best.y or mark.y == best.y and mark.x > best.x:
      best = mark
      bestid = some(id)
  return bestid

proc cursorNthLink(container: Container; n = 1) {.jsfunc.} =
  if container.iface == nil:
    return
  container.iface
    .findNthLink(n)
    .then(proc(res: tuple[x, y: int]) =
      if res.x > -1 and res.y != -1:
        container.setCursorXYCenter(res.x, res.y))

proc cursorRevNthLink(container: Container; n = 1) {.jsfunc.} =
  if container.iface == nil:
    return
  container.iface
    .findRevNthLink(n)
    .then(proc(res: tuple[x, y: int]) =
      if res.x > -1 and res.y != -1:
        container.setCursorXYCenter(res.x, res.y))

proc clearSearchHighlights*(container: Container) =
  for i in countdown(container.highlights.high, 0):
    if container.highlights[i].t == hltSearch:
      container.highlights.del(i)

proc onMatch(container: Container; res: BufferMatch; refresh: bool) =
  if res.success:
    container.setCursorXYCenter(res.x, res.y, refresh)
    if cfHighlight in container.flags:
      container.clearSearchHighlights()
      let ex = res.x + res.str.width() - 1
      let hl = Highlight(
        t: hltSearch,
        x1: res.x,
        y1: res.y,
        x2: ex,
        y2: res.y
      )
      container.highlights.add(hl)
      container.queueDraw()
      container.flags.excl(cfHighlight)
  elif cfHighlight in container.flags:
    container.clearSearchHighlights()
    container.queueDraw()
    container.flags.excl(cfHighlight)

proc cursorNextMatch*(container: Container; regex: Regex; wrap, refresh: bool;
    n: int): EmptyPromise {.discardable.} =
  if container.select != nil:
    #TODO
    for _ in 0 ..< n:
      container.select.cursorNextMatch(regex, wrap)
    return newResolvedPromise()
  else:
    if container.iface == nil:
      return
    return container.iface
      .findNextMatch(regex, container.cursorx, container.cursory, wrap, n)
      .then(proc(res: BufferMatch) =
        container.onMatch(res, refresh))

proc cursorPrevMatch*(container: Container; regex: Regex; wrap, refresh: bool;
    n: int): EmptyPromise {.discardable.} =
  if container.select != nil:
    #TODO
    for _ in 0 ..< n:
      container.select.cursorPrevMatch(regex, wrap)
    return newResolvedPromise()
  else:
    if container.iface == nil:
      return
    container.markPos0()
    return container.iface
      .findPrevMatch(regex, container.cursorx, container.cursory, wrap, n)
      .then(proc(res: BufferMatch) =
        container.onMatch(res, refresh)
        container.markPos()
      )

type
  SelectionOptions = object of JSDict
    selectionType {.jsdefault.}: SelectionType

proc cursorToggleSelection(container: Container; n = 1;
    opts = SelectionOptions()): Highlight {.jsfunc.} =
  if container.currentSelection != nil:
    let i = container.highlights.find(container.currentSelection)
    if i != -1:
      container.highlights.delete(i)
    container.currentSelection = nil
  else:
    let cx = container.cursorFirstX()
    let n = n - 1
    container.cursorRight(n)
    let hl = Highlight(
      t: hltSelect,
      selectionType: opts.selectionType,
      x1: cx,
      y1: container.cursory,
      x2: container.cursorx,
      y2: container.cursory
    )
    container.highlights.add(hl)
    container.currentSelection = hl
  container.queueDraw()
  return container.currentSelection

#TODO I don't like this API
# maybe make selection a subclass of highlight?
proc getSelectionText(container: Container; hl = none(Highlight)):
    Promise[string] {.jsfunc.} =
  let hl = hl.get(container.currentSelection)
  if container.iface == nil or hl == nil or hl.t != hltSelect:
    return newResolvedPromise("")
  let startx = hl.startx
  let starty = hl.starty
  let endx = hl.endx
  let endy = hl.endy
  let nw = starty .. endy
  return container.iface.getLines(nw).then(proc(res: GetLinesResult): string =
    var s = ""
    case hl.selectionType
    of stNormal:
      if starty == endy:
        let si = res.lines[0].str.findColBytes(startx)
        let ei = res.lines[0].str.findColBytes(endx + 1, startx, si) - 1
        s = res.lines[0].str.substr(si, ei)
      else:
        let si = res.lines[0].str.findColBytes(startx)
        s &= res.lines[0].str.substr(si) & '\n'
        for i in 1 .. res.lines.high - 1:
          s &= res.lines[i].str & '\n'
        let ei = res.lines[^1].str.findColBytes(endx + 1) - 1
        s &= res.lines[^1].str.substr(0, ei)
    of stBlock:
      for i, line in res.lines.mypairs:
        let si = line.str.findColBytes(startx)
        let ei = line.str.findColBytes(endx + 1, startx, si) - 1
        if i > 0:
          s &= '\n'
        s &= line.str.substr(si, ei)
    of stLine:
      for i, line in res.lines.mypairs:
        if i > 0:
          s &= '\n'
        s &= line.str
    return s.expandPUATabsHard()
  )

proc markURL(container: Container) {.jsfunc.} =
  if container.iface == nil:
    return
  var schemes = newSeq[string]()
  for key in container.mainConfig.external.urimethodmap.map.keys:
    schemes.add(key.until(':'))
  container.iface.markURL(schemes)

proc toggleImages(container: Container) {.jsfunc.} =
  if container.iface == nil:
    return
  container.iface.toggleImages().then(proc(images: bool) =
    container.config.images = images
  )

proc setLoadInfo(container: Container; msg: string) =
  container.loadinfo = msg
  container.triggerEvent(cetSetLoadInfo)

proc onReadLine(container: Container; rl: ReadLineResult) =
  case rl.t
  of rltText:
    container.triggerEvent(ContainerEvent(
      t: cetReadLine,
      prompt: rl.prompt,
      value: rl.value,
      password: rl.hide
    ))
  of rltArea:
    container.triggerEvent(ContainerEvent(
      t: cetReadArea,
      tvalue: rl.value
    ))
  of rltFile:
    container.triggerEvent(ContainerEvent(t: cetReadFile))

#TODO this should be called with a timeout.
proc onload(container: Container; res: int) =
  if container.loadState == lsCanceled:
    return
  if res == -2:
    container.loadState = lsLoaded
    container.setLoadInfo("")
    container.triggerEvent(cetStatus)
    container.triggerEvent(cetLoaded)
    if cfHasStart notin container.flags:
      let anchor = container.url.hash.substr(1)
      if anchor != "" or container.config.autofocus:
        container.requestLines().then(proc(): Promise[GotoAnchorResult] =
          return container.iface.gotoAnchor(anchor, container.config.autofocus,
            true)
        ).then(proc(res: GotoAnchorResult) =
          if res.found:
            container.setCursorXYCenter(res.x, res.y)
            if res.focus != nil:
              container.onReadLine(res.focus)
        )
    if container.config.metaRefresh != mrNever:
      let res = parseRefresh(container.refreshHeader, container.url)
      container.refreshHeader = ""
      if res.n != -1:
        container.triggerEvent(ContainerEvent(
          t: cetMetaRefresh,
          refreshIn: res.n,
          refreshURL: if res.url != nil: res.url else: container.url
        ))
      else:
        container.iface.checkRefresh().then(proc(res: CheckRefreshResult) =
          if res.n >= 0:
            container.triggerEvent(ContainerEvent(
              t: cetMetaRefresh,
              refreshIn: res.n,
              refreshURL: if res.url != nil: res.url else: container.url
            ))
        )
  else:
    if res == -1:
      container.setLoadInfo("Loading images...")
    else:
      container.setLoadInfo(convertSize(res) & " loaded")
    discard container.iface.load().then(proc(res: int) =
      container.onload(res)
    )

# Apply data received in response.
# Note: pager must call this before checkMailcap.
proc applyResponse*(container: Container; response: Response;
    mimeTypes: MimeTypes) =
  # accept cookies
  let cookieJar = container.loaderConfig.cookieJar
  if cookieJar != nil:
    cookieJar.setCookie(response.headers.getAllNoComma("Set-Cookie"),
      response.url, container.loaderConfig.cookieMode == cmSave)
  # set referrer policy, if any
  if container.config.refererFrom:
    let referrerPolicy = response.getReferrerPolicy()
    container.loaderConfig.referrerPolicy = referrerPolicy.get(DefaultPolicy)
  else:
    container.loaderConfig.referrerPolicy = rpNoReferrer
  # setup content type; note that isSome means an override so we skip it
  if container.contentType == "":
    var contentType = response.getContentType()
    if contentType == "application/octet-stream":
      contentType = mimeTypes.guessContentType(container.url.pathname,
        "text/plain")
    container.contentType = move(contentType)
  # setup charsets:
  # * override charset
  # * network charset
  # * default charset guesses
  # HTML may override the last two (but not the override charset).
  if container.config.charsetOverride != CHARSET_UNKNOWN:
    container.charsetStack = @[container.config.charsetOverride]
  elif (let charset = response.getCharset(CHARSET_UNKNOWN);
      charset != CHARSET_UNKNOWN):
    container.charsetStack = @[charset]
  else:
    container.charsetStack = @[]
    for charset in container.config.charsets.ritems:
      container.charsetStack.add(charset)
    if container.charsetStack.len == 0:
      container.charsetStack.add(DefaultCharset)
  container.charset = container.charsetStack[^1]
  container.refreshHeader = response.headers.getFirst("Refresh")

proc remoteCancel*(container: Container) =
  if container.iface != nil:
    container.iface.cancel()
  container.setLoadInfo("")
  container.alert("Canceled loading")

proc cancel*(container: Container) {.jsfunc.} =
  if container.loadState == lsLoading:
    container.loadState = lsCanceled
    if container.iface != nil:
      container.remoteCancel()
    else:
      container.triggerEvent(cetCancel)

proc readCanceled*(container: Container) =
  container.iface.readCanceled()

proc readSuccess*(container: Container; s: string; fd: cint = -1) =
  let p = container.iface.readSuccess(s, fd != -1)
  if fd != -1:
    doAssert container.iface.stream.flush()
    container.iface.stream.source.withPacketWriterFire w:
      w.sendFd(fd)
  p.then(proc(res: Request) =
    if res != nil:
      container.triggerEvent(ContainerEvent(t: cetOpen, request: res))
  )

proc reshape(container: Container): EmptyPromise {.jsfunc.} =
  if container.iface == nil:
    return
  return container.iface.forceReshape()

proc selectFinish(opaque: RootRef; select: Select) =
  let container = Container(opaque)
  container.iface.select(select.selected).then(proc(res: ClickResult) =
    container.onclick(res, save = false)
  )
  container.select = nil
  container.queueDraw()

proc displaySelect(container: Container; selectResult: SelectResult) =
  container.select = newSelect(
    selectResult.options,
    selectResult.selected,
    max(container.acursorx - 1, 0),
    max(container.acursory - 1 - selectResult.selected, 0),
    container.width,
    container.height,
    selectFinish,
    container
  )

proc onclick(container: Container; res: ClickResult; save: bool) =
  if res.open != nil:
    container.triggerEvent(ContainerEvent(
      t: cetOpen,
      request: res.open,
      save: save,
      contentType: res.contentType
    ))
  if res.select.isSome and not save and res.select.get.options.len > 0:
    container.displaySelect(res.select.get)
  if res.readline.isSome:
    container.onReadLine(res.readline.get)

proc click*(container: Container) {.jsfunc.} =
  if container.iface == nil:
    return
  container.iface.click(container.cursorx, container.cursory)
    .then(proc(res: ClickResult) = container.onclick(res, save = false))

proc saveLink*(container: Container) {.jsfunc.} =
  if container.iface == nil:
    return
  container.iface.click(container.cursorx, container.cursory)
    .then(proc(res: ClickResult) = container.onclick(res, save = true))

proc saveSource*(container: Container) {.jsfunc.} =
  if container.iface == nil:
    return
  container.triggerEvent(ContainerEvent(
    t: cetOpen,
    request: newRequest("cache:" & $container.cacheId),
    save: true,
    url: container.url
  ))

proc windowChange*(container: Container; attrs: WindowAttributes) =
  container.width = attrs.width
  container.height = attrs.height - 1
  if container.iface != nil:
    var attrs = attrs
    # subtract status line height
    attrs.height -= 1
    attrs.heightPx -= attrs.ppl
    container.iface.windowChange(attrs)
  if container.select != nil:
    container.select.windowChange(container.width, container.height)

proc peek(container: Container) {.jsfunc.} =
  container.alert($container.url)

proc clearHover*(container: Container) =
  container.lastPeek = HoverType.high

proc peekCursor(container: Container) {.jsfunc.} =
  var p = container.lastPeek
  while true:
    if p < HoverType.high:
      inc p
    else:
      p = HoverType.low
    if container.hoverText[p] != "" or p == container.lastPeek:
      break
  if container.hoverText[p] != "":
    container.alert(container.hoverText[p])
  container.lastPeek = p

proc hoverLink(container: Container): string {.jsfget.} =
  return container.hoverText[htLink]

proc hoverTitle(container: Container): string {.jsfget.} =
  return container.hoverText[htTitle]

proc hoverImage(container: Container): string {.jsfget.} =
  return container.hoverText[htImage]

proc hoverCachedImage(container: Container): string {.jsfget.} =
  return container.hoverText[htCachedImage]

proc findPrev(container: Container): Container =
  if container.parent == nil:
    return nil
  let n = container.parent.children.find(container)
  assert n != -1, "Container not a child of its parent"
  if n == 0:
    return container.parent
  var container = container.parent.children[n - 1]
  while container.children.len > 0:
    container = container.children[^1]
  return container

proc findNext(container: Container): Container =
  if container.children.len > 0:
    return container.children[0]
  var container = container
  while container.parent != nil:
    let n = container.parent.children.find(container)
    assert n != -1, "Container not a child of its parent"
    if n < container.parent.children.high:
      return container.parent.children[n + 1]
    container = container.parent
  return nil

proc findPrevSibling(container: Container): Container =
  if container.parent == nil:
    return nil
  var n = container.parent.children.find(container)
  assert n != -1, "Container not a child of its parent"
  if n == 0:
    n = container.parent.children.len
  return container.parent.children[n - 1]

proc findNextSibling(container: Container): Container =
  if container.parent == nil:
    return nil
  var n = container.parent.children.find(container)
  assert n != -1, "Container not a child of its parent"
  if n == container.parent.children.high:
    n = -1
  return container.parent.children[n + 1]

proc findParent(container: Container): Container =
  return container.parent

proc findFirstChild(container: Container): Container =
  if container.children.len == 0:
    return nil
  return container.children[0]

proc findAny(container: Container): Container =
  let prev = container.findPrev()
  if prev != nil:
    return prev
  return container.findNext()

proc find*(container: Container; dir: NavDirection): Container {.jsfunc.} =
  return case dir
  of ndPrev: container.findPrev()
  of ndNext: container.findNext()
  of ndPrevSibling: container.findPrevSibling()
  of ndNextSibling: container.findNextSibling()
  of ndParent: container.findParent()
  of ndFirstChild: container.findFirstChild()
  of ndAny: container.findAny()

# Returns false on I/O error.
proc handleCommand(container: Container): Opt[void] =
  var packet {.noinit.}: array[3, int] # 0 len, 1 auxLen, 2 packetid
  if not container.iface.stream.readDataLoop(addr packet[0], sizeof(packet)):
    return err()
  assert packet[1] == 0 # no ancillary data possible for BufStream
  container.iface.resolve(packet[2], packet[0] - sizeof(packet[2]), packet[1])
  ok()

proc startLoad(container: Container) =
  if container.config.headless == hmFalse:
    container.repaintLoop()
  container.iface.load().then(proc(res: int) =
    container.onload(res)
  )
  container.iface.getTitle().then(proc(title: string) =
    if title != "":
      container.title = title
      container.triggerEvent(cetTitle)
  )

proc setStream*(container: Container; stream: BufStream) =
  assert cfCloned notin container.flags
  container.iface = newBufferInterface(stream)
  container.startLoad()

proc setCloneStream*(container: Container; stream: BufStream) =
  assert cfCloned in container.flags
  container.iface = cloneInterface(stream)
  if container.iface != nil: # if nil, the buffer is dead.
    # Maybe we have to resume loading. Let's try.
    container.startLoad()

proc onReadLine(container: Container; w: Slice[int];
    handle: (proc(line: SimpleFlexibleLine)); res: GetLinesResult):
    EmptyPromise =
  container.bgcolor = res.bgcolor
  for line in res.lines:
    handle(line)
  if res.numLines > w.b + 1:
    var w = w
    w.a += 24
    w.b += 24
    return container.iface.getLines(w).then(proc(res: GetLinesResult):
        EmptyPromise =
      return container.onReadLine(w, handle, res)
    )
  else:
    container.numLines = res.numLines
    return newResolvedPromise()

# Synchronously read all lines in the buffer.
# Returns false on I/O error.
proc readLines*(container: Container; handle: proc(line: SimpleFlexibleLine)):
    Opt[void] =
  # load succeded
  let w = 0 .. 23
  container.iface.getLines(w).then(proc(res: GetLinesResult): EmptyPromise =
    return container.onReadLine(w, handle, res)
  ).then(proc() =
    if container.config.markLinks:
      # avoid coloring link markers
      container.bgcolor = defaultColor
      container.iface.getLinks.then(proc(res: seq[string]) =
        handle(SimpleFlexibleLine())
        for i, link in res.mypairs:
          handle(SimpleFlexibleLine(str: "[" & $(i + 1) & "] " & link))
      )
  )
  while container.iface.hasPromises:
    # fulfill all promises
    ?container.handleCommand()
  ok()

proc setFormat(cell: var FixedCell; cf: SimpleFormatCell; bgcolor: CellColor) =
  if cf.pos != -1:
    cell.format = cf.format
  if bgcolor != defaultColor and cell.format.bgcolor == defaultColor:
    cell.format.bgcolor = bgcolor

proc drawLines*(container: Container; display: var FixedGrid;
    hlcolor: CellColor) =
  let bgcolor = container.bgcolor
  var by = 0
  let endy = min(container.fromy + display.height, container.numLines)
  for line in container.ilines(container.fromy ..< endy):
    var w = 0 # width of the row so far
    var i = 0 # byte in line.str
    # Skip cells till fromx.
    while w < container.fromx and i < line.str.len:
      let u = line.str.nextUTF8(i)
      w += u.width()
    let dls = by * display.width # starting position of row in display
    # Fill in the gap in case we skipped more cells than fromx mandates (i.e.
    # we encountered a double-width character.)
    var cf = line.findFormat(w)
    var nf = line.findNextFormat(w)
    var k = 0
    while k < w - container.fromx:
      display[dls + k].str &= ' '
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
      if w > container.fromx + display.width:
        break # die on exceeding the width limit
      if nf.pos != -1 and nf.pos <= pw:
        cf = nf
        nf = line.findNextFormat(pw)
      if u.isControlChar():
        display[dls + k].str = u.controlToVisual()
      elif u in TabPUARange:
        for i in 0 ..< uw:
          display[dls + k].str &= ' '
      else:
        for j in pi ..< i:
          display[dls + k].str &= line.str[j]
      display[dls + k].setFormat(cf, bgcolor)
      k += uw
    if bgcolor != defaultColor:
      # Fill the screen if bgcolor is not default.
      while k < display.width:
        display[dls + k].str &= ' '
        display[dls + k].format.bgcolor = bgcolor
        inc k
    # Finally, override cell formatting for highlighted cells.
    let hls = container.findHighlights(container.fromy + by)
    let aw = display.width - (startw - container.fromx) # actual width
    for hl in hls:
      let area = container.colorArea(hl, container.fromy + by,
        startw .. startw + aw)
      for i in area:
        if i - startw >= display.width:
          break
        let n = dls + i - startw
        if hlcolor != defaultColor:
          display[n].format.bgcolor = hlcolor
        else:
          display[n].format.incl(ffReverse)
    inc by

proc highlightMarks*(container: Container; display: var FixedGrid;
    hlcolor: CellColor) =
  for mark in container.marks.values:
    if mark.x in container.fromx ..< container.fromx + display.width and
        mark.y in container.fromy ..< container.fromy + display.height:
      let x = mark.x - container.fromx
      let y = mark.y - container.fromy
      let n = y * display.width + x
      if hlcolor != defaultColor:
        display[n].format.bgcolor = hlcolor
      else:
        display[n].format.incl(ffReverse)

proc findCachedImage*(container: Container; image: PosBitmap;
    offx, erry, dispw: int): CachedImage =
  let imageId = image.bmp.imageId
  for it in container.cachedImages:
    if it.bmp.imageId == imageId and it.width == image.width and
        it.height == image.height and it.offx == offx and it.erry == erry and
        it.dispw == dispw:
      return it
  return nil

# Returns err on I/O error.
proc handleEvent*(container: Container): Opt[void] =
  ?container.handleCommand()
  if container.needslines:
    container.requestLines()
    container.needslines = false
  ok()

proc addContainerModule*(ctx: JSContext) =
  ctx.registerType(Highlight)
  ctx.registerType(Container, name = "Buffer")

{.pop.} # raises: []
