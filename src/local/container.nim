{.push raises: [].}

import std/options
import std/posix

import chagashi/charset
import config/config
import config/conftypes
import config/cookie
import config/mimetypes
import css/render
import html/script
import io/dynstream
import io/promise
import local/select
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsutils
import monoucha/quickjs
import monoucha/tojs
import server/buffer
import server/bufferiface
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
import types/url
import types/winattrs
import utils/strwidth
import utils/twtstr

type
  CursorState = object
    cursor: PagePos
    xend: int
    fromx: int
    fromy: int
    setx: int
    setxrefresh: bool
    setxsave: bool

  ContainerEventType* = enum
    cetSetLoadInfo, cetStatus, cetTitle

  ContainerEvent* = ref object
    t*: ContainerEventType
    next: ContainerEvent

  BufferFilter* = ref object
    cmd*: string

  LoadState* = enum
    lsLoading = "loading"
    lsCanceled = "canceled"
    lsLoaded = "loaded"

  ContainerFlag* = enum
    cfSave, cfIsHTML, cfHistory, cfTailOnLoad, cfCrashed, cfShowLoading,
    cfDeferLoad, cfGotLines

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

  Tab* {.acyclic.} = ref object
    head*: Container
    current*: Container
    prev*: Tab
    next*: Tab

  Mark = object
    id: string
    pos: PagePos

  ProcessHandle* = ref object
    process*: int
    refc*: int

  Container* = ref object of RootObj
    # note: this is not the same as source.request.url (but should be synced
    # with buffer.url)
    url* {.jsget.}: URL
    # note: this is *not* the same as Buffer.cacheId. buffer has the cache ID of
    # the output, while container holds that of the input. Thus pager can
    # re-interpret the original input, and buffer can rewind the (potentially
    # mailcap) output.
    cacheId* {.jsget.}: int
    prev* {.jsget.}: Container
    next* {.jsget.}: Container
    config*: BufferConfig
    loaderConfig*: LoaderClientConfig
    iface* {.jsget.}: BufferInterface
    width* {.jsget.}: int
    height {.jsget.}: int
    phandle*: ProcessHandle
    title: string # used in status msg
    hoverText: array[HoverType, string]
    request*: Request # source request
    # if set, this *overrides* any content type received from the network.
    # (this is because it stores the content type from the -T flag.)
    # beware, this string may include content type attributes, if you want
    # to match it you'll have to use contentType.untilLower(';').
    contentType* {.jsget.}: string
    pos: CursorState
    bpos: seq[CursorState]
    loadinfo*: string
    replace*: Container
    # if we are referenced by another container, replaceRef is set so that we
    # can clear ourselves on discard
    replaceRef*: Container
    retry*: URL
    sourcepair*: Container # pointer to buffer with a source view (may be nil)
    event: ContainerEvent
    lastEvent: ContainerEvent
    startpos: Option[CursorState]
    hasStart {.jsget.}: bool
    redirectDepth {.jsget.}: int
    select* {.jsgetset.}: Select
    currentSelection* {.jsget.}: Highlight
    tmpJumpMark: PagePos
    jumpMark: PagePos
    marks: seq[Mark]
    filter*: BufferFilter
    loadState* {.jsgetset.}: LoadState
    needslines: bool
    lastPeek: HoverType
    flags*: set[ContainerFlag]
    #TODO this is inaccurate, because charsetStack can desync
    charset*: Charset
    charsetStack*: seq[Charset]
    mainConfig: Config
    images*: seq[PosBitmap]
    imageCache: ImageCache
    refreshUrl {.jsget.}: URL
    refreshMillis {.jsget.}: int
    tab*: Tab
    jsctx: JSContext

  NavDirection* = enum
    ndPrev = "prev"
    ndNext = "next"
    ndAny = "any"

jsDestructor(Container)

# Forward declarations
proc triggerEvent(container: Container; t: ContainerEventType)
proc updateCursor(container: Container)
proc sendCursorPosition(container: Container): EmptyPromise
proc loaded(container: Container)
proc setCursorY*(container: Container; y: int; refresh = true)

proc newContainer*(config: BufferConfig; loaderConfig: LoaderClientConfig;
    url: URL; request: Request; attrs: WindowAttributes; title: string;
    redirectDepth: int; flags: set[ContainerFlag]; contentType: string;
    charsetStack: seq[Charset]; cacheId: int; mainConfig: Config; tab: Tab;
    ctx: JSContext): Container =
  let host = request.url.host
  let loadinfo = (if host != "":
    "Connecting to " & host
  else:
    "Loading " & $request.url) & "..."
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
    pos: CursorState(setx: -1),
    loadinfo: loadinfo,
    cacheId: cacheId,
    phandle: ProcessHandle(process: -1, refc: 1),
    mainConfig: mainConfig,
    flags: flags,
    lastPeek: HoverType.high,
    tab: tab,
    jsctx: ctx
  )

# shallow clone of buffer
proc clone*(container: Container; newurl: URL; loader: FileLoader):
    tuple[fd: cint, c: Container] =
  if container.iface == nil:
    return (-1, nil)
  var sv {.noinit.}: array[2, cint]
  if socketpair(AF_UNIX, SOCK_STREAM, IPPROTO_IP, sv) != 0:
    return (-1, nil)
  let url = if newurl != nil:
    newurl
  else:
    container.url
  let p = container.iface.clone(url, sv[1])
  discard close(sv[1])
  if p == nil:
    return (-1, nil)
  let nc = Container()
  nc[] = container[]
  nc.url = url
  nc.retry = nil
  nc.prev = nil
  nc.next = nil
  nc.select = nil
  nc.images = @[]
  nc.needslines = true
  nc.imageCache = ImageCache()
  inc nc.phandle.refc
  (sv[0], nc)

proc append*(this, other: Container) =
  if other.prev != nil:
    other.prev.next = other.next
  if other.next != nil:
    other.next.prev = other.prev
  other.next = this.next
  if this.next != nil:
    this.next.prev = other
  other.prev = this
  this.next = other

proc remove*(this: Container) =
  if this.prev != nil:
    this.prev.next = this.next
  if this.next != nil:
    this.next.prev = this.prev
  if this.tab.current == this:
    this.tab.current = if this.prev != nil: this.prev else: this.next
  if this.tab.head == this:
    this.tab.head = this.next
  this.tab = nil
  this.next = nil
  this.prev = nil

# tab may be nil.
# Returns the old tab if it has become empty.
proc setTab*(container: Container; tab: Tab): Tab =
  let oldTab = container.tab
  if oldTab != nil:
    container.remove()
  container.tab = tab
  if tab != nil:
    if tab.current == nil:
      tab.current = container
      tab.head = container
    else:
      tab.current.append(container)
  if oldTab != nil and oldTab.current == nil:
    return oldTab
  nil

proc lineLoaded(container: Container; y: int): bool =
  if container.iface == nil:
    return false
  return container.iface.lineLoaded(y)

proc getLine(container: Container; y: int): lent SimpleFlexibleLine =
  if container.iface != nil:
    return container.iface.getLine(y)
  let line {.global.} = SimpleFlexibleLine()
  return line

proc getLineStr(container: Container; y: int): lent string =
  return container.getLine(y).str

# private
proc history(container: Container): bool {.jsfget.} =
  return cfHistory in container.flags

# private
proc save(container: Container): bool {.jsfget.} =
  return cfSave in container.flags

# private
proc charsetOverride(ctx: JSContext; container: Container): JSValue {.jsfget.} =
  let charset = container.config.charsetOverride
  if charset != CHARSET_UNKNOWN:
    return ctx.toJS(charset)
  return JS_NULL

# private
proc scripting(ctx: JSContext; container: Container): ScriptingMode {.jsfget.} =
  return container.config.scripting

# private
proc cookie(ctx: JSContext; container: Container): CookieMode {.jsfget.} =
  return container.loaderConfig.cookieMode

proc cursorx*(container: Container): int {.jsfget.} =
  container.pos.cursor.x

proc cursory*(container: Container): int {.jsfget.} =
  container.pos.cursor.y

proc fromx*(container: Container): int {.jsfget.} =
  container.pos.fromx

proc fromy*(container: Container): int {.jsfget.} =
  container.pos.fromy

proc xend(container: Container): int {.inline.} =
  container.pos.xend

proc process*(container: Container): int {.jsfget.} =
  container.phandle.process

proc numLines*(container: Container): int {.jsfget.} =
  let iface = container.iface
  if iface == nil:
    return 0
  return iface.numLines

proc lastVisibleLine(container: Container): int =
  min(container.fromy + container.height, container.numLines) - 1

proc currentLine(container: Container): lent string =
  return container.getLineStr(container.cursory)

# private
# Returns the X position of the first cell occupied by the character the cursor
# currently points to.
proc cursorFirstX(container: Container): int {.jsfunc.} =
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

# private
# Returns the X position of the last cell occupied by the character the cursor
# currently points to.
proc cursorLastX(container: Container): int {.jsfunc.} =
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

# private
proc unsetReplace(container: Container): Container {.jsfunc.} =
  let replace = container.replace
  if replace != nil:
    replace.replaceRef = nil
    container.replace = nil
  return replace

# private
proc setReplace(container, replace: Container) {.jsfunc.} =
  container.replace = replace
  replace.replaceRef = container

proc acursorx*(container: Container): int {.jsfget.} =
  max(0, container.cursorDispX() - container.fromx)

proc acursory*(container: Container): int {.jsfget.} =
  container.cursory - container.fromy

# private
proc maxScreenWidth(container: Container): int {.jsfunc.} =
  result = 0
  for y in container.fromy..container.lastVisibleLine:
    result = max(container.getLineStr(y).width(), result)

proc getTitle*(container: Container): string {.jsfget: "title".} =
  if container.title != "":
    return container.title
  return container.url.serialize(excludepassword = true)

# private
proc currentLineWidth(container: Container; s = 0; e = int.high): int
    {.jsfunc.} =
  if container.numLines == 0:
    return 0
  return container.currentLine.width(s, e)

proc maxfromy(container: Container): int =
  return max(container.numLines - container.height, 0)

proc maxfromx(container: Container): int =
  return max(container.maxScreenWidth() - container.width, 0)

proc atPercentOf*(container: Container): int =
  if container.numLines == 0:
    return 100
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

proc getHoverText*(container: Container): string =
  for t in HoverType:
    if container.hoverText[t] != "":
      return container.hoverText[t]
  ""

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

# private
proc queueDraw*(container: Container) =
  if container.iface != nil:
    container.iface.redraw = true

proc requestLines(container: Container): EmptyPromise =
  if container.iface == nil:
    return newResolvedPromise()
  let w = container.lineWindow
  return container.iface.getLines(w).then(proc(res: GetLinesResult) =
    let iface = container.iface
    iface.lines.setLen(w.len)
    iface.lineShift = w.a
    container.flags.incl(cfGotLines)
    for y in 0 ..< min(res.lines.len, w.len):
      iface.lines[y] = res.lines[y]
    let isBgNew = container.iface.bgcolor != res.bgcolor
    if isBgNew:
      container.iface.bgcolor = res.bgcolor
    if res.numLines != iface.numLines:
      iface.numLines = res.numLines
      container.updateCursor()
      if container.startpos.isSome and
          res.numLines >= container.startpos.get.cursor.y:
        container.pos = container.startpos.get
        container.iface.fromx = container.fromx
        container.iface.fromy = container.fromy
        container.needslines = true
        container.startpos = none(CursorState)
        discard container.sendCursorPosition()
      if container.loadState != lsLoading:
        container.triggerEvent(cetStatus)
    if res.numLines > 0:
      container.updateCursor()
      if cfTailOnLoad in container.flags:
        container.flags.excl(cfTailOnLoad)
        container.setCursorY(int.high)
    let cw = container.fromy ..< container.fromy + container.height
    if w.a in cw or w.b in cw or cw.a in w or cw.b in w or isBgNew:
      container.queueDraw()
    container.images.setLen(0)
    for image in res.images:
      if image.width > 0 and image.height > 0 and
          image.bmp.width > 0 and image.bmp.height > 0:
        container.images.add(image)
    if cfDeferLoad in container.flags:
      container.flags.excl(cfDeferLoad)
      container.loaded()
  )

proc repaintLoop(container: Container) =
  if container.iface == nil:
    return
  container.iface.onReshape().then(proc() =
    container.requestLines().then(proc() = container.repaintLoop())
  )

# private
proc sendCursorPosition(container: Container): EmptyPromise {.jsfunc.} =
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

# public
proc setFromY(container: Container; y: int) {.jsfunc.} =
  if container.pos.fromy != y and container.iface != nil:
    container.pos.fromy = max(min(y, container.maxfromy), 0)
    container.iface.fromy = container.pos.fromy
    container.needslines = true
    container.queueDraw()

# public
proc setFromX(container: Container; x: int; refresh = true) {.jsfunc.} =
  if refresh:
    container.flags.incl(cfShowLoading)
  if container.pos.fromx != x and container.iface != nil:
    container.pos.fromx = max(min(x, container.maxfromx), 0)
    container.iface.fromx = container.pos.fromx
    if container.pos.fromx > container.cursorx:
      container.pos.cursor.x = min(container.pos.fromx,
        container.currentLineWidth())
      if refresh:
        discard container.sendCursorPosition()
    container.queueDraw()

# public
proc setFromXY(container: Container; x, y: int) {.jsfunc.} =
  container.setFromY(y)
  container.setFromX(x)

# public
# Set the cursor to the xth column. 0-based.
# * `refresh = false' inhibits reporting of the cursor position to the buffer.
# * `save = false' inhibits cursor movement if it is currently outside the
#   screen, and makes it so cursorx is not saved for restoration on cursory
#   movement.
proc setCursorX(container: Container; x: int; refresh = true; save = true)
    {.jsfunc.} =
  if refresh:
    container.flags.incl(cfShowLoading)
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
    container.pos.cursor.x = x
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
    container.pos.cursor.x = container.fromx
  elif x > container.cursorx:
    # target x is greater than current x; a simple case, just shift fromx too
    # accordingly
    container.setFromX(max(x - container.width + 1, container.fromx), false)
    container.pos.cursor.x = x
  if container.cursorx == x and container.currentSelection != nil and
      container.currentSelection.x2 != x:
    container.currentSelection.x2 = x
    container.queueDraw()
  if refresh:
    discard container.sendCursorPosition()
  if save:
    container.pos.xend = container.cursorx

# private
proc restoreCursorX(container: Container) {.jsfunc.} =
  let x = clamp(container.currentLineWidth() - 1, 0, container.xend)
  container.setCursorX(x, false, false)

# public
proc setCursorY*(container: Container; y: int; refresh = true) {.jsfunc.} =
  if refresh:
    container.flags.incl(cfShowLoading)
  let y = max(min(y, container.numLines - 1), 0)
  if y >= container.fromy and y - container.height < container.fromy:
    discard
  elif y > container.cursory:
    container.setFromY(y - container.height + 1)
  else:
    container.setFromY(y)
  if container.cursory == y:
    return
  container.pos.cursor.y = y
  if container.currentSelection != nil and container.currentSelection.y2 != y:
    container.queueDraw()
    container.currentSelection.y2 = y
  container.restoreCursorX()
  if refresh:
    discard container.sendCursorPosition()
    # cursor moved, trigger status so the status is recomputed
    container.triggerEvent(cetStatus)

# public
proc setCursorXY*(container: Container; x, y: int; refresh = true) {.jsfunc.} =
  container.setCursorY(y, refresh)
  container.setCursorX(x, refresh)

# public
# zz
proc centerLine(container: Container; n = 0) {.jsfunc.} =
  if n != 0:
    container.setCursorY(n - 1)
  container.setFromY(container.cursory - container.height div 2)

# public
proc centerColumn(container: Container) {.jsfunc.} =
  container.setFromX(container.cursorx - container.width div 2)

# public
proc setCursorXYCenter(container: Container; x, y: int; refresh = true)
    {.jsfunc.} =
  let fy = container.fromy
  let fx = container.fromx
  container.setCursorXY(x, y, refresh)
  if fy != container.fromy:
    container.centerLine()
  if fx != container.fromx:
    container.centerColumn()

# private
proc markPos0(container: Container) {.jsfunc.} =
  container.tmpJumpMark = (container.cursorx, container.cursory)

# private
proc markPos(container: Container) {.jsfunc.} =
  let pos = container.tmpJumpMark
  if container.cursorx != pos.x or container.cursory != pos.y:
    container.jumpMark = pos

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

# private
proc pushCursorPos(container: Container) {.jsfunc.} =
  container.bpos.add(container.pos)

# private
proc popCursorPos(container: Container; nojump = false) {.jsfunc.} =
  if container.bpos.len > 0:
    container.pos = container.bpos.pop()
    if container.iface != nil:
      container.iface.fromx = container.fromx
      container.iface.fromy = container.fromy
    if not nojump:
      container.updateCursor()
      discard container.sendCursorPosition()
    container.needslines = true

# private
proc copyCursorPos(container, c2: Container) {.jsfunc.} =
  if c2.startpos.isSome:
    container.startpos = c2.startpos
  else:
    container.startpos = some(c2.pos)
  container.hasStart = true

proc findMark(container: Container; id: string): int =
  for i, it in container.marks.mypairs:
    if it.id == id:
      return i
  -1

# public
proc setMark(container: Container; id: string; x = -1; y = -1): bool
    {.jsfunc.} =
  let x = if x == -1: container.cursorx else: x
  let y = if y == -1: container.cursory else: y
  let i = container.findMark(id)
  if i != -1:
    container.marks[i].pos = (x, y)
  else:
    container.marks.add(Mark(id: id, pos: (x, y)))
  container.queueDraw()
  i == -1

# public
proc clearMark(container: Container; id: string): bool {.jsfunc.} =
  let i = container.findMark(id)
  if i != -1:
    container.marks.del(i)
    container.queueDraw()
  i != -1

# public
proc getMarkPos(ctx: JSContext; container: Container; id: string): JSValue
    {.jsfunc.} =
  if id == "`" or id == "'":
    return ctx.toJS(container.jumpMark)
  let i = container.findMark(id)
  if i != -1:
    return ctx.toJS(container.marks[i].pos)
  return JS_NULL

# public
proc findNextMark(ctx: JSContext; container: Container; x = -1; y = -1): JSValue
    {.jsfunc.} =
  let x = if x < 0: container.cursorx else: x
  let y = if y < 0: container.cursory else: y
  var best: PagePos = (int.high, int.high)
  var j = -1
  for i, mark in container.marks.mypairs:
    if mark.pos.y < y or mark.pos.y == y and mark.pos.x <= x:
      continue
    if mark.pos.y < best.y or mark.pos.y == best.y and mark.pos.x < best.x:
      best = mark.pos
      j = i
  if j != -1:
    return ctx.toJS(container.marks[j].id)
  return JS_NULL

# public
proc findPrevMark(ctx: JSContext; container: Container; x = -1; y = -1):
    JSValue {.jsfunc.} =
  let x = if x < 0: container.cursorx else: x
  let y = if y < 0: container.cursory else: y
  var best: PagePos = (-1, -1)
  var j = -1
  for i, mark in container.marks.mypairs:
    if mark.pos.y > y or mark.pos.y == y and mark.pos.x >= x:
      continue
    if mark.pos.y > best.y or mark.pos.y == best.y and mark.pos.x > best.x:
      best = mark.pos
      j = i
  if j != -1:
    return ctx.toJS(container.marks[j].id)
  return JS_NULL

# private
proc setCurrentSelection(ctx: JSContext; container: Container;
    val: JSValueConst): Opt[void] {.jsfset: "currentSelection".} =
  if JS_IsNull(val):
    container.currentSelection = nil
  else:
    ?ctx.fromJS(val, container.currentSelection)
  ok()

# public
proc toggleImages(container: Container) {.jsfunc.} =
  if container.iface == nil:
    return
  container.iface.toggleImages().then(proc(images: bool) =
    container.config.images = images
  )

# private
proc setLoadInfo*(container: Container; msg: string) {.jsfunc.} =
  container.loadinfo = msg
  container.triggerEvent(cetSetLoadInfo)

proc loaded(container: Container) =
  container.loadinfo = ""
  container.loadState = lsLoaded
  #TODO
  let ctx = container.jsctx
  let loaded = JS_NewAtom(ctx, cstring"loaded")
  let this = ctx.toJS(container)
  let headless = ctx.toJS(container.config.headless != hmFalse)
  let metaRefresh = ctx.toJS(container.config.metaRefresh)
  let autofocus = ctx.toJS(container.config.autofocus)
  let res = ctx.invokeSink(this, loaded, headless, metaRefresh, autofocus)
  JS_FreeAtom(ctx, loaded)
  JS_FreeValue(ctx, this)
  JS_FreeValue(ctx, res)

#TODO this should be called with a timeout.
proc onload(container: Container; res: LoadResult) =
  if container.loadState == lsCanceled:
    return
  case res.bs
  of bsLoaded:
    if cfGotLines notin container.flags:
      # We cannot call loaded here because of a subtle phase ordering issue
      # on reload:
      # * load sends a cetLoad event to pager
      # * pager deletes the buffer we are replacing
      # * now, if lines haven't been requested yet, then we'll necessarily
      #   see an empty screen flash because the reloaded buffer is already
      #   deleted
      container.flags.incl(cfDeferLoad)
      container.needslines = true
    else:
      container.loaded()
    return # skip next load
  of bsLoadingResources:
    container.setLoadInfo($res.n & "/" & $res.len & " stylesheets loaded")
  of bsLoadingImages:
    container.setLoadInfo($res.n & "/" & $res.len & " images loaded")
  of bsLoadingPage:
    container.setLoadInfo(convertSize(res.n) & " loaded")
  discard container.iface.load().then(proc(res: LoadResult) =
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
      response.url, container.loaderConfig.cookieMode == cmSave, http = true)
  # set referrer policy, if any
  if container.config.refererFrom:
    let referrerPolicy = response.getReferrerPolicy()
    container.loaderConfig.referrerPolicy = referrerPolicy.get(DefaultPolicy)
  else:
    container.loaderConfig.referrerPolicy = rpNoReferrer
  # setup content type; note that isSome means an override so we skip it
  if container.contentType == "":
    var contentType = response.getLongContentType("application/octet-stream")
    if contentType.until(';') == "application/octet-stream":
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
  let refresh = parseRefresh(response.headers.getFirst("Refresh"),
    container.url)
  container.refreshUrl = refresh.url
  container.refreshMillis = refresh.n

proc cancel*(container: Container) =
  if container.iface != nil:
    container.iface.cancel()

# private
proc closeSelect(container: Container) {.jsfunc.} =
  container.select = nil
  container.queueDraw()

# private
proc showLoading(container: Container) {.jsfunc.} =
  container.flags.incl(cfShowLoading)

proc windowChange*(container: Container; attrs: WindowAttributes) =
  container.width = attrs.width
  container.height = attrs.height - 1
  if container.iface != nil:
    var attrs = attrs
    # subtract status line height
    attrs.height -= 1
    attrs.heightPx -= attrs.ppl
    let x = container.cursorx
    let y = container.cursory
    container.iface.windowChange(attrs, x, y).then(proc(pos: PagePos) =
      container.setCursorXYCenter(pos.x, pos.y)
    )
  if container.select != nil:
    container.select.windowChange(container.width, container.height)

proc clearHover*(container: Container) =
  container.lastPeek = HoverType.high

proc getPeekCursorStr*(container: Container): string =
  var p = container.lastPeek
  while true:
    if p < HoverType.high:
      inc p
    else:
      p = HoverType.low
    if container.hoverText[p] != "" or p == container.lastPeek:
      break
  let s = container.hoverText[p]
  container.lastPeek = p
  s

# public
proc hoverLink(container: Container): lent string {.jsfget.} =
  return container.hoverText[htLink]

# public
proc hoverTitle(container: Container): lent string {.jsfget.} =
  return container.hoverText[htTitle]

# public
proc hoverImage(container: Container): lent string {.jsfget.} =
  return container.hoverText[htImage]

# public
proc hoverCachedImage(container: Container): lent string {.jsfget.} =
  return container.hoverText[htCachedImage]

# public
proc find*(container: Container; dir: NavDirection): Container {.jsfunc.} =
  return case dir
  of ndPrev: container.prev
  of ndNext: container.next
  of ndAny:
    if container.prev != nil: container.prev else: container.next

# Returns false on I/O error.
proc handleCommand(container: Container): Opt[void] =
  var packet {.noinit.}: array[3, int] # 0 len, 1 auxLen, 2 packetid
  ?container.iface.stream.readLoop(addr packet[0], sizeof(packet))
  container.iface.resolve(packet[2], packet[0] - sizeof(packet[2]), packet[1])
  ok()

proc startLoad(container: Container) =
  if container.config.headless == hmFalse:
    container.repaintLoop()
  container.iface.load().then(proc(res: LoadResult) =
    container.onload(res)
  )
  container.iface.getTitle().then(proc(title: string) =
    if title != "":
      container.title = title
      container.triggerEvent(cetTitle)
  )

proc setStream*(container: Container; stream: BufStream) =
  container.iface = newBufferInterface(stream)
  container.startLoad()

type HandleReadLine = proc(line: SimpleFlexibleLine): Opt[void]

proc onReadLine(container: Container; w: Slice[int]; handle: HandleReadLine;
    res: GetLinesResult): EmptyPromise =
  container.iface.bgcolor = res.bgcolor
  for line in res.lines:
    if handle(line).isErr:
      return nil
  if res.numLines > w.b + 1:
    var w = w
    w.a += 24
    w.b += 24
    return container.iface.getLines(w).then(proc(res: GetLinesResult):
        EmptyPromise =
      return container.onReadLine(w, handle, res)
    )
  container.iface.numLines = res.numLines
  return nil

# Synchronously read all lines in the buffer.
# Returns false on I/O error.
proc readLines*(container: Container; handle: HandleReadLine): Opt[void] =
  if container.iface == nil:
    return err()
  # load succeeded
  let w = 0 .. 23
  container.iface.getLines(w).then(proc(res: GetLinesResult): EmptyPromise =
    return container.onReadLine(w, handle, res)
  ).then(proc() =
    if container.config.markLinks:
      # avoid coloring link markers
      container.iface.bgcolor = defaultColor
      container.iface.getLinks.then(proc(res: seq[string]) =
        if handle(SimpleFlexibleLine()).isErr:
          return
        for i, link in res.mypairs:
          var s = "[" & $(i + 1) & "] " & link
          if handle(SimpleFlexibleLine(str: move(s))).isErr:
            return
      )
  )
  while container.iface.hasPromises:
    # fulfill all promises
    ?container.handleCommand()
  ok()

proc highlightMarks*(container: Container; display: var FixedGrid;
    hlcolor: CellColor) =
  for mark in container.marks:
    if mark.pos.x in container.fromx ..< container.fromx + display.width and
        mark.pos.y in container.fromy ..< container.fromy + display.height:
      let x = mark.pos.x - container.fromx
      let y = mark.pos.y - container.fromy
      let n = y * display.width + x
      if hlcolor != defaultColor:
        display[n].format.bgcolor = hlcolor
      else:
        display[n].format.incl(ffReverse)

iterator cachedImages(container: Container): CachedImage =
  var it = container.imageCache.head
  while it != nil:
    yield it
    it = it.next

proc findCachedImage*(container: Container;
    imageId, width, height, offx, erry, dispw: int): CachedImage =
  for it in container.cachedImages:
    if it.bmp.imageId == imageId and it.width == width and
        it.height == height and it.offx == offx and it.erry == erry and
        it.dispw == dispw:
      return it
  return nil

proc clearCachedImages*(container: Container; loader: FileLoader) =
  for cachedImage in container.cachedImages:
    if cachedImage.state == cisLoaded:
      loader.removeCachedItem(cachedImage.cacheId)
    cachedImage.state = cisCanceled
  container.imageCache.head = nil
  container.imageCache.tail = nil

proc addCachedImage*(container: Container; image: CachedImage) =
  if container.imageCache.tail == nil:
    container.imageCache.head = image
  else:
    container.imageCache.tail.next = image
  container.imageCache.tail = image

# Returns err on I/O error.
proc handleEvent*(container: Container): Opt[void] =
  ?container.handleCommand()
  if container.needslines:
    discard container.requestLines()
    container.needslines = false
  ok()

proc addContainerModule*(ctx: JSContext): Opt[void] =
  ?ctx.registerType(Container, name = "Buffer")
  ok()

{.pop.} # raises: []
