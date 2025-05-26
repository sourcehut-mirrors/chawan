{.push raises: [].}

import std/options

import html/catom
import html/domexception
import html/script
import io/timeout
import monoucha/fromjs
import monoucha/javascript
import monoucha/jserror
import monoucha/jstypes
import monoucha/jsutils
import monoucha/quickjs
import monoucha/tojs
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
    #TODO DOMHighResTimeStamp?
    timeStamp {.jsget.}: float64

  CustomEvent* = ref object of Event
    detail {.jsget.}: JSValue

  MessageEvent* = ref object of Event
    data {.jsget.}: JSValue
    origin {.jsget.}: string

  UIEvent* = ref object of Event
    detail {.jsget.}: int32
    view {.jsget.}: EventTarget

  MouseEvent* = ref object of UIEvent
    screenX {.jsget.}: int32
    screenY {.jsget.}: int32
    clientX {.jsget.}: int32
    clientY {.jsget.}: int32
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
    eventListeners: seq[EventListener]

  EventListener* = ref object
    # if callback is undefined, the listener has been removed
    callback: JSValue
    rt: JSRuntime
    ctype*: CAtom
    capture: bool
    once: bool
    internal: bool
    passive: Option[bool]
    #TODO AbortSignal

jsDestructor(Event)
jsDestructor(CustomEvent)
jsDestructor(MessageEvent)
jsDestructor(UIEvent)
jsDestructor(MouseEvent)
jsDestructor(InputEvent)
jsDestructor(EventTarget)

# Forward declaration hack
var isDefaultPassiveImpl*: proc(target: EventTarget): bool {.nimcall,
  noSideEffect, raises: [].}
var getParentImpl*: proc(ctx: JSContext; target: EventTarget; event: Event):
  EventTarget {.nimcall, raises: [].}
var isWindowImpl*: proc(target: EventTarget): bool {.nimcall, noSideEffect,
  raises: [].}

proc finalize(target: EventTarget) {.jsfin.} =
  # Can't take rt as param here, because elements may be unbound in JS.
  if target != nil:
    for el in target.eventListeners:
      let cb = el.callback
      let rt = el.rt
      el.callback = JS_UNDEFINED
      el.rt = nil
      JS_FreeValueRT(rt, cb)

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

func srcElement(this: Event): EventTarget {.jsfget.} =
  return this.target

#TODO shadow DOM etc.
func composedPath(this: Event): seq[EventTarget] {.jsfunc.} =
  if this.currentTarget == nil:
    return @[]
  return @[this.currentTarget]

proc stopPropagation(this: Event) {.jsfunc.} =
  this.flags.incl(efStopPropagation)

func cancelBubble(this: Event): bool {.jsfget.} =
  return efStopPropagation in this.flags

proc cancelBubble(this: Event; cancel: bool) {.jsfset.} =
  if cancel:
    this.stopPropagation()

proc stopImmediatePropagation(this: Event) {.jsfunc.} =
  this.flags.incl({efStopPropagation, efStopImmediatePropagation})

proc setCanceledFlag(this: Event) =
  if this.cancelable and efInPassiveListener notin this.flags:
    this.flags.incl(efCanceled)

proc returnValue(this: Event): bool {.jsfget.} =
  return efCanceled notin this.flags

proc returnValue(this: Event; value: bool) {.jsfset.} =
  if not value:
    this.setCanceledFlag()

proc preventDefault(this: Event) {.jsfunc.} =
  this.flags.incl(efCanceled)

func defaultPrevented(this: Event): bool {.jsfget.} =
  return efCanceled in this.flags

func composed(this: Event): bool {.jsfget.} =
  return efComposed in this.flags

# CustomEvent
proc newCustomEvent*(ctx: JSContext; ctype: CAtom;
    eventInitDict = CustomEventInit(detail: JS_NULL)): CustomEvent {.jsctor.} =
  let event = CustomEvent(
    ctype: ctype,
    detail: JS_DupValue(ctx, eventInitDict.detail)
  )
  event.innerEventCreationSteps(eventInitDict)
  return event

proc finalize(rt: JSRuntime; this: CustomEvent) {.jsfin.} =
  JS_FreeValueRT(rt, this.detail)

proc initCustomEvent(ctx: JSContext; this: CustomEvent; ctype: CAtom;
    bubbles, cancelable: bool; detail: JSValueConst) {.jsfunc.} =
  if efDispatch notin this.flags:
    if efInitialized notin this.flags:
      JS_FreeValue(ctx, this.detail)
    this.detail = JS_DupValue(ctx, detail)
    this.initialize(ctype, bubbles, cancelable)

# MessageEvent
proc finalize(rt: JSRuntime; this: MessageEvent) {.jsfin.} =
  JS_FreeValueRT(rt, this.data)

proc newMessageEvent*(ctx: JSContext; ctype: CAtom;
    eventInit = MessageEventInit(data: JS_NULL)): MessageEvent =
  let event = MessageEvent(
    ctype: ctype,
    data: JS_DupValue(ctx, eventInit.data),
    origin: eventInit.origin
  )
  event.innerEventCreationSteps(eventInit)
  return event

# UIEvent
type EventTargetWindow = distinct EventTarget
proc fromJS(ctx: JSContext; val: JSValue; res: var EventTargetWindow):
    Opt[void] =
  var res0: EventTarget
  ?ctx.fromJS(val, res0)
  if not res0.isWindowImpl():
    JS_ThrowTypeError(ctx, "Window expected")
    return err()
  res = EventTargetWindow(res0)
  ok()

type UIEventInit = object of EventInit
  view {.jsdefault.}: EventTargetWindow
  detail {.jsdefault.}: int32

proc newUIEvent*(ctype: CAtom; eventInit = UIEventInit()): UIEvent {.jsctor.} =
  let event = UIEvent(
    ctype: ctype,
    view: EventTarget(eventInit.view),
    detail: eventInit.detail
  )
  event.innerEventCreationSteps(eventInit)
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
type MouseEventInit = object of EventModifierInit
  screenX {.jsdefault.}: int32
  screenY {.jsdefault.}: int32
  clientX {.jsdefault.}: int32
  clientY {.jsdefault.}: int32
  button {.jsdefault.}: int32 #TODO int16?
  buttons {.jsdefault.}: uint32 #TODO uint16?
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
  event.innerEventCreationSteps(eventInit)
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
  event.innerEventCreationSteps(eventInit)
  return event

# EventTarget
proc newEventTarget(): EventTarget {.jsctor.} =
  return EventTarget()

proc defaultPassiveValue(ctype: CAtom; eventTarget: EventTarget): bool =
  const check = [satTouchstart, satTouchmove, satWheel, satMousewheel]
  if ctype.toStaticAtom() in check:
    return true
  return eventTarget.isDefaultPassiveImpl()

proc findEventListener(ctx: JSContext; eventTarget: EventTarget; ctype: CAtom;
    callback: JSValueConst; capture: bool): int =
  for i, it in eventTarget.eventListeners.mypairs:
    if not it.internal and it.ctype == ctype and
        JS_IsStrictEqual(ctx, it.callback, callback) and
        it.capture == capture:
      return i
  return -1

proc findInternalEventListener(eventTarget: EventTarget; ctype: CAtom): int =
  for i, it in eventTarget.eventListeners.mypairs:
    if it.ctype == ctype and it.internal:
      return i
  return -1

# EventListener
proc invoke(ctx: JSContext; listener: EventListener; event: Event): JSValue =
  #TODO make this standards compliant
  if JS_IsNull(listener.callback):
    return JS_UNDEFINED
  let jsTarget = ctx.toJS(event.currentTarget)
  let jsEvent = ctx.toJS(event)
  if JS_IsFunction(ctx, listener.callback):
    # Apparently it's a bad idea to call a function that can then delete
    # the reference it was called from.
    let callback = JS_DupValue(ctx, listener.callback)
    let ret = JS_Call(ctx, callback, jsTarget, 1, jsEvent.toJSValueArray())
    JS_FreeValue(ctx, callback)
    JS_FreeValue(ctx, jsTarget)
    JS_FreeValue(ctx, jsEvent)
    return ret
  assert JS_IsObject(listener.callback)
  let handler = JS_GetPropertyStr(ctx, listener.callback, "handleEvent")
  if JS_IsException(handler):
    JS_FreeValue(ctx, jsTarget)
    JS_FreeValue(ctx, jsEvent)
    return handler
  let ret = JS_Call(ctx, handler, jsTarget, 1, jsEvent.toJSValueArray())
  JS_FreeValue(ctx, handler)
  JS_FreeValue(ctx, jsTarget)
  JS_FreeValue(ctx, jsEvent)
  return ret

# shared
proc addAnEventListener(ctx: JSContext; target: EventTarget;
    listener: EventListener) =
  #TODO signals
  if JS_IsUndefined(listener.callback):
    return
  if listener.passive.isNone:
    listener.passive = some(defaultPassiveValue(listener.ctype, target))
  if ctx.findEventListener(target, listener.ctype, listener.callback,
      listener.capture) == -1: # dedup
    target.eventListeners.add(listener)
  #TODO signals

proc removeAnEventListener(eventTarget: EventTarget; ctx: JSContext; i: int) =
  let listener = eventTarget.eventListeners[i]
  let callback = listener.callback
  listener.callback = JS_UNDEFINED
  JS_FreeValue(ctx, callback)
  eventTarget.eventListeners.delete(i)

proc flatten(ctx: JSContext; options: JSValueConst): bool =
  result = false
  if JS_IsBool(options):
    discard ctx.fromJS(options, result)
  if JS_IsObject(options):
    let x = JS_GetPropertyStr(ctx, options, "capture")
    discard ctx.fromJS(x, result)
    JS_FreeValue(ctx, x)

proc flattenMore(ctx: JSContext; options: JSValueConst):
    tuple[
      capture: bool,
      once: bool,
      passive: Option[bool]
      #TODO signals
    ] =
  let capture = flatten(ctx, options)
  var once = false
  var passive = none(bool)
  if JS_IsObject(options):
    let jsOnce = JS_GetPropertyStr(ctx, options, "once")
    discard ctx.fromJS(jsOnce, once)
    JS_FreeValue(ctx, jsOnce)
    let jsPassive = JS_GetPropertyStr(ctx, options, "passive")
    var x: bool
    if ctx.fromJS(jsPassive, x).isSome:
      passive = some(x)
    JS_FreeValue(ctx, jsPassive)
  return (capture, once, passive)

proc removeInternalEventListener(ctx: JSContext; eventTarget: EventTarget;
    ctype: StaticAtom) =
  let i = eventTarget.findInternalEventListener(ctype.toAtom())
  if i != -1:
    eventTarget.removeAnEventListener(ctx, i)

proc addInternalEventListener(ctx: JSContext; eventTarget: EventTarget;
    ctype: StaticAtom; callback: JSValueConst) =
  ctx.removeInternalEventListener(eventTarget, ctype)
  ctx.addAnEventListener(eventTarget, EventListener(
    ctype: ctype.toAtom(),
    capture: false,
    once: false,
    internal: true,
    rt: JS_GetRuntime(ctx),
    callback: JS_DupValue(ctx, callback)
  ))

# Event reflection
const EventReflectMap* = [
  cint(0): satLoadstart,
  satProgress,
  satAbort,
  satError,
  satLoad,
  satTimeout,
  satLoadend,
  satReadystatechange
]

type UnionHack {.union.} = object
  fun: JSCFunction
  fun2: JSSetterMagicFunction

proc eventReflectGet*(ctx: JSContext; this: JSValueConst; magic: cint): JSValue
    {.cdecl.} =
  return JS_NULL

proc eventReflectSet0*(ctx: JSContext; this, val: JSValueConst; magic: cint;
    fun2: JSSetterMagicFunction; atom: StaticAtom): JSValue =
  if JS_IsFunction(ctx, val) or JS_IsNull(val):
    var target: EventTarget
    doAssert ctx.fromJS(this, target).isSome
    let name = "on" & $atom
    let getter = ctx.identityFunction(val)
    let hack = UnionHack(fun2: fun2) # cast does not work :(
    let setter = JS_NewCFunction2(ctx, hack.fun, cstring(name), 1,
      JS_CFUNC_setter_magic, magic)
    let ja = JS_NewAtom(ctx, cstring(name))
    let ret = JS_DefineProperty(ctx, this, ja, JS_UNDEFINED, getter, setter,
        JS_PROP_HAS_GET or JS_PROP_HAS_SET or
        JS_PROP_HAS_CONFIGURABLE or JS_PROP_CONFIGURABLE)
    JS_FreeAtom(ctx, ja)
    JS_FreeValue(ctx, getter)
    JS_FreeValue(ctx, setter)
    if ret == -1:
      return JS_EXCEPTION
    if JS_IsNull(val):
      ctx.removeInternalEventListener(target, atom)
    else:
      ctx.addInternalEventListener(target, atom, val)
  return JS_DupValue(ctx, val)

proc eventReflectSet*(ctx: JSContext; this, val: JSValueConst; magic: cint):
    JSValue {.cdecl.} =
  return ctx.eventReflectSet0(this, val, magic, eventReflectSet,
    EventReflectMap[magic])

proc addEventListener*(ctx: JSContext; eventTarget: EventTarget; ctype: CAtom;
    callback: JSValueConst; options: JSValueConst = JS_UNDEFINED): Err[JSError]
    {.jsfunc.} =
  if not JS_IsObject(callback) and not JS_IsNull(callback):
    return errTypeError("callback is not an object")
  let (capture, once, passive) = flattenMore(ctx, options)
  ctx.addAnEventListener(eventTarget, EventListener(
    ctype: ctype,
    capture: capture,
    passive: passive,
    once: once,
    rt: JS_GetRuntime(ctx),
    callback: JS_DupValue(ctx, callback)
  ))
  ok()

proc removeEventListener(ctx: JSContext; eventTarget: EventTarget;
    ctype: CAtom; callback: JSValueConst; options: JSValueConst = JS_UNDEFINED)
    {.jsfunc.} =
  let capture = flatten(ctx, options)
  let i = ctx.findEventListener(eventTarget, ctype, callback, capture)
  if i != -1:
    eventTarget.removeAnEventListener(ctx, i)

proc hasEventListener*(eventTarget: EventTarget; ctype: CAtom): bool =
  for it in eventTarget.eventListeners:
    if it.ctype == ctype:
      return true
  return false

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
    it = dctx.ctx.getParentImpl(it, dctx.event)

proc dispatchEvent0(dctx: var DispatchContext; item: DispatchItem) =
  let ctx = dctx.ctx
  let event = dctx.event
  event.currentTarget = item.target
  for el in item.els:
    if JS_IsUndefined(el.callback):
      continue # removed, presumably by a previous handler
    let e = ctx.invoke(el, event)
    if JS_IsException(e):
      ctx.logException()
    JS_FreeValue(ctx, e)
    if efCanceled in event.flags:
      dctx.canceled = true
    if {efStopPropagation, efStopImmediatePropagation} * event.flags != {}:
      dctx.stop = true
    if efStopImmediatePropagation in event.flags:
      break

proc dispatch*(ctx: JSContext; target: EventTarget; event: Event): bool =
  var dctx = DispatchContext(ctx: ctx, event: event)
  event.flags.incl(efDispatch)
  event.target = target
  dctx.collectItems(target)
  event.eventPhase = 1
  for i in countdown(dctx.capture.high, 0):
    if dctx.stop:
      break
    let item = dctx.capture[i]
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
  return dctx.canceled

proc dispatchEvent(ctx: JSContext; this: EventTarget; event: Event):
    DOMResult[bool] {.jsfunc.} =
  if efDispatch in event.flags:
    return errDOMException("Event's dispatch flag is already set",
      "InvalidStateError")
  if efInitialized notin event.flags:
    return errDOMException("Event is not initialized", "InvalidStateError")
  event.isTrusted = false
  return ok(not ctx.dispatch(this, event))

proc addEventModule*(ctx: JSContext):
    tuple[eventCID, eventTargetCID: JSClassID] =
  let eventCID = ctx.registerType(Event)
  ctx.registerType(CustomEvent, parent = eventCID)
  ctx.registerType(MessageEvent, parent = eventCID)
  let uiEventCID = ctx.registerType(UIEvent, parent = eventCID)
  ctx.registerType(MouseEvent, parent = uiEventCID)
  ctx.registerType(InputEvent, parent = uiEventCID)
  ctx.defineConsts(eventCID, EventPhase)
  let eventTargetCID = ctx.registerType(EventTarget)
  return (eventCID, eventTargetCID)

{.pop.} # raises: []
