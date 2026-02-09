{.push raises: [].}

from std/strutils import split

import std/algorithm
import std/options
import std/os
import std/sets
import std/tables

import chagashi/charset
import config/chapath
import config/conftypes
import config/cookie
import config/mailcap
import config/toml
import config/urimethodmap
import css/cssparser
import css/cssvalues
import html/script
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

  Action = object
    k: string
    n: uint32
    val: JSValue

  ActionMap* = ref object
    defaultAction*: JSValue
    t*: seq[Action]
    keyIdx: int
    keyLast* {.jsget.}: int
    num: uint32

  FormRequestType* = enum
    frtHttp = "http"
    frtFtp = "ftp"
    frtData = "data"
    frtMailto = "mailto"

  SiteconfMatch* = enum
    smUrl, smHost

  SiteConfigObj* = object
    rewriteUrl*: Option[JSValue]
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

  SiteConfig* = ref object
    name: string
    matchType*: SiteconfMatch
    match*: Regex
    o*: SiteConfigObj
    next: SiteConfig

  OmniRule* = ref object
    name: string
    match*: Regex
    substituteUrl*: JSValue
    next: OmniRule

  ConfigList[T] = object
    head: T
    tail: T

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
    mailcap* {.jsgetset.}: seq[ChaPathResolved]
    autoMailcap* {.jsgetset.}: ChaPathResolved
    mimeTypes* {.jsgetset.}: seq[ChaPathResolved]
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
    arraySeen*: TableRef[string, int] # table arrays seen
    dir* {.jsget.}: string
    dataDir* {.jsget.}: string
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
    siteconf*: ConfigList[SiteConfig]
    omnirule*: ConfigList[OmniRule]
    ruleSeen: HashSet[string]
    cmd*: CommandConfig
    page* {.jsget.}: ActionMap
    line* {.jsget.}: ActionMap

  ConfigParser = object
    jsctx: JSContext
    config: Config
    dir: string
    warnings: seq[string]

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

# Forward declarations
proc parseValue[T: object](ctx: var ConfigParser; x: var T; v: TomlValue;
  k: string): Err[string]
proc parseValue[T: ref object](ctx: var ConfigParser; x: var T; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var bool; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var string; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var ChaPath; v: TomlValue;
  k: string): Err[string]
proc parseValue[T](ctx: var ConfigParser; x: var seq[T]; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var Charset; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var int32; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var int64; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var ScriptingMode; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var HeadlessMode; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var CookieMode; v: TomlValue;
  k: string): Err[string]
proc parseValue[T](ctx: var ConfigParser; x: var Option[T]; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var CSSColor; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var RGBColor; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var ActionMap; v: TomlValue;
  k: string): Err[string]
proc parseValue[T: enum](ctx: var ConfigParser; x: var T; v: TomlValue;
  k: string): Err[string]
proc parseValue[T](ctx: var ConfigParser; x: var set[T]; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var Regex; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var RegexCase; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var URL; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var JSValue; v: TomlValue; k: string):
  Err[string]
proc parseValue(ctx: var ConfigParser; x: var ChaPathResolved;
  v: TomlValue; k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var URIMethodMap; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var CommandConfig; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var StyleString; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var Headers; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: var CodepointSet; v: TomlValue;
  k: string): Err[string]
proc parseValue[T](ctx: var ConfigParser; x: var ConfigList[T]; v: TomlValue;
  k: string): Err[string]
proc parseValue(ctx: var ConfigParser; x: SiteConfig; v: TomlValue; k: string):
  Err[string]
proc parseValue(ctx: var ConfigParser; x: OmniRule; v: TomlValue; k: string):
  Err[string]

proc evalCmdDecl(ctx: JSContext; s: string): JSValue
proc getRealKey(key: openArray[char]; warnings: var seq[string]): string

proc parseConfig*(config: Config; dir: string; buf: openArray[char];
  warnings: var seq[string]; jsctx: JSContext; name: string; laxnames = false):
  Err[string]

proc finalize(rt: JSRuntime; map: ActionMap) {.jsfin.} =
  JS_FreeValueRT(rt, map.defaultAction)
  for it in map.t:
    JS_FreeValueRT(rt, it.val)

proc mark(rt: JSRuntime; map: ActionMap; markFunc: JS_MarkFunc) {.jsmark.} =
  JS_MarkValue(rt, map.defaultAction, markFunc)
  for it in map.t:
    JS_MarkValue(rt, it.val, markFunc)

proc newActionMap(ctx: JSContext; s, defaultAction: string): ActionMap =
  let map = ActionMap(defaultAction: JS_UNDEFINED)
  if defaultAction != "":
    map.defaultAction = ctx.evalCmdDecl(defaultAction)
  var dummy: seq[string]
  for it in s.split('\n'):
    var i = 0
    while true:
      let j = it.find(' ', i)
      if j == -1:
        if i == 0:
          break
        var key = getRealKey(it.toOpenArray(0, i - 2), dummy)
        let val = ctx.evalCmdDecl(it.substr(i))
        map.t.add(Action(k: move(key), val: val, n: map.num))
        inc map.num
        break
      i = j + 1
  map

iterator items*[T](list: ConfigList[T]): T =
  var it = list.head
  while it != nil:
    yield it
    it = it.next

proc add[T](list: var ConfigList[T]; x: T) =
  if list.tail == nil:
    list.head = x
  else:
    list.tail.next = x
  list.tail = x

# ASCII only
proc initCodepointSet(s: cstring): CodepointSet =
  result = CodepointSet()
  for c in s:
    result.s.add(uint32(c))

proc free(ctx: JSContext; rule: OmniRule) =
  JS_FreeValue(ctx, rule.substituteUrl)

proc free(ctx: JSContext; rule: SiteConfig) =
  if rule.o.rewriteUrl.isSome:
    JS_FreeValue(ctx, rule.o.rewriteUrl.get)

proc freeValues*[T](ctx: JSContext; list: ConfigList[T]) =
  for it in list:
    ctx.free(it)

proc remove[T](ctx: JSContext; list: var ConfigList[T]; name: string) =
  var it = list.head
  var prev: T = nil
  while it != nil:
    if it.name == name:
      let next = move(it.next)
      if prev == nil:
        list.head = next
      else:
        prev.next = next
      if next == nil:
        list.tail = nil
      ctx.free(it)
      break
    prev = it
    it = it.next

proc addOmniRule(ctx: JSContext; config: Config; name: string;
    re, fun: JSValueConst): JSValue {.jsfunc.} =
  var len: csize_t
  let p = JS_GetRegExpBytecode(ctx, re, len)
  if p == nil:
    return JS_EXCEPTION
  if not JS_IsFunction(ctx, fun):
    return JS_ThrowTypeError(ctx, "function expected")
  if config.ruleSeen.containsOrIncl(name): # replace
    ctx.remove(config.omnirule, name)
  config.omnirule.add(OmniRule(
    name: name,
    match: bytecodeToRegex(cast[REBytecode](p), len),
    substituteUrl: JS_DupValue(ctx, fun)
  ))
  return JS_UNDEFINED

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

proc sort(ctx: JSContext; map: ActionMap) =
  map.t.sort(proc(a, b: Action): int =
    cmp(a.k, b.k), SortOrder.Ascending)
  #TODO we could probably do this more efficiently
  for i in countdown(map.t.high - 1, 0):
    let j = i + 1
    if map.t[j].k.startsWith(map.t[i].k):
      # always remove the older keybinding
      let k = if map.t[j].n < map.t[i].n: j else: i
      JS_FreeValue(ctx, map.t[k].val)
      map.t.delete(k)
  for i in countdown(map.t.high, 0):
    if JS_IsUndefined(map.t[i].val):
      map.t.delete(i)
  #TODO not sure what happens if this is called after feedNext, but probably
  # not what you'd expect
  map.keyIdx = 0
  map.keyLast = 0

# Helper function for evalAction in case it wants to replace the value we
# are reading.
proc mgetValue*(map: ActionMap): var JSValue =
  return map.t[map.keyIdx].val

proc advance*(map: ActionMap; k: string): JSValueConst =
  var i = map.keyIdx
  var j = map.keyLast
  if i == 0 and j == 0 and k.len > 0:
    # optimization: bisearch for the first char
    let c = k[0]
    i = map.t.binarySearch(c, proc(x: Action; c: char): int = cmp(x.k[0], c))
    if i < 0:
      return JS_UNDEFINED
    # go back to first relevant key
    while i >= 0 and map.t[i].k[0] == c:
      dec i
    inc i
  while i < map.t.len:
    block current:
      let ik = map.t[i].k
      while j < ik.len:
        if j >= k.len:
          map.keyIdx = i
          map.keyLast = j
          return JS_UNDEFINED
        if k[j] != ik[j]:
          j = 0
          break current
        inc j
      map.keyIdx = i
      map.keyLast = 0
      return map.t[i].val
    inc i
  map.keyIdx = 0
  map.keyLast = 0
  return JS_UNDEFINED

proc feedNext*(ctx: JSContext; map: ActionMap; b: bool; k: string) =
  if b:
    inc map.keyIdx
    discard map.advance(k)
  else:
    map.keyIdx = 0

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

proc getRealKey(key: openArray[char]; warnings: var seq[string]): string =
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
      var j = i + 2
      while j < key.len and key[j] != ' ':
        inc j
      if key := parseEnumNoCase[CustomKey](key.toOpenArray(i, j - 1)):
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
        var buf = "unknown key "
        for i in i ..< j:
          let c = key[i]
          realk &= c
          buf &= c
        warnings.add(buf)
      start = true
      i = j + 1
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
  if key.len > 1 and key[^1] == ' ':
    realk &= ' '
  move(realk)

proc find(a: ActionMap; s: string): int =
  var dummy: seq[string]
  let rk = getRealKey(s, dummy)
  return a.t.binarySearch(rk, proc(x: Action; k: string): int = cmp(x.k, k))

proc getter(ctx: JSContext; a: ActionMap; s: string): JSValue {.jsgetownprop.} =
  let i = a.find(s)
  if i == -1:
    return JS_UNINITIALIZED
  return JS_DupValue(ctx, a.t[i].val)

proc evalCmdDecl(ctx: JSContext; s: string): JSValue =
  if s.len == 0:
    return JS_UNDEFINED
  if AllChars - AsciiAlphaNumeric - {'_', '$', '.'} notin s and
      not s.startsWith("cmd."):
    return ctx.compileScript("cmd." & s, "<command>")
  return ctx.compileScript(s, "<command>")

proc setter(ctx: JSContext; a: ActionMap; k: string; val: JSValueConst):
    Opt[void] {.jssetprop.} =
  var dummy: seq[string]
  let rk = getRealKey(k, dummy)
  if rk == "":
    return ok()
  let val2 = if JS_IsFunction(ctx, val):
    JS_DupValue(ctx, val)
  else:
    var s: string
    ?ctx.fromJS(val, s)
    ctx.evalCmdDecl(s)
  if JS_IsException(val2):
    return err()
  a.t.add(Action(k: rk, val: val2, n: a.num))
  inc a.num
  ctx.sort(a)
  ok()

proc delete(a: ActionMap; k: string): bool {.jsdelprop.} =
  let i = a.find(k)
  if i != -1:
    a.t.delete(i)
  return i != -1

proc names(ctx: JSContext; a: ActionMap): JSPropertyEnumList
    {.jspropnames.} =
  let L = uint32(a.t.len)
  var list = newJSPropertyEnumList(ctx, L)
  for it in a.t:
    list.add(it.k)
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
  ctx.freeValues(vals)
  return JS_EXCEPTION

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

proc parseValue[T: object](ctx: var ConfigParser; x: var T; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtTable, k)
  if v.tab.clear:
    x = default(typeof(x))
  let k = k & '.'
  for fk, fv in x.fieldPairs:
    const kebabk = camelToKebabCase(fk)
    var x: TomlValue
    if v.pop(kebabk, x):
      ?ctx.parseValue(fv, x, k & kebabk)
  ctx.warnValuesLeft(v, k)
  ok()

proc parseValue[T: ref object](ctx: var ConfigParser; x: var T; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtTable, k)
  if x == nil:
    new(x)
  ctx.parseValue(x[], v, k)

proc parseValue(ctx: var ConfigParser; x: var Headers; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtTable, k)
  if v.tab.clear or x == nil:
    x = newHeaders(hgRequest)
  for kk, vv in v:
    ?typeCheck(vv, tvtString, k & "[" & kk & "]")
    x[kk] = vv.s
  ok()

proc parseValue(ctx: var ConfigParser; x: var CodepointSet; v: TomlValue;
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

proc parseValue(ctx: var ConfigParser; x: OmniRule; v: TomlValue;
    k: string): Err[string] =
  var vv: TomlValue
  if not v.pop("match", vv):
    return err(k & ": missing match")
  ?ctx.parseValue(x.match, vv, k & '.' & "match")
  if not v.pop("substitute-url", vv):
    return err(k & ": missing substitute-url")
  ?ctx.parseValue(x.substituteUrl, vv, k & '.' & "substitute-url")
  ctx.warnValuesLeft(v, k)
  ok()

proc parseValue(ctx: var ConfigParser; x: SiteConfig; v: TomlValue;
    k: string): Err[string] =
  var match: TomlValue
  let isHost = v.pop("host", match)
  if isHost == v.pop("url", match):
    return err(k & ": either host or url must be specified (but not both)")
  x.matchType = if isHost: smHost else: smUrl
  ?ctx.parseValue(x.match, match, k & '.' & "match")
  ctx.parseValue(x.o, v, k)

proc parseValue[T](ctx: var ConfigParser; x: var ConfigList[T]; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtTable, k)
  if v.tab.clear:
    x.head = nil
    x.tail = nil
  for kk, vv in v:
    let kkk = k & '.' & kk
    ?typeCheck(vv, tvtTable, kkk)
    let rule = T(name: kk)
    ?ctx.parseValue(rule, vv, kkk)
    if ctx.config.ruleSeen.containsOrIncl(kk): # replace
      ctx.jsctx.remove(x, kk)
    x.add(rule)
  ok()

proc parseValue(ctx: var ConfigParser; x: var bool; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtBoolean, k)
  x = v.b
  ok()

proc parseValue(ctx: var ConfigParser; x: var string; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  x = v.s
  ok()

proc parseValue(ctx: var ConfigParser; x: var ChaPath;
    v: TomlValue; k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  x = ChaPath(v.s)
  ok()

proc parseValue[T](ctx: var ConfigParser; x: var seq[T]; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, {tvtString, tvtArray}, k)
  if v.t != tvtArray:
    var y: typeof(x[0])
    ?ctx.parseValue(y, v, k)
    x = @[move(y)]
  else:
    x.setLen(0)
    for i in 0 ..< v.a.len:
      var y: typeof(x[0])
      ?ctx.parseValue(y, v.a[i], k & "[" & $i & "]")
      x.add(move(y))
  ok()

proc parseValue(ctx: var ConfigParser; x: var Charset; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  x = getCharset(v.s)
  if x == CHARSET_UNKNOWN:
    return err(k & ": unknown charset '" & v.s & "'")
  ok()

proc parseValue(ctx: var ConfigParser; x: var int32; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtInteger, k)
  x = int32(v.i)
  ok()

proc parseValue(ctx: var ConfigParser; x: var int64; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtInteger, k)
  x = v.i
  ok()

proc parseValue(ctx: var ConfigParser; x: var ScriptingMode; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, {tvtString, tvtBoolean}, k)
  if v.t == tvtBoolean:
    x = if v.b: smTrue else: smFalse
  elif v.s == "app":
    x = smApp
  else:
    return err(k & ": unknown scripting mode '" & v.s & "'")
  ok()

proc parseValue(ctx: var ConfigParser; x: var HeadlessMode; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, {tvtString, tvtBoolean}, k)
  if v.t == tvtBoolean:
    x = if v.b: hmTrue else: hmFalse
  elif v.s == "dump":
    x = hmDump
  else:
    return err(k & ": unknown headless mode '" & v.s & "'")
  ok()

proc parseValue(ctx: var ConfigParser; x: var CookieMode; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, {tvtString, tvtBoolean}, k)
  if v.t == tvtBoolean:
    x = if v.b: cmReadOnly else: cmNone
  elif v.s == "save":
    x = cmSave
  else:
    return err(k & ": unknown cookie mode '" & v.s & "'")
  ok()

proc parseValue(ctx: var ConfigParser; x: var CSSColor; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  var ctx = initCSSParser(v.s)
  let c = ctx.parseColor()
  if c.isErr or ctx.has() or c.get.t == cctCurrent:
    return err(k & ": invalid color '" & v.s & "'")
  x = c.get
  ok()

proc parseValue(ctx: var ConfigParser; x: var RGBColor; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  let c = parseLegacyColor(v.s)
  if c.isErr:
    return err(k & ": invalid color '" & v.s & "'")
  x = c.get
  ok()

proc parseValue[T](ctx: var ConfigParser; x: var Option[T]; v: TomlValue;
    k: string): Err[string] =
  if v.t == tvtString and v.s == "auto":
    x = none(typeof(x.get))
  else:
    var y: typeof(x.get)
    ?ctx.parseValue(y, v, k)
    x = some(move(y))
  ok()

proc parseValue(ctx: var ConfigParser; x: var ActionMap; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtTable, k)
  for kk, vv in v:
    ?typeCheck(vv, tvtString, k & "[" & kk & "]")
    let rk = getRealKey(kk, ctx.warnings)
    let jsctx = ctx.jsctx
    let val = jsctx.evalCmdDecl(vv.s)
    if JS_IsException(val):
      return err(jsctx.getExceptionMsg())
    x.t.add(Action(k: rk, val: val, n: x.num))
    inc x.num
  ok()

proc parseValue[T: enum](ctx: var ConfigParser; x: var T; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  let e = strictParseEnum[typeof(x)](v.s)
  if e.isErr:
    var buf = k & ": invalid value '" & v.s & "', expected one of ["
    for e in typeof(x):
      buf &= '"'
      buf &= $e
      buf &= "\", "
    buf.setLen(buf.high)
    buf[^1] = ']'
    return err(buf)
  x = e.get
  ok()

proc parseValue(ctx: var ConfigParser; x: var RegexCase; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, {tvtBoolean, tvtString}, k)
  if v.t == tvtBoolean:
    x = if v.b: rcIgnore else: rcStrict
  else: # string
    if v.s != "auto":
      return err(k & ": invalid value '" & v.s & "'")
    x = rcAuto
  ok()

proc parseValue[T](ctx: var ConfigParser; x: var set[T]; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, {tvtString, tvtArray}, k)
  if v.t == tvtString:
    var xx: T
    ?ctx.parseValue(xx, v, k)
    x = {xx}
  else:
    x = {}
    for i in 0 ..< v.a.len:
      let kk = k & "[" & $i & "]"
      var xx: T
      ?ctx.parseValue(xx, v.a[i], kk)
      x.incl(xx)
  ok()

proc parseValue(ctx: var ConfigParser; x: var Regex; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  let y = compileMatchRegex(v.s)
  if y.isErr:
    return err(k & ": invalid regex (" & y.error & ")")
  x = y.get
  ok()

proc parseValue(ctx: var ConfigParser; x: var URL; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  let y = parseURL0(v.s)
  if y == nil:
    return err(k & ": invalid URL " & v.s)
  x = y
  ok()

proc parseValue(ctx: var ConfigParser; x: var JSValue; v: TomlValue; k: string):
    Err[string] =
  ?typeCheck(v, tvtString, k)
  let fun = ctx.jsctx.eval(v.s, "<config>", JS_EVAL_TYPE_GLOBAL)
  if JS_IsException(fun):
    return err(k & ": " & ctx.jsctx.getExceptionMsg())
  if not JS_IsFunction(ctx.jsctx, fun):
    return err(k & ": not a function")
  x = fun
  ok()

proc parseValue(ctx: var ConfigParser; x: var ChaPathResolved;
    v: TomlValue; k: string): Err[string] =
  ?typeCheck(v, tvtString, k)
  let y = ChaPath(v.s).unquote(ctx.config.dir)
  if y.isErr:
    return err(k & ": " & y.error)
  x = ChaPathResolved(y.get)
  ok()

const DefaultURIMethodMap = parseURIMethodMap(staticRead"res/urimethodmap")

proc parseValue(ctx: var ConfigParser; x: var URIMethodMap; v: TomlValue;
    k: string): Err[string] =
  var paths: seq[ChaPathResolved]
  ?ctx.parseValue(paths, v, k)
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

proc parseValue(ctx: var ConfigParser; x: var CommandConfig; v: TomlValue;
    k: string): Err[string] =
  ?typeCheck(v, tvtTable, k)
  for kk, vv in v:
    let kkk = k & "." & kk
    ?typeCheck(vv, {tvtTable, tvtString}, kkk)
    if not kk.isCompatibleIdent():
      return err(kkk & ": invalid command name")
    if k in ["cmd", "cmd.pager", "cmd.buffer"]:
      if vv.t == tvtTable:
        if AsciiUpperAlpha in kk:
          ctx.warnings.add(kkk &
            ": the first component of namespaces must be lower-case.")
      else: # tvtString
        ctx.warnings.add("Please move " & kkk &
          " to your own namespace (e.g. [cmd.me]) to avoid name clashes.")
    if vv.t == tvtTable:
      ?ctx.parseValue(x, vv, kkk)
    else: # tvtString
      x.init.add((kkk.substr("cmd.".len), vv.s))
  ok()

proc parseValue(ctx: var ConfigParser; x: var StyleString; v: TomlValue;
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

proc parseConfig(config: Config; dir: string; t: TomlValue;
    warnings: var seq[string]; jsctx: JSContext): Err[string] =
  var ctx = ConfigParser(
    config: config,
    dir: dir,
    jsctx: jsctx
  )
  var includes: seq[string]
  for kk, vv in t:
    case kk
    of "include": ?ctx.parseValue(includes, vv, kk)
    of "start": ?ctx.parseValue(config.start, vv, kk)
    of "buffer": ?ctx.parseValue(config.buffer, vv, kk)
    of "search": ?ctx.parseValue(config.search, vv, kk)
    of "encoding": ?ctx.parseValue(config.encoding, vv, kk)
    of "external": ?ctx.parseValue(config.external, vv, kk)
    of "network": ?ctx.parseValue(config.network, vv, kk)
    of "input": ?ctx.parseValue(config.input, vv, kk)
    of "display": ?ctx.parseValue(config.display, vv, kk)
    of "status": ?ctx.parseValue(config.status, vv, kk)
    of "siteconf": ?ctx.parseValue(config.siteconf, vv, kk)
    of "omnirule": ?ctx.parseValue(config.omnirule, vv, kk)
    of "cmd": ?ctx.parseValue(config.cmd, vv, kk)
    of "page": ?ctx.parseValue(config.page, vv, kk)
    of "line": ?ctx.parseValue(config.line, vv, kk)
    else: warnings.add("unrecognized option " & kk)
  #TODO: warn about recursive includes
  # or just remove include?  it's a lot of trouble for little worth
  for s in includes:
    let ps = newPosixStream($s)
    if ps == nil:
      return err("include file not found: " & $s)
    ?config.parseConfig(dir, ps.readAll(), warnings, jsctx, ($s).afterLast('/'))
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

# called after parseConfig returns
proc initCommands(ctx: JSContext; config: Config): Opt[void] {.jsfunc.} =
  let global = JS_GetGlobalObject(ctx)
  let obj = JS_GetPropertyStr(ctx, global, "cmd")
  JS_FreeValue(ctx, global)
  if JS_IsException(obj):
    JS_FreeValue(ctx, obj)
    return err()
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
            return err()
          else: discard
        if JS_IsException(prop):
          JS_FreeValue(ctx, obj)
          return err()
        JS_FreeValue(ctx, objIt)
        objIt = prop
    if cmd == "":
      continue
    let fun = ctx.eval(cmd, "<" & k & ">", JS_EVAL_TYPE_GLOBAL)
    if JS_IsException(fun):
      JS_FreeValue(ctx, obj)
      return err()
    if not JS_IsFunction(ctx, fun):
      JS_FreeValue(ctx, obj)
      JS_FreeValue(ctx, fun)
      return err()
    if ctx.definePropertyE(objIt, name, fun) == dprException:
      return err()
    JS_FreeValue(ctx, objIt)
  JS_FreeValue(ctx, obj)
  config.cmd.init = @[]
  ctx.sort(config.page)
  ctx.sort(config.line)
  ok()

const PageCommands = """
y u copyCursorLink
y I copyCursorImage
h cursorLeft
j cursorDown
k cursorUp
l cursorRight
Left cursorLeft
Down cursorDown
Up cursorUp
Right cursorRight
C-n cursorDown
C-p cursorUp
0 cursorLineBegin
Home cursorLineBegin
^ cursorLineTextStart
$ cursorLineEnd
End cursorLineEnd
b cursorViWordBegin
e cursorViWordEnd
w cursorNextViWord
B cursorBigWordBegin
E cursorBigWordEnd
W cursorNextBigWord
[ cursorPrevLink
] cursorNextLink
{ cursorPrevParagraph
} cursorNextParagraph
H cursorTop
M cursorMiddle
L cursorBottom
g 0 cursorLeftEdge
g c cursorMiddleColumn
g $ cursorRightEdge
C-d halfPageDown
C-u halfPageUp
C-f pageDown
C-b pageUp
PageDown pageDown
PageUp pageUp
z H pageLeft
z L pageRight
< pageLeft
> pageRight
C-e scrollDown
C-y scrollUp
J scrollDown
K scrollUp
s e editScreen
s E sourceEdit
s RET saveLink
s LF saveLink
s s saveScreen
s S saveSource
m mark
` gotoMark
' gotoMarkY
z h scrollLeft
z l scrollRight
- scrollLeft
+ scrollRight
RET click
LF click
c rightClick
C toggleMenu
I viewImage
s I saveImage
M-i toggleImages
M-j toggleScripting
M-k toggleCookie
: markURL
r redraw
R reshape
C-c cancel
g g gotoLineOrStart
G gotoLineOrEnd
| gotoColumnOrBegin
z . centerLineBegin
z RET raisePageBegin
z LF raisePageBegin
z - lowerPageBegin
z z centerLine
z t raisePage
z b lowerPage
z + nextPageBegin
z ^ previousPageBegin
y copySelection
v cursorToggleSelection
V cursorToggleSelectionLine
C-v cursorToggleSelectionBlock
q quit
C-z suspend
C-l load
M-l loadCursor
C-k webSearch
M-a addBookmark
M-b openBookmarks
C-h openHistory
M-u dupeBuffer
U reloadBuffer
C-g lineInfo
\ toggleSource
D discardBuffer
d, discardBufferPrev
d. discardBufferNext
M-d discardTree
, prevBuffer
. nextBuffer
M-c enterCommand
/ isearchForward
? isearchBackward
n searchNext
N searchPrev
u peekCursor
s u showFullAlert
C-w toggleWrap
M-y copyURL
M-p gotoClipboardURL
f toggleLinkHints
C-a cursorSearchWordForward
* cursorSearchWordForward
# cursorSearchWordBackward
"""

const LineCommands = """
RET line.submit
LF line.submit
C-h line.backspace
C-? line.backspace
C-d line.delete
C-c line.cancel
C-g line.cancel
M-b line.prevWord
M-f line.nextWord
C-b line.backward
C-f line.forward
C-u line.clear
C-x C-? line.clear
C-x C-e line.openEditor
C-_ line.clear
M-k line.clear
C-k line.kill
C-w line.clearWord
M-C-h line.clearWord
M-C-? line.clearWord
M-d line.killWord
C-a line.begin
Home line.begin
C-e line.end
End line.end
C-v line.escape
C-p line.prevHist
C-n line.nextHist
M-c toggleCommandMode
Down line.nextHist
Up line.prevHist
Right line.forward
Left line.backward
C-Left line.prevWord
C-Right line.nextWord
"""

proc newConfig*(ctx: JSContext; dir, dataDir: string): Config =
  Config(
    dir: dir,
    dataDir: dataDir,
    arraySeen: newTable[string, int](),
    page: newActionMap(ctx, PageCommands, ""),
    line: newActionMap(ctx, LineCommands, "writeInputBuffer"),
    start: StartConfig(
      visualHome: "about:chawan",
      consoleBuffer: true
    ),
    search: SearchConfig(wrap: true, ignoreCase: rcAuto),
    encoding: EncodingConfig(
      documentCharset: @[
        CHARSET_UTF_8, CHARSET_SHIFT_JIS, CHARSET_EUC_JP, CHARSET_ISO_8859_2
      ]
    ),
    external: ExternalConfig(
      historySize: 100,
      showDownloadPanel: true,
      editor: "${VISUAL:-${EDITOR:-vi}}",
      copyCmd: "xsel -bi",
      pasteCmd: "xsel -bo",
      mailcap: @[
        ChaPathResolved(expandPath("~/.mailcap")),
        ChaPathResolved"/etc/mailcap",
        ChaPathResolved"/usr/etc/mailcap",
        ChaPathResolved"/usr/local/etc/mailcap"
      ],
      autoMailcap: ChaPathResolved(dir & "/auto.mailcap"),
      mimeTypes: @[
        ChaPathResolved(expandPath("~/.mime.types")),
        ChaPathResolved"/etc/mime.types",
        ChaPathResolved"/usr/etc/mime.types",
        ChaPathResolved"/usr/local/etc/mime.types"
      ],
      #TODO urimethodmap
      bookmark: ChaPathResolved(dataDir & "/bookmark.md"),
      historyFile: ChaPathResolved(dataDir & "/history.uri"),
      tmpdir: ChaPathResolved(
        getEnvEmpty("TMPDIR", "/tmp") & "/cha-tmp-" & getEnvEmpty("LOGNAME")),
      cgiDir: @[
        ChaPathResolved(dir & "/cgi-bin"),
        ChaPathResolved(getEnvEmpty("CHA_LIBEXEC_DIR") & "/cgi-bin")
      ],
      cookieFile: ChaPathResolved(dataDir & "/cookies.txt"),
      downloadDir: ChaPathResolved(getEnvEmpty("TMPDIR", "/tmp") & '/')
    ),
    network: NetworkConfig(
      maxRedirect: 10,
      maxNetConnections: 12,
      prependScheme: "https://",
      defaultHeaders: newHeaders(hgRequest, {
        "User-Agent": "chawan",
        "Accept": "text/html, text/*;q=0.5, */*;q=0.4",
        "Accept-Encoding": "gzip, deflate, br",
        "Accept-Language": "en;q=1.0",
        "Pragma": "no-cache",
        "Cache-Control": "no-cache"
      })
    ),
    input: InputConfig(
      viNumericPrefix: true,
      wheelScroll: 5,
      sideWheelScroll: 5,
      linkHintChars: initCodepointSet("abcdefghijklmnoprstuvxyz")
    ),
    display: DisplayConfig(
      noFormatMode: {ffOverline},
      highlightColor: ANSIColor(6).cssColor(), # cyan
      highlightMarks: true,
      minimumContrast: 100,
      columns: 80,
      lines: 24,
      pixelsPerColumn: 9,
      pixelsPerLine: 18
    ),
    status: StatusConfig(
      showCursorPosition: true,
      showHoverLink: true,
      formatMode: {ffReverse}
    ),
    buffer: BufferSectionConfig(
      styling: true,
      metaRefresh: mrAsk,
      history: true
    )
  )

proc addConfigModule*(ctx: JSContext): Opt[void] =
  ?ctx.registerType(ActionMap)
  ?ctx.registerType(StartConfig)
  ?ctx.registerType(SearchConfig)
  ?ctx.registerType(EncodingConfig)
  ?ctx.registerType(ExternalConfig)
  ?ctx.registerType(NetworkConfig)
  ?ctx.registerType(InputConfig)
  ?ctx.registerType(DisplayConfig)
  ?ctx.registerType(StatusConfig)
  ?ctx.registerType(BufferSectionConfig, name = "BufferConfig")
  ?ctx.registerType(Config)
  ok()

{.pop.} # raises: []
