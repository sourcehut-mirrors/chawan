{.push raises: [].}

import std/algorithm

import io/packetreader
import io/packetwriter
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jstypes
import monoucha/quickjs
import monoucha/tojs
import types/jsopt
import types/opt
import types/referrer
import types/url
import utils/twtstr

type
  HeaderGuard* = enum
    hgNone = "none"
    hgImmutable = "immutable"
    hgRequest = "request"
    hgRequestNoCors = "request-no-cors"
    hgResponse = "response"

  HTTPHeader* = tuple[name, value: string]

  HeaderList = seq[HTTPHeader]

  HeaderListConst = openArray[HTTPHeader]

  Headers* = ref object
    list: HeaderList
    guard*: HeaderGuard

  HeadersInit* = object
    s: seq[HTTPHeader]

jsDestructor(Headers)

proc isForbiddenResponseHeaderName*(name: string): bool

iterator pairs*(this: Headers): tuple[name, value: lent string] =
  for (name, value) in this.list:
    if this.guard == hgResponse and name.isForbiddenResponseHeaderName():
      continue
    yield (name, value)

iterator allPairs*(headers: Headers): tuple[name, value: lent string] =
  for (name, value) in headers.list:
    yield (name, value)

proc sort*(list: var HeaderList) =
  list.sort(proc(a, b: HTTPHeader): int = cmpIgnoreCase(a.name, b.name))

proc sort(headers: Headers) =
  headers.list.sort()

# in the loader we just send a seq of openArray[HTTPHeader]
proc sreadList*(r: var PacketReader; headers: Headers) =
  assert headers != nil
  r.sread(headers.list)
  headers.sort()

proc swriteList*(w: var PacketWriter; headers: Headers) =
  w.swrite(headers.list)

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var HeadersInit):
    FromJSResult =
  var headers: Headers
  if ctx.fromJS(val, headers).isOk:
    res = HeadersInit(s: headers.list)
    return fjOk
  if ctx.isSequence(val):
    res = HeadersInit()
    if ctx.fromJS(val, res.s).isOk:
      return fjOk
  res = HeadersInit()
  var record: JSKeyValuePair[string, string]
  ?ctx.fromJS(val, record)
  res.s = move(record.s)
  fjOk

const TokenChars = {
  '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_', '`', '|', '~'
} + AsciiAlphaNumeric

proc isValidHeaderName*(s: string): bool =
  return s.len > 0 and AllChars - TokenChars notin s

proc isValidHeaderValue*(s: string): bool =
  return s.len == 0 or s[0] notin {' ', '\t'} and s[^1] notin {' ', '\t'} and
    '\n' notin s

proc isForbiddenRequestHeader*(name, value: string): bool =
  const ForbiddenNames = [
    "Accept-Charset",
    "Accept-Encoding",
    "Access-Control-Request-Headers",
    "Access-Control-Request-Method",
    "Connection",
    "Content-Length",
    "Cookie",
    "Cookie2",
    "Date",
    "DNT",
    "Expect",
    "Host",
    "Keep-Alive",
    "Origin",
    "Referer",
    "Set-Cookie",
    "TE",
    "Trailer",
    "Transfer-Encoding",
    "Upgrade",
    "Via"
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

proc isForbiddenResponseHeaderName*(name: string): bool =
  return name.equalsIgnoreCase("Set-Cookie") or
    name.equalsIgnoreCase("Set-Cookie2")

proc validate(ctx: JSContext; this: Headers; name, value: string): Opt[bool] =
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

proc isNoCorsSafelistedName(name: string): bool =
  return name.equalsIgnoreCase("Accept") or
    name.equalsIgnoreCase("Accept-Language") or
    name.equalsIgnoreCase("Content-Language") or
    name.equalsIgnoreCase("Content-Type")

const CorsUnsafeRequestByte = {
  char(0x00)..char(0x08), char(0x10)..char(0x1F), '"', '(', ')', ':', '<', '>',
  '?', '@', '[', '\\', ']', '{', '}', '\e'
}

proc isNoCorsSafelisted(name, value: string): bool =
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
      "multipart/form-data",
      "text/plain",
      "application-x-www-form-urlencoded"
    ]
  return false

proc lowerBound(list: HeaderListConst; name: string): int =
  list.lowerBound(name, proc(it: HTTPHeader; name: string): int =
    cmpIgnoreCase(it.name, name)
  )

proc lowerBound(this: Headers; name: string): int =
  this.list.lowerBound(name)

proc removeAll(list: var HeaderList; name: string; n: int) =
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

proc removeAll(this: Headers; name: string; n: int) =
  this.list.removeAll(name, n)

proc contains(list: HeaderListConst; name: string; n: int): bool =
  return n < list.len and list[n].name.equalsIgnoreCase(name)

proc contains(this: Headers; name: string; n: int): bool =
  this.list.contains(name, n)

proc contains*(list: HeaderList; name: string): bool =
  list.contains(name, list.lowerBound(name))

proc contains*(this: Headers; name: string): bool =
  this.list.contains(name)

proc removeAll*(this: Headers; name: string) =
  this.removeAll(name, this.lowerBound(name))

proc add(headers: Headers; name, value: string; n: int) =
  var n = n
  while n < headers.list.len and headers.contains(name, n):
    inc n
  headers.list.insert((name, value), n)

proc addIfNotFound*(list: var HeaderList; name, value: string) =
  let n = list.lowerBound(name)
  if not list.contains(name, n):
    list.insert((name, value), n)

proc addIfNotFound*(headers: Headers; name, value: string) =
  headers.list.addIfNotFound(name, value)

# returns true if added, false otherwise
proc addIfNotFoundCheck*(headers: Headers; name, value: string): bool =
  let n = headers.lowerBound(name)
  if not headers.contains(name, n):
    headers.list.insert((name, value), n)
    return true
  false

proc get(this: Headers; name: string; n: int): string =
  var s = ""
  for it in this.list.toOpenArray(n, this.list.high):
    if not it.name.equalsIgnoreCase(name):
      break
    if s.len > 0:
      s &= ", "
    s &= it.value
  move(s)

proc get*(ctx: JSContext; this: Headers; name: string): JSValue {.jsfunc.} =
  if not name.isValidHeaderName():
    JS_ThrowTypeError(ctx, "Invalid header name")
    return JS_EXCEPTION
  let n = this.lowerBound(name)
  if this.contains(name, n):
    return ctx.toJS(this.get(name, n))
  return JS_NULL

proc removeRange(this: Headers) =
  if this.guard == hgRequestNoCors:
    this.removeAll("Range") # privileged no-CORS request headers

proc append(ctx: JSContext; this: Headers; name, value: string): Opt[void]
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

proc delete(ctx: JSContext; this: Headers; name: string): Opt[void] {.jsfunc.} =
  if not ?ctx.validate(this, name, "") or
      this.guard == hgRequestNoCors and not name.isNoCorsSafelistedName() and
      not name.equalsIgnoreCase("Range"):
    return ok()
  let n = this.lowerBound(name)
  if this.contains(name, n):
    this.removeAll(name, n)
    this.removeRange()
  ok()

proc has(ctx: JSContext; this: Headers; name: string): JSValue {.jsfunc.} =
  if not name.isValidHeaderName():
    return JS_ThrowTypeError(ctx, "invalid header name")
  if name in this:
    return JS_TRUE
  return JS_FALSE

proc set(ctx: JSContext; this: Headers; name, value: string): Opt[void]
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

proc fill*(ctx: JSContext; headers: Headers; init: HeadersInit): Opt[void] =
  for (k, v) in init.s:
    ?ctx.append(headers, k, v)
  ok()

proc newHeaders*(guard: HeaderGuard): Headers =
  return Headers(guard: guard)

proc newHeaders*(guard: HeaderGuard; list: openArray[(string, string)]):
    Headers =
  let headers = newHeaders(guard)
  headers.list = @list
  headers.sort()
  return headers

proc newHeaders(ctx: JSContext; jsInit: JSValueConst = JS_UNDEFINED):
    Opt[Headers] {.jsctor.} =
  let headers = newHeaders(hgNone)
  if not JS_IsUndefined(jsInit):
    var init: HeadersInit
    ?ctx.fromJS(jsInit, init)
    ?ctx.fill(headers, init)
  ok(headers)

proc clone*(headers: Headers): Headers =
  return Headers(guard: headers.guard, list: headers.list)

proc add*(headers: Headers; name, value: string) =
  headers.add(name, value, headers.lowerBound(name))

proc `[]=`*(this: Headers; name, value: string) =
  let n = this.lowerBound(name)
  this.removeAll(name, n)
  this.add(name, value, n)

proc `[]`*(this: Headers; name: string): var string =
  let n = this.lowerBound(name)
  return this.list[n].value

proc getFirst(list: HeaderListConst; name: string; n: int): lent string =
  if list.contains(name, n):
    return list[n].value
  let emptyStr {.global.} = ""
  return emptyStr

proc getFirst*(list: HeaderListConst; name: string): lent string =
  list.getFirst(name, list.lowerBound(name))

proc getFirst*(headers: Headers; name: string): lent string =
  headers.list.getFirst(name)

proc setupReferrer*(list: var HeaderList; target: URL;
    referrerPolicy: ReferrerPolicy) =
  # set referrer based on origin URL and referrer policy
  let n = list.lowerBound("Referer")
  if list.contains("Referer", n):
    let url = parseURL0(move(list[n].value))
    list.removeAll("Referer", n)
    if url != nil:
      let referrer = url.getReferrer(target, referrerPolicy)
      if referrer != "":
        list.insert(("Referer", referrer), n)

proc getAllNoComma*(list: HeaderListConst; k: string): seq[string] =
  result = @[]
  let n = list.lowerBound(k)
  for it in list.toOpenArray(n, list.high):
    if not it.name.equalsIgnoreCase(k):
      break
    result.add(it.value)

proc getAllNoComma*(this: Headers; k: string): seq[string] =
  this.list.getAllNoComma(k)

proc getAllCommaSplit*(this: Headers; k: string): seq[string] =
  result = @[]
  let n = this.lowerBound(k)
  for it in this.list.toOpenArray(n, this.list.high):
    if not it.name.equalsIgnoreCase(k):
      break
    for value in it.value.split(','):
      result.add(value.strip(chars = {' ', '\t'}))

# n is timeout in millis. -1 => not found
# url == nil => self
type CheckRefreshResult* = tuple[n: int; url: URL]

proc parseRefresh*(s: string; baseURL: URL): CheckRefreshResult =
  var i = s.skipBlanks(0)
  let s0 = s.until(NonDigit, i)
  let x = parseUInt32(s0, allowSign = false)
  if s0 != "":
    if x.isErr and (i >= s.len or s[i] != '.'):
      return (n: -1, url: nil)
  var n = int(x.get(0) * 1000)
  i = s.skipBlanks(i + s0.len)
  if i < s.len and s[i] == '.':
    inc i
    let s1 = s.until(NonDigit, i)
    if s1 != "":
      n += int(parseUInt32(s1, allowSign = false).get(0))
      i = s.skipBlanks(i + s1.len)
  elif s0 == "": # empty string or blanks
    return (n: -1, url: nil)
  if i >= s.len: # just reload this page
    return (n: n, url: nil)
  if s[i] notin {',', ';'}:
    return (n: -1, url: nil)
  i = s.skipBlanks(i + 1)
  if s.toOpenArray(i, s.high).startsWithIgnoreCase("url="):
    i = s.skipBlanks(i + "url=".len)
  var q = false
  if i < s.len and s[i] in {'"', '\''}:
    q = true
    inc i
  var s2 = s.substr(i)
  if q and s2.len > 0 and s[^1] in {'"', '\''}:
    s2.setLen(s2.high)
  if url := parseURL(s2, baseURL):
    return (n: n, url: url)
  return (n: -1, url: nil)

proc addHeadersModule*(ctx: JSContext): Opt[void] =
  ?ctx.registerType(Headers)
  ok()

{.pop.} # raises: []
