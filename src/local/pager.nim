{.push raises: [].}

from std/strutils import strip

import std/options
import std/os
import std/posix
import std/sets
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
import monoucha/jsbind
import monoucha/jsnull
import monoucha/jstypes
import monoucha/jsutils
import monoucha/libregexp
import monoucha/quickjs
import monoucha/tojs
import server/buffer
import server/bufferiface
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
import types/jsopt
import types/opt
import types/url
import types/winattrs
import utils/lrewrap
import utils/luwrap
import utils/myposix
import utils/strwidth
import utils/twtstr

type
  LineMode* = enum
    lmScript = "script"
    lmLocation = "location"
    lmUsername = "username"
    lmPassword = "password"
    lmCommand = "command"
    lmBuffer = "buffer"
    lmSearch = "search"
    lmGotoLine = "gotoLine"
    lmDownload = "download"
    lmBufferFile = "bufferFile"
    lmAlert = "alert"
    lmMailcap = "mailcap"

  PagerAlertState = enum
    pasNormal, pasAlertOn, pasLoadInfo

  ContainerConnectionState = enum
    ccsBeforeResult, ccsBeforeStatus

  ConnectingContainer* = ref object of MapData
    state: ContainerConnectionState
    container: Container
    res: int
    outputId: int

  LineDataScript = ref object of LineData
    resolve: JSValue
    update: JSValue

  LineDataDownload = ref object of LineData
    outputId: int
    stream: PosixStream
    url: URL

  LineDataAuth = ref object of LineData
    container: Container
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

  Pinned = object
    downloads: Container
    console*: Container
    prev: Container

  UpdateStatusState = enum
    ussNone, ussUpdate, ussSkip

  JSMap = object
    # workaround for the annoying warnings (too lazy to fix them)
    pager: JSValue
    handleInput: JSValue

  Pager* = ref object of RootObj
    blockTillRelease: bool
    hasload: bool # has a page been successfully loaded since startup?
    inEval: bool
    dumpConsoleFile: bool
    feedNext*: bool
    updateStatus: UpdateStatusState
    consoleCacheId: int
    consoleFile: string
    alertState: PagerAlertState
    # current number prefix (when vi-numeric-prefix is true)
    precnum {.jsgetset.}: int32
    arg0 {.jsget.}: int32
    alerts: seq[string]
    askCursor: int
    askPromise*: Promise[string]
    askPrompt: string
    config*: Config
    console: Console
    tabHead: Tab # not nil
    tab: Tab # not nil
    cookieJars: CookieJarMap
    surfaces: array[SurfaceType, Surface]
    pinned*: Pinned
    exitCode: int
    forkserver: ForkServer
    inputBuffer: string # currently uninterpreted characters
    jsctx: JSContext
    lastAlert {.jsget.}: string # last alert seen by the user
    lineHist: array[LineMode, History]
    lineedit*: LineEdit
    linemode: LineMode
    loader: FileLoader
    loaderPid {.jsget.}: int
    luctx: LUContext
    menu {.jsget.}: Select
    navDirection {.jsget.}: NavDirection
    numload: int # number of pages currently being loaded
    pollData: PollData
    refreshAllowed: HashSet[string]
    term*: Terminal
    timeouts*: TimeoutState
    tmpfSeq: uint
    unreg: seq[Container]
    attrs: WindowAttributes
    pidMap: Table[int, string] # pid -> command
    jsmap: JSMap
    autoMailcap: Mailcap
    mailcap: Mailcap
    mimeTypes: MimeTypes

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
proc addConsole(pager: Pager; interactive: bool)
proc alert*(pager: Pager; msg: string)
proc askMailcap(pager: Pager; container: Container; ostream: PosixStream;
  contentType: string; i: int; response: Response; sx: int)
proc connected2(pager: Pager; container: Container; res: MailcapResult;
  response: Response)
proc connected3(pager: Pager; container: Container; stream: SocketStream;
  ostream: PosixStream; istreamOutputId, ostreamOutputId: int;
  redirected: bool)
proc cloned(pager: Pager; container: Container; stream: SocketStream)
proc deleteContainer(pager: Pager; container, setTarget: Container)
proc dumpBuffers(pager: Pager)
proc evalJS(pager: Pager; val: JSValue): JSValue
proc getHist(pager: Pager; mode: LineMode): History
proc handleEvents(pager: Pager)
proc handleRead(pager: Pager; fd: int): Opt[void]
proc inputLoop(pager: Pager): Opt[void]
proc loadURL(pager: Pager; url: string; contentType = "";
  charset = CHARSET_UNKNOWN; history = true)
proc onSetLoadInfo(pager: Pager; container: Container)
proc openMenu(pager: Pager; x = -1; y = -1)
proc readPipe(pager: Pager; contentType: string; cs: Charset; ps: PosixStream;
  title: string)
proc redraw(pager: Pager)
proc refreshStatusMsg(pager: Pager)
proc runMailcap(pager: Pager; url: URL; stream: PosixStream;
  istreamOutputId: int; contentType: string; entry: MailcapEntry):
  MailcapResult
proc showAlerts(pager: Pager)
proc unregisterFd(pager: Pager; fd: int)
proc updateReadLine(pager: Pager)
proc windowChange(pager: Pager)

proc container(pager: Pager): Container {.jsfget: "buffer".} =
  pager.tab.current

proc bufWidth(pager: Pager): int {.jsfget.} =
  return pager.attrs.width

proc bufHeight(pager: Pager): int {.jsfget.} =
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

proc updateTitle(pager: Pager) =
  let container = pager.container
  if container != nil:
    pager.term.queueTitle(container.getTitle())

proc setContainer(pager: Pager; c: Container) =
  if pager.term.imageMode != imNone and pager.container != nil:
    pager.container.clearCachedImages(pager.loader)
  if c != nil:
    if c.tab != pager.tab:
      assert c.tab != nil
      pager.tab = c.tab
    c.tab.current = c
    c.queueDraw()
    pager.onSetLoadInfo(c)
    pager.updateTitle()
  else:
    pager.tab.current = nil

proc reflect(ctx: JSContext; this_val: JSValueConst; argc: cint;
    argv: JSValueConstArray; magic: cint; funcData: JSValueConstArray): JSValue
    {.cdecl.} =
  let obj = funcData[0]
  let fun = funcData[1]
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
      let funcData = @[cval, val]
      let fun = JS_NewCFunctionData(ctx, reflect, 1, 0, 2,
        funcData.toJSValueArray())
      JS_FreeValue(ctx, cval)
      JS_FreeValue(ctx, val)
      return fun
    JS_FreeValue(ctx, cval)
    if not JS_IsUndefined(val):
      return val
  return JS_UNINITIALIZED

proc getHist(pager: Pager; mode: LineMode): History =
  if pager.lineHist[mode] == nil:
    pager.lineHist[mode] = newHistory(100)
  return pager.lineHist[mode]

proc setLineEdit0(pager: Pager; mode: LineMode; prompt, current: string;
    hide: bool; data: LineData) =
  let hist = pager.getHist(mode)
  pager.lineedit = readLine(prompt, current, pager.attrs.width, hide, hist,
    pager.luctx, data)
  pager.linemode = mode

proc setLineEdit2(pager: Pager; mode: LineMode; prompt: string; current = "";
    hide = false) =
  pager.setLineEdit0(mode, prompt, current, hide, data = nil)

#TODO the above two variants should be merged into this one
proc setLineEdit(ctx: JSContext; pager: Pager; mode: LineMode; prompt: string;
    obj: JSValueConst = JS_UNDEFINED): JSValue {.jsfunc.} =
  var funs {.noinit.}: array[2, JSValue]
  let res = JS_NewPromiseCapability(ctx, funs.toJSValueArray())
  if JS_IsException(res):
    return res
  JS_FreeValue(ctx, funs[1])
  var current = ""
  var hide = false
  var update = JS_UNDEFINED
  if not JS_IsUndefined(obj):
    let jsCurrent = JS_GetPropertyStr(ctx, obj, "current")
    if JS_IsException(jsCurrent):
      return jsCurrent
    if not JS_IsUndefined(jsCurrent):
      ?ctx.fromJSFree(jsCurrent, current)
    let jsHide = JS_GetPropertyStr(ctx, obj, "hide")
    if JS_IsException(jsHide):
      return jsHide
    if not JS_IsUndefined(jsHide):
      ?ctx.fromJSFree(jsHide, hide)
    update = JS_GetPropertyStr(ctx, obj, "update")
    if JS_IsException(update):
      return update
  let data = LineDataScript(resolve: funs[0], update: update)
  let hist = pager.getHist(mode)
  if pager.lineedit != nil: # clean up old lineedit
    pager.lineedit.state = lesCancel
    pager.updateReadLine()
  pager.lineedit = readLine(prompt, current, pager.attrs.width, hide, hist,
    pager.luctx, data)
  pager.linemode = lmScript
  return res

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
  let ctx = pager.jsctx
  let val = ctx.eval(src, filename,
    JS_EVAL_TYPE_GLOBAL or JS_EVAL_FLAG_COMPILE_ONLY)
  if not JS_IsException(val):
    let ret = pager.evalJS(val)
    if JS_IsException(ret):
      pager.console.writeException(ctx)
      JS_FreeValue(ctx, ret)
  else:
    pager.console.writeException(ctx)

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
    let n = response.body.read(addr opaque.buffer[olen], BufferSize)
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
    cookieJar.setCookie(headers, url, persist, http = true)
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
  discard loader.addClient(loader.clientPid, clientConfig, isPager = true)
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

proc normalizeModuleName(ctx: JSContext; baseName, name: cstringConst;
    opaque: pointer): cstring {.cdecl.} =
  return js_strdup(ctx, name)

proc loadMailcap(pager: Pager; mailcap: var Mailcap; path: ChaPathResolved) =
  let ps = newPosixStream($path)
  if ps != nil:
    let src = ps.readAllOrMmap()
    let res = mailcap.parseMailcap(src.toOpenArray(), $path)
    deallocMem(src)
    ps.sclose()
    if res.isErr:
      pager.alert(res.error)

const DefaultMailcap = staticRead"res/mailcap"
const DefaultAutoMailcap = staticRead"res/auto.mailcap"

proc newPager*(config: Config; forkserver: ForkServer; ctx: JSContext;
    alerts: seq[string]; loader: FileLoader; loaderPid: int;
    console: Console): Pager =
  let tab = Tab()
  let pager = Pager(
    config: config,
    forkserver: forkserver,
    term: newTerminal(newPosixStream(STDOUT_FILENO), config),
    alerts: alerts,
    jsctx: ctx,
    luctx: LUContext(),
    exitCode: -1,
    loader: loader,
    loaderPid: loaderPid,
    cookieJars: newCookieJarMap(),
    tabHead: tab,
    tab: tab,
    consoleCacheId: -1,
    console: console,
  )
  pager.timeouts = newTimeoutState(pager.jsctx, evalJSFree, pager)
  pager.jsmap = JSMap(
    pager: ctx.toJS(pager),
    handleInput: ctx.eval("Pager.prototype.handleInput", "<init>",
      JS_EVAL_TYPE_GLOBAL)
  )
  doAssert not JS_IsException(pager.jsmap.pager) and
    not JS_IsException(pager.jsmap.handleInput)
  let rt = JS_GetRuntime(ctx)
  JS_SetModuleLoaderFunc(rt, normalizeModuleName, loadJSModule, nil)
  JS_SetInterruptHandler(rt, interruptHandler, nil)
  pager.initLoader()
  block history:
    let hist = newHistory(pager.config.external.historySize, getTime().toUnix())
    let ps = newPosixStream($pager.config.external.historyFile)
    if ps != nil:
      if hist.parse(ps).isErr:
        hist.transient = true
        pager.alert("failed to read history")
    pager.lineHist[lmLocation] = hist
  block cookie:
    let ps = newPosixStream($pager.config.external.cookieFile)
    if ps != nil:
      if pager.cookieJars.parse(ps, pager.alerts).isErr:
        pager.cookieJars.transient = true
        pager.alert("failed to read cookies")
  pager.loadMailcap(pager.autoMailcap, config.external.autoMailcap)
  doAssert pager.autoMailcap.parseMailcap(DefaultAutoMailcap,
    "res/auto.mailcap").isOk
  for p in config.external.mailcap:
    pager.loadMailcap(pager.mailcap, p)
  doAssert pager.mailcap.parseMailcap(DefaultMailcap, "res/mailcap").isOk
  for p in config.external.mimeTypes:
    if f := chafile.fopen($p, "r"):
      let res = pager.mimeTypes.parseMimeTypes(f, DefaultImages)
      f.close()
      if res.isErr:
        pager.alert("error reading file " & $p)
  return pager

proc makeDataDir(pager: Pager) =
  # Try to ensure that we have a data directory.
  if mkdir(cstring(pager.config.dataDir), 0o700) < 0 and errno == ENOENT:
    # try creating parent dirs
    var s = pager.config.dataDir
    var i = 1
    while (i = s.find('/', i); i > 0):
      s[i] = '\0'
      if mkdir(cstring(s), 0o755) < 0 and errno != EEXIST:
        return # something went very wrong; bail
      s[i] = '/'
      inc i
    # maybe it works now?
    discard mkdir(cstring(pager.config.dataDir), 0o700)

proc cleanup(pager: Pager) =
  discard pager.term.quit() # maybe stdout is closed, but we don't mind here
  let hist = pager.lineHist[lmLocation]
  var needDataDir = true
  if not hist.transient:
    let hasConfigDir = dirExists(pager.config.dir)
    if hasConfigDir:
      needDataDir = false
      pager.makeDataDir()
    if hist.write($pager.config.external.historyFile).isErr:
      if hasConfigDir:
        # History is enabled by default, so do not print the error
        # message if no config dir exists.
        pager.alert("failed to save history")
  if pager.cookieJars.needsWrite():
    if needDataDir:
      pager.makeDataDir()
    if pager.cookieJars.write($pager.config.external.cookieFile).isErr:
      pager.alert("failed to save cookies")
  for msg in pager.alerts:
    discard cast[ChaFile](stderr).write("cha: " & msg & '\n')
  let ctx = pager.jsctx
  ctx.freeValues(pager.config.line)
  ctx.freeValues(pager.config.page)
  ctx.freeValues(pager.config.omnirule)
  ctx.freeValues(pager.config.siteconf)
  for val in pager.jsmap.fields:
    JS_FreeValue(ctx, val)
  if pager.lineedit != nil and pager.lineedit.data of LineDataScript:
    #TODO maybe put this somewhere else
    let data = LineDataScript(pager.lineedit.data)
    JS_FreeValue(ctx, data.resolve)
    JS_FreeValue(ctx, data.update)
  pager.timeouts.clearAll()
  assert not pager.inEval
  let rt = JS_GetRuntime(ctx)
  ctx.free()
  rt.free()
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
  let rt = JS_GetRuntime(pager.jsctx)
  while true:
    let ctx = rt.runJSJobs()
    if ctx == nil:
      break
    pager.console.writeException(ctx)
  if pager.exitCode != -1:
    pager.quit(pager.exitCode)

proc evalJSStart(pager: Pager): bool =
  if pager.config.start.headless == hmFalse:
    pager.term.catchSigint()
  let wasInEval = pager.inEval
  pager.inEval = true
  return wasInEval

proc evalJSEnd(pager: Pager; wasInEval: bool) =
  pager.inEval = false
  if pager.exitCode != -1:
    # if we are in a nested eval, then just wait until we are not.
    if not wasInEval:
      pager.quit(pager.exitCode)
  else:
    pager.runJSJobs()
  if pager.config.start.headless == hmFalse:
    pager.term.respectSigint()

proc evalJS(pager: Pager; val: JSValue): JSValue =
  let wasInEval = pager.evalJSStart()
  result = pager.jsctx.evalFunction(val)
  pager.evalJSEnd(wasInEval)

proc evalAction(pager: Pager; val: JSValue; arg0: int32; oval: var JSValue):
    JSValue =
  let ctx = pager.jsctx
  var val = val
  if not JS_IsFunction(ctx, val): # yes, this looks weird, but it's correct
    val = ctx.evalFunction(val)
    if JS_IsFunction(ctx, val):
      # optimization: skip this eval on the next call.
      JS_FreeValue(ctx, oval)
      oval = JS_DupValue(ctx, val)
  # If an action evaluates to a function that function is evaluated too.
  if JS_IsFunction(ctx, val):
    if arg0 != 0:
      let arg0 = ctx.toJS(arg0)
      if JS_IsException(arg0):
        JS_FreeValue(ctx, val)
        return arg0
      val = ctx.callSinkFree(val, JS_UNDEFINED, arg0)
    else: # no precnum
      val = ctx.callFree(val, JS_UNDEFINED)
  return val

#TODO this overload shouldn't exist
proc evalAction(pager: Pager; action: string; arg0: int32) =
  let ctx = pager.jsctx
  var val = ctx.eval("cmd." & action, "<command>", JS_EVAL_TYPE_GLOBAL)
  if JS_IsException(val):
    pager.console.writeException(ctx)
    return
  let wasInEval = pager.evalJSStart()
  # If an action evaluates to a function that function is evaluated too.
  if JS_IsFunction(ctx, val):
    if arg0 != 0:
      let arg0 = ctx.toJS(arg0)
      if JS_IsException(arg0):
        val = arg0
      else:
        val = ctx.callSinkFree(val, JS_UNDEFINED, arg0)
    else: # no precnum
      val = ctx.callFree(val, JS_UNDEFINED)
  if JS_IsException(val):
    pager.console.writeException(ctx)
  JS_FreeValue(ctx, val)
  pager.evalJSEnd(wasInEval)

proc writeInputBuffer(pager: Pager) {.jsfunc.} =
  if pager.lineedit != nil:
    pager.lineedit.write(pager.inputBuffer)
    pager.inputBuffer.setLen(0)
    pager.updateReadLine()

proc evalInputAction(ctx: JSContext; pager: Pager; map: ActionMap; arg0: int32):
    JSValue {.jsfunc.} =
  let val = map.advance(pager.inputBuffer)
  if JS_IsUndefined(val):
    if map.keyLast != 0:
      return JS_UNDEFINED
    if JS_IsUndefined(map.defaultAction):
      pager.inputBuffer.setLen(0)
      return JS_UNDEFINED
    let res = pager.evalAction(JS_DupValue(ctx, map.defaultAction), arg0,
      map.defaultAction)
    pager.inputBuffer.setLen(0)
    return res
  # note: this may replace val inside the ActionMap
  let res = pager.evalAction(JS_DupValue(ctx, val), arg0, map.mgetValue())
  ctx.feedNext(map, pager.feedNext, pager.inputBuffer)
  pager.feedNext = false
  if map.keyLast == 0:
    pager.inputBuffer.setLen(0)
  return res

proc queueStatusUpdate(pager: Pager) {.jsfunc.} =
  if pager.updateStatus == ussNone:
    pager.updateStatus = ussUpdate

# called from JS command()
proc evalCommand(pager: Pager; src: string): JSValue {.jsfunc.} =
  let container = pager.pinned.console
  if container != nil:
    container.flags.incl(cfTailOnLoad)
  let ctx = pager.jsctx
  let val = ctx.eval(src, "<command>",
    JS_EVAL_TYPE_GLOBAL or JS_EVAL_FLAG_COMPILE_ONLY)
  if JS_IsException(val):
    pager.console.writeException(ctx)
    return
  return pager.evalJS(val)

proc toJS(ctx: JSContext; input: MouseInput): JSValue =
  #TODO might want to make this an opaque type
  let obj = JS_NewObject(ctx)
  let t = input.t
  let button = input.button
  let mods = cast[int32](input.mods)
  let (x, y) = input.pos
  # TODO we must check for exception on toJS too
  if ctx.defineProperty(obj, "t", ctx.toJS(t)) == dprException or
      ctx.defineProperty(obj, "button", ctx.toJS(button)) == dprException or
      ctx.defineProperty(obj, "mods", ctx.toJS(mods)) == dprException or
      ctx.defineProperty(obj, "x", ctx.toJS(x)) == dprException or
      ctx.defineProperty(obj, "y", ctx.toJS(y)) == dprException:
    JS_FreeValue(ctx, obj)
    return JS_EXCEPTION
  return obj

proc osc52Primary(pager: Pager): bool {.jsfget.} =
  pager.term.osc52Primary

# The maximum number we are willing to accept.
# This should be fine for 32-bit signed ints (which precnum currently is).
const MaxPrecNum = 100000000

proc updateNumericPrefix(pager: Pager): bool {.jsfunc.} =
  if pager.config.input.viNumericPrefix and pager.precnum >= 0:
    let c = pager.inputBuffer[0]
    if pager.precnum != 0 and c == '0' or c in '1'..'9':
      if pager.precnum < MaxPrecNum: # better ignore than eval...
        pager.precnum *= 10
        pager.precnum += int32(decValue(c))
      pager.inputBuffer.setLen(0)
      return true
    pager.arg0 = max(pager.precnum, 0)
    pager.precnum = -1
  false

proc handleUserInput(pager: Pager): Opt[void] =
  if not ?pager.term.ahandleRead():
    return ok()
  while e := pager.term.areadEvent():
    case e.t
    of ietKey: pager.inputBuffer &= e.c
    of ietWindowChange: pager.windowChange()
    of ietRedraw: pager.redraw()
    of ietKeyEnd, ietPaste, ietMouse:
      let wasInEval = pager.evalJSStart()
      let ctx = pager.jsctx
      let arg0 = ctx.toJS(e.t)
      if JS_IsException(arg0):
        pager.console.writeException(ctx)
        break
      let arg1 = if e.t == ietMouse: ctx.toJS(e.m) else: JS_UNDEFINED
      let res = ctx.callSink(pager.jsmap.handleInput, pager.jsmap.pager, arg0,
        arg1)
      let ex = JS_IsException(res)
      JS_FreeValue(ctx, res)
      pager.evalJSEnd(wasInEval)
      if ex:
        pager.console.writeException(ctx)
  ok()

proc runStartupScript(pager: Pager) =
  if pager.config.start.startupScript != "":
    let ps = newPosixStream(pager.config.start.startupScript)
    let s = if ps != nil:
      var x = ps.readAll()
      ps.sclose()
      move(x)
    else:
      pager.config.start.startupScript
    let flag = if pager.config.start.startupScript.endsWith(".mjs"):
      JS_EVAL_TYPE_MODULE
    else:
      JS_EVAL_TYPE_GLOBAL
    let ctx = pager.jsctx
    let val = ctx.eval(s, pager.config.start.startupScript,
      flag or JS_EVAL_FLAG_COMPILE_ONLY)
    if not JS_IsException(val):
      let res = pager.evalJS(val)
      if not JS_IsException(res):
        JS_FreeValue(ctx, res)
      else:
        pager.console.writeException(ctx)
    else:
      pager.console.writeException(ctx)

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
  pager.attrs = pager.term.attrs
  for st in SurfaceType:
    pager.clear(st)
  pager.addConsole(istream != nil)
  let ctx = pager.jsctx
  let jsInit = ctx.eval("Pager.prototype.init", "<init>", JS_EVAL_TYPE_GLOBAL)
  doAssert not JS_IsException(jsInit)
  let res = ctx.callFree(jsInit, pager.jsmap.pager)
  doAssert not JS_IsException(res)
  JS_FreeValue(ctx, res)
  pager.runStartupScript()
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
  if pager.precnum > 0:
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
    let fgcolor = if cfCrashed in container.flags:
      ANSIColor(1).cellColor()
    else:
      defaultColor
    var format = initFormat(defaultColor, fgcolor,
      pager.config.status.formatMode)
    pager.alertState = pasNormal
    var msg = ""
    if container.numLines > 0 and pager.config.status.showCursorPosition:
      msg &= $(container.cursory + 1) & "/" & $container.numLines &
        " (" & $container.atPercentOf() & "%)"
    else:
      msg &= "Viewing"
    if cfCrashed in container.flags:
      msg &= " CRASHED!"
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
      pager.inputBuffer == "" and pager.precnum <= 0:
    pager.queueStatusUpdate()

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

proc drawBuffer(pager: Pager; container: Container): Opt[void] =
  let res = container.readLines(proc(line: SimpleFlexibleLine): Opt[void] =
    let term = pager.term
    var x = 0
    var i = 0
    let bgcolor = container.bgcolor
    let bgformat = term.reduceFormat(initFormat(bgcolor, defaultColor, {}))
    if bgcolor != defaultColor and
        (line.formats.len == 0 or line.formats[0].pos > 0):
      ?term.processFormat(bgformat)
    for f in line.formats:
      var ff = f.format
      if ff.bgcolor == defaultColor:
        ff.bgcolor = container.bgcolor
      let termBgcolor = term.getCurrentBgcolor()
      let ls = line.str.drawBufferAdvance(termBgcolor, i, x, f.pos)
      ?term.processOutputString(ls, trackCursor = false)
      if i < line.str.len:
        ?term.processFormat(term.reduceFormat(ff))
    if i < line.str.len:
      let termBgcolor = term.getCurrentBgcolor()
      let ls = line.str.drawBufferAdvance(termBgcolor, i, x, int.high)
      ?term.processOutputString(ls, trackCursor = false)
    if bgcolor != defaultColor and x < container.width:
      ?term.processFormat(bgformat)
      let spaces = ' '.repeat(container.width - x)
      ?term.processOutputString(spaces, trackCursor = false)
    ?term.processFormat(Format())
    term.cursorNextLine()
  )
  doAssert ?pager.term.flush()
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
  result = $pager.config.external.tmpdir / "chaptmp" &
    $pager.loader.clientPid & "-" & $pager.tmpfSeq
  if ext != "":
    result &= "."
    result &= ext
  inc pager.tmpfSeq

proc loadCachedImage(pager: Pager; container: Container; bmp: NetworkBitmap;
    width, height, offx, erry, dispw: int) =
  let cachedImage = CachedImage(
    bmp: bmp,
    width: width,
    height: height,
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
    if width == bmp.width and height == bmp.height:
      # skip resize
      return newResolvedPromise(res)
    # resize
    # use a temp file, so that img-resize can mmap its output
    let headers = newHeaders(hgRequest, {
      "Cha-Image-Dimensions": $bmp.width & 'x' & $bmp.height,
      "Cha-Image-Target-Dimensions": $width & 'x' & $height
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
      "Cha-Image-Dimensions": $width & 'x' & $height
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
  container.addCachedImage(cachedImage)

proc initImages(pager: Pager; container: Container) =
  let term = pager.term
  let bufWidth = pager.bufWidth
  let bufHeight = pager.bufHeight
  let maxwpx = bufWidth * pager.attrs.ppc
  let maxhpx = bufHeight * pager.attrs.ppl
  let imageMode = term.imageMode
  let pid = container.process
  for image in container.images:
    let dims = term.positionImage(image.x, image.y, image.x - container.fromx,
      image.y - container.fromy, image.offx, image.offy, image.width,
      image.height, maxwpx, maxhpx)
    if not dims.onScreen:
      continue
    let imageId = image.bmp.imageId
    let canvasImage = term.takeImage(pid, imageId, bufHeight, dims)
    if canvasImage != nil:
      term.addImage(canvasImage)
      continue
    let cachedOffx = if imageMode == imSixel: dims.offx else: 0
    let cachedErry = if imageMode == imSixel: dims.erry else: 0
    let cachedDispw = if imageMode == imSixel: dims.dispw else: 0
    let width = image.width
    let height = image.height
    let cached = container.findCachedImage(imageId, width, height, cachedOffx,
      cachedErry, cachedDispw)
    if cached == nil:
      pager.loadCachedImage(container, image.bmp, width, height, cachedOffx,
        cachedErry, cachedDispw)
      continue
    if cached.state == cisLoaded:
      let canvasImage = newCanvasImage(cached.data, pid, cached.preludeLen,
        image.bmp, dims, cached.transparent)
      term.addImage(canvasImage)
  # updateImages yields all scrolled Sixel images damaged by checkImageDamage
  # with a new Y error.  For these, we have to reload the cached image.
  for canvasImage in term.updateImages(bufWidth, bufHeight):
    let cachedOffx = if imageMode == imSixel: canvasImage.dims.offx else: 0
    let cachedErry = if imageMode == imSixel: canvasImage.dims.erry else: 0
    let cachedDispw = if imageMode == imSixel: canvasImage.dims.dispw else: 0
    let width = canvasImage.dims.width
    let height = canvasImage.dims.height
    let cached = container.findCachedImage(canvasImage.bmp.imageId,
      width, height, cachedOffx, cachedErry, cachedDispw)
    if cached == nil:
      pager.loadCachedImage(container, canvasImage.bmp, width, height,
        cachedOffx, cachedErry, cachedDispw)
      canvasImage.damaged = false
    elif cached.state != cisLoaded:
      canvasImage.damaged = false
    else:
      canvasImage.updateImage(cached.data, cached.preludeLen)

proc getAbsoluteCursorXY(pager: Pager; container: Container): tuple[x, y: int] =
  var cursorx = 0
  var cursory = 0
  if pager.askPromise != nil:
    return (pager.askCursor, pager.attrs.height - 1)
  elif pager.lineedit != nil:
    return (pager.lineedit.getCursorX(), pager.attrs.height - 1)
  elif (let menu = pager.menu; menu != nil):
    return (menu.getCursorX(), menu.getCursorY())
  elif container != nil:
    if pager.alertState == pasNormal:
      #TODO this really doesn't belong in draw...
      container.clearHover()
    if (let select = container.select; select != nil):
      cursorx = select.getCursorX()
      cursory = select.getCursorY()
    else:
      cursorx = container.acursorx
      cursory = container.acursory
  return (cursorx, cursory)

proc visibleContainer(pager: Pager): Container =
  let container = pager.container
  if container != nil and container.loadState == lsLoading and
      cfShowLoading notin container.flags and container.numLines == 0:
    # Make buffers that haven't loaded anything yet "transparent".
    # Exception: if the user tries to interact with the page, show the ugly
    # truth.
    if container.replace != nil:
      return container.replace
    if container.prev != nil:
      return container.prev
  return container

proc highlightColor(pager: Pager): CellColor =
  if pager.attrs.colorMode != cmMonochrome:
    return pager.config.display.highlightColor.cellColor()
  return defaultColor

proc needsRedraw(pager: Pager; container: Container): bool =
  if pager.display.redraw or pager.status.redraw or
      pager.menu != nil and pager.menu.redraw or
      pager.lineedit != nil and pager.lineedit.redraw:
    return true
  if container != nil:
    if container.redraw:
      return true
    if container.select != nil and container.select.redraw:
      return true
  false

proc draw(pager: Pager): Opt[void] =
  let term = pager.term
  let container = pager.visibleContainer
  let redraw = pager.needsRedraw(container)
  if redraw:
    # Note: lack of redraw does not necessarily mean that we send nothing to
    # the terminal, but that we at most only send a few cursor movement
    # controls.
    term.initFrame()
  var imageRedraw = false
  var hasMenu = false
  let bufHeight = pager.bufHeight
  if container != nil:
    if container.redraw:
      let hlcolor = pager.highlightColor
      container.drawLines(pager.display.grid, hlcolor)
      if pager.config.display.highlightMarks:
        container.highlightMarks(pager.display.grid, hlcolor)
      container.redraw = false
      pager.display.redraw = true
      imageRedraw = true
      if container.select != nil:
        container.select.redraw = true
      let diff = pager.term.updateScroll(container.process, container.fromx,
        container.fromy)
      if diff != 0 and abs(diff) <= (bufHeight + 1) div 2:
        if diff > 0:
          pager.term.scrollDown(diff, bufHeight)
        else:
          pager.term.scrollUp(-diff, bufHeight)
    if (let select = container.select; select != nil and
        (select.redraw or pager.display.redraw)):
      select.drawSelect(pager.display.grid)
      select.redraw = false
      pager.display.redraw = true
      hasMenu = true
  else:
    pager.term.unsetScroll()
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
  if pager.lineedit != nil:
    if pager.lineedit.redraw:
      let x = pager.lineedit.generateOutput()
      pager.term.writeGrid(x, 0, pager.attrs.height - 1)
      pager.lineedit.redraw = false
  else:
    if pager.status.redraw:
      pager.term.writeGrid(pager.status.grid, 0, pager.attrs.height - 1)
      pager.status.redraw = false
  if pager.term.imageMode != imNone:
    if imageRedraw:
      # init images only after term canvas has been finalized
      pager.initImages(container)
    elif hasMenu and pager.term.imageMode == imKitty:
      # Kitty can't really deal with text layered both on top of *and*
      # under images.
      #
      # Well, it can, but only in a peculiar way: background color is
      # part of the text layer, so with our image model we'd have to
      # a) specify bgcolor for the menu and b) use sub-optimal in-cell
      # positioning.  (You'll understand why if you try to implement it.)
      #
      # Ugh. :(
      pager.term.clearImages(bufHeight)
  let (cursorx, cursory) = pager.getAbsoluteCursorXY(container)
  let mouse = pager.lineedit == nil
  let bgcolor = if container != nil: container.bgcolor else: defaultColor
  pager.term.draw(redraw, mouse, cursorx, cursory, bufHeight, bgcolor)

proc writeAskPrompt(pager: Pager; s = "") =
  let maxwidth = pager.status.grid.width - s.width()
  let i = pager.status.writeStatusMessage(pager.askPrompt, maxwidth = maxwidth)
  pager.askCursor = pager.status.writeStatusMessage(s, start = i)

proc askChar(pager: Pager; prompt: string): Promise[string] {.jsfunc.} =
  pager.askPrompt = prompt
  pager.writeAskPrompt()
  pager.askPromise = Promise[string]()
  return pager.askPromise

proc ask(pager: Pager; prompt0: string): Promise[bool] {.jsfunc.} =
  var prompt = prompt0
  let choice = " (y/n)"
  let maxw = pager.status.grid.width - choice.width()
  var w = 0
  var i = 0
  while i < prompt.len:
    let pi = i
    w += prompt.nextUTF8(i).width()
    if w > maxw:
      i = pi
      break
  prompt.setLen(i)
  prompt &= choice
  return pager.askChar(prompt).then(proc(s: string): Promise[bool] =
    if s == "y":
      return newResolvedPromise(true)
    if s == "n":
      return newResolvedPromise(false)
    pager.askPromise = Promise[string]()
    return pager.ask(prompt0)
  )

proc fulfillAsk(pager: Pager): bool {.jsfunc.} =
  if pager.askPromise != nil:
    let inputBuffer = move(pager.inputBuffer)
    let p = pager.askPromise
    pager.askPromise = nil
    pager.askPrompt = ""
    p.resolve(inputBuffer)
    return true
  return false

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

proc onSetLoadInfo(pager: Pager; container: Container) =
  if container.loadinfo != "" and pager.alertState != pasAlertOn and
      pager.askPromise == nil:
    discard pager.status.writeStatusMessage(container.loadinfo)
    pager.alertState = pasLoadInfo
    pager.updateStatus = ussSkip

proc addContainer(pager: Pager; container: Container) =
  pager.setTab(container, pager.tab)
  pager.setContainer(container)

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
    pager.term.attrs,
    title,
    redirectDepth,
    flags,
    contentType,
    charsetStack,
    cacheId,
    pager.config,
    if tab != nil: tab else: pager.tab,
  )
  pager.loader.put(ConnectingContainer(
    state: ccsBeforeResult,
    container: container,
    stream: stream
  ))
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
  pager.addContainer(res.c)
  let nc = res.c
  let fd = res.fd
  if fd == -1:
    pager.alert("Failed to duplicate buffer.")
    pager.deleteContainer(nc, nil)
  else:
    pager.cloned(nc, newSocketStream(fd))
  return nc

proc dupeBuffer(pager: Pager): Container {.jsfunc.} =
  pager.dupeBuffer(pager.container, pager.container.url)

const OppositeMap = [
  ndPrev: ndNext,
  ndNext: ndPrev,
  ndAny: ndAny
]

proc opposite(dir: NavDirection): NavDirection
    {.jsstfunc: "Pager#oppositeDir".} =
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

proc alert*(pager: Pager; msg: string) {.jsfunc.} =
  if msg != "":
    pager.alerts.add(msg)
    pager.updateStatus = ussUpdate

proc peek(pager: Pager) {.jsfunc.} =
  let container = pager.container
  if container != nil:
    pager.alert($container.url)

proc peekCursor(pager: Pager) {.jsfunc.} =
  let container = pager.container
  if container == nil:
    return
  let s = container.getPeekCursorStr()
  pager.alert(s)

proc lineInfo(pager: Pager) {.jsfunc.} =
  let container = pager.container
  if container == nil:
    return
  pager.alert("line " & $(container.cursory + 1) & "/" &
    $container.numLines & " (" & $container.atPercentOf() & "%) col " &
    $(container.cursorx + 1) & "/" & $container.currentLineWidth &
    " (byte " & $container.currentCursorBytes & ")")

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
  container.prev = move(target.prev)
  container.next = move(target.next)
  container.tab = move(target.tab)
  assert container.tab != nil
  if container.prev != nil:
    container.prev.next = container
  if container.next != nil:
    container.next.prev = container
  pager.updatePinned(target, container)
  if pager.container == target:
    pager.setContainer(container)

proc unregisterContainer(pager: Pager; container: Container) =
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

proc deleteContainer(pager: Pager; container, setTarget: Container) =
  if container.loadState == lsLoading:
    container.cancel()
  if container.sourcepair != nil:
    container.sourcepair.sourcepair = nil
    container.sourcepair = nil
  if container.replaceRef != nil:
    container.replaceRef.replace = nil
    container.replaceRef = nil
  if container.replace != nil:
    container.replace.replaceRef = nil
    container.replace = nil
  let wasCurrent = pager.container == container
  pager.setTab(container, nil)
  pager.updatePinned(container, nil)
  if wasCurrent:
    container.clearCachedImages(pager.loader)
    pager.setContainer(setTarget)
  if container.process != -1:
    pager.loader.removeCachedItem(container.cacheId)
    if cfCrashed notin container.flags:
      dec container.phandle.refc
      if container.phandle.refc == 0:
        pager.loader.removeClient(container.process)
  pager.unregisterContainer(container)

proc discardBuffer(pager: Pager; container = none(Container);
    dir = none(NavDirection)) {.jsfunc.} =
  if dir.isSome:
    pager.navDirection = dir.get.opposite()
  let container = container.get(pager.container)
  let dir = pager.revDirection
  let setTarget = container.find(dir)
  if container == nil or setTarget == nil:
    let s = if dir == ndNext:
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
    env: openArray[EnvVar]): Opt[void] =
  if suspend:
    ?pager.term.quit()
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
    if suspend:
      discard pager.term.restart()
    return err()
  case (let pid = fork(); pid)
  of -1:
    pager.alert("Failed to run process")
    if suspend:
      discard pager.term.restart()
    return err()
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
    if suspend:
      while waitpid(pid, wstatus, 0) == -1:
        if errno != EINTR:
          discard pager.term.restart()
          return err()
    else:
      pager.pidMap[int(pid)] = cmd
    discard sigaction(SIGINT, oldint, act)
    discard sigaction(SIGQUIT, oldquit, act)
    discard sigprocmask(SIG_SETMASK, oldmask, dummy);
    if not suspend:
      return ok()
    if wait:
      discard pager.term.anyKey()
    ?pager.term.restart()
    if WIFEXITED(wstatus) and WEXITSTATUS(wstatus) == 0:
      return ok()
    return err()

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

proc openEditor(pager: Pager; input: var string): Opt[void] =
  let tmpf = pager.getTempFile()
  discard mkdir(cstring($pager.config.external.tmpdir), 0o700)
  input &= '\n'
  if chafile.writeFile(tmpf, input, 0o600).isErr:
    pager.alert("failed to write temporary file")
    return err()
  let cmd = pager.getEditorCommand(tmpf)
  if cmd == "":
    pager.alert("invalid external.editor command")
    return err()
  ?pager.runCommand(cmd, suspend = true, wait = false, pager.defaultEnv())
  ?chafile.readFile(tmpf, input)
  discard unlink(cstring(tmpf))
  if input.len > 0 and input[input.high] == '\n':
    input.setLen(input.high)
  ok()

proc windowChange(pager: Pager) =
  # maybe we didn't change dimensions, just color mode
  let dimChange = pager.attrs.width != pager.term.attrs.width or
    pager.attrs.height != pager.term.attrs.height or
    pager.attrs.ppc != pager.term.attrs.ppc or
    pager.attrs.ppl != pager.term.attrs.ppl
  pager.attrs = pager.term.attrs
  if dimChange:
    pager.term.unsetScroll()
    if pager.lineedit != nil:
      pager.lineedit.windowChange(pager.attrs)
    for st in SurfaceType:
      pager.clear(st)
    if pager.menu != nil:
      pager.menu.windowChange(pager.bufWidth, pager.bufHeight)
    if pager.askPrompt != "":
      pager.writeAskPrompt()
    pager.queueStatusUpdate()
  for container in pager.containers:
    container.windowChange(pager.attrs)

# Apply siteconf settings to a request.
# Note that this may modify the URL passed.
proc applySiteconf(pager: Pager; url: URL; charsetOverride: Charset;
    loaderConfig: var LoaderClientConfig; ourl: var URL;
    cookieJarId: var string; filterCmd: var string): BufferConfig =
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
  let host = url.host
  let surl = $url
  cookieJarId = host
  for sc in pager.config.siteconf:
    let matches = (case sc.matchType
    of smUrl: sc.match.match(surl)
    of smHost: sc.match.match(host))
    if not matches:
      continue
    if sc.o.rewriteUrl.isSome:
      let fun = sc.o.rewriteUrl.get
      var tmpUrl = newURL(url)
      let arg0 = ctx.toJS(tmpUrl)
      if JS_IsException(arg0):
        pager.alert("Error rewriting URL: " & ctx.getExceptionMsg())
      else:
        let ret = ctx.callSink(fun, JS_UNDEFINED, arg0)
        if not JS_IsException(ret):
          # Warning: we must only print exceptions if the *call* returned one.
          # Conversion may simply error out because the function didn't return a
          # new URL, and that's fine.
          var nu: URL
          if ctx.fromJSFree(ret, nu).isOk:
            tmpUrl = nu
        else:
          #TODO should writeException the message to console
          pager.alert("Error rewriting URL: " & ctx.getExceptionMsg())
      if $tmpUrl != surl:
        ourl = tmpUrl
        return
    if sc.o.cookie.isSome:
      loaderConfig.cookieMode = sc.o.cookie.get
    if sc.o.shareCookieJar.isSome:
      cookieJarId = sc.o.shareCookieJar.get
    if sc.o.scripting.isSome:
      result.scripting = sc.o.scripting.get
    if sc.o.refererFrom.isSome:
      result.refererFrom = sc.o.refererFrom.get
    if sc.o.documentCharset.len > 0:
      result.charsets = sc.o.documentCharset
    if sc.o.images.isSome:
      result.images = sc.o.images.get
    if sc.o.styling.isSome:
      result.styling = sc.o.styling.get
    if sc.o.proxy.isSome:
      loaderConfig.proxy = sc.o.proxy.get
    if sc.o.defaultHeaders != nil:
      loaderConfig.defaultHeaders = sc.o.defaultHeaders
    if sc.o.insecureSslNoVerify.isSome:
      loaderConfig.insecureSslNoVerify = sc.o.insecureSslNoVerify.get
    if sc.o.autofocus.isSome:
      result.autofocus = sc.o.autofocus.get
    if sc.o.metaRefresh.isSome:
      result.metaRefresh = sc.o.metaRefresh.get
    if sc.o.history.isSome:
      result.history = sc.o.history.get
    if sc.o.markLinks.isSome:
      result.markLinks = sc.o.markLinks.get
    if sc.o.userStyle.isSome:
      result.userStyle &= string(sc.o.userStyle.get) & '\n'
    if sc.o.filterCmd.isSome:
      filterCmd = sc.o.filterCmd.get
  loaderConfig.allowSchemes.add(pager.config.external.urimethodmap.imageProtos)
  if result.scripting != smFalse:
    loaderConfig.allowSchemes.add("x-cha-cookie")
  if result.images:
    result.imageTypes = pager.mimeTypes.image
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
proc gotoURL0(pager: Pager; request: Request; save, history: bool;
    bufferConfig: BufferConfig; loaderConfig: LoaderClientConfig;
    title, contentType: string; redirectDepth: int; url: URL;
    replace: Container; filterCmd: string): Container =
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
    pager.replace(replace, container)
    var replace = replace
    let old = replace
    if old.replace != nil:
      # handle replacement chains by just dropping everything in the middle
      replace = old.replace
      pager.deleteContainer(old, nil)
    container.replace = replace
    replace.replaceRef = container
  inc pager.numload
  return container

# Load request in a new buffer.
proc gotoURL(pager: Pager; request: Request; contentType = "";
    charset = CHARSET_UNKNOWN; replace: Container = nil; redirectDepth = 0;
    referrer: Container = nil; save = false; history = true; url: URL = nil;
    title = ""): Container =
  var loaderConfig: LoaderClientConfig
  var bufferConfig: BufferConfig
  var filterCmd: string
  pager.initGotoURL(request, charset, referrer, none(CookieMode), loaderConfig,
    bufferConfig, filterCmd)
  return pager.gotoURL0(request, save, history, bufferConfig, loaderConfig,
    title, contentType, redirectDepth, url, replace, filterCmd)

# Check if the user is trying to go to an anchor of the current buffer.
# If yes, the caller need not call gotoURL.
proc gotoURLHash(pager: Pager; request: Request; current: Container): bool =
  let url = request.url
  if current == nil or not current.url.equals(url, excludeHash = true) or
      url.hash == "" or request.httpMethod != hmGet:
    return false
  let anchor = url.hash.substr(1)
  current.iface.gotoAnchor(anchor, false, false).then(
    proc(res: GotoAnchorResult) =
      if res.y >= 0:
        let nc = pager.dupeBuffer(current, url)
        nc.setCursorXYCenter(res.x, res.y)
      else:
        pager.alert("Anchor " & url.hash & " not found")
  )
  true

proc omniRewrite(pager: Pager; s: string): string =
  for rule in pager.config.omnirule:
    if rule.match.match(s):
      let ctx = pager.jsctx
      let arg0 = ctx.toJS(s)
      if not JS_IsException(arg0):
        let jsRet = ctx.callSink(rule.substituteUrl, JS_UNDEFINED, arg0)
        var res: string
        if not JS_IsException(jsRet) and ctx.fromJSFree(jsRet, res).isOk:
          pager.lineHist[lmLocation].add(s)
          return move(res)
      pager.alert("Exception in omni-rule: " & ctx.getExceptionMsg())
  return s

# When the user has passed a partial URL as an argument, they might've meant
# either:
# * file://$PWD/<file>
# * https://<url>
# So we attempt to load both, and see what works.
proc loadURL(pager: Pager; url: string; contentType = "";
    charset = CHARSET_UNKNOWN; history = true) =
  let url0 = pager.omniRewrite(url)
  if firstParse := parseURL(url0):
    let request = newRequest(firstParse)
    if not pager.gotoURLHash(request, pager.container):
      let container = pager.gotoURL(request, contentType, charset,
        history = history)
      pager.addContainer(container)
    return
  let urls = expandPath(url0)
  if urls.len <= 0:
    return
  let local = percentEncode(urls, LocalPathPercentEncodeSet)
  let cdir = parseURL0("file://" & percentEncode(myposix.getcwd(),
    LocalPathPercentEncodeSet) & DirSep)
  var url = parseURL0(local, cdir) # attempt to load local file
  var retry: URL = nil
  if pager.config.network.prependScheme != "" and urls[0] != '/':
    # attempt to load remote page
    retry = parseURL0(pager.config.network.prependScheme & urls)
  if url == nil:
    url = move(retry)
  if url != nil:
    let container = pager.gotoURL(newRequest(url), contentType,
      charset = charset, history = history)
    container.retry = retry
    pager.addContainer(container)
  else:
    pager.alert("Invalid URL " & urls)

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
    c = pager.gotoURL(newRequest(url), history = false)
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
  let container = pager.gotoURL(newRequest(url), contentType, cs, title = title)
  pager.addContainer(container)

proc getHistoryURL(pager: Pager): URL {.jsfunc.} =
  let tmpf = pager.getTempFile()
  discard unlink(cstring(tmpf))
  let ps = newPosixStream(tmpf, O_WRONLY or O_CREAT or O_EXCL, 0o600)
  if ps == nil:
    return nil
  ps.setCloseOnExec()
  let hist = pager.lineHist[lmLocation]
  if hist.write(ps, sync = false, reverse = true).isErr:
    pager.alert("failed to write history")
  return parseURL0("file:" & tmpf)

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
      title = ConsoleTitle, history = false)
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
      replace = pager.pinned.console, title = ConsoleTitle, history = false)
    pager.pinned.console = console
    pager.addTab(console)

proc addConsole(pager: Pager; interactive: bool) =
  if interactive and pager.config.start.consoleBuffer:
    if f := pager.addConsoleFile():
      discard f.writeLine("Type (M-c) console.hide() to return to buffer mode.")
      discard f.flush()
      pager.console.clearFun = proc() =
        pager.clearConsole()
      pager.console.showFun = proc() =
        pager.showConsole()
      pager.console.hideFun = proc() =
        pager.hideConsole()
      pager.console.err = f
      return
    pager.alert("Failed to open temp file for console")
  pager.console.err = cast[ChaFile](stderr)

proc openEditor(ctx: JSContext; pager: Pager; s: string): JSValue {.jsfunc.} =
  var s = s
  if pager.openEditor(s).isOk:
    return ctx.toJS(s)
  return JS_NULL

proc saveTo(pager: Pager; data: LineDataDownload; path: string) =
  if pager.loader.redirectToFile(data.outputId, path, data.url):
    pager.alert("Saving file to " & path)
    pager.loader.resume(data.outputId)
    data.stream.sclose()
    if pager.config.external.showDownloadPanel:
      let request = newRequest("about:downloads")
      let old = pager.pinned.downloads
      let downloads = pager.gotoURL(request, history = false,
        replace = old)
      if old == nil:
        pager.addContainer(downloads)
      else:
        pager.setContainer(downloads)
      pager.pinned.downloads = downloads
  else:
    pager.ask("Failed to save to " & path & ". Retry?").then(
      proc(x: bool) =
        if x:
          pager.setLineEdit2(lmDownload, "(Download)Save file to: ", path)
        else:
          data.stream.sclose()
    )

proc updateReadLine(pager: Pager) {.jsfunc.} =
  let line = pager.lineedit
  let ctx = pager.jsctx
  case line.state
  of lesEdit:
    if pager.linemode == lmScript:
      let lineData = LineDataScript(line.data)
      if not JS_IsUndefined(lineData.update):
        let res = ctx.call(lineData.update, JS_UNDEFINED)
        if JS_IsException(res):
          pager.console.writeException(ctx)
        JS_FreeValue(ctx, res)
  of lesFinish:
    case pager.linemode
    of lmScript:
      let lineData = LineDataScript(line.data)
      JS_FreeValue(ctx, lineData.update)
      let text = ctx.toJS(line.text)
      if JS_IsException(text):
        pager.console.writeException(ctx)
      else:
        let res = ctx.callSinkFree(lineData.resolve, JS_UNDEFINED, text)
        if JS_IsException(res):
          pager.console.writeException(ctx)
        JS_FreeValue(ctx, res)
    of lmUsername:
      let data = LineDataAuth(line.data)
      data.url.username = line.text
      pager.setLineEdit0(lmPassword, "Password: ", "", hide = true, data)
    of lmPassword:
      let lineData = LineDataAuth(line.data)
      let old = lineData.container
      let url = lineData.url
      url.password = line.text
      let container = pager.gotoURL(newRequest(url), referrer = old)
      pager.replace(old, container)
    of lmBuffer: pager.container.readSuccess(line.text)
    of lmBufferFile:
      if path := ChaPath(line.text).unquote(myposix.getcwd()):
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
        pager.alert("Invalid path: " & line.text)
        pager.container.readCanceled()
    of lmDownload:
      let data = LineDataDownload(line.data)
      let path = ChaPath(line.text).unquote(myposix.getcwd())
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
                pager.setLineEdit2(lmDownload, "(Download)Save file to: ",
                  path)
          )
        else:
          pager.saveTo(data, path)
    of lmMailcap:
      var mailcap = Mailcap.default
      let res = mailcap.parseMailcap(line.text, "<input>")
      let data = LineDataMailcap(line.data)
      if res.isOk and mailcap.len == 1:
        let res = pager.runMailcap(data.container.url, data.ostream,
          data.response.outputId, data.contentType, mailcap[0])
        pager.connected2(data.container, res, data.response)
      else:
        if res.isErr:
          pager.alert(res.error)
        pager.askMailcap(data.container, data.ostream, data.contentType,
          data.i, data.response, data.sx)
    else: discard
  of lesCancel:
    case pager.linemode
    of lmScript:
      let lineData = LineDataScript(line.data)
      JS_FreeValue(ctx, lineData.update)
      let res = ctx.callFree(lineData.resolve, JS_UNDEFINED, JS_NULL)
      if JS_IsException(res):
        pager.console.writeException(ctx)
      JS_FreeValue(ctx, res)
    of lmUsername, lmPassword: pager.discardBuffer()
    of lmBuffer: pager.container.readCanceled()
    of lmDownload:
      let data = LineDataDownload(line.data)
      data.stream.sclose()
    of lmMailcap:
      let data = LineDataMailcap(line.data)
      pager.askMailcap(data.container, data.ostream, data.contentType,
        data.i, data.response, data.sx)
    else: discard
  if line.state in {lesCancel, lesFinish} and pager.lineedit == line:
    pager.lineedit = nil
    pager.queueStatusUpdate()

proc loadSubmit(pager: Pager; s: string) {.jsfunc.} =
  pager.loadURL(s)

# Go to specific URL (for JS)
type GotoURLDict = object of JSDict
  contentType {.jsdefault.}: Option[string]
  replace {.jsdefault.}: Option[Container]
  save {.jsdefault.}: bool
  history {.jsdefault.}: bool
  scripting {.jsdefault.}: Option[ScriptingMode]
  cookie {.jsdefault.}: Option[CookieMode]
  charset {.jsdefault.}: Option[Charset]
  url {.jsdefault.}: Option[URL]

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
  pager.initGotoURL(request, t.charset.get(CHARSET_UNKNOWN), referrer = nil,
    t.cookie, loaderConfig, bufferConfig, filterCmd)
  bufferConfig.scripting = t.scripting.get(bufferConfig.scripting)
  let replace = t.replace.get(nil)
  let container = pager.gotoURL0(request, t.save, t.history, bufferConfig,
    loaderConfig, title = "", t.contentType.get(""), redirectDepth = 0,
    url = t.url.get(nil), replace, filterCmd)
  if replace == nil:
    pager.addContainer(container)
  ok(container)

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
  ok(pager.runCommand(cmd, t.suspend, t.wait, env).isOk)

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
  JS_SetUncatchableException(ctx, true)
  return JS_EXCEPTION

proc clipboardWrite(ctx: JSContext; pager: Pager; s: string; clipboard = true):
    JSValue {.jsfunc.} =
  if res := pager.term.sendOSC52(s, clipboard):
    if res:
      return JS_TRUE
    if not clipboard:
      return JS_FALSE
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

# Execute cmd, with ps moved onto stdin, os onto stdout, and the browser
# console onto stderr.
# ps remains open, but os is consumed.
proc execPipe(pager: Pager; cmd: string; ps, os: PosixStream): int =
  var oldint, oldquit: Sigaction
  var act = Sigaction(sa_handler: SIG_IGN, sa_flags: SA_RESTART)
  var oldmask, dummy: Sigset
  let westream = pager.forkserver.westream
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
    westream.moveFd(STDERR_FILENO)
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
  let i = pager.autoMailcap.findMailcapEntry("text/x-ansi", "", url)
  if i == -1:
    pager.alert("No text/x-ansi entry found")
    return nil
  var canpipe = true
  let cmd = unquoteCommand(pager.autoMailcap[i].cmd, "text/x-ansi", "", url,
    canpipe)
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
      while waitpid(pid, x, 0) == -1:
        if errno != EINTR:
          break
      discard pager.term.restart() #TODO

proc writeToFile(istream: PosixStream; outpath: string): bool =
  discard unlink(cstring(outpath))
  let ps = newPosixStream(outpath, O_WRONLY or O_CREAT or O_EXCL, 0o600)
  if ps == nil:
    return false
  var buffer {.noinit.}: array[4096, uint8]
  var n = 0
  while (n = istream.read(buffer); n > 0):
    if ps.writeLoop(buffer.toOpenArray(0, n - 1)).isErr:
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
  discard mkdir(cstring($pager.config.external.tmpdir), 0o700)
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
    let isansi = mfAnsioutput in entry.flags
    if not ishtml and isansi:
      let pins2 = pager.ansiDecode(url, ishtml, pins)
      if pins2 == nil:
        pins.sclose()
        break needsConnect
      pins = pins2
    twtstr.unsetEnv("MAILCAP_URL")
    let url = parseURL0("stream:" & $pid)
    pager.loader.passFd(url.pathname, pins.fd)
    pins.sclose()
    let response = pager.loader.doRequest(newRequest(url))
    var flags = {cmfConnect, cmfFound, cmfRedirected}
    if mfNeedsstyle in entry.flags or isansi:
      # ansi always needs styles
      #TOOD ideally, x-ansioutput should also switch the content type so
      # that the UA style applies
      flags.incl(cmfNeedsstyle)
    if mfNeedsimage in entry.flags:
      flags.incl(cmfNeedsimage)
    if mfSaveoutput in entry.flags:
      flags.incl(cmfSaveoutput)
    if ishtml or isansi:
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
  if save or not pager.gotoURLHash(request, container):
    let nc = pager.gotoURL(request, redirectDepth = container.redirectDepth + 1,
      referrer = container, save = save, history = cfHistory in container.flags)
    if nc != nil:
      let replace = container.replace
      pager.replace(container, nc)
      if replace != nil:
        container.replace = nil
        replace.replaceRef = nc
        nc.replace = replace
      nc.setLoadInfo("Redirecting to " & $request.url)
  dec pager.numload

proc fail(pager: Pager; container: Container; errorMessage: string) =
  dec pager.numload
  if container.replace != nil: # deleteContainer unsets replace etc.
    pager.replace(container, container.replace)
  pager.deleteContainer(container, container.find(ndAny))
  if container.retry != nil:
    let container = pager.gotoURL(newRequest(move(container.retry)),
      container.contentType, history = cfHistory in container.flags)
    pager.addContainer(container)
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
  container.applyResponse(response, pager.mimeTypes)
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
  pager.setLineEdit0(lmDownload, "(Download)Save file to: ", buf, hide = false,
      LineDataDownload(
    outputId: response.outputId,
    stream: stream,
    url: container.url
  ))
  pager.deleteContainer(container, container.find(ndAny))
  pager.queueStatusUpdate()
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
      container.contentType.untilLower(';')
    )
    if pid == -1:
      res.ostream.sclose()
      pager.fail(container, "Error forking new process for buffer")
    else:
      container.phandle.process = pid
      pager.connected3(container, cstream, res.ostream, response.outputId,
        res.ostreamOutputId, cmfRedirected in res.flags)
  else:
    dec pager.numload
    pager.deleteContainer(container, container.find(ndAny))
    pager.queueStatusUpdate()

proc connected3(pager: Pager; container: Container; stream: SocketStream;
    ostream: PosixStream; istreamOutputId, ostreamOutputId: int;
    redirected: bool) =
  let loader = pager.loader
  let cstream = loader.addClient(container.process, container.loaderConfig)
  if cstream == nil:
    stream.sclose()
    ostream.sclose()
    pager.alert("failed to create new loader client")
    return
  let bufStream = newBufStream(stream, proc(fd: int) =
    pager.pollData.unregister(fd)
    pager.pollData.register(fd, POLLIN or POLLOUT))
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
  container.setStream(bufStream)
  cstream.sclose()
  loader.put(ContainerData(stream: stream, container: container))
  pager.pollData.register(stream.fd, POLLIN)

proc cloned(pager: Pager; container: Container; stream: SocketStream) =
  let loader = pager.loader
  let bufStream = newBufStream(stream, proc(fd: int) =
    pager.pollData.unregister(fd)
    pager.pollData.register(fd, POLLIN or POLLOUT))
  # add a reference to parent's cached source; it will be removed when the
  # container is deleted
  discard loader.shareCachedItem(container.cacheId, loader.clientPid)
  container.setStream(bufStream)
  loader.put(ContainerData(stream: stream, container: container))
  pager.pollData.register(stream.fd, POLLIN)

proc saveEntry(pager: Pager; entry: MailcapEntry) =
  let path = $pager.config.external.autoMailcap
  if pager.autoMailcap.saveEntry(path, entry).isErr:
    pager.alert("Could not write to " & $path)

proc askMailcapMsg(pager: Pager; shortContentType: string; i: int; sx: var int;
    prev, next: int): string =
  var msg = "Open " & shortContentType & " as (shift=always): (t)ext, (s)ave"
  if i != -1:
    msg &= ", (r)un \"" & pager.mailcap[i].cmd.strip() & '"'
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
    prev = pager.mailcap.findPrevMailcapEntry(contentType, "", container.url, i)
    next = pager.mailcap.findMailcapEntry(contentType, "", container.url, i)
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
        s = $pager.mailcap[i]
        while s.len > 0 and s[^1] == '\n':
          s.setLen(s.high)
      pager.setLineEdit0(lmMailcap, "Mailcap: ", s, hide = false,
          data = LineDataMailcap(
        container: container,
        ostream: ostream,
        contentType: contentType,
        i: i,
        response: response,
        sx: sx
      ))
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
          contentType, pager.mailcap[i])
        pager.connected2(container, res, response)
        if c == 'R':
          pager.saveEntry(pager.mailcap[i])
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
  container.applyResponse(response, pager.mimeTypes)
  if response.status == 401: # unauthorized
    let url = newURL(container.url)
    pager.setLineEdit0(lmUsername, "Username: ", container.url.username,
      hide = false, LineDataAuth(container: container, url: url))
    istream.sclose()
    return
  # This forces client to ask for confirmation before quitting.
  pager.hasload = true
  if cfHistory in container.flags:
    pager.lineHist[lmLocation].add($container.url)
  # contentType must have been set by applyResponse.
  let shortContentType = container.contentType.untilLower(';')
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
    let i = pager.autoMailcap.findMailcapEntry(contentType, "", container.url)
    if i != -1:
      let res = pager.runMailcap(container.url, istream, response.outputId,
        contentType, pager.autoMailcap[i])
      pager.connected2(container, res, response)
    else:
      let i = pager.mailcap.findMailcapEntry(contentType, "", container.url)
      if pager.config.start.headless != hmFalse or
          i == -1 and shortContentType.isTextType():
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
        container.setLoadInfo("Connected to " & $container.url &
          ". Downloading...")
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
  ("Select text              (v)", "selectOrCopy"),
  ("Previous buffer          (,)", "prevBuffer"),
  ("Next buffer              (.)", "nextBuffer"),
  ("Discard buffer           (D)", "discardBuffer"),
  ("────────────────────────────", ""),
  ("Copy page URL          (M-y)", "copyURL"),
  ("Copy link               (yu)", "copyCursorLink"),
  ("View image               (I)", "viewImage"),
  ("Copy image link         (yI)", "copyCursorImage"),
  ("Reload                   (U)", "reloadBuffer"),
  ("────────────────────────────", ""),
  ("Save link             (sC-m)", "saveLink"),
  ("View source              (\\)", "toggleSource"),
  ("Edit source             (sE)", "sourceEdit"),
  ("Save source             (sS)", "saveSource"),
  ("────────────────────────────", ""),
  ("Linkify URLs             (:)", "markURL"),
  ("Toggle images          (M-i)", "toggleImages"),
  ("Toggle JS & reload     (M-j)", "toggleScripting"),
  ("Toggle cookie & reload (M-k)", "toggleCookie"),
  ("────────────────────────────", ""),
  ("Bookmark page          (M-a)", "addBookmark"),
  ("Open bookmarks         (M-b)", "openBookmarks"),
  ("Open history           (C-h)", "openHistory"),
]

proc menuFinish(opaque: RootRef; select: Select) =
  let pager = Pager(opaque)
  pager.menu = nil
  if select.selected != -1:
    pager.evalAction(MenuMap[select.selected][1], 0)
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

proc closeMenu(pager: Pager) {.jsfunc.} =
  if pager.menu != nil:
    pager.menuFinish(pager.menu)

proc cancel(pager: Pager) {.jsfunc.} =
  let container = pager.container
  if container == nil or container.loadState != lsLoading:
    return
  container.loadState = lsCanceled
  container.setLoadInfo("")
  if container.iface != nil:
    container.cancel()
  elif (let item = pager.findConnectingContainer(container); item != nil):
    dec pager.numload
    # closes item's stream
    pager.deleteContainer(container, container.find(ndAny))
  else:
    return
  pager.alert("Canceled loading")

proc handleEvent0(pager: Pager; container: Container; event: ContainerEvent) =
  case event.t
  of cetLoaded:
    if container.replace != nil:
      let replace = container.replace
      replace.replaceRef = nil
      container.replace = nil
      pager.deleteContainer(replace, container)
    dec pager.numload
    if pager.container == container:
      if pager.alertState == pasLoadInfo:
        pager.alertState = pasNormal
      pager.queueStatusUpdate()
  of cetReadLine, cetReadPassword:
    if container == pager.container:
      pager.setLineEdit2(lmBuffer, event.prompt, event.value,
        event.t == cetReadPassword)
  of cetReadArea:
    if container == pager.container:
      var s = event.tvalue
      if pager.openEditor(s).isOk:
        pager.container.readSuccess(s)
      else:
        pager.container.readCanceled()
  of cetReadFile:
    if container == pager.container:
      pager.setLineEdit2(lmBufferFile, "(Upload)Filename: ")
  of cetOpen, cetSave:
    let request = event.request
    let contentType = event.contentType
    let save = event.t == cetSave
    let url = request.url
    let sameScheme = container.url.scheme == url.scheme
    if request.httpMethod != hmGet and not sameScheme and
        not (container.url.schemeType in {stHttp, stHttps} and
          url.schemeType in {stHttp, stHttps}):
      pager.alert("Blocked cross-scheme POST: " & $url)
      return
    #TODO this is horrible UX, async actions shouldn't block input
    if pager.container != container or
        not save and not container.isHoverURL(url):
      pager.ask("Open pop-up? " & $url).then(proc(x: bool) =
        if x and (save or not pager.gotoURLHash(request, container)):
          let container = pager.gotoURL(request, contentType,
            referrer = container, save = save)
          pager.addContainer(container)
      )
    elif (save or not pager.gotoURLHash(request, container)):
      let container = pager.gotoURL(request, contentType, referrer = container,
        save = save)
      pager.addContainer(container)
  of cetStatus:
    if pager.container == container:
      pager.showAlerts()
  of cetSetLoadInfo:
    if pager.container == container:
      pager.onSetLoadInfo(container)
  of cetTitle:
    if pager.container == container:
      if container.loadState != lsLoading:
        pager.queueStatusUpdate()
      pager.updateTitle()
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

proc handleEvents(pager: Pager) {.jsfunc.} =
  if pager.container != nil:
    pager.handleEvents(pager.container)

proc handleEvent(pager: Pager; container: Container) =
  if container.handleEvent().isOk:
    pager.handleEvents(container)

proc handleStderr(pager: Pager) =
  const BufferSize = 4096
  const prefix = "STDERR: "
  var buffer {.noinit.}: array[BufferSize, char]
  let estream = pager.forkserver.estream
  var hadlf = true
  while true:
    let n = estream.read(buffer)
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
  elif fd in pager.loader.unregistered:
    discard # ignore (see handleError)
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
  else:
    assert false
  ok()

proc handleWrite(pager: Pager; fd: int): Opt[void] =
  if pager.term.ostream != nil and pager.term.ostream.fd == fd:
    if ?pager.term.flush():
      pager.pollData.unregister(pager.term.ostream.fd)
      pager.term.registeredFlag = false
  elif fd in pager.loader.unregistered:
    discard # ignore (see handleError)
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
  elif fd in pager.loader.unregistered:
    # this fd is already unregistered in this cycle.
    # it is possible that another handle has taken the same fd number, in
    # that case we must suppress the error in this cycle and wait for the
    # next one.
    discard
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
      container.flags.incl(cfCrashed)
      pager.unregisterContainer(container)
      pager.console.error("Error in buffer", $container.url)
      pager.console.flush()
      if not isConsole:
        pager.showConsole()
      dec pager.numload
    else:
      discard pager.loader.onError(fd) #TODO handle connection error?
  else:
    pager.showConsole()
  ok()

let SIGWINCH {.importc, header: "<signal.h>", nodecl.}: cint

proc setupSignals(pager: Pager): PosixStream =
  var pipefd {.noinit.}: array[2, cint]
  doAssert pipe(pipefd) != -1
  let writer = newPosixStream(pipefd[1])
  writer.setCloseOnExec()
  writer.setBlocking(false)
  var gwriter {.global.}: PosixStream = nil
  gwriter = writer
  onSignal SIGWINCH, SIGCHLD:
    let n = if sig == SIGCHLD: 1u8 else: 0u8
    discard gwriter.write([n])
  let reader = newPosixStream(pipefd[0])
  reader.setCloseOnExec()
  reader.setBlocking(false)
  return reader

proc handleSigchld(pager: Pager): Opt[void] =
  var wstatus: cint
  var pid: int
  while (pid = int(waitpid(Pid(-1), wstatus, WNOHANG)); pid == -1):
    if errno != EINTR:
      return err() # ECHILD, stop looking
  var cmd: string
  if pager.pidMap.pop(pid, cmd):
    if WIFEXITED(wstatus):
      let n = WEXITSTATUS(wstatus)
      if n != 0:
        pager.alert("Command " & cmd & " exited with code " & $n)
    elif WIFSIGNALED(wstatus):
      let sig = WTERMSIG(wstatus)
      # following were likely sent by the user, so don't bother alerting
      if sig != SIGINT and sig != SIGTERM and sig != SIGKILL:
        pager.alert("Command " & cmd & " crashed")
  ok()

proc inputLoop(pager: Pager): Opt[void] =
  pager.pollData.register(pager.term.istream.fd, POLLIN)
  let signals = pager.setupSignals()
  pager.pollData.register(signals.fd, POLLIN)
  while true:
    let timeout = pager.timeouts.sortAndGetTimeout()
    pager.pollData.poll(timeout)
    pager.loader.blockRegister()
    for event in pager.pollData.events:
      let efd = int(event.fd)
      if (event.revents and POLLIN) != 0:
        if event.fd == signals.fd:
          var sigwinch = false
          var sigchld = 0u
          var buffer {.noinit.}: array[256, uint8]
          while (let n = signals.read(buffer); n > 0):
            for c in buffer.toOpenArray(0, n - 1):
              if c == 1: # SIGCHLD
                inc sigchld
              else: # 0, SIGWINCH
                sigwinch = true
          for u in 0 ..< sigchld:
            if pager.handleSigchld().isErr:
              break
          if sigwinch:
            ?pager.term.queryWindowSize()
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
    if pager.container == nil and pager.lineedit == nil:
      # No buffer to display.
      # Perhaps we failed to load every single URL the user passed us...
      if pager.hasload:
        # ...or at least one connection has succeeded, but we have nothing
        # to display.  Normally, this means that the input stream has been
        # redirected to a file or to an external program, so we can't just
        # exit without potentially interrupting that stream.
        #TODO: a better UI would be querying the number of ongoing streams in
        # loader, and then asking for confirmation if there is at least one.
        discard pager.term.anyKey("Hit any key to quit Chawan:", bottom = true)
      return err()
    case pager.updateStatus
    of ussNone, ussSkip: discard
    of ussUpdate: pager.refreshStatusMsg()
    pager.updateStatus = ussNone
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
      if pager.drawBuffer(container).isOk:
        pager.handleEvents(container)
      else:
        pager.console.error("Error in buffer", $container.url)
        # check for errors
        discard pager.handleRead(pager.forkserver.estream.fd)
        return

proc addPagerModule*(ctx: JSContext) =
  ctx.registerType(Pager)

{.pop.} # raises: []
