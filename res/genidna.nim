import std/algorithm
import std/sets
import std/streams
import std/strutils
import std/tables

import utils/twtstr

type
  LowMap = seq[tuple[ucs: uint16, s: string]]
  FullRangeList = tuple[lm: seq[(uint16, uint16)], hm: seq[(uint32, uint32)]]
  FullSet = tuple[lm: seq[uint16], hm: seq[uint32]]

var MappedMapLow: LowMap = @[]
var MappedMapHigh1: LowMap = @[]
var MappedMapHigh2: LowMap = @[]
var MappedMapStrings: seq[string] = @[]
var DisallowedRanges: FullRangeList
var Disallowed: FullSet
var IgnoredRanges: FullRangeList

proc addMap(u: uint32; str: string) =
  if u < 0x10000:
    MappedMapLow.add((uint16(u), str))
  elif u < 0x20000:
    MappedMapHigh1.add((uint16(u - 0x10000), str))
  elif u < 0x30000:
    MappedMapHigh2.add((uint16(u - 0x20000), str))
  else:
    assert false, "need a higher mapped map"
  MappedMapStrings.add(str)

proc addDisallow(i, j: uint32) =
  if i <= uint16.high:
    DisallowedRanges.lm.add((uint16(i), uint16(j)))
  else:
    DisallowedRanges.hm.add((i, j))

proc addDisallow(u: uint32) =
  if u <= uint16.high:
    Disallowed.lm.add(uint16(u))
  else:
    Disallowed.hm.add(u)

proc addIgnore(rstart, rend: uint32) =
  if rstart <= uint16.high:
    assert rend <= uint16.high
    IgnoredRanges.lm.add((uint16(rstart), uint16(rend)))
  else:
    IgnoredRanges.hm.add((uint32(rstart), uint32(rend)))

proc addIgnore(u: uint32) =
  if u <= uint16.high:
    IgnoredRanges.lm.add((uint16(u), uint16(u)))
  else:
    IgnoredRanges.hm.add((uint32(u), uint32(u)))

proc loadIdnaData() =
  template add(firstcol: string; temp: untyped) =
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

      if firstcol.contains(".."):
        let fcs = firstcol.split("..")
        let rstart = uint32(parseHexInt(fcs[0]))
        let rend = uint32(parseHexInt(fcs[1]))
        for i in rstart..rend:
          addMap(i, str)
      else:
        addMap(uint32(parseHexInt(firstcol)), str)
    of "valid":
      if fourthcol == "NV8" or fourthcol == "XV8":
        add(firstcol, addDisallow)
    of "disallowed":
      add(firstcol, addDisallow)
    of "ignored":
      add(firstcol, addIgnore)

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
    writer.write("(" & $ucs & "u16," & $idxMap[s] & "u16),")
  writer.flush()
  echo "]"
  echo ""
  echo "const MappedMapHigh1: array[" & $MappedMapHigh1.len &
    ", tuple[ucs, idx: uint16]] = ["
  for (ucs, s) in MappedMapHigh1:
    writer.write("(" & $ucs & "u16," & $idxMap[s] & "u16),")
  writer.flush()
  echo "]"
  echo ""
  echo "const MappedMapHigh2: array[" & $MappedMapHigh2.len &
    ", tuple[ucs, idx: uint16]] = ["
  for (ucs, s) in MappedMapHigh2:
    writer.write("(" & $ucs & "u16," & $idxMap[s] & "u16),")
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
    writer.write("(" & $ucs & "u16," & $mapped & "u16),")
  writer.flush()
  echo "]"
  echo ""
  echo "const DisallowedRangesHigh: array[" & $DisallowedRanges.hm.len &
    ", tuple[ucs, mapped: uint32]] = ["
  for (ucs, mapped) in DisallowedRanges.hm:
    writer.write("(" & $ucs & "u32," & $mapped & "u32),")
  writer.flush()
  echo "]"
  echo ""

  echo "const DisallowedLow: array[" & $Disallowed.lm.len & ", uint16] = ["
  writer.write("uint16 ")
  for ucs in Disallowed.lm:
    writer.write($ucs & ",")
  writer.flush()
  echo "]"
  echo ""
  echo "const DisallowedHigh: array[" & $Disallowed.hm.len & ", uint32] = ["
  writer.write("uint32 ")
  for ucs in Disallowed.hm:
    writer.write($ucs & ",")
  writer.flush()
  echo "]"

  echo ""
  echo "const IgnoredLow: array[" & $IgnoredRanges.lm.len &
    ", tuple[s, e: uint16]] = ["
  for (s, e) in IgnoredRanges.lm:
    writer.write("(" & $s & "u16," & $e & "u16),")
  writer.flush()
  echo "]"
  echo ""
  echo "const IgnoredHigh: array[" & $IgnoredRanges.hm.len &
    ", tuple[s, e: uint32]] = ["
  for (s, e) in IgnoredRanges.hm:
    writer.write("(" & $s & "u32," & $e & "u32),")
  writer.flush()
  echo "]"

main()
