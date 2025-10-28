{.push raises: [].}

from std/os import parentDir

import cutils

import constcharp
export constcharp

{.used.}

when not compileOption("threads"):
  const CFLAGS = "-fwrapv -DMNC_NO_THREADS"
else:
  const CFLAGS = "-fwrapv"

{.compile("qjs/dtoa.c", CFLAGS).}

{.passc: "-I" & currentSourcePath().parentDir().}

{.push header: "qjs/dtoa.h", importc.}
# maximum number of digits for fixed and frac formats
const JS_DTOA_MAX_DIGITS* = 101

# radix != 10 is only supported with flags = JS_DTOA_FORMAT_FREE
# use as many digits as necessary
const JS_DTOA_FORMAT_FREE* = (0 shl 0)
# use n_digits significant digits (1 <= n_digits <= JS_DTOA_MAX_DIGITS)
const JS_DTOA_FORMAT_FIXED* = (1 shl 0)
# force fractional format: [-]dd.dd with n_digits fractional digits.
#  0 <= n_digits <= JS_DTOA_MAX_DIGITS
const JS_DTOA_FORMAT_FRAC* = (2 shl 0)
const JS_DTOA_FORMAT_MASK* = (3 shl 0)

# select exponential notation either in fixed or free format
const JS_DTOA_EXP_AUTO* = (0 shl 2)
const JS_DTOA_EXP_ENABLED* = (1 shl 2)
const JS_DTOA_EXP_DISABLED* = (2 shl 2)
const JS_DTOA_EXP_MASK* = (3 shl 2)

const JS_DTOA_MINUS_ZERO* = (1 shl 4) # show the minus sign for -0

# only accepts integers (no dot, no exponent)
const JS_ATOD_INT_ONLY* = (1 shl 0)
# accept Oo and Ob prefixes in addition to 0x prefix if radix = 0
const JS_ATOD_ACCEPT_BIN_OCT* = (1 shl 1)
# accept O prefix as octal if radix == 0 and properly formed (Annex B)
const JS_ATOD_ACCEPT_LEGACY_OCTAL* = (1 shl 2)
# accept _ between digits as a digit separator
const JS_ATOD_ACCEPT_UNDERSCORES* = (1 shl 3)

type
  JSDTOATempMem* {.importc, header: "qjs/dtoa.h".} = object
    mem*: array[37, uint64]

  JSATODTempMem* {.importc, header: "qjs/dtoa.h".} = object
    mem*: array[27, uint64]

# return a maximum bound of the string length
proc js_dtoa_max_len*(d: cdouble; radix, n_digits, flags: cint): cint
# return the string length
proc js_dtoa*(buf: cstring; d: cdouble; radix, n_digits, flags: cint;
  tmp_mem: ptr JSDTOATempMem): cint
proc js_atod*(str: cstringConst; pnext: ptr cstringConst; radix, flags: cint;
  tmp_mem: ptr JSATODTempMem): cdouble

# additional exported functions
proc u32toa*(buf: cstring; n: uint32): csize_t
proc i32toa*(buf: cstring; n: int32): csize_t
proc u64toa*(buf: cstring; n: uint64): csize_t
proc i64toa*(buf: cstring; n: int64): csize_t
proc u64toa_radix*(buf: cstring; n: uint64; radix: cuint): csize_t
proc i64toa_radix*(buf: cstring; n: int64; radix: cuint): csize_t

{.pop.} # header, importc
{.pop.} # raises
