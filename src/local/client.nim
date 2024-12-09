import std/options
import std/os
import std/posix
import std/tables

import config/config
import html/catom
import html/chadombuilder
import html/dom
import html/domexception
import html/env
import html/formdata
import html/jsencoding
import html/jsintl
import html/xmlhttprequest
import io/console
import io/dynstream
import local/container
import local/lineedit
import local/pager
import local/select
import local/term
import monoucha/fromjs
import monoucha/javascript
import monoucha/jserror
import monoucha/jsopaque
import monoucha/quickjs
import monoucha/tojs
import server/forkserver
import server/headers
import server/loaderiface
import server/request
import server/response
import types/blob
import types/cookie
import types/opt
import types/url
import utils/twtstr

type
  Client* = ref object of Window
    pager* {.jsget.}: Pager

func config(client: Client): Config {.jsfget.} =
  return client.pager.config

func console(client: Client): Console {.jsfget.} =
  return client.pager.consoleWrapper.console

proc suspend(client: Client) {.jsfunc.} =
  client.pager.term.quit()
  discard kill(0, cint(SIGTSTP))
  client.pager.term.restart()

proc jsQuit(client: Client; code: uint32 = 0): JSValue {.jsfunc: "quit".} =
  client.pager.exitCode = int(code)
  let ctx = client.jsctx
  let ctor = ctx.getOpaque().errCtorRefs[jeInternalError]
  let err = JS_CallConstructor(ctx, ctor, 0, nil)
  JS_SetUncatchableError(ctx, err, true);
  return JS_Throw(ctx, err)

proc feedNext(client: Client) {.jsfunc.} =
  client.pager.feednext = true

proc alert(client: Client; msg: string) {.jsfunc.} =
  client.pager.alert(msg)

proc consoleBuffer(client: Client): Container {.jsfget.} =
  return client.pager.consoleWrapper.container

proc flushConsole*(client: Client) {.jsfunc.} =
  client.pager.flushConsole()

proc readBlob(client: Client; path: string): WebFile {.jsfunc.} =
  let ps = newPosixStream(path, O_RDONLY, 0)
  if ps == nil:
    return nil
  let name = path.afterLast('/')
  return newWebFile(name, ps.fd)

#TODO this is dumb
proc readFile(client: Client; path: string): string {.jsfunc.} =
  try:
    return readFile(path)
  except IOError:
    discard

#TODO ditto
proc writeFile(client: Client; path, content: string) {.jsfunc.} =
  writeFile(path, content)

proc nimGCStats(client: Client): string {.jsfunc.} =
  return GC_getStatistics()

proc jsGCStats(client: Client): string {.jsfunc.} =
  return client.jsrt.getMemoryUsage()

proc nimCollect(client: Client) {.jsfunc.} =
  GC_fullCollect()

proc jsCollect(client: Client) {.jsfunc.} =
  JS_RunGC(client.jsrt)

proc sleep(client: Client; millis: int) {.jsfunc.} =
  os.sleep(millis)

func line(client: Client): LineEdit {.jsfget.} =
  return client.pager.lineedit

proc addJSModules(client: Client; ctx: JSContext) =
  ctx.addWindowModule2()
  ctx.addDOMExceptionModule()
  ctx.addConsoleModule()
  ctx.addNavigatorModule()
  ctx.addDOMModule()
  ctx.addURLModule()
  ctx.addHTMLModule()
  ctx.addIntlModule()
  ctx.addBlobModule()
  ctx.addFormDataModule()
  ctx.addXMLHttpRequestModule()
  ctx.addHeadersModule()
  ctx.addRequestModule()
  ctx.addResponseModule()
  ctx.addEncodingModule()
  ctx.addLineEditModule()
  ctx.addConfigModule()
  ctx.addPagerModule()
  ctx.addContainerModule()
  ctx.addSelectModule()
  ctx.addCookieModule()

func getClient(client: Client): Client {.jsfget: "client".} =
  return client

proc newClient*(config: Config; forkserver: ForkServer; loaderPid: int;
    jsctx: JSContext; warnings: seq[string]; urandom: PosixStream): Client =
  let jsrt = JS_GetRuntime(jsctx)
  let loader = FileLoader(process: loaderPid, clientPid: getCurrentProcessId())
  loader.setSocketDir(config.external.sockdir)
  let client = Client(
    jsrt: jsrt,
    jsctx: jsctx,
    factory: newCAtomFactory(),
    loader: loader,
    urandom: urandom,
    pager: newPager(config, forkserver, jsctx, warnings, urandom, loader)
  )
  client.timeouts = client.pager.timeouts
  let global = JS_GetGlobalObject(jsctx)
  jsctx.setGlobal(client)
  jsctx.definePropertyE(global, "cmd", config.cmd.jsObj)
  JS_FreeValue(jsctx, global)
  config.cmd.jsObj = JS_NULL
  client.addJSModules(jsctx)
  let windowCID = jsctx.getClass("Window")
  jsctx.registerType(Client, asglobal = true, parent = windowCID)
  return client
