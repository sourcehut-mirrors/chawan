{.push raises: [].}

when NimMajor >= 2:
  import std/assertions

import config/conftypes
import config/mimetypes
import css/cssparser
import css/cssvalues
import css/mediaquery
import encoding/jsencoding
import html/catom
import html/chadombuilder
import html/dom
import html/domcanvas
import html/domexception
import html/domrect
import html/event
import html/form
import html/performance
import html/script
import html/storage
import html/xml
import html/xmlhttprequest
import io/chafile
import io/console
import io/dynstream
import io/timeout
import js/constcharp
import js/cutils
import js/fromjs
import js/jsbind
import js/jsintl
import js/jsopaque
import js/jsref
import js/jstypes
import js/jsutils
import js/quickjs
import js/tojs
import server/blob
import server/headers
import server/loaderiface
import server/request
import server/url
import utils/chaos
import utils/cowstr
import utils/opt
import utils/tabutil
import utils/twtstr

type JSFetchOpaque {.final.} = ref object of RootObj
  ctx: JSContext
  resolve: JSCallback
  reject: JSCallback

# Forward declarations
proc setLocation(ctx: JSContext; window: Window; s: Str): JSValue
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
  proc appCodeName(navigator: Navigator): Str {.jsfget.} = str("Mozilla")
  proc appName(navigator: Navigator): Str {.jsfget.} = str("Netscape")
  proc appVersion(navigator: Navigator): Str {.jsfget.} = str("5.0 (X11)")
  proc platform(navigator: Navigator): Str {.jsfget, jsfget: "oscpu".} =
    str("Linux x86_64")
  proc product(navigator: Navigator): Str {.jsfget.} = str("Gecko")
  proc productSub(navigator: Navigator): Str {.jsfget.} = str("20100101")
  proc userAgent(navigator: Navigator): lent Str {.jsfget.} =
    return Window(navigator).userAgent
  proc vendor(navigator: Navigator): Str {.jsfget, jsfget: "vendorSub".} =
    str("")
  proc taintEnabled(navigator: Navigator): bool {.jsfunc.} = false

  # NavigatorLanguage
  proc language(navigator: Navigator): Str {.jsfget.} = str("en-US")
  proc languages(navigator: Navigator): seq[Str] {.jsfget.} =
    @[str("en-US"), str("en")] #TODO frozen array?

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
      jsfunc: "javaEnabled".} =
    false

# PluginArray
jsClassRaw(PluginArrayDef, "PluginArray"):
  type PluginArray = distinct Window

  proc finalizePluginArray(rt: JSRuntime; this: pointer) {.jsfin.} =
    JS_FreeForeignObject(rt, this)

  proc markPluginArray(rt: JSRuntime; this: pointer; markFunc: JS_MarkFunc)
      {.jsmark.} =
    JS_MarkForeignObject(rt, this, markFunc)

  proc namedItem(pluginArray: PluginArray): Str {.jsfunc.} = str("")
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

  proc namedItem(mimeTypeArray: MimeTypeArray): Str {.jsfunc.} = str("")
  proc item(mimeTypeArray: MimeTypeArray): JSValue {.jsfunc.} = JS_NULL
  proc length(mimeTypeArray: MimeTypeArray): uint32 {.jsfget.} = 0
  proc getter(mimeTypeArray: MimeTypeArray; atom: JSAtom): JSValue
      {.jsgetownprop.} =
    return JS_UNINITIALIZED

# Notification
# we intentionally don't support notifications, but some websites use it
# for "browser verification"
type PermissionEnv = ref object of JSTaskEnv
  resolve: JSCallback
  callback: JSCallback
  name: DOMString

proc resolveToDenied(ctx: JSContext; env: JSTaskEnv): Opt[void] =
  let denied = ?trace(JS_NewString(ctx, "denied"))
  let env = PermissionEnv(env)
  if env.callback != nil:
    discard ?trace(ctx.call(move(env.callback), JS_UNDEFINED.vc, denied.vc))
    #TODO "report" (fire error event)
  discard ?trace(ctx.call(move(env.resolve), JS_UNDEFINED.vc, denied.vc))
  ok()

jsClassRaw(NotificationDef, "Notification"):
  proc newNotification(ctx: JSContext; ctor: JSValueConst): JSValue
      {.jsctor2.} =
    return JS_CreateFromConstructor(ctx, ctor, classDef.id)

  proc requestPermission(ctx: JSContext; callback = JSCallback(nil)): JSValue
      {.jsstfunc.} =
    var resolve: JSCallback
    var reject: JSCallback
    let res = ?ctx.newPromiseCapability(resolve, reject)
    ?ctx.queueTask(jtsDOMManipulation, resolveToDenied, PermissionEnv(
      resolve: resolve,
      callback: callback
    ))
    return res.toJSValue()

# PermissionStatus
type
  PermissionState = enum
    psDenied = "denied"
    psGranted = "granted"
    psPrompt = "prompt"

  PermissionStatusObj = object of EventTargetObj
    state: PermissionState
    name: Str
    #TODO onchange

  PermissionStatus = JSRef[PermissionStatusObj]

jsClassDef(PermissionStatus):
  jsextends EventTargetDef

  jsget PermissionStatus, state
  jsget PermissionStatus, name

# Permissions
proc denyPermissionJob(ctx: JSContext; env: JSTaskEnv): Opt[void] =
  let env = PermissionEnv(env)
  let obj = ?trace(ctx.toJSNew(jsNew PermissionStatusObj(
    name: move(env.name).asStr,
    state: psDenied
  )))
  #TODO call?
  discard ?trace(ctx.call(move(env.resolve), JS_UNDEFINED.vc, obj.vc))
  ok()

jsClassRaw(PermissionsDef, "Permissions"):
  proc finalizePermissions(rt: JSRuntime; this: pointer) {.jsfin.} =
    JS_FreeForeignObject(rt, this)

  proc markPermissions(rt: JSRuntime; this: pointer; markFunc: JS_MarkFunc)
      {.jsmark.} =
    JS_MarkForeignObject(rt, this, markFunc)

  proc query(ctx: JSContext; this, desc: JSValueConst): JSValue {.jsfunc.} =
    let jsName = ?ctx.getProperty(desc, jstName)
    var name: DOMString
    ?ctx.fromJSFree(jsName.toJSValue(), name)
    var resolve: JSCallback
    var reject: JSCallback
    let res = ?ctx.newPromiseCapability(resolve, reject)
    ?ctx.queueTask(jtsPermission, denyPermissionJob, PermissionEnv(
      resolve: resolve,
      name: name
    ))
    res.toJSValue()

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
      unused: DOMString; url = JS_NULL.vc): JSValue {.jsfunc,
      jsfunc: "replaceState".} =
    #TODO figure out some way to emulate the navigation API that isn't as
    # horribly user-hostile as others implement it
    var s: Str
    if not JS_IsNull(url):
      ?ctx.fromJS(url, s)
    let window = Window(history)
    if window != nil and window.document != nil:
      let url2 = window.document.parseURL0(s)
      if url2 != nil and url2.toStr() != window.document.url.toStr():
        return ctx.setLocation(window, s)
    return JS_UNDEFINED

# Crypto
jsClassRaw(CryptoDef, "Crypto"):
  type Crypto = distinct Window

  proc finalizeCrypto(rt: JSRuntime; this: pointer) {.jsfin.} =
    JS_FreeForeignObject(rt, this)

  proc markCrypto(rt: JSRuntime; this: pointer; markFunc: JS_MarkFunc)
      {.jsmark.} =
    JS_MarkForeignObject(rt, this, markFunc)

  proc getRandomValues(ctx: JSContext; crypto: Crypto;
      view: JSArrayBufferView): JSValue {.jsfunc.} =
    let window = Window(crypto)
    var uv = ctx.getUnsafeView(view)
    if uv.t == JS_TYPED_ARRAY_UINT8C or uv.t > JS_TYPED_ARRAY_BIG_UINT64:
      return JS_ThrowDOMException(ctx, "TypeMismatchError",
        "Wrong typed array type")
    if uv.abuf.len > 65536:
      return JS_ThrowDOMException(ctx, "QuotaExceededError", "Too large array")
    doAssert window.urandom.readLoop(uv.toOpenArray()).isOk
    return JS_DupValue(ctx, view.value)

  proc randomUUID(crypto: Crypto): DOMString {.jsfunc.} =
    let window = Window(crypto)
    var bytes: array[16, uint8]
    doAssert window.urandom.readLoop(bytes).isOk
    bytes[6] = (bytes[6] and not 0xF0'u8) or 0x40'u8
    bytes[8] = (bytes[8] and not 0xC0'u8) or 0x80'u8
    var buf = initGrowbufOfCap(36)
    for i, u in bytes:
      buf.addHexLower(u)
      if i == 3 or i == 5 or i == 7 or i == 9:
        buf &= '-'
    DOMString(buf.toStr())

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

  proc toStr(location: Location): Str {.jsuffunc: "toString",
      jsuffget: "href".} =
    return location.url.serialize()

  proc setHref(ctx: JSContext; location: Location; s: Str): JSValue {.
      jsfset: "href", jsuffunc: "assign", jsuffunc: "replace".} =
    let window = location.window
    return ctx.setLocation(window, s)

  proc reload(location: Location) {.jsuffunc.} =
    let window = location.window
    if window.document != nil:
      window.navigate(location.url)

  proc origin(location: Location): Str {.jsuffget.} =
    return location.url.jsOrigin

  proc protocol(ctx: JSContext; location: Location): JSValue {.jsuffget.} =
    return ctx.protocol(location.url)

  proc setProtocol(ctx: JSContext; location: Location; s: Str): JSValue
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

  proc host(location: Location): Str {.jsuffget.} =
    return location.url.host

  proc setHost(location: Location; s: Str) {.jsfset: "host".} =
    let document = location.document
    if document == nil:
      return
    let copyURL = newURL(location.url)
    copyURL.setHost(s)
    document.window.navigate(copyURL)

  proc hostname(location: Location): lent Str {.jsuffget.} =
    location.url.hostname

  proc setHostname(location: Location; s: Str) {.jsfset: "hostname".} =
    let document = location.document
    if document == nil:
      return
    let copyURL = newURL(location.url)
    copyURL.setHostname(s)
    document.window.navigate(copyURL)

  proc port(location: Location): Str {.jsuffget.} =
    return location.url.port

  proc setPort(location: Location; s: Str) {.jsfset: "port".} =
    let document = location.document
    if document == nil:
      return
    let copyURL = newURL(location.url)
    copyURL.setPort(s)
    document.window.navigate(copyURL)

  proc pathname(location: Location): lent Str {.jsuffget.} =
    location.url.pathname

  proc setPathname(location: Location; s: Str) {.jsfset: "pathname".} =
    let document = location.document
    if document == nil:
      return
    let copyURL = newURL(location.url)
    copyURL.setPathname(s)
    document.window.navigate(copyURL)

  proc search(location: Location): lent Str {.jsuffget.} =
    location.url.search

  proc setSearch(location: Location; s: Str) {.jsfset: "search".} =
    let document = location.document
    if document == nil:
      return
    let copyURL = newURL(location.url)
    copyURL.setSearch(s)
    document.window.navigate(copyURL)

  proc hash(location: Location): lent Str {.jsuffget.} =
    location.url.hash

  proc setHash(location: Location; s: Str) {.jsfset: "hash".} =
    let document = location.document
    if document == nil:
      return
    let copyURL = newURL(location.url)
    copyURL.setHash(s)
    document.window.navigate(copyURL)

proc windowAutoInitGetter(ctx: JSContext; this: JSValueConst; argc: cint;
    argv: JSValueConstArray; magic: cint; func_data: JSValueArray): JSValue
    {.cdecl.} =
  # data[0] is object, data[1] is parent's class id
  var parent0: int32
  discard JS_ToInt32(ctx, parent0, func_data[1].vc)
  let parent = JSClassID(uint32(parent0))
  if JS_GetClassID(this) != parent:
    return JS_ThrowTypeErrorInvalidClass(ctx, parent)
  if JS_IsUndefined(func_data[0].vc):
    let classid = JSClassID(uint32(magic))
    let obj = ?ctx.newObjectClass(classid)
    let rt = JS_GetRuntime(ctx)
    let rtOpaque = rt.getOpaque()
    let ctxOpaque = ctx.getOpaque()
    JS_SetOpaque(obj.value, JS_DupForeignObject(rt, ctxOpaque.globalObj))
    if int(classid) < rtOpaque.classes.len:
      ?ctx.setPropertyFunctionList(obj,
        rtOpaque.classes[int(classid)].unforgeable)
    if classid == LocationDef.id:
      ?ctx.defineProperty(obj, "valueOf",
        ctxOpaque.funRefs[jsfObjectPrototypeValueOf].toJSValue())
      ?ctx.defineProperty(obj, "toPrimitive", JS_UNDEFINED)
      #TODO [[DefaultProperties]], exotic
    func_data[0] = obj.toJSValue()
  return JS_DupValue(ctx, func_data[0].vc)

proc windowAutoInitSetter(ctx: JSContext; this, val: JSValueConst;
    magic: cint): JSValue {.cdecl.} =
  let name = JSStrRef(magic)
  if JS_DefinePropertyValue(ctx, this, ctx.getAtom(name),
      JS_DupValue(ctx, val), JS_PROP_C_W_E) < 0:
    return JS_EXCEPTION
  return JS_UNDEFINED

type AutoInitGetSetType = enum
  gstProto, gstReplaceable, gstUnforgeable

proc windowSetLocation(ctx: JSContext; this, val: JSValueConst): JSValue
    {.cdecl.} =
  var window0: pointer
  var s: Str
  ?ctx.fromJSThis(this, event.windowClassID, window0)
  ?ctx.fromJS(val, s)
  let window = cast[Window](window0)
  if window.document == nil:
    return JS_ThrowTypeError(ctx, "document is null")
  return ctx.setLocation(window, s)

proc registerAutoInitGetSet(ctx: JSContext; namespace: JSObject;
    parentClass: JSClassID; def: var ChaClassDef; name: JSStrRef;
    t: AutoInitGetSetType): Opt[void] =
  # Register a lazily initialized singleton-like class.
  ?ctx.registerClass(def)
  let getter = ?ctx.newGetterFunctionData(windowAutoInitGetter, cstring($name),
    cast[cint](def.id), JS_UNDEFINED.vc,
    JS_NewInt32(ctx, int32(parentClass)).vc)
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
  if JS_IsException(setter.vc):
    return err()
  if JS_DefinePropertyGetSet(ctx, namespace.value, ctx.getAtom(name),
      getter.toJSValue(), setter, flags) < 0:
    return err()
  ok()

proc addNavigatorModule(ctx: JSContext; url: URL): Opt[void] =
  ?ctx.registerClass(NotificationDef)
  ?ctx.registerClass(PermissionStatusDef)
  let ctxOpaque = ctx.getOpaque()
  if ctxOpaque == nil:
    return ok()
  let globalId = JS_GetClassID(ctxOpaque.global.value)
  ?ctx.registerAutoInitGetSet(ctxOpaque.global, globalId, NavigatorDef,
    jstNavigator, gstReplaceable)
  ?ctx.registerAutoInitGetSet(ctxOpaque.global, globalId, ScreenDef,
    jstScreen, gstReplaceable)
  ?ctx.registerAutoInitGetSet(ctxOpaque.global, globalId, HistoryDef,
    jstHistory, gstReplaceable)
  ?ctx.registerAutoInitGetSet(ctxOpaque.global, globalId, CryptoDef,
    jstCrypto, gstReplaceable)
  if url.schemeType == stData or
      url.schemeType == stHttp and url.hostname != "localhost":
    #TODO is secure context (except data)
    ?ctx.deleteProperty(ctx.getClassProto(CryptoDef.id), jstRandomUUID)
  ?ctx.registerAutoInitGetSet(ctxOpaque.global, globalId, LocationDef,
    jstLocation, gstUnforgeable)
  let navigator = ctx.getClassProto(NavigatorDef.id)
  let navigatorId = NavigatorDef.id
  ?ctx.registerAutoInitGetSet(navigator, navigatorId, PluginArrayDef,
    jstPlugins, gstProto)
  ?ctx.registerAutoInitGetSet(navigator, navigatorId, MimeTypeArrayDef,
    jstMimeTypes, gstProto)
  ctx.registerAutoInitGetSet(navigator, navigatorId, PermissionsDef,
    jstPermissions, gstProto)

# CSS
jsNamespaceDef(CSS):
  proc supports(ctx: JSContext; arg1: CSSOMString;
      argv: varargs[JSValueConst]): JSValue {.jsstfunc.} =
    if argv.len > 0:
      var value: CSSOMString
      ?ctx.fromJS(argv[0], value)
      if decl := initCSSDeclaration(arg1):
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

  proc cssIdentEscape(s: CSSOMString): Str {.jsstfunc: "escape".} =
    var buf = initGrowbufOfCap(s.len)
    for i, c in s:
      case c
      of '\0': buf &= "\uFFFD"
      of Controls - {'\0'}:
        buf &= '\\'
        if uint8(c) > 0xF:
          buf &= HexCharsLower[uint8(c) shr 4]
        buf &= HexCharsLower[uint8(c) and 0xF]
        buf &= ' '
      of AsciiDigit:
        if i == 0 or i == 1 and buf[0] == '-':
          buf &= '\\'
          buf &= HexCharsLower[uint8(c) shr 4]
          buf &= HexCharsLower[uint8(c) and 0xF]
          buf &= ' '
        else:
          buf &= c
      of '-':
        if buf.len == 1:
          buf &= "\\-"
        else:
          buf &= c
      of NonAscii, '_', AsciiAlpha:
        buf &= c
      else:
        buf &= "\\"
        buf &= c
    buf.toStr()

# MediaQueryList
type
  MediaQueryListObj {.pure, final.} = object of EventTargetObj
    media: Str
    matches: bool
    #TODO onchange
    # also there should be a list of these on window that gets dispatched
    # to on window change

  MediaQueryList = JSRef[MediaQueryListObj]

jsClassDef(MediaQueryList):
  jsextends EventTargetDef

  jsget MediaQueryList, media
  jsget MediaQueryList, matches

  proc addListener(ctx: JSContext; this: MediaQueryList;
      callback: JSObjectNil): Opt[void] {.jsfunc.} =
    ctx.addEventListener(this.asEventTarget, satChange.view(), callback)

  proc removeListener(ctx: JSContext; this: MediaQueryList;
      callback: JSObjectNil): Opt[void] {.jsfunc.} =
    ctx.removeEventListener(this.asEventTarget, satChange.view(), callback,
      JS_FALSE.vc)

# ResizeObserver
type
  ResizeObserverObj = object
    element: Element
    callback: JSCallback

  ResizeObserver = JSRef[ResizeObserverObj]

  ResizeObserverBoxOptions = enum
    robContentBox = "content-box"
    robBorderBox = "border-box"
    robDevicePixelContentBox = "device-pixel-content-box"

  ResizeObserverOptions = object of JSDict
    box {.jsdefault.}: ResizeObserverBoxOptions

jsClassDef(ResizeObserver):
  proc newResizeObserver(callback: JSCallback): ResizeObserver {.jsctor.} =
    jsNew ResizeObserverObj()

  proc observe(this: ResizeObserver; target: Element;
      options = ResizeObserverOptions()) {.jsfunc.} =
    discard #TODO

  proc unobserve(this: ResizeObserver; target: Element) {.jsfunc.} =
    discard #TODO

  proc disconnect(this: ResizeObserver) {.jsfunc.} =
    discard #TODO

# Window
#TODO CORS: get prototype proxy

proc setLocation(ctx: JSContext; window: Window; s: Str): JSValue =
  let url = window.document.parseURL0(s)
  if url == nil:
    return JS_ThrowDOMException(ctx, "SyntaxError", "invalid URL")
  window.navigate(url)
  return JS_UNDEFINED

proc windowSetPrototype(ctx: JSContext; obj, proto: JSValueConst): cint
    {.cdecl.} =
  let ours = trace(JS_GetPrototype(ctx, obj))
  if JS_IsException(ours):
    return -1
  JS_SameValue(ctx, obj, ours.vc)

proc windowIsExtensible(ctx: JSContext; obj: JSValueConst): cint {.cdecl.} =
  return 1

proc windowPreventExtensions(ctx: JSContext; obj: JSValueConst): cint
    {.cdecl.} =
  return 0

proc windowDefineOwnProperty(ctx: JSContext; obj: JSValueConst; prop: JSAtom;
    val, getter, setter: JSValueConst; flags: cint): cint {.cdecl.} =
  var idx: uint32
  case ctx.fromIdx(prop, idx)
  of fiStr:
    return JS_DefineProperty(ctx, obj, prop, val, getter, setter,
      flags or JS_PROP_NO_EXOTIC)
  of fiIdx:
    return JS_ThrowTypeErrorOrFalse(ctx, flags,
      "cannot set indexed property on window")

proc throwNetworkError(ctx: JSContext): JSValue =
  return JS_ThrowTypeError(ctx,
    "NetworkError when attempting to fetch resource")

proc jsFinish(opaque: RootRef; response: Response) =
  let opaque = JSFetchOpaque(opaque)
  let ctx = move(opaque.ctx)
  let resolve = move(opaque.resolve)
  let reject = move(opaque.reject)
  if response != nil:
    let val = ctx.toJS(response)
    if not JS_IsException(val.vc):
      #TODO invoke?
      let res = trace(ctx.callSink(resolve, JS_UNDEFINED.vc, val))
      if JS_IsException(res):
        ctx.consoleError(ctx.getExceptionMsg())
  else:
    discard ctx.throwNetworkError()
    discard ctx.enqueueRejection(reject)
  JS_GetRuntime(ctx).runMicrotasks()
  JS_FreeContext(ctx)

proc microtaskJob(ctx: JSContext; argc: cint; argv: JSValueConstArray):
    JSValue {.cdecl.} =
  JS_Call(ctx, argv[0], JS_UNDEFINED.vc, 0, nil)

type PostMessageEnv = ref object of JSTaskEnv
  data: JSValueTraced

proc postMessageJob(ctx: JSContext; env: JSTaskEnv): Opt[void] =
  let env = PostMessageEnv(env)
  let event = ctx.newMessageEvent(satMessage.view(),
    MessageEventInit(data: move(env.data)))
  if event != nil:
    let window = ctx.getWindow()
    window.fireEvent(event.asEvent, window.asEventTarget)
  ok()

proc animationFrameHandler(ctx: JSContext; this: JSValueConst; argc: cint;
    argv: JSValueConstArray): JSValue {.cdecl.} =
  let arg0 = ?trace(ctx.toJS(getUnixMillis()))
  JS_Call(ctx, argv[0], this, 1, cast[JSValueConstArray](unsafeAddr arg0.vc))

jsClassDef(Window):
  jsextends EventTargetDef

  jsufget Window, document

  proc addWindowEvents(ctx: JSContext): Opt[void] =
    let ctxOpaque = ctx.getOpaque()
    if ctxOpaque == nil:
      return ok()
    ctx.addEventGetSetObj(ctxOpaque.global, classDef.id, WindowEvents)

  proc finalize(rt: JSRuntime; window: Window) {.jsfin.} =
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
    rt.mark(window.settings.moduleMap, markFunc)
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
        let opaque = if data of ConnectData:
          ConnectData(data).opaque
        elif data of OngoingData:
          let data = OngoingData(data)
          rt.markObj(data.response, markFunc)
          data.response.opaque
        else:
          nil
        if opaque of LoadSheetEnv:
          rt.mark(LoadSheetEnv(opaque), markFunc)
        elif opaque of JSFetchOpaque:
          let opaque = JSFetchOpaque(opaque)
          JS_MarkValue(rt, opaque.resolve, markFunc)
          JS_MarkValue(rt, opaque.reject, markFunc)
        elif opaque of XHROpaque:
          rt.mark(XHROpaque(opaque), markFunc)
        elif opaque of FetchModuleEnv:
          rt.mark(FetchModuleEnv(opaque), markFunc)
        elif opaque of ToBlobEnv:
          rt.mark(ToBlobEnv(opaque), markFunc)
    for it in window.pendingCanvasCtls:
      rt.markObj(it, markFunc)
    rt.mark(window.timeouts, markFunc)

  proc fetch(ctx: JSContext; window: Window; input: JSValueConst;
      init = JS_UNDEFINED.vc): JSValue {.jsfunc.} =
    let input = ?newRequest(ctx, input, init)
    if not window.checkCORSRequest(input):
      discard ctx.throwNetworkError()
      let res = ?ctx.newRejectedPromise()
      return res.toJSValue()
    var resolve: JSCallback
    var reject: JSCallback
    let res = ?ctx.newPromiseCapability(resolve, reject)
    let opaque = JSFetchOpaque(
      ctx: JS_DupContext(ctx),
      resolve: resolve,
      reject: reject
    )
    window.loader.fetch(input, jsFinish, opaque)
    res.toJSValue()

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

  proc origin(window: Window): Str {.jsrfget.} =
    return Location(window).origin

  # See twtstr for the actual implementations.
  proc atob(ctx: JSContext; window: Window; data: DOMString): JSValue {.jsfunc.} =
    var s: Str
    if (let r = s.atob(data.toOpenArray()); r.isErr):
      return JS_ThrowDOMException(ctx, "InvalidCharacterError", r.error)
    return JS_NewNarrowStringLen(ctx, s.toCStringConst(), csize_t(s.len))

  proc btoa(ctx: JSContext; window: Window; data: JSValueConst): JSValue
      {.jsfunc.} =
    let data = ?trace(JS_ToString(ctx, data))
    var s: ByteString
    if ctx.fromJS(data.vc, s).isErr:
      return JS_ThrowDOMException(ctx, "InvalidCharacterError",
        "invalid character in string")
    var buf = initGrowbuf()
    buf.addBtoa(s.toOpenArray())
    ctx.toJS(buf)

  proc alert(window: Window; s: DOMString) {.jsfunc.} =
    window.console.error(s.asStr)

  proc getEvent(ctx: JSContext; window: Window): JSValue {.jsrfget: "event".} =
    if window.event == nil:
      return JS_UNDEFINED
    return ctx.toJS(window.event)

  proc postMessage(ctx: JSContext; window: Window; value: JSValueConst):
      Opt[void] {.jsfunc.} =
    let s = ?ctx.serialize(value)
    let ctx = window.jsctx # target realm
    let data = ?trace(ctx.deserialize(s))
    ctx.queueTask(jtsPostMessage, postMessageJob, PostMessageEnv(data: data))

  proc requestAnimationFrame(ctx: JSContext; window: Window;
      callback: JSCallback): JSValue {.jsfunc.} =
    let handler = ?ctx.newCFunction(animationFrameHandler,
      "animation frame handler", 1)
    #TODO hack, do this properly
    let res = window.timeouts.setTimeout(ctx, ttTimeout, handler.value, 0,
      callback.value)
    ctx.toJS(res)

  proc getComputedStyle(ctx: JSContext; window: Window; element: Element;
      pseudoElt = JS_UNDEFINED.vc): Opt[CSSStyleDeclaration] {.jsfunc.} =
    return ctx.getComputedStyle0(window, element, pseudoElt)

  proc queueMicrotask(ctx: JSContext; window: Window; fun: JSCallback):
      JSValue {.jsfunc.} =
    ?ctx.enqueueJob(microtaskJob, fun.value)
    return JS_UNDEFINED

  proc matchMedia(window: Window; s: CSSOMString): MediaQueryList {.jsnfunc.} =
    var ctx = initCSSParser(s)
    let mqlist = ctx.parseMediaQueryList(window.settings.scriptAttrsp)
    jsNew MediaQueryListObj(
      matches: mqlist.appliesScript(addr window.settings),
      media: mqlist.toStr()
    )

  proc getPerformance(ctx: JSContext; window: Window): JSValue {.
      jsrfget: "performance".} =
    if window.internalPerformance == nil:
      window.internalPerformance = newPerformance(window.timeOrigin,
        window.settings.scripting)
    ctx.toJSNew(window.internalPerformance)

  proc customElements(window: Window): CustomElementRegistry {.jsfget.} =
    window.document.customElements

  proc open(ctx: JSContext; window: Window; s: Str): JSValue {.jsuffunc.} =
    ctx.open(window, s)

proc normalizeModuleName(ctx: JSContext; baseName, name: cstringConst;
    opaque: pointer): cstring {.cdecl.} =
  let sname = cstring(name).toStr()
  let url = parseURL0(sname)
  if url != nil:
    return js_strdup(ctx, name)
  if name[0] == '.' and name[1] == '.' and name[2] == '/' or
      name[0] == '.' and name[1] == '/' or
      name[0] == '/':
    let url = parseURL0(sname, parseURL0(cstring(baseName).toStr()))
    if url != nil:
      let surl = url.toStr()
      return js_strdup(ctx, surl.toCStringConst)
  #TODO importmap
  JS_ThrowTypeError(ctx, "relative module names must start with ./, ../ or /")
  return nil

proc loadJSModule(ctx: JSContext; moduleName: cstringConst; opaque: pointer):
    JSModuleDef {.cdecl.} =
  let window = ctx.getWindow()
  let name = cstring(moduleName).toStr()
  let url = parseURL0(name)
  if url == nil:
    JS_ThrowTypeError(ctx, "invalid URL: %s", moduleName)
    return nil
  let request = newRequest(url)
  if not window.checkCORSRequest(request):
    JS_ThrowTypeError(ctx, "CORS request to %s not allowed", moduleName)
    return nil
  var module = window.settings.moduleMap.get(url, mtJavascript)
  if module == nil:
    let response = window.loader.doRequest(request)
    if response.stream == nil:
      JS_ThrowTypeError(ctx, "Failed to load module %s", moduleName)
      return nil
    window.loader.resume(response)
    let source = response.stream.readAll()
    window.loader.close(response)
    #TODO ScriptOptions
    module = ctx.newJSModuleScript(source, url, ScriptOptions(),
      window.settings)
    if JS_IsException(module.script.record):
      return nil
    window.settings.moduleMap.put(url, mtJavascript, module)
    if ctx.setImportMeta(module.script.record.vc, false) == fjErr:
      return nil
  # it seems QJS treats the return value as a const
  return cast[JSModuleDef](JS_VALUE_GET_PTR(module.script.record.vc))

proc rejectionHandler(ctx: JSContext; promise, reason: JSValueConst;
    isHandled: JS_BOOL; opaque: pointer) {.cdecl.} =
  if isHandled == 0:
    let window = ctx.getGlobal()
    var buf = initGrowbuf()
    var s: Str
    if fromJS(ctx, reason, s).isOk:
      buf.addM(s, '\n')
    var ss: Str
    if ctx.fromJSGetProp(reason, "stack", ss).isOk:
      buf &= ss
    if window.document != nil:
      window.console.error(str("Unhandled promise in document"),
        window.document.url.toStr(), buf.toStr())
    else:
      window.console.error(str("(Unhandled promise)"), buf.toStr())
    window.console.flush()

proc windowPropsGetOwnProperty(ctx: JSContext; desc: ptr JSPropertyDescriptor;
    this: JSValueConst; prop: JSAtom): cint {.cdecl.} =
  var window: Window
  discard ctx.fromJS(ctx.getOpaque().global.value, window)
  let document = window.document
  if document != nil:
    var id: CAtomRaw
    if ctx.fromJSView(prop, id).isErr:
      return -1
    if id == CAtomNull:
      return 0
    let element = document.getElementsById(id.view())
    if element != nil:
      if desc != nil:
        let element = ctx.toJS(element)
        if JS_IsException(element.vc):
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
  let name = ?trace(JS_NewString(ctx, "WindowProperties"))
  let parentProto = ctx.getClassProto(EventTargetDef.id)
  let proto = ?trace(JS_NewObjectProtoClass(ctx, parentProto.value, res))
  # must circumvent the exotic handler here
  if JS_DefinePropertyValue(ctx, proto.vc, ctx.getAtom(jsyToStringTag),
      name.toJSValue(), JS_PROP_CONFIGURABLE or JS_PROP_NO_EXOTIC) < 0:
    return JS_EXCEPTION
  proto.toJSValue()

proc addWindowModule(ctx: JSContext): JSCode =
  ?ctx.addEventTarget()
  let proto = ?trace(ctx.addWindowProperties())
  ?ctx.registerGlobalClass(WindowDef, proto.vc)
  event.windowClassID = WindowDef.id
  fjOk

proc addCommonModules(ctx: JSContext; window: Window; url: URL): Opt[void] =
  ?ctx.setGlobal(window)
  ?ctx.addEventModule()
  ?ctx.addWindowEvents()
  ?ctx.registerNamespaceFree(CSSDef)
  ?ctx.registerClass(MediaQueryListDef)
  ?ctx.registerClass(ResizeObserverDef)
  JS_SetHostPromiseRejectionTracker(JS_GetRuntime(ctx), rejectionHandler, nil)
  ?ctx.addConsoleModule()
  ?ctx.addStorageModule()
  ?ctx.addNavigatorModule(url)
  ?ctx.addDOMExceptionModule()
  ?ctx.addDOMRectModule()
  ?ctx.addDOMModule()
  ?ctx.addFormModule()
  ?ctx.addCanvasModule()
  ?ctx.addXMLModule()
  ?ctx.addURLModule()
  ?ctx.addHTMLModule()
  ?ctx.addIntlModule()
  ?ctx.addBlobModule()
  ?ctx.addFileReaderModule()
  ?ctx.addXMLHttpRequestModule()
  ?ctx.addHeadersModule()
  ?ctx.addRequestModule()
  ?ctx.addResponseModule()
  ?ctx.addEncodingModule()
  ctx.addPerformanceModule()

proc getConsole(ctx: JSContext): Console {.exportc: "cha_$1".} =
  ctx.getGlobal().console

proc getLoader(ctx: JSContext): FileLoader {.exportc: "cha_$1".} =
  ctx.getGlobal().loader

proc addScripting(window: Window; ctx: JSContext; url: URL): Opt[void] =
  if window == nil:
    JS_ThrowOutOfMemory(ctx)
    return err()
  let rt = JS_GetRuntime(ctx)
  let ctxOpaque = ctx.getOpaque()
  ?ctx.addCommonModules(window, url)
  if ctxOpaque != nil:
    JS_SetModuleLoaderFunc(rt, normalizeModuleName, loadJSModule, nil)
    if window.settings.scripting == smApp:
      window.settings.scriptAttrsp = window.settings.attrsp
    else:
      window.settings.scriptAttrsp = unsafeAddr dummyAttrs
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
    userAgent, referrer, contentType: Str): Window =
  let console = newConsole(chaStderr)
  let ctx = if scripting != smFalse:
    rt.newJSContext()
  else:
    rt.newDummyContext()
  if ctx.addWindowModule().isErr:
    console.error("failed to initialize window")
    console.writeException(ctx)
    quit(1)
  let window = jsNew WindowObj(
    jsctx: ctx,
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
      contentType: contentType.toAtom(),
    ),
    imageTypes: imageTypes,
    userAgent: userAgent,
    referrer: referrer,
    urandom: urandom,
    importMapsAllowed: true,
    timeOrigin: getTime(scripting)
  )
  if addScripting(window, ctx, url).isErr:
    console.error("failed to initialize JS")
    console.writeException(ctx)
    quit(1)
  rt.getOpaque().logExceptionCb = script.logException
  return window

proc newClient*(ctx: JSContext; loader: FileLoader; urandom: PosixStream):
    Window =
  # global object in the pager
  if ctx.addWindowModule().isErr or ctx.addURLModule().isErr:
    return Window(nil)
  let console = newConsole(chaStderr)
  let window = jsNew WindowObj(
    jsctx: ctx,
    loader: loader,
    urandom: urandom,
    console: console,
    settings: EnvironmentSettings(scripting: smApp),
    dangerAlwaysSameOrigin: true,
    timeOrigin: getTime(smApp)
  )
  let url = parseURL0("about:blank")
  if window == nil or url == nil:
    JS_ThrowOutOfMemory(ctx)
    return Window(nil)
  if ctx.addCommonModules(window, url).isErr:
    return Window(nil)
  window.document = newDocument(url)
  if window.document == nil:
    JS_ThrowOutOfMemory(ctx)
    return Window(nil)
  window

{.pop.} # raises: []
