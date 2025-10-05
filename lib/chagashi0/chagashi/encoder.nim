{.push raises: [].}

import charset
import encodercore

export encodercore

type EncoderErrorMode* = enum
  eemFatal, eemHtml

proc newTextEncoder*(charset: Charset): TextEncoder =
  ## Create a new TextEncoder instance from the charset.
  ## Note: UTF-8 and UTF-16 encoders are not supported. (For UTF-8, please use
  ## a TextDecoder instead.)
  case charset
  of CHARSET_IBM866: return TextEncoderIBM866()
  of CHARSET_ISO_8859_2: return TextEncoderISO8859_2()
  of CHARSET_ISO_8859_3: return TextEncoderISO8859_3()
  of CHARSET_ISO_8859_4: return TextEncoderISO8859_4()
  of CHARSET_ISO_8859_5: return TextEncoderISO8859_5()
  of CHARSET_ISO_8859_6: return TextEncoderISO8859_6()
  of CHARSET_ISO_8859_7: return TextEncoderISO8859_7()
  of CHARSET_ISO_8859_8,
    CHARSET_ISO_8859_8_I: return TextEncoderISO8859_8()
  of CHARSET_ISO_8859_10: return TextEncoderISO8859_10()
  of CHARSET_ISO_8859_13: return TextEncoderISO8859_13()
  of CHARSET_ISO_8859_14: return TextEncoderISO8859_14()
  of CHARSET_ISO_8859_15: return TextEncoderISO8859_15()
  of CHARSET_ISO_8859_16: return TextEncoderISO8859_16()
  of CHARSET_KOI8_R: return TextEncoderKOI8_R()
  of CHARSET_KOI8_U: return TextEncoderKOI8_U()
  of CHARSET_MACINTOSH: return TextEncoderMacintosh()
  of CHARSET_WINDOWS_874: return TextEncoderWindows874()
  of CHARSET_WINDOWS_1250: return TextEncoderWindows1250()
  of CHARSET_WINDOWS_1251: return TextEncoderWindows1251()
  of CHARSET_WINDOWS_1252: return TextEncoderWindows1252()
  of CHARSET_WINDOWS_1253: return TextEncoderWindows1253()
  of CHARSET_WINDOWS_1254: return TextEncoderWindows1254()
  of CHARSET_WINDOWS_1255: return TextEncoderWindows1255()
  of CHARSET_WINDOWS_1256: return TextEncoderWindows1256()
  of CHARSET_WINDOWS_1257: return TextEncoderWindows1257()
  of CHARSET_WINDOWS_1258: return TextEncoderWindows1258()
  of CHARSET_X_MAC_CYRILLIC: return TextEncoderXMacCyrillic()
  of CHARSET_GBK, CHARSET_GB18030: return TextEncoderGB18030()
  of CHARSET_BIG5: return TextEncoderBig5()
  of CHARSET_EUC_JP: return TextEncoderEUC_JP()
  of CHARSET_ISO_2022_JP: return TextEncoderISO2022_JP()
  of CHARSET_SHIFT_JIS: return TextEncoderShiftJIS()
  of CHARSET_EUC_KR: return TextEncoderEUC_KR()
  of CHARSET_X_USER_DEFINED: return TextEncoderXUserDefined()
  of CHARSET_UTF_8, CHARSET_UTF_16_BE, CHARSET_UTF_16_LE, CHARSET_REPLACEMENT,
      CHARSET_UNKNOWN:
    assert false
    return nil

proc encodeAll*(te: TextEncoder; iq: openArray[uint8]; success: var bool):
    string =
  result = newString(iq.len)
  var n = 0
  while true:
    case te.encode(iq, result.toOpenArrayByte(0, result.high), n)
    of terDone:
      result.setLen(n)
      case te.finish()
      of tefrOutputISO2022JPSetAscii:
        result &= "\e(B"
      of tefrDone:
        discard
      break
    of terReqOutput:
      result.setLen(result.len * 2)
    of terError:
      success = false
      return ""
  success = true

proc encodeAll*(td: TextEncoder; iq: openArray[char]; success: var bool):
    string =
  success = false
  return td.encodeAll(iq.toOpenArrayByte(0, iq.high), success)

proc encodeAll*(te: TextEncoder; iq: openArray[uint8]): string =
  result = newString(iq.len)
  var n = 0
  while true:
    case te.encode(iq, result.toOpenArrayByte(0, result.high), n)
    of terDone:
      result.setLen(n)
      case te.finish()
      of tefrOutputISO2022JPSetAscii:
        result &= "\e(B"
      of tefrDone:
        discard
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

proc encodeAll*(td: TextEncoder; iq: openArray[char]): string =
  return td.encodeAll(iq.toOpenArrayByte(0, iq.high))

proc encodeAll*(iq: openArray[char]; charset: Charset): string =
  return newTextEncoder(charset).encodeAll(iq.toOpenArrayByte(0, iq.high))

{.pop.}
