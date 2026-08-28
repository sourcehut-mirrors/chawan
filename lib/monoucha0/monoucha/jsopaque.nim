{.push raises: [].}

import std/algorithm

import quickjs
import utils/twtstr

type
  JSSymbolRef* = enum
    jsyIterator = "iterator"
    jsyToStringTag = "toStringTag"

  JSStrRef* = enum
    jstDone = "done"
    jstValue = "value"
    jstNext = "next"
    jstEntries = "entries"
    jstForEach = "forEach"
    jstKeys = "keys"
    jstValues = "values"
    jstScreen = "screen"
    jstHistory = "history"
    jstCrypto = "crypto"
    jstNavigator = "navigator"
    jstPlugins = "plugins"
    jstMimeTypes = "mimeTypes"
    jstPermissions = "permissions"
    jstLocation = "location"
    jstBuffer = "buffer"
    jstAcceptNode = "acceptNode"
    jstName = "name"

  JSValueRef* = enum
    jsvArrayPrototypeForEach = "Array.prototype.forEach"
    jsvArrayPrototypeEntries = "Array.prototype.entries"
    jsvArrayPrototypeKeys = "Array.prototype.keys"
    jsvArrayPrototypeValues = "Array.prototype.values"
    jsvObjectPrototypeValueOf = "Object.prototype.valueOf"
    jsvSet = "Set"
    jsvFunction = "Function"
    jsvIteratorPrototype = "Iterator.prototype"
    jsvSymbol = "Symbol" # must be last

  BoundRefDestructor* = proc(x: pointer) {.nimcall, raises: [].}

  JSClassData* = object
    parent*: JSClassID
    raw*: bool #TODO remove
    # Parent unforgeables are merged on class creation.
    # (i.e. to set all unforgeables on the prototype chain, it is enough to set)
    # `unforgeable[classid]'.)
    unforgeable*: seq[JSCFunctionListEntry]
    fins*: seq[ChaFinalizerFunction]
    marks*: seq[ChaMarkFunction]
    name*: cstring

  JSContextOpaqueObj* = object
    gclass*: JSClassID # class ID of the global object
    ctors*: seq[JSValue] # class ID -> constructor
    global*: JSValue
    symRefs*: array[JSSymbolRef, JSAtom]
    strRefs*: array[JSStrRef, JSAtom]
    valRefs*: array[JSValueRef, JSValue]
    globalObj*: pointer

  JSContextOpaque* = ptr JSContextOpaqueObj

  ChaFinalizerFunction* = proc(rt: JSRuntime; this: pointer) {.nimcall,
    raises: [].}

  ChaMarkFunction* = proc(rt: JSRuntime; this: pointer;
    markFun: JS_MarkFunc) {.nimcall, raises: [].}

  EnumMapItem* = object
    atom*: JSAtom
    n*: int32

  EnumMapEntry* = object
    atoms*: seq[JSAtom] # enum number -> atom
    enums*: seq[EnumMapItem] # atom number -> enum

  JSRuntimeOpaqueObj* = object
    classes*: seq[JSClassData] # JSClassID -> data
    enumMap*: seq[EnumMapEntry]
    load: int
    when defined(debug):
      marking*: bool

  JSRuntimeOpaque* = ptr JSRuntimeOpaqueObj

var globalRuntime* {.global.}: JSRuntime

iterator finalizers*(rtOpaque: JSRuntimeOpaque; classid: JSClassID):
    ChaFinalizerFunction =
  let classid = int(classid)
  if classid < rtOpaque.classes.len:
    for fin in rtOpaque.classes[classid].fins.ritems:
      yield fin

iterator marks*(rtOpaque: JSRuntimeOpaque; classid: JSClassID):
    ChaMarkFunction =
  let classid = int(classid)
  if classid < rtOpaque.classes.len:
    for mark in rtOpaque.classes[classid].marks.ritems:
      yield mark

proc getParent*(rtOpaque: JSRuntimeOpaque; class: JSClassID): JSClassID =
  rtOpaque.classes[int(class)].parent

proc newJSContextOpaque*(ctx: JSContext): JSContextOpaque =
  let opaque = create(JSContextOpaqueObj)
  opaque.global = JS_GetGlobalObject(ctx)
  let sym = JS_GetPropertyStr(ctx, opaque.global, "Symbol")
  for s in JSSymbolRef:
    let name = $s
    let val = JS_GetPropertyStr(ctx, sym, cstring(name))
    assert JS_IsSymbol(val)
    opaque.symRefs[s] = JS_ValueToAtom(ctx, val)
    JS_FreeValue(ctx, val)
  for s in JSStrRef:
    let ss = $s
    opaque.strRefs[s] = JS_NewAtomLen(ctx, ss.toCStringConst,
      csize_t(ss.len))
  for s in JSValueRef.low..jsvSymbol.pred:
    let ss = $s
    let ret = JS_Eval(ctx, ss.toCStringConst, csize_t(ss.len),
      cstringConst("<init>"), 0)
    assert not JS_IsException(ret)
    opaque.valRefs[s] = ret
  opaque.valRefs[jsvSymbol] = sym
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

proc putEnums0(ctx: JSContext; entry: var EnumMapEntry;
    atoms: openArray[string]): bool =
  entry.enums = newSeqOfCap[EnumMapItem](atoms.len)
  if entry.atoms.len < atoms.len:
    entry.atoms.setLen(atoms.len)
  for i in 0'i32 ..< int32(atoms.len):
    let atom = JS_NewAtomLen(ctx, cstringConst(atoms[i]),
      csize_t(atoms[i].len))
    if atom == JS_ATOM_NULL:
      return false
    if entry.atoms[i] == JS_ATOM_NULL:
      entry.atoms[i] = JS_DupAtom(ctx, atom)
    entry.enums.add(EnumMapItem(n: i, atom: atom))
  entry.enums.sort(proc(x, y: EnumMapItem): int {.nimcall.} =
    cmp(uint32(x.atom), uint32(y.atom))
  )
  true

proc putEnums*(ctx: JSContext; enumId: int; atoms: openArray[string]): bool =
  let rtOpaque = JS_GetRuntime(ctx).getOpaque()
  if enumId >= rtOpaque.enumMap.len:
    rtOpaque.enumMap.setLen(enumId + 1)
  if rtOpaque.enumMap[enumId].enums.len == atoms.len:
    return true
  ctx.putEnums0(rtOpaque.enumMap[enumId], atoms)

proc getName*(rt: JSRuntime; classid: JSClassID): string =
  $rt.getOpaque().classes[int(classid)].name

{.pop.} # raises
