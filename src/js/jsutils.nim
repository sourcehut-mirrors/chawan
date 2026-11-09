## Miscellaneous wrappers around QJS functions.

{.push raises: [].}

when NimMajor >= 2:
  import std/assertions

import js/constcharp
import js/cutils
import js/dtoa
import js/jsopaque
import js/jstypes
import js/quickjs
import utils/cowstr
import utils/opt
import utils/twtstr

type JSCode* = enum
  fjErr, fjOk

template `?`*(res: JSCode) =
  if res == fjErr:
    return err()

template myMove(x: untyped): untyped =
  when (NimMajor, NimMinor, NimPatch) < (2, 2, 2):
    move(x)
  else:
    ensureMove(x)

template `?`*(res: JSValueTraced): JSValueTraced =
  var val = res
  if JS_IsException(val):
    wasMoved(val)
    return err()
  myMove(val)

template `?`*(res: JSAtom): JSAtom =
  var val = res
  if val == JS_ATOM_NULL:
    wasMoved(val)
    return err()
  myMove(val)

template `?`*(res: JSObjectErr): JSObject =
  var val = res
  if val.isErr:
    wasMoved(val)
    return err()
  JSObject(myMove(val))

template err*(t: typedesc[JSValue]): JSValue =
  JS_EXCEPTION

template ok*(t: typedesc[JSCode]): JSCode =
  fjOk

template err*(t: typedesc[JSCode]): JSCode =
  fjErr

template err*(t: typedesc[JSObjectErr]): JSObjectErr =
  JSObjectErr(nil)

template toJSValueArray*(a: openArray[JSValue]): JSValueArray =
  if a.len > 0:
    cast[ptr UncheckedArray[JSValue]](unsafeAddr a[0])
  else:
    nil

template toJSValueConstArray*(a: openArray[JSValue]): JSValueConstArray =
  cast[JSValueConstArray](a.toJSValueArray())

template toJSValueConstArray*(a: openArray[JSValueConst]): JSValueConstArray =
  if a.len > 0:
    cast[JSValueConstArray](unsafeAddr a[0])
  else:
    nil

template toJSValueConstArray*(a: openArray[JSValueTraced]): JSValueConstArray =
  if a.len > 0:
    cast[JSValueConstArray](unsafeAddr a[0])
  else:
    nil

template toJSValueConstOpenArray*(a: openArray[JSValue]):
    openArray[JSValueConst] =
  a.toJSValueConstArray().toOpenArray(0, a.high)

template toJSValueConstOpenArray*(a: openArray[JSValueTraced]):
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

proc freeValues*(ctx: JSContext; vals: openArray[JSValue]) =
  ## Free each individual value in `vals`.
  for val in vals:
    JS_FreeValue(ctx, val)

proc call*(ctx: JSContext; funcObj, this: JSValueConst;
    argv: varargs[JSValueConst]): JSValue =
  ## Call `funcObj` with the this value `this` and parameters `argv`.
  JS_Call(ctx, funcObj, this, cast[cint](argv.len), argv.toJSValueConstArray())

proc call*(ctx: JSContext; funcObj: sink JSCallback; this: JSValueConst;
    argv: varargs[JSValueConst]): JSValue =
  ## Call `funcObj` with the this value `this` and parameters `argv`.
  ##
  ## Note: funcObj is marked sink to bypass the footgun where code
  ## running in JS_Call can unref funcObj itself (e.g. if funcObj is a
  ## member of an object that JS_Call deallocates).
  JS_Call(ctx, funcObj.value, this, cast[cint](argv.len),
    argv.toJSValueConstArray())

proc callSink*(ctx: JSContext; funcObj: sink JSCallback; this: JSValueConst;
    argv: varargs[JSValue]): JSValue =
  ## Call `funcObj` with the this value `this` and parameters `argv`, then
  ## free each element of `argv`.
  let res = JS_Call(ctx, funcObj.value, this, cast[cint](argv.len),
    argv.toJSValueConstArray())
  ctx.freeValues(argv)
  res

proc invoke*(ctx: JSContext; val: JSObject; atom: JSAtom;
    argv: varargs[JSValueConst]): JSValue =
  ## Invoke the function named `atom` on `val`.
  JS_Invoke(ctx, val.value, atom, cast[cint](argv.len),
    argv.toJSValueConstArray())

proc callConstructor*(ctx: JSContext; funcObj: sink JSCallback;
    params: openArray[JSValueConst]): JSValue =
  JS_CallConstructor(ctx, funcObj.value, cint(params.len),
    params.toJSValueConstArray())

proc newArrayFrom*(ctx: JSContext; vals: varargs[JSValue]): JSValue =
  ## Create a new array consisting of `vals`.
  ##
  ## Frees/consumes each individual value in `vals`.
  if int64(vals.len) > int64(cint.high):
    ctx.freeValues(vals)
    return JS_ThrowRangeError(ctx, "sequence too large")
  let p = if vals.len > 0: cast[JSValueArray](unsafeAddr vals[0]) else: nil
  return JS_NewArrayFrom(ctx, cast[cint](vals.len), p)

proc newPromiseCapability*(ctx: JSContext; resolve, reject: var JSCallback):
    JSObjectErr =
  var funs {.noinit.}: array[2, JSValue]
  let res = JS_NewPromiseCapability(ctx, funs.toJSValueArray())
  if JS_IsException(res.vc):
    return err()
  resolve = traceCallback(funs[0])
  reject = traceCallback(funs[1])
  JSObjectErr(traceObj(res))

proc enqueueJob*(ctx: JSContext; fun: JSJobFunc;
    argv: varargs[JSValueConst]): JSCode =
  if JS_EnqueueJob(ctx, fun, cint(argv.len), argv.toJSValueConstArray()) < 0:
    return fjErr
  fjOk

proc rejectJob(ctx: JSContext; argc: cint; argv: JSValueConstArray):
    JSValue {.cdecl.} =
  return ctx.call(argv[0], JS_UNDEFINED.vc, argv[1])

proc enqueueRejection*(ctx: JSContext; reject: JSCallback): JSCode =
  ## Usage: throw an exception, then call queueRejection with the reject fun.
  ## reject is freed.
  let ex = JS_GetException(ctx)
  let code = ctx.enqueueJob(rejectJob, reject.value, ex.vc)
  JS_FreeValue(ctx, ex)
  code

proc newRejectedPromise*(ctx: JSContext): JSObjectErr =
  ## Usage: throw an exception, then create the rejected promise.
  let ex = trace(JS_GetException(ctx))
  var resolve: JSCallback
  var reject: JSCallback
  let res = ?ctx.newPromiseCapability(resolve, reject)
  ?ctx.enqueueJob(rejectJob, reject.value, ex.vc)
  return JSObjectErr(res)

proc newCFunction2*(ctx: JSContext; fun: JSCFunction; name: cstring;
    length: cint; cproto: JSCFunctionEnum; magic: cint): Opt[JSCallback] =
  let fun = JS_NewCFunction2(ctx, fun, cstringConst(name), length,
    cproto, magic)
  if JS_IsException(fun.vc):
    return err()
  ok(traceCallback(fun))

proc newCFunction*(ctx: JSContext; fun: JSCFunction; name: cstring;
    length: cint): Opt[JSCallback] =
  ctx.newCFunction2(fun, name, length, JS_CFUNC_generic, 0)

proc getProperty*(ctx: JSContext; this: JSValueConst; name: JSStrRef):
    JSValueTraced =
  trace(JS_GetProperty(ctx, this, ctx.getAtom(name)))

proc getProperty*(ctx: JSContext; this: JSObject; name: JSStrRef):
    JSValueTraced =
  ctx.getProperty(this.value, name)

proc deleteProperty*(ctx: JSContext; this: JSObject; name: JSStrRef):
    JSCode =
  if JS_DeleteProperty(ctx, this.value, ctx.getAtom(name), 0) < 0:
    return fjErr
  fjOk

proc defineProperty*(ctx: JSContext; this: JSObject; name: JSAtom;
    prop: JSValue; flags = cint(0)): JSCode =
  ## Frees/consumes `prop'.
  if JS_DefinePropertyValue(ctx, this.value, name, prop, flags) < 0:
    return fjErr
  fjOk

proc defineProperty*(ctx: JSContext; this: JSObject; name: cstring;
    prop: JSValue; flags = cint(0)): JSCode =
  ## Define an immutable property on `this`.
  ##
  ## Frees `prop'.
  if JS_DefinePropertyValueStr(ctx, this.value, name, prop, flags) < 0:
    return fjErr
  fjOk

proc defineProperty*(ctx: JSContext; this: JSObject; name: JSStrRef;
    prop: JSValue; flags = cint(0)): JSCode =
  ## Define an immutable property on `this`.
  ##
  ## Frees `prop'.
  if JS_DefinePropertyValue(ctx, this.value, ctx.getAtom(name), prop,
      flags) < 0:
    return fjErr
  fjOk

proc definePropertyC*(ctx: JSContext; this: JSObject; name: JSStrRef;
    prop: JSValue): JSCode =
  ## Define a configurable property on `this`.
  ##
  ## Frees `prop'.
  ctx.defineProperty(this, name, prop, JS_PROP_CONFIGURABLE)

proc definePropertyE*(ctx: JSContext; this: JSObject; name: Str;
    prop: JSValue): JSCode =
  ## Define an enumerable property on `this`.
  ##
  ## Frees `prop'.
  ctx.defineProperty(this, cstring(name.toCStringConst()), prop,
    JS_PROP_ENUMERABLE)

proc definePropertyCW*(ctx: JSContext; this: JSObject; name: cstring;
    prop: JSValue): JSCode =
  ## Frees `prop'.
  ctx.defineProperty(this, name, prop,
    JS_PROP_CONFIGURABLE or JS_PROP_WRITABLE)

proc definePropertyCW*(ctx: JSContext; this: JSObject; name: JSStrRef;
    prop: JSValue): JSCode =
  ## Frees `prop'.
  ctx.defineProperty(this, name, prop,
    JS_PROP_CONFIGURABLE or JS_PROP_WRITABLE)

proc definePropertyCWE*(ctx: JSContext; this: JSObject; name: JSStrRef;
    prop: JSValue): JSCode =
  ## Frees `prop'.
  ctx.defineProperty(this, name, prop, JS_PROP_C_W_E)

proc definePropertyGetSetCE*(ctx: JSContext; this: JSObject; name: cstring;
    getter: JSGetterMagicFunction; setter: JSSetterMagicFunction; magic: cint):
    JSCode =
  let prop = ?JS_NewAtom(ctx, cstringConst(name))
  var f: JSCFunctionType
  f.getter_magic = getter
  let getterVal = ?ctx.newCFunction2(f.generic, name, 0, JS_CFUNC_getter_magic,
    magic)
  var setterVal = JS_UNDEFINED
  if setter != nil:
    f.setter_magic = setter
    setterVal = JS_NewCFunction2(ctx, f.generic, cstringConst(name), 1,
      JS_CFUNC_setter_magic, magic)
    if JS_IsException(setterVal.vc):
      return fjErr
  if JS_DefinePropertyGetSet(ctx, this.value, prop, getterVal.toJSValue(),
      setterVal, JS_PROP_CONFIGURABLE or JS_PROP_ENUMERABLE) < 0:
    return fjErr
  fjOk

proc strictEquals*(ctx: JSContext; a, b: JSValueConst): bool =
  ## Returns true if `a === b', false otherwise.
  JS_StrictEq(ctx, a, b) != 0

proc sameValue*(ctx: JSContext; a, b: JSValueConst): bool =
  JS_SameValue(ctx, a, b) != 0

proc addRow(s: var Growbuf; title: Str; count, size, sz2, cnt2: int64;
    name: Str) =
  let d = cdouble(sz2) / cdouble(cnt2)
  let dn = js_dtoa_max_len(d, 10, 1, JS_DTOA_FORMAT_FIXED)
  var buf = initGrowbufUninit(dn)
  var tmp: JSDTOATempMem
  let len = js_dtoa(cast[cstring](buf.p), d, 10, 1, JS_DTOA_FORMAT_FIXED, tmp)
  buf.setLen(int(len))
  s.addM(title, ": ", count, ' ', size, " (", buf, ')', name, '\n')

proc addRow(s: var Growbuf; title: Str; count, size, sz2: int64; name: Str) =
  s.addRow(title, count, size, sz2, count, name)

proc addRow(s: var Growbuf; title: Str; count, size: int64; name: Str) =
  s.addRow(title, count, size, size, name)

proc getMemoryUsage*(rt: JSRuntime): Str =
  ## Prints a formatted message of the current memory usage.
  ## This wraps `JS_ComputeMemoryUsage`.
  var m: JSMemoryUsage
  JS_ComputeMemoryUsage(rt, m)
  var s = initGrowbuf()
  if m.malloc_count != 0:
    s.addRow(str("memory allocated"), m.malloc_count, m.malloc_size,
      str("/block"))
    s.addRow(str("memory used"), m.memory_used_count, m.memory_used_size,
      m.malloc_size - m.memory_used_size, str(" average slack"))
  if m.atom_count != 0:
    s.addRow(str("atoms"), m.atom_count, m.atom_size, str("/atom"))
  if m.str_count != 0:
    s.addRow(str("strings"), m.str_count, m.str_size, str("/string"))
  if m.obj_count != 0:
    s.addRow(str("objects"), m.obj_count, m.obj_size, str("/object"))
    s.addRow(str("properties"), m.prop_count, m.prop_size, m.prop_size,
      m.obj_count, str("/object"))
    s.addRow(str("shapes"), m.shape_count, m.shape_size, str("/shape"))
  if m.js_func_count != 0:
    s.addRow(str("js functions"), m.js_func_count, m.js_func_size,
      str("/function"))
  if m.c_func_count != 0:
    s.addM("native functions: ", m.c_func_count, '\n')
  if m.array_count != 0:
    s.addM("arrays: ", m.array_count, '\n', "fast arrays: ",
      m.fast_array_count, '\n')
    s.addRow(str("fast array elements"), m.fast_array_elements,
        m.fast_array_elements * sizeof(JSValue), m.fast_array_elements,
        m.fast_array_count, str(""))
  if m.binary_object_count != 0:
    s.addM("binary objects: ", m.binary_object_count, ' ',
      m.binary_object_size)
  s.toStr()

proc eval*(ctx: JSContext; s: Str; file = str("<input>");
    evalFlags = JS_EVAL_TYPE_GLOBAL): JSValue =
  ## Wrapper around JS_Eval.
  return JS_Eval(ctx, s.toCStringConst, csize_t(s.len), file.toCStringConst,
    evalFlags)

proc compileScript*(ctx: JSContext; s: Str; file = str("<input>")): JSValue =
  ## Compiles `s` into bytecode.
  ## You can evaluate the result using `evalFunction`.
  return ctx.eval(s, file, JS_EVAL_FLAG_COMPILE_ONLY)

proc compileModule*(ctx: JSContext; s: Str; file = str("<input>")): JSValue =
  ## Compiles `s` into a module.
  ##
  ## I forgot how to use this, check quickjs-libc.c in the original
  ## distribution if you're interested.
  return ctx.eval(s, file, JS_EVAL_TYPE_MODULE or JS_EVAL_FLAG_COMPILE_ONLY)

proc evalFunction*(ctx: JSContext; val: JSValue): JSValueTraced =
  ## Evaluates a bytecode function or a module.  This wraps `JS_EvalFunction`.
  return trace(JS_EvalFunction(ctx, val))

proc getClassProto*(ctx: JSContext; classid: JSClassID): JSObject =
  let proto = JS_GetClassProto(ctx, classid)
  assert JS_IsObject(proto.vc)
  traceObj(proto)

proc defineConsts*(ctx: JSContext; classid: JSClassID; consts: typedesc[enum]):
    JSCode =
  ## Define a list of constants expressed as a Nim enum on a class.
  let ctxOpaque = ctx.getOpaque()
  if ctxOpaque == nil:
    return fjOk
  let proto = ctx.getClassProto(classid)
  let ctor = ctx.getOpaque().ctors[int(classid)]
  var res = fjOk
  for e in consts:
    res = ctx.definePropertyE(proto, e.toStr(), JS_NewUint32(ctx, uint32(e)))
    if res != fjOk:
      break
    res = ctx.definePropertyE(ctor, e.toStr(), JS_NewUint32(ctx, uint32(e)))
    if res != fjOk:
      break
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
  if JS_IsNull(val.vc):
    return JS_UNINITIALIZED
  return val

proc getExceptionMsg*(ctx: JSContext): Str =
  ## Converts the current exception to a string.
  var buf = initGrowbuf()
  let ex = JS_GetException(ctx)
  var len: csize_t
  let outp = JS_ToCStringLen(ctx, len, ex.vc) # cstring
  if outp != nil:
    buf &= initQJSStr(cstring(outp), cast[int](len)) # free's outp
    buf &= '\n'
  let stack = JS_GetPropertyStr(ctx, ex.vc, cstringConst("stack"))
  JS_FreeValue(ctx, ex)
  if not JS_IsUndefined(stack.vc):
    let outp = JS_ToCStringLen(ctx, len, stack.vc) # cstring
    if outp != nil:
      buf &= initQJSStr(cstring(outp), cast[int](len)) # free's outp
  JS_FreeValue(ctx, stack)
  buf.toStr()

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
  let lenOk = JS_ToIndex(ctx, tmp, value.vc)
  JS_FreeValue(ctx, value)
  if lenOk < 0:
    return -1
  if tmp > uint64(int.high) or tmp > uint32.high:
    JS_ThrowInternalError(ctx, "index out of acceptable range")
    return -1
  int(tmp)

proc tryTraceObj*(val: JSValue): JSObjectErr =
  if JS_IsException(val.vc):
    return err()
  when defined(debug):
    assert JS_IsObject(val.vc)
  JSObjectErr(traceObj(val))

proc toObject*(ctx: JSContext; val: JSValueConst): JSObjectErr =
  let res = JS_ToObject(ctx, val)
  tryTraceObj(res)

proc JS_ThrowTypeErrorInvalidClass*(ctx: JSContext; classid: JSClassID):
    JSValue {.discardable.} =
  ## Roundabout way to invoke JS_ThrowTypeErrorInvalidClass.
  discard JS_GetOpaque2(ctx, JS_UNDEFINED.vc, classid)
  return JS_EXCEPTION

proc newObject*(ctx: JSContext): JSObjectErr =
  let obj = JS_NewObject(ctx)
  tryTraceObj(obj)

proc newObjectProto*(ctx: JSContext; proto: JSValueConst): JSObjectErr =
  let obj = JS_NewObjectProto(ctx, proto)
  tryTraceObj(obj)

proc newObjectClass*(ctx: JSContext; class: JSClassID): JSObjectErr =
  let obj = JS_NewObjectClass(ctx, class)
  tryTraceObj(obj)

proc newObjectFromCtor*(ctx: JSContext; ctor: JSValueConst;
    classid: JSClassID): JSObjectErr =
  let obj = JS_CreateFromConstructor(ctx, ctor, classid)
  tryTraceObj(obj)

proc newCFunctionData*(ctx: JSContext; fun: JSCFunctionData; name: cstring;
    length, magic: cint; data: varargs[JSValueConst]): Opt[JSCallback] =
  let funVal = JS_NewCFunctionData(ctx, fun, length, magic, cint(data.len),
    data.toJSValueConstArray())
  if JS_IsException(funVal.vc):
    return err()
  let fun = traceCallback(funVal)
  let nameVal = JS_NewString(ctx, name)
  if JS_IsException(nameVal.vc) or
      ctx.definePropertyC(JSObject(fun), jstName, nameVal) == fjErr:
    return err()
  ok(fun)

proc newGetterFunctionData*(ctx: JSContext; fun: JSCFunctionData;
    name: cstring; magic: cint; data: varargs[JSValueConst]): Opt[JSCallback] =
  let name = initStrM("get ", name)
  ctx.newCFunctionData(fun, name.toCString(), 0, magic, data)

proc callUserObject*(ctx: JSContext; callback: JSObject; name: JSStrRef;
    this, arg: JSValueConst): JSValue =
  #TODO switch the context as the spec mandates
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
  chaArrayCopy(res, pres.toOpenArray(0, plen - 1))
  ok(move(res))

proc deserialize*(ctx: JSContext; s: openArray[uint8]): JSValue =
  return JS_ReadObject(ctx, unsafeAddr s[0], csize_t(s.len), 0)

proc getImportMeta(ctx: JSContext; m: JSModuleDef): JSObjectErr =
  let obj = JS_GetImportMeta(ctx, m)
  tryTraceObj(obj)

proc setImportMeta*(ctx: JSContext; funcVal: JSValueConst; isMain: bool):
    JSCode =
  let m = cast[JSModuleDef](JS_VALUE_GET_PTR(funcVal))
  let moduleNameAtom = JS_GetModuleName(ctx, m)
  let metaObj = ?ctx.getImportMeta(m)
  ?ctx.definePropertyCWE(metaObj, jstUrl, JS_AtomToValue(ctx, moduleNameAtom))
  ctx.definePropertyCWE(metaObj, jstMain, JS_NewBool(ctx, JS_BOOL(isMain)))

{.pop.} # raises
