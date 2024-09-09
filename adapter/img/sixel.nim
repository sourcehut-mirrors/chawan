# Sixel codec. I'm lazy, so no decoder yet.
#
# "Regular" mode just encodes the image as a sixel image, with
# Cha-Image-Sixel-Palette colors. If that isn't given, it's set
# according to Cha-Image-Quality.
#
# The encoder also has a "half-dump" mode, where the output is modified as
# follows:
#
# * DCS q set-raster-attributes is omitted.
# * 32-bit binary number in header indicates length of following palette.
# * A lookup table is appended to the file end, which includes (height + 5) / 6
#   32-bit binary numbers indicating the start index of every 6th row.
#
# This way, the image can be vertically cropped in ~constant time.

import std/algorithm
import std/options
import std/os
import std/posix
import std/strutils

import io/dynstream
import types/color
import utils/sandbox
import utils/twtstr

proc puts(os: PosixStream; s: string) =
  os.sendDataLoop(s)

proc die(s: string) {.noreturn.} =
  let os = newPosixStream(STDOUT_FILENO)
  os.puts(s)
  quit(1)

const DCSSTART = "\eP"
const ST = "\e\\"

proc setU32BE(s: var string; n: uint32; at: int) =
  s[at] = char((n shr 24) and 0xFF)
  s[at + 1] = char((n shr 16) and 0xFF)
  s[at + 2] = char((n shr 8) and 0xFF)
  s[at + 3] = char(n and 0xFF)

proc putU32BE(s: var string; n: uint32) =
  s &= char((n shr 24) and 0xFF)
  s &= char((n shr 16) and 0xFF)
  s &= char((n shr 8) and 0xFF)
  s &= char(n and 0xFF)

type Node {.acyclic.} = ref object
  c: RGBColor
  n: uint32
  r: uint32
  g: uint32
  b: uint32
  idx: int
  children: array[8, Node]

proc getIdx(c: RGBColor; level: int): uint8 {.inline.} =
  let sl = 7 - level
  let idx = (((c.r shr sl) and 1) shl 2) or
    (((c.g shr sl) and 1) shl 1) or
    (c.b shr sl) and 1
  return idx

type TrimMap = array[7, seq[Node]]

# Insert a node into the octree.
# Returns true if a new leaf was inserted, false otherwise.
proc insert(parent: Node; c: RGBColor; trimMap: var TrimMap; level = 0;
    n = 1u32): bool =
  # max level is 7, because we only have ~6.5 bits (0..100, inclusive)
  # (it *is* 0-indexed, but one extra level is needed for the final leaves)
  assert level < 8
  let idx = c.getIdx(level)
  let old = parent.children[idx]
  if old == nil:
    if level == 7:
      parent.children[idx] = Node(
        c: c,
        n: n,
        r: uint32(c.r) * n,
        g: uint32(c.g) * n,
        b: uint32(c.b) * n
      )
      return true
    else:
      let container = Node(idx: -1)
      parent.children[idx] = container
      trimMap[level].add(container)
      return container.insert(c, trimMap, level + 1, n)
  elif old.idx != -1:
    if old.c == c:
      old.n += n
      old.r += uint32(c.r) * n
      old.g += uint32(c.g) * n
      old.b += uint32(c.b) * n
      return false
    else:
      let container = Node(idx: -1)
      parent.children[idx] = container
      let nlevel = level + 1
      container.children[old.c.getIdx(nlevel)] = old # skip an alloc :)
      trimMap[level].add(container)
      return container.insert(c, trimMap, nlevel, n)
  else:
    return old.insert(c, trimMap, level + 1, n)

proc trim(trimMap: var TrimMap; K: var uint) =
  var node: Node = nil
  for i in countdown(trimMap.high, 0):
    if trimMap[i].len > 0:
      node = trimMap[i].pop()
      break
  assert node != nil
  var r = 0u32
  var g = 0u32
  var b = 0u32
  var n = 0u32
  var k = K + 1
  for child in node.children.mitems:
    if child != nil:
      r += child.r
      g += child.g
      b += child.b
      n += child.n
      child = nil
      dec k
  node.idx = 0
  node.c = rgb(uint8(r div n), uint8(g div n), uint8(b div n))
  node.r = r
  node.g = g
  node.b = b
  node.n = n
  K = k

proc getPixel(img: seq[RGBAColorBE]; m: int; bgcolor: ARGBColor): RGBColor
    {.inline.} =
  let c0 = img[m].toARGBColor()
  if c0.a != 255:
    let c1 = bgcolor.blend(c0)
    return RGBColor(uint32(c1).fastmul(100))
  return RGBColor(uint32(c0).fastmul(100))

proc quantize(img: seq[RGBAColorBE]; bgcolor: ARGBColor; outk: var uint): Node =
  let root = Node(idx: -1)
  # number of leaves
  let palette = outk
  var K = 0u
  # map of non-leaves for each level.
  # (note: somewhat confusingly, this actually starts at level 1.)
  var trimMap: array[7, seq[Node]]
  # batch together insertions of color runs
  var pc = img.getPixel(0, bgcolor)
  var pn = 1u32
  for i in 1 ..< img.len:
    let c = img.getPixel(i, bgcolor)
    if pc != c or i == img.len:
      K += uint(root.insert(pc, trimMap, n = pn))
      pc = c
      pn = 0
    inc pn
    while K > palette:
      trimMap.trim(K)
  outk = K
  return root

proc flatten(node: Node; cols: var seq[Node]) =
  if node.idx != -1:
    cols.add(node)
  else:
    for child in node.children:
      if child != nil:
        child.flatten(cols)

proc flatten(node: Node; outs: var string; palette: uint): seq[Node] =
  var cols = newSeqOfCap[Node](palette)
  node.flatten(cols)
  # try to set the most common colors as the smallest numbers (so we write less)
  cols.sort(proc(a, b: Node): int = cmp(a.n, b.n), order = Descending)
  for n, it in cols:
    let n = n + 1 # skip 0 - that's transparent
    let c = it.c
    # 2 is RGB
    outs &= '#' & $n & ";2;" & $c.r & ';' & $c.g & ';' & $c.b
    it.idx = n
  return cols

type
  DitherDiff = tuple[r, g, b: int32]

  Dither = object
    d1: seq[DitherDiff]
    d2: seq[DitherDiff]

proc getColor(nodes: seq[Node]; c: RGBColor; diff: var DitherDiff): Node =
  var child: Node = nil
  var minDist = uint32.high
  for node in nodes:
    let ic = node.c
    let rd = int32(c.r) - int32(ic.r)
    let gd = int32(c.g) - int32(ic.g)
    let bd = int32(c.b) - int32(ic.b)
    let d = uint32(abs(rd)) + uint32(abs(gd)) + uint32(abs(bd))
    if d < minDist:
      minDist = d
      child = node
      diff = (rd, gd, bd)
      if ic == c:
        break
  return child

proc getColor(node: Node; c: RGBColor; nodes: seq[Node]; diff: var DitherDiff;
    level: int): Node =
  let idx = int(c.getIdx(level))
  var child = node.children[idx]
  let nlevel = level + 1
  if child == nil:
    let child = nodes.getColor(c, diff)
    node.children[idx] = child
    return child
  if node.idx != -1:
    let ic = node.c
    let r = int32(c.r) - int32(ic.r)
    let g = int32(c.g) - int32(ic.g)
    let b = int32(c.b) - int32(ic.b)
    diff = (r, g, b)
    return node
  return child.getColor(c, nodes, diff, nlevel)

proc getColor(node: Node; c: RGBColor; nodes: seq[Node]; diff: var DitherDiff):
    int =
  if nodes.len < 63:
    # Octree-based nearest neighbor search creates really ugly artifacts
    # with a low amount of colors, which is exactly the case where
    # linear search is still acceptable.
    #
    # 64 is the first power of 2 that gives OK results on my test images
    # with the octree; we must also subtract one for transparency.
    #
    # (In practice, I assume no sane terminal would pick a palette (> 2)
    # that isn't a multiple of 4, so really only 16 is relevant here.
    # Even that is quite rare, unless you misconfigure XTerm - or
    # have a hardware terminal, but those didn't have private color
    # registers in the first place. I do like the aesthetics, though;
    # would be a shame if it didn't work :P)
    return nodes.getColor(c, diff).idx
  return node.getColor(c, nodes, diff, 0).idx

proc correctDither(c: RGBColor; x: int; dither: Dither): RGBColor =
  let (rd, gd, bd) = dither.d1[x + 1]
  let pr = (uint32(c) shr 12) and 0xFF0
  let pg = (uint32(c) shr 4) and 0xFF0
  let pb = (uint32(c) shl 4) and 0xFF0
  {.push overflowChecks: off.}
  let r = uint8(uint32(clamp(int32(pr) + rd, 0, 1600)) shr 4)
  let g = uint8(uint32(clamp(int32(pg) + gd, 0, 1600)) shr 4)
  let b = uint8(uint32(clamp(int32(pb) + bd, 0, 1600)) shr 4)
  {.pop.}
  return rgb(r, g, b)

proc fs(dither: var Dither; x: int; d: DitherDiff) =
  let x = x + 1 # skip first bounds check
  template at(p, mul: untyped) =
    var (rd, gd, bd) = p
    p = (rd + d.r * mul, gd + d.g * mul, bd + d.b * mul)
  {.push overflowChecks: off.}
  at(dither.d1[x + 1], 7)
  at(dither.d2[x - 1], 3)
  at(dither.d2[x], 5)
  at(dither.d2[x + 1], 1)
  {.pop.}

type
  SixelBand = seq[ptr SixelChunk]

  SixelChunk = object
    x: int
    c: int
    nrow: uint
    data: seq[uint8]

# data is binary 0..63; the output is the final ASCII form.
proc compressSixel(outs: var string; band: SixelBand) =
  var x = 0
  for chunk in band:
    outs &= '#'
    outs &= $chunk.c
    let diff = chunk.x - x
    if diff > 3:
      outs &= '!' & $diff & '?'
    else:
      for i in 0 ..< diff:
        outs &= '?'
    x = chunk.x + chunk.data.len
    var n = 0
    var c = char(0)
    for u in chunk.data:
      let cc = char(u + 0x3F)
      if c != cc:
        if n > 3:
          outs &= '!' & $n & c
        else: # for char(0) n is also 0, so it is ignored.
          for i in 0 ..< n:
            outs &= c
        c = cc
        n = 0
      inc n
    if n > 3:
      outs &= '!' & $n & c
    else:
      for i in 0 ..< n:
        outs &= c

proc createBands(bands: var seq[SixelBand]; activeChunks: seq[ptr SixelChunk]) =
  for chunk in activeChunks:
    let x = chunk.x
    let ex = chunk.x + chunk.data.len
    var found = false
    for band in bands.mitems:
      if band[0].x > ex:
        band.insert(chunk, 0)
        found = true
        break
      elif band[^1].x + band[^1].data.len <= x:
        band.add(chunk)
        found = true
        break
    if not found:
      bands.add(@[chunk])

proc encode(img: seq[RGBAColorBE]; width, height, offx, offy, cropw: int;
    halfdump: bool; bgcolor: ARGBColor; palette: int) =
  # reserve one entry for transparency
  # (this is necessary so that cropping works properly when the last
  # sixel would not fit on the screen, and also for images with !(height % 6).)
  assert palette > 2
  var palette = uint(palette - 1)
  let node = img.quantize(bgcolor, palette)
  # prelude
  var outs = "Cha-Image-Dimensions: " & $width & 'x' & $height & "\n\n"
  let preludeLenPos = outs.len
  if halfdump: # reserve size for prelude
    outs &= "\0\0\0\0"
  else:
    outs &= DCSSTART & 'q'
    # set raster attributes
    outs &= "\"1;1;" & $width & ';' & $height
  let nodes = node.flatten(outs, palette)
  if halfdump:
    # prepend prelude size
    let L = outs.len - 4 - preludeLenPos # subtract length field
    outs.setU32BE(uint32(L), preludeLenPos)
  let os = newPosixStream(STDOUT_FILENO)
  let L = width * height
  let realw = cropw - offx
  var n = offy * width
  var ymap = ""
  var totalLen = 0u32
  # add +2 so we don't have to bounds check
  var dither = Dither(
    d1: newSeq[DitherDiff](realw + 2),
    d2: newSeq[DitherDiff](realw + 2)
  )
  var chunkMap = newSeq[SixelChunk](palette)
  var activeChunks: seq[ptr SixelChunk] = @[]
  var nrow = 1u
  # buffer to 64k, just because.
  const MaxBuffer = 65546
  while true:
    if halfdump:
      ymap.putU32BE(totalLen)
    for i in 0 ..< 6:
      if n >= L:
        break
      let mask = 1u8 shl i
      var chunk: ptr SixelChunk = nil
      for j in 0 ..< realw:
        let m = n + offx + j
        let c0 = img.getPixel(m, bgcolor).correctDither(j, dither)
        var diff: DitherDiff
        let c = node.getColor(c0, nodes, diff)
        dither.fs(j, diff)
        if chunk == nil or chunk.c != c:
          chunk = addr chunkMap[c - 1]
          chunk.c = c
          if chunk.nrow < nrow:
            chunk.nrow = nrow
            chunk.x = j
            chunk.data.setLen(0)
            activeChunks.add(chunk)
          elif chunk.x > j:
            let diff = chunk.x - j
            chunk.x = j
            let olen = chunk.data.len
            chunk.data.setLen(olen + diff)
            moveMem(addr chunk.data[diff], addr chunk.data[0], olen)
            zeroMem(addr chunk.data[0], diff)
          elif chunk.data.len < j - chunk.x:
            chunk.data.setLen(j - chunk.x)
        let k = j - chunk.x
        if k < chunk.data.len:
          chunk.data[k] = chunk.data[k] or mask
        else:
          chunk.data.add(mask)
      n += width
      var tmp = move(dither.d1)
      dither.d1 = move(dither.d2)
      dither.d2 = move(tmp)
      zeroMem(addr dither.d2[0], dither.d2.len * sizeof(dither.d2[0]))
    var bands: seq[SixelBand] = @[]
    bands.createBands(activeChunks)
    let olen = outs.len
    for i in 0 ..< bands.len:
      if i > 0:
        outs &= '$'
      outs.compressSixel(bands[i])
    if n >= L:
      outs &= ST
      totalLen += uint32(outs.len - olen)
      break
    else:
      outs &= '-'
      totalLen += uint32(outs.len - olen)
      if outs.len >= MaxBuffer:
        os.sendDataLoop(outs)
        outs.setLen(0)
    inc nrow
    activeChunks.setLen(0)
  if halfdump:
    ymap.putU32BE(totalLen)
    ymap.putU32BE(uint32(ymap.len))
    outs &= ymap
  os.sendDataLoop(outs)

proc parseDimensions(s: string): (int, int) =
  let s = s.split('x')
  if s.len != 2:
    die("Cha-Control: ConnectionError 1 wrong dimensions\n")
  let w = parseUInt32(s[0], allowSign = false)
  let h = parseUInt32(s[1], allowSign = false)
  if w.isNone or w.isNone:
    die("Cha-Control: ConnectionError 1 wrong dimensions\n")
  return (int(w.get), int(h.get))

proc main() =
  enterNetworkSandbox()
  let scheme = getEnv("MAPPED_URI_SCHEME")
  let f = scheme.after('+')
  if f != "x-sixel":
    die("Cha-Control: ConnectionError 1 unknown format " & f)
  case getEnv("MAPPED_URI_PATH")
  of "decode":
    die("Cha-Control: ConnectionError 1 not implemented\n")
  of "encode":
    let headers = getEnv("REQUEST_HEADERS")
    var width = 0
    var height = 0
    var offx = 0
    var offy = 0
    var halfdump = false
    var palette = -1
    var bgcolor = rgb(0, 0, 0)
    var cropw = -1
    var quality = -1
    for hdr in headers.split('\n'):
      let s = hdr.after(':').strip()
      case hdr.until(':')
      of "Cha-Image-Dimensions":
        (width, height) = parseDimensions(s)
      of "Cha-Image-Offset":
        (offx, offy) = parseDimensions(s)
      of "Cha-Image-Crop-Width":
        let q = parseUInt32(s, allowSign = false)
        if q.isNone:
          die("Cha-Control: ConnectionError 1 wrong palette\n")
        cropw = int(q.get)
      of "Cha-Image-Sixel-Halfdump":
        halfdump = true
      of "Cha-Image-Sixel-Palette":
        let q = parseUInt16(s, allowSign = false)
        if q.isNone:
          die("Cha-Control: ConnectionError 1 wrong palette\n")
        palette = int(q.get)
      of "Cha-Image-Quality":
        let q = parseUInt16(s, allowSign = false)
        if q.isNone:
          die("Cha-Control: ConnectionError 1 wrong quality\n")
        quality = int(q.get)
      of "Cha-Image-Background-Color":
        bgcolor = parseLegacyColor0(s)
    if cropw == -1:
      cropw = width
    if palette == -1:
      if quality < 30:
        palette = 16
      elif quality < 70:
        palette = 256
      else:
        palette = 1024
    if width == 0 or height == 0:
      let os = newPosixStream(STDOUT_FILENO)
      os.sendDataLoop("Cha-Image-Dimensions: 0x0\n")
      quit(0) # done...
    let n = width * height
    var img = cast[seq[RGBAColorBE]](newSeqUninitialized[uint32](n))
    let ps = newPosixStream(STDIN_FILENO)
    ps.recvDataLoop(addr img[0], n * 4)
    img.encode(width, height, offx, offy, cropw, halfdump, bgcolor, palette)

main()
