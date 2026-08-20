## Macro-based JavaScript binding generator.  Values are converted from JS to
## Nim and vice versa using generic overloaded functions; users can also
## define their own converters.  See the `tojs` and `fromjs` modules for
## details.
##
## Pragmas:
##
## {.jsctor.} for constructors.  These have no `this' value, and are bound
##   as regular constructors in JS.  They must return a ref object, which
##   will have a JS counterpart too.  (Other functions can return ref
##   objects too, which will either use the existing JS counterpart, if
##   exists, or create a new one.)
##
## {.jsfctor.} is like {.jsctor.}, but can also be called as a regular
##   function.
##
## {.jsfunc.} is used for binding normal functions.  Needs a `this'
##   value, as all following pragmas. Generics are not supported, but
##   JSValue is.
##
##   By default, the Nim function name is bound; if this is not desired,
##   you can rename the function like this: {.jsfunc: "preferredName".}
##   This also works for all other pragmas that define named functions
##   in JS.
##
## {.jsstfunc.} binds static functions. Unlike .jsfunc, it does not
##   have a `this' value. A class name must be specified, e.g.
##   {.jsstfunc: "URL".} to define on the URL class.  To rename a static
##   function, use the syntax "ClassName#funcName", e.g. "Response#error".
##
## {.jsget.}, {.jsfget.} must be specified on object fields; these
##   generate regular getter & setter functions.
##
## {.jsufget, jsuffget, jsuffunc.} For fields with the
##   [LegacyUnforgeable] WebIDL property.
##
##   This makes it so a non-configurable/writable, but enumerable
##   property is defined on the object when the *constructor* is called
##   (i.e. NOT on the prototype.)
##
## {.jsrget.}, {.jsrfget.}: For fields with the [Replaceable] WebIDL
##   property.
##
## {.jsfget.} and {.jsfset.} for getters/setters. Note the `f'; bare
##   jsget/jsset can only be used on object fields. (I initially wanted
##   to use the same keyword, unfortunately that didn't work out.)
##
## {.jsgetownprop.} Called when GetOwnProperty would return nothing.  The
##   key must be either a JSAtom, uint32 or string.  (Note that the string
##   variant copies.)
##
## {.jsgetprop.} for property getters.  Called on GetProperty.  (This can be
##   emulated using get_own_property, but this might still be faster.)
##
## {.jssetprop.} for property setters.  Called on SetProperty - this is the
##   set() method of Proxy, except it always returns true. Same rules as
##   jsgetprop for keys.
##
## {.jsdelprop.} for property deletion.  It is like the deleteProperty()
##   method of Proxy.  Must return true if deleted, false if not deleted.
##
## {.jshasprop.} for overriding has_property.  Must return a boolean,
##   or the integer 1 for true, 0 for false, or -1 for exception.
##
## {.jspropnames.} overrides get_own_property_names.  Must return a
##   JSPropertyEnumList object.
##
## {.jsiter.} overrides iterator_next.  Must have a `var JS_BOOL` "done"
##   parameter.

{.push raises: [].}

import std/macros
import std/sets
import std/tables
import std/typetraits

import fromjs
import jsopaque
import jsref
import jsutils
import quickjs
import tojs

when sizeof(int) < sizeof(int64):
  export quickjs.`==`

type
  JSFunctionList = openArray[JSCFunctionListEntry]

  BoundFunctionType = enum
    bfFunction = "js_func"
    bfConstructor = "js_ctor"
    bfConstructorFunction = "js_fctor"
    bfGetter = "js_get"
    bfSetter = "js_set"
    bfPropertyGetOwn = "js_prop_get_own"
    bfPropertyGet = "js_prop_get"
    bfPropertySet = "js_prop_set"
    bfPropertyDel = "js_prop_del"
    bfPropertyHas = "js_prop_has"
    bfPropertyNames = "js_prop_names"
    bfIteratorNext = "js_iter"
    bfFinalizer = "js_fin"
    bfMark = "js_mark"

  BoundFunctionFlag = enum
    bffNone, bffUnforgeable, bffStatic, bffReplaceable, bffMagic, bffThis

  JSIterableType* = enum
    jitNone # not iterable
    jitValue # array-like
    jitIndexed # array-like, but no values()/entries()
    jitPair # pair
    jitIterator # iterator object

  ChaClassDef* = object
    class_name*: cstring
    id*: JSClassID
    parent*: JSClassID
    iterable*: JSIterableType
    ctorType*: JSCFunctionEnum
    raw*: bool #TODO remove this
    # pointer to functions:
    # - 0 ..< funsEnd: regular functions
    # - funsEnd ..< staticFunsEnd: static functions
    # - staticFunsEnd ..< unforgeableFunsEnd: unforgeable functions
    funsEnd*: int16
    staticFunsEnd*: int16
    unforgeableFunsEnd*: int16
    funsBase*: JSCFunctionListP
    ctor*: JSCFunction
    finalizer*: ChaFinalizerFunction
    mark*: ChaMarkFunction
    exotic*: ptr JSClassExoticMethods

template funs*(def: ChaClassDef): openArray[JSCFunctionListEntry] =
  let last = int(def.funsEnd)
  if def.funsBase != nil and last > 0:
    def.funsBase.toOpenArray(0, last - 1)
  else:
    toOpenArray((ptr UncheckedArray[JSCFunctionListEntry])(nil), 0, -1)

template staticFuns*(def: ChaClassDef): openArray[JSCFunctionListEntry] =
  let first = int(def.funsEnd)
  let last = int(def.staticFunsEnd)
  if def.funsBase != nil and last > first:
    def.funsBase.toOpenArray(first, last - 1)
  else:
    toOpenArray((ptr UncheckedArray[JSCFunctionListEntry])(nil), 0, -1)

template unforgeableFuns*(def: ChaClassDef): openArray[JSCFunctionListEntry] =
  let first = int(def.staticFunsEnd)
  let last = int(def.unforgeableFunsEnd)
  if def.funsBase != nil and last > first:
    def.funsBase.toOpenArray(first, last - 1)
  else:
    toOpenArray((ptr UncheckedArray[JSCFunctionListEntry])(nil), 0, -1)

proc bindMalloc(s: JSMallocStateP; size: csize_t): pointer {.cdecl.} =
  if s.malloc_size + size > s.malloc_limit:
    return nil
  let diff = csize_t(getOccupiedMem()) - s.malloc_size
  let res = alloc(size)
  inc s.malloc_count
  s.malloc_size = csize_t(getOccupiedMem()) - diff
  res

proc bindFree(s: JSMallocStateP; p: pointer) {.cdecl.} =
  if p != nil:
    let diff = csize_t(getOccupiedMem()) - s.malloc_size
    dealloc(p)
    dec s.malloc_count
    s.malloc_size = csize_t(getOccupiedMem()) - diff

proc bindRealloc(s: JSMallocStateP; p: pointer; size: csize_t): pointer
    {.cdecl.} =
  if s.malloc_size + size > s.malloc_limit:
    return nil
  let diff = csize_t(getOccupiedMem()) - s.malloc_size
  let res = realloc(p, size)
  s.malloc_size = csize_t(getOccupiedMem()) - diff
  if p == nil and size > 0:
    inc s.malloc_count
  elif p != nil and size == 0:
    dec s.malloc_count
  res

proc getForeignPtr*(val: JSValueConst): pointer =
  # ugly hack, but it does the job
  # (we always get a JSValue for mark, so we discriminate unbound foreign
  # objects from bound ones by passing the former with a module tag)
  if JS_VALUE_GET_TAG(val) == JS_TAG_MODULE:
    return JS_VALUE_GET_PTR(val)
  return JS_GetOpaque(val, JS_GetClassID(val))

proc jsFinalize(rt: JSRuntime; this: JSValueConst) {.cdecl.} =
  # We don't want to duplicate each finalizer, so we store them in a global
  # registry and invoke them in the end.
  #TODO ideally, the finalizers would just tail-call into each other
  # without this indirection.
  var p: pointer
  var classid: JSClassID
  if JS_VALUE_GET_TAG(this) == JS_TAG_OBJECT:
    p = JS_GetAnyOpaque(this, classid)
  else:
    p = JS_VALUE_GET_PTR(this)
    classid = JS_GetForeignClassID(p)
  for fin in rt.getOpaque().finalizers(classid):
    fin(rt, p)
  if JS_VALUE_GET_TAG(this) == JS_TAG_OBJECT:
    # called from JSValue finalizer, so the opaque was not free'd
    JS_FreeForeignObjectMemory(rt, p)

proc jsMark(rt: JSRuntime; this: JSValueConst; markFunc: JS_MarkFunc)
    {.cdecl.} =
  #TODO see above
  var p: pointer
  var classid: JSClassID
  if JS_VALUE_GET_TAG(this) == JS_TAG_OBJECT:
    p = JS_GetAnyOpaque(this, classid)
  else:
    p = JS_VALUE_GET_PTR(this)
    classid = JS_GetForeignClassID(p)
  when defined(debug):
    let marking = rt.getOpaque().marking
    rt.getOpaque().marking = true
  for mark in rt.getOpaque().marks(classid):
    mark(rt, p, markFunc)
  when defined(debug):
    rt.getOpaque().marking = marking

proc newJSRuntime*(): JSRuntime =
  ## Instantiate a Monoucha `JSRuntime`.
  var mf {.global.} = JSMallocFunctions(
    js_malloc: bindMalloc,
    js_free: bindFree,
    js_realloc: bindRealloc,
    js_malloc_usable_size: nil
  )
  return JS_NewRuntime2(addr mf, nil)

proc setGlobalRuntime*(rt: JSRuntime) =
  let opaque = create(JSRuntimeOpaqueObj)
  JS_SetRuntimeOpaque(rt, opaque)
  globalRuntime = rt

proc newGlobalJSRuntime*(): JSRuntime =
  let rt = newJSRuntime()
  if rt != nil:
    setGlobalRuntime(rt)
  return rt

proc newJSContext*(rt: JSRuntime): JSContext =
  ## Instantiate a Monoucha `JSContext`.
  ## It is only valid to call Monoucha procedures on contexts initialized with
  ## `newJSContext`, as it does extra initialization over `JS_NewContext`.
  let ctx = JS_NewContext(rt)
  let opaque = newJSContextOpaque(ctx)
  JS_SetContextOpaque(ctx, opaque)
  return ctx

proc newDummyContext*(rt: JSRuntime): JSContext =
  ## Like newJSContext, but does not actually set the context opaque.
  ## Used in no-JS buffers.
  return JS_NewContextRaw(rt)

proc free*(ctx: JSContext) =
  ## Free the JSContext and associated resources.
  ## Note: this is not an alias of `JS_FreeContext`; `free` also frees various
  ## JSValues stored on context startup by `newJSContext`.
  let opaque = ctx.getOpaque()
  if opaque != nil:
    for a in opaque.symRefs:
      JS_FreeAtom(ctx, a)
    for a in opaque.strRefs:
      JS_FreeAtom(ctx, a)
    ctx.freeValues(opaque.valRefs)
    ctx.freeValues(opaque.ctors)
    let globalObj = move(opaque.globalObj)
    if globalObj != nil:
      let rt = JS_GetRuntime(ctx)
      JS_FreeForeignObject(rt, globalObj)
    JS_FreeValue(ctx, opaque.global)
    JS_SetContextOpaque(ctx, nil)
    `=destroy`(opaque[])
    dealloc(opaque)
  JS_FreeContext(ctx)

proc free*(rt: JSRuntime) =
  ## Free the `JSRuntime` rt and remove it from the global JSRuntime pool.
  let rtOpaque = rt.getOpaque()
  for map in rtOpaque.enumMap:
    for atom in map.atoms:
      JS_FreeAtomRT(rt, atom)
    for it in map.enums:
      JS_FreeAtomRT(rt, it.atom)
  JS_FreeRuntime(rt)
  # free opaque after runtime to preserve class data for mark & finalization
  `=destroy`(rtOpaque[])
  dealloc(rtOpaque)
  globalRuntime = nil

proc setGlobal*[T](ctx: JSContext; obj: JSRef[T]) =
  ## Set the global variable to the reference `obj`.
  let ctxOpaque = ctx.getOpaque()
  if ctxOpaque != nil:
    let obj = cast[pointer](obj)
    let rt = JS_GetRuntime(ctx)
    let dummy = JS_NewObjectClass(ctx, ctxOpaque.gclass)
    JS_SetForeignOpaque(rt, obj, dummy)
    JS_SetOpaque(dummy, obj)
    ctxOpaque.globalObj = JS_DupForeignObject(rt, obj)
    let sym = ctx.call(ctxOpaque.valRefs[jsvSymbol], JS_UNDEFINED)
    assert not JS_IsException(sym)
    let atom = JS_ValueToAtom(ctx, sym)
    assert ctx.defineProperty(ctxOpaque.global, atom, dummy) == dprSuccess
    JS_FreeValue(ctx, sym)
    JS_FreeAtom(ctx, atom)

# Add all LegacyUnforgeable functions defined on the prototype chain to
# the opaque.
# Since every prototype has a list of all its ancestor's LegacyUnforgeable
# functions, it is sufficient to simply merge the new list of new classes
# with their parent's list to achieve this.
# We handle finalizers & mark functions similarly.
# Returns true on success, false on exception.
proc addClass(rtOpaque: JSRuntimeOpaque; def: ChaClassDef): bool =
  var merged = @(def.unforgeableFuns)
  if int(def.parent) < rtOpaque.classes.len:
    merged.add(rtOpaque.classes[int(def.parent)].unforgeable)
  if merged.len > 0:
    rtOpaque.classes[int(def.id)].unforgeable = move(merged)
  var fins: seq[ChaFinalizerFunction] = @[]
  if def.finalizer != nil:
    fins.add(def.finalizer)
  if int(def.parent) < rtOpaque.classes.len:
    fins.add(rtOpaque.classes[int(def.parent)].fins)
  if fins.len > 0:
    rtOpaque.classes[int(def.id)].fins = move(fins)
  var marks: seq[ChaMarkFunction] = @[]
  if def.mark != nil:
    marks.add(def.mark)
  if int(def.parent) < rtOpaque.classes.len:
    marks.add(rtOpaque.classes[int(def.parent)].marks)
  if marks.len > 0:
    rtOpaque.classes[int(def.id)].marks = move(marks)
  rtOpaque.classes[int(def.id)].name = def.class_name
  true

proc newProtoFromParentClass(ctx: JSContext; parent: JSClassID;
    iterable: JSIterableType; parentProto: JSValueConst): JSValue =
  if not JS_IsNull(parentProto):
    return JS_NewObjectProto(ctx, parentProto)
  if parent != JS_INVALID_CLASS_ID:
    let proto = JS_GetClassProto(ctx, parent)
    assert JS_IsObject(proto)
    let res = JS_NewObjectProto(ctx, proto)
    JS_FreeValue(ctx, proto)
    return res
  if iterable == jitIterator:
    let parentProto = ctx.getOpaque().valRefs[jsvIteratorPrototype]
    return JS_NewObjectProto(ctx, parentProto)
  return JS_NewObject(ctx)

proc jsIllegalCtor(ctx: JSContext; this: JSValueConst; argc: cint;
    argv: JSValueConstArray): JSValue {.cdecl.} =
  return JS_ThrowTypeError(ctx, "Illegal constructor")

proc newCtorFunFromParentClass(ctx: JSContext; ctor: JSCFunction;
    className: cstring; parent: JSClassID; ctorType: JSCFunctionEnum): JSValue =
  let ctor = if ctor == nil: jsIllegalCtor else: ctor
  let fun = JS_NewCFunction2(ctx, ctor, cstringConst(className), 0, ctorType,
    0)
  if parent != JS_INVALID_CLASS_ID:
    let proto = ctx.getOpaque().ctors[int(parent)]
    assert JS_IsObject(proto)
    if JS_SetPrototype(ctx, fun, proto) < 0:
      return JS_EXCEPTION
  return fun

proc pairsForEach(ctx: JSContext; this: JSValueConst; argc: cint;
    argv: JSValueConstArray; magic: cint; data: JSValueConstArray): JSValue
    {.cdecl.} =
  let this = ctx.toObject(this)
  if JS_IsException(this):
    return JS_EXCEPTION
  #TODO CORS (security check)
  if JS_GetClassID(this) != JSClassID(magic):
    JS_FreeValue(ctx, this)
    return JS_ThrowTypeError(ctx, "unexpected pairs class")
  #TODO convert argv[0] to function
  let fun = argv[0]
  let iter = JS_Call(ctx, data[0], this, 0, nil)
  if JS_IsException(iter):
    JS_FreeValue(ctx, this)
    return iter
  let nextMethod = JS_GetProperty(ctx, iter, ctx.getOpaque().strRefs[jstNext])
  if JS_IsException(nextMethod):
    JS_FreeValue(ctx, this)
    JS_FreeValue(ctx, iter)
    return JS_EXCEPTION
  var res = JS_UNDEFINED
  while true:
    var entry: JSValue
    case ctx.fromJSSeqIt(iter, nextMethod, entry)
    of sirException:
      res = JS_EXCEPTION
      break
    of sirDone:
      break
    of sirContinue:
      let key = JS_GetPropertyUint32(ctx, entry, 0)
      if JS_IsException(key):
        JS_FreeValue(ctx, entry)
        res = JS_EXCEPTION
        break
      let value = JS_GetPropertyUint32(ctx, entry, 1)
      JS_FreeValue(ctx, entry)
      if JS_IsException(value):
        JS_FreeValue(ctx, key)
        res = JS_EXCEPTION
        break
      let res2 = ctx.call(fun, JS_UNDEFINED, key, value, this)
      ctx.freeValues(key, value)
      if JS_IsException(res2):
        res = JS_EXCEPTION
        break
      JS_FreeValue(ctx, res2)
  JS_FreeValue(ctx, iter)
  JS_FreeValue(ctx, nextMethod)
  JS_FreeValue(ctx, this)
  return res

proc defineIterableProps(ctx: JSContext; iterable: JSIterableType;
    proto: JSValueConst; class: JSClassID): DefinePropertyResult =
  let ctxOpaque = ctx.getOpaque()
  case iterable
  of jitNone: discard
  of jitValue:
    let values = JS_DupValue(ctx, ctxOpaque.valRefs[jsvArrayPrototypeValues])
    let itSym = ctxOpaque.symRefs[jsyIterator]
    if ctx.definePropertyCW(proto, itSym, values) == dprException:
      return dprException
    const map = {
      jstEntries: jsvArrayPrototypeEntries,
      jstForEach: jsvArrayPrototypeForEach,
      jstKeys: jsvArrayPrototypeKeys,
      jstValues: jsvArrayPrototypeValues
    }
    for (n, v) in map:
      let val = JS_DupValue(ctx, ctxOpaque.valRefs[v])
      if ctx.definePropertyCWE(proto, n, val) == dprException:
        return dprException
  of jitIndexed:
    let values = JS_DupValue(ctx, ctxOpaque.valRefs[jsvArrayPrototypeValues])
    let itSym = ctxOpaque.symRefs[jsyIterator]
    if ctx.definePropertyCWE(proto, itSym, values) == dprException:
      return dprException
  of jitPair:
    let pairs = JS_GetProperty(ctx, proto, ctxOpaque.strRefs[jstEntries])
    let forEach = JS_NewCFunctionData(ctx, pairsForEach, 1, cint(class), 1,
      cast[JSValueConstArray](unsafeAddr pairs))
    if ctx.definePropertyCWE(proto, jstForEach, forEach) == dprException:
      JS_FreeValue(ctx, pairs)
      return dprException
    let itSym = ctxOpaque.symRefs[jsyIterator]
    if ctx.definePropertyCWE(proto, itSym, pairs) == dprException:
      return dprException
  of jitIterator:
    discard
  dprSuccess

type
  FuncParam = tuple
    t: NimNode
    val: NimNode # may be nil

  JSFuncGenerator = object
    t: BoundFunctionType
    flag: BoundFunctionFlag
    length: uint8 # minArgs without JSContext
    magic: NimNode
    minArgs: cint
    i: cint # nim parameters accounted for
    funcName: string
    funcParams: seq[FuncParam]
    thisTypeNode: NimNode
    returnType: NimNode # may be nil
    newName: NimNode
    jsFunCallList: NimNode
    jsFunCall: NimNode
    jsCallAndRet: NimNode

  GetSet = object
    get: NimNode
    set: NimNode
    flag: BoundFunctionFlag
    magic: NimNode

  RegistryInfo = object
    name: string # JS name, if this is the empty string then it equals tname
    tabFuns: NimNode # array of function table
    tabUnforgeable: NimNode # array of unforgeable function table
    tabStatic: NimNode # array of static function table
    ctorFun: NimNode # constructor ident
    ctorType: JSCFunctionEnum # constructor function type
    hasExotic: bool # set if we have to generate exotics
    getset: Table[string, GetSet] # name -> value
    propGetOwnFun: NimNode # exotic get own property function ident
    propGetFun: NimNode # exotic get function ident
    propSetFun: NimNode # exotic set function ident
    propDelFun: NimNode # exotic del function ident
    propHasFun: NimNode # exotic has function ident
    propNamesFun: NimNode # exotic property names function ident
    markFun: NimNode # class mark ident
    convId: NimNode # automatically generated class mark ident
    finFun: NimNode # class mark ident
    tabReplaceableNames: NimNode # replaceable names array

proc readParams(gen: var JSFuncGenerator; fun: NimNode) =
  let formalParams = fun.params
  if formalParams[0].kind != nnkEmpty:
    gen.returnType = formalParams[0]
  var minArgsSeen = false
  for i in 1 ..< formalParams.len:
    let it = formalParams[i]
    var val = it[^1]
    if val.kind == nnkEmpty:
      val = nil
    var t = it[^2]
    case t.kind
    of nnkEmpty:
      t = quote do:
        typeof(`val`)
    of nnkVarTy:
      t = newNimNode(nnkPtrTy).add(t[0])
    of nnkCommand, nnkCall:
      if t.len == 2 and t[0].eqIdent("sink"):
        t = t[1]
    of nnkBracketExpr:
      if t[0].eqIdent("varargs"):
        if i != formalParams.len - 1:
          error("varargs must be the last parameter")
        minArgsSeen = true
    else: discard
    for i in 0 ..< it.len - 2:
      gen.funcParams.add((t, val))
    if val != nil:
      minArgsSeen = true
    elif not minArgsSeen:
      gen.minArgs = cint(gen.funcParams.len)
  var length = gen.minArgs
  if (gen.t notin {bfConstructor, bfConstructorFunction} or
      gen.flag == bffThis) and gen.flag != bffStatic:
    dec length
  if gen.flag == bffMagic:
    dec length
  if gen.funcParams.len > gen.i:
    if gen.funcParams[gen.i].t.eqIdent("JSContext"):
      dec length
      gen.jsFunCall.add(ident("ctx"))
      inc gen.i
    elif gen.funcParams[gen.i].t.eqIdent("JSRuntime"):
      inc gen.i # special case for finalizers that have a JSRuntime param
  assert length in 0..255
  gen.length = uint8(length)

template getJSParams(): untyped =
  [
    (quote do: JSValue),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("this"), quote do: JSValueConst),
    newIdentDefs(ident("argc"), quote do: cint),
    newIdentDefs(ident("argv"), quote do: JSValueConstArray)
  ]

template getJSMagicParams(): untyped =
  [
    (quote do: JSValue),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("this"), quote do: JSValueConst),
    newIdentDefs(ident("argc"), quote do: cint),
    newIdentDefs(ident("argv"), quote do: JSValueConstArray),
    newIdentDefs(ident("magic"), quote do: cint)
  ]

template getJSGetterParams(): untyped =
  [
    (quote do: JSValue),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("this"), quote do: JSValueConst),
  ]

template getJSMagicGetterParams(): untyped =
  [
    (quote do: JSValue),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("this"), quote do: JSValueConst),
    newIdentDefs(ident("magic"), quote do: cint)
  ]

template getJSGetOwnPropParams(): untyped =
  [
    (quote do: cint),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("desc"), quote do: ptr JSPropertyDescriptor),
    newIdentDefs(ident("this"), quote do: JSValueConst),
    newIdentDefs(ident("prop"), quote do: JSAtom),
  ]

template getJSGetPropParams(): untyped =
  [
    (quote do: JSValue),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("this"), quote do: JSValueConst),
    newIdentDefs(ident("prop"), quote do: JSAtom),
    newIdentDefs(ident("receiver"), quote do: JSValueConst),
  ]

template getJSSetPropParams(): untyped =
  [
    (quote do: cint),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("this"), quote do: JSValueConst),
    newIdentDefs(ident("atom"), quote do: JSAtom),
    newIdentDefs(ident("value"), quote do: JSValueConst),
    newIdentDefs(ident("receiver"), quote do: JSValueConst),
    newIdentDefs(ident("flags"), quote do: cint),
  ]

template getJSDelPropParams(): untyped =
  [
    (quote do: cint),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("this"), quote do: JSValueConst),
    newIdentDefs(ident("prop"), quote do: JSAtom),
  ]

template getJSHasPropParams(): untyped =
  [
    (quote do: cint),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("this"), quote do: JSValueConst),
    newIdentDefs(ident("atom"), quote do: JSAtom),
  ]


template getJSSetterParams(): untyped =
  [
    (quote do: JSValue),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("this"), quote do: JSValueConst),
    newIdentDefs(ident("val"), quote do: JSValueConst),
  ]

template getJSMagicSetterParams(): untyped =
  [
    (quote do: JSValue),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("this"), quote do: JSValueConst),
    newIdentDefs(ident("val"), quote do: JSValueConst),
    newIdentDefs(ident("magic"), quote do: cint)
  ]

template getJSPropNamesParams(): untyped =
  [
    (quote do: cint),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("ptab"), quote do: ptr JSPropertyEnumArray),
    newIdentDefs(ident("plen"), quote do: ptr uint32),
    newIdentDefs(ident("this"), quote do: JSValueConst)
  ]

template getJSIterParams(): untyped =
  [
    (quote do: JSValue),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("this"), quote do: JSValueConst),
    newIdentDefs(ident("argc"), quote do: cint),
    newIdentDefs(ident("argv"), quote do: JSValueConstArray),
    newIdentDefs(ident("pdone"), newNimNode(nnkVarTy).add(ident"JS_BOOL")),
    newIdentDefs(ident("magic"), quote do: cint),
  ]

proc addThisParam(gen: var JSFuncGenerator; thisName = "this") =
  let t = gen.funcParams[gen.i].t
  let id = ident(thisName)
  if t.eqIdent("JSValueConst"):
    gen.jsFunCallList.add(quote do:
      if dl != fjErr and ctx.checkInstanceOf(`id`, classDef.id) == fjErr:
        dl = fjErr
    )
    gen.jsFunCall.add(id)
  else:
    let s = ident("arg_" & $gen.i)
    gen.jsFunCallList.add(quote do:
      var `s` {.noinit.}: pointer
      if dl != fjErr and ctx.fromJSThis(`id`, classDef.id, `s`) == fjErr:
        dl = fjErr
    )
    gen.jsFunCall.add(quote do: cast[`t`](`s`))
  inc gen.i

proc addCtorParam(gen: var JSFuncGenerator; thisName = "this") =
  let t = gen.funcParams[gen.i].t
  gen.jsFunCall.add(ident(thisName))
  inc gen.i

proc addMagicParam(gen: var JSFuncGenerator; id, magic: NimNode) =
  gen.jsFunCall.add(quote do: cast[typeof(`magic`)](`id`))
  inc gen.i

proc addFixParam(gen: var JSFuncGenerator; id: NimNode) =
  var s = ident("arg_" & $gen.i)
  let t = gen.funcParams[gen.i].t
  gen.jsFunCallList.add(quote do:
    when `t` is JSRef:
      var `s` {.noinit.}: pointer
      if dl != fjErr and ctx.fromJS(`id`, getClassID(`t`), `s`) == fjErr:
        dl = fjErr
    else:
      when `t` is SomeNumber or `t` is enum or `t` is bool:
        var `s` {.noinit.}: `t`
      else:
        var `s`: `t`
      if dl != fjErr and ctx.fromJS(`id`, `s`) == fjErr:
        dl = fjErr
  )
  gen.jsFunCall.add(quote do: cast[`t`](`s`))
  inc gen.i

proc addArgv(gen: var JSFuncGenerator) =
  var j = 0
  while gen.i < gen.minArgs:
    gen.addFixParam(quote do: argv[`j`])
    inc j
  while gen.i < gen.funcParams.len:
    var s = ident("arg_" & $gen.i)
    let t = gen.funcParams[gen.i].t
    if t.kind == nnkBracketExpr and t[0].eqIdent("varargs"):
      s = quote do:
        argv.toOpenArray(`j`, argc - 1)
    else:
      let fallback = gen.funcParams[gen.i].val
      if fallback == nil:
        error("No fallback value.  Maybe a non-optional parameter follows an " &
          "optional parameter?")
      if t.typeKind == ntyGenericParam:
        error("Union parameters are not supported.  Use JSValue instead.")
      gen.jsFunCallList.add(quote do:
        var `s`: `t`
        if dl != fjErr:
          if `j` < argc and not JS_IsUndefined(argv[`j`]):
            if ctx.fromJS(argv[`j`], `s`) == fjErr:
              dl = fjErr
          else:
            `s` = `fallback`
      )
    gen.jsFunCall.add(s)
    inc j
    inc gen.i

proc jsCheckNumArgs*(ctx: JSContext; argc, minargs: cint): FromJSResult =
  if argc < minargs:
    JS_ThrowTypeError(ctx, "At least %d arguments required, but only %d passed",
      minargs, argc)
    return fjErr
  fjOk

proc newJSProc(gen: var JSFuncGenerator; params: openArray[NimNode]): NimNode =
  let jsBody = newStmtList()
  jsBody.add(gen.jsCallAndRet)
  let jsPragmas = newNimNode(nnkPragma)
    .add(ident("cdecl"))
    .add(newTree(nnkExprColonExpr, ident("raises"), newNimNode(nnkBracket)))
  return newProc(gen.newName, params, jsBody, pragmas = jsPragmas)

proc addThisName(gen: var JSFuncGenerator; nimName: NimNode) =
  if gen.t in {bfConstructor, bfConstructorFunction}:
    let rt = gen.returnType
    if rt.kind in {nnkRefTy, nnkPtrTy}:
      gen.thisTypeNode = rt[0]
    else:
      if rt.kind == nnkBracketExpr:
        gen.thisTypeNode = rt[1]
      else:
        gen.thisTypeNode = rt
    gen.newName = ident($gen.t & "_" & gen.funcName)
  elif gen.flag == bffStatic:
    gen.newName = ident($gen.t & "_" & $nimName)
  else:
    var t = gen.funcParams[gen.i].t
    if t.kind in {nnkPtrTy, nnkRefTy}:
      t = t[0]
    gen.thisTypeNode = t
    gen.newName = ident($gen.t & "_" & $t & "_" & gen.funcName)

proc initGenerator(fun: NimNode; t: BoundFunctionType; jsname = "";
    flag = bffNone; magic: NimNode = nil): JSFuncGenerator =
  var funCallName = fun[0]
  if funCallName.kind == nnkPostfix:
    funCallName = funCallName[1]
  result = JSFuncGenerator(
    t: t,
    funcName: if jsname != "": jsname else: $fun.name,
    jsFunCallList: newStmtList(),
    jsFunCall: newCall(funCallName),
    flag: flag,
    magic: magic
  )
  result.readParams(fun)
  result.addThisName(funCallName)

proc makeJSCallAndRet(gen: var JSFuncGenerator; isva: bool) =
  let jfcl = gen.jsFunCallList
  let jfc = gen.jsFunCall
  let ma = cint(gen.length)
  let stmts = if isva and ma > 0:
    quote do:
      var dl {.inject.} = ctx.jsCheckNumArgs(argc, `ma`)
      `jfcl`
  else:
    quote do:
      var dl {.inject.} = fjOk
      `jfcl`
  if gen.returnType != nil:
    stmts.add(quote do:
      if dl != fjErr:
        ctx.toJS(`jfc`)
      else:
        JS_EXCEPTION
    )
  else:
    stmts.add(quote do:
      if dl != fjErr:
        `jfc`
        JS_UNDEFINED
      else:
        JS_EXCEPTION
    )
  gen.jsCallAndRet = stmts

proc generateConstructor(gen: var JSFuncGenerator): NimNode =
  if gen.flag == bffThis:
    gen.addCtorParam()
  gen.addArgv()
  let jfcl = gen.jsFunCallList
  let jfc = gen.jsFunCall
  let ma = cint(gen.length)
  if gen.flag != bffThis:
    gen.jsCallAndRet = quote do:
      var dl {.inject.} = fjOk
      when `ma` > 0:
        dl = ctx.jsCheckNumArgs(argc, `ma`)
      `jfcl`
      if dl != fjErr:
        ctx.toJSNew(`jfc`, this)
      else:
        JS_EXCEPTION
  else:
    gen.jsCallAndRet = quote do:
      var dl {.inject.} = fjOk
      when `ma` > 0:
        dl = ctx.jsCheckNumArgs(argc, `ma`)
      `jfcl`
      if dl != fjErr:
        `jfc`
      else:
        JS_EXCEPTION
  gen.newJSProc(getJSParams())

proc generateHasProperty(gen: var JSFuncGenerator): NimNode =
  gen.addThisParam()
  gen.addFixParam(ident"atom")
  let jfcl = gen.jsFunCallList
  let jfc = gen.jsFunCall
  gen.jsCallAndRet = quote do:
    var dl {.inject.} = fjOk
    `jfcl`
    if dl != fjErr:
      cint(`jfc`)
    else:
      cint(-1)
  gen.newJSProc(getJSHasPropParams())

proc generateGetOwnProperty(gen: var JSFuncGenerator): NimNode =
  gen.addThisParam()
  gen.addFixParam(ident"prop")
  var handleRetv: NimNode
  if gen.i < gen.funcParams.len:
    handleRetv = quote do: discard
    gen.jsFunCall.add(ident("desc"))
  else:
    handleRetv = quote do:
      if desc != nil:
        # From quickjs.h:
        # > If 1 is returned, the property descriptor 'desc' is filled
        # > if != NULL.
        # So desc may be nil.
        desc[].setter = JS_UNDEFINED
        desc[].getter = JS_UNDEFINED
        desc[].value = retv
        desc[].flags = 0
      else:
        JS_FreeValue(ctx, retv)
  let jfcl = gen.jsFunCallList
  let jfc = gen.jsFunCall
  gen.jsCallAndRet = quote do:
    var dl {.inject.} = fjOk
    if JS_GetOpaque(this, JS_GetClassID(this)) == nil:
      return cint(0)
    `jfcl`
    if dl != fjErr:
      let retv {.inject.} = ctx.toJS(`jfc`)
      if JS_IsException(retv):
        cint(-1)
      elif JS_IsUninitialized(retv):
        cint(0)
      else:
        `handleRetv`
        cint(1)
    else:
      cint(-1)
  gen.newJSProc(getJSGetOwnPropParams())

proc generateGetProperty(gen: var JSFuncGenerator): NimNode =
  gen.addThisParam("receiver")
  gen.addFixParam(ident"prop")
  if gen.i < gen.funcParams.len:
    gen.addFixParam(ident"this")
  let jfcl = gen.jsFunCallList
  let jfc = gen.jsFunCall
  gen.jsCallAndRet = quote do:
    var dl {.inject.} = fjOk
    `jfcl`
    if dl != fjErr:
      ctx.toJS(`jfc`)
    else:
      JS_EXCEPTION
  gen.newJSProc(getJSGetPropParams())

proc generateSetProperty(gen: var JSFuncGenerator): NimNode =
  gen.addThisParam("receiver")
  gen.addFixParam(ident"atom")
  gen.addFixParam(ident"value")
  if gen.i < gen.funcParams.len:
    gen.addFixParam(ident"this")
  let jfcl = gen.jsFunCallList
  let jfc = gen.jsFunCall
  gen.jsCallAndRet = if gen.returnType != nil:
    quote do:
      var dl {.inject.} = fjOk
      `jfcl`
      if dl != fjErr:
        let v = toJS(ctx, `jfc`)
        if JS_IsException(v):
          cint(-1)
        elif JS_IsUninitialized(v):
          cint(0)
        else:
          cint(1)
      else:
        cint(-1)
  else:
    quote do:
      var dl {.inject.} = fjOk
      `jfcl`
      if dl != fjErr:
        cint(1)
      else:
        cint(-1)
  gen.newJSProc(getJSSetPropParams())

proc generateDelProperty(gen: var JSFuncGenerator): NimNode =
  gen.addThisParam()
  gen.addFixParam(ident"prop")
  let jfcl = gen.jsFunCallList
  let jfc = gen.jsFunCall
  gen.jsCallAndRet = quote do:
    var dl {.inject.} = fjOk
    `jfcl`
    if dl != fjErr:
      cint(`jfc`)
    else:
      cint(-1)
  gen.newJSProc(getJSDelPropParams())

proc generateGetOwnPropertyNames(gen: var JSFuncGenerator): NimNode =
  gen.addThisParam()
  let jfcl = gen.jsFunCallList
  let jfc = gen.jsFunCall
  gen.jsCallAndRet = quote do:
    var dl {.inject.} = fjOk
    `jfcl`
    if dl != fjErr and (let retv = `jfc`; retv.ctx != nil):
      ptab[] = retv.buffer
      plen[] = retv.len
      cint(0)
    else:
      cint(-1)
  gen.newJSProc(getJSPropNamesParams())

proc generateGet(gen: var JSFuncGenerator): NimNode =
  if gen.length != 0 or gen.funcParams.len != gen.minArgs:
    error("jsfget functions must only accept one parameter")
  if gen.returnType == nil:
    error("jsfget functions must have a return type")
  gen.addThisParam()
  if gen.flag == bffMagic:
    gen.addMagicParam(ident"magic", gen.magic)
  gen.makeJSCallAndRet(isva = false)
  let jsProc = if gen.flag notin {bffReplaceable, bffMagic}:
    gen.newJSProc(getJSGetterParams())
  else:
    gen.newJSProc(getJSMagicGetterParams())
  jsProc

proc generateSet(gen: var JSFuncGenerator): NimNode =
  if gen.length != 1 or gen.funcParams.len != gen.minArgs:
    error("jsfset functions must accept two parameters")
  gen.addThisParam()
  if gen.flag == bffMagic:
    gen.addMagicParam(ident"magic", gen.magic)
  gen.addFixParam(ident"val")
  gen.makeJSCallAndRet(isva = false)
  let jsProc = if gen.flag != bffMagic:
    gen.newJSProc(getJSSetterParams())
  else:
    gen.newJSProc(getJSMagicSetterParams())
  jsProc

proc generateFunction(gen: var JSFuncGenerator): NimNode =
  if gen.minArgs == 0 and gen.flag != bffStatic:
    error("missing `this' parameter")
  if gen.flag != bffStatic:
    gen.addThisParam()
  if gen.flag == bffMagic:
    gen.addMagicParam(ident"magic", gen.magic)
  gen.addArgv()
  gen.makeJSCallAndRet(isva = true)
  let jsProc = if gen.flag == bffMagic:
    gen.newJSProc(getJSMagicParams())
  else:
    gen.newJSProc(getJSParams())
  jsProc

proc generateIter(gen: var JSFuncGenerator): NimNode =
  gen.addThisParam()
  gen.jsFunCall.add(ident("pdone"))
  let jfcl = gen.jsFunCallList
  let jfc = gen.jsFunCall
  gen.jsCallAndRet = quote do:
    var dl {.inject.} = fjOk
    `jfcl`
    if dl != fjErr:
      `jfc`
    else:
      JS_EXCEPTION
  gen.newJSProc(getJSIterParams())

proc bindReplaceableSet(stmts: NimNode; info: RegistryInfo) =
  let rsf = ident("js_replaceable_set")
  let trns = info.tabReplaceableNames
  stmts.add(quote do:
    const replaceableNames = `trns`
    proc `rsf`(ctx: JSContext; this, val: JSValueConst; magic: cint): JSValue
        {.cdecl.} =
      let val = if JS_IsUndefined(val):
        JSValueConst(ctx.getOpaque().global)
      else:
        val
      var dummy {.noinit.}: pointer
      if ctx.fromJS(this, classDef.id, dummy) == fjErr:
        return JS_EXCEPTION
      let name = replaceableNames[int(magic)]
      let dval = JS_DupValue(ctx, val)
      if JS_DefinePropertyValueStr(ctx, this, name, dval, JS_PROP_C_W_E) < 0:
        return JS_EXCEPTION
      return JS_DupValue(ctx, val)
  )

proc bindGetSet(info: RegistryInfo) =
  var replaceableId = 0u16
  for k, it in info.getset:
    let get = if it.get != nil: it.get else: newNilLit()
    let set = if it.set != nil: it.set else: newNilLit()
    let flag = it.flag
    let magic = it.magic
    case flag
    of bffNone:
      info.tabFuns.add(quote do:
        JS_CGETSET_DEF(`k`, `get`, `set`,
          JS_PROP_CONFIGURABLE or JS_PROP_ENUMERABLE)
      )
    of bffUnforgeable:
      info.tabUnforgeable.add(quote do:
        JS_CGETSET_DEF(`k`, `get`, `set`, JS_PROP_ENUMERABLE)
      )
    of bffMagic:
      info.tabFuns.add(quote do:
        JS_CGETSET_MAGIC_DEF(`k`, `get`, `set`, int16(`magic`),
          JS_PROP_ENUMERABLE)
      )
    of bffReplaceable:
      if set != nil:
        error("Replaceable properties must not have a setter.")
      let orid = replaceableId
      inc replaceableId
      if orid > replaceableId:
        error("Too many replaceable functions defined.")
      let magic = cast[int16](orid)
      info.tabFuns.add(quote do:
        JS_CGETSET_MAGIC_DEF(`k`, `get`, js_replaceable_set, `magic`,
          JS_PROP_CONFIGURABLE or JS_PROP_ENUMERABLE)
      )
    else:
      error("Static getters and setters are not supported.")

template jsget*(typ, field, funcName: untyped) =
  proc funcName(ctx: JSContext; this: JSValueConst): JSValue {.cdecl.} =
    var arg_0 {.noinit.}: pointer
    if ctx.fromJSThis(this, classDef.id, arg_0) == fjErr:
      return JS_EXCEPTION
    when cast[ptr typ.T](arg0).field is JSValue:
      return JS_DupValue(ctx, cast[ptr typ.T](arg0).field)
    else:
      return ctx.toJS(cast[ptr typ.T](arg_0).field)

template jsufget*(typ, field, funcName: untyped) =
  jsget(typ, field, funcName) # only differs in the macro

template jsset*(typ, field, funcName: untyped) =
  proc funcName(ctx: JSContext; this, val: JSValueConst): JSValue {.cdecl.} =
    var arg_0 {.noinit.}: pointer
    if ctx.fromJSThis(this, classDef.id, arg_0) == fjErr:
      return JS_EXCEPTION
    # We can't just set arg_0.field directly, or fromJS may damage it.
    var nodeVal: typeof(cast[ptr typ.T](arg_0).field)
    when nodeVal is JSValue:
      static:
        error(".jsset is not supported on JSValue; use jsfset")
    else:
      if ctx.fromJS(val, nodeVal) == fjErr:
        return JS_EXCEPTION
    cast[ptr typ.T](arg_0).field = move(nodeVal)
    return JS_UNDEFINED

template jsgetset*(typ, field, get, set: untyped) =
  jsget typ, field, get
  jsset typ, field, set

proc runFinalizers*(rt: JSRuntime; p: pointer) =
  let class = JS_GetForeignClassID(p)
  let rtOpaque = rt.getOpaque()
  for fin in rtOpaque.finalizers(class):
    fin(rt, p)

template myDestroy*(p: untyped) =
  when not supportsCopyMem(typeof(p)):
    {.cast(raises: []).}:
      `=destroy`(p)

proc jsClassTypeRecurse(markList, finList, recList: NimNode) =
  for it in recList.children:
    case it.kind
    of nnkRecList:
      jsClassTypeRecurse(markList, finList, it)
    of nnkRecCase:
      error("case objects are not supported")
    else:
      for i in 0 ..< it.len - 2:
        var varNode = it[i]
        if varNode.kind == nnkPragmaExpr:
          varNode = varNode[0]
        if varNode.kind == nnkPostfix:
          varNode = varNode[1]
        let typ = it[^2]
        if typ.getTypeInst().sameType(JSValue.getType()):
          markList.add(quote do:
            JS_MarkValue(rt, this.`varNode`, markFunc)
          )
          finList.add(quote do:
            JS_FreeValueRT(rt, this.`varNode`)
          )
        else:
          var impl = typ
          if typ.kind == nnkSym:
            impl = typ.getImpl()
          if impl.kind == nnkTypeDef and impl[2].kind == nnkBracketExpr and
              impl[2][0].sameType(JSRef.getType()):
            markList.add(quote do:
              JS_MarkForeignObject(rt, cast[pointer](this.`varNode`), markFunc)
            )
          finList.add(quote do:
            myDestroy(this.`varNode`)
          )

template jsextends*(class: ChaClassDef) =
  classDef.parent = class.id

proc setGet(exv: var GetSet; get: NimNode; item: GetSet) =
  exv.get = get
  exv.flag = item.flag
  if item.magic != nil:
    assert exv.magic == item.magic

proc setSet(exv: var GetSet; set: NimNode; item: GetSet) =
  exv.set = set
  if item.flag != bffNone:
    exv.flag = item.flag
  if item.magic != nil:
    assert exv.magic == item.magic

proc jsClassRecurse(stmts, body: NimNode; info: var RegistryInfo) =
  for child in body:
    case child.kind
    of nnkProcDef, nnkFuncDef, nnkMethodDef:
      let pragmas = child.pragma
      var gen: JSFuncGenerator
      for j in countdown(pragmas.len - 1, 0):
        let pragma = pragmas[j]
        var jsname = ""
        var magic: NimNode
        var pragmaName: string
        case pragma.kind
        of nnkExprColonExpr, nnkCall:
          expectKind pragma[1], nnkStrLit
          jsname = $pragma[1]
          if pragma.kind == nnkCall and pragma.len >= 3:
            magic = pragma[2]
          pragmaName = $pragma[0]
        of nnkIdent:
          pragmaName = $pragma
        else:
          error("unexpected pragma")
        var t: BoundFunctionType
        var flag = bffNone
        case pragmaName
        of "jsctor": t = bfConstructor
        of "jsctor2": (t = bfConstructor; flag = bffThis)
        of "jsfctor": t = bfConstructorFunction
        of "jsfunc": t = bfFunction
        of "jsmfunc": (t = bfFunction; flag = bffMagic)
        of "jsstfunc": (t = bfFunction; flag = bffStatic)
        of "jsuffunc": (t = bfFunction; flag = bffUnforgeable)
        of "jsfget": t = bfGetter
        of "jsuffget": (t = bfGetter; flag = bffUnforgeable)
        of "jsrfget": (t = bfGetter; flag = bffReplaceable)
        of "jsmfget": (t = bfGetter; flag = bffMagic)
        of "jsfset": t = bfSetter
        of "jsmfset": (t = bfSetter; flag = bffMagic)
        of "jsiter": t = bfIteratorNext
        of "jsfin": t = bfFinalizer
        of "jsmark": t = bfMark
        of "jsgetownprop": t = bfPropertyGetOwn
        of "jspropnames": t = bfPropertyNames
        of "jssetprop": t = bfPropertySet
        of "jsdelprop": t = bfPropertyDel
        of "jsgetprop": t = bfPropertyGet
        of "jshasprop": t = bfPropertyHas
        of "used": continue
        else: error("unknown pragma " & pragmaName)
        if gen.newName == nil or t != gen.t or flag != gen.flag:
          gen = initGenerator(child, t, jsname, flag, magic)
          case t
          of bfConstructor, bfConstructorFunction:
            stmts.add(gen.generateConstructor())
          of bfFunction: stmts.add(gen.generateFunction())
          of bfGetter: stmts.add(gen.generateGet())
          of bfSetter: stmts.add(gen.generateSet())
          of bfIteratorNext: stmts.add(gen.generateIter())
          of bfFinalizer, bfMark: discard
          of bfPropertyGetOwn: stmts.add(gen.generateGetOwnProperty())
          of bfPropertyNames: stmts.add(gen.generateGetOwnPropertyNames())
          of bfPropertySet: stmts.add(gen.generateSetProperty())
          of bfPropertyDel: stmts.add(gen.generateDelProperty())
          of bfPropertyGet: stmts.add(gen.generateGetProperty())
          of bfPropertyHas: stmts.add(gen.generateHasProperty())
        else:
          gen.funcName = if jsname != "": jsname else: $child.name
        let name = gen.funcName
        let id = gen.newName
        case t
        of bfConstructor, bfConstructorFunction:
          if info.ctorFun != nil:
            error("only one constructor is allowed")
          if t == bfConstructorFunction:
            info.ctorType = JS_CFUNC_constructor_or_func
          info.ctorFun = id
        of bfFunction:
          let len = gen.length
          case flag
          of bffNone:
            info.tabFuns.add(quote do:
              JS_CFUNC_DEF(`name`, `len`, `id`, JS_PROP_C_W_E)
            )
          of bffStatic:
            info.tabStatic.add(quote do:
              JS_CFUNC_DEF(`name`, `len`, `id`, JS_PROP_C_W_E)
            )
          of bffMagic:
            info.tabFuns.add(quote do:
              JS_CFUNC_MAGIC_DEF(`name`, `len`, `id`, int16(`magic`),
                JS_PROP_C_W_E)
            )
          of bffUnforgeable:
            info.tabUnforgeable.add(quote do:
              JS_CFUNC_DEF(`name`, `len`, `id`, JS_PROP_ENUMERABLE)
            )
          else: assert false
        of bfGetter:
          let item = GetSet(flag: gen.flag, magic: magic)
          info.getset.mgetOrPut(name, item).setGet(id, item)
          if flag == bffReplaceable:
            info.tabReplaceableNames.add(newCall("cstring",
              newStrLitNode(name)))
        of bfSetter:
          let item = GetSet(flag: gen.flag, magic: magic)
          info.getset.mgetOrPut(name, item).setSet(id, item)
        of bfIteratorNext:
          let len = gen.length
          info.tabFuns.add(quote do:
            JS_ITERATOR_NEXT_DEF(`name`, `len`, `id`, 0)
          )
        of bfFinalizer:
          if info.finFun != nil:
            error("Class " & info.name & " has 2+ jsfin functions.")
          info.finFun = child.name
        of bfMark:
          if info.markFun != nil:
            error("Class " & info.name & " has 2+ jsmark functions.")
          info.markFun = child.name
        of bfPropertyGetOwn:
          if info.propGetOwnFun != nil:
            error("Class " & info.name & " has 2+ jsgetownprop functions.")
          info.propGetOwnFun = id
          info.hasExotic = true
        of bfPropertyNames:
          if info.propNamesFun != nil:
            error("Class " & info.name & " has 2+ jspropnames functions.")
          info.propNamesFun = id
          info.hasExotic = true
        of bfPropertySet:
          if info.propSetFun != nil:
            error("Class " & info.name & " has 2+ jssetprop functions.")
          info.propSetFun = id
          info.hasExotic = true
        of bfPropertyDel:
          if info.propDelFun != nil:
            error("Class " & info.name & " has 2+ jsdelprop functions.")
          info.propDelFun = id
          info.hasExotic = true
        of bfPropertyGet:
          if info.propGetFun != nil:
            error("Class " & info.name & " has 2+ jsgetprop functions.")
          info.propSetFun = id
          info.hasExotic = true
        of bfPropertyHas:
          if info.propHasFun != nil:
            error("Class " & info.name & " has 2+ jsgetprop functions.")
          info.propHasFun = id
          info.hasExotic = true
        pragmas.del(j)
    of nnkCommand:
      if child[0].strVal == "jsget":
        if child.len < 4:
          child.add(newStrLitNode(child[2].strVal))
        let id = ident($bfGetter & '_' & $child[1] & '_' & child[3].strVal)
        for i in countdown(child.len - 1, 3):
          expectKind child[i], nnkStrLit
          let item = GetSet(flag: bffNone)
          info.getset.mgetOrPut(child[i].strVal, item).setGet(id, item)
          child.del(i)
        child.add(id)
      elif child[0].strVal == "jsgetset":
        if child.len < 4:
          child.add(newStrLitNode(child[2].strVal))
        let get = ident($bfGetter & '_' & $child[1] & '_' & child[3].strVal)
        let set = ident($bfSetter & '_' & $child[1] & '_' & child[3].strVal)
        let item = GetSet(flag: bffNone, get: get, set: set)
        for i in countdown(child.len - 1, 3):
          expectKind child[i], nnkStrLit
          info.getset[child[i].strVal] = item
          child.del(i)
        child.add(get)
        child.add(set)
      elif child[0].strVal == "jsufget":
        if child.len < 4:
          child.add(newStrLitNode(child[2].strVal))
        let id = ident($bfGetter & '_' & $child[1] & '_' & child[3].strVal)
        for i in countdown(child.len - 1, 3):
          expectKind child[i], nnkStrLit
          let item = GetSet(flag: bffUnforgeable)
          info.getset.mgetOrPut(child[i].strVal, item).setGet(id, item)
          child.del(i)
        child.add(id)
    of nnkStmtList:
      stmts.jsClassRecurse(child, info)
    else: discard

proc nilToLit(node: NimNode): NimNode =
  if node == nil:
    return newNilLit()
  return node

macro jsClassImpl(def: untyped; jsname: static string; typ: typed;
    body: untyped) =
  var info = RegistryInfo(
    tabFuns: newNimNode(nnkBracket),
    tabUnforgeable: newNimNode(nnkBracket),
    tabStatic: newNimNode(nnkBracket),
    tabReplaceableNames: newNimNode(nnkBracket),
    ctorType: JS_CFUNC_constructor
  )
  let stmts = newStmtList()
  when NimMajor < 2:
    stmts.add(quote do:
      template classDef(): ChaClassDef {.used.} =
        `def`
    )
  else:
    stmts.add(quote do:
      template classDef(): ChaClassDef {.used, redefine.} =
        `def`
    )
  stmts.add(body)
  stmts.jsClassRecurse(body, info)
  if info.tabReplaceableNames.len > 0:
    stmts.bindReplaceableSet(info)
  info.bindGetSet()
  let funs = info.tabFuns
  let funsEnd = int16(funs.len)
  for fun in info.tabStatic:
    funs.add(fun)
  let staticFunsEnd = int16(funs.len)
  for fun in info.tabUnforgeable:
    funs.add(fun)
  let unforgeableFunsEnd = int16(funs.len)
  if funs.len > 0:
    stmts.add(quote do:
      let funs {.global.} = `funs`
      `def`.funsBase = cast[JSCFunctionListP](unsafeAddr funs[0])
      `def`.funsEnd = `funsEnd`
      `def`.staticFunsEnd = `staticFunsEnd`
      `def`.unforgeableFunsEnd = `unforgeableFunsEnd`
    )
  if info.hasExotic:
    let propGetOwnFun = nilToLit(info.propGetOwnFun)
    let propGetFun = nilToLit(info.propGetFun)
    let propSetFun = nilToLit(info.propSetFun)
    let propDelFun = nilToLit(info.propDelFun)
    let propHasFun = nilToLit(info.propHasFun)
    let propNamesFun = nilToLit(info.propNamesFun)
    stmts.add(quote do:
      let exotic {.global.} = JSClassExoticMethods(
        get_own_property: `propGetOwnFun`,
        get_own_property_names: `propNamesFun`,
        has_property: `propHasFun`,
        get_property: `propGetFun`,
        set_property: `propSetFun`,
        delete_property: `propDelFun`
      )
      `def`.exotic = unsafeAddr exotic
    )
  let ctorFun = nilToLit(info.ctorFun)
  var markFun = info.markFun
  var finFun = info.finFun
  if typ != nil:
    when NimMajor < 2:
      stmts.add(quote do:
        globalJSTypeMap[getJSTypeId(`typ`.T)] = classDef.id
      )
    let markList = newStmtList()
    if markFun != nil:
      markList.add(quote do:
        `markFun`(rt, cast[`typ`](this), markFunc)
      )
    let finList = newStmtList()
    if finFun != nil:
      finList.add(quote do:
        `finFun`(rt, cast[`typ`](this))
      )
    let impl = typ.getImpl()[2][1].getImpl()
    jsClassTypeRecurse(markList, finList, impl[2])
    if markList.len > 0:
      let id = ident($bfMark & "_" & jsname)
      stmts.add(quote do:
        proc `id`(rt {.inject.}: JSRuntime; this: pointer;
            markFunc {.inject.}: JS_MarkFunc) =
          let this {.inject.} = cast[ptr `typ`.T](this)
          `markList`
      )
      markFun = id
    if finList.len > 0:
      let id = ident($bfFinalizer & "_" & jsname)
      stmts.add(quote do:
        proc `id`(rt {.inject.}: JSRuntime; this: pointer) =
          let this {.inject.} = cast[ptr `typ`.T](this)
          `finList`
      )
      finFun = id
  else:
    if markFun != nil:
      let id = ident($bfFinalizer & "_" & jsname)
      stmts.add(quote do:
        proc `id`(rt: JSRuntime; this: pointer; markFunc: JS_MarkFunc) =
          `finFun`(rt, cast[JSRef[`typ`]](this), markFunc)
      )
      markFun = id
    if finFun != nil:
      let id = ident($bfFinalizer & "_" & jsname)
      stmts.add(quote do:
        proc `id`(rt: JSRuntime; this: pointer) =
          `finFun`(rt, cast[JSRef[`typ`]](this))
      )
      finFun = id
  let ctorType = info.ctorType
  stmts.add(quote do:
    `def`.class_name = cstring(`jsname`)
    `def`.ctor = `ctorFun`
    `def`.ctorType = JSCFunctionEnum(`ctorType`)
  )
  if finFun != nil:
    stmts.add(quote do:
      `def`.finalizer = `finFun`
    )
  if markFun != nil:
    stmts.add(quote do:
      `def`.mark = `markFun`
    )
  when NimMajor < 2:
    stmts.add(quote do:
      template classDef(): ChaClassDef {.used, error.} =
        discard
    )
  else:
    stmts.add(quote do:
      template classDef(): ChaClassDef {.used, redefine, error.} =
        discard
    )
  stmts

template jsClassRaw*(def: untyped; jsname: string; body: untyped) =
  # why Nim insists on zero-initing global variables is an eternal mystery.
  var def {.global, noinit, inject.}: ChaClassDef
  def.raw = true
  discard JS_NewClassID(def.id)
  jsClassImpl(def, jsname, nil, body)

template jsClassNameDef*(nimt: typedesc; jsname: string; body: untyped) =
  var `nimt Def` {.global, noinit, inject.}: ChaClassDef
  discard JS_NewClassID(`nimt Def`.id)
  jsClassImpl(`nimt Def`, jsname, nimt):
    proc getClassID(t {.inject.}: typedesc[nimt]): JSClassID {.used.} =
      classDef.id
    body

template jsClassPublicNameDef*(nimt: typedesc; jsname: string; body: untyped) =
  var `nimt Def`* {.global, noinit, inject.}: ChaClassDef
  discard JS_NewClassID(`nimt Def`.id)
  jsClassImpl(`nimt Def`, jsname, nimt):
    proc getClassID*(t {.inject.}: typedesc[nimt]): JSClassID {.used.} =
      classDef.id
    body

template jsClassDef*(nimt: typedesc; body: untyped) =
  var `nimt Def` {.global, noinit, inject.}: ChaClassDef
  discard JS_NewClassID(`nimt Def`.id)
  jsClassImpl(`nimt Def`, astToStr(nimt), nimt):
    proc getClassID(t {.inject.}: typedesc[nimt]): JSClassID {.used.} =
      classDef.id
    body

template jsClassPublicDef*(nimt: typedesc; body: untyped) =
  var `nimt Def`* {.global, noinit, inject.}: ChaClassDef
  discard JS_NewClassID(`nimt Def`.id)
  jsClassImpl(`nimt Def`, astToStr(nimt), nimt):
    proc getClassID*(t {.inject.}: typedesc[nimt]): JSClassID =
      classDef.id
    body

template jsNamespaceDef*(name, body: untyped) =
  var `name Def` {.global, noinit, inject.}: ChaClassDef
  jsClassImpl(`name Def`, astToStr(name), nil, body)

proc registerClassCommon(ctx: JSContext; def: ChaClassDef): FromJSResult =
  let rt = JS_GetRuntime(ctx)
  let id = def.id
  let rtOpaque = rt.getOpaque()
  var cdef: JSClassDef
  cdef.class_name = def.class_name
  cdef.exotic = def.exotic
  let raw = def.raw and
    (def.parent == JS_INVALID_CLASS_ID or rtOpaque.classes[int(id)].raw)
  if not raw:
    cdef.gc_mark = jsMark
    cdef.finalizer = jsFinalize
  if JS_NewClass(rt, id, addr cdef) != 0:
    return fjErr
  if rtOpaque.classes.len <= int(id):
    rtOpaque.classes.setLen(int(id) + 1)
  rtOpaque.classes[int(id)].raw = raw
  rtOpaque.classes[int(id)].parent = def.parent
  if not rtOpaque.addClass(def):
    return fjErr
  fjOk

proc registerClass*(ctx: JSContext; def: ChaClassDef; namespace = JS_NULL):
    FromJSResult =
  let rt = JS_GetRuntime(ctx)
  if ctx.registerClassCommon(def) == fjErr:
    return fjErr
  let ctxOpaque = ctx.getOpaque()
  if ctxOpaque == nil: # no scripting
    return fjOk
  let proto = ctx.newProtoFromParentClass(def.parent, def.iterable, JS_NULL)
  let id = def.id
  JS_SetClassProto(ctx, id, JS_DupValue(ctx, proto))
  let name = JS_NewString(ctx, def.class_name)
  let strSym = ctxOpaque.symRefs[jsyToStringTag]
  if ctx.definePropertyC(proto, strSym, name) == dprException or
      not ctx.setPropertyFunctionList(proto, def.funs):
    JS_FreeValue(ctx, proto)
    return fjErr
  let jctor = ctx.newCtorFunFromParentClass(def.ctor, def.class_name,
    def.parent, def.ctorType)
  if not ctx.setPropertyFunctionList(jctor, def.staticFuns):
    JS_FreeValue(ctx, jctor)
    JS_FreeValue(ctx, proto)
    return fjErr
  JS_SetConstructor(ctx, jctor, proto)
  if ctxOpaque.ctors.len <= int(id):
    ctxOpaque.ctors.setLen(int(id) + 1)
  if ctx.defineIterableProps(def.iterable, proto, id) == dprException:
    JS_FreeValue(ctx, proto)
    return fjErr
  JS_FreeValue(ctx, proto)
  if not JS_IsUndefined(namespace):
    let target = if JS_IsNull(namespace):
      JSValueConst(ctxOpaque.global)
    else:
      namespace
    if ctx.definePropertyCW(target, def.class_name,
        JS_DupValue(ctx, jctor)) == dprException:
      JS_FreeValue(ctx, jctor)
      return fjErr
  ctxOpaque.ctors[int(id)] = jctor
  fjOk

proc registerNamespace*(ctx: JSContext; def: ChaClassDef): JSValue =
  assert def.unforgeableFuns.len == 0 and def.funs.len == 0
  let ctxOpaque = ctx.getOpaque()
  if ctxOpaque == nil:
    return JS_UNDEFINED
  let obj = JS_NewObject(ctx)
  if JS_IsException(obj):
    return obj
  let strSym = ctxOpaque.symRefs[jsyToStringTag]
  let name = ctx.toJS(def.class_name)
  if JS_IsException(name):
    JS_FreeValue(ctx, obj)
    return name
  if ctx.definePropertyC(obj, strSym, name) == dprException or
      not ctx.setPropertyFunctionList(obj, def.staticFuns):
    JS_FreeValue(ctx, obj)
    return JS_EXCEPTION
  if ctx.definePropertyCW(ctxOpaque.global, def.class_name,
      JS_DupValue(ctx, obj)) == dprException:
    JS_FreeValue(ctx, obj)
    return JS_EXCEPTION
  return obj

proc registerNamespaceFree*(ctx: JSContext; def: ChaClassDef): FromJSResult =
  let obj = ctx.registerNamespace(def)
  if JS_IsException(obj):
    return fjErr
  JS_FreeValue(ctx, obj)
  fjOk

proc registerFakeClass*(ctx: JSContext; def: ChaClassDef): FromJSResult =
  ## Register a class that will not be exposed to JS.
  ## The prototype is set to the parent class's prototype; however, runtime
  ## type checks in Nim respect the actual class hierarchy.
  if ctx.registerClassCommon(def) == fjErr:
    return fjErr
  let ctxOpaque = ctx.getOpaque()
  if ctxOpaque != nil:
    let iid = int(def.id)
    if ctxOpaque.ctors.len <= iid:
      ctxOpaque.ctors.setLen(iid + 1)
    if def.parent == JS_INVALID_CLASS_ID:
      let obj = JS_NewObject(ctx)
      let proto = JS_GetPrototype(ctx, obj)
      JS_FreeValue(ctx, obj)
      JS_SetClassProto(ctx, def.id, proto)
      let funProto = JS_GetPrototype(ctx, ctxOpaque.valRefs[jsvFunction])
      ctxOpaque.ctors[iid] = funProto
    else:
      let proto = JS_GetClassProto(ctx, def.parent)
      JS_SetClassProto(ctx, def.id, proto)
      ctxOpaque.ctors[iid] = JS_DupValue(ctx, ctxOpaque.ctors[int(def.parent)])
  fjOk

proc registerGlobalClass*(ctx: JSContext; def: ChaClassDef;
    parentProto: JSValueConst = JS_NULL): FromJSResult =
  let rt = JS_GetRuntime(ctx)
  if ctx.registerClassCommon(def) == fjErr:
    return fjErr
  let ctxOpaque = ctx.getOpaque()
  if ctxOpaque == nil: # no scripting
    return fjOk
  let proto = ctx.newProtoFromParentClass(def.parent, def.iterable,
    parentProto)
  let id = def.id
  JS_SetClassProto(ctx, id, JS_DupValue(ctx, proto))
  let name = JS_NewString(ctx, def.class_name)
  let strSym = ctxOpaque.symRefs[jsyToStringTag]
  let global = ctxOpaque.global
  assert ctxOpaque.gclass == JS_INVALID_CLASS_ID
  ctxOpaque.gclass = def.id
  let name2 = JS_DupValue(ctx, name)
  # Global already exists, so set unforgeable functions here
  if ctx.definePropertyC(global, strSym, name2) == dprException or
      ctx.definePropertyC(proto, strSym, name) == dprException or
      JS_SetPrototype(ctx, global, proto) != 1 or
      not ctx.setPropertyFunctionList(global, def.funs) or
      not ctx.setUnforgeable(global, def.id):
    JS_FreeValue(ctx, proto)
    return fjErr
  let jctor = ctx.newCtorFunFromParentClass(def.ctor, def.class_name,
    def.parent, def.ctorType)
  if not ctx.setPropertyFunctionList(jctor, def.staticFuns):
    JS_FreeValue(ctx, jctor)
    JS_FreeValue(ctx, proto)
    return fjErr
  JS_SetConstructor(ctx, jctor, proto)
  if ctxOpaque.ctors.len <= int(id):
    ctxOpaque.ctors.setLen(int(id) + 1)
  if ctx.defineIterableProps(def.iterable, proto, id) == dprException:
    JS_FreeValue(ctx, proto)
    return fjErr
  JS_FreeValue(ctx, proto)
  if ctx.definePropertyCW(global, def.class_name,
      JS_DupValue(ctx, jctor)) == dprException:
    JS_FreeValue(ctx, jctor)
    return fjErr
  ctxOpaque.ctors[int(id)] = jctor
  fjOk

{.pop.} # raises
