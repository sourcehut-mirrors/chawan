{.push raises: [].}

import std/algorithm
import std/times

import io/console
import monoucha/fromjs
import monoucha/javascript
import monoucha/jsutils
import monoucha/quickjs
import types/opt

type
  TimeoutType* = enum
    ttTimeout = "setTimeout handler"
    ttInterval = "setInterval handler"

  TimeoutEntry = ref object
    t: TimeoutType
    id: int32
    val: JSValue
    args: seq[JSValue]
    expires: int64
    timeout: int32
    dead: bool

  EvalJSFree* = proc(opaque: RootRef; src, file: string) {.nimcall, raises: [].}

  TimeoutState* = ref object
    timeoutid: int32
    sorted: bool
    timeouts: seq[TimeoutEntry]
    jsctx: JSContext
    jsrt: JSRuntime
    evalJSFree: EvalJSFree
    opaque: RootRef

proc newTimeoutState*(jsctx: JSContext; evalJSFree: EvalJSFree;
    opaque: RootRef): TimeoutState =
  return TimeoutState(
    jsrt: JS_GetRuntime(jsctx),
    jsctx: jsctx,
    evalJSFree: evalJSFree,
    opaque: opaque,
    sorted: true
  )

proc empty*(state: TimeoutState): bool =
  return state.timeouts.len == 0

proc clearTimeout0(state: var TimeoutState; i: int) =
  let entry = state.timeouts[i]
  JS_FreeValueRT(state.jsrt, entry.val)
  for arg in entry.args:
    JS_FreeValueRT(state.jsrt, arg)
  state.timeouts.del(i)
  if state.timeouts.len != i: # only set if we del'd in the middle
    state.sorted = false

proc clearTimeout*(state: var TimeoutState; id: int32) =
  for entry in state.timeouts:
    if entry.id == id:
      entry.dead = true
      break

proc getUnixMillis*(): int64 =
  let now = getTime()
  return now.toUnix() * 1000 + now.nanosecond div 1_000_000

proc setTimeout*(state: var TimeoutState; t: TimeoutType; handler: JSValueConst;
    timeout: int32; args: openArray[JSValueConst]): int32 =
  let id = state.timeoutid
  inc state.timeoutid
  let entry = TimeoutEntry(
    t: t,
    id: id,
    val: JS_DupValueRT(state.jsrt, handler),
    expires: getUnixMillis() + int64(timeout),
    timeout: timeout
  )
  for arg in args:
    entry.args.add(JS_DupValueRT(state.jsrt, arg))
  state.timeouts.add(entry)
  state.sorted = false
  return id

proc runEntry(state: var TimeoutState; entry: TimeoutEntry; console: Console) =
  if JS_IsFunction(state.jsctx, entry.val):
    let ret = JS_Call(state.jsctx, entry.val, JS_UNDEFINED,
      cint(entry.args.len), entry.args.toJSValueArray())
    if JS_IsException(ret):
      console.writeException(state.jsctx)
    JS_FreeValueRT(state.jsrt, ret)
  else:
    var s: string
    if state.jsctx.fromJS(entry.val, s).isOk:
      state.evalJSFree(state.opaque, s, $entry.t)

# for poll
proc sortAndGetTimeout*(state: var TimeoutState): cint =
  if state.timeouts.len == 0:
    return -1
  if not state.sorted:
    state.timeouts.sort(proc(a, b: TimeoutEntry): int =
      cmp(a.expires, b.expires), order = Descending)
    state.sorted = true
  let now = getUnixMillis()
  return cint(max(state.timeouts[^1].expires - now, -1))

proc run*(state: var TimeoutState; console: Console): bool =
  let now = getUnixMillis()
  var found = false
  var H = state.timeouts.high
  for i in countdown(H, 0):
    if state.timeouts[i].expires > now:
      break
    let entry = state.timeouts[i]
    if entry.dead:
      continue
    state.runEntry(entry, console)
    found = true
    case entry.t
    of ttTimeout:
      entry.dead = true
    of ttInterval:
      entry.expires = now + entry.timeout
      state.sorted = false
  # we can't just delete timeouts in the above loop, because the JS
  # timeout handler may clear them in an arbitrary order
  H = state.timeouts.high
  for i in countdown(H, 0):
    if state.timeouts[i].dead:
      state.clearTimeout0(i)
  return found

proc clearAll*(state: var TimeoutState) =
  for entry in state.timeouts:
    JS_FreeValueRT(state.jsrt, entry.val)
    for arg in entry.args:
      JS_FreeValueRT(state.jsrt, arg)
  state.timeouts.setLen(0)

{.pop.} # raises: []
