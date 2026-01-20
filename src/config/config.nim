{.push raises: [].}

import std/options
import std/os
import std/sets
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
import css/cssvalues
import html/script
import io/chafile
import io/dynstream
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsnull
import monoucha/jspropenumlist
import monoucha/jsutils
import monoucha/quickjs
import monoucha/tojs
import server/headers
import types/cell
import types/color
import types/jscolor
import types/jsopt
import types/opt
import types/url
import utils/lrewrap
import utils/myposix
import utils/twtstr

type
  StyleString* = distinct string

  ChaPathResolved* = distinct string

  RegexCase* = enum
    rcStrict = "" # case-sensitive
    rcIgnore = "ignore" # case-insensitive
    rcAuto = "auto" # smart case

  CodepointSet* = object
    s*: seq[uint32]

  ActionMap* = ref object
    init: seq[tuple[k, s: string]]
    #TODO could use a sorted tuple[k: string; v: JSValue] instead
    # (like in htmltokenizer)
    t: Table[string, JSValue]

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
    filterCmd*: Option[string]

  OmniRule* = ref object
    match*: Option[Regex]
    substituteUrl*: Option[JSValueFunction]

  StartConfig = ref object
    visualHome* {.jsgetset.}: string
    startupScript* {.jsgetset.}: string
    headless* {.jsgetset.}: HeadlessMode
    consoleBuffer* {.jsgetset.}: bool

  SearchConfig = ref object
    wrap* {.jsgetset.}: bool
    ignoreCase* {.jsgetset.}: RegexCase

  StatusConfig = ref object
    showCursorPosition* {.jsgetset.}: bool
    showHoverLink* {.jsgetset.}: bool
    formatMode* {.jsgetset.}: set[FormatFlag]

  EncodingConfig = ref object
    displayCharset* {.jsgetset.}: Option[Charset]
    documentCharset* {.jsgetset.}: seq[Charset]

  CommandConfig = object
    init*: seq[tuple[k, cmd: string]] # initial k/v map

  ExternalConfig = ref object
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

  InputConfig = ref object
    viNumericPrefix* {.jsgetset.}: bool
    useMouse* {.jsgetset.}: Option[bool]
    osc52Copy* {.jsgetset.}: Option[bool]
    osc52Primary* {.jsgetset.}: Option[bool]
    bracketedPaste* {.jsgetset.}: Option[bool]
    wheelScroll* {.jsgetset.}: int32
    sideWheelScroll* {.jsgetset.}: int32
    linkHintChars*: CodepointSet

  NetworkConfig = ref object
    maxRedirect* {.jsgetset.}: int32
    maxNetConnections* {.jsgetset.}: int32
    prependScheme* {.jsgetset.}: string
    proxy* {.jsgetset.}: URL
    defaultHeaders* {.jsgetset.}: Headers
    allowHttpFromFile* {.jsgetset.}: bool

  DisplayConfig = ref object
    colorMode* {.jsgetset.}: Option[ColorMode]
    formatMode* {.jsgetset.}: Option[set[FormatFlag]]
    noFormatMode* {.jsgetset.}: set[FormatFlag]
    imageMode* {.jsgetset.}: Option[ImageMode]
    sixelColors* {.jsgetset.}: Option[int32]
    altScreen* {.jsgetset.}: Option[bool]
    highlightColor* {.jsgetset.}: CSSColor
    highlightMarks* {.jsgetset.}: bool
    doubleWidthAmbiguous* {.jsgetset.}: bool
    minimumContrast* {.jsgetset.}: int32
    setTitle* {.jsgetset.}: Option[bool]
    defaultBackgroundColor* {.jsgetset.}: Option[RGBColor]
    defaultForegroundColor* {.jsgetset.}: Option[RGBColor]
    columns* {.jsgetset.}: int32
    lines* {.jsgetset.}: int32
    pixelsPerColumn* {.jsgetset.}: int32
    pixelsPerLine* {.jsgetset.}: int32
    forceColumns* {.jsgetset.}: bool
    forceLines* {.jsgetset.}: bool
    forcePixelsPerColumn* {.jsgetset.}: bool
    forcePixelsPerLine* {.jsgetset.}: bool

  BufferSectionConfig* = ref object
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
    feedNext*: JSValueFunction
    arraySeen*: TableRef[string, int] # table arrays seen
    dir* {.jsget.}: string
    dataDir* {.jsget.}: string
    `include` {.jsget.}: seq[ChaPathResolved]
    start* {.jsget.}: StartConfig
    buffer* {.jsget.}: BufferSectionConfig
    search* {.jsget.}: SearchConfig
    encoding* {.jsget.}: EncodingConfig
    external* {.jsget.}: ExternalConfig
    network* {.jsget.}: NetworkConfig
    input* {.jsget.}: InputConfig
    display* {.jsget.}: DisplayConfig
    status* {.jsget.}: StatusConfig
    #TODO getset
    siteconf*: OrderedTable[string, SiteConfig]
    omnirule*: OrderedTable[string, OmniRule]
    cmd*: CommandConfig
    page* {.jsget.}: ActionMap
    line* {.jsget.}: ActionMap

  JSValueFunction* = ref object
    val*: JSValue

jsDestructor(ActionMap)
jsDestructor(StartConfig)
jsDestructor(SearchConfig)
jsDestructor(EncodingConfig)
jsDestructor(ExternalConfig)
jsDestructor(NetworkConfig)
jsDestructor(InputConfig)
jsDestructor(DisplayConfig)
jsDestructor(BufferSectionConfig)
jsDestructor(Config)
jsDestructor(StatusConfig)

proc `$`*(p: ChaPathResolved): lent string =
  string(p)

proc fromJS(ctx: JSContext; val: JSValueConst; res: var ChaPathResolved):
    FromJSResult =
  ctx.fromJS(val, string(res))

proc toJS*(ctx: JSContext; cookie: CookieMode): JSValue =
  case cookie
  of cmReadOnly: return JS_TRUE
  of cmNone: return JS_FALSE
  of cmSave: return JS_NewString(ctx, "save")

proc toJS*(ctx: JSContext; p: ChaPathResolved): JSValue =
  ctx.toJS($p)

proc `[]=`(a: ActionMap; b: string; c: JSValue) =
  a.t[b] = c

# Can't be lent string on 2.0.4 yet.
template `[]`(a: ActionMap; b: string): JSValueConst =
  a.t[b]

template getOrDefault*(a: ActionMap; k: string): JSValueConst =
  a.t.getOrDefault(k, JS_UNDEFINED)

proc getActionPtr*(a: ActionMap; k: string):
    ptr JSValue =
  a.t.withValue(k, p):
    return p
  nil

proc contains*(a: ActionMap; b: string): bool =
  return b in a.t

type
  CustomKey = enum
    ckSpc = "Spc"
    ckTab = "Tab"
    ckEsc = "Esc"
    ckRet = "Ret"
    ckLf = "Lf"
    ckLeft = "Left"
    ckUp = "Up"
    ckDown = "Down"
    ckRight = "Right"
    ckPageUp = "Pageup"
    ckPageDown = "Pagedown"
    ckHome = "Home"
    ckEnd = "End"
    ckF1 = "F1"
    ckF2 = "F2"
    ckF3 = "F3"
    ckF4 = "F4"
    ckF5 = "F5"
    ckF6 = "F6"
    ckF7 = "F7"
    ckF8 = "F8"
    ckF9 = "F9"
    ckF10 = "F10"
    ckF11 = "F11"
    ckF12 = "F12"
    ckF13 = "F13"
    ckF14 = "F14"
    ckF15 = "F15"
    ckF16 = "F16"
    ckF17 = "F17"
    ckF18 = "F18"
    ckF19 = "F19"
    ckF20 = "F20"

  KeyModifier = enum
    kmShift, kmControl, kmMeta

proc toXTermMod(mods: set[KeyModifier]): uint8 =
  return if mods == {kmShift}: 2
  elif mods == {kmControl}: 5
  elif mods == {kmShift, kmControl}: 6
  elif mods == {kmMeta}: 9
  elif mods == {kmMeta, kmShift}: 10
  elif mods == {kmMeta, kmControl}: 13
  elif mods == {kmMeta, kmControl, kmShift}: 14
  else: 0

proc getRealKey(key: string; warnings: var seq[string]): string =
  if key == " ":
    return key
  var realk = ""
  var i = 0
  var mods: set[KeyModifier] = {}
  if i < key.len and key[i] == ' ':
    realk &= ' '
    inc i
  var start = true
  while i < key.len:
    let c = key[i]
    if c == ' ':
      start = true
      inc i
      continue
    if i + 1 < key.len and key[i + 1] == '-':
      case c
      of 'C': mods.incl(kmControl)
      of 'M': mods.incl(kmMeta)
      of 'S': mods.incl(kmShift)
      else: warnings.add("invalid modifier " & c & '-')
      i += 2
      continue
    if start and c in AsciiUpperAlpha and
        i + 1 < key.len and key[i + 1] != ' ':
      var buf = $c
      inc i
      while i < key.len:
        let c = key[i]
        if c == ' ':
          break
        buf &= c.toLowerAscii()
        inc i
      if key := strictParseEnum[CustomKey](buf):
        case key
        of ckSpc:
          if kmMeta in mods:
            realk &= '\e'
          if kmControl in mods:
            realk &= '\0'
          else:
            realk &= ' '
        of ckTab:
          if kmMeta in mods:
            realk &= '\e'
          if kmShift in mods:
            realk &= "\e[Z"
          else:
            realk &= '\t'
        of ckEsc:
          if kmMeta in mods:
            realk &= '\e'
          realk &= '\e'
        of ckRet:
          if kmMeta in mods:
            realk &= '\e'
          realk &= '\r'
        of ckLf:
          if kmMeta in mods:
            realk &= '\e'
          realk &= '\n'
        of ckF1, ckF2, ckF3, ckF4:
          let n = mods.toXTermMod()
          let c = char(uint8(key) - uint8(ckF1) + uint8('P'))
          if n == 0:
            realk &= "\eO" & c
          else:
            realk &= "\e[1;" & $n & c
        else:
          realk &= "\e["
          # see ctlseqs(ms) (from XTerm)
          case key
          of ckPageDown: realk &= '6'
          of ckPageUp: realk &= '5'
          of ckF5: realk &= "15"
          of ckF6: realk &= "17"
          of ckF7: realk &= "18"
          of ckF8: realk &= "19"
          of ckF9: realk &= "20"
          of ckF10: realk &= "21"
          of ckF11: realk &= "23"
          of ckF12: realk &= "24"
          of ckF13: realk &= "25"
          of ckF14: realk &= "26"
          of ckF15: realk &= "28"
          of ckF16: realk &= "29"
          of ckF17: realk &= "31"
          of ckF18: realk &= "32"
          of ckF19: realk &= "33"
          of ckF20: realk &= "34"
          else: discard
          let n = mods.toXTermMod()
          if n > 0:
            realk &= "1;" & $n
          case key
          of ckLeft: realk &= 'D'
          of ckDown: realk &= 'B'
          of ckUp: realk &= 'A'
          of ckRight: realk &= 'C'
          of ckHome: realk &= 'H'
          of ckEnd: realk &= 'F'
          else: discard
      else:
        realk &= buf
        warnings.add("unknown key " & buf)
      start = true
      inc i
      mods = {}
      continue
    if kmMeta in mods:
      realk &= '\e'
    if kmControl in mods:
      realk &= (if c == '?': '\x7F' else: char(uint8(c) and 0x1F))
    elif kmShift in mods:
      realk &= c.toUpperAscii()
    else:
      realk &= c
    mods = {}
    start = false
    inc i
  if key.endsWith(" "):
    realk &= ' '
  move(realk)

proc getter(ctx: JSContext; a: ActionMap; s: string): JSValue
    {.jsgetownprop.} =
  return JS_DupValue(ctx, a.getOrDefault(s))

proc evalCmdDecl(ctx: JSContext; s: string): JSValue =
  if AllChars - AsciiAlphaNumeric - {'_', '$', '.'} notin s and
      not s.startsWith("cmd."):
    return ctx.compileScript("cmd." & s, "<command>")
  return ctx.compileScript(s, "<command>")

proc setter(ctx: JSContext; a: ActionMap; k: string; val: JSValueConst):
    Opt[void] {.jssetprop.} =
  var dummy: seq[string]
  let k = getRealKey(k, dummy)
  if k == "":
    return ok()
  let val2 = if JS_IsFunction(ctx, val):
    JS_DupValue(ctx, val)
  else:
    var s: string
    ?ctx.fromJS(val, s)
    ctx.evalCmdDecl(s)
  if JS_IsException(val2):
    return err()
  let old = a.getOrDefault(k)
  JS_FreeValue(ctx, JSValue(old))
  a.t[k] = val2
  var teststr = k
  teststr.setLen(teststr.high)
  let feedNext = ctx.compileScript("window.feedNext()", "<command>")
  for i in countdown(k.high, 0):
    let dup = JS_DupValue(ctx, feedNext)
    if a.t.hasKeyOrPut(teststr, dup):
      JS_FreeValue(ctx, dup)
    teststr.setLen(i)
  JS_FreeValue(ctx, feedNext)
  ok()

proc delete(a: ActionMap; k: string): bool {.jsdelprop.} =
  var dummy: seq[string]
  let k = getRealKey(k, dummy)
  let ina = k in a
  a.t.del(k)
  return ina

proc names(ctx: JSContext; a: ActionMap): JSPropertyEnumList
    {.jspropnames.} =
  let L = uint32(a.t.len)
  var list = newJSPropertyEnumList(ctx, L)
  for key in a.t.keys:
    list.add(key)
  return list

proc jsLinkHintChars(ctx: JSContext; input: InputConfig): JSValue
    {.jsfget: "linkHintChars".} =
  var vals: seq[JSValue] = @[]
  block good:
    var buf = ""
    for u in input.linkHintChars.s:
      buf.setLen(0)
      buf.addUTF8(u)
      let val = ctx.toJS(buf)
      if JS_IsException(val):
        break good
      vals.add(val)
    return ctx.newArrayFrom(vals)
  for val in vals:
    JS_FreeValue(ctx, val)
  return JS_EXCEPTION

type ConfigParser = object
  jsctx: JSContext
  config: Config
  dir: string
  warnings: seq[string]
  builtin: bool

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
proc parseConfigValue(ctx: var ConfigParser; x: var CSSColor; v: TomlValue;
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
proc parseConfigValue(ctx: var ConfigParser; x: var RegexCase; v: TomlValue;
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
proc parseConfigValue(ctx: var ConfigParser; x: var CodepointSet; v: TomlValue;
  k: string): Err[string]

proc freeValues*(ctx: JSContext; map: ActionMap) =
  for val in map.t.values:
    JS_FreeValue(ctx, val)

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
    when fk notin ["jsvfns", "arraySeen", "dir", "dataDir", "feedNext"]:
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

proc parseConfigValue(ctx: var ConfigParser; x: var Headers; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtTable, k)
  if v.tab.clear or x == nil:
    x = newHeaders(hgRequest)
  for kk, vv in v:
    ?typeCheck(vv, tvtString, k & "[" & kk & "]")
    x[kk] = vv.s
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var CodepointSet; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  x = CodepointSet()
  var seen = initHashSet[uint32]()
  for u in v.s.points:
    if seen.containsOrIncl(u):
      return err(k & ": duplicate codepoint '" & u.toUTF8() & "'")
    if x.s.len > int(cint.high):
      return err(k & ": too many values")
    x.s.add(u)
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

proc parseConfigValue(ctx: var ConfigParser; x: var CSSColor; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  var ctx = initCSSParser(v.s)
  let c = ctx.parseColor()
  if c.isErr or ctx.has() or c.get.t == cctCurrent:
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
    let rk = getRealKey(kk, ctx.warnings)
    x.init.add((rk, vv.s))
  ok()

proc parseConfigValue[T: enum](ctx: var ConfigParser; x: var T; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  let e = strictParseEnum[T](v.s)
  if e.isErr:
    var buf = k & ": invalid value '" & v.s & "', expected one of ["
    for e in T:
      buf &= '"'
      buf &= $e
      buf &= "\", "
    buf.setLen(buf.high)
    buf[^1] = ']'
    return err(buf)
  x = e.get
  ok()

proc parseConfigValue(ctx: var ConfigParser; x: var RegexCase; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, {tvtBoolean, tvtString}, k)
  if v.t == tvtBoolean:
    x = if v.b: rcIgnore else: rcStrict
  else: # string
    if v.s != "auto":
      return err(k & ": invalid value '" & v.s & "'")
    x = rcAuto
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
  x = JSValueFunction(val: fun)
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
    if f := chafile.fopen($p, "r"):
      let res = x.parseMimeTypes(f, DefaultImages)
      f.close()
      if res.isErr:
        return err(k & ": error reading file " & $p)
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
    let ps = newPosixStream($p)
    if ps != nil:
      let src = ps.readAllOrMmap()
      let res = x.parseMailcap(src.toOpenArray(), $p)
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
  x = AutoMailcap(path: $path)
  let ps = newPosixStream($path)
  if ps != nil:
    let src = ps.readAllOrMmap()
    let res = x.entries.parseMailcap(src.toOpenArray(), $path)
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
    let ps = newPosixStream($p)
    if ps != nil:
      x.parseURIMethodMap(ps.readAll())
      ps.sclose()
  x.append(DefaultURIMethodMap)
  ok()

proc isCompatibleIdent(s: string): bool =
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
    if not ctx.builtin and k in ["cmd", "cmd.pager", "cmd.buffer"]:
      if vv.t == tvtTable:
        if AsciiUpperAlpha in kk:
          ctx.warnings.add(kkk &
            ": the first component of namespaces must be lower-case.")
      else: # tvtString
        ctx.warnings.add("Please move " & kkk &
          " to your own namespace (e.g. [cmd.me]) to avoid name clashes.")
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
  warnings: var seq[string]; jsctx: JSContext; name: string; builtin: bool;
  laxnames = false): Err[string]

proc parseConfig(config: Config; dir: string; t: TomlValue;
    warnings: var seq[string]; jsctx: JSContext; builtin: bool): Err[string] =
  var ctx = ConfigParser(
    config: config,
    dir: dir,
    jsctx: jsctx,
    builtin: builtin
  )
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
      let ps = newPosixStream($s)
      if ps == nil:
        return err("include file not found: " & $s)
      ?config.parseConfig(dir, ps.readAll(), warnings, jsctx,
        ($s).afterLast('/'), builtin)
      ps.sclose()
  warnings.add(ctx.warnings)
  ok()

proc parseConfig*(config: Config; dir: string; buf: openArray[char];
    warnings: var seq[string]; jsctx: JSContext; name: string; builtin: bool;
    laxnames = false): Err[string] =
  let toml = parseToml(buf, dir / name, laxnames, config.arraySeen)
  if toml.isOk:
    return config.parseConfig(dir, toml.get, warnings, jsctx, builtin)
  return err("fatal error: failed to parse config\n" & toml.error)

proc openConfig*(dir, dataDir: var string; override: Option[string];
    warnings: var seq[string]): PosixStream =
  if override.isSome:
    if override.get.len > 0 and override.get[0] == '/':
      dir = parentDir(override.get)
      dataDir = dir
      return newPosixStream(override.get)
    let path = myposix.getcwd() / override.get
    dir = parentDir(path)
    dataDir = dir
    return newPosixStream(path)
  dir = getEnvEmpty("CHA_DIR")
  if dir != "":
    # mainly just to behave sanely in nested invocations
    dataDir = getEnvEmpty("CHA_DATA_DIR", dir)
    return newPosixStream(dir / "config.toml")
  dir = getEnvEmpty("XDG_CONFIG_HOME")
  if dir != "":
    dir = dir / "chawan"
  else:
    dir = expandPath("~/.config/chawan")
  if (let fs = newPosixStream(dir / "config.toml"); fs != nil):
    let s = getEnvEmpty("XDG_DATA_HOME")
    if s != "":
      dataDir = s / "chawan"
    else:
      dataDir = expandPath("~/.local/share/chawan")
    return fs
  dir = expandPath("~/.chawan")
  dataDir = dir
  return newPosixStream(dir / "config.toml")

proc initActions(config: Config; ctx: JSContext; map: ActionMap): Err[string] =
  for it in map.init:
    var buf = ""
    let feedNext = config.feedNext.val
    for c in it.k.toOpenArray(0, it.k.high - 1):
      buf &= c
      let old = map.getOrDefault(buf)
      JS_FreeValue(ctx, JSValue(old))
      map[buf] = JS_DupValue(ctx, feedNext)
    let old = map.getOrDefault(it.k)
    JS_FreeValue(ctx, JSValue(old))
    if it.s == "":
      map.t.del(it.k)
    else:
      let val = ctx.evalCmdDecl(it.s)
      if JS_IsException(val):
        return err(ctx.getExceptionMsg())
      map[it.k] = val
  map.init.setLen(0)
  ok()

# called after parseConfig returns
proc initCommands*(ctx: JSContext; config: Config): Err[string] =
  let global = JS_GetGlobalObject(ctx)
  let obj = JS_GetPropertyStr(ctx, global, "cmd")
  JS_FreeValue(ctx, global)
  if JS_IsException(obj):
    JS_FreeValue(ctx, obj)
    return err(ctx.getExceptionMsg())
  for (k, cmd) in config.cmd.init.ritems:
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
      continue
    let fun = ctx.eval(cmd, "<" & k & ">", JS_EVAL_TYPE_GLOBAL)
    if JS_IsException(fun):
      JS_FreeValue(ctx, obj)
      return err(ctx.getExceptionMsg())
    if not JS_IsFunction(ctx, fun):
      JS_FreeValue(ctx, obj)
      JS_FreeValue(ctx, fun)
      return err(k & " is not a function")
    case ctx.definePropertyE(objIt, name, fun)
    of dprException: return err(ctx.getExceptionMsg())
    else: discard
    JS_FreeValue(ctx, objIt)
  JS_FreeValue(ctx, obj)
  config.cmd.init = @[]
  ?config.initActions(ctx, config.page)
  config.initActions(ctx, config.line)

proc newConfig*(ctx: JSContext): Config =
  let feedNext = ctx.compileScript("window.feedNext()", "<command>")
  Config(
    arraySeen: newTable[string, int](),
    page: ActionMap(),
    line: ActionMap(),
    start: StartConfig(),
    search: SearchConfig(),
    encoding: EncodingConfig(),
    external: ExternalConfig(),
    network: NetworkConfig(),
    input: InputConfig(),
    display: DisplayConfig(),
    status: StatusConfig(),
    buffer: BufferSectionConfig(),
    feedNext: JSValueFunction(val: feedNext)
  )

proc addConfigModule*(ctx: JSContext) =
  ctx.registerType(ActionMap)
  ctx.registerType(StartConfig)
  ctx.registerType(SearchConfig)
  ctx.registerType(EncodingConfig)
  ctx.registerType(ExternalConfig)
  ctx.registerType(NetworkConfig)
  ctx.registerType(InputConfig)
  ctx.registerType(DisplayConfig)
  ctx.registerType(StatusConfig)
  ctx.registerType(BufferSectionConfig, name = "BufferConfig")
  ctx.registerType(Config)

{.pop.} # raises: []
