## JavaScript binding generator. Horrifying, I know. But it works!
## Pragmas:
## {.jsctor.} for constructors. These need no `this' value, and are
##   bound as regular constructors in JS. They must return a ref object,
##   which will have a JS counterpart too. (Other functions can return
##   ref objects too, which will either use the existing JS counterpart,
##   if exists, or create a new one. In other words: cross-language
##   reference semantics work seamlessly.)
## {.jsfunc.} is used for binding normal functions. Needs a `this'
##   value, as all following pragmas. Generics are not supported, but
##   JSValue does.
##   By default, the Nim function name is bound; if this is not desired,
##   you can rename the function like this: {.jsfunc: "preferredName".}
##   This also works for all other pragmas that define named functions
##   in JS.
## {.jsstfunc.} binds static functions. Unlike .jsfunc, it does not
##   have a `this' value. A class name must be specified,
##   e.g. {.jsstfunc: "URL".} to define on the URL class. To
##   rename a static function, use the syntax "ClassName:funcName",
##   e.g. "Response:error".
## {.jsget.}, {.jsfget.} must be specified on object fields; these
##   generate regular getter & setter functions.
## {.jsufget, jsuffget, jsuffunc.} For fields with the
##   [LegacyUnforgeable] WebIDL property.
##   This makes it so a non-configurable/writable, but enumerable
##   property is defined on the object when the *constructor* is called
##   (i.e. NOT on the prototype.)
## {.jsrget.}, {.jsrfget.}: For fields with the [Replaceable] WebIDL
##   property.
## {.jsfget.} and {.jsfset.} for getters/setters. Note the `f'; bare
##   jsget/jsset can only be used on object fields. (I initially wanted
##   to use the same keyword, unfortunately that didn't work out.)
## {.jsgetownprop.} Called when GetOwnProperty would return nothing. The
##   key must be either a JSAtom, uint32 or string. (Note that the
##   string option copies.)
## {.jsgetprop.} for property getters. Called on GetProperty.
##   (In fact, this can be emulated using get_own_property, but this
##   might still be faster.)
## {.jssetprop.} for property setters. Called on SetProperty - in fact
##   this is the set() method of Proxy, except it always returns
##   true. Same rules as jsgetprop for keys.
## {.jsdelprop.} for property deletion. It is like the deleteProperty
##   method of Proxy. Must return true if deleted, false if not deleted.
## {.jshasprop.} for overriding has_property. Must return a boolean,
##   or the integer 1 for true, 0 for false, or -1 for exception.
## {.jspropnames.} overrides get_own_property_names. Must return a
##   JSPropertyEnumList object.

{.push raises: [].}

import std/macros
import std/sets
import std/strutils
import std/tables

import fromjs
import jserror
import jsopaque
import jsutils
import optshim
import quickjs
import tojs

export
  JS_NULL, JS_UNDEFINED, JS_FALSE, JS_TRUE, JS_EXCEPTION, JS_UNINITIALIZED,
  JS_EVAL_TYPE_GLOBAL,
  JS_EVAL_TYPE_MODULE,
  JS_EVAL_TYPE_DIRECT,
  JS_EVAL_TYPE_INDIRECT,
  JS_EVAL_TYPE_MASK,
  JS_EVAL_FLAG_SHEBANG,
  JS_EVAL_FLAG_STRICT,
  JS_EVAL_FLAG_COMPILE_ONLY,
  JSRuntime, JSContext, JSValue, JSValueConst, JSClassID, JSAtom,
  JS_GetGlobalObject, JS_FreeValue, JS_IsException, JS_GetPropertyStr,
  JS_IsFunction, JS_NewCFunctionData, JS_Call, JS_DupValue, JS_IsUndefined,
  JS_ThrowTypeError, JS_ThrowRangeError, JS_ThrowSyntaxError,
  JS_ThrowInternalError, JS_ThrowReferenceError

when sizeof(int) < sizeof(int64):
  export quickjs.`==`

type
  JSFunctionList = openArray[JSCFunctionListEntry]

  BoundFunctionType = enum
    bfFunction = "js_func"
    bfConstructor = "js_ctor"
    bfGetter = "js_get"
    bfSetter = "js_set"
    bfPropertyGetOwn = "js_prop_get_own"
    bfPropertyGet = "js_prop_get"
    bfPropertySet = "js_prop_set"
    bfPropertyDel = "js_prop_del"
    bfPropertyHas = "js_prop_has"
    bfPropertyNames = "js_prop_names"
    bfFinalizer = "js_fin"
    bfMark = "js_mark"

  BoundFunctionFlag = enum
    bffNone, bffUnforgeable, bffStatic, bffReplaceable

  BoundFunction = object
    t: BoundFunctionType
    flag: BoundFunctionFlag
    magic: uint16
    name: string
    id: NimNode

var runtimes {.threadvar.}: seq[JSRuntime]

proc bindCalloc(s: pointer; count, size: csize_t): pointer {.cdecl.} =
  let n = count * size
  if n > size:
    return nil
  return alloc0(count * size)

proc bindMalloc(s: pointer; size: csize_t): pointer {.cdecl.} =
  return alloc(size)

proc bindFree(s: pointer; p: pointer) {.cdecl.} =
  if p != nil:
    dealloc(p)

proc bindRealloc(s: pointer; p: pointer; size: csize_t): pointer {.cdecl.} =
  return realloc(p, size)

proc jsRuntimeCleanUp(rt: JSRuntime) {.cdecl.} =
  let rtOpaque = rt.getOpaque()
  GC_unref(rtOpaque)
  # For refc: ensure there are no ghost Nim objects holding onto JS
  # values.
  try:
    GC_fullCollect()
  except Exception:
    quit(1)
  JS_RunGC(rt)
  assert rtOpaque.destroying == nil
  # Now comes a very elaborate dance to ensure that ordering
  # dependencies are satisfied:
  # * plist must be cleared before finalizers run.
  # * Individual finalizers rely on their opaques being set.
  # * Bound JSValues must not drop to a refcount of 0 before their
  #   opaque is cleared, lest they try to mark related JSValues and/or
  #   claw back their refcount in can_destroy.
  # * Allocations must not occur during deinitialization.
  #
  # For this we need three passes over the object map.  Theoretically,
  # two passes would be enough if move worked reliably across Nim
  # versions.
  var np = 0
  for nimp, jsp in rtOpaque.plist:
    discard JS_DupValueRT(rt, JS_MKPTR(JS_TAG_OBJECT, jsp))
    rtOpaque.tmplist[np] = (nimp, jsp)
    inc np
  rtOpaque.plist.clear()
  for it in rtOpaque.tmplist.toOpenArray(0, np - 1):
    let val = JS_MKPTR(JS_TAG_OBJECT, it.jsp)
    let classid = JS_GetClassID(val)
    let opaque = JS_GetOpaque(val, classid)
    for fin in rtOpaque.finalizers(classid):
      fin(rt, it.nimp)
    if opaque != nil: # JS held a ref to the Nim object.
      JS_SetOpaque(val, nil)
      assert opaque == it.nimp
      rtOpaque.parentMap.withValue(opaque, pp): # var object
        GC_unref(cast[RootRef](pp[]))
      do: # ref object
        GC_unref(cast[RootRef](opaque))
    else: # Nim held a ref to the JS object.
      JS_FreeValueRT(rt, val)
      assert cast[ptr cint](it.jsp)[] >= 0
  # Opaques are unset, and finalizers have run.  Now we can actually
  # release the JS objects.
  for it in rtOpaque.tmplist.toOpenArray(0, np - 1):
    JS_FreeValueRT(rt, JS_MKPTR(JS_TAG_OBJECT, it.jsp))
  # GC will run again now (in QJS code).

proc newJSRuntime*(): JSRuntime =
  ## Instantiate a Monoucha `JSRuntime`.
  var mf {.global.} = JSMallocFunctions(
    js_calloc: bindCalloc,
    js_malloc: bindMalloc,
    js_free: bindFree,
    js_realloc: bindRealloc,
    js_malloc_usable_size: nil
  )
  let rt = JS_NewRuntime2(addr mf, nil)
  let opaque = JSRuntimeOpaque()
  GC_ref(opaque)
  JS_SetRuntimeOpaque(rt, cast[pointer](opaque))
  JS_SetRuntimeCleanUpFunc(rt, jsRuntimeCleanUp)
  # Must be added after opaque is set, or there is a chance of
  # nim_finalize_for_js dereferencing it (at the new call).
  runtimes.add(rt)
  return rt

proc newJSContext*(rt: JSRuntime): JSContext =
  ## Instantiate a Monoucha `JSContext`.
  ## It is only valid to call Monoucha procedures on contexts initialized with
  ## `newJSContext`, as it does extra initialization over `JS_NewContext`.
  let ctx = JS_NewContext(rt)
  let opaque = newJSContextOpaque(ctx)
  GC_ref(opaque)
  JS_SetContextOpaque(ctx, cast[pointer](opaque))
  return ctx

proc free*(ctx: JSContext) =
  ## Free the JSContext and associated resources.
  ## Note: this is not an alias of `JS_FreeContext`; `free` also frees various
  ## JSValues stored on context startup by `newJSContext`.
  var opaque = ctx.getOpaque()
  if opaque != nil:
    for a in opaque.symRefs:
      JS_FreeAtom(ctx, a)
    for a in opaque.strRefs:
      JS_FreeAtom(ctx, a)
    for v in opaque.valRefs:
      JS_FreeValue(ctx, v)
    for data in opaque.classes:
      JS_FreeValue(ctx, data.ctor)
    for e, v in opaque.errCtorRefs:
      if e != jeCustom:
        JS_FreeValue(ctx, v)
    if opaque.globalObj != nil:
      let rt = JS_GetRuntime(ctx)
      let rtOpaque = rt.getOpaque()
      for fin in rtOpaque.finalizers(opaque.gclass):
        fin(rt, cast[pointer](opaque.globalObj))
      GC_unref(cast[RootRef](opaque.globalObj))
      rtOpaque.plist.del(opaque.globalObj)
    JS_FreeValue(ctx, opaque.global)
    GC_unref(opaque)
  JS_FreeContext(ctx)

proc free*(rt: JSRuntime) =
  ## Free the `JSRuntime` rt and remove it from the global JSRuntime pool.
  #
  # We must prepare space for opaque refs & pointers here, so that we
  # can avoid allocations during cleanup. Otherwise we risk triggering a
  # GC cycle and that would break cleanup too...
  #
  # (But we must *not* collect them yet; wait until the cycles are
  # collected once.)
  let rtOpaque = rt.getOpaque()
  rtOpaque.tmplist.setLen(rtOpaque.plist.len)
  JS_FreeRuntime(rt)
  runtimes.del(runtimes.find(rt))

proc setGlobal*[T](ctx: JSContext; obj: T) =
  ## Set the global variable to the reference `obj`.
  ## Note: you must call `ctx.registerType(T, asglobal = true)` for this to
  ## work, `T` being the type of `obj`.
  # Add JSValue reference.
  let rt = JS_GetRuntime(ctx)
  let rtOpaque = rt.getOpaque()
  let ctxOpaque = ctx.getOpaque()
  let opaque = cast[pointer](obj)
  rtOpaque.plist[opaque] = JS_VALUE_GET_PTR(ctxOpaque.global)
  JS_SetOpaque(ctxOpaque.global, opaque)
  GC_ref(obj)
  ctxOpaque.globalObj = opaque

proc getExceptionMsg*(ctx: JSContext): string =
  result = ""
  let ex = JS_GetException(ctx)
  if fromJS(ctx, ex, result).isOk:
    result &= '\n'
  let stack = JS_GetPropertyStr(ctx, ex, cstring("stack"));
  var s: string
  if not JS_IsUndefined(stack) and ctx.fromJS(stack, s).isOk:
    result &= s
  JS_FreeValue(ctx, stack)
  JS_FreeValue(ctx, ex)

# Returns early with err(JSContext) if an exception was thrown in a
# context.
proc runJSJobs*(rt: JSRuntime): Result[void, JSContext] =
  while JS_IsJobPending(rt):
    var ctx: JSContext
    let r = JS_ExecutePendingJob(rt, ctx)
    if r == -1:
      return err(ctx)
  ok()

# Add all LegacyUnforgeable functions defined on the prototype chain to
# the opaque.
# Since every prototype has a list of all its ancestor's LegacyUnforgeable
# functions, it is sufficient to simply merge the new list of new classes
# with their parent's list to achieve this.
# We handle finalizers similarly.
proc addClassUnforgeableAndFinalizer(ctx: JSContext; proto: JSValueConst;
    classid, parent: JSClassID; ourUnforgeable: JSFunctionList;
    finalizer: JSFinalizerFunction) =
  let ctxOpaque = ctx.getOpaque()
  var merged = @ourUnforgeable
  if int(parent) < ctxOpaque.classes.len:
    merged.add(ctxOpaque.classes[int(parent)].unforgeable)
  if merged.len > 0:
    ctxOpaque.classes[int(classid)].unforgeable = move(merged)
    let ufp0 = addr ctxOpaque.classes[int(classid)].unforgeable[0]
    let ufp = cast[ptr UncheckedArray[JSCFunctionListEntry]](ufp0)
    JS_SetPropertyFunctionList(ctx, proto, ufp, cint(merged.len))
  var fins: seq[JSFinalizerFunction] = @[]
  if finalizer != nil:
    fins.add(finalizer)
  let rtOpaque = JS_GetRuntime(ctx).getOpaque()
  if int(parent) < rtOpaque.fins.len:
    fins.add(rtOpaque.fins[int(parent)])
  if fins.len > 0:
    if rtOpaque.fins.len <= int(classid):
      rtOpaque.fins.setLen(classid + 1)
    rtOpaque.fins[classid] = move(fins)

proc newProtoFromParentClass(ctx: JSContext; parent: JSClassID): JSValue =
  if parent != 0:
    let parentProto = JS_GetClassProto(ctx, parent)
    let proto = JS_NewObjectProtoClass(ctx, parentProto, parent)
    JS_FreeValue(ctx, parentProto)
    return proto
  return JS_NewObject(ctx)

proc newCtorFunFromParentClass(ctx: JSContext; ctor: JSCFunction;
    className: cstring; parent: JSClassID): JSValue =
  if parent != 0:
    return JS_NewCFunction3(ctx, ctor, className, 0, JS_CFUNC_constructor,
      0, ctx.getOpaque().classes[int(parent)].ctor)
  return JS_NewCFunction2(ctx, ctor, className, 0, JS_CFUNC_constructor, 0)

proc newJSClass*(ctx: JSContext; cdef: JSClassDefConst; nimt: pointer;
    ctor: JSCFunction; funcs: JSFunctionList; parent: JSClassID;
    asglobal, nointerface: bool; finalizer: JSFinalizerFunction;
    namespace: JSValueConst; unforgeable, staticfuns: JSFunctionList): JSClassID
    {.discardable.} =
  result = 0
  let rt = JS_GetRuntime(ctx)
  discard JS_NewClassID(rt, result)
  let ctxOpaque = ctx.getOpaque()
  let rtOpaque = rt.getOpaque()
  if JS_NewClass(rt, result, cdef) != 0:
    raise newException(Defect, "Failed to allocate JS class: " &
      $cdef.class_name)
  rtOpaque.typemap[nimt] = result
  if ctxOpaque.classes.len <= int(result):
    ctxOpaque.classes.setLen(int(result) + 1)
  ctxOpaque.classes[result].parent = parent
  let proto = ctx.newProtoFromParentClass(parent)
  if funcs.len > 0:
    let fp = cast[ptr UncheckedArray[JSCFunctionListEntry]](unsafeAddr funcs[0])
    JS_SetPropertyFunctionList(ctx, proto, fp, cint(funcs.len))
  #TODO check if this is an indexed property getter
  if cdef.exotic != nil and cdef.exotic.get_own_property != nil:
    let val = JS_DupValue(ctx, ctxOpaque.valRefs[jsvArrayPrototypeValues])
    let itSym = ctxOpaque.symRefs[jsyIterator]
    doAssert ctx.defineProperty(proto, itSym, val) == dprSuccess
  let news = JS_NewAtomString(ctx, cdef.class_name)
  doAssert not JS_IsException(news)
  doAssert ctx.definePropertyC(proto, ctxOpaque.symRefs[jsyToStringTag],
    JS_DupValue(ctx, news)) == dprSuccess
  JS_SetClassProto(ctx, result, proto)
  ctx.addClassUnforgeableAndFinalizer(proto, result, parent, unforgeable,
    finalizer)
  if asglobal:
    let global = ctxOpaque.global
    assert ctxOpaque.gclass == 0
    ctxOpaque.gclass = result
    doAssert ctx.definePropertyC(global, ctxOpaque.symRefs[jsyToStringTag],
      JS_DupValue(ctx, news)) == dprSuccess
    if JS_SetPrototype(ctx, global, proto) != 1:
      raise newException(Defect, "Failed to set global prototype: " &
        $cdef.class_name)
    # Global already exists, so set unforgeable functions here
    if ctxOpaque.classes[int(result)].unforgeable.len > 0:
      let ufp0 = addr ctxOpaque.classes[int(result)].unforgeable[0]
      let ufp = cast[ptr UncheckedArray[JSCFunctionListEntry]](ufp0)
      JS_SetPropertyFunctionList(ctx, global, ufp,
        cint(ctxOpaque.classes[int(result)].unforgeable.len))
  JS_FreeValue(ctx, news)
  let jctor = ctx.newCtorFunFromParentClass(ctor, cdef.class_name, parent)
  if staticfuns.len > 0:
    let fp0 = unsafeAddr staticfuns[0]
    let fp = cast[ptr UncheckedArray[JSCFunctionListEntry]](fp0)
    JS_SetPropertyFunctionList(ctx, jctor, fp, cint(staticfuns.len))
  JS_SetConstructor(ctx, jctor, proto)
  ctxOpaque.classes[result].ctor = JS_DupValue(ctx, jctor)
  if not nointerface:
    let target = if JS_IsNull(namespace):
      JSValueConst(ctxOpaque.global)
    else:
      namespace
    doAssert JS_DefinePropertyValueStr(ctx, target, cdef.class_name, jctor,
      JS_PROP_CONFIGURABLE or JS_PROP_WRITABLE) == 1
  else:
    JS_FreeValue(ctx, jctor)

type
  FuncParam = tuple
    t: NimNode
    val: NimNode # may be nil

  JSFuncGenerator = object
    t: BoundFunctionType
    hasThis: bool
    flag: BoundFunctionFlag
    funcName: string
    funcParams: seq[FuncParam]
    thisType: string
    thisTypeNode: NimNode
    returnType: NimNode # may be nil
    newName: NimNode
    dielabel: NimNode # die: jump to exception return code (JS_EXCEPTION or -1)
    jsFunCallList: NimNode
    jsFunCall: NimNode
    jsCallAndRet: NimNode
    minArgs: cint
    actualMinArgs: cint # minArgs without JSContext
    i: cint # nim parameters accounted for
    j: cint # js parameters accounted for (not including fix ones, e.g. `this')

  RegistryInfo = ref object
    t: NimNode # NimNode of type
    name: string # JS name, if this is the empty string then it equals tname
    tabFuns: NimNode # array of function table
    tabUnforgeable: NimNode # array of unforgeable function table
    tabStatic: NimNode # array of static function table
    ctorFun: NimNode # constructor ident
    getset: Table[string, (NimNode, NimNode, BoundFunctionFlag)] # name -> value
    propGetOwnFun: NimNode # custom own get function ident
    propGetFun: NimNode # custom get function ident
    propSetFun: NimNode # custom set function ident
    propDelFun: NimNode # custom del function ident
    propHasFun: NimNode # custom has function ident
    propNamesFun: NimNode # custom property names function ident
    finFun: NimNode # finalizer wrapper ident
    dfin: NimNode # CheckDestroy finalizer ident
    replaceableSetFun: NimNode # replaceable setter function ident
    tabReplaceableNames: NimNode # replaceable names array
    markFun: NimNode # gc_mark for class

var BoundFunctions {.compileTime.}: Table[string, RegistryInfo]

proc newRegistryInfo(t: NimNode): RegistryInfo =
  return RegistryInfo(
    t: t,
    name: t.strVal,
    tabFuns: newNimNode(nnkBracket),
    tabUnforgeable: newNimNode(nnkBracket),
    tabStatic: newNimNode(nnkBracket),
    tabReplaceableNames: newNimNode(nnkBracket),
    finFun: newNilLit(),
    propGetOwnFun: newNilLit(),
    propGetFun: newNilLit(),
    propSetFun: newNilLit(),
    propDelFun: newNilLit(),
    propHasFun: newNilLit(),
    propNamesFun: newNilLit(),
    markFun: newNilLit()
  )

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
      if val.kind == nnkEmpty:
        error("?? " & treeRepr(val))
      t = quote do:
        typeof(`val`)
    of nnkVarTy:
      t = newNimNode(nnkPtrTy).add(t[0])
    of nnkCommand, nnkCall:
      if t.len == 2 and t[0].eqIdent("sink"):
        t = t[1]
    of nnkBracketExpr:
      if t.typeKind == ntyVarargs:
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
  gen.actualMinArgs = gen.minArgs
  if gen.hasThis and gen.flag != bffStatic:
    dec gen.actualMinArgs
  if gen.funcParams.len > gen.i:
    if gen.funcParams[gen.i].t.eqIdent("JSContext"):
      dec gen.actualMinArgs
      gen.jsFunCall.add(ident("ctx"))
      inc gen.i
    elif gen.funcParams[gen.i].t.eqIdent("JSRuntime"):
      inc gen.i # special case for finalizers that have a JSRuntime param
  assert gen.actualMinArgs >= 0

template getJSParams(): untyped =
  [
    (quote do: JSValue),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("this"), quote do: JSValueConst),
    newIdentDefs(ident("argc"), quote do: cint),
    newIdentDefs(ident("argv"), quote do: JSValueConstArray)
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

template getJSPropNamesParams(): untyped =
  [
    (quote do: cint),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("ptab"), quote do: ptr JSPropertyEnumArray),
    newIdentDefs(ident("plen"), quote do: ptr uint32),
    newIdentDefs(ident("this"), quote do: JSValueConst)
  ]

proc addParam(gen: var JSFuncGenerator; s, t, val: NimNode;
    fallback: NimNode = nil) =
  if t.typeKind == ntyGenericParam:
    error("Union parameters are no longer supported. Use JSValue instead.")
  let dl = gen.dielabel
  if fallback == nil:
    gen.jsFunCallList.add(quote do:
      var `s`: `t`
      if ctx.fromJS(`val`, `s`).isErr:
        break `dl`
    )
  else:
    let j = gen.j
    gen.jsFunCallList.add(quote do:
      var `s`: `t`
      if `j` < argc and not JS_IsUndefined(argv[`j`]):
        if ctx.fromJS(`val`, `s`).isErr:
          break `dl`
      else:
        `s` = `fallback`
    )

proc addValueParam(gen: var JSFuncGenerator; s, t: NimNode;
    fallback: NimNode = nil) =
  let j = gen.j
  gen.addParam(s, t, quote do: argv[`j`], fallback)

proc addThisParam(gen: var JSFuncGenerator; thisName = "this") =
  var s = ident("arg_" & $gen.i)
  let t = gen.funcParams[gen.i].t
  let id = ident(thisName)
  let dl = gen.dielabel
  gen.jsFunCallList.add(quote do:
    var `s`: `t`
    if ctx.fromJSThis(`id`, `s`).isErr:
      break `dl`
  )
  if gen.funcParams[gen.i].t.kind == nnkPtrTy:
    s = quote do: `s`[]
  gen.jsFunCall.add(s)
  inc gen.i

proc addFixParam(gen: var JSFuncGenerator; name: string) =
  var s = ident("arg_" & $gen.i)
  let t = gen.funcParams[gen.i].t
  let id = ident(name)
  gen.addParam(s, t, id)
  if gen.funcParams[gen.i].t.kind == nnkPtrTy:
    s = quote do: `s`[]
  gen.jsFunCall.add(s)
  inc gen.i

proc addRequiredParams(gen: var JSFuncGenerator) =
  while gen.i < gen.minArgs:
    var s = ident("arg_" & $gen.i)
    let tt = gen.funcParams[gen.i].t
    gen.addValueParam(s, tt)
    if gen.funcParams[gen.i].t.kind == nnkPtrTy:
      s = quote do: `s`[]
    gen.jsFunCall.add(s)
    inc gen.j
    inc gen.i

proc addOptionalParams(gen: var JSFuncGenerator) =
  while gen.i < gen.funcParams.len:
    let j = gen.j
    var s = ident("arg_" & $gen.i)
    let tt = gen.funcParams[gen.i].t
    if tt.typeKind == ntyVarargs:
      let vt = tt[1]
      if vt.sameType(JSValueConst.getType()) or
          JSValueConst.getType().sameType(vt):
        s = quote do:
          argv.toOpenArray(`j`, argc - 1)
      else:
        error("Only JSValueConst varargs are supported")
    else:
      let fallback = gen.funcParams[gen.i].val
      if fallback == nil:
        error("No fallback value. Maybe a non-optional parameter follows an " &
          "optional parameter?")
      gen.addValueParam(s, tt, fallback)
    if gen.funcParams[gen.i].t.kind == nnkPtrTy:
      s = quote do: `s`[]
    gen.jsFunCall.add(s)
    inc gen.j
    inc gen.i

proc finishFunCallList(gen: var JSFuncGenerator) =
  gen.jsFunCallList.add(gen.jsFunCall)

var jsDtors {.compileTime.}: HashSet[string]

proc registerFunction(info: RegistryInfo; fun: BoundFunction) =
  let name = fun.name
  let id = fun.id
  case fun.t
  of bfFunction:
    case fun.flag
    of bffNone:
      info.tabFuns.add(quote do:
        JS_CFUNC_DEF(`name`, 0, cast[JSCFunction](`id`)))
    of bffUnforgeable:
      info.tabUnforgeable.add(quote do:
        JS_CFUNC_DEF_NOCONF(`name`, 0, cast[JSCFunction](`id`)))
    of bffStatic:
      info.tabStatic.add(quote do:
        JS_CFUNC_DEF(`name`, 0, cast[JSCFunction](`id`)))
    of bffReplaceable:
      assert false #TODO
  of bfConstructor:
    if info.ctorFun != nil:
      error("Class " & info.name & " has 2+ constructors.")
    info.ctorFun = id
  of bfGetter:
    info.getset.withValue(name, exv):
      exv[0] = id
      exv[2] = fun.flag
    do:
      info.getset[name] = (id, newNilLit(), fun.flag)
      if fun.flag == bffReplaceable:
        info.tabReplaceableNames.add(newCall("cstring", newStrLitNode(name)))
  of bfSetter:
    info.getset.withValue(name, exv):
      exv[1] = id
    do:
      info.getset[name] = (newNilLit(), id, bffNone)
  of bfPropertyGetOwn:
    if info.propGetFun.kind != nnkNilLit:
      error("Class " & info.name & " has 2+ own property getters.")
    info.propGetOwnFun = id
  of bfPropertyGet:
    if info.propGetFun.kind != nnkNilLit:
      error("Class " & info.name & " has 2+ property getters.")
    info.propGetFun = id
  of bfPropertySet:
    if info.propSetFun.kind != nnkNilLit:
      error("Class " & info.name & " has 2+ property setters.")
    info.propSetFun = id
  of bfPropertyDel:
    if info.propDelFun.kind != nnkNilLit:
      error("Class " & info.name & " has 2+ property deleters.")
    info.propDelFun = id
  of bfPropertyHas:
    if info.propHasFun.kind != nnkNilLit:
      error("Class " & info.name & " has 2+ hasprop getters.")
    info.propHasFun = id
  of bfPropertyNames:
    if info.propNamesFun.kind != nnkNilLit:
      error("Class " & info.name & " has 2+ propnames getters.")
    info.propNamesFun = id
  of bfFinalizer:
    if info.finFun.kind != nnkNilLit:
      error("Class " & info.name & " has 2+ finalizers.")
    info.finFun = id
  of bfMark:
    if info.markFun.kind != nnkNilLit:
      error("Class " & info.name & " has 2+ mark functions.")
    info.markFun = id

proc registerFunction(typ: string; fun: BoundFunction) =
  var info = BoundFunctions.getOrDefault(typ)
  if info == nil:
    info = newRegistryInfo(ident(typ))
    BoundFunctions[typ] = info
  info.registerFunction(fun)

proc registerFunction(gen: JSFuncGenerator) =
  registerFunction(gen.thisType, BoundFunction(
    t: gen.t,
    name: gen.funcName,
    id: gen.newName,
    flag: gen.flag
  ))

proc jsCheckNumArgs(ctx: JSContext; argc, minargs: cint): bool =
  if argc < minargs:
    JS_ThrowTypeError(ctx, "At least %d arguments required, but only %d passed",
      minargs, argc)
    return false
  true

proc newJSProc(gen: var JSFuncGenerator; params: openArray[NimNode];
    isva = true): NimNode =
  let ma = gen.actualMinArgs
  let jsBody = newStmtList()
  if isva and ma > 0:
    jsBody.add(quote do:
      if not ctx.jsCheckNumArgs(argc, `ma`):
        return JS_EXCEPTION
    )
  jsBody.add(gen.jsCallAndRet)
  let jsPragmas = newNimNode(nnkPragma)
    .add(ident("cdecl"))
    .add(newTree(nnkExprColonExpr, ident("raises"), newNimNode(nnkBracket)))
  return newProc(gen.newName, params, jsBody, pragmas = jsPragmas)

proc getFuncName(fun: NimNode; jsname, staticName: string): string =
  if jsname != "":
    return jsname
  if staticName != "":
    let i = staticName.find('.')
    if i != -1:
      return staticName.substr(i + 1)
  return $fun[0]

proc addThisName(gen: var JSFuncGenerator; hasThis: bool) =
  if hasThis:
    var t = gen.funcParams[gen.i].t
    if t.kind in {nnkPtrTy, nnkRefTy}:
      t = t[0]
    gen.thisTypeNode = t
    gen.thisType = $t
    gen.newName = ident($gen.t & "_" & gen.thisType & "_" & gen.funcName)
  else:
    let rt = gen.returnType
    if rt.kind in {nnkRefTy, nnkPtrTy}:
      gen.thisTypeNode = rt[0]
      gen.thisType = rt[0].strVal
    else:
      if rt.kind == nnkBracketExpr:
        gen.thisTypeNode = rt[1]
        gen.thisType = rt[1].strVal
      else:
        gen.thisTypeNode = rt
        gen.thisType = rt.strVal
    gen.newName = ident($gen.t & "_" & gen.funcName)

proc initGenerator(fun: NimNode; t: BoundFunctionType; hasThis: bool;
    jsname = ""; flag = bffNone; staticName = ""): JSFuncGenerator =
  result = JSFuncGenerator(
    t: t,
    funcName: getFuncName(fun, jsname, staticName),
    hasThis: hasThis,
    dielabel: ident("ondie"),
    jsFunCallList: newStmtList(),
    jsFunCall: newCall(fun[0]),
    flag: flag
  )
  result.readParams(fun)
  if staticName == "":
    result.addThisName(hasThis)
  else:
    result.thisType = staticName
    if (let i = result.thisType.find('.'); i != -1):
      result.thisType.setLen(i)
    result.newName = ident($result.t & "_" & result.funcName)

proc makeJSCallAndRet(gen: var JSFuncGenerator; okstmt, errstmt: NimNode) =
  let jfcl = gen.jsFunCallList
  let dl = gen.dielabel
  gen.jsCallAndRet = if gen.returnType != nil:
    quote do:
      block `dl`:
        return ctx.toJS(`jfcl`)
      `errstmt`
  else:
    quote do:
      block `dl`:
        `jfcl`
        `okstmt`
      `errstmt`

macro jsctor*(fun: typed) =
  var gen = initGenerator(fun, bfConstructor, hasThis = false)
  gen.addRequiredParams()
  gen.addOptionalParams()
  gen.finishFunCallList()
  let jfcl = gen.jsFunCallList
  let dl = gen.dielabel
  gen.jsCallAndRet = quote do:
    block `dl`:
      return ctx.toJSNew(`jfcl`, this)
    return JS_EXCEPTION
  let jsProc = gen.newJSProc(getJSParams())
  gen.registerFunction()
  return newStmtList(fun, jsProc)

macro jshasprop*(fun: typed) =
  var gen = initGenerator(fun, bfPropertyHas, hasThis = true)
  gen.addThisParam()
  gen.addFixParam("atom")
  gen.finishFunCallList()
  let jfcl = gen.jsFunCallList
  let dl = gen.dielabel
  gen.jsCallAndRet = quote do:
    block `dl`:
      let retv = `jfcl`
      return cint(retv)
    return cint(-1)
  let jsProc = gen.newJSProc(getJSHasPropParams(), false)
  gen.registerFunction()
  return newStmtList(fun, jsProc)

macro jsgetownprop*(fun: typed) =
  var gen = initGenerator(fun, bfPropertyGetOwn, hasThis = true)
  gen.addThisParam()
  gen.addFixParam("prop")
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
  gen.finishFunCallList()
  let jfcl = gen.jsFunCallList
  let dl = gen.dielabel
  gen.jsCallAndRet = quote do:
    block `dl`:
      if JS_GetOpaque(this, JS_GetClassID(this)) == nil:
        return cint(0)
      let retv {.inject.} = ctx.toJS(`jfcl`)
      if JS_IsException(retv):
        return cint(-1)
      if JS_IsUninitialized(retv):
        return cint(0)
      `handleRetv`
      return cint(1)
    return cint(-1)
  let jsProc = gen.newJSProc(getJSGetOwnPropParams(), false)
  gen.registerFunction()
  return newStmtList(fun, jsProc)

macro jsgetprop*(fun: typed) =
  var gen = initGenerator(fun, bfPropertyGet, hasThis = true)
  gen.addThisParam("receiver")
  gen.addFixParam("prop")
  if gen.i < gen.funcParams.len:
    gen.addFixParam("this")
  gen.finishFunCallList()
  let jfcl = gen.jsFunCallList
  let dl = gen.dielabel
  gen.jsCallAndRet = quote do:
    block `dl`:
      return ctx.toJS(`jfcl`)
    return JS_EXCEPTION
  let jsProc = gen.newJSProc(getJSGetPropParams(), false)
  gen.registerFunction()
  return newStmtList(fun, jsProc)

macro jssetprop*(fun: typed) =
  var gen = initGenerator(fun, bfPropertySet, hasThis = true)
  gen.addThisParam("receiver")
  gen.addFixParam("atom")
  gen.addFixParam("value")
  if gen.i < gen.funcParams.len:
    gen.addFixParam("this")
  gen.finishFunCallList()
  let jfcl = gen.jsFunCallList
  let dl = gen.dielabel
  gen.jsCallAndRet = if gen.returnType != nil:
    quote do:
      block `dl`:
        let v = toJS(ctx, `jfcl`)
        if not JS_IsException(v):
          return cint(1)
        if JS_IsUninitialized(v):
          return cint(0)
      return cint(-1)
  else:
    quote do:
      block `dl`:
        `jfcl`
        return cint(1)
      return cint(-1)
  let jsProc = gen.newJSProc(getJSSetPropParams(), false)
  gen.registerFunction()
  return newStmtList(fun, jsProc)

macro jsdelprop*(fun: typed) =
  var gen = initGenerator(fun, bfPropertyDel, hasThis = true)
  gen.addThisParam()
  gen.addFixParam("prop")
  gen.finishFunCallList()
  let jfcl = gen.jsFunCallList
  let dl = gen.dielabel
  gen.jsCallAndRet = quote do:
    block `dl`:
      let retv = `jfcl`
      return cint(retv)
    return cint(-1)
  let jsProc = gen.newJSProc(getJSDelPropParams(), false)
  gen.registerFunction()
  return newStmtList(fun, jsProc)

macro jspropnames*(fun: typed) =
  var gen = initGenerator(fun, bfPropertyNames, hasThis = true)
  gen.addThisParam()
  gen.finishFunCallList()
  let jfcl = gen.jsFunCallList
  let dl = gen.dielabel
  gen.jsCallAndRet = quote do:
    block `dl`:
      let retv = `jfcl`
      ptab[] = retv.buffer
      plen[] = retv.len
      return cint(0)
    return cint(-1)
  let jsProc = gen.newJSProc(getJSPropNamesParams(), false)
  gen.registerFunction()
  return newStmtList(fun, jsProc)

macro jsfgetn(jsname: static string; flag: static BoundFunctionFlag;
    fun: typed) =
  var gen = initGenerator(fun, bfGetter, hasThis = true, jsname, flag)
  if gen.actualMinArgs != 0 or gen.funcParams.len != gen.minArgs:
    error("jsfget functions must only accept one parameter.")
  if gen.returnType == nil:
    error("jsfget functions must have a return type.")
  gen.addThisParam()
  gen.finishFunCallList()
  gen.makeJSCallAndRet(nil, quote do: discard)
  let jsProc = if flag != bffReplaceable:
    gen.newJSProc(getJSGetterParams(), false)
  else:
    gen.newJSProc(getJSMagicGetterParams(), false)
  gen.registerFunction()
  return newStmtList(fun, jsProc)

# "Why?" So the compiler doesn't cry.
# Warning: make these typed and you will cry instead.
template jsfget*(fun: untyped) =
  jsfgetn("", bffNone, fun)

template jsuffget*(fun: untyped) =
  jsfgetn("", bffUnforgeable, fun)

template jsrfget*(fun: untyped) =
  jsfgetn("", bffReplaceable, fun)

template jsfget*(jsname, fun: untyped) =
  jsfgetn(jsname, bffNone, fun)

template jsuffget*(jsname, fun: untyped) =
  jsfgetn(jsname, bffUnforgeable, fun)

template jsrfget*(jsname, fun: untyped) =
  jsfgetn(jsname, bffReplaceable, fun)

# Ideally we could simulate JS setters using nim setters, but nim setters
# won't accept types that don't match their reflected field's type.
macro jsfsetn(jsname: static string; fun: typed) =
  var gen = initGenerator(fun, bfSetter, hasThis = true, jsname = jsname)
  if gen.actualMinArgs != 1 or gen.funcParams.len != gen.minArgs:
    error("jsfset functions must accept two parameters")
  #TODO should check if result is JSResult[void]
  gen.addThisParam()
  gen.addFixParam("val")
  gen.finishFunCallList()
  # return param anyway
  let okstmt = quote do: discard
  let errstmt = quote do: return JS_DupValue(ctx, val)
  gen.makeJSCallAndRet(okstmt, errstmt)
  let jsProc = gen.newJSProc(getJSSetterParams(), false)
  gen.registerFunction()
  return newStmtList(fun, jsProc)

template jsfset*(fun: untyped) =
  jsfsetn("", fun)

template jsfset*(jsname, fun: untyped) =
  jsfsetn(jsname, fun)

macro jsfuncn*(jsname: static string; flag: static BoundFunctionFlag;
    staticName: static string; fun: typed) =
  var gen = initGenerator(fun, bfFunction, hasThis = true, jsname = jsname,
    flag = flag, staticName = staticName)
  if gen.minArgs == 0 and gen.flag != bffStatic:
    #TODO this should work, especially with JSContext.
    error("Zero-parameter functions are not supported. " &
      "(Maybe pass Window or Client?)")
  if gen.flag != bffStatic:
    gen.addThisParam()
  gen.addRequiredParams()
  gen.addOptionalParams()
  gen.finishFunCallList()
  let okstmt = quote do:
    return JS_UNDEFINED
  let errstmt = quote do:
    return JS_EXCEPTION
  gen.makeJSCallAndRet(okstmt, errstmt)
  let jsProc = gen.newJSProc(getJSParams())
  gen.registerFunction()
  return newStmtList(fun, jsProc)

template jsfunc*(fun: untyped) =
  jsfuncn("", bffNone, "", fun)

template jsuffunc*(fun: untyped) =
  jsfuncn("", bffUnforgeable, "", fun)

template jsfunc*(jsname, fun: untyped) =
  jsfuncn(jsname, bffNone, "", fun)

template jsuffunc*(jsname, fun: untyped) =
  jsfuncn(jsname, bffUnforgeable, "", fun)

template jsstfunc*(name, fun: untyped) =
  jsfuncn("", bffStatic, name, fun)

macro jsfin*(fun: typed) =
  var gen = initGenerator(fun, bfFinalizer, hasThis = true)
  let finName = gen.newName
  let finFun = ident(gen.funcName)
  let t = gen.thisTypeNode
  var finStmt: NimNode = nil # warning: won't compile on 2.0.4 with let
  if gen.minArgs == 1:
    finStmt = quote do: `finFun`(cast[`t`](opaque))
  elif gen.minArgs == 2:
    finStmt = quote do: `finFun`(rt, cast[`t`](opaque))
  else:
    error("Expected one or two parameters")
  let jsProc = quote do:
    proc `finName`(rt {.inject.}: JSRuntime; opaque {.inject.}: pointer) =
      `finStmt`
  gen.registerFunction()
  return newStmtList(fun, jsProc)

macro jsmark*(fun: typed) =
  var gen = initGenerator(fun, bfMark, hasThis = true)
  let markName = gen.newName
  let markFun = ident(gen.funcName)
  let t = gen.thisTypeNode
  let jsProc = quote do:
    proc `markName`(rt {.inject.}: JSRuntime; val: JSValueConst;
        markFunc {.inject.}: JS_MarkFunc) {.cdecl.} =
      let opaque = JS_GetOpaque(val, JS_GetClassID(val))
      if opaque != nil:
        `markFun`(rt, cast[`t`](opaque), markFunc)
  gen.registerFunction()
  return newStmtList(fun, jsProc)

# Having the same names for these and the macros leads to weird bugs, so the
# macros get an additional f.
template jsget*() {.pragma.}
template jsget*(name: string) {.pragma.}
template jsset*() {.pragma.}
template jsset*(name: string) {.pragma.}
template jsgetset*() {.pragma.}
template jsgetset*(name: string) {.pragma.}
template jsufget*() {.pragma.}
template jsufget*(name: string) {.pragma.}
template jsrget*() {.pragma.}
template jsrget*(name: string) {.pragma.}

proc js_illegal_ctor*(ctx: JSContext; this: JSValueConst; argc: cint;
    argv: JSValueConstArray): JSValue {.cdecl.} =
  return JS_ThrowTypeError(ctx, "Illegal constructor")

type
  JSObjectPragma = object
    name: string
    varsym: NimNode
    flag: BoundFunctionFlag

proc getPragmaName(varPragma: NimNode): string =
  if varPragma.kind == nnkExprColonExpr:
    return $varPragma[0]
  return $varPragma

proc getStringFromPragma(varPragma, fallback: NimNode): string =
  if varPragma.kind == nnkExprColonExpr:
    if not varPragma.len == 1 and varPragma[1].kind == nnkStrLit:
      error("Expected string as pragma argument")
    return $varPragma[1]
  return $fallback

proc tname(info: RegistryInfo): string =
  return info.t.strVal

# Differs from tname if the Nim object's name differs from the JS object's
# name.
proc jsname(info: RegistryInfo): string =
  if info.name != "":
    return info.name
  return info.tname

proc registerGetter(stmts: NimNode; info: RegistryInfo; op: JSObjectPragma) =
  let t = info.t
  let tname = info.tname
  let node = op.varsym
  let fn = op.name
  let id = ident($bfGetter & "_" & tname & "_" & fn)
  stmts.add(quote do:
    proc `id`(ctx: JSContext; this: JSValueConst): JSValue {.cdecl.} =
      when `t` is object:
        var arg_0 {.noinit.}: ptr `t`
      else:
        var arg_0: `t`
      if ctx.fromJSThis(this, arg_0).isErr:
        return JS_EXCEPTION
      when arg0.`node` is JSValue:
        return JS_DupValue(ctx, arg0.`node`)
      elif arg_0.`node` is object:
        return ctx.toJSP(arg_0, arg_0.`node`)
      else:
        return ctx.toJS(arg_0.`node`)
  )
  info.registerFunction(BoundFunction(
    t: bfGetter,
    name: fn,
    id: id,
    flag: op.flag
  ))

proc registerSetter(stmts: NimNode; info: RegistryInfo; op: JSObjectPragma) =
  let t = info.t
  let tname = info.tname
  let node = op.varsym
  let fn = op.name
  let id = ident($bfSetter & "_" & tname & "_" & fn)
  stmts.add(quote do:
    proc `id`(ctx: JSContext; this, val: JSValueConst): JSValue {.cdecl.} =
      when `t` is object:
        var arg_0 {.noinit.}: ptr `t`
      else:
        var arg_0: `t`
      if ctx.fromJSThis(this, arg_0).isErr:
        return JS_EXCEPTION
      # We can't just set arg_0.`node` directly, or fromJS may damage it.
      var nodeVal: typeof(arg_0.`node`)
      when nodeVal is JSValue:
        static:
          error(".jsset is not supported on JSValue; use jsfset")
      else:
        if ctx.fromJS(val, nodeVal).isErr:
          return JS_EXCEPTION
      arg_0.`node` = move(nodeVal)
      return JS_DupValue(ctx, val)
  )
  info.registerFunction(BoundFunction(t: bfSetter, name: fn, id: id))

proc registerPragmas(stmts: NimNode; info: RegistryInfo; t: NimNode) =
  let typ = t.getTypeInst()[1] # The type, as declared.
  var impl = typ.getTypeImpl() # ref t
  if impl.kind in {nnkRefTy, nnkPtrTy}:
    impl = impl[0].getImpl()
  else:
    impl = typ.getImpl()
  # stolen from std's macros.customPragmaNode
  var identDefsStack = newSeq[NimNode](impl[2].len)
  for i, it in identDefsStack.mpairs:
    it = impl[2][i]
  while identDefsStack.len > 0:
    let identDefs = identDefsStack.pop()
    case identDefs.kind
    of nnkRecList:
      for child in identDefs.children:
        identDefsStack.add(child)
    of nnkRecCase:
      discard # case objects are not supported
    else:
      for i in 0 ..< identDefs.len - 2:
        var varNode = identDefs[i]
        if varNode.kind == nnkPragmaExpr:
          let varPragmas = varNode[1]
          varNode = varNode[0]
          if varNode.kind == nnkPostfix:
            varNode = varNode[1]
          for varPragma in varPragmas:
            let pragmaName = getPragmaName(varPragma)
            var op = JSObjectPragma(
              name: getStringFromPragma(varPragma, varNode),
              varsym: varNode
            )
            case pragmaName
            of "jsget": stmts.registerGetter(info, op)
            of "jsset": stmts.registerSetter(info, op)
            of "jsufget": # LegacyUnforgeable
              op.flag = bffUnforgeable
              stmts.registerGetter(info, op)
            of "jsrget": # Replaceable
              op.flag = bffReplaceable
              stmts.registerGetter(info, op)
            of "jsgetset":
              stmts.registerGetter(info, op)
              stmts.registerSetter(info, op)
        elif varNode.kind == nnkPostfix:
          varNode = varNode[1]
        let typ = identDefs[^2]
        if typ.getTypeInst().sameType(JSValue.getType()) or
            JSValue.getType().sameType(typ):
          if info.markFun.kind == nnkNilLit:
            warning(info.tname & " misses .jsmark for member " &
              varNode.strVal & ".  This will cause memory leaks.")
          if info.finFun.kind == nnkNilLit:
            warning(info.tname & " misses .jsfin for member " &
              varNode.strVal & ".  This will cause memory leaks.")

proc nim_finalize_for_js*(obj, typeptr: pointer) =
  var lastrt: JSRuntime = nil
  for rt in runtimes:
    let rtOpaque = rt.getOpaque()
    rtOpaque.plist.withValue(obj, pp):
      let val = JS_MKPTR(JS_TAG_OBJECT, pp[])
      for fin in rtOpaque.finalizers(JS_GetClassID(val)):
        fin(nil, obj)
      JS_SetOpaque(val, nil)
      rtOpaque.plist.del(obj)
      if rtOpaque.destroying == obj:
        # Allow QJS to collect the JSValue through checkDestroy.
        rtOpaque.destroying = nil
      else:
        JS_FreeValueRT(rt, val)
      return
    lastrt = rt
  # No JSValue exists for the object, but it likely still expects us to
  # free it.
  # We pass nil as the runtime, since that's the only sensible solution.
  if lastrt != nil:
    let rtOpaque = lastrt.getOpaque()
    let classid = rtOpaque.typemap.getOrDefault(typeptr)
    for fin in rtOpaque.finalizers(classid):
      fin(nil, obj)

type
  TabGetSet* = object
    name*: string
    get*: JSGetterMagicFunction
    set*: JSSetterMagicFunction
    magic*: int16

  TabFunc* = object
    name*: string
    fun*: JSCFunction

template jsDestructor*[U](T: typedesc[ref U]) =
  static:
    jsDtors.incl($T)
  proc `=destroy`(obj: var U) =
    nim_finalize_for_js(addr obj, getTypePtr(obj))

template jsDestructor*(T: typedesc[object]) =
  static:
    jsDtors.incl($T)
  proc `=destroy`(obj: var T) =
    nim_finalize_for_js(addr obj, getTypePtr(obj))

proc bindConstructor(stmts: NimNode; info: var RegistryInfo): NimNode =
  if info.ctorFun != nil:
    return info.ctorFun
  return ident("js_illegal_ctor")

proc bindReplaceableSet(stmts: NimNode; info: var RegistryInfo) =
  let rsf = ident("js_replaceable_set")
  let t = info.t
  info.replaceableSetFun = rsf
  let trns = info.tabReplaceableNames
  stmts.add(quote do:
    const replaceableNames = `trns`
    proc `rsf`(ctx: JSContext; this, val: JSValueConst; magic: cint): JSValue
        {.cdecl.} =
      when `t` is object:
        var dummy {.noinit.}: ptr `t`
      else:
        var dummy: `t`
      if ctx.fromJSThis(this, dummy).isErr:
        return JS_EXCEPTION
      let name = replaceableNames[int(magic)]
      let dval = JS_DupValue(ctx, val)
      if JS_DefinePropertyValueStr(ctx, this, name, dval, JS_PROP_C_W_E) < 0:
        return JS_EXCEPTION
      return JS_DupValue(ctx, val)
  )

proc bindGetSet(stmts: NimNode; info: RegistryInfo) =
  var replaceableId = 0u16
  for k, (get, set, flag) in info.getset:
    case flag
    of bffNone:
      info.tabFuns.add(quote do: JS_CGETSET_DEF(`k`, `get`, `set`))
    of bffUnforgeable:
      info.tabUnforgeable.add(quote do:
        JS_CGETSET_DEF_NOCONF(`k`, `get`, `set`))
    of bffReplaceable:
      if set != nil:
        error("Replaceable properties must not have a setter.")
      let orid = replaceableId
      inc replaceableId
      if orid > replaceableId:
        error("Too many replaceable functions defined.")
      let magic = cast[int16](orid)
      info.tabFuns.add(quote do:
        JS_CGETSET_MAGIC_DEF(`k`, `get`, js_replaceable_set, `magic`))
    else:
      error("Static getters and setters are not supported.")

proc bindExtraGetSet(stmts: NimNode; info: var RegistryInfo;
    extraGetSet: openArray[TabGetSet]) =
  for x in extraGetSet:
    let k = x.name
    let g = x.get
    let s = x.set
    let m = x.magic
    info.tabFuns.add(quote do: JS_CGETSET_MAGIC_DEF(`k`, `g`, `s`, `m`))

proc jsCheckDestroyRef*(rt: JSRuntime; val: JSValueConst): JS_BOOL {.cdecl.} =
  let opaque = JS_GetOpaque(val, JS_GetClassID(val))
  if opaque != nil:
    # Before this function is called, the ownership model is
    # JSObject -> Nim object.
    # Here we change it to Nim object -> JSObject.
    # As a result, Nim object's reference count can now reach zero (it is
    # no longer "referenced" by the JS object).
    # nim_finalize_for_js will be invoked by the Nim GC when the Nim
    # refcount reaches zero. Then, the JS object's opaque will be set
    # to nil, and its refcount decreased again, so next time this
    # function will return true.
    #
    # Actually, we need another hack to ensure correct
    # operation. GC_unref may call the destructor of this object, and
    # in this case we cannot ask QJS to keep the JSValue alive. So we set
    # the "destroying" pointer to the current opaque, and return true if
    # the opaque was collected.
    let rtOpaque = rt.getOpaque()
    rtOpaque.destroying = opaque
    # We can lie about the type in refc, as it type erases the reference.
    # Sadly, this won't work in ARC... then again, nothing works in ARC,
    # so whatever.
    GC_unref(cast[RootRef](opaque))
    if rtOpaque.destroying == nil:
      # Looks like GC_unref called nim_finalize_for_js for this pointer.
      # This means we can allow QJS to collect this JSValue.
      return true
    else:
      rtOpaque.destroying = nil
      # Set an internal flag to note that the JS object is owned by the
      # Nim side.
      # This means that if toJS is used again on the Nim object, JS will
      # first get a non-dup'd object, and a reference will be set on
      # the Nim object.
      # Returning false from this function signals to the QJS GC that it
      # should not be collected yet.  Accordingly, the JSObject's
      # refcount (and that of its children) will be set to one again,
      # and later its opaque to NULL.
      return false
  return true

proc jsCheckDestroyNonRef*(rt: JSRuntime; val: JSValueConst): JS_BOOL
    {.cdecl.} =
  let opaque = JS_GetOpaque(val, JS_GetClassID(val))
  if opaque != nil:
    # This is not a reference, just a pointer with a reference to the
    # root ancestor object.
    # Remove the reference, allowing destruction of the root object once
    # again.
    let rtOpaque = rt.getOpaque()
    var parent: pointer = nil
    discard rtOpaque.parentMap.pop(opaque, parent)
    GC_unref(cast[RootRef](parent))
    # Of course, nim_finalize_for_js might only be called later for
    # this object, because the parent can still have references to it.
    # (And for the same reason, a reference to the same object might
    # still be necessary.)
    # Accordingly, we return false here as well.
    return false
  return true

proc bindEndStmts(endstmts: NimNode; info: RegistryInfo) =
  let jsname = info.jsname
  let dfin = info.dfin
  let markFun = info.markFun
  if info.propGetOwnFun.kind != nnkNilLit or
      info.propGetFun.kind != nnkNilLit or
      info.propSetFun.kind != nnkNilLit or
      info.propDelFun.kind != nnkNilLit or
      info.propHasFun.kind != nnkNilLit or
      info.propNamesFun.kind != nnkNilLit:
    let propGetOwnFun = info.propGetOwnFun
    let propGetFun = info.propGetFun
    let propSetFun = info.propSetFun
    let propDelFun = info.propDelFun
    let propHasFun = info.propHasFun
    let propNamesFun = info.propNamesFun
    endstmts.add(quote do:
      var exotic {.global.} = JSClassExoticMethods(
        get_own_property: `propGetOwnFun`,
        get_own_property_names: `propNamesFun`,
        has_property: `propHasFun`,
        get_property: `propGetFun`,
        set_property: `propSetFun`,
        delete_property: `propDelFun`
      )
      var cd {.global.} = JSClassDef(
        class_name: `jsname`,
        can_destroy: `dfin`,
        gc_mark: `markFun`,
        exotic: JSClassExoticMethodsConst(addr exotic)
      )
      let classDef {.inject.} = JSClassDefConst(addr cd)
    )
  else:
    endstmts.add(quote do:
      var cd {.global.} = JSClassDef(
        class_name: `jsname`,
        can_destroy: `dfin`,
        gc_mark: `markFun`
      )
      let classDef {.inject.} = JSClassDefConst(addr cd)
    )

macro registerType*(ctx: JSContext; t: typed; parent: JSClassID = 0;
    asglobal: static bool = false; globalparent: static bool = false;
    nointerface = false; name: static string = "";
    hasExtraGetSet: static bool = false;
    extraGetSet: static openArray[TabGetSet] = []; namespace = JS_NULL):
    JSClassID =
  var stmts = newStmtList()
  var info = BoundFunctions.getOrDefault(t.strVal)
  if info == nil:
    info = newRegistryInfo(t)
  if name != "":
    info.name = name
  if not asglobal:
    let impl = t.getTypeInst()[1].getTypeImpl()
    if impl.kind == nnkRefTy:
      info.dfin = quote do: jsCheckDestroyRef
    else:
      info.dfin = quote do: jsCheckDestroyNonRef
    if info.tname notin jsDtors:
      warning("No destructor has been defined for type " & info.tname)
  else:
    info.dfin = newNilLit()
    if info.tname in jsDtors:
      error("Global object " & info.tname & " must not have a destructor.")
  stmts.registerPragmas(info, t)
  if info.tabReplaceableNames.len > 0:
    stmts.bindReplaceableSet(info)
  stmts.bindGetSet(info)
  if hasExtraGetSet:
    #HACK: for some reason, extraGetSet gets weird contents when nothing is
    # passed to it. So we need an extra flag to signal if anything has
    # been passed to it at all.
    stmts.bindExtraGetSet(info, extraGetSet)
  let sctr = stmts.bindConstructor(info)
  let endstmts = newStmtList()
  endstmts.bindEndStmts(info)
  let finFun = info.finFun
  let flist = info.tabFuns
  let flen = flist.len
  let sflist = info.tabStatic
  let sflen = sflist.len
  let uflist = info.tabUnforgeable
  let uflen = uflist.len
  let global = asglobal and not globalparent
  endstmts.add(quote do:
    let flist {.global.}: array[`flen`, JSCFunctionListEntry] = `flist`
    let sflist {.global.}: array[`sflen`, JSCFunctionListEntry] = `sflist`
    let uflist {.global.}: array[`uflen`, JSCFunctionListEntry] = `uflist`
    `ctx`.newJSClass(classDef, getTypePtr(`t`), `sctr`, flist, `parent`,
      cast[bool](`global`), `nointerface`, `finFun`, `namespace`, uflist,
      sflist)
  )
  stmts.add(newBlockStmt(endstmts))
  return stmts

proc addRow(s: var string; title: string; count, size, sz2, cnt2: int64;
    name: string) =
  var fv = $(float(sz2) / float(cnt2))
  let i = fv.find('.')
  if i != -1:
    fv.setLen(i + 1)
  else:
    fv &= ".0"
  s &= title & ": " & $count & " " & $size & " (" & fv & ")" & name & "\n"

proc addRow(s: var string; title: string; count, size, sz2: int64;
    name: string) =
  s.addRow(title, count, size, sz2, count, name)

proc addRow(s: var string; title: string; count, size: int64; name: string) =
  s.addRow(title, count, size, size, name)

proc getMemoryUsage*(rt: JSRuntime): string =
  var m: JSMemoryUsage
  JS_ComputeMemoryUsage(rt, m)
  var s = ""
  if m.malloc_count != 0:
    s.addRow("memory allocated", m.malloc_count, m.malloc_size, "/block")
    s.addRow("memory used", m.memory_used_count, m.memory_used_size,
      m.malloc_size - m.memory_used_size, " average slack")
  if m.atom_count != 0:
    s.addRow("atoms", m.atom_count, m.atom_size, "/atom")
  if m.str_count != 0:
    s.addRow("strings", m.str_count, m.str_size, "/string")
  if m.obj_count != 0:
    s.addRow("objects", m.obj_count, m.obj_size, "/object")
    s.addRow("properties", m.prop_count, m.prop_size, m.prop_size, m.obj_count,
      "/object")
    s.addRow("shapes", m.shape_count, m.shape_size, "/shape")
  if m.js_func_count != 0:
    s.addRow("js functions", m.js_func_count, m.js_func_size, "/function")
  if m.c_func_count != 0:
    s &= "native functions: " & $m.c_func_count & "\n"
  if m.array_count != 0:
    s &= "arrays: " & $m.array_count & "\n" &
      "fast arrays: " & $m.fast_array_count & "\n"
    s.addRow("fast array elements", m.fast_array_elements,
        m.fast_array_elements * sizeof(JSValue), m.fast_array_elements,
        m.fast_array_count, "")
  if m.binary_object_count != 0:
    s &= "binary objects: " & $m.binary_object_count & " " &
      $m.binary_object_size
  move(s)

proc eval*(ctx: JSContext; s: string; file = "<input>";
    evalFlags = JS_EVAL_TYPE_GLOBAL): JSValue =
  return JS_Eval(ctx, cstring(s), csize_t(s.len), cstring(file),
    cint(evalFlags))

proc compileScript*(ctx: JSContext; s: string; file = "<input>"): JSValue =
  return ctx.eval(s, file, JS_EVAL_FLAG_COMPILE_ONLY)

proc compileModule*(ctx: JSContext; s: string; file = "<input>"): JSValue =
  return ctx.eval(s, file, JS_EVAL_TYPE_MODULE or JS_EVAL_FLAG_COMPILE_ONLY)

proc evalFunction*(ctx: JSContext; val: JSValue): JSValue =
  return JS_EvalFunction(ctx, val)

proc defineConsts*(ctx: JSContext; classid: JSClassID; consts: typedesc[enum]):
    DefinePropertyResult =
  let proto = JS_GetClassProto(ctx, classid)
  let ctor = ctx.getOpaque().classes[int(classid)].ctor
  for e in consts:
    let s = $e
    if (let res = ctx.definePropertyE(proto, s, uint16(e)); res != dprSuccess):
      JS_FreeValue(ctx, proto)
      return res
    if (let res = ctx.definePropertyE(ctor, s, uint16(e)); res != dprSuccess):
      JS_FreeValue(ctx, proto)
      return res
  JS_FreeValue(ctx, proto)
  dprSuccess

proc identity(ctx: JSContext; this_val: JSValueConst; argc: cint;
    argv: JSValueConstArray; magic: cint; func_data: JSValueConstArray): JSValue
    {.cdecl.} =
  return JS_DupValue(ctx, func_data[0])

proc identityFunction*(ctx: JSContext; val: JSValueConst): JSValue =
  return JS_NewCFunctionData(ctx, identity, 0, 0, 1, val.toJSValueConstArray())

{.pop.} # raises
