{.push raises: [].}

import types/color
import config/history
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsutils
import monoucha/quickjs
import monoucha/tojs
import types/cell
import types/winattrs
import utils/luwrap
import utils/strwidth
import utils/twtstr

type
  LineSelectType = enum
    lstChar = "char"
    lstWord = "word"
    lstLine = "line"

  LineEdit* = ref object
    text {.jsget.}: string # public
    prompt: string
    promptw: int
    cursorx: int # 0 ..< text.width
    cursori: int # 0 ..< text.len
    shiftx: int # 0 ..< text.width
    shifti: int # 0 ..< text.len
    padding: int # 0 or 1
    maxwidth: int
    selecti: int # start of selection
    hist: History
    currHist: HistoryEntry
    histtmp: string
    luctx: LUContext
    selectType: LineSelectType
    redraw*: bool
    skipLast: bool
    escNext {.jsgetset.}: bool # private
    hide {.jsget.}: bool # private
    update: JSValue
    resolve: JSValue

jsDestructor(LineEdit)

proc finalize(rt: JSRuntime; this: LineEdit) {.jsfin.} =
  JS_FreeValueRT(rt, this.update)
  JS_FreeValueRT(rt, this.resolve)

proc mark(rt: JSRuntime; this: LineEdit; markFun: JS_MarkFunc)
    {.jsmark.} =
  JS_MarkValue(rt, this.update, markFun)
  JS_MarkValue(rt, this.resolve, markFun)

proc isDigitAscii(u: uint32): bool =
  return u < 128 and char(u) in AsciiDigit

proc breaksWord(ctx: LUContext; u: uint32): bool =
  return not u.isDigitAscii() and u.width() != 0 and not ctx.isAlpha(u)

proc width(edit: LineEdit; u: uint32): int =
  if edit.hide:
    return 1
  return u.width()

proc width(edit: LineEdit; s: string): int =
  var n = 0
  for u in s.points:
    n += edit.width(u)
  n

# Note: capped at edit.maxwidth.
proc getDisplayWidth(edit: LineEdit): int =
  var dispw = 0
  var i = edit.shifti
  while i < edit.text.len and dispw < edit.maxwidth:
    let u = edit.text.nextUTF8(i)
    dispw += edit.width(u)
  return dispw

proc shiftView(edit: LineEdit) =
  # Shift view so it contains the cursor.
  if edit.cursorx < edit.shiftx:
    edit.shiftx = edit.cursorx
    edit.shifti = edit.cursori
  # Shift view so it is completely filled.
  if edit.shiftx > 0:
    let dispw = edit.getDisplayWidth()
    if dispw < edit.maxwidth:
      let targetx = edit.shiftx - edit.maxwidth + dispw
      if targetx <= 0:
        edit.shiftx = 0
        edit.shifti = 0
      else:
        while edit.shiftx > targetx:
          let u = edit.text.prevUTF8(edit.shifti)
          edit.shiftx -= edit.width(u)
  edit.padding = 0
  # Shift view so it contains the cursor. (act 2)
  if edit.shiftx < edit.cursorx - edit.maxwidth:
    while edit.shiftx < edit.cursorx - edit.maxwidth and
        edit.shifti < edit.text.len:
      let u = edit.text.nextUTF8(edit.shifti)
      edit.shiftx += edit.width(u)
    if edit.shiftx > edit.cursorx - edit.maxwidth:
      # skipped over a cell because of a double-width char
      edit.padding = 1

proc selectStart(edit: LineEdit): int =
  if edit.selecti == -1:
    return -1
  case edit.selectType
  of lstChar: return min(edit.selecti, edit.cursori)
  of lstWord:
    var i = min(edit.selecti, edit.cursori)
    if i < edit.text.len:
      # if we are on a word-breaking char, we stop immediately
      let pi = i
      let u = edit.text.nextUTF8(i)
      if edit.luctx.breaksWord(u):
        return pi
      i = pi
    while i > 0:
      let pi = i
      let u = edit.text.prevUTF8(i)
      if edit.luctx.breaksWord(u):
        return pi
    return i
  of lstLine: return 0

proc selectEnd(edit: LineEdit): int =
  if edit.selecti == -1:
    return -1
  case edit.selectType
  of lstChar:
    var i = max(edit.selecti, edit.cursori)
    if i < edit.text.len:
      discard edit.text.nextUTF8(i)
    return i
  of lstWord:
    var i = max(edit.selecti, edit.cursori)
    if i < edit.text.len:
      # ensure the selection is at least one char wide
      let u = edit.text.nextUTF8(i)
      if edit.luctx.breaksWord(u):
        return i
    while i < edit.text.len:
      let pi = i
      let u = edit.text.nextUTF8(i)
      if edit.luctx.breaksWord(u):
        return pi
    return i
  of lstLine: return edit.text.len

proc generateOutput*(edit: LineEdit; hlcolor: CellColor): FixedGrid =
  edit.shiftView()
  # Make the output grid +1 cell wide, so it covers the whole input area.
  result = newFixedGrid(edit.promptw + edit.maxwidth + 1, 1)
  var x = 0
  for u in edit.prompt.points:
    result[x].str.addUTF8(u)
    x += u.width()
    if x >= result.width: break
  for i in 0 ..< edit.padding:
    if x < result.width:
      result[x].str = " "
      inc x
  var i = edit.shifti
  let selectStart = edit.selectStart
  let selectEnd = edit.selectEnd
  var format = Format()
  while i < edit.text.len:
    if selectStart != -1:
      if i in selectStart ..< selectEnd:
        format.bgcolor = hlcolor
      else:
        format.bgcolor = defaultColor
    let pi = i
    let u = edit.text.nextUTF8(i)
    let w = edit.width(u)
    if x + w > result.width:
      break
    if not edit.hide:
      if u.isControlChar():
        result[x].str = u.controlToVisual()
      else:
        for j in pi ..< i:
          result[x].str &= edit.text[j]
    else:
      result[x].str &= '*'
    result[x].format = format
    x += w

proc getCursorX*(edit: LineEdit): int {.jsfunc.} =
  return edit.promptw + edit.cursorx + edit.padding - edit.shiftx

# private
proc hasSelection(edit: LineEdit): bool {.jsfunc.} =
  return edit.selecti >= 0

# private
proc clearSelection(edit: LineEdit) {.jsfunc.} =
  if edit.selecti != -1:
    edit.selecti = -1
    edit.redraw = true

# private
proc startSelection(edit: LineEdit; t: LineSelectType) {.jsfunc.} =
  edit.selecti = edit.cursori
  edit.selectType = t
  edit.redraw = true

# private
proc selectedText(edit: LineEdit): string {.jsfget.} =
  if edit.selecti < 0:
    return ""
  return edit.text.substr(edit.selectStart, edit.selectEnd - 1)

proc update(ctx: JSContext; edit: LineEdit): JSValue =
  if JS_IsUndefined(edit.update):
    return JS_UNDEFINED
  return ctx.call(edit.update, JS_UNDEFINED)

proc resolve(ctx: JSContext; edit: LineEdit; val: JSValue): JSValue =
  if not JS_IsFunction(ctx, edit.resolve):
    JS_FreeValue(ctx, val)
    return JS_ThrowTypeError(ctx, "nothing to resolve")
  let resolve = edit.resolve
  edit.resolve = JS_UNDEFINED
  return ctx.callSinkFree(resolve, JS_UNDEFINED, val)

proc cancel(ctx: JSContext; edit: LineEdit): JSValue {.jsfunc.} =
  return ctx.resolve(edit, JS_NULL)

proc submit(ctx: JSContext; edit: LineEdit): JSValue {.jsfunc.} =
  let text = ctx.toJS(edit.text)
  if edit.hist.mtime == 0 and edit.text.len > 0:
    edit.hist.add(edit.text)
  if JS_IsException(text):
    return text
  return ctx.resolve(edit, text)

proc deleteTextTo(edit: LineEdit; ei: int) =
  edit.text.delete(edit.cursori ..< ei)
  if edit.cursori < edit.selecti:
    edit.selecti -= ei - edit.cursori
    if edit.selecti <= edit.cursori:
      edit.clearSelection()
  edit.redraw = true

proc backspace(ctx: JSContext; edit: LineEdit): JSValue {.jsfunc.} =
  if edit.cursori > 0:
    let pi = edit.cursori
    let u = edit.text.prevUTF8(edit.cursori)
    edit.cursorx -= edit.width(u)
    edit.deleteTextTo(pi)
    return ctx.update(edit)
  return JS_UNDEFINED

proc write*(ctx: JSContext; edit: LineEdit; s: string): JSValue {.jsfunc.} =
  edit.escNext = false
  if s.len > 0:
    edit.text.insert(s, edit.cursori)
    edit.cursori += s.len
    edit.cursorx += edit.width(s)
    if edit.selecti >= edit.cursori:
      edit.selecti += s.len
    edit.redraw = true
    return ctx.update(edit)
  return JS_UNDEFINED

proc delete(ctx: JSContext; edit: LineEdit): JSValue {.jsfunc.} =
  if edit.cursori < edit.text.len:
    let len = edit.text.pointLenAt(edit.cursori)
    edit.deleteTextTo(edit.cursori + len)
    return ctx.update(edit)
  return JS_UNDEFINED

proc escape(edit: LineEdit) {.jsfunc.} =
  edit.escNext = true

proc clear(ctx: JSContext; edit: LineEdit): JSValue {.jsfunc.} =
  let pi = edit.cursori
  if pi > 0:
    edit.cursori = 0
    edit.cursorx = 0
    edit.deleteTextTo(pi)
    return ctx.update(edit)
  return JS_UNDEFINED

proc kill(ctx: JSContext; edit: LineEdit): JSValue {.jsfunc.} =
  if edit.cursori < edit.text.len:
    edit.text.setLen(edit.cursori)
    edit.redraw = true
    edit.selecti = min(edit.selecti, edit.cursori)
    if edit.selecti == edit.cursori:
      edit.clearSelection()
    return ctx.update(edit)
  return JS_UNDEFINED

proc backward(edit: LineEdit) {.jsfunc.} =
  if edit.cursori > 0:
    let u = edit.text.prevUTF8(edit.cursori)
    edit.cursorx -= edit.width(u)
    if edit.cursorx < edit.shiftx or edit.selecti != -1:
      edit.redraw = true

proc forward(edit: LineEdit) {.jsfunc.} =
  if edit.cursori < edit.text.len:
    let u = edit.text.nextUTF8(edit.cursori)
    edit.cursorx += edit.width(u)
    if edit.cursorx >= edit.shiftx + edit.maxwidth or edit.selecti != -1:
      edit.redraw = true

# private
proc setAbsoluteCursorX(edit: LineEdit; x: int) {.jsfunc.} =
  let x = max(x - edit.shiftx - edit.promptw, 0)
  while edit.cursorx < x:
    let x = edit.cursorx
    edit.forward()
    if edit.cursorx == x:
      break
  while edit.cursorx > x:
    let x = edit.cursorx
    edit.backward()
    if edit.cursorx == x:
      break

proc prevWord(edit: LineEdit) {.jsfunc.} =
  if edit.cursori == 0:
    return
  let pi = edit.cursori
  let u = edit.text.prevUTF8(edit.cursori)
  if edit.luctx.breaksWord(u):
    edit.cursorx -= edit.width(u)
  else:
    edit.cursori = pi
  while edit.cursori > 0:
    let pi = edit.cursori
    let u = edit.text.prevUTF8(edit.cursori)
    if edit.luctx.breaksWord(u):
      edit.cursori = pi
      break
    edit.cursorx -= edit.width(u)
  if edit.cursorx < edit.shiftx:
    edit.redraw = true

proc nextWord(edit: LineEdit) {.jsfunc.} =
  while edit.cursori < edit.text.len:
    let u = edit.text.nextUTF8(edit.cursori)
    edit.cursorx += edit.width(u)
    if edit.luctx.breaksWord(u):
      if edit.cursorx >= edit.shiftx + edit.maxwidth:
        edit.redraw = true
      break

proc clearWord(ctx: JSContext; edit: LineEdit): JSValue {.jsfunc.} =
  let pi = edit.cursori
  edit.prevWord()
  if edit.cursori != pi:
    edit.deleteTextTo(pi)
    return ctx.update(edit)
  return JS_UNDEFINED

proc killWord(ctx: JSContext; edit: LineEdit): JSValue {.jsfunc.} =
  if edit.cursori >= edit.text.len:
    return JS_UNDEFINED
  var i = edit.cursori
  var u = edit.text.nextUTF8(i)
  if not edit.luctx.breaksWord(u):
    while i < edit.text.len:
      let pi = i
      let u = edit.text.nextUTF8(i)
      if edit.luctx.breaksWord(u):
        i = pi
        break
  edit.deleteTextTo(i)
  return ctx.update(edit)

proc begin(edit: LineEdit) {.jsfunc.} =
  edit.cursori = 0
  edit.cursorx = 0
  if edit.shiftx > 0 or edit.selecti != -1:
    edit.redraw = true

proc `end`(edit: LineEdit) {.jsfunc.} =
  if edit.cursori < edit.text.len:
    edit.cursori = edit.text.len
    edit.cursorx = edit.width(edit.text)
    if edit.cursorx >= edit.shiftx + edit.maxwidth or edit.selecti != -1:
      edit.redraw = true

proc prevHist(ctx: JSContext; edit: LineEdit): JSValue {.jsfunc.} =
  if edit.currHist == nil:
    var last = edit.hist.last
    if last != nil and edit.skipLast:
      last = last.prev
    if last != nil and edit.text.len > 0:
      edit.histtmp = edit.text
    edit.currHist = last
  elif edit.currHist.prev != nil:
    edit.currHist = edit.currHist.prev
  if edit.currHist != nil:
    edit.text = edit.currHist.s
    edit.clearSelection()
    # The begin call is needed so the cursor doesn't get lost outside
    # the string.
    edit.begin()
    edit.end()
    edit.redraw = true
    return ctx.update(edit)
  return JS_UNDEFINED

proc nextHist(ctx: JSContext; edit: LineEdit): JSValue {.jsfunc.} =
  if edit.currHist != nil:
    edit.currHist = edit.currHist.next
    if edit.currHist != nil:
      edit.text = edit.currHist.s
      if edit.currHist == edit.hist.last and edit.skipLast:
        edit.currHist = nil
    else:
      edit.text = move(edit.histtmp)
    edit.clearSelection()
    edit.begin()
    edit.end()
    edit.redraw = true
    return ctx.update(edit)
  return JS_UNDEFINED

proc windowChange*(edit: LineEdit; attrs: WindowAttributes) =
  edit.maxwidth = attrs.width - edit.promptw - 1
  edit.redraw = true

proc readLine*(prompt, current: string; termwidth: int; hide: bool;
    hist: History; luctx: LUContext; update, resolve: JSValue): LineEdit =
  let promptw = prompt.width()
  let edit = LineEdit(
    prompt: prompt,
    promptw: promptw,
    text: current,
    hide: hide,
    redraw: true,
    cursori: current.len,
    # - 1, so that the cursor always has place
    maxwidth: termwidth - promptw - 1,
    selecti: -1,
    hist: hist,
    currHist: nil,
    luctx: luctx,
    # Skip the last history entry if it's identical to the input.
    skipLast: hist.last != nil and hist.last.s == current,
    update: update,
    resolve: resolve
  )
  edit.cursorx = edit.width(current)
  return edit

proc addLineEditModule*(ctx: JSContext): JSClassID =
  return ctx.registerType(LineEdit)

{.pop.} # raises: []
