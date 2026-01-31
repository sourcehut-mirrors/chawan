{.push raises: [].}

import std/tables

import quickjs

type
  JSSymbolRef* = enum
    jsyIterator = "iterator"
    jsyToStringTag = "toStringTag"

  JSStrRef* = enum
    jstDone = "done"
    jstValue = "value"
    jstNext = "next"
    jstThen = "then"
    jstCatch = "catch"
    jstSet = "set"
    jstGet = "get"
    jstEntries = "entries"
    jstForEach = "forEach"
    jstKeys = "keys"
    jstValues = "values"

  JSValueRef* = enum
    jsvArrayPrototypeForEach = "Array.prototype.forEach"
    jsvArrayPrototypeEntries = "Array.prototype.entries"
    jsvArrayPrototypeKeys = "Array.prototype.keys"
    jsvArrayPrototypeValues = "Array.prototype.values"
    jsvObjectPrototypeValueOf = "Object.prototype.valueOf"
    jsvSet = "Set"
    jsvFunction = "Function"

  BoundRefDestructor* = proc(x: pointer) {.nimcall, raises: [].}

  JSClassData* = object
    parent*: JSClassID
    # Parent unforgeables are merged on class creation.
    # (i.e. to set all unforgeables on the prototype chain, it is enough to set)
    # `unforgeable[classid]'.)
    unforgeable*: seq[JSCFunctionListEntry]
    fins*: seq[JSFinalizerFunction]
    when defined(gcDestructors):
      dtor*: BoundRefDestructor

  JSContextOpaque* = ref object
    gclass*: JSClassID # class ID of the global object
    ctors*: seq[JSValue] # class ID -> constructor
    global*: JSValue
    symRefs*: array[JSSymbolRef, JSAtom]
    strRefs*: array[JSStrRef, JSAtom]
    valRefs*: array[JSValueRef, JSValue]
    globalObj*: pointer

  JSFinalizerFunction* = proc(rt: JSRuntime; opaque: pointer) {.nimcall,
    raises: [].}

  JSRuntimeOpaque* = ref object
    classes*: seq[JSClassData] # JSClassID -> data
    typemap*: Table[pointer, JSClassID] # getTypePtr -> JSClassID
    enumMap*: seq[seq[JSAtom]]
    plist*: Table[pointer, pointer] # Nim -> JS
    destroying*: pointer
    # temp list for uninit
    tmplist*: seq[tuple[nimp, jsp: pointer]]

iterator finalizers*(rtOpaque: JSRuntimeOpaque; classid: JSClassID):
    JSFinalizerFunction =
  let classid = int(classid)
  if classid < rtOpaque.classes.len:
    for fin in rtOpaque.classes[classid].fins:
      yield fin

proc newJSContextOpaque*(ctx: JSContext): JSContextOpaque =
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
  return opaque

proc getOpaque*(ctx: JSContext): JSContextOpaque =
  return cast[JSContextOpaque](JS_GetContextOpaque(ctx))

proc getOpaque*(rt: JSRuntime): JSRuntimeOpaque =
  return cast[JSRuntimeOpaque](JS_GetRuntimeOpaque(rt))

proc getOpaque*(val: JSValue): pointer =
  if JS_VALUE_GET_TAG(val) == JS_TAG_OBJECT:
    return JS_GetOpaque(val, JS_GetClassID(val))
  return nil

proc setUnforgeable*(ctx: JSContext; val: JSValueConst; class: JSClassID):
    bool =
  let rtOpaque = JS_GetRuntime(ctx).getOpaque()
  let iclass = int(class)
  if iclass < rtOpaque.classes.len and
      rtOpaque.classes[iclass].unforgeable.len > 0:
    let ufp0 = addr rtOpaque.classes[iclass].unforgeable[0]
    let ufp = cast[JSCFunctionListP](ufp0)
    if JS_SetPropertyFunctionList(ctx, val, ufp,
        cint(rtOpaque.classes[iclass].unforgeable.len)) == -1:
      return false
  true

{.pop.} # raises
