# misc OS-specific wrappers

{.push raises: [].}

import std/os

# std's getcwd binding uses int for size, but it's size_t...
proc my_getcwd(buf: cstring; size: csize_t): cstring {.
  importc: "getcwd", header: "<unistd.h>".}

proc getcwd*(): string =
  var s = newString(4096)
  let cs = my_getcwd(cstring(s), csize_t(s.len))
  if cs == nil:
    return ""
  $cs

#TODO std's implementation is a glitched mess, better rewrite it...
proc getAppFilename*(): string =
  result = ""
  try:
    result = os.getAppFilename()
  except OSError:
    discard

{.pop.}
