{.push raises: [].}

import charset
import encodercore

type EncoderErrorMode* = enum
  eemFatal, eemHtml

proc initTextEncoder*(charset: Charset): TextEncoder =
  ## Create a new TextEncoder instance from the charset.
  ## Note: UTF-8 and UTF-16 encoders are not supported.
  ## (For UTF-8, use a TextDecoder instead.)
  assert charset notin {csUtf8, csUtf16be, csUtf16le, csReplacement, csUnknown}
  TextEncoder(charset: charset)

proc encodeAll*(iq: openArray[uint8]; charset: Charset; success: var bool):
    string =
  result = newString(iq.len)
  var te = initTextEncoder(charset)
  var n = 0
  while true:
    case te.encode(iq, result.toOpenArrayByte(0, result.high), n,
      finish = true)
    of terDone:
      result.setLen(n)
      break
    of terReqOutput:
      result.setLen(result.len * 2)
    of terError:
      success = false
      return ""
  success = true

proc encodeAll*(iq: openArray[char]; charset: Charset; success: var bool):
    string =
  success = false
  return iq.toOpenArrayByte(0, iq.high).encodeAll(charset, success)

proc encodeAll*(iq: openArray[uint8]; charset: Charset): string =
  result = newString(iq.len)
  var te = initTextEncoder(charset)
  var n = 0
  while true:
    case te.encode(iq, result.toOpenArrayByte(0, result.high), n,
      finish = true)
    of terDone:
      result.setLen(n)
      break
    of terReqOutput:
      result.setLen(result.len * 2)
    of terError:
      result.setLen(n)
      result &= "&#"
      if te.c == 0:
        result &= '0'
      else:
        while te.c > 0:
          result &= char(uint8('0') + uint8(te.c mod 10))
          te.c = te.c div 10
      result &= ';'
      n = result.len

proc encodeAll*(iq: openArray[char]; charset: Charset): string =
  return iq.toOpenArrayByte(0, iq.high).encodeAll(charset)

{.pop.}
