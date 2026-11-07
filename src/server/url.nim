# See https://url.spec.whatwg.org/#url-parsing.

{.push raises: [].}

when NimMajor >= 2:
  import std/assertions
import std/algorithm

import io/packetreader
import io/packetwriter
import js/constcharp
import js/cutils
import js/fromjs
import js/jsbind
import js/jsnull
import js/jsopaque
import js/jsref
import js/jstypes
import js/jsutils
import js/libunicode
import js/quickjs
import js/tojs
import utils/cowstr
import utils/luwrap
import utils/opt
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
    stData = "data"
    stEd2k = "ed2k"
    stFile = "file"
    stFtp = "ftp"
    stHttp = "http"
    stHttps = "https"
    stJavascript = "javascript"
    stMailto = "mailto"
    stStream = "stream"
    stWs = "ws"
    stWss = "wss"
    stXChaCookie = "x-cha-cookie"

  SearchIteratorType = enum
    sitEntries, sitValues, sitKeys

  URLSearchParams* = JSRef[URLSearchParamsObj]

  URLSearchParamsObj = object
    list: seq[tuple[name, value: Str]]
    url: URL
    # keep a cached string of search.  we update the list whenever the
    # source search changes (which we can check in O(1) thanks to CoW)
    search: Str

  URLSearchParamsIterator = JSRef[URLSearchParamsIteratorObj]

  URLSearchParamsIteratorObj* = object
    t: SearchIteratorType
    params: URLSearchParams
    i: int

  URL* = JSRef[URLObj]

  URLNil* = JSNullRef[URLObj]

  #TODO ideally URL would look something like
  # URLObj = object
  #   buf: Str
  #   schemeStart: int32
  #   usernameStart: int32
  #   ...
  # then toStr would be O(1).
  URLObj = object
    scheme: Str
    username*: Str
    password*: Str
    opaquePath: bool
    hostType: HostType
    schemeType*: SchemeType
    port: int32 # -1 -> no port, other values: has port
    hostname*: Str
    pathname*: Str
    search*: Str
    hash*: Str

  OriginType* = enum
    otOpaque, otTuple

  Origin* = object
    t*: OriginType
    s: Str

# Forward declarations
proc parseURL0*(input: openArray[char]; base = URL(nil)): URL
proc parseURL0*(input: Str; base = URL(nil)): URL
proc serialize*(url: URL; excludeHash = false; excludePassword = false): Str
proc serializeip(ipv4: uint32): Str
proc serializeip(ipv6: array[8, uint16]): Str
proc host*(url: URL): Str
proc toStr*(url: URL): Str
proc toStr*(params: URLSearchParams): Str
proc getClassID*(t: typedesc[URL]): JSClassID
proc getClassID(t: typedesc[URLSearchParamsIterator]): JSClassID

proc swrite*(w: var PacketWriter; url: URL) =
  if url != nil:
    w.swrite(url.serialize())
  else:
    w.swrite(str(""))

proc sread*(r: var PacketReader; url: var URL): PacketCode =
  var s: Str
  ?r.sread(s)
  if s == "":
    url = URL(nil)
  else:
    url = parseURL0(s)
  ok()

# -1 if not special
# 0 if file
# > 0 if special
const SpecialPort = [
  stUnknown: -1i32,
  stAbout: -1,
  stBlob: -1,
  stCache: -1,
  stData: -1,
  stEd2k: -1,
  stFile: 0,
  stFtp: 21,
  stHttp: 80,
  stHttps: 443,
  stJavascript: -1,
  stMailto: -1,
  stStream: -1,
  stWs: 80,
  stWss: 443,
  stXChaCookie: -1,
]

template isSpecial(url: URL): bool =
  SpecialPort[url.schemeType] >= 0

proc parseIpv6(input: openArray[char]): Str =
  var pieceIndex = 0
  var compress = -1
  var i = 0
  var address = array[8, uint16].default
  if input[i] == ':':
    if i + 1 >= input.len or input[i + 1] != ':':
      return str("")
    i += 2
    inc pieceIndex
    compress = pieceIndex
  while i < input.len:
    if pieceIndex == 8:
      return str("")
    if input[i] == ':':
      if compress != -1:
        return str("")
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
          e = input.find('.', i)
          if e < 0:
            return str("")
        let x = parseUInt8NoLeadingZero(input.toOpenArray(i, e - 1))
        if x.isErr:
          return str("")
        address[pieceIndex] = address[pieceIndex] * 0x100 + uint16(x.get)
        if j == 1 or j == 3:
          inc pieceIndex
        i = e + 1
      break
    elif i < input.len:
      if input[i] != ':' or i + 1 >= input.len:
        return str("")
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
    return str("")
  return address.serializeip()

proc parseIpv4Number(s: openArray[char]): Opt[uint32] =
  var i = 0
  var R = 10u32
  if s.len >= 2 and s[0] == '0':
    if s[1] in {'x', 'X'}:
      i = 2
      R = 16
    else:
      i = 1
      R = 8
    if i == s.len:
      return ok(0)
  return parseUInt32Base(s.toOpenArray(i, s.high), radix = R)

proc parseIpv4(input: Str): Opt[uint32] =
  var last = input.high
  if last >= 0 and input[last] == '.':
    dec last
  var res = 0'u32
  var i = 0
  var pi = 0
  var npart = 4'u32
  while i <= last:
    let c = input[i]
    if c == '.':
      let tmp = ?parseIpv4Number(input.toOpenArray(pi, i - 1))
      if tmp > 0xFF:
        return err()
      dec npart
      if npart == 0:
        return err()
      res = (res shl 8) or tmp
      pi = i + 1
    inc i
  let tmp = ?parseIpv4Number(input.toOpenArray(pi, last))
  if npart < 4:
    let shift = npart shl 3'u32
    if tmp >= 1'u32 shl shift:
      return err()
    res = res shl shift
  res = res or tmp
  ok(res)

const ForbiddenHostChars = {
  '\0', '\t', '\n', '\r', ' ', '#', '/', ':', '<', '>', '?', '@', '[',
  '\\', ']', '^', '|'
}
const ForbiddenDomainChars = ForbiddenHostChars + Controls + {'%'}
proc opaqueParseHost(input: Str; schemeType: SchemeType;
    hostType: var HostType): Str =
  var o = initGrowbufOfCap(input.len)
  for c in input:
    # non-standard ed2k quirk for web-compat
    if c in ForbiddenHostChars and not (c == '|' and schemeType == stEd2k):
      return str("")
    o.percentEncode(c, ControlPercentEncodeSet)
  hostType = htOpaque
  o.toStr()

proc endsInNumber(input: Str): bool =
  if input.len <= 0:
    return false
  var i = input.high
  if input[i] == '.':
    dec i
  if i < 0 or input[i] == '.': # empty part
    return false
  # if no period, start from 0
  i = input.rfind('.', start = 0, last = i) + 1
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
  var j = 0
  var res: seq[uint32] = @[]
  for k, c in s:
    if c == '-':
      j = k
    res &= uint32(c)
  res.setLen(j)
  if j > 0:
    inc j
  var n = 0x80u32
  var bias = 72u32
  var i = 0u32
  while j < s.len:
    let oldi = i
    var w = 1u32
    for k in countup(36u32, uint32.high, 36u32):
      if j >= s.len:
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

proc punyEncode(s: openArray[char]): StrNil =
  var res = initGrowbuf()
  var us: seq[uint32] = @[]
  for u in s.points:
    if u <= 0x7F:
      res &= char(u)
    else:
      us.add(u)
  us.sort()
  var h = uint32(res.len)
  if uint(res.len) != uint32(res.len): # overflow
    return str(nil)
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
      return str(nil)
    delta = uint32(delta2)
    n = m
    for u in s.points:
      if u < m:
        inc delta
        if delta == 0: # overflow
          return str(nil)
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
  res.toStr().toStrNil()

proc mapIdna(ctx: LUContext; mapped: var seq[uint32]; u: uint32): Opt[void] =
  case u
  of 0xFF0E, 0x3002, 0xFF61: mapped &= 0x2E # dot-likes map to period
  of 0xDF, 0x1E9E: mapped &= 0xDF # scharfes S
  of 0x03C2: mapped &= u # sigma maps to itself
  of 0x200C, 0x200D: return err() # ZWJ/ZWNJ maps to itself & is GC other
  elif ctx.isBidiControl(u): return err() # bidi_control is disallowed
  else:
    let norm = [u].normalize(UNICODE_NFKC)
    for nu in norm:
      var res {.noinit.}: array[LRE_CC_RES_LEN_MAX, uint32]
      let p = cast[ptr UncheckedArray[uint32]](addr res[0])
      let len = lre_case_conv(p, nu, 2) # case fold
      for mu in res.toOpenArray(0, len - 1):
        if ctx.isDefaultIgnorable(mu):
          continue # NFKC_CF
        if mu == 0xFFFC or mu == 0xFFFD or mu in 0xE0001u32..0xE007Fu32:
          return err() # base exclusion set
        if ctx.isIDSOperator(mu) or ctx.isWhiteSpace(mu) or ctx.isOther(mu):
          return err() # not in base valid set
        mapped &= mu
  ok()

proc processIdna(str: Str; beStrict: bool): Str =
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
      return str("")
  mapped = mapped.normalize()
  if mapped.len == 0:
    return str("")
  var labels = initGrowbuf()
  var first = true
  for label in mapped.toUTF8().split('.'):
    if label.startsWith("xn--"):
      let x0 = punyDecode(label.toOpenArray("xn--".len, label.high))
      if x0.isErr:
        return str("")
      let x1 = x0.get.normalize()
      # CheckHyphens is false
      if x0.get != x1 or x1.len > 0 and ctx.isMark(x1[0]):
        return str("") #error
      for u in x1:
        if u == uint32('.'):
          return str("") #error
        var mapping: seq[uint32] = @[]
        if ctx.mapIdna(mapping, u).isErr:
          return str("") # error
        if mapping.len != 1 or mapping[0] != u:
          return str("") # error, mapped value
        if beStrict and u < 0x80 and char(u) notin AsciiAlphaNumeric + {'-'}:
          return str("") # error, STD3 rules
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
  labels.toStr()

proc unicodeToAscii(s: Str; beStrict: bool): Str =
  let processed = s.processIdna(beStrict)
  var labels = initGrowbuf()
  var all = 0
  var first = true
  for label in processed.split('.'):
    var s = initGrowbuf()
    if NonAscii in label:
      let x = punyEncode(label.toOpenArray())
      if x == nil:
        return str("")
      s.addM("xn--", x.asStr)
    else:
      s = initGrowbufSink(label, label.len)
    if beStrict: # VerifyDnsLength
      let rl = s.toOpenArray().pointLen()
      if rl notin 1..63:
        return str("")
      all += rl
    if not first:
      labels &= '.'
    labels &= s
    first = false
  if beStrict: # VerifyDnsLength
    if all notin 1..253:
      return str("") #error
  labels.toStr()

proc domainToAscii(domain: Str; beStrict: bool): Str =
  var res = domain.toLowerAscii()
  if beStrict or NonAscii in domain:
    if res.startsWith("xn--") or res.find(".xn--") != -1 or NonAscii in res:
      res = domain.unicodeToAscii(beStrict)
  move(res)

proc parseHost*(input: Str; schemeType: SchemeType; hostType: var HostType):
    Str =
  let special = SpecialPort[schemeType] >= 0
  if input.len <= 0:
    if not special:
      hostType = htOpaque
    return str("")
  if input[0] == '[':
    if input[^1] != ']' or input.len < 3:
      return str("")
    let ipv6 = parseIpv6(input.toOpenArray(1, input.high - 1))
    if ipv6 != "":
      hostType = htIpv6
    return ipv6
  if not special:
    return opaqueParseHost(input, schemeType, hostType)
  let domain = percentDecode(input)
  let asciiDomain = domain.domainToAscii(beStrict = false)
  if asciiDomain == "" or ForbiddenDomainChars in asciiDomain:
    return str("")
  if asciiDomain.endsInNumber():
    if ipv4 := parseIpv4(asciiDomain):
      hostType = htIpv4
      return ipv4.serializeip()
    return str("")
  hostType = htDomain
  asciiDomain

proc canShortenPath(schemeType: SchemeType; pathname: openArray[char]): bool =
  if schemeType == stFile and (pathname.len == 3 or
        pathname.len == 4 and pathname[2] == '/') and
      pathname[0] == '/' and pathname[1] in AsciiAlpha and pathname[2] == ':':
    return false
  true

proc shortenPath(url: URL) =
  if canShortenPath(url.schemeType, url.pathname.toOpenArray()) and
      url.pathname.len > 0:
    url.pathname.setLen(url.pathname.rfind('/'))

proc shortenPath(pathname: var Growbuf; schemeType: SchemeType) =
  if canShortenPath(schemeType, pathname.toOpenArray()) and pathname.len > 0:
    pathname.setLen(pathname.rfind('/'))

proc includesCredentials*(url: URL): bool =
  return url.username != "" or url.password != ""

proc isWinDriveLetter(s: openArray[char]): bool =
  return s.len == 2 and s[0] in AsciiAlpha and s[1] in {':', '|'}

proc parseOpaquePath(input: openArray[char]; pointer: var int; url: URL):
    URLState =
  var nextState = usDone
  var buf = initGrowbuf()
  var i = pointer
  while i < input.len:
    let c = input[i]
    inc i
    case c
    of '?':
      nextState = usQuery
      break
    of '#':
      nextState = usFragment
      break
    of ' ':
      if i < input.len and input[i] in {'?', '#'}:
        buf &= "%20"
      else:
        buf &= ' '
    else:
      buf.percentEncode(c, ControlPercentEncodeSet)
  url.pathname = buf.toStr()
  pointer = i
  nextState

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
  if pointer >= input.len:
    return usDone
  let c = input[pointer]
  if c == '?':
    inc pointer
    return usQuery
  if c == '#':
    inc pointer
    return usFragment
  url.search = str("")
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
  var buf = initGrowbuf()
  var i = pointer
  while i < input.len:
    let c = input[i]
    if c in AsciiAlphaNumeric + {'+', '-', '.'}:
      buf &= c.toLowerAscii()
    elif c == ':':
      let schemeType = parseEnumNoCase[SchemeType](buf.toOpenArray)
        .get(stUnknown)
      let port = SpecialPort[schemeType]
      if override:
        if url.isSpecial != (port >= 0):
          return usNoScheme
        if (url.includesCredentials or url.port >= 0) and schemeType == stFile:
          return usNoScheme
        if url.hostType == htNone and url.schemeType == stFile:
          return usNoScheme
      url.scheme = move(buf).toStr()
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
  var buffer = initGrowbuf()
  var beforeBuffer = pointer
  var i = pointer
  var username = initGrowbuf()
  var password = initGrowbuf()
  while i < input.len:
    let c = input[i]
    let nexti = i + 1
    if c in {'/', '?', '#'} or url.isSpecial and c == '\\':
      break
    if c == '@':
      if atSignSeen:
        buffer.insert(str("%40"), 0)
      atSignSeen = true
      for c in buffer:
        if c == ':' and not passwordSeen:
          passwordSeen = true
          continue
        if passwordSeen:
          password.percentEncode(c, UserInfoPercentEncodeSet)
        else:
          username.percentEncode(c, UserInfoPercentEncodeSet)
      buffer.setLen(0)
      beforeBuffer = nexti
    else:
      buffer &= c
    i = nexti
  url.username = username.toStr()
  url.password = password.toStr()
  if atSignSeen and buffer == "":
    return usFail
  pointer = beforeBuffer
  return usHost

proc parseFileHost(input: openArray[char]; pointer: var int; url: URL;
    override: bool): URLState =
  var buf = initGrowbuf()
  for i in pointer ..< input.len:
    let c = input[i]
    if c in {'/', '\\', '?', '#'}:
      break
    buf &= c
  let bufs = buf.toStr()
  if not override and bufs.toOpenArray().isWinDriveLetter():
    return usPath
  pointer += bufs.len
  if bufs == "":
    url.hostType = htDomain
    url.hostname = str("")
  else:
    var t = htNone
    let hostname = parseHost(bufs, url.schemeType, t)
    if t == htNone:
      return usFail
    url.hostType = t
    if t == htDomain and hostname == "localhost":
      url.hostname = str("")
    else:
      url.hostname = hostname
  if override:
    return usFail
  return usPathStart

proc parseHostState(input: openArray[char]; pointer: var int; url: URL;
    override: bool; state: URLState): URLState =
  if override and url.schemeType == stFile:
    return input.parseFileHost(pointer, url, override)
  var insideBrackets = false
  var buf = initGrowbuf()
  while pointer < input.len:
    let c = input[pointer]
    if c == ':' and not insideBrackets:
      if buf == "" or override and state == usHostname:
        return usFail
      var t = htNone
      let hostname = parseHost(move(buf).toStr(), url.schemeType, t)
      if t == htNone:
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
      buf &= c
    inc pointer
  if url.isSpecial and buf == "":
    return usFail
  if override and buf == "" and (url.includesCredentials or url.port >= 0):
    return usFail
  var t = htNone
  let hostname = parseHost(buf.toStr(), url.schemeType, t)
  if t == htNone:
    return usFail
  url.hostname = hostname
  url.hostType = t
  if override:
    return usFail
  return usPathStart

proc parsePort(input: openArray[char]; pointer: var int; url: URL;
    override: bool): URLState =
  var buffer = initGrowbuf()
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
    let i = parseInt32(buffer.toOpenArray()).get(int32.high)
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
  return input[i] in AsciiAlpha and input[i + 1] in {':', '|'} and
    (i + 2 >= input.len or input[i + 2] in {'/', '\\', '?', '#'})

proc parseFileSlash(input: openArray[char]; pointer: var int; base, url: URL;
    override: bool): URLState =
  if pointer < input.len and input[pointer] in {'/', '\\'}:
    inc pointer
    return input.parseFileHost(pointer, url, override)
  if base != nil and base.schemeType == stFile:
    url.hostname = base.hostname
    url.hostType = base.hostType
    if not input.startsWithWinDriveLetter(pointer) and
        base.pathname.len >= 3 and base.pathname[1] in AsciiAlpha and
        base.pathname[2] == ':':
      url.pathname &= ['/', base.pathname[1], ':']
  return usPath

proc parseFile(input: openArray[char]; pointer: var int; base, url: URL;
    override: bool): URLState =
  url.scheme = str("file")
  url.schemeType = stFile
  url.hostname = str("")
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
    if pointer >= input.len:
      return usDone
    let c = input[pointer]
    if c == '?':
      inc pointer
      return usQuery
    elif c == '#':
      inc pointer
      return usFragment
    else:
      url.search = str("")
      if not input.startsWithWinDriveLetter(pointer):
        url.shortenPath()
      else:
        url.pathname = str("")
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
        inc pointer
        return usQuery
      if c == '#':
        inc pointer
        return usFragment
    if c == '/':
      inc pointer
    return usPath
  if override and url.hostType == htNone:
    url.pathname = str("/")
    inc pointer
  return usDone

proc isSingleDotPathSegment(s: Growbuf): bool =
  s == "." or s.equalsIgnoreCase("%2e")

proc isDoubleDotPathSegment(s: Growbuf): bool =
  s == ".." or s.equalsIgnoreCase(".%2e") or s.equalsIgnoreCase("%2e.") or
    s.equalsIgnoreCase("%2e%2e")

proc parsePath(input: openArray[char]; pointer: var int; url: URL;
    override: bool): URLState =
  var nextState = usPath
  var buffer = initGrowbuf()
  var pathname = initGrowbufSink(move(url.pathname))
  let schemeType = url.schemeType
  while pointer < input.len:
    let c = input[pointer]
    inc pointer
    if c == '/' or url.isSpecial and c == '\\' or
        not override and c in {'?', '#'}:
      if c == '?':
        nextState = usQuery
        break
      elif c == '#':
        nextState = usFragment
        break
      let slashCond = c != '/' and (not url.isSpecial or c != '\\')
      if buffer.isDoubleDotPathSegment():
        shortenPath(pathname, schemeType)
        if slashCond:
          pathname &= '/'
      elif buffer.isSingleDotPathSegment() and slashCond:
        pathname &= '/'
      elif not buffer.isSingleDotPathSegment():
        if url.schemeType == stFile and pathname == "" and
            buffer.toOpenArray().isWinDriveLetter():
          buffer[1] = ':'
        pathname &= '/'
        pathname &= buffer
      buffer.setLen(0)
    else:
      buffer.percentEncode(c, PathPercentEncodeSet)
  let slashCond = pointer >= input.len or input[pointer] != '/' and
    (not url.isSpecial or input[pointer] != '\\')
  if buffer.isDoubleDotPathSegment():
    shortenPath(pathname, schemeType)
    if slashCond:
      pathname &= '/'
  elif buffer.isSingleDotPathSegment() and slashCond:
    pathname &= '/'
  elif not buffer.isSingleDotPathSegment():
    if url.schemeType == stFile and pathname == "" and
        buffer.toOpenArray().isWinDriveLetter():
      buffer[1] = ':'
    pathname &= '/'
    pathname &= buffer
  url.pathname = pathname.toStr()
  nextState

proc parseQuery(input: openArray[char]; pointer: var int; url: URL;
    override: bool): URLState =
  #TODO encoding
  var buf = initGrowbuf('?')
  var i = pointer
  while i < input.len:
    let c = input[i]
    if not override and c == '#':
      break
    buf &= c
    inc i
  pointer = i
  let set = if url.isSpecial:
    SpecialQueryPercentEncodeSet
  else:
    QueryPercentEncodeSet
  url.search = buf.toStr().percentEncode(set)
  if pointer < input.len:
    inc pointer
    return usFragment
  return usDone

proc parseURLImpl(input: openArray[char]; base, url: URL;
    state: URLState; override: bool): URLState =
  var pointer = 0
  let input = input.deleteChars({'\r', '\n', '\t'})
  var state = state
  if state == usSchemeStart:
    state = input.toOpenArray().parseSchemeStart(pointer, base, url, override)
  if state == usAuthority:
    state = input.toOpenArray().parseAuthority(pointer, url)
  if state in {usHost, usHostname}:
    state = input.toOpenArray().parseHostState(pointer, url, override, state)
  if state == usPort:
    state = input.toOpenArray().parsePort(pointer, url, override)
  if state == usFile:
    state = input.toOpenArray().parseFile(pointer, base, url, override)
  if state == usPathStart:
    state = input.toOpenArray().parsePathStart(pointer, url, override)
  if state == usPath:
    state = input.toOpenArray().parsePath(pointer, url, override)
  if state == usQuery:
    state = input.toOpenArray().parseQuery(pointer, url, override)
  if state == usFragment:
    var hash = initGrowbuf("#")
    while pointer < input.len:
      hash.percentEncode(input[pointer], FragmentPercentEncodeSet)
      inc pointer
    url.hash = hash.toStr()
  return state

#TODO encoding
proc parseURL0*(input: openArray[char]; base = URL(nil)): URL =
  let url = jsNew URLObj(port: -1)
  const NoStrip = AllChars - C0Controls - {' '}
  var starti = input.find(NoStrip)
  var endi = input.rfind(NoStrip)
  if starti < 0:
    starti = 0
    endi = -1
  if input.toOpenArray(starti, endi).parseURLImpl(base, url, usSchemeStart,
      override = false) == usFail:
    return URL(nil)
  return url

proc parseURL0*(input: Str; base = URL(nil)): URL =
  parseURL0(input.toOpenArray(), base)

proc parseURL1(input: openArray[char]; url: URL; state: URLState) =
  discard input.parseURLImpl(base = URL(nil), url, state, override = true)

proc parseURL*(input: openArray[char]; base = URL(nil)): Opt[URL] =
  let url = parseURL0(input, base)
  if url == nil:
    return err()
  if url.schemeType == stBlob:
    #TODO blob urls
    discard
  ok(url)

proc parseURL*(input: Str; base = URL(nil)): Opt[URL] =
  parseURL(input.toOpenArray(), base)

proc parseJSURL*(ctx: JSContext; s: Str; base = URL(nil)):
    Opt[URL] =
  let url = parseURL0(s.toOpenArray(), base)
  if url == nil:
    JS_ThrowTypeError(ctx, "%s is not a valid URL", s.toCStringConst())
    return err()
  ok(url)

proc serializeip(ipv4: uint32): Str =
  initStrM(ipv4 shr 24, '.', (ipv4 shr 16) and 0xFF, '.',
    (ipv4 shr 8) and 0xFF, '.', (ipv4 and 0xFF))

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

proc addHexLower(buf: var Growbuf; u: uint16) =
  var x = u
  let len = if (u and 0xF000) != 0:
    4
  elif (u and 0x0F00) != 0:
    3
  elif (u and 0xF0) != 0:
    2
  else:
    1
  let olen = buf.len
  buf.setLen(olen + len)
  for i in countdown(buf.high, olen):
    buf[i] = HexCharsLower[x and 0xF]
    x = x shr 4

proc serializeip(ipv6: array[8, uint16]): Str =
  let compress = findZeroSeq(ipv6)
  var ignore0 = false
  var buf = initGrowbuf('[')
  for i, n in ipv6:
    if ignore0:
      if n == 0:
        continue
      else:
        ignore0 = false
    if i == compress:
      if i == 0:
        buf &= "::"
      else:
        buf &= ':'
      ignore0 = true
      continue
    buf.addHexLower(n)
    if i != ipv6.high:
      buf &= ':'
  buf &= ']'
  buf.toStr()

proc serialize*(url: URL; excludeHash = false; excludePassword = false): Str =
  var buf = initGrowbufOfCap(url.scheme.len + url.username.len +
    url.password.len + url.pathname.len + url.search.len + url.hash.len + 3)
  buf &= url.scheme
  buf &= ':'
  if url.hostType != htNone:
    buf &= "//"
    if url.includesCredentials:
      buf &= url.username
      if not excludePassword and url.password != "":
        buf.addM(':', url.password)
      buf &= '@'
    buf &= url.hostname
    if url.port >= 0:
      buf.addM(':', url.port)
  elif not url.opaquePath and url.pathname.len >= 2 and url.pathname[1] == '/':
    buf &= "/."
  buf.addM(url.pathname, url.search)
  if not excludeHash:
    buf &= url.hash
  buf.toStr()

proc `$`*(url: URL): string =
  $url.serialize()

# from a to b
proc cloneInto(a, b: URL) =
  b.scheme = a.scheme
  b.username = a.username
  b.password = a.password
  b.opaquePath = a.opaquePath
  b.hostType = a.hostType
  b.schemeType = a.schemeType
  b.port = a.port
  b.hostname = a.hostname
  b.pathname = a.pathname
  b.search = a.search
  b.hash = a.hash

proc newURL*(url: URL): URL =
  result = jsNew URLObj()
  if result != nil:
    url.cloneInto(result)

proc isIP*(url: URL): bool =
  return url.hostType in {htIpv4, htIpv6}

# https://url.spec.whatwg.org/#urlencoded-parsing
proc parseFromURLEncoded(input: openArray[char]): seq[(Str, Str)] =
  var res = newSeq[(Str, Str)]()
  for s in input.split('&'):
    if s == "":
      continue
    var name = initGrowbufSink(s.until('='))
    var value = initGrowbufSink(s.after('='))
    for c in name.mitems:
      if c == '+':
        c = ' '
    for c in value.mitems:
      if c == '+':
        c = ' '
    res.add((percentDecode(name.toStr()), percentDecode(value.toStr())))
  move(res)

# https://url.spec.whatwg.org/#urlencoded-serializing
proc serializeFormURLEncoded*(kvs: seq[(Str, Str)]; spaceAsPlus = true;
    questionMark = false): Str =
  var buf = initGrowbuf()
  if questionMark and kvs.len > 0:
    buf &= '?'
  for (name, value) in kvs:
    if buf.len > 0:
      buf &= '&'
    buf.percentEncode(name, ApplicationXWWWFormUrlEncodedSet, spaceAsPlus)
    buf &= '='
    buf.percentEncode(value, ApplicationXWWWFormUrlEncodedSet, spaceAsPlus)
  buf.toStr()

proc findSearchParam(url: URL; name: openArray[char]): int =
  var i = 1
  while i + name.len <= url.search.len:
    if url.search.startsWith(name, i) and
        (i + name.len >= url.search.len or url.search[i + name.len] == '&'):
      return i
    i = url.search.find('&', i) + 1
    if i <= 0:
      break
  return -1

proc getSearchParam*(url: URL; name: openArray[char]): Str =
  let i = url.findSearchParam(name)
  if i < 0:
    return str("") # not found
  if i + name.len >= url.search.len or url.search[i + name.len] != '=':
    return str("") # empty
  return url.search.until('&', i + name.len + 1)

proc sync(params: URLSearchParams) =
  if params.url != nil and params.search != params.url.search:
    let i = int(params.url.search.len > 0)
    params.list = parseFromURLEncoded(
      params.url.search.toOpenArray(i, params.url.search.high))
    params.search = params.url.search

proc update(params: URLSearchParams) =
  if params.url == nil:
    return
  params.url.search = serializeFormURLEncoded(params.list, questionMark = true)
  params.search = params.url.search

jsClassPublicDef(URLSearchParams):
  classDef.iterable = jitPair

  proc newURLSearchParams(ctx: JSContext; init = JS_UNDEFINED.vc):
      Opt[URLSearchParams] {.jsctor.} =
    let params = jsNew URLSearchParamsObj()
    if params != nil and not JS_IsUndefined(init):
      if ?ctx.isSequence(init):
        ?ctx.fromJS(init, params.list)
      elif JS_IsObject(init):
        var t: JSKeyValuePair[Str, Str]
        ?ctx.fromJS(init, t)
        params.list = move(t.s)
      else:
        var res: Str
        ?ctx.fromJS(init, res)
        var i = 0
        if res.len > 0 and res[0] == '?':
          inc i
        params.list = parseFromURLEncoded(res.toOpenArray(i, res.high))
    return ok(params)

  proc toStr*(params: URLSearchParams): Str {.jsfunc: "toString".} =
    params.sync()
    serializeFormURLEncoded(params.list)

  proc append(params: URLSearchParams; name, value: sink Str) {.jsfunc.} =
    params.sync()
    params.list.add((name, value))
    params.update()

  proc delete(params: URLSearchParams; name: Str) {.jsfunc.} =
    params.sync()
    for i in countdown(params.list.high, 0):
      if params.list[i][0] == name:
        params.list.delete(i)
    params.update()

  proc get(ctx: JSContext; params: URLSearchParams; name: Str): JSValue
      {.jsfunc.} =
    params.sync()
    for it in params.list:
      if it.name == name:
        return ctx.toJS(it.value)
    return JS_NULL

  proc getAll(params: URLSearchParams; name: Str): seq[Str] {.jsfunc.} =
    params.sync()
    var res = newSeq[Str]()
    for it in params.list:
      if it.name == name:
        res.add(it.value)
    move(res)

  proc has(ctx: JSContext; params: URLSearchParams; name: Str;
      jsValue = JS_UNDEFINED.vc): JSValue {.jsfunc.} =
    params.sync()
    if JS_IsUndefined(jsValue):
      for it in params.list:
        if it.name == name:
          return JS_TRUE
    else:
      var value: Str
      if ctx.fromJS(jsValue, value).isErr:
        return JS_EXCEPTION
      for it in params.list:
        if it.name == name and value == it.value:
          return JS_TRUE
    return JS_FALSE

  proc set(params: URLSearchParams; name, value: Str) {.jsfunc.} =
    params.sync()
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

  proc entries(params: URLSearchParams; t: SearchIteratorType):
      URLSearchParamsIterator {.jsmfunc("entries", sitEntries),
      jsmfunc("values", sitValues), jsmfunc("keys", sitKeys).} =
    jsNew URLSearchParamsIteratorObj(t: t, params: params)

  proc sort(params: URLSearchParams) {.jsfunc.} =
    params.sync()
    params.list.sort(proc(a, b: tuple[name, value: Str]): int =
      cmp(a.name, b.name)
    )
    params.update()

  proc size(params: URLSearchParams): uint32 {.jsfget.} =
    params.sync()
    uint32(params.list.len)

jsClassNameDef(URLSearchParamsIterator, "URLSearchParams Iterator"):
  classDef.iterable = jitIterator

  proc next(ctx: JSContext; iter: URLSearchParamsIterator; done: var JS_BOOL):
      JSValue {.jsiter.} =
    iter.params.sync()
    let i = iter.i
    if i >= iter.params.list.len:
      done = JS_BOOL(1)
      return JS_UNDEFINED
    inc iter.i
    done = JS_BOOL(0)
    case iter.t
    of sitEntries: ctx.toJS(iter.params.list[i])
    of sitKeys: ctx.toJS(iter.params.list[i].name)
    of sitValues: ctx.toJS(iter.params.list[i].value)

# URL
proc origin*(url: URL): Origin =
  case url.schemeType
  of stBlob:
    #TODO
    let pathURL = parseURL(url.pathname)
    if pathURL.isErr:
      return Origin(t: otOpaque, s: url.toStr())
    return pathURL.get.origin
  of stFtp, stHttp, stHttps, stWs, stWss:
    return Origin(t: otTuple, s: initStrM(url.scheme, "://", url.host))
  else:
    return Origin(t: otOpaque, s: url.toStr())

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
    return Origin(t: otTuple, s: initStrM(url.scheme, "://", url.host))
  return Origin(t: otOpaque, s: url.toStr())

proc `==`*(a, b: Origin): bool {.error.} =
  discard

proc isSameOrigin*(a, b: Origin): bool =
  return a.t == b.t and a.s == b.s

proc toStr*(origin: Origin): Str =
  if origin.t == otOpaque:
    return str("null")
  return origin.s

proc scheme*(url: URL): lent Str =
  url[].scheme

jsClassPublicDef(URL):
  jsget URL, username
  jsget URL, password
  jsget URL, hostname
  jsget URL, pathname

  proc newURL*(ctx: JSContext; s: Str; base = JS_UNDEFINED.vc): Opt[URL]
      {.jsctor.} =
    var baseURL: URL
    if not JS_IsUndefined(base):
      var s: Str
      if ctx.fromJS(base, s).isErr:
        return err()
      baseURL = ?ctx.parseJSURL(s)
    ctx.parseJSURL(s, baseURL)

  proc toStr*(url: URL): Str {.jsfunc: "toString", jsfunc: "toJSON",
      jsfget: "href".} =
    url.serialize()

  proc setHref(ctx: JSContext; url: URL; s: Str) {.jsfset: "href".} =
    let purl = parseURL0(s)
    if purl != nil:
      purl.cloneInto(url)
    else:
      JS_ThrowTypeError(ctx, "%s is not a valid URL", s)

  proc searchParams(ctx: JSContext; this: JSValueConst): JSValue {.jsfget.} =
    var url: URL
    ?ctx.fromJS(this, url)
    var desc: JSPropertyDescriptor
    let res = JS_GetOwnProperty(ctx, addr desc, this,
      ctx.getAtom(jszSearchParams))
    if res < 0:
      return JS_EXCEPTION
    if res == 0:
      JS_FreeValue(ctx, desc.getter)
      JS_FreeValue(ctx, desc.setter)
      desc.value = ctx.toJSNew(jsNew URLSearchParamsObj(url: url))
      if JS_IsException(desc.value.vc):
        return JS_EXCEPTION
      if JS_SetProperty(ctx, this, ctx.getAtom(jszSearchParams),
          JS_DupValue(ctx, desc.value.vc)) < 0:
        JS_FreeValue(ctx, desc.value)
        return JS_EXCEPTION
    return desc.value

  proc jsOrigin*(url: URL): Str {.jsfget: "origin".} =
    return url.origin.toStr()

  proc protocol*(ctx: JSContext; url: URL): JSValue {.jsfget.} =
    if url.schemeType == stUnknown:
      return ctx.toJS(initGrowbufM(url.scheme, ':'))
    const enumId = getJSEnumId(SchemeType)
    let n = int(url.schemeType)
    let rt = JS_GetRuntime(ctx)
    let rtOpaque = rt.getOpaque()
    if rtOpaque.enumMap.len <= enumId:
      rtOpaque.enumMap.setLen(enumId + 1)
    if rtOpaque.enumMap[enumId].atoms.len <= n:
      rtOpaque.enumMap[enumId].atoms.setLen(n + 1)
    var atom = rtOpaque.enumMap[enumId].atoms[n]
    if atom == JS_ATOM_NULL:
      let s = initGrowbufM(url.scheme, ':')
      atom = ?JS_NewAtomLen(ctx, cast[cstringConst](s.p), csize_t(s.len))
      rtOpaque.enumMap[enumId].atoms[n] = atom
    return JS_AtomToValue(ctx, atom)

  proc setProtocol*(url: URL; s: Str) {.jsfset: "protocol".} =
    parseURL1(initGrowbufM(s, ':').toOpenArray(), url, usSchemeStart)

  proc setUsername*(url: URL; username: Str) {.jsfset: "username".} =
    if url.isNetPath():
      url.username = username.percentEncode(UserInfoPercentEncodeSet)

  proc setPassword*(url: URL; password: Str) {.jsfset: "password".} =
    if url.isNetPath():
      url.password = password.percentEncode(UserInfoPercentEncodeSet)

  proc host*(url: URL): Str {.jsfget.} =
    if url.hostType == htNone:
      return str("")
    if url.port >= 0:
      return initStrM(url.hostname, ':', url.port)
    return url.hostname

  proc setHost*(url: URL; s: Str) {.jsfset: "host".} =
    if not url.opaquePath:
      parseURL1(s.toOpenArray(), url, usHost)

  proc setHostname*(url: URL; s: Str) {.jsfset: "hostname".} =
    if not url.opaquePath:
      parseURL1(s.toOpenArray(), url, usHostname)

  proc port*(url: URL): Str {.jsfget.} =
    if url[].port >= 0:
      return url[].port.toStr()
    return str("")

  proc setPort*(url: URL; s: Str) {.jsfset: "port".} =
    if url.isNetPath():
      if s == "":
        url.port = -1
      else:
        parseURL1(s.toOpenArray(), url, usPort)

  proc setPathname*(url: URL; s: Str) {.jsfset: "pathname".} =
    if not url.opaquePath:
      url.pathname = str("")
      parseURL1(s.toOpenArray(), url, usPathStart)

  proc search(ctx: JSContext; url: URL): JSValue {.jsfget.} =
    if url.search.len <= 1:
      return ctx.toJS("")
    ctx.toJS(url.search)

  proc setSearch*(url: URL; s: Str) {.jsfset: "search".} =
    if s.len <= 0:
      url.search = str("")
    else:
      let idx = if s[0] == '?': 1 else: 0
      parseURL1(s.toOpenArray(idx, s.high), url, usQuery)

  proc hash(ctx: JSContext; url: URL): JSValue {.jsfget.} =
    if url.hash.len <= 1:
      return ctx.toJS("")
    ctx.toJS(url.hash)

  proc setHash*(url: URL; s: Str) {.jsfset: "hash".} =
    if s.len <= 0:
      url.hash = str("")
    else:
      let idx = if s[0] == '#': 1 else: 0
      parseURL1(s.toOpenArray(idx, s.high), url, usFragment)

  proc parse(ctx: JSContext; url: Str; base = JS_UNDEFINED.vc): URL
      {.jsstfunc.} =
    return ctx.newURL(url, base).get(URL(nil))

  proc canParse(ctx: JSContext; url: Str; base = JS_UNDEFINED.vc): bool
      {.jsstfunc.} =
    return ctx.newURL(url, base).isOk

proc addURLModule*(ctx: JSContext): Opt[void] =
  ?ctx.registerClass(URLDef)
  ?ctx.registerClass(URLSearchParamsDef)
  ?ctx.registerClassNoNamespace(URLSearchParamsIteratorDef)
  ok()

{.pop.} # raises: []
