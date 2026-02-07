{.push raises: [].}

import std/os
import std/posix

import config/chapath
import io/dynstream
import monoucha/jsbind
import monoucha/jsutils
import monoucha/quickjs
import monoucha/tojs
import types/opt
import types/url
import utils/myposix
import utils/twtstr

type Util = ref object

jsDestructor(Util)

proc getcwd(): string {.jsstfunc: "Util".} =
  return myposix.getcwd()

proc unquote(ctx: JSContext; s: string; base = ""): JSValue {.
    jsstfunc: "Util".} =
  let res = ChaPath(s).unquote(base)
  if res.isOk:
    return ctx.toJS(res.get)
  return JS_ThrowTypeError(ctx, "%s", cstring(res.error))

proc openFile(path: string): cint {.jsstfunc: "Util".} =
  let ps = newPosixStream(path, O_RDONLY, 0)
  if ps == nil:
    return -1
  return ps.fd

proc isFile(fd: cint): bool {.jsstfunc: "Util".} =
  var stats: Stat
  return fstat(fd, stats) == 0 and not S_ISDIR(stats.st_mode)

proc closeFile(fd: cint) {.jsstfunc: "Util".} =
  discard close(fd)

proc nimGCStats(): string {.jsstfunc: "Util".} =
  return GC_getStatistics()

proc jsGCStats(ctx: JSContext): string {.jsstfunc: "Util".} =
  let rt = JS_GetRuntime(ctx)
  return rt.getMemoryUsage()

proc nimCollect() {.jsstfunc: "Util".} =
  try:
    GC_fullCollect()
  except Exception:
    discard

proc jsCollect(ctx: JSContext) {.jsstfunc: "Util".} =
  let rt = JS_GetRuntime(ctx)
  JS_RunGC(rt)

proc sleep(millis: int) {.jsstfunc: "Util".} =
  os.sleep(millis)

proc isSameAuthOrigin(a, b: URL): bool {.jsstfunc: "Util".} =
  return a.authOrigin.isSameOrigin(b.authOrigin);

proc encodeURIPath(s: string): string {.jsstfunc: "Util".} =
  return percentEncode(s, LocalPathPercentEncodeSet)

proc expandPath(s: string): string {.jsstfunc: "Util".} =
  return twtstr.expandPath(s)

proc mkdir(s: string; mode: cint): cint {.jsstfunc: "Util".} =
  return posix.mkdir(cstring(s), Mode(mode))

proc unlink(s: string) {.jsstfunc: "Util".} =
  discard posix.unlink(cstring(s))

proc addUtilModule*(ctx: JSContext): JSClassID =
  return ctx.registerType(Util)

{.pop.}
