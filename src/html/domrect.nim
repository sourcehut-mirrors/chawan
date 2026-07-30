{.push raises: [].}

import html/catom
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jstypes
import monoucha/jsutils
import monoucha/quickjs
import monoucha/tojs
import types/jsopt
import types/opt

type
  DOMRectReadOnly* = ref object of JSRootObj
    x*: float64
    y*: float64
    width*: float64
    height*: float64

  DOMRect* {.final.} = ref object of DOMRectReadOnly

  DOMRectList* = ref object
    list*: seq[DOMRect]

  DOMRectInit = object of JSDict
    x {.jsdefault.}: float64
    y {.jsdefault.}: float64
    width {.jsdefault.}: float64
    height {.jsdefault.}: float64

jsDestructor(DOMRectList)

# DOMRectReadOnly
jsClassDef(DOMRectReadOnly):
  jsget DOMRectReadOnly, x
  jsget DOMRectReadOnly, y
  jsget DOMRectReadOnly, width
  jsget DOMRectReadOnly, height

  proc newDOMRectReadOnly(x = 0'f64; y = 0'f64; width = 0'f64; height = 0'f64):
      DOMRectReadOnly {.jsctor.} =
    DOMRectReadOnly(x: x, y: y, width: width, height: height)

  proc fromRectReadOnly(other = DOMRectInit()): DOMRectReadOnly {.
      jsstfunc: "fromRect".} =
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
jsClassDef(DOMRect):
  jsextends DOMRectReadOnlyDef

  jsgetset DOMRect, x
  jsgetset DOMRect, y
  jsgetset DOMRect, width
  jsgetset DOMRect, height

  proc newDOMRect*(x = 0'f64; y = 0'f64; width = 0'f64; height = 0'f64):
      DOMRect {.jsctor.} =
    DOMRect(x: x, y: y, width: width, height: height)

  proc fromRect(other = DOMRectInit()): DOMRect {.jsstfunc.} =
    newDOMRect(other.x, other.y, other.width, other.height)

# DOMRectList
jsClassDef(DOMRectList):
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
  ?ctx.registerClass(DOMRectReadOnlyDef)
  ?ctx.registerClass(DOMRectDef)
  ?ctx.registerClass(DOMRectListDef)
  ok()

{.pop.}
