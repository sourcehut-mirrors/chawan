{.push raises: [].}

import std/algorithm
import std/options
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
    cttUrl, cttBadUrl, cttDelim, cttNumber, cttINumber, cttPercentage,
    cttDimension, cttIDimension, cttWhitespace
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
    ctfId, ctfSign

  CSSToken* = object # token or component value
    num*: float32 # for number-like
    flags*: set[CSSTokenFlag]
    c: char # for cttDelim.  if non-ascii, s contains UTF-8
    ft*: CSSFunctionType
    t*: CSSTokenType
    s*: string # for ident/string-like, and unit of number tokens

  CSSRule* = ref object of RootObj

  CSSAtRuleType* = enum
    cartUnknown = "-cha-unknown"
    cartImport = "import"
    cartMedia = "media"

  CSSAtRule* = ref object of CSSRule
    name*: CSSAtRuleType
    prelude*: seq[CSSToken]
    oblock*: seq[CSSToken]

  CSSQualifiedRule* = ref object of CSSRule
    sels*: SelectorList
    decls*: seq[CSSDeclaration]

  CSSDeclarationType* = enum
    cdtUnknown, cdtProperty, cdtVariable

  CSSDeclarationFlag* = enum
    cdfImportant, cdfHasVar

  CSSAnyPropertyType* = object
    sh*: CSSShorthandType # if sh is cstNone, then use p
    p*: CSSPropertyType

  CSSRuleType* = enum
    crtNormal, crtImportant

  CSSDeclaration* = object
    rt*: CSSRuleType
    hasVar*: bool
    case t*: CSSDeclarationType
    of cdtUnknown:
      uname*: string
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
    cstBackground = "background"
    cstListStyle = "list-style"
    cstFlex = "flex"
    cstFlexFlow = "flex-flow"
    cstOverflow = "overflow"
    cstVerticalAlign = "vertical-align"
    cstBorderSpacing = "border-spacing"

  CSSPropertyType* = enum
    # primitive/enum properties: stored as byte
    # (when adding a new property, sort the individual lists, and update
    # LastBitPropType/LastWordPropType if needed.)
    cptBgcolorIsCanvas = "-cha-bgcolor-is-canvas"
    cptBorderCollapse = "border-collapse"
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
    cptChaColspan = "-cha-colspan"
    cptChaRowspan = "-cha-rowspan"
    cptFlexGrow = "flex-grow"
    cptFlexShrink = "flex-shrink"
    cptFontWeight = "font-weight"
    cptOpacity = "opacity"

    # word properties: stored as (64-bit) word
    cptBackgroundColor = "background-color"
    cptBorderSpacingBlock = "-cha-border-spacing-block"
    cptBorderSpacingInline = "-cha-border-spacing-inline"
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
    stType, stId, stAttr, stClass, stUniversal, stPseudoClass, stPseudoElement

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
    pcNthChild = "nth-child"
    pcNthLastChild = "nth-last-child"
    pcChecked = "checked"
    pcFocus = "focus"
    pcIs = "is"
    pcNot = "not"
    pcWhere = "where"
    pcLang = "lang"
    pcLink = "link"
    pcVisited = "visited"
    pcTarget = "target"
    pcFirstNode = "-cha-first-node"
    pcLastNode = "-cha-last-node"

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
      pseudo*: PseudoData
    of stPseudoElement:
      elem*: PseudoElement

  PseudoData* = object
    case t*: PseudoClass
    of pcNthChild, pcNthLastChild:
      anb*: CSSAnB
      ofsels*: SelectorList
    of pcIs, pcWhere, pcNot:
      fsels*: SelectorList
    of pcLang:
      s*: string
    else: discard

  CompoundSelector* = object
    ct*: CombinatorType # relation to the next entry in a ComplexSelector.
    sels*: seq[Selector]

  ComplexSelector* = object
    specificity*: int
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
func `$`*(slist: SelectorList): string

proc `$`*(tok: CSSToken): string =
  return case tok.t:
  of cttAtKeyword: $tok.t & tok.s & '\n'
  of cttFunction: $tok.ft & '('
  of cttUrl: "url(" & tok.s & ")"
  of cttHash: '#' & tok.s
  of cttIdent: tok.s
  of cttString: ("\"" & tok.s & "\"")
  of cttDelim: (if tok.c in Ascii: $tok.c else: tok.s)
  of cttDimension, cttNumber: $tok.num & tok.s
  of cttINumber, cttIDimension: $int32(tok.num) & tok.s
  of cttPercentage: $tok.num & "%"
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
  of cdtUnknown: result &= decl.uname
  of cdtProperty: result &= $decl.p
  of cdtVariable: result &= "--" & $decl.v

proc `$`*(decl: CSSDeclaration): string =
  result = decl.name & ": "
  for s in decl.value:
    result &= $s
  if decl.rt == crtImportant:
    result &= " !important"
  result &= ";"

proc `$`*(c: CSSSimpleBlock): string =
  result = ""
  for s in c.value:
    result &= $s

proc `$`*(c: CSSRule): string =
  result = ""
  if c of CSSAtRule:
    let c = CSSAtRule(c)
    result &= $c.name & ' '
    for it in c.prelude:
      result &= $it
    result &= "{\n"
    for it in c.oblock:
      result &= $it
    result &= "}"
  else:
    let c = CSSQualifiedRule(c)
    result &= $c.sels & " {\n"
    for decl in c.decls:
      result &= $decl & '\n'
    result &= "}\n"

const LastBitPropType* = cptWordBreak
const FirstHWordPropType* = LastBitPropType.succ
const LastHWordPropType* = cptOpacity
const FirstWordPropType* = LastHWordPropType.succ
const LastWordPropType* = cptZIndex
const FirstObjPropType* = LastWordPropType.succ

func shorthandType*(s: string): CSSShorthandType =
  return parseEnumNoCase[CSSShorthandType](s).get(cstNone)

func propertyType*(s: string): Opt[CSSPropertyType] =
  return parseEnumNoCase[CSSPropertyType](s)

converter toAnyPropertyType*(p: CSSPropertyType): CSSAnyPropertyType =
  CSSAnyPropertyType(sh: cstNone, p: p)

func anyPropertyType*(s: string): Opt[CSSAnyPropertyType] =
  let sh = shorthandType(s)
  if sh == cstNone:
    let p = ?propertyType(s)
    return ok(CSSAnyPropertyType(sh: sh, p: p))
  return ok(CSSAnyPropertyType(sh: sh))

const IdentStart = AsciiAlpha + NonAscii + {'_'}
const Ident = IdentStart + AsciiDigit + {'-'}

proc consumeDelimToken(iq: openArray[char]; n: var int): CSSToken =
  let c = iq[n]
  if c in Ascii:
    inc n
    return CSSToken(t: cttDelim, c: c)
  let u = iq.nextUTF8(n)
  return CSSToken(t: cttDelim, c: c, s: u.toUTF8())

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

proc consumeNumber(iq: openArray[char]; n: var int):
    tuple[isInt, hasSign: bool; val: float32] =
  var isInt = true
  var hasSign = false
  let start = n
  if n < iq.len and iq[n] in {'+', '-'}:
    hasSign = true
    inc n
  while n < iq.len and iq[n] in AsciiDigit:
    inc n
  if n + 1 < iq.len and iq[n] == '.' and iq[n + 1] in AsciiDigit:
    n += 2
    isInt = false
    while n < iq.len and iq[n] in AsciiDigit:
      inc n
  if n + 1 < iq.len and iq[n] in {'E', 'e'} and iq[n + 1] in AsciiDigit or
      n + 2 < iq.len and iq[n] in {'E', 'e'} and iq[n + 1] in {'-', '+'} and
        iq[n + 2] in AsciiDigit:
    inc n
    if iq[n] in {'-', '+'}:
      n += 2
    else:
      inc n
    isInt = false
    while n < iq.len and iq[n] in AsciiDigit:
      inc n
  let val = parseFloat32(iq.toOpenArray(start, n - 1))
  return (isInt, hasSign, val)

proc consumeNumericToken(iq: openArray[char]; n: var int): CSSToken =
  let (isInt, hasSign, num) = iq.consumeNumber(n)
  var flags: set[CSSTokenFlag] = {}
  if hasSign:
    flags.incl(ctfSign)
  if iq.startsWithIdentSequence(n):
    var unit = iq.consumeIdentSequence(n)
    return CSSToken(
      t: if isInt: cttIDimension else: cttDimension,
      num: num,
      s: move(unit),
      flags: flags
    )
  if n < iq.len and iq[n] == '%':
    inc n
    return CSSToken(t: cttPercentage, num: num, flags: flags)
  return CSSToken(
    t: if isInt: cttINumber else: cttNumber,
    num: num,
    flags: flags
  )

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
      return CSSToken(t: cttFunction, ft: cftUrl)
    return iq.consumeURL(n)
  if n < iq.len and iq[n] == '(':
    let ft = parseEnumNoCase[CSSFunctionType](s).get(cftUnknown)
    inc n
    return CSSToken(t: cttFunction, ft: ft)
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
    return CSSToken(t: cttDelim, c: '#')
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
    return CSSToken(t: cttDelim, c: c)
  of '[': return CSSToken(t: cttLbracket)
  of '\\':
    if n < iq.len and iq[n] != '\n':
      dec n
      return iq.consumeIdentLikeToken(n)
    return CSSToken(t: cttDelim, c: c)
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

func skipBlanks*(toks: openArray[CSSToken]; i: int): int =
  var i = i
  while i < toks.len:
    if toks[i].t != cttWhitespace:
      break
    inc i
  return i

proc skipBlanksCheckHas*(toks: openArray[CSSToken]; i: int): Opt[int] =
  let i = toks.skipBlanks(i)
  if i >= toks.len:
    return err()
  ok(i)

proc skipBlanksCheckDone*(toks: openArray[CSSToken]; i: int): Opt[void] =
  if toks.skipBlanks(i) < toks.len:
    return err()
  ok()

proc checkFunctionEnd*(toks: openArray[CSSToken]; i: int): Opt[void] =
  let i = toks.skipBlanks(i)
  if i >= toks.len:
    return ok()
  if toks[i].t != cttRparen:
    return err()
  toks.skipBlanksCheckDone(i + 1)

func tokenPair(t: CSSTokenType): CSSTokenType =
  case t
  of cttLparen, cttFunction: return cttRparen
  of cttLbracket: return cttRbracket
  of cttLbrace: return cttRbrace
  else: return t

proc seek(toks: openArray[CSSToken]; i: int): int =
  var i = i
  let t = toks[i].t
  inc i
  let pair = t.tokenPair
  if t != pair:
    while i < toks.len and toks[i].t != pair:
      i = toks.seek(i)
  return i

func findBlank*(toks: openArray[CSSToken]; i: int): int =
  var i = i
  while i < toks.len:
    if toks[i].t == cttWhitespace:
      break
    i = toks.seek(i)
  return i

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

proc initCSSDeclaration*(name: string): CSSDeclaration =
  if name.startsWith("--"):
    return CSSDeclaration(
      t: cdtVariable,
      v: name.toOpenArray(2, name.high).toAtom()
    )
  elif p := anyPropertyType(name):
    return CSSDeclaration(t: cdtProperty, p: p)
  else:
    return CSSDeclaration(t: cdtUnknown, uname: name)

# Warning: this may return a token or a component value.  Only use this
# if you are looking for a simple token.
proc peekToken(ctx: var CSSParser): lent CSSToken =
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

proc seekToken(ctx: var CSSParser) =
  if ctx.hasBuf:
    ctx.hasBuf = false
  else:
    inc ctx.i

func has*(ctx: var CSSParser): bool =
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

proc skipBlanks*(ctx: var CSSParser) =
  if ctx.iqlen > 0:
    while ctx.has():
      let tok = ctx.peekToken()
      if tok.t != cttWhitespace:
        break
      ctx.seekToken()
  else:
    ctx.i = ctx.toks.skipBlanks(ctx.i)

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

proc consumeDeclaration(ctx: var CSSParser): Opt[CSSDeclaration] =
  let tok = ctx.consumeToken()
  var decl = initCSSDeclaration(tok.s)
  ctx.skipBlanks()
  if not ctx.has() or ctx.peekTokenType() != cttColon:
    while ctx.has():
      let it = ctx.peekTokenType()
      if it == cttRbrace:
        break
      ctx.seek()
      if it == cttSemicolon:
        break
    return err()
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
      decl.rt = crtImportant
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

# > Note: Despite the name, this actually parses a mixed list of
# > declarations and at-rules, as CSS 2.1 does for @page. Unexpected
# > at-rules (which could be all of them, in a given context) are
# > invalid and should be ignored by the consumer.
#
# Currently we never use nested at-rules, so the result of consumeAtRule
# is just discarded. This should be changed if we ever need nested at
# rules (e.g. add a flag to include at rules).
proc consumeDeclarations(ctx: var CSSParser; nested: bool):
    seq[CSSDeclaration] =
  result = @[]
  var valid = not nested
  while ctx.has():
    case ctx.peekTokenType()
    of cttWhitespace, cttSemicolon:
      ctx.seekToken()
    of cttAtKeyword:
      discard ctx.consumeAtRule() # see above
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
      ctx.skipUntil(cttSemicolon)
  if not valid:
    result.setLen(0)

iterator parseListOfRules*(ctx: var CSSParser; topLevel: bool):
    CSSRule {.closure.} =
  while ctx.has():
    var rule: CSSRule = nil
    let t = ctx.peekTokenType()
    if t == cttWhitespace:
      ctx.seekToken()
      continue
    elif t == cttAtKeyword:
      rule = ctx.consumeAtRule()
    elif topLevel and t in {cttCdo, cttCdc}:
      ctx.seekToken()
      continue
    if rule == nil:
      rule = ctx.consumeQualifiedRule().get(nil)
    if rule != nil:
      yield rule

proc parseRule*(iq: openArray[char]): DOMResult[CSSRule] =
  var ctx = initCSSParser(iq)
  ctx.skipBlanks()
  if not ctx.has():
    return errDOMException("Unexpected EOF", "SyntaxError")
  var res = if ctx.peekTokenType() == cttAtKeyword:
    ctx.consumeAtRule()
  elif q := ctx.consumeQualifiedRule():
    q
  else:
    return errDOMException("No qualified rule found", "SyntaxError")
  ctx.skipBlanks()
  if ctx.has():
    return errDOMException("EOF not reached", "SyntaxError")
  return ok(res)

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

proc parseAnB(ctx: var CSSParser): Opt[CSSAnB] =
  template fail_plus =
    if isPlus:
      return err()
  template fail_non_signless_integer(tok: CSSToken; res: Opt[CSSAnB]) =
    if tok.t != cttINumber or int64(tok.num) > int32.high or
        ctfSign in tok.flags:
      return res
    ctx.seekToken()

  ?ctx.skipBlanksCheckHas()
  var tok = ctx.consume()
  let isPlus = tok.t == cttPlus
  if isPlus:
    tok = ctx.consume()
  case tok.t
  of cttIdent:
    if x := parseEnumNoCase[AnBIdent](tok.s):
      case x
      of abiOdd:
        fail_plus
        return ok((2i32, 1i32))
      of abiEven:
        fail_plus
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
          fail_non_signless_integer tok3, ok((1i32, 0i32))
          return ok((1i32, sign * int32(tok3.num)))
        elif tok2.t == cttINumber and int64(tok2.num) <= int32.high:
          ctx.seekToken()
          return ok((1i32, int32(tok2.num)))
        else:
          return ok((1i32, 0i32))
      of abiDashN:
        fail_plus
        if ctx.skipBlanksCheckDone().isOk:
          return ok((-1i32, 0i32))
        let tok2 = ctx.peekToken()
        if tok2.t in {cttPlus, cttMinus}:
          ctx.seekToken()
          let sign = if tok2.t == cttPlus: 1i32 else: -1i32
          ?ctx.skipBlanksCheckHas()
          let tok3 = ctx.peekToken()
          fail_non_signless_integer tok3, ok((-1i32, 0i32))
          return ok((-1i32, sign * int32(tok3.num)))
        elif tok2.t == cttINumber and int64(tok2.num) <= int32.high:
          ctx.seekToken()
          return ok((-1i32, int32(tok2.num)))
        else:
          return ok((-1i32, 0i32))
      of abiNDash:
        ?ctx.skipBlanksCheckHas()
        let tok2 = ctx.peekToken()
        fail_non_signless_integer tok2, err()
        return ok((1i32, -int32(tok2.num)))
      of abiDashNDash:
        fail_plus
        ?ctx.skipBlanksCheckHas()
        let tok2 = ctx.peekToken()
        fail_non_signless_integer tok2, err()
        return ok((-1i32, -int32(tok2.num)))
    elif tok.s.startsWithIgnoreCase("n-"):
      let n = ?parseInt32(tok.s.toOpenArray(2, tok.s.high))
      return ok((1i32, n))
    elif tok.s.startsWithIgnoreCase("-n-"):
      fail_plus
      let n = ?parseInt32(tok.s.toOpenArray(2, tok.s.high))
      return ok((-1i32, -n))
    else:
      return err()
  of cttINumber:
    fail_plus
    # <integer>
    return ok((0i32, int32(tok.num)))
  of cttIDimension:
    fail_plus
    case tok.s
    of "n", "N":
      # <n-dimension>
      if ctx.skipBlanksCheckDone().isOk:
        return ok((int32(tok.num), 0i32))
      let tok2 = ctx.peekToken()
      if tok2.t in {cttPlus, cttMinus}:
        ctx.seekToken()
        let sign = if tok2.t == cttPlus: 1i32 else: -1i32
        ?ctx.skipBlanksCheckHas()
        let tok3 = ctx.peekToken()
        fail_non_signless_integer tok3, ok((int32(tok.num), 0i32))
        return ok((int32(tok.num), sign * int32(tok3.num)))
      elif tok2.t == cttINumber and int64(tok2.num) <= int32.high:
        ctx.seekToken()
        return ok((int32(tok.num), int32(tok2.num)))
      else:
        return ok((int32(tok.num), 0i32))
    of "n-", "N-":
      # <ndash-dimension>
      ?ctx.skipBlanksCheckHas()
      let tok2 = ctx.peekToken()
      fail_non_signless_integer tok2, err()
      return ok((int32(tok.num), -int32(tok2.num)))
    elif tok.s.startsWithIgnoreCase("n-"):
      # <ndashdigit-dimension>
      let n = ?parseInt32(tok.s.toOpenArray(2, tok.s.high))
      return ok((int32(tok.num), n))
    else:
      return err()
  else:
    return err()

iterator items*(csel: CompoundSelector): lent Selector {.inline.} =
  for it in csel.sels:
    yield it

func `[]`*(csel: CompoundSelector; i: int): lent Selector {.inline.} =
  return csel.sels[i]

func `[]`*(csel: CompoundSelector; i: BackwardsIndex): lent Selector
    {.inline.} =
  return csel[csel.sels.len - int(i)]

func len*(csel: CompoundSelector): int {.inline.} =
  return csel.sels.len

proc add*(csel: var CompoundSelector; sel: sink Selector) {.inline.} =
  csel.sels.add(sel)

func `[]`*(cxsel: ComplexSelector; i: int): lent CompoundSelector {.inline.} =
  return cxsel.csels[i]

func `[]`*(cxsel: ComplexSelector; i: BackwardsIndex): lent CompoundSelector
    {.inline.} =
  return cxsel[cxsel.csels.len - int(i)]

func `[]`*(cxsel: var ComplexSelector; i: BackwardsIndex): var CompoundSelector
    {.inline.} =
  return cxsel.csels[i]

func len*(cxsel: ComplexSelector): int {.inline.} =
  return cxsel.csels.len

func high*(cxsel: ComplexSelector): int {.inline.} =
  return cxsel.csels.high

iterator items*(cxsel: ComplexSelector): lent CompoundSelector {.inline.} =
  for it in cxsel.csels:
    yield it

func `$`*(sel: Selector): string =
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
    result = ':' & $sel.pseudo.t
    case sel.pseudo.t
    of pcIs, pcNot, pcWhere:
      result &= '('
      result &= $sel.pseudo.fsels
      result &= ')'
    of pcNthChild, pcNthLastChild:
      result &= '(' & $sel.pseudo.anb.A & 'n' & $sel.pseudo.anb.B
      if sel.pseudo.ofsels.len != 0:
        result &= " of "
        result &= $sel.pseudo.ofsels
      result &= ')'
    else: discard
  of stPseudoElement:
    return "::" & $sel.elem

func `$`*(sels: CompoundSelector): string =
  result = ""
  for sel in sels:
    result &= $sel

func `$`*(cxsel: ComplexSelector): string =
  result = ""
  for sels in cxsel:
    result &= $sels
    case sels.ct
    of ctDescendant: result &= ' '
    of ctChild: result &= " > "
    of ctNextSibling: result &= " + "
    of ctSubsequentSibling: result &= " ~ "
    of ctNone: discard

func `$`*(slist: SelectorList): string =
  result = ""
  var s = false
  for cxsel in slist:
    if s:
      result &= ", "
    result &= $cxsel
    s = true

func getSpecificity(sel: Selector): int =
  result = 0
  case sel.t
  of stId:
    result += 1000000
  of stClass, stAttr:
    result += 1000
  of stPseudoClass:
    case sel.pseudo.t
    of pcIs, pcNot:
      var best = 0
      for child in sel.pseudo.fsels:
        let s = child.specificity
        if s > best:
          best = s
      result += best
    of pcNthChild, pcNthLastChild:
      if sel.pseudo.ofsels.len != 0:
        var best = 0
        for child in sel.pseudo.ofsels:
          let s = child.specificity
          if s > best:
            best = s
        result += best
      result += 1000
    of pcWhere: discard
    else: result += 1000
  of stType, stPseudoElement:
    result += 1
  of stUniversal:
    discard

func getSpecificity(sels: CompoundSelector): int =
  result= 0
  for sel in sels:
    result += getSpecificity(sel)

proc consume(state: var SelectorParser): CSSToken =
  state.ctx.consume()

proc has(state: var SelectorParser): bool =
  return not state.failed and state.ctx.has()

proc peekToken(state: var SelectorParser): lent CSSToken =
  return state.ctx.peekToken()

func peekTokenType(state: var SelectorParser): CSSTokenType =
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
    class: PseudoClass; forgiving: bool): Selector =
  var fun = Selector(
    t: stPseudoClass,
    pseudo: PseudoData(t: class),
  )
  let onested = state.nested
  state.nested = true
  fun.pseudo.fsels = state.parseSelectorList(forgiving)
  state.skipFunction()
  state.nested = onested
  if fun.pseudo.fsels.len == 0: fail
  return fun

proc parseNthChild(state: var SelectorParser; data: PseudoData): Selector =
  var data = data
  var anb = state.ctx.parseAnB()
  if anb.isErr:
    state.skipFunction()
    fail
  data.anb = anb.get
  var nthchild = Selector(t: stPseudoClass, pseudo: data)
  state.skipBlanks()
  if not state.has() or state.peekTokenType() == cttRparen:
    state.skipFunction()
    return nthchild
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
  nthchild.pseudo.ofsels = state.parseSelectorList(forgiving = false)
  state.skipFunction()
  state.nested = onested
  if nthchild.pseudo.ofsels.len == 0: fail
  return nthchild

proc parseLang(state: var SelectorParser): Selector =
  state.skipBlanks()
  if not state.has(): fail
  let tok = state.consume()
  let b = tok.t != cttIdent or not state.has() or
    state.peekTokenType() != cttRparen
  state.skipFunction()
  if b: fail
  return Selector(t: stPseudoClass, pseudo: PseudoData(t: pcLang, s: tok.s))

proc parseSelectorFunction(state: var SelectorParser; ft: CSSFunctionType):
    Selector =
  return case ft
  of cftNot:
    state.parseRecursiveSelectorFunction(pcNot, forgiving = false)
  of cftIs:
    state.parseRecursiveSelectorFunction(pcIs, forgiving = true)
  of cftWhere:
    state.parseRecursiveSelectorFunction(pcWhere, forgiving = true)
  of cftNthChild:
    state.parseNthChild(PseudoData(t: pcNthChild))
  of cftNthLastChild:
    state.parseNthChild(PseudoData(t: pcNthLastChild))
  of cftLang:
    state.parseLang()
  else: fail

proc parsePseudoSelector(state: var SelectorParser): Selector =
  result = nil
  if not state.has(): fail
  let tok = state.consume()
  template add_pseudo_element(element: PseudoElement) =
    state.skipBlanks()
    if state.nested or state.has() and state.peekTokenType() != cttComma: fail
    return Selector(t: stPseudoElement, elem: element)
  case tok.t
  of cttIdent:
    template add_pseudo_class(class: PseudoClass) =
      return Selector(t: stPseudoClass, pseudo: PseudoData(t: class))
    if tok.s.equalsIgnoreCase("before"):
      add_pseudo_element peBefore
    elif tok.s.equalsIgnoreCase("after"):
      add_pseudo_element peAfter
    else:
      let class = parseEnumNoCase[PseudoClass](tok.s)
      if class.isErr: fail
      add_pseudo_class class.get
  of cttColon:
    if not state.has(): fail
    let tok = state.consume()
    if tok.t != cttIdent: fail
    let x = parseEnumNoCase[PseudoElement](tok.s)
    if x.isErr: fail
    add_pseudo_element x.get
  of cttFunction:
    return state.parseSelectorFunction(tok.ft)
  else: fail

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
