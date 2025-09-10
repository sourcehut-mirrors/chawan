{.push raises: [].}

import std/options
import std/os
import std/posix
import std/tables

import chagashi/charset
import config/chapath
import config/config
import config/conftypes
import io/chafile
import io/dynstream
import io/poll
import local/client
import local/pager
import local/term
import monoucha/javascript
import server/forkserver
import types/opt
import utils/myposix
import utils/sandbox
import utils/strwidth
import utils/twtstr

const ChaVersionStr0 = "Chawan browser v0.3"

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
  pages: seq[string]

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

proc parse(ctx: var ParamParseContext) =
  var escapeAll = false
  while ctx.i < ctx.params.len:
    let param = ctx.params[ctx.i]
    if escapeAll: # after --
      ctx.pages.add(param)
      inc ctx.i
      continue
    if param.len == 0:
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
      ctx.pages.add(param)
    inc ctx.i

const defaultConfig = staticRead"res/config.toml"

proc initConfig(ctx: ParamParseContext; config: Config;
    warnings: var seq[string]; jsctx: JSContext): Err[string] =
  let ps = openConfig(config.dir, ctx.configPath, warnings)
  if ps == nil and ctx.configPath.isSome:
    # The user specified a non-existent config file.
    return err("failed to open config file " & ctx.configPath.get)
  if twtstr.setEnv("CHA_DIR", config.dir).isErr:
    die("failed to set env vars")
  ?config.parseConfig("res", defaultConfig, warnings, jsctx, "res/config.toml")
  let cwd = myposix.getcwd()
  when defined(debug):
    if (let ps = newPosixStream(cwd / "res/config.toml"); ps != nil):
      ?config.parseConfig(cwd, ps.readAll(), warnings, jsctx, "res/config.toml")
      ps.sclose()
  if ps != nil:
    let src = ps.readAllOrMmap()
    ?config.parseConfig(config.dir, src.toOpenArray(), warnings, jsctx,
      "config.toml")
    deallocMem(src)
    ps.sclose()
  for opt in ctx.opts:
    ?config.parseConfig(cwd, opt, warnings, jsctx, "<input>", laxnames = true)
  ?jsctx.initCommands(config)
  string(config.buffer.userStyle) &= ctx.stylesheet
  isCJKAmbiguous = config.display.doubleWidthAmbiguous
  return ok()

const libexecPath {.strdefine.} = "$CHA_BIN_DIR/../libexec/chawan"

proc main() =
  let binDir = myposix.getAppFilename().untilLast('/')
  if twtstr.setEnv("CHA_BIN_DIR", binDir).isErr or
      twtstr.setEnv("CHA_LIBEXEC_DIR", ChaPath(libexecPath).unquoteGet()).isErr:
    die("failed to set env vars")
  var loaderSockVec {.noinit.}: array[2, cint]
  if socketpair(AF_UNIX, SOCK_STREAM, IPPROTO_IP, loaderSockVec) != 0:
    die("failed to set up initial socket pair")
  let forkserver = newForkServer(loaderSockVec)
  let urandom = newPosixStream("/dev/urandom", O_RDONLY, 0)
  urandom.setCloseOnExec()
  var ctx = ParamParseContext(params: commandLineParams(), i: 0)
  ctx.parse()
  let jsrt = newJSRuntime()
  let jsctx = jsrt.newJSContext()
  var warnings = newSeq[string]()
  let config = Config(arraySeen: newTable[string, int]())
  if (let res = ctx.initConfig(config, warnings, jsctx); res.isErr):
    die(res.error)
  var history = true
  let ps = newPosixStream(STDIN_FILENO)
  if ctx.pages.len == 0 and ps.isatty():
    if ctx.visual:
      ctx.pages.add(config.start.visualHome)
      history = false
    elif (let httpHome = getEnv("HTTP_HOME"); httpHome != ""):
      ctx.pages.add(httpHome)
      history = false
    elif (let wwwHome = getEnv("WWW_HOME"); wwwHome != ""):
      ctx.pages.add(wwwHome)
      history = false
  if ctx.pages.len == 0 and config.start.headless != hmTrue:
    if ps.isatty():
      help(1)
  # make sure tmpdir exists
  let tmpdir = cstring(config.external.tmpdir)
  discard mkdir(tmpdir, 0o700)
  if chown(tmpdir, getuid(), getgid()) != 0:
    die("failed to set ownership of " & config.external.tmpdir)
  if chmod(tmpdir, 0o700) != 0:
    die("failed to set permissions of " & config.external.tmpdir)
  let loaderPid = forkserver.loadConfig(config)
  if loaderPid == -1:
    die("failed to fork loader process")
  onSignal SIGINT:
    discard sig
    if acceptSigint:
      sigintCaught = true
    else:
      quit(1)
  let loaderControl = newSocketStream(loaderSockVec[0])
  loaderControl.setCloseOnExec()
  let client = newClient(config, forkserver, loaderPid, jsctx, warnings,
    urandom, loaderControl)
  client.pager.run(ctx.pages, ctx.contentType, ctx.charset, history)

main()

{.pop.} # raises: []
