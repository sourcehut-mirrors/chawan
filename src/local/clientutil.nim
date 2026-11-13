{.push raises: [].}

import std/posix

import config/chapath
import io/dynstream
import js/constcharp
import js/fromjs
import js/jsbind
import js/jsref
import js/jstypes
import js/jsutils
import js/quickjs
import js/tojs
import server/blob
import server/url
import utils/chaos
import utils/cowstr
import utils/opt
import utils/strwidth
import utils/twtstr

jsNamespaceDef(Util):
  proc getcwd(): Str {.jsstfunc.} =
    return chaos.getcwd()

  proc unquote(ctx: JSContext; s: Str; base = str("")): JSValue {.jsstfunc.} =
    let res = ChaPath(s).unquote(base)
    if res.isOk:
      return ctx.toJS(res.get)
    return JS_ThrowTypeError(ctx, "%s", res.error.toCString())

  proc openFile(path: CStringNZ): cint {.jsstfunc.} =
    let ps = newPosixStream(path.p, O_RDONLY, 0)
    if ps == nil:
      return -1
    return ps.fd

  proc isFile(ctx: JSContext; val: JSValueConst): Opt[bool] {.jsstfunc.} =
    if JS_IsNumber(val):
      var fd: cint
      ?ctx.fromJS(val, fd)
      var stats: Stat
      return ok(fstat(fd, stats) == 0 and not S_ISDIR(stats.st_mode))
    var path: CStringNZ
    ?ctx.fromJS(val, path)
    return ok(fileExists(path.p))

  proc closeFile(fd: cint) {.jsstfunc.} =
    discard close(fd)

  proc nimGCStats(): string {.jsstfunc.} =
    return GC_getStatistics()

  proc jsGCStats(ctx: JSContext): Str {.jsstfunc.} =
    let rt = JS_GetRuntime(ctx)
    rt.getMemoryUsage()

  proc gc(ctx: JSContext) {.jsstfunc.} =
    let rt = JS_GetRuntime(ctx)
    JS_RunGC(rt)

  proc sleep(millis: int) {.jsstfunc.} =
    chaos.sleep(millis)

  proc isSameAuthOrigin(a, b: URL): bool {.jsstfunc.} =
    return a.authOrigin.isSameOrigin(b.authOrigin);

  proc encodeURIPath(s: DOMString): Str {.jsstfunc.} =
    return percentEncode(s.asStr, PathPercentEncodeSet + {'%'})

  proc expandPath(s: DOMString): Str {.jsstfunc.} =
    return chaos.expandPath(s.asStr)

  proc mkdir(s: CStringNZ; mode: cint): cint {.jsstfunc.} =
    return posix.mkdir(s.p, Mode(mode))

  proc unlink(s: CStringNZ) {.jsstfunc.} =
    discard posix.unlink(s.p)

  proc readBlob(path: sink CStringNZ): WebFile {.jsstfunc.} =
    let ps = newPosixStream(path.p, O_RDONLY, 0)
    if ps == nil:
      return WebFile(nil)
    let name = path.toStr().afterLast('/')
    return newWebFile(name, ps.fd)

  proc convertSize(n: float64): Str {.jsstfunc.} =
    cowstr.convertSize(uint64(n))

  proc width(s: DOMString): int {.jsstfunc.} =
    strwidth.width(s.toOpenArray())

  proc importModule(ctx: JSContext; path: CStringNZ): JSValue {.jsstfunc.} =
    # used in init.js because QJS cannot handle import() if you strip debug
    # info
    JS_LoadModule(ctx, chaos.getcwd().toCStringConst(), cstringConst(path.p))

proc addUtilModule*(ctx: JSContext): JSCode =
  ctx.registerNamespaceFree(UtilDef)

{.pop.}
