{.push raises: [].}

import std/os
import std/posix

import config/chapath
import io/dynstream
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsref
import monoucha/jsutils
import monoucha/quickjs
import monoucha/tojs
import types/blob
import types/jsopt
import types/opt
import types/url
import utils/myposix
import utils/strwidth
import utils/twtstr

jsNamespaceDef(Util):
  proc getcwd(): string {.jsstfunc.} =
    return myposix.getcwd()

  proc unquote(ctx: JSContext; s: string; base = ""): JSValue {.jsstfunc.} =
    let res = ChaPath(s).unquote(base)
    if res.isOk:
      return ctx.toJS(res.get)
    return JS_ThrowTypeError(ctx, "%s", cstring(res.error))

  proc openFile(path: string): cint {.jsstfunc.} =
    let ps = newPosixStream(path, O_RDONLY, 0)
    if ps == nil:
      return -1
    return ps.fd

  proc isFile(ctx: JSContext; val: JSValueConst): Opt[bool] {.jsstfunc.} =
    if JS_IsNumber(val):
      var fd: cint
      ?ctx.fromJS(val, fd)
      var stats: Stat
      return ok(fstat(fd, stats) == 0 and not S_ISDIR(stats.st_mode))
    var path: string
    ?ctx.fromJS(val, path)
    return ok(fileExists(path))

  proc closeFile(fd: cint) {.jsstfunc.} =
    discard close(fd)

  proc nimGCStats(): string {.jsstfunc.} =
    return GC_getStatistics()

  proc jsGCStats(ctx: JSContext): string {.jsstfunc.} =
    let rt = JS_GetRuntime(ctx)
    return rt.getMemoryUsage()

  proc nimCollect() {.jsstfunc.} =
    try:
      GC_fullCollect()
    except Exception:
      discard

  proc jsCollect(ctx: JSContext) {.jsstfunc.} =
    let rt = JS_GetRuntime(ctx)
    JS_RunGC(rt)

  proc sleep(millis: int) {.jsstfunc.} =
    os.sleep(millis)

  proc isSameAuthOrigin(a, b: URL): bool {.jsstfunc.} =
    return a.authOrigin.isSameOrigin(b.authOrigin);

  proc encodeURIPath(s: string): string {.jsstfunc.} =
    return percentEncode(s, PathPercentEncodeSet + {'%'})

  proc expandPath(s: string): string {.jsstfunc.} =
    return twtstr.expandPath(s)

  proc mkdir(s: string; mode: cint): cint {.jsstfunc.} =
    return posix.mkdir(cstring(s), Mode(mode))

  proc unlink(s: string) {.jsstfunc.} =
    discard posix.unlink(cstring(s))

  proc readBlob(path: string): WebFile {.jsstfunc.} =
    let ps = newPosixStream(path, O_RDONLY, 0)
    if ps == nil:
      return WebFile(nil)
    let name = path.afterLast('/')
    return newWebFile(name, ps.fd)

  proc convertSize(n: float64): string {.jsstfunc.} =
    twtstr.convertSize(uint64(n))

  proc width(s: string): int {.jsstfunc.} =
    strwidth.width(s)

proc addUtilModule*(ctx: JSContext): FromJSResult =
  ctx.registerNamespaceFree(UtilDef)

{.pop.}
