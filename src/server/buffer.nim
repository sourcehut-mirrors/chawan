from std/strutils import split, toUpperAscii, find, AllChars

import std/macros
import std/options
import std/os
import std/posix
import std/tables

import chagashi/charset
import chagashi/decoder
import chagashi/decodercore
import chame/tags
import config/config
import css/box
import css/cascade
import css/layout
import css/lunit
import css/render
import css/sheet
import css/stylednode
import html/catom
import html/chadombuilder
import html/dom
import html/enums
import html/env
import html/event
import html/formdata as formdata_impl
import html/script
import io/bufreader
import io/bufwriter
import io/console
import io/dynstream
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
import types/url
import types/winattrs
import utils/strwidth
import utils/twtstr

type
  BufferCommand* = enum
    bcLoad, bcForceReshape, bcWindowChange, bcReadSuccess, bcReadCanceled,
    bcClick, bcFindNextLink, bcFindPrevLink, bcFindNthLink, bcFindRevNthLink,
    bcFindNextMatch, bcFindPrevMatch, bcGetLines, bcUpdateHover, bcGotoAnchor,
    bcCancel, bcGetTitle, bcSelect, bcClone, bcFindPrevParagraph,
    bcFindNextParagraph, bcMarkURL, bcToggleImages, bcCheckRefresh

  BufferState = enum
    bsLoadingPage, bsLoadingResources, bsLoaded

  HoverType* = enum
    htTitle, htLink, htImage, htCachedImage

  BufferMatch* = object
    success*: bool
    x*: int
    y*: int
    str*: string

  Buffer = ref object
    attrs: WindowAttributes
    bgcolor: CellColor
    bytesRead: int
    cacheId: int
    charset: Charset
    charsetStack: seq[Charset]
    config: BufferConfig
    ctx: TextDecoderContext
    document: Document
    estream: DynFileStream # error stream
    factory: CAtomFactory
    fd: int # file descriptor of buffer source
    firstBufferRead: bool
    hoverText: array[HoverType, string]
    htmlParser: HTML5ParserWrapper
    images: seq[PosBitmap]
    ishtml: bool
    istream: PosixStream
    lines: FlexibleGrid
    loader: FileLoader
    needsBOMSniff: bool
    needsReshape: bool
    outputId: int
    pollData: PollData
    prevHover: Element
    prevStyled: StyledNode
    pstream: SocketStream # control stream
    quirkstyle: CSSStylesheet
    reportedBytesRead: int
    rfd: int # file descriptor of command pipe
    rootBox: BlockBox
    savetask: bool
    state: BufferState
    tasks: array[BufferCommand, int] #TODO this should have arguments
    uastyle: CSSStylesheet
    url: URL # URL before readFromFd
    userstyle: CSSStylesheet
    window: Window

  BufferIfaceItem = object
    id: int
    p: EmptyPromise
    get: GetValueProc

  BufferInterface* = ref object
    map: seq[BufferIfaceItem]
    packetid: int
    len: int
    auxLen: int
    stream*: BufStream

  BufferConfig* = object
    userstyle*: string
    refererFrom*: bool
    styling*: bool
    scripting*: ScriptingMode
    images*: bool
    isdump*: bool
    autofocus*: bool
    history*: bool
    charsetOverride*: Charset
    metaRefresh*: MetaRefresh
    cookieMode*: CookieMode
    charsets*: seq[Charset]
    protocol*: Table[string, ProtocolConfig]
    imageTypes*: Table[string, string]
    userAgent*: string
    referrer*: string

  GetValueProc = proc(iface: BufferInterface; promise: EmptyPromise) {.nimcall.}

# Forward declarations
proc submitForm(buffer: Buffer; form: HTMLFormElement; submitter: Element):
  Request

proc getFromStream[T](iface: BufferInterface; promise: EmptyPromise) =
  if iface.len != 0:
    let promise = Promise[T](promise)
    var r = iface.stream.initReader(iface.len, iface.auxLen)
    r.sread(promise.res)
    iface.len = 0

proc addPromise[T](iface: BufferInterface; id: int): Promise[T] =
  let promise = Promise[T]()
  iface.map.add(BufferIfaceItem(id: id, p: promise, get: getFromStream[T]))
  return promise

proc addEmptyPromise(iface: BufferInterface; id: int): EmptyPromise =
  let promise = EmptyPromise()
  iface.map.add(BufferIfaceItem(id: id, p: promise, get: nil))
  return promise

func findPromise(iface: BufferInterface; id: int): int =
  for i in 0 ..< iface.map.len:
    if iface.map[i].id == id:
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

# After cloning a buffer, we need a new interface to the new buffer process.
# Here we create a new interface for that clone.
proc cloneInterface*(stream: BufStream): BufferInterface =
  let iface = newBufferInterface(stream)
  #TODO buffered data should probably be copied here
  # We have just fork'ed the buffer process inside an interface function,
  # from which the new buffer is going to return as well. So we must also
  # consume the return value of the clone function, which is the pid 0.
  var pid: int
  stream.withPacketReader r:
    r.sread(iface.packetid)
    r.sread(pid)
  return iface

proc resolve*(iface: BufferInterface; packetid, len, auxLen: int) =
  iface.len = len
  iface.auxLen = auxLen
  iface.resolve(packetid)
  # Protection against accidentally not exhausting data available to read,
  # by setting len to 0 in getFromStream.
  # (If this assertion is failing, then it means you then()'ed a promise which
  # should read something from the stream with an empty function.)
  assert iface.len == 0

proc hasPromises*(iface: BufferInterface): bool =
  return iface.map.len > 0

# get enum identifier of proxy function
func getFunId(fun: NimNode): string =
  let name = fun[0] # sym
  return "bc" & name.strVal[0].toUpperAscii() & name.strVal.substr(1)

proc buildInterfaceProc(fun: NimNode; funid: string):
    tuple[fun, name: NimNode] =
  let name = fun[0] # sym
  let params = fun[3] # formalparams
  let retval = params[0] # sym
  var body = newStmtList()
  assert params.len >= 2 # return type, this value
  let nup = ident(funid) # add this to enums
  let this2 = newIdentDefs(ident("iface"), ident("BufferInterface"))
  let thisval = this2[0]
  var params2: seq[NimNode] = @[]
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
  params2.add(retval2)
  params2.add(this2)
  # flatten args
  for i in 2 ..< params.len:
    let param = params[i]
    for i in 0 ..< param.len - 2:
      let id2 = newIdentDefs(ident(param[i].strVal), param[^2])
      params2.add(id2)
  body.add(quote do:
    var writer {.inject.} = `thisval`.stream.initWriter()
    writer.swrite(BufferCommand.`nup`)
    writer.swrite(`thisval`.packetid)
  )
  for i in 2 ..< params2.len:
    let s = params2[i][0] # sym e.g. url
    body.add(quote do:
      writer.swrite(`s`)
    )
  body.add(quote do:
    writer.flush()
    writer.deinit()
    let promise = `addfun`
    inc `thisval`.packetid
    return promise
  )
  var pragmas: NimNode
  if retval.kind == nnkEmpty:
    pragmas = newNimNode(nnkPragma).add(ident("discardable"))
  else:
    pragmas = newEmptyNode()
  return (newProc(name, params2, body, pragmas = pragmas), nup)

type
  ProxyFunction = ref object
    iname: NimNode # internal name
    ename: NimNode # enum name
    params: seq[NimNode]
    istask: bool
  ProxyMap = Table[string, ProxyFunction]

# Name -> ProxyFunction
var ProxyFunctions {.compileTime.}: ProxyMap

proc getProxyFunction(funid: string): ProxyFunction =
  if funid notin ProxyFunctions:
    ProxyFunctions[funid] = ProxyFunction()
  return ProxyFunctions[funid]

macro proxy0(fun: untyped) =
  fun[0] = ident(fun[0].strVal & "_internal")
  return fun

macro proxy1(fun: typed) =
  let funid = getFunId(fun)
  let iproc = buildInterfaceProc(fun, funid)
  let pfun = getProxyFunction(funid)
  pfun.iname = ident(fun[0].strVal & "_internal")
  pfun.ename = iproc[1]
  pfun.params.add(fun[3][0])
  var params2: seq[NimNode] = @[]
  params2.add(fun[3][0])
  for i in 1 ..< fun[3].len:
    let param = fun[3][i]
    pfun.params.add(param)
    for i in 0 ..< param.len - 2:
      let id2 = newIdentDefs(ident(param[i].strVal), param[^2])
      params2.add(id2)
  ProxyFunctions[funid] = pfun
  return iproc[0]

macro proxy(fun: typed) =
  quote do:
    proxy0(`fun`)
    proxy1(`fun`)

macro task(fun: typed) =
  let funid = getFunId(fun)
  let pfun = getProxyFunction(funid)
  pfun.istask = true
  fun

func getTitleAttr(buffer: Buffer; element: Element): string =
  if element != nil:
    for element in element.branchElems:
      if element.attrb(satTitle):
        return element.attr(satTitle)
  return ""

const ClickableElements = {
  TAG_A, TAG_INPUT, TAG_OPTION, TAG_BUTTON, TAG_TEXTAREA, TAG_LABEL,
  TAG_VIDEO, TAG_AUDIO, TAG_IFRAME
}

proc isClickable(element: Element): bool =
  if element of HTMLAnchorElement:
    return HTMLAnchorElement(element).reinitURL().isSome
  if element.isButton() and FormAssociatedElement(element).form == nil:
    return false
  return element.tagType in ClickableElements

proc getClickable(element: Element): Element =
  for element in element.branchElems:
    if element.isClickable():
      return element
  return nil

proc getClickable(styledNode: StyledNode): Element =
  if styledNode == nil:
    return nil
  return styledNode.element.getClickable()

func canSubmitOnClick(fae: FormAssociatedElement): bool =
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

proc getImageHover(buffer: Buffer; element: Element): string =
  if element of HTMLImageElement:
    let image = HTMLImageElement(element)
    let src = image.attr(satSrc)
    if src != "":
      let url = image.document.parseURL(src)
      if url.isSome:
        return $url.get
  ""

proc getClickHover(buffer: Buffer; element: Element): string =
  let clickable = element.getClickable()
  if clickable != nil:
    if clickable of HTMLAnchorElement:
      let url = HTMLAnchorElement(clickable).reinitURL()
      if url.isSome:
        return $url.get
    elif clickable of FormAssociatedElement:
      #TODO this is inefficient and also quite stupid
      let fae = FormAssociatedElement(clickable)
      if fae.canSubmitOnClick():
        let req = buffer.submitForm(fae.form, fae)
        if req != nil:
          return $req.url
      return "<" & $clickable.tagType & ">"
    elif clickable of HTMLOptionElement:
      return "<option>"
    elif clickable of HTMLVideoElement or clickable of HTMLAudioElement:
      let (src, _) = HTMLElement(clickable).getSrc()
      if src != "":
        let url = clickable.document.parseURL(src)
        if url.isSome:
          return $url.get
    elif clickable of HTMLIFrameElement:
      let src = clickable.attr(satSrc)
      if src != "":
        let url = clickable.document.parseURL(src)
        if url.isSome:
          return $url.get
  ""

proc getCachedImageHover(buffer: Buffer; element: Element): string =
  if element of HTMLImageElement:
    let image = HTMLImageElement(element)
    if image.bitmap != nil and image.bitmap.cacheId != 0:
      return $image.bitmap.cacheId & ' ' & image.bitmap.contentType
  elif element of SVGSVGElement:
    let image = SVGSVGElement(element)
    if image.bitmap != nil and image.bitmap.cacheId != 0:
      return $image.bitmap.cacheId & ' ' & image.bitmap.contentType
  ""

func getCursorStyledNode(buffer: Buffer; cursorx, cursory: int): StyledNode =
  let i = buffer.lines[cursory].findFormatN(cursorx) - 1
  if i >= 0:
    return buffer.lines[cursory].formats[i].node
  return nil

func getCursorElement(buffer: Buffer; cursorx, cursory: int): Element =
  let styledNode = buffer.getCursorStyledNode(cursorx, cursory)
  if styledNode == nil:
    return nil
  return styledNode.element

proc getCursorClickable(buffer: Buffer; cursorx, cursory: int): Element =
  let element = buffer.getCursorElement(cursorx, cursory)
  if element != nil:
    return element.getClickable()
  return nil

func cursorBytes(buffer: Buffer; y, cc: int): int =
  let line = buffer.lines[y].str
  var w = 0
  var i = 0
  while i < line.len and w < cc:
    let u = line.nextUTF8(i)
    w += u.width()
  return i

proc navigate(buffer: Buffer; url: URL) =
  #TODO how?
  # maybe we could reuse meta refresh for the time being
  stderr.write("navigate to " & $url & "\n")

#TODO rewrite findPrevLink, findNextLink to use the box tree instead
proc findPrevLink*(buffer: Buffer; cursorx, cursory, n: int):
    tuple[x, y: int] {.proxy.} =
  if cursory >= buffer.lines.len:
    return (-1, -1)
  var found = 0
  var i = buffer.lines[cursory].findFormatN(cursorx) - 1
  var link: Element = nil
  if cursorx == int.high:
    # Special case for when we want to jump to the last link on this
    # line (for cursorLinkNavUp).
    i = buffer.lines[cursory].formats.len
  elif i >= 0:
    link = buffer.lines[cursory].formats[i].node.getClickable()
  dec i
  var ly = 0 # last y
  var lx = 0 # last x
  for y in countdown(cursory, 0):
    let line = buffer.lines[y]
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
          let line = buffer.lines[iy]
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

proc findNextLink*(buffer: Buffer; cursorx, cursory, n: int):
    tuple[x, y: int] {.proxy.} =
  if cursory >= buffer.lines.len:
    return (-1, -1)
  var found = 0
  var i = buffer.lines[cursory].findFormatN(cursorx) - 1
  var link: Element = nil
  if i >= 0:
    link = buffer.lines[cursory].formats[i].node.getClickable()
  inc i
  for j, line in buffer.lines.toOpenArray(cursory, buffer.lines.high).mypairs:
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

proc findPrevParagraph*(buffer: Buffer; cursory, n: int): int {.proxy.} =
  var y = cursory
  for i in 0 ..< n:
    while y >= 0 and buffer.lines[y].str.onlyWhitespace():
      dec y
    while y >= 0 and not buffer.lines[y].str.onlyWhitespace():
      dec y
  return y

proc findNextParagraph*(buffer: Buffer; cursory, n: int): int {.proxy.} =
  var y = cursory
  for i in 0 ..< n:
    while y < buffer.lines.len and buffer.lines[y].str.onlyWhitespace():
      inc y
    while y < buffer.lines.len and not buffer.lines[y].str.onlyWhitespace():
      inc y
  return y

proc findNthLink*(buffer: Buffer; i: int): tuple[x, y: int] {.proxy.} =
  if i == 0:
    return (-1, -1)
  var k = 0
  var link: Element
  for y in 0 .. buffer.lines.high:
    let line = buffer.lines[y]
    for j in 0 ..< line.formats.len:
      let format = line.formats[j]
      let fl = format.node.getClickable()
      if fl != nil and fl != link:
        inc k
        if k == i:
          return (format.pos, y)
        link = fl
  return (-1, -1)

proc findRevNthLink*(buffer: Buffer; i: int): tuple[x, y: int] {.proxy.} =
  if i == 0:
    return (-1, -1)
  var k = 0
  var link: Element
  for y in countdown(buffer.lines.high, 0):
    let line = buffer.lines[y]
    for j in countdown(line.formats.high, 0):
      let format = line.formats[j]
      let fl = format.node.getClickable()
      if fl != nil and fl != link:
        inc k
        if k == i:
          return (format.pos, y)
        link = fl
  return (-1, -1)

proc findPrevMatch*(buffer: Buffer; regex: Regex; cursorx, cursory: int;
    wrap: bool, n: int): BufferMatch {.proxy.} =
  if cursory >= buffer.lines.len: return
  var y = cursory
  let b = buffer.cursorBytes(y, cursorx)
  let res = regex.exec(buffer.lines[y].str, 0, b)
  var numfound = 0
  if res.captures.len > 0:
    let cap = res.captures[^1][0]
    let x = buffer.lines[y].str.width(0, cap.s)
    let str = buffer.lines[y].str.substr(cap.s, cap.e - 1)
    inc numfound
    if numfound >= n:
      return BufferMatch(success: true, x: x, y: y, str: str)
  dec y
  while true:
    if y < 0:
      if wrap:
        y = buffer.lines.high
      else:
        break
    let res = regex.exec(buffer.lines[y].str)
    if res.captures.len > 0:
      let cap = res.captures[^1][0]
      let x = buffer.lines[y].str.width(0, cap.s)
      let str = buffer.lines[y].str.substr(cap.s, cap.e - 1)
      inc numfound
      if numfound >= n:
        return BufferMatch(success: true, x: x, y: y, str: str)
    if y == cursory:
      break
    dec y

proc findNextMatch*(buffer: Buffer; regex: Regex; cursorx, cursory: int;
    wrap: bool; n: int): BufferMatch {.proxy.} =
  if cursory >= buffer.lines.len: return
  var y = cursory
  let b = buffer.cursorBytes(y, cursorx + 1)
  let res = regex.exec(buffer.lines[y].str, b, buffer.lines[y].str.len)
  var numfound = 0
  if res.success and res.captures.len > 0:
    let cap = res.captures[0][0]
    let x = buffer.lines[y].str.width(0, cap.s)
    let str = buffer.lines[y].str.substr(cap.s, cap.e - 1)
    inc numfound
    if numfound >= n:
      return BufferMatch(success: true, x: x, y: y, str: str)
  inc y
  while true:
    if y > buffer.lines.high:
      if wrap:
        y = 0
      else:
        break
    let res = regex.exec(buffer.lines[y].str)
    if res.success and res.captures.len > 0:
      let cap = res.captures[0][0]
      let x = buffer.lines[y].str.width(0, cap.s)
      let str = buffer.lines[y].str.substr(cap.s, cap.e - 1)
      inc numfound
      if numfound >= n:
        return BufferMatch(success: true, x: x, y: y, str: str)
    if y == cursory:
      break
    inc y

type
  ReadLineType* = enum
    rltText, rltArea, rltFile

  ReadLineResult* = ref object
    t*: ReadLineType
    prompt*: string
    value*: string
    hide*: bool

  SelectResult* = ref object
    options*: seq[SelectOption]
    selected*: int

  ClickResult* = object
    open*: Request
    contentType*: string
    readline*: Option[ReadLineResult]
    repaint*: bool
    select*: Option[SelectResult]

proc click(buffer: Buffer; clickable: Element): ClickResult

type GotoAnchorResult* = object
  found*: bool
  x*: int
  y*: int
  focus*: ReadLineResult

proc findAnchor(box: BlockBox; anchor: Element): Offset

proc findAnchor(box: InlineBox; anchor: Element): Offset =
  if box.t == ibtBox:
    let off = box.box.findAnchor(anchor)
    if off.y >= 0:
      return off
  elif box.t == ibtParent:
    for child in box.children:
      let off = child.findAnchor(anchor)
      if off.y >= 0:
        return off
  if box.node.element == anchor:
    return box.render.offset
  return offset(-1, -1)

proc findAnchor(box: BlockBox; anchor: Element): Offset =
  if box.inline != nil:
    let off = box.inline.findAnchor(anchor)
    if off.y >= 0:
      return off
  for child in box.children:
    let off = child.findAnchor(anchor)
    if off.y >= 0:
      return off
  if box.node.element == anchor:
    return box.render.offset
  return offset(-1, -1)

proc gotoAnchor*(buffer: Buffer; anchor: string; autofocus, target: bool):
    GotoAnchorResult {.proxy.} =
  if buffer.document == nil:
    return GotoAnchorResult(found: false)
  var anchor = buffer.document.findAnchor(anchor.percentDecode())
  if target and anchor != nil:
    buffer.document.setTarget(anchor)
  var focus: ReadLineResult = nil
  # Do not use buffer.config.autofocus when we just want to check if the
  # anchor can be found.
  if autofocus:
    let autofocus = buffer.document.findAutoFocus()
    if autofocus != nil:
      if anchor == nil:
        anchor = autofocus # jump to autofocus instead
      let res = buffer.click(autofocus)
      focus = res.readline.get(nil)
  if anchor == nil:
    return GotoAnchorResult(found: false)
  let offset = buffer.rootBox.findAnchor(anchor)
  let x = max(offset.x div buffer.attrs.ppc, 0).toInt
  let y = max(offset.y div buffer.attrs.ppl, 0).toInt
  return GotoAnchorResult(found: true, x: x, y: y, focus: focus)

type CheckRefreshResult* = object
  # n is timeout in millis. -1 => not found
  n*: int
  # url == nil => self
  url*: URL

proc checkRefresh*(buffer: Buffer): CheckRefreshResult {.proxy.} =
  if buffer.document == nil:
    return CheckRefreshResult(n: -1)
  let element = buffer.document.findMetaRefresh()
  if element == nil:
    return CheckRefreshResult(n: -1)
  let s = element.attr(satContent)
  var i = s.skipBlanks(0)
  let s0 = s.until(AllChars - AsciiDigit, i)
  let x = parseUInt32(s0, allowSign = false)
  if s0 != "":
    if x.isNone and (i >= s.len or s[i] != '.'):
      return CheckRefreshResult(n: -1)
  var n = int(x.get(0) * 1000)
  i = s.skipBlanks(i + s0.len)
  if i < s.len and s[i] == '.':
    inc i
    let s1 = s.until(AllChars - AsciiDigit, i)
    if s1 != "":
      n += int(parseUInt32(s1, allowSign = false).get(0))
      i = s.skipBlanks(i + s1.len)
  if i >= s.len: # just reload this page
    return CheckRefreshResult(n: n)
  if s[i] notin {',', ';'}:
    return CheckRefreshResult(n: -1)
  i = s.skipBlanks(i + 1)
  if s.toOpenArray(i, s.high).startsWithIgnoreCase("url="):
    i = s.skipBlanks(i + "url=".len)
  var q = false
  if i < s.len and s[i] in {'"', '\''}:
    q = true
    inc i
  var s2 = s.substr(i)
  if q and s2.len > 0 and s[^1] in {'"', '\''}:
    s2.setLen(s2.high)
  let url = buffer.document.parseURL(s2)
  if url.isNone:
    return CheckRefreshResult(n: -1)
  return CheckRefreshResult(n: n, url: url.get)

proc maybeRestyle(buffer: Buffer) =
  if buffer.document == nil:
    return
  if buffer.document.invalid or buffer.document.cachedSheetsInvalid:
    let uastyle = if buffer.document.mode != QUIRKS:
      buffer.uastyle
    else:
      buffer.quirkstyle
    if buffer.document.cachedSheetsInvalid:
      buffer.prevStyled = nil
    let styledRoot = buffer.document.applyStylesheets(uastyle,
      buffer.userstyle, buffer.prevStyled)
    buffer.prevStyled = styledRoot
    buffer.document.invalid = false
    buffer.needsReshape = true

proc maybeReshape(buffer: Buffer): bool {.discardable.} =
  if buffer.document == nil:
    return # not parsed yet, nothing to render
  buffer.maybeRestyle()
  if buffer.needsReshape:
    buffer.rootBox = nil
    # applyStylesheets may return nil if there is no <html> element.
    if buffer.prevStyled != nil:
      buffer.rootBox = buffer.prevStyled.layout(addr buffer.attrs)
    buffer.lines.renderDocument(buffer.bgcolor, buffer.rootBox,
      addr buffer.attrs, buffer.images)
    buffer.needsReshape = false
    return true
  return false

proc processData0(buffer: Buffer; data: UnsafeSlice): bool =
  if buffer.ishtml:
    if buffer.htmlParser.parseBuffer(data.toOpenArray()) == PRES_STOP:
      buffer.charsetStack = @[buffer.htmlParser.builder.charset]
      return false
  else:
    var plaintext = buffer.document.findFirst(TAG_PLAINTEXT)
    if plaintext == nil:
      const s = "<plaintext>"
      doAssert buffer.htmlParser.parseBuffer(s) != PRES_STOP
      plaintext = buffer.document.findFirst(TAG_PLAINTEXT)
    if data.len > 0:
      let lastChild = plaintext.lastChild
      if lastChild != nil and lastChild of Text:
        Text(lastChild).data &= data
      else:
        plaintext.insert(buffer.document.createTextNode($data), nil)
      plaintext.setInvalid()
  true

func canSwitch(buffer: Buffer): bool {.inline.} =
  return buffer.htmlParser.builder.confidence == ccTentative and
    buffer.charsetStack.len > 0

const BufferSize = 16384

proc initDecoder(buffer: Buffer) =
  buffer.ctx = initTextDecoderContext(buffer.charset, demFatal, BufferSize)

proc switchCharset(buffer: Buffer) =
  buffer.charset = buffer.charsetStack.pop()
  buffer.initDecoder()
  buffer.htmlParser.restart(buffer.charset)
  buffer.document = buffer.htmlParser.builder.document
  buffer.prevStyled = nil

proc bomSniff(buffer: Buffer; iq: openArray[uint8]): int =
  if iq[0] == 0xFE and iq[1] == 0xFF:
    buffer.charsetStack = @[CHARSET_UTF_16_BE]
    buffer.switchCharset()
    return 2
  if iq[0] == 0xFF and iq[1] == 0xFE:
    buffer.charsetStack = @[CHARSET_UTF_16_LE]
    buffer.switchCharset()
    return 2
  if iq[0] == 0xEF and iq[1] == 0xBB and iq[2] == 0xBF:
    buffer.charsetStack = @[CHARSET_UTF_8]
    buffer.switchCharset()
    return 3
  return 0

proc processData(buffer: Buffer; iq: openArray[uint8]): bool =
  var si = 0
  if buffer.needsBOMSniff:
    if iq.len >= 3: # ehm... TODO
      si += buffer.bomSniff(iq)
    buffer.needsBOMSniff = false
  if not buffer.canSwitch():
    buffer.ctx.errorMode = demReplacement
  for chunk in buffer.ctx.decode(iq.toOpenArray(si, iq.high), finish = false):
    if not buffer.processData0(chunk):
      buffer.switchCharset()
      return false
  if buffer.ctx.failed:
    buffer.switchCharset()
    return false
  true

type UpdateHoverResult* = object
  hover*: seq[tuple[t: HoverType, s: string]]
  repaint*: bool

const HoverFun = [
  htTitle: getTitleAttr,
  htLink: getClickHover,
  htImage: getImageHover,
  htCachedImage: getCachedImageHover
]
proc updateHover*(buffer: Buffer; cursorx, cursory: int): UpdateHoverResult
    {.proxy.} =
  if cursory >= buffer.lines.len:
    return UpdateHoverResult()
  let thisNode = buffer.getCursorElement(cursorx, cursory)
  var hover: seq[tuple[t: HoverType, s: string]] = @[]
  var repaint = false
  let prevNode = buffer.prevHover
  if thisNode != prevNode and (thisNode == nil or prevNode == nil or
      thisNode != prevNode):
    var oldHover: seq[Element] = @[]
    for element in prevNode.branchElems:
      if element.hover:
        oldHover.add(element)
    for ht in HoverType:
      let s = HoverFun[ht](buffer, thisNode)
      if buffer.hoverText[ht] != s:
        hover.add((ht, s))
        buffer.hoverText[ht] = s
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
    buffer.maybeReshape()
  buffer.prevHover = thisNode
  return UpdateHoverResult(repaint: repaint, hover: hover)

proc loadResources(buffer: Buffer): EmptyPromise =
  if buffer.window.pendingResources.len > 0:
    let pendingResources = move(buffer.window.pendingResources)
    buffer.window.pendingResources.setLen(0)
    return pendingResources.all().then(proc(): EmptyPromise =
      return buffer.loadResources()
    )
  return newResolvedPromise()

proc rewind(buffer: Buffer; offset: int; unregister = true): bool =
  let url = newURL("cache:" & $buffer.cacheId & "?" & $offset).get
  let response = buffer.loader.doRequest(newRequest(url))
  if response.body == nil:
    return false
  buffer.loader.resume(response.outputId)
  if unregister:
    buffer.pollData.unregister(buffer.fd)
    buffer.loader.unregistered.add(buffer.fd)
  buffer.istream.sclose()
  buffer.istream = response.body
  buffer.istream.setBlocking(false)
  buffer.fd = response.body.fd
  buffer.pollData.register(buffer.fd, POLLIN)
  buffer.bytesRead = offset
  return true

var gpstream* {.global.}: SocketStream

# Create an exact clone of the current buffer.
# This clone will share the loader process with the previous buffer.
proc clone*(buffer: Buffer; newurl: URL): int {.proxy.} =
  var pipefd {.noinit.}: array[2, cint]
  if pipe(pipefd) == -1:
    buffer.estream.write("Failed to open pipe.\n")
    return -1
  # suspend outputs before tee'ing
  var ids: seq[int] = @[]
  for it in buffer.loader.ongoing:
    if it.response.onRead != nil:
      ids.add(it.response.outputId)
  buffer.loader.suspend(ids)
  # ongoing transfers are now suspended; exhaust all data in the internal buffer
  # just to be safe.
  for it in buffer.loader.ongoing:
    if it.response.onRead != nil:
      buffer.loader.onRead(it.fd)
  let pid = fork()
  if pid == -1:
    buffer.estream.write("Failed to clone buffer.\n")
    return -1
  if pid == 0: # child
    discard close(pipefd[0]) # close read
    let ps = newPosixStream(pipefd[1])
    buffer.pollData.clear()
    var connecting: seq[ConnectData] = @[]
    var ongoing: seq[OngoingData] = @[]
    for it in buffer.loader.data:
      if it of ConnectData:
        connecting.add(ConnectData(it))
      else:
        let it = OngoingData(it)
        ongoing.add(it)
        it.response.body.sclose()
      buffer.loader.unregistered.add(it.fd)
      buffer.loader.unset(it)
    let myPid = getCurrentProcessId()
    for it in ongoing:
      let response = it.response
      # tee ongoing streams
      let (stream, outputId) = buffer.loader.tee(response.outputId, myPid)
      # if -1, well, this side hasn't exhausted the socket's buffer
      doAssert outputId != -1 and stream != nil
      response.outputId = outputId
      response.body = stream
      let data = OngoingData(response: response, stream: stream)
      buffer.pollData.register(data.fd, POLLIN)
      buffer.loader.put(data)
    if buffer.istream != nil:
      # We do not own our input stream, so we can't tee it.
      # Luckily it is cached, so what we *can* do is to load the same thing from
      # the cache. (This also lets us skip suspend/resume in this case.)
      # We ignore errors; not much we can do with them here :/
      discard buffer.rewind(buffer.bytesRead, unregister = false)
    var sockFd: cint
    buffer.pstream.withPacketReader r:
      sockFd = r.recvAux.pop()
    buffer.pstream.sclose()
    ps.write(char(0))
    buffer.url = newurl
    for it in buffer.tasks.mitems:
      it = 0
    buffer.pstream = newSocketStream(sockFd)
    gpstream = buffer.pstream
    buffer.loader.clientPid = myPid
    # get key for new buffer
    buffer.loader.controlStream.sclose()
    buffer.pstream.withPacketReader r:
      buffer.loader.controlStream = newSocketStream(r.recvAux.pop())
    buffer.rfd = buffer.pstream.fd
    buffer.pollData.register(buffer.rfd, POLLIN)
    # must reconnect after the new client is set up, or the client pids get
    # mixed up.
    for it in connecting:
      # connecting: just reconnect
      buffer.loader.reconnect(it)
    # Set target now, because it's convenient.
    # (It is also possible that newurl has no hash, and then gotoAnchor
    # isn't called at all.)
    let target = buffer.document.findAnchor(newurl.hash)
    buffer.document.setTarget(target)
    return 0
  else: # parent
    discard close(pipefd[1]) # close write
    # We must wait for child to tee its ongoing streams.
    let ps = newPosixStream(pipefd[0])
    let c = ps.sreadChar()
    assert c == char(0)
    ps.sclose()
    buffer.loader.resume(ids)
    return pid

proc dispatchDOMContentLoadedEvent(buffer: Buffer) =
  let window = buffer.window
  let event = newEvent(window.toAtom(satDOMContentLoaded), buffer.document)
  discard window.jsctx.dispatch(buffer.document, event)
  buffer.maybeReshape()

proc dispatchLoadEvent(buffer: Buffer) =
  let window = buffer.window
  let event = newEvent(window.toAtom(satLoad), window)
  discard window.jsctx.dispatch(window, event)
  buffer.maybeReshape()

proc finishLoad(buffer: Buffer): EmptyPromise =
  if buffer.state != bsLoadingPage:
    let p = EmptyPromise()
    p.resolve()
    return p
  buffer.state = bsLoadingResources
  if buffer.ctx.td != nil and buffer.ctx.td.finish() == tdfrError:
    var s = "\uFFFD"
    doAssert buffer.processData0(UnsafeSlice(
      p: cast[ptr UncheckedArray[char]](addr s[0]),
      len: s.len
    ))
  buffer.htmlParser.finish()
  buffer.document.readyState = rsInteractive
  if buffer.config.scripting != smFalse:
    buffer.dispatchDOMContentLoadedEvent()
  buffer.pollData.unregister(buffer.fd)
  buffer.loader.unregistered.add(buffer.fd)
  buffer.loader.removeCachedItem(buffer.cacheId)
  buffer.cacheId = -1
  buffer.fd = -1
  buffer.outputId = -1
  buffer.istream.sclose()
  buffer.istream = nil
  return buffer.loadResources()

# Returns:
# * -1 if loading is done
# * a positive number for reporting the number of bytes loaded and that the page
#   has been partially rendered.
proc load*(buffer: Buffer): int {.proxy, task.} =
  if buffer.state == bsLoaded:
    return -1
  elif buffer.bytesRead > buffer.reportedBytesRead:
    buffer.maybeReshape()
    buffer.reportedBytesRead = buffer.bytesRead
    return buffer.bytesRead
  else:
    # will be resolved in onload
    buffer.savetask = true
    return -2 # unused

proc hasTask(buffer: Buffer; cmd: BufferCommand): bool =
  return buffer.tasks[cmd] != 0

proc resolveTask[T](buffer: Buffer; cmd: BufferCommand; res: T) =
  let packetid = buffer.tasks[cmd]
  assert packetid != 0
  buffer.pstream.withPacketWriter wt:
    wt.swrite(packetid)
    wt.swrite(res)
  buffer.tasks[cmd] = 0

proc onload(buffer: Buffer) =
  case buffer.state
  of bsLoadingResources, bsLoaded:
    if buffer.hasTask(bcLoad):
      buffer.resolveTask(bcLoad, -1)
    return
  of bsLoadingPage:
    discard
  var reprocess = false
  var iq {.noinit.}: array[BufferSize, uint8]
  var n = 0
  while true:
    if not reprocess:
      try:
        n = buffer.istream.recvData(iq)
      except ErrorAgain:
        break
      buffer.bytesRead += n
    if n != 0:
      if not buffer.processData(iq.toOpenArray(0, n - 1)):
        if not buffer.firstBufferRead:
          reprocess = true
          continue
        if buffer.rewind(0):
          continue
      buffer.firstBufferRead = true
      reprocess = false
    else: # EOF
      buffer.finishLoad().then(proc() =
        buffer.maybeReshape()
        buffer.state = bsLoaded
        buffer.document.readyState = rsComplete
        if buffer.config.scripting != smFalse:
          buffer.dispatchLoadEvent()
          for ctx in buffer.window.pendingCanvasCtls:
            ctx.ps.sclose()
            ctx.ps = nil
          buffer.window.pendingCanvasCtls.setLen(0)
        if buffer.hasTask(bcGetTitle):
          buffer.resolveTask(bcGetTitle, buffer.document.title)
        if buffer.hasTask(bcLoad):
          buffer.resolveTask(bcLoad, -1)
      )
      return # skip incr render
  # incremental rendering: only if we cannot read the entire stream in one
  # pass
  if not buffer.config.isdump and buffer.tasks[bcLoad] != 0:
    # only makes sense when not in dump mode (and the user has requested a load)
    buffer.maybeReshape()
    buffer.reportedBytesRead = buffer.bytesRead
    if buffer.hasTask(bcGetTitle):
      buffer.resolveTask(bcGetTitle, buffer.document.title)
    if buffer.hasTask(bcLoad):
      buffer.resolveTask(bcLoad, buffer.bytesRead)

proc getTitle*(buffer: Buffer): string {.proxy, task.} =
  if buffer.document != nil:
    let title = buffer.document.findFirst(TAG_TITLE)
    if title != nil:
      return title.childTextContent.stripAndCollapse()
    if buffer.state == bsLoaded:
      return "" # title no longer expected
  buffer.savetask = true
  return ""

proc forceReshape0(buffer: Buffer) =
  if buffer.document != nil:
    buffer.document.invalid = true
  buffer.needsReshape = true
  buffer.maybeReshape()

proc forceReshape2(buffer: Buffer) =
  buffer.prevStyled = nil
  buffer.forceReshape0()

proc forceReshape*(buffer: Buffer) {.proxy.} =
  buffer.forceReshape2()

proc windowChange*(buffer: Buffer; attrs: WindowAttributes) {.proxy.} =
  buffer.attrs = attrs
  buffer.forceReshape2()

proc cancel*(buffer: Buffer) {.proxy.} =
  if buffer.state == bsLoaded:
    return
  for it in buffer.loader.data:
    let fd = it.fd
    buffer.pollData.unregister(fd)
    buffer.loader.unregistered.add(fd)
    it.stream.sclose()
    buffer.loader.unset(it)
  if buffer.istream != nil:
    buffer.pollData.unregister(buffer.fd)
    buffer.loader.unregistered.add(buffer.fd)
    buffer.loader.removeCachedItem(buffer.cacheId)
    buffer.fd = -1
    buffer.cacheId = -1
    buffer.outputId = -1
    buffer.istream.sclose()
    buffer.istream = nil
    buffer.htmlParser.finish()
  buffer.document.readyState = rsInteractive
  buffer.state = bsLoaded
  buffer.maybeReshape()

#https://html.spec.whatwg.org/multipage/form-control-infrastructure.html#multipart/form-data-encoding-algorithm
proc serializeMultipart(entries: seq[FormDataEntry]; urandom: PosixStream):
    FormData =
  let formData = newFormData0(entries, urandom)
  for entry in formData.entries.mitems:
    entry.name = makeCRLF(entry.name)
  return formData

proc serializePlainTextFormData(kvs: seq[(string, string)]): string =
  result = ""
  for it in kvs:
    let (name, value) = it
    result &= name
    result &= '='
    result &= value
    result &= "\r\n"

func getOutputEncoding(charset: Charset): Charset =
  if charset in {CHARSET_REPLACEMENT, CHARSET_UTF_16_BE, CHARSET_UTF_16_LE}:
    return CHARSET_UTF_8
  return charset

func pickCharset(form: HTMLFormElement): Charset =
  if form.attrb(satAcceptCharset):
    let input = form.attr(satAcceptCharset)
    for label in input.split(AsciiWhitespace):
      let charset = label.getCharset()
      if charset != CHARSET_UNKNOWN:
        return charset.getOutputEncoding()
    return CHARSET_UTF_8
  return form.document.charset.getOutputEncoding()

proc getFormRequestType(buffer: Buffer; scheme: string): FormRequestType =
  buffer.config.protocol.withValue(scheme, p):
    return p[].formRequest
  return frtHttp

proc makeFormRequest(buffer: Buffer; parsedAction: URL; httpMethod: HttpMethod;
    entryList: seq[FormDataEntry]; enctype: FormEncodingType): Request =
  assert httpMethod in {hmGet, hmPost}
  case buffer.getFormRequestType(parsedAction.scheme)
  of frtFtp:
    return newRequest(parsedAction) # get action URL
  of frtData:
    if httpMethod == hmGet:
      # mutate action URL
      let kvlist = entryList.toNameValuePairs()
      #TODO with charset
      parsedAction.setSearch('?' & serializeFormURLEncoded(kvlist))
      return newRequest(parsedAction, httpMethod)
    return newRequest(parsedAction) # get action URL
  of frtMailto:
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
  of frtHttp:
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
      let multipart = serializeMultipart(entryList, buffer.window.urandom)
      RequestBody(t: rbtMultipart, multipart: multipart)
    of fetTextPlain:
      #TODO with charset
      let kvlist = entryList.toNameValuePairs()
      RequestBody(t: rbtString, s: serializePlainTextFormData(kvlist))
    let headers = newHeaders({"Content-Type": $enctype})
    return newRequest(parsedAction, httpMethod, headers, body)

# https://html.spec.whatwg.org/multipage/form-control-infrastructure.html#form-submission-algorithm
proc submitForm(buffer: Buffer; form: HTMLFormElement; submitter: Element): Request =
  if form.constructingEntryList:
    return nil
  #TODO submit()
  let charset = form.pickCharset()
  discard charset #TODO pass to constructEntryList
  let entryList = form.constructEntryList(submitter)
  let subAction = submitter.action()
  let action = if subAction != "":
    subAction
  else:
    $form.document.url
  #TODO encoding-parse
  let url = submitter.document.parseURL(action)
  if url.isNone:
    return nil
  let parsedAction = url.get
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
  return buffer.makeFormRequest(parsedAction, httpMethod, entryList, enctype)

proc setFocus(buffer: Buffer; e: Element): bool =
  buffer.document.setFocus(e)
  return buffer.maybeReshape()

proc restoreFocus(buffer: Buffer): bool =
  buffer.document.setFocus(nil)
  return buffer.maybeReshape()

type ReadSuccessResult* = object
  open*: Request
  repaint*: bool

proc implicitSubmit(buffer: Buffer; input: HTMLInputElement): Request =
  let form = input.form
  if form != nil and form.canSubmitImplicitly():
    var defaultButton: Element
    for element in form.elements:
      if element.isSubmitButton():
        defaultButton = element
        break
    if defaultButton != nil:
      return buffer.submitForm(form, defaultButton)
    else:
      return buffer.submitForm(form, form)
  return nil

proc readSuccess*(buffer: Buffer; s: string; hasFd: bool): ReadSuccessResult
    {.proxy.} =
  var fd: cint = -1
  var res = ReadSuccessResult()
  if hasFd:
    buffer.pstream.withPacketReader r:
      fd = r.recvAux.pop()
  if buffer.document.focus != nil:
    case buffer.document.focus.tagType
    of TAG_INPUT:
      let input = HTMLInputElement(buffer.document.focus)
      case input.inputType
      of itFile:
        input.file = newWebFile(s, fd)
        input.setInvalid()
        buffer.maybeReshape()
        res.repaint = true
        res.open = buffer.implicitSubmit(input)
      else:
        input.value = s
        input.setInvalid()
        buffer.maybeReshape()
        res.repaint = true
        res.open = buffer.implicitSubmit(input)
    of TAG_TEXTAREA:
      let textarea = HTMLTextAreaElement(buffer.document.focus)
      textarea.value = s
      textarea.setInvalid()
      buffer.maybeReshape()
      res.repaint = true
    else: discard
    let r = buffer.restoreFocus()
    if not res.repaint:
      res.repaint = r
  return res

proc click(buffer: Buffer; label: HTMLLabelElement): ClickResult =
  let control = label.control
  if control != nil:
    return buffer.click(control)
  return ClickResult()

proc click(buffer: Buffer; select: HTMLSelectElement): ClickResult =
  if select.attrb(satMultiple):
    return ClickResult()
  let repaint = buffer.setFocus(select)
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
    repaint: repaint,
    select: some(SelectResult(options: move(options), selected: selected))
  )

proc baseURL(buffer: Buffer): URL =
  return buffer.document.baseURL

proc evalJSURL(buffer: Buffer; url: URL): Opt[string] =
  let surl = '<' & $url & '>'
  let source = surl.toOpenArray("javascript:".len, surl.high).percentDecode()
  let ctx = buffer.window.jsctx
  let ret = ctx.eval(source, $buffer.baseURL, JS_EVAL_TYPE_GLOBAL)
  if JS_IsException(ret):
    ctx.writeException(buffer.estream)
    return err() # error
  if JS_IsUndefined(ret):
    return err() # no need to navigate
  var res: string
  ?ctx.fromJS(ret, res)
  JS_FreeValue(ctx, ret)
  # Navigate to result.
  return ok(res)

proc click(buffer: Buffer; anchor: HTMLAnchorElement): ClickResult =
  var repaint = buffer.restoreFocus()
  let url = anchor.reinitURL()
  if url.isSome:
    var url = url.get
    if url.scheme == "javascript":
      if buffer.config.scripting == smFalse:
        return ClickResult(repaint: repaint)
      let s = buffer.evalJSURL(url)
      if buffer.maybeReshape():
        repaint = true
      if s.isNone:
        return ClickResult(repaint: repaint)
      let urls = newURL("data:text/html," & s.get)
      if urls.isNone:
        return ClickResult(repaint: repaint)
      url = urls.get
    return ClickResult(repaint: repaint, open: newRequest(url, hmGet))
  return ClickResult(repaint: repaint)

proc click(buffer: Buffer; option: HTMLOptionElement): ClickResult =
  let select = option.select
  if select != nil:
    if select.attrb(satMultiple):
      option.setSelected(not option.selected)
      return ClickResult(repaint: buffer.maybeReshape())
    return buffer.click(select)
  return ClickResult()

proc click(buffer: Buffer; button: HTMLButtonElement): ClickResult =
  if button.form != nil:
    var open: Request = nil
    case button.ctype
    of btSubmit:
      open = buffer.submitForm(button.form, button)
    of btReset:
      button.form.reset()
      return ClickResult(repaint: buffer.maybeReshape())
    of btButton: discard
    let repaint = buffer.setFocus(button)
    return ClickResult(open: open, repaint: repaint)
  return ClickResult()

proc click(buffer: Buffer; textarea: HTMLTextAreaElement): ClickResult =
  let repaint = buffer.setFocus(textarea)
  let readline = ReadLineResult(
    t: rltArea,
    value: textarea.value
  )
  return ClickResult(
    readline: some(readline),
    repaint: repaint
  )

proc click(buffer: Buffer; audio: HTMLAudioElement): ClickResult =
  let repaint = buffer.restoreFocus()
  let (src, contentType) = audio.getSrc()
  if src != "":
    let url = audio.document.parseURL(src)
    if url.isSome:
      return ClickResult(
        repaint: repaint,
        open: newRequest(url.get),
        contentType: contentType
      )
  return ClickResult(repaint: repaint)

proc click(buffer: Buffer; video: HTMLVideoElement): ClickResult =
  let repaint = buffer.restoreFocus()
  let (src, contentType) = video.getSrc()
  if src != "":
    let url = video.document.parseURL(src)
    if url.isSome:
      return ClickResult(
        repaint: repaint,
        open: newRequest(url.get),
        contentType: contentType
      )
  return ClickResult(repaint: repaint)

proc click(buffer: Buffer; iframe: HTMLIFrameElement): ClickResult =
  let repaint = buffer.restoreFocus()
  let src = iframe.attr(satSrc)
  if src != "":
    let url = iframe.document.parseURL(src)
    if url.isSome:
      return ClickResult(repaint: repaint, open: newRequest(url.get))
  return ClickResult(repaint: repaint)

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

proc click(buffer: Buffer; input: HTMLInputElement): ClickResult =
  let repaint = buffer.restoreFocus()
  case input.inputType
  of itFile:
    #TODO we should somehow extract the path name from the current file
    return ClickResult(
      repaint: buffer.setFocus(input) or repaint,
      readline: some(ReadLineResult(t: rltFile))
    )
  of itCheckbox:
    input.setChecked(not input.checked)
    return ClickResult(repaint: buffer.maybeReshape())
  of itRadio:
    input.setChecked(true)
    return ClickResult(repaint: buffer.maybeReshape())
  of itReset:
    if input.form != nil:
      input.form.reset()
      return ClickResult(repaint: buffer.maybeReshape())
    return ClickResult(repaint: false)
  of itSubmit, itButton:
    if input.form != nil:
      return ClickResult(
        open: buffer.submitForm(input.form, input),
        repaint: repaint
      )
    return ClickResult(repaint: false)
  else:
    # default is text.
    var prompt = InputTypePrompt[input.inputType]
    if input.inputType == itRange:
      prompt &= " (" & input.attr(satMin) & ".." & input.attr(satMax) & ")"
    return ClickResult(
      repaint: buffer.setFocus(input) or repaint,
      readline: some(ReadLineResult(
        prompt: prompt & ": ",
        value: input.value,
        hide: input.inputType == itPassword
      ))
    )

proc click(buffer: Buffer; clickable: Element): ClickResult =
  case clickable.tagType
  of TAG_LABEL:
    return buffer.click(HTMLLabelElement(clickable))
  of TAG_SELECT:
    return buffer.click(HTMLSelectElement(clickable))
  of TAG_A:
    return buffer.click(HTMLAnchorElement(clickable))
  of TAG_OPTION:
    return buffer.click(HTMLOptionElement(clickable))
  of TAG_BUTTON:
    return buffer.click(HTMLButtonElement(clickable))
  of TAG_TEXTAREA:
    return buffer.click(HTMLTextAreaElement(clickable))
  of TAG_INPUT:
    return buffer.click(HTMLInputElement(clickable))
  of TAG_AUDIO:
    return buffer.click(HTMLAudioElement(clickable))
  of TAG_VIDEO:
    return buffer.click(HTMLVideoElement(clickable))
  of TAG_IFRAME:
    return buffer.click(HTMLIFrameElement(clickable))
  else:
    return ClickResult(repaint: buffer.restoreFocus())

proc click*(buffer: Buffer; cursorx, cursory: int): ClickResult {.proxy.} =
  if buffer.lines.len <= cursory: return ClickResult()
  var repaint = false
  var canceled = false
  let clickable = buffer.getCursorClickable(cursorx, cursory)
  if buffer.config.scripting != smFalse:
    let element = buffer.getCursorElement(cursorx, cursory)
    if element != nil:
      let window = buffer.window
      let event = newEvent(window.toAtom(satClick), element)
      canceled = window.jsctx.dispatch(element, event)
      if buffer.maybeReshape():
        repaint = true
  if not canceled:
    if clickable != nil:
      var res = buffer.click(clickable)
      if repaint: # override
        res.repaint = true
      return res
  return ClickResult(repaint: repaint)

proc select*(buffer: Buffer; selected: int): ClickResult {.proxy.} =
  if buffer.document.focus != nil and
      buffer.document.focus of HTMLSelectElement:
    let select = HTMLSelectElement(buffer.document.focus)
    select.setSelectedIndex(selected)
    return ClickResult(repaint: buffer.restoreFocus())
  return ClickResult()

proc readCanceled*(buffer: Buffer): bool {.proxy.} =
  return buffer.restoreFocus()

type GetLinesResult* = tuple
  numLines: int
  lines: seq[SimpleFlexibleLine]
  bgcolor: CellColor
  images: seq[PosBitmap]

proc getLines*(buffer: Buffer; w: Slice[int]): GetLinesResult {.proxy.} =
  var w = w
  if w.b < 0 or w.b > buffer.lines.high:
    w.b = buffer.lines.high
  #TODO this is horribly inefficient
  for y in w:
    var line = SimpleFlexibleLine(str: buffer.lines[y].str)
    for f in buffer.lines[y].formats:
      line.formats.add(SimpleFormatCell(format: f.format, pos: f.pos))
    result.lines.add(line)
  result.numLines = buffer.lines.len
  result.bgcolor = buffer.bgcolor
  if buffer.config.images:
    let ppl = buffer.attrs.ppl
    for image in buffer.images:
      let ey = image.y + (image.height + ppl - 1) div ppl # ceil
      if image.y <= w.b and ey >= w.a:
        result.images.add(image)

proc markURL*(buffer: Buffer; schemes: seq[string]) {.proxy.} =
  if buffer.document == nil or buffer.document.body == nil:
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
  let html = buffer.document.newHTMLElement(TAG_DIV)
  var stack = @[buffer.document.body]
  while stack.len > 0:
    let element = stack.pop()
    var toRemove: seq[Node] = @[]
    var texts: seq[Text] = @[]
    var stackNext: seq[HTMLElement] = @[]
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
  buffer.forceReshape0()

proc toggleImages0(buffer: Buffer): bool =
  buffer.config.images = not buffer.config.images
  buffer.window.images = buffer.config.images
  buffer.window.svgCache.clear()
  for element in buffer.document.descendants:
    if element of HTMLImageElement:
      buffer.window.loadResource(HTMLImageElement(element))
    elif element of SVGSVGElement:
      buffer.window.loadResource(SVGSVGElement(element))
  buffer.savetask = true
  buffer.loadResources().then(proc() =
    if buffer.tasks[bcToggleImages] == 0:
      # we resolved in then
      buffer.savetask = false
    else:
      buffer.resolveTask(bcToggleImages, buffer.config.images)
    buffer.forceReshape2()
  )
  return buffer.config.images

proc toggleImages*(buffer: Buffer): bool {.proxy, task.} =
  buffer.toggleImages0()

macro bufferDispatcher(funs: static ProxyMap; buffer: Buffer;
    cmd: BufferCommand; packetid: int; r: var BufferedReader) =
  let switch = newNimNode(nnkCaseStmt)
  switch.add(ident("cmd"))
  for k, v in funs:
    let ofbranch = newNimNode(nnkOfBranch)
    ofbranch.add(v.ename)
    let stmts = newStmtList()
    let call = newCall(v.iname, buffer)
    for i in 2 ..< v.params.len:
      let param = v.params[i]
      for i in 0 ..< param.len - 2:
        let id = ident(param[i].strVal)
        let typ = param[^2]
        stmts.add(quote do:
          var `id`: `typ`
          `r`.sread(`id`)
        )
        call.add(id)
    var rval: NimNode
    if v.params[0].kind == nnkEmpty:
      stmts.add(call)
    else:
      rval = ident("retval")
      stmts.add(quote do:
        let `rval` = `call`)
    var resolve = newStmtList()
    if rval == nil:
      resolve.add(quote do:
        buffer.pstream.withPacketWriter wt:
          wt.swrite(`packetid`)
      )
    else:
      resolve.add(quote do:
        buffer.pstream.withPacketWriter wt:
          wt.swrite(`packetid`)
          wt.swrite(`rval`)
      )
    if v.istask:
      let en = v.ename
      stmts.add(quote do:
        if buffer.savetask:
          buffer.savetask = false
          buffer.tasks[BufferCommand.`en`] = `packetid`
        else:
          `resolve`
      )
    else:
      stmts.add(resolve)
    ofbranch.add(stmts)
    switch.add(ofbranch)
  return switch

proc readCommand(buffer: Buffer) =
  buffer.pstream.withPacketReader r:
    var cmd: BufferCommand
    var packetid: int
    r.sread(cmd)
    r.sread(packetid)
    bufferDispatcher(ProxyFunctions, buffer, cmd, packetid, r)

proc handleRead(buffer: Buffer; fd: int): bool =
  if fd == buffer.rfd:
    try:
      buffer.readCommand()
    except ErrorConnectionReset, EOFError:
      #eprint "EOF error", $buffer.url & "\nMESSAGE:",
      #       getCurrentExceptionMsg() & "\n",
      #       getStackTrace(getCurrentException())
      return false
  elif fd == buffer.fd:
    buffer.onload()
  elif buffer.loader.get(fd) != nil:
    buffer.loader.onRead(fd)
    if buffer.config.scripting != smFalse:
      buffer.window.runJSJobs()
  elif fd in buffer.loader.unregistered:
    discard # ignore
  else:
    assert false
  true

proc handleError(buffer: Buffer; fd: int; event: TPollfd): bool =
  if fd == buffer.rfd:
    # Connection reset by peer, probably. Close the buffer.
    return false
  elif fd == buffer.fd:
    buffer.onload()
  elif buffer.loader.get(fd) != nil:
    if not buffer.loader.onError(fd):
      #TODO handle connection error
      assert false, $fd
    if buffer.config.scripting != smFalse:
      buffer.window.runJSJobs()
  elif fd in buffer.loader.unregistered:
    discard # ignore
  else:
    assert false, $fd
  true

proc getPollTimeout(buffer: Buffer): cint =
  if buffer.config.scripting != smFalse:
    return buffer.window.timeouts.sortAndGetTimeout()
  return -1

proc runBuffer(buffer: Buffer) =
  var alive = true
  while alive:
    let timeout = buffer.getPollTimeout()
    buffer.pollData.poll(timeout)
    buffer.loader.blockRegister()
    for event in buffer.pollData.events:
      if (event.revents and POLLIN) != 0:
        if not buffer.handleRead(event.fd):
          alive = false
          break
      if (event.revents and POLLERR) != 0 or (event.revents and POLLHUP) != 0:
        if not buffer.handleError(event.fd, event):
          alive = false
          break
    buffer.loader.unregistered.setLen(0)
    buffer.loader.unblockRegister()
    if buffer.config.scripting != smFalse:
      if buffer.window.timeouts.run(buffer.estream):
        buffer.window.runJSJobs()
        buffer.maybeReshape()

proc cleanup(buffer: Buffer) =
  if gpstream != nil:
    gpstream.sclose()
    gpstream = nil
  buffer.window.urandom.sclose()

proc launchBuffer*(config: BufferConfig; url: URL; attrs: WindowAttributes;
    ishtml: bool; charsetStack: seq[Charset]; loader: FileLoader;
    pstream: SocketStream; istream, urandom: PosixStream; cacheId: int) =
  let factory = newCAtomFactory()
  let confidence = if config.charsetOverride == CHARSET_UNKNOWN:
    ccTentative
  else:
    ccCertain
  let buffer = Buffer(
    attrs: attrs,
    config: config,
    estream: newDynFileStream(stderr),
    ishtml: ishtml,
    loader: loader,
    needsBOMSniff: config.charsetOverride == CHARSET_UNKNOWN,
    pstream: pstream,
    rfd: pstream.fd,
    url: url,
    charsetStack: charsetStack,
    cacheId: -1,
    outputId: -1,
    factory: factory
  )
  buffer.window = newWindow(
    config.scripting,
    config.images,
    config.styling,
    config.autofocus,
    addr buffer.attrs,
    factory,
    loader,
    url,
    urandom,
    config.imageTypes,
    config.userAgent,
    config.referrer
  )
  if buffer.config.scripting != smFalse:
    buffer.window.navigate = proc(url: URL) = buffer.navigate(url)
    if buffer.config.scripting == smApp:
      buffer.window.maybeRestyle = proc() = buffer.maybeRestyle()
  buffer.charset = buffer.charsetStack.pop()
  buffer.fd = istream.fd
  buffer.istream = istream
  buffer.istream.setBlocking(false)
  buffer.pollData.register(istream.fd, POLLIN)
  loader.registerFun = proc(fd: int) =
    buffer.pollData.register(fd, POLLIN)
  loader.unregisterFun = proc(fd: int) =
    buffer.pollData.unregister(fd)
  buffer.pollData.register(buffer.rfd, POLLIN)
  const css = staticRead"res/ua.css"
  const quirk = css & staticRead"res/quirk.css"
  buffer.initDecoder()
  let attrsp = addr buffer.attrs
  buffer.uastyle = css.parseStylesheet(factory, nil, attrsp)
  buffer.quirkstyle = quirk.parseStylesheet(factory, nil, attrsp)
  buffer.userstyle = buffer.config.userstyle.parseStylesheet(factory, nil,
    attrsp)
  buffer.htmlParser = newHTML5ParserWrapper(
    buffer.window,
    buffer.url,
    buffer.factory,
    confidence,
    buffer.charset
  )
  assert buffer.htmlParser.builder.document != nil
  buffer.document = buffer.htmlParser.builder.document
  buffer.runBuffer()
  buffer.cleanup()
  quit(0)
