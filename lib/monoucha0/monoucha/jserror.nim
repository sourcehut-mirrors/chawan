## JS Error compatibility using nim-results.  It uses Opt/Result for passing
## down exceptions received up in the chain.
##
## `Opt[T].err()` translates to JS_EXCEPTION, which signals to QJS that
## you have already thrown an exception (say, using `JS_ThrowTypeError`).
## `Result[T, JSError]` also translates to JS_EXCEPTION if error is nil, or
## throws the respective exception otherwise.  For example, you can
## `return err(newTypeError("wrong type"))` from such a proc instantiates
## a TypeError with the message "wrong type".
##
## There are also wrapper templates that are just shorthands for
## `err(new...Error("blah"))`.
##
## This API is strictly less efficient than its QJS counterpart, as it
## relies on additional heap allocation.  It only exists to make it
## easier to write interfaces that can be used both in Nim and QJS.
##
## An alternative with better performance is to set your proc's the return
## value to `JSValue`, take `JSContext` as the first parameter, and return
## e.g. `JS_ThrowTypeError` on exception or `ctx.toJS(val)` for your values.
## (You'll also want to `import monoucha/tojs` for the latter to work.)
##
## To add your own custom errors, derive a new type from JS_CLASS_ERROR
## and set the `e` field to `jeCustom` when initializing it.  Typically
## you'd also add at least a `.jsfget` function for `message`.
##
## If you want to return `null` instead of an exception, check the `jsnull`
## module.

{.push raises: [].}

import fromjs
import quickjs
import results
import tojs

type
  JSError* = ref object of RootObj
    e*: JSErrorEnum
    message*: string

  JSErrorEnum* = enum
    # QuickJS internal errors
    jeRangeError = "RangeError"
    jeReferenceError = "ReferenceError"
    jeSyntaxError = "SyntaxError"
    jeTypeError = "TypeError"
    jeInternalError = "InternalError"
    # Custom errors
    jeCustom = "CustomError"

  JSResult*[T] = Result[T, JSError]

proc toJS*[T, E](ctx: JSContext; opt: Result[T, E]): JSValue
proc toJS*(ctx: JSContext; err: JSError): JSValue
proc toJSNew*[T, E](ctx: JSContext; opt: Result[T, E]; ctor: JSValueConst):
  JSValue

proc newRangeError*(message: sink string): JSError =
  return JSError(e: jeRangeError, message: message)

proc newReferenceError*(message: sink string): JSError =
  return JSError(e: jeReferenceError, message: message)

proc newSyntaxError*(message: sink string): JSError =
  return JSError(e: jeSyntaxError, message: message)

proc newTypeError*(message: sink string): JSError =
  return JSError(e: jeTypeError, message: message)

proc newInternalError*(message: sink string): JSError =
  return JSError(e: jeInternalError, message: message)

template errRangeError*(message: sink string): untyped =
  err(newRangeError(message))

template errReferenceError*(message: sink string): untyped =
  err(newReferenceError(message))

template errSyntaxError*(message: sink string): untyped =
  err(newSyntaxError(message))

template errTypeError*(message: sink string): untyped =
  err(newTypeError(message))

template errInternalError*(message: sink string): untyped =
  err(newInternalError(message))

proc toJS*(ctx: JSContext; err: JSError): JSValue =
  if err == nil:
    return JS_EXCEPTION
  case err.e
  of jeCustom: return ctx.toJSRefObj(err)
  of jeRangeError: JS_ThrowRangeError(ctx, "%s", cstring(err.message))
  of jeReferenceError: JS_ThrowReferenceError(ctx, "%s", cstring(err.message))
  of jeSyntaxError: JS_ThrowSyntaxError(ctx, "%s", cstring(err.message))
  of jeTypeError: JS_ThrowTypeError(ctx, "%s", cstring(err.message))
  of jeInternalError: JS_ThrowInternalError(ctx, "%s", cstring(err.message))
  return JS_GetException(ctx)

proc toJS*[T, E](ctx: JSContext; opt: Result[T, E]): JSValue =
  if opt.isOk:
    when not (T is void):
      return ctx.toJS(opt.get)
    else:
      return JS_UNDEFINED
  else:
    when not (E is void):
      if opt.error != nil:
        return JS_Throw(ctx, ctx.toJS(opt.error))
    return JS_EXCEPTION

proc toJSNew*[T, E](ctx: JSContext; opt: Result[T, E]; ctor: JSValueConst):
    JSValue =
  if opt.isOk:
    when not (T is void):
      return ctx.toJSNew(opt.get, ctor)
    else:
      return JS_UNDEFINED
  else:
    when not (E is void):
      if opt.error != nil:
        return JS_Throw(ctx, ctx.toJS(opt.error))
    return JS_EXCEPTION

proc evalConvert*[T](ctx: JSContext; code: string; file = "<input>";
    flags = JS_EVAL_TYPE_GLOBAL): Result[T, string] =
  let val = ctx.eval(code, file, flags)
  var res: T
  if ctx.fromJSFree(val, res).isErr:
    # Exception when converting the value.
    return err(ctx.getExceptionMsg())
  # All ok; return the converted object.
  ok(res)

{.pop.} # raises
