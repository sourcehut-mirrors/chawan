# Based on https://github.com/N-R-K/ChibiHash

{.push raises: [].}

import std/endians

type Hash* = int

{.push overflowChecks: off.}
proc load32le(p: openArray[uint8]; i: int): uint64 =
  when nimvm:
    return p[0] or (p[1] shl 8) or (p[2] shl 16) or (p[3] shl 24)
  var x: uint64
  {.push boundChecks: off.}
  littleEndian32(addr x, unsafeAddr p[i])
  {.pop.}
  x

proc load64le(p: openArray[uint8]; i: int): uint64 =
  load32le(p, i) or (load32le(p, i + 4) shl 32)

proc rotl(x: uint64; n: int): uint64 =
  (x shl n) or (x shr (-n and 63))

proc chibihash64(key: openArray[uint8]; seed: uint64): uint64 =
  var p = 0
  let L = key.len
  var l = L
  let K = 0x2B7E151628AED2A7'u64
  let seed2 = rotl(seed - K, 15) + rotl(seed - K, 47)
  var h = [seed, seed + K, seed2, seed2 + (K * K xor K)]
  while l >= 32:
    for i in 0 ..< 4:
      let stripe = load64le(key, p)
      h[i] = (stripe + h[i]) * K
      h[(i + 1) and 3] += rotl(stripe, 27)
      p += 8
    l -= 32
  while l >= 8:
    h[0] = (h[0] xor load32le(key, p)) * K
    h[1] = (h[1] xor load32le(key, p + 4)) * K
    p += 8
    l -= 8
  if l >= 4:
    h[2] = h[2] xor load32le(key, p)
    h[3] = h[3] xor load32le(key, p + l - 4)
  elif l > 0:
    {.push boundChecks: off.}
    h[2] = h[2] xor key[p]
    h[3] = h[3] xor (key[p + l div 2] or (uint64(key[p + l - 1]) shl 8))
    {.pop.}
  h[0] += rotl(h[2] * K, 31) xor (h[2] shr 31)
  h[1] += rotl(h[3] * K, 31) xor (h[3] shr 31)
  h[0] *= K
  h[0] = h[0] xor (h[0] shr 31)
  h[1] += h[0]
  var x = uint64(L) * K
  x = x xor rotl(x, 29)
  x += seed
  x = x xor h[1]
  x = x xor rotl(x, 15) xor rotl(x, 42)
  x *= K
  x = x xor rotl(x, 13) xor rotl(x, 31)
  x

proc chibihash64*(key: openArray[char]; seed: uint64): uint64 =
  chibihash64(key.toOpenArrayByte(0, key.len - 1), seed)

proc hash*(s: openArray[char]): Hash =
  cast[Hash](chibihash64(s, 0))

proc hash*(n: int): Hash =
  let pc = cast[ptr UncheckedArray[char]](unsafeAddr n)
  hash(pc.toOpenArray(0, sizeof(n) - 1))

proc hash*(p: pointer): Hash =
  hash(cast[int](p))

proc hash*(u: uint32): Hash =
  let pc = cast[ptr UncheckedArray[char]](unsafeAddr u)
  hash(pc.toOpenArray(0, 3))

# from std
proc `!&`*(h: Hash; val: int): Hash =
  let h = uint(h)
  let val = uint(val)
  var res = h + val
  res += res shl 10
  res = res xor (res shr 6)
  cast[Hash](res)

proc `!$`*(h: Hash): Hash =
  let h = uint(h)
  var res = h + h shl 3
  res = res xor (res shr 11)
  res += res shl 15
  cast[Hash](res)

{.pop.} # overflowChecks: off

{.pop.} # raises: []
