# syncio, but without the exceptions.

{.push raises: [].}

import std/posix

import io/dynstream
import types/opt

type
  CFile {.importc: "FILE", header: "<stdio.h>", incompleteStruct.} = object
  ChaFile* = ptr CFile

let EOF {.importc, header: "<stdio.h>".}: cint
let SEEK_SET {.importc, header: "<stdio.h>".}: cint

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
proc ferror(file: ChaFile): cint
proc popen*(cmd, t: cstring): ChaFile
proc pclose*(file: ChaFile): cint
proc fseek(file: ChaFile; offset: clong; whence: cint): cint
{.pop.} # importc, header: "<stdio.h>"

proc rename*(oldname, newname: string): Opt[void] =
  if rename(cstring(oldname), cstring(newname)) != 0:
    return err()
  ok()

proc fopen*(name: string; mode: cstring): Opt[ChaFile] =
  let file = fopen(cstring(name), mode)
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

proc writeLine*(file: ChaFile): Opt[void] =
  file.write('\n')

proc writeLine*(file: ChaFile; s: openArray[char]): Opt[void] =
  ?file.write(s)
  file.writeLine()

proc writeCRLine*(file: ChaFile; s: openArray[char]): Opt[void] =
  ?file.write(s)
  ?file.write('\r')
  file.writeLine()

proc readLine*(file: ChaFile; s: var string): Opt[bool] =
  s.setLen(0)
  while (let c = file.fgetc(); c != EOF):
    let cc = cast[char](c)
    if cc == '\n':
      return ok(true)
    s &= cc
  if ferror(file) != 0:
    return err()
  ok(false)

proc readAll*(file: ChaFile; s: var string): Opt[void] =
  s = newString(4096)
  var n = 0
  while true:
    let avail = s.len - n
    let m = file.read(s.toOpenArray(n, s.len - 1))
    n += m
    if n == s.len:
      s.setLen(s.len + 4096)
    if m < avail:
      break
  s.setLen(n)
  if ferror(file) != 0:
    return err()
  ok()

proc flush*(file: ChaFile): Opt[void] =
  if fflush(file) != 0:
    return err()
  ok()

proc close*(file: ChaFile): Opt[void] {.discardable.} =
  if fclose(file) != 0:
    return err()
  ok()

proc readFile*(path: string; s: var string): Opt[void] =
  let file = ?fopen(path, "r")
  let res = file.readAll(s)
  ?file.close()
  res

proc writeFile*(path, content: string; mode: cint): Opt[void] =
  discard unlink(cstring(path))
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

when defined(gcDestructors):
  type AChaFile* = object
    p: ChaFile

  proc `=destroy`(f: var AChaFile) =
    if f.p != nil:
      discard f.p.fclose()

  proc `=wasMoved`(f: var AChaFile) =
    f.p = nil

  proc `=copy`(a: var AChaFile; b: AChaFile) {.error.} =
    discard

  proc afopen*(name: string; mode: cstring): Opt[AChaFile] =
    let p = ?fopen(name, mode)
    ok(AChaFile(p: p))

  proc afdopen*(ps: PosixStream; mode: cstring): Opt[AChaFile] =
    let p = ?ps.fdopen(mode)
    ok(AChaFile(p: p))

  proc read*(file: AChaFile; s: var openArray[uint8]): int =
    file.p.read(s)

  proc read*(file: AChaFile; s: var openArray[char]): int =
    file.p.read(s)

  proc readLine*(file: AChaFile; s: var string): Opt[bool] =
    file.p.readLine(s)

  proc write*(file: AChaFile; s: openArray[char]): Opt[void] =
    file.p.write(s)

  proc writeLine*(file: AChaFile; s: openArray[char]): Opt[void] =
    file.p.writeLine(s)

  proc writeCRLine*(file: AChaFile; s: openArray[char]): Opt[void] =
    file.p.writeCRLine(s)

  proc flush*(file: AChaFile): Opt[void] =
    file.p.flush()

  proc seek*(file: AChaFile; offset: clong): Opt[void] =
    file.p.seek(offset)

{.pop.} # raises: []
