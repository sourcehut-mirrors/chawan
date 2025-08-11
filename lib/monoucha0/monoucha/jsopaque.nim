{.push raises: [].}

import std/tables

import jserror
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
    jstCatch = "catch"
    jstSet = "set"
    jstGet = "get"

  JSValueRef* = enum
    jsvArrayPrototypeValues = "Array.prototype.values"
    jsvUint8Array = "Uint8Array"
    jsvObjectPrototypeValueOf = "Object.prototype.valueOf"
    jsvSet = "Set"
    jsvFunction = "Function"

  JSContextOpaque* = ref object
    ctors*: seq[JSValue] # JSClassID -> JSValue
    parents*: seq[JSClassID] # JSClassID -> JSClassID
    # Parent unforgeables are merged on class creation.
    # (i.e. to set all unforgeables on the prototype chain, it is enough to set)
    # `unforgeable[classid]'.)
    unforgeable*: seq[seq[JSCFunctionListEntry]] # JSClassID -> seq
    gclass*: JSClassID # class ID of the global object
    global*: JSValue
    symRefs*: array[JSSymbolRef, JSAtom]
    strRefs*: array[JSStrRef, JSAtom]
    valRefs*: array[JSValueRef, JSValue]
    errCtorRefs*: array[JSErrorEnum, JSValue]
    globalObj*: pointer

  JSFinalizerFunction* = proc(rt: JSRuntime; opaque: pointer) {.nimcall,
    raises: [].}

  JSEmptyOpaqueCallback* = (proc() {.closure, raises: [].})

  JSRuntimeOpaque* = ref object
    typemap*: Table[pointer, JSClassID]
    plist*: Table[pointer, pointer] # Nim -> JS
    flist*: seq[seq[JSCFunctionListEntry]]
    fins*: seq[seq[JSFinalizerFunction]]
    parentMap*: Table[pointer, pointer]
    destroying*: pointer
    # temp list for uninit
    tmplist*: seq[tuple[nimp, jsp: pointer]]

iterator finalizers*(rtOpaque: JSRuntimeOpaque; classid: JSClassID):
    JSFinalizerFunction =
  let classid = int(classid)
  if classid < rtOpaque.fins.len:
    for fin in rtOpaque.fins[classid]:
      yield fin

func newJSContextOpaque*(ctx: JSContext): JSContextOpaque =
  let opaque = JSContextOpaque(global: JS_GetGlobalObject(ctx))
  let sym = JS_GetPropertyStr(ctx, opaque.global, "Symbol")
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
    if e != jeCustom:
      opaque.errCtorRefs[e] = JS_GetPropertyStr(ctx, opaque.global, cstring($e))
  return opaque

func getOpaque*(ctx: JSContext): JSContextOpaque =
  return cast[JSContextOpaque](JS_GetContextOpaque(ctx))

func getOpaque*(rt: JSRuntime): JSRuntimeOpaque =
  return cast[JSRuntimeOpaque](JS_GetRuntimeOpaque(rt))

func isGlobal*(ctx: JSContext; class: JSClassID): bool =
  return ctx.getOpaque().gclass == class

func getOpaque*(val: JSValue): pointer =
  if JS_VALUE_GET_TAG(val) == JS_TAG_OBJECT:
    return JS_GetOpaque(val, JS_GetClassID(val))
  return nil

{.pop.} # raises
