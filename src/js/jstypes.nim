{.push raises: [].}

import std/macros

import encoding/decoder
import io/packetreader
import io/packetwriter
import js/constcharp
import js/quickjs
import utils/cowstr
import utils/macroutil
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
# * DOMStringEmpty: same as DOMString, but JS_NULL is translated to the
#   empty string (instead of being rejected).
# * DOMStringNil: same as DOMString, but JS_NULL is translated to nil.
# * Str: USVString in the spec, encodes surrogates as U+FFFD.
# * string: treated as USVString.
# * ByteString: rejects codepoints greater than U+00FF.
# * CSSOMString: the spec allows aliasing this to DOMString or USVString.
#   We use USVString to reduce malformed UTF-8.
# * CStringNZ: non-zero JS string, may contain surrogates.
#   Useful for paths.
type
  DOMString* = distinct Str

  DOMStringEmpty* = distinct DOMString

  DOMStringNil* = distinct StrNil

  ByteString* = distinct Str

  CStringNZ* = object
    p*: cstring

proc `=destroy`*(s: var CStringNZ) =
  if s.p != nil:
    JS_FreeCStringRT(globalRuntime, cstringConst(s.p))

proc `=sink`*(dst: var CStringNZ; src: CStringNZ) =
  `=destroy`(dst)
  dst.p = src.p

# set as .error for now because I haven't found a need for these
proc `=copy`*(dst: var CStringNZ; src: CStringNZ) {.error.} =
  `=destroy`(dst)
  if src.p != nil:
    dst.p = cstring(JS_DupCStringRT(globalRuntime, cstringConst(s.p)))
  else:
    dst.p = nil

proc `=dup`*(src: CStringNZ): CStringNZ {.error.} =
  let p = if src.p != nil:
    cstring(JS_DupCStringRT(globalRuntime, cstringConst(s.p)))
  else:
    nil
  CStringNZ(p: p)

proc toStr*(src: sink CStringNZ): Str =
  let p = src.p
  wasMoved(src)
  initQJSStr(p, p.len)

template len*(ds: DOMString): int =
  Str(ds).len

template toStr*(ds: DOMString): Str =
  Str(ds)

template toOpenArray*(s: DOMString): openArray[char] =
  Str(s).toOpenArray()

proc `$`*(ds: DOMString): string {.borrow.}
proc `$`*(ds: DOMStringEmpty): string {.borrow.}
proc `==`*(ds: DOMString; s: openArray[char]): bool {.borrow.}
proc `==`*(a, b: DOMString): bool {.borrow.}

template toDOMStringEmpty*(ds: DOMString): DOMStringEmpty =
  DOMStringEmpty(ds)

proc `$`*(s: CStringNZ): string =
  $s.p

# ByteString
proc toStr*(s: ByteString): Str =
  Str(s).toValidUTF8()

template toOpenArray*(s: ByteString): openArray[char] =
  Str(s).toOpenArray()

template len*(s: ByteString): int =
  Str(s).len

proc `[]`*(s: ByteString; n: int): char {.borrow.}
proc contains*(s: ByteString; c: char): bool {.borrow.}
proc contains*(s: ByteString; cs: set[char]): bool {.borrow.}
proc startsWithIgnoreCase*(a: ByteString; b: openArray[char]): bool {.borrow.}
proc equalsIgnoreCase*(a: ByteString; b: openArray[char]): bool {.borrow.}
proc add*(dst: var ByteString; src: openArray[char]) {.borrow.}
proc `==`*(a, b: ByteString): bool {.borrow.}
proc `==`*(a: ByteString; b: openArray[char]): bool {.borrow.}
proc equalsIgnoreCase*(a, b: ByteString): bool {.borrow.}
proc until*(s: ByteString; cc: set[char]; starti = 0): ByteString {.borrow.}

proc sread*(r: var PacketReader; s: var ByteString): PacketCode =
  r.sread(Str(s))

proc swrite*(w: var PacketWriter; s: ByteString) =
  w.swrite(Str(s))

proc `[]`*(s: ByteString; n: BackwardsIndex): char {.inline.} =
  Str(s)[n]

proc strip*(s: ByteString; leading = true; trailing = true;
    chars = AsciiWhitespace): ByteString =
  ByteString(Str(s).strip(leading, trailing, chars))

proc cmpIgnoreCase*(a, b: ByteString): int =
  Str(a).cmpIgnoreCase(Str(b))

proc add*(buf: var Growbuf; s: ByteString) =
  buf &= Str(s)

proc toByteString*(buf: sink Growbuf): ByteString =
  ByteString(buf.toStr())

template byteStr*(s: cstring): ByteString =
  ByteString(str(s))

template asByteString*(s: Str): ByteString =
  ByteString(s)

template add*(dst: var ByteString; src: ByteString) =
  dst &= src.toOpenArray()

template toLowerAscii*(s: ByteString): ByteString =
  ByteString(Str(s).toLowerAscii())

iterator split*(s: ByteString; sep: char): ByteString =
  for it in Str(s).split(sep):
    yield ByteString(it)

proc initDimsHeader*(w, h: int): ByteString =
  initStrM(w, 'x', h).asByteString

# JSObject
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

proc traceObj*(val: JSValue): JSObject =
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

# Either JS bool or undefined.
type OptionalBool* = enum
  obNone, obFalse, obTrue

proc toOptionalBool*(b: bool): OptionalBool =
  if b: obTrue else: obFalse

proc get*(ob: OptionalBool; b: bool): bool =
  case ob
  of obNone: b
  of obFalse: false
  of obTrue: true

{.pop.} # raises
