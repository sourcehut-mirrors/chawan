# String interning with reference counts.
#
# On the different types:
#
# * StaticAtom is a pre-defined atom without a reference count.
# * CAtom is an atom with automatic reference counting.
# * CAtomRaw is an atom with manual refcounting.  It is used as a view to a
#   CAtom in some places as an optimization.

{.push raises: [].}

import std/algorithm
import std/macros

import js/constcharp
import js/fromjs
import js/jstypes
import js/jsutils
import js/quickjs
import js/tojs
import utils/assert
import utils/chahash
import utils/cowstr
import utils/opt
import utils/tabutil
import utils/twtstr

type
  TagType* = enum
    ttUnknown = ""
    ttApplet = "applet"
    ttBig = "big"
    ttHtml = "html"
    ttBase = "base"
    ttBasefont = "basefont"
    ttBgsound = "bgsound"
    ttHead = "head"
    ttLink = "link"
    ttListing = "listing"
    ttMeta = "meta"
    ttStyle = "style"
    ttTitle = "title"
    ttBody = "body"
    ttAddress = "address"
    ttArticle = "article"
    ttAside = "aside"
    ttFooter = "footer"
    ttHeader = "header"
    ttH1 = "h1"
    ttH2 = "h2"
    ttH3 = "h3"
    ttH4 = "h4"
    ttH5 = "h5"
    ttH6 = "h6"
    ttHgroup = "hgroup"
    ttMain = "main"
    ttNav = "nav"
    ttSearch = "search"
    ttSection = "section"
    ttBlockquote = "blockquote"
    ttDd = "dd"
    ttDiv = "div"
    ttDl = "dl"
    ttDt = "dt"
    ttFigcaption = "figcaption"
    ttFigure = "figure"
    ttHr = "hr"
    ttLi = "li"
    ttOl = "ol"
    ttP = "p"
    ttPre = "pre"
    ttUl = "ul"
    ttA = "a"
    ttAbbr = "abbr"
    ttB = "b"
    ttBdi = "bdi"
    ttBdo = "bdo"
    ttBr = "br"
    ttNobr = "nobr"
    ttCite = "cite"
    ttCode = "code"
    ttData = "data"
    ttDfn = "dfn"
    ttEm = "em"
    ttEmbed = "embed"
    ttI = "i"
    ttKbd = "kbd"
    ttMark = "mark"
    ttMarquee = "marquee"
    ttQ = "q"
    ttRb = "rb"
    ttRp = "rp"
    ttRt = "rt"
    ttRtc = "rtc"
    ttRuby = "ruby"
    ttS = "s"
    ttSamp = "samp"
    ttSmall = "small"
    ttSpan = "span"
    ttStrong = "strong"
    ttSub = "sub"
    ttSup = "sup"
    ttTime = "time"
    ttU = "u"
    ttVar = "var"
    ttWbr = "wbr"
    ttArea = "area"
    ttAudio = "audio"
    ttImg = "img"
    ttImage = "image"
    ttMap = "map"
    ttTrack = "track"
    ttVideo = "video"
    ttIframe = "iframe"
    ttObject = "object"
    ttParam = "param"
    ttPicture = "picture"
    ttPortal = "portal"
    ttSource = "source"
    ttCanvas = "canvas"
    ttNoscript = "noscript"
    ttNoembed = "noembed"
    ttPlaintext = "plaintext"
    ttXmp = "xmp"
    ttScript = "script"
    ttSlot = "slot"
    ttDel = "del"
    ttIns = "ins"
    ttCaption = "caption"
    ttCol = "col"
    ttColgroup = "colgroup"
    ttTable = "table"
    ttTbody = "tbody"
    ttTd = "td"
    ttTfoot = "tfoot"
    ttTh = "th"
    ttThead = "thead"
    ttTr = "tr"
    ttButton = "button"
    ttDatalist = "datalist"
    ttFieldset = "fieldset"
    ttForm = "form"
    ttInput = "input"
    ttKeygen = "keygen"
    ttLabel = "label"
    ttLegend = "legend"
    ttMeter = "meter"
    ttOptgroup = "optgroup"
    ttOption = "option"
    ttOutput = "output"
    ttProgress = "progress"
    ttSelect = "select"
    ttSelectedcontent = "selectedcontent"
    ttTextarea = "textarea"
    ttDetails = "details"
    ttDialog = "dialog"
    ttMenu = "menu"
    ttSummary = "summary"
    ttBlink = "blink"
    ttCenter = "center"
    ttDir = "dir"
    ttFont = "font"
    ttFrame = "frame"
    ttNoframes = "noframes"
    ttFrameset = "frameset"
    ttStrike = "strike"
    ttTt = "tt"
    ttTemplate = "template"
    ttMath = "math"
    ttSvg = "svg"
    ttAnnotationXml = "annotation-xml"
    ttForeignObject = "foreignObject"
    ttDesc = "desc"
    ttEncoding = "encoding"
    ttMi = "mi"
    ttMo = "mo"
    ttMn = "mn"
    ttMs = "ms"
    ttMtext = "mtext"
    ttMglyph = "mglyph"
    ttMalignmark = "malignmark"

  QuirksMode* = enum
    qmNoQuirks, qmQuirks, qmLimitedQuirks

  Namespace* = enum
    nsNone = ""
    nsHTML = "http://www.w3.org/1999/xhtml",
    nsMathML = "http://www.w3.org/1998/Math/MathML",
    nsSVG = "http://www.w3.org/2000/svg",
    nsXLink = "http://www.w3.org/1999/xlink",
    nsXml = "http://www.w3.org/XML/1998/namespace",
    nsXmlns = "http://www.w3.org/2000/xmlns/"

const FormAssociatedElements* = {
  ttButton, ttFieldset, ttInput, ttObject, ttOutput, ttSelect,
  ttTextarea, ttImg
}

const ListedElements* = {
  ttFieldset, ttInput, ttObject, ttOutput, ttSelect, ttTextarea
}

# create a static enum compatible with TagType

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
      satCellspacing = "cellspacing"
      satChange = "change"
      satCharset = "charset"
      satChecked = "checked"
      satClass = "class"
      satClear = "clear"
      satClick = "click"
      satClosed = "closed"
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
      satFace = "face"
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
      satHeight = "height"
      satHidden = "hidden"
      satHref = "href"
      satHreflang = "hreflang"
      satHtmlevents = "htmlevents"
      satHttpEquiv = "http-equiv"
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
      satShadow = "shadow"
      satShape = "shape"
      satSize = "size"
      satSizes = "sizes"
      satSrc = "src"
      satSrcset = "srcset"
      satStart = "start"
      satStylesheet = "stylesheet"
      satSubmit = "submit"
      satSvgevents = "svgevents"
      satTarget = "target"
      satText = "text"
      satTextHtml = "text/html"
      satTimeout = "timeout"
      satToggle = "toggle"
      satTouchmove = "touchmove"
      satTouchstart = "touchstart"
      satType = "type"
      satUempty = ""
      satUievent = "uievent"
      satUievents = "uievents"
      satUsemap = "usemap"
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
    let name = if tn == "annotation-xml":
      "satAnnotationXml"
    else:
      "sat" & tn[0].toUpperAscii() & tn.substr(1)
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
    s: Str
    freeNext: uint32 # if free'd, points to next item in free list
    refc: uint32
    hcache: Hash

  CAtomFactoryObj = object
    tab: seq[uint32] # hash table; length is a power of 2
    atomMap: seq[AtomDesc]
    freeHead: uint32

  CAtomFactory = ptr CAtomFactoryObj

# This maps to JS null.
const CAtomNullRaw = CAtomRaw(0)

proc `==`*(a, b: CAtomRaw): bool {.borrow.}
proc cmp*(a, b: CAtomRaw): int {.borrow.}

var factory {.global.}: CAtomFactoryObj

template getFactory(): CAtomFactory =
  addr factory

proc hash*(atom: CAtomRaw): Hash =
  getFactory().atomMap[uint32(atom)].hcache

proc freeAtomImpl(u: uint32) =
  let factory = getFactory()
  factory.atomMap[u].s = str("")
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
    chaDebugAssert desc.refc > 0
    dec desc.refc
    if desc.refc == 0:
      freeAtomImpl(u)

proc dup(atom: CAtomRaw): CAtomRaw =
  let factory = getFactory()
  inc factory.atomMap[uint32(atom)].refc
  atom

type
  CAtom* = distinct CAtomRaw

  CAtomNullable* = distinct CAtom # translates JS_NULL to CAtomNull

const CAtomNull* = CAtom(CAtomNullRaw)

proc `==`*(a, b: CAtom): bool {.borrow.}
proc cmp*(a, b: CAtom): int {.borrow.}
proc hash*(atom: CAtom): Hash {.borrow.}

proc `=destroy`*(atom: var CAtom) =
  freeAtom(cast[CAtomRaw](atom))

proc `=copy`*(x: var CAtom; y: CAtom) =
  if x != y:
    `=destroy`(x)
    cast[ptr CAtomRaw](addr x)[] = dup(cast[CAtomRaw](y))

proc `=sink`*(x: var CAtom; y: CAtom) =
  `=destroy`(x)
  cast[ptr CAtomRaw](addr x)[] = cast[CAtomRaw](y)

proc `=dup`*(atom: CAtom): CAtom =
  CAtom(dup(cast[CAtomRaw](atom)))

proc view*(atom: CAtomRaw): lent CAtom =
  CAtom(atom)

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
    factory.atomMap[int(atom)].s = initStr(s)
  atom

proc toAtomRaw(factory: CAtomFactory; s: Str): CAtomRaw =
  var added = false
  let atom = factory.toAtomImpl(s.toOpenArray(), added)
  if added:
    factory.atomMap[int(atom)].s = s
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
    let atom = factory.toAtomRaw(sa.toStr())
    chaAssert uint32(atom) == uint32(sa)

proc deinitCAtomFactory*() =
  # make it so that we don't leak QJS strings on exit
  for desc in factory.atomMap.mitems:
    desc.s = str("")

proc toAtomRaw(s: openArray[char]): CAtomRaw =
  return getFactory().toAtomRaw(s)

proc toAtom*(s: openArray[char]): CAtom =
  CAtom(s.toAtomRaw())

proc toAtom*(s: Str): CAtom =
  CAtom(getFactory().toAtomRaw(s))

proc toAtom*(s: StrNil): CAtom =
  if s != nil:
    s.asStr.toAtom()
  else:
    CAtomNull

proc toAtom*(s: DOMString): CAtom =
  s.asStr.toAtom()

proc toAtom*(s: Growbuf): CAtom =
  s.toOpenArray().toAtom()

proc toStaticAtom*(tagType: TagType): StaticAtom =
  chaAssert tagType != ttUnknown
  StaticAtom(uint32(tagType))

template view*(tagType: TagType): CAtom =
  let tmp = tagType
  chaAssert tmp != ttUnknown
  CAtom(tmp)

template view*(ns: Namespace): CAtom =
  case ns
  of nsNone: CAtomNull
  of nsHTML: satNamespaceHTML.view()
  of nsMathML: satNamespaceMathML.view()
  of nsSVG: satNamespaceSVG.view()
  of nsXLink: satNamespaceXLink.view()
  of nsXml: satNamespaceXML.view()
  of nsXmlns: satNamespaceXMLNS.view()

proc toAtomLower*(s: Str): CAtom =
  s.toLowerAscii().toAtom()

template view*(satom: StaticAtom): CAtom =
  let tmp = satom
  chaAssert tmp != satUnknown
  CAtom(CAtomRaw(uint32(tmp)))

proc toStr*(atom: CAtom): lent Str =
  getFactory().atomMap[int(atom)].s

proc add*(buf: var Growbuf; atom: CAtom) =
  buf &= atom.toStr()

proc find*(atom: CAtom; c: char): int =
  atom.toStr().find(c)

proc len*(atom: CAtom): int =
  atom.toStr().len

proc substr*(atom: CAtom; first, last: int): CAtom =
  let atomLen = atom.len
  if first >= atomLen:
    return satUempty.view()
  let last = min(last, atomLen - 1)
  atom.toStr().toOpenArray(first, last).toAtom()

proc substr*(atom: CAtom; first: int): CAtom =
  atom.substr(first, atom.toStr().high)

proc contains*(atom: CAtom; c: char): bool =
  c in atom.toStr()

proc contains*(atom: CAtom; cs: set[char]): bool =
  cs in atom.toStr()

proc toLowerAscii*(a: CAtom): CAtom =
  if AsciiUpperAlpha in a:
    a.toStr().toLowerAscii2().toAtom()
  else: # skip hash lookup in the common case
    a

proc equalsIgnoreCase*(a, b: CAtom): bool =
  a == b or a.toStr().equalsIgnoreCase(b.toStr())

proc containsIgnoreCase*(aa: openArray[CAtom]; a: CAtom): bool =
  for it in aa:
    if a.equalsIgnoreCase(it):
      return true
  return false

proc toAtomLower*(s: DOMString): CAtom =
  s.asStr.toAtomLower()

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

proc toStaticAtom*(s: Str): StaticAtom =
  let factory = getFactory()
  factory.get(s.toOpenArray(), s.toOpenArray().hash()).toStaticAtom()

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
  qualifiedName.toStr().toOpenArray(i, qualifiedName.toStr().high) ==
    localName.toStr()

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var CAtom): JSCode =
  var ds: DOMString
  ?ctx.fromJS(val, ds)
  res = ds.toAtom()
  fjOk

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var CAtomNullable):
    JSCode =
  if JS_IsNull(val):
    res = CAtomNullable(CAtomNull)
  else:
    var atom: CAtom
    ?ctx.fromJS(val, atom)
    res = CAtomNullable(atom)
  fjOk

proc fromJS(ctx: JSContext; atom: JSAtom; res: var CAtom): JSCode =
  if atom == JS_ATOM_NULL:
    res = CAtomNull
  else:
    let val = JS_AtomToString(ctx, atom)
    if JS_IsException(val.vc):
      return fjErr
    ?ctx.fromJSFree(val, res)
  fjOk

proc fromJSView*(ctx: JSContext; atom: JSAtom; res: var CAtomRaw): JSCode =
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
    res: var seq[CAtom]): JSCode =
  var tmp = newSeq[CAtom](vals.len)
  for i in 0 ..< vals.len:
    ?ctx.fromJS(vals[i], tmp[i])
  res = move(tmp)
  fjOk

type
  FromIdxResult* = enum
    fiIdx, fiStr, fiErr

  FromIdxResult2* = range[fiIdx..fiStr]

proc fromIdx*(ctx: JSContext; atom: JSAtom; idx: var uint32): FromIdxResult2 =
  if JS_AtomIsArrayIndex(ctx, idx, atom) != 0:
    return FromIdxResult2(fiIdx)
  FromIdxResult2(fiStr)

proc fromIdx*(ctx: JSContext; atom: JSAtom; idx: var uint32; s: var Str):
    FromIdxResult =
  if JS_AtomIsArrayIndex(ctx, idx, atom) != 0:
    return fiIdx
  if ctx.fromJS(atom, s).isOk:
    return fiStr
  fiErr

proc fromIdx*(ctx: JSContext; atom: JSAtom; idx: var uint32; s: var CAtom):
    FromIdxResult =
  let res = ctx.fromIdx(atom, idx)
  if res != fiStr:
    return res
  if ctx.fromJS(atom, s).isOk:
    return fiStr
  fiErr

proc toJS*(ctx: JSContext; atom: CAtom): JSValue =
  if atom == CAtomNull:
    return JS_NULL
  return ctx.toJS(atom.toStr())

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

proc `=destroy`*(this: var DOMTokenArray) =
  if this != nil:
    dealloc(cast[pointer](this))

proc `=sink`*(x: var DOMTokenArray; y: DOMTokenArray) =
  `=destroy`(x)
  cast[ptr ptr DOMTokenArrayBuffer](addr x)[] =
    cast[ptr DOMTokenArrayBuffer](y)

proc `=copy`*(x: var DOMTokenArray; y: DOMTokenArray) =
  if x != y:
    `=destroy`(x)
    cast[ptr ptr DOMTokenArrayBuffer](addr x)[] = dup(y)

proc `=dup`*(this: DOMTokenArray): DOMTokenArray =
  DOMTokenArray(dup(this))

proc len*(this: DOMTokenArrayView): uint32 =
  if this == nil:
    return 0
  (ptr DOMTokenArrayBuffer)(this).len

proc len*(this: DOMTokenArray): uint32 {.borrow.}

proc `[]`*(this: DOMTokenArrayView; u: uint32): lent CAtom =
  chaAssert this != nil and u < this.len
  (ptr DOMTokenArrayBuffer)(this).toks[u]

proc `[]`*(this: DOMTokenArray; u: uint32): lent CAtom =
  DOMTokenArrayView(this)[u]

proc `[]=`*(this: DOMTokenArray; u: uint32; atom: sink CAtom) =
  chaAssert this != nil and u < this.len
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
  chaAssert len < uint32(int32.high)
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

proc newDOMTokenArray*(toks: varargs[CAtom]): DOMTokenArray =
  chaAssert int64(toks.len) < int64(uint32.high)
  if toks.len == 0:
    return DOMTokenArray(nil)
  let this = DOMTokenArray(createDOMTokenArray(uint32(toks.len)))
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

type
  AttrData* = object
    name*: CAtom ## This is the qualified name.
    namespace*: CAtom
    value*: Str

  AttrDataListObj = object
    len: uint32
    cap: uint32
    data: UncheckedArray[AttrData]

  AttrDataList* = object
    p: ptr AttrDataListObj

proc dup(this: AttrDataList): ptr AttrDataListObj

proc `=destroy`*(this: var AttrDataList) =
  if this.p != nil:
    for u in 0 ..< this.p.len:
      `=destroy`(this.p.data[u])
    dealloc(this.p)

proc `=sink`*(x: var AttrDataList; y: AttrDataList) =
  `=destroy`(x)
  x.p = y.p

proc `=copy`*(x: var AttrDataList; y: AttrDataList) =
  if x.p != y.p:
    `=destroy`(x)
    x.p = dup(y)

proc `=dup`*(this: AttrDataList): AttrDataList =
  AttrDataList(p: dup(this))

proc len*(this: AttrDataList): uint32 =
  if this.p == nil:
    return 0
  this.p.len

proc `[]`*(this: AttrDataList; u: uint32): lent AttrData {.inline.} =
  chaAssert u < this.len
  this.p.data[u]

iterator items*(this: AttrDataList): lent AttrData =
  let len = this.len
  for u in 0 ..< len:
    yield this[u]

iterator pairs*(this: AttrDataList): tuple[key: uint32; val: lent AttrData] =
  let len = this.len
  for u in 0 ..< len:
    yield (u, this[u])

proc `[]`*(this: var AttrDataList; u: uint32): var AttrData =
  chaAssert u < this.len
  this.p.data[u]

proc `[]=`*(this: var AttrDataList; u: uint32; data: sink AttrData) =
  chaAssert u < this.len
  this.p.data[u] = move(data)

proc high*(this: AttrDataList): int =
  int(this.len) - 1

template toOpenArray(attrs: AttrDataList): var openArray[AttrData] =
  let p = attrs.p
  var data = if p != nil: addr p.data else: (ptr UncheckedArray[AttrData])(nil)
  data.toOpenArray(0, attrs.high)

proc resizeAttrDataList(old: ptr AttrDataListObj; cap: uint32):
    ptr AttrDataListObj =
  # I guess alignment is fine here...
  let ocap = if old != nil: old.cap else: 0
  let osize = sizeof(AttrDataListObj) + cast[int](ocap) * sizeof(AttrData)
  let size = sizeof(AttrDataListObj) + cast[int](cap) * sizeof(AttrData)
  let this = cast[ptr AttrDataListObj](realloc0(old, osize, size))
  this.cap = cap
  this

proc dup(this: AttrDataList): ptr AttrDataListObj =
  if this.p == nil:
    return nil
  let len = this.len
  let p2 = resizeAttrDataList(nil, len)
  p2.len = len
  for u in 0 ..< this.len:
    p2.data[u] = this[u]
  p2

proc cmpAttrName(a: AttrData; b: CAtom): int =
  return cmp(a.name, b)

proc lowerBound*(this: AttrDataList; name: CAtom): uint32 =
  uint32(this.toOpenArray().lowerBound(name, cmpAttrName))

proc upperBound*(this: AttrDataList; name: CAtom): uint32 =
  uint32(this.toOpenArray().upperBound(name, cmpAttrName))

proc newAttrDataList*(data: sink AttrData): AttrDataList =
  var p = resizeAttrDataList(nil, 1)
  p.len = 1
  p.data[0] = data
  AttrDataList(p: p)

proc setLen*(attrs: var AttrDataList; len: uint32) =
  let olen = attrs.len
  var p = attrs.p
  var cap = if p != nil: p.cap else: 0
  if cap < len:
    chaAssert cap < 0x7FFFFFFF
    cap *= 2
    if cap < len:
      cap = len
    p = resizeAttrDataList(p, cap)
    attrs.p = p
  if p != nil:
    for u in len ..< olen:
      p.data[u] = AttrData.default
    p.len = len

proc delete*(attrs: var AttrDataList; u: uint32) =
  let olen = attrs.len
  chaAssert u < olen
  let p = attrs.p
  {.cast(raises: []).}:
    `=destroy`(p.data[u])
  moveMem(addr p.data[u], addr p.data[u + 1],
    (olen - 1 - u) * uint32(sizeof(AttrData)))
  p.len = olen - 1

proc insert*(attrs: var AttrDataList; data: sink AttrData; u: uint32) =
  let olen = attrs.len
  chaAssert u <= olen
  attrs.setLen(olen + 1)
  if u < olen:
    moveMem(addr attrs[u + 1], addr attrs[u],
      (olen - u) * uint32(sizeof(AttrData)))
  copyMem(addr attrs[u], addr data, sizeof(AttrData))
  wasMoved(data)

proc add*(attrs: var AttrDataList; data: sink AttrData) =
  let olen = attrs.len
  attrs.setLen(olen + 1)
  attrs[olen] = data

proc `==`*(a, b: AttrDataList): bool =
  let alen = a.len
  if alen != b.len:
    return false
  for u in 0 ..< alen:
    if a[u] != b[u]:
      return false
  true

proc sortAttrs*(attrs: var AttrDataList) =
  if attrs.len > 1:
    attrs.toOpenArray().sort(proc(a, b: AttrData): int {.nimcall.} =
      cmp(a.name, b.name)
    )
    var j = 1'u32
    var prev = attrs[0].name
    for i in 1 ..< attrs.len:
      let name = attrs[i].name
      if name != prev:
        if j < i:
          attrs[j] = move(attrs[i])
        inc j
      prev = name
    attrs.setLen(j)

{.pop.} # raises: []
