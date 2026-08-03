{.push raises: [].}

import std/options
import std/typetraits

import html/catom
import html/domexception
import html/script
import io/timeout
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsnull
import monoucha/jsopaque
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

  EventFlag = enum
    efStopPropagation
    efStopImmediatePropagation
    efCanceled
    efInPassiveListener
    efComposed
    efInitialized
    efDispatch
    efBubbles
    efCancelable
    efTrusted

  Event* = ref object of JSRootObj
    timeStamp: float64
    target*: EventTarget
    currentTarget*: EventTarget
    ctype*: CAtom
    eventPhase: uint16
    flags: set[EventFlag]

  CustomEvent* {.final.} = ref object of Event
    detail: JSValue

  MessageEvent* {.final.} = ref object of Event
    data: JSValue
    origin: string

  SubmitEvent* {.final.} = ref object of Event
    submitter: EventTarget

  UIEvent* = ref object of Event
    detail: int32
    view: EventTarget

  MouseEvent* {.final.} = ref object of UIEvent
    screenX: int32
    screenY: int32
    clientX: int32
    clientY: int32
    button: int16
    buttons: uint16
    ctrlKey: bool
    shiftKey: bool
    altKey: bool
    metaKey: bool
    relatedTarget: EventTarget
    #TODO and the others

  InputEvent* {.final.} = ref object of UIEvent
    data: Option[string]
    isComposing: bool
    inputType: string

  EventTarget* = ref object of JSRootObj
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

  AbortSignal {.final.} = ref object of EventTarget
    reason: JSValue
    aborted: bool
    abortSteps: seq[JSValue]
    #TODO source/dependent signals

  AbortController = ref object
    signal: AbortSignal

jsDestructor(AbortController)

# Forward declarations
proc removeEventListener(ctx: JSContext; eventTarget: EventTarget;
  ctype: CAtomTraced; callback: JSValueConst;
  options: JSValueConst = JS_UNDEFINED): Opt[void]
proc getClassID*(t: typedesc[EventTarget]): JSClassID
proc getClassID*(t: typedesc[AbortSignal]): JSClassID

# Forward declaration hack
var isDefaultPassiveImpl*: proc(target: EventTarget): bool {.nimcall,
  raises: [].}
var getParentImpl*: proc(ctx: JSContext; target: EventTarget; isLoad: bool):
  EventTarget {.nimcall, raises: [].}
var isWindowImpl*: proc(target: EventTarget): bool {.nimcall, raises: [].}
var isHTMLElementImpl*: proc(target: EventTarget): bool {.nimcall, raises: [].}
var setEventImpl*: proc(ctx: JSContext; event: Event): Event {.
  nimcall, raises: [].}

iterator eventListeners(this: EventTarget): EventListener =
  var it = this.eventListener
  while it != nil:
    yield it
    it = it.next

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
  if eventInitDict.bubbles:
    event.flags.incl(efBubbles)
  if eventInitDict.cancelable:
    event.flags.incl(efCancelable)
  if eventInitDict.composed:
    event.flags.incl(efComposed)

proc newEvent*(ctype: StaticAtom; target: EventTarget;
    bubbles, cancelable: bool): Event =
  let event = Event(
    ctype: ctype.toAtom(),
    target: target,
    currentTarget: target,
  )
  if bubbles:
    event.flags.incl(efBubbles)
  if cancelable:
    event.flags.incl(efCancelable)
  event

proc newTrustedEvent*(ctype: StaticAtom; target: EventTarget;
    bubbles, cancelable: bool): Event =
  let event = Event(
    ctype: ctype.toAtom(),
    target: target,
    currentTarget: target,
    flags: {efTrusted}
  )
  if bubbles:
    event.flags.incl(efBubbles)
  if cancelable:
    event.flags.incl(efCancelable)
  event

proc setTrusted*(event: Event) =
  event.flags.incl(efTrusted)

jsClassPublicDef(Event):
  jsget Event, timeStamp
  jsget Event, target
  jsget Event, currentTarget
  jsget Event, ctype, "type"
  jsget Event, eventPhase

  proc newEvent(ctype: CAtomTraced; eventInitDict = EventInit()): Event {.
      jsctor.} =
    let event = Event(ctype: ctype.dup())
    event.innerEventCreationSteps(eventInitDict)
    return event

  proc eventFlag(event: Event; flag: EventFlag): bool {.
      jsmfget("bubbles", efBubbles), jsmfget("cancelable", efCancelable),
      jsmfget("isTrusted", efTrusted), jsmfget("defaultPrevented", efCanceled),
      jsmfget("cancelBubble", efStopPropagation),
      jsmfget("composed", efComposed).} =
    flag in event.flags

  proc initialize(this: Event; ctype: CAtomTraced; bubbles, cancelable: bool) =
    this.flags.incl(efInitialized)
    this.flags.excl(efTrusted)
    this.target = nil
    this.ctype = ctype.dup()
    this.flags.toggleIf(efBubbles, bubbles)
    this.flags.toggleIf(efCancelable, cancelable)

  proc initEvent(this: Event; ctype: CAtomTraced; bubbles, cancelable: bool)
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

  proc `cancelBubble=`(this: Event; flag: EventFlag; cancel: bool) {.
      jsmfset("cancelBubble", efStopPropagation).} =
    if cancel:
      this.stopPropagation()

  proc stopImmediatePropagation(this: Event) {.jsfunc.} =
    this.flags.incl({efStopPropagation, efStopImmediatePropagation})

  proc preventDefault(this: Event) {.jsfunc.} =
    if efCancelable in this.flags and efInPassiveListener notin this.flags:
      this.flags.incl(efCanceled)

  proc returnValue(this: Event): bool {.jsfget.} =
    efCanceled notin this.flags

  proc `returnValue=`(this: Event; value: bool) {.jsfset: "returnValue".} =
    if not value:
      this.preventDefault()

# CustomEvent
jsClassDef(CustomEvent):
  jsextends EventDef

  jsget CustomEvent, detail

  proc newCustomEvent*(ctx: JSContext; ctype: CAtomTraced;
      eventInitDict = CustomEventInit(detail: JS_NULL)): CustomEvent
      {.jsctor.} =
    let event = CustomEvent(
      ctype: ctype.dup(),
      detail: JS_DupValue(ctx, eventInitDict.detail)
    )
    event.innerEventCreationSteps(EventInit(eventInitDict))
    return event

  proc finalize(rt: JSRuntime; this: CustomEvent) {.jsfin.} =
    JS_FreeValueRT(rt, this.detail)

  proc mark(rt: JSRuntime; this: CustomEvent; markFun: JS_MarkFunc) {.jsmark.} =
    JS_MarkValue(rt, this.detail, markFun)

  proc initCustomEvent(ctx: JSContext; this: CustomEvent; ctype: CAtomTraced;
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

jsClassDef(MessageEvent):
  jsextends EventDef

  jsget MessageEvent, data
  jsget MessageEvent, origin

  proc finalize(rt: JSRuntime; this: MessageEvent) {.jsfin.} =
    JS_FreeValueRT(rt, this.data)

  proc mark(rt: JSRuntime; this: MessageEvent; markFun: JS_MarkFunc)
      {.jsmark.} =
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

jsClassDef(SubmitEvent):
  jsextends EventDef

  jsget SubmitEvent, submitter

  proc newSubmitEvent*(ctype: CAtomTraced; eventInit = SubmitEventInit()):
      SubmitEvent {.jsctor.} =
    let event = SubmitEvent(
      ctype: ctype.dup(),
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

jsClassDef(UIEvent):
  jsextends EventDef

  jsget UIEvent, detail
  jsget UIEvent, view

  proc newUIEvent*(ctype: CAtomTraced; eventInit = UIEventInit()): UIEvent
      {.jsctor.} =
    let event = UIEvent(
      ctype: ctype.dup(),
      view: EventTarget(eventInit.view),
      detail: eventInit.detail
    )
    event.innerEventCreationSteps(EventInit(eventInit))
    return event

  proc initUIEvent(this: UIEvent; ctype: CAtomTraced; bubbles = false;
      cancelable = false; view = none(EventTarget); detail = 0i32) {.jsfunc.} =
    this.ctype = ctype.dup()
    this.flags.toggleIf(efBubbles, bubbles)
    this.flags.toggleIf(efCancelable, cancelable)
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

jsClassDef(MouseEvent):
  jsextends UIEventDef

  jsget MouseEvent, screenX
  jsget MouseEvent, screenY
  jsget MouseEvent, clientX, "clientX", "x"
  jsget MouseEvent, clientY, "clientY", "y"
  jsget MouseEvent, button
  jsget MouseEvent, buttons
  jsget MouseEvent, ctrlKey
  jsget MouseEvent, shiftKey
  jsget MouseEvent, altKey
  jsget MouseEvent, metaKey
  jsget MouseEvent, relatedTarget

  proc newMouseEvent*(ctype: CAtomTraced; eventInit = MouseEventInit()):
      MouseEvent {.jsctor.} =
    let event = MouseEvent(
      ctype: ctype.dup(),
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

jsClassDef(InputEvent):
  jsextends UIEventDef

  jsget InputEvent, data
  jsget InputEvent, isComposing
  jsget InputEvent, inputType

  proc newInputEvent*(ctype: CAtomTraced; eventInit = InputEventInit()):
      InputEvent {.jsctor.} =
    let event = InputEvent(
      ctype: ctype.dup(),
      view: EventTarget(eventInit.view),
      data: eventInit.data,
      isComposing: eventInit.isComposing,
      inputType: eventInit.inputType,
      detail: eventInit.detail
    )
    event.innerEventCreationSteps(EventInit(eventInit))
    return event

# EventTarget
proc defaultPassiveValue(ctype: CAtomTraced; eventTarget: EventTarget): bool =
  const check = [satTouchstart, satTouchmove, satWheel, satMousewheel]
  return ctype.toStaticAtom() in check and eventTarget.isDefaultPassiveImpl()

proc findEventListener(ctx: JSContext; eventTarget: EventTarget;
    ctype: CAtomTraced; callback: JSValueConst; capture: bool): EventListener =
  for it in eventTarget.eventListeners:
    if not it.internal and it.ctype == ctype and
        ctx.strictEquals(it.callback, callback) and it.capture == capture:
      return it
  nil

proc findInternalEventListener(ctx: JSContext; eventTarget: EventTarget;
    ctype: StaticAtom): EventListener =
  for it in eventTarget.eventListeners:
    if it.internal and it.ctype == ctype:
      return it
  nil

proc hasEventListener*(eventTarget: EventTarget; ctype: CAtomTraced): bool =
  for it in eventTarget.eventListeners:
    if it.ctype == ctype:
      return true
  false

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
    argc: cint; argv: JSValueConstArray; magic: cint;
    funcData: JSValueConstArray): JSValue {.cdecl.} =
  var this: EventTarget
  ?ctx.fromJS(funcData[0], this)
  var ctype: CAtomTraced
  ?ctx.fromJS(funcData[1], ctype)
  if ctx.removeEventListener(this, ctype, funcData[2], funcData[3]).isErr:
    return JS_EXCEPTION
  return JS_UNDEFINED

proc addEventListener(ctx: JSContext; target: EventTarget; ctype: CAtomTraced;
    capture, once, internal: bool; passive: Option[bool];
    callback: JSValueConst; signal: AbortSignal): Opt[void] =
  if signal != nil and signal.aborted or JS_IsUndefined(callback):
    return ok()
  let passive = passive.get(defaultPassiveValue(ctype, target))
  if ctx.findEventListener(target, ctype, callback, capture) == nil:
    # dedup
    let listener = EventListener(
      ctype: ctype.dup(),
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
  ctx.addEventListener(eventTarget, ctype.view(), capture = false,
    once = false, internal = true, passive = none(bool), callback, signal = nil)

# Event reflection
proc eventReflectGetImpl*(ctx: JSContext; this: EventTarget; name: StaticAtom):
    JSValue {.cdecl.} =
  if this == nil:
    return JS_EXCEPTION
  let el = ctx.findInternalEventListener(this, name)
  if el == nil:
    return JS_NULL
  return JS_DupValue(ctx, el.callback)

proc eventReflectSetImpl*(ctx: JSContext; this: EventTarget; val: JSValueConst;
    atom: StaticAtom): JSValue =
  if this == nil:
    return JS_EXCEPTION
  if JS_IsFunction(ctx, val) or JS_IsNull(val):
    if JS_IsNull(val):
      ctx.removeInternalEventListener(this, atom)
    elif ctx.addInternalEventListener(this, atom, val).isErr:
      return JS_EXCEPTION
  return JS_UNDEFINED

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
  let bubbles = efBubbles in dctx.event.flags
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

jsClassPublicDef(EventTarget):
  proc finalize(rt: JSRuntime; target: EventTarget) {.jsfin.} =
    # Can't take rt as param here, because elements may be unbound in JS.
    for el in target.eventListeners:
      JS_FreeValueRT(rt, el.callback)

  proc mark(rt: JSRuntime; target: EventTarget; markFunc: JS_MarkFunc)
      {.jsmark.} =
    for el in target.eventListeners:
      JS_MarkValue(rt, el.callback, markFunc)

  proc newEventTarget(): EventTarget {.jsctor.} =
    return EventTarget()

  proc addEventListener(ctx: JSContext; eventTarget: EventTarget;
      ctype: CAtomTraced; callback: JSValueConst;
      options: JSValueConst = JS_UNDEFINED): Opt[void] {.jsfunc.} =
    if not JS_IsObject(callback) and not JS_IsNull(callback):
      JS_ThrowTypeError(ctx, "callback is not an object")
      return err()
    var res: FlattenMoreResult
    ?ctx.flattenMore(options, res)
    ctx.addEventListener(eventTarget, ctype, res.capture, res.once,
      internal = false, res.passive, callback, res.signal)

  proc removeEventListener(ctx: JSContext; eventTarget: EventTarget;
      ctype: CAtomTraced; callback: JSValueConst;
      options: JSValueConst = JS_UNDEFINED): Opt[void] {.jsfunc.} =
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

  proc dispatchEvent(ctx: JSContext; this: EventTarget; event: Event): JSValue
      {.jsfunc.} =
    if efDispatch in event.flags:
      return JS_ThrowDOMException(ctx, "InvalidStateError",
        "event's dispatch flag is already set")
    if efInitialized notin event.flags:
      return JS_ThrowDOMException(ctx, "InvalidStateError",
        "event is not initialized")
    event.flags.excl(efTrusted)
    if ctx.dispatch(this, event):
      return JS_FALSE
    return JS_TRUE

proc addEventGetSetImpl*(ctx: JSContext; obj: JSValueConst; id: JSClassID;
    atoms: openArray[StaticAtom]; get: JSGetterMagicFunction;
    set: JSSetterMagicFunction): Opt[void] =
  assert ctx.isInstanceOf(id, EventTargetDef.id)
  for atom in atoms:
    let name = "on" & $atom
    ?ctx.addReflectFunction(obj, cstring(name), get, set, cint(atom))
  ok()

proc fromJSEventTarget*(ctx: JSContext; this: JSValueConst;
    tclassid: JSClassID): EventTarget =
  let ctxOpaque = ctx.getOpaque()
  var classid: JSClassID
  var p: pointer
  if JS_VALUE_GET_PTR(ctxOpaque.global) != JS_VALUE_GET_PTR(this):
    p = JS_GetAnyOpaque(this, classid)
  else:
    classid = ctxOpaque.gclass
    p = ctxOpaque.globalObj
  if not ctx.isInstanceOf(classid, tclassid):
    discard JS_GetOpaque2(ctx, JS_UNDEFINED, tclassid)
    return nil
  return cast[EventTarget](p)

template addEventGetSetObj*(ctx2: JSContext; obj: JSValueConst; id: JSClassID;
    atoms: varargs[StaticAtom]): Opt[void] =
  proc eventReflectGet(ctx: JSContext; this: JSValueConst; magic: cint):
      JSValue {.cdecl.} =
    let target = ctx.fromJSEventTarget(this, id)
    ctx.eventReflectGetImpl(target, cast[StaticAtom](magic))

  proc eventReflectSet(ctx: JSContext; this, val: JSValueConst;
      magic: cint): JSValue {.cdecl.} =
    let target = ctx.fromJSEventTarget(this, id)
    ctx.eventReflectSetImpl(target, val, cast[StaticAtom](magic))

  ctx2.addEventGetSetImpl(obj, id, atoms, eventReflectGet, eventReflectSet)

template addEventGetSet*(ctx: JSContext; id: JSClassID;
    atoms: varargs[StaticAtom]): Opt[void] =
  let proto = JS_GetClassProto(ctx, id)
  let res = ctx.addEventGetSetObj(proto, id, atoms)
  JS_FreeValue(ctx, proto)
  res

# AbortSignal
proc toSignalReason(ctx: JSContext; reason: JSValueConst): JSValue =
  if not JS_IsUndefined(reason):
    return JS_DupValue(ctx, reason)
  JS_ThrowDOMException(ctx, "AbortError", "aborted (core not dumped)")
  return JS_GetException(ctx)

jsClassDef(AbortSignal):
  jsextends EventTargetDef

  proc addAbortSignalEvents(ctx: JSContext): Opt[void] =
    ctx.addEventGetSet(classDef.id, satAbort)

  jsget AbortSignal, reason
  jsget AbortSignal, aborted

  proc finalize(rt: JSRuntime; this: AbortSignal) {.jsfin.} =
    JS_FreeValueRT(rt, this.reason)
    rt.freeValues(this.abortSteps)

  proc mark(rt: JSRuntime; this: AbortSignal; markFun: JS_MarkFunc) {.
      jsmark.} =
    JS_MarkValue(rt, this.reason, markFun)
    for it in this.abortSteps:
      JS_MarkValue(rt, it, markFun)

  proc abort(ctx: JSContext; reason: JSValueConst = JS_UNDEFINED): AbortSignal
      {.jsstfunc.} =
    AbortSignal(reason: ctx.toSignalReason(reason))

  proc throwIfAborted(ctx: JSContext; signal: AbortSignal): JSValue
      {.jsfunc.} =
    if signal.aborted:
      return JS_Throw(ctx, JS_DupValue(ctx, signal.reason))
    return JS_UNDEFINED

  #TODO _any

# AbortController
jsClassDef(AbortController):
  jsget AbortController, signal

  proc newAbortController(ctx: JSContext): AbortController {.jsctor.} =
    let signal = AbortSignal(reason: JS_UNDEFINED)
    AbortController(signal: signal)

  proc abort(ctx: JSContext; this: AbortController; reason: JSValueConst):
      JSValue {.jsfunc.} =
    let signal = this.signal
    if not signal.aborted:
      signal.reason = ctx.toSignalReason(reason)
      #TODO dependent signals
      for step in signal.abortSteps:
        let res = ctx.call(step, JS_UNDEFINED)
        if JS_IsException(res):
          return res
        JS_FreeValue(ctx, res)
      let event = newTrustedEvent(satAbort, signal, bubbles = false,
        cancelable = false)
      discard ctx.dispatch(signal, event)
    return JS_UNDEFINED

proc addEventModule*(ctx: JSContext): Opt[void] =
  ?ctx.registerClass(EventDef)
  ?ctx.registerClass(CustomEventDef)
  ?ctx.registerClass(MessageEventDef)
  ?ctx.registerClass(SubmitEventDef)
  ?ctx.registerClass(UIEventDef)
  ?ctx.registerClass(MouseEventDef)
  ?ctx.registerClass(InputEventDef)
  if ctx.defineConsts(EventDef.id, EventPhase) == dprException:
    return err()
  ?ctx.registerClass(EventTargetDef)
  ?ctx.registerClass(AbortSignalDef)
  ?ctx.addAbortSignalEvents()
  ?ctx.registerClass(AbortControllerDef)
  ok()

{.pop.} # raises: []
