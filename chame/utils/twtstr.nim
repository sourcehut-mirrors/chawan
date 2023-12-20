import std/strutils

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

func startsWithNoCase*(str, prefix: string): bool =
  if str.len < prefix.len: return false
  # prefix.len is always lower
  var i = 0
  while true:
    if i == prefix.len: return true
    if str[i].toLowerAscii() != prefix[i].toLowerAscii(): return false
    inc i

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

func isSurrogate*(u: uint32): bool = u in 0xD800u32..0xDFFFu32
func isNonCharacter*(u: uint32): bool =
  u in 0xFDD0u32..0xFDEFu32 or
  u in [0xFFFEu32, 0xFFFFu32, 0x1FFFEu32, 0x1FFFFu32, 0x2FFFEu32, 0x2FFFFu32,
    0x3FFFEu32, 0x3FFFFu32, 0x4FFFEu32, 0x4FFFFu32, 0x5FFFEu32, 0x5FFFFu32,
    0x6FFFEu32, 0x6FFFFu32, 0x7FFFEu32, 0x7FFFFu32, 0x8FFFEu32, 0x8FFFFu32,
    0x9FFFEu32, 0x9FFFFu32, 0xAFFFEu32, 0xAFFFFu32, 0xBFFFEu32, 0xBFFFFu32,
    0xCFFFEu32, 0xCFFFFu32, 0xDFFFEu32, 0xDFFFFu32, 0xEFFFEu32, 0xEFFFFu32,
    0xFFFFEu32, 0xFFFFFu32, 0x10FFFEu32, 0x10FFFFu32]
