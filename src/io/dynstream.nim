{.push raises: [].}

import std/posix

type
  DynStream* = ref object of RootObj
    isend*: bool
    closed: bool

# Semantics of this function are those of POSIX read(3): that is, it
# may return a result that is lower than `len`, and that does not mean
# the stream is finished.
# isend must be set by implementations when the end of the stream is
# reached.  If the user is trying to read after isend is set, the
# implementation should assert.
method readData*(s: DynStream; buffer: pointer; len: int): int {.base.} =
  result = 0
  doAssert false

# See above, but with write(2)
method writeData*(s: DynStream; buffer: pointer; len: int): int {.base.} =
  result = 0
  doAssert false

method seek*(s: DynStream; off: int64): int64 {.base.} =
  result = 0
  doAssert false

method sclose*(s: DynStream) {.base.} =
  doAssert false

method flush*(s: DynStream): bool {.base.} =
  true

proc readData*(s: DynStream; buffer: var openArray[uint8]): int {.inline.} =
  return s.readData(addr buffer[0], buffer.len)

proc readData*(s: DynStream; buffer: var openArray[char]): int {.inline.} =
  return s.readData(addr buffer[0], buffer.len)

proc writeData*(s: DynStream; buffer: openArray[char]): int {.inline.} =
  return s.writeData(unsafeAddr buffer[0], buffer.len)

proc writeData*(s: DynStream; buffer: openArray[uint8]): int {.inline.} =
  return s.writeData(unsafeAddr buffer[0], buffer.len)

proc readDataLoop*(s: DynStream; buffer: pointer; len: int): bool =
  var n = 0
  while n < len:
    let m = s.readData(addr cast[ptr UncheckedArray[uint8]](buffer)[n], len - n)
    if m <= 0:
      return false
    n += m
  return true

proc readDataLoop*(s: DynStream; buffer: var openArray[uint8]): bool
    {.inline.} =
  if buffer.len == 0:
    return true
  return s.readDataLoop(addr buffer[0], buffer.len)

proc readDataLoop*(s: DynStream; buffer: var openArray[char]): bool {.inline.} =
  if buffer.len == 0:
    return true
  return s.readDataLoop(addr buffer[0], buffer.len)

proc writeDataLoop*(s: DynStream; buffer: pointer; len: int): bool =
  var n = 0
  while n < len:
    let p = addr cast[ptr UncheckedArray[uint8]](buffer)[n]
    let m = s.writeData(p, len - n)
    if m <= 0:
      return false
    n += m
  return true

proc writeDataLoop*(s: DynStream; buffer: openArray[uint8]): bool {.inline.} =
  if buffer.len > 0:
    return s.writeDataLoop(unsafeAddr buffer[0], buffer.len)
  return true

proc writeDataLoop*(s: DynStream; buffer: openArray[char]): bool {.inline.} =
  if buffer.len > 0:
    return s.writeDataLoop(unsafeAddr buffer[0], buffer.len)
  return true

proc write*(s: DynStream; buffer: openArray[char]) {.inline.} =
  discard s.writeDataLoop(buffer)

proc write*(s: DynStream; c: char) {.inline.} =
  s.write([c])

proc setEnd(s: DynStream) =
  assert not s.isend
  s.isend = true

type
  PosixStream* = ref object of DynStream
    fd*: cint
    blocking*: bool

proc readAll*(s: PosixStream; buffer: var string): bool =
  assert s.blocking
  buffer = newString(4096)
  var idx = 0
  while true:
    let n = s.readData(addr buffer[idx], buffer.len - idx)
    if n == 0:
      break
    if n < 0:
      return false
    idx += n
    if idx == buffer.len:
      buffer.setLen(buffer.len + 4096)
  buffer.setLen(idx)
  true

proc readAll*(s: PosixStream): string =
  discard s.readAll(result)

method readData*(s: PosixStream; buffer: pointer; len: int): int =
  let n = read(s.fd, buffer, len)
  if n == 0:
    s.setEnd()
  return n

method writeData*(s: PosixStream; buffer: pointer; len: int): int =
  return write(s.fd, buffer, len)

method setBlocking*(s: PosixStream; blocking: bool) {.base.} =
  s.blocking = blocking
  let ofl = fcntl(s.fd, F_GETFL, 0)
  if blocking:
    discard fcntl(s.fd, F_SETFL, ofl and not O_NONBLOCK)
  else:
    discard fcntl(s.fd, F_SETFL, ofl or O_NONBLOCK)

method seek*(s: PosixStream; off: int64): int64 =
  return int64(lseek(s.fd, Off(off), SEEK_SET))

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

func isatty*(ps: PosixStream): bool =
  return ps.fd.isatty() == 1

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
proc readDataLoopOrMmap*(ps: PosixStream; ilen: int): MaybeMappedMemory =
  var stats: Stat
  if fstat(ps.fd, stats) != -1 and S_ISREG(stats.st_mode):
    return ps.mmap(stats, ilen)
  let res = create(MaybeMappedMemoryObj)
  let p = cast[ptr UncheckedArray[uint8]](alloc(ilen))
  if not ps.readDataLoop(p, ilen):
    return nil
  res[] = MaybeMappedMemoryObj(
    t: mmmtAlloc,
    p0: p,
    p0len: ilen,
    p: p,
    len: ilen
  )
  return res

# Try to mmap the file, and fall back to readAll if it fails.
# This never returns nil.
proc readAllOrMmap*(ps: PosixStream): MaybeMappedMemory =
  var stats: Stat
  if fstat(ps.fd, stats) != -1 and S_ISREG(stats.st_mode):
    let res = ps.mmap(stats, -1)
    if res != nil:
      return res
  let res = create(MaybeMappedMemoryObj)
  let s = new(string)
  s[] = ps.readAll()
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
    if ps.seek(len - 1) < 0:
      return nil
    if not ps.writeDataLoop([char(0)]):
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

proc writeDataLoop*(ps: PosixStream; mem: MaybeMappedMemory): bool =
  # only send if not mmapped; otherwise everything is already where it should be
  if mem.t != mmmtMmap:
    return ps.writeDataLoop(mem.toOpenArray())
  return true

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
  while ps.readData(buffer) > 0:
    discard

proc setCloseOnExec*(ps: PosixStream) =
  let ofd = fcntl(ps.fd, F_GETFD)
  discard fcntl(ps.fd, ofd or F_SETFD, FD_CLOEXEC)

type SocketStream* = ref object of PosixStream

proc sendMsg*(s: SocketStream; buffer: openArray[uint8];
    fds: openArray[cint]): int =
  assert buffer.len > 0
  var iov = IOVec(iov_base: unsafeAddr buffer[0], iov_len: csize_t(buffer.len))
  let fdSize = sizeof(cint) * fds.len
  let controlLen = CMSG_SPACE(csize_t(fdSize))
  var cmsgBuf = newSeqUninit[uint8](controlLen)
  var hdr = Tmsghdr(
    msg_iov: addr iov,
    msg_iovlen: 1,
    msg_control: if cmsgBuf.len > 0: addr cmsgBuf[0] else: nil,
    msg_controllen: SockLen(controlLen)
  )
  let cmsg = CMSG_FIRSTHDR(addr hdr)
  cmsg.cmsg_len = SockLen(CMSG_LEN(csize_t(fdSize)))
  cmsg.cmsg_level = SOL_SOCKET
  cmsg.cmsg_type = SCM_RIGHTS
  if fds.len > 0:
    copyMem(CMSG_DATA(cmsg), unsafeAddr fds[0], fdSize)
  return sendmsg(SocketHandle(s.fd), addr hdr, 0)

proc recvMsg*(s: SocketStream; buffer: var openArray[uint8];
    fdbuf: var openArray[cint]; numFds: var int): int =
  assert buffer.len > 0
  var iov = IOVec(iov_base: addr buffer[0], iov_len: csize_t(buffer.len))
  let fdbufSize = sizeof(cint) * fdbuf.len
  let controlLen = CMSG_SPACE(csize_t(fdbufSize))
  var cmsgBuf = newSeqUninit[uint8](controlLen)
  var hdr = Tmsghdr(
    msg_iov: addr iov,
    msg_iovlen: 1,
    msg_control: if cmsgBuf.len > 0: addr cmsgBuf[0] else: nil,
    msg_controllen: SockLen(controlLen)
  )
  let n = recvmsg(SocketHandle(s.fd), addr hdr, 0)
  if n <= 0:
    return n
  numFds = 0
  var cmsg = CMSG_FIRSTHDR(addr hdr)
  while cmsg != nil:
    let data = CMSG_DATA(cmsg)
    let size = int(cmsg.cmsg_len) - (cast[int](data) - cast[int](cmsg))
    if cmsg.cmsg_level == SOL_SOCKET and cmsg.cmsg_type == SCM_RIGHTS and
        size mod sizeof(cint) == 0:
      let n = size div sizeof(cint)
      var m = min(fdbuf.len, numFds + n) - numFds
      copyMem(addr fdbuf[numFds], data, m * sizeof(cint))
      numFds += m
      while m < n:
        var fd {.noinit.}: cint
        copyMem(addr fd, addr cast[ptr UncheckedArray[cint]](data)[m],
          sizeof(fd))
        discard close(fd)
    else:
      #TODO we could just return -2 here, but I'm not sure if it can
      # ever happen
      assert false
    cmsg = CMSG_NXTHDR(addr hdr, cmsg)
  return n

method seek*(s: SocketStream; off: int64): int64 =
  result = 0
  doAssert false

proc newSocketStream*(fd: cint): SocketStream =
  return SocketStream(fd: fd, blocking: true)

type
  BufStream* = ref object of DynStream
    source*: SocketStream
    registerFun: proc(fd: int)
    registered: bool
    writeBuffer: string

method readData*(s: BufStream; buffer: pointer; len: int): int =
  s.source.readData(buffer, len)

method writeData*(s: BufStream; buffer: pointer; len: int): int =
  s.source.setBlocking(false)
  block nobuf:
    var n: int
    if not s.registered:
      n = s.source.writeData(buffer, len)
      if n == len:
        break nobuf
      let e = errno
      if n == -1 and e != EAGAIN and e != EWOULDBLOCK and e != EINTR:
        return -1
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
  let n = s.source.writeData(s.writeBuffer)
  if n == -1:
    return false
  s.source.setBlocking(true)
  if n == s.writeBuffer.len:
    s.writeBuffer = ""
    s.registered = false
    return true
  s.writeBuffer = s.writeBuffer.substr(n)
  return false

method flush*(s: BufStream): bool =
  return s.source.writeDataLoop(s.writeBuffer)

proc newBufStream*(s: SocketStream; registerFun: proc(fd: int)): BufStream =
  return BufStream(source: s, registerFun: registerFun)

{.pop.} # raises: []
