{.push raises: [].}

import html/catom
import html/script
import monoucha/jsbind
import monoucha/quickjs
import monoucha/tojs
import types/jsopt
import types/opt

type
  DOMRect* = ref object
    x* {.jsgetset.}: float64
    y* {.jsgetset.}: float64
    width* {.jsgetset.}: float64
    height* {.jsgetset.}: float64

  DOMRectList* = ref object
    list*: seq[DOMRect]

jsDestructor(DOMRect)
jsDestructor(DOMRectList)

# DOMRect
proc left(rect: DOMRect): float64 {.jsfget.} =
  return min(rect.x, rect.x + rect.width)

proc right(rect: DOMRect): float64 {.jsfget.} =
  return max(rect.x, rect.x + rect.width)

proc top(rect: DOMRect): float64 {.jsfget.} =
  return min(rect.y, rect.y + rect.height)

proc bottom(rect: DOMRect): float64 {.jsfget.} =
  return max(rect.y, rect.y + rect.height)

# DOMRectList
proc length(this: DOMRectList): int {.jsfget.} =
  this.list.len

proc getter(ctx: JSContext; this: DOMRectList; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  return case ctx.fromIdx(atom, u)
  of fiIdx:
    if int64(u) < int64(this.list.len):
      ctx.toJS(this.list[int(u)]).uninitIfNull()
    else:
      JS_UNINITIALIZED
  of fiStr: JS_UNINITIALIZED
  of fiErr: JS_EXCEPTION

proc addDOMRectModule*(ctx: JSContext): Opt[void] =
  ?ctx.registerType(DOMRect)
  ?ctx.registerType(DOMRectList)
  ok()

{.pop.}
