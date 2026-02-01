# Sixel codec. I'm lazy, so no decoder yet.
#
# "Regular" mode just encodes the image as a sixel image, with
# Cha-Image-Sixel-Palette colors. If that isn't given, it's set
# according to Cha-Image-Quality.
#
# The encoder also has a "half-dump" mode, where a binary lookup table
# is appended to the file end to allow vertical cropping in ~constant
# time.
#
# This table is an array of 32-bit big-endian integers indicating the
# start index of every sixel, and finally a 32-bit big-endian integer
# indicating the number of sixels in the image.
#
# Warning: we intentionally leak the final octree. Be careful if you
# want to integrate this module into a larger program. Deallocation
# would (currently) look like:
#
# * Free the leaves first, since they might have been inserted more
#   than once (iterate over "nodes" seq)
# * Recurse to free the parent nodes (start from root, dealloc each
#   node where idx == -1)

{.push raises: [].}

from std/strutils import
  split,
  strip

import std/algorithm
import std/posix

import types/color

import ../protocol/lcgi

proc puts(os: PosixStream; s: string) =
  doAssert os.writeLoop(s).isOk

const DCS = "\eP"
const ST = "\e\\"

proc putU32BE(s: var string; n: uint32) =
  s &= char((n shr 24) and 0xFF)
  s &= char((n shr 16) and 0xFF)
  s &= char((n shr 8) and 0xFF)
  s &= char(n and 0xFF)

type
  Node = ptr NodeObj

  NodeObj = object
    idx: int # -1: parent, anything else: leaf
    u: NodeUnion

  NodeUnion {.union.} = object
    leaf: NodeLeaf
    children: NodeChildren

  NodeChildren = array[8, Node]

  NodeLeaf = object
    c: RGBColor
    n: uint32
    r: uint32
    g: uint32
    b: uint32

proc getIdx(c: RGBColor; level: int): uint8 {.inline.} =
  let c = uint32(c) and (0x80808080u32 shr uint32(level))
  return uint8((c shr (21 - level)) or
    (c shr (14 - level)) or
    (c shr (7 - level)))

type TrimMap = array[7, seq[Node]]

proc insert(root: var NodeChildren; c: RGBColor; trimMap: var TrimMap): uint =
  # max level is 7, because we only have ~6.5 bits (0..100, inclusive)
  # (it *is* 0-indexed, but one extra level is needed for the final leaves)
  var level = 0
  var parent = addr root
  var split = false
  while true:
    assert level < 8
    let idx = c.getIdx(level)
    let old = parent[idx]
    if old == nil:
      let node = cast[Node](alloc(sizeof(NodeObj)))
      node.idx = 0
      node.u.leaf = NodeLeaf(
        c: c,
        n: 1,
        r: uint32(c.r),
        g: uint32(c.g),
        b: uint32(c.b)
      )
      parent[idx] = node
      return 1
    elif old.idx != -1:
      # split just once with identical colors
      if level == 7 or split and old.u.leaf.c == c:
        inc old.u.leaf.n
        old.u.leaf.r += uint32(c.r)
        old.u.leaf.g += uint32(c.g)
        old.u.leaf.b += uint32(c.b)
        break
      let oc = old.u.leaf.c
      let child = cast[Node](alloc(sizeof(NodeObj)))
      child.idx = 0
      child.u.leaf = old.u.leaf
      old.idx = -1
      zeroMem(addr old.u.children, sizeof(old.u.children))
      old.u.children[oc.getIdx(level + 1)] = child
      trimMap[level].add(old)
      split = true
    inc level
    parent = addr old.u.children
  0

proc trim(trimMap: var TrimMap; K: var uint) =
  var node: Node = nil
  for i in countdown(trimMap.high, 0):
    if trimMap[i].len > 0:
      node = trimMap[i].pop()
      break
  var r = 0u32
  var g = 0u32
  var b = 0u32
  var n = 0u32
  var k = K + 1
  for child in node.u.children:
    if child != nil:
      r += child.u.leaf.r
      g += child.u.leaf.g
      b += child.u.leaf.b
      n += child.u.leaf.n
      dealloc(child)
      dec k
  node.idx = 0
  node.u.leaf = NodeLeaf(
    c: rgb(uint8(r div n), uint8(g div n), uint8(b div n)),
    r: r,
    g: g,
    b: b,
    n: n
  )
  K = k

proc quantize(img: openArray[RGBAColorBE]; outk: var uint;
    outTransparent: var bool): NodeChildren =
  var root = NodeChildren.default
  if outk <= 2: # monochrome; not much we can do with an octree...
    root[0] = cast[Node](alloc0(sizeof(NodeObj)))
    root[0].u.leaf.c = rgb(0, 0, 0)
    root[7] = cast[Node](alloc0(sizeof(NodeObj)))
    root[7].u.leaf.c = rgb(100, 100, 100)
    outk = 2
    # the point is to skip the first scan, so fall back to the option
    # that always works
    outTransparent = true
    return root
  # number of leaves
  let palette = outk
  var K = 0u
  # map of non-leaves for each level.
  # (note: somewhat confusingly, this actually starts at level 1.)
  var trimMap: array[7, seq[Node]]
  var transparent = false
  for c0 in img:
    let c0 = c0.argb().fastmul(100)
    transparent = transparent or c0.a != 100
    let c = RGBColor(c0)
    K += root.insert(c, trimMap)
    while K > palette:
      trimMap.trim(K)
  outk = K
  outTransparent = transparent
  return root

proc flatten(children: NodeChildren; cols: var seq[Node]) =
  for node in children:
    if node != nil:
      if node.idx != -1:
        cols.add(node)
      else:
        node.u.children.flatten(cols)

proc flatten(root: NodeChildren; outs: var string; palette: uint): seq[Node] =
  var cols = newSeqOfCap[Node](palette)
  root.flatten(cols)
  # try to set the most common colors as the smallest numbers (so we write less)
  cols.sort(proc(a, b: Node): int = cmp(a.u.leaf.n, b.u.leaf.n),
    order = Descending)
  for n, it in cols:
    let c = it.u.leaf.c
    # 2 is RGB
    outs &= '#' & $n & ";2;" & $c.r & ';' & $c.g & ';' & $c.b
    it.idx = n
  return cols

type
  DitherDiff = tuple[a, r, g, b: int32]

  Dither = object
    d1: seq[DitherDiff]
    d2: seq[DitherDiff]

proc getColor(nodes: seq[Node]; c: ARGBColor; diff: var DitherDiff): Node =
  var child: Node = nil
  var minDist = uint32.high
  var mdiff = DitherDiff.default
  for node in nodes:
    let ic = node.u.leaf.c
    let ad = int32(c.a) - 100
    let rd = int32(c.r) - int32(ic.r)
    let gd = int32(c.g) - int32(ic.g)
    let bd = int32(c.b) - int32(ic.b)
    let d = uint32(abs(rd)) + uint32(abs(gd)) + uint32(abs(bd))
    if d < minDist:
      minDist = d
      child = node
      mdiff = (ad, rd, gd, bd)
      if ic == c.rgb():
        break
  diff = mdiff
  return child

proc getColor(root: var NodeChildren; c: ARGBColor; nodes: seq[Node];
    diff: var DitherDiff): int =
  if nodes.len < 64:
    # Octree-based nearest neighbor search creates really ugly artifacts
    # with a low amount of colors, which is exactly the case where
    # linear search is still acceptable.
    #
    # 64 is the first power of 2 that gives OK results on my test images
    # with the octree.
    #
    # (In practice, I assume no sane terminal would pick a palette (> 2)
    # that isn't a multiple of 4, so really only 16 is relevant here.
    # Even that is quite rare, unless you misconfigure XTerm - or
    # have a hardware terminal, but those didn't have private color
    # registers in the first place. I do like the aesthetics, though;
    # would be a shame if it didn't work :P)
    return nodes.getColor(c, diff).idx
  # Find a matching color in the octree.
  # Not as accurate as a linear search, but good enough (and much
  # faster) for palettes that reach this path.
  var level = 0
  var children = addr root
  while true:
    let idx = RGBColor(c).getIdx(level)
    let child = children[idx]
    if child == nil:
      let child = nodes.getColor(c, diff)
      # No child found in this corner of the octree. This is caused by
      # dithering.
      # Allocate at least 4 ancestors, so that other colors with the
      # same initial bits don't end up using something wildly different
      # than the dither intended.
      while level < 4:
        let idx = RGBColor(c).getIdx(level)
        let node = cast[Node](alloc0(sizeof(NodeObj)))
        node.idx = -1
        children[idx] = node
        children = addr node.u.children
        inc level
      let idx = RGBColor(c).getIdx(level)
      children[idx] = child
      return child.idx
    if child.idx != -1:
      let ic = child.u.leaf.c
      let a = int32(c.a) - 100
      let r = int32(c.r) - int32(ic.r)
      let g = int32(c.g) - int32(ic.g)
      let b = int32(c.b) - int32(ic.b)
      diff = (a, r, g, b)
      return child.idx
    inc level
    children = addr child.u.children
  -1 # unreachable

proc correctDither(c: ARGBColor; x: int; dither: Dither): ARGBColor =
  let (ad, rd, gd, bd) = dither.d1[x + 1]
  let pa = (uint32(c) shr 20) and 0xFF0
  let pr = (uint32(c) shr 12) and 0xFF0
  let pg = (uint32(c) shr 4) and 0xFF0
  let pb = (uint32(c) shl 4) and 0xFF0
  {.push overflowChecks: off.}
  let a = uint8(uint32(clamp(int32(pa) + ad, 0, 1600)) shr 4)
  let r = uint8(uint32(clamp(int32(pr) + rd, 0, 1600)) shr 4)
  let g = uint8(uint32(clamp(int32(pg) + gd, 0, 1600)) shr 4)
  let b = uint8(uint32(clamp(int32(pb) + bd, 0, 1600)) shr 4)
  {.pop.}
  return rgba(r, g, b, a)

proc fs(dither: var Dither; x: int; d: DitherDiff) =
  let x = x + 1 # skip first bounds check
  template at(p, mul: untyped) =
    var (ad, rd, gd, bd) = p
    p = (ad + d.a * mul, rd + d.r * mul, gd + d.g * mul, bd + d.b * mul)
  {.push overflowChecks: off.}
  at(dither.d1[x + 1], 7)
  at(dither.d2[x - 1], 3)
  at(dither.d2[x], 5)
  at(dither.d2[x + 1], 1)
  {.pop.}

type
  SixelBand = object
    head: ptr SixelChunk
    tail: ptr SixelChunk

  SixelChunk = object
    x: int
    c: int
    nrow: uint
    # data is binary 0..63; compressSixel creates the final ASCII form
    data: seq[uint8]
    # linked list for chaining together bands
    # (yes, this *is* faster than a seq.)
    next: ptr SixelChunk

proc compressSixel(outs: var string; band: SixelBand) =
  var x = 0
  var chunk = band.head
  while chunk != nil:
    outs &= '#' & $chunk.c
    var n = chunk.x - x
    var c = '?'
    for u in chunk.data:
      let cc = char(u + 0x3F)
      if c != cc:
        if n > 3:
          outs &= '!' & $n & c
        else:
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
    x = chunk.x + chunk.data.len
    let next = chunk.next
    chunk.next = nil
    chunk = next

proc createBands(bands: var seq[SixelBand]; activeChunks: seq[ptr SixelChunk]) =
  for chunk in activeChunks:
    var found = false
    for band in bands.mitems:
      if band.head.x > chunk.x + chunk.data.len:
        chunk.next = band.head
        band.head = chunk
        found = true
        break
      elif band.tail.x + band.tail.data.len <= chunk.x:
        band.tail.next = chunk
        band.tail = chunk
        found = true
        break
    if not found:
      bands.add(SixelBand(head: chunk, tail: chunk))

proc encode(os: PosixStream; img: openArray[RGBAColorBE];
    width, height, offx, offy, cropw, palette: int; halfdump: bool) =
  var palette = uint(palette)
  var transparent = false
  var root = img.quantize(palette, transparent)
  # prelude
  var outs = "Cha-Image-Sixel-Transparent: " & $int(transparent) & "\n"
  outs &= "Cha-Image-Sixel-Prelude-Len: "
  const PreludePad = "666 666 666"
  let preludeLenPos = outs.len
  outs &= PreludePad & "\n\n"
  let dcsPos = outs.len
  outs &= DCS
  if transparent:
    outs &= "0;1" # P2=1 -> image has transparency
  outs &= 'q'
  # set raster attributes
  outs &= "\"1;1;" & $width & ';' & $height
  let nodes = root.flatten(outs, palette)
  # prepend prelude size
  var ps = $(outs.len - dcsPos)
  while ps.len < PreludePad.len:
    ps &= ' '
  for i, c in ps:
    outs[preludeLenPos + i] = c
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
  const MaxBuffer = 65536
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
        let c0 = img[m].argb().fastmul(100).correctDither(j, dither)
        if c0.a < 50: # transparent
          let diff = (int32(c0.a), 0i32, 0i32, 0i32)
          dither.fs(j, diff)
          chunk = nil
          continue
        var diff: DitherDiff
        let c = root.getColor(c0, nodes, diff)
        dither.fs(j, diff)
        if chunk == nil or chunk.c != c:
          chunk = addr chunkMap[c]
          if chunk.nrow < nrow:
            chunk.c = c
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
            let olen = chunk.data.len
            chunk.data.setLen(j - chunk.x)
            when NimMajor < 2:
              zeroMem(addr chunk.data[olen], j - chunk.x - olen)
            else:
              discard olen
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
        os.puts(outs)
        outs.setLen(0)
    inc nrow
    activeChunks.setLen(0)
  if halfdump:
    ymap.putU32BE(totalLen)
    ymap.putU32BE(uint32(ymap.len))
    outs &= ymap
  os.puts(outs)
  # Note: we leave octree deallocation to the OS. See the header for details.

proc parseDimensions(os: PosixStream; s: string; allowZero: bool): (int, int) =
  let s = s.split('x')
  if s.len != 2:
    cgiDie(ceInternalError, "wrong dimensions")
  let w = parseIntP(s[0]).get(-1)
  let h = parseIntP(s[1]).get(-1)
  if w < 0 or h < 0 or not allowZero and (w == 0 or h == 0):
    cgiDie(ceInternalError, "wrong dimensions")
  return (w, h)

proc main() =
  let os = newPosixStream(STDOUT_FILENO)
  if getEnvEmpty("MAPPED_URI_PATH") == "encode":
    var width = 0
    var height = 0
    var offx = 0
    var offy = 0
    var halfdump = false
    var palette = -1
    var cropw = -1
    var quality = -1
    for hdr in getEnvEmpty("REQUEST_HEADERS").split('\n'):
      let s = hdr.after(':').strip()
      case hdr.until(':')
      of "Cha-Image-Dimensions":
        (width, height) = os.parseDimensions(s, allowZero = false)
      of "Cha-Image-Offset":
        (offx, offy) = os.parseDimensions(s, allowZero = true)
      of "Cha-Image-Crop-Width":
        let q = parseUInt32(s, allowSign = false)
        if q.isErr:
          cgiDie(ceInternalError, "wrong crop width")
        cropw = int(q.get)
      of "Cha-Image-Sixel-Halfdump":
        halfdump = true
      of "Cha-Image-Sixel-Palette":
        let q = parseUInt16(s, allowSign = false)
        if q.isErr:
          cgiDie(ceInternalError, "wrong palette")
        palette = int(q.get)
      of "Cha-Image-Quality":
        let q = parseUInt16(s, allowSign = false)
        if q.isErr:
          cgiDie(ceInternalError, "wrong quality")
        quality = int(q.get)
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
      quit(0) # done...
    let n = width * height
    let L = n * 4
    let ps = newPosixStream(STDIN_FILENO)
    let src = ps.readLoopOrMmap(L)
    if src == nil:
      cgiDie(ceInternalError, "failed to read input")
    enterNetworkSandbox() # don't swallow stat
    let p = cast[ptr UncheckedArray[RGBAColorBE]](src.p)
    os.encode(p.toOpenArray(0, n - 1), width, height, offx, offy, cropw,
      palette, halfdump)
    deallocMem(src)
  else:
    cgiDie(ceInternalError, "not implemented")

main()

{.pop.} # raises: []
