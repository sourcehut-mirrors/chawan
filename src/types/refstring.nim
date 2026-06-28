{.push raises: [].}

import monoucha/fromjs
import monoucha/jstypes
import monoucha/quickjs
import monoucha/tojs

type RefString* = ref object
  s*: string

proc newRefString*(s: sink string): RefString =
  RefString(s: s)

proc newRefString*(ds: DOMString): RefString =
  RefString(s: $ds)

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

proc fromJS*(ctx: JSContext; val: JSValueConst; rs: var RefString):
    FromJSResult =
  rs = RefString()
  ctx.fromJS(val, rs.s)

{.pop.} # raises: []
