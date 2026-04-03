## TextEncoder encodes valid UTF-8 (or WTF-8) byte sequences to non-UTF-8
## encodings, in accordance with the WHATWG
## [encoding standard](https://encoding.spec.whatwg.org/).
##
## This is a low-level interface; you may also be interested in
## [encoder](encoder.html), which provides useful wrapper procedures.
##
## To encode a stream, sequentially call `encode` on any number of chunks
## with `finish = false`, then with `finish = true` on the last chunk.
## If you don't know which chunk is the last, use an empty chunk.
##
## (`finish` only has a significance for the ISO-2022-JP encoder, which
## is specified to emit a sequence at the end of the queue to reset the
## decoder state to ASCII.)
##
## The input stream **must** be valid UTF-8, with the exception that
## (invalid) surrogate codepoints are automagically replaced with
## replacement characters.  So if std/unicode's `validateUtf8` returns -1
## on a buffer, it is safe to feed it to `TextEncoder`.
##
## `encode` expects an input queue `iq`, an output queue `oq`, and an index
## in the output queue `n`.  Output is placed in the output queue starting
## from `n`.  `encode` may either return `terDone`, `terReqOutput`, or
## `terError`.
##
## `terDone` means the entire input buffer has been successfully encoded;
## the output can be found in `oq`, and the number of bytes output is
## stored in `n`.
##
## `terReqOutput` is a request for more output space to decode the current
## buffer.  Users may handle this by processing the contents of `oq` until
## `n`, resetting `n` to 0, then calling `encode` on the same input queue
## `iq` again.
##
## `terError` represents an error with a specific code point, as specified
## by the standard.  Per spec, implementations should handle this either
## by immediately aborting the encoding process (error mode "fatal"), or
## outputting a decimal representation of the code point stored in the
## `TextEncoder` object's `c` member as an HTML reference (error mode
## "html").  For an example, see [encoder](encoder.html)'s source code.

{.push raises: [].}

import std/algorithm

import charset
import charset_map

type
  TextEncoderResult* = enum
    terDone, terReqOutput, terError

  Iso2022JPState* = enum
    i2jsAscii, i2jsRoman, i2jsJis0208

  TextEncoder* = object
    i*: int
    c*: uint32
    charset*: Charset
    state*: Iso2022JPState

proc gb18030RangesPointer(c: uint32): uint32 =
  if c == 0xE7C7:
    return 7457
  # Let offset be the last pointer in index gb18030 ranges that is less than or
  # equal to pointer and code point offset its corresponding code point.
  var offset: uint32
  var p: uint32
  if c >= 0x10000:
    # omitted from the map for storage efficiency
    offset = 0x10000
    p = 189000
  elif c >= 0xFFE6:
    # Needed because upperBound returns the first element greater than pointer
    # OR last on failure, so we can't just remove one if p is e.g. 39400.
    offset = 0xFFE6
    p = 39394
  else:
    # Find the first range that is greater than p, or last if no such element
    # is found.
    # We want the last that is <=, so decrease index by one.
    let i = GB18030Ranges.upperBound(c, proc(a: UCS16x16; b: uint32): int =
        cmp(uint32(a.ucs), b)
    )
    let elem = GB18030Ranges[i - 1]
    offset = elem.ucs
    p = elem.p
  return p + c - offset

proc findPair(map: openArray[UCS16x16]; u: uint16): int =
  return map.binarySearch(u, proc(x: UCS16x16; y: uint16): int = cmp(x[0], y))

proc findPair16(map: openArray[UCS16x16]; u: uint32): int =
  if u > uint16.high:
    return -1
  let u = uint16(u)
  return map.binarySearch(u, proc(x: UCS16x16; y: uint16): int = cmp(x[0], y))

proc findPair16(map: openArray[UCS16x8]; u: uint32): int =
  if u > uint16.high:
    return -1
  let u = uint16(u)
  return map.binarySearch(u, proc(x: UCS16x8; y: uint16): int = cmp(x[0], y))

proc findRun(runs: openArray[uint32]; offset, ic: uint16): uint16 =
  let i = runs.upperBound(ic, proc(x: uint32; y: uint16): int =
    let op = x and 0x1FFF # this is the pointer
    let diff = (x shr 13) and 0xFFF # difference between op and the point
    let ucs = offset + op + diff # UCS
    return cmp(ucs, y)
  )
  let x = runs[i - 1]
  let op = x and 0x1FFF # this is the pointer
  let diff = (x shr 13) and 0xFFF # difference between op and the point
  let ucs = offset + op + diff # UCS
  let len = x shr 25
  if ucs <= ic and ic < ucs + len:
    return uint16(ic - offset - diff + 1)
  return 0

template try_put_byte(oq: var openArray[uint8]; b: uint8; n: var int) =
  if n >= oq.len:
    return terReqOutput
  oq[n] = b
  inc n

template try_put_bytes(oq: var openArray[uint8]; bs: openArray[uint8];
    n: var int) =
  if n + bs.len > oq.len:
    return terReqOutput
  for i in 0 ..< bs.len:
    oq[n] = bs[i]
    inc n

# returns the consumed character's length in bytes
template try_get_utf8(te: TextEncoder; iq: openArray[uint8]; b: uint8): int =
  if b shr 5 == 0x6:
    if te.i + 1 >= iq.len:
      return terReqOutput
    te.c = (uint32(b and 0x1F) shl 6) or
      (iq[te.i + 1] and 0x3F)
    2
  elif b shr 4 == 0xE:
    if te.i + 2 >= iq.len:
      return terReqOutput
    let c = (uint32(b and 0xF) shl 12) or
      (uint32(iq[te.i + 1] and 0x3F) shl 6) or
      (iq[te.i + 2] and 0x3F)
    if likely((c shr 11) != 0x1B): # valid (probably)
      te.c = c
      3
    else: # surrogate
      te.c = 0xFFFD
      1
  elif b shr 3 == 0x1E:
    if te.i + 3 >= iq.len:
      return terReqOutput
    te.c = (uint32(b and 0x7) shl 18) or
      (uint32(iq[te.i + 1] and 0x3F) shl 12) or
      (uint32(iq[te.i + 2] and 0x3F) shl 6) or
      (iq[te.i + 3] and 0x3F)
    4
  else:
    te.c = 0xFFFD # invalid
    1

proc encodeGb18030(te: var TextEncoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int; isGBK: bool): TextEncoderResult =
  while te.i < iq.len:
    let b = iq[te.i]
    if b < 0x80:
      oq.try_put_byte b, n
      inc te.i
      continue
    let cl = te.try_get_utf8(iq, b)
    let c = te.c
    const NewTable2024Part2 = [
      0xE81Eu16, 0xE826, 0xE82B, 0xE82C, 0xE832, 0xE843, 0xE854, 0xE864
    ]
    if isGBK and c == 0x20AC:
      oq.try_put_byte 0x80, n
      te.i += cl
      continue
    if c >= 0x4E02 and c <= 0x72DB and
        (let p0 = GB18030Runs.findRun(GB18030RunsOffset, uint16(c)); p0 != 0):
      let p = p0 - 1
      let lead = p div 190 + 0x81
      let trail = p mod 190
      let offset = if trail < 0x3F: 0x40u8 else: 0x41u8
      oq.try_put_bytes [uint8(lead), uint8(trail) + offset], n
    elif c >= 0x72DC and c <= 0x9F31 and
        (let p0 = GB18030Runs2.findRun(GB18030RunsOffset2, uint16(c)); p0 != 0):
      let p = p0 - 1
      let lead = p div 96 + 0xAA
      let trail = p mod 96
      let offset = if trail < 0x3F: 0x40u8 else: 0x41u8
      oq.try_put_bytes [uint8(lead), uint8(trail) + offset], n
    elif c >= 0xE78D and c <= 0xE796: # new table of 2024 part 1
      var b = c - 0xE78D + 0xD9
      if b > 0xDF:
        b += 12
      if b == 0xEE:
        b = 0xF3
      oq.try_put_bytes [0xA6u8, uint8(b)], n
    elif c <= 0xE864 and uint16(c) in NewTable2024Part2:
      var b = c - 0xE81E + 0x59
      if b > 0x7E:
        inc b
      oq.try_put_bytes [0xFEu8, uint8(b)], n
    elif (let i = GB18030Encode.findPair16(c); i != -1):
      let p = GB18030Encode[i].p
      let lead = p div 190 + 0x81
      let trail = p mod 190
      let offset = if trail < 0x3F: 0x40u8 else: 0x41u8
      oq.try_put_bytes [uint8(lead), uint8(trail) + offset], n
    elif isGBK:
      te.i += cl
      return terError
    else:
      var p = gb18030RangesPointer(c)
      let b1 = p div (10 * 126 * 10)
      p = p mod (10 * 126 * 10)
      let b2 = p div (10 * 126)
      p = p mod (10 * 126)
      let b3 = p div 10
      let b4 = p mod 10
      let b1b = uint8(b1 + 0x81)
      let b2b = uint8(b2 + 0x30)
      let b3b = uint8(b3 + 0x81)
      let b4b = uint8(b4 + 0x30)
      oq.try_put_bytes [b1b, b2b, b3b, b4b], n
    te.i += cl
  te.i = 0
  terDone

proc encodeBig5(te: var TextEncoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int): TextEncoderResult =
  while te.i < iq.len:
    let b = iq[te.i]
    if b < 0x80:
      oq.try_put_byte b, n
      inc te.i
      continue
    let cl = te.try_get_utf8(iq, b)
    let c = te.c
    let p = if c <= uint16.high:
      let i = Big5EncodeLow.findPair(uint16(c))
      if i == -1:
        te.i += cl
        return terError
      Big5EncodeLow[i].p
    else:
      let i = Big5EncodeHigh.findPair(uint16(c - 0x20000))
      if i == -1:
        te.i += cl
        return terError
      Big5EncodeHigh[i].p
    let lead = p div 157 + 0x81
    let trail = p mod 157
    let offset = if trail < 0x3F: 0x40u8 else: 0x62u8
    oq.try_put_bytes [uint8(lead), uint8(trail) + offset], n
    te.i += cl
  te.i = 0
  terDone

proc ucsToJis0208(c: uint16): uint16 =
  if (let i = Jis0208Encode.findPair16(c); i != -1):
    return Jis0208Encode[i].p + 1
  return 0

proc encodeEucJP(te: var TextEncoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int): TextEncoderResult =
  while te.i < iq.len:
    let b = iq[te.i]
    if b < 0x80:
      oq.try_put_byte b, n
      inc te.i
      continue
    let cl = te.try_get_utf8(iq, b)
    var c = te.c
    if c == 0xA5:
      oq.try_put_byte 0x5C, n
    elif c == 0x203E:
      oq.try_put_byte 0x7E, n
    elif c in 0xFF61u32..0xFF9Fu32:
      oq.try_put_bytes [0x8Eu8, uint8(c - 0xFF61 + 0xA1)], n
    elif c < uint16.high and (let p0 = ucsToJis0208(uint16(c)); p0 != 0):
      let p = p0 - 1
      let lead = p div 94 + 0xA1
      let trail = p mod 94 + 0xA1
      oq.try_put_bytes [uint8(lead), uint8(trail)], n
    else:
      te.i += cl
      return terError
    te.i += cl
  te.i = 0
  terDone

proc ucsToIso2022JP(c: uint16): uint16 =
  var c = c
  if c in 0xFF61'u32..0xFF9F'u32:
    c = uint16(Iso2022JPKatakanaMap[c - 0xFF61]) + 0x3000
  return ucsToJis0208(c)

proc encodeIso2022JP(te: var TextEncoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int; finish: bool): TextEncoderResult =
  while te.i < iq.len:
    let b = iq[te.i]
    if b < 0x80: # ASCII
      if te.state in {i2jsAscii, i2jsRoman} and b in {0x0Eu8, 0x0Fu8, 0x1Bu8}:
        te.c = 0xFFFD # note: this returns replacement intentionally
        inc te.i
        return terError
      if te.state == i2jsRoman and b notin {0x5Cu8, 0x7Eu8}:
        oq.try_put_byte b, n
        inc te.i
        continue
      if te.state == i2jsAscii:
        oq.try_put_byte b, n
        inc te.i
        continue
      oq.try_put_bytes [0x1Bu8, 0x28u8, 0x42u8], n
      te.state = i2jsAscii
      # prepend (no inc i)
      continue
    let cl = te.try_get_utf8(iq, b)
    let c = te.c
    if te.state == i2jsRoman and c == 0xA5:
      oq.try_put_byte 0x5C, n
    elif te.state == i2jsRoman and c == 0x203E:
      oq.try_put_byte 0x7E, n
    elif te.state != i2jsRoman and (c == 0xA5 or c == 0x203E):
      oq.try_put_bytes [0x1B'u8, 0x28'u8, 0x4A'u8], n
      te.state = i2jsRoman
      # prepend (no inc i)
      continue
    elif c < uint16.high and (let p0 = ucsToIso2022JP(uint16(c)); p0 != 0):
      let p = p0 - 1
      if te.state != i2jsJis0208:
        oq.try_put_bytes [0x1B'u8, 0x24'u8, 0x42'u8], n
        te.state = i2jsJis0208
        # prepend (no inc i)
        continue
      let lead = p div 94 + 0x21
      let trail = p mod 94 + 0x21
      oq.try_put_bytes [uint8(lead), uint8(trail)], n
    else: # pointer is null
      if te.state == i2jsJis0208:
        oq.try_put_bytes [0x1B'u8, 0x28'u8, 0x42'u8], n
        te.state = i2jsAscii
        # prepend (no inc i)
        continue
      te.i += cl
      return terError
    te.i += cl
  if finish and te.state != i2jsAscii:
    # reset state at end of queue
    oq.try_put_bytes [0x1B'u8, 0x28'u8, 0x42'u8], n
    te.state = i2jsAscii
  te.i = 0
  terDone

proc ucsToSJIS(c: uint16): uint16 =
  if (let i = ShiftJISEncode.findPair16(c); i != -1):
    return ShiftJISEncode[i].p + 1
  return ucsToJis0208(c)

proc encodeShiftJIS(te: var TextEncoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int): TextEncoderResult =
  while te.i < iq.len:
    let b = iq[te.i]
    if b < 0x80:
      oq.try_put_byte b, n
      inc te.i
      continue
    let cl = te.try_get_utf8(iq, b)
    let c = te.c
    if c == 0xA5:
      oq.try_put_byte 0x5C, n
    elif c == 0x203E:
      oq.try_put_byte 0x7E, n
    elif c in 0xFF61u32..0xFF9Fu32:
      oq.try_put_byte uint8(c - 0xFF61 + 0xA1), n
    elif c < uint16.high and (let p0 = ucsToSJIS(uint16(c)); p0 != 0):
      let p = p0 - 1
      let lead = uint8(p div 188)
      let lead_offset = if lead < 0x1F: 0x81u8 else: 0xC1u8
      let trail = uint8(p mod 188)
      let offset = if trail < 0x3F: 0x40u8 else: 0x41u8
      oq.try_put_bytes [lead + lead_offset, trail + offset], n
    else:
      te.i += cl
      return terError
    te.i += cl
  te.i = 0
  terDone

proc encodeEucKR(te: var TextEncoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int): TextEncoderResult =
  while te.i < iq.len:
    let b = iq[te.i]
    if b < 0x80:
      oq.try_put_byte b, n
      inc te.i
      continue
    let cl = te.try_get_utf8(iq, b)
    let c = te.c
    if c >= 0xAC02 and c <= 0xC8A4 and
        (let p0 = EucKRRuns.findRun(EucKRRunsOffset, uint16(c)); p0 != 0):
      let p = p0 - 1
      let row = p div 178
      var col = p mod 178
      if col >= 0x34:
        col += 12
      elif col >= 0x1A:
        col += 6
      let lead = row + 0x81
      let trail = col + 0x41
      oq.try_put_bytes [uint8(lead), uint8(trail)], n
    elif c >= 0xC8A5 and c <= 0xD7A3 and
        (let p0 = EucKRRuns2.findRun(EucKRRunsOffset2, uint16(c)); p0 != 0):
      let p = p0 - 1
      let row = p div 84 + 32
      var col = p mod 84
      if col >= 0x34:
        col += 12
      elif col >= 0x1A:
        col += 6
      let lead = row + 0x81
      let trail = col + 0x41
      oq.try_put_bytes [uint8(lead), uint8(trail)], n
    elif (let i = EucKREncode.findPair16(c); i != -1):
      let p = EucKREncode[i].p
      let lead = p div 190 + 0x81
      let trail = p mod 190 + 0x41
      oq.try_put_bytes [uint8(lead), uint8(trail)], n
    else:
      te.i += cl
      return terError
    te.i += cl
  te.i = 0
  terDone

proc encodeXUserDefined(te: var TextEncoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int): TextEncoderResult =
  while te.i < iq.len:
    let b = iq[te.i]
    if b < 0x80:
      oq.try_put_byte b, n
      inc te.i
      continue
    let cl = te.try_get_utf8(iq, b)
    let c = te.c
    if c in 0xF780u32..0xF7FFu32:
      oq.try_put_byte uint8(c - 0xF780 + 0x80), n
      te.i += cl
      continue
    te.i += cl
    return terError
  te.i = 0
  terDone

proc encodeSingleByte(te: var TextEncoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int; map: openArray[UCS16x8]):
    TextEncoderResult =
  while te.i < iq.len:
    let b = iq[te.i]
    if b < 0x80:
      oq.try_put_byte b, n
      inc te.i
      continue
    let cl = te.try_get_utf8(iq, b)
    if (let j = map.findPair16(te.c); j != -1):
      oq.try_put_byte map[j].p, n
      te.i += cl
      continue
    te.i += cl
    return terError
  te.i = 0
  terDone

proc encode*(te: var TextEncoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int; finish = false): TextEncoderResult =
  case te.charset
  of csUnknown, csUtf8, csUtf16le, csUtf16be, csReplacement: terError
  of csGbk: te.encodeGb18030(iq, oq, n, isGBK = true)
  of csGb18030: te.encodeGb18030(iq, oq, n, isGBK = false)
  of csBig5: te.encodeBig5(iq, oq, n)
  of csEucJP: te.encodeEucJP(iq, oq, n)
  of csIso2022JP: te.encodeIso2022JP(iq, oq, n, finish)
  of csShiftJIS: te.encodeShiftJIS(iq, oq, n)
  of csEucKR: te.encodeEucKR(iq, oq, n)
  of csXUserDefined: te.encodeXUserDefined(iq, oq, n)
  of csIbm866: te.encodeSingleByte(iq, oq, n, Ibm866Encode)
  of csIso8859_2: te.encodeSingleByte(iq, oq, n, Iso8859_2Encode)
  of csIso8859_3: te.encodeSingleByte(iq, oq, n, Iso8859_3Encode)
  of csIso8859_4: te.encodeSingleByte(iq, oq, n, Iso8859_4Encode)
  of csIso8859_5: te.encodeSingleByte(iq, oq, n, Iso8859_5Encode)
  of csIso8859_6: te.encodeSingleByte(iq, oq, n, Iso8859_6Encode)
  of csIso8859_7: te.encodeSingleByte(iq, oq, n, Iso8859_7Encode)
  of csIso8859_8, csIso8859_8i: te.encodeSingleByte(iq, oq, n, Iso8859_8Encode)
  of csIso8859_10: te.encodeSingleByte(iq, oq, n, Iso8859_10Encode)
  of csIso8859_13: te.encodeSingleByte(iq, oq, n, Iso8859_13Encode)
  of csIso8859_14: te.encodeSingleByte(iq, oq, n, Iso8859_14Encode)
  of csIso8859_15: te.encodeSingleByte(iq, oq, n, Iso8859_15Encode)
  of csIso8859_16: te.encodeSingleByte(iq, oq, n, Iso8859_16Encode)
  of csKoi8r: te.encodeSingleByte(iq, oq, n, Koi8rEncode)
  of csKoi8u: te.encodeSingleByte(iq, oq, n, Koi8uEncode)
  of csMacintosh: te.encodeSingleByte(iq, oq, n, MacintoshEncode)
  of csWindows874: te.encodeSingleByte(iq, oq, n, Windows874Encode)
  of csWindows1250: te.encodeSingleByte(iq, oq, n, Windows1250Encode)
  of csWindows1251: te.encodeSingleByte(iq, oq, n, Windows1251Encode)
  of csWindows1252: te.encodeSingleByte(iq, oq, n, Windows1252Encode)
  of csWindows1253: te.encodeSingleByte(iq, oq, n, Windows1253Encode)
  of csWindows1254: te.encodeSingleByte(iq, oq, n, Windows1254Encode)
  of csWindows1255: te.encodeSingleByte(iq, oq, n, Windows1255Encode)
  of csWindows1256: te.encodeSingleByte(iq, oq, n, Windows1256Encode)
  of csWindows1257: te.encodeSingleByte(iq, oq, n, Windows1257Encode)
  of csWindows1258: te.encodeSingleByte(iq, oq, n, Windows1258Encode)
  of csXMacCyrillic: te.encodeSingleByte(iq, oq, n, XMacCyrillicEncode)

{.pop.}
