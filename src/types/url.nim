# See https://url.spec.whatwg.org/#url-parsing.
import std/algorithm
import std/options
import std/strutils
import std/tables

import io/bufreader
import io/bufwriter
import lib/punycode
import monoucha/fromjs
import monoucha/javascript
import monoucha/jserror
import monoucha/libunicode
import monoucha/quickjs
import types/blob
import types/opt
import utils/luwrap
import utils/map
import utils/twtstr

include res/map/idna_gen

type
  URLState = enum
    usFail, usDone, usSchemeStart, usNoScheme, usFile, usFragment, usAuthority,
    usPath, usQuery, usHost, usHostname, usPort, usPathStart

  BlobURLEntry* = object
    obj: Blob #TODO blob urls

  URLPath* = object
    case opaque*: bool
    of true:
      s*: string
    else:
      ss*: seq[string]

  HostType = enum
    htNone, htDomain, htIpv4, htIpv6, htOpaque

  Host = object
    case t: HostType
    of htNone:
      discard
    of htDomain:
      domain: string
    of htIpv4:
      ipv4: uint32
    of htIpv6:
      ipv6: array[8, uint16]
    of htOpaque:
      opaque: string

  URLSearchParams* = ref object
    list*: seq[tuple[name, value: string]]
    url: URL

  URL* = ref object
    scheme*: string
    username* {.jsget.}: string
    password* {.jsget.}: string
    port: Option[uint16]
    host: Host
    path*: URLPath
    query*: Option[string]
    fragment: Option[string]
    blob: Option[BlobURLEntry]
    searchParamsInternal: URLSearchParams

  OriginType* = enum
    otOpaque, otTuple

  TupleOrigin* = tuple
    scheme: string
    host: Host
    port: Option[uint16]
    domain: Option[string]

  Origin* = ref object
    case t*: OriginType
    of otOpaque:
      s: string
    of otTuple:
      tup: TupleOrigin

jsDestructor(URL)
jsDestructor(URLSearchParams)

# Forward declarations
proc parseURL*(input: string; base = none(URL); override = none(URLState)):
    Option[URL]
func serialize*(url: URL; excludefragment = false; excludepassword = false):
    string

proc swrite*(writer: var BufferedWriter; url: URL) =
  if url != nil:
    writer.swrite(url.serialize())
  else:
    writer.swrite("")

proc sread*(reader: var BufferedReader; url: var URL) =
  var s: string
  reader.sread(s)
  if s == "":
    url = nil
  else:
    let x = parseURL(s)
    if x.isSome:
      url = x.get
    else:
      url = nil

const EmptyPath = URLPath(opaque: true, s: "")
const EmptyHost = Host(t: htDomain, domain: "")

const SpecialSchemes = {
  "ftp": some(21u16),
  "file": none(uint16),
  "http": some(80u16),
  "https": some(443u16),
  "ws": some(80u16),
  "wss": some(443u16),
}.toTable()

func parseIpv6(input: openArray[char]): Option[array[8, uint16]] =
  var pieceindex = 0
  var compress = -1
  var pointer = 0
  var address: array[8, uint16]

  template c(i = 0): char = input[pointer + i]
  template has(i = 0): bool = (pointer + i < input.len)
  template failure(): Option[array[8, uint16]] = none(array[8, uint16])
  if c == ':':
    if not has(1) or c(1) != ':':
      return failure
    pointer += 2
    inc pieceindex
    compress = pieceindex
  while has:
    if pieceindex == 8:
      return failure
    if c == ':':
      if compress != -1:
        return failure
      inc pointer
      inc pieceindex
      compress = pieceindex
      continue
    var value: uint16 = 0
    var length = 0
    while length < 4 and has and c in AsciiHexDigit:
      value = value * 0x10 + uint16(c.hexValue)
      inc pointer
      inc length
    if has and c == '.':
      if length == 0:
        return failure
      pointer -= length
      if pieceindex > 6:
        return failure
      var numbersseen = 0
      while has:
        var ipv4piece = -1
        if numbersseen > 0:
          if c == '.' and numbersseen < 4:
            inc pointer
          else:
            return failure
        if not has or c notin AsciiDigit:
          return failure
        while has and c in AsciiDigit:
          if ipv4piece == -1:
            ipv4piece = c.decValue
          elif ipv4piece == 0:
            return failure
          else:
            ipv4piece = ipv4piece * 10 + c.decValue
          if ipv4piece > 255:
            return failure
          inc pointer
        address[pieceindex] = address[pieceindex] * 0x100 + uint16(ipv4piece)
        inc numbersseen
        if numbersseen == 2 or numbersseen == 4:
          inc pieceindex
      if numbersseen != 4:
        return failure
      break
    elif has:
      if c == ':':
        inc pointer
        if not has:
          return failure
      else:
        return failure
    address[pieceindex] = value
    inc pieceindex
  if compress != -1:
    var swaps = pieceindex - compress
    pieceindex = 7
    while pieceindex != 0 and swaps > 0:
      let sp = address[pieceindex]
      address[pieceindex] = address[compress + swaps - 1]
      address[compress + swaps - 1] = sp
      dec pieceindex
      dec swaps
  elif pieceindex != 8:
    return failure
  return address.some

func parseIpv4Number(s: string): uint32 =
  var input = s
  var R = 10
  if input.len >= 2 and input[0] == '0':
    if input[1] in {'x', 'X'}:
      input.delete(0..1)
      R = 16
    else:
      input.delete(0..0)
      R = 8
  if input == "":
    return 0
  case R
  of 8: return parseOctUInt32(input, allowSign = false).get(uint32.high)
  of 10: return parseUInt32(input, allowSign = false).get(uint32.high)
  of 16: return parseHexUInt32(input, allowSign = false).get(uint32.high)
  else: return 0

func parseIpv4(input: string): Option[uint32] =
  var numbers: seq[uint32] = @[]
  var prevEmpty = false
  var i = 0
  for part in input.split('.'):
    if i > 4 or prevEmpty:
      return none(uint32)
    inc i
    if part == "":
      prevEmpty = true
      continue
    let num = parseIpv4Number(part)
    if num notin 0u32..255u32:
      return none(uint32)
    numbers.add(num)
  if numbers[^1] >= 1u32 shl ((5 - numbers.len) * 8):
    return none(uint32)
  var ipv4 = uint32(numbers[^1])
  for i in 0 ..< numbers.high:
    let n = uint32(numbers[i])
    ipv4 += n * (1u32 shl ((3 - i) * 8))
  return some(ipv4)

const ForbiddenHostChars = {
  char(0x00), '\t', '\n', '\r', ' ', '#', '/', ':', '<', '>', '?', '@', '[',
  '\\', ']', '^', '|'
}
const ForbiddenDomainChars = ForbiddenHostChars + {'%'}
func opaqueParseHost(input: string): Host =
  var o = ""
  for c in input:
    if c in ForbiddenHostChars:
      return Host(t: htNone)
    o.percentEncode(c, ControlPercentEncodeSet)
  return Host(t: htOpaque, opaque: o)

func endsInNumber(input: string): bool =
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

type
  IDNATableStatus = enum
    itsValid, itsIgnored, itsMapped, itsDeviation, itsDisallowed

func getIdnaTableStatus(u: uint32): IDNATableStatus =
  if u <= high(uint16):
    let u = uint16(u)
    if u in IgnoredLow:
      return itsIgnored
    if u in DisallowedLow or DisallowedRangesLow.isInRange(u):
      return itsDisallowed
    if MappedMapLow.isInMap(u):
      return itsMapped
  else:
    if u in IgnoredHigh:
      return itsIgnored
    if u in DisallowedHigh or DisallowedRangesHigh.isInRange(u):
      return itsDisallowed
    if MappedMapHigh.isInMap(u):
      return itsMapped
  return itsValid

func getIdnaMapped(u: uint32): string =
  if u <= high(uint16):
    let u = uint16(u)
    let n = MappedMapLow.searchInMap(u)
    let idx = MappedMapLow[n].idx
    let e = MappedMapData.find('\0', idx)
    return MappedMapData[idx ..< e]
  let n = MappedMapHigh.searchInMap(u)
  let idx = MappedMapHigh[n].idx
  let e = MappedMapData.find('\0', idx)
  return MappedMapData[idx ..< e]

func processIdna(str: string; beStrict: bool): string =
  # CheckHyphens = false
  # CheckBidi = true
  # CheckJoiners = true
  # UseSTD3ASCIIRules = beStrict (but STD3 is not implemented)
  # Transitional_Processing = false
  # VerifyDnsLength = beStrict
  var mapped: seq[uint32] = @[]
  for u in str.points:
    let status = getIdnaTableStatus(u)
    case status
    of itsDisallowed: return "" #error
    of itsIgnored: discard
    of itsMapped: mapped &= getIdnaMapped(u).toPoints()
    of itsDeviation: mapped &= u
    of itsValid: mapped &= u
  if mapped.len == 0: return
  mapped = mapped.normalize()
  var cr: CharRange
  {.cast(noSideEffect).}:
    cr_init(addr cr, nil, passRealloc)
    let r = unicode_general_category(addr cr, "Mark")
    assert r == 0
  var labels = ""
  for label in mapped.toUTF8().split('.'):
    if label.startsWith("xn--"):
      try:
        let s = punycode.decode(label.substr("xn--".len))
        let x0 = s.toPoints()
        let x1 = x0.normalize()
        if x0 != x1:
          return "" #error
        # CheckHyphens is false
        if x0.len > 0:
          let cps = cast[ptr UncheckedArray[u32pair]](cr.points)
          let c = uint32(x0[0])
          let L = cr.len div 2 - 1
          if cps.toOpenArray(0, L).binarySearch(c, cmpRange) != -1:
            return "" #error
        for u in x0:
          if u == uint32('.'):
            return "" #error
          let status = getIdnaTableStatus(u)
          if status in {itsDisallowed, itsIgnored, itsMapped}:
            return "" #error
          #TODO check joiners
          #TODO check bidi
        if labels.len > 0:
          labels &= '.'
        labels &= s
      except PunyError:
        return "" #error
    else:
      if labels.len > 0:
        labels &= '.'
      labels &= label
  cr_free(addr cr)
  return labels

func unicodeToAscii(s: string; beStrict: bool): string =
  let processed = s.processIdna(beStrict)
  var labels = ""
  var all = 0
  for label in processed.split('.'):
    var s = ""
    if AllChars - Ascii in label:
      try:
        s = "xn--" & punycode.encode(label)
      except PunyError:
        return "" #error
    else:
      s = label
    if beStrict: # VerifyDnsLength
      let rl = s.pointLen()
      if rl notin 1..63:
        return ""
      all += rl
    if labels.len > 0:
      labels &= '.'
    labels &= s
  if beStrict: # VerifyDnsLength
    if all notin 1..253:
      return "" #error
  return labels

func domainToAscii(domain: string; bestrict = false): string =
  var needsprocessing = false
  for s in domain.split('.'):
    if s.startsWith("xn--") or AllChars - Ascii in s:
      needsprocessing = true
      break
  if bestrict or needsprocessing:
    # Note: we don't implement STD3 separately, it's always true
    return domain.unicodeToAscii(bestrict)
  return domain.toLowerAscii()

func parseHost(input: string; special: bool): Host =
  if input.len == 0:
    return Host(t: htNone)
  if input[0] == '[':
    if input[^1] != ']' or input.len < 3:
      return Host(t: htNone)
    let ipv6 = parseIpv6(input.toOpenArray(1, input.high - 1))
    if ipv6.isNone:
      return Host(t: htNone)
    return Host(
      t: htIpv6,
      ipv6: ipv6.get
    )
  if not special:
    return opaqueParseHost(input)
  let domain = percentDecode(input)
  let asciiDomain = domain.domainToAscii()
  if asciiDomain == "" or ForbiddenDomainChars in asciiDomain:
    return Host(t: htNone)
  if asciiDomain.endsInNumber():
    let ipv4 = parseIpv4(asciiDomain)
    if ipv4.isSome:
      return Host(t: htIpv4, ipv4: ipv4.get)
  return Host(t: htDomain, domain: asciiDomain)

proc shortenPath(url: URL) =
  assert not url.path.opaque
  if url.scheme == "file" and url.path.ss.len == 1 and
      url.path.ss[0].len == 2 and url.path.ss[0][0] in AsciiAlpha and
      url.path.ss[0][1] == ':':
    return
  if url.path.ss.len > 0:
    discard url.path.ss.pop()

proc append(path: var URLPath; s: string) =
  if path.opaque:
    path.s &= s
  else:
    path.ss.add(s)

func includesCredentials(url: URL): bool =
  return url.username != "" or url.password != ""

template is_windows_drive_letter(s: string): bool =
  s.len == 2 and s[0] in AsciiAlpha and (s[1] == ':' or s[1] == '|')

template canHaveUsernamePasswordPort(url: URL): bool =
  url.host.serialize() != "" and url.scheme != "file"

proc parseOpaquePath(input: openArray[char]; pointer: var int; url: URL):
    URLState =
  while pointer < input.len:
    let c = input[pointer]
    if c == '?':
      url.query = some("")
      inc pointer
      return usQuery
    elif c == '#':
      url.fragment = some("")
      inc pointer
      return usFragment
    else:
      url.path.s.percentEncode(c, ControlPercentEncodeSet)
    inc pointer
  return usDone

proc parseSpecialAuthorityIgnoreSlashes(input: openArray[char];
    pointer: var int): URLState =
  while pointer < input.len and input[pointer] in {'/', '\\'}:
    inc pointer
  return usAuthority

proc parseRelativeSlash(input: openArray[char]; pointer: var int;
    isSpecial: var bool; base, url: URL): URLState =
  if isSpecial and pointer < input.len and input[pointer] in {'/', '\\'}:
    inc pointer
    return input.parseSpecialAuthorityIgnoreSlashes(pointer)
  if pointer < input.len and input[pointer] == '/':
    inc pointer
    return usAuthority
  url.username = base.username
  url.password = base.password
  url.host = base.host
  url.port = base.port
  return usPath

proc parseRelative(input: openArray[char]; pointer: var int;
    isSpecial: var bool; base, url: URL): URLState =
  assert base.scheme != "file"
  url.scheme = base.scheme
  isSpecial = url.scheme in SpecialSchemes
  if pointer < input.len and input[pointer] == '/' or
      isSpecial and pointer < input.len and input[pointer] == '\\':
    inc pointer
    return input.parseRelativeSlash(pointer, isSpecial, base, url)
  url.username = base.username
  url.password = base.password
  url.host = base.host
  url.port = base.port
  url.path = base.path
  url.query = base.query
  if pointer < input.len and input[pointer] == '?':
    url.query = some("")
    inc pointer
    return usQuery
  if pointer < input.len and input[pointer] == '#':
    url.fragment = some("")
    inc pointer
    return usFragment
  url.query = none(string)
  url.shortenPath()
  return usPath

proc parseSpecialRelativeOrAuthority(input: openArray[char]; pointer: var int;
    isSpecial: var bool; base, url: URL): URLState =
  if pointer + 1 < input.len and input[pointer] == '/' and
      input[pointer + 1] == '/':
    pointer += 2
    return input.parseSpecialAuthorityIgnoreSlashes(pointer)
  return input.parseRelative(pointer, isSpecial, base, url)

proc parsePathOrAuthority(input: openArray[char]; pointer: var int): URLState =
  if pointer < input.len and input[pointer] == '/':
    inc pointer
    return usAuthority
  return usPath

proc parseScheme(input: openArray[char]; pointer: var int; isSpecial: var bool;
    firstc: char; base: Option[URL]; url: URL; override: bool): URLState =
  var buffer = $firstc
  var i = pointer
  while i < input.len:
    let c = input[i]
    if c in AsciiAlphaNumeric + {'+', '-', '.'}:
      buffer &= c.toLowerAscii()
    elif c == ':':
      if override:
        if isSpecial != (buffer in SpecialSchemes):
          return usNoScheme
        if (url.includesCredentials or url.port.isSome) and buffer == "file":
          return usNoScheme
        if url.host.t == htNone and url.scheme == "file":
          return usNoScheme
      url.scheme = buffer
      isSpecial = url.scheme in SpecialSchemes
      if override:
        if isSpecial and SpecialSchemes[url.scheme] == url.port:
          url.port = none(uint16)
        return usDone
      pointer = i + 1
      if url.scheme == "file":
        return usFile
      if isSpecial and base.isSome and base.get.scheme == url.scheme:
        return input.parseSpecialRelativeOrAuthority(pointer, isSpecial,
          base.get, url)
      if isSpecial:
        # special authority slashes state
        if pointer + 1 < input.len and input[pointer] == '/' and
            input[pointer + 1] == '/':
          pointer += 2
        return input.parseSpecialAuthorityIgnoreSlashes(pointer)
      if i + 1 < input.len and input[i + 1] == '/':
        inc pointer
        return input.parsePathOrAuthority(pointer)
      url.path = EmptyPath
      return input.parseOpaquePath(pointer, url)
    else:
      break
    inc i
  return usNoScheme

proc parseSchemeStart(input: openArray[char]; pointer: var int;
    isSpecial: var bool; base: Option[URL]; url: URL; override: bool):
    URLState =
  var state = usNoScheme
  if pointer < input.len and (let c = input[pointer]; c in AsciiAlpha):
    # continue to scheme state
    inc pointer
    state = input.parseScheme(pointer, isSpecial, c.toLowerAscii(), base, url,
      override)
  if state == usNoScheme:
    pointer = 0 # start over
  if override:
    return usDone
  if state == usNoScheme:
    if base.isNone:
      return usFail
    if base.get.path.opaque and (pointer >= input.len or input[pointer] != '#'):
      return usFail
    if base.get.path.opaque and pointer < input.len and input[pointer] == '#':
      url.scheme = base.get.scheme
      isSpecial = url.scheme in SpecialSchemes
      url.path = base.get.path
      url.query = base.get.query
      url.fragment = some("")
      inc pointer
      return usFragment
    if base.get.scheme != "file":
      return input.parseRelative(pointer, isSpecial, base.get, url)
    return usFile
  return state

proc parseAuthority(input: openArray[char]; pointer: var int; isSpecial: bool;
    url: URL): URLState =
  var atSignSeen = false
  var passwordSeen = false
  var buffer = ""
  var beforeBuffer = pointer
  while pointer < input.len:
    let c = input[pointer]
    if c in {'/', '?', '#'} or isSpecial and c == '\\':
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

proc parseFileHost(input: openArray[char]; pointer: var int; isSpecial: bool;
    url: URL; override: bool): URLState =
  let buffer = input.until({'/', '\\', '?', '#'}, pointer)
  pointer += buffer.len
  if not override and buffer.is_windows_drive_letter:
    return usPath
  if buffer == "":
    url.host = Host(t: htDomain, domain: "")
  else:
    let host = parseHost(buffer, isSpecial)
    if host.t == htNone:
      return usFail
    url.host = host
    if url.host.t == htDomain and url.host.domain == "localhost":
      url.host.domain = ""
  if override:
    return usFail
  return usPathStart

proc parseHostState(input: openArray[char]; pointer: var int; isSpecial: bool;
    url: URL; override: bool; state: URLState): URLState =
  if override and url.scheme == "file":
    return input.parseFileHost(pointer, isSpecial, url, override)
  var insideBrackets = false
  var buffer = ""
  while pointer < input.len:
    let c = input[pointer]
    if c == ':' and not insideBrackets:
      if override and state == usHostname:
        return usFail
      let host = parseHost(buffer, isSpecial)
      if host.t == htNone:
        return usFail
      url.host = host
      inc pointer
      return usPort
    elif c in {'/', '?', '#'} or isSpecial and c == '\\':
      break
    else:
      if c == '[':
        insideBrackets = true
      elif c == ']':
        insideBrackets = false
      buffer &= c
    inc pointer
  if isSpecial and buffer == "":
    return usFail
  if override and buffer == "" and (url.includesCredentials or url.port.isSome):
    return usFail
  let host = parseHost(buffer, isSpecial)
  if host.t == htNone:
    return usFail
  url.host = host
  if override:
    return usFail
  return usPathStart

proc parsePort(input: openArray[char]; pointer: var int; isSpecial: bool;
    url: URL; override: bool): URLState =
  var buffer = ""
  var i = pointer
  while i < input.len:
    let c = input[i]
    if c in AsciiDigit:
      buffer &= c
    elif c in {'/', '?', '#'} or isSpecial and c == '\\' or override:
      break
    else:
      return usFail
    inc i
  pointer = i
  if buffer != "":
    let i = parseInt32(buffer)
    if i.isNone or i.get notin 0..65535:
      return usFail
    let port = some(uint16(i.get))
    url.port = if isSpecial and SpecialSchemes[url.scheme] == port:
      none(uint16)
    else:
      port
  if override:
    return usFail
  return usPathStart

func startsWithWinDriveLetter(input: openArray[char]; i: int): bool =
  if i + 1 >= input.len:
    return false
  return input[i] in AsciiAlpha and input[i + 1] in {':', '|'}

proc parseFileSlash(input: openArray[char]; pointer: var int; isSpecial: bool;
    base: Option[URL]; url: URL; override: bool): URLState =
  if pointer < input.len and input[pointer] in {'/', '\\'}:
    inc pointer
    return input.parseFileHost(pointer, isSpecial, url, override)
  template is_normalized_windows_drive_letter(s: string): bool =
    s.len == 2 and s[0] in AsciiAlpha and s[1] == ':'
  if base.isSome and base.get.scheme == "file":
    url.host = base.get.host
    let bpath = base.get.path.ss
    if not input.startsWithWinDriveLetter(pointer) and bpath.len > 0 and
        bpath[0].is_normalized_windows_drive_letter():
      url.path.append(bpath[0])
  return usPath

proc parseFile(input: openArray[char]; pointer: var int; base: Option[URL];
    url: URL; override: bool): URLState =
  url.scheme = "file"
  url.host = EmptyHost
  if pointer < input.len and input[pointer] in {'/', '\\'}:
    inc pointer
    return input.parseFileSlash(pointer, isSpecial = true, base, url, override)
  if base.isSome and base.get.scheme == "file":
    url.host = base.get.host
    url.path = base.get.path
    url.query = base.get.query
    if pointer < input.len:
      let c = input[pointer]
      if c == '?':
        url.query = some("")
        inc pointer
        return usQuery
      elif c == '#':
        url.fragment = some("")
        inc pointer
        return usFragment
      else:
        url.query = none(string)
        if not input.startsWithWinDriveLetter(pointer):
          url.shortenPath()
        else:
          url.path.ss.setLen(0)
  return usPath

proc parsePathStart(input: openArray[char]; pointer: var int; isSpecial: bool;
    url: URL; override: bool): URLState =
  if isSpecial:
    if pointer < input.len and input[pointer] in {'/', '\\'}:
      inc pointer
    return usPath
  if pointer < input.len:
    let c = input[pointer]
    if not override:
      if c == '?':
        url.query = some("")
        inc pointer
        return usQuery
      if c == '#':
        url.fragment = some("")
        inc pointer
        return usFragment
    if c == '/':
      inc pointer
    return usPath
  if override and url.host.t == htNone:
    url.path.append("")
    inc pointer
  return usDone

proc parsePath(input: openArray[char]; pointer: var int; isSpecial: bool;
    url: URL; override: bool): URLState =
  var state = usPath
  var buffer = ""
  template is_single_dot_path_segment(s: string): bool =
    s == "." or s.equalsIgnoreCase("%2e")
  template is_double_dot_path_segment(s: string): bool =
    s == ".." or s.equalsIgnoreCase(".%2e") or s.equalsIgnoreCase("%2e.") or
      s.equalsIgnoreCase("%2e%2e")
  while pointer < input.len:
    let c = input[pointer]
    if c == '/' or isSpecial and c == '\\' or not override and c in {'?', '#'}:
      if c == '?':
        url.query = some("")
        state = usQuery
        inc pointer
        break
      elif c == '#':
        url.fragment = some("")
        state = usFragment
        inc pointer
        break
      let slashCond = c != '/' and (not isSpecial or c != '\\')
      if buffer.is_double_dot_path_segment:
        url.shortenPath()
        if slashCond:
          url.path.append("")
      elif buffer.is_single_dot_path_segment and slashCond:
        url.path.append("")
      elif not buffer.is_single_dot_path_segment:
        if url.scheme == "file" and url.path.ss.len == 0 and
            buffer.is_windows_drive_letter:
          buffer[1] = ':'
        url.path.append(buffer)
      buffer = ""
    else:
      buffer.percentEncode(c, PathPercentEncodeSet)
    inc pointer
  let slashCond = pointer >= input.len or input[pointer] != '/' and
    (not isSpecial or input[pointer] != '\\')
  if buffer.is_double_dot_path_segment:
    url.shortenPath()
    if slashCond:
      url.path.append("")
  elif buffer.is_single_dot_path_segment and slashCond:
    url.path.append("")
  elif not buffer.is_single_dot_path_segment:
    if url.scheme == "file" and url.path.ss.len == 0 and
        buffer.is_windows_drive_letter:
      buffer[1] = ':'
    url.path.append(buffer)
  return state

proc parseQuery(input: openArray[char]; pointer: var int; isSpecial: bool;
    url: URL; override: bool): URLState =
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
  let querypercentencodeset = if isSpecial:
    SpecialQueryPercentEncodeSet
  else:
    QueryPercentEncodeSet
  url.query.get.percentEncode(buffer, querypercentencodeset)
  if pointer < input.len:
    url.fragment = some("")
    inc pointer
    return usFragment
  return usDone

proc basicParseURL0(input: openArray[char]; base: Option[URL]; url: URL;
    stateOverride: Option[URLState]): Option[URL] =
  var pointer = 0
  var isSpecial = url.scheme in SpecialSchemes
  let input = input.deleteChars({'\n', '\t'})
  let override = stateOverride.isSome
  var state = stateOverride.get(usSchemeStart)
  if state == usSchemeStart:
    state = input.parseSchemeStart(pointer, isSpecial, base, url, override)
  if state == usAuthority:
    state = input.parseAuthority(pointer, isSpecial, url)
  if state in {usHost, usHostname}:
    state = input.parseHostState(pointer, isSpecial, url, override, state)
  if state == usPort:
    state = input.parsePort(pointer, isSpecial, url, override)
  if state == usFile:
    isSpecial = true
    state = input.parseFile(pointer, base, url, override)
  if state == usPathStart:
    state = input.parsePathStart(pointer, isSpecial, url, override)
  if state == usPath:
    state = input.parsePath(pointer, isSpecial, url, override)
  if state == usQuery:
    state = input.parseQuery(pointer, isSpecial, url, override)
  if state == usFragment:
    while pointer < input.len:
      url.fragment.get.percentEncode(input[pointer], FragmentPercentEncodeSet)
      inc pointer
  if state == usFail:
    return none(URL)
  return some(url)

#TODO encoding
proc basicParseURL(input: string; base = none(URL); url: URL = nil;
    stateOverride = none(URLState)): Option[URL] =
  if url != nil:
    return input.basicParseURL0(base, url, stateOverride)
  let url = URL()
  const NoStrip = AllChars - C0Controls - {' '}
  let starti0 = input.find(NoStrip)
  let starti = if starti0 == -1: 0 else: starti0
  let endi0 = input.rfind(NoStrip)
  let endi = if endi0 == -1: input.high else: endi0
  return input.toOpenArray(starti, endi).basicParseURL0(base, url,
    stateOverride)

func anchor*(url: URL): string =
  return url.fragment.get("")

proc parseURL*(input: string; base = none(URL); override = none(URLState)):
    Option[URL] =
  let url = basicParseURL(input, base, stateOverride = override)
  if url.isNone:
    return url
  if url.get.scheme == "blob":
    url.get.blob = some(BlobURLEntry())
  return url

proc parseJSURL*(s: string; base = none(URL)): JSResult[URL] =
  let url = parseURL(s, base)
  if url.isNone:
    return errTypeError(s & " is not a valid URL")
  return ok(url.get)

func serializeip(ipv4: uint32): string =
  var n = ipv4
  for i in 1..4:
    result = $(n mod 256) & result
    if i != 4:
      result = '.' & result
    n = n div 256
  assert n == 0

func findZeroSeq(ipv6: array[8, uint16]): int =
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

func serializeip(ipv6: array[8, uint16]): string =
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

func serialize(host: Host): string =
  case host.t
  of htNone: return ""
  of htDomain: return host.domain
  of htIpv4: return host.ipv4.serializeip()
  of htIpv6: return host.ipv6.serializeip()
  of htOpaque: return host.opaque

func serialize*(path: URLPath): string {.inline.} =
  if path.opaque:
    return path.s
  var buf = ""
  for s in path.ss:
    buf &= '/'
    buf &= s
  return buf

when defined(windows) or defined(OS2) or defined(DOS):
  func serialize_unicode_dos(path: URLPath): string =
    if path.opaque:
      return percentDecode(path.s)
    var i = 0
    if i < path.ss.len:
      if path.ss[i].is_windows_drive_letter:
        result &= path.ss[i]
        inc i
    while i < path.ss.len:
      let s = path.ss[i]
      result &= '\\'
      result &= percentDecode(s)
      inc i
  func serialize_unicode*(path: URLPath): string =
    return path.serialize_unicode_dos()
else:
  func serialize_unicode*(path: URLPath): string =
    if path.opaque:
      return percentDecode(path.s)
    for s in path.ss:
      result &= '/'
      result &= percentDecode(s)

func serialize*(url: URL; excludefragment = false; excludepassword = false):
    string =
  result = url.scheme & ':'
  if url.host.t != htNone:
    result &= "//"
    if url.includesCredentials:
      result &= url.username
      if not excludepassword and url.password != "":
        result &= ':' & url.password
      result &= '@'
    result &= url.host.serialize()
    if url.port.isSome:
      result &= ':' & $url.port.get
  elif not url.path.opaque and url.path.ss.len > 1 and url.path.ss[0] == "":
    result &= "/."
  result &= url.path.serialize()
  if url.query.isSome:
    result &= '?' & url.query.get
  if not excludefragment and url.fragment.isSome:
    result &= '#' & url.fragment.get

func serialize*(url: Option[URL]; excludefragment = false): string =
  if url.isNone:
    return ""
  return url.get.serialize()

func equals*(a, b: URL; excludefragment = false): bool =
  return a.serialize(excludefragment) == b.serialize(excludefragment)

func `$`*(url: URL): string {.jsfunc.} = url.serialize()

func `$`*(path: URLPath): string {.inline.} = path.serialize()

func href(url: URL): string {.jsfget.} =
  return $url

func toJSON(url: URL): string {.jsfget.} =
  return $url

# from a to b
proc cloneInto(a, b: URL) =
  b[] = a[]
  b.searchParamsInternal = nil

proc newURL*(url: URL): URL =
  result = URL()
  url.cloneInto(result)

proc setHref(ctx: JSContext; url: URL; s: string) {.jsfset: "href".} =
  let purl = basicParseURL(s)
  if purl.isSome:
    purl.get.cloneInto(url)
  else:
    JS_ThrowTypeError(ctx, "%s is not a valid URL", s)

func isIP*(url: URL): bool =
  return url.host.t in {htIpv4, htIpv6}

#https://url.spec.whatwg.org/#concept-urlencoded-serializer
proc parseFromURLEncoded(input: string): seq[(string, string)] =
  for s in input.split('&'):
    if s == "":
      continue
    var name = ""
    var value = ""
    for i in 0..<s.len:
      if s[i] == '=':
        name = s.substr(0, i - 1)
        value = s.substr(i + 1)
        break
    if name == "":
      name = s
    for i in 0..<name.len:
      if name[i] == '+':
        name[i] = ' '
    for i in 0..<value.len:
      if value[i] == '+':
        value[i] = ' '
    result.add((percentDecode(name), percentDecode(value)))

#https://url.spec.whatwg.org/#concept-urlencoded-serializer
proc serializeFormURLEncoded*(kvs: seq[(string, string)]; spaceAsPlus = true):
    string =
  for it in kvs:
    let (name, value) = it
    if result != "":
      result &= '&'
    result.percentEncode(name, ApplicationXWWWFormUrlEncodedSet, spaceAsPlus)
    result &= '='
    result.percentEncode(value, ApplicationXWWWFormUrlEncodedSet, spaceAsPlus)

proc newURLSearchParams(ctx: JSContext; init: varargs[JSValue]):
    Opt[URLSearchParams] {.jsctor.} =
  let params = URLSearchParams()
  if init.len > 0:
    let val = init[0]
    if ctx.fromJS(val, params.list).isSome:
      discard
    elif (var t: Table[string, string]; ctx.fromJS(val, t).isSome):
      for k, v in t:
        params.list.add((k, v))
    else:
      var res: string
      ?ctx.fromJS(val, res)
      if res.len > 0 and res[0] == '?':
        res.delete(0..0)
      params.list = parseFromURLEncoded(res)
  return ok(params)

proc searchParams(url: URL): URLSearchParams {.jsfget.} =
  if url.searchParamsInternal == nil:
    let params = URLSearchParams(list: parseFromURLEncoded(url.query.get("")))
    params.url = url
    url.searchParamsInternal = params
  return url.searchParamsInternal

proc `$`*(params: URLSearchParams): string {.jsfunc.} =
  return serializeFormURLEncoded(params.list)

proc update(params: URLSearchParams) =
  if params.url == nil:
    return
  let serializedQuery = $params
  if serializedQuery == "":
    params.url.query = none(string)
  else:
    params.url.query = some(serializedQuery)

proc append(params: URLSearchParams; name, value: string) {.jsfunc.} =
  params.list.add((name, value))
  params.update()

proc delete(params: URLSearchParams; name: string) {.jsfunc.} =
  for i in countdown(params.list.high, 0):
    if params.list[i][0] == name:
      params.list.delete(i)
  params.update()

proc get(params: URLSearchParams; name: string): Option[string] {.jsfunc.} =
  for it in params.list:
    if it.name == name:
      return some(it.value)
  return none(string)

proc getAll(params: URLSearchParams; name: string): seq[string] {.jsfunc.} =
  result = @[]
  for it in params.list:
    if it.name == name:
      result.add(it.value)

proc has(params: URLSearchParams; name: string; value = none(string)): bool
    {.jsfunc.} =
  for it in params.list:
    if it.name == name:
      if value.isNone or value.get == it.value:
        return true
  return false

proc set(params: URLSearchParams; name, value: string) {.jsfunc.} =
  for param in params.list.mitems:
    if param.name == name:
      param.value = value
      break

proc parseAPIURL(s: string; base: Option[string]): JSResult[URL] =
  let baseURL = if base.isSome:
    let x = parseURL(base.get)
    if x.isNone:
      return errTypeError(base.get & " is not a valid URL")
    x
  else:
    none(URL)
  return parseJSURL(s, baseURL)

proc newURL*(s: string; base: Option[string] = none(string)):
    JSResult[URL] {.jsctor.} =
  return parseAPIURL(s, base)

proc origin*(url: URL): Origin =
  case url.scheme
  of "blob":
    if url.blob.isSome:
      #TODO
      discard
    let pathURL = parseURL($url.path)
    if pathURL.isNone:
      return Origin(t: otOpaque, s: $url)
    return pathURL.get.origin
  of "ftp", "http", "https", "ws", "wss":
    return Origin(
      t: otTuple,
      tup: (url.scheme, url.host, url.port, none(string))
    )
  of "file":
    return Origin(t: otOpaque, s: $url)
  else:
    return Origin(t: otOpaque, s: $url)

proc `==`(a, b: Host): bool =
  if a.t != b.t:
    return false
  case a.t
  of htNone: return true
  of htDomain: return a.domain == b.domain
  of htOpaque: return a.opaque == b.opaque
  of htIpv4: return a.ipv4 == b.ipv4
  of htIpv6: return a.ipv6 == b.ipv6

proc `==`*(a, b: Origin): bool {.error.} =
  discard

proc isSameOrigin*(a, b: Origin): bool =
  if a.t != b.t:
    return false
  case a.t
  of otOpaque:
    return a.s == b.s
  of otTuple:
    return a.tup == b.tup

proc `$`*(origin: Origin): string =
  if origin.t == otOpaque:
    return "null"
  var s = origin.tup.scheme
  s &= "://"
  s &= origin.tup.host.serialize()
  if origin.tup.port.isSome:
    s &= ':'
    s &= $origin.tup.port.get
  return s

proc jsOrigin*(url: URL): string {.jsfget: "origin".} =
  return $url.origin

proc protocol*(url: URL): string {.jsfget.} =
  return url.scheme & ':'

proc setProtocol*(url: URL; s: string) {.jsfset: "protocol".} =
  discard basicParseURL(s & ':', url = url,
    stateOverride = some(usSchemeStart))

proc setUsername*(url: URL; username: string) {.jsfset: "username".} =
  if not url.canHaveUsernamePasswordPort:
    return
  url.username = username.percentEncode(UserInfoPercentEncodeSet)

proc setPassword*(url: URL; password: string) {.jsfset: "password".} =
  if not url.canHaveUsernamePasswordPort:
    return
  url.password = password.percentEncode(UserInfoPercentEncodeSet)

proc host*(url: URL): string {.jsfget.} =
  if url.host.t == htNone:
    return ""
  if url.port.isNone:
    return url.host.serialize()
  return url.host.serialize() & ':' & $url.port.get

proc setHost*(url: URL; s: string) {.jsfset: "host".} =
  if url.path.opaque:
    return
  discard basicParseURL(s, url = url, stateOverride = some(usHost))

proc hostname*(url: URL): string {.jsfget.} =
  return url.host.serialize()

proc setHostname*(url: URL; s: string) {.jsfset: "hostname".} =
  if url.path.opaque:
    return
  discard basicParseURL(s, url = url, stateOverride = some(usHostname))

proc port*(url: URL): string {.jsfget.} =
  if url.port.isSome:
    return $url.port.get

proc setPort*(url: URL; s: string) {.jsfset: "port".} =
  if not url.canHaveUsernamePasswordPort:
    return
  if s == "":
    url.port = none(uint16)
  else:
    discard basicParseURL(s, url = url, stateOverride = some(usPort))

proc pathname*(url: URL): string {.jsfget.} =
  return url.path.serialize()

proc setPathname*(url: URL; s: string) {.jsfset: "pathname".} =
  if url.path.opaque:
    return
  url.path.ss.setLen(0)
  discard basicParseURL(s, url = url, stateOverride = some(usPathStart))

proc search*(url: URL): string {.jsfget.} =
  if url.query.get("") == "":
    return ""
  return "?" & url.query.get

proc setSearch*(url: URL; s: string) {.jsfset: "search".} =
  if s == "":
    url.query = none(string)
    if url.searchParamsInternal != nil:
      url.searchParamsInternal.list.setLen(0)
    return
  let s = if s[0] == '?': s.substr(1) else: s
  url.query = some("")
  discard basicParseURL(s, url = url, stateOverride = some(usQuery))
  if url.searchParamsInternal != nil:
    url.searchParamsInternal.list = parseFromURLEncoded(s)

proc hash*(url: URL): string {.jsfget.} =
  if url.fragment.get("") == "":
    return ""
  return '#' & url.fragment.get

proc setHash*(url: URL; s: string) {.jsfset: "hash".} =
  if s == "":
    url.fragment = none(string)
    return
  let s = if s[0] == '#': s.substr(1) else: s
  url.fragment = some("")
  discard basicParseURL(s, url = url, stateOverride = some(usFragment))

proc jsParse(url: string; base = none(string)): URL {.jsstfunc: "URL.parse".} =
  return parseAPIURL(url, base).get(nil)

proc canParse(url: string; base = none(string)): bool {.jsstfunc: "URL".} =
  return parseAPIURL(url, base).isSome

proc addURLModule*(ctx: JSContext) =
  ctx.registerType(URL)
  ctx.registerType(URLSearchParams)
