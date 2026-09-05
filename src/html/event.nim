{.push raises: [].}

import std/options

import html/catom
import html/domexception
import html/script
import io/timeout
import js/fromjs
import js/jsbind
import js/jsnull
import js/jsopaque
import js/jsopt
import js/jsref
import js/jstypes
import js/jsutils
import js/quickjs
import js/tojs
import types/opt
import types/refstring
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

  EventObj* {.pure.} = object of JSRootObj
    timeStamp: float64
    target*: EventTarget
    currentTarget*: EventTarget
    eventType*: CAtom
    eventPhase: uint16
    flags: set[EventFlag]

  Event* = JSRef[EventObj]

  CustomEventObj {.pure, final.} = object of EventObj
    detail: JSValue

  CustomEvent = JSRef[CustomEventObj]

  MessageEventObj {.pure, final.} = object of EventObj
    data: JSValue
    origin: string

  MessageEvent = JSRef[MessageEventObj]

  SubmitEventObj {.pure, final.} = object of EventObj
    submitter: EventTarget

  SubmitEvent = JSRef[SubmitEventObj]

  UIEventObj {.pure.} = object of EventObj
    detail: int32
    view: EventTarget

  UIEvent = JSRef[UIEventObj]

  MouseEventObj {.pure, final.} = object of UIEventObj
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

  MouseEvent = JSRef[MouseEventObj]

  InputEventObj {.final.} = object of UIEventObj
    data: Option[string]
    isComposing: bool
    inputType: string

  InputEvent = JSRef[InputEventObj]

  EventTargetObj* = object of JSRootObj
    eventListener: EventListener

  EventTarget* = JSRef[EventTargetObj]

  MutationRecordType* = enum
    mrtAttributes = "attributes"
    mrtCharacterData = "characterData"
    mrtChildList = "childList"

  MutationRecordObj = object
    t: MutationRecordType
    attributeName: CAtom
    attributeNamespace: CAtom
    oldValue: RefString
    target: EventTarget
    addedNodes: JSRootRef
    removedNodes: JSRootRef
    previousSibling: EventTarget
    nextSibling: EventTarget

  MutationRecord = JSRef[MutationRecordObj]

  MutationObserverObj = object
    callback*: JSObject
    nodes: seq[ptr EventTargetObj]
    records*: seq[MutationRecord]

  MutationObserver* = JSRef[MutationObserverObj]

  EventListenerType = enum
    eltEventListener, eltMutationObserver

  ObservedItemFlag* = enum
    oifChildList, oifAttributes, oifAttributeFilter, oifAttributeOldValue,
    oifCharacterData, oifCharacterDataOldValue, oifSubtree

  EventListenerFlag = enum
    elfOnce, elfPassive

  EventListener {.acyclic.} = ref object
    flags*: set[ObservedItemFlag]
    case t: EventListenerType
    of eltEventListener:
      # callback may be
      # * null (accepted from addEventListener)
      # * an object (whose handleEvent property will be invoked)
      # * a function
      callback: JSObject
      eventType: CAtom
      eflags: set[EventListenerFlag]
      capture: bool
      internal: bool
      removed: bool
      signal: AbortSignal
    of eltMutationObserver:
      observer*: MutationObserver
      attributeFilter*: seq[CAtom]
    # order is: eltEventListener nodes -> eltMutationObserver nodes
    next: EventListener

  AbortSignal = JSRef[AbortSignalObj]

  AbortSignalObj {.pure, final.} = object of EventTargetObj
    reason: JSValue
    aborted: bool
    abortSteps: seq[JSValue]
    #TODO source/dependent signals

  AbortControllerObj = object
    signal: AbortSignal

  AbortController = JSRef[AbortControllerObj]

# Forward declarations
proc removeEventListener(ctx: JSContext; eventTarget: EventTarget;
  eventType: CAtom; callback: JSValueConst;
  options: JSValueConst = JS_UNDEFINED): Opt[void]
proc getClassID*(t: typedesc[EventTarget]): JSClassID
proc getClassID(t: typedesc[AbortSignal]): JSClassID
proc getClassID*(t: typedesc[Event]): JSClassID
proc getClassID(t: typedesc[MessageEvent]): JSClassID

# Forward declaration hack
proc isDefaultPassive(target: EventTarget): bool {.importc: "cha_$1".}
proc getParentImpl(target: EventTarget; isLoad: bool): EventTarget {.
  importc: "cha_$1".}
proc setEvent(ctx: JSContext; event: Event): Event {.importc: "cha_$1".}

var windowClassID* {.global.}: JSClassID
var nodeClassID* {.global.}: JSClassID
var htmlElementClassID* {.global.}: JSClassID

iterator eventListenersRaw(this: EventTarget): EventListener =
  # includes mutation observers too!
  var it = this.eventListener
  while it != nil:
    yield it
    it = it.next

iterator eventListeners(this: EventTarget): EventListener =
  for el in this.eventListenersRaw:
    if el.t == eltEventListener:
      yield el
    else:
      break

iterator mutationObservers*(this: EventTarget): EventListener =
  for el in this.eventListenersRaw:
    if el.t == eltMutationObserver:
      yield el

type
  EventInit* = object of JSDict
    bubbles* {.jsdefault.}: bool
    cancelable* {.jsdefault.}: bool
    composed* {.jsdefault.}: bool

  CustomEventInit = object of EventInit
    detail {.jsdefault: trace(JS_NULL).}: JSValueTraced

  MessageEventInit* = object of EventInit
    data* {.jsdefault: trace(JS_NULL).}: JSValueTraced
    origin {.jsdefault.}: string
    lastEventId {.jsdefault.}: string

# Event
template asEvent*[T: EventObj](x: JSRef[T]): Event =
  Event(x)

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

proc newEvent*(eventType: StaticAtom; target: EventTarget;
    bubbles, cancelable: bool): Event =
  let event = jsNew EventObj(
    eventType: eventType.view(),
    target: target,
    currentTarget: target,
  )
  if event != nil:
    if bubbles:
      event.flags.incl(efBubbles)
    if cancelable:
      event.flags.incl(efCancelable)
  event

proc newTrustedEvent*(eventType: StaticAtom; target: EventTarget;
    bubbles, cancelable: bool): Event =
  let event = newEvent(eventType, target, bubbles, cancelable)
  if event != nil:
    event.flags.incl(efTrusted)
  event

proc setTrusted*(event: Event) =
  event.flags.incl(efTrusted)

jsClassPublicDef(Event):
  jsget Event, timeStamp
  jsget Event, target
  jsget Event, currentTarget
  jsget Event, eventType, "type"
  jsget Event, eventPhase

  proc newEvent(eventType: CAtom; eventInitDict = EventInit()): Event {.
      jsctor.} =
    let event = jsNew EventObj(eventType: eventType)
    if event != nil:
      event.innerEventCreationSteps(eventInitDict)
    return event

  proc eventFlag(event: Event; flag: EventFlag): bool {.
      jsmfget("bubbles", efBubbles), jsmfget("cancelable", efCancelable),
      jsmfget("isTrusted", efTrusted), jsmfget("defaultPrevented", efCanceled),
      jsmfget("cancelBubble", efStopPropagation),
      jsmfget("composed", efComposed).} =
    flag in event.flags

  proc initialize(this: Event; eventType: CAtom; bubbles, cancelable: bool) =
    this.flags.incl(efInitialized)
    this.flags.excl(efTrusted)
    this.target = EventTarget(nil)
    this.eventType = eventType
    this.flags.toggleIf(efBubbles, bubbles)
    this.flags.toggleIf(efCancelable, cancelable)

  proc initEvent(this: Event; eventType: CAtom; bubbles, cancelable: bool)
      {.jsfunc.} =
    if efDispatch notin this.flags:
      this.initialize(eventType, bubbles, cancelable)

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

  proc newCustomEvent*(ctx: JSContext; eventType: CAtom;
      eventInitDict = CustomEventInit(detail: trace(JS_NULL))): CustomEvent
      {.jsctor.} =
    let event = jsNew CustomEventObj(
      eventType: eventType,
      detail: JS_DupValue(ctx, eventInitDict.detail)
    )
    if event != nil:
      event.asEvent.innerEventCreationSteps(EventInit(eventInitDict))
    event

  proc initCustomEvent(ctx: JSContext; this: CustomEvent; eventType: CAtom;
      bubbles, cancelable: bool; detail: JSValueConst) {.jsfunc.} =
    if efDispatch notin this.flags:
      if efInitialized notin this.flags:
        JS_FreeValue(ctx, this.detail)
      this.detail = JS_DupValue(ctx, detail)
      this.asEvent.initialize(eventType, bubbles, cancelable)

# MessageEvent
proc newMessageEvent*(ctx: JSContext; eventType: CAtom;
    eventInit = MessageEventInit(data: trace(JS_NULL))): MessageEvent =
  let event = jsNew MessageEventObj(
    eventType: eventType,
    data: JS_DupValue(ctx, eventInit.data),
    origin: eventInit.origin
  )
  if event != nil:
    event.asEvent.innerEventCreationSteps(EventInit(eventInit))
  return event

jsClassDef(MessageEvent):
  jsextends EventDef

  jsget MessageEvent, data
  jsget MessageEvent, origin

# SubmitEvent
type EventTargetHTMLElement* = distinct EventTarget
proc fromJS(ctx: JSContext; val: JSValueConst; res: var EventTargetHTMLElement):
    JSCode =
  var res0: pointer
  ?ctx.fromJS(val, htmlElementClassID, res0)
  res = cast[EventTargetHTMLElement](res0)
  fjOk

type SubmitEventInit* = object of EventInit
  submitter* {.jsdefault.}: EventTargetHTMLElement

jsClassDef(SubmitEvent):
  jsextends EventDef

  jsget SubmitEvent, submitter

  proc newSubmitEvent*(eventType: CAtom; eventInit = SubmitEventInit()):
      SubmitEvent {.jsctor.} =
    let event = jsNew SubmitEventObj(
      eventType: eventType,
      submitter: EventTarget(eventInit.submitter)
    )
    if event != nil:
      event.asEvent.innerEventCreationSteps(EventInit(eventInit))
    event

# UIEvent
type EventTargetWindowNull* = distinct EventTarget

proc fromJS(ctx: JSContext; val: JSValueConst; res: var EventTargetWindowNull):
    JSCode =
  if JS_IsNull(val):
    res = EventTargetWindowNull(nil)
  else:
    var res0: pointer
    ?ctx.fromJS(val, windowClassID, res0)
    res = EventTargetWindowNull(cast[EventTarget](res0))
  fjOk

type UIEventInit = object of EventInit
  view* {.jsdefault.}: EventTargetWindowNull
  detail* {.jsdefault.}: int32

jsClassDef(UIEvent):
  jsextends EventDef

  jsget UIEvent, detail
  jsget UIEvent, view

  proc newUIEvent*(eventType: CAtom; eventInit = UIEventInit()): UIEvent
      {.jsctor.} =
    let event = jsNew UIEventObj(
      eventType: eventType,
      view: EventTarget(eventInit.view),
      detail: eventInit.detail
    )
    if event != nil:
      event.asEvent.innerEventCreationSteps(EventInit(eventInit))
    return event

  proc initUIEvent(this: UIEvent; eventType: CAtom; bubbles = false;
      cancelable = false; view = EventTargetWindowNull(nil); detail = 0i32)
      {.jsfunc.} =
    this.eventType = eventType
    this.flags.toggleIf(efBubbles, bubbles)
    this.flags.toggleIf(efCancelable, cancelable)
    this.view = EventTarget(view)
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
  relatedTarget {.jsdefault.}: JSNullRef[EventTargetObj]

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

  proc newMouseEvent*(eventType: CAtom; eventInit = MouseEventInit()):
      MouseEvent {.jsctor.} =
    let event = jsNew MouseEventObj(
      eventType: eventType,
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
      relatedTarget: eventInit.relatedTarget.get
    )
    if event != nil:
      event.asEvent.innerEventCreationSteps(EventInit(eventInit))
    event

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

  proc newInputEvent*(eventType: CAtom; eventInit = InputEventInit()):
      InputEvent {.jsctor.} =
    let event = jsNew InputEventObj(
      eventType: eventType,
      view: EventTarget(eventInit.view),
      data: eventInit.data,
      isComposing: eventInit.isComposing,
      inputType: eventInit.inputType,
      detail: eventInit.detail
    )
    if event != nil:
      event.asEvent.innerEventCreationSteps(EventInit(eventInit))
    event

# MutationRecord
jsClassDef(MutationRecord):
  jsget MutationRecord, t, "type"
  jsget MutationRecord, target
  jsget MutationRecord, addedNodes
  jsget MutationRecord, removedNodes
  jsget MutationRecord, previousSibling
  jsget MutationRecord, nextSibling
  jsget MutationRecord, attributeName
  jsget MutationRecord, attributeNamespace
  jsget MutationRecord, oldValue

# MutationObserver
type OptionalBool = enum
  obNone, obFalse, obTrue

proc fromJS(ctx: JSContext; val: JSValueConst; ob: var OptionalBool):
    JSCode =
  var status = fjOk
  if JS_IsUndefined(val):
    ob = obNone
  else:
    var b: bool
    status = ctx.fromJS(val, b)
    ob = if b: obTrue else: obFalse
  status

type MutationObserverInit {.pure.} = object of JSDict
  childList {.jsdefault.}: bool
  attributes {.jsdefault.}: OptionalBool
  characterData {.jsdefault.}: OptionalBool
  subtree {.jsdefault.}: bool
  attributeOldValue {.jsdefault.}: OptionalBool
  characterDataOldValue {.jsdefault.}: OptionalBool
  attributeFilter {.jsdefault: trace(JS_UNDEFINED).}: JSValueTraced

proc queueRecord*(observer: MutationObserver; target: EventTarget;
    t: MutationRecordType; name, namespace: CAtom; oldValue: RefString;
    addedNodes, removedNodes: JSRootRef;
    previousSibling, nextSibling: EventTarget) =
  let record = jsNew MutationRecordObj(
    t: t,
    target: target,
    attributeName: name,
    attributeNamespace: namespace,
    oldValue: oldValue,
    addedNodes: addedNodes,
    removedNodes: removedNodes,
    previousSibling: previousSibling,
    nextSibling: nextSibling
  )
  if record != nil:
    observer.records.add(record)

jsClassDef(MutationObserver):
  proc newMutationObserver(ctx: JSContext; callback: JSValueConst):
      MutationObserver {.jsctor.} =
    jsNew MutationObserverObj(callback: ctx.dupTraceObj(callback))

  proc mark(rt: JSRuntime; this: MutationObserver; markFunc: JS_MarkFunc)
      {.jsmark.} =
    for record in this.records:
      rt.markObj(record, markFunc)

  proc observe(ctx: JSContext; this: MutationObserver; jsTarget: JSValueConst;
      jsInit: JSValueConst = JS_UNDEFINED): JSValue {.jsfunc.} =
    var targetp: pointer
    ?ctx.fromJS(jsTarget, nodeClassID, targetp)
    let target = cast[ptr EventTargetObj](targetp)
    var init = MutationObserverInit(
      attributeFilter: trace(JS_UNDEFINED)
    )
    if not JS_IsUndefined(jsInit):
      ?ctx.fromJS(jsInit, init)
    var flags: set[ObservedItemFlag]
    var attributeFilter: seq[CAtom]
    if not JS_IsUndefined(init.attributeFilter):
      flags.incl(oifAttributeFilter)
    if oifAttributeFilter in flags:
      ?ctx.fromJS(init.attributeFilter, attributeFilter)
    if (oifAttributeFilter in flags or init.attributeOldValue == obTrue) and
        init.attributes == obFalse or
        init.characterDataOldValue == obTrue and init.characterData == obFalse:
      return JS_ThrowTypeError(ctx, "incompatible MutationObserver flags")
    if oifAttributeFilter in flags or init.attributeOldValue != obNone or
        init.attributes == obTrue:
      flags.incl(oifAttributes)
    if init.attributes == obFalse:
      flags.excl(oifAttributes)
    if init.attributeOldValue == obTrue:
      flags.incl(oifAttributeOldValue)
    if init.characterDataOldValue != obNone or init.characterData == obTrue:
      flags.incl(oifCharacterData)
    if init.characterData == obFalse:
      flags.excl(oifCharacterData)
    if init.characterDataOldValue == obTrue:
      flags.incl(oifCharacterDataOldValue)
    if init.childList:
      flags.incl(oifChildList)
    block add:
      for el in cast[EventTarget](target).mutationObservers:
        if el.observer == this:
          #TODO remove transient registered observers
          el.flags = flags
          el.attributeFilter = move(attributeFilter)
          break add
      let el = EventListener(
        t: eltMutationObserver,
        observer: this,
        flags: flags,
        attributeFilter: move(attributeFilter)
      )
      var it = target.eventListener
      if it == nil:
        target.eventListener = el
      else:
        # insert after event listeners
        while it.next != nil and it.next.t == eltEventListener:
          it = it.next
        el.next = it.next
        it.next = el
      this.nodes.add(target)
    return JS_UNDEFINED

  proc disconnect(this: MutationObserver) {.jsfunc.} =
    for node in this.nodes:
      var it = node.eventListener
      var prev: EventListener = nil
      while it != nil:
        if it.t == eltMutationObserver and it.observer == this:
          if prev == nil:
            node.eventListener = it.next
          else:
            prev.next = it.next
        prev = it
        it = it.next
    # the spec forgot about nodes, but surely we want to empty it?
    this.nodes = @[]
    this.records = @[]

  proc takeRecords(this: MutationObserver): seq[MutationRecord] {.jsfunc.} =
    move(this.records)

# EventTarget
template asEventTarget*[T: EventTargetObj](x: JSRef[T]): EventTarget =
  EventTarget(x)

proc defaultPassiveValue(eventType: CAtom; eventTarget: EventTarget): bool =
  const check = [satTouchstart, satTouchmove, satWheel, satMousewheel]
  return eventType.toStaticAtom() in check and eventTarget.isDefaultPassive()

proc findEventListener(ctx: JSContext; eventTarget: EventTarget;
    eventType: CAtom; callback: JSValueConst; capture: bool): EventListener =
  for it in eventTarget.eventListeners:
    if not it.internal and not it.removed and it.eventType == eventType and
        ctx.strictEquals(it.callback.value, callback) and
        it.capture == capture:
      return it
  nil

proc findInternalEventListener(ctx: JSContext; eventTarget: EventTarget;
    eventType: StaticAtom): EventListener =
  for it in eventTarget.eventListeners:
    if it.internal and not it.removed and it.eventType == eventType:
      return it
  nil

proc hasEventListener*(eventTarget: EventTarget; eventType: CAtom): bool =
  for it in eventTarget.eventListeners:
    if it.eventType == eventType:
      return true
  false

proc invoke(ctx: JSContext; listener: EventListener; event: Event): JSValue =
  if listener.callback == nil:
    return JS_UNDEFINED
  let jsTarget = ctx.toJS(event.currentTarget)
  if JS_IsException(jsTarget):
    return JS_EXCEPTION
  let jsEvent = ctx.toJS(event)
  if JS_IsException(jsEvent):
    JS_FreeValue(ctx, jsTarget)
    return JS_EXCEPTION
  var ret = JS_UNINITIALIZED
  #TODO user object operation
  let callback = JS_DupValue(ctx, listener.callback.value)
  if JS_IsFunction(ctx, callback):
    # Apparently it's a bad idea to call a function that can then delete
    # the reference it was called from (hence the dup).
    ret = ctx.call(callback, jsTarget, jsEvent)
  else:
    assert JS_IsObject(callback)
    ret = JS_GetPropertyStr(ctx, callback, "handleEvent")
    if not JS_IsException(ret):
      ret = ctx.callFree(ret, callback, jsEvent)
  JS_FreeValue(ctx, callback)
  JS_FreeValue(ctx, jsTarget)
  JS_FreeValue(ctx, jsEvent)
  return ret

proc removeEventListenerData(ctx: JSContext; _: JSValueConst;
    argc: cint; argv: JSValueConstArray; magic: cint;
    funcData: JSValueConstArray): JSValue {.cdecl.} =
  var this: EventTarget
  ?ctx.fromJS(funcData[0], this)
  var eventType: CAtom
  ?ctx.fromJS(funcData[1], eventType)
  if ctx.removeEventListener(this, eventType, funcData[2], funcData[3]).isErr:
    return JS_EXCEPTION
  return JS_UNDEFINED

proc addEventListener(ctx: JSContext; target: EventTarget; eventType: CAtom;
    capture, once, internal: bool; passive: Option[bool];
    callback: JSValueConst; signal: AbortSignal): Opt[void] =
  if signal != nil and signal.aborted:
    return ok()
  let passive = passive.get(defaultPassiveValue(eventType, target))
  if ctx.findEventListener(target, eventType, callback, capture) == nil:
    # dedup
    let listener = EventListener(
      t: eltEventListener,
      eventType: eventType,
      capture: capture,
      internal: internal,
      callback: ctx.dupTraceObj(callback),
      next: target.eventListener,
      signal: signal
    )
    if passive:
      listener.eflags.incl(elfPassive)
    if once:
      listener.eflags.incl(elfOnce)
    target.eventListener = listener
    if signal != nil:
      let jsTarget = ctx.toJS(target)
      if JS_IsException(jsTarget):
        return err()
      let jsType = ctx.toJS(eventType)
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
  var signal: AbortSignal
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
    eventType: StaticAtom) =
  var prev: EventListener = nil
  for it in eventTarget.eventListeners:
    if it.eventType == eventType and it.internal:
      it.callback = JSObject(nil)
      it.removed = true
      if prev == nil:
        eventTarget.eventListener = it.next
      else:
        prev.next = it.next
      break
    prev = it

proc addInternalEventListener(ctx: JSContext; eventTarget: EventTarget;
    eventType: StaticAtom; callback: JSValueConst): Opt[void] =
  ctx.removeInternalEventListener(eventTarget, eventType)
  ctx.addEventListener(eventTarget, eventType.view(), capture = false,
    once = false, internal = true, passive = none(bool), callback,
    signal = AbortSignal(nil))

# Event reflection
proc eventReflectGetImpl*(ctx: JSContext; this: EventTarget; name: StaticAtom):
    JSValue {.cdecl.} =
  if this == nil:
    return JS_EXCEPTION
  let el = ctx.findInternalEventListener(this, name)
  if el == nil:
    return JS_NULL
  return JS_DupValue(ctx, el.callback.value)

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
  let eventType = dctx.event.eventType
  let bubbles = efBubbles in dctx.event.flags
  let isLoad = dctx.event.eventType == satLoad
  var it = target
  while it != nil:
    var capture: seq[EventListener] = @[]
    var bubble: seq[EventListener] = @[]
    for el in it.eventListeners:
      if el.eventType == eventType:
        if el.capture:
          capture.add(el)
        elif bubbles or it == target:
          bubble.add(el)
    if capture.len > 0:
      dctx.capture.add(DispatchItem(target: it, els: move(capture)))
    if bubble.len > 0:
      dctx.bubble.add(DispatchItem(target: it, els: move(bubble)))
    it = it.getParentImpl(isLoad)

proc dispatchEvent0(dctx: var DispatchContext; item: DispatchItem) =
  let ctx = dctx.ctx
  let event = dctx.event
  event.currentTarget = item.target
  for el in item.els.ritems:
    if el.removed:
      continue # removed, presumably by a previous handler
    if elfPassive in el.eflags:
      event.flags.incl(efInPassiveListener)
    let e = ctx.invoke(el, event)
    if JS_IsException(e):
      ctx.logException()
    JS_FreeValue(ctx, e)
    if elfPassive in el.eflags:
      event.flags.excl(efInPassiveListener)
    if efCanceled in event.flags:
      dctx.canceled = true
    if {efStopPropagation, efStopImmediatePropagation} * event.flags != {}:
      dctx.stop = true
    if efStopImmediatePropagation in event.flags:
      break

proc dispatch*(ctx: JSContext; target: EventTarget; event: Event;
    targetOverride = false): bool =
  let prev = ctx.setEvent(event)
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
  discard ctx.setEvent(prev)
  return dctx.canceled

jsClassPublicDef(EventTarget):
  proc finalize(rt: JSRuntime; this: EventTarget) {.jsfin.} =
    # Can't take rt as param here, because elements may be unbound in JS.
    for el in this.eventListenersRaw:
      if el.t == eltMutationObserver:
        let i = el.observer.nodes.find(cast[ptr EventTargetObj](this))
        if i >= 0: # might have already been destroyed
          el.observer.nodes.del(i)

  proc mark(rt: JSRuntime; this: EventTarget; markFunc: JS_MarkFunc)
      {.jsmark.} =
    for el in this.eventListenersRaw:
      case el.t
      of eltEventListener:
        JS_MarkValue(rt, el.callback, markFunc)
        rt.markObj(el.signal, markFunc)
      of eltMutationObserver:
        rt.markObj(el.observer, markFunc)

  proc newEventTarget(): EventTarget {.jsctor.} =
    jsNew EventTargetObj()

  proc addEventListener(ctx: JSContext; eventTarget: EventTarget;
      eventType: CAtom; callback: JSValueConst;
      options: JSValueConst = JS_UNDEFINED): Opt[void] {.jsfunc.} =
    if not JS_IsObject(callback) and not JS_IsNull(callback):
      JS_ThrowTypeError(ctx, "callback is not an object")
      return err()
    var res: FlattenMoreResult
    ?ctx.flattenMore(options, res)
    ctx.addEventListener(eventTarget, eventType, res.capture, res.once,
      internal = false, res.passive, callback, res.signal)

  proc removeEventListener(ctx: JSContext; eventTarget: EventTarget;
      eventType: CAtom; callback: JSValueConst;
      options: JSValueConst = JS_UNDEFINED): Opt[void] {.jsfunc.} =
    let capture = ?ctx.flatten(options)
    var prev: EventListener = nil
    for it in eventTarget.eventListeners:
      if not it.internal and not it.removed and it.eventType == eventType and
          ctx.strictEquals(it.callback.value, callback) and
          it.capture == capture:
        it.callback = JSObject(nil)
        it.removed = true
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

proc fromJSEventTarget(ctx: JSContext; this: JSValueConst;
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
    JS_ThrowTypeErrorInvalidClass(ctx, tclassid)
    return EventTarget(nil)
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
  if ctx.getOpaque() == nil:
    return ok()
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
    rt.freeValues(this.abortSteps)

  proc mark(rt: JSRuntime; this: AbortSignal; markFun: JS_MarkFunc) {.
      jsmark.} =
    for it in this.abortSteps:
      JS_MarkValue(rt, it, markFun)

  proc abort(ctx: JSContext; reason: JSValueConst = JS_UNDEFINED): AbortSignal
      {.jsstfunc.} =
    jsNew AbortSignalObj(reason: ctx.toSignalReason(reason))

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
    let signal = jsNew AbortSignalObj(reason: JS_UNDEFINED)
    if signal == nil:
      return AbortController(nil)
    jsNew AbortControllerObj(signal: signal)

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
      let event = newTrustedEvent(satAbort, signal.asEventTarget,
        bubbles = false, cancelable = false)
      discard ctx.dispatch(signal.asEventTarget, event)
    return JS_UNDEFINED

proc addEventTarget*(ctx: JSContext): JSCode =
  # must do this first, so that we can init Window ASAP
  ctx.registerClass(EventTargetDef)

proc addEventModule*(ctx: JSContext): Opt[void] =
  ?ctx.registerClass(EventDef)
  ?ctx.registerClass(CustomEventDef)
  ?ctx.registerClass(MessageEventDef)
  ?ctx.registerClass(SubmitEventDef)
  ?ctx.registerClass(UIEventDef)
  ?ctx.registerClass(MouseEventDef)
  ?ctx.registerClass(InputEventDef)
  ?ctx.defineConsts(EventDef.id, EventPhase)
  ?ctx.registerClass(MutationRecordDef)
  ?ctx.registerClass(MutationObserverDef)
  ?ctx.registerClass(AbortSignalDef)
  ?ctx.addAbortSignalEvents()
  ?ctx.registerClass(AbortControllerDef)
  ok()

{.pop.} # raises: []
