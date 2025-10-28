{.used.}
when not compileOption("threads"):
  const CFLAGS = "-fwrapv -DMNC_NO_THREADS"
else:
  const CFLAGS = "-fwrapv"

{.compile("qjs/cutils.c", CFLAGS).}

type JS_BOOL* {.importc: "bool".} = bool
