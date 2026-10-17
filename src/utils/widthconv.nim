{.push raises: [].}

when NimMajor >= 2:
  import std/assertions
import std/algorithm

import utils/cowstr
import utils/twtstr

const CanHaveDakuten = ("かきくけこさしすせそたちつてとはひふへほカキクケコ" &
  "サシスセソタチツテトハヒフヘホ").toPoints()

const CanHaveHanDakuten = "はひふへほハヒフヘホ".toPoints()

const HasDakuten = ("がぎぐげござじずぜぞだぢづでどばびぶべぼガギグゲゴ" &
  "ザジズゼゾダヂヅデドバビブベボ").toPoints()

const HasHanDakuten = "ぱぴぷぺぽパピプペポ".toPoints()

# Halfwidth to fullwidth & vice versa
const halfFullMap = (proc(): seq[tuple[half, full1, full2: uint32]] =
  result = @[]
  const map = staticRead"res/widthconvmap.tab"
  var i = 0
  while i < map.len:
    let half = map.nextUTF8(i)
    assert map[i] == '\t'
    inc i
    let full1 = map.nextUTF8(i)
    var full2 = 0u32
    if i < map.len and map[i] != '\n':
      assert map[i] == '\t'
      inc i
      full2 = map.nextUTF8(i)
    result.add((half, full1, full2))
    assert map[i] == '\n'
    inc i
)()

proc halfwidth(u: uint32): uint32 =
  if u != 0: # special case to avoid comparison with f2
    for (h, f1, f2) in halfFullMap:
      if f1 == u or f2 == u:
        return h
  return u

const HalfDakuten = 0xFF9Eu32 # half-width dakuten
const HalfHanDakuten = 0xFF9Fu32 # half-width handakuten

# Note: in unicode, char + 1 is dakuten and char + 2 handakuten

proc halfwidth*(s: openArray[char]): Str =
  var buf = initGrowbufOfCap(s.len)
  for u in s.points:
    case u
    of HasDakuten:
      buf.addUTF8(halfwidth(u - 1))
      buf.addUTF8(HalfDakuten)
    of HasHanDakuten:
      buf.addUTF8(halfwidth(u - 2))
      buf.addUTF8(HalfHanDakuten)
    else:
      buf.addUTF8(halfwidth(u))
  buf.toStr()

proc fullwidth(r: uint32): uint32 =
  if r != 0: # special case to avoid comparison with f2
    for (h, f1, f2) in halfFullMap:
      if h == r:
        return f1
  return r

proc fullwidth*(s: openArray[char]): Str =
  var buf = initGrowbufOfCap(s.len)
  var lastu = 0u32
  for u in s.points:
    if lastu != 0:
      if u == HalfDakuten:
        # flush with dakuten
        buf.addUTF8(lastu + 1)
        lastu = 0
        continue
      elif u == HalfHanDakuten and lastu in CanHaveHanDakuten:
        # flush with handakuten
        buf.addUTF8(lastu + 2)
        lastu = 0
        continue
      buf.addUTF8(lastu)
      lastu = 0
    let u = fullwidth(u)
    if u in CanHaveDakuten:
      lastu = u
    else:
      buf.addUTF8(u)
  if lastu != 0:
    # flush
    buf.addUTF8(lastu)
  buf.toStr()

# this used to be generated at compile time, then I got annoyed with it
# when switching to CoW strings and just copy pasted the thing here.
# the drawback is that I have no clue what characters these are...
const FullSizeMap = [
  (12353u32, 12354u16), (12355u32, 12356u16), (12357u32, 12358u16),
  (12359u32, 12360u16), (12361u32, 12362u16), (12387u32, 12388u16),
  (12419u32, 12420u16), (12421u32, 12422u16), (12423u32, 12424u16),
  (12430u32, 12431u16), (12437u32, 12363u16), (12438u32, 12369u16),
  (12449u32, 12450u16), (12451u32, 12452u16), (12453u32, 12454u16),
  (12455u32, 12456u16), (12457u32, 12458u16), (12483u32, 12484u16),
  (12515u32, 12516u16), (12517u32, 12518u16), (12519u32, 12520u16),
  (12526u32, 12527u16), (12533u32, 12459u16), (12534u32, 12465u16),
  (12784u32, 12463u16), (12785u32, 12471u16), (12786u32, 12473u16),
  (12787u32, 12488u16), (12788u32, 12492u16), (12789u32, 12495u16),
  (12790u32, 12498u16), (12791u32, 12501u16), (12792u32, 12504u16),
  (12793u32, 12507u16), (12794u32, 12512u16), (12795u32, 12521u16),
  (12796u32, 12522u16), (12797u32, 12523u16), (12798u32, 12524u16),
  (12799u32, 12525u16), (65383u32, 65393u16), (65384u32, 65394u16),
  (65385u32, 65395u16), (65386u32, 65396u16), (65387u32, 65397u16),
  (65388u32, 65428u16), (65389u32, 65429u16), (65390u32, 65430u16),
  (65391u32, 65410u16), (110898u32, 12371u16), (110928u32, 12432u16),
  (110929u32, 12433u16), (110930u32, 12434u16), (110933u32, 12467u16),
  (110948u32, 12528u16), (110949u32, 12529u16), (110950u32, 12530u16),
  (110951u32, 12531u16),
]

proc fullsize*(s: openArray[char]): Str =
  var buf = initGrowbufOfCap(s.len)
  for u in s.points:
    let i = FullSizeMap.binarySearch(u,
      proc(x: (uint32, uint16); y: uint32): int = cmp(x[0], y))
    if i < 0:
      buf.addUTF8(u)
    else:
      buf.addUTF8(uint32(FullSizeMap[i][1]))
  buf.toStr()

{.pop.} # raises: []
