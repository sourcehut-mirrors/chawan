{.push raises: [].}

from std/os import parentDir

{.used.}
# used so that we can import it from quickjs.nim

import libunicode

export libunicode.JS_BOOL

when not compileOption("threads"):
  const CFLAGS = "-fwrapv -DMNC_NO_THREADS"
else:
  const CFLAGS = "-fwrapv"

{.compile("qjs/libregexp.c", CFLAGS).}

# this is hardcoded into quickjs, so we must override it here.
proc lre_realloc(opaque, p: pointer; size: csize_t): pointer {.exportc.} =
  if size == 0:
    if p != nil:
      dealloc(p)
    return nil
  return realloc(p, size)

# Hack: quickjs provides a lre_check_stack_overflow, but that basically
# depends on the entire QuickJS runtime. So to avoid pulling that in as
# a necessary dependency, we must provide one ourselves, but *only* if
# quickjs has not been imported.
# So we define NOT_LRE_ONLY in quickjs.nim, and check it in the "second
# compilation pass" (i.e. in C).
{.emit: """
#ifndef NOT_LRE_ONLY
int lre_check_timeout(void *opaque)
{
  return 0;
}

int lre_check_stack_overflow(void *opaque, size_t alloca_size)
{
  return 0;
}
#endif
""".}

type
  LREFlag* {.size: sizeof(cint).} = enum
    LRE_FLAG_GLOBAL = "g"
    LRE_FLAG_IGNORECASE = "i"
    LRE_FLAG_MULTILINE = "m"
    LRE_FLAG_DOTALL = "s"
    LRE_FLAG_UNICODE = "u"
    LRE_FLAG_STICKY = "y"

  LREFlags* = set[LREFlag]

proc toCInt*(flags: LREFlags): cint =
  cint(cast[uint8](flags))

proc toLREFlags*(flags: cint): LREFlags =
  cast[LREFlags](flags)

{.passc: "-I" & currentSourcePath().parentDir().}

{.push header: "qjs/libregexp.h", importc.}
proc lre_compile*(plen: var cint; error_msg: cstring; error_msg_size: cint;
  buf: cstring; buf_len: csize_t; re_flags: cint; opaque: pointer): ptr uint8

proc lre_exec*(capture: ptr ptr uint8; bc_buf, cbuf: ptr uint8;
  cindex, clen, cbuf_type: cint; opaque: pointer): cint

proc lre_get_alloc_count*(bc_buf: ptr uint8): cint
proc lre_get_capture_count*(bc_buf: ptr uint8): cint
proc lre_get_flags*(bc_buf: ptr uint8): cint

proc lre_is_space_non_ascii*(c: uint32): JS_BOOL

proc lre_is_space*(c: uint32): JS_BOOL

{.pop.} # header, importc
{.pop.} # raises
