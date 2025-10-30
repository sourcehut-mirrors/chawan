{.push raises: [].}

import io/chafile
import monoucha/fromjs
import monoucha/jsopaque
import monoucha/jsutils
import monoucha/quickjs
import types/jsopt
import utils/twtstr

type Console* = ref object
  err*: ChaFile
  clearFun*: proc() {.raises: [].}
  showFun*: proc() {.raises: [].}
  hideFun*: proc() {.raises: [].}

# Forward declarations
proc flush*(console: Console)

# Forward declaration hacks
# set in html/env
var getConsoleImpl*: proc(ctx: JSContext): Console {.nimcall, raises: [].}

proc newConsole*(err: ChaFile): Console =
  return Console(err: err)

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

proc jsConsoleLog(ctx: JSContext; this: JSValueConst; argc: cint;
    argv: JSValueConstArray): JSValue {.cdecl.} =
  let console = ctx.getConsoleImpl()
  var buf = ""
  let H = argc - 1
  for i, val in argv.toOpenArray(0, H):
    var res: string
    ?ctx.fromJS(val, res)
    buf &= res
    if i != H:
      buf &= ' '
  buf &= '\n'
  console.write(buf)
  console.flush()
  return JS_UNDEFINED

proc jsConsoleClear(ctx: JSContext; this: JSValueConst; argc: cint;
    argv: JSValueConstArray): JSValue {.cdecl.} =
  let console = ctx.getConsoleImpl()
  if console.clearFun != nil:
    console.clearFun()
  return JS_UNDEFINED

proc jsConsoleShow(ctx: JSContext; this: JSValueConst; argc: cint;
    argv: JSValueConstArray): JSValue {.cdecl.} =
  let console = ctx.getConsoleImpl()
  if console.showFun != nil:
    console.showFun()
  return JS_UNDEFINED

proc jsConsoleHide(ctx: JSContext; this: JSValueConst; argc: cint;
    argv: JSValueConstArray): JSValue {.cdecl.} =
  let console = ctx.getConsoleImpl()
  if console.hideFun != nil:
    console.hideFun()
  return JS_UNDEFINED

let jsConsoleFuncs {.global.} = [
    JS_CFUNC_DEF("log", 0, jsConsoleLog),
    # For now, these are the same as log().
    JS_CFUNC_DEF("debug", 0, jsConsoleLog),
    JS_CFUNC_DEF("error", 0, jsConsoleLog),
    JS_CFUNC_DEF("info", 0, jsConsoleLog),
    JS_CFUNC_DEF("warn", 0, jsConsoleLog),
    JS_CFUNC_DEF("show", 0, jsConsoleShow),
    JS_CFUNC_DEF("hide", 0, jsConsoleHide),
    JS_CFUNC_DEF("clear", 0, jsConsoleClear),
    JS_PROP_STRING_DEF("[Symbol.toStringTag]", "console", JS_PROP_CONFIGURABLE),
]

proc addConsoleModule*(ctx: JSContext) =
  # console doesn't really look like other WebIDL interfaces; it's just an
  # object with a couple functions assigned.
  let console = JS_NewObject(ctx)
  if JS_IsException(console):
    return
  let fp = cast[JSCFunctionListP](unsafeAddr jsConsoleFuncs[0])
  if JS_SetPropertyFunctionList(ctx, console, fp, cint(jsConsoleFuncs.len)) < 0:
    return
  discard ctx.definePropertyCW(ctx.getOpaque().global, "console", console)

proc flush*(console: Console) =
  discard console.err.flush()

proc writeException*(console: Console; ctx: JSContext) =
  console.write(ctx.getExceptionMsg())
  console.flush()

{.pop.} # raises: []
