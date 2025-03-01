import std/options
import std/tables

import io/dynstream
import types/color
import types/opt

type PacketReader* = object
  buffer: seq[uint8]
  bufIdx: int
  fds: seq[cint] #TODO assert on unused ones

proc sread*(r: var PacketReader; n: out SomeNumber)
proc sread*[T](r: var PacketReader; s: out set[T])
proc sread*[T: enum](r: var PacketReader; x: out T)
proc sread*(r: var PacketReader; s: out string)
proc sread*(r: var PacketReader; b: out bool)
proc sread*(r: var PacketReader; tup: var tuple)
proc sread*[I, T](r: var PacketReader; a: out array[I, T])
proc sread*[T](r: var PacketReader; s: out seq[T])
proc sread*[U, V](r: var PacketReader; t: out Table[U, V])
proc sread*(r: var PacketReader; obj: var object)
proc sread*(r: var PacketReader; obj: var ref object)
proc sread*[T](r: var PacketReader; o: out Option[T])
proc sread*[T, E](r: var PacketReader; o: out Result[T, E])
proc sread*(r: var PacketReader; c: var ARGBColor)
proc sread*(r: var PacketReader; c: var CellColor)

proc initReader*(stream: DynStream; len, nfds: int): PacketReader =
  assert len != 0 or nfds != 0
  var r = PacketReader(
    buffer: newSeqUninitialized[uint8](len),
    fds: newSeqUninitialized[cint](nfds),
    bufIdx: 0
  )
  if not stream.readDataLoop(r.buffer):
    raise newException(EOFError, "end of file")
  if nfds > 0:
    # bufwriter added ancillary data.
    var dummy {.noinit.}: array[1, uint8]
    var numFds = 0
    let n = SocketStream(stream).recvMsg(dummy, r.fds, numFds)
    if n < dummy.len or numFds < nfds:
      raise newException(EOFError, "end of file")
  return r

proc initPacketReader*(stream: DynStream): PacketReader =
  var len {.noinit.}: array[2, int]
  if not stream.readDataLoop(addr len[0], sizeof(len)):
    raise newException(EOFError, "end of file")
  return stream.initReader(len[0], len[1])

template withPacketReader*(stream: DynStream; r, body: untyped) =
  block:
    var r = stream.initPacketReader()
    body
    assert r.fds.len == 0

proc empty*(r: var PacketReader): bool =
  return r.bufIdx == r.buffer.len

proc readData*(r: var PacketReader; buffer: pointer; len: int) =
  assert r.bufIdx + len <= r.buffer.len
  copyMem(buffer, addr r.buffer[r.bufIdx], len)
  r.bufIdx += len

proc recvFd*(r: var PacketReader): cint =
  return r.fds.pop()

proc sread*(r: var PacketReader; n: out SomeNumber) =
  n = 0
  r.readData(addr n, sizeof(n))

proc sread*[T: enum](r: var PacketReader; x: out T) =
  var i {.noinit.}: int
  r.sread(i)
  x = cast[T](i)

proc sread*[T](r: var PacketReader; s: out set[T]) =
  var len {.noinit.}: int
  r.sread(len)
  s = {}
  for i in 0 ..< len:
    var x: T
    r.sread(x)
    s.incl(x)

proc sread*(r: var PacketReader; s: out string) =
  var len {.noinit.}: int
  r.sread(len)
  s = newString(len)
  if len > 0:
    r.readData(addr s[0], len)

proc sread*(r: var PacketReader; b: out bool) =
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

proc sread*[I; T](r: var PacketReader; a: out array[I, T]) =
  for x in a.mitems:
    r.sread(x)

proc sread*[T](r: var PacketReader; s: out seq[T]) =
  var len {.noinit.}: int
  r.sread(len)
  s = newSeq[T](len)
  for x in s.mitems:
    r.sread(x)

proc sread*[U; V](r: var PacketReader; t: out Table[U, V]) =
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

proc sread*[T](r: var PacketReader; o: out Option[T]) =
  var x: bool
  r.sread(x)
  if x:
    var m: T
    r.sread(m)
    o = some(m)
  else:
    o = none(T)

proc sread*[T, E](r: var PacketReader; o: out Result[T, E]) =
  var x: bool
  r.sread(x)
  if x:
    when T isnot void:
      var m: T
      r.sread(m)
      o.ok(m)
    else:
      o.ok()
  else:
    when E isnot void:
      var e: E
      r.sread(e)
      o.err(e)
    else:
      o.err()

proc sread*(r: var PacketReader; c: var ARGBColor) =
  r.sread(uint32(c))

proc sread*(r: var PacketReader; c: var CellColor) =
  r.sread(uint32(c))
