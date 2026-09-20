# misc OS-specific wrappers

{.push raises: [].}

import std/posix

import utils/twtstr

# POSIX types
type SighandlerT = proc(sig: cint) {.cdecl, raises: [].}

# POSIX functions
{.push importc, header: "<stdlib.h>".}
proc free(p: pointer)
proc system*(cmd: cstring): cint
{.pop.} # importc, header: "<stdlib.h>"

{.push importc, header: "<signal.h>".}
let SIG_DFL*: SighandlerT
let SIG_IGN*: SighandlerT

proc signal*(signum: cint; handler: SighandlerT): SighandlerT
{.pop.}

{.push importc, header: "<unistd.h>".}
proc getcwd(buf: cstring; size: csize_t): cstring
{.pop.} # importc, header: "<unistd.h>"

{.push importc, header: "<time.h>".}
proc nanosleep(a1: var Timespec; a2: ptr Timespec): cint
proc strftime*(s: cstring; slen: csize_t; format: cstring; tm: ptr Tm): csize_t
{.pop.} # importc, header: "<time.h>"

# wrappers
proc realPath(path: string): string =
  let p = realpath(cstring(path), nil)
  if p == nil:
    return ""
  var s = $p
  free(p)
  move(s)

proc getcwd*(): string =
  var s = newString(4096)
  let cs = getcwd(cstring(s), csize_t(s.len))
  if cs == nil:
    return ""
  $cs

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

proc fileExists*(s: string): bool =
  var stats {.noinit.}: Stat
  stat(cstring(s), stats) == 0 and S_ISREG(stats.st_mode)

proc dirExists*(s: string): bool =
  var stats {.noinit.}: Stat
  stat(cstring(s), stats) == 0 and S_ISDIR(stats.st_mode)

proc symlinkExists*(s: string): bool =
  var stats {.noinit.}: Stat
  stat(cstring(s), stats) == 0 and S_ISLNK(stats.st_mode)

proc parentDir*(s: string): string =
  s.untilLast('/')

proc sleep*(millis: int) =
  var duration: Timespec
  duration.tv_sec = Time(millis div 1000)
  duration.tv_nsec = typeof(duration.tv_nsec)((millis mod 1000) * 1_000_000)
  discard nanosleep(duration, nil)

proc normalizedPath*(s: string): string =
  var res = newStringOfCap(s.len)
  var first = true
  for name in s.split('/'):
    if name == ".." and res.len > 0: # one dir up
      if res.len > 0 and res[^1] == '/':
        res.setLen(res.high)
      let i = res.rfind('/')
      if i < 0:
        res = ""
        first = true
      else:
        res.setLen(i + 1)
      continue
    if not first and (res.len == 0 or res[^1] != '/'):
      res &= '/'
    if name != "." and name != "":
      res &= name
    first = false
  move(res)

proc `/`*(a, b: string): string =
  if a.len == 0:
    return normalizedPath(b)
  normalizedPath(a & '/' & b)

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

type QuoteState* = enum
  qsNormal, qsDoubleQuoted, qsSingleQuoted

proc quoteFile*(file: openArray[char]; qs: QuoteState): string =
  var s = newStringOfCap(file.len)
  for c in file:
    case c
    of '$', '`', '"', '\\':
      if qs != qsSingleQuoted:
        s &= '\\'
    of '\'':
      if qs == qsSingleQuoted:
        s &= "'\\'" # then re-open the quote by appending c
      elif qs == qsNormal:
        s &= '\\'
      # double-quoted: append normally
    of AsciiAlphaNumeric, '_', '.', ':', '/':
      discard # no need to quote
    elif qs == qsNormal:
      s &= '\\'
    s &= c
  move(s)

proc quoteShellPosix*(file: openArray[char]): string =
  var res = newStringOfCap(file.len + 2)
  res &= '\''
  res &= quoteFile(file, qsSingleQuoted)
  res &= '\''
  move(res)

{.pop.} # raises: []
