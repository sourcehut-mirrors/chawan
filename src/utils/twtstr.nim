{.push raises: [].}

import std/algorithm
import std/math
import std/posix
import std/strutils

import types/opt

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

proc addPoints*(res: var seq[uint32]; s: openArray[char]) =
  for u in s.points:
    res.add(u)

proc toPoints*(s: openArray[char]): seq[uint32] =
  result = @[]
  result.addPoints(s)

proc addUTF8*(res: var string; u: uint32) =
  if u < 0x80:
    res &= char(u)
  elif u < 0x800:
    res &= char(u shr 6 or 0xC0)
    res &= char(u and 0x3F or 0x80)
  elif u < 0x10000:
    res &= char(u shr 12 or 0xE0)
    res &= char(u shr 6 and 0x3F or 0x80)
    res &= char(u and 0x3F or 0x80)
  else:
    res &= char(u shr 18 or 0xF0)
    res &= char(u shr 12 and 0x3F or 0x80)
    res &= char(u shr 6 and 0x3F or 0x80)
    res &= char(u and 0x3F or 0x80)

proc addUTF8*(res: var string; us: openArray[uint32]) =
  for u in us:
    res.addUTF8(u)

proc toUTF8*(u: uint32): string =
  result = ""
  result.addUTF8(u)

proc toUTF8*(us: openArray[uint32]): string =
  result = newStringOfCap(us.len)
  result.addUTF8(us)

proc pointLen*(s: openArray[char]): int =
  var n = 0
  for u in s.points:
    inc n
  return n

proc searchInMap*[U, T](a: openArray[(U, T)]; u: U): int =
  binarySearch(a, u, proc(x: (U, T); y: U): int = cmp(x[0], y))

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

proc onlyWhitespace*(s: string): bool =
  return AllChars - AsciiWhitespace notin s

proc isControlChar*(u: uint32): bool =
  return u <= 0x1F or u >= 0x7F and u <= 0x9F

proc kebabToCamelCase*(s: string): string =
  result = ""
  var flip = false
  for c in s:
    if c == '-':
      flip = true
    else:
      if flip:
        result &= c.toUpperAscii()
      else:
        result &= c
      flip = false

proc camelToKebabCase*(s: openArray[char]; dashPrefix = false): string =
  result = newStringOfCap(s.len)
  if dashPrefix:
    result &= '-'
  for c in s:
    if c in AsciiUpperAlpha:
      result &= '-'
      result &= c.toLowerAscii()
    else:
      result &= c

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

const HexCharsUpper = "0123456789ABCDEF"
const HexCharsLower = "0123456789abcdef"
proc pushHex*(buf: var string; u: uint8) =
  buf &= HexCharsUpper[u shr 4]
  buf &= HexCharsUpper[u and 0xF]

proc pushHex*(buf: var string; c: char) =
  buf.pushHex(uint8(c))

proc toHexLower*(u: uint16): string =
  var x = u
  let len = if (u and 0xF000) != 0:
    4
  elif (u and 0x0F00) != 0:
    3
  elif (u and 0xF0) != 0:
    2
  else:
    1
  var s = newString(len)
  for i in countdown(len - 1, 0):
    s[i] = HexCharsLower[x and 0xF]
    x = x shr 4
  move(s)

proc controlToVisual*(u: uint32): string =
  if u <= 0x1F:
    return "^" & char(u or 0x40)
  if u == 0x7F:
    return "^?"
  var res = "["
  res.pushHex(uint8(u))
  res &= ']'
  move(res)

proc add*(s: var string; u: uint8) =
  s.addInt(uint64(u))

proc equalsIgnoreCase*(s1, s2: string): bool {.inline.} =
  return s1.cmpIgnoreCase(s2) == 0

proc startsWithIgnoreCase*(s1, s2: openArray[char]): bool =
  if s1.len < s2.len:
    return false
  for i in 0 ..< s2.len:
    if s1[i].toLowerAscii() != s2[i].toLowerAscii():
      return false
  return true

proc startsWith2*(s1, s2: openArray[char]): bool =
  if s1.len < s2.len:
    return false
  for i in 0 ..< s2.len:
    if s1[i] != s2[i]:
      return false
  return true

proc endsWithIgnoreCase*(s1, s2: openArray[char]): bool =
  if s1.len < s2.len:
    return false
  let h1 = s1.high
  let h2 = s2.high
  for i in 0 ..< s2.len:
    if s1[h1 - i].toLowerAscii() != s2[h2 - i].toLowerAscii():
      return false
  return true

proc containsIgnoreCase*(ss: openArray[string]; s: string): bool =
  for it in ss:
    if it.equalsIgnoreCase(s):
      return true
  false

proc skipBlanks*(buf: openArray[char]; at: int): int =
  result = at
  while result < buf.len and buf[result] in AsciiWhitespace:
    inc result

proc skipBlanksTillLF*(buf: openArray[char]; at: int): int =
  result = at
  while result < buf.len and buf[result] in AsciiWhitespace - {'\n'}:
    inc result

proc stripAndCollapse*(s: openArray[char]): string =
  var res = newStringOfCap(s.len)
  var space = false
  for c in s.toOpenArray(s.skipBlanks(0), s.high):
    let cspace = c in AsciiWhitespace
    if not cspace:
      if space:
        res &= ' '
      res &= c
    space = cspace
  move(res)

proc until*(s: openArray[char]; c: set[char]; starti = 0): string =
  result = ""
  for i in starti ..< s.len:
    if s[i] in c:
      break
    result &= s[i]

proc untilLower*(s: openArray[char]; c: set[char]; starti = 0): string =
  result = ""
  for i in starti ..< s.len:
    if s[i] in c:
      break
    result.add(s[i].toLowerAscii())

proc until*(s: openArray[char]; c: char; starti = 0): string =
  return s.until({c}, starti)

proc untilLower*(s: openArray[char]; c: char; starti = 0): string =
  return s.untilLower({c}, starti)

proc after*(s: string; c: set[char]): string =
  let i = s.find(c)
  if i != -1:
    return s.substr(i + 1)
  return ""

proc after*(s: string; c: char): string = s.after({c})

proc afterLast*(s: string; c: set[char]; n = 1): string =
  var j = 0
  for i in countdown(s.high, 0):
    if s[i] in c:
      inc j
      if j == n:
        return s.substr(i + 1)
  return s

proc afterLast*(s: string; c: char; n = 1): string = s.afterLast({c}, n)

proc untilLast*(s: string; c: set[char]; n = 1): string =
  var j = 0
  for i in countdown(s.high, 0):
    if s[i] in c:
      inc j
      if j == n:
        return s.substr(0, i)
  return s

proc untilLast*(s: string; c: char; n = 1): string = s.untilLast({c}, n)

proc snprintf(str: cstring; size: csize_t; format: cstring): cint
  {.header: "<stdio.h>", importc, varargs}

# From w3m
const SizeUnit = [
  cstring"b", cstring"kb", cstring"Mb", cstring"Gb", cstring"Tb", cstring"Pb",
  cstring"Eb", cstring"Zb", cstring"Bb", cstring"Yb"
]
proc convertSize*(size: uint64): string =
  var sizepos = 0
  var csize = float32(size)
  while csize >= 999.495 and sizepos < SizeUnit.len:
    csize = csize / 1024.0
    inc sizepos
  result = newString(10)
  let f = floor(csize * 100 + 0.5) / 100
  discard snprintf(cstring(result), csize_t(result.len), "%.3g%s", f,
    SizeUnit[sizepos])
  result.setLen(cstring(result).len)

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

proc parseOctInt64*(s: openArray[char]): Opt[int64] =
  return parseIntImpl[int64, uint64](s, 8)

proc parseHexInt64*(s: openArray[char]): Opt[int64] =
  return parseIntImpl[int64, uint64](s, 16)

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
# used by pager
when defined(windows):
  const LocalPathPercentEncodeSet* = Ascii - AsciiAlpha - AsciiDigit -
    {'.', '\\', '/'}
else:
  const LocalPathPercentEncodeSet* = Ascii - AsciiAlpha - AsciiDigit -
    {'.', '/'}

proc percentEncode*(append: var string; c: char; set: set[char];
    spaceAsPlus = false) {.inline.} =
  if spaceAsPlus and c == ' ':
    append &= '+'
  elif c notin set:
    append &= c
  else:
    append &= '%'
    append.pushHex(c)

proc percentEncode*(append: var string; s: openArray[char]; set: set[char];
    spaceAsPlus = false) =
  for c in s:
    append.percentEncode(c, set, spaceAsPlus)

proc percentEncode*(s: openArray[char]; set: set[char]; spaceAsPlus = false):
    string =
  result = ""
  result.percentEncode(s, set, spaceAsPlus)

proc percentDecode*(input: openArray[char]): string =
  result = ""
  var i = 0
  while i < input.len:
    let c = input[i]
    if c != '%' or i + 2 >= input.len:
      result &= c
    else:
      let h1 = input[i + 1].hexValue
      let h2 = input[i + 2].hexValue
      if h1 == -1 or h2 == -1:
        result &= c
      else:
        result &= char((h1 shl 4) or h2)
        i += 2
    inc i

type EscapeMode* = enum
  emAll # attribute chars plus single quote (non-standard but safest)
  emAttribute # text chars plus double quote ("attribute mode" in spec)
  emText # &, nbsp, <, > (default mode in spec)

proc htmlEscape*(s: openArray[char]; mode = emAll): string =
  result = newStringOfCap(s.len)
  var nbspMode = false
  for c in s:
    if nbspMode:
      if c == '\xA0':
        result &= "&nbsp;"
      else:
        result &= '\xC2' & c
      nbspMode = false
      continue
    case c
    of '<': result &= "&lt;"
    of '>': result &= "&gt;"
    of '&': result &= "&amp;"
    of '\xC2': nbspMode = true
    elif c == '"' and mode <= emAttribute: result &= "&quot;"
    elif c == '\'' and mode == emAll: result &= "&apos;"
    else: result &= c

proc dqEscape*(s: openArray[char]): string =
  result = newStringOfCap(s.len)
  for c in s:
    if c == '"':
      result &= '\\'
    result &= c

proc cssEscape*(s: openArray[char]): string =
  result = ""
  for c in s:
    if c == '\'':
      result &= '\\'
    result &= c

#basically std join but with char
proc join*(ss: openArray[string]; sep: char): string =
  if ss.len <= 0:
    return ""
  result = ss[0]
  for i in 1 ..< ss.len:
    result &= sep
    result &= ss[i]

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

proc utf16Len*(s: openArray[char]): int =
  result = 0
  for u in s.points:
    if u < 0x10000: # ucs-2
      result += 1
    else: # surrogate
      result += 2

proc c_getenv(name: cstring): cstring {.
  header: "<stdlib.h>", importc: "getenv".}
proc c_setenv(envname, envval: cstring; overwrite: cint): cint {.
  header: "<stdlib.h>", importc: "setenv".}
proc c_unsetenv(name: cstring): cint {.
  header: "<stdlib.h>", importc: "unsetenv".}

proc getEnvCString*(name: string): cstring =
  return c_getenv(cstring(name))

proc getEnvEmpty*(name: string; fallback = ""): string =
  var res = getEnvCString(name)
  if res == nil or res[0] == '\0':
    return fallback
  return $res

proc setEnv*(name, value: string): Opt[void] =
  if c_setenv(cstring(name), cstring(value), 1) != 0:
    return err()
  ok()

proc unsetEnv*(name: string) =
  discard c_unsetenv(cstring(name))

proc expandPath*(path: string): string =
  if path.len > 0 and path[0] == '~':
    if path.len == 1:
      return getEnvEmpty("HOME")
    if path[1] == '/':
      return getEnvEmpty("HOME") & path.substr(1)
    let usr = path.until({'/'}, 1)
    let p = getpwnam(cstring(usr))
    if p != nil and p.pw_dir != nil:
      return $p.pw_dir & '/' & path.substr(usr.len)
  return path

proc deleteChars*(s: openArray[char]; todel: set[char]): string =
  result = newStringOfCap(s.len)
  for c in s:
    if c notin todel:
      result &= c

proc replaceControls*(s: openArray[char]): string =
  result = newStringOfCap(s.len)
  for u in s.points:
    if u.isControlChar():
      result &= u.controlToVisual()
    else:
      result.addUTF8(u)

#https://html.spec.whatwg.org/multipage/form-control-infrastructure.html#multipart/form-data-encoding-algorithm
proc makeCRLF*(s: openArray[char]): string =
  result = newStringOfCap(s.len)
  var i = 0
  while i < s.len - 1:
    if s[i] == '\r' and s[i + 1] != '\n':
      result &= '\r'
      result &= '\n'
    elif s[i] != '\r' and s[i + 1] == '\n':
      result &= s[i]
      result &= '\r'
      result &= '\n'
      inc i
    else:
      result &= s[i]
    inc i
  if i < s.len:
    if s[i] == '\r':
      result &= '\r'
      result &= '\n'
    else:
      result &= s[i]

type IdentMapItem* = tuple[s: string; n: int]

proc getIdentMap*[T: enum](e: typedesc[T]): seq[IdentMapItem] =
  result = @[]
  for e in T.low .. T.high:
    result.add(($e, int(e)))
  result.sort(proc(x, y: IdentMapItem): int = cmp(x.s, y.s))

proc cmpItem(x: IdentMapItem; y: string): int =
  return x.s.cmp(y)

proc strictParseEnum0(map: openArray[IdentMapItem]; s: string): int =
  let i = map.binarySearch(s, cmpItem)
  if i != -1:
    return map[i].n
  return -1

proc strictParseEnum*[T: enum](s: string): Opt[T] =
  const IdentMap = getIdentMap(T)
  let n = IdentMap.strictParseEnum0(s)
  if n != -1:
    {.push rangeChecks: off.}
    return ok(T(n))
    {.pop.}
  err()

proc parseEnumNoCase0*(map: openArray[IdentMapItem]; s: string): int =
  let i = map.binarySearch(s, proc(x: IdentMapItem; y: string): int =
    return x[0].cmpIgnoreCase(y)
  )
  if i != -1:
    return map[i].n
  return -1

proc parseEnumNoCase*[T: enum](s: string): Opt[T] =
  const IdentMap = getIdentMap(T)
  let n = IdentMap.parseEnumNoCase0(s)
  if n != -1:
    {.push rangeChecks: off.}
    return ok(T(n))
    {.pop.}
  return err()

const tchar = AsciiAlphaNumeric +
  {'!', '#'..'\'', '*', '+', '-', '.', '^', '_', '`', '|', '~'}

proc getContentTypeAttr*(contentType, attrname: string): string =
  var i = contentType.find(';')
  if i == -1:
    return ""
  i = contentType.find(attrname, i)
  if i == -1:
    return ""
  i = contentType.skipBlanks(i + attrname.len)
  if i >= contentType.len or contentType[i] != '=':
    return ""
  i = contentType.skipBlanks(i + 1)
  if i >= contentType.len:
    return ""
  var q = false
  result = ""
  let dq = contentType[i] == '"'
  if dq:
    inc i
  for c in contentType.toOpenArray(i, contentType.high):
    if q:
      result &= c
      q = false
    elif dq and c == '"':
      break
    elif c == '\\':
      q = true
    elif not dq and c notin tchar:
      break
    else:
      result &= c

# turn value into quoted-string
proc mimeQuote*(value: string): string =
  var s = newStringOfCap(value.len)
  s &= '"'
  var found = false
  for c in value:
    if c notin tchar:
      s &= '\\'
      found = true
    s &= c
  if not found:
    return value
  s &= '"'
  move(s)

proc setContentTypeAttr*(contentType: var string; attrname, value: string) =
  var i = contentType.find(';')
  if i == -1:
    contentType &= ';' & attrname & '=' & value
    return
  i = contentType.find(attrname, i)
  if i == -1:
    contentType &= ';' & attrname & '=' & value
    return
  i = contentType.skipBlanks(i + attrname.len)
  if i >= contentType.len or contentType[i] != '=':
    contentType &= ';' & attrname & '=' & value
    return
  i = contentType.skipBlanks(i + 1)
  var q = false
  var j = i
  while j < contentType.len:
    let c = contentType[j]
    if q:
      q = false
    elif c == '\\':
      q = true
    elif c notin tchar:
      break
    inc j
  contentType[i..<j] = value.mimeQuote()

proc atob(c: char): uint8 {.inline.} =
  # see RFC 4648 table
  if c in AsciiUpperAlpha:
    return uint8(c) - uint8('A')
  if c in AsciiLowerAlpha:
    return uint8(c) - uint8('a') + 26
  if c in AsciiDigit:
    return uint8(c) - uint8('0') + 52
  if c == '+':
    return 62
  if c == '/':
    return 63
  return uint8.high

# Warning: this overrides outs.
proc atob*(outs: var string; data: string): Err[cstring] =
  outs = newStringOfCap(data.len div 4 * 3)
  var buf = array[4, uint8].default
  var i = 0
  var j = 0
  var pad = 0
  while true:
    i = data.skipBlanks(i)
    if i >= data.len:
      break
    if data[i] == '=':
      i = data.skipBlanks(i + 1)
      inc pad
      break
    buf[j] = atob(data[i])
    if buf[j] == uint8.high:
      return err("Invalid character in encoded string")
    if j == 3:
      let ob1 = (buf[0] shl 2) or (buf[1] shr 4) # 6 bits of b0 | 2 bits of b1
      let ob2 = (buf[1] shl 4) or (buf[2] shr 2) # 4 bits of b1 | 4 bits of b2
      let ob3 = (buf[2] shl 6) or buf[3]         # 2 bits of b2 | 6 bits of b3
      outs &= char(ob1)
      outs &= char(ob2)
      outs &= char(ob3)
      j = 0
    else:
      inc j
    inc i
  if i < data.len:
    if i < data.len and data[i] == '=':
      inc pad
      inc i
    i = data.skipBlanks(i)
  if pad > 0 and j + pad != 4:
    return err("Too much padding")
  if i < data.len:
    return err("Invalid character after encoded string")
  if j == 3:
    let ob1 = (buf[0] shl 2) or (buf[1] shr 4) # 6 bits of b0 | 2 bits of b1
    let ob2 = (buf[1] shl 4) or (buf[2] shr 2) # 4 bits of b1 | 4 bits of b2
    outs &= char(ob1)
    outs &= char(ob2)
  elif j == 2:
    let ob1 = (buf[0] shl 2) or (buf[1] shr 4) # 6 bits of b0 | 2 bits of b1
    outs &= char(ob1)
  elif j != 0:
    return err("Incorrect number of characters in encoded string")
  return ok()

const AMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

proc btoa*(s: var string; data: openArray[uint8]) =
  var i = 0
  let endw = data.len - 2
  while i < endw:
    let n = uint32(data[i]) shl 16 or
      uint32(data[i + 1]) shl 8 or
      uint32(data[i + 2])
    i += 3
    s &= AMap[n shr 18 and 0x3F]
    s &= AMap[n shr 12 and 0x3F]
    s &= AMap[n shr 6 and 0x3F]
    s &= AMap[n and 0x3F]
  if i < data.len:
    let b1 = uint32(data[i])
    inc i
    if i < data.len:
      let b2 = uint32(data[i])
      s &= AMap[b1 shr 2]                      # 6 bits of b1
      s &= AMap[b1 shl 4 and 0x3F or b2 shr 4] # 2 bits of b1 | 4 bits of b2
      s &= AMap[b2 shl 2 and 0x3F]             # 4 bits of b2
    else:
      s &= AMap[b1 shr 2]          # 6 bits of b1
      s &= AMap[b1 shl 4 and 0x3F] # 2 bits of b1
      s &= '='
    s &= '='

proc btoa*(data: openArray[uint8]): string =
  if data.len == 0:
    return ""
  var L = data.len div 3 * 4
  if (let rem = data.len mod 3; rem) > 0:
    L += 3 - rem
  var s = newStringOfCap(L)
  s.btoa(data)
  move(s)

proc btoa*(data: openArray[char]): string =
  return btoa(data.toOpenArrayByte(0, data.len - 1))

iterator mypairs*[T](a: openArray[T]): tuple[key: int; val: lent T] {.inline.} =
  var i = 0u
  let L = uint(a.len)
  while i < L:
    yield (cast[int](i), a[i])
    inc i

iterator ritems*[T](a: openArray[T]): lent T {.inline.} =
  var i = uint(a.len)
  while i > 0:
    dec i
    yield a[i]

proc getFileExt*(path: string): string =
  let n = path.rfind({'/', '.'})
  if n < 0 or path[n] != '.':
    return ""
  return path.substr(n + 1)

iterator lineIndices*(s: openArray[char]): tuple[si, ei: int] {.inline.} =
  var i = 0
  let H = s.high
  while i < s.len:
    var j = i + s.toOpenArray(i, H).find('\n')
    if j == -1:
      j = H
    yield (i, j - 1)
    i = j + 1

when not defined(nimHasXorSet):
  proc toggle*[T](x: var set[T]; y: set[T]) =
    x = x + y - (x * y)

{.pop.} # raises: []
