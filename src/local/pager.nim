{.push raises: [].}

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
import local/lineEdit
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
    lmAlert = "alert"
    lmMailcap = "mailcap"

  PagerAlertState = enum
    pasNormal = "normal"
    pasAlertOn = "alertOn"
    pasLoadInfo = "loadInfo"

  BufferConnectionState = enum
    bcsBeforeResult, bcsBeforeStatus

  ConnectingBuffer = ref object of MapData
    state: BufferConnectionState
    init: BufferInit
    res: int
    outputId: int

  SurfaceType = enum
    stDisplay, stStatus

  Surface = object
    redraw: bool
    grid: FixedGrid

  UpdateStatusState = enum
    ussNone, ussUpdate, ussSkip

  JSMap = object
    # workaround for the annoying warnings (too lazy to fix them)
    pager: JSValue
    handleInput: JSValue
    showConsole: JSValue
    askPromise: JSValue # function to resolve on ask finish

  Pager* = ref object of RootObj
    blockTillRelease: bool
    hasload: bool # has a page been successfully loaded since startup?
    dumpConsoleFile: bool
    feedNext {.jsgetset.}: bool
    updateStatus: UpdateStatusState
    consoleCacheId {.jsget.}: int # private
    consoleFile: string
    alertState {.jsgetset.}: PagerAlertState # private
    # current number prefix (when vi-numeric-prefix is true)
    precnum {.jsgetset.}: int32 # private
    arg0 {.jsget.}: int32 # private
    alerts: seq[string]
    askCursor: int
    askPrompt: string
    config: Config
    console: Console
    cookieJars: CookieJarMap
    surfaces: array[SurfaceType, Surface]
    consoleInit {.jsgetset.}: BufferInit
    exitCode: int
    forkserver: ForkServer
    inputBuffer: string # currently uninterpreted characters
    jsctx: JSContext
    lastAlert {.jsget.}: string # last alert seen by the user
    lineHist: array[LineMode, History]
    lineEdit* {.jsget.}: LineEdit # private
    loader: FileLoader
    loaderPid {.jsget.}: int
    luctx: LUContext
    menu {.jsget.}: Select
    numload {.jsgetset.}: int # number of pages currently being loaded
    term*: Terminal
    timeouts*: TimeoutState
    tmpfSeq: uint
    attrs: WindowAttributes
    pidMap: Table[int, string] # pid -> command
    jsmap: JSMap
    autoMailcap: Mailcap
    mailcap: Mailcap
    mimeTypes: MimeTypes
    bufferInit {.jsget.}: BufferInit # visible BufferInit (may != iface.init)
    bufferIface {.jsget.}: BufferInterface # visible BufferInterface
    bufferAtom: JSAtom

  CheckMailcapFlag = enum
    cmfConnect, cmfHTML, cmfRedirected, cmfPrompt, cmfNeedsstyle,
    cmfNeedsimage, cmfSaveoutput

  MailcapResult = object
    entry: MailcapEntry
    flags: set[CheckMailcapFlag]
    ostream: PosixStream
    ostreamOutputId: int
    cmd: string

jsDestructor(Pager)

# Forward declarations
proc addConsole2(pager: Pager; interactive: bool)
proc alert(pager: Pager; msg: string)
proc redraw(pager: Pager)
proc quit(pager: Pager; code: int)
proc windowChange(pager: Pager): Opt[void]

# private
proc bufWidth(pager: Pager): int {.jsfget.} =
  return pager.attrs.width

# private
proc bufHeight(pager: Pager): int {.jsfget.} =
  return pager.attrs.height - 1

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

# private
proc statusWidth(pager: Pager): int {.jsfget.} =
  return pager.status.grid.width

# private
proc updateTitle(pager: Pager; init: BufferInit) {.jsfunc.} =
  pager.term.queueTitle(init.title)

# private
proc clearCachedImages(pager: Pager; iface: BufferInterface) {.jsfunc.} =
  if pager.term.imageMode != imNone:
    iface.clearCachedImages(pager.loader)

# private
proc setBufferInit(ctx: JSContext; pager: Pager; init: Option[BufferInit])
    {.jsfset: "bufferInit".} =
  pager.bufferInit = init.get(nil)

# private
proc setBufferIface(ctx: JSContext; pager: Pager; iface: BufferInterface) {.
    jsfset: "bufferIface".} =
  pager.bufferIface = iface

proc getHist(pager: Pager; mode: LineMode): History =
  if pager.lineHist[mode] == nil:
    pager.lineHist[mode] = newHistory(100)
  return pager.lineHist[mode]

# private
proc setLineEdit0(ctx: JSContext; pager: Pager; mode: LineMode; prompt: string;
    obj: JSValueConst = JS_UNDEFINED): JSValue {.jsfunc.} =
  var current = ""
  var hide = false
  var update = JS_UNDEFINED
  if not JS_IsUndefined(obj):
    if ctx.fromJSGetProp(obj, "current", current).isErr:
      return JS_EXCEPTION
    if ctx.fromJSGetProp(obj, "hide", hide).isErr:
      return JS_EXCEPTION
    update = JS_GetPropertyStr(ctx, obj, "update")
    if JS_IsException(update):
      return JS_EXCEPTION
  var funs {.noinit.}: array[2, JSValue]
  let res = JS_NewPromiseCapability(ctx, funs.toJSValueArray())
  if JS_IsException(res):
    JS_FreeValue(ctx, update)
    return JS_EXCEPTION
  JS_FreeValue(ctx, funs[1])
  let hist = pager.getHist(mode)
  pager.lineEdit = readLine(prompt, current, pager.attrs.width, hide, hist,
    pager.luctx, update, funs[0])
  return res

# private
proc unsetLineEdit(pager: Pager) {.jsfunc.} =
  pager.lineEdit = nil

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
  let headless = pager.config.start.headless != hmFalse
  if not headless:
    pager.term.catchSigint()
  let ret = ctx.eval(src, filename, JS_EVAL_TYPE_GLOBAL)
  if not headless:
    pager.term.respectSigint()
  if JS_IsException(ret):
    pager.console.writeException(ctx)
  JS_FreeValue(ctx, ret)

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
    consoleCacheId: -1,
    console: console,
    bufferAtom: JS_NewAtom(ctx, cstring"buffer"),
  )
  pager.timeouts = newTimeoutState(pager.jsctx, evalJSFree, pager)
  pager.jsmap = JSMap(
    pager: ctx.toJS(pager),
    handleInput: ctx.eval("Pager.prototype.handleInput", "<init>",
      JS_EVAL_TYPE_GLOBAL),
    showConsole: ctx.eval("Pager.prototype.showConsole", "<init>",
      JS_EVAL_TYPE_GLOBAL),
    askPromise: JS_UNDEFINED
  )
  for field in pager.jsmap.fields:
    doAssert not JS_IsException(field)
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
      let res = pager.mimeTypes.parseMimeTypes(f)
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
  # Decrement refcount of action maps.  This is needed so that refc
  # actually cleans them up.
  # (For some reason, doing the same with config doesn't work.)
  pager.config.line = nil
  pager.config.page = nil
  ctx.freeValues(pager.config.omnirule)
  ctx.freeValues(pager.config.siteconf)
  JS_FreeAtom(ctx, pager.bufferAtom)
  for val in pager.jsmap.fields:
    JS_FreeValue(ctx, val)
  pager.timeouts.clearAll()
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

proc runJSJobs(pager: Pager): Opt[void] =
  let rt = JS_GetRuntime(pager.jsctx)
  while true:
    let ctx = rt.runJSJobs()
    if ctx == nil:
      break
    pager.console.writeException(ctx)
  if pager.exitCode != -1:
    return err()
  ok()

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

# private
proc writeInputBuffer(ctx: JSContext; pager: Pager): JSValue {.jsfunc.} =
  if pager.lineEdit != nil:
    let res = ctx.write(pager.lineEdit, pager.inputBuffer)
    pager.inputBuffer.setLen(0)
    return res
  return JS_UNDEFINED

# private
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

# private
proc queueStatusUpdate(pager: Pager) {.jsfunc.} =
  if pager.updateStatus == ussNone:
    pager.updateStatus = ussUpdate

# private
# called from JS command()
proc evalCommand(ctx: JSContext; pager: Pager; src: string): JSValue
    {.jsfunc.} =
  if pager.consoleInit != nil:
    pager.consoleInit.flags.incl(bifTailOnLoad)
  return ctx.eval(src, "<command>",
    JS_EVAL_TYPE_GLOBAL or JS_EVAL_FLAG_BACKTRACE_BARRIER)

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

# private
proc osc52Primary(pager: Pager): bool {.jsfget.} =
  pager.term.osc52Primary

# The maximum number we are willing to accept.
# This should be fine for 32-bit signed ints (which precnum currently is).
const MaxPrecNum = 100000000

# private
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
    of ietWindowChange: ?pager.windowChange()
    of ietRedraw: pager.redraw()
    of ietKeyEnd, ietPaste, ietMouse:
      let ctx = pager.jsctx
      let arg0 = ctx.toJS(e.t)
      if JS_IsException(arg0):
        pager.console.writeException(ctx)
        break
      let arg1 = if e.t == ietMouse: ctx.toJS(e.m) else: JS_UNDEFINED
      pager.term.catchSigint()
      let res = ctx.callSink(pager.jsmap.handleInput, pager.jsmap.pager, arg0,
        arg1)
      pager.term.respectSigint()
      if JS_IsException(res):
        if pager.exitCode != -1: # quit() called
          return err()
        # user code, so catch & log exceptions here
        pager.console.writeException(ctx)
      JS_FreeValue(ctx, res)
  ok()

# private
proc runStartupScript(ctx: JSContext; pager: Pager): JSValue {.jsfunc.} =
  if pager.config.start.startupScript == "":
    return JS_UNDEFINED
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
  return ctx.eval(s, pager.config.start.startupScript, flag)

proc run*(pager: Pager; pages: openArray[JSValue]; contentType: string;
    charset: Charset; history: bool) =
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
  pager.loader.pollData.register(pager.forkserver.estream.fd, POLLIN)
  let sr = pager.term.start(istream, proc(fd: cint) =
    pager.loader.pollData.register(fd, POLLOUT))
  if sr.isErr:
    return
  pager.attrs = pager.term.attrs
  for st in SurfaceType:
    pager.clear(st)
  pager.addConsole2(istream != nil)
  let pipe = not ps.isatty()
  if pipe:
    pager.loader.passFd("-", ps.fd)
  # we don't want history for dump/headless mode
  let history = pager.config.start.headless == hmFalse and history
  let ctx = pager.jsctx
  let pages = ctx.newArrayFrom(pages)
  let jsInit = ctx.eval("Pager.prototype.init", "<init>", JS_EVAL_TYPE_GLOBAL)
  doAssert not JS_IsException(jsInit)
  let res = ctx.callSinkFree(jsInit, pager.jsmap.pager, pages,
    ctx.toJS(contentType), ctx.toJS(charset), ctx.toJS(history), ctx.toJS(pipe))
  if JS_IsException(res) and pager.exitCode == -1:
    pager.console.writeException(ctx)
  JS_FreeValue(ctx, res)
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
  let init = pager.bufferInit
  if init == nil or pager.askPrompt != "":
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
    let fgcolor = if bifCrashed in init.flags:
      ANSIColor(1).cellColor()
    else:
      defaultColor
    var format = initFormat(defaultColor, fgcolor,
      pager.config.status.formatMode)
    pager.alertState = pasNormal
    var msg = ""
    let iface = pager.bufferIface
    if pager.config.status.showCursorPosition and iface != nil and
        iface.numLines > 0:
      msg &= $(iface.cursory + 1) & "/" & $iface.numLines &
        " (" & $iface.atPercentOf() & "%)"
    else:
      msg &= "Viewing"
    if bifCrashed in init.flags:
      msg &= " CRASHED!"
    msg &= " <" & init.title
    let hover = if pager.config.status.showHoverLink and iface != nil:
      iface.getHoverText()
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
    if iface == nil or iface.numLines == 0:
      msg &= "\tNo Line"
    discard pager.status.writeStatusMessage(msg, format)

# Call refreshStatusMsg if no alert is being displayed on the screen.
# Alerts take precedence over load info, but load info is preserved when no
# pending alerts exist.
# private
proc showAlerts(pager: Pager) {.jsfunc.} =
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

# private
proc drawBuffer(pager: Pager; iface: BufferInterface): Opt[bool] {.jsfunc.} =
  let ctx = pager.jsctx
  let res = ctx.requestLinesSync(iface, proc(line: SimpleFlexibleLine):
      Opt[void] =
    let term = pager.term
    var x = 0
    var i = 0
    let bgcolor = iface.bgcolor
    let bgformat = term.reduceFormat(initFormat(bgcolor, defaultColor, {}))
    if bgcolor != defaultColor and
        (line.formats.len == 0 or line.formats[0].pos > 0):
      ?term.processFormat(bgformat)
    for f in line.formats:
      var ff = f.format
      if ff.bgcolor == defaultColor:
        ff.bgcolor = iface.bgcolor
      let termBgcolor = term.getCurrentBgcolor()
      let ls = line.str.drawBufferAdvance(termBgcolor, i, x, f.pos)
      ?term.processOutputString(ls, trackCursor = false)
      if i < line.str.len:
        ?term.processFormat(term.reduceFormat(ff))
    if i < line.str.len:
      let termBgcolor = term.getCurrentBgcolor()
      let ls = line.str.drawBufferAdvance(termBgcolor, i, x, int.high)
      ?term.processOutputString(ls, trackCursor = false)
    if bgcolor != defaultColor and x < iface.init.width:
      ?term.processFormat(bgformat)
      let spaces = ' '.repeat(iface.init.width - x)
      ?term.processOutputString(spaces, trackCursor = false)
    ?term.processFormat(Format())
    term.cursorNextLine()
  )
  if pager.term.flush().isErr:
    return ok(false)
  case res
  of irEOF: return ok(false)
  of irOk: return ok(true)
  of irException: return err()

# public
proc redraw(pager: Pager) {.jsfunc.} =
  pager.term.clearCanvas()
  for surface in pager.surfaces.mitems:
    surface.redraw = true
  if pager.bufferIface != nil:
    pager.bufferIface.queueDraw()
  if pager.menu != nil:
    pager.menu.redraw = true
  if pager.lineEdit != nil:
    pager.lineEdit.redraw = true

# private
proc getTempFile(pager: Pager; ext = ""): string {.jsfunc.} =
  result = $pager.config.external.tmpdir / "chaptmp" &
    $pager.loader.clientPid & "-" & $pager.tmpfSeq
  if ext != "":
    result &= "."
    result &= ext
  inc pager.tmpfSeq

proc loadCachedImage(pager: Pager; iface: BufferInterface; bmp: NetworkBitmap;
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
      iface.process):
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
      iface.queueDraw()
      cachedImage.data = blob
      cachedImage.state = cisLoaded
      cachedImage.cacheId = cacheId
      cachedImage.transparent =
        response.headers.getFirst("Cha-Image-Sixel-Transparent") == "1"
      let plens = response.headers.getFirst("Cha-Image-Sixel-Prelude-Len")
      cachedImage.preludeLen = parseIntP(plens).get(0)
    )
  )
  iface.addCachedImage(cachedImage)

proc initImages(pager: Pager; iface: BufferInterface) =
  let term = pager.term
  let bufWidth = pager.bufWidth
  let bufHeight = pager.bufHeight
  let maxwpx = bufWidth * pager.attrs.ppc
  let maxhpx = bufHeight * pager.attrs.ppl
  let imageMode = term.imageMode
  let pid = iface.process
  for image in iface.images:
    let dims = term.positionImage(image.x, image.y, image.x - iface.fromx,
      image.y - iface.fromy, image.offx, image.offy, image.width,
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
    let cached = iface.findCachedImage(imageId, width, height, cachedOffx,
      cachedErry, cachedDispw)
    if cached == nil:
      pager.loadCachedImage(iface, image.bmp, width, height, cachedOffx,
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
    let cached = iface.findCachedImage(canvasImage.bmp.imageId,
      width, height, cachedOffx, cachedErry, cachedDispw)
    if cached == nil:
      pager.loadCachedImage(iface, canvasImage.bmp, width, height,
        cachedOffx, cachedErry, cachedDispw)
      canvasImage.damaged = false
    elif cached.state != cisLoaded:
      canvasImage.damaged = false
    else:
      canvasImage.updateImage(cached.data, cached.preludeLen)

proc getAbsoluteCursorXY(pager: Pager; iface: BufferInterface): PagePos =
  var cursorx = 0
  var cursory = 0
  if pager.askPrompt != "":
    return (pager.askCursor, pager.attrs.height - 1)
  elif pager.lineEdit != nil:
    return (pager.lineEdit.getCursorX(), pager.attrs.height - 1)
  elif (let menu = pager.menu; menu != nil):
    return (menu.getCursorX(), menu.getCursorY())
  elif iface != nil:
    if pager.alertState == pasNormal:
      #TODO this really doesn't belong in draw...
      iface.clearHover()
    cursorx = iface.acursorx
    cursory = iface.acursory
  return (cursorx, cursory)

proc highlightColor(pager: Pager): CellColor =
  if pager.attrs.colorMode != cmMonochrome:
    return pager.config.display.highlightColor.cellColor()
  return defaultColor

proc needsRedraw(pager: Pager; iface: BufferInterface): bool =
  return pager.display.redraw or pager.status.redraw or
    pager.menu != nil and pager.menu.redraw or
    pager.lineEdit != nil and pager.lineEdit.redraw or
    iface != nil and iface.redraw

proc draw(pager: Pager): bool =
  let term = pager.term
  let iface = pager.bufferIface
  let redraw = pager.needsRedraw(iface)
  if redraw:
    # Note: lack of redraw does not necessarily mean that we send nothing to
    # the terminal, but that we at most only send a few cursor movement
    # controls.
    term.initFrame()
  var imageRedraw = false
  var hasMenu = false
  let bufHeight = pager.bufHeight
  if iface != nil:
    if iface.redraw:
      let hlcolor = pager.highlightColor
      iface.drawLines(pager.display.grid, hlcolor)
      if pager.config.display.highlightMarks:
        iface.highlightMarks(pager.display.grid, hlcolor)
      iface.redraw = false
      pager.display.redraw = true
      imageRedraw = true
      let diff = pager.term.updateScroll(iface.process, iface.fromx, iface.fromy)
      if diff != 0 and abs(diff) <= (bufHeight + 1) div 2:
        if diff > 0:
          pager.term.scrollDown(diff, bufHeight)
        else:
          pager.term.scrollUp(-diff, bufHeight)
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
  if pager.lineEdit != nil:
    if pager.lineEdit.redraw:
      let x = pager.lineEdit.generateOutput()
      pager.term.writeGrid(x, 0, pager.attrs.height - 1)
      pager.lineEdit.redraw = false
  else:
    if pager.status.redraw:
      pager.term.writeGrid(pager.status.grid, 0, pager.attrs.height - 1)
      pager.status.redraw = false
  if pager.term.imageMode != imNone:
    if imageRedraw:
      # init images only after term canvas has been finalized
      pager.initImages(iface)
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
  let (cursorx, cursory) = pager.getAbsoluteCursorXY(iface)
  let mouse = pager.lineEdit == nil
  let bgcolor = if iface != nil: iface.bgcolor else: defaultColor
  pager.term.draw(redraw, mouse, cursorx, cursory, bufHeight, bgcolor).isOk

proc writeAskPrompt(pager: Pager; s = "") =
  let maxwidth = pager.status.grid.width - s.width()
  let i = pager.status.writeStatusMessage(pager.askPrompt, maxwidth = maxwidth)
  pager.askCursor = pager.status.writeStatusMessage(s, start = i)

# public
proc askChar(ctx: JSContext; pager: Pager; prompt: string): JSValue {.jsfunc.} =
  if prompt == "":
    return JS_ThrowTypeError(ctx, "prompt may not be empty")
  var funs {.noinit.}: array[2, JSValue]
  let res = JS_NewPromiseCapability(ctx, funs.toJSValueArray())
  if JS_IsException(res):
    return JS_EXCEPTION
  JS_FreeValue(ctx, funs[1])
  pager.askPrompt = prompt
  pager.writeAskPrompt()
  pager.jsmap.askPromise = funs[0]
  return res

proc fitAskPrompt(pager: Pager; prompt0: string): string {.jsfunc.} =
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
  move(prompt)

# private
proc fulfillAsk(ctx: JSContext; pager: Pager): JSValue {.jsfunc.} =
  if not JS_IsUndefined(pager.jsmap.askPromise):
    let inputBuffer = move(pager.inputBuffer)
    let text = ctx.toJS(inputBuffer)
    if JS_IsException(text):
      return text
    let fun = pager.jsmap.askPromise
    pager.jsmap.askPromise = JS_UNDEFINED
    pager.askPrompt = ""
    let res = ctx.callSinkFree(fun, JS_UNDEFINED, text)
    if JS_IsException(res):
      return res
    JS_FreeValue(ctx, res)
    return JS_TRUE
  return JS_FALSE

# private
proc copyLoadInfo(pager: Pager; init: BufferInit) {.jsfunc.} =
  if pager.bufferInit == init and init.loadInfo != "" and
      pager.alertState != pasAlertOn and pager.askPrompt == "":
    discard pager.status.writeStatusMessage(init.loadInfo)
    pager.alertState = pasLoadInfo
    pager.updateStatus = ussSkip

proc initBuffer(pager: Pager; bufferConfig: BufferConfig;
    loaderConfig: LoaderClientConfig; request: Request; url: URL; title = "";
    redirectDepth = 0; flags: set[BufferInitFlag] = {}; contentType = "";
    filterCmd = ""; charsetStack: seq[Charset] = @[]): BufferInit =
  let stream = pager.loader.startRequest(request, loaderConfig)
  if stream == nil:
    pager.alert("failed to start request for " & $request.url)
    return nil
  pager.loader.pollData.register(stream.fd, POLLIN)
  let init = newBufferInit(bufferConfig, loaderConfig, url, request,
    pager.attrs, title, redirectDepth, flags, contentType, filterCmd,
    charsetStack)
  pager.loader.put(ConnectingBuffer(
    state: bcsBeforeResult,
    init: init,
    stream: stream
  ))
  return init

# private
proc initBufferFrom(pager: Pager; init: BufferInit;
    contentType, filterCmd: string): BufferInit {.jsfunc.} =
  return pager.initBuffer(
    init.config,
    init.loaderConfig,
    newRequest("cache:" & $init.cacheId),
    init.url,
    contentType = contentType,
    charsetStack = init.charsetStack,
    filterCmd = filterCmd
  )

proc bufferPackets(opaque: RootRef; stream: PosixStream) =
  let loader = FileLoader(opaque)
  loader.pollData.unregister(stream.fd)
  loader.pollData.register(stream.fd, POLLIN or POLLOUT)

proc addInterface(pager: Pager; init: BufferInit; stream: SocketStream;
    phandle: ProcessHandle): BufferInterface =
  stream.setBlocking(false)
  let iface = newBufferInterface(stream, bufferPackets, pager.loader, phandle,
    addr pager.attrs, init)
  pager.loader.register(iface, POLLIN)
  return iface

# private
proc clone(pager: Pager; iface: BufferInterface; init: BufferInit; url: URL):
    BufferInterface {.jsfunc.} =
  var sv {.noinit.}: array[2, cint]
  if socketpair(AF_UNIX, SOCK_STREAM, IPPROTO_IP, sv) != 0:
    return nil
  let res = iface.clone(url, sv[1])
  if res.isErr:
    return nil
  let fd = sv[0]
  let stream = newSocketStream(fd)
  # add a reference to parent's cached source; it will be removed when the
  # buffer is deleted
  let loader = pager.loader
  discard loader.shareCachedItem(init.cacheId, loader.clientPid)
  let iface2 = pager.addInterface(init, stream, iface.phandle)
  # I need numLines so that setCursorY works immediately
  iface2.numLines = iface.numLines
  iface2.requestLinesFast(force = true)
  return iface2

# public
proc alert(pager: Pager; msg: string) {.jsfunc.} =
  if msg != "":
    pager.alerts.add(msg)
    pager.updateStatus = ussUpdate

# public
proc peekCursor(pager: Pager) {.jsfunc.} =
  if pager.bufferIface != nil:
    pager.alert(pager.bufferIface.getPeekCursorStr())

# private
proc unregisterBufferIface(pager: Pager; iface: BufferInterface) {.jsfunc.} =
  if iface.dead:
    return # already unregistered
  pager.loader.removeCachedItem(iface.init.cacheId)
  if bifCrashed notin iface.init.flags:
    dec iface.phandle.refc
    if iface.phandle.refc == 0:
      pager.loader.removeClient(iface.process)
  let stream = iface.stream
  let fd = stream.fd
  pager.loader.unregister(fd)
  pager.loader.unset(fd)
  stream.sclose()
  iface.dead = true

proc findBufferInit(pager: Pager; init: BufferInit): ConnectingBuffer =
  #TODO eliminate this search
  for item in pager.loader.data:
    if item of ConnectingBuffer:
      let item = ConnectingBuffer(item)
      if item.init == init:
        return item
  return nil

# private
proc unregisterBufferInit(pager: Pager; init: BufferInit) {.jsfunc.} =
  let item = pager.findBufferInit(init)
  if item != nil:
    # connecting to URL
    let stream = item.stream
    pager.loader.unregister(item)
    stream.sclose()

template myExec(cmd: string) =
  discard execl("/bin/sh", "sh", "-c", cstring(cmd), nil)
  exitnow(127)

type EnvVar = tuple[name, value: string]

proc defaultEnv(pager: Pager): seq[EnvVar] =
  let init = pager.bufferInit
  if init != nil:
    return @[("CHA_URL", $init.url), ("CHA_CHARSET", $init.charset)]
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
  act.sa_handler = posix.SIG_IGN
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
    act.sa_handler = posix.SIG_DFL
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
    pager.redraw()
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

# private
proc getCacheFile(pager: Pager; cacheId: int; pid = -1): string {.jsfunc.} =
  let pid = if pid == -1: pager.loader.clientPid else: pid
  return pager.loader.getCacheFile(cacheId, pid)

# private
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

proc windowChange(pager: Pager): Opt[void] =
  # maybe we didn't change dimensions, just color mode
  let dimChange = pager.attrs.width != pager.term.attrs.width or
    pager.attrs.height != pager.term.attrs.height or
    pager.attrs.ppc != pager.term.attrs.ppc or
    pager.attrs.ppl != pager.term.attrs.ppl
  pager.attrs = pager.term.attrs
  if dimChange:
    pager.term.unsetScroll()
    if pager.lineEdit != nil:
      pager.lineEdit.windowChange(pager.attrs)
    for st in SurfaceType:
      pager.clear(st)
    if pager.menu != nil:
      pager.menu.windowChange(pager.bufWidth, pager.bufHeight)
    if pager.askPrompt != "":
      pager.writeAskPrompt()
    pager.queueStatusUpdate()
  let ctx = pager.jsctx
  let arg0 = ctx.toJS(ietWindowChange)
  if JS_IsException(arg0):
    return err()
  let res = ctx.callSink(pager.jsmap.handleInput, pager.jsmap.pager, arg0)
  if JS_IsException(res):
    return err()
  JS_FreeValue(ctx, res)
  ok()

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
    referrer: BufferInit; cookie: Option[CookieMode];
    loaderConfig: var LoaderClientConfig; bufferConfig: var BufferConfig;
    filterCmd: var string) =
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

proc gotoURL0(pager: Pager; request: Request; save, history: bool;
    bufferConfig: BufferConfig; loaderConfig: LoaderClientConfig;
    title, contentType: string; redirectDepth: int; url: URL;
    filterCmd: string): BufferInit =
  var flags: set[BufferInitFlag] = {}
  if save:
    flags.incl(bifSave)
  if history and bufferConfig.history:
    flags.incl(bifHistory)
  let init = pager.initBuffer(bufferConfig, loaderConfig, request,
    if url != nil: url else: request.url, title, redirectDepth, flags,
    contentType, filterCmd)
  if init == nil:
    return nil
  inc pager.numload
  return init

# private
proc omniRewrite(ctx: JSContext; pager: Pager; arg0: JSValueConst): JSValue
    {.jsfunc.} =
  var s: string
  ?ctx.fromJS(arg0, s)
  for rule in pager.config.omnirule:
    if rule.match.match(s):
      pager.lineHist[lmLocation].add(s)
      return ctx.call(rule.substituteUrl, JS_UNDEFINED, arg0)
  return JS_DupValue(ctx, arg0)

proc createPipe(pager: Pager): (PosixStream, PosixStream) =
  var pipefds {.noinit.}: array[2, cint]
  if pipe(pipefds) == -1:
    pager.alert("Failed to create pipe")
    return (nil, nil)
  return (newPosixStream(pipefds[0]), newPosixStream(pipefds[1]))

# private
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

# private
proc showConsole(pager: Pager) =
  let ctx = pager.jsctx
  let res = ctx.call(pager.jsmap.showConsole, pager.jsmap.pager)
  if JS_IsException(res):
    pager.console.writeException(ctx)
  JS_FreeValue(ctx, res)

proc addConsole0(pager: Pager; close: bool): bool =
  let oldCacheId = pager.consoleCacheId
  if f := pager.addConsoleFile():
    if oldCacheId != -1:
      pager.loader.removeCachedItem(oldCacheId)
    pager.console.setStream(f, close)
    return true
  return false

# private
proc addConsole(pager: Pager): bool {.jsfunc.} =
  pager.addConsole0(close = true)

proc addConsole2(pager: Pager; interactive: bool) =
  if interactive and pager.config.start.consoleBuffer:
    if pager.addConsole0(close = false):
      pager.console.log("Type (M-c) console.hide() to return to buffer mode.")
      pager.console.flush()
      return
    pager.alert("Failed to open temp file for console")

# private
proc saveTo(pager: Pager; init: BufferInit; path: string): bool
    {.jsfunc.} =
  if pager.loader.redirectToFile(init.istreamOutputId, path, init.url):
    pager.alert("Saving file to " & path)
    pager.loader.resume(init.istreamOutputId)
    init.closeMailcap()
    return true
  return false

# Go to specific URL (for JS)
type GotoURLDict = object of JSDict
  contentType {.jsdefault.}: Option[string]
  save {.jsdefault.}: bool
  history {.jsdefault: true.}: bool
  scripting {.jsdefault.}: Option[ScriptingMode]
  cookie {.jsdefault.}: Option[CookieMode]
  charset {.jsdefault.}: Option[Charset]
  url {.jsdefault.}: Option[URL]
  referrer {.jsdefault.}: Option[BufferInit]
  redirectDepth {.jsdefault.}: int
  title {.jsdefault.}: string

# public
proc gotoURLImpl(ctx: JSContext; pager: Pager; v: JSValueConst;
    t = GotoURLDict()): Opt[BufferInit] {.jsfunc.} =
  var request: Request = nil
  var jsRequest: JSRequest = nil
  if ctx.fromJS(v, jsRequest).isOk:
    request = jsRequest.request
  else:
    var url: URL
    if ctx.fromJS(v, url).isErr:
      var s: string
      ?ctx.fromJS(v, s)
      url = ?ctx.newURL(s)
    request = newRequest(url)
  var loaderConfig: LoaderClientConfig
  var bufferConfig: BufferConfig
  var filterCmd: string
  pager.initGotoURL(request, t.charset.get(CHARSET_UNKNOWN),
    t.referrer.get(nil), t.cookie, loaderConfig, bufferConfig, filterCmd)
  bufferConfig.scripting = t.scripting.get(bufferConfig.scripting)
  let init = pager.gotoURL0(request, t.save, t.history, bufferConfig,
    loaderConfig, t.title, t.contentType.get(""), t.redirectDepth,
    t.url.get(nil), filterCmd)
  ok(init)

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
# public
proc extern(ctx: JSContext; pager: Pager; cmd: string;
    t = ExternDict(env: JS_UNDEFINED, suspend: true)): Opt[bool] {.jsfunc.} =
  var env = newSeq[EnvVar]()
  ?ctx.readEnvSeq(pager, t.env, env)
  ok(pager.runCommand(cmd, t.suspend, t.wait, env).isOk)

# public
proc externCapture(ctx: JSContext; pager: Pager; cmd: string): JSValue
    {.jsfunc.} =
  pager.setEnvVars(pager.defaultEnv())
  var s: string
  if runProcessCapture(cmd, s):
    return ctx.toJS(s)
  return JS_NULL

# public
proc externInto(pager: Pager; cmd, ins: string): bool {.jsfunc.} =
  pager.setEnvVars(pager.defaultEnv())
  return runProcessInto(cmd, ins)

# private
proc jsQuit(ctx: JSContext; pager: Pager; code = 0): JSValue {.
    jsfunc: "quit".} =
  pager.exitCode = int(code)
  JS_ThrowInternalError(ctx, "interrupted")
  JS_SetUncatchableException(ctx, true)
  return JS_EXCEPTION

# private
proc suspend(ctx: JSContext; pager: Pager): JSValue {.jsfunc.} =
  if pager.term.quit().isErr:
    return ctx.jsQuit(pager, 1)
  discard kill(0, cint(SIGTSTP))
  discard pager.term.restart() #TODO
  return JS_UNDEFINED

# public
proc clipboardWrite(ctx: JSContext; pager: Pager; s: string; clipboard = true):
    JSValue {.jsfunc.} =
  if res := pager.term.sendOSC52(s, clipboard):
    if res:
      return JS_TRUE
    if not clipboard:
      return JS_FALSE
    return ctx.toJS(pager.externInto(pager.config.external.copyCmd, s))
  return ctx.jsQuit(pager, 1)

# Execute cmd, with ps moved onto stdin, os onto stdout, and the browser
# console onto stderr.
# ps remains open, but os is consumed.
proc execPipe(pager: Pager; cmd: string; ps, os: PosixStream): int =
  var oldint, oldquit: Sigaction
  var act = Sigaction(sa_handler: posix.SIG_IGN, sa_flags: SA_RESTART)
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
    act.sa_handler = posix.SIG_DFL
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

proc execPipeSink(pager: Pager; cmd: string; istream: PosixStream):
    PosixStream =
  let (pins, pouts) = pager.createPipe()
  if pins == nil:
    return nil
  pins.setCloseOnExec()
  let pid = pager.execPipe(cmd, istream, pouts)
  istream.sclose()
  if pid == -1:
    return nil
  return pins

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
  return pager.execPipeSink(cmd, istream)

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
        break needsConnect
      pins = pins2
    twtstr.unsetEnv("MAILCAP_URL")
    let url = parseURL0("stream:" & $pid)
    pager.loader.passFd(url.pathname, pins.fd)
    let response = pager.loader.doRequest(newRequest(url))
    var flags = {cmfConnect, cmfRedirected}
    if mfNeedsstyle in entry.flags or isansi:
      # ansi always needs styles
      #TODO ideally, x-ansioutput should also switch the content type so
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
  return MailcapResult(flags: {})

# private
proc addHist(pager: Pager; mode: LineMode; s: string) {.jsfunc.} =
  pager.getHist(mode).add(s)

proc fail(pager: Pager; init: BufferInit; errorMessage: string): Opt[void] =
  dec pager.numload
  let ctx = pager.jsctx
  var msg = ctx.toJS(errorMessage)
  if JS_IsException(msg): # OOM
    msg = JS_UNDEFINED
  let res = ctx.connected(init, bcrFail, msg)
  if JS_IsException(res):
    return err()
  JS_FreeValue(ctx, res)
  ok()

proc applyMailcap(pager: Pager; init: BufferInit; entry: MailcapEntry) =
  let res = pager.runMailcap(init.url, init.ostream, init.istreamOutputId,
    init.contentType, entry)
  if cmfSaveoutput in res.flags:
    init.flags.incl(bifSave)
  init.ostream = res.ostream
  init.ostreamOutputId = res.ostreamOutputId
  if cmfConnect notin res.flags:
    init.flags.incl(bifMailcapCancel)
  if cmfHTML in res.flags:
    init.flags.incl(bifHTML)
  else:
    init.flags.excl(bifHTML)
  if cmfNeedsstyle in res.flags: # override
    init.config.styling = true
  if cmfNeedsimage in res.flags: # override
    init.config.images = true
  if cmfRedirected in res.flags:
    init.flags.incl(bifRedirected)

# private
proc applyMailcap(ctx: JSContext; pager: Pager; init: BufferInit;
    val: JSValueConst): Opt[void] {.jsfunc.} =
  if JS_IsNumber(val):
    var i: int
    ?ctx.fromJS(val, i)
    if i < 0 or i >= pager.mailcap.len:
      JS_ThrowRangeError(ctx, "invalid mailcap entry")
      return err()
    pager.applyMailcap(init, pager.mailcap[i])
  else:
    var s: string
    ?ctx.fromJS(val, s)
    var mailcap: Mailcap
    let res = mailcap.parseMailcap(s, "<input>")
    if res.isOk and mailcap.len == 1:
      pager.applyMailcap(init, mailcap[0])
    elif res.isErr:
      JS_ThrowTypeError(ctx, "%s", cstring(res.error))
      return err()
    else:
      JS_ThrowTypeError(ctx, "one mailcap entry expected")
      return err()
  ok()

# private
proc connected2(pager: Pager; init: BufferInit): Opt[void] {.jsfunc.} =
  let loader = pager.loader
  let ctx = pager.jsctx
  var arg0 = JS_UNDEFINED
  let cres = if bifSave in init.flags:
    dec pager.numload
    # resume the ostream
    loader.resume(init.ostreamOutputId)
    bcrSave
  elif bifMailcapCancel in init.flags:
    dec pager.numload
    bcrCancel
  else:
    # buffer now actually exists; create a process for it
    var attrs = pager.attrs
    # subtract status line height
    attrs.height -= 1
    attrs.heightPx -= attrs.ppl
    var url = init.url
    if url.username != "" or url.password != "":
      url = newURL(url)
      url.username = ""
      url.password = ""
    let (pid, stream) = pager.forkserver.forkBuffer(
      init.config,
      url,
      attrs,
      bifHTML in init.flags,
      init.charsetStack,
      init.contentType.untilLower(';')
    )
    let ostream = init.ostream
    if pid == -1:
      ostream.sclose()
      return pager.fail(init, "error forking new process for buffer")
    let istreamOutputId = init.istreamOutputId
    let redirected = bifRedirected in init.flags
    let cstream = loader.addClient(pid, init.loaderConfig)
    if cstream == nil:
      stream.sclose()
      ostream.sclose()
      return pager.fail(init, "failed to create new loader client")
    if init.cacheId == -1:
      init.cacheId = loader.addCacheFile(istreamOutputId)
    if init.request.url.schemeType == stCache:
      # loading from cache; now both the buffer and us hold a new reference
      # to the cached item, but it's only shared with the buffer. add a
      # pager ref too.
      discard loader.shareCachedItem(init.cacheId, loader.clientPid)
    var outCacheId = init.cacheId
    if not redirected:
      discard loader.shareCachedItem(init.cacheId, pid)
      loader.resume(istreamOutputId)
    else:
      outCacheId = loader.addCacheFile(init.ostreamOutputId)
      discard loader.shareCachedItem(outCacheId, pid)
      loader.removeCachedItem(outCacheId)
      loader.resume([istreamOutputId, init.ostreamOutputId])
    stream.withPacketWriterFire w: # if EOF, poll will notify us later
      w.swrite(outCacheId)
      w.sendFd(cstream.fd)
      # pass down ostream
      w.sendFd(ostream.fd)
    let iface = pager.addInterface(init, stream, newProcessHandle(pid))
    arg0 = ctx.toJS(iface)
    bcrConnected
  let res = ctx.connected(init, cres, arg0)
  if JS_IsException(res):
    return err()
  JS_FreeValue(ctx, res)
  ok()

proc saveEntry(pager: Pager; entry: MailcapEntry) =
  let path = $pager.config.external.autoMailcap
  if pager.autoMailcap.saveEntry(path, entry).isErr:
    pager.alert("Could not write to " & $path)

# private
proc saveMailcapEntry(ctx: JSContext; pager: Pager; i: int): Opt[void]
    {.jsfunc.} =
  if i < 0 or i >= pager.mailcap.len:
    JS_ThrowRangeError(ctx, "invalid mailcap entry")
    return err()
  pager.saveEntry(pager.mailcap[i])
  ok()

# private
proc addMailcapEntry(pager: Pager; init: BufferInit; cmd: string;
    flag: MailcapFlag) {.jsfunc.} =
  pager.saveEntry(MailcapEntry(
    t: init.contentType.untilLower(';'),
    cmd: cmd,
    flags: {flag}
  ))

# private
proc findMailcapPrevNext(pager: Pager; init: BufferInit; i: int):
    tuple[prev, next: int] {.jsfunc.} =
  let prev = pager.mailcap.findPrevMailcapEntry(init.contentType, "",
    init.url, i)
  let next = pager.mailcap.findMailcapEntry(init.contentType, "",
    init.url, i)
  return (prev, next)

# private
proc askMailcap(ctx: JSContext; pager: Pager; init: BufferInit;
    i, sx, prev, next: int): JSValue {.jsfunc.} =
  var sx = sx
  let shortContentType = init.contentType.untilLower(';')
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
  return ctx.askChar(pager, msg.substr(j))

proc connected(pager: Pager; init: BufferInit; response: Response): Opt[void] =
  # This forces client to ask for confirmation before quitting.
  pager.hasload = true
  if bifHistory in init.flags:
    pager.lineHist[lmLocation].add($init.url)
  # contentType must have been set by applyResponse.
  let shortContentType = init.contentType.untilLower(';')
  var contentType = init.contentType
  if shortContentType.startsWithIgnoreCase("text/"):
    # prepare content type for %{charset}
    contentType.setContentTypeAttr("charset", $init.charset)
  var istream = response.body
  if init.filterCmd != "":
    pager.setEnvVars(pager.defaultEnv())
    istream = pager.execPipeSink(init.filterCmd, istream)
    if istream == nil:
      return pager.fail(init, "failed to filter buffer")
  init.istreamOutputId = response.outputId
  init.ostream = istream
  if shortContentType.equalsIgnoreCase("text/html"):
    init.flags.incl(bifHTML)
    return pager.connected2(init)
  if shortContentType.equalsIgnoreCase("text/plain") or bifSave in init.flags:
    return pager.connected2(init)
  let i = pager.autoMailcap.findMailcapEntry(contentType, "", init.url)
  if i != -1 or pager.config.start.headless != hmFalse:
    pager.applyMailcap(init, pager.autoMailcap[i])
    return pager.connected2(init)
  else:
    let i = pager.mailcap.findMailcapEntry(contentType, "", init.url)
    if i < 0 and shortContentType.isTextType():
      return pager.connected2(init)
    let ctx = pager.jsctx
    let arg0 = ctx.toJS(i)
    if JS_IsException(arg0):
      return err()
    let res = ctx.connected(init, bcrMailcap, arg0)
    if JS_IsException(res):
      return err()
    JS_FreeValue(ctx, res)
    return ok()

proc handleRead(pager: Pager; item: ConnectingBuffer): Opt[void] =
  let init = item.init
  let stream = item.stream
  case item.state
  of bcsBeforeResult:
    var res = int(ceLoaderGone)
    var msg: string
    stream.withPacketReaderFire r:
      r.sread(res)
      if res == 0: # continue
        r.sread(item.outputId)
        inc item.state
        let host = init.url.host
        if host == "":
          init.loadInfo = "Loading " & $init.url
        else:
          init.loadInfo = "Connected to " & host & ". Downloading..."
        pager.copyLoadInfo(init)
      else:
        r.sread(msg)
    if res != 0: # done
      if msg == "":
        msg = getLoaderErrorMessage(res)
      return pager.fail(init, msg)
  of bcsBeforeStatus:
    let response = newResponse(item.res, init.request, stream, item.outputId)
    stream.withPacketReaderFire r:
      r.sread(response.status)
      r.sread(response.headers)
    # done
    pager.loader.unregister(item)
    init.applyResponse(response, pager.mimeTypes.t)
    let redirect = response.getRedirect(init.request)
    let ctx = pager.jsctx
    var arg0 = JS_UNDEFINED
    let cres = if redirect != nil:
      arg0 = ctx.toJS(redirect.toPagerJSRequest())
      bcrRedirect
    elif response.status == 401:
      bcrUnauthorized
    else:
      return pager.connected(init, response)
    stream.sclose()
    let res = ctx.connected(init, cres, arg0)
    if JS_IsException(res):
      return err()
    JS_FreeValue(ctx, res)
  ok()

# private
proc setMenu(ctx: JSContext; pager: Pager; val: JSValueConst): Opt[void] {.
    jsfset: "menu".} =
  if JS_IsNull(val):
    pager.menu = nil
  else:
    ?ctx.fromJS(val, pager.menu)
  ok()

# private
proc handleStderr(pager: Pager) {.jsfunc.} =
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

proc handleRead(pager: Pager; fd: cint): Opt[bool] =
  if pager.term.istream != nil and fd == pager.term.istream.fd:
    if pager.handleUserInput().isErr:
      return ok(false)
  elif fd == pager.forkserver.estream.fd:
    pager.handleStderr()
  elif fd in pager.loader.unregistered:
    discard # ignore (see handleError)
  elif (let data = pager.loader.get(fd); data != nil):
    if data of ConnectingBuffer:
      ?pager.handleRead(ConnectingBuffer(data))
    elif data of BufferInterface:
      let iface = BufferInterface(data)
      let ctx = pager.jsctx
      case ctx.handleCommand(iface)
      of irOk:
        if pager.bufferIface == iface and iface.refreshStatus:
          pager.showAlerts()
        iface.refreshStatus = false
      of irException: pager.console.writeException(ctx)
      of irEOF: discard
    else:
      pager.loader.onRead(fd)
      if data of ConnectData:
        ?pager.runJSJobs()
  else:
    assert false
  ok(true)

proc handleWrite(pager: Pager; fd: cint): bool =
  if pager.term.ostream != nil and pager.term.ostream.fd == fd:
    let res = pager.term.flush()
    if res.isErr:
      return false
    if res.get:
      pager.loader.pollData.unregister(pager.term.ostream.fd)
      pager.term.registeredFlag = false
  elif fd in pager.loader.unregistered:
    discard # ignore (see handleError)
  else:
    let iface = BufferInterface(pager.loader.get(fd))
    # this might just do an unregister/register/unregister/register sequence,
    # but with poll this is basically free so it's fine
    pager.loader.pollData.unregister(fd)
    pager.loader.pollData.register(fd, POLLIN)
    # if flushWrite errors out, then poll will notify us anyway
    discard iface.flushWrite()
  true

proc handleError(pager: Pager; fd: cint): Opt[bool] =
  if pager.term.istream != nil and fd == pager.term.istream.fd:
    pager.alert("error in tty")
    return ok(false)
  elif fd == pager.forkserver.estream.fd:
    pager.alert("fork server crashed")
    return ok(false)
  elif fd in pager.loader.unregistered:
    # this fd is already unregistered in this cycle.
    # it is possible that another handle has taken the same fd number, in
    # that case we must suppress the error in this cycle and wait for the
    # next one.
    discard
  elif (let data = pager.loader.get(fd); data != nil):
    if data of ConnectingBuffer:
      let item = ConnectingBuffer(data)
      ?pager.fail(item.init, "loader died while loading")
    elif data of BufferInterface:
      let iface = BufferInterface(data)
      let isConsole = iface.init == pager.consoleInit
      if isConsole:
        pager.dumpConsoleFile = true
      iface.init.flags.incl(bifCrashed)
      pager.unregisterBufferIface(iface)
      pager.console.error("Error in buffer", $iface.init.url)
      pager.console.flush()
      if not isConsole:
        pager.showConsole()
      dec pager.numload
    else:
      discard pager.loader.onError(fd) #TODO handle connection error?
  else:
    pager.showConsole()
  ok(true)

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

# private
proc inputLoop(pager: Pager): Opt[void] {.jsfunc.} =
  pager.loader.pollData.register(pager.term.istream.fd, POLLIN)
  let signals = pager.setupSignals()
  pager.loader.pollData.register(signals.fd, POLLIN)
  while true:
    let timeout = pager.timeouts.sortAndGetTimeout()
    pager.loader.pollData.poll(timeout)
    pager.loader.blockRegister()
    for event in pager.loader.pollData.events:
      let efd = event.fd
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
            if pager.term.queryWindowSize().isErr:
              return ok()
            ?pager.windowChange()
        elif not ?pager.handleRead(efd):
          return ok()
      if (event.revents and POLLOUT) != 0:
        if not pager.handleWrite(efd):
          return ok()
      if (event.revents and POLLERR) != 0 or (event.revents and POLLHUP) != 0:
        if not ?pager.handleError(efd):
          return ok()
    if pager.timeouts.run(pager.console):
      if pager.consoleInit != nil:
        pager.consoleInit.flags.incl(bifTailOnLoad)
    pager.loader.unblockRegister()
    pager.loader.unregistered.setLen(0)
    ?pager.runJSJobs()
    if pager.bufferInit == nil and pager.lineEdit == nil:
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
      return ok()
    case pager.updateStatus
    of ussNone, ussSkip: discard
    of ussUpdate: pager.refreshStatusMsg()
    pager.updateStatus = ussNone
    if not pager.draw():
      return ok()
  ok()

proc hasSelectFds(pager: Pager): bool =
  return not pager.timeouts.empty or pager.numload > 0 or
    pager.loader.hasFds()

# private
proc headlessLoop(pager: Pager): Opt[void] {.jsfunc.} =
  while pager.hasSelectFds():
    let timeout = pager.timeouts.sortAndGetTimeout()
    pager.loader.pollData.poll(timeout)
    pager.loader.blockRegister()
    for event in pager.loader.pollData.events:
      let efd = event.fd
      if (event.revents and POLLIN) != 0:
        if not ?pager.handleRead(efd):
          return ok()
      if (event.revents and POLLOUT) != 0:
        if not pager.handleWrite(efd):
          return ok()
      if (event.revents and POLLERR) != 0 or (event.revents and POLLHUP) != 0:
        if not ?pager.handleError(efd):
          return ok()
    pager.loader.unblockRegister()
    pager.loader.unregistered.setLen(0)
    discard pager.timeouts.run(pager.console)
    ?pager.runJSJobs()
  ok()

# List of properties that are defined on both Buffer and as reflectors
# on Pager.
# It's a horrible setup that should not be extended anymore, instead users
# should just use `pager.buffer'.
const LegacyReflectFuncList = [
  cstring"cursorUp", "cursorDown", "cursorLeft", "cursorRight",
  "cursorLineBegin", "cursorLineEnd", "cursorLineTextStart", "cursorNextWord",
  "cursorNextViWord", "cursorNextBigWord", "cursorPrevWord", "cursorPrevViWord",
  "cursorPrevBigWord", "cursorWordEnd", "cursorViWordEnd", "cursorBigWordEnd",
  "cursorWordBegin", "cursorViWordBegin", "cursorBigWordBegin",
  "getCurrentWord", "cursorNextLink", "cursorPrevLink", "cursorLinkNavDown",
  "cursorLinkNavUp", "cursorNextParagraph", "cursorPrevParagraph",
  "cursorNthLink", "cursorRevNthLink", "pageUp", "pageDown", "pageLeft",
  "pageRight", "halfPageUp", "halfPageDown", "halfPageLeft", "halfPageRight",
  "scrollUp", "scrollDown", "scrollLeft", "scrollRight", "click",
  "cursorFirstLine", "cursorLastLine", "cursorTop", "cursorMiddle",
  "cursorBottom", "lowerPage", "lowerPageBegin", "centerLine",
  "centerLineBegin", "raisePage", "raisePageBegin", "nextPageBegin",
  "cursorLeftEdge", "cursorMiddleColumn", "cursorRightEdge", "centerColumn",
  "findNextMark", "setMark", "clearMark", "gotoMark", "gotoMarkY", "getMarkPos",
  "cursorToggleSelection", "getSelectionText", "markURL", "showLinkHints",
  "toggleImages", "saveLink", "saveSource", "setCursorX", "setCursorY",
  "setCursorXY", "setCursorXCenter", "setCursorYCenter", "setCursorXYCenter",
  "setFromX", "setFromY", "setFromXY", "find", "cancel", "reshape"
]
const LegacyReflectGetList = [
  cstring"url", "hoverTitle", "hoverLink", "hoverImage", "cursorx", "cursory",
  "fromx", "fromy", "numLines", "width", "height", "process", "title",
  "next", "prev", "select"
]

proc legacyReflectFunction(ctx: JSContext; this: JSValueConst; argc: cint;
    argv: JSValueConstArray; magic: cint): JSValue {.cdecl.} =
  var pager: Pager
  if ctx.fromJS(this, pager).isErr:
    return JS_EXCEPTION
  let cval = if pager.menu != nil:
    ctx.toJS(pager.menu)
  else:
    JS_GetProperty(ctx, this, pager.bufferAtom)
  if JS_IsException(cval):
    return cval
  let val = JS_GetPropertyStr(ctx, cval, LegacyReflectFuncList[magic])
  if JS_IsException(val):
    JS_FreeValue(ctx, cval)
    return JS_EXCEPTION
  let res = JS_Call(ctx, val, cval, argc, argv)
  ctx.freeValues(val, cval)
  return res

proc legacyReflectGetter(ctx: JSContext; this: JSValueConst; magic: cint):
    JSValue {.cdecl.} =
  var pager: Pager
  if ctx.fromJS(this, pager).isErr:
    return JS_EXCEPTION
  let cval = if pager.menu != nil:
    ctx.toJS(pager.menu)
  else:
    JS_GetProperty(ctx, this, pager.bufferAtom)
  if JS_IsException(cval):
    return cval
  let res = JS_GetPropertyStr(ctx, cval, LegacyReflectGetList[magic])
  JS_FreeValue(ctx, cval)
  return res

proc addPagerModule*(ctx: JSContext): Opt[void] =
  let pagerCID = ctx.registerType(Pager)
  if pagerCID == 0:
    return err()
  let proto = JS_GetClassProto(ctx, pagerCID)
  var f: JSCFunctionType
  f.generic_magic = legacyReflectFunction
  for i, name in LegacyReflectFuncList.mypairs:
    let fun = JS_NewCFunction2(ctx, f.generic, name, 0, JS_CFUNC_generic_magic,
      cint(i))
    if ctx.defineProperty(proto, name, fun) == dprException:
      return err()
  f.getter_magic = legacyReflectGetter
  for i, name in LegacyReflectGetList.mypairs:
    let fun = JS_NewCFunction2(ctx, f.generic, name, 0, JS_CFUNC_getter_magic,
      cint(i))
    let atom = JS_NewAtom(ctx, name)
    if JS_DefineProperty(ctx, proto, atom, JS_UNDEFINED, fun, JS_UNDEFINED,
        JS_PROP_HAS_GET) < 0:
      return err()
    JS_FreeValue(ctx, fun)
    JS_FreeAtom(ctx, atom)
  JS_FreeValue(ctx, proto)
  ok()

{.pop.} # raises: []
