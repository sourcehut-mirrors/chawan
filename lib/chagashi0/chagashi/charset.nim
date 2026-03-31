## This module contains the `Charset` enum used by [encoder](encoder.html) and
## [decoder](decoder.html).

{.push raises: [].}

import std/algorithm
import std/strutils

type Charset* = enum
  csUnknown
  csUtf8 = "utf-8"
  csIbm866 = "ibm866"
  csIso8859_2 = "iso-8859-2"
  csIso8859_3 = "iso-8859-3"
  csIso8859_4 = "iso-8859-4"
  csIso8859_5 = "iso-8859-5"
  csIso8859_6 = "iso-8859-6"
  csIso8859_7 = "iso-8859-7"
  csIso8859_8 = "iso-8859-8"
  csIso8859_8i = "iso-8859-8-i"
  csIso8859_10 = "iso-8859-10"
  csIso8859_13 = "iso-8859-13"
  csIso8859_14 = "iso-8859-14"
  csIso8859_15 = "iso-8859-15"
  csIso8859_16 = "iso-8859-16"
  csKoi8r = "koi8-r"
  csKoi8u = "koi8-u"
  csMacintosh = "macintosh"
  csWindows874 = "windows-874"
  csWindows1250 = "windows-1250"
  csWindows1251 = "windows-1251"
  csWindows1252 = "windows-1252"
  csWindows1253 = "windows-1253"
  csWindows1254 = "windows-1254"
  csWindows1255 = "windows-1255"
  csWindows1256 = "windows-1256"
  csWindows1257 = "windows-1257"
  csWindows1258 = "windows-1258"
  csXMacCyrillic = "x-mac-cyrillic"
  csGbk = "gbk"
  csGb18030 = "gb18030"
  csBig5 = "Big5"
  csEucJP = "euc-jp"
  csIso2022JP = "iso-2022-jp"
  csShiftJIS = "shift_jis"
  csEucKR = "euc-kr"
  csReplacement = "replacement"
  csUtf16be = "utf-16be"
  csUtf16le = "utf-16le"
  csXUserDefined = "x-user-defined"

const CharsetMap = {
  "866": csIbm866,
  "ansi_x3.4-1968": csWindows1252,
  "arabic": csIso8859_6,
  "ascii": csWindows1252, # lol
  "asmo-708": csIso8859_6,
  "big5": csBig5,
  "big5-hkscs": csBig5,
  "chinese": csGbk,
  "cn-big5": csBig5,
  "cp1250": csWindows1250,
  "cp1251": csWindows1251,
  "cp1252": csWindows1252,
  "cp1253": csWindows1253,
  "cp1254": csWindows1254,
  "cp1255": csWindows1255,
  "cp1256": csWindows1256,
  "cp1257": csWindows1257,
  "cp1258": csWindows1258,
  "cp819": csWindows1252,
  "cp866": csIbm866,
  "csbig5": csBig5,
  "cseuckr": csEucKR,
  "cseucpkdfmtjapanese": csEucJP,
  "csgb2312": csGbk,
  "csibm866": csIbm866,
  "csiso2022jp": csIso2022JP,
  "csiso2022kr": csReplacement,
  "csiso58gb231280": csGbk,
  "csiso88596e": csIso8859_6,
  "csiso88596i": csIso8859_6,
  "csiso88598e": csIso8859_8,
  "csiso88598i": csIso8859_8i,
  "csisolatin1": csWindows1252,
  "csisolatin2": csIso8859_2,
  "csisolatin3": csIso8859_3,
  "csisolatin4": csIso8859_4,
  "csisolatin5": csWindows1254,
  "csisolatin6": csIso8859_10,
  "csisolatin9": csIso8859_15,
  "csisolatinarabic": csIso8859_6,
  "csisolatincyrillic": csIso8859_5,
  "csisolatingreek": csIso8859_7,
  "csisolatinhebrew": csIso8859_8,
  "cskoi8r": csKoi8r,
  "csksc56011987": csEucKR,
  "csmacintosh": csMacintosh,
  "csshiftjis": csShiftJIS,
  "csunicode": csUtf16le,
  "cyrillic": csIso8859_5,
  "dos-874": csWindows874,
  "ecma-114": csIso8859_6,
  "ecma-118": csIso8859_7,
  "elot_928": csIso8859_7,
  "euc-jp": csEucJP,
  "euc-kr": csEucKR,
  "gb18030": csGb18030,
  "gb2312": csGbk,
  "gb_2312": csGbk,
  "gb_2312-80": csGbk,
  "gbk": csGbk,
  "greek": csIso8859_7,
  "greek8": csIso8859_7,
  "hebrew": csIso8859_8,
  "hz-gb-2312": csReplacement,
  "ibm819": csWindows1252,
  "ibm866": csIbm866,
  "iso-10646-ucs-2": csUtf16le,
  "iso-2022-cn": csReplacement,
  "iso-2022-cn-ext": csReplacement,
  "iso-2022-jp": csIso2022JP,
  "iso-2022-kr": csReplacement,
  "iso-8859-1": csWindows1252,
  "iso-8859-10": csIso8859_10,
  "iso-8859-11": csWindows874,
  "iso-8859-13": csIso8859_13,
  "iso-8859-14": csIso8859_14,
  "iso-8859-15": csIso8859_15,
  "iso-8859-16": csIso8859_16,
  "iso-8859-2": csIso8859_2,
  "iso-8859-3": csIso8859_3,
  "iso-8859-4": csIso8859_4,
  "iso-8859-5": csIso8859_5,
  "iso-8859-6": csIso8859_6,
  "iso-8859-6-e": csIso8859_6,
  "iso-8859-6-i": csIso8859_6,
  "iso-8859-7": csIso8859_7,
  "iso-8859-8": csIso8859_8,
  "iso-8859-8-e": csIso8859_8,
  "iso-8859-8-i": csIso8859_8i,
  "iso-8859-9": csWindows1254,
  "iso-ir-101": csIso8859_2,
  "iso-ir-109": csIso8859_3,
  "iso-ir-110": csIso8859_4,
  "iso-ir-126": csIso8859_7,
  "iso-ir-127": csIso8859_6,
  "iso-ir-138": csIso8859_8,
  "iso-ir-144": csIso8859_5,
  "iso-ir-148": csWindows1254,
  "iso-ir-149": csEucKR,
  "iso-ir-157": csIso8859_10,
  "iso-ir-58": csGbk,
  "iso8859-10": csIso8859_10,
  "iso8859-11": csWindows874,
  "iso8859-13": csIso8859_13,
  "iso8859-14": csIso8859_14,
  "iso8859-15": csIso8859_15,
  "iso8859-2": csIso8859_2,
  "iso8859-3": csIso8859_3,
  "iso8859-4": csIso8859_4,
  "iso8859-5": csIso8859_5,
  "iso8859-6": csIso8859_6,
  "iso8859-7": csIso8859_7,
  "iso8859-8": csIso8859_8,
  "iso8859-9": csWindows1254,
  "iso88591": csWindows1252,
  "iso885910": csIso8859_10,
  "iso885911": csWindows874,
  "iso885913": csIso8859_13,
  "iso885914": csIso8859_14,
  "iso885915": csIso8859_15,
  "iso88592": csIso8859_2,
  "iso88593": csIso8859_3,
  "iso88594": csIso8859_4,
  "iso88595": csIso8859_5,
  "iso88596": csIso8859_6,
  "iso88597": csIso8859_7,
  "iso88598": csIso8859_8,
  "iso88599": csWindows1254,
  "iso_8859-15": csIso8859_15,
  "iso_8859-1:1987": csWindows1252,
  "iso_8859-2": csIso8859_2,
  "iso_8859-2:1987": csIso8859_2,
  "iso_8859-3": csIso8859_3,
  "iso_8859-3:1988": csIso8859_3,
  "iso_8859-4": csIso8859_4,
  "iso_8859-4:1988": csIso8859_4,
  "iso_8859-5": csIso8859_5,
  "iso_8859-5:1988": csIso8859_5,
  "iso_8859-6": csIso8859_6,
  "iso_8859-6:1987": csIso8859_6,
  "iso_8859-7": csIso8859_7,
  "iso_8859-7:1987": csIso8859_7,
  "iso_8859-8": csIso8859_8,
  "iso_8859-8:1988": csIso8859_8,
  "iso_8859-9": csWindows1254,
  "iso_8859-9:1989": csWindows1254,
  "koi": csKoi8r,
  "koi8": csKoi8r,
  "koi8-r": csKoi8r,
  "koi8-ru": csKoi8u,
  "koi8-u": csKoi8u,
  "koi8_r": csKoi8r,
  "korean": csEucKR,
  "ks_c_5601-1987": csEucKR,
  "ks_c_5601-1989": csEucKR,
  "ksc5601": csEucKR,
  "ksc_5601": csEucKR,
  "l1": csWindows1252,
  "l2": csIso8859_2,
  "l3": csIso8859_3,
  "l4": csIso8859_4,
  "l5": csWindows1254,
  "l6": csIso8859_10,
  "l9": csIso8859_15,
  "latin1": csWindows1252,
  "latin2": csIso8859_2,
  "latin3": csIso8859_3,
  "latin4": csIso8859_4,
  "latin5": csWindows1254,
  "latin6": csIso8859_10,
  "logical": csIso8859_8i,
  "mac": csMacintosh,
  "macintosh": csMacintosh,
  "ms932": csShiftJIS,
  "ms_kanji": csShiftJIS,
  "replacement": csReplacement,
  "shift-jis": csShiftJIS,
  "shift_jis": csShiftJIS,
  "sjis": csShiftJIS,
  "sun_eu_greek": csIso8859_7,
  "tis-620": csWindows874,
  "ucs-2": csUtf16le,
  "unicode": csUtf16le,
  "unicode-1-1-utf-8": csUtf8,
  "unicode11utf-8": csUtf8,
  "unicode20utf-8": csUtf8,
  "unicodefeff": csUtf16le,
  "unicodefffe": csUtf16be,
  "us-ascii": csWindows1252,
  "utf-16": csUtf16le,
  "utf-16be": csUtf16be,
  "utf-16le": csUtf16le,
  "utf-8": csUtf8,
  "utf8": csUtf8,
  "visual": csIso8859_8,
  "windows-1250": csWindows1250,
  "windows-1251": csWindows1251,
  "windows-1252": csWindows1252,
  "windows-1253": csWindows1253,
  "windows-1254": csWindows1254,
  "windows-1255": csWindows1255,
  "windows-1256": csWindows1256,
  "windows-1257": csWindows1257,
  "windows-1258": csWindows1258,
  "windows-31j": csShiftJIS,
  "windows-874": csWindows874,
  "windows-949": csEucKR,
  "x-cp1250" : csWindows1250,
  "x-cp1251": csWindows1251,
  "x-cp1252": csWindows1252,
  "x-cp1253": csWindows1253,
  "x-cp1254": csWindows1254,
  "x-cp1255": csWindows1255,
  "x-cp1256": csWindows1256,
  "x-cp1257": csWindows1257,
  "x-cp1258": csWindows1258,
  "x-euc-jp": csEucJP,
  "x-gbk": csGbk,
  "x-mac-cyrillic": csXMacCyrillic,
  "x-mac-roman": csMacintosh,
  "x-mac-ukrainian": csXMacCyrillic,
  "x-sjis": csShiftJIS,
  "x-unicode20utf8": csUtf8,
  "x-user-defined": csXUserDefined,
  "x-x-big5": csBig5,
}

const NormalizedCharsetMap = {
  "866": csIbm866,
  "arabic": csIso8859_6,
  "ascii": csWindows1252, # lol
  "asmo708": csIso8859_6,
  "big5": csBig5,
  "big5hkscs": csBig5,
  "chinese": csGbk,
  "cnbig5": csBig5,
  "cp1250": csWindows1250,
  "cp1251": csWindows1251,
  "cp1252": csWindows1252,
  "cp1253": csWindows1253,
  "cp1254": csWindows1254,
  "cp1255": csWindows1255,
  "cp1256": csWindows1256,
  "cp1257": csWindows1257,
  "cp1258": csWindows1258,
  "cp819": csWindows1252,
  "cp866": csIbm866,
  "csbig5": csBig5,
  "cseuckr": csEucKR,
  "cseucpkdfmtjapanese": csEucJP,
  "csgb2312": csGbk,
  "csibm866": csIbm866,
  "csiso2022jp": csIso2022JP,
  "csiso2022kr": csReplacement,
  "csiso58gb231280": csGbk,
  "csiso88596e": csIso8859_6,
  "csiso88596i": csIso8859_6,
  "csiso88598e": csIso8859_8,
  "csiso88598i": csIso8859_8i,
  "csisolatin1": csWindows1252,
  "csisolatin2": csIso8859_2,
  "csisolatin3": csIso8859_3,
  "csisolatin4": csIso8859_4,
  "csisolatin5": csWindows1254,
  "csisolatin6": csIso8859_10,
  "csisolatin9": csIso8859_15,
  "csisolatinarabic": csIso8859_6,
  "csisolatincyrillic": csIso8859_5,
  "csisolatingreek": csIso8859_7,
  "csisolatinhebrew": csIso8859_8,
  "cskoi8r": csKoi8r,
  "csksc56011987": csEucKR,
  "csmacintosh": csMacintosh,
  "csshiftjis": csShiftJIS,
  "csunicode": csUtf16le,
  "cyrillic": csIso8859_5,
  "dos874": csWindows874,
  "ecma114": csIso8859_6,
  "ecma118": csIso8859_7,
  "elot928": csIso8859_7,
  "eucjp": csEucJP,
  "euckr": csEucKR,
  "gb18030": csGb18030,
  "gb2312": csGbk,
  "gb231280": csGbk,
  "gbk": csGbk,
  "greek": csIso8859_7,
  "greek8": csIso8859_7,
  "hebrew": csIso8859_8,
  "hzgb2312": csReplacement,
  "ibm819": csWindows1252,
  "ibm866": csIbm866,
  "iso10646ucs2": csUtf16le,
  "iso2022cn": csReplacement,
  "iso2022cnext": csReplacement,
  "iso2022jp": csIso2022JP,
  "iso2022kr": csReplacement,
  "iso88591": csWindows1252,
  "iso885910": csIso8859_10,
  "iso885911": csWindows874,
  "iso885913": csIso8859_13,
  "iso885914": csIso8859_14,
  "iso885915": csIso8859_15,
  "iso885915": csIso8859_15,
  "iso885916": csIso8859_16,
  "iso88592": csIso8859_2,
  "iso88592": csIso8859_2,
  "iso88593": csIso8859_3,
  "iso88593": csIso8859_3,
  "iso88594": csIso8859_4,
  "iso88594": csIso8859_4,
  "iso88595": csIso8859_5,
  "iso88595": csIso8859_5,
  "iso88596": csIso8859_6,
  "iso88596": csIso8859_6,
  "iso88596e": csIso8859_6,
  "iso88596i": csIso8859_6,
  "iso88597": csIso8859_7,
  "iso88597": csIso8859_7,
  "iso88598": csIso8859_8,
  "iso88598": csIso8859_8,
  "iso88598e": csIso8859_8,
  "iso88598i": csIso8859_8i,
  "iso88599": csWindows1254,
  "iso88599": csWindows1254,
  "isoir101": csIso8859_2,
  "isoir109": csIso8859_3,
  "isoir110": csIso8859_4,
  "isoir126": csIso8859_7,
  "isoir127": csIso8859_6,
  "isoir138": csIso8859_8,
  "isoir144": csIso8859_5,
  "isoir148": csWindows1254,
  "isoir149": csEucKR,
  "isoir157": csIso8859_10,
  "isoir58": csGbk,
  "koi": csKoi8r,
  "koi8": csKoi8r,
  "koi8r": csKoi8r,
  "koi8ru": csKoi8u,
  "koi8u": csKoi8u,
  "korean": csEucKR,
  "ksc5601": csEucKR,
  "ksc56011987": csEucKR,
  "ksc56011989": csEucKR,
  "l1": csWindows1252,
  "l2": csIso8859_2,
  "l3": csIso8859_3,
  "l4": csIso8859_4,
  "l5": csWindows1254,
  "l6": csIso8859_10,
  "l9": csIso8859_15,
  "latin1": csWindows1252,
  "latin2": csIso8859_2,
  "latin3": csIso8859_3,
  "latin4": csIso8859_4,
  "latin5": csWindows1254,
  "latin6": csIso8859_10,
  "logical": csIso8859_8i,
  "mac": csMacintosh,
  "macintosh": csMacintosh,
  "ms932": csShiftJIS,
  "mskanji": csShiftJIS,
  "shiftjis": csShiftJIS,
  "sjis": csShiftJIS,
  "suneugreek": csIso8859_7,
  "tis620": csWindows874,
  "ucs2": csUtf16le,
  "unicode": csUtf16le,
  "unicode11utf8": csUtf8,
  "unicode20utf8": csUtf8,
  "unicodefeff": csUtf16le,
  "unicodefffe": csUtf16be,
  "usascii": csWindows1252,
  "utf16": csUtf16le,
  "utf16be": csUtf16be,
  "utf16le": csUtf16le,
  "utf8": csUtf8,
  "visual": csIso8859_8,
  "windows1250": csWindows1250,
  "windows1251": csWindows1251,
  "windows1252": csWindows1252,
  "windows1253": csWindows1253,
  "windows1254": csWindows1254,
  "windows1255": csWindows1255,
  "windows1256": csWindows1256,
  "windows1257": csWindows1257,
  "windows1258": csWindows1258,
  "windows31j": csShiftJIS,
  "windows874": csWindows874,
  "windows949": csEucKR,
  "xcp1250" : csWindows1250,
  "xcp1251": csWindows1251,
  "xcp1252": csWindows1252,
  "xcp1253": csWindows1253,
  "xcp1254": csWindows1254,
  "xcp1255": csWindows1255,
  "xcp1256": csWindows1256,
  "xcp1257": csWindows1257,
  "xcp1258": csWindows1258,
  "xeucjp": csEucJP,
  "xgbk": csGbk,
  "xmaccyrillic": csXMacCyrillic,
  "xmacroman": csMacintosh,
  "xmacukrainian": csXMacCyrillic,
  "xsjis": csShiftJIS,
  "xunicode20utf8": csUtf8,
  "xxbig5": csBig5,
}

proc normalizeLocale(s: openArray[char]): string =
  result = ""
  for c in s:
    if uint8(c) > 0x20 and c notin {'_', '-'}:
      result &= c.toLowerAscii()

const DefaultCharset* = csUtf8

proc cmpCharsetPair(x: (string, Charset); k: string): int =
  cmpIgnoreCase(x[0], k)

proc getCharset*(s: string): Charset =
  ## Return a Charset from the label `s`. This function is equivalent to the
  ## standard "get an encoding from a string label" algorithm:
  ##
  ## https://encoding.spec.whatwg.org/#concept-encoding-get
  ##
  ## On failure, csUnknown is returned.
  const AsciiWhitespace = {' ', '\n', '\r', '\t', '\f'}
  let s = s.strip(chars = AsciiWhitespace)
  let i = CharsetMap.binarySearch(s, cmpCharsetPair)
  if i < 0:
    return csUnknown
  return CharsetMap[i][1]

proc getLocaleCharset*(s: string): Charset =
  ## Extract a charset from a locale. e.g. returns EUC_JP for the string
  ## LC_ALL=ja_JP.EUC_JP.
  let i = s.find('.')
  if i >= 0 and i < s.high:
    let ss = s.toOpenArray(i + 1, s.high).normalizeLocale()
    let i = NormalizedCharsetMap.binarySearch(ss, cmpCharsetPair)
    if i < 0:
      return csUnknown
    return NormalizedCharsetMap[i][1]
  # We could try to guess the charset based on the language here, like w3m
  # does.
  # However, these days it is more likely for any system to be using UTF-8
  # than any other charset, irrespective of the language. So we just assume
  # UTF-8.
  return DefaultCharset

{.pop.}
