import std/unittest

import monoucha/fromjs
import monoucha/javascript
import monoucha/jstypes
import monoucha/optshim
import monoucha/quickjs
import monoucha/tojs

type TestEnum = enum
  teA = "a", teB = "b", teC = "c"

test "enums":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  let val = ctx.toJS(teB)
  var e: TestEnum
  assert ctx.fromJS(val, e).isSome
  assert e == teB
  ctx.free()
  rt.free()

test "enums null":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  let val = ctx.toJS("b\0c")
  var e: TestEnum
  assert ctx.fromJS(val, e).isNone
  ctx.free()
  rt.free()

type
  TestDict0 = object of JSDict
    a {.jsdefault: true.}: bool
    b: int
    c {.jsdefault.}: TestEnum
    d: TestDict1
    e {.jsdefault.}: int32
    f {.jsdefault.}: Option[JSValue]

  TestDict1 = object of JSDict
    a: Option[JSValue]

  TestDict2 = object of JSDict
    a {.jsdefault.}: Option[JSValue]
    b {.jsdefault: 2.}: int
    c {.jsdefault.}: string

  TestDict3 = object of TestDict2

proc default(e: typedesc[TestEnum]): TestEnum =
  return teB

test "jsdict undefined missing fields":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  var res: TestDict0
  assert ctx.fromJS(JS_UNDEFINED, res).isNone
  ctx.free()
  rt.free()

test "optional jsdict undefined":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  var res: TestDict2
  assert ctx.fromJS(JS_UNDEFINED, res).isSome, ctx.getExceptionMsg()
  ctx.free()
  rt.free()

test "optional jsdict inherited":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  var res: TestDict3
  assert ctx.fromJS(JS_UNDEFINED, res).isSome, ctx.getExceptionMsg()
  assert res.b == 2
  ctx.free()
  rt.free()

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
  block:
    var res: TestDict0
    assert ctx.fromJS(val, res).isSome, ctx.getExceptionMsg()
    discard ctx.eval("delete val.f", "<input>")
    assert res.a
    assert res.b == 1
    assert res.c == teB
    assert res.e == 0
    assert res.d.a.isNone
    ctx.defineProperty(res.f.get, "x", JS_NewInt32(ctx, 9))
  JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()
