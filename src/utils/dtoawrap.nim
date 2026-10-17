{.push raises: [].}

import js/constcharp
import js/dtoa
import utils/cowstr

# n: start pointer -> end pointer
# dtoa assumes NUL-termination, so s must be a cstring.
# returns NaN if s doesn't start with a number.
proc atod*(s: cstringConst; n: var int; radix = cint(10); flags = cint(0)):
    float64 =
  if s == nil:
    return NaN
  let cs = cast[cstringConst](unsafeAddr cstring(s)[n])
  var tmp: JSATODTempMem
  var pnext = cs
  let res = js_atod(cs, addr pnext, radix, flags, tmp)
  n += cast[int](cast[uint](pnext) - cast[uint](cs))
  float64(res)

proc parseFloat64*(s: Str): float64 =
  var i = 0
  let res = atod(s.toCStringConst(), i)
  if i < s.len:
    return NaN
  return res

proc addDouble*(s: var Growbuf; d: float64) =
  let d = cdouble(d)
  let m = js_dtoa_max_len(d, 10, 0, JS_DTOA_FORMAT_FREE)
  let olen = s.len
  s.setLenUninit(olen + int(m) + 1) # +1 for NUL-term
  var tmp: JSDTOATempMem
  let n = js_dtoa(cast[cstring](addr s[olen]), d, 10, 0, JS_DTOA_FORMAT_FREE,
    tmp)
  s.setLenUninit(olen + int(n))

proc dtoa*(d: float64): Str =
  var buf = initGrowbuf()
  buf.addDouble(d)
  buf.toStr()

{.pop.} # raises: []
