# String interning.
# Currently, interned strings do not have a reference count, so it is
# best to use them cautiously (as they technically leak memory).
# This could be changed if we switched to ORC, but ORC is still utterly
# broken in the latest version.  What can you do...
# (If this turns out to be an issue in practice, we can always turn
# atoms into ref objects; that would work with refc, but it would also
# add a lot of overhead.)

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
      satBlur = "blur"
      satCellspacing = "cellspacing"
      satChange = "change"
      satCharset = "charset"
      satChecked = "checked"
      satClass = "class"
      satClassList = "classList"
      satClassName = "className"
      satClick = "click"
      satColor = "color"
      satCols = "cols"
      satColspan = "colspan"
      satContent = "content"
      satCrossorigin = "crossorigin"
      satCustomevent = "customevent"
      satDOMContentLoaded = "DOMContentLoaded"
      satDatetime = "datetime"
      satDefaultSelected = "defaultSelected"
      satDefer = "defer"
      satDirname = "dirname"
      satDisabled = "disabled"
      satEnctype = "enctype"
      satError = "error"
      satEvent = "event"
      satEvents = "events"
      satFocus = "focus"
      satFor = "for"
      satForm = "form"
      satFormaction = "formaction"
      satFormenctype = "formenctype"
      satFormmethod = "formmethod"
      satHDateTime = "dateTime"
      satHHttpEquiv = "httpEquiv"
      satHIsMap = "isMap"
      satHNoValidate = "noValidate"
      satHUseMap = "useMap"
      satHash = "hash"
      satHeight = "height"
      satHost = "host"
      satHostname = "hostname"
      satHref = "href"
      satHtmlFor = "htmlFor"
      satHtmlevents = "htmlevents"
      satId = "id"
      satIntegrity = "integrity"
      satIsmap = "ismap"
      satLang = "lang"
      satLanguage = "language"
      satListItem = "list-item"
      satLoad = "load"
      satLoadend = "loadend"
      satLoadstart = "loadstart"
      satMax = "max"
      satMedia = "media"
      satMessage = "message"
      satMethod = "method"
      satMin = "min"
      satMouseevent = "mouseevent"
      satMouseevents = "mouseevents"
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
      satOnblur = "onblur"
      satOnchange = "onchange"
      satOnclick = "onclick"
      satOnerror = "onerror"
      satOnfocus = "onfocus"
      satOninput = "oninput"
      satOnload = "onload"
      satOpen = "open"
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
      satStart = "start"
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
      satUievent = "uievent"
      satUievents = "uievents"
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
  var seen = HashSet[string].default
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

const CAtomFactoryStrMapLength = 2048 # must be a power of 2
static:
  doAssert (CAtomFactoryStrMapLength and (CAtomFactoryStrMapLength - 1)) == 0

type
  CAtom* = distinct uint32

  CAtomFactoryObj = object
    strMap: array[CAtomFactoryStrMapLength, seq[CAtom]]
    atomMap: seq[string]
    lowerMap: seq[CAtom]

  CAtomFactory = ptr CAtomFactoryObj

# This maps to JS null.
const CAtomNull* = CAtom(0)

# Mandatory Atom functions
func `==`*(a, b: CAtom): bool {.borrow.}
func hash*(atom: CAtom): Hash {.borrow.}

func toAtom(factory: var CAtomFactoryObj; s: openArray[char]; addLower = true):
    CAtom =
  let h = s.hash()
  let i = h and (factory.strMap.len - 1)
  for atom in factory.strMap[i]:
    if factory.atomMap[int(atom)] == s:
      # Found
      return atom
  # Not found
  let atom = CAtom(factory.atomMap.len)
  var ss = newString(s.len)
  if s.len > 0:
    copyMem(addr ss[0], unsafeAddr s[0], s.len)
  var lower = ""
  if addLower and AsciiUpperAlpha in ss:
    lower = ss.toLowerAscii()
  factory.atomMap.add(move(ss))
  if addLower:
    if lower == "":
      factory.lowerMap.add(atom)
    else:
      factory.lowerMap.add(factory.toAtom(lower))
  factory.strMap[i].add(atom)
  return atom

var factory {.global.}: CAtomFactoryObj

template getFactory(): CAtomFactory =
  {.cast(noSideEffect).}:
    addr factory

proc initCAtomFactory*() =
  # Null atom
  factory.atomMap.add("")
  factory.lowerMap.add(CAtom(0))
  # StaticAtom includes TagType too.
  for sa in StaticAtom(1) .. StaticAtom.high:
    discard factory.toAtom($sa, addLower = false)
  for sa in StaticAtom(1) .. StaticAtom.high:
    let atom = factory.toAtom(($sa).toLowerAscii(), addLower = false)
    factory.lowerMap.add(atom)
  # fill slots of newly added lower mappings
  while factory.lowerMap.len < factory.atomMap.len:
    factory.lowerMap.add(CAtom(factory.lowerMap.len))

func toLowerAscii*(a: CAtom): CAtom =
  return getFactory().lowerMap[int32(a)]

func equalsIgnoreCase*(a, b: CAtom): bool =
  return getFactory().lowerMap[int32(a)] == getFactory().lowerMap[int32(b)]

func containsIgnoreCase*(aa: openArray[CAtom]; a: CAtom): bool =
  let a = a.toLowerAscii()
  for it in aa:
    if a == it.toLowerAscii():
      return true
  return false

proc toAtom*(s: openArray[char]): CAtom {.sideEffect.} =
  return getFactory()[].toAtom(s)

func toAtom*(tagType: TagType): CAtom =
  assert tagType != TAG_UNKNOWN
  return CAtom(tagType)

func toAtom*(attrType: StaticAtom): CAtom =
  assert attrType != atUnknown
  return CAtom(attrType)

proc toAtomLower*(s: openArray[char]): CAtom {.sideEffect.} =
  return getFactory().lowerMap[int32(s.toAtom())]

func containsIgnoreCase*(aa: openArray[CAtom]; a: StaticAtom): bool =
  return aa.containsIgnoreCase(a.toAtom())

func `$`*(atom: CAtom): lent string =
  return getFactory().atomMap[int(atom)]

func toTagType*(atom: CAtom): TagType =
  let i = int(atom)
  if i <= int(TagType.high):
    return TagType(i)
  return TAG_UNKNOWN

func toStaticAtom*(atom: CAtom): StaticAtom =
  let i = int(atom)
  if i <= int(StaticAtom.high):
    return StaticAtom(i)
  return atUnknown

func toStaticAtom*(s: string): StaticAtom =
  let factory = getFactory()
  let h = s.hash()
  let i = h and (factory.strMap.len - 1)
  for atom in factory.strMap[i]:
    if factory.atomMap[int(atom)] == s:
      # Found
      return atom.toStaticAtom()
  atUnknown

func toNamespace*(atom: CAtom): Namespace =
  case atom.toStaticAtom()
  of satUempty: return NO_NAMESPACE
  of satNamespaceHTML: return Namespace.HTML
  of satNamespaceMathML: return Namespace.MATHML
  of satNamespaceSVG: return Namespace.SVG
  of satNamespaceXLink: return Namespace.XLINK
  of satNamespaceXML: return Namespace.XML
  of satNamespaceXMLNS: return Namespace.XMLNS
  else: return NAMESPACE_UNKNOWN

func toAtom*(namespace: Namespace): CAtom =
  return (case namespace
  of NO_NAMESPACE: satUempty
  of Namespace.HTML: satNamespaceHTML
  of Namespace.MATHML: satNamespaceMathML
  of Namespace.SVG: satNamespaceSVG
  of Namespace.XLINK: satNamespaceXLink
  of Namespace.XML: satNamespaceXML
  of Namespace.XMLNS: satNamespaceXMLNS
  of NAMESPACE_UNKNOWN: satUempty).toAtom()

func toAtom*(prefix: NamespacePrefix): CAtom =
  return (case prefix
  of NO_PREFIX: satUempty
  of PREFIX_XLINK: satXlink
  of PREFIX_XML: satXml
  of PREFIX_XMLNS: satXmlns
  of PREFIX_UNKNOWN: satUempty).toAtom()

proc `==`*(a: CAtom; b: StaticAtom): bool =
  a.toStaticAtom() == b

proc `==`*(a: StaticAtom; b: CAtom): bool =
  a == b.toStaticAtom()

proc contains*(a: openArray[CAtom]; b: StaticAtom): bool =
  b.toAtom() in a

proc contains*(a: openArray[StaticAtom]; b: CAtom): bool =
  b.toStaticAtom() in a

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var CAtom): Opt[void] =
  if JS_IsNull(val):
    res = CAtomNull
  else:
    var len: csize_t
    let cs = JS_ToCStringLen(ctx, len, val)
    if cs == nil:
      return err()
    if len > csize_t(int.high):
      JS_FreeCString(ctx, cs)
      return err()
    {.push overflowChecks: off.}
    let H = cast[int](len) - 1
    {.pop.}
    res = cs.toOpenArray(0, H).toAtom()
    JS_FreeCString(ctx, cs)
  ok()

proc fromJS*(ctx: JSContext; val: JSAtom; res: var CAtom): Opt[void] =
  if val == JS_ATOM_NULL:
    res = CAtomNull
  else:
    var s: string
    ?ctx.fromJS(val, s)
    res = s.toAtom()
  ok()

proc fromJS*(ctx: JSContext; val: JSAtom; res: var StaticAtom): Opt[void] =
  var ca: CAtom
  ?ctx.fromJS(val, ca)
  res = ca.toStaticAtom()
  ok()

proc toJS*(ctx: JSContext; atom: CAtom): JSValue =
  if atom == CAtomNull:
    return JS_NULL
  return ctx.toJS($atom)

proc toJS*(ctx: JSContext; atom: StaticAtom): JSValue =
  return ctx.toJS($atom)
