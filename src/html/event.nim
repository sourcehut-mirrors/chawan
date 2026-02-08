{.push raises: [].}

import std/options

import html/catom
import html/domexception
import html/script
import io/timeout
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsnull
import monoucha/jstypes
import monoucha/jsutils
import monoucha/quickjs
import monoucha/tojs
import types/jsopt
import types/opt
import utils/twtstr

type
  EventPhase = enum
    NONE = 0u16
    CAPTURING_PHASE = 1u16
    AT_TARGET = 2u16
    BUBBLING_PHASE = 3u16

  EventFlag* = enum
    efStopPropagation
    efStopImmediatePropagation
    efCanceled
    efInPassiveListener
    efComposed
    efInitialized
    efDispatch

  Event* = ref object of RootObj
    ctype* {.jsget: "type".}: CAtom
    target* {.jsget.}: EventTarget
    currentTarget* {.jsget.}: EventTarget
    eventPhase {.jsget.}: uint16
    bubbles {.jsget.}: bool
    cancelable {.jsget.}: bool
    flags*: set[EventFlag]
    isTrusted* {.jsufget.}: bool
    timeStamp {.jsget.}: float64

  CustomEvent* = ref object of Event
    detail {.jsget.}: JSValue

  MessageEvent* = ref object of Event
    data {.jsget.}: JSValue
    origin {.jsget.}: string

  SubmitEvent* = ref object of Event
    submitter {.jsget.}: EventTarget

  UIEvent* = ref object of Event
    detail {.jsget.}: int32
    view {.jsget.}: EventTarget

  MouseEvent* = ref object of UIEvent
    screenX {.jsget.}: int32
    screenY {.jsget.}: int32
    clientX {.jsget, jsget: "x".}: int32
    clientY {.jsget, jsget: "y".}: int32
    button {.jsget.}: int16
    buttons {.jsget.}: uint16
    ctrlKey {.jsget.}: bool
    shiftKey {.jsget.}: bool
    altKey {.jsget.}: bool
    metaKey {.jsget.}: bool
    relatedTarget {.jsget.}: EventTarget
    #TODO and the others

  InputEvent* = ref object of UIEvent
    data {.jsget.}: Option[string]
    isComposing {.jsget.}: bool
    inputType {.jsget.}: string

  EventTarget* = ref object of RootObj
    eventListener: EventListener

  EventListener {.acyclic.} = ref object
    # if callback is undefined, the listener has been removed
    callback: JSValue
    ctype: CAtom
    capture: bool
    once: bool
    internal: bool
    passive: bool
    next: EventListener
    signal: AbortSignal

  AbortSignal = ref object of EventTarget
    reason {.jsget.}: JSValue
    aborted {.jsget.}: bool
    abortSteps: seq[JSValue]
    #TODO source/dependent signals

  AbortController = ref object
    signal {.jsget.}: AbortSignal

jsDestructor(Event)
jsDestructor(CustomEvent)
jsDestructor(MessageEvent)
jsDestructor(SubmitEvent)
jsDestructor(UIEvent)
jsDestructor(MouseEvent)
jsDestructor(InputEvent)
jsDestructor(EventTarget)
jsDestructor(AbortSignal)
jsDestructor(AbortController)

# Forward declaration hack
var isDefaultPassiveImpl*: proc(target: EventTarget): bool {.nimcall,
  raises: [].}
var getParentImpl*: proc(ctx: JSContext; target: EventTarget; isLoad: bool):
  EventTarget {.nimcall, raises: [].}
var isWindowImpl*: proc(target: EventTarget): bool {.nimcall, raises: [].}
var isHTMLElementImpl*: proc(target: EventTarget): bool {.nimcall, raises: [].}
var setEventImpl*: proc(ctx: JSContext; event: Event): Event {.
  nimcall, raises: [].}

# Forward declarations
proc removeEventListener(ctx: JSContext; eventTarget: EventTarget;
  ctype: CAtom; callback: JSValueConst; options: JSValueConst = JS_UNDEFINED):
  Opt[void]

iterator eventListeners(this: EventTarget): EventListener =
  var it = this.eventListener
  while it != nil:
    yield it
    it = it.next

proc finalize(rt: JSRuntime; target: EventTarget) {.jsfin.} =
  # Can't take rt as param here, because elements may be unbound in JS.
  for el in target.eventListeners:
    JS_FreeValueRT(rt, el.callback)

proc mark(rt: JSRuntime; target: EventTarget; markFunc: JS_MarkFunc)
    {.jsmark.} =
  for el in target.eventListeners:
    JS_MarkValue(rt, el.callback, markFunc)

type
  EventInit* = object of JSDict
    bubbles* {.jsdefault.}: bool
    cancelable* {.jsdefault.}: bool
    composed* {.jsdefault.}: bool

  CustomEventInit = object of EventInit
    detail {.jsdefault: JS_NULL.}: JSValueConst

  MessageEventInit* = object of EventInit
    data* {.jsdefault: JS_NULL.}: JSValueConst
    origin {.jsdefault.}: string
    lastEventId {.jsdefault.}: string

# Event
proc innerEventCreationSteps*(event: Event; eventInitDict: EventInit) =
  event.flags = {efInitialized}
  #TODO this should measure time starting from when the script was started.
  event.timeStamp = float64(getUnixMillis())
  event.bubbles = eventInitDict.bubbles
  event.cancelable = eventInitDict.cancelable
  if eventInitDict.composed:
    event.flags.incl(efComposed)

#TODO eventInitDict type
proc newEvent(ctx: JSContext; ctype: CAtom; eventInitDict = EventInit()):
    Event {.jsctor.} =
  let event = Event(ctype: ctype)
  event.innerEventCreationSteps(eventInitDict)
  return event

proc newEvent*(ctype: CAtom; target: EventTarget; bubbles, cancelable: bool):
    Event =
  return Event(
    ctype: ctype,
    target: target,
    currentTarget: target,
    bubbles: bubbles,
    cancelable: cancelable
  )

proc initialize(this: Event; ctype: CAtom; bubbles, cancelable: bool) =
  this.flags.incl(efInitialized)
  this.isTrusted = false
  this.target = nil
  this.ctype = ctype
  this.bubbles = bubbles
  this.cancelable = cancelable

proc initEvent(this: Event; ctype: CAtom; bubbles, cancelable: bool)
    {.jsfunc.} =
  if efDispatch notin this.flags:
    this.initialize(ctype, bubbles, cancelable)

proc srcElement(this: Event): EventTarget {.jsfget.} =
  return this.target

#TODO shadow DOM etc.
proc composedPath(this: Event): seq[EventTarget] {.jsfunc.} =
  if this.currentTarget == nil:
    return newSeq[EventTarget]()
  return @[this.currentTarget]

proc stopPropagation(this: Event) {.jsfunc.} =
  this.flags.incl(efStopPropagation)

proc cancelBubble(this: Event): bool {.jsfget.} =
  return efStopPropagation in this.flags

proc `cancelBubble=`(this: Event; cancel: bool) {.jsfset: "cancelBubble".} =
  if cancel:
    this.stopPropagation()

proc stopImmediatePropagation(this: Event) {.jsfunc.} =
  this.flags.incl({efStopPropagation, efStopImmediatePropagation})

proc preventDefault(this: Event) {.jsfunc.} =
  if this.cancelable and efInPassiveListener notin this.flags:
    this.flags.incl(efCanceled)

proc returnValue(this: Event): bool {.jsfget.} =
  return efCanceled notin this.flags

proc `returnValue=`(this: Event; value: bool) {.jsfset: "returnValue".} =
  if not value:
    this.preventDefault()

proc defaultPrevented(this: Event): bool {.jsfget.} =
  return efCanceled in this.flags

proc composed(this: Event): bool {.jsfget.} =
  return efComposed in this.flags

# CustomEvent
proc newCustomEvent*(ctx: JSContext; ctype: CAtom;
    eventInitDict = CustomEventInit(detail: JS_NULL)): CustomEvent {.jsctor.} =
  let event = CustomEvent(
    ctype: ctype,
    detail: JS_DupValue(ctx, eventInitDict.detail)
  )
  event.innerEventCreationSteps(EventInit(eventInitDict))
  return event

proc finalize(rt: JSRuntime; this: CustomEvent) {.jsfin.} =
  JS_FreeValueRT(rt, this.detail)

proc mark(rt: JSRuntime; this: CustomEvent; markFun: JS_MarkFunc) {.jsmark.} =
  JS_MarkValue(rt, this.detail, markFun)

proc initCustomEvent(ctx: JSContext; this: CustomEvent; ctype: CAtom;
    bubbles, cancelable: bool; detail: JSValueConst) {.jsfunc.} =
  if efDispatch notin this.flags:
    if efInitialized notin this.flags:
      JS_FreeValue(ctx, this.detail)
    this.detail = JS_DupValue(ctx, detail)
    this.initialize(ctype, bubbles, cancelable)

# MessageEvent
proc newMessageEvent*(ctx: JSContext; ctype: CAtom;
    eventInit = MessageEventInit(data: JS_NULL)): MessageEvent =
  let event = MessageEvent(
    ctype: ctype,
    data: JS_DupValue(ctx, eventInit.data),
    origin: eventInit.origin
  )
  event.innerEventCreationSteps(EventInit(eventInit))
  return event

proc finalize(rt: JSRuntime; this: MessageEvent) {.jsfin.} =
  JS_FreeValueRT(rt, this.data)

proc mark(rt: JSRuntime; this: MessageEvent; markFun: JS_MarkFunc) {.jsmark.} =
  JS_MarkValue(rt, this.data, markFun)

# SubmitEvent
type EventTargetHTMLElement* = distinct EventTarget
proc fromJS(ctx: JSContext; val: JSValueConst; res: var EventTargetHTMLElement):
    FromJSResult =
  var res0: EventTarget
  ?ctx.fromJS(val, res0)
  if not res0.isHTMLElementImpl():
    JS_ThrowTypeError(ctx, "HTMLElement expected")
    return fjErr
  res = EventTargetHTMLElement(res0)
  fjOk

type SubmitEventInit* = object of EventInit
  submitter* {.jsdefault.}: EventTargetHTMLElement

proc newSubmitEvent*(ctype: CAtom; eventInit = SubmitEventInit()): SubmitEvent
    {.jsctor.} =
  let event = SubmitEvent(
    ctype: ctype,
    submitter: EventTarget(eventInit.submitter)
  )
  event.innerEventCreationSteps(EventInit(eventInit))
  return event

# UIEvent
type EventTargetWindow* = distinct EventTarget
proc fromJS(ctx: JSContext; val: JSValueConst; res: var EventTargetWindow):
    FromJSResult =
  var res0: EventTarget
  ?ctx.fromJS(val, res0)
  if not res0.isWindowImpl():
    JS_ThrowTypeError(ctx, "Window expected")
    return fjErr
  res = EventTargetWindow(res0)
  fjOk

type UIEventInit = object of EventInit
  view* {.jsdefault.}: EventTargetWindow
  detail* {.jsdefault.}: int32

proc newUIEvent*(ctype: CAtom; eventInit = UIEventInit()): UIEvent {.jsctor.} =
  let event = UIEvent(
    ctype: ctype,
    view: EventTarget(eventInit.view),
    detail: eventInit.detail
  )
  event.innerEventCreationSteps(EventInit(eventInit))
  return event

proc initUIEvent(this: UIEvent; ctype: CAtom; bubbles = false;
    cancelable = false; view = none(EventTarget); detail = 0i32) {.jsfunc.} =
  this.ctype = ctype
  this.bubbles = bubbles
  this.cancelable = cancelable
  this.view = view.get(nil)
  this.detail = detail

type EventModifierInit = object of UIEventInit
  ctrlKey {.jsdefault.}: bool
  shiftKey {.jsdefault.}: bool
  altKey {.jsdefault.}: bool
  metaKey {.jsdefault.}: bool
  #TODO and the others...

# MouseEvent
type MouseEventInit* = object of EventModifierInit
  screenX* {.jsdefault.}: int32
  screenY* {.jsdefault.}: int32
  clientX* {.jsdefault.}: int32
  clientY* {.jsdefault.}: int32
  button* {.jsdefault.}: int16
  buttons* {.jsdefault.}: uint16
  relatedTarget {.jsdefault.}: Option[EventTarget]

proc newMouseEvent*(ctype: CAtom; eventInit = MouseEventInit()): MouseEvent
    {.jsctor.} =
  let event = MouseEvent(
    ctype: ctype,
    view: EventTarget(eventInit.view),
    screenX: eventInit.screenX,
    screenY: eventInit.screenY,
    clientX: eventInit.clientX,
    clientY: eventInit.clientY,
    ctrlKey: eventInit.ctrlKey,
    shiftKey: eventInit.shiftKey,
    altKey: eventInit.altKey,
    metaKey: eventInit.metaKey,
    button: cast[int16](eventInit.button),
    buttons: uint16(eventInit.buttons),
    relatedTarget: eventInit.relatedTarget.get(nil)
  )
  event.innerEventCreationSteps(EventInit(eventInit))
  return event

# InputEvent
type InputEventInit* = object of UIEventInit
  data* {.jsdefault.}: Option[string]
  isComposing* {.jsdefault.}: bool
  inputType* {.jsdefault.}: string

proc newInputEvent*(ctype: CAtom; eventInit = InputEventInit()): InputEvent =
  let event = InputEvent(
    ctype: ctype,
    view: EventTarget(eventInit.view),
    data: eventInit.data,
    isComposing: eventInit.isComposing,
    inputType: eventInit.inputType,
    detail: eventInit.detail
  )
  event.innerEventCreationSteps(EventInit(eventInit))
  return event

# EventTarget
proc newEventTarget(): EventTarget {.jsctor.} =
  return EventTarget()

proc defaultPassiveValue(ctype: CAtom; eventTarget: EventTarget): bool =
  const check = [satTouchstart, satTouchmove, satWheel, satMousewheel]
  return ctype.toStaticAtom() in check and eventTarget.isDefaultPassiveImpl()

proc findEventListener(ctx: JSContext; eventTarget: EventTarget; ctype: CAtom;
    callback: JSValueConst; capture: bool): EventListener =
  for it in eventTarget.eventListeners:
    if not it.internal and it.ctype == ctype and
        ctx.strictEquals(it.callback, callback) and it.capture == capture:
      return it
  nil

proc hasEventListener*(eventTarget: EventTarget; ctype: CAtom): bool =
  for it in eventTarget.eventListeners:
    if it.ctype == ctype:
      return true
  false

# EventListener
proc invoke(ctx: JSContext; listener: EventListener; event: Event): JSValue =
  if JS_IsNull(listener.callback):
    return JS_UNDEFINED
  let jsTarget = ctx.toJS(event.currentTarget)
  if JS_IsException(jsTarget):
    return JS_EXCEPTION
  let jsEvent = ctx.toJS(event)
  if JS_IsException(jsEvent):
    JS_FreeValue(ctx, jsTarget)
    return JS_EXCEPTION
  var ret = JS_UNINITIALIZED
  if JS_IsFunction(ctx, listener.callback):
    # Apparently it's a bad idea to call a function that can then delete
    # the reference it was called from (hence the dup).
    let callback = JS_DupValue(ctx, listener.callback)
    ret = ctx.callFree(callback, jsTarget, jsEvent)
  else:
    assert JS_IsObject(listener.callback)
    ret = JS_GetPropertyStr(ctx, listener.callback, "handleEvent")
    if not JS_IsException(ret):
      ret = ctx.callFree(ret, jsTarget, jsEvent)
  JS_FreeValue(ctx, jsTarget)
  JS_FreeValue(ctx, jsEvent)
  return ret

proc removeEventListenerData(ctx: JSContext; _: JSValueConst;
    argc: cint; argv: JSValueConstArray; margic: cint;
    funcData: JSValueConstArray): JSValue {.cdecl.} =
  var this: EventTarget
  ?ctx.fromJS(funcData[0], this)
  var ctype: CAtom
  ?ctx.fromJS(funcData[1], ctype)
  if ctx.removeEventListener(this, ctype, funcData[2], funcData[3]).isErr:
    return JS_EXCEPTION
  return JS_UNDEFINED

# shared
proc addEventListener(ctx: JSContext; target: EventTarget; ctype: CAtom;
    capture, once, internal: bool; passive: Option[bool];
    callback: JSValueConst; signal: AbortSignal): Opt[void] =
  if signal != nil and signal.aborted or JS_IsUndefined(callback):
    return ok()
  let passive = passive.get(defaultPassiveValue(ctype, target))
  if ctx.findEventListener(target, ctype, callback, capture) == nil: # dedup
    let listener = EventListener(
      ctype: ctype,
      capture: capture,
      once: once,
      internal: internal,
      passive: passive,
      callback: JS_DupValue(ctx, callback),
      next: target.eventListener,
      signal: signal
    )
    target.eventListener = listener
    if signal != nil:
      let jsTarget = ctx.toJS(target)
      if JS_IsException(jsTarget):
        return err()
      let jsType = ctx.toJS(ctype)
      if JS_IsException(jsType):
        JS_FreeValue(ctx, jsTarget)
        return err()
      let jsCapture = ctx.toJS(capture)
      let data = [jsTarget, jsType, JS_DupValue(ctx, callback), jsCapture]
      let fun = JS_NewCFunctionData(ctx, removeEventListenerData, 0, 0, 4,
        data.toJSValueArray())
      ctx.freeValues(data)
      if JS_IsException(fun):
        return err()
      signal.abortSteps.add(fun)
  ok()

proc flatten(ctx: JSContext; options: JSValueConst): Opt[bool] =
  var res = false
  if JS_IsBool(options):
    ?ctx.fromJS(options, res)
  elif JS_IsObject(options):
    discard ?ctx.fromJSGetProp(options, "capture", res)
  ok(res)

type FlattenMoreResult = object
  capture: bool
  once: bool
  passive: Option[bool]
  signal: AbortSignal

proc flattenMore(ctx: JSContext; options: JSValueConst;
    res: var FlattenMoreResult): Opt[void] =
  let capture = ?ctx.flatten(options)
  var once = false
  var passive = none(bool)
  var signal: AbortSignal = nil
  if JS_IsObject(options):
    discard ?ctx.fromJSGetProp(options, "once", once)
    var res: bool
    if ?ctx.fromJSGetProp(options, "passive", res):
      passive = some(res)
    discard ?ctx.fromJSGetProp(options, "signal", signal)
  res = FlattenMoreResult(
    capture: capture,
    once: once,
    passive: passive,
    signal: signal
  )
  ok()

proc removeInternalEventListener(ctx: JSContext; eventTarget: EventTarget;
    ctype: StaticAtom) =
  var prev: EventListener = nil
  for it in eventTarget.eventListeners:
    if it.ctype == ctype and it.internal:
      let callback = it.callback
      it.callback = JS_UNDEFINED
      JS_FreeValue(ctx, callback)
      if prev == nil:
        eventTarget.eventListener = it.next
      else:
        prev.next = it.next
      break
    prev = it

proc addInternalEventListener(ctx: JSContext; eventTarget: EventTarget;
    ctype: StaticAtom; callback: JSValueConst): Opt[void] =
  ctx.removeInternalEventListener(eventTarget, ctype)
  ctx.addEventListener(eventTarget, ctype.toAtom(), capture = false,
    once = false, internal = true, passive = none(bool), callback, signal = nil)

# Event reflection
const EventReflectMap = [
  cint(0): satLoadstart,
  satProgress,
  satAbort,
  satError,
  satLoad,
  satTimeout,
  satLoadend,
  satReadystatechange,
  satFocus,
  satBlur
]

proc eventReflectGet*(ctx: JSContext; this: JSValueConst; magic: cint): JSValue
    {.cdecl.} =
  return JS_NULL

proc eventReflectSet0*(ctx: JSContext; target: EventTarget;
    val: JSValueConst; magic: cint; fun2: JSSetterMagicFunction;
    atom: StaticAtom; target2 = none(EventTarget)): JSValue =
  if JS_IsFunction(ctx, val) or JS_IsNull(val):
    let jsTarget = ctx.toJS(target)
    if JS_IsException(jsTarget):
      return JS_EXCEPTION
    let jsTarget2 = ctx.toJS(target2)
    if JS_IsException(jsTarget2):
      JS_FreeValue(ctx, jsTarget)
      return JS_EXCEPTION
    let name = "on" & $atom
    let getter = ctx.identityFunction(val)
    if JS_IsException(getter):
      ctx.freeValues(jsTarget, jsTarget2)
      return JS_EXCEPTION
    let f = JSCFunctionType(setter_magic: fun2)
    let setter = JS_NewCFunction2(ctx, f.generic, cstring(name), 1,
      JS_CFUNC_setter_magic, magic)
    if JS_IsException(getter):
      ctx.freeValues(jsTarget, jsTarget2, getter)
      return JS_EXCEPTION
    let ja = JS_NewAtom(ctx, cstring(name))
    if ja == JS_ATOM_NULL:
      ctx.freeValues(jsTarget, jsTarget2, getter, setter)
      return JS_EXCEPTION
    var ret = JS_DefineProperty(ctx, jsTarget, ja, JS_UNDEFINED, getter,
        setter, JS_PROP_HAS_GET or JS_PROP_HAS_SET or
        JS_PROP_HAS_CONFIGURABLE or JS_PROP_CONFIGURABLE)
    if ret != -1 and target2.isSome:
      # target2 is set to document.body in case of properties like
      # onload, which set functions both on document.body and window,
      # but only set an event listener on window.
      ret = JS_DefineProperty(ctx, jsTarget2, ja, JS_UNDEFINED, getter,
        setter, JS_PROP_HAS_GET or JS_PROP_HAS_SET or
        JS_PROP_HAS_CONFIGURABLE or JS_PROP_CONFIGURABLE)
    JS_FreeAtom(ctx, ja)
    ctx.freeValues(getter, setter, jsTarget, jsTarget2)
    if ret == -1:
      return JS_EXCEPTION
    if JS_IsNull(val):
      ctx.removeInternalEventListener(target, atom)
    elif ctx.addInternalEventListener(target, atom, val).isErr:
      return JS_EXCEPTION
  return JS_DupValue(ctx, val)

proc eventReflectSet*(ctx: JSContext; this, val: JSValueConst; magic: cint):
    JSValue {.cdecl.} =
  var target: EventTarget
  ?ctx.fromJS(this, target)
  return ctx.eventReflectSet0(target, val, magic, eventReflectSet,
    EventReflectMap[magic])

proc addEventListener(ctx: JSContext; eventTarget: EventTarget; ctype: CAtom;
    callback: JSValueConst; options: JSValueConst = JS_UNDEFINED): Opt[void]
    {.jsfunc.} =
  if not JS_IsObject(callback) and not JS_IsNull(callback):
    JS_ThrowTypeError(ctx, "callback is not an object")
    return err()
  var res: FlattenMoreResult
  ?ctx.flattenMore(options, res)
  ctx.addEventListener(eventTarget, ctype, res.capture, res.once,
    internal = false, res.passive, callback, res.signal)

proc removeEventListener(ctx: JSContext; eventTarget: EventTarget;
    ctype: CAtom; callback: JSValueConst; options: JSValueConst = JS_UNDEFINED):
    Opt[void] {.jsfunc.} =
  let capture = ?ctx.flatten(options)
  var prev: EventListener = nil
  for it in eventTarget.eventListeners:
    if not it.internal and it.ctype == ctype and
        ctx.strictEquals(it.callback, callback) and it.capture == capture:
      let callback = it.callback
      it.callback = JS_UNDEFINED
      JS_FreeValue(ctx, callback)
      if prev == nil:
        eventTarget.eventListener = it.next
      else:
        prev.next = it.next
      break
    prev = it
  ok()

type
  DispatchItem = object
    target: EventTarget
    els: seq[EventListener]

  DispatchContext = object
    event: Event
    ctx: JSContext
    stop: bool
    canceled: bool
    capture: seq[DispatchItem]
    bubble: seq[DispatchItem]

proc collectItems(dctx: var DispatchContext; target: EventTarget) =
  let ctype = dctx.event.ctype
  let bubbles = dctx.event.bubbles
  let isLoad = dctx.event.ctype == satLoad.toAtom()
  var it = target
  while it != nil:
    var capture: seq[EventListener] = @[]
    var bubble: seq[EventListener] = @[]
    for el in it.eventListeners:
      if el.ctype == ctype:
        if el.capture:
          capture.add(el)
        elif bubbles or it == target:
          bubble.add(el)
    if capture.len > 0:
      dctx.capture.add(DispatchItem(target: it, els: move(capture)))
    if bubble.len > 0:
      dctx.bubble.add(DispatchItem(target: it, els: move(bubble)))
    it = dctx.ctx.getParentImpl(it, isLoad)

proc dispatchEvent0(dctx: var DispatchContext; item: DispatchItem) =
  let ctx = dctx.ctx
  let event = dctx.event
  event.currentTarget = item.target
  for el in item.els.ritems:
    if JS_IsUndefined(el.callback):
      continue # removed, presumably by a previous handler
    if el.passive:
      event.flags.incl(efInPassiveListener)
    let e = ctx.invoke(el, event)
    if JS_IsException(e):
      ctx.logException()
    JS_FreeValue(ctx, e)
    if el.passive:
      event.flags.excl(efInPassiveListener)
    if efCanceled in event.flags:
      dctx.canceled = true
    if {efStopPropagation, efStopImmediatePropagation} * event.flags != {}:
      dctx.stop = true
    if efStopImmediatePropagation in event.flags:
      break

proc dispatch*(ctx: JSContext; target: EventTarget; event: Event;
    targetOverride = false): bool =
  let prev = ctx.setEventImpl(event)
  var dctx = DispatchContext(ctx: ctx, event: event)
  event.flags.incl(efDispatch)
  if not targetOverride:
    event.target = target
  dctx.collectItems(target)
  event.eventPhase = 1
  for item in dctx.capture.ritems:
    if dctx.stop:
      break
    if item.target == target:
      event.eventPhase = 2
    dctx.dispatchEvent0(item)
  event.eventPhase = 2
  for item in dctx.bubble:
    if dctx.stop:
      break
    if item.target != target:
      event.eventPhase = 3
    dctx.dispatchEvent0(item)
  event.eventPhase = 0
  event.flags.excl(efDispatch)
  discard ctx.setEventImpl(prev)
  return dctx.canceled

proc dispatchEvent(ctx: JSContext; this: EventTarget; event: Event): JSValue
    {.jsfunc.} =
  if efDispatch in event.flags:
    return JS_ThrowDOMException(ctx, "InvalidStateError",
      "event's dispatch flag is already set")
  if efInitialized notin event.flags:
    return JS_ThrowDOMException(ctx, "InvalidStateError",
      "event is not initialized")
  event.isTrusted = false
  if ctx.dispatch(this, event):
    return JS_FALSE
  return JS_TRUE

# AbortSignal
proc finalize(rt: JSRuntime; this: AbortSignal) {.jsfin.} =
  JS_FreeValueRT(rt, this.reason)
  rt.freeValues(this.abortSteps)

proc mark(rt: JSRuntime; this: AbortSignal; markFun: JS_MarkFunc) {.jsmark.} =
  JS_MarkValue(rt, this.reason, markFun)
  for it in this.abortSteps:
    JS_MarkValue(rt, it, markFun)

proc toSignalReason(ctx: JSContext; reason: JSValueConst): JSValue =
  if not JS_IsUndefined(reason):
    return JS_DupValue(ctx, reason)
  JS_ThrowDOMException(ctx, "AbortError", "aborted (core not dumped)")
  return JS_GetException(ctx)

proc abortSignalAbort(ctx: JSContext; reason: JSValueConst = JS_UNDEFINED):
    AbortSignal {.jsstfunc: "AbortSignal#abort".} =
  AbortSignal(reason: ctx.toSignalReason(reason))

proc throwIfAborted(ctx: JSContext; signal: AbortSignal): JSValue {.jsfunc.} =
  if signal.aborted:
    return JS_Throw(ctx, JS_DupValue(ctx, signal.reason))
  return JS_UNDEFINED

#TODO _any

# AbortController
proc newAbortController(ctx: JSContext): AbortController {.jsctor.} =
  let signal = AbortSignal(reason: JS_UNDEFINED)
  AbortController(signal: signal)

proc abort(ctx: JSContext; this: AbortController; reason: JSValueConst): JSValue
    {.jsfunc.} =
  let signal = this.signal
  if not signal.aborted:
    signal.reason = ctx.toSignalReason(reason)
    #TODO dependent signals
    for step in signal.abortSteps:
      let res = ctx.call(step, JS_UNDEFINED)
      if JS_IsException(res):
        return res
      JS_FreeValue(ctx, res)
    let event = newEvent(satAbort.toAtom(), signal, bubbles = false,
      cancelable = false)
    event.isTrusted = true
    discard ctx.dispatch(signal, event)
  return JS_UNDEFINED

# atoms must be sorted in the order of EventReflectMap
proc addEventGetSet*(ctx: JSContext; obj: JSValueConst;
    atoms: openArray[StaticAtom]): Opt[void] =
  var i = cint(0)
  for atom in atoms:
    while EventReflectMap[i] != atom:
      inc i
    let name = "on" & $atom
    ?ctx.addReflectFunction(obj, name, eventReflectGet, eventReflectSet, i)
  ok()

proc addEventGetSet*(ctx: JSContext; classid: JSClassID;
    atoms: openArray[StaticAtom]): Opt[void] =
  let proto = JS_GetClassProto(ctx, classid)
  let res = ctx.addEventGetSet(proto, atoms)
  JS_FreeValue(ctx, proto)
  res

proc addEventModule*(ctx: JSContext):
    Opt[tuple[eventCID, eventTargetCID: JSClassID]] =
  let eventCID = ctx.registerType(Event)
  if eventCID == 0:
    return err()
  ?ctx.registerType(CustomEvent, parent = eventCID)
  ?ctx.registerType(MessageEvent, parent = eventCID)
  ?ctx.registerType(SubmitEvent, parent = eventCID)
  let uiEventCID = ctx.registerType(UIEvent, parent = eventCID)
  if uiEventCID == 0:
    return err()
  ?ctx.registerType(MouseEvent, parent = uiEventCID)
  ?ctx.registerType(InputEvent, parent = uiEventCID)
  if ctx.defineConsts(eventCID, EventPhase) == dprException:
    return err()
  let eventTargetCID = ctx.registerType(EventTarget)
  if eventTargetCID == 0:
    return err()
  let abortSignalCID = ctx.registerType(AbortSignal, parent = eventTargetCID)
  if abortSignalCID == 0:
    return err()
  ?ctx.addEventGetSet(abortSignalCID, [satAbort])
  ?ctx.registerType(AbortController)
  ok((eventCID, eventTargetCID))

{.pop.} # raises: []
