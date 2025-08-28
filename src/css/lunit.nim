# 32-bit fixed-point number, with 6 bits of precision.

type LUnit* = distinct int32

{.push overflowChecks: off, rangeChecks: off.}
template satlu(a: int64): LUnit =
  if unlikely(a < int32.low):
    LUnit.low
  elif unlikely(a > int32.high):
    LUnit.high
  else:
    LUnit(a)

when sizeof(int) == 4 and not defined(nimEmulateOverflowChecks) and
    (defined(gcc) or defined(clang)):
  proc nimAddInt(a, b: int; res: ptr int): bool {.importc, nodecl.}
  proc nimSubInt(a, b: int; res: ptr int): bool {.importc, nodecl.}

  proc `+`*(a, b: LUnit): LUnit {.inline.} =
    let a = int(a)
    let b = int(b)
    var res {.noinit.}: int
    if nimAddInt(a, b, addr res):
      if a > 0:
        return LUnit.high
      return LUnit.low
    return LUnit(res)

  proc `-`*(a, b: LUnit): LUnit {.inline.} =
    let a = int(a)
    let b = int(b)
    var res {.noinit.}: int
    if nimSubInt(a, b, addr res):
      if b < 0:
        return LUnit.high
      return LUnit.low
    return LUnit(res)
else:
  when sizeof(int) == 4:
    {.warning: "Using 64-bit lunit ops on a 32-bit arch".}

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

converter toLUnit*(a: int32): LUnit =
  let a = int64(a) shl 6
  return satlu(a)

converter toLUnit*(a: int): LUnit =
  let a = int64(a) shl 6
  return satlu(a)

proc `-`*(a: LUnit): LUnit {.inline.} =
  let a = int32(a)
  if unlikely(a == int32.high):
    return LUnit.low
  return LUnit(-a)
{.pop.} # overflowChecks, rangeChecks

proc `==`*(a, b: LUnit): bool {.borrow.}
proc `<`*(a, b: LUnit): bool {.borrow.}
proc `<=`*(a, b: LUnit): bool {.borrow.}

proc toInt*(a: LUnit): int =
  if a < 0:
    return -(int32(-a) shr 6)
  return int32(a) shr 6

proc `+=`*(a: var LUnit; b: LUnit) {.inline.} =
  a = a + b

proc `-=`*(a: var LUnit; b: LUnit) {.inline.} =
  a = a - b

proc `*=`*(a: var LUnit; b: LUnit) {.inline.} =
  a = a * b

proc toLUnit*(a: float32): LUnit =
  let a = a * 64
  if unlikely(a == Inf):
    return LUnit(high(int32))
  elif unlikely(a == -Inf):
    return LUnit(low(int32))
  return LUnit(int32(a))

proc toFloat32*(a: LUnit): float32 =
  return float32(int32(a)) / 64

proc `$`*(a: LUnit): string =
  $toFloat32(a)

proc min*(a, b: LUnit): LUnit {.borrow.}
proc max*(a, b: LUnit): LUnit {.borrow.}

proc ceilTo*(a: LUnit; prec: int): LUnit =
  return (1 + ((a - 1) div prec).toInt) * prec
