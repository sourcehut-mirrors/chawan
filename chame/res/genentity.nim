import json
import streams
import strutils

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
  echo "const entityTable = ["
  var writer = LineWriter(s: newFileStream(stdout))
  for k, v in entityJson:
    let s = v{"characters"}.getStr().escape()
    writer.write("(Z\"" & k.substr(1) & "\"," & s & ".Z),")
  writer.flush()
  echo "]"
main()
