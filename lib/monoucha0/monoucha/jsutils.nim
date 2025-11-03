## Miscellaneous wrappers around QJS functions.

{.push raises: [].}

import dtoa
import jsopaque
import quickjs

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

template toJSValueConstArray*(a: JSValueConst): JSValueConstArray =
  cast[JSValueConstArray](unsafeAddr a)

proc JS_CallFree*(ctx: JSContext; funcObj: JSValue; this: JSValueConst;
    argc: cint; argv: JSValueConstArray): JSValue =
  result = JS_Call(ctx, funcObj, this, argc, argv)
  JS_FreeValue(ctx, funcObj)

proc call*(ctx: JSContext; funcObj, this: JSValueConst;
    argv: varargs[JSValueConst]): JSValue =
  ## Call `funcObj` with the this value `this` and parameters `argv`.
  JS_Call(ctx, funcObj, this, cast[cint](argv.len), argv.toJSValueConstArray())

proc callFree*(ctx: JSContext; funcObj: JSValue; this: JSValueConst;
    argv: varargs[JSValueConst]): JSValue =
  ## Call `funcObj` with the this value `this` and parameters `argv`, then
  ## free `funcObj`.
  JS_CallFree(ctx, funcObj, this, cast[cint](argv.len),
    argv.toJSValueConstArray())

proc toUndefined*(ctx: JSContext; val: JSValue): JSValue =
  ## Free JSValue, and return JS_EXCEPTION if it's an exception (or
  ## undefined otherwise).
  if JS_IsException(val):
    return JS_EXCEPTION
  JS_FreeValue(ctx, val)
  return JS_UNDEFINED

proc freeValues*(ctx: JSContext; vals: openArray[JSValue]) =
  ## Free each individual value in `vals`.
  for val in vals:
    JS_FreeValue(ctx, val)

proc newArrayFrom*(ctx: JSContext; vals: openArray[JSValue]): JSValue =
  ## Create a new array consisting of `vals`.
  ##
  ## Frees/consumes each individual value in `vals`.
  let L = vals.len
  if L > int(cint.high):
    ctx.freeValues(vals)
    return JS_ThrowRangeError(ctx, "sequence too large")
  return JS_NewArrayFrom(ctx, cast[cint](L), vals.toJSValueArray())

type DefinePropertyResult* = enum
  dprException, dprSuccess, dprFail

proc defineProperty*(ctx: JSContext; this: JSValueConst; name: JSAtom;
    prop: JSValue; flags = cint(0)): DefinePropertyResult =
  ## Frees/consumes `prop'.
  return case JS_DefinePropertyValue(ctx, this, name, prop, flags)
  of 0: dprFail
  of 1: dprSuccess
  else: dprException

proc definePropertyC*(ctx: JSContext; this: JSValueConst; name: JSAtom;
    prop: JSValue): DefinePropertyResult =
  ## Define a configurable property on `this`.
  ##
  ## Frees `prop'.
  ctx.defineProperty(this, name, prop, JS_PROP_CONFIGURABLE)

proc defineProperty*(ctx: JSContext; this: JSValueConst; name: string;
    prop: JSValue; flags = cint(0)): DefinePropertyResult =
  ## Define an immutable property on `this`.
  ##
  ## Frees `prop'.
  return case JS_DefinePropertyValueStr(ctx, this, cstring(name), prop, flags)
  of 0: dprFail
  of 1: dprSuccess
  else: dprException

proc definePropertyC*(ctx: JSContext; this: JSValueConst; name: string;
    prop: JSValue): DefinePropertyResult =
  ## Define a configurable property on `this`.
  ##
  ## Frees `prop'.
  ctx.defineProperty(this, name, prop, JS_PROP_CONFIGURABLE)

proc definePropertyE*(ctx: JSContext; this: JSValueConst; name: string;
    prop: JSValue): DefinePropertyResult =
  ## Define an enumerable property on `this`.
  ##
  ## Frees `prop'.
  ctx.defineProperty(this, name, prop, JS_PROP_ENUMERABLE)

proc definePropertyCW*(ctx: JSContext; this: JSValueConst; name: string;
    prop: JSValue): DefinePropertyResult =
  ## Frees `prop'.
  ctx.defineProperty(this, name, prop, JS_PROP_CONFIGURABLE or JS_PROP_WRITABLE)

proc definePropertyCWE*(ctx: JSContext; this: JSValueConst; name: string;
    prop: JSValue): DefinePropertyResult =
  ## Frees `prop'.
  ctx.defineProperty(this, name, prop, JS_PROP_C_W_E)

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
  return JS_Eval(ctx, cstring(s), csize_t(s.len), cstring(file),
    cint(evalFlags))

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
    DefinePropertyResult =
  ## Define a list of constants expressed as a Nim enum on a class.
  let proto = JS_GetClassProto(ctx, classid)
  let ctor = ctx.getOpaque().ctors[int(classid)]
  var res = dprSuccess
  for e in consts:
    let s = $e
    res = ctx.definePropertyE(proto, s, JS_NewUint32(ctx, uint32(e)))
    if res != dprSuccess:
      break
    res = ctx.definePropertyE(ctor, s, JS_NewUint32(ctx, uint32(e)))
    if res != dprSuccess:
      break
  JS_FreeValue(ctx, proto)
  res

proc setPropertyFunctionList*(ctx: JSContext; val: JSValueConst;
    funcs: openArray[JSCFunctionListEntry]): bool =
  if funcs.len == 0:
    return true
  let fp = cast[JSCFunctionListP](unsafeAddr funcs[0])
  return JS_SetPropertyFunctionList(ctx, val, fp, cint(funcs.len)) != -1

proc identity(ctx: JSContext; this_val: JSValueConst; argc: cint;
    argv: JSValueConstArray; magic: cint; func_data: JSValueConstArray): JSValue
    {.cdecl.} =
  return JS_DupValue(ctx, func_data[0])

proc identityFunction*(ctx: JSContext; val: JSValueConst): JSValue =
  ## Returns a function that always returns `val`.
  return JS_NewCFunctionData(ctx, identity, 0, 0, 1, val.toJSValueConstArray())

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
  let stack = JS_GetPropertyStr(ctx, ex, cstring("stack"))
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
  while JS_IsJobPending(rt):
    var ctx: JSContext
    let r = JS_ExecutePendingJob(rt, ctx)
    if r == -1:
      return ctx
  nil

{.pop.} # raises
