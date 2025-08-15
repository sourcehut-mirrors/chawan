{.push raises: [].}

import std/options
import std/os
import std/strutils
import std/tables

import chagashi/charset
import config/chapath
import config/conftypes
import config/cookie
import config/mailcap
import config/mimetypes
import config/toml
import config/urimethodmap
import css/cssparser
import html/script
import io/dynstream
import monoucha/fromjs
import monoucha/javascript
import monoucha/jspropenumlist
import monoucha/jsregex
import monoucha/jstypes
import monoucha/quickjs
import monoucha/tojs
import server/headers
import types/cell
import types/color
import types/jscolor
import types/opt
import types/url
import utils/myposix
import utils/regexutils
import utils/twtstr

type
  StyleString* = distinct string

  ChaPathResolved* = distinct string

  ActionMap = object
    t: Table[string, string]

  FormRequestType* = enum
    frtHttp = "http"
    frtFtp = "ftp"
    frtData = "data"
    frtMailto = "mailto"

  SiteConfig* = ref object
    url*: Option[Regex]
    host*: Option[Regex]
    rewriteUrl*: Option[JSValueFunction]
    shareCookieJar*: Option[string]
    proxy*: Option[URL]
    defaultHeaders*: Headers
    cookie*: Option[CookieMode]
    refererFrom*: Option[bool]
    scripting*: Option[ScriptingMode]
    documentCharset*: seq[Charset]
    images*: Option[bool]
    styling*: Option[bool]
    insecureSslNoVerify*: Option[bool]
    autofocus*: Option[bool]
    metaRefresh*: Option[MetaRefresh]
    history*: Option[bool]
    markLinks*: Option[bool]
    userStyle*: Option[StyleString]

  OmniRule* = ref object
    match*: Option[Regex]
    substituteUrl*: Option[JSValueFunction]

  StartConfig = object
    visualHome* {.jsgetset.}: string
    startupScript* {.jsgetset.}: string
    headless* {.jsgetset.}: HeadlessMode
    consoleBuffer* {.jsgetset.}: bool

  SearchConfig = object
    wrap* {.jsgetset.}: bool
    ignoreCase* {.jsgetset.}: Option[bool]

  EncodingConfig = object
    displayCharset* {.jsgetset.}: Option[Charset]
    documentCharset* {.jsgetset.}: seq[Charset]

  CommandConfig = object
    jsObj*: JSValue
    init*: seq[tuple[k, cmd: string]] # initial k/v map
    map*: Table[string, JSValue] # qualified name -> function

  ExternalConfig = object
    tmpdir* {.jsgetset.}: ChaPathResolved
    editor* {.jsgetset.}: string
    mailcap*: Mailcap
    autoMailcap*: AutoMailcap
    mimeTypes*: MimeTypes
    cgiDir* {.jsgetset.}: seq[ChaPathResolved]
    urimethodmap*: URIMethodMap
    bookmark* {.jsgetset.}: ChaPathResolved
    historyFile*: ChaPathResolved
    historySize* {.jsgetset.}: int32
    cookieFile*: ChaPathResolved
    downloadDir* {.jsgetset.}: ChaPathResolved
    showDownloadPanel* {.jsgetset.}: bool
    w3mCgiCompat* {.jsgetset.}: bool
    copyCmd* {.jsgetset.}: string
    pasteCmd* {.jsgetset.}: string

  InputConfig = object
    viNumericPrefix* {.jsgetset.}: bool
    useMouse* {.jsgetset.}: bool
    bracketedPaste* {.jsgetset.}: bool
    wheelScroll* {.jsgetset.}: int32
    sideWheelScroll* {.jsgetset.}: int32

  NetworkConfig = object
    maxRedirect* {.jsgetset.}: int32
    maxNetConnections* {.jsgetset.}: int32
    prependScheme* {.jsgetset.}: string
    proxy* {.jsgetset.}: URL
    defaultHeaders* {.jsgetset.}: Headers
    allowHttpFromFile* {.jsgetset.}: bool

  DisplayConfig = object
    colorMode* {.jsgetset.}: Option[ColorMode]
    formatMode* {.jsgetset.}: Option[set[FormatFlag]]
    noFormatMode* {.jsgetset.}: set[FormatFlag]
    imageMode* {.jsgetset.}: Option[ImageMode]
    sixelColors* {.jsgetset.}: Option[int32]
    altScreen* {.jsgetset.}: Option[bool]
    highlightColor* {.jsgetset.}: ARGBColor
    highlightMarks* {.jsgetset.}: bool
    doubleWidthAmbiguous* {.jsgetset.}: bool
    minimumContrast* {.jsgetset.}: int32
    forceClear* {.jsgetset.}: bool
    setTitle* {.jsgetset.}: Option[bool]
    defaultBackgroundColor* {.jsgetset.}: Option[RGBColor]
    defaultForegroundColor* {.jsgetset.}: Option[RGBColor]
    queryDa1* {.jsgetset.}: bool
    columns* {.jsgetset.}: int32
    lines* {.jsgetset.}: int32
    pixelsPerColumn* {.jsgetset.}: int32
    pixelsPerLine* {.jsgetset.}: int32
    forceColumns* {.jsgetset.}: bool
    forceLines* {.jsgetset.}: bool
    forcePixelsPerColumn* {.jsgetset.}: bool
    forcePixelsPerLine* {.jsgetset.}: bool

  ProtocolConfig* = ref object
    formRequest*: FormRequestType

  BufferSectionConfig* = object
    styling* {.jsgetset.}: bool
    scripting* {.jsgetset.}: ScriptingMode
    images* {.jsgetset.}: bool
    cookie* {.jsgetset.}: CookieMode
    refererFrom* {.jsgetset.}: bool
    autofocus* {.jsgetset.}: bool
    metaRefresh* {.jsgetset.}: MetaRefresh
    history* {.jsgetset.}: bool
    markLinks* {.jsgetset.}: bool
    userStyle*: StyleString #TODO getset

  Config* = ref object
    jsvfns*: seq[JSValueFunction]
    arraySeen*: TableRef[string, int] # table arrays seen
    dir* {.jsget.}: string
    `include` {.jsget.}: seq[ChaPathResolved]
    start* {.jsget.}: StartConfig
    buffer* {.jsget.}: BufferSectionConfig
    search* {.jsget.}: SearchConfig
    encoding* {.jsget.}: EncodingConfig
    external* {.jsget.}: ExternalConfig
    network* {.jsget.}: NetworkConfig
    input* {.jsget.}: InputConfig
    display* {.jsget.}: DisplayConfig
    #TODO getset
    protocol*: Table[string, ProtocolConfig]
    siteconf*: OrderedTable[string, SiteConfig]
    omnirule*: OrderedTable[string, OmniRule]
    cmd*: CommandConfig
    page* {.jsget.}: ActionMap
    line* {.jsget.}: ActionMap

jsDestructor(ActionMap)
jsDestructor(StartConfig)
jsDestructor(SearchConfig)
jsDestructor(EncodingConfig)
jsDestructor(ExternalConfig)
jsDestructor(NetworkConfig)
jsDestructor(DisplayConfig)
jsDestructor(BufferSectionConfig)
jsDestructor(Config)

converter toStr*(p: ChaPathResolved): lent string {.inline.} =
  return string(p)

proc fromJS(ctx: JSContext; val: JSValueConst; res: var ChaPathResolved):
    Opt[void] =
  return ctx.fromJS(val, string(res))

proc toJS*(ctx: JSContext; cookie: CookieMode): JSValue =
  case cookie
  of cmReadOnly: return JS_TRUE
  of cmNone: return JS_FALSE
  of cmSave: return JS_NewString(ctx, "save")

proc `[]=`(a: var ActionMap; b: string; c: sink string) =
  a.t[b] = c

# Can't be lent string on 2.0.4 yet.
template `[]`*(a: ActionMap; b: string): string =
  a.t[b]

template getOrDefault(a: ActionMap; b: string): string =
  a.t.getOrDefault(b)

proc contains*(a: ActionMap; b: string): bool =
  return b in a.t

func getRealKey(key: string): string =
  var realk = ""
  var control = 0
  var meta = 0
  var skip = false
  for c in key:
    if c == '\\':
      skip = true
    elif skip:
      realk &= c
      skip = false
    elif c == 'M' and meta == 0:
      inc meta
    elif c == 'C' and control == 0:
      inc control
    elif c == '-' and control == 1:
      inc control
    elif c == '-' and meta == 1:
      inc meta
    elif meta == 1:
      realk &= 'M' & c
      meta = 0
    elif control == 1:
      realk &= 'C' & c
      control = 0
    else:
      if meta == 2:
        realk &= '\e'
        meta = 0
      if control == 2:
        realk &= getControlChar(c)
        control = 0
      else:
        realk &= c
  if control == 1:
    realk &= 'C'
  if meta == 1:
    realk &= 'M'
  if skip:
    realk &= '\\'
  move(realk)

proc getter(ctx: JSContext; a: var ActionMap; s: string): JSValue
    {.jsgetownprop.} =
  a.t.withValue(s, p):
    return ctx.toJS(p[])
  return JS_NULL

proc setter(a: var ActionMap; k, v: string) {.jssetprop.} =
  let k = getRealKey(k)
  if k == "":
    return
  a[k] = v
  var teststr = k
  teststr.setLen(teststr.high)
  for i in countdown(k.high, 0):
    discard a.t.hasKeyOrPut(teststr, "window.feedNext()")
    teststr.setLen(i)

proc delete(a: var ActionMap; k: string): bool {.jsdelprop.} =
  let k = getRealKey(k)
  let ina = k in a
  a.t.del(k)
  return ina

func names(ctx: JSContext; a: var ActionMap): JSPropertyEnumList
    {.jspropnames.} =
  let L = uint32(a.t.len)
  var list = newJSPropertyEnumList(ctx, L)
  for key in a.t.keys:
    list.add(key)
  return list

type ConfigParser = object
  jsctx: JSContext
  config: Config
  dir: string
  warnings: seq[string]

proc parseConfigValue(ctx: var ConfigParser; x: var object; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var ref object; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var bool; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var string; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var ChaPath; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue[T](ctx: var ConfigParser; x: var seq[T]; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var Charset; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var int32; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var int64; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var ScriptingMode; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var HeadlessMode; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var CookieMode; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue[T](ctx: var ConfigParser; x: var Option[T]; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var ARGBColor; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var RGBColor; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var ActionMap; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue[U; V](ctx: var ConfigParser; x: var Table[U, V];
  v: TomlValue; k: string): Err[string]
proc parseConfigValue[U; V](ctx: var ConfigParser; x: var OrderedTable[U, V];
  v: TomlValue; k: string): Err[string]
proc parseConfigValue[U; V](ctx: var ConfigParser; x: var TableRef[U, V];
  v: TomlValue; k: string): Err[string]
proc parseConfigValue[T](ctx: var ConfigParser; x: var set[T]; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var Regex; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var URL; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var JSValueFunction;
  v: TomlValue; k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var ChaPathResolved;
  v: TomlValue; k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var MimeTypes; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var Mailcap; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var AutoMailcap; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var URIMethodMap; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var CommandConfig; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var StyleString; v: TomlValue;
  k: string): Err[string]
proc parseConfigValue(ctx: var ConfigParser; x: var Headers; v: TomlValue;
  k: string): Err[string]

proc typeCheck(v: TomlValue; t: TomlValueType; k: string): Err[string] =
  if v.t != t:
    return err(k & ": invalid type (got " & $v.t & ", expected " & $t & ")")
  ok()

proc typeCheck(v: TomlValue; t: set[TomlValueType]; k: string): Err[string] =
  if v.t notin t:
    return err(k & ": invalid type (got " & $v.t & ", expected " & $t & ")")
  ok()

proc warnValuesLeft(ctx: var ConfigParser; v: TomlValue; k: string) =
  for fk in v.keys:
    ctx.warnings.add("unrecognized option " & k & fk)

proc parseConfigValue(ctx: var ConfigParser; x: var object; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtTable, k)
  if v.tab.clear:
    x = default(typeof(x))
  when x isnot typeof(Config()[]):
    let k = k & '.'
  for fk, fv in x.fieldPairs:
    when fk notin ["jsvfns", "arraySeen", "dir"]:
      const kebabk = camelToKebabCase(fk)
      var x: TomlValue
      if v.pop(kebabk, x):
        ?ctx.parseConfigValue(fv, x, k & kebabk)
  ctx.warnValuesLeft(v, k)
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var ref object; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtTable, k)
  if x == nil:
    new(x)
  ctx.parseConfigValue(x[], v, k)

proc parseConfigValue[U, V](ctx: var ConfigParser; x: var Table[U, V];
    v: TomlValue; k: string): Err[string] =
  ?typeCheck(v, tvtTable, k)
  if v.tab.clear:
    x.clear()
  for kk, vv in v:
    let kkk = k & "[" & kk & "]"
    ?ctx.parseConfigValue(x.mgetOrPut(kk, default(V)), vv, kkk)
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var Headers;
    v: TomlValue; k: string): Err[string] =
  ?typeCheck(v, tvtTable, k)
  if v.tab.clear or x == nil:
    x = newHeaders(hgRequest)
  for kk, vv in v:
    ?typeCheck(vv, tvtString, k & "[" & kk & "]")
    x[kk] = vv.s
  ok()

proc parseConfigValue[U, V](ctx: var ConfigParser; x: var OrderedTable[U, V];
    v: TomlValue; k: string): Err[string] =
  ?typeCheck(v, tvtTable, k)
  if v.tab.clear:
    x.clear()
  for kk, vv in v:
    let kkk = k & "[" & kk & "]"
    ?ctx.parseConfigValue(x.mgetOrPut(kk, default(V)), vv, kkk)
  ok()

proc parseConfigValue[U, V](ctx: var ConfigParser; x: var TableRef[U, V];
    v: TomlValue; k: string): Err[string] =
  if x == nil:
    x = TableRef[U, V]()
  ctx.parseConfigValue(x[], v, k)

proc parseConfigValue(ctx: var ConfigParser; x: var bool; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtBoolean, k)
  x = v.b
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var string; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  x = v.s
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var ChaPath;
    v: TomlValue; k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  x = ChaPath(v.s)
  ok()

proc parseConfigValue[T](ctx: var ConfigParser; x: var seq[T]; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, {tvtString, tvtArray}, k)
  if v.t != tvtArray:
    var y: T
    ?ctx.parseConfigValue(y, v, k)
    x = @[move(y)]
  else:
    x.setLen(0)
    for i in 0 ..< v.a.len:
      var y: T
      ?ctx.parseConfigValue(y, v.a[i], k & "[" & $i & "]")
      x.add(move(y))
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var Charset; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  x = getCharset(v.s)
  if x == CHARSET_UNKNOWN:
    return err(k & ": unknown charset '" & v.s & "'")
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var int32; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtInteger, k)
  x = int32(v.i)
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var int64; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtInteger, k)
  x = v.i
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var ScriptingMode; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, {tvtString, tvtBoolean}, k)
  if v.t == tvtBoolean:
    x = if v.b: smTrue else: smFalse
  elif v.s == "app":
    x = smApp
  else:
    return err(k & ": unknown scripting mode '" & v.s & "'")
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var HeadlessMode; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, {tvtString, tvtBoolean}, k)
  if v.t == tvtBoolean:
    x = if v.b: hmTrue else: hmFalse
  elif v.s == "dump":
    x = hmDump
  else:
    return err(k & ": unknown headless mode '" & v.s & "'")
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var CookieMode; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, {tvtString, tvtBoolean}, k)
  if v.t == tvtBoolean:
    x = if v.b: cmReadOnly else: cmNone
  elif v.s == "save":
    x = cmSave
  else:
    return err(k & ": unknown cookie mode '" & v.s & "'")
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var ARGBColor; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  let c = parseARGBColor(v.s)
  if c.isNone:
    return err(k & ": invalid color '" & v.s & "'")
  x = c.get
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var RGBColor; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  let c = parseLegacyColor(v.s)
  if c.isErr:
    return err(k & ": invalid color '" & v.s & "'")
  x = c.get
  ok()

proc parseConfigValue[T](ctx: var ConfigParser; x: var Option[T]; v: TomlValue;
    k: string): Err[string] =
  if v.t == tvtString and v.s == "auto":
    x = none(T)
  else:
    var y: T
    ?ctx.parseConfigValue(y, v, k)
    x = some(move(y))
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var ActionMap; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtTable, k)
  for kk, vv in v:
    ?typeCheck(vv, tvtString, k & "[" & kk & "]")
    let rk = getRealKey(kk)
    var buf = ""
    for c in rk.toOpenArray(0, rk.high - 1):
      buf &= c
      x[buf] = "window.feedNext()"
    x[rk] = vv.s
  ok()

proc parseConfigValue[T: enum](ctx: var ConfigParser; x: var T; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  let e = strictParseEnum[T](v.s)
  if e.isErr:
    return err(k & ": invalid value '" & v.s & "'")
  x = e.get
  ok()

proc parseConfigValue[T](ctx: var ConfigParser; x: var set[T]; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, {tvtString, tvtArray}, k)
  if v.t == tvtString:
    var xx: T
    ?ctx.parseConfigValue(xx, v, k)
    x = {xx}
  else:
    x = {}
    for i in 0 ..< v.a.len:
      let kk = k & "[" & $i & "]"
      var xx: T
      ?ctx.parseConfigValue(xx, v.a[i], kk)
      x.incl(xx)
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var Regex; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  let y = compileMatchRegex(v.s)
  if y.isErr:
    return err(k & ": invalid regex (" & y.error & ")")
  x = y.get
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var URL; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  let y = parseURL0(v.s)
  if y == nil:
    return err(k & ": invalid URL " & v.s)
  x = y
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var JSValueFunction;
    v: TomlValue; k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  let fun = ctx.jsctx.eval(v.s, "<config>", JS_EVAL_TYPE_GLOBAL)
  if JS_IsException(fun):
    return err(k & ": " & ctx.jsctx.getExceptionMsg())
  if not JS_IsFunction(ctx.jsctx, fun):
    return err(k & ": not a function")
  x = JSValueFunction(fun: fun)
  ctx.config.jsvfns.add(x) # so we can clean it up on exit
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var ChaPathResolved;
    v: TomlValue; k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  let y = ChaPath(v.s).unquote(ctx.config.dir)
  if y.isErr:
    return err(k & ": " & y.error)
  x = ChaPathResolved(y.get)
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var MimeTypes; v: TomlValue;
    k: string): Err[string] =
  var paths: seq[ChaPathResolved]
  ?ctx.parseConfigValue(paths, v, k)
  x = MimeTypes.default
  for p in paths:
    let ps = newPosixStream(p)
    if ps != nil:
      let src = ps.readAllOrMmap()
      x.parseMimeTypes(src.toOpenArray(), DefaultImages)
      deallocMem(src)
      ps.sclose()
  ok()

const DefaultMailcap = block:
  var mailcap: Mailcap
  const name = "res/mailcap"
  doAssert mailcap.parseMailcap(staticRead(name), name).isOk
  mailcap

proc parseConfigValue(ctx: var ConfigParser; x: var Mailcap; v: TomlValue;
    k: string): Err[string] =
  var paths: seq[ChaPathResolved]
  ?ctx.parseConfigValue(paths, v, k)
  x = Mailcap.default
  for p in paths:
    let ps = newPosixStream(p)
    if ps != nil:
      let src = ps.readAllOrMmap()
      let res = x.parseMailcap(src.toOpenArray(), p)
      deallocMem(src)
      ps.sclose()
      if res.isErr:
        ctx.warnings.add(res.error)
  x.add(DefaultMailcap)
  ok()

const DefaultAutoMailcap = block:
  var mailcap: Mailcap
  const name = "res/auto.mailcap"
  doAssert mailcap.parseMailcap(staticRead(name), name).isOk
  mailcap

proc parseConfigValue(ctx: var ConfigParser; x: var AutoMailcap;
    v: TomlValue; k: string): Err[string] =
  var path: ChaPathResolved
  ?ctx.parseConfigValue(path, v, k)
  x = AutoMailcap(path: path)
  let ps = newPosixStream(path)
  if ps != nil:
    let src = ps.readAllOrMmap()
    let res = x.entries.parseMailcap(src.toOpenArray(), path)
    deallocMem(src)
    ps.sclose()
    if res.isErr:
      ctx.warnings.add(res.error)
  x.entries.add(DefaultAutoMailcap)
  ok()

const DefaultURIMethodMap = parseURIMethodMap(staticRead"res/urimethodmap")

proc parseConfigValue(ctx: var ConfigParser; x: var URIMethodMap; v: TomlValue;
    k: string): Err[string] =
  var paths: seq[ChaPathResolved]
  ?ctx.parseConfigValue(paths, v, k)
  x = URIMethodMap.default
  for p in paths:
    let ps = newPosixStream(p)
    if ps != nil:
      x.parseURIMethodMap(ps.readAll())
      ps.sclose()
  x.append(DefaultURIMethodMap)
  ok()

func isCompatibleIdent(s: string): bool =
  if s.len == 0 or s[0] notin AsciiAlpha + {'_', '$'}:
    return false
  for i in 1 ..< s.len:
    if s[i] notin AsciiAlphaNumeric + {'_', '$'}:
      return false
  return true

proc parseConfigValue(ctx: var ConfigParser; x: var CommandConfig; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtTable, k)
  for kk, vv in v:
    let kkk = k & "." & kk
    ?typeCheck(vv, {tvtTable, tvtString}, kkk)
    if not kk.isCompatibleIdent():
      return err(kkk & ": invalid command name")
    if vv.t == tvtTable:
      ?ctx.parseConfigValue(x, vv, kkk)
    else: # tvtString
      x.init.add((kkk.substr("cmd.".len), vv.s))
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var StyleString; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  var y = ""
  var parser = initCSSParser(v.s)
  var j = 0
  for it in parser.consumeImports():
    var parser2 = initCSSParserSink(it.prelude)
    if parser2.skipBlanksCheckHas().isErr:
      break
    let tok = parser2.consume()
    if parser2.skipBlanksCheckDone().isErr:
      break
    if tok.t != cttString:
      return err(k & ": wrong CSS import (unexpected token)")
    let path = ChaPath(tok.s).unquote(ctx.config.dir)
    if path.isErr:
      return err(k & ": wrong CSS import (" & tok.s & " is not a valid path)")
    let ps = newPosixStream(path.get)
    if ps == nil:
      return err(k & ": wrong CSS import (file " & tok.s & " not found)")
    y &= ps.readAll()
    j = parser.i
  y &= v.s.substr(j)
  x = StyleString(move(y))
  ok()

proc parseConfig*(config: Config; dir: string; buf: openArray[char];
  warnings: var seq[string]; jsctx: JSContext; name: string;
  laxnames = false): Err[string]

proc parseConfig(config: Config; dir: string; t: TomlValue;
    warnings: var seq[string]; jsctx: JSContext): Err[string] =
  var ctx = ConfigParser(config: config, dir: dir, jsctx: jsctx)
  ?ctx.parseConfigValue(config[], t, "")
  for name, value in config.omnirule:
    if value.match.isNone:
      return err("omnirule." & name & ": missing match regex")
  #TODO: for omnirule/siteconf, check if substitution rules are specified?
  while config.`include`.len > 0:
    #TODO: warn about recursive includes
    var includes = config.`include`
    config.`include`.setLen(0)
    for s in includes:
      let ps = newPosixStream(s)
      if ps == nil:
        return err("include file not found: " & s)
      ?config.parseConfig(dir, ps.readAll(), warnings, jsctx, s.afterLast('/'))
      ps.sclose()
  warnings.add(ctx.warnings)
  ok()

proc parseConfig*(config: Config; dir: string; buf: openArray[char];
    warnings: var seq[string]; jsctx: JSContext; name: string;
    laxnames = false): Err[string] =
  let toml = parseToml(buf, dir / name, laxnames, config.arraySeen)
  if toml.isOk:
    return config.parseConfig(dir, toml.get, warnings, jsctx)
  return err("fatal error: failed to parse config\n" & toml.error)

template getNormalAction*(config: Config; s: string): string =
  config.page.getOrDefault(s)

template getLinedAction*(config: Config; s: string): string =
  config.line.getOrDefault(s)

proc openConfig*(dir: var string; override: Option[string];
    warnings: var seq[string]): PosixStream =
  if override.isSome:
    if override.get.len > 0 and override.get[0] == '/':
      dir = parentDir(override.get)
      return newPosixStream(override.get)
    else:
      let path = myposix.getcwd() / override.get
      dir = parentDir(path)
      return newPosixStream(path)
  dir = getEnv("CHA_DIR")
  if dir != "":
    return newPosixStream(dir / "config.toml")
  dir = getEnv("XDG_CONFIG_HOME")
  if dir != "":
    dir = dir / "chawan"
    return newPosixStream(dir / "config.toml")
  dir = expandPath("~/.config/chawan")
  if (let fs = newPosixStream(dir / "config.toml"); fs != nil):
    return fs
  dir = expandPath("~/.chawan")
  return newPosixStream(dir / "config.toml")

# called after parseConfig returns
proc initCommands*(ctx: JSContext; config: Config): Err[string] =
  let obj = JS_NewObject(ctx)
  if JS_IsException(obj):
    return err(ctx.getExceptionMsg())
  for i in countdown(config.cmd.init.high, 0):
    let (k, cmd) = config.cmd.init[i]
    if k in config.cmd.map:
      # already in map; skip
      continue
    var objIt = JS_DupValue(ctx, obj)
    let name = k.afterLast('.')
    if name.len < k.len:
      for ss in k.substr(0, k.high - name.len - 1).split('.'):
        var prop = JS_GetPropertyStr(ctx, objIt, cstring(ss))
        if JS_IsUndefined(prop):
          prop = JS_NewObject(ctx)
          case ctx.definePropertyE(objIt, ss, JS_DupValue(ctx, prop))
          of dprException:
            JS_FreeValue(ctx, obj)
            return err(ctx.getExceptionMsg())
          else: discard
        if JS_IsException(prop):
          JS_FreeValue(ctx, obj)
          return err(ctx.getExceptionMsg())
        JS_FreeValue(ctx, objIt)
        objIt = prop
    if cmd == "":
      config.cmd.map[k] = JS_UNDEFINED
      continue
    let fun = ctx.eval(cmd, "<" & k & ">", JS_EVAL_TYPE_GLOBAL)
    if JS_IsException(fun):
      JS_FreeValue(ctx, obj)
      return err(ctx.getExceptionMsg())
    if not JS_IsFunction(ctx, fun):
      JS_FreeValue(ctx, obj)
      JS_FreeValue(ctx, fun)
      return err(k & " is not a function")
    case ctx.definePropertyE(objIt, name, JS_DupValue(ctx, fun))
    of dprException: return err(ctx.getExceptionMsg())
    else: discard
    config.cmd.map[k] = fun
    JS_FreeValue(ctx, objIt)
  config.cmd.jsObj = obj
  config.cmd.init = @[]
  ok()

proc addConfigModule*(ctx: JSContext) =
  ctx.registerType(ActionMap)
  ctx.registerType(StartConfig)
  ctx.registerType(SearchConfig)
  ctx.registerType(EncodingConfig)
  ctx.registerType(ExternalConfig)
  ctx.registerType(NetworkConfig)
  ctx.registerType(DisplayConfig)
  ctx.registerType(BufferSectionConfig, name = "BufferConfig")
  ctx.registerType(Config)

{.pop.} # raises: []
