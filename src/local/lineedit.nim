{.push raises: [].}

import std/strutils

import chagashi/decoder
import config/history
import monoucha/fromjs
import monoucha/javascript
import monoucha/quickjs
import monoucha/tojs
import types/cell
import types/opt
import types/winattrs
import utils/luwrap
import utils/strwidth
import utils/twtstr
import utils/wordbreak

type
  LineEditState* = enum
    lesEdit, lesFinish, lesCancel

  LineEdit* = ref object
    news*: string
    prompt: string
    promptw: int
    state*: LineEditState
    cursorx: int # 0 ..< news.width
    cursori: int # 0 ..< news.len
    shiftx: int # 0 ..< news.width
    shifti: int # 0 ..< news.len
    padding: int # 0 or 1
    maxwidth: int
    hist: History
    currHist: HistoryEntry
    histtmp: string
    luctx: LUContext
    redraw*: bool
    skipLast: bool
    escNext*: bool
    hide: bool

jsDestructor(LineEdit)

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
  while i < edit.news.len and dispw < edit.maxwidth:
    let u = edit.news.nextUTF8(i)
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
          let u = edit.news.prevUTF8(edit.shifti)
          edit.shiftx -= edit.width(u)
  edit.padding = 0
  # Shift view so it contains the cursor. (act 2)
  if edit.shiftx < edit.cursorx - edit.maxwidth:
    while edit.shiftx < edit.cursorx - edit.maxwidth and
        edit.shifti < edit.news.len:
      let u = edit.news.nextUTF8(edit.shifti)
      edit.shiftx += edit.width(u)
    if edit.shiftx > edit.cursorx - edit.maxwidth:
      # skipped over a cell because of a double-width char
      edit.padding = 1

proc generateOutput*(edit: LineEdit): FixedGrid =
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
  while i < edit.news.len:
    let pi = i
    let u = edit.news.nextUTF8(i)
    let w = edit.width(u)
    if x + w > result.width:
      break
    if not edit.hide:
      if u.isControlChar():
        result[x].str = u.controlToVisual()
      else:
        for j in pi ..< i:
          result[x].str &= edit.news[j]
    else:
      result[x].str &= '*'
    x += w

proc getCursorX*(edit: LineEdit): int =
  return edit.promptw + edit.cursorx + edit.padding - edit.shiftx

proc insertCharseq(edit: LineEdit; s: string) =
  edit.escNext = false
  if s.len == 0:
    return
  edit.news.insert(s, edit.cursori)
  edit.cursori += s.len
  edit.cursorx += edit.width(s)
  edit.redraw = true

proc cancel(edit: LineEdit) {.jsfunc.} =
  edit.state = lesCancel

proc submit(edit: LineEdit) {.jsfunc.} =
  if edit.hist.mtime == 0 and edit.news.len > 0:
    edit.hist.add(edit.news)
  edit.state = lesFinish

proc backspace(edit: LineEdit) {.jsfunc.} =
  if edit.cursori > 0:
    let pi = edit.cursori
    let u = edit.news.prevUTF8(edit.cursori)
    edit.news.delete(edit.cursori ..< pi)
    edit.cursorx -= edit.width(u)
    edit.redraw = true
 
proc write*(edit: LineEdit; s: string) =
  edit.insertCharseq(s)

proc write(ctx: JSContext; edit: LineEdit; s: string): JSValue {.jsfunc.} =
  if s.validateUTF8Surr() != -1:
    # Note: pretty sure this is dead code, as QJS converts surrogates to
    # replacement chars.
    return JS_ThrowTypeError(ctx, "string contains surrogate codepoints")
  edit.insertCharseq(s)
  return JS_UNDEFINED

proc delete(edit: LineEdit) {.jsfunc.} =
  if edit.cursori < edit.news.len:
    let len = edit.news.pointLenAt(edit.cursori)
    edit.news.delete(edit.cursori ..< edit.cursori + len)
    edit.redraw = true

proc escape(edit: LineEdit) {.jsfunc.} =
  edit.escNext = true

proc clear(edit: LineEdit) {.jsfunc.} =
  if edit.cursori > 0:
    edit.news.delete(0..edit.cursori - 1)
    edit.cursori = 0
    edit.cursorx = 0
    edit.redraw = true

proc kill(edit: LineEdit) {.jsfunc.} =
  if edit.cursori < edit.news.len:
    edit.news.setLen(edit.cursori)
    edit.redraw = true

proc backward(edit: LineEdit) {.jsfunc.} =
  if edit.cursori > 0:
    let u = edit.news.prevUTF8(edit.cursori)
    edit.cursorx -= edit.width(u)
    if edit.cursorx < edit.shiftx:
      edit.redraw = true

proc forward(edit: LineEdit) {.jsfunc.} =
  if edit.cursori < edit.news.len:
    let u = edit.news.nextUTF8(edit.cursori)
    edit.cursorx += edit.width(u)
    if edit.cursorx >= edit.shiftx + edit.maxwidth:
      edit.redraw = true

proc prevWord(edit: LineEdit) {.jsfunc.} =
  if edit.cursori == 0:
    return
  let pi = edit.cursori
  let u = edit.news.prevUTF8(edit.cursori)
  if edit.luctx.breaksWord(u):
    edit.cursorx -= edit.width(u)
  else:
    edit.cursori = pi
  while edit.cursori > 0:
    let pi = edit.cursori
    let u = edit.news.prevUTF8(edit.cursori)
    if edit.luctx.breaksWord(u):
      edit.cursori = pi
      break
    edit.cursorx -= edit.width(u)
  if edit.cursorx < edit.shiftx:
    edit.redraw = true

proc nextWord(edit: LineEdit) {.jsfunc.} =
  while edit.cursori < edit.news.len:
    let u = edit.news.nextUTF8(edit.cursori)
    edit.cursorx += edit.width(u)
    if edit.luctx.breaksWord(u):
      if edit.cursorx >= edit.shiftx + edit.maxwidth:
        edit.redraw = true
      break

proc clearWord(edit: LineEdit) {.jsfunc.} =
  let oc = edit.cursori
  edit.prevWord()
  if oc != edit.cursori:
    edit.news.delete(edit.cursori .. oc - 1)
    edit.redraw = true

proc killWord(edit: LineEdit) {.jsfunc.} =
  if edit.cursori >= edit.news.len:
    return
  var i = edit.cursori
  var u = edit.news.nextUTF8(i)
  if not edit.luctx.breaksWord(u):
    while i < edit.news.len:
      let pi = i
      let u = edit.news.nextUTF8(i)
      if edit.luctx.breaksWord(u):
        i = pi
        break
  edit.news.delete(edit.cursori ..< i)
  edit.redraw = true

proc begin(edit: LineEdit) {.jsfunc.} =
  edit.cursori = 0
  edit.cursorx = 0
  if edit.shiftx > 0:
    edit.redraw = true

proc `end`(edit: LineEdit) {.jsfunc.} =
  if edit.cursori < edit.news.len:
    edit.cursori = edit.news.len
    edit.cursorx = edit.width(edit.news)
    if edit.cursorx >= edit.shiftx + edit.maxwidth:
      edit.redraw = true

proc prevHist(edit: LineEdit) {.jsfunc.} =
  if edit.currHist == nil:
    var last = edit.hist.last
    if last != nil and edit.skipLast:
      last = last.prev
    if last != nil and edit.news.len > 0:
      edit.histtmp = edit.news
    edit.currHist = last
  elif edit.currHist.prev != nil:
    edit.currHist = edit.currHist.prev
  if edit.currHist != nil:
    edit.news = edit.currHist.s
    # The begin call is needed so the cursor doesn't get lost outside
    # the string.
    edit.begin()
    edit.end()
    edit.redraw = true

proc nextHist(edit: LineEdit) {.jsfunc.} =
  if edit.currHist != nil:
    edit.currHist = edit.currHist.next
    if edit.currHist != nil:
      edit.news = edit.currHist.s
      if edit.currHist == edit.hist.last and edit.skipLast:
        edit.currHist = nil
    else:
      edit.news = move(edit.histtmp)
      edit.histtmp = ""
    edit.begin()
    edit.end()
    edit.redraw = true

proc windowChange*(edit: LineEdit; attrs: WindowAttributes) =
  edit.maxwidth = attrs.width - edit.promptw - 1

proc readLine*(prompt, current: string; termwidth: int; hide: bool;
    hist: History; luctx: LUContext): LineEdit =
  let promptw = prompt.width()
  let edit = LineEdit(
    prompt: prompt,
    promptw: promptw,
    news: current,
    hide: hide,
    redraw: true,
    cursori: current.len,
    # - 1, so that the cursor always has place
    maxwidth: termwidth - promptw - 1,
    hist: hist,
    currHist: nil,
    luctx: luctx,
    # Skip the last history entry if it's identical to the input.
    skipLast: hist.last != nil and hist.last.s == current
  )
  edit.cursorx = edit.width(current)
  return edit

proc addLineEditModule*(ctx: JSContext) =
  ctx.registerType(LineEdit)

{.pop.} # raises: []
