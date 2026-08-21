import std/os
import std/posix
import std/strutils
import std/unittest

import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsref
import monoucha/jsutils
import monoucha/quickjs
import types/opt

proc evalConvert[T](ctx: JSContext; code: string; file = "<input>";
    flags = JS_EVAL_TYPE_GLOBAL): Result[T, string] =
  let val = ctx.eval(code, file, flags)
  var res: T
  if ctx.fromJSFree(val, res).isErr:
    # Exception when converting the value.
    return err(ctx.getExceptionMsg())
  # All ok; return the converted object.
  ok(res)

test "Hello, world":
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  const code = "'Hello from JS!'"
  let val = ctx.eval(code)
  var res: string
  check ctx.fromJS(val, res).isOk
  check res == "Hello from JS!"
  JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()

test "Error handling":
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  const code = "abcd"
  let res = ctx.eval(code, "<test>")
  check JS_IsException(res)
  const ex = """
ReferenceError: 'abcd' is not defined
    at <eval> (<test>:1:1)
"""
  check ctx.getExceptionMsg() == ex
  check evalConvert[string](ctx, code, "<test>").error == ex
  JS_FreeValue(ctx, res)
  ctx.free()
  rt.free()

type
  Planet = JSRef[PlanetObj]

  PlanetObj = object of JSRootObj

  Earth = JSRef[EarthObj]

  EarthObj = object of PlanetObj
    moon: Moon
    name: string
    population: int64

  Moon = JSRef[MoonObj]

  MoonObj = object of PlanetObj

jsClassDef(Planet):
  discard

jsClassDef(Earth):
  jsextends PlanetDef

  jsget Earth, moon
  jsgetset Earth, name
  jsgetset Earth, population

  proc jsAssert(earth: Earth; pred: bool) {.jsfunc: "assert".} =
    assert pred

jsClassDef(Moon):
  jsextends PlanetDef

template `?`(x: FromJSResult) =
  assert x == fjOk

test "registerType: registering type interfaces":
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  ?ctx.registerClass(PlanetDef)
  ?ctx.registerClass(MoonDef)
  block:
    const code = "Moon"
    let val = ctx.eval(code)
    var res: string
    check ctx.fromJS(val, res).isOk
    check res == """
function Moon() {
    [native code]
}"""
    JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()

test "Global objects":
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  block:
    ?ctx.registerClass(PlanetDef)
    ?ctx.registerGlobalClass(EarthDef)
    let earth = jsNew EarthObj()
    ctx.setGlobal(earth)
    const code = "assert(globalThis instanceof Earth)"
    let val = ctx.eval(code)
    check not JS_IsException(val)
    JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()

test "Inheritance":
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  ?ctx.registerClass(PlanetDef)
  ?ctx.registerGlobalClass(EarthDef)
  ?ctx.registerClass(MoonDef)
  block:
    ctx.setGlobal(jsNew EarthObj())
    const code = "assert(globalThis instanceof Planet)"
    let val = ctx.eval(code)
    check not JS_IsException(val)
    JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()

test "jsget, jsset: basic property reflectors":
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  block:
    ?ctx.registerClass(PlanetDef)
    ?ctx.registerGlobalClass(EarthDef)
    ?ctx.registerClass(MoonDef)
    let moon = jsNew MoonObj()
    let earth = jsNew EarthObj(moon: moon, population: 1, name: "Earth")
    ctx.setGlobal(earth)
    const code = """
globalThis.population = 8e9;
"name: " + globalThis.name + ", moon: " + globalThis.moon;
  """
    let val = ctx.eval(code)
    var res: string
    check ctx.fromJS(val, res).isOk
    check res == "name: Earth, moon: [object Moon]"
    check earth.population == int64(8e9)
    JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()

type
  Window = JSRef[WindowObj]

  WindowObj = object
    console: Console

  Console = JSRef[ConsoleObj]

  ConsoleObj = object

jsClassDef(Window):
  jsget Window, console

  # aux stuff for tests
  proc jsAssert(window: Window; pred: bool) {.jsfunc: "assert".} =
    assert pred

jsClassDef(Console):
  proc log(console: Console; s: string) {.jsfunc.} =
    echo s

test "jsfunc: regular functions":
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  ?ctx.registerGlobalClass(WindowDef)
  ?ctx.registerClass(ConsoleDef)
  block:
    let window = jsNew WindowObj(console: jsNew ConsoleObj())
    ctx.setGlobal(window)
    const code = """
console.log('Hello, world!')
"""
    let val = ctx.eval(code)
    check not JS_IsException(val)
    JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()

type
  JSFile = JSRef[JSFileObj]

  JSFileObj = object
    buffer: pointer # some internal buffer handled as managed memory
    path: string

jsClassNameDef(JSFile, "File"):
  jsget JSFile, path

  proc newJSFile(path: string): JSFile {.jsctor.} =
    jsNew JSFileObj(
      path: path,
      buffer: alloc(4096)
    )

  func name(file: JSFile): string {.jsfget.} =
    return file.path.substr(file.path.rfind('/') + 1)

  proc setName(file: JSFile; s: string) {.jsfset: "name".} =
    let i = file.path.rfind('/')
    file.path = file.path.substr(0, i) & s

  proc jsExists(path: string): bool {.jsstfunc: "exists".} =
    return fileExists(path)

  # this will always return the result of the fstat call.
  proc owner(file: JSFile): int {.jsuffget.} =
    let fd = open(cstring(file.path), O_RDONLY, 0)
    if fd == -1: return -1
    var stats = Stat.default
    if fstat(fd, stats) == -1:
      discard close(fd)
      return -1
    return int(stats.st_uid)

  proc getOwner(file: JSFile): int {.jsuffget.} =
    return file.owner

  var unrefd {.global.} = 0
  proc finalize(rt: JSRuntime; file: JSFile) {.jsfin.} =
    if file.buffer != nil:
      dealloc(file.buffer)
      inc unrefd

test "jsctor: constructors":
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  ?ctx.registerGlobalClass(WindowDef)
  ?ctx.registerClass(JSFileDef)
  block:
    ctx.setGlobal(jsNew WindowObj())
    const code = """
assert(new File('/path/to/file') + '' == '[object File]')
  """
    let val = ctx.eval(code)
    check not JS_IsException(val)
    JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()

test "jsfget, jsfset: custom property reflectors":
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  ?ctx.registerGlobalClass(WindowDef)
  ?ctx.registerClass(JSFileDef)
  block:
    ctx.setGlobal(jsNew WindowObj())
    const code = """
const file = new File("/path/to/file");
assert(file.path === "/path/to/file");
assert(file.name === "file"); /* file */
file.name = "new-name";
assert(file.path === "/path/to/new-name");
    """
    let val = ctx.eval(code)
    check not JS_IsException(val)
    JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()

test "jsstfunc: static functions":
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  ?ctx.registerGlobalClass(WindowDef)
  ?ctx.registerClass(JSFileDef)
  block:
    ctx.setGlobal(jsNew WindowObj())
    const code = """
assert(File.exists("doc/manual.md"));
    """
    let val = ctx.eval(code)
    check not JS_IsException(val)
    JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()

test "jsuffunc, jsufget, jsuffget: the LegacyUnforgeable property":
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  ?ctx.registerGlobalClass(WindowDef)
  ?ctx.registerClass(JSFileDef)
  block:
    const code = """
const file = new File("doc/manual.md");
const oldGetOwner = file.getOwner;
file.getOwner = () => -2; /* doesn't work */
assert(oldGetOwner == file.getOwner);
Object.defineProperty(file, "owner", { value: -2 }); /* throws */
    """
    let val = ctx.eval(code)
    check JS_IsException(val)
    JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()

test "jsfin: object finalizers":
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  unrefd = 0 # ignore previous unrefs
  ?ctx.registerGlobalClass(WindowDef)
  ?ctx.registerClass(JSFileDef)
  block:
    const code = """
/* this doesn't leak. yay :D */
{ const file = new File("doc/manual.md"); }
/* note that I put the above call in a separate scope, so QJS can unref
 * it immediately. in contrast, following file will not be deallocated until
 * the runtime is gone. */
const file = new File("doc/manual.md");
    """
    JS_FreeValue(ctx, ctx.eval(code))
    check unrefd == 1 # first file is already deallocated
  ctx.free()
  check unrefd == 1 # the second file is still available
  rt.free()
  check unrefd == 2 # runtime is freed, so the second file gets deallocated too
