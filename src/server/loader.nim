# A file loader server (?)
# We receive various types of requests on a control socket, then respond
# to each with a response.  In case of the "load" request, we return one
# half of a socket pair, and then send connection information before the
# response body so that the protocol looks like:
# C: Request
# S: (packet 1) res (0 => success, _ => error)
# if success:
#  S: (packet 1) output ID
#  S: (packet 2) status code, headers
#  C: resume (on control socket)
#  S: response body
# else:
#  S: (packet 1) error message
#
# The body is passed to the stream as-is, so effectively nothing can follow it.
#
# Note: if the consumer closes the request's body after headers have been
# passed, it will *not* be cleaned up until a `resume' command is
# received. (This allows for passing outputIds to the pager for later
# addCacheFile commands there.)

import std/algorithm
import std/deques
import std/options
import std/os
import std/posix
import std/strutils
import std/tables
import std/times

import config/cookie
import config/urimethodmap
import io/dynstream
import io/packetreader
import io/packetwriter
import io/poll
import monoucha/javascript
import server/connecterror
import server/headers
import server/loaderiface
import server/request
import server/urlfilter
import types/formdata
import types/opt
import types/referrer
import types/url
import utils/twtstr

# Try to make it a SmallChunk.
# We must subtract SmallChunk size, and then FreeCell size.
# (See system/alloc.nim for details.)
#TODO measure this on 32-bit too, we get a few more bytes there
const LoaderBufferPageSize = 4016 # 4096 - 64 - 16

# Override posix.Time
type Time = times.Time

type
  CachedItem = ref object
    id: int
    refc: int
    offset: int64
    path: string

  LoaderBuffer = ref object
    len: int
    page: seq[uint8]

  LoaderHandle = ref object of RootObj
    registered: bool # track registered state
    stream: PosixStream # input/output stream depending on type
    when defined(debug):
      url: URL

  InputHandle = ref object of LoaderHandle
    outputs: seq[OutputHandle] # list of outputs to be streamed into
    cacheId: int # if cached, our ID in a client cacheMap
    cacheRef: CachedItem # if this is a tocache handle, a ref to our cache item
    parser: HeaderParser # only exists for CGI handles
    rstate: ResponseState # track response state
    contentLen: uint64 # value of Content-Length; uint64.high if no such header
    bytesSeen: uint64 # number of bytes read until now
    startTime: Time # time when download of the body was started

  OutputHandle = ref object of LoaderHandle
    parent: InputHandle
    currentBuffer: LoaderBuffer
    currentBufferIdx: int
    buffers: Deque[LoaderBuffer]
    ownerPid: int
    outputId: int
    istreamAtEnd: bool
    suspended: bool
    dead: bool
    bytesSent: uint64

  HandleParserState = enum
    hpsBeforeLines, hpsAfterFirstLine, hpsControlDone

  HeaderParser = ref object
    state: HandleParserState
    crSeen: bool
    status: uint16
    lineBuffer: string
    headers: Headers

  ResponseState = enum
    rsBeforeResult, rsAfterFailure, rsBeforeStatus, rsAfterHeaders

  AuthItem = ref object
    origin: Origin
    username: string
    password: string

  ClientHandle = ref object of LoaderHandle
    pid: int
    # List of cached resources.
    cacheMap: seq[CachedItem]
    # List of file descriptors passed by the client.
    passedFdMap: seq[tuple[name: string; ps: PosixStream]] # host -> ps
    config: LoaderClientConfig
    # List of credentials the client has access to (same origin only).
    authMap: seq[AuthItem]

  DownloadItem = ref object
    path: string
    displayUrl: string
    output: OutputHandle
    sent: uint64
    contentLen: uint64
    startTime: Time

  LoaderContext = object
    pid: int
    pagerClient: ClientHandle
    config: LoaderConfig
    handleMap: seq[LoaderHandle]
    pollData: PollData
    tmpfSeq: uint
    # List of existing clients (buffer or pager) that may make requests.
    clientMap: Table[int, ClientHandle] # pid -> data
    # ID of next output. TODO: find a better allocation scheme
    outputNum: int
    # List of *all* credentials the loader knows of.
    authMap: seq[AuthItem]
    # Handles to unregister and close at the end of this iteration.
    # This is needed so that we don't accidentally replace them with new
    # streams in the same iteration as they got closed.
    unregRead: seq[InputHandle]
    unregWrite: seq[OutputHandle]
    unregClient: seq[ClientHandle]
    downloadList: seq[DownloadItem]

  LoaderConfig* = object
    cgiDir*: seq[string]
    uriMethodMap*: URIMethodMap
    w3mCGICompat*: bool
    tmpdir*: string
    configdir*: string
    bookmark*: string

  PushBufferResult = enum
    pbrDone, pbrUnregister

proc pushBuffer(ctx: var LoaderContext; output: OutputHandle;
  buffer: LoaderBuffer; ignoreSuspension: bool): PushBufferResult

when defined(debug):
  func `$`*(buffer: LoaderBuffer): string =
    var s = newString(buffer.len)
    copyMem(addr s[0], addr buffer.page[0], buffer.len)
    return s

proc put(ctx: var LoaderContext; handle: LoaderHandle) =
  let fd = int(handle.stream.fd)
  if ctx.handleMap.len <= fd:
    ctx.handleMap.setLen(fd + 1)
  assert ctx.handleMap[fd] == nil
  ctx.handleMap[fd] = handle

proc unset(ctx: var LoaderContext; handle: LoaderHandle) =
  assert not handle.registered
  let fd = int(handle.stream.fd)
  if fd < ctx.handleMap.len:
    ctx.handleMap[fd] = nil

proc getOutputId(ctx: var LoaderContext): int =
  result = ctx.outputNum
  inc ctx.outputNum

# Create a new loader handle, with the output stream ostream.
proc newInputHandle(ctx: var LoaderContext; ostream: PosixStream; pid: int;
    suspended = true): InputHandle =
  let handle = InputHandle(cacheId: -1, contentLen: uint64.high)
  let output = OutputHandle(
    stream: ostream,
    parent: handle,
    outputId: ctx.getOutputId(),
    ownerPid: pid,
    suspended: suspended
  )
  ctx.put(output)
  handle.outputs.add(output)
  return handle

func cap(buffer: LoaderBuffer): int {.inline.} =
  return LoaderBufferPageSize

template isEmpty(output: OutputHandle): bool =
  output.currentBuffer == nil and not output.suspended

proc newLoaderBuffer(size = LoaderBufferPageSize): LoaderBuffer =
  return LoaderBuffer(page: newSeqUninitialized[uint8](size))

proc bufferCleared(output: OutputHandle) =
  assert output.currentBuffer != nil
  output.currentBufferIdx = 0
  if output.buffers.len > 0:
    output.currentBuffer = output.buffers.popFirst()
  else:
    output.currentBuffer = nil

proc tee(ctx: var LoaderContext; outputIn: OutputHandle; ostream: PosixStream;
    pid: int): OutputHandle =
  assert outputIn.suspended
  let output = OutputHandle(
    parent: outputIn.parent,
    stream: ostream,
    currentBuffer: outputIn.currentBuffer,
    currentBufferIdx: outputIn.currentBufferIdx,
    buffers: outputIn.buffers,
    istreamAtEnd: outputIn.istreamAtEnd,
    outputId: ctx.getOutputId(),
    ownerPid: pid,
    suspended: outputIn.suspended
  )
  ctx.put(output)
  when defined(debug):
    output.url = outputIn.url
  if outputIn.parent != nil:
    assert outputIn.parent.parser == nil
    outputIn.parent.outputs.add(output)
  return output

template output(handle: InputHandle): OutputHandle =
  assert handle.outputs.len == 1
  handle.outputs[0]

template bufferFromWriter(w, body: untyped): LoaderBuffer =
  var w = initPacketWriter()
  body
  w.writeSize()
  LoaderBuffer(page: move(w.buffer), len: w.bufLen)

proc sendResult(ctx: var LoaderContext; handle: InputHandle; res: int;
    msg = ""): PushBufferResult =
  assert handle.rstate == rsBeforeResult
  let output = handle.output
  inc handle.rstate
  let buffer = bufferFromWriter w:
    w.swrite(res)
    if res == 0: # success
      assert msg == ""
      w.swrite(output.outputId)
      inc handle.rstate
    else: # error
      w.swrite(msg)
  return ctx.pushBuffer(output, buffer, ignoreSuspension = true)

proc sendStatus(ctx: var LoaderContext; handle: InputHandle; status: uint16;
    headers: Headers): PushBufferResult =
  assert handle.rstate == rsBeforeStatus
  inc handle.rstate
  let contentLens = headers.getOrDefault("Content-Length")
  handle.startTime = getTime()
  handle.contentLen = parseUInt64(contentLens).get(uint64.high)
  let buffer = bufferFromWriter w:
    w.swrite(status)
    w.swrite(headers)
  return ctx.pushBuffer(handle.output, buffer, ignoreSuspension = true)

proc writeData(ps: PosixStream; buffer: LoaderBuffer; si = 0): int {.inline.} =
  assert buffer.len - si > 0
  return ps.writeData(addr buffer.page[si], buffer.len - si)

proc iclose(ctx: var LoaderContext; handle: InputHandle) =
  if handle.stream != nil:
    ctx.unset(handle)
    handle.stream.sclose()
    handle.stream = nil

proc oclose(ctx: var LoaderContext; output: OutputHandle) =
  ctx.unset(output)
  output.stream.sclose()
  output.stream = nil

proc close(ctx: var LoaderContext; handle: InputHandle) =
  ctx.iclose(handle)
  for output in handle.outputs:
    if output.stream != nil:
      ctx.oclose(output)

proc close(ctx: var LoaderContext; client: ClientHandle) =
  # Do *not* unset the client, that breaks temp-file cleanup.
  client.stream.sclose()
  client.stream = nil
  for it in client.cacheMap:
    dec it.refc
    if it.refc == 0:
      discard unlink(cstring(it.path))

func isPrivileged(ctx: LoaderContext; client: ClientHandle): bool =
  return ctx.pagerClient == client

#TODO this may be too low if we want to use urimethodmap for everything
const MaxRewrites = 4

func canRewriteForCGICompat(ctx: LoaderContext; path: string): bool =
  if path.startsWith("/cgi-bin/") or path.startsWith("/$LIB/"):
    return true
  for dir in ctx.config.cgiDir:
    if path.startsWith(dir):
      return true
  return false

proc rejectHandle(ctx: var LoaderContext; handle: InputHandle;
    code: ConnectionError; msg = "") =
  case ctx.sendResult(handle, code, msg)
  of pbrDone: discard
  of pbrUnregister:
    ctx.unregWrite.add(handle.output)
    handle.output.dead = true

iterator inputHandles(ctx: LoaderContext): InputHandle {.inline.} =
  for it in ctx.handleMap:
    if it != nil and it of InputHandle:
      yield InputHandle(it)

iterator outputHandles(ctx: LoaderContext): OutputHandle {.inline.} =
  for it in ctx.handleMap:
    if it != nil and it of OutputHandle:
      yield OutputHandle(it)

func findOutput(ctx: var LoaderContext; id: int;
    client: ClientHandle): OutputHandle =
  assert id != -1
  for it in ctx.outputHandles:
    if it.outputId == id:
      # verify that it's safe to access this handle.
      doAssert ctx.isPrivileged(client) or client.pid == it.ownerPid
      return it
  return nil

func findCachedHandle(ctx: LoaderContext; cacheId: int): InputHandle =
  assert cacheId != -1
  for it in ctx.inputHandles:
    if it.cacheId == cacheId:
      return it
  return nil

func find(cacheMap: openArray[CachedItem]; id: int): int =
  for i, it in cacheMap.mypairs:
    if it.id == id:
      return i
  -1

proc register(ctx: var LoaderContext; handle: InputHandle) =
  assert not handle.registered
  ctx.pollData.register(handle.stream.fd, cshort(POLLIN))
  handle.registered = true

proc unregister(ctx: var LoaderContext; handle: InputHandle) =
  assert handle.registered
  ctx.pollData.unregister(int(handle.stream.fd))
  handle.registered = false

proc register(ctx: var LoaderContext; output: OutputHandle) =
  assert not output.registered
  ctx.pollData.register(int(output.stream.fd), cshort(POLLOUT))
  output.registered = true

proc unregister(ctx: var LoaderContext; output: OutputHandle) =
  assert output.registered
  ctx.pollData.unregister(int(output.stream.fd))
  output.registered = false

proc register(ctx: var LoaderContext; client: ClientHandle) =
  assert not client.registered
  ctx.clientMap[client.pid] = client
  ctx.pollData.register(client.stream.fd, cshort(POLLIN))
  client.registered = true

proc unregister(ctx: var LoaderContext; client: ClientHandle) =
  assert client.registered
  ctx.clientMap.del(client.pid)
  ctx.pollData.unregister(int(client.stream.fd))
  client.registered = false

# Either write data to the target output, or append it to the list of
# buffers to write and register the output in our selector.
# ignoreSuspension is meant to be used when sending the connection
# result and headers, which are sent irrespective of whether the handle
# is suspended or not.
proc pushBuffer(ctx: var LoaderContext; output: OutputHandle;
    buffer: LoaderBuffer; ignoreSuspension: bool): PushBufferResult =
  if output.suspended and not ignoreSuspension:
    if output.currentBuffer == nil:
      output.currentBuffer = buffer
      output.currentBufferIdx = 0
    else:
      output.buffers.addLast(buffer)
  elif output.currentBuffer == nil:
    var n = output.stream.writeData(buffer)
    if n < 0:
      let e = errno
      if e == EAGAIN or e == EWOULDBLOCK:
        n = 0
      else:
        assert e == EPIPE, $strerror(e)
        return pbrUnregister
    else:
      output.bytesSent += uint64(n)
    if n < buffer.len:
      output.currentBuffer = buffer
      output.currentBufferIdx = n
      ctx.register(output)
  else:
    output.buffers.addLast(buffer)
  pbrDone

proc redirectToFile(ctx: var LoaderContext; output: OutputHandle;
    targetPath: string; fileOutput: out OutputHandle; osent: out uint64): bool =
  fileOutput = nil
  osent = 0
  discard mkdir(cstring(ctx.config.tmpdir), 0o700)
  let ps = newPosixStream(targetPath, O_CREAT or O_WRONLY or O_TRUNC, 0o600)
  if ps == nil:
    return false
  if output.currentBuffer != nil:
    #TODO I suspect this is wrong... at least we should loop until n
    # is 0 or -1.
    let n = ps.writeData(output.currentBuffer, output.currentBufferIdx)
    if n > 0:
      osent += uint64(n)
    if unlikely(n < output.currentBuffer.len - output.currentBufferIdx):
      ps.sclose()
      return false
  for buffer in output.buffers:
    #TODO ditto
    let n = ps.writeData(buffer)
    if n > 0:
      osent += uint64(n)
    if unlikely(n < buffer.len):
      ps.sclose()
      return false
  if output.istreamAtEnd:
    ps.sclose()
  elif output.parent != nil:
    fileOutput = OutputHandle(
      parent: output.parent,
      stream: ps,
      istreamAtEnd: output.istreamAtEnd,
      outputId: ctx.getOutputId(),
      bytesSent: osent
    )
    output.parent.outputs.add(fileOutput)
    when defined(debug):
      fileOutput.url = output.url
  return true

proc getTempFile(ctx: var LoaderContext): string =
  result = ctx.config.tmpdir / "chaltmp" & $ctx.pid & "-" & $ctx.tmpfSeq
  inc ctx.tmpfSeq

proc addCacheFile(ctx: var LoaderContext; client: ClientHandle;
    output: OutputHandle): int =
  if output.parent != nil and output.parent.cacheId != -1:
    # may happen e.g. if client tries to cache a `cache:' URL
    return output.parent.cacheId
  let tmpf = ctx.getTempFile()
  var dummy: OutputHandle
  var sent: uint64
  if ctx.redirectToFile(output, tmpf, dummy, sent):
    let cacheId = output.outputId
    if output.parent != nil:
      output.parent.cacheId = cacheId
    client.cacheMap.add(CachedItem(id: cacheId, path: tmpf, refc: 1))
    return cacheId
  return -1

proc openCachedItem(client: ClientHandle; id: int): (PosixStream, int) =
  let n = client.cacheMap.find(id)
  if n != -1:
    let item = client.cacheMap[n]
    let ps = newPosixStream(client.cacheMap[n].path, O_RDONLY, 0)
    if ps == nil:
      client.cacheMap.del(n)
      return (nil, -1)
    assert item.offset != -1
    if ps.seek(item.offset) >= 0:
      return (ps, n)
  return (nil, -1)

proc addFd(ctx: var LoaderContext; handle: InputHandle) =
  handle.stream.setBlocking(false)
  ctx.register(handle)
  ctx.put(handle)

type ControlResult = enum
  crDone, crContinue, crError

proc handleFirstLine(ctx: var LoaderContext; handle: InputHandle; line: string):
    ControlResult =
  if line.startsWithIgnoreCase("HTTP/1.0") or
      line.startsWithIgnoreCase("HTTP/1.1"):
    let codes = line.until(' ', "HTTP/1.0 ".len)
    let code = parseUInt16(codes)
    if codes.len > 3 or code.isNone:
      ctx.rejectHandle(handle, ceCGIMalformedHeader)
      return crError
    case ctx.sendResult(handle, 0) # Success
    of pbrDone: discard
    of pbrUnregister: return crError
    handle.parser.status = code.get
    return crDone
  let k = line.until(':')
  if k.len == line.len:
    # invalid
    ctx.rejectHandle(handle, ceCGIMalformedHeader)
    return crError
  let v = line.substr(k.len + 1).strip()
  if k.equalsIgnoreCase("Status"):
    case ctx.sendResult(handle, 0) # success
    of pbrDone: discard
    of pbrUnregister: return crError
    let code = parseUInt16(v)
    if v.len > 3 or code.isNone:
      ctx.rejectHandle(handle, ceCGIMalformedHeader)
      return crError
    handle.parser.status = code.get
    return crContinue
  if k.equalsIgnoreCase("Cha-Control"):
    if v.startsWithIgnoreCase("Connected"):
      case ctx.sendResult(handle, 0) # success
      of pbrDone: discard
      of pbrUnregister: return crError
      return crContinue
    if v.startsWithIgnoreCase("ConnectionError"):
      let errs = v.split(' ')
      var code = ceCGIInvalidChaControl
      var message = ""
      if errs.len > 1:
        if (let x = parseInt32(errs[1]); x.isSome):
          let n = x.get
          if n > 0 and n <= int32(ConnectionError.high):
            code = ConnectionError(x.get)
        elif (let x = strictParseEnum[ConnectionError](errs[1]);
            x.get(ceNone) != ceNone):
          code = x.get
        if errs.len > 2:
          message &= errs[2]
          for i in 3 ..< errs.len:
            message &= ' '
            message &= errs[i]
      ctx.rejectHandle(handle, code, message)
      return crError
    if v.startsWithIgnoreCase("ControlDone"):
      return crDone
    ctx.rejectHandle(handle, ceCGIInvalidChaControl)
    return crError
  case ctx.sendResult(handle, 0) # success
  of pbrDone: discard
  of pbrUnregister: return crError
  handle.parser.headers.add(k, v)
  return crDone

proc handleControlLine(handle: InputHandle; line: string): ControlResult =
  let k = line.until(':')
  if k.len == line.len:
    # invalid
    return crError
  let v = line.substr(k.len + 1).strip()
  if k.equalsIgnoreCase("Status"):
    let code = parseUInt16(v)
    if v.len > 3 or code.isNone:
      return crError
    handle.parser.status = parseUInt16(v).get(0)
    return crContinue
  if k.equalsIgnoreCase("Cha-Control"):
    if v.startsWithIgnoreCase("ControlDone"):
      return crDone
    return crError
  handle.parser.headers.add(k, v)
  return crDone

proc handleLine(handle: InputHandle; line: string) =
  let k = line.until(':')
  if k.len < line.len:
    let v = line.substr(k.len + 1).strip()
    handle.parser.headers.add(k, v)

proc parseHeaders0(ctx: var LoaderContext; handle: InputHandle;
    data: openArray[char]): int =
  let parser = handle.parser
  for i, c in data:
    template die =
      handle.parser = nil
      return -1
    if parser.crSeen and c != '\n':
      die
    parser.crSeen = false
    if c == '\r':
      parser.crSeen = true
    elif c == '\n':
      if parser.lineBuffer == "":
        if parser.state == hpsBeforeLines:
          # body comes immediately, so we haven't had a chance to send result
          # yet.
          case ctx.sendResult(handle, 0)
          of pbrDone: discard
          of pbrUnregister: die
        let res = ctx.sendStatus(handle, parser.status, parser.headers)
        handle.parser = nil
        return case res
        of pbrDone: i + 1 # +1 to skip \n
        of pbrUnregister: -1
      case parser.state
      of hpsBeforeLines:
        case ctx.handleFirstLine(handle, parser.lineBuffer)
        of crDone: parser.state = hpsControlDone
        of crContinue: parser.state = hpsAfterFirstLine
        of crError: die
      of hpsAfterFirstLine:
        case handle.handleControlLine(parser.lineBuffer)
        of crDone: parser.state = hpsControlDone
        of crContinue: discard
        of crError: die
      of hpsControlDone:
        handle.handleLine(parser.lineBuffer)
      parser.lineBuffer = ""
    else:
      parser.lineBuffer &= c
  return data.len

proc parseHeaders(ctx: var LoaderContext; handle: InputHandle;
    buffer: LoaderBuffer): int =
  if buffer == nil:
    return ctx.parseHeaders0(handle, ['\n'])
  let p = cast[ptr UncheckedArray[char]](addr buffer.page[0])
  return ctx.parseHeaders0(handle, p.toOpenArray(0, buffer.len - 1))

proc finishParse(ctx: var LoaderContext; handle: InputHandle) =
  if handle.cacheRef != nil:
    assert handle.cacheRef.offset == -1
    let ps = newPosixStream(handle.cacheRef.path, O_RDONLY, 0)
    if ps != nil:
      var buffer {.noinit.}: array[4096, char]
      var off = 0i64
      while true:
        let n = ps.readData(buffer)
        if n <= 0:
          assert n == 0 or errno != EBADF
          break
        let pn = ctx.parseHeaders0(handle, buffer.toOpenArray(0, n - 1))
        if pn == -1:
          break
        off += int64(pn)
        if pn < n:
          handle.parser = nil
          break
      handle.cacheRef.offset = off
      ps.sclose()
    handle.cacheRef = nil
  if handle.parser != nil:
    discard ctx.parseHeaders(handle, nil)

type HandleReadResult = enum
  hrrDone, hrrUnregister, hrrBrokenPipe

# Called whenever there is more data available to read.
proc handleRead(ctx: var LoaderContext; handle: InputHandle;
    unregWrite: var seq[OutputHandle]): HandleReadResult =
  var unregs = 0
  let maxUnregs = handle.outputs.len
  while true:
    var buffer = newLoaderBuffer()
    let n = handle.stream.readData(buffer.page)
    if n < 0:
      let e = errno
      if e == EAGAIN or e == EWOULDBLOCK: # retry later
        break
      else: # sender died; stop streaming
        assert e == EPIPE, $strerror(e)
        return hrrBrokenPipe
    if n == 0: # EOF
      return hrrUnregister
    buffer.len = n
    var si = 0
    if handle.parser != nil:
      si = ctx.parseHeaders(handle, buffer)
      if si == -1: # died while parsing headers; unregister
        return hrrUnregister
      if si == n: # parsed the entire buffer as headers; skip output handling
        continue
      if si != 0:
        # Some parts of the buffer have been consumed as headers; others
        # must be passed on to the client.
        # We *could* store si as an offset to the buffer, but it would
        # make things much more complex.  Let's just do this:
        let nlen = buffer.len - si
        let nbuffer = newLoaderBuffer(nlen)
        nbuffer.len = nlen
        copyMem(addr nbuffer.page[0], addr buffer.page[si], nbuffer.len)
        buffer = nbuffer
        assert nbuffer.len != 0, $si & ' ' & $buffer.len & " n " & $n
    else:
      handle.bytesSeen += uint64(n)
      #TODO stop reading if Content-Length exceeded
    for output in handle.outputs:
      if output.dead:
        # do not push to unregWrite candidates
        continue
      case ctx.pushBuffer(output, buffer, ignoreSuspension = false)
      of pbrUnregister:
        output.dead = true
        unregWrite.add(output)
        inc unregs
      of pbrDone: discard
    if unregs == maxUnregs:
      # early return: no more outputs to write to
      break
    if n < buffer.cap:
      break
  hrrDone

# stream is a regular file, so we can't select on it.
#
# cachedHandle is used for attaching the output handle to another
# InputHandle when loadFromCache is called while a download is still
# ongoing (and thus some parts of the document are not cached yet).
proc loadStreamRegular(ctx: var LoaderContext;
    handle, cachedHandle: InputHandle) =
  assert handle.parser == nil # parser is only used with CGI
  var unregWrite: seq[OutputHandle] = @[]
  let r = ctx.handleRead(handle, unregWrite)
  for output in unregWrite:
    output.parent = nil
    let i = handle.outputs.find(output)
    if output.registered:
      ctx.unregister(output)
    handle.outputs.del(i)
  for output in handle.outputs:
    if r == hrrBrokenPipe:
      ctx.oclose(output)
    elif cachedHandle != nil:
      output.parent = cachedHandle
      cachedHandle.outputs.add(output)
    elif output.registered or output.suspended:
      output.parent = nil
      output.istreamAtEnd = true
    else:
      ctx.oclose(output)
  handle.outputs.setLen(0)
  ctx.iclose(handle)

proc findItem(authMap: seq[AuthItem]; origin: Origin): AuthItem =
  for it in authMap:
    if origin.isSameOrigin(it.origin):
      return it
  return nil

proc findAuth(client: ClientHandle; url: URL): AuthItem =
  if client.authMap.len > 0:
    return client.authMap.findItem(url.authOrigin)
  return nil

proc putMappedURL(url: URL; auth: AuthItem) =
  putEnv("MAPPED_URI_SCHEME", url.scheme)
  if auth != nil:
    putEnv("MAPPED_URI_USERNAME", auth.username)
    putEnv("MAPPED_URI_PASSWORD", auth.password)
  else:
    delEnv("MAPPED_URI_USERNAME")
    delEnv("MAPPED_URI_PASSWORD")
  putEnv("MAPPED_URI_HOST", url.hostname)
  putEnv("MAPPED_URI_PORT", url.port)
  putEnv("MAPPED_URI_PATH", url.pathname)
  putEnv("MAPPED_URI_QUERY", url.search.substr(1))

type CGIPath = object
  basename: string
  pathInfo: string
  cmd: string
  scriptName: string
  requestURI: string
  myDir: string

proc setupEnv(cpath: CGIPath; request: Request; contentLen: int; prevURL: URL;
    config: LoaderClientConfig; auth: AuthItem) =
  let url = request.url
  putEnv("SCRIPT_NAME", cpath.scriptName)
  putEnv("SCRIPT_FILENAME", cpath.cmd)
  putEnv("REQUEST_URI", cpath.requestURI)
  putEnv("REQUEST_METHOD", $request.httpMethod)
  var headers = ""
  for k, v in request.headers.allPairs:
    headers &= k & ": " & v & "\r\n"
  putEnv("REQUEST_HEADERS", headers)
  if prevURL != nil:
    putMappedURL(prevURL, auth)
  if cpath.pathInfo != "":
    putEnv("PATH_INFO", cpath.pathInfo)
  if url.search != "":
    putEnv("QUERY_STRING", url.search.substr(1))
  if request.httpMethod == hmPost:
    if request.body.t == rbtMultipart:
      putEnv("CONTENT_TYPE", request.body.multipart.getContentType())
    else:
      putEnv("CONTENT_TYPE", request.headers.getOrDefault("Content-Type", ""))
    putEnv("CONTENT_LENGTH", $contentLen)
  if "Cookie" in request.headers:
    putEnv("HTTP_COOKIE", request.headers["Cookie"])
  if request.referrer != nil:
    putEnv("HTTP_REFERER", $request.referrer)
  if config.proxy != nil:
    putEnv("ALL_PROXY", $config.proxy)
  if config.insecureSslNoVerify:
    putEnv("CHA_INSECURE_SSL_NO_VERIFY", "1")
  setCurrentDir(cpath.myDir)

proc parseCGIPath(ctx: LoaderContext; request: Request): CGIPath =
  var path = percentDecode(request.url.pathname)
  if path.startsWith("/cgi-bin/"):
    path.delete(0 .. "/cgi-bin/".high)
  elif path.startsWith("/$LIB/"):
    path.delete(0 .. "/$LIB/".high)
  var cpath = CGIPath()
  if path == "" or request.url.hostname != "":
    return cpath
  if path[0] == '/':
    for dir in ctx.config.cgiDir:
      if path.startsWith(dir):
        cpath.basename = path.substr(dir.len).until('/')
        cpath.pathInfo = path.substr(dir.len + cpath.basename.len)
        cpath.cmd = dir / cpath.basename
        if not fileExists(cpath.cmd):
          continue
        cpath.myDir = dir
        cpath.scriptName = path.substr(0, dir.len + cpath.basename.len)
        cpath.requestURI = cpath.cmd / cpath.pathInfo & request.url.search
        break
  else:
    cpath.basename = path.until('/')
    cpath.pathInfo = path.substr(cpath.basename.len)
    cpath.scriptName = "/cgi-bin/" & cpath.basename
    cpath.requestURI = "/cgi-bin/" & path & request.url.search
    for dir in ctx.config.cgiDir:
      cpath.cmd = dir / cpath.basename
      if fileExists(cpath.cmd):
        cpath.myDir = dir
        break
  return cpath

proc loadCGI(ctx: var LoaderContext; client: ClientHandle; handle: InputHandle;
    request: Request; prevURL: URL; config: LoaderClientConfig) =
  let cpath = ctx.parseCGIPath(request)
  if cpath.cmd == "" or cpath.basename in ["", ".", ".."] or
      cpath.basename[0] == '~':
    ctx.rejectHandle(handle, ceInvalidCGIPath)
    return
  if not fileExists(cpath.cmd):
    ctx.rejectHandle(handle, ceCGIFileNotFound)
    return
  # Pipe the response body as stdout.
  var pipefd: array[2, cint] # child -> parent
  if pipe(pipefd) == -1:
    ctx.rejectHandle(handle, ceFailedToSetUpCGI)
    return
  let istreamOut = newPosixStream(pipefd[0]) # read by loader
  var ostreamOut = newPosixStream(pipefd[1]) # written by child
  var ostreamOut2: PosixStream = nil
  if request.tocache:
    # Set stdout to a file, and repurpose the pipe as a dummy to detect when
    # the process ends. outputId is the cache id.
    let tmpf = ctx.getTempFile()
    ostreamOut2 = ostreamOut
    # RDWR, otherwise mmap won't work
    ostreamOut = newPosixStream(tmpf, O_CREAT or O_RDWR, 0o600)
    if ostreamOut == nil:
      ctx.rejectHandle(handle, ceCGIFailedToOpenCacheOutput)
      return
    let cacheId = handle.output.outputId # welp
    let item = CachedItem(
      id: cacheId,
      path: tmpf,
      refc: 1,
      offset: -1
    )
    handle.cacheRef = item
    client.cacheMap.add(item)
  # Pipe the request body as stdin for POST.
  var istream: PosixStream = nil # child end (read)
  var ostream: PosixStream = nil # parent end (write)
  var istream2: PosixStream = nil # child end (read) for rbtCache
  var cachedHandle: InputHandle = nil # for rbtCache
  var outputIn: OutputHandle = nil # for rbtOutput
  if request.body.t == rbtCache:
    var n: int
    (istream, n) = client.openCachedItem(request.body.cacheId)
    if istream == nil:
      ctx.rejectHandle(handle, ceCGICachedBodyNotFound)
      return
    cachedHandle = ctx.findCachedHandle(request.body.cacheId)
    if cachedHandle != nil: # cached item still open, switch to streaming mode
      if client.cacheMap[n].offset == -1:
        ctx.rejectHandle(handle, ceCGICachedBodyUnavailable)
        return
      istream2 = istream
  elif request.body.t == rbtOutput:
    outputIn = ctx.findOutput(request.body.outputId, client)
    if outputIn == nil:
      ctx.rejectHandle(handle, ceCGIOutputHandleNotFound)
      return
  if request.body.t in {rbtString, rbtMultipart, rbtOutput} or
      request.body.t == rbtCache and istream2 != nil:
    var pipefdRead: array[2, cint] # parent -> child
    if pipe(pipefdRead) == -1:
      ctx.rejectHandle(handle, ceFailedToSetUpCGI)
      return
    istream = newPosixStream(pipefdRead[0])
    ostream = newPosixStream(pipefdRead[1])
  let contentLen = request.body.contentLength()
  stderr.flushFile()
  let pid = fork()
  if pid == -1:
    ctx.rejectHandle(handle, ceFailedToSetUpCGI)
  elif pid == 0:
    istreamOut.sclose() # close read
    ostreamOut.moveFd(STDOUT_FILENO) # dup stdout
    if ostream != nil:
      ostream.sclose() # close write
    if istream2 != nil:
      istream2.sclose() # close cache file; we aren't reading it directly
    if istream != nil:
      if istream.fd != 0:
        istream.moveFd(STDIN_FILENO) # dup stdin
    else:
      closeStdin()
    let auth = if prevURL != nil: client.findAuth(prevURL) else: nil
    # we leave stderr open, so it can be seen in the browser console
    setupEnv(cpath, request, contentLen, prevURL, config, auth)
    # reset SIGCHLD to the default handler. this is useful if the child process
    # expects SIGCHLD to be untouched. (e.g. git dies a horrible death with
    # SIGCHLD as SIG_IGN)
    signal(SIGCHLD, SIG_DFL)
    # let's also reset SIGPIPE, which we ignored in forkserver
    signal(SIGPIPE, SIG_DFL)
    # close the parent handles
    for i in 0 ..< ctx.handleMap.len:
      if ctx.handleMap[i] != nil:
        discard close(cint(i))
    discard execl(cstring(cpath.cmd), cstring(cpath.basename), nil)
    let code = int(ceFailedToExecuteCGIScript)
    stdout.write("Cha-Control: ConnectionError " & $code & " " &
      ($strerror(errno)).deleteChars({'\n', '\r'}))
    exitnow(1)
  else:
    ostreamOut.sclose() # close write
    if ostreamOut2 != nil:
      ostreamOut2.sclose() # close write
    if request.body.t != rbtNone:
      istream.sclose() # close read
    handle.parser = HeaderParser(headers: newHeaders(hgResponse))
    handle.stream = istreamOut
    case request.body.t
    of rbtString:
      ostream.write(request.body.s)
      ostream.sclose()
    of rbtMultipart:
      let boundary = request.body.multipart.boundary
      for entry in request.body.multipart.entries:
        ostream.writeEntry(entry, boundary)
      ostream.writeEnd(boundary)
      ostream.sclose()
    of rbtOutput:
      ostream.setBlocking(false)
      let output = ctx.tee(outputIn, ostream, client.pid)
      output.suspended = false
      if not output.isEmpty:
        ctx.register(output)
    of rbtCache:
      if ostream != nil:
        let handle = ctx.newInputHandle(ostream, client.pid, suspended = false)
        handle.stream = istream2
        ostream.setBlocking(false)
        ctx.loadStreamRegular(handle, cachedHandle)
        assert handle.stream == nil
        ctx.close(handle)
    of rbtNone:
      discard

func findPassedFd(client: ClientHandle; name: string): int =
  for i in 0 ..< client.passedFdMap.len:
    if client.passedFdMap[i].name == name:
      return i
  return -1

proc loadStream(ctx: var LoaderContext; client: ClientHandle;
    handle: InputHandle; request: Request) =
  let i = client.findPassedFd(request.url.pathname)
  if i == -1:
    ctx.rejectHandle(handle, ceFileNotFound, "stream not found")
    return
  case ctx.sendResult(handle, 0)
  of pbrDone: discard
  of pbrUnregister: return
  case ctx.sendStatus(handle, 200, newHeaders(hgResponse))
  of pbrDone: discard
  of pbrUnregister: return
  let ps = client.passedFdMap[i].ps
  var stats: Stat
  doAssert fstat(ps.fd, stats) != -1
  handle.stream = ps
  client.passedFdMap.del(i)
  if S_ISCHR(stats.st_mode) or S_ISREG(stats.st_mode):
    # regular file: e.g. cha <file
    # or character device: e.g. cha </dev/null
    handle.output.stream.setBlocking(false)
    # not loading from cache, so cachedHandle is nil
    ctx.loadStreamRegular(handle, nil)

proc loadFromCache(ctx: var LoaderContext; client: ClientHandle;
    handle: InputHandle; request: Request) =
  let id = parseInt32(request.url.pathname).get(-1)
  let startFrom = parseInt64(request.url.search.substr(1)).get(0)
  let (ps, n) = client.openCachedItem(id)
  if ps != nil:
    if startFrom != 0:
      discard ps.seek(startFrom)
    handle.stream = ps
    if ps == nil:
      ctx.rejectHandle(handle, ceFileNotInCache)
      client.cacheMap.del(n)
      return
    case ctx.sendResult(handle, 0)
    of pbrDone: discard
    of pbrUnregister:
      client.cacheMap.del(n)
      ctx.close(handle)
      return
    case ctx.sendStatus(handle, 200, newHeaders(hgResponse))
    of pbrDone: discard
    of pbrUnregister:
      client.cacheMap.del(n)
      ctx.close(handle)
      return
    handle.output.stream.setBlocking(false)
    let cachedHandle = ctx.findCachedHandle(id)
    ctx.loadStreamRegular(handle, cachedHandle)
  else:
    ctx.rejectHandle(handle, ceURLNotInCache)

# Data URL handler.
# Moved back into loader from CGI, because data URLs can get extremely long
# and thus no longer fit into the environment.
proc loadDataSend(ctx: var LoaderContext; handle: InputHandle; s, ct: string) =
  case ctx.sendResult(handle, 0)
  of pbrDone: discard
  of pbrUnregister:
    ctx.close(handle)
    return
  case ctx.sendStatus(handle, 200, newHeaders(hgResponse, {"Content-Type": ct}))
  of pbrDone: discard
  of pbrUnregister:
    ctx.close(handle)
    return
  let output = handle.output
  if s.len == 0:
    if output.suspended:
      output.istreamAtEnd = true
    else:
      ctx.oclose(output)
    return
  let buffer = newLoaderBuffer(s.len)
  buffer.len = s.len
  copyMem(addr buffer.page[0], unsafeAddr s[0], s.len)
  case ctx.pushBuffer(output, buffer, ignoreSuspension = false)
  of pbrUnregister:
    if output.registered:
      ctx.unregister(output)
    ctx.oclose(output)
  of pbrDone:
    if output.registered or output.suspended:
      output.istreamAtEnd = true
    else:
      ctx.oclose(output)

proc loadData(ctx: var LoaderContext; handle: InputHandle; request: Request) =
  let url = request.url
  var ct = url.pathname.until(',')
  if AllChars - Ascii + Controls - {'\t'} in ct:
    ctx.rejectHandle(handle, ceInvalidURL, "invalid data URL")
    return
  let sd = ct.len + 1 # data start
  let body = percentDecode(url.pathname.toOpenArray(sd, url.pathname.high))
  if ct.endsWith(";base64"):
    var d: string
    if d.atob(body).isNone:
      ctx.rejectHandle(handle, ceInvalidURL, "invalid data URL")
      return
    ct.setLen(ct.len - ";base64".len) # remove base64 indicator
    ctx.loadDataSend(handle, d, ct)
  else:
    ctx.loadDataSend(handle, body, ct)

# Download manager. Based on (you guessed it) w3m.
func formatSize(size: uint64): string =
  result = ""
  var size = size
  while size > 0:
    let n = size mod 1000
    size = size div 1000
    var ns = ""
    if size != 0:
      ns &= ','
      if n < 100:
        ns &= '0'
      if n < 10:
        ns &= '0'
    ns &= $n
    result.insert(ns, 0)

proc formatDuration(dur: Duration): string =
  result = ""
  let parts = dur.toParts()
  if parts[Weeks] != 0:
    result &= $parts[Weeks] & " Weeks, "
  if parts[Days] != 0:
    result &= $parts[Days] & " Days, "
  for i, it in [Hours, Minutes, Seconds]:
    if i > 0:
      result &= ':'
    if parts[it] in 0..9:
      result &= '0'
    result &= $parts[it]

proc makeProgress(it: DownloadItem; now: Time): string =
  result = it.displayUrl.htmlEscape() & '\n'
  result &= "  -> " & it.path & '\n'
  result &= "  "
  #TODO implement progress element and use that
  var rat = 0u64
  if it.contentLen == uint64.high and it.sent > 0 and it.output == nil:
    rat = 80
  elif it.contentLen < uint64.high and it.contentLen > 0:
    rat = it.sent * 80 div it.contentLen
  for i in 0 ..< rat:
    result &= '#'
  for i in rat ..< 80:
    result &= '_'
  result &= "\n  "
  result &= formatSize(it.sent)
  if it.sent < it.contentLen and
      (it.contentLen < uint64.high or it.output != nil):
    if it.contentLen < uint64.high and it.contentLen > 0:
      result &= " / " & formatSize(it.contentLen) & " bytes (" &
        $(it.sent * 100 div it.contentLen) & "%)  "
    else:
      result &= " bytes loaded  "
    let dur = now - it.startTime
    result &= formatDuration(dur)
    result &= "  rate "
    let udur = max(uint64(dur.inSeconds()), 1)
    let rate = it.sent div udur
    result &= convertSize(int(rate)) & "/sec"
    if it.contentLen < uint64.high:
      let left = it.contentLen - it.sent
      let eta = initDuration(seconds = int64(left div max(rate, 1)))
      result &= "  eta " & formatDuration(eta)
  else:
    result &= " bytes loaded"
  result &= '\n'

type
  DownloadActionType = enum
    datRemove

  DownloadAction = object
    n: int
    t: DownloadActionType

proc parseDownloadActions(ctx: LoaderContext; s: string): seq[DownloadAction] =
  result = @[]
  for it in s.split('&'):
    let name = it.until('=')
    if name.startsWith("stop"):
      let n = parseIntP(name.substr("stop".len)).get(-1)
      if n >= 0 and n < ctx.downloadList.len:
        result.add(DownloadAction(n: n, t: datRemove))
  result.sort(proc(a, b: DownloadAction): int = return cmp(a.n, b.n),
    Descending)

proc loadAbout(ctx: var LoaderContext; handle: InputHandle; request: Request) =
  let url = request.url
  case url.pathname
  of "blank":
    ctx.loadDataSend(handle, "", "text/html")
  of "chawan":
    const body = staticRead"res/chawan.html"
    ctx.loadDataSend(handle, body, "text/html")
  of "downloads":
    if request.httpMethod == hmPost:
      # OK/STOP/PAUSE/RESUME clicked
      if request.body.t != rbtString:
        ctx.rejectHandle(handle, ceInvalidURL, "wat")
        return
      for it in ctx.parseDownloadActions(request.body.s):
        let dl = ctx.downloadList[it.n]
        if dl.output != nil:
          ctx.unregWrite.add(dl.output)
        ctx.downloadList.del(it.n)
    var body = """
<!DOCTYPE html>
<title>Download List Panel</title>
<body>
<h1 align=center>Download List Panel</h1>
<hr>
<form method=POST action=about:downloads>
<hr>
<pre>
"""
    let now = getTime()
    var refresh = false
    for i, it in ctx.downloadList.mpairs:
      if it.output != nil:
        it.sent = it.output.bytesSent
        if it.output.stream == nil:
          it.output = nil
        refresh = true
      body &= it.makeProgress(now)
      body &= "<input type=submit name=stop" & $i
      if it.output != nil:
        body &= " value=STOP"
      else:
        body &= " value=OK"
      body &= ">"
      body &= "<hr>"
    if refresh:
      body &= "<meta http-equiv=refresh content=1>" # :P
    body &= """
</pre>
</body>
"""
    ctx.loadDataSend(handle, body, "text/html")
  of "license":
    const body = staticRead"res/license.md"
    ctx.loadDataSend(handle, body, "text/markdown")
  else:
    ctx.rejectHandle(handle, ceInvalidURL, "invalid download URL")

proc loadResource(ctx: var LoaderContext; client: ClientHandle;
    config: LoaderClientConfig; request: Request; handle: InputHandle) =
  var redo = true
  var tries = 0
  var prevurl: URL = nil
  while redo and tries < MaxRewrites:
    redo = false
    if ctx.config.w3mCGICompat and request.url.scheme == "file":
      let path = request.url.pathname.percentDecode()
      if ctx.canRewriteForCGICompat(path):
        let newURL = newURL("cgi-bin:" & path & request.url.search)
        if newURL.isSome:
          request.url = newURL.get
          inc tries
          redo = true
          continue
    case request.url.scheme
    of "cgi-bin":
      ctx.loadCGI(client, handle, request, prevurl, config)
      if handle.stream != nil:
        ctx.addFd(handle)
      else:
        ctx.close(handle)
    of "stream":
      ctx.loadStream(client, handle, request)
      if handle.stream != nil:
        ctx.addFd(handle)
      else:
        ctx.close(handle)
    of "cache":
      ctx.loadFromCache(client, handle, request)
      assert handle.stream == nil
    of "data":
      ctx.loadData(handle, request)
    of "about":
      ctx.loadAbout(handle, request)
    else:
      prevurl = request.url
      case ctx.config.uriMethodMap.findAndRewrite(request.url)
      of ummrSuccess:
        inc tries
        redo = true
      of ummrWrongURL:
        ctx.rejectHandle(handle, ceInvalidURIMethodEntry)
      of ummrNotFound:
        ctx.rejectHandle(handle, ceUnknownScheme)
  if tries >= MaxRewrites:
    ctx.rejectHandle(handle, ceTooManyRewrites)

proc setupRequestDefaults(request: Request; config: LoaderClientConfig) =
  for k, v in config.defaultHeaders.allPairs:
    if k notin request.headers:
      request.headers[k] = v
  if config.cookieJar != nil and config.cookieJar.cookies.len > 0:
    if "Cookie" notin request.headers:
      let cookie = config.cookieJar.serialize(request.url)
      if cookie != "":
        request.headers["Cookie"] = cookie
  if request.referrer != nil and "Referer" notin request.headers:
    let r = request.referrer.getReferrer(request.url, config.referrerPolicy)
    if r != "":
      request.headers["Referer"] = r

proc load(ctx: var LoaderContext; stream: SocketStream; request: Request;
    client: ClientHandle; config: LoaderClientConfig) =
  var sv {.noinit.}: array[2, cint]
  var fail = false
  stream.withPacketWriter w:
    if socketpair(AF_UNIX, SOCK_STREAM, IPPROTO_IP, sv) == 0:
      w.swrite(true)
      w.sendFd(sv[1])
    else:
      fail = true
      w.swrite(false)
  if not fail:
    discard close(sv[1])
    let stream = newSocketStream(sv[0])
    stream.setBlocking(false)
    let handle = ctx.newInputHandle(stream, client.pid)
    when defined(debug):
      handle.url = request.url
      handle.output.url = request.url
    if not config.filter.match(request.url):
      ctx.rejectHandle(handle, ceDisallowedURL)
    else:
      request.setupRequestDefaults(config)
      ctx.loadResource(client, config, request, handle)

proc load(ctx: var LoaderContext; stream: SocketStream; client: ClientHandle;
    r: var PacketReader) =
  var request: Request
  r.sread(request)
  ctx.load(stream, request, client, client.config)

proc loadConfig(ctx: var LoaderContext; stream: SocketStream;
    client: ClientHandle; r: var PacketReader) =
  var request: Request
  var config: LoaderClientConfig
  r.sread(request)
  r.sread(config)
  ctx.load(stream, request, client, config)

proc getCacheFile(ctx: var LoaderContext; stream: SocketStream;
    r: var PacketReader) =
  var cacheId: int
  var sourcePid: int
  r.sread(cacheId)
  r.sread(sourcePid)
  let client = ctx.clientMap.getOrDefault(sourcePid, nil)
  let n = if client != nil: client.cacheMap.find(cacheId) else: -1
  stream.withPacketWriter w:
    if n != -1:
      w.swrite(client.cacheMap[n].path)
    else:
      w.swrite("")

proc addClient(ctx: var LoaderContext; stream: SocketStream;
    r: var PacketReader) =
  var pid: int
  var config: LoaderClientConfig
  var clonedFrom: int
  r.sread(pid)
  r.sread(config)
  r.sread(clonedFrom)
  assert pid notin ctx.clientMap
  var sv {.noinit.}: array[2, cint]
  stream.withPacketWriter w:
    if socketpair(AF_UNIX, SOCK_STREAM, IPPROTO_IP, sv) == 0:
      let stream = newSocketStream(sv[0])
      let client = ClientHandle(stream: stream, pid: pid, config: config)
      ctx.register(client)
      ctx.put(client)
      if clonedFrom != -1:
        let client2 = ctx.clientMap[clonedFrom]
        for item in client2.cacheMap:
          inc item.refc
        client.cacheMap = client2.cacheMap
      if ctx.authMap.len > 0:
        let origin = config.originURL.authOrigin
        for it in ctx.authMap:
          if it.origin.isSameOrigin(origin):
            client.authMap.add(it)
      w.swrite(true)
      w.sendFd(sv[1])
    else:
      w.swrite(false)
  discard close(sv[1])

proc removeClient(ctx: var LoaderContext; stream: SocketStream;
    r: var PacketReader) =
  var pid: int
  r.sread(pid)
  if pid in ctx.clientMap:
    let client = ctx.clientMap[pid]
    ctx.unregClient.add(client)

proc addCacheFile(ctx: var LoaderContext; stream: SocketStream;
    client: ClientHandle; r: var PacketReader) =
  var outputId: int
  var targetPid: int
  r.sread(outputId)
  #TODO get rid of targetPid
  r.sread(targetPid)
  doAssert ctx.isPrivileged(client) or client.pid == targetPid
  let output = ctx.findOutput(outputId, client)
  assert output != nil
  let targetClient = ctx.clientMap[targetPid]
  let id = ctx.addCacheFile(targetClient, output)
  stream.withPacketWriter w:
    w.swrite(id)

proc redirectToFile(ctx: var LoaderContext; stream: SocketStream;
    client: ClientHandle; r: var PacketReader) =
  var outputId: int
  var targetPath: string
  var displayUrl: string
  r.sread(outputId)
  r.sread(targetPath)
  r.sread(displayUrl)
  let output = ctx.findOutput(outputId, client)
  var success = false
  if output != nil:
    var fileOutput: OutputHandle
    var sent: uint64
    success = ctx.redirectToFile(output, targetPath, fileOutput, sent)
    let contentLen = if output.parent != nil:
      output.parent.contentLen
    else:
      uint64.high
    let startTime = if output.parent != nil:
      output.parent.startTime
    else:
      #TODO ???
      fromUnix(0)
    ctx.downloadList.add(DownloadItem(
      path: targetPath,
      output: fileOutput,
      displayUrl: displayUrl,
      sent: sent,
      contentLen: contentLen,
      startTime: startTime
    ))
  stream.withPacketWriter w:
    w.swrite(success)

proc shareCachedItem(ctx: var LoaderContext; stream: SocketStream;
    r: var PacketReader) =
  # share a cached file with another buffer. this is for newBufferFrom
  # (i.e. view source)
  var sourcePid: int # pid of source client
  var targetPid: int # pid of target client
  var id: int
  r.sread(sourcePid)
  r.sread(targetPid)
  r.sread(id)
  let sourceClient = ctx.clientMap[sourcePid]
  let targetClient = ctx.clientMap[targetPid]
  let n = sourceClient.cacheMap.find(id)
  if n != -1:
    let item = sourceClient.cacheMap[n]
    inc item.refc
    targetClient.cacheMap.add(item)
  stream.withPacketWriter w:
    w.swrite(n != -1)

proc openCachedItem(ctx: LoaderContext; stream: SocketStream;
    client: ClientHandle; r: var PacketReader) =
  # open a cached item
  var id: int
  r.sread(id)
  let (ps, _) = client.openCachedItem(id)
  stream.withPacketWriter w:
    w.swrite(ps != nil)
    if ps != nil:
      w.sendFd(ps.fd)
  if ps != nil:
    ps.sclose()

proc passFd(ctx: var LoaderContext; stream: SocketStream; client: ClientHandle;
    r: var PacketReader) =
  var id: string
  r.sread(id)
  let fd = r.recvFd()
  #TODO cloexec?
  client.passedFdMap.add((id, newPosixStream(fd)))

proc addPipe(ctx: var LoaderContext; stream: SocketStream; client: ClientHandle;
    r: var PacketReader) =
  var id: string
  r.sread(id)
  var pipefd {.noinit.}: array[2, cint]
  if pipe(pipefd) == -1:
    stream.withPacketWriter w:
      w.swrite(false)
  else:
    stream.withPacketWriter w:
      w.swrite(true)
      w.sendFd(pipefd[1])
    discard close(pipefd[1])
    let ps = newPosixStream(pipefd[0])
    ps.setCloseOnExec()
    client.passedFdMap.add((id, ps))

proc removeCachedItem(ctx: var LoaderContext; stream: SocketStream;
    client: ClientHandle; r: var PacketReader) =
  var id: int
  r.sread(id)
  let n = client.cacheMap.find(id)
  if n != -1:
    let item = client.cacheMap[n]
    client.cacheMap.del(n)
    dec item.refc
    if item.refc == 0:
      discard unlink(cstring(item.path))

proc tee(ctx: var LoaderContext; stream: SocketStream; client: ClientHandle;
    r: var PacketReader) =
  var sourceId: int
  var targetPid: int
  r.sread(sourceId)
  r.sread(targetPid)
  let outputIn = ctx.findOutput(sourceId, client)
  var sv {.noinit.}: array[2, cint]
  if outputIn != nil and socketpair(AF_UNIX, SOCK_STREAM, IPPROTO_IP, sv) == 0:
    let ostream = newSocketStream(sv[0])
    ostream.setBlocking(false)
    let output = ctx.tee(outputIn, ostream, targetPid)
    stream.withPacketWriter w:
      w.swrite(output.outputId)
      w.sendFd(sv[1])
    discard close(sv[1])
  else:
    stream.withPacketWriter w:
      w.swrite(-1)

proc addAuth(ctx: var LoaderContext; stream: SocketStream;
    r: var PacketReader) =
  var url: URL
  r.sread(url)
  let origin = url.authOrigin
  let item = ctx.authMap.findItem(origin)
  if item != nil:
    item.username = url.username
    item.password = url.password
  else:
    let item = AuthItem(
      origin: url.authOrigin,
      username: url.username,
      password: url.password
    )
    ctx.authMap.add(item)
    ctx.pagerClient.authMap.add(item)

proc suspend(ctx: var LoaderContext; stream: SocketStream; client: ClientHandle;
    r: var PacketReader) =
  var ids: seq[int]
  r.sread(ids)
  for id in ids:
    let output = ctx.findOutput(id, client)
    if output != nil:
      output.suspended = true
      if output.registered:
        # do not waste cycles trying to push into output
        ctx.unregister(output)

proc resume(ctx: var LoaderContext; stream: SocketStream; client: ClientHandle;
    r: var PacketReader) =
  var ids: seq[int]
  r.sread(ids)
  for id in ids:
    let output = ctx.findOutput(id, client)
    if output != nil:
      output.suspended = false
      if not output.isEmpty or output.istreamAtEnd:
        ctx.register(output)

proc readCommand(ctx: var LoaderContext; client: ClientHandle) =
  let stream = SocketStream(client.stream)
  try:
    assert not client.stream.isend
    stream.withPacketReader r:
      var cmd: LoaderCommand
      r.sread(cmd)
      template privileged_command =
        doAssert ctx.isPrivileged(client)
      case cmd
      of lcAddClient:
        privileged_command
        ctx.addClient(stream, r)
      of lcAddAuth:
        privileged_command
        ctx.addAuth(stream, r)
      of lcRemoveClient:
        privileged_command
        ctx.removeClient(stream, r)
      of lcShareCachedItem:
        privileged_command
        ctx.shareCachedItem(stream, r)
      of lcOpenCachedItem:
        privileged_command
        ctx.openCachedItem(stream, client, r)
      of lcRedirectToFile:
        privileged_command
        ctx.redirectToFile(stream, client, r)
      of lcLoadConfig:
        privileged_command
        ctx.loadConfig(stream, client, r)
      of lcGetCacheFile:
        privileged_command
        ctx.getCacheFile(stream, r)
      of lcPassFd:
        privileged_command
        ctx.passFd(stream, client, r)
      of lcAddCacheFile:
        ctx.addCacheFile(stream, client, r)
      of lcRemoveCachedItem:
        ctx.removeCachedItem(stream, client, r)
      of lcAddPipe:
        ctx.addPipe(stream, client, r)
      of lcLoad:
        ctx.load(stream, client, r)
      of lcTee:
        ctx.tee(stream, client, r)
      of lcSuspend:
        ctx.suspend(stream, client, r)
      of lcResume:
        ctx.resume(stream, client, r)
      assert r.empty()
  except EOFError:
    # Receiving end died while reading, or sent less bytes than they
    # promised.  Give up.
    ctx.unregClient.add(client)

proc exitLoader(ctx: LoaderContext) =
  for it in ctx.handleMap:
    if it of ClientHandle:
      let client = ClientHandle(it)
      for it in client.cacheMap:
        dec it.refc
        if it.refc <= 0:
          discard unlink(cstring(it.path))
  exitnow(1)

# This is only called when an OutputHandle could not read enough of one (or
# more) buffers, and we asked select to notify us when it will be available.
proc handleWrite(ctx: var LoaderContext; output: OutputHandle;
    unregWrite: var seq[OutputHandle]) =
  while output.currentBuffer != nil:
    let buffer = output.currentBuffer
    let n = output.stream.writeData(buffer, output.currentBufferIdx)
    if n < 0:
      let e = errno
      if e == EAGAIN or e == EWOULDBLOCK: # never mind
        break
      else: # receiver died; stop streaming
        assert e == EPIPE, $strerror(e)
        unregWrite.add(output)
        break
    output.bytesSent += uint64(n)
    output.currentBufferIdx += n
    if output.currentBufferIdx < buffer.len:
      break
    output.bufferCleared() # swap out buffer
  if output.isEmpty:
    if output.istreamAtEnd:
      # after EOF, no need to send anything more here
      unregWrite.add(output)
    else:
      # all buffers sent, no need to select on this output again for now
      ctx.unregister(output)

proc finishCycle(ctx: var LoaderContext) =
  # Unregister handles queued for unregistration.
  # It is possible for both unregRead and unregWrite to contain duplicates. To
  # avoid double-close/double-unregister, we set the istream/ostream of
  # unregistered handles to nil.
  for handle in ctx.unregRead:
    if handle.stream != nil:
      ctx.unregister(handle)
      if handle.parser != nil:
        ctx.finishParse(handle)
      ctx.iclose(handle)
      for output in handle.outputs:
        output.istreamAtEnd = true
        if output.isEmpty:
          ctx.unregWrite.add(output)
  for output in ctx.unregWrite:
    if output.stream != nil:
      if output.registered:
        ctx.unregister(output)
      ctx.oclose(output)
      let handle = output.parent
      if handle != nil: # may be nil if from loadStream S_ISREG
        let i = handle.outputs.find(output)
        handle.outputs.del(i)
        if handle.outputs.len == 0 and handle.stream != nil:
          # premature end of all output streams; kill istream too
          ctx.unregister(handle)
          if handle.parser != nil:
            ctx.finishParse(handle)
          ctx.iclose(handle)
  for client in ctx.unregClient:
    if client.stream != nil:
      # Do it in this exact order, or the cleanup procedure will have
      # trouble finding all clients if we got interrupted in this loop.
      ctx.unregister(client)
      let fd = int(client.stream.fd)
      ctx.close(client)
      if fd < ctx.handleMap.len:
        ctx.handleMap[fd] = nil
  ctx.unregRead.setLen(0)
  ctx.unregWrite.setLen(0)
  ctx.unregClient.setLen(0)

proc loaderLoop(ctx: var LoaderContext) =
  while true:
    ctx.pollData.poll(-1)
    for event in ctx.pollData.events:
      let efd = int(event.fd)
      if (event.revents and POLLIN) != 0:
        let handle = ctx.handleMap[efd]
        if handle of ClientHandle:
          ctx.readCommand(ClientHandle(handle))
        else:
          let handle = InputHandle(handle)
          case ctx.handleRead(handle, ctx.unregWrite)
          of hrrDone: discard
          of hrrUnregister, hrrBrokenPipe: ctx.unregRead.add(handle)
      if (event.revents and POLLOUT) != 0:
        let handle = ctx.handleMap[efd]
        ctx.handleWrite(OutputHandle(handle), ctx.unregWrite)
      if (event.revents and POLLERR) != 0 or (event.revents and POLLHUP) != 0:
        let handle = ctx.handleMap[efd]
        if handle of InputHandle: # istream died
          ctx.unregRead.add(InputHandle(handle))
        elif handle of OutputHandle: # ostream died
          ctx.unregWrite.add(OutputHandle(handle))
        else: # client died
          assert handle of ClientHandle
          ctx.unregClient.add(ClientHandle(handle))
    ctx.finishCycle()
  ctx.exitLoader()

proc runFileLoader*(config: LoaderConfig; stream: SocketStream) =
  var ctx {.global.}: LoaderContext
  ctx = LoaderContext(
    config: config,
    pid: getCurrentProcessId()
  )
  onSignal SIGTERM:
    discard sig
    ctx.exitLoader()
  for dir in ctx.config.cgiDir.mitems:
    if dir.len > 0 and dir[^1] != '/':
      dir &= '/'
  stream.withPacketReader r:
    var cmd: LoaderCommand
    r.sread(cmd)
    doAssert cmd == lcAddClient
    var pid: int
    var config: LoaderClientConfig
    r.sread(pid)
    r.sread(config)
    stream.withPacketWriter w:
      w.swrite(true)
    ctx.pagerClient = ClientHandle(stream: stream, pid: pid, config: config)
  ctx.register(ctx.pagerClient)
  ctx.put(ctx.pagerClient)
  # for CGI
  putEnv("SERVER_SOFTWARE", "Chawan")
  putEnv("SERVER_PROTOCOL", "HTTP/1.0")
  putEnv("SERVER_NAME", "localhost")
  putEnv("SERVER_PORT", "80")
  putEnv("REMOTE_HOST", "localhost")
  putEnv("REMOTE_ADDR", "127.0.0.1")
  putEnv("GATEWAY_INTERFACE", "CGI/1.1")
  putEnv("CHA_INSECURE_SSL_NO_VERIFY", "0")
  putEnv("CHA_TMP_DIR", config.tmpdir)
  putEnv("CHA_DIR", config.configdir)
  putEnv("CHA_BOOKMARK", config.bookmark)
  ctx.loaderLoop()
