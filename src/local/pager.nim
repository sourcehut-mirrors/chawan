import std/deques
import std/exitprocs
import std/options
import std/os
import std/osproc
import std/posix
import std/sets
import std/strutils
import std/tables

import chagashi/charset
import chagashi/decoder
import config/chapath
import config/config
import config/mailcap
import config/mimetypes
import css/render
import io/bufreader
import io/bufwriter
import io/console
import io/dynstream
import io/poll
import io/promise
import io/tempfile
import io/timeout
import local/container
import local/lineedit
import local/select
import local/term
import monoucha/fromjs
import monoucha/javascript
import monoucha/jserror
import monoucha/jsregex
import monoucha/jstypes
import monoucha/jsutils
import monoucha/libregexp
import monoucha/quickjs
import monoucha/tojs
import server/buffer
import server/connecterror
import server/forkserver
import server/headers
import server/loaderiface
import server/request
import server/response
import server/urlfilter
import types/bitmap
import types/blob
import types/cell
import types/color
import types/cookie
import types/opt
import types/url
import types/winattrs
import utils/luwrap
import utils/regexutils
import utils/strwidth
import utils/twtstr

type
  LineMode* = enum
    lmLocation = "URL: "
    lmUsername = "Username: "
    lmPassword = "Password: "
    lmCommand = "COMMAND: "
    lmBuffer = "(BUFFER) "
    lmSearchF = "/"
    lmSearchB = "?"
    lmISearchF = "/"
    lmISearchB = "?"
    lmGotoLine = "Goto line: "
    lmDownload = "(Download)Save file to: "
    lmBufferFile = "(Upload)Filename: "
    lmAlert = "Alert: "
    lmMailcap = "Mailcap: "

  ProcMapItem = object
    container*: Container
    ostream*: PosixStream
    istreamOutputId*: int
    ostreamOutputId*: int
    redirected*: bool

  PagerAlertState = enum
    pasNormal, pasAlertOn, pasLoadInfo

  ContainerConnectionState = enum
    ccsBeforeResult, ccsBeforeStatus, ccsBeforeHeaders

  ConnectingContainer* = ref object of MapData
    state: ContainerConnectionState
    container: Container
    res: int
    outputId: int
    status: uint16

  LineData = ref object of RootObj

  LineDataDownload = ref object of LineData
    outputId: int
    stream: DynStream

  LineDataAuth = ref object of LineData
    url: URL

  LineDataMailcap = ref object of LineData
    container: Container
    ostream: PosixStream
    contentType: string
    i: int
    response: Response
    sx: int

  NavDirection = enum
    ndPrev = "prev"
    ndNext = "next"
    ndPrevSibling = "prev-sibling"
    ndNextSibling = "next-sibling"
    ndParent = "parent"
    ndFirstChild
    ndAny = "any"

  Surface = object
    redraw: bool
    grid: FixedGrid

  ConsoleWrapper* = object
    console*: Console
    container*: Container
    prev*: Container

  Pager* = ref object of RootObj
    alertState: PagerAlertState
    alerts: seq[string]
    alive: bool
    askcharpromise*: Promise[string]
    askcursor: int
    askpromise*: Promise[bool]
    askprompt: string
    blockTillRelease: bool
    commandMode {.jsget.}: bool
    config*: Config
    consoleWrapper*: ConsoleWrapper
    container {.jsget: "buffer".}: Container
    cookiejars: Table[string, CookieJar]
    display: Surface
    exitCode*: int
    feednext*: bool
    forkserver*: ForkServer
    hasload*: bool # has a page been successfully loaded since startup?
    inEval: bool
    inputBuffer: string # currently uninterpreted characters
    iregex: Result[Regex, string]
    isearchpromise: EmptyPromise
    jsctx: JSContext
    jsrt: JSRuntime
    lastAlert: string # last alert seen by the user
    lineData: LineData
    lineHist: array[LineMode, LineHistory]
    lineedit*: LineEdit
    linemode: LineMode
    loader*: FileLoader
    luctx: LUContext
    menu: Select
    navDirection {.jsget.}: NavDirection
    notnum: bool # has a non-numeric character been input already?
    numload*: int # number of pages currently being loaded
    pollData*: PollData
    precnum*: int32 # current number prefix (when vi-numeric-prefix is true)
    pressed: tuple[col, row: int]
    procmap*: seq[ProcMapItem]
    refreshAllowed: HashSet[string]
    regex: Opt[Regex]
    reverseSearch: bool
    scommand: string
    status: Surface
    term*: Terminal
    timeouts*: TimeoutState
    unreg*: seq[Container]
    urandom: PosixStream

  ContainerData* = ref object of MapData
    container*: Container

  CheckMailcapFlag = enum
    cmfConnect, cmfHTML, cmfFound, cmfRedirected, cmfPrompt, cmfNeedsstyle,
    cmfSaveoutput

  MailcapResult = object
    entry: MailcapEntry
    flags: set[CheckMailcapFlag]
    ostream: PosixStream
    ostreamOutputId: int
    cmd: string

jsDestructor(Pager)

# Forward declarations
proc acceptBuffers(pager: Pager)
proc addConsole(pager: Pager; interactive: bool): ConsoleWrapper
proc addLoaderClient(pager: Pager; pid: int; config: LoaderClientConfig;
  clonedFrom = -1): ClientKey
proc alert*(pager: Pager; msg: string)
proc askMailcap(pager: Pager; container: Container; ostream: PosixStream;
  contentType: string; i: int; response: Response; sx: int)
proc connected2(pager: Pager; container: Container; res: MailcapResult;
  response: Response)
proc draw(pager: Pager)
proc dumpBuffers(pager: Pager)
proc evalJS(pager: Pager; src, filename: string; module = false): JSValue
proc fulfillAsk(pager: Pager; y: bool)
proc fulfillCharAsk(pager: Pager; s: string)
proc getLineHist(pager: Pager; mode: LineMode): LineHistory
proc handleEvents(pager: Pager)
proc handleRead(pager: Pager; fd: int)
proc headlessLoop(pager: Pager)
proc inputLoop(pager: Pager)
proc loadURL(pager: Pager; url: string; ctype = none(string);
  cs = CHARSET_UNKNOWN)
proc openMenu(pager: Pager; x = -1; y = -1)
proc readPipe(pager: Pager; contentType: string; cs: Charset; ps: PosixStream;
  title: string)
proc refreshStatusMsg(pager: Pager)
proc runMailcap(pager: Pager; url: URL; stream: PosixStream;
  istreamOutputId: int; contentType: string; entry: MailcapEntry):
  MailcapResult
proc showAlerts(pager: Pager)
proc updateReadLine(pager: Pager)

template attrs(pager: Pager): WindowAttributes =
  pager.term.attrs

func loaderPid(pager: Pager): int {.jsfget.} =
  return pager.loader.process

func getRoot(container: Container): Container =
  var c = container
  while c.parent != nil:
    c = c.parent
  return c

func bufWidth(pager: Pager): int =
  return pager.attrs.width

func bufHeight(pager: Pager): int =
  return pager.attrs.height - 1

func console(pager: Pager): Console =
  return pager.consoleWrapper.console

# depth-first descendant iterator
iterator descendants(parent: Container): Container {.inline.} =
  var stack = newSeqOfCap[Container](parent.children.len)
  for i in countdown(parent.children.high, 0):
    stack.add(parent.children[i])
  while stack.len > 0:
    let c = stack.pop()
    # add children first, so that deleteContainer works on c
    for i in countdown(c.children.high, 0):
      stack.add(c.children[i])
    yield c

iterator containers*(pager: Pager): Container {.inline.} =
  if pager.container != nil:
    let root = getRoot(pager.container)
    yield root
    for c in root.descendants:
      yield c

proc clearDisplay(pager: Pager) =
  pager.display = Surface(
    grid: newFixedGrid(pager.bufWidth, pager.bufHeight),
    redraw: true
  )

proc clearStatus(pager: Pager) =
  pager.status = Surface(
    grid: newFixedGrid(pager.attrs.width),
    redraw: true
  )

proc setContainer(pager: Pager; c: Container) {.jsfunc.} =
  if pager.term.imageMode != imNone and pager.container != nil:
    for cachedImage in pager.container.cachedImages:
      if cachedImage.state == cisLoaded:
        pager.loader.removeCachedItem(cachedImage.cacheId)
      cachedImage.state = cisCanceled
    pager.container.cachedImages.setLen(0)
  pager.container = c
  if c != nil:
    c.queueDraw()
    pager.term.setTitle(c.getTitle())

proc reflect(ctx: JSContext; this_val: JSValue; argc: cint;
    argv: ptr UncheckedArray[JSValue]; magic: cint;
    func_data: ptr UncheckedArray[JSValue]): JSValue {.cdecl.} =
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

proc getLineHist(pager: Pager; mode: LineMode): LineHistory =
  if pager.lineHist[mode] == nil:
    pager.lineHist[mode] = newLineHistory()
  return pager.lineHist[mode]

proc setLineEdit(pager: Pager; mode: LineMode; current = ""; hide = false;
    extraPrompt = "") =
  let hist = pager.getLineHist(mode)
  if pager.term.isatty() and pager.config.input.use_mouse:
    pager.term.disableMouse()
  pager.lineedit = readLine($mode & extraPrompt, current, pager.attrs.width,
    {}, hide, hist, pager.luctx)
  pager.linemode = mode

# Reuse the line editor as an alert message viewer.
proc showFullAlert(pager: Pager) {.jsfunc.} =
  if pager.lastAlert != "":
    pager.setLineEdit(lmAlert, pager.lastAlert)

proc clearLineEdit(pager: Pager) =
  pager.lineedit = nil
  if pager.term.isatty() and pager.config.input.use_mouse:
    pager.term.enableMouse()

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

proc gotoLine(ctx: JSContext; pager: Pager; val = JS_UNDEFINED): Opt[void]
    {.jsfunc.} =
  var n: int
  if ctx.fromJS(val, n).isSome:
    pager.container.gotoLine(n)
  elif JS_IsUndefined(val):
    pager.setLineEdit(lmGotoLine)
  else:
    var s: string
    ?ctx.fromJS(val, s)
    pager.container.gotoLine(s)
  return ok()

proc setImportMeta(ctx: JSContext; funcVal: JSValue; isMain: bool) =
  let m = cast[JSModuleDef](JS_VALUE_GET_PTR(funcVal))
  let moduleNameAtom = JS_GetModuleName(ctx, m)
  let metaObj = JS_GetImportMeta(ctx, m)
  definePropertyCWE(ctx, metaObj, "url", JS_AtomToValue(ctx, moduleNameAtom))
  definePropertyCWE(ctx, metaObj, "main", isMain)
  JS_FreeValue(ctx, metaObj)
  JS_FreeAtom(ctx, moduleNameAtom)

proc finishLoadModule(ctx: JSContext; f: string; name: cstring): JSModuleDef =
  let funcVal = compileModule(ctx, f, $name)
  if JS_IsException(funcVal):
    return nil
  setImportMeta(ctx, funcVal, false)
  # "the module is already referenced, so we must free it"
  # idk how this works, so for now let's just do what qjs does
  result = cast[JSModuleDef](JS_VALUE_GET_PTR(funcVal))
  JS_FreeValue(ctx, funcVal)

proc normalizeModuleName(ctx: JSContext; base_name, name: cstringConst;
    opaque: pointer): cstring {.cdecl.} =
  return js_strdup(ctx, cstring(name))

proc clientLoadJSModule(ctx: JSContext; module_name: cstringConst;
    opaque: pointer): JSModuleDef {.cdecl.} =
  let global = JS_GetGlobalObject(ctx)
  JS_FreeValue(ctx, global)
  var x: Option[URL]
  if module_name[0] == '/' or module_name[0] == '.' and
      (module_name[1] == '/' or
      module_name[1] == '.' and module_name[2] == '/'):
    let cur = getCurrentDir()
    x = parseURL($module_name, parseURL("file://" & cur & "/"))
  else:
    x = parseURL($module_name)
  if x.isNone or x.get.scheme != "file":
    JS_ThrowTypeError(ctx, "Invalid URL: %s", module_name)
    return nil
  try:
    let f = readFile(x.get.pathname)
    return finishLoadModule(ctx, f, cstring(module_name))
  except IOError:
    JS_ThrowTypeError(ctx, "Failed to open file %s", module_name)
    return nil

proc interruptHandler(rt: JSRuntime; opaque: pointer): cint {.cdecl.} =
  let pager = cast[Pager](opaque)
  if pager.console != nil and pager.term.istream != nil:
    try:
      var buf = [char(0)]
      let n = pager.term.istream.recvData(buf)
      if n == 1 and buf[0] == char(3): #C-c
        pager.term.ibuf = ""
        return 1
      pager.term.ibuf &= buf[0]
    except ErrorAgain:
      discard
  return 0

proc evalJSFree(opaque: RootRef; src, filename: string) =
  let pager = Pager(opaque)
  JS_FreeValue(pager.jsctx, pager.evalJS(src, filename))

proc newPager*(config: Config; forkserver: ForkServer; ctx: JSContext;
    alerts: seq[string]; urandom: PosixStream; loader: FileLoader): Pager =
  let pager = Pager(
    alive: true,
    config: config,
    forkserver: forkserver,
    term: newTerminal(stdout, config),
    alerts: alerts,
    jsrt: JS_GetRuntime(ctx),
    jsctx: ctx,
    luctx: LUContext(),
    urandom: urandom,
    exitCode: -1,
    loader: loader
  )
  pager.timeouts = newTimeoutState(pager.jsctx, evalJSFree, pager)
  JS_SetModuleLoaderFunc(pager.jsrt, normalizeModuleName, clientLoadJSModule,
    nil)
  JS_SetInterruptHandler(pager.jsrt, interruptHandler, cast[pointer](pager))
  loader.key = pager.addLoaderClient(pager.loader.clientPid, LoaderClientConfig(
    defaultHeaders: newHeaders(pager.config.network.default_headers),
    proxy: pager.config.network.proxy,
    filter: newURLFilter(default = true),
  ))
  return pager

proc cleanup(pager: Pager) =
  if pager.alive:
    pager.alive = false
    pager.term.quit()
    for msg in pager.alerts:
      stderr.write("cha: " & msg & '\n')
    for val in pager.config.cmd.map.values:
      JS_FreeValue(pager.jsctx, val)
    for fn in pager.config.jsvfns:
      JS_FreeValue(pager.jsctx, fn)
    pager.timeouts.clearAll()
    assert not pager.inEval
    pager.jsctx.free()
    pager.jsrt.free()

proc quit*(pager: Pager; code: int) =
  pager.cleanup()
  quit(code)

proc runJSJobs(pager: Pager) =
  while true:
    let r = pager.jsrt.runJSJobs()
    if r.isSome:
      break
    let ctx = r.error
    ctx.writeException(pager.console.err)
  if pager.exitCode != -1:
    pager.quit(0)

proc evalJS(pager: Pager; src, filename: string; module = false): JSValue =
  pager.term.unblockStdin()
  let flags = if module:
    JS_EVAL_TYPE_MODULE
  else:
    JS_EVAL_TYPE_GLOBAL
  let wasInEval = pager.inEval
  pager.inEval = true
  result = pager.jsctx.eval(src, filename, flags)
  pager.inEval = false
  pager.term.restoreStdin()
  if pager.exitCode != -1:
    # if we are in a nested eval, then just wait until we are not.
    if not wasInEval:
      pager.quit(pager.exitCode)
  else:
    pager.runJSJobs()

proc evalActionJS(pager: Pager; action: string): JSValue =
  if action.startsWith("cmd."):
    pager.config.cmd.map.withValue(action.substr("cmd.".len), p):
      return JS_DupValue(pager.jsctx, p[])
  return pager.evalJS(action, "<command>")

# Warning: this is not re-entrant.
proc evalAction(pager: Pager; action: string; arg0: int32): EmptyPromise =
  var ret = pager.evalActionJS(action)
  let ctx = pager.jsctx
  var p = EmptyPromise()
  p.resolve()
  if JS_IsFunction(ctx, ret):
    if arg0 != 0:
      let arg0 = toJS(ctx, arg0)
      let ret2 = JS_Call(ctx, ret, JS_UNDEFINED, 1, arg0.toJSValueArray())
      JS_FreeValue(ctx, arg0)
      JS_FreeValue(ctx, ret)
      ret = ret2
    else: # no precnum
      let ret2 = JS_Call(ctx, ret, JS_UNDEFINED, 0, nil)
      JS_FreeValue(ctx, ret)
      ret = ret2
    if pager.exitCode != -1:
      assert not pager.inEval
      pager.quit(pager.exitCode)
  if JS_IsException(ret):
    pager.jsctx.writeException(pager.console.err)
  elif JS_IsObject(ret):
    var maybep: EmptyPromise
    if ctx.fromJS(ret, maybep).isSome:
      p = maybep
  JS_FreeValue(ctx, ret)
  return p

proc command0(pager: Pager; src: string; filename = "<command>";
    silence = false; module = false) =
  let ret = pager.evalJS(src, filename, module = module)
  if JS_IsException(ret):
    pager.jsctx.writeException(pager.console.err)
  else:
    if not silence:
      var res: string
      if pager.jsctx.fromJS(ret, res).isSome:
        pager.console.log(res)
  JS_FreeValue(pager.jsctx, ret)

proc handleMouseInputGeneric(pager: Pager; input: MouseInput) =
  case input.button
  of mibLeft:
    case input.t
    of mitPress:
      pager.pressed = (input.col, input.row)
    of mitRelease:
      if pager.pressed != (-1, -1):
        let diff = (input.col - pager.pressed.col,
          input.row - pager.pressed.row)
        if diff[0] > 0:
          discard pager.evalAction("cmd.buffer.scrollLeft", int32(diff[0]))
        elif diff[0] < 0:
          discard pager.evalAction("cmd.buffer.scrollRight", -int32(diff[0]))
        if diff[1] > 0:
          discard pager.evalAction("cmd.buffer.scrollUp", int32(diff[1]))
        elif diff[1] < 0:
          discard pager.evalAction("cmd.buffer.scrollDown", -int32(diff[1]))
        pager.pressed = (-1, -1)
    else: discard
  of mibWheelUp:
    if input.t == mitPress:
      discard pager.evalAction("cmd.buffer.scrollUp", 5)
  of mibWheelDown:
    if input.t == mitPress:
      discard pager.evalAction("cmd.buffer.scrollDown", 5)
  of mibWheelLeft:
    if input.t == mitPress:
      discard pager.evalAction("cmd.buffer.scrollLeft", 5)
  of mibWheelRight:
    if input.t == mitPress:
      discard pager.evalAction("cmd.buffer.scrollRight", 5)
  else: discard

proc handleMouseInput(pager: Pager; input: MouseInput; container: Container) =
  case input.button
  of mibLeft:
    if input.t == mitRelease and pager.pressed == (input.col, input.row):
      let prevx = container.cursorx
      let prevy = container.cursory
      #TODO I wish we could avoid setCursorXY if we're just going to
      # click, but that doesn't work with double-width chars
      container.setCursorXY(container.fromx + input.col,
        container.fromy + input.row)
      if container.cursorx == prevx and container.cursory == prevy:
        discard pager.evalAction("cmd.buffer.click", 0)
  of mibMiddle:
    if input.t == mitRelease: # release, to emulate w3m
      discard pager.evalAction("cmd.pager.discardBuffer", 0)
  of mibRight:
    if input.t == mitPress: # w3m uses release, but I like this better
      pager.pressed = (input.col, input.row)
      container.setCursorXY(container.fromx + input.col,
        container.fromy + input.row)
      pager.openMenu(input.col, input.row)
      pager.menu.unselect()
  of mibThumbInner:
    if input.t == mitPress:
      discard pager.evalAction("cmd.pager.prevBuffer", 0)
  of mibThumbTip:
    if input.t == mitPress:
      discard pager.evalAction("cmd.pager.nextBuffer", 0)
  else: discard

proc handleMouseInput(pager: Pager; input: MouseInput; select: Select) =
  let y = select.fromy + input.row - select.y - 1 # one off because of border
  if input.button in {mibRight, mibLeft}:
    # Note: "not inside and not outside" is a valid state, and it
    # represents the mouse being above the border.
    let inside = input.row in select.y + 1 ..< select.y + select.height - 1 and
      input.col in select.x + 1 ..< select.x + select.width - 1
    let outside = input.row notin select.y ..< select.y + select.height or
      input.col notin select.x ..< select.x + select.width
    if input.button == mibRight:
      if not inside:
        select.unselect()
      elif (input.col, input.row) != pager.pressed:
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
        if inside and (input.col, input.row) != pager.pressed:
          select.click()
        elif outside:
          select.cursorLeft()
        # forget about where we started once btn3 is released
        pager.pressed = (-1, -1)
      of mitMove: discard
    else: # mibLeft
      case input.t
      of mitPress:
        if outside: # clicked outside the select
          pager.blockTillRelease = true
          select.cursorLeft()
      of mitRelease:
        let at = (input.col, input.row)
        if at == pager.pressed and
            (inside or select.multiple and at == (select.x, select.y)):
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

# The maximum number we are willing to accept.
# This should be fine for 32-bit signed ints (which precnum currently is).
# We can always increase it further (e.g. by switching to uint32, uint64...) if
# it proves to be too low.
const MaxPrecNum = 100000000

proc handleCommandInput(pager: Pager; c: char): EmptyPromise =
  if pager.config.input.vi_numeric_prefix and not pager.notnum:
    if pager.precnum != 0 and c == '0' or c in '1' .. '9':
      if pager.precnum < MaxPrecNum: # better ignore than eval...
        pager.precnum *= 10
        pager.precnum += cast[int32](decValue(c))
      return
    else:
      pager.notnum = true
  pager.inputBuffer &= c
  let action = getNormalAction(pager.config, pager.inputBuffer)
  if action != "":
    let p = pager.evalAction(action, pager.precnum)
    if not pager.feednext:
      pager.precnum = 0
      pager.notnum = false
      pager.handleEvents()
    return p
  if pager.config.input.use_mouse:
    if pager.inputBuffer == "\e[<":
      let input = pager.term.parseMouseInput()
      if input.isSome:
        let input = input.get
        pager.handleMouseInput(input)
      pager.inputBuffer = ""
    elif "\e[<".startsWith(pager.inputBuffer):
      pager.feednext = true
  return nil

proc input(pager: Pager): EmptyPromise =
  var p: EmptyPromise = nil
  pager.term.restoreStdin()
  var buf: string
  while true:
    let c = pager.term.readChar()
    if pager.askpromise != nil:
      if c == 'y':
        pager.fulfillAsk(true)
      elif c == 'n':
        pager.fulfillAsk(false)
    elif pager.askcharpromise != nil:
      buf &= c
      if buf.validateUTF8Surr() != -1:
        continue
      pager.fulfillCharAsk(buf)
    elif pager.lineedit != nil:
      pager.inputBuffer &= c
      let edit = pager.lineedit
      if edit.escNext:
        edit.escNext = false
        if edit.write(pager.inputBuffer, pager.term.cs):
          pager.inputBuffer = ""
      else:
        let action = pager.config.getLinedAction(pager.inputBuffer)
        if action == "":
          if edit.write(pager.inputBuffer, pager.term.cs):
            pager.inputBuffer = ""
          else:
            pager.feednext = true
        elif not pager.feednext:
          discard pager.evalAction(action, 0)
        if not pager.feednext:
          pager.updateReadLine()
    else:
      p = pager.handleCommandInput(c)
      if not pager.feednext:
        pager.inputBuffer = ""
        pager.refreshStatusMsg()
        break
      #TODO this is not perfect, because it results in us never displaying
      # lone escape. maybe a timeout for escape display would be useful
      if not "\e[<".startsWith(pager.inputBuffer):
        pager.refreshStatusMsg()
        pager.draw()
    if not pager.feednext:
      pager.inputBuffer = ""
      break
    else:
      pager.feednext = false
  pager.inputBuffer = ""
  if p == nil:
    p = newResolvedPromise()
  return p

proc genClientKey(pager: Pager): ClientKey =
  var key: ClientKey
  pager.urandom.recvDataLoop(key)
  return key

proc addLoaderClient(pager: Pager; pid: int; config: LoaderClientConfig;
    clonedFrom = -1): ClientKey =
  var key = pager.genClientKey()
  while unlikely(not pager.loader.addClient(key, pid, config, clonedFrom)):
    key = pager.genClientKey()
  return key

proc run*(pager: Pager; pages: openArray[string]; contentType: Option[string];
    cs: Charset; dump: bool) =
  var istream: PosixStream = nil
  var dump = dump
  if not dump:
    if stdin.isatty():
      istream = newPosixStream(STDIN_FILENO)
    if stdout.isatty():
      if istream == nil:
        istream = newPosixStream("/dev/tty", O_RDONLY, 0)
    else:
      istream = nil
    dump = istream == nil
  pager.pollData.register(pager.forkserver.estream.fd, POLLIN)
  pager.loader.registerFun = proc(fd: int) =
    pager.pollData.register(fd, POLLIN)
  pager.loader.unregisterFun = proc(fd: int) =
    pager.pollData.unregister(fd)
  case pager.term.start(istream)
  of tsrSuccess: discard
  of tsrDA1Fail:
    pager.alert("Failed to query DA1, please set display.query-da1 = false")
  pager.clearDisplay()
  pager.clearStatus()
  pager.consoleWrapper = pager.addConsole(interactive = istream != nil)
  addExitProc((proc() = pager.cleanup()))
  if pager.config.start.startup_script != "":
    let s = if fileExists(pager.config.start.startup_script):
      readFile(pager.config.start.startup_script)
    else:
      pager.config.start.startup_script
    let ismodule = pager.config.start.startup_script.endsWith(".mjs")
    pager.command0(s, pager.config.start.startup_script, silence = true,
      module = ismodule)
  if not stdin.isatty():
    # stdin may very well receive ANSI text
    let contentType = contentType.get("text/x-ansi")
    let ps = newPosixStream(STDIN_FILENO)
    pager.readPipe(contentType, cs, ps, "*stdin*")
  for page in pages:
    pager.loadURL(page, ctype = contentType, cs = cs)
  pager.showAlerts()
  pager.acceptBuffers()
  if not dump:
    pager.inputLoop()
  else:
    pager.dumpBuffers()
  if pager.config.start.headless:
    pager.headlessLoop()

# Note: this function does not work correctly if start < x of last written char
proc writeStatusMessage(pager: Pager; str: string; format = Format();
    start = 0; maxwidth = -1; clip = '$'): int =
  var maxwidth = maxwidth
  if maxwidth == -1:
    maxwidth = pager.status.grid.len
  var x = start
  let e = min(start + maxwidth, pager.status.grid.width)
  if x >= e:
    return x
  pager.status.redraw = true
  var lx = 0
  for u in str.points:
    let w = u.width()
    if x + w > e: # clip if we overflow (but not on exact fit)
      if lx < e:
        pager.status.grid[lx].format = format
        pager.status.grid[lx].str = $clip
      x = lx + 1 # clip must be 1 cell wide
      break
    if u.isControlChar():
      pager.status.grid[x].str = "^"
      pager.status.grid[x + 1].str = $getControlLetter(char(u))
      pager.status.grid[x + 1].format = format
    else:
      pager.status.grid[x].str = u.toUTF8()
    pager.status.grid[x].format = format
    lx = x
    let nx = x + w
    inc x
    while x < nx: # clear unset cells
      pager.status.grid[x].str = ""
      pager.status.grid[x].format = Format()
      inc x
  result = x
  while x < e:
    pager.status.grid[x].str = ""
    pager.status.grid[x].format = Format()
    inc x

# Note: should only be called directly after user interaction.
proc refreshStatusMsg(pager: Pager) =
  let container = pager.container
  if container == nil: return
  if pager.askpromise != nil: return
  if pager.precnum != 0:
    discard pager.writeStatusMessage($pager.precnum & pager.inputBuffer)
  elif pager.inputBuffer != "":
    discard pager.writeStatusMessage(pager.inputBuffer)
  elif pager.alerts.len > 0:
    pager.alertState = pasAlertOn
    discard pager.writeStatusMessage(pager.alerts[0])
    # save to alert history
    if pager.lastAlert != "":
      let hist = pager.getLineHist(lmAlert)
      if hist.lines.len == 0 or hist.lines[^1] != pager.lastAlert:
        if hist.lines.len > 19:
          hist.lines.delete(0)
        hist.lines.add(move(pager.lastAlert))
    pager.lastAlert = move(pager.alerts[0])
    pager.alerts.delete(0)
  else:
    var format = Format(flags: {ffReverse})
    pager.alertState = pasNormal
    container.clearHover()
    var msg = $(container.cursory + 1) & "/" & $container.numLines &
      " (" & $container.atPercentOf() & "%)" &
      " <" & container.getTitle()
    let hover = container.getHoverText()
    let sl = hover.width()
    var l = 0
    var i = 0
    var maxw = pager.status.grid.width - 1 # -1 for '>'
    if sl > 0:
      maxw -= 1 # plus one blank
    while i < msg.len:
      let pi = i
      let u = msg.nextUTF8(i)
      l += u.width()
      if l + sl >= maxw:
        i = pi
        break
    msg.setLen(i)
    if i > 0:
      msg &= ">"
      if sl > 0:
        msg &= ' '
    msg &= hover
    discard pager.writeStatusMessage(msg, format)

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
  return ls

proc drawBuffer*(pager: Pager; container: Container; ofile: File) =
  var format = Format()
  container.readLines(proc(line: SimpleFlexibleLine) =
    var x = 0
    var w = -1
    var i = 0
    var s = ""
    for f in line.formats:
      let ls = line.str.drawBufferAdvance(format.bgcolor, i, x, f.pos)
      s.processOutputString(pager.term, ls, w)
      s.processFormat(pager.term, format, f.format)
    if i < line.str.len:
      let ls = line.str.drawBufferAdvance(format.bgcolor, i, x, int.high)
      s.processOutputString(pager.term, ls, w)
    s.processFormat(pager.term, format, Format())
    ofile.writeLine(s)
  )
  ofile.flushFile()

proc redraw(pager: Pager) {.jsfunc.} =
  pager.term.clearCanvas()
  pager.display.redraw = true
  pager.status.redraw = true
  if pager.container != nil:
    pager.container.redraw = true
    if pager.container.select != nil:
      pager.container.select.redraw = true

proc getTempFile(pager: Pager; ext = ""): string =
  return getTempFile(pager.config.external.tmpdir, ext)

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
  pager.loader.shareCachedItem(bmp.cacheId, pager.loader.clientPid,
    container.process)
  let imageMode = pager.term.imageMode
  pager.loader.fetch(newRequest(
    newURL("img-codec+" & bmp.contentType.after('/') & ":decode").get,
    httpMethod = hmPost,
    body = RequestBody(t: rbtCache, cacheId: bmp.cacheId),
    tocache = true
  )).then(proc(res: JSResult[Response]): FetchPromise =
    # remove previous step
    pager.loader.removeCachedItem(bmp.cacheId)
    if res.isNone:
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
    let headers = newHeaders({
      "Cha-Image-Dimensions": $bmp.width & 'x' & $bmp.height,
      "Cha-Image-Target-Dimensions": $image.width & 'x' & $image.height
    })
    let p = pager.loader.fetch(newRequest(
      newURL("cgi-bin:resize").get,
      httpMethod = hmPost,
      headers = headers,
      body = RequestBody(t: rbtCache, cacheId: cacheId),
      tocache = true
    )).then(proc(res: JSResult[Response]): FetchPromise =
      # ugh. I must remove the previous cached item, but only after
      # resize is done...
      pager.loader.removeCachedItem(cacheId)
      return newResolvedPromise(res)
    )
    response.resume()
    response.close()
    return p
  ).then(proc(res: JSResult[Response]) =
    if res.isNone:
      return
    let response = res.get
    let cacheId = response.outputId
    if cachedImage.state == cisCanceled:
      pager.loader.removeCachedItem(cacheId)
      return
    let headers = newHeaders({
      "Cha-Image-Dimensions": $image.width & 'x' & $image.height
    })
    var url: URL = nil
    case imageMode
    of imSixel:
      url = newURL("img-codec+x-sixel:encode").get
      headers.add("Cha-Image-Sixel-Halfdump", "1")
      headers.add("Cha-Image-Sixel-Palette", $pager.term.sixelRegisterNum)
      headers.add("Cha-Image-Offset", $offx & 'x' & $erry)
      headers.add("Cha-Image-Crop-Width", $dispw)
    of imKitty:
      url = newURL("img-codec+png:encode").get
    of imNone: assert false
    let request = newRequest(
      url,
      httpMethod = hmPost,
      headers = headers,
      body = RequestBody(t: rbtCache, cacheId: cacheId),
      tocache = true
    )
    let r = pager.loader.fetch(request)
    response.resume()
    response.close()
    r.then(proc(res: JSResult[Response]) =
      # remove previous step
      pager.loader.removeCachedItem(cacheId)
      if res.isNone:
        return
      let response = res.get
      response.resume()
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
        response.headers.getOrDefault("Cha-Image-Sixel-Transparent", "0") == "1"
      let plens = response.headers.getOrDefault("Cha-Image-Sixel-Prelude-Len")
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
      let width = min(image.width - offx, pager.term.sixelMaxWidth) + offx
      dispw = min(width + xpx, maxwpx) - xpx
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

proc draw(pager: Pager) =
  var redraw = false
  var imageRedraw = false
  var hasMenu = false
  let container = pager.container
  if container != nil:
    if container.redraw:
      pager.clearDisplay()
      let hlcolor = cellColor(pager.config.display.highlight_color.rgb)
      container.drawLines(pager.display.grid, hlcolor)
      if pager.config.display.highlight_marks:
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
  if pager.askpromise != nil or pager.askcharpromise != nil:
    pager.term.writeGrid(pager.status.grid, 0, pager.attrs.height - 1)
    pager.status.redraw = false
    redraw = true
  elif pager.lineedit != nil:
    if pager.lineedit.redraw:
      let x = pager.lineedit.generateOutput()
      pager.term.writeGrid(x, 0, pager.attrs.height - 1)
      pager.lineedit.redraw = false
      redraw = true
  elif pager.status.redraw:
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
    pager.term.hideCursor()
    pager.term.outputGrid()
    if pager.term.imageMode != imNone:
      pager.term.outputImages()
  if pager.askpromise != nil:
    pager.term.setCursor(pager.askcursor, pager.attrs.height - 1)
  elif pager.lineedit != nil:
    pager.term.setCursor(pager.lineedit.getCursorX(), pager.attrs.height - 1)
  elif (let menu = pager.menu; menu != nil):
    pager.term.setCursor(menu.getCursorX(), menu.getCursorY())
  elif container != nil:
    if (let select = container.select; select != nil):
      pager.term.setCursor(select.getCursorX(), select.getCursorY())
    else:
      pager.term.setCursor(container.acursorx, container.acursory)
  if redraw:
    pager.term.showCursor()
  pager.term.flush()

proc writeAskPrompt(pager: Pager; s = "") =
  let maxwidth = pager.status.grid.width - s.width()
  let i = pager.writeStatusMessage(pager.askprompt, maxwidth = maxwidth)
  pager.askcursor = pager.writeStatusMessage(s, start = i)

proc ask(pager: Pager; prompt: string): Promise[bool] {.jsfunc.} =
  pager.askprompt = prompt
  pager.writeAskPrompt(" (y/n)")
  pager.askpromise = Promise[bool]()
  return pager.askpromise

proc askChar(pager: Pager; prompt: string): Promise[string] {.jsfunc.} =
  pager.askprompt = prompt
  pager.writeAskPrompt()
  pager.askcharpromise = Promise[string]()
  return pager.askcharpromise

proc fulfillAsk(pager: Pager; y: bool) =
  let p = pager.askpromise
  pager.askpromise = nil
  pager.askprompt = ""
  p.resolve(y)

proc fulfillCharAsk(pager: Pager; s: string) =
  let p = pager.askcharpromise
  pager.askcharpromise = nil
  pager.askprompt = ""
  p.resolve(s)

proc addContainer*(pager: Pager; container: Container) =
  container.parent = pager.container
  if pager.container != nil:
    pager.container.children.insert(container, 0)
  pager.setContainer(container)

proc onSetLoadInfo(pager: Pager; container: Container) =
  if pager.alertState != pasAlertOn:
    if container.loadinfo == "":
      pager.alertState = pasNormal
    else:
      discard pager.writeStatusMessage(container.loadinfo)
      pager.alertState = pasLoadInfo

proc newContainer(pager: Pager; bufferConfig: BufferConfig;
    loaderConfig: LoaderClientConfig; request: Request; title = "";
    redirectDepth = 0; flags = {cfCanReinterpret, cfUserRequested};
    contentType = none(string); charsetStack: seq[Charset] = @[];
    url = request.url): Container =
  let stream = pager.loader.startRequest(request, loaderConfig)
  pager.loader.registerFun(stream.fd)
  let cacheId = if request.url.scheme == "cache":
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
    pager.config
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
  let url = newURL("cache:" & $container.cacheId).get
  return pager.newContainer(
    container.config,
    container.loaderConfig,
    newRequest(url),
    contentType = some(contentType),
    charsetStack = container.charsetStack,
    url = container.url
  )

func findConnectingContainer(pager: Pager; container: Container):
    ConnectingContainer =
  for item in pager.loader.data:
    if item of ConnectingContainer:
      let item = ConnectingContainer(item)
      if item.container == container:
        return item
  return nil

func findProcMapItem(pager: Pager; pid: int): int =
  for i, item in pager.procmap.mypairs:
    if item.container.process == pid:
      return i
  -1

proc dupeBuffer(pager: Pager; container: Container; url: URL) =
  let p = container.clone(url, pager.loader)
  if p == nil:
    pager.alert("Failed to duplicate buffer.")
  else:
    p.then(proc(container: Container): Container =
      if container == nil:
        pager.alert("Failed to duplicate buffer.")
      else:
        pager.addContainer(container)
        pager.procmap.add(ProcMapItem(
          container: container,
          istreamOutputId: -1,
          ostreamOutputId: -1
        ))
    )

proc dupeBuffer(pager: Pager) {.jsfunc.} =
  pager.dupeBuffer(pager.container, pager.container.url)

func findPrev(container: Container): Container =
  if container.parent == nil:
    return nil
  let n = container.parent.children.find(container)
  assert n != -1, "Container not a child of its parent"
  if n == 0:
    return container.parent
  var container = container.parent.children[n - 1]
  while container.children.len > 0:
    container = container.children[^1]
  return container

func findNext(container: Container): Container =
  if container.children.len > 0:
    return container.children[0]
  var container = container
  while container.parent != nil:
    let n = container.parent.children.find(container)
    assert n != -1, "Container not a child of its parent"
    if n < container.parent.children.high:
      return container.parent.children[n + 1]
    container = container.parent
  return nil

func findPrevSibling(container: Container): Container =
  if container.parent == nil:
    return nil
  var n = container.parent.children.find(container)
  assert n != -1, "Container not a child of its parent"
  if n == 0:
    n = container.parent.children.len
  return container.parent.children[n - 1]

func findNextSibling(container: Container): Container =
  if container.parent == nil:
    return nil
  var n = container.parent.children.find(container)
  assert n != -1, "Container not a child of its parent"
  if n == container.parent.children.high:
    n = -1
  return container.parent.children[n + 1]

func findParent(container: Container): Container =
  return container.parent

func findFirstChild(container: Container): Container =
  if container.children.len == 0:
    return nil
  return container.children[0]

func findAny(container: Container): Container =
  let prev = container.findPrev()
  if prev != nil:
    return prev
  return container.findNext()

func opposite(dir: NavDirection): NavDirection =
  const Map = [
    ndPrev: ndNext,
    ndNext: ndPrev,
    ndPrevSibling: ndNextSibling,
    ndNextSibling: ndPrevSibling,
    ndParent: ndFirstChild,
    ndFirstChild: ndParent,
    ndAny: ndAny
  ]
  return Map[dir]

func find(container: Container; dir: NavDirection): Container =
  return case dir
  of ndPrev: container.findPrev()
  of ndNext: container.findNext()
  of ndPrevSibling: container.findPrevSibling()
  of ndNextSibling: container.findNextSibling()
  of ndParent: container.findParent()
  of ndFirstChild: container.findFirstChild()
  of ndAny: container.findAny()

# The prevBuffer and nextBuffer procedures emulate w3m's PREV and NEXT
# commands by traversing the container tree in a depth-first order.
proc prevBuffer(pager: Pager): bool {.jsfunc.} =
  pager.navDirection = ndPrev
  if pager.container == nil:
    return false
  let prev = pager.container.findPrev()
  if prev == nil:
    return false
  pager.setContainer(prev)
  return true

proc nextBuffer(pager: Pager): bool {.jsfunc.} =
  pager.navDirection = ndNext
  if pager.container == nil:
    return false
  let next = pager.container.findNext()
  if next == nil:
    return false
  pager.setContainer(next)
  return true

proc parentBuffer(pager: Pager): bool {.jsfunc.} =
  pager.navDirection = ndParent
  if pager.container == nil:
    return false
  let parent = pager.container.findParent()
  if parent == nil:
    return false
  pager.setContainer(parent)
  return true

proc prevSiblingBuffer(pager: Pager): bool {.jsfunc.} =
  pager.navDirection = ndPrevSibling
  if pager.container == nil:
    return false
  if pager.container.parent == nil:
    return false
  var n = pager.container.parent.children.find(pager.container)
  assert n != -1, "Container not a child of its parent"
  if n == 0:
    n = pager.container.parent.children.len
  pager.setContainer(pager.container.parent.children[n - 1])
  return true

proc nextSiblingBuffer(pager: Pager): bool {.jsfunc.} =
  pager.navDirection = ndNextSibling
  if pager.container == nil:
    return false
  if pager.container.parent == nil:
    return false
  var n = pager.container.parent.children.find(pager.container)
  assert n != -1, "Container not a child of its parent"
  if n == pager.container.parent.children.high:
    n = -1
  pager.setContainer(pager.container.parent.children[n + 1])
  return true

proc alert*(pager: Pager; msg: string) {.jsfunc.} =
  if msg != "":
    pager.alerts.add(msg)

# replace target with container in the tree
proc replace(pager: Pager; target, container: Container) =
  let n = target.children.find(container)
  if n != -1:
    target.children.delete(n)
    container.parent = nil
  let n2 = container.children.find(target)
  if n2 != -1:
    container.children.delete(n2)
    target.parent = nil
  container.children.add(target.children)
  for child in container.children:
    child.parent = container
  target.children.setLen(0)
  if target.parent != nil:
    container.parent = target.parent
    let n = target.parent.children.find(target)
    assert n != -1, "Container not a child of its parent"
    container.parent.children[n] = container
    target.parent = nil
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
  if container.parent != nil:
    let parent = container.parent
    let n = parent.children.find(container)
    assert n != -1, "Container not a child of its parent"
    for i in countdown(container.children.high, 0):
      let child = container.children[i]
      child.parent = container.parent
      parent.children.insert(child, n + 1)
    parent.children.delete(n)
  elif container.children.len > 0:
    let parent = container.children[0]
    parent.parent = nil
    for i in 1..container.children.high:
      container.children[i].parent = parent
      parent.children.add(container.children[i])
  container.parent = nil
  container.children.setLen(0)
  if container.replace != nil:
    container.replace = nil
  elif container.replaceBackup != nil:
    container.replaceBackup = nil
  elif pager.container == container:
    pager.setContainer(setTarget)
  pager.unreg.add(container)
  if container.process != -1:
    pager.loader.removeCachedItem(container.cacheId)
    pager.forkserver.removeChild(container.process)
    pager.loader.removeClient(container.process)

proc discardBuffer(pager: Pager; container = none(Container);
    dir = none(NavDirection)) {.jsfunc.} =
  if dir.isSome:
    pager.navDirection = dir.get.opposite()
  let container = container.get(pager.container)
  let dir = pager.navDirection.opposite()
  let setTarget = container.find(dir)
  if container == nil or setTarget == nil:
    pager.alert("No buffer in direction: " & $dir)
  else:
    pager.deleteContainer(container, setTarget)

proc discardTree(pager: Pager; container = none(Container)) {.jsfunc.} =
  let container = container.get(pager.container)
  if container != nil:
    for c in container.descendants:
      pager.deleteContainer(container, nil)
  else:
    pager.alert("Buffer has no children!")

template myFork(): cint =
  stdout.flushFile()
  stderr.flushFile()
  fork()

template myExec(cmd: string) =
  discard execl("/bin/sh", "sh", "-c", cstring(cmd), nil)
  exitnow(127)

proc setEnvVars(pager: Pager; env: JSValue) =
  try:
    if pager.container != nil and JS_IsUndefined(env):
      putEnv("CHA_URL", $pager.container.url)
      putEnv("CHA_CHARSET", $pager.container.charset)
    else:
      var tab: Table[string, string]
      if pager.jsctx.fromJS(env, tab).isSome:
        for k, v in tab:
          putEnv(k, v)
  except OSError:
    pager.alert("Warning: failed to set some environment variables")

# Run process (and suspend the terminal controller).
# For the most part, this emulates system(3).
proc runCommand(pager: Pager; cmd: string; suspend, wait: bool;
    env: JSValue): bool =
  if suspend:
    pager.term.quit()
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
    return
  case (let pid = myFork(); pid)
  of -1:
    pager.alert("Failed to run process")
  of 0:
    act.sa_handler = SIG_DFL
    discard sigemptyset(act.sa_mask)
    discard sigaction(SIGINT, oldint, act)
    discard sigaction(SIGQUIT, oldquit, act)
    discard sigprocmask(SIG_SETMASK, oldmask, dummy);
    for it in pager.loader.data:
      if it.stream.fd > 2:
        it.stream.sclose()
    #TODO this is probably a bad idea: we are interacting with a js
    # context in a forked process.
    # likely not much of a problem unless the user does something very
    # stupid, but may still be surprising.
    pager.setEnvVars(env)
    if not suspend:
      newPosixStream(STDOUT_FILENO).safeClose()
      newPosixStream(STDERR_FILENO).safeClose()
      newPosixStream(STDIN_FILENO).safeClose()
    else:
      if pager.term.istream != nil:
        discard dup2(pager.term.istream.fd, STDIN_FILENO)
    discard execl("/bin/sh", "sh", "-c", cstring(cmd), nil)
    exitnow(127)
  else:
    var wstatus: cint
    while waitpid(pid, wstatus, 0) == -1:
      if errno != EINTR:
        return false
    discard sigaction(SIGINT, oldint, act)
    discard sigprocmask(SIG_SETMASK, oldmask, dummy);
    if suspend:
      if wait:
        pager.term.anyKey()
      pager.term.restart()
    return WIFEXITED(wstatus) and WEXITSTATUS(wstatus) == 0

# Run process, and capture its output.
proc runProcessCapture(cmd: string; outs: var string): bool =
  let file = popen(cmd, "r")
  if file == nil:
    return false
  outs = file.readAll()
  let rv = pclose(file)
  if rv == -1:
    return false
  return rv == 0

# Run process, and write an arbitrary string into its standard input.
proc runProcessInto(cmd, ins: string): bool =
  let file = popen(cmd, "w")
  if file == nil:
    return false
  file.write(ins)
  let rv = pclose(file)
  if rv == -1:
    return false
  return rv == 0

proc toggleSource(pager: Pager) {.jsfunc.} =
  if cfCanReinterpret notin pager.container.flags:
    return
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
  if (let uqEditor = ChaPath(editor).unquote(""); uqEditor.isSome):
    if uqEditor.get in ["vi", "nvi", "vim", "nvim"]:
      editor = uqEditor.get & " +%d"
  var canpipe = true
  var s = unquoteCommand(editor, "", file, nil, canpipe, line)
  if s.len > 0 and canpipe:
    # %s not in command; add file name ourselves
    if s[^1] != ' ':
      s &= ' '
    s &= quoteFile(file, qsNormal)
  return s

proc openInEditor(pager: Pager; input: var string): bool =
  try:
    let tmpf = pager.getTempFile()
    if input != "":
      writeFile(tmpf, input)
    let cmd = pager.getEditorCommand(tmpf)
    if cmd == "":
      pager.alert("invalid external.editor command")
    elif pager.runCommand(cmd, suspend = true, wait = false, JS_UNDEFINED):
      if fileExists(tmpf):
        input = readFile(tmpf)
        removeFile(tmpf)
        return true
  except IOError:
    discard
  return false

proc windowChange(pager: Pager) =
  let oldAttrs = pager.attrs
  pager.term.windowChange()
  if pager.attrs == oldAttrs:
    #TODO maybe it's more efficient to let false positives through?
    return
  if pager.lineedit != nil:
    pager.lineedit.windowChange(pager.attrs)
  pager.clearDisplay()
  pager.clearStatus()
  for container in pager.containers:
    container.windowChange(pager.attrs)
  if pager.askprompt != "":
    pager.writeAskPrompt()
  pager.showAlerts()

# Apply siteconf settings to a request.
# Note that this may modify the URL passed.
proc applySiteconf(pager: Pager; url: URL; charsetOverride: Charset;
    loaderConfig: var LoaderClientConfig; ourl: var URL): BufferConfig =
  let host = url.host
  let ctx = pager.jsctx
  var res = BufferConfig(
    userstyle: pager.config.css.stylesheet,
    refererFrom: pager.config.buffer.referer_from,
    scripting: pager.config.buffer.scripting,
    charsets: pager.config.encoding.document_charset,
    images: pager.config.buffer.images,
    styling: pager.config.buffer.styling,
    autofocus: pager.config.buffer.autofocus,
    isdump: pager.config.start.headless,
    charsetOverride: charsetOverride,
    protocol: pager.config.protocol,
    metaRefresh: pager.config.buffer.meta_refresh
  )
  loaderConfig = LoaderClientConfig(
    defaultHeaders: newHeaders(pager.config.network.default_headers),
    cookiejar: nil,
    proxy: pager.config.network.proxy,
    filter: newURLFilter(
      scheme = some(url.scheme),
      allowschemes = @["data", "cache", "stream"],
      default = true
    ),
    insecureSSLNoVerify: false
  )
  let surl = $url
  for sc in pager.config.siteconf:
    if sc.url.isSome and not sc.url.get.match(surl):
      continue
    elif sc.host.isSome and not sc.host.get.match(host):
      continue
    if sc.rewrite_url.isSome:
      let fun = sc.rewrite_url.get
      var tmpUrl = newURL(url)
      var arg0 = ctx.toJS(tmpUrl)
      let ret = JS_Call(ctx, fun, JS_UNDEFINED, 1, arg0.toJSValueArray())
      if not JS_IsException(ret):
        # Warning: we must only print exceptions if the *call* returned one.
        # Conversion may simply error out because the function didn't return a
        # new URL, and that's fine.
        var nu: URL
        if ctx.fromJS(ret, nu).isSome and nu != nil:
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
      if sc.cookie.get:
        # host/url might have changed by now
        let jarid = sc.share_cookie_jar.get(url.host)
        if jarid notin pager.cookiejars:
          pager.cookiejars[jarid] = newCookieJar(url,
            sc.third_party_cookie)
        loaderConfig.cookieJar = pager.cookiejars[jarid]
      else:
        loaderConfig.cookieJar = nil # override
    if sc.scripting.isSome:
      res.scripting = sc.scripting.get
    if sc.referer_from.isSome:
      res.refererFrom = sc.referer_from.get
    if sc.document_charset.len > 0:
      res.charsets = sc.document_charset
    if sc.images.isSome:
      res.images = sc.images.get
    if sc.styling.isSome:
      res.styling = sc.styling.get
    if sc.stylesheet.isSome:
      res.userstyle &= "\n"
      res.userstyle &= sc.stylesheet.get
    if sc.proxy.isSome:
      loaderConfig.proxy = sc.proxy.get
    if sc.default_headers != nil:
      loaderConfig.defaultHeaders = newHeaders(sc.default_headers[])
    if sc.insecure_ssl_no_verify.isSome:
      loaderConfig.insecureSSLNoVerify = sc.insecure_ssl_no_verify.get
    if sc.autofocus.isSome:
      res.autofocus = sc.autofocus.get
    if sc.meta_refresh.isSome:
      res.metaRefresh = sc.meta_refresh.get
  loaderConfig.filter.allowschemes
    .add(pager.config.external.urimethodmap.imageProtos)
  if res.images:
    res.imageTypes = pager.config.external.mime_types.image
  return res

# Load request in a new buffer.
proc gotoURL(pager: Pager; request: Request; prevurl = none(URL);
    contentType = none(string); cs = CHARSET_UNKNOWN; replace: Container = nil;
    replaceBackup: Container = nil; redirectDepth = 0;
    referrer: Container = nil; save = false; url: URL = nil): Container =
  pager.navDirection = ndNext
  if referrer != nil and referrer.config.refererFrom:
    request.referrer = referrer.url
  var loaderConfig: LoaderClientConfig
  var bufferConfig: BufferConfig
  for i in 0 ..< pager.config.network.max_redirect:
    var ourl: URL = nil
    bufferConfig = pager.applySiteconf(request.url, cs, loaderConfig, ourl)
    if ourl == nil:
      break
    request.url = ourl
  if prevurl.isNone or
      not prevurl.get.equals(request.url, excludeHash = true) or
      request.url.hash == "" or request.httpMethod != hmGet or save:
    # Basically, we want to reload the page *only* when
    # a) we force a reload (by setting prevurl to none)
    # b) or the new URL isn't just the old URL + an anchor
    # I think this makes navigation pretty natural, or at least very close to
    # what other browsers do. Still, it would be nice if we got some visual
    # feedback on what is actually going to happen when typing a URL; TODO.
    if referrer != nil:
      loaderConfig.referrerPolicy = referrer.loaderConfig.referrerPolicy
    var flags = {cfCanReinterpret, cfUserRequested}
    if save:
      flags.incl(cfSave)
    let container = pager.newContainer(
      bufferConfig,
      loaderConfig,
      request,
      redirectDepth = redirectDepth,
      contentType = contentType,
      flags = flags,
      # override the URL so that the file name is correct for saveSource
      # (but NOT up above, so that rewrite-url works too)
      url = if url != nil: url else: request.url
    )
    if replace != nil:
      pager.replace(replace, container)
      if replaceBackup == nil:
        container.replace = replace
        replace.replaceRef = container
      else:
        container.replaceBackup = replaceBackup
        replaceBackup.replaceRef = container
      container.copyCursorPos(replace)
    else:
      pager.addContainer(container)
    inc pager.numload
    return container
  else:
    let container = pager.container
    let url = request.url
    let anchor = url.hash.substr(1)
    container.iface.gotoAnchor(anchor, false).then(proc(res: GotoAnchorResult) =
      if res.found:
        pager.dupeBuffer(container, url)
      else:
        pager.alert("Anchor " & url.hash & " not found")
    )
    return nil

proc omniRewrite(pager: Pager; s: string): string =
  for rule in pager.config.omnirule:
    if rule.match.match(s):
      let fun = rule.substitute_url.get
      let ctx = pager.jsctx
      var arg0 = ctx.toJS(s)
      let jsRet = JS_Call(ctx, fun, JS_UNDEFINED, 1, arg0.toJSValueArray())
      defer: JS_FreeValue(ctx, jsRet)
      defer: JS_FreeValue(ctx, arg0)
      var res: string
      if ctx.fromJS(jsRet, res).isSome:
        return res
      pager.alert("Error in substitution of " & $rule.match & " for " & s &
        ": " & ctx.getExceptionMsg())
  return s

# When the user has passed a partial URL as an argument, they might've meant
# either:
# * file://$PWD/<file>
# * https://<url>
# So we attempt to load both, and see what works.
proc loadURL(pager: Pager; url: string; ctype = none(string);
    cs = CHARSET_UNKNOWN) =
  let url0 = pager.omniRewrite(url)
  let url = expandPath(url0)
  if url.len == 0:
    return
  let firstparse = parseURL(url)
  if firstparse.isSome:
    let prev = if pager.container != nil:
      some(pager.container.url)
    else:
      none(URL)
    discard pager.gotoURL(newRequest(firstparse.get), prev, ctype, cs)
    return
  var urls: seq[URL] = @[]
  if pager.config.network.prepend_https and
      pager.config.network.prepend_scheme != "" and url[0] != '/':
    let pageurl = parseURL(pager.config.network.prepend_scheme & url)
    if pageurl.isSome: # attempt to load remote page
      urls.add(pageurl.get)
  let cdir = parseURL("file://" & percentEncode(getCurrentDir(),
    LocalPathPercentEncodeSet) & DirSep)
  let localurl = percentEncode(url, LocalPathPercentEncodeSet)
  let newurl = parseURL(localurl, cdir)
  if newurl.isSome:
    urls.add(newurl.get) # attempt to load local file
  if urls.len == 0:
    pager.alert("Invalid URL " & url)
  else:
    let container = pager.gotoURL(newRequest(urls.pop()), contentType = ctype,
      cs = cs)
    if container != nil:
      container.retry = urls

proc createPipe(pager: Pager): (PosixStream, PosixStream) =
  var pipefds {.noinit.}: array[2, cint]
  if pipe(pipefds) == -1:
    pager.alert("Failed to create pipe")
    return (nil, nil)
  return (newPosixStream(pipefds[0]), newPosixStream(pipefds[1]))

proc readPipe0(pager: Pager; contentType: string; cs: Charset;
    ps: PosixStream; url: URL; title: string; flags: set[ContainerFlag]):
    Container =
  var url = url
  pager.loader.passFd(url.pathname, ps.fd)
  ps.safeClose()
  var loaderConfig: LoaderClientConfig
  var ourl: URL
  let bufferConfig = pager.applySiteconf(url, cs, loaderConfig, ourl)
  return pager.newContainer(
    bufferConfig,
    loaderConfig,
    newRequest(url),
    title = title,
    flags = flags,
    contentType = some(contentType)
  )

proc readPipe(pager: Pager; contentType: string; cs: Charset; ps: PosixStream;
    title: string) =
  let url = newURL("stream:-").get
  let container = pager.readPipe0(contentType, cs, ps, url, title,
    {cfCanReinterpret, cfUserRequested})
  inc pager.numload
  pager.addContainer(container)

const ConsoleTitle = "Browser Console"

proc showConsole(pager: Pager) =
  let container = pager.consoleWrapper.container
  if pager.container != container:
    pager.consoleWrapper.prev = pager.container
    pager.setContainer(container)

proc hideConsole(pager: Pager) =
  if pager.container == pager.consoleWrapper.container:
    pager.setContainer(pager.consoleWrapper.prev)

proc clearConsole(pager: Pager) =
  let (pins, pouts) = pager.createPipe()
  if pins != nil:
    let url = newURL("stream:console").get
    let replacement = pager.readPipe0("text/plain", CHARSET_UNKNOWN, pins,
      url, ConsoleTitle, {})
    replacement.replace = pager.consoleWrapper.container
    pager.replace(pager.consoleWrapper.container, replacement)
    pager.consoleWrapper.container = replacement
    let console = pager.console
    console.err.sclose()
    console.err = pouts

proc addConsole(pager: Pager; interactive: bool): ConsoleWrapper =
  if interactive and pager.config.start.console_buffer:
    let (pins, pouts) = pager.createPipe()
    if pins != nil:
      let clearFun = proc() =
        pager.clearConsole()
      let showFun = proc() =
        pager.showConsole()
      let hideFun = proc() =
        pager.hideConsole()
      let url = newURL("stream:console").get
      let container = pager.readPipe0("text/plain", CHARSET_UNKNOWN, pins,
        url, ConsoleTitle, {})
      pouts.write("Type (M-c) console.hide() to return to buffer mode.\n")
      let console = newConsole(pouts, clearFun, showFun, hideFun)
      return ConsoleWrapper(console: console, container: container)
  let err = newPosixStream(STDERR_FILENO)
  return ConsoleWrapper(console: newConsole(err))

proc flushConsole*(pager: Pager) =
  if pager.console == nil:
    # hack for when client crashes before console has been initialized
    pager.consoleWrapper = ConsoleWrapper(
      console: newConsole(newDynFileStream(stderr))
    )
  pager.handleRead(pager.forkserver.estream.fd)

proc command(pager: Pager) {.jsfunc.} =
  pager.setLineEdit(lmCommand)

proc commandMode(pager: Pager; val: bool) {.jsfset.} =
  pager.commandMode = val
  if val:
    pager.command()

proc checkRegex(pager: Pager; regex: Result[Regex, string]): Opt[Regex] =
  if regex.isNone:
    pager.alert("Invalid regex: " & regex.error)
    return err()
  return ok(regex.get)

proc compileSearchRegex(pager: Pager; s: string): Result[Regex, string] =
  return compileSearchRegex(s, pager.config.search.ignore_case)

proc updateReadLineISearch(pager: Pager; linemode: LineMode) =
  let lineedit = pager.lineedit
  pager.isearchpromise = pager.isearchpromise.then(proc(): EmptyPromise =
    case lineedit.state
    of lesCancel:
      pager.iregex.err()
      pager.container.popCursorPos()
      pager.container.clearSearchHighlights()
      pager.container.redraw = true
      pager.isearchpromise = newResolvedPromise()
    of lesEdit:
      if lineedit.news != "":
        pager.iregex = pager.compileSearchRegex(lineedit.news)
      pager.container.popCursorPos(true)
      pager.container.pushCursorPos()
      if pager.iregex.isSome:
        pager.container.hlon = true
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
  )

proc saveTo(pager: Pager; data: LineDataDownload; path: string) =
  if pager.loader.redirectToFile(data.outputId, path):
    pager.alert("Saving file to " & path)
    pager.loader.resume(data.outputId)
    data.stream.sclose()
    pager.lineData = nil
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
        discard pager.gotoURL(newRequest(url), some(pager.container.url),
          replace = pager.container, referrer = pager.container)
        pager.lineData = nil
      of lmCommand:
        pager.scommand = lineedit.news
        if pager.commandMode:
          pager.command()
      of lmBuffer: pager.container.readSuccess(lineedit.news)
      of lmBufferFile:
        let ps = newPosixStream(lineedit.news, O_RDONLY, 0)
        if ps == nil:
          pager.alert("File not found")
          pager.container.readCanceled()
        else:
          var stats: Stat
          if fstat(ps.fd, stats) < 0 or S_ISDIR(stats.st_mode):
            pager.alert("Not a file: " & lineedit.news)
          else:
            let name = lineedit.news.afterLast('/')
            pager.container.readSuccess(name, ps.fd)
          ps.sclose()
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
        if fileExists(lineedit.news):
          pager.ask("Override file " & lineedit.news & "?").then(
            proc(x: bool) =
              if x:
                pager.saveTo(data, lineedit.news)
              else:
                pager.setLineEdit(lmDownload, lineedit.news)
          )
        else:
          pager.saveTo(data, lineedit.news)
      of lmMailcap:
        var mailcap = Mailcap.default
        let res = mailcap.parseMailcap(lineedit.news)
        let data = LineDataMailcap(pager.lineData)
        if res.isSome and mailcap.len == 1:
          let res = pager.runMailcap(data.container.url, data.ostream,
            data.response.outputId, data.contentType, mailcap[0])
          pager.connected2(data.container, res, data.response)
        else:
          if res.isNone:
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
    pager.clearLineEdit()

# Same as load(s + '\n')
proc loadSubmit(pager: Pager; s: string) {.jsfunc.} =
  pager.loadURL(s)

# Open a URL prompt and visit the specified URL.
proc load(pager: Pager; s = "") {.jsfunc.} =
  if s.len > 0 and s[^1] == '\n':
    if s.len > 1:
      pager.loadURL(s[0..^2])
  elif s == "":
    pager.setLineEdit(lmLocation, $pager.container.url)
  else:
    pager.setLineEdit(lmLocation, s)

# Go to specific URL (for JS)
type GotoURLDict = object of JSDict
  contentType {.jsdefault.}: Option[string]
  replace {.jsdefault.}: Container
  save {.jsdefault.}: bool

proc jsGotoURL(pager: Pager; v: JSValue; t = GotoURLDict()): JSResult[void]
    {.jsfunc: "gotoURL".} =
  var request: Request = nil
  var jsRequest: JSRequest = nil
  if pager.jsctx.fromJS(v, jsRequest).isSome:
    request = jsRequest.request
  else:
    var url: URL = nil
    if pager.jsctx.fromJS(v, url).isNone:
      var s: string
      ?pager.jsctx.fromJS(v, s)
      url = ?newURL(s)
    request = newRequest(url)
  discard pager.gotoURL(request, contentType = t.contentType,
    replace = t.replace, save = t.save)
  return ok()

# Reload the page in a new buffer, then kill the previous buffer.
proc reload(pager: Pager) {.jsfunc.} =
  discard pager.gotoURL(newRequest(pager.container.url), none(URL),
    pager.container.contentType, replace = pager.container)

type ExternDict = object of JSDict
  env {.jsdefault: JS_UNDEFINED.}: JSValue
  suspend {.jsdefault: true.}: bool
  wait {.jsdefault: false.}: bool

#TODO we should have versions with retval as int?
# or perhaps just an extern2 that can use JS readablestreams and returns
# retval, then deprecate the rest.
proc extern(pager: Pager; cmd: string;
    t = ExternDict(env: JS_UNDEFINED, suspend: true)): bool {.jsfunc.} =
  return pager.runCommand(cmd, t.suspend, t.wait, t.env)

proc externCapture(pager: Pager; cmd: string): Option[string] {.jsfunc.} =
  pager.setEnvVars(JS_UNDEFINED)
  var s: string
  if not runProcessCapture(cmd, s):
    return none(string)
  return some(s)

proc externInto(pager: Pager; cmd, ins: string): bool {.jsfunc.} =
  pager.setEnvVars(JS_UNDEFINED)
  return runProcessInto(cmd, ins)

proc externFilterSource(pager: Pager; cmd: string; c: Container = nil;
    contentType = none(string)) {.jsfunc.} =
  let fromc = if c != nil: c else: pager.container
  let fallback = pager.container.contentType.get("text/plain")
  let contentType = contentType.get(fallback)
  let container = pager.newContainerFrom(fromc, contentType)
  pager.addContainer(container)
  container.filter = BufferFilter(cmd: cmd)

proc execPipe(pager: Pager; cmd: string; ps, os, closeme: PosixStream): int =
  case (let pid = myFork(); pid)
  of -1:
    pager.alert("Failed to fork for " & cmd)
    os.sclose()
    return -1
  of 0:
    discard dup2(ps.fd, STDIN_FILENO)
    ps.sclose()
    discard dup2(os.fd, STDOUT_FILENO)
    os.sclose()
    closeStderr()
    closeme.sclose()
    for it in pager.loader.data:
      if it.stream.fd > 2:
        it.stream.sclose()
    myExec(cmd)
  else:
    os.sclose()
    return pid

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
  let pid = pager.execPipe(cmd, istream, pouts, pins)
  if pid == -1:
    return nil
  return pins

# Pipe input into the mailcap command, and discard its output.
# If needsterminal, leave stderr and stdout open and wait for the process.
proc runMailcapWritePipe(pager: Pager; stream: PosixStream;
    needsterminal: bool; cmd: string) =
  if needsterminal:
    pager.term.quit()
  let pid = myFork()
  if pid == -1:
    pager.alert("Error: failed to fork mailcap write process")
  elif pid == 0:
    # child process
    discard dup2(stream.fd, stdin.getFileHandle())
    stream.sclose()
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
      pager.term.restart()

proc writeToFile(istream: PosixStream; outpath: string): bool =
  let ps = newPosixStream(outpath, O_WRONLY or O_CREAT, 0o600)
  if ps == nil:
    return false
  var buffer {.noinit.}: array[4096, uint8]
  while true:
    let n = istream.recvData(buffer)
    if n == 0:
      break
    ps.sendDataLoop(buffer.toOpenArray(0, n - 1))
  ps.sclose()
  true

# Save input in a file, run the command, and redirect its output to a
# new buffer.
# needsterminal is ignored.
proc runMailcapReadFile(pager: Pager; stream: PosixStream;
    cmd, outpath: string; pins, pouts: PosixStream): int =
  case (let pid = myFork(); pid)
  of -1:
    pager.alert("Error: failed to fork mailcap read process")
    pouts.sclose()
    return pid
  of 0:
    # child process
    pins.sclose()
    discard dup2(pouts.fd, stdout.getFileHandle())
    pouts.sclose()
    closeStderr()
    if not stream.writeToFile(outpath):
      quit(1)
    stream.sclose()
    let ret = execCmd(cmd)
    discard tryRemoveFile(outpath)
    quit(ret)
  else: # parent
    pouts.sclose()
    return pid

# Save input in a file, run the command, and discard its output.
# If needsterminal, leave stderr and stdout open and wait for the process.
proc runMailcapWriteFile(pager: Pager; stream: PosixStream;
    needsterminal: bool; cmd, outpath: string) =
  if needsterminal:
    pager.term.quit()
    if not stream.writeToFile(outpath):
      pager.term.restart()
      pager.alert("Error: failed to write file for mailcap process")
    else:
      discard execCmd(cmd)
      discard tryRemoveFile(outpath)
      pager.term.restart()
  else:
    # don't block
    let pid = myFork()
    if pid == 0:
      # child process
      closeStdin()
      closeStdout()
      closeStderr()
      if not stream.writeToFile(outpath):
        quit(1)
      stream.sclose()
      let ret = execCmd(cmd)
      discard tryRemoveFile(outpath)
      quit(ret)
    # parent
    stream.sclose()

proc filterBuffer(pager: Pager; ps: PosixStream; cmd: string): PosixStream =
  pager.setEnvVars(JS_UNDEFINED)
  let (pins, pouts) = pager.createPipe()
  if pins == nil:
    return nil
  let pid = pager.execPipe(cmd, ps, pouts, pins)
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
  putEnv("MAILCAP_URL", $url)
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
    let pid = if canpipe:
      # Pipe input into the mailcap command, then read its output into a buffer.
      # needsterminal is ignored.
      pager.execPipe(cmd, stream, pouts, pins)
    else:
      pager.runMailcapReadFile(stream, cmd, outpath, pins, pouts)
    stream.sclose()
    if pid == -1:
      break needsConnect
    if not ishtml and mfAnsioutput in entry.flags:
      pins = pager.ansiDecode(url, ishtml, pins)
    delEnv("MAILCAP_URL")
    let url = parseURL("stream:" & $pid).get
    pager.loader.passFd(url.pathname, pins.fd)
    pins.safeClose()
    let response = pager.loader.doRequest(newRequest(url))
    var flags = {cmfConnect, cmfFound, cmfRedirected}
    if mfNeedsstyle in entry.flags or mfAnsioutput in entry.flags:
      # ansi always needs styles
      flags.incl(cmfNeedsstyle)
    if mfSaveoutput in entry.flags:
      flags.incl(cmfSaveoutput)
    if ishtml:
      flags.incl(cmfHTML)
    return MailcapResult(
      flags: flags,
      ostream: response.body,
      ostreamOutputId: response.outputId
    )
  delEnv("MAILCAP_URL")
  return MailcapResult(flags: {cmfFound})

proc redirectTo(pager: Pager; container: Container; request: Request) =
  let replaceBackup = if container.replaceBackup != nil:
    container.replaceBackup
  else:
    container.find(ndAny)
  let nc = pager.gotoURL(request, some(container.url), replace = container,
    replaceBackup = replaceBackup, redirectDepth = container.redirectDepth + 1,
    referrer = container)
  nc.loadinfo = "Redirecting to " & $request.url
  pager.onSetLoadInfo(nc)
  dec pager.numload

proc fail(pager: Pager; container: Container; errorMessage: string) =
  dec pager.numload
  pager.deleteContainer(container, container.find(ndAny))
  if container.retry.len > 0:
    discard pager.gotoURL(newRequest(container.retry.pop()),
      contentType = container.contentType)
  else:
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
  container.applyResponse(response, pager.config.external.mime_types)
  if container.redirectDepth < pager.config.network.max_redirect:
    if container.url.scheme == request.url.scheme or
        container.url.scheme == "cgi-bin" or
        container.url.scheme == "http" and request.url.scheme == "https" or
        container.url.scheme == "https" and request.url.scheme == "http":
      pager.redirectTo(container, request)
    #TODO perhaps make following behavior configurable?
    elif request.url.scheme == "cgi-bin":
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
  var buf = string(pager.config.external.download_dir)
  let pathname = container.url.pathname
  if buf.len == 0 or buf[^1] != '/':
    buf &= '/'
  if pathname[^1] == '/':
    buf &= "index.html"
  else:
    buf &= container.url.pathname.afterLast('/').percentDecode()
  pager.setLineEdit(lmDownload, buf)
  pager.lineData = LineDataDownload(outputId: response.outputId, stream: stream)
  pager.deleteContainer(container, container.find(ndAny))
  pager.refreshStatusMsg()
  dec pager.numload

proc connected2(pager: Pager; container: Container; res: MailcapResult;
    response: Response) =
  if cfSave in container.flags or cmfSaveoutput in res.flags:
    container.flags.incl(cfSave) # saveoutput doesn't include it before
    pager.askDownloadPath(container, res.ostream, response)
  elif cmfConnect in res.flags:
    if cmfHTML in res.flags:
      container.flags.incl(cfIsHTML)
    else:
      container.flags.excl(cfIsHTML)
    if cmfNeedsstyle in res.flags: # override
      container.config.styling = true
    # buffer now actually exists; create a process for it
    var attrs = pager.attrs
    # subtract status line height
    attrs.height -= 1
    attrs.heightPx -= attrs.ppl
    container.process = pager.forkserver.forkBuffer(
      container.config,
      container.url,
      attrs,
      cmfHTML in res.flags,
      container.charsetStack
    )
    pager.procmap.add(ProcMapItem(
      container: container,
      ostream: res.ostream,
      redirected: cmfRedirected in res.flags,
      ostreamOutputId: res.ostreamOutputId,
      istreamOutputId: response.outputId
    ))
    if container.replace != nil:
      pager.deleteContainer(container.replace, container.find(ndAny))
      container.replace = nil
  else:
    dec pager.numload
    pager.deleteContainer(container, container.find(ndAny))
    pager.refreshStatusMsg()

proc saveEntry(pager: Pager; entry: MailcapEntry) =
  if not pager.config.external.auto_mailcap.saveEntry(entry):
    pager.alert("Could not write to " & pager.config.external.auto_mailcap.path)

proc askMailcapMsg(pager: Pager; shortContentType: string; i: int; sx: var int):
    string =
  var msg = "Open " & shortContentType & " as (shift=always): (t)ext, (s)ave"
  if i != -1:
    msg &= ", (r)un \"" & pager.config.external.mailcap[i].cmd.strip() & '"'
  msg &= ", (e)dit entry, (C-c)ancel"
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
  msg = msg.substr(j)
  return msg

proc askMailcap(pager: Pager; container: Container; ostream: PosixStream;
    contentType: string; i: int; response: Response; sx: int) =
  var sx = sx
  let msg = pager.askMailcapMsg(container.contentType.get, i, sx)
  pager.askChar(msg).then(proc(s: string) =
    if s.len != 1:
      pager.askMailcap(container, ostream, contentType, i, response, sx)
      return
    let c = s[0]
    if c in {'\3', 'q'}:
      pager.alert("Canceled")
      ostream.sclose()
      pager.connected2(container, MailcapResult(), response)
    elif c == 'e':
      #TODO no idea how to implement save :/
      # probably it should run use a custom reader that runs through
      # auto.mailcap clearing any other entry. but maybe it's better to
      # add a full blown editor like w3m has at that point...
      var s = container.contentType.get & ';'
      if i != -1:
        s = $pager.config.external.mailcap[i]
      pager.setLineEdit(lmMailcap, s)
      pager.lineData = LineDataMailcap(
        container: container,
        ostream: ostream,
        contentType: contentType,
        i: i,
        response: response,
        sx: sx
      )
    elif c in {'t', 'T'}:
      pager.connected2(container, MailcapResult(
        flags: {cmfConnect},
        ostream: ostream
      ), response)
      if c == 'T':
        pager.saveEntry(MailcapEntry(
          t: container.contentType.get,
          cmd: "cat",
          flags: {mfCopiousoutput}
        ))
    elif c in {'s', 'S'}:
      container.flags.incl(cfSave)
      pager.connected2(container, MailcapResult(
        flags: {cmfConnect},
        ostream: ostream
      ), response)
      if c == 'S':
        pager.saveEntry(MailcapEntry(
          t: container.contentType.get,
          cmd: "cat",
          flags: {mfSaveoutput}
        ))
    elif i != -1 and c in {'r', 'R'}:
      let res = pager.runMailcap(container.url, ostream, response.outputId,
        contentType, pager.config.external.mailcap[i])
      pager.connected2(container, res, response)
      if c == 'R':
        pager.saveEntry(pager.config.external.mailcap[i])
    else:
      var sx = sx
      if c == 'h':
        dec sx
      if c == 'l':
        inc sx
      pager.askMailcap(container, ostream, contentType, i, response, max(sx, 0))
  )

proc connected(pager: Pager; container: Container; response: Response) =
  var istream = PosixStream(response.body)
  container.applyResponse(response, pager.config.external.mime_types)
  if response.status == 401: # unauthorized
    pager.setLineEdit(lmUsername, container.url.username)
    pager.lineData = LineDataAuth(url: newURL(container.url))
    istream.sclose()
    return
  # This forces client to ask for confirmation before quitting.
  # (It checks a flag on container, because console buffers must not affect this
  # variable.)
  if cfUserRequested in container.flags:
    pager.hasload = true
  var contentType = if "Content-Type" in response.headers:
    response.headers["Content-Type"]
  else:
    # both contentType and charset must be set by applyResponse.
    container.contentType.get & ";charset=" & $container.charset
  contentType = contentType.toValidUTF8()
  # contentType must exist, because we set it in applyResponse
  let shortContentType = container.contentType.get
  if container.filter != nil:
    istream = pager.filterBuffer(istream, container.filter.cmd)
  if shortContentType.equalsIgnoreCase("text/html"):
    pager.connected2(container, MailcapResult(
      flags: {cmfConnect, cmfHTML, cmfFound},
      ostream: istream
    ), response)
  elif shortContentType.equalsIgnoreCase("text/plain"):
    pager.connected2(container, MailcapResult(
      flags: {cmfConnect, cmfFound},
      ostream: istream
    ), response)
  else:
    let i = pager.config.external.auto_mailcap.entries
      .findMailcapEntry(contentType, "", container.url)
    if i != -1:
      let res = pager.runMailcap(container.url, istream, response.outputId,
        contentType, pager.config.external.auto_mailcap.entries[i])
      pager.connected2(container, res, response)
    else:
      let i = pager.config.external.mailcap.findMailcapEntry(contentType, "",
        container.url)
      if i == -1 and container.contentType.get.isTextType():
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
    var r = stream.initPacketReader()
    var res: int
    r.sread(res)
    if res == 0:
      r.sread(item.outputId)
      inc item.state
      container.loadinfo = "Connected to " & $container.url & ". Downloading..."
      pager.onSetLoadInfo(container)
      # continue
    else:
      var msg: string
      r.sread(msg)
      if msg == "":
        msg = getLoaderErrorMessage(res)
      pager.fail(container, msg)
      # done
      pager.loader.unset(item)
      pager.unregisterFd(int(item.stream.fd))
      stream.sclose()
  of ccsBeforeStatus:
    var r = stream.initPacketReader()
    r.sread(item.status)
    inc item.state
    # continue
  of ccsBeforeHeaders:
    let response = newResponse(item.res, container.request, stream,
      item.outputId, item.status)
    var r = stream.initPacketReader()
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
  pager.unregisterFd(int(item.stream.fd))
  item.stream.sclose()
  pager.loader.unset(item)

proc metaRefresh(pager: Pager; container: Container; n: int; url: URL) =
  let ctx = pager.jsctx
  let fun = ctx.newFunction(["url", "replace"],
    "pager.gotoURL(url, {replace: replace})")
  let args = [ctx.toJS(url), ctx.toJS(container)]
  discard pager.timeouts.setTimeout(ttTimeout, fun, int32(n), args)
  JS_FreeValue(ctx, fun)
  for arg in args:
    JS_FreeValue(ctx, arg)

const MenuMap = [
  ("Select text           (v)", "cmd.buffer.cursorToggleSelection(1)"),
  ("Copy selection        (y)", "cmd.buffer.copySelection(1)"),
  ("Previous buffer       (,)", "cmd.pager.prevBuffer(1)"),
  ("Next buffer           (.)", "cmd.pager.nextBuffer(1)"),
  ("Discard buffer        (D)", "cmd.pager.discardBuffer(1)"),
  ("─────────────────────────", ""),
  ("View image            (I)", "cmd.buffer.viewImage(1)"),
  ("Peek                  (u)", "cmd.pager.peekCursor(1)"),
  ("Copy link            (yu)", "cmd.pager.copyCursorLink(1)"),
  ("Copy image link      (yI)", "cmd.pager.copyCursorImage(1)"),
  ("Go to clipboard URL (M-p)", "cmd.pager.gotoClipboardURL(1)"),
  ("Reload                (U)", "cmd.pager.reloadBuffer(1)"),
  ("─────────────────────────", ""),
  ("Linkify URLs          (:)", "cmd.buffer.markURL(1)"),
  ("Save link          (sC-m)", "cmd.buffer.saveLink(1)"),
  ("View source           (\\)", "cmd.pager.toggleSource(1)"),
  ("Edit source          (sE)", "cmd.buffer.sourceEdit(1)"),
  ("Save source          (sS)", "cmd.buffer.saveSource(1)"),
  ("─────────────────────────", ""),
  ("Bookmark page       (M-a)", "cmd.pager.addBookmark(1)"),
  ("Open bookmarks      (M-b)", "cmd.pager.openBookmarks(1)"),
]

proc menuFinish(opaque: RootRef; select: Select; sr: SubmitResult) =
  let pager = Pager(opaque)
  case sr
  of srCancel: discard
  of srSubmit: pager.scommand = MenuMap[select.selected[0]][1]
  pager.menu = nil
  if pager.container != nil:
    pager.container.queueDraw()
  pager.draw()

proc openMenu(pager: Pager; x = -1; y = -1) {.jsfunc.} =
  let x = if x == -1 and pager.container != nil:
    pager.container.acursorx
  else:
    max(x, 0)
  let y = if y == -1 and pager.container != nil:
    pager.container.acursory
  else:
    max(y, 0)
  var options: seq[SelectOption] = @[]
  for (s, cmd) in MenuMap:
    options.add(SelectOption(s: s, nop: cmd == ""))
  pager.menu = newSelect(false, options, @[], x, y, pager.bufWidth,
    pager.bufHeight, menuFinish, pager)

proc handleEvent0(pager: Pager; container: Container; event: ContainerEvent):
    bool =
  case event.t
  of cetLoaded:
    dec pager.numload
  of cetReadLine:
    if container == pager.container:
      pager.setLineEdit(lmBuffer, event.value, hide = event.password,
        extraPrompt = event.prompt)
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
        not (container.url.scheme in ["http", "https"] and
          url.scheme in ["http", "https"]):
      pager.alert("Blocked cross-scheme POST: " & $url)
      return
    #TODO this is horrible UX, async actions shouldn't block input
    if pager.container != container or
        not event.save and not container.isHoverURL(url):
      pager.ask("Open pop-up? " & $url).then(proc(x: bool) =
        if x:
          discard pager.gotoURL(event.request, some(container.url),
            referrer = pager.container, save = event.save)
      )
    else:
      discard pager.gotoURL(event.request, some(container.url),
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
      pager.term.setTitle(container.getTitle())
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
      pager.deleteContainer(container, container.find(ndAny))
      pager.loader.unset(item)
      pager.unregisterFd(int(item.stream.fd))
      item.stream.sclose()
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
  return true

proc handleEvents(pager: Pager; container: Container) =
  while container.events.len > 0:
    let event = container.events.popFirst()
    if not pager.handleEvent0(container, event):
      break

proc handleEvents(pager: Pager) =
  if pager.container != nil:
    pager.handleEvents(pager.container)

proc handleEvent(pager: Pager; container: Container) =
  try:
    container.handleEvent()
    pager.handleEvents(container)
  except IOError:
    discard

proc runCommand(pager: Pager) =
  if pager.scommand != "":
    pager.command0(pager.scommand)
    let container = pager.consoleWrapper.container
    if container != nil:
      container.tailOnLoad = true
    pager.scommand = ""
    pager.handleEvents()

proc acceptBuffers(pager: Pager) =
  while pager.unreg.len > 0:
    let container = pager.unreg.pop()
    if container.iface != nil: # fully connected
      let stream = container.iface.stream
      let fd = int(stream.source.fd)
      pager.pollData.unregister(fd)
      pager.loader.unset(fd)
      stream.sclose()
    elif container.process != -1: # connecting to buffer process
      let i = pager.findProcMapItem(container.process)
      if i != -1:
        pager.procmap.del(i)
    elif (let item = pager.findConnectingContainer(container); item != nil):
      # connecting to URL
      let stream = item.stream
      pager.pollData.unregister(int(stream.fd))
      stream.sclose()
      pager.loader.unset(item)
  let registerFun = proc(fd: int) =
    pager.pollData.unregister(fd)
    pager.pollData.register(fd, POLLIN or POLLOUT)
  for item in pager.procmap:
    let container = item.container
    let stream = connectSocketStream(pager.config.external.sockdir,
      pager.loader.sockDirFd, container.process)
    # unlink here; on Linux we can't unlink from the buffer :/
    discard tryRemoveFile(getSocketPath(pager.config.external.sockdir,
      container.process))
    if stream == nil:
      pager.alert("Error: failed to set up buffer")
      continue
    let key = pager.addLoaderClient(container.process, container.loaderConfig,
      container.clonedFrom)
    let loader = pager.loader
    if item.istreamOutputId != -1: # new buffer
      if container.cacheId == -1:
        container.cacheId = loader.addCacheFile(item.istreamOutputId,
          loader.clientPid)
      if container.request.url.scheme == "cache":
        # loading from cache; now both the buffer and us hold a new reference
        # to the cached item, but it's only shared with the buffer. add a
        # pager ref too.
        loader.shareCachedItem(container.cacheId, loader.clientPid)
      let pid = container.process
      var outCacheId = container.cacheId
      if not item.redirected:
        loader.shareCachedItem(container.cacheId, pid)
        loader.resume(item.istreamOutputId)
      else:
        outCacheId = loader.addCacheFile(item.ostreamOutputId, pid)
        loader.resume([item.istreamOutputId, item.ostreamOutputId])
      stream.withPacketWriter w:
        w.swrite(key)
        w.swrite(outCacheId)
      # pass down ostream
      # must come after the previous block so the first packet is flushed
      stream.sendFd(item.ostream.fd)
      item.ostream.sclose()
      container.setStream(stream, registerFun)
    else: # cloned buffer
      stream.withPacketWriter w:
        w.swrite(key)
      # buffer is cloned, just share the parent's cached source
      loader.shareCachedItem(container.cacheId, container.process)
      # also add a reference here; it will be removed when the container is
      # deleted
      loader.shareCachedItem(container.cacheId, loader.clientPid)
      container.setCloneStream(stream, registerFun)
    let fd = int(stream.fd)
    pager.loader.put(ContainerData(stream: stream, container: container))
    pager.pollData.register(fd, POLLIN)
    # clear replacement references, because we can't fail to load this
    # buffer anymore
    container.replaceRef = nil
    container.replace = nil
    container.replaceBackup = nil
    pager.handleEvents(container)
  pager.procmap.setLen(0)

proc handleStderr(pager: Pager) =
  const BufferSize = 4096
  const prefix = "STDERR: "
  var buffer {.noinit.}: array[BufferSize, char]
  let estream = pager.forkserver.estream
  var hadlf = true
  while true:
    try:
      let n = estream.recvData(buffer)
      if n == 0:
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
          pager.console.err.write(prefix)
        if j - i > 0:
          pager.console.err.write(buffer.toOpenArray(i, j - 1))
        i = j
        hadlf = found
    except ErrorAgain:
      break
  if not hadlf:
    pager.console.err.write('\n')
  pager.console.err.sflush()

proc handleRead(pager: Pager; fd: int) =
  if pager.term.istream != nil and fd == pager.term.istream.fd:
    pager.input().then(proc() =
      pager.handleEvents()
    )
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

proc handleWrite(pager: Pager; fd: int) =
  let container = ContainerData(pager.loader.get(fd)).container
  if container.iface.stream.flushWrite():
    pager.pollData.unregister(fd)
    pager.pollData.register(fd, POLLIN)

proc handleError(pager: Pager; fd: int) =
  if pager.term.istream != nil and fd == pager.term.istream.fd:
    #TODO do something here...
    stderr.write("Error in tty\n")
    pager.quit(1)
  elif fd == pager.forkserver.estream.fd:
    #TODO do something here...
    stderr.write("Fork server crashed :(\n")
    pager.quit(1)
  elif (let data = pager.loader.get(fd); data != nil):
    if data of ConnectingContainer:
      pager.handleError(ConnectingContainer(data))
    elif data of ContainerData:
      let container = ContainerData(data).container
      if container != pager.consoleWrapper.container:
        pager.console.error("Error in buffer", $container.url)
      else:
        pager.consoleWrapper.container = nil
      pager.pollData.unregister(fd)
      pager.loader.unset(fd)
      if container.iface != nil:
        container.iface.stream.sclose()
        container.iface = nil
      doAssert pager.consoleWrapper.container != nil
      pager.showConsole()
    else:
      discard pager.loader.onError(fd) #TODO handle connection error?
  elif fd in pager.loader.unregistered:
    discard # already unregistered...
  else:
    doAssert pager.consoleWrapper.container != nil
    pager.showConsole()

let SIGWINCH {.importc, header: "<signal.h>", nodecl.}: cint

proc setupSigwinch(pager: Pager): PosixStream =
  var pipefd {.noinit.}: array[2, cint]
  doAssert pipe(pipefd) != -1
  let writer = newPosixStream(pipefd[1])
  writer.setBlocking(false)
  var gwriter {.global.}: PosixStream = nil
  gwriter = writer
  onSignal SIGWINCH:
    discard sig
    try:
      gwriter.sendDataLoop([0u8])
    except ErrorAgain:
      discard
  let reader = newPosixStream(pipefd[0])
  reader.setBlocking(false)
  return reader

proc inputLoop(pager: Pager) =
  pager.pollData.register(pager.term.istream.fd, POLLIN)
  let sigwinch = pager.setupSigwinch()
  pager.pollData.register(sigwinch.fd, POLLIN)
  while true:
    let timeout = pager.timeouts.sortAndGetTimeout()
    pager.pollData.poll(timeout)
    for event in pager.pollData.events:
      let efd = int(event.fd)
      if (event.revents and POLLIN) != 0:
        if event.fd == sigwinch.fd:
          sigwinch.drain()
          pager.windowChange()
        else:
          pager.handleRead(efd)
      if (event.revents and POLLOUT) != 0:
        pager.handleWrite(efd)
      if (event.revents and POLLERR) != 0 or (event.revents and POLLHUP) != 0:
        pager.handleError(efd)
    if pager.timeouts.run(pager.console.err):
      let container = pager.consoleWrapper.container
      if container != nil:
        container.tailOnLoad = true
    pager.runJSJobs()
    pager.loader.unregistered.setLen(0)
    pager.acceptBuffers()
    pager.runCommand()
    if pager.container == nil and pager.lineedit == nil:
      # No buffer to display.
      if not pager.hasload:
        # Failed to load every single URL the user passed us. We quit, and that
        # will dump all alerts to stderr.
        pager.quit(1)
      else:
        # At least one connection has succeeded, but we have nothing to display.
        # Normally, this means that the input stream has been redirected to a
        # file or to an external program. That also means we can't just exit
        # without potentially interrupting that stream.
        #TODO: a better UI would be querying the number of ongoing streams in
        # loader, and then asking for confirmation if there is at least one.
        pager.term.setCursor(0, pager.term.attrs.height - 1)
        pager.term.anyKey("Hit any key to quit Chawan:")
        pager.quit(0)
    pager.showAlerts()
    pager.draw()

func hasSelectFds(pager: Pager): bool =
  return not pager.timeouts.empty or pager.numload > 0 or
    pager.loader.mapFds > 0 or pager.procmap.len > 0

proc headlessLoop(pager: Pager) =
  while pager.hasSelectFds():
    let timeout = pager.timeouts.sortAndGetTimeout()
    pager.pollData.poll(timeout)
    for event in pager.pollData.events:
      let efd = int(event.fd)
      if (event.revents and POLLIN) != 0:
        pager.handleRead(efd)
      if (event.revents and POLLOUT) != 0:
        pager.handleWrite(efd)
      if (event.revents and POLLERR) != 0 or (event.revents and POLLHUP) != 0:
        pager.handleError(efd)
    discard pager.timeouts.run(pager.console.err)
    pager.runJSJobs()
    pager.loader.unregistered.setLen(0)
    pager.acceptBuffers()

proc dumpBuffers(pager: Pager) =
  pager.headlessLoop()
  for container in pager.containers:
    try:
      pager.drawBuffer(container, stdout)
      pager.handleEvents(container)
    except IOError:
      pager.console.error("Error in buffer", $container.url)
      # check for errors
      pager.handleRead(pager.forkserver.estream.fd)
      pager.quit(1)

proc addPagerModule*(ctx: JSContext) =
  ctx.registerType(Pager)
