{.push raises: [].}

import std/options

import html/catom
import html/domexception
import types/opt
import utils/twtstr

type
  CSSTokenType* = enum
    cttIdent, cttFunction, cttAtKeyword, cttHash, cttString,
    cttBadString, cttUrl, cttBadUrl, cttDelim, cttNumber, cttINumber,
    cttPercentage, cttDimension, cttIDimension, cttWhitespace, cttCdo,
    cttCdc, cttColon, cttSemicolon, cttComma, cttRbracket, cttLbracket,
    cttLparen, cttRparen, cttLbrace, cttRbrace

  CSSComponentValue* = ref object of RootObj

  CSSToken* = ref object of CSSComponentValue
    nvalue*: float32
    validId*: bool # type flag; "unrestricted" -> false, "id" -> true
    case t*: CSSTokenType
    of cttIdent, cttFunction, cttAtKeyword, cttHash, cttString, cttUrl:
      value*: string
    of cttDelim:
      cvalue*: char
    of cttNumber, cttINumber, cttPercentage, cttDimension, cttIDimension:
      unit*: string
    else: discard

  CSSRule* = ref object of CSSComponentValue

  CSSAtRuleType* = enum
    cartUnknown = "-cha-unknown"
    cartImport = "import"
    cartMedia = "media"

  CSSAtRule* = ref object of CSSRule
    prelude*: seq[CSSComponentValue]
    name*: CSSAtRuleType
    oblock*: CSSSimpleBlock

  CSSQualifiedRule* = ref object of CSSRule
    sels*: SelectorList
    decls*: seq[CSSDeclaration]

  CSSDeclaration* = ref object of CSSComponentValue
    name*: string
    value*: seq[CSSComponentValue]
    important*: bool

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

  CSSFunction* = ref object of CSSComponentValue
    name*: CSSFunctionType
    value*: seq[CSSComponentValue]

  CSSSimpleBlock* = ref object of CSSComponentValue
    token*: CSSToken
    value*: seq[CSSComponentValue]

  CSSAnB* = tuple[A, B: int32]

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
    cvals: seq[CSSComponentValue]
    at: int
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
proc consumeDeclarations(cvals: openArray[CSSComponentValue]):
  seq[CSSDeclaration]
proc consumeComponentValue(cvals: openArray[CSSComponentValue]; i: var int):
  CSSComponentValue
proc parseSelectors*(cvals: seq[CSSComponentValue]): seq[ComplexSelector]
proc parseSelectorList(cvals: seq[CSSComponentValue]; nested, forgiving: bool):
  SelectorList
proc parseComplexSelector(state: var SelectorParser): ComplexSelector
func `$`*(cxsel: ComplexSelector): string

proc `$`*(c: CSSComponentValue): string =
  result = ""
  if c of CSSToken:
    let c = CSSToken(c)
    case c.t:
    of cttFunction, cttAtKeyword:
      result &= $c.t & c.value & '\n'
    of cttUrl:
      result &= "url(" & c.value & ")"
    of cttHash:
      result &= '#' & c.value
    of cttIdent:
      result &= c.value
    of cttString:
      result &= ("\"" & c.value & "\"")
    of cttDelim:
      if c.cvalue != char(128):
        result &= c.cvalue
      else:
        result &= "<UNICODE>"
    of cttDimension, cttNumber:
      result &= $c.nvalue & c.unit
    of cttINumber, cttIDimension:
      result &= $int32(c.nvalue) & c.unit
    of cttPercentage:
      result &= $c.nvalue & "%"
    of cttColon:
      result &= ":"
    of cttWhitespace:
      result &= " "
    of cttSemicolon:
      result &= ";\n"
    of cttComma:
      result &= ","
    else:
      result &= $c.t & '\n'
  elif c of CSSDeclaration:
    let decl = CSSDeclaration(c)
    result &= decl.name
    result &= ": "
    for s in decl.value:
      result &= $s
    if decl.important:
      result &= " !important"
    result &= ";"
  elif c of CSSFunction:
    result &= $CSSFunction(c).name & "("
    for s in CSSFunction(c).value:
      result &= $s
    result &= ")"
  elif c of CSSSimpleBlock:
    case CSSSimpleBlock(c).token.t
    of cttLbrace: result &= "{\n"
    of cttLparen: result &= "("
    of cttLbracket: result &= "["
    else: discard
    for s in CSSSimpleBlock(c).value:
      result &= $s
    case CSSSimpleBlock(c).token.t
    of cttLbrace: result &= "\n}"
    of cttLparen: result &= ")"
    of cttLbracket: result &= "]"
    else: discard
  elif c of CSSRule:
    if c of CSSAtRule:
      result &= $CSSAtRule(c).name & ' '
    if c of CSSAtRule:
      result &= $CSSAtRule(c).prelude & "\n"
      result &= $CSSAtRule(c).oblock
    else:
      result &= $CSSQualifiedRule(c).sels & "\n"
      result &= $CSSQualifiedRule(c).decls

func `==`*(a: CSSComponentValue; b: CSSTokenType): bool =
  return a of CSSToken and CSSToken(a).t == b

const IdentStart = AsciiAlpha + NonAscii + {'_'}
const Ident = IdentStart + AsciiDigit + {'-'}

proc consumeRChar(iq: openArray[char]; n: var int): char =
  let u = iq.nextUTF8(n)
  if u < 0x80:
    return char(u)
  return char(128)

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

proc consumeCSSString*(iq: openArray[char]; ending: char; n: var int):
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
  return CSSToken(t: cttString, value: move(s))

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
    tuple[isInt: bool; val: float32] =
  var isInt = true
  let start = n
  if n < iq.len and iq[n] in {'+', '-'}:
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
  return (isInt, val)

proc consumeNumericToken(iq: openArray[char]; n: var int): CSSToken =
  let (isInt, val) = iq.consumeNumber(n)
  if iq.startsWithIdentSequence(n):
    var unit = iq.consumeIdentSequence(n)
    if isInt:
      return CSSToken(t: cttIDimension, nvalue: val, unit: move(unit))
    return CSSToken(t: cttDimension, nvalue: val, unit: move(unit))
  if n < iq.len and iq[n] == '%':
    inc n
    return CSSToken(t: cttPercentage, nvalue: val)
  if isInt:
    return CSSToken(t: cttINumber, nvalue: val)
  return CSSToken(t: cttNumber, nvalue: val)

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
  let res = CSSToken(t: cttUrl)
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
        res.value &= iq.consumeEscape(n)
      else:
        iq.consumeBadURL(n)
        return CSSToken(t: cttBadUrl)
    else:
      res.value &= c
  return res

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
      return CSSToken(t: cttFunction, value: move(s))
    return iq.consumeURL(n)
  if n < iq.len and iq[n] == '(':
    inc n
    return CSSToken(t: cttFunction, value: move(s))
  return CSSToken(t: cttIdent, value: move(s))

proc nextCSSToken*(iq: openArray[char]; n: var int): bool =
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
    return iq.consumeCSSString(c, n)
  of '#':
    if n < iq.len and iq[n] in Ident or
        n + 1 < iq.len and iq[n] == '\\' and iq[n + 1] != '\n':
      let validId = iq.startsWithIdentSequence(n)
      return CSSToken(
        t: cttHash,
        value: iq.consumeIdentSequence(n),
        validId: validId
      )
    else:
      dec n
      return CSSToken(t: cttDelim, cvalue: iq.consumeRChar(n))
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
    else:
      return CSSToken(t: cttDelim, cvalue: c)
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
      return CSSToken(t: cttDelim, cvalue: c)
  of '.':
    # starts with a number
    if n < iq.len and iq[n] in AsciiDigit:
      dec n
      return iq.consumeNumericToken(n)
    else:
      return CSSToken(t: cttDelim, cvalue: c)
  of ':': return CSSToken(t: cttColon)
  of ';': return CSSToken(t: cttSemicolon)
  of '<':
    if n + 2 < iq.len and iq[n] == '!' and iq[n + 1] == '-' and
        iq[n + 2] == '-':
      n += 3
      return CSSToken(t: cttCdo)
    else:
      return CSSToken(t: cttDelim, cvalue: c)
  of '@':
    if iq.startsWithIdentSequence(n):
      return CSSToken(t: cttAtKeyword, value: iq.consumeIdentSequence(n))
    else:
      return CSSToken(t: cttDelim, cvalue: c)
  of '[': return CSSToken(t: cttLbracket)
  of '\\':
    if n < iq.len and iq[n] != '\n':
      dec n
      return iq.consumeIdentLikeToken(n)
    else:
      return CSSToken(t: cttDelim, cvalue: c)
  of ']': return CSSToken(t: cttRbracket)
  of AsciiDigit:
    dec n
    return iq.consumeNumericToken(n)
  of IdentStart:
    dec n
    return iq.consumeIdentLikeToken(n)
  else:
    dec n
    return CSSToken(t: cttDelim, cvalue: iq.consumeRChar(n))

proc tokenizeCSS*(iq: openArray[char]): seq[CSSComponentValue] =
  result = @[]
  var n = 0
  while iq.nextCSSToken(n):
    result.add(iq.consumeToken(n))

func skipBlanks*(vals: openArray[CSSComponentValue]; i: int): int =
  var i = i
  while i < vals.len:
    if vals[i] != cttWhitespace:
      break
    inc i
  return i

func findBlank*(vals: openArray[CSSComponentValue]; i: int): int =
  var i = i
  while i < vals.len:
    if vals[i] == cttWhitespace:
      break
    inc i
  return i

func getToken*(cvals: openArray[CSSComponentValue]; i: int): Opt[CSSToken] =
  if i < cvals.len:
    let cval = cvals[i]
    if cval of CSSToken:
      return ok(CSSToken(cval))
  return err()

proc consumeToken*(cvals: openArray[CSSComponentValue]; i: var int):
    Opt[CSSToken] =
  let tok = ?cvals.getToken(i)
  inc i
  return ok(tok)

func getToken*(cvals: openArray[CSSComponentValue]; i: int;
    tt: set[CSSTokenType]): Opt[CSSToken] =
  let tok = ?cvals.getToken(i)
  if tok.t in tt:
    return ok(tok)
  return err()

func getToken*(cvals: openArray[CSSComponentValue]; i: int; t: CSSTokenType):
    Opt[CSSToken] =
  let tok = ?cvals.getToken(i)
  if t == tok.t:
    return ok(tok)
  return err()

proc consumeSimpleBlock(cvals: openArray[CSSComponentValue]; tok: CSSToken;
    i: var int): CSSSimpleBlock =
  var ending: CSSTokenType
  case tok.t
  of cttLbrace: ending = cttRbrace
  of cttLparen: ending = cttRparen
  of cttLbracket: ending = cttRbracket
  else: doAssert false
  result = CSSSimpleBlock(token: tok)
  while i < cvals.len:
    let tok = cvals[i]
    if tok == ending:
      inc i
      break
    elif tok == cttLbrace or tok == cttLbracket or tok == cttLparen:
      inc i
      result.value.add(cvals.consumeSimpleBlock(CSSToken(tok), i))
    else:
      result.value.add(cvals.consumeComponentValue(i))

proc consumeFunction(cvals: openArray[CSSComponentValue]; i: var int):
    CSSFunction =
  let t = CSSToken(cvals[i])
  inc i
  let name = parseEnumNoCase[CSSFunctionType](t.value).get(cftUnknown)
  let res = CSSFunction(name: name)
  while i < cvals.len:
    let t = cvals[i]
    if t == cttRparen:
      inc i
      break
    res.value.add(cvals.consumeComponentValue(i))
  return res

proc consumeComponentValue(cvals: openArray[CSSComponentValue]; i: var int):
    CSSComponentValue =
  let t = cvals[i]
  if t == cttLbrace or t == cttLbracket or t == cttLparen:
    inc i
    return cvals.consumeSimpleBlock(CSSToken(t), i)
  elif t == cttFunction:
    return cvals.consumeFunction(i)
  inc i
  return t

proc consumeQualifiedRule(cvals: openArray[CSSComponentValue]; i: var int):
    Opt[CSSQualifiedRule] =
  var oblock: CSSSimpleBlock = nil
  var r = CSSQualifiedRule()
  var prelude: seq[CSSComponentValue] = @[]
  while i < cvals.len:
    let t = cvals[i]
    if t of CSSSimpleBlock and CSSSimpleBlock(t).token == cttLbrace:
      inc i
      oblock = CSSSimpleBlock(t)
      break
    elif t == cttLbrace:
      inc i
      oblock = cvals.consumeSimpleBlock(CSSToken(t), i)
      break
    else:
      prelude.add(cvals.consumeComponentValue(i))
  if oblock != nil:
    r.sels = prelude.parseSelectors()
    r.decls = oblock.value.consumeDeclarations()
    return ok(r)
  err()

proc consumeAtRule(cvals: openArray[CSSComponentValue]; i: var int): CSSAtRule =
  let t = CSSToken(cvals[i])
  inc i
  let name = parseEnumNoCase[CSSAtRuleType](t.value).get(cartUnknown)
  result = CSSAtRule(name: name)
  while i < cvals.len:
    let t = cvals[i]
    inc i
    if t of CSSSimpleBlock:
      result.oblock = CSSSimpleBlock(t)
      break
    elif t == cttSemicolon:
      break
    elif t == cttLbrace:
      result.oblock = cvals.consumeSimpleBlock(CSSToken(t), i)
      break
    else:
      dec i
      result.prelude.add(cvals.consumeComponentValue(i))

proc consumeDeclaration(cvals: openArray[CSSComponentValue]; i: var int):
    Option[CSSDeclaration] =
  let t = CSSToken(cvals[i])
  i = cvals.skipBlanks(i + 1)
  if i >= cvals.len or cvals[i] != cttColon:
    return none(CSSDeclaration)
  i = cvals.skipBlanks(i + 1)
  let decl = CSSDeclaration(name: t.value)
  while i < cvals.len:
    decl.value.add(cvals.consumeComponentValue(i))
  var j = 0
  var k = 0
  var l = 0
  for i in countdown(decl.value.high, 0):
    if decl.value[i] == cttWhitespace:
      continue
    inc j
    if decl.value[i] == cttIdent and k == 0:
      if CSSToken(decl.value[i]).value.equalsIgnoreCase("important"):
        inc k
        l = i
    elif k == 1 and decl.value[i] == cttDelim:
      if CSSToken(decl.value[i]).cvalue == '!':
        decl.important = true
        decl.value.delete(l)
        decl.value.delete(i)
        break
    if j == 2:
      break
  while decl.value.len > 0 and decl.value[^1] == cttWhitespace:
    decl.value.setLen(decl.value.len - 1)
  return some(decl)

# > Note: Despite the name, this actually parses a mixed list of
# > declarations and at-rules, as CSS 2.1 does for @page. Unexpected
# > at-rules (which could be all of them, in a given context) are
# > invalid and should be ignored by the consumer.
#
# Currently we never use nested at-rules, so the result of consumeAtRule
# is just discarded. This should be changed if we ever need nested at
# rules (e.g. add a flag to include at rules).
proc consumeDeclarations(cvals: openArray[CSSComponentValue]):
    seq[CSSDeclaration] =
  var i = 0
  result = @[]
  while i < cvals.len:
    let t = cvals[i]
    inc i
    if t == cttWhitespace or t == cttSemicolon:
      continue
    elif t == cttAtKeyword:
      dec i
      discard cvals.consumeAtRule(i) # see above
    elif t == cttIdent:
      var tempList = @[t]
      while i < cvals.len and cvals[i] != cttSemicolon:
        tempList.add(cvals.consumeComponentValue(i))
      var j = 0
      let decl = tempList.consumeDeclaration(j)
      if decl.isSome:
        result.add(decl.get)
    else:
      dec i
      while i < cvals.len and cvals[i] != cttSemicolon:
        discard cvals.consumeComponentValue(i)

iterator parseListOfRules*(cvals: openArray[CSSComponentValue];
    topLevel: bool): CSSRule {.inline.} =
  var i = 0
  while i < cvals.len:
    let t = cvals[i]
    inc i
    var rule: CSSRule = nil
    if t == cttWhitespace:
      continue
    elif t == cttAtKeyword:
      dec i
      rule = cvals.consumeAtRule(i)
    elif topLevel and (t == cttCdo or t == cttCdc):
      continue
    else:
      dec i
      rule = cvals.consumeQualifiedRule(i).get(nil)
    if rule != nil:
      yield rule

proc parseRule*(iq: openArray[char]): DOMResult[CSSRule] =
  let cvals = tokenizeCSS(iq)
  var i = cvals.skipBlanks(0)
  if i >= cvals.len:
    return errDOMException("Unexpected EOF", "SyntaxError")
  var res = if cvals[i] == cttAtKeyword:
    cvals.consumeAtRule(i)
  elif q := cvals.consumeQualifiedRule(i):
    q
  else:
    return errDOMException("No qualified rule found", "SyntaxError")
  if cvals.skipBlanks(i) < cvals.len:
    return errDOMException("EOF not reached", "SyntaxError")
  return ok(res)

proc parseDeclarations*(iq: openArray[char]): seq[CSSDeclaration] =
  return tokenizeCSS(iq).consumeDeclarations()

proc parseComponentValue*(iq: openArray[char]): DOMResult[CSSComponentValue] =
  let cvals = tokenizeCSS(iq)
  var i = cvals.skipBlanks(0)
  if i >= cvals.len:
    return errDOMException("Unexpected EOF", "SyntaxError")
  let res = cvals.consumeComponentValue(i)
  if cvals.skipBlanks(i) < cvals.len:
    return errDOMException("EOF not reached", "SyntaxError")
  return ok(res)

proc parseComponentValues*(iq: openArray[char]): seq[CSSComponentValue] =
  let cvals = tokenizeCSS(iq)
  result = @[]
  var i = 0
  while i < cvals.len:
    result.add(cvals.consumeComponentValue(i))

proc nextCommaSepComponentValue(cvals: openArray[CSSComponentValue];
    s: var seq[CSSComponentValue]; i: var int): bool =
  s = @[]
  while i < cvals.len:
    let cvl = cvals.consumeComponentValue(i)
    if cvl == cttComma:
      break
    s.add(cvl)
  return s.len > 0

iterator parseCommaSepComponentValues*(cvals: openArray[CSSComponentValue]):
    seq[CSSComponentValue] =
  var i = 0
  var s: seq[CSSComponentValue]
  while cvals.nextCommaSepComponentValue(s, i):
    yield move(s)

type AnBIdent = enum
  abiOdd = "odd"
  abiEven = "even"
  abiN = "n"
  abiDashN = "-n"
  abiNDash = "n-"
  abiDashNDash = "-n-"

proc parseAnB*(cvals: openArray[CSSComponentValue]; i: var int):
    Opt[CSSAnB] =
  template is_eof: bool =
    i >= cvals.len or not (cvals[i] of CSSToken)
  template get_plus: bool =
    let tok = cvals.getToken(i, cttDelim)
    if tok.isOk and tok.get.cvalue == '+':
      inc i
      true
    else:
      false
  template get_tok: CSSToken =
    i = cvals.skipBlanks(i)
    ?cvals.consumeToken(i)
  template fail_plus =
    if isPlus:
      return err()
  template parse_sub_int(s: string; skip: int): int32 =
    ?parseInt32(s.toOpenArray(skip, s.high))
  template fail_non_integer(tok: CSSToken; res: Opt[CSSAnB]) =
    if tok.t != cttINumber:
      dec i
      return res
    if int64(tok.nvalue) > high(int):
      dec i
      return res
  template fail_non_signless_integer(tok: CSSToken; res: Opt[CSSAnB]) =
    fail_non_integer tok, res #TODO check if signless?

  i = cvals.skipBlanks(i)
  if is_eof:
    return err()
  let isPlus = get_plus
  let tok = ?cvals.consumeToken(i)
  case tok.t
  of cttIdent:
    if x := parseEnumNoCase[AnBIdent](tok.value):
      case x
      of abiOdd:
        fail_plus
        return ok((2i32, 1i32))
      of abiEven:
        fail_plus
        return ok((2i32, 0i32))
      of abiN:
        i = cvals.skipBlanks(i)
        if is_eof:
          return ok((1i32, 0i32))
        let tok2 = ?cvals.consumeToken(i)
        if tok2.t == cttDelim:
          let sign = case tok2.cvalue
          of '+': 1i32
          of '-': -1i32
          else: return err()
          let tok3 = get_tok
          fail_non_signless_integer tok3, ok((1i32, 0i32))
          return ok((1i32, sign * int32(tok3.nvalue)))
        else:
          fail_non_integer tok2, ok((1i32, 0i32))
          return ok((1i32, int32(tok2.nvalue)))
      of abiDashN:
        fail_plus
        i = cvals.skipBlanks(i)
        if is_eof:
          return ok((-1i32, 0i32))
        let tok2 = ?cvals.consumeToken(i)
        if tok2.t == cttDelim:
          let sign = case tok2.cvalue
          of '+': 1i32
          of '-': -1i32
          else: return err()
          let tok3 = get_tok
          fail_non_signless_integer tok3, ok((-1i32, 0i32))
          return ok((-1i32, sign * int32(tok3.nvalue)))
        else:
          fail_non_integer tok2, ok((-1i32, 0i32))
          return ok((-1i32, int32(tok2.nvalue)))
      of abiNDash:
        let tok2 = get_tok
        fail_non_signless_integer tok2, err()
        return ok((1i32, -int32(tok2.nvalue)))
      of abiDashNDash:
        fail_plus
        let tok2 = get_tok
        fail_non_signless_integer tok2, err()
        return ok((-1i32, -int32(tok2.nvalue)))
    elif tok.value.startsWithIgnoreCase("n-"):
      return ok((1i32, -parse_sub_int(tok.value, "n-".len)))
    elif tok.value.startsWithIgnoreCase("-n-"):
      fail_plus
      return ok((-1i32, -parse_sub_int(tok.value, "n-".len)))
    else:
      return err()
  of cttINumber:
    fail_plus
    # <integer>
    return ok((0i32, int32(tok.nvalue)))
  of cttIDimension:
    fail_plus
    case tok.unit
    of "n", "N":
      # <n-dimension>
      i = cvals.skipBlanks(i)
      if is_eof:
        return ok((int32(tok.nvalue), 0i32))
      let tok2 = ?cvals.consumeToken(i)
      if tok2.t == cttDelim:
        let sign = case tok2.cvalue
        of '+': 1i32
        of '-': -1i32
        else: return err()
        let tok3 = get_tok
        fail_non_signless_integer tok3, ok((int32(tok.nvalue), 0i32))
        return ok((int32(tok.nvalue), sign * int32(tok3.nvalue)))
      else:
        fail_non_integer tok2, ok((int32(tok.nvalue), 0i32))
        return ok((int32(tok.nvalue), int32(tok2.nvalue)))
    of "n-", "N-":
      # <ndash-dimension>
      let tok2 = get_tok
      fail_non_signless_integer tok2, err()
      return ok((int32(tok.nvalue), -int32(tok2.nvalue)))
    elif tok.unit.startsWithIgnoreCase("n-"):
      # <ndashdigit-dimension>
      return ok((int32(tok.nvalue), -parse_sub_int(tok.unit, "n-".len)))
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
      for fsel in sel.pseudo.fsels:
        result &= $fsel
        if fsel != sel.pseudo.fsels[^1]:
          result &= ", "
      result &= ')'
    of pcNthChild, pcNthLastChild:
      result &= '(' & $sel.pseudo.anb.A & 'n' & $sel.pseudo.anb.B
      if sel.pseudo.ofsels.len != 0:
        result &= " of "
        for fsel in sel.pseudo.ofsels:
          result &= $fsel
          if fsel != sel.pseudo.ofsels[^1]:
            result &= ','
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

proc consume(state: var SelectorParser): CSSComponentValue =
  result = state.cvals[state.at]
  inc state.at

proc has(state: var SelectorParser; i = 0): bool =
  return not state.failed and state.at + i < state.cvals.len

proc peek(state: var SelectorParser; i = 0): CSSComponentValue =
  return state.cvals[state.at + i]

template fail() =
  state.failed = true
  return

template get_tok(cval: CSSComponentValue): CSSToken =
  let c = cval
  if not (c of CSSToken): fail
  CSSToken(c)

# Functions that may contain other selectors, functions, etc.
proc parseRecursiveSelectorFunction(state: var SelectorParser;
    class: PseudoClass; body: seq[CSSComponentValue]; forgiving: bool):
    Selector =
  var fun = Selector(
    t: stPseudoClass,
    pseudo: PseudoData(t: class),
  )
  fun.pseudo.fsels = parseSelectorList(body, nested = true, forgiving)
  if fun.pseudo.fsels.len == 0: fail
  return fun

proc parseNthChild(state: var SelectorParser; cssfunction: CSSFunction;
    data: PseudoData): Selector =
  var data = data
  var i = 0
  var anb = cssfunction.value.parseAnB(i)
  if anb.isErr: fail
  data.anb = anb.get
  var nthchild = Selector(t: stPseudoClass, pseudo: data)
  while i < cssfunction.value.len and cssfunction.value[i] == cttWhitespace:
    inc i
  if i >= cssfunction.value.len:
    return nthchild
  let lasttok = get_tok cssfunction.value[i]
  if lasttok.t != cttIdent or not lasttok.value.equalsIgnoreCase("of"):
    fail
  inc i
  while i < cssfunction.value.len and cssfunction.value[i] == cttWhitespace:
    inc i
  if i == cssfunction.value.len: fail
  nthchild.pseudo.ofsels = cssfunction.value[i..^1]
    .parseSelectorList(nested = true, forgiving = false)
  if nthchild.pseudo.ofsels.len == 0: fail
  return nthchild

proc skipWhitespace(state: var SelectorParser) =
  while state.has() and state.peek() of CSSToken and
      CSSToken(state.peek()).t == cttWhitespace:
    inc state.at

proc parseLang(cvals: seq[CSSComponentValue]): Selector =
  var state = SelectorParser(cvals: cvals)
  state.skipWhitespace()
  if not state.has(): fail
  let tok = get_tok state.consume()
  if tok.t != cttIdent: fail
  return Selector(t: stPseudoClass, pseudo: PseudoData(t: pcLang, s: tok.value))

proc parseSelectorFunction(state: var SelectorParser; cssfunction: CSSFunction):
    Selector =
  return case cssfunction.name
  of cftNot:
    state.parseRecursiveSelectorFunction(pcNot, cssfunction.value,
      forgiving = false)
  of cftIs:
    state.parseRecursiveSelectorFunction(pcIs, cssfunction.value,
      forgiving = true)
  of cftWhere:
    state.parseRecursiveSelectorFunction(pcWhere, cssfunction.value,
      forgiving = true)
  of cftNthChild:
    state.parseNthChild(cssfunction, PseudoData(t: pcNthChild))
  of cftNthLastChild:
    state.parseNthChild(cssfunction, PseudoData(t: pcNthLastChild))
  of cftLang:
    parseLang(cssfunction.value)
  else: fail

proc parsePseudoSelector(state: var SelectorParser): Selector =
  result = nil
  if not state.has(): fail
  let cval = state.consume()
  if cval of CSSToken:
    template add_pseudo_element(element: PseudoElement) =
      state.skipWhitespace()
      if state.nested or state.has() and state.peek() != cttComma: fail
      return Selector(t: stPseudoElement, elem: element)
    let tok = CSSToken(cval)
    case tok.t
    of cttIdent:
      template add_pseudo_class(class: PseudoClass) =
        return Selector(t: stPseudoClass, pseudo: PseudoData(t: class))
      if tok.value.equalsIgnoreCase("before"):
        add_pseudo_element peBefore
      elif tok.value.equalsIgnoreCase("after"):
        add_pseudo_element peAfter
      else:
        let class = parseEnumNoCase[PseudoClass](tok.value)
        if class.isErr: fail
        add_pseudo_class class.get
    of cttColon:
      if not state.has(): fail
      let tok = get_tok state.consume()
      if tok.t != cttIdent: fail
      let x = parseEnumNoCase[PseudoElement](tok.value)
      if x.isErr: fail
      add_pseudo_element x.get
    else: fail
  elif cval of CSSFunction:
    return state.parseSelectorFunction(CSSFunction(cval))
  else: fail

proc parseAttributeSelector(state: var SelectorParser;
    cssblock: CSSSimpleBlock): Selector =
  if cssblock.token.t != cttLbracket: fail
  var state2 = SelectorParser(cvals: cssblock.value)
  state2.skipWhitespace()
  if not state2.has(): fail
  let attr = get_tok state2.consume()
  if attr.t != cttIdent: fail
  state2.skipWhitespace()
  if not state2.has():
    return Selector(
      t: stAttr,
      attr: attr.value.toAtomLower(),
      rel: SelectorRelation(t: rtExists)
    )
  let delim = get_tok state2.consume()
  if delim.t != cttDelim: fail
  let rel = case delim.cvalue
  of '~': rtToken
  of '|': rtBeginDash
  of '^': rtStartsWith
  of '$': rtEndsWith
  of '*': rtContains
  of '=': rtEquals
  else: fail
  if rel != rtEquals:
    let delim = get_tok state2.consume()
    if delim.t != cttDelim or delim.cvalue != '=': fail
  state2.skipWhitespace()
  if not state2.has(): fail
  let value = get_tok state2.consume()
  if value.t notin {cttIdent, cttString}: fail
  state2.skipWhitespace()
  var flag = rfNone
  if state2.has():
    let delim = get_tok state2.consume()
    if delim.t != cttIdent: fail
    if delim.value.equalsIgnoreCase("i"):
      flag = rfI
    elif delim.value.equalsIgnoreCase("s"):
      flag = rfS
  return Selector(
    t: stAttr,
    attr: attr.value.toAtomLower(),
    value: value.value,
    rel: SelectorRelation(t: rel, flag: flag)
  )

proc parseClassSelector(state: var SelectorParser): Selector =
  if not state.has(): fail
  let tok = get_tok state.consume()
  if tok.t != cttIdent: fail
  let class = tok.value.toAtomLower()
  Selector(t: stClass, class: class)

proc parseCompoundSelector(state: var SelectorParser): CompoundSelector =
  result = CompoundSelector()
  while state.has():
    let cval = state.peek()
    if cval of CSSToken:
      let tok = CSSToken(cval)
      case tok.t
      of cttIdent:
        inc state.at
        let tag = tok.value.toAtomLower()
        result.add(Selector(t: stType, tag: tag))
      of cttColon:
        inc state.at
        result.add(state.parsePseudoSelector())
      of cttHash:
        inc state.at
        if not tok.validId:
          fail
        let id = tok.value.toAtomLower()
        result.add(Selector(t: stId, id: id))
      of cttComma: break
      of cttDelim:
        case tok.cvalue
        of '.':
          inc state.at
          result.add(state.parseClassSelector())
        of '*':
          inc state.at
          result.add(Selector(t: stUniversal))
        of '>', '+', '~': break
        else: fail
      of cttWhitespace:
        # skip trailing whitespace
        if not state.has(1) or state.peek(1) == cttComma:
          inc state.at
        elif state.peek(1) == cttDelim:
          let tok = CSSToken(state.peek(1))
          if tok.cvalue in {'>', '+', '~'}:
            inc state.at
        break
      else: fail
    elif cval of CSSSimpleBlock:
      inc state.at
      result.add(state.parseAttributeSelector(CSSSimpleBlock(cval)))
    else:
      fail

proc parseComplexSelector(state: var SelectorParser): ComplexSelector =
  result = ComplexSelector()
  while true:
    state.skipWhitespace()
    let sels = state.parseCompoundSelector()
    if state.failed:
      break
    #TODO propagate from parser
    result.specificity += sels.getSpecificity()
    result.csels.add(sels)
    if sels.len == 0: fail
    if not state.has():
      break # finish
    let tok = get_tok state.consume()
    case tok.t
    of cttDelim:
      case tok.cvalue
      of '>': result[^1].ct = ctChild
      of '+': result[^1].ct = ctNextSibling
      of '~': result[^1].ct = ctSubsequentSibling
      else: fail
    of cttWhitespace:
      result[^1].ct = ctDescendant
    of cttComma:
      break # finish
    else: fail
  if result.len == 0 or result[^1].ct != ctNone:
    fail
  if result[^1][^1].t == stPseudoElement:
    #TODO move pseudo check here?
    result.pseudo = result[^1][^1].elem

proc parseSelectorList(cvals: seq[CSSComponentValue]; nested, forgiving: bool):
    SelectorList =
  var state = SelectorParser(
    cvals: cvals,
    nested: nested
  )
  var res: SelectorList = @[]
  while state.has():
    let csel = state.parseComplexSelector()
    if state.failed:
      if not forgiving:
        return @[]
      state.failed = false
      while state.has() and state.consume() != cttComma:
        discard
    else:
      res.add(csel)
  move(res)

proc parseSelectors*(cvals: seq[CSSComponentValue]): seq[ComplexSelector] =
  return parseSelectorList(cvals, nested = false, forgiving = false)

proc parseSelectors*(ibuf: string): seq[ComplexSelector] =
  return parseSelectors(parseComponentValues(ibuf))

{.pop.} # raises: []
