import std/tables

import html/catom
import html/chadombuilder
import html/dom
import html/domexception
import html/event
import html/formdata
import html/jsencoding
import html/jsintl
import html/script
import html/xmlhttprequest
import io/console
import io/dynstream
import io/promise
import io/timeout
import monoucha/javascript
import monoucha/jserror
import monoucha/jspropenumlist
import monoucha/jstypes
import monoucha/quickjs
import monoucha/tojs
import server/headers
import server/loaderiface
import server/request
import server/response
import types/blob
import types/opt
import types/url
import types/winattrs
import utils/twtstr

# NavigatorID
proc appCodeName(navigator: var Navigator): string {.jsfget.} = "Mozilla"
proc appName(navigator: var Navigator): string {.jsfget.} = "Netscape"
proc appVersion(navigator: var Navigator): string {.jsfget.} = "5.0 (Windows)"
proc platform(navigator: var Navigator): string {.jsfget.} = "Win32"
proc product(navigator: var Navigator): string {.jsfget.} = "Gecko"
proc productSub(navigator: var Navigator): string {.jsfget.} = "20100101"
proc userAgent(ctx: JSContext; navigator: var Navigator): string {.jsfget.} =
  return ctx.getWindow().userAgent
proc vendor(navigator: var Navigator): string {.jsfget.} = ""
proc vendorSub(navigator: var Navigator): string {.jsfget.} = ""
proc taintEnabled(navigator: var Navigator): bool {.jsfunc.} = false
proc oscpu(navigator: var Navigator): string {.jsfget.} = "Windows NT 10.0"

# NavigatorLanguage
proc language(navigator: var Navigator): string {.jsfget.} = "en-US"
proc languages(navigator: var Navigator): seq[string] {.jsfget.} =
  @["en-US"] #TODO frozen array?

# NavigatorOnline
proc onLine(navigator: var Navigator): bool {.jsfget.} =
  true # at the very least, the terminal is on-line :)

#TODO NavigatorContentUtils

# NavigatorCookies
# "this website needs cookies to be enabled to function correctly"
# It's probably better to lie here.
proc cookieEnabled(navigator: var Navigator): bool {.jsfget.} = true

# NavigatorPlugins
proc pdfViewerEnabled(navigator: var Navigator): bool {.jsfget.} = false
proc javaEnabled(navigator: var Navigator): bool {.jsfunc.} = false
proc namedItem(pluginArray: var PluginArray): string {.jsfunc.} = ""
proc namedItem(mimeTypeArray: var MimeTypeArray): string {.jsfunc.} = ""
proc item(pluginArray: var PluginArray): JSValue {.jsfunc.} = JS_NULL
proc length(pluginArray: var PluginArray): uint32 {.jsfget.} = 0
proc item(mimeTypeArray: var MimeTypeArray): JSValue {.jsfunc.} = JS_NULL
proc length(mimeTypeArray: var MimeTypeArray): uint32 {.jsfget.} = 0
proc getter(pluginArray: var PluginArray; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  return JS_UNINITIALIZED
proc getter(mimeTypeArray: var MimeTypeArray; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  return JS_UNINITIALIZED

# Screen

# These are fingerprinting vectors; only app mode gets the real values.
proc availWidth(ctx: JSContext; screen: var Screen): int {.jsfget.} =
  let window = ctx.getWindow()
  if window.settings.scripting == smApp:
    return window.attrsp.widthPx
  return 80 * 9

proc availHeight(ctx: JSContext; screen: var Screen): int {.jsfget.} =
  let window = ctx.getWindow()
  if window.settings.scripting == smApp:
    return window.attrsp.heightPx
  return 24 * 18

proc width(ctx: JSContext; screen: var Screen): int {.jsfget.} =
  return ctx.availWidth(screen)

proc height(ctx: JSContext; screen: var Screen): int {.jsfget.} =
  return ctx.availHeight(screen)

proc colorDepth(screen: var Screen): int {.jsfget.} = 24
proc pixelDepth(screen: var Screen): int {.jsfget.} = screen.colorDepth

# History
func length(history: var History): uint32 {.jsfget.} = 1
func state(history: var History): JSValue {.jsfget.} = JS_NULL
func go(history: var History) {.jsfunc.} = discard
func back(history: var History) {.jsfunc.} = discard
func forward(history: var History) {.jsfunc.} = discard

# Storage
func find(this: Storage; key: string): int =
  for i in 0 ..< this.map.len:
    if this.map[i].key == key:
      return i
  return -1

func length(this: var Storage): uint32 {.jsfget.} =
  return uint32(this.map.len)

func key(ctx: JSContext; this: var Storage; i: uint32): JSValue {.jsfunc.} =
  if int(i) < this.map.len:
    return ctx.toJS(this.map[int(i)].value)
  return JS_NULL

func getItem(ctx: JSContext; this: var Storage; s: string): JSValue {.jsfunc.} =
  let i = this.find(s)
  if i != -1:
    return ctx.toJS(this.map[i].value)
  return JS_NULL

func setItem(this: var Storage; key, value: string):
    Err[DOMException] {.jsfunc.} =
  let i = this.find(key)
  if i != -1:
    this.map[i].value = value
  else:
    if this.map.len >= 64:
      return errDOMException("Quota exceeded", "QuotaExceededError")
    this.map.add((key, value))
  ok()

func removeItem(this: var Storage; key: string) {.jsfunc.} =
  let i = this.find(key)
  if i != -1:
    this.map.del(i)

func names(ctx: JSContext; this: var Storage): JSPropertyEnumList
    {.jspropnames.} =
  var list = newJSPropertyEnumList(ctx, uint32(this.map.len))
  for it in this.map:
    list.add(it.key)
  return list

func getter(ctx: JSContext; this: var Storage; s: string): JSValue
    {.jsgetownprop.} =
  return ctx.toJS(ctx.getItem(this, s)).uninitIfNull()

func setter(this: var Storage; k, v: string): Err[DOMException]
    {.jssetprop.} =
  return this.setItem(k, v)

func delete(this: var Storage; k: string): bool {.jsdelprop.} =
  this.removeItem(k)
  return true

proc addNavigatorModule*(ctx: JSContext) =
  ctx.registerType(Navigator)
  ctx.registerType(PluginArray)
  ctx.registerType(MimeTypeArray)
  ctx.registerType(Screen)
  ctx.registerType(History)
  ctx.registerType(Storage)

proc fetch(window: Window; input: JSValue;
    init = RequestInit(window: JS_UNDEFINED)): JSResult[FetchPromise]
    {.jsfunc.} =
  let input = ?newRequest(window.jsctx, input, init)
  #TODO cors requests?
  if input.request.url.scheme != "data" and
      not window.settings.origin.isSameOrigin(input.request.url.origin):
    let err = newFetchTypeError()
    return ok(newResolvedPromise(JSResult[Response].err(err)))
  return ok(window.loader.fetch(input.request))

proc setTimeout(window: Window; handler: JSValue; timeout = 0i32;
    args: varargs[JSValue]): int32 {.jsfunc.} =
  return window.timeouts.setTimeout(ttTimeout, handler, timeout, args)

proc setInterval(window: Window; handler: JSValue; interval = 0i32;
    args: varargs[JSValue]): int32 {.jsfunc.} =
  return window.timeouts.setTimeout(ttInterval, handler, interval, args)

proc clearTimeout(window: Window; id: int32) {.jsfunc.} =
  window.timeouts.clearTimeout(id)

proc clearInterval(window: Window; id: int32) {.jsfunc.} =
  window.clearTimeout(id)

func console(window: Window): Console {.jsfget.} =
  return window.internalConsole

proc screenX(window: Window): int {.jsfget.} = 0
proc screenY(window: Window): int {.jsfget.} = 0
proc screenLeft(window: Window): int {.jsfget.} = 0
proc screenTop(window: Window): int {.jsfget.} = 0

proc outerWidth(ctx: JSContext; window: Window): int {.jsfget.} =
  return ctx.availWidth(window.screen)

proc outerHeight(ctx: JSContext; window: Window): int {.jsfget.} =
  return ctx.availHeight(window.screen)

proc innerWidth(ctx: JSContext; window: Window): int {.jsfget.} =
  return ctx.availWidth(window.screen)

proc innerHeight(ctx: JSContext; window: Window): int {.jsfget.} =
  return ctx.availHeight(window.screen)

proc devicePixelRatio(window: Window): float64 {.jsfget.} = 1

proc setLocation(window: Window; s: string): Err[JSError]
    {.jsfset: "location".} =
  if window.document == nil:
    return errTypeError("document is null")
  return window.document.setLocation(s)

func getWindow(window: Window): Window {.jsuffget: "window".} =
  return window

#TODO [Replaceable]
func getSelf(window: Window): Window {.jsfget: "self".} =
  return window

#TODO [Replaceable]
func getFrames(window: Window): Window {.jsfget: "frames".} =
  return window

func getTop(window: Window): Window {.jsuffget: "top".} =
  return window #TODO frames?

#TODO [Replaceable]
func getParent(window: Window): Window {.jsfget: "parent".} =
  return window #TODO frames?

# See twtstr for the actual implementations.
proc atob(ctx: JSContext; window: Window; data: string): JSValue {.jsfunc.} =
  var s = ""
  if (let r = s.atob(data); r.isNone):
    let ex = newDOMException($r.error, "InvalidCharacterError")
    return JS_Throw(ctx, ctx.toJS(ex))
  return ctx.toJS(NarrowString(s))

proc btoa(ctx: JSContext; window: Window; data: JSValue): JSValue
    {.jsfunc.} =
  let data = JS_ToString(ctx, data)
  if JS_IsException(data):
    return JS_EXCEPTION
  doAssert JS_IsString(data)
  if JS_IsStringWideChar(data):
    JS_FreeValue(ctx, data)
    let ex = newDOMException("Invalid character in string",
      "InvalidCharacterError")
    return JS_Throw(ctx, ctx.toJS(ex))
  let len = int(JS_GetStringLength(data))
  if len == 0:
    JS_FreeValue(ctx, data)
    return ctx.toJS("")
  let buf = JS_GetNarrowStringBuffer(data)
  let res = btoa(buf.toOpenArray(0, len - 1))
  JS_FreeValue(ctx, data)
  return ctx.toJS(res)

proc alert(window: Window; s: string) {.jsfunc.} =
  window.console.error(s)

proc requestAnimationFrame(ctx: JSContext; window: Window; callback: JSValue):
    JSValue {.jsfunc.} =
  if not JS_IsFunction(ctx, callback):
    return JS_ThrowTypeError(ctx, "callback is not a function")
  let handler = ctx.newFunction(["callback"], """
callback(new Event("").timeStamp);
""")
  return ctx.toJS(window.setTimeout(handler, 0, callback))

proc getComputedStyle(window: Window; element: Element;
    pseudoElt = none(string)): CSSStyleDeclaration {.jsfunc.} =
  if window.settings.scripting == smApp:
    return element.getComputedStyle()
  # Maybe it works.
  return element.style

proc postMessage(window: Window) {.jsfunc.} =
  window.console.log("postMessage: Stub")

proc setOnLoad(ctx: JSContext; window: Window; val: JSValue)
    {.jsfset: "onload".} =
  if JS_IsFunction(ctx, val):
    let this = ctx.toJS(window)
    ctx.definePropertyC(this, "onload", JS_DupValue(ctx, val))
    #TODO I haven't checked but this might also be wrong
    doAssert ctx.addEventListener(window, window.toAtom(satLoad), val).isSome
    JS_FreeValue(ctx, this)

proc addWindowModule*(ctx: JSContext) =
  ctx.addEventModule()
  let eventTargetCID = ctx.getClass("EventTarget")
  ctx.registerType(Window, parent = eventTargetCID, asglobal = true)

proc addWindowModule2*(ctx: JSContext) =
  ctx.addEventModule()
  let eventTargetCID = ctx.getClass("EventTarget")
  ctx.registerType(Window, parent = eventTargetCID, asglobal = true,
    globalparent = true)

proc evalJSFree(opaque: RootRef; src, file: string) =
  let window = Window(opaque)
  let ret = window.jsctx.eval(src, file, JS_EVAL_TYPE_GLOBAL)
  if JS_IsException(ret):
    window.console.log("Exception in document", $window.document.url,
      window.jsctx.getExceptionMsg())
  else:
    JS_FreeValue(window.jsctx, ret)

proc addScripting*(window: Window) =
  let rt = newJSRuntime()
  let ctx = rt.newJSContext()
  window.jsrt = rt
  window.jsctx = ctx
  window.importMapsAllowed = true
  window.timeouts = newTimeoutState(ctx, evalJSFree, window)
  ctx.addWindowModule()
  ctx.setGlobal(window)
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

proc runJSJobs*(window: Window) =
  while true:
    let r = window.jsrt.runJSJobs()
    if r.isSome:
      break
    let ctx = r.error
    ctx.writeException(window.console.err)

proc newWindow*(scripting: ScriptingMode; images, styling, autofocus: bool;
    attrsp: ptr WindowAttributes; factory: CAtomFactory; loader: FileLoader;
    url: URL; urandom: PosixStream; imageTypes: Table[string, string];
    userAgent: string): Window =
  let err = newDynFileStream(stderr)
  let window = Window(
    attrsp: attrsp,
    internalConsole: newConsole(err),
    navigator: Navigator(),
    loader: loader,
    images: images,
    styling: styling,
    settings: EnvironmentSettings(
      scripting: scripting,
      origin: url.origin
    ),
    factory: factory,
    urandom: urandom,
    imageTypes: imageTypes,
    userAgent: userAgent,
    autofocus: autofocus
  )
  window.location = window.newLocation()
  if scripting != smFalse:
    window.addScripting()
  return window

# Forward declaration hack
fetchImpl = fetch
