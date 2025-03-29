## JS Error compatibility.
##
## This API is strictly less efficient than its QJS counterpart, as it
## relies on additional heap allocation.  It only exists to make it
## easier to write interfaces that can be used both in Nim and QJS.
##
## To add your own custom errors, derive a new type from JS_CLASS_ERROR
## and set the `e` field to `jeCustom` when initializing it.  Typically
## you'd also add at least a `.jsfget` function for `message`.

{.push raises: [].}

import optshim

type
  JSError* = ref object of RootObj
    e*: JSErrorEnum
    message*: string

  JSErrorEnum* = enum
    # QuickJS internal errors
    jeEvalError = "EvalError"
    jeRangeError = "RangeError"
    jeReferenceError = "ReferenceError"
    jeSyntaxError = "SyntaxError"
    jeTypeError = "TypeError"
    jeURIError = "URIError"
    jeInternalError = "InternalError"
    jeAggregateError = "AggregateError"
    # Custom errors
    jeCustom = "CustomError"

  JSResult*[T] = Result[T, JSError]

proc newEvalError*(message: sink string): JSError =
  return JSError(e: jeEvalError, message: message)

proc newRangeError*(message: sink string): JSError =
  return JSError(e: jeRangeError, message: message)

proc newReferenceError*(message: sink string): JSError =
  return JSError(e: jeReferenceError, message: message)

proc newSyntaxError*(message: sink string): JSError =
  return JSError(e: jeSyntaxError, message: message)

proc newTypeError*(message: sink string): JSError =
  return JSError(e: jeTypeError, message: message)

proc newURIError*(message: sink string): JSError =
  return JSError(e: jeURIError, message: message)

proc newInternalError*(message: sink string): JSError =
  return JSError(e: jeInternalError, message: message)

proc newAggregateError*(message: sink string): JSError =
  return JSError(e: jeAggregateError, message: message)

template errEvalError*(message: sink string): untyped =
  err(newEvalError(message))

template errRangeError*(message: sink string): untyped =
  err(newRangeError(message))

template errReferenceError*(message: sink string): untyped =
  err(newReferenceError(message))

template errSyntaxError*(message: sink string): untyped =
  err(newSyntaxError(message))

template errTypeError*(message: sink string): untyped =
  err(newTypeError(message))

template errURIError*(message: sink string): untyped =
  err(newURIError(message))

template errInternalError*(message: sink string): untyped =
  err(newInternalError(message))

template errAggregateError*(message: sink string): untyped =
  err(newAggregateError(message))

{.pop.} # raises
