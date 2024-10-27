import std/math
import std/options
import std/times

import html/catom
import html/script
import js/domexception
import monoucha/fromjs
import monoucha/javascript
import monoucha/jserror
import monoucha/jstypes
import monoucha/jsutils
import monoucha/quickjs
import monoucha/tojs
import types/opt

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
    #TODO DOMHighResTimeStamp?
    timeStamp {.jsget.}: float64
    flags*: set[EventFlag]
    isTrusted {.jsufget.}: bool

  CustomEvent* = ref object of Event
    detail {.jsget.}: JSValue

  EventTarget* = ref object of RootObj
    eventListeners*: seq[EventListener]

  EventHandler* = JSValue

  EventListenerCallback = JSValue

  EventListener* = ref object
    ctype*: CAtom
    # if callback is undefined, the listener has been removed
    callback*: EventListenerCallback
    capture: bool
    passive: Option[bool]
    once: bool
    #TODO AbortSignal

jsDestructor(Event)
jsDestructor(CustomEvent)
jsDestructor(EventTarget)

# Forward declaration hack
var isDefaultPassiveImpl*: proc(target: EventTarget): bool {.nimcall,
  noSideEffect.} = nil
var getParentImpl*: proc(ctx: JSContext; target: EventTarget; event: Event):
  EventTarget {.nimcall.}

type
  EventInit* = object of JSDict
    bubbles* {.jsdefault.}: bool
    cancelable* {.jsdefault.}: bool
    composed* {.jsdefault.}: bool

  CustomEventInit = object of EventInit
    detail* {.jsdefault: JS_NULL.}: JSValue

# Event
proc innerEventCreationSteps*(event: Event; eventInitDict: EventInit) =
  event.flags = {efInitialized}
  #TODO this is probably incorrect?
  # I think it measures the time since the first fork. not sure though
  event.timeStamp = round(cpuTime())
  event.bubbles = eventInitDict.bubbles
  event.cancelable = eventInitDict.cancelable
  if eventInitDict.composed:
    event.flags.incl(efComposed)

#TODO eventInitDict type
proc newEvent(ctx: JSContext; ctype: CAtom; eventInitDict = EventInit()):
    JSResult[Event] {.jsctor.} =
  let event = Event(ctype: ctype)
  event.innerEventCreationSteps(eventInitDict)
  return ok(event)

proc newEvent*(ctype: CAtom; target: EventTarget): Event =
  return Event(
    ctype: ctype,
    target: target,
    currentTarget: target
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
proc newCustomEvent(ctx: JSContext; ctype: CAtom;
    eventInitDict = CustomEventInit()): JSResult[CustomEvent] {.jsctor.} =
  let event = CustomEvent()
  event.innerEventCreationSteps(eventInitDict)
  event.detail = JS_DupValue(ctx, eventInitDict.detail)
  event.ctype = ctype
  return ok(event)

proc finalize(rt: JSRuntime; this: CustomEvent) {.jsfin.} =
  JS_FreeValueRT(rt, this.detail)

proc initCustomEvent(this: CustomEvent; ctype: CAtom;
    bubbles, cancelable: bool; detail: JSValue) {.jsfunc.} =
  if efDispatch notin this.flags:
    this.initialize(ctype, bubbles, cancelable)
    this.detail = detail

# EventTarget
proc newEventTarget(): EventTarget {.jsctor.} =
  return EventTarget()

proc defaultPassiveValue(ctx: JSContext; ctype: CAtom;
    eventTarget: EventTarget): bool =
  const check = [satTouchstart, satTouchmove, satWheel, satMousewheel]
  if ctx.toStaticAtom(ctype) in check:
    return true
  return eventTarget.isDefaultPassiveImpl()

proc findEventListener(eventTarget: EventTarget; ctype: CAtom;
    callback: EventListenerCallback; capture: bool): int =
  for i, it in eventTarget.eventListeners:
    if it.ctype == ctype and it.callback == callback and it.capture == capture:
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
    let ret = JS_Call(ctx, listener.callback, jsTarget, 1,
      jsEvent.toJSValueArray())
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
    listener.passive = some(ctx.defaultPassiveValue(listener.ctype, target))
  if target.findEventListener(listener.ctype, listener.callback,
      listener.capture) == -1: # dedup
    target.eventListeners.add(listener)
  #TODO signals

proc removeAnEventListener(eventTarget: EventTarget; ctx: JSContext; i: int) =
  let listener = eventTarget.eventListeners[i]
  JS_FreeValue(ctx, listener.callback)
  listener.callback = JS_UNDEFINED
  eventTarget.eventListeners.delete(i)

proc flatten(ctx: JSContext; options: JSValue): bool =
  result = false
  if JS_IsBool(options):
    discard ctx.fromJS(options, result)
  if JS_IsObject(options):
    let x = JS_GetPropertyStr(ctx, options, "capture")
    discard ctx.fromJS(x, result)
    JS_FreeValue(ctx, x)

proc flattenMore(ctx: JSContext; options: JSValue):
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

proc addEventListener*(ctx: JSContext; eventTarget: EventTarget; ctype: CAtom;
    callback: EventListenerCallback; options = JS_UNDEFINED): Err[JSError]
    {.jsfunc.} =
  if not JS_IsObject(callback) and not JS_IsNull(callback):
    return errTypeError("callback is not an object")
  let (capture, once, passive) = flattenMore(ctx, options)
  let listener = EventListener(
    ctype: ctype,
    capture: capture,
    passive: passive,
    once: once,
    callback: JS_DupValue(ctx, callback)
  )
  ctx.addAnEventListener(eventTarget, listener)
  ok()

proc removeEventListener(ctx: JSContext; eventTarget: EventTarget;
    ctype: CAtom; callback: EventListenerCallback;
    options = JS_UNDEFINED) {.jsfunc.} =
  let capture = flatten(ctx, options)
  let i = eventTarget.findEventListener(ctype, callback, capture)
  if i != -1:
    eventTarget.removeAnEventListener(ctx, i)

proc dispatchEvent0(ctx: JSContext; event: Event; currentTarget: EventTarget;
    stop, canceled: var bool) =
  event.currentTarget = currentTarget
  var els = currentTarget.eventListeners # copy intentionally
  for el in els:
    if JS_IsUndefined(el.callback):
      continue # removed, presumably by a previous handler
    if el.ctype == event.ctype:
      let e = ctx.invoke(el, event)
      if JS_IsException(e):
        ctx.logException()
      JS_FreeValue(ctx, e)
      if efStopImmediatePropagation in event.flags:
        stop = true
        break
      if efStopPropagation in event.flags:
        stop = true
      if efCanceled in event.flags:
        canceled = true

proc dispatch*(ctx: JSContext; target: EventTarget; event: Event): bool =
  #TODO this is far from being compliant
  var canceled = false
  var stop = false
  event.flags.incl(efDispatch)
  var target = target
  while target != nil and not stop:
    ctx.dispatchEvent0(event, target, stop, canceled)
    target = ctx.getParentImpl(target, event)
  event.flags.excl(efDispatch)
  return canceled

proc dispatchEvent(ctx: JSContext; this: EventTarget; event: Event):
    DOMResult[bool] {.jsfunc.} =
  if efDispatch in event.flags:
    return errDOMException("Event's dispatch flag is already set",
      "InvalidStateError")
  if efInitialized notin event.flags:
    return errDOMException("Event is not initialized", "InvalidStateError")
  event.isTrusted = false
  return ok(ctx.dispatch(this, event))

proc addEventModule*(ctx: JSContext) =
  let eventCID = ctx.registerType(Event)
  ctx.registerType(CustomEvent, parent = eventCID)
  ctx.defineConsts(eventCID, EventPhase, uint16)
  ctx.registerType(EventTarget)
