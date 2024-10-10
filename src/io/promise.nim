import std/tables

import monoucha/quickjs
import monoucha/javascript
import monoucha/jsutils
import monoucha/jsopaque
import monoucha/tojs
import types/opt

type
  PromiseState = enum
    psPending, psFulfilled, psRejected

  EmptyPromise* = ref object of RootObj
    cb: (proc())
    next: EmptyPromise
    state*: PromiseState

  Promise*[T] = ref object of EmptyPromise
    res*: T

proc resolve*(promise: EmptyPromise) =
  var promise = promise
  while true:
    if promise.cb != nil:
      promise.cb()
    promise.cb = nil
    promise.state = psFulfilled
    promise = promise.next
    if promise == nil:
      break
    promise.next = nil

proc resolve*[T](promise: Promise[T]; res: T) =
  promise.res = res
  promise.resolve()

proc newResolvedPromise*(): EmptyPromise =
  let res = EmptyPromise()
  res.resolve()
  return res

proc newResolvedPromise*[T](x: T): Promise[T] =
  let res = Promise[T]()
  res.resolve(x)
  return res

proc then*(promise: EmptyPromise; cb: (proc())): EmptyPromise {.discardable.} =
  promise.cb = cb
  promise.next = EmptyPromise()
  if promise.state == psFulfilled:
    promise.resolve()
  return promise.next

proc then*(promise: EmptyPromise; cb: (proc(): EmptyPromise)): EmptyPromise
    {.discardable.} =
  let next = EmptyPromise()
  promise.then(proc() =
    var p2 = cb()
    if p2 != nil:
      p2.then(proc() =
        next.resolve())
    else:
      next.resolve())
  return next

proc then*[T](promise: Promise[T]; cb: (proc(x: T))): EmptyPromise
    {.discardable.} =
  return promise.then(proc() = cb(promise.res))

proc then*[T](promise: EmptyPromise; cb: (proc(): Promise[T])): Promise[T]
    {.discardable.} =
  let next = Promise[T]()
  promise.then(proc() =
    var p2 = cb()
    if p2 != nil:
      p2.then(proc(x: T) =
        next.res = x
        next.resolve())
    else:
      next.resolve())
  return next

proc then*[T](promise: Promise[T]; cb: (proc(x: T): EmptyPromise)): EmptyPromise
    {.discardable.} =
  let next = EmptyPromise()
  promise.then(proc(x: T) =
    let p2 = cb(x)
    if p2 != nil:
      p2.then(proc() =
        next.resolve())
    else:
      next.resolve())
  return next

proc then*[T](promise: EmptyPromise; cb: (proc(): T)): Promise[T]
    {.discardable.} =
  let next = Promise[T]()
  promise.then(proc() =
    next.res = cb()
    next.resolve())
  return next

proc then*[T, U](promise: Promise[T]; cb: (proc(x: T): U)): Promise[U]
    {.discardable.} =
  let next = Promise[U]()
  promise.then(proc(x: T) =
    next.res = cb(x)
    next.resolve())
  return next

proc then*[T, U](promise: Promise[T]; cb: (proc(x: T): Promise[U])): Promise[U]
    {.discardable.} =
  let next = Promise[U]()
  promise.then(proc(x: T) =
    let p2 = cb(x)
    if p2 != nil:
      p2.then(proc(y: U) =
        next.res = y
        next.resolve())
    else:
      next.resolve())
  return next

proc then*[T, U](promise: Promise[T]; cb: (proc(x: T): Opt[Promise[U]])):
    Promise[Opt[U]] {.discardable.} =
  let next = Promise[Opt[U]]()
  promise.then(proc(x: T) =
    let p2 = cb(x)
    if p2.isSome:
      p2.get.then(proc(y: U) =
        next.res = opt(y)
        next.resolve())
    else:
      next.resolve())
  return next

proc all*(promises: seq[EmptyPromise]): EmptyPromise =
  let res = EmptyPromise()
  var i = 0
  for promise in promises:
    promise.then(proc() =
      inc i
      if i == promises.len:
        res.resolve())
  if promises.len == 0:
    res.resolve()
  return res

# Promise is converted to a JS promise which will be resolved when the Nim
# promise is resolved.

proc promiseThenCallback(ctx: JSContext; this_val: JSValue; argc: cint;
    argv: ptr UncheckedArray[JSValue]; magic: cint;
    func_data: ptr UncheckedArray[JSValue]): JSValue {.cdecl.} =
  let fun = func_data[0]
  let op = JS_GetOpaque(fun, JS_GetClassID(fun))
  if op != nil:
    let p = cast[EmptyPromise](op)
    p.resolve()
    GC_unref(p)
    JS_SetOpaque(fun, nil)
  return JS_UNDEFINED

proc fromJS*(ctx: JSContext; val: JSValue; res: var EmptyPromise): Opt[void] =
  if not JS_IsObject(val):
    JS_ThrowTypeError(ctx, "value is not an object")
    return err()
  res = EmptyPromise()
  GC_ref(res)
  let tmp = JS_NewObject(ctx)
  JS_SetOpaque(tmp, cast[pointer](res))
  let fun = JS_NewCFunctionData(ctx, promiseThenCallback, 0, 0, 1,
    tmp.toJSValueArray())
  JS_FreeValue(ctx, tmp)
  let val = JS_Invoke(ctx, val, ctx.getOpaque().strRefs[jstThen], 1,
    fun.toJSValueArray())
  JS_FreeValue(ctx, fun)
  if JS_IsException(val):
    JS_FreeValue(ctx, val)
    GC_unref(res)
    res = nil
    return err()
  JS_FreeValue(ctx, val)
  return ok()

proc toJS*(ctx: JSContext; promise: EmptyPromise): JSValue =
  if promise == nil:
    return JS_NULL
  var resolvingFuncs: array[2, JSValue]
  let jsPromise = JS_NewPromiseCapability(ctx, resolvingFuncs.toJSValueArray())
  if JS_IsException(jsPromise):
    return JS_EXCEPTION
  promise.then(proc() =
    let res = JS_Call(ctx, resolvingFuncs[0], JS_UNDEFINED, 0, nil)
    JS_FreeValue(ctx, res)
    JS_FreeValue(ctx, resolvingFuncs[0])
    JS_FreeValue(ctx, resolvingFuncs[1]))
  return jsPromise

proc toJS*[T](ctx: JSContext; promise: Promise[T]): JSValue =
  if promise == nil:
    return JS_NULL
  var resolvingFuncs: array[2, JSValue]
  let jsPromise = JS_NewPromiseCapability(ctx, resolvingFuncs.toJSValueArray())
  if JS_IsException(jsPromise):
    return JS_EXCEPTION
  promise.then(proc(x: T) =
    let x = toJS(ctx, x)
    let res = JS_Call(ctx, resolvingFuncs[0], JS_UNDEFINED, 1,
      x.toJSValueArray())
    JS_FreeValue(ctx, res)
    JS_FreeValue(ctx, x)
    JS_FreeValue(ctx, resolvingFuncs[0])
    JS_FreeValue(ctx, resolvingFuncs[1]))
  return jsPromise

proc toJS*[T, E](ctx: JSContext; promise: Promise[Result[T, E]]): JSValue =
  if promise == nil:
    return JS_NULL
  var resolvingFuncs: array[2, JSValue]
  let jsPromise = JS_NewPromiseCapability(ctx, resolvingFuncs.toJSValueArray())
  if JS_IsException(jsPromise):
    return JS_EXCEPTION
  promise.then(proc(x: Result[T, E]) =
    if x.isSome:
      let x = when T is void:
        JS_UNDEFINED
      else:
        toJS(ctx, x.get)
      let res = JS_Call(ctx, resolvingFuncs[0], JS_UNDEFINED, 1,
        x.toJSValueArray())
      JS_FreeValue(ctx, res)
      JS_FreeValue(ctx, x)
    else: # err
      let x = when E is void:
        JS_UNDEFINED
      else:
        toJS(ctx, x.error)
      let res = JS_Call(ctx, resolvingFuncs[1], JS_UNDEFINED, 1, x.toJSValueArray())
      JS_FreeValue(ctx, res)
      JS_FreeValue(ctx, x)
    JS_FreeValue(ctx, resolvingFuncs[0])
    JS_FreeValue(ctx, resolvingFuncs[1]))
  return jsPromise
