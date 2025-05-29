# syncio, but without the exceptions.

{.push raises: [].}

import io/dynstream
import types/opt

type
  CFile {.importc: "FILE", header: "<stdio.h>", incompleteStruct.} = object
  ChaFile* = ptr CFile

let EOF {.importc, header: "<stdio.h>".}: cint

{.push importc, header: "<stdio.h>".}
proc fdopen(fd: cint; mode: cstring): ChaFile
proc fflush(f: ChaFile): cint
proc fclose(f: ChaFile): cint
proc rename(oldname, newname: cstring): cint
proc fwrite(p: pointer; size, nmemb: csize_t; f: ChaFile): csize_t
proc fputc(c: cint; file: ChaFile): cint
proc fgetc(file: ChaFile): cint
proc ferror(file: ChaFile): cint
{.pop.} # importc, header: "<stdio.h>"

proc rename*(oldname, newname: string): Opt[void] =
  if rename(cstring(oldname), cstring(newname)) != 0:
    return err()
  ok()

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

proc flush*(file: ChaFile): Opt[void] =
  if fflush(file) != 0:
    return err()
  ok()

proc close*(file: ChaFile): Opt[void] =
  if fclose(file) != 0:
    return err()
  ok()

{.pop.} # raises: []
