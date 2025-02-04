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
proc promiseThenCallback(ctx: JSContext; this: JSValue; argc: cint;
    argv: ptr UncheckedArray[JSValue]; magic: cint;
    funcData: ptr UncheckedArray[JSValue]): JSValue {.cdecl.} =
  let fun = funcData[0]
  let op = JS_GetOpaque(fun, JS_GetClassID(fun))
  if op != nil:
    var vals: seq[JSValue] = @[]
    for it in argv.toOpenArray(0, argc - 1):
      vals.add(it)
    let p = cast[Promise[seq[JSValue]]](op)
    p.resolve(vals)
    GC_unref(p)
    JS_SetOpaque(fun, nil)
  return JS_UNDEFINED

proc promiseCatchCallback(ctx: JSContext; this: JSValue; argc: cint;
    argv: ptr UncheckedArray[JSValue]; magic: cint;
    funcData: ptr UncheckedArray[JSValue]): JSValue {.cdecl.} =
  let fun = funcData[0]
  let op = JS_GetOpaque(fun, JS_GetClassID(fun))
  if op != nil and argc > 0:
    let vals = @[JS_Throw(ctx, argv[0])]
    let p = cast[Promise[seq[JSValue]]](op)
    p.resolve(vals)
    GC_unref(p)
    JS_SetOpaque(fun, nil)
  return JS_UNDEFINED

proc fromJS*(ctx: JSContext; val: JSValue; res: out Promise[seq[JSValue]]):
    Opt[void] =
  if not JS_IsObject(val):
    JS_ThrowTypeError(ctx, "value is not an object")
    res = nil
    return err()
  res = Promise[seq[JSValue]]()
  let tmp = JS_NewObject(ctx)
  JS_SetOpaque(tmp, cast[pointer](res))
  block then:
    let fun = JS_NewCFunctionData(ctx, promiseThenCallback, 0, 0, 1,
      tmp.toJSValueArray())
    let val = JS_Invoke(ctx, val, ctx.getOpaque().strRefs[jstThen], 1,
      fun.toJSValueArray())
    JS_FreeValue(ctx, fun)
    if JS_IsException(val):
      JS_FreeValue(ctx, tmp)
      res = nil
      return err()
    JS_FreeValue(ctx, val)
  block catch:
    let fun = JS_NewCFunctionData(ctx, promiseCatchCallback, 0, 0, 1,
      tmp.toJSValueArray())
    let val = JS_Invoke(ctx, val, ctx.getOpaque().strRefs[jstCatch], 1,
      fun.toJSValueArray())
    JS_FreeValue(ctx, fun)
    if JS_IsException(val):
      JS_FreeValue(ctx, tmp)
      res = nil
      return err()
    JS_FreeValue(ctx, val)
  JS_FreeValue(ctx, tmp)
  GC_ref(res)
  return ok()

proc fromJS*(ctx: JSContext; val: JSValue; res: out EmptyPromise): Opt[void] =
  var res1: Promise[seq[JSValue]]
  ?ctx.fromJS(val, res1)
  let res2 = EmptyPromise()
  res1.then(proc(_: seq[JSValue]) =
    res2.resolve()
  )
  res = res2
  return ok()

proc fromJS*(ctx: JSContext; val: JSValue; res: out Promise[JSValue]):
    Opt[void] =
  var res1: Promise[seq[JSValue]]
  ?ctx.fromJS(val, res1)
  let res2 = Promise[JSValue]()
  res1.then(proc(s: seq[JSValue]) =
    if s.len > 0:
      res2.resolve(s[0])
    else:
      res2.resolve(JS_UNDEFINED)
  )
  res = res2
  return ok()

proc toJS*(ctx: JSContext; promise: EmptyPromise): JSValue =
  if promise == nil:
    return JS_NULL
  var resolvingFuncs {.noinit.}: array[2, JSValue]
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
  var resolvingFuncs {.noinit.}: array[2, JSValue]
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
  var resolvingFuncs {.noinit.}: array[2, JSValue]
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
