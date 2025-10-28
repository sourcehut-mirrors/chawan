import std/os
import std/posix
import std/tables

import config/config
import config/conftypes
import html/catom
import html/chadombuilder
import html/dom
import html/domcanvas
import html/env
import html/formdata
import html/jsencoding
import html/jsintl
import html/script
import html/xmlhttprequest
import io/chafile
import io/console
import io/dynstream
import local/container
import local/lineedit
import local/pager
import local/select
import local/term
import monoucha/fromjs
import monoucha/javascript
import monoucha/jsopaque
import monoucha/quickjs
import monoucha/tojs
import server/forkserver
import server/headers
import server/loaderiface
import server/request
import server/response
import types/blob
import types/opt
import types/url
import utils/twtstr

type
  Client* = ref object of Window
    pager* {.jsget.}: Pager

proc config(client: Client): Config {.jsfget.} =
  return client.pager.config

proc console(client: Client): Console {.jsrfget.} =
  return client.pager.console

proc suspend(ctx: JSContext; client: Client): JSValue {.jsfunc.} =
  if client.pager.term.quit().isErr:
    return ctx.jsQuit(client.pager, 1)
  discard kill(0, cint(SIGTSTP))
  discard client.pager.term.restart() #TODO
  return JS_UNDEFINED

proc jsQuit(ctx: JSContext; client: Client; code = 0): JSValue
    {.jsfunc: "quit".} =
  ctx.jsQuit(client.pager, code)

proc feedNext(client: Client) {.jsfunc.} =
  client.pager.feednext = true

proc alert(client: Client; msg: string) {.jsfunc.} =
  client.pager.alert(msg)

proc consoleBuffer(client: Client): Container {.jsfget.} =
  return client.pager.pinned.console

proc readBlob(client: Client; path: string): WebFile {.jsfunc.} =
  let ps = newPosixStream(path, O_RDONLY, 0)
  if ps == nil:
    return nil
  let name = path.afterLast('/')
  return newWebFile(name, ps.fd)

proc readFile(ctx: JSContext; client: Client; path: string): JSValue
    {.jsfunc.} =
  var s: string
  if chafile.readFile(path, s).isOk:
    return ctx.toJS(s)
  return JS_NULL

proc writeFile(ctx: JSContext; client: Client; path, content: string): JSValue
    {.jsfunc.} =
  if chafile.writeFile(path, content, 0o644).isOk:
    return JS_UNDEFINED
  return JS_ThrowTypeError(ctx, "Could not write to file %s", cstring(path))

proc getenv(ctx: JSContext; client: Client; s: string;
    fallback: JSValueConst = JS_NULL): JSValue {.jsfunc.} =
  let env = twtstr.getEnvCString(s)
  if env == nil:
    return JS_DupValue(ctx, fallback)
  return JS_NewString(ctx, env)

proc setenv(ctx: JSContext; client: Client; s: string; val: JSValueConst):
    JSValue {.jsfunc.} =
  if JS_IsNull(val):
    twtstr.unsetEnv(s)
  else:
    var vals: string
    if ctx.fromJS(val, vals).isOk:
      if twtstr.setEnv(s, vals).isErr:
        return JS_ThrowTypeError(ctx, "Failed to set environment variable")
    else:
      return JS_EXCEPTION
  return JS_UNDEFINED

proc nimGCStats(client: Client): string {.jsfunc.} =
  return GC_getStatistics()

proc jsGCStats(client: Client): string {.jsfunc.} =
  return client.jsrt.getMemoryUsage()

proc nimCollect(client: Client) {.jsfunc.} =
  try:
    GC_fullCollect()
  except Exception:
    discard

proc jsCollect(client: Client) {.jsfunc.} =
  JS_RunGC(client.jsrt)

proc sleep(client: Client; millis: int) {.jsfunc.} =
  os.sleep(millis)

proc line(client: Client): LineEdit {.jsfget.} =
  return client.pager.lineedit

method isSameOrigin(client: Client; origin: Origin): bool =
  return true

proc addJSModules(client: Client; ctx: JSContext): JSClassID =
  let (windowCID, eventCID, eventTargetCID) = ctx.addWindowModule2()
  ctx.addConsoleModule()
  ctx.addNavigatorModule()
  ctx.addDOMModule(eventTargetCID)
  ctx.addCanvasModule()
  ctx.addURLModule()
  ctx.addHTMLModule()
  ctx.addIntlModule()
  ctx.addBlobModule()
  ctx.addFormDataModule()
  ctx.addXMLHttpRequestModule(eventCID, eventTargetCID)
  ctx.addHeadersModule()
  ctx.addRequestModule()
  ctx.addResponseModule()
  ctx.addEncodingModule()
  ctx.addLineEditModule()
  ctx.addConfigModule()
  ctx.addPagerModule()
  ctx.addContainerModule()
  ctx.addSelectModule()
  return windowCID

proc newClient*(config: Config; forkserver: ForkServer; loaderPid: int;
    jsctx: JSContext; warnings: seq[string]; urandom: PosixStream;
    loaderStream: SocketStream): Client =
  initCAtomFactory()
  let jsrt = JS_GetRuntime(jsctx)
  let clientPid = getCurrentProcessId()
  let loader = newFileLoader(clientPid, loaderStream)
  let pager = newPager(config, forkserver, jsctx, warnings, loader, loaderPid)
  let client = Client(
    jsrt: jsrt,
    jsctx: jsctx,
    loader: loader,
    crypto: Crypto(urandom: urandom),
    pager: pager,
    timeouts: pager.timeouts,
    settings: EnvironmentSettings(
      scripting: smApp,
      attrsp: addr pager.term.attrs,
      scriptAttrsp: addr pager.term.attrs
    )
  )
  jsctx.setGlobal(client)
  let global = JS_GetGlobalObject(jsctx)
  doAssert jsctx.definePropertyE(global, "cmd", config.cmd.jsObj) !=
    dprException
  JS_FreeValue(jsctx, global)
  config.cmd.jsObj = JS_NULL
  let windowCID = client.addJSModules(jsctx)
  jsctx.registerType(Client, asglobal = true, parent = windowCID)
  return client
