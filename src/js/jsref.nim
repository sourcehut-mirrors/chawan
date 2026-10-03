# Custom object hierarchy and ref type, implemented in QJS.
# The idea is to avoid duplicate work that would result from running both
# the QJS cycle collector and ORC.

{.push raises: [].}

import std/macrocache

import js/jsopaque
import js/jstypes
import js/quickjs

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

proc `=destroy`*[T](r: var JSRef[T]) {.
  importc: "cha_jsDestroy", header: "quickjs-aux.h".}

proc `=copy`*[T](dest: var JSRef[T]; r: JSRef[T]) {.
  importc: "cha_jsCopy", header: "quickjs-aux.h".}

proc `=dup`*[T](r: JSRef[T]): JSRef[T] {.
  importc: "cha_jsDup", header: "quickjs-aux.h".}

proc `=sink`*[T](dest: var JSRef[T]; r: JSRef[T]) {.
  importc: "cha_jsSink", header: "quickjs-aux.h".}

type JSRootRef* = JSRef[JSRootObj]

template asRootRef*[T: JSRootObj](r: JSRef[T]): JSRootRef =
  JSRootRef(r)

template markObj*[T](rt: JSRuntime; r: JSRef[T]; markFunc: JS_MarkFunc) =
  JS_MarkForeignObject(rt, dotGet(ptr T, r), markFunc)

template setMagic*[T](r: JSRef[T]; magic: uint32) =
  JS_SetForeignMagic(dotGet(ptr T, r), magic)

template getMagic*[T](r: JSRef[T]): uint32 =
  JS_GetForeignMagic(dotGet(ptr T, r))

proc jsNew0(p: ptr pointer; class: JSClassID; size: csize_t) =
  p[] = JS_NewForeignObject(globalRuntime, class, size)

template jsNewOf*[T](x: T; classid: JSClassID): JSRef[T] =
  ## Create a new JSForeignObject with a specific classid.  Useful if you
  ## want to instantiate a fake subclass.
  # Can't noinit, because p can be hoisted up by Nim's asinine codegen.
  # Simply assigning to a pointer doesn't work either as that would result
  # in a dup at the end (i.e., once we cast to JSRef).
  var r: JSRef[T]
  jsNew0(cast[ptr pointer](addr r), classid, csize_t(sizeof(T)))
  if r != nil:
    # Assign x to a temporary, copy it to the pointer, then inhibit its
    # destruction.  Effectively this is the same as storing it there,
    # but it avoids an unnecessary =destroy call.
    var y = x
    copyMem(cast[ptr T](r), addr y, sizeof(T))
    # inhibit destroy
    {.cast(raises: []).}:
      wasMoved(y)
  r

template jsNew*[T](x: T): JSRef[T] =
  ## Create a new JSForeignObject.  The class id is derived from the
  ## getClassID procedure, so to use this before the class definition,
  ## you have to forward-declare getClassID.
  mixin getClassID
  jsNewOf(x, getClassID(JSRef[T]))

when NimMajor < 2:
  var globalJSTypeMap* {.global, noinit.}: array[1024, JSClassID]

  const JSTypeCounter = CacheCounter("JSTypeCounter")

  proc getJSTypeID*[T: object](t: typedesc[T]): int =
    const typeId = JSTypeCounter.value
    static:
      inc JSTypeCounter
    typeId

template `==`*[T](t: typeof(nil); t2: JSRef[T]): bool =
  dotGet(ptr T, t2) == nil

template `==`*[T](t2: JSRef[T]; t: typeof(nil)): bool =
  dotGet(ptr T, t2) == nil

template `==`*[T; U: T](a: JSRef[T]; b: JSRef[U]): bool =
  dotGet(ptr T, a) == dotGet(ptr U, b)

template `[]`*[T](r: JSRef[T]): T =
  dotGet(ptr T, r)[]

template `[]=`*[T](a: JSRef[T]; b: T) =
  dotGet(ptr T, a)[] = b

template `.`*[T](t: JSRef[T]; field: untyped): untyped =
  dotGet(ptr T, t).field

template `.=`*[T](t: JSRef[T]; field, val: untyped): untyped =
  dotGet(ptr T, t).field = val

proc ofImpl(p: pointer; tclassid: JSClassID): bool =
  if p == nil:
    return false
  let rtOpaque = globalRuntime.getOpaque()
  var classid = JS_GetForeignClassID(p)
  if rtOpaque.classes[int(tclassid)].final:
    return classid == tclassid
  while true:
    if tclassid == classid:
      return true
    classid = rtOpaque.classes[int(classid)].parent
    if classid == JS_INVALID_CLASS_ID:
      break
  false

template `of`*[T; U: T](r: JSRef[T]; u: typedesc[JSRef[U]]): bool =
  mixin getClassID
  ofImpl(dotGet(ptr T, r), getClassID(JSRef[U]))

proc sameClass*[T, U](a: JSRef[T]; b: JSRef[U]): bool =
  let aclass = JS_GetForeignClassID(addr a[])
  let bclass = JS_GetForeignClassID(addr b[])
  return aclass == bclass

proc asImpl(p: pointer; classid: JSClassID): pointer =
  if ofImpl(p, classid):
    return p
  nil

template `as`*[T; U: T](r: JSRef[T]; u: typedesc[JSRef[U]]): JSRef[U] =
  mixin getClassID
  cast[u](asImpl(dotGet(ptr T, r), getClassID(JSRef[U])))

{.pop.}
