{.push raises: [].}

import quickjs

template toJSValueArray*(a: openArray[JSValue]): JSValueArray =
  if a.len > 0:
    cast[ptr UncheckedArray[JSValue]](unsafeAddr a[0])
  else:
    nil

template toJSValueConstArray*(a: openArray[JSValue]): JSValueConstArray =
  cast[JSValueConstArray](a.toJSValueArray())

template toJSValueConstOpenArray*(a: openArray[JSValue]):
    openArray[JSValueConst] =
  a.toJSValueConstArray().toOpenArray(0, a.high)

# Warning: this must be a template, because we're taking the address of
# the passed value, and Nim is pass-by-value.
template toJSValueArray*(a: JSValue): JSValueArray =
  cast[JSValueArray](unsafeAddr a)

template toJSValueConstArray*(a: JSValueConst): JSValueConstArray =
  cast[JSValueConstArray](unsafeAddr a)

{.pop.} # raises
