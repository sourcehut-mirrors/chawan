# 32-bit fixed-point number, with 6 bits of precision.

import std/math

import types/opt
import utils/dtoawrap
import utils/twtstr

type LUnit* = distinct int32

{.push overflowChecks: off, rangeChecks: off.}
template satlu(a: int64): LUnit =
  if unlikely(a < int32.low):
    LUnit.low
  elif unlikely(a > int32.high):
    LUnit.high
  else:
    LUnit(a)

proc `+`*(a, b: LUnit): LUnit {.inline.} =
  let ab = int64(a) + int64(b)
  return satlu(ab)

proc `-`*(a, b: LUnit): LUnit {.inline.} =
  let ab = int64(a) - int64(b)
  return satlu(ab)

proc `*`*(a, b: LUnit): LUnit {.inline.} =
  let ab = (int64(a) * int64(b)) shr 6
  return satlu(ab)

proc `div`*(a, b: LUnit): LUnit {.inline.} =
  let a = int64(uint64(a) shl 12)
  let b = int64(b)
  return LUnit((a div b) shr 6)

proc toLUnit*(a: int32): LUnit =
  let b = int64(a) shl 6
  satlu(b)

proc toLUnit*(a: int): LUnit =
  let b = int64(a) shl 6
  satlu(b)

proc `-`*(a: LUnit): LUnit {.inline.} =
  let a = int32(a)
  if unlikely(a == int32.low):
    return LUnit.high
  return LUnit(-a)
{.pop.} # overflowChecks, rangeChecks

template `'lu`*(s: static string): LUnit =
  (static(parseInt32(s).get.toLUnit()))

proc `==`*(a, b: LUnit): bool {.borrow.}
proc `<`*(a, b: LUnit): bool {.borrow.}
proc `<=`*(a, b: LUnit): bool {.borrow.}

proc toInt*(a: LUnit): int =
  if a < 0'lu:
    return -(int32(-a) shr 6)
  return int32(a) shr 6

proc `+=`*(a: var LUnit; b: LUnit) {.inline.} =
  a = a + b

proc `-=`*(a: var LUnit; b: LUnit) {.inline.} =
  a = a - b

proc `*=`*(a: var LUnit; b: LUnit) {.inline.} =
  a = a * b

proc toLUnit*(a: float32): LUnit =
  let a = round(a * 64)
  if unlikely(a == Inf):
    return LUnit(int32.high)
  elif unlikely(a == -Inf):
    return LUnit(int32.low)
  return LUnit(int32(a))

proc toFloat32*(a: LUnit): float32 =
  return float32(int32(a)) / 64

proc toFloat64*(a: LUnit): float64 =
  return float64(int32(a)) / 64

proc `$`*(a: LUnit): string =
  dtoa(a.toFloat32())

proc min*(a, b: LUnit): LUnit {.borrow.}
proc max*(a, b: LUnit): LUnit {.borrow.}

proc ceilTo*(a: LUnit; prec: int): LUnit =
  let prec = prec.toLUnit()
  return (1 + ((a - 1'lu) div prec).toInt).toLUnit() * prec
