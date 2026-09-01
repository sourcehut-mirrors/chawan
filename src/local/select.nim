{.push raises: [].}

import js/fromjs
import js/jsbind
import js/jsref
import js/jstypes
import js/jsutils
import js/quickjs
import js/tojs
import types/cell
import types/jsopt
import types/opt
import utils/lrewrap
import utils/luwrap
import utils/strwidth
import utils/twtstr

type
  SelectOption* = object
    nop*: bool
    s*: string

  SelectObj = object
    options: seq[SelectOption]
    selected: int # new selection
    fromy: int # first index to display
    cursory: int # hover index
    maxw: int # widest option
    maxh: int # maximum number of options on screen
    # location on screen
    #TODO make this absolute
    x: int
    y: int
    redraw*: bool
    unselected: bool
    finish: JSObject

  Select* = JSRef[SelectObj]

# Forward declarations
proc setCursorY(select: Select; y: int)

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var SelectOption):
    JSCode =
  if JS_IsNull(val):
    res = SelectOption(nop: true)
  else:
    res = SelectOption()
    ?ctx.fromJS(val, res.s)
  fjOk

proc toJS*(ctx: JSContext; x: SelectOption): JSValue =
  if x.nop:
    return JS_NULL
  return ctx.toJS(x.s)

proc queueDraw(select: Select) =
  select.redraw = true

proc setFromY(select: Select; y: int) =
  select.fromy = max(min(y, select.options.len - select.maxh), 0)

proc getCursorX*(select: Select): int =
  if select.cursory == -1:
    return select.x
  return select.x + 1

proc getCursorY*(select: Select): int =
  return max(select.y + 1 + select.cursory - select.fromy, 0)

proc finish(ctx: JSContext; select: Select): JSValue =
  let selected = ctx.toJS(select.selected)
  if JS_IsException(selected):
    return JS_EXCEPTION
  let finish = moveJSValue(select.finish)
  ctx.callSinkFree(finish, JS_UNDEFINED, selected)

proc cursorNextMatch(select: Select; regex: REBytecode; wrap: bool) =
  var j = -1
  for i in select.cursory + 1 ..< select.options.len:
    if regex.match(select.options[i].s):
      j = i
      break
  if j != -1:
    select.setCursorY(j)
    select.queueDraw()
  elif wrap:
    for i in 0 ..< select.cursory:
      if regex.match(select.options[i].s):
        j = i
        break
    if j != -1:
      select.setCursorY(j)
      select.queueDraw()

proc cursorPrevMatch(select: Select; regex: REBytecode; wrap: bool) =
  var j = -1
  for i in countdown(select.cursory - 1, 0):
    if regex.match(select.options[i].s):
      j = i
      break
  if j != -1:
    select.setCursorY(j)
    select.queueDraw()
  elif wrap:
    for i in countdown(select.options.high, select.cursory):
      if regex.match(select.options[i].s):
        j = i
        break
    if j != -1:
      select.setCursorY(j)
      select.queueDraw()

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
  let tl = if upmore: bdcVerticalBarLeft else: bdcCornerTopLeft
  let tr = if upmore: bdcVerticalBarRight else: bdcCornerTopRight
  let bl = if downmore: bdcVerticalBarLeft else: bdcCornerBottomLeft
  let br = if downmore: bdcVerticalBarRight else: bdcCornerBottomRight
  const fmt = Format()
  display[sy * display.width + sx].str = $tl
  display[sy * display.width + ex].str = $tr
  display[ey * display.width + sx].str = $bl
  display[ey * display.width + ex].str = $br
  display[sy * display.width + sx].format = fmt
  display[sy * display.width + ex].format = fmt
  display[ey * display.width + sx].format = fmt
  display[ey * display.width + ex].format = fmt
  # Draw top, bottom borders.
  let ups = if upmore: " " else: $bdcHorizontalBarTop
  let downs = if downmore: " " else: $bdcHorizontalBarBottom
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
    display[y * display.width + sx].str = $bdcVerticalBarLeft
    display[y * display.width + ex].str = $bdcVerticalBarRight
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
  # move inside border
  inc sy
  inc sx
  var format = Format()
  for y in sy ..< ey:
    let i = y - sy + si
    var j = 0
    var x = sx
    let dls = y * display.width
    if select.getCursorY() == y and not select.unselected:
      format.incl(ffReverse)
    else:
      format.excl(ffReverse)
    while j < select.options[i].s.len:
      let pj = j
      let u = select.options[i].s.nextUTF8(j)
      let uw = u.width()
      let nx = x + uw
      if nx > ex:
        break
      display[dls + x].str = ""
      if u.isControlChar():
        display[dls + x].str &= u.controlToVisual()
      else:
        for l in pj ..< j:
          display[dls + x].str &= select.options[i].s[l]
      display[dls + x].format = format
      if x == sx:
        # do not reverse the position of the cursor
        display[dls + x].format.excl(ffReverse)
      inc x
      while x < nx:
        display[dls + x].str = ""
        display[dls + x].format = format
        inc x
    while x < ex:
      display[dls + x].str = " "
      display[dls + x].format = format
      inc x

jsClassPublicDef(Select):
  jsget Select, fromy # public
  jsget Select, cursory # public
  jsget Select, x # public
  jsget Select, y # public

  # public
  proc numLines(select: Select): int {.jsfget.} =
    return select.options.len

  # public
  proc width(select: Select): int {.jsfget.} =
    return select.maxw + 2

  # public
  proc height(select: Select): int {.jsfget.} =
    return select.maxh + 2

  # public
  proc setCursorY(select: Select; y: int) {.jsfunc.} =
    var y = max(min(y, select.options.high), 0)
    if y < select.options.len and select.options[y].nop:
      if not select.unselected:
        select.unselected = true
        select.queueDraw()
      # move y to the nearest valid slot
      if select.cursory > y:
        while y < select.options.high and select.options[y].nop:
          inc y
      else:
        while y > 0 and select.options[y].nop:
          dec y
    else:
      select.unselected = false
    if select.fromy > y:
      select.setFromY(y)
    if select.fromy + select.maxh <= y:
      select.setFromY(y - select.maxh + 1)
    select.cursory = y
    select.queueDraw()

  # public
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

  # public
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

  # public
  proc scrollDown(select: Select; n = 1) {.jsfunc.} =
    let tfy = select.fromy + n
    select.setFromY(tfy)
    if select.fromy > select.cursory:
      select.cursorDown(select.fromy - select.cursory)
    elif tfy > select.fromy:
      select.cursorDown(tfy - select.fromy)
    select.queueDraw()

  # public
  proc scrollUp(select: Select; n = 1) {.jsfunc.} =
    let tfy = select.fromy - n
    select.setFromY(tfy)
    if select.fromy + select.maxh <= select.cursory:
      select.cursorUp(select.cursory - select.fromy - select.maxh + 1)
    elif tfy < select.fromy:
      select.cursorUp(select.fromy - tfy)
    select.queueDraw()

  # public
  proc halfPageDown(select: Select; n = 1) {.jsfunc.} =
    select.cursorDown(select.maxh div 2)

  # public
  proc halfPageUp(select: Select; n = 1) {.jsfunc.} =
    select.cursorUp(select.maxh div 2)

  # public
  proc pageDown(select: Select; n = 1) {.jsfunc.} =
    select.cursorDown(select.maxh)

  # public
  proc pageUp(select: Select; n = 1) {.jsfunc.} =
    select.cursorUp(select.maxh)

  # public
  proc cancel(ctx: JSContext; select: Select): JSValue {.jsfunc.} =
    select.selected = -1
    return ctx.finish(select)

  # public
  proc click(ctx: JSContext; select: Select): JSValue {.jsfunc.} =
    if select.unselected or
        select.cursory >= 0 and select.cursory < select.options.len and
        select.options[select.cursory].nop:
      return JS_UNDEFINED
    else:
      select.selected = select.cursory
      return ctx.finish(select)

  # public
  proc cursorFirstLine(select: Select) {.jsfunc.} =
    if select.cursory != 0:
      select.cursory = 0
      select.fromy = 0
      select.queueDraw()

  # public
  proc cursorLastLine(select: Select) {.jsfunc.} =
    if select.cursory < select.options.len:
      select.fromy = max(select.options.len - select.maxh, 0)
      select.cursory = select.fromy + select.maxh - 1
      select.queueDraw()

  # public
  proc cursorTop(select: Select) {.jsfunc.} =
    select.setCursorY(select.fromy)

  # public
  proc cursorMiddle(select: Select) {.jsfunc.} =
    select.setCursorY(select.fromy + (select.maxh - 1) div 2)

  # public
  proc cursorBottom(select: Select) {.jsfunc.} =
    select.setCursorY(select.fromy + select.maxh - 1)

  # private
  proc cursorPrevMatch(ctx: JSContext; select: Select; re: JSValueConst;
      wrap: bool; n: int): Opt[void] {.jsfunc.} =
    var plen: cint
    let p = JS_GetRegExpBytecode(ctx, re, plen)
    if p == nil:
      return err()
    for i in 0 ..< n:
      select.cursorPrevMatch(cast[REBytecode](p), wrap)
    ok()

  # private
  proc cursorNextMatch(ctx: JSContext; select: Select; re: JSValueConst;
      wrap: bool; n: int): Opt[void] {.jsfunc.} =
    var plen: cint
    let p = JS_GetRegExpBytecode(ctx, re, plen)
    if p == nil:
      return err()
    for i in 0 ..< n:
      select.cursorNextMatch(cast[REBytecode](p), wrap)
    ok()

  # public
  proc unselect(select: Select) {.jsfunc.} =
    if not select.unselected:
      select.unselected = true
      select.queueDraw()

  # private
  proc windowChange*(select: Select; width, height: int) {.jsfunc.} =
    if select.y + select.options.len >= height - 2:
      select.y = max(height - 2 - select.options.len, 0)
    select.maxh = min(height - 2, select.options.len)
    if select.x + select.maxw + 2 > width:
      #TODO I don't know why but - 2 does not work.
      select.x = max(width - select.maxw - 3, 0)
    select.setCursorY(select.cursory)
    select.queueDraw()

  proc newSelect(ctx: JSContext; options: seq[SelectOption]; selected: int;
      x, y, width, height: int; finish: JSValueConst): Opt[Select] {.jsctor.} =
    let select = jsNew SelectObj(
      selected: selected,
      x: x,
      y: y,
      options: options,
      finish: ctx.dupTraceObj(finish)
    )
    if select != nil:
      var maxw = 0
      for opt in select.options.mitems:
        opt.s.mnormalize()
        opt.s = ' ' & opt.s & ' '
        maxw = max(maxw, opt.s.width())
      select.maxw = maxw
      for opt in select.options.mitems:
        if opt.nop:
          opt.s = ' ' & ($bdcHorizontalBarTop).repeat(maxw - 2) & ' '
      select.windowChange(width, height)
      select.setCursorY(selected)
    ok(select)

proc addSelectModule*(ctx: JSContext): JSCode =
  ctx.registerClass(SelectDef)

{.pop.} # raises: []
