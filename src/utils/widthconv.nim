import std/strutils

import utils/twtstr

const CanHaveDakuten = ("かきくけこさしすせそたちつてとはひふへほカキクケコ" &
  "サシスセソタチツテトハヒフヘホ").toPoints()

const CanHaveHanDakuten = "はひふへほハヒフヘホ".toPoints()

const HasDakuten = ("がぎぐげござじずぜぞだぢづでどばびぶべぼガギグゲゴ" &
  "ザジズゼゾダヂヅデドバビブベボ").toPoints()

const HasHanDakuten = "ぱぴぷぺぽパピプペポ".toPoints()

# Halfwidth to fullwidth & vice versa
const halfFullMap = (func(): seq[tuple[half, full1, full2: uint32]] =
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

func halfwidth(u: uint32): uint32 =
  if u != 0: # special case to avoid comparison with f2
    for (h, f1, f2) in halfFullMap:
      if f1 == u or f2 == u:
        return h
  return u

const HalfDakuten = 0xFF9Eu32 # half-width dakuten
const HalfHanDakuten = 0xFF9Fu32 # half-width handakuten

# Note: in unicode, char + 1 is dakuten and char + 2 handakuten

func halfwidth*(s: string): string =
  result = ""
  for u in s.points:
    case u
    of HasDakuten:
      result.addUTF8(halfwidth(u - 1))
      result.addUTF8(HalfDakuten)
    of HasHanDakuten:
      result.addUTF8(halfwidth(u - 2))
      result.addUTF8(HalfHanDakuten)
    else:
      result.addUTF8(halfwidth(u))

func fullwidth(r: uint32): uint32 =
  if r != 0: # special case to avoid comparison with f2
    for (h, f1, f2) in halfFullMap:
      if h == r:
        return f1
  return r

func fullwidth*(s: string): string =
  result = ""
  var lastu = 0u32
  for u in s.points:
    if lastu != 0:
      if u == HalfDakuten:
        # flush with dakuten
        result.addUTF8(lastu + 1)
        lastu = 0
        continue
      elif u == HalfHanDakuten and lastu in CanHaveHanDakuten:
        # flush with handakuten
        result.addUTF8(lastu + 2)
        lastu = 0
        continue
      result.addUTF8(lastu)
      lastu = 0
    let u = fullwidth(u)
    if u in CanHaveDakuten:
      lastu = u
    else:
      result.addUTF8(u)
  if lastu != 0:
    # flush
    result.addUTF8(lastu)

const kanamap = staticRead"res/kanamap.tab"
func genFullSizeMap(): seq[(uint32, uint32)] =
  result = @[]
  for line in kanamap.split('\n'):
    if line.len == 0: break
    let rs = line.toPoints()
    assert rs[1] == uint32('\t')
    result.add((rs[0], rs[2]))
const fullSizeMap = genFullSizeMap()

proc fullsize*(s: string): string =
  result = ""
  for u in s.points:
    let i = searchInMap(fullSizeMap, u)
    if i == -1:
      result.addUTF8(u)
    else:
      result.addUTF8(fullSizeMap[i][1])
