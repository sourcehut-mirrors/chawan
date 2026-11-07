{.push raises: [].}

when NimMajor >= 2:
  import std/assertions
import std/algorithm

import io/packetreader
import io/packetwriter
import js/fromjs
import js/jsbind
import js/jsref
import js/jstypes
import js/jsutils
import js/quickjs
import js/tojs
import server/url
import utils/cowstr
import utils/opt
import utils/twtstr

type
  HeaderGuard* = enum
    hgNone = "none"
    hgImmutable = "immutable"
    hgRequest = "request"
    hgRequestNoCors = "request-no-cors"
    hgResponse = "response"

  # HTTP header.  Ostensibly UTF-8, but no guarantees are made for this;
  # in fact, while the network stack treats them as UTF-8, the fetch API
  # instead returns ByteStrings which produce latin-1 in JS.
  #
  # To illustrate: Gecko & Blink both handle headers as follows.
  # * fetch("", {headers: {a:'\xF3'}}) -> U+00F3 encoded as latin-1
  # * fetch("", {headers: {a:'\xC3\xB3'}}) -> U+00F3 encoded as UTF-8
  # * Set-Cookie: a=\u00F3 (encoded as UTF-8) -> document.cookie has U+00F3
  # * Set-Cookie: a=\u00F3 (encoded as latin-1) -> document.cookie has U+FFFD
  #
  # Meanwhile, ByteString -> header conversion looks like:
  # * Moo: \u00F3 (encoded as UTF-8) -> headers.get("moo") produces
  #   U+00C3 U+00B3
  # * Moo: \u00F3 (encoded as latin-1) -> headers.get("moo") produces U+00F3
  HTTPHeader* = tuple[name, value: ByteString]

  HeaderList = seq[HTTPHeader]

  HeaderListConst = openArray[HTTPHeader]

  HeadersObj* = object
    list: HeaderList
    guard*: HeaderGuard

  Headers* = JSRef[HeadersObj]

  HeadersInit* = object
    s: seq[tuple[name, value: ByteString]]

  ReferrerPolicy* = enum
    rpStrictOriginWhenCrossOrigin = "strict-origin-when-cross-origin"
    rpNoReferrer = "no-referrer"
    rpNoReferrerWhenDowngrade = "no-referrer-when-downgrade"
    rpStrictOrigin = "strict-origin"
    rpOrigin = "origin"
    rpSameOrigin = "same-origin"
    rpOriginWhenCrossOrigin = "origin-when-cross-origin"
    rpUnsafeURL = "unsafe-url"

# Forward declarations
proc append(ctx: JSContext; this: Headers; name, value: ByteString): Opt[void]
proc isForbiddenResponseHeaderName*(name: ByteString): bool
proc getClassID(t: typedesc[Headers]): JSClassID
proc sort(headers: Headers)

# in the loader we just send a seq of openArray[HTTPHeader]
proc sreadList*(r: var PacketReader; headers: Headers): PacketCode =
  assert headers != nil
  ?r.sread(headers.list)
  headers.sort()
  ok()

proc swriteList*(w: var PacketWriter; headers: Headers) =
  w.swrite(headers.list)

proc sread*(r: var PacketReader; headers: var Headers): PacketCode =
  var has: bool
  ?r.sread(has)
  if has:
    var obj: HeadersObj
    ?r.sread(obj.list)
    headers = jsNew obj
    if headers != nil:
      headers.sort()
  else:
    headers = Headers(nil)
  ok()

proc swrite*(w: var PacketWriter; headers: Headers) =
  w.swrite(headers != nil)
  if headers != nil:
    w.swriteList(headers)

iterator pairs*(this: Headers): tuple[name, value: lent ByteString] =
  for (name, value) in this.list:
    if this.guard == hgResponse and name.isForbiddenResponseHeaderName():
      continue
    yield (name, value)

iterator allPairs*(headers: Headers): tuple[name, value: lent ByteString] =
  for (name, value) in headers.list:
    yield (name, value)

proc sort*(list: var HeaderList) =
  list.sort(proc(a, b: HTTPHeader): int = cmpIgnoreCase(a.name, b.name))

proc sort(headers: Headers) =
  headers.list.sort()

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var HeadersInit): JSCode =
  var headers: Headers
  if ctx.fromJS(val, headers).isOk:
    res = HeadersInit()
    for it in headers.list:
      res.s.add((it.name, it.value))
    return fjOk
  if ?ctx.isSequence(val):
    res = HeadersInit()
    ?ctx.fromJS(val, res.s)
  var record: JSKeyValuePair[ByteString, ByteString]
  ?ctx.fromJS(val, record)
  res = HeadersInit(s: move(record.s))
  fjOk

const TokenChars = {
  '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_', '`', '|', '~'
} + AsciiAlphaNumeric

proc isValidHeaderName*(s: ByteString): bool =
  return s.len > 0 and AllChars - TokenChars notin s

proc isValidHeaderValue*(s: ByteString): bool =
  return s.len == 0 or s[0] notin {' ', '\t'} and s[^1] notin {' ', '\t'} and
    '\n' notin s

proc isForbiddenRequestHeader*(name, value: ByteString): bool =
  const ForbiddenNames = [
    byteStr("Accept-Charset"),
    byteStr("Accept-Encoding"),
    byteStr("Access-Control-Request-Headers"),
    byteStr("Access-Control-Request-Method"),
    byteStr("Connection"),
    byteStr("Content-Length"),
    byteStr("Cookie"),
    byteStr("Cookie2"),
    byteStr("Date"),
    byteStr("DNT"),
    byteStr("Expect"),
    byteStr("Host"),
    byteStr("Keep-Alive"),
    byteStr("Origin"),
    byteStr("Referer"),
    byteStr("Set-Cookie"),
    byteStr("TE"),
    byteStr("Trailer"),
    byteStr("Transfer-Encoding"),
    byteStr("Upgrade"),
    byteStr("Via")
  ]
  for x in ForbiddenNames:
    if name.equalsIgnoreCase(x):
      return true
  if name.startsWithIgnoreCase("proxy-") or name.startsWithIgnoreCase("sec-"):
    return true
  if name.equalsIgnoreCase("X-HTTP-Method") or
      name.equalsIgnoreCase("X-HTTP-Method-Override") or
      name.equalsIgnoreCase("X-Method-Override"):
    return true # meh
  return false

proc isForbiddenResponseHeaderName*(name: ByteString): bool =
  Str(name).equalsIgnoreCase("Set-Cookie") or
    Str(name).equalsIgnoreCase("Set-Cookie2")

proc validate(ctx: JSContext; this: Headers; name, value: ByteString):
    Opt[bool] =
  if not name.isValidHeaderName() or not value.isValidHeaderValue():
    JS_ThrowTypeError(ctx, "invalid header name or value")
    return err()
  if this.guard == hgImmutable:
    JS_ThrowTypeError(ctx, "tried to modify immutable Headers object")
    return err()
  if this.guard == hgRequest and isForbiddenRequestHeader(name, value):
    return ok(false)
  if this.guard == hgResponse and name.isForbiddenResponseHeaderName():
    return ok(false)
  ok(true)

proc isNoCorsSafelistedName(name: ByteString): bool =
  return name.equalsIgnoreCase("Accept") or
    name.equalsIgnoreCase("Accept-Language") or
    name.equalsIgnoreCase("Content-Language") or
    name.equalsIgnoreCase("Content-Type")

const CorsUnsafeRequestByte = {
  char(0x00)..char(0x08), char(0x10)..char(0x1F), '"', '(', ')', ':', '<', '>',
  '?', '@', '[', '\\', ']', '{', '}', '\e'
}

proc isNoCorsSafelisted(name, value: ByteString): bool =
  if value.len > 128:
    return false
  if name.equalsIgnoreCase("Accept"):
    return CorsUnsafeRequestByte notin value
  if name.equalsIgnoreCase("Accept-Language") or
      name.equalsIgnoreCase("Content-Language"):
    const Forbidden = AllChars - AsciiAlphaNumeric -
      {' ', '*', ',', '-', '.', ';', '='}
    return Forbidden notin value
  if name.equalsIgnoreCase("Content-Type"):
    return value.strip().toLowerAscii() in [
      byteStr("multipart/form-data"),
      byteStr("text/plain"),
      byteStr("application-x-www-form-urlencoded")
    ]
  return false

proc lowerBound(list: HeaderListConst; name: ByteString): int =
  list.lowerBound(name, proc(it: HTTPHeader; name: ByteString): int =
    cmpIgnoreCase(it.name, name)
  )

proc lowerBound(this: Headers; name: ByteString): int =
  this.list.lowerBound(name)

proc removeAll(list: var HeaderList; name: ByteString; n: int) =
  var j = 0
  for i, it in list.toOpenArray(n, list.high).mypairs:
    if not it.name.equalsIgnoreCase(name):
      break
    j = i + 1
  var m = n + j
  if n != m:
    let L = list.len - j
    for n in n ..< L:
      list[n] = move(list[m])
      inc m
    list.setLen(L)

proc removeAll(this: Headers; name: ByteString; n: int) =
  this.list.removeAll(name, n)

proc contains(list: HeaderListConst; name: ByteString; n: int): bool =
  return n < list.len and list[n].name.equalsIgnoreCase(name)

proc contains(this: Headers; name: ByteString; n: int): bool =
  this.list.contains(name, n)

proc contains*(list: HeaderList; name: ByteString): bool =
  list.contains(name, list.lowerBound(name))

proc contains*(this: Headers; name: ByteString): bool =
  this.list.contains(name)

proc removeAll*(this: Headers; name: ByteString) =
  this.removeAll(name, this.lowerBound(name))

proc add(headers: Headers; name, value: ByteString; n: int) =
  var n = n
  while n < headers.list.len and headers.contains(name, n):
    inc n
  headers.list.insert((name, value), n)

proc addIfNotFound*(list: var HeaderList; name, value: ByteString) =
  let n = list.lowerBound(name)
  if not list.contains(name, n):
    list.insert((name, value), n)

proc addIfNotFound*(headers: Headers; name, value: ByteString) =
  headers.list.addIfNotFound(name, value)

# returns true if added, false otherwise
proc addIfNotFoundCheck*(headers: Headers; name, value: ByteString): bool =
  let n = headers.lowerBound(name)
  if not headers.contains(name, n):
    headers.list.insert((name, value), n)
    return true
  false

proc get(this: Headers; name: ByteString; n: int): ByteString =
  var s = initGrowbuf()
  for it in this.list.toOpenArray(n, this.list.high):
    if not it.name.equalsIgnoreCase(name):
      break
    if s.len > 0:
      s &= ", "
    s &= it.value
  s.toByteString()

proc removeRange(this: Headers) =
  if this.guard == hgRequestNoCors:
    this.removeAll(byteStr("Range")) # privileged no-CORS request headers

proc fill*(ctx: JSContext; headers: Headers; init: HeadersInit): Opt[void] =
  for (k, v) in init.s:
    ?ctx.append(headers, k, v)
  ok()

proc newHeaders*(guard: HeaderGuard): Headers =
  jsNew HeadersObj(guard: guard)

proc newHeaders*(guard: HeaderGuard; list: sink seq[HTTPHeader]): Headers =
  let headers = newHeaders(guard)
  if headers != nil:
    headers.list = move(list)
    headers.sort()
  return headers

proc clone*(headers: Headers): Headers =
  jsNew HeadersObj(guard: headers.guard, list: headers.list)

proc add*(headers: Headers; name, value: ByteString) =
  headers.add(name, value, headers.lowerBound(name))

proc `[]=`*(this: Headers; name, value: ByteString) =
  let n = this.lowerBound(name)
  this.removeAll(name, n)
  this.add(name, value, n)

proc `[]`*(this: Headers; name: ByteString): var ByteString =
  let n = this.lowerBound(name)
  return this.list[n].value

proc getFirst(list: HeaderListConst; name: ByteString; n: int): ByteString =
  if list.contains(name, n):
    return list[n].value
  byteStr("")

proc getFirst*(list: HeaderListConst; name: ByteString): ByteString =
  list.getFirst(name, list.lowerBound(name))

proc getFirst*(headers: Headers; name: ByteString): ByteString =
  headers.list.getFirst(name)

proc getReferrer*(prev, target: URL; policy: ReferrerPolicy): Str =
  let origin = prev.origin
  if origin.t == otOpaque:
    return str("")
  if prev.schemeType notin {stHttp, stHttps} or
      target.schemeType notin {stHttp, stHttps}:
    return str("")
  case policy
  of rpNoReferrer:
    return str("")
  of rpNoReferrerWhenDowngrade:
    if prev.schemeType == stHttps and target.schemeType == stHttp:
      return str("")
    return initStrM(origin.toStr(), prev.pathname, prev.search)
  of rpSameOrigin:
    if origin.isSameOrigin(target.origin):
      return origin.toStr()
    return str("")
  of rpOrigin:
    return origin.toStr()
  of rpStrictOrigin:
    if prev.schemeType == stHttps and target.schemeType == stHttp:
      return str("")
    return origin.toStr()
  of rpOriginWhenCrossOrigin:
    if not origin.isSameOrigin(target.origin):
      return origin.toStr()
    return initStrM(origin.toStr(), prev.pathname, prev.search)
  of rpStrictOriginWhenCrossOrigin:
    if prev.schemeType == stHttps and target.schemeType == stHttp or
        not origin.isSameOrigin(target.origin):
      return origin.toStr()
    return initStrM(origin.toStr(), prev.pathname, prev.search)
  of rpUnsafeURL:
    return initStrM(origin.toStr(), prev.pathname, prev.search)

proc setupReferrer*(list: var HeaderList; originURL, target: URL;
    hasReferrer: bool; referrerPolicy: ReferrerPolicy) =
  let n = list.lowerBound(byteStr("Referer"))
  let url = parseURL0(list.getFirst(byteStr("Referer"), n).toStr())
  list.removeAll(byteStr("Referer"), n)
  if hasReferrer:
    let url = if url != nil: url else: originURL
    if url != nil:
      let referrer = url.getReferrer(target, referrerPolicy)
      if referrer != "":
        list.insert((byteStr("Referer"), referrer.asByteString), n)

proc getAllNoComma*(list: HeaderListConst; k: ByteString): seq[ByteString] =
  var res = newSeq[ByteString]()
  let n = list.lowerBound(k)
  for it in list.toOpenArray(n, list.high):
    if not it.name.equalsIgnoreCase(k):
      break
    res.add(it.value)
  move(res)

proc getAllNoComma*(this: Headers; k: ByteString): seq[ByteString] =
  this.list.getAllNoComma(k)

proc getAllCommaSplit*(this: Headers; k: ByteString): seq[ByteString] =
  var res = newSeq[ByteString]()
  let n = this.lowerBound(k)
  for it in this.list.toOpenArray(n, this.list.high):
    if not it.name.equalsIgnoreCase(k):
      break
    for value in it.value.split(','):
      res.add(value.strip(chars = {' ', '\t'}))
  res

proc getAll*(this: Headers; name: ByteString): ByteString =
  let n = this.lowerBound(name)
  if this.contains(name, n):
    return this.get(name, n)
  return byteStr("")

# n is timeout in millis. -1 => not found
# url == nil => self
type CheckRefreshResult* = tuple[n: int; url: URL]

proc parseRefresh*(s: Str; baseURL: URL): CheckRefreshResult =
  var i = s.skipBlanks(0)
  let s0 = s.until(NonDigit, i)
  let x = parseUInt32(s0.toOpenArray(), allowSign = false)
  if s0 != "":
    if x.isErr and (i >= s.len or s[i] != '.'):
      return (n: -1, url: URL(nil))
  var n = int(x.get(0) * 1000)
  i = s.skipBlanks(i + s0.len)
  if i < s.len and s[i] == '.':
    inc i
    let s1 = s.until(NonDigit, i)
    if s1 != "":
      n += int(parseUInt32(s1.toOpenArray(), allowSign = false).get(0))
      i = s.skipBlanks(i + s1.len)
  elif s0 == "": # empty string or blanks
    return (n: -1, url: URL(nil))
  if i >= s.len: # just reload this page
    return (n: n, url: URL(nil))
  if s[i] notin {',', ';'}:
    return (n: -1, url: URL(nil))
  i = s.skipBlanks(i + 1)
  if s.toOpenArray(i, s.high).startsWithIgnoreCase("url="):
    i = s.skipBlanks(i + "url=".len)
  var q = false
  if i < s.len and s[i] in {'"', '\''}:
    q = true
    inc i
  var j = s.high
  if q and i < s.len and s[^1] in {'"', '\''}:
    dec j
  if url := parseURL(s.substr(i, j), baseURL):
    return (n: n, url: url)
  return (n: -1, url: URL(nil))

jsClassDef(Headers):
  proc newHeaders(ctx: JSContext; jsInit = JS_UNDEFINED.vc): Opt[Headers]
      {.jsctor.} =
    let headers = newHeaders(hgNone)
    if headers != nil and not JS_IsUndefined(jsInit):
      var init: HeadersInit
      ?ctx.fromJS(jsInit, init)
      ?ctx.fill(headers, init)
    ok(headers)

  proc append(ctx: JSContext; this: Headers; name, value: ByteString): Opt[void]
      {.jsfunc.} =
    let value = value.strip(chars = HTTPWhitespace)
    if not ?ctx.validate(this, name, value):
      return ok()
    let n = this.lowerBound(name)
    if this.guard == hgRequestNoCors:
      var tmp = this.get(name, n)
      if tmp.len > 0:
        tmp &= ", "
      tmp &= value
      if not name.isNoCorsSafelisted(tmp):
        return ok()
    this.add(name, value, n)
    this.removeRange()
    ok()

  proc delete(ctx: JSContext; this: Headers; name: ByteString): Opt[void] {.
      jsfunc.} =
    if not ?ctx.validate(this, name, byteStr("")) or
        this.guard == hgRequestNoCors and not name.isNoCorsSafelistedName() and
        not name.equalsIgnoreCase("Range"):
      return ok()
    let n = this.lowerBound(name)
    if this.contains(name, n):
      this.removeAll(name, n)
      this.removeRange()
    ok()

  proc has(ctx: JSContext; this: Headers; name: ByteString): JSValue
      {.jsfunc.} =
    if not name.isValidHeaderName():
      return JS_ThrowTypeError(ctx, "invalid header name")
    ctx.toJS(name in this)

  proc set(ctx: JSContext; this: Headers; name, value: ByteString): Opt[void]
      {.jsfunc.} =
    let value = value.strip(chars = HTTPWhitespace)
    if not ?ctx.validate(this, name, value):
      return ok()
    if this.guard == hgRequestNoCors and not name.isNoCorsSafelisted(value):
      return ok()
    let n = this.lowerBound(name)
    this.removeAll(name, n)
    this.add(name, value, n)
    this.removeRange()
    ok()

  proc get*(ctx: JSContext; this: Headers; name: ByteString): JSValue {.
      jsfunc.} =
    if not name.isValidHeaderName():
      JS_ThrowTypeError(ctx, "Invalid header name")
      return JS_EXCEPTION
    let n = this.lowerBound(name)
    if this.contains(name, n):
      return ctx.toJS(this.get(name, n))
    return JS_NULL

proc addHeadersModule*(ctx: JSContext): JSCode =
  ctx.registerClass(HeadersDef)

{.pop.} # raises: []
