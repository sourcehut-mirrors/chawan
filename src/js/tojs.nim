## Automatic conversion of Nim types to JavaScript types.
##
## Every conversion involves copying unless explicitly noted below.
##
## * Primitives are converted to their respective JavaScript counterparts.
## * seq is converted to a JS array. Note: this always copies the seq's
##   contents.
## * enum is converted to its stringifier's output.
## * JSValue is returned as-is, *without* a DupValue operation.
## * JSArrayBuffer, JSArrayBufferViewInit are converted to a JS object without
##   copying their contents.
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

import js/constcharp
import js/cutils
import js/jsopaque
import js/jsref
import js/jstypes
import js/jsutils
import js/quickjs
import utils/opt

# Convert Nim types to the corresponding JavaScript type.
proc toJS*(ctx: JSContext; s: string): JSValue
proc toJS*(ctx: JSContext; s: DOMString): JSValue
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
proc toJS*(ctx: JSContext; t: JSValueTraced): JSValue
proc toJS*[T](ctx: JSContext; obj: sink JSRef[T]): JSValue
proc toJS*(ctx: JSContext; abuf: JSArrayBufferInit): JSValue
proc toJS*(ctx: JSContext; u8a: JSArrayBufferViewInit): JSValue
proc toJS*(ctx: JSContext; ns: NarrowString): JSValue
proc toJS*[T](ctx: JSContext; opt: Opt[T]): JSValue

# Same as toJS, but used in constructors. ctor contains the target prototype,
# used for subclassing from JS.
# Note: nil is translated to an OOM exception.
proc toJSNew*[T](ctx: JSContext; obj: sink JSRef[T]; ctor: JSValueConst):
  JSValue
proc toJSNew*[T](ctx: JSContext; opt: Opt[T]; ctor: JSValueConst): JSValue
proc toJSNew*[T](ctx: JSContext; opt: Opt[T]): JSValue

proc newFunction*(ctx: JSContext; args: openArray[string]; body: string):
    JSValue =
  var paramList: seq[JSValue] = @[]
  for arg in args:
    paramList.add(ctx.toJS(arg))
  paramList.add(ctx.toJS(body))
  let fun = ctx.callConstructor(ctx.getOpaque().funRefs[jsfFunction],
    paramList)
  for param in paramList:
    JS_FreeValue(ctx, param)
  return fun

proc newArrayBuffer*(ctx: JSContext; s: openArray[char]): JSValue =
  let p = if s.len > 0:
    cast[ptr UncheckedArray[uint8]](unsafeAddr s[0])
  else:
    nil
  return JS_NewArrayBufferCopy(ctx, p, csize_t(s.len))

proc toJS*(ctx: JSContext; s: cstring): JSValue =
  return JS_NewString(ctx, s)

proc toJS*(ctx: JSContext; s: string): JSValue =
  return JS_NewStringLen(ctx, s.toCStringConst, csize_t(s.len))

proc toJS*(ctx: JSContext; s: openArray[char]): JSValue =
  if s.len < 0:
    return JS_NewString(ctx, "")
  return JS_NewStringLen(ctx, cast[cstringConst](unsafeAddr s[0]),
    csize_t(s.len))

proc toJS*(ctx: JSContext; s: DOMString): JSValue =
  ctx.toJS(s.toOpenArray())

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
  return JS_NewBool(ctx, JS_BOOL(b))

proc toJS*[T](ctx: JSContext; s: seq[T]): JSValue =
  var vals = newSeqOfCap[JSValue](s.len)
  for it in s:
    let val = ctx.toJS(it)
    if JS_IsException(val.vc):
      ctx.freeValues(vals)
      return val
    vals.add(val)
  return ctx.newArrayFrom(vals)

proc toJS*[T](ctx: JSContext; s: set[T]): JSValue =
  var vals: seq[JSValue] = @[]
  for e in s:
    let val = ctx.toJS(e)
    if JS_IsException(val.vc):
      ctx.freeValues(vals)
      return val
    vals.add(val)
  let a = ctx.newArrayFrom(vals)
  if JS_IsException(a.vc):
    return JS_EXCEPTION
  let ret = ctx.callConstructor(ctx.getOpaque().funRefs[jsfSet], [a])
  JS_FreeValue(ctx, a)
  return ret

proc toJS*[T: tuple](ctx: JSContext; t: T): JSValue =
  const L = T.tupleLen
  var vals {.noinit.}: array[L, JSValue]
  var i = 0
  {.push overflowChecks: off.}
  for it in t.fields:
    let val = ctx.toJS(it)
    if JS_IsException(val.vc):
      break
    vals[i] = val
    inc i
  if i != L:
    ctx.freeValues(vals.toOpenArray(0, i - 1))
    return JS_EXCEPTION
  {.pop.}
  return ctx.newArrayFrom(vals)

proc toJSRef0(ctx: JSContext; p: pointer; ctor: JSValueConst): JSValue =
  let rt = JS_GetRuntime(ctx)
  let jsptr = JS_GetForeignOpaque(rt, p)
  if jsptr != nil:
    # a JSValue already points to this object.
    if ctx.getOpaque().globalObj == p:
      JS_FreeForeignObject(rt, p)
      return JS_GetGlobalObject(ctx)
    return JS_MKPTR(JS_TAG_OBJECT, jsptr)
  let classid = JS_GetForeignClassID(p)
  var jsObj0 = ctx.newObjectFromCtor(ctor, classid)
  if jsObj0.isErr:
    JS_FreeForeignObject(rt, p)
    return JS_EXCEPTION
  let jsObj = move(jsObj0.get)
  # Set the opaque first, before GC has a chance to run.
  JS_SetForeignOpaque(rt, p, JSValue(jsObj.value))
  JS_SetOpaque(jsObj.value, p)
  # We are constructing a new JS object, so we must add unforgeable properties
  # here.
  ?ctx.setUnforgeable(jsObj, classid)
  return jsObj.toJSValue()

proc toJSRef(ctx: JSContext; p: pointer): JSValue =
  if p == nil:
    return JS_NULL
  ctx.toJSRef0(p, JS_UNDEFINED.vc)

proc toJSRefNew(ctx: JSContext; p: pointer; ctor: JSValueConst): JSValue =
  if p == nil:
    return JS_ThrowOutOfMemory(ctx)
  ctx.toJSRef0(p, ctor)

proc toJS*[T](ctx: JSContext; obj: sink JSRef[T]): JSValue =
  let p = cast[pointer](obj)
  wasMoved(obj)
  ctx.toJSRef(p)

proc toJSNew*[T](ctx: JSContext; obj: sink JSRef[T]; ctor: JSValueConst):
    JSValue =
  let p = cast[pointer](obj)
  wasMoved(obj)
  ctx.toJSRefNew(p, ctor)

template toJSNew*[T](ctx: JSContext; obj: JSRef[T]): JSValue =
  # useful when you want to JSify a new object (i.e., nil converts to OOM)
  ctx.toJSNew(obj, JS_UNDEFINED.vc)

proc toJSEnum(ctx: JSContext; enumId: int; n: int; s: string): JSValue =
  let rt = JS_GetRuntime(ctx)
  let rtOpaque = rt.getOpaque()
  if rtOpaque.enumMap.len <= enumId:
    rtOpaque.enumMap.setLen(enumId + 1)
  if rtOpaque.enumMap[enumId].atoms.len <= n:
    rtOpaque.enumMap[enumId].atoms.setLen(n + 1)
  var atom = rtOpaque.enumMap[enumId].atoms[n]
  if atom == JS_ATOM_NULL:
    atom = ?JS_NewAtomLen(ctx, cstringConst(s), csize_t(s.len))
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

proc toJS*(ctx: JSContext; t: JSValueTraced): JSValue =
  return JS_DupValue(ctx, t.vc)

proc toJS*(ctx: JSContext; p: JSObject): JSValue =
  return JS_DupValue(ctx, p.value)

proc toJS*(ctx: JSContext; p: JSObjectNil): JSValue =
  return JS_DupValue(ctx, p.value)

proc toJS*(ctx: JSContext; abuf: JSArrayBufferInit): JSValue =
  let len = csize_t(abuf.len)
  return JS_NewArrayBuffer(ctx, abuf.p, len, abuf.dealloc, nil, JS_BOOL(0))

proc toJS*(ctx: JSContext; u8a: JSArrayBufferViewInit): JSValue =
  let jsabuf = ctx.toJS(u8a.abuf)
  if JS_IsException(jsabuf.vc):
    return jsabuf
  let offset = ctx.toJS(u8a.offset)
  if JS_IsException(offset.vc):
    JS_FreeValue(ctx, jsabuf)
    return JS_EXCEPTION
  let len = ctx.toJS(u8a.len)
  if JS_IsException(len.vc):
    JS_FreeValue(ctx, jsabuf)
    JS_FreeValue(ctx, offset)
    return JS_EXCEPTION
  let argv = [JSValueConst(jsabuf), JSValueConst(offset), JSValueConst(len)]
  let ret = JS_NewTypedArray(ctx, 3, argv.toJSValueConstArray(), u8a.t)
  JS_FreeValue(ctx, jsabuf)
  JS_FreeValue(ctx, offset)
  JS_FreeValue(ctx, len)
  return ret

proc toJS*(ctx: JSContext; ns: NarrowString): JSValue =
  return JS_NewNarrowStringLen(ctx, cstring(ns), csize_t(string(ns).len))

proc definePropertyConvert*[T](ctx: JSContext; this: JSObject;
    name: JSStrRef; x: T): JSCode =
  let val = ctx.toJS(x)
  if JS_IsException(val.vc):
    return fjErr
  ctx.defineProperty(this, name, val)

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

proc toJSNew*[T](ctx: JSContext; opt: Opt[T]): JSValue =
  if opt.isOk:
    when not (T is void):
      return ctx.toJSNew(opt.get)
    else:
      return JS_UNDEFINED
  else:
    return JS_EXCEPTION

{.pop.} # raises: []
