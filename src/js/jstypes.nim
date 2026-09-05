{.push raises: [].}

import jsopaque
import quickjs

when NimMajor < 2:
  import utils/twtstr

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

proc toDOMStringNull*(ds: sink DOMString): DOMStringNull =
  let p = ds.p
  ds.p = nil
  DOMStringNull(p: p, ilen: ds.ilen)

proc `$`*(bs: ByteString): lent string =
  bs.s

type JSObject* = distinct pointer

proc `=destroy`(p: var JSObject) =
  if cast[pointer](p) != nil:
    JS_FreeValueRT(globalRuntime, JS_MKPTR(JS_TAG_OBJECT, cast[pointer](p)))

proc `=wasMoved`(p: var JSObject) =
  cast[ptr pointer](addr p)[] = nil

proc `=sink`(dest: var JSObject; src: JSObject) =
  `=destroy`(dest)
  cast[ptr pointer](addr dest)[] = cast[pointer](src)

proc `=copy`(dest: var JSObject; src: JSObject) =
  `=destroy`(dest)
  if cast[pointer](src) == nil:
    cast[ptr pointer](addr dest)[] = nil
  else:
    let val = JS_MKPTR(JS_TAG_OBJECT, cast[pointer](src))
    let val2 = JS_DupValueRT(globalRuntime, val)
    cast[ptr pointer](addr dest)[] = JS_VALUE_GET_PTR(val2)

proc `=dup`(src: JSObject): JSObject {.noinit.} =
  if pointer(src) == nil:
    cast[ptr pointer](addr result)[] = nil
  else:
    let val = JS_MKPTR(JS_TAG_OBJECT, cast[pointer](src))
    let val2 = JS_DupValueRT(globalRuntime, val)
    cast[ptr pointer](addr result)[] = JS_VALUE_GET_PTR(val2)

proc `==`*(a: JSObject; b: typeof(nil)): bool =
  pointer(a) == nil

proc traceObj*(val: JSValue): JSObject =
  JSObject(JS_VALUE_GET_PTR(val))

proc dupTraceObj*(ctx: JSContext; val: JSValueConst): JSObject =
  let val2 = JS_DupValue(ctx, val)
  val2.traceObj()

proc value*(p: JSObject): JSValueConst =
  if pointer(p) != nil:
    JSValueConst(JS_MKPTR(JS_TAG_OBJECT, cast[pointer](p)))
  else:
    JS_NULL

proc moveJSValue*(p: var JSObject): JSValue =
  let val = JS_MKPTR(JS_TAG_OBJECT, cast[pointer](p))
  cast[ptr pointer](addr p)[] = nil
  val

proc JS_MarkValue*(rt: JSRuntime; p: JSObject; markFunc: JS_MarkFunc) =
  JS_MarkValue(rt, p.value, markFunc)

type
  JSCallback* = distinct JSObject

  BufferSource* = distinct JSObject

  JSArrayBufferView* = distinct JSObject

template jsObjectBorrow(typ: untyped) =
  proc `==`*(a: typ; b: typeof(nil)): bool =
    pointer(a) == nil

  proc value*(p: typ): JSValueConst {.borrow.}
  proc moveJSValue*(p: var typ): JSValue {.borrow.}
  proc JS_MarkValue*(rt: JSRuntime; p: typ; markFunc: JS_MarkFunc) {.borrow.}

jsObjectBorrow(JSCallback)
jsObjectBorrow(BufferSource)
jsObjectBorrow(JSArrayBufferView)

type
  JSValueTraced* = object
    v*: JSValue

proc `=destroy`(t: var JSValueTraced) =
  JS_FreeValueRT(globalRuntime, t.v)

proc `=wasMoved`(t: var JSValueTraced) =
  t.v = JS_UNINITIALIZED

proc `=copy`(dest: var JSValueTraced; src: JSValueTraced) =
  JS_FreeValueRT(globalRuntime, dest.v)
  dest.v = JS_DupValueRT(globalRuntime, src.v)

proc `=sink`(dest: var JSValueTraced; src: JSValueTraced) =
  JS_FreeValueRT(globalRuntime, dest.v)
  dest.v = src.v

proc `=dup`(t: JSValueTraced): JSValueTraced =
  JSValueTraced(v: JS_DupValueRT(globalRuntime, t.v))

proc trace*(val: JSValue): JSValueTraced =
  JSValueTraced(v: val)

converter toJSValueConst*(t: JSValueTraced): JSValueConst =
  JSValueConst(t.v)

{.pop.} # raises
