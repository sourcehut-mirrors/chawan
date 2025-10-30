import std/math
import std/times

import config/conftypes
import html/event
import io/timeout
import monoucha/fromjs
import monoucha/jsbind
import monoucha/quickjs
import monoucha/tojs

type Performance* = ref object of EventTarget
  timeOrigin {.jsget.}: float64
  scripting: ScriptingMode

jsDestructor(Performance)

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

proc addPerformanceModule*(ctx: JSContext; eventTargetCID: JSClassID) =
  ctx.registerType(Performance, parent = eventTargetCID)
