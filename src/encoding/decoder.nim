{.push raises: [].}

import charset
import decodercore

type DecoderErrorMode* = enum
  demFatal, demReplacement

proc initTextDecoder*(charset: Charset): TextDecoder =
  ## Create a new TextDecoder instance from the charset.
  ## `charset` may be any value except csUnknown.
  assert charset != csUnknown
  TextDecoder(charset: charset)

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

proc initTextDecoderContext*(charset: Charset; errorMode = demReplacement;
    bufLen = 4096): TextDecoderContext =
  ## Initialize a new text decoder context.
  ##
  ## `charset` is the charset to decode the buffer with.
  ##
  ## `errorMode` affects how errors are handled.  With `demReplacement`,
  ## a U+FFFD replacement character is output when an error is encountered.
  ## With `demFatal`, decoding is aborted and the `failed` member of the
  ## `TextDecoderContext` is set to `true`.
  ##
  ## `bufLen` is the size of the internal buffer in bytes.
  return TextDecoderContext(
    td: initTextDecoder(charset),
    oq: newSeq[uint8](bufLen),
    errorMode: errorMode
  )

# returns whether this is the last iteration
proc decodeIter(ctx: var TextDecoderContext; iq: openArray[uint8];
    slices: var array[2, UnsafeSlice]; finish: bool): bool =
  result = false
  case ctx.td.decode(iq, ctx.oq, ctx.n, finish)
  of tdrDone:
    slices[0] = ctx.oq.toOpenArray(0, ctx.n - 1).toUnsafeSlice()
    result = true
  of tdrReadInput:
    if ctx.n > 0:
      slices[0] = ctx.oq.toOpenArray(0, ctx.n - 1).toUnsafeSlice()
    slices[1] = iq.toOpenArray(ctx.td.pi, ctx.td.ri - 1).toUnsafeSlice()
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
  ## Streaming consumers should set `finish` to true when decoding the last
  ## chunk.  (If you don't know which chunk will be the last, just pass
  ## an empty chunk after the stream is broken.)
  ##
  ## Returns an `UnsafeSlice` object, which can be further processed as an
  ## openArray or a string.  WARNING: this is simply a pointer into the
  ## input data and/or the output buffer.  Never use an `UnsafeSlice`
  ## object after the iteration you received it in.
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
  ## Note that setLen is called on the string, which may zero out the
  ## target space before the copy.
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

proc decodeAll*(iq: openArray[uint8]; charset: Charset; success: var bool):
    string =
  ## Decode `iq` using `charset`, with `iq` representing a complete
  ## contiguous input queue.  When a decoding error occurs, `success` is
  ## set to `false` and an empty string is returned; otherwise, it is set
  ## to `true` and the decoder's full output is returned.
  result = newStringOfCap(iq.len)
  var ctx = initTextDecoderContext(charset, errorMode = demFatal)
  for s in ctx.decode(iq, finish = true):
    result &= s
  success = not ctx.failed

proc decodeAll*(iq: openArray[char]; charset: Charset; success: var bool):
    string =
  return iq.toOpenArrayByte(0, iq.high).decodeAll(charset, success)

proc decodeAll*(iq: openArray[uint8]; charset: Charset): string =
  ## Use `td` to decode `iq`, representing a complete contiguous input
  ## queue.  Decoding errors are represented by U+FFFD replacement
  ## characters in the output.
  result = newStringOfCap(iq.len)
  var ctx = initTextDecoderContext(charset)
  for s in ctx.decode(iq, finish = true):
    result &= s

proc decodeAll*(iq: openArray[char]; charset: Charset): string =
  ## See above.
  return iq.toOpenArrayByte(0, iq.high).decodeAll(charset)

proc toValidUTF8*(iq: openArray[char]): string =
  ## Validate the UTF-8 string `iq`, replacing invalid characters with
  ## U+FFFD replacement characters.
  return iq.decodeAll(csUtf8)

proc validateUTF8Surr*(s: openArray[char]): int =
  ## Analogous to std/unicode's validateUtf8, but also reports surrogates.
  var ctx = initTextDecoderContext(csUtf8, errorMode = demFatal)
  for chunk in ctx.decode(s.toOpenArrayByte(0, s.high), finish = true):
    discard
  if ctx.failed:
    return ctx.td.ri
  return -1

{.pop.}
