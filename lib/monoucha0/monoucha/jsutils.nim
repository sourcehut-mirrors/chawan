{.push raises: [].}

import quickjs

template toJSValueArray*(a: openArray[JSValue]): JSValueArray =
  if a.len > 0:
    cast[ptr UncheckedArray[JSValue]](unsafeAddr a[0])
  else:
    nil

template toJSValueConstArray*(a: openArray[JSValue]): JSValueConstArray =
  cast[JSValueConstArray](a.toJSValueArray())

template toJSValueConstArray*(a: openArray[JSValueConst]): JSValueConstArray =
  if a.len > 0:
    cast[ptr UncheckedArray[JSValueConst]](unsafeAddr a[0])
  else:
    nil

template toJSValueConstOpenArray*(a: openArray[JSValue]):
    openArray[JSValueConst] =
  a.toJSValueConstArray().toOpenArray(0, a.high)

# Warning: this must be a template, because we're taking the address of
# the passed value, and Nim is pass-by-value.
template toJSValueArray*(a: JSValue): JSValueArray =
  cast[JSValueArray](unsafeAddr a)

template toJSValueConstArray*(a: JSValueConst): JSValueConstArray =
  cast[JSValueConstArray](unsafeAddr a)

proc JS_CallFree*(ctx: JSContext; funcObj: JSValue; this: JSValueConst;
    argc: cint; argv: JSValueConstArray): JSValue =
  result = JS_Call(ctx, funcObj, this, argc, argv)
  JS_FreeValue(ctx, funcObj)

# Free JSValue, and return JS_EXCEPTION if it's an exception (or undefined
# otherwise).
proc toUndefined*(ctx: JSContext; val: JSValue): JSValue =
  if JS_IsException(val):
    return JS_EXCEPTION
  JS_FreeValue(ctx, val)
  return JS_UNDEFINED

{.pop.} # raises
