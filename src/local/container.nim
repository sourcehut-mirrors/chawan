import std/deques
import std/options
import std/os
import std/posix
import std/tables

import chagashi/charset
import config/config
import config/mimetypes
import io/dynstream
import io/promise
import layout/renderdocument
import loader/headers
import loader/loaderiface
import loader/request
import loader/response
import local/select
import monoucha/javascript
import monoucha/jsregex
import monoucha/jstypes
import server/buffer
import types/bitmap
import types/blob
import types/cell
import types/color
import types/cookie
import types/opt
import types/referrer
import types/url
import types/winattrs
import utils/luwrap
import utils/mimeguess
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
    cetAnchor, cetNoAnchor, cetReadLine, cetReadArea, cetReadFile, cetOpen,
    cetSetLoadInfo, cetStatus, cetAlert, cetLoaded, cetTitle, cetCancel,
    cetMetaRefresh

  ContainerEvent* = object
    case t*: ContainerEventType
    of cetReadLine:
      prompt*: string
      value*: string
      password*: bool
    of cetReadArea:
      tvalue*: string
    of cetOpen:
      request*: Request
      save*: bool
      url*: URL
    of cetAnchor, cetNoAnchor:
      anchor*: string
    of cetAlert:
      msg*: string
    of cetMetaRefresh:
      refreshIn*: int
      refreshURL*: URL
    else: discard

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
    cfCloned, cfUserRequested, cfHasStart, cfCanReinterpret, cfSave, cfIsHTML

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
    #TODO this is inaccurate, because charsetStack can desync
    charset*: Charset
    charsetStack*: seq[Charset]
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
    height* {.jsget.}: int
    title*: string # used in status msg
    hoverText: array[HoverType, string]
    lastPeek: HoverType
    request*: Request # source request
    # if set, this *overrides* any content type received from the network. (this
    # is because it stores the content type from the -T flag.)
    contentType* {.jsget.}: Option[string]
    pos: CursorPosition
    bpos: seq[CursorPosition]
    highlights: seq[Highlight]
    process* {.jsget.}: int
    clonedFrom*: int
    loadinfo*: string
    lines: SimpleFlexibleGrid
    lineshift: int
    numLines*: int
    replace*: Container
    replaceBackup*: Container # for redirection; when set, we get discarded
    # if we are referenced by another container, replaceRef is set so that we
    # can clear ourselves on discard
    #TODO this is a mess :(
    replaceRef*: Container
    code*: int # note: this is not the status code, but the ConnectErrorCode.
    errorMessage*: string
    retry*: seq[URL]
    hlon*: bool # highlight on?
    sourcepair*: Container # pointer to buffer with a source view (may be nil)
    needslines*: bool
    loadState*: LoadState
    events*: Deque[ContainerEvent]
    startpos: Option[CursorPosition]
    redirectDepth*: int
    select* {.jsget.}: Select
    currentSelection {.jsget.}: Highlight
    tmpJumpMark: PagePos
    jumpMark: PagePos
    marks: Table[string, PagePos]
    filter*: BufferFilter
    bgcolor*: CellColor
    tailOnLoad*: bool
    mainConfig*: Config
    flags*: set[ContainerFlag]
    images*: seq[PosBitmap]
    cachedImages*: seq[CachedImage]
    luctx: LUContext
    redraw*: bool

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
    contentType: Option[string]; charsetStack: seq[Charset]; cacheId: int;
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

func location(container: Container): URL {.jsfget.} =
  return container.url

proc c_rename(oldname, newname: cstring): cint {.importc: "rename",
  header: "<stdio.h>".}

proc clone*(container: Container; newurl: URL; loader: FileLoader):
    Promise[Container] =
  if container.iface == nil:
    return nil
  let url = if newurl != nil:
    newurl
  else:
    container.url
  let p = container.iface.clone(url)
  # create a server socket, pass it on to the buffer, then move it to
  # the expected path after the buffer forked itself
  #TODO this is very ugly
  let ssock = newServerSocket(loader.sockDir, loader.sockDirFd,
    loader.clientPid)
  SocketStream(container.iface.stream.source).sendFd(ssock.fd)
  ssock.close(unlink = false)
  return p.then(proc(pid: int): Container =
    if pid == -1:
      return nil
    let newPath = getSocketPath(loader.sockDir, pid)
    let oldPath = getSocketPath(loader.sockDir, loader.clientPid)
    if c_rename(cstring(oldPath), cstring(newPath)) == -1:
      return nil
    let nc = Container()
    nc[] = container[]
    nc.url = url
    nc.process = pid
    nc.clonedFrom = container.process
    nc.flags.incl(cfCloned)
    nc.retry = @[]
    nc.parent = nil
    nc.children = @[]
    return nc
  )

func lineLoaded(container: Container; y: int): bool =
  return y - container.lineshift in 0..container.lines.high

func getLine(container: Container; y: int): SimpleFlexibleLine =
  if container.lineLoaded(y):
    return container.lines[y - container.lineshift]

iterator ilines*(container: Container; slice: Slice[int]): SimpleFlexibleLine
    {.inline.} =
  for y in slice:
    yield container.getLine(y)

func cursorx*(container: Container): int {.jsfget.} =
  container.pos.cursorx

func cursory*(container: Container): int {.jsfget.} =
  container.pos.cursory

func fromx*(container: Container): int {.jsfget.} =
  container.pos.fromx

func fromy*(container: Container): int {.jsfget.} =
  container.pos.fromy

func xend(container: Container): int {.inline.} =
  container.pos.xend

func lastVisibleLine(container: Container): int =
  min(container.fromy + container.height, container.numLines) - 1

func currentLine(container: Container): string =
  return container.getLine(container.cursory).str

func findColBytes(s: string; endx: int; startx = 0; starti = 0): int =
  var w = startx
  var i = starti
  while i < s.len and w < endx:
    let u = s.nextUTF8(i)
    w += u.width()
  return i

func cursorBytes(container: Container; y: int; cc = container.cursorx): int =
  return container.getLine(y).str.findColBytes(cc, 0, 0)

func currentCursorBytes(container: Container; cc = container.cursorx): int =
  return container.cursorBytes(container.cursory, cc)

# Returns the X position of the first cell occupied by the character the cursor
# currently points to.
func cursorFirstX(container: Container): int =
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
func cursorLastX(container: Container): int =
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
func cursorDispX(container: Container): int =
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

func acursorx*(container: Container): int =
  max(0, container.cursorDispX() - container.fromx)

func acursory*(container: Container): int =
  container.cursory - container.fromy

func maxScreenWidth(container: Container): int =
  for line in container.ilines(container.fromy..container.lastVisibleLine):
    result = max(line.str.width(), result)

func getTitle*(container: Container): string {.jsfget: "title".} =
  if container.title != "":
    return container.title
  return container.url.serialize(excludepassword = true)

func currentLineWidth(container: Container): int =
  if container.numLines == 0: return 0
  return container.currentLine.width()

func maxfromy(container: Container): int =
  return max(container.numLines - container.height, 0)

func maxfromx(container: Container): int =
  return max(container.maxScreenWidth() - container.width, 0)

func atPercentOf*(container: Container): int =
  if container.numLines == 0: return 100
  return (100 * (container.cursory + 1)) div container.numLines

func lineWindow(container: Container): Slice[int] =
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

func startx(hl: Highlight): int =
  if hl.y1 < hl.y2:
    hl.x1
  elif hl.y2 < hl.y1:
    hl.x2
  else:
    min(hl.x1, hl.x2)

func starty(hl: Highlight): int =
  return min(hl.y1, hl.y2)

func endx(hl: Highlight): int =
  if hl.y1 > hl.y2:
    hl.x1
  elif hl.y2 > hl.y1:
    hl.x2
  else:
    max(hl.x1, hl.x2)

func endy(hl: Highlight): int =
  return max(hl.y1, hl.y2)

func colorNormal(container: Container; hl: Highlight; y: int;
    limitx: Slice[int]): Slice[int] =
  let starty = hl.starty
  let endy = hl.endy
  if y in starty + 1 .. endy - 1:
    let w = container.getLine(y).str.width()
    return min(limitx.a, w) .. min(limitx.b, w)
  if y == starty and y == endy:
    return max(hl.startx, limitx.a) .. min(hl.endx, limitx.b)
  if y == starty:
    let w = container.getLine(y).str.width()
    return max(hl.startx, limitx.a) .. min(limitx.b, w)
  if y == endy:
    let w = container.getLine(y).str.width()
    return min(limitx.a, w) .. min(hl.endx, limitx.b)

func colorArea(container: Container; hl: Highlight; y: int;
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
    of stLine:
      if y in hl.starty .. hl.endy:
        let w = container.getLine(y).str.width()
        return min(limitx.a, w) .. min(limitx.b, w)
  else:
    return container.colorNormal(hl, y, limitx)

func findHighlights*(container: Container; y: int): seq[Highlight] =
  for hl in container.highlights:
    if y in hl.starty .. hl.endy:
      result.add(hl)

func getHoverText*(container: Container): string =
  for t in HoverType:
    if container.hoverText[t] != "":
      return container.hoverText[t]
  ""

func isHoverURL*(container: Container; url: URL): bool =
  let hoverurl = parseURL(container.hoverText[htLink])
  return hoverurl.isSome and url.host == hoverurl.get.host

proc triggerEvent(container: Container; event: ContainerEvent) =
  container.events.addLast(event)

proc triggerEvent(container: Container; t: ContainerEventType) =
  container.triggerEvent(ContainerEvent(t: t))

proc setNumLines(container: Container; lines: int; finish = false) =
  if container.numLines != lines:
    container.numLines = lines
    if container.startpos.isSome and finish:
      container.pos = container.startpos.get
      container.startpos = none(CursorPosition)
      container.needslines = true
    container.updateCursor()

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
    var isBgNew = container.bgcolor != res.bgcolor
    if isBgNew:
      container.bgcolor = res.bgcolor
    if res.numLines != container.numLines:
      container.setNumLines(res.numLines, true)
      if container.loadState != lsLoading:
        container.triggerEvent(cetStatus)
    if res.numLines > 0:
      container.updateCursor()
      if container.tailOnLoad:
        container.tailOnLoad = false
        container.cursorLastLine()
    let cw = container.fromy ..< container.fromy + container.height
    if w.a in cw or w.b in cw or cw.a in w or cw.b in w or isBgNew:
      container.queueDraw()
    container.images = res.images
  )

proc sendCursorPosition*(container: Container) =
  if container.iface == nil:
    return
  container.iface.updateHover(container.cursorx, container.cursory)
      .then(proc(res: UpdateHoverResult) =
    if res.hover.len > 0:
      assert res.hover.high <= int(HoverType.high)
      for (ht, s) in res.hover:
        container.hoverText[ht] = s
      container.triggerEvent(cetStatus)
    if res.repaint:
      container.needslines = true
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

proc setCursorXYCenter(container: Container; x, y: int; refresh = true)
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

type BreakFunc = proc(ctx: LUContext; r: uint32): BreakCategory {.nimcall.}

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
    container.setCursorY(container.lastVisibleLine)
    container.alert("Last line is #" & $container.numLines)

proc gotoLine*(container: Container; s: string) =
  if s == "":
    container.redraw = true
  elif s[0] == '^':
    container.cursorFirstLine()
  elif s[0] == '$':
    container.cursorLastLine()
  else:
    let i = parseUInt32(s, allowSign = true)
    if i.isSome and i.get > 0:
      container.markPos0()
      container.setCursorY(int(i.get - 1))
      container.markPos()
    else:
      container.alert("First line is #1") # :)

proc gotoLine*(container: Container; n: int) =
  container.markPos0()
  container.setCursorY(n - 1)
  container.markPos()

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

proc copyCursorPos*(container, c2: Container) =
  container.startpos = some(c2.pos)
  container.flags.incl(cfHasStart)

proc cursorNextLink*(container: Container; n = 1) {.jsfunc.} =
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

proc cursorPrevLink*(container: Container; n = 1) {.jsfunc.} =
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

proc cursorNextParagraph*(container: Container; n = 1) {.jsfunc.} =
  if container.iface == nil:
    return
  container.markPos0()
  container.iface
    .findNextParagraph(container.cursory, n)
    .then(proc(res: int) =
      container.setCursorY(res)
      container.markPos()
    )

proc cursorPrevParagraph*(container: Container; n = 1) {.jsfunc.} =
  if container.iface == nil:
    return
  container.markPos0()
  container.iface
    .findPrevParagraph(container.cursory, n)
    .then(proc(res: int) =
      container.setCursorY(res)
      container.markPos()
    )

proc setMark*(container: Container; id: string; x = none(int);
    y = none(int)): bool {.jsfunc.} =
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

proc clearMark*(container: Container; id: string): bool {.jsfunc.} =
  result = id in container.marks
  container.marks.del(id)
  container.queueDraw()

proc getMarkPos(container: Container; id: string): Opt[PagePos] {.jsfunc.} =
  if id == "`" or id == "'":
    return ok(container.jumpMark)
  container.marks.withValue(id, p):
    return ok(p[])
  return err()

proc gotoMark*(container: Container; id: string): bool {.jsfunc.} =
  container.markPos0()
  let mark = container.getMarkPos(id)
  if mark.isSome:
    let mark = mark.get
    container.setCursorXYCenter(mark.x, mark.y)
    container.markPos()
    return true
  return false

proc gotoMarkY*(container: Container; id: string): bool {.jsfunc.} =
  container.markPos0()
  let mark = container.getMarkPos(id)
  if mark.isSome:
    let mark = mark.get
    container.setCursorXYCenter(0, mark.y)
    container.markPos()
    return true
  return false

proc findNextMark*(container: Container; x = none(int), y = none(int)):
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

proc findPrevMark*(container: Container; x = none(int), y = none(int)):
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

proc cursorNthLink*(container: Container; n = 1) {.jsfunc.} =
  if container.iface == nil:
    return
  container.iface
    .findNthLink(n)
    .then(proc(res: tuple[x, y: int]) =
      if res.x > -1 and res.y != -1:
        container.setCursorXYCenter(res.x, res.y))

proc cursorRevNthLink*(container: Container; n = 1) {.jsfunc.} =
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
    if container.hlon:
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
      container.hlon = false
      container.needslines = true
  elif container.hlon:
    container.clearSearchHighlights()
    container.queueDraw()
    container.needslines = true
    container.hlon = false

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
proc getSelectionText(container: Container; hl: Highlight = nil):
    Promise[string] {.jsfunc.} =
  if container.iface == nil:
    return nil
  let hl = if hl == nil: container.currentSelection else: hl
  if hl == nil:
    return nil
  if hl.t != hltSelect:
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
      for i, line in res.lines:
        let si = line.str.findColBytes(startx)
        let ei = line.str.findColBytes(endx + 1, startx, si) - 1
        if i > 0:
          s &= '\n'
        s &= line.str.substr(si, ei)
    of stLine:
      for i, line in res.lines:
        if i > 0:
          s &= '\n'
        s &= line.str
    return s.expandPUATabsHard()
  )

proc markURL(container: Container) {.jsfunc.} =
  if container.iface == nil:
    return
  var schemes: seq[string] = @[]
  for key in container.mainConfig.external.urimethodmap.map.keys:
    schemes.add(key.until(':'))
  container.iface.markURL(schemes).then(proc() =
    container.needslines = true
  )

proc toggleImages(container: Container) {.jsfunc.} =
  if container.iface == nil:
    return
  container.iface.toggleImages().then(proc() =
    container.needslines = true
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
  if res == -1:
    container.loadState = lsLoaded
    container.setLoadInfo("")
    container.triggerEvent(cetStatus)
    container.triggerEvent(cetLoaded)
    if cfHasStart notin container.flags and (container.url.anchor != "" or
        container.config.autofocus):
      container.requestLines().then(proc(): Promise[GotoAnchorResult] =
        return container.iface.gotoAnchor()
      ).then(proc(res: GotoAnchorResult) =
        if res.found:
          container.setCursorXYCenter(res.x, res.y)
          if res.focus != nil:
            container.onReadLine(res.focus)
      )
    else:
      container.needslines = true
    if container.config.metaRefresh != mrNever:
      container.iface.checkRefresh().then(proc(res: CheckRefreshResult) =
        if res.n >= 0:
          container.triggerEvent(ContainerEvent(
            t: cetMetaRefresh,
            refreshIn: res.n,
            refreshURL: if res.url != nil: res.url else: container.url
          ))
      )
  else:
    container.needslines = true
    container.setLoadInfo(convertSize(res) & " loaded")
    discard container.iface.load().then(proc(res: int) =
      container.onload(res)
    )

proc extractCookies(response: Response): seq[Cookie] =
  result = @[]
  if "Set-Cookie" in response.headers.table:
    for s in response.headers.table["Set-Cookie"]:
      let cookie = newCookie(s, response.url)
      if cookie.isSome:
        result.add(cookie.get)

# Apply data received in response.
# Note: pager must call this before checkMailcap.
proc applyResponse*(container: Container; response: Response;
    mimeTypes: MimeTypes) =
  container.code = response.res
  # accept cookies
  let cookieJar = container.loaderConfig.cookieJar
  if cookieJar != nil:
    cookieJar.add(response.extractCookies())
  # set referrer policy, if any
  let referrerPolicy = response.getReferrerPolicy()
  if container.config.refererFrom:
    if referrerPolicy.isSome:
      container.loaderConfig.referrerPolicy = referrerPolicy.get
  else:
    container.loaderConfig.referrerPolicy = rpNoReferrer
  # setup content type; note that isSome means an override so we skip it
  if container.contentType.isNone:
    var contentType = response.getContentType()
    if contentType == "application/octet-stream":
      contentType = mimeTypes.guessContentType(container.url.pathname,
        "text/plain")
    container.contentType = some(contentType)
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
    for i in countdown(container.config.charsets.high, 0):
      container.charsetStack.add(container.config.charsets[i])
    if container.charsetStack.len == 0:
      container.charsetStack.add(DefaultCharset)
  container.charset = container.charsetStack[^1]

proc remoteCancel*(container: Container) =
  if container.iface != nil:
    container.iface.cancel().then(proc() =
      container.needslines = true
    )
  container.setLoadInfo("")
  container.alert("Canceled loading")

proc cancel*(container: Container) {.jsfunc.} =
  if container.loadState == lsLoading:
    container.loadState = lsCanceled
    if container.iface != nil:
      container.remoteCancel()
    else:
      container.triggerEvent(cetCancel)

proc findAnchor*(container: Container; anchor: string) =
  container.iface.findAnchor(anchor).then(proc(found: bool) =
    if found:
      container.triggerEvent(ContainerEvent(t: cetAnchor, anchor: anchor))
    else:
      container.triggerEvent(ContainerEvent(t: cetNoAnchor, anchor: anchor))
  )

proc readCanceled*(container: Container) =
  container.iface.readCanceled().then(proc(repaint: bool) =
    if repaint:
      container.needslines = true)

proc readSuccess*(container: Container; s: string; fd: cint = -1) =
  let p = container.iface.readSuccess(s, fd != -1)
  if fd != -1:
    container.iface.stream.reallyFlush()
    SocketStream(container.iface.stream.source).sendFd(fd)
  p.then(proc(res: ReadSuccessResult) =
    if res.repaint:
      container.needslines = true
    if res.open != nil:
      container.triggerEvent(ContainerEvent(t: cetOpen, request: res.open))
  )

proc reshape(container: Container): EmptyPromise {.jsfunc.} =
  if container.iface == nil:
    return
  return container.iface.forceRender().then(proc(): EmptyPromise =
    return container.requestLines()
  )

proc selectFinish(opaque: RootRef; select: Select; res: SubmitResult) =
  let container = Container(opaque)
  case res
  of srCancel:
    container.iface.select(select.oselected).then(proc(res: ClickResult) =
      container.onclick(res, save = false)
    )
  of srSubmit:
    container.iface.select(select.selected).then(proc(res: ClickResult) =
      container.onclick(res, save = false)
    )
  container.select = nil

proc displaySelect(container: Container; selectResult: SelectResult) =
  container.select = newSelect(
    selectResult.multiple,
    selectResult.options,
    selectResult.selected,
    container.acursorx,
    container.acursory,
    container.height,
    selectFinish,
    container
  )

proc onclick(container: Container; res: ClickResult; save: bool) =
  if res.repaint:
    container.needslines = true
  if res.open != nil:
    container.triggerEvent(ContainerEvent(
      t: cetOpen,
      request: res.open,
      save: save
    ))
  if res.select.isSome and not save:
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
    request: newRequest(newURL("cache:" & $container.cacheId).get),
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
    container.iface.windowChange(attrs).then(proc() =
      container.needslines = true
    )
  if container.select != nil:
    container.select.windowChange(container.height)

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

func hoverLink(container: Container): string {.jsfget.} =
  return container.hoverText[htLink]

func hoverTitle(container: Container): string {.jsfget.} =
  return container.hoverText[htTitle]

func hoverImage(container: Container): string {.jsfget.} =
  return container.hoverText[htImage]

proc handleCommand(container: Container) =
  var packet: array[3, int] # 0 len, 1 auxLen, 2 packetid
  container.iface.stream.recvDataLoop(addr packet[0], sizeof(packet))
  container.iface.resolve(packet[2], packet[0] - sizeof(packet[2]), packet[1])

proc startLoad(container: Container) =
  container.iface.load().then(proc(res: int) =
    container.onload(res)
  )
  container.iface.getTitle().then(proc(title: string) =
    if title != "":
      container.title = title
      container.triggerEvent(cetTitle)
  )

proc setStream*(container: Container; stream: SocketStream;
    registerFun: proc(fd: int)) =
  assert cfCloned notin container.flags
  container.iface = newBufferInterface(stream, registerFun)
  container.startLoad()

proc setCloneStream*(container: Container; stream: SocketStream;
    registerFun: proc(fd: int)) =
  assert cfCloned in container.flags
  container.iface = cloneInterface(stream, registerFun)
  # Maybe we have to resume loading. Let's try.
  container.startLoad()

proc onreadline(container: Container; w: Slice[int];
    handle: (proc(line: SimpleFlexibleLine)); res: GetLinesResult) =
  for line in res.lines:
    handle(line)
  if res.numLines > w.b + 1:
    var w = w
    w.a += 24
    w.b += 24
    container.iface.getLines(w).then(proc(res: GetLinesResult) =
      container.onreadline(w, handle, res))
  else:
    container.setNumLines(res.numLines, true)

# Synchronously read all lines in the buffer.
proc readLines*(container: Container; handle: proc(line: SimpleFlexibleLine)) =
  if container.code == 0:
    # load succeded
    let w = 0 .. 23
    container.iface.getLines(w).then(proc(res: GetLinesResult) =
      container.onreadline(w, handle, res))
    while container.iface.hasPromises:
      # fulfill all promises
      container.handleCommand()

proc drawLines*(container: Container; display: var FixedGrid; hlcolor: CellColor) =
  let bgcolor = container.bgcolor
  template set_fmt(cell, cf: typed) =
    if cf.pos != -1:
      cell.format = cf.format
    if bgcolor != defaultColor and cell.format.bgcolor == defaultColor:
      cell.format.bgcolor = bgcolor
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
      set_fmt display[dls + k], cf
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
      if u <= 0xFF and char(u) in Controls:
        display[dls + k].str &= '^' & char(u).getControlLetter()
      elif u in TabPUARange:
        for i in 0 ..< uw:
          display[dls + k].str &= ' '
      else:
        for j in pi ..< i:
          display[dls + k].str &= line.str[j]
      set_fmt display[dls + k], cf
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
        var hlformat = display[dls + i - startw].format
        hlformat.bgcolor = hlcolor
        display[dls + i - startw].format = hlformat
    inc by

proc highlightMarks*(container: Container; display: var FixedGrid;
    hlcolor: CellColor) =
  for mark in container.marks.values:
    if mark.x in container.fromx ..< container.fromx + display.width and
        mark.y in container.fromy ..< container.fromy + display.height:
      let x = mark.x - container.fromx
      let y = mark.y - container.fromy
      var hlformat = display[y * display.width + x].format
      hlformat.bgcolor = hlcolor
      display[y * display.width + x].format = hlformat

func findCachedImage*(container: Container; image: PosBitmap;
    offx, erry, dispw: int): CachedImage =
  let imageId = image.bmp.imageId
  for it in container.cachedImages:
    if it.bmp.imageId == imageId and it.width == image.width and
        it.height == image.height and it.offx == offx and it.erry == erry and
        it.dispw == dispw:
      return it
  return nil

proc handleEvent*(container: Container) =
  container.handleCommand()
  if container.needslines:
    container.requestLines()
    container.needslines = false

proc addContainerModule*(ctx: JSContext) =
  ctx.registerType(Highlight)
  ctx.registerType(Container, name = "Buffer")
