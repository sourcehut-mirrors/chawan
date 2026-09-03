{.push raises: [].}

when NimMajor >= 2:
  import std/assertions
import std/algorithm

import js/constcharp
import js/jstypes
import js/quickjs
import utils/cowstr
import utils/opt
import utils/twtstr

type
  JSStrRef* = enum
    jstAcceptNode = "acceptNode"
    jstBuffer = "buffer"
    jstButton = "button"
    jstConfig = "config"
    jstContentType = "contentType"
    jstCrypto = "crypto"
    jstDisabledFeatures = "disabledFeatures"
    jstDone = "done"
    jstEntries = "entries"
    jstForEach = "forEach"
    jstHandleEvent = "handleEvent"
    jstHash = "hash"
    jstHistory = "history"
    jstHost = "host"
    jstHostname = "hostname"
    jstHref = "href"
    jstKeys = "keys"
    jstLength = "length"
    jstLocale = "locale"
    jstLocation = "location"
    jstMain = "main"
    jstMimeTypes = "mimeTypes"
    jstMods = "mods"
    jstName = "name"
    jstNavigator = "navigator"
    jstNext = "next"
    jstObservedAttributes = "observedAttributes"
    jstOpen = "open"
    jstOptions = "options"
    jstOrigin = "origin"
    jstPassword = "password"
    jstPathname = "pathname"
    jstPermissions = "permissions"
    jstPlugins = "plugins"
    jstPort = "port"
    jstPrompt = "prompt"
    jstProtocol = "protocol"
    jstPrototype = "prototype"
    jstRandomUUID = "randomUUID"
    jstScreen = "screen"
    jstSearch = "search"
    jstSelected = "selected"
    jstT = "t"
    jstUrl = "url"
    jstUsername = "username"
    jstValue = "value"
    jstValues = "values"
    jstX = "x"
    jstY = "y"
    jsyIterator = "iterator" # must be the first symbol
    jsyToStringTag = "toStringTag"
    jszSearchParams

  JSFunctionRef* = enum
    jsfArrayPrototypeForEach = "Array.prototype.forEach"
    jsfArrayPrototypeEntries = "Array.prototype.entries"
    jsfArrayPrototypeKeys = "Array.prototype.keys"
    jsfArrayPrototypeValues = "Array.prototype.values"
    jsfObjectPrototypeValueOf = "Object.prototype.valueOf"
    jsfSet = "Set"
    jsfFunction = "Function"

  JSObjectRef* = enum
    jsoIteratorPrototype = "Iterator.prototype"

  BoundRefDestructor* = proc(x: pointer) {.nimcall, raises: [].}

  JSClassData* = object
    parent*: JSClassID
    raw*: bool
    initialized*: bool
    final*: bool
    # Parent unforgeables are merged on class creation.
    # (i.e. to set all unforgeables on the prototype chain, it is enough to set)
    # `unforgeable[classid]'.)
    unforgeable*: seq[JSCFunctionListEntry]
    fins*: seq[ChaFinalizerFunction]
    marks*: seq[ChaMarkFunction]
    name*: cstring

  JSContextOpaqueObj* = object
    gclass*: JSClassID # class ID of the global object
    ctors*: seq[JSObject] # class ID -> constructor
    global*: JSObject
    strRefs: array[JSStrRef, JSAtom]
    funRefs*: array[JSFunctionRef, JSCallback]
    objRefs*: array[JSObjectRef, JSObject]
    globalObj*: pointer

  JSContextOpaque* = ptr JSContextOpaqueObj

  ChaFinalizerFunction* = proc(rt: JSRuntime; this: pointer) {.nimcall,
    raises: [].}

  ChaMarkFunction* = proc(rt: JSRuntime; this: pointer;
    markFun: JS_MarkFunc) {.nimcall, raises: [].}

  EnumMapItem* = object
    atom*: JSAtom
    n*: int32

  EnumMapEntry* = object
    atoms*: seq[JSAtom] # enum number -> atom
    enums*: seq[EnumMapItem] # atom number -> enum

  JSTaskSource* = enum
    jtsPermission
    jtsPostMessage
    jtsFileReader
    jtsDOMManipulation

  JSTaskEnv* = ref object of RootObj #TODO JSRoot?

  #TODO return JSCode?
  JSTaskCallback* = proc(ctx: JSContext; env: JSTaskEnv): Opt[void] {.
    nimcall, raises: [].}

  JSTask* = ref JSTaskObj

  JSTaskObj = object
    ctx*: JSContext
    source*: JSTaskSource
    env*: JSTaskEnv
    cb*: JSTaskCallback
    next: JSTask

  JSRuntimeOpaqueObj* = object
    classes*: seq[JSClassData] # JSClassID -> data
    enumMap*: seq[EnumMapEntry]
    tasksHead*: JSTask
    tasksTail*: JSTask
    load: int
    mutationJobQueued*: bool
    inMicrotaskCheckpoint*: bool
    inScript*: bool
    logExceptionCb*: proc(ctx: JSContext) {.nimcall, raises: [].}
    when defined(debug):
      marking*: bool

  JSRuntimeOpaque* = ptr JSRuntimeOpaqueObj

iterator finalizers*(rtOpaque: JSRuntimeOpaque; classid: JSClassID):
    ChaFinalizerFunction =
  let classid = int(classid)
  if classid < rtOpaque.classes.len:
    for fin in rtOpaque.classes[classid].fins.ritems:
      yield fin

iterator marks*(rtOpaque: JSRuntimeOpaque; classid: JSClassID):
    ChaMarkFunction =
  let classid = int(classid)
  if classid < rtOpaque.classes.len:
    for mark in rtOpaque.classes[classid].marks.ritems:
      yield mark

proc `=destroy`*(task: var JSTaskObj) =
  JS_FreeContext(task.ctx)

# hooks for cowstr
proc freeCString(p: cstring) {.exportc: "cha_$1".} =
  JS_FreeCStringRT(globalRuntime, cstringConst(p))

proc dupCString(p: cstring): cstring {.exportc: "cha_$1".} =
  cstring(JS_DupCStringRT(globalRuntime, cstringConst(p)))

proc getParent*(rtOpaque: JSRuntimeOpaque; class: JSClassID): JSClassID =
  rtOpaque.classes[int(class)].parent

proc newJSContextOpaque*(ctx: JSContext): JSContextOpaque =
  let opaque = create(JSContextOpaqueObj)
  opaque.global = traceObj(JS_GetGlobalObject(ctx))
  var fail = false
  for s in JSStrRef.low..jsyIterator.pred:
    let ss = $s
    let atom = JS_NewAtomLen(ctx, ss.toCStringConst, csize_t(ss.len))
    if atom == JS_ATOM_NULL:
      fail = true
    opaque.strRefs[s] = atom
  let sym = JS_GetPropertyStr(ctx, opaque.global.value, cstringConst("Symbol"))
  if not JS_IsException(sym.vc):
    for s in jsyIterator..<jszSearchParams:
      let val = JS_GetPropertyStr(ctx, sym.vc, s.toStr().toCStringConst())
      if not JS_IsException(val.vc):
        opaque.strRefs[s] = JS_ValueToAtom(ctx, val.vc)
        JS_FreeValue(ctx, val)
      else:
        fail = true
    JS_FreeValue(ctx, sym)
  else:
    fail = true
  for s in jszSearchParams..JSStrRef.high:
    let val = JS_NewPrivateSymbol(ctx)
    if not JS_IsException(val.vc):
      opaque.strRefs[s] = JS_ValueToAtom(ctx, val.vc)
      JS_FreeValue(ctx, val)
    else:
      fail = true
  for s, it in opaque.objRefs.mpairs:
    let ss = $s
    let val = JS_Eval(ctx, ss.toCStringConst, csize_t(ss.len),
      cstringConst("<init>"), 0)
    if not JS_IsException(val.vc):
      assert JS_IsObject(val.vc)
      it = traceObj(val)
    else:
      fail = true
  for s, it in opaque.funRefs.mpairs:
    let ss = $s
    let val = JS_Eval(ctx, ss.toCStringConst, csize_t(ss.len),
      cstringConst("<init>"), 0)
    if not JS_IsException(val.vc):
      assert JS_IsFunction(ctx, val.vc)
      it = traceCallback(val)
    else:
      fail = true
  if fail:
    {.cast(raises: [])}:
      `=destroy`(opaque[])
    return nil
  return opaque

proc getOpaque*(ctx: JSContext): JSContextOpaque =
  return cast[JSContextOpaque](JS_GetContextOpaque(ctx))

proc getOpaque*(rt: JSRuntime): JSRuntimeOpaque =
  return cast[JSRuntimeOpaque](JS_GetRuntimeOpaque(rt))

proc getOpaque*(val: JSValueConst): pointer =
  if JS_VALUE_GET_TAG(val) == JS_TAG_OBJECT:
    return JS_GetOpaque(val, JS_GetClassID(val))
  return nil

proc putEnums0(ctx: JSContext; entry: var EnumMapEntry;
    atoms: openArray[string]): bool =
  entry.enums = newSeqOfCap[EnumMapItem](atoms.len)
  if entry.atoms.len < atoms.len:
    entry.atoms.setLen(atoms.len)
  for i in 0'i32 ..< int32(atoms.len):
    let atom = JS_NewAtomLen(ctx, cstringConst(atoms[i]),
      csize_t(atoms[i].len))
    if atom == JS_ATOM_NULL:
      return false
    if entry.atoms[i] == JS_ATOM_NULL:
      entry.atoms[i] = atom
    entry.enums.add(EnumMapItem(n: i, atom: atom))
  entry.enums.sort(proc(x, y: EnumMapItem): int {.nimcall.} =
    cmp(uint32(x.atom), uint32(y.atom))
  )
  true

proc putEnums*(ctx: JSContext; enumId: int; atoms: openArray[string]): bool =
  let rtOpaque = JS_GetRuntime(ctx).getOpaque()
  if enumId >= rtOpaque.enumMap.len:
    rtOpaque.enumMap.setLen(enumId + 1)
  if rtOpaque.enumMap[enumId].enums.len == atoms.len:
    return true
  ctx.putEnums0(rtOpaque.enumMap[enumId], atoms)

proc getName*(rt: JSRuntime; classid: JSClassID): string =
  $rt.getOpaque().classes[int(classid)].name

proc getAtom*(ctx: JSContext; jst: JSStrRef): lent JSAtom =
  ctx.getOpaque().strRefs[jst]

proc queueTask2(rtOpaque: JSRuntimeOpaque; task: sink JSTask) =
  if rtOpaque.tasksTail == nil:
    rtOpaque.tasksHead = task
  else:
    rtOpaque.tasksTail.next = task
  rtOpaque.tasksTail = task

proc queueTask*(ctx: JSContext; source: JSTaskSource; cb: JSTaskCallback;
    env: JSTaskEnv): Opt[void] =
  let rt = JS_GetRuntime(ctx)
  let rtOpaque = rt.getOpaque()
  let task = JSTask(ctx: JS_DupContext(ctx), source: source, env: env, cb: cb)
  rtOpaque.queueTask2(task)
  ok() # in case we ever want to handle OOM

proc popTask*(rt: JSRuntime): JSTask =
  let rtOpaque = rt.getOpaque()
  let task = move(rtOpaque.tasksHead)
  if task != nil:
    rtOpaque.tasksHead = move(task.next)
    if rtOpaque.tasksHead == nil:
      rtOpaque.tasksTail = nil
  task

proc removeTasks*(rt: JSRuntime; source: JSTaskSource) =
  #TODO use filterTasks instead
  let rtOpaque = rt.getOpaque()
  var it = move(rtOpaque.tasksHead)
  rtOpaque.tasksTail = nil
  while it != nil:
    let next = move(it.next)
    if it.source != source:
      rtOpaque.queueTask2(it)
    it = next

type FilterFun = proc(env: JSTaskEnv; opaque: RootRef): bool {.
  nimcall, raises: [].}

proc filterTasks*(rt: JSRuntime; cb: FilterFun; opaque: RootRef) =
  ## remove tasks for which `cb' returns true
  let rtOpaque = rt.getOpaque()
  var it = move(rtOpaque.tasksHead)
  rtOpaque.tasksTail = nil
  while it != nil:
    let next = move(it.next)
    if not cb(it.env, opaque):
      rtOpaque.queueTask2(it)
    it = next

proc runMicrotasks*(rt: JSRuntime) =
  let rtOpaque = rt.getOpaque()
  if not rtOpaque.inMicrotaskCheckpoint:
    rtOpaque.inMicrotaskCheckpoint = true
    while JS_IsJobPending(rt) != 0:
      var ctx: JSContext
      let r = JS_ExecutePendingJob(rt, ctx)
      if r < 0 and ctx != nil and rtOpaque.logExceptionCb != nil:
        #TODO QJS says ctx is deprecated, but I'm not sure if we can log
        # all exceptions otherwise.  (Maybe it's possible with the promise
        # tracker + doing it on our side otherwise?)
        rtOpaque.logExceptionCb(ctx)
    rtOpaque.inMicrotaskCheckpoint = false

proc cleanUpScript*(rt: JSRuntime; prevInScript: bool) =
  rt.getOpaque().inScript = prevInScript
  if not prevInScript:
    rt.runMicrotasks()

proc cleanUpCallback*(rt: JSRuntime; prevInScript: bool) =
  # same as cleanUpScript for now; in the spec it handles the incumbent
  # settings object
  rt.cleanUpScript(prevInScript)

proc hasTasksOrJobs*(rt: JSRuntime): bool =
  JS_IsJobPending(rt) != 0 or rt.getOpaque().tasksHead != nil

{.pop.} # raises
