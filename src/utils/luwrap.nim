{.push raises: [].}

import std/algorithm
import std/strutils

import monoucha/libunicode
import monoucha/libregexp
import utils/twtstr

proc passRealloc(opaque, p: pointer; size: csize_t): pointer {.cdecl.} =
  return realloc(p, size)

proc normalize*(rs: openArray[uint32]; form = UNICODE_NFC): seq[uint32] =
  if rs.len <= 0:
    return @[]
  var outbuf: ptr uint32
  let p = cast[ptr uint32](unsafeAddr rs[0])
  let out_len = unicode_normalize(addr outbuf, p, cint(rs.len), form, nil,
    passRealloc)
  if out_len <= 0:
    return @[]
  var rs = newSeqUninit[uint32](out_len)
  copyMem(addr rs[0], outbuf, out_len * sizeof(uint32))
  dealloc(outbuf)
  return rs

proc mnormalize*(s: var string) =
  if NonAscii notin s:
    return # no need to normalize ascii
  s = s.toPoints().normalize().toUTF8()

# n == 0: upper, 1: lower, 2: case fold
proc toUpperLU(s: string; n: cint): string =
  result = newStringOfCap(s.len)
  for u in s.points:
    var outa {.noinit.}: array[LRE_CC_RES_LEN_MAX, uint32]
    let n = lre_case_conv(cast[ptr UncheckedArray[uint32]](addr outa[0]), u, n)
    result.addUTF8(outa.toOpenArray(0, n - 1))

proc toUpperLU*(s: string): string =
  return s.toUpperLU(0)

proc toLowerLU*(s: string): string =
  return s.toUpperLU(1)

proc capitalizeLU*(s: string): string =
  result = newStringOfCap(s.len)
  var wordStart = true
  for u in s.points:
    if lre_is_space(u):
      wordStart = true
      result.addUTF8(u)
    elif wordStart:
      var outa {.noinit.}: array[LRE_CC_RES_LEN_MAX, uint32]
      let n = lre_case_conv(cast[ptr UncheckedArray[uint32]](addr outa[0]),
        u, 0)
      result.addUTF8(outa.toOpenArray(0, n - 1))
      wordStart = false
    else:
      result.addUTF8(u)

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
    lurHan = "Han"
    lurHiragana = "Hiragana"
    lurKatakana = "Katakana"
    lurHangul = "Hangul"
    lurEnclosingMark = "Me"
    lurNonspacingMark = "Mn"
    lurFormat = "Cf"
    lurBidiControl = "Bidi_Control"
    lurIDSU = "IDSU"
    lurIDSB = "IDSB"
    lurIDST = "IDST"

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

proc initScript(ctx: LUContext; lur: LURangeType) =
  if lur notin ctx.inited:
    let p = addr ctx.crs[lur]
    cr_init(p, nil, passRealloc)
    doAssert unicode_script(p, cstring($lur), false) == 0
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

proc isHan*(ctx: LUContext; u: uint32): bool =
  ctx.initScript(lurHan)
  return u in ctx.crs[lurHan]

proc isHiragana*(ctx: LUContext; u: uint32): bool =
  ctx.initScript(lurHiragana)
  return u in ctx.crs[lurHiragana]

proc isKatakana*(ctx: LUContext; u: uint32): bool =
  ctx.initScript(lurKatakana)
  return u in ctx.crs[lurKatakana]

proc isHangul*(ctx: LUContext; u: uint32): bool =
  ctx.initScript(lurHangul)
  return u in ctx.crs[lurHangul]

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

{.pop.} # raises: []
