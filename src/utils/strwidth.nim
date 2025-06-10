import utils/proptable
import utils/twtstr

include res/map/charwidth_gen

# Tabs are a bit of a problem: depending on their position in text, they may
# represent one to eight characters. Inferring their size after layout is wrong
# because a rendered line is obviously not equivalent to a CSS line.
#
# In the past, we worked around this by always passing the string's current
# width to width(), but this only ever worked properly for plain text documents,
# which we no longer distinguish from HTML.
#
# So now, to preserve tabs, we do the following:
#
# * Define Unicode PUA U+E000 to U+E007 as a tab range. The final digit
#   represents the number of characters the tab occupies, minus one. (Tab size
#   ranges from 1 char to 8 chars.)
# * In layout, replace characters in this range with U+FFFD. Then, translate
#   literal tabs into the range depending on their width in the document.
# * In width(), substitute the size of these characters accordingly.
# * Finally, in buffer drawing code, translate the range back into the necessary
#   number of spaces - except in dump mode, where properly aligned tabs become
#   hard tabs, and in selection mode, where *all* tabs become hard tabs.
const TabPUARange* = 0xE000u32 .. 0xE007u32

func tabPUAPoint*(n: int): uint32 =
  let u = 0xE000 + uint32(n) - 1
  assert u in TabPUARange
  return u

var isCJKAmbiguous* {.global.} = false

# Warning: this shouldn't be called without normalization.
func width*(u: uint32): int =
  if u <= 0xFFFF: # fast path for BMP
    if u in DoubleWidthTable:
      return 2
    if u in 0x80u32 .. 0x9Fu32:
      # Represent Unicode control chars as [XX] where X is a hex digit.
      return 4
    if u in TabPUARange:
      return int(((u - TabPUARange.a) and 7) + 1)
  else:
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

func padToWidth*(s: string; size: uint32; schar = '$'): string =
  result = newStringOfCap(s.len)
  var w = 0u32
  var i = 0
  var pi = 0
  while i < s.len:
    pi = i
    w += uint32(s.nextUTF8(i).width())
    if w + 1 > size:
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

# Expand all PUA tabs into hard tabs, disregarding their position.
# (This is mainly intended for copy/paste, where the actual characters
# are more interesting than cell alignment.)
func expandPUATabsHard*(s: openArray[char]): string =
  var res = newStringOfCap(s.len)
  var i = 0
  while i < s.len:
    let pi = i
    if s.nextUTF8(i) in TabPUARange:
      res &= '\t'
    else:
      for j in pi ..< i:
        res &= s[j]
  move(res)
