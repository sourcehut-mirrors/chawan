import std/options

import html/domexception
import types/opt
import utils/twtstr

type
  CSSTokenType* = enum
    cttIdent, cttFunction, cttAtKeyword, cttHash, cttString, cttBadString,
    cttUrl, cttBadUrl, cttDelim, cttNumber, cttPercentage, cttDimension,
    cttWhitespace, cttCdo, cttCdc, cttColon, cttSemicolon, cttComma,
    cttRbracket, cttLbracket, cttLparen, cttRparen, cttLbrace, cttRbrace

  CSSTokenizerState = object
    at: int
    buf: string
    curr: char

  CSSParseState = object
    tokens: seq[CSSParsedItem]
    at: int

  tflaga = enum
    tflagaUnrestricted, tflagaId

  tflagb* = enum
    tflagbInteger, tflagbNumber

  CSSParsedItem* = ref object of RootObj
  CSSComponentValue* = ref object of CSSParsedItem

  CSSToken* = ref object of CSSComponentValue
    case t*: CSSTokenType
    of cttIdent, cttFunction, cttAtKeyword, cttHash, cttString, cttUrl:
      value*: string
      tflaga*: tflaga
    of cttDelim:
      cvalue*: char
    of cttNumber, cttPercentage, cttDimension:
      nvalue*: float64
      tflagb*: tflagb
      unit*: string
    else: discard

  CSSRule* = ref object of CSSParsedItem
    prelude*: seq[CSSComponentValue]
    oblock*: CSSSimpleBlock

  CSSAtRule* = ref object of CSSRule
    name*: string

  CSSQualifiedRule* = ref object of CSSRule

  CSSDeclaration* = ref object of CSSComponentValue
    name*: string
    value*: seq[CSSComponentValue]
    important*: bool

  CSSFunction* = ref object of CSSComponentValue
    name*: string
    value*: seq[CSSComponentValue]

  CSSSimpleBlock* = ref object of CSSComponentValue
    token*: CSSToken
    value*: seq[CSSComponentValue]

  CSSRawStylesheet* = object
    value*: seq[CSSRule]

  CSSAnB* = tuple[A, B: int]

# For debugging
proc `$`*(c: CSSParsedItem): string =
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
    of cttDimension:
      case c.tflagb
      of tflagbNumber:
        result &= $c.nvalue & c.unit
      of tflagbInteger:
        result &= $int64(c.nvalue) & c.unit
    of cttNumber:
      result &= $c.nvalue & c.unit
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
    result &= ";\n"
  elif c of CSSFunction:
    result &= CSSFunction(c).name & "("
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
      result &= CSSAtRule(c).name & " "
    result &= $CSSRule(c).prelude & "\n"
    result &= $CSSRule(c).oblock

func `==`*(a: CSSParsedItem, b: CSSTokenType): bool =
  return a of CSSToken and CSSToken(a).t == b

const IdentStart = AsciiAlpha + NonAscii + {'_'}
const Ident = IdentStart + AsciiDigit + {'-'}

proc consume(state: var CSSTokenizerState): char =
  state.curr = state.buf[state.at]
  inc state.at
  return state.curr

proc seek(state: var CSSTokenizerState; n: int) =
  state.at += n

proc consumeRChar(state: var CSSTokenizerState): char =
  let u = state.buf.nextUTF8(state.at)
  if u < 0x80:
    return char(u)
  return char(128)

proc reconsume(state: var CSSTokenizerState) =
  dec state.at

func peek(state: CSSTokenizerState; i: int = 0): char =
  return state.buf[state.at + i]

proc has(state: var CSSTokenizerState; i: int = 0): bool =
  return state.at + i < state.buf.len

proc isValidEscape(a, b: char): bool =
  return a == '\\' and b != '\n'

proc isValidEscape(state: var CSSTokenizerState): bool =
  return state.has() and isValidEscape(state.curr, state.peek())

# current + next + next(1)
proc startsWithIdentSequence(state: var CSSTokenizerState): bool =
  case state.curr
  of '-':
    return state.has() and state.peek() in IdentStart + {'-'} or
      state.has(1) and state.isValidEscape()
  of IdentStart:
    return true
  of '\\':
    return state.isValidEscape()
  else:
    return false

# next, next(1), next(2)
proc next3startsWithIdentSequence(state: var CSSTokenizerState): bool =
  if not state.has():
    return false
  case state.peek()
  of '-':
    return state.has(1) and state.peek(1) in IdentStart + {'-'} or
      state.has(2) and isValidEscape(state.peek(1), state.peek(2))
  of IdentStart:
    return true
  of '\\':
    return state.has(1) and isValidEscape(state.peek(), state.peek(1))
  else:
    return false

proc startsWithNumber(state: var CSSTokenizerState): bool =
  if state.has():
    case state.peek()
    of '+', '-':
      if state.has(1):
        if state.peek(1) in AsciiDigit:
          return true
        elif state.peek(1) == '.':
          if state.has(2) and state.peek(2) in AsciiDigit:
            return true
    of '.':
      if state.has(1) and state.peek(1) in AsciiDigit:
        return true
    elif state.peek() in AsciiDigit:
      return true
    else:
      return false
  return false

proc skipWhitespace(state: var CSSTokenizerState) =
  while state.has() and state.peek() in AsciiWhitespace:
    state.seek(1)

proc consumeEscape(state: var CSSTokenizerState): string =
  if not state.has():
    return "\uFFFD"
  let c = state.consume()
  if c in AsciiHexDigit:
    var num = uint32(hexValue(c))
    var i = 0
    while i <= 5 and state.has():
      let c = state.consume()
      if hexValue(c) == -1:
        state.reconsume()
        break
      num *= 0x10
      num += uint32(hexValue(c))
      inc i
    if state.has() and state.peek() in AsciiWhitespace:
      state.seek(1)
    if num == 0 or num > 0x10FFFF or num in 0xD800u32..0xDFFFu32:
      return "\uFFFD"
    else:
      return num.toUTF8()
  else:
    return $c #NOTE this assumes the caller doesn't care about non-ascii

proc consumeString(state: var CSSTokenizerState): CSSToken =
  var s = ""
  let ending = state.curr
  while state.has():
    let c = state.consume()
    case c
    of '\n':
      state.reconsume()
      return CSSToken(t: cttBadString)
    of '\\':
      if not state.has():
        continue
      elif state.peek() == '\n':
        state.seek(1)
      else:
        s &= consumeEscape(state)
    elif c == ending:
      break
    else:
      s &= c
  return CSSToken(t: cttString, value: s)

proc consumeIdentSequence(state: var CSSTokenizerState): string =
  var s = ""
  while state.has():
    let c = state.consume()
    if state.isValidEscape():
      s &= state.consumeEscape()
    elif c in Ident:
      s &= c
    else:
      state.reconsume()
      break
  return s

proc consumeNumber(state: var CSSTokenizerState): (tflagb, float64) =
  var t = tflagbInteger
  var repr = ""
  if state.has() and state.peek() in {'+', '-'}:
    repr &= state.consume()
  while state.has() and state.peek() in AsciiDigit:
    repr &= state.consume()
  if state.has(1) and state.peek() == '.' and state.peek(1) in AsciiDigit:
    repr &= state.consume()
    repr &= state.consume()
    t = tflagbNumber
    while state.has() and state.peek() in AsciiDigit:
      repr &= state.consume()
  if state.has(1) and state.peek() in {'E', 'e'} and
        state.peek(1) in AsciiDigit or
      state.has(2) and state.peek() in {'E', 'e'} and
        state.peek(1) in {'-', '+'} and state.peek(2) in AsciiDigit:
    repr &= state.consume()
    if state.peek() in {'-', '+'}:
      repr &= state.consume()
      repr &= state.consume()
    else:
      repr &= state.consume()
    t = tflagbNumber
    while state.has() and state.peek() in AsciiDigit:
      repr &= state.consume()
  let val = parseFloat64(repr)
  return (t, val)

proc consumeNumericToken(state: var CSSTokenizerState): CSSToken =
  let (t, val) = state.consumeNumber()
  if state.next3startsWithIdentSequence():
    return CSSToken(
      t: cttDimension,
      nvalue: val,
      tflagb: t,
      unit: state.consumeIdentSequence()
    )
  if state.has() and state.peek() == '%':
    state.seek(1)
    return CSSToken(t: cttPercentage, nvalue: val)
  return CSSToken(t: cttNumber, nvalue: val, tflagb: t)

proc consumeBadURL(state: var CSSTokenizerState) =
  while state.has():
    case state.consume()
    of ')':
      return
    elif state.isValidEscape():
      discard state.consumeEscape()
    else: discard

const NonPrintable = {
  '\0'..char(0x08), '\v', char(0x0E)..char(0x1F), char(0x7F)
}

proc consumeURL(state: var CSSTokenizerState): CSSToken =
  let res = CSSToken(t: cttUrl)
  state.skipWhitespace()
  while state.has():
    let c = state.consume()
    case c
    of ')':
      return res
    of '"', '\'', '(', NonPrintable:
      state.consumeBadURL()
      return CSSToken(t: cttBadUrl)
    of AsciiWhitespace:
      state.skipWhitespace()
      if not state.has():
        return res
      if state.peek() == ')':
        state.seek(1)
        return res
      state.consumeBadURL()
      return CSSToken(t: cttBadUrl)
    of '\\':
      state.reconsume()
      if state.isValidEscape():
        res.value &= state.consumeEscape()
      else:
        state.consumeBadURL()
        return CSSToken(t: cttBadUrl)
    else:
      res.value &= c
  return res

proc consumeIdentLikeToken(state: var CSSTokenizerState): CSSToken =
  let s = state.consumeIdentSequence()
  if s.equalsIgnoreCase("url") and state.has() and state.peek() == '(':
    state.seek(1)
    while state.has(1) and state.peek() in AsciiWhitespace and
        state.peek(1) in AsciiWhitespace:
      state.seek(1)
    if state.has() and state.peek() in {'"', '\''} or
        state.has(1) and state.peek() in {'"', '\''} + AsciiWhitespace and
        state.peek(1) in {'"', '\''}:
      return CSSToken(t: cttFunction, value: s)
    return state.consumeURL()
  if state.has() and state.peek() == '(':
    state.seek(1)
    return CSSToken(t: cttFunction, value: s)
  return CSSToken(t: cttIdent, value: s)

proc consumeComments(state: var CSSTokenizerState) =
  if state.has(1) and state.peek() == '/' and state.peek(1) == '*':
    state.seek(2)
    while state.has() and not (state.has(1) and state.peek() == '*' and
        state.peek(1) == '/'):
      state.seek(1)
    if state.has(1):
      state.seek(1)
    if state.has():
      state.seek(1)

proc consumeToken(state: var CSSTokenizerState): CSSToken =
  let c = state.consume()
  case c
  of AsciiWhitespace:
    state.skipWhitespace()
    return CSSToken(t: cttWhitespace)
  of '"', '\'':
    return consumeString(state)
  of '#':
    if state.has() and state.peek() in Ident or state.isValidEscape():
      result = CSSToken(t: cttHash)
      if state.startsWithIdentSequence():
        result.tflaga = tflagaId
      result.value = consumeIdentSequence(state)
    else:
      state.reconsume()
      return CSSToken(t: cttDelim, cvalue: state.consumeRChar())
  of '(': return CSSToken(t: cttLparen)
  of ')': return CSSToken(t: cttRparen)
  of '{': return CSSToken(t: cttLbrace)
  of '}': return CSSToken(t: cttRbrace)
  of '+':
    if state.startsWithNumber():
      state.reconsume()
      return state.consumeNumericToken()
    else:
      return CSSToken(t: cttDelim, cvalue: c)
  of ',': return CSSToken(t: cttComma)
  of '-':
    if state.startsWithNumber():
      state.reconsume()
      return state.consumeNumericToken()
    else:
      if state.has(1) and state.peek() == '-' and state.peek(1) == '>':
        state.seek(2)
        return CSSToken(t: cttCdc)
      elif state.startsWithIdentSequence():
        state.reconsume()
        return state.consumeIdentLikeToken()
      else:
        return CSSToken(t: cttDelim, cvalue: c)
  of '.':
    if state.startsWithNumber():
      state.reconsume()
      return state.consumeNumericToken()
    else:
      return CSSToken(t: cttDelim, cvalue: c)
  of ':': return CSSToken(t: cttColon)
  of ';': return CSSToken(t: cttSemicolon)
  of '<':
    if state.has(2) and state.peek() == '!' and state.peek(1) == '-' and
        state.peek(2) == '-':
      state.seek(3)
      return CSSToken(t: cttCdo)
    else:
      return CSSToken(t: cttDelim, cvalue: c)
  of '@':
    if state.next3startsWithIdentSequence():
      let name = state.consumeIdentSequence()
      return CSSToken(t: cttAtKeyword, value: name)
    else:
      return CSSToken(t: cttDelim, cvalue: c)
  of '[': return CSSToken(t: cttLbracket)
  of '\\':
    if state.isValidEscape():
      state.reconsume()
      return state.consumeIdentLikeToken()
    else:
      return CSSToken(t: cttDelim, cvalue: c)
  of ']': return CSSToken(t: cttRbracket)
  of AsciiDigit:
    state.reconsume()
    return state.consumeNumericToken()
  of IdentStart:
    state.reconsume()
    return state.consumeIdentLikeToken()
  else:
    state.reconsume()
    return CSSToken(t: cttDelim, cvalue: state.consumeRChar())

proc tokenizeCSS*(ibuf: string): seq[CSSParsedItem] =
  result = @[]
  var state = CSSTokenizerState(buf: ibuf)
  while state.has():
    state.consumeComments()
    if state.has():
      result.add(state.consumeToken())

proc consume(state: var CSSParseState): CSSParsedItem =
  result = state.tokens[state.at]
  inc state.at

proc reconsume(state: var CSSParseState) =
  dec state.at

func has(state: CSSParseState; i: int = 0): bool =
  return state.at + i < state.tokens.len

func peek(state: CSSParseState): CSSParsedItem =
  return state.tokens[state.at]

proc skipWhitespace(state: var CSSParseState) =
  while state.has() and state.peek() == cttWhitespace:
    discard state.consume()

proc consumeComponentValue(state: var CSSParseState): CSSComponentValue

proc consumeSimpleBlock(state: var CSSParseState; tok: CSSToken):
    CSSSimpleBlock =
  var ending: CSSTokenType
  case tok.t
  of cttLbrace: ending = cttRbrace
  of cttLparen: ending = cttRparen
  of cttLbracket: ending = cttRbracket
  else: doAssert false
  result = CSSSimpleBlock(token: tok)
  while state.at < state.tokens.len:
    let tok = state.consume()
    if tok == ending:
      break
    elif tok == cttLbrace or tok == cttLbracket or tok == cttLparen:
      result.value.add(state.consumeSimpleBlock(CSSToken(tok)))
    else:
      state.reconsume()
      result.value.add(state.consumeComponentValue())

proc consumeFunction(state: var CSSParseState): CSSFunction =
  let t = CSSToken(state.consume())
  let res = CSSFunction(name: t.value)
  while state.at < state.tokens.len:
    let t = state.consume()
    if t == cttRparen:
      break
    state.reconsume()
    res.value.add(state.consumeComponentValue())
  return res

proc consumeComponentValue(state: var CSSParseState): CSSComponentValue =
  let t = state.consume()
  if t == cttLbrace or t == cttLbracket or t == cttLparen:
    return state.consumeSimpleBlock(CSSToken(t))
  elif t == cttFunction:
    state.reconsume()
    return state.consumeFunction()
  return CSSComponentValue(t)

proc consumeQualifiedRule(state: var CSSParseState): Option[CSSQualifiedRule] =
  var r = CSSQualifiedRule()
  while state.has():
    let t = state.consume()
    if t of CSSSimpleBlock and CSSSimpleBlock(t).token == cttLbrace:
      r.oblock = CSSSimpleBlock(t)
      return some(r)
    elif t == cttLbrace:
      r.oblock = state.consumeSimpleBlock(CSSToken(t))
      return some(r)
    else:
      state.reconsume()
      r.prelude.add(state.consumeComponentValue())
  return none(CSSQualifiedRule)

proc consumeAtRule(state: var CSSParseState): CSSAtRule =
  let t = CSSToken(state.consume())
  result = CSSAtRule(name: t.value)
  while state.at < state.tokens.len:
    let t = state.consume()
    if t of CSSSimpleBlock:
      result.oblock = CSSSimpleBlock(t)
      break
    elif t == cttSemicolon:
      break
    elif t == cttLbrace:
      result.oblock = state.consumeSimpleBlock(CSSToken(t))
      break
    else:
      state.reconsume()
      result.prelude.add(state.consumeComponentValue())

proc consumeDeclaration(state: var CSSParseState): Option[CSSDeclaration] =
  let t = CSSToken(state.consume())
  var decl = CSSDeclaration(name: t.value)
  state.skipWhitespace()
  if not state.has() or state.peek() != cttColon:
    return none(CSSDeclaration)
  discard state.consume()
  state.skipWhitespace()
  while state.has():
    decl.value.add(state.consumeComponentValue())
  var i = decl.value.len - 1
  var j = 2
  var k = 0
  var l = 0
  while i >= 0 and j > 0:
    if decl.value[i] != cttWhitespace:
      dec j
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
    dec i
  while decl.value.len > 0 and decl.value[^1] == cttWhitespace:
    decl.value.setLen(decl.value.len - 1)
  return some(decl)

#> Note: Despite the name, this actually parses a mixed list of declarations
#> and at-rules, as CSS 2.1 does for @page. Unexpected at-rules (which could be
#> all of them, in a given context) are invalid and should be ignored by the
#> consumer.
#So we have two versions, one with at rules and one without.
proc consumeDeclarations(state: var CSSParseState): seq[CSSParsedItem] =
  while state.has():
    let t = state.consume()
    if t == cttWhitespace or t == cttSemicolon:
      continue
    elif t == cttAtKeyword:
      state.reconsume()
      result.add(state.consumeAtRule())
    elif t == cttIdent:
      var tempList: seq[CSSParsedItem]
      tempList.add(CSSToken(t))
      while state.has() and state.peek() != cttSemicolon:
        tempList.add(state.consumeComponentValue())
      var tempState = CSSParseState(at: 0, tokens: tempList)
      let decl = tempState.consumeDeclaration()
      if decl.isSome:
        result.add(decl.get)
    else:
      state.reconsume()
      if state.peek() != cttSemicolon:
        discard state.consumeComponentValue()

proc consumeDeclarations2(state: var CSSParseState): seq[CSSDeclaration] =
  result = @[]
  while state.has():
    let t = state.consume()
    if t == cttWhitespace or t == cttSemicolon:
      continue
    elif t == cttAtKeyword:
      state.reconsume()
      discard state.consumeAtRule()
    elif t == cttIdent:
      var tempList: seq[CSSParsedItem] = @[]
      let tok = CSSToken(t)
      tempList.add(tok)
      while state.has() and state.peek() != cttSemicolon:
        tempList.add(state.consumeComponentValue())
      var tempState = CSSParseState(at: 0, tokens: tempList)
      let decl = tempState.consumeDeclaration()
      if decl.isSome:
        result.add(decl.get)
    else:
      state.reconsume()
      while state.has() and state.peek() != cttSemicolon:
        discard state.consumeComponentValue()

proc consumeListOfRules(state: var CSSParseState; topLevel = false):
    seq[CSSRule] =
  while state.at < state.tokens.len:
    let t = state.consume()
    if t == cttWhitespace:
      continue
    elif t == cttCdo or t == cttCdc:
      if topLevel:
        continue
      state.reconsume()
      let q = state.consumeQualifiedRule()
      if q.isSome:
        result.add(q.get)
    elif t == cttAtKeyword:
      state.reconsume()
      result.add(state.consumeAtRule())
    else:
      state.reconsume()
      let q = state.consumeQualifiedRule()
      if q.isSome:
        result.add(q.get)

proc parseStylesheet(state: var CSSParseState): CSSRawStylesheet =
  return CSSRawStylesheet(value: state.consumeListOfRules(true))

proc parseStylesheet*(ibuf: string): CSSRawStylesheet =
  var state = CSSParseState()
  state.tokens = tokenizeCSS(ibuf)
  return state.parseStylesheet()

proc parseListOfRules(state: var CSSParseState): seq[CSSRule] =
  return state.consumeListOfRules()

proc parseListOfRules*(cvals: seq[CSSComponentValue]): seq[CSSRule] =
  var state = CSSParseState()
  state.tokens = cast[seq[CSSParsedItem]](cvals)
  return state.parseListOfRules()

proc parseRule(state: var CSSParseState): DOMResult[CSSRule] =
  state.skipWhitespace()
  if not state.has():
    return errDOMException("Unexpected EOF", "SyntaxError")
  var res = if state.peek() == cttAtKeyword:
    state.consumeAtRule()
  else:
    let q = state.consumeQualifiedRule()
    if q.isNone:
      return errDOMException("No qualified rule found!", "SyntaxError")
    q.get
  state.skipWhitespace()
  if state.has():
    return errDOMException("EOF not reached", "SyntaxError")
  return ok(res)

proc parseRule*(ibuf: string): DOMResult[CSSRule] =
  var state = CSSParseState()
  state.tokens = tokenizeCSS(ibuf)
  return state.parseRule()

proc parseDeclaration(state: var CSSParseState): DOMResult[CSSDeclaration] =
  state.skipWhitespace()
  if not state.has() or state.peek() != cttIdent:
    return errDOMException("No ident token found", "SyntaxError")
  let d = state.consumeDeclaration()
  if d.isSome:
    return ok(d.get)
  return errDOMException("No declaration found", "SyntaxError")

proc parseDeclaration*(ibuf: string): DOMResult[CSSDeclaration] =
  var state = CSSParseState()
  state.tokens = tokenizeCSS(ibuf)
  return state.parseDeclaration()

proc parseDeclarations(state: var CSSParseState): seq[CSSParsedItem] =
  return state.consumeDeclarations()

proc parseDeclarations*(cvals: seq[CSSComponentValue]):
    seq[CSSParsedItem] =
  var state = CSSParseState(tokens: cast[seq[CSSParsedItem]](cvals))
  return state.consumeDeclarations()

proc parseDeclarations*(ibuf: string): seq[CSSParsedItem] =
  var state = CSSParseState()
  state.tokens = tokenizeCSS(ibuf)
  return state.parseDeclarations()

proc parseDeclarations2(state: var CSSParseState): seq[CSSDeclaration] =
  return state.consumeDeclarations2()

proc parseDeclarations2*(cvals: seq[CSSComponentValue]):
    seq[CSSDeclaration] =
  var state = CSSParseState(tokens: cast[seq[CSSParsedItem]](cvals))
  return state.consumeDeclarations2()

proc parseDeclarations2*(ibuf: string): seq[CSSDeclaration] =
  var state = CSSParseState(tokens: tokenizeCSS(ibuf))
  return state.parseDeclarations2()

proc parseComponentValue(state: var CSSParseState):
    DOMResult[CSSComponentValue] =
  state.skipWhitespace()
  if not state.has():
    return errDOMException("Unexpected EOF", "SyntaxError")
  let res = state.consumeComponentValue()
  state.skipWhitespace()
  if state.has():
    return errDOMException("EOF not reached", "SyntaxError")
  return ok(res)

proc parseComponentValue*(ibuf: string): DOMResult[CSSComponentValue] =
  var state = CSSParseState(tokens: tokenizeCSS(ibuf))
  return state.parseComponentValue()

proc parseComponentValues(state: var CSSParseState): seq[CSSComponentValue] =
  result = @[]
  while state.has():
    result.add(state.consumeComponentValue())

proc parseComponentValues*(ibuf: string): seq[CSSComponentValue] =
  var state = CSSParseState(tokens: tokenizeCSS(ibuf))
  return state.parseComponentValues()

proc parseCommaSepComponentValues(state: var CSSParseState):
    seq[seq[CSSComponentValue]] =
  result = @[]
  if state.has():
    result.add(newSeq[CSSComponentValue]())
  while state.has():
    let cvl = state.consumeComponentValue()
    if cvl != cttComma:
      result[^1].add(cvl)
    else:
      result.add(newSeq[CSSComponentValue]())

proc parseCommaSepComponentValues*(cvals: seq[CSSComponentValue]):
    seq[seq[CSSComponentValue]] =
  var state = CSSParseState(tokens: cast[seq[CSSParsedItem]](cvals))
  return state.parseCommaSepComponentValues()

proc parseAnB*(state: var CSSParseState): Option[CSSAnB] =
  template is_eof: bool =
    not state.has() or not (state.peek() of CSSToken)
  template fail_eof =
    if is_eof:
      return none(CSSAnB)
  template get_plus: bool =
    let tok = state.peek()
    if tok == cttDelim and CSSToken(tok).cvalue == '+':
      discard state.consume()
      true
    else:
      false
  template get_tok: CSSToken =
    state.skipWhitespace()
    fail_eof
    CSSToken(state.consume())
  template get_tok_nows: CSSToken =
    fail_eof
    CSSToken(state.consume())
  template fail_plus =
    if is_plus:
      return none(CSSAnB)
  template parse_sub_int(sub: string; skip: int): int =
    let s = sub.substr(skip)
    let x = parseInt32(s)
    if x.isNone:
      return none(CSSAnB)
    x.get
  template fail_non_integer(tok: CSSToken; res: Option[CSSAnB]) =
    if tok.t != cttNumber:
      state.reconsume()
      return res
    if tok.tflagb != tflagbInteger:
      state.reconsume()
      return res
    if int64(tok.nvalue) > high(int):
      state.reconsume()
      return res
  template fail_non_signless_integer(tok: CSSToken; res: Option[CSSAnB]) =
    fail_non_integer tok, res #TODO check if signless?

  fail_eof
  state.skipWhitespace()
  fail_eof
  let is_plus = get_plus
  let tok = get_tok_nows
  case tok.t
  of cttIdent:
    case tok.value
    of "odd":
      fail_plus
      return some((2, 1))
    of "even":
      fail_plus
      return some((2, 0))
    of "n", "N":
      state.skipWhitespace()
      if is_eof:
        return some((1, 0))
      let tok2 = get_tok_nows
      if tok2.t == cttDelim:
        let sign = case tok2.cvalue
        of '+': 1
        of '-': -1
        else: return none(CSSAnB)
        let tok3 = get_tok
        fail_non_signless_integer tok3, some((1, 0))
        return some((1, sign * int(tok3.nvalue)))
      else:
        fail_non_integer tok2, some((1, 0))
        return some((1, int(tok2.nvalue)))
    of "-n", "-N":
      fail_plus
      state.skipWhitespace()
      if is_eof:
        return some((-1, 0))
      let tok2 = get_tok_nows
      if tok2.t == cttDelim:
        let sign = case tok2.cvalue
        of '+': 1
        of '-': -1
        else: return none(CSSAnB)
        let tok3 = get_tok
        fail_non_signless_integer tok3, some((-1, 0))
        return some((-1, sign * int(tok3.nvalue)))
      else:
        fail_non_integer tok2, some((-1, 0))
        return some((-1, int(tok2.nvalue)))
    of "n-", "N-":
      let tok2 = get_tok
      fail_non_signless_integer tok2, none(CSSAnB)
      return some((1, -int(tok2.nvalue)))
    of "-n-", "-N-":
      fail_plus
      let tok2 = get_tok
      fail_non_signless_integer tok2, none(CSSAnB)
      return some((-1, -int(tok2.nvalue)))
    elif tok.value.startsWithIgnoreCase("n-"):
      return some((1, -parse_sub_int(tok.value, "n-".len)))
    elif tok.value.startsWithIgnoreCase("-n-"):
      fail_plus
      return some((-1, -parse_sub_int(tok.value, "n-".len)))
    else:
      return none(CSSAnB)
  of cttNumber:
    fail_plus
    if tok.tflagb != tflagbInteger:
      return none(CSSAnB)
    if int64(tok.nvalue) > high(int):
      return none(CSSAnB)
    # <integer>
    return some((0, int(tok.nvalue)))
  of cttDimension:
    fail_plus
    if int64(tok.nvalue) > high(int):
      return none(CSSAnB)
    if tok.tflagb != tflagbInteger:
      return none(CSSAnB)
    case tok.unit
    of "n", "N":
      # <n-dimension>
      state.skipWhitespace()
      if is_eof:
        return some((int(tok.nvalue), 0))
      let tok2 = get_tok_nows
      if tok2.t == cttDelim:
        let sign = case tok2.cvalue
        of '+': 1
        of '-': -1
        else: return none(CSSAnB)
        let tok3 = get_tok
        fail_non_signless_integer tok3, some((int(tok.nvalue), 0))
        return some((int(tok.nvalue), sign * int(tok3.nvalue)))
      else:
        fail_non_integer tok2, some((int(tok.nvalue), 0))
        return some((int(tok.nvalue), int(tok2.nvalue)))
    of "n-", "N-":
      # <ndash-dimension>
      let tok2 = get_tok
      fail_non_signless_integer tok2, none(CSSAnB)
      return some((int(tok.nvalue), -int(tok2.nvalue)))
    elif tok.unit.startsWithIgnoreCase("n-"):
      # <ndashdigit-dimension>
      return some((int(tok.nvalue), -parse_sub_int(tok.unit, "n-".len)))
    else:
      return none(CSSAnB)
  else:
    return none(CSSAnB)

proc parseAnB*(cvals: seq[CSSComponentValue]): (Option[CSSAnB], int) =
  var state = CSSParseState(tokens: cast[seq[CSSParsedItem]](cvals))
  let anb = state.parseAnB()
  return (anb, state.at)
