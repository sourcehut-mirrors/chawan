# Write data to streams in packets.
# Each packet is prefixed with two pointer-sized integers;
# the first one indicates the buffer's length, while the second one the
# length of its ancillary data (i.e. the number of file descriptors
# passed).

{.push raises: [].}

import std/algorithm
import std/tables

import io/dynstream
import types/color

type PacketWriter* = object
  buffer*: seq[uint8]
  bufLen*: int
  # file descriptors to send in the packet
  fds: seq[cint]

proc swrite*(w: var PacketWriter; n: SomeNumber)
proc swrite*[T](w: var PacketWriter; s: set[T])
proc swrite*[T: enum](w: var PacketWriter; x: T)
proc swrite*(w: var PacketWriter; s: string)
proc swrite*(w: var PacketWriter; b: bool)
proc swrite*(w: var PacketWriter; tup: tuple)
proc swrite*[I, T](w: var PacketWriter; a: array[I, T])
proc swrite*[T](w: var PacketWriter; s: openArray[T])
proc swrite*[U, V](w: var PacketWriter; t: Table[U, V])
proc swrite*(w: var PacketWriter; obj: object)
proc swrite*(w: var PacketWriter; obj: ref object)
proc swrite*(w: var PacketWriter; c: ARGBColor)
proc swrite*(w: var PacketWriter; c: CellColor)

proc sendFd*(w: var PacketWriter; fd: cint) =
  w.fds.add(fd)

const InitLen = sizeof(int) * 2
const SizeInit = max(64, InitLen)
proc initPacketWriter*(): PacketWriter =
  return PacketWriter(
    buffer: newSeqUninit[uint8](SizeInit),
    bufLen: InitLen
  )

proc writeSize*(w: var PacketWriter) =
  # subtract the length field's size
  let len = [w.bufLen - InitLen, w.fds.len]
  copyMem(addr w.buffer[0], unsafeAddr len[0], sizeof(len))

# Returns false on EOF, true if we flushed successfully.
proc flush*(w: var PacketWriter; stream: DynStream): bool =
  w.writeSize()
  if not stream.writeDataLoop(w.buffer.toOpenArray(0, w.bufLen - 1)):
    return false
  if w.fds.len > 0:
    w.fds.reverse()
    let n = SocketStream(stream).sendMsg([0u8], w.fds)
    if n < 1:
      return false
  w.bufLen = 0
  w.fds.setLen(0)
  true

template withPacketWriter*(stream: DynStream; w, body, fallback: untyped) =
  var w = initPacketWriter()
  body
  if not w.flush(stream):
    fallback

template withPacketWriterFire*(stream: DynStream; w, body: untyped) =
  var w = initPacketWriter()
  body
  discard w.flush(stream)

proc writeData*(w: var PacketWriter; buffer: pointer; len: int) =
  let targetLen = w.bufLen + len
  let missing = targetLen - w.buffer.len
  if missing > 0:
    let target = max(w.buffer.len + missing, w.buffer.len * 2)
    w.buffer.setLen(target)
  copyMem(addr w.buffer[w.bufLen], buffer, len)
  w.bufLen = targetLen

proc swrite*(w: var PacketWriter; n: SomeNumber) =
  w.writeData(unsafeAddr n, sizeof(n))

proc swrite*[T: enum](w: var PacketWriter; x: T) =
  static:
    doAssert sizeof(int) >= sizeof(T)
  w.swrite(int(x))

proc swrite*[T](w: var PacketWriter; s: set[T]) =
  w.swrite(s.card)
  for e in s:
    w.swrite(e)

proc swrite*(w: var PacketWriter; s: string) =
  w.swrite(s.len)
  if s.len > 0:
    w.writeData(unsafeAddr s[0], s.len)

proc swrite*(w: var PacketWriter; b: bool) =
  if b:
    w.swrite(1u8)
  else:
    w.swrite(0u8)

proc swrite*(w: var PacketWriter; tup: tuple) =
  for f in tup.fields:
    w.swrite(f)

proc swrite*[I, T](w: var PacketWriter; a: array[I, T]) =
  for x in a:
    w.swrite(x)

proc swrite*[T](w: var PacketWriter; s: openArray[T]) =
  w.swrite(s.len)
  for x in s:
    w.swrite(x)

proc swrite*[U, V](w: var PacketWriter; t: Table[U, V]) =
  w.swrite(t.len)
  for k, v in t:
    w.swrite(k)
    w.swrite(v)

proc swrite*(w: var PacketWriter; obj: object) =
  for f in obj.fields:
    w.swrite(f)

proc swrite*(w: var PacketWriter; obj: ref object) =
  w.swrite(obj != nil)
  if obj != nil:
    w.swrite(obj[])

proc swrite*(w: var PacketWriter; c: ARGBColor) =
  w.swrite(uint32(c))

proc swrite*(w: var PacketWriter; c: CellColor) =
  w.swrite(uint32(c))

{.pop.} # raises: []
