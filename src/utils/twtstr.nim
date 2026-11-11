{.push raises: [].}

when NimMajor >= 2:
  import std/assertions
import std/algorithm

import utils/opt

const AllChars* = {char.low..char.high}
const C0Controls* = {'\0'..'\x1F'}
const Controls* = C0Controls + {'\x7F'}
const Ascii* = {'\0'..'\x7F'}
const AsciiUpperAlpha* = {'A'..'Z'}
const AsciiLowerAlpha* = {'a'..'z'}
const AsciiAlpha* = AsciiUpperAlpha + AsciiLowerAlpha
const NonAscii* = {'\x80'..'\xFF'}
const AsciiDigit* = {'0'..'9'}
const AsciiAlphaNumeric* = AsciiAlpha + AsciiDigit
const AsciiHexDigit* = AsciiDigit + {'a'..'f', 'A'..'F'}
const AsciiWhitespace* = {' ', '\n', '\r', '\t', '\f'}
const HTTPWhitespace* = {' ', '\n', '\r', '\t'}
const NonDigit* = AllChars - AsciiDigit

type BoxDrawingChar* = enum
  bdcHorizontalBarTop = "\u2500"
  bdcHorizontalBarBottom = "\u2500"
  bdcVerticalBarLeft = "\u2502"
  bdcVerticalBarRight = "\u2502"
  bdcCornerTopLeft = "\u250C"
  bdcCornerTopRight = "\u2510"
  bdcCornerBottomLeft = "\u2514"
  bdcCornerBottomRight = "\u2518"
  bdcSideBarLeft = "\u251C"
  bdcSideBarRight = "\u2524"
  bdcSideBarTop = "\u252C"
  bdcSideBarBottom = "\u2534"
  bdcSideBarCross = "\u253C"

const HorizontalBar* = {bdcHorizontalBarTop, bdcHorizontalBarBottom}
const VerticalBar* = {bdcVerticalBarLeft, bdcVerticalBarRight}

proc nextUTF8*(s: openArray[char]; i: var int): uint32 =
  var j = i
  var u = uint32(s[j])
  {.push overflowChecks: off, boundChecks: off.}
  inc j # can't overflow if s[j] didn't panic
  if u <= 0x7F:
    i = j
    return u
  block good:
    var min = 0x80u32
    var n = 1
    if u shr 5 == 0b110:
      u = u and 0x1F
    elif u shr 4 == 0b1110:
      min = 0x800
      n = 2
      u = u and 0xF
    elif likely(u shr 3 == 0b11110):
      min = 0x10000
      n = 3
      u = u and 7
    else:
      break good
    while true:
      if unlikely(j >= s.len):
        break good
      let u2 = uint32(s[j])
      if unlikely((u2 shr 6) != 2):
        break good
      u = (u shl 6) or u2 and 0x3F
      inc j
      dec n
      if n == 0:
        break
    if u - min <= 0x10FFFF - min:
      i = j
      return u
  {.pop.}
  i = j
  0xFFFD

proc prevUTF8*(s: openArray[char]; i: var int): uint32 =
  var j = i - 1
  while uint32(s[j]) shr 6 == 2:
    dec j
  i = j
  return s.nextUTF8(j)

proc pointLenAt*(s: openArray[char]; i: int): int =
  var j = i
  discard s.nextUTF8(j)
  return j - i

iterator points*(s: openArray[char]): uint32 {.inline.} =
  var i = 0
  while i < s.len:
    let u = s.nextUTF8(i)
    yield u

proc toPoints*(s: openArray[char]): seq[uint32] =
  var res: seq[uint32] = @[]
  for u in s.points:
    res.add(u)
  move(res)

proc pointLen*(s: openArray[char]): int =
  var n = 0
  for u in s.points:
    inc n
  return n

proc isInRange*[U](a: openArray[(U, U)]; u: U): bool =
  let res = binarySearch(a, u, proc(x: (U, U); y: U): int =
    if x[0] > y:
      1
    elif x[1] < y:
      -1
    else:
      0
  )
  return res != -1

proc isControlChar*(u: uint32): bool =
  return u <= 0x1F or u >= 0x7F and u <= 0x9F

proc toLowerAscii*(c: char): char {.inline.} =
  if c in AsciiUpperAlpha:
    char(uint8(c) xor 0x20'u8)
  else:
    c

proc toUpperAscii*(c: char): char {.inline.} =
  if c in AsciiLowerAlpha:
    char(uint8(c) xor 0x20'u8)
  else:
    c

proc hexValue*(c: char): int =
  if c in AsciiDigit:
    return int(uint8(c) - uint8('0'))
  if c in 'a'..'f':
    return int(uint8(c) - uint8('a') + 0xA)
  if c in 'A'..'F':
    return int(uint8(c) - uint8('A') + 0xA)
  return -1

proc decValue*(c: char): int =
  if c in AsciiDigit:
    return int(uint8(c) - uint8('0'))
  return -1

proc cmpIgnoreCase2*(a, b: openArray[char]): int =
  let alen = a.len
  let blen = b.len
  let L = min(alen, blen)
  for i in 0 ..< L:
    let n = cmp(a[i].toLowerAscii(), b[i].toLowerAscii())
    if n != 0:
      return n
  cmp(alen, blen)

proc equalsIgnoreCase*(s1, s2: openArray[char]): bool {.inline.} =
  return s1.cmpIgnoreCase2(s2) == 0

proc startsWithIgnoreCase*(s1, s2: openArray[char]): bool =
  if s1.len < s2.len:
    return false
  for i in 0 ..< s2.len:
    if s1[i].toLowerAscii() != s2[i].toLowerAscii():
      return false
  return true

proc startsWith*(s1, s2: openArray[char]): bool =
  let len2 = s2.len
  if s1.len < len2:
    return false
  when nimvm:
    for i in 0 ..< len2:
      if s1[i] != s2[i]:
        return false
    return true
  else:
    if len2 <= 0:
      return true
    return equalMem(unsafeAddr s1[0], unsafeAddr s2[0], len2)

proc startsWith*(s1, s2: openArray[char]; start: int): bool =
  if start >= s1.len:
    return false
  return s1.toOpenArray(start, s1.high).startsWith(s2)

proc endsWithIgnoreCase*(s1, s2: openArray[char]): bool =
  let len2 = s2.len
  if s1.len < len2:
    return false
  let h1 = s1.high
  let h2 = s2.high
  for i in 0 ..< len2:
    if s1[h1 - i].toLowerAscii() != s2[h2 - i].toLowerAscii():
      return false
  return true

proc endsWith*(s1, s2: openArray[char]): bool =
  let len1 = s1.len
  let len2 = s2.len
  if len1 < len2:
    return false
  when nimvm:
    let h1 = s1.high
    let h2 = s2.high
    for i in 0 ..< len2:
      if s1[h1 - i] != s2[h2 - i]:
        return false
    return true
  else:
    if len2 <= 0:
      return true
    return equalMem(unsafeAddr s1[len1 - len2], unsafeAddr s2[0], len2)

proc memset(s: pointer; c: cint; size: csize_t): pointer {.
  importc, header: "<string.h>".}

proc chaMemset*(s: var openArray[char]; c: char) =
  when nimvm:
    for ic in s.mitems:
      ic = c
  else:
    let slen = s.len
    if slen > 0:
      discard memset(addr s[0], cint(c), csize_t(slen))

proc memchr(s: pointer; c: cint; n: csize_t): pointer {.
  importc, header: "<string.h>".}

proc find*(s: openArray[char]; c: char): int =
  let slen = s.len
  when nimvm:
    for i in 0 ..< slen:
      if s[i] == c:
        return i
  else:
    if slen > 0:
      let sp = unsafeAddr s[0]
      let p = memchr(sp, cint(c), csize_t(slen))
      if p != nil:
        return cast[int](cast[uint](p) - cast[uint](sp))
  return -1

proc find*(s: openArray[char]; c: char; start: int; last = -1): int =
  let last = if last == -1: s.high else: last
  let n = s.toOpenArray(start, last).find(c)
  if n < 0:
    return n
  return start + n

proc findOrLen*(s: openArray[char]; c: char): int =
  let n = s.find(c)
  if n < 0:
    return s.len
  return n

proc findOrLen*(s: openArray[char]; c: char; start: int): int =
  let n = s.find(c, start)
  if n < 0:
    return s.len
  return n

proc find*(s: openArray[char]; cs: set[char]; start = 0; last = -1): int =
  let slen = if last == -1: s.len else: last + 1
  for i in start ..< slen:
    if s[i] in cs:
      return i
  return -1

proc findOrLen*(s: openArray[char]; cc: set[char]; start: int): int =
  let n = s.find(cc, start)
  if n < 0:
    return s.len
  return n

proc memmem(haystack: pointer; haystacklen: csize_t; needle: pointer;
  needlelen: csize_t): pointer {.importc, header: "<string.h>".}

proc find*(haystack, needle: openArray[char]): int =
  let haystacklen = haystack.len
  let needlelen = needle.len
  if haystacklen < needlelen:
    return -1
  if needlelen <= 0:
    return 0
  when nimvm:
    let L = haystacklen - needlelen + 1
    var i = 0
    let haystackHigh = haystack.high
    while i < L:
      if haystack.toOpenArray(i, haystackHigh).startsWith(needle):
        return i
      inc i
  else:
    let sp = unsafeAddr haystack[0]
    let p = memmem(sp, csize_t(haystacklen), unsafeAddr needle[0],
      csize_t(needlelen))
    if p != nil:
      return cast[int](cast[uint](p) - cast[uint](sp))
  return -1

proc find*(haystack: openArray[char]; needle: string): int =
  haystack.find(needle.toOpenArray(0, needle.high))

proc find*(haystack, needle: openArray[char]; start: int; last = -1):
    int =
  let last = if last == -1: haystack.high else: last
  if start > last:
    return -1
  let n = haystack.toOpenArray(start, last).find(needle)
  if n < 0:
    return n
  return start + n

proc findOrLen*(haystack: openArray[char]; needle: string): int =
  let n = haystack.find(needle)
  if n < 0:
    return haystack.len
  return n

const HasMemrchr = defined(linux) or defined(freebsd) or defined(openbsd) or
  defined(netbsd) or defined(haiku)

when HasMemrchr:
  proc memrchr(s: pointer; c: cint; n: csize_t): pointer {.
    importc, header: "<string.h>".}

proc rfind*(s: openArray[char]; c: char): int =
  template impl =
    for i in countdown(s.high, 0):
      if s[i] == c:
        return i
  when nimvm:
    impl()
  else:
    when HasMemrchr:
      let slen = s.len
      if slen > 0:
        let sp = unsafeAddr s[0]
        let p = memrchr(sp, cint(c), csize_t(slen))
        if p != nil:
          return cast[int](cast[uint](p) - cast[uint](sp))
    else:
      impl()
  return -1

proc rfind*(s: openArray[char]; c: char; start: int; last = -1): int =
  let last = if last == -1: s.high else: last
  let n = s.toOpenArray(start, last).rfind(c)
  if n < 0:
    return n
  return start + n

proc rfind*(s: openArray[char]; cs: set[char]; start = 0; last = -1): int =
  let H = if last < 0: s.high else: last
  for i in countdown(H, start):
    if s[i] in cs:
      return i
  return -1

proc contains*(s1, s2: openArray[char]): bool =
  s1.find(s2) != -1

proc contains*(s: openArray[char]; cs: set[char]): bool =
  s.find(cs) != -1

proc onlyWhitespace*(s: openArray[char]): bool =
  AllChars - AsciiWhitespace notin s

proc count*(s: openArray[char]; c: char): int =
  var n = 0
  for ic in s:
    if ic == c:
      inc n
  n

proc count*(s: openArray[char]; cs: set[char]): int =
  var n = 0
  for c in s:
    if c in cs:
      inc n
  n

proc skipBlanks*(buf: openArray[char]; at: int): int =
  result = at
  while result < buf.len and buf[result] in AsciiWhitespace:
    inc result

when NimMajor < 2:
  proc substr*(s: openArray[char]): string =
    var res = newStringOfCap(s.len)
    for c in s:
      res &= c
    move(res)

proc parentDir*(s: string): string =
  let i = s.rfind('/')
  if i >= 0:
    return s.substr(0, i - 1)
  return s

# https://html.spec.whatwg.org/multipage/common-microsyntaxes.html#numbers
proc parseUIntImpl[T: SomeUnsignedInt](s: openArray[char]; allowSign: bool;
    radix: T): Opt[T] =
  var integer: T = 0
  let radix = uint(radix)
  var i = 0u
  let L = uint(s.len)
  if allowSign and i < L and s[i] == '+':
    inc i
  var fail = i == L # fail on empty input
  for i in i ..< L:
    let u = uint64(hexValue(s[i]))
    let n = uint64(integer) * radix + u
    integer = T(n)
    fail = fail or u >= radix or n != uint64(integer) # overflow check
  if fail:
    return err() # invalid or overflow
  ok(integer)

proc parseUInt8*(s: openArray[char]; allowSign = false): Opt[uint8] =
  return parseUIntImpl[uint8](s, allowSign, 10)

proc parseUInt8NoLeadingZero*(s: openArray[char]): Opt[uint8] =
  if s.len > 1 and s[0] == '0':
    return err()
  return parseUInt8(s)

proc parseUInt16*(s: openArray[char]; allowSign = false): Opt[uint16] =
  return parseUIntImpl[uint16](s, allowSign, 10)

proc parseUInt32Base*(s: openArray[char]; allowSign = false; radix: uint32):
    Opt[uint32] =
  return parseUIntImpl[uint32](s, allowSign, radix)

proc parseUInt32*(s: openArray[char]; allowSign = false): Opt[uint32] =
  return parseUInt32Base(s, allowSign, 10)

proc parseUInt64*(s: openArray[char]; allowSign = false): Opt[uint64] =
  return parseUIntImpl[uint64](s, allowSign, 10)

proc parseHexInt64*(s: openArray[char]; allowSign = false): Opt[uint64] =
  return parseUIntImpl[uint64](s, allowSign, 16)

proc parseIntImpl[T: SomeSignedInt; U: SomeUnsignedInt](s: openArray[char];
    radix: U): Opt[T] =
  var sign: T = 1
  var i = 0
  if s.len > 0 and s[0] == '-':
    sign = -1
    inc i
  let res = parseUIntImpl[U](s.toOpenArray(i, s.high), allowSign = true, radix)
  let u = res.get(U.high)
  if sign == -1 and u == U(T.high) + 1:
    return ok(T.low) # negative has one more valid int
  if u <= U(T.high):
    return ok(T(u) * sign)
  err()

proc parseInt32*(s: openArray[char]): Opt[int32] =
  return parseIntImpl[int32, uint32](s, 10)

proc parseInt64*(s: openArray[char]): Opt[int64] =
  return parseIntImpl[int64, uint64](s, 10)

proc parseIntP*(s: openArray[char]): Opt[int] =
  return parseIntImpl[int, uint](s, 10)

const ControlPercentEncodeSet* = Controls + NonAscii
const FragmentPercentEncodeSet* = ControlPercentEncodeSet +
  {' ', '"', '<', '>', '`'}
const QueryPercentEncodeSet* = FragmentPercentEncodeSet - {'`'} + {'#'}
const SpecialQueryPercentEncodeSet* = QueryPercentEncodeSet + {'\''}
const PathPercentEncodeSet* = QueryPercentEncodeSet + {'?', '`', '{', '}', '^'}
const UserInfoPercentEncodeSet* = PathPercentEncodeSet +
  {'/', ':', ';', '=', '@', '['..']', '|'}
const ComponentPercentEncodeSet* = UserInfoPercentEncodeSet +
  {'$'..'&', '+', ','}
const ApplicationXWWWFormUrlEncodedSet* = ComponentPercentEncodeSet +
  {'!', '\''..')', '~'}

type EscapeMode* = enum
  emAll # attribute chars plus single quote (non-standard but safest)
  emAttribute # text chars plus double quote ("attribute mode" in spec)
  emText # &, nbsp, <, > (default mode in spec)

# https://www.w3.org/TR/xml/#NT-Name
const NameStartCharRanges = [
  (0xC0u16, 0xD6u16),
  (0xD8u16, 0xF6u16),
  (0xF8u16, 0x2FFu16),
  (0x370u16, 0x37Du16),
  (0x37Fu16, 0x1FFFu16),
  (0x200Cu16, 0x200Du16),
  (0x2070u16, 0x218Fu16),
  (0x2C00u16, 0x2FEFu16),
  (0x3001u16, 0xD7FFu16),
  (0xF900u16, 0xFDCFu16),
  (0xFDF0u16, 0xFFFDu16)
]
const NameStartCharAscii = {':', '_'} + AsciiAlpha
const NameCharAscii = NameStartCharAscii + {'-', '.'} + AsciiDigit

proc isNameStartCharHigh(u: uint32): bool =
  return u <= uint16.high and NameStartCharRanges.isInRange(uint16(u)) or
    u in 0x10000u32..0xEFFFFu32

proc matchNameProduction*(s: openArray[char]): bool =
  if s.len <= 0:
    return false
  # NameStartChar
  var i = 0
  let u = s.nextUTF8(i)
  if u <= 0x7F:
    if char(u) notin NameStartCharAscii:
      return false
  elif not u.isNameStartCharHigh():
    return false
  # NameChar
  while i < s.len:
    let u = s.nextUTF8(i)
    if u <= 0x7F:
      if char(u) notin NameCharAscii:
        return false
    elif not u.isNameStartCharHigh() and u != 0xB7 and
        u notin 0x300u32..0x36Fu32 and u notin 0x203Fu32..0x2040u32:
      return false
  return true

proc matchQNameProduction*(s: openArray[char]): bool =
  if s.len <= 0:
    return false
  if s[0] == ':':
    return false
  if s[^1] == ':':
    return false
  var colon = false
  for i in 1 ..< s.len - 1:
    if s[i] == ':':
      if colon:
        return false
      colon = true
  return s.matchNameProduction()

type IdentMapItem* = tuple[s: string; n: int]

proc cmpItem(x: IdentMapItem; y: openArray[char]): int =
  let slen = x.s.len
  let n = cmp(slen, y.len)
  if n != 0:
    return n
  when nimvm:
    for i in 0 ..< slen:
      let n = cmp(x.s[i], y[i])
      if n != 0:
        return n
  else:
    if slen > 0:
      return cmpMem(unsafeAddr x.s[0], unsafeAddr y[0], slen)
  return 0

proc getIdentMap*[T: enum](lo, hi: T): seq[IdentMapItem] =
  result = @[]
  for e in lo .. hi:
    result.add(($e, int(e)))
  result.sort(proc(x, y: IdentMapItem): int = cmpItem(x, y.s))

proc getIdentMap*[T: enum](e: typedesc[T]): seq[IdentMapItem] =
  getIdentMap(T.low, T.high)

proc cmpItemNoCase(x: IdentMapItem; y: openArray[char]): int =
  let slen = x.s.len
  let n = cmp(slen, y.len)
  if n != 0:
    return n
  for i in 0 ..< slen:
    let n = cmp(x.s[i].toLowerAscii(), y[i].toLowerAscii())
    if n != 0:
      return n
  return 0

proc strictParseEnum0(map: openArray[IdentMapItem]; s: openArray[char]): int =
  let i = map.binarySearch(s, cmpItem)
  if i != -1:
    return map[i].n
  return -1

proc strictParseEnum*[T: enum](s: openArray[char]): Opt[T] =
  const IdentMap = getIdentMap(T)
  let n = IdentMap.strictParseEnum0(s)
  if n != -1:
    {.push rangeChecks: off.}
    return ok(T(n))
    {.pop.}
  err()

# Warning: the comparator here is *not* the standard cmp, but rather a
# length-based one.
proc parseEnumNoCase0*(map: openArray[IdentMapItem]; s: openArray[char]): int =
  let i = map.binarySearch(s, cmpItemNoCase)
  if i != -1:
    return map[i].n
  return -1

proc parseEnumNoCase*[T: enum](s: openArray[char]): Opt[T] =
  const IdentMap = getIdentMap(T)
  let n = IdentMap.parseEnumNoCase0(s)
  if n != -1:
    {.push rangeChecks: off.}
    return ok(T(n))
    {.pop.}
  return err()

template uncheckedInc(i: untyped) =
  {.push overflowChecks: off.}
  inc i
  {.pop.}

iterator myitems*[IX, T](a: array[IX, T]): lent T {.inline.} =
  when a.len > 0:
    var i = IX.low
    while true:
      yield a[i]
      if i >= IX.high:
        break
      uncheckedInc i

iterator mypairs*[T](a: openArray[T]): tuple[key: int; val: lent T] {.inline.} =
  var i = 0
  let L = a.len
  while i < L:
    yield (i, a[i])
    uncheckedInc i

iterator ritems*[T](a: openArray[T]): lent T {.inline.} =
  var i = a.len
  while i > 0:
    {.push overflowChecks: off.}
    dec i
    {.pop.}
    yield a[i]

iterator mritems*[T](a: var openArray[T]): var T {.inline.} =
  for i in countdown(a.high, 0):
    yield a[i]

proc chaArrayCopy*[T](dest: var openArray[T]; src: openArray[T]) =
  assert dest.len == src.len
  if dest.len > 0:
    copyMem(addr dest[0], unsafeAddr src[0], dest.len * sizeof(T))

proc add*(s: var string; a: openArray[char]) =
  let olen = s.len
  let nlen = olen + a.len
  s.setLen(nlen)
  chaArrayCopy(s.toOpenArray(olen, nlen - 1), a)

when not defined(nimHasXorSet):
  proc toggle*[T](x: var set[T]; y: set[T]) =
    x = x + y - (x * y)

proc toggleIf*[T](x: var set[T]; y: T; b: bool) =
  if b:
    x.incl(y)
  else:
    x.excl(y)

template unionHooks*(typ: untyped) =
  # workaround for https://github.com/nim-lang/Nim/issues/25236
  {.push warning[Deprecated]:off.}
  proc `=destroy`*(a: var typ) =
    discard

  proc `=copy`*(a: var typ; b: typ) =
    copyMem(addr a, unsafeAddr b, sizeof(typ))
  {.pop.}

{.pop.} # raises: []
