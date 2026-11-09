{.push raises: [].}

when NimMajor >= 2:
  import std/assertions

import encoding/charset
import encoding/decodercore
import utils/cowstr
import utils/twtstr

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

proc high*(sl: UnsafeSlice): int {.inline.} =
  {.push overflowChecks: off.}
  let H = sl.len - 1
  {.pop.}
  H

template toOpenArray*(sl: UnsafeSlice): openArray[char] =
  sl.toOpenArray(0, sl.high)

template toOpenArray*(sl: UnsafeSlice; lo, hi: int): openArray[char] =
  sl.p.toOpenArray(lo, hi)

template toOpenArrayByte*(sl: UnsafeSlice; lo, hi: int): openArray[uint8] =
  sl.p.toOpenArrayByte(lo, hi)

template toOpenArrayByte*(sl: UnsafeSlice): openArray[uint8] =
  sl.toOpenArrayByte(0, sl.high)

proc `$`*(sl: UnsafeSlice): string =
  if sl.p == nil:
    return ""
  var s = newString(sl.len)
  chaArrayCopy(s, sl.toOpenArray())
  move(s)

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
  failed*: bool
  last*: TextDecoderResult
  errorMode*: DecoderErrorMode

proc initTextDecoderContext*(charset: Charset; errorMode = demReplacement):
    TextDecoderContext =
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
  return TextDecoderContext(td: initTextDecoder(charset), errorMode: errorMode)

# returns whether this is the last iteration
proc decodeIter(ctx: var TextDecoderContext; iq: openArray[uint8];
    oq: var openArray[uint8]; slice: var UnsafeSlice; finish: bool): bool =
  case ctx.last
  of tdrReadInput:
    ctx.last = tdrDone
    slice = iq.toOpenArray(ctx.td.pi, ctx.td.ri - 1).toUnsafeSlice()
    return false
  of tdrError:
    ctx.last = tdrDone
    case ctx.errorMode
    of demReplacement:
      slice = "\uFFFD".toUnsafeSlice()
      return false
    of demFatal:
      ctx.failed = true
      return true
  else: discard
  var done = false
  case ctx.td.decode(iq, oq, ctx.n, finish)
  of tdrDone:
    slice = oq.toOpenArray(0, ctx.n - 1).toUnsafeSlice()
    done = true
  of tdrReadInput:
    if ctx.n > 0:
      slice = oq.toOpenArray(0, ctx.n - 1).toUnsafeSlice()
      ctx.last = tdrReadInput
    else:
      slice = iq.toOpenArray(ctx.td.pi, ctx.td.ri - 1).toUnsafeSlice()
  of tdrReqOutput:
    slice = oq.toOpenArray(0, ctx.n - 1).toUnsafeSlice()
  of tdrError:
    slice = oq.toOpenArray(0, ctx.n - 1).toUnsafeSlice()
    ctx.last = tdrError
  ctx.n = 0
  done

iterator decode*(ctx: var TextDecoderContext; iq: openArray[uint8];
    oq: var openArray[uint8]; finish: bool): UnsafeSlice =
  # for testing (so we can pass custom output queue lengths)
  var done = false
  while not done:
    var slice: UnsafeSlice
    done = ctx.decodeIter(iq, oq, slice, finish)
    if slice.p != nil:
      yield slice

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
  var oq {.noinit.}: array[1024, uint8]
  for it in ctx.decode(iq, oq, finish):
    yield it

proc add*(s: var Growbuf; sl: UnsafeSlice) =
  s &= sl.toOpenArray()

proc decodeAll*(iq: openArray[uint8]; charset: Charset; success: var bool):
    Str =
  ## Decode `iq` using `charset`, with `iq` representing a complete
  ## contiguous input queue.  When a decoding error occurs, `success` is
  ## set to `false` and an empty string is returned; otherwise, it is set
  ## to `true` and the decoder's full output is returned.
  var buf = initGrowbufOfCap(iq.len)
  var ctx = initTextDecoderContext(charset, errorMode = demFatal)
  for s in ctx.decode(iq, finish = true):
    buf &= s
  success = not ctx.failed
  buf.toStr()

proc decodeAll*(iq: openArray[char]; charset: Charset; success: var bool):
    Str =
  return iq.toOpenArrayByte(0, iq.high).decodeAll(charset, success)

proc decodeAll*(iq: openArray[uint8]; charset: Charset): Str =
  ## Use `td` to decode `iq`, representing a complete contiguous input
  ## queue.  Decoding errors are represented by U+FFFD replacement
  ## characters in the output.
  var buf = initGrowbufOfCap(iq.len)
  var ctx = initTextDecoderContext(charset)
  for s in ctx.decode(iq, finish = true):
    buf &= s
  buf.toStr()

proc decodeAll*(iq: openArray[char]; charset: Charset): Str =
  ## See above.
  return iq.toOpenArrayByte(0, iq.high).decodeAll(charset)

proc validateUTF8*(iq: openArray[char]): int =
  var ctx = initTextDecoderContext(csUtf8, demFatal)
  var oq: array[4, uint8]
  for s in ctx.decode(iq.toOpenArrayByte(0, iq.high), oq, finish = true):
    discard
  if ctx.failed:
    return ctx.td.ri
  return -1

proc toValidUTF8*(iq: Str): Str =
  ## Validate the UTF-8 string `iq`, replacing invalid characters with
  ## U+FFFD replacement characters.
  if iq.toOpenArray().validateUTF8() < 0:
    return iq
  return iq.toOpenArray().decodeAll(csUtf8)

{.pop.}
