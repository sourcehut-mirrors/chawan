{.push raises: [].}

import std/macros

import js/constcharp
import js/quickjs

when NimMajor < 2:
  import utils/twtstr

proc isLocal(t: NimNode): bool =
  let kind = t.kind
  # fast path
  if kind == nnkSym:
    return true
  if kind == nnkCall:
    return false
  # slow path
  var t = t
  while true:
    case t.kind
    of nnkCall, nnkCast:
      # if it's a call, see below.
      # if it's a cast, preserve it.
      return true
    of nnkStmtList, nnkStmtListExpr:
      # check the last child
      t = t[^1]
    of nnkSym, nnkIdent, nnkConv, nnkDerefExpr, nnkDotExpr, nnkHiddenDeref,
        nnkBracketExpr, nnkCheckedFieldExpr:
      # if it's a symbol, see below.
      # if it's a deref, dot, or bracket expr, we don't need a decref.
      # if it's a bracket expr, that means we're accessing an array/seq,
      # which always produces lent, so we don't need decref.
      # if it's a conv, preserve it.
      break
    else:
      # might want to check if it doesn't leak...
      warning("handle kind " & $t.kind)
      break
  true

macro dotGet*(T, t: untyped): untyped =
  # Evil hack to work around compiler bugs:
  # * if t is a funcall, we have to use a cast so that we don't
  #   accidentally disarm the destroy hook.  e.g.,
  #     node.document = other.rootNode.document
  #     # if we desugar this to
  #     #   let tmp1 = (ptr NodeObj)(other)
  #     #   let tmp = (ptr NodeObj)(tmp1.rootNode)
  #     #   (ptr NodeObj)(node).document = tmp.document
  #     # then, since tmp is not considered a JSRef anymore, the
  #     # compiler won't bother unref'ing it.
  # * otherwise, t is derived from a symbol in the current scope.  in this
  #   case we we have to use a conversion to defeat move inference.  e.g.,
  #     document.window = window
  #     # if we only access window by casts from here on, it's not
  #     # accounted for in sink inference, and will get sink'ed in by the
  #     # previous assignment.
  #     window.document = document
  #   note that moves are inferred even based on object/array access
  #   so we have to be broader here.
  if isLocal(t):
    quote do:
      `T`(`t`)
  else:
    quote do:
      cast[`T`](`t`)

# This is the WebIDL dictionary type.
# We only use it for type inference in generics.
type
  JSDict* {.pure, inheritable.} = object

# Example usage:
#
# type MyOptions = object of JSDict
#   x {.jsdefault: 1.}: int
#   y {.jsdefault.}: bool
#
# For the above JSDict, no exception will be thrown if `x` is missing; instead,
# it gets set to `1'.
template jsdefault*(x: untyped) {.pragma.}
template jsdefault*() {.pragma.}

# Container compatible with the internal representation of narrow strings in
# QuickJS (Latin-1).
type NarrowString* = distinct string

# Various containers for array buffer types.
# Converting these only requires copying the metadata; buffers are never copied.
type
  JSArrayBufferInit* = object
    p*: ptr UncheckedArray[uint8]
    len*: int
    dealloc*: JSFreeArrayBufferDataFunc

  JSArrayBufferViewInit* = object
    abuf*: JSArrayBufferInit
    offset*: int # offset into the buffer
    len*: int # number of members
    t*: JSTypedArrayEnum # type

proc base*(view: JSArrayBufferViewInit): ptr UncheckedArray[uint8] =
  if view.len <= 0:
    return nil
  return cast[ptr UncheckedArray[uint8]](addr view.abuf.p[view.offset])

# A key-value pair: in WebIDL terms, this is a record.
type JSKeyValuePair*[K, T] = object
  s*: seq[tuple[name: K; value: T]]

# * DOMString: may include surrogates (encoded as UTF-8).
# * DOMStringNull: same as DOMString, but JS_NULL is translated to the empty
#   string (instead of being rejected).
# * string: the spec calls this USVString.  Encodes surrogates as U+FFFD.
# * ByteString: like string, but rejects codepoints greater than U+00FF.
# * CSSOMString: the spec allows aliasing this to DOMString or USVString.
#   We use DOMString for the simple reason that our USVString isn't
#   zero-copy.
type
  DOMString* {.pure, inheritable.} = object
    p*: cstring
    ilen: int

  DOMStringNull* {.pure, final.} = object of DOMString

  ByteString* = object
    s*: string

  CSSOMString* = DOMString

const DOMStringConstFlag = 1 shl (sizeof(int) * 8 - 1)

proc `=destroy`*(s: var DOMString) =
  if (s.ilen and DOMStringConstFlag) == 0:
    JS_FreeCStringRT(globalRuntime, cstringConst(s.p))

proc `=copy`*(a: var DOMString; b: DOMString) {.error.} =
  discard

template len*(ds: DOMString): int =
  ds.ilen and not DOMStringConstFlag

proc initDOMString*(s: cstring; len: int): DOMString =
  DOMString(p: s, ilen: len)

proc initDOMStringLit*(s: cstring): DOMString =
  DOMString(p: s, ilen: s.len or DOMStringConstFlag)

template toOpenArray*(s: DOMString): openArray[char] =
  {.push overflowChecks: off.}
  let H = s.len - 1
  {.pop.}
  s.p.toOpenArray(0, H)

template toOpenArray*(s: DOMString; start: int): openArray[char] =
  {.push overflowChecks: off.}
  let H = s.len - 1
  {.pop.}
  s.p.toOpenArray(start, H)

proc `$`*(ds: DOMString): string =
  ds.toOpenArray().substr()

proc toDOMStringView*(s: string): DOMString =
  DOMString(p: cstring(s), ilen: s.len or DOMStringConstFlag)

proc `==`*(ds: DOMString; s: string): bool =
  ds.toOpenArray() == s

proc `==`*(s: string; ds: DOMString): bool =
  ds.toOpenArray() == s

proc toDOMStringNull*(ds: sink DOMString): DOMStringNull =
  let p = ds.p
  ds.p = nil
  DOMStringNull(p: p, ilen: ds.ilen)

proc `$`*(ds: DOMStringNull): string =
  ds.toOpenArray().substr()

proc `$`*(bs: ByteString): lent string =
  bs.s

type JSObject* = distinct pointer

proc `=destroy`*(p: var JSObject) =
  if cast[pointer](p) != nil:
    JS_FreeValueRT(globalRuntime, JS_MKPTR(JS_TAG_OBJECT, cast[pointer](p)))

proc `=sink`*(dest: var JSObject; src: JSObject) =
  `=destroy`(dest)
  cast[ptr pointer](addr dest)[] = cast[pointer](src)

proc `=copy`*(dest: var JSObject; src: JSObject) =
  `=destroy`(dest)
  if cast[pointer](src) == nil:
    cast[ptr pointer](addr dest)[] = nil
  else:
    let val = JS_MKPTR(JS_TAG_OBJECT, cast[pointer](src))
    let val2 = JS_DupValueRT(globalRuntime, val.vc)
    cast[ptr pointer](addr dest)[] = JS_VALUE_GET_PTR(val2.vc)

proc `=dup`*(src: JSObject): JSObject =
  if pointer(src) == nil:
    JSObject(nil)
  else:
    let val = JS_MKPTR(JS_TAG_OBJECT, cast[pointer](src))
    let val2 = JS_DupValueRT(globalRuntime, val.vc)
    JSObject(JS_VALUE_GET_PTR(val2.vc))

proc `==`*(a: JSObject; b: typeof(nil)): bool =
  pointer(a) == nil

template traceObj*(val: JSValue): JSObject =
  JSObject(JS_VALUE_GET_PTR(val.vc))

template dupTraceObj*(ctx: JSContext; val: JSValueConst): JSObject =
  traceObj(JS_DupValue(ctx, val))

proc value*(p: JSObject): JSValueConst =
  JS_MKPTR(JS_TAG_OBJECT, cast[pointer](p)).vc

proc toJSValue*(p: sink JSObject): JSValue =
  let val = JS_MKPTR(JS_TAG_OBJECT, cast[pointer](p))
  wasMoved(p)
  val

proc JS_MarkValue*(rt: JSRuntime; p: JSObject; markFunc: JS_MarkFunc) =
  if p != nil:
    JS_MarkValue(rt, p.value, markFunc)

proc JS_IsFunction*(ctx: JSContext; p: JSObject): bool =
  JS_IsFunction(ctx, p.value)

type
  JSCallback* = distinct JSObject

  JSObjectNil* = distinct JSObject # like JSObject, but nil is allowed

  JSObjectErr* = distinct JSObject # like JSObject, but nil -> err

  BufferSource* = distinct JSObject

  JSArrayBufferView* = distinct JSObject

template jsObjectBorrow(typ: untyped) =
  proc `==`*(a: typ; b: typeof(nil)): bool =
    pointer(a) == nil

  proc `==`*(a, b: typ): bool =
    pointer(a) == pointer(b)

  proc JS_MarkValue*(rt: JSRuntime; p: typ; markFunc: JS_MarkFunc) {.borrow.}

jsObjectBorrow(JSCallback)
jsObjectBorrow(BufferSource)
jsObjectBorrow(JSArrayBufferView)
jsObjectBorrow(JSObjectNil)

template value*(p: JSCallback): JSValueConst =
  JSObject(p).value

template value*(p: BufferSource): JSValueConst =
  JSObject(p).value

template value*(p: JSArrayBufferView): JSValueConst =
  JSObject(p).value

proc value*(p: JSObjectNil): JSValueConst =
  if p == nil:
    JS_NULL.vc
  else:
    JSObject(p).value

proc toJSValue*(p: sink JSCallback): JSValue {.borrow.}

template isErr*(obj: JSObjectErr): bool =
  JSObject(obj) == nil

template traceCallback*(val: JSValue): JSCallback =
  JSCallback(traceObj(val))

type
  JSValueTraced* = distinct JSValue

proc `=destroy`*(t: var JSValueTraced) =
  JS_FreeValueRT(globalRuntime, cast[ptr JSValue](addr t)[])

proc `=copy`*(dest: var JSValueTraced; src: JSValueTraced) =
  JS_FreeValueRT(globalRuntime, cast[ptr JSValue](addr dest)[])
  cast[ptr JSValue](addr dest)[] =
    JS_DupValueRT(globalRuntime, cast[ptr JSValueConst](unsafeAddr src)[])

proc `=sink`*(dest: var JSValueTraced; src: JSValueTraced) =
  JS_FreeValueRT(globalRuntime, cast[ptr JSValue](addr dest)[])
  cast[ptr JSValue](addr dest)[] = cast[ptr JSValue](unsafeAddr src)[]

proc `=dup`*(t: JSValueTraced): JSValueTraced =
  JSValueTraced(JS_DupValueRT(globalRuntime, JSValueConst(t)))

proc trace*(val: JSValue): JSValueTraced {.noinit.} =
  cast[ptr JSValue](addr result)[] = val

proc dupTrace*(ctx: JSContext; val: JSValueConst): JSValueTraced =
  trace(JS_DupValue(ctx, val))

template vc*(t: JSValueTraced): JSValueConst =
  dotGet(JSValueConst, t)

proc JS_IsUndefined*(t: JSValueTraced): bool =
  JS_IsUndefined(t.vc)

proc JS_IsNull*(t: JSValueTraced): bool =
  JS_IsNull(t.vc)

proc JS_IsFunction*(ctx: JSContext; t: JSValueTraced): bool =
  JS_IsFunction(ctx, t.vc)

proc JS_IsException*(t: JSValueTraced): bool =
  JS_IsException(t.vc)

proc JS_IsObject*(t: JSValueTraced): bool =
  JS_IsObject(t.vc)

proc JS_IsString*(t: JSValueTraced): bool =
  JS_IsString(t.vc)

proc JS_MarkValue*(rt: JSRuntime; t: JSValueTraced; markFunc: JS_MarkFunc) =
  JS_MarkValue(rt, t.vc, markFunc)

proc JS_DupValue*(ctx: JSContext; t: JSValueTraced): JSValue =
  JS_DupValue(ctx, t.vc)

proc toJSValue*(t: sink JSValueTraced): JSValue =
  let val = JSValue(t)
  wasMoved(t)
  return val

{.pop.} # raises
