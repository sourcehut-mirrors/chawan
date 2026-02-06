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
import server/request
import types/bitmap
import types/blob
import types/cell
import types/color
import types/opt
import types/refstring
import types/url
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

  BufferInterface* = ref object
    map*: seq[BufferIfaceItem]
    packetid*: int
    len*: int
    nfds*: int
    stream*: BufStream
    lines*: SimpleFlexibleGrid
    lineShift*: int
    numLines*: int

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

jsDestructor(BufferInterface)

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

proc onReshape*(iface: BufferInterface): EmptyPromise =
  iface.withPacketWriterFire bcOnReshape, w:
    discard
  return iface.addEmptyPromise()

proc gotoAnchor*(iface: BufferInterface; anchor: string;
    autofocus, target: bool): Promise[GotoAnchorResult] {.jsfunc.} =
  iface.withPacketWriterFire bcGotoAnchor, w:
    w.swrite(anchor)
    w.swrite(autofocus)
    w.swrite(target)
  return addPromise[GotoAnchorResult](iface)

proc click*(iface: BufferInterface; x, y, n: int): Promise[ClickResult] {.
    jsfunc.} =
  iface.withPacketWriterFire bcClick, w:
    w.swrite(x)
    w.swrite(y)
    w.swrite(n)
  return addPromise[ClickResult](iface)

proc submitForm*(iface: BufferInterface; x, y: int): Promise[ClickResult] {.
    jsfunc.} =
  iface.withPacketWriterFire bcSubmitForm, w:
    w.swrite(x)
    w.swrite(y)
  return addPromise[ClickResult](iface)

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

proc findNextLink(iface: BufferInterface; x, y, n: int): Promise[PagePos]
    {.jsfunc.} =
  iface.withPacketWriterFire bcFindNextLink, w:
    w.swrite(x)
    w.swrite(y)
    w.swrite(n)
  return addPromise[PagePos](iface)

#TODO findPrevLink & findRevNthLink should probably be merged into findNextLink
proc findPrevLink(iface: BufferInterface; x, y, n: int): Promise[PagePos]
    {.jsfunc.} =
  iface.withPacketWriterFire bcFindPrevLink, w:
    w.swrite(x)
    w.swrite(y)
    w.swrite(n)
  return addPromise[PagePos](iface)

proc findRevNthLink(iface: BufferInterface; x, y, n: int): Promise[PagePos]
    {.jsfunc.} =
  iface.withPacketWriterFire bcFindPrevLink, w:
    w.swrite(x)
    w.swrite(y)
    w.swrite(n)
  return addPromise[PagePos](iface)

proc findNextParagraph(iface: BufferInterface; y, n: int): Promise[int]
    {.jsfunc.} =
  iface.withPacketWriterFire bcFindNextParagraph, w:
    w.swrite(y)
    w.swrite(n)
  return addPromise[int](iface)

proc markURL(iface: BufferInterface): EmptyPromise {.jsfunc.} =
  iface.withPacketWriterFire bcMarkURL, w:
    discard
  return addEmptyPromise(iface)

proc forceReshape(iface: BufferInterface): EmptyPromise {.jsfunc.} =
  iface.withPacketWriterFire bcForceReshape, w:
    discard
  return addEmptyPromise(iface)

proc getLines*(iface: BufferInterface; slice: Slice[int]):
    Promise[GetLinesResult] =
  iface.withPacketWriterFire bcGetLines, w:
    w.swrite(slice)
  return addPromise[GetLinesResult](iface)

proc showHints(iface: BufferInterface; sx, sy, ex, ey: int):
    Promise[HintResult] {.jsfunc.} =
  iface.withPacketWriterFire bcShowHints, w:
    w.swrite(sx)
    w.swrite(sy)
    w.swrite(ex)
    w.swrite(ey)
  return addPromise[HintResult](iface)

proc hideHints(iface: BufferInterface): EmptyPromise {.jsfunc.} =
  iface.withPacketWriterFire bcHideHints, w:
    discard
  return addEmptyPromise(iface)

proc checkRefresh(iface: BufferInterface): Promise[CheckRefreshResult]
    {.jsfunc.} =
  iface.withPacketWriterFire bcCheckRefresh, w:
    discard
  return addPromise[CheckRefreshResult](iface)

proc contextMenu(iface: BufferInterface; cursorx, cursory: int):
    Promise[bool] {.jsfunc.} =
  iface.withPacketWriterFire bcContextMenu, w:
    w.swrite(cursorx)
    w.swrite(cursory)
  return addPromise[bool](iface)

proc getSelectionText(iface: BufferInterface; sx, sy, ex, ey: int;
    t: SelectionType): Promise[string] {.jsfunc.} =
  iface.withPacketWriterFire bcGetSelectionText, w:
    w.swrite(sx)
    w.swrite(sy)
    w.swrite(ex)
    w.swrite(ey)
    w.swrite(t)
  return addPromise[string](iface)

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

proc matchFirst(ctx: JSContext; iface: BufferInterface; re: JSValueConst;
    y: int): JSValue {.jsfunc.} =
  if not iface.lineLoaded(y):
    return ctx.toJS((-1, -1))
  var plen: csize_t
  let p = JS_GetRegExpBytecode(ctx, re, plen)
  if p == nil:
    return JS_EXCEPTION
  return ctx.toJS(cast[REBytecode](p).matchFirst(iface.getLineStr(y)))

proc addBufferInterfaceModule*(ctx: JSContext): JSClassID =
  return ctx.registerType(BufferInterface)

{.pop.}
