## `TextDecoder` decodes non-UTF-8 byte sequences to valid UTF-8, in
## accordance with WHATWG's [encoding standard](https://encoding.spec.whatwg.org/).
##
## This is a low-level interface; you may also be interested in
## [decoder](decoder.html), which provides equally efficient high-level
## wrapper procedures.
##
## The implementation consists of a single procedure: `decode`, which
## dispatches on the charset field to pick the desired decoder.  To decode
## an input stream, call `decode` on any number of chunks with `finish =
## false`, then with `finish = true` on the last chunk.  (If you don't know
## which is the last chunk, just use an empty chunk at the end.)
##
## Each decode call may return a tdrDone, tdrReqOutput, or tdrError result.
## It takes input from `iq` (input queue), and places it in `oq` (output
## queue).  The parameter `n` is always set to the last byte *written* to
## in the output queue.
##
## `tdrReqOutput` signals that the output queue was too small to fit output
## of the decoder.  The consumer should provide more space, e.g. by
## copying contents of the output queue elsewhere and resetting `n`, or by
## growing the output queue in size.
##
## At this point, the internal variable `i` points to the last input byte
## consumed; bytes before that may be safely discarded, provided you adjust
## `i` accordingly (subtracting the removed input bytes).
##
## `tdrReadInput` instructs the consumer to read the input queue between the
## bytes `pi..<ri` (exclusive) as decoded output.  WARNING: this does not
## mean that `oq` is left unmodified.
##
## In particular, in the UTF-8 decoder, if the previous `iq` ended with a
## split up UTF-8 character, then the next pass fills `oq` with its remains
## before it would return `tdrReadInput`.  Make sure to process `oq` to `n`
## before you process `iq`.
##
## `tdrError` is returned for *all* decoding errors encountered.
## For compliance with the encoding standard, callers must either abort
## decoding the input stream (error mode "fatal"), or manually append a
## `U+FFFD` replacement character (error mode "replacement").
##
## Note that even if `finish` is true, decoding of the chunk is *not
## complete* after receiving `tdrError` if you're using error mode
## "replacement".
##
## `tdrDone` is returned once decoding of `iq` has finished.  If `finish`
## was set to true, it can be assumed that decoding is complete; otherwise,
## you should call `decode` again on the next buffer.  (`i` is reset to 0
## automatically, so there's no need to do anything before the next call.)
##
## Using TextDecoder objects after setting `finish = true` is valid, but
## not well tested, so it is recommended that you reset your decoder after
## the last chunk.

{.push raises: [].}

import std/algorithm
import std/bitops

import charset
import charset_map

type
  TextDecoderResult* = enum
    tdrDone, tdrReadInput, tdrReqOutput, tdrError

  TextDecoderFinishResult* = enum
    tdfrDone, tdfrError

  TextDecoder* = object
    i*: int
    ri*: int #TODO could be removed with some effort
    pi*: int
    charset*: Charset
    # note: in UTF-8, `lead' is repurposed as `needed'
    lead: uint8 # Big5, Shift_JIS, EUC-KR, EUC-JP, ISO-2022-JP, UTF-16
    bounds: uint8 # UTF-8
    flag: TextDecoderResult # UTF-8
    # UTF-8: buffer storing at most 3 bytes on chunk boundaries
    # UTF-16: surrogate at lower 2 bytes, then a flag for whether we've
    #         already read a lead byte
    # replacement: bool for whether we've already returned error
    # EUC-JP: bool for whether the next character uses the JIS X 0212 table
    # GB18030: four bytes: a buffer to emit after error, then three bytes
    #          for a pointer into the table
    # ISO-2022-JP: lowest byte is a char buffer (or 0), second byte is
    #              output flag, third byte is state, fourth byte is output
    #              state
    buf: uint32

# All decoders must take care of two things:
# * Put all state changes *before* returning with tdrError - for obvious
#   reasons :)  You can't change anything after returning from the proc.
# * Put all state changes *after* `try_put_*' templates.  This is important
#   because the templates might return early requesting more place for the
#   output; instead of using an internal buffer, in this case we simply
#   repeat the computation on the previous state in the next call (after
#   receiving more place.)

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

# UTF-8 table:
# 00..7F: ASCII
# 80..BF: continuation byte
# C0..C1: bad, consume 1
# C2..DF: good, consume 1
# E0    : good, consume 2 with first >= A0
# E1..EC: good, consume 2
# ED    : good, consume 2 with first < A0
# EE..EF: good, consume 2
# F0    : good, consume 3 with first >= 90
# F1..F3: good, consume 3
# F4    : good, consume 3 with first < 90
# F5..FF: bad, consume 1
const
  u8tConsume1 = 1'u8 shl 0 # consume1 + consume2 = needed
  u8tConsume2 = 1'u8 shl 1
  u8tCont = 1'u8 shl 2
  u8tBounds0 = 1'u8 shl 3
  u8tBounds1 = 1'u8 shl 4
  u8tBounds2 = 1'u8 shl 5
  u8tBadLead = 1'u8 shl 7

  u8tConsume3 = u8tConsume1 or u8tConsume2
  u8tLt90 = u8tBounds0 # c < 90
  u8tGe90 = u8tBounds1 # c >= 90
  u8tGeA0 = u8tBounds2 # c >= A0
  u8tLtA0 = u8tBounds0 or u8tBounds1 # c < A0
  # unused = u8tBounds0 or u8tBounds2

  u8tBoundsMask = u8tBounds0 or u8tBounds1 or u8tBounds2 or u8tBadLead

const Utf8Table = block:
  var res: array[uint8, uint8]
  for u in uint8.low..uint8.high:
    case u
    of 0x00'u8 .. 0x7F'u8: res[u] = 0 # ASCII
    of 0x80'u8 .. 0xBF'u8:
      res[u] = u8tCont or u8tConsume1
      if u < 0x90:
        res[u] = res[u] or u8tLt90
      else:
        res[u] = res[u] or u8tGe90
      if u < 0xA0:
        res[u] = res[u] or u8tLtA0
      else:
        res[u] = res[u] or u8tGeA0
    of 0xC0'u8 .. 0xC1'u8: res[u] = u8tConsume1 or u8tBadLead
    of 0xC2'u8 .. 0xDF'u8: res[u] = u8tConsume1
    of 0xE0'u8: res[u] = u8tConsume2 or u8tGeA0
    of 0xE1'u8 .. 0xEC'u8: res[u] = u8tConsume2
    of 0xED'u8: res[u] = u8tConsume2 or u8tLtA0
    of 0xEE'u8 .. 0xEF'u8: res[u] = u8tConsume2
    of 0xF0'u8: res[u] = u8tConsume3 or u8tGe90
    of 0xF1'u8 .. 0xF3: res[u] = u8tConsume3
    of 0xF4'u8: res[u] = u8tConsume3 or u8tLt90
    of 0xF5'u8 .. 0xFF: res[u] = u8tConsume1 or u8tBadLead
  res

proc decodeUtf8(td: var TextDecoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int; finish: bool): TextDecoderResult =
  var bounds = td.bounds
  var flag = td.flag
  var i = td.i
  var ri = td.ri
  # we use the lead field to store the number of needed bytes
  var needed = td.lead
  var obuf = td.buf
  var buf = obuf
  let pi = i
  if flag == tdrDone:
    while i < iq.len:
      let b = iq[i]
      let ni = i + 1
      if needed == 0:
        if b <= 0x7F:
          ri = ni
        else:
          let t = Utf8Table[b]
          needed = t and 3
          bounds = (t and u8tBoundsMask) or ((t and u8tCont) shl 5) or u8tCont
          buf = b
      else:
        let t = Utf8Table[b]
        if (t and bounds) != bounds:
          needed = 0
          buf = 0
          # prepend, no consume
          flag = tdrError
          break
        dec needed
        if needed == 0:
          buf = 0
          ri = ni
        else:
          buf = (buf shl 8) or b
        bounds = u8tCont
      i = ni
  if (bounds and u8tBadLead) != 0 and needed == 1:
    # if streaming, we can't defer error reporting to the next iteration
    # (as this would be observable)
    needed = 0
    buf = 0
    flag = tdrError
  if obuf != 0 and pi == 0 and ri != 0:
    let L = (uint8(fastLog2(obuf)) + 7) shr 3
    let n2 = n + int(L)
    if n2 > oq.len:
      return tdrReqOutput
    for i in countdown(int(L - 1), 0):
      oq[n + i] = uint8(obuf and 0xFF)
      obuf = obuf shr 8
    n = n2
  td.ri = ri
  td.i = i
  td.lead = needed
  td.bounds = bounds
  td.buf = buf
  if pi < ri:
    td.pi = pi
    td.flag = flag
    return tdrReadInput
  td.flag = tdrDone
  case flag
  of tdrError:
    td.pi = pi
  of tdrDone:
    td.ri = 0
    if finish:
      td.buf = 0
      td.bounds = 0
      if needed != 0:
        td.lead = 0
        return tdrError
    td.i = 0
  else: discard # unreachable
  flag

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

proc decodeGb18030(td: var TextDecoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int; finish: bool): TextDecoderResult =
  if (td.buf and 0xFF) != 0: # buffer: to output after error
    oq.try_put_byte uint8(td.buf and 0xFF), n
    td.buf = td.buf and not 0xFF'u32
  while (let i = td.i; i < iq.len):
    let b = iq[i]
    let s = td.buf
    let first = (s shr 8) and 0xFF
    let second = (s shr 16) and 0xFF
    let third = (s shr 24) and 0xFF
    if b < 0x80 and s == 0: # first, second, third are all 0 (ASCII)
      oq.try_put_byte b, n
    elif third != 0:
      if b notin 0x30u8 .. 0x39u8:
        # set buf to second, first to third, second and third to 0
        td.buf = s shr 16
        # prepend (no inc i)
        return tdrError
      let p = ((uint32(first) - 0x81) * 10 * 126 * 10) +
              ((uint32(second) - 0x30) * (10 * 126)) +
              ((uint32(third) - 0x81) * 10) + uint32(b) - 0x30
      let c = gb18030RangesCodepoint(p)
      if c == high(uint32): # null
        td.buf = 0
        inc td.i
        return tdrError
      else:
        oq.try_put_utf8 c, n
        td.buf = 0
    elif second != 0:
      if b in 0x81u8 .. 0xFEu8:
        td.buf = s or (uint32(b) shl 24) # set third to b
      else:
        td.buf = second # set buf to second, first/second/third to 0
        return tdrError
    elif first != 0:
      if b in 0x30u8 .. 0x39u8:
        td.buf = s or (uint32(b) shl 16) # set second to b
      else:
        if b in {0x40u8..0x7Eu8, 0x80..0xFE}:
          let offset = if b < 0x7F: 0x40u16 else: 0x41u16
          let row = (uint16(first) - 0x81)
          let col = (uint16(b) - offset)
          if (let c = gb18030ToU16(row, col); c != 0):
            oq.try_put_utf8 c, n
            td.buf = 0 # set first to 0
            inc td.i
            continue
        if b < 0x80: # prepend if ASCII
          td.buf = b
        else:
          td.buf = 0
        inc td.i
        return tdrError
    elif b == 0x80:
      oq.try_put_str "\u20AC", n
    elif b in 0x81u8 .. 0xFEu8:
      td.buf = uint32(b) shl 8 # set first to b
    else:
      inc td.i
      return tdrError
    inc td.i
  if finish and td.buf != 0:
    td.buf = 0
    return tdrError
  td.i = 0
  tdrDone

proc decodeBig5(td: var TextDecoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int; finish: bool): TextDecoderResult =
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
            #TODO this should be done the other way around
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
  if finish and td.lead != 0:
    td.lead = 0
    return tdrError
  td.i = 0
  tdrDone

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

proc decodeEucJP(td: var TextDecoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int; finish: bool): TextDecoderResult =
  while (let i = td.i; i < iq.len):
    let b = iq[i]
    let lead = td.lead
    if b < 0x80 and lead == 0:
      oq.try_put_byte b, n
      inc td.i
      continue
    if lead == 0x8E and b in 0xA1u8 .. 0xDFu8:
      oq.try_put_utf8 b, n
      td.lead = 0
    elif lead == 0x8F and b in 0xA1u8 .. 0xFEu8:
      td.buf = 1
      td.lead = b
    elif lead != 0:
      if lead in 0xA1u8 .. 0xFEu8 and b in 0xA1u8 .. 0xFEu8:
        let row = (uint16(lead) - 0xA1)
        let col = uint16(b) - 0xA1
        let c = if td.buf != 0:
          jis0212ToU16(row, col)
        else:
          jis0208ToU16(row, col)
        if c != 0:
          oq.try_put_utf8 c, n
          td.buf = 0
          td.lead = 0
          inc td.i
          continue
        td.buf = 0
      td.lead = 0
      inc td.i
      return tdrError
    elif b in {0x8Eu8, 0x8Fu8, 0xA1u8 .. 0xFEu8}:
      td.lead = b
    else:
      inc td.i
      return tdrError
    inc td.i
  if finish and td.lead != 0:
    td.lead = 0
    return tdrError
  td.i = 0
  tdrDone

proc packState(buf: uint8; output: bool; state, outputState: uint8):
    uint32 =
  buf or (uint32(output) shl 8) or (uint32(state) shl 16) or
    (uint32(outputState) shl 24)

const
  i2jsAscii = 0'u8
  i2jsRoman = 1'u8
  i2jsKatakana = 2'u8
  i2jsLeadByte = 3'u8
  i2jsTrailByte = 4'u8
  i2jsEscapeStart = 5'u8
  i2jsEscape = 6'u8
  i2jsNull = 7'u8

proc decodeIso2022JP(td: var TextDecoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int; finish: bool): TextDecoderResult =
  let s = td.buf
  var buf = uint8(s and 0xFF)
  var output = ((s shr 8) and 0xFF) != 0
  var state = uint8((s shr 16) and 0xFF)
  var outputState = uint8((s shr 24) and 0xFF)
  #TODO checking buf in every iteration is not really needed, only in the
  # first one.  (it's only set before returning error)
  while (let i = td.i; buf != 0 or i < iq.len):
    template consume =
      if buf != 0:
        buf = 0
      else:
        inc td.i
    let b = if buf != 0: buf else: iq[i]
    td.buf = packState(buf, output, state, outputState)
    case state
    of i2jsAscii:
      case b
      of 0x1B:
        state = i2jsEscapeStart
      of {0x00u8..0x7Fu8} - {0x0Eu8, 0x0Fu8, 0x1Bu8}:
        oq.try_put_byte b, n
        output = false
      else:
        output = false
        consume
        td.buf = packState(buf, output, state, outputState)
        return tdrError
    of i2jsRoman:
      case b
      of 0x1B: state = i2jsEscapeStart
      of 0x5C:
        oq.try_put_str "\u00A5", n # yen
        output = false
      of 0x7E:
        oq.try_put_str "\u203E", n # overline
        output = false
      of {0x00u8..0x7Fu8} - {0x0Eu8, 0x0Fu8, 0x1Bu8, 0x5Cu8, 0x7Eu8}:
        oq.try_put_byte b, n
        output = false
      else:
        output = false
        consume
        td.buf = packState(buf, output, state, outputState)
        return tdrError
    of i2jsKatakana:
      case b
      of 0x1B: state = i2jsEscapeStart
      of 0x21u8..0x5Fu8:
        oq.try_put_utf8 0xFF61u16 - 0x21 + uint16(b), n
        output = false
      else:
        output = false
        consume
        td.buf = packState(buf, output, state, outputState)
        return tdrError
    of i2jsLeadByte:
      case b
      of 0x1B: state = i2jsEscapeStart
      of 0x21u8..0x7Eu8:
        output = false
        td.lead = b
        state = i2jsTrailByte
      else:
        output = false
        consume
        td.buf = packState(buf, output, state, outputState)
        return tdrError
    of i2jsTrailByte:
      case b
      of 0x1B:
        state = i2jsEscapeStart
        consume
        td.buf = packState(buf, output, state, outputState)
        return tdrError
      of 0x21u8..0x7Eu8:
        let row = (uint16(td.lead) - 0x21)
        let col = uint16(b) - 0x21
        if (let c = jis0208ToU16(row, col); c != 0):
          oq.try_put_utf8 c, n
          state = i2jsLeadByte
        else:
          state = i2jsLeadByte
          consume
          td.buf = packState(buf, output, state, outputState)
          return tdrError
      else:
        state = i2jsLeadByte
        consume
        td.buf = packState(buf, output, state, outputState)
        return tdrError
    of i2jsEscapeStart:
      if b == 0x24 or b == 0x28:
        td.lead = b
        state = i2jsEscape
      else:
        output = false
        state = outputState
        td.buf = packState(buf, output, state, outputState)
        # prepend (no inc i)
        return tdrError
    else: # i2jsEscape
      let l = td.lead
      td.lead = 0 # this is ok; we don't put anything in this state.
      let s = if l == 0x28:
        case b
        of 0x42: i2jsAscii
        of 0x4A: i2jsRoman
        of 0x49: i2jsKatakana
        else: i2jsNull
      elif b in {0x40u8, 0x42u8}:
        i2jsLeadByte
      else:
        i2jsNull
      if s != i2jsNull:
        state = s
        outputState = s
        consume
        if output:
          td.buf = packState(buf, output, state, outputState)
          return tdrError
        output = true
        continue
      td.buf = packState(l, false, outputState, outputState)
      # prepend (no inc i)
      return tdrError
    consume
  if finish:
    let l = td.lead
    td.lead = 0
    td.buf = 0
    case state
    of i2jsTrailByte, i2jsEscapeStart:
      return tdrError
    of i2jsEscape:
      # restore lead to the input queue
      td.buf = packState(l, false, outputState, outputState)
      return tdrError
    else: discard
  else:
    td.buf = packState(buf, output, state, outputState)
  td.i = 0
  tdrDone

proc decodeShiftJIS(td: var TextDecoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int; finish: bool): TextDecoderResult =
  while (let i = td.i; i < iq.len):
    let b = iq[i]
    let lead = td.lead
    if b < 0x80 and lead == 0: # ASCII
      oq.try_put_byte b, n
      inc td.i
      continue
    if lead != 0:
      let offset = if b < 0x7Fu8: 0x40u16 else: 0x41u16
      let leadoffset = if lead < 0xA0: 0x81u16 else: 0xC1u16
      if b in 0x40u8..0x7Eu8 or b in 0x80u8..0xFCu8:
        var row = (uint16(lead) - leadoffset) * 2
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
  if finish and td.lead != 0:
    td.lead = 0
    return tdrError
  td.i = 0
  tdrDone

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
    return EucKRRuns.findInRuns(EucKRRunsOffset, p)
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
    return EucKRRuns2.findInRuns(EucKRRunsOffset2, p)
  # bottom right quadrant
  col -= 0x60
  let p = row * 94 + col
  if p < EucKRDecode.len:
    return EucKRDecode[p]
  return 0

proc decodeEucKR(td: var TextDecoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int; finish: bool): TextDecoderResult =
  while (let i = td.i; i < iq.len):
    let b = iq[i]
    let lead = td.lead
    if lead == 0 and b < 0x80:
      oq.try_put_utf8 b, n
      inc td.i
      continue
    if lead != 0:
      if b in 0x41u8..0xFEu8:
        let col = (uint16(b) - 0x41)
        let row = (uint16(lead) - 0x81)
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
  if finish and td.lead != 0:
    td.lead = 0
    return tdrError
  td.i = 0
  tdrDone

proc decodeUtf16(td: var TextDecoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int; be, finish: bool): TextDecoderResult =
  let shiftLead = uint16(be) * 8
  let shiftTrail = uint16(not be) * 8
  while (let i = td.i; i < iq.len):
    let s = td.buf
    if ((s shr 16) and 0xFF) == 0: # no lead yet; read it
      td.buf = s or 0x10000
      td.lead = iq[i]
      inc td.i
      continue
    let lead = td.lead
    let cu = (uint16(lead) shl shiftLead) + uint16(iq[i]) shl shiftTrail
    if s != 0x10000: # has surrogate
      if unlikely(cu notin 0xDC00u16 .. 0xDFFFu16):
        td.buf = 0x10000
        return tdrError
      let surr = uint32(s and 0xFFFF)
      let c = 0x10000 + ((surr - 0xD800) shl 10) + (uint32(cu) - 0xDC00)
      oq.try_put_utf8 c, n
      td.buf = 0 # clear lead, surrogate
      inc td.i
      continue
    if cu in 0xD800u16 .. 0xDBFFu16:
      td.buf = uint32(cu) # clear lead, set cu as surrogate
      inc td.i
      continue
    if unlikely(cu in 0xDC00u16 .. 0xDFFFu16):
      inc td.i
      td.buf = 0 # clear lead, no surrogate
      return tdrError
    oq.try_put_utf8 uint32(cu), n
    td.buf = 0 # clear lead, no surrogate
    inc td.i
  if finish:
    td.lead = 0
    if td.buf != 0:
      td.buf = 0
      return tdrError
  td.i = 0
  tdrDone

proc decodeXUserDefined(td: var TextDecoder; iq: openArray[uint8];
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

proc decodeSingleByte(td: var TextDecoder; iq: openArray[uint8];
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

proc decodeReplacement(td: var TextDecoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int): TextDecoderResult =
  if td.buf == 0:
    td.buf = 1
    return tdrError
  tdrDone

proc decode*(td: var TextDecoder; iq: openArray[uint8];
    oq: var openArray[uint8]; n: var int; finish = false): TextDecoderResult =
  case td.charset #TODO maybe reuse unknown as BOM sniff?
  of csUnknown: tdrError
  of csUtf8: td.decodeUtf8(iq, oq, n, finish)
  of csGbk, csGb18030: td.decodeGb18030(iq, oq, n, finish)
  of csBig5: td.decodeBig5(iq, oq, n, finish)
  of csEucJP: td.decodeEucJP(iq, oq, n, finish)
  of csIso2022JP: td.decodeIso2022JP(iq, oq, n, finish)
  of csShiftJIS: td.decodeShiftJIS(iq, oq, n, finish)
  of csEucKR: td.decodeEucKR(iq, oq, n, finish)
  of csUtf16be: td.decodeUtf16(iq, oq, n, be = true, finish)
  of csUtf16le: td.decodeUtf16(iq, oq, n, be = false, finish)
  of csXUserDefined: td.decodeXUserDefined(iq, oq, n)
  of csReplacement: td.decodeReplacement(iq, oq, n)
  of csIbm866: td.decodeSingleByte(iq, oq, n, Ibm866Decode)
  of csIso8859_2: td.decodeSingleByte(iq, oq, n, Iso8859_2Decode)
  of csIso8859_3: td.decodeSingleByte(iq, oq, n, Iso8859_3Decode)
  of csIso8859_4: td.decodeSingleByte(iq, oq, n, Iso8859_4Decode)
  of csIso8859_5: td.decodeSingleByte(iq, oq, n, Iso8859_5Decode)
  of csIso8859_6: td.decodeSingleByte(iq, oq, n, Iso8859_6Decode)
  of csIso8859_7: td.decodeSingleByte(iq, oq, n, Iso8859_7Decode)
  of csIso8859_8, csIso8859_8i: td.decodeSingleByte(iq, oq, n, Iso8859_8Decode)
  of csIso8859_10: td.decodeSingleByte(iq, oq, n, Iso8859_10Decode)
  of csIso8859_13: td.decodeSingleByte(iq, oq, n, Iso8859_13Decode)
  of csIso8859_14: td.decodeSingleByte(iq, oq, n, Iso8859_14Decode)
  of csIso8859_15: td.decodeSingleByte(iq, oq, n, Iso8859_15Decode)
  of csIso8859_16: td.decodeSingleByte(iq, oq, n, Iso8859_16Decode)
  of csKoi8r: td.decodeSingleByte(iq, oq, n, Koi8rDecode)
  of csKoi8u: td.decodeSingleByte(iq, oq, n, Koi8uDecode)
  of csMacintosh: td.decodeSingleByte(iq, oq, n, MacintoshDecode)
  of csWindows874: td.decodeSingleByte(iq, oq, n, Windows874Decode)
  of csWindows1250: td.decodeSingleByte(iq, oq, n, Windows1250Decode)
  of csWindows1251: td.decodeSingleByte(iq, oq, n, Windows1251Decode)
  of csWindows1252: td.decodeSingleByte(iq, oq, n, Windows1252Decode)
  of csWindows1253: td.decodeSingleByte(iq, oq, n, Windows1253Decode)
  of csWindows1254: td.decodeSingleByte(iq, oq, n, Windows1254Decode)
  of csWindows1255: td.decodeSingleByte(iq, oq, n, Windows1255Decode)
  of csWindows1256: td.decodeSingleByte(iq, oq, n, Windows1256Decode)
  of csWindows1257: td.decodeSingleByte(iq, oq, n, Windows1257Decode)
  of csWindows1258: td.decodeSingleByte(iq, oq, n, Windows1258Decode)
  of csXMacCyrillic: td.decodeSingleByte(iq, oq, n, XMacCyrillicDecode)

{.pop.}
