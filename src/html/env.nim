import std/strutils
import std/tables

import css/cssparser
import css/mediaquery
import html/catom
import html/chadombuilder
import html/dom
import html/domexception
import html/event
import html/formdata
import html/jsencoding
import html/jsintl
import html/performance
import html/script
import html/xmlhttprequest
import io/console
import io/dynstream
import io/promise
import io/timeout
import monoucha/fromjs
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

proc setLocation(window: Window; s: string): Err[JSError]

# History
func length(history: var History): uint32 {.jsfget.} = 1
func state(history: var History): JSValue {.jsfget.} = JS_NULL
func go(history: var History) {.jsfunc.} = discard
func back(history: var History) {.jsfunc.} = discard
func forward(history: var History) {.jsfunc.} = discard
proc pushState(ctx: JSContext; history: var History;
    data, unused: JSValueConst; s: string): JSResult[void] {.jsfunc.} =
  let window = ctx.getWindow()
  if window != nil:
    return window.setLocation(s)
  return ok()

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

# Crypto
proc getRandomValues(ctx: JSContext; crypto: var Crypto; array: JSValueConst):
    JSValue {.jsfunc.} =
  var view: JSArrayBufferView
  if ctx.fromJS(array, view).isNone:
    return JS_EXCEPTION
  if view.t < 0 or view.t > cint(JS_TYPED_ARRAY_BIG_UINT64):
    return JS_ThrowDOMException(ctx, "Wrong typed array type",
      "TypeMismatchError")
  if view.abuf.len > 65536:
    return JS_ThrowDOMException(ctx, "Too large array", "QuotaExceededError")
  doAssert crypto.urandom.readDataLoop(view.abuf.p, int(view.abuf.len))
  return JS_DupValue(ctx, array)

proc addNavigatorModule*(ctx: JSContext) =
  ctx.registerType(Navigator)
  ctx.registerType(PluginArray)
  ctx.registerType(MimeTypeArray)
  ctx.registerType(Screen)
  ctx.registerType(History)
  ctx.registerType(Storage)
  ctx.registerType(Crypto)

method isSameOrigin*(window: Window; origin: Origin): bool {.base.} =
  return window.settings.origin.isSameOrigin(origin)

proc fetch(window: Window; input: JSValueConst;
    init = RequestInit(window: JS_UNDEFINED)): JSResult[FetchPromise]
    {.jsfunc.} =
  let input = ?newRequest(window.jsctx, input, init)
  #TODO cors requests?
  if input.request.url.scheme != "data" and
      not window.isSameOrigin(input.request.url.origin):
    let err = newFetchTypeError()
    return ok(newResolvedPromise(JSResult[Response].err(err)))
  return ok(window.loader.fetch(input.request))

proc setTimeout(window: Window; handler: JSValueConst; timeout = 0i32;
    args: varargs[JSValueConst]): int32 {.jsfunc.} =
  return window.timeouts.setTimeout(ttTimeout, handler, timeout, args)

proc setInterval(window: Window; handler: JSValueConst; interval = 0i32;
    args: varargs[JSValueConst]): int32 {.jsfunc.} =
  return window.timeouts.setTimeout(ttInterval, handler, interval, args)

proc clearTimeout(window: Window; id: int32) {.jsfunc.} =
  window.timeouts.clearTimeout(id)

proc clearInterval(window: Window; id: int32) {.jsfunc.} =
  window.clearTimeout(id)

func console*(window: Window): Console {.jsrfget.} =
  return window.internalConsole

proc screenX(window: Window): int {.jsrfget.} = 0
proc screenY(window: Window): int {.jsrfget.} = 0
proc screenLeft(window: Window): int {.jsrfget.} = 0
proc screenTop(window: Window): int {.jsrfget.} = 0

proc outerWidth(ctx: JSContext; window: Window): int {.jsrfget.} =
  return ctx.availWidth(window.screen)

proc outerHeight(ctx: JSContext; window: Window): int {.jsrfget.} =
  return ctx.availHeight(window.screen)

proc innerWidth(ctx: JSContext; window: Window): int {.jsrfget.} =
  return ctx.availWidth(window.screen)

proc innerHeight(ctx: JSContext; window: Window): int {.jsrfget.} =
  return ctx.availHeight(window.screen)

proc devicePixelRatio(window: Window): float64 {.jsrfget.} = 1

proc setLocation(window: Window; s: string): Err[JSError]
    {.jsfset: "location".} =
  if window.document == nil:
    return errTypeError("document is null")
  return window.document.setLocation(s)

func getWindow(window: Window): Window {.jsuffget: "window".} =
  return window

func getSelf(window: Window): Window {.jsrfget: "self".} =
  return window

func getFrames(window: Window): Window {.jsrfget: "frames".} =
  return window

func getTop(window: Window): Window {.jsuffget: "top".} =
  return window #TODO frames?

func getParent(window: Window): Window {.jsrfget: "parent".} =
  return window #TODO frames?

# See twtstr for the actual implementations.
proc atob(ctx: JSContext; window: Window; data: string): JSValue {.jsfunc.} =
  var s: string
  if (let r = s.atob(data); r.isNone):
    return JS_ThrowDOMException(ctx, $r.error, "InvalidCharacterError")
  return ctx.toJS(NarrowString(s))

proc btoa(ctx: JSContext; window: Window; data: JSValueConst): JSValue
    {.jsfunc.} =
  let data = JS_ToString(ctx, data)
  if JS_IsException(data):
    return JS_EXCEPTION
  doAssert JS_IsString(data)
  if JS_IsStringWideChar(data):
    JS_FreeValue(ctx, data)
    return JS_ThrowDOMException(ctx, "Invalid character in string",
      "InvalidCharacterError")
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

proc requestAnimationFrame(ctx: JSContext; window: Window;
    callback: JSValueConst): JSValue {.jsfunc.} =
  if not JS_IsFunction(ctx, callback):
    return JS_ThrowTypeError(ctx, "callback is not a function")
  let handler = ctx.newFunction(["callback"], """
callback(new Event("").timeStamp);
""")
  return ctx.toJS(window.setTimeout(handler, 0, callback))

proc getComputedStyle(window: Window; element: Element;
    pseudoElt = none(string)): CSSStyleDeclaration {.jsfunc.} =
  return window.getComputedStyle0(element, pseudoElt)

type MediaQueryList = ref object of EventTarget
  media: string
  matches: bool
  #TODO onchange

jsDestructor(MediaQueryList)

proc matchMedia(window: Window; s: string): MediaQueryList {.jsfunc.} =
  let cvals = parseComponentValues(s)
  let mqlist = parseMediaQueryList(cvals, window.scriptAttrsp)
  return MediaQueryList(
    matches: mqlist.applies(window.settings.scripting, window.scriptAttrsp),
    media: $mqlist
  )

proc postMessage(ctx: JSContext; window: Window; value: JSValueConst): Err[void]
    {.jsfunc.} =
  #TODO structuredClone...
  let value = JS_JSONStringify(ctx, value, JS_UNDEFINED, JS_UNDEFINED)
  defer: JS_FreeValue(ctx, value)
  var s: string
  ?ctx.fromJS(value, s)
  let data = JS_ParseJSON(ctx, cstring(s), csize_t(s.len),
    cstring"<postMessage>")
  let event = ctx.newMessageEvent(satMessage.toAtom(),
    MessageEventInit(data: data))
  window.fireEvent(event, window)
  ok()

proc loadJSModule(ctx: JSContext; moduleName: cstringConst; opaque: pointer):
    JSModuleDef {.cdecl.} =
  let window = ctx.getWindow()
  #TODO I suspect this doesn't work with dynamically loaded modules?
  # at least we'd have to set currentModuleURL before every script
  # execution...
  let url = window.currentModuleURL
  var x = none(URL)
  let moduleName = $moduleName
  if url != nil and
      (moduleName.startsWith("/") or moduleName.startsWith("./") or
      moduleName.startsWith("../")):
    x = parseURL($moduleName, some(url))
  if x.isNone or not x.get.origin.isSameOrigin(url.origin):
    JS_ThrowTypeError(ctx, "Invalid URL: %s", cstring(moduleName))
    return nil
  let request = newRequest(x.get)
  let response = window.loader.doRequest(request)
  if response.res != 0:
    JS_ThrowTypeError(ctx, "Failed to load module %s", cstring(moduleName))
    return nil
  response.resume()
  let source = response.body.readAll()
  response.close()
  return ctx.finishLoadModule(source, moduleName)

proc addWindowModule*(ctx: JSContext):
    tuple[eventCID, eventTargetCID: JSClassID] =
  let (eventCID, eventTargetCID) = ctx.addEventModule()
  const getset = [TabGetSet(
    name: "onload",
    get: eventReflectGet,
    set: eventReflectSet,
    magic: static int16(EventReflectMap.find(satLoad))
  )]
  ctx.registerType(Window, parent = eventTargetCID, asglobal = true,
    hasExtraGetSet = true, extraGetSet = getset)
  ctx.registerType(MediaQueryList, parent = eventTargetCID)
  return (eventCID, eventTargetCID)

proc addWindowModule2*(ctx: JSContext):
    tuple[windowCID, eventCID, eventTargetCID: JSClassID] =
  let (eventCID, eventTargetCID) = ctx.addEventModule()
  let windowCID = ctx.registerType(Window, parent = eventTargetCID,
    asglobal = true, globalparent = true)
  ctx.registerType(MediaQueryList, parent = eventTargetCID)
  return (windowCID, eventCID, eventTargetCID)

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
  let performance = JS_NewAtom(ctx, cstringConst("performance"))
  let jsWindow = JS_GetGlobalObject(ctx)
  doAssert JS_DeleteProperty(ctx, jsWindow, performance, 0) == 1
  JS_FreeValue(ctx, jsWindow)
  JS_FreeAtom(ctx, performance)
  JS_SetModuleLoaderFunc(rt, normalizeModuleName, loadJSModule, nil)
  window.performance = newPerformance(window.settings.scripting)
  if window.settings.scripting == smApp:
    window.scriptAttrsp = window.attrsp
  else:
    window.scriptAttrsp = unsafeAddr dummyAttrs
  let (eventCID, eventTargetCID) = ctx.addWindowModule()
  ctx.setGlobal(window)
  ctx.addDOMExceptionModule()
  ctx.addConsoleModule()
  ctx.addNavigatorModule()
  ctx.addDOMModule(eventTargetCID)
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
  ctx.addPerformanceModule(eventTargetCID)

proc newWindow*(scripting: ScriptingMode; images, styling, autofocus: bool;
    attrsp: ptr WindowAttributes; loader: FileLoader; url: URL;
    urandom: PosixStream; imageTypes: Table[string, string];
    userAgent, referrer: string): Window =
  let window = Window(
    attrsp: attrsp,
    internalConsole: newConsole(stderr),
    navigator: Navigator(),
    loader: loader,
    images: images,
    styling: styling,
    settings: EnvironmentSettings(
      scripting: scripting,
      origin: url.origin
    ),
    crypto: Crypto(urandom: urandom),
    imageTypes: imageTypes,
    userAgent: userAgent,
    referrer: referrer,
    autofocus: autofocus
  )
  window.location = window.newLocation()
  if scripting != smFalse:
    window.addScripting()
  return window

# Forward declaration hack
fetchImpl = fetch
