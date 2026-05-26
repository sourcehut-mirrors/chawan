{.push raises: [].}

import html/catom
import html/script
import monoucha/jsbind
import monoucha/jstypes
import monoucha/quickjs
import monoucha/tojs
import types/jsopt
import types/opt

type
  DOMRectReadOnly* = ref object of RootObj
    x* {.jsget.}: float64
    y* {.jsget.}: float64
    width* {.jsget.}: float64
    height* {.jsget.}: float64

  DOMRect* = ref object of DOMRectReadOnly

  DOMRectList* = ref object
    list*: seq[DOMRect]

  DOMRectInit = object of JSDict
    x {.jsdefault.}: float64
    y {.jsdefault.}: float64
    width {.jsdefault.}: float64
    height {.jsdefault.}: float64

jsDestructor(DOMRectReadOnly)
jsDestructor(DOMRect)
jsDestructor(DOMRectList)

# DOMRectReadOnly
proc newDOMRectReadOnly(x = 0'f64; y = 0'f64; width = 0'f64; height = 0'f64):
    DOMRectReadOnly {.jsctor.} =
  DOMRectReadOnly(x: x, y: y, width: width, height: height)

proc fromRectReadOnly(other = DOMRectInit()): DOMRectReadOnly {.
    jsstfunc: "DOMRectReadOnly#fromRect".} =
  newDOMRectReadOnly(other.x, other.y, other.width, other.height)

proc left(rect: DOMRectReadOnly): float64 {.jsfget.} =
  return min(rect.x, rect.x + rect.width)

proc right(rect: DOMRectReadOnly): float64 {.jsfget.} =
  return max(rect.x, rect.x + rect.width)

proc top(rect: DOMRectReadOnly): float64 {.jsfget.} =
  return min(rect.y, rect.y + rect.height)

proc bottom(rect: DOMRectReadOnly): float64 {.jsfget.} =
  return max(rect.y, rect.y + rect.height)

#TODO toJSON

# DOMRect
proc newDOMRect*(x = 0'f64; y = 0'f64; width = 0'f64; height = 0'f64):
    DOMRect {.jsctor.} =
  DOMRect(x: x, y: y, width: width, height: height)

proc getX(rect: DOMRect): float64 {.jsfget: "x".} =
  rect.x

proc getY(rect: DOMRect): float64 {.jsfget: "y".} =
  rect.y

proc getWidth(rect: DOMRect): float64 {.jsfget: "width".} =
  rect.width

proc getHeight(rect: DOMRect): float64 {.jsfget: "height".} =
  rect.height

proc setX(rect: DOMRect; x: float64) {.jsfset: "x".} =
  rect.x = x

proc setY(rect: DOMRect; y: float64) {.jsfset: "y".} =
  rect.y = y

proc setWidth(rect: DOMRect; width: float64) {.jsfset: "width".} =
  rect.width = width

proc setHeight(rect: DOMRect; height: float64) {.jsfset: "height".} =
  rect.height = height

proc fromRect(other = DOMRectInit()): DOMRect {.jsstfunc: "DOMRect".} =
  newDOMRect(other.x, other.y, other.width, other.height)

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
  let domRectReadOnlyCID = ctx.registerType(DOMRectReadOnly)
  ?domRectReadOnlyCID
  ?ctx.registerType(DOMRect, parent = domRectReadOnlyCID)
  ?ctx.registerType(DOMRectList)
  ok()

{.pop.}
