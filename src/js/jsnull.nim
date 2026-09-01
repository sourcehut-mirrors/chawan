## Converts `Option` from `std/options` into nullable JS types.
## Use this if you want to return either a string or take a ref object
## parameter that can be nil.

{.push raises: [].}

import std/options

import js/fromjs
import js/jsref
import js/jsutils
import js/quickjs
import js/tojs

proc toJS*[T](ctx: JSContext; opt: Option[T]): JSValue =
  if opt.isSome:
    return ctx.toJS(opt.get)
  return JS_NULL

proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var Option[T]):
    JSCode =
  mixin fromJS
  if JS_IsNull(val):
    res = none(T)
  else:
    var x: T
    if ctx.fromJS(val, x).isErr:
      return fjErr
    res = option(move(x))
  fjOk

type JSNullRef*[T] = distinct JSRef[T]

proc toJS*[T](ctx: JSContext; r: JSNullRef[T]): JSValue =
  ctx.toJS(JSRef[T](r))

proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var JSNullRef[T]):
    JSCode =
  mixin fromJS
  if JS_IsNull(val):
    res = JSNullRef[T](nil)
  else:
    var x: JSRef[T]
    if ctx.fromJS(val, x).isErr:
      return fjErr
    res = JSNullRef[T](x)
  fjOk

template get*[T](r: JSNullRef[T]): JSRef[T] =
  JSRef[T](r)

template jsNull*[T](r: JSRef[T]): JSNullRef[T] =
  JSNullRef[T](r)

template jsNull*[T](r: typedesc[JSRef[T]]): JSNullRef[T] =
  JSNullRef[T](nil)

{.pop.} # raises: []
