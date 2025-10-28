import std/math

import monoucha/dtoa

# n: start pointer -> end pointer
# dtoa assumes NUL-termination, so s must be a cstring.
# returns NaN if s doesn't start with a number.
proc parseFloat64*(s: cstring; n: var int): float32 =
  let cs = cast[cstringConst](unsafeAddr s[n])
  var tmp: JSATODTempMem
  var pnext = cs
  let res = js_atod(cs, addr pnext, 10, 0, addr tmp)
  n += cast[int](cast[uint](pnext) - cast[uint](cs))
  float64(res)

proc parseFloat64*(s: cstring): float64 =
  var i = 0
  let res = parseFloat64(s, i)
  if i < s.len:
    return NaN
  return res
