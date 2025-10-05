{.push raises: [].}

import charset
import decodercore

export decodercore

type DecoderErrorMode* = enum
  demFatal, demReplacement

proc newTextDecoder*(charset: Charset): TextDecoder =
  ## Create a new TextDecoder instance from the charset.
  ## `charset` may be any value except CHARSET_UNKNOWN.
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
  of CHARSET_UNKNOWN:
    assert false
    return nil

type UnsafeSlice* = object
  p*: ptr UncheckedArray[char]
  len*: int

proc `$`*(sl: UnsafeSlice): string =
  if sl.p == nil:
    return ""
  var s = newString(sl.len)
  copyMem(addr s[0], addr sl.p[0], sl.len)
  return s

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
  oq*: seq[uint8]
  failed*: bool
  errorMode*: DecoderErrorMode

proc initTextDecoderContext*(td: TextDecoder; errorMode = demReplacement;
    bufLen = 4096): TextDecoderContext =
  ## Initialize a new text decoder context.
  ##
  ## `td` is an existing `TextDecoder` object, created with
  ## e.g. `newTextDecoder`.
  ##
  ## `errorMode` affects how errors are handled.
  ## For `demReplacement`, a U+FFFD replacement character is output when an
  ## error is encountered.
  ## For `demFatal`, decoding is aborted and the `failed` member of the
  ## `TextDecoderContext` is set to `true`.
  ##
  ## `bufLen` is the size of the internal buffer in bytes.
  return TextDecoderContext(
    td: td,
    oq: newSeq[uint8](bufLen),
    errorMode: errorMode
  )

proc initTextDecoderContext*(charset: Charset; errorMode = demReplacement;
    bufLen = 4096): TextDecoderContext =
  return initTextDecoderContext(newTextDecoder(charset), errorMode, bufLen)

# returns whether this is the last iteration
proc decodeIter(ctx: var TextDecoderContext; iq: openArray[uint8];
    slices: var array[2, UnsafeSlice]; finish: bool): bool =
  result = false
  let td = ctx.td
  case td.decode(iq, ctx.oq, ctx.n)
  of tdrDone:
    slices[0] = ctx.oq.toOpenArray(0, ctx.n - 1).toUnsafeSlice()
    if finish:
      if td.finish() == tdfrError:
        case ctx.errorMode
        of demReplacement: slices[1] = "\uFFFD".toUnsafeSlice()
        of demFatal: ctx.failed = true
    result = true
  of tdrReadInput:
    if ctx.n > 0:
      slices[0] = ctx.oq.toOpenArray(0, ctx.n - 1).toUnsafeSlice()
    slices[1] = iq.toOpenArray(td.pi, td.ri).toUnsafeSlice()
  of tdrReqOutput:
    slices[0] = ctx.oq.toOpenArray(0, ctx.n - 1).toUnsafeSlice()
  of tdrError:
    slices[0] = ctx.oq.toOpenArray(0, ctx.n - 1).toUnsafeSlice()
    case ctx.errorMode
    of demReplacement:
      slices[1] = "\uFFFD".toUnsafeSlice()
    of demFatal:
      ctx.failed = true
      result = true
  ctx.n = 0

iterator decode*(ctx: var TextDecoderContext; iq: openArray[uint8];
    finish: bool): UnsafeSlice =
  ## Decodes the bytes provided in `iq` (input queue).
  ##
  ## If called with `finish = true`, then this is assumed to be the last
  ## call. Streaming consumers should set `finish` on the last call.
  ##
  ## Returns an `UnsafeSlice` object, which can be further processed as an
  ## openArray or a string. WARNING: these are simply pointers into the input
  ## data and/or the output buffer. Never use an `UnsafeSlice` object after the
  ## iteration you received it in.
  var done = false
  while not done:
    var slices: array[2, UnsafeSlice]
    done = ctx.decodeIter(iq, slices, finish)
    for slice in slices:
      if slice.p != nil:
        yield slice

proc `&=`*(s: var string; sl: UnsafeSlice) =
  ## Append the slice `sl` to `s` without unnecessary copying.
  ##
  ## Note that setLen is called on the string, which may zero out the target
  ## space before the copy.
  if sl.p != nil:
    let L = s.len
    s.setLen(s.len + sl.len)
    copyMem(addr s[L], sl.p, sl.len)

proc high*(sl: UnsafeSlice): int =
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
  ## Use `td` to decode `iq`, representing a complete contiguous input queue.
  ## When a decoding error occurs, `success` is set to `false` and an empty
  ## string is returned; otherwise, it is set to `true` and the decoder's full
  ## output is returned.
  result = newStringOfCap(iq.len)
  var ctx = initTextDecoderContext(td, errorMode = demFatal)
  for s in ctx.decode(iq, finish = true):
    result &= s
  success = not ctx.failed

proc decodeAll*(td: TextDecoder; iq: openArray[char]; success: var bool):
    string =
  return td.decodeAll(iq.toOpenArrayByte(0, iq.high), success)

proc decodeAll*(td: TextDecoder; iq: openArray[uint8]): string =
  ## Use `td` to decode `iq`, representing a complete contiguous input queue.
  ## When a decoding error occurs, a U+FFFD replacement character is appended to
  ## the output.
  result = newStringOfCap(iq.len)
  var ctx = initTextDecoderContext(td)
  for s in ctx.decode(iq, finish = true):
    result &= s

proc decodeAll*(td: TextDecoder; iq: openArray[char]): string =
  ## See above.
  return td.decodeAll(iq.toOpenArrayByte(0, iq.high))

proc decodeAll*(iq: openArray[char]; charset: Charset): string =
  ## Decode the string `iq` as a string encoded with `charset`.
  return newTextDecoder(charset).decodeAll(iq)

proc toValidUTF8*(iq: openArray[char]): string =
  ## Validate the UTF-8 string `iq`, replacing invalid characters with U+FFFD
  ## replacement characters.
  return iq.decodeAll(CHARSET_UTF_8)

proc validateUTF8Surr*(s: openArray[char]; start = 0): int =
  ## Analogous to std/unicode's validateUtf8, but also reports surrogates and
  ## has an optional `start` parameter.
  var ctx = initTextDecoderContext(CHARSET_UTF_8, errorMode = demFatal)
  for chunk in ctx.decode(s.toOpenArrayByte(0, s.high), finish = true):
    discard
  if ctx.failed:
    return ctx.td.ri + 1
  return -1

{.pop.}
