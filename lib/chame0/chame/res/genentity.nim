import std/json
import std/streams
import std/strutils
import std/tables

type LineWriter = object
  s: Stream
  line: string

proc write(writer: var LineWriter, s: string) =
  if s.len + writer.line.len > 80:
    writer.s.writeLine(writer.line)
    writer.line = ""
  writer.line &= s

proc flush(writer: var LineWriter) =
  writer.s.writeLine(writer.line)
  writer.line = ""

proc nextUTF8(s: openArray[char]; i: var int): uint32 =
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

proc toCodeUnits(s: string): tuple[unit1, unit2: uint16] =
  var i = 0
  var u = s.nextUTF8(i)
  if u < 0x10000:
    if i == s.len:
      return (uint16(u), 0'u16)
    let u2 = s.nextUTF8(i)
    assert i == s.len
    return (uint16(u), uint16(u2))
  # one surrogate
  assert i == s.len
  u -= 0x10000
  return (uint16(u shr 10) + 0xD800, uint16(u and 0x3FF) + 0xDC00)

proc main() =
  let entityJson = parseJson(readFile("entity.json"))
  echo "type Z = cstring"
  var writer = LineWriter(s: newFileStream(stdout))
  var cc: char
  var charMap: array[char, int]
  for i in charMap.mitems:
    i = -1
  var entityMap: OrderedTable[string, string]
  for k, v in entityJson:
    if k[^1] == ';' and k.substr(1, k.high - 1) in entityMap:
      continue
    entityMap[k.substr(1)] = v{"characters"}.getStr()
  let n = entityMap.len
  echo "const entityMap*: array[" & $n & ", tuple[name: Z; unit1, unit2: uint16]] = ["
  var i = 0
  for k, v in entityMap:
    if k[0] != cc:
      cc = k[0]
      charMap[cc] = i
    let (unit1, unit2) = v.toCodeUnits()
    writer.write("(Z" & k.escape() & "," & $unit1 & "u16," & $unit2 & "u16),")
    inc i
  assert cc == 'z'
  writer.flush()
  echo "]"
  echo ""
  echo "const charMap*: array[char, int16] = ["
  for c in char.low..char.high:
    writer.write($charMap[c] & "i16,")
  writer.flush()
  echo "]"
main()
