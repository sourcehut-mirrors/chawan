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
import std/typetraits

import jsopaque
import jsref
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
proc toJS*[T: enum](ctx: JSContext; e: T): JSValue
proc toJS*(ctx: JSContext; j: JSValue): JSValue
proc toJS*[T](ctx: JSContext; obj: JSRef[T]): JSValue
proc toJS*(ctx: JSContext; abuf: JSArrayBuffer): JSValue
proc toJS*(ctx: JSContext; u8a: JSArrayBufferView): JSValue
proc toJS*(ctx: JSContext; ns: NarrowString): JSValue
proc toJS*[T: JSDict](ctx: JSContext; dict: T): JSValue

# Same as toJS, but used in constructors. ctor contains the target prototype,
# used for subclassing from JS.
# Note: nil is translated to an OOM exception.
proc toJSNew*[T](ctx: JSContext; obj: JSRef[T]; ctor: JSValueConst): JSValue

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
  return JS_NewStringLen(ctx, s.toCStringConst, csize_t(s.len))

proc toJS*(ctx: JSContext; s: openArray[char]): JSValue =
  if s.len < 0:
    return JS_NewString(ctx, "")
  return JS_NewStringLen(ctx, cast[cstringConst](unsafeAddr s[0]),
    csize_t(s.len))

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
  const L = T.tupleLen
  var vals {.noinit.}: array[L, JSValue]
  var i = 0
  {.push overflowChecks: off.}
  for it in t.fields:
    let val = ctx.toJS(it)
    if JS_IsException(val):
      break
    vals[i] = val
    inc i
  if i != L:
    ctx.freeValues(vals.toOpenArray(0, i - 1))
    return JS_EXCEPTION
  {.pop.}
  return ctx.newArrayFrom(vals)

proc toJSRef(ctx: JSContext; p: pointer; ctor: JSValueConst): JSValue =
  let rt = JS_GetRuntime(ctx)
  let jsptr = JS_GetForeignOpaque(rt, p)
  if jsptr != nil:
    # a JSValue already points to this object.
    if ctx.getOpaque().globalObj == p:
      return JS_GetGlobalObject(ctx)
    return JS_DupValue(ctx, JS_MKPTR(JS_TAG_OBJECT, jsptr))
  let classid = JS_GetForeignClassID(p)
  let jsObj = JS_NewObjectFromCtor(ctx, ctor, classid)
  if JS_IsException(jsObj):
    return jsObj
  # Set the opaque first, before GC has a chance to run.
  JS_SetForeignOpaque(rt, p, jsObj)
  JS_SetOpaque(jsObj, p)
  # We are constructing a new JS object, so we must add unforgeable properties
  # here.
  if not ctx.setUnforgeable(jsObj, classid):
    JS_FreeValue(ctx, jsObj)
    return JS_EXCEPTION
  return jsObj

proc toJS*[T](ctx: JSContext; obj: JSRef[T]): JSValue =
  if obj == nil:
    return JS_NULL
  return ctx.toJSRef(cast[pointer](obj), JS_UNDEFINED)

proc toJSNew*[T](ctx: JSContext; obj: JSRef[T]; ctor: JSValueConst): JSValue =
  if obj == nil:
    return JS_ThrowOutOfMemory(ctx)
  return ctx.toJSRef(cast[pointer](obj), ctor)

template toJSNew*[T](ctx: JSContext; obj: JSRef[T]): JSValue =
  # useful when you want to JSify a new object (i.e., nil converts to OOM)
  ctx.toJSNew(obj, JS_UNDEFINED)

proc toJSEnum(ctx: JSContext; enumId: int; n: int; s: string): JSValue =
  let rt = JS_GetRuntime(ctx)
  let rtOpaque = rt.getOpaque()
  if rtOpaque.enumMap.len <= enumId:
    rtOpaque.enumMap.setLen(enumId + 1)
  if rtOpaque.enumMap[enumId].atoms.len <= n:
    rtOpaque.enumMap[enumId].atoms.setLen(n + 1)
  var atom = rtOpaque.enumMap[enumId].atoms[n]
  if atom == JS_ATOM_NULL:
    atom = JS_NewAtomLen(ctx, cstringConst(s), csize_t(s.len))
    if atom == JS_ATOM_NULL:
      return JS_EXCEPTION
    rtOpaque.enumMap[enumId].atoms[n] = atom
  return JS_AtomToValue(ctx, atom)

const EnumCounter = CacheCounter("EnumCounter")

proc getJSEnumId*[T: enum](t: typedesc[T]): int =
  const enumId = EnumCounter.value
  static:
    assert int(T.low) >= 0
    inc EnumCounter
  enumId

proc toJS*[T: enum](ctx: JSContext; e: T): JSValue =
  const enumId = getJSEnumId(T)
  ctx.toJSEnum(enumId, int(e), $e)

proc toJS*(ctx: JSContext; j: JSValue): JSValue =
  return j

proc toJS*(ctx: JSContext; p: JSObject): JSValue =
  # this is inconsistent, but I don't have a better idea right now
  if p == nil:
    return JS_NULL
  return JS_DupValue(ctx, p.value)

proc toJS*(ctx: JSContext; abuf: JSArrayBuffer): JSValue =
  let len = csize_t(abuf.len)
  return JS_NewArrayBuffer(ctx, abuf.p, len, abuf.dealloc, nil, false)

proc toJS*(ctx: JSContext; u8a: JSArrayBufferView): JSValue =
  let jsabuf = ctx.toJS(u8a.abuf)
  if JS_IsException(jsabuf):
    return jsabuf
  let offset = ctx.toJS(u8a.offset)
  if JS_IsException(offset):
    JS_FreeValue(ctx, jsabuf)
    return offset
  let len = ctx.toJS(u8a.len)
  if JS_IsException(len):
    JS_FreeValue(ctx, jsabuf)
    JS_FreeValue(ctx, offset)
    return len
  let argv = [JSValueConst(jsabuf), JSValueConst(offset), JSValueConst(len)]
  let ret = JS_NewTypedArray(ctx, 3, argv.toJSValueConstArray(), u8a.t)
  JS_FreeValue(ctx, jsabuf)
  JS_FreeValue(ctx, offset)
  JS_FreeValue(ctx, len)
  return ret

proc toJS*(ctx: JSContext; ns: NarrowString): JSValue =
  return JS_NewNarrowStringLen(ctx, cstring(ns), csize_t(string(ns).len))

proc definePropertyConvert*[T](ctx: JSContext; this: JSValueConst;
    name: cstring; x: T): JSCode =
  let val = ctx.toJS(x)
  if JS_IsException(val):
    return fjErr
  ctx.defineProperty(this, name, val)

proc toJS*[T: JSDict](ctx: JSContext; dict: T): JSValue =
  let obj = JS_NewObject(ctx)
  if JS_IsException(obj):
    return obj
  block good:
    for k, v in dict.fieldPairs:
      if ctx.definePropertyConvert(obj, k, v) == fjErr:
        break good
    return obj
  JS_FreeValue(ctx, obj)
  return JS_EXCEPTION

{.pop.} # raises: []
