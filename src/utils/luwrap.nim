{.push raises: [].}

when NimMajor >= 2:
  import std/assertions

import std/algorithm

import js/libregexp
import js/libunicode
import utils/cowstr
import utils/twtstr

proc passRealloc(opaque, p: pointer; size: csize_t): pointer {.cdecl.} =
  return realloc(p, cast[int](size))

type CodeArray* = object
  p: ptr UncheckedArray[uint32]
  len*: int

proc `=destroy`*(ca: var CodeArray) =
  if ca.p != nil:
    dealloc(ca.p)

proc `=sink`*(dst: var CodeArray; src: CodeArray) =
  `=destroy`(dst)
  dst.p = src.p
  dst.len = src.len

proc `=copy`*(dst: var CodeArray; src: CodeArray) {.error.} =
  discard

iterator items*(ca: CodeArray): uint32 {.inline.} =
  let len = ca.len
  for i in 0 ..< len:
    yield ca.p[i]

proc high(ca: CodeArray): int =
  {.push overflowChecks: off.}
  let H = ca.len - 1
  {.pop.}
  H

template toOpenArray(ca: CodeArray): openArray[uint32] =
  ca.p.toOpenArray(0, ca.high)

proc toUTF8*(ca: CodeArray): Str =
  ca.toOpenArray().toUTF8()

proc addUTF8*(buf: var Growbuf; us: CodeArray) =
  buf.addUTF8(us.toOpenArray())

proc `[]`*(ca: CodeArray; n: int): uint32 {.inline.} =
  assert n >= 0 and n < ca.len
  ca.p[n]

proc `==`*(a: openArray[uint32]; b: CodeArray): bool =
  a == b.toOpenArray()

proc normalize*(rs: openArray[uint32]; form = UNICODE_NFC): CodeArray =
  if rs.len <= 0:
    return CodeArray()
  var obuf: ptr uint32
  let olen = unicode_normalize(addr obuf, unsafeAddr rs[0], cint(rs.len), form,
    nil, passRealloc)
  if olen <= 0:
    return CodeArray()
  CodeArray(p: cast[ptr UncheckedArray[uint32]](obuf), len: int(olen))

proc mnormalize*(s: var Growbuf) =
  if NonAscii in s.toOpenArray(): # no need to normalize ascii
    let rs = s.toOpenArray().toPoints()
    let ca = normalize(rs, UNICODE_NFC)
    s.setLen(0)
    s.addUTF8(ca)

# n == 0: upper, 1: lower, 2: case fold
proc toUpperLU(s: openArray[char]; n: cint): Str =
  var buf = initGrowbufOfCap(s.len)
  for u in s.points:
    var outa {.noinit.}: array[LRE_CC_RES_LEN_MAX, uint32]
    let n = lre_case_conv(cast[ptr UncheckedArray[uint32]](addr outa[0]), u, n)
    buf.addUTF8(outa.toOpenArray(0, n - 1))
  buf.toStr()

proc toUpperLU*(s: openArray[char]): Str =
  return s.toUpperLU(0)

proc toLowerLU*(s: openArray[char]): Str =
  return s.toUpperLU(1)

proc capitalizeLU*(s: openArray[char]): Str =
  var buf = initGrowbufOfCap(s.len)
  var wordStart = true
  for u in s.points:
    if lre_is_space(u) != 0:
      wordStart = true
      buf.addUTF8(u)
    elif wordStart:
      var outa {.noinit.}: array[LRE_CC_RES_LEN_MAX, uint32]
      let n = lre_case_conv(cast[ptr UncheckedArray[uint32]](addr outa[0]),
        u, 0)
      buf.addUTF8(outa.toOpenArray(0, n - 1))
      wordStart = false
    else:
      buf.addUTF8(u)
  buf.toStr()

type u32pair* {.packed.} = object
  a: uint32
  b: uint32

proc cmpRange*(x: u32pair; y: uint32): int =
  if x.a > y:
    return 1
  elif x.b <= y:
    return -1
  return 0

proc contains(cr: CharRange; u: uint32): bool =
  let cps = cast[ptr UncheckedArray[u32pair]](cr.points)
  let L = cr.len div 2 - 1
  return cps.toOpenArray(0, L).binarySearch(u, cmpRange) != -1

type
  LURangeType = enum
    lurLetter = "Letter"
    lurSeparator = "Separator"
    lurOther = "Other"
    lurMark = "Mark"
    lurEnclosingMark = "Me"
    lurNonspacingMark = "Mn"
    lurFormat = "Cf"
    lurBidiControl = "Bidi_Control"
    lurIDSU = "IDSU"
    lurIDSB = "IDSB"
    lurIDST = "IDST"
    lurDI = "DI"

  LUContextObj = object
    crs: array[LURangeType, CharRange]
    inited: set[LURangeType]

  LUContext* = ref LUContextObj

proc `=destroy`*(ctx: var LUContextObj) =
  for lur, cr in ctx.crs.mpairs:
    if lur in ctx.inited:
      cr_free(addr cr)
  ctx.inited = {}

proc initGeneralCategory(ctx: LUContext; lur: LURangeType) =
  if lur notin ctx.inited:
    let p = addr ctx.crs[lur]
    cr_init(p, nil, passRealloc)
    doAssert unicode_general_category(p, cstring($lur)) == 0
    ctx.inited.incl(lur)

proc initProp(ctx: LUContext; lur: LURangeType) =
  if lur notin ctx.inited:
    let p = addr ctx.crs[lur]
    cr_init(p, nil, passRealloc)
    doAssert unicode_prop(p, cstring($lur)) == 0
    ctx.inited.incl(lur)

proc isAlpha*(ctx: LUContext; u: uint32): bool =
  ctx.initGeneralCategory(lurLetter)
  return u in ctx.crs[lurLetter]

proc isWhiteSpace*(ctx: LUContext; u: uint32): bool =
  ctx.initGeneralCategory(lurSeparator)
  return u in ctx.crs[lurSeparator]

proc isOther*(ctx: LUContext; u: uint32): bool =
  ctx.initGeneralCategory(lurOther)
  return u in ctx.crs[lurOther]

proc isMark*(ctx: LUContext; u: uint32): bool =
  ctx.initGeneralCategory(lurMark)
  return u in ctx.crs[lurMark]

proc isEnclosingMark*(ctx: LUContext; u: uint32): bool =
  ctx.initGeneralCategory(lurEnclosingMark)
  return u in ctx.crs[lurEnclosingMark]

proc isNonspacingMark*(ctx: LUContext; u: uint32): bool =
  ctx.initGeneralCategory(lurNonspacingMark)
  return u in ctx.crs[lurNonspacingMark]

proc isFormat*(ctx: LUContext; u: uint32): bool =
  ctx.initGeneralCategory(lurFormat)
  return u in ctx.crs[lurFormat]

proc isBidiControl*(ctx: LUContext; u: uint32): bool =
  ctx.initProp(lurBidiControl)
  return u in ctx.crs[lurBidiControl]

proc isIDSOperator*(ctx: LUContext; u: uint32): bool =
  ctx.initProp(lurIDSU)
  ctx.initProp(lurIDSB)
  ctx.initProp(lurIDST)
  return u in ctx.crs[lurIDSU] or u in ctx.crs[lurIDSB] or u in ctx.crs[lurIDST]

proc isDefaultIgnorable*(ctx: LUContext; u: uint32): bool =
  ctx.initProp(lurDI)
  return u in ctx.crs[lurDI]

# Halfwidth to fullwidth & vice versa
const HalfFullMap = [
  uint8 1, 11, 12, 0, 250, 241, 160, 162, 164, 166, 168, 226, 228, 230, 194,
  251, 161, 163, 165, 167, 169, 170, 172, 174, 176, 178, 180, 182, 184, 186,
  188, 190, 192, 195, 197, 199, 201, 202, 203, 204, 205, 206, 209, 212, 215,
  218, 221, 222, 223, 224, 225, 227, 229, 231, 232, 233, 234, 235, 236, 238,
  242, 154, 155
]

proc halfwidth(u: uint32): uint32 =
  if u in 0xFF01'u16 .. 0xFF5E'u16:
    return u - 0xFF01 + 0x21 # ASCII
  if u == 0xFFE5: # full width yen
    return 0xA5 # yen
  if u == 0x3000: # full width space
    return 0x20 # space
  if u in 0x3099'u32 .. 0x309A'u32: # full width (han)dakuten
    return u - 0x3099 + 0xFF9E # half width (han)dakuten
  if u in 0x3001'u16 .. 0x30FF'u16:
    let u2 = u - 0x3001
    for i, it in HalfFullMap:
      if uint16(it) == u2:
        return 0xFF61 + uint16(i)
  return u

const HalfDakuten = 0xFF9Eu32 # half-width dakuten
const HalfHanDakuten = 0xFF9Fu32 # half-width handakuten

proc halfwidth*(s: openArray[char]): Str =
  var buf = initGrowbufOfCap(s.len)
  for u in s.points:
    var u = u
    if u in 0x3041'u32 .. 0x3093'u32 and u != 0x308E and u != 0x3090 and
        u != 0x3091:
      u += 0x60 # shift to katakana
    if u in 0x30A1'u32 .. 0x30FA'u32:
      # split (han)dakuten from kana
      let us = normalize([u], UNICODE_NFKD)
      for u in us:
        buf.addUTF8(halfwidth(u))
    else:
      buf.addUTF8(halfwidth(u))
  buf.toStr()

proc fullwidth(u: uint32): uint32 =
  if u in 0x21'u32 .. 0x7E'u32:
    return u + 0xFF01 - 0x21 # ASCII
  if u == 0xA5: # yen
    return 0xFFE5 # full width yen
  if u == 0x20: # space
    return 0x3000 # full width space
  if u in 0xFF9E'u32 .. 0xFF9F'u32: # half width (han)dakuten
    return u + 0x3099 - 0xFF9E # full width (han)dakuten
  if u in 0xFF61'u16 .. 0xFF9f'u16:
    return 0x3001 + uint16(HalfFullMap[u - 0xFF61])
  return u

const CanHaveDakuten = ("かきくけこさしすせそたちつてとはひふへほカキクケコ" &
  "サシスセソタチツテトハヒフヘホ").toPoints()

const CanHaveHanDakuten = "はひふへほハヒフヘホ".toPoints()

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
  (12353u16, 12354u16), (12355u16, 12356u16), (12357u16, 12358u16),
  (12359u16, 12360u16), (12361u16, 12362u16), (12387u16, 12388u16),
  (12419u16, 12420u16), (12421u16, 12422u16), (12423u16, 12424u16),
  (12430u16, 12431u16), (12437u16, 12363u16), (12438u16, 12369u16),
  (12449u16, 12450u16), (12451u16, 12452u16), (12453u16, 12454u16),
  (12455u16, 12456u16), (12457u16, 12458u16), (12483u16, 12484u16),
  (12515u16, 12516u16), (12517u16, 12518u16), (12519u16, 12520u16),
  (12526u16, 12527u16), (12533u16, 12459u16), (12534u16, 12465u16),
  (12784u16, 12463u16), (12785u16, 12471u16), (12786u16, 12473u16),
  (12787u16, 12488u16), (12788u16, 12492u16), (12789u16, 12495u16),
  (12790u16, 12498u16), (12791u16, 12501u16), (12792u16, 12504u16),
  (12793u16, 12507u16), (12794u16, 12512u16), (12795u16, 12521u16),
  (12796u16, 12522u16), (12797u16, 12523u16), (12798u16, 12524u16),
  (12799u16, 12525u16), (65383u16, 65393u16), (65384u16, 65394u16),
  (65385u16, 65395u16), (65386u16, 65396u16), (65387u16, 65397u16),
  (65388u16, 65428u16), (65389u16, 65429u16), (65390u16, 65430u16),
  (65391u16, 65410u16),
]

proc cmpFullSize(x: (uint16, uint16); y: uint16): int =
  cmp(x[0], y)

proc fullsize*(s: openArray[char]): Str =
  var buf = initGrowbufOfCap(s.len)
  for u in s.points:
    if u <= 0xFFFF and
        (let i = FullSizeMap.binarySearch(uint16(u), cmpFullSize); i >= 0):
      buf.addUTF8(uint32(FullSizeMap[i][1]))
    elif u == 0x1B132:
      buf.addUTF8(0x3053)
    elif u in 0x1B150'u32 .. 0x1B152'u32:
      buf.addUTF8(0x3090 + u - 0x1B150)
    elif u == 0x1B155:
      buf.addUTF8(0x30B3)
    elif u in 0x1B164'u32 .. 0x1B167'u32:
      buf.addUTF8(0x30F0 + u - 0x1B164)
    else:
      buf.addUTF8(u)
  buf.toStr()

{.pop.} # raises: []
