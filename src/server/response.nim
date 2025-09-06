{.push raises: [].}

import std/options
import std/posix
import std/strutils

import chagashi/charset
import chagashi/decoder
import config/mimetypes
import io/dynstream
import io/promise
import monoucha/fromjs
import monoucha/javascript
import monoucha/jserror
import monoucha/quickjs
import monoucha/tojs
import server/headers
import server/request
import types/blob
import types/opt
import types/referrer
import types/url
import utils/twtstr

type
  ResponseType* = enum
    rtDefault = "default"
    rtBasic = "basic"
    rtCors = "cors"
    rtError = "error"
    rtOpaque = "opaque"
    rtOpaquedirect = "opaqueredirect"

  ResponseFlag* = enum
    rfAborted

  Response* = ref object
    responseType* {.jsget: "type".}: ResponseType
    res*: int
    body*: PosixStream
    bodyUsed* {.jsget.}: bool
    status* {.jsget.}: uint16
    headers* {.jsget.}: Headers
    url*: URL #TODO should be urllist?
    unregisterFun*: proc() {.raises: [].}
    resumeFun*: proc(outputId: int)
    internalMessage*: string # should NOT be exposed to JS!
    outputId*: int
    onRead*: proc(response: Response) {.nimcall, raises: [].}
    onFinish*: proc(response: Response; success: bool) {.nimcall, raises: [].}
    opaque*: RootRef
    flags*: set[ResponseFlag]

  FetchPromise* = Promise[JSResult[Response]]

jsDestructor(Response)

proc newResponse*(res: int; request: Request; stream: PosixStream;
    outputId: int): Response =
  return Response(
    res: res,
    url: if request != nil: request.url else: nil,
    body: stream,
    outputId: outputId,
    status: 200
  )

proc newResponse*(body: JSValueConst = JS_UNDEFINED;
    init: JSValueConst = JS_UNDEFINED): JSResult[Response] {.jsctor.} =
  if not JS_IsUndefined(body) or not JS_IsUndefined(init):
    #TODO
    return errInternalError("Response constructor with body or init")
  return ok(newResponse(0, nil, nil, -1))

proc makeNetworkError*(): Response {.jsstfunc: "Response.error".} =
  #TODO use "create" function
  return Response(
    res: 0,
    responseType: rtError,
    status: 0,
    headers: newHeaders(hgImmutable),
    bodyUsed: true
  )

proc newFetchTypeError*(): JSError =
  return newTypeError("NetworkError when attempting to fetch resource")

proc jsOk(response: Response): bool {.jsfget: "ok".} =
  return response.status in 200u16 .. 299u16

proc surl*(response: Response): string {.jsfget: "url".} =
  if response.responseType == rtError or response.url == nil:
    return ""
  return $response.url

#TODO: this should be a property of body
proc close*(response: Response) =
  response.bodyUsed = true
  if response.resumeFun != nil:
    response.resumeFun(response.outputId)
    response.resumeFun = nil
  if response.unregisterFun != nil:
    response.unregisterFun()
    response.unregisterFun = nil
  if response.body != nil:
    response.body.sclose()
    response.body = nil

proc getCharset*(this: Response; fallback: Charset): Charset =
  let header = this.headers.getFirst("Content-Type").toLowerAscii()
  if header != "":
    let cs = header.getContentTypeAttr("charset").getCharset()
    if cs != CHARSET_UNKNOWN:
      return cs
  return fallback

proc getLongContentType*(this: Response; fallback: string): string =
  let header = this.headers.getFirst("Content-Type")
  if header != "":
    return header.toValidUTF8().toLowerAscii().strip()
  # also use DefaultGuess for container, so that local mime.types cannot
  # override buffer mime.types
  return DefaultGuess.guessContentType(this.url.pathname, fallback)

proc getContentType*(this: Response; fallback = "application/octet-stream"):
    string =
  return this.getLongContentType(fallback).until(';')

proc getContentLength*(this: Response): int64 =
  let x = this.headers.getFirst("Content-Length")
  let u = parseUInt64(x.strip(), allowSign = false).get(uint64.high)
  if u <= uint64(int64.high):
    return int64(u)
  return -1

proc getReferrerPolicy*(this: Response): Option[ReferrerPolicy] =
  let header = this.headers.getFirst("Referrer-Policy")
  if p := strictParseEnum[ReferrerPolicy](header):
    return some(p)
  none(ReferrerPolicy)

proc resume*(response: Response) =
  response.resumeFun(response.outputId)
  response.resumeFun = nil

const BufferSize = 4096

type BlobOpaque = ref object of RootObj
  p: pointer
  len: int
  size: int
  bodyRead: Promise[JSResult[Blob]]
  contentType: string

proc onReadBlob(response: Response) =
  let opaque = BlobOpaque(response.opaque)
  while true:
    if opaque.len + BufferSize > opaque.size:
      opaque.size *= 2
      opaque.p = realloc(opaque.p, opaque.size)
    let p = cast[ptr UncheckedArray[uint8]](opaque.p)
    let diff = opaque.size - opaque.len
    let n = response.body.readData(addr p[opaque.len], diff)
    if n <= 0:
      assert n != -1 or errno != EBADF
      break
    opaque.len += n

proc onFinishBlob(response: Response; success: bool) =
  let opaque = BlobOpaque(response.opaque)
  let bodyRead = opaque.bodyRead
  if success:
    let p = opaque.p
    opaque.p = nil
    let blob = if p == nil:
      newEmptyBlob(opaque.contentType)
    else:
      newBlob(p, opaque.len, opaque.contentType, deallocBlob)
    bodyRead.resolve(JSResult[Blob].ok(blob))
  else:
    if opaque.p != nil:
      dealloc(opaque.p)
      opaque.p = nil
    let res = newTypeError("Error reading response")
    bodyRead.resolve(JSResult[Blob].err(res))

proc blob*(response: Response): Promise[JSResult[Blob]] {.jsfunc.} =
  if response.bodyUsed:
    let err = JSResult[Blob].err(newTypeError("Body has already been consumed"))
    return newResolvedPromise(err)
  if response.body == nil:
    response.bodyUsed = true
    return newResolvedPromise(JSResult[Blob].ok(newEmptyBlob()))
  let opaque = BlobOpaque(
    bodyRead: Promise[JSResult[Blob]](),
    contentType: response.getContentType(),
    p: alloc(BufferSize),
    size: BufferSize
  )
  response.opaque = opaque
  response.onRead = onReadBlob
  response.onFinish = onFinishBlob
  response.bodyUsed = true
  response.resume()
  return opaque.bodyRead

proc text*(response: Response): Promise[JSResult[string]] {.jsfunc.} =
  return response.blob().then(proc(res: JSResult[Blob]): JSResult[string] =
    let blob = ?res
    return ok(blob.toOpenArray().toValidUTF8())
  )

proc json(ctx: JSContext; this: Response): Promise[JSValue] {.jsfunc.} =
  return this.text().then(proc(s: JSResult[string]): JSValue =
    if s.isErr:
      return ctx.toJS(s.error)
    return JS_ParseJSON(ctx, cstring(s.get), csize_t(s.get.len),
      cstring"<input>")
  )

proc addResponseModule*(ctx: JSContext) =
  ctx.registerType(Response)

{.pop.} # raises: []
