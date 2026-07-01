{.push raises: [].}

import std/hashes
import std/algorithm
import std/tables

import quickjs
import utils/tabutil

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
    jsvIteratorPrototype = "Iterator.prototype"

  BoundRefDestructor* = proc(x: pointer) {.nimcall, raises: [].}

  JSClassData* = object
    parent*: JSClassID
    # Parent unforgeables are merged on class creation.
    # (i.e. to set all unforgeables on the prototype chain, it is enough to set)
    # `unforgeable[classid]'.)
    unforgeable*: seq[JSCFunctionListEntry]
    fins*: seq[JSFinalizerFunction]
    nimt*: pointer # pointer to the Nim type
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

  EnumMapItem* = object
    atom*: JSAtom
    n*: int32

  EnumMapEntry* = object
    atoms*: seq[JSAtom] # enum number -> atom
    enums*: seq[EnumMapItem] # atom number -> enum

  # Stores hash code and Nim/JS pointers.
  JSPointerItem = object
    hcache: Hash
    nimp*: pointer
    jsp*: pointer

  JSRuntimeOpaque* = ref object
    classes*: seq[JSClassData] # JSClassID -> data
    typemap*: Table[pointer, JSClassID] # getTypePtr -> JSClassID
    enumMap*: seq[EnumMapEntry]
    plist*: seq[JSPointerItem] # Nim -> JS
    load: int

var globalRuntime* {.global.}: JSRuntime

iterator finalizers*(rtOpaque: JSRuntimeOpaque; classid: JSClassID):
    JSFinalizerFunction =
  let classid = int(classid)
  if classid < rtOpaque.classes.len:
    for fin in rtOpaque.classes[classid].fins:
      yield fin

# Return the JSObject pointer associated with nimp, or nil.
# If nimt is not nil, then an associated weakly referenced Nim object is
# returned instead.
proc getOrDefault*(rtOpaque: JSRuntimeOpaque; nimp: pointer): pointer =
  if rtOpaque.plist.len <= 0:
    return nil
  let mask = rtOpaque.plist.len - 1
  var i = nimp.hash() and mask
  while true:
    let it = rtOpaque.plist[i]
    if it.nimp == nimp:
      return it.jsp
    if it.nimp == nil:
      break
    i = (i + 1) and mask
  nil

proc put0(rtOpaque: JSRuntimeOpaque; item: JSPointerItem) =
  let mask = rtOpaque.plist.len - 1
  var home = item.hcache and mask
  var i = home
  var current = item
  while true:
    let it = rtOpaque.plist[i]
    if it.nimp == nil:
      rtOpaque.plist[i] = current
      break
    if tabSwap(home, it.hcache, i, mask): # displace
      swap(rtOpaque.plist[i], current)
    i = (i + 1) and mask

proc add*(rtOpaque: JSRuntimeOpaque; nimp, jsp: pointer) =
  for it in rtOpaque.plist.prepareTableAdd(rtOpaque.load, init = 32):
    if it.nimp != nil:
      rtOpaque.put0(it)
  rtOpaque.put0(JSPointerItem(
    hcache: nimp.hash(),
    nimp: nimp,
    jsp: jsp
  ))
  inc rtOpaque.load

proc del*(rtOpaque: JSRuntimeOpaque; nimp: pointer) =
  if rtOpaque.plist.len == 0:
    return
  let mask = rtOpaque.plist.len - 1
  var i = nimp.hash() and mask
  while true:
    let it = rtOpaque.plist[i]
    if it.nimp == nil:
      return # not found
    if it.nimp == nimp:
      dec rtOpaque.load
      rtOpaque.plist[i] = JSPointerItem()
      break
    i = (i + 1) and mask
  var j = i
  while true:
    j = (j + 1) and mask
    let it = rtOpaque.plist[j]
    if it.nimp == nil:
      break
    let k = it.hcache and mask
    if j == k: # already at home
      break
    # backwards shift
    rtOpaque.plist[i] = move(rtOpaque.plist[j])
    i = j

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
    assert not JS_IsException(ret)
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

{.pop.} # raises
