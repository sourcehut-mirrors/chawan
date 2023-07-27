import algorithm
import streams
import unicode

import charset
import utils/twtstr

# DecoderStream decodes any encoding to valid utf-32.
type
  DecoderErrorMode* = enum
    DECODER_ERROR_MODE_FATAL, DECODER_ERROR_MODE_REPLACEMENT

  ISO2022JPState = enum
    STATE_ASCII, STATE_ROMAN, STATE_KATAKANA, STATE_LEAD_BYTE,
    STATE_TRAIL_BYTE, STATE_ESCAPE_START, STATE_ESCAPE

  DecoderStream* = ref object
    source: Stream
    errormode: DecoderErrorMode
    isend: bool
    failed*: bool
    bufs: seq[seq[uint32]]
    bs: int
    bi: int
    buflen: int
    c: uint32
    case charset: Charset
    of CHARSET_UTF_8:
      u8c: uint32
      u8needed: int
      u8seen: int
      u8bounds: Slice[uint8]
    of CHARSET_GBK, CHARSET_GB18030:
      gb18first: uint8
      gb18second: uint8
      gb18third: uint8
      gb18buf: uint8
      gb18hasbuf: bool
    of CHARSET_BIG5:
      big5lead: uint8
    of CHARSET_EUC_JP:
      eucjplead: uint8
      eucjpjis0212: bool
    of CHARSET_ISO_2022_JP:
      iso2022jplead: uint8
      iso2022jpstate: ISO2022JPState
      iso2022jpoutputstate: ISO2022JPState
      iso2022jpoutput: bool
      iso2022jpbuf: uint8
      iso2022jphasbuf: bool
    of CHARSET_SHIFT_JIS:
      sjislead: uint8
    of CHARSET_EUC_KR:
      euckrlead: uint8
    of CHARSET_UTF_16_BE, CHARSET_UTF_16_LE:
      u16lead: uint8
      u16surr: uint16
      u16haslead: bool
      u16hassurr: bool
    of CHARSET_REPLACEMENT:
      replreported: bool
    else: discard

template append_codepoint_buf(stream: DecoderStream, c: uint32) =
  if stream.bi >= stream.buflen:
    stream.bufs.add(newSeqUninitialized[uint32](stream.buflen))
    stream.bi = 0
  stream.bufs[^1][stream.bi] = c
  inc stream.bi

template append_codepoint(stream: DecoderStream, c: uint32, oq: ptr UncheckedArray[uint32], olen: int, n: var int) =
  if n < olen:
    oq[n div sizeof(uint32)] = c
    n += sizeof(uint32)
  else:
    append_codepoint_buf stream, c

template append_codepoint(stream: DecoderStream, c: char, oq: ptr UncheckedArray[uint32], olen: int, n: var int) =
  stream.append_codepoint uint32(c), oq, olen, n

proc handleError(stream: DecoderStream, oq: ptr UncheckedArray[uint32], olen: int, n: var int) =
  case stream.errormode
  of DECODER_ERROR_MODE_FATAL:
    stream.isend = true
    stream.failed = true
  of DECODER_ERROR_MODE_REPLACEMENT:
    stream.append_codepoint 0xFFFD, oq, olen, n

proc decodeUTF8(stream: DecoderStream, iq: openArray[uint8],
    oq: ptr UncheckedArray[uint32], olen: int, n: var int) =
  var c = stream.u8c
  var needed = stream.u8needed
  var seen = stream.u8seen
  var bounds = stream.u8bounds
  var i = 0
  while i < iq.len:
    let b = iq[i]
    if needed == 0:
      case b
      of 0x00u8 .. 0x7Fu8:
        stream.append_codepoint uint32(b), oq, olen, n
      of 0xC2u8 .. 0xDFu8:
        needed = 1
        c = uint32(b) and 0x1F
      of 0xE0u8:
        bounds.a = 0xA0
        needed = 2
        c = uint32(b) and 0xF
      of 0xEDu8:
        bounds.b = 0x9F
        needed = 2
        c = uint32(b) and 0xF
      of 0xE1u8 .. 0xECu8, 0xEEu8 .. 0xEFu8:
        needed = 2
        c = uint32(b) and 0xF
      of 0xF0u8:
        bounds.a = 0x90
        needed = 3
        c = uint32(b) and 0x7
      of 0xF4u8:
        bounds.b = 0x8F
        needed = 3
        c = uint32(b) and 0x7
      of 0xF1u8 .. 0xF3u8:
        needed = 3
        c = uint32(b) and 0x7
      else:
        stream.handleError(oq, olen, n)
        if stream.isend: # fatal error
          break
      inc i
      continue
    if b notin bounds:
      c = 0
      needed = 0
      seen = 0
      bounds = 0x80u8 .. 0xBFu8
      stream.handleError(oq, olen, n)
      continue # prepend (no inc i)
    bounds = 0x80u8 .. 0xBFu8
    c = (c shl 6) or (b and 0x3F)
    inc seen
    if seen == needed:
      stream.append_codepoint c, oq, olen, n
      c = 0
      needed = 0
      seen = 0
    inc i
  stream.u8c = c
  stream.u8bounds = bounds
  stream.u8seen = seen
  stream.u8needed = needed

proc gb18RangesCodepoint(p: uint32): uint32 =
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
    # OR last on failure, so we can't just remove one if p is e.g. 39400.
    offset = 39394
    c = 0xFFE6
  else:
    # Find the first range that is greater than p, or last if no such element
    # is found.
    # We want the last that is <=, so decrease index by one.
    let i = upperBound(Gb18030RangesDecode, p, func(a: tuple[p, ucs: uint16], b: uint32): int =
      cmp(uint32(a.p), b))
    let elem = Gb18030RangesDecode[i - 1]
    offset = elem.p
    c = elem.ucs
  return c + p - offset

proc decodeGb18030(stream: DecoderStream, iq: openArray[uint8],
    oq: ptr UncheckedArray[uint32], olen: int, n: var int) =
  var first = stream.gb18first
  var second = stream.gb18second
  var third = stream.gb18third
  var buf = stream.gb18buf
  var hasbuf = stream.gb18hasbuf
  var i = 0
  while i < iq.len:
    let b = if hasbuf:
      hasbuf = false
      dec i
      buf
    else:
      iq[i]
    if third != 0:
      if b notin 0x30u8 .. 0x39u8:
        hasbuf = true
        buf = second
        first = third
        first = 0
        second = 0
        third = 0
        stream.handleError(oq, olen, n)
        if stream.isend: break
        continue # prepend (no inc i)
      else:
        let p = ((uint32(first) - 0x81) * 10 * 126 * 10) +
                ((uint32(second) - 0x30) * (10 * 126)) +
                ((uint32(third) - 0x81) * 10) + uint32(b) - 0x30
        let c = gb18RangesCodepoint(p)
        first = 0
        second = 0
        third = 0
        if c == high(uint32): # null
          stream.handleError(oq, olen, n)
          if stream.isend: break
        else:
          stream.append_codepoint c, oq, olen, n
    elif second != 0:
      if b in 0x81u8 .. 0xFEu8:
        third = b
      else:
        hasbuf = true
        buf = second
        first = 0
        second = 0
        third = 0
        stream.handleError(oq, olen, n)
        if stream.isend: break
    elif first != 0:
      if b in 0x30u8 .. 0x39u8:
        second = b
      else:
        let ff = first
        first = 0
        if b in 0x40u8 .. 0x7Eu8:
          let offset = if b < 0x7F: 0x40u32 else: 0x41u32
          let p = (uint16(ff) - 0x81) * 190 + (uint16(b) - offset)
          if p < Gb18030Decode.len:
            let c = Gb18030Decode[cast[uint16](p)]
            stream.append_codepoint uint32(c), oq, olen, n
            inc i
            continue
        if cast[char](b) in Ascii:
          continue # prepend (no inc i)
        else:
          stream.handleError(oq, olen, n)
          if stream.isend: break
    elif cast[char](b) in Ascii:
      stream.append_codepoint b, oq, olen, n
    elif b == 0x80:
      stream.append_codepoint 0x20AC, oq, olen, n
    elif b in 0x81u8 .. 0xFEu8:
      first = b
    else:
      stream.handleError(oq, olen, n)
      if stream.isend: break
    inc i
  stream.gb18first = first
  stream.gb18second = second
  stream.gb18third = third
  stream.gb18buf = buf
  stream.gb18hasbuf = hasbuf

proc decodeBig5(stream: DecoderStream, iq: openArray[uint8],
    oq: ptr UncheckedArray[uint32], olen: int, n: var int) =
  for b in iq:
    if stream.big5lead != 0:
      let lead = uint32(stream.big5lead)
      stream.big5lead = 0
      let offset = if b < 0x7F: 0x40u16 else: 0x62u16
      if b in {0x40u8 .. 0x7Eu8, 0xA1u8 .. 0xFEu8}:
        let p = (lead - 0x81) * 157 + uint16(b) - offset
        template output_two(a, b: uint32) =
          stream.append_codepoint a, oq, olen, n
          stream.append_codepoint b, oq, olen, n
        block no_continue:
          case p
          of 1133: output_two 0x00CA, 0x0304
          of 1135: output_two 0x00CA, 0x030C
          of 1164: output_two 0x00EA, 0x0304
          of 1166: output_two 0x00EA, 0x030C
          else: break no_continue
          continue
        if p < Big5Decode.len + Big5DecodeOffset:
          let c = Big5Decode[p - Big5DecodeOffset]
          if c != 0:
            stream.append_codepoint c, oq, olen, n
            continue
      if cast[char](b) in Ascii:
        stream.append_codepoint b, oq, olen, n
      else:
        stream.handleError(oq, olen, n)
        if stream.isend: break
    elif cast[char](b) in Ascii:
      stream.append_codepoint b, oq, olen, n
    elif b in 0x81u8 .. 0xFEu8:
      stream.big5lead = b
    else:
      stream.handleError(oq, olen, n)
      if stream.isend: break

proc decodeEUCJP(stream: DecoderStream, iq: openArray[uint8],
    oq: ptr UncheckedArray[uint32], olen: int, n: var int) =
  var jis0212 = stream.eucjpjis0212
  var lead = stream.eucjplead
  for b in iq:
    if lead == 0x8E and b in 0xA1u8 .. 0xDFu8:
      lead = 0
      stream.append_codepoint b, oq, olen, n
    elif lead == 0x8F and b in 0xA1u8 .. 0xFEu8:
      jis0212 = true
      lead = b
    elif lead != 0:
      if lead in 0xA1u8 .. 0xFEu8 and b in 0xA1u8 .. 0xFEu8:
        let p = (uint16(lead) - 0xA1) * 94 + uint16(b) - 0xA1
        lead = 0
        var c: uint16
        if jis0212:
          if p < Jis0212Decode.len:
            c = Jis0212Decode[p]
        else:
          if p < Jis0208Decode.len:
            c = Jis0208Decode[p]
        jis0212 = false
        if c != 0:
          stream.append_codepoint c, oq, olen, n
          continue
      else:
        lead = 0
      stream.handleError(oq, olen, n)
      if stream.isend: break
    elif cast[char](b) in Ascii:
      stream.append_codepoint b, oq, olen, n
    elif b in {0x8Eu8, 0x8Fu8, 0xA1u8 .. 0xFEu8}:
      lead = b
    else:
      stream.handleError(oq, olen, n)
      if stream.isend: break
  stream.eucjpjis0212 = jis0212
  stream.eucjplead = lead

proc decodeISO2022JP(stream: DecoderStream, iq: openArray[uint8],
    oq: ptr UncheckedArray[uint32], olen: int, n: var int) =
  var i = 0
  var lead = stream.iso2022jplead
  var state = stream.iso2022jpstate
  var output = stream.iso2022jpoutput
  var outputstate = stream.iso2022jpoutputstate
  var buf = stream.iso2022jpbuf
  var hasbuf = stream.iso2022jphasbuf
  while i < iq.len:
    let b = if hasbuf:
      hasbuf = false
      dec i
      buf
    else:
      iq[i]
    case state
    of STATE_ASCII:
      case b
      of 0x1B: state = STATE_ESCAPE_START
      of {0x00u8..0x7Fu8} - {0x0Eu8, 0x0Fu8, 0x1Bu8}:
        output = false
        stream.append_codepoint b, oq, olen, n
      else:
        output = false
        stream.handleError(oq, olen, n)
        if stream.isend: break
    of STATE_ROMAN:
      case b
      of 0x1B: state = STATE_ESCAPE_START
      of 0x5C:
        output = false
        stream.append_codepoint 0x00A5, oq, olen, n
      of 0x7E:
        output = false
        stream.append_codepoint 0x203E, oq, olen, n
      of {0x00u8..0x7Fu8} - {0x0Eu8, 0x0Fu8, 0x1Bu8, 0x5Cu8, 0x7Eu8}:
        output = false
        stream.append_codepoint b, oq, olen, n
      else:
        output = false
        stream.handleError(oq, olen, n)
        if stream.isend: break
    of STATE_KATAKANA:
      case b
      of 0x1B: state = STATE_ESCAPE_START
      of 0x21u8..0x5Fu8:
        output = false
        stream.append_codepoint 0xFF61u16 - 0x21 + uint16(b), oq, olen, n
      else:
        output = false
        stream.handleError(oq, olen, n)
        if stream.isend: break
    of STATE_LEAD_BYTE:
      case b
      of 0x1B: state = STATE_ESCAPE_START
      of 0x21u8..0x7Eu8:
        output = false
        lead = b
        state = STATE_TRAIL_BYTE
      else:
        output = false
        stream.handleError(oq, olen, n)
        if stream.isend: break
    of STATE_TRAIL_BYTE:
      case b
      of 0x1B:
        state = STATE_ESCAPE_START
        stream.handleError(oq, olen, n)
        if stream.isend: break
      of 0x21u8..0x7Eu8:
        state = STATE_LEAD_BYTE
        let p = (uint16(lead) - 0x21) * 94 + uint16(b) - 0x21
        if p < Jis0208Decode.len:
          let c = Jis0208Decode[p]
          if c != 0:
            stream.append_codepoint c, oq, olen, n
          else:
            stream.handleError(oq, olen, n)
            if stream.isend: break
      else:
        state = STATE_LEAD_BYTE
        stream.handleError(oq, olen, n)
        if stream.isend: break
    of STATE_ESCAPE_START:
      if b == 0x24 or b == 0x28:
        lead = b
        state = STATE_ESCAPE
      else:
        output = false
        state = outputstate
        stream.handleError(oq, olen, n)
        if stream.isend: break
        continue # prepend (no inc i)
    of STATE_ESCAPE:
      let l = lead
      lead = 0
      block statenonnull:
        var s: ISO2022JPState
        if l == 0x28:
          case b
          of 0x42: s = STATE_ASCII
          of 0x4A: s = STATE_ROMAN
          of 0x49: s = STATE_KATAKANA
          else: break statenonnull
        elif l == 0x24 and b in {0x40u8, 0x42u8}:
          s = STATE_LEAD_BYTE
        else: break statenonnull
        state = s
        outputstate = s
        if output:
          stream.handleError(oq, olen, n)
          if stream.isend:
            break
        output = true
        inc i
        continue
      output = false
      state = outputstate
      stream.handleError(oq, olen, n)
      if stream.isend: break
      hasbuf = true
      buf = l
      continue # prepend (no inc i)
    inc i
  stream.iso2022jphasbuf = hasbuf
  stream.iso2022jpbuf = buf
  stream.iso2022jplead = lead
  stream.iso2022jpstate = state
  stream.iso2022jpoutput = output
  stream.iso2022jpoutputstate = outputstate

proc decodeShiftJIS(stream: DecoderStream, iq: openArray[uint8],
    oq: ptr UncheckedArray[uint32], olen: int, n: var int) =
  var lead = stream.sjislead
  var i = 0
  while i < iq.len:
    let b = iq[i]
    if lead != 0:
      var ptrisnull = true;
      var p = 0u16
      let offset = if b < 0x7Fu8: 0x40u16 else: 0x41u16
      let leadoffset = if lead < 0xA0: 0x81u16 else: 0xC1u16
      if b in 0x40u8..0x7Eu8 or b in 0x80u8..0xFCu8:
        p = (uint16(lead) - leadoffset) * 188 + uint16(b) - offset
        ptrisnull = false
      lead = 0
      if not ptrisnull and p in 8836u16..10715u16:
        stream.append_codepoint 0xE000u16 - 8836 + p, oq, olen, n
        inc i
        continue
      elif not ptrisnull and p < Jis0208Decode.len and Jis0208Decode[p] != 0:
        let c = Jis0208Decode[p]
        stream.append_codepoint c, oq, olen, n
      else:
        stream.handleError(oq, olen, n)
        if stream.isend: break
        if cast[char](b) in Ascii:
          continue # prepend (no inc i)
    elif cast[char](b) in Ascii or b == 0x80:
      stream.append_codepoint b, oq, olen, n
    elif b in 0xA1u8..0xDFu8:
      stream.append_codepoint 0xFF61u16 - 0xA1 + uint16(b), oq, olen, n
    elif b in {0x81..0x9F} + {0xE0..0xFC}:
      lead = b
    else:
      stream.handleError(oq, olen, n)
      if stream.isend: break
    inc i
  stream.sjislead = lead

proc decodeEUCKR(stream: DecoderStream, iq: openArray[uint8],
    oq: ptr UncheckedArray[uint32], olen: int, n: var int) =
  var lead = stream.euckrlead
  for b in iq:
    if lead != 0:
      if b in 0x41u8..0xFEu8:
        let p = (uint16(lead) - 0x81) * 190 + (uint16(b) - 0x41)
        if p < EUCKRDecode.len and EUCKRDecode[p] != 0:
          let c = EUCKRDecode[p]
          stream.append_codepoint c, oq, olen, n
          continue
      stream.handleError(oq, olen, n)
      if stream.isend: break
    elif cast[char](b) in Ascii:
      stream.append_codepoint b, oq, olen, n
    elif b in {0x81u8..0xFEu8}:
      lead = b
    else:
      stream.handleError(oq, olen, n)
      if stream.isend: break
  stream.euckrlead = lead

proc decodeUTF16(stream: DecoderStream, iq: openArray[uint8],
    oq: ptr UncheckedArray[uint32], olen: int, n: var int, be: static bool) =
  var i = 0
  var lead = stream.u16lead
  var haslead = stream.u16haslead
  var surr = stream.u16surr
  var hassurr = stream.u16hassurr
  while i < iq.len:
    if not haslead:
      haslead = true
      lead = iq[i]
    else:
      let cu = if be:
        (uint16(lead) shl 8) + uint16(iq[i])
      else:
        (uint16(iq[i]) shl 8) + uint16(lead)
      haslead = false
      if hassurr:
        hassurr = false
        if cu in 0xDC00u16 .. 0xDFFFu16:
          let c = 0x10000 + ((uint32(surr) - 0xD800) shl 10) + (uint32(cu) - 0xDC00)
          stream.append_codepoint c, oq, olen, n
          inc i
          continue
        haslead = true # prepend the last two bytes
        stream.handleError(oq, olen, n)
        continue
      if cu in 0xD800u16 .. 0xDBFFu16:
        surr = cu
        hassurr = true
        inc i
        continue
      elif cu in 0xDC00u16 .. 0xDFFFu16:
        stream.handleError(oq, olen, n)
        if stream.isend: # fatal error
          break
        else:
          inc i
          continue
      stream.append_codepoint uint32(cu), oq, olen, n
    inc i
  stream.u16lead = lead
  stream.u16haslead = haslead
  stream.u16surr = surr
  stream.u16hassurr = hassurr

proc decodeUTF16LE(stream: DecoderStream, iq: openArray[uint8],
    oq: ptr UncheckedArray[uint32], olen: int, n: var int) =
  stream.decodeUTF16(iq, oq, olen, n, false)

proc decodeUTF16BE(stream: DecoderStream, iq: openArray[uint8],
    oq: ptr UncheckedArray[uint32], olen: int, n: var int) =
  stream.decodeUTF16(iq, oq, olen, n, true)

proc decodeXUserDefined(stream: DecoderStream, iq: openArray[uint8],
    oq: ptr UncheckedArray[uint32], olen: int, n: var int) =
  for b in iq:
    let c = cast[char](b)
    if c in Ascii:
      stream.append_codepoint c, oq, olen, n
    else:
      let c = 0xF780 + uint32(c) - 0x80
      stream.append_codepoint c, oq, olen, n

proc decodeSingleByte(stream: DecoderStream, iq: openArray[uint8],
    oq: ptr UncheckedArray[uint32], olen: int, n: var int,
    map: array[char, uint16]) =
  for b in iq:
    let c = cast[char](b)
    if c in Ascii:
      stream.append_codepoint c, oq, olen, n
    else:
      let p = map[cast[char](b - 0x80)]
      if p == 0u16:
        stream.handleError(oq, olen, n)
      else:
        stream.append_codepoint uint32(p), oq, olen, n

proc decodeReplacement(stream: DecoderStream, oq: ptr UncheckedArray[uint32],
    olen: int, n: var int) =
  if not stream.replreported:
    stream.replreported = true
    stream.handleError(oq, olen, n)
  # I think that's it?

# copy any data remaining from previous passes
proc copyBuffers(stream: DecoderStream, oq: ptr UncheckedArray[uint32], olen: int): int =
  if stream.bufs.len == 1:
    # one page: stream.bs ..< stream.bi
    let n = min((stream.bi - stream.bs) * sizeof(stream.bufs[0][0]), olen)
    copyMem(addr oq[0], addr stream.bufs[0][stream.bs], n)
    stream.bs += n div sizeof(uint32)
    if stream.bs >= stream.bi:
      # read entire page; recycle it
      stream.bs = 0
      stream.bi = 0
    return n
  else:
    # multiple pages:
    # stream.bs ..< stream.buflen
    # 0 ..< stream.buflen
    # ...
    # 0 ..< stream.bi
    let a = (stream.buflen - stream.bs) * sizeof(stream.bufs[0][0])
    if a < olen:
      copyMem(addr oq[0], addr stream.bufs[0][stream.bs], a)
      var ns = a
      stream.bs = 0
      var i = 1
      while i < stream.bufs.high:
        let n = min(stream.buflen * sizeof(stream.bufs[0][0]), olen - ns)
        copyMem(addr oq[ns div sizeof(uint32)], addr stream.bufs[i][0], n)
        ns += n
        if ns >= olen:
          # i'th buffer still has contents.
          stream.bs = n div sizeof(uint32)
          break
        stream.bs = 0
        inc i
      if ns < olen:
        # last page
        let n = min(stream.bi * sizeof(stream.bufs[0][0]), olen - ns)
        copyMem(addr oq[ns div sizeof(uint32)], addr stream.bufs[i][0], n)
        ns += n
        stream.bs = n div sizeof(uint32)
        if stream.bs >= stream.bi:
          # read entire page; recycle it
          stream.bs = 0
          stream.bi = 0
      for j in i ..< stream.bufs.len:
        stream.bufs[j - i] = stream.bufs[j]
      stream.bufs.setLen(stream.bufs.len - i)
      return ns
    elif a > olen:
      copyMem(addr oq[0], addr stream.bufs[0][stream.bs], olen)
      stream.bs += olen div sizeof(uint32)
      assert stream.bs < stream.buflen
      return olen
    else: # a == olen
      copyMem(addr oq[0], addr stream.bufs[0][stream.bs], a)
      stream.bs = 0
      stream.bufs.delete(0)
      return a

proc checkEnd(stream: DecoderStream, oq: ptr UncheckedArray[uint32], olen: int,
              n: var int) =
  if not stream.isend and stream.bufs.len == 1 and
      stream.bs >= stream.bi and stream.source.atEnd:
    stream.isend = true
    case stream.charset
    of CHARSET_UTF_16_LE, CHARSET_UTF_16_BE:
      if stream.u16haslead or stream.u16hassurr:
        stream.handleError(oq, olen, n)
    of CHARSET_UTF_8:
      if stream.u8needed != 0:
        stream.handleError(oq, olen, n)
    of CHARSET_GB18030, CHARSET_GBK:
      if stream.gb18first != 0 or stream.gb18second != 0 or stream.gb18third != 0:
        stream.handleError(oq, olen, n)
    of CHARSET_BIG5:
      if stream.big5lead != 0:
        stream.handleError(oq, olen, n)
    of CHARSET_EUC_JP:
      if stream.eucjplead != 0:
        stream.handleError(oq, olen, n)
    of CHARSET_ISO_2022_JP:
      case stream.iso2022jpstate
      of STATE_ASCII, STATE_ROMAN, STATE_KATAKANA, STATE_LEAD_BYTE: discard
      of STATE_TRAIL_BYTE:
        stream.handleError(oq, olen, n)
      of STATE_ESCAPE_START:
        stream.handleError(oq, olen, n)
      of STATE_ESCAPE:
        stream.isend = false
        stream.iso2022jpbuf = stream.iso2022jplead
        stream.iso2022jphasbuf = true
        stream.iso2022jplead = 0
        stream.iso2022jpoutput = false
        stream.iso2022jpstate = stream.iso2022jpoutputstate
        stream.handleError(oq, olen, n)
    of CHARSET_SHIFT_JIS:
      if stream.sjislead != 0:
        stream.handleError(oq, olen, n)
    of CHARSET_EUC_KR:
      if stream.euckrlead != 0:
        stream.handleError(oq, olen, n)
    else: discard

proc prepend*(stream: DecoderStream, c: uint32) =
  append_codepoint_buf stream, c

const ReadSize = 4096
proc readData*(stream: DecoderStream, buffer: pointer, olen: int): int =
  const l = sizeof(stream.bufs[0][0])
  assert olen mod l == 0, "Buffer size must be divisible by " & $l
  if olen == 0: return
  let oq = cast[ptr UncheckedArray[uint32]](buffer)
  result = stream.copyBuffers(oq, olen)
  let olen = olen - result
  if olen == 0 or stream.source.atEnd:
    # either output filled with buffered data; nothing to decode
    # or we're at the end of the source stream
    stream.checkEnd(oq, olen, result)
    return result
  var iq = newSeqUninitialized[uint8](ReadSize)
  let ilen = stream.source.readData(cast[pointer](addr iq[0]), ReadSize)
  if ilen == 0:
    stream.checkEnd(oq, olen, result)
    return result
  template iqoa: openArray[uint8] = toOpenArray(iq, 0, ilen - 1)
  case stream.charset
  of CHARSET_UTF_8:
    stream.decodeUTF8(iqoa, oq, olen, result)
  of CHARSET_IBM866:
    stream.decodeSingleByte(iqoa, oq, olen, result, IBM866Decode)
  of CHARSET_ISO_8859_2:
    stream.decodeSingleByte(iqoa, oq, olen, result, ISO88592Decode)
  of CHARSET_ISO_8859_3:
    stream.decodeSingleByte(iqoa, oq, olen, result, ISO88593Decode)
  of CHARSET_ISO_8859_4:
    stream.decodeSingleByte(iqoa, oq, olen, result, ISO88594Decode)
  of CHARSET_ISO_8859_5:
    stream.decodeSingleByte(iqoa, oq, olen, result, ISO88595Decode)
  of CHARSET_ISO_8859_6:
    stream.decodeSingleByte(iqoa, oq, olen, result, ISO88596Decode)
  of CHARSET_ISO_8859_7:
    stream.decodeSingleByte(iqoa, oq, olen, result, ISO88597Decode)
  of CHARSET_ISO_8859_8,
     CHARSET_ISO_8859_8_I:
    stream.decodeSingleByte(iqoa, oq, olen, result, ISO88598Decode)
  of CHARSET_ISO_8859_10:
    stream.decodeSingleByte(iqoa, oq, olen, result, ISO885910Decode)
  of CHARSET_ISO_8859_13:
    stream.decodeSingleByte(iqoa, oq, olen, result, ISO885913Decode)
  of CHARSET_ISO_8859_14:
    stream.decodeSingleByte(iqoa, oq, olen, result, ISO885914Decode)
  of CHARSET_ISO_8859_15:
    stream.decodeSingleByte(iqoa, oq, olen, result, ISO885915Decode)
  of CHARSET_ISO_8859_16:
    stream.decodeSingleByte(iqoa, oq, olen, result, ISO885916Decode)
  of CHARSET_KOI8_R:
    stream.decodeSingleByte(iqoa, oq, olen, result, KOI8RDecode)
  of CHARSET_KOI8_U:
    stream.decodeSingleByte(iqoa, oq, olen, result, KOI8UDecode)
  of CHARSET_MACINTOSH:
    stream.decodeSingleByte(iqoa, oq, olen, result, MacintoshDecode)
  of CHARSET_WINDOWS_874:
    stream.decodeSingleByte(iqoa, oq, olen, result, Windows874Decode)
  of CHARSET_WINDOWS_1250:
    stream.decodeSingleByte(iqoa, oq, olen, result, Windows1250Decode)
  of CHARSET_WINDOWS_1251:
    stream.decodeSingleByte(iqoa, oq, olen, result, Windows1251Decode)
  of CHARSET_WINDOWS_1252:
    stream.decodeSingleByte(iqoa, oq, olen, result, Windows1252Decode)
  of CHARSET_WINDOWS_1253:
    stream.decodeSingleByte(iqoa, oq, olen, result, Windows1253Decode)
  of CHARSET_WINDOWS_1254:
    stream.decodeSingleByte(iqoa, oq, olen, result, Windows1254Decode)
  of CHARSET_WINDOWS_1255:
    stream.decodeSingleByte(iqoa, oq, olen, result, Windows1255Decode)
  of CHARSET_WINDOWS_1256:
    stream.decodeSingleByte(iqoa, oq, olen, result, Windows1256Decode)
  of CHARSET_WINDOWS_1257:
    stream.decodeSingleByte(iqoa, oq, olen, result, Windows1257Decode)
  of CHARSET_WINDOWS_1258:
    stream.decodeSingleByte(iqoa, oq, olen, result, Windows1258Decode)
  of CHARSET_X_MAC_CYRILLIC:
    stream.decodeSingleByte(iqoa, oq, olen, result, XMacCyrillicDecode)
  of CHARSET_GBK, CHARSET_GB18030:
    stream.decodeGb18030(iqoa, oq, olen, result)
  of CHARSET_BIG5:
    stream.decodeBig5(iqoa, oq, olen, result)
  of CHARSET_EUC_JP:
    stream.decodeEUCJP(iqoa, oq, olen, result)
  of CHARSET_ISO_2022_JP:
    stream.decodeISO2022JP(iqoa, oq, olen, result)
  of CHARSET_SHIFT_JIS:
    stream.decodeShiftJIS(iqoa, oq, olen, result)
  of CHARSET_EUC_KR:
    stream.decodeEUCKR(iqoa, oq, olen, result)
  of CHARSET_REPLACEMENT:
    stream.decodeReplacement(oq, olen, result)
  of CHARSET_UTF_16_LE:
    stream.decodeUTF16LE(iqoa, oq, olen, result)
  of CHARSET_UTF_16_BE:
    stream.decodeUTF16BE(iqoa, oq, olen, result)
  of CHARSET_X_USER_DEFINED:
    stream.decodeXUserDefined(iqoa, oq, olen, result)
  of CHARSET_UNKNOWN:
    doAssert false, "Somebody forgot to set the character set here"
  stream.checkEnd(oq, olen, result)

# Returns the number of bytes read.
proc readData*(stream: DecoderStream, buf: var openarray[uint32]): int =
  return stream.readData(addr buf[0], buf.len * sizeof(buf[0]))

proc atEnd*(stream: DecoderStream): bool =
  return stream.isend

# Read all and convert to UTF-8.
# Probably not very efficient. Oh well.
proc readAll*(stream: DecoderStream): string =
  var buf = newSeqUninitialized[uint32](stream.buflen)
  while not stream.atEnd:
    let n = stream.readData(buf)
    for i in 0 ..< n div 4:
      let r = cast[Rune](buf[i])
      result &= $r

proc newDecoderStream*(source: Stream, cs = CHARSET_UTF_8, buflen = 1024,
                       errormode = DECODER_ERROR_MODE_REPLACEMENT): DecoderStream =
  result = DecoderStream(
    source: source,
    charset: cs,
    buflen: buflen,
    errormode: errormode
  )
  when nimvm:
    result.bufs = @[newSeq[uint32](buflen)]
  else:
    result.bufs = @[newSeqUninitialized[uint32](buflen)]
  case cs
  of CHARSET_UTF_8:
    result.u8bounds = 0x80u8 .. 0xBFu8
  else: discard
