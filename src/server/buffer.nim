{.push raises: [].}

from std/strutils import split

import std/macros
import std/options
import std/os
import std/posix
import std/tables

import chagashi/charset
import chagashi/decoder
import chagashi/decodercore
import chame/htmlparser
import chame/tags
import config/config
import config/conftypes
import css/box
import css/csstree
import css/layout
import css/lunit
import css/render
import html/catom
import html/chadombuilder
import html/dom
import html/env
import html/event
import html/formdata as formdata_impl
import io/chafile
import io/console
import io/dynstream
import io/packetreader
import io/packetwriter
import io/poll
import io/promise
import io/timeout
import local/select
import monoucha/fromjs
import monoucha/javascript
import monoucha/jsregex
import monoucha/libregexp
import monoucha/quickjs
import server/headers
import server/loaderiface
import server/request
import types/blob
import types/cell
import types/color
import types/formdata
import types/opt
import types/refstring
import types/url
import types/winattrs
import utils/strwidth
import utils/twtstr

type
  BufferCommand* = enum
    bcCancel = "cancel"
    bcCheckRefresh = "checkRefresh"
    bcClick = "click"
    bcClone = "clone"
    bcFindNextLink = "findNextLink"
    bcFindNextMatch = "findNextMatch"
    bcFindNextParagraph = "findNextParagraph"
    bcFindNthLink = "findNthLink"
    bcFindPrevLink = "findPrevLink"
    bcFindPrevMatch = "findPrevMatch"
    bcFindPrevParagraph = "findPrevParagraph"
    bcFindRevNthLink = "findRevNthLink"
    bcForceReshape = "forceReshape"
    bcGetLines = "getLines"
    bcGetLinks = "getLinks"
    bcGetTitle = "getTitle"
    bcGotoAnchor = "gotoAnchor"
    bcLoad = "load"
    bcMarkURL = "markURL"
    bcOnReshape = "onReshape"
    bcReadCanceled = "readCanceled"
    bcReadSuccess = "readSuccess"
    bcSelect = "select"
    bcToggleImages = "toggleImages"
    bcUpdateHover = "updateHover"
    bcWindowChange = "windowChange"

  BufferState = enum
    bsLoadingPage, bsLoadingResources, bsLoadingImages, bsLoadingImagesAck,
    bsLoaded

  HoverType* = enum
    htTitle, htLink, htImage, htCachedImage

  BufferMatch* = object
    success*: bool
    x*: int
    y*: int
    str*: string

  InputData = ref object of MapData

  BufferContext = ref object
    firstBufferRead: bool
    headlessLoading: bool
    ishtml: bool
    needsBOMSniff: bool
    onReshapeImmediately: bool
    savetask: bool
    state: BufferState
    charset: Charset
    bgcolor: CellColor
    attrs: WindowAttributes
    bytesRead: int
    cacheId: int
    charsetStack: seq[Charset]
    config: BufferConfig
    ctx: TextDecoderContext
    hoverText: array[HoverType, string]
    htmlParser: HTML5ParserWrapper
    images: seq[PosBitmap]
    lines: FlexibleGrid
    loader: FileLoader
    navigateUrl: URL # stored when JS tries to navigate
    outputId: int
    pollData: PollData
    prevHover: Element
    clickResult: ClickResult
    pstream: SocketStream # control stream
    reportedBytesRead: int
    rootBox: BlockBox
    tasks: array[BufferCommand, int] #TODO this should have arguments
    window: Window

  BufferIfaceItem = object
    id: int
    p: EmptyPromise
    get: GetValueProc

  BufferInterface* = ref object
    map: seq[BufferIfaceItem]
    packetid: int
    len: int
    nfds: int
    stream*: BufStream

  BufferConfig* = object
    refererFrom*: bool
    styling*: bool
    scripting*: ScriptingMode
    images*: bool
    headless*: HeadlessMode
    autofocus*: bool
    history*: bool
    markLinks*: bool
    charsetOverride*: Charset
    metaRefresh*: MetaRefresh
    colorMode*: ColorMode
    charsets*: seq[Charset]
    imageTypes*: Table[string, string]
    userAgent*: string
    referrer*: string
    userStyle*: string

  GetValueProc = proc(iface: BufferInterface; promise: EmptyPromise) {.
    nimcall, raises: [].}

  ReadLineType* = enum
    rltText, rltArea, rltFile

  ReadLineResult* = ref object
    t*: ReadLineType
    hide*: bool
    prompt*: string
    value*: string

  SelectResult* = ref object
    options*: seq[SelectOption]
    selected*: int

  ClickResult* = ref object
    open*: Request
    contentType*: string
    readline*: Option[ReadLineResult]
    select*: Option[SelectResult]

# Forward declarations
proc click(bc: BufferContext; clickable: Element): ClickResult
proc submitForm(bc: BufferContext; form: HTMLFormElement;
  submitter: HTMLElement; jsSubmitCall = false): Request

template document(bc: BufferContext): Document =
  bc.window.document

proc getFromStream[T](iface: BufferInterface; promise: EmptyPromise) =
  if iface.len != 0:
    let promise = Promise[T](promise)
    var r: PacketReader
    if iface.stream.initReader(r, iface.len, iface.nfds):
      r.sread(promise.res)
    iface.len = 0
    iface.nfds = 0

proc addPromise[T](iface: BufferInterface; id: int): Promise[T] =
  let promise = Promise[T]()
  iface.map.add(BufferIfaceItem(id: id, p: promise, get: getFromStream[T]))
  return promise

proc addEmptyPromise(iface: BufferInterface; id: int): EmptyPromise =
  let promise = EmptyPromise()
  iface.map.add(BufferIfaceItem(id: id, p: promise, get: nil))
  return promise

proc findPromise(iface: BufferInterface; id: int): int =
  for i, it in iface.map.mypairs:
    if it.id == id:
      return i
  return -1

proc resolve(iface: BufferInterface; id: int) =
  let i = iface.findPromise(id)
  if i != -1:
    let it = iface.map[i]
    if it.get != nil:
      it.get(iface, it.p)
    it.p.resolve()
    iface.map.del(i)

proc newBufferInterface*(stream: BufStream): BufferInterface =
  return BufferInterface(
    packetid: 1, # ids below 1 are invalid
    stream: stream
  )

# After cloning a buffer, we need a new interface to the new buffer
# process.
# Here we create a new interface for that clone.
proc cloneInterface*(stream: BufStream): BufferInterface =
  let iface = newBufferInterface(stream)
  #TODO buffered data should probably be copied here
  # We have just fork'ed the buffer process inside an interface
  # function, from which the new buffer is going to return as well.
  # So we must also consume the return value of the clone function,
  # which is the pid 0.
  var pid = -1
  stream.withPacketReaderFire r:
    r.sread(iface.packetid)
    r.sread(pid)
  if pid == -1:
    return nil
  return iface

proc resolve*(iface: BufferInterface; packetid, len, nfds: int) =
  iface.len = len
  iface.nfds = nfds
  iface.resolve(packetid)
  # Protection against accidentally not exhausting data available to read,
  # by setting len to 0 in getFromStream.
  # (If this assertion is failing, then it means you then()'ed a promise which
  # should read something from the stream with an empty function.)
  assert iface.len == 0

proc hasPromises*(iface: BufferInterface): bool =
  return iface.map.len > 0

# For each proxied command, we create two procs: a) an interface proc to
# send packets to buffer, then read result (overloaded, but has the same
# name); b) a proxy proc to read packets in buffer, call proxied proc,
# and send back the result (nameCmd).
type ProxyFlag = enum
  pfNone, pfTask

proc buildInterfaceProc(name, params: NimNode; cmd: BufferCommand): NimNode =
  let name = ident(name.strVal).postfix("*")
  let retval = params[0] # sym
  assert params.len >= 2 # return type, this value
  let this2 = newIdentDefs(ident("iface"), ident("BufferInterface"))
  let thisval = this2[0]
  var retval2: NimNode
  var addfun: NimNode
  if retval.kind == nnkEmpty:
    addfun = quote do:
      `thisval`.addEmptyPromise(`thisval`.packetid)
    retval2 = ident("EmptyPromise")
  else:
    addfun = quote do:
      addPromise[`retval`](`thisval`, `thisval`.packetid)
    retval2 = newNimNode(nnkBracketExpr).add(ident("Promise"), retval)
  var params2 = @[retval2, this2]
  # flatten args
  for i in 2 ..< params.len:
    let param = params[i]
    for i in 0 ..< param.len - 2:
      let id2 = newIdentDefs(ident(param[i].strVal), param[^2])
      params2.add(id2)
  let writeStmts = newStmtList()
  for i in 2 ..< params2.len:
    let s = params2[i][0] # sym e.g. url
    writeStmts.add(quote do: writer.swrite(`s`))
  let body = quote do:
    `thisval`.stream.withPacketWriterFire writer:
      writer.swrite(BufferCommand(`cmd`))
      writer.swrite(`thisval`.packetid)
      `writeStmts`
    let promise = `addfun`
    inc `thisval`.packetid
    return promise
  let pragmas = if retval.kind == nnkEmpty:
    newNimNode(nnkPragma).add(ident("discardable"))
  else:
    newEmptyNode()
  return newProc(name, params2, body, pragmas = pragmas)

proc buildProxyProc(name, params: NimNode; cmd: BufferCommand; flag: ProxyFlag):
    NimNode =
  let stmts = newStmtList()
  let r = ident("r")
  let bc = ident("bc")
  let packetid = ident("packetid")
  let call = newCall(name, ident("bc"))
  for i in 2 ..< params.len:
    let param = params[i]
    for i in 0 ..< param.len - 2:
      let id = ident(param[i].strVal)
      let typ = param[^2]
      stmts.add(quote do:
        var `id`: `typ`
        `r`.sread(`id`)
      )
      call.add(id)
  let hasRes = params[0].kind == nnkEmpty
  if hasRes:
    stmts.add(call)
  else:
    stmts.add(quote do:
      let retval {.inject.} = `call`)
  let resolve = if hasRes:
    quote do:
      `bc`.pstream.withPacketWriter wt:
        wt.swrite(`packetid`)
      do:
        quit(1)
  else:
    quote do:
      `bc`.pstream.withPacketWriter wt:
        wt.swrite(`packetid`)
        wt.swrite(retval)
      do:
        quit(1)
  case flag
  of pfTask:
    stmts.add(quote do:
      if `bc`.savetask:
        `bc`.savetask = false
        `bc`.tasks[BufferCommand(`cmd`)] = `packetid`
      else:
        `resolve`
    )
  of pfNone:
    stmts.add(resolve)
  let name = ident(name.strVal & "Cmd")
  quote do:
    proc `name`(`bc`: BufferContext; `r`: var PacketReader; `packetid`: int) =
      `stmts`

macro proxyt(flag: static ProxyFlag; fun: typed) =
  let name = fun.name # sym
  let params = fun.params # formalParams
  let cmd = strictParseEnum[BufferCommand](name.strVal).get
  let iproc = buildInterfaceProc(name, params, cmd)
  let pproc = buildProxyProc(name, params, cmd, flag)
  quote do:
    `fun`
    `iproc`
    `pproc`

template proxy(fun: untyped) =
  proxyt(pfNone, fun)

template proxy(flag, fun: untyped) =
  proxyt(flag, fun)

proc getTitleAttr(bc: BufferContext; element: Element): string =
  if element != nil:
    for element in element.branchElems:
      if element.attrb(satTitle):
        return element.attr(satTitle)
  return ""

const ClickableElements = {
  TAG_A, TAG_INPUT, TAG_OPTION, TAG_BUTTON, TAG_TEXTAREA, TAG_LABEL,
  TAG_VIDEO, TAG_AUDIO, TAG_IFRAME, TAG_FRAME
}

proc isClickable(element: Element): bool =
  if element.hasEventListener(satClick.toAtom()):
    return true
  if element of HTMLAnchorElement:
    return HTMLAnchorElement(element).reinitURL().isOk
  if element.isButton() and FormAssociatedElement(element).form == nil:
    return false
  return element.tagType in ClickableElements

proc getClickable(element: Element): Element =
  for element in element.branchElems:
    if element.isClickable():
      return element
  return nil

proc canSubmitOnClick(fae: FormAssociatedElement): bool =
  if fae.form == nil:
    return false
  if fae.form.canSubmitImplicitly():
    return true
  if fae of HTMLButtonElement and HTMLButtonElement(fae).ctype == btSubmit:
    return true
  if fae of HTMLInputElement and
      HTMLInputElement(fae).inputType in {itSubmit, itButton}:
    return true
  return false

proc getImageHover(bc: BufferContext; element: Element): string =
  if element of HTMLImageElement:
    let image = HTMLImageElement(element)
    let src = image.attr(satSrc)
    if src != "":
      if url := image.document.parseURL(src):
        return $url
  ""

proc getClickHover(bc: BufferContext; element: Element): string =
  let clickable = element.getClickable()
  if clickable != nil:
    case clickable.tagType
    of TAG_A:
      if url := HTMLAnchorElement(clickable).reinitURL():
        return $url
    of TAG_OPTION:
      return "<option>"
    of TAG_VIDEO, TAG_AUDIO:
      let (src, _) = HTMLElement(clickable).getSrc()
      if src != "":
        if url := clickable.document.parseURL(src):
          return $url
    of TAG_FRAME, TAG_IFRAME:
      let src = clickable.attr(satSrc)
      if src != "":
        if url := clickable.document.parseURL(src):
          return $url
    elif clickable of FormAssociatedElement:
      let fae = FormAssociatedElement(clickable)
      if fae.canSubmitOnClick():
        let req = bc.submitForm(fae.form, fae)
        if req != nil:
          return $req.url
      return "<" & $clickable.tagType & ">"
  ""

proc getCachedImageHover(bc: BufferContext; element: Element): string =
  if element of HTMLImageElement:
    let image = HTMLImageElement(element)
    if image.bitmap != nil and image.bitmap.cacheId != 0:
      return $image.bitmap.cacheId & ' ' & image.bitmap.contentType
  elif element of SVGSVGElement:
    let image = SVGSVGElement(element)
    if image.bitmap != nil and image.bitmap.cacheId != 0:
      return $image.bitmap.cacheId & ' ' & image.bitmap.contentType
  ""

proc getCursorElement(bc: BufferContext; cursorx, cursory: int): Element =
  let i = bc.lines[cursory].findFormatN(cursorx) - 1
  if i >= 0:
    return bc.lines[cursory].formats[i].node
  return nil

proc getCursorClickable(bc: BufferContext; cursorx, cursory: int): Element =
  let element = bc.getCursorElement(cursorx, cursory)
  if element != nil:
    return element.getClickable()
  return nil

proc cursorBytes(bc: BufferContext; y, cc: int): int =
  let line = bc.lines[y].str
  var w = 0
  var i = 0
  while i < line.len and w < cc:
    let u = line.nextUTF8(i)
    w += u.width()
  return i

proc navigate(bc: BufferContext; url: URL) =
  let stderr = cast[ChaFile](stderr)
  bc.navigateUrl = url
  discard stderr.writeLine("navigate to " & $url)

#TODO rewrite findPrevLink, findNextLink to use the box tree instead
proc findPrevLink*(bc: BufferContext; cursorx, cursory, n: int):
    tuple[x, y: int] {.proxy.} =
  if cursory >= bc.lines.len:
    return (-1, -1)
  var found = 0
  var i = bc.lines[cursory].findFormatN(cursorx) - 1
  var link: Element = nil
  if cursorx == int.high:
    # Special case for when we want to jump to the last link on this
    # line (for cursorLinkNavUp).
    i = bc.lines[cursory].formats.len
  elif i >= 0:
    link = bc.lines[cursory].formats[i].node.getClickable()
  dec i
  var ly = 0 # last y
  var lx = 0 # last x
  for y in countdown(cursory, 0):
    let line = bc.lines[y]
    if y != cursory:
      i = line.formats.len - 1
    while i >= 0:
      let format = line.formats[i]
      let fl = format.node.getClickable()
      if fl != nil and fl != link:
        # go to beginning of link
        ly = y
        lx = format.pos
        # on the current line
        while i >= 0:
          let format = line.formats[i]
          let nl = format.node.getClickable()
          if nl == fl:
            lx = format.pos
          dec i
        # on previous lines
        for iy in countdown(ly - 1, 0):
          let line = bc.lines[iy]
          i = line.formats.len - 1
          let oly = iy
          let olx = lx
          while i >= 0:
            let format = line.formats[i]
            let nl = format.node.getClickable()
            if nl == fl:
              ly = iy
              lx = format.pos
            dec i
          if iy == oly and olx == lx:
            # Assume all multiline anchors are placed on consecutive
            # lines.
            # This is not true, but otherwise we would have to loop
            # through the entire document.
            # TODO: find an efficient and correct way to do this.
            break
        inc found
        if found == n:
          return (lx, ly)
        link = fl
      dec i
  return (-1, -1)

proc findNextLink*(bc: BufferContext; cursorx, cursory, n: int):
    tuple[x, y: int] {.proxy.} =
  if cursory >= bc.lines.len:
    return (-1, -1)
  var found = 0
  var i = bc.lines[cursory].findFormatN(cursorx) - 1
  var link: Element = nil
  if i >= 0:
    link = bc.lines[cursory].formats[i].node.getClickable()
  inc i
  for j, line in bc.lines.toOpenArray(cursory, bc.lines.high).mypairs:
    while i < line.formats.len:
      let format = line.formats[i]
      let fl = format.node.getClickable()
      if fl != nil and fl != link:
        inc found
        if found == n:
          return (format.pos, cursory + j)
        link = fl
      inc i
    i = 0
  return (-1, -1)

proc findPrevParagraph*(bc: BufferContext; cursory, n: int): int {.proxy.} =
  var y = cursory
  for i in 0 ..< n:
    while y >= 0 and bc.lines[y].str.onlyWhitespace():
      dec y
    while y >= 0 and not bc.lines[y].str.onlyWhitespace():
      dec y
  return y

proc findNextParagraph*(bc: BufferContext; cursory, n: int): int {.proxy.} =
  var y = cursory
  for i in 0 ..< n:
    while y < bc.lines.len and bc.lines[y].str.onlyWhitespace():
      inc y
    while y < bc.lines.len and not bc.lines[y].str.onlyWhitespace():
      inc y
  return y

proc findNthLink*(bc: BufferContext; i: int): tuple[x, y: int] {.proxy.} =
  if i == 0:
    return (-1, -1)
  var k = 0
  var link: Element
  for y in 0 .. bc.lines.high:
    let line = bc.lines[y]
    for j in 0 ..< line.formats.len:
      let format = line.formats[j]
      let fl = format.node.getClickable()
      if fl != nil and fl != link:
        inc k
        if k == i:
          return (format.pos, y)
        link = fl
  return (-1, -1)

proc findRevNthLink*(bc: BufferContext; i: int): tuple[x, y: int] {.proxy.} =
  if i == 0:
    return (-1, -1)
  var k = 0
  var link: Element
  for y in countdown(bc.lines.high, 0):
    let line = bc.lines[y]
    for j in countdown(line.formats.high, 0):
      let format = line.formats[j]
      let fl = format.node.getClickable()
      if fl != nil and fl != link:
        inc k
        if k == i:
          return (format.pos, y)
        link = fl
  return (-1, -1)

proc findPrevMatch*(bc: BufferContext; regex: Regex; cursorx, cursory: int;
    wrap: bool, n: int): BufferMatch {.proxy.} =
  if cursory >= bc.lines.len: return BufferMatch()
  var y = cursory
  let b = bc.cursorBytes(y, cursorx)
  let res = regex.exec(bc.lines[y].str, 0, b)
  var numfound = 0
  if res.captures.len > 0:
    let cap = res.captures[^1][0]
    let x = bc.lines[y].str.width(0, cap.s)
    let str = bc.lines[y].str.substr(cap.s, cap.e - 1)
    inc numfound
    if numfound >= n:
      return BufferMatch(success: true, x: x, y: y, str: str)
  dec y
  while true:
    if y < 0:
      if wrap:
        y = bc.lines.high
      else:
        break
    let res = regex.exec(bc.lines[y].str)
    if res.captures.len > 0:
      let cap = res.captures[^1][0]
      let x = bc.lines[y].str.width(0, cap.s)
      let str = bc.lines[y].str.substr(cap.s, cap.e - 1)
      inc numfound
      if numfound >= n:
        return BufferMatch(success: true, x: x, y: y, str: str)
    if y == cursory:
      break
    dec y
  BufferMatch()

proc findNextMatch*(bc: BufferContext; regex: Regex; cursorx, cursory: int;
    wrap: bool; n: int): BufferMatch {.proxy.} =
  if cursory >= bc.lines.len: return BufferMatch()
  var y = cursory
  let b = bc.cursorBytes(y, cursorx + 1)
  let res = regex.exec(bc.lines[y].str, b, bc.lines[y].str.len)
  var numfound = 0
  if res.success and res.captures.len > 0:
    let cap = res.captures[0][0]
    let x = bc.lines[y].str.width(0, cap.s)
    let str = bc.lines[y].str.substr(cap.s, cap.e - 1)
    inc numfound
    if numfound >= n:
      return BufferMatch(success: true, x: x, y: y, str: str)
  inc y
  while true:
    if y > bc.lines.high:
      if wrap:
        y = 0
      else:
        break
    let res = regex.exec(bc.lines[y].str)
    if res.success and res.captures.len > 0:
      let cap = res.captures[0][0]
      let x = bc.lines[y].str.width(0, cap.s)
      let str = bc.lines[y].str.substr(cap.s, cap.e - 1)
      inc numfound
      if numfound >= n:
        return BufferMatch(success: true, x: x, y: y, str: str)
    if y == cursory:
      break
    inc y
  BufferMatch()

type GotoAnchorResult* = object
  found*: bool
  x*: int
  y*: int
  focus*: ReadLineResult

proc findAnchor(box: CSSBox; anchor: Element): Offset =
  for child in box.children:
    let off = child.findAnchor(anchor)
    if off.y >= 0:
      return off
  if box.element == anchor:
    return box.render.offset
  return offset(-1, -1)

proc gotoAnchor*(bc: BufferContext; anchor: string; autofocus, target: bool):
    GotoAnchorResult {.proxy.} =
  if bc.document == nil:
    return GotoAnchorResult(found: false)
  if anchor.len > 0 and anchor[0] == 'L' and not bc.ishtml:
    let y = parseIntP(anchor.toOpenArray(1, anchor.high)).get(-1)
    if y > 0:
      return GotoAnchorResult(found: true, x: 0, y: y - 1)
  var element = bc.document.findAnchor(anchor)
  if element == nil:
    let s = percentDecode(anchor)
    if s != anchor:
      element = bc.document.findAnchor(s)
  if target and element != nil:
    bc.document.setTarget(element)
  var focus: ReadLineResult = nil
  # Do not use bc.config.autofocus when we just want to check if the
  # anchor can be found.
  if autofocus:
    let autofocus = bc.document.findAutoFocus()
    if autofocus != nil:
      if element == nil:
        element = autofocus # jump to autofocus instead
      let res = bc.click(autofocus)
      focus = res.readline.get(nil)
  if element == nil:
    return GotoAnchorResult(found: false)
  let offset = bc.rootBox.findAnchor(element)
  let x = max(offset.x div bc.attrs.ppc, 0).toInt
  let y = max(offset.y div bc.attrs.ppl, 0).toInt
  return GotoAnchorResult(found: true, x: x, y: y, focus: focus)

proc checkRefresh*(bc: BufferContext): CheckRefreshResult {.proxy.} =
  if bc.navigateUrl != nil:
    let url = bc.navigateUrl
    bc.navigateUrl = nil
    return CheckRefreshResult(n: 0, url: url)
  if bc.document == nil:
    return CheckRefreshResult(n: -1)
  let element = bc.document.findMetaRefresh()
  if element == nil:
    return CheckRefreshResult(n: -1)
  return parseRefresh(element.attr(satContent), bc.document.url)

proc hasTask(bc: BufferContext; cmd: BufferCommand): bool =
  return bc.tasks[cmd] != 0

proc resolveTask(bc: BufferContext; cmd: BufferCommand) =
  let packetid = bc.tasks[cmd]
  assert packetid != 0
  bc.pstream.withPacketWriter wt:
    wt.swrite(packetid)
  do:
    quit(1)
  bc.tasks[cmd] = 0

proc resolveTask[T](bc: BufferContext; cmd: BufferCommand; res: T) =
  let packetid = bc.tasks[cmd]
  assert packetid != 0
  bc.pstream.withPacketWriter wt:
    wt.swrite(packetid)
    wt.swrite(res)
  do:
    quit(1)
  bc.tasks[cmd] = 0

proc maybeReshape(bc: BufferContext) =
  let document = bc.document
  if document == nil or document.documentElement == nil:
    return # not parsed yet, nothing to render
  if document.invalid:
    let stack = document.documentElement.buildTree(bc.rootBox,
      bc.config.markLinks)
    bc.rootBox = BlockBox(stack.box)
    bc.rootBox.layout(addr bc.attrs)
    bc.lines.render(bc.bgcolor, stack, addr bc.attrs, bc.images)
    document.invalid = false
    if bc.hasTask(bcOnReshape):
      bc.resolveTask(bcOnReshape)
    else:
      bc.onReshapeImmediately = true

proc processData0(bc: BufferContext; data: UnsafeSlice): bool =
  if bc.ishtml:
    if bc.htmlParser.parseBuffer(data.toOpenArray()) == PRES_STOP:
      bc.charsetStack = @[bc.htmlParser.builder.charset]
      return false
  else:
    var plaintext = bc.document.findFirst(TAG_PLAINTEXT)
    if plaintext == nil:
      const s = "<plaintext>"
      doAssert bc.htmlParser.parseBuffer(s) != PRES_STOP
      plaintext = bc.document.findFirst(TAG_PLAINTEXT)
    if data.len > 0:
      let lastChild = plaintext.lastChild
      if lastChild != nil and lastChild of Text:
        Text(lastChild).data.s &= data
      else:
        plaintext.insert(bc.document.newText($data), nil)
      #TODO just invalidate document?
      plaintext.invalidate()
  true

proc canSwitch(bc: BufferContext): bool {.inline.} =
  return bc.htmlParser.builder.confidence == ccTentative and
    bc.charsetStack.len > 0

const BufferSize = 16384

proc initDecoder(bc: BufferContext) =
  bc.ctx = initTextDecoderContext(bc.charset, demFatal, BufferSize)

proc switchCharset(bc: BufferContext) =
  bc.charset = bc.charsetStack.pop()
  bc.initDecoder()
  bc.htmlParser.restart(bc.charset)
  bc.document.applyUASheet()
  bc.document.applyUserSheet(bc.config.userStyle)
  bc.document.invalid = true

proc bomSniff(bc: BufferContext; iq: openArray[uint8]): int =
  if iq[0] == 0xFE and iq[1] == 0xFF:
    bc.charsetStack = @[CHARSET_UTF_16_BE]
    bc.switchCharset()
    return 2
  if iq[0] == 0xFF and iq[1] == 0xFE:
    bc.charsetStack = @[CHARSET_UTF_16_LE]
    bc.switchCharset()
    return 2
  if iq[0] == 0xEF and iq[1] == 0xBB and iq[2] == 0xBF:
    bc.charsetStack = @[CHARSET_UTF_8]
    bc.switchCharset()
    return 3
  return 0

proc processData(bc: BufferContext; iq: openArray[uint8]): bool =
  var si = 0
  if bc.needsBOMSniff:
    if iq.len >= 3: # ehm... TODO
      si += bc.bomSniff(iq)
    bc.needsBOMSniff = false
  if not bc.canSwitch():
    bc.ctx.errorMode = demReplacement
  for chunk in bc.ctx.decode(iq.toOpenArray(si, iq.high), finish = false):
    if not bc.processData0(chunk):
      bc.switchCharset()
      return false
  if bc.ctx.failed:
    bc.switchCharset()
    return false
  true

type UpdateHoverResult* = seq[tuple[t: HoverType, s: string]]

const HoverFun = [
  htTitle: getTitleAttr,
  htLink: getClickHover,
  htImage: getImageHover,
  htCachedImage: getCachedImageHover
]
proc updateHover*(bc: BufferContext; cursorx, cursory: int): UpdateHoverResult
    {.proxy.} =
  if cursory >= bc.lines.len:
    return UpdateHoverResult.default
  let thisNode = bc.getCursorElement(cursorx, cursory)
  var hover = newSeq[tuple[t: HoverType, s: string]]()
  var repaint = false
  if thisNode != bc.prevHover:
    var oldHover = newSeq[Element]()
    for element in bc.prevHover.branchElems:
      if element.hover:
        oldHover.add(element)
    for ht in HoverType:
      let s = HoverFun[ht](bc, thisNode)
      if bc.hoverText[ht] != s:
        hover.add((ht, s))
        bc.hoverText[ht] = s
    for element in thisNode.branchElems:
      if not element.hover:
        element.setHover(true)
        repaint = true
      elif (let i = oldHover.find(element); i != -1):
        # branches converged
        oldHover.setLen(i)
        break
    for element in oldHover:
      element.setHover(false)
      repaint = true
  if repaint:
    bc.maybeReshape()
  bc.prevHover = thisNode
  move(hover)

proc loadResources(bc: BufferContext): EmptyPromise =
  if bc.window.pendingResources.len > 0:
    let pendingResources = move(bc.window.pendingResources)
    bc.window.pendingResources = @[]
    return pendingResources.all().then(proc(): EmptyPromise =
      return bc.loadResources()
    )
  return newResolvedPromise()

proc loadImages(bc: BufferContext): EmptyPromise =
  if bc.window.pendingImages.len > 0:
    let pendingImages = move(bc.window.pendingImages)
    bc.window.pendingImages = @[]
    return pendingImages.all().then(proc(): EmptyPromise =
      return bc.loadImages()
    )
  return newResolvedPromise()

proc rewind(bc: BufferContext; data: InputData; offset: int;
    unregister = true): bool =
  let url = parseURL0("cache:" & $bc.cacheId & "?" & $offset)
  let response = bc.loader.doRequest(newRequest(url))
  if response.body == nil:
    return false
  bc.loader.resume(response.outputId)
  if unregister:
    bc.pollData.unregister(data.stream.fd)
    bc.loader.unregistered.add(data.stream.fd)
  bc.loader.unset(data)
  data.stream.sclose()
  bc.loader.put(InputData(stream: response.body))
  response.body.setBlocking(false)
  bc.pollData.register(response.body.fd, POLLIN)
  bc.bytesRead = offset
  return true

# Create an exact clone of the current buffer.
# This clone will share the loader process with the previous buffer.
proc clone*(bc: BufferContext; newurl: URL): int {.proxy.} =
  var pstream: SocketStream
  var pins, pouts: PosixStream
  bc.pstream.withPacketReader r:
    pstream = newSocketStream(r.recvFd())
    pins = newPosixStream(r.recvFd())
    pouts = newPosixStream(r.recvFd())
  do: # EOF, pager died
    return -1
  # suspend outputs before tee'ing
  var ids = newSeq[int]()
  for it in bc.loader.ongoing:
    if it.response.onRead != nil:
      ids.add(it.response.outputId)
  bc.loader.suspend(ids)
  # ongoing transfers are now suspended; exhaust all data in the
  # internal buffer
  # just to be safe.
  for it in bc.loader.ongoing:
    if it.response.onRead != nil:
      bc.loader.onRead(it.fd)
  var pid = fork()
  if pid == -1:
    bc.window.console.error("Failed to clone bc.")
    return -1
  if pid == 0: # child
    pins.sclose()
    bc.pollData.clear()
    var connecting = newSeq[ConnectData]()
    var ongoing = newSeq[OngoingData]()
    var istream: InputData = nil
    for it in bc.loader.data:
      if it of ConnectData:
        connecting.add(ConnectData(it))
      elif it of OngoingData:
        let it = OngoingData(it)
        ongoing.add(it)
        it.response.body.sclose()
      else:
        istream = InputData(it)
      bc.loader.unregistered.add(it.fd)
      bc.loader.unset(it)
    let myPid = getCurrentProcessId()
    for it in ongoing:
      let response = it.response
      # tee ongoing streams
      let (stream, outputId) = bc.loader.tee(response.outputId, myPid)
      # if -1, well, this side hasn't exhausted the socket's buffer
      doAssert outputId != -1 and stream != nil
      response.outputId = outputId
      response.body = stream
      let data = OngoingData(response: response, stream: stream)
      bc.pollData.register(data.fd, POLLIN)
      bc.loader.put(data)
    if istream != nil:
      # We do not own our input stream, so we can't tee it.
      # Luckily it is cached, so what we *can* do is to load the same thing from
      # the cache. (This also lets us skip suspend/resume in this case.)
      # We ignore errors; not much we can do with them here :/
      discard bc.rewind(istream, bc.bytesRead, unregister = false)
    bc.pstream.sclose()
    pouts.write(char(0))
    pouts.sclose()
    for it in bc.tasks.mitems:
      it = 0
    bc.pstream = pstream
    bc.loader.clientPid = myPid
    # get key for new buffer
    bc.loader.controlStream.sclose()
    bc.pstream.withPacketReader r:
      bc.loader.controlStream = newSocketStream(r.recvFd())
    do: # EOF, pager died
      quit(1)
    bc.pollData.register(bc.pstream.fd, POLLIN)
    # must reconnect after the new client is set up, or the client pids get
    # mixed up.
    for it in connecting:
      # connecting: just reconnect
      bc.loader.reconnect(it)
    # Set target now, because it's convenient.
    # (It is also possible that newurl has no hash, and then gotoAnchor
    # isn't called at all.)
    let target = bc.document.findAnchor(newurl.hash)
    bc.document.setTarget(target)
    return 0
  else: # parent
    pouts.sclose()
    pstream.sclose()
    # We must wait for child to tee its ongoing streams.
    var c: char
    if pins.readData(addr c, 1) == 1:
      assert c == char(0)
    else:
      pid = -1
    pins.sclose()
    bc.loader.resume(ids)
    return pid

proc dispatchDOMContentLoadedEvent(bc: BufferContext) =
  let window = bc.window
  window.fireEvent(satDOMContentLoaded, bc.document, bubbles = false,
    cancelable = false, trusted = true)
  bc.maybeReshape()

proc dispatchLoadEvent(bc: BufferContext) =
  let window = bc.window
  let event = newEvent(satLoad.toAtom(), window.document, bubbles = false,
    cancelable = false)
  event.isTrusted = true
  discard window.jsctx.dispatch(window, event, targetOverride = true)
  bc.maybeReshape()

proc finishLoad(bc: BufferContext; data: InputData): EmptyPromise =
  if bc.ctx.td != nil and bc.ctx.td.finish() == tdfrError:
    var s = "\uFFFD"
    doAssert bc.processData0(UnsafeSlice(
      p: cast[ptr UncheckedArray[char]](addr s[0]),
      len: s.len
    ))
  bc.htmlParser.finish()
  bc.document.readyState = rsInteractive
  if bc.config.scripting != smFalse:
    bc.dispatchDOMContentLoadedEvent()
  bc.pollData.unregister(data.stream.fd)
  bc.loader.unregistered.add(data.stream.fd)
  bc.loader.removeCachedItem(bc.cacheId)
  bc.cacheId = -1
  bc.outputId = -1
  bc.loader.unset(data)
  data.stream.sclose()
  return bc.loadResources()

proc headlessMustWait(bc: BufferContext): bool =
  return bc.config.scripting != smFalse and
    not bc.window.timeouts.empty or
    bc.loader.hasFds()

# Returns:
# * -1 if loading is done
# * a positive number for reporting the number of bytes loaded and that the page
#   has been partially rendered.
proc load*(bc: BufferContext): int {.proxy: pfTask.} =
  if bc.state == bsLoaded:
    if bc.config.headless == hmTrue and bc.headlessMustWait():
      bc.headlessLoading = true
      return -999 # unused
    else:
      return -2
  elif bc.state == bsLoadingImages:
    bc.state = bsLoadingImagesAck
    return -1
  elif bc.bytesRead > bc.reportedBytesRead:
    bc.maybeReshape()
    bc.reportedBytesRead = bc.bytesRead
    return bc.bytesRead
  else:
    # will be resolved in onload
    bc.savetask = true
    return -999 # unused

proc onload(bc: BufferContext; data: InputData) =
  if bc.state != bsLoadingPage:
    # We've been called from onError, but we've already seen EOF here.
    # Nothing to do.
    return
  var reprocess = false
  var iq {.noinit.}: array[BufferSize, uint8]
  var n = 0
  while true:
    if not reprocess:
      n = data.stream.readData(iq)
      if n < 0:
        break
      bc.bytesRead += n
    if n != 0:
      if not bc.processData(iq.toOpenArray(0, n - 1)):
        if not bc.firstBufferRead:
          reprocess = true
          continue
        if bc.rewind(data, 0):
          continue
      bc.firstBufferRead = true
      reprocess = false
    else: # EOF
      bc.state = bsLoadingResources
      bc.finishLoad(data).then(proc() =
        # CSS loaded
        if bc.window.pendingImages.len > 0:
          bc.maybeReshape()
          bc.state = bsLoadingImages
          if bc.hasTask(bcLoad):
            bc.resolveTask(bcLoad, -1)
            bc.state = bsLoadingImagesAck
        bc.loadImages().then(proc() =
          # images loaded
          bc.maybeReshape()
          bc.state = bsLoaded
          bc.document.readyState = rsComplete
          if bc.config.scripting != smFalse:
            bc.dispatchLoadEvent()
            for ctx in bc.window.pendingCanvasCtls:
              ctx.ps.sclose()
              ctx.ps = nil
            bc.window.pendingCanvasCtls.setLen(0)
          if bc.hasTask(bcGetTitle):
            bc.resolveTask(bcGetTitle, bc.document.title)
          if bc.hasTask(bcLoad):
            if bc.config.headless == hmTrue and bc.headlessMustWait():
              bc.headlessLoading = true
            else:
              bc.resolveTask(bcLoad, -2)
        )
      )
      return # skip incr render
  # incremental rendering: only if we cannot read the entire stream in one
  # pass
  if bc.config.headless == hmFalse and bc.tasks[bcLoad] != 0:
    # only makes sense when not in dump mode (and the user has requested a load)
    bc.maybeReshape()
    bc.reportedBytesRead = bc.bytesRead
    if bc.hasTask(bcGetTitle):
      bc.resolveTask(bcGetTitle, bc.document.title)
    if bc.hasTask(bcLoad):
      bc.resolveTask(bcLoad, bc.bytesRead)

proc getTitle*(bc: BufferContext): string {.proxy: pfTask.} =
  if bc.document != nil:
    let title = bc.document.findFirst(TAG_TITLE)
    if title != nil:
      return title.childTextContent.stripAndCollapse()
    if bc.state == bsLoaded:
      return "" # title no longer expected
  bc.savetask = true
  return ""

proc forceReshape0(bc: BufferContext) =
  if bc.document != nil:
    bc.document.invalid = true
  bc.maybeReshape()

proc forceReshape*(bc: BufferContext) {.proxy.} =
  if bc.document != nil and bc.document.documentElement != nil:
    bc.document.documentElement.invalidate()
  bc.forceReshape0()

proc windowChange*(bc: BufferContext; attrs: WindowAttributes) {.proxy.} =
  bc.attrs = attrs
  bc.forceReshape()

proc cancel*(bc: BufferContext) {.proxy.} =
  if bc.state == bsLoaded:
    return
  for it in bc.loader.data:
    let fd = it.fd
    bc.pollData.unregister(fd)
    bc.loader.unregistered.add(fd)
    it.stream.sclose()
    bc.loader.unset(it)
    if it of InputData:
      bc.loader.removeCachedItem(bc.cacheId)
      bc.cacheId = -1
      bc.outputId = -1
      bc.htmlParser.finish()
  bc.document.readyState = rsInteractive
  bc.state = bsLoaded
  bc.maybeReshape()

proc serializeMultipart(entries: seq[FormDataEntry]; urandom: PosixStream):
    FormData =
  let formData = newFormData0(entries, urandom)
  for entry in formData.entries.mitems:
    entry.name = makeCRLF(entry.name)
  return formData

proc serializePlainTextFormData(kvs: seq[(string, string)]): string =
  result = ""
  for (name, value) in kvs:
    result &= name
    result &= '='
    result &= value
    result &= "\r\n"

proc getOutputEncoding(charset: Charset): Charset =
  if charset in {CHARSET_REPLACEMENT, CHARSET_UTF_16_BE, CHARSET_UTF_16_LE}:
    return CHARSET_UTF_8
  return charset

proc pickCharset(form: HTMLFormElement): Charset =
  if form.attrb(satAcceptCharset):
    let input = form.attr(satAcceptCharset)
    for label in input.split(AsciiWhitespace):
      let charset = label.getCharset()
      if charset != CHARSET_UNKNOWN:
        return charset.getOutputEncoding()
    return CHARSET_UTF_8
  return form.document.charset.getOutputEncoding()

proc makeFormRequest(bc: BufferContext; parsedAction: URL;
    httpMethod: HttpMethod; entryList: seq[FormDataEntry];
    enctype: FormEncodingType): Request =
  assert httpMethod in {hmGet, hmPost}
  case parsedAction.schemeType
  of stFtp:
    return newRequest(parsedAction) # get action URL
  of stData:
    if httpMethod == hmGet:
      # mutate action URL
      let kvlist = entryList.toNameValuePairs()
      #TODO with charset
      parsedAction.setSearch('?' & serializeFormURLEncoded(kvlist))
      return newRequest(parsedAction, httpMethod)
    return newRequest(parsedAction) # get action URL
  of stMailto:
    if httpMethod == hmGet:
      # mailWithHeaders
      let kvlist = entryList.toNameValuePairs()
      #TODO with charset
      parsedAction.setSearch('?' & serializeFormURLEncoded(kvlist,
        spaceAsPlus = false))
      return newRequest(parsedAction, httpMethod)
    # mail as body
    let kvlist = entryList.toNameValuePairs()
    let body = if enctype == fetTextPlain:
      percentEncode(serializePlainTextFormData(kvlist), PathPercentEncodeSet)
    else:
      #TODO with charset
      serializeFormURLEncoded(kvlist)
    if parsedAction.search == "":
      parsedAction.search = "?"
    if parsedAction.search != "?":
      parsedAction.search &= '&'
    parsedAction.search &= "body=" & body
    return newRequest(parsedAction, httpMethod)
  else:
    if httpMethod == hmGet:
      # mutate action URL
      let kvlist = entryList.toNameValuePairs()
      #TODO with charset
      let search = '?' & serializeFormURLEncoded(kvlist)
      parsedAction.setSearch(search)
      return newRequest(parsedAction, httpMethod)
    # submit as entity body
    let body = case enctype
    of fetUrlencoded:
      #TODO with charset
      let kvlist = entryList.toNameValuePairs()
      RequestBody(t: rbtString, s: serializeFormURLEncoded(kvlist))
    of fetMultipart:
      #TODO with charset
      let multipart = serializeMultipart(entryList,
        bc.window.crypto.urandom)
      RequestBody(t: rbtMultipart, multipart: multipart)
    of fetTextPlain:
      #TODO with charset
      let kvlist = entryList.toNameValuePairs()
      RequestBody(t: rbtString, s: serializePlainTextFormData(kvlist))
    let headers = newHeaders(hgRequest, {"Content-Type": $enctype})
    return newRequest(parsedAction, httpMethod, headers, body)

# https://html.spec.whatwg.org/multipage/form-control-infrastructure.html#form-submission-algorithm
proc submitForm(bc: BufferContext; form: HTMLFormElement;
    submitter: HTMLElement; jsSubmitCall = false): Request =
  if form.constructingEntryList:
    return nil
  if not jsSubmitCall:
    if form.firing:
      return nil
    form.firing = true
    #TODO user validity/validity constraints
    let jsSubmitter = EventTarget(if submitter != form: submitter else: nil)
    let event = newSubmitEvent(satSubmit.toAtom(), SubmitEventInit(
      submitter: EventTargetHTMLElement(jsSubmitter),
      bubbles: true,
      cancelable: true
    ))
    event.isTrusted = true
    let canceled = bc.window.jsctx.dispatch(form, event)
    form.firing = false
    if canceled:
      return nil
  let charset = form.pickCharset()
  discard charset #TODO pass to constructEntryList
  let entryList = form.constructEntryList(submitter)
  let subAction = submitter.action()
  let action = if subAction != "":
    subAction
  else:
    $form.document.url
  #TODO encoding-parse
  let parsedAction = submitter.document.parseURL0(action)
  if parsedAction == nil:
    return nil
  let enctype = submitter.enctype()
  let formMethod = submitter.formmethod()
  let httpMethod = case formMethod
  of fmDialog: return nil #TODO
  of fmGet: hmGet
  of fmPost: hmPost
  #let target = if submitter.isSubmitButton() and submitter.attrb("formtarget"):
  #  submitter.attr("formtarget")
  #else:
  #  submitter.target()
  #let noopener = true #TODO
  return bc.makeFormRequest(parsedAction, httpMethod, entryList, enctype)

proc setFocus(bc: BufferContext; e: Element) =
  bc.document.setFocus(e)
  bc.maybeReshape()

proc restoreFocus(bc: BufferContext) =
  bc.document.setFocus(nil)
  bc.maybeReshape()

proc implicitSubmit(bc: BufferContext; input: HTMLInputElement): Request =
  let form = input.form
  if form != nil and form.canSubmitImplicitly():
    return bc.submitForm(form, form)
  return nil

proc readSuccess*(bc: BufferContext; s: string; hasFd: bool): Request
    {.proxy.} =
  var fd: cint = -1
  if hasFd:
    bc.pstream.withPacketReader r:
      fd = r.recvFd()
    do: # EOF, pager died
      return nil
  if bc.document.focus != nil:
    let focus = bc.document.focus
    bc.restoreFocus()
    case focus.tagType
    of TAG_INPUT:
      let input = HTMLInputElement(focus)
      case input.inputType
      of itFile:
        input.files = @[newWebFile(s, fd)]
        input.invalidate()
      else:
        input.setValue(s)
      if bc.config.scripting != smFalse:
        let window = bc.window
        if input.inputType == itFile:
          window.fireEvent(satInput, input, bubbles = true, cancelable = true,
            trusted = true)
        else:
          let inputEvent = newInputEvent(satInput.toAtom(),
            InputEventInit(
              data: some(s),
              inputType: "insertText",
              bubbles: true,
              cancelable: true
            )
          )
          inputEvent.isTrusted = true
          window.fireEvent(inputEvent, input)
        bc.window.fireEvent(satChange, input, bubbles = true,
          cancelable = true, trusted = true)
      bc.maybeReshape()
      return bc.implicitSubmit(input)
    of TAG_TEXTAREA:
      let textarea = HTMLTextAreaElement(focus)
      textarea.value = s
      textarea.invalidate()
      if bc.config.scripting != smFalse:
        bc.window.fireEvent(satChange, textarea, bubbles = true,
          cancelable = true, trusted = true)
      bc.maybeReshape()
    else: discard
  return nil

proc click(bc: BufferContext; label: HTMLLabelElement): ClickResult =
  let control = label.control
  if control != nil:
    return bc.click(control)
  return ClickResult()

proc click(bc: BufferContext; select: HTMLSelectElement): ClickResult =
  if select.attrb(satMultiple):
    return ClickResult()
  bc.setFocus(select)
  var options: seq[SelectOption] = @[]
  var selected = -1
  var i = 0
  for option in select.options:
    #TODO: add nop options for each optgroup
    options.add(SelectOption(s: option.textContent.stripAndCollapse()))
    if selected == -1 and option.selected:
      selected = i
    inc i
  return ClickResult(
    select: some(SelectResult(options: move(options), selected: selected))
  )

proc baseURL(bc: BufferContext): URL =
  return bc.document.baseURL

proc evalJSURL(bc: BufferContext; url: URL): Opt[string] =
  let surl = $url
  let source = surl.toOpenArray("javascript:".len, surl.high).percentDecode()
  let ctx = bc.window.jsctx
  let ret = ctx.eval(source, '<' & $bc.baseURL & '>', JS_EVAL_TYPE_GLOBAL)
  if JS_IsException(ret):
    bc.window.console.writeException(ctx)
    return err() # error
  if JS_IsUndefined(ret):
    return err() # no need to navigate
  var res: string
  ?ctx.fromJS(ret, res)
  JS_FreeValue(ctx, ret)
  # Navigate to result.
  return ok(res)

proc click(bc: BufferContext; anchor: HTMLAnchorElement): ClickResult =
  bc.restoreFocus()
  if url := anchor.reinitURL():
    if url.schemeType == stJavascript:
      if bc.config.scripting == smFalse:
        return ClickResult()
      let s = bc.evalJSURL(url)
      bc.maybeReshape()
      if s.isErr:
        return ClickResult()
      let urls = parseURL0("data:text/html," & s.get)
      if urls == nil:
        return ClickResult()
      url = urls
    return ClickResult(open: newRequest(url, hmGet))
  return ClickResult()

proc click(bc: BufferContext; option: HTMLOptionElement): ClickResult =
  let select = option.select
  if select != nil:
    if select.attrb(satMultiple):
      option.setSelected(not option.selected)
      if bc.config.scripting != smFalse:
        bc.window.fireEvent(satChange, select, bubbles = true,
          cancelable = true, trusted = true)
      bc.maybeReshape()
      return ClickResult()
    return bc.click(select)
  return ClickResult()

proc click(bc: BufferContext; button: HTMLButtonElement): ClickResult =
  if button.form != nil:
    case button.ctype
    of btSubmit:
      let open = bc.submitForm(button.form, button)
      bc.setFocus(button)
      return ClickResult(open: open)
    of btReset:
      button.form.reset()
    of btButton: discard
    bc.setFocus(button)
  return ClickResult()

proc click(bc: BufferContext; textarea: HTMLTextAreaElement): ClickResult =
  bc.setFocus(textarea)
  let readline = ReadLineResult(
    t: rltArea,
    value: textarea.value
  )
  return ClickResult(readline: some(readline))

proc click(bc: BufferContext; audio: HTMLAudioElement): ClickResult =
  bc.restoreFocus()
  let (src, contentType) = audio.getSrc()
  if src != "":
    if url := audio.document.parseURL(src):
      return ClickResult(open: newRequest(url), contentType: contentType)
  return ClickResult()

proc click(bc: BufferContext; video: HTMLVideoElement): ClickResult =
  bc.restoreFocus()
  let (src, contentType) = video.getSrc()
  if src != "":
    if url := video.document.parseURL(src):
      return ClickResult(open: newRequest(url), contentType: contentType)
  return ClickResult()

# Used for frame, ifframe
proc clickFrame(bc: BufferContext; frame: Element): ClickResult =
  bc.restoreFocus()
  let src = frame.attr(satSrc)
  if src != "":
    if url := frame.document.parseURL(src):
      return ClickResult(open: newRequest(url))
  return ClickResult()

const InputTypePrompt = [
  itText: "TEXT",
  itButton: "",
  itCheckbox: "",
  itColor: "Color",
  itDate: "Date",
  itDatetimeLocal: "Local date/time",
  itEmail: "E-Mail",
  itFile: "",
  itHidden: "",
  itImage: "Image",
  itMonth: "Month",
  itNumber: "Number",
  itPassword: "Password",
  itRadio: "Radio",
  itRange: "Range",
  itReset: "",
  itSearch: "Search",
  itSubmit: "",
  itTel: "Telephone number",
  itTime: "Time",
  itURL: "URL input",
  itWeek: "Week"
]

proc click(bc: BufferContext; input: HTMLInputElement): ClickResult =
  bc.restoreFocus()
  case input.inputType
  of itFile:
    #TODO we should somehow extract the path name from the current file
    bc.setFocus(input)
    return ClickResult(readline: some(ReadLineResult(t: rltFile)))
  of itCheckbox:
    input.setChecked(not input.checked)
    if bc.config.scripting != smFalse:
      # Note: not an InputEvent.
      bc.window.fireEvent(satInput, input, bubbles = true,
        cancelable = true, trusted = true)
      bc.window.fireEvent(satChange, input, bubbles = true,
        cancelable = true, trusted = true)
    bc.maybeReshape()
    return ClickResult()
  of itRadio:
    let wasChecked = input.checked
    input.setChecked(true)
    if not wasChecked and bc.config.scripting != smFalse:
      # See above.
      bc.window.fireEvent(satInput, input, bubbles = true,
        cancelable = true, trusted = true)
      bc.window.fireEvent(satChange, input, bubbles = true,
        cancelable = true, trusted = true)
    bc.maybeReshape()
    return ClickResult()
  of itReset:
    if input.form != nil:
      input.form.reset()
      bc.maybeReshape()
    return ClickResult()
  of itSubmit, itButton:
    if input.form != nil:
      return ClickResult(open: bc.submitForm(input.form, input))
    return ClickResult()
  else:
    # default is text.
    var prompt = InputTypePrompt[input.inputType]
    if input.inputType == itRange:
      prompt &= " (" & input.attr(satMin) & ".." & input.attr(satMax) & ")"
    bc.setFocus(input)
    return ClickResult(
      readline: some(ReadLineResult(
        prompt: prompt & ": ",
        value: input.value,
        hide: input.inputType == itPassword
      ))
    )

proc click(bc: BufferContext; clickable: Element): ClickResult =
  case clickable.tagType
  of TAG_LABEL:
    return bc.click(HTMLLabelElement(clickable))
  of TAG_SELECT:
    return bc.click(HTMLSelectElement(clickable))
  of TAG_A:
    return bc.click(HTMLAnchorElement(clickable))
  of TAG_OPTION:
    return bc.click(HTMLOptionElement(clickable))
  of TAG_BUTTON:
    return bc.click(HTMLButtonElement(clickable))
  of TAG_TEXTAREA:
    return bc.click(HTMLTextAreaElement(clickable))
  of TAG_INPUT:
    return bc.click(HTMLInputElement(clickable))
  of TAG_AUDIO:
    return bc.click(HTMLAudioElement(clickable))
  of TAG_VIDEO:
    return bc.click(HTMLVideoElement(clickable))
  of TAG_IFRAME, TAG_FRAME:
    return bc.clickFrame(clickable)
  else:
    bc.restoreFocus()
    return ClickResult()

proc click*(bc: BufferContext; cursorx, cursory: int): ClickResult {.proxy.} =
  if bc.lines.len <= cursory: return ClickResult()
  var canceled = false
  let clickable = bc.getCursorClickable(cursorx, cursory)
  if bc.config.scripting != smFalse:
    let element = bc.getCursorElement(cursorx, cursory)
    if element != nil:
      bc.clickResult = nil
      let window = bc.window
      let event = newEvent(satClick.toAtom(), element, bubbles = true,
        cancelable = true)
      event.isTrusted = true
      canceled = window.jsctx.dispatch(element, event)
      bc.maybeReshape()
      if bc.clickResult != nil:
        return bc.clickResult
  let url = bc.navigateUrl
  bc.navigateUrl = nil
  if not canceled and clickable != nil:
    return bc.click(clickable)
  if url != nil:
    return ClickResult(open: newRequest(url, hmGet))
  return ClickResult()

proc select*(bc: BufferContext; selected: int): ClickResult {.proxy.} =
  if bc.document.focus != nil and
      bc.document.focus of HTMLSelectElement:
    if selected != -1:
      let select = HTMLSelectElement(bc.document.focus)
      let index = select.selectedIndex
      if index != selected:
        select.setSelectedIndex(selected)
        if bc.config.scripting != smFalse:
          bc.window.fireEvent(satChange, select, bubbles = true,
            cancelable = true, trusted = true)
    bc.restoreFocus()
    bc.maybeReshape()
  return ClickResult()

proc readCanceled*(bc: BufferContext) {.proxy.} =
  bc.restoreFocus()

type GetLinesResult* = object
  numLines*: int
  lines*: seq[SimpleFlexibleLine]
  bgcolor*: CellColor
  images*: seq[PosBitmap]

proc getLines*(bc: BufferContext; w: Slice[int]): GetLinesResult {.proxy.} =
  result = GetLinesResult(numLines: bc.lines.len, bgcolor: bc.bgcolor)
  var w = w
  if w.b < 0 or w.b > bc.lines.high:
    w.b = bc.lines.high
  #TODO this is horribly inefficient
  for y in w:
    var line = SimpleFlexibleLine(str: bc.lines[y].str)
    for f in bc.lines[y].formats:
      line.formats.add(SimpleFormatCell(format: f.format, pos: f.pos))
    result.lines.add(line)
  if bc.config.images:
    let ppl = bc.attrs.ppl
    for image in bc.images:
      let ey = image.y + (image.height + ppl - 1) div ppl # ceil
      if image.y <= w.b and ey >= w.a:
        result.images.add(image)

proc getLinks*(bc: BufferContext): seq[string] {.proxy.} =
  result = newSeq[string]()
  if bc.document != nil:
    for element in bc.window.displayedElements(TAG_A):
      if element.attrb(satHref):
        if url := HTMLAnchorElement(element).reinitURL():
          result.add($url)
        else:
          result.add(element.attr(satHref))

proc onReshape*(bc: BufferContext) {.proxy: pfTask.} =
  if bc.onReshapeImmediately:
    # We got a reshape before the container even asked us for the event.
    # This variable prevents the race that would otherwise occur if
    # the buffer were to be reshaped between two onReshape requests.
    bc.onReshapeImmediately = false
    return
  assert bc.tasks[bcOnReshape] == 0
  bc.savetask = true

proc markURL*(bc: BufferContext; schemes: seq[string]) {.proxy.} =
  if bc.document == nil or bc.document.body == nil:
    return
  var buf = "("
  for i, scheme in schemes:
    if i > 0:
      buf &= '|'
    buf &= scheme
  buf &= r"):(//[\w%:.-]+)?[\w/@%:.~-]*\??[\w%:~.=&]*#?[\w:~.=-]*[\w/~=-]"
  let regex = compileRegex(buf, {LRE_FLAG_GLOBAL}).get
  # Dummy element for the fragment parsing algorithm. We can't just use parent
  # there, because e.g. plaintext would not parse the text correctly.
  let html = bc.document.newHTMLElement(TAG_DIV)
  var stack = @[bc.document.body]
  while stack.len > 0:
    let element = stack.pop()
    var toRemove = newSeq[Node]()
    var texts = newSeq[Text]()
    var stackNext = newSeq[HTMLElement]()
    var lastText: Text = nil
    for node in element.childList:
      if node of Text:
        let text = Text(node)
        if lastText != nil:
          lastText.data &= text.data
          toRemove.add(text)
        else:
          texts.add(text)
          lastText = text
      elif node of HTMLElement:
        let element = HTMLElement(node)
        if element.tagType in {TAG_NOBR, TAG_WBR}:
          toRemove.add(node)
        elif element.tagType notin {TAG_HEAD, TAG_SCRIPT, TAG_STYLE, TAG_A}:
          stackNext.add(element)
          lastText = nil
        else:
          lastText = nil
      else:
        lastText = nil
    for it in toRemove:
      it.remove()
    for text in texts:
      var res = regex.exec(text.data)
      if res.success:
        var offset = 0
        var data = ""
        var j = 0
        for cap in res.captures.mitems:
          let capLen = cap[0].e - cap[0].s
          while j < cap[0].s:
            case (let c = text.data[j]; c)
            of '<':
              data &= "&lt;"
              offset += 3
            of '>':
              data &= "&gt;"
              offset += 3
            of '\'':
              data &= "&apos;"
              offset += 5
            of '"':
              data &= "&quot;"
              offset += 5
            of '&':
              data &= "&amp;"
              offset += 4
            else:
              data &= c
            inc j
          cap[0].s += offset
          cap[0].e += offset
          let s = text.data[j ..< j + capLen]
          let news = "<a href=\"" & s & "\">" & s.htmlEscape() & "</a>"
          data &= news
          j += cap[0].e - cap[0].s
          offset += news.len - (cap[0].e - cap[0].s)
        while j < text.data.len:
          case (let c = text.data[j]; c)
          of '<': data &= "&lt;"
          of '>': data &= "&gt;"
          of '\'': data &= "&apos;"
          of '"': data &= "&quot;"
          of '&': data &= "&amp;"
          else: data &= c
          inc j
        let replacement = html.fragmentParsingAlgorithm(data)
        discard element.replace(text, replacement)
    stack.add(stackNext)
  bc.forceReshape0()

proc toggleImages*(bc: BufferContext): bool {.proxy: pfTask.} =
  bc.config.images = not bc.config.images
  bc.window.settings.images = bc.config.images
  bc.window.svgCache.clear()
  for element in bc.document.descendants:
    if element of HTMLImageElement:
      bc.window.loadResource(HTMLImageElement(element))
    elif element of SVGSVGElement:
      bc.window.loadResource(SVGSVGElement(element))
  bc.savetask = true
  bc.loadImages().then(proc() =
    if bc.tasks[bcToggleImages] == 0:
      # we resolved in then
      bc.savetask = false
    else:
      bc.resolveTask(bcToggleImages, bc.config.images)
    bc.forceReshape()
  )
  return bc.config.images

# Note: these functions are automatically generated by the .proxy macro.
const ProxyMap = [
  bcCancel: cancelCmd,
  bcCheckRefresh: checkRefreshCmd,
  bcClick: clickCmd,
  bcClone: cloneCmd,
  bcFindNextLink: findNextLinkCmd,
  bcFindNextMatch: findNextMatchCmd,
  bcFindNextParagraph: findNextParagraphCmd,
  bcFindNthLink: findNthLinkCmd,
  bcFindPrevLink: findPrevLinkCmd,
  bcFindPrevMatch: findPrevMatchCmd,
  bcFindPrevParagraph: findPrevParagraphCmd,
  bcFindRevNthLink: findRevNthLinkCmd,
  bcForceReshape: forceReshapeCmd,
  bcGetLines: getLinesCmd,
  bcGetLinks: getLinksCmd,
  bcGetTitle: getTitleCmd,
  bcGotoAnchor: gotoAnchorCmd,
  bcLoad: loadCmd,
  bcMarkURL: markURLCmd,
  bcOnReshape: onReshapeCmd,
  bcReadCanceled: readCanceledCmd,
  bcReadSuccess: readSuccessCmd,
  bcSelect: selectCmd,
  bcToggleImages: toggleImagesCmd,
  bcUpdateHover: updateHoverCmd,
  bcWindowChange: windowChangeCmd,
]

proc readCommand(bc: BufferContext): bool =
  bc.pstream.withPacketReader r:
    var cmd: BufferCommand
    var packetid: int
    r.sread(cmd)
    r.sread(packetid)
    ProxyMap[cmd](bc, r, packetid)
  do: # EOF, pager died
    return false
  true

proc handleRead(bc: BufferContext; fd: int): bool =
  if fd == bc.pstream.fd:
    return bc.readCommand()
  elif (let data = bc.loader.get(fd); data != nil):
    if data of InputData:
      bc.onload(InputData(data))
    else:
      bc.loader.onRead(fd)
      if bc.config.scripting != smFalse:
        bc.window.runJSJobs()
  elif fd in bc.loader.unregistered:
    discard # ignore
  else:
    assert false
  true

proc handleError(bc: BufferContext; fd: int): bool =
  if fd == bc.pstream.fd:
    # Connection reset by peer, probably.  Close the buffer.
    return false
  elif (let data = bc.loader.get(fd); data != nil):
    if data of InputData:
      bc.onload(InputData(data))
    else:
      if not bc.loader.onError(fd):
        #TODO handle connection error
        assert false, $fd
      if bc.config.scripting != smFalse:
        bc.window.runJSJobs()
  elif fd in bc.loader.unregistered:
    discard # ignore
  else:
    assert false, $fd
  true

proc getPollTimeout(bc: BufferContext): cint =
  if bc.config.scripting != smFalse:
    return bc.window.timeouts.sortAndGetTimeout()
  return -1

proc runBuffer(bc: BufferContext) =
  var alive = true
  while alive:
    if bc.headlessLoading and not bc.headlessMustWait():
      bc.headlessLoading = false
      bc.resolveTask(bcLoad, -1)
    let timeout = bc.getPollTimeout()
    bc.pollData.poll(timeout)
    bc.loader.blockRegister()
    for fd, revents in bc.pollData.events:
      let fd = int(fd)
      if (revents and POLLIN) != 0:
        if not bc.handleRead(fd):
          alive = false
          break
      if (revents and POLLERR) != 0 or (revents and POLLHUP) != 0:
        if not bc.handleError(fd):
          alive = false
          break
    bc.loader.unregistered.setLen(0)
    bc.loader.unblockRegister()
    if bc.config.scripting != smFalse:
      if bc.window.timeouts.run(bc.window.console):
        bc.window.runJSJobs()
        bc.maybeReshape()

proc cleanup(bc: BufferContext) =
  bc.pstream.sclose()
  bc.window.crypto.urandom.sclose()
  if bc.config.scripting != smFalse:
    bc.window.jsctx.free()
    bc.window.jsrt.free()

proc launchBuffer*(config: BufferConfig; url: URL; attrs: WindowAttributes;
    ishtml: bool; charsetStack: seq[Charset]; loader: FileLoader;
    pstream, istream: SocketStream; urandom: PosixStream; cacheId: int;
    contentType: string) =
  let confidence = if config.charsetOverride == CHARSET_UNKNOWN:
    ccTentative
  else:
    ccCertain
  let bc = BufferContext(
    attrs: attrs,
    config: config,
    ishtml: ishtml,
    loader: loader,
    needsBOMSniff: config.charsetOverride == CHARSET_UNKNOWN,
    pstream: pstream,
    charsetStack: charsetStack,
    cacheId: cacheId,
    outputId: -1
  )
  bc.window = newWindow(
    config.scripting,
    config.images,
    config.styling,
    config.autofocus,
    config.colorMode,
    config.headless,
    addr bc.attrs,
    loader,
    url,
    urandom,
    config.imageTypes,
    config.userAgent,
    config.referrer,
    contentType
  )
  if bc.config.scripting != smFalse:
    bc.window.navigate = proc(url: URL) = bc.navigate(url)
    bc.window.click = proc(element: HTMLElement) =
      #TODO not sure if this is the right behavior for app mode.
      # (for normal mode it's the right design, I think.)
      bc.clickResult = bc.click(element)
  bc.charset = bc.charsetStack.pop()
  istream.setBlocking(false)
  bc.loader.put(InputData(stream: istream))
  bc.pollData.register(istream.fd, POLLIN)
  loader.registerFun = proc(fd: int) =
    bc.pollData.register(fd, POLLIN)
  loader.unregisterFun = proc(fd: int) =
    bc.pollData.unregister(fd)
  bc.pollData.register(bc.pstream.fd, POLLIN)
  bc.initDecoder()
  bc.htmlParser = newHTML5ParserWrapper(
    bc.window,
    url,
    confidence,
    bc.charset
  )
  bc.document.applyUASheet()
  bc.document.applyUserSheet(bc.config.userStyle)
  bc.runBuffer()
  bc.cleanup()
  quit(0)

{.pop.} # raises: []
