# syncio, but without the exceptions.

{.push raises: [].}

import std/posix

import io/dynstream
import utils/cowstr
import utils/opt
import utils/twtstr

type
  CFile {.importc: "FILE", header: "<stdio.h>", incompleteStruct.} = object
  ChaFile* = ptr CFile

let EOF {.importc, header: "<stdio.h>".}: cint
let SEEK_SET {.importc, header: "<stdio.h>".}: cint
let chaStdin* {.importc: "stdin", header: "<stdio.h>".}: ChaFile
let chaStdout* {.importc: "stdout", header: "<stdio.h>".}: ChaFile
let chaStderr* {.importc: "stderr", header: "<stdio.h>".}: ChaFile

{.push importc, header: "<stdio.h>".}
proc fopen(pathname, mode: cstring): ChaFile
proc fdopen(fd: cint; mode: cstring): ChaFile
proc fflush(f: ChaFile): cint
proc fclose(f: ChaFile): cint
proc rename(oldname, newname: cstring): cint
proc fwrite(p: pointer; size, nmemb: csize_t; f: ChaFile): csize_t
proc fread(p: pointer; size, nmemb: csize_t; f: ChaFile): csize_t
proc fputc(c: cint; file: ChaFile): cint
proc fputs(s: cstring; file: ChaFile): cint
proc fgetc(file: ChaFile): cint
proc fgets(s: cstring; n: cint; file: ChaFile): cstring
proc ferror(file: ChaFile): cint
proc popen*(cmd, t: cstring): ChaFile
proc pclose*(file: ChaFile): cint
proc fseek(file: ChaFile; offset: clong; whence: cint): cint
proc setbuf*(stream: ChaFile; buf: cstring)
{.pop.} # importc, header: "<stdio.h>"

proc rename*(oldname, newname: Str): Opt[void] =
  if rename(oldname.toCString(), newname.toCString()) != 0:
    return err()
  ok()

proc fopen(name: string; mode: cstring): Opt[ChaFile] =
  let file = fopen(cstring(name), mode)
  if file == nil:
    return err()
  ok(file)

proc fopen(name: Str; mode: cstring): Opt[ChaFile] =
  let file = fopen(name.toCString(), mode)
  if file == nil:
    return err()
  ok(file)

proc fdopen*(ps: PosixStream; mode: cstring): Opt[ChaFile] =
  let file = fdopen(ps.fd, mode)
  if file == nil:
    ps.sclose()
    return err()
  ok(file)

# Some Nim versions can't deal with overloading cstring and openArray[char],
# better use a different name.
proc writecstr*(file: ChaFile; s: cstring): Opt[void] =
  if fputs(s, file) == EOF:
    return err()
  ok()

proc write*(file: ChaFile; s: openArray[uint8]): Opt[void] =
  if s.len > 0:
    if fwrite(unsafeAddr s[0], 1, csize_t(s.len), file) != csize_t(s.len):
      return err()
  ok()

proc write*(file: ChaFile; s: openArray[char]): Opt[void] =
  if s.len > 0:
    if fwrite(unsafeAddr s[0], 1, csize_t(s.len), file) != csize_t(s.len):
      return err()
  ok()

proc read*(file: ChaFile; s: var openArray[uint8]): int =
  if s.len > 0:
    return cast[int](fread(addr s[0], 1, csize_t(s.len), file))
  return 0

proc read*(file: ChaFile; s: var openArray[char]): int =
  if s.len > 0:
    return cast[int](fread(addr s[0], 1, csize_t(s.len), file))
  return 0

proc write*(file: ChaFile; c: char): Opt[void] =
  if fputc(cint(c), file) != cint(c):
    return err()
  ok()

proc write*(file: ChaFile; s: Str): Opt[void] =
  file.write(s.toOpenArray())

proc write*(file: ChaFile; buf: Growbuf): Opt[void] =
  file.write(buf.toOpenArray())

proc writeM*(file: ChaFile; ss: varargs[Str]): Opt[void] =
  for it in ss:
    ?file.write(it)
  ok()

proc writeLine*(file: ChaFile; ss: varargs[Str]): Opt[void] =
  for s in ss:
    ?file.write(s.toOpenArray())
  file.write('\n')

proc writeLine*(file: ChaFile; s: openArray[char]): Opt[void] =
  ?file.write(s)
  file.write('\n')

proc readLineAppend*(file: ChaFile; s: var Growbuf): Opt[bool] =
  while (let c = file.fgetc(); c != EOF):
    let cc = cast[char](c)
    if cc == '\n':
      return ok(true)
    s &= cc
  if ferror(file) != 0:
    return err()
  ok(false)

proc readLine*(file: ChaFile; s: var Growbuf): Opt[bool] =
  var i = 0
  var bufLen = cint(80)
  s.setLen(int(bufLen))
  chaMemset(s.toOpenArray(), '\n') # sentinel
  while fgets(cast[cstring](addr s[i]), bufLen - cast[cint](i), file) != nil:
    if s[^1] == '\n' or s[^2] == '\n':
      # either line is shorter than buf, then s[^1] is LF
      # or line is exactly as long as buf, then s[^1] is NUL and s[^1] is LF.
      break
    i = int(bufLen - 1)
    bufLen += 128
    s.setLen(int(bufLen))
    chaMemset(s.toOpenArray(i + 1, int(bufLen) - 1), '\n') # sentinel
  i = s.rfind('\0')
  if i >= 0: # fgets wrote a zero for us at EOL
    if i > 0 and s[i - 1] == '\n': # strip LF if any
      i = i - 1
    s.setLen(i)
    return ok(true)
  # all LFs; we have no more lines.
  s = initGrowbuf()
  if ferror(file) != 0:
    return err()
  return ok(false)

proc readLine*(file: ChaFile; s: var Str): Opt[bool] =
  var buf = initGrowbufSink(move(s))
  let res = file.readLine(buf)
  s = buf.toStr()
  res

proc readAll*(file: ChaFile; s: var Str): Opt[void] =
  var buf = initGrowbufUninit(4096)
  var n = 0
  while true:
    let avail = buf.len - n
    let m = file.read(buf.toOpenArray(n, buf.len - 1))
    n += m
    if n == buf.len:
      buf.setLenUninit(buf.len + 4096)
    if m < avail:
      break
  buf.setLen(n)
  if ferror(file) != 0:
    return err()
  s = buf.toStr()
  ok()

proc flush*(file: ChaFile): Opt[void] =
  if fflush(file) != 0:
    return err()
  ok()

proc close*(file: ChaFile): Opt[void] {.discardable.} =
  if fclose(file) != 0:
    return err()
  ok()

proc readFile*(path: cstring; s: var Str): Opt[void] =
  let file = fopen(path, "r")
  if file == nil:
    return err()
  let res = file.readAll(s)
  ?file.close()
  res

proc readFile*(path: Str; s: var Str): Opt[void] =
  readFile(path.toCString(), s)

proc writeFile*(path: cstring; content: openArray[char]; mode: cint): Opt[void] =
  discard unlink(path)
  let ps = newPosixStream(path, O_CREAT or O_WRONLY or O_EXCL, mode)
  if ps == nil:
    return err()
  let file = ?ps.fdopen("w")
  let res = file.write(content)
  ?file.close()
  res

proc seek*(file: ChaFile; offset: clong): Opt[void] =
  if fseek(file, offset, SEEK_SET) != 0:
    return err()
  ok()

type AChaFile* = distinct ChaFile

proc `=destroy`*(f: var AChaFile) =
  if cast[ChaFile](f) != nil:
    discard fclose(cast[ChaFile](f))

proc `=copy`*(a: var AChaFile; b: AChaFile) {.error.} =
  discard

proc `=sink`*(a: var AChaFile; b: AChaFile) =
  `=destroy`(a)
  cast[ptr ChaFile](addr a)[] = cast[ptr ChaFile](unsafeAddr b)[]

proc afopen*(name: Str; mode: cstring): Opt[AChaFile] =
  let p = ?fopen(name, mode)
  ok(AChaFile(p))

proc afopen*(name: string; mode: cstring): Opt[AChaFile] =
  let p = ?fopen(name, mode)
  ok(AChaFile(p))

proc afdopen*(ps: PosixStream; mode: cstring): Opt[AChaFile] =
  let p = ?ps.fdopen(mode)
  ok(AChaFile(p))

proc read*(file: AChaFile; s: var openArray[uint8]): int {.borrow.}
proc read*(file: AChaFile; s: var openArray[char]): int {.borrow.}
proc write*(file: AChaFile; s: openArray[char]): Opt[void] {.borrow.}
proc writeLine*(file: AChaFile; s: openArray[char]): Opt[void] {.borrow.}
proc writeM*(file: AChaFile; ss: varargs[Str]): Opt[void] {.borrow.}
proc flush*(file: AChaFile): Opt[void] {.borrow.}
proc seek*(file: AChaFile; offset: clong): Opt[void] {.borrow.}

proc readLine*(file: AChaFile; s: var Str): Opt[bool] =
  ChaFile(file).readLine(s)

proc readLine*(file: AChaFile; s: var Growbuf): Opt[bool] =
  ChaFile(file).readLine(s)

proc readLineAppend*(file: AChaFile; s: var Growbuf): Opt[bool] =
  ChaFile(file).readLineAppend(s)

proc writeLine*(file: AChaFile; ss: varargs[Str]): Opt[void] =
  file.writeLine(ss)

{.pop.} # raises: []
