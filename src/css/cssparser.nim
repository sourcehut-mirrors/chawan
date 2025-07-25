{.push raises: [].}

import std/options

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

  CSSTokenType* = enum
    cttIdent, cttFunctionKeyword, cttAtKeyword, cttHash, cttString,
    cttBadString, cttUrl, cttBadUrl, cttDelim, cttNumber, cttINumber,
    cttPercentage, cttDimension, cttIDimension, cttWhitespace, cttCdo, cttCdc,
    cttColon, cttSemicolon, cttComma, cttRbracket, cttLbracket, cttLparen,
    cttRparen, cttLbrace, cttRbrace, cttFunction, cttSimpleBlock

  CSSTokenFlag = enum
    ctfId, ctfSign

  CSSToken* = object # token or component value
    num*: float32 # for number-like
    flags*: set[CSSTokenFlag]
    c*: char # for cttDelim.  if non-ascii, s contains UTF-8
    case t*: CSSTokenType
    of cttFunction:
      fun*: CSSFunction
    of cttSimpleBlock:
      oblock*: CSSSimpleBlock
    else:
      s*: string # for ident/string-like, and unit of number tokens

  CSSRule* = ref object of RootObj

  CSSAtRuleType* = enum
    cartUnknown = "-cha-unknown"
    cartImport = "import"
    cartMedia = "media"

  CSSAtRule* = ref object of CSSRule
    prelude*: seq[CSSToken]
    name*: CSSAtRuleType
    oblock*: CSSSimpleBlock

  CSSQualifiedRule* = ref object of CSSRule
    sels*: SelectorList
    decls*: seq[CSSDeclaration]

  CSSDeclaration* = ref object
    name*: string
    value*: seq[CSSToken]
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

  CSSFunction* = ref object
    name*: CSSFunctionType
    value*: seq[CSSToken]

  CSSSimpleBlock* = ref object
    t*: CSSTokenType # starting token
    value*: seq[CSSToken]

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
    toks: seq[CSSToken]
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
proc consumeDeclarations(ctx: var CSSParser): seq[CSSDeclaration]
proc consumeComponentValue(ctx: var CSSParser): CSSToken
proc parseSelectors*(toks: seq[CSSToken]): seq[ComplexSelector]
proc parseSelectorList(toks: seq[CSSToken]; nested, forgiving: bool):
  SelectorList
proc parseComplexSelector(state: var SelectorParser): ComplexSelector
proc `$`*(tok: CSSToken): string
proc `$`*(c: CSSRule): string
proc `$`*(decl: CSSDeclaration): string
proc `$`*(c: CSSSimpleBlock): string
func `$`*(slist: SelectorList): string

func isDelim*(tok: CSSToken; c: char): bool =
  return tok.t == cttDelim and tok.c == c

proc `$`*(tok: CSSToken): string =
  case tok.t:
  of cttFunctionKeyword, cttAtKeyword: return $tok.t & tok.s & '\n'
  of cttUrl: return "url(" & tok.s & ")"
  of cttHash: return '#' & tok.s
  of cttIdent: return tok.s
  of cttString: return ("\"" & tok.s & "\"")
  of cttDelim: return if tok.c in Ascii: $tok.c else: tok.s
  of cttDimension, cttNumber: return $tok.num & tok.s
  of cttINumber, cttIDimension: return $int32(tok.num) & tok.s
  of cttPercentage: return $tok.num & "%"
  of cttColon: return ":"
  of cttWhitespace: return " "
  of cttSemicolon: return ";\n"
  of cttComma: return ","
  of cttFunction:
    let fun = tok.fun
    result &= $fun.name & "("
    for s in fun.value:
      result &= $s
    result &= ")"
  else: return $tok.t & '\n'

proc `$`*(decl: CSSDeclaration): string =
  result = decl.name
  result &= ": "
  for s in decl.value:
    result &= $s
  if decl.important:
    result &= " !important"
  result &= ";"

proc `$`*(c: CSSSimpleBlock): string =
  case c.t
  of cttLbrace: result = "{\n"
  of cttLparen: result = "("
  of cttLbracket: result = "["
  else: result = ""
  for s in c.value:
    result &= $s
  case c.t
  of cttLbrace: result &= "\n}"
  of cttLparen: result &= ")"
  of cttLbracket: result &= "]"
  else: discard

proc `$`*(c: CSSRule): string =
  result = ""
  if c of CSSAtRule:
    let c = CSSAtRule(c)
    result &= $c.name & ' '
    result &= $c.prelude & "\n"
    result &= $c.oblock
  else:
    let c = CSSQualifiedRule(c)
    result &= $c.sels & " {\n"
    for decl in c.decls:
      result &= $decl & '\n'
    result &= "}\n"

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
      return CSSToken(t: cttFunctionKeyword, s: move(s))
    return iq.consumeURL(n)
  if n < iq.len and iq[n] == '(':
    inc n
    return CSSToken(t: cttFunctionKeyword, s: move(s))
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
    else:
      dec n
      return iq.consumeDelimToken(n)
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
      return CSSToken(t: cttDelim, c: c)
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
      return CSSToken(t: cttDelim, c: c)
  of '.':
    # starts with a number
    if n < iq.len and iq[n] in AsciiDigit:
      dec n
      return iq.consumeNumericToken(n)
    else:
      return CSSToken(t: cttDelim, c: c)
  of ':': return CSSToken(t: cttColon)
  of ';': return CSSToken(t: cttSemicolon)
  of '<':
    if n + 2 < iq.len and iq[n] == '!' and iq[n + 1] == '-' and
        iq[n + 2] == '-':
      n += 3
      return CSSToken(t: cttCdo)
    else:
      return CSSToken(t: cttDelim, c: c)
  of '@':
    if iq.startsWithIdentSequence(n):
      return CSSToken(t: cttAtKeyword, s: iq.consumeIdentSequence(n))
    else:
      return CSSToken(t: cttDelim, c: c)
  of '[': return CSSToken(t: cttLbracket)
  of '\\':
    if n < iq.len and iq[n] != '\n':
      dec n
      return iq.consumeIdentLikeToken(n)
    else:
      return CSSToken(t: cttDelim, c: c)
  of ']': return CSSToken(t: cttRbracket)
  of AsciiDigit:
    dec n
    return iq.consumeNumericToken(n)
  of IdentStart:
    dec n
    return iq.consumeIdentLikeToken(n)
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

func findBlank*(toks: openArray[CSSToken]; i: int): int =
  var i = i
  while i < toks.len:
    if toks[i].t == cttWhitespace:
      break
    inc i
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

proc peekToken(ctx: var CSSParser): lent CSSToken =
  assert ctx.toks.len == 0
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

func has(ctx: var CSSParser): bool =
  if ctx.iqlen > 0:
    return ctx.hasBuf or ctx.iq.nextToken(ctx.i)
  return ctx.i < ctx.toks.len

proc consumeSimpleBlock(ctx: var CSSParser; start: CSSTokenType):
    CSSSimpleBlock =
  var ending: CSSTokenType
  case start
  of cttLbrace: ending = cttRbrace
  of cttLparen: ending = cttRparen
  of cttLbracket: ending = cttRbracket
  else: doAssert false
  result = CSSSimpleBlock(t: start)
  while ctx.has():
    let t = ctx.peekToken().t
    if t == ending:
      ctx.seekToken()
      break
    elif t in {cttLbrace, cttLbracket, cttLparen}:
      ctx.seekToken()
      result.value.add(CSSToken(
        t: cttSimpleBlock,
        oblock: ctx.consumeSimpleBlock(t)
      ))
    else:
      result.value.add(ctx.consumeComponentValue())

proc peekTokenType(ctx: var CSSParser): CSSTokenType =
  if ctx.iqlen > 0:
    return ctx.peekToken().t
  return ctx.toks[ctx.i].t

proc consumeComponentValue(ctx: var CSSParser): CSSToken =
  if ctx.iqlen == 0:
    var cval = ctx.toks[ctx.i]
    inc ctx.i
    return move(cval)
  case (let t = ctx.peekToken().t; t)
  of cttLbrace, cttLbracket, cttLparen:
    ctx.seekToken()
    return CSSToken(t: cttSimpleBlock, oblock: ctx.consumeSimpleBlock(t))
  of cttFunctionKeyword: # consume function
    let tok = ctx.consumeToken()
    let name = parseEnumNoCase[CSSFunctionType](tok.s).get(cftUnknown)
    let fun = CSSFunction(name: name)
    while ctx.has():
      if ctx.peekToken().t == cttRparen:
        ctx.seekToken()
        break
      fun.value.add(ctx.consumeComponentValue())
    return CSSToken(t: cttFunction, fun: fun)
  else: # preserved token
    return ctx.consumeToken()

proc skipBlanks(ctx: var CSSParser) =
  if ctx.iqlen > 0:
    while ctx.has():
      let tok = ctx.peekToken()
      if tok.t != cttWhitespace:
        break
      ctx.seekToken()
  else:
    ctx.i = ctx.toks.skipBlanks(ctx.i)

proc consumeQualifiedRule(ctx: var CSSParser): Opt[CSSQualifiedRule] =
  var oblock: CSSSimpleBlock = nil
  var r = CSSQualifiedRule()
  var prelude: seq[CSSToken] = @[]
  while ctx.has():
    var tok = ctx.consumeComponentValue()
    if tok.t == cttSimpleBlock and tok.oblock.t == cttLbrace:
      oblock = tok.oblock
      break
    prelude.add(move(tok))
  if oblock != nil:
    r.sels = prelude.parseSelectors()
    var ctx = CSSParser(toks: move(oblock.value))
    r.decls = ctx.consumeDeclarations()
    oblock.value = move(ctx.toks)
    return ok(r)
  err()

proc consumeDeclaration(ctx: var CSSParser): Opt[CSSDeclaration] =
  let tok = ctx.consumeToken()
  let decl = CSSDeclaration(name: tok.s)
  ctx.skipBlanks()
  if not ctx.has():
    return err()
  if ctx.peekTokenType() != cttColon:
    while ctx.has():
      if ctx.peekTokenType() == cttSemicolon:
        ctx.seekToken()
        break
      discard ctx.consumeComponentValue()
    return err()
  ctx.seekToken()
  ctx.skipBlanks()
  var lastTokIdx1 = -1
  var lastTokIdx2 = -1
  while ctx.has():
    case ctx.peekTokenType()
    of cttSemicolon:
      ctx.seekToken()
      break
    of cttWhitespace:
      discard
    else:
      lastTokIdx1 = lastTokIdx2
      lastTokIdx2 = decl.value.len
    decl.value.add(ctx.consumeComponentValue())
  if lastTokIdx1 != -1 and lastTokIdx2 != -1:
    let lastTok1 = decl.value[lastTokIdx1]
    let lastTok2 = decl.value[lastTokIdx2]
    if lastTok1.t == cttDelim and lastTok1.c == '!' and
        lastTok2.t == cttIdent and lastTok2.s.equalsIgnoreCase("important"):
      decl.value.setLen(lastTokIdx1)
      decl.important = true
  while decl.value.len > 0 and decl.value[^1].t == cttWhitespace:
    decl.value.setLen(decl.value.len - 1)
  return ok(decl)

proc consumeAtRule(ctx: var CSSParser): CSSAtRule =
  let tok = ctx.consumeToken()
  let name = parseEnumNoCase[CSSAtRuleType](tok.s).get(cartUnknown)
  result = CSSAtRule(name: name)
  while ctx.has():
    if ctx.peekTokenType() == cttSemicolon:
      ctx.seekToken()
      break
    var tok = ctx.consumeComponentValue()
    if tok.t == cttSimpleBlock and tok.oblock.t == cttLbrace:
      result.oblock = tok.oblock
      break
    result.prelude.add(move(tok))

# > Note: Despite the name, this actually parses a mixed list of
# > declarations and at-rules, as CSS 2.1 does for @page. Unexpected
# > at-rules (which could be all of them, in a given context) are
# > invalid and should be ignored by the consumer.
#
# Currently we never use nested at-rules, so the result of consumeAtRule
# is just discarded. This should be changed if we ever need nested at
# rules (e.g. add a flag to include at rules).
proc consumeDeclarations(ctx: var CSSParser): seq[CSSDeclaration] =
  result = @[]
  while ctx.has():
    case ctx.peekTokenType()
    of cttWhitespace, cttSemicolon:
      ctx.seekToken()
    of cttAtKeyword:
      discard ctx.consumeAtRule() # see above
    of cttIdent:
      if decl := ctx.consumeDeclaration():
        result.add(decl)
    else:
      while ctx.has() and ctx.peekTokenType() != cttSemicolon:
        discard ctx.consumeComponentValue()

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
  return ctx.consumeDeclarations()

proc parseComponentValue*(iq: openArray[char]): DOMResult[CSSToken] =
  var ctx = initCSSParser(iq)
  ctx.skipBlanks()
  if not ctx.has():
    return errDOMException("Unexpected EOF", "SyntaxError")
  let res = ctx.consumeComponentValue()
  ctx.skipBlanks()
  if ctx.has():
    return errDOMException("EOF not reached", "SyntaxError")
  return ok(res)

proc parseComponentValues*(iq: openArray[char]): seq[CSSToken] =
  var ctx = initCSSParser(iq)
  result = @[]
  while ctx.has():
    result.add(ctx.consumeComponentValue())

proc consumeImports*(ctx: var CSSParser): seq[CSSAtRule] =
  result = @[]
  while ctx.has():
    case ctx.peekTokenType()
    of cttWhitespace:
      ctx.seekToken()
    of cttAtKeyword:
      let rule = ctx.consumeAtRule()
      if rule.name != cartImport or rule.oblock != nil:
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

proc consume(toks: openArray[CSSToken]; i: var int): lent CSSToken =
  let j = i
  inc i
  return toks[j]

proc parseAnB(toks: openArray[CSSToken]; i: var int): Opt[CSSAnB] =
  template get_tok: CSSToken =
    i = ?toks.skipBlanksCheckHas(i)
    toks.consume(i)
  template fail_plus =
    if isPlus:
      return err()
  template fail_non_integer(tok: CSSToken; res: Opt[CSSAnB]) =
    if tok.t != cttINumber:
      dec i
      return res
    if int64(tok.num) > high(int):
      dec i
      return res
  template fail_non_signless_integer(tok: CSSToken; res: Opt[CSSAnB]) =
    fail_non_integer tok, res
    if ctfSign in tok.flags:
      return res

  i = ?toks.skipBlanksCheckHas(i)
  var tok = toks.consume(i)
  let isPlus = tok.t == cttDelim and tok.c == '+'
  if isPlus:
    tok = toks.consume(i)
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
        i = toks.skipBlanks(i)
        if i >= toks.len:
          return ok((1i32, 0i32))
        let tok2 = toks.consume(i)
        if tok2.t == cttDelim:
          let sign = case tok2.c
          of '+': 1i32
          of '-': -1i32
          else: return err()
          let tok3 = get_tok
          fail_non_signless_integer tok3, ok((1i32, 0i32))
          return ok((1i32, sign * int32(tok3.num)))
        else:
          fail_non_integer tok2, ok((1i32, 0i32))
          return ok((1i32, int32(tok2.num)))
      of abiDashN:
        fail_plus
        i = toks.skipBlanks(i)
        if i >= toks.len:
          return ok((-1i32, 0i32))
        let tok2 = toks.consume(i)
        if tok2.t == cttDelim:
          let sign = case tok2.c
          of '+': 1i32
          of '-': -1i32
          else: return err()
          let tok3 = get_tok
          fail_non_signless_integer tok3, ok((-1i32, 0i32))
          return ok((-1i32, sign * int32(tok3.num)))
        else:
          fail_non_integer tok2, ok((-1i32, 0i32))
          return ok((-1i32, int32(tok2.num)))
      of abiNDash:
        let tok2 = get_tok
        fail_non_signless_integer tok2, err()
        return ok((1i32, -int32(tok2.num)))
      of abiDashNDash:
        fail_plus
        let tok2 = get_tok
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
      i = toks.skipBlanks(i)
      if i >= toks.len:
        return ok((int32(tok.num), 0i32))
      let tok2 = toks.consume(i)
      if tok2.t == cttDelim:
        let sign = case tok2.c
        of '+': 1i32
        of '-': -1i32
        else: return err()
        let tok3 = get_tok
        fail_non_signless_integer tok3, ok((int32(tok.num), 0i32))
        return ok((int32(tok.num), sign * int32(tok3.num)))
      else:
        fail_non_integer tok2, ok((int32(tok.num), 0i32))
        return ok((int32(tok.num), int32(tok2.num)))
    of "n-", "N-":
      # <ndash-dimension>
      let tok2 = get_tok
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

proc consume(state: var SelectorParser): CSSToken =
  result = move(state.toks[state.at])
  inc state.at

proc has(state: var SelectorParser; i = 0): bool =
  return not state.failed and state.at + i < state.toks.len

proc peek(state: var SelectorParser; i = 0): lent CSSToken =
  return state.toks[state.at + i]

template fail() =
  state.failed = true
  return

# Functions that may contain other selectors, functions, etc.
proc parseRecursiveSelectorFunction(state: var SelectorParser;
    class: PseudoClass; body: seq[CSSToken]; forgiving: bool):
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
  i = cssfunction.value.skipBlanks(i)
  if i >= cssfunction.value.len:
    return nthchild
  let lasttok = cssfunction.value[i]
  if lasttok.t != cttIdent or not lasttok.s.equalsIgnoreCase("of"):
    fail
  i = cssfunction.value.skipBlanks(i + 1)
  if i == cssfunction.value.len: fail
  nthchild.pseudo.ofsels = cssfunction.value[i..^1]
    .parseSelectorList(nested = true, forgiving = false)
  if nthchild.pseudo.ofsels.len == 0: fail
  return nthchild

proc skipWhitespace(state: var SelectorParser) =
  while state.has() and state.peek().t == cttWhitespace:
    inc state.at

proc parseLang(toks: seq[CSSToken]): Selector =
  var state = SelectorParser(toks: toks)
  state.skipWhitespace()
  if not state.has(): fail
  let tok = state.consume()
  if tok.t != cttIdent: fail
  return Selector(t: stPseudoClass, pseudo: PseudoData(t: pcLang, s: tok.s))

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
  let tok = state.consume()
  template add_pseudo_element(element: PseudoElement) =
    state.skipWhitespace()
    if state.nested or state.has() and state.peek().t != cttComma: fail
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
    return state.parseSelectorFunction(tok.fun)
  else: fail

proc parseAttributeSelector(state: var SelectorParser;
    cssblock: CSSSimpleBlock): Selector =
  if cssblock.t != cttLbracket: fail
  var state2 = SelectorParser(toks: cssblock.value)
  state2.skipWhitespace()
  if not state2.has(): fail
  let attr = state2.consume()
  if attr.t != cttIdent: fail
  state2.skipWhitespace()
  if not state2.has():
    return Selector(
      t: stAttr,
      attr: attr.s.toAtomLower(),
      rel: SelectorRelation(t: rtExists)
    )
  let delim = state2.consume()
  if delim.t != cttDelim: fail
  let rel = case delim.c
  of '~': rtToken
  of '|': rtBeginDash
  of '^': rtStartsWith
  of '$': rtEndsWith
  of '*': rtContains
  of '=': rtEquals
  else: fail
  if rel != rtEquals:
    let delim = state2.consume()
    if delim.t != cttDelim or delim.c != '=': fail
  state2.skipWhitespace()
  if not state2.has(): fail
  let value = state2.consume()
  if value.t notin {cttIdent, cttString}: fail
  state2.skipWhitespace()
  var flag = rfNone
  if state2.has():
    let delim = state2.consume()
    if delim.t != cttIdent: fail
    if delim.s.equalsIgnoreCase("i"):
      flag = rfI
    elif delim.s.equalsIgnoreCase("s"):
      flag = rfS
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
    let tok = state.peek()
    case tok.t
    of cttIdent:
      inc state.at
      let tag = tok.s.toAtomLower()
      result.add(Selector(t: stType, tag: tag))
    of cttColon:
      inc state.at
      result.add(state.parsePseudoSelector())
    of cttHash:
      inc state.at
      if ctfId notin tok.flags:
        fail
      let id = tok.s.toAtomLower()
      result.add(Selector(t: stId, id: id))
    of cttComma: break
    of cttDelim:
      case tok.c
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
      if not state.has(1) or state.peek(1).t == cttComma:
        inc state.at
      elif state.peek(1).t == cttDelim:
        let tok = state.peek(1)
        if tok.c in {'>', '+', '~'}:
          inc state.at
      break
    of cttSimpleBlock:
      inc state.at
      result.add(state.parseAttributeSelector(tok.oblock))
    else: fail

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
    let tok = state.consume()
    case tok.t
    of cttDelim:
      case tok.c
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

proc parseSelectorList(toks: seq[CSSToken]; nested, forgiving: bool):
    SelectorList =
  var state = SelectorParser(
    toks: toks,
    nested: nested
  )
  var res: SelectorList = @[]
  while state.has():
    let csel = state.parseComplexSelector()
    if state.failed:
      if not forgiving:
        return @[]
      state.failed = false
      while state.has() and state.consume().t != cttComma:
        discard
    else:
      res.add(csel)
  move(res)

proc parseSelectors*(toks: seq[CSSToken]): seq[ComplexSelector] =
  return parseSelectorList(toks, nested = false, forgiving = false)

proc parseSelectors*(ibuf: string): seq[ComplexSelector] =
  return parseSelectors(parseComponentValues(ibuf))

{.pop.} # raises: []
