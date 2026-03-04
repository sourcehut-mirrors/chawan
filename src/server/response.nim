{.push raises: [].}

import std/posix

import chagashi/charset
import chagashi/decoder
import config/mimetypes
import io/dynstream
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
  ResponseType* = enum
    rtDefault = "default"
    rtBasic = "basic"
    rtCors = "cors"
    rtError = "error"
    rtOpaque = "opaque"
    rtOpaquedirect = "opaqueredirect"

  ResponseFlag* = enum
    rfAborted

  ResponseFinish* = proc(response: Response; success: bool) {.
    nimcall, raises: [].}

  Response* = ref object
    body*: PosixStream
    flags*: set[ResponseFlag]
    responseType* {.jsget: "type".}: ResponseType
    bodyUsed* {.jsget.}: bool
    status* {.jsget.}: uint16
    headers* {.jsget.}: Headers
    url*: URL #TODO should be urllist?
    resumeFun*: proc(outputId: int)
    onRead*: proc(response: Response) {.nimcall, raises: [].}
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
    body: stream,
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
    bodyUsed: true
  )

proc jsOk(response: Response): bool {.jsfget: "ok".} =
  return response.status in 200u16 .. 299u16

proc surl*(response: Response): string {.jsfget: "url".} =
  if response.responseType == rtError or response.url == nil:
    return ""
  return $response.url

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

proc blob*(response: Response; opaque: BlobOpaque) =
  response.opaque = opaque
  if response.bodyUsed:
    response.onFinish(response, false)
    return
  if response.body == nil:
    response.bodyUsed = true
    response.onFinish(response, true)
    return
  opaque.contentType = response.getContentType()
  opaque.p = alloc(BufferSize)
  opaque.size = BufferSize
  response.onRead = onReadBlob
  response.bodyUsed = true
  response.resume()

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
  response.blob(opaque)
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

{.pop.} # raises: []
