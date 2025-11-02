{.push raises: [].}

import std/options

import html/script
import io/packetreader
import io/packetwriter
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsnull
import monoucha/jstypes
import monoucha/quickjs
import monoucha/tojs
import server/headers
import types/blob
import types/formdata
import types/jsopt
import types/opt
import types/referrer
import types/url

type
  HttpMethod* = enum
    hmGet = "GET"
    hmConnect = "CONNECT"
    hmDelete = "DELETE"
    hmHead = "HEAD"
    hmOptions = "OPTIONS"
    hmPatch = "PATCH"
    hmPost = "POST"
    hmPut = "PUT"
    hmTrace = "TRACE"

  RequestMode* = enum
    rmNoCors = "no-cors"
    rmSameOrigin = "same-origin"
    rmCors = "cors"
    rmNavigate = "navigate"
    rmWebsocket = "websocket"

  CORSAttribute* = enum
    caNoCors = "no-cors"
    caAnonymous = "anonymous"
    caUseCredentials = "use-credentials"

type
  RequestOriginType* = enum
    rotClient, rotOrigin

  RequestOrigin* = object
    case t*: RequestOriginType
    of rotClient: discard
    of rotOrigin:
      origin*: Origin

  RequestWindowType* = enum
    rwtClient, rwtNoWindow, rwtWindow

  RequestWindow* = object
    case t*: RequestWindowType
    of rwtClient, rwtNoWindow: discard
    of rwtWindow:
      window*: EnvironmentSettings

  RequestBodyType* = enum
    rbtNone, rbtString, rbtBlob, rbtMultipart, rbtOutput, rbtCache

  RequestBody* = object
    case t*: RequestBodyType
    of rbtNone:
      discard
    of rbtString:
      s*: string
    of rbtMultipart:
      multipart*: FormData
    of rbtOutput:
      outputId*: int
    of rbtCache:
      cacheId*: int
    of rbtBlob:
      blob*: Blob

  Request* = ref object
    httpMethod*: HttpMethod
    url*: URL
    headers*: Headers
    body*: RequestBody
    tocache*: bool
    credentialsMode*: CredentialsMode

  JSRequest* = ref object
    request*: Request
    mode* {.jsget.}: RequestMode
    destination* {.jsget.}: RequestDestination
    origin*: RequestOrigin
    window*: RequestWindow
    client*: Option[EnvironmentSettings]

jsDestructor(JSRequest)

# Forward declaration hack
var getAPIBaseURLImpl*: proc(ctx: JSContext): URL {.nimcall, raises: [].}

proc swrite*(w: var PacketWriter; o: RequestBody) =
  w.swrite(o.t)
  case o.t
  of rbtNone: discard
  of rbtString: w.swrite(o.s)
  of rbtBlob: w.swrite(o.blob)
  of rbtMultipart: w.swrite(o.multipart)
  of rbtOutput: w.swrite(o.outputId)
  of rbtCache: w.swrite(o.cacheId)

proc sread*(r: var PacketReader; o: var RequestBody) =
  var t: RequestBodyType
  r.sread(t)
  o = RequestBody(t: t)
  case t
  of rbtNone: discard
  of rbtString: r.sread(o.s)
  of rbtBlob: r.sread(o.blob)
  of rbtMultipart: r.sread(o.multipart)
  of rbtOutput: r.sread(o.outputId)
  of rbtCache: r.sread(o.cacheId)

proc contentLength*(body: RequestBody): int =
  case body.t
  of rbtNone: return 0
  of rbtString: return body.s.len
  of rbtBlob: return body.blob.size
  of rbtMultipart: return body.multipart.calcLength()
  of rbtOutput: return 0
  of rbtCache: return 0

proc headers(this: JSRequest): Headers {.jsfget.} =
  return this.request.headers

proc url(this: JSRequest): URL =
  return this.request.url

proc jsUrl(this: JSRequest): string {.jsfget: "url".} =
  return $this.url

proc credentialsMode(this: JSRequest): string {.jsfget.} =
  return $this.request.credentialsMode

#TODO pretty sure this is incorrect
proc referrer(this: JSRequest): string {.jsfget.} =
  return this.request.headers.getFirst("Referer")

proc getReferrer*(this: Request): URL =
  return parseURL0(this.headers.getFirst("Referer"))

proc takeReferrer*(this: Request; policy: ReferrerPolicy): string =
  let url = parseURL0(this.headers.takeFirstRemoveAll("Referer"))
  if url != nil:
    return url.getReferrer(this.url, policy)
  return ""

proc newRequest*(url: URL; httpMethod = hmGet; headers = newHeaders(hgRequest);
    body = RequestBody(); referrer: URL = nil; tocache = false;
    credentialsMode = cmSameOrigin): Request =
  assert url != nil
  if referrer != nil:
    headers["Referer"] = $referrer
  return Request(
    url: url,
    httpMethod: httpMethod,
    headers: headers,
    body: body,
    tocache: tocache,
    credentialsMode: credentialsMode
  )

proc newRequest*(s: string; httpMethod = hmGet; headers = newHeaders(hgRequest);
    body = RequestBody(); referrer: URL = nil; tocache = false;
    credentialsMode = cmSameOrigin): Request =
  return newRequest(parseURL0(s), httpMethod, headers, body, referrer, tocache,
    credentialsMode)

proc createPotentialCORSRequest*(url: URL; destination: RequestDestination;
    cors: CORSAttribute; fallbackFlag = false): JSRequest =
  var mode = if cors == caNoCors:
    rmNoCors
  else:
    rmCors
  if fallbackFlag and mode == rmNoCors:
    mode = rmSameOrigin
  let credentialsMode = if cors == caAnonymous: cmSameOrigin else: cmInclude
  return JSRequest(
    request: newRequest(url, credentialsMode = credentialsMode),
    destination: destination,
    mode: mode
  )

type
  BodyInitType = enum
    bitNull, bitBlob, bitFormData, bitUrlSearchParams, bitString

  BodyInit* = object
    #TODO ReadableStream, BufferSource
    case t: BodyInitType
    of bitNull: discard
    of bitBlob:
      blob: Blob
    of bitFormData:
      formData: FormData
    of bitUrlSearchParams:
      searchParams: URLSearchParams
    of bitString:
      s: string

  RequestInit* = object of JSDict
    `method`* {.jsdefault.}: Option[HttpMethod] #TODO aliasing in dicts
    headers* {.jsdefault.}: HeadersInit
    body* {.jsdefault.}: BodyInit
    referrer* {.jsdefault.}: Option[string]
    referrerPolicy* {.jsdefault.}: Option[ReferrerPolicy]
    credentials* {.jsdefault.}: Option[CredentialsMode]
    mode* {.jsdefault.}: Option[RequestMode]
    window* {.jsdefault: JS_UNDEFINED.}: JSValueConst

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var BodyInit):
    FromJSResult =
  if JS_IsNull(val):
    res = BodyInit(t: bitNull)
    return fjOk
  res = BodyInit(t: bitFormData)
  if ctx.fromJS(val, res.formData).isOk:
    return fjOk
  res = BodyInit(t: bitBlob)
  if ctx.fromJS(val, res.blob).isOk:
    return fjOk
  res = BodyInit(t: bitUrlSearchParams)
  if ctx.fromJS(val, res.searchParams).isOk:
    return fjOk
  res = BodyInit(t: bitString)
  ctx.fromJS(val, res.s)

# Returns the content type
proc extract*(init: BodyInit; body: var RequestBody): string =
  case init.t
  of bitNull: return ""
  of bitFormData:
    body = RequestBody(t: rbtMultipart, multipart: init.formData)
    return init.formData.getContentType()
  of bitString:
    body = RequestBody(t: rbtString, s: init.s)
    return "text/plain;charset=UTF-8"
  of bitUrlSearchParams:
    body = RequestBody(t: rbtString, s: $init.searchParams)
    return "application/x-www-form-urlencoded;charset=UTF-8"
  of bitBlob:
    body = RequestBody(t: rbtBlob, blob: init.blob)
    return init.blob.ctype

proc safeExtract*(init: BodyInit; body: var RequestBody): string =
  #TODO check for ReadableStream once we have it
  init.extract(body)

proc newRequest*(ctx: JSContext; resource: JSValueConst;
    init = RequestInit(window: JS_UNDEFINED)): Opt[JSRequest] {.jsctor.} =
  var headers = newHeaders(hgRequest)
  var fallbackMode = opt(rmCors)
  var window = RequestWindow(t: rwtClient)
  var body = RequestBody()
  var credentials = cmSameOrigin
  var httpMethod = hmGet
  var referrer: URL = nil
  var url: URL = nil
  if (var res: JSRequest; ctx.fromJS(resource, res).isOk):
    url = res.url
    httpMethod = res.request.httpMethod
    headers[] = res.headers[]
    referrer = res.request.getReferrer()
    credentials = res.request.credentialsMode
    body = res.request.body
    fallbackMode = opt(RequestMode)
    window = res.window
  else:
    var s: string
    ?ctx.fromJS(resource, s)
    url = ?ctx.parseJSURL(s, ctx.getAPIBaseURLImpl())
  if url.username != "" or url.password != "":
    JS_ThrowTypeError(ctx, "input URL contains a username or password")
    return err()
  var mode = fallbackMode.get(rmNoCors)
  let destination = rdNone
  #TODO origin, window
  if not JS_IsUndefined(init.window):
    if not JS_IsNull(init.window):
      JS_ThrowTypeError(ctx, "expected window to be null")
      return err()
    window = RequestWindow(t: rwtNoWindow)
  if mode == rmNavigate:
    mode = rmSameOrigin
  #TODO flags?
  #TODO referrer
  if init.`method`.isSome:
    httpMethod = init.`method`.get
  if init.body.t != bitNull and httpMethod in {hmGet, hmHead}:
    JS_ThrowTypeError(ctx, "HEAD or GET requests cannot have a body")
    return err()
  ?ctx.fill(headers, init.headers)
  let contentType = init.body.extract(body)
  if contentType != "":
    headers.addIfNotFound("Content-Type", contentType)
  if init.credentials.isSome:
    credentials = init.credentials.get
  if init.mode.isSome:
    mode = init.mode.get
  if mode == rmNoCors:
    headers.guard = hgRequestNoCors
  return ok(JSRequest(
    request: newRequest(
      url,
      httpMethod,
      headers,
      body,
      referrer = referrer,
      credentialsMode = credentials
    ),
    mode: mode,
    destination: destination,
    window: window
  ))

proc credentialsMode*(attribute: CORSAttribute): CredentialsMode =
  case attribute
  of caNoCors, caAnonymous:
    return cmSameOrigin
  of caUseCredentials:
    return cmInclude

proc addRequestModule*(ctx: JSContext) =
  ctx.registerType(JSRequest, name = "Request")

{.pop.} # raises: []
