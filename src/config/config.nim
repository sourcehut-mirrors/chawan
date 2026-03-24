{.push raises: [].}

import std/algorithm
import std/macros
import std/math
import std/options
import std/os
import std/sets
import std/tables

import chagashi/charset
import config/chapath
import config/conftypes
import config/cookie
import config/mailcap
import css/cssparser
import css/cssvalues
import html/script
import io/chafile
import io/dynstream
import monoucha/dtoa
import monoucha/fromjs
import monoucha/jsbind
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
import utils/dtoawrap
import utils/lrewrap
import utils/myposix
import utils/twtstr

type
  RegexCase* = enum
    rcAuto = "auto" # smart case
    rcStrict = "" # case-sensitive
    rcIgnore = "ignore" # case-insensitive

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

  BoolAuto* = enum
    baAuto = "auto"
    baFalse = "false"
    baTrue = "true"

  # ColorMode or -1 for auto
  ColorModeAuto = distinct uint8

  # ImageMode or -1 for auto
  ImageModeAuto = distinct uint8

  # cast[int32] of FormatMode or -1 for auto
  FormatModeAuto = distinct uint32

  ConfigOptionBit {.union.} = object
    u*: uint8
    bool*: bool
    boolAuto*: BoolAuto # bool or "auto"
    charset*: Charset
    colorModeAuto*: ColorModeAuto
    cookieMode*: CookieMode
    formatMode: FormatMode
    headlessMode*: HeadlessMode
    imageModeAuto*: ImageModeAuto
    metaRefresh*: MetaRefresh
    regexCase: RegexCase
    scriptingMode*: ScriptingMode

  ConfigOptionHWord {.union.} = object
    int32: int32
    formatModeAuto: FormatModeAuto

  # RGBColor or -1 for auto
  RGBColorAuto = distinct uint64

  ConfigOptionWord {.union.} = object
    cssColor: CSSColor
    rgbColorAuto: RGBColorAuto

  ConfigOptionType = enum
    # bit (1 byte)
    cotBool = "bool"
    cotBoolAuto = "boolAuto"
    cotCharset = "charset"
    cotColorModeAuto = "colorModeAuto"
    cotCookieMode = "cookieMode"
    cotFormatMode = "formatMode"
    cotHeadlessMode = "headlessMode"
    cotImageModeAuto = "imageModeAuto"
    cotMetaRefresh = "metaRefresh"
    cotRegexCase = "regexCase"
    cotScriptingMode = "scriptingMode"
    # hword (4 bytes)
    cotInt32 = "int32"
    cotInt32Auto = "int32" # signed int32; parses "auto" as -1
    cotFormatModeAuto = "formatModeAuto"
    # word (8 bytes)
    cotCSSColor = "cssColor"
    cotRGBColorAuto = "rgbColorAuto"
    # string
    cotString
    cotStylesheet
    cotPath
    cotCodepointSet
    # seq[Charset]
    cotCharsetSeq
    # seq[ChaPath]
    cotPathSeq
    # Headers
    cotHeaders
    # URL
    cotURL
    # regex
    cotRegex
    # JS function
    cotFunction

  ConfigSection* = enum
    csNone = "none" # starting section
    csBuffer = "buffer"
    csDisplay = "display"
    csEncoding = "encoding"
    csExternal = "external"
    csInput = "input"
    csNetwork = "network"
    csSearch = "search"
    csStart = "start"
    csStatus = "status"
    # command sections
    csCmd = "cmd"
    csPage = "page"
    csLine = "line"
    # array sections
    csSiteconf = "siteconf"
    csOmnirule = "omnirule"

  # Note: when adding a new option, the compiler will scream about a bunch
  # of places.  Just fill the gaps until it's satisfied, then everything
  # should be OK.
  ConfigOption* = enum
    # 1 byte
    coAllowHttpFromFile = "allowHttpFromFile"
    coAltScreen = "altScreen"
    coAutofocus = "autofocus"
    coBracketedPaste = "bracketedPaste"
    coColorMode = "colorMode"
    coConsoleBuffer = "consoleBuffer"
    coCookie = "cookie"
    coDisplayCharset = "displayCharset"
    coDoubleWidthAmbiguous = "doubleWidthAmbiguous"
    coForceColumns = "forceColumns"
    coForceLines = "forceLines"
    coForcePixelsPerColumn = "forcePixelsPerColumn"
    coForcePixelsPerLine = "forcePixelsPerLine"
    coFormatModeStatus = "status.formatMode"
    coHeadless = "headless"
    coHighlightMarks = "highlightMarks"
    coHistory = "history"
    coIgnoreCase = "ignoreCase"
    coImageMode = "imageMode"
    coImages = "images"
    coMarkLinks = "markLinks"
    coMetaRefresh = "metaRefresh"
    coNoFormatMode = "noFormatMode"
    coOsc52Copy = "osc52Copy"
    coOsc52Primary = "osc52Primary"
    coRefererFrom = "refererFrom"
    coScripting = "scripting"
    coSetTitle = "setTitle"
    coShowCursorPosition = "showCursorPosition"
    coShowDownloadPanel = "showDownloadPanel"
    coShowHoverLink = "showHoverLink"
    coStyling = "styling"
    coUseMouse = "useMouse"
    coViNumericPrefix = "viNumericPrefix"
    coW3mCgiCompat = "w3mCgiCompat"
    coWrap = "wrap"

    # 4 bytes
    coColumns = "columns"
    coFormatModeDisplay = "display.formatMode"
    coHistorySize = "historySize"
    coLines = "lines"
    coMaxNetConnections = "maxNetConnections"
    coMaxRedirect = "maxRedirect"
    coMinimumContrast = "minimumContrast"
    coPixelsPerColumn = "pixelsPerColumn"
    coPixelsPerLine = "pixelsPerLine"
    coSideWheelScroll = "sideWheelScroll"
    coSixelColors = "sixelColors"
    coWheelScroll = "wheelScroll"

    # 8 bytes
    coDefaultBackgroundColor = "defaultBackgroundColor"
    coDefaultForegroundColor = "defaultForegroundColor"
    coHighlightColor = "highlightColor"

    # string
    coAutoMailcap = "autoMailcap"
    coBookmark = "bookmark"
    coCookieFile = "cookieFile"
    coCopyCmd = "copyCmd"
    coDownloadDir = "downloadDir"
    coEditor = "editor"
    coHistoryFile = "historyFile"
    coLinkHintChars = "linkHintChars"
    coPasteCmd = "pasteCmd"
    coPrependScheme = "prependScheme"
    coStartupScript = "startupScript"
    coTmpdir = "tmpdir"
    coUserStyle = "userStyle"
    coVisualHome = "visualHome"

    # seq[string]
    coCgiDir = "cgiDir"
    coInclude = "include"
    coMailcap = "mailcap"
    coMimeTypes = "mimeTypes"
    coUrimethodmap = "urimethodmap"

    # Note: if you add another of these, don't forget to add an
    # array in Config too

    # seq[Charset]
    coDocumentCharset = "documentCharset"

    # Headers
    coDefaultHeaders = "defaultHeaders"

    # URL
    coProxy = "proxy"

    # siteconf-only, not available in config
    coAddEntry = "-cha-addEntry" # pseudo-rule for new entries
    coFilterCmd = "filterCmd"
    coHost = "host"
    coInsecureSslNoVerify = "insecureSslNoVerify"
    coMatch = "match"
    coRewriteUrl = "rewriteUrl"
    coShareCookieJar = "shareCookieJar"
    coSubstituteUrl = "substituteUrl"
    coUrl = "url"

  ConfigOptionClass* = enum
    cocBit, cocHWord, cocWord, cocStr, cocStrSeq, cocCharsetSeq, cocHeaders,
    cocURL, cocRegex, cocFunction, cocClear

  ConfigHeadersInit* = ref object
    clear*: bool
    s*: seq[HTTPHeader]

  ConfigEntry* = object
    section*: ConfigSection
    opt*: ConfigOption
    case t*: ConfigOptionClass
    of cocBit:
      bit*: ConfigOptionBit
    of cocHWord:
      hword*: ConfigOptionHWord
    of cocWord:
      word*: ConfigOptionWord
    of cocStr:
      str*: string
    of cocStrSeq:
      strSeq*: seq[string]
    of cocCharsetSeq:
      charsetSeq*: seq[Charset]
    of cocHeaders:
      headers*: ConfigHeadersInit
    of cocURL:
      url*: URL
    of cocRegex:
      regex*: Regex
    of cocFunction:
      fun*: pointer # JSObject *
    of cocClear:
      discard

  ConfigRule* = ref object
    name: string
    matchType*: SiteconfMatch # only used for siteconf
    regex*: Regex # url for siteconf, match for omnirule
    fun*: JSValue # substituteUrl for siteconf, rewriteUrl for omnirule
    entries*: seq[ConfigEntry] # only used for siteconf
    next: ConfigRule

  ConfigList = object
    head: ConfigRule
    tail: ConfigRule

  CommandConfig = object
    init*: seq[tuple[k, cmd: string]] # initial k/v map

const OptionMap = [
  coAllowHttpFromFile: (t: cotBool, section: csNetwork),
  coAltScreen: (cotBoolAuto, csDisplay),
  coAutofocus: (cotBool, csBuffer),
  coBracketedPaste: (cotBoolAuto, csInput),
  coColorMode: (cotColorModeAuto, csDisplay),
  coConsoleBuffer: (cotBool, csStart),
  coCookie: (cotCookieMode, csBuffer),
  coDisplayCharset: (cotCharset, csEncoding),
  coDoubleWidthAmbiguous: (cotBool, csDisplay),
  coForceColumns: (cotBool, csDisplay),
  coForceLines: (cotBool, csDisplay),
  coForcePixelsPerColumn: (cotBool, csDisplay),
  coForcePixelsPerLine: (cotBool, csDisplay),
  coFormatModeStatus: (cotFormatMode, csStatus),
  coHeadless: (cotHeadlessMode, csStart),
  coHighlightMarks: (cotBool, csDisplay),
  coHistory: (cotBool, csBuffer),
  coIgnoreCase: (cotRegexCase, csSearch),
  coImageMode: (cotImageModeAuto, csDisplay),
  coImages: (cotBool, csBuffer),
  coMarkLinks: (cotBool, csBuffer),
  coMetaRefresh: (cotMetaRefresh, csBuffer),
  coNoFormatMode: (cotFormatMode, csDisplay),
  coOsc52Copy: (cotBoolAuto, csInput),
  coOsc52Primary: (cotBoolAuto, csInput),
  coRefererFrom: (cotBool, csBuffer),
  coScripting: (cotScriptingMode, csBuffer),
  coSetTitle: (cotBoolAuto, csDisplay),
  coShowCursorPosition: (cotBool, csStatus),
  coShowDownloadPanel: (cotBool, csExternal),
  coShowHoverLink: (cotBool, csStatus),
  coStyling: (cotBool, csBuffer),
  coUseMouse: (cotBoolAuto, csInput),
  coViNumericPrefix: (cotBool, csInput),
  coW3mCgiCompat: (cotBool, csExternal),
  coWrap: (cotBool, csSearch),

  coColumns: (cotInt32, csDisplay),
  coFormatModeDisplay: (cotFormatModeAuto, csDisplay),
  coHistorySize: (cotInt32, csExternal),
  coLines: (cotInt32, csDisplay),
  coMaxNetConnections: (cotInt32, csNetwork),
  coMaxRedirect: (cotInt32, csNetwork),
  coMinimumContrast: (cotInt32, csDisplay),
  coPixelsPerColumn: (cotInt32, csDisplay),
  coPixelsPerLine: (cotInt32, csDisplay),
  coSideWheelScroll: (cotInt32, csInput),
  coSixelColors: (cotInt32Auto, csDisplay),
  coWheelScroll: (cotInt32, csInput),

  coDefaultBackgroundColor: (cotRGBColorAuto, csDisplay),
  coDefaultForegroundColor: (cotRGBColorAuto, csDisplay),
  coHighlightColor: (cotCSSColor, csDisplay),

  coAutoMailcap: (cotPath, csExternal),
  coBookmark: (cotPath, csExternal),
  coCookieFile: (cotPath, csExternal),
  coCopyCmd: (cotString, csExternal),
  coDownloadDir: (cotPath, csExternal),
  coEditor: (cotPath, csExternal),
  coHistoryFile: (cotPath, csExternal),
  coLinkHintChars: (cotCodepointSet, csInput),
  coPasteCmd: (cotString, csExternal),
  coPrependScheme: (cotString, csNetwork),
  coStartupScript: (cotString, csStart),
  coTmpdir: (cotPath, csExternal),
  coUserStyle: (cotStylesheet, csBuffer),
  coVisualHome: (cotString, csStart),

  coCgiDir: (cotPathSeq, csExternal),
  coInclude: (cotPathSeq, csNone),
  coMailcap: (cotPathSeq, csExternal),
  coMimeTypes: (cotPathSeq, csExternal),
  coUrimethodmap: (cotPathSeq, csExternal),

  coDocumentCharset: (cotCharsetSeq, csEncoding),

  coDefaultHeaders: (cotHeaders, csNetwork),

  coProxy: (cotURL, csNetwork),

  coAddEntry: (cotString, csSiteconf),
  coFilterCmd: (cotString, csSiteconf),
  coHost: (cotRegex, csSiteconf),
  coInsecureSslNoVerify: (cotBool, csSiteconf),
  coMatch: (cotRegex, csOmnirule),
  coRewriteUrl: (cotFunction, csSiteconf),
  coShareCookieJar: (cotString, csSiteconf),
  coSubstituteUrl: (cotFunction, csOmnirule),
  coUrl: (cotRegex, csSiteconf),
]

const FirstBitOpt = ConfigOption.low
const LastBitOpt = coWrap
const FirstHWordOpt = LastBitOpt.succ
const LastHWordOpt = coWheelScroll
const FirstWordOpt = LastHWordOpt.succ
const LastWordOpt = coHighlightColor
const FirstStrOpt = LastWordOpt.succ
const LastStrOpt = coVisualHome
const FirstStrSeqOpt = LastStrOpt.succ
const LastStrSeqOpt = coUrimethodmap

const SiteconfOptions = {
  coCookie, coScripting, coRefererFrom, coImages, coStyling,
  coInsecureSslNoVerify, coAutofocus, coMetaRefresh, coHistory, coMarkLinks,
  coShareCookieJar, coUserStyle, coFilterCmd, coDocumentCharset, coProxy,
  coDefaultHeaders
}

type
  Config* = ref ConfigObj

  ConfigObj = object
    bits*: array[FirstBitOpt..LastBitOpt, ConfigOptionBit]
    hwords*: array[FirstHWordOpt..LastHWordOpt, ConfigOptionHWord]
    words*: array[FirstWordOpt..LastWordOpt, ConfigOptionWord]
    strs*: array[FirstStrOpt..LastStrOpt, string]
    strSeqs*: array[FirstStrSeqOpt..LastStrSeqOpt, seq[string]]
    # we only have one of these types, so no arrays
    documentCharset*: seq[Charset]
    defaultHeaders*: Headers
    proxy*: URL
    dir* {.jsget.}: string
    dataDir* {.jsget.}: string
    #TODO getset
    lists*: array[csSiteconf..csOmnirule, ConfigList]
    ruleSeen: HashSet[string]
    cmd*: CommandConfig
    actionMap*: array[csPage..csLine, ActionMap]

  TomlState = enum
    tsTable
    tsArray
    tsMultiStringSimple
    tsMultiStringDouble

  TomlType = enum
    ttString = "string"
    ttMultiString = "multi-string"
    ttInteger = "integer"
    ttFloat = "float"
    ttBoolean = "boolean"
    ttTable = "table"
    ttArray = "array"

  BeforeKey = object
    keyLen: int
    section: ConfigSection
    opt: ConfigOption
    addEntrySeen: bool

  ConfigParser = object
    ctx: JSContext
    config: Config
    dir: string # CWD for -o, config.dir otherwise
    filename: string
    key: string # user-specified key
    buf: string # last consumed string
    warnings: seq[string]
    states: seq[TomlState]
    arr: seq[string]
    entries: seq[ConfigEntry]
    # these sections have user-defined keys, so we prevent dupes like this
    keysSeen: array[csCmd..csOmnirule, HashSet[string]]
    tableArrayCount: array[csSiteconf..csOmnirule, uint32]
    error: string
    line: int
    beforeKey: BeforeKey
    ival: int32
    tt: TomlType
    bval: bool
    laxnames: bool
    commaSeen: bool
    section: ConfigSection
    opt: ConfigOption
    sectionsSeen: set[ConfigSection]
    optionsSeen: set[ConfigOption]
    # cleared on every new siteconf/omnirule
    ruleOptionsSeen: set[ConfigOption]

jsDestructor(ActionMap)
jsDestructor(Config)

when defined(gcDestructors):
  proc `=destroy`*(a: var ConfigOptionBit) =
    discard

  proc `=destroy`*(a: var ConfigOptionHWord) =
    discard

  proc `=destroy`*(a: var ConfigOptionWord) =
    discard

  proc `=copy`*(a: var ConfigOptionBit; b: ConfigOptionBit) =
    copyMem(addr a, unsafeAddr b, sizeof(a))

  proc `=copy`*(a: var ConfigOptionHWord; b: ConfigOptionHWord) =
    copyMem(addr a, unsafeAddr b, sizeof(a))

  proc `=copy`*(a: var ConfigOptionWord; b: ConfigOptionWord) =
    copyMem(addr a, unsafeAddr b, sizeof(a))

# Forward declarations
proc consumeValue(cp: var ConfigParser; line: string; n: var int): Opt[void]
proc parseConfigValue(cp: var ConfigParser): Opt[void]
proc parseKeyComb(key: openArray[char]; warnings: var seq[string]): string

static:
  doAssert sizeof(ConfigOptionBit) == 1
  doAssert sizeof(ConfigOptionHWord) == 4
  doAssert sizeof(ConfigOptionWord) == 8

proc parseOption(s: openArray[char]): Opt[ConfigOption] =
  return strictParseEnum[ConfigOption](s)

proc optionType(o: ConfigOption): ConfigOptionType =
  return OptionMap[o].t

proc section(o: ConfigOption): ConfigSection =
  return OptionMap[o].section

macro `{}`*(config: Config; s: static string): untyped =
  let t = parseOption(s).get
  let om = OptionMap[t]
  let ot = om.t
  if om.section == csSiteconf:
    error("value only available in siteconf")
  let vs = ident($ot)
  case ot
  of cotBool..cotScriptingMode:
    return quote do:
      `config`.bits[ConfigOption(`t`)].`vs`
  of cotInt32..cotFormatModeAuto:
    return quote do:
      `config`.hwords[ConfigOption(`t`)].`vs`
  of cotCSSColor..cotRGBColorAuto:
    return quote do:
      `config`.words[ConfigOption(`t`)].`vs`
  of cotString..cotCodepointSet:
    return quote do:
      `config`.strs[ConfigOption(`t`)]
  of cotCharsetSeq:
    return quote do:
      `config`.documentCharset
  of cotPathSeq:
    return quote do:
      `config`.strSeqs[ConfigOption(`t`)]
  of cotHeaders:
    return quote do:
      `config`.defaultHeaders
  of cotURL:
    return quote do:
      `config`.proxy
  of cotRegex, cotFunction: # only used in omnirule/siteconf
    error("no such config value")

proc page*(config: Config): lent ActionMap {.jsfget.} =
  config.actionMap[csPage]

proc line*(config: Config): lent ActionMap {.jsfget.} =
  config.actionMap[csLine]

proc parseConfig*(config: Config; dir: string; buf: openArray[char];
  warnings: var seq[string]; ctx: JSContext; name: string; laxnames = false):
  Err[string]

proc finalize(rt: JSRuntime; map: ActionMap) {.jsfin.} =
  JS_FreeValueRT(rt, map.defaultAction)
  for it in map.t:
    JS_FreeValueRT(rt, it.val)

proc mark(rt: JSRuntime; map: ActionMap; markFunc: JS_MarkFunc) {.jsmark.} =
  JS_MarkValue(rt, map.defaultAction, markFunc)
  for it in map.t:
    JS_MarkValue(rt, it.val, markFunc)

template siteconf*(config: Config): ConfigList =
  config.lists[csSiteconf]

template omnirule*(config: Config): ConfigList =
  config.lists[csOmnirule]

proc get*(ba: BoolAuto; b: bool): bool =
  case ba
  of baAuto: return b
  of baTrue: return true
  of baFalse: return false

template isSome*(ba: BoolAuto): bool =
  ba != baAuto

template isNone*(ba: BoolAuto): bool =
  ba == baAuto

template get*(ba: BoolAuto): bool =
  ba == baTrue

template defineAuto(typ, other: untyped) =
  template isSome*(v: typ): bool =
    uint8(v) > 0

  template isNone*(v: typ): bool =
    uint8(v) == 0

  template get*(v: typ): other =
    other(uint8(v) - 1)

  proc toJS*(ctx: JSContext; v: typ): JSValue =
    if v.isSome:
      return ctx.toJS(v.get)
    return JS_NULL

  proc fromJS*(ctx: JSContext; val: JSValueConst; res: var typ): FromJSResult =
    if not JS_IsNull(val):
      res = typ(0)
    else:
      var res2: other
      ?ctx.fromJS(val, res2)
      res = typ(uint(res2) + 1)
    fjOk

defineAuto(ColorModeAuto, ColorMode)
defineAuto(ImageModeAuto, ImageMode)

template isSome*(v: FormatModeAuto): bool =
  uint32(v) > 0

template get*(v: FormatModeAuto): FormatMode =
  cast[set[FormatFlag]](uint32(v) - 1)

proc toJS*(ctx: JSContext; v: FormatModeAuto): JSValue =
  if v.isSome:
    return ctx.toJS(v.get)
  return JS_NULL

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var FormatModeAuto):
    FromJSResult =
  if JS_IsNull(val):
    res = FormatModeAuto(0)
  else:
    var res2: FormatMode
    ?ctx.fromJS(val, res2)
    res = FormatModeAuto(cast[uint32](res2) + 1)
  fjOk

template isSome*(v: RGBColorAuto): bool =
  int64(v) > 0

template isNone*(v: RGBColorAuto): bool =
  int64(v) == 0

template get*(v: RGBColorAuto): RGBColor =
  cast[RGBColor](int64(v))

proc toJS*(ctx: JSContext; v: RGBColorAuto): JSValue =
  if v.isSome:
    return ctx.toJS(v.get)
  return JS_NULL

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var RGBColorAuto):
    FromJSResult =
  if JS_IsNull(val):
    res = RGBColorAuto(0)
  else:
    var res2: RGBColor
    ?ctx.fromJS(val, res2)
    res = RGBColorAuto(uint64(res2) + 1)
  fjOk

proc evalCmdDecl(ctx: JSContext; s: string): JSValue =
  if s.len == 0:
    return JS_UNDEFINED
  if AllChars - AsciiAlphaNumeric - {'_', '$', '.'} notin s and
      not s.startsWith("cmd."):
    return ctx.compileScript("cmd." & s, "<command>")
  return ctx.compileScript(s, "<command>")

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
        var key = parseKeyComb(it.toOpenArray(0, i - 2), dummy)
        let val = ctx.evalCmdDecl(it.substr(i))
        map.t.add(Action(k: move(key), val: val, n: map.num))
        inc map.num
        break
      i = j + 1
  map

iterator items*(list: ConfigList): ConfigRule =
  var it = list.head
  while it != nil:
    yield it
    it = it.next

proc add(list: var ConfigList; x: ConfigRule) =
  if list.tail == nil:
    list.head = x
  else:
    list.tail.next = x
  list.tail = x

proc freeValues*(ctx: JSContext; list: ConfigList) =
  for it in list:
    JS_FreeValue(ctx, it.fun)

proc clear(ctx: JSContext; list: var ConfigList) =
  ctx.freeValues(list)
  list.head = nil
  list.tail = nil

proc remove(ctx: JSContext; list: var ConfigList; name: string) =
  var it = list.head
  var prev: ConfigRule = nil
  while it != nil:
    if it.name == name:
      let next = move(it.next)
      if prev == nil:
        list.head = next
      else:
        prev.next = next
      if next == nil:
        list.tail = nil
      it.next = nil
      JS_FreeValue(ctx, it.fun)
      break
    prev = it
    it = it.next

proc addOmniRule(ctx: JSContext; config: Config; name: string;
    re, fun: JSValueConst): JSValue {.jsfunc.} =
  var len: cint
  let p = JS_GetRegExpBytecode(ctx, re, len)
  if p == nil:
    return JS_EXCEPTION
  if not JS_IsFunction(ctx, fun):
    return JS_ThrowTypeError(ctx, "function expected")
  if config.ruleSeen.containsOrIncl(name): # replace
    ctx.remove(config.omnirule, name)
  config.omnirule.add(ConfigRule(
    name: name,
    regex: bytecodeToRegex(cast[REBytecode](p), len),
    fun: JS_DupValue(ctx, fun)
  ))
  return JS_UNDEFINED

proc toJS*(ctx: JSContext; b: BoolAuto): JSValue =
  case b
  of baAuto: return JS_NULL
  of baFalse: return JS_FALSE
  of baTrue: return JS_TRUE

proc toJS*(ctx: JSContext; cookie: CookieMode): JSValue =
  case cookie
  of cmReadOnly: return JS_TRUE
  of cmNone: return JS_FALSE
  of cmSave: return JS_NewString(ctx, "save")

proc toJS*(ctx: JSContext; headless: HeadlessMode): JSValue =
  case headless
  of hmTrue: return JS_TRUE
  of hmFalse: return JS_FALSE
  of hmDump: return JS_NewString(ctx, "dump")

proc toJS*(ctx: JSContext; val: ScriptingMode): JSValue =
  case val
  of smTrue: return JS_TRUE
  of smFalse: return JS_FALSE
  of smApp: return JS_NewString(ctx, "app")

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

proc parseKeyComb(key: openArray[char]; warnings: var seq[string]): string =
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
  let rk = parseKeyComb(s, dummy)
  return a.t.binarySearch(rk, proc(x: Action; k: string): int = cmp(x.k, k))

proc getter(ctx: JSContext; a: ActionMap; s: string): JSValue {.jsgetownprop.} =
  let i = a.find(s)
  if i == -1:
    return JS_UNINITIALIZED
  return JS_DupValue(ctx, a.t[i].val)

proc setter(ctx: JSContext; a: ActionMap; k: string; val: JSValueConst):
    Opt[void] {.jssetprop.} =
  var dummy: seq[string]
  let rk = parseKeyComb(k, dummy)
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

proc isCompatibleIdent(s: string): bool =
  if s.len == 0 or s[0] notin AsciiAlpha + {'_', '$'}:
    return false
  for i in 1 ..< s.len:
    if s[i] notin AsciiAlphaNumeric + {'_', '$'}:
      return false
  return true

const ValidBare = AsciiAlphaNumeric + {'-', '_'}

proc setError(cp: var ConfigParser; msg: string) =
  #TODO add line etc later?
  cp.error = cp.filename & "(" & $cp.line & "): " & msg

template err(cp: var ConfigParser; msg: string): untyped =
  cp.setError(msg)
  err()

proc warn(cp: var ConfigParser; msg: string) =
  cp.warnings.add(cp.filename & "(" & $cp.line & "): " & msg)

proc expect(cp: var ConfigParser; c: char; line: string; n: var int):
    Opt[void] =
  let m = n
  if m >= line.len:
    return cp.err("expected `" & c & "', got end of line")
  let nc = line[m]
  if nc != c:
    return cp.err("expected `" & c & "', got `" & nc & "'")
  inc n
  ok()

proc expectEOL(cp: var ConfigParser; line: string; n: int): Opt[void] =
  if n < line.len and line[n] != '#':
    return cp.err("unexpected character `" & line[n] & '\'')
  ok()

proc skipTomlBlanks(line: openArray[char]; n: int): int =
  var n = n
  while n < line.len:
    if line[n] notin {' ', '\t'}:
      break
    inc n
  n

proc consumeEscape(cp: var ConfigParser; line: openArray[char]; c: char;
    res: var string; n: int): Opt[n] =
  var n = n
  case c
  of 'b': res &= '\b'
  of 't': res &= '\t'
  of 'n': res &= '\n'
  of 'f': res &= '\f'
  of 'r': res &= '\r'
  of '"': res &= '"'
  of '\\': res &= '\\'
  of 'u', 'U':
    var last = n + 4
    if c == 'U':
      last = n + 8
    let c = line[n]
    inc n
    var num = 0'u32
    let val = hexValue(c)
    if val == -1:
      return cp.err("invalid escaped codepoint: " & $c)
    num = uint32(val)
    while n < last:
      let val = hexValue(line[n])
      if val == -1:
        break
      num *= 0x10
      num += uint32(val)
      inc n
    if n != last:
      return cp.err("invalid escaped length")
    if num > 0x10FFFF or num in 0xD800'u32..0xDFFF'u32:
      return cp.err("invalid escaped codepoint: " & $num)
    res.addUTF8(num)
  of '$': res &= "\\$" # special case for substitution in paths
  else: return cp.err("invalid escape sequence \\" & c)
  ok(n)

# Consume a string and store it in cp.buf.
# If `camel' is true, the buffer is converted to camel-case from
# kebab-case.
proc consumeKeyString(cp: var ConfigParser; camel: bool; line: string;
    first: char; n: int): Opt[int] =
  var n = n
  var escape = false
  var upper = false
  while n < line.len:
    var c = line[n]
    inc n
    if escape:
      n = ?cp.consumeEscape(line, c, cp.buf, n)
      escape = false
    elif c == first:
      break
    elif first == '"' and c == '\\':
      escape = true
    elif c == '-' and camel:
      upper = true
    else:
      if upper:
        c = c.toUpperAscii()
        upper = false
      cp.buf &= c
  if escape:
    return cp.err("invalid escape sequence \\ LF")
  ok(n)

# Consume a bare token, and store it (optionally camel-cased) in cp.buf.
proc consumeBare(cp: var ConfigParser; camel: bool; line: string; n: int):
    Opt[int] =
  var n = line.skipTomlBlanks(n)
  var upper = false
  while n < line.len:
    var c = line[n]
    if c == '-' and camel:
      upper = true
    elif c in ValidBare:
      if upper:
        c = c.toUpperAscii()
        upper = false
      cp.buf &= c
    else:
      break
    inc n
  ok(n)

proc consumeKey(cp: var ConfigParser; camel: bool; line: string; n: int):
    Opt[int] =
  var n = line.skipTomlBlanks(n)
  if n >= line.len:
    return cp.err("key expected")
  cp.buf.setLen(0)
  let c = line[n]
  if c in {'"', '\''}:
    n = ?cp.consumeKeyString(camel, line, c, n + 1)
  else:
    n = ?cp.consumeBare(camel, line, n)
  ok(line.skipTomlBlanks(n))

proc consumeString(cp: var ConfigParser; line: string; first: char; n: int):
    Opt[int] =
  var n = n
  var escape = false
  var multiline = false
  var start = true
  if cp.states.len > 0 and
      cp.states[^1] in {tsMultiStringSimple, tsMultiStringDouble}:
    multiline = true
    start = false
  elif line.startsWith("\"\"", n):
    cp.states.add(tsMultiStringDouble)
    multiline = true
    n += 2
  elif line.startsWith("''", n):
    cp.states.add(tsMultiStringSimple)
    multiline = true
    n += 2
  if start:
    cp.buf.setLen(0)
  while n < line.len:
    var c = line[n]
    inc n
    if escape:
      n = ?cp.consumeEscape(line, c, cp.buf, n)
      escape = false
    elif c == first:
      if not multiline:
        return ok(n)
      if n + 1 < line.len and line[n] == first and line[n + 1] == first:
        n += 2
        doAssert cp.states.pop() in {tsMultiStringSimple, tsMultiStringDouble}
        return ok(n)
      cp.buf &= c
    elif first == '"' and c == '\\':
      escape = true
    else:
      cp.buf &= c
  if escape:
    return cp.err("invalid escape sequence \\ LF")
  if not multiline:
    return cp.err("unexpected end of line")
  if not start:
    cp.buf &= '\n'
  ok(n)

proc parseSection(cp: var ConfigParser; key: string): Opt[ConfigSection] =
  let section = strictParseEnum[ConfigSection](key).get(csNone)
  if section == csNone:
    return cp.err("unknown section " & key)
  ok(section)

proc parseOption(cp: var ConfigParser; section: ConfigSection; key: string):
    Opt[ConfigOption] =
  var x = parseOption(key)
  if x.isErr:
    # retry ambiguous names
    let full = $section & '.' & key
    x = parseOption(full)
    if x.isErr:
      cp.warn("unknown option " & camelToKebabCase(full))
      return ok(coAddEntry) # dummy value
  let opt = x.get
  if opt.section != section and
      not (section == csSiteconf and opt in SiteconfOptions):
    let kebab = camelToKebabCase(key)
    cp.warnings.add("unknown option " & $section & '.' & kebab &
      ", maybe try " & $opt.section & '.' & kebab & '?')
    return ok(coAddEntry) # dummy value
  if section in {csSiteconf, csOmnirule}:
    if opt in cp.ruleOptionsSeen:
      let kebab = camelToKebabCase(key)
      return cp.err("redefinition of option " & kebab)
    cp.ruleOptionsSeen.incl(opt)
  else:
    if opt in cp.optionsSeen:
      let kebab = camelToKebabCase(key)
      return cp.err("redefinition of option " & $section & '.' & kebab)
    cp.optionsSeen.incl(opt)
  x

proc addRuleEntry(cp: var ConfigParser) =
  cp.entries.add(ConfigEntry(
    section: cp.section,
    opt: coAddEntry,
    t: cocStr,
    str: move(cp.buf)
  ))
  cp.ruleOptionsSeen.incl(coAddEntry)

proc checkRuleRegex(cp: var ConfigParser): Opt[void] =
  if coAddEntry in cp.ruleOptionsSeen:
    let intersection = {coUrl, coHost, coMatch} * cp.ruleOptionsSeen
    if intersection == {}:
      return cp.err("missing match regex for " & $cp.section)
    if intersection notin [{coUrl}, {coHost}, {coMatch}]:
      return cp.err("too many match regexes for " & $cp.section)
  ok()

proc parseKey(cp: var ConfigParser; single, tableArray: bool; line: string;
    n: int): Opt[int] =
  var n = n
  var section = cp.section
  if section == csNone:
    n = ?cp.consumeKey(camel = false, line, n)
    section = cp.parseSection(cp.buf).get(csNone)
    if section == csNone:
      if cp.buf != "include":
        return err()
      cp.opt = coInclude
    cp.section = section
    if single or n >= line.len or line[n] != '.':
      if section in cp.sectionsSeen:
        cp.warn("re-definition of section " & $section)
      return ok(n)
    if not tableArray and section notin {csSiteconf, csOmnirule}:
      # Duplicate sections are invalid TOML for siteconf/omnirule too,
      # but the old parser accepted them.
      cp.sectionsSeen.incl(section)
    inc n
  case section
  of csSiteconf, csOmnirule:
    if coAddEntry notin cp.ruleOptionsSeen:
      n = ?cp.consumeKey(camel = false, line, n)
      if cp.keysSeen[section].containsOrIncl(cp.buf):
        return cp.err("duplicate key " & $section & '.' & cp.buf)
      cp.addRuleEntry()
      if single or n >= line.len or line[n] != '.':
        return ok(n)
      inc n
  of csCmd:
    n = ?cp.consumeKey(camel = false, line, n)
    if not cp.buf.isCompatibleIdent():
      return cp.err("invalid command name: " & cp.buf)
    if cp.key.len > 0:
      cp.key &= '.'
    cp.key &= cp.buf
    while n < line.len and line[n] == '.':
      inc n
      n = ?cp.consumeKey(camel = false, line, n)
      if not cp.buf.isCompatibleIdent():
        return cp.err("invalid command name: " & cp.buf)
      cp.key &= '.'
      cp.key &= cp.buf
    if cp.keysSeen[section].containsOrIncl(cp.key):
      return cp.err("duplicate command")
    return ok(n)
  of csPage, csLine:
    if cp.key.len > 0:
      return cp.err("unexpected nested key for section " & $section)
    n = ?cp.consumeKey(camel = false, line, n)
    var warnings: seq[string]
    cp.key = parseKeyComb(cp.buf, warnings)
    for warning in warnings:
      cp.warn(warning)
    if cp.keysSeen[section].containsOrIncl(cp.key):
      return cp.err("duplicate keybinding")
    return ok(n)
  else: discard
  if cp.opt == coAddEntry:
    n = ?cp.consumeKey(camel = true, line, n)
    cp.opt = ?cp.parseOption(cp.section, cp.buf)
    if single or n >= line.len or line[n] != '.':
      return ok(n)
    inc n
  if cp.opt.optionType == cotHeaders:
    n = ?cp.consumeKey(camel = false, line, n)
    cp.key = move(cp.buf)
  ok(n)

proc parseConfigSection(cp: var ConfigParser; line: string; n: int): Opt[void] =
  var n = n
  if n >= line.len:
    return cp.err("unexpected end of line")
  let c = line[n]
  let tableArray = c == '['
  if tableArray:
    inc n
  ?cp.checkRuleRegex()
  cp.buf.setLen(0)
  cp.ruleOptionsSeen = {}
  cp.section = csNone
  cp.opt = coAddEntry
  n = ?cp.parseKey(single = false, tableArray, line, n)
  let section = cp.section
  if tableArray:
    if section notin {csSiteconf, csOmnirule}:
      return cp.err("unexpected table array " & $section &
        ", maybe try [" & $section & "]")
    if coAddEntry in cp.ruleOptionsSeen:
      return cp.err("unexpected name, maybe try [[" & $section & "]]")
    cp.buf = $cp.tableArrayCount[section]
    inc cp.tableArrayCount[section]
    cp.addRuleEntry()
  ?cp.expect(']', line, n)
  if tableArray:
    ?cp.expect(']', line, n)
  n = line.skipTomlBlanks(n)
  cp.expectEOL(line, n)

proc typeCheck(cp: var ConfigParser; t: TomlType): Opt[void] =
  let vt = cp.tt
  if vt != t:
    return cp.err("invalid type (got " & $vt & ", expected " & $t & ")")
  ok()

proc typeCheck(cp: var ConfigParser; t: set[TomlType]): Opt[void] =
  let vt = cp.tt
  if vt notin t:
    return cp.err("invalid type (got " & $vt & ", expected " & $t & ")")
  ok()

proc parseBool(cp: var ConfigParser; x: var bool): Opt[void] =
  ?cp.typeCheck(ttBoolean)
  x = cp.bval
  ok()

proc parseBoolAuto(cp: var ConfigParser; x: var BoolAuto): Opt[void] =
  if cp.tt == ttString and cp.buf == "auto":
    x = baAuto
  else:
    ?cp.typeCheck(ttBoolean)
    x = BoolAuto(uint8(cp.bval) + 1)
  ok()

proc parseCharset(cp: var ConfigParser; x: var Charset): Opt[void] =
  ?cp.typeCheck(ttString)
  let charset = getCharset(cp.buf)
  if charset == CHARSET_UNKNOWN and cp.buf != "auto":
    # auto represented as unknown
    return cp.err("unknown charset '" & cp.buf & "'")
  x = charset
  ok()

proc parseEnum[T: enum](cp: var ConfigParser; x: var T): Opt[void] =
  let e = if cp.tt == ttBoolean:
    strictParseEnum[T]($cp.bval)
  else:
    ?cp.typeCheck(ttString)
    strictParseEnum[T](cp.buf)
  if e.isErr:
    var buf = "invalid value '" & cp.buf & "', expected one of ["
    for e in T:
      buf &= '"'
      buf &= $e
      buf &= "\", "
    buf.setLen(buf.high)
    buf[^1] = ']'
    return cp.err(buf)
  x = e.get
  ok()

proc parseColorModeAuto(cp: var ConfigParser; x: var ColorModeAuto): Opt[void] =
  if cp.tt == ttString and cp.buf == "auto":
    x = ColorModeAuto(0)
  else:
    var y: ColorMode
    ?cp.parseEnum(y)
    x = ColorModeAuto(uint8(y) + 1)
  ok()

proc parseImageModeAuto(cp: var ConfigParser; x: var ImageModeAuto): Opt[void] =
  if cp.tt == ttString and cp.buf == "auto":
    x = ImageModeAuto(0)
  else:
    var y: ImageMode
    ?cp.parseEnum(y)
    x = ImageModeAuto(uint8(y) + 1)
  ok()

proc parseRegexCase(cp: var ConfigParser; x: var RegexCase): Opt[void] =
  ?cp.typeCheck({ttString, ttBoolean})
  if cp.tt == ttBoolean:
    x = if cp.bval: rcIgnore else: rcStrict
  else: # string
    if cp.buf != "auto":
      return cp.err("invalid value '" & cp.buf & "'")
    x = rcAuto
  ok()

proc parseSet[T: enum](cp: var ConfigParser; x: var set[T]): Opt[void] =
  ?cp.typeCheck({ttString, ttArray})
  if cp.tt == ttString:
    var e: T
    ?cp.parseEnum(e)
    x = {e}
    return ok()
  cp.tt = ttString
  var tmp: set[T] = {}
  for s in cp.arr.mitems:
    cp.buf = move(s)
    var e: T
    ?cp.parseEnum(e)
    tmp.incl(e)
  x = tmp
  ok()

proc parseInt32(cp: var ConfigParser; x: var int32): Opt[void] =
  ?cp.typeCheck(ttInteger)
  x = cp.ival
  ok()

proc parseInt32Auto(cp: var ConfigParser; x: var int32): Opt[void] =
  if cp.tt == ttString and cp.buf == "auto":
    x = 0'i32
  else:
    ?cp.typeCheck(ttInteger)
    if cp.ival <= 0:
      return cp.err("positive value expected")
    x = cp.ival
  ok()

proc parseFormatModeAuto(cp: var ConfigParser; x: var FormatModeAuto):
    Opt[void] =
  if cp.tt == ttString and cp.buf == "auto":
    x = FormatModeAuto(0'u32)
  else:
    var y: FormatMode
    ?cp.parseSet(y)
    x = FormatModeAuto(cast[uint32](y) + 1)
  ok()

proc parseCSSColor(cp: var ConfigParser; x: var CSSColor): Opt[void] =
  ?cp.typeCheck(ttString)
  var ctx = initCSSParser(cp.buf)
  let c = ctx.parseColor()
  if c.isErr or ctx.has() or c.get.t == cctCurrent:
    return cp.err("invalid color '" & cp.buf & "'")
  x = c.get
  ok()

proc parseRGBColorAuto(cp: var ConfigParser; x: var RGBColorAuto): Opt[void] =
  ?cp.typeCheck(ttString)
  if cp.buf == "auto":
    x = RGBColorAuto(0)
  else:
    let c = parseLegacyColor(cp.buf)
    if c.isErr:
      return cp.err("invalid color '" & cp.buf & "'")
    x = RGBColorAuto(uint64(c.get) + 1)
  ok()

proc parseString(cp: var ConfigParser; x: var string): Opt[void] =
  ?cp.typeCheck(ttString)
  x = move(cp.buf)
  ok()

proc parseStylesheet(cp: var ConfigParser; x: var string): Opt[void] =
  ?cp.typeCheck(ttString)
  var y = ""
  var parser = initCSSParser(cp.buf)
  var j = 0
  for it in parser.consumeImports():
    var parser2 = initCSSParserSink(it.prelude)
    if parser2.skipBlanksCheckHas().isErr:
      break
    let tok = parser2.consume()
    if parser2.skipBlanksCheckDone().isErr:
      break
    if tok.t != cttString:
      return cp.err("wrong CSS import (unexpected token)")
    let path = ChaPath(tok.s).unquote(cp.config.dir)
    if path.isErr:
      return cp.err("wrong CSS import (" & tok.s & " is not a valid path)")
    let ps = newPosixStream(path.get)
    if ps == nil:
      return cp.err("wrong CSS import (file " & tok.s & " not found)")
    y &= ps.readAll()
    j = parser.i
  y &= cp.buf.substr(j)
  x = move(y)
  ok()

proc parsePath(cp: var ConfigParser; x: var string): Opt[void] =
  ?cp.typeCheck(ttString)
  var y = ChaPath(cp.buf).unquote(cp.config.dir)
  if y.isErr:
    return cp.err(y.error)
  x = move(y.get)
  ok()

proc parseCodepointSet(cp: var ConfigParser; x: var string): Opt[void] =
  ?cp.typeCheck(ttString)
  var seen = initHashSet[uint32]()
  var nseen = 0
  for u in cp.buf.points:
    if seen.containsOrIncl(u):
      return cp.err("duplicate codepoint '" & u.toUTF8() & "'")
    inc nseen
    if nseen > int(cint.high):
      return cp.err("too many values")
  x = move(cp.buf)
  ok()

proc parseCharsetSeq(cp: var ConfigParser; x: var seq[Charset]): Opt[void] =
  ?cp.typeCheck({ttString, ttArray})
  if cp.tt == ttString:
    var charset: Charset
    ?cp.parseEnum(charset)
    x = @[charset]
  else:
    x = @[]
    cp.tt = ttString
    for it in cp.arr.mitems:
      cp.buf = move(it)
      var charset: Charset
      ?cp.parseCharset(charset)
      x.add(charset)
  ok()

proc parsePathSeq(cp: var ConfigParser; x: var seq[string]): Opt[void] =
  ?cp.typeCheck({ttString, ttArray})
  if cp.tt == ttString:
    var s: string
    ?cp.parsePath(s)
    x = @[move(s)]
  else:
    x = @[]
    for it in cp.arr:
      var y = ChaPath(it).unquote(cp.config.dir)
      if y.isErr:
        return cp.err(y.error)
      x.add(move(y.get))
  ok()

proc parseHeaders(cp: var ConfigParser; x: var ConfigHeadersInit): Opt[void] =
  if x == nil:
    x = ConfigHeadersInit()
  if cp.tt == ttTable:
    x.clear = true
  else:
    ?cp.typeCheck(ttString)
    x.s.add((move(cp.key), move(cp.buf)))
  ok()

proc parseURL(cp: var ConfigParser; x: var URL): Opt[void] =
  ?cp.typeCheck(ttString)
  if cp.buf == "":
    x = nil
  else:
    x = parseURL0(cp.buf)
    if x == nil:
      return cp.err("invalid URL " & cp.buf)
  ok()

proc parseRegex(cp: var ConfigParser; x: var Regex): Opt[void] =
  ?cp.typeCheck(ttString)
  var y = compileMatchRegex(cp.buf)
  if y.isErr:
    return cp.err("invalid regex (" & y.error & ")")
  x = move(y.get)
  ok()

proc parseFunction(cp: var ConfigParser; x: var pointer): Opt[void] =
  ?cp.typeCheck(ttString)
  let fun = cp.ctx.eval(cp.buf, "<config>", JS_EVAL_TYPE_GLOBAL)
  if JS_IsException(fun):
    return cp.err(cp.ctx.getExceptionMsg())
  if not JS_IsFunction(cp.ctx, fun):
    return cp.err("not a function")
  x = JS_VALUE_GET_PTR(fun)
  ok()

proc saveKeyState(cp: var ConfigParser) =
  # state to be restored after the current option is flushed
  cp.beforeKey = BeforeKey(
    keyLen: cp.key.len,
    section: cp.section,
    opt: cp.opt,
    addEntrySeen: coAddEntry in cp.ruleOptionsSeen
  )

proc parseKVPair(cp: var ConfigParser; single: bool; line: string; n: var int):
    Opt[void] =
  let nstates = cp.states.len
  cp.saveKeyState()
  n = ?cp.parseKey(single, tableArray = false, line, n)
  ?cp.expect('=', line, n)
  n = line.skipTomlBlanks(n)
  ?cp.consumeValue(line, n)
  n = line.skipTomlBlanks(n)
  # if nesting increased (e.g. array), we defer flushing the option until
  # the line that decreases it.
  if nstates != cp.states.len:
    return ok()
  cp.parseConfigValue()

proc consumeArray(cp: var ConfigParser; line: string; n: var int): Opt[void] =
  let nstates = cp.states.len
  while true:
    n = line.skipTomlBlanks(n)
    if n >= line.len:
      break
    let c = line[n]
    if c == ']':
      inc n
      cp.states.setLen(cp.states.high)
      cp.tt = ttArray
      break
    if c == '#':
      break
    if not cp.commaSeen:
      ?cp.expect(',', line, n)
      n = line.skipTomlBlanks(n)
      cp.commaSeen = true
    if n >= line.len or line[n] == '#':
      break
    ?cp.consumeValue(line, n)
    cp.commaSeen = false
    if nstates != cp.states.len:
      return cp.err("unexpected nested array")
    ?cp.typeCheck(ttString)
    cp.arr.add(move(cp.buf))
  ok()

proc consumeTable(cp: var ConfigParser; line: string; n: var int): Opt[void] =
  while true:
    n = line.skipTomlBlanks(n)
    if n >= line.len:
      break
    let c = line[n]
    if c == '}':
      inc n
      cp.states.setLen(cp.states.high)
      cp.tt = ttTable
      if cp.key.len > 0:
        cp.key.setLen(max(cp.key.rfind('.'), 0))
      elif cp.opt != coAddEntry:
        cp.opt = coAddEntry
      elif coAddEntry in cp.ruleOptionsSeen:
        ?cp.checkRuleRegex()
        cp.ruleOptionsSeen.excl(coAddEntry)
      else:
        cp.section = csNone
      cp.saveKeyState()
      break
    if c == '#':
      break
    if not cp.commaSeen:
      ?cp.expect(',', line, n)
      n = line.skipTomlBlanks(n)
      cp.commaSeen = true
    if n >= line.len or line[n] == '#':
      break
    ?cp.parseKVPair(single = true, line, n)
    cp.commaSeen = false
  ok()

proc consumeValue(cp: var ConfigParser; line: string; n: var int): Opt[void] =
  if n >= line.len:
    return cp.err("value expected")
  let c = line[n]
  case c
  of '[':
    cp.commaSeen = true
    inc n
    cp.states.add(tsArray)
    cp.arr.setLen(0)
    return cp.consumeArray(line, n)
  of '{':
    cp.commaSeen = true
    inc n
    cp.states.add(tsTable)
    if cp.opt == coAddEntry and cp.section in {csSiteconf, csOmnirule}:
      # Note: the old parser could clear all objects, but this seems like
      # a fairly useless feature.
      cp.entries.add(ConfigEntry(section: cp.section, t: cocClear))
    return cp.consumeTable(line, n)
  of '+', '-', AsciiDigit:
    cp.tt = ttInteger
    let val = atod(cstring(line), n, 0, JS_ATOD_INT_ONLY or
      JS_ATOD_ACCEPT_UNDERSCORES)
    if classify(val) in {fcInf, fcNegInf, fcNan}:
      return cp.err("invalid number")
    let ival = int64(val)
    if ival notin int64(int32.low)..int64(int32.high):
      return cp.err("number out of bounds")
    cp.ival = int32(ival)
  of AsciiAlpha:
    cp.buf.setLen(0)
    n = ?cp.consumeBare(camel = false, line, n)
    if cp.buf == "true":
      cp.tt = ttBoolean
      cp.bval = true
    elif cp.buf == "false":
      cp.tt = ttBoolean
      cp.bval = false
    elif cp.laxnames:
      cp.tt = ttString
    else:
      return cp.err("invalid token: " & cp.buf)
  of '"', '\'':
    cp.tt = ttString
    n = ?cp.consumeString(line, c, n + 1)
  else:
    return cp.err("unexpected character in value: `" & c & "'")
  ok()

proc addBit(cp: var ConfigParser): var ConfigOptionBit =
  cp.entries.add(ConfigEntry(section: cp.section, opt: cp.opt, t: cocBit))
  cp.entries[^1].bit

proc addHWord(cp: var ConfigParser): var ConfigOptionHWord =
  cp.entries.add(ConfigEntry(section: cp.section, opt: cp.opt, t: cocHWord))
  cp.entries[^1].hword

proc addWord(cp: var ConfigParser): var ConfigOptionWord =
  cp.entries.add(ConfigEntry(section: cp.section, opt: cp.opt, t: cocWord))
  cp.entries[^1].word

proc addStr(cp: var ConfigParser): var string =
  cp.entries.add(ConfigEntry(section: cp.section, opt: cp.opt, t: cocStr))
  cp.entries[^1].str

proc addCharsetSeq(cp: var ConfigParser): var seq[Charset] =
  cp.entries.add(ConfigEntry(
    section: cp.section,
    opt: cp.opt,
    t: cocCharsetSeq
  ))
  cp.entries[^1].charsetSeq

proc addStrSeq(cp: var ConfigParser): var seq[string] =
  cp.entries.add(ConfigEntry(section: cp.section, opt: cp.opt, t: cocStrSeq))
  cp.entries[^1].strSeq

proc addHeaders(cp: var ConfigParser): var ConfigHeadersInit =
  if cp.entries.len == 0 or cp.entries[^1].opt != cp.opt:
    cp.entries.add(ConfigEntry(section: cp.section, opt: cp.opt, t: cocHeaders))
  cp.entries[^1].headers

proc addURL(cp: var ConfigParser): var URL =
  cp.entries.add(ConfigEntry(section: cp.section, opt: cp.opt, t: cocURL))
  cp.entries[^1].url

proc addRegex(cp: var ConfigParser): var Regex =
  cp.entries.add(ConfigEntry(section: cp.section, opt: cp.opt, t: cocRegex))
  cp.entries[^1].regex

proc addFunction(cp: var ConfigParser): var pointer =
  cp.entries.add(ConfigEntry(section: cp.section, opt: cp.opt, t: cocFunction))
  cp.entries[^1].fun

proc parseConfigValue1(cp: var ConfigParser): Opt[void] =
  let ot = optionType(cp.opt)
  return case ot
  of cotBool: cp.parseBool(cp.addBit().bool)
  of cotBoolAuto: cp.parseBoolAuto(cp.addBit().boolAuto)
  of cotCharset: cp.parseCharset(cp.addBit().charset)
  of cotColorModeAuto: cp.parseColorModeAuto(cp.addBit().colorModeAuto)
  of cotCookieMode: cp.parseEnum(cp.addBit().cookieMode)
  of cotFormatMode: cp.parseSet(cp.addBit().formatMode)
  of cotHeadlessMode: cp.parseEnum(cp.addBit().headlessMode)
  of cotImageModeAuto: cp.parseImageModeAuto(cp.addBit().imageModeAuto)
  of cotMetaRefresh: cp.parseEnum(cp.addBit().metaRefresh)
  of cotRegexCase: cp.parseRegexCase(cp.addBit().regexCase)
  of cotScriptingMode: cp.parseEnum(cp.addBit().scriptingMode)
  of cotInt32: cp.parseInt32(cp.addHWord().int32)
  of cotInt32Auto: cp.parseInt32Auto(cp.addHWord().int32)
  of cotFormatModeAuto: cp.parseFormatModeAuto(cp.addHWord().formatModeAuto)
  of cotCSSColor: cp.parseCSSColor(cp.addWord().cssColor)
  of cotRGBColorAuto: cp.parseRGBColorAuto(cp.addWord().rgbColorAuto)
  of cotString: cp.parseString(cp.addStr())
  of cotStylesheet: cp.parseStylesheet(cp.addStr())
  of cotPath: cp.parsePath(cp.addStr())
  of cotCodepointSet: cp.parseCodepointSet(cp.addStr())
  of cotCharsetSeq: cp.parseCharsetSeq(cp.addCharsetSeq())
  of cotPathSeq: cp.parsePathSeq(cp.addStrSeq())
  of cotHeaders: cp.parseHeaders(cp.addHeaders())
  of cotURL: cp.parseURL(cp.addURL())
  of cotRegex: cp.parseRegex(cp.addRegex())
  of cotFunction: cp.parseFunction(cp.addFunction())

proc parseConfigValue(cp: var ConfigParser): Opt[void] =
  let section = cp.section
  case section
  of csCmd:
    ?cp.typeCheck(ttString)
    let dotIdx = cp.key.find('.')
    if dotIdx == -1:
      cp.warn("please move cmd." & cp.key &
        " to your own namespace (e.g. [cmd.me]) to avoid name clashes")
    elif cp.key.startsWith("pager.") or cp.key.startsWith("buffer."):
      cp.warn("the namespace " & cp.key.until('.') & " is deprecated")
    elif AsciiUpperAlpha in cp.key.toOpenArray(0, dotIdx):
      cp.warn("the first component of namespaces must be lower-case")
    #TODO I guess it would be better if we eval'd here?
    # then a) config reloading can't (normally) choke after parsing,
    # b) we don't have to store the buffer
    cp.config.cmd.init.add((move(cp.key), move(cp.buf)))
  of csPage, csLine:
    ?cp.typeCheck(ttString)
    let ctx = cp.ctx
    let val = ctx.evalCmdDecl(cp.buf)
    if JS_IsException(val):
      return cp.err(ctx.getExceptionMsg())
    #TODO this won't fly for dynamic reloading (and neither will cmd)
    let map = cp.config.actionMap[section]
    map.t.add(Action(k: move(cp.key), val: val, n: map.num))
    inc map.num
  elif cp.opt != coAddEntry: # add entry here means "not found"
    ?cp.parseConfigValue1()
  # reset to state before this key
  cp.section = cp.beforeKey.section
  cp.opt = cp.beforeKey.opt
  if not cp.beforeKey.addEntrySeen:
    ?cp.checkRuleRegex()
    cp.ruleOptionsSeen.excl(coAddEntry)
  cp.key.setLen(cp.beforeKey.keyLen)
  ok()

proc applyEntry(ctx: JSContext; config: Config; entry: var ConfigEntry) =
  let section = entry.section
  let opt = entry.opt
  if section in {csSiteconf, csOmnirule}:
    if entry.t == cocStr and opt == coAddEntry:
      let rule = ConfigRule(fun: JS_UNDEFINED, name: move(entry.str))
      if config.ruleSeen.containsOrIncl(rule.name): # replace
        ctx.remove(config.lists[section], rule.name)
      config.lists[section].add(rule)
    else:
      let rule = config.lists[section].tail
      case entry.t
      of cocRegex:
        if opt == coHost: # smUrl is the default
          rule.matchType = smHost
        rule.regex.bytecode = move(entry.regex.bytecode)
      of cocFunction:
        rule.fun = JS_MKPTR(JS_TAG_OBJECT, entry.fun)
      of cocClear: ctx.clear(config.lists[section])
      else:
        assert opt in SiteconfOptions
        rule.entries.add(entry)
  else:
    case entry.t
    of cocBit: config.bits[opt] = entry.bit
    of cocHWord: config.hwords[opt] = entry.hword
    of cocWord: config.words[opt] = entry.word
    of cocStr: config.strs[opt] = move(entry.str)
    of cocStrSeq: config.strSeqs[opt] = move(entry.strSeq)
    of cocCharsetSeq: config.documentCharset = move(entry.charsetSeq)
    of cocHeaders:
      let init = entry.headers
      if init.clear:
        config.defaultHeaders = newHeaders(hgRequest, init.s)
      else:
        for it in init.s:
          config.defaultHeaders[it.name] = it.value
    of cocURL: config.proxy = move(entry.url)
    of cocClear, cocRegex, cocFunction: assert false

proc applyEntries(ctx: JSContext; config: Config;
    entries: var seq[ConfigEntry]) =
  for entry in entries.mitems:
    ctx.applyEntry(config, entry)

proc parseConfigRegular(cp: var ConfigParser; line: string): Opt[void] =
  var n = line.skipTomlBlanks(0)
  if n >= line.len:
    return ok()
  case (let c = line[n]; c)
  of '#': return ok()
  of '[':
    inc n
    return cp.parseConfigSection(line, n)
  of '"', '\'', ValidBare:
    ?cp.parseKVPair(single = false, line, n)
    return cp.expectEOL(line, n)
  else:
    return cp.err("unexpected character `" & c & "'")

proc parseConfigLine(cp: var ConfigParser; line: string): Opt[void] =
  if cp.states.len == 0:
    return cp.parseConfigRegular(line)
  var n = 0
  while cp.states.len > 0 and n < line.len and line[n] != '#':
    let nstates = cp.states.len
    case cp.states[^1]
    of tsTable: ?cp.consumeTable(line, n)
    of tsArray: ?cp.consumeArray(line, n)
    of tsMultiStringSimple: n = ?cp.consumeString(line, '\'', n)
    of tsMultiStringDouble: n = ?cp.consumeString(line, '"', n)
    if nstates > cp.states.len:
      ?cp.parseConfigValue()
    n = line.skipTomlBlanks(n)
  cp.expectEOL(line, n)

proc initConfigParser(config: Config; dir: string; ctx: JSContext; name: string;
    laxnames: bool): ConfigParser =
  ConfigParser(
    config: config,
    dir: dir,
    ctx: ctx,
    filename: dir / name,
    line: 1,
    laxnames: laxnames,
    sectionsSeen: {csNone},
    opt: coAddEntry
  )

proc parseFile(cp: var ConfigParser; file: ChaFile): Opt[void] =
  var line: string
  while ?file.readLine(line):
    ?cp.parseConfigLine(line)
    inc cp.line
  ok()

proc cleanup(cp: var ConfigParser) =
  for entry in cp.entries:
    if entry.t == cocFunction and entry.fun != nil:
      JS_FreeValue(cp.ctx, JS_MKPTR(JS_TAG_OBJECT, entry.fun))
  if cp.error == "":
    cp.error = "failed to read config"

proc parseConfig*(config: Config; dir: string; file: ChaFile;
    warnings: var seq[string]; ctx: JSContext; name: string; laxnames = false):
    Err[string] =
  var cp = initConfigParser(config, dir, ctx, name, laxnames)
  if cp.parseFile(file).isErr:
    cp.cleanup()
    return err(move(cp.error))
  ctx.applyEntries(config, cp.entries)
  #TODO warn about recursive includes
  # or just remove include
  var includes = move(config{"include"})
  for s in includes:
    let x = chafile.fopen(s, "r")
    if x.isErr:
      return err("include file not found: " & s)
    let f = x.get
    ?config.parseConfig(dir, f, warnings, ctx, s.afterLast('/'))
    f.close()
  warnings.add(cp.warnings)
  ok()

proc parseConfig*(config: Config; dir: string; buf: openArray[char];
    warnings: var seq[string]; ctx: JSContext; name: string; laxnames = false):
    Err[string] =
  var cp = initConfigParser(config, dir, ctx, name, laxnames)
  for line in buf.split('\n'):
    if cp.parseConfigLine(line).isErr:
      for entry in cp.entries:
        if entry.t == cocFunction and entry.fun != nil:
          JS_FreeValue(ctx, JS_MKPTR(JS_TAG_OBJECT, entry.fun))
      return err(move(cp.error))
    inc cp.line
  ctx.applyEntries(config, cp.entries)
  warnings.add(cp.warnings)
  ok()

proc openConfig*(dir, dataDir: var string; override: Option[string];
    warnings: var seq[string]): Opt[ChaFile] =
  if override.isSome:
    if override.get.len > 0 and override.get[0] == '/':
      dir = parentDir(override.get)
      dataDir = dir
      return chafile.fopen(override.get, "r")
    let path = myposix.getcwd() / override.get
    dir = parentDir(path)
    dataDir = dir
    return chafile.fopen(path, "r")
  dir = getEnvEmpty("CHA_DIR")
  if dir != "":
    # mainly just to behave sanely in nested invocations
    dataDir = getEnvEmpty("CHA_DATA_DIR", dir)
    return chafile.fopen(dir / "config.toml", "r")
  dir = getEnvEmpty("XDG_CONFIG_HOME")
  if dir != "":
    dir = dir / "chawan"
  else:
    dir = expandPath("~/.config/chawan")
  if (let fs = chafile.fopen(dir / "config.toml", "r"); fs.isOk):
    let s = getEnvEmpty("XDG_DATA_HOME")
    if s != "":
      dataDir = s / "chawan"
    else:
      dataDir = expandPath("~/.local/share/chawan")
    return fs
  dir = expandPath("~/.chawan")
  dataDir = dir
  return chafile.fopen(dir / "config.toml", "r")

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
      JS_FreeValue(ctx, objIt)
      JS_FreeValue(ctx, obj)
      return err()
    if not JS_IsFunction(ctx, fun):
      JS_FreeValue(ctx, objIt)
      JS_FreeValue(ctx, obj)
      JS_FreeValue(ctx, fun)
      JS_ThrowTypeError(ctx, "not a function")
      return err()
    let dpr = ctx.definePropertyE(objIt, name, fun)
    JS_FreeValue(ctx, objIt)
    if dpr == dprException:
      JS_FreeValue(ctx, obj)
      return err()
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
s E editSource
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

# boolean options that initialize to true
const ConfigInitTrue = [
  coConsoleBuffer, coWrap, coShowDownloadPanel, coViNumericPrefix,
  coHighlightMarks, coShowCursorPosition, coShowHoverLink, coStyling, coHistory
]

const ConfigInitInt32 = {
  coHistorySize: 100'i32,
  coMaxRedirect: 10,
  coMaxNetConnections: 12,
  coWheelScroll: 5,
  coSideWheelScroll: 5,
  coMinimumContrast: 100,
  coColumns: 80,
  coLines: 24,
  coPixelsPerColumn: 9,
  coPixelsPerLine: 18
}

const ConfigInitStr = {
  coVisualHome: "about:chawan",
  coEditor: "${VISUAL:-${EDITOR:-vi}}",
  coCopyCmd: "xsel -bi",
  coPasteCmd: "xsel -bo",
  coPrependScheme: "https://",
  coLinkHintChars: "abcdefghijklmnoprstuvxyz",
}

const ConfigInitPath = {
  coAutoMailcap: "mailcap",
  coBookmark: "$CHA_DATA_DIR/bookmark.md",
  coHistoryFile: "$CHA_DATA_DIR/history.uri",
  coTmpdir: "${TMPDIR:-/tmp}/cha-tmp-$LOGNAME",
  coCookieFile: "$CHA_DATA_DIR/cookies.txt",
  coDownloadDir: "${TMPDIR:-/tmp}/",
}

const ConfigInitPathSeq = {
  coMailcap: @[
    "~/.mailcap", "/etc/mailcap", "/usr/etc/mailcap", "/usr/local/etc/mailcap"
  ],
  coMimeTypes: @[
    "~/.mime.types", "/etc/mime.types", "/usr/etc/mime.types",
    "/usr/local/etc/mime.types"
  ],
  #TODO why are we using w3m's urimethodmap?
  coUrimethodmap: @[
    "~/.urimethodmap",
    "~/.w3m/urimethodmap",
    "/etc/urimethodmap",
    "/usr/local/etc/w3m/urimethodmap"
  ],
  coCgiDir: @["cgi-bin", "$CHA_LIBEXEC_DIR/cgi-bin"],
}

proc getConfigOption(ctx: JSContext; this: JSValueConst; magic: cint): JSValue
    {.cdecl.} =
  let config = cast[ptr ConfigObj](JS_GetOpaque(this, JS_GetClassID(this)))
  let opt = cast[ConfigOption](magic)
  case opt.optionType
  of cotBool: return ctx.toJS(config.bits[opt].bool)
  of cotBoolAuto: return ctx.toJS(config.bits[opt].boolAuto)
  of cotCharset: return ctx.toJS(config.bits[opt].charset)
  of cotColorModeAuto: return ctx.toJS(config.bits[opt].colorModeAuto)
  of cotCookieMode: return ctx.toJS(config.bits[opt].cookieMode)
  of cotFormatMode: return ctx.toJS(config.bits[opt].formatMode)
  of cotHeadlessMode: return ctx.toJS(config.bits[opt].headlessMode)
  of cotImageModeAuto: return ctx.toJS(config.bits[opt].imageModeAuto)
  of cotMetaRefresh: return ctx.toJS(config.bits[opt].metaRefresh)
  of cotRegexCase: return ctx.toJS(config.bits[opt].regexCase)
  of cotScriptingMode: return ctx.toJS(config.bits[opt].scriptingMode)
  of cotInt32: return ctx.toJS(config.hwords[opt].int32)
  of cotInt32Auto:
    let i = config.hwords[opt].int32
    if i < 0:
      return JS_NULL
    return ctx.toJS(i)
  of cotFormatModeAuto: return ctx.toJS(config.hwords[opt].formatModeAuto)
  of cotCSSColor: return ctx.toJS(config.words[opt].cssColor)
  of cotRGBColorAuto: return ctx.toJS(config.words[opt].rgbColorAuto)
  of cotString, cotStylesheet, cotPath, cotCodepointSet:
    return ctx.toJS(config.strs[opt])
  of cotCharsetSeq: return ctx.toJS(config.documentCharset)
  of cotPathSeq: return ctx.toJS(config.strSeqs[opt])
  of cotHeaders: return ctx.toJS(config.defaultHeaders)
  of cotURL: return ctx.toJS(config.proxy)
  of cotRegex, cotFunction: return JS_NULL

proc setConfigOption(ctx: JSContext; this, val: JSValueConst; magic: cint):
    JSValue {.cdecl.} =
  let config = cast[ptr ConfigObj](JS_GetOpaque(this, JS_GetClassID(this)))
  let opt = cast[ConfigOption](magic)
  let res = case opt.optionType
  of cotBool: ctx.fromJS(val, config.bits[opt].bool)
  of cotBoolAuto: ctx.fromJS(val, config.bits[opt].boolAuto)
  of cotCharset: ctx.fromJS(val, config.bits[opt].charset)
  of cotColorModeAuto: ctx.fromJS(val, config.bits[opt].colorModeAuto)
  of cotCookieMode: ctx.fromJS(val, config.bits[opt].cookieMode)
  of cotFormatMode: ctx.fromJS(val, config.bits[opt].formatMode)
  of cotHeadlessMode: ctx.fromJS(val, config.bits[opt].headlessMode)
  of cotImageModeAuto: ctx.fromJS(val, config.bits[opt].imageModeAuto)
  of cotMetaRefresh: ctx.fromJS(val, config.bits[opt].metaRefresh)
  of cotRegexCase: ctx.fromJS(val, config.bits[opt].regexCase)
  of cotScriptingMode: ctx.fromJS(val, config.bits[opt].scriptingMode)
  of cotInt32: ctx.fromJS(val, config.hwords[opt].int32)
  of cotInt32Auto:
    if JS_IsNull(val):
      config.hwords[opt].int32 = -1
      fjOk
    else:
      ctx.fromJS(val, config.hwords[opt].int32)
  of cotFormatModeAuto: ctx.fromJS(val, config.hwords[opt].formatModeAuto)
  of cotCSSColor: ctx.fromJS(val, config.words[opt].cssColor)
  of cotRGBColorAuto: ctx.fromJS(val, config.words[opt].rgbColorAuto)
  of cotString, cotStylesheet, cotPath, cotCodepointSet:
    ctx.fromJS(val, config.strs[opt])
  of cotCharsetSeq: ctx.fromJS(val, config.documentCharset)
  of cotPathSeq: ctx.fromJS(val, config.strSeqs[opt])
  of cotHeaders: ctx.fromJS(val, config.defaultHeaders)
  of cotURL: ctx.fromJS(val, config.proxy)
  of cotRegex, cotFunction: fjOk
  if res == fjErr:
    return JS_EXCEPTION
  return JS_DupValue(ctx, val)

proc addConfigSections(ctx: JSContext; config: Config): Opt[void] =
  var objs {.noinit.}: array[csBuffer..csStatus, JSValue]
  for obj in objs.mitems:
    obj = JS_NewObject(ctx)
    if JS_IsException(obj):
      return err()
    JS_SetOpaque(obj, addr config[])
  for opt in ConfigOption.low..coAddEntry.pred:
    let desc = OptionMap[opt]
    if desc.section == csNone:
      continue
    let obj = objs[desc.section]
    let s = $opt
    let start = s.find('.') + 1
    let p = cast[cstring](unsafeAddr s[start])
    let atom = JS_NewAtomLen(ctx, p, csize_t(s.len - start))
    var f: JSCFunctionType
    f.getter_magic = getConfigOption
    let get = JS_NewCFunction2(ctx, f.generic, p, 0, JS_CFUNC_getter_magic,
      cint(opt))
    if JS_IsException(get):
      return err()
    f.setter_magic = setConfigOption
    let set = JS_NewCFunction2(ctx, f.generic, p, 0, JS_CFUNC_setter_magic,
      cint(opt))
    if JS_IsException(set):
      return err()
    if JS_DefineProperty(ctx, obj, atom, JS_UNDEFINED, get, set,
        JS_PROP_HAS_GET or JS_PROP_HAS_GET) < 0:
      return err()
    ctx.freeValues(get, set)
    JS_FreeAtom(ctx, atom)
  let configObj = ctx.toJS(config)
  for section in csBuffer..csStatus:
    let s = $section
    let obj = objs[section]
    if ctx.defineProperty(configObj, cstring(s), obj) == dprException:
      return err()
  JS_FreeValue(ctx, configObj)
  ok()

proc newConfig*(ctx: JSContext; dir, dataDir: string): Config =
  let config = Config(
    dir: dir,
    dataDir: dataDir,
    actionMap: [
      csPage: newActionMap(ctx, PageCommands, ""),
      csLine: newActionMap(ctx, LineCommands, "writeInputBuffer"),
    ],
    documentCharset: @[
      CHARSET_UTF_8, CHARSET_SHIFT_JIS, CHARSET_EUC_JP, CHARSET_ISO_8859_2
    ],
    defaultHeaders: newHeaders(hgRequest, {
      "User-Agent": "chawan",
      "Accept": "text/html, text/*;q=0.5, */*;q=0.4",
      "Accept-Encoding": "gzip, deflate, br",
      "Accept-Language": "en;q=1.0",
      "Pragma": "no-cache",
      "Cache-Control": "no-cache"
    }),
  )
  for it in ConfigInitTrue:
    config.bits[it].bool = true
  config.bits[coFormatModeStatus].formatMode = {ffReverse}
  config.bits[coNoFormatMode].formatMode = {ffOverline}
  config.words[coHighlightColor].cssColor = ANSIColor(6).cssColor() # cyan
  for it in ConfigInitInt32:
    config.hwords[it[0]].int32 = it[1]
  for it in ConfigInitStr:
    config.strs[it[0]] = it[1]
  for it in ConfigInitPath:
    config.strs[it[0]] = ChaPath(it[1]).unquote(dir).get
  for it in ConfigInitPathSeq:
    for path in it[1]:
      config.strSeqs[it[0]].add(ChaPath(path).unquote(dir).get)
  config.siteconf.add(ConfigRule(
    name: "downloads",
    regex: compileMatchRegex("about:downloads").get,
    fun: JS_UNDEFINED,
    entries: @[ConfigEntry(
      section: csSiteconf,
      opt: coMetaRefresh,
      t: cocBit,
      bit: ConfigOptionBit(metaRefresh: mrAlways)
    )]
  ))
  if ctx.addConfigSections(config).isErr:
    return nil
  config

proc addConfigModule*(ctx: JSContext): Opt[void] =
  ?ctx.registerType(ActionMap)
  ?ctx.registerType(Config)
  ok()

{.pop.} # raises: []
