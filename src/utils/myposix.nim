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

proc system*(cmd: cstring): cint {.importc, header: "<stdlib.h>".}

proc c_fwrite(p: pointer; size, nmemb: csize_t; f: File): csize_t {.
  importc: "fwrite", header: "<stdio.h>".}

proc fwrite*(f: File; s: openArray[char]) =
  if s.len > 0:
    discard c_fwrite(unsafeAddr s[0], 1, csize_t(s.len), f)

proc die*(s: string) {.noreturn.} =
  stderr.fwrite("cha: " & s & '\n')
  quit(1)

#TODO std's implementation is a glitched mess, better rewrite it...
proc getAppFilename*(): string =
  result = ""
  try:
    result = os.getAppFilename()
  except OSError:
    discard

{.pop.}
