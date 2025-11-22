import monoucha/quickjs

{.compile("domexception.c", "").}

proc JS_AddIntrinsicDOMException*(ctx: JSContext): cint {.importc.}
proc JS_ThrowDOMException*(ctx: JSContext; name, fmt: cstring): JSValue {.
  importc, varargs, discardable.}

proc addDOMExceptionModule*(ctx: JSContext) =
  discard JS_AddIntrinsicDOMException(ctx)
