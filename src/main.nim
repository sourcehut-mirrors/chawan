import version

import std/options
import std/os
import std/posix

import chagashi/charset
import config/chapath
import config/config
import io/dynstream
import local/client
import local/pager
import local/term
import monoucha/javascript
import server/forkserver
import types/opt
import utils/sandbox
import utils/strwidth
import utils/twtstr

const ChaVersionStr0 = "Chawan browser v0.1"

const ChaVersionStr = block:
  var s = ChaVersionStr0 & " ("
  when defined(debug):
    s &= "debug"
  else:
    s &= "release"
  s &= ", "
  when SandboxMode == stNone:
    s &= "not sandboxed"
  else:
    s &= "sandboxed"
  s &= ", "
  when TermcapFound:
    s &= "has termcap"
  else:
    s &= "no termcap"
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
  when TermcapFound:
    s &= "termcap library " & Termlib
  else:
    s &= "no termcap"
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
    stdout.write(s)
  else:
    stderr.write(s)
  quit(i)

proc version() =
  stdout.write(ChaVersionStrLong)
  quit(0)

type ParamParseContext = object
  params: seq[string]
  i: int
  next: string
  configPath: Option[string]
  contentType: Option[string]
  charset: Charset
  dump: bool
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
  ctx.contentType = some(ctx.getNext())

proc getCharset(ctx: var ParamParseContext): Charset =
  let s = ctx.getNext()
  let charset = getCharset(s)
  if charset == CHARSET_UNKNOWN:
    stderr.writeLine("Unknown charset " & s)
    quit(1)
  return charset

proc parseInputCharset(ctx: var ParamParseContext) =
  ctx.charset = ctx.getCharset()

proc parseOutputCharset(ctx: var ParamParseContext) =
  ctx.opts.add("encoding.display-charset = '" & $ctx.getCharset() & "'")

proc parseDump(ctx: var ParamParseContext) =
  ctx.dump = true

proc parseCSS(ctx: var ParamParseContext) =
  ctx.stylesheet &= ctx.getNext()

proc parseOpt(ctx: var ParamParseContext) =
  ctx.opts.add(ctx.getNext())

proc parseRun(ctx: var ParamParseContext) =
  let script = dqEscape(ctx.getNext())
  ctx.opts.add("start.startup-script = \"\"\"" & script & "\"\"\"")
  ctx.opts.add("start.headless = true")
  ctx.dump = true

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
    warnings: var seq[string]): Err[string] =
  let ps = openConfig(config.dir, ctx.configPath, warnings)
  if ps == nil and ctx.configPath.isSome:
    # The user specified a non-existent config file.
    return err("Failed to open config file " & ctx.configPath.get)
  putEnv("CHA_DIR", config.dir)
  ?config.parseConfig("res", defaultConfig, warnings)
  when defined(debug):
    if (let ps = newPosixStream(getCurrentDir() / "res/config.toml");
        ps != nil):
      ?config.parseConfig(getCurrentDir(), ps.recvAll(), warnings)
      ps.sclose()
  if ps != nil:
    let src = ps.recvAllOrMmap()
    ?config.parseConfig(config.dir, src.toOpenArray(), warnings)
    deallocMem(src)
    ps.sclose()
  for opt in ctx.opts:
    ?config.parseConfig(getCurrentDir(), opt, warnings, laxnames = true)
  config.css.stylesheet &= ctx.stylesheet
  ?config.initCommands()
  isCJKAmbiguous = config.display.double_width_ambiguous
  return ok()

const libexecPath {.strdefine.} = "$CHA_BIN_DIR/../libexec/chawan"

proc main() =
  putEnv("CHA_BIN_DIR", getAppFilename().untilLast('/'))
  putEnv("CHA_LIBEXEC_DIR", ChaPath(libexecPath).unquoteGet())
  var loaderSockVec {.noinit.}: array[2, cint]
  if socketpair(AF_UNIX, SOCK_STREAM, IPPROTO_IP, loaderSockVec) != 0:
    stderr.writeLine("Failed to set up initial socket pair")
    quit(1)
  let forkserver = newForkServer(loaderSockVec)
  let urandom = newPosixStream("/dev/urandom", O_RDONLY, 0)
  urandom.setCloseOnExec()
  var ctx = ParamParseContext(params: commandLineParams(), i: 0)
  ctx.parse()
  let jsrt = newJSRuntime()
  let jsctx = jsrt.newJSContext()
  var warnings = newSeq[string]()
  let config = Config(jsctx: jsctx)
  if (let res = ctx.initConfig(config, warnings); res.isNone):
    stderr.writeLine(res.error)
    quit(1)
  var history = true
  if ctx.pages.len == 0 and stdin.isatty():
    if ctx.visual:
      ctx.pages.add(config.start.visual_home)
      history = false
    elif (let httpHome = getEnv("HTTP_HOME"); httpHome != ""):
      ctx.pages.add(httpHome)
      history = false
    elif (let wwwHome = getEnv("WWW_HOME"); wwwHome != ""):
      ctx.pages.add(wwwHome)
      history = false
  if ctx.pages.len == 0 and not config.start.headless:
    if stdin.isatty():
      help(1)
  # make sure tmpdir exists
  discard mkdir(cstring(config.external.tmpdir), 0o700)
  let loaderPid = forkserver.loadConfig(config)
  setControlCHook(proc() {.noconv.} = quit(1))
  let client = newClient(config, forkserver, loaderPid, jsctx, warnings,
    urandom, newSocketStream(loaderSockVec[0]))
  try:
    client.pager.run(ctx.pages, ctx.contentType, ctx.charset, ctx.dump, history)
  except CatchableError:
    client.flushConsole()
    raise

main()
