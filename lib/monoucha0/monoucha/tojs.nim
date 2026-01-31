## Automatic conversion of Nim types to JavaScript types.
##
## Every conversion involves copying unless explicitly noted below.
##
## * Primitives are converted to their respective JavaScript counterparts.
## * seq is converted to a JS array. Note: this always copies the seq's
##   contents.
## * enum is converted to its stringifier's output.
## * JSValue is returned as-is, *without* a DupValue operation.
## * JSArrayBuffer, JSUint8Array are converted to a JS object without copying
##   their contents.
## * NarrowString is converted to a JS narrow string (with copying). For more
##   information on JS string handling, see js/jstypes.nim.
## * Finally, ref object is converted to a JS object whose opaque is the ref
##   object. (See below.)
##
## ref objects can be seamlessly converted to JS objects despite the fact
## that they are managed by two separate garbage collectors thanks to a patch
## in QJS:
##
## * Nim objects registered with registerType can be paired with one JS
##   object each.  This happens on-demand, whenever the Nim object has to be
##   converted into JS.
## * Once the conversion happened, the JS object will be kept alive until the
##   Nim object is destroyed, so that JS properties on the JS object are not
##   lost during a re-conversion.
## * Similarly, the Nim object is kept alive so long as the JS object is alive.
## * The patched in can_destroy hook is used to synchronize reference counts
##   of the two objects; this way, no memory leak occurs.

{.push raises: [].}

import std/macrocache
import std/tables
import std/typetraits

import jsopaque
import jstypes
import jsutils
import quickjs

# Convert Nim types to the corresponding JavaScript type.
proc toJS*(ctx: JSContext; s: string): JSValue
proc toJS*(ctx: JSContext; n: int64): JSValue
proc toJS*(ctx: JSContext; n: int32): JSValue
proc toJS*(ctx: JSContext; n: int): JSValue
proc toJS*(ctx: JSContext; n: uint16): JSValue
proc toJS*(ctx: JSContext; n: uint32): JSValue
proc toJS*(ctx: JSContext; n: uint64): JSValue
proc toJS*(ctx: JSContext; n: float64): JSValue
proc toJS*(ctx: JSContext; b: bool): JSValue
proc toJS*[T](ctx: JSContext; s: seq[T]): JSValue
proc toJS*[T](ctx: JSContext; s: set[T]): JSValue
proc toJS*[T: tuple](ctx: JSContext; t: T): JSValue
proc toJS*(ctx: JSContext; j: JSValue): JSValue
proc toJS*(ctx: JSContext; obj: ref object): JSValue
proc toJS*(ctx: JSContext; abuf: JSArrayBuffer): JSValue
proc toJS*(ctx: JSContext; u8a: JSTypedArray): JSValue
proc toJS*(ctx: JSContext; ns: NarrowString): JSValue
proc toJS*[T: JSDict](ctx: JSContext; dict: T): JSValue

# Same as toJS, but used in constructors. ctor contains the target prototype,
# used for subclassing from JS.
proc toJSNew*(ctx: JSContext; obj: ref object; ctor: JSValueConst): JSValue

proc newFunction*(ctx: JSContext; args: openArray[string]; body: string):
    JSValue =
  var paramList: seq[JSValue] = @[]
  for arg in args:
    paramList.add(ctx.toJS(arg))
  paramList.add(ctx.toJS(body))
  let fun = JS_CallConstructor(ctx, ctx.getOpaque().valRefs[jsvFunction],
    cint(paramList.len), paramList.toJSValueArray())
  for param in paramList:
    JS_FreeValue(ctx, param)
  return fun

proc toJS*(ctx: JSContext; s: cstring): JSValue =
  return JS_NewString(ctx, s)

proc toJS*(ctx: JSContext; s: string): JSValue =
  return JS_NewStringLen(ctx, cstring(s), csize_t(s.len))

proc toJS*(ctx: JSContext; n: int16): JSValue =
  return JS_NewInt32(ctx, int32(n))

proc toJS*(ctx: JSContext; n: int32): JSValue =
  return JS_NewInt32(ctx, n)

proc toJS*(ctx: JSContext; n: int64): JSValue =
  return JS_NewInt64(ctx, n)

proc toJS*(ctx: JSContext; n: int): JSValue =
  when sizeof(int) > 4:
    return ctx.toJS(int64(n))
  elif sizeof(int) > 2:
    return ctx.toJS(int32(n))
  else:
    return ctx.toJS(int16(n))

proc toJS*(ctx: JSContext; n: uint16): JSValue =
  return JS_NewUint32(ctx, uint32(n))

proc toJS*(ctx: JSContext; n: uint32): JSValue =
  return JS_NewUint32(ctx, n)

proc toJS*(ctx: JSContext; n: uint64): JSValue =
  #TODO this is incorrect
  return JS_NewFloat64(ctx, float64(n))

proc toJS*(ctx: JSContext; n: float64): JSValue =
  return JS_NewFloat64(ctx, n)

proc toJS*(ctx: JSContext; b: bool): JSValue =
  return JS_NewBool(ctx, b)

proc toJS*[T](ctx: JSContext; s: seq[T]): JSValue =
  var vals = newSeqOfCap[JSValue](s.len)
  for it in s:
    let val = ctx.toJS(it)
    if JS_IsException(val):
      ctx.freeValues(vals)
      return val
    vals.add(val)
  return ctx.newArrayFrom(vals)

proc toJS*[T](ctx: JSContext; s: set[T]): JSValue =
  var vals: seq[JSValue] = @[]
  for e in s:
    let val = ctx.toJS(e)
    if JS_IsException(val):
      ctx.freeValues(vals)
      return val
    vals.add(val)
  let a = ctx.newArrayFrom(vals)
  if JS_IsException(a):
    return a
  let ret = JS_CallConstructor(ctx, ctx.getOpaque().valRefs[jsvSet], 1,
    a.toJSValueArray())
  JS_FreeValue(ctx, a)
  return ret

proc toJS*[T: tuple](ctx: JSContext; t: T): JSValue =
  const L = uint(T.tupleLen)
  var vals {.noinit.}: array[L, JSValue]
  var u = 0u
  for it in t.fields:
    let val = ctx.toJS(it)
    if JS_IsException(val):
      break
    vals[u] = val
    inc u
  if u != L:
    if u > 0:
      ctx.freeValues(vals.toOpenArray(0, u - 1))
    return JS_EXCEPTION
  return ctx.newArrayFrom(vals)

proc toJSP0(ctx: JSContext; p, tp, toRef: pointer; ctor: JSValueConst):
    JSValue =
  let rtOpaque = JS_GetRuntime(ctx).getOpaque()
  rtOpaque.plist.withValue(p, obj):
    # a JSValue already points to this object.
    let val = JS_MKPTR(JS_TAG_OBJECT, obj[])
    if val.getOpaque() != nil:
      # JS owns the Nim value, because it still holds an active
      # reference to it.
      return JS_DupValue(ctx, val)
    # Nim owned the JS value, but now JS wants to own Nim.
    # This means we must release the JS reference, and add a reference
    # to Nim.
    GC_ref(cast[RootRef](toRef))
    JS_SetOpaque(val, p)
    return val
  let class = rtOpaque.typemap.getOrDefault(tp, 0)
  let jsObj = JS_NewObjectFromCtor(ctx, ctor, class)
  if JS_IsException(jsObj):
    return jsObj
  # We are constructing a new JS object, so we must add unforgeable properties
  # here.
  if not ctx.setUnforgeable(jsObj, class):
    return JS_EXCEPTION
  rtOpaque.plist[p] = JS_VALUE_GET_PTR(jsObj)
  JS_SetOpaque(jsObj, p)
  GC_ref(cast[RootRef](toRef))
  return jsObj

when defined(gcDestructors):
  proc getTypeInfo2[T](x: T): pointer {.magic: "GetTypeInfoV2".}
else:
  template getTypeInfo2[T](x: T): pointer = getTypeInfo(x)

# Get a unique pointer for each type.
template getTypePtr*[T: ref object and not RootRef](x: T): pointer =
  # This returns static type info, so it only works for non-inheritable
  # objects.
  getTypeInfo2(x[])

template getTypePtr*[T: object and not RootObj](x: var T): pointer =
  getTypeInfo2(x)

template getTypePtr*(x: RootRef): pointer =
  # Dereference the object's first member, m_type.
  cast[ptr pointer](x)[]

template getTypePtr*[T: RootObj](x: var T): pointer =
  # See above.
  cast[ptr pointer](addr x)[]

template getTypePtr*[T: ref object](t: typedesc[T]): pointer =
  var x: typeof(T()[])
  getTypeInfo2(x)

proc toJSRefObj*(ctx: JSContext; obj: ref object): JSValue =
  let p = cast[pointer](obj)
  let tp = getTypePtr(obj)
  return ctx.toJSP0(p, tp, p, JS_UNDEFINED)

proc toJS*(ctx: JSContext; obj: ref object): JSValue =
  if obj == nil:
    return JS_NULL
  return ctx.toJSRefObj(obj)

proc toJSNew*(ctx: JSContext; obj: ref object; ctor: JSValueConst): JSValue =
  if obj == nil:
    return JS_NULL
  let p = cast[pointer](obj)
  let tp = getTypePtr(obj)
  return ctx.toJSP0(p, tp, p, ctor)

proc toJSEnum(ctx: JSContext; enumId: int; n: int; s: string): JSValue =
  let rt = JS_GetRuntime(ctx)
  let rtOpaque = rt.getOpaque()
  if rtOpaque.enumMap.len <= enumId:
    rtOpaque.enumMap.setLen(enumId + 1)
  if rtOpaque.enumMap[enumId].len <= n:
    rtOpaque.enumMap[enumId].setLen(n + 1)
  var atom = rtOpaque.enumMap[enumId][n]
  if atom == JS_ATOM_NULL:
    atom = JS_NewAtomLen(ctx, cstringConst(s), csize_t(s.len))
    if atom == JS_ATOM_NULL:
      return JS_EXCEPTION
    rtOpaque.enumMap[enumId][n] = atom
  return JS_AtomToValue(ctx, atom)

const EnumCounter = CacheCounter("EnumCounter")

proc toJS*[T: enum](ctx: JSContext; e: T): JSValue =
  const enumId = EnumCounter.value
  static:
    inc EnumCounter
  ctx.toJSEnum(enumId, int(e), $e)

proc toJS(ctx: JSContext; j: JSValue): JSValue =
  return j

proc toJS*(ctx: JSContext; abuf: JSArrayBuffer): JSValue =
  return JS_NewArrayBuffer(ctx, abuf.p, abuf.len, abuf.dealloc, nil, false)

proc toJS*(ctx: JSContext; u8a: JSTypedArray): JSValue =
  let jsabuf = ctx.toJS(u8a.abuf)
  if JS_IsException(jsabuf):
    return jsabuf
  let argv = [JSValueConst(jsabuf), JS_UNDEFINED, JS_UNDEFINED]
  let ret = JS_NewTypedArray(ctx, 3, argv.toJSValueConstArray(),
    JS_TYPED_ARRAY_UINT8)
  JS_FreeValue(ctx, jsabuf)
  return ret

proc toJS*(ctx: JSContext; ns: NarrowString): JSValue =
  return JS_NewNarrowStringLen(ctx, cstring(ns), csize_t(string(ns).len))

proc toJS*[T: JSDict](ctx: JSContext; dict: T): JSValue =
  let obj = JS_NewObject(ctx)
  if JS_IsException(obj):
    return obj
  block good:
    for k, v in dict.fieldPairs:
      when k != "toFree":
        case ctx.defineProperty(obj, k, ctx.toJS(v))
        of dprSuccess, dprFail: discard
        of dprException: break good
    return obj
  JS_FreeValue(ctx, obj)
  return JS_EXCEPTION

{.pop.} # raises: []
