# See https://url.spec.whatwg.org/#url-parsing.
{.push raises: [].}

import std/algorithm
import std/strutils

import io/packetreader
import io/packetwriter
import monoucha/fromjs
import monoucha/javascript
import monoucha/jstypes
import monoucha/libunicode
import monoucha/quickjs
import monoucha/tojs
import types/opt
import utils/luwrap
import utils/twtstr

type
  URLState = enum
    usFail, usDone, usSchemeStart, usNoScheme, usFile, usFragment, usAuthority,
    usPath, usQuery, usHost, usHostname, usPort, usPathStart

  HostType* = enum
    htNone, htDomain, htIpv4, htIpv6, htOpaque

  # List of known schemes.
  SchemeType* = enum
    stUnknown = ""
    stAbout = "about"
    stBlob = "blob"
    stCache = "cache"
    stCgiBin = "cgi-bin"
    stData = "data"
    stFile = "file"
    stFtp = "ftp"
    stHttp = "http"
    stHttps = "https"
    stJavascript = "javascript"
    stMailto = "mailto"
    stStream = "stream"
    stWs = "ws"
    stWss = "wss"

  URLSearchParams* = ref object
    list: seq[tuple[name, value: string]]
    url: URL

  URL* = ref object
    scheme: string
    username* {.jsget.}: string
    password* {.jsget.}: string
    opaquePath: bool
    hostType: HostType
    schemeType*: SchemeType
    port: int32 # -1 -> no port, other values: has port
    hostname* {.jsget.}: string
    pathname* {.jsget.}: string
    search* {.jsget.}: string
    hash* {.jsget.}: string
    searchParamsInternal: URLSearchParams

  OriginType* = enum
    otOpaque, otTuple

  Origin* = ref object
    t*: OriginType
    domain: string
    s: string

jsDestructor(URL)
jsDestructor(URLSearchParams)

# Forward declarations
proc parseURL0*(input: string; base: URL = nil): URL
proc serialize*(url: URL; excludeHash = false; excludePassword = false):
  string
proc serializeip(ipv4: uint32): string
proc serializeip(ipv6: array[8, uint16]): string
proc host*(url: URL): string

proc swrite*(w: var PacketWriter; url: URL) =
  if url != nil:
    w.swrite(url.serialize())
  else:
    w.swrite("")

proc sread*(r: var PacketReader; url: var URL) =
  var s: string
  r.sread(s)
  if s == "":
    url = nil
  else:
    url = parseURL0(s)

# -1 if not special
# 0 if file
# > 0 if special
const SpecialPort = [
  stUnknown: -1i32,
  stAbout: -1,
  stBlob: -1,
  stCache: -1,
  stCgiBin: -1,
  stData: -1,
  stFile: 0,
  stFtp: 21,
  stHttp: 80,
  stHttps: 443,
  stJavascript: -1,
  stMailto: -1,
  stStream: -1,
  stWs: 80,
  stWss: 443,
]

template isSpecial(url: URL): bool =
  SpecialPort[url.schemeType] >= 0

proc parseSchemeType(buffer: string): SchemeType =
  return parseEnumNoCase[SchemeType](buffer).get(stUnknown)

proc parseIpv6(input: openArray[char]): string =
  var pieceIndex = 0
  var compress = -1
  var i = 0
  var address = array[8, uint16].default
  if input[i] == ':':
    if i + 1 >= input.len or input[i + 1] != ':':
      return ""
    i += 2
    inc pieceIndex
    compress = pieceIndex
  while i < input.len:
    if pieceIndex == 8:
      return ""
    if input[i] == ':':
      if compress != -1:
        return ""
      inc i
      inc pieceIndex
      compress = pieceIndex
      continue
    var value: uint16 = 0
    let L = min(i + 4, input.len)
    let oi = i
    while i < L and (let n = hexValue(input[i]); n != -1):
      value = value * 0x10 + uint16(n)
      inc i
    if i < input.len and input[i] == '.' and pieceIndex <= 6: # dual address
      i = oi
      for j in 0 ..< 4:
        var e = input.len
        if j < 3: # find ipv4 separator
          e = i + input.toOpenArray(i, input.high).find('.')
          if e < i: # not found
            return ""
        let x = parseUInt8NoLeadingZero(input.toOpenArray(i, e - 1))
        if x.isErr:
          return ""
        address[pieceIndex] = address[pieceIndex] * 0x100 + uint16(x.get)
        if j == 1 or j == 3:
          inc pieceIndex
        i = e + 1
      break
    elif i < input.len:
      if input[i] != ':' or i + 1 >= input.len:
        return ""
      inc i
    address[pieceIndex] = value
    inc pieceIndex
  if compress != -1:
    var swaps = pieceIndex - compress
    pieceIndex = 7
    while pieceIndex > 0 and swaps > 0:
      swap(address[pieceIndex], address[compress + swaps - 1])
      dec pieceIndex
      dec swaps
  elif pieceIndex != 8:
    return ""
  return address.serializeip()

proc parseIpv4Number(s: string): uint32 =
  var i = 0
  var R = 10u32
  if s.len >= 2 and s[0] == '0':
    if s[1] in {'x', 'X'}:
      i = 2
      R = 16
    else:
      i = 1
      R = 8
  if i >= s.len:
    return 0
  return parseUInt32Base(s.toOpenArray(i, s.high), radix = R).get(uint32.high)

proc parseIpv4(input: string): Opt[uint32] =
  var numbers: seq[uint32] = @[]
  var prevEmpty = false
  var i = 0
  for part in input.split('.'):
    if i > 4 or prevEmpty:
      return err()
    inc i
    if part == "":
      prevEmpty = true
      continue
    let num = parseIpv4Number(part)
    if num notin 0u32..255u32:
      return err()
    numbers.add(num)
  if numbers[^1] >= 1u32 shl ((5 - numbers.len) * 8):
    return err()
  var ipv4 = uint32(numbers[^1])
  for i in 0 ..< numbers.high:
    let n = uint32(numbers[i])
    ipv4 += n * (1u32 shl ((3 - i) * 8))
  ok(ipv4)

const ForbiddenHostChars = {
  char(0x00), '\t', '\n', '\r', ' ', '#', '/', ':', '<', '>', '?', '@', '[',
  '\\', ']', '^', '|'
}
const ForbiddenDomainChars = ForbiddenHostChars + {'%'}
proc opaqueParseHost(input: string): string =
  var o = ""
  for c in input:
    if c in ForbiddenHostChars:
      return ""
    o.percentEncode(c, ControlPercentEncodeSet)
  move(o)

proc endsInNumber(input: string): bool =
  if input.len == 0:
    return false
  var i = input.high
  if input[i] == '.':
    dec i
  i = input.rfind('.', last = i)
  if i < 0:
    return false
  inc i
  if i + 1 < input.len and input[i] == '0' and input[i + 1] in {'x', 'X'}:
    # hex?
    i += 2
    while i < input.len and input[i] != '.':
      if input[i] notin AsciiHexDigit:
        return false
      inc i
  else:
    while i < input.len and input[i] != '.':
      if input[i] notin AsciiDigit:
        return false
      inc i
  return true

# RFC 3492
proc punyAdapt(delta, len: uint32; first: bool): uint32 =
  var delta = if first:
    delta div 700
  else:
    delta div 2
  delta += delta div len
  var k = 0u32
  while delta > 455:
    delta = delta div 35
    k += 36
  return k + (36 * delta) div (delta + 38)

proc punyCharDecode(c: char): Opt[uint32] =
  if c in AsciiDigit:
    return ok(uint32(c) - uint32('0') + 26)
  let c = c.toLowerAscii()
  if c in AsciiLowerAlpha:
    return ok(uint32(c) - uint32('a'))
  err()

proc punyDecode(s: openArray[char]): Opt[seq[uint32]] =
  var j = 0u
  var res: seq[uint32] = @[]
  for k, c in s:
    if c == '-':
      j = uint(k)
    res &= uint32(c)
  res.setLen(j)
  if j > 0:
    inc j
  var n = 0x80u32
  var bias = 72u32
  var i = 0u32
  while j < uint(s.len):
    let oldi = i
    var w = 1u32
    for k in countup(36u32, uint32.high, 36u32):
      if j >= uint(s.len):
        return err()
      let d = ?punyCharDecode(s[j])
      inc j
      let dw = d * w
      if uint32.high - dw < i: # overflow
        return err()
      i += dw
      let t = if k <= bias: 1u32 elif k >= bias + 26: 26u32 else: k - bias
      if d < t:
        break
      if static(uint32.high div 36) < w: # overflow
        return err()
      w *= 36 - t
    let L = uint32(res.len + 1)
    bias = punyAdapt(i - oldi, L, oldi == 0)
    let iL = i div L
    if uint32.high - iL < n: # overflow
      return err()
    n += iL
    i = i mod L
    res.insert(n, i)
    inc i
  ok(move(res))

proc punyCharEncode(q: uint32): char =
  if q < 26:
    return char(uint32('a') + q)
  return char(uint32('0') + q - 26)

proc punyEncode(s: openArray[char]): Opt[string] =
  var res = ""
  var us: seq[uint32] = @[]
  for u in s.points:
    if u <= 0x7F:
      res &= char(u)
    else:
      us.add(u)
  us.sort()
  var h = uint32(res.len)
  if uint(res.len) != uint32(res.len): # overflow
    return err()
  let b = h
  if res.len > 0:
    res &= '-'
  var n = 0x7Fu32
  var bias = 72u32
  var delta = 0u32
  for m in us:
    if m == n:
      continue
    let delta2 = uint64(delta) + uint64(m - n - 1) * uint64(h + 1)
    if uint64(delta) > uint64(uint32.high): # overflow
      return err()
    delta = uint32(delta2)
    n = m
    for u in s.points:
      if u < m:
        inc delta
        if delta == 0: # overflow
          return err()
      elif u == m:
        var q = delta
        for k in countup(36u32, uint32.high, 36u32):
          let t = if k <= bias: 1u32 elif k >= bias + 26: 26u32 else: k - bias
          if q < t:
            break
          let tt = 36 - t
          res &= punyCharEncode(t + (q - t) mod tt)
          q = (q - t) div tt
        res &= punyCharEncode(q)
        bias = punyAdapt(delta, h + 1, h == b)
        delta = 0
        inc h
    inc delta
  ok(move(res))

proc mapIdna(ctx: LUContext; mapped: var seq[uint32]; u: uint32): Opt[void] =
  case u
  of 0xFF0E, 0x3002, 0xFF61: mapped &= 0x2E # dot-likes map to period
  of 0xDF, 0x1E9E: mapped &= 0xDF # scharfes S
  of 0x03C2: mapped &= u # sigma maps to itself
  elif ctx.isBidiControl(u): return err() # bidi_control is disallowed
  else:
    var res {.noinit.}: array[3, uint32]
    let p = cast[ptr UncheckedArray[uint32]](addr res[0])
    let len = lre_case_conv(p, u, 2) # case fold
    let mapping = res.toOpenArray(0, len - 1).normalize(UNICODE_NFKC)
    for mu in mapping:
      if mu == 0xFFFC or mu == 0xFFFD or mu in 0xE0001u32..0xE007Fu32:
        return err() # base exclusion set
      if ctx.isIDSOperator(mu) or ctx.isWhiteSpace(mu) or ctx.isOther(mu):
        return err() # not in base valid set
    mapped &= mapping
  ok()

proc processIdna(str: string; beStrict: bool): string =
  # CheckHyphens = false
  # CheckBidi = true
  # CheckJoiners = true
  # UseSTD3ASCIIRules = beStrict
  # Transitional_Processing = false
  # VerifyDnsLength = beStrict
  var mapped: seq[uint32] = @[]
  let ctx = LUContext()
  for u in str.points:
    if ctx.mapIdna(mapped, u).isErr:
      return ""
  mapped = mapped.normalize()
  if mapped.len == 0:
    return ""
  let luctx = LUContext()
  var labels = ""
  var first = true
  for label in mapped.toUTF8().split('.'):
    if label.startsWith("xn--"):
      let x0 = punyDecode(label.toOpenArray("xn--".len, label.high))
      if x0.isErr:
        return ""
      let x1 = x0.get.normalize()
      # CheckHyphens is false
      if x0.get != x1 or x1.len > 0 and luctx.isMark(x1[0]):
        return "" #error
      for u in x1:
        if u == uint32('.'):
          return "" #error
        var mapping: seq[uint32] = @[]
        if ctx.mapIdna(mapping, u).isErr:
          return "" # error
        if mapping.len != 1 or mapping[0] != u:
          return "" # error, mapped value
        if beStrict and u < 0x80 and char(u) notin AsciiAlphaNumeric + {'-'}:
          return "" # error, STD3 rules
        #TODO check joiners
        #TODO check bidi
      if not first:
        labels &= '.'
      labels &= x1.toUTF8()
    else:
      if not first:
        labels &= '.'
      labels &= label
    first = false
  move(labels)

proc unicodeToAscii(s: string; beStrict: bool): string =
  let processed = s.processIdna(beStrict)
  var labels = ""
  var all = 0
  var first = true
  for label in processed.split('.'):
    var s = ""
    if AllChars - Ascii in label:
      let x = punyEncode(label)
      if x.isErr:
        return ""
      s = "xn--" & x.get
    else:
      s = label
    if beStrict: # VerifyDnsLength
      let rl = s.pointLen()
      if rl notin 1..63:
        return ""
      all += rl
    if not first:
      labels &= '.'
    labels &= s
    first = false
  if beStrict: # VerifyDnsLength
    if all notin 1..253:
      return "" #error
  move(labels)

proc domainToAscii(domain: string; beStrict: bool): string =
  result = domain.toLowerAscii()
  if beStrict or result.startsWith("xn--") or result.find(".xn--") != -1 or
      AllChars - Ascii in result:
    result = domain.unicodeToAscii(beStrict)

proc parseHost*(input: string; special: bool; hostType: var HostType): string =
  if input.len == 0:
    return ""
  if input[0] == '[':
    if input[^1] != ']' or input.len < 3:
      return ""
    var ipv6 = parseIpv6(input.toOpenArray(1, input.high - 1))
    if ipv6 != "":
      hostType = htIpv6
    return move(ipv6)
  if not special:
    hostType = htOpaque
    return opaqueParseHost(input)
  let domain = percentDecode(input)
  var asciiDomain = domain.domainToAscii(beStrict = false)
  if asciiDomain == "" or ForbiddenDomainChars in asciiDomain:
    return ""
  if asciiDomain.endsInNumber():
    if ipv4 := parseIpv4(asciiDomain):
      hostType = htIpv4
      return ipv4.serializeip()
    return ""
  hostType = htDomain
  move(asciiDomain)

proc shortenPath(url: URL) =
  if url.schemeType == stFile and (url.pathname.len == 3 or
        url.pathname.len == 4 and url.pathname[2] == '/') and
      url.pathname[0] == '/' and url.pathname[1] in AsciiAlpha and
      url.pathname[2] == ':':
    return
  if url.pathname.len > 0:
    url.pathname.setLen(url.pathname.rfind('/'))

proc includesCredentials(url: URL): bool =
  return url.username != "" or url.password != ""

proc isWinDriveLetter(s: string): bool =
  return s.len == 2 and s[0] in AsciiAlpha and s[1] in {':', '|'}

proc parseOpaquePath(input: openArray[char]; pointer: var int; url: URL):
    URLState =
  while pointer < input.len:
    let c = input[pointer]
    if c == '?':
      url.search = "?"
      inc pointer
      return usQuery
    elif c == '#':
      url.hash = "#"
      inc pointer
      return usFragment
    else:
      url.pathname.percentEncode(c, ControlPercentEncodeSet)
    inc pointer
  return usDone

proc parseSpecialAuthorityIgnoreSlashes(input: openArray[char];
    pointer: var int): URLState =
  while pointer < input.len and input[pointer] in {'/', '\\'}:
    inc pointer
  return usAuthority

proc parseRelativeSlash(input: openArray[char]; pointer: var int;
    base, url: URL): URLState =
  if url.isSpecial and pointer < input.len and input[pointer] in {'/', '\\'}:
    inc pointer
    return input.parseSpecialAuthorityIgnoreSlashes(pointer)
  if pointer < input.len and input[pointer] == '/':
    inc pointer
    return usAuthority
  url.username = base.username
  url.password = base.password
  url.hostname = base.hostname
  url.hostType = base.hostType
  url.port = base.port
  return usPath

proc parseRelative(input: openArray[char]; pointer: var int;
    base, url: URL): URLState =
  url.scheme = base.scheme
  url.schemeType = base.schemeType
  assert url.schemeType != stFile
  if pointer < input.len and input[pointer] == '/' or
      url.isSpecial and pointer < input.len and input[pointer] == '\\':
    inc pointer
    return input.parseRelativeSlash(pointer, base, url)
  url.username = base.username
  url.password = base.password
  url.hostname = base.hostname
  url.hostType = base.hostType
  url.port = base.port
  url.pathname = base.pathname
  url.opaquePath = base.opaquePath
  url.search = base.search
  if pointer < input.len and input[pointer] == '?':
    url.search = "?"
    inc pointer
    return usQuery
  if pointer < input.len and input[pointer] == '#':
    url.hash = "#"
    inc pointer
    return usFragment
  url.search = ""
  url.shortenPath()
  return usPath

proc parseSpecialRelativeOrAuthority(input: openArray[char]; pointer: var int;
    base, url: URL): URLState =
  if pointer + 1 < input.len and input[pointer] == '/' and
      input[pointer + 1] == '/':
    pointer += 2
    return input.parseSpecialAuthorityIgnoreSlashes(pointer)
  return input.parseRelative(pointer, base, url)

proc parseScheme(input: openArray[char]; pointer: var int; base, url: URL;
    override: bool): URLState =
  var buffer = ""
  var i = pointer
  while i < input.len:
    let c = input[i]
    if c in AsciiAlphaNumeric + {'+', '-', '.'}:
      buffer &= c.toLowerAscii()
    elif c == ':':
      let schemeType = parseSchemeType(buffer)
      let port = SpecialPort[schemeType]
      if override:
        if url.isSpecial != (port >= 0):
          return usNoScheme
        if (url.includesCredentials or url.port >= 0) and schemeType == stFile:
          return usNoScheme
        if url.hostType == htNone and url.schemeType == stFile:
          return usNoScheme
      url.scheme = move(buffer)
      url.schemeType = schemeType
      if override:
        if port == url.port:
          url.port = -1
        return usDone
      pointer = i + 1
      if url.schemeType == stFile:
        return usFile
      if url.isSpecial:
        if base != nil and base.scheme == url.scheme:
          return input.parseSpecialRelativeOrAuthority(pointer, base, url)
        # special authority slashes state
        if pointer + 1 < input.len and input[pointer] == '/' and
            input[pointer + 1] == '/':
          pointer += 2
        return input.parseSpecialAuthorityIgnoreSlashes(pointer)
      if i + 1 < input.len and input[i + 1] == '/':
        inc pointer
        # path or authority state
        if pointer < input.len and input[pointer] == '/':
          inc pointer
          return usAuthority
        return usPath
      url.opaquePath = true
      url.pathname = ""
      return input.parseOpaquePath(pointer, url)
    else:
      break
    inc i
  return usNoScheme

proc parseSchemeStart(input: openArray[char]; pointer: var int;
    base, url: URL; override: bool): URLState =
  var state = usNoScheme
  if pointer < input.len and input[pointer] in AsciiAlpha:
    # continue to scheme state
    state = input.parseScheme(pointer, base, url, override)
  if state == usNoScheme:
    pointer = 0 # start over
  if override:
    return usDone
  if state == usNoScheme:
    if base == nil:
      return usFail
    if base.opaquePath and (pointer >= input.len or input[pointer] != '#'):
      return usFail
    if base.opaquePath and pointer < input.len and input[pointer] == '#':
      url.scheme = base.scheme
      url.schemeType = base.schemeType
      url.pathname = base.pathname
      url.opaquePath = base.opaquePath
      url.search = base.search
      url.hash = "#"
      inc pointer
      return usFragment
    if base.schemeType == stFile:
      return usFile
    return input.parseRelative(pointer, base, url)
  return state

proc parseAuthority(input: openArray[char]; pointer: var int; url: URL):
    URLState =
  var atSignSeen = false
  var passwordSeen = false
  var buffer = ""
  var beforeBuffer = pointer
  while pointer < input.len:
    let c = input[pointer]
    if c in {'/', '?', '#'} or url.isSpecial and c == '\\':
      break
    if c == '@':
      if atSignSeen:
        buffer = "%40" & buffer
      atSignSeen = true
      for c in buffer:
        if c == ':' and not passwordSeen:
          passwordSeen = true
          continue
        if passwordSeen:
          url.password.percentEncode(c, UserInfoPercentEncodeSet)
        else:
          url.username.percentEncode(c, UserInfoPercentEncodeSet)
      buffer = ""
      beforeBuffer = pointer + 1
    else:
      buffer &= c
    inc pointer
  if atSignSeen and buffer == "":
    return usFail
  pointer = beforeBuffer
  return usHost

proc parseFileHost(input: openArray[char]; pointer: var int; url: URL;
    override: bool): URLState =
  let buffer = input.until({'/', '\\', '?', '#'}, pointer)
  pointer += buffer.len
  if not override and buffer.isWinDriveLetter():
    return usPath
  if buffer == "":
    url.hostType = htDomain
    url.hostname = ""
  else:
    var t = htNone
    var hostname = parseHost(buffer, url.isSpecial, t)
    if hostname == "":
      return usFail
    url.hostType = t
    if t == htDomain and hostname == "localhost":
      url.hostname = ""
    else:
      url.hostname = move(hostname)
  if override:
    return usFail
  return usPathStart

proc parseHostState(input: openArray[char]; pointer: var int; url: URL;
    override: bool; state: URLState): URLState =
  if override and url.schemeType == stFile:
    return input.parseFileHost(pointer, url, override)
  var insideBrackets = false
  var buffer = ""
  while pointer < input.len:
    let c = input[pointer]
    if c == ':' and not insideBrackets:
      if override and state == usHostname:
        return usFail
      var t = htNone
      let hostname = parseHost(buffer, url.isSpecial, t)
      if hostname == "":
        return usFail
      url.hostname = hostname
      url.hostType = t
      inc pointer
      return usPort
    elif c in {'/', '?', '#'} or url.isSpecial and c == '\\':
      break
    else:
      if c == '[':
        insideBrackets = true
      elif c == ']':
        insideBrackets = false
      buffer &= c
    inc pointer
  if url.isSpecial and buffer == "":
    return usFail
  if override and buffer == "" and (url.includesCredentials or url.port >= 0):
    return usFail
  var t = htNone
  let hostname = parseHost(buffer, url.isSpecial, t)
  if hostname == "":
    return usFail
  url.hostname = hostname
  url.hostType = t
  if override:
    return usFail
  return usPathStart

proc parsePort(input: openArray[char]; pointer: var int; url: URL;
    override: bool): URLState =
  var buffer = ""
  var i = pointer
  while i < input.len:
    let c = input[i]
    if c in AsciiDigit:
      buffer &= c
    elif c in {'/', '?', '#'} or url.isSpecial and c == '\\' or override:
      break
    else:
      return usFail
    inc i
  pointer = i
  if buffer != "":
    let i = parseInt32(buffer).get(int32.high)
    # can't be negative, buffer only includes AsciiDigit
    if i > 65535:
      return usFail
    if SpecialPort[url.schemeType] == i:
      url.port = -1
    else:
      url.port = i
  if override:
    return usFail
  return usPathStart

proc startsWithWinDriveLetter(input: openArray[char]; i: int): bool =
  if i + 1 >= input.len:
    return false
  return input[i] in AsciiAlpha and input[i + 1] in {':', '|'}

proc parseFileSlash(input: openArray[char]; pointer: var int; base, url: URL;
    override: bool): URLState =
  if pointer < input.len and input[pointer] in {'/', '\\'}:
    inc pointer
    return input.parseFileHost(pointer, url, override)
  if base != nil and base.schemeType == stFile:
    url.hostname = base.hostname
    url.hostType = base.hostType
    if not input.startsWithWinDriveLetter(pointer) and
        base.pathname.len > 3 and base.pathname[0] in AsciiAlpha and
        base.pathname[1] == ':' and base.pathname[2] == '/':
      url.pathname &= base.pathname.until('/') & '/'
  return usPath

proc parseFile(input: openArray[char]; pointer: var int; base, url: URL;
    override: bool): URLState =
  url.scheme = "file"
  url.schemeType = stFile
  url.hostname = ""
  url.hostType = htOpaque
  if pointer < input.len and input[pointer] in {'/', '\\'}:
    inc pointer
    return input.parseFileSlash(pointer, base, url, override)
  if base != nil and base.schemeType == stFile:
    url.hostname = base.hostname
    url.hostType = base.hostType
    url.pathname = base.pathname
    url.opaquePath = base.opaquePath
    url.search = base.search
    if pointer < input.len:
      let c = input[pointer]
      if c == '?':
        url.search = "?"
        inc pointer
        return usQuery
      elif c == '#':
        url.hash = "#"
        inc pointer
        return usFragment
      else:
        url.search = ""
        if not input.startsWithWinDriveLetter(pointer):
          url.shortenPath()
        else:
          url.pathname = ""
  return usPath

proc parsePathStart(input: openArray[char]; pointer: var int; url: URL;
    override: bool): URLState =
  if url.isSpecial:
    if pointer < input.len and input[pointer] in {'/', '\\'}:
      inc pointer
    return usPath
  if pointer < input.len:
    let c = input[pointer]
    if not override:
      if c == '?':
        url.search = "?"
        inc pointer
        return usQuery
      if c == '#':
        url.hash = "#"
        inc pointer
        return usFragment
    if c == '/':
      inc pointer
    return usPath
  if override and url.hostType == htNone:
    url.pathname &= '/'
    inc pointer
  return usDone

proc isSingleDotPathSegment(s: string): bool =
  s == "." or s.equalsIgnoreCase("%2e")

proc isDoubleDotPathSegment(s: string): bool =
  s == ".." or s.equalsIgnoreCase(".%2e") or s.equalsIgnoreCase("%2e.") or
    s.equalsIgnoreCase("%2e%2e")

proc parsePath(input: openArray[char]; pointer: var int; url: URL;
    override: bool): URLState =
  var state = usPath
  var buffer = ""
  while pointer < input.len:
    let c = input[pointer]
    if c == '/' or url.isSpecial and c == '\\' or
        not override and c in {'?', '#'}:
      if c == '?':
        url.search = "?"
        state = usQuery
        inc pointer
        break
      elif c == '#':
        url.hash = "#"
        state = usFragment
        inc pointer
        break
      let slashCond = c != '/' and (not url.isSpecial or c != '\\')
      if buffer.isDoubleDotPathSegment():
        url.shortenPath()
        if slashCond:
          url.pathname &= '/'
      elif buffer.isSingleDotPathSegment() and slashCond:
        url.pathname &= '/'
      elif not buffer.isSingleDotPathSegment():
        if url.schemeType == stFile and url.pathname == "" and
            buffer.isWinDriveLetter():
          buffer[1] = ':'
        url.pathname &= '/'
        url.pathname &= buffer
      buffer = ""
    else:
      buffer.percentEncode(c, PathPercentEncodeSet)
    inc pointer
  let slashCond = pointer >= input.len or input[pointer] != '/' and
    (not url.isSpecial or input[pointer] != '\\')
  if buffer.isDoubleDotPathSegment():
    url.shortenPath()
    if slashCond:
      url.pathname &= '/'
  elif buffer.isSingleDotPathSegment() and slashCond:
    url.pathname &= '/'
  elif not buffer.isSingleDotPathSegment():
    if url.schemeType == stFile and url.pathname == "" and
        buffer.isWinDriveLetter():
      buffer[1] = ':'
    url.pathname &= '/'
    url.pathname &= buffer
  return state

proc parseQuery(input: openArray[char]; pointer: var int; url: URL;
    override: bool): URLState =
  #TODO encoding
  var buffer = ""
  var i = pointer
  while i < input.len:
    let c = input[i]
    if not override and c == '#':
      break
    buffer &= c
    inc i
  pointer = i
  let set = if url.isSpecial:
    SpecialQueryPercentEncodeSet
  else:
    QueryPercentEncodeSet
  url.search.percentEncode(buffer, set)
  if pointer < input.len:
    url.hash = "#"
    inc pointer
    return usFragment
  return usDone

proc parseURLImpl(input: openArray[char]; base, url: URL;
    state: URLState; override: bool): URLState =
  var pointer = 0
  # The URL is special if this is >= 0.
  # A special port of "0" means "no port" (i.e. file scheme).
  let input = input.deleteChars({'\n', '\t'})
  var state = state
  if state == usSchemeStart:
    state = input.parseSchemeStart(pointer, base, url, override)
  if state == usAuthority:
    state = input.parseAuthority(pointer, url)
  if state in {usHost, usHostname}:
    state = input.parseHostState(pointer, url, override, state)
  if state == usPort:
    state = input.parsePort(pointer, url, override)
  if state == usFile:
    state = input.parseFile(pointer, base, url, override)
  if state == usPathStart:
    state = input.parsePathStart(pointer, url, override)
  if state == usPath:
    state = input.parsePath(pointer, url, override)
  if state == usQuery:
    state = input.parseQuery(pointer, url, override)
  if state == usFragment:
    while pointer < input.len:
      url.hash.percentEncode(input[pointer], FragmentPercentEncodeSet)
      inc pointer
  return state

#TODO encoding
proc parseURL0*(input: string; base: URL = nil): URL =
  let url = URL(port: -1)
  const NoStrip = AllChars - C0Controls - {' '}
  let starti0 = input.find(NoStrip)
  let starti = if starti0 == -1: 0 else: starti0
  let endi0 = input.rfind(NoStrip)
  let endi = if endi0 == -1: input.high else: endi0
  if input.toOpenArray(starti, endi).parseURLImpl(base, url, usSchemeStart,
      override = false) == usFail:
    return nil
  return url

proc parseURL1(input: string; url: URL; state: URLState) =
  discard input.parseURLImpl(base = nil, url, state, override = true)

proc parseURL*(input: string; base: URL = nil): Opt[URL] =
  let url = parseURL0(input, base)
  if url == nil:
    return err()
  if url.schemeType == stBlob:
    #TODO blob urls
    discard
  ok(url)

proc parseJSURL*(ctx: JSContext; s: string; base: URL = nil): Opt[URL] =
  let url = parseURL0(s, base)
  if url == nil:
    JS_ThrowTypeError(ctx, "%s is not a valid URL", cstring(s))
    return err()
  ok(url)

proc serializeip(ipv4: uint32): string =
  return $(ipv4 shr 24) & '.' &
    $((ipv4 shr 16) and 0xFF) & '.' &
    $((ipv4 shr 8) and 0xFF) & '.' &
    $(ipv4 and 0xFF)

proc findZeroSeq(ipv6: array[8, uint16]): int =
  var maxi = -1
  var maxn = 0
  var newi = -1
  var newn = 1
  for i, n in ipv6:
    if n == 0:
      inc newn
      if newi == -1:
        newi = i
    else:
      if newn > maxn:
        maxn = newn
        maxi = newi
      newn = 0
      newi = -1
  if newn > maxn:
    return newi
  return maxi

proc serializeip(ipv6: array[8, uint16]): string =
  let compress = findZeroSeq(ipv6)
  var ignore0 = false
  result = "["
  for i, n in ipv6:
    if ignore0:
      if n == 0:
        continue
      else:
        ignore0 = false
    if i == compress:
      if i == 0:
        result &= "::"
      else:
        result &= ':'
      ignore0 = true
      continue
    result &= toHexLower(n)
    if i != ipv6.high:
      result &= ':'
  result &= ']'

proc serialize*(url: URL; excludeHash = false; excludePassword = false):
    string =
  result = url.scheme & ':'
  if url.hostType != htNone:
    result &= "//"
    if url.includesCredentials:
      result &= url.username
      if not excludePassword and url.password != "":
        result &= ':' & url.password
      result &= '@'
    result &= url.hostname
    if url.port >= 0:
      result &= ':' & $url.port
  elif not url.opaquePath and url.pathname.len >= 2 and url.pathname[1] == '/':
    result &= "/."
  result &= url.pathname
  result &= url.search
  if not excludeHash:
    result &= url.hash

proc equals*(a, b: URL; excludeHash = false): bool =
  return a.serialize(excludeHash) == b.serialize(excludeHash)

proc `$`*(url: URL): string {.jsfunc: "toString".} = url.serialize()

proc href(url: URL): string {.jsfget.} =
  return $url

proc toJSON(url: URL): string {.jsfget.} =
  return $url

# from a to b
proc cloneInto(a, b: URL) =
  b[] = a[]
  b.searchParamsInternal = nil

proc newURL*(url: URL): URL =
  result = URL()
  url.cloneInto(result)

proc setHref(ctx: JSContext; url: URL; s: string) {.jsfset: "href".} =
  let purl = parseURL0(s)
  if purl != nil:
    purl.cloneInto(url)
  else:
    JS_ThrowTypeError(ctx, "%s is not a valid URL", s)

proc isIP*(url: URL): bool =
  return url.hostType in {htIpv4, htIpv6}

# https://url.spec.whatwg.org/#urlencoded-parsing
proc parseFromURLEncoded(input: string): seq[(string, string)] =
  result = @[]
  for s in input.split('&'):
    if s == "":
      continue
    var name = s.until('=')
    var value = s.after('=')
    for c in name.mitems:
      if c == '+':
        c = ' '
    for c in value.mitems:
      if c == '+':
        c = ' '
    result.add((name.percentDecode(), value.percentDecode()))

# https://url.spec.whatwg.org/#urlencoded-serializing
proc serializeFormURLEncoded*(kvs: seq[(string, string)]; spaceAsPlus = true):
    string =
  result = ""
  for (name, value) in kvs:
    if result.len > 0:
      result &= '&'
    result.percentEncode(name, ApplicationXWWWFormUrlEncodedSet, spaceAsPlus)
    result &= '='
    result.percentEncode(value, ApplicationXWWWFormUrlEncodedSet, spaceAsPlus)

proc newURLSearchParams(ctx: JSContext; init: JSValueConst = JS_UNDEFINED):
    Opt[URLSearchParams] {.jsctor.} =
  let params = URLSearchParams()
  if not JS_IsUndefined(init):
    if ctx.fromJS(init, params.list).isOk:
      discard
    elif (var t: JSKeyValuePair[string, string]; ctx.fromJS(init, t).isOk):
      params.list = move(t.s)
    else:
      var res: string
      ?ctx.fromJS(init, res)
      if res.len > 0 and res[0] == '?':
        res.delete(0..0)
      params.list = parseFromURLEncoded(res)
  return ok(params)

proc searchParams(url: URL): URLSearchParams {.jsfget.} =
  if url.searchParamsInternal == nil:
    url.searchParamsInternal = URLSearchParams(
      list: parseFromURLEncoded(url.search.substr(1)),
      url: url
    )
  return url.searchParamsInternal

proc `$`*(params: URLSearchParams): string {.jsfunc: "toString".} =
  return serializeFormURLEncoded(params.list)

proc update(params: URLSearchParams) =
  if params.url == nil:
    return
  let serializedQuery = $params
  if serializedQuery == "":
    params.url.search = ""
  else:
    params.url.search = "?" & serializedQuery

proc append(params: URLSearchParams; name, value: sink string) {.jsfunc.} =
  params.list.add((name, value))
  params.update()

proc delete(params: URLSearchParams; name: string) {.jsfunc.} =
  for i in countdown(params.list.high, 0):
    if params.list[i][0] == name:
      params.list.delete(i)
  params.update()

proc get(ctx: JSContext; params: URLSearchParams; name: string): JSValue
    {.jsfunc.} =
  for it in params.list:
    if it.name == name:
      return ctx.toJS(it.value)
  return JS_NULL

proc getAll(params: URLSearchParams; name: string): seq[string] {.jsfunc.} =
  result = newSeq[string]()
  for it in params.list:
    if it.name == name:
      result.add(it.value)

proc has(ctx: JSContext; params: URLSearchParams; name: string;
    jsValue: JSValueConst = JS_UNDEFINED): JSValue {.jsfunc.} =
  if JS_IsUndefined(jsValue):
    for it in params.list:
      if it.name == name:
        return JS_TRUE
  else:
    var value: string
    if ctx.fromJS(jsValue, value).isErr:
      return JS_EXCEPTION
    for it in params.list:
      if it.name == name and value == it.value:
        return JS_TRUE
  return JS_FALSE

proc set(params: URLSearchParams; name: string; value: sink string) {.jsfunc.} =
  var found = false
  for param in params.list.mitems:
    if param.name == name:
      param.value = value
      found = true
      break
  if found:
    params.update()
  else:
    params.append(name, value)

proc newURL*(ctx: JSContext; s: string; base: JSValueConst = JS_UNDEFINED):
    Opt[URL] {.jsctor.} =
  var baseURL: URL = nil
  if not JS_IsUndefined(base):
    var s: string
    if ctx.fromJS(base, s).isErr:
      return err()
    baseURL = ?ctx.parseJSURL(s)
  ctx.parseJSURL(s, baseURL)

proc origin*(url: URL): Origin =
  case url.schemeType
  of stBlob:
    #TODO
    let pathURL = parseURL(url.pathname)
    if pathURL.isErr:
      return Origin(t: otOpaque, s: $url)
    return pathURL.get.origin
  of stFtp, stHttp, stHttps, stWs, stWss:
    return Origin(t: otTuple, s: url.scheme & "://" & url.host)
  else:
    return Origin(t: otOpaque, s: $url)

# Whether the URL is a net path (ref. RFC 2396).
# In general, this means that its serialization will look like
# "scheme://host:port/blah" instead of "scheme:/blah", *except* for
# file URLs which are special-cased for legacy reasons (they become
# "file:///blah", but are treated as absoluteURI).
proc isNetPath*(url: URL): bool =
  return url.hostType != htNone and url.schemeType != stFile

# This follows somewhat different rules from the standard:
# * for URLs with a net_path, the origin is opaque.
# * with other host types, the origin is a tuple origin.
proc authOrigin*(url: URL): Origin =
  if url.isNetPath():
    return Origin(t: otTuple, s: url.scheme & "://" & url.host)
  return Origin(t: otOpaque, s: $url)

proc `==`*(a, b: Origin): bool {.error.} =
  discard

proc isSameOrigin*(a, b: Origin): bool =
  return a.t == b.t and a.s == b.s

proc `$`*(origin: Origin): string =
  if origin.t == otOpaque:
    return "null"
  return origin.s

proc jsOrigin*(url: URL): string {.jsfget: "origin".} =
  return $url.origin

proc protocol*(url: URL): string {.jsfget.} =
  return url.scheme & ':'

proc setProtocol*(url: URL; s: string) {.jsfset: "protocol".} =
  parseURL1(s & ':', url, usSchemeStart)

proc scheme*(url: URL): lent string =
  return url.scheme

proc setUsername*(url: URL; username: string) {.jsfset: "username".} =
  if url.isNetPath():
    url.username = username.percentEncode(UserInfoPercentEncodeSet)

proc setPassword*(url: URL; password: string) {.jsfset: "password".} =
  if url.isNetPath():
    url.password = password.percentEncode(UserInfoPercentEncodeSet)

proc host*(url: URL): string {.jsfget.} =
  if url.hostType == htNone:
    return ""
  if url.port >= 0:
    return url.hostname & ':' & $url.port
  return url.hostname

proc setHost*(url: URL; s: string) {.jsfset: "host".} =
  if not url.opaquePath:
    parseURL1(s, url, usHost)

proc setHostname*(url: URL; s: string) {.jsfset: "hostname".} =
  if not url.opaquePath:
    parseURL1(s, url, usHostname)

proc port*(url: URL): string {.jsfget.} =
  if url.port >= 0:
    return $url.port
  return ""

proc setPort*(url: URL; s: string) {.jsfset: "port".} =
  if url.isNetPath():
    if s == "":
      url.port = -1
    else:
      parseURL1(s, url, usPort)

proc setPathname*(url: URL; s: string) {.jsfset: "pathname".} =
  if not url.opaquePath:
    url.pathname = ""
    parseURL1(s, url, usPathStart)

proc setSearch*(url: URL; s: string) {.jsfset: "search".} =
  if s.len <= 0:
    url.search = ""
    if url.searchParamsInternal != nil:
      url.searchParamsInternal.list.setLen(0)
    return
  let s = if s[0] == '?': s.substr(1) else: s
  url.search = "?"
  parseURL1(s, url, usQuery)
  if url.searchParamsInternal != nil:
    url.searchParamsInternal.list = parseFromURLEncoded(s)

proc setHash*(url: URL; s: string) {.jsfset: "hash".} =
  if s.len <= 0:
    url.hash = ""
  else:
    let s = if s[0] == '#': s.substr(1) else: s
    url.hash = "#"
    parseURL1(s, url, usFragment)

proc jsParse(ctx: JSContext; url: string; base: JSValueConst = JS_UNDEFINED):
    URL {.jsstfunc: "URL.parse".} =
  return ctx.newURL(url, base).get(nil)

proc canParse(ctx: JSContext; url: string; base: JSValueConst = JS_UNDEFINED):
    bool {.jsstfunc: "URL".} =
  return ctx.newURL(url, base).isOk

proc addURLModule*(ctx: JSContext) =
  ctx.registerType(URL)
  ctx.registerType(URLSearchParams)

{.pop.} # raises: []
