import std/hashes
import std/macros
import std/sets
import std/strutils

import chame/tags
import monoucha/fromjs
import monoucha/javascript
import monoucha/quickjs
import monoucha/tojs
import types/opt
import utils/twtstr

# create a static enum compatible with chame/tags

macro makeStaticAtom =
  # declare inside the macro to avoid confusion with StaticAtom0
  type
    StaticAtom0 = enum
      satAbort = "abort"
      satAcceptCharset = "accept-charset"
      satAction = "action"
      satAlign = "align"
      satAlt = "alt"
      satAlternate = "alternate"
      satAsync = "async"
      satAutofocus = "autofocus"
      satBgcolor = "bgcolor"
      satBlocking = "blocking"
      satCellspacing = "cellspacing"
      satChange = "change"
      satCharset = "charset"
      satChecked = "checked"
      satClass = "class"
      satClassList = "classList"
      satClick = "click"
      satColor = "color"
      satCols = "cols"
      satColspan = "colspan"
      satContent = "content"
      satCrossorigin = "crossorigin"
      satCustomevent = "customevent"
      satDOMContentLoaded = "DOMContentLoaded"
      satDefer = "defer"
      satDirname = "dirname"
      satDisabled = "disabled"
      satEnctype = "enctype"
      satError = "error"
      satEvent = "event"
      satEvents = "events"
      satFor = "for"
      satForm = "form"
      satFormaction = "formaction"
      satFormenctype = "formenctype"
      satFormmethod = "formmethod"
      satHash = "hash"
      satHeight = "height"
      satHost = "host"
      satHostname = "hostname"
      satHref = "href"
      satId = "id"
      satIntegrity = "integrity"
      satIsmap = "ismap"
      satLanguage = "language"
      satLoad = "load"
      satLoadend = "loadend"
      satLoadstart = "loadstart"
      satMax = "max"
      satMedia = "media"
      satMessage = "message"
      satMethod = "method"
      satMin = "min"
      satMousewheel = "mousewheel"
      satMultiple = "multiple"
      satName = "name"
      satNamespaceHTML = "http://www.w3.org/1999/xhtml",
      satNamespaceMathML = "http://www.w3.org/1998/Math/MathML",
      satNamespaceSVG = "http://www.w3.org/2000/svg",
      satNamespaceXLink = "http://www.w3.org/1999/xlink",
      satNamespaceXML = "http://www.w3.org/XML/1998/namespace",
      satNamespaceXMLNS = "http://www.w3.org/2000/xmlns/",
      satNomodule = "nomodule"
      satNovalidate = "novalidate"
      satOnchange = "onchange"
      satOnclick = "onclick"
      satOnload = "onload"
      satOrigin = "origin"
      satPassword = "password"
      satPathname = "pathname"
      satPort = "port"
      satProgress = "progress"
      satProtocol = "protocol"
      satReadystatechange = "readystatechange"
      satReferrerpolicy = "referrerpolicy"
      satRel = "rel"
      satRequired = "required"
      satRows = "rows"
      satRowspan = "rowspan"
      satSearch = "search"
      satSelected = "selected"
      satSize = "size"
      satSizes = "sizes"
      satSlot = "slot"
      satSrc = "src"
      satSrcset = "srcset"
      satStyle = "style"
      satStylesheet = "stylesheet"
      satSvgevents = "svgevents"
      satTarget = "target"
      satText = "text"
      satTimeout = "timeout"
      satTitle = "title"
      satToString = "toString"
      satTouchmove = "touchmove"
      satTouchstart = "touchstart"
      satType = "type"
      satUempty = ""
      satUsemap = "usemap"
      satUsername = "username"
      satValign = "valign"
      satValue = "value"
      satWheel = "wheel"
      satWidth = "width"
      satXlink = "xlink"
      satXml = "xml"
      satXmlns = "xmlns"
  let decl = quote do:
    type StaticAtom* {.inject.} = enum
      atUnknown = ""
  let decl0 = decl[0][2]
  var seen: HashSet[string]
  for t in TagType:
    if t == TAG_UNKNOWN:
      continue
    let tn = $t
    let name = "sat" & tn[0].toUpperAscii() & tn.substr(1).kebabToCamelCase()
    seen.incl(tn)
    decl0.add(newNimNode(nnkEnumFieldDef).add(ident(name), newStrLitNode(tn)))
  for i, f in StaticAtom0.getType():
    if i == 0:
      continue
    let tn = $StaticAtom0(i - 1)
    if tn in seen:
      continue
    decl0.add(newNimNode(nnkEnumFieldDef).add(ident(f.strVal),
      newStrLitNode(tn)))
  decl

makeStaticAtom

#TODO use a better hash map
const CAtomFactoryStrMapLength = 1024 # must be a power of 2
static:
  doAssert (CAtomFactoryStrMapLength and (CAtomFactoryStrMapLength - 1)) == 0

type
  CAtom* = distinct uint32

  CAtomFactoryInit = object
    obj: CAtomFactoryObj

  CAtomFactoryObj = object
    strMap: array[CAtomFactoryStrMapLength, seq[CAtom]]
    atomMap: seq[string]
    lowerMap: seq[CAtom]
    namespaceMap: array[Namespace, CAtom]
    prefixMap: array[NamespacePrefix, CAtom]

  #TODO could be a ptr probably
  CAtomFactory* = ref CAtomFactoryObj

# This maps to JS null.
const CAtomNull* = CAtom(0)

# Mandatory Atom functions
func `==`*(a, b: CAtom): bool {.borrow.}
func hash*(atom: CAtom): Hash {.borrow.}

when defined(debug):
  func `$`*(a: CAtom): string {.borrow.}

func toAtom(factory: var CAtomFactoryObj; s: sink string;
    isInit: static bool = false): CAtom =
  let h = s.hash()
  let i = h and (factory.strMap.len - 1)
  for atom in factory.strMap[i]:
    if factory.atomMap[int(atom)] == s:
      # Found
      return atom
  # Not found
  let atom = CAtom(factory.atomMap.len)
  factory.atomMap.add(s)
  when not isInit:
    let lower = if AsciiUpperAlpha notin s:
      atom
    else:
      factory.toAtom(s.toLowerAscii())
    factory.lowerMap.add(lower)
  factory.strMap[i].add(atom)
  return atom

const factoryInit = (func(): CAtomFactoryInit =
  var init = CAtomFactoryInit()
  # Null atom
  init.obj.atomMap.add("")
  init.obj.lowerMap.add(CAtom(0))
  # StaticAtom includes TagType too.
  for sa in StaticAtom(1) .. StaticAtom.high:
    discard init.obj.toAtom($sa, isInit = true)
  for sa in StaticAtom(1) .. StaticAtom.high:
    let atom = init.obj.toAtom(($sa).toLowerAscii(), isInit = true)
    init.obj.lowerMap.add(atom)
  # fill slots of newly added lower mappings
  while init.obj.lowerMap.len < init.obj.atomMap.len:
    init.obj.lowerMap.add(CAtom(init.obj.lowerMap.len))
  let olen = init.obj.atomMap.len
  for it in Namespace:
    if it == NO_NAMESPACE:
      init.obj.namespaceMap[it] = CAtomNull
    else:
      init.obj.namespaceMap[it] = init.obj.toAtom($it)
  for it in NamespacePrefix:
    if it == NO_PREFIX:
      init.obj.prefixMap[it] = CAtomNull
    else:
      init.obj.prefixMap[it] = init.obj.toAtom($it)
  assert init.obj.atomMap.len == olen
  return init
)()

proc newCAtomFactory*(): CAtomFactory =
  let factory = new(CAtomFactory)
  factory[] = factoryInit.obj
  return factory

func toLowerAscii*(factory: CAtomFactory; a: CAtom): CAtom =
  return factory.lowerMap[int32(a)]

func equalsIgnoreCase*(factory: CAtomFactory; a, b: CAtom): bool =
  return factory.lowerMap[int32(a)] == factory.lowerMap[int32(b)]

func containsIgnoreCase*(factory: CAtomFactory; aa: openArray[CAtom];
    a: CAtom): bool =
  let a = factory.toLowerAscii(a)
  for it in aa:
    if a == factory.toLowerAscii(it):
      return true
  return false

func toAtom*(factory: CAtomFactory; s: sink string): CAtom =
  return factory[].toAtom(s)

func toAtom*(factory: CAtomFactory; tagType: TagType): CAtom =
  assert tagType != TAG_UNKNOWN
  return CAtom(tagType)

func toAtom*(factory: CAtomFactory; attrType: StaticAtom): CAtom =
  assert attrType != atUnknown
  return CAtom(attrType)

func toAtomLower*(factory: CAtomFactory; s: sink string): CAtom =
  return factory.lowerMap[int32(factory.toAtom(s))]

func containsIgnoreCase*(factory: CAtomFactory; aa: openArray[CAtom];
    a: StaticAtom): bool =
  return factory.containsIgnoreCase(aa, factory.toAtom(a))

func toStr*(factory: CAtomFactory; atom: CAtom): lent string =
  return factory.atomMap[int(atom)]

func toStr*(factory: CAtomFactory; sa: StaticAtom): lent string =
  return factory.toStr(factory.toAtom(sa))

func toTagType*(atom: CAtom): TagType =
  let i = int(atom)
  if i <= int(TagType.high):
    return TagType(i)
  return TAG_UNKNOWN

func toStaticAtom*(factory: CAtomFactory; atom: CAtom): StaticAtom =
  let i = int(atom)
  if i <= int(StaticAtom.high):
    return StaticAtom(i)
  return atUnknown

func toStaticAtom*(factory: CAtomFactory; s: string): StaticAtom =
  return factory.toStaticAtom(factory.toAtom(s))

func toNamespace*(factory: CAtomFactory; atom: CAtom): Namespace =
  case factory.toStaticAtom(atom)
  of satUempty: return NO_NAMESPACE
  of satNamespaceHTML: return Namespace.HTML
  of satNamespaceMathML: return Namespace.MATHML
  of satNamespaceSVG: return Namespace.SVG
  of satNamespaceXLink: return Namespace.XLINK
  of satNamespaceXML: return Namespace.XML
  of satNamespaceXMLNS: return Namespace.XMLNS
  else: return NAMESPACE_UNKNOWN

func toAtom*(factory: CAtomFactory; namespace: Namespace): CAtom =
  return factory.namespaceMap[namespace]

func toAtom*(factory: CAtomFactory; prefix: NamespacePrefix): CAtom =
  return factory.prefixMap[prefix]

# Forward declaration hack
var getFactoryImpl*: proc(ctx: JSContext): CAtomFactory {.nimcall, noSideEffect,
  raises: [].}

proc toAtom*(ctx: JSContext; atom: StaticAtom): CAtom =
  return ctx.getFactoryImpl().toAtom(atom)

proc toAtom*(ctx: JSContext; s: string): CAtom =
  return ctx.getFactoryImpl().toAtom(s)

proc toStaticAtom*(ctx: JSContext; atom: CAtom): StaticAtom =
  return ctx.getFactoryImpl().toStaticAtom(atom)

proc toStaticAtom*(ctx: JSContext; s: string): StaticAtom =
  return ctx.getFactoryImpl().toStaticAtom(s)

proc toStr*(ctx: JSContext; atom: CAtom): lent string =
  return ctx.getFactoryImpl().toStr(atom)

proc toLowerAscii*(ctx: JSContext; atom: CAtom): CAtom =
  return ctx.getFactoryImpl().toLowerAscii(atom)

proc toStr*(ctx: JSContext; sa: StaticAtom): lent string =
  return ctx.getFactoryImpl().toStr(sa)

proc fromJS*(ctx: JSContext; val: JSValue; res: var CAtom): Opt[void] =
  if JS_IsNull(val):
    res = CAtomNull
  else:
    var s: string
    ?ctx.fromJS(val, s)
    res = ctx.getFactoryImpl().toAtom(s)
  return ok()

proc fromJS*(ctx: JSContext; val: JSAtom; res: var CAtom): Opt[void] =
  var s: string
  ?ctx.fromJS(val, s)
  res = ctx.getFactoryImpl().toAtom(s)
  return ok()

proc fromJS*(ctx: JSContext; val: JSAtom; res: var StaticAtom): Opt[void] =
  var ca: CAtom
  ?ctx.fromJS(val, ca)
  res = ctx.getFactoryImpl().toStaticAtom(ca)
  return ok()

proc toJS*(ctx: JSContext; atom: CAtom): JSValue =
  if atom == CAtomNull:
    return JS_NULL
  return ctx.toJS(ctx.getFactoryImpl().toStr(atom))

proc toJS*(ctx: JSContext; atom: StaticAtom): JSValue =
  return ctx.toJS($atom)
