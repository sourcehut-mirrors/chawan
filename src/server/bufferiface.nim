{.push raises: [].}

import io/dynstream
import io/packetreader
import io/packetwriter
import io/promise
import monoucha/jsbind
import monoucha/quickjs
import types/cell

type
  BufferCommand* = enum
    bcCancel = "cancel"
    bcCheckRefresh = "checkRefresh"
    bcClick = "click"
    bcClone = "clone"
    bcContextMenu = "contextMenu"
    bcFindNextLink = "findNextLink"
    bcFindNextMatch = "findNextMatch"
    bcFindNextParagraph = "findNextParagraph"
    bcFindPrevLink = "findPrevLink"
    bcFindPrevMatch = "findPrevMatch"
    bcFindRevNthLink = "findRevNthLink"
    bcForceReshape = "forceReshape"
    bcGetLines = "getLines"
    bcGetLinks = "getLinks"
    bcGetTitle = "getTitle"
    bcGotoAnchor = "gotoAnchor"
    bcHideHints = "hideHints"
    bcLoad = "load"
    bcMarkURL = "markURL"
    bcOnReshape = "onReshape"
    bcReadCanceled = "readCanceled"
    bcReadSuccess = "readSuccess"
    bcSelect = "select"
    bcShowHints = "showHints"
    bcSubmitForm = "submitForm"
    bcToggleImages = "toggleImages"
    bcUpdateHover = "updateHover"
    bcWindowChange = "windowChange"

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

  ReadLineType* = enum
    rltText, rltPassword, rltArea, rltFile

  ReadLineResult* = ref object
    t*: ReadLineType
    prompt*: string
    value*: string

  GotoAnchorResult* = object
    x*: int
    y*: int
    focus*: ReadLineResult

  PagePos* = tuple
    x: int
    y: int

jsDestructor(BufferInterface)

proc addPromise*(iface: BufferInterface; promise: EmptyPromise;
    get: GetValueProc) =
  iface.map.add(BufferIfaceItem(id: iface.packetid, p: promise, get: get))
  inc iface.packetid

proc addEmptyPromise*(iface: BufferInterface): EmptyPromise =
  let promise = EmptyPromise()
  iface.addPromise(promise, nil)
  return promise

proc getFromStream*[T](iface: BufferInterface; promise: EmptyPromise) =
  if iface.len != 0:
    let promise = Promise[T](promise)
    var r: PacketReader
    if iface.stream.initReader(r, iface.len, iface.nfds):
      r.sread(promise.res)
    iface.len = 0
    iface.nfds = 0

proc addPromise*[T](iface: BufferInterface): Promise[T] =
  let promise = Promise[T]()
  iface.addPromise(promise, getFromStream[T])
  return promise

proc lineLoaded*(iface: BufferInterface; y: int): bool =
  let dy = y - iface.lineShift
  return dy in 0 ..< iface.lines.len

template withPacketWriterFire(iface: BufferInterface; cmd: BufferCommand;
    w, body: untyped) =
  iface.stream.withPacketWriterFire w:
    w.swrite(cmd)
    w.swrite(iface.packetid)
    body

proc onReshape*(iface: BufferInterface): EmptyPromise =
  iface.withPacketWriterFire bcOnReshape, w:
    discard
  return iface.addEmptyPromise()

proc gotoAnchor*(iface: BufferInterface; anchor: string;
    autofocus, target: bool): Promise[GotoAnchorResult] =
  iface.withPacketWriterFire bcGotoAnchor, w:
    w.swrite(anchor)
    w.swrite(autofocus)
    w.swrite(target)
  return addPromise[GotoAnchorResult](iface)

proc findNextLink(iface: BufferInterface; x, y, n: int): Promise[PagePos]
    {.jsfunc.} =
  iface.withPacketWriterFire bcFindNextLink, w:
    w.swrite(x)
    w.swrite(y)
    w.swrite(n)
  return addPromise[PagePos](iface)

#TODO findPrevLink & findRevNthLink should probably be merged into findNextLink
proc findPrevLink(iface: BufferInterface; x, y, n: int): Promise[PagePos]
    {.jsfunc.} =
  iface.withPacketWriterFire bcFindPrevLink, w:
    w.swrite(x)
    w.swrite(y)
    w.swrite(n)
  return addPromise[PagePos](iface)

proc findRevNthLink(iface: BufferInterface; x, y, n: int): Promise[PagePos]
    {.jsfunc.} =
  iface.withPacketWriterFire bcFindPrevLink, w:
    w.swrite(x)
    w.swrite(y)
    w.swrite(n)
  return addPromise[PagePos](iface)

proc findNextParagraph(iface: BufferInterface; y, n: int): Promise[int]
    {.jsfunc.} =
  iface.withPacketWriterFire bcFindNextParagraph, w:
    w.swrite(y)
    w.swrite(n)
  return addPromise[int](iface)

proc markURL(iface: BufferInterface): EmptyPromise {.jsfunc.} =
  iface.withPacketWriterFire bcMarkURL, w:
    discard
  return addEmptyPromise(iface)

proc forceReshape(iface: BufferInterface): EmptyPromise {.jsfunc.} =
  iface.withPacketWriterFire bcForceReshape, w:
    discard
  return addEmptyPromise(iface)

proc addBufferInterfaceModule*(ctx: JSContext): JSClassID =
  return ctx.registerType(BufferInterface)

{.pop.}
