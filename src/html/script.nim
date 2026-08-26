{.push raises: [].}

import config/conftypes
import html/catom
import monoucha/jsopaque
import monoucha/jsref
import monoucha/jsutils
import monoucha/quickjs
import types/opt
import types/referrer
import types/url
import types/winattrs
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
    record*: JSValue

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
var errorImpl*: proc(ctx: JSContext; ss: varargs[string]) {.
  nimcall, raises: [].}
var getEnvSettingsImpl*: proc(ctx: JSContext): EnvironmentSettings {.
  nimcall, raises: [].}

proc free*(script: Script) =
  let record = script.record
  script.record = JS_UNINITIALIZED
  JS_FreeValueRT(globalRuntime, record)

proc clear*(moduleMap: var ModuleMap; rt: JSRuntime) =
  for it in moduleMap.mitems:
    if it.value.t == srtScript:
      it.value.script.free()
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
    record: JS_DupValueRT(globalRuntime, script.record)
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
  if i == -1:
    return nil
  return moduleMap[i].value.clone()

proc put*(moduleMap: var ModuleMap; url: URL; moduleType: ModuleType;
    value: ScriptResult) =
  let i = moduleMap.find(url, moduleType)
  if i >= 0:
    let ovalue = moduleMap[i].value
    if ovalue.t == srtScript:
      ovalue.script.free()
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
  return ScriptResult(
    t: srtScript,
    script: Script(
      settings: settings,
      record: record,
      baseURL: baseURL,
      options: options,
      mutedErrors: mutedErrors
    )
  )

proc newJSModuleScript*(ctx: JSContext; source: string; baseURL: URL;
    options: ScriptOptions; settings: EnvironmentSettings): ScriptResult =
  let record = ctx.compileModule(source, $baseURL)
  return ScriptResult(
    t: srtScript,
    script: Script(
      settings: settings,
      record: record,
      baseURL: baseURL,
      options: options
    )
  )

proc setImportMeta*(ctx: JSContext; funcVal: JSValue; isMain: bool) =
  let m = cast[JSModuleDef](JS_VALUE_GET_PTR(funcVal))
  let moduleNameAtom = JS_GetModuleName(ctx, m)
  let metaObj = JS_GetImportMeta(ctx, m)
  doAssert ctx.definePropertyCWE(metaObj, "url",
    JS_AtomToValue(ctx, moduleNameAtom)) == dprSuccess
  doAssert ctx.definePropertyCWE(metaObj, "main", JS_FALSE) == dprSuccess
  JS_FreeValue(ctx, metaObj)
  JS_FreeAtom(ctx, moduleNameAtom)

proc finishLoadModule*(ctx: JSContext; source, name: string): JSModuleDef =
  let funcVal = compileModule(ctx, source, name)
  if JS_IsException(funcVal):
    return nil
  ctx.setImportMeta(funcVal, false)
  # "the module is already referenced, so we must free it"
  # idk how this works, so for now let's just do what qjs does
  result = cast[JSModuleDef](JS_VALUE_GET_PTR(funcVal))
  JS_FreeValue(ctx, funcVal)

proc logException*(ctx: JSContext) =
  ctx.errorImpl(ctx.getExceptionMsg())

proc getEnvSettings*(ctx: JSContext): EnvironmentSettings =
  return ctx.getEnvSettingsImpl()

proc addReflectFunction*(ctx: JSContext; proto: JSValueConst; name: cstring;
    get: JSGetterMagicFunction; set: JSSetterMagicFunction; magic: cint):
    Opt[void] =
  if ctx.definePropertyGetSetCE(proto, name, get, set, magic) == dprException:
    return err()
  ok()

{.pop.} # raises: []
