# Very simple canvas renderer. At the moment, it uses an undocumented binary
# protocol for reading commands, and renders it whenever stdin is closed.
# So for now, it can only really render a single frame.
#
# It uses unifont for rendering text - currently I just store it as PNG
# and read it with stbi. (TODO: try switching to a more efficient format
# like qemacs fbf.)

{.push raises: [].}

import std/algorithm
import std/posix

import io/dynstream
import io/packetreader
import types/canvastypes
import types/color
import types/path

import ../protocol/lcgi

{.passc: "-I" & currentSourcePath().untilLast('/').}

{.push header: """
#define STBI_ONLY_PNG
#define STBI_NO_STDIO
#define STBI_NO_LINEAR
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
""".}
proc stbi_load_from_memory(buffer: ptr uint8; len: cint; x, y, comp: ptr cint;
  req_comp: cint): ptr uint8
proc stbi_image_free(retval_from_stbi_load: pointer)
{.pop.}

type
  GlyphCacheItem = object
    u: uint32
    bmp: Bitmap

  Bitmap = ref object
    px: seq[RGBAColorBE]
    width: int
    height: int

proc newBitmap(width, height: int): Bitmap =
  return Bitmap(
    px: newSeq[RGBAColorBE](width * height),
    width: width,
    height: height
  )

proc setpx(bmp: Bitmap; x, y: int; color: RGBAColorBE) {.inline.} =
  bmp.px[bmp.width * y + x] = color

proc setpx(bmp: Bitmap; x, y: int; color: ARGBColor) {.inline.} =
  bmp.px[bmp.width * y + x] = rgba_be(color.r, color.g, color.b, color.a)

proc getpx(bmp: Bitmap; x, y: int): RGBAColorBE {.inline.} =
  return bmp.px[bmp.width * y + x]

proc setpxb(bmp: Bitmap; x, y: int; c: RGBAColorBE) {.inline.} =
  if c.a == 255:
    bmp.setpx(x, y, c)
  else:
    bmp.setpx(x, y, bmp.getpx(x, y).argb.blend(c.argb))

proc setpxb(bmp: Bitmap; x, y: int; c: ARGBColor) {.inline.} =
  bmp.setpxb(x, y, rgba_be(c.r, c.g, c.b, c.a))

const unifont = staticRead"res/unifont_jp-15.0.05.png"
proc loadUnifont(unifont: string): Bitmap =
  var width, height, comp: cint
  let p = stbi_load_from_memory(cast[ptr uint8](unsafeAddr unifont[0]),
    cint(unifont.len), addr width, addr height, addr comp, 4)
  let len = width * height
  let bitmap = Bitmap(
    px: cast[seq[RGBAColorBE]](newSeqUninit[uint32](len)),
    width: int(width),
    height: int(height)
  )
  copyMem(addr bitmap.px[0], p, len)
  stbi_image_free(p)
  return bitmap

# https://en.wikipedia.org/wiki/Bresenham's_line_algorithm#All_cases
proc plotLineLow(bmp: Bitmap; x1, y1, x2, y2: int; color: ARGBColor) =
  var dx = x2 - x1
  var dy = y2 - y1
  var yi = 1
  if dy < 0:
    yi = -1
    dy = -dy
  var D = 2 * dy - dx;
  var y = y1;
  for x in x1 ..< x2:
    if x < 0 or y < 0 or x >= bmp.width or y >= bmp.height:
      break
    bmp.setpxb(x, y, color)
    if D > 0:
       y = y + yi;
       D = D - 2 * dx;
    D = D + 2 * dy;

proc plotLineHigh(bmp: Bitmap; x1, y1, x2, y2: int; color: ARGBColor) =
  var dx = x2 - x1
  var dy = y2 - y1
  var xi = 1
  if dx < 0:
    xi = -1
    dx = -dx
  var D = 2 * dx - dy
  var x = x1
  for y in y1 ..< y2:
    if x < 0 or y < 0 or x >= bmp.width or y >= bmp.height:
      break
    bmp.setpxb(x, y, color)
    if D > 0:
       x = x + xi
       D = D - 2 * dy
    D = D + 2 * dx

proc plotLine(bmp: Bitmap; x1, y1, x2, y2: int; color: ARGBColor) =
  if abs(y2 - y1) < abs(x2 - x1):
    if x1 > x2:
      bmp.plotLineLow(x2, y2, x1, y1, color)
    else:
      bmp.plotLineLow(x1, y1, x2, y2, color)
  else:
    if y1 > y2:
      bmp.plotLineHigh(x2, y2, x1, y1, color)
    else:
      bmp.plotLineHigh(x1, y1, x2, y2, color)

proc plotLine(bmp: Bitmap; a, b: Vector2D; color: ARGBColor) =
  bmp.plotLine(int(a.x), int(a.y), int(b.x), int(b.y), color)

proc plotLine(bmp: Bitmap; line: Line; color: ARGBColor) =
  bmp.plotLine(line.p0, line.p1, color)

proc strokePath(bmp: Bitmap; lines: seq[Line]; color: ARGBColor) =
  for line in lines:
    bmp.plotLine(line, color)

proc isInside(windingNumber: int; fillRule: CanvasFillRule): bool =
  return case fillRule
  of cfrNonZero: windingNumber != 0
  of cfrEvenOdd: windingNumber mod 2 == 0

# Algorithm originally from SerenityOS.
proc fillPath(bmp: Bitmap; lines: PathLines; color: ARGBColor;
    fillRule: CanvasFillRule) =
  var i = 0
  var ylines: seq[LineSegment] = @[]
  for y in int(lines.miny) .. int(lines.maxy):
    for k in countdown(ylines.high, 0):
      if ylines[k].maxy < float64(y):
        ylines.del(k) # we'll sort anyways, so del is fine
    for j in i ..< lines.len:
      if lines[j].miny > float64(y):
        break
      if lines[j].maxy > float64(y):
        ylines.add(lines[j])
      inc i
    ylines.sort(cmpLineSegmentX)
    var w = if fillRule == cfrNonZero: 1 else: 0
    for k in 0 ..< ylines.high:
      let a = ylines[k]
      let b = ylines[k + 1]
      let sx = int(a.minyx)
      let ex = int(b.minyx)
      if w.isInside(fillRule) and y > 0:
        for x in sx .. ex:
          if x > 0:
            bmp.setpxb(x, y, color)
      if int(a.p0.y) != y and int(a.p1.y) != y and int(b.p0.y) != y and
          int(b.p1.y) != y and sx != ex or a.islope * b.islope < 0:
        case fillRule
        of cfrEvenOdd: inc w
        of cfrNonZero:
          if a.p0.y < a.p1.y:
            inc w
          else:
            dec w
      ylines[k].minyx += ylines[k].islope
    if ylines.len > 0:
      ylines[^1].minyx += ylines[^1].islope

proc fillRect(bmp: Bitmap; x1, y1, x2, y2: int; color: ARGBColor) =
  for y in y1 ..< y2:
    for x in x1 ..< x2:
      bmp.setpxb(x, y, color)

proc strokeRect(bmp: Bitmap; x1, y1, x2, y2: int; color: ARGBColor) =
  for x in x1 ..< x2:
    bmp.setpxb(x, y1, color)
    bmp.setpxb(x, y2, color)
  for y in y1 ..< y2:
    bmp.setpxb(x1, y, color)
    bmp.setpxb(x2, y, color)

var unifontBitmap: Bitmap = nil
var glyphCache: seq[GlyphCacheItem] = @[]
var glyphCacheI = 0
proc getCharBmp(u: uint32): Bitmap =
  # We only have the BMP.
  let u = if u <= 0xFFFF: u else: 0xFFFD
  for it in glyphCache:
    if it.u == u:
      return it.bmp
  # Unifont glyphs start at x: 32, y: 64, and are of 8x16/16x16 size
  let gx = int(32 + 16 * (u mod 0x100))
  let gy = int(64 + 16 * (u div 0x100))
  var fullwidth = false
  const white = rgba_be(255, 255, 255, 255)
  block loop:
    # hack to recognize full width characters
    for y in 0 ..< 16:
      for x in 8 ..< 16:
        if unifontBitmap.getpx(gx + x, gy + y) != white:
          fullwidth = true
          break loop
  let bmp = newBitmap(if fullwidth: 16 else: 8, 16)
  for y in 0 ..< bmp.height:
    for x in 0 ..< bmp.width:
      let c = unifontBitmap.getpx(gx + x, gy + y)
      if c != white:
        bmp.setpx(x, y, c)
  if glyphCache.len < 256:
    glyphCache.add(GlyphCacheItem(u: u, bmp: bmp))
  else:
    glyphCache[glyphCacheI] = GlyphCacheItem(u: u, bmp: bmp)
    inc glyphCacheI
    if glyphCacheI >= glyphCache.len:
      glyphCacheI = 0
  return bmp

proc drawBitmap(a, b: Bitmap; p: Vector2D; color: ARGBColor) =
  for y in 0 ..< b.height:
    for x in 0 ..< b.width:
      let ax = int(p.x) + x
      let ay = int(p.y) + y
      if ax >= 0 and ay >= y and ax < a.width and ay < a.height and
          b.getpx(x, y).a != 0:
        a.setpxb(ax, ay, color)

proc fillText(bmp: Bitmap; text: string; x, y: float64; color: ARGBColor;
    textAlign: CanvasTextAlign) =
  var w = 0f64
  var glyphs: seq[Bitmap] = @[]
  for u in text.points:
    let glyph = getCharBmp(u)
    glyphs.add(glyph)
    w += float64(glyph.width)
  var x = x
  #TODO rtl
  case textAlign
  of ctaLeft, ctaStart: discard
  of ctaRight, ctaEnd: x -= w
  of ctaCenter: x -= w / 2
  for glyph in glyphs:
    bmp.drawBitmap(glyph, Vector2D(x: x, y: y - 8), color)
    x += float64(glyph.width)

proc strokeText(bmp: Bitmap; text: string; x, y: float64; color: ARGBColor;
    textAlign: CanvasTextAlign) =
  #TODO
  bmp.fillText(text, x, y, color, textAlign)

proc main() =
  enterNetworkSandbox()
  let os = newPosixStream(STDOUT_FILENO)
  let ps = newPosixStream(STDIN_FILENO)
  if getEnvEmpty("MAPPED_URI_SCHEME") != "img-codec+x-cha-canvas":
    cgiDie(ceInternalError, "invalid scheme")
  case getEnvEmpty("MAPPED_URI_PATH")
  of "decode":
    let headers = getEnvEmpty("REQUEST_HEADERS")
    for hdr in headers.split('\n'):
      if hdr.strip() == "Cha-Image-Info-Only: 1":
        #TODO this is a hack...
        # basically, we eat & discard all data from the buffer so it gets saved
        # to a cache file. then, actually render when the pager asks us to
        # do so.
        # obviously this is highly sub-optimal; a better solution would be to
        # leave stdin open & pass down the stream id from the buffer. (but then
        # you have to save canvas output too, so it doesn't have to be
        # re-coded, and handle that case in encoders... or implement on-demand
        # multi-frame output.)
        discard os.write("\n")
        discard ps.readAll()
        quit(0)
    var cmd: PaintCommand
    var width: int
    var height: int
    ps.withPacketReader r:
      r.sread(cmd)
      if cmd != pcSetDimensions:
        cgiDie(ceInternalError, "wrong dimensions")
      r.sread(width)
      r.sread(height)
    do:
      quit(1)
    if os.writeLoop("Cha-Image-Dimensions: " & $width & "x" & $height &
        "\n\n").isErr:
      quit(1)
    let bmp = newBitmap(width, height)
    var alive = true
    while alive:
      ps.withPacketReader r:
        r.sread(cmd)
        case cmd
        of pcSetDimensions:
          alive = false
        of pcFillRect, pcStrokeRect:
          var x1, y1, x2, y2: int
          var color: ARGBColor
          r.sread(x1)
          r.sread(y1)
          r.sread(x2)
          r.sread(y2)
          r.sread(color)
          if cmd == pcFillRect:
            bmp.fillRect(x1, y1, x2, y2, color)
          else:
            bmp.strokeRect(x1, y1, x2, y2, color)
        of pcFillPath:
          var lines: PathLines
          var color: ARGBColor
          var fillRule: CanvasFillRule
          r.sread(lines)
          r.sread(color)
          r.sread(fillRule)
          bmp.fillPath(lines, color, fillRule)
        of pcStrokePath:
          var lines: seq[Line]
          var color: ARGBColor
          r.sread(lines)
          r.sread(color)
          bmp.strokePath(lines, color)
        of pcFillText, pcStrokeText:
          if unifontBitmap == nil:
            unifontBitmap = loadUnifont(unifont)
          var text: string
          var x, y: float64
          var color: ARGBColor
          var align: CanvasTextAlign
          r.sread(text)
          r.sread(x)
          r.sread(y)
          r.sread(color)
          r.sread(align)
          if cmd == pcFillText:
            bmp.fillText(text, x, y, color, align)
          else:
            bmp.strokeText(text, x, y, color, align)
      do:
        alive = false
    discard os.writeLoop(addr bmp.px[0], bmp.px.len * sizeof(bmp.px[0]))
  else:
    cgiDie(ceInternalError, "not implemented")

main()

{.pop.} # raises: []
