{.push raises: [].}

import std/macros
import std/options
import std/posix
import std/tables

import chagashi/charset
import chagashi/decoder
import chagashi/decodercore
import chame/htmlparser
import chame/tags
import config/conftypes
import css/box
import css/csstree
import css/cssvalues
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
import monoucha/jsbind
import monoucha/jsutils
import monoucha/libregexp
import monoucha/quickjs
import server/bufferiface
import server/headers
import server/loaderiface
import server/request
import types/blob
import types/cell
import types/color
import types/formdata
import types/jsopt
import types/opt
import types/refstring
import types/url
import types/winattrs
import utils/lrewrap
import utils/luwrap
import utils/strwidth
import utils/twtstr

type
  InputData = ref object of MapData

  PagerHandle = ref object of MapData
    tasks: array[BufferCommand, int]
    reportedLoad: LoadResult
    onReshapeImmediately: bool
    prevHover: Element
    next: PagerHandle

  BufferContext = ref object
    firstBufferRead: bool
    headlessLoading: bool
    ishtml: bool
    needsBOMSniff: bool
    savetask: bool
    checkJobs: bool
    state: BufferState
    charset: Charset
    bgcolor: CellColor
    attrs: WindowAttributes
    bytesRead: uint64
    cacheId: int
    charsetStack: seq[Charset]
    config: BufferConfig
    ctx: TextDecoderContext
    hoverText: array[HoverType, string]
    htmlParser: HTML5ParserWrapper
    images: seq[PosBitmap]
    linkHintChars: ref seq[uint32]
    schemes: seq[string]
    lines: FlexibleGrid
    loader: FileLoader
    navigateUrl: URL # stored when JS tries to navigate
    outputId: int
    pollData: PollData
    clickResult: ClickResult
    rootBox: BlockBox
    window: Window
    luctx: LUContext
    nhints: int
    handlesHead: PagerHandle

  CommandResult = enum
    cmdrDone, cmdrEOF

# Forward declarations
proc click(bc: BufferContext; clickable: Element): ClickResult
proc submitForm(bc: BufferContext; form: HTMLFormElement;
  submitter: HTMLElement; jsSubmitCall = false): Request

iterator handles(bc: BufferContext): PagerHandle =
  var it = bc.handlesHead
  while it != nil:
    yield it
    it = it.next

template document(bc: BufferContext): Document =
  bc.window.document

template withPacketWriterReturnEOF(stream: DynStream; w, body: untyped) =
  stream.withPacketWriter w:
    body
  do:
    return cmdrEOF

# For each proxied command, we create a proxy proc to read packets in
# buffer, call proxied proc, and send back the result (nameCmd).
type ProxyFlag = enum
  pfNone, pfTask

proc buildProxyProc(name, params: NimNode; cmd: BufferCommand; flag: ProxyFlag):
    NimNode =
  let stmts = newStmtList()
  let r = ident("r")
  let packetid = ident("packetid")
  let call = newCall(name, ident("bc"), ident("handle"))
  for i in 3 ..< params.len:
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
      handle.stream.withPacketWriterReturnEOF wt:
        wt.swrite(`packetid`)
  else:
    quote do:
      handle.stream.withPacketWriterReturnEOF wt:
        wt.swrite(`packetid`)
        wt.swrite(retval)
  case flag
  of pfTask:
    stmts.add(quote do:
      if bc.savetask:
        bc.savetask = false
        handle.tasks[BufferCommand(`cmd`)] = `packetid`
      else:
        `resolve`
    )
  of pfNone:
    stmts.add(resolve)
  let name = ident(name.strVal & "Cmd")
  quote do:
    proc `name`(bc {.inject.}: BufferContext; handle {.inject.}: PagerHandle;
        `r`: var PacketReader; `packetid`: int): CommandResult =
      `stmts`
      cmdrDone

macro proxyt(flag: static ProxyFlag; fun: typed) =
  let name = fun.name # sym
  let params = fun.params # formalParams
  let cmd = strictParseEnum[BufferCommand](name.strVal).get
  let pproc = buildProxyProc(name, params, cmd, flag)
  quote do:
    `fun`
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
  if cursory < 0 or cursory >= bc.lines.len:
    return nil
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
proc findPrevLink(bc: BufferContext; handle: PagerHandle;
    cursorx, cursory, n: int): tuple[x, y: int] {.proxy.} =
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

proc findNextLink(bc: BufferContext; handle: PagerHandle;
    cursorx, cursory, n: int): tuple[x, y: int] {.proxy.} =
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

proc findNextParagraph(bc: BufferContext; handle: PagerHandle;
    cursory, n: int): int {.proxy.} =
  var y = cursory
  if n < 0:
    for i in 0 ..< -n:
      while y >= 0 and bc.lines[y].str.onlyWhitespace():
        dec y
      while y >= 0 and not bc.lines[y].str.onlyWhitespace():
        dec y
  else:
    for i in 0 ..< n:
      while y < bc.lines.len and bc.lines[y].str.onlyWhitespace():
        inc y
      while y < bc.lines.len and not bc.lines[y].str.onlyWhitespace():
        inc y
  return y

proc findRevNthLink(bc: BufferContext; handle: PagerHandle; i: int):
    tuple[x, y: int] {.proxy.} =
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

proc findPrevMatch(bc: BufferContext; handle: PagerHandle; regex: Regex;
    x, y, endy: int; wrap: bool; n: int): BufferMatch {.proxy.} =
  if n <= 0 or x < 0 or y < 0 or y >= bc.lines.len:
    return BufferMatch(x: -1, y: -1)
  var n = n
  var y = y
  var b = bc.cursorBytes(y, x)
  var first = true
  while true:
    if y < 0:
      if not wrap:
        break
      y = bc.lines.high
    let s = bc.lines[y].str
    if b < 0:
      b = s.len
    let cap = regex.matchLast(s.toOpenArray(0, b - 1), 0)
    if cap.s >= 0:
      let x = s.width(0, cap.s)
      let w = s.toOpenArray(cap.s, cap.e - 1).width()
      dec n
      if n == 0:
        return BufferMatch(x: x, y: y, w: w)
    if y == endy and not first:
      break
    first = false
    b = -1
    dec y
  BufferMatch(x: -1, y: -1)

proc findNextMatch(bc: BufferContext; handle: PagerHandle; regex: Regex;
    cursorx, cursory, endy: int; wrap: bool; n: int): BufferMatch {.proxy.} =
  if n <= 0 or cursorx < 0 or cursory < 0 or cursory >= bc.lines.len:
    return BufferMatch(x: -1, y: -1)
  var y = cursory
  var n = n
  var b = bc.cursorBytes(y, cursorx + 1)
  var first = true
  while true:
    if y >= bc.lines.len:
      if not wrap:
        break
      y = 0
    let s = bc.lines[y].str
    let cap = regex.matchFirst(s, b)
    if cap.s >= 0:
      let x = s.width(0, cap.s)
      let w = s.toOpenArray(cap.s, cap.e - 1).width()
      dec n
      if n == 0:
        return BufferMatch(x: x, y: y, w: w)
    b = 0
    if y == endy and not first:
      break
    first = false
    inc y
  BufferMatch(x: -1, y: -1)

proc gotoAnchor(bc: BufferContext; handle: PagerHandle; anchor: string;
    autofocus, target: bool): GotoAnchorResult {.proxy.} =
  if bc.document == nil:
    return GotoAnchorResult(x: -1, y: -1)
  if anchor.len > 0 and anchor[0] == 'L' and not bc.ishtml:
    let y = parseIntP(anchor.toOpenArray(1, anchor.high)).get(-1)
    if y > 0:
      return GotoAnchorResult(x: 0, y: y - 1)
  var element = bc.document.findAnchor(anchor)
  if element == nil:
    let s = percentDecode(anchor)
    if s != anchor:
      element = bc.document.findAnchor(s)
  if target and element != nil:
    bc.document.setTarget(element)
  var focus = initClickResult()
  # Do not use bc.config.autofocus when we just want to check if the
  # anchor can be found.
  if autofocus:
    let autofocus = bc.document.findAutoFocus()
    if autofocus != nil:
      if element == nil:
        element = autofocus # jump to autofocus instead
      let res = bc.click(autofocus)
      if res.t in ClickResultReadLine:
        focus = res
  if element == nil or element.box == nil:
    return GotoAnchorResult(x: -1, y: -1)
  let offset = CSSBox(element.box).render.offset
  let x = max(offset.x div bc.attrs.ppc.toLUnit(), 0'lu).toInt
  let y = max(offset.y div bc.attrs.ppl.toLUnit(), 0'lu).toInt
  return GotoAnchorResult(x: x, y: y, focus: focus)

proc checkRefresh(bc: BufferContext; handle: PagerHandle): CheckRefreshResult
    {.proxy.} =
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

proc hasTask(handle: PagerHandle; cmd: BufferCommand): bool =
  return handle.tasks[cmd] != 0

proc resolveTask(handle: PagerHandle; cmd: BufferCommand) =
  let packetid = handle.tasks[cmd]
  assert packetid != 0
  handle.stream.withPacketWriterFire wt:
    wt.swrite(packetid)
  handle.tasks[cmd] = 0

proc resolveTask[T](handle: PagerHandle; cmd: BufferCommand; res: T) =
  let packetid = handle.tasks[cmd]
  assert packetid != 0
  handle.stream.withPacketWriterFire wt:
    wt.swrite(packetid)
    wt.swrite(res)
  handle.tasks[cmd] = 0

proc resolveLoad(bc: BufferContext; handle: PagerHandle; n, len: uint64) =
  let res = (n: n, len: len, bs: bc.state)
  handle.reportedLoad = res
  handle.resolveTask(bcLoad, res)

proc maybeReshape(bc: BufferContext; suppressFouc = false) =
  let document = bc.document
  if document == nil or document.documentElement == nil:
    return # not parsed yet, nothing to render
  if document.invalid:
    let (stack, fixedHead) = document.documentElement.buildTree(bc.rootBox,
      bc.config.markLinks, bc.nhints, bc.linkHintChars)
    bc.rootBox = BlockBox(stack.box)
    bc.rootBox.layout(bc.attrs, fixedHead, bc.luctx)
    bc.lines.render(bc.bgcolor, stack, bc.attrs, bc.images)
    document.invalid = false
    # We don't want a FOUC on automatic reshape, but we still want to allow
    # the user to override this and interact with the page (useful if e.g. a
    # sheet really doesn't want to load).
    if not suppressFouc or bc.window.loadedSheetNum == bc.window.remoteSheetNum:
      for handle in bc.handles:
        if handle.hasTask(bcOnReshape):
          handle.resolveTask(bcOnReshape)
        else:
          handle.onReshapeImmediately = true

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

const HoverFun = [
  htTitle: getTitleAttr,
  htLink: getClickHover,
  htImage: getImageHover,
  htCachedImage: getCachedImageHover
]
proc updateHover(bc: BufferContext; handle: PagerHandle;
    cursorx, cursory: int): UpdateHoverResult {.proxy.} =
  let thisNode = bc.getCursorElement(cursorx, cursory)
  var hover = newSeq[tuple[t: HoverType, s: string]]()
  var repaint = false
  let prevHover = handle.prevHover
  if thisNode != prevHover:
    var oldHover = newSeq[Element]()
    for element in prevHover.branchElems:
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
  handle.prevHover = thisNode
  move(hover)

proc loadResources(bc: BufferContext): EmptyPromise =
  if bc.window.pendingResources.len > 0:
    let promises = move(bc.window.pendingResources)
    if promises.len > 0:
      bc.window.pendingResources = @[]
      let res = EmptyPromise()
      var u = 0u
      let L = uint(promises.len)
      for promise in promises:
        promise.then(proc() =
          if bc.state == bsLoadingResources:
            for handle in bc.handles:
              if handle.hasTask(bcLoad):
                bc.resolveLoad(handle, bc.window.loadedSheetNum,
                  bc.window.remoteSheetNum)
          inc u
          if u == L:
            res.resolve()
        )
      return res.then(proc(): EmptyPromise =
        return bc.loadResources()
      )
  return newResolvedPromise()

proc loadImages(bc: BufferContext): EmptyPromise =
  if bc.window.pendingImages.len > 0:
    let promises = move(bc.window.pendingImages)
    if promises.len > 0:
      bc.window.pendingImages = @[]
      let res = EmptyPromise()
      var u = 0u
      let L = uint(promises.len)
      for promise in promises:
        promise.then(proc() =
          if bc.state == bsLoadingImages:
            for handle in bc.handles:
              if handle.hasTask(bcLoad):
                bc.resolveLoad(handle, bc.window.loadedImageNum,
                  bc.window.remoteImageNum)
          inc u
          if u == L:
            res.resolve()
        )
      return res.then(proc(): EmptyPromise =
        return bc.loadImages()
      )
  return newResolvedPromise()

proc rewind(bc: BufferContext; data: InputData; offset: uint64;
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

proc addPagerHandle(bc: BufferContext; stream: PosixStream) =
  let handle = PagerHandle(stream: stream)
  bc.loader.put(handle)
  bc.pollData.register(stream.fd, POLLIN)
  var it = bc.handlesHead
  if it == nil:
    bc.handlesHead = handle
  else:
    while it.next != nil:
      it = it.next
    it.next = handle

# returns true if there are still other handles, false otherwise
proc removePagerHandle(bc: BufferContext; handle: PagerHandle): bool =
  bc.loader.unset(handle)
  bc.pollData.unregister(handle.stream.fd)
  bc.loader.unregistered.add(handle.stream.fd)
  if bc.handlesHead == handle:
    bc.handlesHead = bc.handlesHead.next
  else:
    var it = bc.handlesHead
    while it.next != handle:
      it = it.next
    it.next = it.next.next
  bc.handlesHead != nil

proc cloneCmd(bc: BufferContext; handle: PagerHandle; r: var PacketReader;
    packetid: int): CommandResult =
  var newurl: URL
  r.sread(newurl)
  let pstream = newSocketStream(r.recvFd())
  bc.addPagerHandle(pstream)
  let target = bc.document.findAnchor(newurl.hash)
  bc.document.setTarget(target)
  handle.stream.withPacketWriterReturnEOF w:
    w.swrite(packetid)
  cmdrDone

proc dispatchDOMContentLoadedEvent(bc: BufferContext) =
  let window = bc.window
  window.fireEvent(satDOMContentLoaded, bc.document, bubbles = false,
    cancelable = false, trusted = true)
  bc.maybeReshape(suppressFouc = true)

proc dispatchLoadEvent(bc: BufferContext) =
  let window = bc.window
  let event = newEvent(satLoad.toAtom(), window.document, bubbles = false,
    cancelable = false)
  event.isTrusted = true
  discard window.jsctx.dispatch(window, event, targetOverride = true)
  bc.maybeReshape()

proc finishLoad(bc: BufferContext; data: InputData) =
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

proc headlessMustWait(bc: BufferContext): bool =
  return bc.config.scripting != smFalse and
      (not bc.window.timeouts.empty or bc.checkJobs) or
    bc.loader.hasFds()

# Returns:
# * -1 if loading is done
# * a positive number for reporting the number of bytes loaded and that the page
#   has been partially rendered.
proc load(bc: BufferContext; handle: PagerHandle): LoadResult {.
    proxy: pfTask.} =
  var n = 0'u64
  var len = 0'u64
  let bs = bc.state
  case bs
  of bsLoaded:
    if bc.config.headless == hmTrue and bc.headlessMustWait():
      # suppress load event until all scripts have finished
      # (obviously, this might never happen)
      bc.savetask = true
      bc.headlessLoading = true
  of bsLoadingImages:
    n = bc.window.loadedImageNum
    len = bc.window.remoteImageNum
  of bsLoadingResources:
    n = bc.window.loadedSheetNum
    len = bc.window.remoteSheetNum
  of bsLoadingPage:
    n = bc.bytesRead
    #TODO the problem here is that content-length is for compressed size,
    # but we already uncompress inside CGI so it's impossible to compare
    # the two
    # probably we'll need some reporting mechanism in BGI
    if n > handle.reportedLoad.n:
      bc.maybeReshape(suppressFouc = true)
  let old = handle.reportedLoad
  let res = (n: n, len: len, bs: bs)
  if bs != bsLoaded and old.bs == bs and n == old.n:
    # drop this result, resolve in onload instead
    bc.savetask = true
  else:
    handle.reportedLoad = res
  res

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
      n = data.stream.read(iq)
      if n < 0:
        break
      bc.bytesRead += uint64(n)
    if n != 0:
      if not bc.processData(iq.toOpenArray(0, n - 1)):
        if not bc.firstBufferRead:
          reprocess = true
          continue
        if bc.rewind(data, 0):
          continue
      bc.checkJobs = true
      bc.firstBufferRead = true
      reprocess = false
    else: # EOF
      bc.finishLoad(data)
      if bc.window.pendingResources.len > 0:
        bc.state = bsLoadingResources
        for handle in bc.handles:
          if handle.hasTask(bcLoad):
            bc.resolveLoad(handle, bc.window.loadedSheetNum,
              bc.window.remoteSheetNum)
      bc.loadResources().then(proc() =
        # CSS loaded
        if bc.window.pendingImages.len > 0:
          bc.maybeReshape()
          bc.state = bsLoadingImages
          for handle in bc.handles:
            if handle.hasTask(bcLoad):
              bc.resolveLoad(handle, bc.window.loadedImageNum,
                bc.window.remoteImageNum)
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
          for handle in bc.handles:
            if handle.hasTask(bcGetTitle):
              handle.resolveTask(bcGetTitle, bc.document.title)
            if handle.hasTask(bcLoad):
              if bc.config.headless == hmTrue and bc.headlessMustWait():
                #TODO might want to move this to handle too
                bc.headlessLoading = true
              else:
                bc.resolveLoad(handle, 0, 0)
        )
      )
      return # skip incr render
  # incremental rendering: only if we cannot read the entire stream in one
  # pass
  if bc.config.headless == hmFalse:
    for handle in bc.handles:
      if handle.hasTask(bcLoad):
        # only makes sense when not in dump mode (and the user has requested
        # a load)
        bc.maybeReshape(suppressFouc = true)
        if handle.hasTask(bcGetTitle):
          handle.resolveTask(bcGetTitle, bc.document.title)
        bc.resolveLoad(handle, bc.bytesRead, 0) #TODO content-length

proc getTitle(bc: BufferContext; handle: PagerHandle): string {.
    proxy: pfTask.} =
  if bc.document != nil:
    let title = bc.document.findFirst(TAG_TITLE)
    if title != nil:
      return title.childTextContent.stripAndCollapse()
    if bc.state == bsLoaded:
      return "" # title no longer expected
  bc.savetask = true
  return ""

proc forceReshape(bc: BufferContext; handle: PagerHandle) {.proxy.} =
  if bc.document != nil and bc.document.documentElement != nil:
    bc.document.documentElement.invalidate()
  bc.rootBox = nil
  if bc.document != nil:
    bc.document.invalid = true
  bc.maybeReshape()

proc windowChange(bc: BufferContext; handle: PagerHandle;
    attrs: WindowAttributes; x, y: int): PagePos {.proxy.} =
  let element = bc.getCursorElement(x, y)
  let box = if element != nil: CSSBox(element.box) else: nil
  let offset = if box != nil: box.render.offset else: offset(0'lu, 0'lu)
  let ppc = attrs.ppc.toLUnit()
  let ppl = attrs.ppl.toLUnit()
  let dx = x - (offset.x div ppc).toInt()
  let dy = y - (offset.y div ppl).toInt()
  bc.attrs = attrs
  bc.window.windowChange()
  bc.maybeReshape()
  if element != nil and element.box != nil:
    let offset = CSSBox(element.box).render.offset
    let x = (offset.x div ppc).toInt() + dx
    let y = (offset.y div ppl).toInt() + dy
    return (x, y)
  return (x, y)

proc cancel(bc: BufferContext; handle: PagerHandle) {.proxy.} =
  if bc.state == bsLoaded:
    return
  for it in bc.loader.data:
    if it of PagerHandle:
      continue
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
    var contentType = $enctype
    let body = case enctype
    of fetUrlencoded:
      #TODO with charset
      let kvlist = entryList.toNameValuePairs()
      RequestBody(t: rbtString, s: serializeFormURLEncoded(kvlist))
    of fetMultipart:
      #TODO with charset
      let multipart = serializeMultipart(entryList,
        bc.window.crypto.urandom)
      contentType = multipart.getContentType()
      RequestBody(t: rbtMultipart, multipart: multipart)
    of fetTextPlain:
      #TODO with charset
      let kvlist = entryList.toNameValuePairs()
      RequestBody(t: rbtString, s: serializePlainTextFormData(kvlist))
    let headers = newHeaders(hgRequest, {"Content-Type": move(contentType)})
    return newRequest(parsedAction, httpMethod, headers, body)

# https://html.spec.whatwg.org/multipage/form-control-infrastructure.html#form-submission-algorithm
proc submitForm(bc: BufferContext; form: HTMLFormElement;
    submitter: HTMLElement; jsSubmitCall = false): Request =
  if form.constructingEntryList:
    return nil
  if not jsSubmitCall and bc.config.scripting != smFalse:
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
  let formMethod = submitter.getFormMethod()
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

proc readSuccess0(bc: BufferContext; s: string; fd: cint): Request =
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

proc readSuccessCmd(bc: BufferContext; handle: PagerHandle; r: var PacketReader;
    packetid: int): CommandResult =
  var s: string
  var hasfd: bool
  r.sread(s)
  r.sread(hasfd)
  let fd = if hasfd: r.recvFd() else: -1
  let request = bc.readSuccess0(s, fd)
  let clickResult = initClickResult(request)
  handle.stream.withPacketWriterReturnEOF w:
    w.swrite(packetid)
    w.swrite(clickResult)
  cmdrDone

proc click(bc: BufferContext; label: HTMLLabelElement): ClickResult =
  let control = label.control
  if control != nil:
    return bc.click(control)
  return initClickResult()

proc click(bc: BufferContext; select: HTMLSelectElement): ClickResult =
  if select.attrb(satMultiple):
    return initClickResult()
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
  return initClickResult(move(options), selected)

proc baseURL(bc: BufferContext): URL =
  return bc.document.baseURL

proc evalJSURL(bc: BufferContext; url: URL): Opt[string] =
  let surl = $url
  let source = surl.toOpenArray("javascript:".len, surl.high).percentDecode()
  let ctx = bc.window.jsctx
  let ret = ctx.eval(source, $bc.baseURL, JS_EVAL_TYPE_GLOBAL)
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
        return initClickResult()
      let s = bc.evalJSURL(url)
      bc.maybeReshape()
      if s.isErr:
        return initClickResult()
      let urls = parseURL0("data:text/html," & s.get)
      if urls == nil:
        return initClickResult()
      url = urls
    return initClickResult(newRequest(url, hmGet))
  return initClickResult()

proc click(bc: BufferContext; option: HTMLOptionElement): ClickResult =
  let select = option.select
  if select != nil:
    if select.attrb(satMultiple):
      option.setSelected(not option.selected)
      if bc.config.scripting != smFalse:
        bc.window.fireEvent(satChange, select, bubbles = true,
          cancelable = true, trusted = true)
      bc.maybeReshape()
      return initClickResult()
    return bc.click(select)
  return initClickResult()

proc click(bc: BufferContext; button: HTMLButtonElement): ClickResult =
  if button.form != nil:
    case button.ctype
    of btSubmit:
      let open = bc.submitForm(button.form, button)
      bc.setFocus(button)
      return initClickResult(open)
    of btReset:
      button.form.reset()
    of btButton: discard
    bc.setFocus(button)
  return initClickResult()

proc click(bc: BufferContext; textarea: HTMLTextAreaElement): ClickResult =
  bc.setFocus(textarea)
  ClickResult(t: crtReadArea, value: textarea.value)

proc click(bc: BufferContext; audio: HTMLAudioElement): ClickResult =
  bc.restoreFocus()
  let (src, contentType) = audio.getSrc()
  if src != "":
    if url := audio.document.parseURL(src):
      return initClickResult(newRequest(url), contentType)
  return initClickResult()

proc click(bc: BufferContext; video: HTMLVideoElement): ClickResult =
  bc.restoreFocus()
  let (src, contentType) = video.getSrc()
  if src != "":
    if url := video.document.parseURL(src):
      return initClickResult(newRequest(url), contentType)
  return initClickResult()

# Used for frame, ifframe
proc clickFrame(bc: BufferContext; frame: Element): ClickResult =
  bc.restoreFocus()
  let src = frame.attr(satSrc)
  if src != "":
    if url := frame.document.parseURL(src):
      return initClickResult(newRequest(url))
  return initClickResult()

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
    return ClickResult(t: crtReadFile)
  of itCheckbox:
    input.setChecked(not input.checked)
    if bc.config.scripting != smFalse:
      # Note: not an InputEvent.
      bc.window.fireEvent(satInput, input, bubbles = true,
        cancelable = true, trusted = true)
      bc.window.fireEvent(satChange, input, bubbles = true,
        cancelable = true, trusted = true)
    bc.maybeReshape()
    return initClickResult()
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
    return initClickResult()
  of itReset:
    if input.form != nil:
      input.form.reset()
      bc.maybeReshape()
    return initClickResult()
  of itSubmit, itButton:
    if input.form != nil:
      return initClickResult(bc.submitForm(input.form, input))
    return initClickResult()
  else:
    # default is text.
    var prompt = InputTypePrompt[input.inputType]
    if input.inputType == itRange:
      prompt &= " (" & input.attr(satMin) & ".." & input.attr(satMax) & ")"
    bc.setFocus(input)
    if input.inputType == itPassword:
      return ClickResult(
        t: crtReadPassword,
        prompt: prompt & ": ",
        value: input.value
      )
    return ClickResult(
      t: crtReadText,
      prompt: prompt & ": ",
      value: input.value
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

proc initMouseEventInit(bc: BufferContext; button: int16; buttons: uint16;
    x, y, detail: int): MouseEventInit =
  let x = if bc.config.scripting == smApp and x <= int32.high div bc.attrs.ppc:
    int32(x * bc.attrs.ppc)
  else:
    0
  let y = if bc.config.scripting == smApp and y <= int32.high div bc.attrs.ppl:
    int32(y * bc.attrs.ppl)
  else:
    0
  MouseEventInit(
    bubbles: true,
    cancelable: true,
    button: button,
    buttons: buttons,
    view: EventTargetWindow(bc.window),
    clientX: x,
    clientY: y,
    screenX: x,
    screenY: y,
    detail: int32(clamp(detail, 0, int32.high))
  )

proc click(bc: BufferContext; handle: PagerHandle;
    cursorx, cursory, n: int): ClickResult {.proxy.} =
  if bc.lines.len <= cursory: return ClickResult()
  var canceled = false
  let clickable = bc.getCursorClickable(cursorx, cursory)
  if bc.config.scripting != smFalse:
    let element = bc.getCursorElement(cursorx, cursory)
    if element != nil:
      bc.clickResult = initClickResult()
      let window = bc.window
      let init = bc.initMouseEventInit(0, 0, cursorx, cursory, n)
      let event = newMouseEvent(satClick.toAtom(), init)
      event.isTrusted = true
      canceled = window.jsctx.dispatch(element, event)
      if n == 2:
        let init = bc.initMouseEventInit(0, 0, cursorx, cursory, n)
        let event = newMouseEvent(satDblclick.toAtom(), init)
        event.isTrusted = true
        discard window.jsctx.dispatch(element, event)
      bc.maybeReshape()
      if bc.clickResult.t != crtNone:
        return bc.clickResult
  let url = bc.navigateUrl
  bc.navigateUrl = nil
  if not canceled and clickable != nil:
    return bc.click(clickable)
  if url != nil:
    return initClickResult(newRequest(url, hmGet))
  return initClickResult()

proc contextMenu(bc: BufferContext; handle: PagerHandle;
    cursorx, cursory: int): bool {.proxy.} =
  var canceled = false
  if bc.config.scripting != smFalse:
    let element = bc.getCursorElement(cursorx, cursory)
    if element != nil:
      bc.clickResult = initClickResult()
      let window = bc.window
      let init = bc.initMouseEventInit(2, 2, cursorx, cursory, 1)
      let event = newMouseEvent(satContextmenu.toAtom(), init)
      event.isTrusted = true
      canceled = window.jsctx.dispatch(element, event)
      bc.maybeReshape()
  canceled

proc select(bc: BufferContext; handle: PagerHandle; selected: int): ClickResult
    {.proxy.} =
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
  return initClickResult()

proc readCanceled(bc: BufferContext; handle: PagerHandle) {.proxy.} =
  bc.restoreFocus()

# hack: avoid writing element in FormatCell by hand-rolling a serialization
# function that matches SimpleFlexibleLine
# (TODO: elements really don't belong in FormatCell...)
proc swrite(w: var PacketWriter; x: FlexibleLine) =
  w.swrite(x.str)
  w.swrite(x.formats.len)
  for f in x.formats:
    w.swrite(f.format)
    w.swrite(f.pos)

proc getLinesCmd(bc: BufferContext; handle: PagerHandle; r: var PacketReader;
    packetid: int): CommandResult =
  var slice: Slice[int]
  r.sread(slice)
  if slice.b < 0 or slice.b > bc.lines.high:
    slice.b = bc.lines.high
  handle.stream.withPacketWriterReturnEOF w:
    w.swrite(packetid)
    w.swrite(slice.a) # lineShift
    w.swrite(bc.lines.len) # numLines
    w.swrite(bc.bgcolor) # bgcolor
    w.swrite(slice.len) # lines.len
    for y in slice: # lines.data
      w.swrite(bc.lines[y])
    var images: seq[PosBitmap]
    if bc.config.images:
      let ppl = bc.attrs.ppl
      for image in bc.images:
        let ey = image.y + (image.height + ppl - 1) div ppl # ceil
        if image.width > 0 and image.height > 0 and
            image.y <= slice.b and ey >= slice.a:
          images.add(image)
    w.swrite(images) # images
  cmdrDone

proc getSelectionText(bc: BufferContext; handle: PagerHandle;
    sx, sy, ex, ey: int; t: SelectionType): string {.proxy.} =
  var s = ""
  let sy = max(sy, 0)
  let ey = min(bc.lines.high, ey)
  case t
  of stNormal:
    let si = bc.lines[sy].str.findColBytes(sx)
    let ei = bc.lines[ey].str.findColBytes(ex + 1, sx, si) - 1
    if sy == ey:
      s = bc.lines[sy].str.substr(si, ei)
    else:
      s = bc.lines[sy].str.substr(si) & '\n'
      for y in sy + 1 .. ey - 1:
        s &= bc.lines[y].str & '\n'
      s &= bc.lines[ey].str.substr(0, ei)
  of stBlock:
    for y in sy .. ey:
      let si = bc.lines[y].str.findColBytes(sx)
      let ei = bc.lines[y].str.findColBytes(ex + 1, sx, si) - 1
      if y > sy:
        s &= '\n'
      s &= bc.lines[y].str.substr(si, ei)
  of stLine:
    for y in sy .. ey:
      if y > sy:
        s &= '\n'
      s &= bc.lines[y].str
  move(s)

proc getLinks(bc: BufferContext; handle: PagerHandle): seq[string] {.proxy.} =
  result = newSeq[string]()
  if bc.document != nil:
    for element in bc.window.displayedElements:
      if element.tagType == TAG_A and element.attrb(satHref):
        if url := HTMLAnchorElement(element).reinitURL():
          result.add($url)
        else:
          result.add(element.attr(satHref))

proc onReshape(bc: BufferContext; handle: PagerHandle) {.proxy: pfTask.} =
  if handle.onReshapeImmediately:
    # We got a reshape before the container even asked us for the event.
    # This variable prevents the race that would otherwise occur if
    # the buffer were to be reshaped between two onReshape requests.
    handle.onReshapeImmediately = false
    return
  assert handle.tasks[bcOnReshape] == 0
  bc.savetask = true

proc markURL(bc: BufferContext; handle: PagerHandle) {.proxy.} =
  if bc.document == nil or bc.document.body == nil:
    return
  var buf = "("
  for i, scheme in bc.schemes.mypairs:
    if i > 0:
      buf &= '|'
    buf &= scheme
  buf &= r"):(//[\w%:.-]+)?[\w/@%:.~-]*\??[\w%:~.=&-]*#?[\w:~.=-]*[\w/~=-]"
  var regex: Regex
  doAssert compileRegex(buf, {LRE_FLAG_GLOBAL}, regex)
  # Dummy element for the fragment parsing algorithm. We can't just use parent
  # there, because e.g. plaintext would not parse the text correctly.
  let html = bc.document.newHTMLElement(TAG_DIV)
  var stack = @[bc.document.body]
  while stack.len > 0:
    let element = stack.pop()
    var texts = newSeq[Text]()
    var lastText: Text = nil
    for node in element.safeChildList:
      if node of Text:
        let text = Text(node)
        if lastText != nil:
          lastText.data &= text.data.s
          text.remove()
        else:
          texts.add(text)
          lastText = text
      elif node of HTMLElement:
        let element = HTMLElement(node)
        if element.tagType in {TAG_NOBR, TAG_WBR}:
          element.remove()
        elif element.tagType notin {TAG_HEAD, TAG_SCRIPT, TAG_STYLE, TAG_A}:
          stack.add(element)
          lastText = nil
        else:
          lastText = nil
      else:
        lastText = nil
    for text in texts:
      var data = ""
      var j = 0
      for cap in regex.matchCap(text.data.s, 0):
        let capLen = cap.e - cap.s
        while j < cap.s:
          case (let c = text.data[j]; c)
          of '<':
            data &= "&lt;"
          of '>':
            data &= "&gt;"
          of '\'':
            data &= "&apos;"
          of '"':
            data &= "&quot;"
          of '&':
            data &= "&amp;"
          else:
            data &= c
          inc j
        let s = text.data.s[j ..< j + capLen]
        let news = "<a href=\"" & s & "\">" & s.htmlEscape() & "</a>"
        data &= news
        j += capLen
      if data.len > 0:
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
  bc.maybeReshape()

proc toggleImages(bc: BufferContext; handle: PagerHandle): bool {.
    proxy: pfTask.} =
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
    if handle.tasks[bcToggleImages] == 0:
      # we resolved in then
      bc.savetask = false
    else:
      handle.resolveTask(bcToggleImages, bc.config.images)
    bc.maybeReshape()
  )
  return bc.config.images

proc findLeaf(box: CSSBox; element: Element): CSSBox =
  for it in box.children:
    if it.element == element or
        it.element.parentNode == element and not it.element.isClickable():
      let box = it.findLeaf(it.element)
      if box.computed{"visibility"} == VisibilityVisible and
          box of InlineTextBox:
        return box
  return box

proc showHints(bc: BufferContext; handle: PagerHandle; sx, sy, ex, ey: int):
    HintResult {.proxy.} =
  result = @[]
  bc.maybeReshape()
  let ppc = bc.attrs.ppc.toLUnit()
  let ppl = bc.attrs.ppl.toLUnit()
  let so = offset(x = sx.toLUnit() * ppc, y = sy.toLUnit() * ppl)
  let eo = offset(x = ex.toLUnit() * ppc, y = ey.toLUnit() * ppl)
  for element in bc.window.displayedElements:
    if element.box != nil and element.isClickable():
      let box = CSSBox(element.box).findLeaf(element)
      let offset = box.render.offset
      if offset >= so and offset < eo:
        result.add(CursorXY(
          x: (offset.x div ppc).toInt(),
          y: (offset.y div ppl).toInt()
        ))
        element.setHint(true)
  bc.nhints = result.len
  bc.maybeReshape()

proc submitForm(bc: BufferContext; handle: PagerHandle; cursorx, cursory: int):
    ClickResult {.proxy.} =
  var element = bc.getCursorElement(cursorx, cursory)
  var form: HTMLFormElement = nil
  while element != nil:
    if element.tagType == TAG_FORM:
      form = HTMLFormElement(element)
      break
    if element of FormAssociatedElement:
      form = FormAssociatedElement(element).form
      break
    element = element.parentElement
  if form == nil:
    return ClickResult()
  let open = bc.submitForm(form, form) #TODO maybe use element as submitter?
  return initClickResult(open)

proc hideHints(bc: BufferContext; handle: PagerHandle) {.proxy.} =
  for element in bc.window.document.elementDescendants:
    element.setHint(false)
  bc.maybeReshape()

# Note: these functions are automatically generated by the .proxy macro.
const ProxyMap = [
  bcCancel: cancelCmd,
  bcCheckRefresh: checkRefreshCmd,
  bcClick: clickCmd,
  bcClone: cloneCmd,
  bcContextMenu: contextMenuCmd,
  bcFindNextLink: findNextLinkCmd,
  bcFindNextMatch: findNextMatchCmd,
  bcFindNextParagraph: findNextParagraphCmd,
  bcFindPrevLink: findPrevLinkCmd,
  bcFindPrevMatch: findPrevMatchCmd,
  bcFindRevNthLink: findRevNthLinkCmd,
  bcForceReshape: forceReshapeCmd,
  bcGetLines: getLinesCmd,
  bcGetLinks: getLinksCmd,
  bcGetSelectionText: getSelectionTextCmd,
  bcGetTitle: getTitleCmd,
  bcGotoAnchor: gotoAnchorCmd,
  bcHideHints: hideHintsCmd,
  bcLoad: loadCmd,
  bcMarkURL: markURLCmd,
  bcOnReshape: onReshapeCmd,
  bcReadCanceled: readCanceledCmd,
  bcReadSuccess: readSuccessCmd,
  bcSelect: selectCmd,
  bcShowHints: showHintsCmd,
  bcSubmitForm: submitFormCmd,
  bcToggleImages: toggleImagesCmd,
  bcUpdateHover: updateHoverCmd,
  bcWindowChange: windowChangeCmd,
]

proc readCommand(bc: BufferContext; data: PagerHandle): CommandResult =
  var res = cmdrDone
  data.stream.withPacketReader r:
    var cmd: BufferCommand
    var packetid: int
    r.sread(cmd)
    r.sread(packetid)
    res = ProxyMap[cmd](bc, data, r, packetid)
  do: # EOF, pager died
    return cmdrEOF
  res

proc handleRead(bc: BufferContext; fd: int): bool =
  if fd in bc.loader.unregistered:
    discard # ignore (see pager handleError for explanation)
  elif (let data = bc.loader.get(fd); data != nil):
    if data of PagerHandle:
      let handle = PagerHandle(data)
      case bc.readCommand(handle)
      of cmdrDone: discard
      of cmdrEOF:
        if not bc.removePagerHandle(handle):
          return false
    elif data of InputData:
      bc.onload(InputData(data))
    else:
      bc.loader.onRead(fd)
      bc.checkJobs = true
  else:
    assert false
  true

proc handleError(bc: BufferContext; fd: int): bool =
  if fd in bc.loader.unregistered:
    discard # ignore (see pager handleError for explanation)
  elif (let data = bc.loader.get(fd); data != nil):
    if data of InputData:
      bc.onload(InputData(data))
    elif data of PagerHandle:
      # Connection reset by peer, probably.  Close the buffer.
      return false
    else:
      if not bc.loader.onError(fd):
        #TODO handle connection error
        assert false, $fd
      bc.checkJobs = true
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
      for handle in bc.handles:
        bc.resolveLoad(handle, 0, 0) # already set to bsLoad
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
      if bc.window.timeouts.run(bc.window.console) or bc.checkJobs:
        bc.window.runJSJobs()
        bc.maybeReshape(suppressFouc = true)
        bc.checkJobs = false

proc cleanup(bc: BufferContext) =
  #TODO loader map handles?
  bc.window.crypto.urandom.sclose()
  if bc.config.scripting != smFalse:
    bc.window.jsctx.free()
    bc.window.jsrt.free()

proc launchBuffer*(config: BufferConfig; url: URL; attrs: WindowAttributes;
    ishtml: bool; charsetStack: seq[Charset]; loader: FileLoader;
    pstream, istream: SocketStream; urandom: PosixStream; cacheId: int;
    contentType: string; linkHintChars: sink seq[uint32];
    schemes: sink seq[string]) =
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
    charsetStack: charsetStack,
    cacheId: cacheId,
    outputId: -1,
    luctx: LUContext(),
    schemes: schemes
  )
  bc.linkHintChars = new(seq[uint32])
  bc.linkHintChars[] = linkHintChars
  bc.window = newWindow(
    config.scripting,
    config.images,
    config.styling,
    config.autofocus,
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
    if bc.config.scripting == smApp:
      bc.window.ensureLayout = proc(element: Element) =
        bc.maybeReshape(suppressFouc = true)
  bc.charset = bc.charsetStack.pop()
  istream.setBlocking(false)
  bc.loader.put(InputData(stream: istream))
  bc.pollData.register(istream.fd, POLLIN)
  bc.addPagerHandle(pstream)
  loader.registerFun = proc(fd: int) =
    bc.pollData.register(fd, POLLIN)
  loader.unregisterFun = proc(fd: int) =
    bc.pollData.unregister(fd)
  bc.initDecoder()
  bc.htmlParser = newHTML5ParserWrapper(bc.window, url, confidence, bc.charset)
  bc.document.applyUASheet()
  bc.document.applyUserSheet(bc.config.userStyle)
  bc.runBuffer()
  bc.cleanup()
  quit(0)

{.pop.} # raises: []
