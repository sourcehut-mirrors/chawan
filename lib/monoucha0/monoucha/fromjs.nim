{.push raises: [].}

import std/algorithm
import std/macros
import std/options
import std/tables

import jsopaque
import jstypes
import optshim
import quickjs
import tojs

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var string): Opt[void]
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int32): Opt[void]
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int64): Opt[void]
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var uint32): Opt[void]
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int): Opt[void]
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var float64): Opt[void]
proc fromJS*[T: tuple](ctx: JSContext; val: JSValueConst; res: var T): Opt[void]
proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var seq[T]): Opt[void]
proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var set[T]): Opt[void]
proc fromJS*[A, B](ctx: JSContext; val: JSValueConst;
  res: var JSKeyValuePair[A, B]): Opt[void]
proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var Option[T]):
  Opt[void]
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var bool): Opt[void]
proc fromJS*[T: enum](ctx: JSContext; val: JSValueConst; res: var T): Opt[void]
proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var ptr T): Opt[void]
proc fromJS*[T: ref object](ctx: JSContext; val: JSValueConst; res: var T):
  Opt[void]
proc fromJS*[T: JSDict](ctx: JSContext; val: JSValueConst; res: var T):
  Opt[void]
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSArrayBuffer):
  Opt[void]
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSArrayBufferView):
  Opt[void]
proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSValueConst):
  Opt[void]

proc isInstanceOf*(ctx: JSContext; val: JSValueConst; tclassid: JSClassID):
    bool =
  let ctxOpaque = ctx.getOpaque()
  let rtOpaque = JS_GetRuntime(ctx).getOpaque()
  var classid = JS_GetClassID(val)
  if classid == JS_CLASS_OBJECT:
    let p0 = JS_VALUE_GET_PTR(ctxOpaque.global)
    let p1 = JS_VALUE_GET_PTR(val)
    if p0 == p1:
      classid = ctxOpaque.gclass
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

proc fromJSFree*[T](ctx: JSContext; val: JSValue; res: var T): Opt[void] =
  result = ctx.fromJS(val, res)
  JS_FreeValue(ctx, val)

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var string): Opt[void] =
  var plen {.noinit.}: csize_t
  let outp = JS_ToCStringLen(ctx, plen, val) # cstring
  if outp == nil:
    return err()
  res = newString(plen)
  if plen != 0:
    copyMem(addr res[0], cstring(outp), plen)
  JS_FreeCString(ctx, outp)
  return ok()

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int32): Opt[void] =
  var n {.noinit.}: int32
  if JS_ToInt32(ctx, n, val) < 0:
    return err()
  res = n
  return ok()

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int64): Opt[void] =
  var n {.noinit.}: int64
  if JS_ToInt64(ctx, n, val) < 0:
    return err()
  res = n
  return ok()

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var uint32): Opt[void] =
  var n {.noinit.}: uint32
  if JS_ToUint32(ctx, n, val) < 0:
    return err()
  res = n
  return ok()

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var int): Opt[void] =
  when sizeof(int) > 4:
    var x: int64
  else:
    var x: int32
  ?ctx.fromJS(val, x)
  res = int(x)
  return ok()

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var float64): Opt[void] =
  var n {.noinit.}: float64
  if JS_ToFloat64(ctx, n, val) < 0:
    return err()
  res = n
  return ok()

proc readTupleDone(ctx: JSContext; it, nextMethod: JSValueConst): Opt[void] =
  let next = JS_Call(ctx, nextMethod, it, 0, nil)
  let ctxOpaque = ctx.getOpaque()
  let doneVal = JS_GetProperty(ctx, next, ctxOpaque.strRefs[jstDone])
  var done = false
  if ctx.fromJSFree(doneVal, done).isErr or done:
    JS_FreeValue(ctx, next)
    if not done:
      return err()
    return ok()
  while true:
    let next = JS_Call(ctx, nextMethod, it, 0, nil)
    let doneVal = JS_GetProperty(ctx, next, ctxOpaque.strRefs[jstDone])
    var done = false
    if ctx.fromJSFree(doneVal, done).isErr or done:
      JS_FreeValue(ctx, next)
      if done:
        JS_ThrowTypeError(ctx, "too many tuple members")
      return err()
    JS_FreeValue(ctx, JS_GetProperty(ctx, next, ctxOpaque.strRefs[jstValue]))
    JS_FreeValue(ctx, next)
  ok()

proc fromJSTupleBody[T](ctx: JSContext; it, nextMethod: JSValueConst;
    res: var T): Opt[void] =
  for f in res.fields:
    let next = JS_Call(ctx, nextMethod, it, 0, nil)
    let doneVal = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstDone])
    var done = false
    if ctx.fromJSFree(doneVal, done).isErr or done:
      if done:
        JS_ThrowTypeError(ctx, "too few arguments in sequence")
      JS_FreeValue(ctx, next)
      return err()
    let valueVal = JS_GetProperty(ctx, next,
      ctx.getOpaque().strRefs[jstValue])
    JS_FreeValue(ctx, next)
    ?ctx.fromJSFree(valueVal, f)
  ctx.readTupleDone(it, nextMethod)

proc fromJS*[T: tuple](ctx: JSContext; val: JSValueConst; res: var T):
    Opt[void] =
  let it = JS_Invoke(ctx, val, ctx.getOpaque().symRefs[jsyIterator], 0, nil)
  let nextMethod = JS_GetProperty(ctx, it, ctx.getOpaque().strRefs[jstNext])
  if JS_IsException(nextMethod):
    JS_FreeValue(ctx, it)
    return err()
  result = ctx.fromJSTupleBody(it, nextMethod, res)
  JS_FreeValue(ctx, it)
  JS_FreeValue(ctx, nextMethod)

proc fromJSSeqIt(ctx: JSContext; it, nextMethod: JSValueConst;
    res: var JSValue): Opt[bool] =
  let next = JS_Call(ctx, nextMethod, it, 0, nil)
  let doneVal = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstDone])
  var done = false
  if ctx.fromJSFree(doneVal, done).isOk and not done:
    res = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstValue])
    JS_FreeValue(ctx, next)
    return ok(false)
  JS_FreeValue(ctx, next)
  if not done:
    return err() # conversion error
  ok(true) # actually done

proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var seq[T]): Opt[void] =
  let it = JS_Invoke(ctx, val, ctx.getOpaque().symRefs[jsyIterator], 0, nil)
  let nextMethod = JS_GetProperty(ctx, it, ctx.getOpaque().strRefs[jstNext])
  if JS_IsException(nextMethod):
    JS_FreeValue(ctx, it)
    return err()
  var status = ok()
  var tmp = newSeq[T]()
  while status.isOk:
    var val: JSValue
    let done = ctx.fromJSSeqIt(it, nextMethod, val)
    if done.isErr:
      status = err()
      break
    if done.get:
      res = move(tmp)
      break
    tmp.add(default(T))
    status = ctx.fromJSFree(val, tmp[^1])
  JS_FreeValue(ctx, it)
  JS_FreeValue(ctx, nextMethod)
  return status

proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var set[T]): Opt[void] =
  let it = JS_Invoke(ctx, val, ctx.getOpaque().symRefs[jsyIterator], 0, nil)
  let nextMethod = JS_GetProperty(ctx, it, ctx.getOpaque().strRefs[jstNext])
  if JS_IsException(nextMethod):
    JS_FreeValue(ctx, it)
    return err()
  var status = ok()
  var tmp: set[T] = {}
  while status.isOk:
    var val: JSValue
    let next = ctx.fromJSSeqIt(it, nextMethod, val)
    if next.isErr:
      status = err()
      break
    if next.get:
      res = tmp
      break
    var x: T
    status = ctx.fromJSFree(val, x)
    tmp.incl(x)
  JS_FreeValue(ctx, it)
  JS_FreeValue(ctx, nextMethod)
  return status

proc fromJS*[A, B](ctx: JSContext; val: JSValueConst;
    res: var JSKeyValuePair[A, B]): Opt[void] =
  if JS_IsException(val):
    return err()
  var ptab: ptr UncheckedArray[JSPropertyEnum]
  var plen: uint32
  let flags = cint(JS_GPN_STRING_MASK)
  if JS_GetOwnPropertyNames(ctx, addr ptab, addr plen, val, flags) == -1:
    # exception
    return err()
  var tmp = newSeqOfCap[tuple[name: A, value: B]](plen)
  for i in 0 ..< plen:
    let atom = ptab[i].atom
    let k = JS_AtomToValue(ctx, atom)
    var kn: A
    if ctx.fromJSFree(k, kn).isErr:
      JS_FreePropertyEnum(ctx, ptab, plen)
      return err()
    let v = JS_GetProperty(ctx, val, atom)
    var vn: B
    if ctx.fromJSFree(v, vn).isErr:
      JS_FreePropertyEnum(ctx, ptab, plen)
      return err()
    tmp.add((move(kn), move(vn)))
  JS_FreePropertyEnum(ctx, ptab, plen)
  res = JSKeyValuePair[A, B](s: move(tmp))
  return ok()

# Option vs Opt:
# Option is for nullable types, e.g. if you want to return either a string
# or null. (This is rather pointless for anything else.)
# Opt is for passing down exceptions received up in the chain.
# So e.g. none(T) translates to JS_NULL, but err() translates to JS_EXCEPTION.
proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var Option[T]):
    Opt[void] =
  if JS_IsNull(val):
    res = none(T)
  else:
    var x: T
    ?ctx.fromJS(val, x)
    res = option(move(x))
  return ok()

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var bool): Opt[void] =
  let ret = JS_ToBool(ctx, val)
  if ret == -1: # exception
    return err()
  res = ret != 0
  return ok()

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
    Opt[void] =
  const IdentMap = getIdentMap(T)
  const tname = cstring($T)
  if (let i = fromJSEnumBody(IdentMap, ctx, val, tname); i >= 0):
    res = T(IdentMap[i].n)
    return ok()
  err()

proc fromJS(ctx: JSContext; val: JSValueConst; nimt: pointer; res: var pointer):
    Opt[void] =
  if not JS_IsObject(val):
    if not JS_IsException(val):
      JS_ThrowTypeError(ctx, "value is not an object")
    return err()
  let p = JS_GetOpaque(val, JS_GetClassID(val))
  let rtOpaque = JS_GetRuntime(ctx).getOpaque()
  let tclassid = rtOpaque.typemap.getOrDefault(nimt, JS_CLASS_OBJECT)
  if p == nil or not ctx.isInstanceOf(val, tclassid):
    let proto = JS_GetClassProto(ctx, tclassid)
    let name = JS_GetProperty(ctx, proto,
      ctx.getOpaque().symRefs[jsyToStringTag])
    JS_FreeValue(ctx, proto)
    let cs = JS_ToCString(ctx, name)
    if cs != nil:
      JS_ThrowTypeError(ctx, "%s expected", cs)
      JS_FreeCString(ctx, cs)
    JS_FreeValue(ctx, name)
    return err()
  res = p
  return ok()

proc fromJS*[T](ctx: JSContext; val: JSValueConst; res: var ptr T): Opt[void] =
  let nimt = getTypePtr(T)
  var x: pointer
  ?ctx.fromJS(val, nimt, x)
  res = cast[ptr T](x)
  return ok()

proc fromJS*[T: ref object](ctx: JSContext; val: JSValueConst; res: var T):
    Opt[void] =
  let nimt = getTypePtr(T)
  var x: pointer
  ?ctx.fromJS(val, nimt, x)
  res = cast[T](x)
  return ok()

proc fromJSThis*[T: ref object](ctx: JSContext; val: JSValueConst; res: var T):
    Opt[void] =
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
  var undefInit = newNimNode(nnkObjConstr).add(t)
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
      if fallback == nil:
        isOptional = false
      elif isOptional:
        undefInit.add(name.newColonExpr(fallback))
      var it = newStmtList()
      let nameStr = newStrLitNode($name)
      it.add(quote do:
        let prop {.inject.} = JS_GetPropertyStr(`ctx`, `val`, `nameStr`)
      )
      let missingStmt = if fallback == nil:
        quote do:
          missing = `nameStr`
          break `success`
      else:
        quote do:
          `res`.`name` = `fallback`
      it.add(quote do:
        if not JS_IsUndefined(prop):
          res.toFree.vals.add(prop)
          ?`ctx`.fromJS(prop, `res`.`name`)
        else:
          `missingStmt`
      )
      convertStmts.add(newBlockStmt(it))
  let undefCheck = if isOptional:
    quote do:
      if JS_IsUndefined(val) or JS_IsNull(val):
        res = `undefInit`
        return ok()
  else:
    newStmtList()
  result = quote do:
    `undefCheck`
    if not JS_IsObject(val):
      if not JS_IsException(val):
        JS_ThrowTypeError(ctx, "dictionary is not an object")
      return err()
    # Note: following in-place construction is an optimization documented in the
    # manual.
    res = T(toFree: JSDictToFreeAux(ctx: ctx))
    var missing {.inject.}: cstring = nil
    block `success`:
      `convertStmts`
    if missing != nil:
      JS_ThrowTypeError(ctx, "missing field %s", missing)
      return err()
    return ok()

# For some reason, the compiler can't deal with this.
proc fromJS*[T: JSDict](ctx: JSContext; val: JSValueConst; res: var T):
    Opt[void] =
  fromJSDictBody(ctx, val, res, T)

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSArrayBuffer):
    Opt[void] =
  var len {.noinit.}: csize_t
  let p = JS_GetArrayBuffer(ctx, len, val)
  if p == nil:
    return err()
  res = JSArrayBuffer(len: len, p: cast[ptr UncheckedArray[uint8]](p))
  return ok()

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSArrayBufferView):
    Opt[void] =
  var offset {.noinit.}: csize_t
  var nmemb {.noinit.}: csize_t
  var nsize {.noinit.}: csize_t
  let jsbuf = JS_GetTypedArrayBuffer(ctx, val, offset, nmemb, nsize)
  if JS_IsException(jsbuf):
    return err()
  var abuf: JSArrayBuffer
  ?ctx.fromJSFree(jsbuf, abuf)
  res = JSArrayBufferView(
    abuf: abuf,
    offset: offset,
    nmemb: nmemb,
    nsize: nsize,
    t: JS_GetTypedArrayType(val)
  )
  return ok()

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var JSValueConst):
    Opt[void] =
  res = val
  return ok()

const JS_ATOM_TAG_INT = 1u32 shl 31

proc JS_IsNumber*(v: JSAtom): JS_BOOL =
  return (uint32(v) and JS_ATOM_TAG_INT) != 0

proc fromJS*(ctx: JSContext; atom: JSAtom; res: var JSAtom): Opt[void] =
  res = atom
  return ok()

proc fromJS*(ctx: JSContext; atom: JSAtom; res: var uint32): Opt[void] =
  if JS_IsNumber(atom):
    res = uint32(atom) and (not JS_ATOM_TAG_INT)
    return ok()
  return err()

proc fromJS*(ctx: JSContext; atom: JSAtom; res: var string): Opt[void] =
  let cs = JS_AtomToCString(ctx, atom)
  if cs == nil:
    return err()
  res = $cs
  JS_FreeCString(ctx, cs)
  return ok()

{.pop.} # raises: []
