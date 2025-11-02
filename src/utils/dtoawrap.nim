import monoucha/dtoa

# n: start pointer -> end pointer
# dtoa assumes NUL-termination, so s must be a cstring.
# returns NaN if s doesn't start with a number.
proc parseFloat64*(s: cstring; n: var int): float32 =
  let cs = cast[cstringConst](unsafeAddr s[n])
  var tmp: JSATODTempMem
  var pnext = cs
  let res = js_atod(cs, addr pnext, 10, 0, tmp)
  n += cast[int](cast[uint](pnext) - cast[uint](cs))
  float64(res)

proc parseFloat64*(s: cstring): float64 =
  var i = 0
  let res = parseFloat64(s, i)
  if i < s.len:
    return NaN
  return res

proc addDouble*(s: var string; d: float64) =
  let d = cdouble(d)
  let m = js_dtoa_max_len(d, 10, 0, JS_DTOA_FORMAT_FREE)
  let olen = s.len
  # Note: this relies on Nim strings having a NUL term by default (because
  # js_dtoa writes one).
  s.setLen(olen + int(m))
  var tmp: JSDTOATempMem
  let n = js_dtoa(cast[cstring](addr s[olen]), d, 10, 0, JS_DTOA_FORMAT_FREE,
    tmp)
  s.setLen(olen + int(n))

proc dtoa*(d: float64): string =
  result = ""
  result.addDouble(d)
