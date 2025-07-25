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

proc write*(file: ChaFile; s: openArray[char]): Opt[void] =
  if s.len > 0:
    if fwrite(unsafeAddr s[0], 1, csize_t(s.len), file) != csize_t(s.len):
      return err()
  ok()

proc read*(file: ChaFile; s: var openArray[char]): int =
  if s.len > 0:
    return cast[int](fread(addr s[0], 1, csize_t(s.len), file))
  return 0

proc writeLine*(file: ChaFile; s: openArray[char]): Opt[void] =
  ?file.write(s)
  if fputc(cint('\n'), file) != cint('\n'):
    return err()
  ok()

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
  let ps = newPosixStream(path, O_CREAT or O_WRONLY or O_TRUNC, mode)
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
    return ok(AChaFile(p: p))

  proc afdopen*(ps: PosixStream; mode: cstring): Opt[AChaFile] =
    let p = ?ps.fdopen(mode)
    return ok(AChaFile(p: p))

  proc readLine*(file: AChaFile; s: var string): Opt[bool] =
    return file.p.readLine(s)

  proc writeLine*(file: AChaFile; s: openArray[char]): Opt[void] =
    return file.p.writeLine(s)

  proc seek*(file: AChaFile; offset: clong): Opt[void] =
    return file.p.seek(offset)

{.pop.} # raises: []
