import version

import std/options
import std/os
import std/posix

import bindings/termcap
import chagashi/charset
import config/chapath
import config/config
import local/client
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

proc help(i: int) =
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
  configPath: Option[string]
  contentType: Option[string]
  charset: Charset
  dump: bool
  visual: bool
  opts: seq[string]
  stylesheet: string
  pages: seq[string]

proc getnext(ctx: var ParamParseContext): string =
  inc ctx.i
  if ctx.i < ctx.params.len:
    return ctx.params[ctx.i]
  help(1)

proc parseConfig(ctx: var ParamParseContext) =
  ctx.configPath = some(ctx.getnext())

proc parseMonochrome(ctx: var ParamParseContext) =
  ctx.opts.add("display.color-mode = monochrome")

proc parseVisual(ctx: var ParamParseContext) =
  ctx.visual = true

proc parseContentType(ctx: var ParamParseContext) =
  ctx.contentType = some(ctx.getnext())

proc getCharset(ctx: var ParamParseContext): Charset =
  let s = ctx.getnext()
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
  ctx.stylesheet &= ctx.getnext()

proc parseOpt(ctx: var ParamParseContext) =
  ctx.opts.add(ctx.getnext())

proc parseRun(ctx: var ParamParseContext) =
  let script = dqEscape(ctx.getnext())
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
          if j != param.high and param[j] in NeedsNextParam:
            # expecting next parameter, but not the last char...
            help(1)
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

proc main() =
  putEnv("CHA_LIBEXEC_DIR", ChaPath"${%CHA_LIBEXEC_DIR}".unquoteGet())
  let forkserver = newForkServer()
  var ctx = ParamParseContext(params: commandLineParams(), i: 0)
  ctx.parse()
  let jsrt = newJSRuntime()
  let jsctx = jsrt.newJSContext()
  var warnings = newSeq[string]()
  let (config, res) = readConfig(ctx.configPath, jsctx)
  if not res.success:
    stderr.writeLine(res.errorMsg)
    quit(1)
  warnings.add(res.warnings)
  for opt in ctx.opts:
    let res = config.parseConfig(getCurrentDir(), opt, laxnames = true,
      setdir = false)
    if not res.success:
      stderr.writeLine(res.errorMsg)
      quit(1)
    warnings.add(res.warnings)
  config.css.stylesheet &= ctx.stylesheet
  block commands:
    let res = config.initCommands()
    if res.isNone:
      stderr.writeLine("Error parsing commands: " & res.error)
      quit(1)
  isCJKAmbiguous = config.display.double_width_ambiguous
  if ctx.pages.len == 0 and stdin.isatty():
    if ctx.visual:
      ctx.pages.add(config.start.visual_home)
    elif (let httpHome = getEnv("HTTP_HOME"); httpHome != ""):
      ctx.pages.add(httpHome)
    elif (let wwwHome = getEnv("WWW_HOME"); wwwHome != ""):
      ctx.pages.add(wwwHome)
  if ctx.pages.len == 0 and not config.start.headless:
    if stdin.isatty():
      help(1)
  # make sure tmpdir & sockdir both exist; if we do this later, then
  # forkserver may try to open an empty dir
  discard mkdir(cstring(config.external.tmpdir), 0o700)
  discard mkdir(cstring(config.external.sockdir), 0o700)
  let loaderPid = forkserver.loadConfig(config)
  let client = newClient(config, forkserver, loaderPid, jsctx, warnings)
  try:
    client.launchClient(ctx.pages, ctx.contentType, ctx.charset, ctx.dump)
  except CatchableError:
    client.flushConsole()
    raise

main()
