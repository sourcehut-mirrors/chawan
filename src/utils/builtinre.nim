# Precompiled regex patterns for searching word boundaries.

import monoucha/libregexp
import utils/lrewrap

type
  BuiltinRegex* = enum
    brWordStart = r"(?<!\w)\w"
    brViWordStart =
      # kana
      r"((?<!\p{sc=Hira})\p{sc=Hira})|((?<!\p{sc=Kana})\p{sc=Kana})|" &
      # han, hangul
      r"((?<!\p{sc=Han})\p{sc=Han})|((?<!\p{sc=Hang})\p{sc=Hang})|" &
      # other alpha & non-alpha (symbol)
      r"((?<!\w)\w)|((?<![^\p{L}\p{Z}\p{N}])[^\p{L}\p{Z}\p{N}])"
    brBigWordStart = r"(?<!\S)\S"
    brWordEnd = r"\w(?!\w)"
    brViWordEnd =
      # kana
      r"(\p{sc=Hira}(?!\p{sc=Hira}))|(\p{sc=Kana}(?!\p{sc=Kana}))|" &
      # han, hangul
      r"(\p{sc=Han}(?!\p{sc=Han}))|(\p{sc=Hang}(?!\p{sc=Hang}))|" &
      # other alpha & non-alpha (symbol)
      r"(\w(?!\w))|([^\p{L}\p{Z}\p{N}](?![^\p{L}\p{Z}\p{N}]))"
    brBigWordEnd = r"\S(?!\S)"
    brTextStart = r"\S"

  BuiltinRegexList* = ref object
    a*: array[BuiltinRegex, Regex]

proc newBuiltinRegexList*(): BuiltinRegexList =
  let flags = {LRE_FLAG_GLOBAL, LRE_FLAG_UNICODE}
  let relist = BuiltinRegexList()
  for e, it in relist.a.mpairs:
    let success = compileRegex($e, flags, it)
    assert success, it.bytecode & " in regex: " & $e
  return relist
