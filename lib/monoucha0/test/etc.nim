import std/unittest

import monoucha/fromjs
import monoucha/javascript
import monoucha/jspropenumlist
import monoucha/jstypes
import monoucha/optshim
import monoucha/quickjs
import monoucha/tojs

type TestEnum = enum
  teA = "a", teB = "b", teC = "c"

type TestEnum2 = enum
  te2C = "c", te2B = "b", te2A = "a"

test "enums":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  let val = ctx.toJS(teB)
  var e: TestEnum
  assert ctx.fromJS(val, e).isOk
  assert e == teB
  var e2: TestEnum2
  let val2 = ctx.toJS(te2A)
  assert ctx.fromJS(val2, e2).isOk
  assert e2 == te2A
  ctx.free()
  rt.free()

test "enums null":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  let val = ctx.toJS("b\0c")
  var e: TestEnum
  assert ctx.fromJS(val, e).isErr
  ctx.free()
  rt.free()

type
  TestDict0 = object of JSDict
    a {.jsdefault: true.}: bool
    b: int
    c {.jsdefault.}: TestEnum
    d: TestDict1
    e {.jsdefault.}: int32
    f {.jsdefault.}: Option[JSValueConst]

  TestDict1 = object of JSDict
    a: Option[JSValueConst]

  TestDict2 = object of JSDict
    a {.jsdefault.}: Option[JSValueConst]
    b {.jsdefault: 2.}: int
    c {.jsdefault.}: string

  TestDict3 = object of TestDict2

proc default(e: typedesc[TestEnum]): TestEnum =
  return teB

test "jsdict undefined missing fields":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  var res: TestDict0
  assert ctx.fromJS(JS_UNDEFINED, res).isErr
  ctx.free()
  rt.free()

test "optional jsdict undefined":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  var res: TestDict2
  assert ctx.fromJS(JS_UNDEFINED, res).isOk, ctx.getExceptionMsg()
  ctx.free()
  rt.free()

test "optional jsdict inherited":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
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
  doAssert ctx.defineProperty(res.f.get, "x", JS_NewInt32(ctx, 9)) == dprSuccess

test "jsdict transitive JSValue descendant":
  let rt = newJSRuntime()
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
  GC_fullCollect()
  JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()

test "jspropenumlist":
  let rt = newJSRuntime()
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

test "fromjs-seq":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  var test = @[1, 2, 3, 4]
  let jsTest = ctx.toJS(test)
  var test2: seq[int]
  assert ctx.fromJS(jsTest, test2).isOk
  assert test2 == test
  JS_FreeValue(ctx, jsTest)
  ctx.free()
  rt.free()

test "fromjs-tuple":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  var test = (2, "hi")
  let jsTest = ctx.toJS(test)
  var test2: tuple[n: int; s: string]
  assert ctx.fromJS(jsTest, test2).isOk
  assert test2 == test
  JS_FreeValue(ctx, jsTest)
  ctx.free()
  rt.free()

type X = ref object

jsDestructor(X)

proc foo(x: X; s: sink string) {.jsfunc.} =
  discard

proc bar(x: X; s: sink(string)) {.jsfunc.} =
  discard

test "sink":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  ctx.registerType(X)
  ctx.free()
  rt.free()
