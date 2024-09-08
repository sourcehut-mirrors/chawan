func nextUTF8*(s: openArray[char]; i: var int): uint32 =
  let j = i
  let u = uint32(s[j])
  if u <= 0x7F:
    inc i
    return u
  elif u shr 5 == 0b110:
    let e = j + 2
    if likely(e <= s.len):
      i = e
      return (u and 0x1F) shl 6 or
        (uint32(s[j + 1]) and 0x3F)
  elif u shr 4 == 0b1110:
    let e = j + 3
    if likely(e <= s.len):
      i = e
      return (u and 0xF) shl 12 or
        (uint32(s[j + 1]) and 0x3F) shl 6 or
        (uint32(s[j + 2]) and 0x3F)
  elif u shr 3 == 0b11110:
    let e = j + 4
    if likely(e <= s.len):
      i = e
      return (u and 7) shl 18 or
        (uint32(s[j + 1]) and 0x3F) shl 12 or
        (uint32(s[j + 2]) and 0x3F) shl 6 or
        (uint32(s[j + 3]) and 0x3F)
  inc i
  return 0xFFFD

func prevUTF8*(s: openArray[char]; i: var int): uint32 =
  var j = i - 1
  while uint32(s[j]) shr 6 == 2:
    dec j
  i = j
  return s.nextUTF8(j)

func pointLenAt*(s: openArray[char]; i: int): int =
  let u = uint8(s[i])
  if u <= 0x7F:
    return 1
  elif u shr 5 == 0b110:
    return 2
  elif u shr 4 == 0b1110:
    return 3
  elif u shr 3 == 0b11110:
    return 4
  return 1

iterator points*(s: openArray[char]): uint32 {.inline.} =
  var i = 0
  while i < s.len:
    let u = s.nextUTF8(i)
    yield u

func toPoints*(s: openArray[char]): seq[uint32] =
  result = @[]
  for u in s.points:
    result.add(u)

proc addUTF8*(res: var string; u: uint32) =
  if u < 0x80:
    res &= char(u)
  elif u < 0x800:
    res &= char(u shr 6 or 0xC0)
    res &= char(u and 0x3F or 0x80)
  elif u < 0x10000:
    res &= char(u shr 12 or 0xE0)
    res &= char(u shr 6 and 0x3F or 0x80)
    res &= char(u and 0x3F or 0x80)
  else:
    res &= char(u shr 18 or 0xF0)
    res &= char(u shr 12 and 0x3F or 0x80)
    res &= char(u shr 6 and 0x3F or 0x80)
    res &= char(u and 0x3F or 0x80)

func addUTF8*(res: var string; us: openArray[uint32]) =
  for u in us:
    res.addUTF8(u)

func toUTF8*(u: uint32): string =
  var s = ""
  s.addUTF8(u)
  return s

func toUTF8*(us: openArray[uint32]): string =
  var s = newStringOfCap(us.len shr 2)
  s.addUTF8(us)
  return s

func pointLen*(s: openArray[char]): int =
  var n = 0
  for u in s.points:
    inc n
  return n
