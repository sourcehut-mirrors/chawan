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
    # Chawan errors
    jeDOMException = "DOMException"

  JSResult*[T] = Result[T, JSError]

const QuickJSErrors* = [
  jeEvalError,
  jeRangeError,
  jeReferenceError,
  jeSyntaxError,
  jeTypeError,
  jeURIError,
  jeInternalError,
  jeAggregateError
]

proc newEvalError*(message: string): JSError =
  return JSError(e: jeEvalError, message: message)

proc newRangeError*(message: string): JSError =
  return JSError(e: jeRangeError, message: message)

proc newReferenceError*(message: string): JSError =
  return JSError(e: jeReferenceError, message: message)

proc newSyntaxError*(message: string): JSError =
  return JSError(e: jeSyntaxError, message: message)

proc newTypeError*(message: string): JSError =
  return JSError(e: jeTypeError, message: message)

proc newURIError*(message: string): JSError =
  return JSError(e: jeURIError, message: message)

proc newInternalError*(message: string): JSError =
  return JSError(e: jeInternalError, message: message)

proc newAggregateError*(message: string): JSError =
  return JSError(e: jeAggregateError, message: message)

template errTypeError*(message: string): untyped =
  err(newTypeError(message))
