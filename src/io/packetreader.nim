# TODO:
# * impose a sensible limit on packet size
# * allocation errors?  (I think they have to be handled differently...)

{.push raises: [].}

import std/posix
import std/typetraits

import config/conftypes
import css/color
import io/dynstream
import utils/opt

type
  PacketReader* = object
    buffer: seq[uint8]
    bufIdx: int
    fds: seq[cint]
    error*: cstring

  PartialPacketReader* = object
    idx: int
    numFds: int
    lens: array[2 * sizeof(int), uint8]
    r*: PacketReader

type PacketCode* = enum
  pcErr, pcOk

proc sread*(r: var PacketReader; n: var SomeNumber): PacketCode
proc sread*[T](r: var PacketReader; s: var set[T]): PacketCode
proc sread*[T: enum](r: var PacketReader; x: var T): PacketCode
proc sread*(r: var PacketReader; s: var string): PacketCode
proc sread*(r: var PacketReader; b: var bool): PacketCode
proc sread*(r: var PacketReader; tup: var tuple): PacketCode
proc sread*[T](r: var PacketReader; s: var seq[T]): PacketCode
proc sread*(r: var PacketReader; obj: var object): PacketCode
proc sread*(r: var PacketReader; c: var ARGBColor): PacketCode
proc sread*(r: var PacketReader; c: var CellColor): PacketCode
proc sread*(r: var PacketReader; bmp: var NetworkBitmap): PacketCode

proc initReader*(stream: PosixStream; r: var PacketReader; len, nfds: int):
    bool =
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
    if n <= 0:
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
    if n <= 0:
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
  # it is allowed (recommended) to abort reading if the packet is malformed
  assert r.error != nil or r.bufIdx == r.buffer.len and r.fds.len == 0

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

template ok*(t: typedesc[PacketCode]): PacketCode =
  pcOk

template err*(t: typedesc[PacketCode]): PacketCode =
  pcErr

template `?`*(res: PacketCode) =
  if res == pcErr:
    return pcErr

template err*(r: var PacketReader; s: cstring): untyped =
  r.error = s
  err()

template isOk*(res: PacketCode): bool =
  res == pcOk

template isErr*(res: PacketCode): bool =
  res == pcErr

proc readData*(r: var PacketReader; buffer: pointer; len: int): PacketCode =
  if len > r.buffer.len:
    return r.err("out of packet bounds")
  if len > 0:
    copyMem(buffer, addr r.buffer[r.bufIdx], len)
    r.bufIdx += len
  ok()

proc recvFd*(r: var PacketReader): Opt[cint] =
  if r.fds.len <= 0:
    return r.err("out of file descriptors")
  ok(r.fds.pop())

proc closeFds*(r: var PacketReader) =
  for fd in r.fds:
    discard close(fd)

proc sread*(r: var PacketReader; n: var SomeNumber): PacketCode =
  r.readData(addr n, sizeof(n))

proc sread*[T: enum](r: var PacketReader; x: var T): PacketCode =
  #TODO could just send/read the enum size
  var i {.noinit.}: int
  ?r.sread(i)
  x = cast[T](i)
  ok()

proc sread*[T](r: var PacketReader; s: var set[T]): PacketCode =
  r.readData(addr s, sizeof(s))

proc readLen*(r: var PacketReader): Opt[int] =
  #TODO 32-bit ints should be enough...
  var len {.noinit.}: int
  if r.sread(len).isErr:
    return err()
  if len < 0:
    return r.err("negative length")
  ok(len)

proc sread*(r: var PacketReader; s: var string): PacketCode =
  let len = ?r.readLen()
  var s2 = newString(len)
  if s2.len > 0:
    ?r.readData(addr s2[0], len)
  s = move(s2)
  ok()

proc sread*(r: var PacketReader; b: var bool): PacketCode =
  #TODO could compress into bits (but maybe not worth it...)
  var n: uint8
  ?r.sread(n)
  if n > 1:
    return r.err("invalid bool value")
  b = n == 1
  ok()

proc sread*(r: var PacketReader; tup: var tuple): PacketCode =
  for f in tup.fields:
    ?r.sread(f)
  ok()

proc sread*[T](r: var PacketReader; s: var seq[T]): PacketCode =
  let len = ?r.readLen()
  var s2 = newSeq[T](len)
  when T is char or T is SomeNumber:
    if len > 0:
      ?r.readData(addr s2[0], s2.len * sizeof(T))
  else:
    for x in s2.mitems:
      ?r.sread(x)
  s = move(s2)
  ok()

proc sread*(r: var PacketReader; obj: var object): PacketCode =
  for f in obj.fields:
    ?r.sread(f)
  ok()

proc sread*(r: var PacketReader; c: var ARGBColor): PacketCode =
  r.sread(uint32(c))

proc sread*(r: var PacketReader; c: var CellColor): PacketCode =
  r.sread(uint32(c))

proc sread*(r: var PacketReader; bmp: var NetworkBitmap): PacketCode =
  var n: bool
  ?r.sread(n)
  if n:
    bmp = NetworkBitmap()
    ?r.sread(bmp[])
  else:
    bmp = nil
  ok()

proc assert*(r: var PacketReader; res: PacketCode) =
  doAssert res == pcOk, $r.error

{.pop.} # raises: []
