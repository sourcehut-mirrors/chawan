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

type JSNullRef*[T: JSRef] = distinct T

proc toJS*[T: JSRef](ctx: JSContext; r: JSNullRef[T]): JSValue =
  ctx.toJS(T(r))

proc fromJS*[T: JSRef](ctx: JSContext; val: JSValueConst;
    res: var JSNullRef[T]): JSCode =
  mixin fromJS
  if JS_IsNull(val):
    res = JSNullRef[T](nil)
  else:
    var x: T
    if ctx.fromJS(val, x).isErr:
      return fjErr
    res = JSNullRef[T](x)
  fjOk

template get*[T: JSRef](r: JSNullRef[T]): T =
  T(r)

template jsNull*[T: JSRef](r: T): JSNullRef[T] =
  JSNullRef[T](r)

template jsNull*[T: JSRef](r: typedesc[T]): JSNullRef[T] =
  JSNullRef[T](nil)

{.pop.} # raises: []
