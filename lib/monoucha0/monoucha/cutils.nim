{.used.}
when not compileOption("threads"):
  const CFLAGS = "-fwrapv -DCHA_NO_THREADS"
else:
  const CFLAGS = "-fwrapv"

{.compile("qjs/cutils.c", CFLAGS).}

type JS_BOOL* = distinct cint

converter toBool*(x: JS_BOOL): bool =
  cast[bool](x)

converter toJSBool*(x: bool): JS_BOOL =
  JS_BOOL(x)
