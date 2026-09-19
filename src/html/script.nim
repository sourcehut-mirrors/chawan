{.push raises: [].}

import config/conftypes
import html/catom
import js/jsref
import js/jstypes
import js/jsutils
import js/quickjs
import server/headers
import utils/opt
import server/url
import utils/twtstr

type
  ParserMetadata* = enum
    pmParserInserted, pmNotParserInserted

  ScriptType* = enum
    stClassic, stModule, stImportMap

  ScriptResultType* = enum
    srtNull, srtScript, srtImportMapParse, srtFetching

  RequestDestination* = enum
    rdNone = ""
    rdAudio = "audio"
    rdAudioworklet = "audioworklet"
    rdDocument = "document"
    rdEmbed = "embed"
    rdFont = "font"
    rdFrame = "frame"
    rdIframe = "iframe"
    rdImage = "image"
    rdJson = "json"
    rdManifest = "manifest"
    rdObject = "object"
    rdPaintworklet = "paintworklet"
    rdReport = "report"
    rdScript = "script"
    rdServiceworker = "serviceworker"
    rdSharedworker = "sharedworker"
    rdStyle = "style"
    rdTrack = "track"
    rdWorker = "worker"
    rdXslt = "xslt"

  CredentialsMode* = enum
    cmSameOrigin = "same-origin"
    cmOmit = "omit"
    cmInclude = "include"

type
  EnvironmentSettings* = ref object
    ctx*: JSContext
    attrsp*: ptr WindowAttributes
    # In app mode, attrsp == scriptAttrsp.
    # In lite mode, scriptAttrsp == addr dummyAttrs.
    scriptAttrsp*: ptr WindowAttributes
    moduleMap*: ModuleMap
    origin*: Origin
    scripting*: ScriptingMode
    headless*: HeadlessMode
    images*: bool
    styling*: bool
    autofocus*: bool
    contentType*: CAtom

  Script* = ref object
    settings: EnvironmentSettings
    baseURL*: URL
    options*: ScriptOptions
    mutedErrors*: bool
    #TODO parse error/error to rethrow
    record*: JSValueTraced

  ScriptOptions* = object
    nonce*: string
    integrity*: string
    parserMetadata*: ParserMetadata
    credentialsMode*: CredentialsMode
    referrerPolicy*: Opt[ReferrerPolicy]
    renderBlocking*: bool

  ScriptResult* = ref object
    case t*: ScriptResultType
    of srtNull, srtFetching:
      discard
    of srtScript:
      script*: Script
    of srtImportMapParse:
      discard #TODO

  ModuleType* = enum
    mtJavascript = "javascript"
    mtJson = "json"
    mtCss = "css"

  ModuleMapEntry = object
    key: tuple[url: string; moduleType: ModuleType]
    value*: ScriptResult

  ModuleMap* = seq[ModuleMapEntry]

# Forward declaration hack
# set in html/dom
proc consoleError(ctx: JSContext; ss: varargs[string]) {.importc: "cha_$1".}

proc clear*(moduleMap: var ModuleMap; rt: JSRuntime) =
  moduleMap.setLen(0)

proc find(moduleMap: ModuleMap; url: URL; moduleType: ModuleType): int =
  let surl = $url
  for i, entry in moduleMap.mypairs:
    if entry.key.moduleType == moduleType and entry.key.url == surl:
      return i
  return -1

proc clone(script: Script): Script =
  return Script(
    baseURL: script.baseURL,
    options: script.options,
    mutedErrors: script.mutedErrors,
    #TODO parse error/error to rethrow
    record: script.record
  )

proc clone*(value: ScriptResult): ScriptResult =
  case value.t
  of srtScript:
    return ScriptResult(t: srtScript, script: value.script.clone())
  of srtNull, srtFetching:
    return value
  of srtImportMapParse:
    return ScriptResult(t: srtImportMapParse)

proc mark*(rt: JSRuntime; value: ScriptResult; markFunc: JS_MarkFunc) =
  if value.t == srtScript:
    JS_MarkValue(rt, value.script.record, markFunc)
    rt.markObj(value.script.baseURL, markFunc)

proc mark*(rt: JSRuntime; moduleMap: ModuleMap; markFunc: JS_MarkFunc) =
  for it in moduleMap:
    rt.mark(it.value, markFunc)

proc get*(moduleMap: ModuleMap; url: URL; moduleType: ModuleType):
    ScriptResult =
  let i = moduleMap.find(url, moduleType)
  if i < 0:
    return nil
  return moduleMap[i].value.clone()

proc put*(moduleMap: var ModuleMap; url: URL; moduleType: ModuleType;
    value: ScriptResult) =
  let i = moduleMap.find(url, moduleType)
  if i >= 0:
    moduleMap[i].value = value
  else:
    moduleMap.add(ModuleMapEntry(key: ($url, moduleType), value: value))

proc moduleTypeToRequestDest*(moduleType: ModuleType;
    default: RequestDestination): RequestDestination =
  if moduleType == mtJson:
    return rdJson
  if moduleType == mtCss:
    return rdStyle
  return default

proc newClassicScript*(ctx: JSContext; source: string; baseURL: URL;
    options: ScriptOptions; settings: EnvironmentSettings;
    mutedErrors = false): ScriptResult =
  let record = ctx.compileScript(source, $baseURL)
  ScriptResult(
    t: srtScript,
    script: Script(
      settings: settings,
      record: trace(record),
      baseURL: baseURL,
      options: options,
      mutedErrors: mutedErrors
    )
  )

proc newJSModuleScript*(ctx: JSContext; source: string; baseURL: URL;
    options: ScriptOptions; settings: EnvironmentSettings): ScriptResult =
  let record = ctx.compileModule(source, $baseURL)
  ScriptResult(
    t: srtScript,
    script: Script(
      settings: settings,
      record: trace(record),
      baseURL: baseURL,
      options: options
    )
  )

proc setImportMeta*(ctx: JSContext; funcVal: JSValue; isMain: bool) =
  let m = cast[JSModuleDef](JS_VALUE_GET_PTR(funcVal))
  let moduleNameAtom = JS_GetModuleName(ctx, m)
  let metaObj = JS_GetImportMeta(ctx, m)
  doAssert ctx.definePropertyCWE(metaObj, "url",
    JS_AtomToValue(ctx, moduleNameAtom)) == fjOk
  doAssert ctx.definePropertyCWE(metaObj, "main", JS_FALSE) == fjOk
  JS_FreeValue(ctx, metaObj)

proc finishLoadModule*(ctx: JSContext; funcVal: JSValue; name: string):
    JSModuleDef =
  ctx.setImportMeta(funcVal, false)
  # "the module is already referenced, so we must free it"
  # idk how this works, so for now let's just do what qjs does
  result = cast[JSModuleDef](JS_VALUE_GET_PTR(funcVal))
  JS_FreeValue(ctx, funcVal)

proc logException*(ctx: JSContext) =
  ctx.consoleError(ctx.getExceptionMsg())

{.pop.} # raises: []
