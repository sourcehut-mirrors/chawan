import std/tables

import jserror
import optshim
import quickjs

type
  JSSymbolRef* = enum
    jsyIterator = "iterator"
    jsyAsyncIterator = "asyncIterator"
    jsyToStringTag = "toStringTag"

  JSStrRef* = enum
    jstDone = "done"
    jstValue = "value"
    jstNext = "next"
    jstPrototype = "prototype"
    jstThen = "then"

  JSValueRef* = enum
    jsvArrayPrototypeValues = "Array.prototype.values"
    jsvUint8Array = "Uint8Array"
    jsvObjectPrototypeValueOf = "Object.prototype.valueOf"
    jsvSet = "Set"
    jsvFunction = "Function"

  JSContextOpaque* = ref object
    creg*: Table[string, JSClassID]
    typemap*: Table[pointer, JSClassID]
    ctors*: Table[JSClassID, JSValue]
    parents*: Table[JSClassID, JSClassID]
    # Parent unforgeables are merged on class creation.
    # (i.e. to set all unforgeables on the prototype chain, it is enough to set)
    # `unforgeable[classid]'.)
    unforgeable*: Table[JSClassID, seq[JSCFunctionListEntry]]
    gclaz*: string
    gparent*: JSClassID
    symRefs*: array[JSSymbolRef, JSAtom]
    strRefs*: array[JSStrRef, JSAtom]
    valRefs*: array[JSValueRef, JSValue]
    errCtorRefs*: array[JSErrorEnum, JSValue]
    htmldda*: JSClassID # only one of these exists: document.all.
    globalUnref*: proc() {.closure.}

  JSFinalizerFunction* = proc(rt: JSRuntime; val: JSValue) {.nimcall,
    raises: [].}

  JSRuntimeOpaque* = ref object
    plist*: Table[pointer, pointer] # Nim, JS
    flist*: seq[seq[JSCFunctionListEntry]]
    fins*: Table[JSClassID, JSFinalizerFunction]
    refmap*: Table[pointer, tuple[cref, cunref: (proc() {.closure.})]]
    destroying*: pointer

func newJSContextOpaque*(ctx: JSContext): JSContextOpaque =
  let opaque = JSContextOpaque()
  block: # get well-known symbols and other functions
    let global = JS_GetGlobalObject(ctx)
    let sym = JS_GetPropertyStr(ctx, global, "Symbol")
    for s in JSSymbolRef:
      let name = $s
      let val = JS_GetPropertyStr(ctx, sym, cstring(name))
      assert JS_IsSymbol(val)
      opaque.symRefs[s] = JS_ValueToAtom(ctx, val)
      JS_FreeValue(ctx, val)
    JS_FreeValue(ctx, sym)
    for s in JSStrRef:
      let ss = $s
      opaque.strRefs[s] = JS_NewAtomLen(ctx, cstring(ss), csize_t(ss.len))
    for s in JSValueRef:
      let ss = $s
      let ret = JS_Eval(ctx, cstring(ss), csize_t(ss.len), "<init>", 0)
      assert JS_IsFunction(ctx, ret)
      opaque.valRefs[s] = ret
    for e in JSErrorEnum:
      let s = $e
      let err = JS_GetPropertyStr(ctx, global, cstring(s))
      opaque.errCtorRefs[e] = err
    JS_FreeValue(ctx, global)
  return opaque

func getOpaque*(ctx: JSContext): JSContextOpaque =
  return cast[JSContextOpaque](JS_GetContextOpaque(ctx))

func getOpaque*(rt: JSRuntime): JSRuntimeOpaque =
  return cast[JSRuntimeOpaque](JS_GetRuntimeOpaque(rt))

func isGlobal*(ctx: JSContext; class: string): bool =
  assert class != ""
  return ctx.getOpaque().gclaz == class

proc setOpaque*(ctx: JSContext; val: JSValue; opaque: pointer) =
  let rt = JS_GetRuntime(ctx)
  let rtOpaque = rt.getOpaque()
  let p = JS_VALUE_GET_PTR(val)
  rtOpaque.plist[opaque] = p
  JS_SetOpaque(val, opaque)

# getOpaque, but doesn't work for global objects.
func getOpaque0*(val: JSValue): pointer =
  if JS_VALUE_GET_TAG(val) == JS_TAG_OBJECT:
    return JS_GetOpaque(val, JS_GetClassID(val))

func getGlobalOpaque0*(ctx: JSContext; val = JS_UNDEFINED): Opt[pointer] =
  let global = JS_GetGlobalObject(ctx)
  if JS_IsUndefined(val) or val == global:
    let opaque = JS_GetOpaque(global, JS_CLASS_OBJECT)
    JS_FreeValue(ctx, global)
    return ok(opaque)
  JS_FreeValue(ctx, global)
  return err()

func getGlobalOpaque*(ctx: JSContext; T: typedesc; val = JS_UNDEFINED): Opt[T] =
  return ok(cast[T](?getGlobalOpaque0(ctx, val)))

func getOpaque*(ctx: JSContext; val: JSValue; class: string): pointer =
  # Unfortunately, we can't change the global object's class.
  #TODO: or maybe we can, but I'm afraid of breaking something.
  # This needs further investigation.
  if ctx.isGlobal(class):
    let global = JS_GetGlobalObject(ctx)
    let opaque = JS_GetOpaque(global, JS_CLASS_OBJECT)
    JS_FreeValue(ctx, global)
    return opaque
  return getOpaque0(val)

func getOpaque*[T: ref object](ctx: JSContext; val: JSValue): T =
  cast[T](getOpaque(ctx, val, $T))
