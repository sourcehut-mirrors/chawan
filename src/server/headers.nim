import std/strutils
import std/tables

import monoucha/fromjs
import monoucha/javascript
import monoucha/jserror
import monoucha/quickjs
import monoucha/tojs
import types/opt
import utils/twtstr

type
  HeaderGuard* = enum
    hgNone = "none"
    hgImmutable = "immutable"
    hgRequest = "request"
    hgRequestNoCors = "request-no-cors"
    hgResponse = "response"

  Headers* = ref object
    table*: Table[string, seq[string]]
    guard*: HeaderGuard

  HeadersInitType = enum
    hitSequence, hitTable

  HeadersInit* = object
    case t: HeadersInitType
    of hitSequence:
      s: seq[(string, string)]
    of hitTable:
      tab: Table[string, string]

jsDestructor(Headers)

const HTTPWhitespace = {'\n', '\r', '\t', ' '}

proc fromJS(ctx: JSContext; val: JSValueConst; res: var HeadersInit):
    Err[void] =
  if JS_IsUndefined(val) or JS_IsNull(val):
    return err()
  var headers: Headers
  if ctx.fromJS(val, headers).isSome:
    res = HeadersInit(t: hitSequence, s: @[])
    for k, v in headers.table:
      for vv in v:
        res.s.add((k, vv))
    return ok()
  if ctx.isSequence(val):
    res = HeadersInit(t: hitSequence)
    if ctx.fromJS(val, res.s).isSome:
      return ok()
  res = HeadersInit(t: hitTable)
  ?ctx.fromJS(val, res.tab)
  return ok()

const TokenChars = {
  '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_', '`', '|', '~'
} + AsciiAlphaNumeric

func isValidHeaderName*(s: string): bool =
  return s.len > 0 and AllChars - TokenChars notin s

func isValidHeaderValue*(s: string): bool =
  return s.len == 0 or s[0] notin {' ', '\t'} and s[^1] notin {' ', '\t'} and
    '\n' notin s

func isForbiddenRequestHeader*(name, value: string): bool =
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

func isForbiddenResponseHeaderName*(name: string): bool =
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

func isNoCorsSafelistedName(name: string): bool =
  return name.equalsIgnoreCase("Accept") or
    name.equalsIgnoreCase("Accept-Language") or
    name.equalsIgnoreCase("Content-Language") or
    name.equalsIgnoreCase("Content-Type")

const CorsUnsafeRequestByte = {
  char(0x00)..char(0x08), char(0x10)..char(0x1F), '"', '(', ')', ':', '<', '>',
  '?', '@', '[', '\\', ']', '{', '}', '\e'
}

func isNoCorsSafelisted(name, value: string): bool =
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

func get0(this: Headers; name: string): string =
  return this.table[name].join(", ")

proc get*(ctx: JSContext; this: Headers; name: string): JSValue {.jsfunc.} =
  if not name.isValidHeaderName():
    JS_ThrowTypeError(ctx, "Invalid header name")
    return JS_EXCEPTION
  let name = name.toHeaderCase()
  if name notin this.table:
    return JS_NULL
  return ctx.toJS(this.get0(name))

proc removeRange(this: Headers) =
  if this.guard == hgRequestNoCors:
    #TODO do this case insensitively
    this.table.del("Range") # privileged no-CORS request headers
    this.table.del("range")

proc append(this: Headers; name, value: string): JSResult[void] {.jsfunc.} =
  let value = value.strip(chars = HTTPWhitespace)
  if not ?this.validate(name, value):
    return ok()
  let name = name.toHeaderCase()
  if this.guard == hgRequestNoCors:
    if name in this.table:
      let tmp = this.get0(name) & ", " & value
      if not name.isNoCorsSafelisted(tmp):
        return ok()
  if name in this.table:
    this.table[name].add(value)
  else:
    this.table[name] = @[value]
  this.removeRange()
  ok()

proc delete(this: Headers; name: string): JSResult[void] {.jsfunc.} =
  let name = name.toHeaderCase()
  if not ?this.validate(name, "") or name notin this.table:
    return ok()
  if not name.isNoCorsSafelistedName() and not name.equalsIgnoreCase("Range"):
    return ok()
  this.table.del(name)
  this.removeRange()
  ok()

proc has(this: Headers; name: string): JSResult[bool] {.jsfunc.} =
  if not name.isValidHeaderName():
    return errTypeError("Invalid header name")
  let name = name.toHeaderCase()
  return ok(name in this.table)

proc set(this: Headers; name, value: string): JSResult[void] {.jsfunc.} =
  let value = value.strip(chars = HTTPWhitespace)
  if not ?this.validate(name, value):
    return
  if this.guard == hgRequestNoCors and not name.isNoCorsSafelisted(value):
    return
  this.table[name.toHeaderCase()] = @[value]
  this.removeRange()

proc fill(headers: Headers; s: seq[(string, string)]): JSResult[void] =
  for (k, v) in s:
    ?headers.append(k, v)
  ok()

proc fill(headers: Headers; tab: Table[string, string]): JSResult[void] =
  for k, v in tab:
    ?headers.append(k, v)
  ok()

proc fill*(headers: Headers; init: HeadersInit): JSResult[void] =
  case init.t
  of hitSequence: return headers.fill(init.s)
  of hitTable: return headers.fill(init.tab)

func newHeaders*(guard = hgNone): Headers =
  return Headers(guard: guard)

func newHeaders(obj = none(HeadersInit)): JSResult[Headers] {.jsctor.} =
  let headers = Headers(guard: hgNone)
  if obj.isSome:
    ?headers.fill(obj.get)
  return ok(headers)

func newHeaders*(table: openArray[(string, string)]): Headers =
  let headers = Headers()
  for (k, v) in table:
    let k = k.toHeaderCase()
    headers.table.withValue(k, vs):
      vs[].add(v)
    do:
      headers.table[k] = @[v]
  return headers

func newHeaders*(table: Table[string, string]): Headers =
  let headers = Headers()
  for k, v in table:
    let k = k.toHeaderCase()
    headers.table.withValue(k, vs):
      vs[].add(v)
    do:
      headers.table[k] = @[v]
  return headers

func clone*(headers: Headers): Headers =
  return Headers(table: headers.table)

proc add*(headers: Headers; k: string; v: sink string) =
  let k = k.toHeaderCase()
  headers.table.withValue(k, p):
    p[].add(v)
  do:
    headers.table[k] = @[v]

proc `[]=`*(headers: Headers; k: static string; v: string) =
  const k = k.toHeaderCase()
  headers.table[k] = @[v]

func `[]`*(headers: Headers; k: static string): var string =
  const k = k.toHeaderCase()
  return headers.table[k][0]

func contains*(headers: Headers; k: static string): bool =
  const k = k.toHeaderCase()
  return k in headers.table

func getOrDefault*(headers: Headers; k: static string; default = ""): string =
  const k = k.toHeaderCase()
  headers.table.withValue(k, p):
    return p[][0]
  do:
    return default

proc addHeadersModule*(ctx: JSContext) =
  ctx.registerType(Headers)
