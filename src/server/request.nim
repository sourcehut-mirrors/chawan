{.push raises: [].}

import std/options

import html/script
import io/packetreader
import io/packetwriter
import monoucha/fromjs
import monoucha/javascript
import monoucha/jserror
import monoucha/jstypes
import monoucha/quickjs
import monoucha/tojs
import server/headers
import types/blob
import types/formdata
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
    rbtNone, rbtString, rbtMultipart, rbtOutput, rbtCache

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
  of rbtMultipart: r.sread(o.multipart)
  of rbtOutput: r.sread(o.outputId)
  of rbtCache: r.sread(o.cacheId)

proc contentLength*(body: RequestBody): int =
  case body.t
  of rbtNone: return 0
  of rbtString: return body.s.len
  of rbtMultipart: return body.multipart.calcLength()
  of rbtOutput: return 0
  of rbtCache: return 0

func headers(this: JSRequest): Headers {.jsfget.} =
  return this.request.headers

func url(this: JSRequest): URL =
  return this.request.url

proc jsUrl(this: JSRequest): string {.jsfget: "url".} =
  return $this.url

func credentialsMode(this: JSRequest): string {.jsfget.} =
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

func newRequest*(url: URL; httpMethod = hmGet; headers = newHeaders(hgRequest);
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

func createPotentialCORSRequest*(url: URL; destination: RequestDestination;
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
    bitBlob, bitFormData, bitUrlSearchParams, bitString

  BodyInit = object
    #TODO ReadableStream, BufferSource
    case t: BodyInitType
    of bitBlob:
      blob: Blob
    of bitFormData:
      formData: FormData
    of bitUrlSearchParams:
      searchParams: URLSearchParams
    of bitString:
      str: string

  RequestInit* = object of JSDict
    `method`* {.jsdefault.}: Option[HttpMethod] #TODO aliasing in dicts
    headers* {.jsdefault.}: Option[HeadersInit]
    body* {.jsdefault.}: Option[BodyInit]
    referrer* {.jsdefault.}: Option[string]
    referrerPolicy* {.jsdefault.}: Option[ReferrerPolicy]
    credentials* {.jsdefault.}: Option[CredentialsMode]
    mode* {.jsdefault.}: Option[RequestMode]
    window* {.jsdefault: JS_UNDEFINED.}: JSValueConst

proc fromJS(ctx: JSContext; val: JSValueConst; res: var BodyInit): Opt[void] =
  if not JS_IsUndefined(val) and not JS_IsNull(val):
    res = BodyInit(t: bitFormData)
    if ctx.fromJS(val, res.formData).isOk:
      return ok()
    res = BodyInit(t: bitBlob)
    if ctx.fromJS(val, res.blob).isOk:
      return ok()
    res = BodyInit(t: bitUrlSearchParams)
    if ctx.fromJS(val, res.searchParams).isOk:
      return ok()
    res = BodyInit(t: bitString)
    if ctx.fromJS(val, res.str).isOk:
      return ok()
  JS_ThrowTypeError(ctx, "invalid body init type")
  return err()

proc newRequest*(ctx: JSContext; resource: JSValueConst;
    init = RequestInit(window: JS_UNDEFINED)): JSResult[JSRequest] {.jsctor.} =
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
    url = ?parseJSURL(s, option(ctx.getAPIBaseURLImpl()))
  if url.username != "" or url.password != "":
    return errTypeError("Input URL contains a username or password")
  var mode = fallbackMode.get(rmNoCors)
  let destination = rdNone
  #TODO origin, window
  if not JS_IsUndefined(init.window):
    if not JS_IsNull(init.window):
      return errTypeError("Expected window to be null")
    window = RequestWindow(t: rwtNoWindow)
  if mode == rmNavigate:
    mode = rmSameOrigin
  #TODO flags?
  #TODO referrer
  if init.`method`.isSome:
    httpMethod = init.`method`.get
  if init.body.isSome:
    let ibody = init.body.get
    case ibody.t
    of bitFormData:
      body = RequestBody(t: rbtMultipart, multipart: ibody.formData)
    of bitString:
      body = RequestBody(t: rbtString, s: ibody.str)
    else: discard #TODO
    if httpMethod in {hmGet, hmHead}:
      return errTypeError("HEAD or GET Request cannot have a body.")
  if init.headers.isSome:
    ?headers.fill(init.headers.get)
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

func credentialsMode*(attribute: CORSAttribute): CredentialsMode =
  case attribute
  of caNoCors, caAnonymous:
    return cmSameOrigin
  of caUseCredentials:
    return cmInclude

proc addRequestModule*(ctx: JSContext) =
  ctx.registerType(JSRequest, name = "Request")

{.pop.} # raises: []
