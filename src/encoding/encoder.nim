{.push raises: [].}

when NimMajor >= 2:
  import std/assertions

import encoding/charset
import encoding/encodercore
import utils/cowstr

type EncoderErrorMode* = enum
  eemFatal, eemHtml

proc initTextEncoder*(charset: Charset): TextEncoder =
  ## Create a new TextEncoder instance from the charset.
  ## Note: UTF-8 and UTF-16 encoders are not supported.
  ## (For UTF-8, use a TextDecoder instead.)
  assert charset notin {csUtf8, csUtf16be, csUtf16le, csReplacement, csUnknown}
  TextEncoder(charset: charset)

proc encodeAll*(iq: openArray[uint8]; charset: Charset; success: var bool):
    Str =
  var buf = initGrowbufUninit(iq.len)
  var te = initTextEncoder(charset)
  var n = 0
  while true:
    case te.encode(iq, buf.toOpenArrayByte(0, buf.high), n, finish = true)
    of terDone:
      buf.setLen(n)
      break
    of terReqOutput:
      buf.setLenUninit(buf.len * 2)
    of terError:
      success = false
      return str("")
  success = true
  buf.toStr()

proc encodeAll*(iq: openArray[char]; charset: Charset; success: var bool):
    Str =
  success = false
  iq.toOpenArrayByte(0, iq.high).encodeAll(charset, success)

proc encodeAll*(iq: openArray[uint8]; charset: Charset): Str =
  var buf = initGrowbufUninit(iq.len)
  var te = initTextEncoder(charset)
  var n = 0
  while true:
    case te.encode(iq, buf.toOpenArrayByte(0, buf.high), n, finish = true)
    of terDone:
      buf.setLen(n)
      break
    of terReqOutput:
      buf.setLenUninit(buf.len * 2)
    of terError:
      buf.setLen(n)
      buf &= "&#"
      if te.c == 0:
        buf &= '0'
      else:
        while te.c > 0:
          buf &= char(uint8('0') + uint8(te.c mod 10))
          te.c = te.c div 10
      buf &= ';'
      n = buf.len
  buf.toStr()

proc encodeAll*(iq: openArray[char]; charset: Charset): Str =
  return iq.toOpenArrayByte(0, iq.high).encodeAll(charset)

{.pop.}
