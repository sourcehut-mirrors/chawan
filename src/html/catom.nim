# String interning with reference counts.
#
# On the different types:
#
# * StaticAtom is a pre-defined atom without a reference count.
# * CAtom is an atom with automatic reference counting.
# * CAtomRaw is an atom with manual refcounting.  It is used as a view to a
#   CAtom in some places as an optimization.

{.push raises: [].}

import std/hashes
import std/macros

import chame/tags
import js/fromjs
import js/jstypes
import js/quickjs
import js/tojs
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
      satAttributes = "attributes"
      satAutofocus = "autofocus"
      satAxis = "axis"
      satBgcolor = "bgcolor"
      satBlocking = "blocking"
      satBlur = "blur"
      satBorder = "border"
      satCells = "cells"
      satCellspacing = "cellspacing"
      satChange = "change"
      satChecked = "checked"
      satChildNodes = "childNodes"
      satChildren = "children"
      satClass = "class"
      satClear = "clear"
      satClick = "click"
      satCodetype = "codetype"
      satColorDashProfile = "color-profile"
      satCols = "cols"
      satColspan = "colspan"
      satCompact = "compact"
      satContextmenu = "contextmenu"
      satCrossorigin = "crossorigin"
      satCustomevent = "customevent"
      satDOMContentLoaded = "DOMContentLoaded"
      satDashChaHintCounter = "-cha-hint-counter"
      satDashChaLinkCounter = "-cha-link-counter"
      satDataset = "dataset"
      satDatetime = "datetime"
      satDblclick = "dblclick"
      satDeclare = "declare"
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
      satFormaction = "formaction"
      satFormenctype = "formenctype"
      satFormmethod = "formmethod"
      satHash = "hash"
      satHeight = "height"
      satHidden = "hidden"
      satHost = "host"
      satHostname = "hostname"
      satHref = "href"
      satHreflang = "hreflang"
      satHtmlevents = "htmlevents"
      satId = "id"
      satImageSvgXml = "image/svg+xml"
      satImages = "images"
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
      satProtocol = "protocol"
      satReadonly = "readonly"
      satReadystatechange = "readystatechange"
      satReferrerpolicy = "referrerpolicy"
      satRel = "rel"
      satRequired = "required"
      satRev = "rev"
      satReversed = "reversed"
      satRows = "rows"
      satRowspan = "rowspan"
      satRules = "rules"
      satScope = "scope"
      satScrolling = "scrolling"
      satSelected = "selected"
      satSelectedOptions = "selectedOptions"
      satShadow = "shadow"
      satShape = "shape"
      satSizes = "sizes"
      satSrc = "src"
      satSrcset = "srcset"
      satStart = "start"
      satStylesheet = "stylesheet"
      satSubmit = "submit"
      satSvgevents = "svgevents"
      satTBodies = "tBodies"
      satTarget = "target"
      satText = "text"
      satTextHtml = "text/html"
      satTimeout = "timeout"
      satToString = "toString"
      satTouchmove = "touchmove"
      satTouchstart = "touchstart"
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
      satXml = "xml"
      satXmlns = "xmlns"
  let decl = quote do:
    type StaticAtom* {.inject.} = enum
      satUnknown = ""
  let decl0 = decl[0][2]
  for t in TagType:
    if t == ttUnknown:
      continue
    let tn = $t
    let name = "sat" & tn[0].toUpperAscii() & tn.substr(1).kebabToCamelCase()
    decl0.add(newNimNode(nnkEnumFieldDef).add(ident(name), newStrLitNode(tn)))
  for i, f in StaticAtom0.getType():
    if i == 0:
      continue
    let tn = $StaticAtom0(i - 1)
    decl0.add(newNimNode(nnkEnumFieldDef).add(ident(f.strVal),
      newStrLitNode(tn)))
  decl

makeStaticAtom

const CAtomFactoryInitSize* = 2048 # must be a power of 2

type
  CAtomRaw* = distinct uint32

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

# This maps to JS null.
const CAtomNullRaw* = CAtomRaw(0)

proc `==`*(a, b: CAtomRaw): bool {.borrow.}
proc cmp*(a, b: CAtomRaw): int {.borrow.}

var factory {.global.}: CAtomFactoryObj

template getFactory(): CAtomFactory =
  addr factory

proc hash*(atom: CAtomRaw): Hash =
  getFactory().atomMap[uint32(atom)].hcache

proc freeAtomImpl(u: uint32) =
  let factory = getFactory()
  factory.atomMap[u].s = ""
  factory.atomMap[u].freeNext = factory.freeHead
  factory.freeHead = u
  let mask = factory.tab.len - 1
  var j = -1
  let keyh = factory.atomMap[u].hcache
  for i, it in factory.tab.mtabPairs(keyh):
    if it == u:
      it = 0
      j = i
    elif j >= 0:
      let k = factory.atomMap[it].hcache and mask
      if i == k: # already at home
        break
      # backwards shift
      factory.tab[j] = move(it)
      j = i

proc freeAtom(atom: CAtomRaw) =
  let u = uint32(atom)
  if u > uint32(StaticAtom.high):
    let factory = getFactory()
    let desc = addr factory.atomMap[uint32(atom)]
    when defined(debug):
      assert desc.refc > 0
    dec desc.refc
    if desc.refc == 0:
      freeAtomImpl(u)

proc dup*(atom: CAtomRaw): CAtomRaw =
  let factory = getFactory()
  inc factory.atomMap[uint32(atom)].refc
  atom

type
  CAtom* = distinct CAtomRaw

const CAtomNull* = CAtom(CAtomNullRaw)

proc `==`*(a, b: CAtom): bool {.borrow.}
proc cmp*(a, b: CAtom): int {.borrow.}
proc hash*(atom: CAtom): Hash {.borrow.}

proc `=destroy`(atom: var CAtom) =
  freeAtom(cast[CAtomRaw](atom))

proc `=dup`(atom: CAtom): CAtom {.noinit.} =
  cast[ptr CAtomRaw](addr result)[] = dup(cast[CAtomRaw](atom))

proc `=copy`(x: var CAtom; y: CAtom) =
  if x != y:
    `=destroy`(x)
    cast[ptr CAtomRaw](addr x)[] = dup(cast[CAtomRaw](y))

proc `=sink`(x: var CAtom; y: CAtom) =
  `=destroy`(x)
  cast[ptr CAtomRaw](addr x)[] = cast[CAtomRaw](y)

template trace(atom: CAtomRaw): CAtom =
  CAtom(atom)

proc view*(atom: CAtomRaw): lent CAtom =
  CAtom(atom)

template view*(atom: CAtom): CAtomRaw =
  CAtomRaw(atom)

proc put0(factory: CAtomFactory; atom: uint32) =
  let mask = factory.tab.len - 1
  let hcache = CAtomRaw(atom).hash()
  var home = hcache and mask
  var atom = atom
  for i, it in factory.tab.mtabPairs(hcache):
    if it == 0:
      it = atom
      break
    if tabSwap(home, CAtomRaw(it).hash(), i, mask): # displace
      swap(it, atom)

proc get(factory: CAtomFactory; s: openArray[char]; h: Hash): CAtomRaw =
  for i, atom in factory.tab.tabPairs(h):
    if atom == 0:
      break
    if factory.atomMap[int(atom)].s == s:
      return CAtomRaw(atom)
  return CAtomNullRaw

proc toAtomImpl(factory: CAtomFactory; s: openArray[char];
    added: var bool): CAtomRaw =
  let h = s.hash()
  if (let atom = factory.get(s, h); atom != CAtomNullRaw):
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
  CAtomRaw(u)

proc toAtomRaw(factory: CAtomFactory; s: openArray[char]): CAtomRaw =
  var added = false
  let atom = factory.toAtomImpl(s, added)
  if added:
    factory.atomMap[int(atom)].s = s.substr()
  atom

proc toAtomView*(s: openArray[char]): CAtomRaw =
  let h = s.hash()
  getFactory().get(s, h)

proc initCAtomFactory*() =
  let factory = getFactory()
  factory.tab = newSeq[uint32](CAtomFactoryInitSize)
  # Null atom
  factory.atomMap.add(AtomDesc())
  # StaticAtom includes TagType too.
  for sa in StaticAtom(1) .. StaticAtom.high:
    let atom = factory.toAtomRaw($sa)
    assert uint32(atom) == uint32(sa)

proc toAtomRaw(s: openArray[char]): CAtomRaw =
  return getFactory().toAtomRaw(s)

proc toAtom*(s: openArray[char]): CAtom =
  s.toAtomRaw().trace()

proc toAtom*(s: DOMString): CAtom =
  s.toOpenArray().toAtom()

proc toStaticAtom*(tagType: TagType): StaticAtom =
  assert tagType != ttUnknown
  StaticAtom(uint32(tagType))

template view*(tagType: TagType): CAtom =
  let tmp = tagType
  assert tmp != ttUnknown
  CAtom(tmp)

proc toAtomRawLower(s: openArray[char]): CAtomRaw =
  let factory = getFactory()
  var added = false
  var s = s.toLowerAscii()
  let atom = factory.toAtomImpl(s, added)
  if added:
    factory.atomMap[int(atom)].s = move(s)
  atom

template view*(satom: StaticAtom): CAtom =
  let tmp = satom
  assert tmp != satUnknown
  CAtom(CAtomRaw(uint32(tmp)))

proc `$`*(atom: CAtomRaw): lent string =
  getFactory().atomMap[int(atom)].s

proc `$`*(atom: CAtom): lent string =
  $CAtomRaw(atom)

proc find*(atom: CAtom; c: char): int =
  ($atom).find(c)

proc len*(atom: CAtom): int =
  ($atom).len

proc substr*(atom: CAtom; first, last: int): CAtom =
  let atomLen = atom.len
  if first >= atomLen:
    return satUempty.view()
  let last = min(last, atomLen - 1)
  ($atom).toOpenArray(first, last).toAtom()

proc substr*(atom: CAtom; first: int): CAtom =
  atom.substr(first, ($atom).high)

proc contains*(atom: CAtom; c: char): bool =
  c in $atom

proc contains*(atom: CAtom; cs: set[char]): bool =
  cs in $atom

proc toLowerAscii*(a: CAtom): CAtom =
  if AsciiUpperAlpha notin $a:
    return a
  return ($a).toAtomRawLower().trace()

proc equalsIgnoreCase*(a, b: CAtom): bool =
  a == b or ($a).equalsIgnoreCase($b)

proc containsIgnoreCase*(aa: openArray[CAtom]; a: CAtom): bool =
  for it in aa:
    if a.equalsIgnoreCase(it):
      return true
  return false

proc toAtomLower*(s: openArray[char]): CAtom =
  s.toAtomRawLower().trace()

proc toAtomLower*(s: DOMString): CAtom =
  s.toOpenArray().toAtomLower()

proc containsIgnoreCase*(aa: openArray[CAtom]; a: StaticAtom): bool =
  return aa.containsIgnoreCase(a.view())

proc toTagType*(atom: CAtom): TagType =
  let i = uint32(atom)
  if i <= uint32(TagType.high):
    return TagType(i)
  return ttUnknown

proc toStaticAtom(atom: CAtomRaw): StaticAtom =
  let i = uint32(atom)
  if i <= uint32(StaticAtom.high):
    return StaticAtom(i)
  return satUnknown

proc toStaticAtom*(atom: CAtom): StaticAtom {.borrow.}

proc toStaticAtomLower*(atom: CAtom): StaticAtom =
  atom.toLowerAscii().toStaticAtom()

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

proc `==`*(a: CAtomRaw; b: StaticAtom): bool =
  a.toStaticAtom() == b

proc `==`*(a: StaticAtom; b: CAtomRaw): bool =
  a == b.toStaticAtom()

proc `==`*(a: CAtom; b: CAtomRaw): bool =
  CAtomRaw(a) == b

proc `==`*(a: CAtomRaw; b: CAtom): bool =
  a == CAtomRaw(b)

proc `==`*(a: CAtom; b: StaticAtom): bool =
  CAtomRaw(a) == b

proc `==`*(a: StaticAtom; b: CAtom): bool =
  a == CAtomRaw(b)

proc contains*(a: openArray[CAtom]; b: StaticAtom): bool =
  b.view() in a

proc contains*(a: openArray[StaticAtom]; b: CAtom): bool =
  b.toStaticAtom() in a

proc matchesLocalName*(qualifiedName, localName: CAtom): bool =
  let i = qualifiedName.find(':') + 1
  if i == 0:
    return qualifiedName == localName
  return ($qualifiedName).toOpenArray(i, ($qualifiedName).high) == $localName

proc fromJSImpl(ctx: JSContext; val: JSValueConst; res: var CAtomRaw):
    FromJSResult =
  if JS_IsNull(val):
    res = CAtomNullRaw
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
    res = cstring(cs).toOpenArray(0, H).toAtomRaw()
    JS_FreeCString(ctx, cs)
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var CAtom):
    FromJSResult =
  var atom: CAtomRaw
  let status = ctx.fromJSImpl(val, atom)
  res = atom.trace()
  status

proc fromJS*(ctx: JSContext; atom: JSAtom; res: var CAtom): FromJSResult =
  if atom == JS_ATOM_NULL:
    res = CAtomNullRaw.trace()
  else:
    let val = JS_AtomToString(ctx, atom)
    if JS_IsException(val):
      return fjErr
    ?ctx.fromJSFree(val, res)
  fjOk

proc fromJSView*(ctx: JSContext; atom: JSAtom; res: var CAtomRaw): FromJSResult =
  if atom == JS_ATOM_NULL:
    res = CAtomNullRaw
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
    res = cstring(cs).toOpenArray(0, H).toAtomView()
    JS_FreeCString(ctx, cs)
  fjOk

proc fromJS*(ctx: JSContext; vals: openArray[JSValueConst];
    res: var seq[CAtom]): FromJSResult =
  var tmp = newSeq[CAtom](vals.len)
  for i in 0 ..< vals.len:
    ?ctx.fromJS(vals[i], tmp[i])
  res = move(tmp)
  fjOk

proc fromJS*(ctx: JSContext; val: JSAtom; res: var StaticAtom): FromJSResult =
  var ca: CAtom
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
    s: var CAtom): FromIdxResult =
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

when defined(test):
  proc testSetHash*(atom: CAtom; h: Hash) =
    getFactory().atomMap[uint32(atom)].hcache = h

  proc testGetIdx*(atom: CAtom): int =
    for i, it in factory.tab.tabPairs(atom.hash()):
      if it == uint32(atom):
        return i
    -1

# Backing buffer for DOMTokenList.
# `nil` is a valid state for this object and simply means "empty".
type
  DOMTokenArrayBuffer = object
    len: uint32
    toks: UncheckedArray[CAtom]

  DOMTokenArrayView* = distinct ptr DOMTokenArrayBuffer

  DOMTokenArray* = distinct DOMTokenArrayView

proc `==`(a, b: DOMTokenArrayView): bool {.borrow.}
proc `==`(a: DOMTokenArrayView; b: typeof(nil)): bool {.borrow.}

proc dup(this: DOMTokenArray): ptr DOMTokenArrayBuffer
proc `==`(a, b: DOMTokenArray): bool {.borrow.}
proc `==`(a: DOMTokenArray; b: typeof(nil)): bool {.borrow.}

proc `=destroy`(this: var DOMTokenArray) =
  if this != nil:
    dealloc(cast[pointer](this))

proc `=dup`(this: DOMTokenArray): DOMTokenArray {.noinit.} =
  cast[ptr ptr DOMTokenArrayBuffer](addr result)[] = dup(this)

proc `=copy`(x: var DOMTokenArray; y: DOMTokenArray) =
  if x != y:
    `=destroy`(x)
    cast[ptr ptr DOMTokenArrayBuffer](addr x)[] = dup(y)

proc `=sink`(x: var DOMTokenArray; y: DOMTokenArray) =
  `=destroy`(x)
  cast[ptr ptr DOMTokenArrayBuffer](addr x)[] =
    cast[ptr DOMTokenArrayBuffer](y)

proc len*(this: DOMTokenArrayView): uint32 =
  if this == nil:
    return 0
  (ptr DOMTokenArrayBuffer)(this).len

proc len*(this: DOMTokenArray): uint32 {.borrow.}

proc `[]`*(this: DOMTokenArrayView; u: uint32): lent CAtom =
  assert this != nil and u < this.len
  (ptr DOMTokenArrayBuffer)(this).toks[u]

proc `[]`*(this: DOMTokenArray; u: uint32): lent CAtom =
  DOMTokenArrayView(this)[u]

proc `[]=`*(this: DOMTokenArray; u: uint32; atom: sink CAtom) =
  assert this != nil and u < this.len
  (ptr DOMTokenArrayBuffer)(this).toks[u] = move(atom)

iterator items*(a: DOMTokenArrayView): lent CAtom {.inline.} =
  if a != nil:
    var u = 0'u32
    while u < a.len:
      yield a[u]
      inc u

iterator pairs*(a: DOMTokenArrayView): tuple[key: uint32; value: lent CAtom]
    {.inline.} =
  if a != nil:
    var u = 0'u32
    while u < a.len:
      yield (u, a[u])
      inc u

iterator items*(a: DOMTokenArray): lent CAtom {.inline.} =
  for it in DOMTokenArrayView(a):
    yield it

iterator pairs*(a: DOMTokenArray): tuple[key: uint32; value: lent CAtom]
    {.inline.} =
  for u, tok in DOMTokenArrayView(a).pairs:
    yield (u, tok)

proc createDOMTokenArray(len: uint32): ptr DOMTokenArrayBuffer =
  assert len < uint32(int32.high)
  let size = sizeof(DOMTokenArrayBuffer) + cast[int](len) * sizeof(CAtom)
  let this = cast[ptr DOMTokenArrayBuffer](alloc0(size))
  this.len = len
  this

proc dup(this: DOMTokenArray): ptr DOMTokenArrayBuffer =
  if this == nil:
    return nil
  let other = createDOMTokenArray(this.len)
  for u, tok in this:
    other.toks[u] = tok
  other

proc newDOMTokenArray*(toks: openArray[CAtom]): DOMTokenArray =
  assert int64(toks.len) < int64(uint32.high)
  if toks.len == 0:
    return DOMTokenArray(nil)
  let this = cast[DOMTokenArray](createDOMTokenArray(uint32(toks.len)))
  for i, tok in toks.mypairs:
    this[uint32(i)] = tok
  this

proc contains*(this: DOMTokenArrayView; a: CAtom): bool =
  for it in this:
    if it == a:
      return true
  false

proc contains*(this: DOMTokenArray; a: CAtom): bool =
  DOMTokenArrayView(this).contains(a)

proc containsIgnoreCase*(this: DOMTokenArray; a: CAtom): bool =
  for it in this:
    if it.equalsIgnoreCase(a):
      return true
  false

proc containsIgnoreCase*(this: DOMTokenArray; a: StaticAtom): bool =
  this.containsIgnoreCase(a.view())

{.pop.} # raises: []
