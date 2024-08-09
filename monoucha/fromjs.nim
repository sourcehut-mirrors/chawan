{.push raises: [].}

import std/algorithm
import std/macros
import std/options
import std/tables

import jsopaque
import jstypes
import optshim
import quickjs

proc fromJS*(ctx: JSContext; val: JSValue; res: var string): Opt[void]
proc fromJS*(ctx: JSContext; val: JSValue; res: var int32): Opt[void]
proc fromJS*(ctx: JSContext; val: JSValue; res: var int64): Opt[void]
proc fromJS*(ctx: JSContext; val: JSValue; res: var uint32): Opt[void]
proc fromJS*(ctx: JSContext; val: JSValue; res: var int): Opt[void]
proc fromJS*(ctx: JSContext; val: JSValue; res: var float64): Opt[void]
proc fromJS*[T: tuple](ctx: JSContext; val: JSValue; res: var T): Opt[void]
proc fromJS*[T](ctx: JSContext; val: JSValue; res: var seq[T]): Opt[void]
proc fromJS*[T](ctx: JSContext; val: JSValue; res: var set[T]): Opt[void]
proc fromJS*[A, B](ctx: JSContext; val: JSValue; res: var Table[A, B]):
  Opt[void]
proc fromJS*[T](ctx: JSContext; val: JSValue; res: var Option[T]): Opt[void]
proc fromJS*(ctx: JSContext; val: JSValue; res: var bool): Opt[void]
proc fromJS*[T: enum](ctx: JSContext; val: JSValue; res: var T): Opt[void]
proc fromJS*[T](ctx: JSContext; val: JSValue; res: var ptr T): Opt[void]
proc fromJS*[T: ref object](ctx: JSContext; val: JSValue; res: var T):
  Opt[void]
proc fromJS*[T: JSDict](ctx: JSContext; val: JSValue; res: var T): Opt[void]
proc fromJS*(ctx: JSContext; val: JSValue; res: var JSArrayBuffer): Opt[void]
proc fromJS*(ctx: JSContext; val: JSValue; res: var JSArrayBufferView):
  Opt[void]
proc fromJS*(ctx: JSContext; val: JSValue; res: var JSValue): Opt[void]

func isInstanceOf*(ctx: JSContext; val: JSValue; class: cstring): bool =
  let ctxOpaque = ctx.getOpaque()
  var classid = JS_GetClassID(val)
  let tclassid = ctxOpaque.creg.getOrDefault(class, JS_CLASS_OBJECT)
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
    ctxOpaque.parents.withValue(classid, val):
      classid = val[]
    do:
      classid = 0 # not defined by Chawan; assume parent is Object.
    if classid == 0:
      break
  return found

proc fromJS*(ctx: JSContext; val: JSValue; res: var string): Opt[void] =
  var plen: csize_t
  let outp = JS_ToCStringLen(ctx, addr plen, val) # cstring
  if outp == nil:
    return err()
  res = newString(plen)
  if plen != 0:
    copyMem(addr res[0], cstring(outp), plen)
  JS_FreeCString(ctx, outp)
  return ok()

proc fromJS*(ctx: JSContext; val: JSValue; res: var int32): Opt[void] =
  if JS_ToInt32(ctx, addr res, val) < 0:
    return err()
  return ok()

proc fromJS*(ctx: JSContext; val: JSValue; res: var int64): Opt[void] =
  if JS_ToInt64(ctx, addr res, val) < 0:
    return err()
  return ok()

proc fromJS*(ctx: JSContext; val: JSValue; res: var uint32): Opt[void] =
  if JS_ToUint32(ctx, addr res, val) < 0:
    return err()
  return ok()

proc fromJS*(ctx: JSContext; val: JSValue; res: var int): Opt[void] =
  # Always int32, so we don't risk 32-bit only breakage.
  # If int64 is needed, specify it explicitly.
  #TODO maybe it's better to follow pointer size anyway...?
  var x: int32
  ?ctx.fromJS(val, x)
  res = int(x)
  return ok()

proc fromJS*(ctx: JSContext; val: JSValue; res: var float64): Opt[void] =
  if JS_ToFloat64(ctx, addr res, val) < 0:
    return err()
  return ok()

macro fromJSTupleBody(a: tuple) =
  let len = a.getType().len - 1
  result = newStmtList(quote do:
    var done {.inject.}: bool)
  for i in 0 ..< len:
    result.add(quote do:
      let next = JS_Call(ctx, nextMethod, it, 0, nil)
      let doneVal = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstDone])
      defer:
        JS_FreeValue(ctx, next)
        JS_FreeValue(ctx, doneVal)
      ?ctx.fromJS(doneVal, done)
      if done:
        JS_ThrowTypeError(ctx,
          "too few arguments in sequence (got %d, expected %d)", cint(`i`),
          cint(`len`))
        return err()
      let valueVal = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstValue])
      defer: JS_FreeValue(ctx, valueVal)
      ?ctx.fromJS(valueVal, `a`[`i`])
    )
    if i == len - 1:
      result.add(quote do:
        let next = JS_Call(ctx, nextMethod, it, 0, nil)
        defer: JS_FreeValue(ctx, next)
        let doneVal = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstDone])
        ?ctx.fromJS(doneVal, done)
        var i = `i`
        # we're emulating a sequence, so we must query all remaining parameters
        # too:
        while not done:
          inc i
          let next = JS_Call(ctx, nextMethod, it, 0, nil)
          defer: JS_FreeValue(ctx, next)
          let doneVal = JS_GetProperty(ctx, next,
            ctx.getOpaque().strRefs[jstDone])
          defer: JS_FreeValue(ctx, doneVal)
          ?ctx.fromJS(doneVal, done)
          if done:
            JS_ThrowTypeError(ctx,
              "too many tuple members (got %d, expected %d)", cint(i),
              cint(`len`))
            return err()
          JS_FreeValue(ctx, JS_GetProperty(ctx, next,
            ctx.getOpaque().strRefs[jstValue]))
      )

proc fromJS*[T: tuple](ctx: JSContext; val: JSValue; res: var T): Opt[void] =
  let itprop = JS_GetProperty(ctx, val, ctx.getOpaque().symRefs[jsyIterator])
  if JS_IsException(itprop):
    return err()
  defer: JS_FreeValue(ctx, itprop)
  let it = JS_Call(ctx, itprop, val, 0, nil)
  defer: JS_FreeValue(ctx, it)
  let nextMethod = JS_GetProperty(ctx, it, ctx.getOpaque().strRefs[jstNext])
  if JS_IsException(nextMethod):
    return err()
  defer: JS_FreeValue(ctx, nextMethod)
  fromJSTupleBody(res)
  return ok()

proc fromJS*[T](ctx: JSContext; val: JSValue; res: var seq[T]): Opt[void] =
  let itprop = JS_GetProperty(ctx, val, ctx.getOpaque().symRefs[jsyIterator])
  if JS_IsException(itprop):
    return err()
  defer: JS_FreeValue(ctx, itprop)
  let it = JS_Call(ctx, itprop, val, 0, nil)
  defer: JS_FreeValue(ctx, it)
  let nextMethod = JS_GetProperty(ctx, it, ctx.getOpaque().strRefs[jstNext])
  if JS_IsException(nextMethod):
    return err()
  defer: JS_FreeValue(ctx, nextMethod)
  var tmp = newSeq[T]()
  while true:
    let next = JS_Call(ctx, nextMethod, it, 0, nil)
    defer: JS_FreeValue(ctx, next)
    let doneVal = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstDone])
    defer: JS_FreeValue(ctx, doneVal)
    var done: bool
    ?ctx.fromJS(doneVal, done)
    if done:
      break
    let valueVal = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstValue])
    defer: JS_FreeValue(ctx, valueVal)
    tmp.add(default(T))
    ?ctx.fromJS(valueVal, res[^1])
  res = move(tmp)
  return ok()

proc fromJS*[T](ctx: JSContext; val: JSValue; res: var set[T]): Opt[void] =
  let itprop = JS_GetProperty(ctx, val, ctx.getOpaque().symRefs[jsyIterator])
  if JS_IsException(itprop):
    return err()
  defer: JS_FreeValue(ctx, itprop)
  let it = JS_Call(ctx, itprop, val, 0, nil)
  defer: JS_FreeValue(ctx, it)
  let nextMethod = JS_GetProperty(ctx, it, ctx.getOpaque().strRefs[jstNext])
  if JS_IsException(nextMethod):
    return err()
  defer: JS_FreeValue(ctx, nextMethod)
  var tmp: set[T] = {}
  while true:
    let next = JS_Call(ctx, nextMethod, it, 0, nil)
    defer: JS_FreeValue(ctx, next)
    let doneVal = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstDone])
    defer: JS_FreeValue(ctx, doneVal)
    var done: bool
    ?ctx.fromJS(doneVal, done)
    if done:
      break
    let valueVal = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstValue])
    defer: JS_FreeValue(ctx, valueVal)
    var x: T
    ?ctx.fromJS(valueVal, x)
    tmp.incl(x)
  res = tmp
  return ok()

proc fromJS*[A, B](ctx: JSContext; val: JSValue; res: var Table[A, B]):
    Opt[void] =
  if not JS_IsObject(val):
    if not JS_IsException(val):
      JS_ThrowTypeError(ctx, "object expected")
    return err()
  var ptab: ptr UncheckedArray[JSPropertyEnum]
  var plen: uint32
  let flags = cint(JS_GPN_STRING_MASK)
  if JS_GetOwnPropertyNames(ctx, addr ptab, addr plen, val, flags) == -1:
    # exception
    return err()
  defer:
    for i in 0 ..< plen:
      JS_FreeAtom(ctx, ptab[i].atom)
    js_free(ctx, ptab)
  var tmp = initTable[A, B]()
  for i in 0 ..< plen:
    let atom = ptab[i].atom
    let k = JS_AtomToValue(ctx, atom)
    defer: JS_FreeValue(ctx, k)
    var kn: A
    ?ctx.fromJS(k, kn)
    let v = JS_GetProperty(ctx, val, atom)
    defer: JS_FreeValue(ctx, v)
    var vn: B
    ?ctx.fromJS(v, vn)
    tmp[kn] = move(vn)
  res = move(tmp)
  return ok()

# Option vs Opt:
# Option is for nullable types, e.g. if you want to return either a string
# or null. (This is rather pointless for anything else.)
# Opt is for passing down exceptions received up in the chain.
# So e.g. none(T) translates to JS_NULL, but err() translates to JS_EXCEPTION.
proc fromJS*[T](ctx: JSContext; val: JSValue; res: var Option[T]): Opt[void] =
  if JS_IsNull(val):
    res = none(T)
  else:
    var x: T
    ?ctx.fromJS(val, x)
    res = option(move(x))
  return ok()

proc fromJS*(ctx: JSContext; val: JSValue; res: var bool): Opt[void] =
  let ret = JS_ToBool(ctx, val)
  if ret == -1: # exception
    return err()
  res = ret != 0
  return ok()

type IdentMapItem = tuple[s: string; n: int]

func getIdentMap[T: enum](e: typedesc[T]): seq[IdentMapItem] =
  result = @[]
  for e in T.low .. T.high:
    result.add(($e, int(e)))
  result.sort(proc(x, y: IdentMapItem): int = cmp(x[0], y[0]))

proc fromJSEnumBody(map: openArray[IdentMapItem]; ctx: JSContext; val: JSValue;
    tname: cstring): int =
  var plen: csize_t
  let s = JS_ToCStringLen(ctx, addr plen, val)
  if s == nil:
    return -1
  let i = map.binarySearch(s.toOpenArray(0, int(plen - 1)),
      proc(x: IdentMapItem; y: openArray[char]): int =
    let x = x[0]
    if (let n = cmpMem(cstring(x), unsafeAddr y[0], min(x.len, y.len)); n != 0):
      return n
    return x.len - y.len
  )
  if i == -1:
    JS_ThrowTypeError(ctx, "`%s' is not a valid value for enumeration %s",
      s, tname)
  return i

proc fromJS*[T: enum](ctx: JSContext; val: JSValue; res: var T): Opt[void] =
  const IdentMap = getIdentMap(T)
  const tname = cstring($T)
  if (let i = fromJSEnumBody(IdentMap, ctx, val, tname); i > 0):
    res = cast[T](IdentMap[i].n)
    return ok()
  return err()

proc fromJS(ctx: JSContext; val: JSValue; t: cstring; res: var pointer):
    Opt[void] =
  if JS_IsNull(val):
    res = nil
    return ok()
  if not JS_IsObject(val):
    if not JS_IsException(val):
      JS_ThrowTypeError(ctx, "value is not an object")
    return err()
  if not ctx.isInstanceOf(val, t):
    JS_ThrowTypeError(ctx, "%s expected", t)
    return err()
  res = JS_GetOpaque(val, JS_GetClassID(val))
  return ok()

proc fromJS*[T](ctx: JSContext; val: JSValue; res: var ptr T): Opt[void] =
  var x: pointer
  const tname = cstring($T)
  ?ctx.fromJS(val, tname, x)
  res = cast[ptr T](x)
  return ok()

proc fromJS*[T: ref object](ctx: JSContext; val: JSValue; res: var T):
    Opt[void] =
  var x: pointer
  const tname = cstring($T)
  ?ctx.fromJS(val, tname, x)
  res = cast[T](x)
  return ok()

proc fromJSThis*[T: ptr object](ctx: JSContext; val: JSValue; res: var T):
    Opt[void] =
  return ctx.fromJS(val, res)

proc fromJSThis*[T: ref object](ctx: JSContext; val: JSValue; res: var T):
    Opt[void] =
  # translate undefined -> global
  if JS_IsUndefined(val):
    return ctx.fromJS(ctx.getOpaque().global, res)
  return ctx.fromJS(val, res)

macro fromJSDictBody(ctx: JSContext; val: JSValue; res, t: typed) =
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

proc fromJS*[T: JSDict](ctx: JSContext; val: JSValue; res: var T): Opt[void] =
  fromJSDictBody(ctx, val, res, T)

proc fromJS*(ctx: JSContext; val: JSValue; res: var JSArrayBuffer): Opt[void] =
  var len: csize_t
  let p = JS_GetArrayBuffer(ctx, addr len, val)
  if p == nil:
    return err()
  res = JSArrayBuffer(
    len: len,
    p: cast[ptr UncheckedArray[uint8]](p)
  )
  return ok()

proc fromJS*(ctx: JSContext; val: JSValue; res: var JSArrayBufferView):
    Opt[void] =
  var offset: csize_t
  var nmemb: csize_t
  var nsize: csize_t
  let jsbuf = JS_GetTypedArrayBuffer(ctx, val, addr offset, addr nmemb,
    addr nsize)
  var abuf: JSArrayBuffer
  ?ctx.fromJS(jsbuf, abuf)
  res = JSArrayBufferView(
    abuf: abuf,
    offset: offset,
    nmemb: nmemb,
    nsize: nsize
  )
  return ok()

proc fromJS*(ctx: JSContext; val: JSValue; res: var JSValue): Opt[void] =
  res = val
  return ok()

const JS_ATOM_TAG_INT = 1u32 shl 31

func JS_IsNumber*(v: JSAtom): JS_BOOL =
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

{.pop.}
