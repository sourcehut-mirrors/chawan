## This module contains the `Charset` enum used by [encoder](encoder.html) and
## [decoder](decoder.html).

{.push raises: [].}

import std/algorithm
import std/strutils

type Charset* = enum
  CHARSET_UNKNOWN
  CHARSET_UTF_8 = "utf-8"
  CHARSET_IBM866 = "ibm866"
  CHARSET_ISO_8859_2 = "iso-8859-2"
  CHARSET_ISO_8859_3 = "iso-8859-3"
  CHARSET_ISO_8859_4 = "iso-8859-4"
  CHARSET_ISO_8859_5 = "iso-8859-5"
  CHARSET_ISO_8859_6 = "iso-8859-6"
  CHARSET_ISO_8859_7 = "iso-8859-7"
  CHARSET_ISO_8859_8 = "iso-8859-8"
  CHARSET_ISO_8859_8_I = "iso-8859-8-i"
  CHARSET_ISO_8859_10 = "iso-8859-10"
  CHARSET_ISO_8859_13 = "iso-8859-13"
  CHARSET_ISO_8859_14 = "iso-8859-14"
  CHARSET_ISO_8859_15 = "iso-8859-15"
  CHARSET_ISO_8859_16 = "iso-8859-16"
  CHARSET_KOI8_R = "koi8-r"
  CHARSET_KOI8_U = "koi8-u"
  CHARSET_MACINTOSH = "macintosh"
  CHARSET_WINDOWS_874 = "windows-874"
  CHARSET_WINDOWS_1250 = "windows-1250"
  CHARSET_WINDOWS_1251 = "windows-1251"
  CHARSET_WINDOWS_1252 = "windows-1252"
  CHARSET_WINDOWS_1253 = "windows-1253"
  CHARSET_WINDOWS_1254 = "windows-1254"
  CHARSET_WINDOWS_1255 = "windows-1255"
  CHARSET_WINDOWS_1256 = "windows-1256"
  CHARSET_WINDOWS_1257 = "windows-1257"
  CHARSET_WINDOWS_1258 = "windows-1258"
  CHARSET_X_MAC_CYRILLIC = "x-mac-cyrillic"
  CHARSET_GBK = "gbk"
  CHARSET_GB18030 = "gb18030"
  CHARSET_BIG5 = "Big5"
  CHARSET_EUC_JP = "euc-jp"
  CHARSET_ISO_2022_JP = "iso-2022-jp"
  CHARSET_SHIFT_JIS = "shift_jis"
  CHARSET_EUC_KR = "euc-kr"
  CHARSET_REPLACEMENT = "replacement"
  CHARSET_UTF_16_BE = "utf-16be"
  CHARSET_UTF_16_LE = "utf-16le"
  CHARSET_X_USER_DEFINED = "x-user-defined"

const CharsetMap = {
  "866": CHARSET_IBM866,
  "ansi_x3.4-1968": CHARSET_WINDOWS_1252,
  "arabic": CHARSET_ISO_8859_6,
  "ascii": CHARSET_WINDOWS_1252, # lol
  "asmo-708": CHARSET_ISO_8859_6,
  "big5": CHARSET_BIG5,
  "big5-hkscs": CHARSET_BIG5,
  "chinese": CHARSET_GBK,
  "cn-big5": CHARSET_BIG5,
  "cp1250": CHARSET_WINDOWS_1250,
  "cp1251": CHARSET_WINDOWS_1251,
  "cp1252": CHARSET_WINDOWS_1252,
  "cp1253": CHARSET_WINDOWS_1253,
  "cp1254": CHARSET_WINDOWS_1254,
  "cp1255": CHARSET_WINDOWS_1255,
  "cp1256": CHARSET_WINDOWS_1256,
  "cp1257": CHARSET_WINDOWS_1257,
  "cp1258": CHARSET_WINDOWS_1258,
  "cp819": CHARSET_WINDOWS_1252,
  "cp866": CHARSET_IBM866,
  "csbig5": CHARSET_BIG5,
  "cseuckr": CHARSET_EUC_KR,
  "cseucpkdfmtjapanese": CHARSET_EUC_JP,
  "csgb2312": CHARSET_GBK,
  "csibm866": CHARSET_IBM866,
  "csiso2022jp": CHARSET_ISO_2022_JP,
  "csiso2022kr": CHARSET_REPLACEMENT,
  "csiso58gb231280": CHARSET_GBK,
  "csiso88596e": CHARSET_ISO_8859_6,
  "csiso88596i": CHARSET_ISO_8859_6,
  "csiso88598e": CHARSET_ISO_8859_8,
  "csiso88598i": CHARSET_ISO_8859_8_I,
  "csisolatin1": CHARSET_WINDOWS_1252,
  "csisolatin2": CHARSET_ISO_8859_2,
  "csisolatin3": CHARSET_ISO_8859_3,
  "csisolatin4": CHARSET_ISO_8859_4,
  "csisolatin5": CHARSET_WINDOWS_1254,
  "csisolatin6": CHARSET_ISO_8859_10,
  "csisolatin9": CHARSET_ISO_8859_15,
  "csisolatinarabic": CHARSET_ISO_8859_6,
  "csisolatincyrillic": CHARSET_ISO_8859_5,
  "csisolatingreek": CHARSET_ISO_8859_7,
  "csisolatinhebrew": CHARSET_ISO_8859_8,
  "cskoi8r": CHARSET_KOI8_R,
  "csksc56011987": CHARSET_EUC_KR,
  "csmacintosh": CHARSET_MACINTOSH,
  "csshiftjis": CHARSET_SHIFT_JIS,
  "csunicode": CHARSET_UTF_16_LE,
  "cyrillic": CHARSET_ISO_8859_5,
  "dos-874": CHARSET_WINDOWS_874,
  "ecma-114": CHARSET_ISO_8859_6,
  "ecma-118": CHARSET_ISO_8859_7,
  "elot_928": CHARSET_ISO_8859_7,
  "euc-jp": CHARSET_EUC_JP,
  "euc-kr": CHARSET_EUC_KR,
  "gb18030": CHARSET_GB18030,
  "gb2312": CHARSET_GBK,
  "gb_2312": CHARSET_GBK,
  "gb_2312-80": CHARSET_GBK,
  "gbk": CHARSET_GBK,
  "greek": CHARSET_ISO_8859_7,
  "greek8": CHARSET_ISO_8859_7,
  "hebrew": CHARSET_ISO_8859_8,
  "hz-gb-2312": CHARSET_REPLACEMENT,
  "ibm819": CHARSET_WINDOWS_1252,
  "ibm866": CHARSET_IBM866,
  "iso-10646-ucs-2": CHARSET_UTF_16_LE,
  "iso-2022-cn": CHARSET_REPLACEMENT,
  "iso-2022-cn-ext": CHARSET_REPLACEMENT,
  "iso-2022-jp": CHARSET_ISO_2022_JP,
  "iso-2022-kr": CHARSET_REPLACEMENT,
  "iso-8859-1": CHARSET_WINDOWS_1252,
  "iso-8859-10": CHARSET_ISO_8859_10,
  "iso-8859-11": CHARSET_WINDOWS_874,
  "iso-8859-13": CHARSET_ISO_8859_13,
  "iso-8859-14": CHARSET_ISO_8859_14,
  "iso-8859-15": CHARSET_ISO_8859_15,
  "iso-8859-16": CHARSET_ISO_8859_16,
  "iso-8859-2": CHARSET_ISO_8859_2,
  "iso-8859-3": CHARSET_ISO_8859_3,
  "iso-8859-4": CHARSET_ISO_8859_4,
  "iso-8859-5": CHARSET_ISO_8859_5,
  "iso-8859-6": CHARSET_ISO_8859_6,
  "iso-8859-6-e": CHARSET_ISO_8859_6,
  "iso-8859-6-i": CHARSET_ISO_8859_6,
  "iso-8859-7": CHARSET_ISO_8859_7,
  "iso-8859-8": CHARSET_ISO_8859_8,
  "iso-8859-8-e": CHARSET_ISO_8859_8,
  "iso-8859-8-i": CHARSET_ISO_8859_8_I,
  "iso-8859-9": CHARSET_WINDOWS_1254,
  "iso-ir-101": CHARSET_ISO_8859_2,
  "iso-ir-109": CHARSET_ISO_8859_3,
  "iso-ir-110": CHARSET_ISO_8859_4,
  "iso-ir-126": CHARSET_ISO_8859_7,
  "iso-ir-127": CHARSET_ISO_8859_6,
  "iso-ir-138": CHARSET_ISO_8859_8,
  "iso-ir-144": CHARSET_ISO_8859_5,
  "iso-ir-148": CHARSET_WINDOWS_1254,
  "iso-ir-149": CHARSET_EUC_KR,
  "iso-ir-157": CHARSET_ISO_8859_10,
  "iso-ir-58": CHARSET_GBK,
  "iso8859-10": CHARSET_ISO_8859_10,
  "iso8859-11": CHARSET_WINDOWS_874,
  "iso8859-13": CHARSET_ISO_8859_13,
  "iso8859-14": CHARSET_ISO_8859_14,
  "iso8859-15": CHARSET_ISO_8859_15,
  "iso8859-2": CHARSET_ISO_8859_2,
  "iso8859-3": CHARSET_ISO_8859_3,
  "iso8859-4": CHARSET_ISO_8859_4,
  "iso8859-5": CHARSET_ISO_8859_5,
  "iso8859-6": CHARSET_ISO_8859_6,
  "iso8859-7": CHARSET_ISO_8859_7,
  "iso8859-8": CHARSET_ISO_8859_8,
  "iso8859-9": CHARSET_WINDOWS_1254,
  "iso88591": CHARSET_WINDOWS_1252,
  "iso885910": CHARSET_ISO_8859_10,
  "iso885911": CHARSET_WINDOWS_874,
  "iso885913": CHARSET_ISO_8859_13,
  "iso885914": CHARSET_ISO_8859_14,
  "iso885915": CHARSET_ISO_8859_15,
  "iso88592": CHARSET_ISO_8859_2,
  "iso88593": CHARSET_ISO_8859_3,
  "iso88594": CHARSET_ISO_8859_4,
  "iso88595": CHARSET_ISO_8859_5,
  "iso88596": CHARSET_ISO_8859_6,
  "iso88597": CHARSET_ISO_8859_7,
  "iso88598": CHARSET_ISO_8859_8,
  "iso88599": CHARSET_WINDOWS_1254,
  "iso_8859-15": CHARSET_ISO_8859_15,
  "iso_8859-1:1987": CHARSET_WINDOWS_1252,
  "iso_8859-2": CHARSET_ISO_8859_2,
  "iso_8859-2:1987": CHARSET_ISO_8859_2,
  "iso_8859-3": CHARSET_ISO_8859_3,
  "iso_8859-3:1988": CHARSET_ISO_8859_3,
  "iso_8859-4": CHARSET_ISO_8859_4,
  "iso_8859-4:1988": CHARSET_ISO_8859_4,
  "iso_8859-5": CHARSET_ISO_8859_5,
  "iso_8859-5:1988": CHARSET_ISO_8859_5,
  "iso_8859-6": CHARSET_ISO_8859_6,
  "iso_8859-6:1987": CHARSET_ISO_8859_6,
  "iso_8859-7": CHARSET_ISO_8859_7,
  "iso_8859-7:1987": CHARSET_ISO_8859_7,
  "iso_8859-8": CHARSET_ISO_8859_8,
  "iso_8859-8:1988": CHARSET_ISO_8859_8,
  "iso_8859-9": CHARSET_WINDOWS_1254,
  "iso_8859-9:1989": CHARSET_WINDOWS_1254,
  "koi": CHARSET_KOI8_R,
  "koi8": CHARSET_KOI8_R,
  "koi8-r": CHARSET_KOI8_R,
  "koi8-ru": CHARSET_KOI8_U,
  "koi8-u": CHARSET_KOI8_U,
  "koi8_r": CHARSET_KOI8_R,
  "korean": CHARSET_EUC_KR,
  "ks_c_5601-1987": CHARSET_EUC_KR,
  "ks_c_5601-1989": CHARSET_EUC_KR,
  "ksc5601": CHARSET_EUC_KR,
  "ksc_5601": CHARSET_EUC_KR,
  "l1": CHARSET_WINDOWS_1252,
  "l2": CHARSET_ISO_8859_2,
  "l3": CHARSET_ISO_8859_3,
  "l4": CHARSET_ISO_8859_4,
  "l5": CHARSET_WINDOWS_1254,
  "l6": CHARSET_ISO_8859_10,
  "l9": CHARSET_ISO_8859_15,
  "latin1": CHARSET_WINDOWS_1252,
  "latin2": CHARSET_ISO_8859_2,
  "latin3": CHARSET_ISO_8859_3,
  "latin4": CHARSET_ISO_8859_4,
  "latin5": CHARSET_WINDOWS_1254,
  "latin6": CHARSET_ISO_8859_10,
  "logical": CHARSET_ISO_8859_8_I,
  "mac": CHARSET_MACINTOSH,
  "macintosh": CHARSET_MACINTOSH,
  "ms932": CHARSET_SHIFT_JIS,
  "ms_kanji": CHARSET_SHIFT_JIS,
  "replacement": CHARSET_REPLACEMENT,
  "shift-jis": CHARSET_SHIFT_JIS,
  "shift_jis": CHARSET_SHIFT_JIS,
  "sjis": CHARSET_SHIFT_JIS,
  "sun_eu_greek": CHARSET_ISO_8859_7,
  "tis-620": CHARSET_WINDOWS_874,
  "ucs-2": CHARSET_UTF_16_LE,
  "unicode": CHARSET_UTF_16_LE,
  "unicode-1-1-utf-8": CHARSET_UTF_8,
  "unicode11utf-8": CHARSET_UTF_8,
  "unicode20utf-8": CHARSET_UTF_8,
  "unicodefeff": CHARSET_UTF_16_LE,
  "unicodefffe": CHARSET_UTF_16_BE,
  "us-ascii": CHARSET_WINDOWS_1252,
  "utf-16": CHARSET_UTF_16_LE,
  "utf-16be": CHARSET_UTF_16_BE,
  "utf-16le": CHARSET_UTF_16_LE,
  "utf-8": CHARSET_UTF_8,
  "utf8": CHARSET_UTF_8,
  "visual": CHARSET_ISO_8859_8,
  "windows-1250": CHARSET_WINDOWS_1250,
  "windows-1251": CHARSET_WINDOWS_1251,
  "windows-1252": CHARSET_WINDOWS_1252,
  "windows-1253": CHARSET_WINDOWS_1253,
  "windows-1254": CHARSET_WINDOWS_1254,
  "windows-1255": CHARSET_WINDOWS_1255,
  "windows-1256": CHARSET_WINDOWS_1256,
  "windows-1257": CHARSET_WINDOWS_1257,
  "windows-1258": CHARSET_WINDOWS_1258,
  "windows-31j": CHARSET_SHIFT_JIS,
  "windows-874": CHARSET_WINDOWS_874,
  "windows-949": CHARSET_EUC_KR,
  "x-cp1250" : CHARSET_WINDOWS_1250,
  "x-cp1251": CHARSET_WINDOWS_1251,
  "x-cp1252": CHARSET_WINDOWS_1252,
  "x-cp1253": CHARSET_WINDOWS_1253,
  "x-cp1254": CHARSET_WINDOWS_1254,
  "x-cp1255": CHARSET_WINDOWS_1255,
  "x-cp1256": CHARSET_WINDOWS_1256,
  "x-cp1257": CHARSET_WINDOWS_1257,
  "x-cp1258": CHARSET_WINDOWS_1258,
  "x-euc-jp": CHARSET_EUC_JP,
  "x-gbk": CHARSET_GBK,
  "x-mac-cyrillic": CHARSET_X_MAC_CYRILLIC,
  "x-mac-roman": CHARSET_MACINTOSH,
  "x-mac-ukrainian": CHARSET_X_MAC_CYRILLIC,
  "x-sjis": CHARSET_SHIFT_JIS,
  "x-unicode20utf8": CHARSET_UTF_8,
  "x-user-defined": CHARSET_X_USER_DEFINED,
  "x-x-big5": CHARSET_BIG5,
}

const NormalizedCharsetMap = {
  "866": CHARSET_IBM866,
  "arabic": CHARSET_ISO_8859_6,
  "ascii": CHARSET_WINDOWS_1252, # lol
  "asmo708": CHARSET_ISO_8859_6,
  "big5": CHARSET_BIG5,
  "big5hkscs": CHARSET_BIG5,
  "chinese": CHARSET_GBK,
  "cnbig5": CHARSET_BIG5,
  "cp1250": CHARSET_WINDOWS_1250,
  "cp1251": CHARSET_WINDOWS_1251,
  "cp1252": CHARSET_WINDOWS_1252,
  "cp1253": CHARSET_WINDOWS_1253,
  "cp1254": CHARSET_WINDOWS_1254,
  "cp1255": CHARSET_WINDOWS_1255,
  "cp1256": CHARSET_WINDOWS_1256,
  "cp1257": CHARSET_WINDOWS_1257,
  "cp1258": CHARSET_WINDOWS_1258,
  "cp819": CHARSET_WINDOWS_1252,
  "cp866": CHARSET_IBM866,
  "csbig5": CHARSET_BIG5,
  "cseuckr": CHARSET_EUC_KR,
  "cseucpkdfmtjapanese": CHARSET_EUC_JP,
  "csgb2312": CHARSET_GBK,
  "csibm866": CHARSET_IBM866,
  "csiso2022jp": CHARSET_ISO_2022_JP,
  "csiso2022kr": CHARSET_REPLACEMENT,
  "csiso58gb231280": CHARSET_GBK,
  "csiso88596e": CHARSET_ISO_8859_6,
  "csiso88596i": CHARSET_ISO_8859_6,
  "csiso88598e": CHARSET_ISO_8859_8,
  "csiso88598i": CHARSET_ISO_8859_8_I,
  "csisolatin1": CHARSET_WINDOWS_1252,
  "csisolatin2": CHARSET_ISO_8859_2,
  "csisolatin3": CHARSET_ISO_8859_3,
  "csisolatin4": CHARSET_ISO_8859_4,
  "csisolatin5": CHARSET_WINDOWS_1254,
  "csisolatin6": CHARSET_ISO_8859_10,
  "csisolatin9": CHARSET_ISO_8859_15,
  "csisolatinarabic": CHARSET_ISO_8859_6,
  "csisolatincyrillic": CHARSET_ISO_8859_5,
  "csisolatingreek": CHARSET_ISO_8859_7,
  "csisolatinhebrew": CHARSET_ISO_8859_8,
  "cskoi8r": CHARSET_KOI8_R,
  "csksc56011987": CHARSET_EUC_KR,
  "csmacintosh": CHARSET_MACINTOSH,
  "csshiftjis": CHARSET_SHIFT_JIS,
  "csunicode": CHARSET_UTF_16_LE,
  "cyrillic": CHARSET_ISO_8859_5,
  "dos874": CHARSET_WINDOWS_874,
  "ecma114": CHARSET_ISO_8859_6,
  "ecma118": CHARSET_ISO_8859_7,
  "elot928": CHARSET_ISO_8859_7,
  "eucjp": CHARSET_EUC_JP,
  "euckr": CHARSET_EUC_KR,
  "gb18030": CHARSET_GB18030,
  "gb2312": CHARSET_GBK,
  "gb231280": CHARSET_GBK,
  "gbk": CHARSET_GBK,
  "greek": CHARSET_ISO_8859_7,
  "greek8": CHARSET_ISO_8859_7,
  "hebrew": CHARSET_ISO_8859_8,
  "hzgb2312": CHARSET_REPLACEMENT,
  "ibm819": CHARSET_WINDOWS_1252,
  "ibm866": CHARSET_IBM866,
  "iso10646ucs2": CHARSET_UTF_16_LE,
  "iso2022cn": CHARSET_REPLACEMENT,
  "iso2022cnext": CHARSET_REPLACEMENT,
  "iso2022jp": CHARSET_ISO_2022_JP,
  "iso2022kr": CHARSET_REPLACEMENT,
  "iso88591": CHARSET_WINDOWS_1252,
  "iso885910": CHARSET_ISO_8859_10,
  "iso885911": CHARSET_WINDOWS_874,
  "iso885913": CHARSET_ISO_8859_13,
  "iso885914": CHARSET_ISO_8859_14,
  "iso885915": CHARSET_ISO_8859_15,
  "iso885915": CHARSET_ISO_8859_15,
  "iso885916": CHARSET_ISO_8859_16,
  "iso88592": CHARSET_ISO_8859_2,
  "iso88592": CHARSET_ISO_8859_2,
  "iso88593": CHARSET_ISO_8859_3,
  "iso88593": CHARSET_ISO_8859_3,
  "iso88594": CHARSET_ISO_8859_4,
  "iso88594": CHARSET_ISO_8859_4,
  "iso88595": CHARSET_ISO_8859_5,
  "iso88595": CHARSET_ISO_8859_5,
  "iso88596": CHARSET_ISO_8859_6,
  "iso88596": CHARSET_ISO_8859_6,
  "iso88596e": CHARSET_ISO_8859_6,
  "iso88596i": CHARSET_ISO_8859_6,
  "iso88597": CHARSET_ISO_8859_7,
  "iso88597": CHARSET_ISO_8859_7,
  "iso88598": CHARSET_ISO_8859_8,
  "iso88598": CHARSET_ISO_8859_8,
  "iso88598e": CHARSET_ISO_8859_8,
  "iso88598i": CHARSET_ISO_8859_8_I,
  "iso88599": CHARSET_WINDOWS_1254,
  "iso88599": CHARSET_WINDOWS_1254,
  "isoir101": CHARSET_ISO_8859_2,
  "isoir109": CHARSET_ISO_8859_3,
  "isoir110": CHARSET_ISO_8859_4,
  "isoir126": CHARSET_ISO_8859_7,
  "isoir127": CHARSET_ISO_8859_6,
  "isoir138": CHARSET_ISO_8859_8,
  "isoir144": CHARSET_ISO_8859_5,
  "isoir148": CHARSET_WINDOWS_1254,
  "isoir149": CHARSET_EUC_KR,
  "isoir157": CHARSET_ISO_8859_10,
  "isoir58": CHARSET_GBK,
  "koi": CHARSET_KOI8_R,
  "koi8": CHARSET_KOI8_R,
  "koi8r": CHARSET_KOI8_R,
  "koi8ru": CHARSET_KOI8_U,
  "koi8u": CHARSET_KOI8_U,
  "korean": CHARSET_EUC_KR,
  "ksc5601": CHARSET_EUC_KR,
  "ksc56011987": CHARSET_EUC_KR,
  "ksc56011989": CHARSET_EUC_KR,
  "l1": CHARSET_WINDOWS_1252,
  "l2": CHARSET_ISO_8859_2,
  "l3": CHARSET_ISO_8859_3,
  "l4": CHARSET_ISO_8859_4,
  "l5": CHARSET_WINDOWS_1254,
  "l6": CHARSET_ISO_8859_10,
  "l9": CHARSET_ISO_8859_15,
  "latin1": CHARSET_WINDOWS_1252,
  "latin2": CHARSET_ISO_8859_2,
  "latin3": CHARSET_ISO_8859_3,
  "latin4": CHARSET_ISO_8859_4,
  "latin5": CHARSET_WINDOWS_1254,
  "latin6": CHARSET_ISO_8859_10,
  "logical": CHARSET_ISO_8859_8_I,
  "mac": CHARSET_MACINTOSH,
  "macintosh": CHARSET_MACINTOSH,
  "ms932": CHARSET_SHIFT_JIS,
  "mskanji": CHARSET_SHIFT_JIS,
  "shiftjis": CHARSET_SHIFT_JIS,
  "sjis": CHARSET_SHIFT_JIS,
  "suneugreek": CHARSET_ISO_8859_7,
  "tis620": CHARSET_WINDOWS_874,
  "ucs2": CHARSET_UTF_16_LE,
  "unicode": CHARSET_UTF_16_LE,
  "unicode11utf8": CHARSET_UTF_8,
  "unicode20utf8": CHARSET_UTF_8,
  "unicodefeff": CHARSET_UTF_16_LE,
  "unicodefffe": CHARSET_UTF_16_BE,
  "usascii": CHARSET_WINDOWS_1252,
  "utf16": CHARSET_UTF_16_LE,
  "utf16be": CHARSET_UTF_16_BE,
  "utf16le": CHARSET_UTF_16_LE,
  "utf8": CHARSET_UTF_8,
  "visual": CHARSET_ISO_8859_8,
  "windows1250": CHARSET_WINDOWS_1250,
  "windows1251": CHARSET_WINDOWS_1251,
  "windows1252": CHARSET_WINDOWS_1252,
  "windows1253": CHARSET_WINDOWS_1253,
  "windows1254": CHARSET_WINDOWS_1254,
  "windows1255": CHARSET_WINDOWS_1255,
  "windows1256": CHARSET_WINDOWS_1256,
  "windows1257": CHARSET_WINDOWS_1257,
  "windows1258": CHARSET_WINDOWS_1258,
  "windows31j": CHARSET_SHIFT_JIS,
  "windows874": CHARSET_WINDOWS_874,
  "windows949": CHARSET_EUC_KR,
  "xcp1250" : CHARSET_WINDOWS_1250,
  "xcp1251": CHARSET_WINDOWS_1251,
  "xcp1252": CHARSET_WINDOWS_1252,
  "xcp1253": CHARSET_WINDOWS_1253,
  "xcp1254": CHARSET_WINDOWS_1254,
  "xcp1255": CHARSET_WINDOWS_1255,
  "xcp1256": CHARSET_WINDOWS_1256,
  "xcp1257": CHARSET_WINDOWS_1257,
  "xcp1258": CHARSET_WINDOWS_1258,
  "xeucjp": CHARSET_EUC_JP,
  "xgbk": CHARSET_GBK,
  "xmaccyrillic": CHARSET_X_MAC_CYRILLIC,
  "xmacroman": CHARSET_MACINTOSH,
  "xmacukrainian": CHARSET_X_MAC_CYRILLIC,
  "xsjis": CHARSET_SHIFT_JIS,
  "xunicode20utf8": CHARSET_UTF_8,
  "xxbig5": CHARSET_BIG5,
}

proc normalizeLocale(s: openArray[char]): string =
  result = ""
  for c in s:
    if uint8(c) > 0x20 and c notin {'_', '-'}:
      result &= c.toLowerAscii()

const DefaultCharset* = CHARSET_UTF_8

proc cmpCharsetPair(x: (string, Charset); k: string): int =
  cmpIgnoreCase(x[0], k)

proc getCharset*(s: string): Charset =
  ## Return a Charset from the label `s`. This function is equivalent to the
  ## standard "get an encoding from a string label" algorithm:
  ##
  ## https://encoding.spec.whatwg.org/#concept-encoding-get
  ##
  ## On failure, CHARSET_UNKNOWN is returned.
  const AsciiWhitespace = {' ', '\n', '\r', '\t', '\f'}
  let s = s.strip(chars = AsciiWhitespace)
  let i = CharsetMap.binarySearch(s, cmpCharsetPair)
  if i < 0:
    return CHARSET_UNKNOWN
  return CharsetMap[i][1]

proc getLocaleCharset*(s: string): Charset =
  ## Extract a charset from a locale. e.g. returns EUC_JP for the string
  ## LC_ALL=ja_JP.EUC_JP.
  let i = s.find('.')
  if i >= 0 and i < s.high:
    let ss = s.toOpenArray(i + 1, s.high).normalizeLocale()
    let i = NormalizedCharsetMap.binarySearch(ss, cmpCharsetPair)
    if i < 0:
      return CHARSET_UNKNOWN
    return NormalizedCharsetMap[i][1]
  # We could try to guess the charset based on the language here, like w3m
  # does.
  # However, these days it is more likely for any system to be using UTF-8
  # than any other charset, irrespective of the language. So we just assume
  # UTF-8.
  return DefaultCharset

{.pop.}
