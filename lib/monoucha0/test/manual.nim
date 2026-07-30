import std/os
import std/posix
import std/strutils
import std/unittest

import monoucha/javascript
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
  Planet = ref object of JSRootObj
  Earth = ref object of Planet
  Moon = ref object of Planet

jsClassDef(Planet):
  discard

jsClassDef(Earth):
  jsextends PlanetDef

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
  let earth = Earth()
  ?ctx.registerClass(PlanetDef)
  ?ctx.registerClass(EarthDef, asglobal = true)
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
  ?ctx.registerClass(EarthDef, asglobal = true)
  ?ctx.registerClass(MoonDef)
  ctx.setGlobal(Earth())
  const code = "assert(globalThis instanceof Planet)"
  let val = ctx.eval(code)
  check not JS_IsException(val)
  JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()

test "jsget, jsset: basic property reflectors":
  type
    Moon = ref object

    Earth = ref object
      moon: Moon
      name: string
      population: int64

  jsDestructor(Moon)

  jsClassDef(Moon):
    discard

  jsClassDef(Earth):
    jsget Earth, moon
    jsgetset Earth, name
    jsgetset Earth, population

  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  let earth = Earth(moon: Moon(), population: 1, name: "Earth")
  ?ctx.registerClass(EarthDef, asglobal = true)
  ?ctx.registerClass(MoonDef)
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
  Window = ref object
    console: Console

  Console = ref object

jsDestructor(Console)

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
  let window = Window(console: Console())
  ?ctx.registerClass(WindowDef, asglobal = true)
  ?ctx.registerClass(ConsoleDef)
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
  JSFile = ref object
    buffer: pointer # some internal buffer handled as managed memory
    path: string

jsDestructor(JSFile)

jsClassNameDef(JSFile, "File"):
  jsget JSFile, path

  proc newJSFile(path: string): JSFile {.jsctor.} =
    return JSFile(
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
  proc finalize(file: JSFile) {.jsfin.} =
    if file.buffer != nil:
      dealloc(file.buffer)
      # Note: it is not necessary to nil out the pointer; it's just me being
      # paranoid :P
      file.buffer = nil
      inc unrefd

test "jsctor: constructors":
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  ?ctx.registerClass(WindowDef, asglobal = true)
  ?ctx.registerClass(JSFileDef)
  ctx.setGlobal(Window())
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
  ?ctx.registerClass(WindowDef, asglobal = true)
  ?ctx.registerClass(JSFileDef)
  ctx.setGlobal(Window())
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
  ?ctx.registerClass(WindowDef, asglobal = true)
  ?ctx.registerClass(JSFileDef)
  ctx.setGlobal(Window())
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
  ?ctx.registerClass(WindowDef, asglobal = true)
  ?ctx.registerClass(JSFileDef)
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
  GC_fullCollect() # ensure refc runs
  unrefd = 0 # ignore previous unrefs
  ?ctx.registerClass(WindowDef, asglobal = true)
  ?ctx.registerClass(JSFileDef)
  const code = """
/* this doesn't leak. yay :D */
{ const file = new File("doc/manual.md"); }
/* note that I put the above call in a separate scope, so QJS can unref
 * it immediately. in contrast, following file will not be deallocated until
 * the runtime is gone. */
const file = new File("doc/manual.md");
  """
  JS_FreeValue(ctx, ctx.eval(code))
  GC_fullCollect() # ensure refc runs
  check unrefd == 1 # first file is already deallocated
  ctx.free()
  GC_fullCollect() # ensure refc runs
  check unrefd == 1 # the second file is still available
  rt.free()
  check unrefd == 2 # runtime is freed, so the second file gets deallocated too
