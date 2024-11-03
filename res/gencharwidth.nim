import std/streams
import std/strutils

import utils/proptable
import utils/twtstr

var DoubleWidthRanges: seq[(uint32, uint32)]
var DoubleWidthAmbiguousRanges: seq[(uint32, uint32)]
#var HalfWidthRanges: seq[(uint32, uint32)]

# Combining chars from https://www.cl.cam.ac.uk/~mgk25/ucs/wcwidth.c
#
# The following two functions define the column width of an ISO 10646
# character as follows:
#
#   - The null character (U+0000) has a column width of 0.
#
#   - Other C0/C1 control characters and DEL will lead to a return value of 0
#
#   - Non-spacing and enclosing combining characters (general category code Mn
#     or Me in the Unicode database) have a column width of 0.
#
#   - SOFT HYPHEN (U+00AD) has a column width of 1.
#
#   - Other format characters (general category code Cf in the Unicode
#     database) and ZERO WIDTH SPACE (U+200B) have a column width of 0.
#
#   - Hangul Jamo medial vowels and final consonants (U+1160-U+11FF) have a
#     column width of 0.
#
#   - Spacing characters in the East Asian Wide (W) or East Asian Full-width
#     (F) category as defined in Unicode Technical Report #11 have a column
#     width of 2.
#
#   - All remaining characters (including all printable ISO 8859-1 and WGL4
#     characters, Unicode control characters, etc.) have a column width of 1.
#

# sorted list of non-overlapping intervals of non-spacing characters generated
# by "uniset +cat=Me +cat=Mn +cat=Cf -00AD +1160-11FF +200B c"
const Combining = [
  (0x0300u32, 0x036Fu32), (0x0483u32, 0x0486u32), (0x0488u32, 0x0489u32),
  (0x0591u32, 0x05BDu32), (0x05BFu32, 0x05BFu32), (0x05C1u32, 0x05C2u32),
  (0x05C4u32, 0x05C5u32), (0x05C7u32, 0x05C7u32), (0x0600u32, 0x0603u32),
  (0x0610u32, 0x0615u32), (0x064Bu32, 0x065Eu32), (0x0670u32, 0x0670u32),
  (0x06D6u32, 0x06E4u32), (0x06E7u32, 0x06E8u32), (0x06EAu32, 0x06EDu32),
  (0x070Fu32, 0x070Fu32), (0x0711u32, 0x0711u32), (0x0730u32, 0x074Au32),
  (0x07A6u32, 0x07B0u32), (0x07EBu32, 0x07F3u32), (0x0901u32, 0x0902u32),
  (0x093Cu32, 0x093Cu32), (0x0941u32, 0x0948u32), (0x094Du32, 0x094Du32),
  (0x0951u32, 0x0954u32), (0x0962u32, 0x0963u32), (0x0981u32, 0x0981u32),
  (0x09BCu32, 0x09BCu32), (0x09C1u32, 0x09C4u32), (0x09CDu32, 0x09CDu32),
  (0x09E2u32, 0x09E3u32), (0x0A01u32, 0x0A02u32), (0x0A3Cu32, 0x0A3Cu32),
  (0x0A41u32, 0x0A42u32), (0x0A47u32, 0x0A48u32), (0x0A4Bu32, 0x0A4Du32),
  (0x0A70u32, 0x0A71u32), (0x0A81u32, 0x0A82u32), (0x0ABCu32, 0x0ABCu32),
  (0x0AC1u32, 0x0AC5u32), (0x0AC7u32, 0x0AC8u32), (0x0ACDu32, 0x0ACDu32),
  (0x0AE2u32, 0x0AE3u32), (0x0B01u32, 0x0B01u32), (0x0B3Cu32, 0x0B3Cu32),
  (0x0B3Fu32, 0x0B3Fu32), (0x0B41u32, 0x0B43u32), (0x0B4Du32, 0x0B4Du32),
  (0x0B56u32, 0x0B56u32), (0x0B82u32, 0x0B82u32), (0x0BC0u32, 0x0BC0u32),
  (0x0BCDu32, 0x0BCDu32), (0x0C3Eu32, 0x0C40u32), (0x0C46u32, 0x0C48u32),
  (0x0C4Au32, 0x0C4Du32), (0x0C55u32, 0x0C56u32), (0x0CBCu32, 0x0CBCu32),
  (0x0CBFu32, 0x0CBFu32), (0x0CC6u32, 0x0CC6u32), (0x0CCCu32, 0x0CCDu32),
  (0x0CE2u32, 0x0CE3u32), (0x0D41u32, 0x0D43u32), (0x0D4Du32, 0x0D4Du32),
  (0x0DCAu32, 0x0DCAu32), (0x0DD2u32, 0x0DD4u32), (0x0DD6u32, 0x0DD6u32),
  (0x0E31u32, 0x0E31u32), (0x0E34u32, 0x0E3Au32), (0x0E47u32, 0x0E4Eu32),
  (0x0EB1u32, 0x0EB1u32), (0x0EB4u32, 0x0EB9u32), (0x0EBBu32, 0x0EBCu32),
  (0x0EC8u32, 0x0ECDu32), (0x0F18u32, 0x0F19u32), (0x0F35u32, 0x0F35u32),
  (0x0F37u32, 0x0F37u32), (0x0F39u32, 0x0F39u32), (0x0F71u32, 0x0F7Eu32),
  (0x0F80u32, 0x0F84u32), (0x0F86u32, 0x0F87u32), (0x0F90u32, 0x0F97u32),
  (0x0F99u32, 0x0FBCu32), (0x0FC6u32, 0x0FC6u32), (0x102Du32, 0x1030u32),
  (0x1032u32, 0x1032u32), (0x1036u32, 0x1037u32), (0x1039u32, 0x1039u32),
  (0x1058u32, 0x1059u32), (0x1160u32, 0x11FFu32), (0x135Fu32, 0x135Fu32),
  (0x1712u32, 0x1714u32), (0x1732u32, 0x1734u32), (0x1752u32, 0x1753u32),
  (0x1772u32, 0x1773u32), (0x17B4u32, 0x17B5u32), (0x17B7u32, 0x17BDu32),
  (0x17C6u32, 0x17C6u32), (0x17C9u32, 0x17D3u32), (0x17DDu32, 0x17DDu32),
  (0x180Bu32, 0x180Du32), (0x18A9u32, 0x18A9u32), (0x1920u32, 0x1922u32),
  (0x1927u32, 0x1928u32), (0x1932u32, 0x1932u32), (0x1939u32, 0x193Bu32),
  (0x1A17u32, 0x1A18u32), (0x1B00u32, 0x1B03u32), (0x1B34u32, 0x1B34u32),
  (0x1B36u32, 0x1B3Au32), (0x1B3Cu32, 0x1B3Cu32), (0x1B42u32, 0x1B42u32),
  (0x1B6Bu32, 0x1B73u32), (0x1DC0u32, 0x1DCAu32), (0x1DFEu32, 0x1DFFu32),
  (0x200Bu32, 0x200Fu32), (0x202Au32, 0x202Eu32), (0x2060u32, 0x2063u32),
  (0x206Au32, 0x206Fu32), (0x20D0u32, 0x20EFu32), (0x302Au32, 0x302Fu32),
  (0x3099u32, 0x309Au32), (0xA806u32, 0xA806u32), (0xA80Bu32, 0xA80Bu32),
  (0xA825u32, 0xA826u32), (0xFB1Eu32, 0xFB1Eu32), (0xFE00u32, 0xFE0Fu32),
  (0xFE20u32, 0xFE23u32), (0xFEFFu32, 0xFEFFu32), (0xFFF9u32, 0xFFFBu32),
  (0x10A01u32, 0x10A03u32), (0x10A05u32, 0x10A06u32), (0x10A0Cu32, 0x10A0Fu32),
  (0x10A38u32, 0x10A3Au32), (0x10A3Fu32, 0x10A3Fu32), (0x1D167u32, 0x1D169u32),
  (0x1D173u32, 0x1D182u32), (0x1D185u32, 0x1D18Bu32), (0x1D1AAu32, 0x1D1ADu32),
  (0x1D242u32, 0x1D244u32), (0xE0001u32, 0xE0001u32), (0xE0020u32, 0xE007Fu32),
  (0xE0100u32, 0xE01EFu32)
]

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

proc main() =
  loadRanges()
  var DoubleWidthTable = makePropertyTable(DoubleWidthRanges, Combining)
  # Control chars return a width of 2, and are displayed as ^{letter}.
  for c in Controls:
    let u = ptint(c)
    let i = u div (sizeof(ptint) * 8)
    let m = u mod (sizeof(ptint) * 8)
    DoubleWidthTable[i] = DoubleWidthTable[i] or ptint(1 shl m)
  let CombiningTable = makePropertyTable(Combining)

  var dwrLen = 0
  for (ucs, mapped) in DoubleWidthRanges:
    if ucs > uint16.high: # lower ranges are added to DoubleWidthTable
      inc dwrLen
  echo "const DoubleWidthRanges: array[" & $dwrLen &
    ", tuple[ucs, mapped: uint32]] = ["
  var writer = LineWriter(s: newFileStream(stdout))
  for (ucs, mapped) in DoubleWidthRanges:
    if ucs > uint16.high: # lower ranges are added to DoubleWidthTable
      writer.write("(" & $ucs & "," & $mapped & "),")
  writer.flush()
  echo "]"
  echo ""

  echo "const DoubleWidthAmbiguousRanges: array[" &
    $DoubleWidthAmbiguousRanges.len & ", tuple[ucs, mapped: uint32]] = ["
  for (ucs, mapped) in DoubleWidthAmbiguousRanges:
    writer.write("(" & $ucs & "," & $mapped & "),")
  writer.flush()
  echo "]"
  echo ""

  var cmbLen = 0
  for (ucs, mapped) in Combining:
    if ucs > uint16.high: # lower ranges are added to CombiningTable
      inc cmbLen
  echo "const Combining: array[" & $cmbLen & ", tuple[ucs, mapped: uint32]] = ["
  for (ucs, mapped) in Combining:
    if ucs > uint16.high:
      writer.write("(" & $ucs & "," & $mapped & "),")
  writer.flush()
  echo "]"
  echo ""

  echo "const DoubleWidthTable: PropertyTable = ["
  for u in DoubleWidthTable:
    writer.write($u & "u32,")
  writer.flush()
  echo "]"
  echo ""

  echo "const CombiningTable: PropertyTable = ["
  for u in CombiningTable:
    writer.write($u & "u32,")
  writer.flush()
  echo "]"
  echo ""

main()
