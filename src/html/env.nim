{.push raises: [].}

import std/options
import std/strutils
import std/tables

import config/conftypes
import css/cssparser
import css/mediaquery
import html/catom
import html/chadombuilder
import html/dom
import html/domcanvas
import html/domexception
import html/event
import html/formdata
import html/jsencoding
import html/jsintl
import html/performance
import html/script
import html/xmlhttprequest
import io/chafile
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

# Forward declarations
proc setLocation(window: Window; s: string): Err[JSError]

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
  return window.settings.scriptAttrsp.widthPx

proc availHeight(ctx: JSContext; screen: var Screen): int {.jsfget.} =
  let window = ctx.getWindow()
  return window.settings.scriptAttrsp.heightPx

proc width(ctx: JSContext; screen: var Screen): int {.jsfget.} =
  return ctx.availWidth(screen)

proc height(ctx: JSContext; screen: var Screen): int {.jsfget.} =
  return ctx.availHeight(screen)

proc colorDepth(screen: var Screen): int {.jsfget.} = 24
proc pixelDepth(screen: var Screen): int {.jsfget.} = screen.colorDepth

# History
proc length(history: var History): uint32 {.jsfget.} = 1
proc state(history: var History): JSValue {.jsfget.} = JS_NULL
proc go(history: var History) {.jsfunc.} = discard
proc back(history: var History) {.jsfunc.} = discard
proc forward(history: var History) {.jsfunc.} = discard
proc pushState(ctx: JSContext; history: var History;
    data, unused: JSValueConst; s: string): JSResult[void] {.jsfunc.} =
  let window = ctx.getWindow()
  if window != nil:
    return window.setLocation(s)
  return ok()

# Storage
proc find(this: Storage; key: string): int =
  for i in 0 ..< this.map.len:
    if this.map[i].key == key:
      return i
  return -1

proc length(this: var Storage): uint32 {.jsfget.} =
  return uint32(this.map.len)

proc key(ctx: JSContext; this: var Storage; i: uint32): JSValue {.jsfunc.} =
  if int(i) < this.map.len:
    return ctx.toJS(this.map[int(i)].value)
  return JS_NULL

proc getItem(ctx: JSContext; this: var Storage; s: string): JSValue {.jsfunc.} =
  let i = this.find(s)
  if i != -1:
    return ctx.toJS(this.map[i].value)
  return JS_NULL

proc setItem(this: var Storage; key, value: string):
    Err[DOMException] {.jsfunc.} =
  let i = this.find(key)
  if i != -1:
    this.map[i].value = value
  else:
    if this.map.len >= 64:
      return errDOMException("Quota exceeded", "QuotaExceededError")
    this.map.add((key, value))
  ok()

proc removeItem(this: var Storage; key: string) {.jsfunc.} =
  let i = this.find(key)
  if i != -1:
    this.map.del(i)

proc names(ctx: JSContext; this: var Storage): JSPropertyEnumList
    {.jspropnames.} =
  var list = newJSPropertyEnumList(ctx, uint32(this.map.len))
  for it in this.map:
    list.add(it.key)
  return list

proc getter(ctx: JSContext; this: var Storage; s: string): JSValue
    {.jsgetownprop.} =
  return ctx.toJS(ctx.getItem(this, s)).uninitIfNull()

proc setter(this: var Storage; k, v: string): Err[DOMException]
    {.jssetprop.} =
  return this.setItem(k, v)

proc delete(this: var Storage; k: string): bool {.jsdelprop.} =
  this.removeItem(k)
  return true

# Crypto
proc getRandomValues(ctx: JSContext; crypto: var Crypto; array: JSValueConst):
    JSValue {.jsfunc.} =
  var view: JSArrayBufferView
  if ctx.fromJS(array, view).isErr:
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

# Window
proc finalize(window: Window) {.jsfin.} =
  window.timeouts.clearAll()
  for it in window.weakMap:
    JS_FreeValueRT(window.jsrt, it)
  for it in window.jsStore.mitems:
    let val = it
    it = JS_UNINITIALIZED
    JS_FreeValueRT(window.jsrt, val)
  window.jsStore.setLen(0)
  window.settings.moduleMap.clear(window.jsrt)

proc mark(rt: JSRuntime; window: Window; markFunc: JS_MarkFunc) {.jsmark.} =
  for it in window.weakMap:
    JS_MarkValue(rt, it, markFunc)
  for it in window.jsStore:
    JS_MarkValue(rt, it, markFunc)

method isSameOrigin*(window: Window; origin: Origin): bool {.base.} =
  return window.settings.origin.isSameOrigin(origin)

proc fetch0(window: Window; input: JSRequest): JSResult[FetchPromise] =
  #TODO cors requests?
  if input.request.url.schemeType != stData and
      not window.isSameOrigin(input.request.url.origin):
    let err = newFetchTypeError()
    return ok(newResolvedPromise(JSResult[Response].err(err)))
  return ok(window.loader.fetch(input.request))

proc fetch(window: Window; input: JSValueConst;
    init = RequestInit(window: JS_UNDEFINED)): JSResult[FetchPromise]
    {.jsfunc.} =
  let input = ?newRequest(window.jsctx, input, init)
  return window.fetch0(input)

proc storeJS0(ctx: JSContext; v: JSValue): int =
  assert not JS_IsUninitialized(v)
  let global = ctx.getGlobal()
  let n = global.jsStoreFree
  if n == global.jsStore.len:
    global.jsStore.add(v)
  else:
    global.jsStore[n] = v
  var m = global.jsStoreFree
  while m < global.jsStore.len:
    if JS_IsUninitialized(global.jsStore[m]):
      break
    inc m
  global.jsStoreFree = m
  return n

proc fetchJS0(ctx: JSContext; n: int): JSValue =
  let global = ctx.getGlobal()
  if n >= global.jsStore.len:
    return JS_UNINITIALIZED
  result = global.jsStore[n]
  global.jsStore[n] = JS_UNINITIALIZED
  if n < global.jsStoreFree:
    global.jsStoreFree = n
  if n == global.jsStore.high:
    var n = n
    while n >= 0:
      if not JS_IsUninitialized(global.jsStore[n]):
        break
      dec n
    global.jsStore.setLen(n + 1)

proc scrollTo(window: Window) {.jsfunc.} =
  discard #TODO maybe in app mode?

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

proc console*(window: Window): Console {.jsrfget.} =
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

proc getWindow(window: Window): Window {.jsuffget: "window".} =
  return window

proc getSelf(window: Window): Window {.jsrfget: "self".} =
  return window

proc getFrames(window: Window): Window {.jsrfget: "frames".} =
  return window

proc getTop(window: Window): Window {.jsuffget: "top".} =
  return window #TODO frames?

proc getParent(window: Window): Window {.jsrfget: "parent".} =
  return window #TODO frames?

# See twtstr for the actual implementations.
proc atob(ctx: JSContext; window: Window; data: string): JSValue {.jsfunc.} =
  var s: string
  if (let r = s.atob(data); r.isErr):
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
  let res = ctx.toJS(window.setTimeout(handler, 0, callback))
  JS_FreeValue(ctx, handler)
  res

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
  let mqlist = parseMediaQueryList(cvals, window.settings.scriptAttrsp)
  return MediaQueryList(
    matches: mqlist.applies(addr window.settings),
    media: $mqlist
  )

proc postMessage(ctx: JSContext; window: Window; value: JSValueConst): Err[void]
    {.jsfunc.} =
  #TODO structuredClone...
  let value = JS_JSONStringify(ctx, value, JS_UNDEFINED, JS_UNDEFINED)
  var s: string
  ?ctx.fromJSFree(value, s)
  let data = JS_ParseJSON(ctx, cstring(s), csize_t(s.len),
    cstring"<postMessage>")
  let event = ctx.newMessageEvent(satMessage.toAtom(),
    MessageEventInit(data: data))
  JS_FreeValue(ctx, data)
  window.fireEvent(event, window)
  ok()

proc loadJSModule(ctx: JSContext; moduleName: cstringConst; opaque: pointer):
    JSModuleDef {.cdecl.} =
  let window = ctx.getWindow()
  #TODO I suspect this doesn't work with dynamically loaded modules?
  # at least we'd have to set currentModuleURL before every script
  # execution...
  let url = window.currentModuleURL
  var x = Opt[URL].err()
  let moduleName = $moduleName
  if url != nil and
      (moduleName.startsWith("/") or moduleName.startsWith("./") or
      moduleName.startsWith("../")):
    x = parseURL($moduleName, some(url))
  if x.isErr or not x.get.origin.isSameOrigin(url.origin):
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

proc collectWindowGetSet(): seq[TabGetSet] =
  result = @[]
  for it in WindowEvents:
    result.add(TabGetSet(
      name: "on" & $it,
      get: eventReflectGet,
      set: eventReflectSet,
      magic: int16(EventReflectMap.find(it))
    ))

proc addWindowModule*(ctx: JSContext):
    tuple[eventCID, eventTargetCID: JSClassID] =
  let (eventCID, eventTargetCID) = ctx.addEventModule()
  const getset = collectWindowGetSet()
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
  let weakMap = JS_GetPropertyStr(ctx, jsWindow, "WeakMap")
  for it in window.weakMap.mitems:
    it = JS_CallConstructor(ctx, weakMap, 0, nil)
    doAssert not JS_IsException(it)
  JS_FreeValue(ctx, weakMap)
  doAssert JS_DeleteProperty(ctx, jsWindow, performance, 0) == 1
  JS_FreeValue(ctx, jsWindow)
  JS_FreeAtom(ctx, performance)
  JS_SetModuleLoaderFunc(rt, normalizeModuleName, loadJSModule, nil)
  window.performance = newPerformance(window.settings.scripting)
  if window.settings.scripting == smApp:
    window.settings.scriptAttrsp = window.settings.attrsp
  else:
    window.settings.scriptAttrsp = unsafeAddr dummyAttrs
  let (eventCID, eventTargetCID) = ctx.addWindowModule()
  ctx.setGlobal(window)
  ctx.addDOMExceptionModule()
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
  ctx.addPerformanceModule(eventTargetCID)

proc newWindow*(scripting: ScriptingMode; images, styling, autofocus: bool;
    colorMode: ColorMode; headless: HeadlessMode; attrsp: ptr WindowAttributes;
    loader: FileLoader; url: URL; urandom: PosixStream;
    imageTypes: Table[string, string];
    userAgent, referrer, contentType: string): Window =
  let window = Window(
    internalConsole: newConsole(cast[ChaFile](stderr)),
    navigator: Navigator(),
    loader: loader,
    settings: EnvironmentSettings(
      attrsp: attrsp,
      styling: styling,
      scripting: scripting,
      origin: url.origin,
      images: images,
      autofocus: autofocus,
      colorMode: colorMode,
      headless: headless,
      contentType: contentType.toAtom()
    ),
    crypto: Crypto(urandom: urandom),
    imageTypes: imageTypes,
    userAgent: userAgent,
    referrer: referrer
  )
  window.location = window.newLocation()
  for it in window.weakMap.mitems:
    it = JS_UNDEFINED
  if scripting != smFalse:
    window.addScripting()
  return window

# Forward declaration hack
fetchImpl = fetch0
storeJSImpl = storeJS0
fetchJSImpl = fetchJS0

{.pop.} # raises: []
