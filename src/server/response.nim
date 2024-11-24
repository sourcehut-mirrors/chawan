import std/strutils
import std/tables

import chagashi/charset
import chagashi/decoder
import io/dynstream
import io/promise
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
import utils/mimeguess
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
    body*: SocketStream
    bodyUsed* {.jsget.}: bool
    status* {.jsget.}: uint16
    headers* {.jsget.}: Headers
    url*: URL #TODO should be urllist?
    unregisterFun*: proc()
    resumeFun*: proc(outputId: int)
    internalMessage*: string # should NOT be exposed to JS!
    outputId*: int
    onRead*: proc(response: Response) {.nimcall.}
    onFinish*: proc(response: Response; success: bool) {.nimcall.}
    opaque*: RootRef
    flags*: set[ResponseFlag]

  FetchPromise* = Promise[JSResult[Response]]

jsDestructor(Response)

proc newResponse*(res: int; request: Request; stream: SocketStream;
    outputId: int; status: uint16): Response =
  return Response(
    res: res,
    url: request.url,
    body: stream,
    outputId: outputId,
    status: status
  )

func makeNetworkError*(): Response {.jsstfunc: "Response.error".} =
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

func sok(response: Response): bool {.jsfget: "ok".} =
  return response.status in 200u16 .. 299u16

func surl*(response: Response): string {.jsfget: "url".} =
  if response.responseType == rtError or response.url == nil:
    return ""
  return $response.url

#TODO: this should be a property of body
proc close*(response: Response) {.jsfunc.} =
  response.bodyUsed = true
  if response.unregisterFun != nil:
    response.unregisterFun()
    response.unregisterFun = nil
  if response.body != nil:
    response.body.sclose()
    response.body = nil

func getCharset*(this: Response; fallback: Charset): Charset =
  this.headers.table.withValue("Content-Type", p):
    let header = p[][0].toLowerAscii()
    let cs = header.getContentTypeAttr("charset").getCharset()
    if cs != CHARSET_UNKNOWN:
      return cs
  return fallback

func getContentType*(this: Response; fallback = "application/octet-stream"):
    string =
  this.headers.table.withValue("Content-Type", p):
    return p[][0].untilLower(';').strip()
  # also use DefaultGuess for container, so that local mime.types cannot
  # override buffer mime.types
  return DefaultGuess.guessContentType(this.url.pathname, fallback)

func getContentLength*(this: Response): int64 =
  this.headers.table.withValue("Content-Length", p):
    for x in p[]:
      let u = parseUInt64(x.strip(), allowSign = false)
      if u.isSome and u.get <= uint64(int64.high):
        return int64(u.get)
  return -1

func getReferrerPolicy*(this: Response): Option[ReferrerPolicy] =
  this.headers.table.withValue("Referrer-Policy", p):
    return strictParseEnum[ReferrerPolicy](p[][0])

proc resume*(response: Response) =
  response.resumeFun(response.outputId)
  response.resumeFun = nil

type TextOpaque = ref object of RootObj
  buf: string
  bodyRead: Promise[JSResult[string]]

const BufferSize = 4096

proc onReadText(response: Response) =
  let opaque = TextOpaque(response.opaque)
  while true:
    let olen = opaque.buf.len
    try:
      opaque.buf.setLen(olen + BufferSize)
      let n = response.body.recvData(addr opaque.buf[olen], BufferSize)
      opaque.buf.setLen(olen + n)
      if n == 0:
        break
    except ErrorAgain:
      opaque.buf.setLen(olen)
      break

proc onFinishText(response: Response; success: bool) =
  let opaque = TextOpaque(response.opaque)
  let bodyRead = opaque.bodyRead
  if success:
    let charset = response.getCharset(CHARSET_UTF_8)
    bodyRead.resolve(JSResult[string].ok(opaque.buf.decodeAll(charset)))
  else:
    bodyRead.resolve(JSResult[string].err(newFetchTypeError()))

proc text*(response: Response): Promise[JSResult[string]] {.jsfunc.} =
  if response.body == nil:
    return newResolvedPromise(JSResult[string].ok(""))
  if response.bodyUsed:
    let err = newTypeError("Body has already been consumed")
    return newResolvedPromise(JSResult[string].err(err))
  let opaque = TextOpaque(bodyRead: Promise[JSResult[string]]())
  response.opaque = opaque
  response.onRead = onReadText
  response.onFinish = onFinishText
  response.bodyUsed = true
  response.resume()
  return opaque.bodyRead

type BlobOpaque = ref object of RootObj
  p: pointer
  len: int
  size: int
  bodyRead: Promise[JSResult[Blob]]
  contentType: string

proc onReadBlob(response: Response) =
  let opaque = BlobOpaque(response.opaque)
  while true:
    try:
      if opaque.len + BufferSize > opaque.size:
        opaque.size *= 2
        opaque.p = realloc(opaque.p, opaque.size)
      let p = cast[ptr UncheckedArray[uint8]](opaque.p)
      let diff = opaque.size - opaque.len
      let n = response.body.recvData(addr p[opaque.len], diff)
      opaque.len += n
      if n == 0:
        break
    except ErrorAgain:
      break

proc onFinishBlob(response: Response; success: bool) =
  let opaque = BlobOpaque(response.opaque)
  let bodyRead = opaque.bodyRead
  if success:
    let p = realloc(opaque.p, opaque.len)
    opaque.p = nil
    let blob = if p == nil:
      newBlob(nil, 0, opaque.contentType, nil)
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

proc json(ctx: JSContext; this: Response): Promise[JSValue] {.jsfunc.} =
  return this.text().then(proc(s: JSResult[string]): JSValue =
    if s.isNone:
      return ctx.toJS(s.error)
    return JS_ParseJSON(ctx, cstring(s.get), csize_t(s.get.len),
      cstring"<input>")
  )

proc addResponseModule*(ctx: JSContext) =
  ctx.registerType(Response)
