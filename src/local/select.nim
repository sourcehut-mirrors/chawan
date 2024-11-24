import monoucha/javascript
import monoucha/jsregex
import types/cell
import utils/luwrap
import utils/strwidth
import utils/twtstr

type
  SelectFinish* = proc(opaque: RootRef; select: Select; res: SubmitResult)
    {.nimcall.}

  SelectOption* = object
    nop*: bool
    s*: string

  Select* = ref object
    options: seq[SelectOption]
    multiple* {.jsget.}: bool
    oselected*: seq[int] # old selection
    selected*: seq[int] # new selection
    fromy* {.jsget.}: int # first index to display
    cursory {.jsget.}: int # selected index
    maxw: int # widest option
    maxh: int # maximum height on screen (yes the naming is dumb)
    # location on screen
    #TODO make this absolute
    x*: int
    y*: int
    redraw*: bool
    bpos: seq[int]
    opaque: RootRef
    finishImpl: SelectFinish

  SubmitResult* = enum
    srCancel, srSubmit

jsDestructor(Select)

proc queueDraw(select: Select) =
  select.redraw = true

func dispheight(select: Select): int =
  return select.maxh - select.y

proc setFromY(select: Select; y: int) =
  select.fromy = max(min(y, select.options.len - select.maxh), 0)

func width*(select: Select): int =
  return select.maxw + 2

func height*(select: Select): int =
  return min(select.options.len + 2, select.maxh)

proc setCursorY*(select: Select; y: int) =
  var y = clamp(y, -1, select.options.high)
  if not select.multiple:
    y = max(y, 0)
  if select.options[max(y, 0)].nop:
    return
  if select.fromy > y:
    select.setFromY(y)
  if select.fromy + select.dispheight <= y:
    select.setFromY(y - select.dispheight + 1)
  select.cursory = y
  select.queueDraw()

proc getCursorX*(select: Select): int =
  if select.cursory == -1:
    return select.x
  return select.x + 1

proc getCursorY*(select: Select): int =
  return select.y + 1 + select.cursory - select.fromy

proc cursorDown(select: Select; n = 1) {.jsfunc.} =
  var y = select.cursory + 1
  var n = n
  while y < select.options.len:
    if not select.options[y].nop:
      dec n
    if n <= 0:
      break
    inc y
  select.setCursorY(y)

proc cursorUp(select: Select; n = 1) {.jsfunc.} =
  var y = select.cursory - 1
  var n = n
  while y >= 0:
    if not select.options[y].nop:
      dec n
    if n <= 0:
      break
    dec y
  select.setCursorY(y)

proc scrollDown(select: Select; n = 1) {.jsfunc.} =
  let tfy = select.fromy + n
  select.setFromY(tfy)
  if select.fromy > select.cursory:
    select.setCursorY(select.fromy)
  elif tfy > select.fromy:
    select.cursorDown(tfy - select.fromy)
  select.queueDraw()

proc scrollUp(select: Select; n = 1) {.jsfunc.} =
  let tfy = select.fromy - n
  select.setFromY(tfy)
  if select.fromy + select.dispheight <= select.cursory:
    select.setCursorY(select.fromy + select.dispheight - 1)
  elif tfy < select.fromy:
    select.cursorUp(select.fromy - tfy)
  select.queueDraw()

proc cursorPrevLink(select: Select; n = 1) {.jsfunc.} =
  select.cursorUp(n)

proc cursorNextLink(select: Select; n = 1) {.jsfunc.} =
  select.cursorDown(n)

proc cursorLinkNavUp(select: Select; n = 1) {.jsfunc.} =
  select.cursorUp(n)

proc cursorLinkNavDown(select: Select; n = 1) {.jsfunc.} =
  select.cursorDown(n)

proc cursorNthLink(select: Select; n = 1) {.jsfunc.} =
  select.setCursorY(n - 1)

proc cursorRevNthLink(select: Select; n = 1) {.jsfunc.} =
  select.setCursorY(select.options.len - n)

proc gotoLine(select: Select; n: int) {.jsfunc.} =
  select.setCursorY(n + 1)

proc cancel(select: Select) {.jsfunc.} =
  select.finishImpl(select.opaque, select, srCancel)

proc submit(select: Select) {.jsfunc.} =
  if not select.multiple:
    select.selected = @[select.cursory]
  select.finishImpl(select.opaque, select, srSubmit)

proc click*(select: Select) {.jsfunc.} =
  if select.cursory >= 0 and select.cursory < select.options.len and
      select.options[select.cursory].nop:
    discard
  elif not select.multiple:
    select.submit()
  elif select.cursory == -1:
    select.submit()
  else:
    var k = select.selected.len
    let i = select.cursory
    for j in 0 ..< select.selected.len:
      if select.selected[j] >= i:
        k = j
        break
    if k < select.selected.len and select.selected[k] == i:
      select.selected.delete(k)
    else:
      select.selected.insert(i, k)
    select.queueDraw()

proc cursorLeft*(select: Select) {.jsfunc.} =
  if select.multiple:
    select.submit()
  else:
    select.cancel()

proc cursorRight(select: Select) {.jsfunc.} =
  select.click()

proc cursorFirstLine(select: Select) {.jsfunc.} =
  if select.cursory != 0:
    select.cursory = 0
    select.fromy = 0
    select.queueDraw()

proc cursorLastLine(select: Select) {.jsfunc.} =
  if select.cursory < select.options.len:
    select.fromy = max(select.options.len - select.maxh, 0)
    select.cursory = select.fromy + select.dispheight - 1
    select.queueDraw()

proc cursorTop(select: Select) {.jsfunc.} =
  select.setCursorY(select.fromy)

proc cursorMiddle(select: Select) {.jsfunc.} =
  select.setCursorY(select.fromy + (select.height - 1) div 2)

proc cursorBottom(select: Select) {.jsfunc.} =
  select.setCursorY(select.fromy + select.height - 1)

proc cursorNextMatch*(select: Select; regex: Regex; wrap: bool) =
  var j = -1
  for i in select.cursory + 1 ..< select.options.len:
    if regex.exec(select.options[i].s).success:
      j = i
      break
  if j != -1:
    select.setCursorY(j)
    select.queueDraw()
  elif wrap:
    for i in 0 ..< select.cursory:
      if regex.exec(select.options[i].s).success:
        j = i
        break
    if j != -1:
      select.setCursorY(j)
      select.queueDraw()

proc cursorPrevMatch*(select: Select; regex: Regex; wrap: bool) =
  var j = -1
  for i in countdown(select.cursory - 1, 0):
    if regex.exec(select.options[i].s).success:
      j = i
      break
  if j != -1:
    select.setCursorY(j)
    select.queueDraw()
  elif wrap:
    for i in countdown(select.options.high, select.cursory):
      if regex.exec(select.options[i].s).success:
        j = i
        break
    if j != -1:
      select.setCursorY(j)
      select.queueDraw()

proc pushCursorPos*(select: Select) =
  select.bpos.add(select.cursory)

proc popCursorPos*(select: Select; nojump = false) =
  select.setCursorY(select.bpos.pop())
  if not nojump:
    select.queueDraw()

const HorizontalBar = "\u2500"
const VerticalBar = "\u2502"
const CornerTopLeft = "\u250C"
const CornerTopRight = "\u2510"
const CornerBottomLeft = "\u2514"
const CornerBottomRight = "\u2518"

proc drawBorders(display: var FixedGrid; sx, ex, sy, ey: int;
    upmore, downmore: bool) =
  for y in sy .. ey:
    var x = 0
    let yi = y * display.width
    while true:
      if display[yi + x].str == "":
        display[yi + x].str = " "
      let w = display[yi + x].str.width()
      if x + w > sx:
        while x < sx:
          display[yi + x].str = " "
          inc x
        break
      x += w
  # Draw corners.
  let tl = if upmore: VerticalBar else: CornerTopLeft
  let tr = if upmore: VerticalBar else: CornerTopRight
  let bl = if downmore: VerticalBar else: CornerBottomLeft
  let br = if downmore: VerticalBar else: CornerBottomRight
  const fmt = Format()
  display[sy * display.width + sx].str = tl
  display[sy * display.width + ex].str = tr
  display[ey * display.width + sx].str = bl
  display[ey * display.width + ex].str = br
  display[sy * display.width + sx].format = fmt
  display[sy * display.width + ex].format = fmt
  display[ey * display.width + sx].format = fmt
  display[ey * display.width + ex].format = fmt
  # Draw top, bottom borders.
  let ups = if upmore: " " else: HorizontalBar
  let downs = if downmore: " " else: HorizontalBar
  for x in sx + 1 .. ex - 1:
    display[sy * display.width + x].str = ups
    display[ey * display.width + x].str = downs
    display[sy * display.width + x].format = fmt
    display[ey * display.width + x].format = fmt
  if upmore:
    display[sy * display.width + sx + (ex - sx) div 2].str = ":"
  if downmore:
    display[ey * display.width + sx + (ex - sx) div 2].str = ":"
  # Draw left, right borders.
  for y in sy + 1 .. ey - 1:
    display[y * display.width + sx].str = VerticalBar
    display[y * display.width + ex].str = VerticalBar
    display[y * display.width + sx].format = fmt
    display[y * display.width + ex].format = fmt

proc drawSelect*(select: Select; display: var FixedGrid) =
  if display.width < 2 or display.height < 2:
    return # border does not fit...
  # Max width, height with one row/column on the sides.
  let mw = display.width - 2
  let mh = display.height - 2
  var sy = select.y
  let si = select.fromy
  var ey = min(sy + select.options.len, mh) + 1
  var sx = select.x
  if sx + select.maxw >= mw:
    sx = display.width - select.maxw
    if sx < 0:
      # This means the widest option is wider than the available screen.
      # w3m simply cuts off the part that doesn't fit, and we do that too,
      # but I feel like this may not be the best solution.
      sx = 0
  var ex = min(sx + select.maxw, mw) + 1
  let upmore = select.fromy > 0
  let downmore = select.fromy + mh < select.options.len
  drawBorders(display, sx, ex, sy, ey, upmore, downmore)
  if select.multiple and not upmore:
    display[sy * display.width + sx].str = "X"
  # move inside border
  inc sy
  inc sx
  var k = 0
  var format = Format()
  while k < select.selected.len and select.selected[k] < si:
    inc k
  for y in sy ..< ey:
    let i = y - sy + si
    var j = 0
    var x = sx
    let dls = y * display.width
    if (select.multiple and k < select.selected.len and
          select.selected[k] == i or
        not select.multiple and select.getCursorY() == y):
      format.flags.incl(ffReverse)
      inc k
    else:
      format.flags.excl(ffReverse)
    while j < select.options[i].s.len:
      let pj = j
      let u = select.options[i].s.nextUTF8(j)
      let uw = u.width()
      let nx = x + uw
      if nx > ex:
        break
      display[dls + x].str = ""
      if u <= 0xFF and char(u) in Controls:
        display[dls + x].str &= '^' & char(u).getControlLetter()
      else:
        for l in pj ..< j:
          display[dls + x].str &= select.options[i].s[l]
      display[dls + x].format = format
      inc x
      while x < nx:
        display[dls + x].str = ""
        display[dls + x].format = format
        inc x
    while x < ex:
      display[dls + x].str = " "
      display[dls + x].format = format
      inc x

proc windowChange*(select: Select; width, height: int) =
  select.maxh = height - 2
  if select.y + select.options.len >= select.maxh:
    select.y = max(select.maxh - select.options.len, 0)
  if select.x + select.maxw + 2 > width:
    #TODO I don't know why but - 2 does not work.
    select.x = max(width - select.maxw - 3, 0)
  select.setCursorY(select.cursory)
  select.queueDraw()

proc newSelect*(multiple: bool; options: seq[SelectOption]; selected: seq[int];
    x, y, width, height: int; finishImpl: SelectFinish; opaque: RootRef):
    Select =
  let select = Select(
    multiple: multiple,
    options: options,
    oselected: selected,
    selected: selected,
    x: x,
    y: y,
    finishImpl: finishImpl,
    opaque: opaque
  )
  for opt in select.options.mitems:
    opt.s.mnormalize()
    select.maxw = max(select.maxw, opt.s.width())
  select.windowChange(width, height)
  if selected.len > 0:
    select.setCursorY(selected[0])
  return select

proc addSelectModule*(ctx: JSContext) =
  ctx.registerType(Select)
