{.push raises: [].}

import monoucha/jsopaque
import monoucha/quickjs
import types/opt

{.compile("domexception.c", "").}

proc JS_AddIntrinsicDOMException*(ctx: JSContext): cint {.importc.}
proc JS_ThrowDOMException*(ctx: JSContext; name, fmt: cstring): JSValue {.
  importc, varargs, discardable.}

proc addDOMExceptionModule*(ctx: JSContext): Opt[void] =
  if ctx.getOpaque() == nil:
    return ok()
  if JS_AddIntrinsicDOMException(ctx) < 0:
    return err()
  ok()

{.pop.} # raises: []
