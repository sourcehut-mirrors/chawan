import std/macros
import std/options
import std/tables
import std/unicode

import jserror
import jsopaque
import jstypes
import optshim
import quickjs

proc fromJS*[T](ctx: JSContext; val: JSValue): JSResult[T]

func isInstanceOfNonGlobal(ctx: JSContext; val: JSValue; class: string): bool =
  let ctxOpaque = ctx.getOpaque()
  var classid = JS_GetClassID(val)
  let tclassid = ctxOpaque.creg[class]
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

func isInstanceOfGlobal(ctx: JSContext; val: JSValue; class: string): bool =
  let ctxOpaque = ctx.getOpaque()
  #TODO gparent only works for a single level. (But this is not really a
  # problem right now, because our global objects have at most one inheritance
  # level.)
  if ctx.isGlobal(class) or ctxOpaque.creg[class] == ctxOpaque.gparent:
    # undefined -> global
    if JS_IsUndefined(val):
      return true
    if JS_IsObject(val):
      let global = JS_GetGlobalObject(ctx)
      let p0 = JS_VALUE_GET_PTR(global)
      let p1 = JS_VALUE_GET_PTR(val)
      JS_FreeValue(ctx, global)
      if p0 == p1:
        return true
  return false

func isInstanceOf*(ctx: JSContext; val: JSValue; class: string): bool =
  return ctx.isInstanceOfGlobal(val, class) or
    ctx.isInstanceOfNonGlobal(val, class)

func toString(ctx: JSContext; val: JSValue): Opt[string] =
  var plen: csize_t
  let outp = JS_ToCStringLen(ctx, addr plen, val) # cstring
  if outp != nil:
    var ret = newString(plen)
    if plen != 0:
      prepareMutation(ret)
      copyMem(addr ret[0], outp, plen)
    result = ok(ret)
    JS_FreeCString(ctx, outp)

func fromJSString(ctx: JSContext; val: JSValue): JSResult[string] =
  var plen: csize_t
  let outp = JS_ToCStringLen(ctx, addr plen, val) # cstring
  if outp == nil:
    return err(nil)
  var ret = newString(plen)
  if plen != 0:
    prepareMutation(ret)
    copyMem(addr ret[0], outp, plen)
  JS_FreeCString(ctx, outp)
  return ok(ret)

func fromJSInt[T: SomeInteger](ctx: JSContext; val: JSValue): JSResult[T] =
  when T is int:
    # Always int32, so we don't risk 32-bit only breakage.
    # If int64 is needed, specify it explicitly.
    var ret: int32
    if JS_ToInt32(ctx, addr ret, val) < 0:
      return err(nil)
    return ok(int(ret))
  elif T is int32:
    var ret: int32
    if JS_ToInt32(ctx, addr ret, val) < 0:
      return err(nil)
    return ok(ret)
  elif T is int64:
    var ret: int64
    if JS_ToInt64(ctx, addr ret, val) < 0:
      return err(nil)
    return ok(ret)
  elif T is uint32:
    var ret: uint32
    if JS_ToUint32(ctx, addr ret, val) < 0:
      return err(nil)
    return ok(ret)
  else:
    static:
      error($T & " cannot be converted to JS automatically")

proc fromJSFloat64(ctx: JSContext; val: JSValue): JSResult[float64] =
  var f64: float64
  if JS_ToFloat64(ctx, addr f64, val) < 0:
    return err(nil)
  return ok(f64)

macro fromJSTupleBody(a: tuple) =
  let len = a.getType().len - 1
  let done = ident("done")
  result = newStmtList(quote do:
    var `done`: bool)
  for i in 0..<len:
    result.add(quote do:
      let next = JS_Call(ctx, nextMethod, it, 0, nil)
      if JS_IsException(next):
        return err()
      defer: JS_FreeValue(ctx, next)
      let doneVal = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstDone])
      if JS_IsException(doneVal):
        return err()
      defer: JS_FreeValue(ctx, doneVal)
      `done` = ?fromJS[bool](ctx, doneVal)
      if `done`:
        return errTypeError("Too few arguments in sequence (got " & $`i` &
          ", expected " & $`len` & ")")
      let valueVal = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstValue])
      if JS_IsException(valueVal):
        return err()
      defer: JS_FreeValue(ctx, valueVal)
      `a`[`i`] = ?fromJS[typeof(`a`[`i`])](ctx, valueVal)
    )
    if i == len - 1:
      result.add(quote do:
        let next = JS_Call(ctx, nextMethod, it, 0, nil)
        if JS_IsException(next):
          return err()
        defer: JS_FreeValue(ctx, next)
        let doneVal = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstDone])
        `done` = ?fromJS[bool](ctx, doneVal)
        var i = `i`
        # we're emulating a sequence, so we must query all remaining parameters
        # too:
        while not `done`:
          inc i
          let next = JS_Call(ctx, nextMethod, it, 0, nil)
          if JS_IsException(next):
            return err()
          defer: JS_FreeValue(ctx, next)
          let doneVal = JS_GetProperty(ctx, next,
            ctx.getOpaque().strRefs[jstDone])
          if JS_IsException(doneVal):
            return err()
          defer: JS_FreeValue(ctx, doneVal)
          `done` = ?fromJS[bool](ctx, doneVal)
          if `done`:
            let msg = "Too many arguments in sequence (got " & $i &
              ", expected " & $`len` & ")"
            return err(newTypeError(msg))
          JS_FreeValue(ctx, JS_GetProperty(ctx, next,
            ctx.getOpaque().strRefs[jstValue]))
      )

proc fromJSTuple[T: tuple](ctx: JSContext; val: JSValue): JSResult[T] =
  let itprop = JS_GetProperty(ctx, val, ctx.getOpaque().symRefs[jsyIterator])
  if JS_IsException(itprop):
    return err()
  defer: JS_FreeValue(ctx, itprop)
  let it = JS_Call(ctx, itprop, val, 0, nil)
  if JS_IsException(it):
    return err()
  defer: JS_FreeValue(ctx, it)
  let nextMethod = JS_GetProperty(ctx, it, ctx.getOpaque().strRefs[jstNext])
  if JS_IsException(nextMethod):
    return err()
  defer: JS_FreeValue(ctx, nextMethod)
  var x: T
  fromJSTupleBody(x)
  return ok(x)

proc fromJSSeq[T](ctx: JSContext; val: JSValue): JSResult[seq[T]] =
  let itprop = JS_GetProperty(ctx, val, ctx.getOpaque().symRefs[jsyIterator])
  if JS_IsException(itprop):
    return err()
  defer: JS_FreeValue(ctx, itprop)
  let it = JS_Call(ctx, itprop, val, 0, nil)
  if JS_IsException(it):
    return err()
  defer: JS_FreeValue(ctx, it)
  let nextMethod = JS_GetProperty(ctx, it, ctx.getOpaque().strRefs[jstNext])
  if JS_IsException(nextMethod):
    return err()
  defer: JS_FreeValue(ctx, nextMethod)
  var s = newSeq[T]()
  while true:
    let next = JS_Call(ctx, nextMethod, it, 0, nil)
    if JS_IsException(next):
      return err()
    defer: JS_FreeValue(ctx, next)
    let doneVal = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstDone])
    if JS_IsException(doneVal):
      return err()
    defer: JS_FreeValue(ctx, doneVal)
    let done = ?fromJS[bool](ctx, doneVal)
    if done:
      break
    let valueVal = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstValue])
    if JS_IsException(valueVal):
      return err()
    defer: JS_FreeValue(ctx, valueVal)
    let genericRes = ?fromJS[typeof(s[0])](ctx, valueVal)
    s.add(genericRes)
  return ok(s)

proc fromJSSet[T](ctx: JSContext; val: JSValue): JSResult[set[T]] =
  let itprop = JS_GetProperty(ctx, val, ctx.getOpaque().symRefs[jsyIterator])
  if JS_IsException(itprop):
    return err()
  defer: JS_FreeValue(ctx, itprop)
  let it = JS_Call(ctx, itprop, val, 0, nil)
  if JS_IsException(it):
    return err()
  defer: JS_FreeValue(ctx, it)
  let nextMethod = JS_GetProperty(ctx, it, ctx.getOpaque().strRefs[jstNext])
  if JS_IsException(nextMethod):
    return err()
  defer: JS_FreeValue(ctx, nextMethod)
  var s: set[T]
  while true:
    let next = JS_Call(ctx, nextMethod, it, 0, nil)
    if JS_IsException(next):
      return err()
    defer: JS_FreeValue(ctx, next)
    let doneVal = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstDone])
    if JS_IsException(doneVal):
      return err()
    defer: JS_FreeValue(ctx, doneVal)
    let done = ?fromJS[bool](ctx, doneVal)
    if done:
      break
    let valueVal = JS_GetProperty(ctx, next, ctx.getOpaque().strRefs[jstValue])
    if JS_IsException(valueVal):
      return err()
    defer: JS_FreeValue(ctx, valueVal)
    let genericRes = ?fromJS[T](ctx, valueVal)
    s.incl(genericRes)
  return ok(s)

proc fromJSTable[A, B](ctx: JSContext; val: JSValue): JSResult[Table[A, B]] =
  if not JS_IsObject(val):
    return err(newTypeError("object expected"))
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
  var res = Table[A, B]()
  for i in 0 ..< plen:
    let atom = ptab[i].atom
    let k = JS_AtomToValue(ctx, atom)
    defer: JS_FreeValue(ctx, k)
    let kn = ?fromJS[A](ctx, k)
    let v = JS_GetProperty(ctx, val, atom)
    defer: JS_FreeValue(ctx, v)
    let vn = ?fromJS[B](ctx, v)
    res[kn] = vn
  return ok(res)

template optionType[T](o: type Option[T]): auto =
  T

# Option vs Opt:
# Option is for nullable types, e.g. if you want to return either a string
# or null. (This is rather pointless for anything else.)
# Opt is for passing down exceptions received up in the chain.
# So e.g. none(T) translates to JS_NULL, but err() translates to JS_EXCEPTION.
proc fromJSOption[T](ctx: JSContext; val: JSValue): JSResult[Option[T]] =
  if JS_IsNull(val):
    return ok(none(T))
  let res = ?fromJS[T](ctx, val)
  return ok(option(res))

proc fromJSBool(ctx: JSContext; val: JSValue): JSResult[bool] =
  let ret = JS_ToBool(ctx, val)
  if ret == -1: # exception
    return err(nil)
  if ret == 0:
    return ok(false)
  return ok(true)

func strictParseEnum[T: enum](s: string): Opt[T] =
  # cmp when len is small enough, otherwise hashmap
  when {T.low..T.high}.len <= 4:
    for e in T.low .. T.high:
      if $e == s:
        return ok(e)
  else:
    const tab = (func(): Table[string, T] =
      result = initTable[string, T]()
      for e in T.low .. T.high:
        result[$e] = e
    )()
    if s in tab:
      return ok(tab[s])
  return err()

proc fromJSEnum[T: enum](ctx: JSContext; val: JSValue): JSResult[T] =
  if JS_IsException(val):
    return err()
  let s = ?toString(ctx, val)
  let r = strictParseEnum[T](s)
  if r.isSome:
    return ok(r.get)
  return errTypeError("`" & s & "' is not a valid value for enumeration " & $T)

proc fromJSPObj0(ctx: JSContext; val: JSValue; t: string): JSResult[pointer] =
  if JS_IsException(val):
    return err(nil)
  if JS_IsNull(val):
    return ok(nil)
  if ctx.isInstanceOfGlobal(val, t):
    let op = getGlobalOpaque0(ctx, val)
    if op.isSome:
      return ok(op.get)
    return err(nil)
  if not JS_IsObject(val):
    return err(newTypeError("Value is not an object"))
  if not isInstanceOfNonGlobal(ctx, val, t):
    return errTypeError(t & " expected")
  let classid = JS_GetClassID(val)
  let op = JS_GetOpaque(val, classid)
  return ok(op)

proc fromJSObject[T: ref object](ctx: JSContext; val: JSValue): JSResult[T] =
  return ok(cast[T](?fromJSPObj0(ctx, val, $T)))

proc fromJSVoid(ctx: JSContext; val: JSValue): JSResult[void] =
  if JS_IsException(val):
    return err(nil)
  return ok()

proc fromJSDict[T: JSDict](ctx: JSContext; val: JSValue): JSResult[T] =
  if not JS_IsUndefined(val) and not JS_IsNull(val) and not JS_IsObject(val):
    return err(newTypeError("Dictionary is not an object"))
  #TODO throw on missing required values
  var d = T()
  if JS_IsObject(val):
    for k, v in d.fieldPairs:
      let esm = JS_GetPropertyStr(ctx, val, k)
      if not JS_IsUndefined(esm):
        v = ?fromJS[typeof(v)](ctx, esm)
      when v isnot JSValue:
        JS_FreeValue(ctx, esm)
  return ok(d)

proc fromJSArrayBuffer(ctx: JSContext; val: JSValue): JSResult[JSArrayBuffer] =
  var len: csize_t
  let p = JS_GetArrayBuffer(ctx, addr len, val)
  if p == nil:
    return err(nil)
  let abuf = JSArrayBuffer(
    len: len,
    p: cast[ptr UncheckedArray[uint8]](p)
  )
  return ok(abuf)

proc fromJSArrayBufferView(ctx: JSContext; val: JSValue):
    JSResult[JSArrayBufferView] =
  var offset: csize_t
  var nmemb: csize_t
  var nsize: csize_t
  let jsbuf = JS_GetTypedArrayBuffer(ctx, val, addr offset, addr nmemb,
    addr nsize)
  let abuf = ?fromJSArrayBuffer(ctx, jsbuf)
  let view = JSArrayBufferView(
    abuf: abuf,
    offset: offset,
    nmemb: nmemb,
    nsize: nsize
  )
  return ok(view)

type FromJSAllowedT = (object and not (Result|Option|Table|JSValue|JSDict|
  JSArrayBuffer|JSArrayBufferView|JSUint8Array))

macro fromJS2(ctx: JSContext; val: JSValue; x: static string): untyped =
  let id = ident("fromJS" & x)
  return quote do:
    `id`(`ctx`, `val`)

proc fromJS*[T](ctx: JSContext; val: JSValue): JSResult[T] =
  when T is string:
    return fromJSString(ctx, val)
  elif T is Option:
    return fromJSOption[optionType(T)](ctx, val)
  elif T is seq:
    return fromJSSeq[typeof(result.get.items)](ctx, val)
  elif T is set:
    return fromJSSet[typeof(result.get.items)](ctx, val)
  elif T is tuple:
    return fromJSTuple[T](ctx, val)
  elif T is bool:
    return fromJSBool(ctx, val)
  elif typeof(result).valType is Table:
    return fromJSTable[typeof(result.get.keys),
      typeof(result.get.values)](ctx, val)
  elif T is SomeInteger:
    return fromJSInt[T](ctx, val)
  elif T is float64:
    return fromJSFloat64(ctx, val)
  elif T is enum:
    return fromJSEnum[T](ctx, val)
  elif T is JSValue:
    return ok(val)
  elif T is ref object:
    return fromJSObject[T](ctx, val)
  elif T is void:
    return fromJSVoid(ctx, val)
  elif T is JSDict:
    return fromJSDict[T](ctx, val)
  elif T is JSArrayBuffer:
    return fromJSArrayBuffer(ctx, val)
  elif T is JSArrayBufferView:
    return fromJSArrayBufferView(ctx, val)
  else:
    return fromJS2(ctx, val, $T)

const JS_ATOM_TAG_INT = 1u32 shl 31

func JS_IsNumber*(v: JSAtom): JS_BOOL =
  return (uint32(v) and JS_ATOM_TAG_INT) != 0

func fromJS*[T: string|uint32|JSAtom](ctx: JSContext; atom: JSAtom): Opt[T] =
  when T is JSAtom:
    return ok(atom)
  elif T is SomeNumber:
    if JS_IsNumber(atom):
      return ok(uint32(atom) and (not JS_ATOM_TAG_INT))
    return err()
  else:
    let cs = JS_AtomToCString(ctx, atom)
    if cs == nil:
      return err()
    let s = $cs
    JS_FreeCString(ctx, cs)
    return ok(s)

proc fromJSPObj[T](ctx: JSContext; val: JSValue): JSResult[ptr T] =
  return cast[JSResult[ptr T]](fromJSPObj0(ctx, val, $T))

template fromJSP*[T](ctx: JSContext; val: JSValue): untyped =
  when T is FromJSAllowedT:
    fromJSPObj[T](ctx, val)
  else:
    fromJS[T](ctx, val)
