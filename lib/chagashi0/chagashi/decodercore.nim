## TextDecoder decodes non-UTF-8 byte sequences to valid UTF-8, in accordance
## with the WHATWG [encoding standard](https://encoding.spec.whatwg.org/)
##
## This is a low-level interface; you may also be interested in
## [decoder](decoder.html), which provides high-level wrapper procedures.
##
## Each TextDecoder has two methods: `decode`, and `finish`. To decode an input
## stream, call `decode` on any number of input buffers, then call `finish`.
##
## Each decode call may return a tdrDone, tdrReqOutput, or tdrError result.
## It takes input from `iq` (input queue), and places it in `oq` (output queue).
## The parameter `n` is always set to the last byte *written* to, in the output
## queue.
##
## `tdrReqOutput` signals that the output queue was too small to fit output of
## the decoder. You should call `decode` with the same `TextDecoder` on the same
## input buffer again, but with a larger output buffer.
##
## At this point, the internal variable `i` points to the last input byte
## consumed; bytes before that may be safely discarded, provided you adjust `i`
## accordingly (subtracting the removed input bytes).
##
## `tdrReadInput` instructs the consumer to read the input queue between the
## bytes `pi..<ri` (exclusive) as decoded output.
##
## WARNING: this does not mean that `oq` is left unmodified. In particular, in
## the UTF-8 decoder, if the previous `iq` ended with a split up UTF-8
## character, then the next pass fills `oq` with its remains before it would
## return tdrReadInput. Make sure to process `oq` to `n` before you process
## `iq`.
##
## `tdrError` is returned for *all* decoding errors encountered. For compliance
## with the encoding standard, callers must either abort decoding the input
## stream (error mode "fatal"), or manually append a `U+FFFD` replacement
## character (error mode "replacement").
##
## `tdrDone` is returned after decoding of the entire buffer has finished. At
## this point, the caller has two options:
##
## * Call the decoder again on the next buffer. (`i` is reset to 0
##   automatically, so there's no need to do anything before the next call.)
## * Call finish; the decoder will perform the appropriate steps for receiving
##   "end-of-queue". It may return tdrDone or tdrError.
##
## The `finish` call resets all decoder state, so it is possible to re-use
## TextDecoder objects. It is however incorrect to call `finish` unless the last
## `decode` call has returned `tdrDone`.

{.push raises: [].}

import std/algorithm

import charset_map

type
  TextDecoderResult* = enum
    tdrDone, tdrReadInput, tdrReqOutput, tdrError

  TextDecoderFinishResult* = enum
    tdfrDone, tdfrError

  ISO2022JPState = enum
    i2jsAscii, i2jsRoman, i2jsKatakana, i2jsLeadByte, i2jsTrailByte,
    i2jsEscapeStart, i2jsEscape

  TextDecoder* = ref object of RootObj
    i*: int
    ri*: int
    pi*: int

  TextDecoderUTF8* = ref object of TextDecoder
    bounds: Slice[uint8]
    flag: TextDecoderResult
    buf: array[3, uint8]
    seen: uint8
    needed: uint8
    bufLen: uint8
    ppi: int

  TextDecoderGB18030* = ref object of TextDecoder
    buf: uint8
    hasbuf: bool
    first: uint8
    second: uint8
    third: uint8

  TextDecoderBig5* = ref object of TextDecoder
    lead: uint8

  TextDecoderEUC_JP* = ref object of TextDecoder
    lead: uint8
    jis0212: bool

  TextDecoderISO2022_JP* = ref object of TextDecoder
    buf: uint8
    lead: uint8
    output: bool
    hasbuf: bool
    state: ISO2022JPState
    outputstate: ISO2022JPState

  TextDecoderShiftJIS* = ref object of TextDecoder
    lead: uint8

  TextDecoderEUC_KR* = ref object of TextDecoder
    lead: uint8

  TextDecoderUTF16_BE* = ref object of TextDecoder
    lead: uint8
    surr: uint16
    haslead: bool
    hassurr: bool

  TextDecoderUTF16_LE* = ref object of TextDecoder
    lead: uint8
    surr: uint16
    haslead: bool
    hassurr: bool

  TextDecoderXUserDefined* = ref object of TextDecoder

  TextDecoderReplacement* = ref object of TextDecoder
    reported: bool

# All decoders must take care of two things:
# * Put all state changes *before* returning with tdrError. (For obvious
#   reasons :) You can't change anything after returning from the method.
# * Put all state changes *after* `try_put_*' templates. This is particularly
#   important because the templates might return early requesting more place for
#   the output; instead of using an internal buffer, in this case we simply
#   repeat the computation on the previous state in the next call (after
#   receiving more place.)

method decode*(td: TextDecoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int): TextDecoderResult {.base.} =
  assert false
  tdrDone

method finish*(td: TextDecoder): TextDecoderFinishResult {.base.} =
  tdfrDone

template try_put_utf8(oq: var openArray[uint8]; c: uint32; n: var int) =
  if c < 0x80:
    if n >= oq.len:
      return tdrReqOutput
    oq[n] = uint8(c)
    inc n
  elif c < 0x800:
    if n + 1 >= oq.len:
      return tdrReqOutput
    oq[n] = uint8(c shr 6 or 0xC0)
    inc n
    oq[n] = uint8(c and 0x3F or 0x80)
    inc n
  elif c < 0x10000:
    if n + 2 >= oq.len:
      return tdrReqOutput
    oq[n] = uint8(c shr 12 or 0xE0)
    inc n
    oq[n] = uint8(c shr 6 and 0x3F or 0x80)
    inc n
    oq[n] = uint8(c and 0x3F or 0x80)
    inc n
  else:
    assert c <= 0x10FFFF
    if n + 3 >= oq.len:
      return tdrReqOutput
    oq[n] = uint8(c shr 18 or 0xF0)
    inc n
    oq[n] = uint8(c shr 12 and 0x3F or 0x80)
    inc n
    oq[n] = uint8(c shr 6 and 0x3F or 0x80)
    inc n
    oq[n] = uint8(c and 0x3F or 0x80)
    inc n

template try_put_byte(oq: var openArray[uint8]; b: uint8; n: var int) =
  if n >= oq.len:
    return tdrReqOutput
  oq[n] = b
  inc n

template try_put_str(oq: var openArray[uint8]; s: static string; n: var int) =
  if n + s.len > oq.len:
    return tdrReqOutput
  for c in s:
    oq[n] = uint8(c)
    inc n

proc gb18030RangesCodepoint(p: uint32): uint32 =
  if p > 39419 and p < 189000 or p > 1237575:
    return high(uint32) # null
  if p == 7457:
    return 0xE7C7
  # Let offset be the last pointer in index gb18030 ranges that is less than or
  # equal to pointer and code point offset its corresponding code point.
  var offset: uint32
  var c: uint32
  if p >= 189000:
    # omitted from the map for storage efficiency
    offset = 189000
    c = 0x10000
  elif p >= 39394:
    # Needed because upperBound returns the first element greater than pointer
    # OR last on failure, so we can't just subtract one if p is e.g. 39400.
    offset = 39394
    c = 0xFFE6
  else:
    # Find the first range that is greater than p, or last if no such element
    # is found.
    # We want the last that is <=, so decrease index by one.
    let i = GB18030Ranges.upperBound(p, proc(a: UCS16x16; b: uint32): int =
        cmp(uint32(a.p), b)
    )
    let elem = GB18030Ranges[i - 1]
    offset = elem.p
    c = elem.ucs
  c + p - offset

method decode*(td: TextDecoderUTF8; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int): TextDecoderResult =
  var bounds = td.bounds
  var flag = td.flag
  var i = td.i
  var ri = td.ri
  var needed = td.needed
  var seen = td.seen
  var bufLen = td.bufLen
  let obuf = td.buf
  var buf = obuf
  let ppi = td.ppi
  if flag == tdrDone:
    while i < iq.len:
      let b = iq[i]
      let ni = i + 1
      if needed == 0:
        if b <= 0x7F:
          ri = ni
        else:
          bounds = 0x80u8 .. 0xBFu8
          case b
          of 0xC2u8 .. 0xDFu8:
            needed = 1
          of 0xE0u8 .. 0xEFu8:
            if b == 0xE0: bounds.a = 0xA0
            elif b == 0xED: bounds.b = 0x9F
            needed = 2
          of 0xF0u8 .. 0xF4u8:
            if b == 0xF0: bounds.a = 0x90
            elif b == 0xF4: bounds.b = 0x8F
            needed = 3
          else:
            # needs consume
            needed = 1
            bounds = 1u8 .. 0u8
          buf[0] = b
      else:
        if b notin bounds:
          needed = 0
          seen = 0
          bounds = 0x80u8 .. 0xBFu8
          # prepend, no consume
          flag = tdrError
          break
        inc seen
        if seen == needed:
          needed = 0
          seen = 0
          ri = ni
        else:
          buf[seen] = b
        bounds = 0x80u8 .. 0xBFu8
      i = ni
  td.bounds = bounds
  td.ri = ri
  td.i = i
  td.needed = needed
  td.seen = seen
  td.bufLen = bufLen
  if bufLen > 0 and ppi == 0 and ri != 0:
    let L = int(bufLen)
    if L > oq.len:
      return tdrReqOutput
    for i in 0 ..< L:
      oq[n] = obuf[i]
      inc n
  if ppi < ri:
    td.bufLen = seen
    td.ppi = i
    td.pi = ppi
    td.flag = flag
    td.buf = buf
    return tdrReadInput
  td.flag = tdrDone
  case flag
  of tdrError:
    td.bufLen = 0
    td.ppi = i
    td.pi = ppi
  of tdrDone:
    if needed > 0:
      td.buf = buf
      bufLen = seen + 1
    td.bufLen = bufLen
    td.ri = 0
    td.i = 0
    td.ppi = 0
  else: discard # unreachable
  flag

method finish*(td: TextDecoderUTF8): TextDecoderFinishResult =
  result = tdfrDone
  if td.needed != 0:
    result = tdfrError
  td.needed = 0
  td.seen = 0
  td.i = 0
  td.pi = 0
  td.ri = 0
  td.ppi = 0
  td.bufLen = 0
  td.bounds = 0x80u8 .. 0xBFu8

proc findInRuns(runs: openArray[uint32]; offset, p: uint16): uint16 =
  let i = runs.upperBound(p, proc(x: uint32; y: uint16): int =
    let x = x and 0x1FFF # mask off first 13 bits; this is the pointer
    return cmp(x, y)
  )
  let u = runs[i - 1]
  var op = uint16(u and 0x1FFF)
  let len = u shr 25
  if p < op + len:
    let diff = uint16((u shr 13) and 0xFFF) # UCS - pointer - offset
    return offset + p + diff
  return 0

proc gb18030ToU16(row, col: uint16): uint16 =
  if row <= 0x1F:
    let p = row * 190 + col
    return GB18030Runs.findInRuns(GB18030RunsOffset, p)
  if row <= 0x26:
    if col <= 0x5F:
      # PUA section
      if row == 0x22 and col == 0x5F:
        # 6555 ideographic space
        return 0x3000
      return 0xE4C6 + (row - 0x20) * 96 + col
    let p = (row - 0x20) * 190 + col - (row - 0x1F) * 96
    return GB18030Decode[p]
  if row <= 0x28:
    let p = (row - 0x20) * 190 + col - 7 * 96
    return GB18030Decode[p]
  if row <= 0x7B:
    if col <= 0x5F:
      let p = (row - 0x29) * 0x60 + col
      return GB18030Runs2.findInRuns(GB18030RunsOffset2, p)
    let p = (row - 0x20) * 190 + col - 7 * 96 - (row - 0x28) * 96
    return GB18030Decode[p]
  let p = (row - 0x20) * 190 + col - 7 * 96 - 83 * 96
  if p < GB18030Decode.len:
    return GB18030Decode[p]
  return 0

method decode*(td: TextDecoderGB18030; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int): TextDecoderResult =
  while (let i = td.i; i < iq.len or td.hasbuf):
    template consume =
      if td.hasbuf:
        td.hasbuf = false
      else:
        inc td.i
    let b = if td.hasbuf:
      td.buf
    else:
      iq[i]
    if b < 0x80 and td.first == 0 and td.second == 0 and td.third == 0:
      oq.try_put_byte b, n
      consume
      continue
    if td.third != 0:
      if b notin 0x30u8 .. 0x39u8:
        td.hasbuf = true
        td.buf = td.second
        td.first = td.third
        td.second = 0
        td.third = 0
        # prepend (no inc i)
        return tdrError
      let p = ((uint32(td.first) - 0x81) * 10 * 126 * 10) +
              ((uint32(td.second) - 0x30) * (10 * 126)) +
              ((uint32(td.third) - 0x81) * 10) + uint32(b) - 0x30
      let c = gb18030RangesCodepoint(p)
      if c == high(uint32): # null
        td.first = 0
        td.second = 0
        td.third = 0
        consume
        return tdrError
      else:
        oq.try_put_utf8 c, n
        td.first = 0
        td.second = 0
        td.third = 0
    elif td.second != 0:
      if b in 0x81u8 .. 0xFEu8:
        td.third = b
      else:
        td.hasbuf = true
        td.buf = td.second
        td.first = 0
        td.second = 0
        td.third = 0
        return tdrError
    elif td.first != 0:
      if b in 0x30u8 .. 0x39u8:
        td.second = b
      else:
        if b in {0x40u8..0x7Eu8, 0x80..0xFE}:
          let offset = if b < 0x7F: 0x40u16 else: 0x41u16
          let row = (uint16(td.first) - 0x81)
          let col = (uint16(b) - offset)
          if (let c = gb18030ToU16(row, col); c != 0):
            oq.try_put_utf8 c, n
            td.first = 0
            consume
            continue
        td.first = 0
        if b < 0x80:
          continue # prepend (no inc i)
        else:
          consume
          return tdrError
    elif b == 0x80:
      oq.try_put_str "\u20AC", n
    elif b in 0x81u8 .. 0xFEu8:
      td.first = b
    else:
      consume
      return tdrError
    consume
  td.i = 0
  tdrDone

method finish*(td: TextDecoderGB18030): TextDecoderFinishResult =
  result = tdfrDone
  if td.first != 0 or td.second != 0 or td.third != 0:
    result = tdfrError
  assert not td.hasbuf
  td.first = 0
  td.second = 0
  td.third = 0

method decode*(td: TextDecoderBig5; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int): TextDecoderResult =
  while (let i = td.i; i < iq.len):
    let b = iq[i]
    if b < 0x80 and td.lead == 0:
      oq.try_put_byte b, n
      inc td.i
      continue
    if td.lead != 0:
      let offset = if b < 0x7F: 0x40u16 else: 0x62u16
      if b in {0x40u8..0x7Eu8, 0xA1u8..0xFEu8}:
        let p = (uint16(td.lead) - 0x81) * 157 + (uint16(b) - offset)
        block no_continue:
          case p
          of 1133: oq.try_put_str "\u00CA\u0304", n
          of 1135: oq.try_put_str "\u00CA\u030C", n
          of 1164: oq.try_put_str "\u00EA\u0304", n
          of 1166: oq.try_put_str "\u00EA\u030C", n
          else: break no_continue
          td.lead = 0
          inc td.i
          continue
        if p >= Big5DecodeOffset and p < Big5Decode.len + Big5DecodeOffset:
          var c = uint32(Big5Decode[p - Big5DecodeOffset])
          if c == 1:
            # must linear search as it's sorted by ucs
            for (ucs, itp) in Big5EncodeHigh:
              if p == itp:
                c = uint32(ucs) + 0x20000
                break
          if c != 0:
            oq.try_put_utf8 c, n
            td.lead = 0
            inc td.i
            continue
      td.lead = 0
      if b >= 0x80: # prepend if ASCII (only inc if 8th bit of b is set)
        inc td.i
      return tdrError
    elif b in 0x81u8 .. 0xFEu8:
      td.lead = b
    else:
      inc td.i
      return tdrError
    inc td.i
  td.i = 0
  tdrDone

method finish*(td: TextDecoderBig5): TextDecoderFinishResult =
  result = tdfrDone
  if td.lead != 0:
    result = tdfrError
  td.lead = 0

proc jis0212ToU16(row, col: uint16): uint16 =
  let p = row * 94 + col
  if p < Jis0212Decode.len:
    return Jis0212Decode[p]
  return 0

proc jis0208ToU16(row, col: uint16): uint16 =
  var row = row
  if row >= 0x5C:
    if row <= 0x71:
      return 0
    row -= 32
  elif row >= 0x54:
    if row <= 0x57:
      return 0
    row -= 10
  elif row >= 0xD:
    if row <= 0xE:
      return 0
    row -= 6
  elif row >= 0x8:
    if row <= 0xB:
      return 0
    row -= 4
  let p = row * 94 + col
  if p < Jis0208Decode.len:
    return Jis0208Decode[p]
  return 0

method decode*(td: TextDecoderEUC_JP; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int): TextDecoderResult =
  while (let i = td.i; i < iq.len):
    let b = iq[i]
    if b < 0x80 and td.lead == 0:
      oq.try_put_byte b, n
      inc td.i
      continue
    if td.lead == 0x8E and b in 0xA1u8 .. 0xDFu8:
      oq.try_put_utf8 b, n
      td.lead = 0
    elif td.lead == 0x8F and b in 0xA1u8 .. 0xFEu8:
      td.jis0212 = true
      td.lead = b
    elif td.lead != 0:
      if td.lead in 0xA1u8 .. 0xFEu8 and b in 0xA1u8 .. 0xFEu8:
        let row = (uint16(td.lead) - 0xA1)
        let col = uint16(b) - 0xA1
        let c = if td.jis0212:
          jis0212ToU16(row, col)
        else:
          jis0208ToU16(row, col)
        if c != 0:
          oq.try_put_utf8 c, n
          td.jis0212 = false
          td.lead = 0
          inc td.i
          continue
        td.jis0212 = false
      td.lead = 0
      inc td.i
      return tdrError
    elif b in {0x8Eu8, 0x8Fu8, 0xA1u8 .. 0xFEu8}:
      td.lead = b
    else:
      inc td.i
      return tdrError
    inc td.i
  td.i = 0
  tdrDone

method finish*(td: TextDecoderEUC_JP): TextDecoderFinishResult =
  result = tdfrDone
  if td.lead != 0:
    result = tdfrError
  td.lead = 0
  td.jis0212 = false

method decode*(td: TextDecoderISO2022_JP; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int): TextDecoderResult =
  while (let i = td.i; i < iq.len or td.hasbuf):
    template consume =
      if td.hasbuf:
        td.hasbuf = false
      else:
        inc td.i
    let b = if td.hasbuf:
      td.buf
    else:
      iq[i]
    case td.state
    of i2jsAscii:
      case b
      of 0x1B:
        td.state = i2jsEscapeStart
      of {0x00u8..0x7Fu8} - {0x0Eu8, 0x0Fu8, 0x1Bu8}:
        oq.try_put_byte b, n
        td.output = false
      else:
        td.output = false
        consume
        return tdrError
    of i2jsRoman:
      case b
      of 0x1B: td.state = i2jsEscapeStart
      of 0x5C:
        oq.try_put_str "\u00A5", n # yen
        td.output = false
      of 0x7E:
        oq.try_put_str "\u203E", n # overline
        td.output = false
      of {0x00u8..0x7Fu8} - {0x0Eu8, 0x0Fu8, 0x1Bu8, 0x5Cu8, 0x7Eu8}:
        oq.try_put_byte b, n
        td.output = false
      else:
        td.output = false
        consume
        return tdrError
    of i2jsKatakana:
      case b
      of 0x1B: td.state = i2jsEscapeStart
      of 0x21u8..0x5Fu8:
        oq.try_put_utf8 0xFF61u16 - 0x21 + uint16(b), n
        td.output = false
      else:
        td.output = false
        consume
        return tdrError
    of i2jsLeadByte:
      case b
      of 0x1B: td.state = i2jsEscapeStart
      of 0x21u8..0x7Eu8:
        td.output = false
        td.lead = b
        td.state = i2jsTrailByte
      else:
        td.output = false
        consume
        return tdrError
    of i2jsTrailByte:
      case b
      of 0x1B:
        td.state = i2jsEscapeStart
        consume
        return tdrError
      of 0x21u8..0x7Eu8:
        let row = (uint16(td.lead) - 0x21)
        let col = uint16(b) - 0x21
        if (let c = jis0208ToU16(row, col); c != 0):
          oq.try_put_utf8 c, n
          td.state = i2jsLeadByte
        else:
          td.state = i2jsLeadByte
          consume
          return tdrError
      else:
        td.state = i2jsLeadByte
        consume
        return tdrError
    of i2jsEscapeStart:
      if b == 0x24 or b == 0x28:
        td.lead = b
        td.state = i2jsEscape
      else:
        td.output = false
        td.state = td.outputstate
        # prepend (no inc i)
        return tdrError
    of i2jsEscape:
      let l = td.lead
      td.lead = 0 # this is ok; we don't put anything in this state.
      var isstatenull = false
      var s: ISO2022JPState
      if l == 0x28:
        case b
        of 0x42: s = i2jsAscii
        of 0x4A: s = i2jsRoman
        of 0x49: s = i2jsKatakana
        else: isstatenull = true
      elif l == 0x24 and b in {0x40u8, 0x42u8}:
        s = i2jsLeadByte
      else: isstatenull = true
      if not isstatenull:
        td.state = s
        td.outputstate = s
        if td.output:
          consume
          return tdrError
        td.output = true
        consume
        continue
      td.output = false
      td.state = td.outputstate
      td.hasbuf = true
      td.buf = l
      # prepend (no inc i)
      return tdrError
    consume
  td.i = 0
  tdrDone

method finish*(td: TextDecoderISO2022_JP): TextDecoderFinishResult =
  result = tdfrDone
  if td.state in {i2jsTrailByte, i2jsEscapeStart, i2jsEscape}:
    result = tdfrError
  assert not td.hasbuf
  td.lead = 0
  td.output = false
  td.state = i2jsAscii
  td.outputstate = i2jsAscii

method decode*(td: TextDecoderShiftJIS; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int): TextDecoderResult =
  while (let i = td.i; i < iq.len):
    let b = iq[i]
    if b < 0x80 and td.lead == 0: # ASCII
      oq.try_put_byte b, n
      inc td.i
      continue
    if td.lead != 0:
      let offset = if b < 0x7Fu8: 0x40u16 else: 0x41u16
      let leadoffset = if td.lead < 0xA0: 0x81u16 else: 0xC1u16
      if b in 0x40u8..0x7Eu8 or b in 0x80u8..0xFCu8:
        var row = (uint16(td.lead) - leadoffset) * 2
        var col = uint16(b) - offset
        if col >= 94:
          col -= 94
          inc row
        if 0x5E <= row and row < 0x72:
          oq.try_put_utf8 0xE000 - 8836 + row * 94 + col, n
          td.lead = 0
          inc td.i
          continue
        elif (let c = jis0208ToU16(row, col); c != 0):
          oq.try_put_utf8 c, n
          td.lead = 0
        else:
          td.lead = 0
          if b >= 0x80: # prepend if ASCII (only inc if 8th bit of b is set)
            inc td.i
          return tdrError
      else:
        td.lead = 0
        if b >= 0x80: # prepend if ASCII (only inc if 8th bit of b is set)
          inc td.i
        return tdrError
    elif b == 0x80: # not ASCII, but treat it the same
      oq.try_put_str "\u80", n
    elif b in 0xA1u8..0xDFu8:
      oq.try_put_utf8 0xFF61u16 - 0xA1 + uint16(b), n
    elif b in {0x81..0x9F} + {0xE0..0xFC}:
      td.lead = b
    else:
      inc td.i
      return tdrError
    inc td.i
  td.i = 0
  tdrDone

method finish*(td: TextDecoderShiftJIS): TextDecoderFinishResult =
  result = tdfrDone
  if td.lead != 0:
    result = tdfrError
  td.lead = 0

proc eucKRToU16(row, col: uint16): uint16 =
  var col = col
  var row = row
  if row <= 0x1F: # runs 1
    # Skip empty columns 0x1A..0x1F and 0x3A..0x3F
    if col >= 0x3A:
      if col <= 0x3F:
        return 0
      col -= 12
    elif col >= 0x1A:
      if col <= 0x1F:
        return 0
      col -= 6
    let p = row * 178 + col
    return EUCKRRuns.findInRuns(EUCKRRunsOffset, p)
  row -= 0x20
  if col < 0x60: # runs 2
    # Skip empty columns 0x1A..0x1F and 0x3A..0x3F
    if col >= 0x3A:
      if col <= 0x3F:
        return 0
      col -= 12
    elif col >= 0x1A:
      if col <= 0x1F:
        return 0
      col -= 6
    let p = row * 0x54 + col
    return EUCKRRuns2.findInRuns(EUCKRRunsOffset2, p)
  # bottom right quadrant
  col -= 0x60
  let p = row * 94 + col
  if p < EUCKRDecode.len:
    return EUCKRDecode[p]
  return 0

method decode*(td: TextDecoderEUC_KR; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int): TextDecoderResult =
  while (let i = td.i; i < iq.len):
    let b = iq[i]
    if td.lead == 0 and b < 0x80:
      oq.try_put_utf8 b, n
      inc td.i
      continue
    if td.lead != 0:
      if b in 0x41u8..0xFEu8:
        let col = (uint16(b) - 0x41)
        let row = (uint16(td.lead) - 0x81)
        if (let c = eucKRToU16(row, col); c != 0):
          oq.try_put_utf8 c, n
          inc td.i
          td.lead = 0
          continue
      td.lead = 0
      if b >= 0x80: # prepend on ASCII
        inc td.i
      return tdrError
    elif b in {0x81u8..0xFEu8}:
      td.lead = b
      inc td.i
    else:
      inc td.i
      return tdrError
  td.i = 0
  tdrDone

method finish*(td: TextDecoderEUC_KR): TextDecoderFinishResult =
  result = tdfrDone
  if td.lead != 0:
    result = tdfrError
  td.lead = 0

proc decode0(td: TextDecoderUTF16_BE|TextDecoderUTF16_LE; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int; be: bool): TextDecoderResult =
  let shiftLead = uint16(be) * 8
  let shiftTrail = uint16(not be) * 8
  while (let i = td.i; i < iq.len):
    if not td.haslead:
      td.haslead = true
      td.lead = iq[i]
      inc td.i
      continue
    let cu = (uint16(td.lead) shl shiftLead) + uint16(iq[i]) shl shiftTrail
    if td.hassurr:
      if unlikely(cu notin 0xDC00u16 .. 0xDFFFu16):
        td.haslead = true # prepend the last two bytes
        td.hassurr = false
        return tdrError
      let c = 0x10000 + ((uint32(td.surr) - 0xD800) shl 10) +
        (uint32(cu) - 0xDC00)
      oq.try_put_utf8 c, n
      td.hassurr = false
      td.haslead = false
      inc td.i
      continue
    if cu in 0xD800u16 .. 0xDBFFu16:
      td.surr = cu
      td.hassurr = true
      td.haslead = false
      inc td.i
      continue
    if unlikely(cu in 0xDC00u16 .. 0xDFFFu16):
      inc td.i
      td.haslead = false
      return tdrError
    oq.try_put_utf8 uint32(cu), n
    td.haslead = false
    inc td.i
  td.i = 0
  tdrDone

method decode*(td: TextDecoderUTF16_BE; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int): TextDecoderResult =
  td.decode0(iq, oq, n, be = true)

method finish*(td: TextDecoderUTF16_BE): TextDecoderFinishResult =
  result = tdfrDone
  if td.haslead or td.hassurr:
    result = tdfrError
  td.haslead = false
  td.hassurr = false

method decode*(td: TextDecoderUTF16_LE; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int): TextDecoderResult =
  td.decode0(iq, oq, n, be = false)

method finish*(td: TextDecoderUTF16_LE): TextDecoderFinishResult =
  result = tdfrDone
  if td.haslead or td.hassurr:
    result = tdfrError
  td.haslead = false
  td.hassurr = false

method decode*(td: TextDecoderXUserDefined; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int): TextDecoderResult =
  while (let i = td.i; i < iq.len):
    let b = iq[i]
    if b < 0x80:
      oq.try_put_byte b, n
    else:
      oq.try_put_utf8 0xF780 + uint32(b) - 0x80, n
    inc td.i
  td.i = 0
  tdrDone

proc decode0(td: TextDecoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int; map: openArray[uint16]):
    TextDecoderResult =
  while (let i = td.i; i < iq.len):
    let b = iq[i]
    if b < 0x80:
      oq.try_put_byte b, n
    elif int(b) - 0x80 < map.len:
      let p = map[int(b) - 0x80]
      if p == 0:
        inc td.i
        return tdrError
      oq.try_put_utf8 uint32(p), n
    else:
      inc td.i
      return tdrError
    inc td.i
  td.i = 0
  tdrDone

template makeSingleByte(name: untyped) {.dirty.} =
  type `TextDecoder name`* = ref object of TextDecoder

  method decode*(td: `TextDecoder name`; iq: openArray[uint8];
      oq: var openArray[uint8]; n: var int): TextDecoderResult =
    td.decode0(iq, oq, n, `name Decode`)

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

method decode*(td: TextDecoderReplacement; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int): TextDecoderResult =
  if not td.reported:
    td.reported = true
    return tdrError
  tdrDone

{.pop.}
