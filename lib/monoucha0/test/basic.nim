import std/unittest

import monoucha/fromjs
import monoucha/javascript
import monoucha/optshim

type MyGlobal = ref object
  s: string

proc testFun(x: MyGlobal): string {.jsfunc.} =
  return "Hello, " & x.s

test "hello JS":
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  let global = MyGlobal(s: "world!")
  ctx.registerType(MyGlobal, asglobal = true)
  ctx.setGlobal(global)
  const code = "testFun()"
  let val = ctx.eval(code, "<test>", 0)
  var res: string
  check ctx.fromJS(val, res).isOk
  check res == "Hello, world!"
  JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()
