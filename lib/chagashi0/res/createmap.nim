import std/algorithm
import std/os
import std/sets
import std/streams
import std/strutils
import std/tables

iterator mapPairs(path: string): tuple[a, b: int] =
  let s = readFile("res/" / path)
  var k = 0
  while k < s.len:
    if s[k] == '\n':
      inc k
      continue
    if s[k] == '#':
      inc k
      while k < s.len and s[k] != '\n':
        inc k
      inc k
      continue
    while s[k] == ' ': inc k
    var j = k
    while s[k] in '0'..'9': inc k
    let index = parseInt(s.substr(j, k - 1))
    inc k # tab
    j = k
    while s[k] in {'0'..'9', 'A'..'F', 'x'}: inc k
    let n = parseHexInt(s.substr(j, k - 1))
    while k < s.len and s[k] != '\n': inc k
    inc k
    yield (index, n)

# All single-byte encodings map to ucs-2.
proc loadCharsetMap8(path: string): tuple[
      decode: seq[uint16],
      encode: seq[tuple[ucs: uint16; val: char]]
    ] =
  for index, n in mapPairs(path):
    while result.decode.len < index:
      result.decode.add(0)
    result.decode.add(uint16(n))
    result.encode.add((uint16(n), char(index)))
  result.encode.sort()

proc loadCharsetMapISO2022JPKatakana(path: string): array[char, uint16] =
  for index, n in mapPairs(path):
    result[char(index)] = uint16(n)

type UCS16x16* = tuple[ucs, p: uint16]
type PUCS16x16* = tuple[p, ucs: uint16]

proc loadGB18030Ranges(path: string): tuple[
      decode: seq[PUCS16x16],
      encode: seq[UCS16x16]
    ] =
  for index, n in mapPairs(path):
    if uint32(index) > uint32(high(uint16)): break
    result.decode.add((uint16(index), uint16(n)))
    result.encode.add((uint16(n), uint16(index)))
  result.encode.sort()

proc loadCharsetMap16(path: string): tuple[
      decode: seq[uint16],
      encode: seq[UCS16x16]
    ] =
  var found = initHashSet[int]()
  for index, n in mapPairs(path):
    while result.decode.len < index:
      result.decode.add(0)
    result.decode.add(uint16(n))
    if n notin found:
      found.incl(n)
      result.encode.add((uint16(n), uint16(index)))
  result.encode.sort()

proc loadCharsetMapJis0208(path: string): tuple[
      decode: seq[uint16],
      encode: seq[UCS16x16]
    ] =
  var found = initHashSet[int]()
  found.incl(0x2212)
  result.encode.add((0x2212u16, 60u16))
  for index, n in mapPairs(path):
    while result.decode.len < index:
      result.decode.add(0)
    result.decode.add(uint16(n))
    if n notin found:
      found.incl(n)
      result.encode.add((uint16(n), uint16(index)))
  result.encode.sort()

proc loadCharsetMapSJIS(path: string): seq[UCS16x16] =
  var found = initHashSet[int]()
  result.add((0x2212u16, 60u16))
  for index, n in mapPairs(path):
    if index < 8272:
      found.incl(n)
      continue
    if index in 8272..8835:
      continue # skip
    if n in found:
      continue
    found.incl(n)
    result.add((uint16(n), uint16(index)))
  result.sort()

type UCS32x16* = tuple[ucs: uint32, p: uint16]

proc loadBig5Map(path: string; offset: static uint16): tuple[
      decode: array[19782u16 - offset, uint16];
      encodeLow: seq[UCS16x16];
      encodeHigh: seq[UCS32x16]
    ] =
  var found = initHashSet[int]()
  for index, n in mapPairs(path):
    # Set high mappings to 1, then linear search encodeHigh.
    # Note that this means encodeHigh cannot be de-duped. Luckily, there appear
    # to be no duplicates in there.
    assert n != 1
    if n > int(uint16.high):
      result.decode[uint16(index) - offset] = 1
    else:
      result.decode[uint16(index) - offset] = uint16(n)
    if n in [0x2550, 0x255E, 0x2561, 0x256A, 0x5341, 0x5345]:
      if n notin found:
        found.incl(n)
        continue
    else:
      if n in found:
        assert n <= int(uint16.high)
        continue
      found.incl(n)
    if n > int(uint16.high):
      result.encodeHigh.add((uint32(n), uint16(index)))
    else:
      result.encodeLow.add((uint16(n), uint16(index)))
  #for i in result.decode: assert x != 0 # fail
  result.encodeLow.sort()
  result.encodeHigh.sort()

type LineWriter = object
  s: Stream
  line: string

proc write(writer: var LineWriter; s: string) =
  if s.len + writer.line.len > 80:
    writer.s.writeLine(writer.line)
    writer.line = ""
  writer.line &= s

proc flush(writer: var LineWriter) =
  writer.s.writeLine(writer.line)
  writer.line = ""

proc writeCharsetMap8(s: Stream; path, outname: string) =
  let (decode, encode) = loadCharsetMap8(path)
  s.write("const " & outname & "Decode*: array[" & $decode.len &
    ", uint16] = [\n")
  var writer = LineWriter(s: s)
  for c in decode:
    writer.write($c & ",")
  writer.flush()
  s.write("]\n")
  s.write("const " & outname & "Encode*: array[" & $encode.len &
    ", tuple[ucs: uint16, val: char]] = [\n")
  for (val, index) in encode:
    writer.write("(" & $val & "," & $int(index) & ".char),")
  writer.flush()
  s.write("]\n\n")

type Run = tuple[p, ucs: uint16; len: uint8]

# Writes a list of runs in the following format:
# * rightmost 13 bits: pointer
# * middle 12 bits: UCS codepoint offset - pointer
# * top 7 bits: run length
# The codepoint offset is the first UCS codepoint found in the run list minus
# the first pointer, so that you get the codepoint again as
# "offset + pointer + diff".
proc writeRuns(writer: var LineWriter; runs: seq[Run];
    isJis0212 = false): uint16 =
  var ucslo = uint16.high
  var pucs = 0u16
  var pp = 0u16
  for (p, ucs, len) in runs:
    ucslo = min(ucslo, ucs)
    if not isJis0212:
      assert ucs >= pucs
    assert p >= pp
    assert len < 128
    pp = p
    pucs = ucs
  for (p, ucs, len) in runs:
    let diff0 = int(ucs) - int(p) - int(ucslo)
    let diff = uint16(diff0)
    assert diff0 >= 0
    assert (p and 0x1FFF) == p
    assert (diff and 0xFFF) == diff
    let pack32 = (uint32(p) and 0x1FFF) or # 13 bits
      ((uint32(diff) and 0xFFF) shl 13) or # 12 bits
      (uint32(len) shl 25) # 7 bits
    assert pack32 shr 25 == len
    # 13 + 12 + 7 = 32
    writer.write($pack32 & "u32,")
  writer.flush()
  return ucslo

proc writeGB18030Map(s: Stream; path, outname: string) =
  let (decode, encode) = loadCharsetMap16(path)
  var runs: seq[Run] = @[]
  var runs2: seq[Run] = @[]
  var L = 0u16
  var L2 = 0u16
  var runc = 0u16
  var runp = 0u16
  var runlen = 0u8
  var runvals: set[uint16] = {}
  for i, val in decode:
    let row = i div 190
    let col = i mod 190
    if row <= 0x1F:
      if runlen == 0 or runc + uint16(runlen) != val:
        if runlen != 0:
          runs.add((runp, runc, runlen))
          runlen = 0
        runc = val
        runp = L2
      runvals.incl(val)
      assert runlen < 255
      inc runlen
      inc L2
      continue
    if row == 0x20 and col == 0: # finish final run1
      assert runlen > 0
      runs.add((runp, runc, runlen))
      runlen = 0
    if row <= 0x26 and col <= 0x5F:
      continue
    if row >= 0x29 and col <= 0x5F and row < 0x7C:
      if row == 0x29 and col == 0:
        L2 = 0
      if runlen == 0 or runc + uint16(runlen) != val or runlen >= 127:
        if runlen != 0:
          runs2.add((runp, runc, runlen))
          runlen = 0
        runc = val
        runp = L2
      runvals.incl(val)
      inc L2
      inc runlen
      continue
    elif row >= 0x7C and runlen > 0:
      runs2.add((runp, runc, runlen))
      runlen = 0
    inc L
  s.writeLine("const " & outname & "Runs*: array[" & $runs.len &
    ", uint32] = [")
  var writer = LineWriter(s: s)
  let ucslo = writer.writeRuns(runs)
  s.writeLine("]")
  s.writeLine("const " & outname & "RunsOffset* = " & $ucslo & "u16")
  s.writeLine("const " & outname & "Runs2*: array[" & $runs2.len &
    ", uint32] = [")
  let ucslo2 = writer.writeRuns(runs2)
  s.writeLine("]")
  s.writeLine("const " & outname & "RunsOffset2* = " & $ucslo2 & "u16")
  s.writeLine("const " & outname & "Decode*: array[" & $L & ", uint16] = [")
  for i, val in decode:
    let row = i div 190
    if row <= 0x1F:
      continue # runs
    let col = i mod 190
    if row <= 0x26 and col <= 0x5F:
      continue # PUA
    if row >= 0x29 and col <= 0x5F and row < 0x7C:
      continue # runs 2
    writer.write($val & ",")
  writer.flush()
  s.writeLine("]")
  var EL = 0
  for (val, index) in encode:
    if val in runvals:
      continue
    inc EL
  s.writeLine("const " & outname & "Encode*: array[" & $EL & ", UCS16x16] = [")
  for (val, index) in encode:
    if val in runvals:
      continue
    writer.write("(" & $val & "," & $index & "),")
  writer.flush()
  s.write("]\n\n")

proc writeJis0208Map(s: Stream; path, outname: string) =
  let (decode, encode) = loadCharsetMapJis0208(path)
  var L = 0
  for i in 0 ..< decode.len:
    let row = i div 94
    if row in 0x8 .. 0xB or row in 0xD .. 0xE or row in 0x54 .. 0x57 or
        row in 0x5C .. 0x71:
      continue
    inc L
  s.write("const " & outname & "Decode*: array[" & $L & ", uint16] = [\n")
  var writer = LineWriter(s: s)
  for i, val in decode:
    let row = i div 94
    if row in 0x8 .. 0xB or row in 0xD .. 0xE or row in 0x54 .. 0x57 or
        row in 0x5C .. 0x71:
      continue
    writer.write($val & ",")
  writer.flush()
  s.write("]\n")
  s.write("const " & outname & "Encode*: array[" & $encode.len &
    ", UCS16x16] = [\n")
  for (val, index) in encode:
    writer.write("(" & $val & "," & $index & "),")
  writer.flush()
  s.write("]\n\n")

proc writeJis0212Map(s: Stream; path, outname: string) =
  let (decode, _) = loadCharsetMap16(path)
  var writer = LineWriter(s: s)
  s.writeLine("const " & outname & "Decode*: array[" & $decode.len &
    ", uint16] = [")
  for i, val in decode:
    writer.write($val & ",")
  writer.flush()
  s.writeLine("]")

proc writeEUCKRMap(s: Stream; path, outname: string) =
  let (decode, encode) = loadCharsetMap16(path)
  var runs: seq[tuple[p, ucs: uint16; len: uint8]] = @[]
  var runs2: seq[tuple[p, ucs: uint16; len: uint8]] = @[]
  var runc = 0u16
  var runp = 0u16
  var runlen = 0u8
  var L = 0
  var L2 = 0u16
  var runvals: set[uint16] = {}
  for i, val in decode:
    let col = i mod 190
    if col in 0x1A .. 0x1F or col in 0x3A .. 0x3F:
      continue
    let row = i div 190
    if row <= 0x1F:
      if runlen == 0 or runc + uint16(runlen) != val:
        if runlen != 0:
          runs.add((runp, runc, runlen))
          runlen = 0
        runc = val
        runp = L2
      runvals.incl(val)
      inc runlen
      inc L2
      continue
    if col < 0x60:
      if val == 0:
        continue
      if row == 0x20 and col == 0:
        runs.add((runp, runc, runlen))
        runlen = 0
        L2 = 0
      if runlen == 0 or runc + uint16(runlen) != val:
        if runlen != 0:
          runs2.add((runp, runc, runlen))
          runlen = 0
        runc = val
        runp = L2
      runvals.incl(val)
      inc runlen
      inc L2
    else:
      if row > 0x45 and runlen > 0:
        runs2.add((runp, runc, runlen))
        runlen = 0
      inc L
  var writer = LineWriter(s: s)
  s.writeLine("const " & outname & "Runs*: array[" & $runs.len &
    ", uint32] = [")
  let ucslo = writer.writeRuns(runs)
  s.write("]\n")
  s.writeLine("const " & outname & "RunsOffset* = " & $ucslo & "u16")
  s.writeLine("const " & outname & "Runs2*: array[" & $runs2.len &
    ", uint32] = [")
  let ucslo2 = writer.writeRuns(runs2)
  s.write("]\n")
  s.writeLine("const " & outname & "RunsOffset2* = " & $ucslo2 & "u16")
  s.writeLine("const " & outname & "Decode*: array[" & $L & ", uint16] = [")
  for i, val in decode:
    let col = i mod 190
    if col in 0x1A .. 0x1F:
      continue
    if col in 0x3A .. 0x3F:
      continue
    let row = i div 190
    if row <= 0x1F:
      continue # runs
    if col < 0x60:
      continue # runs2 / empty space
    writer.write($val & ",")
  writer.flush()
  s.write("]\n")
  var EL = 0
  for (val, index) in encode:
    if val in runvals:
      continue
    inc EL
  s.writeLine("const " & outname & "Encode*: array[" & $EL & ", UCS16x16] = [")
  for (val, index) in encode:
    if val in runvals:
      continue
    writer.write("(" & $val & "," & $index & "),")
  writer.flush()
  s.write("]\n\n")

proc writeGB18030RangesMap(s: Stream; path, outname: string) =
  let (decode, encode) = loadGB18030Ranges(path)
  s.write("const " & outname & "Decode*: array[" & $decode.len &
    ", PUCS16x16] = [\n")
  var writer = LineWriter(s: s)
  for (val, index) in decode:
    writer.write("(" & $index & "," & $index & "),")
  writer.flush()
  s.write("]\n")
  s.write("const " & outname & "Encode*: array[" & $encode.len &
    ", UCS16x16] = [\n")
  for (val, index) in encode:
    writer.write("(" & $val & "," & $index & "),")
  writer.flush()
  s.write("]\n\n")

proc writeBig5Map(s: Stream; path, outname: string; offset: static uint16) =
  let (decode, encode0, encode1) = loadBig5Map(path, offset)
  s.write("const " & outname & "Decode*: array[" & $decode.len &
    ", uint16] = [\n")
  var writer = LineWriter(s: s)
  for val in decode:
    writer.write($val & ",")
  writer.flush()
  s.write("]\n")
  s.write("const " & outname & "EncodeLow*: array[" & $encode0.len &
    ", UCS16x16] = [\n")
  for (val, index) in encode0:
    writer.write("(" & $val & "," & $index & "),")
  writer.flush()
  s.write("]\n")
  s.write("const " & outname & "EncodeHigh*: array[" & $encode1.len &
    ", UCS32x16] = [\n")
  for (val, index) in encode1:
    writer.write("(" & $val & "," & $index & "),")
  writer.flush()
  s.write("]\n\n")

proc writeShiftJISMap(s: Stream; path, outname: string) =
  let encode = loadCharsetMapSJIS(path)
  s.write("const " & outname & "Encode*: array[" & $encode.len &
    ", UCS16x16] = [\n")
  var writer = LineWriter(s: s)
  for (val, index) in encode:
    writer.write("(" & $val & "," & $index & "),")
  writer.flush()
  s.write("]\n\n")

proc writeISO2022JPKatakanaEncode(s: Stream; path: string) =
  let encode = loadCharsetMapISO2022JPKatakana(path)
  s.write("const ISO2022JPKatakanaMap*: array[uint8, uint16] = [\n")
  var writer = LineWriter(s: s)
  for index in encode:
    writer.write($int(index) & ",")
  writer.flush()
  s.write("]\n\n")

let s = newFileStream(stdout)
s.writeLine("const Big5DecodeOffset* = 942")
s.writeLine("type UCS16x16* = tuple[ucs, p: uint16]")
s.writeLine("type UCS32x16* = tuple[ucs: uint32, p: uint16]")
s.writeLine("type PUCS16x16* = tuple[p, ucs: uint16]")
s.writeLine()
s.writeCharsetMap8("index-ibm866.txt", "IBM866")
s.writeCharsetMap8("index-iso-8859-2.txt", "ISO88592")
s.writeCharsetMap8("index-iso-8859-3.txt", "ISO88593")
s.writeCharsetMap8("index-iso-8859-4.txt", "ISO88594")
s.writeCharsetMap8("index-iso-8859-5.txt", "ISO88595")
s.writeCharsetMap8("index-iso-8859-6.txt", "ISO88596")
s.writeCharsetMap8("index-iso-8859-7.txt", "ISO88597")
s.writeCharsetMap8("index-iso-8859-8.txt", "ISO88598")
s.writeCharsetMap8("index-iso-8859-10.txt", "ISO885910")
s.writeCharsetMap8("index-iso-8859-13.txt", "ISO885913")
s.writeCharsetMap8("index-iso-8859-14.txt", "ISO885914")
s.writeCharsetMap8("index-iso-8859-15.txt", "ISO885915")
s.writeCharsetMap8("index-iso-8859-16.txt", "ISO885916")
s.writeCharsetMap8("index-koi8-r.txt", "KOI8R")
s.writeCharsetMap8("index-koi8-u.txt", "KOI8U")
s.writeCharsetMap8("index-macintosh.txt", "Macintosh")
s.writeCharsetMap8("index-windows-874.txt", "Windows874")
s.writeCharsetMap8("index-windows-1250.txt", "Windows1250")
s.writeCharsetMap8("index-windows-1251.txt", "Windows1251")
s.writeCharsetMap8("index-windows-1252.txt", "Windows1252")
s.writeCharsetMap8("index-windows-1253.txt", "Windows1253")
s.writeCharsetMap8("index-windows-1254.txt", "Windows1254")
s.writeCharsetMap8("index-windows-1255.txt", "Windows1255")
s.writeCharsetMap8("index-windows-1256.txt", "Windows1256")
s.writeCharsetMap8("index-windows-1257.txt", "Windows1257")
s.writeCharsetMap8("index-windows-1258.txt", "Windows1258")
s.writeCharsetMap8("index-x-mac-cyrillic.txt", "XMacCyrillic")
s.writeGB18030Map("index-gb18030.txt", "GB18030")
s.writeJis0208Map("index-jis0208.txt", "Jis0208")
s.writeJis0212Map("index-jis0212.txt", "Jis0212")
s.writeEUCKRMap("index-euc-kr.txt", "EUCKR")
s.writeGB18030RangesMap("index-gb18030-ranges.txt", "GB18030Ranges")
const Big5DecodeOffset* = 942
s.writeBig5Map("index-big5.txt", "Big5", offset = Big5DecodeOffset)
s.writeShiftJISMap("index-jis0208.txt", "ShiftJIS")
s.writeISO2022JPKatakanaEncode("index-iso-2022-jp-katakana.txt")
s.close()
