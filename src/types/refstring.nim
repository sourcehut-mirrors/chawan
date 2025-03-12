import monoucha/fromjs
import monoucha/javascript
import monoucha/tojs
import types/opt

type RefString* = ref object
  s*: string

proc newRefString*(s: sink string): RefString =
  return RefString(s: s)

converter `$`*(rs: RefString): lent string =
  rs.s

template `&=`*(rs: var RefString; ss: string) =
  rs.s &= ss

proc toJS*(ctx: JSContext; rs: RefString): JSValue =
  return ctx.toJS($rs)

proc fromJS*(ctx: JSContext; val: JSValueConst; rs: out RefString): Opt[void] =
  rs = RefString()
  if ctx.fromJS(val, rs.s).isNone:
    rs = nil
    return err()
  return ok()
