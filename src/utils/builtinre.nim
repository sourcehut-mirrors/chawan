# Precompiled regex patterns for searching word boundaries.

import monoucha/libregexp
import utils/lrewrap

type
  BuiltinRegex* = enum
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
