# misc OS-specific wrappers

{.push raises: [].}

import std/os
import std/posix

proc free(p: pointer) {.importc, header: "<stdlib.h>".}

proc realPath(path: string): string =
  let p = realpath(cstring(path), nil)
  if p == nil:
    return ""
  var s = $p
  free(p)
  move(s)

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

proc getAppFilename*(): string =
  result = ""
  try:
    result = os.getAppFilename()
    # The NetBSD sysctl does not resolve symlinks.
    result = realPath(result)
  except OSError:
    discard

type SighandlerT = proc(sig: cint) {.cdecl, raises: [].}

let SIG_DFL* {.importc, header: "<signal.h>".}: SighandlerT
let SIG_IGN* {.importc, header: "<signal.h>".}: SighandlerT

proc signal*(signum: cint; handler: SighandlerT): SighandlerT {.
  importc, header: "<signal.h>".}

{.pop.}
