import utils/map
import utils/proptable
import utils/twtuni

include res/map/charwidth_gen

# One of the few global variables in the code. Honestly, it should not exist.
var isCJKAmbiguous* = false

# Warning: this shouldn't be called without normalization.
func width*(u: uint32): int =
  if u <= 0xFFFF: # fast path for BMP
    if u in CombiningTable:
      return 0
    if u in DoubleWidthTable:
      return 2
    {.cast(noSideEffect).}:
      if isCJKAmbiguous and DoubleWidthAmbiguousRanges.isInRange(u):
        return 2
  else:
    if Combining.isInRange(u):
      return 0
    if DoubleWidthRanges.isInRange(u):
      return 2
    {.cast(noSideEffect).}:
      if isCJKAmbiguous and DoubleWidthAmbiguousRanges.isInRange(u):
        return 2
  return 1

func width*(s: openArray[char]): int =
  var w = 0
  for u in s.points:
    w += u.width()
  return w

func width*(s: string; start, len: int): int =
  var w = 0
  var i = start
  var m = len
  if m > s.len:
    m = s.len
  while i < m:
    let u = s.nextUTF8(i)
    w += u.width()
  return w

func padToWidth*(s: string; size: int; schar = '$'): string =
  result = newStringOfCap(s.len)
  var w = 0
  var i = 0
  var pi = 0
  while i < s.len:
    pi = i
    w += s.nextUTF8(i).width()
    if w > size - 1:
      break
    for j in pi ..< i:
      result &= s[j]
  if w > size - 1:
    if w == size and i == s.len:
      for j in pi ..< i:
        result &= s[j]
    else:
      result &= schar
  while w < size:
    result &= ' '
    inc w
