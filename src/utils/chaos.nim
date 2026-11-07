# misc OS-specific wrappers

{.push raises: [].}

when NimMajor >= 2:
  import std/assertions
import std/posix

import utils/cowstr
import utils/opt
import utils/twtstr

# POSIX types
type
  SighandlerT = proc(sig: cint) {.cdecl, raises: [].}

  cptrdiff* {.importc: "ptrdiff_t", header: "<stddef.h>".} = distinct int

# POSIX functions
{.push header: "<stdlib.h>".}
proc free(p: pointer) {.importc.}
proc system*(cmd: cstring): cint {.importc.}
proc c_getenv(name: cstring): cstring {.
  header: "<stdlib.h>", importc: "getenv".}
proc c_setenv(envname, envval: cstring; overwrite: cint): cint {.
  header: "<stdlib.h>", importc: "setenv".}
proc c_unsetenv(name: cstring): cint {.header: "<stdlib.h>",
  importc: "unsetenv".}
{.pop.} # header: "<stdlib.h>"

let SIG_DFL* {.importc, header: "<signal.h>".}: SighandlerT
let SIG_IGN* {.importc, header: "<signal.h>".}: SighandlerT

{.push importc, header: "<signal.h>".}
proc signal*(signum: cint; handler: SighandlerT): SighandlerT
{.pop.}

{.push importc, header: "<unistd.h>".}
proc getcwd(buf: cstring; size: csize_t): cstring
{.pop.} # importc, header: "<unistd.h>"

{.push importc, header: "<time.h>".}
proc nanosleep(a1: var Timespec; a2: ptr Timespec): cint
proc strftime*(s: cstring; slen: csize_t; format: cstring; tm: ptr Tm): csize_t
{.pop.} # importc, header: "<time.h>"

when defined(macosx):
  proc gettimeofday(tp: var Timeval; tzp: pointer): cint {.
    importc, header: "<sys/time.h>".}

# wrappers
proc realPath(path: Str): Str =
  let p = realpath(path.toCString(), nil)
  if p == nil:
    return str("")
  var s = p.toStr()
  free(p)
  move(s)

proc getcwd*(): Str =
  var s = initGrowbufUninit(4096)
  let cs = getcwd(cast[cstring](s.p), csize_t(s.len))
  if cs == nil:
    return str("")
  cs.toStr()

let cmdLine {.importc, global.}: cstringArray
let cmdCount {.importc, global.}: cint

proc getArgvCString*(i: int): cstring =
  assert i >= 0 and i < cmdCount
  cmdLine[i]

proc getArgv*(i: int): Str =
  getArgvCString(i).toStr()

proc getArgvOrDefault*(i: int; fallback = str("")): Str =
  if i >= cmdCount:
    return fallback
  let s = getArgvCString(i)
  if s == "":
    return fallback
  s.toStr()

proc getArgvCount*(): int =
  int(cmdCount)

proc getEnvCString*(name: cstring): cstring =
  return c_getenv(name)

proc getEnvEmpty*(name: cstring; fallback = str("")): Str =
  var res = getEnvCString(name)
  if res == nil or res[0] == '\0':
    return fallback
  return res.toStr()

proc getEnvEmpty*(name: Str; fallback = str("")): Str =
  getEnvEmpty(name.toCString(), fallback)

proc setEnvCString*(name, value: cstring): Opt[void] =
  if c_setenv(name, value, 1) != 0:
    return err()
  ok()

proc setEnv*(name, value: string): Opt[void] =
  setEnvCString(cstring(name), cstring(value))

proc setEnv*(name: cstring; value: Str): Opt[void] =
  setEnvCString(name, value.toCString())

proc setEnv*(name, value: Str): Opt[void] =
  setEnv(name.toCString(), value)

proc unsetEnvCString*(name: cstring) =
  discard c_unsetenv(name)

proc unsetEnv*(name: string) =
  unsetEnvCString(cstring(name))

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

proc readLink*(s: Str): Str =
  var res = initGrowbufUninit(1024)
  var len = readlink(s.toCString(), cast[cstring](res.p), csize_t(res.len))
  if len < 0 or len == res.len:
    return str("")
  res.setLen(int(len))
  res.toStr()

proc fileExists*(s: cstring): bool =
  var stats {.noinit.}: Stat
  stat(s, stats) == 0 and S_ISREG(stats.st_mode)

proc fileExists*(s: Str): bool =
  fileExists(s.toCString())

proc dirExists*(s: Str): bool =
  var stats {.noinit.}: Stat
  stat(s.toCString(), stats) == 0 and S_ISDIR(stats.st_mode)

proc symlinkExists*(s: Str): bool =
  var stats {.noinit.}: Stat
  stat(s.toCString(), stats) == 0 and S_ISLNK(stats.st_mode)

proc sleep*(millis: int) =
  var duration: Timespec
  duration.tv_sec = Time(millis div 1000)
  duration.tv_nsec = typeof(duration.tv_nsec)((millis mod 1000) * 1_000_000)
  discard nanosleep(duration, nil)

proc normalizedPath*(s: Str): Str =
  var res = initGrowbufOfCap(s.len)
  var first = true
  for name in s.split('/'):
    if name == ".." and res.len > 0: # one dir up
      if res.len > 0 and res[^1] == '/':
        res.setLen(res.high)
      let i = res.toOpenArray().rfind('/')
      if i < 0:
        res.setLen(0)
        first = true
      else:
        res.setLen(i + 1)
      continue
    if not first and (res.len == 0 or res[^1] != '/'):
      res &= '/'
    if name != "." and name != "":
      res &= name
    first = false
  res.toStr()

proc `/`*(a, b: Str): Str =
  if a.len == 0:
    return normalizedPath(b)
  normalizedPath(initStrM(a, '/', b))

proc getAppFilename*(): Str =
  var res = str("")
  when defined(linux):
    res = readLink(str("/proc/self/exe"))
  elif defined(solaris):
    res = readLink(initStrM("/proc/", getpid().toStr(), "/path/a.out"))
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

proc quoteFile*(file: Str; qs: QuoteState): Str =
  var s = initGrowbufOfCap(file.len)
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
  s.toStr()

proc quoteShellPosix*(file: Str): Str =
  initStrM('\'', quoteFile(file, qsSingleQuoted), '\'')

proc getUnixTime(): tuple[sec, usec: int64] =
  when defined(macosx):
    var tv {.noinit.}: Timeval
    if gettimeofday(tv, nil) < 0:
      return (0'i64, 0'i64)
    return (int64(tv.tv_sec), int64(tv.tv_usec))
  else:
    var ts {.noinit.}: Timespec
    if clock_gettime(CLOCK_REALTIME, ts) < 0:
      return (0'i64, 0'i64)
    return (int64(ts.tv_sec), int64(ts.tv_nsec) div 1000)

proc getUnixMillisFloat*(): float64 =
  let time = getUnixTime()
  float64(time.sec) * 1000 + float64(time.usec div 100) / 10

proc getUnixMillis*(): int64 =
  let time = getUnixTime()
  time.sec * 1000 + time.usec div 1000

proc getUnixSeconds*(): int64 =
  let time = getUnixTime()
  time.sec

proc formatUnixSeconds*(n: int64; fmt: cstring): Str =
  #TODO if new enough, send time instead of year
  var time = Time(n)
  let tm = localtime(time)
  if tm == nil:
    return str("")
  var buf: array[64, char]
  let n = strftime(cast[cstring](addr buf[0]), csize_t(buf.len), fmt, tm)
  initStr(buf.toOpenArray(0, int(n) - 1))

proc expandPath*(path: Str): Str =
  if path.len > 0 and path[0] == '~':
    if path.len == 1:
      return getEnvEmpty("HOME")
    if path[1] == '/':
      var res = getEnvEmpty("HOME")
      res &= path.toOpenArray(1, path.high)
      return move(res)
    let usr = path.until({'/'}, 1)
    let p = getpwnam(usr.toCString())
    if p != nil and p.pw_dir != nil:
      var res = initGrowbufM(p.pw_dir, '/')
      res &= path.toOpenArray(usr.len, path.high)
      return res.toStr()
  return path

{.pop.} # raises: []
