# misc OS-specific wrappers

{.push raises: [].}

import std/os
import std/posix
import std/strutils

import utils/twtstr

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

proc free(p: pointer) {.importc, header: "<stdlib.h>".}

proc realPath(path: string): string =
  let p = realpath(cstring(path), nil)
  if p == nil:
    return ""
  var s = $p
  free(p)
  move(s)

# std's implementation is a glitched mess, so we don't use it.
proc js_exepath(buffer: cstring; size: var csize_t): cint {.importc.}

let PATH_MAX {.importc, header: "<limits.h>".}: csize_t

proc getAppFilename*(): string =
  var s = newString(PATH_MAX)
  var len = csize_t(s.len)
  # let QJS do the job for us
  # this should work on Linux and macOS
  if js_exepath(cstring(s), len) == 0:
    s.setLen(len)
    return move(s)
  # QJS died; try to find ourselves anyway
  s = ""
  let a0 = paramStr(0)
  if a0.len > 0 and a0[0] == '/':
    return realPath(a0)
  let cwd = getcwd()
  if '/' in a0:
    # probably a relative path...
    return realPath(cwd / a0)
  # try searching PATH
  for it in getEnvEmpty("PATH").split(':'):
    var rp = realPath(it / a0)
    if fileExists(rp):
      return move(rp)
  # welp.  return ./$0 and hope for the best
  cwd / a0

{.pop.}
