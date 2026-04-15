# Interface to server/loader. The idea is that modules don't have to
# import the entire loader implementation to interact with it.
#
# See server/loader for a more detailed description of the protocol.

{.push raises: [].}

import std/posix

import config/conftypes
import config/cookie
import config/mimetypes
import encoding/charset
import encoding/decoder
import io/dynstream
import io/packetreader
import io/packetwriter
import io/poll
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsutils
import monoucha/quickjs
import monoucha/tojs
import server/headers
import server/request
import types/blob
import types/jsopt
import types/opt
import types/referrer
import types/url
import utils/twtstr

type
  FileLoader* = ref object of RootObj
    clientPid*: int
    map: seq[MapData]
    mapFds*: int # number of fds in map
    pollData*: PollData
    unregistered*: seq[cint]
    # A mechanism to queue up new fds being added to the poll data
    # inside the events iterator.
    registerBlocked: bool
    registerQueue: seq[tuple[data: MapData; events: cshort]]
    # UNIX domain socket to the loader process.
    # We send all messages through this.
    controlStream*: PosixStream

  ConnectDataState* = enum
    cdsBeforeResult, cdsBeforeStatus

  MapData* = ref object of RootObj
    stream*: PosixStream

  LoaderData = ref object of MapData

  FetchFinish* = proc(opaque: RootRef; res: Response) {.nimcall, raises: [].}

  ConnectData* = ref object of LoaderData
    state: ConnectDataState
    outputId: int
    redirectNum: int
    finish: FetchFinish
    opaque*: RootRef
    request: Request

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

  ResponseType* = enum
    rtDefault = "default"
    rtBasic = "basic"
    rtCors = "cors"
    rtError = "error"
    rtOpaque = "opaque"
    rtOpaquedirect = "opaqueredirect"

  ResponseFlag* = enum
    rfAborted, rfBodyUsed, rfResumed

  ResponseFinish* = proc(response: Response; success: bool) {.
    nimcall, raises: [].}

  ResponseRead* = proc(response: Response) {.nimcall, raises: [].}

  Response* = ref object of LoaderData
    flags*: set[ResponseFlag]
    responseType* {.jsget: "type".}: ResponseType
    status* {.jsget.}: uint16
    headers* {.jsget.}: Headers
    url*: URL #TODO should be urllist?
    onRead*: ResponseRead
    onFinish*: ResponseFinish
    outputId*: int
    opaque*: RootRef

  TextResult* = object
    isOk*: bool
    get*: string

  BlobFinish* = proc(opaque: BlobOpaque; blob: Blob) {.nimcall, raises: [].}

  BlobOpaque* = ref object of RootObj
    p: pointer
    len: int
    size: int
    contentType*: string

  JSBlobOpaque = ref object of BlobOpaque
    ctx: JSContext
    resolve: pointer # JSObject *
    reject: pointer # JSObject *

jsDestructor(Response)

# Forward declarations
proc get*(loader: FileLoader; fd: cint): MapData
proc resume*(loader: FileLoader; outputId: int)
proc unregister*(loader: FileLoader; data: MapData)

# Forward declaration hack
var getLoaderImpl*: proc(ctx: JSContext): FileLoader {.nimcall, raises: [].}

template resolveVal(this: BlobOpaque): JSValue =
  JS_MKPTR(JS_TAG_OBJECT, this.resolve)

template rejectVal(this: BlobOpaque): JSValue =
  JS_MKPTR(JS_TAG_OBJECT, this.reject)

proc finalize(rt: JSRuntime; this: Response) {.jsfin.} =
  if this.opaque of JSBlobOpaque:
    let opaque = JSBlobOpaque(this.opaque)
    if opaque.resolve != nil:
      JS_FreeValueRT(rt, opaque.resolveVal)
    if opaque.reject != nil:
      JS_FreeValueRT(rt, opaque.rejectVal)

proc mark(rt: JSRuntime; this: Response; fun: JS_MarkFunc) {.jsmark.} =
  if this.opaque of JSBlobOpaque:
    let opaque = JSBlobOpaque(this.opaque)
    if opaque.resolve != nil:
      JS_MarkValue(rt, opaque.resolveVal, fun)
    if opaque.reject != nil:
      JS_MarkValue(rt, opaque.rejectVal, fun)

template isErr*(x: TextResult): bool =
  not x.isOk

template ok*(t: typedesc[TextResult]; s: string): TextResult =
  TextResult(isOk: true, get: s)

template err*(t: typedesc[TextResult]): TextResult =
  TextResult()

proc toJS*(ctx: JSContext; x: TextResult): JSValue =
  if x.isOk:
    return ctx.toJS(x.get)
  return JS_ThrowTypeError(ctx, "error reading response body")

proc newResponse*(request: Request; stream: PosixStream; outputId: int):
    Response =
  return Response(
    url: if request != nil: request.url else: nil,
    stream: stream,
    outputId: outputId,
    headers: newHeaders(hgResponse),
    status: 200
  )

proc newResponse*(ctx: JSContext; body: JSValueConst = JS_UNDEFINED;
    init: JSValueConst = JS_UNDEFINED): Opt[Response] {.jsctor.} =
  if not JS_IsUndefined(body) or not JS_IsUndefined(init):
    #TODO
    JS_ThrowInternalError(ctx, "Response constructor with body or init")
    return err()
  return ok(newResponse(nil, nil, -1))

proc makeNetworkError*(): Response {.jsstfunc: "Response#error".} =
  #TODO use "create" function
  return Response(
    responseType: rtError,
    status: 0,
    headers: newHeaders(hgImmutable),
    flags: {rfBodyUsed}
  )

proc jsOk(response: Response): bool {.jsfget: "ok".} =
  return response.status in 200u16 .. 299u16

proc surl*(response: Response): string {.jsfget: "url".} =
  if response.responseType == rtError or response.url == nil:
    return ""
  return $response.url

proc bodyUsed*(response: Response): bool {.jsfget.} =
  rfBodyUsed in response.flags

proc getCharset*(this: Response; fallback: Charset): Charset =
  let header = this.headers.getFirst("Content-Type").toLowerAscii()
  if header != "":
    let cs = header.getContentTypeAttr("charset").getCharset()
    if cs != csUnknown:
      return cs
  return fallback

proc getLongContentType*(this: Response; fallback: string): string =
  let header = this.headers.getFirst("Content-Type")
  if header != "":
    return header.toValidUTF8().strip()
  # also use DefaultGuess for container, so that local mime.types cannot
  # override buffer mime.types
  return DefaultGuess.guessContentType(this.url.pathname, fallback)

proc getContentType*(this: Response; fallback = "application/octet-stream"):
    string =
  return this.getLongContentType(fallback).untilLower(';')

proc getContentLength*(this: Response): int64 =
  let x = this.headers.getFirst("Content-Length")
  let u = parseUInt64(x.strip(), allowSign = false).get(uint64.high)
  if u <= uint64(int64.high):
    return int64(u)
  return -1

proc getReferrerPolicy*(this: Response): Opt[ReferrerPolicy] =
  for value in this.headers.getAllCommaSplit("Referrer-Policy"):
    if policy := parseEnumNoCase[ReferrerPolicy](value):
      return ok(policy)
  err()

proc resume*(loader: FileLoader; response: Response) =
  assert rfResumed notin response.flags
  loader.resume(response.outputId)
  response.flags.incl(rfResumed)

proc close*(loader: FileLoader; response: Response) =
  response.flags.incl(rfBodyUsed)
  if response.stream != nil:
    if rfResumed notin response.flags:
      loader.resume(response)
    let fd = response.stream.fd
    let data = loader.get(fd)
    if data != nil:
      loader.unregister(data)
    response.stream.sclose()
    response.stream = nil

const BufferSize = 4096

proc onReadBlob(response: Response) =
  let opaque = BlobOpaque(response.opaque)
  while true:
    if opaque.len + BufferSize > opaque.size:
      opaque.size *= 2
      opaque.p = realloc(opaque.p, opaque.size)
    let p = cast[ptr UncheckedArray[uint8]](opaque.p)
    let diff = opaque.size - opaque.len
    let n = response.stream.read(addr p[opaque.len], diff)
    if n <= 0:
      assert n != -1 or errno != EBADF
      break
    opaque.len += n

proc onFinishBlob*(response: Response; success: bool): Blob =
  let opaque = BlobOpaque(response.opaque)
  if success:
    let p = opaque.p
    opaque.p = nil
    let blob = if p == nil:
      newEmptyBlob(opaque.contentType)
    else:
      newBlob(p, opaque.len, opaque.contentType, deallocBlob)
    return blob
  if opaque.p != nil:
    dealloc(opaque.p)
    opaque.p = nil
  return nil

proc blob*(loader: FileLoader; response: Response; opaque: BlobOpaque) =
  response.opaque = opaque
  if response.bodyUsed:
    response.onFinish(response, false)
    return
  if response.stream == nil:
    response.flags.incl(rfBodyUsed)
    response.onFinish(response, true)
    return
  opaque.contentType = response.getContentType()
  opaque.p = alloc(BufferSize)
  opaque.size = BufferSize
  response.onRead = onReadBlob
  response.flags.incl(rfBodyUsed)
  loader.resume(response)

proc jsFinish0(opaque: JSBlobOpaque; val: JSValue) =
  let ctx = opaque.ctx
  let resolve = opaque.resolveVal
  let reject = opaque.rejectVal
  opaque.resolve = nil
  opaque.reject = nil
  opaque.ctx = nil
  if not JS_IsException(val):
    let res = ctx.callSink(resolve, JS_UNDEFINED, val)
    JS_FreeValue(ctx, res)
  else:
    discard ctx.enqueueRejection(reject)
  JS_FreeValue(ctx, resolve)
  JS_FreeValue(ctx, reject)
  JS_FreeContext(ctx)

proc jsBlobFinish(response: Response; success: bool) =
  let blob = response.onFinishBlob(success)
  let opaque = JSBlobOpaque(response.opaque)
  let ctx = opaque.ctx
  let val = if blob != nil:
    ctx.toJS(blob)
  else:
    JS_ThrowTypeError(ctx, "error reading response body")
  jsFinish0(opaque, val)

proc blob0(ctx: JSContext; response: Response; finish: ResponseFinish):
    JSValue =
  var funs {.noinit.}: array[2, JSValue]
  let res = ctx.newPromiseCapability(funs)
  if JS_IsException(res):
    return res
  let opaque = JSBlobOpaque(
    ctx: JS_DupContext(ctx),
    resolve: JS_VALUE_GET_PTR(funs[0]),
    reject: JS_VALUE_GET_PTR(funs[1])
  )
  response.onFinish = finish
  let loader = ctx.getLoaderImpl()
  loader.blob(response, opaque)
  return res

proc blob(ctx: JSContext; response: Response): JSValue {.jsfunc.} =
  return ctx.blob0(response, jsBlobFinish)

proc onFinishText(response: Response; success: bool) =
  let blob = response.onFinishBlob(success)
  let opaque = JSBlobOpaque(response.opaque)
  let ctx = opaque.ctx
  let val = if blob != nil:
    ctx.toJS(blob.toOpenArray().toValidUTF8())
  else:
    JS_ThrowTypeError(ctx, "error reading response body")
  jsFinish0(opaque, val)

proc text(ctx: JSContext; response: Response): JSValue {.jsfunc.} =
  return ctx.blob0(response, onFinishText)

proc onFinishJSON(response: Response; success: bool) =
  let blob = response.onFinishBlob(success)
  let opaque = JSBlobOpaque(response.opaque)
  let ctx = opaque.ctx
  let val = if blob != nil:
    let s = blob.toOpenArray().toValidUTF8()
    JS_ParseJSON(ctx, cstring(s), csize_t(s.len), cstring"<input>")
  else:
    JS_ThrowTypeError(ctx, "error reading response body")
  jsFinish0(opaque, val)

proc json(ctx: JSContext; this: Response): JSValue {.jsfunc.} =
  return ctx.blob0(this, onFinishJSON)

proc addResponseModule*(ctx: JSContext): JSClassID =
  return ctx.registerType(Response)

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
proc startRequest(loader: FileLoader; request: Request): PosixStream =
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
    let res = newPosixStream(fd)
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

iterator ongoing*(loader: FileLoader): Response {.inline.} =
  for it in loader.data:
    if it of Response:
      yield Response(it)

proc put*(loader: FileLoader; data: MapData) =
  let fd = int(data.stream.fd)
  if loader.map.len <= fd:
    loader.map.setLen(fd + 1)
  assert loader.map[fd] == nil
  loader.map[fd] = data
  if data of LoaderData:
    inc loader.mapFds

proc get*(loader: FileLoader; fd: cint): MapData =
  if fd < loader.map.len:
    return loader.map[fd]
  return nil

proc unset*(loader: FileLoader; fd: cint) =
  if loader.map[fd] != nil and loader.map[fd] of LoaderData:
    dec loader.mapFds
  loader.map[fd] = nil

proc unset*(loader: FileLoader; data: MapData) =
  let fd = data.stream.fd
  if loader.get(fd) != nil:
    loader.unset(fd)

proc hasFds*(loader: FileLoader): bool =
  return loader.mapFds > 0 or loader.registerQueue.len > 0

proc register*(loader: FileLoader; data: MapData; events: cshort) =
  if loader.registerBlocked:
    loader.registerQueue.add((data, events))
  else:
    loader.pollData.register(data.stream.fd, events)
    loader.put(data)

proc register(loader: FileLoader; data: ConnectData) =
  loader.register(data, POLLIN)

proc unregister*(loader: FileLoader; fd: cint) =
  loader.pollData.unregister(fd)
  loader.unregistered.add(fd)

#TODO ideally this should be the only exposed unregister function
# (unset + unregister on fd belong together)
proc unregister*(loader: FileLoader; data: MapData) =
  loader.unset(data)
  loader.unregister(data.stream.fd)

proc blockRegister*(loader: FileLoader) =
  assert not loader.registerBlocked
  loader.registerBlocked = true

proc unblockRegister*(loader: FileLoader) =
  assert loader.registerBlocked
  loader.registerBlocked = false
  for it in loader.registerQueue:
    loader.register(it.data, it.events)
  loader.registerQueue.setLen(0)

proc fetch0(loader: FileLoader; input: Request; finish: FetchFinish;
    opaque: RootRef; redirectNum = 0) =
  let stream = loader.startRequest(input)
  if stream != nil:
    loader.register(ConnectData(
      opaque: opaque,
      finish: finish,
      request: input,
      stream: stream,
      redirectNum: redirectNum
    ))

proc fetch*(loader: FileLoader; input: Request; finish: FetchFinish;
    opaque: RootRef) =
  loader.fetch0(input, finish, opaque, 0)

proc suspend*(loader: FileLoader; fds: seq[int]) =
  loader.withPacketWriterFire w:
    w.swrite(lcSuspend)
    w.swrite(fds)

proc resume*(loader: FileLoader; outputIds: openArray[int]) =
  loader.withPacketWriterFire w:
    w.swrite(lcResume)
    w.swrite(outputIds)

proc resume*(loader: FileLoader; outputId: int) =
  loader.resume([outputId])

proc tee*(loader: FileLoader; sourceId, targetPid: int): (PosixStream, int) =
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
    return (newPosixStream(fd), outputId)
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
  let finish = connectData.finish
  let opaque = connectData.opaque
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
        let fd = connectData.stream.fd
        loader.unregister(fd)
        stream.sclose()
        # delete before resolving the promise
        loader.unset(connectData)
        finish(opaque, nil)
    of cdsBeforeStatus:
      let response = newResponse(request, stream, connectData.outputId)
      # packet 2
      r.sread(response.status)
      r.sreadList(response.headers)
      # Only a stream of the response body may arrive after this point.
      response.stream = stream
      # delete before resolving the promise
      loader.unset(connectData)
      loader.put(response)
      stream.setBlocking(false)
      let redirect = response.getRedirect(request)
      if redirect != nil:
        loader.unregister(response)
        stream.sclose()
        let redirectNum = connectData.redirectNum + 1
        if redirectNum < 5: #TODO use config.network.max_redirect?
          loader.fetch0(redirect, finish, opaque, redirectNum)
        else:
          finish(opaque, nil)
      else:
        finish(opaque, response)
  do: # loader died
    loader.unregister(connectData.stream.fd)
    stream.sclose()
    # delete before resolving the promise
    loader.unset(connectData)
    finish(opaque, nil)

proc onRead*(loader: FileLoader; response: Response) =
  response.onRead(response)
  if response.stream.isend:
    if response.onFinish != nil:
      response.onFinish(response, true)
    response.onFinish = nil
    loader.close(response)

proc onRead*(loader: FileLoader; fd: int) =
  let data = loader.map[fd]
  if data of ConnectData:
    loader.onConnected(ConnectData(data))
  else:
    loader.onRead(Response(data))

proc onError*(loader: FileLoader; response: Response) =
  if response.onFinish != nil:
    response.onFinish(response, true)
  response.onFinish = nil
  loader.close(response)

proc onError*(loader: FileLoader; fd: int): bool =
  let data = loader.map[fd]
  if data of ConnectData:
    # probably shouldn't happen. TODO
    return false
  else:
    loader.onError(Response(data))
    return true

# Note: this blocks until headers are received.
proc doRequest*(loader: FileLoader; request: Request): Response =
  let stream = loader.startRequest(request)
  let response = newResponse(request, nil, -1)
  var r: PacketReader
  if stream != nil and stream.initPacketReader(r):
    var res: int
    r.sread(res) # packet 1
    if res == 0:
      r.sread(response.outputId) # packet 1
      if stream.initPacketReader(r): # packet 2
        r.sread(response.status)
        r.sreadList(response.headers)
        # Only a stream of the response body may arrive after this point.
        response.stream = stream
      else: # EOF
        stream.sclose()
    else:
      var msg: string
      r.sread(msg) # packet 1
      stream.sclose()
  else: # EOF
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

proc addClient*(loader: FileLoader; pid: int; config: LoaderClientConfig):
    PosixStream =
  loader.withPacketWriter w:
    w.swrite(lcAddClient)
    w.swrite(pid)
    w.swrite(config)
  do:
    return nil
  var success = false
  var fd: cint
  loader.withPacketReaderFire r:
    r.sread(success)
    if success:
      fd = r.recvFd()
  if success:
    return newPosixStream(fd)
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
  if response.stream == nil:
    ps.sclose()
    return (nil, nil)
  return (ps, response)

proc newFileLoader*(clientPid: int; controlStream: PosixStream):
    FileLoader =
  return FileLoader(
    clientPid: clientPid,
    controlStream: controlStream
  )

{.pop.}
