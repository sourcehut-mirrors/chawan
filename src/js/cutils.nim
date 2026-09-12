{.used.}
const CFLAGS = "-fwrapv"

{.compile("../../lib/quickjs/cutils.c", CFLAGS).}

type JS_BOOL* = cint
