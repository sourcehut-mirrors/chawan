{.push raises: [].}

import quickjs

# This is the WebIDL dictionary type.
# We only use it for type inference in generics.
#TODO required members
type
  # JSDictToFreeAux is a hack to ensure JSValues are freed only
  # when the JSDict goes out of scope. Ugly and sub-optimal, but it does
  # the job.
  JSDictToFreeAux* = ref JSDictToFreeAuxObj
  JSDictToFreeAuxObj = object
    ctx*: JSContext
    vals*: seq[JSValue]

  JSDict* = object of RootObj
    toFree*: JSDictToFreeAux

proc `=destroy`*(x: var JSDictToFreeAuxObj) =
  for val in x.vals:
    JS_FreeValue(x.ctx, val)

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
    len*: csize_t
    dealloc*: JSFreeArrayBufferDataFunc

  JSArrayBufferView* = object
    abuf*: JSArrayBuffer
    offset*: csize_t # offset into the buffer
    nmemb*: csize_t # number of members
    nsize*: csize_t # member size
    t*: cint # type

  JSTypedArray* = object
    t*: JSTypedArrayEnum
    abuf*: JSArrayBuffer
    #TODO offset/nmemb

proc high*(abuf: JSArrayBuffer): int =
  return int(abuf.len) - 1

# A key-value pair: in WebIDL terms, this is a record.
type JSKeyValuePair*[K, T] = object
  s*: seq[tuple[name: string; value: T]]

{.pop.} # raises
