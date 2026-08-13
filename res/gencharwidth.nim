{.push raises: [].}

import io/chafile
import types/opt
import utils/strwidth
import utils/twtstr

proc die(s: string) {.noreturn.} =
  discard cast[ChaFile](stderr).writeLine("gencharwidth: " & s)
  quit(1)

var DoubleWidthRanges: seq[(uint32, uint32)] = @[]
var DoubleWidthAmbiguousRanges: seq[(uint32, uint32)] = @[]

proc add(res: var seq[(uint32, uint32)]; s: string) =
  let i = s.find("..")
  var rstart: uint32
  var rend: uint32
  if i >= 0:
    rstart = uint32(parseHexInt64(s.toOpenArray(0, i - 1)).get)
    rend = uint32(parseHexInt64(s.toOpenArray(i + 2, s.high)).get)
  else:
    rstart = uint32(parseHexInt64(s).get)
    rend = rstart
  if res.len > 0 and res[^1][1] + 1 == rstart:
    res[^1][1] = rend
  else:
    res.add((rstart, rend))

proc loadRanges() =
  var s: string
  if readFile("res/EastAsianWidth.txt", s).isErr:
    die("failed to read res/EastAsianWidth.txt")
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
    of "W", "F": DoubleWidthRanges.add(firstcol)
    of "A": DoubleWidthAmbiguousRanges.add(firstcol)

type LineWriter = object
  line: string

proc flush(writer: var LineWriter) =
  let stdout = cast[ChaFile](stdout)
  discard stdout.write(writer.line & '\n')
  writer.line = ""

proc write(writer: var LineWriter, s: string) =
  if s.len + writer.line.len > 80:
    writer.flush()
  writer.line &= s

proc makePropertyTable(ranges: RangeMap): PropertyTable =
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
  var writer = LineWriter()
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

{.pop.} # raises: []
