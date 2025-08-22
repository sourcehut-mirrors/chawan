{.push raises: [].}

import io/chafile
import monoucha/fromjs
import monoucha/javascript
import monoucha/quickjs
import monoucha/tojs
import types/opt
import utils/twtstr

type Console* = ref object
  err: ChaFile
  clearFun: proc() {.raises: [].}
  showFun: proc() {.raises: [].}
  hideFun: proc() {.raises: [].}

jsDestructor(Console)

# Forward declarations
proc flush*(console: Console)

proc newConsole*(err: ChaFile; clearFun: proc() = nil; showFun: proc() = nil;
    hideFun: proc() = nil): Console =
  return Console(
    err: err,
    clearFun: clearFun,
    showFun: showFun,
    hideFun: hideFun
  )

proc setStream*(console: Console; file: ChaFile) =
  discard console.err.close()
  console.err = file

proc write*(console: Console; s: openArray[char]) =
  discard console.err.write(s)

proc write*(console: Console; c: char) =
  console.write([c])

proc log*(console: Console; ss: varargs[string]) =
  var buf = ""
  for i, s in ss.mypairs:
    buf &= s
    if i != ss.high:
      buf &= ' '
  buf &= '\n'
  console.write(buf)

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
  console.write(buf)
  console.flush()
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
  discard console.err.flush()

proc writeException*(console: Console; ctx: JSContext) =
  console.write(ctx.getExceptionMsg())
  console.flush()

{.pop.} # raises: []
