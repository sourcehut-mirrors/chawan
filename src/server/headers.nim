{.push raises: [].}

import std/algorithm
import std/strutils
import std/tables

import monoucha/fromjs
import monoucha/javascript
import monoucha/jserror
import monoucha/quickjs
import monoucha/tojs
import types/opt
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

  Headers* = ref object
    list: seq[HTTPHeader]
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

proc fromJS(ctx: JSContext; val: JSValueConst; res: var HeadersInit):
    Err[void] =
  var headers: Headers
  if ctx.fromJS(val, headers).isOk:
    res = HeadersInit(s: headers.list)
    return ok()
  if ctx.isSequence(val):
    res = HeadersInit()
    if ctx.fromJS(val, res.s).isOk:
      return ok()
  res = HeadersInit()
  var tab: Table[string, string]
  ?ctx.fromJS(val, tab)
  for k, v in tab:
    res.s.add((k, v))
  return ok()

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

proc validate(this: Headers; name, value: string): JSResult[bool] =
  if not name.isValidHeaderName() or not value.isValidHeaderValue():
    return errTypeError("Invalid header name or value")
  if this.guard == hgImmutable:
    return errTypeError("Tried to modify immutable Headers object")
  if this.guard == hgRequest and isForbiddenRequestHeader(name, value):
    return ok(false)
  if this.guard == hgResponse and name.isForbiddenResponseHeaderName():
    return ok(false)
  return ok(true)

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
    return value.strip(chars = AsciiWhitespace).toLowerAscii() in [
      "multipart/form-data",
      "text/plain",
      "application-x-www-form-urlencoded"
    ]
  return false

proc lowerBound(this: Headers; name: string): int =
  return this.list.lowerBound(name, proc(it: HTTPHeader; name: string): int =
    cmpIgnoreCase(it.name, name)
  )

proc removeAll(this: Headers; name: string; n: int) =
  var m = n
  for n, it in this.list.toOpenArray(n, this.list.high).mypairs:
    if not it.name.equalsIgnoreCase(name):
      break
    m = n + 1
  if n != m:
    let L = this.list.len - m
    for n in n ..< L:
      this.list[n] = move(this.list[m])
      inc m
    this.list.setLen(L)

proc contains(this: Headers; name: string; n: int): bool =
  return n < this.list.len and this.list[n].name.equalsIgnoreCase(name)

proc contains*(this: Headers; name: string): bool =
  return this.contains(name, this.lowerBound(name))

proc removeAll*(this: Headers; name: string) =
  this.removeAll(name, this.lowerBound(name))

proc add(headers: Headers; name, value: string; n: int) =
  var n = n
  while n < headers.list.len and headers.contains(name, n):
    inc n
  headers.list.insert((name, value), n)

proc addIfNotFound*(headers: Headers; name, value: string) =
  let n = headers.lowerBound(name)
  if not headers.contains(name, n):
    headers.list.insert((name, value), n)

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

proc append(this: Headers; name, value: string): JSResult[void] {.jsfunc.} =
  let value = value.strip(chars = HTTPWhitespace)
  if not ?this.validate(name, value):
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

proc delete(this: Headers; name: string): JSResult[void] {.jsfunc.} =
  if not ?this.validate(name, "") or
      this.guard == hgRequestNoCors and not name.isNoCorsSafelistedName() and
      not name.equalsIgnoreCase("Range"):
    return ok()
  let n = this.lowerBound(name)
  if this.contains(name, n):
    this.removeAll(name, n)
    this.removeRange()
  ok()

proc has(this: Headers; name: string): JSResult[bool] {.jsfunc.} =
  if not name.isValidHeaderName():
    return errTypeError("Invalid header name")
  return ok(name in this)

proc set(this: Headers; name, value: string): JSResult[void] {.jsfunc.} =
  let value = value.strip(chars = HTTPWhitespace)
  if not ?this.validate(name, value):
    return ok()
  if this.guard == hgRequestNoCors and not name.isNoCorsSafelisted(value):
    return ok()
  let n = this.lowerBound(name)
  this.removeAll(name, n)
  this.add(name, value, n)
  this.removeRange()
  ok()

proc fill*(headers: Headers; init: HeadersInit): JSResult[void] =
  for (k, v) in init.s:
    ?headers.append(k, v)
  ok()

proc newHeaders*(guard: HeaderGuard): Headers =
  return Headers(guard: guard)

proc newHeaders*(guard: HeaderGuard; list: openArray[(string, string)]):
    Headers =
  let headers = newHeaders(guard)
  headers.list = @list
  headers.list.sort(proc(a, b: HTTPHeader): int = cmpIgnoreCase(a.name, b.name))
  return headers

proc newHeaders(obj = none(HeadersInit)): JSResult[Headers] {.jsctor.} =
  let headers = newHeaders(hgNone)
  if obj.isSome:
    ?headers.fill(obj.get)
  return ok(headers)

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

proc getFirst(headers: Headers; name: string; n: int): lent string =
  if headers.contains(name, n):
    return headers.list[n].value
  let emptyStr {.global.} = ""
  return emptyStr

proc getFirst*(headers: Headers; name: string): lent string =
  return headers.getFirst(name, headers.lowerBound(name))

proc takeFirstRemoveAll*(headers: Headers; name: string): string =
  let n = headers.lowerBound(name)
  var s = ""
  if headers.contains(name, n):
    s = move(headers.list[n].value)
  headers.removeAll(name, n)
  move(s)

proc getAllNoComma*(this: Headers; k: string): seq[string] =
  result = @[]
  let n = this.lowerBound(k)
  for it in this.list.toOpenArray(n, this.list.high):
    if not it.name.equalsIgnoreCase(k):
      break
    result.add(it.value)

proc getAllCommaSplit*(this: Headers; k: string): seq[string] =
  result = @[]
  let n = this.lowerBound(k)
  for it in this.list.toOpenArray(n, this.list.high):
    if not it.name.equalsIgnoreCase(k):
      break
    result.add(it.value.split(','))

type CheckRefreshResult* = object
  # n is timeout in millis. -1 => not found
  n*: int
  # url == nil => self
  url*: URL

proc parseRefresh*(s: string; baseURL: URL): CheckRefreshResult =
  var i = s.skipBlanks(0)
  let s0 = s.until(AllChars - AsciiDigit, i)
  let x = parseUInt32(s0, allowSign = false)
  if s0 != "":
    if x.isErr and (i >= s.len or s[i] != '.'):
      return CheckRefreshResult(n: -1)
  var n = int(x.get(0) * 1000)
  i = s.skipBlanks(i + s0.len)
  if i < s.len and s[i] == '.':
    inc i
    let s1 = s.until(AllChars - AsciiDigit, i)
    if s1 != "":
      n += int(parseUInt32(s1, allowSign = false).get(0))
      i = s.skipBlanks(i + s1.len)
  elif s0 == "": # empty string or blanks
    return CheckRefreshResult(n: -1)
  if i >= s.len: # just reload this page
    return CheckRefreshResult(n: n)
  if s[i] notin {',', ';'}:
    return CheckRefreshResult(n: -1)
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
  if url := parseURL(s2, some(baseURL)):
    return CheckRefreshResult(n: n, url: url)
  return CheckRefreshResult(n: -1)

proc addHeadersModule*(ctx: JSContext) =
  ctx.registerType(Headers)

{.pop.} # raises: []
