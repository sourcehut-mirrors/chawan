# misc OS-specific wrappers

{.push raises: [].}

import std/os
import std/posix

import utils/twtstr

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

type SighandlerT = proc(sig: cint) {.cdecl, raises: [].}

let SIG_DFL* {.importc, header: "<signal.h>".}: SighandlerT
let SIG_IGN* {.importc, header: "<signal.h>".}: SighandlerT

proc signal*(signum: cint; handler: SighandlerT): SighandlerT {.
  importc, header: "<signal.h>".}

let cmdLine {.importc, global.}: cstringArray
let cmdCount {.importc, global.}: cint

proc getArgvCString*(i: int): cstring =
  assert i >= 0 and i < cmdCount
  cmdLine[i]

proc getArgv*(i: int): string =
  $getArgvCString(i)

proc getArgvCount*(): int =
  int(cmdCount)

proc basename*(s: cstring): cstring =
  var i = 0
  var j = 0
  while (let c = s[i]; c != '\0'):
    if c == '/':
      j = i + 1
    inc i
  return cast[cstring](unsafeAddr s[j])

iterator getArgvIter*(): cstring =
  for i in 1 ..< getArgvCount():
    yield getArgvCString(i)

proc readlink(path: cstring; buf: cstring; buflen: csize_t): int {.
  importc, header: "<unistd.h>".}

proc readLink*(s: string): string =
  var res = newString(1024)
  var len = readlink(cstring(s), cstring(res), csize_t(res.len))
  if len < 0 or len == res.len:
    return ""
  res.setLen(int(len))
  move(res)

proc getAppFilename*(): string =
  var res = ""
  when defined(linux):
    res = readLink("/proc/self/exe")
  elif defined(solaris):
    res = readLink("/proc/" & $getpid() & "/path/a.out")
  if res.len == 0:
    var a0 = getArgv(0)
    if a0.len > 0 and a0[0] == '/': # absolute
      res = move(a0)
    else: # relative
      if '/' notin a0: # basename only; try searching PATH
        for it in getEnvEmpty("PATH").split(':'):
          var rp = realPath(it / a0)
          if fileExists(rp):
            res = move(rp)
            break
      if res.len == 0:
        # not in path; return ./$0 and hope for the best
        res = getcwd() / a0
  realPath(res)

{.pop.}
