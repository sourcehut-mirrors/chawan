{.push raises: [].}

import monoucha/fromjs
import monoucha/quickjs
import monoucha/tojs
import types/opt

proc toJS*[T](ctx: JSContext; opt: Opt[T]): JSValue
proc toJSNew*[T](ctx: JSContext; opt: Opt[T]; ctor: JSValueConst): JSValue

template `?`*(res: FromJSResult) =
  if res == fjErr:
    when result is FromJSResult:
      return fjErr
    elif result is JSValue or result is JSValueConst:
      return JS_EXCEPTION
    else:
      return err()

template `?`*(res: JSClassID) =
  if res == JS_INVALID_CLASS_ID:
    when result is JSClassID:
      return JS_INVALID_CLASS_ID
    else:
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
