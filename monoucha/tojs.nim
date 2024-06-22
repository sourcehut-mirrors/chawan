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
#
# There are also toJSP variants of object converters. These work identically
# to ref object converters, except the reference count of the closest
# `ref object' ancestor is incremented/decremented when synchronizing refcounts
# with the JS object pair.

import std/options
import std/tables
import std/unicode

import jserror
import jsopaque
import jstypes
import jsutils
import optshim
import quickjs

# Convert Nim types to the corresponding JavaScript type.
# This does not work with var objects.
proc toJS*(ctx: JSContext; s: string): JSValue
proc toJS*(ctx: JSContext; r: Rune): JSValue
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
proc toJS*(ctx: JSContext; dict: JSDict): JSValue

# Convert Nim types to the corresponding JavaScript type, with knowledge of
# the parent object.
# This supports conversion of var object types.
#
# The idea here is to allow conversion of var objects to quasi-reference types
# by saving a pointer to their ancestor and incrementing/decrementing the
# ancestor's reference count instead.
proc toJSP*(ctx: JSContext; parent: ref object; child: var object): JSValue
proc toJSP*(ctx: JSContext; parent: ptr object; child: var object): JSValue

# Same as toJS, but used in constructors. ctor contains the target prototype,
# used for subclassing from JS.
proc toJSNew*(ctx: JSContext; obj: ref object; ctor: JSValue): JSValue
proc toJSNew*[T, E](ctx: JSContext; opt: Result[T, E]; ctor: JSValue): JSValue

# Avoid accidentally calling toJSP on objects that we have explicit toJS
# converters for.
template makeToJSP(typ: untyped) =
  template toJSP*(ctx: JSContext; parent: ref object; child: var typ): JSValue =
    toJS(ctx, child)
  template toJSP*(ctx: JSContext; parent: ptr object; child: var typ): JSValue =
    toJS(ctx, child)
makeToJSP(Table)
makeToJSP(Option)
makeToJSP(Result)
makeToJSP(JSValue)
makeToJSP(JSDict)

# Note: this consumes `prop'.
proc defineProperty(ctx: JSContext; this: JSValue; name: JSAtom;
    prop: JSValue; flags = cint(0)) =
  if JS_DefinePropertyValue(ctx, this, name, prop, flags) <= 0:
    raise newException(Defect, "Failed to define property string")

proc defineProperty(ctx: JSContext; this, name, prop: JSValue;
    flags = cint(0)) =
  let atom = JS_ValueToAtom(ctx, prop);
  JS_FreeValue(ctx, prop);
  if unlikely(atom == JS_ATOM_NULL):
    raise newException(Defect, "Failed to define property string")
  ctx.defineProperty(this, atom, prop, flags)
  JS_FreeAtom(ctx, atom);

proc definePropertyC*(ctx: JSContext; this: JSValue; name: JSAtom;
    prop: JSValue) =
  ctx.defineProperty(this, name, prop, JS_PROP_CONFIGURABLE)

proc defineProperty(ctx: JSContext; this: JSValue; name: string;
    prop: JSValue; flags = cint(0)) =
  if JS_DefinePropertyValueStr(ctx, this, cstring(name), prop, flags) <= 0:
    raise newException(Defect, "Failed to define property string: " & name)

proc definePropertyC*(ctx: JSContext; this: JSValue; name: string;
    prop: JSValue) =
  ctx.defineProperty(this, name, prop, JS_PROP_CONFIGURABLE)

proc defineProperty*[T](ctx: JSContext; this: JSValue; name: string; prop: T;
    flags = cint(0)) =
  defineProperty(ctx, this, name, toJS(ctx, prop), flags)

proc definePropertyE*[T](ctx: JSContext; this: JSValue; name: string;
    prop: T) =
  defineProperty(ctx, this, name, prop, JS_PROP_ENUMERABLE)

proc definePropertyCW*[T](ctx: JSContext; this: JSValue; name: string;
    prop: T) =
  defineProperty(ctx, this, name, prop, JS_PROP_CONFIGURABLE or
    JS_PROP_WRITABLE)

proc definePropertyCWE*[T](ctx: JSContext; this: JSValue; name: string;
    prop: T) =
  defineProperty(ctx, this, name, prop, JS_PROP_C_W_E)

proc newFunction*(ctx: JSContext; args: openArray[string]; body: string):
    JSValue =
  var paramList: seq[JSValue] = @[]
  for arg in args:
    paramList.add(toJS(ctx, arg))
  paramList.add(toJS(ctx, body))
  let fun = JS_CallConstructor(ctx, ctx.getOpaque().valRefs[jsvFunction],
    cint(paramList.len), paramList.toJSValueArray())
  for param in paramList:
    JS_FreeValue(ctx, param)
  return fun

proc toJS*(ctx: JSContext; s: cstring): JSValue =
  return JS_NewString(ctx, s)

proc toJS*(ctx: JSContext; s: string): JSValue =
  return toJS(ctx, cstring(s))

proc toJS*(ctx: JSContext; r: Rune): JSValue =
  return toJS(ctx, $r)

proc toJS*(ctx: JSContext; n: int32): JSValue =
  return JS_NewInt32(ctx, n)

proc toJS*(ctx: JSContext; n: int64): JSValue =
  return JS_NewInt64(ctx, n)

# Always int32, so we don't risk 32-bit only breakage.
proc toJS*(ctx: JSContext; n: int): JSValue =
  return toJS(ctx, int32(n))

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
      definePropertyCWE(ctx, obj, k, v)
  return obj

proc toJS*(ctx: JSContext; opt: Option): JSValue =
  if opt.isSome:
    return toJS(ctx, opt.get)
  return JS_NULL

proc toJS*[T, E](ctx: JSContext; opt: Result[T, E]): JSValue =
  if opt.isSome:
    when not (T is void):
      return toJS(ctx, opt.get)
    else:
      return JS_UNDEFINED
  else:
    when not (E is void):
      if opt.error != nil:
        return JS_Throw(ctx, toJS(ctx, opt.error))
    return JS_EXCEPTION

proc toJS*(ctx: JSContext; s: seq): JSValue =
  let a = JS_NewArray(ctx)
  if not JS_IsException(a):
    for i, x in s:
      let val = toJS(ctx, x)
      if JS_IsException(val):
        return val
      ctx.defineProperty(a, JS_NewInt64(ctx, int64(i)), val,
        JS_PROP_C_W_E or JS_PROP_THROW)
  return a

proc toJS*[T](ctx: JSContext; s: set[T]): JSValue =
  #TODO this is a bit lazy :p
  var x = newSeq[T]()
  for e in s:
    x.add(e)
  var a = toJS(ctx, x)
  if JS_IsException(a):
    return a
  let ret = JS_CallConstructor(ctx, ctx.getOpaque().valRefs[jsvSet], 1,
    a.toJSValueArray())
  JS_FreeValue(ctx, a)
  return ret

proc toJS(ctx: JSContext; t: tuple): JSValue =
  let a = JS_NewArray(ctx)
  if not JS_IsException(a):
    var i = 0
    for f in t.fields:
      let val = toJS(ctx, f)
      if JS_IsException(val):
        return val
      ctx.defineProperty(a, JS_NewInt64(ctx, int64(i)), val,
        JS_PROP_C_W_E or JS_PROP_THROW)
      inc i
  return a

proc toJSP0(ctx: JSContext; p, tp: pointer; ctor: JSValue;
    needsref: var bool): JSValue =
  JS_GetRuntime(ctx).getOpaque().plist.withValue(p, obj):
    # a JSValue already points to this object.
    return JS_DupValue(ctx, JS_MKPTR(JS_TAG_OBJECT, obj[]))
  let ctxOpaque = ctx.getOpaque()
  let class = ctxOpaque.typemap[tp]
  let jsObj = JS_NewObjectFromCtor(ctx, ctor, class)
  if JS_IsException(jsObj):
    return jsObj
  setOpaque(ctx, jsObj, p)
  # We are constructing a new JS object, so we must add unforgeable properties
  # here.
  ctxOpaque.unforgeable.withValue(class, uf):
    let ufp = cast[ptr UncheckedArray[JSCFunctionListEntry]](addr uf[][0])
    JS_SetPropertyFunctionList(ctx, jsObj, ufp, cint(uf[].len))
  needsref = true
  if unlikely(ctxOpaque.htmldda == class):
    JS_SetIsHTMLDDA(ctx, jsObj)
  return jsObj

# Get a unique pointer for each type.
proc getTypePtr*[T](x: T): pointer =
  when T is RootRef:
    # I'm so sorry.
    # (This dereferences the object's first member, m_type. Probably.)
    return cast[ptr pointer](x)[]
  elif T is RootObj:
    return cast[pointer](x)
  else:
    return getTypeInfo(x)

func getTypePtr*(t: typedesc[ref object]): pointer =
  var x = t()
  return getTypePtr(x)

func getTypePtr*(t: type): pointer =
  var x: t
  return getTypePtr(x)

proc toJSRefObj(ctx: JSContext; obj: ref object): JSValue =
  if obj == nil:
    return JS_NULL
  let p = cast[pointer](obj)
  let tp = getTypePtr(obj)
  var needsref = false
  let val = toJSP0(ctx, p, tp, JS_UNDEFINED, needsref)
  if needsref:
    GC_ref(obj)
  return val

proc toJS*(ctx: JSContext; obj: ref object): JSValue =
  return toJSRefObj(ctx, obj)

proc toJSNew*(ctx: JSContext; obj: ref object; ctor: JSValue): JSValue =
  if obj == nil:
    return JS_NULL
  let p = cast[pointer](obj)
  let tp = getTypePtr(obj)
  var needsref = false
  let val = toJSP0(ctx, p, tp, ctor, needsref)
  if needsref:
    GC_ref(obj)
  return val

proc toJSNew[T, E](ctx: JSContext; opt: Result[T, E]; ctor: JSValue): JSValue =
  if opt.isSome:
    when not (T is void):
      return toJSNew(ctx, opt.get, ctor)
    else:
      return JS_UNDEFINED
  else:
    when not (E is void):
      let res = toJS(ctx, opt.error)
      if not JS_IsNull(res):
        return JS_Throw(ctx, res)
    else:
      return JS_NULL

proc toJS(ctx: JSContext; e: enum): JSValue =
  return toJS(ctx, $e)

proc toJS(ctx: JSContext; j: JSValue): JSValue =
  return j

proc toJS*(ctx: JSContext; err: JSError): JSValue =
  if err == nil:
    return JS_EXCEPTION
  if err.e notin QuickJSErrors:
    return toJSRefObj(ctx, err)
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

proc toJS*(ctx: JSContext; dict: JSDict): JSValue =
  let obj = JS_NewObject(ctx)
  if JS_IsException(obj):
    return obj
  for k, v in dict.fieldPairs:
    ctx.defineProperty(obj, k, v)
  return obj

proc toJSP(ctx: JSContext; parent: ref object; child: var object): JSValue =
  let p = addr child
  # Save parent as the original ancestor for this tree.
  JS_GetRuntime(ctx).getOpaque().refmap[p] = (
    (proc() =
      GC_ref(parent)),
    (proc() =
      GC_unref(parent))
  )
  let tp = getTypePtr(child)
  var needsref = false
  let val = toJSP0(ctx, p, tp, JS_UNDEFINED, needsref)
  if needsref:
    GC_ref(parent)
  return val

proc toJSP(ctx: JSContext; parent: ptr object; child: var object): JSValue =
  let p = addr child
  # Increment the reference count of parent's root ancestor, and save the
  # increment/decrement callbacks for the child as well.
  let rtOpaque = JS_GetRuntime(ctx).getOpaque()
  let ru = rtOpaque.refmap[parent]
  ru.cref()
  rtOpaque.refmap[p] = ru
  let tp = getTypePtr(child)
  return toJSP0(ctx, p, tp)
