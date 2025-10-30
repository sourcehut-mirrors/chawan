## Converts `Option` from `std/options` into nullable JS types.
## Use this if you want to return either a string or take a ref object
## parameter that can be nil.
##
## If you want to return a value or an exception, see the `jserror` module
## instead.

{.push raises: [].}

import std/options

import fromjs
import quickjs
import tojs

proc toJS*(ctx: JSContext; opt: Option): JSValue =
  if opt.isSome:
    return ctx.toJS(opt.get)
  return JS_NULL

proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var Option[T]):
  FromJSResult

proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var Option[T]):
    FromJSResult =
  if JS_IsNull(val):
    res = none(T)
  else:
    var x: T
    if ctx.fromJS(val, x).isErr:
      return fjErr
    res = option(move(x))
  fjOk
