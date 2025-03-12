import monoucha/javascript
import monoucha/jsopaque
import monoucha/jsutils
import monoucha/quickjs
import monoucha/tojs
import types/referrer
import types/url
import utils/twtstr

type
  ScriptingMode* = enum
    smFalse = "false"
    smTrue = "true"
    smApp = "app"

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
    scripting*: ScriptingMode
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
  let urls = '<' & baseURL.serialize() & '>'
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

proc setImportMeta*(ctx: JSContext; funcVal: JSValue; isMain: bool) =
  let m = cast[JSModuleDef](JS_VALUE_GET_PTR(funcVal))
  let moduleNameAtom = JS_GetModuleName(ctx, m)
  let metaObj = JS_GetImportMeta(ctx, m)
  doAssert ctx.definePropertyCWE(metaObj, "url",
    JS_AtomToValue(ctx, moduleNameAtom)) == dprSuccess
  doAssert ctx.definePropertyCWE(metaObj, "main", false) == dprSuccess
  JS_FreeValue(ctx, metaObj)
  JS_FreeAtom(ctx, moduleNameAtom)

proc normalizeModuleName*(ctx: JSContext; base_name, name: cstringConst;
    opaque: pointer): cstring {.cdecl.} =
  return js_strdup(ctx, cstring(name))

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

func uninitIfNull*(val: JSValue): JSValue =
  if JS_IsNull(val):
    return JS_UNINITIALIZED
  return val

proc defineConsts*(ctx: JSContext; classid: JSClassID; consts: typedesc[enum]) =
  let proto = JS_GetClassProto(ctx, classid)
  let ctor = ctx.getOpaque().ctors[classid]
  #TODO it should be enough to define on the proto only, but apparently
  # it isn't...
  for e in consts:
    let s = $e
    doAssert ctx.definePropertyE(proto, s, uint16(e)) == dprSuccess
    doAssert ctx.definePropertyE(ctor, s, uint16(e)) == dprSuccess
  JS_FreeValue(ctx, proto)

proc identity(ctx: JSContext; this_val: JSValueConst; argc: cint;
    argv: JSValueConstArray; magic: cint; func_data: JSValueConstArray): JSValue
    {.cdecl.} =
  return JS_DupValue(ctx, func_data[0])

#TODO move to javascript.nim?
proc identityFunction*(ctx: JSContext; val: JSValueConst): JSValue =
  return JS_NewCFunctionData(ctx, identity, 0, 0, 1, val.toJSValueArray())
