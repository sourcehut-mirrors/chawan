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
import std/options
import std/sets
import std/strutils
import std/tables

import fromjs
import jserror
import jsopaque
import optshim
import quickjs
import tojs

export options

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
  JSRuntime, JSContext, JSValue, JSClassID, JSAtom,
  JS_GetGlobalObject, JS_FreeValue, JS_IsException, JS_GetPropertyStr,
  JS_IsFunction, JS_NewCFunctionData, JS_Call, JS_DupValue, JS_IsUndefined,
  JS_ThrowTypeError, JS_ThrowRangeError, JS_ThrowSyntaxError,
  JS_ThrowInternalError, JS_ThrowReferenceError

when sizeof(int) < sizeof(int64):
  export quickjs.`==`

type
  JSFunctionList = openArray[JSCFunctionListEntry]

  BoundFunction = object
    t: BoundFunctionType
    name: string
    id: NimNode
    magic: uint16
    unforgeable: bool
    isstatic: bool
    ctorBody: NimNode

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
  var np = 0
  for p in rtOpaque.plist.values:
    rtOpaque.tmplist[np] = p
    inc np
  rtOpaque.plist.clear()
  var nu = 0
  for (_, unref) in rtOpaque.refmap.values:
    rtOpaque.tmpunrefs[nu] = unref
    inc nu
  rtOpaque.refmap.clear()
  for i in 0 ..< nu:
    rtOpaque.tmpunrefs[i]()
  for i in 0 ..< np:
    let p = rtOpaque.tmplist[i]
    #TODO maybe finalize?
    let val = JS_MKPTR(JS_TAG_OBJECT, p)
    let classid = JS_GetClassID(val)
    rtOpaque.fins.withValue(classid, fin):
      fin[](rt, val)
    JS_SetOpaque(val, nil)
    JS_FreeValueRT(rt, val)
  # GC will run again now

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

func getClass*(ctx: JSContext; class: string): JSClassID =
  ## Get the class ID of the registered class `class'.
  ## Note: this uses the Nim type's name, **not** the JS type's name.
  try:
    return ctx.getOpaque().creg[class]
  except KeyError:
    raise newException(Defect, "Class does not exist")

func hasClass*(ctx: JSContext; class: type): bool =
  ## Check if `class' is registered.
  ## Note: this uses the Nim type's name, **not** the JS type's name.
  return $class in ctx.getOpaque().creg

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
    for classid, v in opaque.ctors:
      JS_FreeValue(ctx, v)
    for v in opaque.errCtorRefs:
      JS_FreeValue(ctx, v)
    if opaque.globalUnref != nil:
      opaque.globalUnref()
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
  rtOpaque.tmpunrefs.setLen(rtOpaque.refmap.len)
  JS_FreeRuntime(rt)
  runtimes.del(runtimes.find(rt))

proc setGlobal*[T](ctx: JSContext; obj: T) =
  ## Set the global variable to the reference `obj`.
  ## Note: you must call `ctx.registerType(T, asglobal = true)` for this to
  ## work, `T` being the type of `obj`.
  # Add JSValue reference.
  let ctxOpaque = ctx.getOpaque()
  let opaque = cast[pointer](obj)
  ctx.setOpaque(ctxOpaque.global, opaque)
  GC_ref(obj)
  let rtOpaque = JS_GetRuntime(ctx).getOpaque()
  ctx.getOpaque().globalUnref = proc() =
    GC_unref(obj)
    rtOpaque.plist.del(opaque)

proc getExceptionMsg*(ctx: JSContext): string =
  result = ""
  let ex = JS_GetException(ctx)
  if fromJS(ctx, ex, result).isSome:
    result &= '\n'
  let stack = JS_GetPropertyStr(ctx, ex, cstring("stack"));
  var s: string
  if not JS_IsUndefined(stack) and ctx.fromJS(stack, s).isSome:
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
proc addClassUnforgeable(ctx: JSContext; proto: JSValue;
    classid, parent: JSClassID; ourUnforgeable: JSFunctionList) =
  let ctxOpaque = ctx.getOpaque()
  var merged = @ourUnforgeable
  if int(parent) < ctxOpaque.unforgeable.len:
    merged.add(ctxOpaque.unforgeable[int(parent)])
  if merged.len > 0:
    if int(classid) >= ctxOpaque.unforgeable.len:
      ctxOpaque.unforgeable.setLen(int(classid) + 1)
    ctxOpaque.unforgeable[int(classid)] = move(merged)
    let ufp0 = addr ctxOpaque.unforgeable[int(classid)][0]
    let ufp = cast[ptr UncheckedArray[JSCFunctionListEntry]](ufp0)
    JS_SetPropertyFunctionList(ctx, proto, ufp, cint(merged.len))

proc newProtoFromParentClass(ctx: JSContext; parent: JSClassID): JSValue =
  if parent != 0:
    let parentProto = JS_GetClassProto(ctx, parent)
    let proto = JS_NewObjectProtoClass(ctx, parentProto, parent)
    JS_FreeValue(ctx, parentProto)
    return proto
  return JS_NewObject(ctx)

func newJSClass*(ctx: JSContext; cdef: JSClassDefConst; tname: cstring;
    nimt: pointer; ctor: JSCFunction; funcs: JSFunctionList; parent: JSClassID;
    asglobal: bool; nointerface: bool; finalizer: JSFinalizerFunction;
    namespace: JSValue; errid: Opt[JSErrorEnum];
    unforgeable, staticfuns: JSFunctionList; ishtmldda: bool): JSClassID
    {.discardable.} =
  result = 0
  let rt = JS_GetRuntime(ctx)
  discard JS_NewClassID(rt, result)
  var ctxOpaque = ctx.getOpaque()
  var rtOpaque = rt.getOpaque()
  if JS_NewClass(rt, result, cdef) != 0:
    raise newException(Defect, "Failed to allocate JS class: " &
      $cdef.class_name)
  ctxOpaque.typemap[nimt] = result
  ctxOpaque.creg[tname] = result
  if ctxOpaque.parents.len <= int(result):
    ctxOpaque.parents.setLen(int(result) + 1)
  ctxOpaque.parents[result] = parent
  if ishtmldda:
    ctxOpaque.htmldda = result
  if finalizer != nil:
    rtOpaque.fins[result] = finalizer
  let proto = ctx.newProtoFromParentClass(parent)
  if funcs.len > 0:
    # We avoid funcs being GC'ed by putting the list in rtOpaque.
    # (QuickJS uses the pointer later.)
    #TODO maybe put them in ctxOpaque instead?
    rtOpaque.flist.add(@funcs)
    let fp0 = addr rtOpaque.flist[^1][0]
    let fp = cast[ptr UncheckedArray[JSCFunctionListEntry]](fp0)
    JS_SetPropertyFunctionList(ctx, proto, fp, cint(funcs.len))
  #TODO check if this is an indexed property getter
  if cdef.exotic != nil and cdef.exotic.get_own_property != nil:
    let val = JS_DupValue(ctx, ctxOpaque.valRefs[jsvArrayPrototypeValues])
    let itSym = ctxOpaque.symRefs[jsyIterator]
    ctx.defineProperty(proto, itSym, val)
  let news = JS_NewAtomString(ctx, cdef.class_name)
  doAssert not JS_IsException(news)
  ctx.definePropertyC(proto, ctxOpaque.symRefs[jsyToStringTag],
    JS_DupValue(ctx, news))
  JS_SetClassProto(ctx, result, proto)
  ctx.addClassUnforgeable(proto, result, parent, unforgeable)
  if asglobal:
    let global = ctxOpaque.global
    assert ctxOpaque.gclass == 0
    ctxOpaque.gclass = result
    ctx.definePropertyC(global, ctxOpaque.symRefs[jsyToStringTag],
      JS_DupValue(ctx, news))
    if JS_SetPrototype(ctx, global, proto) != 1:
      raise newException(Defect, "Failed to set global prototype: " &
        $cdef.class_name)
    # Global already exists, so set unforgeable functions here
    if int(result) < ctxOpaque.unforgeable.len and
        ctxOpaque.unforgeable[int(result)].len > 0:
      let ufp0 = addr ctxOpaque.unforgeable[int(result)][0]
      let ufp = cast[ptr UncheckedArray[JSCFunctionListEntry]](ufp0)
      JS_SetPropertyFunctionList(ctx, global, ufp,
        cint(ctxOpaque.unforgeable[int(result)].len))
  JS_FreeValue(ctx, news)
  let jctor = JS_NewCFunction2(ctx, ctor, cstring($cdef.class_name), 0,
    JS_CFUNC_constructor, 0)
  if staticfuns.len > 0:
    rtOpaque.flist.add(@staticfuns)
    let fp0 = addr rtOpaque.flist[^1][0]
    let fp = cast[ptr UncheckedArray[JSCFunctionListEntry]](fp0)
    JS_SetPropertyFunctionList(ctx, jctor, fp, cint(staticfuns.len))
  JS_SetConstructor(ctx, jctor, proto)
  if errid.isSome:
    ctx.getOpaque().errCtorRefs[errid.get] = JS_DupValue(ctx, jctor)
  while ctxOpaque.ctors.len <= int(result):
    ctxOpaque.ctors.add(JS_UNDEFINED)
  ctxOpaque.ctors[result] = JS_DupValue(ctx, jctor)
  if not nointerface:
    if JS_IsNull(namespace):
      ctx.definePropertyCW(ctxOpaque.global, $cdef.class_name, jctor)
    else:
      ctx.definePropertyCW(namespace, $cdef.class_name, jctor)
  else:
    JS_FreeValue(ctx, jctor)

type FuncParam = tuple
  name: string
  t: NimNode
  val: Option[NimNode]
  generic: Option[NimNode]
  isptr: bool

func getMinArgs(params: seq[FuncParam]): int =
  for i, it in params:
    if it[2].isSome:
      return i
    let t = it.t
    if t.kind == nnkBracketExpr:
      if t.typeKind == varargs.getType().typeKind:
        assert i == params.high, "Not even nim can properly handle this..."
        return i
  return params.len

type
  JSFuncGenerator = ref object
    t: BoundFunctionType
    hasThis: bool
    funcName: string
    funcParams: seq[FuncParam]
    passCtx: bool
    thisType: string
    thisTypeNode: NimNode
    returnType: Option[NimNode]
    newName: NimNode
    newBranchList: seq[NimNode]
    errval: NimNode # JS_EXCEPTION or -1
    # die: didn't match parameters, but could still match other ones
    dielabel: NimNode
    jsFunCallLists: seq[NimNode]
    jsFunCallList: NimNode
    jsFunCall: NimNode
    jsCallAndRet: NimNode
    minArgs: int
    actualMinArgs: int # minArgs without JSContext
    i: int # nim parameters accounted for
    j: int # js parameters accounted for (not including fix ones, e.g. `this')
    unforgeable: bool
    isstatic: bool

var BoundFunctions {.compileTime.}: Table[string, seq[BoundFunction]]

proc getParams(fun: NimNode): seq[FuncParam] =
  let formalParams = fun.findChild(it.kind == nnkFormalParams)
  var funcParams: seq[FuncParam] = @[]
  var returnType = none(NimNode)
  if formalParams[0].kind != nnkEmpty:
    returnType = some(formalParams[0])
  for i in 1 ..< fun.params.len:
    let it = formalParams[i]
    let tt = it[^2]
    var t: NimNode
    if it[^2].kind != nnkEmpty:
      t = `tt`
    elif it[^1].kind != nnkEmpty:
      let x = it[^1]
      t = quote do:
        typeof(`x`)
    else:
      error("?? " & treeRepr(it))
    let isptr = t.kind == nnkVarTy
    if t.kind == nnkRefTy:
      t = t[0]
    elif t.kind == nnkVarTy:
      t = newNimNode(nnkPtrTy).add(t[0])
    let val = if it[^1].kind != nnkEmpty:
      let x = it[^1]
      some(newPar(x))
    else:
      none(NimNode)
    var g = none(NimNode)
    for i in 0 ..< it.len - 2:
      let name = $it[i]
      funcParams.add((name, t, val, g, isptr))
  funcParams

proc getReturn(fun: NimNode): Option[NimNode] =
  let formalParams = fun.findChild(it.kind == nnkFormalParams)
  if formalParams[0].kind != nnkEmpty:
    some(formalParams[0])
  else:
    none(NimNode)

template getJSParams(): untyped =
  [
    (quote do: JSValue),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("this"), quote do: JSValue),
    newIdentDefs(ident("argc"), quote do: cint),
    newIdentDefs(ident("argv"), quote do: ptr UncheckedArray[JSValue])
  ]

template getJSGetterParams(): untyped =
  [
    (quote do: JSValue),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("this"), quote do: JSValue),
  ]

template getJSGetOwnPropParams(): untyped =
  [
    (quote do: cint),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("desc"), quote do: ptr JSPropertyDescriptor),
    newIdentDefs(ident("this"), quote do: JSValue),
    newIdentDefs(ident("prop"), quote do: JSAtom),
  ]

template getJSGetPropParams(): untyped =
  [
    (quote do: JSValue),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("this"), quote do: JSValue),
    newIdentDefs(ident("prop"), quote do: JSAtom),
    newIdentDefs(ident("receiver"), quote do: JSValue),
  ]

template getJSSetPropParams(): untyped =
  [
    (quote do: cint),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("this"), quote do: JSValue),
    newIdentDefs(ident("atom"), quote do: JSAtom),
    newIdentDefs(ident("value"), quote do: JSValue),
    newIdentDefs(ident("receiver"), quote do: JSValue),
    newIdentDefs(ident("flags"), quote do: cint),
  ]

template getJSDelPropParams(): untyped =
  [
    (quote do: cint),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("this"), quote do: JSValue),
    newIdentDefs(ident("prop"), quote do: JSAtom),
  ]

template getJSHasPropParams(): untyped =
  [
    (quote do: cint),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("this"), quote do: JSValue),
    newIdentDefs(ident("atom"), quote do: JSAtom),
  ]


template getJSSetterParams(): untyped =
  [
    (quote do: JSValue),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("this"), quote do: JSValue),
    newIdentDefs(ident("val"), quote do: JSValue),
  ]

template getJSPropNamesParams(): untyped =
  [
    (quote do: cint),
    newIdentDefs(ident("ctx"), quote do: JSContext),
    newIdentDefs(ident("ptab"), quote do: ptr JSPropertyEnumArray),
    newIdentDefs(ident("plen"), quote do: ptr uint32),
    newIdentDefs(ident("this"), quote do: JSValue)
  ]

template fromJS_or_die*(ctx, val, res, dl: untyped) =
  if ctx.fromJS(val, res).isNone:
    break dl

proc addParam2(gen: var JSFuncGenerator; s, t, val: NimNode;
    fallback: NimNode = nil) =
  let dl = gen.dielabel
  if fallback == nil:
    for list in gen.jsFunCallLists.mitems:
      list.add(quote do:
        var `s`: `t`
        fromJS_or_die(ctx, `val`, `s`, `dl`)
      )
  else:
    let j = gen.j
    for list in gen.jsFunCallLists.mitems:
      list.add(quote do:
        var `s`: `t`
        if `j` < argc and not JS_IsUndefined(argv[`j`]):
          fromJS_or_die(ctx, `val`, `s`, `dl`)
        else:
          `s` = `fallback`
      )

proc addValueParam(gen: var JSFuncGenerator; s, t: NimNode;
    fallback: NimNode = nil) =
  let j = gen.j
  gen.addParam2(s, t, quote do: argv[`j`], fallback)

proc addThisParam(gen: var JSFuncGenerator; thisName = "this") =
  var s = ident("arg_" & $gen.i)
  let t = gen.funcParams[gen.i].t
  let id = ident(thisName)
  let tt = gen.thisType
  let fn = gen.funcName
  let ev = gen.errval
  for list in gen.jsFunCallLists.mitems:
    list.add(quote do:
      var `s`: `t`
      if ctx.fromJSThis(`id`, `s`).isNone:
        discard JS_ThrowTypeError(ctx,
          "'%s' called on an object that is not an instance of %s", `fn`, `tt`)
        return `ev`
    )
  if gen.funcParams[gen.i].isptr:
    s = quote do: `s`[]
  gen.jsFunCall.add(s)
  inc gen.i

proc addFixParam(gen: var JSFuncGenerator; name: string) =
  var s = ident("arg_" & $gen.i)
  let t = gen.funcParams[gen.i].t
  let id = ident(name)
  if t.typeKind == ntyGenericParam:
    error("Union parameters are no longer supported. Use JSValue instead.")
  gen.addParam2(s, t, id)
  if gen.funcParams[gen.i].isptr:
    s = quote do: `s`[]
  gen.jsFunCall.add(s)
  inc gen.i

proc addRequiredParams(gen: var JSFuncGenerator) =
  while gen.i < gen.minArgs:
    var s = ident("arg_" & $gen.i)
    let tt = gen.funcParams[gen.i].t
    if tt.typeKind == ntyGenericParam:
      error("Union parameters are no longer supported. Use JSValue instead.")
    gen.addValueParam(s, tt)
    if gen.funcParams[gen.i].isptr:
      s = quote do: `s`[]
    gen.jsFunCall.add(s)
    inc gen.j
    inc gen.i

proc addOptionalParams(gen: var JSFuncGenerator) =
  while gen.i < gen.funcParams.len:
    let j = gen.j
    var s = ident("arg_" & $gen.i)
    let tt = gen.funcParams[gen.i].t
    if tt.typeKind == varargs.getType().typeKind: # pray it's not a generic...
      let vt = tt[1]
      if vt.sameType(JSValue.getType()) or JSValue.getType().sameType(vt):
        s = quote do:
          argv.toOpenArray(`j`, argc - 1)
      else:
        error("Only JSValue varargs are supported")
    else:
      if gen.funcParams[gen.i][2].isNone:
        error("No fallback value. Maybe a non-optional parameter follows an " &
          "optional parameter?")
      let fallback = gen.funcParams[gen.i][2].get
      if tt.typeKind == ntyGenericParam:
        error("Union parameters are no longer supported. Use JSValue instead.")
      gen.addValueParam(s, tt, fallback)
    if gen.funcParams[gen.i].isptr:
      s = quote do: `s`[]
    gen.jsFunCall.add(s)
    inc gen.j
    inc gen.i

proc finishFunCallList(gen: var JSFuncGenerator) =
  for branch in gen.jsFunCallLists:
    branch.add(gen.jsFunCall)

var jsDtors {.compileTime.}: HashSet[string]

proc registerFunction(typ: string; nf: BoundFunction) =
  BoundFunctions.withValue(typ, val):
    val[].add(nf)
  do:
    BoundFunctions[typ] = @[nf]

proc registerFunction(typ: string; t: BoundFunctionType; name: string;
    id: NimNode; magic: uint16 = 0; uf = false; isstatic = false;
    ctorBody: NimNode = nil) =
  registerFunction(typ, BoundFunction(
    t: t,
    name: name,
    id: id,
    magic: magic,
    unforgeable: uf,
    isstatic: isstatic,
    ctorBody: ctorBody
  ))

proc registerConstructor(gen: JSFuncGenerator; jsProc: NimNode) =
  registerFunction(gen.thisType, gen.t, gen.funcName, gen.newName,
    uf = gen.unforgeable, isstatic = gen.isstatic, ctorBody = jsProc)

proc registerFunction(gen: JSFuncGenerator) =
  registerFunction(gen.thisType, gen.t, gen.funcName, gen.newName,
    uf = gen.unforgeable, isstatic = gen.isstatic)

proc newJSProcBody(gen: var JSFuncGenerator; isva: bool): NimNode =
  let ma = gen.actualMinArgs
  result = newStmtList()
  if isva and ma > 0:
    result.add(quote do:
      if argc < `ma`:
        return JS_ThrowTypeError(ctx,
          "At least %d arguments required, but only %d passed", cint(`ma`),
          cint(argc))
    )
  result.add(gen.jsCallAndRet)

proc newJSProc(gen: var JSFuncGenerator; params: openArray[NimNode];
    isva = true): NimNode =
  let jsBody = gen.newJSProcBody(isva)
  let jsPragmas = newNimNode(nnkPragma).add(ident("cdecl"))
  return newProc(gen.newName, params, jsBody, pragmas = jsPragmas)

func getFuncName(fun: NimNode; jsname, staticName: string): string =
  if jsname != "":
    return jsname
  if staticName != "":
    let i = staticName.find('.')
    if i != -1:
      return staticName.substr(i + 1)
  return $fun[0]

func getErrVal(t: BoundFunctionType): NimNode =
  if t in {bfPropertyGetOwn, bfPropertySet, bfPropertyDel, bfPropertyHas,
      bfPropertyNames}:
    return quote do: cint(-1)
  return quote do: JS_EXCEPTION

proc addJSContext(gen: var JSFuncGenerator) =
  if gen.funcParams.len > gen.i:
    if gen.funcParams[gen.i].t.eqIdent(ident("JSContext")):
      gen.passCtx = true
      gen.jsFunCall.add(ident("ctx"))
      inc gen.i
    elif gen.funcParams[gen.i].t.eqIdent(ident("JSRuntime")):
      inc gen.i # special case for finalizers that have a JSRuntime param

proc addThisName(gen: var JSFuncGenerator; hasThis: bool) =
  if hasThis:
    var t = gen.funcParams[gen.i].t
    if t.kind == nnkPtrTy:
      t = t[0]
    gen.thisTypeNode = t
    gen.thisType = $t
    gen.newName = ident($gen.t & "_" & gen.thisType & "_" & gen.funcName)
  else:
    let rt = gen.returnType.get
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

func getActualMinArgs(gen: var JSFuncGenerator): int =
  var ma = gen.minArgs
  if gen.hasThis and not gen.isstatic:
    dec ma
  if gen.passCtx:
    dec ma
  assert ma >= 0
  return ma

proc initGenerator(fun: NimNode; t: BoundFunctionType; hasThis: bool;
    jsname = ""; unforgeable = false; staticName = ""): JSFuncGenerator =
  let jsFunCallList = newStmtList()
  let funcParams = getParams(fun)
  var gen = JSFuncGenerator(
    t: t,
    funcName: getFuncName(fun, jsname, staticName),
    funcParams: funcParams,
    returnType: getReturn(fun),
    minArgs: funcParams.getMinArgs(),
    hasThis: hasThis,
    errval: getErrVal(t),
    dielabel: ident("ondie"),
    jsFunCallList: jsFunCallList,
    jsFunCallLists: @[jsFunCallList],
    jsFunCall: newCall(fun[0]),
    unforgeable: unforgeable,
    isstatic: staticName != ""
  )
  gen.addJSContext()
  gen.actualMinArgs = gen.getActualMinArgs() # must come after passctx is set
  if staticName == "":
    gen.addThisName(hasThis)
  else:
    gen.thisType = staticName
    if (let i = gen.thisType.find('.'); i != -1):
      gen.thisType.setLen(i)
    gen.newName = ident($gen.t & "_" & gen.funcName)
  return gen

proc makeJSCallAndRet(gen: var JSFuncGenerator; okstmt, errstmt: NimNode) =
  let jfcl = gen.jsFunCallList
  let dl = gen.dielabel
  gen.jsCallAndRet = if gen.returnType.isSome:
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

proc makeCtorJSCallAndRet(gen: var JSFuncGenerator; errstmt: NimNode) =
  let jfcl = gen.jsFunCallList
  let dl = gen.dielabel
  gen.jsCallAndRet = quote do:
    block `dl`:
      return ctx.toJSNew(`jfcl`, this)
    `errstmt`

macro jsctor*(fun: typed) =
  var gen = initGenerator(fun, bfConstructor, hasThis = false)
  gen.addRequiredParams()
  gen.addOptionalParams()
  gen.finishFunCallList()
  let errstmt = quote do:
    return JS_ThrowTypeError(ctx, "Invalid parameters passed to constructor")
  gen.makeCtorJSCallAndRet(errstmt)
  let jsProc = gen.newJSProc(getJSParams())
  gen.registerConstructor(jsProc)
  return fun

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
  var handleRetv: NimNode = nil
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
  gen.finishFunCallList()
  let jfcl = gen.jsFunCallList
  let dl = gen.dielabel
  gen.jsCallAndRet = quote do:
    block `dl`:
      if JS_GetOpaque(this, JS_GetClassID(this)) == nil:
        return cint(0)
      let retv {.inject.} = ctx.toJS(`jfcl`)
      if JS_IsException(retv):
        break `dl`
      if JS_IsUninitialized(retv):
        return cint(0)
      `handleRetv`
      return cint(1)
    return cint(-1)
  let jsProc = gen.newJSProc(getJSGetOwnPropParams(), false)
  gen.registerFunction()
  return newStmtList(fun, jsProc)

macro jsgetprop*(fun: typed) {.deprecated: "use jsgetownprop instead".} =
  var gen = initGenerator(fun, bfPropertyGetOwn, hasThis = true)
  gen.addThisParam()
  gen.addFixParam("prop")
  gen.finishFunCallList()
  let jfcl = gen.jsFunCallList
  let dl = gen.dielabel
  gen.jsCallAndRet = quote do:
    block `dl`:
      if JS_GetOpaque(this, JS_GetClassID(this)) == nil:
        return cint(0)
      let retv = ctx.toJS(`jfcl`)
      if JS_IsException(retv):
        break `dl`
      if JS_IsNull(retv):
        return cint(0)
      if desc != nil:
        # From quickjs.h:
        # > If 1 is returned, the property descriptor 'desc' is filled
        # > if != NULL.
        # So desc may be nil.
        let fun = ctx.newFunction([], "return () => this;")
        let val = JS_Call(ctx, fun, retv, 0, nil)
        JS_FreeValue(ctx, fun)
        desc[].setter = JS_UNDEFINED
        desc[].getter = val
        desc[].value = JS_UNDEFINED
        desc[].flags = JS_PROP_GETSET
      return cint(1)
    return cint(-1)
  let jsProc = gen.newJSProc(getJSGetOwnPropParams(), false)
  gen.registerFunction()
  return newStmtList(fun, jsProc)

macro jsgetrealprop*(fun: typed) =
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
  gen.jsCallAndRet = if gen.returnType.isSome:
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

macro jsfgetn(jsname: static string; uf: static bool; fun: typed) =
  var gen = initGenerator(fun, bfGetter, hasThis = true, jsname = jsname,
    unforgeable = uf)
  if gen.actualMinArgs != 0 or gen.funcParams.len != gen.minArgs:
    error("jsfget functions must only accept one parameter.")
  if gen.returnType.isNone:
    error("jsfget functions must have a return type.")
  gen.addThisParam()
  gen.finishFunCallList()
  gen.makeJSCallAndRet(nil, quote do: discard)
  let jsProc = gen.newJSProc(getJSGetterParams(), false)
  gen.registerFunction()
  return newStmtList(fun, jsProc)

# "Why?" So the compiler doesn't cry.
# Warning: make these typed and you will cry instead.
template jsfget*(fun: untyped) =
  jsfgetn("", false, fun)

template jsuffget*(fun: untyped) =
  jsfgetn("", true, fun)

template jsfget*(jsname, fun: untyped) =
  jsfgetn(jsname, false, fun)

template jsuffget*(jsname, fun: untyped) =
  jsfgetn(jsname, true, fun)

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

macro jsfuncn*(jsname: static string; uf: static bool;
    staticName: static string; fun: typed) =
  var gen = initGenerator(fun, bfFunction, hasThis = true, jsname = jsname,
    unforgeable = uf, staticName = staticName)
  if gen.minArgs == 0 and not gen.isstatic:
    error("Zero-parameter functions are not supported. " &
      "(Maybe pass Window or Client?)")
  if not gen.isstatic:
    gen.addThisParam()
  gen.addRequiredParams()
  gen.addOptionalParams()
  gen.finishFunCallList()
  let okstmt = quote do:
    return JS_UNDEFINED
  let errstmt = quote do:
    return JS_ThrowTypeError(ctx, "Invalid parameters passed to function")
  gen.makeJSCallAndRet(okstmt, errstmt)
  let jsProc = gen.newJSProc(getJSParams())
  gen.registerFunction()
  return newStmtList(fun, jsProc)

template jsfunc*(fun: untyped) =
  jsfuncn("", false, "", fun)

template jsuffunc*(fun: untyped) =
  jsfuncn("", true, "", fun)

template jsfunc*(jsname, fun: untyped) =
  jsfuncn(jsname, false, "", fun)

template jsuffunc*(jsname, fun: untyped) =
  jsfuncn(jsname, true, "", fun)

template jsstfunc*(name, fun: untyped) =
  jsfuncn("", false, name, fun)

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
    proc `finName`(rt {.inject.}: JSRuntime; val: JSValue) =
      let opaque {.inject.} = JS_GetOpaque(val, JS_GetClassID(val))
      if opaque != nil:
        `finStmt`
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

proc js_illegal_ctor*(ctx: JSContext; this: JSValue; argc: cint;
    argv: ptr UncheckedArray[JSValue]): JSValue {.cdecl.} =
  return JS_ThrowTypeError(ctx, "Illegal constructor")

type
  JSObjectPragma = object
    name: string
    varsym: NimNode
    unforgeable: bool

  JSObjectPragmas = object
    jsget: seq[JSObjectPragma]
    jsset: seq[JSObjectPragma]
    jsinclude: seq[JSObjectPragma]

func getPragmaName(varPragma: NimNode): string =
  if varPragma.kind == nnkExprColonExpr:
    return $varPragma[0]
  return $varPragma

func getStringFromPragma(varPragma: NimNode): Option[string] =
  if varPragma.kind == nnkExprColonExpr:
    if not varPragma.len == 1 and varPragma[1].kind == nnkStrLit:
      error("Expected string as pragma argument")
    return some($varPragma[1])
  return none(string)

proc findPragmas(t: NimNode): JSObjectPragmas =
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
  var pragmas = JSObjectPragmas()
  while identDefsStack.len > 0:
    let identDefs = identDefsStack.pop()
    case identDefs.kind
    of nnkRecList:
      for child in identDefs.children:
        identDefsStack.add(child)
    of nnkRecCase:
      # Add condition definition
      identDefsStack.add(identDefs[0])
      # Add branches
      for i in 1 ..< identDefs.len:
        identDefsStack.add(identDefs[i].last)
    else:
      for i in 0 ..< identDefs.len - 2:
        let varNode = identDefs[i]
        if varNode.kind == nnkPragmaExpr:
          var varName = varNode[0]
          if varName.kind == nnkPostfix:
            # This is a public field. We are skipping the postfix *
            varName = varName[1]
          let varPragmas = varNode[1]
          for varPragma in varPragmas:
            let pragmaName = getPragmaName(varPragma)
            var op = JSObjectPragma(
              name: getStringFromPragma(varPragma).get($varName),
              varsym: varName
            )
            case pragmaName
            of "jsget": pragmas.jsget.add(op)
            of "jsset": pragmas.jsset.add(op)
            of "jsufget": # LegacyUnforgeable
              op.unforgeable = true
              pragmas.jsget.add(op)
            of "jsgetset":
              pragmas.jsget.add(op)
              pragmas.jsset.add(op)
            of "jsinclude": pragmas.jsinclude.add(op)
  return pragmas

proc nim_finalize_for_js*(obj: pointer) =
  for rt in runtimes:
    let rtOpaque = rt.getOpaque()
    rtOpaque.plist.withValue(obj, v):
      let p = v[]
      let val = JS_MKPTR(JS_TAG_OBJECT, p)
      let classid = JS_GetClassID(val)
      rtOpaque.fins.withValue(classid, fin):
        fin[](rt, val)
      JS_SetOpaque(val, nil)
      rtOpaque.plist.del(obj)
      if rtOpaque.destroying == obj:
        # Allow QJS to collect the JSValue through checkDestroy.
        rtOpaque.destroying = nil
      else:
        JS_FreeValueRT(rt, val)

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
  {.warning[Deprecated]:off.}:
    proc `=destroy`(obj: var U) =
      nim_finalize_for_js(addr obj)

template jsDestructor*(T: typedesc[object]) =
  static:
    jsDtors.incl($T)
  {.warning[Deprecated]:off.}:
    proc `=destroy`(obj: var T) =
      nim_finalize_for_js(addr obj)

type RegistryInfo = object
  t: NimNode # NimNode of type
  name: string # JS name, if this is the empty string then it equals tname
  tabList: NimNode # array of function table
  ctorImpl: NimNode # definition & body of constructor
  ctorFun: NimNode # constructor ident
  getset: Table[string, (NimNode, NimNode, bool)] # name -> get, set, uf
  propGetOwnFun: NimNode # custom own get function ident
  propGetFun: NimNode # custom get function ident
  propSetFun: NimNode # custom set function ident
  propDelFun: NimNode # custom del function ident
  propHasFun: NimNode # custom has function ident
  propNamesFun: NimNode # custom property names function ident
  finFun: NimNode # finalizer ident
  finName: NimNode # finalizer wrapper ident
  dfin: NimNode # CheckDestroy finalizer ident
  classDef: NimNode # ClassDef ident
  tabUnforgeable: NimNode # array of unforgeable function table
  tabStatic: NimNode # array of static function table

func tname(info: RegistryInfo): string =
  return info.t.strVal

# Differs from tname if the Nim object's name differs from the JS object's
# name.
func jsname(info: RegistryInfo): string =
  if info.name != "":
    return info.name
  return info.tname

proc newRegistryInfo(t: NimNode; name: string): RegistryInfo =
  return RegistryInfo(
    t: t,
    name: name,
    classDef: ident("classDef"),
    tabList: newNimNode(nnkBracket),
    tabUnforgeable: newNimNode(nnkBracket),
    tabStatic: newNimNode(nnkBracket),
    finName: newNilLit(),
    finFun: newNilLit(),
    propGetOwnFun: newNilLit(),
    propGetFun: newNilLit(),
    propSetFun: newNilLit(),
    propDelFun: newNilLit(),
    propHasFun: newNilLit(),
    propNamesFun: newNilLit()
  )

proc bindConstructor(stmts: NimNode; info: var RegistryInfo): NimNode =
  if info.ctorFun != nil:
    stmts.add(info.ctorImpl)
    return info.ctorFun
  return ident("js_illegal_ctor")

proc registerGetters(stmts: NimNode; info: RegistryInfo;
    jsget: seq[JSObjectPragma]) =
  let t = info.t
  let tname = info.tname
  let jsname = info.jsname
  for op in jsget:
    let node = op.varsym
    let fn = op.name
    let id = ident($bfGetter & "_" & tname & "_" & fn)
    stmts.add(quote do:
      proc `id`(ctx: JSContext; this: JSValue): JSValue {.cdecl.} =
        when `t` is object:
          var arg_0: ptr `t`
        else:
          var arg_0: `t`
        if ctx.fromJSThis(this, arg_0).isNone:
          return JS_ThrowTypeError(ctx,
            "'%s' called on an object that is not an instance of %s", `fn`,
            `jsname`)
        when typeof(arg_0.`node`) is object:
          return toJSP(ctx, arg_0, arg_0.`node`)
        else:
          return toJS(ctx, arg_0.`node`)
    )
    registerFunction(tname, BoundFunction(
      t: bfGetter,
      name: fn,
      id: id,
      unforgeable: op.unforgeable
    ))

proc registerSetters(stmts: NimNode; info: RegistryInfo;
    jsset: seq[JSObjectPragma]) =
  let t = info.t
  let tname = info.tname
  let jsname = info.jsname
  for op in jsset:
    let node = op.varsym
    let fn = op.name
    let id = ident($bfSetter & "_" & tname & "_" & fn)
    stmts.add(quote do:
      proc `id`(ctx: JSContext; this: JSValue; val: JSValue): JSValue
          {.cdecl.} =
        when `t` is object:
          var arg_0: ptr `t`
        else:
          var arg_0: `t`
        if ctx.fromJS(this, arg_0).isNone:
          return JS_ThrowTypeError(ctx,
            "'%s' called on an object that is not an instance of %s", `fn`,
            `jsname`)
        # We can't just set arg_0.`node` directly, or fromJS may damage it.
        var nodeVal: typeof(arg_0.`node`)
        if ctx.fromJS(val, nodeVal).isNone:
          return JS_EXCEPTION
        arg_0.`node` = move(nodeVal)
        return JS_DupValue(ctx, val)
    )
    registerFunction(tname, bfSetter, fn, id)

proc bindFunctions(stmts: NimNode; info: var RegistryInfo) =
  BoundFunctions.withValue(info.tname, funs):
    for fun in funs[].mitems:
      var f0 = fun.name
      let f1 = fun.id
      if fun.name.endsWith("_exceptions"):
        fun.name = fun.name.substr(0, fun.name.high - "_exceptions".len)
      case fun.t
      of bfFunction:
        f0 = fun.name
        if fun.unforgeable:
          info.tabUnforgeable.add(quote do:
            JS_CFUNC_DEF_NOCONF(`f0`, 0, cast[JSCFunction](`f1`)))
        elif fun.isstatic:
          info.tabStatic.add(quote do:
            JS_CFUNC_DEF(`f0`, 0, cast[JSCFunction](`f1`)))
        else:
          info.tabList.add(quote do:
            JS_CFUNC_DEF(`f0`, 0, cast[JSCFunction](`f1`)))
      of bfConstructor:
        info.ctorImpl = fun.ctorBody
        if info.ctorFun != nil:
          error("Class " & info.tname & " has 2+ constructors.")
        info.ctorFun = f1
      of bfGetter:
        info.getset.withValue(f0, exv):
          exv[0] = f1
          exv[2] = fun.unforgeable
        do:
          info.getset[f0] = (f1, newNilLit(), fun.unforgeable)
      of bfSetter:
        info.getset.withValue(f0, exv):
          exv[1] = f1
        do:
          info.getset[f0] = (newNilLit(), f1, false)
      of bfPropertyGetOwn:
        if info.propGetFun.kind != nnkNilLit:
          error("Class " & info.tname & " has 2+ own property getters.")
        info.propGetOwnFun = f1
      of bfPropertyGet:
        if info.propGetFun.kind != nnkNilLit:
          error("Class " & info.tname & " has 2+ property getters.")
        info.propGetFun = f1
      of bfPropertySet:
        if info.propSetFun.kind != nnkNilLit:
          error("Class " & info.tname & " has 2+ property setters.")
        info.propSetFun = f1
      of bfPropertyDel:
        if info.propDelFun.kind != nnkNilLit:
          error("Class " & info.tname & " has 2+ property deleters.")
        info.propDelFun = f1
      of bfPropertyHas:
        if info.propHasFun.kind != nnkNilLit:
          error("Class " & info.tname & " has 2+ hasprop getters.")
        info.propHasFun = f1
      of bfPropertyNames:
        if info.propNamesFun.kind != nnkNilLit:
          error("Class " & info.tname & " has 2+ propnames getters.")
        info.propNamesFun = f1
      of bfFinalizer:
        f0 = fun.name
        info.finFun = ident(f0)
        info.finName = f1

proc bindGetSet(stmts: NimNode; info: RegistryInfo) =
  for k, (get, set, unforgeable) in info.getset:
    if not unforgeable:
      info.tabList.add(quote do: JS_CGETSET_DEF(`k`, `get`, `set`))
    else:
      info.tabUnforgeable.add(quote do:
        JS_CGETSET_DEF_NOCONF(`k`, `get`, `set`))

proc bindExtraGetSet(stmts: NimNode; info: var RegistryInfo;
    extraGetSet: openArray[TabGetSet]) =
  for x in extraGetSet:
    let k = x.name
    let g = x.get
    let s = x.set
    let m = x.magic
    info.tabList.add(quote do: JS_CGETSET_MAGIC_DEF(`k`, `g`, `s`, `m`))

proc bindCheckDestroy(stmts: NimNode; info: RegistryInfo) =
  let t = info.t
  let dfin = info.dfin
  stmts.add(quote do:
    proc `dfin`(rt: JSRuntime; val: JSValue): JS_BOOL {.cdecl.} =
      let opaque = JS_GetOpaque(val, JS_GetClassID(val))
      if opaque != nil:
        when `t` is ref object:
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
          rt.getOpaque().destroying = opaque
          GC_unref(cast[`t`](opaque))
          if rt.getOpaque().destroying == nil:
            # Looks like GC_unref called nim_finalize_for_js for this pointer.
            # This means we can allow QJS to collect this JSValue.
            return true
          else:
            rt.getOpaque().destroying = nil
            # Returning false from this function signals to the QJS GC that it
            # should not be collected yet. Accordingly, the JSObject's refcount
            # will be set to one again.
            return false
        else:
          # This is not a reference, just a pointer with a reference to the
          # root ancestor object.
          # Remove the reference, allowing destruction of the root object once
          # again.
          let rtOpaque = rt.getOpaque()
          var crefunref: tuple[cref, cunref: (proc())]
          discard rtOpaque.refmap.pop(opaque, crefunref)
          crefunref.cunref()
          # Of course, nim_finalize_for_js might only be called later for
          # this object, because the parent can still have references to it.
          # (And for the same reason, a reference to the same object might
          # still be necessary.)
          # Accordingly, we return false here as well.
          return false
      return true
  )

proc bindEndStmts(endstmts: NimNode; info: RegistryInfo) =
  let jsname = info.jsname
  let dfin = info.dfin
  let classDef = info.classDef
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
        exotic: JSClassExoticMethodsConst(addr exotic)
      )
      let `classDef` = JSClassDefConst(addr cd)
    )
  else:
    endstmts.add(quote do:
      var cd {.global.} = JSClassDef(
        class_name: `jsname`,
        can_destroy: `dfin`
      )
      let `classDef` = JSClassDefConst(addr cd)
    )

macro registerType*(ctx: JSContext; t: typed; parent: JSClassID = 0;
    asglobal: static bool = false; globalparent: static bool = false;
    nointerface = false; name: static string = "";
    hasExtraGetSet: static bool = false;
    extraGetSet: static openArray[TabGetSet] = []; namespace = JS_NULL;
    errid = Opt[JSErrorEnum].err(); ishtmldda = false): JSClassID =
  var stmts = newStmtList()
  var info = newRegistryInfo(t, name)
  if not asglobal:
    info.dfin = ident("js_" & t.strVal & "ClassCheckDestroy")
    if info.tname notin jsDtors:
      warning("No destructor has been defined for type " & info.tname)
  else:
    info.dfin = newNilLit()
    if info.tname in jsDtors:
      error("Global object " & info.tname & " must not have a destructor!")
  let pragmas = findPragmas(t)
  stmts.registerGetters(info, pragmas.jsget)
  stmts.registerSetters(info, pragmas.jsset)
  stmts.bindFunctions(info)
  stmts.bindGetSet(info)
  if hasExtraGetSet:
    #HACK: for some reason, extraGetSet gets weird contents when nothing is
    # passed to it. So we need an extra flag to signal if anything has
    # been passed to it at all.
    stmts.bindExtraGetSet(info, extraGetSet)
  let sctr = stmts.bindConstructor(info)
  if not asglobal:
    stmts.bindCheckDestroy(info)
  let endstmts = newStmtList()
  endstmts.bindEndStmts(info)
  let tabList = info.tabList
  let finName = info.finName
  let classDef = info.classDef
  let tname = info.tname
  let unforgeable = info.tabUnforgeable
  let staticfuns = info.tabStatic
  let global = asglobal and not globalparent
  endstmts.add(quote do:
    `ctx`.newJSClass(`classDef`, `tname`, getTypePtr(`t`), `sctr`, `tabList`,
      `parent`, bool(`global`), `nointerface`, `finName`, `namespace`,
      `errid`, `unforgeable`, `staticfuns`, `ishtmldda`)
  )
  stmts.add(newBlockStmt(endstmts))
  return stmts

proc getMemoryUsage*(rt: JSRuntime): string =
  var m: JSMemoryUsage
  JS_ComputeMemoryUsage(rt, m)
  template row(title: string; count, size, sz2, cnt2: int64, name: string):
      string =
    var fv = $(float(sz2) / float(cnt2))
    let i = fv.find('.')
    if i != -1:
      fv.setLen(i + 1)
    else:
      fv &= ".0"
    title & ": " & $count & " " & $size & " (" & fv & ")" & name & "\n"
  template row(title: string; count, size, sz2: int64, name: string):
      string =
    row(title, count, size, sz2, count, name)
  template row(title: string; count, size: int64, name: string): string =
    row(title, count, size, size, name)
  var s = ""
  if m.malloc_count != 0:
    s &= row("memory allocated", m.malloc_count, m.malloc_size, "/block")
    s &= row("memory used", m.memory_used_count, m.memory_used_size,
      m.malloc_size - m.memory_used_size, " average slack")
  if m.atom_count != 0:
    s &= row("atoms", m.atom_count, m.atom_size, "/atom")
  if m.str_count != 0:
    s &= row("strings", m.str_count, m.str_size, "/string")
  if m.obj_count != 0:
    s &= row("objects", m.obj_count, m.obj_size, "/object") &
      row("properties", m.prop_count, m.prop_size, m.prop_size, m.obj_count,
        "/object") &
      row("shapes", m.shape_count, m.shape_size, "/shape")
  if m.js_func_count != 0:
    s &= row("js functions", m.js_func_count, m.js_func_size, "/function")
  if m.c_func_count != 0:
    s &= "native functions: " & $m.c_func_count & "\n"
  if m.array_count != 0:
    s &= "arrays: " & $m.array_count & "\n" &
      "fast arrays: " & $m.fast_array_count & "\n" &
      row("fast array elements", m.fast_array_elements,
        m.fast_array_elements * sizeof(JSValue), m.fast_array_elements,
        m.fast_array_count, "")
  if m.binary_object_count != 0:
    s &= "binary objects: " & $m.binary_object_count & " " &
      $m.binary_object_size
  return s

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

{.pop.} # raises
