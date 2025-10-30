{.push raises: [].}

import std/tables

import html/script
import monoucha/fromjs
import monoucha/jsopaque
import monoucha/jsutils
import monoucha/quickjs
import monoucha/tojs
import types/jsopt

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
    let next = promise.next
    promise.next = nil
    if next == nil:
      break
    promise = next

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
  let next = EmptyPromise()
  promise.cb = cb
  promise.next = next
  if promise.state == psFulfilled:
    promise.resolve()
  next

proc then*(promise: EmptyPromise; cb: (proc(): EmptyPromise {.raises: [].})):
    EmptyPromise {.discardable.} =
  let next = EmptyPromise()
  promise.then(proc() =
    let p2 = cb()
    if p2 != nil:
      p2.next = next
    if p2 == nil or p2.state == psFulfilled:
      next.resolve())
  return next

proc then*[T](promise: Promise[T]; cb: (proc(x: T) {.raises: [].})):
    EmptyPromise {.discardable.} =
  return promise.then(proc() = cb(promise.res))

proc then*[T](promise: EmptyPromise; cb: (proc(): Promise[T] {.raises: [].})):
    Promise[T] {.discardable.} =
  let next = Promise[T]()
  promise.then(proc() =
    let p2 = cb()
    if p2 != nil:
      if p2.state == psFulfilled:
        next.res = p2.res
      else:
        p2.next = next
        p2.cb = proc() =
          next.res = p2.res
    if p2 == nil or p2.state == psFulfilled:
      next.resolve())
  next

proc then*[T](promise: Promise[T];
    cb: (proc(x: T): EmptyPromise {.raises: [].})): EmptyPromise
    {.discardable.} =
  let next = EmptyPromise()
  promise.then(proc(x: T) =
    let p2 = cb(x)
    if p2 != nil:
      p2.then(proc() = next.resolve())
    else:
      next.resolve())
  next

proc then*[T](promise: EmptyPromise; cb: (proc(): T {.raises: [].})): Promise[T]
    {.discardable.} =
  let next = Promise[T]()
  promise.next = next
  if promise.state == psFulfilled:
    next.res = cb()
    next.resolve()
  else:
    promise.cb = proc() =
      next.res = cb()
  next

proc then*[T, U: not void](promise: Promise[T];
    cb: (proc(x: T): U {.raises: [].})): Promise[U] {.discardable.} =
  let next = Promise[U]()
  promise.next = next
  if promise.state == psFulfilled:
    next.res = cb(promise.res)
    promise.resolve()
  else:
    promise.cb = proc() =
      next.res = cb(promise.res)
  next

proc then*[T, U](promise: Promise[T];
    cb: (proc(x: T): Promise[U] {.raises: [].})): Promise[U] {.discardable.} =
  let next = Promise[U]()
  promise.then(proc(x: T) =
    let p2 = cb(x)
    if p2 != nil:
      p2.then(proc(y: U) =
        next.res = y
        next.resolve())
    else:
      next.resolve())
  next

proc all*(promises: seq[EmptyPromise]): EmptyPromise =
  let res = EmptyPromise()
  var u = 0u
  let L = uint(promises.len)
  for promise in promises:
    promise.then(proc() =
      inc u
      if u == L:
        res.resolve()
    )
  if promises.len == 0:
    res.resolve()
  res

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
    res: var Promise[seq[JSValueConst]]): FromJSResult =
  if not JS_IsObject(val):
    JS_ThrowTypeError(ctx, "value is not an object")
    return fjErr
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
      return fjErr
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
      return fjErr
    JS_FreeValue(ctx, val)
  JS_FreeValue(ctx, tmp)
  GC_ref(res)
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var EmptyPromise):
    FromJSResult =
  var res1: Promise[seq[JSValueConst]]
  ?ctx.fromJS(val, res1)
  let res2 = EmptyPromise()
  res1.then(proc(_: seq[JSValueConst]) =
    res2.resolve()
  )
  res = res2
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var Promise[JSValueConst]):
    FromJSResult =
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
  fjOk

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
      JS_FreeValue(ctx, ctx.callFree(resolve, JS_UNDEFINED))
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
