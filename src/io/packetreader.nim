{.push raises: [].}

import std/posix
import std/tables

import io/dynstream
import types/color

type PacketReader* = object
  buffer: seq[uint8]
  bufIdx: int
  fds: seq[cint]

proc sread*(r: var PacketReader; n: var SomeNumber)
proc sread*[T](r: var PacketReader; s: var set[T])
proc sread*[T: enum](r: var PacketReader; x: var T)
proc sread*(r: var PacketReader; s: var string)
proc sread*(r: var PacketReader; b: var bool)
proc sread*(r: var PacketReader; tup: var tuple)
proc sread*[I, T](r: var PacketReader; a: var array[I, T])
proc sread*[T](r: var PacketReader; s: var seq[T])
proc sread*[U, V](r: var PacketReader; t: var Table[U, V])
proc sread*(r: var PacketReader; obj: var object)
proc sread*(r: var PacketReader; obj: var ref object)
proc sread*(r: var PacketReader; c: var ARGBColor)
proc sread*(r: var PacketReader; c: var CellColor)

proc initReader*(stream: DynStream; r: var PacketReader; len, nfds: int): bool =
  assert len != 0 or nfds != 0
  r = PacketReader(
    buffer: newSeqUninit[uint8](len),
    fds: newSeqUninit[cint](nfds),
    bufIdx: 0
  )
  if not stream.readDataLoop(r.buffer):
    return false
  if nfds > 0:
    # bufwriter added ancillary data.
    var dummy {.noinit.}: array[1, uint8]
    var numFds = 0
    let stream = if stream of BufStream:
      BufStream(stream).source
    else:
      SocketStream(stream)
    let n = stream.recvMsg(dummy, r.fds, numFds)
    if n < dummy.len:
      return false
    if numFds < nfds:
      for i in 0 ..< numFds:
        discard close(r.fds[i])
      return false
  true

proc initPacketReader*(stream: DynStream; r: var PacketReader): bool =
  var len {.noinit.}: array[2, int]
  if not stream.readDataLoop(addr len[0], sizeof(len)):
    return false
  return stream.initReader(r, len[0], len[1])

proc assertEmpty(r: var PacketReader) =
  assert r.bufIdx == r.buffer.len and r.fds.len == 0

template withPacketReader*(stream: DynStream; r, body, fallback: untyped) =
  block:
    var r: PacketReader
    if stream.initPacketReader(r):
      body
      r.assertEmpty()
    else:
      fallback

template withPacketReaderFire*(stream: DynStream; r, body: untyped) =
  stream.withPacketReader r:
    body
  do:
    discard

proc readData*(r: var PacketReader; buffer: pointer; len: int) =
  assert r.bufIdx + len <= r.buffer.len
  copyMem(buffer, addr r.buffer[r.bufIdx], len)
  r.bufIdx += len

proc recvFd*(r: var PacketReader): cint =
  return r.fds.pop()

proc sread*(r: var PacketReader; n: var SomeNumber) =
  n = 0
  r.readData(addr n, sizeof(n))

proc sread*[T: enum](r: var PacketReader; x: var T) =
  var i {.noinit.}: int
  r.sread(i)
  x = cast[T](i)

proc sread*[T](r: var PacketReader; s: var set[T]) =
  var len {.noinit.}: int
  r.sread(len)
  s = {}
  for i in 0 ..< len:
    var x: T
    r.sread(x)
    s.incl(x)

proc sread*(r: var PacketReader; s: var string) =
  var len {.noinit.}: int
  r.sread(len)
  s = newString(len)
  if len > 0:
    r.readData(addr s[0], len)

proc sread*(r: var PacketReader; b: var bool) =
  var n: uint8
  r.sread(n)
  if n == 1u8:
    b = true
  else:
    assert n == 0u8
    b = false

proc sread*(r: var PacketReader; tup: var tuple) =
  for f in tup.fields:
    r.sread(f)

proc sread*[I; T](r: var PacketReader; a: var array[I, T]) =
  for x in a.mitems:
    r.sread(x)

proc sread*[T](r: var PacketReader; s: var seq[T]) =
  var len {.noinit.}: int
  r.sread(len)
  s = newSeq[T](len)
  for x in s.mitems:
    r.sread(x)

proc sread*[U; V](r: var PacketReader; t: var Table[U, V]) =
  var len {.noinit.}: int
  r.sread(len)
  t = initTable[U, V](len)
  for i in 0..<len:
    var k: U
    r.sread(k)
    var v: V
    r.sread(v)
    t[k] = v

proc sread*(r: var PacketReader; obj: var object) =
  obj = default(typeof(obj))
  for f in obj.fields:
    r.sread(f)

proc sread*(r: var PacketReader; obj: var ref object) =
  var n: bool
  r.sread(n)
  if n:
    obj = new(typeof(obj))
    r.sread(obj[])
  else:
    obj = nil

proc sread*(r: var PacketReader; c: var ARGBColor) =
  r.sread(uint32(c))

proc sread*(r: var PacketReader; c: var CellColor) =
  r.sread(uint32(c))

{.pop.} # raises: []
