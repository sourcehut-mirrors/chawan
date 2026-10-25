{.push raises: [].}

type
  ByteArray* = object
    len*: int
    p*: ptr UncheckedArray[char]
    opaque: pointer

proc `=destroy`*(this: var ByteArray) =
  if this.p != nil:
    dealloc(this.p)

proc `=copy`*(dst: var ByteArray; src: ByteArray) {.error.} =
  discard

proc `=sink`*(dst: var ByteArray; src: ByteArray) =
  `=destroy`(dst)
  dst.p = src.p
  dst.len = src.len

template toOpenArray*(this: ByteArray): openArray[char] =
  this.p.toOpenArray(0, this.len - 1)

proc initByteArray*(p: pointer; len: int): ByteArray =
  ByteArray(
    p: cast[ptr UncheckedArray[char]](p),
    len: len,
  )

{.pop.} # raises: []
