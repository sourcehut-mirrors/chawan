# Lookup tables for characters on the BMP. This "only" takes up 8k of space
# per table, as opposed to the 135k that storing all characters would require.
# The downside is obviously that we need a binary search fallback for non-bmp.
# We do not store a lookup table of ambiguous ranges, either.

type
  ptint* = uint32
  PropertyTable* = array[0x10000 div (sizeof(ptint) * 8), ptint]
  RangeMap* = openArray[(uint32, uint32)]

{.push boundChecks:off.}
proc contains*(props: PropertyTable; u: ptint): bool {.inline.} =
  const isz = sizeof(ptint) * 8
  let i = u div isz
  let m = u mod isz
  return (props[i] and (1u32 shl m)) != 0
{.pop.}
