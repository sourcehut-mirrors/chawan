import std/unittest

import monoucha/libregexp

proc match(re, str: string): bool =
  var plen: cint
  var e = newString(64)
  let bytecode = lre_compile(plen, cstring(e), cint(e.len), cstring(re),
    csize_t(re.len), 0, nil)
  let captureCount = lre_get_capture_count(bytecode)
  var capture = newSeq[ptr uint8](captureCount * 2)
  let res = lre_exec(addr capture[0], bytecode,
    cast[ptr uint8](cstring(str)), 0, cint(str.len), 3, nil)
  res == 1

test "regex only":
  check match(".*", "whatever")
  check match(".*", "")

test r"\b":
  check not "\bth\b".match("Weather")
