{.push raises: [].}

import std/os
import std/posix
import std/strutils

import io/dynstream
import utils/sandbox
import utils/twtstr

{.passc: "-I" & currentSourcePath().parentDir().}

{.push header: """
#define NANOSVG_IMPLEMENTATION
#define NANOSVG_ALL_COLOR_KEYWORDS
#include "nanosvg.h"
""".}
type
  NSVGimage {.importc.} = object
    width: cfloat
    height: cfloat
    shapes: ptr NSVGShape

  NSVGShape {.importc, incompleteStruct.} = object

{.push importc, cdecl.}
proc nsvgParse(input, units: cstring; dpi: cfloat): ptr NSVGimage
proc nsvgDelete(image: ptr NSVGimage)
{.pop.}

{.pop.} # nanosvg.h

{.push header: """
#define NANOSVGRAST_IMPLEMENTATION
#include "nanosvgrast.h"
""".}
type NSVGrasterizer {.incompleteStruct, importc.} = object

{.push importc, cdecl.}
proc nsvgCreateRasterizer(): ptr NSVGrasterizer
proc nsvgRasterize(r: ptr NSVGrasterizer; image: ptr NSVGimage;
  tx, ty, scale: cfloat; dst: ptr uint8; w, h, stride: cint)
proc nsvgDeleteRasterizer(r: ptr NSVGrasterizer)
{.pop.}

{.pop.} # nanosvgrast.h

proc main() =
  let os = newPosixStream(STDOUT_FILENO)
  enterNetworkSandbox()
  case getEnv("MAPPED_URI_PATH")
  of "decode":
    # Unfortunate as it is, I can't just mmap the string because nanosvg
    # wants to modify it.
    var ss = newPosixStream(STDIN_FILENO).readAll()
    let image = nsvgParse(cstring(ss), "px", 96)
    if image == nil or image.width < 0 or image.height < 0 or
        cdouble(image.width) >= cdouble(cint.high) or
        cdouble(image.height) >= cdouble(cint.high):
      os.write("Cha-Control: ConnectionError 1 decoding failed\n")
      quit(1)
    let width = cint(image.width)
    let height = cint(image.height)
    os.write("Cha-Image-Dimensions: " & $width & 'x' & $height & "\n\n")
    for hdr in getEnv("REQUEST_HEADERS").split('\n'):
      let v = hdr.after(':').strip()
      if hdr.until(':') == "Cha-Image-Info-Only" and v == "1":
        return
    if width >= 0 and height >= 0:
      let r = nsvgCreateRasterizer()
      if r == nil:
        quit(1)
      var obuf = newSeqUninit[uint8](width * height * 4)
      r.nsvgRasterize(image, 0, 0, 1, addr obuf[0], width, height, width * 4)
      discard os.writeDataLoop(obuf)
      r.nsvgDeleteRasterizer()
      image.nsvgDelete()
  else:
    os.write("Cha-Control: ConnectionError 1 not supported\n")

main()

{.pop.} # raises: []
