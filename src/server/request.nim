{.push raises: [].}

import html/script
import io/dynstream
import io/packetreader
import io/packetwriter
import js/fromjs
import js/jsbind
import js/jsref
import js/jstypes
import js/jsutils
import js/quickjs
import js/tojs
import server/headers
import types/blob
import types/opt
import types/url
import utils/twtstr

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
    hmTrack = "TRACK"

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

  FormDataEntry* = object
    name*: string
    filename*: string
    case isstr*: bool
    of true:
      svalue*: string
    of false:
      value*: Blob

  FormDataObj* = object
    entries*: seq[FormDataEntry]
    boundary*: string

  FormData* = JSRef[FormDataObj]

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

  RequestFlag* = enum
    rqfToCache # save the result to the cache
    rqfUrlCredentials # whether to use user/pass in URL
    rqfReferrer # use Referer header (if not set, use client base URL)
    rqfInternal # may use internal browsecap entries (e.g. image codecs)

  RawRequest* = object
    url*: URL
    headers*: seq[HTTPHeader]
    body*: RequestBody
    httpMethod*: HttpMethod
    flags: set[RequestFlag]
    credentials*: CredentialsMode

  RequestObj* = object
    # RawRequest
    url*: URL
    headers*: Headers
    body*: RequestBody
    httpMethod*: HttpMethod
    flags: set[RequestFlag]
    credentials*: CredentialsMode
    # client-specific
    mode*: RequestMode
    destination*: RequestDestination
    origin*: RequestOrigin
    window*: RequestWindow
    client*: EnvironmentSettings

  Request* = JSRef[RequestObj]

# Forward declarations
proc getClassID(t: typedesc[Request]): JSClassID
proc getClassID*(t: typedesc[FormData]): JSClassID

# Forward declaration hack
proc getAPIBaseURL(ctx: JSContext): URL {.importc: "cha_$1".}
proc getOrigin(ctx: JSContext): Origin {.importc: "cha_$1".}
proc newFormDataImpl(ctx: JSContext; argv: varargs[JSValueConst]):
  Opt[FormData] {.importc: "cha_$1".}

# Iterators
iterator items*(this: FormData): lent FormDataEntry {.inline.} =
  for entry in this.entries:
    yield entry

proc swrite*(w: var PacketWriter; part: FormDataEntry) =
  w.swrite(part.isstr)
  w.swrite(part.name)
  w.swrite(part.filename)
  if part.isstr:
    w.swrite(part.svalue)
  else:
    w.swrite(part.value)

proc sread*(r: var PacketReader; part: var FormDataEntry) =
  var isstr: bool
  r.sread(isstr)
  if isstr:
    part = FormDataEntry(isstr: true)
  else:
    part = FormDataEntry(isstr: false)
  r.sread(part.name)
  r.sread(part.filename)
  if part.isstr:
    r.sread(part.svalue)
  else:
    r.sread(part.value)

proc swrite*(w: var PacketWriter; formData: FormData) =
  w.swrite(formData != nil)
  if formData != nil:
    w.swrite(formData.entries)
    w.swrite(formData.boundary)

proc sread*(r: var PacketReader; formData: var FormData) =
  var has: bool
  r.sread(has)
  if has:
    var obj: FormDataObj
    r.sread(obj.entries)
    r.sread(obj.boundary)
    formData = jsNew obj
  else:
    formData = FormData(nil)

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

proc swrite*(w: var PacketWriter; o: Request) =
  w.swrite(o.url)
  w.swriteList(o.headers)
  w.swrite(o.body)
  w.swrite(o.httpMethod)
  w.swrite(o.flags)
  w.swrite(o.credentials)

proc sread*(w: var PacketReader; o: var Request) {.
    error: "use RawRequest instead".} =
  discard

proc sread*(r: var PacketReader; o: var RawRequest) =
  r.sread(o.url)
  r.sread(o.headers)
  r.sread(o.body)
  r.sread(o.httpMethod)
  r.sread(o.flags)
  r.sread(o.credentials)

# FormData
proc writeEntry(stream: PosixStream; entry: FormDataEntry; boundary: string):
    Opt[void] =
  var buf = "--" & boundary & "\r\n"
  let name = percentEncode(entry.name, {'"', '\r', '\n'})
  if entry.isstr:
    buf &= "Content-Disposition: form-data; name=\"" & name & "\"\r\n\r\n"
    # try to merge the write call for small entries
    if entry.svalue.len < 4096:
      buf &= entry.svalue
      ?stream.writeLoop(buf)
    else:
      ?stream.writeLoop(buf)
      ?stream.writeLoop(entry.svalue)
  else:
    buf &= "Content-Disposition: form-data; name=\"" & name & "\";"
    let filename = percentEncode(entry.filename, {'"', '\r', '\n'})
    buf &= " filename=\"" & filename & "\"\r\n"
    let blob = entry.value
    let contentType = if blob.contentType == "":
      "application/octet-stream"
    else:
      blob.contentType
    buf &= "Content-Type: "
    if blob.contentType == "":
      buf &= "application/octet-stream"
    else:
      buf &= contentType
    buf &= "\r\n\r\n"
    ?stream.writeLoop(buf)
    if (let file = blob as WebFile; file != nil and file.fd != -1):
      let ps = newPosixStream(file.fd)
      if ps != nil:
        var buf {.noinit.}: array[4096, uint8]
        while true:
          let n = ps.read(buf)
          if n <= 0:
            break
          ?stream.writeLoop(buf.toOpenArray(0, n - 1))
    else:
      ?stream.writeLoop(blob.buffer, blob.size)
  stream.writeLoop("\r\n")

proc write*(stream: PosixStream; formData: FormData): Opt[void] =
  for entry in formData.entries:
    ?stream.writeEntry(entry, formData.boundary)
  stream.writeLoop("--" & formData.boundary & "--\r\n")

proc generateBoundary(urandom: PosixStream): string =
  var s {.noinit.}: array[33, uint8]
  if urandom.readLoop(s).isErr:
    return ""
  # 33 * 4 / 3 = 44 + prefix string is 22 bytes = 66 bytes
  return "----WebKitFormBoundary" & btoa(s)

proc newFormData0*(urandom: PosixStream): FormData =
  var boundary = urandom.generateBoundary()
  if boundary.len == 0:
    return FormData(nil)
  return jsNew FormDataObj(boundary: move(boundary))

proc add*(list: var seq[FormDataEntry], entry: tuple[name, value: string]) =
  list.add(FormDataEntry(
    name: entry.name,
    isstr: true,
    svalue: entry.value
  ))

proc toNameValuePairs*(list: seq[FormDataEntry]):
    seq[tuple[name, value: string]] =
  result = @[]
  for entry in list:
    if entry.isstr:
      result.add((entry.name, entry.svalue))
    else:
      result.add((entry.name, entry.name))

proc calcLength*(this: FormData): int =
  result = 0
  for entry in this.entries:
    result += "--\r\n".len + this.boundary.len # always have boundary
    #TODO maybe make CRLF for name first?
    result += entry.name.len # always have name
    # these must be percent-encoded, with 2 char overhead:
    result += entry.name.count({'\r', '\n', '"'}) * 2
    if entry.isstr:
      result += "Content-Disposition: form-data; name=\"\"\r\n".len
      result += entry.svalue.len
    else:
      result += "Content-Disposition: form-data; name=\"\";".len
      # file name
      result += " filename=\"\"\r\n".len
      result += entry.filename.len
      # dquot must be quoted with 2 char overhead
      result += entry.filename.count('"') * 2
      # content type
      result += "Content-Type: \r\n".len
      result += entry.value.contentType.len
      result += entry.value.getSize()
    result += "\r\n".len # header is always followed by \r\n
    result += "\r\n".len # value is always followed by \r\n
  result += "--".len + this.boundary.len + "--\r\n".len

proc getContentType*(this: FormData): string =
  return "multipart/form-data; boundary=" & this.boundary

jsClassPublicDef(FormData):
  proc newFormData(ctx: JSContext; argv: varargs[JSValueConst]): Opt[FormData]
      {.jsctor.} =
    newFormDataImpl(ctx, argv)

  proc append*(ctx: JSContext; this: FormData; name: string; val: JSValueConst;
      rest: varargs[JSValueConst]): Opt[void] {.jsfunc.} =
    var blob: Blob
    if ctx.fromJS(val, blob).isOk:
      var filename = "blob"
      if rest.len > 0:
        ?ctx.fromJS(rest[0], filename)
      elif blob of WebFile:
        filename = WebFile(blob).name
      this.entries.add(FormDataEntry(
        name: name,
        isstr: false,
        value: blob,
        filename: filename
      ))
      ok()
    elif rest.len > 0:
      err()
    else:
      var s: string
      ?ctx.fromJS(val, s)
      this.entries.add(FormDataEntry(name: name, isstr: true, svalue: s))
      ok()

  proc delete(this: FormData; name: string) {.jsfunc.} =
    for i in countdown(this.entries.high, 0):
      if this.entries[i].name == name:
        this.entries.delete(i)

  proc get(ctx: JSContext; this: FormData; name: string): JSValue {.jsfunc.} =
    for entry in this.entries:
      if entry.name == name:
        if entry.isstr:
          return ctx.toJS(entry.svalue)
        else:
          return ctx.toJS(entry.value)
    return JS_NULL

  proc getAll(ctx: JSContext; this: FormData; name: string): seq[JSValue]
      {.jsfunc.} =
    result = newSeq[JSValue]()
    for entry in this.entries:
      if entry.name == name:
        if entry.isstr:
          result.add(ctx.toJS(entry.svalue))
        else:
          result.add(ctx.toJS(entry.value))

# Request
proc contentLength*(body: RequestBody): int =
  case body.t
  of rbtString: return body.s.len
  of rbtBlob: return body.blob.size
  of rbtMultipart: return body.multipart.calcLength()
  of rbtNone, rbtOutput, rbtCache: return 0

proc tocache*(this: RawRequest): bool =
  rqfToCache in this.flags

proc urlCredentials*(this: RawRequest): bool =
  rqfUrlCredentials in this.flags

proc hasReferrer*(this: RawRequest): bool =
  rqfReferrer in this.flags

proc internal*(this: RawRequest): bool =
  rqfInternal in this.flags

proc hasReferrer*(this: Request): bool =
  rqfReferrer in this.flags

proc getReferrer*(this: Request): URL =
  return parseURL0(this.headers.getFirst("Referer"))

proc setReferrer*(this: Request; value: string) =
  this.flags.incl(rqfReferrer)
  this.headers["Referer"] = value

proc unsetReferrer*(this: Request) =
  this.flags.excl(rqfReferrer)
  this.headers.removeAll("Referer")

proc newRequest*(url: URL; httpMethod = hmGet; headers = newHeaders(hgRequest);
    body = RequestBody(); hasReferrer = true; referrer = URL(nil);
    tocache = false; credentials = cmSameOrigin; internal = false;
    urlCredentials = false; destination = rdNone; mode = rmNoCors;
    window = RequestWindow(t: rwtNoWindow)): Request =
  assert url != nil
  if referrer != nil:
    headers["Referer"] = $referrer
  var flags: set[RequestFlag] = {}
  if tocache:
    flags.incl(rqfToCache)
  if urlCredentials:
    flags.incl(rqfUrlCredentials)
  if hasReferrer:
    flags.incl(rqfReferrer)
  if internal:
    flags.incl(rqfInternal)
  return jsNew RequestObj(
    url: url,
    httpMethod: httpMethod,
    headers: headers,
    body: body,
    flags: flags,
    credentials: credentials,
    destination: destination,
    mode: mode
  )

proc newRequest*(raw: RawRequest): Request =
  return newRequest(raw.url, raw.httpMethod, newHeaders(hgRequest, raw.headers),
    raw.body, tocache = raw.tocache, credentials = raw.credentials,
    internal = raw.internal, urlCredentials = raw.urlCredentials)

proc newRequest*(s: string; httpMethod = hmGet; headers = newHeaders(hgRequest);
    body = RequestBody(); hasReferrer = true; referrer = URL(nil);
    tocache = false; credentials = cmSameOrigin; internal = false): Request =
  return newRequest(parseURL0(s), httpMethod, headers, body, hasReferrer,
    referrer, tocache, credentials, internal)

proc createPotentialCORSRequest*(url: URL; destination: RequestDestination;
    cors: CORSAttribute; fallbackFlag = false): Request =
  var mode = if cors == caNoCors:
    rmNoCors
  else:
    rmCors
  if fallbackFlag and mode == rmNoCors:
    mode = rmSameOrigin
  let credentials = if cors == caAnonymous: cmSameOrigin else: cmInclude
  return newRequest(url, credentials = credentials, destination = destination, mode = mode)

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

  RequestInit = object of JSDict
    `method` {.jsdefault: trace(JS_UNDEFINED).}: JSValueTraced
    headers {.jsdefault.}: HeadersInit
    body {.jsdefault.}: BodyInit
    referrer {.jsdefault: trace(JS_UNDEFINED).}: JSValueTraced
    referrerPolicy {.jsdefault: trace(JS_UNDEFINED).}: JSValueTraced
    credentials {.jsdefault: trace(JS_UNDEFINED).}: JSValueTraced
    mode {.jsdefault: trace(JS_UNDEFINED).}: JSValueTraced
    window {.jsdefault: trace(JS_UNDEFINED).}: JSValueTraced

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var BodyInit):
    JSCode =
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
    return init.blob.contentType

proc safeExtract*(init: BodyInit; body: var RequestBody): string =
  #TODO check for ReadableStream once we have it
  init.extract(body)

proc credentials*(attribute: CORSAttribute): CredentialsMode =
  case attribute
  of caNoCors, caAnonymous:
    return cmSameOrigin
  of caUseCredentials:
    return cmInclude

jsClassDef(Request):
  jsget Request, headers
  jsget Request, httpMethod, "method"
  jsget Request, credentials
  jsget Request, mode
  jsget Request, destination

  proc jsUrl(this: Request): string {.jsfget: "url".} =
    return $this.url

  proc referrer(ctx: JSContext; this: Request): JSValue {.jsfget.} =
    if rqfReferrer notin this.flags:
      return ctx.toJS("")
    let res = this.headers.getFirst("Referer")
    if res != "":
      return ctx.toJS(res)
    return ctx.toJS("about:client")

  proc newRequest*(ctx: JSContext; resource: JSValueConst;
      jsInit: JSValueConst = JS_UNDEFINED): Opt[Request] {.jsctor.} =
    var init: RequestInit
    ?ctx.fromJS(jsInit, init)
    var headers = newHeaders(hgRequest)
    var window = RequestWindow(t: rwtClient)
    var body = RequestBody()
    var credentials = cmSameOrigin
    var httpMethod = hmGet
    var referrerStr = ""
    if not JS_IsUndefined(init.referrer):
      ?ctx.fromJS(init.referrer, referrerStr)
    if not JS_IsUndefined(init.credentials):
      ?ctx.fromJS(init.credentials, credentials)
    if not JS_IsUndefined(init.`method`):
      var s: DOMString
      ?ctx.fromJS(init.`method`, s)
      #TODO the spec allows this to be any string :(
      let res = parseEnumNoCase[HttpMethod](s.toOpenArray())
      if res.isErr:
        JS_ThrowTypeError(ctx, "unexpected HTTP method %s", s.p)
        return err()
      httpMethod = res.get
    var hasReferrer = true
    var referrer: URL
    var url: URL
    var mode = rmNoCors
    if not JS_IsUndefined(init.mode):
      ?ctx.fromJS(init.mode, mode)
    let apiBaseURL = ctx.getAPIBaseURL()
    let origin = ctx.getOrigin()
    if (var res: Request; ctx.fromJS(resource, res).isOk):
      url = res.url
      if JS_IsUndefined(init.`method`):
        httpMethod = res.httpMethod
      headers[] = res.headers[]
      if JS_IsUndefined(jsInit):
        hasReferrer = rqfReferrer in res.flags
        referrer = res.getReferrer()
        mode = res.mode
      if JS_IsUndefined(init.mode):
        mode = res.mode
        if not JS_IsUndefined(jsInit) and mode == rmNavigate:
          mode = rmSameOrigin
      if JS_IsUndefined(init.credentials):
        credentials = res.credentials
      body = res.body
      window = res.window
    else:
      var s: string
      ?ctx.fromJS(resource, s)
      url = ?ctx.parseJSURL(s, apiBaseURL)
      if JS_IsUndefined(init.mode):
        mode = rmCors
    if url.username != "" or url.password != "":
      JS_ThrowTypeError(ctx, "input URL contains a username or password")
      return err()
    let destination = rdNone
    #TODO origin, window
    if not JS_IsUndefined(init.window):
      if not JS_IsNull(init.window):
        JS_ThrowTypeError(ctx, "expected window to be null")
        return err()
      window = RequestWindow(t: rwtNoWindow)
    #TODO flags
    if not JS_IsUndefined(init.referrer):
      if referrerStr == "":
        hasReferrer = false
      else:
        referrer = ?ctx.parseJSURL(referrerStr, apiBaseURL)
        if referrer.schemeType == stAbout and referrer.pathname == "client" or
            not referrer.origin.isSameOrigin(origin):
          referrer = URL(nil)
    #TODO referrerPolicy
    if mode == rmNavigate:
      JS_ThrowTypeError(ctx, "request mode must not be `navigate'")
      return err()
    if init.body.t != bitNull and httpMethod in {hmGet, hmHead}:
      JS_ThrowTypeError(ctx, "HEAD or GET requests cannot have a body")
      return err()
    ?ctx.fill(headers, init.headers)
    let contentType = init.body.extract(body)
    if contentType != "":
      headers.addIfNotFound("Content-Type", contentType)
    if mode == rmNoCors:
      headers.guard = hgRequestNoCors
    ok(newRequest(
      url,
      httpMethod,
      headers,
      body,
      hasReferrer,
      referrer,
      credentials = credentials,
      mode = mode,
      destination = destination,
      window = window
    ))

proc addRequestModule*(ctx: JSContext): JSCode =
  ?ctx.registerClass(RequestDef)
  ctx.registerClass(FormDataDef)

{.pop.} # raises: []
