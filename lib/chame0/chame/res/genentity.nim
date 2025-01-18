import std/json
import std/streams
import std/strutils

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

proc main() =
  let entityJson = parseJson(readFile("entity.json"))
  echo "type Z = cstring"
  var writer = LineWriter(s: newFileStream(stdout))
  var cc: char
  var charMap: array[char, int]
  for i in charMap.mitems:
    i = -1
  var entityMap: seq[tuple[name, value: string]]
  for k, v in entityJson:
    entityMap.add((k.substr(1), v{"characters"}.getStr()))
  let n = entityMap.len
  echo "const entityMap*: array[" & $n & ", Z] = ["
  var i = 0
  for (k, v) in entityMap:
    if k[0] != cc:
      charMap[cc] = i - 1
      cc = k[0]
    writer.write((k & ":" & v).escape() & ",")
    inc i
  assert cc == 'z'
  charMap[cc] = i - 1
  writer.flush()
  echo "]"
  echo ""
  echo "const charMap*: array[char, int] = ["
  for c in char.low..char.high:
    writer.write($charMap[c] & ",")
  writer.flush()
  echo "]"
main()
