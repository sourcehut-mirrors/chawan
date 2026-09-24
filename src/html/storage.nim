{.push raises: [].}

import std/options

import html/catom
import html/domexception
import html/event
import js/constcharp
import js/fromjs
import js/jsbind
import js/jsnull
import js/jsopaque
import js/jspropenumlist
import js/jsref
import js/jstypes
import js/jsutils
import js/quickjs
import js/tojs
import utils/opt

type
  StorageObj = object
    map: seq[tuple[key, value: string]]

  Storage = JSRef[StorageObj]

  StorageNil = JSNullRef[StorageObj]

  StorageEventObj {.pure, final.} = object of EventObj
    key: Option[string]
    oldValue: Option[string]
    newValue: Option[string]
    url: string
    storageArea: StorageNil

  StorageEvent = JSRef[StorageEventObj]

proc getClassID(t: typedesc[Storage]): JSClassID

# Storage
proc find(this: Storage; key: DOMString): int =
  for i in 0 ..< this.map.len:
    if this.map[i].key == key.toOpenArray():
      return i
  return -1

jsClassDef(Storage):
  proc length(this: Storage): uint32 {.jsfget.} =
    return uint32(this.map.len)

  proc key(ctx: JSContext; this: Storage; u: uint32): JSValue {.jsfunc.} =
    if u < uint32(this.map.len):
      return ctx.toJS(this.map[int(u)].key)
    return JS_NULL

  proc getItem(ctx: JSContext; this: Storage; s: DOMString): JSValue
      {.jsfunc.} =
    let i = this.find(s)
    if i >= 0:
      return ctx.toJS(this.map[i].value)
    return JS_NULL

  proc setItem(ctx: JSContext; this: Storage; key, value: DOMString): JSValue
      {.jsfunc.} =
    let i = this.find(key)
    if i >= 0:
      this.map[i].value = $value
    else:
      if this.map.len >= 64:
        return JS_ThrowDOMException(ctx, "QuotaExceededError",
          "quota exceeded")
      this.map.add(($key, $value))
    return JS_UNDEFINED

  proc removeItem(this: Storage; key: DOMString) {.jsfunc.} =
    let i = this.find(key)
    if i >= 0:
      this.map.del(i)

  proc names(ctx: JSContext; this: Storage): JSPropertyEnumList
      {.jspropnames.} =
    var list = newJSPropertyEnumList(ctx, uint32(this.map.len))
    for it in this.map:
      list.add(it.key)
    return list

  proc getter(ctx: JSContext; this: Storage; s: DOMString): JSValue
      {.jsgetownprop.} =
    return ctx.toJS(ctx.getItem(this, s)).uninitIfNull()

  proc setter(ctx: JSContext; this: Storage; k, v: DOMString): JSValue
      {.jssetprop.} =
    return ctx.setItem(this, k, v)

  proc delete(this: Storage; k: DOMString): bool {.jsdelprop.} =
    this.removeItem(k)
    return true

proc storageAutoInitGetter(ctx: JSContext; this: JSValueConst; argc: cint;
    argv: JSValueConstArray; magic: cint; func_data: JSValueArray): JSValue
    {.cdecl.} =
  let ctxOpaque = ctx.getOpaque()
  if not ctx.strictEquals(this, ctxOpaque.global.value):
    return JS_ThrowTypeErrorInvalidClass(ctx, ctxOpaque.gclass)
  # data[0] is object
  if JS_IsUndefined(func_data[0]):
    let storage = jsNew StorageObj()
    let obj = ctx.toJSNew(storage)
    if JS_IsException(obj):
      return obj
    func_data[0] = obj
  return JS_DupValue(ctx, func_data[0])

proc registerAutoInitStorage(ctx: JSContext; name: cstring): JSCode =
  let ctxOpaque = ctx.getOpaque()
  let getter = ctx.newGetterFunctionData(storageAutoInitGetter,
    name, cast[cint](StorageDef.id), JS_UNDEFINED)
  if JS_IsException(getter):
    return fjErr
  let prop = JS_NewAtom(ctx, cstringConst(name))
  if JS_DefinePropertyGetSet(ctx, ctxOpaque.global.value, prop, getter,
      JS_UNDEFINED, cint(JS_PROP_CONFIGURABLE or JS_PROP_ENUMERABLE)) < 0:
    return fjErr
  fjOk

# StorageEvent
type StorageEventInit = object of EventInit
  key {.jsdefault.}: Option[string] #TODO DOMString
  oldValue {.jsdefault.}: Option[string] #TODO DOMString
  newValue {.jsdefault.}: Option[string] #TODO DOMString
  url {.jsdefault.}: string
  storageArea {.jsdefault.}: StorageNil

jsClassDef(StorageEvent):
  jsextends EventDef

  jsget StorageEvent, key
  jsget StorageEvent, oldValue
  jsget StorageEvent, newValue
  jsget StorageEvent, url
  jsget StorageEvent, storageArea

  proc newStorageEvent(eventType: CAtom;
      eventInitDict: sink StorageEventInit = StorageEventInit()):
      StorageEvent {.jsctor.} =
    let event = jsNew StorageEventObj(
      key: move(eventInitDict.key),
      oldValue: move(eventInitDict.oldValue),
      newValue: move(eventInitDict.newValue),
      url: move(eventInitDict.url),
      storageArea: move(eventInitDict.storageArea)
    )
    if event != nil:
      event.asEvent.innerEventCreationSteps(EventInit(eventInitDict))
    event

  proc initStorageEvent(this: StorageEvent; eventType: CAtom; bubbles = false;
      cancelable = false; key = none(string); oldValue = none(string);
      newValue = none(string); url: sink string = "";
      storageArea = StorageNil(nil)) {.jsfunc.} =
    if efDispatch notin this.flags:
      this.key = key
      this.oldValue = oldValue
      this.newValue = newValue
      this.storageArea = storageArea
      this.asEvent.initialize(eventType, bubbles, cancelable)

proc addStorageModule*(ctx: JSContext): JSCode =
  ?ctx.registerClass(StorageDef)
  ?ctx.registerClass(StorageEventDef)
  let ctxOpaque = ctx.getOpaque()
  if ctxOpaque == nil:
    return fjOk
  ?ctx.registerAutoInitStorage("localStorage")
  ctx.registerAutoInitStorage("sessionStorage")

{.pop.}
