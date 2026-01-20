{.push raises: [].}

import io/dynstream
import io/promise
import types/cell

type
  BufferIfaceItem* = object
    id*: int
    p*: EmptyPromise
    get*: GetValueProc

  GetValueProc* = proc(iface: BufferInterface; promise: EmptyPromise) {.
    nimcall, raises: [].}

  BufferInterface* = ref object
    map*: seq[BufferIfaceItem]
    packetid*: int
    len*: int
    nfds*: int
    stream*: BufStream
    lines*: SimpleFlexibleGrid
    lineShift*: int

proc lineLoaded*(iface: BufferInterface; y: int): bool =
  let dy = y - iface.lineShift
  return dy in 0 ..< iface.lines.len

{.pop.}
