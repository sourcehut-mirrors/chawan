import strutils
import unicode

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

const lowerChars = (func(): array[char, char] =
  for i in 0..255:
    if char(i) in 'A'..'Z':
      result[char(i)] = char(i + 32)
    else:
      result[char(i)] = char(i)
)()

func tolower*(c: char): char =
  return lowerChars[c]

func isAscii*(r: Rune): bool =
  return cast[uint32](r) < 128

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

func equalsIgnoreCase*(s1, s2: string): bool {.inline.} =
  return s1.cmpIgnoreCase(s2) == 0

func until*(s: string, c: set[char]): string =
  var i = 0
  while i < s.len:
    if s[i] in c:
      break
    result.add(s[i])
    inc i

func until*(s: string, c: char): string = s.until({c})

func isSurrogate*(r: Rune): bool = int32(r) in 0xD800..0xDFFF
func isNonCharacter*(r: Rune): bool =
  let n = int32(r)
  n in 0xFDD0..0xFDEF or
  n in [0xFFFE, 0xFFFF, 0x1FFFE, 0x1FFFF, 0x2FFFE, 0x2FFFF, 0x3FFFE, 0x3FFFF,
        0x4FFFE, 0x4FFFF, 0x5FFFE, 0x5FFFF, 0x6FFFE, 0x6FFFF, 0x7FFFE, 0x7FFFF,
        0x8FFFE, 0x8FFFF, 0x9FFFE, 0x9FFFF, 0xAFFFE, 0xAFFFF, 0xBFFFE, 0xBFFFF,
        0xCFFFE, 0xCFFFF, 0xDFFFE, 0xDFFFF, 0xEFFFE, 0xEFFFF, 0xFFFFE, 0xFFFFF,
        0x10FFFE, 0x10FFFF]
