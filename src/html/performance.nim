import std/math
import std/times

import config/conftypes
import html/event
import io/timeout
import monoucha/fromjs
import monoucha/jsbind
import monoucha/quickjs
import monoucha/tojs
import types/jsopt
import types/opt

type
  Performance* = ref object of EventTarget
    timeOrigin {.jsget.}: float64
    scripting: ScriptingMode
    id: uint64

  PerformanceEntry = ref object of RootObj
    id {.jsget.}: uint64
    name {.jsget.}: string
    startTime {.jsget.}: float64
    duration {.jsget.}: float64
    navigationId {.jsget.}: uint64

  PerformanceMark = ref object of PerformanceEntry
    detail {.jsget.}: JSValue

jsDestructor(Performance)
jsDestructor(PerformanceEntry)
jsDestructor(PerformanceMark)

proc finalize(rt: JSRuntime; this: PerformanceMark) {.jsfin.} =
  JS_FreeValueRT(rt, this.detail)

proc mark(rt: JSRuntime; this: PerformanceMark; markFun: JS_MarkFunc)
    {.jsmark.} =
  JS_MarkValue(rt, this.detail, markFun)

proc getTime(scripting: ScriptingMode): float64 =
  let t = getTime()
  if scripting == smApp:
    return float64(t.toUnix() * 1000) + floor(t.nanosecond / 100_000) / 10
  return float64(getUnixMillis())

proc newPerformance*(scripting: ScriptingMode): Performance =
  return Performance(timeOrigin: getTime(scripting), scripting: scripting)

proc now(performance: Performance): float64 {.jsfunc.} =
  return getTime(performance.scripting) - performance.timeOrigin

proc getEntries(ctx: JSContext; performance: Performance): JSValue {.jsfunc.} =
  return JS_NewArray(ctx)

proc getEntriesByType(ctx: JSContext; performance: Performance; t: string):
    JSValue {.jsfunc.} =
  return JS_NewArray(ctx)

proc getEntriesByName(ctx: JSContext; performance: Performance; name: string;
    t: JSValueConst = JS_UNDEFINED): JSValue {.jsfunc.} =
  return JS_NewArray(ctx)

proc getEntryId(this: Performance): uint64 =
  result = this.id
  inc this.id

# PerformanceEntry
proc entryType(this: PerformanceEntry): string {.jsfget.} =
  if this of PerformanceMark:
    return "mark"
  return ""

# PerformanceMark
#TODO constructor

proc mark(ctx: JSContext; this: Performance; name: string;
    init: JSValueConst = JS_UNDEFINED): Opt[PerformanceMark] {.jsfunc.} =
  var startTime: float64
  if ?ctx.fromJSGetProp(init, "startTime", startTime):
    if startTime < 0:
      JS_ThrowTypeError(ctx, "startTime must not be negative")
      return err()
  else:
    startTime = this.now()
  var detail: JSValue
  if not ?ctx.fromJSGetProp(init, "detail", detail):
    detail = JS_NULL
  #TODO serialize/deserialize detail
  let mark = PerformanceMark(
    id: this.getEntryId(),
    name: name,
    startTime: startTime,
    detail: detail
  )
  ok(mark)

proc addPerformanceModule*(ctx: JSContext; eventTargetCID: JSClassID):
    Opt[void] =
  ?ctx.registerType(Performance, parent = eventTargetCID)
  let performanceEntryCID = ctx.registerType(PerformanceEntry)
  if performanceEntryCID == 0:
    return err()
  ?ctx.registerType(PerformanceMark, performanceEntryCID)
  ok()
