{.push raises: [].}

import std/options
import std/os
import std/posix

import chagashi/charset
import config/chapath
import config/config
import config/conftypes
import html/catom
import html/dom
import html/env
import html/script
import io/chafile
import io/console
import io/dynstream
import io/poll
import local/clientutil
import local/lineedit
import local/pager
import local/select
import local/term
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsutils
import monoucha/quickjs
import monoucha/tojs
import server/bufferiface
import server/forkserver
import server/loaderiface
import types/jsopt
import types/opt
import utils/myposix
import utils/sandbox
import utils/strwidth
import utils/twtstr

const ChaVersionStr0 = "Chawan browser v0.4-dev"

const ChaVersionStr = block:
  var s = ChaVersionStr0 & " ("
  when defined(debug):
    s &= "debug"
  else:
    s &= "release"
  s &= ", "
  s &= $SandboxMode
  s &= ", "
  s &= $PollMode
  s & ")\n"

const ChaVersionStrLong = block:
  var s = ChaVersionStr0 & " ("
  when defined(debug):
    s &= "debug"
  else:
    s &= "release"
  s &= ", "
  when SandboxMode == stNone:
    s &= "not sandboxed"
  else:
    s &= "sandboxed by " & $SandboxMode
  s &= ", "
  s &= "poll uses " & $PollMode
  s & ")\n"

proc die(s: string) {.noreturn.} =
  discard cast[ChaFile](stderr).writeLine("cha: " & s)
  quit(1)

proc help(i: int) {.noreturn.} =
  let s = ChaVersionStr & """
Usage: cha [options] [URL(s) or file(s)...]
Options:
    --                          Interpret all following arguments as URLs
    -c, --css <stylesheet>      Pass stylesheet (e.g. -c 'a{color: blue}')
    -d, --dump                  Print page to stdout
    -h, --help                  Print this usage message
    -o, --opt <config>          Pass config options (e.g. -o 'page.q="quit()"')
    -r, --run <script/file>     Run passed script or file
    -v, --version               Print version information
    -C, --config <file>         Override config path
    -I, --input-charset <enc>   Specify document charset
    -M, --monochrome            Set color-mode to 'monochrome'
    -O, --display-charset <enc> Specify display charset
    -T, --type <type>           Specify content mime type
    -V, --visual                Visual startup mode
"""
  if i == 0:
    discard cast[ChaFile](stdout).write(s)
  else:
    discard cast[ChaFile](stderr).write(s)
  quit(i)

proc version() =
  discard cast[ChaFile](stdout).write(ChaVersionStrLong)
  quit(0)

type ParamParseContext = object
  params: seq[string]
  i: int
  next: string
  configPath: Option[string]
  contentType: string
  charset: Charset
  visual: bool
  opts: seq[string]
  stylesheet: string
  jsctx: JSContext
  pages: seq[JSValue]

proc addPage(ctx: var ParamParseContext; s: string): Opt[void] =
  let val = ctx.jsctx.toJS(s)
  if JS_IsException(val):
    return err()
  ctx.pages.add(val)
  ok()

proc addDefaultPages(ctx: var ParamParseContext; config: Config;
    history: var bool): Opt[void] =
  if ctx.visual:
    history = false
    return ctx.addPage(config.start.visualHome)
  if (let httpHome = getEnv("HTTP_HOME"); httpHome != ""):
    history = false
    return ctx.addPage(httpHome)
  if (let wwwHome = getEnv("WWW_HOME"); wwwHome != ""):
    history = false
    return ctx.addPage(wwwHome)
  ok()

proc getNext(ctx: var ParamParseContext): string =
  if ctx.next != "":
    return ctx.next
  inc ctx.i
  if ctx.i < ctx.params.len:
    return ctx.params[ctx.i]
  help(1)

proc parseConfig(ctx: var ParamParseContext) =
  ctx.configPath = some(ctx.getNext())

proc parseMonochrome(ctx: var ParamParseContext) =
  ctx.opts.add("display.color-mode = monochrome")

proc parseVisual(ctx: var ParamParseContext) =
  ctx.visual = true

proc parseContentType(ctx: var ParamParseContext) =
  ctx.contentType = ctx.getNext()

proc getCharset(ctx: var ParamParseContext): Charset =
  let s = ctx.getNext()
  let charset = getCharset(s)
  if charset == CHARSET_UNKNOWN:
    die("unknown charset " & s)
  return charset

proc parseInputCharset(ctx: var ParamParseContext) =
  ctx.charset = ctx.getCharset()

proc parseOutputCharset(ctx: var ParamParseContext) =
  ctx.opts.add("encoding.display-charset = '" & $ctx.getCharset() & "'")

proc parseDump(ctx: var ParamParseContext) =
  ctx.opts.add("start.headless = 'dump'")

proc parseCSS(ctx: var ParamParseContext) =
  ctx.stylesheet &= ctx.getNext()

proc parseOpt(ctx: var ParamParseContext) =
  ctx.opts.add(ctx.getNext())

proc parseRun(ctx: var ParamParseContext) =
  let script = dqEscape(ctx.getNext())
  ctx.opts.add("start.startup-script = \"\"\"" & script & "\"\"\"")
  ctx.opts.add("start.headless = true")

proc parse(ctx: var ParamParseContext): Opt[void] =
  var escapeAll = false
  while ctx.i < ctx.params.len:
    let param = ctx.params[ctx.i]
    if escapeAll: # after --
      ?ctx.addPage(param)
      inc ctx.i
      continue
    if param.len <= 0:
      inc ctx.i
      continue
    if param[0] == '-':
      if param.len == 1:
        # If param == "-", i.e. it is a single dash, then ignore it.
        # (Some programs use single-dash to read from stdin, but we do that
        # automatically when stdin is not a tty. So ignoring it entirely
        # is probably for the best.)
        inc ctx.i
        continue
      if param[1] != '-':
        for j in 1 ..< param.len:
          const NeedsNextParam = {'C', 'I', 'O', 'T', 'c', 'o', 'r'}
          if j < param.high and param[j] in NeedsNextParam:
            ctx.next = param.substr(j + 1)
          case param[j]
          of 'C': ctx.parseConfig()
          of 'I': ctx.parseInputCharset()
          of 'M': ctx.parseMonochrome()
          of 'O': ctx.parseOutputCharset()
          of 'T': ctx.parseContentType()
          of 'V': ctx.parseVisual()
          of 'c': ctx.parseCSS()
          of 'd': ctx.parseDump()
          of 'h': help(0)
          of 'o': ctx.parseOpt()
          of 'r': ctx.parseRun()
          of 'v': version()
          else: help(1)
          if ctx.next != "":
            ctx.next = ""
            break
      else:
        case param
        of "--config": ctx.parseConfig()
        of "--input-charset": ctx.parseInputCharset()
        of "--monochrome": ctx.parseMonochrome()
        of "--output-charset": ctx.parseOutputCharset()
        of "--type": ctx.parseContentType()
        of "--visual": ctx.parseVisual()
        of "--css": ctx.parseCSS()
        of "--dump": ctx.parseDump()
        of "--help": help(0)
        of "--opt": ctx.parseOpt()
        of "--run": ctx.parseRun()
        of "--version": version()
        of "--": escapeAll = true
        else: help(1)
    else:
      ?ctx.addPage(param)
    inc ctx.i
  ok()

const defaultConfig = """
[external]
urimethodmap = [
	"~/.urimethodmap",
	"~/.w3m/urimethodmap",
	"/etc/urimethodmap",
	"/usr/local/etc/w3m/urimethodmap"
]

[siteconf.downloads]
url = 'about:downloads'
meta-refresh = "always"
"""

proc initConfig(ctx: ParamParseContext; warnings: var seq[string];
    jsctx: JSContext): Result[Config, string] =
  var dir, dataDir: string
  let ps = openConfig(dir, dataDir, ctx.configPath, warnings)
  if ps == nil and ctx.configPath.isSome:
    # The user specified a non-existent config file.
    return err("failed to open config file " & ctx.configPath.get)
  if twtstr.setEnv("CHA_DIR", dir).isErr or
      twtstr.setEnv("CHA_DATA_DIR", dataDir).isErr:
    die("failed to set env vars")
  let config = newConfig(jsctx, dir, dataDir)
  ?config.parseConfig("res", defaultConfig, warnings, jsctx, "default")
  let cwd = myposix.getcwd()
  if ps != nil:
    let src = ps.readAllOrMmap()
    ?config.parseConfig(config.dir, src.toOpenArray(), warnings, jsctx,
      "config.toml")
    deallocMem(src)
    ps.sclose()
  for opt in ctx.opts:
    ?config.parseConfig(cwd, opt, warnings, jsctx, "<input>", laxnames = true)
  string(config.buffer.userStyle) &= ctx.stylesheet
  isCJKAmbiguous = config.display.doubleWidthAmbiguous
  ok(config)

const libexecPath {.strdefine.} = "$CHA_BIN_DIR/../libexec/chawan"

proc forkForkServer(loaderSockVec: array[2, cint]): ForkServer =
  var sockVec {.noinit.}: array[2, cint] # stdin in forkserver
  var pipeFdErr {.noinit.}: array[2, cint] # stderr in forkserver
  if socketpair(AF_UNIX, SOCK_STREAM, IPPROTO_IP, sockVec) != 0:
    die("failed to open fork server i/o socket")
  if pipe(pipeFdErr) == -1:
    die("failed to open fork server error pipe")
  let westream = newPosixStream(pipeFdErr[1])
  let pid = fork()
  if pid == -1:
    die("failed to fork fork the server process")
  elif pid == 0:
    # child process
    discard setsid()
    closeStdin()
    closeStdout()
    westream.moveFd(STDERR_FILENO)
    discard close(pipeFdErr[0]) # close read
    discard close(sockVec[0])
    discard close(loaderSockVec[0])
    let controlStream = newSocketStream(sockVec[1])
    let loaderStream = newSocketStream(loaderSockVec[1])
    runForkServer(controlStream, loaderStream)
    exitnow(1)
  else:
    discard close(sockVec[1])
    discard close(loaderSockVec[1])
    let stream = newSocketStream(sockVec[0])
    stream.setCloseOnExec()
    let estream = newPosixStream(pipeFdErr[0])
    estream.setCloseOnExec()
    estream.setBlocking(false)
    return ForkServer(stream: stream, estream: estream, westream: westream)

proc setupStartupScript(ctx: JSContext; script: string) =
  let path = ChaPath("$CHA_LIBEXEC_DIR/" & script).unquoteGet()
  let ps = newPosixStream(path)
  if ps != nil:
    let s = ps.readAll()
    let obj = JS_ReadObject(ctx, cast[ptr uint8](cstring(s)), csize_t(s.len),
      JS_READ_OBJ_BYTECODE)
    if JS_IsException(obj):
      die(ctx.getExceptionMsg())
    let ret = JS_EvalFunction(ctx, obj)
    JS_FreeValue(ctx, obj)
    if JS_IsException(ret):
      die(ctx.getExceptionMsg())
    JS_FreeValue(ctx, ret)
  else:
    die("failed to read startup bytecode")

type Client = ref object of Window
  config: Config

proc config(this: Window): Config {.jsfget.} =
  return Client(this).config

proc readFile(ctx: JSContext; this: Window; path: string): JSValue
    {.jsfunc.} =
  var s: string
  if chafile.readFile(path, s).isOk:
    return ctx.toJS(s)
  return JS_NULL

proc writeFile(ctx: JSContext; this: Window; path, content: string;
    mode = cint(0o644)): JSValue {.jsfunc.} =
  if chafile.writeFile(path, content, mode).isOk:
    return JS_UNDEFINED
  return JS_ThrowTypeError(ctx, "Could not write to file %s", cstring(path))

proc getenv(ctx: JSContext; this: Window; s: string;
    fallback: JSValueConst = JS_NULL): JSValue {.jsfunc.} =
  let env = twtstr.getEnvCString(s)
  if env == nil:
    return JS_DupValue(ctx, fallback)
  return JS_NewString(ctx, env)

proc setenv(ctx: JSContext; this: Window; s: string; val: JSValueConst):
    JSValue {.jsfunc.} =
  if JS_IsNull(val):
    twtstr.unsetEnv(s)
  else:
    var vals: string
    ?ctx.fromJS(val, vals)
    if twtstr.setEnv(s, vals).isErr:
      return JS_ThrowTypeError(ctx, "Failed to set environment variable")
  return JS_UNDEFINED

let ClientJSFunctions {.global.} = [
  JS_CFUNC_DEF("getenv", 0, js_func_Window_getenv),
  JS_CFUNC_DEF("setenv", 0, js_func_Window_setenv),
  JS_CFUNC_DEF("readFile", 0, js_func_Window_readFile),
  JS_CFUNC_DEF("writeFile", 0, js_func_Window_writeFile),
  JS_CGETSET_DEF("config", js_get_Window_config, nil),
]

proc addJSModules(client: Client; ctx: JSContext): Opt[void] =
  ?ctx.addCommonModules(client)
  let global = JS_GetGlobalObject(ctx)
  if not ctx.setPropertyFunctionList(global, ClientJSFunctions):
    return err()
  JS_FreeValue(ctx, global)
  ?ctx.addUtilModule()
  ?ctx.addLineEditModule()
  ?ctx.addConfigModule()
  ?ctx.addPagerModule()
  ?ctx.addBufferInterfaceModule()
  ?ctx.addSelectModule()
  ok()

proc newClient(forkserver: ForkServer; loader: FileLoader; jsctx: JSContext;
    urandom: PosixStream): Client =
  let jsrt = JS_GetRuntime(jsctx)
  let console = newConsole(cast[ChaFile](stderr))
  let client = Client(
    jsrt: jsrt,
    jsctx: jsctx,
    loader: loader,
    crypto: Crypto(urandom: urandom),
    console: console,
    settings: EnvironmentSettings(
      scripting: smApp,
    ),
    dangerAlwaysSameOrigin: true
  )
  if client.addJSModules(jsctx).isOk:
    return client
  else:
    die("failed to initialize JS " & jsctx.getExceptionMsg())

proc main() =
  initCAtomFactory()
  let binDir = myposix.getAppFilename().untilLast('/')
  if twtstr.setEnv("CHA_BIN_DIR", binDir).isErr or
      twtstr.setEnv("CHA_LIBEXEC_DIR", ChaPath(libexecPath).unquoteGet()).isErr:
    die("failed to set env vars")
  var loaderSockVec {.noinit.}: array[2, cint]
  if socketpair(AF_UNIX, SOCK_STREAM, IPPROTO_IP, loaderSockVec) != 0:
    die("failed to set up initial socket pair")
  let forkserver = forkForkServer(loaderSockVec)
  let urandom = newPosixStream("/dev/urandom", O_RDONLY, 0)
  urandom.setCloseOnExec()
  let jsrt = newGlobalJSRuntime()
  let jsctx = jsrt.newJSContext()
  var ctx = ParamParseContext(jsctx: jsctx, params: commandLineParams(), i: 0)
  if ctx.parse().isErr:
    die(jsctx.getExceptionMsg())
  let clientPid = getCurrentProcessId()
  let loaderControl = newSocketStream(loaderSockVec[0])
  loaderControl.setCloseOnExec()
  let loader = newFileLoader(clientPid, loaderControl)
  let client = newClient(forkserver, loader, jsctx, urandom)
  var warnings = newSeq[string]()
  let cres = ctx.initConfig(warnings, jsctx)
  if cres.isErr:
    die(cres.error)
  let config = cres.get
  client.config = config
  var history = true
  let ps = newPosixStream(STDIN_FILENO)
  if ctx.pages.len == 0 and ps.isatty():
    if ctx.addDefaultPages(config, history).isErr:
      die(jsctx.getExceptionMsg())
  if ctx.pages.len == 0 and config.start.headless != hmTrue:
    if ps.isatty():
      help(1)
  # make sure tmpdir exists
  let tmpdir = cstring(config.external.tmpdir)
  discard mkdir(tmpdir, 0o700)
  if chown(tmpdir, getuid(), getgid()) != 0:
    die("failed to set ownership of " & $config.external.tmpdir)
  if chmod(tmpdir, 0o700) != 0:
    die("failed to set permissions of " & $config.external.tmpdir)
  let loaderPid = forkserver.loadConfig(config)
  if loaderPid == -1:
    die("failed to fork loader process")
  onSignal SIGINT:
    discard sig
    if acceptSigint:
      sigintCaught = true
    else:
      quit(1)
  jsctx.setupStartupScript("init.jsb")
  let pager = newPager(config, forkserver, jsctx, warnings, loader, loaderPid,
    client.console)
  client.timeouts = pager.timeouts
  client.settings.attrsp = addr pager.term.attrs
  client.settings.scriptAttrsp = addr pager.term.attrs
  pager.run(ctx.pages, ctx.contentType, ctx.charset, history)

main()

{.pop.} # raises: []
