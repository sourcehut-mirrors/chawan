{.push raises: [].}

import io/chafile
import js/fromjs
import js/jsbind
import js/jsutils
import js/quickjs
import types/jsopt
import types/opt
import types/url
import utils/twtstr

type Console* = ref object
  err: ChaFile

# Forward declarations
proc flush*(console: Console)

# Forward declaration hacks
# set in html/env
proc getConsole(ctx: JSContext): Console {.importc: "cha_$1".}

proc newConsole*(err: ChaFile): Console =
  return Console(err: err)

proc setStream*(console: Console; file: ChaFile; close: bool) =
  if console.err != nil and close:
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

proc consoleWriteCb(opaque: pointer; buf: cstringConst; len: csize_t) {.
    cdecl.} =
  if len > 0 and len <= csize_t(int.high):
    let H = int(len) - 1
    cast[Console](opaque).write(cstring(buf).toOpenArray(0, H))

jsNamespaceDef(console):
  proc log(ctx: JSContext; argv: varargs[JSValueConst]): Opt[void] {.jsstfunc,
      jsstfunc: "debug", jsstfunc: "error", jsstfunc: "info", jsstfunc: "warn",
      jsstfunc: "assert".} =
    let console = ctx.getConsole()
    for i, val in argv:
      if JS_IsString(val):
        var res: string
        ?ctx.fromJS(val, res)
        console.write(res)
      elif (var url: URL; ctx.fromJS(val, url).isOk):
        console.write($url)
      else:
        JS_PrintValue(ctx, consoleWriteCb, cast[pointer](console), val, nil)
      if i != argv.high:
        console.write(' ')
    console.write('\n')
    console.flush()
    ok()

  proc clear() {.jsstfunc.} =
    discard

proc addConsoleModule*(ctx: JSContext): Opt[void] =
  let obj = ctx.registerNamespace(consoleDef)
  if JS_IsUndefined(obj):
    return ok()
  if JS_IsException(obj):
    return err()
  let proto = JS_NewObject(ctx)
  if JS_IsException(proto):
    JS_FreeValue(ctx, obj)
    return err()
  let res = JS_SetPrototype(ctx, obj, proto)
  JS_FreeValue(ctx, obj)
  JS_FreeValue(ctx, proto)
  if res < 0:
    return err()
  ok()

proc flush*(console: Console) =
  discard console.err.flush()

proc writeException*(console: Console; ctx: JSContext) =
  console.write(ctx.getExceptionMsg())
  console.flush()

{.pop.} # raises: []
