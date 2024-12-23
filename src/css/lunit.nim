# 32-bit fixed-point number, with 6 bits of precision.

type LayoutUnit* = distinct int32

{.push overflowChecks: off, rangeChecks: off.}
template satlu(a: int64): LayoutUnit =
  if unlikely(a < int32.low):
    LayoutUnit.low
  elif unlikely(a > int32.high):
    LayoutUnit.high
  else:
    LayoutUnit(a)

when sizeof(int) == 4 and not defined(nimEmulateOverflowChecks) and
    (defined(gcc) or defined(clang)):
  func nimAddInt(a, b: int; res: ptr int): bool {.importc, nodecl.}
  func nimSubInt(a, b: int; res: ptr int): bool {.importc, nodecl.}

  func `+`*(a, b: LayoutUnit): LayoutUnit {.inline.} =
    let a = int(a)
    let b = int(b)
    var res {.noinit.}: int
    if nimAddInt(a, b, addr res):
      if a > 0:
        return LayoutUnit.high
      return LayoutUnit.low
    return LayoutUnit(res)

  func `-`*(a, b: LayoutUnit): LayoutUnit {.inline.} =
    let a = int(a)
    let b = int(b)
    var res {.noinit.}: int
    if nimSubInt(a, b, addr res):
      if b < 0:
        return LayoutUnit.high
      return LayoutUnit.low
    return LayoutUnit(res)
else:
  when sizeof(int) == 4:
    {.warning: """Using 64-bit lunit ops on a 32-bit arch.
If you are using GCC/clang, report this at https://todo.sr.ht/~bptato/chawan""".}

  func `+`*(a, b: LayoutUnit): LayoutUnit {.inline.} =
    let ab = int64(a) + int64(b)
    return satlu(ab)

  func `-`*(a, b: LayoutUnit): LayoutUnit {.inline.} =
    let ab = int64(a) - int64(b)
    return satlu(ab)

func `*`*(a, b: LayoutUnit): LayoutUnit {.inline.} =
  let ab = (int64(a) * int64(b)) shr 6
  return satlu(ab)

func `div`*(a, b: LayoutUnit): LayoutUnit {.inline.} =
  let a = int64(uint64(a) shl 12)
  let b = int64(b)
  return LayoutUnit((a div b) shr 6)

converter toLayoutUnit*(a: int): LayoutUnit =
  let a = int64(a) shl 6
  return satlu(a)

func `-`*(a: LayoutUnit): LayoutUnit {.inline.} =
  let a = int32(a)
  if unlikely(a == int32.high):
    return LayoutUnit.low
  return LayoutUnit(-a)
{.pop.} # overflowChecks, rangeChecks

func `==`*(a, b: LayoutUnit): bool {.borrow.}
func `<`*(a, b: LayoutUnit): bool {.borrow.}
func `<=`*(a, b: LayoutUnit): bool {.borrow.}

func toInt*(a: LayoutUnit): int =
  return int32(a) shr 6

func `+=`*(a: var LayoutUnit; b: LayoutUnit) {.inline.} =
  a = a + b

func `-=`*(a: var LayoutUnit; b: LayoutUnit) {.inline.} =
  a = a - b

func `*=`*(a: var LayoutUnit; b: LayoutUnit) {.inline.} =
  a = a * b

func toLayoutUnit*(a: float64): LayoutUnit =
  let a = a * 64
  if unlikely(a == Inf):
    return LayoutUnit(high(int32))
  elif unlikely(a == -Inf):
    return LayoutUnit(low(int32))
  return LayoutUnit(int32(a))

func toFloat64*(a: LayoutUnit): float64 =
  return float64(int32(a)) / 64

func `$`*(a: LayoutUnit): string =
  $toFloat64(a)

func min*(a, b: LayoutUnit): LayoutUnit {.borrow.}
func max*(a, b: LayoutUnit): LayoutUnit {.borrow.}

func ceilTo*(a: LayoutUnit; prec: int): LayoutUnit =
  return (1 + ((a - 1) div prec).toInt) * prec
