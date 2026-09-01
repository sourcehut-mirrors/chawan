{.push raises: [].}

import js/fromjs
import js/jsutils
import js/quickjs
import js/tojs
import types/opt

proc toJS*[T](ctx: JSContext; opt: Opt[T]): JSValue
proc toJSNew*[T](ctx: JSContext; opt: Opt[T]; ctor: JSValueConst): JSValue

template err*(t: typedesc[JSValue]): JSValue =
  JS_EXCEPTION

template ok*(t: typedesc[JSCode]): JSCode =
  fjOk

template err*(t: typedesc[JSCode]): JSCode =
  fjErr

template `?`*(res: JSCode) =
  if res == fjErr:
    return err()

proc toJS*[T](ctx: JSContext; opt: Opt[T]): JSValue =
  if opt.isOk:
    when not (T is void):
      return ctx.toJS(opt.get)
    else:
      return JS_UNDEFINED
  else:
    return JS_EXCEPTION

proc toJSNew*[T](ctx: JSContext; opt: Opt[T]; ctor: JSValueConst): JSValue =
  if opt.isOk:
    when not (T is void):
      return ctx.toJSNew(opt.get, ctor)
    else:
      return JS_UNDEFINED
  else:
    return JS_EXCEPTION

proc fromJSGetProp*[T](ctx: JSContext; this: JSValueConst; name: cstring;
    res: var T): Opt[bool] =
  if JS_IsUndefined(this):
    return ok(false)
  let prop = JS_GetPropertyStr(ctx, this, name)
  if JS_IsException(prop):
    return err()
  if JS_IsUndefined(prop):
    return ok(false)
  ?ctx.fromJSFree(prop, res)
  ok(true)

{.pop.}
