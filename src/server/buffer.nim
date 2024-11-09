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
import css/cascade
import css/cssparser
import css/cssvalues
import css/sheet
import css/stylednode
import html/catom
import html/chadombuilder
import html/dom
import html/enums
import html/env
import html/event
import html/formdata as formdata_impl
import io/bufreader
import io/bufwriter
import io/dynstream
import io/poll
import io/promise
import js/console
import js/timeout
import layout/renderdocument
import loader/headers
import loader/loaderiface
import loader/request
import monoucha/fromjs
import monoucha/javascript
import monoucha/jsregex
import monoucha/libregexp
import monoucha/quickjs
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
    bcLoad, bcForceRender, bcWindowChange, bcFindAnchor, bcReadSuccess,
    bcReadCanceled, bcClick, bcFindNextLink, bcFindPrevLink, bcFindNthLink,
    bcFindRevNthLink, bcFindNextMatch, bcFindPrevMatch, bcGetLines,
    bcUpdateHover, bcGotoAnchor, bcCancel, bcGetTitle, bcSelect, bcClone,
    bcFindPrevParagraph, bcFindNextParagraph, bcMarkURL, bcToggleImages,
    bcCheckRefresh

  BufferState = enum
    bsLoadingPage, bsLoadingResources, bsLoaded

  HoverType* = enum
    htTitle = "TITLE"
    htLink = "URL"
    htImage = "IMAGE"

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
    outputId: int
    pollData: PollData
    prevStyled: StyledNode
    prevnode: StyledNode
    pstream: SocketStream # control stream
    quirkstyle: CSSStylesheet
    reportedBytesRead: int
    rfd: int # file descriptor of command pipe
    savetask: bool
    ssock: ServerSocket
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
    scripting*: bool
    images*: bool
    isdump*: bool
    charsets*: seq[Charset]
    charsetOverride*: Charset
    protocol*: Table[string, ProtocolConfig]
    autofocus*: bool
    metaRefresh*: MetaRefresh

  GetValueProc = proc(iface: BufferInterface; promise: EmptyPromise) {.nimcall.}

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

proc newBufferInterface*(stream: SocketStream; registerFun: proc(fd: int)):
    BufferInterface =
  return BufferInterface(
    packetid: 1, # ids below 1 are invalid
    stream: newBufStream(stream, registerFun)
  )

# After cloning a buffer, we need a new interface to the new buffer process.
# Here we create a new interface for that clone.
proc cloneInterface*(stream: SocketStream; registerFun: proc(fd: int)):
    BufferInterface =
  let iface = newBufferInterface(stream, registerFun)
  #TODO buffered data should probably be copied here
  # We have just fork'ed the buffer process inside an interface function,
  # from which the new buffer is going to return as well. So we must also
  # consume the return value of the clone function, which is the pid 0.
  var pid: int
  var r = stream.initPacketReader()
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
  var params2: seq[NimNode]
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

func getTitleAttr(buffer: Buffer; node: StyledNode): string =
  if node == nil:
    return ""
  if node.t == stElement and node.node != nil:
    let element = Element(node.node)
    if element.attrb(satTitle):
      return element.attr(satTitle)
  if node.node != nil:
    var node = node.node
    for element in node.ancestors:
      if element.attrb(satTitle):
        return element.attr(satTitle)
  #TODO pseudo-elements
  return ""

const ClickableElements = {
  TAG_A, TAG_INPUT, TAG_OPTION, TAG_BUTTON, TAG_TEXTAREA, TAG_LABEL
}

proc isClickable(styledNode: StyledNode): bool =
  if styledNode.t != stElement or styledNode.node == nil:
    return false
  if styledNode.computed{"visibility"} != VisibilityVisible:
    return false
  let element = Element(styledNode.node)
  if element of HTMLAnchorElement:
    return HTMLAnchorElement(element).reinitURL().isSome
  if element.isButton() and FormAssociatedElement(element).form == nil:
    return false
  return element.tagType in ClickableElements

proc getClickable(styledNode: StyledNode): Element =
  var styledNode = styledNode
  while styledNode != nil:
    if styledNode.isClickable():
      return Element(styledNode.node)
    styledNode = styledNode.parent
  return nil

proc submitForm(buffer: Buffer; form: HTMLFormElement; submitter: Element):
  Request

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

proc getClickHover(buffer: Buffer; styledNode: StyledNode): string =
  let clickable = styledNode.getClickable()
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
  ""

proc getImageHover(buffer: Buffer; styledNode: StyledNode): string =
  var styledNode = styledNode
  while styledNode != nil:
    if styledNode.t == stElement:
      if styledNode.node of HTMLImageElement:
        let image = HTMLImageElement(styledNode.node)
        let src = image.attr(satSrc)
        if src != "":
          let url = image.document.parseURL(src)
          if url.isSome:
            return $url.get
      elif styledNode.node of HTMLVideoElement:
        let video = HTMLVideoElement(styledNode.node)
        let src = video.getSrc()
        if src != "":
          let url = video.document.parseURL(src)
          if url.isSome:
            return $url.get
      elif styledNode.node of HTMLAudioElement:
        let audio = HTMLAudioElement(styledNode.node)
        let src = audio.getSrc()
        if src != "":
          let url = audio.document.parseURL(src)
          if url.isSome:
            return $url.get
    styledNode = styledNode.parent
  ""

func getCursorStyledNode(buffer: Buffer; cursorx, cursory: int): StyledNode =
  let i = buffer.lines[cursory].findFormatN(cursorx) - 1
  if i >= 0:
    return buffer.lines[cursory].formats[i].node
  nil

func getCursorElement(buffer: Buffer; cursorx, cursory: int): Element =
  let styledNode = buffer.getCursorStyledNode(cursorx, cursory)
  if styledNode == nil:
    return nil
  if styledNode.node != nil:
    if styledNode.t == stElement:
      return Element(styledNode.node)
    return styledNode.node.parentElement
  if styledNode.parent != nil and styledNode.parent.t == stElement:
    return Element(styledNode.parent.node)
  return nil

proc getCursorClickable(buffer: Buffer; cursorx, cursory: int): Element =
  let styledNode = buffer.getCursorStyledNode(cursorx, cursory)
  if styledNode != nil:
    return styledNode.getClickable()
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
  stderr.write("navigate to " & $url & "\n")

proc findPrevLink*(buffer: Buffer; cursorx, cursory, n: int):
    tuple[x, y: int] {.proxy.} =
  if cursory >= buffer.lines.len: return (-1, -1)
  var found = 0
  let line = buffer.lines[cursory]
  var i = line.findFormatN(cursorx) - 1
  var link: Element = nil
  if i >= 0:
    link = line.formats[i].node.getClickable()
  dec i

  var ly = 0 #last y
  var lx = 0 #last x
  template link_beginning() =
    #go to beginning of link
    ly = y #last y
    lx = format.pos #last x

    #on the current line
    let line = buffer.lines[y]
    while i >= 0:
      let format = line.formats[i]
      let nl = format.node.getClickable()
      if nl == fl:
        lx = format.pos
      dec i

    #on previous lines
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
        # Assume multiline anchors are always placed on consecutive lines.
        # This is not true, but otherwise we would have to loop through
        # the entire document, which would be rather inefficient. TODO: find
        # an efficient and correct way to do this.
        break

  template found_pos(x, y: int; fl: Element) =
    inc found
    link = fl
    if found == n:
      return (x, y)

  while i >= 0:
    let format = line.formats[i]
    let fl = format.node.getClickable()
    if fl != nil and fl != link:
      let y = cursory
      link_beginning
      found_pos lx, ly, fl
    dec i

  for y in countdown(cursory - 1, 0):
    let line = buffer.lines[y]
    i = line.formats.len - 1
    while i >= 0:
      let format = line.formats[i]
      let fl = format.node.getClickable()
      if fl != nil and fl != link:
        link_beginning
        found_pos lx, ly, fl
      dec i
  return (-1, -1)

proc findNextLink*(buffer: Buffer; cursorx, cursory, n: int):
    tuple[x, y: int] {.proxy.} =
  if cursory >= buffer.lines.len: return (-1, -1)
  let line = buffer.lines[cursory]
  var i = line.findFormatN(cursorx) - 1
  var link: Element = nil
  if i >= 0:
    link = line.formats[i].node.getClickable()
  inc i

  var found = 0
  template found_pos(x, y: int; fl: Element) =
    inc found
    link = fl
    if found == n:
      return (x, y)

  while i < line.formats.len:
    let format = line.formats[i]
    let fl = format.node.getClickable()
    if fl != nil and fl != link:
      found_pos format.pos, cursory, fl
    inc i

  for y in cursory + 1 .. buffer.lines.len - 1:
    let line = buffer.lines[y]
    for i in 0 ..< line.formats.len:
      let format = line.formats[i]
      let fl = format.node.getClickable()
      if fl != nil and fl != link:
        found_pos format.pos, y, fl
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

  SelectResult* = object
    multiple*: bool
    options*: seq[string]
    selected*: seq[int]

  ClickResult* = object
    open*: Request
    readline*: Option[ReadLineResult]
    repaint*: bool
    select*: Option[SelectResult]

proc click(buffer: Buffer; clickable: Element): ClickResult

type GotoAnchorResult* = object
  found*: bool
  x*: int
  y*: int
  focus*: ReadLineResult

proc gotoAnchor*(buffer: Buffer): GotoAnchorResult {.proxy.} =
  if buffer.document == nil:
    return GotoAnchorResult(found: false)
  var anchor = buffer.document.findAnchor(buffer.url.anchor)
  var focus: ReadLineResult = nil
  if buffer.config.autofocus:
    let autofocus = buffer.document.findAutoFocus()
    if autofocus != nil:
      if anchor == nil:
        anchor = autofocus # jump to autofocus instead
      let res = buffer.click(autofocus)
      focus = res.readline.get(nil)
  if anchor == nil:
    return GotoAnchorResult(found: false)
  for y in 0 ..< buffer.lines.len:
    let line = buffer.lines[y]
    for i in 0 ..< line.formats.len:
      let format = line.formats[i]
      if format.node != nil and format.node.node in anchor:
        return GotoAnchorResult(
          found: true,
          x: format.pos,
          y: y,
          focus: focus
        )
  return GotoAnchorResult(found: false)

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

proc reshape(buffer: Buffer) =
  if buffer.document == nil:
    return # not parsed yet, nothing to render
  let uastyle = if buffer.document.mode != QUIRKS:
    buffer.uastyle
  else:
    buffer.quirkstyle
  if buffer.document.cachedSheetsInvalid:
    buffer.prevStyled = nil
  let styledRoot = buffer.document.applyStylesheets(uastyle,
    buffer.userstyle, buffer.prevStyled)
  buffer.lines.renderDocument(buffer.bgcolor, styledRoot, addr buffer.attrs,
    buffer.images)
  buffer.prevStyled = styledRoot

proc maybeReshape(buffer: Buffer) =
  if buffer.document != nil and buffer.document.invalid:
    buffer.reshape()
    buffer.document.invalid = false

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

proc windowChange*(buffer: Buffer; attrs: WindowAttributes) {.proxy.} =
  buffer.attrs = attrs
  buffer.prevStyled = nil
  buffer.window.attrs = attrs
  buffer.reshape()

type UpdateHoverResult* = object
  hover*: seq[tuple[t: HoverType, s: string]]
  repaint*: bool

const HoverFun = [
  htTitle: getTitleAttr,
  htLink: getClickHover,
  htImage: getImageHover
]
proc updateHover*(buffer: Buffer; cursorx, cursory: int): UpdateHoverResult
    {.proxy.} =
  if cursory >= buffer.lines.len:
    return UpdateHoverResult()
  var thisnode: StyledNode = nil
  let i = buffer.lines[cursory].findFormatN(cursorx) - 1
  if i >= 0:
    thisnode = buffer.lines[cursory].formats[i].node
  var hover: seq[tuple[t: HoverType, s: string]] = @[]
  var repaint = false
  let prevnode = buffer.prevnode
  if thisnode != prevnode and (thisnode == nil or prevnode == nil or
      thisnode.node != prevnode.node):
    for styledNode in prevnode.branch:
      if styledNode.t == stElement and styledNode.node != nil:
        let elem = Element(styledNode.node)
        if elem.hover:
          elem.setHover(false)
          repaint = true
    for ht in HoverType:
      let s = HoverFun[ht](buffer, thisnode)
      if buffer.hoverText[ht] != s:
        hover.add((ht, s))
        buffer.hoverText[ht] = s
    for styledNode in thisnode.branch:
      if styledNode.t == stElement and styledNode.node != nil:
        let elem = Element(styledNode.node)
        if not elem.hover:
          elem.setHover(true)
          repaint = true
  if repaint:
    buffer.reshape()
  buffer.prevnode = thisnode
  return UpdateHoverResult(repaint: repaint, hover: hover)

proc loadResources(buffer: Buffer): EmptyPromise =
  return buffer.window.loadingResourcePromises.all()

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

var gssock* {.global.}: ServerSocket
var gpstream* {.global.}: SocketStream

# Create an exact clone of the current buffer.
# This clone will share the loader process with the previous buffer.
proc clone*(buffer: Buffer; newurl: URL): int {.proxy.} =
  var pipefd: array[2, cint]
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
    let sockFd = buffer.pstream.recvFd()
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
    buffer.pstream.sclose()
    buffer.ssock.close(unlink = false)
    let ssock = newServerSocket(sockFd, buffer.loader.sockDir,
      buffer.loader.sockDirFd, myPid)
    buffer.ssock = ssock
    gssock = ssock
    ps.write(char(0))
    buffer.url = newurl
    for it in buffer.tasks.mitems:
      it = 0
    buffer.pstream = ssock.acceptSocketStream()
    gpstream = buffer.pstream
    buffer.loader.clientPid = myPid
    # get key for new buffer
    var r = buffer.pstream.initPacketReader()
    r.sread(buffer.loader.key)
    buffer.rfd = buffer.pstream.fd
    buffer.pollData.register(buffer.rfd, POLLIN)
    # must reconnect after the new client is set up, or the client pids get
    # mixed up.
    for it in connecting:
      # connecting: just reconnect
      buffer.loader.reconnect(it)
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
  if buffer.config.scripting:
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
    buffer.reshape()
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
  buffer.pstream.withPacketWriter w:
    w.swrite(packetid)
    w.swrite(res)
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
        buffer.reshape()
        buffer.state = bsLoaded
        buffer.document.readyState = rsComplete
        if buffer.config.scripting:
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
    buffer.reshape()
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

proc forceRender*(buffer: Buffer) {.proxy.} =
  buffer.prevStyled = nil
  buffer.reshape()

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
  buffer.reshape()

#https://html.spec.whatwg.org/multipage/form-control-infrastructure.html#multipart/form-data-encoding-algorithm
proc serializeMultipart(entries: seq[FormDataEntry]): FormData =
  let formData = newFormData0(entries)
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
    return p[].form_request
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
      parsedAction.query = some(serializeFormURLEncoded(kvlist))
      return newRequest(parsedAction, httpMethod)
    return newRequest(parsedAction) # get action URL
  of frtMailto:
    if httpMethod == hmGet:
      # mailWithHeaders
      let kvlist = entryList.toNameValuePairs()
      #TODO with charset
      let headers = serializeFormURLEncoded(kvlist, spaceAsPlus = false)
      parsedAction.query = some(headers)
      return newRequest(parsedAction, httpMethod)
    # mail as body
    let kvlist = entryList.toNameValuePairs()
    let body = if enctype == fetTextPlain:
      percentEncode(serializePlainTextFormData(kvlist), PathPercentEncodeSet)
    else:
      #TODO with charset
      serializeFormURLEncoded(kvlist)
    if parsedAction.query.isNone:
      parsedAction.query = some("")
    if parsedAction.query.get != "":
      parsedAction.query.get &= '&'
    parsedAction.query.get &= "body=" & body
    return newRequest(parsedAction, httpMethod)
  of frtHttp:
    if httpMethod == hmGet:
      # mutate action URL
      let kvlist = entryList.toNameValuePairs()
      #TODO with charset
      let query = serializeFormURLEncoded(kvlist)
      parsedAction.query = some(query)
      return newRequest(parsedAction, httpMethod)
    # submit as entity body
    let body = case enctype
    of fetUrlencoded:
      #TODO with charset
      let kvlist = entryList.toNameValuePairs()
      RequestBody(t: rbtString, s: serializeFormURLEncoded(kvlist))
    of fetMultipart:
      #TODO with charset
      RequestBody(t: rbtMultipart, multipart: serializeMultipart(entryList))
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
  if buffer.document.focus != e:
    buffer.document.setFocus(e)
    buffer.reshape()
    return true

proc restoreFocus(buffer: Buffer): bool =
  if buffer.document.focus != nil:
    buffer.document.setFocus(nil)
    buffer.reshape()
    return true

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
    fd = buffer.pstream.recvFd()
  if buffer.document.focus != nil:
    case buffer.document.focus.tagType
    of TAG_INPUT:
      let input = HTMLInputElement(buffer.document.focus)
      case input.inputType
      of itFile:
        input.file = newWebFile(s, fd)
        input.setInvalid()
        buffer.reshape()
        res.repaint = true
        res.open = buffer.implicitSubmit(input)
      else:
        input.value = s
        input.setInvalid()
        buffer.reshape()
        res.repaint = true
        res.open = buffer.implicitSubmit(input)
    of TAG_TEXTAREA:
      let textarea = HTMLTextAreaElement(buffer.document.focus)
      textarea.value = s
      textarea.setInvalid()
      buffer.reshape()
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

proc click(buffer: Buffer; select: HTMLSelectElement): ClickResult =
  let repaint = buffer.setFocus(select)
  var options: seq[string] = @[]
  var selected: seq[int] = @[]
  var i = 0
  for option in select.options:
    options.add(option.textContent.stripAndCollapse())
    if option.selected:
      selected.add(i)
    inc i
  let select = SelectResult(
    multiple: select.attrb(satMultiple),
    options: options,
    selected: selected
  )
  return ClickResult(
    repaint: repaint,
    select: some(select)
  )

proc baseURL(buffer: Buffer): URL =
  return buffer.document.baseURL

proc evalJSURL(buffer: Buffer; url: URL): Opt[string] =
  let encodedScriptSource = ($url)["javascript:".len..^1]
  let scriptSource = percentDecode(encodedScriptSource)
  let ctx = buffer.window.jsctx
  let ret = ctx.eval(scriptSource, $buffer.baseURL, JS_EVAL_TYPE_GLOBAL)
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
      if not buffer.config.scripting:
        return ClickResult(repaint: repaint)
      let s = buffer.evalJSURL(url)
      buffer.reshape()
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
      buffer.reshape()
      return ClickResult(repaint: true)
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
    input.setInvalid()
    buffer.reshape()
    return ClickResult(repaint: true)
  of itRadio:
    for radio in input.radiogroup:
      radio.setChecked(false)
      radio.setInvalid()
    input.setChecked(true)
    input.setInvalid()
    buffer.reshape()
    return ClickResult(repaint: true)
  of itReset:
    if input.form != nil:
      input.form.reset()
      buffer.reshape()
      return ClickResult(repaint: true)
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
  else:
    return ClickResult(repaint: buffer.restoreFocus())

proc click*(buffer: Buffer; cursorx, cursory: int): ClickResult {.proxy.} =
  if buffer.lines.len <= cursory: return ClickResult()
  var repaint = false
  var canceled = false
  let clickable = buffer.getCursorClickable(cursorx, cursory)
  if buffer.config.scripting:
    let element = buffer.getCursorElement(cursorx, cursory)
    if element != nil:
      let window = buffer.window
      let event = newEvent(window.toAtom(satClick), element)
      canceled = window.jsctx.dispatch(element, event)
      if buffer.document.invalid:
        buffer.reshape()
        buffer.document.invalid = false
        repaint = true
  if not canceled:
    if clickable != nil:
      var res = buffer.click(clickable)
      if repaint: # override
        res.repaint = true
      return res
  return ClickResult(repaint: repaint)

proc select*(buffer: Buffer; selected: seq[int]): ClickResult {.proxy.} =
  if buffer.document.focus != nil and
      buffer.document.focus of HTMLSelectElement:
    let select = HTMLSelectElement(buffer.document.focus)
    var i = 0
    var j = 0
    var repaint = false
    for option in select.options:
      var wasSelected = option.selected
      if i < selected.len and selected[i] == j:
        option.selected = true
        inc i
      else:
        option.selected = false
      if not repaint:
        repaint = wasSelected != option.selected
      inc j
    return ClickResult(repaint: buffer.restoreFocus())

proc readCanceled*(buffer: Buffer): bool {.proxy.} =
  return buffer.restoreFocus()

proc findAnchor*(buffer: Buffer; anchor: string): bool {.proxy.} =
  return buffer.document != nil and buffer.document.findAnchor(anchor) != nil

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
    for i in countdown(element.childList.high, 0):
      let node = element.childList[i]
      if node of Text:
        let text = Text(node)
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
      elif node of HTMLElement:
        let element = HTMLElement(node)
        if element.tagType notin {TAG_HEAD, TAG_SCRIPT, TAG_STYLE, TAG_A}:
          stack.add(element)
  buffer.reshape()

proc toggleImages*(buffer: Buffer) {.proxy.} =
  buffer.config.images = not buffer.config.images

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
        buffer.pstream.withPacketWriter w:
          w.swrite(`packetid`)
      )
    else:
      resolve.add(quote do:
        buffer.pstream.withPacketWriter w:
          w.swrite(`packetid`)
          w.swrite(`rval`)
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
  var r = buffer.pstream.initPacketReader()
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
    if buffer.config.scripting:
      buffer.window.runJSJobs()
  elif fd in buffer.loader.unregistered:
    discard # ignore
  else:
    assert false
  true

proc handleError(buffer: Buffer; fd: int): bool =
  if fd == buffer.rfd:
    # Connection reset by peer, probably. Close the buffer.
    return false
  elif fd == buffer.fd:
    buffer.onload()
  elif buffer.loader.get(fd) != nil:
    if not buffer.loader.onError(fd):
      #TODO handle connection error
      assert false, $fd
    if buffer.config.scripting:
      buffer.window.runJSJobs()
  elif fd in buffer.loader.unregistered:
    discard # ignore
  else:
    assert false, $fd
  true

proc getPollTimeout(buffer: Buffer): cint =
  if not buffer.config.scripting:
    return -1
  return buffer.window.timeouts.sortAndGetTimeout()

proc runBuffer(buffer: Buffer) =
  var alive = true
  while alive:
    let timeout = buffer.getPollTimeout()
    buffer.pollData.poll(timeout)
    for event in buffer.pollData.events:
      if (event.revents and POLLIN) != 0:
        if not buffer.handleRead(event.fd):
          alive = false
          break
      if (event.revents and POLLERR) != 0 or (event.revents and POLLHUP) != 0:
        if not buffer.handleError(event.fd):
          alive = false
          break
    if buffer.config.scripting:
      if buffer.window.timeouts.run(buffer.estream):
        buffer.window.runJSJobs()
        buffer.maybeReshape()
    buffer.loader.unregistered.setLen(0)

proc cleanup(buffer: Buffer) =
  buffer.pstream.sclose()
  urandom.sclose()
  # no unlink access on Linux, so just hope that the pager could clean it up
  buffer.ssock.close(unlink = false)

proc launchBuffer*(config: BufferConfig; url: URL; attrs: WindowAttributes;
    ishtml: bool; charsetStack: seq[Charset]; loader: FileLoader;
    ssock: ServerSocket; pstream: SocketStream) =
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
    ssock: ssock,
    url: url,
    charsetStack: charsetStack,
    cacheId: -1,
    outputId: -1,
    factory: factory,
    window: newWindow(config.scripting, config.images, config.styling, attrs,
      factory, loader, url)
  )
  if buffer.config.scripting:
    buffer.window.navigate = proc(url: URL) = buffer.navigate(url)
  buffer.charset = buffer.charsetStack.pop()
  var r = pstream.initPacketReader()
  r.sread(buffer.loader.key)
  r.sread(buffer.cacheId)
  let fd = pstream.recvFd()
  buffer.fd = int(fd)
  buffer.istream = newPosixStream(fd)
  buffer.istream.setBlocking(false)
  buffer.pollData.register(fd, POLLIN)
  loader.registerFun = proc(fd: int) =
    buffer.pollData.register(fd, POLLIN)
  loader.unregisterFun = proc(fd: int) =
    buffer.pollData.unregister(fd)
  buffer.pollData.register(buffer.rfd, POLLIN)
  const css = staticRead"res/ua.css"
  const quirk = css & staticRead"res/quirk.css"
  buffer.initDecoder()
  buffer.uastyle = css.parseStylesheet(factory)
  buffer.quirkstyle = quirk.parseStylesheet(factory)
  buffer.userstyle = parseStylesheet(buffer.config.userstyle, factory)
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
