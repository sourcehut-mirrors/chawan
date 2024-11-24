import std/options
import std/os
import std/streams
import std/strutils
import std/tables

import chagashi/charset
import config/chapath
import config/mailcap
import config/mimetypes
import config/toml
import config/urimethodmap
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
import types/cookie
import types/jscolor
import types/opt
import types/url
import utils/regexutils
import utils/twtstr

type
  ColorMode* = enum
    cmMonochrome = "monochrome"
    cmANSI = "ansi"
    cmEightBit = "eight-bit"
    cmTrueColor = "true-color"

  MetaRefresh* = enum
    mrNever = "never"
    mrAlways = "always"
    mrAsk = "ask"

  ImageMode* = enum
    imNone = "none"
    imSixel = "sixel"
    imKitty = "kitty"

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
    rewrite_url*: Option[JSValueFunction]
    cookie*: Option[bool]
    third_party_cookie*: seq[Regex]
    share_cookie_jar*: Option[string]
    referer_from*: Option[bool]
    scripting*: Option[bool]
    document_charset*: seq[Charset]
    images*: Option[bool]
    styling*: Option[bool]
    stylesheet*: Option[string]
    proxy*: Option[URL]
    default_headers*: TableRef[string, string]
    insecure_ssl_no_verify*: Option[bool]
    autofocus*: Option[bool]
    meta_refresh*: Option[MetaRefresh]

  OmniRule* = ref object
    match*: Regex
    substitute_url*: Option[JSValueFunction]

  StartConfig = object
    visual_home* {.jsgetset.}: string
    startup_script* {.jsgetset.}: string
    headless* {.jsgetset.}: bool
    console_buffer* {.jsgetset.}: bool

  CSSConfig = object
    stylesheet* {.jsgetset.}: string

  SearchConfig = object
    wrap* {.jsgetset.}: bool
    ignore_case* {.jsgetset.}: Option[bool]

  EncodingConfig = object
    display_charset* {.jsgetset.}: Option[Charset]
    document_charset* {.jsgetset.}: seq[Charset]

  CommandConfig = object
    jsObj*: JSValue
    init*: seq[tuple[k, cmd: string]] # initial k/v map
    map*: Table[string, JSValue] # qualified name -> function

  ExternalConfig = object
    tmpdir* {.jsgetset.}: ChaPathResolved
    sockdir* {.jsgetset.}: ChaPathResolved
    editor* {.jsgetset.}: string
    mailcap*: Mailcap
    mime_types*: MimeTypes
    cgi_dir* {.jsgetset.}: seq[ChaPathResolved]
    urimethodmap*: URIMethodMap
    download_dir* {.jsgetset.}: ChaPathResolved
    w3m_cgi_compat* {.jsgetset.}: bool

  InputConfig = object
    vi_numeric_prefix* {.jsgetset.}: bool
    use_mouse* {.jsgetset.}: bool

  NetworkConfig = object
    max_redirect* {.jsgetset.}: int32
    prepend_https* {.jsgetset.}: bool
    prepend_scheme* {.jsgetset.}: string
    proxy* {.jsgetset.}: URL
    default_headers* {.jsgetset.}: Table[string, string]

  DisplayConfig = object
    color_mode* {.jsgetset.}: Option[ColorMode]
    format_mode* {.jsgetset.}: Option[set[FormatFlag]]
    no_format_mode* {.jsgetset.}: set[FormatFlag]
    image_mode* {.jsgetset.}: Option[ImageMode]
    sixel_colors* {.jsgetset.}: Option[int32]
    alt_screen* {.jsgetset.}: Option[bool]
    highlight_color* {.jsgetset.}: ARGBColor
    highlight_marks* {.jsgetset.}: bool
    double_width_ambiguous* {.jsgetset.}: bool
    minimum_contrast* {.jsgetset.}: int32
    force_clear* {.jsgetset.}: bool
    set_title* {.jsgetset.}: bool
    default_background_color* {.jsgetset.}: Option[RGBColor]
    default_foreground_color* {.jsgetset.}: Option[RGBColor]
    query_da1* {.jsgetset.}: bool
    columns* {.jsgetset.}: int32
    lines* {.jsgetset.}: int32
    pixels_per_column* {.jsgetset.}: int32
    pixels_per_line* {.jsgetset.}: int32
    force_columns* {.jsgetset.}: bool
    force_lines* {.jsgetset.}: bool
    force_pixels_per_column* {.jsgetset.}: bool
    force_pixels_per_line* {.jsgetset.}: bool

  ProtocolConfig* = ref object
    form_request*: FormRequestType

  BufferSectionConfig* = object
    styling* {.jsgetset.}: bool
    scripting* {.jsgetset.}: bool
    images* {.jsgetset.}: bool
    cookie* {.jsgetset.}: bool
    referer_from* {.jsgetset.}: bool
    autofocus* {.jsgetset.}: bool
    meta_refresh* {.jsgetset.}: MetaRefresh

  Config* = ref object
    jsctx*: JSContext
    jsvfns*: seq[JSValueFunction]
    configdir* {.jsget.}: string
    `include` {.jsget.}: seq[ChaPathResolved]
    start* {.jsget.}: StartConfig
    buffer* {.jsget.}: BufferSectionConfig
    search* {.jsget.}: SearchConfig
    css* {.jsget.}: CSSConfig
    encoding* {.jsget.}: EncodingConfig
    external* {.jsget.}: ExternalConfig
    network* {.jsget.}: NetworkConfig
    input* {.jsget.}: InputConfig
    display* {.jsget.}: DisplayConfig
    #TODO getset
    protocol*: Table[string, ProtocolConfig]
    siteconf*: seq[SiteConfig]
    omnirule*: seq[OmniRule]
    cmd*: CommandConfig
    page* {.jsget.}: ActionMap
    line* {.jsget.}: ActionMap

jsDestructor(ActionMap)
jsDestructor(StartConfig)
jsDestructor(CSSConfig)
jsDestructor(SearchConfig)
jsDestructor(EncodingConfig)
jsDestructor(ExternalConfig)
jsDestructor(NetworkConfig)
jsDestructor(DisplayConfig)
jsDestructor(BufferSectionConfig)
jsDestructor(Config)

converter toStr*(p: ChaPathResolved): string {.inline.} =
  return string(p)

proc fromJS(ctx: JSContext; val: JSValue; res: var ChaPathResolved): Opt[void] =
  return ctx.fromJS(val, string(res))

proc `[]=`(a: var ActionMap; b, c: string) =
  a.t[b] = c

proc `[]`*(a: ActionMap; b: string): string =
  a.t[b]

proc contains*(a: ActionMap; b: string): bool =
  return b in a.t

proc getOrDefault(a: ActionMap; b: string): string =
  return a.t.getOrDefault(b)

proc hasKeyOrPut(a: var ActionMap; b, c: string): bool =
  return a.t.hasKeyOrPut(b, c)

func getRealKey(key: string): string =
  var realk: string
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
  return realk

proc getter(a: var ActionMap; s: string): Option[string] {.jsgetownprop.} =
  a.t.withValue(s, p):
    return some(p[])
  return none(string)

proc setter(a: var ActionMap; k, v: string) {.jssetprop.} =
  let k = getRealKey(k)
  if k == "":
    return
  a[k] = v
  var teststr = k
  teststr.setLen(teststr.high)
  for i in countdown(k.high, 0):
    if teststr notin a:
      a[teststr] = "client.feedNext()"
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

proc bindPagerKey(config: Config; key, action: string) {.jsfunc.} =
  config.page.setter(key, action)

proc bindLineKey(config: Config; key, action: string) {.jsfunc.} =
  config.line.setter(key, action)

proc openFileExpand(dir, file: string): FileStream =
  if file.len == 0:
    return nil
  if file[0] == '/':
    return newFileStream(file)
  else:
    return newFileStream(dir / file)

proc readUserStylesheet(dir, file: string): string =
  let x = ChaPath(file).unquote()
  if x.isNone:
    raise newException(ValueError, x.error)
  let s = openFileExpand(dir, x.get)
  if s != nil:
    result = s.readAll()
    s.close()

type ConfigParser = object
  config: Config
  dir: string
  warnings: seq[string]

proc parseConfigValue(ctx: var ConfigParser; x: var object; v: TomlValue;
  k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var ref object; v: TomlValue;
  k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var bool; v: TomlValue;
  k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var string; v: TomlValue;
  k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var ChaPath; v: TomlValue;
  k: string)
proc parseConfigValue[T](ctx: var ConfigParser; x: var seq[T]; v: TomlValue;
  k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var Charset; v: TomlValue;
  k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var int32; v: TomlValue;
  k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var int64; v: TomlValue;
  k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var ColorMode; v: TomlValue;
  k: string)
proc parseConfigValue[T](ctx: var ConfigParser; x: var Option[T]; v: TomlValue;
  k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var ARGBColor; v: TomlValue;
  k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var RGBColor; v: TomlValue;
  k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var ActionMap; v: TomlValue;
  k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var CSSConfig; v: TomlValue;
  k: string)
proc parseConfigValue[U; V](ctx: var ConfigParser; x: var Table[U, V];
  v: TomlValue; k: string)
proc parseConfigValue[U; V](ctx: var ConfigParser; x: var TableRef[U, V];
  v: TomlValue; k: string)
proc parseConfigValue[T](ctx: var ConfigParser; x: var set[T]; v: TomlValue;
  k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var TomlTable; v: TomlValue;
  k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var Regex; v: TomlValue;
  k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var URL; v: TomlValue;
  k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var JSValueFunction;
  v: TomlValue; k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var ChaPathResolved;
  v: TomlValue; k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var MimeTypes; v: TomlValue;
  k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var Mailcap; v: TomlValue;
  k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var URIMethodMap; v: TomlValue;
  k: string)
proc parseConfigValue(ctx: var ConfigParser; x: var CommandConfig; v: TomlValue;
  k: string)

proc typeCheck(v: TomlValue; t: TomlValueType; k: string) =
  if v.t != t:
    raise newException(ValueError, "invalid type for key " & k &
      " (got " & $v.t & ", expected " & $t & ")")

proc typeCheck(v: TomlValue; t: set[TomlValueType]; k: string) =
  if v.t notin t:
    raise newException(ValueError, "invalid type for key " & k &
      " (got " & $v.t & ", expected " & $t & ")")

proc parseConfigValue(ctx: var ConfigParser; x: var object; v: TomlValue;
    k: string) =
  typeCheck(v, tvtTable, k)
  for fk, fv in x.fieldPairs:
    when typeof(fv) isnot JSContext|seq[JSValueFunction]:
      let kebabk = snakeToKebabCase(fk)
      if kebabk in v:
        let kkk = if k != "":
          k & "." & fk
        else:
          fk
        ctx.parseConfigValue(fv, v[kebabk], kkk)

proc parseConfigValue(ctx: var ConfigParser; x: var ref object; v: TomlValue;
    k: string) =
  new(x)
  ctx.parseConfigValue(x[], v, k)

proc parseConfigValue[U, V](ctx: var ConfigParser; x: var Table[U, V];
    v: TomlValue; k: string) =
  typeCheck(v, tvtTable, k)
  x.clear()
  for kk, vv in v:
    var y: V
    let kkk = k & "[" & kk & "]"
    ctx.parseConfigValue(y, vv, kkk)
    x[kk] = y

proc parseConfigValue[U, V](ctx: var ConfigParser; x: var TableRef[U, V];
    v: TomlValue; k: string) =
  typeCheck(v, tvtTable, k)
  x = TableRef[U, V]()
  for kk, vv in v:
    var y: V
    let kkk = k & "[" & kk & "]"
    ctx.parseConfigValue(y, vv, kkk)
    x[kk] = y

proc parseConfigValue(ctx: var ConfigParser; x: var bool; v: TomlValue;
    k: string) =
  typeCheck(v, tvtBoolean, k)
  x = v.b

proc parseConfigValue(ctx: var ConfigParser; x: var string; v: TomlValue;
    k: string) =
  typeCheck(v, tvtString, k)
  x = v.s

proc parseConfigValue(ctx: var ConfigParser; x: var ChaPath;
    v: TomlValue; k: string) =
  typeCheck(v, tvtString, k)
  x = ChaPath(v.s)

proc parseConfigValue[T](ctx: var ConfigParser; x: var seq[T]; v: TomlValue;
    k: string) =
  typeCheck(v, {tvtString, tvtArray}, k)
  if v.t != tvtArray:
    var y: T
    ctx.parseConfigValue(y, v, k)
    x = @[y]
  else:
    if not v.ad:
      x.setLen(0)
    for i in 0 ..< v.a.len:
      var y: T
      ctx.parseConfigValue(y, v.a[i], k & "[" & $i & "]")
      x.add(y)

proc parseConfigValue(ctx: var ConfigParser; x: var TomlTable; v: TomlValue;
    k: string) =
  typeCheck(v, {tvtTable}, k)
  x = v.tab

proc parseConfigValue(ctx: var ConfigParser; x: var Charset; v: TomlValue;
    k: string) =
  typeCheck(v, tvtString, k)
  x = getCharset(v.s)
  if x == CHARSET_UNKNOWN:
    raise newException(ValueError, "unknown charset '" & v.s & "' for key " &
      k)

proc parseConfigValue(ctx: var ConfigParser; x: var int32; v: TomlValue;
    k: string) =
  typeCheck(v, tvtInteger, k)
  x = int32(v.i)

proc parseConfigValue(ctx: var ConfigParser; x: var int64; v: TomlValue;
    k: string) =
  typeCheck(v, tvtInteger, k)
  x = v.i

proc parseConfigValue(ctx: var ConfigParser; x: var ColorMode; v: TomlValue;
    k: string) =
  typeCheck(v, tvtString, k)
  let y = strictParseEnum[ColorMode](v.s)
  if y.isSome:
    x = y.get
  # backwards compat
  elif v.s == "8bit":
    x = cmEightBit
  elif v.s == "24bit":
    x = cmTrueColor
  else:
    raise newException(ValueError, "unknown color mode '" & v.s &
      "' for key " & k)

proc parseConfigValue(ctx: var ConfigParser; x: var ARGBColor; v: TomlValue;
    k: string) =
  typeCheck(v, tvtString, k)
  let c = parseARGBColor(v.s)
  if c.isNone:
    raise newException(ValueError, "invalid color '" & v.s &
      "' for key " & k)
  x = c.get

proc parseConfigValue(ctx: var ConfigParser; x: var RGBColor; v: TomlValue;
    k: string) =
  typeCheck(v, tvtString, k)
  let c = parseLegacyColor(v.s)
  if c.isNone:
    raise newException(ValueError, "invalid color '" & v.s &
      "' for key " & k)
  x = c.get

proc parseConfigValue[T](ctx: var ConfigParser; x: var Option[T]; v: TomlValue;
    k: string) =
  if v.t == tvtString and v.s == "auto":
    x = none(T)
  else:
    var y: T
    ctx.parseConfigValue(y, v, k)
    x = some(y)

proc parseConfigValue(ctx: var ConfigParser; x: var ActionMap; v: TomlValue;
    k: string) =
  typeCheck(v, tvtTable, k)
  for kk, vv in v:
    typeCheck(vv, tvtString, k & "[" & kk & "]")
    let rk = getRealKey(kk)
    var buf: string
    for i in 0 ..< rk.high:
      buf &= rk[i]
      discard x.hasKeyOrPut(buf, "client.feedNext()")
    x[rk] = vv.s

proc parseConfigValue[T: enum](ctx: var ConfigParser; x: var T; v: TomlValue;
    k: string) =
  typeCheck(v, tvtString, k)
  let e = strictParseEnum[T](v.s)
  if e.isNone:
    raise newException(ValueError, "invalid value '" & v.s & "' for key " & k)
  x = e.get

proc parseConfigValue[T](ctx: var ConfigParser; x: var set[T]; v: TomlValue;
    k: string) =
  typeCheck(v, {tvtString, tvtArray}, k)
  if v.t == tvtString:
    var xx: T
    ctx.parseConfigValue(xx, v, k)
    x = {xx}
  else:
    x = {}
    for i in 0 ..< v.a.len:
      let kk = k & "[" & $i & "]"
      var xx: T
      ctx.parseConfigValue(xx, v.a[i], kk)
      x.incl(xx)

proc parseConfigValue(ctx: var ConfigParser; x: var CSSConfig; v: TomlValue;
    k: string) =
  typeCheck(v, tvtTable, k)
  for kk, vv in v:
    let kkk = if k != "":
      k & "." & kk
    else:
      kk
    case kk
    of "include":
      typeCheck(vv, {tvtString, tvtArray}, kkk)
      case vv.t
      of tvtString:
        x.stylesheet &= readUserStylesheet(ctx.dir, vv.s)
      of tvtArray:
        for child in vv.a:
          x.stylesheet &= readUserStylesheet(ctx.dir, vv.s)
      else: discard
    of "inline":
      typeCheck(vv, tvtString, kkk)
      x.stylesheet &= vv.s

proc parseConfigValue(ctx: var ConfigParser; x: var Regex; v: TomlValue;
    k: string) =
  typeCheck(v, tvtString, k)
  let y = compileMatchRegex(v.s)
  if y.isNone:
    raise newException(ValueError, "invalid regex " & k & " : " & y.error)
  x = y.get

proc parseConfigValue(ctx: var ConfigParser; x: var URL; v: TomlValue;
    k: string) =
  typeCheck(v, tvtString, k)
  let y = parseURL(v.s)
  if y.isNone:
    raise newException(ValueError, "invalid URL " & k)
  x = y.get

proc parseConfigValue(ctx: var ConfigParser; x: var JSValueFunction;
    v: TomlValue; k: string) =
  typeCheck(v, tvtString, k)
  let fun = ctx.config.jsctx.eval(v.s, "<config>", JS_EVAL_TYPE_GLOBAL)
  if JS_IsException(fun):
    raise newException(ValueError, "exception in " & k & ": " &
      ctx.config.jsctx.getExceptionMsg())
  if not JS_IsFunction(ctx.config.jsctx, fun):
    raise newException(ValueError, k & " is not a function")
  x = JSValueFunction(fun: fun)
  ctx.config.jsvfns.add(x) # so we can clean it up on exit

proc parseConfigValue(ctx: var ConfigParser; x: var ChaPathResolved;
    v: TomlValue; k: string) =
  typeCheck(v, tvtString, k)
  let y = ChaPath(v.s).unquote()
  if y.isNone:
    raise newException(ValueError, y.error)
  x = ChaPathResolved(y.get)

proc parseConfigValue(ctx: var ConfigParser; x: var MimeTypes; v: TomlValue;
    k: string) =
  var paths: seq[ChaPathResolved]
  ctx.parseConfigValue(paths, v, k)
  x = default(MimeTypes)
  for p in paths:
    let f = openFileExpand(ctx.dir, p)
    if f != nil:
      x.parseMimeTypes(f)

const DefaultMailcap = block:
  let ss = newStringStream(staticRead"res/mailcap")
  parseMailcap(ss).get

proc parseConfigValue(ctx: var ConfigParser; x: var Mailcap; v: TomlValue;
    k: string) =
  var paths: seq[ChaPathResolved]
  ctx.parseConfigValue(paths, v, k)
  x = default(Mailcap)
  for p in paths:
    let f = openFileExpand(ctx.dir, p)
    if f != nil:
      let res = parseMailcap(f)
      if res.isSome:
        x.add(res.get)
      else:
        ctx.warnings.add("Error reading mailcap: " & res.error)
  x.add(DefaultMailcap)

const DefaultURIMethodMap = parseURIMethodMap(staticRead"res/urimethodmap")

proc parseConfigValue(ctx: var ConfigParser; x: var URIMethodMap; v: TomlValue;
    k: string) =
  var paths: seq[ChaPathResolved]
  ctx.parseConfigValue(paths, v, k)
  x = default(URIMethodMap)
  for p in paths:
    let f = openFileExpand(ctx.dir, p)
    if f != nil:
      x.parseURIMethodMap(f.readAll())
  x.append(DefaultURIMethodMap)

func isCompatibleIdent(s: string): bool =
  if s.len == 0 or s[0] notin AsciiAlpha + {'_', '$'}:
    return false
  for i in 1 ..< s.len:
    if s[i] notin AsciiAlphaNumeric + {'_', '$'}:
      return false
  return true

proc parseConfigValue(ctx: var ConfigParser; x: var CommandConfig; v: TomlValue;
    k: string) =
  typeCheck(v, tvtTable, k)
  for kk, vv in v:
    let kkk = k & "." & kk
    typeCheck(vv, {tvtTable, tvtString}, kkk)
    if not kk.isCompatibleIdent():
      raise newException(ValueError, "invalid command name: " & kkk)
    if vv.t == tvtTable:
      ctx.parseConfigValue(x, vv, kkk)
    else: # tvtString
      x.init.add((kkk.substr("cmd.".len), vv.s))

proc parseConfig*(config: Config; dir, buf: string; warnings: var seq[string];
  name = "<input>"; laxnames = false): Err[string]

proc parseConfig(config: Config; dir: string; t: TomlValue;
    warnings: var seq[string]): Err[string] =
  var ctx = ConfigParser(config: config, dir: dir)
  try:
    ctx.parseConfigValue(config[], t, "")
    #TODO: for omnirule/siteconf, check if substitution rules are specified?
    while config.`include`.len > 0:
      #TODO: warn about recursive includes
      var includes = config.`include`
      config.`include`.setLen(0)
      for s in includes:
        let fs = openFileExpand(dir, s)
        if fs == nil:
          return err("include file not found: " & s)
        ?config.parseConfig(dir, fs.readAll(), warnings)
    warnings.add(ctx.warnings)
    return ok()
  except ValueError as e:
    return err(e.msg)

proc parseConfig*(config: Config; dir, buf: string; warnings: var seq[string];
    name = "<input>"; laxnames = false): Err[string] =
  let toml = parseToml(buf, dir / name, laxnames)
  if toml.isSome:
    return config.parseConfig(dir, toml.get, warnings)
  return err("Fatal error: failed to parse config\n" & toml.error)

proc getNormalAction*(config: Config; s: string): string =
  return config.page.getOrDefault(s)

proc getLinedAction*(config: Config; s: string): string =
  return config.line.getOrDefault(s)

proc openConfig*(dir: var string; override: Option[string]): FileStream =
  if override.isSome:
    if override.get.len > 0 and override.get[0] == '/':
      dir = parentDir(override.get)
      return newFileStream(override.get)
    else:
      let path = getCurrentDir() / override.get
      dir = parentDir(path)
      return newFileStream(path)
  dir = getEnv("CHA_CONFIG_DIR")
  if dir != "":
    return newFileStream(dir / "config.toml")
  dir = getEnv("XDG_CONFIG_HOME")
  if dir != "":
    dir = dir / "chawan"
    return newFileStream(dir / "config.toml")
  dir = expandTilde("~/.config/chawan")
  if (let fs = newFileStream(dir / "config.toml"); fs != nil):
    return fs
  dir = expandTilde("~/.chawan")
  return newFileStream(dir / "config.toml")

# called after parseConfig returns
proc initCommands*(config: Config): Err[string] =
  let ctx = config.jsctx
  let obj = JS_NewObject(ctx)
  defer: JS_FreeValue(ctx, obj)
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
          ctx.definePropertyE(objIt, ss, JS_DupValue(ctx, prop))
        if JS_IsException(prop):
          return err(ctx.getExceptionMsg())
        JS_FreeValue(ctx, objIt)
        objIt = prop
    if cmd == "":
      config.cmd.map[k] = JS_UNDEFINED
      continue
    let fun = ctx.eval(cmd, "<" & k & ">", JS_EVAL_TYPE_GLOBAL)
    if JS_IsException(fun):
      return err(ctx.getExceptionMsg())
    if not JS_IsFunction(ctx, fun):
      JS_FreeValue(ctx, fun)
      return err(k & " is not a function")
    ctx.definePropertyE(objIt, name, JS_DupValue(ctx, fun))
    config.cmd.map[k] = fun
    JS_FreeValue(ctx, objIt)
  config.cmd.jsObj = JS_DupValue(ctx, obj)
  config.cmd.init = @[]
  ok()

proc addConfigModule*(ctx: JSContext) =
  ctx.registerType(ActionMap)
  ctx.registerType(StartConfig)
  ctx.registerType(CSSConfig)
  ctx.registerType(SearchConfig)
  ctx.registerType(EncodingConfig)
  ctx.registerType(ExternalConfig)
  ctx.registerType(NetworkConfig)
  ctx.registerType(DisplayConfig)
  ctx.registerType(BufferSectionConfig, name = "BufferConfig")
  ctx.registerType(Config)
