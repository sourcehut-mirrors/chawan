import charset
import decodercore

export decodercore

type DecoderErrorMode* = enum
  demFatal, demReplacement

proc newTextDecoder*(charset: Charset): TextDecoder =
  case charset
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
  of CHARSET_UTF_8, CHARSET_UNKNOWN: doAssert false

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
    of tdrReqOutput:
      result.setLen(result.len * 2)
    of tdrError:
      success = false
      return ""
  success = true

proc decodeAll*(td: TextDecoder; iq: string; success: var bool): string =
  success = false
  return td.decodeAll(iq.toOpenArrayByte(0, iq.high), success)

proc decodeAll*(td: TextDecoder; iq: openArray[uint8]): string =
  result = newString(iq.len)
  var n = 0
  while true:
    case td.decode(iq, result.toOpenArrayByte(0, result.high), n)
    of tdrDone:
      result.setLen(n)
      if td.finish() == tdfrError:
        result &= "\uFFFD"
      break
    of tdrReqOutput:
      result.setLen(result.len * 2)
    of tdrError:
      if n + "\uFFFD".len > result.len:
        result.setLen(result.len * 2 + "\uFFFD".len)
      for c in "\uFFFD":
        result[n] = c
        inc n

proc decodeAll*(td: TextDecoder; iq: string): string =
  return td.decodeAll(iq.toOpenArrayByte(0, iq.high))
