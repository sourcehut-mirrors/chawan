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

  JSValueRef* = enum
    jsvArrayPrototypeValues = "Array.prototype.values"
    jsvUint8Array = "Uint8Array"
    jsvObjectPrototypeValueOf = "Object.prototype.valueOf"
    jsvSet = "Set"
    jsvFunction = "Function"

  JSContextOpaque* = ref object
    typemap*: Table[pointer, JSClassID]
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
    globalUnref*: JSEmptyOpaqueCallback

  JSFinalizerFunction* = proc(rt: JSRuntime; opaque: pointer) {.nimcall,
    raises: [].}

  JSEmptyOpaqueCallback* = (proc() {.closure, raises: [].})

  JSRuntimeOpaque* = ref object
    plist*: Table[pointer, tuple[p: pointer; jsref: bool]] # Nim, JS
    flist*: seq[seq[JSCFunctionListEntry]]
    fins*: Table[pointer, seq[JSFinalizerFunction]]
    #TODO maybe just extract this from typemap on JSContext free?
    inverseTypemap*: seq[pointer]
    parentMap*: Table[pointer, pointer]
    destroying*: pointer
    # temp list for uninit
    tmplist*: seq[pointer]
    tmpunrefs*: seq[pointer]

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

func toNimType*(opaque: JSRuntimeOpaque; class: JSClassID): pointer =
  if int(class) < opaque.inverseTypemap.len:
    return opaque.inverseTypemap[class]
  nil

proc setOpaque*(ctx: JSContext; val: JSValue; opaque: pointer) =
  let rt = JS_GetRuntime(ctx)
  let rtOpaque = rt.getOpaque()
  let p = JS_VALUE_GET_PTR(val)
  rtOpaque.plist[opaque] = (p, true)
  JS_SetOpaque(val, opaque)

func getOpaque*(val: JSValue): pointer =
  if JS_VALUE_GET_TAG(val) == JS_TAG_OBJECT:
    return JS_GetOpaque(val, JS_GetClassID(val))
  return nil

{.pop.} # raises
