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

{.push raises: [].}

import std/algorithm
import std/os
import std/posix
import std/strutils
import std/tables
import std/times

import config/config
import config/conftypes
import config/cookie
import config/urimethodmap
import html/script
import io/dynstream
import io/packetreader
import io/packetwriter
import io/poll
import server/connectionerror
import server/headers
import server/loaderiface
import server/request
import types/formdata
import types/opt
import types/url
import utils/myposix
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

  LoaderBuffer {.acyclic.} = ref object
    len: int
    page: seq[uint8]
    next: LoaderBuffer

  LoaderHandle = ref object of RootObj
    registered: bool # track registered state
    stream: PosixStream # input/output stream depending on type
    url: URL # URL nominally retrieved by handle before rewrites

  InputHandle = ref object of LoaderHandle
    outputs: seq[OutputHandle] # list of outputs to be streamed into
    cacheId: int # if cached, our ID in a client cacheMap
    cacheRef: CachedItem # if this is a tocache handle, a ref to our cache item
    parser: HeaderParser # only exists for CGI handles
    rstate: ResponseState # track response state
    credentials: bool # normalized to "include" (true) or "omit" (false)
    contentLen: uint64 # value of Content-Length; uint64.high if no such header
    bytesSeen: uint64 # number of bytes read until now
    startTime: Time # time when download of the body was started
    connectionOwner: ClientHandle # set if the handle counts in numConnections
    lastBuffer: LoaderBuffer # tail of buffer linked list

  OutputHandle = ref object of LoaderHandle
    parent: InputHandle
    currentBuffer: LoaderBuffer
    currentBufferIdx: int
    owner: ClientHandle
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
    # Number of ongoing requests in this client.
    numConnections: int
    # Requests that will only be sent once n no longer exceeds
    # maxNetConnections.
    pending: seq[(InputHandle, Request, URL)]

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
    forkStream: SocketStream # handle to the fork server
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
    cookieStream: InputHandle
    pendingConnections: seq[ClientHandle]

  LoaderConfig* = object
    cgiDir*: seq[string]
    uriMethodMap*: URIMethodMap
    w3mCGICompat*: bool
    tmpdir*: string
    configdir*: string
    bookmark*: string
    maxNetConnections*: int

  PushBufferResult = enum
    pbrDone, pbrUnregister

  CommandResult = enum
    cmdrDone, cmdrEOF

# Forward declarations
proc loadCGI(ctx: var LoaderContext; client: ClientHandle; handle: InputHandle;
  request: Request; prevURL: URL; config: LoaderClientConfig)
proc pushBuffer(ctx: var LoaderContext; handle: InputHandle;
  buffer: LoaderBuffer; ignoreSuspension: bool;
  unregWrite: var seq[OutputHandle])

proc `$`*(buffer: LoaderBuffer): string {.deprecated: "for debugging only".} =
  var s = newString(buffer.len)
  copyMem(addr s[0], addr buffer.page[0], buffer.len)
  return s

template withPacketWriter(client: ClientHandle; w, body, fallback: untyped) =
  client.stream.withPacketWriter w:
    body
  do:
    fallback

template withPacketWriterReturnEOF(client: ClientHandle; w, body: untyped) =
  client.withPacketWriter w:
    body
  do:
    return cmdrEOF

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
proc newInputHandle(ctx: var LoaderContext; ostream: PosixStream;
    owner: ClientHandle; url: URL; credentials: bool; suspended = true):
    InputHandle =
  let handle = InputHandle(
    cacheId: -1,
    contentLen: uint64.high,
    url: url,
    credentials: credentials
  )
  let output = OutputHandle(
    stream: ostream,
    parent: handle,
    outputId: ctx.getOutputId(),
    owner: owner,
    url: url,
    suspended: suspended
  )
  ctx.put(output)
  handle.outputs.add(output)
  return handle

proc cap(buffer: LoaderBuffer): int {.inline.} =
  return LoaderBufferPageSize

template isEmpty(output: OutputHandle): bool =
  output.currentBuffer == nil and not output.suspended

proc newLoaderBuffer(size = LoaderBufferPageSize): LoaderBuffer =
  return LoaderBuffer(page: newSeqUninit[uint8](size))

proc newLoaderBuffer(s: openArray[char]): LoaderBuffer =
  let buffer = newLoaderBuffer(s.len)
  buffer.len = s.len
  copyMem(addr buffer.page[0], unsafeAddr s[0], s.len)
  buffer

proc tee(ctx: var LoaderContext; outputIn: OutputHandle; ostream: PosixStream;
    owner: ClientHandle): OutputHandle =
  assert outputIn.suspended
  let output = OutputHandle(
    parent: outputIn.parent,
    stream: ostream,
    currentBuffer: outputIn.currentBuffer,
    currentBufferIdx: outputIn.currentBufferIdx,
    istreamAtEnd: outputIn.istreamAtEnd,
    outputId: ctx.getOutputId(),
    owner: owner,
    suspended: outputIn.suspended,
    url: outputIn.url
  )
  ctx.put(output)
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
  var unregWrite: seq[OutputHandle] = @[]
  ctx.pushBuffer(handle, buffer, ignoreSuspension = true, unregWrite)
  if unregWrite.len > 0:
    return pbrUnregister
  pbrDone

proc updateCookies(ctx: var LoaderContext; cookieJar: CookieJar;
    url: URL; owner: ClientHandle; values: openArray[string]) =
  # Syntax: {jarId} RS {url} RS {persist?} RS {header} [ CR {header} ... ] LF
  # Persist is ASCII digit 0 if persist, 1 if not.
  const RS = '\x1E' # ASCII record separator
  let persist = if owner.config.cookieMode == cmSave: '1' else: '0'
  var s = cookieJar.name & RS & $url & RS & persist & RS
  for i, it in values.mypairs:
    s &= it & [false: '\r', true: '\n'][i == values.high]
  let buffer = newLoaderBuffer(s)
  ctx.pushBuffer(ctx.cookieStream, buffer, ignoreSuspension = false,
    ctx.unregWrite)
  if ctx.cookieStream.output.dead:
    ctx.cookieStream = nil

proc sendStatus(ctx: var LoaderContext; handle: InputHandle; status: uint16;
    headers: Headers): PushBufferResult =
  assert handle.rstate == rsBeforeStatus
  inc handle.rstate
  let contentLens = headers.getFirst("Content-Length")
  handle.startTime = getTime()
  handle.contentLen = parseUInt64(contentLens).get(uint64.high)
  let output = handle.output
  let cookieJar = output.owner.config.cookieJar
  if cookieJar != nil and handle.credentials:
    # Never persist in loader; we save cookies in the pager.
    let values = headers.getAllNoComma("Set-Cookie")
    if values.len > 0:
      cookieJar.setCookie(values, handle.url, persist = false)
      if ctx.cookieStream != nil:
        ctx.updateCookies(cookieJar, handle.url, output.owner, values)
  let buffer = bufferFromWriter w:
    w.swrite(status)
    w.swrite(headers)
  var unregWrite: seq[OutputHandle] = @[]
  ctx.pushBuffer(handle, buffer, ignoreSuspension = true, unregWrite)
  if unregWrite.len > 0:
    return pbrUnregister
  pbrDone

proc writeData(ps: PosixStream; buffer: LoaderBuffer; si = 0): int {.inline.} =
  let len = buffer.len - si
  if len == 0:
    # Warning: this can happen when using partially cached handles.
    return 0
  assert len > 0
  return ps.writeData(addr buffer.page[si], len)

proc iclose(ctx: var LoaderContext; handle: InputHandle) =
  if handle.stream != nil:
    ctx.unset(handle)
    handle.stream.sclose()
    handle.stream = nil
  let client = handle.connectionOwner
  if client != nil:
    if client.numConnections == ctx.config.maxNetConnections and
        client.pending.len > 0:
      ctx.pendingConnections.add(client)
    dec client.numConnections
    handle.connectionOwner = nil

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

proc isPrivileged(ctx: LoaderContext; client: ClientHandle): bool =
  return ctx.pagerClient == client

#TODO this may be too low if we want to use urimethodmap for everything
const MaxRewrites = 4

proc canRewriteForCGICompat(ctx: LoaderContext; path: string): bool =
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

proc findOutput(ctx: var LoaderContext; id: int;
    client: ClientHandle): OutputHandle =
  assert id != -1
  for it in ctx.outputHandles:
    if it.outputId == id:
      # verify that it's safe to access this handle.
      doAssert ctx.isPrivileged(client) or client == it.owner
      return it
  return nil

proc findCachedHandle(ctx: LoaderContext; cacheId: int): InputHandle =
  assert cacheId != -1
  for it in ctx.inputHandles:
    if it.cacheId == cacheId:
      return it
  return nil

proc find(cacheMap: openArray[CachedItem]; id: int): int =
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
proc pushBuffer(ctx: var LoaderContext; handle: InputHandle;
    buffer: LoaderBuffer; ignoreSuspension: bool;
    unregWrite: var seq[OutputHandle]) =
  if handle.lastBuffer == nil:
    handle.lastBuffer = buffer
  else:
    handle.lastBuffer.next = buffer
    handle.lastBuffer = buffer
  for output in handle.outputs:
    if output.dead:
      # do not push to unregWrite candidates
      continue
    if output.currentBuffer == nil:
      if output.suspended and not ignoreSuspension:
        output.currentBuffer = buffer
        output.currentBufferIdx = 0
      else:
        var n = output.stream.writeData(buffer)
        if n < 0:
          let e = errno
          if e == EAGAIN or e == EWOULDBLOCK or e == EINTR:
            n = 0
          else:
            assert e == EPIPE, $strerror(e)
            output.dead = true
            unregWrite.add(output)
            continue
        else:
          output.bytesSent += uint64(n)
        if n < buffer.len:
          output.currentBuffer = buffer
          output.currentBufferIdx = n
          ctx.register(output)

proc redirectToFile(ctx: var LoaderContext; output: OutputHandle;
    targetPath: string; fileOutput: var OutputHandle; osent: var uint64): bool =
  fileOutput = nil
  osent = 0
  discard mkdir(cstring(ctx.config.tmpdir), 0o700)
  let ps = newPosixStream(targetPath, O_CREAT or O_WRONLY or O_TRUNC, 0o600)
  if ps == nil:
    return false
  var buffer {.cursor.} = output.currentBuffer
  var m = output.currentBufferIdx
  while buffer != nil:
    while m < buffer.len:
      let n = ps.writeData(buffer, m)
      if n <= 0:
        ps.sclose()
        return false
      m += n
      osent += uint64(n)
    m = 0
    buffer = buffer.next
  if output.istreamAtEnd:
    ps.sclose()
  elif output.parent != nil:
    fileOutput = OutputHandle(
      parent: output.parent,
      stream: ps,
      istreamAtEnd: output.istreamAtEnd,
      outputId: ctx.getOutputId(),
      bytesSent: osent,
      url: output.url
    )
    output.parent.outputs.add(fileOutput)
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
    if codes.len > 3 or code.isErr:
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
    if v.len > 3 or code.isErr:
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
        if n := parseInt32(errs[1]):
          if n > 0 and n <= int32(ConnectionError.high):
            code = ConnectionError(n)
        elif (let x = strictParseEnum[ConnectionError](errs[1]).get(ceNone);
            x != ceNone):
          code = x
        if errs.len > 2:
          message &= errs[2]
          for i in 3 ..< errs.len:
            message &= ' '
            message &= errs[i]
      ctx.rejectHandle(handle, code, message)
      return crError
    if v.startsWithIgnoreCase("ControlDone"):
      case ctx.sendResult(handle, 0) # success
      of pbrDone: discard
      of pbrUnregister: return crError
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
    if v.len > 3 or code.isErr:
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
        of crError:
          discard ctx.sendStatus(handle, 500, parser.headers)
          die
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
  let maxUnregs = unregWrite.len + handle.outputs.len
  while true:
    var buffer = newLoaderBuffer()
    let n = handle.stream.readData(buffer.page)
    if n < 0:
      let e = errno
      if e == EAGAIN or e == EWOULDBLOCK or e == EINTR: # retry later
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
    ctx.pushBuffer(handle, buffer, ignoreSuspension = false, unregWrite)
    if unregWrite.len == maxUnregs:
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
  if r == hrrBrokenPipe:
    for output in handle.outputs:
      ctx.oclose(output)
  elif cachedHandle != nil:
    if handle.lastBuffer != nil:
      # cachedHandle has a different tail than handle, so output's
      # linked list will eventually break.
      # To fix this, we create a "ghost" buffer whose only purpose is to
      # connect the two chains, by setting it as the tail of both.
      # Note: we know that handle has read cachedHandle.lastBuffer,
      # because handle's input is taken synchronously from cachedHandle.
      let buffer = newLoaderBuffer(1)
      if cachedHandle.lastBuffer != nil:
        # I'm not 100% sure if this can be nil, but better safe than
        # sorry.
        cachedHandle.lastBuffer.next = buffer
      cachedHandle.lastBuffer = buffer
      handle.lastBuffer.next = buffer
    for output in handle.outputs:
      output.parent = cachedHandle
      cachedHandle.outputs.add(output)
  else:
    for output in handle.outputs:
      if output.registered or output.suspended:
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

proc includeCredentials(config: LoaderClientConfig; request: Request; url: URL):
    bool =
  return request.credentialsMode == cmInclude or
    request.credentialsMode == cmSameOrigin and
      config.originURL == nil or
        url.origin.isSameOrigin(config.originURL.origin)

proc findAuth(client: ClientHandle; request: Request; url: URL): AuthItem =
  if "Authorization" notin request.headers and
      client.config.includeCredentials(request, url):
    if client.authMap.len > 0:
      return client.authMap.findItem(url.authOrigin)
  return nil

proc putMappedURL(s: var seq[tuple[name, value: string]]; url: URL;
    auth: AuthItem) =
  s.add(("MAPPED_URI_SCHEME", url.scheme))
  if auth != nil:
    s.add(("MAPPED_URI_USERNAME", auth.username))
    s.add(("MAPPED_URI_PASSWORD", auth.password))
  s.add(("MAPPED_URI_HOST", url.hostname))
  s.add(("MAPPED_URI_PORT", url.port))
  s.add(("MAPPED_URI_PATH", url.pathname))
  s.add(("MAPPED_URI_QUERY", url.search.substr(1)))

type CGIPath = object
  basename: string
  pathInfo: string
  cmd: string
  scriptName: string
  requestURI: string
  myDir: string

proc setupEnv(cpath: CGIPath; request: Request; contentLen: int; prevURL: URL;
    config: LoaderClientConfig; auth: AuthItem):
    seq[tuple[name, value: string]] =
  result = @[]
  let url = request.url
  result.add(("SCRIPT_NAME", cpath.scriptName))
  result.add(("SCRIPT_FILENAME", cpath.cmd))
  result.add(("REQUEST_URI", cpath.requestURI))
  result.add(("REQUEST_METHOD", $request.httpMethod))
  var headers = ""
  for k, v in request.headers.allPairs:
    headers &= k & ": " & v & "\r\n"
  result.add(("REQUEST_HEADERS", headers))
  if prevURL != nil:
    result.putMappedURL(prevURL, auth)
  if cpath.pathInfo != "":
    result.add(("PATH_INFO", cpath.pathInfo))
  if url.search != "":
    result.add(("QUERY_STRING", url.search.substr(1)))
  if request.httpMethod == hmPost:
    if request.body.t == rbtMultipart:
      result.add(("CONTENT_TYPE", request.body.multipart.getContentType()))
    else:
      let contentType = request.headers.getFirst("Content-Type")
      result.add(("CONTENT_TYPE", contentType))
    result.add(("CONTENT_LENGTH", $contentLen))
  let cookie = request.headers.getFirst("Cookie")
  if cookie != "":
    result.add(("HTTP_COOKIE", cookie))
  let referer = request.headers.getFirst("Referer")
  if referer != "":
    result.add(("HTTP_REFERER", referer))
  if config.proxy != nil:
    result.add(("ALL_PROXY", $config.proxy))
  if config.insecureSslNoVerify:
    result.add(("CHA_INSECURE_SSL_NO_VERIFY", "1"))

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
  if prevURL != nil and not ctx.isPrivileged(client) and prevURL.isNetPath():
    # Quick hack to throttle the number of simultaneous ongoing
    # connections.
    # We do not want to throttle non-net paths and requests originating
    # from the pager (i.e. client is privileged); in the former case,
    # we are probably dealing with local requests, and in the latter
    # case, the config may be different than client.config.
    handle.connectionOwner = client
    if client.numConnections >= ctx.config.maxNetConnections:
      client.pending.add((handle, request, prevURL))
      return
    inc client.numConnections
  let cpath = ctx.parseCGIPath(request)
  if cpath.cmd == "" or cpath.basename in ["", ".", ".."] or
      cpath.basename[0] == '~':
    ctx.rejectHandle(handle, ceInvalidCGIPath)
    ctx.close(handle)
    return
  if not fileExists(cpath.cmd):
    ctx.rejectHandle(handle, ceCGIFileNotFound)
    ctx.close(handle)
    return
  # Pipe the response body as stdout.
  var pipefd: array[2, cint] # child -> parent
  if pipe(pipefd) == -1:
    ctx.rejectHandle(handle, ceFailedToSetUpCGI)
    ctx.close(handle)
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
      ctx.close(handle)
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
      ctx.close(handle)
      return
    cachedHandle = ctx.findCachedHandle(request.body.cacheId)
    if cachedHandle != nil: # cached item still open, switch to streaming mode
      if client.cacheMap[n].offset == -1:
        ctx.rejectHandle(handle, ceCGICachedBodyUnavailable)
        ctx.close(handle)
        return
      istream2 = istream
  elif request.body.t == rbtOutput:
    outputIn = ctx.findOutput(request.body.outputId, client)
    if outputIn == nil:
      ctx.rejectHandle(handle, ceCGIOutputHandleNotFound)
      ctx.close(handle)
      return
  if request.body.t in {rbtString, rbtMultipart, rbtOutput} or
      request.body.t == rbtCache and istream2 != nil:
    var pipefdRead: array[2, cint] # parent -> child
    if pipe(pipefdRead) == -1:
      ctx.rejectHandle(handle, ceFailedToSetUpCGI)
      ctx.close(handle)
      return
    istream = newPosixStream(pipefdRead[0])
    ostream = newPosixStream(pipefdRead[1])
  let contentLen = request.body.contentLength()
  let auth = if prevURL != nil: client.findAuth(request, prevURL) else: nil
  let env = setupEnv(cpath, request, contentLen, prevURL, config, auth)
  var pid: int
  let istream3 = if istream != nil: nil else: newPosixStream("/dev/null")
  ctx.forkStream.withPacketWriter w:
    if istream != nil:
      w.sendFd(istream.fd)
    else:
      w.sendFd(istream3.fd)
    w.sendFd(ostreamOut.fd)
    w.swrite(ostreamOut2 != nil)
    if ostreamOut2 != nil:
      w.sendFd(ostreamOut2.fd)
    w.swrite(env)
    w.swrite(cpath.myDir)
    w.swrite(cpath.cmd)
    w.swrite(cpath.basename)
  do:
    pid = -1
  if istream3 != nil:
    istream3.sclose()
  if pid != -1:
    ctx.forkStream.withPacketReader r:
      r.sread(pid)
    do:
      pid = -1
  ostreamOut.sclose() # close write
  if ostreamOut2 != nil:
    ostreamOut2.sclose() # close write
  if request.body.t != rbtNone:
    istream.sclose() # close read
  if pid == -1:
    ctx.rejectHandle(handle, ceFailedToSetUpCGI)
    if ostream != nil:
      ostream.sclose()
    ctx.close(handle)
  else:
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
      let output = ctx.tee(outputIn, ostream, client)
      output.suspended = false
      if not output.isEmpty:
        ctx.register(output)
    of rbtCache:
      if ostream != nil:
        let handle = ctx.newInputHandle(ostream, client,
          parseURL0("cache:/dev/null"), credentials = false, suspended = false)
        handle.stream = istream2
        ostream.setBlocking(false)
        ctx.loadStreamRegular(handle, cachedHandle)
        assert handle.stream == nil
        ctx.close(handle)
    of rbtNone:
      discard

proc findPassedFd(client: ClientHandle; name: string): int =
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
  let buffer = newLoaderBuffer(s)
  var dummy: seq[OutputHandle] = @[]
  ctx.pushBuffer(handle, buffer, ignoreSuspension = false, dummy)
  if not output.dead and (output.registered or output.suspended):
    output.istreamAtEnd = true
  else:
    if output.registered:
      ctx.unregister(output)
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
    if d.atob(body).isErr:
      ctx.rejectHandle(handle, ceInvalidURL, "invalid data URL")
      return
    ct.setLen(ct.len - ";base64".len) # remove base64 indicator
    ctx.loadDataSend(handle, d, ct)
  else:
    ctx.loadDataSend(handle, body, ct)

# Download manager. Based on (you guessed it) w3m.
proc formatSize(size: uint64): string =
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

proc loadDownloads(ctx: var LoaderContext; handle: InputHandle;
    request: Request) =
  if request.httpMethod == hmPost:
    # OK clicked
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

# Stream for notifying the pager of new cookies set in the loader.
proc loadCookieStream(ctx: var LoaderContext; handle: InputHandle;
    request: Request) =
  if ctx.cookieStream != nil:
    ctx.rejectHandle(handle, ceCookieStreamExists)
    return
  case ctx.sendResult(handle, 0)
  of pbrDone: discard
  of pbrUnregister:
    ctx.close(handle)
    return
  case ctx.sendStatus(handle, 200, newHeaders(hgResponse))
  of pbrDone: discard
  of pbrUnregister:
    ctx.close(handle)
    return
  ctx.cookieStream = handle

proc loadAbout(ctx: var LoaderContext; handle: InputHandle; request: Request) =
  let url = request.url
  case url.pathname
  of "blank":
    ctx.loadDataSend(handle, "", "text/html")
  of "chawan":
    const body = staticRead"res/chawan.html"
    ctx.loadDataSend(handle, body, "text/html")
  of "downloads":
    ctx.loadDownloads(handle, request)
  of "cookie-stream":
    ctx.loadCookieStream(handle, request)
  of "license":
    const body = staticRead"res/license.md"
    ctx.loadDataSend(handle, body, "text/markdown")
  else:
    ctx.rejectHandle(handle, ceInvalidURL, "invalid about URL")

proc loadResource(ctx: var LoaderContext; client: ClientHandle;
    config: LoaderClientConfig; request: Request; handle: InputHandle) =
  var redo = true
  var tries = 0
  var prevurl: URL = nil
  while redo and tries < MaxRewrites:
    redo = false
    if ctx.config.w3mCGICompat and request.url.schemeType == stFile:
      let path = request.url.pathname.percentDecode()
      if ctx.canRewriteForCGICompat(path):
        let url = parseURL0("cgi-bin:" & path & request.url.search)
        if url != nil:
          request.url = url
          inc tries
          redo = true
          continue
    case request.url.schemeType
    of stCgiBin:
      ctx.loadCGI(client, handle, request, prevurl, config)
      if handle.stream != nil:
        ctx.addFd(handle)
    of stStream:
      ctx.loadStream(client, handle, request)
      if handle.stream != nil:
        ctx.addFd(handle)
      else:
        ctx.close(handle)
    of stCache:
      ctx.loadFromCache(client, handle, request)
      assert handle.stream == nil
    of stData:
      ctx.loadData(handle, request)
    of stAbout:
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

proc setupRequestDefaults(request: Request; config: LoaderClientConfig;
    credentials: bool) =
  for k, v in config.defaultHeaders.allPairs:
    request.headers.addIfNotFound(k, v)
  if config.cookieJar != nil and credentials:
    let cookie = config.cookieJar.serialize(request.url)
    if cookie != "":
      request.headers.addIfNotFound("Cookie", cookie)
  let referrer = request.takeReferrer(config.referrerPolicy)
  if referrer != "":
    request.headers.add("Referer", referrer)

proc load(ctx: var LoaderContext; request: Request; client: ClientHandle;
    config: LoaderClientConfig): CommandResult =
  var pipev {.noinit.}: array[2, cint]
  var fail = false
  client.withPacketWriterReturnEOF w:
    if pipe(pipev) == 0:
      w.swrite(true)
      w.sendFd(pipev[0])
    else:
      fail = true
      w.swrite(false)
  if not fail:
    discard close(pipev[0])
    let stream = newSocketStream(pipev[1])
    stream.setBlocking(false)
    let credentials = config.includeCredentials(request, request.url)
    let handle = ctx.newInputHandle(stream, client, request.url, credentials)
    if not config.allowAllSchemes and
        request.url.scheme != config.originURL.scheme and
        request.url.scheme notin config.allowSchemes:
      ctx.rejectHandle(handle, ceDisallowedURL)
    else:
      request.setupRequestDefaults(config, credentials)
      ctx.loadResource(client, config, request, handle)
  cmdrDone

proc loadCmd(ctx: var LoaderContext; client: ClientHandle; r: var PacketReader):
    CommandResult =
  var request: Request
  r.sread(request)
  ctx.load(request, client, client.config)

proc loadConfigCmd(ctx: var LoaderContext; client: ClientHandle;
    r: var PacketReader): CommandResult =
  var request: Request
  var config: LoaderClientConfig
  r.sread(request)
  r.sread(config)
  ctx.load(request, client, config)

proc getCacheFileCmd(ctx: var LoaderContext; rclient: ClientHandle;
    r: var PacketReader): CommandResult =
  var cacheId: int
  var sourcePid: int
  r.sread(cacheId)
  r.sread(sourcePid)
  let client = ctx.clientMap.getOrDefault(sourcePid, nil)
  let n = if client != nil: client.cacheMap.find(cacheId) else: -1
  rclient.withPacketWriterReturnEOF w:
    if n != -1:
      w.swrite(client.cacheMap[n].path)
    else:
      w.swrite("")
  cmdrDone

proc addClientCmd(ctx: var LoaderContext; rclient: ClientHandle;
    r: var PacketReader): CommandResult =
  var pid: int
  var config: LoaderClientConfig
  var clonedFrom: int
  r.sread(pid)
  r.sread(config)
  r.sread(clonedFrom)
  assert pid notin ctx.clientMap
  var sv {.noinit.}: array[2, cint]
  var needsClose = false
  var res = cmdrDone
  rclient.withPacketWriter w:
    if socketpair(AF_UNIX, SOCK_STREAM, IPPROTO_IP, sv) == 0:
      let stream = newSocketStream(sv[0])
      let client = ClientHandle(stream: stream, pid: pid, config: config)
      ctx.register(client)
      ctx.put(client)
      if clonedFrom != -1:
        let client2 = ctx.clientMap.getOrDefault(clonedFrom)
        if client2 != nil:
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
      needsClose = true
    else:
      w.swrite(false)
  do:
    res = cmdrEOF
  if needsClose:
    discard close(sv[1])
  res

proc removeClientCmd(ctx: var LoaderContext; rclient: ClientHandle;
    r: var PacketReader): CommandResult =
  var pid: int
  r.sread(pid)
  let client = ctx.clientMap.getOrDefault(pid)
  if client != nil:
    ctx.unregClient.add(client)
  cmdrDone

proc addCacheFileCmd(ctx: var LoaderContext; rclient: ClientHandle;
    r: var PacketReader): CommandResult =
  var outputId: int
  r.sread(outputId)
  let output = ctx.findOutput(outputId, rclient)
  rclient.withPacketWriter w:
    if output == nil:
      w.swrite(-1)
    else:
      w.swrite(ctx.addCacheFile(rclient, output))
  do:
    return cmdrEOF
  cmdrDone

proc redirectToFileCmd(ctx: var LoaderContext; rclient: ClientHandle;
    r: var PacketReader): CommandResult =
  var outputId: int
  var targetPath: string
  var displayUrl: string
  r.sread(outputId)
  r.sread(targetPath)
  r.sread(displayUrl)
  let output = ctx.findOutput(outputId, rclient)
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
  rclient.withPacketWriter w:
    w.swrite(success)
  do:
    return cmdrEOF
  cmdrDone

proc shareCachedItemCmd(ctx: var LoaderContext; rclient: ClientHandle;
    r: var PacketReader): CommandResult =
  # share a cached file with another buffer. this is for newBufferFrom
  # (i.e. view source)
  var sourcePid: int # pid of source client
  var targetPid: int # pid of target client
  var id: int
  r.sread(sourcePid)
  r.sread(targetPid)
  r.sread(id)
  let sourceClient = ctx.clientMap.getOrDefault(sourcePid)
  let targetClient = ctx.clientMap.getOrDefault(targetPid)
  let n = if sourceClient != nil and targetClient != nil:
    sourceClient.cacheMap.find(id)
  else:
    -1
  if n != -1:
    let item = sourceClient.cacheMap[n]
    inc item.refc
    targetClient.cacheMap.add(item)
  rclient.withPacketWriter w:
    w.swrite(n != -1)
  do:
    return cmdrEOF
  cmdrDone

proc openCachedItemCmd(ctx: var LoaderContext; rclient: ClientHandle;
    r: var PacketReader): CommandResult =
  # open a cached item
  var id: int
  r.sread(id)
  let (ps, _) = rclient.openCachedItem(id)
  rclient.withPacketWriter w:
    w.swrite(ps != nil)
    if ps != nil:
      w.sendFd(ps.fd)
  do:
    return cmdrEOF
  if ps != nil:
    ps.sclose()
  cmdrDone

proc passFdCmd(ctx: var LoaderContext; rclient: ClientHandle;
    r: var PacketReader): CommandResult =
  var id: string
  r.sread(id)
  let fd = r.recvFd()
  #TODO cloexec?
  rclient.passedFdMap.add((id, newPosixStream(fd)))
  cmdrDone

proc addPipeCmd(ctx: var LoaderContext; rclient: ClientHandle;
    r: var PacketReader): CommandResult =
  var id: string
  r.sread(id)
  var pipefd {.noinit.}: array[2, cint]
  if pipe(pipefd) == -1:
    rclient.withPacketWriter w:
      w.swrite(false)
    do:
      return cmdrEOF
  else:
    var success = true
    rclient.withPacketWriter w:
      w.swrite(true)
      w.sendFd(pipefd[1])
    do:
      discard close(pipefd[0])
      discard close(pipefd[1])
      return cmdrEOF
    discard close(pipefd[1])
    if success:
      let ps = newPosixStream(pipefd[0])
      ps.setCloseOnExec()
      rclient.passedFdMap.add((id, ps))
    else:
      discard close(pipefd[0])
  cmdrDone

proc removeCachedItemCmd(ctx: var LoaderContext; client: ClientHandle;
    r: var PacketReader): CommandResult =
  var id: int
  r.sread(id)
  let n = client.cacheMap.find(id)
  if n != -1:
    let item = client.cacheMap[n]
    client.cacheMap.del(n)
    dec item.refc
    if item.refc == 0:
      discard unlink(cstring(item.path))
  cmdrDone

proc teeCmd(ctx: var LoaderContext; rclient: ClientHandle; r: var PacketReader):
    CommandResult =
  var sourceId: int
  var targetPid: int
  r.sread(sourceId)
  r.sread(targetPid)
  let outputIn = ctx.findOutput(sourceId, rclient)
  let target = ctx.clientMap.getOrDefault(targetPid)
  var pipev {.noinit.}: array[2, cint]
  var res = cmdrDone
  if target != nil and outputIn != nil and pipe(pipev) == 0:
    let ostream = newSocketStream(pipev[1])
    ostream.setBlocking(false)
    let output = ctx.tee(outputIn, ostream, target)
    rclient.withPacketWriter w:
      w.swrite(output.outputId)
      w.sendFd(pipev[0])
    do:
      res = cmdrEOF
    discard close(pipev[0])
  else:
    rclient.withPacketWriter w:
      w.swrite(-1)
    do:
      res = cmdrEOF
  res

proc addAuthCmd(ctx: var LoaderContext; rclient: ClientHandle;
    r: var PacketReader): CommandResult =
  var url: URL
  r.sread(url)
  let origin = url.authOrigin
  let item = ctx.authMap.findItem(origin)
  if item != nil:
    # Only replace the old item if the URL sets a password or the old
    # item's username is different.
    # This way, loading a URL with only the username set still lets us
    # load the password which is already associated with said username.
    if url.password != "" or item.username != url.username:
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
  cmdrDone

proc suspendCmd(ctx: var LoaderContext; rclient: ClientHandle;
    r: var PacketReader): CommandResult =
  var ids: seq[int]
  r.sread(ids)
  for id in ids:
    let output = ctx.findOutput(id, rclient)
    if output != nil:
      output.suspended = true
      if output.registered:
        # do not waste cycles trying to push into output
        ctx.unregister(output)
  cmdrDone

proc resumeCmd(ctx: var LoaderContext; rclient: ClientHandle;
    r: var PacketReader): CommandResult =
  var ids: seq[int]
  r.sread(ids)
  for id in ids:
    let output = ctx.findOutput(id, rclient)
    if output != nil:
      output.suspended = false
      if not output.isEmpty or output.istreamAtEnd:
        ctx.register(output)
  cmdrDone

const CommandMap = [
  lcAddAuth: addAuthCmd,
  lcAddCacheFile: addCacheFileCmd,
  lcAddClient: addClientCmd,
  lcAddPipe: addPipeCmd,
  lcGetCacheFile: getCacheFileCmd,
  lcLoad: loadCmd,
  lcLoadConfig: loadConfigCmd,
  lcOpenCachedItem: openCachedItemCmd,
  lcPassFd: passFdCmd,
  lcRedirectToFile: redirectToFileCmd,
  lcRemoveCachedItem: removeCachedItemCmd,
  lcRemoveClient: removeClientCmd,
  lcResume: resumeCmd,
  lcShareCachedItem: shareCachedItemCmd,
  lcSuspend: suspendCmd,
  lcTee: teeCmd,
]

const UnprivilegedCommands = {
  lcAddCacheFile, lcAddPipe, lcLoad, lcRemoveCachedItem, lcResume, lcSuspend,
  lcTee
}
const PrivilegedCommands = {LoaderCommand.low .. LoaderCommand.high} -
  UnprivilegedCommands

proc readCommand(ctx: var LoaderContext; rclient: ClientHandle) =
  assert not rclient.stream.isend
  var res = cmdrEOF
  rclient.stream.withPacketReaderFire r:
    var cmd: LoaderCommand
    r.sread(cmd)
    if cmd in PrivilegedCommands:
      doAssert ctx.isPrivileged(rclient)
    res = CommandMap[cmd](ctx, rclient, r)
  case res
  of cmdrDone: discard
  of cmdrEOF: ctx.unregClient.add(rclient)

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
      if e == EAGAIN or e == EWOULDBLOCK or e == EINTR: # never mind
        break
      else: # receiver died; stop streaming
        assert e == EPIPE, $strerror(e)
        unregWrite.add(output)
        break
    output.bytesSent += uint64(n)
    output.currentBufferIdx += n
    if output.currentBufferIdx < buffer.len:
      break
    # swap out buffer
    output.currentBufferIdx = 0
    output.currentBuffer = buffer.next
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
  for client in ctx.pendingConnections:
    if client.stream == nil:
      continue
    var j = ctx.config.maxNetConnections - client.numConnections
    for (handle, request, prevURL) in client.pending:
      if client.numConnections >= ctx.config.maxNetConnections:
        break
      ctx.loadCGI(client, handle, request, prevURL, client.config)
      if handle.stream != nil:
        ctx.addFd(handle)
    let L = max(client.pending.len - j, 0)
    for i in 0 ..< L:
      client.pending[i] = client.pending[j]
      inc j
    client.pending.setLen(L)
  ctx.pendingConnections.setLen(0)

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

proc runFileLoader*(config: LoaderConfig; stream, forkStream: SocketStream) =
  var ctx {.global.}: LoaderContext
  ctx = LoaderContext(
    config: config,
    pid: getCurrentProcessId(),
    forkStream: forkStream
  )
  onSignal SIGTERM:
    discard sig
    ctx.exitLoader()
  for dir in ctx.config.cgiDir.mitems:
    if dir.len > 0 and dir[^1] != '/':
      dir &= '/'
  var fail = false
  stream.withPacketReader r:
    var cmd: LoaderCommand
    r.sread(cmd)
    doAssert cmd == lcAddClient
    var pid: int
    var config: LoaderClientConfig
    var clonedFrom: int
    r.sread(pid)
    r.sread(config)
    r.sread(clonedFrom)
    stream.withPacketWriter w:
      w.swrite(true)
    do:
      fail = true
    ctx.pagerClient = ClientHandle(stream: stream, pid: pid, config: config)
  do:
    fail = true
  if fail:
    die("initialization error in loader")
  ctx.register(ctx.pagerClient)
  ctx.put(ctx.pagerClient)
  ctx.loaderLoop()

{.pop.} # raises: []
