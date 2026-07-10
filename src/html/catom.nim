# String interning with reference counts.
#
# There's a complication here: Nim hooks only work reliably with ORC, but
# we're stuck with refc because ORC still has some horrible bugs and
# generates garbage code.
#
# As an inbetween solution, we do "semi-automatic" refcounting where local
# variables are tracked with `=destroy`, but copy/dup hooks are not used
# and atom members are sometimes managed manually in finalizers.  This
# makes it so a compiler bug will, at worst, just cause a leak.
#
# On the different types:
#
# * StaticAtom is a pre-defined atom without a reference count.
# * CAtomTraced is an atom with automatic reference counting.  It is
#   still not possible to copy these; instead, when you have to dup the
#   atom, use dupTrace().
# * CAtom is an atom with manual refcounting.
#
# TODO: in the past, we didn't bother with refcounting atoms, and there is
# still some code that straight out leaks them, in particular the HTML
# parser.  Of course, the goal is to plug all leaks eventually.

{.push raises: [].}

import std/hashes
import std/macros
import std/sets

import chame/tags
import monoucha/fromjs
import monoucha/jstypes
import monoucha/quickjs
import monoucha/tojs
import types/jsopt
import utils/tabutil
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
      satInternals = "internals"
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
      satShadow = "shadow"
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
      satUstar = "*"
      satValign = "valign"
      satValue = "value"
      satValuetype = "valuetype"
      satVlink = "vlink"
      satWheel = "wheel"
      satWidth = "width"
      satXml = "xml"
      satXmlns = "xmlns"
  let decl = quote do:
    type StaticAtom* {.inject.} = enum
      satUnknown = ""
  let decl0 = decl[0][2]
  var seen = HashSet[string].default
  for t in TagType:
    if t == ttUnknown:
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

const CAtomFactoryInitSize* = 2048 # must be a power of 2

type
  CAtom* = distinct uint32

  AtomDesc = object
    s: string
    freeNext: uint32 # if free'd, points to next item in free list
    refc: uint32
    hcache: Hash

  CAtomFactoryObj = object
    tab: seq[uint32] # hash table; length is a power of 2
    atomMap: seq[AtomDesc]
    freeHead: uint32

  CAtomFactory = ptr CAtomFactoryObj

  CAtomTraced* = distinct CAtom

# This maps to JS null.
const CAtomNull* = CAtom(0)

# Mandatory Atom functions
proc `==`*(a, b: CAtom): bool {.borrow.}
proc cmp*(a, b: CAtom): int {.borrow.}

var factory {.global.}: CAtomFactoryObj

template getFactory(): CAtomFactory =
  addr factory

proc hash*(atom: CAtom): Hash =
  getFactory().atomMap[uint32(atom)].hcache

proc freeAtomImpl(u: uint32) =
  let factory = getFactory()
  factory.atomMap[u].s = ""
  factory.atomMap[u].freeNext = factory.freeHead
  factory.freeHead = u
  let mask = (factory.tab.len - 1)
  var i = factory.atomMap[u].hcache and mask
  while true:
    if factory.tab[i] == u:
      factory.tab[i] = 0
      break
    i = (i + 1) and mask
  var j = i
  while true:
    j = (j + 1) and mask
    let it = factory.tab[j]
    if it == 0:
      break
    let k = factory.atomMap[it].hcache and mask
    if j == k: # already at home
      break
    # backwards shift
    factory.tab[i] = move(factory.tab[j])
    i = j

proc freeAtom*(atom: CAtom) =
  let u = uint32(atom)
  if u > uint32(StaticAtom.high):
    let factory = getFactory()
    let desc = addr factory.atomMap[uint32(atom)]
    when defined(debug):
      assert desc.refc > 0
    dec desc.refc
    if desc.refc == 0:
      freeAtomImpl(u)

proc freeAtoms*(atoms: openArray[CAtom]) =
  for a in atoms:
    freeAtom(a)

proc dup*(atom: CAtom): CAtom =
  let factory = getFactory()
  inc factory.atomMap[uint32(atom)].refc
  atom

proc `=copy`*(x: var CAtomTraced; y: CAtomTraced) {.error.} =
  discard

proc `=destroy`*(atom: var CAtomTraced) =
  freeAtom(CAtom(atom))

template dup*(atom: CAtomTraced): CAtom =
  CAtom(atom).dup()

template trace(atom: CAtom): CAtomTraced =
  CAtomTraced(atom)

template dupTrace*(atom: CAtom): CAtomTraced =
  CAtomTraced(atom.dup())

template dupTrace*(atom: CAtomTraced): CAtomTraced =
  CAtomTraced(CAtom(atom).dup())

proc view*(atom: CAtom): lent CAtomTraced =
  CAtomTraced(atom)

template view*(atom: CAtomTraced): CAtom =
  CAtom(atom)

proc put0(factory: CAtomFactory; atom: uint32) =
  let mask = factory.tab.len - 1
  var home = CAtom(atom).hash() and mask
  var i = home
  var atom = atom
  while true:
    let it = factory.tab[i]
    if it == 0:
      factory.tab[i] = atom
      break
    if tabSwap(home, CAtom(it).hash(), i, mask): # displace
      swap(factory.tab[i], atom)
    i = (i + 1) and mask

proc get(factory: CAtomFactory; s: openArray[char]; h: Hash): CAtom =
  let mask = (factory.tab.len - 1)
  var i = h and mask
  while true:
    let atom = factory.tab[i]
    if atom == 0:
      break
    if factory.atomMap[int(atom)].s == s:
      return CAtom(atom)
    i = (i + 1) and mask
  return CAtomNull

proc toAtomImpl(factory: CAtomFactory; s: openArray[char];
    added: var bool): CAtom =
  let h = s.hash()
  if (let atom = factory.get(s, h); atom != CAtomNull):
    inc factory.atomMap[int(atom)].refc
    return atom
  var u = factory.freeHead
  if u != 0:
    factory.freeHead = factory.atomMap[factory.freeHead].freeNext
  else:
    # Not found
    for atom in factory.tab.prepareTableAdd(factory.atomMap.len, 0):
      if atom != 0:
        factory.put0(atom)
    u = uint32(factory.atomMap.len)
    factory.atomMap.add(AtomDesc())
  factory.atomMap[u] = AtomDesc(refc: 1, hcache: h)
  factory.put0(u)
  added = true
  CAtom(u)

proc toAtom(factory: CAtomFactory; s: openArray[char]): CAtom =
  var added = false
  let atom = factory.toAtomImpl(s, added)
  if added:
    factory.atomMap[int(atom)].s = s.substr()
  atom

proc toAtomView*(s: openArray[char]): CAtom =
  let h = s.hash()
  getFactory().get(s, h)

proc initCAtomFactory*() =
  let factory = getFactory()
  factory.tab = newSeq[uint32](CAtomFactoryInitSize)
  # Null atom
  factory.atomMap.add(AtomDesc())
  # StaticAtom includes TagType too.
  for sa in StaticAtom(1) .. StaticAtom.high:
    discard factory.toAtom($sa)

proc toAtom*(s: openArray[char]): CAtom =
  return getFactory().toAtom(s)

proc toAtomTrace*(s: openArray[char]): CAtomTraced =
  s.toAtom().trace()

proc toAtomTrace*(s: DOMString): CAtomTraced =
  s.toOpenArray().toAtomTrace()

proc toStaticAtom*(tagType: TagType): StaticAtom =
  assert tagType != ttUnknown
  StaticAtom(uint32(tagType))

proc toAtom*(tagType: TagType): CAtom =
  assert tagType != ttUnknown
  return CAtom(tagType)

proc toAtom*(satom: StaticAtom): CAtom =
  assert satom != satUnknown
  return CAtom(satom)

proc toAtomLower*(s: openArray[char]): CAtom =
  let factory = getFactory()
  var added = false
  var s = s.toLowerAscii()
  let atom = factory.toAtomImpl(s, added)
  if added:
    factory.atomMap[int(atom)].s = move(s)
  atom

proc toAtomTrace*(satom: StaticAtom): CAtomTraced =
  satom.toAtom().trace()

template view*(satom: StaticAtom): lent CAtomTraced =
  satom.toAtom().view()

proc `$`*(atom: CAtom): lent string =
  return getFactory().atomMap[int(atom)].s

proc `$`*(atom: CAtomTraced): lent string =
  $CAtom(atom)

proc find*(atom: CAtom; c: char): int =
  ($atom).find(c)

proc find*(atom: CAtomTraced; c: char): int =
  CAtom(atom).find(c)

proc len*(atom: CAtom): int =
  ($atom).len

proc len*(atom: CAtomTraced): int =
  CAtom(atom).len

proc substr*(atom: CAtom; first, last: int): CAtom =
  let atomLen = atom.len
  if first >= atomLen:
    return satUempty.toAtom()
  let last = min(last, atomLen - 1)
  ($atom).toOpenArray(first, last).toAtom()

proc substr*(atom: CAtom; first: int): CAtom =
  atom.substr(first, ($atom).high)

proc substrTrace*(atom: CAtomTraced; first, last: int): CAtomTraced =
  CAtom(atom).substr(first, last).trace()

proc substrTrace*(atom: CAtomTraced; first: int): CAtomTraced =
  CAtom(atom).substr(first).trace()

proc contains*(atom: CAtomTraced; c: char): bool =
  c in $atom

proc contains*(atom: CAtom; cs: set[char]): bool =
  cs in $atom

proc contains*(atom: CAtomTraced; cs: set[char]): bool {.borrow.}

proc toLowerAscii*(a: CAtom): CAtom =
  if AsciiUpperAlpha notin a:
    return a.dup()
  return ($a).toAtomLower()

proc toLowerAscii*(a: CAtomTraced): CAtomTraced =
  CAtom(a).toLowerAscii().trace()

proc equalsIgnoreCase*(a, b: CAtom): bool =
  a == b or ($a).equalsIgnoreCase($b)

proc equalsIgnoreCase*(a: CAtomTraced; b: CAtom): bool =
  a.view().equalsIgnoreCase(b)

proc containsIgnoreCase*(aa: openArray[CAtom]; a: CAtom): bool =
  for it in aa:
    if a.equalsIgnoreCase(it):
      return true
  return false

proc toAtomLowerTrace*(s: openArray[char]): CAtomTraced =
  s.toAtom().toLowerAscii().trace()

proc toAtomLowerTrace*(s: DOMString): CAtomTraced =
  s.toOpenArray().toAtomLowerTrace()

proc containsIgnoreCase*(aa: openArray[CAtom]; a: StaticAtom): bool =
  return aa.containsIgnoreCase(a.toAtom())

proc toTagType*(atom: CAtom): TagType =
  let i = int(atom)
  if i <= int(TagType.high):
    return TagType(i)
  return ttUnknown

proc toTagType*(atom: CAtomTraced): TagType {.borrow.}

proc toStaticAtom*(atom: CAtom): StaticAtom =
  let i = int(atom)
  if i <= int(StaticAtom.high):
    return StaticAtom(i)
  return satUnknown

proc toStaticAtom*(atom: CAtomTraced): StaticAtom {.borrow.}

proc toStaticAtomLower*(atom: CAtomTraced): StaticAtom =
  let atom = CAtom(atom).toLowerAscii().trace()
  atom.toStaticAtom()

proc toStaticAtom*(s: string): StaticAtom =
  let factory = getFactory()
  factory.get(s, s.hash()).toStaticAtom()

proc toNamespace*(atom: CAtom): Namespace =
  case atom.toStaticAtom()
  of satUempty: return nsNone
  of satNamespaceHTML: return nsHTML
  of satNamespaceMathML: return nsMathML
  of satNamespaceSVG: return nsSVG
  of satNamespaceXLink: return nsXLink
  of satNamespaceXML: return nsXml
  of satNamespaceXMLNS: return nsXmlns
  else: return nsUnknown

proc toStaticAtom*(namespace: Namespace): StaticAtom =
  return case namespace
  of nsNone, nsUnknown: satUempty
  of nsHTML: satNamespaceHTML
  of nsMathML: satNamespaceMathML
  of nsSVG: satNamespaceSVG
  of nsXLink: satNamespaceXLink
  of nsXml: satNamespaceXML
  of nsXmlns: satNamespaceXMLNS

proc `==`*(a, b: CAtomTraced): bool {.borrow.}

proc `==`*(a: CAtom; b: StaticAtom): bool =
  a.toStaticAtom() == b

proc `==`*(a: StaticAtom; b: CAtom): bool =
  a == b.toStaticAtom()

proc `==`*(a: CAtomTraced; b: CAtom): bool =
  CAtom(a) == b

proc `==`*(a: CAtom; b: CAtomTraced): bool =
  a == CAtom(b)

proc `==`*(a: CAtomTraced; b: StaticAtom): bool =
  CAtom(a) == b

proc `==`*(a: StaticAtom; b: CAtomTraced): bool =
  a == CAtom(b)

proc contains*(a: openArray[CAtom]; b: StaticAtom): bool =
  b.toAtom() in a

proc contains*(a: openArray[CAtom]; b: CAtomTraced): bool =
  b.view() in a

proc contains*(a: openArray[StaticAtom]; b: CAtom): bool =
  b.toStaticAtom() in a

proc fromJSImpl(ctx: JSContext; val: JSValueConst; res: var CAtom):
    FromJSResult =
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

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var CAtomTraced):
    FromJSResult =
  var atom: CAtom
  let status = ctx.fromJSImpl(val, atom)
  res = atom.trace()
  status

proc fromJS*(ctx: JSContext; atom: JSAtom; res: var CAtomTraced): FromJSResult =
  if atom == JS_ATOM_NULL:
    res = CAtomNull.trace()
  else:
    let val = JS_AtomToString(ctx, atom)
    if JS_IsException(val):
      return fjErr
    ?ctx.fromJSFree(val, res)
  fjOk

proc fromJSView*(ctx: JSContext; atom: JSAtom; res: var CAtom): FromJSResult =
  if atom == JS_ATOM_NULL:
    res = CAtomNull
  else:
    var len: csize_t
    let cs = JS_AtomToCStringLen(ctx, len, atom)
    if cs == nil:
      return fjErr
    if len > csize_t(int.high):
      JS_FreeCString(ctx, cs)
      JS_ThrowRangeError(ctx, "string length out of bounds")
      return fjErr
    {.push overflowChecks: off.}
    let H = cast[int](len) - 1
    {.pop.}
    res = cs.toOpenArray(0, H).toAtomView()
    JS_FreeCString(ctx, cs)
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var seq[CAtom]):
    FromJSResult =
  var it: JSValue
  var nextMethod: JSValue
  ?ctx.fromJSSeqInit(val, it, nextMethod)
  var status = fjOk
  var tmp = newSeq[CAtom]()
  while status.isOk:
    var val: JSValue
    case ctx.fromJSSeqIt(it, nextMethod, val)
    of sirException:
      status = fjErr
      break
    of sirDone:
      res = move(tmp)
      break
    of sirContinue:
      var atom = CAtomNull
      status = ctx.fromJSImpl(val, atom)
      tmp.add(atom)
      JS_FreeValue(ctx, val)
  freeAtoms(tmp)
  JS_FreeValue(ctx, it)
  JS_FreeValue(ctx, nextMethod)
  status

proc fromJS*(ctx: JSContext; vals: openArray[JSValueConst];
    res: var seq[CAtom]): FromJSResult =
  var tmp: seq[CAtom] = @[]
  for val in vals:
    var atom: CAtomTraced
    if ctx.fromJS(val, atom).isErr:
      freeAtoms(tmp)
      return fjErr
    tmp.add(atom.dup())
  res = move(tmp)
  fjOk

proc fromJS*(ctx: JSContext; val: JSAtom; res: var StaticAtom): FromJSResult =
  var ca: CAtomTraced
  ?ctx.fromJS(val, ca)
  res = ca.toStaticAtom()
  fjOk

type FromIdxResult* = enum
  fiIdx, fiStr, fiErr

proc fromIdx*(ctx: JSContext; atom: JSAtom; idx: var uint32): FromIdxResult =
  let val = JS_AtomIsNumericIndex1(ctx, atom)
  if JS_IsException(val):
    return fiErr
  var i: int64
  if not JS_IsUndefined(val) and ctx.fromJSFree(val, i).isOk and
      i in 0..int64(uint32.high - 1):
    idx = uint32(i)
    return fiIdx
  fiStr

proc fromIdx*(ctx: JSContext; atom: JSAtom; idx: var uint32;
    ds: var DOMString): FromIdxResult =
  let res = ctx.fromIdx(atom, idx)
  if res != fiStr:
    return res
  if ctx.fromJS(atom, ds).isOk:
    return fiStr
  fiErr

proc fromIdx*(ctx: JSContext; atom: JSAtom; idx: var uint32;
    s: var CAtomTraced): FromIdxResult =
  let res = ctx.fromIdx(atom, idx)
  if res != fiStr:
    return res
  if ctx.fromJS(atom, s).isOk:
    return fiStr
  fiErr

proc toJS*(ctx: JSContext; atom: CAtom): JSValue =
  if atom == CAtomNull:
    return JS_NULL
  return ctx.toJS($atom)

proc toJS*(ctx: JSContext; atom: CAtomTraced): JSValue =
  ctx.toJS(CAtom(atom))

when defined(test):
  proc testSetHash*(atom: CAtom; h: Hash) =
    getFactory().atomMap[uint32(atom)].hcache = h

  proc testGetIdx*(atom: CAtom): int =
    let mask = getFactory().tab.high
    var i = atom.hash() and mask
    while true:
      if factory.tab[i] == uint32(atom):
        break
      i = (i + 1) and mask
    i

{.pop.} # raises: []
