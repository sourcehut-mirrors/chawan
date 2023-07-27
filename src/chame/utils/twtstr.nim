import strutils
import unicode
import math

const C0Controls* = {chr(0x00)..chr(0x1F)}
const Controls* = (C0Controls + {chr(0x7F)})
const Ascii* = {chr(0x00)..chr(0x7F)}
const AsciiUpperAlpha* = {'A'..'Z'}
const AsciiLowerAlpha* = {'a'..'z'}
const AsciiAlpha* = (AsciiUpperAlpha + AsciiLowerAlpha)
const NonAscii* = (AllChars - Ascii)
const AsciiDigit* = {'0'..'9'}
const AsciiAlphaNumeric* = AsciiAlpha + AsciiDigit
const AsciiHexDigit* = (AsciiDigit + {'a'..'f', 'A'..'F'})
const AsciiWhitespace* = {' ', '\n', '\r', '\t', '\f'}

func isWhitespace*(c: char): bool {.inline.} =
  return c in AsciiWhitespace

func onlyWhitespace*(s: string): bool =
  for c in s:
    if not c.isWhitespace():
      return false
  return true

func isControlChar*(r: Rune): bool =
  case r
  of Rune(0x00)..Rune(0x1F): return true
  of Rune(0x7F): return true
  else: return false

func isC0ControlOrSpace*(c: char): bool =
  return c in (Controls + {' '})

func genControlCharMap*(): string =
  for c in low(char)..high(char):
    if c == '?':
      result &= char(127)
    else:
      result &= char((int(c) and 0x1f))

const controlCharMap = genControlCharMap()

func getControlChar*(c: char): char =
  return controlCharMap[int(c)]

func genControlLetterMap*(): string =
  for c in low(char)..high(char):
    if c == char(127):
      result &= '?'
    else:
      result &= char((int(c) or 0x40))

const controlLetterMap = genControlLetterMap()

func getControlLetter*(c: char): char =
  return controlLetterMap[int(c)]

const lowerChars = (func(): array[char, char] =
  for i in 0..255:
    if char(i) in 'A'..'Z':
      result[char(i)] = char(i + 32)
    else:
      result[char(i)] = char(i)
)()

func tolower*(c: char): char =
  return lowerChars[c]

func toLowerAscii2*(str: string): string =
  var i = 0
  block noconv:
    while i < str.len:
      let c = str[i]
      if c in AsciiUpperAlpha:
        break noconv
      inc i
    return str
  result = newString(str.len)
  prepareMutation(result)
  copyMem(addr result[0], unsafeAddr str[0], i)
  for i in i ..< str.len:
    result[i] = str[i].tolower()

proc mtoLowerAscii*(str: var string) =
  for i in 0 ..< str.len:
    str[i] = str[i].tolower()

func toHeaderCase*(str: string): string =
  result = str
  var flip = true
  for i in 0..str.high:
    if flip:
      result[i] = result[i].toUpperAscii()
    flip = result[i] == '-'

func toScreamingSnakeCase*(str: string): string = # input is camel case
  if str.len >= 1: result &= str[0].toUpperAscii()
  for c in str[1..^1]:
    if c in AsciiUpperAlpha:
      result &= '_'
      result &= c
    else:
      result &= c.toUpperAscii()

func snakeToKebabCase*(str: string): string =
  result = str
  for c in result.mitems:
    if c == '_':
      c = '-'

func normalizeLocale*(s: string): string =
  for i in 0 ..< s.len:
    if cast[uint8](s[i]) > 0x20 and s[i] != '_' and s[i] != '-':
      result &= s[i].toLowerAscii()

func isAscii*(r: Rune): bool =
  return cast[uint32](r) < 128

func `==`*(r: Rune, c: char): bool {.inline.} =
  return Rune(c) == r

func startsWithNoCase*(str, prefix: string): bool =
  if str.len < prefix.len: return false
  # prefix.len is always lower
  var i = 0
  while true:
    if i == prefix.len: return true
    if str[i].tolower() != prefix[i].tolower(): return false
    inc i

const hexCharMap = (func(): array[char, int] =
  for i in 0..255:
    case chr(i)
    of '0'..'9': result[char(i)] = i - ord('0')
    of 'a'..'f': result[char(i)] = i - ord('a') + 10
    of 'A'..'F': result[char(i)] = i - ord('A') + 10
    else: result[char(i)] = -1
)()

const decCharMap = (func(): array[char, int] =
  for i in 0..255:
    case char(i)
    of '0'..'9': result[char(i)] = i - ord('0')
    else: result[char(i)] = -1
)()

func hexValue*(c: char): int =
  return hexCharMap[c]

func decValue*(c: char): int =
  return decCharMap[c]

func isAscii*(s: string): bool =
  for c in s:
    if c > char(0x80):
      return false
  return true

const HexCharsUpper = "0123456789ABCDEF"
const HexCharsLower = "0123456789abcdef"
func pushHex*(buf: var string, c: char) =
  buf &= HexCharsUpper[(uint8(c) shr 4)]
  buf &= HexCharsUpper[(uint8(c) and 0xF)]

func toHexLower*(u: uint16): string =
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
  return s

func pushHex*(buf: var string, i: uint8) =
  buf.pushHex(cast[char](i))

func equalsIgnoreCase*(s1: seq[Rune], s2: string): bool =
  var i = 0
  while i < min(s1.len, s2.len):
    if not s1[i].isAscii() or cast[char](s1[i]).tolower() != s2[i]:
      return false
    inc i
  return true

func equalsIgnoreCase*(s1, s2: string): bool {.inline.} =
  return s1.cmpIgnoreCase(s2) == 0

func isAlphaAscii*(r: Rune): bool =
  return int(r) < 256 and isAlphaAscii(char(r))

func isDigitAscii*(r: Rune): bool =
  return int(r) < 256 and isDigit(char(r))

func substr*(s: seq[Rune], i, j: int): seq[Rune] =
  if s.len == 0:
    return @[]
  return s[min(high(s), i)..min(high(s), j - 1)]

func substr*(s: seq[Rune], i: int): seq[Rune] =
  if i > high(s) or s.len == 0:
    return @[]
  return s[min(high(s), i)..high(s)]

func stripAndCollapse*(s: string): string =
  var i = 0
  while i < s.len and s[i] in AsciiWhitespace:
    inc i
  var space = false
  while i < s.len:
    if s[i] notin AsciiWhitespace:
      if space:
        result &= ' '
        space = false
      result &= s[i]
    elif not space:
      space = true
    else:
      result &= ' '
    inc i

func skipBlanks*(buf: string, at: int): int =
  result = at
  while result < buf.len and buf[result].isWhitespace():
    inc result

func until*(s: string, c: set[char]): string =
  var i = 0
  while i < s.len:
    if s[i] in c:
      break
    result.add(s[i])
    inc i

func until*(s: string, c: char): string = s.until({c})

func after*(s: string, c: set[char]): string =
  var i = 0
  while i < s.len:
    if s[i] in c:
      return s.substr(i + 1)
    inc i

func after*(s: string, c: char): string = s.after({c})

func afterLast*(s: string, c: set[char], n = 1): string =
  var j = 0
  for i in countdown(s.high, 0):
    if s[i] in c:
      inc j
      if j == n:
        return s.substr(i + 1)
  return s

func afterLast*(s: string, c: char, n = 1): string = s.afterLast({c}, n)

func beforeLast*(s: string, c: set[char], n = 1): string =
  var j = 0
  for i in countdown(s.high, 0):
    if s[i] in c:
      inc j
      if j == n:
        return s.substr(0, i)
  return s

func beforeLast*(s: string, c: char, n = 1): string = s.afterLast({c}, n)

proc c_sprintf(buf, fm: cstring): cint {.header: "<stdio.h>", importc: "sprintf", varargs}

# From w3m
const SizeUnit = [
  cstring"b", cstring"kb", cstring"Mb", cstring"Gb", cstring"Tb", cstring"Pb",
  cstring"Eb", cstring"Zb", cstring"Bb", cstring"Yb"
]
func convert_size*(size: int): string =
  var sizepos = 0
  var csize = float32(size)
  while csize >= 999.495 and sizepos < SizeUnit.len:
    csize = csize / 1024.0
    inc sizepos
  result = newString(10)
  let f = floor(csize * 100 + 0.5) / 100
  discard c_sprintf(cstring(result), cstring("%.3g%s"), f, SizeUnit[sizepos])
  result.setLen(cstring(result).len)

func number_additive*(i: int, range: HSlice[int, int], symbols: openarray[(int, string)]): string =
  if i notin range:
    return $i

  var n = i
  var at = 0
  while n > 0:
    if n >= symbols[at][0]:
      n -= symbols[at][0]
      result &= symbols[at][1]
      continue
    inc at

  return result

func isSurrogate*(r: Rune): bool = int32(r) in 0xD800..0xDFFF
func isNonCharacter*(r: Rune): bool =
  let n = int32(r)
  n in 0xFDD0..0xFDEF or
  n in [0xFFFE, 0xFFFF, 0x1FFFE, 0x1FFFF, 0x2FFFE, 0x2FFFF, 0x3FFFE, 0x3FFFF,
        0x4FFFE, 0x4FFFF, 0x5FFFE, 0x5FFFF, 0x6FFFE, 0x6FFFF, 0x7FFFE, 0x7FFFF,
        0x8FFFE, 0x8FFFF, 0x9FFFE, 0x9FFFF, 0xAFFFE, 0xAFFFF, 0xBFFFE, 0xBFFFF,
        0xCFFFE, 0xCFFFF, 0xDFFFE, 0xDFFFF, 0xEFFFE, 0xEFFFF, 0xFFFFE, 0xFFFFF,
        0x10FFFE, 0x10FFFF]

const ControlPercentEncodeSet* = (Controls + NonAscii)
const FragmentPercentEncodeSet* = (Controls + NonAscii)
const QueryPercentEncodeSet* = (ControlPercentEncodeSet + {' ', '"', '#', '<', '>'})
const SpecialQueryPercentEncodeSet* = (QueryPercentEncodeSet + {'\''})
const PathPercentEncodeSet* = (QueryPercentEncodeSet + {'?', '`', '{', '}'})
const UserInfoPercentEncodeSet* = (PathPercentEncodeSet + {'/', ':', ';', '=', '@', '['..'^', '|'})
const ComponentPercentEncodeSet* = (UserInfoPercentEncodeSet + {'$'..'&', '+', ','})
const ApplicationXWWWFormUrlEncodedSet* = (ComponentPercentEncodeSet + {'!', '\''..')', '~'})
# used by client
when defined(windows) or defined(OS2) or defined(DOS):
  const LocalPathPercentEncodeSet* = (Ascii - AsciiAlpha - AsciiDigit - {'.', '\\', '/'})
else:
  const LocalPathPercentEncodeSet* = (Ascii - AsciiAlpha - AsciiDigit -  {'.', '/'})

proc percentEncode*(append: var string, c: char, set: set[char], spaceAsPlus = false) {.inline.} =
  if spaceAsPlus and c == ' ':
    append &= '+'
  elif c notin set:
    append &= c
  else:
    append &= '%'
    append.pushHex(c)

proc percentEncode*(append: var string, s: string, set: set[char], spaceAsPlus = false) {.inline.} =
  for c in s:
    append.percentEncode(c, set, spaceAsPlus)

func percentEncode*(c: char, set: set[char], spaceAsPlus = false): string {.inline.} =
  result.percentEncode(c, set, spaceAsPlus)

func percentEncode*(s: string, set: set[char], spaceAsPlus = false): string =
  result.percentEncode(s, set, spaceAsPlus)

func percentDecode*(input: string): string =
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

#basically std join but with char
func join*(ss: openarray[string], sep: char): string =
  if ss.len == 0:
    return ""
  var n = ss.high - 1
  for i in 0..high(ss):
    n += ss[i].len
  result = newStringOfCap(n)
  result &= ss[0]
  for i in 1..high(ss):
    result &= sep
    result &= ss[i]

func clearControls*(s: string): string =
  for c in s:
    if c notin Controls:
      result &= c

iterator split*(s: seq[Rune], sep: Rune): seq[Rune] =
  var i = 0
  var prev = 0
  while i < s.len:
    if s[i] == sep:
      yield s.substr(prev, i)
      prev = i
    inc i

  if prev < i:
    yield s.substr(prev, i)
