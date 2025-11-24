{.push raises: [].}

import std/os
import std/posix
import std/strutils

import ../protocol/lcgi

{.passc: "-I" & currentSourcePath().parentDir().}

{.push header: """
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image_resize.h"
""".}
proc stbir_resize_uint8_srgb(input_pixels: ptr uint8;
  input_w, input_h, input_stride_in_bytes: cint; output_pixels: ptr uint8;
  output_w, output_h, output_stride_in_bytes, num_channels, alpha_channel,
  flags: cint): cint {.importc.}
{.pop.}

proc main() =
  var srcWidth = cint(-1)
  var srcHeight = cint(-1)
  var dstWidth = cint(-1)
  var dstHeight = cint(-1)
  for hdr in getEnv("REQUEST_HEADERS").split('\n'):
    let k = hdr.until(':')
    if k == "Cha-Image-Target-Dimensions" or k == "Cha-Image-Dimensions":
      let v = hdr.after(':').strip()
      let s = v.split('x')
      if s.len != 2:
        cgiDie(ceInternalError, "wrong dimensions")
      let w = parseUInt32(s[0], allowSign = false).get(0)
      let h = parseUInt32(s[1], allowSign = false).get(0)
      if w == 0 or h == 0:
        cgiDie(ceInternalError, "wrong dimensions")
      if k == "Cha-Image-Target-Dimensions":
        dstWidth = cint(w)
        dstHeight = cint(h)
      else:
        srcWidth = cint(w)
        srcHeight = cint(h)
  let ps = newPosixStream(STDIN_FILENO)
  let os = newPosixStream(STDOUT_FILENO)
  let src = ps.readLoopOrMmap(int(srcWidth * srcHeight * 4))
  let dst = os.maybeMmapForSend(int(dstWidth * dstHeight * 4 + 1))
  if src == nil or dst == nil:
    cgiDie(ceInternalError, "failed to open i/o")
  dst.p[0] = uint8('\n') # for CGI
  enterNetworkSandbox()
  doAssert stbir_resize_uint8_srgb(addr src.p[0], srcWidth, srcHeight, 0,
    addr dst.p[1], dstWidth, dstHeight, 0, 4, 3, 0) != 0
  discard os.writeLoop(dst)
  deallocMem(src)
  deallocMem(dst)

main()

{.pop.} # raises: []
