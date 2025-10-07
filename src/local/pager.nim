{.push raises: [].}

import std/options
import std/os
import std/posix
import std/sets
import std/strutils
import std/tables
import std/times

import chagashi/charset
import chagashi/decoder
import config/chapath
import config/config
import config/conftypes
import config/cookie
import config/history
import config/mailcap
import config/mimetypes
import css/render
import html/script
import io/chafile
import io/console
import io/dynstream
import io/packetreader
import io/packetwriter
import io/poll
import io/promise
import io/timeout
import local/container
import local/lineedit
import local/select
import local/term
import monoucha/fromjs
import monoucha/javascript
import monoucha/jsregex
import monoucha/jstypes
import monoucha/jsutils
import monoucha/libregexp
import monoucha/quickjs
import monoucha/tojs
import server/buffer
import server/connectionerror
import server/forkserver
import server/headers
import server/loaderiface
import server/request
import server/response
import types/bitmap
import types/blob
import types/cell
import types/color
import types/opt
import types/url
import types/winattrs
import utils/luwrap
import utils/myposix
import utils/regexutils
import utils/strwidth
import utils/twtstr

type
  LineMode* = enum
    lmLocation = "URL: "
    lmUsername = "Username: "
    lmPassword = "Password: "
    lmCommand = "COMMAND: "
    lmBuffer
    lmSearchF = "/"
    lmSearchB = "?"
    lmISearchF = "/"
    lmISearchB = "?"
    lmGotoLine = "Goto line: "
    lmDownload = "(Download)Save file to: "
    lmBufferFile = "(Upload)Filename: "
    lmAlert = ""
    lmMailcap = "Mailcap: "

  PagerAlertState = enum
    pasNormal, pasAlertOn, pasLoadInfo

  ContainerConnectionState = enum
    ccsBeforeResult, ccsBeforeStatus

  ConnectingContainer* = ref object of MapData
    state: ContainerConnectionState
    container: Container
    res: int
    outputId: int

  LineData = ref object of RootObj

  LineDataDownload = ref object of LineData
    outputId: int
    stream: PosixStream
    url: URL

  LineDataAuth = ref object of LineData
    url: URL

  LineDataMailcap = ref object of LineData
    container: Container
    ostream: PosixStream
    contentType: string
    i: int
    response: Response
    sx: int

  SurfaceType = enum
    stDisplay, stStatus

  Surface = object
    redraw: bool
    grid: FixedGrid

  # Mouse data
  MouseClickState = enum
    mcsNormal, mcsDouble

  MouseMoveType = enum
    mmtNone, mmtDrag, mmtSelect

  Mouse = object
    pressed: array[MouseButton, MouseInputPosition]
    click: array[MouseButton, MouseClickState]
    lastPressed: array[MouseButton, MouseInputPosition]
    inSelection: bool
    moveType: MouseMoveType

  Pinned = object
    downloads: Container
    console*: Container
    prev: Container

  Pager* = ref object of RootObj
    alive: bool
    blockTillRelease: bool
    commandMode {.jsget.}: bool
    feednext*: bool
    hasload: bool # has a page been successfully loaded since startup?
    inEval: bool
    notnum: bool # has a non-numeric character been input already?
    reverseSearch: bool
    dumpConsoleFile: bool
    updateTitle: bool
    consoleCacheId: int
    consoleFile: string
    alertState: PagerAlertState
    precnum: int32 # current number prefix (when vi-numeric-prefix is true)
    alerts: seq[string]
    askCursor: int
    askPromise*: Promise[string]
    askPrompt: string
    config*: Config
    console*: Console
    tabHead: Tab # not nil
    tab: Tab # not nil
    cookieJars: CookieJarMap
    surfaces: array[SurfaceType, Surface]
    pinned*: Pinned
    exitCode: int
    forkserver*: ForkServer
    inputBuffer: string # currently uninterpreted characters
    iregex: Result[Regex, string]
    isearchpromise: EmptyPromise
    jsctx: JSContext
    jsrt: JSRuntime
    lastAlert: string # last alert seen by the user
    lineData: LineData
    lineHist: array[LineMode, History]
    lineedit*: LineEdit
    linemode: LineMode
    loader: FileLoader
    loaderPid {.jsget.}: int
    luctx: LUContext
    menu: Select
    mouse: Mouse
    navDirection {.jsget.}: NavDirection
    numload: int # number of pages currently being loaded
    pollData: PollData
    refreshAllowed: HashSet[string]
    regex: Option[Regex]
    scommand: string
    term*: Terminal
    timeouts*: TimeoutState
    tmpfSeq: uint
    unreg: seq[Container]

  ContainerData* = ref object of MapData
    container*: Container

  CheckMailcapFlag = enum
    cmfConnect, cmfHTML, cmfFound, cmfRedirected, cmfPrompt, cmfNeedsstyle,
    cmfNeedsimage, cmfSaveoutput

  MailcapResult = object
    entry: MailcapEntry
    flags: set[CheckMailcapFlag]
    ostream: PosixStream
    ostreamOutputId: int
    cmd: string

jsDestructor(Pager)

# Forward declarations
proc addConsole(pager: Pager; interactive: bool): Console
proc alert*(pager: Pager; msg: string)
proc askMailcap(pager: Pager; container: Container; ostream: PosixStream;
  contentType: string; i: int; response: Response; sx: int)
proc connected2(pager: Pager; container: Container; res: MailcapResult;
  response: Response)
proc connected3(pager: Pager; container: Container; stream: SocketStream;
  ostream: PosixStream; istreamOutputId, ostreamOutputId: int;
  redirected: bool)
proc deleteContainer(pager: Pager; container, setTarget: Container)
proc dumpBuffers(pager: Pager)
proc evalJS(pager: Pager; src, filename: string; module = false): JSValue
proc fulfillAsk(pager: Pager; s: string)
proc getHist(pager: Pager; mode: LineMode): History
proc handleEvents(pager: Pager)
proc handleRead(pager: Pager; fd: int): Opt[void]
proc inputLoop(pager: Pager): Opt[void]
proc loadURL(pager: Pager; url: string; contentType = "";
  charset = CHARSET_UNKNOWN; history = true)
proc openMenu(pager: Pager; x = -1; y = -1)
proc readPipe(pager: Pager; contentType: string; cs: Charset; ps: PosixStream;
  title: string)
proc refreshStatusMsg(pager: Pager)
proc runMailcap(pager: Pager; url: URL; stream: PosixStream;
  istreamOutputId: int; contentType: string; entry: MailcapEntry):
  MailcapResult
proc showAlerts(pager: Pager)
proc unregisterFd(pager: Pager; fd: int)
proc updateReadLine(pager: Pager)

template attrs(pager: Pager): WindowAttributes =
  pager.term.attrs

proc container(pager: Pager): Container {.jsfget: "buffer".} =
  pager.tab.current

proc bufWidth(pager: Pager): int =
  return pager.attrs.width

proc bufHeight(pager: Pager): int =
  return pager.attrs.height - 1

iterator tabs(pager: Pager): Tab {.inline.} =
  var tab = pager.tabHead
  while tab != nil:
    yield tab
    tab = tab.next

iterator containers(tab: Tab): Container {.inline.} =
  var c = tab.head
  while c != nil:
    yield c
    c = c.next

iterator containers(pager: Pager): Container {.inline.} =
  for tab in pager.tabs:
    for c in tab.containers:
      yield c

proc surfaceSize(pager: Pager; t: SurfaceType): tuple[w, h: int] =
  case t
  of stDisplay: return (pager.bufWidth, pager.bufHeight)
  of stStatus: return (pager.attrs.width, 1)

proc clear(pager: Pager; t: SurfaceType) =
  let (w, h) = pager.surfaceSize(t)
  pager.surfaces[t] = Surface(
    grid: newFixedGrid(w, h),
    redraw: true
  )

template status(pager: Pager): Surface =
  pager.surfaces[stStatus]

template display(pager: Pager): Surface =
  pager.surfaces[stDisplay]

proc setContainer(pager: Pager; c: Container) =
  if pager.term.imageMode != imNone and pager.container != nil:
    for cachedImage in pager.container.cachedImages:
      if cachedImage.state == cisLoaded:
        pager.loader.removeCachedItem(cachedImage.cacheId)
      cachedImage.state = cisCanceled
    pager.container.cachedImages.setLen(0)
  if c != nil:
    if c.tab != pager.tab:
      assert c.tab != nil
      pager.tab = c.tab
    c.tab.current = c
    c.queueDraw()
    pager.updateTitle = true
  else:
    pager.tab.current = nil

proc reflect(ctx: JSContext; this_val: JSValueConst; argc: cint;
    argv: JSValueConstArray; magic: cint; func_data: JSValueConstArray): JSValue
    {.cdecl.} =
  let obj = func_data[0]
  let fun = func_data[1]
  return JS_Call(ctx, fun, obj, argc, argv)

proc getter(ctx: JSContext; pager: Pager; a: JSAtom): JSValue {.jsgetownprop.} =
  if pager.container != nil:
    let cval = if pager.menu != nil:
      ctx.toJS(pager.menu)
    elif pager.container.select != nil:
      ctx.toJS(pager.container.select)
    else:
      ctx.toJS(pager.container)
    let val = JS_GetProperty(ctx, cval, a)
    if JS_IsFunction(ctx, val):
      let func_data = @[cval, val]
      let fun = JS_NewCFunctionData(ctx, reflect, 1, 0, 2,
        func_data.toJSValueArray())
      JS_FreeValue(ctx, cval)
      JS_FreeValue(ctx, val)
      return fun
    JS_FreeValue(ctx, cval)
    if not JS_IsUndefined(val):
      return val
  return JS_UNINITIALIZED

proc searchNext(pager: Pager; n = 1) {.jsfunc.} =
  if pager.regex.isSome:
    let wrap = pager.config.search.wrap
    pager.container.markPos0()
    if not pager.reverseSearch:
      pager.container.cursorNextMatch(pager.regex.get, wrap, true, n)
    else:
      pager.container.cursorPrevMatch(pager.regex.get, wrap, true, n)
    pager.container.markPos()
  else:
    pager.alert("No previous regular expression")

proc searchPrev(pager: Pager; n = 1) {.jsfunc.} =
  if pager.regex.isSome:
    let wrap = pager.config.search.wrap
    pager.container.markPos0()
    if not pager.reverseSearch:
      pager.container.cursorPrevMatch(pager.regex.get, wrap, true, n)
    else:
      pager.container.cursorNextMatch(pager.regex.get, wrap, true, n)
    pager.container.markPos()
  else:
    pager.alert("No previous regular expression")

proc setSearchRegex(ctx: JSContext; pager: Pager; s: string; flags0 = "";
    reverse = false): JSValue {.jsfunc.} =
  var flags = {LRE_FLAG_GLOBAL}
  for c in flags0:
    let x = strictParseEnum[LREFlag]($c)
    if x.isErr:
      return JS_ThrowTypeError(ctx, "invalid flag %c", c)
  let re = compileRegex(s, flags)
  if re.isErr:
    return JS_ThrowTypeError(ctx, cstring(re.error))
  pager.regex = some(re.get)
  pager.reverseSearch = reverse
  return JS_UNDEFINED

proc getHist(pager: Pager; mode: LineMode): History =
  if pager.lineHist[mode] == nil:
    pager.lineHist[mode] = newHistory(100)
  return pager.lineHist[mode]

proc setLineEdit(pager: Pager; mode: LineMode; current = ""; hide = false;
    prompt = $mode) =
  let hist = pager.getHist(mode)
  pager.lineedit = readLine(prompt, current, pager.attrs.width, hide, hist,
    pager.luctx)
  pager.linemode = mode

# Reuse the line editor as an alert message viewer.
proc showFullAlert(pager: Pager) {.jsfunc.} =
  if pager.lastAlert != "":
    pager.setLineEdit(lmAlert, pager.lastAlert)

proc searchForward(pager: Pager) {.jsfunc.} =
  pager.setLineEdit(lmSearchF)

proc searchBackward(pager: Pager) {.jsfunc.} =
  pager.setLineEdit(lmSearchB)

proc isearchForward(pager: Pager) {.jsfunc.} =
  pager.container.pushCursorPos()
  pager.isearchpromise = newResolvedPromise()
  pager.container.markPos0()
  pager.setLineEdit(lmISearchF)

proc isearchBackward(pager: Pager) {.jsfunc.} =
  pager.container.pushCursorPos()
  pager.isearchpromise = newResolvedPromise()
  pager.container.markPos0()
  pager.setLineEdit(lmISearchB)

proc gotoLine(ctx: JSContext; pager: Pager; val: JSValueConst = JS_UNDEFINED):
    Opt[void] {.jsfunc.} =
  var n: int
  if JS_IsNumber(val) and ctx.fromJS(val, n).isOk:
    pager.container.gotoLine(n)
  elif JS_IsUndefined(val):
    pager.setLineEdit(lmGotoLine)
  else:
    var s: string
    ?ctx.fromJS(val, s)
    pager.container.gotoLine(s)
  return ok()

proc loadJSModule(ctx: JSContext; moduleName: cstringConst; opaque: pointer):
    JSModuleDef {.cdecl.} =
  let moduleName = $moduleName
  let x = if moduleName.startsWith("/") or moduleName.startsWith("./") or
      moduleName.startsWith("../"):
    parseURL0(moduleName, parseURL0("file://" & myposix.getcwd() & "/"))
  else:
    parseURL0(moduleName)
  if x == nil or x.schemeType != stFile:
    JS_ThrowTypeError(ctx, "invalid URL: %s", cstring(moduleName))
    return nil
  var source: string
  if chafile.readFile(x.pathname, source).isOk:
    return ctx.finishLoadModule(source, moduleName)
  JS_ThrowTypeError(ctx, "failed to read file %s", cstring(moduleName))
  return nil

proc interruptHandler(rt: JSRuntime; opaque: pointer): cint {.cdecl.} =
  result = cint(term.sigintCaught)
  term.sigintCaught = false

proc evalJSFree(opaque: RootRef; src, filename: string) =
  let pager = Pager(opaque)
  JS_FreeValue(pager.jsctx, pager.evalJS(src, filename))

type CookieStreamOpaque = ref object of RootObj
  pager: Pager
  buffer: string

proc onReadCookieStream(response: Response) =
  const BufferSize = 4096
  let opaque = CookieStreamOpaque(response.opaque)
  let pager = opaque.pager
  while true:
    let olen = opaque.buffer.len
    opaque.buffer.setLen(olen + BufferSize)
    let n = response.body.readData(addr opaque.buffer[olen], BufferSize)
    if n <= 0:
      opaque.buffer.setLen(olen)
      break
    opaque.buffer.setLen(olen + n)
  var lastlf = opaque.buffer.rfind('\n')
  var i = 0
  # Syntax: {jarId} RS {url} RS {persist?} RS {header} [ CR {header} ... ] LF
  # Persist is ASCII digit 0 if persist, 1 if not.
  const RS = '\x1E' # ASCII record separator
  while i < lastlf:
    let jarId = opaque.buffer.until(RS, i)
    i += jarId.len + 1
    let urls = opaque.buffer.until(RS, i)
    i += urls.len + 1
    let persists = opaque.buffer.until(RS, i)
    i += persists.len + 1
    var headers: seq[string] = @[]
    while i - 1 < opaque.buffer.len and opaque.buffer[i - 1] != '\n':
      let header = opaque.buffer.until({'\n', '\r'}, i)
      headers.add(header)
      i += header.len + 1
    let cookieJar = pager.cookieJars.getOrDefault(jarId)
    let url = parseURL0(urls)
    let persist = persists != "0"
    if cookieJar == nil or url == nil or persist and persists != "1":
      pager.alert("Error: received wrong set-cookie notification")
      continue
    cookieJar.setCookie(headers, url, persist)
  if i > 0:
    opaque.buffer.delete(0 ..< i)

proc onFinishCookieStream(response: Response; success: bool) =
  let pager = CookieStreamOpaque(response.opaque).pager
  pager.alert("Error: cookie stream broken")

proc initLoader(pager: Pager) =
  let clientConfig = LoaderClientConfig(
    defaultHeaders: pager.config.network.defaultHeaders,
    proxy: pager.config.network.proxy,
    allowAllSchemes: true
  )
  let loader = pager.loader
  discard loader.addClient(loader.clientPid, clientConfig, -1, isPager = true)
  pager.loader.registerFun = proc(fd: int) =
    pager.pollData.register(fd, POLLIN)
  pager.loader.unregisterFun = proc(fd: int) =
    pager.pollData.unregister(fd)
  let request = newRequest("about:cookie-stream")
  loader.fetch(request).then(proc(res: FetchResult) =
    if res.isErr:
      pager.alert("failed to open cookie stream")
      return
    # ugly hack, so that the cookie stream does not keep headless
    # instances running
    dec loader.mapFds
    let response = res.get
    response.opaque = CookieStreamOpaque(pager: pager)
    response.onRead = onReadCookieStream
    response.onFinish = onFinishCookieStream
    response.resume()
  )

proc newPager*(config: Config; forkserver: ForkServer; ctx: JSContext;
    alerts: seq[string]; loader: FileLoader; loaderPid: int): Pager =
  let tab = Tab()
  let pager = Pager(
    alive: true,
    config: config,
    forkserver: forkserver,
    term: newTerminal(newPosixStream(STDOUT_FILENO), config),
    alerts: alerts,
    jsrt: JS_GetRuntime(ctx),
    jsctx: ctx,
    luctx: LUContext(),
    exitCode: -1,
    loader: loader,
    loaderPid: loaderPid,
    cookieJars: newCookieJarMap(),
    tabHead: tab,
    tab: tab,
    consoleCacheId: -1
  )
  pager.timeouts = newTimeoutState(pager.jsctx, evalJSFree, pager)
  JS_SetModuleLoaderFunc(pager.jsrt, normalizeModuleName, loadJSModule, nil)
  JS_SetInterruptHandler(pager.jsrt, interruptHandler, nil)
  pager.initLoader()
  block history:
    let hist = newHistory(pager.config.external.historySize, getTime().toUnix())
    let ps = newPosixStream(pager.config.external.historyFile)
    if ps != nil:
      if hist.parse(ps).isErr:
        hist.transient = true
        pager.alert("failed to read history")
    pager.lineHist[lmLocation] = hist
  block cookie:
    let ps = newPosixStream(pager.config.external.cookieFile)
    if ps != nil:
      if pager.cookieJars.parse(ps, pager.alerts).isErr:
        pager.cookieJars.transient = true
        pager.alert("failed to read cookies")
  return pager

proc cleanup(pager: Pager) =
  if pager.alive:
    pager.alive = false
    discard pager.term.quit() # maybe stdout is closed, but we don't mind here
    let hist = pager.lineHist[lmLocation]
    let hasConfigDir = dirExists(pager.config.dir)
    if not hist.transient:
      if hasConfigDir and not dirExists(pager.config.dataDir):
        # Basedir case: data dir is not the same as config dir.
        # I'd try to make parent dirs but in all likelihood some other
        # program has already spammed this nonsense into $HOME so whatever.
        discard mkdir(cstring(pager.config.external.tmpdir), 0o700)
      if hist.write(pager.config.external.historyFile).isErr:
        if not hasConfigDir:
          # History is enabled by default, so do not print the error
          # message if no config dir exists.
          pager.alert("failed to save history")
    if not pager.cookieJars.transient:
      if hasConfigDir and not dirExists(pager.config.dataDir):
        # see above
        discard mkdir(cstring(pager.config.external.tmpdir), 0o700)
      if pager.cookieJars.write(pager.config.external.cookieFile).isErr:
        pager.alert("failed to save cookies")
    for msg in pager.alerts:
      discard cast[ChaFile](stderr).write("cha: " & msg & '\n')
    for val in pager.config.cmd.map.values:
      JS_FreeValue(pager.jsctx, val)
    for fn in pager.config.jsvfns:
      JS_FreeValue(pager.jsctx, fn)
    pager.timeouts.clearAll()
    assert not pager.inEval
    pager.jsctx.free()
    pager.jsrt.free()
    if pager.console != nil and pager.dumpConsoleFile:
      if file := chafile.fopen(pager.consoleFile, "r+"):
        let stderr = cast[ChaFile](stderr)
        var buffer {.noinit.}: array[1024, uint8]
        while (let n = file.read(buffer); n != 0):
          if stderr.write(buffer.toOpenArray(0, n - 1)).isErr:
            break

proc quit(pager: Pager; code: int) =
  pager.cleanup()
  quit(code)

proc runJSJobs(pager: Pager) =
  while true:
    let r = pager.jsrt.runJSJobs()
    if r.isOk:
      break
    let ctx = r.error
    pager.console.writeException(ctx)
  if pager.exitCode != -1:
    pager.quit(pager.exitCode)

proc evalJS(pager: Pager; src, filename: string; module = false): JSValue =
  if pager.config.start.headless == hmFalse:
    pager.term.catchSigint()
  let flags = if module:
    JS_EVAL_TYPE_MODULE
  else:
    JS_EVAL_TYPE_GLOBAL
  let wasInEval = pager.inEval
  pager.inEval = true
  result = pager.jsctx.eval(src, filename, flags)
  pager.inEval = false
  if pager.exitCode != -1:
    # if we are in a nested eval, then just wait until we are not.
    if not wasInEval:
      pager.quit(pager.exitCode)
  else:
    pager.runJSJobs()
  if pager.config.start.headless == hmFalse:
    pager.term.respectSigint()

proc evalActionJS(pager: Pager; action: string): JSValue =
  if action.startsWith("cmd."):
    let k = action.substr("cmd.".len)
    let val = pager.config.cmd.map.getOrDefault(k, JS_UNINITIALIZED)
    if not JS_IsUninitialized(val):
      return JS_DupValue(pager.jsctx, val)
  return pager.evalJS(action, "<command>")

# Warning: this is not re-entrant.
proc evalAction(pager: Pager; action: string; arg0: int32): EmptyPromise =
  var ret = pager.evalActionJS(action)
  let ctx = pager.jsctx
  var p: EmptyPromise = nil
  if JS_IsFunction(ctx, ret):
    if arg0 != 0:
      let arg0 = toJS(ctx, arg0)
      let ret2 = JS_CallFree(ctx, ret, JS_UNDEFINED, 1, arg0.toJSValueArray())
      JS_FreeValue(ctx, arg0)
      ret = ret2
    else: # no precnum
      ret = JS_CallFree(ctx, ret, JS_UNDEFINED, 0, nil)
    if pager.exitCode != -1:
      assert not pager.inEval
      pager.quit(pager.exitCode)
  if JS_IsException(ret):
    pager.console.writeException(pager.jsctx)
  elif JS_IsObject(ret):
    var maybep: EmptyPromise
    if ctx.fromJS(ret, maybep).isOk:
      p = maybep
  JS_FreeValue(ctx, ret)
  return p

proc command0(pager: Pager; src: string; filename = "<command>";
    silence = false; module = false) =
  let ret = pager.evalJS(src, filename, module = module)
  if JS_IsException(ret):
    pager.console.writeException(pager.jsctx)
  else:
    if not silence:
      var res: string
      if pager.jsctx.fromJS(ret, res).isOk:
        pager.console.log(res)
        pager.console.flush()
  JS_FreeValue(pager.jsctx, ret)

proc hasMouseSelection(pager: Pager): bool =
  return pager.container.currentSelection != nil and
    pager.container.currentSelection.mouse

proc handleMouseInputGeneric(pager: Pager; input: MouseInput) =
  let button = input.button
  let pressed = pager.mouse.pressed[input.button]
  case button
  of mibLeft:
    if input.t == mitRelease:
      if pager.mouse.inSelection:
        pager.mouse.inSelection = false
      elif input.pos.y == pager.attrs.height - 1 and pressed == input.pos:
        discard pager.evalAction("cmd.pager.load", 0)
      elif input.pos.y >= pager.attrs.height - 2 and pressed.y == input.pos.y:
        let dcol = input.pos.x - pressed.x
        if dcol <= -2:
          discard pager.evalAction("cmd.pager.nextBuffer", 0)
        elif dcol >= 2:
          discard pager.evalAction("cmd.pager.prevBuffer", 0)
      elif pressed != (-1i32, -1i32):
        let dcol = input.pos.x - pressed.x
        let drow = input.pos.y - pressed.y
        if dcol > 0:
          discard pager.evalAction("cmd.buffer.scrollLeft", dcol)
        elif dcol < 0:
          discard pager.evalAction("cmd.buffer.scrollRight", -dcol)
        if drow > 0:
          discard pager.evalAction("cmd.buffer.scrollUp", drow)
        elif drow < 0:
          discard pager.evalAction("cmd.buffer.scrollDown", -drow)
  of mibRight:
    if input.t == mitRelease and pressed == input.pos and
        input.pos.y == pager.attrs.height - 1:
      discard pager.evalAction("cmd.pager.loadCursor", 0)
  of mibMiddle:
    if input.t == mitRelease and pressed == input.pos and
        input.pos.y == pager.attrs.height - 1:
      discard pager.evalAction("cmd.pager.loadEmpty", 0)
  of mibWheelUp:
    if input.t == mitPress:
      discard pager.evalAction("cmd.buffer.scrollUp",
        pager.config.input.wheelScroll)
  of mibWheelDown:
    if input.t == mitPress:
      discard pager.evalAction("cmd.buffer.scrollDown",
        pager.config.input.wheelScroll)
  of mibWheelLeft:
    if input.t == mitPress:
      discard pager.evalAction("cmd.buffer.scrollLeft",
        pager.config.input.sideWheelScroll)
  of mibWheelRight:
    if input.t == mitPress:
      discard pager.evalAction("cmd.buffer.scrollRight",
        pager.config.input.sideWheelScroll)
  else: discard
  case input.t
  of mitPress:
    pager.mouse.pressed[button] = input.pos
    if input.pos == pager.mouse.lastPressed[input.button]:
      if pager.mouse.click[button] < MouseClickState.high:
        inc pager.mouse.click[button]
  of mitMove: discard
  of mitRelease:
    if pressed != input.pos:
      pager.mouse.click[button] = mcsNormal
    pager.mouse.lastPressed[button] = pager.mouse.pressed[button]
    pager.mouse.pressed[button] = (-1i32, -1i32)

proc handleMouseInput(pager: Pager; input: MouseInput; container: Container) =
  let button = input.button
  let pressed = pager.mouse.pressed[button]
  case button
  of mibLeft:
    case input.t
    of mitRelease:
      if pager.hasMouseSelection():
        pager.mouse.inSelection = true
      elif pressed == input.pos and input.pos.y < pager.attrs.height - 1:
        let prevx = container.cursorx
        let prevy = container.cursory
        container.setAbsoluteCursorXY(input.pos.x, input.pos.y)
        if prevx == container.cursorx and prevy == container.cursory:
          discard pager.evalAction("cmd.buffer.click", 0)
      pager.mouse.moveType = mmtNone
    of mitPress:
      if pager.hasMouseSelection():
        pager.container.clearSelection()
    of mitMove:
      if pager.mouse.click[button] == mcsDouble:
        case pager.mouse.moveType
        of mmtNone:
          # if mouse moved downwards, grab.
          # otherwise, select.
          if pressed.y == input.pos.y:
            pager.mouse.moveType = mmtSelect
            if not pager.hasMouseSelection():
              container.startSelection(stNormal, mouse = true)
            container.setAbsoluteCursorXY(input.pos.x, input.pos.y)
          else:
            pager.mouse.moveType = mmtDrag
        of mmtSelect:
          container.setAbsoluteCursorXY(input.pos.x, input.pos.y)
        of mmtDrag: discard
  of mibMiddle:
    if input.t == mitRelease and input.pos == pressed and
        input.pos.y < pager.attrs.height - 1:
      discard pager.evalAction("cmd.pager.discardBuffer", 0)
  of mibRight:
    if input.t == mitPress and input.pos.y < pager.attrs.height - 1:
      # w3m uses release, but I like press better
      if container.currentSelection == nil:
        container.setAbsoluteCursorXY(input.pos.x, input.pos.y)
      pager.openMenu(input.pos.x, input.pos.y)
      pager.menu.unselect()
  of mibThumbInner:
    if input.t == mitPress:
      discard pager.evalAction("cmd.pager.prevBuffer", 0)
  of mibThumbTip:
    if input.t == mitPress:
      discard pager.evalAction("cmd.pager.nextBuffer", 0)
  else: discard

proc handleMouseInput(pager: Pager; input: MouseInput; select: Select) =
  let y = select.fromy + input.pos.y - select.y - 1 # one off because of border
  if input.button in {mibRight, mibLeft}:
    let pressed = pager.mouse.pressed[input.button]
    # Note: "not inside and not outside" is a valid state, and it
    # represents the mouse being above the border.
    let inside =
      input.pos.y in select.y + 1 ..< select.y + select.height - 1 and
      input.pos.x in select.x + 1 ..< select.x + select.width - 1
    let outside =
      input.pos.y notin select.y ..< select.y + select.height or
      input.pos.x notin select.x ..< select.x + select.width
    if input.button == mibRight:
      if not inside:
        select.unselect()
      elif input.pos != pressed:
        # Prevent immediate movement/submission in case the menu appeared under
        # the cursor.
        select.setCursorY(y)
      case input.t
      of mitPress:
        # Do not include borders, so that a double right click closes the
        # menu again.
        if not inside:
          pager.blockTillRelease = true
          select.cursorLeft()
      of mitRelease:
        if inside and input.pos != pressed:
          select.click()
        elif outside:
          select.cursorLeft()
      of mitMove: discard
    else: # mibLeft
      case input.t
      of mitPress:
        if outside: # clicked outside the select
          pager.blockTillRelease = true
          select.cursorLeft()
      of mitRelease:
        if input.pos == pressed and inside:
          # clicked inside the select
          select.setCursorY(y)
          select.click()
      of mitMove: discard

proc handleMouseInput(pager: Pager; input: MouseInput) =
  if pager.blockTillRelease:
    if input.t != mitRelease:
      return
    pager.blockTillRelease = false
  if pager.menu != nil:
    pager.handleMouseInput(input, pager.menu)
  elif (let container = pager.container; container != nil):
    if container.select != nil:
      pager.handleMouseInput(input, container.select)
    else:
      pager.handleMouseInput(input, container)
  if not pager.blockTillRelease:
    pager.handleMouseInputGeneric(input)
  pager.refreshStatusMsg()
  pager.handleEvents()

# The maximum number we are willing to accept.
# This should be fine for 32-bit signed ints (which precnum currently is).
# We can always increase it further (e.g. by switching to uint32, uint64...) if
# it proves to be too low.
const MaxPrecNum = 100000000

proc handleAskInput(pager: Pager; e: InputEvent) =
  case e.t
  of ietKey: pager.inputBuffer &= e.c
  of ietKeyEnd:
    pager.fulfillAsk(pager.inputBuffer)
    pager.inputBuffer = ""
    pager.refreshStatusMsg()
    pager.handleEvents()
  of ietMouse: pager.handleMouseInput(e.m)
  else: discard

proc handleLineInput(pager: Pager; e: InputEvent) =
  case e.t
  of ietKey: pager.inputBuffer &= e.c
  of ietKeyEnd:
    let edit = pager.lineedit
    if edit.escNext:
      edit.escNext = false
      edit.write(move(pager.inputBuffer))
    else:
      let action = pager.config.getLinedAction(pager.inputBuffer)
      if action == "":
        edit.write(move(pager.inputBuffer))
      else:
        discard pager.evalAction(action, 0)
      if not pager.feednext:
        pager.updateReadLine()
        pager.inputBuffer = ""
      pager.feednext = false
  of ietMouse: pager.handleMouseInput(e.m)
  of ietPaste: pager.lineedit.write(move(pager.inputBuffer))

proc handleCommandInput(pager: Pager; e: InputEvent) =
  case e.t
  of ietMouse: pager.handleMouseInput(e.m)
  of ietKey: pager.inputBuffer &= e.c
  of ietPaste: pager.setLineEdit(lmLocation, move(pager.inputBuffer))
  of ietKeyEnd:
    if pager.config.input.viNumericPrefix and not pager.notnum:
      let c = pager.inputBuffer[0]
      if pager.precnum != 0 and c == '0' or c in '1'..'9':
        if pager.precnum < MaxPrecNum: # better ignore than eval...
          pager.precnum *= 10
          pager.precnum += int32(decValue(c))
        pager.inputBuffer = ""
        pager.refreshStatusMsg()
        return
      else:
        pager.notnum = true
    let action = pager.config.getNormalAction(pager.inputBuffer)
    let p = if action != "": pager.evalAction(action, pager.precnum) else: nil
    if not pager.feednext:
      pager.inputBuffer = ""
      pager.precnum = 0
      pager.notnum = false
      if p != nil:
        p.then(proc() =
          pager.refreshStatusMsg()
          pager.handleEvents()
        )
    if p == nil:
      pager.refreshStatusMsg()
      pager.handleEvents()
    pager.feednext = false

proc handleUserInput(pager: Pager): Opt[void] =
  if not ?pager.term.ahandleRead():
    return
  while e := pager.term.areadEvent():
    if pager.askPromise != nil:
      pager.handleAskInput(e)
    elif pager.lineedit != nil:
      pager.handleLineInput(e)
    else:
      pager.handleCommandInput(e)
  ok()

proc run*(pager: Pager; pages: openArray[string]; contentType: string;
    cs: Charset; history: bool) =
  var istream: PosixStream = nil
  let ps = newPosixStream(STDIN_FILENO)
  if pager.config.start.headless == hmFalse:
    let os = newPosixStream(STDOUT_FILENO)
    if ps.isatty():
      istream = ps
    if os.isatty():
      if istream == nil:
        istream = newPosixStream("/dev/tty", O_RDONLY, 0)
    else:
      istream = nil
    if istream == nil:
      pager.config.start.headless = hmDump
  pager.pollData.register(pager.forkserver.estream.fd, POLLIN)
  let sr = pager.term.start(istream, proc(fd: int) =
    pager.pollData.register(fd, POLLOUT))
  if sr.isErr:
    return
  case sr.get
  of tsrSuccess: discard
  of tsrDA1Fail:
    pager.alert("Failed to query DA1, please set display.query-da1 = false")
  for st in SurfaceType:
    pager.clear(st)
  pager.console = pager.addConsole(istream != nil)
  if pager.config.start.startupScript != "":
    let ps = newPosixStream(pager.config.start.startupScript)
    let s = if ps != nil:
      var x = ps.readAll()
      ps.sclose()
      move(x)
    else:
      pager.config.start.startupScript
    let ismodule = pager.config.start.startupScript.endsWith(".mjs")
    pager.command0(s, pager.config.start.startupScript, silence = true,
      module = ismodule)
  if not ps.isatty():
    # stdin may very well receive ANSI text
    let contentType = if contentType != "": contentType else: "text/x-ansi"
    pager.readPipe(contentType, cs, ps, "*stdin*")
  # we don't want history for dump/headless mode
  let history = pager.config.start.headless == hmFalse and history
  for page in pages:
    pager.loadURL(page, contentType, cs, history)
  pager.showAlerts()
  if pager.config.start.headless == hmFalse:
    discard pager.inputLoop()
  else:
    pager.dumpBuffers()
  pager.quit(max(pager.exitCode, 0))

# Note: this function does not work correctly if start < x of last written char
proc writeStatusMessage(status: var Surface; str: string; format = Format();
    start = 0; maxwidth = -1): int =
  var maxwidth = maxwidth
  if maxwidth == -1:
    maxwidth = status.grid.len
  var x = start
  let e = min(start + maxwidth, status.grid.width)
  if x >= e:
    return x
  status.redraw = true
  for u in str.points:
    var u = u
    var w = u.width()
    if u == uint32('\t'):
      w = ((x + 8) and not 7) - x
    if x + w > e: # clip if we overflow (but not on exact fit)
      break
    if u.isControlChar():
      if u == uint32('\t'):
        while w > 0:
          status.grid[x].str = " "
          status.grid[x].format = format
          inc x
          dec w
        continue
      status.grid[x].str = u.controlToVisual()
    else:
      status.grid[x].str = u.toUTF8()
    status.grid[x].format = format
    let nx = x + w
    inc x
    while x < nx: # clear unset cells
      status.grid[x].str = ""
      status.grid[x].format = Format()
      inc x
  result = x
  while x < e:
    status.grid[x] = FixedCell()
    inc x

# Note: should only be called directly after user interaction.
proc refreshStatusMsg(pager: Pager) =
  let container = pager.container
  if container == nil: return
  if pager.askPromise != nil:
    return
  if pager.precnum != 0:
    discard pager.status.writeStatusMessage($pager.precnum & pager.inputBuffer)
  elif pager.inputBuffer != "":
    discard pager.status.writeStatusMessage(pager.inputBuffer)
  elif pager.alerts.len > 0:
    pager.alertState = pasAlertOn
    discard pager.status.writeStatusMessage(pager.alerts[0])
    # save to alert history
    if pager.lastAlert != "":
      let hist = pager.getHist(lmAlert)
      hist.add(move(pager.lastAlert))
    pager.lastAlert = move(pager.alerts[0])
    pager.alerts.delete(0)
  else:
    var format = initFormat(defaultColor, defaultColor, {ffReverse})
    pager.alertState = pasNormal
    container.clearHover()
    var msg = ""
    if container.numLines > 0 and pager.config.status.showCursorPosition:
      msg &= $(container.cursory + 1) & "/" & $container.numLines &
        " (" & $container.atPercentOf() & "%)"
    else:
      msg &= "Viewing"
    msg &= " <" & container.getTitle()
    let hover = if pager.config.status.showHoverLink:
      container.getHoverText()
    else:
      ""
    let sl = hover.width()
    var l = 0
    var i = 0
    var maxw = pager.status.grid.width - 1
    if sl > 0:
      maxw -= 2 # -2 for '>' and one blank
    while i < msg.len:
      let pi = i
      let u = msg.nextUTF8(i)
      l += u.width()
      if l + sl > maxw:
        i = pi
        break
    msg.setLen(i)
    if i > 0 and l < maxw:
      msg &= '>'
      if sl > 0 and l < maxw:
        msg &= ' '
    msg &= hover
    if container.numLines == 0:
      msg &= "\tNo Line"
    discard pager.status.writeStatusMessage(msg, format)

# Call refreshStatusMsg if no alert is being displayed on the screen.
# Alerts take precedence over load info, but load info is preserved when no
# pending alerts exist.
proc showAlerts(pager: Pager) =
  if (pager.alertState == pasNormal or
      pager.alertState == pasLoadInfo and pager.alerts.len > 0) and
      pager.inputBuffer == "" and pager.precnum == 0:
    pager.refreshStatusMsg()

proc drawBufferAdvance(s: openArray[char]; bgcolor: CellColor; oi, ox: var int;
    ex: int): string =
  var ls = newStringOfCap(s.len)
  var i = oi
  var x = ox
  while x < ex and i < s.len:
    let pi = i
    let u = s.nextUTF8(i)
    let uw = u.width()
    x += uw
    if u in TabPUARange:
      # PUA tabs can be expanded to hard tabs if
      # * they are correctly aligned
      # * they don't have a bgcolor (terminals will fail to output bgcolor with
      #   tabs)
      if bgcolor == defaultColor and (x and 7) == 0:
        ls &= '\t'
      else:
        for i in 0 ..< uw:
          ls &= ' '
    else:
      for i in pi ..< i:
        ls &= s[i]
  oi = i
  ox = x
  move(ls)

proc drawBuffer(pager: Pager; container: Container; ofile: ChaFile): Opt[void] =
  var format = Format()
  let res = container.readLines(proc(line: SimpleFlexibleLine): Opt[void] =
    var x = 0
    var w = -1
    var i = 0
    var s = ""
    if container.bgcolor != defaultColor and
        (line.formats.len == 0 or line.formats[0].pos > 0):
      let nformat = initFormat(container.bgcolor, defaultColor, {})
      s.processFormat(pager.term, format, nformat)
    for f in line.formats:
      var ff = f.format
      if ff.bgcolor == defaultColor:
        ff.bgcolor = container.bgcolor
      let ls = line.str.drawBufferAdvance(format.bgcolor, i, x, f.pos)
      s.processOutputString(pager.term, ls, w)
      if i < line.str.len:
        s.processFormat(pager.term, format, ff)
    if i < line.str.len:
      let ls = line.str.drawBufferAdvance(format.bgcolor, i, x, int.high)
      s.processOutputString(pager.term, ls, w)
    if container.bgcolor != defaultColor and x < container.width:
      let nformat = initFormat(container.bgcolor, defaultColor, {})
      s.processFormat(pager.term, format, nformat)
      let spaces = ' '.repeat(container.width - x)
      s.processOutputString(pager.term, spaces, w)
    s.processFormat(pager.term, format, Format())
    s &= '\n'
    ofile.write(s)
  )
  ?ofile.flush()
  res

proc redraw(pager: Pager) {.jsfunc.} =
  pager.term.clearCanvas()
  for surface in pager.surfaces.mitems:
    surface.redraw = true
  if pager.container != nil:
    pager.container.redraw = true
    if pager.container.select != nil:
      pager.container.select.redraw = true
  if pager.lineedit != nil:
    pager.lineedit.redraw = true

proc getTempFile(pager: Pager; ext = ""): string =
  result = pager.config.external.tmpdir / "chaptmp" &
    $pager.loader.clientPid & "-" & $pager.tmpfSeq
  if ext != "":
    result &= "."
    result &= ext
  inc pager.tmpfSeq

proc loadCachedImage(pager: Pager; container: Container; image: PosBitmap;
    offx, erry, dispw: int) =
  let bmp = image.bmp
  let cachedImage = CachedImage(
    bmp: bmp,
    width: image.width,
    height: image.height,
    offx: offx,
    erry: erry,
    dispw: dispw
  )
  if not pager.loader.shareCachedItem(bmp.cacheId, pager.loader.clientPid,
      container.process):
    pager.alert("Error: received incorrect cache ID from buffer")
    return
  let imageMode = pager.term.imageMode
  pager.loader.fetch(newRequest(
    "img-codec+" & bmp.contentType.after('/') & ":decode",
    httpMethod = hmPost,
    body = RequestBody(t: rbtCache, cacheId: bmp.cacheId),
    tocache = true
  )).then(proc(res: FetchResult): FetchPromise =
    # remove previous step
    pager.loader.removeCachedItem(bmp.cacheId)
    if res.isErr:
      return nil
    let response = res.get
    let cacheId = response.outputId # set by loader in tocache
    if cachedImage.state == cisCanceled: # container is no longer visible
      pager.loader.removeCachedItem(cacheId)
      return nil
    if image.width == bmp.width and image.height == bmp.height:
      # skip resize
      return newResolvedPromise(res)
    # resize
    # use a temp file, so that img-resize can mmap its output
    let headers = newHeaders(hgRequest, {
      "Cha-Image-Dimensions": $bmp.width & 'x' & $bmp.height,
      "Cha-Image-Target-Dimensions": $image.width & 'x' & $image.height
    })
    let p = pager.loader.fetch(newRequest(
      "cgi-bin:resize",
      httpMethod = hmPost,
      headers = headers,
      body = RequestBody(t: rbtCache, cacheId: cacheId),
      tocache = true
    )).then(proc(res: FetchResult): FetchPromise =
      # ugh. I must remove the previous cached item, but only after
      # resize is done...
      pager.loader.removeCachedItem(cacheId)
      return newResolvedPromise(res)
    )
    response.close()
    return p
  ).then(proc(res: FetchResult) =
    if res.isErr:
      return
    let response = res.get
    let cacheId = response.outputId
    if cachedImage.state == cisCanceled:
      pager.loader.removeCachedItem(cacheId)
      return
    let headers = newHeaders(hgRequest, {
      "Cha-Image-Dimensions": $image.width & 'x' & $image.height
    })
    var url: URL = nil
    case imageMode
    of imSixel:
      url = parseURL0("img-codec+x-sixel:encode")
      headers.add("Cha-Image-Sixel-Halfdump", "1")
      headers.add("Cha-Image-Sixel-Palette", $pager.term.sixelRegisterNum)
      headers.add("Cha-Image-Offset", $offx & 'x' & $erry)
      headers.add("Cha-Image-Crop-Width", $dispw)
    of imKitty:
      url = parseURL0("img-codec+png:encode")
    of imNone: assert false
    let request = newRequest(
      url,
      httpMethod = hmPost,
      headers = headers,
      body = RequestBody(t: rbtCache, cacheId: cacheId),
      tocache = true
    )
    let r = pager.loader.fetch(request)
    response.close()
    r.then(proc(res: FetchResult) =
      # remove previous step
      pager.loader.removeCachedItem(cacheId)
      if res.isErr:
        return
      let response = res.get
      response.close()
      let cacheId = res.get.outputId
      if cachedImage.state == cisCanceled:
        pager.loader.removeCachedItem(cacheId)
        return
      let ps = pager.loader.openCachedItem(cacheId)
      if ps == nil:
        pager.loader.removeCachedItem(cacheId)
        return
      let mem = ps.mmap()
      ps.sclose()
      if mem == nil:
        pager.loader.removeCachedItem(cacheId)
        return
      let blob = newBlob(mem.p, mem.len, "image/x-sixel",
        (proc(opaque, p: pointer) =
          deallocMem(cast[MaybeMappedMemory](opaque))
        ), mem
      )
      container.redraw = true
      cachedImage.data = blob
      cachedImage.state = cisLoaded
      cachedImage.cacheId = cacheId
      cachedImage.transparent =
        response.headers.getFirst("Cha-Image-Sixel-Transparent") == "1"
      let plens = response.headers.getFirst("Cha-Image-Sixel-Prelude-Len")
      cachedImage.preludeLen = parseIntP(plens).get(0)
    )
  )
  container.cachedImages.add(cachedImage)

proc initImages(pager: Pager; container: Container) =
  var newImages: seq[CanvasImage] = @[]
  var redrawNext = false # redraw images if a new one was loaded before
  for image in container.images:
    var erry = 0
    var offx = 0
    var dispw = 0
    if pager.term.imageMode == imSixel:
      let xpx = (image.x - container.fromx) * pager.attrs.ppc
      offx = -min(xpx, 0)
      let maxwpx = pager.bufWidth * pager.attrs.ppc
      dispw = min(image.width + xpx, maxwpx) - xpx
      let ypx = (image.y - container.fromy) * pager.attrs.ppl
      erry = -min(ypx, 0) mod 6
      if dispw <= offx:
        continue
    let cached = container.findCachedImage(image, offx, erry, dispw)
    let imageId = image.bmp.imageId
    if cached == nil:
      pager.loadCachedImage(container, image, offx, erry, dispw)
      continue
    if cached.state != cisLoaded:
      continue # loading
    let canvasImage = pager.term.loadImage(cached.data, container.process,
      imageId, image.x - container.fromx, image.y - container.fromy,
      image.width, image.height, image.x, image.y, pager.bufWidth,
      pager.bufHeight, erry, offx, dispw, image.offx, image.offy,
      cached.preludeLen, cached.transparent, redrawNext)
    if canvasImage != nil:
      newImages.add(canvasImage)
  pager.term.clearImages(pager.bufHeight)
  pager.term.canvasImages = newImages
  pager.term.checkImageDamage(pager.bufWidth, pager.bufHeight)

proc draw(pager: Pager): Opt[void] =
  var redraw = false
  var imageRedraw = false
  var hasMenu = false
  let container = pager.container
  if container != nil:
    if container.redraw:
      let hlcolor = if pager.attrs.colorMode != cmMonochrome:
        cellColor(pager.config.display.highlightColor.rgb)
      else:
        defaultColor
      container.drawLines(pager.display.grid, hlcolor)
      if pager.config.display.highlightMarks:
        container.highlightMarks(pager.display.grid, hlcolor)
      container.redraw = false
      pager.display.redraw = true
      imageRedraw = true
      if container.select != nil:
        container.select.redraw = true
    if (let select = container.select; select != nil and
        (select.redraw or pager.display.redraw)):
      select.drawSelect(pager.display.grid)
      select.redraw = false
      pager.display.redraw = true
      hasMenu = true
    if pager.updateTitle:
      ?pager.term.setTitle(container.getTitle())
      pager.updateTitle = false
  if (let menu = pager.menu; menu != nil and
      (menu.redraw or pager.display.redraw)):
    menu.drawSelect(pager.display.grid)
    menu.redraw = false
    pager.display.redraw = true
    imageRedraw = false
    hasMenu = true
  if pager.display.redraw:
    pager.term.writeGrid(pager.display.grid)
    pager.display.redraw = false
    redraw = true
  if pager.lineedit != nil:
    ?pager.term.disableMouse()
    if pager.lineedit.redraw:
      let x = pager.lineedit.generateOutput()
      pager.term.writeGrid(x, 0, pager.attrs.height - 1)
      pager.lineedit.redraw = false
      redraw = true
  else:
    if pager.config.input.useMouse:
      ?pager.term.enableMouse()
    if pager.status.redraw:
      pager.term.writeGrid(pager.status.grid, 0, pager.attrs.height - 1)
      pager.status.redraw = false
      redraw = true
  if pager.term.imageMode != imNone:
    if imageRedraw:
      # init images only after term canvas has been finalized
      pager.initImages(container)
    elif hasMenu and pager.term.imageMode == imKitty:
      # Kitty can't really deal with text layered both on top of *and*
      # under images.
      #
      # Well, it can, but only in a peculiar way: background color is
      # part of the text layer, so with our image model we'd a) have to
      # specify bgcolor for the menu and b) have to use sub-optimal
      # in-cell positioning. (You'll understand why if you try to
      # implement it.)
      #
      # Ugh. :(
      pager.term.clearImages(pager.bufHeight)
  if redraw:
    ?pager.term.hideCursor()
    ?pager.term.outputGrid()
    if pager.term.imageMode != imNone:
      ?pager.term.outputImages()
  if pager.askPromise != nil:
    ?pager.term.setCursor(pager.askCursor, pager.attrs.height - 1)
  elif pager.lineedit != nil:
    ?pager.term.setCursor(pager.lineedit.getCursorX(), pager.attrs.height - 1)
  elif (let menu = pager.menu; menu != nil):
    ?pager.term.setCursor(menu.getCursorX(), menu.getCursorY())
  elif container != nil:
    if (let select = container.select; select != nil):
      ?pager.term.setCursor(select.getCursorX(), select.getCursorY())
    else:
      ?pager.term.setCursor(container.acursorx, container.acursory)
  if redraw:
    ?pager.term.showCursor()
  ok()

proc writeAskPrompt(pager: Pager; s = "") =
  let maxwidth = pager.status.grid.width - s.width()
  let i = pager.status.writeStatusMessage(pager.askPrompt, maxwidth = maxwidth)
  pager.askCursor = pager.status.writeStatusMessage(s, start = i)

proc askChar(pager: Pager; prompt: string): Promise[string] {.jsfunc.} =
  pager.askPrompt = prompt
  pager.writeAskPrompt()
  pager.askPromise = Promise[string]()
  return pager.askPromise

proc ask(pager: Pager; prompt: string): Promise[bool] {.jsfunc.} =
  return pager.askChar(prompt & " (y/n)").then(proc(s: string): Promise[bool] =
    if s == "y":
      return newResolvedPromise(true)
    if s == "n":
      return newResolvedPromise(false)
    pager.askPromise = Promise[string]()
    return pager.ask(prompt)
  )

proc fulfillAsk(pager: Pager; s: string) =
  let p = pager.askPromise
  pager.askPromise = nil
  pager.askPrompt = ""
  p.resolve(s)

proc setTab(pager: Pager; container: Container; tab: Tab) =
  let removed = container.setTab(tab)
  if removed != nil:
    if removed.next != nil:
      removed.next.prev = removed.prev
    if removed.prev != nil:
      removed.prev.next = removed.next
    if pager.tabHead == removed:
      pager.tabHead = removed.next
    removed.prev = nil
    removed.next = nil
    if pager.tabHead == nil:
      # tab cannot be nil, so create a dummy...
      pager.tabHead = Tab()
      pager.tab = pager.tabHead

proc addContainer(pager: Pager; container: Container) =
  pager.setTab(container, pager.tab)
  pager.setContainer(container)

proc onSetLoadInfo(pager: Pager; container: Container) =
  if pager.alertState != pasAlertOn:
    if container.loadinfo == "":
      pager.alertState = pasNormal
    else:
      discard pager.status.writeStatusMessage(container.loadinfo)
      pager.alertState = pasLoadInfo

proc newContainer(pager: Pager; bufferConfig: BufferConfig;
    loaderConfig: LoaderClientConfig; request: Request; url: URL; title = "";
    redirectDepth = 0; flags: set[ContainerFlag] = {}; contentType = "";
    charsetStack: seq[Charset] = @[]; tab: Tab = nil): Container =
  let stream = pager.loader.startRequest(request, loaderConfig)
  if stream == nil:
    pager.alert("failed to start request for " & $request.url)
    return nil
  pager.loader.registerFun(stream.fd)
  let cacheId = if request.url.schemeType == stCache:
    parseInt32(request.url.pathname).get(-1)
  else:
    -1
  let container = newContainer(
    bufferConfig,
    loaderConfig,
    url,
    request,
    pager.luctx,
    pager.term.attrs,
    title,
    redirectDepth,
    flags,
    contentType,
    charsetStack,
    cacheId,
    pager.config,
    if tab != nil: tab else: pager.tab
  )
  pager.loader.put(ConnectingContainer(
    state: ccsBeforeResult,
    container: container,
    stream: stream
  ))
  pager.onSetLoadInfo(container)
  return container

proc newContainerFrom(pager: Pager; container: Container; contentType: string):
    Container =
  return pager.newContainer(
    container.config,
    container.loaderConfig,
    newRequest("cache:" & $container.cacheId),
    container.url,
    contentType = contentType,
    charsetStack = container.charsetStack
  )

proc findConnectingContainer(pager: Pager; container: Container):
    ConnectingContainer =
  for item in pager.loader.data:
    if item of ConnectingContainer:
      let item = ConnectingContainer(item)
      if item.container == container:
        return item
  return nil

proc dupeBuffer(pager: Pager; container: Container; url: URL): Container =
  let res = container.clone(url, pager.loader)
  if res.p == nil:
    pager.alert("Failed to duplicate buffer.")
    return nil
  pager.addContainer(res.c)
  let nc = res.c
  res.p.then(proc(fd: cint) =
    if fd == -1:
      pager.alert("Failed to duplicate buffer.")
      pager.deleteContainer(nc, nil)
    else:
      pager.connected3(nc, newSocketStream(fd), nil, -1, -1, false)
  )
  return nc

proc dupeBuffer(pager: Pager): Container {.jsfunc.} =
  pager.dupeBuffer(pager.container, pager.container.url)

const OppositeMap = [
  ndPrev: ndNext,
  ndNext: ndPrev,
  ndPrevSibling: ndNextSibling,
  ndNextSibling: ndPrevSibling,
  ndParent: ndNext,
  ndAny: ndAny
]

proc opposite(dir: NavDirection): NavDirection
    {.jsstfunc: "Pager.oppositeDir".} =
  return OppositeMap[dir]

proc revDirection(pager: Pager): NavDirection {.jsfget.} =
  return pager.navDirection.opposite()

proc traverse(pager: Pager; dir: NavDirection): bool {.jsfunc.} =
  pager.navDirection = dir
  if pager.container == nil:
    return false
  let next = pager.container.find(dir)
  if next == nil:
    return false
  pager.setContainer(next)
  true

proc prevBuffer(pager: Pager): bool {.jsfunc.} =
  pager.traverse(ndPrev)

proc nextBuffer(pager: Pager): bool {.jsfunc.} =
  pager.traverse(ndNext)

# Backwards compatibility with the now-removed buffer tree
proc parentBuffer(pager: Pager): bool {.jsfunc.} =
  pager.traverse(ndParent)

proc prevSiblingBuffer(pager: Pager): bool {.jsfunc.} =
  pager.traverse(ndPrevSibling)

proc nextSiblingBuffer(pager: Pager): bool {.jsfunc.} =
  pager.traverse(ndNextSibling)

proc alert*(pager: Pager; msg: string) {.jsfunc.} =
  if msg != "":
    pager.alerts.add(msg)

proc updatePinned(pager: Pager; old, replacement: Container) =
  if pager.pinned.downloads == old:
    pager.pinned.downloads = replacement
  if pager.pinned.console == old:
    pager.pinned.console = replacement
  if pager.pinned.prev == old:
    pager.pinned.prev = replacement

# replace target with container
proc replace(pager: Pager; target, container: Container) =
  assert container != target
  if container.prev != nil:
    container.prev.next = container.next
  if container.next != nil:
    container.next.prev = container.prev
  if target.tab.head == target:
    target.tab.head = container
  #TODO move() when we switch to arc
  container.prev = target.prev
  container.next = target.next
  container.tab = target.tab
  assert container.tab != nil
  target.prev = nil
  target.next = nil
  target.tab = nil
  if container.prev != nil:
    container.prev.next = container
  if container.next != nil:
    container.next.prev = container
  pager.updatePinned(target, container)
  if pager.container == target:
    pager.setContainer(container)

proc deleteContainer(pager: Pager; container, setTarget: Container) =
  if container.loadState == lsLoading:
    container.cancel()
  if container.replaceBackup != nil:
    pager.setContainer(container.replaceBackup)
  elif container.replace != nil:
    pager.replace(container, container.replace)
  if container.sourcepair != nil:
    container.sourcepair.sourcepair = nil
    container.sourcepair = nil
  if container.replaceRef != nil:
    container.replaceRef.replace = nil
    container.replaceRef.replaceBackup = nil
    container.replaceRef = nil
  let wasCurrent = pager.container == container
  pager.setTab(container, nil)
  pager.updatePinned(container, nil)
  if container.replace != nil:
    container.replace = nil
  elif container.replaceBackup != nil:
    container.replaceBackup = nil
  elif wasCurrent:
    pager.setContainer(setTarget)
  if container.process != -1:
    pager.loader.removeCachedItem(container.cacheId)
    pager.loader.removeClient(container.process)
  if container.iface != nil: # fully connected
    let stream = container.iface.stream
    let fd = int(stream.source.fd)
    pager.unregisterFd(fd)
    pager.loader.unset(fd)
    stream.sclose()
    container.iface = nil
  elif (let item = pager.findConnectingContainer(container); item != nil):
    # connecting to URL
    let stream = item.stream
    pager.unregisterFd(int(stream.fd))
    pager.loader.unset(item)
    stream.sclose()

proc discardBuffer(pager: Pager; container = none(Container);
    dir = none(NavDirection)) {.jsfunc.} =
  if dir.isSome:
    pager.navDirection = dir.get.opposite()
  let container = container.get(pager.container)
  let dir = pager.revDirection
  let setTarget = container.find(dir)
  if container == nil or setTarget == nil:
    let s = if dir in {ndNext, ndNextSibling}:
      "No next buffer"
    else:
      "No previous buffer"
    pager.alert(s)
  else:
    pager.deleteContainer(container, setTarget)

proc discardTree(pager: Pager; container = none(Container)) {.jsfunc.} =
  let container = container.get(pager.container)
  if container != nil:
    var c = container.next
    while c != nil:
      let next = c.next
      pager.deleteContainer(c, nil)
      c = next
  else:
    pager.alert("Buffer has no siblings!")

template myExec(cmd: string) =
  discard execl("/bin/sh", "sh", "-c", cstring(cmd), nil)
  exitnow(127)

type EnvVar = tuple[name, value: string]

proc defaultEnv(pager: Pager): seq[EnvVar] =
  let c = pager.container
  if c != nil:
    return @[("CHA_URL", $c.url), ("CHA_CHARSET", $c.charset)]
  return @[]

proc setEnvVars0(pager: Pager; env: openArray[EnvVar]): Opt[void] =
  for it in env:
    ?twtstr.setEnv(it.name, it.value)
  ok()

proc setEnvVars(pager: Pager; env: openArray[EnvVar]) =
  if pager.setEnvVars0(env).isErr:
    pager.alert("Warning: failed to set some environment variables")

# Run process (and suspend the terminal controller).
# For the most part, this emulates system(3).
proc runCommand(pager: Pager; cmd: string; suspend, wait: bool;
    env: openArray[EnvVar]): bool =
  if suspend:
    discard pager.term.quit() #TODO
  var oldint, oldquit, act: Sigaction
  var oldmask, dummy: Sigset
  act.sa_handler = SIG_IGN
  act.sa_flags = SA_RESTART
  if sigemptyset(act.sa_mask) < 0 or
      sigaction(SIGINT, act, oldint) < 0 or
      sigaction(SIGQUIT, act, oldquit) < 0 or
      sigaddset(act.sa_mask, SIGCHLD) < 0 or
      sigprocmask(SIG_BLOCK, act.sa_mask, oldmask) < 0:
    pager.alert("Failed to run process")
    return false
  case (let pid = fork(); pid)
  of -1:
    pager.alert("Failed to run process")
    return false
  of 0:
    if pager.setEnvVars0(env).isErr:
      quit(1)
    act.sa_handler = SIG_DFL
    discard sigemptyset(act.sa_mask)
    discard sigaction(SIGINT, oldint, act)
    discard sigaction(SIGQUIT, oldquit, act)
    discard sigprocmask(SIG_SETMASK, oldmask, dummy);
    if not suspend:
      closeStdin()
      closeStdout()
      closeStderr()
    else:
      if pager.term.istream != nil:
        pager.term.istream.moveFd(STDIN_FILENO)
    myExec(cmd)
  else:
    var wstatus: cint
    while waitpid(pid, wstatus, 0) == -1:
      if errno != EINTR:
        return false
    discard sigaction(SIGINT, oldint, act)
    discard sigaction(SIGQUIT, oldquit, act)
    discard sigprocmask(SIG_SETMASK, oldmask, dummy);
    if suspend:
      if wait:
        discard pager.term.anyKey() #TODO
      discard pager.term.restart() #TODO
    return WIFEXITED(wstatus) and WEXITSTATUS(wstatus) == 0

# Run process, and capture its output.
proc runProcessCapture(cmd: string; outs: var string): bool =
  let file = chafile.popen(cmd, "r")
  if file == nil:
    return false
  let res = file.readAll(outs).isOk
  let rv = file.pclose()
  if not res or rv == -1:
    return false
  return rv == 0

# Run process, and write an arbitrary string into its standard input.
proc runProcessInto(cmd, ins: string): bool =
  let file = chafile.popen(cmd, "w")
  if file == nil:
    return false
  # It is OK if a process refuses to read all input.
  discard file.write(ins)
  let rv = file.pclose()
  if rv == -1:
    return false
  return rv == 0

proc toggleSource(pager: Pager) {.jsfunc.} =
  if pager.container.sourcepair != nil:
    pager.setContainer(pager.container.sourcepair)
  else:
    let ishtml = cfIsHTML notin pager.container.flags
    #TODO I wish I could set the contentType to whatever I wanted, not just HTML
    let contentType = if ishtml:
      "text/html"
    else:
      "text/plain"
    let container = pager.newContainerFrom(pager.container, contentType)
    if container != nil:
      container.sourcepair = pager.container
      pager.navDirection = ndNext
      pager.container.sourcepair = container
      pager.addContainer(container)

proc getCacheFile(pager: Pager; cacheId: int; pid = -1): string {.jsfunc.} =
  let pid = if pid == -1: pager.loader.clientPid else: pid
  return pager.loader.getCacheFile(cacheId, pid)

proc cacheFile(pager: Pager): string {.jsfget.} =
  if pager.container != nil:
    return pager.getCacheFile(pager.container.cacheId)
  return ""

proc getEditorCommand(pager: Pager; file: string; line = 1): string {.jsfunc.} =
  var editor = pager.config.external.editor
  if uqEditor := ChaPath(editor).unquote(""):
    if uqEditor in ["vi", "nvi", "vim", "nvim"]:
      editor = uqEditor & " +%d"
  var canpipe = true
  var s = unquoteCommand(editor, "", file, nil, canpipe, line)
  if s.len > 0 and canpipe:
    # %s not in command; add file name ourselves
    if s[^1] != ' ':
      s &= ' '
    s &= quoteFile(file, qsNormal)
  move(s)

proc openInEditor(pager: Pager; input: var string): bool =
  let tmpf = pager.getTempFile()
  discard mkdir(cstring(pager.config.external.tmpdir), 0o700)
  input &= '\n'
  if chafile.writeFile(tmpf, input, 0o600).isErr:
    pager.alert("failed to write temporary file")
    return false
  let cmd = pager.getEditorCommand(tmpf)
  if cmd == "":
    pager.alert("invalid external.editor command")
  elif pager.runCommand(cmd, suspend = true, wait = false, pager.defaultEnv()):
    if chafile.readFile(tmpf, input).isOk:
      discard unlink(cstring(tmpf))
      if input.len > 0 and input[input.high] == '\n':
        input.setLen(input.high)
      return true
  return false

proc windowChange(pager: Pager) =
  let oldAttrs = pager.attrs
  pager.term.windowChange()
  if pager.attrs == oldAttrs:
    #TODO maybe it's more efficient to let false positives through?
    return
  if pager.lineedit != nil:
    pager.lineedit.windowChange(pager.attrs)
  for st in SurfaceType:
    pager.clear(st)
  for container in pager.containers:
    container.windowChange(pager.attrs)
  if pager.askPrompt != "":
    pager.writeAskPrompt()
  pager.showAlerts()

# Apply siteconf settings to a request.
# Note that this may modify the URL passed.
proc applySiteconf(pager: Pager; url: URL; charsetOverride: Charset;
    loaderConfig: var LoaderClientConfig; ourl: var URL;
    cookieJarId: var string; filterCmd: var string): BufferConfig =
  let host = url.host
  let ctx = pager.jsctx
  result = BufferConfig(
    userStyle: string(pager.config.buffer.userStyle) & '\n',
    refererFrom: pager.config.buffer.refererFrom,
    scripting: pager.config.buffer.scripting,
    charsets: pager.config.encoding.documentCharset,
    images: pager.config.buffer.images,
    styling: pager.config.buffer.styling,
    autofocus: pager.config.buffer.autofocus,
    history: pager.config.buffer.history,
    headless: pager.config.start.headless,
    charsetOverride: charsetOverride,
    metaRefresh: pager.config.buffer.metaRefresh,
    markLinks: pager.config.buffer.markLinks
  )
  loaderConfig = LoaderClientConfig(
    originURL: url,
    defaultHeaders: pager.config.network.defaultHeaders,
    cookiejar: nil,
    proxy: pager.config.network.proxy,
    allowSchemes: @["data", "cache", "stream"],
    cookieMode: pager.config.buffer.cookie,
    insecureSslNoVerify: false
  )
  if pager.config.network.allowHttpFromFile and
      url.schemeType in {stFile, stStream}:
    loaderConfig.allowSchemes.add("http")
    loaderConfig.allowSchemes.add("https")
  cookieJarId = url.host
  let surl = $url
  for sc in pager.config.siteconf.values:
    if sc.url.isSome and not sc.url.get.match(surl):
      continue
    elif sc.host.isSome and not sc.host.get.match(host):
      continue
    if sc.rewriteUrl.isSome:
      let fun = sc.rewriteUrl.get
      var tmpUrl = newURL(url)
      var arg0 = ctx.toJS(tmpUrl)
      let ret = JS_Call(ctx, fun, JS_UNDEFINED, 1, arg0.toJSValueArray())
      if not JS_IsException(ret):
        # Warning: we must only print exceptions if the *call* returned one.
        # Conversion may simply error out because the function didn't return a
        # new URL, and that's fine.
        var nu: URL
        if ctx.fromJS(ret, nu).isOk:
          tmpUrl = nu
      else:
        #TODO should writeException the message to console
        pager.alert("Error rewriting URL: " & ctx.getExceptionMsg())
      JS_FreeValue(ctx, arg0)
      JS_FreeValue(ctx, ret)
      if $tmpUrl != surl:
        ourl = tmpUrl
        return
    if sc.cookie.isSome:
      loaderConfig.cookieMode = sc.cookie.get
    if sc.shareCookieJar.isSome:
      cookieJarId = sc.shareCookieJar.get
    if sc.scripting.isSome:
      result.scripting = sc.scripting.get
    if sc.refererFrom.isSome:
      result.refererFrom = sc.refererFrom.get
    if sc.documentCharset.len > 0:
      result.charsets = sc.documentCharset
    if sc.images.isSome:
      result.images = sc.images.get
    if sc.styling.isSome:
      result.styling = sc.styling.get
    if sc.proxy.isSome:
      loaderConfig.proxy = sc.proxy.get
    if sc.defaultHeaders != nil:
      loaderConfig.defaultHeaders = sc.defaultHeaders
    if sc.insecureSslNoVerify.isSome:
      loaderConfig.insecureSslNoVerify = sc.insecureSslNoVerify.get
    if sc.autofocus.isSome:
      result.autofocus = sc.autofocus.get
    if sc.metaRefresh.isSome:
      result.metaRefresh = sc.metaRefresh.get
    if sc.history.isSome:
      result.history = sc.history.get
    if sc.markLinks.isSome:
      result.markLinks = sc.markLinks.get
    if sc.userStyle.isSome:
      result.userStyle &= string(sc.userStyle.get) & '\n'
    if sc.filterCmd.isSome:
      filterCmd = sc.filterCmd.get
  loaderConfig.allowSchemes.add(pager.config.external.urimethodmap.imageProtos)
  if result.images:
    result.imageTypes = pager.config.external.mimeTypes.image
  result.userAgent = loaderConfig.defaultHeaders.getFirst("User-Agent")

proc applyCookieJar(pager: Pager; loaderConfig: var LoaderClientConfig;
    cookieJarId: string) =
  if loaderConfig.cookieMode != cmNone:
    var cookieJar = pager.cookieJars.getOrDefault(cookieJarId)
    if cookieJar == nil:
      cookieJar = pager.cookieJars.addNew(cookieJarId)
    loaderConfig.cookieJar = cookieJar

proc initGotoURL(pager: Pager; request: Request; charset: Charset;
    referrer: Container; cookie: Option[CookieMode];
    loaderConfig: var LoaderClientConfig; bufferConfig: var BufferConfig;
    filterCmd: var string) =
  pager.navDirection = ndNext
  var cookieJarId: string
  for i in 0 ..< pager.config.network.maxRedirect:
    var ourl: URL = nil
    bufferConfig = pager.applySiteconf(request.url, charset, loaderConfig, ourl,
      cookieJarId, filterCmd)
    if ourl == nil:
      break
    request.url = ourl
  if referrer != nil and referrer.config.refererFrom:
    let referer = $referrer.url
    request.headers["Referer"] = referer
    bufferConfig.referrer = referer
  loaderConfig.cookieMode = cookie.get(loaderConfig.cookieMode)
  pager.applyCookieJar(loaderConfig, cookieJarId)
  if request.url.username != "":
    pager.loader.addAuth(request.url)
  request.url.password = ""

#TODO maybe we should create the container object before starting the
# request?  then we wouldn't have to pass around these million params...
proc gotoURL0(pager: Pager; request: Request; save, history, add: bool;
    bufferConfig: BufferConfig; loaderConfig: LoaderClientConfig;
    title, contentType: string; redirectDepth: int; url: URL;
    replace: Container; redirect: bool; filterCmd: string): Container =
  var flags: set[ContainerFlag] = {}
  if save:
    flags.incl(cfSave)
  if history and bufferConfig.history:
    flags.incl(cfHistory)
  let container = pager.newContainer(
    bufferConfig,
    loaderConfig,
    request,
    # override the URL so that the file name is correct for saveSource
    url = if url != nil: url else: request.url,
    title = title,
    redirectDepth = redirectDepth,
    contentType = contentType,
    flags = flags,
  )
  if filterCmd != "":
    container.filter = BufferFilter(cmd: filterCmd)
  if replace != nil:
    let replaceBackup = if replace.replaceBackup != nil:
      replace.replaceBackup
    else:
      replace.find(ndAny)
    pager.replace(replace, container)
    #TODO surely there's a less convoluted way to achieve this...
    if redirect:
      if replaceBackup != nil:
        replaceBackup.replaceRef = container
        container.replaceBackup = replaceBackup
    else:
      container.replace = replace
      replace.replaceRef = container
  else:
    if add:
      pager.addContainer(container)
  inc pager.numload
  return container

# Load request in a new buffer.
proc gotoURL(pager: Pager; request: Request; contentType = "";
    charset = CHARSET_UNKNOWN; replace: Container = nil;
    redirect: bool = false; redirectDepth = 0; referrer: Container = nil;
    save = false; history = true; url: URL = nil; add = true; title = ""):
    Container =
  var loaderConfig: LoaderClientConfig
  var bufferConfig: BufferConfig
  var filterCmd: string
  pager.initGotoURL(request, charset, referrer, none(CookieMode), loaderConfig,
    bufferConfig, filterCmd)
  return pager.gotoURL0(request, save, history, add, bufferConfig, loaderConfig,
    title, contentType, redirectDepth, url, replace, redirect, filterCmd)

# Check if the user is trying to go to an anchor of the current buffer.
# If yes, the caller need not call gotoURL.
proc gotoURLHash(pager: Pager; request: Request; current: Container;
    save: bool): bool =
  let url = request.url
  if current == nil or not current.url.equals(url, excludeHash = true) or
      url.hash == "" or request.httpMethod != hmGet or save:
    return false
  let anchor = url.hash.substr(1)
  current.iface.gotoAnchor(anchor, false, false).then(
    proc(res: GotoAnchorResult) =
      if res.found:
        discard pager.dupeBuffer(current, url)
      else:
        pager.alert("Anchor " & url.hash & " not found")
  )
  true

proc omniRewrite(pager: Pager; s: string): string =
  for rule in pager.config.omnirule.values:
    if rule.match.get.match(s):
      let fun = rule.substituteUrl.get
      let ctx = pager.jsctx
      var arg0 = ctx.toJS(s)
      let jsRet = JS_Call(ctx, fun, JS_UNDEFINED, 1, arg0.toJSValueArray())
      JS_FreeValue(ctx, arg0)
      var res: string
      if ctx.fromJSFree(jsRet, res).isOk:
        pager.lineHist[lmLocation].add(s)
        return move(res)
      pager.alert("Error in substitution of " & $rule.match & " for " & s &
        ": " & ctx.getExceptionMsg())
  return s

# When the user has passed a partial URL as an argument, they might've meant
# either:
# * file://$PWD/<file>
# * https://<url>
# So we attempt to load both, and see what works.
proc loadURL(pager: Pager; url: string; contentType = "";
    charset = CHARSET_UNKNOWN; history = true) =
  let url0 = pager.omniRewrite(url)
  let url = expandPath(url0)
  if url.len == 0:
    return
  if firstParse := parseURL(url):
    let request = newRequest(firstParse)
    if not pager.gotoURLHash(request, pager.container, save = false):
      discard pager.gotoURL(request, contentType, charset, history = history)
    return
  var urls: seq[URL] = @[]
  if pager.config.network.prependScheme != "" and url[0] != '/':
    if pageurl := parseURL(pager.config.network.prependScheme & url):
      # attempt to load remote page
      urls.add(pageurl)
  let cdir = parseURL0("file://" & percentEncode(myposix.getcwd(),
    LocalPathPercentEncodeSet) & DirSep)
  let localurl = percentEncode(url, LocalPathPercentEncodeSet)
  if newurl := parseURL(localurl, cdir):
    urls.add(newurl) # attempt to load local file
  if urls.len <= 0:
    pager.alert("Invalid URL " & url)
  else:
    let container = pager.gotoURL(newRequest(urls.pop()), contentType,
      charset = charset, history = history)
    container.retry = urls

proc fromJSURL(ctx: JSContext; val: JSValueConst): Opt[URL] =
  var url: URL
  if ctx.fromJS(val, url).isOk:
    return ok(url)
  var s: string
  ?ctx.fromJS(val, s)
  url = ?ctx.newURL(s)
  ok(url)

proc addTab(pager: Pager; c: Container) =
  let tab = Tab()
  if pager.tab.next != nil:
    pager.tab.next.prev = tab
  # add to link first, or setTab dies
  tab.prev = pager.tab
  tab.next = pager.tab.next
  if tab.next != nil:
    tab.next.prev = tab
  pager.tab.next = tab
  pager.setTab(c, tab)
  tab.current = c
  c.queueDraw()
  pager.tab = tab

proc addTab(ctx: JSContext; pager: Pager; buffer: JSValueConst = JS_UNDEFINED):
    JSValue {.jsfunc.} =
  var c: Container
  if ctx.fromJS(buffer, c).isErr:
    let url = if JS_IsUndefined(buffer):
      parseURL0("about:blank")
    else:
      let parsed = ctx.fromJSURL(buffer)
      if parsed.isErr:
        return JS_EXCEPTION
      parsed.get
    c = pager.gotoURL(newRequest(url), history = false, add = false)
  pager.addTab(c)
  JS_UNDEFINED

proc prevTab(pager: Pager) {.jsfunc.} =
  if pager.tab.prev != nil:
    pager.tab = pager.tab.prev
    pager.container.queueDraw()
  else:
    pager.alert("No previous tab")

proc nextTab(pager: Pager) {.jsfunc.} =
  if pager.tab.next != nil:
    pager.tab = pager.tab.next
    pager.container.queueDraw()
  else:
    pager.alert("No next tab")

proc discardTab(pager: Pager) {.jsfunc.} =
  let tab = pager.tab
  if tab.prev != nil or tab.next != nil:
    let prevTab = tab.prev
    let nextTab = tab.next
    var c = tab.head
    while c != nil:
      let next = c.next
      pager.deleteContainer(c, nil)
      c = next
    if prevTab != nil:
      if nextTab != nil:
        nextTab.prev = prevTab
      prevTab.next = nextTab
      pager.tab = prevTab
    else:
      if prevTab != nil:
        prevTab.next = nextTab
      nextTab.prev = prevTab
      if tab == pager.tabHead:
        pager.tabHead = nextTab
      pager.tab = nextTab
    pager.container.queueDraw()
  else:
    pager.alert("This is the last tab")

proc createPipe(pager: Pager): (PosixStream, PosixStream) =
  var pipefds {.noinit.}: array[2, cint]
  if pipe(pipefds) == -1:
    pager.alert("Failed to create pipe")
    return (nil, nil)
  return (newPosixStream(pipefds[0]), newPosixStream(pipefds[1]))

proc readPipe(pager: Pager; contentType: string; cs: Charset; ps: PosixStream;
    title: string) =
  let url = parseURL0("stream:-")
  pager.loader.passFd(url.pathname, ps.fd)
  ps.sclose()
  discard pager.gotoURL(newRequest(url), contentType, cs, title = title)

proc getHistoryURL(pager: Pager): URL {.jsfunc.} =
  let url = parseURL0("stream:history")
  let ps = pager.loader.addPipe(url.pathname)
  if ps == nil:
    return nil
  ps.setCloseOnExec()
  let hist = pager.lineHist[lmLocation]
  if hist.write(ps, sync = false, reverse = true).isErr:
    pager.alert("failed to write history")
  return url

proc addConsoleFile(pager: Pager): Opt[ChaFile] =
  let url = parseURL0("stream:console")
  let ps = pager.loader.addPipe(url.pathname)
  if ps == nil:
    return err()
  ps.setCloseOnExec()
  let file = ?ps.fdopen("w")
  let response = pager.loader.doRequest(newRequest(url))
  if response.res != 0:
    discard file.close()
    return err()
  let cacheId = pager.loader.addCacheFile(response.outputId)
  if cacheId == -1:
    discard file.close()
    return err()
  response.close()
  pager.consoleCacheId = cacheId
  pager.consoleFile = pager.getCacheFile(cacheId)
  ok(file)

const ConsoleTitle = "Browser Console"

proc showConsole(pager: Pager) =
  if pager.consoleCacheId == -1:
    return
  let current = pager.container
  if pager.pinned.console == nil:
    let request = newRequest("cache:" & $pager.consoleCacheId)
    let console = pager.gotoURL(request, "text/plain", CHARSET_UNKNOWN,
      add = false, title = ConsoleTitle)
    pager.pinned.console = console
    pager.addTab(console)
  if current != pager.pinned.console:
    pager.pinned.prev = current
    pager.setContainer(pager.pinned.console)

proc hideConsole(pager: Pager) =
  if pager.consoleCacheId != -1 and pager.container == pager.pinned.console:
    pager.setContainer(pager.pinned.prev)

proc clearConsole(pager: Pager) =
  if pager.consoleCacheId == -1:
    return
  let oldCacheId = pager.consoleCacheId
  let file = pager.addConsoleFile()
  if file.isErr:
    return
  pager.loader.removeCachedItem(oldCacheId)
  pager.console.setStream(file.get)
  if pager.pinned.console != nil:
    let request = newRequest("cache:" & $pager.consoleCacheId)
    let console = pager.gotoURL(request, "text/plain", CHARSET_UNKNOWN,
      replace = pager.pinned.console, add = false, title = ConsoleTitle)
    pager.pinned.console = console
    pager.addTab(console)

proc addConsole(pager: Pager; interactive: bool): Console =
  if interactive and pager.config.start.consoleBuffer:
    if f := pager.addConsoleFile():
      discard f.writeLine("Type (M-c) console.hide() to return to buffer mode.")
      discard f.flush()
      let clearFun = proc() =
        pager.clearConsole()
      let showFun = proc() =
        pager.showConsole()
      let hideFun = proc() =
        pager.hideConsole()
      return newConsole(f, clearFun, showFun, hideFun)
    pager.alert("Failed to open temp file for console")
  return newConsole(cast[ChaFile](stderr))

proc command(pager: Pager) {.jsfunc.} =
  pager.setLineEdit(lmCommand)

proc commandMode(pager: Pager; val: bool) {.jsfset.} =
  pager.commandMode = val
  if val:
    pager.command()

proc checkRegex(pager: Pager; regex: Result[Regex, string]): Option[Regex] =
  if regex.isErr:
    pager.alert("Invalid regex: " & regex.error)
    return none(Regex)
  return some(regex.get)

proc compileSearchRegex(pager: Pager; s: string): Result[Regex, string] =
  return compileSearchRegex(s, pager.config.search.ignoreCase)

proc updateReadLineISearch(pager: Pager; linemode: LineMode) =
  let lineedit = pager.lineedit
  pager.isearchpromise = pager.isearchpromise.then(proc(): EmptyPromise =
    case lineedit.state
    of lesCancel:
      pager.iregex = Result[Regex, string].err("")
      pager.container.popCursorPos()
      pager.container.clearSearchHighlights()
      pager.container.redraw = true
      pager.isearchpromise = newResolvedPromise()
    of lesEdit:
      if lineedit.news != "":
        pager.iregex = pager.compileSearchRegex(lineedit.news)
      pager.container.popCursorPos(true)
      pager.container.pushCursorPos()
      if pager.iregex.isOk:
        pager.container.flags.incl(cfHighlight)
        let wrap = pager.config.search.wrap
        return if linemode == lmISearchF:
          pager.container.cursorNextMatch(pager.iregex.get, wrap, false, 1)
        else:
          pager.container.cursorPrevMatch(pager.iregex.get, wrap, false, 1)
    of lesFinish:
      if lineedit.news != "":
        pager.regex = pager.checkRegex(pager.iregex)
      else:
        pager.searchNext()
      pager.reverseSearch = linemode == lmISearchB
      pager.container.markPos()
      pager.container.clearSearchHighlights()
      pager.container.sendCursorPosition()
      pager.container.redraw = true
      pager.isearchpromise = newResolvedPromise()
    return nil
  )

proc saveTo(pager: Pager; data: LineDataDownload; path: string) =
  if pager.loader.redirectToFile(data.outputId, path, data.url):
    pager.alert("Saving file to " & path)
    pager.loader.resume(data.outputId)
    data.stream.sclose()
    pager.lineData = nil
    if pager.config.external.showDownloadPanel:
      let request = newRequest("about:downloads")
      let downloads = pager.pinned.downloads
      if downloads != nil:
        pager.setContainer(downloads)
      pager.pinned.downloads = pager.gotoURL(request, history = false,
        replace = downloads)
  else:
    pager.ask("Failed to save to " & path & ". Retry?").then(
      proc(x: bool) =
        if x:
          pager.setLineEdit(lmDownload, path)
        else:
          data.stream.sclose()
          pager.lineData = nil
    )

proc updateReadLine(pager: Pager) =
  let lineedit = pager.lineedit
  if pager.linemode in {lmISearchF, lmISearchB}:
    pager.updateReadLineISearch(pager.linemode)
  else:
    case lineedit.state
    of lesEdit: discard
    of lesFinish:
      case pager.linemode
      of lmLocation: pager.loadURL(lineedit.news)
      of lmUsername:
        LineDataAuth(pager.lineData).url.username = lineedit.news
        pager.setLineEdit(lmPassword, hide = true)
      of lmPassword:
        let url = LineDataAuth(pager.lineData).url
        url.password = lineedit.news
        discard pager.gotoURL(newRequest(url), replace = pager.container,
          referrer = pager.container)
        pager.lineData = nil
      of lmCommand:
        pager.scommand = lineedit.news
        if pager.commandMode:
          pager.command()
      of lmBuffer: pager.container.readSuccess(lineedit.news)
      of lmBufferFile:
        if path := ChaPath(lineedit.news).unquote(myposix.getcwd()):
          let ps = newPosixStream(path, O_RDONLY, 0)
          if ps == nil:
            pager.alert("File not found")
            pager.container.readCanceled()
          else:
            var stats: Stat
            if fstat(ps.fd, stats) < 0 or S_ISDIR(stats.st_mode):
              pager.alert("Not a file: " & path)
            else:
              let name = path.afterLast('/')
              pager.container.readSuccess(name, ps.fd)
            ps.sclose()
        else:
          pager.alert("Invalid path: " & lineedit.news)
          pager.container.readCanceled()
      of lmSearchF, lmSearchB:
        if lineedit.news != "":
          let regex = pager.compileSearchRegex(lineedit.news)
          pager.regex = pager.checkRegex(regex)
        pager.reverseSearch = pager.linemode == lmSearchB
        pager.searchNext()
      of lmGotoLine:
        pager.container.gotoLine(lineedit.news)
      of lmDownload:
        let data = LineDataDownload(pager.lineData)
        let path = ChaPath(lineedit.news).unquote(myposix.getcwd())
        if path.isErr:
          pager.alert(path.error)
        else:
          let path = path.get
          if fileExists(path):
            pager.ask("Override file " & path & "?").then(
              proc(x: bool) =
                if x:
                  pager.saveTo(data, path)
                else:
                  pager.setLineEdit(lmDownload, path)
            )
          else:
            pager.saveTo(data, path)
      of lmMailcap:
        var mailcap = Mailcap.default
        let res = mailcap.parseMailcap(lineedit.news, "<input>")
        let data = LineDataMailcap(pager.lineData)
        if res.isOk and mailcap.len == 1:
          let res = pager.runMailcap(data.container.url, data.ostream,
            data.response.outputId, data.contentType, mailcap[0])
          pager.connected2(data.container, res, data.response)
        else:
          if res.isErr:
            pager.alert(res.error)
          pager.askMailcap(data.container, data.ostream, data.contentType,
            data.i, data.response, data.sx)
      of lmISearchF, lmISearchB, lmAlert: discard
    of lesCancel:
      case pager.linemode
      of lmUsername, lmPassword: pager.discardBuffer()
      of lmBuffer: pager.container.readCanceled()
      of lmCommand: pager.commandMode = false
      of lmDownload:
        let data = LineDataDownload(pager.lineData)
        data.stream.sclose()
      of lmMailcap:
        let data = LineDataMailcap(pager.lineData)
        pager.askMailcap(data.container, data.ostream, data.contentType,
          data.i, data.response, data.sx)
      else: discard
      pager.lineData = nil
  if lineedit.state in {lesCancel, lesFinish} and pager.lineedit == lineedit:
    pager.lineedit = nil

proc loadSubmit(pager: Pager; s: string) {.jsfunc.} =
  pager.loadURL(s)

# Open a URL prompt and visit the specified URL.
proc load(ctx: JSContext; pager: Pager; val: JSValueConst = JS_NULL): Opt[void]
    {.jsfunc.} =
  if JS_IsNull(val):
    pager.setLineEdit(lmLocation, $pager.container.url)
  else:
    var s: string
    ?ctx.fromJS(val, s)
    if s.len > 0 and s[^1] == '\n':
      const msg = "pager.load(\"...\\n\") is deprecated, use loadSubmit instead"
      if s.len > 1:
        pager.alert(msg)
        pager.loadURL(s[0..^2])
    else:
      pager.setLineEdit(lmLocation, s)
  ok()

# Go to specific URL (for JS)
type GotoURLDict = object of JSDict
  contentType {.jsdefault.}: Option[string]
  replace {.jsdefault.}: Option[Container]
  save {.jsdefault.}: bool
  history {.jsdefault.}: bool
  scripting {.jsdefault.}: Option[ScriptingMode]
  cookie {.jsdefault.}: Option[CookieMode]

proc jsGotoURL(ctx: JSContext; pager: Pager; v: JSValueConst;
    t = GotoURLDict()): Opt[Container] {.jsfunc: "gotoURL".} =
  var request: Request = nil
  var jsRequest: JSRequest = nil
  if ctx.fromJS(v, jsRequest).isOk:
    request = jsRequest.request
  else:
    let url = ?ctx.fromJSURL(v)
    request = newRequest(url)
  var loaderConfig: LoaderClientConfig
  var bufferConfig: BufferConfig
  var filterCmd: string
  pager.initGotoURL(request, CHARSET_UNKNOWN, referrer = nil, t.cookie,
    loaderConfig, bufferConfig, filterCmd)
  bufferConfig.scripting = t.scripting.get(bufferConfig.scripting)
  ok(pager.gotoURL0(request, t.save, t.history, add = true, bufferConfig,
    loaderConfig, title = "", t.contentType.get(""), redirectDepth = 0,
    url = nil, t.replace.get(nil), redirect = false, filterCmd))

# Reload the page in a new buffer, then kill the previous buffer.
proc reload(pager: Pager) {.jsfunc.} =
  let old = pager.container
  let container = pager.gotoURL(newRequest(pager.container.url),
    pager.container.contentType, replace = old,
    history = cfHistory in old.flags)
  container.copyCursorPos(old)

type ExternDict = object of JSDict
  env {.jsdefault: JS_UNDEFINED.}: JSValueConst
  suspend {.jsdefault: true.}: bool
  wait {.jsdefault: false.}: bool

proc readEnvSeq(ctx: JSContext; pager: Pager; val: JSValueConst;
    s: var seq[EnvVar]): Opt[void] =
  if JS_IsUndefined(val):
    s = pager.defaultEnv()
    return ok()
  var record: JSKeyValuePair[string, string]
  ?ctx.fromJS(val, record)
  s = move(record.s)
  ok()

#TODO we should have versions with retval as int?
# or perhaps just an extern2 that can use JS readablestreams and returns
# retval, then deprecate the rest.
proc extern(ctx: JSContext; pager: Pager; cmd: string;
    t = ExternDict(env: JS_UNDEFINED, suspend: true)): Opt[bool] {.jsfunc.} =
  var env = newSeq[EnvVar]()
  ?ctx.readEnvSeq(pager, t.env, env)
  ok(pager.runCommand(cmd, t.suspend, t.wait, env))

proc externCapture(ctx: JSContext; pager: Pager; cmd: string): JSValue
    {.jsfunc.} =
  pager.setEnvVars(pager.defaultEnv())
  var s: string
  if runProcessCapture(cmd, s):
    return ctx.toJS(s)
  return JS_NULL

proc externInto(pager: Pager; cmd, ins: string): bool {.jsfunc.} =
  pager.setEnvVars(pager.defaultEnv())
  return runProcessInto(cmd, ins)

proc jsQuit*(ctx: JSContext; pager: Pager; code = 0): JSValue =
  pager.exitCode = int(code)
  JS_ThrowInternalError(ctx, "interrupted")
  let ex = JS_GetException(ctx)
  JS_SetUncatchableError(ctx, ex)
  return JS_Throw(ctx, ex)

proc clipboardWrite(ctx: JSContext; pager: Pager; s: string): JSValue
    {.jsfunc.} =
  if res := pager.term.sendOSC52(s):
    if res:
      return JS_TRUE
    return ctx.toJS(pager.externInto(pager.config.external.copyCmd, s))
  return ctx.jsQuit(pager, 1)

proc externFilterSource(pager: Pager; cmd: string; c = none(Container);
    contentType = none(string)) {.jsfunc.} =
  let fromc = c.get(pager.container)
  let fallback = if fromc.contentType != "":
    fromc.contentType
  else:
    "text/plain"
  let contentType = contentType.get(fallback)
  let container = pager.newContainerFrom(fromc, contentType)
  if container != nil:
    pager.addContainer(container)
    container.filter = BufferFilter(cmd: cmd)

# Execute cmd, with ps moved onto stdin, os onto stdout, and stderr closed.
# ps remains open, but os is consumed.
proc execPipe(pager: Pager; cmd: string; ps, os: PosixStream): int =
  var oldint, oldquit: Sigaction
  var act = Sigaction(sa_handler: SIG_IGN, sa_flags: SA_RESTART)
  var oldmask, dummy: Sigset
  if sigemptyset(act.sa_mask) < 0 or
      sigaction(SIGINT, act, oldint) < 0 or
      sigaction(SIGQUIT, act, oldquit) < 0 or
      sigaddset(act.sa_mask, SIGCHLD) < 0 or
      sigprocmask(SIG_BLOCK, act.sa_mask, oldmask) < 0:
    pager.alert("Failed to run process (errno " & $errno & ")")
    return -1
  case (let pid = fork(); pid)
  of -1:
    pager.alert("Failed to fork process")
    return -1
  of 0:
    act.sa_handler = SIG_DFL
    discard sigemptyset(act.sa_mask)
    discard sigaction(SIGINT, oldint, act)
    discard sigaction(SIGQUIT, oldquit, act)
    discard sigprocmask(SIG_SETMASK, oldmask, dummy);
    ps.moveFd(STDIN_FILENO)
    os.moveFd(STDOUT_FILENO)
    closeStderr()
    myExec(cmd)
  else:
    discard sigaction(SIGINT, oldint, act)
    discard sigprocmask(SIG_SETMASK, oldmask, dummy);
    os.sclose()
    return pid

proc execPipeWait(pager: Pager; cmd: string; ps, os: PosixStream): int =
  let pid = pager.execPipe(cmd, ps, os)
  if pid == -1:
    return 1
  var wstatus = cint(0)
  while waitpid(Pid(pid), wstatus, 0) == -1:
    if errno != EINTR:
      break
  if WIFSIGNALED(wstatus):
    return 128 + WTERMSIG(wstatus)
  return WEXITSTATUS(wstatus)

# Pipe output of an x-ansioutput mailcap command to the text/x-ansi handler.
proc ansiDecode(pager: Pager; url: URL; ishtml: bool; istream: PosixStream):
    PosixStream =
  let i = pager.config.external.mailcap.findMailcapEntry("text/x-ansi", "", url)
  if i == -1:
    pager.alert("No text/x-ansi entry found")
    return nil
  var canpipe = true
  let cmd = unquoteCommand(pager.config.external.mailcap[i].cmd, "text/x-ansi",
    "", url, canpipe)
  if not canpipe:
    pager.alert("Error: could not pipe to text/x-ansi, decoding as text/plain")
    return nil
  let (pins, pouts) = pager.createPipe()
  if pins == nil:
    return nil
  pins.setCloseOnExec()
  let pid = pager.execPipe(cmd, istream, pouts)
  if pid == -1:
    return nil
  return pins

# Pipe input into the mailcap command, and discard its output.
# If needsterminal, leave stderr and stdout open and wait for the process.
proc runMailcapWritePipe(pager: Pager; stream: PosixStream;
    needsterminal: bool; cmd: string) =
  if needsterminal:
    discard pager.term.quit() #TODO
  let pid = fork()
  if pid == -1:
    pager.alert("Error: failed to fork mailcap write process")
  elif pid == 0:
    # child process
    stream.moveFd(STDIN_FILENO)
    if not needsterminal:
      closeStdout()
      closeStderr()
    myExec(cmd)
  else:
    # parent
    stream.sclose()
    if needsterminal:
      var x: cint
      discard waitpid(pid, x, 0)
      discard pager.term.restart() #TODO

proc writeToFile(istream: PosixStream; outpath: string): bool =
  let ps = newPosixStream(outpath, O_WRONLY or O_CREAT, 0o600)
  if ps == nil:
    return false
  var buffer {.noinit.}: array[4096, uint8]
  var n = 0
  while (n = istream.readData(buffer); n > 0):
    if not ps.writeDataLoop(buffer.toOpenArray(0, n - 1)):
      n = -1
      break
  ps.sclose()
  n == 0

# Save input in a file, run the command, and redirect its output to a
# new buffer.
# needsterminal is ignored.
proc runMailcapReadFile(pager: Pager; stream: PosixStream;
    cmd, outpath: string; pouts: PosixStream): int =
  case (let pid = fork(); pid)
  of -1:
    pager.alert("Error: failed to fork mailcap read process")
    pouts.sclose()
    return pid
  of 0:
    # child process
    closeStderr()
    pager.term.istream.sclose()
    pager.term.ostream.sclose()
    if not stream.writeToFile(outpath):
      quit(1)
    stream.sclose()
    let ps = newPosixStream("/dev/null")
    let ret = pager.execPipeWait(cmd, ps, pouts)
    discard unlink(cstring(outpath))
    quit(ret)
  else: # parent
    pouts.sclose()
    return pid

# Save input in a file, run the command, and discard its output.
# If needsterminal, leave stderr and stdout open and wait for the process.
proc runMailcapWriteFile(pager: Pager; stream: PosixStream;
    needsterminal: bool; cmd, outpath: string) =
  discard mkdir(cstring(pager.config.external.tmpdir), 0o700)
  if needsterminal:
    discard pager.term.quit() #TODO
    let os = newPosixStream(dup(pager.term.ostream.fd))
    if not stream.writeToFile(outpath) or os.fd == -1:
      if os.fd != -1:
        os.sclose()
      discard pager.term.restart() #TODO
      pager.alert("Error: failed to write file for mailcap process")
    else:
      let ret = pager.execPipeWait(cmd, pager.term.istream, os)
      discard unlink(cstring(outpath))
      discard pager.term.restart() #TODO
      if ret != 0:
        pager.alert("Error: " & cmd & " exited with status " & $ret)
  else:
    # don't block
    let pid = fork()
    if pid == 0:
      # child process
      closeStderr()
      pager.term.istream.sclose()
      pager.term.ostream.sclose()
      if not stream.writeToFile(outpath):
        quit(1)
      stream.sclose()
      let ps = newPosixStream("/dev/null")
      let os = newPosixStream("/dev/null", O_WRONLY)
      let ret = pager.execPipeWait(cmd, ps, os)
      discard unlink(cstring(outpath))
      quit(ret)
    # parent
    stream.sclose()

proc filterBuffer(pager: Pager; ps: PosixStream; cmd: string): PosixStream =
  pager.setEnvVars(pager.defaultEnv())
  let (pins, pouts) = pager.createPipe()
  if pins == nil:
    return nil
  pins.setCloseOnExec()
  let pid = pager.execPipe(cmd, ps, pouts)
  if pid == -1:
    return nil
  return pins

# Search for a mailcap entry, and if found, execute the specified command
# and pipeline the input and output appropriately.
# There are four possible outcomes:
# * pipe stdin, discard stdout
# * pipe stdin, read stdout
# * write to file, run, discard stdout
# * write to file, run, read stdout
# If needsterminal is specified, and stdout is not being read, then the
# pager is suspended until the command exits.
#TODO add support for edit/compose, better error handling
proc runMailcap(pager: Pager; url: URL; stream: PosixStream;
    istreamOutputId: int; contentType: string; entry: MailcapEntry):
    MailcapResult =
  let ext = url.pathname.afterLast('.')
  var outpath = pager.getTempFile(ext)
  if entry.nametemplate != "":
    outpath = unquoteCommand(entry.nametemplate, contentType, outpath, url)
  var canpipe = true
  let cmd = unquoteCommand(entry.cmd, contentType, outpath, url, canpipe)
  let ishtml = mfHtmloutput in entry.flags
  let needsterminal = mfNeedsterminal in entry.flags
  if twtstr.setEnv("MAILCAP_URL", $url).isErr:
    pager.alert("failed to set env vars")
  block needsConnect:
    if entry.flags * {mfCopiousoutput, mfHtmloutput, mfAnsioutput,
        mfSaveoutput} == {}:
      # No output. Resume here, so that blocking needsterminal filters work.
      pager.loader.resume(istreamOutputId)
      if canpipe:
        pager.runMailcapWritePipe(stream, needsterminal, cmd)
      else:
        pager.runMailcapWriteFile(stream, needsterminal, cmd, outpath)
      # stream is already closed
      break needsConnect # never connect here, since there's no output
    var (pins, pouts) = pager.createPipe()
    if pins == nil:
      stream.sclose() # connect: false implies that we consumed the stream
      break needsConnect
    pins.setCloseOnExec()
    let pid = if canpipe:
      # Pipe input into the mailcap command, then read its output into a buffer.
      # needsterminal is ignored.
      pager.execPipe(cmd, stream, pouts)
    else:
      pager.runMailcapReadFile(stream, cmd, outpath, pouts)
    stream.sclose()
    if pid == -1:
      break needsConnect
    if not ishtml and mfAnsioutput in entry.flags:
      pins = pager.ansiDecode(url, ishtml, pins)
    twtstr.unsetEnv("MAILCAP_URL")
    let url = parseURL0("stream:" & $pid)
    pager.loader.passFd(url.pathname, pins.fd)
    pins.sclose()
    let response = pager.loader.doRequest(newRequest(url))
    var flags = {cmfConnect, cmfFound, cmfRedirected}
    if mfNeedsstyle in entry.flags or mfAnsioutput in entry.flags:
      # ansi always needs styles
      flags.incl(cmfNeedsstyle)
    if mfNeedsimage in entry.flags:
      flags.incl(cmfNeedsimage)
    if mfSaveoutput in entry.flags:
      flags.incl(cmfSaveoutput)
    if ishtml:
      flags.incl(cmfHTML)
    return MailcapResult(
      flags: flags,
      ostream: response.body,
      ostreamOutputId: response.outputId
    )
  twtstr.unsetEnv("MAILCAP_URL")
  return MailcapResult(flags: {cmfFound})

proc redirectTo(pager: Pager; container: Container; request: Request) =
  let save = cfSave in container.flags
  if not pager.gotoURLHash(request, pager.container, save):
    let nc = pager.gotoURL(request, replace = container, redirect = true,
      redirectDepth = container.redirectDepth + 1, referrer = container,
      save = save, history = cfHistory in container.flags)
    if nc != nil:
      nc.loadinfo = "Redirecting to " & $request.url
      pager.onSetLoadInfo(nc)
  dec pager.numload

proc fail(pager: Pager; container: Container; errorMessage: string) =
  dec pager.numload
  pager.deleteContainer(container, container.find(ndAny))
  if container.retry.len > 0:
    discard pager.gotoURL(newRequest(container.retry.pop()),
      container.contentType, history = cfHistory in container.flags)
  else:
    # Add to the history anyway, so that the user can edit the URL.
    if cfHistory in container.flags:
      pager.lineHist[lmLocation].add($container.url)
    # Try to fit a meaningful part of the URL and the error message too.
    # URLs can't include double-width chars, so we can just use string
    # length for those.  (However, error messages can.)
    var msg = "Can't load " & $container.url
    let ew = errorMessage.width() + 3
    if msg.len + ew > pager.attrs.width:
      msg.setLen(max(pager.attrs.width - ew, pager.attrs.width div 3))
      if msg.len > 0:
        msg[^1] = '$'
    msg &= " (" & errorMessage & ')'
    pager.alert(msg)

proc redirect(pager: Pager; container: Container; response: Response;
    request: Request) =
  # if redirection fails, then we need some other container to move to...
  let failTarget = container.find(ndAny)
  # still need to apply response, or we lose cookie jars.
  container.applyResponse(response, pager.config.external.mimeTypes)
  if container.redirectDepth < pager.config.network.maxRedirect:
    if container.url.scheme == request.url.scheme or
        container.url.schemeType == stCgiBin or
        container.url.schemeType == stHttp and
          request.url.schemeType == stHttps or
        container.url.schemeType == stHttps and
          request.url.schemeType == stHttp:
      pager.redirectTo(container, request)
    #TODO perhaps make following behavior configurable?
    elif request.url.schemeType == stCgiBin:
      pager.alert("Blocked redirection attempt to " & $request.url)
    else:
      let url = request.url
      pager.ask("Warning: switch protocols? " & $url).then(proc(x: bool) =
        if x:
          pager.redirectTo(container, request)
      )
  else:
    pager.alert("Error: maximum redirection depth reached")
    pager.deleteContainer(container, failTarget)

proc askDownloadPath(pager: Pager; container: Container; stream: PosixStream;
    response: Response) =
  var buf = string(pager.config.external.downloadDir)
  let pathname = container.url.pathname
  if buf.len == 0 or buf[^1] != '/':
    buf &= '/'
  if pathname[^1] == '/':
    buf &= "index.html"
  else:
    buf &= container.url.pathname.afterLast('/').percentDecode()
  pager.setLineEdit(lmDownload, buf)
  pager.lineData = LineDataDownload(
    outputId: response.outputId,
    stream: stream,
    url: container.url
  )
  pager.deleteContainer(container, container.find(ndAny))
  pager.refreshStatusMsg()
  dec pager.numload

proc connected2(pager: Pager; container: Container; res: MailcapResult;
    response: Response) =
  if cfSave in container.flags or cmfSaveoutput in res.flags:
    container.flags.incl(cfSave) # saveoutput doesn't include it before
    # resume the ostream
    pager.loader.resume(res.ostreamOutputId)
    pager.askDownloadPath(container, res.ostream, response)
  elif cmfConnect in res.flags:
    if cmfHTML in res.flags:
      container.flags.incl(cfIsHTML)
    else:
      container.flags.excl(cfIsHTML)
    if cmfNeedsstyle in res.flags: # override
      container.config.styling = true
    if cmfNeedsimage in res.flags: # override
      container.config.images = true
    # buffer now actually exists; create a process for it
    var attrs = pager.attrs
    # subtract status line height
    attrs.height -= 1
    attrs.heightPx -= attrs.ppl
    var url = container.url
    if url.username != "" or url.password != "":
      url = newURL(url)
      url.username = ""
      url.password = ""
    let (pid, cstream) = pager.forkserver.forkBuffer(
      container.config,
      url,
      attrs,
      cmfHTML in res.flags,
      container.charsetStack,
      container.contentType
    )
    if pid == -1:
      res.ostream.sclose()
      pager.fail(container, "Error forking new process for buffer")
    else:
      container.process = pid
      if container.replace != nil:
        pager.deleteContainer(container.replace, container.find(ndAny))
        container.replace = nil
      pager.connected3(container, cstream, res.ostream, response.outputId,
        res.ostreamOutputId, cmfRedirected in res.flags)
  else:
    dec pager.numload
    pager.deleteContainer(container, container.find(ndAny))
    pager.refreshStatusMsg()

proc connected3(pager: Pager; container: Container; stream: SocketStream;
    ostream: PosixStream; istreamOutputId, ostreamOutputId: int;
    redirected: bool) =
  let loader = pager.loader
  let cstream = loader.addClient(container.process, container.loaderConfig,
    container.clonedFrom)
  if cstream == nil:
    stream.sclose()
    ostream.sclose()
    pager.alert("failed to create new loader client")
    return
  let bufStream = newBufStream(stream, proc(fd: int) =
    pager.pollData.unregister(fd)
    pager.pollData.register(fd, POLLIN or POLLOUT))
  if istreamOutputId != -1: # new buffer
    if container.cacheId == -1:
      container.cacheId = loader.addCacheFile(istreamOutputId)
    if container.request.url.schemeType == stCache:
      # loading from cache; now both the buffer and us hold a new reference
      # to the cached item, but it's only shared with the buffer. add a
      # pager ref too.
      discard loader.shareCachedItem(container.cacheId, loader.clientPid)
    let pid = container.process
    var outCacheId = container.cacheId
    if not redirected:
      discard loader.shareCachedItem(container.cacheId, pid)
      loader.resume(istreamOutputId)
    else:
      outCacheId = loader.addCacheFile(ostreamOutputId)
      discard loader.shareCachedItem(outCacheId, pid)
      loader.removeCachedItem(outCacheId)
      loader.resume([istreamOutputId, ostreamOutputId])
    stream.withPacketWriterFire w: # if EOF, poll will notify us later
      w.swrite(outCacheId)
      w.sendFd(cstream.fd)
      # pass down ostream
      w.sendFd(ostream.fd)
    ostream.sclose()
  else: # cloned buffer
    stream.withPacketWriterFire w: # if EOF, poll will notify us later
      w.sendFd(cstream.fd)
    # buffer is cloned, just share the parent's cached source
    discard loader.shareCachedItem(container.cacheId, container.process)
    # also add a reference here; it will be removed when the container is
    # deleted
    discard loader.shareCachedItem(container.cacheId, loader.clientPid)
  container.setStream(bufStream)
  cstream.sclose()
  loader.put(ContainerData(stream: stream, container: container))
  pager.pollData.register(stream.fd, POLLIN)
  # clear replacement references, because we can't fail to load this
  # buffer anymore
  container.replaceRef = nil
  container.replace = nil
  container.replaceBackup = nil

proc saveEntry(pager: Pager; entry: MailcapEntry) =
  if not pager.config.external.autoMailcap.saveEntry(entry):
    pager.alert("Could not write to " & pager.config.external.autoMailcap.path)

proc askMailcapMsg(pager: Pager; shortContentType: string; i: int; sx: var int;
    prev, next: int): string =
  var msg = "Open " & shortContentType & " as (shift=always): (t)ext, (s)ave"
  if i != -1:
    msg &= ", (r)un \"" & pager.config.external.mailcap[i].cmd.strip() & '"'
  msg &= ", (e)dit entry, (C-c)ancel"
  if prev != -1:
    msg &= ", (p)rev"
  if next != -1:
    msg &= ", (n)ext"
  msg = msg.toValidUTF8()
  var mw = msg.width()
  var j = 0
  var x = 0
  while j < msg.len:
    let pj = j
    let px = x
    x += msg.nextUTF8(j).width()
    if mw - px <= pager.attrs.width or x > sx:
      j = pj
      sx = px
      break
  msg.substr(j)

proc askMailcap(pager: Pager; container: Container; ostream: PosixStream;
    contentType: string; i: int; response: Response; sx: int) =
  var sx = sx
  var prev = -1
  var next = -1
  if i != -1:
    prev = pager.config.external.mailcap.findPrevMailcapEntry(contentType, "",
      container.url, i)
    next = pager.config.external.mailcap.findMailcapEntry(contentType, "",
      container.url, i)
  let msg = pager.askMailcapMsg(container.contentType.untilLower(';'), i, sx,
    prev, next)
  pager.askChar(msg).then(proc(s: string) =
    var retry = true
    var sx = sx
    var i = i
    var c = '\0'
    if s.len == 1:
      c = s[0]
    case c
    of '\3', 'q':
      retry = false
      pager.alert("Canceled")
      ostream.sclose()
      pager.connected2(container, MailcapResult(), response)
    of 'e':
      #TODO no idea how to implement save :/
      # probably it should run use a custom reader that runs through
      # auto.mailcap clearing any other entry. but maybe it's better to
      # add a full blown editor like w3m has at that point...
      retry = false
      var s = container.contentType.untilLower(';') & ';'
      if i != -1:
        s = $pager.config.external.mailcap[i]
        while s.len > 0 and s[^1] == '\n':
          s.setLen(s.high)
      pager.setLineEdit(lmMailcap, s)
      pager.lineData = LineDataMailcap(
        container: container,
        ostream: ostream,
        contentType: contentType,
        i: i,
        response: response,
        sx: sx
      )
    of 't', 'T':
      retry = false
      pager.connected2(container, MailcapResult(
        flags: {cmfConnect},
        ostream: ostream
      ), response)
      if c == 'T':
        pager.saveEntry(MailcapEntry(
          t: container.contentType.untilLower(';'),
          cmd: "exec cat",
          flags: {mfCopiousoutput}
        ))
    of 's', 'S':
      retry = false
      container.flags.incl(cfSave)
      pager.connected2(container, MailcapResult(
        flags: {cmfConnect},
        ostream: ostream
      ), response)
      if c == 'S':
        pager.saveEntry(MailcapEntry(
          t: container.contentType.untilLower(';'),
          cmd: "exec cat",
          flags: {mfSaveoutput}
        ))
    of 'r', 'R':
      retry = i == -1
      if not retry:
        let res = pager.runMailcap(container.url, ostream, response.outputId,
          contentType, pager.config.external.mailcap[i])
        pager.connected2(container, res, response)
        if c == 'R':
          pager.saveEntry(pager.config.external.mailcap[i])
    of 'p', 'k':
      if prev != -1:
        i = prev
    of 'n', 'j':
      if next != -1:
        i = next
    of 'h': dec sx
    of 'l': inc sx
    of '^', '\1': sx = 0
    of '$', '\5': sx = int.high
    else: discard
    if retry:
      pager.askMailcap(container, ostream, contentType, i, response, max(sx, 0))
  )

proc connected(pager: Pager; container: Container; response: Response) =
  var istream = response.body
  container.applyResponse(response, pager.config.external.mimeTypes)
  if response.status == 401: # unauthorized
    pager.setLineEdit(lmUsername, container.url.username)
    pager.lineData = LineDataAuth(url: newURL(container.url))
    istream.sclose()
    return
  # This forces client to ask for confirmation before quitting.
  pager.hasload = true
  if cfHistory in container.flags:
    pager.lineHist[lmLocation].add($container.url)
  # contentType must have been set by applyResponse.
  let shortContentType = container.contentType.until(';')
  var contentType = container.contentType
  if shortContentType.startsWithIgnoreCase("text/"):
    # prepare content type for %{charset}
    contentType.setContentTypeAttr("charset", $container.charset)
  if container.filter != nil:
    istream = pager.filterBuffer(istream, container.filter.cmd)
  if shortContentType.equalsIgnoreCase("text/html"):
    pager.connected2(container, MailcapResult(
      flags: {cmfConnect, cmfHTML, cmfFound},
      ostream: istream
    ), response)
  elif shortContentType.equalsIgnoreCase("text/plain") or
      cfSave in container.flags:
    pager.connected2(container, MailcapResult(
      flags: {cmfConnect, cmfFound},
      ostream: istream
    ), response)
  else:
    let i = pager.config.external.autoMailcap.entries
      .findMailcapEntry(contentType, "", container.url)
    if i != -1:
      let res = pager.runMailcap(container.url, istream, response.outputId,
        contentType, pager.config.external.autoMailcap.entries[i])
      pager.connected2(container, res, response)
    else:
      let i = pager.config.external.mailcap.findMailcapEntry(contentType, "",
        container.url)
      if i == -1 and shortContentType.isTextType():
        pager.connected2(container, MailcapResult(
          flags: {cmfConnect, cmfFound},
          ostream: istream
        ), response)
      else:
        pager.askMailcap(container, istream, contentType, i, response, 0)

proc unregisterFd(pager: Pager; fd: int) =
  pager.pollData.unregister(fd)
  pager.loader.unregistered.add(fd)

proc handleRead(pager: Pager; item: ConnectingContainer) =
  let container = item.container
  let stream = item.stream
  case item.state
  of ccsBeforeResult:
    var res = int(ceLoaderGone)
    var msg: string
    stream.withPacketReaderFire r:
      r.sread(res)
      if res == 0: # continue
        r.sread(item.outputId)
        inc item.state
        container.loadinfo = "Connected to " & $container.url &
          ". Downloading..."
        pager.onSetLoadInfo(container)
      else:
        r.sread(msg)
    if res != 0: # done
      if msg == "":
        msg = getLoaderErrorMessage(res)
      pager.fail(container, msg)
  of ccsBeforeStatus:
    let response = newResponse(item.res, container.request, stream,
      item.outputId)
    stream.withPacketReaderFire r:
      r.sread(response.status)
      r.sread(response.headers)
    # done
    pager.loader.unset(item)
    pager.unregisterFd(int(item.stream.fd))
    let redirect = response.getRedirect(container.request)
    if redirect != nil:
      stream.sclose()
      pager.redirect(container, response, redirect)
    else:
      pager.connected(container, response)

proc handleError(pager: Pager; item: ConnectingContainer) =
  pager.fail(item.container, "loader died while loading")

proc metaRefresh(pager: Pager; container: Container; n: int; url: URL) =
  let ctx = pager.jsctx
  let fun = ctx.newFunction(["url", "replace"],
    """
if (replace.alive) {
  const c2 = pager.gotoURL(url, {replace: replace, history: replace.history});
  c2.copyCursorPos(replace)
}
""")
  let args = [ctx.toJS(url), ctx.toJS(container)]
  discard pager.timeouts.setTimeout(ttTimeout, fun, int32(n),
    args.toJSValueConstOpenArray())
  JS_FreeValue(ctx, fun)
  for arg in args:
    JS_FreeValue(ctx, arg)

const MenuMap = [
  ("Select text              (v)", "cmd.buffer.selectOrCopy()"),
  ("Previous buffer          (,)", "cmd.pager.prevBuffer(1)"),
  ("Next buffer              (.)", "cmd.pager.nextBuffer(1)"),
  ("Discard buffer           (D)", "cmd.pager.discardBuffer(1)"),
  ("────────────────────────────", ""),
  ("Copy page URL          (M-y)", "cmd.pager.copyURL(1)"),
  ("Copy link               (yu)", "cmd.pager.copyCursorLink(1)"),
  ("View image               (I)", "cmd.buffer.viewImage(1)"),
  ("Copy image link         (yI)", "cmd.pager.copyCursorImage(1)"),
  ("Reload                   (U)", "cmd.pager.reloadBuffer(1)"),
  ("────────────────────────────", ""),
  ("Save link             (sC-m)", "cmd.buffer.saveLink(1)"),
  ("View source              (\\)", "cmd.pager.toggleSource(1)"),
  ("Edit source             (sE)", "cmd.buffer.sourceEdit(1)"),
  ("Save source             (sS)", "cmd.buffer.saveSource(1)"),
  ("────────────────────────────", ""),
  ("Linkify URLs             (:)", "cmd.buffer.markURL(1)"),
  ("Toggle images          (M-i)", "cmd.buffer.toggleImages(1)"),
  ("Toggle JS & reload     (M-j)", "cmd.buffer.toggleScripting(1)"),
  ("Toggle cookie & reload (M-k)", "cmd.buffer.toggleCookie(1)"),
  ("────────────────────────────", ""),
  ("Bookmark page          (M-a)", "cmd.pager.addBookmark(1)"),
  ("Open bookmarks         (M-b)", "cmd.pager.openBookmarks(1)"),
  ("Open history           (C-h)", "cmd.pager.openHistory(1)"),
]

proc menuFinish(opaque: RootRef; select: Select) =
  let pager = Pager(opaque)
  if select.selected != -1:
    pager.scommand = MenuMap[select.selected][1]
  pager.menu = nil
  if pager.container != nil:
    pager.container.queueDraw()

proc openMenu(pager: Pager; x = -1; y = -1) {.jsfunc.} =
  let x = if x == -1 and pager.container != nil:
    pager.container.acursorx
  else:
    max(x, 0)
  let y = if y == -1 and pager.container != nil:
    pager.container.acursory
  else:
    max(y, 0)
  var options = newSeq[SelectOption]()
  for (s, cmd) in MenuMap:
    options.add(SelectOption(s: s, nop: cmd == ""))
  if pager.container != nil and pager.container.currentSelection != nil:
    options[0].s = "Copy selection           (y)"
  pager.menu = newSelect(options, -1, x, y, pager.bufWidth, pager.bufHeight,
    menuFinish, pager)

proc handleEvent0(pager: Pager; container: Container; event: ContainerEvent) =
  case event.t
  of cetLoaded:
    dec pager.numload
  of cetReadLine:
    if container == pager.container:
      pager.setLineEdit(lmBuffer, event.value, event.password, event.prompt)
  of cetReadArea:
    if container == pager.container:
      var s = event.tvalue
      if pager.openInEditor(s):
        pager.container.readSuccess(s)
      else:
        pager.container.readCanceled()
  of cetReadFile:
    if container == pager.container:
      pager.setLineEdit(lmBufferFile, "")
  of cetOpen:
    let url = event.request.url
    let sameScheme = container.url.scheme == url.scheme
    if event.request.httpMethod != hmGet and not sameScheme and
        not (container.url.schemeType in {stHttp, stHttps} and
          url.schemeType in {stHttp, stHttps}):
      pager.alert("Blocked cross-scheme POST: " & $url)
      return
    #TODO this is horrible UX, async actions shouldn't block input
    if pager.container != container or
        not event.save and not container.isHoverURL(url):
      pager.ask("Open pop-up? " & $url).then(proc(x: bool) =
        if x:
          if not pager.gotoURLHash(event.request, container, event.save):
            discard pager.gotoURL(event.request, event.contentType,
              referrer = pager.container, save = event.save)
      )
    else:
      if not pager.gotoURLHash(event.request, container, event.save):
        discard pager.gotoURL(event.request, event.contentType,
          referrer = pager.container, save = event.save, url = event.url)
  of cetStatus:
    if pager.container == container:
      pager.showAlerts()
  of cetSetLoadInfo:
    if pager.container == container:
      pager.onSetLoadInfo(container)
  of cetTitle:
    if pager.container == container:
      pager.showAlerts()
      pager.updateTitle = true
  of cetAlert:
    if pager.container == container:
      pager.alert(event.msg)
  of cetCancel:
    let item = pager.findConnectingContainer(container)
    if item == nil:
      # whoops. we tried to cancel, but the event loop did not favor us...
      # at least cancel it in the buffer
      container.remoteCancel()
    else:
      dec pager.numload
      # closes item's stream
      pager.deleteContainer(container, container.find(ndAny))
  of cetMetaRefresh:
    let url = event.refreshURL
    let n = event.refreshIn
    case container.config.metaRefresh
    of mrNever: assert false
    of mrAlways: pager.metaRefresh(container, n, url)
    of mrAsk:
      let surl = $url
      if surl in pager.refreshAllowed:
        pager.metaRefresh(container, n, url)
      else:
        pager.ask("Redirect to " & $url & " (in " & $n & "ms)?")
          .then(proc(x: bool) =
            if x:
              pager.refreshAllowed.incl($url)
              pager.metaRefresh(container, n, url)
          )

proc handleEvents(pager: Pager; container: Container) =
  while (let event = container.popEvent(); event != nil):
    pager.handleEvent0(container, event)

proc handleEvents(pager: Pager) =
  if pager.container != nil:
    pager.handleEvents(pager.container)

proc handleEvent(pager: Pager; container: Container) =
  if container.handleEvent().isOk:
    pager.handleEvents(container)

proc runCommand(pager: Pager) =
  if pager.scommand != "":
    pager.command0(pager.scommand)
    let container = pager.pinned.console
    if container != nil:
      container.flags.incl(cfTailOnLoad)
    pager.scommand = ""
    pager.handleEvents()

proc handleStderr(pager: Pager) =
  const BufferSize = 4096
  const prefix = "STDERR: "
  var buffer {.noinit.}: array[BufferSize, char]
  let estream = pager.forkserver.estream
  var hadlf = true
  while true:
    let n = estream.readData(buffer)
    if n <= 0:
      break
    var i = 0
    while i < n:
      var j = n
      var found = false
      for k in i ..< n:
        if buffer[k] == '\n':
          j = k + 1
          found = true
          break
      if hadlf:
        pager.console.write(prefix)
      if j - i > 0:
        pager.console.write(buffer.toOpenArray(i, j - 1))
      i = j
      hadlf = found
  if not hadlf:
    pager.console.write('\n')
  pager.console.flush()

proc handleRead(pager: Pager; fd: int): Opt[void] =
  if pager.term.istream != nil and fd == pager.term.istream.fd:
    ?pager.handleUserInput()
  elif fd == pager.forkserver.estream.fd:
    pager.handleStderr()
  elif (let data = pager.loader.get(fd); data != nil):
    if data of ConnectingContainer:
      pager.handleRead(ConnectingContainer(data))
    elif data of ContainerData:
      let container = ContainerData(data).container
      pager.handleEvent(container)
    else:
      pager.loader.onRead(fd)
      if data of ConnectData:
        pager.runJSJobs()
  elif fd in pager.loader.unregistered:
    discard # ignore
  else:
    assert false
  ok()

proc handleWrite(pager: Pager; fd: int): Opt[void] =
  if pager.term.ostream != nil and pager.term.ostream.fd == fd:
    if ?pager.term.flush():
      pager.pollData.unregister(pager.term.ostream.fd)
  else:
    let container = ContainerData(pager.loader.get(fd)).container
    if container.iface.stream.flushWrite():
      pager.pollData.unregister(fd)
      pager.pollData.register(fd, POLLIN)
  ok()

proc handleError(pager: Pager; fd: int): Opt[void] =
  if pager.term.istream != nil and fd == pager.term.istream.fd:
    pager.alert("error in tty")
    return err()
  elif fd == pager.forkserver.estream.fd:
    pager.alert("fork server crashed")
    return err()
  elif (let data = pager.loader.get(fd); data != nil):
    if data of ConnectingContainer:
      pager.handleError(ConnectingContainer(data))
    elif data of ContainerData:
      let container = ContainerData(data).container
      pager.pollData.unregister(fd)
      pager.loader.unset(fd)
      if container.iface != nil:
        container.iface.stream.sclose()
        container.iface = nil
      let isConsole = container == pager.pinned.console
      if isConsole:
        pager.dumpConsoleFile = true
      pager.deleteContainer(container, container.find(ndAny))
      pager.console.error("error in buffer", $container.url)
      if not isConsole:
        pager.showConsole()
      dec pager.numload
    else:
      discard pager.loader.onError(fd) #TODO handle connection error?
  elif fd in pager.loader.unregistered:
    discard # already unregistered...
  else:
    pager.showConsole()
  ok()

let SIGWINCH {.importc, header: "<signal.h>", nodecl.}: cint

proc setupSigwinch(pager: Pager): PosixStream =
  var pipefd {.noinit.}: array[2, cint]
  doAssert pipe(pipefd) != -1
  let writer = newPosixStream(pipefd[1])
  writer.setCloseOnExec()
  writer.setBlocking(false)
  var gwriter {.global.}: PosixStream = nil
  gwriter = writer
  onSignal SIGWINCH:
    discard sig
    discard gwriter.writeData([0u8])
  let reader = newPosixStream(pipefd[0])
  reader.setCloseOnExec()
  reader.setBlocking(false)
  return reader

proc inputLoop(pager: Pager): Opt[void] =
  pager.pollData.register(pager.term.istream.fd, POLLIN)
  let sigwinch = pager.setupSigwinch()
  pager.pollData.register(sigwinch.fd, POLLIN)
  while true:
    let timeout = pager.timeouts.sortAndGetTimeout()
    pager.pollData.poll(timeout)
    pager.loader.blockRegister()
    for event in pager.pollData.events:
      let efd = int(event.fd)
      if (event.revents and POLLIN) != 0:
        if event.fd == sigwinch.fd:
          sigwinch.drain()
          pager.windowChange()
        else:
          ?pager.handleRead(efd)
      if (event.revents and POLLOUT) != 0:
        ?pager.handleWrite(efd)
      if (event.revents and POLLERR) != 0 or (event.revents and POLLHUP) != 0:
        ?pager.handleError(efd)
    if pager.timeouts.run(pager.console):
      if pager.pinned.console != nil:
        pager.pinned.console.flags.incl(cfTailOnLoad)
    pager.loader.unblockRegister()
    pager.loader.unregistered.setLen(0)
    pager.runJSJobs()
    pager.runCommand()
    if pager.container == nil and pager.lineedit == nil:
      # No buffer to display.
      if not pager.hasload:
        # Failed to load every single URL the user passed us. We quit, and that
        # will dump all alerts to stderr.
        return err()
      else:
        # At least one connection has succeeded, but we have nothing to display.
        # Normally, this means that the input stream has been redirected to a
        # file or to an external program. That also means we can't just exit
        # without potentially interrupting that stream.
        #TODO: a better UI would be querying the number of ongoing streams in
        # loader, and then asking for confirmation if there is at least one.
        discard pager.term.setCursor(0, pager.term.attrs.height - 1)
        discard pager.term.anyKey("Hit any key to quit Chawan:")
        return
    pager.showAlerts()
    ?pager.draw()
  ok()

proc hasSelectFds(pager: Pager): bool =
  return not pager.timeouts.empty or pager.numload > 0 or
    pager.loader.hasFds()

proc headlessLoop(pager: Pager): Opt[void] =
  while pager.hasSelectFds():
    let timeout = pager.timeouts.sortAndGetTimeout()
    pager.pollData.poll(timeout)
    pager.loader.blockRegister()
    for event in pager.pollData.events:
      let efd = int(event.fd)
      if (event.revents and POLLIN) != 0:
        ?pager.handleRead(efd)
      if (event.revents and POLLOUT) != 0:
        ?pager.handleWrite(efd)
      if (event.revents and POLLERR) != 0 or (event.revents and POLLHUP) != 0:
        ?pager.handleError(efd)
    pager.loader.unblockRegister()
    pager.loader.unregistered.setLen(0)
    discard pager.timeouts.run(pager.console)
    pager.runJSJobs()
  ok()

proc dumpBuffers(pager: Pager) =
  if pager.headlessLoop().isErr:
    return
  for tab in pager.tabs:
    for container in tab.containers:
      if container.iface == nil:
        continue # ignore crashed buffers; they are already logged anyway
      if pager.drawBuffer(container, cast[ChaFile](stdout)).isOk:
        pager.handleEvents(container)
      else:
        pager.console.error("Error in buffer", $container.url)
        # check for errors
        discard pager.handleRead(pager.forkserver.estream.fd)
        return

proc addPagerModule*(ctx: JSContext) =
  ctx.registerType(Pager)

{.pop.} # raises: []
