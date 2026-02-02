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
import std/options
import std/sets

import chame/tags
import monoucha/fromjs
import monoucha/quickjs
import monoucha/tojs
import types/jsopt
import utils/twtstr

# create a static enum compatible with chame/tags

macro makeStaticAtom =
  # declare inside the macro to avoid confusion with StaticAtom0
  type
    StaticAtom0 = enum
      satAbort = "abort"
      satAccept = "accept"
      satAcceptCharset = "accept-charset"
      satAction = "action"
      satAlign = "align"
      satAlink = "alink"
      satAlt = "alt"
      satAlternate = "alternate"
      satAnonymous = "anonymous"
      satApplicationXml = "application/xml"
      satApplicationXmlHtml = "application/xml+html"
      satAsync = "async"
      satAutofocus = "autofocus"
      satAxis = "axis"
      satBgcolor = "bgcolor"
      satBlocking = "blocking"
      satBlur = "blur"
      satBorder = "border"
      satCellspacing = "cellspacing"
      satChange = "change"
      satCharset = "charset"
      satChecked = "checked"
      satClass = "class"
      satClassName = "className"
      satClear = "clear"
      satClick = "click"
      satCodetype = "codetype"
      satColor = "color"
      satColorDashProfile = "color-profile"
      satCols = "cols"
      satColspan = "colspan"
      satCompact = "compact"
      satContent = "content"
      satContextmenu = "contextmenu"
      satCrossorigin = "crossorigin"
      satCustomevent = "customevent"
      satDOMContentLoaded = "DOMContentLoaded"
      satDashChaHintCounter = "-cha-hint-counter"
      satDashChaLinkCounter = "-cha-link-counter"
      satDatetime = "datetime"
      satDblclick = "dblclick"
      satDeclare = "declare"
      satDefaultSelected = "defaultSelected"
      satDefer = "defer"
      satDirection = "direction"
      satDirname = "dirname"
      satDisabled = "disabled"
      satEnctype = "enctype"
      satError = "error"
      satEvent = "event"
      satEvents = "events"
      satFocus = "focus"
      satFontDashFace = "font-face"
      satFontDashFaceDashFormat = "font-face-format"
      satFontDashFaceDashName = "font-face-name"
      satFontDashFaceDashSrc = "font-face-src"
      satFontDashFaceDashUri = "font-face-uri"
      satFor = "for"
      satForm = "form"
      satFormaction = "formaction"
      satFormenctype = "formenctype"
      satFormmethod = "formmethod"
      satHCrossOrigin = "crossOrigin"
      satHDateTime = "dateTime"
      satHFormMethod = "formMethod"
      satHHttpEquiv = "httpEquiv"
      satHIsMap = "isMap"
      satHNoValidate = "noValidate"
      satHReferrerPolicy = "referrerPolicy"
      satHUseMap = "useMap"
      satHash = "hash"
      satHeight = "height"
      satHost = "host"
      satHostname = "hostname"
      satHref = "href"
      satHreflang = "hreflang"
      satHtmlFor = "htmlFor"
      satHtmlevents = "htmlevents"
      satId = "id"
      satImageSvgXml = "image/svg+xml"
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
      satMissingDashGlyph = "missing-glyph"
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
      satNohref = "nohref"
      satNomodule = "nomodule"
      satNoresize = "noresize"
      satNoshade = "noshade"
      satNovalidate = "novalidate"
      satNowrap = "nowrap"
      satOnblur = "onblur"
      satOnchange = "onchange"
      satOnclick = "onclick"
      satOncontextmenu = "oncontextmenu"
      satOndblclick = "ondblclick"
      satOnerror = "onerror"
      satOnfocus = "onfocus"
      satOninput = "oninput"
      satOnload = "onload"
      satOnsubmit = "onsubmit"
      satOpen = "open"
      satOrigin = "origin"
      satPassword = "password"
      satPathname = "pathname"
      satPort = "port"
      satProgress = "progress"
      satProtocol = "protocol"
      satReadonly = "readonly"
      satReadystatechange = "readystatechange"
      satReferrerpolicy = "referrerpolicy"
      satRel = "rel"
      satRequired = "required"
      satRev = "rev"
      satRows = "rows"
      satRowspan = "rowspan"
      satRules = "rules"
      satScope = "scope"
      satScrolling = "scrolling"
      satSearch = "search"
      satSelected = "selected"
      satShape = "shape"
      satSize = "size"
      satSizes = "sizes"
      satSlot = "slot"
      satSrc = "src"
      satSrcset = "srcset"
      satStart = "start"
      satStyle = "style"
      satStylesheet = "stylesheet"
      satSubmit = "submit"
      satSvgevents = "svgevents"
      satTarget = "target"
      satText = "text"
      satTextHtml = "text/html"
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
      satValuetype = "valuetype"
      satVlink = "vlink"
      satWheel = "wheel"
      satWidth = "width"
      satXlink = "xlink"
      satXml = "xml"
      satXmlns = "xmlns"
  let decl = quote do:
    type StaticAtom* {.inject.} = enum
      satUnknown = ""
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
proc `==`*(a, b: CAtom): bool {.borrow.}
proc hash*(atom: CAtom): Hash {.borrow.}

proc toAtom(factory: var CAtomFactoryObj; s: openArray[char]; addLower = true):
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

proc toLowerAscii*(a: CAtom): CAtom =
  return getFactory().lowerMap[int32(a)]

proc equalsIgnoreCase*(a, b: CAtom): bool =
  return getFactory().lowerMap[int32(a)] == getFactory().lowerMap[int32(b)]

proc containsIgnoreCase*(aa: openArray[CAtom]; a: CAtom): bool =
  let a = a.toLowerAscii()
  for it in aa:
    if a == it.toLowerAscii():
      return true
  return false

proc toAtom*(s: openArray[char]): CAtom =
  return getFactory()[].toAtom(s)

proc toAtom*(tagType: TagType): CAtom =
  assert tagType != TAG_UNKNOWN
  return CAtom(tagType)

proc toAtom*(attrType: StaticAtom): CAtom =
  assert attrType != satUnknown
  return CAtom(attrType)

proc toAtomLower*(s: openArray[char]): CAtom =
  return getFactory().lowerMap[int32(s.toAtom())]

proc containsIgnoreCase*(aa: openArray[CAtom]; a: StaticAtom): bool =
  return aa.containsIgnoreCase(a.toAtom())

proc `$`*(atom: CAtom): lent string =
  return getFactory().atomMap[int(atom)]

proc toTagType*(atom: CAtom): TagType =
  let i = int(atom)
  if i <= int(TagType.high):
    return TagType(i)
  return TAG_UNKNOWN

proc toStaticAtom*(atom: CAtom): StaticAtom =
  let i = int(atom)
  if i <= int(StaticAtom.high):
    return StaticAtom(i)
  return satUnknown

proc toStaticAtom*(s: string): StaticAtom =
  let factory = getFactory()
  let h = s.hash()
  let i = h and (factory.strMap.len - 1)
  for atom in factory.strMap[i]:
    if factory.atomMap[int(atom)] == s:
      # Found
      return atom.toStaticAtom()
  satUnknown

proc toNamespace*(atom: CAtom): Namespace =
  case atom.toStaticAtom()
  of satUempty: return NO_NAMESPACE
  of satNamespaceHTML: return Namespace.HTML
  of satNamespaceMathML: return Namespace.MATHML
  of satNamespaceSVG: return Namespace.SVG
  of satNamespaceXLink: return Namespace.XLINK
  of satNamespaceXML: return Namespace.XML
  of satNamespaceXMLNS: return Namespace.XMLNS
  else: return NAMESPACE_UNKNOWN

proc toAtom*(namespace: Namespace): CAtom =
  return (case namespace
  of NO_NAMESPACE: satUempty
  of Namespace.HTML: satNamespaceHTML
  of Namespace.MATHML: satNamespaceMathML
  of Namespace.SVG: satNamespaceSVG
  of Namespace.XLINK: satNamespaceXLink
  of Namespace.XML: satNamespaceXML
  of Namespace.XMLNS: satNamespaceXMLNS
  of NAMESPACE_UNKNOWN: satUempty).toAtom()

proc toAtom*(prefix: NamespacePrefix): CAtom =
  return (case prefix
  of NO_PREFIX: satUempty
  of PREFIX_XLINK: satXlink
  of PREFIX_XML: satXml
  of PREFIX_XMLNS: satXmlns
  of PREFIX_UNKNOWN: satUempty).toAtom()

proc toAtom*(val: Option[string]): CAtom =
  if val.isSome:
    return val.unsafeGet.toAtom()
  CAtomNull

proc `==`*(a: CAtom; b: StaticAtom): bool =
  a.toStaticAtom() == b

proc `==`*(a: StaticAtom; b: CAtom): bool =
  a == b.toStaticAtom()

proc contains*(a: openArray[CAtom]; b: StaticAtom): bool =
  b.toAtom() in a

proc contains*(a: openArray[StaticAtom]; b: CAtom): bool =
  b.toStaticAtom() in a

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var CAtom): FromJSResult =
  if JS_IsNull(val):
    res = CAtomNull
  else:
    var len: csize_t
    let cs = JS_ToCStringLen(ctx, len, val)
    if cs == nil:
      return fjErr
    if len > csize_t(int.high):
      JS_FreeCString(ctx, cs)
      JS_ThrowRangeError(ctx, "string length out of bounds")
      return fjErr
    {.push overflowChecks: off.}
    let H = cast[int](len) - 1
    {.pop.}
    res = cs.toOpenArray(0, H).toAtom()
    JS_FreeCString(ctx, cs)
  fjOk

proc fromJS*(ctx: JSContext; val: JSAtom; res: var CAtom): FromJSResult =
  if val == JS_ATOM_NULL:
    res = CAtomNull
  else:
    var s: string
    ?ctx.fromJS(val, s)
    res = s.toAtom()
  fjOk

proc fromJS*(ctx: JSContext; val: JSAtom; res: var StaticAtom): FromJSResult =
  var ca: CAtom
  ?ctx.fromJS(val, ca)
  res = ca.toStaticAtom()
  fjOk

type FromIdxResult* = enum
  fiIdx, fiStr, fiErr

proc fromIdx*[T: string|CAtom](ctx: JSContext; atom: JSAtom; idx: var uint32;
    s: var T): FromIdxResult =
  let val = JS_AtomIsNumericIndex1(ctx, atom)
  if JS_IsException(val):
    return fiErr
  var i: int64
  if not JS_IsUndefined(val) and ctx.fromJSFree(val, i).isOk and
      i in 0..int64(uint32.high - 1):
    idx = uint32(i)
    return fiIdx
  elif ctx.fromJS(atom, s).isOk:
    return fiStr
  fiErr

proc fromIdx*(ctx: JSContext; atom: JSAtom; idx: var uint32): FromIdxResult =
  var dummy: string
  ctx.fromIdx(atom, idx, dummy)

proc toJS*(ctx: JSContext; atom: CAtom): JSValue =
  if atom == CAtomNull:
    return JS_NULL
  return ctx.toJS($atom)
