# Interface to server/loader. The idea is that modules don't have to
# depend on the entire loader implementation to interact with it.
#
# See server/loader for a more detailed description of the protocol.

import config/conftypes
import config/cookie
import io/dynstream
import io/packetreader
import io/packetwriter
import io/promise
import monoucha/jserror
import server/connectionerror
import server/headers
import server/request
import server/response
import types/opt
import types/referrer
import types/url

type
  FileLoader* = ref object
    clientPid*: int
    map: seq[MapData]
    mapFds*: int # number of fds in map
    unregistered*: seq[int]
    registerFun*: proc(fd: int) {.raises: [].}
    unregisterFun*: proc(fd: int) {.raises: [].}
    # A mechanism to queue up new fds being added to the poll data
    # inside the events iterator.
    registerBlocked: bool
    registerQueue: seq[ConnectData]
    # UNIX domain socket to the loader process.
    # We send all messages through this.
    controlStream*: SocketStream

  ConnectDataState = enum
    cdsBeforeResult, cdsBeforeStatus

  MapData* = ref object of RootObj
    stream*: PosixStream

  LoaderData = ref object of MapData

  ConnectData* = ref object of LoaderData
    state: ConnectDataState
    res: int
    outputId: int
    redirectNum: int
    promise: FetchPromise
    request: Request

  OngoingData* = ref object of LoaderData
    response*: Response

  LoaderCommand* = enum
    lcAddAuth
    lcAddCacheFile
    lcAddClient
    lcAddPipe
    lcGetCacheFile
    lcLoad
    lcLoadConfig
    lcOpenCachedItem
    lcPassFd
    lcRedirectToFile
    lcRemoveCachedItem
    lcRemoveClient
    lcResume
    lcShareCachedItem
    lcSuspend
    lcTee

  ClientKey* = array[32, uint8]

  LoaderClientConfig* = object
    originURL*: URL
    cookieJar*: CookieJar
    defaultHeaders*: Headers
    proxy*: URL
    allowSchemes*: seq[string]
    allowAllSchemes*: bool # only true for pager process
    insecureSslNoVerify*: bool
    referrerPolicy*: ReferrerPolicy
    cookieMode*: CookieMode

proc getRedirect*(response: Response; request: Request): Request =
  if response.status in 301u16..303u16 or response.status in 307u16..308u16:
    let location = response.headers.getFirst("Location")
    if url := parseURL(location, request.url):
      let status = response.status
      if status == 303 and request.httpMethod notin {hmGet, hmHead} or
          status == 301 or
          status == 302 and request.httpMethod == hmPost:
        return newRequest(url, hmGet)
      return newRequest(url, request.httpMethod, body = request.body)
  return nil

# Sometimes, we can return a value even after the loader crashed.
# This improves reliability of the pager.
template withPacketWriter(loader: FileLoader; w, body, fallback: untyped) =
  loader.controlStream.withPacketWriter w:
    body
  do:
    fallback

template withPacketWriterFire(loader: FileLoader; w, body: untyped) =
  loader.controlStream.withPacketWriterFire w:
    body

template withPacketReaderFire(loader: FileLoader; r, body: untyped) =
  loader.controlStream.withPacketReaderFire r:
    body

# Start a request. This should not block (not for a significant amount
# of time anyway).
proc startRequest(loader: FileLoader; request: Request): SocketStream =
  loader.withPacketWriter w:
    w.swrite(lcLoad)
    w.swrite(request)
  do:
    return nil
  var success = false
  var fd: cint
  loader.withPacketReaderFire r:
    r.sread(success)
    if success:
      fd = r.recvFd()
  if success:
    let res = newSocketStream(fd)
    res.setCloseOnExec()
    return res
  return nil

proc startRequest*(loader: FileLoader; request: Request;
    config: LoaderClientConfig): PosixStream =
  loader.withPacketWriter w:
    w.swrite(lcLoadConfig)
    w.swrite(request)
    w.swrite(config)
  do:
    return nil
  var fd = cint(-1)
  loader.withPacketReaderFire r:
    var success: bool
    r.sread(success)
    if success:
      fd = r.recvFd()
  if fd != -1:
    return newPosixStream(fd)
  nil

iterator data*(loader: FileLoader): MapData {.inline.} =
  for it in loader.map:
    if it != nil:
      yield it

iterator ongoing*(loader: FileLoader): OngoingData {.inline.} =
  for it in loader.data:
    if it of OngoingData:
      yield OngoingData(it)

proc fd*(data: MapData): int =
  return int(data.stream.fd)

proc put*(loader: FileLoader; data: MapData) =
  let fd = int(data.stream.fd)
  if loader.map.len <= fd:
    loader.map.setLen(fd + 1)
  assert loader.map[fd] == nil
  loader.map[fd] = data
  if data of LoaderData:
    inc loader.mapFds

proc get*(loader: FileLoader; fd: int): MapData =
  if fd < loader.map.len:
    return loader.map[fd]
  return nil

proc unset*(loader: FileLoader; fd: int) =
  if loader.map[fd] != nil and loader.map[fd] of LoaderData:
    dec loader.mapFds
  loader.map[fd] = nil

proc unset*(loader: FileLoader; data: MapData) =
  let fd = int(data.stream.fd)
  if loader.get(fd) != nil:
    loader.unset(fd)

proc hasFds*(loader: FileLoader): bool =
  return loader.mapFds > 0 or loader.registerQueue.len > 0

proc register(loader: FileLoader; data: ConnectData) =
  if loader.registerBlocked:
    loader.registerQueue.add(data)
  else:
    loader.registerFun(int(data.stream.fd))
    loader.put(data)

proc blockRegister*(loader: FileLoader) =
  assert not loader.registerBlocked
  loader.registerBlocked = true

proc unblockRegister*(loader: FileLoader) =
  assert loader.registerBlocked
  loader.registerBlocked = false
  for it in loader.registerQueue:
    loader.register(it)
  loader.registerQueue.setLen(0)

proc fetch0(loader: FileLoader; input: Request; promise: FetchPromise;
    redirectNum: int) =
  let stream = loader.startRequest(input)
  if stream != nil:
    loader.register(ConnectData(
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
  if stream != nil:
    loader.register(ConnectData(
      promise: data.promise,
      request: data.request,
      stream: stream
    ))

proc suspend*(loader: FileLoader; fds: seq[int]) =
  loader.withPacketWriterFire w:
    w.swrite(lcSuspend)
    w.swrite(fds)

proc resume*(loader: FileLoader; fds: openArray[int]) =
  loader.withPacketWriterFire w:
    w.swrite(lcResume)
    w.swrite(fds)

proc resume*(loader: FileLoader; fds: int) =
  loader.resume([fds])

proc tee*(loader: FileLoader; sourceId, targetPid: int): (SocketStream, int) =
  loader.withPacketWriter w:
    w.swrite(lcTee)
    w.swrite(sourceId)
    w.swrite(targetPid)
  do:
    return (nil, -1)
  var outputId: int
  var fd = cint(-1)
  loader.withPacketReaderFire r:
    r.sread(outputId)
    if outputId != -1:
      fd = r.recvFd()
  if fd != -1:
    return (newSocketStream(fd), outputId)
  return (nil, -1)

proc addCacheFile*(loader: FileLoader; outputId: int): int =
  loader.withPacketWriter w:
    w.swrite(lcAddCacheFile)
    w.swrite(outputId)
  do:
    return -1
  var cacheId = -1
  loader.withPacketReaderFire r:
    r.sread(cacheId)
  return cacheId

proc getCacheFile*(loader: FileLoader; cacheId, sourcePid: int): string =
  loader.withPacketWriter w:
    w.swrite(lcGetCacheFile)
    w.swrite(cacheId)
    w.swrite(sourcePid)
  do:
    return ""
  var s = ""
  loader.withPacketReaderFire r:
    r.sread(s)
  move(s)

proc redirectToFile*(loader: FileLoader; outputId: int; targetPath: string;
    displayUrl: URL): bool =
  loader.withPacketWriter w:
    w.swrite(lcRedirectToFile)
    w.swrite(outputId)
    w.swrite(targetPath)
    w.swrite($displayUrl)
  do:
    return false
  var res = false
  loader.withPacketReaderFire r:
    r.sread(res)
  return res

proc onConnected(loader: FileLoader; connectData: ConnectData) =
  let stream = connectData.stream
  let promise = connectData.promise
  let request = connectData.request
  stream.withPacketReader r:
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
        r.sread(msg) # packet 1
        let fd = connectData.fd
        loader.unregisterFun(fd)
        loader.unregistered.add(fd)
        stream.sclose()
        # delete before resolving the promise
        loader.unset(connectData)
        promise.resolve(JSResult[Response].err(newFetchTypeError()))
    of cdsBeforeStatus:
      let response = newResponse(connectData.res, request, stream,
        connectData.outputId)
      # packet 2
      r.sread(response.status)
      r.sread(response.headers)
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
          promise.resolve(JSResult[Response].err(newFetchTypeError()))
      else:
        promise.resolve(JSResult[Response].ok(response))
  do: # loader died
    loader.unregisterFun(connectData.fd)
    loader.unregistered.add(connectData.fd)
    stream.sclose()
    # delete before resolving the promise
    loader.unset(connectData)
    promise.resolve(JSResult[Response].err(newFetchTypeError()))

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
    response.onFinish(response, true)
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
  var r: PacketReader
  if stream != nil and stream.initPacketReader(r):
    r.sread(response.res) # packet 1
    if response.res == 0:
      r.sread(response.outputId) # packet 1
      if stream.initPacketReader(r): # packet 2
        r.sread(response.status)
        r.sread(response.headers)
        # Only a stream of the response body may arrive after this point.
        response.body = stream
        response.resumeFun = proc(outputId: int) =
          loader.resume(outputId)
      else: # EOF
        response.res = int(ceLoaderGone)
        stream.sclose()
    else:
      var msg: string
      r.sread(msg) # packet 1
      stream.sclose()
  else: # EOF
    response.res = int(ceLoaderGone)
    if stream != nil:
      stream.sclose()
  return response

proc shareCachedItem*(loader: FileLoader; id, targetPid: int; sourcePid = -1):
    bool =
  let sourcePid = if sourcePid != -1: sourcePid else: loader.clientPid
  loader.withPacketWriterFire w:
    w.swrite(lcShareCachedItem)
    w.swrite(sourcePid)
    w.swrite(targetPid)
    w.swrite(id)
  var success = false
  loader.withPacketReaderFire r:
    r.sread(success)
  return success

proc openCachedItem*(loader: FileLoader; cacheId: int): PosixStream =
  loader.withPacketWriter w:
    w.swrite(lcOpenCachedItem)
    w.swrite(cacheId)
  do:
    return nil
  var fd = cint(-1)
  loader.withPacketReaderFire r:
    var success: bool
    r.sread(success)
    if success:
      fd = r.recvFd()
  if fd != -1:
    return newPosixStream(fd)
  return nil

proc passFd*(loader: FileLoader; id: string; fd: cint) =
  loader.withPacketWriterFire w:
    w.swrite(lcPassFd)
    w.swrite(id)
    w.sendFd(fd)

proc removeCachedItem*(loader: FileLoader; cacheId: int) =
  loader.withPacketWriterFire w:
    w.swrite(lcRemoveCachedItem)
    w.swrite(cacheId)

proc addAuth*(loader: FileLoader; url: URL) =
  loader.withPacketWriterFire w:
    w.swrite(lcAddAuth)
    w.swrite(url)

proc addClient*(loader: FileLoader; pid: int; config: LoaderClientConfig;
    clonedFrom: int; isPager = false): SocketStream =
  loader.withPacketWriter w:
    w.swrite(lcAddClient)
    w.swrite(pid)
    w.swrite(config)
    w.swrite(clonedFrom)
  do:
    return nil
  var success = false
  var fd: cint
  loader.withPacketReaderFire r:
    r.sread(success)
    if success and not isPager:
      fd = r.recvFd()
  if success and not isPager:
    return newSocketStream(fd)
  return nil

proc removeClient*(loader: FileLoader; pid: int) =
  loader.withPacketWriterFire w:
    w.swrite(lcRemoveClient)
    w.swrite(pid)

# Equivalent to creating a pipe and passing its read half of it through
# passFd.
proc addPipe*(loader: FileLoader; id: string): PosixStream =
  loader.withPacketWriter w:
    w.swrite(lcAddPipe)
    w.swrite(id)
  do:
    return nil
  var fd: cint = -1
  loader.withPacketReaderFire r:
    var success: bool
    r.sread(success)
    if success:
      fd = r.recvFd()
  if fd != -1:
    return newPosixStream(fd)
  return nil

proc doPipeRequest*(loader: FileLoader; id: string):
    tuple[ps: PosixStream; response: Response] =
  let ps = loader.addPipe(id)
  if ps == nil:
    return (nil, nil)
  let request = newRequest("stream:" & id)
  let response = loader.doRequest(request)
  if response.res != 0:
    ps.sclose()
    return (nil, nil)
  return (ps, response)

proc newFileLoader*(clientPid: int; controlStream: SocketStream):
    FileLoader =
  return FileLoader(
    clientPid: clientPid,
    controlStream: controlStream
  )
