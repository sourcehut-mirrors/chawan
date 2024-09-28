import std/deques
import std/net
import std/posix
import std/tables

import io/bufwriter
import io/dynstream
import loader/headers

when defined(debug):
  import types/url

const LoaderBufferPageSize = 4064 # 4096 - 32

type
  LoaderBufferObj = object
    page*: ptr UncheckedArray[uint8]
    len*: int

  CachedItem* = ref object
    id*: int
    refc*: int
    offset*: int
    path*: string

  LoaderBuffer* = ref LoaderBufferObj

  LoaderHandle* = ref object of RootObj
    registered*: bool # track registered state
    stream*: PosixStream # input/output stream depending on type
    when defined(debug):
      url*: URL

  InputHandle* = ref object of LoaderHandle
    outputs*: seq[OutputHandle] # list of outputs to be streamed into
    cacheId*: int # if cached, our ID in a client cacheMap
    cacheRef*: CachedItem # if this is a tocache handle, a ref to our cache item
    parser*: HeaderParser # only exists for CGI handles
    rstate: ResponseState # track response state

  OutputHandle* = ref object of LoaderHandle
    parent*: InputHandle
    currentBuffer*: LoaderBuffer
    currentBufferIdx*: int
    buffers*: Deque[LoaderBuffer]
    istreamAtEnd*: bool
    ownerPid*: int
    outputId*: int
    suspended*: bool
    dead*: bool

  HandleParserState* = enum
    hpsBeforeLines, hpsAfterFirstLine, hpsControlDone

  HeaderParser* = ref object
    state*: HandleParserState
    lineBuffer*: string
    crSeen*: bool
    headers*: Headers
    status*: uint16

  ResponseState = enum
    rsBeforeResult, rsAfterFailure, rsBeforeStatus, rsBeforeHeaders,
    rsAfterHeaders

proc `=destroy`(buffer: var LoaderBufferObj) =
  if buffer.page != nil:
    dealloc(buffer.page)
    buffer.page = nil

# for debugging
when defined(debug):
  func `$`*(buffer: LoaderBuffer): string =
    var s = newString(buffer.len)
    copyMem(addr s[0], addr buffer.page[0], buffer.len)
    return s

# Create a new loader handle, with the output stream ostream.
proc newInputHandle*(ostream: PosixStream; outputId, pid: int;
    suspended = true): InputHandle =
  let handle = InputHandle(cacheId: -1)
  handle.outputs.add(OutputHandle(
    stream: ostream,
    parent: handle,
    outputId: outputId,
    ownerPid: pid,
    suspended: suspended
  ))
  return handle

proc findOutputHandle*(handle: InputHandle; fd: int): OutputHandle =
  for output in handle.outputs:
    if output.stream.fd == fd:
      return output
  return nil

func cap*(buffer: LoaderBuffer): int {.inline.} =
  return LoaderBufferPageSize

template isEmpty*(output: OutputHandle): bool =
  output.currentBuffer == nil and not output.suspended

proc newLoaderBuffer*(size = LoaderBufferPageSize): LoaderBuffer =
  return LoaderBuffer(
    page: cast[ptr UncheckedArray[uint8]](alloc(size)),
    len: 0
  )

proc bufferCleared*(output: OutputHandle) =
  assert output.currentBuffer != nil
  output.currentBufferIdx = 0
  if output.buffers.len > 0:
    output.currentBuffer = output.buffers.popFirst()
  else:
    output.currentBuffer = nil

proc tee*(outputIn: OutputHandle; ostream: PosixStream; outputId, pid: int):
    OutputHandle =
  assert outputIn.suspended
  let output = OutputHandle(
    parent: outputIn.parent,
    stream: ostream,
    currentBuffer: outputIn.currentBuffer,
    currentBufferIdx: outputIn.currentBufferIdx,
    buffers: outputIn.buffers,
    istreamAtEnd: outputIn.istreamAtEnd,
    outputId: outputId,
    ownerPid: pid,
    suspended: outputIn.suspended
  )
  when defined(debug):
    output.url = outputIn.url
  if outputIn.parent != nil:
    assert outputIn.parent.parser == nil
    outputIn.parent.outputs.add(output)
  return output

template output*(handle: InputHandle): OutputHandle =
  handle.outputs[0]

proc sendResult*(handle: InputHandle; res: int; msg = "") =
  assert handle.rstate == rsBeforeResult
  inc handle.rstate
  let output = handle.output
  let blocking = output.stream.blocking
  output.stream.setBlocking(true)
  output.stream.withPacketWriter w:
    w.swrite(res)
    if res == 0: # success
      assert msg == ""
      w.swrite(output.outputId)
      inc handle.rstate
    else: # error
      w.swrite(msg)
  output.stream.setBlocking(blocking)

proc sendStatus*(handle: InputHandle; status: uint16) =
  assert handle.rstate == rsBeforeStatus
  inc handle.rstate
  let blocking = handle.output.stream.blocking
  handle.output.stream.setBlocking(true)
  handle.output.stream.withPacketWriter w:
    w.swrite(status)
  handle.output.stream.setBlocking(blocking)

proc sendHeaders*(handle: InputHandle; headers: Headers) =
  assert handle.rstate == rsBeforeHeaders
  inc handle.rstate
  let blocking = handle.output.stream.blocking
  handle.output.stream.setBlocking(true)
  handle.output.stream.withPacketWriter w:
    w.swrite(headers)
  handle.output.stream.setBlocking(blocking)

proc recvData*(ps: PosixStream; buffer: LoaderBuffer): int {.inline.} =
  let n = ps.recvData(addr buffer.page[0], buffer.cap)
  buffer.len = n
  return n

proc sendData*(ps: PosixStream; buffer: LoaderBuffer; si = 0): int {.inline.} =
  assert buffer.len - si > 0
  return ps.sendData(addr buffer.page[si], buffer.len - si)

proc iclose*(handle: InputHandle) =
  if handle.stream != nil:
    assert not handle.registered
    if handle.rstate notin {rsBeforeResult, rsAfterFailure, rsAfterHeaders}:
      assert handle.outputs.len == 1
      # not an ideal solution, but better than silently eating malformed
      # headers
      try:
        if handle.rstate == rsBeforeStatus:
          handle.sendStatus(500)
        if handle.rstate == rsBeforeHeaders:
          handle.sendHeaders(newHeaders())
        handle.output.stream.setBlocking(true)
        const msg = "Error: malformed header in CGI script"
        discard handle.output.stream.sendData(msg)
      except ErrorBrokenPipe:
        discard # receiver is dead
    handle.stream.sclose()
    handle.stream = nil

proc oclose*(output: OutputHandle) =
  assert not output.registered
  output.stream.sclose()
  output.stream = nil

proc close*(handle: InputHandle) =
  handle.iclose()
  for output in handle.outputs:
    if output.stream != nil:
      output.oclose()
