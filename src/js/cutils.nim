{.used.}
when not compileOption("threads"):
  const CFLAGS = "-fwrapv -DCHA_NO_THREADS"
else:
  const CFLAGS = "-fwrapv"

{.compile("../../lib/quickjs/cutils.c", CFLAGS).}

type JS_BOOL* = cint
