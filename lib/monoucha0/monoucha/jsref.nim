# Custom object hierarchy and ref type, implemented in QJS.
# The idea is to avoid duplicate work that would result from running both
# the QJS cycle collector and ORC.

{.push raises: [].}

import std/macrocache
import std/macros

import jsopaque
import quickjs

type
  JSRootObj* {.pure, inheritable.} = object

  JSRef*[T] = distinct ptr T

proc destroyAux(p: ptr pointer) {.exportc: "cha_jsDestroyImpl".} =
  if p[] != nil:
    when defined(debug):
      assert not globalRuntime.getOpaque().marking
    JS_FreeForeignObject(globalRuntime, p[])

proc dupAux(p: pointer): pointer {.exportc: "cha_jsDup".} =
  if p == nil:
    return nil
  when defined(debug):
    assert not globalRuntime.getOpaque().marking
  return JS_DupForeignObject(globalRuntime, p)

proc copyAux(dest: ptr pointer; r: pointer) {.exportc: "cha_jsCopyImpl".} =
  if dest[] != r:
    destroyAux(dest)
    dest[] = dupAux(r)

proc sinkAux(dest: ptr pointer; r: pointer) {.exportc: "cha_jsSinkImpl".} =
  destroyAux(dest)
  dest[] = r

proc `=destroy`[T](r: var JSRef[T]) {.
  importc: "cha_jsDestroy", header: "quickjs-aux.h".}

proc `=copy`[T](dest: var JSRef[T]; r: JSRef[T]) {.
  importc: "cha_jsCopy", header: "quickjs-aux.h".}

proc `=dup`[T](r: JSRef[T]): JSRef[T] {.
  importc: "cha_jsDup", header: "quickjs-aux.h".}

proc `=sink`[T](dest: var JSRef[T]; r: JSRef[T]) {.
  importc: "cha_jsSink", header: "quickjs-aux.h".}

type JSRootRef* = JSRef[JSRootObj]

template asRootRef*[T: JSRootObj](r: JSRef[T]): JSRootRef =
  cast[JSRootRef](r)

template markObj*[T](rt: JSRuntime; r: JSRef[T]; markFunc: JS_MarkFunc) =
  JS_MarkForeignObject(rt, cast[pointer](r), markFunc)

proc jsNew0*(p: ptr pointer; class: JSClassID; size: csize_t) =
  p[] = JS_NewForeignObject(globalRuntime, class, size)

when NimMajor >= 2:
  proc jsNewAsgn*[T](p: ptr T; x {.byref.}: sink T; len: csize_t) {.
    importc: "memcpy", header: "<string.h>".}
else:
  proc jsSinkIntoEther*[T](x: sink T) {.importc: "cha_jsSinkIntoEther",
    header: "quickjs-aux.h".}

template jsNew*[T](x: T): JSRef[T] =
  mixin getClassID
  # Can't noinit, because p can be hoisted up by Nim's asinine codegen.
  # Simply assigning to a pointer doesn't work either as that would result
  # in a dup at the end (i.e., once we cast to JSRef).
  var r: JSRef[T]
  jsNew0(cast[ptr pointer](addr r), getClassID(JSRef[T]), csize_t(sizeof(T)))
  if r != nil:
    when NimMajor < 2: # sadly, .byref won't work on sink
      var y = x
      copyMem(cast[ptr T](r), addr y, sizeof(T))
      # inhibit destroy
      jsSinkIntoEther(y)
    else:
      # In-place object construction hack: we inhibit the temporary's
      # destruction by passing it as `sink T` to memcpy.  (A sufficiently
      # advanced compiler will hopefully optimize out the temporary in most
      # cases.)
      jsNewAsgn(cast[ptr T](r), x, csize_t(sizeof(T)))
  r

when NimMajor < 2:
  var globalJSTypeMap* {.global, noinit.}: array[1024, JSClassID]

  const JSTypeCounter = CacheCounter("EnumCounter")

  proc getJSTypeID*[T: object](t: typedesc[T]): int =
    const typeId = JSTypeCounter.value
    static:
      inc JSTypeCounter
    typeId

template `==`*[T](t: typeof(nil); t2: JSRef[T]): bool =
  cast[pointer](t2) == nil

template `==`*[T](t2: JSRef[T]; t: typeof(nil)): bool =
  cast[pointer](t2) == nil

template `==`*[T; U: T](a: JSRef[T]; b: JSRef[U]): bool =
  cast[pointer](a) == cast[pointer](b)

proc isLocal(t: NimNode): bool =
  let kind = t.kind
  # fast path
  if kind == nnkSym:
    return true
  if kind == nnkCall:
    return false
  # slow path
  var t = t
  while true:
    case t.kind
    of nnkCall, nnkCast:
      # if it's a call, see below.
      # if it's a cast, preserve it.
      return true
    of nnkStmtList, nnkStmtListExpr:
      # check the last child
      t = t[^1]
    of nnkSym, nnkIdent, nnkConv, nnkDerefExpr, nnkDotExpr, nnkHiddenDeref,
        nnkBracketExpr, nnkCheckedFieldExpr:
      # if it's a symbol, see below.
      # if it's a deref, dot, or bracket expr, we don't need a decref.
      # if it's a bracket expr, that means we're accessing an array/seq,
      # which always produces lent, so we don't need decref.
      # if it's a conv, preserve it.
      break
    else:
      # might want to check if it doesn't leak...
      warning("handle kind " & $t.kind)
      break
  true

proc dotGet2*[T](r: JSRef[T]): ptr T {.gcsafe, noSideEffect,
    importc: "cha_dotGet", header: "quickjs-aux.h".}

macro dotGet(T, t: untyped): untyped =
  # Evil hack to work around compiler bugs:
  # * if t is a funcall, we have to use a cast so that we don't
  #   accidentally disarm the destroy hook.  e.g.,
  #     node.document = other.rootNode.document
  #     # if we desugar this to
  #     #   let tmp1 = (ptr NodeObj)(other)
  #     #   let tmp = (ptr NodeObj)(tmp1.rootNode)
  #     #   (ptr NodeObj)(node).document = tmp.document
  #     # then, since tmp is not considered a JSRef anymore, the
  #     # compiler won't bother unref'ing it.
  # * otherwise, t is derived from a symbol in the current scope.  in this
  #   case we we have to use a conversion to defeat move inference.  e.g.,
  #     document.window = window
  #     # if we only access window by casts from here on, it's not
  #     # accounted for in sink inference, and will get sink'ed in by the
  #     # previous assignment.
  #     window.document = document
  #   note that moves are inferred even based on object/array access
  #   so we have to be broader here.
  if isLocal(t):
    quote do:
      (ptr `T`)(`t`)
  else:
    quote do:
      cast[ptr `T`](`t`)

template `[]`*[T](r: JSRef[T]): T =
  dotGet(T, r)[]

template `[]=`*[T](a: JSRef[T]; b: T) =
  dotGet(T, a)[] = b

template `.`*[T](t: JSRef[T]; field: untyped): untyped =
  dotGet(T, t).field

template `.=`*[T](t: JSRef[T]; field, val: untyped): untyped =
  dotGet(T, t).field = val

proc ofImpl(p: pointer; tclassid: JSClassID): bool =
  if p == nil:
    return false
  var classid = JS_GetForeignClassID(p)
  let rtOpaque = globalRuntime.getOpaque()
  while classid != JS_INVALID_CLASS_ID:
    if tclassid == classid:
      return true
    classid = rtOpaque.classes[int(classid)].parent
  false

proc isForeignOf*[T](r: ptr T; classid: JSClassID): bool =
  ofImpl(cast[pointer](r), classid)

template `of`*[T; U: T](r: JSRef[T]; u: typedesc[JSRef[U]]): bool =
  mixin getClassID
  ofImpl(cast[pointer](r), getClassID(JSRef[U]))

proc sameClass*[T, U](a: JSRef[T]; b: JSRef[U]): bool =
  let aclass = JS_GetForeignClassID(cast[pointer](a))
  let bclass = JS_GetForeignClassID(cast[pointer](b))
  return aclass == bclass

proc asImpl(p: pointer; classid: JSClassID): pointer =
  if ofImpl(p, classid):
    return p
  nil

template `as`*[T; U: T](r: JSRef[T]; u: typedesc[JSRef[U]]): JSRef[U] =
  mixin getClassID
  cast[u](asImpl(cast[pointer](r), getClassID(JSRef[U])))

{.pop.}
