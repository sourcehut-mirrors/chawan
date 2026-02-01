{.push raises: [].}

from std/strutils import
  split,
  strip

import std/posix

import io/dynstream
import types/opt
import utils/sandbox
import utils/twtstr

import ../protocol/lcgi

{.passc: "-fno-strict-aliasing".}
{.passl: "-fno-strict-aliasing".}

{.push header: """
#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_LINEAR
#define STBI_NO_STDIO
/* #define STBI_NO_JPEG
 * #define STBI_NO_PNG
 * #define STBI_NO_BMP
 */
#define STBI_NO_PSD
#define STBI_NO_TGA
/* #define STBI_NO_GIF */
#define STBI_NO_HDR
#define STBI_NO_PIC
#define STBI_NO_PNM /* (.ppm and .pgm) */
#include "stb_image.h"
""".}

type stbi_io_callbacks {.importc.} = object
  read: proc(user: pointer; data: ptr char; size: cint): cint {.cdecl.}
  skip: proc(user: pointer; n: cint) {.cdecl.}
  eof: proc(user: pointer): cint {.cdecl.}

proc stbi_load_from_callbacks(clbk: ptr stbi_io_callbacks; user: pointer;
  x, y, channels_in_file: var cint; desired_channels: cint):
  ptr uint8 {.importc.}

proc stbi_info_from_callbacks(clbk: ptr stbi_io_callbacks; user: pointer;
  x, y, comp: var cint): cint {.importc.}

proc stbi_failure_reason(): cstring {.importc.}

proc stbi_image_free(retval_from_stbi_load: pointer) {.importc.}

{.pop.}

type StbiUser = object
  atEof: bool

const STDIN_FILENO = 0
const STDOUT_FILENO = 1

proc myRead(user: pointer; data: ptr char; size: cint): cint {.cdecl.} =
  var n = cint(0)
  while n < size:
    let i = read(STDIN_FILENO, addr cast[ptr UncheckedArray[char]](data)[n],
      int(size - n))
    if i == 0:
      cast[ptr StbiUser](user)[].atEof = true
      break
    n += cint(i)
  return n

proc mySkip(user: pointer; size: cint) {.cdecl.} =
  var data: array[4096, uint8]
  var n = cint(0)
  while n < size:
    let i = read(STDIN_FILENO, addr data[0], min(int(size - n), data.len))
    if i == 0:
      cast[ptr StbiUser](user)[].atEof = true
      break
    n += cint(i)

proc myEof(user: pointer): cint {.cdecl.} =
  return cint(cast[ptr StbiUser](user)[].atEof)

type stbi_write_func = proc(context, data: pointer; size: cint) {.cdecl.}

{.push header: """
#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STIBW_NO_STDIO
#include "stb_image_write.h"
""".}
proc stbi_write_png_to_func(fun: stbi_write_func; context: pointer;
  w, h, comp: cint; data: pointer; stride_in_bytes: cint) {.importc.}
proc stbi_write_bmp_to_func(fun: stbi_write_func; context: pointer;
  w, h, comp: cint; data: pointer) {.importc.}
proc stbi_write_jpg_to_func(fun: stbi_write_func; context: pointer;
  w, h, comp: cint; data: pointer; quality: cint) {.importc.}
{.pop.}

proc writeAll(data: pointer; size: int) =
  var n = 0
  while n < size:
    let i = write(STDOUT_FILENO, addr cast[ptr UncheckedArray[uint8]](data)[n],
      int(size) - n)
    assert i >= 0
    n += i

proc myWriteFunc(context, data: pointer; size: cint) {.cdecl.} =
  writeAll(data, int(size))

proc puts(s: string) =
  if s.len > 0:
    writeAll(unsafeAddr s[0], s.len)

proc main() =
  let f = getEnvEmpty("MAPPED_URI_SCHEME").after('+')
  case getEnvEmpty("MAPPED_URI_PATH")
  of "decode":
    if f notin ["jpeg", "gif", "bmp", "png", "x-unknown"]:
      cgiDie(ceInternalError, "unknown format " & f)
    enterNetworkSandbox()
    var user = StbiUser()
    var x: cint
    var y: cint
    var channels_in_file: cint
    var clbk = stbi_io_callbacks(
      read: myRead,
      skip: mySkip,
      eof: myEof
    )
    var infoOnly = false
    for hdr in getEnvEmpty("REQUEST_HEADERS").split('\n'):
      let v = hdr.after(':').strip()
      if hdr.until(':') == "Cha-Image-Info-Only":
        infoOnly = v == "1"
        break
    if infoOnly:
      if stbi_info_from_callbacks(addr clbk, addr user, x, y,
          channels_in_file) == 1:
        puts("Cha-Image-Dimensions: " & $x & "x" & $y & "\n\n")
        quit(0)
      else:
        cgiDie(ceInternalError, stbi_failure_reason())
    let p = stbi_load_from_callbacks(addr clbk, addr user, x, y,
      channels_in_file, 4)
    if p == nil:
      cgiDie(ceInternalError, stbi_failure_reason())
    else:
      puts("Cha-Image-Dimensions: " & $x & "x" & $y & "\n\n")
      writeAll(p, x * y * 4)
      stbi_image_free(p)
  of "encode":
    if f notin ["png", "bmp", "jpeg"]:
      cgiDie(ceInternalError, "unknown format " & f)
    let headers = getEnvEmpty("REQUEST_HEADERS")
    var quality = cint(50)
    var width = cint(0)
    var height = cint(0)
    for hdr in headers.split('\n'):
      case hdr.until(':')
      of "Cha-Image-Dimensions":
        let s = hdr.after(':').strip().split('x')
        let w = parseUInt32(s[0], allowSign = false)
        let h = parseUInt32(s[1], allowSign = false)
        if w.isErr or h.isErr:
          cgiDie(ceInternalError, "wrong dimensions")
        width = cint(w.get)
        height = cint(h.get)
      of "Cha-Image-Quality":
        let s = hdr.after(':').strip()
        let q = parseUInt32(s, allowSign = false).get(101)
        if q < 1 or 100 < q:
          cgiDie(ceInternalError, "wrong quality")
        quality = cint(q)
    let ps = newPosixStream(STDIN_FILENO)
    let src = ps.readLoopOrMmap(width * height * 4)
    if src == nil:
      cgiDie(ceInternalError, "failed to read input")
    enterNetworkSandbox() # don't swallow stat
    puts("Cha-Image-Dimensions: " & $width & 'x' & $height & "\n\n")
    let p = src.p
    case f
    of "png":
      stbi_write_png_to_func(myWriteFunc, nil, cint(width), cint(height), 4, p,
        0)
    of "bmp":
      stbi_write_bmp_to_func(myWriteFunc, nil, cint(width), cint(height), 4, p)
    of "jpeg":
      stbi_write_jpg_to_func(myWriteFunc, nil, cint(width), cint(height), 4, p,
        quality)
    deallocMem(src)
  else:
    cgiDie(ceInternalError, "not implemented")

main()

{.pop.} # raises: []
