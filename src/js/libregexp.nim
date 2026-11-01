{.push raises: [].}

import utils/chaos

{.used.}
# used so that we can import it from quickjs.nim

import cutils
import libunicode

const CFLAGS = "-fwrapv"

{.compile("../../lib/quickjs/libregexp.c", CFLAGS).}

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

const lreheader = "../../lib/quickjs/libregexp.h"

type JSLREStackCheckFunc =
  proc(opaque: pointer; alloca_size: csize_t): cint {.cdecl.}

type JSLREReallocFunc* =
  proc(opaque, p: pointer; size: csize_t): pointer {.cdecl.}

type JSLREExecFunctions* {.importc, header: lreheader,
    completeStruct.} = object
  lre_realloc*: JSLREReallocFunc
  lre_check_timeout*: proc(opaque: pointer): cint {.cdecl.}

{.push header: "../../lib/quickjs/libregexp.h", importc.}
proc lre_compile*(plen: var cint; error_msg: cstring; error_msg_size: cint;
  buf: cstring; buf_len: csize_t; re_flags: cint;
  lre_realloc: JSLREReallocFunc; lre_check_stack_overflow: JSLREStackCheckFunc;
  opaque: pointer): ptr uint8

proc lre_exec*(capture: ptr ptr uint8; bc_buf, cbuf: ptr uint8;
  cindex, clen, cbuf_type: cint; funcs: ptr JSLREExecFunctions;
  opaque: pointer): cint

proc lre_get_alloc_count*(bc_buf: ptr uint8): cint
proc lre_get_capture_count*(bc_buf: ptr uint8): cint
proc lre_get_flags*(bc_buf: ptr uint8): cint

proc lre_is_space_non_ascii*(c: uint32): JS_BOOL

proc lre_is_space*(c: uint32): JS_BOOL

{.pop.} # header, importc
{.pop.} # raises
