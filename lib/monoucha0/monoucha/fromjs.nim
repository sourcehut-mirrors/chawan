{.push raises: [].}

import std/algorithm
import std/macros
import std/tables

import jsopaque
import jstypes
import quickjs
import tojs

type FromJSResult* = enum
  fjErr, fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var string): FromJSResult
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int16): FromJSResult
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int32): FromJSResult
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int64): FromJSResult
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var uint16): FromJSResult
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var uint32): FromJSResult
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int): FromJSResult
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var float64): FromJSResult
proc fromJS*[T: tuple](ctx: JSContext; val: JSValueConst; res: var T):
  FromJSResult
proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var seq[T]):
  FromJSResult
proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var set[T]):
  FromJSResult
proc fromJS*[A, B](ctx: JSContext; val: JSValueConst;
  res: var JSKeyValuePair[A, B]): FromJSResult
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var bool): FromJSResult
proc fromJS*[T: enum](ctx: JSContext; val: JSValueConst; res: var T):
  FromJSResult
proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var ptr T): FromJSResult
proc fromJS*[T: ref object](ctx: JSContext; val: JSValueConst; res: var T):
  FromJSResult
proc fromJS*[T: JSDict](ctx: JSContext; val: JSValueConst; res: var T):
  FromJSResult
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSArrayBuffer):
  FromJSResult
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSArrayBufferView):
  FromJSResult
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSValueConst):
  FromJSResult

template isOk*(res: FromJSResult): bool =
  res == fjOk

template isErr*(res: FromJSResult): bool =
  res == fjErr

template `?`(res: FromJSResult) =
  if res == fjErr:
    return fjErr

proc isInstanceOf(ctx: JSContext; classid, tclassid: JSClassID): bool =
  let rtOpaque = JS_GetRuntime(ctx).getOpaque()
  var classid = classid
  var found = false
  while true:
    if classid == tclassid:
      found = true
      break
    if int(classid) < rtOpaque.classes.len:
      classid = rtOpaque.classes[int(classid)].parent
    else:
      classid = 0 # not defined by us; assume parent is Object.
    if classid == 0:
      break
  return found

proc isSequence*(ctx: JSContext; o: JSValueConst): bool =
  if not JS_IsObject(o):
    return false
  let prop = JS_GetProperty(ctx, o, ctx.getOpaque().symRefs[jsyIterator])
  # prop can't be exception (throws_ref_error is 0 and tag is object)
  result = not JS_IsUndefined(prop)
  JS_FreeValue(ctx, prop)

proc fromJSFree*[T](ctx: JSContext; val: JSValue; res: var T): FromJSResult =
  result = ctx.fromJS(val, res)
  JS_FreeValue(ctx, val)

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var string): FromJSResult =
  var plen {.noinit.}: csize_t
  let outp = JS_ToCStringLen(ctx, plen, val) # cstring
  if outp == nil:
    return fjErr
  res = newString(plen)
  if plen != 0:
    copyMem(addr res[0], cstring(outp), plen)
  JS_FreeCString(ctx, outp)
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int16): FromJSResult =
  var n {.noinit.}: int32
  if JS_ToInt32(ctx, n, val) < 0:
    return fjErr
  res = cast[int16](n)
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int32): FromJSResult =
  var n {.noinit.}: int32
  if JS_ToInt32(ctx, n, val) < 0:
    return fjErr
  res = n
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int64): FromJSResult =
  var n {.noinit.}: int64
  if JS_ToInt64(ctx, n, val) < 0:
    return fjErr
  res = n
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var uint16): FromJSResult =
  var n {.noinit.}: uint32
  if JS_ToUint32(ctx, n, val) < 0:
    return fjErr
  res = uint16(n)
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var uint32): FromJSResult =
  var n {.noinit.}: uint32
  if JS_ToUint32(ctx, n, val) < 0:
    return fjErr
  res = n
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int): FromJSResult =
  when sizeof(int) > 4:
    var x: int64
  else:
    var x: int32
  ?ctx.fromJS(val, x)
  res = int(x)
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var float64): FromJSResult =
  var n {.noinit.}: float64
  if JS_ToFloat64(ctx, n, val) < 0:
    return fjErr
  res = n
  fjOk

proc readTupleDone(ctx: JSContext; it, nextMethod: JSValueConst): FromJSResult =
  let next = JS_Call(ctx, nextMethod, it, 0, nil)
  let ctxOpaque = ctx.getOpaque()
  let doneVal = JS_GetProperty(ctx, next, ctxOpaque.strRefs[jstDone])
  var done = false
  if ctx.fromJSFree(doneVal, done).isErr or done:
    JS_FreeValue(ctx, next)
    if not done:
      return fjErr
    return fjOk
  while true:
    let next = JS_Call(ctx, nextMethod, it, 0, nil)
    let doneVal = JS_GetProperty(ctx, next, ctxOpaque.strRefs[jstDone])
    var done = false
    if ctx.fromJSFree(doneVal, done).isErr or done:
      JS_FreeValue(ctx, next)
      if done:
        JS_ThrowTypeError(ctx, "too many tuple members")
      return fjErr
    JS_FreeValue(ctx, JS_GetProperty(ctx, next, ctxOpaque.strRefs[jstValue]))
    JS_FreeValue(ctx, next)
  fjOk

proc fromJSTupleBody[T](ctx: JSContext; it, nextMethod: JSValueConst;
    res: var T): FromJSResult =
  for f in res.fields:
    let next = JS_Call(ctx, nextMethod, it, 0, nil)
    let doneVal = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstDone])
    var done = false
    if ctx.fromJSFree(doneVal, done).isErr or done:
      if done:
        JS_ThrowTypeError(ctx, "too few arguments in sequence")
      JS_FreeValue(ctx, next)
      return fjErr
    let valueVal = JS_GetProperty(ctx, next,
      ctx.getOpaque().strRefs[jstValue])
    JS_FreeValue(ctx, next)
    ?ctx.fromJSFree(valueVal, f)
  ctx.readTupleDone(it, nextMethod)

proc fromJS*[T: tuple](ctx: JSContext; val: JSValueConst; res: var T):
    FromJSResult =
  let it = JS_Invoke(ctx, val, ctx.getOpaque().symRefs[jsyIterator], 0, nil)
  let nextMethod = JS_GetProperty(ctx, it, ctx.getOpaque().strRefs[jstNext])
  if JS_IsException(nextMethod):
    JS_FreeValue(ctx, it)
    return fjErr
  result = ctx.fromJSTupleBody(it, nextMethod, res)
  JS_FreeValue(ctx, it)
  JS_FreeValue(ctx, nextMethod)

type SeqItResult = enum
  sirDone, sirContinue, sirException

proc fromJSSeqIt(ctx: JSContext; it, nextMethod: JSValueConst;
    res: var JSValue): SeqItResult =
  let next = JS_Call(ctx, nextMethod, it, 0, nil)
  let doneVal = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstDone])
  var done = false
  if ctx.fromJSFree(doneVal, done).isOk and not done:
    res = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstValue])
    JS_FreeValue(ctx, next)
    return sirContinue
  JS_FreeValue(ctx, next)
  if not done:
    return sirException # conversion error
  sirDone # actually done

proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var seq[T]): FromJSResult =
  let it = JS_Invoke(ctx, val, ctx.getOpaque().symRefs[jsyIterator], 0, nil)
  let nextMethod = JS_GetProperty(ctx, it, ctx.getOpaque().strRefs[jstNext])
  if JS_IsException(nextMethod):
    JS_FreeValue(ctx, it)
    return fjErr
  var status = fjOk
  var tmp = newSeq[T]()
  while status.isOk:
    var val: JSValue
    case ctx.fromJSSeqIt(it, nextMethod, val)
    of sirException:
      status = fjErr
      break
    of sirDone:
      res = move(tmp)
      break
    of sirContinue:
      tmp.add(default(T))
      status = ctx.fromJSFree(val, tmp[^1])
  JS_FreeValue(ctx, it)
  JS_FreeValue(ctx, nextMethod)
  status

proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var set[T]): FromJSResult =
  let it = JS_Invoke(ctx, val, ctx.getOpaque().symRefs[jsyIterator], 0, nil)
  let nextMethod = JS_GetProperty(ctx, it, ctx.getOpaque().strRefs[jstNext])
  if JS_IsException(nextMethod):
    JS_FreeValue(ctx, it)
    return fjErr
  var status = fjOk
  var tmp: set[T] = {}
  while status.isOk:
    var val: JSValue
    case ctx.fromJSSeqIt(it, nextMethod, val)
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
  JS_FreeValue(ctx, it)
  JS_FreeValue(ctx, nextMethod)
  status

proc fromJS*[A, B](ctx: JSContext; val: JSValueConst;
    res: var JSKeyValuePair[A, B]): FromJSResult =
  if JS_IsException(val):
    return fjErr
  var ptab: ptr UncheckedArray[JSPropertyEnum]
  var plen: uint32
  let flags = cint(JS_GPN_STRING_MASK)
  if JS_GetOwnPropertyNames(ctx, addr ptab, addr plen, val, flags) == -1:
    # exception
    return fjErr
  var tmp = newSeqOfCap[tuple[name: A, value: B]](plen)
  for i in 0 ..< plen:
    let atom = ptab[i].atom
    let k = JS_AtomToValue(ctx, atom)
    var kn: A
    if ctx.fromJSFree(k, kn).isErr:
      JS_FreePropertyEnum(ctx, ptab, plen)
      return fjErr
    let v = JS_GetProperty(ctx, val, atom)
    var vn: B
    if ctx.fromJSFree(v, vn).isErr:
      JS_FreePropertyEnum(ctx, ptab, plen)
      return fjErr
    tmp.add((move(kn), move(vn)))
  JS_FreePropertyEnum(ctx, ptab, plen)
  res = JSKeyValuePair[A, B](s: move(tmp))
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var bool): FromJSResult =
  let ret = JS_ToBool(ctx, val)
  if ret == -1: # exception
    return fjErr
  res = ret != 0
  fjOk

type IdentMapItem = tuple[s: string; n: int]

proc getIdentMap[T: enum](e: typedesc[T]): seq[IdentMapItem] =
  result = @[]
  for e in T.low .. T.high:
    result.add(($e, int(e)))
  result.sort(proc(x, y: IdentMapItem): int = cmp(x.s, y.s))

proc cmpItemOA(x: IdentMapItem; y: openArray[char]): int =
  let xlen = x.s.len
  let L = min(xlen, y.len)
  if L > 0:
    let n = cmpMem(unsafeAddr x.s[0], unsafeAddr y[0], L)
    if n != 0:
      return n
  return xlen - y.len

proc fromJSEnumBody(map: openArray[IdentMapItem]; ctx: JSContext;
    val: JSValueConst; tname: cstring): int =
  var plen {.noinit.}: csize_t
  let s = JS_ToCStringLen(ctx, plen, val)
  if s == nil:
    return -1
  let i = map.binarySearch(s.toOpenArray(0, int(plen) - 1), cmpItemOA)
  if i == -1:
    JS_ThrowTypeError(ctx, "`%s' is not a valid value for enumeration %s",
      s, tname)
  return i

proc fromJS*[T: enum](ctx: JSContext; val: JSValueConst; res: var T):
    FromJSResult =
  const IdentMap = getIdentMap(T)
  const tname = cstring($T)
  if (let i = fromJSEnumBody(IdentMap, ctx, val, tname); i >= 0):
    res = T(IdentMap[i].n)
    return fjOk
  fjErr

proc fromJS(ctx: JSContext; val: JSValueConst; nimt: pointer; res: var pointer):
    FromJSResult =
  if not JS_IsObject(val):
    if not JS_IsException(val):
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
  let rtOpaque = JS_GetRuntime(ctx).getOpaque()
  let tclassid = rtOpaque.typemap.getOrDefault(nimt, 0)
  if p == nil or not ctx.isInstanceOf(classid, tclassid):
    # dumb way to invoke JS_ThrowTypeErrorInvalidClass
    discard JS_GetOpaque2(ctx, JS_UNDEFINED, tclassid)
    return fjErr
  res = p
  fjOk

proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var ptr T): FromJSResult =
  let nimt = getTypePtr(T)
  var x: pointer
  ?ctx.fromJS(val, nimt, x)
  res = cast[ptr T](x)
  fjOk

proc fromJS*[T: ref object](ctx: JSContext; val: JSValueConst; res: var T):
    FromJSResult =
  let nimt = getTypePtr(T)
  var x: pointer
  ?ctx.fromJS(val, nimt, x)
  res = cast[T](x)
  fjOk

proc fromJSThis*[T: ref object](ctx: JSContext; val: JSValueConst; res: var T):
    FromJSResult =
  # translate undefined -> global
  if JS_IsUndefined(val):
    return ctx.fromJS(ctx.getOpaque().global, res)
  return ctx.fromJS(val, res)

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
      if $name == "toFree":
        continue
      if fallback != nil:
        undefInit.add(quote do: `res`.`name` = `fallback`)
      else:
        isOptional = false
      let nameStr = newStrLitNode($name)
      let it = if fallback != nil:
        quote do:
          let prop = JS_GetPropertyStr(`ctx`, `val`, `nameStr`)
          if not JS_IsUndefined(prop):
            res.toFree.vals.add(prop)
            if `ctx`.fromJS(prop, `res`.`name`) == fjErr:
              return fjErr
      else:
        quote do:
          missing = `nameStr`
          let prop = JS_GetPropertyStr(`ctx`, `val`, missing)
          if JS_IsUndefined(prop):
            break `success`
          res.toFree.vals.add(prop)
          if `ctx`.fromJS(prop, `res`.`name`) == fjErr:
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
      if not JS_IsException(val):
        JS_ThrowTypeError(ctx, "dictionary is not an object")
      return fjErr
    res.toFree = JSDictToFreeAux(ctx: ctx)
    var missing {.inject.}: cstring = nil
    block `success`:
      `convertStmts`
      return fjOk
    JS_ThrowTypeError(ctx, "missing field %s", missing)
    return fjErr

# For some reason, the compiler can't deal with this.
proc fromJS*[T: JSDict](ctx: JSContext; val: JSValueConst; res: var T):
    FromJSResult =
  fromJSDictBody(ctx, val, res, T)

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSArrayBuffer):
    FromJSResult =
  var len {.noinit.}: csize_t
  let p = JS_GetArrayBuffer(ctx, len, val)
  if p == nil:
    return fjErr
  res = JSArrayBuffer(len: len, p: cast[ptr UncheckedArray[uint8]](p))
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSArrayBufferView):
    FromJSResult =
  var offset {.noinit.}: csize_t
  var nmemb {.noinit.}: csize_t
  var nsize {.noinit.}: csize_t
  let jsbuf = JS_GetTypedArrayBuffer(ctx, val, offset, nmemb, nsize)
  if JS_IsException(jsbuf):
    return fjErr
  var abuf: JSArrayBuffer
  ?ctx.fromJSFree(jsbuf, abuf)
  res = JSArrayBufferView(
    abuf: abuf,
    offset: offset,
    nmemb: nmemb,
    nsize: nsize,
    t: JS_GetTypedArrayType(val)
  )
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSValueConst):
    FromJSResult =
  res = val
  fjOk

proc fromJS*(ctx: JSContext; atom: JSAtom; res: var JSAtom): FromJSResult =
  res = atom
  fjOk

proc fromJS*(ctx: JSContext; atom: JSAtom; res: var string): FromJSResult =
  var len: csize_t
  let cs = JS_AtomToCStringLen(ctx, addr len, atom)
  if cs == nil:
    return fjErr
  if len > csize_t(int.high):
    JS_FreeCString(ctx, cs)
    JS_ThrowRangeError(ctx, "string length out of bounds")
    return fjErr
  res = newString(int(len))
  if len > 0:
    copyMem(addr res[0], cast[pointer](cs), len)
  JS_FreeCString(ctx, cs)
  fjOk

{.pop.} # raises: []
