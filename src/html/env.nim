{.push raises: [].}

import config/conftypes
import config/mimetypes
import css/cssparser
import css/cssvalues
import css/mediaquery
import html/catom
import html/chadombuilder
import html/dom
import html/domcanvas
import html/domexception
import html/domrect
import html/event
import html/jsencoding
import html/jsintl
import html/performance
import html/script
import html/xmlhttprequest
import io/chafile
import io/console
import io/dynstream
import io/timeout
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsopaque
import monoucha/jspropenumlist
import monoucha/jsref
import monoucha/jstypes
import monoucha/jsutils
import monoucha/quickjs
import monoucha/tojs
import server/headers
import server/loaderiface
import server/request
import types/blob
import types/formdata
import types/jsopt
import types/opt
import types/url
import types/winattrs
import utils/tabutil
import utils/twtstr

type JSFetchOpaque {.final.} = ref object of RootObj
  ctx: JSContext
  resolve: JSObjectTraced
  reject: JSObjectTraced

# Forward declarations
proc setLocation(ctx: JSContext; window: Window; s: string): JSValue
proc outerWidth(window: Window): int
proc outerHeight(window: Window): int

jsClassRaw(NavigatorDef, "Navigator"):
  type Navigator = distinct Window

  proc finalizeNavigator(rt: JSRuntime; this: pointer) {.jsfin.} =
    JS_FreeForeignObject(rt, this)

  proc markNavigator(rt: JSRuntime; this: pointer; markFunc: JS_MarkFunc)
      {.jsmark.} =
    JS_MarkForeignObject(rt, this, markFunc)

  # NavigatorID
  proc appCodeName(navigator: Navigator): string {.jsfget.} = "Mozilla"
  proc appName(navigator: Navigator): string {.jsfget.} = "Netscape"
  proc appVersion(navigator: Navigator): string {.jsfget.} = "5.0 (X11)"
  proc platform(navigator: Navigator): string {.jsfget, jsfget: "oscpu".} =
    "Linux x86_64"
  proc product(navigator: Navigator): string {.jsfget.} = "Gecko"
  proc productSub(navigator: Navigator): string {.jsfget.} = "20100101"
  proc userAgent(navigator: Navigator): lent string {.jsfget.} =
    return Window(navigator).userAgent
  proc vendor(navigator: Navigator): string {.jsfget, jsfget: "vendorSub".} =
    ""
  proc taintEnabled(navigator: Navigator): bool {.jsfunc.} = false

  # NavigatorLanguage
  proc language(navigator: Navigator): string {.jsfget.} = "en-US"
  proc languages(navigator: Navigator): seq[string] {.jsfget.} =
    @["en-US", "en"] #TODO frozen array?

  # NavigatorOnline
  proc onLine(navigator: Navigator): bool {.jsfget.} =
    true # at the very least, the terminal is on-line :)

  #TODO NavigatorContentUtils

  # NavigatorCookies
  proc cookieEnabled(navigator: Navigator): bool {.jsfget.} =
    #TODO check window for cookie?  it's exposed anyway so we wouldn't
    # lose much
    true

  # NavigatorPlugins
  proc pdfViewerEnabled(navigator: Navigator): bool {.jsfget,
      jsfget: "javaEnabled".} =
    false

# PluginArray
jsClassRaw(PluginArrayDef, "PluginArray"):
  type PluginArray = distinct Window

  proc finalizePluginArray(rt: JSRuntime; this: pointer) {.jsfin.} =
    JS_FreeForeignObject(rt, this)

  proc markPluginArray(rt: JSRuntime; this: pointer; markFunc: JS_MarkFunc)
      {.jsmark.} =
    JS_MarkForeignObject(rt, this, markFunc)

  proc namedItem(pluginArray: PluginArray): string {.jsfunc.} = ""
  proc item(pluginArray: PluginArray): JSValue {.jsfunc.} = JS_NULL
  proc length(pluginArray: PluginArray): uint32 {.jsfget.} = 0
  proc getter(pluginArray: PluginArray; atom: JSAtom): JSValue
      {.jsgetownprop.} =
    return JS_UNINITIALIZED

# MimeTypeArray
jsClassRaw(MimeTypeArrayDef, "MimeTypeArray"):
  type MimeTypeArray = distinct Window

  proc finalizeMimeTypeArray(rt: JSRuntime; this: pointer) {.jsfin.} =
    JS_FreeForeignObject(rt, this)

  proc markMimeTypeArray(rt: JSRuntime; this: pointer; markFunc: JS_MarkFunc)
      {.jsmark.} =
    JS_MarkForeignObject(rt, this, markFunc)

  proc namedItem(mimeTypeArray: MimeTypeArray): string {.jsfunc.} = ""
  proc item(mimeTypeArray: MimeTypeArray): JSValue {.jsfunc.} = JS_NULL
  proc length(mimeTypeArray: MimeTypeArray): uint32 {.jsfget.} = 0
  proc getter(mimeTypeArray: MimeTypeArray; atom: JSAtom): JSValue
      {.jsgetownprop.} =
    return JS_UNINITIALIZED

# Notification
# The existence of this feature in mainstream browsers is an insult to all
# users' intelligence.  Nevertheless, we have to shim the API because some
# geniuses use it for "browser verification."
proc resolveToDenied(ctx: JSContext; argc: cint; argv: JSValueConstArray):
    JSValue {.cdecl.} =
  let denied = JS_NewString(ctx, "denied")
  if JS_IsException(denied):
    return denied
  if not JS_IsUndefined(argv[0]):
    let res = ctx.call(argv[0], JS_UNDEFINED, denied)
    if JS_IsException(res):
      #TODO "report" (fire error event)
      JS_FreeValue(ctx, denied)
      return res
  return ctx.callSink(argv[1], JS_UNDEFINED, denied)

jsClassRaw(NotificationDef, "Notification"):
  proc newNotification(ctx: JSContext; ctor: JSValueConst): JSValue
      {.jsctor2.} =
    return JS_NewObjectFromCtor(ctx, ctor, classDef.id)

  proc requestPermission(ctx: JSContext; callback: JSValueConst = JS_UNDEFINED):
      JSValue {.jsstfunc.} =
    if not JS_IsUndefined(callback) and not JS_IsFunction(ctx, callback):
      return JS_ThrowTypeError(ctx, "not a function")
    var funs {.noinit.}: array[2, JSValue]
    let res = ctx.newPromiseCapability(funs)
    if JS_IsException(res):
      return res
    let code = ctx.enqueueJob(resolveToDenied, funs[0], callback)
    ctx.freeValues(funs)
    if code < 0:
      JS_FreeValue(ctx, res)
      return JS_EXCEPTION
    return res

# Permissions
# See above.
jsClassRaw(PermissionsDef, "Permissions"):
  proc finalizePermissions(rt: JSRuntime; this: pointer) {.jsfin.} =
    JS_FreeForeignObject(rt, this)

  proc markPermissions(rt: JSRuntime; this: pointer; markFunc: JS_MarkFunc)
      {.jsmark.} =
    JS_MarkForeignObject(rt, this, markFunc)

  proc query(ctx: JSContext; this: JSValueConst; desc: JSValueConst): JSValue
      {.jsfunc.} =
    let name = JS_GetPropertyStr(ctx, desc, "name")
    if JS_IsException(name):
      return name
    JS_FreeValue(ctx, name)
    # reject immediately
    JS_ThrowTypeError(ctx, "permissions are not supported")
    return ctx.newRejectedPromise()

# Screen
jsClassRaw(ScreenDef, "Screen"):
  type Screen = distinct Window

  proc finalizeScreen(rt: JSRuntime; this: pointer) {.jsfin.} =
    JS_FreeForeignObject(rt, this)

  proc markScreen(rt: JSRuntime; this: pointer; markFunc: JS_MarkFunc)
      {.jsmark.} =
    JS_MarkForeignObject(rt, this, markFunc)

  # These are fingerprinting vectors; only app mode gets the real values.
  proc availWidth(screen: Screen): int {.jsfget.} =
    return Window(screen).outerWidth

  proc availHeight(screen: Screen): int {.jsfget.} =
    return Window(screen).outerHeight

  proc width(screen: Screen): int {.jsfget.} =
    return screen.availWidth

  proc height(screen: Screen): int {.jsfget.} =
    return screen.availHeight

  proc colorDepth(screen: Screen): int32 {.jsfget.} =
    case Window(screen).settings.scriptAttrsp.colorMode
    of cmMonochrome: return 1
    of cmANSI: return 4
    of cmEightBit: return 8
    of cmTrueColor: return 24

  proc pixelDepth(screen: Screen): int32 {.jsfget.} =
    screen.colorDepth

# History
jsClassRaw(HistoryDef, "History"):
  type History = distinct Window

  proc finalizeHistory(rt: JSRuntime; this: pointer) {.jsfin.} =
    JS_FreeForeignObject(rt, this)

  proc markHistory(rt: JSRuntime; this: pointer; markFunc: JS_MarkFunc)
      {.jsmark.} =
    JS_MarkForeignObject(rt, this, markFunc)

  proc length(history: History): uint32 {.jsfget.} = 1
  proc state(history: History): JSValue {.jsfget.} = JS_NULL
  proc go(history: History) {.jsfunc.} = discard
  proc back(history: History) {.jsfunc.} = discard
  proc forward(history: History) {.jsfunc.} = discard

  proc pushState(ctx: JSContext; history: History; data: JSValueConst;
      unused: DOMString; url: JSValueConst = JS_NULL): JSValue {.jsfunc,
      jsfunc: "replaceState".} =
    #TODO figure out some way to emulate the navigation API that isn't as
    # horribly user-hostile as others implement it
    var s: string
    if not JS_IsNull(url):
      ?ctx.fromJS(url, s)
    let window = Window(history)
    if window != nil and window.document != nil:
      let url2 = window.document.parseURL0(s)
      if url2 != nil and $url2 != $window.document.url:
        return ctx.setLocation(window, s)
    return JS_UNDEFINED

# Storage
jsClassDef(Storage):
  proc find(this: Storage; key: DOMString): int =
    for i in 0 ..< this.map.len:
      if this.map[i].key == key.toOpenArray():
        return i
    return -1

  proc length(this: Storage): uint32 {.jsfget.} =
    return uint32(this.map.len)

  proc key(ctx: JSContext; this: Storage; u: uint32): JSValue {.jsfunc.} =
    if u < uint32(this.map.len):
      return ctx.toJS(this.map[int(u)].key)
    return JS_NULL

  proc getItem(ctx: JSContext; this: Storage; s: DOMString): JSValue
      {.jsfunc.} =
    let i = this.find(s)
    if i >= 0:
      return ctx.toJS(this.map[i].value)
    return JS_NULL

  proc setItem(ctx: JSContext; this: Storage; key, value: DOMString): JSValue
      {.jsfunc.} =
    let i = this.find(key)
    if i >= 0:
      this.map[i].value = $value
    else:
      if this.map.len >= 64:
        return JS_ThrowDOMException(ctx, "QuotaExceededError",
          "quota exceeded")
      this.map.add(($key, $value))
    return JS_UNDEFINED

  proc removeItem(this: Storage; key: DOMString) {.jsfunc.} =
    let i = this.find(key)
    if i >= 0:
      this.map.del(i)

  proc names(ctx: JSContext; this: Storage): JSPropertyEnumList
      {.jspropnames.} =
    var list = newJSPropertyEnumList(ctx, uint32(this.map.len))
    for it in this.map:
      list.add(it.key)
    return list

  proc getter(ctx: JSContext; this: Storage; s: DOMString): JSValue
      {.jsgetownprop.} =
    return ctx.toJS(ctx.getItem(this, s)).uninitIfNull()

  proc setter(ctx: JSContext; this: Storage; k, v: DOMString): JSValue
      {.jssetprop.} =
    return ctx.setItem(this, k, v)

  proc delete(this: Storage; k: DOMString): bool {.jsdelprop.} =
    this.removeItem(k)
    return true

# Crypto
jsClassRaw(CryptoDef, "Crypto"):
  type Crypto = distinct Window

  proc finalizeCrypto(rt: JSRuntime; this: pointer) {.jsfin.} =
    JS_FreeForeignObject(rt, this)

  proc markCrypto(rt: JSRuntime; this: pointer; markFunc: JS_MarkFunc)
      {.jsmark.} =
    JS_MarkForeignObject(rt, this, markFunc)

  proc getRandomValues(ctx: JSContext; crypto: Crypto; array: JSValueConst):
      JSValue {.jsfunc.} =
    let window = Window(crypto)
    var view: JSArrayBufferView
    ?ctx.fromJS(array, view)
    if view.t == JS_TYPED_ARRAY_UINT8C or view.t > JS_TYPED_ARRAY_BIG_UINT64:
      return JS_ThrowDOMException(ctx, "TypeMismatchError",
        "Wrong typed array type")
    if view.abuf.len > 65536:
      return JS_ThrowDOMException(ctx, "QuotaExceededError", "Too large array")
    doAssert window.urandom.readLoop(view.toOpenArray()).isOk
    return JS_DupValue(ctx, array)

# Location
type Location = distinct Window

template window(location: Location): Window =
  Window(location)

proc document(location: Location): Document =
  return location.window.document

proc url(location: Location): URL =
  let document = location.document
  if document != nil:
    return document.url
  return parseURL0("about:blank")

#TODO CORS (SecurityError)
jsClassRaw(LocationDef, "Location"):
  proc finalizeLocation(rt: JSRuntime; this: pointer) {.jsfin.} =
    JS_FreeForeignObject(rt, this)

  proc markLocation(rt: JSRuntime; this: pointer; markFunc: JS_MarkFunc)
      {.jsmark.} =
    JS_MarkForeignObject(rt, this, markFunc)

  proc `$`(location: Location): string {.jsuffunc: "toString",
      jsuffget: "href".} =
    return location.url.serialize()

  proc setHref(ctx: JSContext; location: Location; s: string): JSValue {.
      jsfset: "href", jsuffunc: "assign", jsuffunc: "replace".} =
    let window = location.window
    return ctx.setLocation(window, s)

  proc reload(location: Location) {.jsuffunc.} =
    let window = location.window
    if window.document != nil:
      window.navigate(location.url)

  proc origin*(location: Location): string {.jsuffget.} =
    return location.url.jsOrigin

  proc protocol(ctx: JSContext; location: Location): JSValue {.jsuffget.} =
    return ctx.protocol(location.url)

  proc setProtocol(ctx: JSContext; location: Location; s: string): JSValue
      {.jsfset: "protocol".} =
    let document = location.document
    if document == nil:
      return JS_UNDEFINED
    let copyURL = newURL(location.url)
    copyURL.setProtocol(s)
    if copyURL.schemeType notin {stHttp, stHttps}:
      return JS_ThrowDOMException(ctx, "SyntaxError", "invalid URL")
    document.window.navigate(copyURL)
    return JS_UNDEFINED

  proc host(location: Location): string {.jsuffget.} =
    return location.url.host

  proc setHost(location: Location; s: string) {.jsfset: "host".} =
    let document = location.document
    if document == nil:
      return
    let copyURL = newURL(location.url)
    copyURL.setHost(s)
    document.window.navigate(copyURL)

  proc hostname(location: Location): string {.jsuffget.} =
    return location.url.hostname

  proc setHostname(location: Location; s: string) {.jsfset: "hostname".} =
    let document = location.document
    if document == nil:
      return
    let copyURL = newURL(location.url)
    copyURL.setHostname(s)
    document.window.navigate(copyURL)

  proc port(location: Location): string {.jsuffget.} =
    return location.url.port

  proc setPort(location: Location; s: string) {.jsfset: "port".} =
    let document = location.document
    if document == nil:
      return
    let copyURL = newURL(location.url)
    copyURL.setPort(s)
    document.window.navigate(copyURL)

  proc pathname(location: Location): string {.jsuffget.} =
    return location.url.pathname

  proc setPathname(location: Location; s: string) {.jsfset: "pathname".} =
    let document = location.document
    if document == nil:
      return
    let copyURL = newURL(location.url)
    copyURL.setPathname(s)
    document.window.navigate(copyURL)

  proc search(location: Location): string {.jsuffget.} =
    return location.url.search

  proc setSearch(location: Location; s: string) {.jsfset: "search".} =
    let document = location.document
    if document == nil:
      return
    let copyURL = newURL(location.url)
    copyURL.setSearch(s)
    document.window.navigate(copyURL)

  proc hash(location: Location): string {.jsuffget.} =
    return location.url.hash

  proc setHash(location: Location; s: string) {.jsfset: "hash".} =
    let document = location.document
    if document == nil:
      return
    let copyURL = newURL(location.url)
    copyURL.setHash(s)
    document.window.navigate(copyURL)

proc windowAutoInitGetter(ctx: JSContext; this: JSValueConst; argc: cint;
    argv: JSValueConstArray; magic: cint; func_data: JSValueConstArray):
    JSValue {.cdecl.} =
  # data[0] is object, data[1] is parent's class id
  var parent0: int32
  discard JS_ToInt32(ctx, parent0, func_data[1])
  let parent = JSClassID(uint32(parent0))
  if JS_GetClassID(this) != parent:
    return JS_ThrowTypeErrorInvalidClass(ctx, parent)
  if JS_IsUndefined(func_data[0]):
    let classid = JSClassID(uint32(magic))
    let obj = JS_NewObjectClass(ctx, classid)
    if JS_IsException(obj):
      return obj
    let rt = JS_GetRuntime(ctx)
    let rtOpaque = rt.getOpaque()
    if int(classid) < rtOpaque.classes.len:
      if not ctx.setPropertyFunctionList(obj,
          rtOpaque.classes[int(classid)].unforgeable):
        JS_FreeValue(ctx, obj)
        return JS_EXCEPTION
    let ctxOpaque = ctx.getOpaque()
    if classid == LocationDef.id:
      let valueOf0 = ctxOpaque.valRefs[jsvObjectPrototypeValueOf]
      if ctx.defineProperty(obj, "valueOf",
          JS_DupValue(ctx, valueOf0)) == dprException:
        JS_FreeValue(ctx, obj)
        return JS_EXCEPTION
      if ctx.defineProperty(obj, "toPrimitive", JS_UNDEFINED) == dprException:
        JS_FreeValue(ctx, obj)
        return JS_EXCEPTION
      #TODO [[DefaultProperties]], exotic
    JS_SetOpaque(obj, JS_DupForeignObject(rt, ctxOpaque.globalObj))
    func_data[0] = obj
  return JS_DupValue(ctx, func_data[0])

proc windowAutoInitSetter(ctx: JSContext; this, val: JSValueConst;
    magic: cint): JSValue {.cdecl.} =
  let atom = ctx.getOpaque().strRefs[JSStrRef(magic)]
  if JS_DefinePropertyValue(ctx, this, atom, JS_DupValue(ctx, val),
      JS_PROP_C_W_E) < 0:
    return JS_EXCEPTION
  return JS_UNDEFINED

type AutoInitGetSetType = enum
  gstProto, gstReplaceable, gstUnforgeable

proc windowSetLocation(ctx: JSContext; this, val: JSValueConst): JSValue
    {.cdecl.} =
  var window0: pointer
  var s: string
  ?ctx.fromJSThis(this, event.windowClassID, window0)
  ?ctx.fromJS(val, s)
  let window = cast[Window](window0)
  if window.document == nil:
    return JS_ThrowTypeError(ctx, "document is null")
  return ctx.setLocation(window, s)

proc registerAutoInitGetSet(ctx: JSContext; namespace: JSValueConst;
    parentClass: JSClassID; def: ChaClassDef; name: JSStrRef;
    t: AutoInitGetSetType): Opt[void] =
  # Register a lazily initialized singleton-like class.
  ?ctx.registerClass(def)
  let prop = ctx.getOpaque().strRefs[name]
  let parentClass = JS_NewInt32(ctx, int32(parentClass))
  var data = [JSValueConst(JS_UNDEFINED), parentClass]
  let getter = JS_NewCFunctionData(ctx, windowAutoInitGetter, 0,
    cast[cint](def.id), 2, data.toJSValueConstArray())
  if JS_IsException(getter):
    return err()
  if ctx.definePropertyC(getter, prop,
      JS_AtomToValue(ctx, prop)) == dprException:
    JS_FreeValue(ctx, getter)
    return err()
  var setter = JS_UNDEFINED
  var flags = cint(JS_PROP_CONFIGURABLE or JS_PROP_ENUMERABLE)
  var f: JSCFunctionType
  case t
  of gstProto: discard
  of gstUnforgeable:
    flags = JS_PROP_ENUMERABLE
    f.setter = windowSetLocation
    setter = JS_NewCFunction2(ctx, f.generic, ($name).toCStringConst, 1,
      JS_CFUNC_setter, 0)
  of gstReplaceable:
    f.setter_magic = windowAutoInitSetter
    setter = JS_NewCFunction2(ctx, f.generic, ($name).toCStringConst, 1,
      JS_CFUNC_setter_magic, cint(name))
  if JS_IsException(setter):
    JS_FreeValue(ctx, getter)
    return err()
  if JS_DefinePropertyGetSet(ctx, namespace, prop, getter, setter, flags) < 0:
    return err()
  ok()

proc addNavigatorModule*(ctx: JSContext): Opt[void] =
  ?ctx.registerClass(StorageDef)
  ?ctx.registerClass(NotificationDef)
  let ctxOpaque = ctx.getOpaque()
  if ctxOpaque == nil:
    return ok()
  let global = ctxOpaque.global
  let globalId = JS_GetClassID(global)
  ?ctx.registerAutoInitGetSet(global, globalId, NavigatorDef, jstNavigator,
    gstReplaceable)
  ?ctx.registerAutoInitGetSet(global, globalId, ScreenDef, jstScreen,
    gstReplaceable)
  ?ctx.registerAutoInitGetSet(global, globalId, HistoryDef, jstHistory,
    gstReplaceable)
  ?ctx.registerAutoInitGetSet(global, globalId, CryptoDef, jstCrypto,
    gstReplaceable)
  ?ctx.registerAutoInitGetSet(global, globalId, LocationDef, jstLocation,
    gstUnforgeable)
  let navigator = JS_GetClassProto(ctx, NavigatorDef.id)
  let navigatorId = NavigatorDef.id
  ?ctx.registerAutoInitGetSet(navigator, navigatorId, PluginArrayDef,
    jstPlugins, gstProto)
  ?ctx.registerAutoInitGetSet(navigator, navigatorId, MimeTypeArrayDef,
    jstMimeTypes, gstProto)
  ?ctx.registerAutoInitGetSet(navigator, navigatorId, PermissionsDef,
    jstPermissions, gstProto)
  JS_FreeValue(ctx, navigator)
  ok()

# CSS
jsNamespaceDef(CSS):
  proc supports(ctx: JSContext; arg1: CSSOMString;
      argv: varargs[JSValueConst]): JSValue {.jsstfunc.} =
    if argv.len > 0:
      var value: CSSOMString
      ?ctx.fromJS(argv[0], value)
      if decl := initCSSDeclaration($arg1):
        case decl.t
        of cdtProperty:
          var cp = initCSSParser(value)
          var dummy: seq[CSSComputedEntry] = @[]
          let res = cp.parseComputedValues0(decl.p, dummyAttrs, dummy)
          return ctx.toJS(res.isOk)
        of cdtVariable:
          let toks = parseComponentValues(value)
          return ctx.toJS(parseDeclWithVar1(toks).len == 0)
        of cdtNestedRule: discard
      return JS_FALSE
    else:
      #TODO supports(arg1)
      return JS_FALSE

  proc cssEscape(ident: CSSOMString): string {.jsstfunc: "escape".} =
    return ident.toOpenArray().cssIdentEscape()

# MediaQueryList
type
  MediaQueryListObj {.pure, final.} = object of EventTargetObj
    media: string
    matches: bool
    #TODO onchange

  MediaQueryList = JSRef[MediaQueryListObj]

jsClassDef(MediaQueryList):
  jsextends EventTargetDef

  jsget MediaQueryList, media
  jsget MediaQueryList, matches

# Window
#TODO CORS: get prototype proxy

proc setLocation(ctx: JSContext; window: Window; s: string): JSValue =
  let url = window.document.parseURL0(s)
  if url == nil:
    return JS_ThrowDOMException(ctx, "SyntaxError", "invalid URL")
  window.navigate(url)
  return JS_UNDEFINED

proc windowSetPrototype(ctx: JSContext; obj, proto: JSValueConst): cint
    {.cdecl.} =
  let ours = JS_GetPrototype(ctx, obj)
  if JS_IsException(ours):
    return -1
  let res = JS_SameValue(ctx, obj, ours)
  JS_FreeValue(ctx, ours)
  cint(res)

proc windowIsExtensible(ctx: JSContext; obj: JSValueConst): cint {.cdecl.} =
  return 1

proc windowPreventExtensions(ctx: JSContext; obj: JSValueConst): cint
    {.cdecl.} =
  return 0

proc windowDefineOwnProperty(ctx: JSContext; obj: JSValueConst; prop: JSAtom;
    val, getter, setter: JSValueConst; flags: cint): cint {.cdecl.} =
  let propVal = JS_AtomIsNumericIndex1(ctx, prop)
  if JS_IsException(propVal):
    return -1
  if JS_IsUndefined(propVal):
    return JS_DefineProperty(ctx, obj, prop, val, getter, setter,
      flags or JS_PROP_NO_EXOTIC)
  JS_FreeValue(ctx, propVal)
  return JS_ThrowTypeErrorOrFalse(ctx, flags,
    "cannot set indexed property on window")

proc throwNetworkError(ctx: JSContext): JSValue =
  return JS_ThrowTypeError(ctx,
    "NetworkError when attempting to fetch resource")

proc jsFinish(opaque: RootRef; response: Response) =
  let opaque = JSFetchOpaque(opaque)
  let ctx = move(opaque.ctx)
  let resolve = moveJSValue(opaque.resolve)
  let reject = moveJSValue(opaque.reject)
  if response != nil:
    let val = ctx.toJS(response)
    if not JS_IsException(val):
      let res = ctx.callSink(resolve, JS_UNDEFINED, val)
      JS_FreeValue(ctx, res)
    JS_FreeValue(ctx, reject)
  else:
    discard ctx.throwNetworkError()
    discard ctx.enqueueRejection(reject)
  JS_FreeValue(ctx, resolve)
  JS_FreeContext(ctx)

proc microtaskJob(ctx: JSContext; argc: cint; argv: JSValueConstArray):
    JSValue {.cdecl.} =
  ctx.call(argv[0], JS_UNDEFINED)

proc animationFrameHandler(ctx: JSContext; this: JSValueConst; argc: cint;
    argv: JSValueConstArray): JSValue {.cdecl.} =
  let arg0 = ctx.toJS(getUnixMillis())
  return ctx.callSink(argv[0], this, arg0)

jsClassDef(Window):
  jsextends EventTargetDef

  event.windowClassID = classDef.id

  jsget Window, localStorage
  jsget Window, sessionStorage
  jsget Window, referrer
  jsget Window, performance
  jsget Window, customElements
  jsufget Window, document

  proc addWindowEvents(ctx: JSContext): Opt[void] =
    let ctxOpaque = ctx.getOpaque()
    if ctxOpaque == nil:
      return ok()
    ctx.addEventGetSetObj(ctxOpaque.global, classDef.id, WindowEvents)

  proc finalize(rt: JSRuntime; window: Window) {.jsfin.} =
    rt.finalize(window.timeouts)
    rt.freeValues(window.weakMap)
    window.urandom.sclose()
    window.settings.moduleMap.clear(rt)
    for data in window.loader.data:
      if data of ConnectData:
        let data = ConnectData(data)
        if data.opaque of JSFetchOpaque:
          let opaque = JSFetchOpaque(data.opaque)
          JS_FreeContext(opaque.ctx)
      window.loader.unset(data)

  proc mark(rt: JSRuntime; window: Window; markFunc: JS_MarkFunc) {.jsmark.} =
    for it in window.weakMap.myitems:
      JS_MarkValue(rt, it, markFunc)
    for it in window.imageURLCache:
      let cachedURL = CachedURLImage(it)
      rt.markObj(cachedURL.window, markFunc)
      for img in cachedURL.shared:
        rt.markObj(img, markFunc)
    for it in window.svgCache:
      let cachedSvg = CachedSVG(it)
      rt.markObj(cachedSvg.window, markFunc)
      for svg in cachedSvg.shared:
        rt.markObj(svg, markFunc)
    if window.loader != nil:
      for data in window.loader.data:
        if data of ConnectData:
          let data = ConnectData(data)
          if data.opaque of JSFetchOpaque:
            let opaque = JSFetchOpaque(data.opaque)
            JS_MarkValue(rt, opaque.resolve, markFunc)
            JS_MarkValue(rt, opaque.reject, markFunc)
        elif data of OngoingData:
          let data = OngoingData(data)
          rt.markObj(data.response, markFunc)
    for it in window.pendingCanvasCtls:
      rt.markObj(it, markFunc)
    rt.mark(window.timeouts, markFunc)

  proc fetch(ctx: JSContext; window: Window; input: JSValueConst;
      init: JSValueConst = JS_UNDEFINED): JSValue {.jsfunc.} =
    let input = ?newRequest(ctx, input, init)
    if input.url.schemeType != stData and
        not window.isSameOrigin(input.url.origin):
      # reject immediately
      discard ctx.throwNetworkError()
      return ctx.newRejectedPromise()
    var funs {.noinit.}: array[2, JSValue]
    let res = ctx.newPromiseCapability(funs)
    if JS_IsException(res):
      return res
    let opaque = JSFetchOpaque(
      ctx: JS_DupContext(ctx),
      resolve: traceObj(funs[0]),
      reject: traceObj(funs[1])
    )
    window.loader.fetch(input, jsFinish, opaque)
    return res

  proc scrollTo(window: Window) {.jsfunc.} =
    discard #TODO maybe in app mode?

  proc setTimeout(ctx: JSContext; window: Window; t: TimeoutType;
      handler: JSValueConst; timeout = 0i32; args: varargs[JSValueConst]):
      int32 {.jsmfunc("setTimeout", ttTimeout),
        jsmfunc("setInterval", ttInterval).} =
    window.timeouts.setTimeout(ctx, t, handler, timeout, args)

  proc clearTimeout(window: Window; id: int32) {.jsfunc.} =
    window.timeouts.clearTimeout(id)

  proc clearInterval(window: Window; id: int32) {.jsfunc.} =
    window.clearTimeout(id)

  proc screenX(window: Window): int {.jsrfget.} = 0
  proc screenY(window: Window): int {.jsrfget.} = 0
  proc screenLeft(window: Window): int {.jsrfget.} = 0
  proc screenTop(window: Window): int {.jsrfget.} = 0

  proc outerWidth(window: Window): int {.jsrfget.} =
    return window.settings.scriptAttrsp.widthPx

  proc outerHeight(window: Window): int {.jsrfget.} =
    return window.settings.scriptAttrsp.heightPx

  proc innerWidth(window: Window): int {.jsrfget.} =
    return window.outerWidth

  proc innerHeight(window: Window): int {.jsrfget.} =
    return window.innerWidth

  proc devicePixelRatio(window: Window): float64 {.jsrfget.} = 1

  proc getWindow(window: Window): Window {.jsuffget: "window",
      jsrfget: "frames", jsrfget: "self".} =
    return window

  proc getTop(window: Window): Window {.jsuffget: "top".} =
    return window #TODO frames?

  proc getParent(window: Window): Window {.jsrfget: "parent".} =
    return window #TODO frames?

  proc origin(window: Window): string {.jsrfget.} =
    return Location(window).origin

  # See twtstr for the actual implementations.
  proc atob(ctx: JSContext; window: Window; data: string): JSValue {.jsfunc.} =
    var s: string
    if (let r = s.atob(data); r.isErr):
      return JS_ThrowDOMException(ctx, "InvalidCharacterError", r.error)
    return ctx.toJS(NarrowString(s))

  proc btoa(ctx: JSContext; window: Window; data: JSValueConst): JSValue
      {.jsfunc.} =
    let data = JS_ToString(ctx, data)
    if JS_IsException(data):
      return JS_EXCEPTION
    let len = JS_GetStringLength(data)
    if len == 0:
      JS_FreeValue(ctx, data)
      return ctx.toJS("")
    let buf = JS_GetNarrowStringBuffer(data)
    if buf == nil:
      JS_FreeValue(ctx, data)
      return JS_ThrowDOMException(ctx, "InvalidCharacterError",
        "invalid character in string")
    let res = btoa(buf.toOpenArray(0, int(len) - 1))
    JS_FreeValue(ctx, data)
    return ctx.toJS(res)

  proc alert(window: Window; s: DOMString) {.jsfunc.} =
    window.console.error($s)

  proc getEvent(ctx: JSContext; window: Window): JSValue {.jsrfget: "event".} =
    if window.event == nil:
      return JS_UNDEFINED
    return ctx.toJS(window.event)

  proc postMessage(ctx: JSContext; window: Window; value: JSValueConst):
      Opt[void] {.jsfunc.} =
    #TODO structuredClone...
    let value = JS_JSONStringify(ctx, value, JS_UNDEFINED, JS_UNDEFINED)
    if JS_IsException(value):
      return err()
    var s: string
    ?ctx.fromJSFree(value, s)
    let data = JS_ParseJSON(ctx, s.toCStringConst, csize_t(s.len),
      "<postMessage>".toCStringConst)
    let event = ctx.newMessageEvent(satMessage.view(),
      MessageEventInit(data: data))
    JS_FreeValue(ctx, data)
    if event != nil:
      window.fireEvent(event.asEvent, window.asEventTarget)
    ok()

  proc requestAnimationFrame(ctx: JSContext; window: Window;
      callback: JSValueConst): JSValue {.jsfunc.} =
    if not JS_IsFunction(ctx, callback):
      return JS_ThrowTypeError(ctx, "not a function")
    let handler = JS_NewCFunction(ctx, animationFrameHandler,
      "animation frame handler".toCStringConst, 1)
    if JS_IsException(handler):
      return handler
    let res = window.timeouts.setTimeout(ctx, ttTimeout, handler, 0, callback)
    JS_FreeValue(ctx, handler)
    ctx.toJS(res)

  proc getComputedStyle(ctx: JSContext; window: Window; element: Element;
      pseudoElt: JSValueConst = JS_UNDEFINED): Opt[CSSStyleDeclaration]
      {.jsfunc.} =
    return ctx.getComputedStyle0(window, element, pseudoElt)

  proc queueMicrotask(ctx: JSContext; window: Window; fun: JSValueConst):
      JSValue {.jsfunc.} =
    if not JS_IsFunction(ctx, fun):
      return JS_ThrowTypeError(ctx, "not a function")
    if ctx.enqueueJob(microtaskJob, fun) < 0:
      return JS_EXCEPTION
    return JS_UNDEFINED

  proc matchMedia(window: Window; s: CSSOMString): MediaQueryList {.jsfunc.} =
    var ctx = initCSSParser(s)
    let mqlist = ctx.parseMediaQueryList(window.settings.scriptAttrsp)
    jsNew MediaQueryListObj(
      matches: mqlist.appliesScript(addr window.settings),
      media: $mqlist
    )

proc normalizeModuleName*(ctx: JSContext; baseName, name: cstringConst;
    opaque: pointer): cstring {.cdecl.} =
  let sname = $name
  let url = parseURL0(sname)
  if url != nil:
    return js_strdup(ctx, name)
  if name[0] == '.' and name[1] == '.' and name[2] == '/' or
      name[0] == '.' and name[1] == '/' or
      name[0] == '/':
    let url = parseURL0(sname, parseURL0($baseName))
    if url != nil:
      let surl = $url
      return js_strdup(ctx, surl.toCStringConst)
  JS_ThrowTypeError(ctx, "relative module names must start with ./, ../ or /")
  return nil

proc loadJSModule(ctx: JSContext; moduleName: cstringConst; opaque: pointer):
    JSModuleDef {.cdecl.} =
  let window = ctx.getWindow()
  let name = $moduleName
  let url = parseURL0(name)
  if url == nil or not window.isSameOrigin(url.origin):
    JS_ThrowTypeError(ctx, "invalid URL: %s", moduleName)
    return nil
  let request = newRequest(url)
  let response = window.loader.doRequest(request)
  if response.stream == nil:
    JS_ThrowTypeError(ctx, "Failed to load module %s", moduleName)
    return nil
  window.loader.resume(response)
  let source = response.stream.readAll()
  window.loader.close(response)
  return ctx.finishLoadModule(source, name)

proc rejectionHandler(ctx: JSContext; promise, reason: JSValueConst;
    isHandled: JS_BOOL; opaque: pointer) {.cdecl.} =
  if not isHandled:
    let window = ctx.getGlobal()
    var s: string
    if fromJS(ctx, reason, s).isOk:
      s &= '\n'
    var ss: string
    if ctx.fromJSGetProp(reason, "stack", ss).isOk:
      s &= ss
    if window.document != nil:
      window.console.error("Unhandled promise in document",
        $window.document.url, s)
    else:
      window.console.error("(Unhandled promise)", s)
    window.console.flush()

proc windowPropsGetOwnProperty(ctx: JSContext; desc: ptr JSPropertyDescriptor;
    this: JSValueConst; prop: JSAtom): cint {.cdecl.} =
  let global = ctx.getOpaque().global
  var window: Window
  discard ctx.fromJS(global, window)
  let document = window.document
  if document != nil:
    var id: CAtom
    if ctx.fromJSView(prop, id).isErr:
      return -1
    if id == CAtomNull:
      return 0
    let element = document.getElementsById(id.view())
    if element != nil:
      if desc != nil:
        let element = ctx.toJS(element)
        if JS_IsException(element):
          return -1
        desc.flags = JS_PROP_CONFIGURABLE or JS_PROP_WRITABLE
        desc.setter = JS_UNDEFINED
        desc.getter = JS_UNDEFINED
        desc.value = element
      return 1
  return 0

proc windowPropsDeleteProperty(ctx: JSContext; obj: JSValueConst;
    prop: JSAtom): cint {.cdecl.} =
  return 0

proc windowPropsDefineOwnProperty(ctx: JSContext; obj: JSValueConst;
    prop: JSAtom; val, getter, setter: JSValueConst; flags: cint): cint
    {.cdecl.} =
  return JS_ThrowTypeErrorOrFalse(ctx, flags,
    "cannot set indexed property on window")

proc JS_SetGlobalExotic(ctx: JSContext; exotic: JSClassExoticMethodsConst)
  {.importc.}

proc addWindowProperties(ctx: JSContext): JSValue =
  var exotic {.global.} = JSClassExoticMethods(
    get_own_property: windowPropsGetOwnProperty,
    delete_property: windowPropsDeleteProperty,
    define_own_property: windowPropsDefineOwnProperty,
    set_prototype: windowSetPrototype, # same as Window
    prevent_extensions: windowPreventExtensions # same as Window
  )
  var cd {.global.} = JSClassDef(
    class_name: "WindowProperties",
    gc_mark: nil,
    exotic: JSClassExoticMethodsConst(addr exotic)
  )
  let cdef = JSClassDefConst(addr cd)
  let rt = JS_GetRuntime(ctx)
  var res: JSClassID
  discard JS_NewClassID(res)
  if JS_NewClass(rt, res, cdef) != 0:
    return JS_EXCEPTION
  let ctxOpaque = ctx.getOpaque()
  if ctxOpaque == nil:
    return JS_UNDEFINED
  let name = JS_NewString(ctx, "WindowProperties")
  if JS_IsException(name):
    return name
  let parentProto = JS_GetClassProto(ctx, EventTargetDef.id)
  let proto = JS_NewObjectProtoClass(ctx, parentProto, res)
  JS_FreeValue(ctx, parentProto)
  if JS_IsException(proto):
    JS_FreeValue(ctx, name)
    return JS_EXCEPTION
  # must circumvent the exotic handler here
  let strSym = ctx.getOpaque().symRefs[jsyToStringTag]
  if JS_DefinePropertyValue(ctx, proto, strSym, name,
      JS_PROP_CONFIGURABLE or JS_PROP_NO_EXOTIC) < 0:
    JS_FreeValue(ctx, proto)
    return JS_EXCEPTION
  return proto

proc addWindowModule(ctx: JSContext): FromJSResult =
  ?ctx.addEventTarget()
  let proto = ctx.addWindowProperties()
  let res = ctx.registerGlobalClass(WindowDef, proto)
  JS_FreeValue(ctx, proto)
  res

proc addCommonModules(ctx: JSContext; window: Window): Opt[void] =
  ctx.setGlobal(window)
  ?ctx.addEventModule()
  ?ctx.addWindowEvents()
  ?ctx.registerNamespaceFree(CSSDef)
  ?ctx.registerClass(MediaQueryListDef)
  JS_SetHostPromiseRejectionTracker(JS_GetRuntime(ctx), rejectionHandler, nil)
  ?ctx.addConsoleModule()
  ?ctx.addNavigatorModule()
  ?ctx.addDOMExceptionModule()
  ?ctx.addDOMRectModule()
  ?ctx.addDOMModule()
  ?ctx.addCanvasModule()
  ?ctx.addURLModule()
  ?ctx.addHTMLModule()
  ?ctx.addIntlModule()
  ?ctx.addBlobModule()
  ?ctx.addFormDataModule()
  ?ctx.addXMLHttpRequestModule()
  ?ctx.addHeadersModule()
  ?ctx.addRequestModule()
  ?ctx.addResponseModule()
  ?ctx.addEncodingModule()
  ctx.addPerformanceModule()

proc getConsole(ctx: JSContext): Console =
  ctx.getGlobal().console

proc getLoader(ctx: JSContext): FileLoader =
  ctx.getGlobal().loader

proc addScripting*(window: Window; ctx: JSContext): Opt[void] =
  let rt = JS_GetRuntime(ctx)
  let ctxOpaque = ctx.getOpaque()
  ?ctx.addCommonModules(window)
  if ctxOpaque != nil:
    let weakMap = JS_GetPropertyStr(ctx, ctx.getOpaque().global, "WeakMap")
    for it in window.weakMap.mitems:
      it = JS_CallConstructor(ctx, weakMap, 0, nil)
      if JS_IsException(it):
        return err()
    JS_FreeValue(ctx, weakMap)
    JS_SetModuleLoaderFunc(rt, normalizeModuleName, loadJSModule, nil)
    window.performance = newPerformance(window.settings.scripting)
    if window.settings.scripting == smApp:
      window.settings.scriptAttrsp = window.settings.attrsp
    else:
      window.settings.scriptAttrsp = unsafeAddr dummyAttrs
  if ctxOpaque != nil:
    #TODO do this in addCommonModules?
    var globalExotic {.global.} = JSClassExoticMethods(
      define_own_property: windowDefineOwnProperty,
      #TODO get_own_property, get, set, delete, own property keys
      set_prototype: windowSetPrototype,
      is_extensible: windowIsExtensible,
      prevent_extensions: windowPreventExtensions,
    )
    JS_SetGlobalExotic(ctx, addr globalExotic)
  ok()

proc newWindow*(rt: JSRuntime; scripting: ScriptingMode;
    images, styling, autofocus: bool; headless: HeadlessMode;
    attrsp: ptr WindowAttributes; loader: FileLoader; url: URL;
    urandom: PosixStream; imageTypes: MimeTypesImages;
    userAgent, referrer, contentType: string): Window =
  let console = newConsole(cast[ChaFile](stderr))
  let ctx = if scripting != smFalse:
    rt.newJSContext()
  else:
    rt.newDummyContext()
  if ctx.addWindowModule().isErr:
    console.error("failed to initialize window")
    console.writeException(ctx)
    quit(1)
  #TODO OOM
  let window = jsNew WindowObj(
    console: console,
    loader: loader,
    settings: EnvironmentSettings(
      attrsp: attrsp,
      styling: styling,
      scripting: scripting,
      origin: url.origin,
      images: images,
      autofocus: autofocus,
      headless: headless,
      contentType: contentType.toAtomTrace()
    ),
    imageTypes: imageTypes,
    userAgent: userAgent,
    referrer: referrer,
    urandom: urandom,
    localStorage: jsNew StorageObj(),
    sessionStorage: jsNew StorageObj(),
    customElements: newCustomElementRegistry(),
    importMapsAllowed: true,
    jsctx: ctx
  )
  if window != nil:
    for it in window.weakMap.mitems:
      it = JS_UNDEFINED
  if window == nil or window.addScripting(ctx).isErr:
    console.error("failed to initialize JS")
    console.writeException(ctx)
    quit(1)
  return window

proc newClient*(ctx: JSContext; loader: FileLoader; urandom: PosixStream;
    console: Console): Window =
  # global object in the pager
  if ctx.addWindowModule().isErr:
    return Window(nil)
  let window = jsNew WindowObj(
    jsctx: ctx,
    loader: loader,
    urandom: urandom,
    console: console,
    settings: EnvironmentSettings(scripting: smApp),
    dangerAlwaysSameOrigin: true,
    document: newDocument(parseURL0("about:blank"))
  )
  if window != nil:
    for it in window.weakMap.mitems:
      it = JS_UNDEFINED
  if ctx.addCommonModules(window).isErr:
    return Window(nil)
  window

# Forward declaration hack
getConsoleImpl = getConsole
getLoaderImpl = getLoader

{.pop.} # raises: []
