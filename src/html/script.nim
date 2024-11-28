import monoucha/javascript
import monoucha/quickjs
import types/referrer
import types/url
import utils/twtstr

type
  ParserMetadata* = enum
    pmParserInserted, pmNotParserInserted

  ScriptType* = enum
    stNone, stClassic, stModule, stImportMap

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
    scripting*: bool
    moduleMap*: ModuleMap
    origin*: Origin

  Script* = ref object
    #TODO setings
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
    referrerPolicy*: Option[ReferrerPolicy]
    renderBlocking*: bool

  ScriptResult* = ref object
    case t*: ScriptResultType
    of srtNull, srtFetching:
      discard
    of srtScript:
      script*: Script
    of srtImportMapParse:
      discard #TODO

  ModuleMapEntry = object
    key: tuple[url, moduleType: string]
    value*: ScriptResult

  ModuleMap* = seq[ModuleMapEntry]

# Forward declaration hack
# set in html/dom
var errorImpl*: proc(ctx: JSContext; ss: varargs[string]) {.nimcall.}

proc find*(moduleMap: ModuleMap; url: URL; moduleType: string): int =
  let surl = $url
  for i, entry in moduleMap.mypairs:
    if entry.key.moduleType == moduleType and entry.key.url == surl:
      return i
  return -1

proc set*(moduleMap: var ModuleMap; url: URL; moduleType: string;
    value: ScriptResult; ctx: JSContext) =
  let i = moduleMap.find(url, moduleType)
  if i != -1:
    if moduleMap[i].value.t == srtScript:
      JS_FreeValue(ctx, moduleMap[i].value.script.record)
    moduleMap[i].value = value
  else:
    moduleMap.add(ModuleMapEntry(key: ($url, moduleType), value: value))

func moduleTypeToRequestDest*(moduleType: string; default: RequestDestination):
    RequestDestination =
  if moduleType == "json":
    return rdJson
  if moduleType == "css":
    return rdStyle
  return default

proc newClassicScript*(ctx: JSContext; source: string; baseURL: URL;
    options: ScriptOptions; mutedErrors = false): ScriptResult =
  let urls = baseURL.serialize(excludepassword = true)
  let record = ctx.compileScript(source, urls)
  return ScriptResult(
    t: srtScript,
    script: Script(
      record: record,
      baseURL: baseURL,
      options: options,
      mutedErrors: mutedErrors
    )
  )

proc newJSModuleScript*(ctx: JSContext; source: string; baseURL: URL;
    options: ScriptOptions): ScriptResult =
  let urls = baseURL.serialize(excludepassword = true)
  let record = ctx.compileModule(source, urls)
  return ScriptResult(
    t: srtScript,
    script: Script(
      record: record,
      baseURL: baseURL,
      options: options
    )
  )

proc logException*(ctx: JSContext) =
  ctx.errorImpl(ctx.getExceptionMsg())

func uninitIfNull*(val: JSValue): JSValue =
  if JS_IsNull(val):
    return JS_UNINITIALIZED
  return val
