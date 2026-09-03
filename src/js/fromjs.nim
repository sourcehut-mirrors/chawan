{.push raises: [].}

import std/algorithm
import std/macros
import std/typetraits

import js/jsopaque
import js/jsref
import js/jstypes
import js/jsutils
import js/quickjs
import js/tojs
import utils/twtstr

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var string): JSCode
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var DOMString):
  JSCode
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var DOMStringNull):
  JSCode
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var ByteString):
  JSCode
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int16): JSCode
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int32): JSCode
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int64): JSCode
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var uint16): JSCode
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var uint32): JSCode
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int): JSCode
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var float64): JSCode
proc fromJS*[T: tuple](ctx: JSContext; val: JSValueConst; res: var T):
  JSCode
proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var seq[T]):
  JSCode
proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var set[T]):
  JSCode
proc fromJS*[K, T](ctx: JSContext; val: JSValueConst;
  res: var JSKeyValuePair[K, T]): JSCode
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var bool): JSCode
proc fromJS*[T: enum](ctx: JSContext; val: JSValueConst; res: var T):
  JSCode
proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var JSRef[T]):
  JSCode
proc fromJS*[T: JSDict](ctx: JSContext; val: JSValueConst; res: var T):
  JSCode
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSArrayBuffer):
  JSCode
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSArrayBufferView):
  JSCode
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSValueConst):
  JSCode
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSValue): JSCode
proc fromJS*(ctx: JSContext; atom: JSAtom; res: var string): JSCode
proc fromJS*(ctx: JSContext; atom: JSAtom; res: var DOMString): JSCode
proc fromJS*(ctx: JSContext; atom: JSAtom; res: var ByteString): JSCode

template isOk*(res: JSCode): bool =
  res == fjOk

template isErr*(res: JSCode): bool =
  res == fjErr

template `?`(res: JSCode) =
  if res == fjErr:
    return fjErr

proc fromJSFree*[T](ctx: JSContext; val: JSValue; res: var T): JSCode =
  result = ctx.fromJS(val, res)
  JS_FreeValue(ctx, val)

proc fromJSFree*(ctx: JSContext; val: JSValue; res: var JSValueTraced):
    JSCode =
  res = trace(val)
  fjOk

proc fromJSFree*(ctx: JSContext; val: JSValue; res: var JSCallback):
    JSCode =
  if not JS_IsFunction(ctx, val):
    JS_FreeValue(ctx, val)
    JS_ThrowTypeError(ctx, "function expected")
    return fjErr
  res = JSCallback(traceObj(val))
  fjOk

proc fromJSCallback*(ctx: JSContext; val: JSValueConst;
    res: var pointer): JSCode =
  if not JS_IsFunction(ctx, val):
    JS_ThrowTypeError(ctx, "function expected")
    return fjErr
  res = JS_VALUE_GET_PTR(val)
  fjOk

proc isInstanceOf*(ctx: JSContext; classid, tclassid: JSClassID): bool =
  let rtOpaque = JS_GetRuntime(ctx).getOpaque()
  var classid = classid
  var found = false
  while true:
    if classid == tclassid:
      found = true
      break
    if int(classid) >= rtOpaque.classes.len:
      break
    classid = rtOpaque.classes[int(classid)].parent
    if classid == JS_INVALID_CLASS_ID:
      break
  found

proc checkInstanceOf*(ctx: JSContext; this: JSValueConst; tclassid: JSClassID):
    JSCode =
  let ctxOpaque = ctx.getOpaque()
  let classid = if JS_VALUE_GET_PTR(ctxOpaque.global) != JS_VALUE_GET_PTR(this):
    JS_GetClassID(this)
  else:
    ctxOpaque.gclass
  if not ctx.isInstanceOf(classid, tclassid):
    # JS_ThrowTypeErroInvalidClass
    discard JS_GetOpaque2(ctx, JS_UNDEFINED, tclassid)
    return fjErr
  fjOk

proc isSequence*(ctx: JSContext; o: JSValueConst): bool =
  if not JS_IsObject(o):
    return false
  let prop = JS_GetProperty(ctx, o, ctx.getOpaque().symRefs[jsyIterator])
  # prop can't be exception (throws_ref_error is 0 and tag is object)
  result = not JS_IsUndefined(prop)
  JS_FreeValue(ctx, prop)

proc fromJS(ctx: JSContext; cs: cstringConst; len: csize_t; narrow: bool;
    res: var string): JSCode =
  if cs == nil:
    return fjErr
  if len > csize_t(int.high):
    JS_FreeCString(ctx, cs)
    JS_ThrowRangeError(ctx, "string length out of bounds")
    return fjErr
  let ilen = cast[int](len)
  res = newString(ilen)
  if ilen > 0:
    chaArrayCopy(res, cstring(cs).toOpenArray(0, ilen - 1))
    if not narrow:
      res.replaceSurrogates()
  JS_FreeCString(ctx, cs)
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var string): JSCode =
  var len {.noinit.}: csize_t
  let cs = JS_ToCStringLen(ctx, len, val) # cstring
  let narrow = JS_GetNarrowStringBuffer(val) != nil
  ctx.fromJS(cs, len, narrow, res)

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var DOMString):
    JSCode =
  var len {.noinit.}: csize_t
  let cs = JS_ToCStringLen(ctx, len, val) # cstring
  if cs == nil:
    return fjErr
  if len > csize_t(int.high):
    JS_FreeCString(ctx, cs)
    JS_ThrowRangeError(ctx, "string length out of bounds")
    return fjErr
  res = initDOMString(cstring(cs), cast[int](len))
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var DOMStringNull):
    JSCode =
  var ds = initDOMStringLit("")
  if not JS_IsNull(val):
    ?ctx.fromJS(val, ds)
  res = ds.toDOMStringNull()
  fjOk

proc fromJS(ctx: JSContext; cs: cstringConst; len: csize_t;
    res: var ByteString): JSCode =
  if cs == nil:
    return fjErr
  if len > csize_t(int.high):
    JS_FreeCString(ctx, cs)
    JS_ThrowRangeError(ctx, "string length out of bounds")
    return fjErr
  let ilen = cast[int](len)
  res.s = newString(ilen)
  for u in cs.toCString.toOpenArray(0, ilen - 1).points:
    if u > 0xFF:
      JS_ThrowTypeError(ctx, "ByteString character out of bounds")
      return fjErr
  if ilen > 0:
    copyMem(addr res.s[0], cast[pointer](cs), ilen)
  JS_FreeCString(ctx, cs)
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var ByteString):
    JSCode =
  var len {.noinit.}: csize_t
  let cs = JS_ToCStringLen(ctx, len, val) # cstring
  ctx.fromJS(cs, len, res)

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int16): JSCode =
  var n {.noinit.}: int32
  if JS_ToInt32(ctx, n, val) < 0:
    return fjErr
  res = cast[int16](n)
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int32): JSCode =
  var n {.noinit.}: int32
  if JS_ToInt32(ctx, n, val) < 0:
    return fjErr
  res = n
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int64): JSCode =
  var n {.noinit.}: int64
  if JS_ToInt64(ctx, n, val) < 0:
    return fjErr
  res = n
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var uint16): JSCode =
  var n {.noinit.}: uint32
  if JS_ToUint32(ctx, n, val) < 0:
    return fjErr
  res = uint16(n)
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var uint32): JSCode =
  var n {.noinit.}: uint32
  if JS_ToUint32(ctx, n, val) < 0:
    return fjErr
  res = n
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int): JSCode =
  when sizeof(int) > 4:
    var x: int64
  else:
    var x: int32
  ?ctx.fromJS(val, x)
  res = int(x)
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var float64): JSCode =
  var n {.noinit.}: float64
  if JS_ToFloat64(ctx, n, val) < 0:
    return fjErr
  res = n
  fjOk

type SeqItResult* = enum
  sirDone, sirContinue, sirException

proc fromJSSeqIt*(ctx: JSContext; iter, nextMethod: JSValueConst;
    res: var JSValue): SeqItResult =
  let next = JS_Call(ctx, nextMethod, iter, 0, nil)
  if JS_IsException(next):
    return sirException
  let doneVal = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstDone])
  if JS_IsException(doneVal):
    JS_FreeValue(ctx, next)
    return sirException
  var done: bool
  if ctx.fromJSFree(doneVal, done).isErr:
    JS_FreeValue(ctx, next)
    return sirException
  if not done:
    res = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstValue])
    JS_FreeValue(ctx, next)
    if JS_IsException(res):
      return sirException
    return sirContinue
  JS_FreeValue(ctx, next)
  sirDone

proc readTupleDone(ctx: JSContext; iter, nextMethod: JSValue): JSCode =
  var res = sirDone
  while true:
    var val: JSValue
    case ctx.fromJSSeqIt(iter, nextMethod, val)
    of sirException:
      res = sirException
      break
    of sirContinue:
      JS_FreeValue(ctx, val)
      res = sirContinue
    of sirDone:
      break
  JS_FreeValue(ctx, iter)
  JS_FreeValue(ctx, nextMethod)
  case res
  of sirContinue:
    JS_ThrowTypeError(ctx, "too few arguments in sequence")
    fjErr
  of sirException: fjErr
  of sirDone: fjOk

proc fromJS*[T: tuple](ctx: JSContext; val: JSValueConst; res: var T):
    JSCode =
  var iter: JSValue
  var nextMethod: JSValue
  var status = sirContinue
  ?ctx.fromJSSeqInit(val, iter, nextMethod)
  for f in res.fields:
    var val: JSValue
    status = ctx.fromJSSeqIt(iter, nextMethod, val)
    if status != sirContinue:
      break
    if ctx.fromJSFree(val, f).isErr:
      status = sirException
      break
  if status != sirContinue:
    JS_FreeValue(ctx, iter)
    JS_FreeValue(ctx, nextMethod)
    if status != sirException:
      JS_ThrowTypeError(ctx, "too few arguments in sequence")
    return fjErr
  ctx.readTupleDone(iter, nextMethod)

proc fromJSSeqInit*(ctx: JSContext; val: JSValueConst;
    oit, onextMethod: var JSValue): JSCode =
  let it = JS_Invoke(ctx, val, ctx.getOpaque().symRefs[jsyIterator], 0, nil)
  if JS_IsException(it):
    return fjErr
  let nextMethod = JS_GetProperty(ctx, it, ctx.getOpaque().strRefs[jstNext])
  if JS_IsException(nextMethod):
    JS_FreeValue(ctx, it)
    return fjErr
  oit = it
  onextMethod = nextMethod
  fjOk

proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var seq[T]): JSCode =
  var iter: JSValue
  var nextMethod: JSValue
  ?ctx.fromJSSeqInit(val, iter, nextMethod)
  var status = fjOk
  var tmp = newSeq[T]()
  while status.isOk:
    var val: JSValue
    case ctx.fromJSSeqIt(iter, nextMethod, val)
    of sirException:
      status = fjErr
      break
    of sirDone:
      res = move(tmp)
      break
    of sirContinue:
      tmp.add(default(T))
      status = ctx.fromJSFree(val, tmp[^1])
  JS_FreeValue(ctx, iter)
  JS_FreeValue(ctx, nextMethod)
  status

proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var set[T]): JSCode =
  var iter: JSValue
  var nextMethod: JSValue
  ?ctx.fromJSSeqInit(val, iter, nextMethod)
  var status = fjOk
  var tmp: set[T] = {}
  while status.isOk:
    var val: JSValue
    case ctx.fromJSSeqIt(iter, nextMethod, val)
    of sirException:
      status = fjErr
      break
    of sirDone:
      res = tmp
      break
    of sirContinue:
      var x: T
      status = ctx.fromJSFree(val, x)
      tmp.incl(x)
  res = tmp
  JS_FreeValue(ctx, iter)
  JS_FreeValue(ctx, nextMethod)
  status

proc fromJS*[K, T](ctx: JSContext; val: JSValueConst;
    res: var JSKeyValuePair[K, T]): JSCode =
  var ptab: ptr UncheckedArray[JSPropertyEnum]
  var plen: uint32
  let flags = JS_GPN_STRING_MASK
  if JS_GetOwnPropertyNames(ctx, addr ptab, addr plen, val, flags) == -1:
    # exception
    return fjErr
  var tmp = newSeqOfCap[tuple[name: K; value: T]](plen)
  for i in 0 ..< plen:
    let atom = ptab[i].atom
    var kn: K
    if ctx.fromJS(atom, kn).isErr:
      JS_FreePropertyEnum(ctx, ptab, plen)
      return fjErr
    let v = JS_GetProperty(ctx, val, atom)
    var vn: T
    if ctx.fromJSFree(v, vn).isErr:
      JS_FreePropertyEnum(ctx, ptab, plen)
      return fjErr
    tmp.add((move(kn), move(vn)))
  JS_FreePropertyEnum(ctx, ptab, plen)
  res = JSKeyValuePair[K, T](s: move(tmp))
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var bool): JSCode =
  let ret = JS_ToBool(ctx, val)
  if ret == -1: # exception
    return fjErr
  res = ret != 0
  fjOk

proc cmpItem(x: EnumMapItem; y: JSAtom): int =
  cmp(uint32(x.atom), uint32(y))

proc fromJSEnumBody(ctx: JSContext; val: JSValueConst; enumId: int;
    enums: openArray[string]; tname: cstring): int32 =
  if not ctx.putEnums(enumId, enums):
    return -1
  let atom = JS_ValueToAtom(ctx, val)
  if atom == JS_ATOM_NULL:
    return -1
  let rtOpaque = JS_GetRuntime(ctx).getOpaque()
  let i = rtOpaque.enumMap[enumId].enums.binarySearch(atom, cmpItem)
  JS_FreeAtom(ctx, atom)
  if i < 0:
    JS_ThrowTypeError(ctx, "invalid value for enumeration %s", tname)
    return -1
  return rtOpaque.enumMap[enumId].enums[i].n

proc getEnumMap[T: enum](t: typedesc[T]): array[T, string] =
  result = array[T, string].default
  for e, s in result.mpairs:
    s = $e

proc fromJS*[T: enum](ctx: JSContext; val: JSValueConst; res: var T):
    JSCode =
  const tname = cstring($T)
  const enumId = getJSEnumId(T)
  const enums = getEnumMap(T)
  let n = ctx.fromJSEnumBody(val, enumId, enums, tname)
  if n == -1:
    return fjErr
  {.push rangeChecks: off.}
  res = T(n)
  {.pop.}
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; tclassid: JSClassID;
    res: var pointer): JSCode =
  if not JS_IsObject(val):
    JS_ThrowTypeError(ctx, "value is not an object")
    return fjErr
  let ctxOpaque = ctx.getOpaque()
  var classid: JSClassID
  var p: pointer
  if JS_VALUE_GET_PTR(ctxOpaque.global) != JS_VALUE_GET_PTR(val):
    p = JS_GetAnyOpaque(val, classid)
  else:
    classid = ctxOpaque.gclass
    p = ctxOpaque.globalObj
  if not ctx.isInstanceOf(classid, tclassid):
    # dumb way to invoke JS_ThrowTypeErrorInvalidClass
    discard JS_GetOpaque2(ctx, JS_UNDEFINED, tclassid)
    return fjErr
  res = p
  fjOk

proc fromJSThis*(ctx: JSContext; val: JSValueConst; tclassid: JSClassID;
    res: var pointer): JSCode =
  let val = if JS_IsUndefined(val):
    JSValueConst(ctx.getOpaque().global)
  else:
    val
  ctx.fromJS(val, tclassid, res)

proc fromJS*[T: object](ctx: JSContext; val: JSValueConst; res: var ptr T):
    JSCode =
  when NimMajor < 2:
    # I don't know why, but Nim 1.6.14 fails to generate the forward decls
    # in C.  So we add a little indirection instead.
    let classId = globalJSTypeMap[getJSTypeID(T)]
  else:
    mixin getClassID
    let classId = getClassID(JSRef[T])
  var x {.noinit.}: pointer
  ?ctx.fromJS(val, classId, x)
  res = cast[ptr T](x)
  fjOk

proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var JSRef[T]):
    JSCode =
  var p: ptr T
  ?ctx.fromJS(val, p)
  res = cast[JSRef[T]](p)
  fjOk

macro fromJSDictBody(ctx: JSContext; val: JSValueConst; res, t: typed) =
  let impl = t.getTypeInst()[1].getImpl()
  let convertStmts = newStmtList()
  let success = ident("success")
  var isOptional = true
  var identDefsStack = @[impl[2]]
  let jsDictType = JSDict.getType()
  var undefInit = newStmtList()
  while identDefsStack.len > 0:
    let def = identDefsStack.pop()
    case def.kind
    of nnkRecList, nnkObjectTy:
      for child in def.children:
        if child.kind != nnkEmpty:
          identDefsStack.add(child)
    of nnkOfInherit:
      let other = def[0].getType()
      if not other.sameType(jsDictType) and not jsDictType.sameType(other):
        identDefsStack.add(other.getTypeInst().getImpl()[2][2])
    else:
      assert def.kind == nnkIdentDefs
      var fallback: NimNode = nil
      var name = def[0]
      if name.kind == nnkPragmaExpr:
        for varPragma in name[1]:
          if varPragma.kind == nnkExprColonExpr:
            if varPragma[0].strVal == "jsdefault":
              fallback = varPragma[1]
          elif varPragma.kind == nnkSym:
            if varPragma.strVal == "jsdefault":
              let typ = def[1]
              fallback = quote do: `typ`.default
        name = name[0]
      if name.kind == nnkPostfix:
        # This is a public field. We are skipping the postfix *
        name = name[1]
      if fallback != nil:
        undefInit.add(quote do: `res`.`name` = `fallback`)
      else:
        isOptional = false
      let nameStr = newStrLitNode($name)
      let it = if fallback != nil:
        quote do:
          let prop = JS_GetPropertyStr(`ctx`, `val`, `nameStr`)
          if JS_IsException(prop):
            return fjErr
          if not JS_IsUndefined(prop):
            if `ctx`.fromJSFree(prop, `res`.`name`) == fjErr:
              return fjErr
      else:
        quote do:
          missing = `nameStr`
          let prop = JS_GetPropertyStr(`ctx`, `val`, missing)
          if JS_IsException(prop):
            return fjErr
          if JS_IsUndefined(prop):
            break `success`
          if `ctx`.fromJSFree(prop, `res`.`name`) == fjErr:
            return fjErr
      convertStmts.add(it)
  let undefCheck = if isOptional:
    quote do:
      if JS_IsUndefined(val) or JS_IsNull(val):
        return fjOk
  else:
    newStmtList()
  result = quote do:
    `undefInit`
    `undefCheck`
    if not JS_IsObject(val):
      JS_ThrowTypeError(ctx, "dictionary is not an object")
      return fjErr
    var missing {.inject.}: cstring = nil
    block `success`:
      `convertStmts`
      return fjOk
    JS_ThrowTypeError(ctx, "missing field %s", missing)
    return fjErr

# For some reason, the compiler can't deal with this.
proc fromJS*[T: JSDict](ctx: JSContext; val: JSValueConst; res: var T):
    JSCode =
  fromJSDictBody(ctx, val, res, T)

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSArrayBuffer):
    JSCode =
  var len {.noinit.}: csize_t
  let p = JS_GetArrayBuffer(ctx, len, val)
  if p == nil:
    return fjErr
  if len > csize_t(int.high):
    JS_ThrowRangeError(ctx, "array buffer size out of range")
    return fjErr
  res = JSArrayBuffer(
    len: cast[int](len),
    p: cast[ptr UncheckedArray[uint8]](p)
  )
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSArrayBufferView):
    JSCode =
  var offset {.noinit.}: csize_t
  var len {.noinit.}: csize_t
  var bytesPerItem {.noinit.}: csize_t
  let jsbuf = JS_GetTypedArrayBuffer(ctx, val, offset, len, bytesPerItem)
  if JS_IsException(jsbuf):
    return fjErr
  if uint64(offset) + uint64(len) > uint64(int32.high):
    JS_FreeValue(ctx, jsbuf)
    JS_ThrowRangeError(ctx, "array buffer view too large")
    return fjErr
  var abuf: JSArrayBuffer
  ?ctx.fromJSFree(jsbuf, abuf)
  res = JSArrayBufferView(
    abuf: abuf,
    offset: cast[int](offset),
    len: cast[int](len),
    bytesPerItem: uint8(bytesPerItem),
    t: JSTypedArrayEnum(JS_GetTypedArrayType(val))
  )
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSValueConst):
    JSCode =
  res = val
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSValue): JSCode =
  res = JS_DupValue(ctx, val)
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSValueTraced):
    JSCode =
  res = trace(JS_DupValue(ctx, val))
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSCallback):
    JSCode =
  if not JS_IsFunction(ctx, val):
    JS_ThrowTypeError(ctx, "function expected")
    return fjErr
  res = JSCallback(ctx.dupTraceObj(val))
  fjOk

proc fromJS*(ctx: JSContext; atom: JSAtom; res: var JSAtom): JSCode =
  res = atom
  fjOk

proc fromJS*(ctx: JSContext; atom: JSAtom; res: var string): JSCode =
  var len {.noinit.}: csize_t
  let cs = JS_AtomToCStringLen(ctx, len, atom)
  ctx.fromJS(cs, len, narrow = false, res)

proc fromJS*(ctx: JSContext; atom: JSAtom; res: var DOMString): JSCode =
  var len {.noinit.}: csize_t
  let cs = JS_AtomToCStringLen(ctx, len, atom)
  if cs == nil:
    return fjErr
  if len > csize_t(int.high):
    JS_FreeCString(ctx, cs)
    JS_ThrowRangeError(ctx, "string length out of bounds")
    return fjErr
  res = initDOMString(cstring(cs), cast[int](len))
  fjOk

proc fromJS*(ctx: JSContext; atom: JSAtom; res: var ByteString): JSCode =
  var len {.noinit.}: csize_t
  let cs = JS_AtomToCStringLen(ctx, len, atom)
  ctx.fromJS(cs, len, res)

{.pop.} # raises: []
