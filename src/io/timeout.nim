{.push raises: [].}

import std/algorithm
import std/times

import io/console
import monoucha/fromjs
import monoucha/jsutils
import monoucha/quickjs

type
  TimeoutType* = enum
    ttTimeout = "setTimeout handler"
    ttInterval = "setInterval handler"

  TimeoutEntry = ref object
    expires: int64
    val: JSValue
    args: seq[JSValue]
    timeout: int32
    id: int32
    dead: bool
    t: TimeoutType

  TimeoutState* = object
    timeoutid: int32
    needsSort: bool
    timeouts: seq[TimeoutEntry]

proc empty*(state: TimeoutState): bool =
  return state.timeouts.len == 0

proc clearTimeout0(state: var TimeoutState; ctx: JSContext; i: int) =
  let entry = state.timeouts[i]
  JS_FreeValue(ctx, entry.val)
  ctx.freeValues(entry.args)
  state.timeouts.del(i)
  if state.timeouts.len != i: # only set if we del'd in the middle
    state.needsSort = true

proc clearTimeout*(state: TimeoutState; id: int32) =
  for entry in state.timeouts:
    if entry.id == id:
      entry.dead = true
      break

proc getUnixMillis*(): int64 =
  let now = getTime()
  return now.toUnix() * 1000 + now.nanosecond div 1_000_000

proc setTimeout*(state: var TimeoutState; ctx: JSContext; t: TimeoutType;
    handler: JSValueConst; timeout: int32; args: varargs[JSValueConst]):
    int32 =
  let id = state.timeoutid
  if state.timeoutid == int32.high:
    state.timeoutid = 0
  inc state.timeoutid
  let entry = TimeoutEntry(
    t: t,
    id: id,
    val: JS_DupValue(ctx, handler),
    expires: getUnixMillis() + int64(timeout),
    timeout: timeout
  )
  for arg in args:
    entry.args.add(JS_DupValue(ctx, arg))
  state.timeouts.add(entry)
  state.needsSort = true
  return id

proc runEntry(ctx: JSContext; entry: TimeoutEntry; console: Console) =
  var ret = JS_EXCEPTION
  if JS_IsFunction(ctx, entry.val):
    ret = JS_Call(ctx, entry.val, JS_UNDEFINED, cint(entry.args.len),
      entry.args.toJSValueArray())
  else:
    var s: string
    if ctx.fromJS(entry.val, s).isOk:
      ret = ctx.eval(s, $entry.t, JS_EVAL_TYPE_GLOBAL)
  if JS_IsException(ret):
    console.writeException(ctx)
  JS_FreeValue(ctx, ret)

# for poll
proc sortAndGetTimeout*(state: var TimeoutState): cint =
  if state.timeouts.len == 0:
    return -1
  if state.needsSort:
    state.timeouts.sort(proc(a, b: TimeoutEntry): int =
      cmp(a.expires, b.expires), order = Descending)
    state.needsSort = false
  let now = getUnixMillis()
  return cint(max(state.timeouts[^1].expires - now, -1))

proc run*(state: var TimeoutState; ctx: JSContext; console: Console): bool =
  let now = getUnixMillis()
  var found = false
  var H = state.timeouts.high
  for i in countdown(H, 0):
    if state.timeouts[i].expires > now:
      break
    let entry = state.timeouts[i]
    if entry.dead:
      continue
    ctx.runEntry(entry, console)
    found = true
    case entry.t
    of ttTimeout:
      entry.dead = true
    of ttInterval:
      entry.expires = now + entry.timeout
      state.needsSort = true
  # we can't just delete timeouts in the above loop, because the JS
  # timeout handler may clear them in an arbitrary order
  H = state.timeouts.high
  for i in countdown(H, 0):
    if state.timeouts[i].dead:
      state.clearTimeout0(ctx, i)
  return found

proc mark*(rt: JSRuntime; state: TimeoutState; markFunc: JS_MarkFunc) =
  for entry in state.timeouts:
    JS_MarkValue(rt, entry.val, markFunc)
    for arg in entry.args:
      JS_MarkValue(rt, arg, markFunc)

proc finalize*(rt: JSRuntime; state: TimeoutState) =
  for entry in state.timeouts:
    JS_FreeValueRT(rt, entry.val)
    rt.freeValues(entry.args)

{.pop.} # raises: []
