{.push raises: [].}

import std/posix

import config/chapath
import config/config
import config/conftypes
import encoding/charset
import html/catom
import html/dom
import html/env
import html/script
import io/chafile
import io/dynstream
import io/poll
import js/fromjs
import js/jsbind
import js/jsopaque
import js/jsref
import js/jstypes
import js/jsutils
import js/quickjs
import js/tojs
import local/bufferiface
import local/clientutil
import local/lineedit
import local/pager
import local/select
import local/term
import server/forkserver
import server/loaderiface
import utils/chaos
import utils/opt
import utils/sandbox
import utils/strwidth
import utils/twtstr

const ChaVersionStr0 = "Chawan browser " & staticRead"res/version".strip()

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
  discard chaStderr.writeLine("cha: " & s)
  quit(1)

proc help(i: int) {.noreturn.} =
  let s = ChaVersionStr & """
Usage: cha [options] [URL(s) or file(s)...]
Options:
    --                         Interpret all following arguments as URLs
    -c, --css <stylesheet>     Pass stylesheet (e.g. -c 'a {color: blue}')
    -d, --dump                 Print page to stdout
    -h, --help                 Print this usage message
    -o, --opt <config>         Pass config options (e.g. -o buffer.images=true)
    -r, --run <script/file>    Run passed script or file
    -v, --version              Print version information
    -C, --config <file>        Override config path
    -I, --input-charset <enc>  Specify document charset
    -M, --monochrome           Set color-mode to 'monochrome'
    -O, --output-charset <enc> Specify display charset
    -T, --type <type>          Specify content mime type
    -V, --visual               Visual startup mode
"""
  if i == 0:
    discard chaStdout.write(s)
  else:
    discard chaStderr.write(s)
  quit(i)

proc version() =
  discard chaStdout.write(ChaVersionStrLong)
  quit(0)

type ParamParseContext = object
  i: int
  next: string
  configPath: string
  contentType: string
  charset: Charset
  visual: bool
  opts: seq[string]
  stylesheet: string
  ctx: JSContext
  pages: seq[JSValue]

proc addPage(ppc: var ParamParseContext; s: string): Opt[void] =
  let val = ppc.ctx.toJS(s)
  if JS_IsException(val.vc):
    return err()
  ppc.pages.add(val)
  ok()

proc addDefaultPages(ppc: var ParamParseContext; config: Config;
    history: var bool): Opt[void] =
  if ppc.visual:
    history = false
    return ppc.addPage(config{"visualHome"})
  if (let httpHome = getEnvEmpty("HTTP_HOME"); httpHome != ""):
    history = false
    return ppc.addPage(httpHome)
  if (let wwwHome = getEnvEmpty("WWW_HOME"); wwwHome != ""):
    history = false
    return ppc.addPage(wwwHome)
  ok()

when defined(nimUseStrictDefs):
  template myProveInit(x: untyped): untyped =
    {.warning[ProveInit]:off.}:
      x
else:
  template myProveInit(x: untyped): untyped =
    x

proc getNext(ppc: var ParamParseContext): string {.myProveInit.} =
  if ppc.next != "":
    return move(ppc.next)
  inc ppc.i
  if ppc.i < getArgvCount():
    return $getArgvCString(ppc.i)
  help(1)

proc parseConfig(ppc: var ParamParseContext) =
  ppc.configPath = ppc.getNext()
  if ppc.configPath == "":
    die("config override cannot be empty")

proc parseMonochrome(ppc: var ParamParseContext) =
  ppc.opts.add("display.color-mode = monochrome")

proc parseVisual(ppc: var ParamParseContext) =
  ppc.visual = true

proc parseContentType(ppc: var ParamParseContext) =
  ppc.contentType = ppc.getNext()

proc getCharset(ppc: var ParamParseContext): Charset =
  let s = ppc.getNext()
  let charset = getCharset(s)
  if charset == csUnknown:
    die("unknown charset " & s)
  return charset

proc parseInputCharset(ppc: var ParamParseContext) =
  ppc.charset = ppc.getCharset()

proc parseOutputCharset(ppc: var ParamParseContext) =
  ppc.opts.add("encoding.display-charset = '" & $ppc.getCharset() & "'")

proc parseDump(ppc: var ParamParseContext) =
  ppc.opts.add("start.headless = 'dump'")

proc parseCSS(ppc: var ParamParseContext) =
  ppc.stylesheet &= ppc.getNext()

proc parseOpt(ppc: var ParamParseContext) =
  ppc.opts.add(ppc.getNext())

proc parseRun(ppc: var ParamParseContext) =
  let script = dqEscape(ppc.getNext())
  ppc.opts.add("start.startup-script = \"\"\"" & script & "\"\"\"")
  ppc.opts.add("start.headless = true")

proc parse(ppc: var ParamParseContext): Opt[void] =
  var escapeAll = false
  while ppc.i < getArgvCount():
    let param = $getArgvCString(ppc.i)
    if escapeAll: # after --
      ?ppc.addPage(param)
      inc ppc.i
      continue
    if param.len <= 0:
      inc ppc.i
      continue
    if param[0] == '-':
      if param.len == 1:
        # If param == "-", i.e. it is a single dash, then ignore it.
        # (Some programs use single-dash to read from stdin, but we do that
        # automatically when stdin is not a tty. So ignoring it entirely
        # is probably for the best.)
        inc ppc.i
        continue
      if param[1] != '-':
        for j in 1 ..< param.len:
          const NeedsNextParam = {'C', 'I', 'O', 'T', 'c', 'o', 'r'}
          var hasNext = false
          if j < param.high and param[j] in NeedsNextParam:
            ppc.next = param.substr(j + 1)
            hasNext = true
          case param[j]
          of 'C': ppc.parseConfig()
          of 'I': ppc.parseInputCharset()
          of 'M': ppc.parseMonochrome()
          of 'O': ppc.parseOutputCharset()
          of 'T': ppc.parseContentType()
          of 'V': ppc.parseVisual()
          of 'c': ppc.parseCSS()
          of 'd': ppc.parseDump()
          of 'h': help(0)
          of 'o': ppc.parseOpt()
          of 'r': ppc.parseRun()
          of 'v': version()
          else: help(1)
          if hasNext:
            ppc.next = ""
            break
      else:
        case param
        of "--config": ppc.parseConfig()
        of "--input-charset": ppc.parseInputCharset()
        of "--monochrome": ppc.parseMonochrome()
        of "--output-charset": ppc.parseOutputCharset()
        of "--type": ppc.parseContentType()
        of "--visual": ppc.parseVisual()
        of "--css": ppc.parseCSS()
        of "--dump": ppc.parseDump()
        of "--help": help(0)
        of "--opt": ppc.parseOpt()
        of "--run": ppc.parseRun()
        of "--version": version()
        of "--": escapeAll = true
        else: help(1)
    else:
      ?ppc.addPage(param)
    inc ppc.i
  ok()

proc initConfig(ppc: ParamParseContext; warnings: var seq[string];
    ctx: JSContext): Result[Config, string] =
  var dir, dataDir: string
  let file = openConfig(dir, dataDir, ppc.configPath, warnings)
  if file.isErr and ppc.configPath.len > 0:
    # The user specified a non-existent config file.
    return err("failed to open config file " & ppc.configPath)
  if setEnv("CHA_DIR", dir).isErr or setEnv("CHA_DATA_DIR", dataDir).isErr:
    die("failed to set env vars")
  let config = newConfig(ctx, dir, dataDir)
  if config == nil:
    return err(ctx.getExceptionMsg())
  let cwd = chaos.getcwd()
  if file.isOk:
    let name = if ppc.configPath.len > 0:
      ppc.configPath.afterLast('/')
    else:
      "config.toml"
    ?config.parseConfig(config.dir, file.get, warnings, ctx, name)
  for opt in ppc.opts:
    ?config.parseConfig(cwd, opt, warnings, ctx, "<input>", laxnames = true)
  config{"userStyle"} &= ppc.stylesheet
  isCJKAmbiguous = config{"doubleWidthAmbiguous"}
  ok(config)

const libexecPath {.strdefine.} = "$CHA_BIN_DIR/../libexec/chawan"

proc forkForkServer(loaderSockVec: array[2, cint]; pagerPid: int;
    rt: JSRuntime): ForkServer {.myProveInit.} =
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
    discard setpgid(0, 0)
    closeStdin()
    closeStdout()
    westream.moveFd(STDERR_FILENO)
    discard close(pipeFdErr[0]) # close read
    discard close(sockVec[0])
    discard close(loaderSockVec[0])
    let controlStream = newPosixStream(sockVec[1])
    let loaderStream = newPosixStream(loaderSockVec[1])
    runForkServer(controlStream, loaderStream, pagerPid, rt)
    exitnow(1)
  else:
    discard close(sockVec[1])
    discard close(loaderSockVec[1])
    let stream = newPosixStream(sockVec[0])
    stream.setCloseOnExec()
    let estream = newPosixStream(pipeFdErr[0])
    estream.setCloseOnExec()
    estream.setBlocking(false)
    return ForkServer(
      pid: pid,
      stream: stream,
      estream: estream,
      westream: westream
    )

when defined(embedStartup):
  proc readStartupScriptROM(ctx: JSContext; src: string): JSValue =
    JS_ReadObject(ctx, cast[ptr uint8](unsafeAddr src[0]),
      csize_t(src.len), JS_READ_OBJ_BYTECODE or JS_READ_OBJ_ROM_DATA)

proc setupStartupScript(ctx: JSContext) =
  when defined(embedStartup):
    const src = staticRead".obj/init.jsb"
    let obj = ctx.readStartupScriptROM(src)
  else:
    let path = ChaPath("$CHA_LIBEXEC_DIR/init.jsb").unquoteGet()
    let ps = newPosixStream(path)
    if ps == nil:
      die("failed to read startup bytecode at " & path)
    let src = ps.readAll()
    let obj = JS_ReadObject(ctx, cast[ptr uint8](unsafeAddr src[0]),
      csize_t(src.len), JS_READ_OBJ_BYTECODE)
  if JS_IsException(obj.vc):
    die(ctx.getExceptionMsg())
  let ret = ctx.evalFunction(obj)
  if JS_IsException(ret):
    die(ctx.getExceptionMsg())

jsNamespaceDef(Client): # fake namespace
  proc readFile(ctx: JSContext; path: CStringNZ): JSValue {.jsstfunc.} =
    var s: string
    if chafile.readFile(path.p, s).isOk:
      return ctx.toJS(s)
    return JS_NULL

  proc writeFile(ctx: JSContext; path: CStringNZ; content: USVString;
      mode = cint(0o644)): JSValue {.jsstfunc.} =
    if chafile.writeFile(path.p, content.toOpenArray(), mode).isOk:
      return JS_UNDEFINED
    return JS_ThrowTypeError(ctx, "Could not write to file %s", path.p)

  proc getenv(ctx: JSContext; s: CStringNZ; fallback = JS_NULL.vc): JSValue
      {.jsstfunc.} =
    let env = getEnvCString(s.p)
    if env == nil:
      return JS_DupValue(ctx, fallback)
    return JS_NewString(ctx, env)

  proc setenv(ctx: JSContext; s: CStringNZ; val: JSValueConst): JSValue
      {.jsstfunc.} =
    if JS_IsNull(val):
      unsetEnvCString(s.p)
    else:
      var vals: CStringNZ
      ?ctx.fromJS(val, vals)
      if setEnvCString(s.p, vals.p).isErr:
        return JS_ThrowTypeError(ctx, "Failed to set environment variable")
    return JS_UNDEFINED

proc addJSModules(client: Window; ctx: JSContext): JSCode =
  ?ctx.setPropertyFunctionList(ctx.getOpaque().global, ClientDef.staticFuns)
  ?ctx.addUtilModule()
  ?ctx.addLineEditModule()
  ?ctx.addConfigModule()
  ?ctx.addPagerModule()
  ?ctx.addBufferInterfaceModule()
  ctx.addSelectModule()

proc main2(ctx: JSContext; loaderSockVec: array[2, cint]; pagerPid: int;
    forkserver: ForkServer): int =
  let urandom = newPosixStream("/dev/urandom", O_RDONLY, 0)
  if urandom == nil:
    die("failed to open /dev/urandom")
  urandom.setCloseOnExec()
  var ppc = ParamParseContext(ctx: ctx, i: 1)
  if ppc.parse().isErr:
    die(ctx.getExceptionMsg())
  let loaderControl = newPosixStream(loaderSockVec[0])
  loaderControl.setCloseOnExec()
  let loader = newFileLoader(pagerPid, loaderControl)
  let client = newClient(ctx, loader, urandom)
  if client == nil or client.addJSModules(ctx).isErr:
    die("failed to initialize JS: " & ctx.getExceptionMsg())
  var warnings = newSeq[string]()
  let cres = ppc.initConfig(warnings, ctx)
  if cres.isErr:
    die(cres.error)
  let config = cres.get
  if ctx.definePropertyConvert(ctx.getOpaque().global, jstConfig,
      config).isErr:
    die(ctx.getExceptionMsg())
  var history = true
  let ps = newPosixStream(STDIN_FILENO)
  if ppc.pages.len == 0 and ps.isatty():
    if ppc.addDefaultPages(config, history).isErr:
      die(ctx.getExceptionMsg())
  if ppc.pages.len == 0 and config{"headless"} != hmTrue:
    if ps.isatty():
      help(1)
  # make sure tmpdir exists
  let tmpdir = cstring(config{"tmpdir"})
  discard mkdir(tmpdir, 0o700)
  if chown(tmpdir, getuid(), getgid()) != 0:
    die("failed to set ownership of " & config{"tmpdir"})
  if chmod(tmpdir, 0o700) != 0:
    die("failed to set permissions of " & config{"tmpdir"})
  let loaderPid = forkserver.loadConfig(config, warnings)
  if loaderPid == -1:
    die("failed to fork loader process")
  onSignal SIGINT:
    discard sig
    if acceptSigint:
      sigintCaught = true
    else:
      discard chaos.signal(SIGINT, chaos.SIG_DFL);
      discard kill(getpid(), SIGINT)
  ctx.setupStartupScript()
  let pager = newPager(config, forkserver, ctx, warnings, loader, loaderPid,
    client.console, addr client.timeouts)
  if pager == nil:
    die("failed to create pager")
  client.settings.attrsp = addr pager.term.attrs
  client.settings.scriptAttrsp = addr pager.term.attrs
  return pager.run(ctx, ppc.pages, ppc.contentType, ppc.charset, history)

proc main() =
  let rt = newGlobalJSRuntime()
  initCAtomFactory()
  let binDir = chaos.getAppFilename().parentDir()
  if setEnv("CHA_BIN_DIR", binDir).isErr or
      setEnv("CHA_LIBEXEC_DIR", ChaPath(libexecPath).unquoteGet()).isErr:
    die("failed to set env vars")
  var loaderSockVec {.noinit.}: array[2, cint]
  if socketpair(AF_UNIX, SOCK_STREAM, IPPROTO_IP, loaderSockVec) != 0:
    die("failed to set up initial socket pair")
  let pagerPid = int(getpid())
  let forkserver = forkForkServer(loaderSockVec, pagerPid, rt)
  let ctx = rt.newJSContext()
  let code = main2(ctx, loaderSockVec, pagerPid, forkserver)
  ctx.free()
  rt.free()
  quit(code)

main()

{.pop.} # raises: []
