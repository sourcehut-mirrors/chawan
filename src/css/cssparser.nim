{.push raises: [].}

import std/algorithm
import std/strutils

import html/catom
import html/domexception
import types/opt
import utils/twtstr

type
  CSSParser* = object
    toks: seq[CSSToken]
    i*: int # pointer into iq or toks
    iqp: ptr UncheckedArray[char] # addr iq[0]
    iqlen: int # iq.len
    hasBuf: bool
    tokBuf: CSSToken

# Tokens

  CSSTokenType* = enum
    cttIdent, cttFunction, cttAtKeyword, cttHash, cttString, cttBadString,
    cttUrl, cttBadUrl, cttDelim, cttNumber, cttPercentage, cttDimension,
    cttWhitespace
    cttCdo = "<!--"
    cttCdc = "-->"
    cttColon = ":"
    cttSemicolon = ";"
    cttComma = ","
    cttRbracket = "["
    cttLbracket = "]"
    cttLparen = "("
    cttRparen = ")"
    cttLbrace = "{"
    cttRbrace = "}"
    cttSlash = "/"
    cttStar = "*"
    cttPlus = "+"
    cttMinus = "-"
    cttLt = "<"
    cttGt = ">"
    cttTilde = "~"
    cttDot = "."
    cttPipe = "|"
    cttCaret = "^"
    cttDollar = "$"
    cttEquals = "="
    cttBang = "!"

  CSSTokenFlag = enum
    ctfId, ctfSign, ctfInteger

  CSSTokenUnion {.union.} = object
    i: int32 # cttNumber with ctfInteger
    f: float32 # cttNumber without ctfInteger
    u: uint32 # cttDelim (codepoint)
    ft: CSSFunctionType # cttFunction

  CSSDimensionType* = enum
    cdtUnknown = ""
    # AnB
    cdtN = "n"
    cdtNDash = "n-"
    # CSSUnit
    cuAuto = ""
    cuCap = "cap"
    cuCh = "ch"
    cuCm = "cm"
    cuDvmax = "dvmax"
    cuDvmin = "dvmin"
    cuEm = "em"
    cuEx = "ex"
    cuIc = "ic"
    cuIn = "in"
    cuLh = "lh"
    cuLvmax = "lvmax"
    cuLvmin = "lvmin"
    cuMm = "mm"
    cuPc = "pc"
    cuPt = "pt"
    cuPx = "px"
    cuRcap = "rcap"
    cuRch = "rch"
    cuRem = "rem"
    cuRex = "rex"
    cuRic = "ric"
    cuRlh = "rlh"
    cuSvmax = "svmax"
    cuSvmin = "svmin"
    cuVb = "vb"
    cuVh = "vh"
    cuVi = "vi"
    cuVmax = "vmax"
    cuVmin = "vmin"
    cuVw = "vw"
    # CSSAngle
    catDeg = "deg"
    catGrad = "grad"
    catRad = "rad"
    catTurn = "turn"
  CSSUnit* = range[cuAuto..cuVw]
  CSSAngleType* = range[catDeg..catTurn]

  CSSToken* = object
    t*: CSSTokenType
    flags*: set[CSSTokenFlag]
    dt*: CSSDimensionType
    tu: CSSTokenUnion
    s*: string # for ident/string-like, and unit of number tokens

  CSSRuleType* = enum
    crtAt, crtQualified

  CSSRule* = object
    case t*: CSSRuleType
    of crtAt:
      at*: CSSAtRule
    of crtQualified:
      qualified*: CSSQualifiedRule

  CSSAtRuleType* = enum
    cartUnknown = "-cha-unknown"
    cartImport = "import"
    cartMedia = "media"

  CSSAtRule* = ref object
    name*: CSSAtRuleType
    prelude*: seq[CSSToken]
    oblock*: seq[CSSToken]

  CSSQualifiedRule* = ref object
    sels*: SelectorList
    decls*: seq[CSSDeclaration]

  CSSDeclarationType* = enum
    cdtProperty, cdtVariable

  CSSImportantFlag* = enum
    cifNormal, cifImportant

  CSSAnyPropertyType* = object
    sh*: CSSShorthandType # if sh is cstNone, then use p
    p*: CSSPropertyType

  CSSDeclaration* = object
    f*: CSSImportantFlag
    hasVar*: bool
    case t*: CSSDeclarationType
    of cdtProperty:
      p*: CSSAnyPropertyType
    of cdtVariable:
      v*: CAtom
    value*: seq[CSSToken]

  CSSFunctionType* = enum
    cftUnknown = "-cha-unknown"
    cftNot = "not"
    cftIs = "is"
    cftWhere = "where"
    cftNthChild = "nth-child"
    cftNthLastChild = "nth-last-child"
    cftLang = "lang"
    cftRgb = "rgb"
    cftRgba = "rgba"
    cftChaAnsi = "-cha-ansi"
    cftUrl = "url"
    cftSrc = "src"
    cftVar = "var"
    cftHsl = "hsl"
    cftHsla = "hsla"
    cftCalc = "calc"
    cftCounter = "counter"

  CSSSimpleBlock* = ref object
    value*: seq[CSSToken]

  CSSAnB* = tuple[A, B: int32]

# Properties

  CSSShorthandType* = enum
    cstNone = ""
    cstAll = "all"
    cstMargin = "margin"
    cstPadding = "padding"
    cstBorderStyle = "border-style"
    cstBorderColor = "border-color"
    cstBorderWidth = "border-width"
    cstBackground = "background"
    cstListStyle = "list-style"
    cstFlex = "flex"
    cstFlexFlow = "flex-flow"
    cstOverflow = "overflow"
    cstVerticalAlign = "vertical-align"
    cstBorderSpacing = "border-spacing"
    cstBorderBottom = "border-bottom"
    cstBorderLeft = "border-left"
    cstBorderRight = "border-right"
    cstBorderTop = "border-top"
    cstBorder = "border"

  CSSPropertyType* = enum
    # primitive/enum properties: stored as byte
    # (when adding a new property, sort the individual lists, and update
    # LastBitPropType/LastWordPropType if needed.)
    cptBgcolorIsCanvas = "-cha-bgcolor-is-canvas"
    cptBorderBottomStyle = "border-bottom-style"
    cptBorderCollapse = "border-collapse"
    cptBorderLeftStyle = "border-left-style"
    cptBorderRightStyle = "border-right-style"
    cptBorderTopStyle = "border-top-style"
    cptBoxSizing = "box-sizing"
    cptCaptionSide = "caption-side"
    cptClear = "clear"
    cptDisplay = "display"
    cptFlexDirection = "flex-direction"
    cptFlexWrap = "flex-wrap"
    cptFloat = "float"
    cptFontStyle = "font-style"
    cptListStylePosition = "list-style-position"
    cptListStyleType = "list-style-type"
    cptOverflowX = "overflow-x"
    cptOverflowY = "overflow-y"
    cptPosition = "position"
    cptTextAlign = "text-align"
    cptTextDecoration = "text-decoration"
    cptTextTransform = "text-transform"
    cptVerticalAlign = "vertical-align"
    cptVisibility = "visibility"
    cptWhiteSpace = "white-space"
    cptWordBreak = "word-break"

    # half-word properties: stored as (32-bit) word
    cptBorderBottomWidth = "border-bottom-width"
    cptBorderLeftWidth = "border-left-width"
    cptBorderRightWidth = "border-right-width"
    cptBorderTopWidth = "border-top-width"
    cptChaColspan = "-cha-colspan"
    cptChaRowspan = "-cha-rowspan"
    cptFlexGrow = "flex-grow"
    cptFlexShrink = "flex-shrink"
    cptFontWeight = "font-weight"
    cptInputIntrinsicSize = "-cha-input-intrinsic-size"
    cptOpacity = "opacity"

    # word properties: stored as (64-bit) word
    cptBackgroundColor = "background-color"
    cptBorderBottomColor = "border-bottom-color"
    cptBorderLeftColor = "border-left-color"
    cptBorderRightColor = "border-right-color"
    cptBorderSpacingBlock = "-cha-border-spacing-block"
    cptBorderSpacingInline = "-cha-border-spacing-inline"
    cptBorderTopColor = "border-top-color"
    cptBottom = "bottom"
    cptColor = "color"
    cptFlexBasis = "flex-basis"
    cptFontSize = "font-size"
    cptHeight = "height"
    cptLeft = "left"
    cptMarginBottom = "margin-bottom"
    cptMarginLeft = "margin-left"
    cptMarginRight = "margin-right"
    cptMarginTop = "margin-top"
    cptMaxHeight = "max-height"
    cptMaxWidth = "max-width"
    cptMinHeight = "min-height"
    cptMinWidth = "min-width"
    cptPaddingBottom = "padding-bottom"
    cptPaddingLeft = "padding-left"
    cptPaddingRight = "padding-right"
    cptPaddingTop = "padding-top"
    cptRight = "right"
    cptTop = "top"
    cptVerticalAlignLength = "-cha-vertical-align-length"
    cptWidth = "width"
    cptZIndex = "z-index"

    # object properties: stored as a tagged ref object
    cptBackgroundImage = "background-image"
    cptContent = "content"
    cptCounterReset = "counter-reset"
    cptCounterIncrement = "counter-increment"
    cptCounterSet = "counter-set"
    cptQuotes = "quotes"

# Selectors

  SelectorType* = enum
    stType, stId, stAttr, stClass, stUniversal, stPseudoClass, stPseudoElement,
    stIs = "is"
    stNot = "not"
    stWhere = "where"
    stLang = "lang"
    stNthChild = "nth-child"
    stNthLastChild = "nth-last-child"

  SelectorTypeRecursive = range[stIs..stWhere]

  SelectorTypeNthChild = range[stNthChild..stNthLastChild]

  PseudoElement* = enum
    peNone = "-cha-none"
    peBefore = "before"
    peAfter = "after"
    peMarker = "marker"
    peLinkMarker = "-cha-link-marker"

  PseudoClass* = enum
    pcFirstChild = "first-child"
    pcLastChild = "last-child"
    pcOnlyChild = "only-child"
    pcHover = "hover"
    pcRoot = "root"
    pcChecked = "checked"
    pcFocus = "focus"
    pcLink = "link"
    pcVisited = "visited"
    pcTarget = "target"
    pcDisabled = "disabled"
    pcFirstNode = "-cha-first-node"
    pcLastNode = "-cha-last-node"
    pcBorderNonzero = "-cha-border-nonzero"

  CombinatorType* = enum
    ctNone, ctDescendant, ctChild, ctNextSibling, ctSubsequentSibling

  SelectorParser = object
    selectors: seq[ComplexSelector]
    ctx: CSSParser
    failed: bool
    nested: bool

  RelationType* = enum
    rtExists, rtEquals, rtToken, rtBeginDash, rtStartsWith, rtEndsWith,
    rtContains

  RelationFlag* = enum
    rfNone, rfI, rfS

  SelectorRelation* = object
    t*: RelationType
    flag*: RelationFlag

  CSSNthChild* = object
    anb*: CSSAnB
    ofsels*: SelectorList

  Selector* = ref object # Simple selector
    case t*: SelectorType
    of stType:
      tag*: CAtom
    of stId:
      id*: CAtom
    of stClass:
      class*: CAtom
    of stAttr:
      attr*: CAtom
      rel*: SelectorRelation
      value*: string
    of stUniversal: #TODO namespaces?
      discard
    of stPseudoClass:
      pc*: PseudoClass
    of stIs, stWhere, stNot:
      fsels*: SelectorList
    of stLang:
      lang*: string
    of stNthChild, stNthLastChild:
      nthChild*: CSSNthChild
    of stPseudoElement:
      elem*: PseudoElement

  CompoundSelector* = object
    ct*: CombinatorType # relation to the next entry in a ComplexSelector.
    sels*: seq[Selector]

  ComplexSelector* = object
    specificity*: uint
    pseudo*: PseudoElement
    csels: seq[CompoundSelector]

  SelectorList* = seq[ComplexSelector]

# Forward declarations
proc consumeDeclarations(ctx: var CSSParser; nested: bool): seq[CSSDeclaration]
proc parseSelectorsConsume(toks: var seq[CSSToken]): seq[ComplexSelector]
proc parseSelectorList(state: var SelectorParser; forgiving: bool): SelectorList
proc parseComplexSelector(state: var SelectorParser): ComplexSelector
proc addComponentValue(ctx: var CSSParser; toks: var seq[CSSToken])
proc seek*(ctx: var CSSParser)
proc `$`*(tok: CSSToken): string
proc `$`*(c: CSSRule): string
proc `$`*(decl: CSSDeclaration): string
proc `$`*(c: CSSSimpleBlock): string
proc `$`*(slist: SelectorList): string

template fnum(tok: CSSToken): float32 =
  tok.tu.f

template inum(tok: CSSToken): int32 =
  tok.tu.i

template ft*(tok: CSSToken): CSSFunctionType =
  tok.tu.ft

template delim(tok: CSSToken): uint32 =
  tok.tu.u

proc num*(tok: CSSToken): float32 {.inline.} =
  if ctfInteger in tok.flags:
    float32(tok.inum)
  else:
    tok.fnum

proc toi*(tok: CSSToken): int32 {.inline.} =
  if ctfInteger in tok.flags:
    tok.inum
  else:
    int32(tok.fnum)

proc `$`*(tok: CSSToken): string =
  return case tok.t:
  of cttAtKeyword: $tok.t & tok.s & '\n'
  of cttFunction: $tok.ft & '('
  of cttUrl: "url(" & tok.s & ')'
  of cttHash: '#' & tok.s
  of cttIdent: tok.s
  of cttString: ("\"" & tok.s & "\"")
  of cttDelim: tok.delim.toUTF8()
  of cttNumber:
    if ctfInteger in tok.flags:
      $tok.inum
    else:
      $tok.fnum
  of cttDimension:
    if ctfInteger in tok.flags:
      $tok.inum & tok.s
    else:
      $tok.fnum & tok.s
  of cttPercentage: $tok.fnum & '%'
  of cttWhitespace: " "
  of cttSemicolon: ";\n"
  of cttRbrace: "}\n"
  else: $tok.t

proc `$`*(p: CSSAnyPropertyType): string =
  if p.sh != cstNone:
    return $p.sh
  return $p.p

proc name*(decl: CSSDeclaration): string =
  case decl.t
  of cdtProperty: result &= $decl.p
  of cdtVariable: result &= "--" & $decl.v

proc `$`*(decl: CSSDeclaration): string =
  result = decl.name & ": "
  for s in decl.value:
    result &= $s
  if decl.f == cifImportant:
    result &= " !important"
  result &= ";"

proc `$`*(c: CSSSimpleBlock): string =
  result = ""
  for s in c.value:
    result &= $s

proc `$`*(c: CSSAtRule): string =
  result = $c.name & ' '
  for it in c.prelude:
    result &= $it
  result &= "{\n"
  for it in c.oblock:
    result &= $it
  result &= "}"

proc `$`*(c: CSSQualifiedRule): string =
  result = $c.sels & " {\n"
  for decl in c.decls:
    result &= $decl & '\n'
  result &= "}\n"

proc `$`*(c: CSSRule): string =
  case c.t
  of crtAt: return $c.at
  of crtQualified: return $c.qualified

const LastBitPropType* = cptWordBreak
const FirstHWordPropType* = LastBitPropType.succ
const LastHWordPropType* = cptOpacity
const FirstWordPropType* = LastHWordPropType.succ
const LastWordPropType* = cptZIndex
const FirstObjPropType* = LastWordPropType.succ

proc shorthandType*(s: string): CSSShorthandType =
  return parseEnumNoCase[CSSShorthandType](s).get(cstNone)

proc propertyType*(s: string): Opt[CSSPropertyType] =
  return parseEnumNoCase[CSSPropertyType](s)

converter toAnyPropertyType*(p: CSSPropertyType): CSSAnyPropertyType =
  CSSAnyPropertyType(sh: cstNone, p: p)

proc anyPropertyType*(s: string): Opt[CSSAnyPropertyType] =
  let sh = shorthandType(s)
  if sh == cstNone:
    let p = ?propertyType(s)
    return ok(CSSAnyPropertyType(sh: sh, p: p))
  return ok(CSSAnyPropertyType(sh: sh))

proc cssNumberToken*(n: float32): CSSToken =
  let tu = CSSTokenUnion(f: n)
  return CSSToken(t: cttNumber, tu: tu)

proc cssDimensionToken*(n: float32; dt: CSSDimensionType): CSSToken =
  let tu = CSSTokenUnion(f: n)
  CSSToken(t: cttDimension, tu: tu, dt: dt)

proc cssPercentageToken*(n: float32; flags: set[CSSTokenFlag] = {}): CSSToken =
  let tu = CSSTokenUnion(f: n)
  return CSSToken(t: cttPercentage, tu: tu, flags: flags)

proc cssDelimToken(c: char): CSSToken =
  let tu = CSSTokenUnion(u: uint32(c))
  return CSSToken(t: cttDelim, tu: tu)

proc cssFunctionToken(ft: CSSFunctionType): CSSToken =
  let tu = CSSTokenUnion(ft: ft)
  return CSSToken(t: cttFunction, tu: tu)

const IdentStart = AsciiAlpha + NonAscii + {'_'}
const Ident = IdentStart + AsciiDigit + {'-'}

proc consumeDelimToken(iq: openArray[char]; n: var int): CSSToken =
  let u = iq.nextUTF8(n)
  let tu = CSSTokenUnion(u: u)
  return CSSToken(t: cttDelim, tu: tu)

# next, next(1)
proc startsWithIdentSequenceDash(iq: openArray[char]; n: int): bool =
  return n < iq.len and iq[n] in IdentStart + {'-'} or
    n + 1 < iq.len and iq[n] == '\\' and iq[n + 1] != '\n'

# next, next(1), next(2)
proc startsWithIdentSequence(iq: openArray[char]; n: int): bool =
  if n >= iq.len:
    return false
  case iq[n]
  of '-':
    return n + 1 < iq.len and iq[n + 1] in IdentStart + {'-'} or
      n + 2 < iq.len and iq[n + 1] == '\\' and iq[n + 2] != '\n'
  of IdentStart:
    return true
  of '\\':
    return n + 1 < iq.len and iq[n + 1] != '\n'
  else:
    return false

proc consumeEscape(iq: openArray[char]; n: var int): string =
  if n >= iq.len:
    return "\uFFFD"
  let c = iq[n]
  inc n
  if c in AsciiHexDigit:
    var num = uint32(hexValue(c))
    var i = 0
    while i <= 5 and n < iq.len:
      let val = hexValue(iq[n])
      if val == -1:
        break
      num *= 0x10
      num += uint32(val)
      inc n
      inc i
    if n < iq.len and iq[n] in AsciiWhitespace:
      inc n
    if num == 0 or num > 0x10FFFF or num in 0xD800u32..0xDFFFu32:
      return "\uFFFD"
    return num.toUTF8()
  return $c # assume the caller doesn't care about non-ascii

proc consumeStringToken(iq: openArray[char]; ending: char; n: var int):
    CSSToken =
  var s = ""
  while n < iq.len:
    let c = iq[n]
    case c
    of '\n':
      return CSSToken(t: cttBadString)
    of '\\':
      if n + 1 >= iq.len or iq[n + 1] == '\n':
        discard
      else:
        inc n
        s &= iq.consumeEscape(n)
        continue
    elif c == ending:
      inc n
      break
    else:
      s &= c
    inc n
  return CSSToken(t: cttString, s: move(s))

proc consumeIdentSequence(iq: openArray[char]; n: var int): string =
  var s = ""
  while n < iq.len:
    let c = iq[n]
    if c == '\\' and n + 1 < iq.len and iq[n + 1] != '\n':
      inc n
      s &= iq.consumeEscape(n)
      continue
    elif c in Ident:
      s &= c
    else:
      break
    inc n
  move(s)

proc consumeNumericToken(iq: openArray[char]; n: var int): CSSToken =
  var isInt = true
  var flags: set[CSSTokenFlag] = {}
  var m = n
  let start = m
  var sign = 1i64
  if n < iq.len and (let c = iq[m]; c in {'+', '-'}):
    if c == '-':
      sign = -1
    flags.incl(ctfSign)
    inc m
  var integer = 0u32
  while m < iq.len and (let c = iq[m]; c in AsciiDigit):
    let u = uint32(c) - uint32('0')
    let uu = integer * 10 + u
    isInt = isInt and (uu > integer or u == 0 and integer == 0)
    integer = uu
    inc m
  if m + 1 < iq.len and iq[m] == '.' and iq[m + 1] in AsciiDigit:
    m += 2
    isInt = false
    while m < iq.len and iq[m] in AsciiDigit:
      inc m
  if m + 1 < iq.len and iq[m] in {'E', 'e'}:
    let c = iq[m + 1]
    let signed = c in {'-', '+'}
    if c in AsciiDigit or signed and m + 2 < iq.len and iq[m + 2] in AsciiDigit:
      isInt = false
      m += (if signed: 3 else: 2)
      while m < iq.len and iq[m] in AsciiDigit:
        inc m
  if m < iq.len and iq[m] == '%':
    let f = parseFloat32(iq.toOpenArray(start, m - 1))
    n = m + 1
    return cssPercentageToken(f, flags)
  let isDim = iq.startsWithIdentSequence(m)
  var ii: int32
  if isInt:
    let i = int64(integer) * sign
    ii = cast[int32](i)
    if int64(ii) != i:
      isInt = false
  let tu = if isInt:
    flags.incl(ctfInteger)
    CSSTokenUnion(i: ii)
  else:
    CSSTokenUnion(f: parseFloat32(iq.toOpenArray(start, m - 1)))
  if isDim:
    var s = iq.consumeIdentSequence(m)
    n = m
    if dt := parseEnumNoCase[CSSDimensionType](s):
      return CSSToken(t: cttDimension, tu: tu, dt: dt, flags: flags)
    return CSSToken(
      t: cttDimension,
      tu: tu,
      dt: cdtUnknown,
      s: move(s),
      flags: flags
    )
  n = m
  return CSSToken(t: cttNumber, tu: tu, flags: flags)

proc consumeBadURL(iq: openArray[char]; n: var int) =
  while n < iq.len:
    let c = iq[n]
    inc n
    if c == ')':
      break
    if c == '\\' and n < iq.len and iq[n] != '\n':
      discard iq.consumeEscape(n)

const NonPrintable = {
  '\0'..char(0x08), '\v', char(0x0E)..char(0x1F), char(0x7F)
}

proc consumeURL(iq: openArray[char]; n: var int): CSSToken =
  var res = CSSToken(t: cttUrl)
  n = iq.skipBlanks(n)
  while n < iq.len:
    let c = iq[n]
    inc n
    case c
    of ')':
      return res
    of '"', '\'', '(', NonPrintable:
      iq.consumeBadURL(n)
      return CSSToken(t: cttBadUrl)
    of AsciiWhitespace:
      n = iq.skipBlanks(n)
      if n >= iq.len:
        return res
      if iq[n] == ')':
        inc n
        return res
      iq.consumeBadURL(n)
      return CSSToken(t: cttBadUrl)
    of '\\':
      if n < iq.len and iq[n] != '\n':
        res.s &= iq.consumeEscape(n)
      else:
        iq.consumeBadURL(n)
        return CSSToken(t: cttBadUrl)
    else:
      res.s &= c
  move(res)

proc consumeIdentLikeToken(iq: openArray[char]; n: var int): CSSToken =
  var s = iq.consumeIdentSequence(n)
  if s.equalsIgnoreCase("url") and n < iq.len and iq[n] == '(':
    inc n
    while n + 1 < iq.len and iq[n] in AsciiWhitespace and
        iq[n + 1] in AsciiWhitespace:
      inc n
    if n < iq.len and iq[n] in {'"', '\''} or
        n + 1 < iq.len and iq[n] in {'"', '\''} + AsciiWhitespace and
        iq[n + 1] in {'"', '\''}:
      return cssFunctionToken(cftUrl)
    return iq.consumeURL(n)
  if n < iq.len and iq[n] == '(':
    let ft = parseEnumNoCase[CSSFunctionType](s).get(cftUnknown)
    inc n
    return cssFunctionToken(ft)
  return CSSToken(t: cttIdent, s: move(s))

proc nextToken(iq: openArray[char]; n: var int): bool =
  var m = n
  while m + 1 < iq.len and iq[m] == '/' and iq[m + 1] == '*':
    m += 2
    while m < iq.len and not (m + 1 < iq.len and iq[m] == '*' and
        iq[m + 1] == '/'):
      inc m
    if m + 1 < iq.len:
      inc m
    if m < iq.len:
      inc m
  n = m
  return m < iq.len

proc consumeToken(iq: openArray[char]; n: var int): CSSToken =
  let c = iq[n]
  inc n
  case c
  of AsciiWhitespace:
    n = iq.skipBlanks(n)
    return CSSToken(t: cttWhitespace)
  of '"', '\'':
    return iq.consumeStringToken(c, n)
  of '#':
    if n < iq.len and iq[n] in Ident or
        n + 1 < iq.len and iq[n] == '\\' and iq[n + 1] != '\n':
      var flags: set[CSSTokenFlag] = {}
      if iq.startsWithIdentSequence(n):
        flags.incl(ctfId)
      return CSSToken(t: cttHash, s: iq.consumeIdentSequence(n), flags: flags)
    return cssDelimToken('#')
  of '(': return CSSToken(t: cttLparen)
  of ')': return CSSToken(t: cttRparen)
  of '{': return CSSToken(t: cttLbrace)
  of '}': return CSSToken(t: cttRbrace)
  of '+':
    # starts with a number
    if n < iq.len and iq[n] in AsciiDigit or
        n + 1 < iq.len and iq[n] == '.' and iq[n + 1] in AsciiDigit:
      dec n
      return iq.consumeNumericToken(n)
    return CSSToken(t: cttPlus)
  of ',': return CSSToken(t: cttComma)
  of '-':
    # starts with a number
    if n < iq.len and iq[n] in AsciiDigit or
        n + 1 < iq.len and iq[n] == '.' and iq[n + 1] in AsciiDigit:
      dec n
      return iq.consumeNumericToken(n)
    elif n + 1 < iq.len and iq[n] == '-' and iq[n + 1] == '>':
      n += 2
      return CSSToken(t: cttCdc)
    elif iq.startsWithIdentSequenceDash(n):
      dec n
      return iq.consumeIdentLikeToken(n)
    else:
      return CSSToken(t: cttMinus)
  of '.':
    # starts with a number
    if n < iq.len and iq[n] in AsciiDigit:
      dec n
      return iq.consumeNumericToken(n)
    return CSSToken(t: cttDot)
  of ':': return CSSToken(t: cttColon)
  of ';': return CSSToken(t: cttSemicolon)
  of '<':
    if n + 2 < iq.len and iq[n] == '!' and iq[n + 1] == '-' and
        iq[n + 2] == '-':
      n += 3
      return CSSToken(t: cttCdo)
    return CSSToken(t: cttLt)
  of '@':
    if iq.startsWithIdentSequence(n):
      return CSSToken(t: cttAtKeyword, s: iq.consumeIdentSequence(n))
    return cssDelimToken('@')
  of '[': return CSSToken(t: cttLbracket)
  of '\\':
    if n < iq.len and iq[n] != '\n':
      dec n
      return iq.consumeIdentLikeToken(n)
    return cssDelimToken('\\')
  of ']': return CSSToken(t: cttRbracket)
  of AsciiDigit:
    dec n
    return iq.consumeNumericToken(n)
  of IdentStart:
    dec n
    return iq.consumeIdentLikeToken(n)
  of '/': return CSSToken(t: cttSlash)
  of '>': return CSSToken(t: cttGt)
  of '*': return CSSToken(t: cttStar)
  of '~': return CSSToken(t: cttTilde)
  of '|': return CSSToken(t: cttPipe)
  of '^': return CSSToken(t: cttCaret)
  of '$': return CSSToken(t: cttDollar)
  of '=': return CSSToken(t: cttEquals)
  of '!': return CSSToken(t: cttBang)
  else:
    dec n
    return iq.consumeDelimToken(n)

proc tokenPair(t: CSSTokenType): CSSTokenType =
  case t
  of cttLparen, cttFunction: return cttRparen
  of cttLbracket: return cttRbracket
  of cttLbrace: return cttRbrace
  else: return t

template iq(ctx: CSSParser): openArray[char] =
  ctx.iqp.toOpenArray(0, ctx.iqlen - 1)

proc initCSSParser*(iq: openArray[char]): CSSParser =
  if iq.len == 0:
    return CSSParser()
  return CSSParser(
    iqp: cast[ptr UncheckedArray[char]](unsafeAddr iq[0]),
    iqlen: iq.len
  )

proc initCSSParser*(toks: openArray[CSSToken]): CSSParser =
  return CSSParser(toks: @toks)

# Destroys `toks'.
proc initCSSParserSink*(toks: var seq[CSSToken]): CSSParser =
  return CSSParser(toks: move(toks))

proc initCSSDeclaration*(name: string): Opt[CSSDeclaration] =
  if name.startsWith("--"):
    return ok(CSSDeclaration(
      t: cdtVariable,
      v: name.toOpenArray(2, name.high).toAtom()
    ))
  let p = ?anyPropertyType(name)
  ok(CSSDeclaration(t: cdtProperty, p: p))

proc peekToken*(ctx: var CSSParser): lent CSSToken =
  if ctx.toks.len > 0:
    return ctx.toks[ctx.i]
  if ctx.hasBuf:
    return ctx.tokBuf
  discard ctx.iq.nextToken(ctx.i)
  ctx.tokBuf = ctx.iq.consumeToken(ctx.i)
  ctx.hasBuf = true
  return ctx.tokBuf

proc consumeToken(ctx: var CSSParser): CSSToken =
  if ctx.iqlen > 0:
    if ctx.hasBuf:
      ctx.hasBuf = false
      return move(ctx.tokBuf)
    return ctx.iq.consumeToken(ctx.i)
  let i = ctx.i
  inc ctx.i
  return ctx.toks[i]

proc seekToken*(ctx: var CSSParser) =
  if ctx.hasBuf:
    ctx.hasBuf = false
  elif ctx.iqlen > 0:
    discard ctx.consumeToken()
  else:
    inc ctx.i

proc has*(ctx: var CSSParser): bool =
  if ctx.iqlen > 0:
    return ctx.hasBuf or ctx.iq.nextToken(ctx.i)
  return ctx.i < ctx.toks.len

proc peekTokenType*(ctx: var CSSParser): CSSTokenType =
  return ctx.peekToken().t

proc peekIdentNoCase*(ctx: var CSSParser; s: string): bool =
  return ctx.peekTokenType() == cttIdent and
    ctx.peekToken().s.equalsIgnoreCase(s)

proc consume*(ctx: var CSSParser): CSSToken =
  if ctx.iqlen == 0:
    var cval = ctx.toks[ctx.i]
    inc ctx.i
    return move(cval)
  return ctx.consumeToken()

proc consumeInt*(ctx: var CSSParser): Opt[int32] =
  let tok = ctx.peekToken()
  if tok.t != cttNumber or ctfInteger notin tok.flags:
    return err()
  ok(ctx.consume().inum)

proc skipBlanks*(ctx: var CSSParser) =
  while ctx.has() and ctx.peekTokenType() == cttWhitespace:
    ctx.seekToken()

proc skipBlanksCheckHas*(ctx: var CSSParser): Opt[void] =
  ctx.skipBlanks()
  if not ctx.has():
    return err()
  ok()

proc skipBlanksCheckDone*(ctx: var CSSParser): Opt[void] =
  ctx.skipBlanks()
  if ctx.has():
    return err()
  ok()

proc checkFunctionEnd*(ctx: var CSSParser): Opt[void] =
  if ctx.skipBlanksCheckDone().isOk:
    return ok()
  if ctx.peekTokenType() != cttRparen:
    return err()
  ctx.seekToken()
  ok()

proc addComponentValue(ctx: var CSSParser; toks: var seq[CSSToken]) =
  var tok = ctx.consume()
  let t = tok.t
  toks.add(move(tok))
  if (let pair = t.tokenPair; pair != t):
    while ctx.has():
      let t = ctx.peekTokenType()
      ctx.addComponentValue(toks)
      if t == pair:
        break

proc addUntil(ctx: var CSSParser; tt: CSSTokenType; toks: var seq[CSSToken]):
    Opt[CSSToken] =
  while ctx.has():
    if ctx.peekTokenType() == tt:
      return ok(ctx.consume())
    ctx.addComponentValue(toks)
  err()

proc addUntil(ctx: var CSSParser; tt: set[CSSTokenType];
    toks: var seq[CSSToken]): Opt[CSSToken] =
  while ctx.has():
    if ctx.peekTokenType() in tt:
      return ok(ctx.consume())
    ctx.addComponentValue(toks)
  err()

proc skipUntil(ctx: var CSSParser; t: CSSTokenType) =
  while ctx.has():
    let it = ctx.peekTokenType()
    ctx.seek()
    if it == t:
      break

proc skipFunction*(ctx: var CSSParser) =
  ctx.skipUntil(cttRparen)

proc seek*(ctx: var CSSParser) =
  let tok = ctx.consume()
  let pair = tok.t.tokenPair
  if pair != tok.t:
    ctx.skipUntil(pair)

proc consumeQualifiedRule(ctx: var CSSParser): Opt[CSSQualifiedRule] =
  var r = CSSQualifiedRule()
  var prelude: seq[CSSToken] = @[]
  if tok := ctx.addUntil(cttLbrace, prelude):
    r.sels = parseSelectorsConsume(prelude)
    r.decls = ctx.consumeDeclarations(nested = true)
    return ok(r)
  err()

proc skipDeclaration(ctx: var CSSParser) =
  while ctx.has():
    let it = ctx.peekTokenType()
    if it == cttRbrace:
      break
    ctx.seek()
    if it == cttSemicolon:
      break

proc consumeDeclaration(ctx: var CSSParser): Opt[CSSDeclaration] =
  let tok = ctx.consumeToken()
  let x = initCSSDeclaration(tok.s)
  ?ctx.skipBlanksCheckHas()
  if ctx.peekTokenType() != cttColon or x.isErr:
    ctx.skipDeclaration()
    return err()
  var decl = x.get
  ctx.seekToken()
  ctx.skipBlanks()
  var lastTokIdx1 = -1
  var lastTokIdx2 = -1
  var hasVar = false
  while ctx.has():
    case ctx.peekTokenType()
    of cttSemicolon:
      ctx.seekToken()
      break
    of cttWhitespace:
      discard
    of cttRbrace:
      break
    else:
      lastTokIdx1 = lastTokIdx2
      lastTokIdx2 = decl.value.len
    let olen = decl.value.len
    ctx.addComponentValue(decl.value)
    for it in decl.value.toOpenArray(olen, decl.value.high):
      if it.t == cttFunction and it.ft == cftVar:
        hasVar = true
        break
  decl.hasVar = hasVar
  if lastTokIdx1 != -1 and lastTokIdx2 != -1:
    let lastTok1 = decl.value[lastTokIdx1]
    let lastTok2 = decl.value[lastTokIdx2]
    if lastTok1.t == cttBang and
        lastTok2.t == cttIdent and lastTok2.s.equalsIgnoreCase("important"):
      decl.value.setLen(lastTokIdx1)
      decl.f = cifImportant
  while decl.value.len > 0 and decl.value[^1].t == cttWhitespace:
    decl.value.setLen(decl.value.len - 1)
  ok(move(decl))

proc consumeAtRule(ctx: var CSSParser): CSSAtRule =
  let tok = ctx.consumeToken()
  let name = parseEnumNoCase[CSSAtRuleType](tok.s).get(cartUnknown)
  result = CSSAtRule(name: name)
  if found := ctx.addUntil({cttSemicolon, cttLbrace}, result.prelude):
    if found.t == cttLbrace:
      var valid = false
      while ctx.has():
        let t = ctx.peekTokenType()
        if t == cttRbrace:
          valid = true
          ctx.seek()
          break
        ctx.addComponentValue(result.oblock)
      if not valid:
        result.oblock.setLen(0)

proc consumeDeclarations(ctx: var CSSParser; nested: bool):
    seq[CSSDeclaration] =
  result = @[]
  var valid = not nested
  while ctx.has():
    case ctx.peekTokenType()
    of cttWhitespace, cttSemicolon:
      ctx.seekToken()
    of cttAtKeyword:
      discard ctx.consumeAtRule()
    of cttIdent:
      if decl := ctx.consumeDeclaration():
        # looks ridiculous, but it's the only way to convince refc not
        # to copy the seq...  TODO remove when moving to ARC
        var value = move(decl.value)
        result.add(move(decl))
        result[^1].value = move(value)
    of cttRbrace:
      if nested:
        ctx.seekToken()
        valid = true
        break
    else:
      ctx.skipDeclaration()
  if not valid:
    result.setLen(0)

proc consumeRule(ctx: var CSSParser; topLevel: bool): Opt[CSSRule] =
  ?ctx.skipBlanksCheckHas()
  let t = ctx.peekTokenType()
  if t == cttAtKeyword:
    let at = ctx.consumeAtRule()
    if at != nil:
      return ok(CSSRule(t: crtAt, at: at))
  elif topLevel and t in {cttCdo, cttCdc}:
    ctx.seekToken()
    return err()
  let qualified = ?ctx.consumeQualifiedRule()
  return ok(CSSRule(t: crtQualified, qualified: qualified))

iterator parseListOfRules*(ctx: var CSSParser; topLevel: bool):
    CSSRule {.closure.} =
  while ctx.has():
    if rule := ctx.consumeRule(topLevel):
      yield rule

proc parseRule*(iq: openArray[char]): DOMResult[CSSRule] =
  var ctx = initCSSParser(iq)
  var x = ctx.consumeRule(topLevel = false)
  if x.isErr:
    return errDOMException("No qualified rule found", "SyntaxError")
  if ctx.skipBlanksCheckDone().isErr:
    return errDOMException("EOF not reached", "SyntaxError")
  return ok(move(x.get))

proc parseDeclarations*(iq: openArray[char]): seq[CSSDeclaration] =
  var ctx = initCSSParser(iq)
  return ctx.consumeDeclarations(nested = false)

proc parseComponentValue*(iq: openArray[char]): DOMResult[CSSToken] =
  var ctx = initCSSParser(iq)
  ctx.skipBlanks()
  if not ctx.has():
    return errDOMException("Unexpected EOF", "SyntaxError")
  let res = ctx.consume()
  ctx.skipBlanks()
  if ctx.has():
    return errDOMException("EOF not reached", "SyntaxError")
  return ok(res)

proc parseComponentValues*(iq: openArray[char]): seq[CSSToken] =
  var ctx = initCSSParser(iq)
  result = @[]
  while ctx.has():
    result.add(ctx.consume())

proc consumeImports*(ctx: var CSSParser): seq[CSSAtRule] =
  result = @[]
  while ctx.has():
    case ctx.peekTokenType()
    of cttWhitespace:
      ctx.seekToken()
    of cttAtKeyword:
      let rule = ctx.consumeAtRule()
      if rule.name != cartImport or rule.oblock.len > 0:
        break
      result.add(rule)
    else:
      break

proc nextCommaSepComponentValue(toks: openArray[CSSToken]; s: var seq[CSSToken];
    i: var int): bool =
  s = @[]
  while i < toks.len:
    var tok = toks[i]
    inc i
    if tok.t == cttComma:
      break
    s.add(move(tok))
  return s.len > 0

iterator parseCommaSepComponentValues*(toks: openArray[CSSToken]):
    seq[CSSToken] =
  var i = 0
  var s: seq[CSSToken]
  while toks.nextCommaSepComponentValue(s, i):
    yield move(s)

type AnBIdent = enum
  abiOdd = "odd"
  abiEven = "even"
  abiN = "n"
  abiDashN = "-n"
  abiNDash = "n-"
  abiDashNDash = "-n-"

proc isInteger(tok: CSSToken): bool =
  tok.t == cttNumber and ctfInteger in tok.flags

proc isUnsignedInteger(tok: CSSToken): bool =
  tok.isInteger() and ctfSign notin tok.flags

proc parseAnB(ctx: var CSSParser): Opt[CSSAnB] =
  ?ctx.skipBlanksCheckHas()
  var tok = ctx.peekToken()
  let isPlus = tok.t == cttPlus
  let noPlus = if not isPlus: Opt[void].ok() else: Opt[void].err()
  if isPlus:
    ctx.seekToken()
    tok = ctx.peekToken()
  case tok.t
  of cttIdent:
    ctx.seekToken()
    if x := parseEnumNoCase[AnBIdent](tok.s):
      case x
      of abiOdd:
        ?noPlus
        return ok((2i32, 1i32))
      of abiEven:
        ?noPlus
        return ok((2i32, 0i32))
      of abiN:
        if ctx.skipBlanksCheckDone().isOk:
          return ok((1i32, 0i32))
        let tok2 = ctx.peekToken()
        if tok2.t in {cttPlus, cttMinus}:
          ctx.seekToken()
          let sign = if tok2.t == cttPlus: 1i32 else: -1i32
          ?ctx.skipBlanksCheckHas()
          let tok3 = ctx.peekToken()
          if not tok3.isUnsignedInteger():
            return ok((1i32, 0i32))
          ctx.seekToken()
          return ok((1i32, sign * tok3.inum))
        elif tok2.isInteger():
          if ctfInteger notin tok2.flags:
            return ok((1i32, 0i32))
          ctx.seekToken()
          return ok((1i32, tok2.inum))
        else:
          return ok((1i32, 0i32))
      of abiDashN:
        ?noPlus
        if ctx.skipBlanksCheckDone().isOk:
          return ok((-1i32, 0i32))
        let tok2 = ctx.peekToken()
        if tok2.t in {cttPlus, cttMinus}:
          ctx.seekToken()
          let sign = if tok2.t == cttPlus: 1i32 else: -1i32
          ?ctx.skipBlanksCheckHas()
          let tok3 = ctx.peekToken()
          if not tok3.isUnsignedInteger():
            return ok((-1i32, 0i32))
          ctx.seekToken()
          return ok((-1i32, sign * tok3.inum))
        elif tok2.isInteger():
          ctx.seekToken()
          return ok((-1i32, tok2.inum))
        else:
          return ok((-1i32, 0i32))
      of abiNDash:
        ?ctx.skipBlanksCheckHas()
        let tok2 = ctx.peekToken()
        if not tok2.isUnsignedInteger():
          return err()
        ctx.seekToken()
        return ok((1i32, -tok2.inum))
      of abiDashNDash:
        ?noPlus
        ?ctx.skipBlanksCheckHas()
        let tok2 = ctx.peekToken()
        if not tok2.isUnsignedInteger():
          return err()
        ctx.seekToken()
        return ok((-1i32, -tok2.inum))
    elif tok.s.startsWithIgnoreCase("n-"):
      let n = ?parseInt32(tok.s.toOpenArray(2, tok.s.high))
      return ok((1i32, n))
    elif tok.s.startsWithIgnoreCase("-n-"):
      ?noPlus
      let n = ?parseInt32(tok.s.toOpenArray(2, tok.s.high))
      return ok((-1i32, -n))
    else:
      return err()
  of cttNumber:
    if ctfInteger notin tok.flags:
      return err()
    ctx.seekToken()
    ?noPlus
    # <integer>
    return ok((0i32, tok.inum))
  of cttDimension:
    if ctfInteger notin tok.flags:
      return err()
    ctx.seekToken()
    ?noPlus
    case tok.dt
    of cdtN:
      # <n-dimension>
      if ctx.skipBlanksCheckDone().isOk:
        return ok((tok.inum, 0i32))
      let tok2 = ctx.peekToken()
      if tok2.t in {cttPlus, cttMinus}:
        ctx.seekToken()
        let sign = if tok2.t == cttPlus: 1i32 else: -1i32
        ?ctx.skipBlanksCheckHas()
        let tok3 = ctx.peekToken()
        if not tok3.isUnsignedInteger():
          return ok((tok.inum, 0i32))
        ctx.seekToken()
        return ok((tok.inum, sign * tok3.inum))
      elif tok2.isInteger():
        ctx.seekToken()
        return ok((tok.inum, tok2.inum))
      else:
        return ok((tok.inum, 0i32))
    of cdtNDash:
      # <ndash-dimension>
      ?ctx.skipBlanksCheckHas()
      let tok2 = ctx.peekToken()
      if not tok2.isUnsignedInteger():
        return err()
      ctx.seekToken()
      return ok((tok.inum, -tok2.inum))
    of cdtUnknown:
      if tok.s.startsWithIgnoreCase("n-"):
        # <ndashdigit-dimension>
        let n = ?parseInt32(tok.s.toOpenArray(2, tok.s.high))
        return ok((tok.inum, n))
      return err()
    else:
      return err()
  else:
    return err()

iterator items*(csel: CompoundSelector): lent Selector {.inline.} =
  for it in csel.sels:
    yield it

proc `[]`*(csel: CompoundSelector; i: int): lent Selector {.inline.} =
  return csel.sels[i]

proc `[]`*(csel: CompoundSelector; i: BackwardsIndex): lent Selector
    {.inline.} =
  return csel[csel.sels.len - int(i)]

proc len*(csel: CompoundSelector): int {.inline.} =
  return csel.sels.len

proc add*(csel: var CompoundSelector; sel: sink Selector) {.inline.} =
  csel.sels.add(sel)

iterator ritems*(cxsel: ComplexSelector): lent CompoundSelector {.inline.} =
  for csel in cxsel.csels.ritems:
    yield csel

proc `[]`*(cxsel: ComplexSelector; i: int): lent CompoundSelector {.inline.} =
  return cxsel.csels[i]

proc `[]`*(cxsel: ComplexSelector; i: BackwardsIndex): lent CompoundSelector
    {.inline.} =
  return cxsel[cxsel.csels.len - int(i)]

proc `[]`*(cxsel: var ComplexSelector; i: BackwardsIndex): var CompoundSelector
    {.inline.} =
  return cxsel.csels[i]

proc len*(cxsel: ComplexSelector): int {.inline.} =
  return cxsel.csels.len

iterator items*(cxsel: ComplexSelector): lent CompoundSelector {.inline.} =
  for it in cxsel.csels:
    yield it

proc `$`*(nthChild: CSSNthChild): string =
  result = $nthChild.anb.A & 'n' & $nthChild.anb.B
  if nthChild.ofsels.len != 0:
    result &= " of "
    result &= $nthChild.ofsels

proc `$`*(sel: Selector): string =
  case sel.t
  of stType: return $sel.tag
  of stId: return "#" & $sel.id
  of stAttr:
    let rel = case sel.rel.t
    of rtExists: ""
    of rtEquals: "="
    of rtToken: "~="
    of rtBeginDash: "|="
    of rtStartsWith: "^="
    of rtEndsWith: "$="
    of rtContains: "*="
    let flag = case sel.rel.flag
    of rfNone: ""
    of rfI: " i"
    of rfS: " s"
    return '[' & $sel.attr & rel & sel.value & flag & ']'
  of stClass: return "." & $sel.class
  of stUniversal:
    return "*"
  of stPseudoClass:
    return ':' & $sel.pc
  of stIs, stNot, stWhere:
    return ":" & $sel.t & '(' & $sel.fsels & ')'
  of stLang:
    return ":lang(" & sel.lang & ')'
  of stNthChild, stNthLastChild:
    return ':' & $sel.t & '(' & $sel.nthChild & ')'
  of stPseudoElement:
    return "::" & $sel.elem

proc `$`*(sels: CompoundSelector): string =
  result = ""
  for sel in sels:
    result &= $sel

proc `$`*(cxsel: ComplexSelector): string =
  result = ""
  for sels in cxsel:
    result &= $sels
    case sels.ct
    of ctDescendant: result &= ' '
    of ctChild: result &= " > "
    of ctNextSibling: result &= " + "
    of ctSubsequentSibling: result &= " ~ "
    of ctNone: discard

proc `$`*(slist: SelectorList): string =
  result = ""
  var s = false
  for cxsel in slist:
    if s:
      result &= ", "
    result &= $cxsel
    s = true

proc getSpecificity(sel: Selector): uint =
  case sel.t
  of stId: return 1000000
  of stClass, stAttr, stPseudoClass, stLang: return 1000
  of stType, stPseudoElement: return 1
  of stUniversal, stWhere: return 0
  of stIs, stNot:
    var best = 0u
    for child in sel.fsels:
      let s = child.specificity
      if s > best:
        best = s
    return best
  of stNthChild, stNthLastChild:
    var best = 0u
    if sel.nthChild.ofsels.len != 0:
      for child in sel.nthChild.ofsels:
        let s = child.specificity
        if s > best:
          best = s
    return 1000 + best

proc getSpecificity(sels: CompoundSelector): uint =
  result = 0
  for sel in sels:
    result += getSpecificity(sel)

proc consume(state: var SelectorParser): CSSToken =
  state.ctx.consume()

proc has(state: var SelectorParser): bool =
  return not state.failed and state.ctx.has()

proc peekToken(state: var SelectorParser): lent CSSToken =
  return state.ctx.peekToken()

proc peekTokenType(state: var SelectorParser): CSSTokenType =
  return state.ctx.peekTokenType()

proc seekToken(state: var SelectorParser) =
  state.ctx.seekToken()

template fail() =
  state.failed = true
  return

proc skipUntil(state: var SelectorParser; t: CSSTokenType) =
  state.ctx.skipUntil(t)

proc skipFunction(state: var SelectorParser) =
  state.ctx.skipFunction()

proc skipBlanks(state: var SelectorParser) =
  state.ctx.skipBlanks()

# Functions that may contain other selectors, functions, etc.
proc parseRecursiveSelectorFunction(state: var SelectorParser;
    t: SelectorTypeRecursive; forgiving: bool): Selector =
  let onested = state.nested
  state.nested = true
  let fun = Selector(
    t: t,
    fsels: state.parseSelectorList(forgiving)
  )
  state.skipFunction()
  state.nested = onested
  if fun.fsels.len == 0: fail
  return fun

proc parseNthChild(state: var SelectorParser; t: SelectorTypeNthChild):
    Selector =
  let x = state.ctx.parseAnB()
  if x.isErr:
    state.skipFunction()
    fail
  let anb = x.get
  state.skipBlanks()
  if not state.has() or state.peekTokenType() == cttRparen:
    state.skipFunction()
    return Selector(t: t, nthChild: CSSNthChild(anb: anb))
  let lasttok = state.consume()
  if lasttok.t != cttIdent or not lasttok.s.equalsIgnoreCase("of"):
    state.skipFunction()
    fail
  state.skipBlanks()
  if not state.has() or state.peekTokenType() == cttRparen:
    state.skipFunction()
    fail
  let onested = state.nested
  state.nested = true
  let sel = Selector(
    t: t,
    nthChild: CSSNthChild(
      anb: anb,
      ofsels: state.parseSelectorList(forgiving = false)
    )
  )
  state.skipFunction()
  state.nested = onested
  if sel.nthChild.ofsels.len == 0: fail
  return sel

proc parseLang(state: var SelectorParser): Selector =
  state.skipBlanks()
  if not state.has(): fail
  let tok = state.consume()
  let b = tok.t != cttIdent or not state.has() or
    state.peekTokenType() != cttRparen
  state.skipFunction()
  if b: fail
  return Selector(t: stLang, lang: tok.s)

proc parseSelectorFunction(state: var SelectorParser; ft: CSSFunctionType):
    Selector =
  return case ft
  of cftNot:
    state.parseRecursiveSelectorFunction(stNot, forgiving = false)
  of cftIs:
    state.parseRecursiveSelectorFunction(stIs, forgiving = true)
  of cftWhere:
    state.parseRecursiveSelectorFunction(stWhere, forgiving = true)
  of cftNthChild:
    state.parseNthChild(stNthChild)
  of cftNthLastChild:
    state.parseNthChild(stNthLastChild)
  of cftLang:
    state.parseLang()
  else: fail

proc parsePseudoSelector(state: var SelectorParser): Selector =
  result = nil
  if not state.has(): fail
  let tok = state.consume()
  var pseudoElement = peNone
  case tok.t
  of cttIdent:
    if tok.s.equalsIgnoreCase("before"):
      pseudoElement = peBefore
      # fall through
    elif tok.s.equalsIgnoreCase("after"):
      pseudoElement = peAfter
      # fall through
    elif pc := parseEnumNoCase[PseudoClass](tok.s):
      return Selector(t: stPseudoClass, pc: pc)
    else:
      fail
  of cttColon:
    if not state.has(): fail
    let tok = state.consume()
    if tok.t != cttIdent: fail
    pseudoElement = parseEnumNoCase[PseudoElement](tok.s).get(peNone)
    if pseudoElement == peNone:
      fail
    # fall through
  of cttFunction:
    return state.parseSelectorFunction(tok.ft)
  else: fail
  state.skipBlanks()
  if state.nested or state.has() and state.peekTokenType() != cttComma: fail
  return Selector(t: stPseudoElement, elem: pseudoElement)

proc parseAttributeSelector(state: var SelectorParser): Selector =
  state.skipBlanks()
  if not state.has() or state.peekTokenType() == cttRbracket:
    state.skipUntil(cttRbracket)
    fail
  let attr = state.consume()
  if attr.t != cttIdent:
    state.skipUntil(cttRbracket)
    fail
  state.skipBlanks()
  if not state.has(): fail
  let delim = state.consume()
  if delim.t == cttRbracket:
    return Selector(
      t: stAttr,
      attr: attr.s.toAtomLower(),
      rel: SelectorRelation(t: rtExists)
    )
  let rel = case delim.t
  of cttTilde: rtToken
  of cttPipe: rtBeginDash
  of cttCaret: rtStartsWith
  of cttDollar: rtEndsWith
  of cttStar: rtContains
  of cttEquals: rtEquals
  else:
    state.skipUntil(cttRbracket)
    fail
  if rel != rtEquals:
    if not state.has(): fail
    let delim = state.consume()
    if delim.t != cttEquals:
      if delim.t != cttRbracket:
        state.skipUntil(cttRbracket)
      fail
  state.skipBlanks()
  if not state.has(): fail
  let value = state.consume()
  if value.t notin {cttIdent, cttString}:
    if value.t != cttRbracket:
      state.skipUntil(cttRbracket)
    fail
  state.skipBlanks()
  var flag = rfNone
  if state.has() and state.peekTokenType() != cttRbracket:
    let delim = state.consume()
    if delim.t != cttIdent:
      state.skipUntil(cttRbracket)
      fail
    if delim.s.equalsIgnoreCase("i"):
      flag = rfI
    elif delim.s.equalsIgnoreCase("s"):
      flag = rfS
  if not state.has() or state.consume().t != cttRbracket:
    state.skipUntil(cttRbracket)
    fail
  return Selector(
    t: stAttr,
    attr: attr.s.toAtomLower(),
    value: value.s,
    rel: SelectorRelation(t: rel, flag: flag)
  )

proc parseClassSelector(state: var SelectorParser): Selector =
  if not state.has(): fail
  let tok = state.consume()
  if tok.t != cttIdent: fail
  let class = tok.s.toAtomLower()
  Selector(t: stClass, class: class)

proc parseCompoundSelector(state: var SelectorParser): CompoundSelector =
  result = CompoundSelector()
  while state.has():
    let tok = state.peekToken()
    case tok.t
    of cttIdent:
      state.seekToken()
      let tag = tok.s.toAtomLower()
      result.add(Selector(t: stType, tag: tag))
    of cttColon:
      state.seekToken()
      result.add(state.parsePseudoSelector())
    of cttHash:
      state.seekToken()
      if ctfId notin tok.flags:
        fail
      let id = tok.s.toAtomLower()
      result.add(Selector(t: stId, id: id))
    of cttDot:
      state.seekToken()
      result.add(state.parseClassSelector())
    of cttStar:
      state.seekToken()
      result.add(Selector(t: stUniversal))
    of cttLbracket:
      state.seekToken()
      result.add(state.parseAttributeSelector())
    of cttRparen:
      if not state.nested: fail
      break
    of cttComma, cttPlus, cttGt, cttTilde, cttWhitespace:
      break
    else: fail

proc parseComplexSelector(state: var SelectorParser): ComplexSelector =
  result = ComplexSelector()
  while true:
    state.skipBlanks()
    let sels = state.parseCompoundSelector()
    if state.failed:
      break
    #TODO propagate from parser
    result.specificity += sels.getSpecificity()
    result.csels.add(sels)
    if sels.len == 0: fail
    if not state.has() or state.nested and state.peekTokenType() == cttRparen:
      break # finish
    let tok = state.consume()
    case tok.t
    of cttGt: result[^1].ct = ctChild
    of cttPlus: result[^1].ct = ctNextSibling
    of cttTilde: result[^1].ct = ctSubsequentSibling
    of cttWhitespace:
      if not state.has() or state.peekTokenType() == cttComma:
        break # skip trailing whitespace
      elif state.peekTokenType() in {cttGt, cttPlus, cttTilde}:
        case state.consume().t
        of cttGt: result[^1].ct = ctChild
        of cttPlus: result[^1].ct = ctNextSibling
        else: result[^1].ct = ctSubsequentSibling # cttTilde
      else:
        result[^1].ct = ctDescendant
    of cttComma:
      break # finish
    else: fail
  if result.len == 0 or result[^1].ct != ctNone:
    fail
  if result[^1][^1].t == stPseudoElement:
    #TODO move pseudo check here?
    result.pseudo = result[^1][^1].elem

proc parseSelectorList(state: var SelectorParser; forgiving: bool):
    SelectorList =
  var res: SelectorList = @[]
  while true:
    if not state.has() or state.nested and state.peekTokenType() == cttRparen:
      break
    let csel = state.parseComplexSelector()
    if state.failed:
      if not forgiving:
        return @[]
      # forgiving is always nested
      assert state.nested
      state.failed = false
      while state.has():
        case state.peekTokenType()
        of cttComma:
          state.seekToken()
          break
        of cttRparen: break
        else: state.ctx.seek()
    else:
      res.add(csel)
  res.sort(proc(a, b: ComplexSelector): int =
    cmp(a.specificity, b.specificity), Descending)
  move(res)

proc parseSelectorsConsume(toks: var seq[CSSToken]): seq[ComplexSelector] =
  var state = SelectorParser(ctx: initCSSParserSink(toks))
  state.parseSelectorList(forgiving = false)

proc parseSelectors*(ibuf: openArray[char]): seq[ComplexSelector] =
  var state = SelectorParser(ctx: initCSSParser(ibuf))
  state.parseSelectorList(forgiving = false)

{.pop.} # raises: []
