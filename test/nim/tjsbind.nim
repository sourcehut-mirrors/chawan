import std/options
import std/os
import std/posix
import std/strutils
import std/unittest

import js/fromjs
import js/jsbind
import js/jsnull
import js/jspropenumlist
import js/jsref
import js/jstypes
import js/jsutils
import js/quickjs
import js/tojs
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

proc testHelloWorld() =
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

proc testErrorHandling() =
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

template `?`(x: JSCode) =
  assert x == fjOk

proc testRegisterClass() =
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

proc testGlobalObjects() =
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

proc testInheritance() =
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

proc testGetSet() =
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

var logged {.global.}: string

jsClassDef(Console):
  proc log(console: Console; s: string) {.jsfunc.} =
    logged = s

proc testFunctions() =
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
    check logged == "Hello, world!"
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
    return true

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

proc testConstructors() =
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

proc testFunctionGetSet() =
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

proc testStaticFunctions() =
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

proc testUnforgeable() =
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

proc testFinalizers() =
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

type TestEnum = enum
  teA = "a", teB = "b", teC = "c"

type TestEnum2 = enum
  te2C = "c", te2B = "b", te2A = "a"

proc testEnums() =
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  block:
    let val = ctx.toJS(teB)
    var e: TestEnum
    assert ctx.fromJS(val, e).isOk
    assert e == teB
  block:
    var e2: TestEnum2
    let val2 = ctx.toJS(te2A)
    assert ctx.fromJS(val2, e2).isOk
    assert e2 == te2A
  block:
    let val3 = ctx.toJS("b\0c")
    var e: TestEnum
    assert ctx.fromJS(val3, e).isErr
  ctx.free()
  rt.free()

type
  TestDict0 = object of JSDict
    a {.jsdefault: true.}: bool
    b: int
    c {.jsdefault.}: TestEnum
    d: TestDict1
    e {.jsdefault.}: int32
    f {.jsdefault.}: Option[JSValueTraced]

  TestDict1 = object of JSDict
    a: Option[JSValueConst]

  TestDict2 = object of JSDict
    a {.jsdefault.}: Option[JSValueTraced]
    b {.jsdefault: 2.}: int
    c {.jsdefault.}: string

  TestDict3 = object of TestDict2

proc default(e: typedesc[TestEnum]): TestEnum =
  return teB

proc testJSDictUndefined() =
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  block:
    var res: TestDict0
    assert ctx.fromJS(JS_UNDEFINED, res).isErr
  block:
    var res: TestDict2
    assert ctx.fromJS(JS_UNDEFINED, res).isOk, ctx.getExceptionMsg()
  block:
    var res: TestDict3
    assert ctx.fromJS(JS_UNDEFINED, res).isOk, ctx.getExceptionMsg()
    assert res.b == 2
  ctx.free()
  rt.free()

proc subroutine(ctx: JSContext; val: JSValueConst) =
  var res: TestDict0
  assert ctx.fromJS(val, res).isOk, ctx.getExceptionMsg()
  discard ctx.eval("delete val.f", "<input>")
  assert res.a
  assert res.b == 1
  assert res.c == teB
  assert res.e == 0
  assert res.d.a.isNone
  doAssert ctx.defineProperty(res.f.get, "x", JS_NewInt32(ctx, 9)) == fjOk

proc testJSDictTransitive() =
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  const code = """
const val = {
  b: 1,
  d: { a: null },
  f: { x: 1 }
}
val"""
  let val = ctx.eval(code, "<input>")
  ctx.subroutine(val)
  JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()

proc testJSPropEnumList() =
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  var list = newJSPropertyEnumList(ctx, 0)
  list.add(1)
  list.add("hi")
  list.add(3)
  list.add(4)
  assert list.len == 4
  js_free(ctx, list.buffer)
  ctx.free()
  rt.free()

proc testSeq() =
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  var test = @[1, 2, 3, 4]
  let jsTest = ctx.toJS(test)
  var test2: seq[int]
  assert ctx.fromJS(jsTest, test2).isOk
  assert test2 == test
  JS_FreeValue(ctx, jsTest)
  ctx.free()
  rt.free()

proc testTuple() =
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  var test = (2, "hi")
  let jsTest = ctx.toJS(test)
  var test2: tuple[n: int; s: string]
  assert ctx.fromJS(jsTest, test2).isOk
  assert test2 == test
  JS_FreeValue(ctx, jsTest)
  ctx.free()
  rt.free()

type
  X = JSRef[XObj]

  XObj = object

jsClassDef(X):
  proc foo(x: X; s: sink string) {.jsfunc.} =
    discard

  proc bar(x: X; s: sink(string)) {.jsfunc.} =
    discard

proc testSink() =
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  ?ctx.registerClass(XDef)
  ctx.free()
  rt.free()

proc main() =
  testHelloWorld()
  testErrorHandling()
  testRegisterClass()
  testGlobalObjects()
  testInheritance()
  testGetSet()
  testFunctions()
  testConstructors()
  testFunctionGetSet()
  testStaticFunctions()
  testUnforgeable()
  testFinalizers()
  testEnums()
  testJSDictUndefined()
  testJSDictTransitive()
  testJSPropEnumList()
  testSeq()
  testTuple()
  testSink()

main()
