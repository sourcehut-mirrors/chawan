## Miscellaneous wrappers around QJS functions.

{.push raises: [].}

import js/constcharp
import js/cutils
import js/dtoa
import js/jsopaque
import js/jstypes
import js/quickjs
import utils/opt

type JSCode* = enum
  fjErr, fjOk

template `?`*(res: JSCode) =
  if res == fjErr:
    return err()

template myMove(x: untyped): untyped =
  when NimMajor < 2:
    move(x)
  else:
    ensureMove(x)

template `?`*(res: JSValueTraced): JSValueTraced =
  var val = res
  if JS_IsException(val):
    wasMoved(val)
    return err()
  myMove(val)

template `?`*(x: JSObjectNil): JSObject =
  var obj = x
  if obj == nil:
    wasMoved(obj)
    return err()
  JSObject(myMove(obj))

template `?`*(res: JSAtom): JSAtom =
  var val = res
  if val == JS_ATOM_NULL:
    wasMoved(val)
    return err()
  myMove(val)

template err*(t: typedesc[JSValue]): JSValue =
  JS_EXCEPTION

template ok*(t: typedesc[JSCode]): JSCode =
  fjOk

template err*(t: typedesc[JSCode]): JSCode =
  fjErr

template toJSValueArray*(a: openArray[JSValue]): JSValueArray =
  if a.len > 0:
    cast[ptr UncheckedArray[JSValue]](unsafeAddr a[0])
  else:
    nil

template toJSValueConstArray*(a: openArray[JSValue]): JSValueConstArray =
  cast[JSValueConstArray](a.toJSValueArray())

template toJSValueConstArray*(a: openArray[JSValueConst]): JSValueConstArray =
  if a.len > 0:
    cast[ptr UncheckedArray[JSValueConst]](unsafeAddr a[0])
  else:
    nil

template toJSValueConstOpenArray*(a: openArray[JSValue]):
    openArray[JSValueConst] =
  a.toJSValueConstArray().toOpenArray(0, a.high)

# This must be a template, because we're taking the address of the passed
# value, and Nim is pass-by-value.
template toJSValueArray*(a: JSValue): JSValueArray =
  cast[JSValueArray](unsafeAddr a)

template toJSValueConstArray*(a: JSValue): JSValueConstArray =
  cast[JSValueConstArray](unsafeAddr a)

template toJSValueConstArray*(a: JSValueConst): JSValueConstArray =
  cast[JSValueConstArray](unsafeAddr a)

proc freeValues*(rt: JSRuntime; vals: openArray[JSValue]) =
  ## Free each individual value in `vals`.
  for val in vals:
    JS_FreeValueRT(rt, val)

proc freeValues*(ctx: JSContext; vals: openArray[JSValue]) =
  ## Free each individual value in `vals`.
  for val in vals:
    JS_FreeValue(ctx, val)

proc call*(ctx: JSContext; funcObj, this: JSValueConst;
    argv: varargs[JSValueConst]): JSValue =
  ## Call `funcObj` with the this value `this` and parameters `argv`.
  JS_Call(ctx, funcObj, this, cast[cint](argv.len), argv.toJSValueConstArray())

proc call*(ctx: JSContext; funcObj: JSCallback; this: JSValueConst;
    argv: varargs[JSValueConst]): JSValue =
  ## Call `funcObj` with the this value `this` and parameters `argv`.
  JS_Call(ctx, funcObj.value, this, cast[cint](argv.len),
    argv.toJSValueConstArray())

proc callSink*(ctx: JSContext; funcObj: JSCallback; this: JSValueConst;
    argv: varargs[JSValue]): JSValue =
  ## Call `funcObj` with the this value `this` and parameters `argv`, then
  ## free each element of `argv`.
  let res = JS_Call(ctx, funcObj.value, this, cast[cint](argv.len),
    argv.toJSValueConstArray())
  ctx.freeValues(argv)
  res

proc callSinkThis*(ctx: JSContext; funcObj: JSCallback; this: JSValue;
    argv: varargs[JSValue]): JSValue =
  ## Call `funcObj` with the this value `this` and parameters `argv`, then
  ## free each element of `argv` as well as `this`.
  let res = ctx.callSink(funcObj, this, argv)
  JS_FreeValue(ctx, this)
  res

proc invoke*(ctx: JSContext; val: JSObject; atom: JSAtom;
    argv: varargs[JSValueConst]): JSValue =
  ## Invoke the function named `atom` on `val`.
  JS_Invoke(ctx, val.value, atom, cast[cint](argv.len),
    argv.toJSValueConstArray())

proc toUndefined*(ctx: JSContext; val: JSValue): JSValue =
  ## Free JSValue, and return JS_EXCEPTION if it's an exception (or
  ## undefined otherwise).
  if JS_IsException(val):
    return JS_EXCEPTION
  JS_FreeValue(ctx, val)
  return JS_UNDEFINED

proc newArrayFrom*(ctx: JSContext; vals: varargs[JSValue]): JSValue =
  ## Create a new array consisting of `vals`.
  ##
  ## Frees/consumes each individual value in `vals`.
  if int64(vals.len) > int64(uint32.high):
    ctx.freeValues(vals)
    return JS_ThrowRangeError(ctx, "sequence too large")
  var obj = JS_NewArray(ctx)
  if JS_IsException(obj):
    return obj
  var u = 0u32
  let L = uint32(vals.len)
  while u < L:
    let res = JS_SetPropertyUint32(ctx, obj, u, vals[u])
    inc u
    if res < 0:
      JS_FreeValue(ctx, obj)
      obj = JS_EXCEPTION
      break
  while u < L:
    JS_FreeValue(ctx, vals[u])
    inc u
  return obj

proc newPromiseCapability*(ctx: JSContext; resolve, reject: var JSCallback):
    JSValue =
  var funs {.noinit.}: array[2, JSValue]
  let res = JS_NewPromiseCapability(ctx, funs.toJSValueArray())
  if not JS_IsException(res):
    resolve = traceCallback(funs[0])
    reject = traceCallback(funs[1])
  res

proc enqueueJob*(ctx: JSContext; fun: JSJobFunc;
    argv: varargs[JSValueConst]): JSCode =
  if JS_EnqueueJob(ctx, fun, cint(argv.len), argv.toJSValueConstArray()) < 0:
    return fjErr
  fjOk

proc rejectJob(ctx: JSContext; argc: cint; argv: JSValueConstArray):
    JSValue {.cdecl.} =
  return ctx.call(argv[0], JS_UNDEFINED, argv[1])

proc enqueueRejection*(ctx: JSContext; reject: JSValue): JSCode =
  ## Usage: throw an exception, then call queueRejection with the reject fun.
  ## reject is freed.
  let ex = JS_GetException(ctx)
  let code = ctx.enqueueJob(rejectJob, reject, ex)
  JS_FreeValue(ctx, reject)
  JS_FreeValue(ctx, ex)
  code

proc newRejectedPromise*(ctx: JSContext): JSValue =
  ## Usage: throw an exception, then create the rejected promise.
  let ex = JS_GetException(ctx)
  var resolve: JSCallback
  var reject: JSCallback
  let res = ctx.newPromiseCapability(resolve, reject)
  if JS_IsException(res):
    JS_FreeValue(ctx, ex)
    return res
  let code = ctx.enqueueJob(rejectJob, reject.value, ex)
  JS_FreeValue(ctx, ex)
  if code == fjErr:
    JS_FreeValue(ctx, res)
    return JS_EXCEPTION
  return res

proc getProperty*(ctx: JSContext; this: JSValueConst; name: JSStrRef):
    JSValue =
  JS_GetProperty(ctx, this, ctx.getAtom(name))

proc getProperty*(ctx: JSContext; this: JSValueConst; name: JSSymbolRef):
    JSValue =
  JS_GetProperty(ctx, this, ctx.getAtom(name))

proc deleteProperty*(ctx: JSContext; this: JSObject; name: JSSymbolRef):
    JSCode =
  if JS_DeleteProperty(ctx, this.value, ctx.getAtom(name), 0) < 0:
    return fjErr
  fjOk

proc defineProperty*(ctx: JSContext; this: JSValueConst; name: JSAtom;
    prop: JSValue; flags = cint(0)): JSCode =
  ## Frees/consumes `prop'.
  if JS_DefinePropertyValue(ctx, this, name, prop, flags) < 0:
    return fjErr
  fjOk

proc definePropertyC*(ctx: JSContext; this: JSValueConst; name: JSAtom;
    prop: JSValue): JSCode =
  ## Define a configurable property on `this`.
  ##
  ## Frees `prop'.
  ctx.defineProperty(this, name, prop, JS_PROP_CONFIGURABLE)

proc definePropertyC*(ctx: JSContext; this: JSValueConst; name: JSSymbolRef;
    prop: JSValue): JSCode =
  ## Define a configurable property on `this`.
  ##
  ## Frees `prop'.
  ctx.defineProperty(this, ctx.getAtom(name), prop, JS_PROP_CONFIGURABLE)

proc defineProperty*(ctx: JSContext; this: JSValueConst; name: cstring;
    prop: JSValue; flags = cint(0)): JSCode =
  ## Define an immutable property on `this`.
  ##
  ## Frees `prop'.
  if JS_DefinePropertyValueStr(ctx, this, name, prop, flags) < 0:
    return fjErr
  fjOk

proc defineProperty*(ctx: JSContext; this: JSValueConst; name: JSStrRef;
    prop: JSValue; flags = cint(0)): JSCode =
  ## Define an immutable property on `this`.
  ##
  ## Frees `prop'.
  if JS_DefinePropertyValue(ctx, this, ctx.getAtom(name), prop, flags) < 0:
    return fjErr
  fjOk

proc definePropertyC*(ctx: JSContext; this: JSValueConst; name: string;
    prop: JSValue): JSCode =
  ## Define a configurable property on `this`.
  ##
  ## Frees `prop'.
  ctx.defineProperty(this, name, prop, JS_PROP_CONFIGURABLE)

proc definePropertyE*(ctx: JSContext; this: JSValueConst; name: string;
    prop: JSValue): JSCode =
  ## Define an enumerable property on `this`.
  ##
  ## Frees `prop'.
  ctx.defineProperty(this, name, prop, JS_PROP_ENUMERABLE)

proc definePropertyCW*(ctx: JSContext; this: JSValueConst; name: JSAtom;
    prop: JSValue): JSCode =
  ## Frees `prop'.
  ctx.defineProperty(this, name, prop, JS_PROP_CONFIGURABLE or JS_PROP_WRITABLE)

proc definePropertyCW*(ctx: JSContext; this: JSValueConst; name: cstring;
    prop: JSValue): JSCode =
  ## Frees `prop'.
  ctx.defineProperty(this, name, prop, JS_PROP_CONFIGURABLE or JS_PROP_WRITABLE)

proc definePropertyCWE*(ctx: JSContext; this: JSValueConst; name: JSAtom;
    prop: JSValue): JSCode =
  ## Frees `prop'.
  ctx.defineProperty(this, name, prop, JS_PROP_C_W_E)

proc definePropertyCWE*(ctx: JSContext; this: JSValueConst; name: JSStrRef;
    prop: JSValue): JSCode =
  ## Frees `prop'.
  ctx.defineProperty(this, ctx.getAtom(name), prop, JS_PROP_C_W_E)

proc definePropertyGetSetCE*(ctx: JSContext; this: JSValueConst; name: cstring;
    getter: JSGetterMagicFunction; setter: JSSetterMagicFunction; magic: cint):
    JSCode =
  let prop = ?JS_NewAtom(ctx, cstringConst(name))
  var f: JSCFunctionType
  f.getter_magic = getter
  let getterVal = JS_NewCFunction2(ctx, f.generic, cstringConst(name), 0,
    JS_CFUNC_getter_magic, magic)
  if JS_IsException(getterVal):
    return fjErr
  var setterVal = JS_UNDEFINED
  if setter != nil:
    f.setter_magic = setter
    setterVal = JS_NewCFunction2(ctx, f.generic, cstringConst(name), 1,
      JS_CFUNC_setter_magic, magic)
    if JS_IsException(setterVal):
      JS_FreeValue(ctx, getterVal)
      return fjErr
  if JS_DefinePropertyGetSet(ctx, this, prop, getterVal, setterVal,
      JS_PROP_CONFIGURABLE or JS_PROP_ENUMERABLE) < 0:
    return fjErr
  fjOk

proc strictEquals*(ctx: JSContext; a, b: JSValueConst): bool =
  ## Returns true if `a === b', false otherwise.
  JS_StrictEq(ctx, a, b) != 0

proc sameValue*(ctx: JSContext; a, b: JSValueConst): bool =
  JS_SameValue(ctx, a, b) != 0

proc addRow(s: var string; title: string; count, size, sz2, cnt2: int64;
    name: string) =
  let d = cdouble(sz2) / cdouble(cnt2)
  let dn = js_dtoa_max_len(d, 10, 1, JS_DTOA_FORMAT_FIXED)
  var buf = newString(dn)
  var tmp: JSDTOATempMem
  let len = js_dtoa(cstring(buf), d, 10, 1, JS_DTOA_FORMAT_FIXED, tmp)
  buf.setLen(int(len))
  s &= title & ": " & $count & " " & $size & " (" & buf & ")" & name & "\n"

proc addRow(s: var string; title: string; count, size, sz2: int64;
    name: string) =
  s.addRow(title, count, size, sz2, count, name)

proc addRow(s: var string; title: string; count, size: int64; name: string) =
  s.addRow(title, count, size, size, name)

proc getMemoryUsage*(rt: JSRuntime): string =
  ## Prints a formatted message of the current memory usage.
  ## This wraps `JS_ComputeMemoryUsage`.
  var m: JSMemoryUsage
  JS_ComputeMemoryUsage(rt, m)
  var s = ""
  if m.malloc_count != 0:
    s.addRow("memory allocated", m.malloc_count, m.malloc_size, "/block")
    s.addRow("memory used", m.memory_used_count, m.memory_used_size,
      m.malloc_size - m.memory_used_size, " average slack")
  if m.atom_count != 0:
    s.addRow("atoms", m.atom_count, m.atom_size, "/atom")
  if m.str_count != 0:
    s.addRow("strings", m.str_count, m.str_size, "/string")
  if m.obj_count != 0:
    s.addRow("objects", m.obj_count, m.obj_size, "/object")
    s.addRow("properties", m.prop_count, m.prop_size, m.prop_size, m.obj_count,
      "/object")
    s.addRow("shapes", m.shape_count, m.shape_size, "/shape")
  if m.js_func_count != 0:
    s.addRow("js functions", m.js_func_count, m.js_func_size, "/function")
  if m.c_func_count != 0:
    s &= "native functions: " & $m.c_func_count & "\n"
  if m.array_count != 0:
    s &= "arrays: " & $m.array_count & "\n" &
      "fast arrays: " & $m.fast_array_count & "\n"
    s.addRow("fast array elements", m.fast_array_elements,
        m.fast_array_elements * sizeof(JSValue), m.fast_array_elements,
        m.fast_array_count, "")
  if m.binary_object_count != 0:
    s &= "binary objects: " & $m.binary_object_count & " " &
      $m.binary_object_size
  move(s)

proc eval*(ctx: JSContext; s: string; file = "<input>";
    evalFlags = JS_EVAL_TYPE_GLOBAL): JSValue =
  ## Wrapper around JS_Eval.
  return JS_Eval(ctx, s.toCStringConst, csize_t(s.len), file.toCStringConst,
    evalFlags)

proc compileScript*(ctx: JSContext; s: string; file = "<input>"): JSValue =
  ## Compiles `s` into bytecode.
  ## You can evaluate the result using `evalFunction`.
  return ctx.eval(s, file, JS_EVAL_FLAG_COMPILE_ONLY)

proc compileModule*(ctx: JSContext; s: string; file = "<input>"): JSValue =
  ## Compiles `s` into a module.
  ##
  ## I forgot how to use this, check quickjs-libc.c in the original
  ## distribution if you're interested.
  return ctx.eval(s, file, JS_EVAL_TYPE_MODULE or JS_EVAL_FLAG_COMPILE_ONLY)

proc evalFunction*(ctx: JSContext; val: JSValue): JSValue =
  ## Evaluates a bytecode function or a module.  This wraps `JS_EvalFunction`.
  return JS_EvalFunction(ctx, val)

proc defineConsts*(ctx: JSContext; classid: JSClassID; consts: typedesc[enum]):
    JSCode =
  ## Define a list of constants expressed as a Nim enum on a class.
  let ctxOpaque = ctx.getOpaque()
  if ctxOpaque == nil:
    return fjOk
  let proto = JS_GetClassProto(ctx, classid)
  let ctor = ctx.getOpaque().ctors[int(classid)]
  var res = fjOk
  for e in consts:
    let s = $e
    res = ctx.definePropertyE(proto, s, JS_NewUint32(ctx, uint32(e)))
    if res != fjOk:
      break
    res = ctx.definePropertyE(ctor.value, s, JS_NewUint32(ctx, uint32(e)))
    if res != fjOk:
      break
  JS_FreeValue(ctx, proto)
  res

proc setPropertyFunctionList*(ctx: JSContext; val: JSObject;
    funcs: openArray[JSCFunctionListEntry]): JSCode =
  if funcs.len > 0:
    let fp = cast[JSCFunctionListP](unsafeAddr funcs[0])
    if JS_SetPropertyFunctionList(ctx, val.value, fp, cint(funcs.len)) < 0:
      return fjErr
  fjOk

proc setUnforgeable*(ctx: JSContext; obj: JSObject; class: JSClassID): JSCode =
  let rtOpaque = JS_GetRuntime(ctx).getOpaque()
  let iclass = int(class)
  if iclass < rtOpaque.classes.len:
    ?ctx.setPropertyFunctionList(obj, rtOpaque.classes[iclass].unforgeable)
  fjOk

proc uninitIfNull*(val: JSValue): JSValue =
  if JS_IsNull(val):
    return JS_UNINITIALIZED
  return val

proc getExceptionMsg*(ctx: JSContext): string =
  ## Converts the current exception to a string.
  result = ""
  let ex = JS_GetException(ctx)
  var plen: csize_t
  let outp = JS_ToCStringLen(ctx, plen, ex) # cstring
  if outp != nil:
    if plen > 0:
      result.setLen(plen)
      copyMem(addr result[0], cstring(outp), plen)
    JS_FreeCString(ctx, outp)
    result &= '\n'
  let stack = JS_GetPropertyStr(ctx, ex, "stack")
  JS_FreeValue(ctx, ex)
  if not JS_IsUndefined(stack):
    let outp = JS_ToCStringLen(ctx, plen, stack) # cstring
    if outp != nil:
      if plen > 0:
        let olen = result.len
        result.setLen(csize_t(olen) + plen)
        copyMem(addr result[olen], cstring(outp), plen)
      JS_FreeCString(ctx, outp)
  JS_FreeValue(ctx, stack)

proc runJSJobs*(rt: JSRuntime): JSContext =
  ## Returns the first JSContext that threw an exception, or nil if no
  ## exception was thrown.
  while JS_IsJobPending(rt) != 0:
    var ctx: JSContext
    let r = JS_ExecutePendingJob(rt, ctx)
    if r == -1:
      return ctx
  nil

proc toIntIndex*(ctx: JSContext; value: JSValue): int =
  ## Convert value to an index that is guaranteed to be smaller than
  ## uint32.high or int.high (on 32-bit systems).
  ##
  ## Returns -1 on exception.
  var tmp {.noinit.}: uint64
  let lenOk = JS_ToIndex(ctx, tmp, value)
  JS_FreeValue(ctx, value)
  if lenOk < 0:
    return -1
  if tmp > uint64(int.high) or tmp > uint32.high:
    JS_ThrowInternalError(ctx, "index out of acceptable range")
    return -1
  int(tmp)

proc toObject*(ctx: JSContext; val: JSValueConst): JSValue =
  ## Roundabout way to invoke ToObject.
  let fun = ctx.getOpaque().valRefs[jsvObjectPrototypeValueOf]
  JS_Call(ctx, fun, val, 0, nil)

proc JS_ThrowTypeErrorInvalidClass*(ctx: JSContext; classid: JSClassID):
    JSValue {.discardable.} =
  ## Roundabout way to invoke JS_ThrowTypeErrorInvalidClass.
  discard JS_GetOpaque2(ctx, JS_UNDEFINED, classid)
  return JS_EXCEPTION

proc newObject*(ctx: JSContext): JSObjectNil =
  let obj = JS_NewObject(ctx)
  if JS_IsException(obj):
    return JSObjectNil(nil)
  JSObjectNil(traceObj(obj))

proc newObjectProto*(ctx: JSContext; proto: JSValueConst): JSObjectNil =
  let obj = JS_NewObjectProto(ctx, proto)
  if JS_IsException(obj):
    return JSObjectNil(nil)
  JSObjectNil(traceObj(obj))

proc newObjectClass*(ctx: JSContext; class: JSClassID): JSObjectNil =
  let obj = JS_NewObjectClass(ctx, class)
  if JS_IsException(obj):
    return JSObjectNil(nil)
  JSObjectNil(traceObj(obj))

proc newObjectFromCtor*(ctx: JSContext; ctor: JSValueConst;
    classid: JSClassID): JSObjectNil =
  let obj = JS_NewObjectFromCtor(ctx, ctor, classid)
  if JS_IsException(obj):
    return JSObjectNil(nil)
  JSObjectNil(traceObj(obj))

proc newGetterFunctionData*(ctx: JSContext; fun: JSCFunctionData;
    name: cstring; magic: cint; data: varargs[JSValueConst]): JSValue =
  let getter = JS_NewCFunctionData(ctx, fun, 0, magic, cint(data.len),
    data.toJSValueConstArray())
  if JS_IsException(getter):
    return JS_EXCEPTION
  let getName = JS_NewString(ctx, cstring("get " & $name))
  if JS_IsException(getName):
    JS_FreeValue(ctx, getter)
    return JS_EXCEPTION
  if ctx.definePropertyC(getter, ctx.getAtom(jstName), getName) == fjErr:
    JS_FreeValue(ctx, getter)
    return JS_EXCEPTION
  return getter

proc callUserObject*(ctx: JSContext; callback: JSObject; name: JSStrRef;
    this, arg: JSValueConst): JSValue =
  #TODO switch the context as the spec mandates
  # must dup the callback first, otherwise the function might delete the
  # callback itself
  let callback = ctx.dup(callback)
  let ret = if JS_IsFunction(ctx, callback):
    ctx.call(JSCallback(callback), this, arg)
  else:
    ctx.invoke(callback, ctx.getAtom(name), arg)
  ret

proc serialize*(ctx: JSContext; val: JSValueConst): Opt[seq[uint8]] =
  #TODO we'll have to do something about [Serializable] too
  var plens: csize_t
  let pres = JS_WriteObject(ctx, plens, val, 0)
  if pres == nil:
    return err()
  let plen = cast[int](plens)
  var res = newSeqUninit[uint8](plen)
  if plen > 0:
    copyMem(addr res[0], pres, plen)
  ok(move(res))

proc deserialize*(ctx: JSContext; s: openArray[uint8]): JSValue =
  return JS_ReadObject(ctx, unsafeAddr s[0], csize_t(s.len), 0)

proc setImportMeta*(ctx: JSContext; funcVal: JSValueConst; isMain: bool):
    JSCode =
  let m = cast[JSModuleDef](JS_VALUE_GET_PTR(funcVal))
  let moduleNameAtom = JS_GetModuleName(ctx, m)
  let metaObj = ?trace(JS_GetImportMeta(ctx, m))
  ?ctx.definePropertyCWE(metaObj.v, jstUrl,
    JS_AtomToValue(ctx, moduleNameAtom))
  ?ctx.definePropertyCWE(metaObj.v, jstMain, JS_NewBool(ctx, JS_BOOL(isMain)))
  fjOk

proc finishLoadModule*(ctx: JSContext; funcVal: JSValue; name: string):
    JSModuleDef =
  if ctx.setImportMeta(funcVal, false) == fjErr:
    return nil
  # "the module is already referenced, so we must free it"
  # it seems QJS treats the return value as a const
  let m = cast[JSModuleDef](JS_VALUE_GET_PTR(funcVal))
  JS_FreeValue(ctx, funcVal)
  m

{.pop.} # raises
