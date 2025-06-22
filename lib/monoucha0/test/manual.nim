import std/os
import std/posix
import std/strutils
import std/unittest

import monoucha/fromjs
import monoucha/javascript
import monoucha/optshim
import monoucha/tojs

test "Hello, world":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  const code = "'Hello from JS!'"
  let val = ctx.eval(code)
  var res: string
  check ctx.fromJS(val, res).isOk
  check res == "Hello from JS!"
  JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()

proc evalConvert[T](ctx: JSContext; code: string;
    file = "<input>"): Result[T, string] =
  let val = ctx.eval(code, file)
  defer: JS_FreeValue(ctx, val) # unref result before returning
  var res: T
  if ctx.fromJS(val, res).isErr:
    # Conversion failed; return the exception message.
    return err(ctx.getExceptionMsg())
  # All ok! Return the converted object.
  return ok(res)

test "Error handling":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  const code = "abcd"
  let res = ctx.eval(code, "<test>")
  check JS_IsException(res)
  const ex = """
ReferenceError: abcd is not defined
    at <eval> (<test>:1:1)
"""
  check ctx.getExceptionMsg() == ex
  check evalConvert[string](ctx, code, "<test>").error == ex
  JS_FreeValue(ctx, res)
  ctx.free()
  rt.free()

type
  Planet = ref object of RootObj
  Earth = ref object of Planet
  Moon = ref object of Planet

proc jsAssert(earth: Earth; pred: bool) {.jsfunc: "assert".} =
  assert pred

test "registerType: registering type interfaces":
  type Moon = ref object
  jsDestructor(Moon)
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  ctx.registerType(Moon)
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
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  let earth = Earth()
  ctx.registerType(Earth, asglobal = true)
  ctx.setGlobal(earth)
  const code = "assert(globalThis instanceof Earth)"
  let val = ctx.eval(code)
  check not JS_IsException(val)
  JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()

test "Inheritance":
  jsDestructor(Moon)
  jsDestructor(Planet)
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  let planetCID = ctx.registerType(Planet)
  ctx.registerType(Earth, parent = planetCID, asglobal = true)
  ctx.registerType(Moon, parent = planetCID)
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
      moon {.jsget.}: Moon
      name {.jsgetset.}: string
      population {.jsset.}: int64

  jsDestructor(Moon)
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  let earth = Earth(moon: Moon(), population: 1, name: "Earth")
  ctx.registerType(Earth, asglobal = true)
  ctx.registerType(Moon)
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
    console {.jsget.}: Console
  Console = ref object

jsDestructor(Console)

# aux stuff for tests
proc jsAssert(window: Window; pred: bool) {.jsfunc: "assert".} =
  assert pred

test "jsfunc: regular functions":
  proc log(console: Console; s: string) {.jsfunc.} =
    echo s
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  let window = Window(console: Console())
  ctx.registerType(Window, asglobal = true)
  ctx.registerType(Console)
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
    path {.jsget.}: string

jsDestructor(JSFile)

proc newJSFile(path: string): JSFile {.jsctor.} =
  return JSFile(
    path: path,
    buffer: alloc(4096)
  )

test "jsctor: constructors":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  ctx.registerType(Window, asglobal = true)
  ctx.registerType(JSFile, name = "File")
  ctx.setGlobal(Window())
  const code = """
assert(new File('/path/to/file') + '' == '[object File]')
"""
  let val = ctx.eval(code)
  check not JS_IsException(val)
  JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()

func name(file: JSFile): string {.jsfget.} =
  return file.path.substr(file.path.rfind('/') + 1)

proc setName(file: JSFile; s: string) {.jsfset: "name".} =
  let i = file.path.rfind('/')
  file.path = file.path.substr(0, i) & s

test "jsfget, jsfset: custom property reflectors":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  ctx.registerType(Window, asglobal = true)
  ctx.registerType(JSFile, name = "File")
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

proc jsExists(path: string): bool {.jsstfunc: "JSFile.exists".} =
  return fileExists(path)

test "jsstfunc: static functions":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  ctx.registerType(Window, asglobal = true)
  ctx.registerType(JSFile, name = "File")
  ctx.setGlobal(Window())
  const code = """
assert(File.exists("doc/manual.md"));
  """
  let val = ctx.eval(code)
  check not JS_IsException(val)
  JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()

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

test "jsuffunc, jsufget, jsuffget: the LegacyUnforgeable property":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  ctx.registerType(Window, asglobal = true)
  ctx.registerType(JSFile, name = "File")
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

var unrefd {.global.} = 0
proc finalize(file: JSFile) {.jsfin.} =
  if file.buffer != nil:
    dealloc(file.buffer)
    # Note: it is not necessary to nil out the pointer; it's just me being
    # paranoid :P
    file.buffer = nil
    inc unrefd

test "jsfin: object finalizers":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  GC_fullCollect() # ensure refc runs
  unrefd = 0 # ignore previous unrefs
  ctx.registerType(Window, asglobal = true)
  ctx.registerType(JSFile, name = "File")
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
