{.push raises: [].}

import std/tables

import html/script
import monoucha/javascript
import monoucha/jsopaque
import monoucha/jsutils
import monoucha/quickjs
import monoucha/tojs
import types/opt

type
  PromiseState = enum
    psPending, psFulfilled

  EmptyPromise* = ref object of RootObj
    cb: (proc() {.raises: [].})
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

proc then*(promise: EmptyPromise; cb: (proc() {.raises: [].})): EmptyPromise
    {.discardable.} =
  promise.cb = cb
  promise.next = EmptyPromise()
  if promise.state == psFulfilled:
    promise.resolve()
  return promise.next

proc then*(promise: EmptyPromise; cb: (proc(): EmptyPromise {.raises: [].})):
    EmptyPromise {.discardable.} =
  let next = EmptyPromise()
  promise.then(proc() =
    var p2 = cb()
    if p2 != nil:
      p2.then(proc() =
        next.resolve())
    else:
      next.resolve())
  return next

proc then*[T](promise: Promise[T]; cb: (proc(x: T) {.raises: [].})):
    EmptyPromise {.discardable.} =
  return promise.then(proc() = cb(promise.res))

proc then*[T](promise: EmptyPromise; cb: (proc(): Promise[T] {.raises: [].})):
    Promise[T] {.discardable.} =
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

proc then*[T](promise: Promise[T];
    cb: (proc(x: T): EmptyPromise {.raises: [].})): EmptyPromise
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

proc then*[T](promise: EmptyPromise; cb: (proc(): T {.raises: [].})): Promise[T]
    {.discardable.} =
  let next = Promise[T]()
  promise.then(proc() =
    next.res = cb()
    next.resolve())
  return next

proc then*[T, U](promise: Promise[T]; cb: (proc(x: T): U {.raises: [].})):
    Promise[U] {.discardable.} =
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
proc promiseThenCallback(ctx: JSContext; this: JSValueConst; argc: cint;
    argv: JSValueConstArray; magic: cint; funcData: JSValueConstArray): JSValue
    {.cdecl.} =
  let fun = funcData[0]
  let op = JS_GetOpaque(fun, JS_GetClassID(fun))
  if op != nil:
    let p = cast[Promise[seq[JSValueConst]]](op)
    p.resolve(@(argv.toOpenArray(0, argc - 1)))
    GC_unref(p)
    JS_SetOpaque(fun, nil)
  return JS_UNDEFINED

proc promiseCatchCallback(ctx: JSContext; this: JSValueConst; argc: cint;
    argv: JSValueConstArray; magic: cint; funcData: JSValueConstArray): JSValue
    {.cdecl.} =
  let fun = funcData[0]
  let op = JS_GetOpaque(fun, JS_GetClassID(fun))
  if op != nil and argc > 0:
    let vals = @[JSValueConst(JS_Throw(ctx, JS_DupValue(ctx, argv[0])))]
    let p = cast[Promise[seq[JSValueConst]]](op)
    p.resolve(vals)
    GC_unref(p)
    JS_SetOpaque(fun, nil)
  return JS_UNDEFINED

proc fromJS*(ctx: JSContext; val: JSValueConst;
    res: var Promise[seq[JSValueConst]]): Opt[void] =
  if not JS_IsObject(val):
    JS_ThrowTypeError(ctx, "value is not an object")
    return err()
  res = Promise[seq[JSValueConst]]()
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

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var EmptyPromise):
    Opt[void] =
  var res1: Promise[seq[JSValueConst]]
  ?ctx.fromJS(val, res1)
  let res2 = EmptyPromise()
  res1.then(proc(_: seq[JSValueConst]) =
    res2.resolve()
  )
  res = res2
  return ok()

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var Promise[JSValueConst]):
    Opt[void] =
  var res1: Promise[seq[JSValueConst]]
  ?ctx.fromJS(val, res1)
  let res2 = Promise[JSValueConst]()
  res1.then(proc(s: seq[JSValueConst]) =
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
  JS_FreeValue(ctx, resolvingFuncs[1])
  let nthen = ctx.storeJS(resolvingFuncs[0])
  promise.then(proc() =
    let resolve = ctx.fetchJS(nthen)
    if not JS_IsUninitialized(resolve):
      JS_FreeValue(ctx, JS_CallFree(ctx, resolve, JS_UNDEFINED, 0, nil))
  )
  return jsPromise

proc toJS*[T](ctx: JSContext; promise: Promise[T]): JSValue =
  if promise == nil:
    return JS_NULL
  var resolvingFuncs {.noinit.}: array[2, JSValue]
  let jsPromise = JS_NewPromiseCapability(ctx, resolvingFuncs.toJSValueArray())
  if JS_IsException(jsPromise):
    return JS_EXCEPTION
  let nthen = ctx.storeJS(resolvingFuncs[0])
  let ncatch = ctx.storeJS(resolvingFuncs[1])
  promise.then(proc(ox: T) =
    let x = ctx.toJS(ox)
    let resolve = ctx.fetchJS(nthen)
    let catch = ctx.fetchJS(ncatch)
    if not JS_IsException(x):
      if not JS_IsUninitialized(resolve):
        JS_FreeValue(ctx, JS_Call(ctx, resolve, JS_UNDEFINED, 1,
          x.toJSValueArray()))
    else:
      if not JS_IsUninitialized(catch):
        let ex = JS_GetException(ctx)
        JS_FreeValue(ctx, JS_Call(ctx, catch, JS_UNDEFINED, 1,
          ex.toJSValueArray()))
        JS_FreeValue(ctx, ex)
    JS_FreeValue(ctx, x)
    JS_FreeValue(ctx, resolve)
    JS_FreeValue(ctx, catch)
  )
  return jsPromise

{.pop.} # raises: []
