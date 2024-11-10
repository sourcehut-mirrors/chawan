# 32-bit fixed-point number, with 6 bits of precision.

type LayoutUnit* = distinct int32

func `==`*(a, b: LayoutUnit): bool {.borrow.}
func `<`*(a, b: LayoutUnit): bool {.borrow.}
func `<=`*(a, b: LayoutUnit): bool {.borrow.}
func `+`*(a, b: LayoutUnit): LayoutUnit {.borrow.}
func `+=`*(a: var LayoutUnit, b: LayoutUnit) {.borrow.}
func `-`*(a, b: LayoutUnit): LayoutUnit {.borrow.}
func `-`*(a: LayoutUnit): LayoutUnit {.borrow.}
func `-=`*(a: var LayoutUnit, b: LayoutUnit) {.borrow.}
func `*`*(a, b: LayoutUnit): LayoutUnit {.inline.} =
  LayoutUnit((int32(a) * int32(b)) shr 6)
func `*=`*(a: var LayoutUnit, b: LayoutUnit) {.inline.} =
  a = a * b
func `/`*(a, b: LayoutUnit): LayoutUnit {.inline.} =
  let a64 = int64(a)
  let b64 = int64(b)
  LayoutUnit(cast[int32](((a64 shl 12) div b64) shr 6))
func `/=`*(a: var LayoutUnit, b: LayoutUnit) {.inline.} =
  a = a / b
func `div`*(a, b: LayoutUnit): LayoutUnit {.inline.} =
  a / b

func toInt*(a: LayoutUnit): int =
  return int32(a) shr 6

converter toLayoutUnit*(a: int32): LayoutUnit =
  return LayoutUnit(a shl 6)

converter toLayoutUnit*(a: int): LayoutUnit =
  return toLayoutUnit(cast[int32](a))

func toLayoutUnit*(a: float64): LayoutUnit =
  if unlikely(a == Inf):
    return LayoutUnit(high(int32))
  elif unlikely(a == -Inf):
    return LayoutUnit(low(int32))
  return LayoutUnit(int32(a * 64))

func toFloat64*(a: LayoutUnit): float64 =
  return float64(int32(a)) / 64

func `$`*(a: LayoutUnit): string =
  $toFloat64(a)

func min*(a, b: LayoutUnit): LayoutUnit {.borrow.}
func max*(a, b: LayoutUnit): LayoutUnit {.borrow.}

func ceilTo*(a: LayoutUnit; prec: int): LayoutUnit =
  return (1 + ((a - 1) div prec).toInt) * prec
