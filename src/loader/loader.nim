# A file loader server (?)
# The idea here is that we receive requests with a socket, then respond to each
# with a response (ideally a document.)
# For now, the protocol looks like:
# C: Request
# S: res (0 => success, _ => error)
# if success:
#  S: output ID
#  S: status code
#  S: headers
#  C: resume
#  S: response body
# else:
#  S: error message
#
# The body is passed to the stream as-is, so effectively nothing can follow it.
#
# Note: if the consumer closes the request's body after headers have been
# passed, it will *not* be cleaned up until a `resume' command is
# received. (This allows for passing outputIds to the pager for later
# addCacheFile commands there.)

import std/deques
import std/nativesockets
import std/net
import std/options
import std/os
import std/posix
import std/selectors
import std/strutils
import std/tables

import io/bufreader
import io/bufwriter
import io/dynstream
import io/promise
import io/serversocket
import io/tempfile
import io/urlfilter
import loader/cgi
import loader/connecterror
import loader/headers
import loader/loaderhandle
import loader/request
import loader/response
import monoucha/javascript
import monoucha/jserror
import types/cookie
import types/opt
import types/referrer
import types/urimethodmap
import types/url
import utils/twtstr

export request
export response

type
  FileLoader* = ref object
    key*: ClientKey
    process*: int
    clientPid*: int
    map*: seq[LoaderData]
    mapFds*: int # number of fds in map
    unregistered*: seq[int]
    registerFun*: proc(fd: int)
    unregisterFun*: proc(fd: int)
    # directory where we store UNIX domain sockets
    sockDir*: string
    # (FreeBSD only) fd for the socket directory so we can connectat() on it
    sockDirFd*: int

  ConnectDataState = enum
    cdsBeforeResult, cdsBeforeStatus, cdsBeforeHeaders

  LoaderData = ref object of RootObj
    stream*: SocketStream

  ConnectData* = ref object of LoaderData
    state: ConnectDataState
    status: uint16
    res: int
    outputId: int
    redirectNum: int
    promise: Promise[JSResult[Response]]
    request: Request

  OngoingData* = ref object of LoaderData
    response*: Response

  LoaderCommand = enum
    lcAddCacheFile
    lcAddClient
    lcGetCacheFile
    lcLoad
    lcLoadConfig
    lcPassFd
    lcRedirectToFile
    lcRemoveCachedItem
    lcRemoveClient
    lcResume
    lcShareCachedItem
    lcSuspend
    lcTee

  ClientKey* = array[32, uint8]

  CachedItem = ref object
    id: int
    path: string
    refc: int

  ClientData = ref object
    pid: int
    key: ClientKey
    # List of cached resources.
    cacheMap: seq[CachedItem]
    # List of file descriptors passed by the client.
    passedFdMap: Table[string, FileHandle] # host -> fd
    config: LoaderClientConfig

  LoaderContext = ref object
    pagerClient: ClientData
    ssock: ServerSocket
    alive: bool
    config: LoaderConfig
    handleMap: seq[LoaderHandle]
    selector: Selector[int]
    # List of existing clients (buffer or pager) that may make requests.
    clientData: Table[int, ClientData] # pid -> data
    # ID of next output. TODO: find a better allocation scheme
    outputNum: int

  LoaderConfig* = object
    cgiDir*: seq[string]
    uriMethodMap*: URIMethodMap
    w3mCGICompat*: bool
    tmpdir*: string
    sockdir*: string

  LoaderClientConfig* = object
    cookieJar*: CookieJar
    defaultHeaders*: Headers
    filter*: URLFilter
    proxy*: URL
    referrerPolicy*: ReferrerPolicy
    insecureSSLNoVerify*: bool

  FetchPromise* = Promise[JSResult[Response]]

func isPrivileged(ctx: LoaderContext; client: ClientData): bool =
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

proc rejectHandle(handle: InputHandle; code: ConnectErrorCode; msg = "") =
  handle.sendResult(code, msg)
  handle.close()

iterator inputHandles(ctx: LoaderContext): InputHandle {.inline.} =
  for it in ctx.handleMap:
    if it != nil and it of InputHandle:
      yield InputHandle(it)

iterator outputHandles(ctx: LoaderContext): OutputHandle {.inline.} =
  for it in ctx.handleMap:
    if it != nil and it of OutputHandle:
      yield OutputHandle(it)

func findOutput(ctx: LoaderContext; id: int; client: ClientData): OutputHandle =
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

type PushBufferResult = enum
  pbrDone, pbrUnregister

proc register(ctx: LoaderContext; handle: InputHandle) =
  assert not handle.registered
  ctx.selector.registerHandle(int(handle.stream.fd), {Read}, 0)
  handle.registered = true

proc unregister(ctx: LoaderContext; handle: InputHandle) =
  assert handle.registered
  ctx.selector.unregister(int(handle.stream.fd))
  handle.registered = false

proc register(ctx: LoaderContext; output: OutputHandle) =
  assert not output.registered
  ctx.selector.registerHandle(int(output.stream.fd), {Write}, 0)
  output.registered = true

const bsdPlatform = defined(macosx) or defined(freebsd) or defined(netbsd) or
  defined(openbsd) or defined(dragonfly)
proc unregister(ctx: LoaderContext; output: OutputHandle) =
  assert output.registered
  # so kqueue-based selectors raise when we try to unregister a pipe whose
  # reader is at EOF. "solution": clean up this mess ourselves.
  let fd = int(output.stream.fd)
  when bsdPlatform:
    let oc = ctx.selector.count
    try:
      ctx.selector.unregister(fd)
    except IOSelectorsException:
      # ????
      for name, f in ctx.selector[].fieldPairs:
        when name == "fds":
          cast[ptr int](addr f[fd])[] = -1
        elif name == "changes":
          f.setLen(0)
      ctx.selector.count = oc - 1
  else:
    ctx.selector.unregister(fd)
  output.registered = false

# Either write data to the target output, or append it to the list of buffers to
# write and register the output in our selector.
proc pushBuffer(ctx: LoaderContext; output: OutputHandle; buffer: LoaderBuffer;
    si: int): PushBufferResult =
  if output.suspended:
    if output.currentBuffer == nil:
      output.currentBuffer = buffer
      output.currentBufferIdx = si
    else:
      # si must be 0 here in all cases. Why? Well, it indicates the first unread
      # position after reading headers, and at that point currentBuffer will
      # be empty.
      #
      # Obviously, this breaks down if anything is pushed into the stream
      # before the header parser destroys itself. For now it never does, so we
      # should be fine.
      doAssert si == 0
      output.buffers.addLast(buffer)
  elif output.currentBuffer == nil:
    var n = si
    try:
      n += output.stream.sendData(buffer, si)
    except ErrorAgain:
      discard
    except ErrorBrokenPipe:
      return pbrUnregister
    if n < buffer.len:
      output.currentBuffer = buffer
      output.currentBufferIdx = n
      ctx.register(output)
  else:
    output.buffers.addLast(buffer)
  pbrDone

proc getOutputId(ctx: LoaderContext): int =
  result = ctx.outputNum
  inc ctx.outputNum

proc redirectToFile(ctx: LoaderContext; output: OutputHandle;
    targetPath: string): bool =
  let ps = newPosixStream(targetPath, O_CREAT or O_WRONLY, 0o600)
  if ps == nil:
    return false
  try:
    if output.currentBuffer != nil:
      let n = ps.sendData(output.currentBuffer, output.currentBufferIdx)
      if unlikely(n < output.currentBuffer.len - output.currentBufferIdx):
        ps.sclose()
        return false
    for buffer in output.buffers:
      let n = ps.sendData(buffer)
      if unlikely(n < buffer.len):
        ps.sclose()
        return false
  except ErrorBrokenPipe:
    # ps is dead; give up.
    ps.sclose()
    return false
  if output.istreamAtEnd:
    ps.sclose()
  elif output.parent != nil:
    output.parent.outputs.add(OutputHandle(
      parent: output.parent,
      stream: ps,
      istreamAtEnd: output.istreamAtEnd,
      outputId: ctx.getOutputId()
    ))
  return true

proc addCacheFile(ctx: LoaderContext; client: ClientData; output: OutputHandle):
    int =
  if output.parent != nil and output.parent.cacheId != -1:
    # may happen e.g. if client tries to cache a `cache:' URL
    return output.parent.cacheId
  let tmpf = getTempFile(ctx.config.tmpdir)
  if ctx.redirectToFile(output, tmpf):
    let cacheId = output.outputId
    if output.parent != nil:
      output.parent.cacheId = cacheId
    client.cacheMap.add(CachedItem(id: cacheId, path: tmpf, refc: 1))
    return cacheId
  return -1

proc put(ctx: LoaderContext; handle: LoaderHandle) =
  let fd = int(handle.stream.fd)
  if ctx.handleMap.len <= fd:
    ctx.handleMap.setLen(fd + 1)
  assert ctx.handleMap[fd] == nil
  ctx.handleMap[fd] = handle

proc unset(ctx: LoaderContext; handle: LoaderHandle) =
  let fd = int(handle.stream.fd)
  if fd < ctx.handleMap.len:
    ctx.handleMap[fd] = nil

proc addFd(ctx: LoaderContext; handle: InputHandle) =
  let output = handle.output
  output.stream.setBlocking(false)
  handle.stream.setBlocking(false)
  ctx.register(handle)
  ctx.put(handle)
  ctx.put(output)

type HandleReadResult = enum
  hrrDone, hrrUnregister, hrrBrokenPipe

# Called whenever there is more data available to read.
proc handleRead(ctx: LoaderContext; handle: InputHandle;
    unregWrite: var seq[OutputHandle]): HandleReadResult =
  var unregs = 0
  let maxUnregs = handle.outputs.len
  while true:
    let buffer = newLoaderBuffer()
    try:
      let n = handle.stream.recvData(buffer)
      if n == 0: # EOF
        return hrrUnregister
      var si = 0
      if handle.parser != nil:
        si = handle.parseHeaders(buffer)
        if si == -1: # died while parsing headers; unregister
          return hrrUnregister
        if si == n: # parsed the entire buffer as headers; skip output handling
          continue
      for output in handle.outputs:
        if output.dead:
          # do not push to unregWrite candidates
          continue
        case ctx.pushBuffer(output, buffer, si)
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
    except ErrorAgain: # retry later
      break
    except ErrorBrokenPipe: # sender died; stop streaming
      return hrrBrokenPipe
  hrrDone

# stream is a regular file, so we can't select on it.
# cachedHandle is used for attaching the output handle to a different
# InputHandle when loadFromCache is called while a download is still ongoing
# (and thus some parts of the document are not cached yet).
proc loadStreamRegular(ctx: LoaderContext; handle, cachedHandle: InputHandle) =
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
      output.oclose()
    elif cachedHandle != nil:
      output.parent = cachedHandle
      cachedHandle.outputs.add(output)
      ctx.put(output)
    elif output.registered or output.suspended:
      output.parent = nil
      output.istreamAtEnd = true
      ctx.put(output)
    else:
      assert output.stream.fd < ctx.handleMap.len or
        ctx.handleMap[output.stream.fd] == nil
      output.oclose()
  handle.outputs.setLen(0)
  handle.iclose()

proc loadStream(ctx: LoaderContext; client: ClientData; handle: InputHandle;
    request: Request) =
  client.passedFdMap.withValue(request.url.pathname, fdp):
    handle.sendResult(0)
    handle.sendStatus(200)
    handle.sendHeaders(newHeaders())
    let ps = newPosixStream(fdp[])
    var stats: Stat
    doAssert fstat(fdp[], stats) != -1
    handle.stream = ps
    client.passedFdMap.del(request.url.pathname)
    if S_ISCHR(stats.st_mode) or S_ISREG(stats.st_mode):
      # regular file: e.g. cha <file
      # or character device: e.g. cha </dev/null
      handle.output.stream.setBlocking(false)
      # not loading from cache, so cachedHandle is nil
      ctx.loadStreamRegular(handle, nil)
  do:
    handle.sendResult(ERROR_FILE_NOT_FOUND, "stream not found")

func find(cacheMap: seq[CachedItem]; id: int): int =
  for i, it in cacheMap:
    if it.id == id:
      return i
  -1

proc openCachedItem(client: ClientData; id: int): (PosixStream, int) =
  let n = client.cacheMap.find(id)
  if n != -1:
    return (newPosixStream(client.cacheMap[n].path, O_RDONLY, 0), n)
  return (nil, -1)

proc loadFromCache(ctx: LoaderContext; client: ClientData; handle: InputHandle;
    request: Request) =
  let id = parseInt32(request.url.pathname).get(-1)
  let startFrom = if request.url.query.isSome:
    parseInt32(request.url.query.get).get(0)
  else:
    0
  let (ps, n) = client.openCachedItem(id)
  if ps != nil:
    if startFrom != 0:
      ps.seek(startFrom)
    handle.stream = ps
    if ps == nil:
      handle.rejectHandle(ERROR_FILE_NOT_IN_CACHE)
      client.cacheMap.del(n)
      return
    handle.sendResult(0)
    handle.sendStatus(200)
    handle.sendHeaders(newHeaders())
    handle.output.stream.setBlocking(false)
    let cachedHandle = ctx.findCachedHandle(id)
    ctx.loadStreamRegular(handle, cachedHandle)
  else:
    handle.sendResult(ERROR_URL_NOT_IN_CACHE)

# Data URL handler.
# Moved back into loader from CGI, because data URLs can get extremely long
# and thus no longer fit into the environment.
proc loadDataSend(ctx: LoaderContext; handle: InputHandle; s, ct: string) =
  handle.sendResult(0)
  handle.sendStatus(200)
  handle.sendHeaders(newHeaders({"Content-Type": ct}))
  let output = handle.output
  if s.len == 0:
    if output.suspended:
      output.istreamAtEnd = true
      ctx.put(output)
    else:
      output.oclose()
    return
  let buffer = newLoaderBuffer(size = s.len)
  buffer.len = s.len
  copyMem(buffer.page, unsafeAddr s[0], s.len)
  case ctx.pushBuffer(output, buffer, 0)
  of pbrUnregister:
    if output.registered:
      ctx.unregister(output)
    output.oclose()
  of pbrDone:
    if output.registered or output.suspended:
      output.istreamAtEnd = true
      ctx.put(output)
    else:
      output.oclose()

proc loadData(ctx: LoaderContext; handle: InputHandle; request: Request) =
  let url = request.url
  var ct = url.path.s.until(',')
  if AllChars - Ascii + Controls - {'\t', ' '} in ct:
    handle.sendResult(ERROR_INVALID_URL, "invalid data URL")
    handle.close()
    return
  let sd = ct.len + 1 # data start
  let body = percentDecode(url.path.s, sd)
  if ct.endsWith(";base64"):
    let d = atob0(body) # decode from ct end + 1
    if d.isNone:
      handle.sendResult(ERROR_INVALID_URL, "invalid data URL")
      handle.close()
      return
    ct.setLen(ct.len - ";base64".len) # remove base64 indicator
    ctx.loadDataSend(handle, d.get, ct)
  else:
    ctx.loadDataSend(handle, body, ct)

proc loadResource(ctx: LoaderContext; client: ClientData;
    config: LoaderClientConfig; request: Request; handle: InputHandle) =
  var redo = true
  var tries = 0
  var prevurl: URL = nil
  while redo and tries < MaxRewrites:
    redo = false
    if ctx.config.w3mCGICompat and request.url.scheme == "file":
      let path = request.url.path.serialize_unicode()
      if ctx.canRewriteForCGICompat(path):
        let newURL = newURL("cgi-bin:" & path & request.url.search)
        if newURL.isSome:
          request.url = newURL.get
          inc tries
          redo = true
          continue
    if request.url.scheme == "cgi-bin":
      var istream: PosixStream = nil # for rbtCache
      var ostream: PosixStream = nil # for rbtOutput
      if request.body.t == rbtCache:
        var n: int
        (istream, n) = client.openCachedItem(request.body.cacheId)
      handle.loadCGI(request, ctx.config.cgiDir, prevurl,
        config.insecureSSLNoVerify, ctx.handleMap, istream, ostream)
      if handle.stream != nil:
        if ostream != nil:
          let outputIn = ctx.findOutput(request.body.outputId, client)
          if outputIn != nil:
            ostream.setBlocking(false)
            let output = outputIn.tee(ostream, ctx.getOutputId(), client.pid)
            ctx.put(output)
            output.suspended = false
            if not output.isEmpty:
              ctx.register(output)
          else:
            ostream.sclose()
        ctx.addFd(handle)
      else:
        assert ostream == nil
        handle.close()
    elif request.url.scheme == "stream":
      ctx.loadStream(client, handle, request)
      if handle.stream != nil:
        ctx.addFd(handle)
      else:
        handle.close()
    elif request.url.scheme == "cache":
      ctx.loadFromCache(client, handle, request)
      assert handle.stream == nil
      handle.close()
    elif request.url.scheme == "data":
      ctx.loadData(handle, request)
    else:
      prevurl = request.url
      case ctx.config.uriMethodMap.findAndRewrite(request.url)
      of ummrSuccess:
        inc tries
        redo = true
      of ummrWrongURL:
        handle.rejectHandle(ERROR_INVALID_URI_METHOD_ENTRY)
      of ummrNotFound:
        handle.rejectHandle(ERROR_UNKNOWN_SCHEME)
  if tries >= MaxRewrites:
    handle.rejectHandle(ERROR_TOO_MANY_REWRITES)

proc setupRequestDefaults(request: Request; config: LoaderClientConfig) =
  for k, v in config.defaultHeaders.table:
    if k notin request.headers.table:
      request.headers.table[k] = v
  if config.cookieJar != nil and config.cookieJar.cookies.len > 0:
    if "Cookie" notin request.headers.table:
      let cookie = config.cookieJar.serialize(request.url)
      if cookie != "":
        request.headers["Cookie"] = cookie
  if request.referrer != nil and "Referer" notin request.headers:
    let r = request.referrer.getReferrer(request.url, config.referrerPolicy)
    if r != "":
      request.headers["Referer"] = r

proc load(ctx: LoaderContext; stream: SocketStream; request: Request;
    client: ClientData; config: LoaderClientConfig) =
  let handle = newInputHandle(stream, ctx.getOutputId(), client.pid)
  when defined(debug):
    handle.url = request.url
    handle.output.url = request.url
  if not config.filter.match(request.url):
    handle.rejectHandle(ERROR_DISALLOWED_URL)
  else:
    request.setupRequestDefaults(config)
    if request.proxy == nil or not ctx.isPrivileged(client):
      request.proxy = config.proxy
    ctx.loadResource(client, config, request, handle)

proc load(ctx: LoaderContext; stream: SocketStream; client: ClientData;
    r: var BufferedReader) =
  var request: Request
  r.sread(request)
  ctx.load(stream, request, client, client.config)

proc loadConfig(ctx: LoaderContext; stream: SocketStream; client: ClientData;
    r: var BufferedReader) =
  var request: Request
  r.sread(request)
  var config: LoaderClientConfig
  r.sread(config)
  ctx.load(stream, request, client, config)

proc getCacheFile(ctx: LoaderContext; stream: SocketStream; client: ClientData;
    r: var BufferedReader) =
  var cacheId: int
  r.sread(cacheId)
  stream.withPacketWriter w:
    let n = client.cacheMap.find(cacheId)
    if n != -1:
      w.swrite(client.cacheMap[n].path)
    else:
      w.swrite("")

proc addClient(ctx: LoaderContext; stream: SocketStream;
    r: var BufferedReader) =
  var key: ClientKey
  var pid: int
  var config: LoaderClientConfig
  var clonedFrom: int
  r.sread(key)
  r.sread(pid)
  r.sread(config)
  r.sread(clonedFrom)
  stream.withPacketWriter w:
    if pid in ctx.clientData or key == default(ClientKey):
      w.swrite(false)
    else:
      let client = ClientData(pid: pid, key: key, config: config)
      ctx.clientData[pid] = client
      if clonedFrom != -1:
        let client2 = ctx.clientData[clonedFrom]
        for item in client2.cacheMap:
          inc item.refc
        client.cacheMap = client2.cacheMap
      w.swrite(true)
  stream.sclose()

proc cleanup(client: ClientData) =
  for it in client.cacheMap:
    dec it.refc
    if it.refc == 0:
      discard unlink(cstring(it.path))

proc removeClient(ctx: LoaderContext; stream: SocketStream;
    r: var BufferedReader) =
  var pid: int
  r.sread(pid)
  if pid in ctx.clientData:
    let client = ctx.clientData[pid]
    client.cleanup()
    ctx.clientData.del(pid)
  stream.sclose()

proc addCacheFile(ctx: LoaderContext; stream: SocketStream; client: ClientData;
    r: var BufferedReader) =
  var outputId: int
  var targetPid: int
  r.sread(outputId)
  #TODO get rid of targetPid
  r.sread(targetPid)
  doAssert ctx.isPrivileged(client) or client.pid == targetPid
  let output = ctx.findOutput(outputId, client)
  assert output != nil
  let targetClient = ctx.clientData[targetPid]
  let id = ctx.addCacheFile(targetClient, output)
  stream.withPacketWriter w:
    w.swrite(id)
  stream.sclose()

proc redirectToFile(ctx: LoaderContext; stream: SocketStream;
    r: var BufferedReader) =
  var outputId: int
  var targetPath: string
  r.sread(outputId)
  r.sread(targetPath)
  let output = ctx.findOutput(outputId, ctx.pagerClient)
  var success = false
  if output != nil:
    success = ctx.redirectToFile(output, targetPath)
  stream.withPacketWriter w:
    w.swrite(success)
  stream.sclose()

proc shareCachedItem(ctx: LoaderContext; stream: SocketStream;
    r: var BufferedReader) =
  # share a cached file with another buffer. this is for newBufferFrom
  # (i.e. view source)
  var sourcePid: int # pid of source client
  var targetPid: int # pid of target client
  var id: int
  r.sread(sourcePid)
  r.sread(targetPid)
  r.sread(id)
  let sourceClient = ctx.clientData[sourcePid]
  let targetClient = ctx.clientData[targetPid]
  let n = sourceClient.cacheMap.find(id)
  let item = sourceClient.cacheMap[n]
  inc item.refc
  targetClient.cacheMap.add(item)
  stream.sclose()

proc passFd(ctx: LoaderContext; stream: SocketStream; client: ClientData;
    r: var BufferedReader) =
  var id: string
  r.sread(id)
  let fd = stream.recvFileHandle()
  client.passedFdMap[id] = fd
  stream.sclose()

proc removeCachedItem(ctx: LoaderContext; stream: SocketStream;
    client: ClientData; r: var BufferedReader) =
  var id: int
  r.sread(id)
  let n = client.cacheMap.find(id)
  if n != -1:
    let item = client.cacheMap[n]
    client.cacheMap.del(n)
    dec item.refc
    if item.refc == 0:
      discard unlink(cstring(item.path))
  stream.sclose()

proc tee(ctx: LoaderContext; stream: SocketStream; client: ClientData;
    r: var BufferedReader) =
  var sourceId: int
  var targetPid: int
  r.sread(sourceId)
  r.sread(targetPid)
  let outputIn = ctx.findOutput(sourceId, client)
  if outputIn != nil:
    let id = ctx.getOutputId()
    let output = outputIn.tee(stream, id, targetPid)
    ctx.put(output)
    stream.withPacketWriter w:
      w.swrite(id)
    stream.setBlocking(false)
  else:
    stream.withPacketWriter w:
      w.swrite(-1)
    stream.sclose()

proc suspend(ctx: LoaderContext; stream: SocketStream; client: ClientData;
    r: var BufferedReader) =
  var ids: seq[int]
  r.sread(ids)
  for id in ids:
    let output = ctx.findOutput(id, client)
    if output != nil:
      output.suspended = true
      if output.registered:
        # do not waste cycles trying to push into output
        ctx.unregister(output)
  stream.sclose()

proc resume(ctx: LoaderContext; stream: SocketStream; client: ClientData;
    r: var BufferedReader) =
  var ids: seq[int]
  r.sread(ids)
  for id in ids:
    let output = ctx.findOutput(id, client)
    if output != nil:
      output.suspended = false
      ctx.register(output)
  stream.sclose()

proc equalsConstantTime(a, b: ClientKey): bool =
  static:
    doAssert a.len == b.len
  {.push boundChecks:off, overflowChecks:off.}
  var i {.volatile.} = 0
  var res {.volatile.} = 0u8
  while i < a.len:
    res = res or (a[i] xor b[i])
    inc i
  {.pop.}
  return res == 0

proc acceptConnection(ctx: LoaderContext) =
  let stream = ctx.ssock.acceptSocketStream()
  try:
    stream.withPacketReader r:
      var myPid: int
      var key: ClientKey
      r.sread(myPid)
      r.sread(key)
      if myPid notin ctx.clientData:
        # possibly already removed
        stream.sclose()
        return
      let client = ctx.clientData[myPid]
      if not client.key.equalsConstantTime(key):
        # ditto
        stream.sclose()
        return
      var cmd: LoaderCommand
      r.sread(cmd)
      template privileged_command =
        doAssert ctx.isPrivileged(client)
      case cmd
      of lcAddClient:
        privileged_command
        ctx.addClient(stream, r)
      of lcRemoveClient:
        privileged_command
        ctx.removeClient(stream, r)
      of lcShareCachedItem:
        privileged_command
        ctx.shareCachedItem(stream, r)
      of lcRedirectToFile:
        privileged_command
        ctx.redirectToFile(stream, r)
      of lcLoadConfig:
        privileged_command
        ctx.loadConfig(stream, client, r)
      of lcGetCacheFile:
        privileged_command
        ctx.getCacheFile(stream, client, r)
      of lcAddCacheFile:
        ctx.addCacheFile(stream, client, r)
      of lcRemoveCachedItem:
        ctx.removeCachedItem(stream, client, r)
      of lcPassFd:
        ctx.passFd(stream, client, r)
      of lcLoad:
        ctx.load(stream, client, r)
      of lcTee:
        ctx.tee(stream, client, r)
      of lcSuspend:
        ctx.suspend(stream, client, r)
      of lcResume:
        ctx.resume(stream, client, r)
  except ErrorBrokenPipe:
    # receiving end died while reading the file; give up.
    assert stream.fd >= ctx.handleMap.len or ctx.handleMap[stream.fd] == nil
    stream.sclose()

proc exitLoader(ctx: LoaderContext) =
  ctx.ssock.close()
  for client in ctx.clientData.values:
    client.cleanup()
  exitnow(1)

var gctx: LoaderContext
proc initLoaderContext(fd: cint; config: LoaderConfig): LoaderContext =
  var ctx = LoaderContext(
    alive: true,
    config: config,
    selector: newSelector[int]()
  )
  gctx = ctx
  let myPid = getCurrentProcessId()
  # we don't capsicumize loader, so -1 is appropriate here
  ctx.ssock = initServerSocket(config.sockdir, -1, myPid, blocking = true)
  let sfd = int(ctx.ssock.sock.getFd())
  ctx.selector.registerHandle(sfd, {Read}, 0)
  if ctx.handleMap.len <= sfd:
    ctx.handleMap.setLen(sfd + 1)
  ctx.handleMap[sfd] = LoaderHandle() # pseudo handle
  # The server has been initialized, so the main process can resume execution.
  let ps = newPosixStream(fd)
  ps.write(char(0u8))
  ps.sclose()
  onSignal SIGTERM:
    discard sig
    gctx.exitLoader()
  for dir in ctx.config.cgiDir.mitems:
    if dir.len > 0 and dir[^1] != '/':
      dir &= '/'
  # get pager's key
  let stream = ctx.ssock.acceptSocketStream()
  stream.withPacketReader r:
    block readNullKey:
      var pid: int # ignore pid
      r.sread(pid)
      # pager's key is still null
      var key: ClientKey
      r.sread(key)
      doAssert key == default(ClientKey)
    var cmd: LoaderCommand
    r.sread(cmd)
    doAssert cmd == lcAddClient
    var key: ClientKey
    var pid: int
    var config: LoaderClientConfig
    r.sread(key)
    r.sread(pid)
    r.sread(config)
    stream.withPacketWriter w:
      w.swrite(true)
    ctx.pagerClient = ClientData(key: key, pid: pid, config: config)
    ctx.clientData[pid] = ctx.pagerClient
    stream.sclose()
  # unblock main socket
  ctx.ssock.sock.getFd().setBlocking(false)
  # for CGI
  putEnv("SERVER_SOFTWARE", "Chawan")
  putEnv("SERVER_PROTOCOL", "HTTP/1.0")
  putEnv("SERVER_NAME", "localhost")
  putEnv("SERVER_PORT", "80")
  putEnv("REMOTE_HOST", "localhost")
  putEnv("REMOTE_ADDR", "127.0.0.1")
  putEnv("GATEWAY_INTERFACE", "CGI/1.1")
  putEnv("CHA_INSECURE_SSL_NO_VERIFY", "0")
  return ctx

# This is only called when an OutputHandle could not read enough of one (or
# more) buffers, and we asked select to notify us when it will be available.
proc handleWrite(ctx: LoaderContext; output: OutputHandle;
    unregWrite: var seq[OutputHandle]) =
  while output.currentBuffer != nil:
    let buffer = output.currentBuffer
    try:
      let n = output.stream.sendData(buffer, output.currentBufferIdx)
      output.currentBufferIdx += n
      if output.currentBufferIdx < buffer.len:
        break
      output.bufferCleared() # swap out buffer
    except ErrorAgain: # never mind
      break
    except ErrorBrokenPipe: # receiver died; stop streaming
      unregWrite.add(output)
      break
  if output.isEmpty:
    if output.istreamAtEnd:
      # after EOF, no need to send anything more here
      unregWrite.add(output)
    else:
      # all buffers sent, no need to select on this output again for now
      ctx.unregister(output)

proc finishCycle(ctx: LoaderContext; unregRead: var seq[InputHandle];
    unregWrite: var seq[OutputHandle]) =
  # Unregister handles queued for unregistration.
  # It is possible for both unregRead and unregWrite to contain duplicates. To
  # avoid double-close/double-unregister, we set the istream/ostream of
  # unregistered handles to nil.
  for handle in unregRead:
    if handle.stream != nil:
      ctx.unregister(handle)
      ctx.unset(handle)
      if handle.parser != nil:
        handle.finishParse()
      handle.iclose()
      for output in handle.outputs:
        output.istreamAtEnd = true
        if output.isEmpty:
          unregWrite.add(output)
  for output in unregWrite:
    if output.stream != nil:
      if output.registered:
        ctx.unregister(output)
      ctx.unset(output)
      output.oclose()
      let handle = output.parent
      if handle != nil: # may be nil if from loadStream S_ISREG
        let i = handle.outputs.find(output)
        handle.outputs.del(i)
        if handle.outputs.len == 0 and handle.stream != nil:
          # premature end of all output streams; kill istream too
          ctx.unregister(handle)
          ctx.unset(handle)
          if handle.parser != nil:
            handle.finishParse()
          handle.iclose()

proc runFileLoader*(fd: cint; config: LoaderConfig) =
  var ctx = initLoaderContext(fd, config)
  let fd = int(ctx.ssock.sock.getFd())
  var keys: array[64, ReadyKey]
  while ctx.alive:
    let count = ctx.selector.selectInto(-1, keys)
    var unregRead: seq[InputHandle] = @[]
    var unregWrite: seq[OutputHandle] = @[]
    for event in keys.toOpenArray(0, count - 1):
      let handle = ctx.handleMap[event.fd]
      if Read in event.events:
        if event.fd == fd: # incoming connection
          ctx.acceptConnection()
        else:
          let handle = InputHandle(ctx.handleMap[event.fd])
          case ctx.handleRead(handle, unregWrite)
          of hrrDone: discard
          of hrrUnregister, hrrBrokenPipe: unregRead.add(handle)
      if Write in event.events:
        ctx.handleWrite(OutputHandle(handle), unregWrite)
      if Error in event.events:
        assert event.fd != fd
        if handle of InputHandle: # istream died
          unregRead.add(InputHandle(handle))
        else: # ostream died
          unregWrite.add(OutputHandle(handle))
    ctx.finishCycle(unregRead, unregWrite)
  ctx.exitLoader()

proc getRedirect*(response: Response; request: Request): Request =
  if "Location" in response.headers.table:
    if response.status in 301u16..303u16 or response.status in 307u16..308u16:
      let location = response.headers.table["Location"][0]
      let url = parseURL(location, option(request.url))
      if url.isSome:
        let status = response.status
        if status == 303 and request.httpMethod notin {hmGet, hmHead} or
            status == 301 or
            status == 302 and request.httpMethod == hmPost:
          return newRequest(url.get, hmGet)
        else:
          return newRequest(url.get, request.httpMethod, body = request.body)
  return nil

template withLoaderPacketWriter(stream: SocketStream; loader: FileLoader;
    w, body: untyped) =
  stream.withPacketWriter w:
    w.swrite(loader.clientPid)
    w.swrite(loader.key)
    body

proc connect(loader: FileLoader): SocketStream =
  return connectSocketStream(loader.sockDir, loader.sockDirFd, loader.process,
    blocking = true)

# Start a request. This should not block (not for a significant amount of time
# anyway).
proc startRequest(loader: FileLoader; request: Request): SocketStream =
  let stream = loader.connect()
  stream.withLoaderPacketWriter loader, w:
    w.swrite(lcLoad)
    w.swrite(request)
  return stream

proc startRequest*(loader: FileLoader; request: Request;
    config: LoaderClientConfig): SocketStream =
  let stream = loader.connect()
  stream.withLoaderPacketWriter loader, w:
    w.swrite(lcLoadConfig)
    w.swrite(request)
    w.swrite(config)
  return stream

iterator ongoing*(loader: FileLoader): OngoingData =
  for it in loader.map:
    if it != nil and it of OngoingData:
      yield OngoingData(it)

func fd*(data: LoaderData): int =
  return int(data.stream.fd)

proc put*(loader: FileLoader; data: LoaderData) =
  let fd = int(data.stream.fd)
  if loader.map.len <= fd:
    loader.map.setLen(fd + 1)
  assert loader.map[fd] == nil
  loader.map[fd] = data
  inc loader.mapFds

proc get*(loader: FileLoader; fd: int): LoaderData =
  if fd < loader.map.len:
    return loader.map[fd]
  return nil

proc unset*(loader: FileLoader; data: LoaderData) =
  let fd = int(data.stream.fd)
  if loader.get(fd) != nil:
    dec loader.mapFds
    loader.map[fd] = nil

proc fetch0(loader: FileLoader; input: Request; promise: FetchPromise;
    redirectNum: int) =
  let stream = loader.startRequest(input)
  loader.registerFun(int(stream.fd))
  loader.put(ConnectData(
    promise: promise,
    request: input,
    stream: stream,
    redirectNum: redirectNum
  ))

proc fetch*(loader: FileLoader; input: Request): FetchPromise =
  let promise = FetchPromise()
  loader.fetch0(input, promise, 0)
  return promise

proc reconnect*(loader: FileLoader; data: ConnectData) =
  data.stream.sclose()
  let stream = loader.startRequest(data.request)
  let data = ConnectData(
    promise: data.promise,
    request: data.request,
    stream: stream
  )
  loader.put(data)
  loader.registerFun(data.fd)

proc suspend*(loader: FileLoader; fds: seq[int]) =
  let stream = loader.connect()
  stream.withLoaderPacketWriter loader, w:
    w.swrite(lcSuspend)
    w.swrite(fds)
  stream.sclose()

proc resume*(loader: FileLoader; fds: openArray[int]) =
  let stream = loader.connect()
  stream.withLoaderPacketWriter loader, w:
    w.swrite(lcResume)
    w.swrite(fds)
  stream.sclose()

proc resume*(loader: FileLoader; fds: int) =
  loader.resume([fds])

proc tee*(loader: FileLoader; sourceId, targetPid: int): (SocketStream, int) =
  let stream = loader.connect()
  stream.withLoaderPacketWriter loader, w:
    w.swrite(lcTee)
    w.swrite(sourceId)
    w.swrite(targetPid)
  var outputId: int
  var r = stream.initPacketReader()
  r.sread(outputId)
  return (stream, outputId)

proc addCacheFile*(loader: FileLoader; outputId, targetPid: int): int =
  let stream = loader.connect()
  if stream == nil:
    return -1
  stream.withLoaderPacketWriter loader, w:
    w.swrite(lcAddCacheFile)
    w.swrite(outputId)
    w.swrite(targetPid)
  var r = stream.initPacketReader()
  var outputId: int
  r.sread(outputId)
  stream.sclose()
  return outputId

proc getCacheFile*(loader: FileLoader; cacheId: int): string =
  let stream = loader.connect()
  if stream == nil:
    return ""
  stream.withLoaderPacketWriter loader, w:
    w.swrite(lcGetCacheFile)
    w.swrite(cacheId)
  var r = stream.initPacketReader()
  var s: string
  r.sread(s)
  stream.sclose()
  return s

proc redirectToFile*(loader: FileLoader; outputId: int; targetPath: string):
    bool =
  let stream = loader.connect()
  if stream == nil:
    return false
  stream.withLoaderPacketWriter loader, w:
    w.swrite(lcRedirectToFile)
    w.swrite(outputId)
    w.swrite(targetPath)
  var r = stream.initPacketReader()
  var res: bool
  r.sread(res)
  stream.sclose()
  return res

proc onConnected(loader: FileLoader; connectData: ConnectData) =
  let stream = connectData.stream
  let promise = connectData.promise
  let request = connectData.request
  var r = stream.initPacketReader()
  case connectData.state
  of cdsBeforeResult:
    var res: int
    r.sread(res) # packet 1
    if res == 0:
      r.sread(connectData.outputId) # packet 1
      inc connectData.state
    else:
      var msg: string
      # msg is discarded.
      #TODO maybe print if called from trusted code (i.e. global == client)?
      r.sread(msg) # packet 1
      let fd = connectData.fd
      loader.unregisterFun(fd)
      loader.unregistered.add(fd)
      stream.sclose()
      # delete before resolving the promise
      loader.unset(connectData)
      let err = newTypeError("NetworkError when attempting to fetch resource")
      promise.resolve(JSResult[Response].err(err))
  of cdsBeforeStatus:
    r.sread(connectData.status) # packet 2
    inc connectData.state
  of cdsBeforeHeaders:
    let response = newResponse(connectData.res, request, stream,
      connectData.outputId, connectData.status)
    r.sread(response.headers) # packet 3
    # Only a stream of the response body may arrive after this point.
    response.body = stream
    # delete before resolving the promise
    loader.unset(connectData)
    let data = OngoingData(response: response, stream: stream)
    loader.put(data)
    assert loader.unregisterFun != nil
    response.unregisterFun = proc() =
      loader.unset(data)
      let fd = data.fd
      loader.unregistered.add(fd)
      loader.unregisterFun(fd)
    response.resumeFun = proc(outputId: int) =
      loader.resume(outputId)
    stream.setBlocking(false)
    let redirect = response.getRedirect(request)
    if redirect != nil:
      response.unregisterFun()
      stream.sclose()
      let redirectNum = connectData.redirectNum + 1
      if redirectNum < 5: #TODO use config.network.max_redirect?
        loader.fetch0(redirect, promise, redirectNum)
      else:
        let err = newTypeError("NetworkError when attempting to fetch resource")
        promise.resolve(JSResult[Response].err(err))
    else:
      promise.resolve(JSResult[Response].ok(response))

proc onRead*(loader: FileLoader; data: OngoingData) =
  let response = data.response
  response.onRead(response)
  if response.body.isend:
    if response.onFinish != nil:
      response.onFinish(response, true)
    response.onFinish = nil
    response.close()

proc onRead*(loader: FileLoader; fd: int) =
  let data = loader.map[fd]
  if data of ConnectData:
    loader.onConnected(ConnectData(data))
  else:
    loader.onRead(OngoingData(data))

proc onError*(loader: FileLoader; data: OngoingData) =
  let response = data.response
  if response.onFinish != nil:
    response.onFinish(response, false)
  response.onFinish = nil
  response.close()

proc onError*(loader: FileLoader; fd: int): bool =
  let data = loader.map[fd]
  if data of ConnectData:
    # probably shouldn't happen. TODO
    return false
  else:
    loader.onError(OngoingData(data))
    return true

# Note: this blocks until headers are received.
proc doRequest*(loader: FileLoader; request: Request): Response =
  let stream = loader.startRequest(request)
  let response = Response(url: request.url)
  var r = stream.initPacketReader()
  r.sread(response.res) # packet 1
  if response.res == 0:
    r.sread(response.outputId) # packet 1
    r = stream.initPacketReader()
    r.sread(response.status) # packet 2
    r = stream.initPacketReader()
    r.sread(response.headers) # packet 3
    # Only a stream of the response body may arrive after this point.
    response.body = stream
    response.resumeFun = proc(outputId: int) =
      loader.resume(outputId)
  else:
    var msg: string
    r.sread(msg) # packet 1
    stream.sclose()
  return response

proc shareCachedItem*(loader: FileLoader; id, targetPid: int; sourcePid = -1) =
  let stream = loader.connect()
  if stream != nil:
    let sourcePid = if sourcePid != -1: sourcePid else: loader.clientPid
    stream.withLoaderPacketWriter loader, w:
      w.swrite(lcShareCachedItem)
      w.swrite(sourcePid)
      w.swrite(targetPid)
      w.swrite(id)
    stream.sclose()

proc passFd*(loader: FileLoader; id: string; fd: FileHandle) =
  let stream = loader.connect()
  if stream != nil:
    stream.withLoaderPacketWriter loader, w:
      w.swrite(lcPassFd)
      w.swrite(id)
    stream.sendFileHandle(fd)
    stream.sclose()

proc removeCachedItem*(loader: FileLoader; cacheId: int) =
  let stream = loader.connect()
  if stream != nil:
    stream.withLoaderPacketWriter loader, w:
      w.swrite(lcRemoveCachedItem)
      w.swrite(cacheId)
    stream.sclose()

proc addClient*(loader: FileLoader; key: ClientKey; pid: int;
    config: LoaderClientConfig; clonedFrom: int): bool =
  let stream = loader.connect()
  stream.withLoaderPacketWriter loader, w:
    w.swrite(lcAddClient)
    w.swrite(key)
    w.swrite(pid)
    w.swrite(config)
    w.swrite(clonedFrom)
  var r = stream.initPacketReader()
  var res: bool
  r.sread(res)
  stream.sclose()
  return res

proc removeClient*(loader: FileLoader; pid: int) =
  let stream = loader.connect()
  if stream != nil:
    stream.withLoaderPacketWriter loader, w:
      w.swrite(lcRemoveClient)
      w.swrite(pid)
    stream.sclose()

when defined(freebsd):
  let O_DIRECTORY* {.importc, header: "<fcntl.h>", noinit.}: cint

proc setSocketDir*(loader: FileLoader; path: string) =
  loader.sockDir = path
  when defined(freebsd):
    loader.sockDirFd = open(cstring(path), O_DIRECTORY)
  else:
    loader.sockDirFd = -1
