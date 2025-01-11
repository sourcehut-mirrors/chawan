import std/posix

type
  DynStream* = ref object of RootObj
    isend*: bool
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
  while n < len:
    n += s.recvData(addr cast[ptr UncheckedArray[uint8]](buffer)[n], len - n)

proc recvDataLoop*(s: DynStream; buffer: var openArray[uint8]) {.inline.} =
  if buffer.len > 0:
    s.recvDataLoop(addr buffer[0], buffer.len)

proc recvDataLoop*(s: DynStream; buffer: var openArray[char]) {.inline.} =
  if buffer.len > 0:
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
    blocking*: bool

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

proc closeHandle(fd, flags: cint) =
  let devnull = open("/dev/null", flags)
  doAssert devnull != -1
  if devnull != fd:
    discard dup2(devnull, fd)
    discard close(devnull)

proc closeStdin*() =
  closeHandle(0, O_RDONLY)

proc closeStdout*() =
  closeHandle(1, O_WRONLY)

proc closeStderr*() =
  closeHandle(2, O_WRONLY)

# dup2 the stream to fd, close the old fd and set fd as the new fd
# of ps.
# If ps already points to fd, then do nothing.
proc moveFd*(ps: PosixStream; fd: cint) =
  if ps.fd == fd:
    discard
  else:
    discard dup2(ps.fd, fd)
    discard close(ps.fd)
    ps.fd = fd

proc newPosixStream*(fd: cint): PosixStream =
  return PosixStream(fd: fd, blocking: true)

proc newPosixStream*(fd: SocketHandle): PosixStream =
  return newPosixStream(cint(fd))

proc newPosixStream*(path: string; flags = cint(O_RDONLY); mode = cint(0)):
    PosixStream =
  if path == "":
    return nil
  let fd = open(cstring(path), flags, mode)
  if fd == -1:
    return nil
  return newPosixStream(fd)

type
  MaybeMappedMemory* = ptr MaybeMappedMemoryObj

  MaybeMappedMemoryType = enum
    mmmtMmap, mmmtAlloc, mmmtString

  MaybeMappedMemoryObj = object
    t: MaybeMappedMemoryType
    p0: pointer
    p0len: int
    p*: ptr UncheckedArray[uint8]
    len*: int

proc mmap(ps: PosixStream; stats: Stat; ilen: int): MaybeMappedMemory =
  let srcOff = lseek(ps.fd, 0, SEEK_CUR) # skip headers
  doAssert srcOff >= 0
  let p0len = int(stats.st_size)
  let len = int(stats.st_size - srcOff)
  if ilen != -1:
    doAssert ilen == len
  if len == 0:
    let res = create(MaybeMappedMemoryObj)
    res[] = MaybeMappedMemoryObj(t: mmmtMmap, p0: nil, p0len: 0, p: nil, len: 0)
    return res
  let p0 = mmap(nil, p0len, PROT_READ, MAP_PRIVATE, ps.fd, 0)
  if p0 == MAP_FAILED:
    return nil
  let p1 = addr cast[ptr UncheckedArray[uint8]](p0)[srcOff]
  let res = create(MaybeMappedMemoryObj)
  res[] = MaybeMappedMemoryObj(
    t: mmmtMmap,
    p0: p0,
    p0len: p0len,
    p: cast[ptr UncheckedArray[uint8]](p1),
    len: len
  )
  return res

# Try to mmap the stream, and return nil on failure.
proc mmap*(ps: PosixStream): MaybeMappedMemory =
  var stats: Stat
  if fstat(ps.fd, stats) != -1:
    return ps.mmap(stats, -1)
  return nil

# Read data of size "len", or mmap it if the stream is a file.
# This may return nil.
proc recvDataLoopOrMmap*(ps: PosixStream; ilen: int): MaybeMappedMemory =
  var stats: Stat
  if fstat(ps.fd, stats) != -1 and S_ISREG(stats.st_mode):
    return ps.mmap(stats, ilen)
  let res = create(MaybeMappedMemoryObj)
  let p = cast[ptr UncheckedArray[uint8]](alloc(ilen))
  ps.recvDataLoop(p, ilen)
  res[] = MaybeMappedMemoryObj(
    t: mmmtAlloc,
    p0: p,
    p0len: ilen,
    p: p,
    len: ilen
  )
  return res

# Try to mmap the file, and fall back to recvAll if it fails.
# This never returns nil.
proc recvAllOrMmap*(ps: PosixStream): MaybeMappedMemory =
  var stats: Stat
  if fstat(ps.fd, stats) != -1 and S_ISREG(stats.st_mode):
    let res = ps.mmap(stats, -1)
    if res != nil:
      return res
  let res = create(MaybeMappedMemoryObj)
  let s = new(string)
  s[] = ps.recvAll()
  GC_ref(s)
  let p = if s[].len > 0:
    cast[ptr UncheckedArray[uint8]](addr s[][0])
  else:
    nil
  res[] = MaybeMappedMemoryObj(
    t: mmmtString,
    p0: cast[pointer](s),
    p0len: s[].len,
    p: p,
    len: s[].len
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
      t: mmmtMmap,
      p0: p0,
      p0len: len,
      p: cast[ptr UncheckedArray[uint8]](p0),
      len: len
    )
    return res
  let p = cast[ptr UncheckedArray[uint8]](alloc(len))
  let res = create(MaybeMappedMemoryObj)
  res[] = MaybeMappedMemoryObj(
    t: mmmtAlloc,
    p0: p,
    p0len: len,
    p: p,
    len: len
  )
  return res

template toOpenArray*(mem: MaybeMappedMemory): openArray[char] =
  cast[ptr UncheckedArray[char]](mem.p).toOpenArray(0, mem.len - 1)

proc sendDataLoop*(ps: PosixStream; mem: MaybeMappedMemory) =
  # only send if not mmapped; otherwise everything is already where it should be
  if mem.t != mmmtMmap:
    ps.sendDataLoop(mem.toOpenArray())

template dealloc*(mem: MaybeMappedMemory) {.error: "use deallocMem".} = discard

proc deallocMem*(mem: MaybeMappedMemory) =
  case mem.t
  of mmmtMmap:
    if mem.p0len != 0:
      discard munmap(mem.p0, mem.p0len)
  of mmmtString: GC_unref(cast[ref string](mem.p0))
  of mmmtAlloc: dealloc(mem.p0)
  dealloc(pointer(mem))

proc drain*(ps: PosixStream) =
  assert not ps.blocking
  var buffer {.noinit.}: array[4096, uint8]
  try:
    while true:
      discard ps.recvData(addr buffer[0], buffer.len)
  except ErrorAgain:
    discard

proc setCloseOnExec*(ps: PosixStream) =
  let ofd = fcntl(ps.fd, F_GETFD)
  discard fcntl(ps.fd, ofd or F_SETFD, FD_CLOEXEC)

type SocketStream* = ref object of PosixStream

proc sendMsg*(s: SocketStream; buffer: openArray[uint8];
    sendAux: openArray[cint]) =
  var dummy = 0u8
  var iov = IOVec(iov_base: addr dummy, iov_len: 1)
  if buffer.len > 0:
    iov = IOVec(iov_base: unsafeAddr buffer[0], iov_len: csize_t(buffer.len))
  let sendAuxSize = sizeof(cint) * sendAux.len
  let controlLen = CMSG_SPACE(csize_t(sendAuxSize))
  var cmsgBuf = if controlLen > 0: alloc(controlLen) else: nil
  var hdr = Tmsghdr()
  zeroMem(addr hdr, sizeof(hdr))
  hdr.msg_iov = addr iov
  hdr.msg_iovlen = 1
  hdr.msg_control = cmsgBuf
  hdr.msg_controllen = controlLen
  let cmsg = CMSG_FIRSTHDR(addr hdr)
  cmsg.cmsg_len = CMSG_LEN(csize_t(sendAuxSize))
  cmsg.cmsg_level = SOL_SOCKET
  cmsg.cmsg_type = SCM_RIGHTS
  if sendAux.len > 0:
    copyMem(CMSG_DATA(cmsg), unsafeAddr sendAux[0], sendAuxSize)
  let n = sendmsg(SocketHandle(s.fd), addr hdr, 0)
  if cmsgBuf != nil:
    dealloc(cmsgBuf)
  if n < 0:
    raisePosixIOError()
  if n < buffer.len:
    raise newException(EOFError, "eof")

proc recvMsg*(s: SocketStream; buffer: var openArray[uint8];
    recvAux: var openArray[cint]) =
  var dummy {.noinit.}: uint8
  var iov = IOVec(iov_base: addr dummy, iov_len: 1)
  if buffer.len > 0:
    iov = IOVec(iov_base: addr buffer[0], iov_len: csize_t(buffer.len))
  let recvAuxSize = sizeof(cint) * recvAux.len
  let controlLen = CMSG_SPACE(csize_t(recvAuxSize))
  var cmsgBuf = if controlLen > 0: alloc(controlLen) else: nil
  var hdr = Tmsghdr()
  zeroMem(addr hdr, sizeof(hdr))
  hdr.msg_iov = addr iov
  hdr.msg_iovlen = 1
  hdr.msg_control = cmsgBuf
  hdr.msg_controllen = controlLen
  let n = recvmsg(SocketHandle(s.fd), addr hdr, 0)
  if n < 0:
    if cmsgBuf != nil:
      dealloc(cmsgBuf)
    raisePosixIOError()
  if n < buffer.len:
    if cmsgBuf != nil:
      dealloc(cmsgBuf)
    raise newException(EOFError, "eof")
  if recvAux.len > 0:
    let cmsg = CMSG_FIRSTHDR(addr hdr)
    copyMem(addr recvAux[0], CMSG_DATA(cmsg), recvAuxSize)
  if cmsgBuf != nil:
    dealloc(cmsgBuf)

method seek*(s: SocketStream; off: int) =
  doAssert false

proc newSocketStream*(fd: cint): SocketStream =
  return SocketStream(fd: fd, blocking: true)

type
  BufStream* = ref object of DynStream
    source*: SocketStream
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

method sflush*(s: BufStream) =
  if s.writeBuffer.len > 0:
    s.source.sendDataLoop(s.writeBuffer)

proc newBufStream*(s: SocketStream; registerFun: proc(fd: int)): BufStream =
  return BufStream(source: s, registerFun: registerFun)

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
  return DynFileStream(file: file)

proc newDynFileStream*(path: string): DynFileStream =
  var file: File
  if file.open(path):
    return newDynFileStream(path)
  return nil
