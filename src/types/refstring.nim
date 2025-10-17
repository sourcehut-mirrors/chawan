import monoucha/fromjs
import monoucha/javascript
import monoucha/tojs
import types/opt

type RefString* = ref object
  s*: string

proc newRefString*(s: sink string): RefString =
  return RefString(s: s)

proc `$`*(rs: RefString): lent string =
  rs.s

template `&=`*(rs: var RefString; ss: string) =
  rs.s &= ss

template `[]`*(rs: RefString; i: int): char =
  rs.s[i]

proc len*(rs: RefString): int =
  rs.s.len

proc toJS*(ctx: JSContext; rs: RefString): JSValue =
  return ctx.toJS($rs)

proc fromJS*(ctx: JSContext; val: JSValueConst; rs: var RefString): Opt[void] =
  rs = RefString()
  ?ctx.fromJS(val, rs.s)
  ok()
