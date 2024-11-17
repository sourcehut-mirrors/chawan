import monoucha/javascript
import monoucha/jsregex
import types/cell
import utils/luwrap
import utils/strwidth
import utils/twtstr

type
  SelectFinish* = proc(opaque: RootRef; select: Select; res: SubmitResult)
    {.nimcall.}

  Select* = ref object
    options: seq[string]
    multiple: bool
    oselected*: seq[int] # old selection
    selected*: seq[int] # new selection
    cursor: int # cursor distance from y
    maxw: int # widest option
    maxh: int # maximum height on screen (yes the naming is dumb)
    si: int # first index to display
    # location on screen
    #TODO make this absolute
    x: int
    y: int
    redraw*: bool
    bpos: seq[int]
    opaque: RootRef
    finishImpl: SelectFinish

  SubmitResult* = enum
    srCancel, srSubmit

jsDestructor(Select)

proc queueDraw(select: Select) =
  select.redraw = true

# index of option currently under cursor
func hover(select: Select): int =
  return select.cursor + select.si

func dispheight(select: Select): int =
  return select.maxh - select.y

proc `hover=`(select: Select; i: int) =
  let i = clamp(i, 0, select.options.high)
  if i >= select.si + select.dispheight:
    select.si = i - select.dispheight + 1
    select.cursor = select.dispheight - 1
  elif i < select.si:
    select.si = i
    select.cursor = 0
  else:
    select.cursor = i - select.si

proc cursorDown(select: Select) {.jsfunc.} =
  if select.hover < select.options.high and
      select.cursor + select.y < select.maxh - 1:
    inc select.cursor
    select.queueDraw()
  elif select.si < select.options.len - select.maxh:
    inc select.si
    select.queueDraw()

proc cursorUp(select: Select) {.jsfunc.} =
  if select.cursor > 0:
    dec select.cursor
    select.queueDraw()
  elif select.si > 0:
    dec select.si
    select.queueDraw()
  elif select.multiple and select.cursor > -1:
    select.cursor = -1

proc cursorPrevLink(select: Select) {.jsfunc.} =
  select.cursorUp()

proc cursorNextLink(select: Select) {.jsfunc.} =
  select.cursorDown()

proc cancel(select: Select) {.jsfunc.} =
  select.finishImpl(select.opaque, select, srCancel)

proc submit(select: Select) {.jsfunc.} =
  select.finishImpl(select.opaque, select, srSubmit)

proc click(select: Select) {.jsfunc.} =
  if not select.multiple:
    select.selected = @[select.hover]
    select.submit()
  elif select.cursor == -1:
    select.submit()
  else:
    var k = select.selected.len
    let i = select.hover
    for j in 0 ..< select.selected.len:
      if select.selected[j] >= i:
        k = j
        break
    if k < select.selected.len and select.selected[k] == i:
      select.selected.delete(k)
    else:
      select.selected.insert(i, k)
    select.queueDraw()

proc cursorLeft(select: Select) {.jsfunc.} =
  select.submit()

proc cursorRight(select: Select) {.jsfunc.} =
  select.click()

proc getCursorX*(select: Select): int =
  if select.cursor == -1:
    return select.x
  return select.x + 1

proc getCursorY*(select: Select): int =
  return select.y + 1 + select.cursor

proc cursorFirstLine(select: Select) {.jsfunc.} =
  if select.cursor != 0 or select.si != 0:
    select.cursor = 0
    select.si = 0
    select.queueDraw()

proc cursorLastLine(select: Select) {.jsfunc.} =
  if select.hover < select.options.len:
    select.cursor = select.dispheight - 1
    select.si = max(select.options.len - select.maxh, 0)
    select.queueDraw()

proc cursorNextMatch*(select: Select; regex: Regex; wrap: bool) =
  var j = -1
  for i in select.hover + 1 ..< select.options.len:
    if regex.exec(select.options[i]).success:
      j = i
      break
  if j != -1:
    select.hover = j
    select.queueDraw()
  elif wrap:
    for i in 0 ..< select.hover:
      if regex.exec(select.options[i]).success:
        j = i
        break
    if j != -1:
      select.hover = j
      select.queueDraw()

proc cursorPrevMatch*(select: Select; regex: Regex; wrap: bool) =
  var j = -1
  for i in countdown(select.hover - 1, 0):
    if regex.exec(select.options[i]).success:
      j = i
      break
  if j != -1:
    select.hover = j
    select.queueDraw()
  elif wrap:
    for i in countdown(select.options.high, select.hover):
      if regex.exec(select.options[i]).success:
        j = i
        break
    if j != -1:
      select.hover = j
      select.queueDraw()

proc pushCursorPos*(select: Select) =
  select.bpos.add(select.hover)

proc popCursorPos*(select: Select; nojump = false) =
  select.hover = select.bpos.pop()
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
    while x < sx:
      if display[y * display.width + x].str == "":
        display[y * display.width + x].str = " "
        inc x
      else:
        #x = display[y * display.width + x].str.width()
        inc x
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
  let si = select.si
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
  let upmore = select.si > 0
  let downmore = select.si + mh < select.options.len
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
    if k < select.selected.len and select.selected[k] == i:
      format.flags.incl(ffReverse)
      inc k
    else:
      format.flags.excl(ffReverse)
    while j < select.options[i].len:
      let pj = j
      let u = select.options[i].nextUTF8(j)
      let nx = x + u.width()
      if nx > ex:
        break
      display[dls + x].str = select.options[i].substr(pj, j - 1)
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

proc windowChange*(select: Select; height: int) =
  select.maxh = height - 2
  if select.y + select.options.len >= select.maxh:
    select.y = height - select.options.len
    if select.y < 0:
      select.si = -select.y
      select.y = 0
  if select.selected.len > 0:
    let i = select.selected[0]
    if select.si > i:
      select.si = i
    elif select.si + select.maxh < i:
      select.si = max(i - select.maxh, 0)
  select.queueDraw()

proc newSelect*(multiple: bool; options: seq[string]; selected: seq[int];
    x, y, height: int; finishImpl: SelectFinish; opaque: RootRef): Select =
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
  select.windowChange(height)
  for opt in select.options.mitems:
    opt.mnormalize()
    select.maxw = max(select.maxw, opt.width())
  select.windowChange(height)
  select.queueDraw()
  return select

proc addSelectModule*(ctx: JSContext) =
  ctx.registerType(Select)
