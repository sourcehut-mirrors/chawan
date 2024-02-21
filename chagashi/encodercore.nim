## TextEncoder encodes valid UTF-8 (or WTF-8) byte sequences to non-UTF-8
## encodings, in accordance with the WHATWG
## [encoding standard](https://encoding.spec.whatwg.org/).
##
## This is a low-level interface; you may also be interested in
## [encoder](encoder.html), which provides useful wrapper procedures.
##
## `TextEncoder` objects have two methods: `encode` and `finish`. To encode
## a stream, sequentially call `encode` on any number of buffers, then call
## `finish`.
##
## Note that the input stream **must** be valid UTF-8, with the exception that
## (invalid) surrogate codepoints are automagically replaced with replacement
## characters. So if std/unicode's `validateUtf8` returns -1 on a buffer, it is
## safe to feed it to `TextEncoder`. Otherwise, it is not.
##
## `encode` expects an input queue `iq`, an output queue `oq`, and an index in the
## output queue `n`. Output is placed in the output queue starting from
## `n`. `encode` may either return `terDone`, `terReqOutput`, or `terError`.
##
## `terDone` means the entire input buffer has been successfully encoded; the
## output can be found in `oq`, and the number of bytes outputted is stored in
## `n`.
##
## `terReqOutput` is a request for more output space to decode the current
## buffer. Users may handle this by processing the contents of `oq` until `n`,
## resetting `n` to 0, then calling `encode` on the same input queue `iq` again.
##
## `terError` represents an error with a specific code point, as specified by
## the standard. Conformant implementations must handle this either by
## immediately aborting the encoding process (error mode "fatal"), or outputting
## a decimal representation of the code point stored in the `TextEncoder`
## object's `c` member as an HTML reference (error mode "html"). For an example,
## see [encoder](encoder.html)'s source code.
##
## After having received a `terDone` result, users may call the `finish` method
## on the `TextEncoder` object. This method has two possible results:
##
## * `tefrDone` signals that nothing else is to be done. For all encoders except
##    ISO-2022-JP, this is the only possible result.
## * `tefrOutputISO2022JPSetAscii` signals that the character sequence "\e(B"
##    (=the three bytes `0x1B`, `0x28` and `0x42`) must be written to the output
##    stream by the consumer. Only the ISO-2022-JP encoder may return this
##    value. (This sequence resets the decoder's output state to ASCII.)
##
## It is valid to re-use `TextEncoder` objects after finish has been
## called. However, it is invalid (and broken) to call `finish` without having
## received a `terDone` result from the encoder first.

import std/algorithm

import charset_map

type
  TextEncoderResult* = enum
    terDone, terReqOutput, terError

  TextEncoderFinishResult* = enum
    tefrDone, tefrOutputISO2022JPSetAscii

  ISO2022JPState = enum
    i2jsAscii, i2jsRoman, i2jsJis0208

  TextEncoder* = ref object of RootObj
    i*: int
    c*: uint32

  TextEncoderGB18030* = ref object of TextEncoder

  TextEncoderGBK* = ref object of TextEncoder

  TextEncoderBig5* = ref object of TextEncoder

  TextEncoderEUC_JP* = ref object of TextEncoder

  TextEncoderISO2022_JP* = ref object of TextEncoder
    state: ISO2022JPState

  TextEncoderShiftJIS* = ref object of TextEncoder

  TextEncoderEUC_KR* = ref object of TextEncoder

  TextEncoderXUserDefined* = ref object of TextEncoder

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
    let i = upperBound(GB18030RangesEncode, c,
      func(a: tuple[ucs, p: uint16], b: uint32): int =
        cmp(uint32(a.ucs), b)
    )
    let elem = GB18030RangesEncode[i - 1]
    offset = elem.ucs
    p = elem.p
  return p + c - offset

func searchInMap(a: openArray[UCS16x16], u: uint16): int =
  binarySearch(a, u, proc(x: UCS16x16, y: uint16): int = cmp(x[0], y))

func searchInMap(a: openArray[(uint16, char)], u: uint16): int =
  binarySearch(a, u, proc(x: (uint16, char), y: uint16): int = cmp(x[0], y))

func searchInMap(a: openArray[UCS32x16], u: uint32): int =
  binarySearch(a, u, proc(x: UCS32x16, y: uint32): int = cmp(x[0], y))

func findPair(map: openArray[UCS32x16], c: uint32): int {.inline.} =
  return searchInMap(map, c)

func findPair(map: openArray[UCS16x16], c: uint16): int {.inline.} =
  return searchInMap(map, c)

func findPair16(map: openArray[UCS16x16], c: uint32): int {.inline.} =
  if c > uint16.high:
    return -1
  return searchInMap(map, uint16(c))

func findPair16(map: openArray[tuple[ucs: uint16, val: char]], c: uint32): int
    {.inline.} =
  if c > uint16.high:
    return -1
  return searchInMap(map, uint16(c))

template try_put_byte(oq: var openArray[uint8], b: uint8, n: var int) =
  if n + 1 > oq.len:
    return terReqOutput
  oq[n] = b
  inc n

template try_put_bytes(oq: var openArray[uint8], bs: openArray[uint8],
    n: var int) =
  if n + bs.len > oq.len:
    return terReqOutput
  for i in 0 ..< bs.len:
    oq[n] = bs[i]
    inc n

# returns the consumed character's length in bytes
template try_get_utf8(te: TextEncoder, iq: openArray[uint8], b: uint8): int =
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

method encode*(te: TextEncoder, iq: openArray[uint8],
    oq: var openArray[uint8], n: var int): TextEncoderResult {.base.} =
  assert false

method finish*(te: TextEncoder): TextEncoderFinishResult {.base.} =
  tefrDone

proc encodeGB18030(te: TextEncoder, iq: openArray[uint8],
    oq: var openArray[uint8], n: var int, isGBK: bool): TextEncoderResult =
  while te.i < iq.len:
    let b = iq[te.i]
    if b < 0x80:
      oq.try_put_byte b, n
      inc te.i
      continue
    let cl = te.try_get_utf8(iq, b)
    let c = te.c
    if isGBK and c == 0x20AC:
      oq.try_put_byte 0x80, n
      te.i += cl
      continue
    if (let i = GB18030Encode.findPair16(c); i != -1):
      let p = GB18030Encode[i].p
      let lead = p div 190 + 0x81
      let trail = p mod 190
      let offset: uint8 = if trail < 0x3F: 0x40 else: 0x41
      oq.try_put_bytes [uint8(lead), uint8(trail) + offset], n
      te.i += cl
      continue
    if isGBK:
      te.i += cl
      return terError
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

method encode*(te: TextEncoderGB18030, iq: openArray[uint8],
    oq: var openArray[uint8], n: var int): TextEncoderResult =
  te.encodeGB18030(iq, oq, n, isGBK = false)

method encode*(te: TextEncoderGBK, iq: openArray[uint8],
    oq: var openArray[uint8], n: var int): TextEncoderResult =
  te.encodeGB18030(iq, oq, n, isGBK = true)

method encode*(te: TextEncoderBig5, iq: openArray[uint8],
    oq: var openArray[uint8], n: var int): TextEncoderResult =
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
      let i = Big5EncodeHigh.findPair(c)
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

method encode*(te: TextEncoderEUC_JP, iq: openArray[uint8],
    oq: var openArray[uint8], n: var int): TextEncoderResult =
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
    else:
      if c == 0x2212:
        c = 0xFF0Du32
      if (let i = Jis0208Encode.findPair16(c); i != -1):
        let p = Jis0208Encode[i].p
        let lead = p div 94 + 0xA1
        let trail = p mod 94 + 0xA1
        oq.try_put_bytes [uint8(lead), uint8(trail)], n
      else:
        te.i += cl
        return terError
    te.i += cl
  te.i = 0
  terDone

method encode*(te: TextEncoderISO2022_JP, iq: openArray[uint8],
    oq: var openArray[uint8], n: var int): TextEncoderResult =
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
      oq.try_put_bytes [0x1Bu8, 0x28u8, 0x4Au8], n
      te.state = i2jsRoman
      # prepend (no inc i)
      continue
    else:
      let c = if c == 0x2212:
        0xFF0Du32
      elif c in 0xFF61u32..0xFF9Fu32:
        uint32(ISO2022JPKatakanaMap[uint8(c - 0xFF61)])
      else:
        c
      if (let j = Jis0208Encode.findPair16(c); j != -1):
        let p = Jis0208Encode[j].p
        if te.state != i2jsJis0208:
          oq.try_put_bytes [0x1Bu8, 0x24u8, 0x42u8], n
          te.state = i2jsJis0208
          # prepend (no inc i)
          continue
        let lead = p div 94 + 0x21
        let trail = p mod 94 + 0x21
        oq.try_put_bytes [uint8(lead), uint8(trail)], n
      else: # pointer is null
        if te.state == i2jsJis0208:
          oq.try_put_bytes [0x1Bu8, 0x28u8, 0x42u8], n
          te.state = i2jsAscii
          # prepend (no inc i)
          continue
        te.i += cl
        return terError
    te.i += cl
  te.i = 0
  terDone

method finish*(te: TextEncoderISO2022_JP): TextEncoderFinishResult =
  if te.state != i2jsAscii:
    te.state = i2jsAscii
    return tefrOutputISO2022JPSetAscii
  tefrDone

method encode*(te: TextEncoderShiftJIS, iq: openArray[uint8],
    oq: var openArray[uint8], n: var int): TextEncoderResult =
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
    else:
      let c = if c == 0x2212: 0xFF0Du32 else: c
      if (let j = ShiftJISEncode.findPair16(c); j != -1):
        let p = ShiftJISEncode[j].p
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

method encode*(te: TextEncoderEUC_KR, iq: openArray[uint8],
    oq: var openArray[uint8], n: var int): TextEncoderResult =
  while te.i < iq.len:
    let b = iq[te.i]
    if b < 0x80:
      oq.try_put_byte b, n
      inc te.i
      continue
    let cl = te.try_get_utf8(iq, b)
    if (let i = EUCKREncode.findPair16(te.c); i != -1):
      let p = EUCKREncode[i].p
      let lead = p div 190 + 0x81
      let trail = p mod 190 + 0x41
      oq.try_put_bytes [uint8(lead), uint8(trail)], n
      te.i += cl
    else:
      te.i += cl
      return terError
  te.i = 0
  terDone

method encode*(te: TextEncoderXUserDefined, iq: openArray[uint8],
    oq: var openArray[uint8], n: var int): TextEncoderResult =
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

proc encode0(te: TextEncoder, iq: openArray[uint8],
    oq: var openArray[uint8], n: var int,
    map: openArray[tuple[ucs: uint16, val: char]]): TextEncoderResult =
  while te.i < iq.len:
    let b = iq[te.i]
    if b < 0x80:
      oq.try_put_byte b, n
      inc te.i
      continue
    let cl = te.try_get_utf8(iq, b)
    if (let j = map.findPair16(te.c); j != -1):
      oq.try_put_byte uint8(map[j].val) + 0x80, n
      te.i += cl
      continue
    te.i += cl
    return terError
  te.i = 0
  terDone

template makeSingleByte(name: untyped) {.dirty.} =
  type `TextEncoder name`* = ref object of TextEncoder

  method encode*(td: `TextEncoder name`, iq: openArray[uint8],
      oq: var openArray[uint8], n: var int): TextEncoderResult =
    td.encode0(iq, oq, n, `name Encode`)

makeSingleByte IBM866
makeSingleByte ISO8859_2
makeSingleByte ISO8859_3
makeSingleByte ISO8859_4
makeSingleByte ISO8859_5
makeSingleByte ISO8859_6
makeSingleByte ISO8859_7
makeSingleByte ISO8859_8
makeSingleByte ISO8859_10
makeSingleByte ISO8859_13
makeSingleByte ISO8859_14
makeSingleByte ISO8859_15
makeSingleByte ISO8859_16
makeSingleByte KOI8_R
makeSingleByte KOI8_U
makeSingleByte Macintosh
makeSingleByte Windows874
makeSingleByte Windows1250
makeSingleByte Windows1251
makeSingleByte Windows1252
makeSingleByte Windows1253
makeSingleByte Windows1254
makeSingleByte Windows1255
makeSingleByte Windows1256
makeSingleByte Windows1257
makeSingleByte Windows1258
makeSingleByte XMacCyrillic
