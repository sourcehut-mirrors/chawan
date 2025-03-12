import monoucha/fromjs
import monoucha/javascript
import types/opt
import utils/twtstr

type Console* = ref object
  err: File
  clearFun: proc()
  showFun: proc()
  hideFun: proc()

jsDestructor(Console)

proc newConsole*(err: File; clearFun: proc() = nil; showFun: proc() = nil;
    hideFun: proc() = nil): Console =
  return Console(
    err: err,
    clearFun: clearFun,
    showFun: showFun,
    hideFun: hideFun
  )

proc setStream*(console: Console; file: File) =
  console.err.close()
  console.err = file

proc write*(console: Console; c: char) =
  discard console.err.writeBuffer(unsafeAddr c, 1)

proc write*(console: Console; s: openArray[char]) =
  if s.len > 0:
    discard console.err.writeBuffer(unsafeAddr s[0], s.len)

proc log*(console: Console; ss: varargs[string]) =
  var buf = ""
  for i, s in ss.mypairs:
    buf &= s
    if i != ss.high:
      buf &= ' '
  buf &= '\n'
  console.err.write(buf)

proc error*(console: Console; ss: varargs[string]) =
  console.log(ss)

proc log*(ctx: JSContext; console: Console; ss: varargs[JSValueConst]):
    Opt[void] {.jsfunc.} =
  var buf = ""
  for i, val in ss:
    var res: string
    ?ctx.fromJS(val, res)
    buf &= res
    if i != ss.high:
      buf &= ' '
  buf &= '\n'
  console.err.write(buf)
  ok()

proc clear(console: Console) {.jsfunc.} =
  if console.clearFun != nil:
    console.clearFun()

# For now, these are the same as log().
proc debug(ctx: JSContext; console: Console; ss: varargs[JSValueConst]):
    Opt[void] {.jsfunc.} =
  return log(ctx, console, ss)

proc error(ctx: JSContext; console: Console; ss: varargs[JSValueConst]):
    Opt[void] {.jsfunc.} =
  return log(ctx, console, ss)

proc info(ctx: JSContext; console: Console; ss: varargs[JSValueConst]):
    Opt[void] {.jsfunc.} =
  return log(ctx, console, ss)

proc warn(ctx: JSContext; console: Console; ss: varargs[JSValueConst]):
    Opt[void] {.jsfunc.} =
  return log(ctx, console, ss)

proc show(console: Console) {.jsfunc.} =
  if console.showFun != nil:
    console.showFun()

proc hide(console: Console) {.jsfunc.} =
  if console.hideFun != nil:
    console.hideFun()

proc addConsoleModule*(ctx: JSContext) =
  #TODO console should not have a prototype
  # "For historical reasons, console is lowercased."
  ctx.registerType(Console, nointerface = true, name = "console")

proc flush*(console: Console) =
  console.err.flushFile()

proc writeException*(console: Console; ctx: JSContext) =
  console.err.write(ctx.getExceptionMsg())
  console.flush()
