{.push raises: [].}

import std/posix
import std/strutils

import chagashi/charset
import chagashi/decoder
import config/mimetypes
import io/dynstream
import io/promise
import monoucha/fromjs
import monoucha/jsbind
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

  FetchResult* = object
    get*: Response

  BlobResult* = object
    get*: Blob

  TextResult* = object
    isOk*: bool
    get*: string

  FetchPromise* = Promise[FetchResult]

jsDestructor(Response)

template isOk*(x: FetchResult): bool =
  x.get != nil

template isErr*(x: FetchResult): bool =
  x.get == nil

template ok*(t: typedesc[FetchResult]; x: Response): FetchResult =
  FetchResult(get: x)

template err*(t: typedesc[FetchResult]): FetchResult =
  FetchResult(get: nil)

proc toJS*(ctx: JSContext; x: FetchResult): JSValue =
  if x.isOk:
    return ctx.toJS(x.get)
  return JS_ThrowTypeError(ctx,
    "NetworkError when attempting to fetch resource")

template isOk*(x: BlobResult): bool =
  x.get != nil

template isErr*(x: BlobResult): bool =
  x.get == nil

template ok*(t: typedesc[BlobResult]; x: Blob): BlobResult =
  BlobResult(get: x)

template err*(t: typedesc[BlobResult]): BlobResult =
  BlobResult(get: nil)

proc toJS*(ctx: JSContext; x: BlobResult): JSValue =
  if x.isOk:
    return ctx.toJS(x.get)
  return JS_ThrowTypeError(ctx, "error reading response body")

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

proc newResponse*(res: int; request: Request; stream: PosixStream;
    outputId: int): Response =
  return Response(
    res: res,
    url: if request != nil: request.url else: nil,
    body: stream,
    outputId: outputId,
    status: 200
  )

proc newResponse*(ctx: JSContext; body: JSValueConst = JS_UNDEFINED;
    init: JSValueConst = JS_UNDEFINED): Opt[Response] {.jsctor.} =
  if not JS_IsUndefined(body) or not JS_IsUndefined(init):
    #TODO
    JS_ThrowInternalError(ctx, "Response constructor with body or init")
    return err()
  return ok(newResponse(0, nil, nil, -1))

proc makeNetworkError*(): Response {.jsstfunc: "Response#error".} =
  #TODO use "create" function
  return Response(
    res: 0,
    responseType: rtError,
    status: 0,
    headers: newHeaders(hgImmutable),
    bodyUsed: true
  )

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

proc resume*(response: Response) =
  response.resumeFun(response.outputId)
  response.resumeFun = nil

const BufferSize = 4096

type BlobOpaque = ref object of RootObj
  p: pointer
  len: int
  size: int
  bodyRead: Promise[BlobResult]
  contentType: string

proc onReadBlob(response: Response) =
  let opaque = BlobOpaque(response.opaque)
  while true:
    if opaque.len + BufferSize > opaque.size:
      opaque.size *= 2
      opaque.p = realloc(opaque.p, opaque.size)
    let p = cast[ptr UncheckedArray[uint8]](opaque.p)
    let diff = opaque.size - opaque.len
    let n = response.body.read(addr p[opaque.len], diff)
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
    bodyRead.resolve(BlobResult.ok(blob))
  else:
    if opaque.p != nil:
      dealloc(opaque.p)
      opaque.p = nil
    bodyRead.resolve(BlobResult.err())

proc blob*(response: Response): Promise[BlobResult] {.jsfunc.} =
  if response.bodyUsed:
    return newResolvedPromise(BlobResult.err())
  if response.body == nil:
    response.bodyUsed = true
    return newResolvedPromise(BlobResult.ok(newEmptyBlob()))
  let opaque = BlobOpaque(
    bodyRead: Promise[BlobResult](),
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

proc text*(response: Response): Promise[TextResult] {.jsfunc.} =
  return response.blob().then(proc(res: BlobResult): TextResult =
    if res.isErr:
      return TextResult.err()
    TextResult.ok(res.get.toOpenArray().toValidUTF8())
  )

proc cssDecode(iq: openArray[char]; fallback: Charset): string =
  var charset = fallback
  var offset = 0
  const charsetRule = "@charset \""
  if iq.startsWith2("\xFE\xFF"):
    charset = CHARSET_UTF_16_BE
    offset = 2
  elif iq.startsWith2("\xFF\xFE"):
    charset = CHARSET_UTF_16_LE
    offset = 2
  elif iq.startsWith2("\xEF\xBB\xBF"):
    charset = CHARSET_UTF_8
    offset = 3
  elif iq.startsWith2(charsetRule):
    let s = iq.toOpenArray(charsetRule.len, min(1024, iq.high)).until('"')
    let n = charsetRule.len + s.len
    if n >= 0 and n + 1 < iq.len and iq[n] == '"' and iq[n + 1] == ';':
      charset = getCharset(s)
      if charset in {CHARSET_UTF_16_LE, CHARSET_UTF_16_BE}:
        charset = CHARSET_UTF_8
  iq.toOpenArray(offset, iq.high).decodeAll(charset)

proc cssText*(response: Response; fallback: Charset): Promise[TextResult] =
  return response.blob().then(proc(res: BlobResult): TextResult =
    if res.isErr:
      return TextResult.err()
    TextResult.ok(res.get.toOpenArray().cssDecode(fallback))
  )

proc json(ctx: JSContext; this: Response): Promise[JSValue] {.jsfunc.} =
  return this.text().then(proc(s: TextResult): JSValue =
    if s.isErr:
      return ctx.toJS(s)
    return JS_ParseJSON(ctx, cstring(s.get), csize_t(s.get.len),
      cstring"<input>")
  )

proc addResponseModule*(ctx: JSContext) =
  ctx.registerType(Response)

{.pop.} # raises: []
