{.push raises: [].}

import std/math
import std/times

import config/conftypes
import html/event
import io/timeout
import js/fromjs
import js/jsbind
import js/jsref
import js/jstypes
import js/quickjs
import js/tojs
import js/jsopt
import types/opt

type
  PerformanceObj {.final.} = object of EventTargetObj
    timeOrigin: float64
    scripting: ScriptingMode
    id: uint64

  Performance* = JSRef[PerformanceObj]

  PerformanceEntryObj {.pure.} = object of JSRootObj
    id: uint64
    name: string
    startTime: float64
    duration: float64
    navigationId: uint64

  PerformanceEntry = JSRef[PerformanceEntryObj]

  PerformanceMarkObj {.pure, final.} = object of PerformanceEntryObj
    detail: JSValue

  PerformanceMark = JSRef[PerformanceMarkObj]

# Forward declarations
proc getClassID(t: typedesc[Performance]): JSClassID
proc getClassID(t: typedesc[PerformanceMark]): JSClassID

# Performance
proc getTime(scripting: ScriptingMode): float64 =
  if scripting == smApp:
    let t = getTime()
    return float64(t.toUnix() * 1000) + floor(t.nanosecond / 100_000) / 10
  return float64(getUnixMillis())

proc newPerformance*(scripting: ScriptingMode): Performance =
  jsNew PerformanceObj(timeOrigin: getTime(scripting), scripting: scripting)

proc getEntryId(this: Performance): uint64 =
  result = this.id
  inc this.id

jsClassDef(Performance):
  jsextends EventTargetDef

  jsget Performance, timeOrigin

  proc now(this: Performance): float64 {.jsfunc.} =
    return getTime(this.scripting) - this.timeOrigin

  proc getEntries(ctx: JSContext; this: Performance): JSValue {.jsfunc.} =
    return JS_NewArray(ctx)

  proc getEntriesByType(ctx: JSContext; this: Performance;
      t: DOMString): JSValue {.jsfunc.} =
    return JS_NewArray(ctx)

  proc getEntriesByName(ctx: JSContext; this: Performance;
      name: DOMString; t: JSValueConst = JS_UNDEFINED): JSValue {.jsfunc.} =
    return JS_NewArray(ctx)

  proc mark(ctx: JSContext; this: Performance; name: DOMString;
      init: JSValueConst = JS_UNDEFINED): JSValue {.jsfunc.} =
    var startTime: float64
    if ?ctx.fromJSGetProp(init, "startTime", startTime):
      if startTime < 0:
        return JS_ThrowTypeError(ctx, "startTime must not be negative")
    else:
      startTime = this.now()
    var detail: JSValue
    if not ?ctx.fromJSGetProp(init, "detail", detail):
      detail = JS_NULL
    #TODO serialize/deserialize detail
    let mark = jsNew PerformanceMarkObj(
      id: this.getEntryId(),
      name: $name,
      startTime: startTime,
      detail: detail
    )
    ctx.toJSNew(mark)

# PerformanceEntry
jsClassDef(PerformanceEntry):
  jsget PerformanceEntry, id
  jsget PerformanceEntry, name
  jsget PerformanceEntry, startTime
  jsget PerformanceEntry, duration
  jsget PerformanceEntry, navigationId

  proc entryType(this: PerformanceEntry): string {.jsfget.} =
    if this of PerformanceMark:
      return "mark"
    return ""

# PerformanceMark
jsClassDef(PerformanceMark):
  jsextends PerformanceEntryDef

  jsget PerformanceMark, detail

  #TODO constructor

proc addPerformanceModule*(ctx: JSContext): Opt[void] =
  ?ctx.registerClass(PerformanceDef)
  ?ctx.registerClass(PerformanceEntryDef)
  ?ctx.registerClass(PerformanceMarkDef)
  ok()

{.pop.}
