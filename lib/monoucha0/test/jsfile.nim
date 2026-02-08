import std/posix
import std/unittest

import monoucha/javascript
import monoucha/tojs

type
  JSFile = ref object

jsDestructor(JSFile)

proc newJSFile(): JSFile {.jsctor.} =
  return JSFile()

test "jsfin: object finalizers":
  let rt = newGlobalJSRuntime()
  let ctx = rt.newJSContext()
  ctx.registerType(JSFile)
  const code = """
{ const file = new JSFile(); }
const file = new JSFile();
  """
  JS_FreeValue(ctx, ctx.eval(code))
  ctx.free()
  rt.free()
