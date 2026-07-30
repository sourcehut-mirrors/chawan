import std/unittest

import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsutils
import monoucha/quickjs

type MyGlobal = ref object
  s: string

jsClassDef(MyGlobal):
  proc testFun(x: MyGlobal): string {.jsfunc.} =
    return "Hello, " & x.s

template `?`(x: FromJSResult) =
  assert x == fjOk

test "hello JS":
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  let global = MyGlobal(s: "world!")
  ?ctx.registerClass(MyGlobalDef, asglobal = true)
  ctx.setGlobal(global)
  const code = "testFun()"
  let val = ctx.eval(code, "<test>", 0)
  var res: string
  check ctx.fromJS(val, res).isOk
  check res == "Hello, world!"
  JS_FreeValue(ctx, val)
  ctx.free()
  rt.free()
