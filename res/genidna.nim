import std/algorithm
import std/sets
import std/streams
import std/strutils
import std/tables

import utils/twtstr

type
  LowMap = seq[tuple[ucs: uint16, s: string]]
  HighMap = seq[tuple[ucs: uint32, s: string]]
  FullRangeList = tuple[lm: seq[(uint16, uint16)], hm: seq[(uint32, uint32)]]
  FullSet = tuple[lm: seq[uint16], hm: seq[uint32]]

var MappedMapLow: LowMap = @[]
var MappedMapHigh: HighMap = @[]
var MappedMapStrings: seq[string] = @[]
var DisallowedRanges: FullRangeList
var Disallowed: FullSet
var Ignored: FullSet

proc loadIdnaData() =
  template add_map(i: uint32, str: string) =
    if i <= high(uint16):
      MappedMapLow.add((uint16(i), str))
    else:
      MappedMapHigh.add((i, str))
    MappedMapStrings.add(str)
  template add_disallow(i, j: uint32) =
    if i <= high(uint16):
      DisallowedRanges.lm.add((uint16(i), uint16(j)))
    else:
      DisallowedRanges.hm.add((i, j))
  template add_disallow(i: uint32) =
    if i <= high(uint16):
      Disallowed.lm.add(uint16(i))
    else:
      Disallowed.hm.add(i)
  template add_ignore(rstart, rend: uint32) =
    for i in rstart..rend:
      if i <= high(uint16):
        Ignored.lm.add(uint16(i))
      else:
        Ignored.hm.add(i)
  template add_ignore(i: uint32) =
    if i <= high(uint16):
      Ignored.lm.add(uint16(i))
    else:
      Ignored.hm.add(i)
  template add(firstcol: string, str: string, temp: untyped) =
    if firstcol.contains(".."):
      let fcs = firstcol.split("..")
      let rstart = uint32(parseHexInt(fcs[0]))
      let rend = uint32(parseHexInt(fcs[1]))
      for i in rstart..rend:
        temp(i, str)
    else:
      temp(uint32(parseHexInt(firstcol)), str)
  template add(firstcol: string, temp: untyped) =
    if firstcol.contains(".."):
      let fcs = firstcol.split("..")
      let rstart = uint32(parseHexInt(fcs[0]))
      let rend = uint32(parseHexInt(fcs[1]))
      temp(rstart, rend)
    else:
      temp(uint32(parseHexInt(firstcol)))

  var f: File
  if not open(f, "res/map/IdnaMappingTable.txt"):
    stderr.write("res/map/IdnaMappingTable.txt not found\n")
    quit(1)
  let s = f.readAll()
  f.close()
  for line in s.split('\n'):
    if line.len == 0 or line[0] == '#':
      continue
    var i = 0
    var firstcol = ""
    var status = ""
    var thirdcol: seq[string]
    var fourthcol = ""

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
    if line[i] != '#':
      inc i

    var nw = true
    while i < line.len and line[i] notin {'#', ';'}:
      if line[i] == ' ':
        nw = true
      else:
        if nw:
          thirdcol.add("")
          nw = false
        thirdcol[^1] &= line[i]
      inc i
    if line[i] != '#':
      inc i

    while i < line.len and line[i] notin {'#', ';'}:
      if line[i] != ' ':
        fourthcol &= line[i]
      inc i

    case status
    of "mapped", "disallowed_STD3_mapped":
      let codepoints = thirdcol
      var str = ""
      for code in codepoints:
        str &= uint32(parseHexInt(code)).toUTF8()

      add(firstcol, str, add_map)
    of "valid":
      if fourthcol == "NV8" or fourthcol == "XV8":
        add(firstcol, add_disallow)
    of "disallowed":
      add(firstcol, add_disallow)
    of "ignored":
      add(firstcol, add_ignore)

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
  loadIdnaData()
  var writer = LineWriter(s: newFileStream(stdout))
  echo "const MappedMapLow: array[" & $MappedMapLow.len &
    ", tuple[ucs, idx: uint16]] = ["
  MappedMapStrings.sort(proc(a, b: string): int = cmp(a.len, b.len),
    order = Descending)
  var mdata = ""
  var idxMap = initTable[string, int]()
  for s in MappedMapStrings:
    let s0 = s & '\0'
    let i = mdata.find(s0)
    if i != -1:
      idxMap[s] = i
    else:
      idxMap[s] = mdata.len
      mdata &= s0
  for (ucs, s) in MappedMapLow:
    writer.write("(" & $ucs & "," & $idxMap[s] & "),")
  writer.flush()
  echo "]"
  echo ""
  echo "const MappedMapHigh: array[" & $MappedMapHigh.len &
    ", tuple[ucs: uint32; idx: uint16]] = ["
  for (ucs, s) in MappedMapHigh:
    writer.write("(" & $ucs & "," & $idxMap[s] & "),")
  writer.flush()
  echo "]"
  echo ""
  stdout.write("const MappedMapData = ")
  stdout.write(mdata.escape())
  echo ""
  echo ""

  echo "const DisallowedRangesLow: array[" & $DisallowedRanges.lm.len &
    ", tuple[ucs, mapped: uint16]] = ["
  for (ucs, mapped) in DisallowedRanges.lm:
    writer.write("(" & $ucs & "," & $mapped & "),")
  writer.flush()
  echo "]"
  echo ""
  echo "const DisallowedRangesHigh: array[" & $DisallowedRanges.hm.len &
    ", tuple[ucs, mapped: uint32]] = ["
  for (ucs, mapped) in DisallowedRanges.hm:
    writer.write("(" & $ucs & "," & $mapped & "),")
  writer.flush()
  echo "]"
  echo ""

  echo "const DisallowedLow: array[" & $Disallowed.lm.len & ", uint16] = ["
  for ucs in Disallowed.lm:
    writer.write($ucs & ",")
  writer.flush()
  echo "]"
  echo ""
  echo "const DisallowedHigh: array[" & $Disallowed.hm.len & ", uint32] = ["
  for ucs in Disallowed.hm:
    writer.write($ucs & ",")
  writer.flush()
  echo "]"

  echo ""
  echo "const IgnoredLow: array[" & $Ignored.lm.len & ", uint16] = ["
  for ucs in Ignored.lm:
    writer.write($ucs & ",")
  writer.flush()
  echo "]"
  echo ""
  echo "const IgnoredHigh: array[" & $Ignored.hm.len & ", uint32] = ["
  for ucs in Ignored.hm:
    writer.write($ucs & ",")
  writer.flush()
  echo "]"

main()
