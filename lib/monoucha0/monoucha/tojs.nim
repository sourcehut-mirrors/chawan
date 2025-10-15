# Automatic conversion of Nim types to JavaScript types.
#
# Every conversion involves copying unless explicitly noted below.
#
# * Primitives are converted to their respective JavaScript counterparts.
# * seq is converted to a JS array. Note: this always copies the seq's contents.
# * enum is converted to its stringifier's output.
# * JSValue is returned as-is, *without* a DupValue operation.
# * JSError is converted to a new error object corresponding to the error
#   it represents.
# * JSArrayBuffer, JSUint8Array are converted to a JS object without copying
#   their contents.
# * NarrowString is converted to a JS narrow string (with copying). For more
#   information on JS string handling, see js/jstypes.nim.
# * Finally, ref object is converted to a JS object whose opaque is the ref
#   object. (See below.)
#
# Note that ref objects can be seamlessly converted to JS objects, despite
# the fact that they are managed by two separate garbage collectors. This
# works thanks to a patch in QJS and machine oil. Basically:
#
# * Nim objects registered with registerType can be paired with one (1)
#   JS object each.
# * This happens on-demand, whenever the Nim object has to be converted into JS.
# * Once the conversion happened, the JS object will be kept alive until the
#   Nim object is destroyed, so that JS properties on the JS object are not
#   lost during a re-conversion.
# * Similarly, the Nim object is kept alive so long as the JS object is alive.
# * The patched in can_destroy hook is used to synchronize reference counts
#   of the two objects; this way, no memory leak occurs.

{.push raises: [].}

import std/options
import std/tables

import jserror
import jsopaque
import jstypes
import jsutils
import optshim
import quickjs

# Convert Nim types to the corresponding JavaScript type.
# This does not work with var objects.
proc toJS*(ctx: JSContext; s: string): JSValue
proc toJS*(ctx: JSContext; n: int64): JSValue
proc toJS*(ctx: JSContext; n: int32): JSValue
proc toJS*(ctx: JSContext; n: int): JSValue
proc toJS*(ctx: JSContext; n: uint16): JSValue
proc toJS*(ctx: JSContext; n: uint32): JSValue
proc toJS*(ctx: JSContext; n: uint64): JSValue
proc toJS*(ctx: JSContext; n: float64): JSValue
proc toJS*(ctx: JSContext; b: bool): JSValue
proc toJS*[U, V](ctx: JSContext; t: Table[U, V]): JSValue
proc toJS*(ctx: JSContext; opt: Option): JSValue
proc toJS*[T, E](ctx: JSContext; opt: Result[T, E]): JSValue
proc toJS*(ctx: JSContext; s: seq): JSValue
proc toJS*[T](ctx: JSContext; s: set[T]): JSValue
proc toJS*(ctx: JSContext; t: tuple): JSValue
proc toJS*(ctx: JSContext; e: enum): JSValue
proc toJS*(ctx: JSContext; j: JSValue): JSValue
proc toJS*(ctx: JSContext; obj: ref object): JSValue
proc toJS*(ctx: JSContext; err: JSError): JSValue
proc toJS*(ctx: JSContext; abuf: JSArrayBuffer): JSValue
proc toJS*(ctx: JSContext; u8a: JSUint8Array): JSValue
proc toJS*(ctx: JSContext; ns: NarrowString): JSValue
proc toJS*[T: JSDict](ctx: JSContext; dict: T): JSValue

# Same as toJS, but used in constructors. ctor contains the target prototype,
# used for subclassing from JS.
proc toJSNew*(ctx: JSContext; obj: ref object; ctor: JSValueConst): JSValue
proc toJSNew*[T, E](ctx: JSContext; opt: Result[T, E]; ctor: JSValueConst):
  JSValue

type DefinePropertyResult* = enum
  dprException, dprSuccess, dprFail

# Note: this consumes `prop'.
proc defineProperty*(ctx: JSContext; this: JSValueConst; name: JSAtom;
    prop: JSValue; flags = cint(0)): DefinePropertyResult =
  return case JS_DefinePropertyValue(ctx, this, name, prop, flags)
  of 0: dprFail
  of 1: dprSuccess
  else: dprException

# Note: this consumes `prop'.
proc defineProperty(ctx: JSContext; this: JSValueConst; name: int64;
    prop: JSValue; flags = cint(0)): DefinePropertyResult =
  let name = JS_NewInt64(ctx, name)
  let atom = JS_ValueToAtom(ctx, name)
  JS_FreeValue(ctx, name)
  if unlikely(atom == JS_ATOM_NULL):
    return dprException
  result = ctx.defineProperty(this, atom, prop, flags)
  JS_FreeAtom(ctx, atom)

proc definePropertyC*(ctx: JSContext; this: JSValueConst; name: JSAtom;
    prop: JSValue): DefinePropertyResult =
  ctx.defineProperty(this, name, prop, JS_PROP_CONFIGURABLE)

proc defineProperty(ctx: JSContext; this: JSValueConst; name: string;
    prop: JSValue; flags = cint(0)): DefinePropertyResult =
  return case JS_DefinePropertyValueStr(ctx, this, cstring(name), prop, flags)
  of 0: dprFail
  of 1: dprSuccess
  else: dprException

proc definePropertyC*(ctx: JSContext; this: JSValueConst; name: string;
    prop: JSValue): DefinePropertyResult =
  ctx.defineProperty(this, name, prop, JS_PROP_CONFIGURABLE)

proc defineProperty*[T](ctx: JSContext; this: JSValueConst; name: string;
    prop: T; flags = cint(0)): DefinePropertyResult =
  ctx.defineProperty(this, name, ctx.toJS(prop), flags)

proc definePropertyE*[T](ctx: JSContext; this: JSValueConst; name: string;
    prop: T): DefinePropertyResult =
  ctx.defineProperty(this, name, prop, JS_PROP_ENUMERABLE)

proc definePropertyCW*[T](ctx: JSContext; this: JSValueConst; name: string;
    prop: T): DefinePropertyResult =
  ctx.defineProperty(this, name, prop, JS_PROP_CONFIGURABLE or
    JS_PROP_WRITABLE)

proc definePropertyCWE*[T](ctx: JSContext; this: JSValueConst; name: string;
    prop: T): DefinePropertyResult =
  ctx.defineProperty(this, name, prop, JS_PROP_C_W_E)

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

proc toJS*[U, V](ctx: JSContext; t: Table[U, V]): JSValue =
  let obj = JS_NewObject(ctx)
  if not JS_IsException(obj):
    for k, v in t:
      case ctx.definePropertyCWE(obj, k, v)
      of dprException:
        JS_FreeValue(ctx, obj)
        return JS_EXCEPTION
      else: discard
  return obj

proc toJS*(ctx: JSContext; opt: Option): JSValue =
  if opt.isSome:
    return ctx.toJS(opt.get)
  return JS_NULL

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

proc toJS*(ctx: JSContext; s: seq): JSValue =
  let a = JS_NewArray(ctx)
  if not JS_IsException(a):
    for i in 0 ..< s.len:
      let val = toJS(ctx, s[i])
      if JS_IsException(val):
        return val
      case ctx.defineProperty(a, int64(i), val, JS_PROP_C_W_E or JS_PROP_THROW)
      of dprException: return JS_EXCEPTION
      else: discard
  return a

proc toJS*[T](ctx: JSContext; s: set[T]): JSValue =
  let a = JS_NewArray(ctx)
  if JS_IsException(a):
    return a
  var i = 0i64
  for e in s:
    let val = ctx.toJS(e)
    if JS_IsException(val):
      return val
    case ctx.defineProperty(a, i, val, JS_PROP_C_W_E or JS_PROP_THROW)
    of dprException:
      JS_FreeValue(ctx, a)
      return JS_EXCEPTION
    else: discard
    inc i
  let ret = JS_CallConstructor(ctx, ctx.getOpaque().valRefs[jsvSet], 1,
    a.toJSValueArray())
  JS_FreeValue(ctx, a)
  return ret

proc toJS(ctx: JSContext; t: tuple): JSValue =
  let a = JS_NewArray(ctx)
  if not JS_IsException(a):
    var i = 0i64
    for f in t.fields:
      let val = toJS(ctx, f)
      if JS_IsException(val):
        return val
      case ctx.defineProperty(a, i, val, JS_PROP_C_W_E or JS_PROP_THROW)
      of dprException:
        JS_FreeValue(ctx, a)
        return JS_EXCEPTION
      else: discard
      inc i
  return a

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
  rtOpaque.plist[p] = JS_VALUE_GET_PTR(jsObj)
  JS_SetOpaque(jsObj, p)
  # We are constructing a new JS object, so we must add unforgeable properties
  # here.
  let iclass = int(class)
  if iclass < rtOpaque.classes.len and
      rtOpaque.classes[iclass].unforgeable.len > 0:
    let ufp0 = addr rtOpaque.classes[iclass].unforgeable[0]
    let ufp = cast[JSCFunctionListP](ufp0)
    JS_SetPropertyFunctionList(ctx, jsObj, ufp,
      cint(rtOpaque.classes[iclass].unforgeable.len))
  GC_ref(cast[RootRef](toRef))
  return jsObj

type NonInheritable = (object and not RootObj) or (ref object and not RootRef)

when defined(gcDestructors):
  proc getTypeInfo2[T](x: T): pointer {.magic: "GetTypeInfoV2".}
else:
  template getTypeInfo2[T](x: T): pointer = getTypeInfo(x)

# Get a unique pointer for each type.
template getTypePtr*[T: NonInheritable](x: T): pointer =
  # This only seems to work for non-inheritable objects.
  getTypeInfo2(x)

template getTypePtr*[T: RootObj](x: T): pointer {.error:
    "Please make it var".} =
  discard

template getTypePtr*(x: RootRef): pointer =
  # Dereference the object's first member, m_type.
  cast[ptr pointer](x)[]

when defined(gcDestructors):
  proc getTypePtr*[T: RootObj](x: var T): pointer {.nodestroy.} =
    # ARC somehow doesn't return the same pointer without this...
    getTypePtr(cast[ref T](addr x))
else:
  template getTypePtr*[T: RootObj](x: var T): pointer =
    # See above.
    cast[ptr pointer](addr x)[]

# For some reason, getTypeInfo for ref object of RootObj returns a
# different pointer from m_type.
# To make matters even more confusing, getTypeInfo on non-inherited ref
# object returns a different type than on the same non-ref object.
template getTypePtr*[T: RootRef](t: typedesc[T]): pointer =
  var x: typeof(t()[])
  getTypeInfo2(x)

template getTypePtr*[T: ref object](t: typedesc[T]): pointer =
  var x: T
  getTypeInfo2(x)

proc toJSRefObj(ctx: JSContext; obj: ref object): JSValue =
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

proc toJS(ctx: JSContext; e: enum): JSValue =
  return toJS(ctx, $e)

proc toJS(ctx: JSContext; j: JSValue): JSValue =
  return j

proc toJS*(ctx: JSContext; err: JSError): JSValue =
  if err == nil:
    return JS_EXCEPTION
  if err.e == jeCustom:
    return ctx.toJSRefObj(err)
  var msg = toJS(ctx, err.message)
  if JS_IsException(msg):
    return msg
  let ctor = ctx.getOpaque().errCtorRefs[err.e]
  let ret = JS_CallConstructor(ctx, ctor, 1, msg.toJSValueArray())
  JS_FreeValue(ctx, msg)
  return ret

proc toJS*(ctx: JSContext; abuf: JSArrayBuffer): JSValue =
  return JS_NewArrayBuffer(ctx, abuf.p, abuf.len, abuf.dealloc, nil, false)

proc toJS*(ctx: JSContext; u8a: JSUint8Array): JSValue =
  let jsabuf = toJS(ctx, u8a.abuf)
  let ctor = ctx.getOpaque().valRefs[jsvUint8Array]
  let ret = JS_CallConstructor(ctx, ctor, 1, jsabuf.toJSValueArray())
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
        case ctx.defineProperty(obj, k, v)
        of dprSuccess, dprFail: discard
        of dprException: break good
    return obj
  JS_FreeValue(ctx, obj)
  return JS_EXCEPTION

{.pop.} # raises: []
