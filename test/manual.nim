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
  let res = ctx.eval(code, "<test>")
  check fromJS[string](ctx, res).get == "Hello from JS!"
  JS_FreeValue(ctx, res)
  ctx.free()
  rt.free()

proc evalConvert[T](ctx: JSContext; code, file: string): Result[T, string] =
  let res = ctx.eval(code, file)
  if JS_IsException(res):
    # Exception in eval; return the message.
    return err(ctx.getExceptionMsg())
  let val = fromJS[T](ctx, res)
  JS_FreeValue(ctx, res)
  if val.isNone:
    # Conversion failed; convert the error value into an exception and then
    # return its message.
    JS_FreeValue(ctx, toJS(ctx, val.error))
    return err(ctx.getExceptionMsg())
  # All ok! Return the converted object.
  return ok(val.get)

test "Error handling":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  const code = "abcd"
  let res = ctx.eval(code, "<test>")
  check JS_IsException(res)
  const ex = """
ReferenceError: 'abcd' is not defined
    at <eval> (<test>)
"""
  check ctx.getExceptionMsg() == ex
  check evalConvert[string](ctx, code, "<test>").error == ex
  JS_FreeValue(ctx, res)
  ctx.free()
  rt.free()

test "registerType: registering type interfaces":
  type Moon = ref object
  jsDestructor(Moon)
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  ctx.registerType(Moon)
  const code = "Moon"
  let res = ctx.eval(code, "<test>")
  check fromJS[string](ctx, res).get == """
function Moon() {
    [native code]
}"""
  JS_FreeValue(ctx, res)
  ctx.free()
  rt.free()

test "Global objects":
  type Earth = ref object
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  let earth = Earth()
  ctx.registerType(Earth, asglobal = true)
  ctx.setGlobal(earth)
  const code = "globalThis instanceof Earth"
  let res = ctx.eval(code, "<test>")
  check fromJS[bool](ctx, res).get
  JS_FreeValue(ctx, res)
  ctx.free()
  rt.free()

test "Inheritance":
  type
    Planet = ref object of RootObj
    Earth = ref object of Planet
    Moon = ref object of Planet
  jsDestructor(Moon)
  jsDestructor(Planet)
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  let planetCID = ctx.registerType(Planet)
  ctx.registerType(Earth, parent = planetCID, asglobal = true)
  ctx.registerType(Moon, parent = planetCID)
  const code = "globalThis instanceof Planet"
  let res = ctx.eval(code, "<test>")
  check fromJS[bool](ctx, res).get
  JS_FreeValue(ctx, res)
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
  let res = ctx.eval(code, "<test>")
  check fromJS[string](ctx, res).get == "name: Earth, moon: [object Moon]"
  check earth.population == int64(8e9)
  JS_FreeValue(ctx, res)
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
  let res = ctx.eval(code, "<test>")
  check not JS_IsException(res)
  JS_FreeValue(ctx, res)
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
  const code = """
assert(new File('/path/to/file') + '' == '[object File]')
"""
  let res = ctx.eval(code, "<test>")
  check not JS_IsException(res)
  JS_FreeValue(ctx, res)
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
  const code = """
const file = new File("/path/to/file");
assert(file.path === "/path/to/file");
assert(file.name === "file"); /* file */
file.name = "new-name";
assert(file.path === "/path/to/new-name");
  """
  let res = ctx.eval(code, "<test>")
  check not JS_IsException(res)
  JS_FreeValue(ctx, res)
  ctx.free()
  rt.free()

proc jsExists(path: string): bool {.jsstfunc: "JSFile.exists".} =
  return fileExists(path)

test "jsstfunc: static functions":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  ctx.registerType(Window, asglobal = true)
  ctx.registerType(JSFile, name = "File")
  const code = """
assert(File.exists("doc/manual.md"));
  """
  let res = ctx.eval(code, "<test>")
  check not JS_IsException(res)
  JS_FreeValue(ctx, res)
  ctx.free()
  rt.free()

# this will always return the result of the fstat call.
proc owner(file: JSFile): int {.jsuffget.} =
  let fd = open(cstring(file.path), O_RDONLY, 0)
  if fd == -1: return -1
  var stats: Stat
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
  let res = ctx.eval(code, "<test>")
  check JS_IsException(res)
  JS_FreeValue(ctx, res)
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
  JS_FreeValue(ctx, ctx.eval(code, "<test>"))
  check unrefd == 1 # deallocated once, all good :)
  ctx.free()
  check unrefd == 1 # still available...
  rt.free()
  check unrefd == 2 # runtime is free'd; deallocated twice!
