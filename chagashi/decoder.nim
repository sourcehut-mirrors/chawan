import charset
import decodercore

export decodercore

type DecoderErrorMode* = enum
  demFatal, demReplacement

proc newTextDecoder*(charset: Charset): TextDecoder =
  ## Create a new TextDecoder instance from the charset.
  case charset
  of CHARSET_UTF_8: return TextDecoderUTF8()
  of CHARSET_IBM866: return TextDecoderIBM866()
  of CHARSET_ISO_8859_2: return TextDecoderISO8859_2()
  of CHARSET_ISO_8859_3: return TextDecoderISO8859_3()
  of CHARSET_ISO_8859_4: return TextDecoderISO8859_4()
  of CHARSET_ISO_8859_5: return TextDecoderISO8859_5()
  of CHARSET_ISO_8859_6: return TextDecoderISO8859_6()
  of CHARSET_ISO_8859_7: return TextDecoderISO8859_7()
  of CHARSET_ISO_8859_8,
    CHARSET_ISO_8859_8_I: return TextDecoderISO8859_8()
  of CHARSET_ISO_8859_10: return TextDecoderISO8859_10()
  of CHARSET_ISO_8859_13: return TextDecoderISO8859_13()
  of CHARSET_ISO_8859_14: return TextDecoderISO8859_14()
  of CHARSET_ISO_8859_15: return TextDecoderISO8859_15()
  of CHARSET_ISO_8859_16: return TextDecoderISO8859_16()
  of CHARSET_KOI8_R: return TextDecoderKOI8_R()
  of CHARSET_KOI8_U: return TextDecoderKOI8_U()
  of CHARSET_MACINTOSH: return TextDecoderMacintosh()
  of CHARSET_WINDOWS_874: return TextDecoderWindows874()
  of CHARSET_WINDOWS_1250: return TextDecoderWindows1250()
  of CHARSET_WINDOWS_1251: return TextDecoderWindows1251()
  of CHARSET_WINDOWS_1252: return TextDecoderWindows1252()
  of CHARSET_WINDOWS_1253: return TextDecoderWindows1253()
  of CHARSET_WINDOWS_1254: return TextDecoderWindows1254()
  of CHARSET_WINDOWS_1255: return TextDecoderWindows1255()
  of CHARSET_WINDOWS_1256: return TextDecoderWindows1256()
  of CHARSET_WINDOWS_1257: return TextDecoderWindows1257()
  of CHARSET_WINDOWS_1258: return TextDecoderWindows1258()
  of CHARSET_X_MAC_CYRILLIC: return TextDecoderXMacCyrillic()
  of CHARSET_GBK, CHARSET_GB18030: return TextDecoderGB18030()
  of CHARSET_BIG5: return TextDecoderBig5()
  of CHARSET_EUC_JP: return TextDecoderEUC_JP()
  of CHARSET_ISO_2022_JP: return TextDecoderISO2022_JP()
  of CHARSET_SHIFT_JIS: return TextDecoderShiftJIS()
  of CHARSET_EUC_KR: return TextDecoderEUC_KR()
  of CHARSET_REPLACEMENT: return TextDecoderReplacement()
  of CHARSET_UTF_16_LE: return TextDecoderUTF16_LE()
  of CHARSET_UTF_16_BE: return TextDecoderUTF16_BE()
  of CHARSET_X_USER_DEFINED: return TextDecoderXUserDefined()
  of CHARSET_UNKNOWN: doAssert false

type UnsafeSlice* = object
  p*: ptr UncheckedArray[char]
  len*: int

proc toUnsafeSlice(s: openArray[uint8]): UnsafeSlice =
  if s.len == 0:
    return UnsafeSlice(p: nil, len: 0)
  return UnsafeSlice(
    p: cast[ptr UncheckedArray[char]](unsafeAddr s[0]),
    len: s.len
  )

proc toUnsafeSlice(s: openArray[char]): UnsafeSlice =
  return s.toOpenArrayByte(0, s.high).toUnsafeSlice()

proc toUnsafeSlice(s: string): UnsafeSlice =
  return s.toOpenArray(0, s.high).toUnsafeSlice()

type TextDecoderContext* = object
  td*: TextDecoder
  n*: int
  pn*: int
  oq*: seq[char]
  failed*: bool
  errorMode*: DecoderErrorMode

proc initTextDecoderContext*(td: TextDecoder; errorMode = demReplacement;
    bufLen = 4096): TextDecoderContext =
  return TextDecoderContext(
    td: td,
    oq: newSeq[char](bufLen),
    errorMode: errorMode
  )

proc initTextDecoderContext*(charset: Charset; errorMode = demReplacement;
    bufLen = 4096): TextDecoderContext =
  return initTextDecoderContext(newTextDecoder(charset), errorMode, bufLen)

iterator decode*(ctx: var TextDecoderContext; iq: openArray[uint8];
    finish: bool): UnsafeSlice =
  ## Decodes the bytes provided in `iq` (input queue).
  ## If called with finish = true, then this is assumed to be the last call.
  ## Streaming consumers should call `finish` only on the last call.
  let td = ctx.td
  while true:
    case td.decode(iq, ctx.oq.toOpenArrayByte(0, ctx.oq.high), ctx.n)
    of tdrDone:
      yield ctx.oq.toOpenArray(ctx.pn, ctx.n - 1).toUnsafeSlice()
      if finish:
        if td.finish() == tdfrError:
          yield "\uFFFD".toUnsafeSlice()
      break
    of tdrReadInput:
      yield ctx.oq.toOpenArray(ctx.pn, ctx.n - 1).toUnsafeSlice()
      yield iq.toOpenArray(td.pi, td.ri).toUnsafeSlice()
      ctx.pn = ctx.n
    of tdrReqOutput:
      yield ctx.oq.toOpenArray(ctx.pn, ctx.n - 1).toUnsafeSlice()
      ctx.n = 0
      ctx.pn = 0
    of tdrError:
      yield ctx.oq.toOpenArray(ctx.pn, ctx.n - 1).toUnsafeSlice()
      case ctx.errorMode
      of demReplacement:
        #TODO we could squash \uFFFD into oq but I'm too lazy
        ctx.n = 0
        ctx.pn = 0
        yield "\uFFFD".toUnsafeSlice()
      of demFatal:
        ctx.failed = true
        break

proc `&=`*(s: var string; sl: UnsafeSlice) =
  if sl.p != nil:
    let L = s.len
    s.setLen(s.len + sl.len)
    copyMem(addr s[L], sl.p, sl.len)

func high*(sl: UnsafeSlice): int =
  return sl.len - 1

template toOpenArray*(sl: UnsafeSlice; lo, hi: int): openArray[char] =
  sl.p.toOpenArray(lo, hi)

template toOpenArray*(sl: UnsafeSlice): openArray[char] =
  sl.toOpenArray(0, sl.high)

template toOpenArrayByte*(sl: UnsafeSlice; lo, hi: int): openArray[uint8] =
  sl.p.toOpenArrayByte(lo, hi)

template toOpenArrayByte*(sl: UnsafeSlice): openArray[uint8] =
  sl.toOpenArrayByte(0, sl.high)

proc decodeAll*(td: TextDecoder; iq: openArray[uint8]; success: var bool):
    string =
  result = newString(iq.len)
  var n = 0
  while true:
    case td.decode(iq, result.toOpenArrayByte(0, result.high), n)
    of tdrDone:
      if td.finish() == tdfrError:
        success = false
        return ""
      break
    of tdrReadInput:
      let L = td.ri - td.pi + 1
      if result.len < n + L:
        result.setLen(n + L)
      for c in iq.toOpenArray(td.pi, td.ri):
        result[n] = char(c)
        inc n
    of tdrReqOutput:
      result.setLen(result.len * 2)
    of tdrError:
      success = false
      return ""
  success = true

proc decodeAll*(td: TextDecoder; iq: string; success: var bool): string =
  result = newStringOfCap(iq.len)
  var ctx = initTextDecoderContext(td, errorMode = demFatal)
  for s in ctx.decode(iq.toOpenArrayByte(0, iq.high), finish = true):
    result &= s
  success = not ctx.failed

proc decodeAll*(td: TextDecoder; iq: openArray[uint8]): string =
  result = newStringOfCap(iq.len)
  var ctx = initTextDecoderContext(td)
  for s in ctx.decode(iq, finish = true):
    result &= s

proc decodeAll*(td: TextDecoder; iq: string): string =
  return td.decodeAll(iq.toOpenArrayByte(0, iq.high))

proc decodeAll*(iq: string; charset: Charset): string =
  return newTextDecoder(charset).decodeAll(iq)

proc toValidUTF8*(iq: string): string =
  return TextDecoderUTF8().decodeAll(iq.toOpenArrayByte(0, iq.high))

proc validateUTF8Surr*(s: string; start = 0): int =
  ## Analogous to std/unicode's validateUtf8, but also reports surrogates and
  ## has an optional `start` parameter.
  var ctx = initTextDecoderContext(CHARSET_UTF_8, errorMode = demFatal)
  for chunk in ctx.decode(s.toOpenArrayByte(0, s.high), finish = true):
    discard
  if ctx.failed:
    return ctx.td.ri + 1
  return -1
