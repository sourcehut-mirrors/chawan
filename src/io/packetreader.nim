{.push raises: [].}

import std/posix
import std/tables

import io/dynstream
import types/color
import types/opt

type
  PacketReader* = object
    buffer: seq[uint8]
    bufIdx: int
    fds: seq[cint]

  PartialPacketReader* = object
    idx: int
    numFds: int
    lens: array[2 * sizeof(int), uint8]
    r*: PacketReader

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

proc initReader*(stream: PosixStream; r: var PacketReader; len, nfds: int): bool =
  assert len != 0 or nfds != 0
  r = PacketReader(
    buffer: newSeqUninit[uint8](len),
    fds: newSeqUninit[cint](nfds),
    bufIdx: 0
  )
  if stream.readLoop(r.buffer).isErr:
    return false
  if nfds > 0:
    # packetwriter added ancillary data.
    #TODO just use recvmsg for both?
    var dummy {.noinit.}: array[1, uint8]
    var numFds = 0
    let n = stream.recvMsg(dummy, r.fds, numFds)
    if n < dummy.len:
      return false
    if numFds < nfds:
      for i in 0 ..< numFds:
        discard close(r.fds[i])
      return false
  true

proc initPacketReader*(stream: PosixStream; r: var PacketReader): bool =
  var len {.noinit.}: array[2, int]
  if stream.readLoop(addr len[0], sizeof(len)).isErr:
    return false
  return stream.initReader(r, len[0], len[1])

type PartialReaderCode* = enum
  prcEOF, prcDone, prcBuffer

proc initPartialReader*(stream: PosixStream; pr: var PartialPacketReader):
    PartialReaderCode =
  if pr.r.bufIdx == pr.r.buffer.len and pr.r.fds.len == 0:
    # reset
    pr.idx = 0
    pr.numFds = 0
  if pr.idx < pr.lens.len:
    let n = stream.read(addr pr.lens[pr.idx], pr.lens.len - pr.idx)
    if n < 0:
      let e = errno
      if e == EAGAIN or e == EWOULDBLOCK or e == EINTR:
        return prcBuffer
      return prcEOF
    pr.idx += n
    if pr.idx < pr.lens.len:
      return prcBuffer
    var lens {.noinit.}: array[2, int]
    copyMem(addr lens[0], addr pr.lens[0], sizeof(lens))
    pr.r = PacketReader(
      buffer: newSeqUninit[uint8](lens[0]),
      fds: newSeqUninit[cint](lens[1])
    )
  let dataIdx = pr.idx - pr.lens.len
  if dataIdx < pr.r.buffer.len:
    let n = stream.read(pr.r.buffer.toOpenArray(dataIdx, pr.r.buffer.high))
    if n < 0:
      let e = errno
      if e == EAGAIN or e == EWOULDBLOCK or e == EINTR:
        return prcBuffer
      return prcEOF
    pr.idx += n
    if pr.idx - pr.lens.len < pr.r.buffer.len:
      return prcBuffer
  if pr.numFds < pr.r.fds.len:
    var dummy {.noinit.}: array[1, uint8]
    var numFds = 0
    let n = stream.recvMsg(dummy,
      pr.r.fds.toOpenArray(pr.numFds, pr.r.fds.high), numFds)
    if n < 0:
      let e = errno
      if e == EAGAIN or e == EWOULDBLOCK or e == EINTR:
        return prcBuffer
    if n <= 0:
      return prcEOF
    pr.numFds += numFds
    if pr.numFds < pr.r.fds.len:
      return prcBuffer
  return prcDone

proc assertEmpty(r: var PacketReader) =
  assert r.bufIdx == r.buffer.len and r.fds.len == 0

template withPacketReader*(stream: PosixStream; r, body, fallback: untyped) =
  block:
    var r: PacketReader
    if stream.initPacketReader(r):
      body
      r.assertEmpty()
    else:
      fallback

template withPacketReaderFire*(stream: PosixStream; r, body: untyped) =
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

proc closeFds*(r: var PacketReader) =
  for fd in r.fds:
    discard close(fd)

proc sread*(r: var PacketReader; n: var SomeNumber) =
  n = 0
  r.readData(addr n, sizeof(n))

proc sread*[T: enum](r: var PacketReader; x: var T) =
  var i {.noinit.}: int
  r.sread(i)
  x = cast[T](i)

proc sread*[T](r: var PacketReader; s: var set[T]) =
  r.readData(addr s, sizeof(s))

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
