import std/streams
import std/strutils

import utils/proptable
import utils/twtstr

var DoubleWidthRanges: seq[(uint32, uint32)] = @[]
var DoubleWidthAmbiguousRanges: seq[(uint32, uint32)] = @[]

proc loadRanges() =
  template add(firstcol: string, res: var seq[(uint32, uint32)]) =
    if firstcol.contains(".."):
      let fcs = firstcol.split("..")
      let rstart = uint32(parseHexInt(fcs[0]))
      let rend = uint32(parseHexInt(fcs[1]))
      res.add((rstart, rend))
    else:
      let cp = uint32(parseHexInt(firstcol))
      res.add((cp, cp))
  var f: File
  if not open(f, "res/map/EastAsianWidth.txt"):
    stderr.write("res/map/EastAsianWidth.txt not found\n")
    quit(1)
  let s = f.readAll()
  f.close()
  for line in s.split('\n'):
    if line.len == 0 or line[0] == '#':
      continue
    var i = 0
    var firstcol = ""
    var status = ""
    while i < line.len and line[i] notin {'#', ';'}:
      if line[i] != ' ':
        firstcol &= line[i]
      inc i
    if line[i] != '#':
      inc i
    while i < line.len and line[i] notin {'#', ';'}:
      if line[i] != ' ':
        status &= line[i]
      inc i
    case status
    of "W", "F": add(firstcol, DoubleWidthRanges)
    of "A": add(firstcol, DoubleWidthAmbiguousRanges)
    #of "H": add(firstcol, HalfWidthRanges)

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

func makePropertyTable(ranges: RangeMap): PropertyTable =
  var ucs = 0u32
  var k = 0
  while ucs <= 0xFFFF:
    if k > ranges.len:
      break
    if ranges[k][0] > ucs:
      ucs = ranges[k][0]
      continue
    if ranges[k][1] < ucs:
      inc k
      continue
    let i = ucs div (sizeof(ptint) * 8)
    let m = ucs mod (sizeof(ptint) * 8)
    result[i] = result[i] or ptint(1 shl m)
    inc ucs

proc main() =
  loadRanges()
  var DoubleWidthTable = makePropertyTable(DoubleWidthRanges)
  # Control chars return a width of 2, and are displayed as ^{letter}.
  for c in Controls:
    let u = ptint(c)
    let i = u div (sizeof(ptint) * 8)
    let m = u mod (sizeof(ptint) * 8)
    DoubleWidthTable[i] = DoubleWidthTable[i] or ptint(1 shl m)

  var dwrLen = 0
  for (ucs, mapped) in DoubleWidthRanges:
    if ucs > uint16.high: # lower ranges are added to DoubleWidthTable
      inc dwrLen
  echo "const DoubleWidthRanges: array[" & $dwrLen &
    ", tuple[ucs, mapped: uint32]] = ["
  var writer = LineWriter(s: newFileStream(stdout))
  for (ucs, mapped) in DoubleWidthRanges:
    if ucs > uint16.high: # lower ranges are added to DoubleWidthTable
      writer.write("(" & $ucs & "u32," & $mapped & "u32),")
  writer.flush()
  echo "]"
  echo ""

  echo "const DoubleWidthAmbiguousRanges: array[" &
    $DoubleWidthAmbiguousRanges.len & ", tuple[ucs, mapped: uint32]] = ["
  for (ucs, mapped) in DoubleWidthAmbiguousRanges:
    writer.write("(" & $ucs & "u32," & $mapped & "u32),")
  writer.flush()
  echo "]"
  echo ""

  echo "const DoubleWidthTable: PropertyTable = ["
  writer.write("uint32 ")
  for u in DoubleWidthTable:
    writer.write($u & "u32,")
  writer.flush()
  echo "]"
  echo ""

main()
