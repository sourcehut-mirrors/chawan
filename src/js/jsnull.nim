## Nullable JS types.  Use this if you want to take a ref object parameter
## that can be nil.
##
## For nullable strings, use StrNil or DOMStringNil instead.

{.push raises: [].}

import js/fromjs
import js/jsref
import js/jsutils
import js/quickjs
import js/tojs

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

proc `==`*[T](r: JSNullRef[T]; t: typeof(nil)): bool =
  cast[pointer](r) == nil

{.pop.} # raises: []
