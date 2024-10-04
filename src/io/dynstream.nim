import std/nativesockets
import std/net
import std/os
import std/posix

import io/serversocket

type
  DynStream* = ref object of RootObj
    isend*: bool
    blocking*: bool #TODO move to posixstream
    closed: bool

# Semantics of this function are those of POSIX read(3): that is, it may return
# a result that is lower than `len`, and that does not mean the stream is
# finished.
# isend must be set by implementations when the end of the stream is reached.
# An exception should be raised if recvData is called with the 'isend' flag set
# to true.
method recvData*(s: DynStream; buffer: pointer; len: int): int {.base.} =
  assert false

# See above, but with write(2)
method sendData*(s: DynStream; buffer: pointer; len: int): int {.base.} =
  assert false

method seek*(s: DynStream; off: int) {.base.} =
  assert false

method sclose*(s: DynStream) {.base.} =
  assert false

method sflush*(s: DynStream) {.base.} =
  discard

proc recvData*(s: DynStream; buffer: var openArray[uint8]): int {.inline.} =
  return s.recvData(addr buffer[0], buffer.len)

proc recvData*(s: DynStream; buffer: var openArray[char]): int {.inline.} =
  return s.recvData(addr buffer[0], buffer.len)

proc sendData*(s: DynStream; buffer: openArray[char]): int {.inline.} =
  return s.sendData(unsafeAddr buffer[0], buffer.len)

proc sendData*(s: DynStream; buffer: openArray[uint8]): int {.inline.} =
  return s.sendData(unsafeAddr buffer[0], buffer.len)

proc sendDataLoop*(s: DynStream; buffer: pointer; len: int) =
  var n = 0
  while true:
    n += s.sendData(addr cast[ptr UncheckedArray[uint8]](buffer)[n], len - n)
    if n == len:
      break

proc sendDataLoop*(s: DynStream; buffer: openArray[uint8]) {.inline.} =
  if buffer.len > 0:
    s.sendDataLoop(unsafeAddr buffer[0], buffer.len)

proc sendDataLoop*(s: DynStream; buffer: openArray[char]) {.inline.} =
  if buffer.len > 0:
    s.sendDataLoop(unsafeAddr buffer[0], buffer.len)

proc write*(s: DynStream; buffer: openArray[char]) {.inline.} =
  s.sendDataLoop(buffer)

proc write*(s: DynStream; c: char) {.inline.} =
  s.sendDataLoop(unsafeAddr c, 1)

proc sreadChar*(s: DynStream): char =
  let n = s.recvData(addr result, 1)
  assert n == 1

proc recvDataLoop*(s: DynStream; buffer: pointer; len: int) =
  var n = 0
  while true:
    n += s.recvData(addr cast[ptr UncheckedArray[uint8]](buffer)[n], len - n)
    if n == len:
      break

proc recvDataLoop*(s: DynStream; buffer: var openArray[uint8]) {.inline.} =
  s.recvDataLoop(addr buffer[0], buffer.len)

proc recvDataLoop*(s: DynStream; buffer: var openArray[char]) {.inline.} =
  s.recvDataLoop(addr buffer[0], buffer.len)

proc recvAll*(s: DynStream): string =
  var buffer = newString(4096)
  var idx = 0
  while true:
    let n = s.recvData(addr buffer[idx], buffer.len - idx)
    if n == 0:
      break
    idx += n
    if idx == buffer.len:
      buffer.setLen(buffer.len + 4096)
  buffer.setLen(idx)
  return buffer

type
  PosixStream* = ref object of DynStream
    fd*: cint

  ErrorAgain* = object of IOError
  ErrorBadFD* = object of IOError
  ErrorFault* = object of IOError
  ErrorInterrupted* = object of IOError
  ErrorInvalid* = object of IOError
  ErrorConnectionReset* = object of IOError
  ErrorBrokenPipe* = object of IOError

proc raisePosixIOError() =
  # In the nim stdlib, these are only constants on linux amd64, so we
  # can't use a switch.
  if errno == EAGAIN or errno == EWOULDBLOCK:
    raise newException(ErrorAgain, "eagain")
  elif errno == EBADF:
    raise newException(ErrorBadFD, "bad fd")
  elif errno == EFAULT:
    raise newException(ErrorFault, "fault")
  elif errno == EINVAL:
    raise newException(ErrorInvalid, "invalid")
  elif errno == ECONNRESET:
    raise newException(ErrorConnectionReset, "connection reset by peer")
  elif errno == EPIPE:
    raise newException(ErrorBrokenPipe, "broken pipe")
  else:
    raise newException(IOError, $strerror(errno))

method recvData*(s: PosixStream; buffer: pointer; len: int): int =
  let n = read(s.fd, buffer, len)
  if n < 0:
    raisePosixIOError()
  if n == 0:
    if unlikely(s.isend):
      raise newException(EOFError, "eof")
    s.isend = true
  return n

proc sreadChar*(s: PosixStream): char =
  let n = read(s.fd, addr result, 1)
  assert n == 1

method sendData*(s: PosixStream; buffer: pointer; len: int): int =
  let n = write(s.fd, buffer, len)
  if n < 0:
    raisePosixIOError()
  return n

method setBlocking*(s: PosixStream; blocking: bool) {.base.} =
  s.blocking = blocking
  let ofl = fcntl(s.fd, F_GETFL, 0)
  if blocking:
    discard fcntl(s.fd, F_SETFL, ofl and not O_NONBLOCK)
  else:
    discard fcntl(s.fd, F_SETFL, ofl or O_NONBLOCK)

method seek*(s: PosixStream; off: int) =
  if lseek(s.fd, Off(off), SEEK_SET) == -1:
    raisePosixIOError()

method sclose*(s: PosixStream) =
  assert not s.closed
  discard close(s.fd)
  s.closed = true

proc newPosixStream*(fd: FileHandle): PosixStream =
  return PosixStream(fd: cint(fd), blocking: true)

proc newPosixStream*(fd: SocketHandle): PosixStream =
  return PosixStream(fd: cint(fd), blocking: true)

proc newPosixStream*(path: string; flags, mode: cint): PosixStream =
  let fd = open(cstring(path), flags, mode)
  if fd == -1:
    return nil
  return newPosixStream(fd)

type
  MaybeMappedMemory* = ptr MaybeMappedMemoryObj

  MaybeMappedMemoryObj = object
    p0: pointer
    p0len: int
    fromMmap: bool
    p*: ptr UncheckedArray[uint8]
    len*: int

# Read data of size "len", or mmap it if the stream is a file.
proc recvDataLoopOrMmap*(ps: PosixStream; ilen = -1): MaybeMappedMemory =
  var stats: Stat
  if fstat(ps.fd, stats) != -1 and S_ISREG(stats.st_mode):
    let srcOff = lseek(ps.fd, 0, SEEK_CUR) # skip headers
    let p0len = int(stats.st_size)
    let len = int(stats.st_size - srcOff)
    if ilen != -1:
      doAssert ilen == len
    let p0 = mmap(nil, p0len, PROT_READ, MAP_SHARED, ps.fd, 0)
    if p0 == MAP_FAILED:
      return nil
    let p1 = addr cast[ptr UncheckedArray[uint8]](p0)[srcOff]
    let res = create(MaybeMappedMemoryObj)
    res[] = MaybeMappedMemoryObj(
      p0: p0,
      p0len: p0len,
      p: cast[ptr UncheckedArray[uint8]](p1),
      len: len,
      fromMmap: true
    )
    return res
  let p = cast[ptr UncheckedArray[uint8]](alloc(ilen))
  ps.recvDataLoop(p, ilen)
  let res = create(MaybeMappedMemoryObj)
  res[] = MaybeMappedMemoryObj(
    p0: p,
    p0len: ilen,
    p: p,
    len: ilen,
    fromMmap: false
  )
  return res

proc maybeMmapForSend*(ps: PosixStream; len: int): MaybeMappedMemory =
  var stats: Stat
  if fstat(0, stats) != -1 and S_ISREG(stats.st_mode):
    try:
      ps.seek(len - 1)
      ps.sendDataLoop([char(0)])
    except IOError:
      return nil
    let p0 = mmap(nil, len, PROT_WRITE, MAP_SHARED, ps.fd, 0)
    if p0 == MAP_FAILED:
      return nil
    let res = create(MaybeMappedMemoryObj)
    res[] = MaybeMappedMemoryObj(
      p0: p0,
      p0len: len,
      p: cast[ptr UncheckedArray[uint8]](p0),
      len: len,
      fromMmap: true
    )
    return res
  let p = cast[ptr UncheckedArray[uint8]](alloc(len))
  let res = create(MaybeMappedMemoryObj)
  res[] = MaybeMappedMemoryObj(
    p0: p,
    p0len: len,
    p: p,
    len: len,
    fromMmap: false
  )
  return res

proc sendDataLoop*(ps: PosixStream; mem: MaybeMappedMemory) =
  # only send if not mmapped; otherwise everything is already where it should be
  if not mem.fromMmap:
    ps.sendDataLoop(mem.p, mem.len)

template dealloc*(mem: MaybeMappedMemory) {.error: "use deallocMem".} = discard

proc deallocMem*(mem: MaybeMappedMemory) =
  if mem.fromMmap:
    discard munmap(mem.p0, mem.p0len)
  else:
    dealloc(mem.p0)
  dealloc(pointer(mem))

proc drain*(ps: PosixStream) =
  assert not ps.blocking
  var buffer {.noinit.}: array[4096, uint8]
  try:
    while true:
      discard ps.recvData(addr buffer[0], buffer.len)
  except ErrorAgain:
    discard

type SocketStream* = ref object of PosixStream
  source*: Socket

method recvData*(s: SocketStream; buffer: pointer; len: int): int =
  let n = s.source.recv(buffer, len)
  if n < 0:
    raisePosixIOError()
  if n == 0:
    if unlikely(s.isend):
      raise newException(EOFError, "eof")
    s.isend = true
  return n

method sendData*(s: SocketStream; buffer: pointer; len: int): int =
  let n = s.source.send(buffer, len)
  if n < 0:
    raisePosixIOError()
  return n

{.compile: "sendfd.c".}
proc sendfd(sock, fd: cint): int {.importc.}

proc sendFileHandle*(s: SocketStream; fd: FileHandle) =
  assert not s.source.hasDataBuffered
  let n = sendfd(s.fd, cint(fd))
  if n < 0:
    raisePosixIOError()
  assert n == 1 # we send a single nul byte as buf

{.compile: "recvfd.c".}
proc recvfd(sock: cint; fdout: ptr cint): int {.importc.}

proc recvFileHandle*(s: SocketStream): FileHandle =
  assert not s.source.hasDataBuffered
  var fd: cint
  let n = recvfd(s.fd, addr fd)
  if n < 0:
    raisePosixIOError()
  return FileHandle(fd)

method setBlocking*(s: SocketStream; blocking: bool) =
  s.blocking = blocking
  s.source.getFd().setBlocking(blocking)

method seek*(s: SocketStream; off: int) =
  doAssert false

method sclose*(s: SocketStream) =
  assert not s.closed
  s.source.close()
  s.closed = true

# see serversocket.nim for an explanation
{.compile: "connect_unix.c".}
proc connect_unix_from_c(fd: cint; path: cstring; pathlen: cint): cint
  {.importc.}
when defined(freebsd):
  # for FreeBSD/capsicum
  proc connectat_unix_from_c(baseFd, sockFd: cint; rel_path: cstring;
    rel_pathlen: cint): cint {.importc.}

proc connectAtSocketStream0(socketDir: string; baseFd, pid: int;
    blocking = true): SocketStream =
  let sock = newSocket(Domain.AF_UNIX, SockType.SOCK_STREAM,
    Protocol.IPPROTO_IP, buffered = false)
  if not blocking:
    sock.getFd().setBlocking(false)
  let path = getSocketPath(socketDir, pid)
  if baseFd == -1:
    if connect_unix_from_c(cint(sock.getFd()), cstring(path),
        cint(path.len)) != 0:
      raiseOSError(osLastError())
  else:
    when defined(freebsd):
      doAssert baseFd != -1
      let name = getSocketName(pid)
      if connectat_unix_from_c(cint(baseFd), cint(sock.getFd()), cstring(name),
          cint(name.len)) != 0:
        raiseOSError(osLastError())
    else:
      # shouldn't have sockDirFd on other architectures
      doAssert false
  return SocketStream(
    source: sock,
    fd: cint(sock.getFd()),
    blocking: blocking
  )

proc connectSocketStream*(socketDir: string; baseFd, pid: int;
    blocking = true): SocketStream =
  try:
    return connectAtSocketStream0(socketDir, baseFd, pid, blocking)
  except OSError:
    return nil

proc acceptSocketStream*(ssock: ServerSocket; blocking = true): SocketStream =
  var sock: Socket
  ssock.sock.accept(sock, inheritable = true)
  if not blocking:
    sock.getFd().setBlocking(false)
  return SocketStream(
    blocking: blocking,
    source: sock,
    fd: cint(sock.getFd())
  )

type
  BufStream* = ref object of DynStream
    source*: PosixStream
    registerFun: proc(fd: int)
    registered: bool
    writeBuffer: string

method recvData*(s: BufStream; buffer: pointer; len: int): int =
  s.source.recvData(buffer, len)

method sendData*(s: BufStream; buffer: pointer; len: int): int =
  s.source.setBlocking(false)
  block nobuf:
    var n: int
    if not s.registered:
      try:
        n = s.source.sendData(buffer, len)
        if n == len:
          break nobuf
      except ErrorAgain:
        discard
      s.registerFun(s.source.fd)
      s.registered = true
    let olen = s.writeBuffer.len
    s.writeBuffer.setLen(s.writeBuffer.len + len - n)
    let buffer = cast[ptr UncheckedArray[uint8]](buffer)
    copyMem(addr s.writeBuffer[olen], addr buffer[n], len - n)
  s.source.setBlocking(true)
  return len

method sclose*(s: BufStream) =
  assert not s.closed
  s.source.sclose()
  s.closed = true

proc flushWrite*(s: BufStream): bool =
  s.source.setBlocking(false)
  let n = s.source.sendData(s.writeBuffer)
  s.source.setBlocking(true)
  if n == s.writeBuffer.len:
    s.writeBuffer = ""
    s.registered = false
    return true
  s.writeBuffer = s.writeBuffer.substr(n)
  return false

proc reallyFlush*(s: BufStream) =
  if s.writeBuffer.len > 0:
    s.source.sendDataLoop(s.writeBuffer)

proc newBufStream*(ps: PosixStream; registerFun: proc(fd: int)): BufStream =
  return BufStream(source: ps, blocking: ps.blocking, registerFun: registerFun)

type
  DynFileStream* = ref object of DynStream
    file*: File

method recvData*(s: DynFileStream; buffer: pointer; len: int): int =
  let n = s.file.readBuffer(buffer, len)
  if n == 0:
    if unlikely(s.isend):
      raise newException(EOFError, "eof")
    s.isend = true
  return n

method sendData*(s: DynFileStream; buffer: pointer; len: int): int =
  return s.file.writeBuffer(buffer, len)

method seek*(s: DynFileStream; off: int) =
  s.file.setFilePos(int64(off))

method sclose*(s: DynFileStream) =
  assert not s.closed
  s.file.close()
  s.closed = true

method sflush*(s: DynFileStream) =
  s.file.flushFile()

proc newDynFileStream*(file: File): DynFileStream =
  return DynFileStream(file: file, blocking: true)

proc newDynFileStream*(path: string): DynFileStream =
  var file: File
  if file.open(path):
    return newDynFileStream(path)
  return nil
