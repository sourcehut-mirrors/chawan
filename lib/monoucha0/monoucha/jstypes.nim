{.push raises: [].}

import utils/twtstr

import jsopaque
import quickjs

# This is the WebIDL dictionary type.
# We only use it for type inference in generics.
type
  # JSDictToFreeAux is a hack to ensure JSValues are freed only
  # when the JSDict goes out of scope. Ugly and sub-optimal, but it does
  # the job.
  JSDictToFreeAux* = ref JSDictToFreeAuxObj
  JSDictToFreeAuxObj = object
    vals*: seq[JSValue]

  JSDict* {.pure, inheritable.} = object
    toFree*: JSDictToFreeAux

proc `=destroy`*(x: var JSDictToFreeAuxObj) =
  for val in x.vals:
    JS_FreeValueRT(globalRuntime, val)

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
  JSArrayBuffer* = object
    p*: ptr UncheckedArray[uint8]
    len*: int
    dealloc*: JSFreeArrayBufferDataFunc

  JSArrayBufferView* = object
    abuf*: JSArrayBuffer
    offset*: int # offset into the buffer
    len*: int # number of members
    bytesPerItem*: uint8 # ignored in toJS
    t*: JSTypedArrayEnum # type

template toOpenArray*(view: JSArrayBufferView): openArray[uint8] =
  view.abuf.p.toOpenArray(view.offset, view.offset + view.len - 1)

proc base*(view: JSArrayBufferView): ptr UncheckedArray[uint8] =
  if view.len <= 0:
    return nil
  return cast[ptr UncheckedArray[uint8]](addr view.abuf.p[view.offset])

# A key-value pair: in WebIDL terms, this is a record.
type JSKeyValuePair*[T] = object
  s*: seq[tuple[name: string; value: T]]

type
  DOMString* = object
    p*: cstring
    ilen: int

  DOMStringNull* = distinct DOMString

const DOMStringConstFlag = 1 shl (sizeof(int) * 8 - 1)

proc `=destroy`*(s: var DOMString) =
  if (s.ilen and DOMStringConstFlag) == 0:
    JS_FreeCStringRT(globalRuntime, s.p)

proc `=copy`*(a: var DOMString; b: DOMString) {.error.} =
  discard

template len*(ds: DOMString): int =
  ds.ilen and not DOMStringConstFlag

proc initDOMString*(s: cstring; len: int): DOMString =
  DOMString(p: s, ilen: s.len)

proc initDOMStringLit*(s: cstring): DOMString =
  DOMString(p: s, ilen: s.len or DOMStringConstFlag)

template toOpenArray*(s: DOMString): openArray[char] =
  {.push overflowChecks: off.}
  let H = s.len - 1
  {.pop.}
  s.p.toOpenArray(0, H)

proc `$`*(ds: DOMString): string =
  ds.toOpenArray().substr()

template toOpenArray*(s: DOMStringNull): openArray[char] =
  DOMString(s).toOpenArray()

{.pop.} # raises
