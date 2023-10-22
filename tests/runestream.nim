import streams

type RuneStream* = ref object of Stream
  at: int # index in u32 (i.e. position * 4)
  source: seq[uint32]

proc runeClose(s: Stream) =
  let s = cast[RuneStream](s)
  s.source.setLen(0)

proc runeReadData(s: Stream, buffer: pointer, bufLen: int): int =
  let s = cast[RuneStream](s)
  let L = min(bufLen, s.source.len - s.at)
  if s.source.len == s.at:
    return
  copyMem(buffer, addr s.source[s.at], L * sizeof(uint32))
  s.at += L
  assert s.at <= s.source.len
  return L * sizeof(uint32)

proc runeAtEnd(s: Stream): bool =
  let s = cast[RuneStream](s)
  return s.at == s.source.len

proc newRuneStream*(source: openarray[uint32]): RuneStream =
  return RuneStream(
    source: @source,
    closeImpl: runeClose,
    readDataImpl: runeReadData,
    atEndImpl: runeAtEnd
  )
