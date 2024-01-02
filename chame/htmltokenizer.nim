{.experimental: "overloadableEnums".}

import std/options
import std/strformat
import std/strutils
import std/tables
import std/unicode

import dombuilder
import entity
import parseerror
import utils/radixtree
import utils/twtstr

# Tokenizer
type
  Tokenizer*[Handle, Atom] = object
    dombuilder: DOMBuilder[Handle, Atom]
    state*: TokenizerState
    rstate: TokenizerState # return state
    tmp: string # temporary buffer (mentioned by the standard)
    code: uint32 # codepoint of current numeric character reference
    tok: Token[Atom] # current token to be emitted
    laststart*: Token[Atom] # last start tag token
    attrn: string # buffer for attribute names
    attrna: Atom # atom representing attrn after the attribute name is closed
    attrv: string # buffer for attribute values
    attr: bool # is there already an attr in the previous values?
    hasnonhtml*: bool # does the stack of open elements have a non-HTML node?
    tokqueue: seq[Token[Atom]] # queue of tokens to be emitted in this iteration
    charbuf: string # buffer for character tokens
    isws: bool # is the current character token whitespace-only?
    tagNameBuf: string # buffer for storing the tag name
    peekBuf: array[64, char] # a stack with the last element at peekBufLen - 1
    peekBufLen: int

  TokenType* = enum
    DOCTYPE, START_TAG, END_TAG, COMMENT, CHARACTER, CHARACTER_WHITESPACE,
    CHARACTER_NULL, EOF

  TokenizerState* = enum
    DATA, CHARACTER_REFERENCE, TAG_OPEN, RCDATA, RCDATA_LESS_THAN_SIGN,
    RAWTEXT, RAWTEXT_LESS_THAN_SIGN, SCRIPT_DATA, SCRIPT_DATA_LESS_THAN_SIGN,
    PLAINTEXT, MARKUP_DECLARATION_OPEN, END_TAG_OPEN, BOGUS_COMMENT, TAG_NAME,
    BEFORE_ATTRIBUTE_NAME, RCDATA_END_TAG_OPEN, RCDATA_END_TAG_NAME,
    RAWTEXT_END_TAG_OPEN, RAWTEXT_END_TAG_NAME, SELF_CLOSING_START_TAG,
    SCRIPT_DATA_END_TAG_OPEN, SCRIPT_DATA_ESCAPE_START,
    SCRIPT_DATA_END_TAG_NAME, SCRIPT_DATA_ESCAPE_START_DASH,
    SCRIPT_DATA_ESCAPED_DASH_DASH, SCRIPT_DATA_ESCAPED,
    SCRIPT_DATA_ESCAPED_DASH, SCRIPT_DATA_ESCAPED_LESS_THAN_SIGN,
    SCRIPT_DATA_ESCAPED_END_TAG_OPEN, SCRIPT_DATA_DOUBLE_ESCAPE_START,
    SCRIPT_DATA_ESCAPED_END_TAG_NAME, SCRIPT_DATA_DOUBLE_ESCAPED,
    SCRIPT_DATA_DOUBLE_ESCAPED_DASH, SCRIPT_DATA_DOUBLE_ESCAPED_LESS_THAN_SIGN,
    SCRIPT_DATA_DOUBLE_ESCAPED_DASH_DASH, SCRIPT_DATA_DOUBLE_ESCAPE_END,
    AFTER_ATTRIBUTE_NAME, ATTRIBUTE_NAME, BEFORE_ATTRIBUTE_VALUE,
    ATTRIBUTE_VALUE_DOUBLE_QUOTED, ATTRIBUTE_VALUE_SINGLE_QUOTED,
    ATTRIBUTE_VALUE_UNQUOTED, AFTER_ATTRIBUTE_VALUE_QUOTED, COMMENT_START,
    CDATA_SECTION, COMMENT_START_DASH, COMMENT, COMMENT_END,
    COMMENT_LESS_THAN_SIGN, COMMENT_END_DASH, COMMENT_LESS_THAN_SIGN_BANG,
    COMMENT_LESS_THAN_SIGN_BANG_DASH, COMMENT_LESS_THAN_SIGN_BANG_DASH_DASH,
    COMMENT_END_BANG, DOCTYPE, BEFORE_DOCTYPE_NAME, DOCTYPE_NAME,
    AFTER_DOCTYPE_NAME, AFTER_DOCTYPE_PUBLIC_KEYWORD,
    AFTER_DOCTYPE_SYSTEM_KEYWORD, BOGUS_DOCTYPE,
    BEFORE_DOCTYPE_PUBLIC_IDENTIFIER, DOCTYPE_PUBLIC_IDENTIFIER_DOUBLE_QUOTED,
    DOCTYPE_PUBLIC_IDENTIFIER_SINGLE_QUOTED, AFTER_DOCTYPE_PUBLIC_IDENTIFIER,
    BETWEEN_DOCTYPE_PUBLIC_AND_SYSTEM_IDENTIFIERS,
    DOCTYPE_SYSTEM_IDENTIFIER_DOUBLE_QUOTED,
    DOCTYPE_SYSTEM_IDENTIFIER_SINGLE_QUOTED, BEFORE_DOCTYPE_SYSTEM_IDENTIFIER,
    AFTER_DOCTYPE_SYSTEM_IDENTIFIER, CDATA_SECTION_BRACKET, CDATA_SECTION_END,
    NAMED_CHARACTER_REFERENCE, NUMERIC_CHARACTER_REFERENCE,
    AMBIGUOUS_AMPERSAND_STATE, HEXADECIMAL_CHARACTER_REFERENCE_START,
    DECIMAL_CHARACTER_REFERENCE_START, HEXADECIMAL_CHARACTER_REFERENCE,
    DECIMAL_CHARACTER_REFERENCE, NUMERIC_CHARACTER_REFERENCE_END

  Token*[Atom] = ref object
    case t*: TokenType
    of DOCTYPE:
      quirks*: bool
      name*: Option[string]
      pubid*: Option[string]
      sysid*: Option[string]
    of START_TAG, END_TAG:
      selfclosing*: bool
      tagname*: Atom
      attrs*: Table[Atom, string]
    of CHARACTER, CHARACTER_WHITESPACE:
      s*: string
    of COMMENT:
      data*: string
    of EOF, CHARACTER_NULL: discard

func `$`*(tok: Token): string =
  case tok.t
  of DOCTYPE: fmt"{tok.t} {tok.name} {tok.pubid} {tok.sysid} {tok.quirks}"
  of START_TAG, END_TAG: fmt"{tok.t} {tok.tagname} {tok.selfclosing} {tok.attrs}"
  of CHARACTER, CHARACTER_WHITESPACE: $tok.t & " " & tok.s
  of CHARACTER_NULL: $tok.t
  of COMMENT: fmt"{tok.t} {tok.data}"
  of EOF: fmt"{tok.t}"

const hexCharMap = (func(): array[char, uint32] =
  for i in 0u32..255u32:
    case chr(i)
    of '0'..'9': result[char(i)] = i - ord('0')
    of 'a'..'f': result[char(i)] = i - ord('a') + 10
    of 'A'..'F': result[char(i)] = i - ord('A') + 10
    else: result[char(i)] = -1
)()

const decCharMap = (func(): array[char, uint32] =
  for i in 0u32..255u32:
    case char(i)
    of '0'..'9': result[char(i)] = i - ord('0')
    else: result[char(i)] = -1
)()

func hexValue(c: char): uint32 =
  return hexCharMap[c]

func decValue(c: char): uint32 =
  return decCharMap[c]

proc strToAtom[Handle, Atom](tokenizer: Tokenizer[Handle, Atom],
    s: string): Atom =
  mixin strToAtomImpl
  return tokenizer.dombuilder.strToAtomImpl(s)

proc newTokenizer*[Handle, Atom](dombuilder: DOMBuilder[Handle, Atom],
    initialState = DATA): Tokenizer[Handle, Atom] =
  var t = Tokenizer[Handle, Atom](
    state: initialState,
    dombuilder: dombuilder
  )
  return t

proc atEnd(tokenizer: Tokenizer): bool =
  mixin atEndImpl
  if tokenizer.peekBufLen > 0:
    return false
  return tokenizer.dombuilder.atEndImpl()

proc reconsume(tokenizer: var Tokenizer, s: string) =
  for i in countdown(s.high, 0):
    tokenizer.peekBuf[tokenizer.peekBufLen] = s[i]
    inc tokenizer.peekBufLen

proc reconsume(tokenizer: var Tokenizer, c: char) =
  tokenizer.peekBuf[tokenizer.peekBufLen] = c
  inc tokenizer.peekBufLen

proc getChar(tokenizer: var Tokenizer): char =
  mixin getCharImpl
  if tokenizer.peekBufLen > 0:
    dec tokenizer.peekBufLen
    return tokenizer.peekBuf[tokenizer.peekBufLen]
  return tokenizer.dombuilder.getCharImpl()

proc consume(tokenizer: var Tokenizer): char =
  let c = tokenizer.getChar()
  if c == '\r': # \r\n -> \n, \r -> \n
    if not tokenizer.atEnd(): # may be \r\n
      let c = tokenizer.getChar()
      if c != '\n': # single \r
        tokenizer.reconsume(c) # keep next c
    return '\n'
  return c

proc consumeDiscard(tokenizer: var Tokenizer, n: int) =
  # We only call this with n <= peekBufLen, because peekBuf has already been
  # filled with characters.
  assert tokenizer.peekBufLen >= n
  tokenizer.peekBufLen -= n

proc flushChars[Handle, Atom](tokenizer: var Tokenizer[Handle, Atom]) =
  if tokenizer.charbuf.len > 0:
    let token = if not tokenizer.isws:
      Token[Atom](t: CHARACTER, s: tokenizer.charbuf)
    else:
      Token[Atom](t: CHARACTER_WHITESPACE, s: tokenizer.charbuf)
    tokenizer.tokqueue.add(token)
    tokenizer.isws = false
    tokenizer.charbuf.setLen(0)

when not defined(parseErrorImpl):
  proc parseErrorImpl(builder: DOMBuilderBase, e: ParseError) =
    discard

proc parseError(tokenizer: Tokenizer, e: ParseError) =
  mixin parseErrorImpl
  tokenizer.dombuilder.parseErrorImpl(e)

const AttributeStates = {
  ATTRIBUTE_VALUE_DOUBLE_QUOTED, ATTRIBUTE_VALUE_SINGLE_QUOTED,
  ATTRIBUTE_VALUE_UNQUOTED
}

func consumedAsAnAttribute(tokenizer: Tokenizer): bool =
  return tokenizer.rstate in AttributeStates

proc appendToCurrentAttrValue(tokenizer: var Tokenizer, c: auto) =
  if tokenizer.attr:
    tokenizer.attrv &= c

proc emit(tokenizer: var Tokenizer, c: char) =
  let isws = c in AsciiWhitespace
  if tokenizer.isws != isws:
    # Emit whitespace & non-whitespace separately.
    tokenizer.flushChars()
    tokenizer.isws = isws
  tokenizer.charbuf &= c

proc numericCharacterReferenceEndState(tokenizer: var Tokenizer) =
  template parse_error(error: untyped) =
    tokenizer.parseError(error)
  template consumed_as_an_attribute(): bool =
    tokenizer.consumedAsAnAttribute()
  case tokenizer.code
  of 0x00:
    parse_error NULL_CHARACTER_REFERENCE
    tokenizer.code = 0xFFFD
  elif tokenizer.code > 0x10FFFF:
    parse_error CHARACTER_REFERENCE_OUTSIDE_UNICODE_RANGE
    tokenizer.code = 0xFFFD
  elif tokenizer.code.isSurrogate():
    parse_error SURROGATE_CHARACTER_REFERENCE
    tokenizer.code = 0xFFFD
  elif tokenizer.code.isNonCharacter():
    parse_error NONCHARACTER_CHARACTER_REFERENCE
    # do nothing
  elif tokenizer.code < 0x80 and
      char(tokenizer.code) in (Controls - AsciiWhitespace) + {char(0x0D)} or
      tokenizer.code in 0x80u32 .. 0x9Fu32:
    const ControlMapTable = [
      (0x80u32, 0x20ACu32), (0x82u32, 0x201Au32), (0x83u32, 0x0192u32),
      (0x84u32, 0x201Eu32), (0x85u32, 0x2026u32), (0x86u32, 0x2020u32),
      (0x87u32, 0x2021u32), (0x88u32, 0x02C6u32), (0x89u32, 0x2030u32),
      (0x8Au32, 0x0160u32), (0x8Bu32, 0x2039u32), (0x8Cu32, 0x0152u32),
      (0x8Eu32, 0x017Du32), (0x91u32, 0x2018u32), (0x92u32, 0x2019u32),
      (0x93u32, 0x201Cu32), (0x94u32, 0x201Du32), (0x95u32, 0x2022u32),
      (0x96u32, 0x2013u32), (0x97u32, 0x2014u32), (0x98u32, 0x02DCu32),
      (0x99u32, 0x2122u32), (0x9Au32, 0x0161u32), (0x9Bu32, 0x203Au32),
      (0x9Cu32, 0x0153u32), (0x9Eu32, 0x017Eu32), (0x9Fu32, 0x0178u32),
    ].toTable()
    if tokenizer.code in ControlMapTable:
      tokenizer.code = ControlMapTable[tokenizer.code]
  let s = $Rune(tokenizer.code)
  if consumed_as_an_attribute:
    tokenizer.appendToCurrentAttrValue(s)
  else:
    for c in s:
      tokenizer.emit(c)

proc flushAttr(tokenizer: var Tokenizer) =
  tokenizer.tok.attrs[tokenizer.attrna] = tokenizer.attrv

proc peekStr(tokenizer: var Tokenizer, s: static string): bool =
  var cs = ""
  for i in 0 ..< s.len:
    if tokenizer.atEnd():
      tokenizer.reconsume(cs)
      return false
    let c = tokenizer.consume()
    cs &= c
    if c != s[i]:
      tokenizer.reconsume(cs)
      return false
  tokenizer.reconsume(cs)
  return true

proc peekStrNoCase(tokenizer: var Tokenizer, s: static string): bool =
  const s = s.toLowerAscii()
  var cs = ""
  for i in 0 ..< s.len:
    if tokenizer.atEnd():
      tokenizer.reconsume(cs)
      return false
    let c = tokenizer.consume()
    cs &= c
    if c.toLowerAscii() != s[i]:
      tokenizer.reconsume(cs)
      return false
  tokenizer.reconsume(cs)
  return true

proc flushTagName(tokenizer: var Tokenizer) =
  tokenizer.tok.tagname = tokenizer.strToAtom(tokenizer.tagNameBuf)

iterator tokenize*[Handle, Atom](tokenizer: var Tokenizer[Handle, Atom]):
    Token[Atom] =
  var running = true

  template emit(tok: Token) =
    tokenizer.flushChars()
    if tok.t == START_TAG:
      tokenizer.laststart = tok
    tokenizer.tokqueue.add(tok)
  template emit(tok: TokenType) = emit Token[Atom](t: tok)
  template emit(s: static string) =
    static:
      doAssert AsciiWhitespace notin s
    if tokenizer.isws:
      tokenizer.flushChars()
    tokenizer.charbuf &= s
  template emit(ch: char) =
    tokenizer.emit(ch)
  template emit_null =
    tokenizer.flushChars()
    emit Token[Atom](t: CHARACTER_NULL)
  template emit_eof =
    tokenizer.flushChars()
    running = false
  template prepare_attrs_if_start =
    if tokenizer.tok.t == START_TAG and tokenizer.attr and
        tokenizer.attrn != "":
      tokenizer.flushAttr()
  template emit_tok =
    emit tokenizer.tok
  template emit_replacement = emit "\uFFFD"
  template switch_state(s: TokenizerState) =
    tokenizer.state = s
  template switch_state_return(s: TokenizerState) =
    tokenizer.rstate = tokenizer.state
    tokenizer.state = s
  template parse_error(error: untyped) =
    tokenizer.parseError(error)
  template is_appropriate_end_tag_token(): bool =
    tokenizer.laststart != nil and
      tokenizer.laststart.tagname == tokenizer.tok.tagname
  template start_new_attribute =
    if tokenizer.tok.t == START_TAG and tokenizer.attr:
      # This can also be called with tok.t == END_TAG, in that case we do
      # not want to flush attributes.
      tokenizer.flushAttr()
    tokenizer.attrn = ""
    tokenizer.attrv = ""
    tokenizer.attr = true
  template leave_attribute_name_state =
    tokenizer.attrna = tokenizer.strToAtom(tokenizer.attrn)
    if tokenizer.attrna in tokenizer.tok.attrs:
      tokenizer.attr = false
  template peek_char(): char =
    let c = tokenizer.consume()
    tokenizer.reconsume(c)
    c
  template emit_tmp() =
    for c in tokenizer.tmp:
      tokenizer.emit(c)
  template flush_code_points_consumed_as_a_character_reference() =
    if tokenizer.consumedAsAnAttribute():
      tokenizer.appendToCurrentAttrValue(tokenizer.tmp)
    else:
      emit_tmp
  template new_token(t: Token) =
    tokenizer.attr = false
    tokenizer.tok = t

  while not tokenizer.atEnd():
    let c = tokenizer.consume()
    template reconsume_in(s: TokenizerState) =
      tokenizer.reconsume(c)
      switch_state s

    case tokenizer.state
    of DATA:
      case c
      of '&': switch_state_return CHARACTER_REFERENCE
      of '<': switch_state TAG_OPEN
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        emit_null
      else: emit c

    of RCDATA:
      case c
      of '&': switch_state_return CHARACTER_REFERENCE
      of '<': switch_state RCDATA_LESS_THAN_SIGN
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        emit_replacement
      else: emit c

    of RAWTEXT:
      case c
      of '<': switch_state RAWTEXT_LESS_THAN_SIGN
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        emit_replacement
      else: emit c

    of SCRIPT_DATA:
      case c
      of '<': switch_state SCRIPT_DATA_LESS_THAN_SIGN
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        emit_replacement
      else: emit c

    of PLAINTEXT:
      case c
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        emit_replacement
      else: emit c

    of TAG_OPEN:
      case c
      of '!': switch_state MARKUP_DECLARATION_OPEN
      of '/': switch_state END_TAG_OPEN
      of AsciiAlpha:
        new_token Token[Atom](t: START_TAG)
        tokenizer.tagNameBuf = ""
        reconsume_in TAG_NAME
      of '?':
        parse_error UNEXPECTED_QUESTION_MARK_INSTEAD_OF_TAG_NAME
        new_token Token[Atom](t: COMMENT)
        reconsume_in BOGUS_COMMENT
      else:
        parse_error INVALID_FIRST_CHARACTER_OF_TAG_NAME
        emit '<'
        reconsume_in DATA

    of END_TAG_OPEN:
      case c
      of AsciiAlpha:
        new_token Token[Atom](t: END_TAG)
        tokenizer.tagNameBuf = ""
        reconsume_in TAG_NAME
      of '>':
        parse_error MISSING_END_TAG_NAME
        switch_state DATA
      else:
        parse_error INVALID_FIRST_CHARACTER_OF_TAG_NAME
        new_token Token[Atom](t: COMMENT)
        reconsume_in BOGUS_COMMENT

    of TAG_NAME:
      case c
      of AsciiWhitespace:
        tokenizer.flushTagName()
        switch_state BEFORE_ATTRIBUTE_NAME
      of '/':
        tokenizer.flushTagName()
        switch_state SELF_CLOSING_START_TAG
      of '>':
        switch_state DATA
        tokenizer.flushTagName()
        emit_tok
      of AsciiUpperAlpha: tokenizer.tagNameBuf &= c.toLowerAscii()
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.tagNameBuf &= "\uFFFD"
      else: tokenizer.tagNameBuf &= c

    of RCDATA_LESS_THAN_SIGN:
      case c
      of '/':
        tokenizer.tmp = ""
        switch_state RCDATA_END_TAG_OPEN
      else:
        emit '<'
        reconsume_in RCDATA

    of RCDATA_END_TAG_OPEN:
      case c
      of AsciiAlpha:
        new_token Token[Atom](t: END_TAG)
        tokenizer.tagNameBuf = ""
        reconsume_in RCDATA_END_TAG_NAME
      else:
        emit "</"
        reconsume_in RCDATA

    of RCDATA_END_TAG_NAME:
      template anything_else =
        new_token nil #TODO
        emit "</"
        emit_tmp
        reconsume_in RCDATA
      case c
      of AsciiWhitespace:
        tokenizer.flushTagName()
        if is_appropriate_end_tag_token:
          switch_state BEFORE_ATTRIBUTE_NAME
        else:
          anything_else
      of '/':
        tokenizer.flushTagName()
        if is_appropriate_end_tag_token:
          switch_state SELF_CLOSING_START_TAG
        else:
          anything_else
      of '>':
        tokenizer.flushTagName()
        if is_appropriate_end_tag_token:
          switch_state DATA
          emit_tok
        else:
          anything_else
      of AsciiAlpha: # note: merged upper & lower
        tokenizer.tagNameBuf &= c.toLowerAscii()
        tokenizer.tmp &= c
      else:
        anything_else

    of RAWTEXT_LESS_THAN_SIGN:
      case c
      of '/':
        tokenizer.tmp = ""
        switch_state RAWTEXT_END_TAG_OPEN
      else:
        emit '<'
        reconsume_in RAWTEXT

    of RAWTEXT_END_TAG_OPEN:
      case c
      of AsciiAlpha:
        new_token Token[Atom](t: END_TAG)
        tokenizer.tagNameBuf = ""
        reconsume_in RAWTEXT_END_TAG_NAME
      else:
        emit "</"
        reconsume_in RAWTEXT

    of RAWTEXT_END_TAG_NAME:
      template anything_else =
        new_token nil #TODO
        emit "</"
        emit_tmp
        reconsume_in RAWTEXT
      case c
      of AsciiWhitespace:
        tokenizer.flushTagName()
        if is_appropriate_end_tag_token:
          switch_state BEFORE_ATTRIBUTE_NAME
        else:
          anything_else
      of '/':
        tokenizer.flushTagName()
        if is_appropriate_end_tag_token:
          switch_state SELF_CLOSING_START_TAG
        else:
          anything_else
      of '>':
        tokenizer.flushTagName()
        if is_appropriate_end_tag_token:
          switch_state DATA
          emit_tok
        else:
          anything_else
      of AsciiAlpha: # note: merged upper & lower
        tokenizer.tagNameBuf &= c.toLowerAscii()
        tokenizer.tmp &= c
      else:
        anything_else

    of SCRIPT_DATA_LESS_THAN_SIGN:
      case c
      of '/':
        tokenizer.tmp = ""
        switch_state SCRIPT_DATA_END_TAG_OPEN
      of '!':
        switch_state SCRIPT_DATA_ESCAPE_START
        emit "<!"
      else:
        emit '<'
        reconsume_in SCRIPT_DATA

    of SCRIPT_DATA_END_TAG_OPEN:
      case c
      of AsciiAlpha:
        new_token Token[Atom](t: END_TAG)
        tokenizer.tagNameBuf = ""
        reconsume_in SCRIPT_DATA_END_TAG_NAME
      else:
        emit "</"
        reconsume_in SCRIPT_DATA

    of SCRIPT_DATA_END_TAG_NAME:
      template anything_else =
        emit "</"
        emit_tmp
        reconsume_in SCRIPT_DATA
      case c
      of AsciiWhitespace:
        tokenizer.flushTagName()
        if is_appropriate_end_tag_token:
          switch_state BEFORE_ATTRIBUTE_NAME
        else:
          anything_else
      of '/':
        tokenizer.flushTagName()
        if is_appropriate_end_tag_token:
          switch_state SELF_CLOSING_START_TAG
        else:
          anything_else
      of '>':
        tokenizer.flushTagName()
        if is_appropriate_end_tag_token:
          switch_state DATA
          emit_tok
        else:
          anything_else
      of AsciiAlpha: # note: merged upper & lower
        tokenizer.tagNameBuf &= c.toLowerAscii()
        tokenizer.tmp &= c
      else:
        anything_else

    of SCRIPT_DATA_ESCAPE_START:
      case c
      of '-':
        switch_state SCRIPT_DATA_ESCAPE_START_DASH
        emit '-'
      else:
        reconsume_in SCRIPT_DATA

    of SCRIPT_DATA_ESCAPE_START_DASH:
      case c
      of '-':
        switch_state SCRIPT_DATA_ESCAPED_DASH_DASH
        emit '-'
      else:
        reconsume_in SCRIPT_DATA

    of SCRIPT_DATA_ESCAPED:
      case c
      of '-':
        switch_state SCRIPT_DATA_ESCAPED_DASH
        emit '-'
      of '<':
        switch_state SCRIPT_DATA_ESCAPED_LESS_THAN_SIGN
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        emit_replacement
      else:
        emit c

    of SCRIPT_DATA_ESCAPED_DASH:
      case c
      of '-':
        switch_state SCRIPT_DATA_ESCAPED_DASH_DASH
        emit '-'
      of '<':
        switch_state SCRIPT_DATA_ESCAPED_LESS_THAN_SIGN
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        switch_state SCRIPT_DATA_ESCAPED
        emit_replacement
      else:
        switch_state SCRIPT_DATA_ESCAPED
        emit c

    of SCRIPT_DATA_ESCAPED_DASH_DASH:
      case c
      of '-':
        emit '-'
      of '<':
        switch_state SCRIPT_DATA_ESCAPED_LESS_THAN_SIGN
      of '>':
        switch_state SCRIPT_DATA
        emit '>'
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        switch_state SCRIPT_DATA_ESCAPED
        emit_replacement
      else:
        switch_state SCRIPT_DATA_ESCAPED
        emit c

    of SCRIPT_DATA_ESCAPED_LESS_THAN_SIGN:
      case c
      of '/':
        tokenizer.tmp = ""
        switch_state SCRIPT_DATA_ESCAPED_END_TAG_OPEN
      of AsciiAlpha:
        tokenizer.tmp = ""
        emit '<'
        reconsume_in SCRIPT_DATA_DOUBLE_ESCAPE_START
      else:
        emit '<'
        reconsume_in SCRIPT_DATA_ESCAPED

    of SCRIPT_DATA_ESCAPED_END_TAG_OPEN:
      case c
      of AsciiAlpha:
        new_token Token[Atom](t: END_TAG)
        tokenizer.tagNameBuf = ""
        reconsume_in SCRIPT_DATA_ESCAPED_END_TAG_NAME
      else:
        emit "</"
        reconsume_in SCRIPT_DATA_ESCAPED

    of SCRIPT_DATA_ESCAPED_END_TAG_NAME:
      template anything_else =
        emit "</"
        emit_tmp
        reconsume_in SCRIPT_DATA_ESCAPED
      case c
      of AsciiWhitespace:
        tokenizer.flushTagName()
        if is_appropriate_end_tag_token:
          switch_state BEFORE_ATTRIBUTE_NAME
        else:
          anything_else
      of '/':
        tokenizer.flushTagName()
        if is_appropriate_end_tag_token:
          switch_state SELF_CLOSING_START_TAG
        else:
          anything_else
      of '>':
        tokenizer.flushTagName()
        if is_appropriate_end_tag_token:
          switch_state DATA
          emit_tok
        else:
          anything_else
      of AsciiAlpha:
        tokenizer.tagNameBuf &= c.toLowerAscii()
        tokenizer.tmp &= c
      else:
        anything_else

    of SCRIPT_DATA_DOUBLE_ESCAPE_START:
      case c
      of AsciiWhitespace, '/', '>':
        if tokenizer.tmp == "script":
          switch_state SCRIPT_DATA_DOUBLE_ESCAPED
        else:
          switch_state SCRIPT_DATA_ESCAPED
        emit c
      of AsciiAlpha: # note: merged upper & lower
        tokenizer.tmp &= c.toLowerAscii()
        emit c
      else: reconsume_in SCRIPT_DATA_ESCAPED

    of SCRIPT_DATA_DOUBLE_ESCAPED:
      case c
      of '-':
        switch_state SCRIPT_DATA_DOUBLE_ESCAPED_DASH
        emit '-'
      of '<':
        switch_state SCRIPT_DATA_DOUBLE_ESCAPED_LESS_THAN_SIGN
        emit '<'
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        emit_replacement
      else: emit c

    of SCRIPT_DATA_DOUBLE_ESCAPED_DASH:
      case c
      of '-':
        switch_state SCRIPT_DATA_DOUBLE_ESCAPED_DASH_DASH
        emit '-'
      of '<':
        switch_state SCRIPT_DATA_DOUBLE_ESCAPED_LESS_THAN_SIGN
        emit '<'
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        switch_state SCRIPT_DATA_DOUBLE_ESCAPED
        emit_replacement
      else:
        switch_state SCRIPT_DATA_DOUBLE_ESCAPED
        emit c

    of SCRIPT_DATA_DOUBLE_ESCAPED_DASH_DASH:
      case c
      of '-': emit '-'
      of '<':
        switch_state SCRIPT_DATA_DOUBLE_ESCAPED_LESS_THAN_SIGN
        emit '<'
      of '>':
        switch_state SCRIPT_DATA
        emit '>'
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        switch_state SCRIPT_DATA_DOUBLE_ESCAPED
        emit_replacement
      else:
        switch_state SCRIPT_DATA_DOUBLE_ESCAPED
        emit c

    of SCRIPT_DATA_DOUBLE_ESCAPED_LESS_THAN_SIGN:
      case c
      of '/':
        tokenizer.tmp = ""
        switch_state SCRIPT_DATA_DOUBLE_ESCAPE_END
        emit '/'
      else: reconsume_in SCRIPT_DATA_DOUBLE_ESCAPED

    of SCRIPT_DATA_DOUBLE_ESCAPE_END:
      case c
      of AsciiWhitespace, '/', '>':
        if tokenizer.tmp == "script":
          switch_state SCRIPT_DATA_ESCAPED
        else:
          switch_state SCRIPT_DATA_DOUBLE_ESCAPED
        emit c
      of AsciiAlpha: # note: merged upper & lower
        tokenizer.tmp &= c.toLowerAscii()
        emit c
      else:
        reconsume_in SCRIPT_DATA_DOUBLE_ESCAPED

    of BEFORE_ATTRIBUTE_NAME:
      case c
      of AsciiWhitespace: discard
      of '/', '>': reconsume_in AFTER_ATTRIBUTE_NAME
      of '=':
        parse_error UNEXPECTED_EQUALS_SIGN_BEFORE_ATTRIBUTE_NAME
        start_new_attribute
        tokenizer.attrn &= c
        switch_state ATTRIBUTE_NAME
      else:
        start_new_attribute
        reconsume_in ATTRIBUTE_NAME

    of ATTRIBUTE_NAME:
      template anything_else =
        tokenizer.attrn &= c
      case c
      of AsciiWhitespace, '/', '>':
        leave_attribute_name_state
        reconsume_in AFTER_ATTRIBUTE_NAME
      of '=':
        leave_attribute_name_state
        switch_state BEFORE_ATTRIBUTE_VALUE
      of AsciiUpperAlpha:
        tokenizer.attrn &= c.toLowerAscii()
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.attrn &= "\uFFFD"
      of '"', '\'', '<':
        parse_error UNEXPECTED_CHARACTER_IN_ATTRIBUTE_NAME
        anything_else
      else:
        anything_else

    of AFTER_ATTRIBUTE_NAME:
      case c
      of AsciiWhitespace: discard
      of '/': switch_state SELF_CLOSING_START_TAG
      of '=': switch_state BEFORE_ATTRIBUTE_VALUE
      of '>':
        switch_state DATA
        prepare_attrs_if_start
        emit_tok
      else:
        start_new_attribute
        reconsume_in ATTRIBUTE_NAME

    of BEFORE_ATTRIBUTE_VALUE:
      case c
      of AsciiWhitespace: discard
      of '"': switch_state ATTRIBUTE_VALUE_DOUBLE_QUOTED
      of '\'': switch_state ATTRIBUTE_VALUE_SINGLE_QUOTED
      of '>':
        parse_error MISSING_ATTRIBUTE_VALUE
        switch_state DATA
        prepare_attrs_if_start
        emit_tok
      else: reconsume_in ATTRIBUTE_VALUE_UNQUOTED

    of ATTRIBUTE_VALUE_DOUBLE_QUOTED:
      case c
      of '"': switch_state AFTER_ATTRIBUTE_VALUE_QUOTED
      of '&': switch_state_return CHARACTER_REFERENCE
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.appendToCurrentAttrValue("\uFFFD")
      else: tokenizer.appendToCurrentAttrValue(c)

    of ATTRIBUTE_VALUE_SINGLE_QUOTED:
      case c
      of '\'': switch_state AFTER_ATTRIBUTE_VALUE_QUOTED
      of '&': switch_state_return CHARACTER_REFERENCE
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.appendToCurrentAttrValue("\uFFFD")
      else: tokenizer.appendToCurrentAttrValue(c)

    of ATTRIBUTE_VALUE_UNQUOTED:
      case c
      of AsciiWhitespace: switch_state BEFORE_ATTRIBUTE_NAME
      of '&': switch_state_return CHARACTER_REFERENCE
      of '>':
        switch_state DATA
        prepare_attrs_if_start
        emit_tok
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.appendToCurrentAttrValue("\uFFFD")
      of '"', '\'', '<', '=', '`':
        parse_error UNEXPECTED_CHARACTER_IN_UNQUOTED_ATTRIBUTE_VALUE
        tokenizer.appendToCurrentAttrValue(c)
      else: tokenizer.appendToCurrentAttrValue(c)

    of AFTER_ATTRIBUTE_VALUE_QUOTED:
      case c
      of AsciiWhitespace:
        switch_state BEFORE_ATTRIBUTE_NAME
      of '/':
        switch_state SELF_CLOSING_START_TAG
      of '>':
        switch_state DATA
        prepare_attrs_if_start
        emit_tok
      else:
        parse_error MISSING_WHITESPACE_BETWEEN_ATTRIBUTES
        reconsume_in BEFORE_ATTRIBUTE_NAME

    of SELF_CLOSING_START_TAG:
      case c
      of '>':
        tokenizer.tok.selfclosing = true
        switch_state DATA
        prepare_attrs_if_start
        emit_tok
      else:
        parse_error UNEXPECTED_SOLIDUS_IN_TAG
        reconsume_in BEFORE_ATTRIBUTE_NAME

    of BOGUS_COMMENT:
      assert tokenizer.tok.t == COMMENT
      case c
      of '>':
        switch_state DATA
        emit_tok
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.tok.data &= "\uFFFD"
      else: tokenizer.tok.data &= c

    of MARKUP_DECLARATION_OPEN: # note: rewritten to fit case model as we consume a char anyway
      template anything_else =
        parse_error INCORRECTLY_OPENED_COMMENT
        new_token Token[Atom](t: COMMENT)
        reconsume_in BOGUS_COMMENT
      case c
      of '-':
        if not tokenizer.atEnd() and peek_char == '-':
          new_token Token[Atom](t: COMMENT)
          tokenizer.state = COMMENT_START
          tokenizer.consumeDiscard(1)
        else: anything_else
      of 'D', 'd':
        if tokenizer.peekStrNoCase("octype"):
          tokenizer.consumeDiscard("octype".len)
          switch_state DOCTYPE
        else: anything_else
      of '[':
        if tokenizer.peekStr("CDATA["):
          tokenizer.consumeDiscard("CDATA[".len)
          if tokenizer.hasnonhtml:
            switch_state CDATA_SECTION
          else:
            parse_error CDATA_IN_HTML_CONTENT
            new_token Token[Atom](t: COMMENT, data: "[CDATA[")
            switch_state BOGUS_COMMENT
        else: anything_else
      else:
        anything_else

    of COMMENT_START:
      case c
      of '-': switch_state COMMENT_START_DASH
      of '>':
        parse_error ABRUPT_CLOSING_OF_EMPTY_COMMENT
        switch_state DATA
        emit_tok
      else: reconsume_in COMMENT

    of COMMENT_START_DASH:
      case c
      of '-': switch_state COMMENT_END
      of '>':
        parse_error ABRUPT_CLOSING_OF_EMPTY_COMMENT
        switch_state DATA
        emit_tok
      else:
        tokenizer.tok.data &= '-'
        reconsume_in COMMENT

    of COMMENT:
      case c
      of '<':
        tokenizer.tok.data &= c
        switch_state COMMENT_LESS_THAN_SIGN
      of '-': switch_state COMMENT_END_DASH
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.tok.data &= "\uFFFD"
      else: tokenizer.tok.data &= c

    of COMMENT_LESS_THAN_SIGN:
      case c
      of '!':
        tokenizer.tok.data &= c
        switch_state COMMENT_LESS_THAN_SIGN_BANG
      of '<': tokenizer.tok.data &= c
      else: reconsume_in COMMENT

    of COMMENT_LESS_THAN_SIGN_BANG:
      case c
      of '-': switch_state COMMENT_LESS_THAN_SIGN_BANG_DASH
      else: reconsume_in COMMENT

    of COMMENT_LESS_THAN_SIGN_BANG_DASH:
      case c
      of '-': switch_state COMMENT_LESS_THAN_SIGN_BANG_DASH_DASH
      else: reconsume_in COMMENT_END_DASH

    of COMMENT_LESS_THAN_SIGN_BANG_DASH_DASH:
      case c
      of '>': reconsume_in COMMENT_END
      else:
        parse_error NESTED_COMMENT
        reconsume_in COMMENT_END

    of COMMENT_END_DASH:
      case c
      of '-': switch_state COMMENT_END
      else:
        tokenizer.tok.data &= '-'
        reconsume_in COMMENT

    of COMMENT_END:
      case c
      of '>':
        switch_state DATA
        emit_tok
      of '!': switch_state COMMENT_END_BANG
      of '-': tokenizer.tok.data &= '-'
      else:
        tokenizer.tok.data &= "--"
        reconsume_in COMMENT

    of COMMENT_END_BANG:
      case c
      of '-':
        tokenizer.tok.data &= "--!"
        switch_state COMMENT_END_DASH
      of '>':
        parse_error INCORRECTLY_CLOSED_COMMENT
        switch_state DATA
        emit_tok
      else:
        tokenizer.tok.data &= "--!"
        reconsume_in COMMENT

    of DOCTYPE:
      case c
      of AsciiWhitespace: switch_state BEFORE_DOCTYPE_NAME
      of '>': reconsume_in BEFORE_DOCTYPE_NAME
      else:
        parse_error MISSING_WHITESPACE_BEFORE_DOCTYPE_NAME
        reconsume_in BEFORE_DOCTYPE_NAME

    of BEFORE_DOCTYPE_NAME:
      case c
      of AsciiWhitespace: discard
      of AsciiUpperAlpha:
        new_token Token[Atom](t: DOCTYPE, name: some($c.toLowerAscii()))
        switch_state DOCTYPE_NAME
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        new_token Token[Atom](t: DOCTYPE, name: some($"\uFFFD"))
        switch_state DOCTYPE_NAME
      of '>':
        parse_error MISSING_DOCTYPE_NAME
        new_token Token[Atom](t: DOCTYPE, quirks: true)
        switch_state DATA
        emit_tok
      else:
        new_token Token[Atom](t: DOCTYPE, name: some($c))
        switch_state DOCTYPE_NAME

    of DOCTYPE_NAME:
      case c
      of AsciiWhitespace: switch_state AFTER_DOCTYPE_NAME
      of '>':
        switch_state DATA
        emit_tok
      of AsciiUpperAlpha:
        tokenizer.tok.name.get &= c.toLowerAscii()
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.tok.name.get &= "\uFFFD"
      else:
        tokenizer.tok.name.get &= c

    of AFTER_DOCTYPE_NAME: # note: rewritten to fit case model as we consume a char anyway
      template anything_else =
        parse_error INVALID_CHARACTER_SEQUENCE_AFTER_DOCTYPE_NAME
        tokenizer.tok.quirks = true
        reconsume_in BOGUS_DOCTYPE
      case c
      of AsciiWhitespace: discard
      of '>':
        switch_state DATA
        emit_tok
      of 'p', 'P':
        if tokenizer.peekStrNoCase("ublic"):
          tokenizer.consumeDiscard("ublic".len)
          switch_state AFTER_DOCTYPE_PUBLIC_KEYWORD
        else:
          anything_else
      of 's', 'S':
        if tokenizer.peekStrNoCase("ystem"):
          tokenizer.consumeDiscard("ystem".len)
          switch_state AFTER_DOCTYPE_SYSTEM_KEYWORD
        else:
          anything_else
      else:
        anything_else

    of AFTER_DOCTYPE_PUBLIC_KEYWORD:
      case c
      of AsciiWhitespace: switch_state BEFORE_DOCTYPE_PUBLIC_IDENTIFIER
      of '"':
        parse_error MISSING_WHITESPACE_AFTER_DOCTYPE_PUBLIC_KEYWORD
        tokenizer.tok.pubid = some("")
        switch_state DOCTYPE_PUBLIC_IDENTIFIER_DOUBLE_QUOTED
      of '\'':
        parse_error MISSING_WHITESPACE_AFTER_DOCTYPE_PUBLIC_KEYWORD
        tokenizer.tok.pubid = some("")
        switch_state DOCTYPE_PUBLIC_IDENTIFIER_SINGLE_QUOTED
      of '>':
        parse_error MISSING_DOCTYPE_PUBLIC_IDENTIFIER
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      else:
        parse_error MISSING_QUOTE_BEFORE_DOCTYPE_PUBLIC_IDENTIFIER
        tokenizer.tok.quirks = true
        reconsume_in BOGUS_DOCTYPE

    of BEFORE_DOCTYPE_PUBLIC_IDENTIFIER:
      case c
      of AsciiWhitespace: discard
      of '"':
        tokenizer.tok.pubid = some("")
        switch_state DOCTYPE_PUBLIC_IDENTIFIER_DOUBLE_QUOTED
      of '\'':
        tokenizer.tok.pubid = some("")
        switch_state DOCTYPE_PUBLIC_IDENTIFIER_SINGLE_QUOTED
      of '>':
        parse_error MISSING_DOCTYPE_PUBLIC_IDENTIFIER
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      else:
        parse_error MISSING_QUOTE_BEFORE_DOCTYPE_PUBLIC_IDENTIFIER
        tokenizer.tok.quirks = true
        reconsume_in BOGUS_DOCTYPE

    of DOCTYPE_PUBLIC_IDENTIFIER_DOUBLE_QUOTED:
      case c
      of '"': switch_state AFTER_DOCTYPE_PUBLIC_IDENTIFIER
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.tok.pubid.get &= "\uFFFD"
      of '>':
        parse_error ABRUPT_DOCTYPE_PUBLIC_IDENTIFIER
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      else:
        tokenizer.tok.pubid.get &= c

    of DOCTYPE_PUBLIC_IDENTIFIER_SINGLE_QUOTED:
      case c
      of '\'': switch_state AFTER_DOCTYPE_PUBLIC_IDENTIFIER
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.tok.pubid.get &= "\uFFFD"
      of '>':
        parse_error ABRUPT_DOCTYPE_PUBLIC_IDENTIFIER
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      else:
        tokenizer.tok.pubid.get &= c

    of AFTER_DOCTYPE_PUBLIC_IDENTIFIER:
      case c
      of AsciiWhitespace: switch_state BETWEEN_DOCTYPE_PUBLIC_AND_SYSTEM_IDENTIFIERS
      of '>':
        switch_state DATA
        emit_tok
      of '"':
        parse_error MISSING_WHITESPACE_BETWEEN_DOCTYPE_PUBLIC_AND_SYSTEM_IDENTIFIERS
        tokenizer.tok.sysid = some("")
        switch_state DOCTYPE_SYSTEM_IDENTIFIER_DOUBLE_QUOTED
      of '\'':
        parse_error MISSING_WHITESPACE_BETWEEN_DOCTYPE_PUBLIC_AND_SYSTEM_IDENTIFIERS
        tokenizer.tok.sysid = some("")
        switch_state DOCTYPE_SYSTEM_IDENTIFIER_SINGLE_QUOTED
      else:
        parse_error MISSING_QUOTE_BEFORE_DOCTYPE_SYSTEM_IDENTIFIER
        tokenizer.tok.quirks = true
        reconsume_in BOGUS_DOCTYPE

    of BETWEEN_DOCTYPE_PUBLIC_AND_SYSTEM_IDENTIFIERS:
      case c
      of AsciiWhitespace: discard
      of '>':
        switch_state DATA
        emit_tok
      of '"':
        tokenizer.tok.sysid = some("")
        switch_state DOCTYPE_SYSTEM_IDENTIFIER_DOUBLE_QUOTED
      of '\'':
        tokenizer.tok.sysid = some("")
        switch_state DOCTYPE_SYSTEM_IDENTIFIER_SINGLE_QUOTED
      else:
        parse_error MISSING_QUOTE_BEFORE_DOCTYPE_SYSTEM_IDENTIFIER
        tokenizer.tok.quirks = true
        reconsume_in BOGUS_DOCTYPE

    of AFTER_DOCTYPE_SYSTEM_KEYWORD:
      case c
      of AsciiWhitespace: switch_state BEFORE_DOCTYPE_SYSTEM_IDENTIFIER
      of '"':
        parse_error MISSING_WHITESPACE_AFTER_DOCTYPE_SYSTEM_KEYWORD
        tokenizer.tok.sysid = some("")
        switch_state DOCTYPE_SYSTEM_IDENTIFIER_DOUBLE_QUOTED
      of '\'':
        parse_error MISSING_WHITESPACE_AFTER_DOCTYPE_SYSTEM_KEYWORD
        tokenizer.tok.sysid = some("")
        switch_state DOCTYPE_SYSTEM_IDENTIFIER_SINGLE_QUOTED
      of '>':
        parse_error MISSING_DOCTYPE_SYSTEM_IDENTIFIER
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      else:
        parse_error MISSING_QUOTE_BEFORE_DOCTYPE_SYSTEM_IDENTIFIER
        tokenizer.tok.quirks = true
        reconsume_in BOGUS_DOCTYPE

    of BEFORE_DOCTYPE_SYSTEM_IDENTIFIER:
      case c
      of AsciiWhitespace: discard
      of '"':
        tokenizer.tok.sysid = some("")
        switch_state DOCTYPE_SYSTEM_IDENTIFIER_DOUBLE_QUOTED
      of '\'':
        tokenizer.tok.sysid = some("")
        switch_state DOCTYPE_SYSTEM_IDENTIFIER_SINGLE_QUOTED
      of '>':
        parse_error MISSING_DOCTYPE_SYSTEM_IDENTIFIER
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      else:
        parse_error MISSING_QUOTE_BEFORE_DOCTYPE_SYSTEM_IDENTIFIER
        tokenizer.tok.quirks = true
        reconsume_in BOGUS_DOCTYPE

    of DOCTYPE_SYSTEM_IDENTIFIER_DOUBLE_QUOTED:
      case c
      of '"': switch_state AFTER_DOCTYPE_SYSTEM_IDENTIFIER
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.tok.sysid.get &= "\uFFFD"
      of '>':
        parse_error ABRUPT_DOCTYPE_SYSTEM_IDENTIFIER
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      else:
        tokenizer.tok.sysid.get &= c

    of DOCTYPE_SYSTEM_IDENTIFIER_SINGLE_QUOTED:
      case c
      of '\'': switch_state AFTER_DOCTYPE_SYSTEM_IDENTIFIER
      of '\0':
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.tok.sysid.get &= "\uFFFD"
      of '>':
        parse_error ABRUPT_DOCTYPE_SYSTEM_IDENTIFIER
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      else:
        tokenizer.tok.sysid.get &= c

    of AFTER_DOCTYPE_SYSTEM_IDENTIFIER:
      case c
      of AsciiWhitespace: discard
      of '>':
        switch_state DATA
        emit_tok
      else:
        parse_error UNEXPECTED_CHARACTER_AFTER_DOCTYPE_SYSTEM_IDENTIFIER
        reconsume_in BOGUS_DOCTYPE

    of BOGUS_DOCTYPE:
      case c
      of '>':
        switch_state DATA
        emit_tok
      of '\0': parse_error UNEXPECTED_NULL_CHARACTER
      else: discard

    of CDATA_SECTION:
      case c
      of ']': switch_state CDATA_SECTION_BRACKET
      of '\0':
        # "U+0000 NULL characters are handled in the tree construction stage,
        # as part of the in foreign content insertion mode, which is the only
        # place where CDATA sections can appear."
        emit_null
      else:
        emit c

    of CDATA_SECTION_BRACKET:
      case c
      of ']': switch_state CDATA_SECTION_END
      else:
        emit ']'
        reconsume_in CDATA_SECTION

    of CDATA_SECTION_END:
      case c
      of ']': emit ']'
      of '>': switch_state DATA
      else:
        emit "]]"
        reconsume_in CDATA_SECTION

    of CHARACTER_REFERENCE:
      case c
      of AsciiAlpha:
        tokenizer.tmp = "&"
        reconsume_in NAMED_CHARACTER_REFERENCE
      of '#':
        tokenizer.tmp = "&#"
        switch_state NUMERIC_CHARACTER_REFERENCE
      else:
        tokenizer.tmp = "&"
        flush_code_points_consumed_as_a_character_reference
        reconsume_in tokenizer.rstate

    of NAMED_CHARACTER_REFERENCE:
      tokenizer.reconsume(c)
      var tokenizerp = addr tokenizer
      var lasti = 0
      let value = entityMap.find((proc(s: var string): bool =
        if tokenizerp[].atEnd():
          return false
        let c = tokenizerp[].consume()
        tokenizerp[].tmp &= c
        s &= c
        return true
      ), lasti)
      inc lasti # add 1, because we do not store the & in entityMap
      # move back the pointer & shorten the buffer to the last match.
      tokenizer.reconsume(tokenizer.tmp.substr(lasti))
      tokenizer.tmp.setLen(lasti)
      if value.isSome:
        if tokenizer.consumedAsAnAttribute() and tokenizer.tmp[^1] != ';' and
            not tokenizer.atEnd() and peek_char in {'='} + AsciiAlphaNumeric:
          flush_code_points_consumed_as_a_character_reference
          switch_state tokenizer.rstate
        else:
          if tokenizer.tmp[^1] != ';':
            parse_error MISSING_SEMICOLON_AFTER_CHARACTER_REFERENCE
          tokenizer.tmp = $value.get
          flush_code_points_consumed_as_a_character_reference
          switch_state tokenizer.rstate
      else:
        flush_code_points_consumed_as_a_character_reference
        switch_state AMBIGUOUS_AMPERSAND_STATE

    of AMBIGUOUS_AMPERSAND_STATE:
      case c
      of AsciiAlpha:
        if tokenizer.consumedAsAnAttribute():
          tokenizer.appendToCurrentAttrValue(c)
        else:
          emit c
      of ';':
        parse_error UNKNOWN_NAMED_CHARACTER_REFERENCE
        reconsume_in tokenizer.rstate
      else: reconsume_in tokenizer.rstate

    of NUMERIC_CHARACTER_REFERENCE:
      tokenizer.code = 0
      case c
      of 'x', 'X':
        tokenizer.tmp &= c
        switch_state HEXADECIMAL_CHARACTER_REFERENCE_START
      else: reconsume_in DECIMAL_CHARACTER_REFERENCE_START

    of HEXADECIMAL_CHARACTER_REFERENCE_START:
      case c
      of AsciiHexDigit: reconsume_in HEXADECIMAL_CHARACTER_REFERENCE
      else:
        parse_error ABSENCE_OF_DIGITS_IN_NUMERIC_CHARACTER_REFERENCE
        flush_code_points_consumed_as_a_character_reference
        reconsume_in tokenizer.rstate

    of DECIMAL_CHARACTER_REFERENCE_START:
      case c
      of AsciiDigit: reconsume_in DECIMAL_CHARACTER_REFERENCE
      else:
        parse_error ABSENCE_OF_DIGITS_IN_NUMERIC_CHARACTER_REFERENCE
        flush_code_points_consumed_as_a_character_reference
        reconsume_in tokenizer.rstate

    of HEXADECIMAL_CHARACTER_REFERENCE:
      case c
      of AsciiHexDigit: # note: merged digit, upper hex, lower hex
        if tokenizer.code < 0x10FFFF:
          tokenizer.code *= 0x10
          tokenizer.code += hexValue(c)
      of ';': switch_state NUMERIC_CHARACTER_REFERENCE_END
      else:
        parse_error MISSING_SEMICOLON_AFTER_CHARACTER_REFERENCE
        reconsume_in NUMERIC_CHARACTER_REFERENCE_END

    of DECIMAL_CHARACTER_REFERENCE:
      case c
      of AsciiDigit:
        if tokenizer.code < 0x10FFFF:
          tokenizer.code *= 10
          tokenizer.code += decValue(c)
      of ';': switch_state NUMERIC_CHARACTER_REFERENCE_END
      else:
        parse_error MISSING_SEMICOLON_AFTER_CHARACTER_REFERENCE
        reconsume_in NUMERIC_CHARACTER_REFERENCE_END

    of NUMERIC_CHARACTER_REFERENCE_END:
      tokenizer.numericCharacterReferenceEndState()
      reconsume_in tokenizer.rstate # we unnecessarily consumed once so reconsume

    for tok in tokenizer.tokqueue:
      yield tok
    tokenizer.tokqueue.setLen(0)

  template reconsume_in(s: TokenizerState) =
    switch_state s

  # tokenizer.atEnd() is true here
  while running:
    case tokenizer.state
    of DATA, RCDATA, RAWTEXT, SCRIPT_DATA, PLAINTEXT:
      emit_eof
    of TAG_OPEN:
      parse_error EOF_BEFORE_TAG_NAME
      emit '<'
      emit_eof
    of END_TAG_OPEN:
      parse_error EOF_BEFORE_TAG_NAME
      emit "</"
      emit_eof
    of TAG_NAME:
      parse_error EOF_IN_TAG
      emit_eof
    of RCDATA_LESS_THAN_SIGN:
      emit '<'
      reconsume_in RCDATA
    of RCDATA_END_TAG_OPEN:
      emit "</"
      reconsume_in RCDATA
    of RCDATA_END_TAG_NAME:
      new_token nil #TODO
      emit "</"
      emit_tmp
      reconsume_in RCDATA
    of RAWTEXT_LESS_THAN_SIGN:
      emit '<'
      reconsume_in RAWTEXT
    of RAWTEXT_END_TAG_OPEN:
      emit "</"
      reconsume_in RAWTEXT
    of RAWTEXT_END_TAG_NAME:
      new_token nil #TODO
      emit "</"
      emit_tmp
      reconsume_in RAWTEXT
      emit_eof
    of SCRIPT_DATA_LESS_THAN_SIGN:
      emit '<'
      reconsume_in SCRIPT_DATA
    of SCRIPT_DATA_END_TAG_OPEN:
      emit "</"
      reconsume_in SCRIPT_DATA
    of SCRIPT_DATA_END_TAG_NAME:
      emit "</"
      emit_tmp
      reconsume_in SCRIPT_DATA
    of SCRIPT_DATA_ESCAPE_START, SCRIPT_DATA_ESCAPE_START_DASH:
      reconsume_in SCRIPT_DATA
    of SCRIPT_DATA_ESCAPED, SCRIPT_DATA_ESCAPED_DASH,
        SCRIPT_DATA_ESCAPED_DASH_DASH:
      parse_error EOF_IN_SCRIPT_HTML_COMMENT_LIKE_TEXT
      emit_eof
    of SCRIPT_DATA_ESCAPED_LESS_THAN_SIGN:
      emit '<'
      reconsume_in SCRIPT_DATA_ESCAPED
    of SCRIPT_DATA_ESCAPED_END_TAG_OPEN:
      emit "</"
      reconsume_in SCRIPT_DATA_ESCAPED
    of SCRIPT_DATA_ESCAPED_END_TAG_NAME:
      emit "</"
      emit_tmp
      reconsume_in SCRIPT_DATA_ESCAPED
    of SCRIPT_DATA_DOUBLE_ESCAPE_START:
      reconsume_in SCRIPT_DATA_ESCAPED
    of SCRIPT_DATA_DOUBLE_ESCAPED, SCRIPT_DATA_DOUBLE_ESCAPED_DASH,
        SCRIPT_DATA_DOUBLE_ESCAPED_DASH_DASH:
      parse_error EOF_IN_SCRIPT_HTML_COMMENT_LIKE_TEXT
      emit_eof
    of SCRIPT_DATA_DOUBLE_ESCAPED_LESS_THAN_SIGN, SCRIPT_DATA_DOUBLE_ESCAPE_END:
      reconsume_in SCRIPT_DATA_DOUBLE_ESCAPED
    of BEFORE_ATTRIBUTE_NAME, ATTRIBUTE_NAME:
      reconsume_in AFTER_ATTRIBUTE_NAME
    of AFTER_ATTRIBUTE_NAME:
      parse_error EOF_IN_TAG
      emit_eof
    of BEFORE_ATTRIBUTE_VALUE:
      reconsume_in ATTRIBUTE_VALUE_UNQUOTED
    of ATTRIBUTE_VALUE_DOUBLE_QUOTED, ATTRIBUTE_VALUE_SINGLE_QUOTED,
        ATTRIBUTE_VALUE_UNQUOTED, AFTER_ATTRIBUTE_VALUE_QUOTED,
        SELF_CLOSING_START_TAG:
      parse_error EOF_IN_TAG
      emit_eof
    of BOGUS_COMMENT:
      emit_tok
      emit_eof
    of MARKUP_DECLARATION_OPEN:
      parse_error INCORRECTLY_OPENED_COMMENT
      new_token Token[Atom](t: COMMENT)
      reconsume_in BOGUS_COMMENT
    of COMMENT_START:
      reconsume_in COMMENT
    of COMMENT_START_DASH, COMMENT:
      parse_error EOF_IN_COMMENT
      emit_tok
      emit_eof
    of COMMENT_LESS_THAN_SIGN, COMMENT_LESS_THAN_SIGN_BANG:
      reconsume_in COMMENT
    of COMMENT_LESS_THAN_SIGN_BANG_DASH:
      reconsume_in COMMENT_END_DASH
    of COMMENT_LESS_THAN_SIGN_BANG_DASH_DASH:
      reconsume_in COMMENT_END
    of COMMENT_END_DASH, COMMENT_END, COMMENT_END_BANG:
      parse_error EOF_IN_COMMENT
      emit_tok
      emit_eof
    of DOCTYPE, BEFORE_DOCTYPE_NAME:
      parse_error EOF_IN_DOCTYPE
      new_token Token[Atom](t: DOCTYPE, quirks: true)
      emit_tok
      emit_eof
    of DOCTYPE_NAME, AFTER_DOCTYPE_NAME, AFTER_DOCTYPE_PUBLIC_KEYWORD,
        BEFORE_DOCTYPE_PUBLIC_IDENTIFIER,
        DOCTYPE_PUBLIC_IDENTIFIER_DOUBLE_QUOTED,
        DOCTYPE_PUBLIC_IDENTIFIER_SINGLE_QUOTED,
        AFTER_DOCTYPE_PUBLIC_IDENTIFIER,
        BETWEEN_DOCTYPE_PUBLIC_AND_SYSTEM_IDENTIFIERS,
        AFTER_DOCTYPE_SYSTEM_KEYWORD, BEFORE_DOCTYPE_SYSTEM_IDENTIFIER,
        DOCTYPE_SYSTEM_IDENTIFIER_DOUBLE_QUOTED,
        DOCTYPE_SYSTEM_IDENTIFIER_SINGLE_QUOTED,
        AFTER_DOCTYPE_SYSTEM_IDENTIFIER:
      parse_error EOF_IN_DOCTYPE
      tokenizer.tok.quirks = true
      emit_tok
      emit_eof
    of BOGUS_DOCTYPE:
      emit_tok
      emit_eof
    of CDATA_SECTION:
      parse_error EOF_IN_CDATA
      emit_eof
    of CDATA_SECTION_BRACKET:
      emit ']'
      reconsume_in CDATA_SECTION
    of CDATA_SECTION_END:
      emit "]]"
      reconsume_in CDATA_SECTION
    of CHARACTER_REFERENCE:
      tokenizer.tmp = "&"
      flush_code_points_consumed_as_a_character_reference
      reconsume_in tokenizer.rstate
    of NAMED_CHARACTER_REFERENCE:
      # No match for EOF
      flush_code_points_consumed_as_a_character_reference
      switch_state AMBIGUOUS_AMPERSAND_STATE
    of AMBIGUOUS_AMPERSAND_STATE:
      reconsume_in tokenizer.rstate
    of NUMERIC_CHARACTER_REFERENCE:
      reconsume_in DECIMAL_CHARACTER_REFERENCE_START
    of HEXADECIMAL_CHARACTER_REFERENCE_START, DECIMAL_CHARACTER_REFERENCE_START:
      parse_error ABSENCE_OF_DIGITS_IN_NUMERIC_CHARACTER_REFERENCE
      flush_code_points_consumed_as_a_character_reference
      reconsume_in tokenizer.rstate
    of HEXADECIMAL_CHARACTER_REFERENCE, DECIMAL_CHARACTER_REFERENCE:
      parse_error MISSING_SEMICOLON_AFTER_CHARACTER_REFERENCE
      reconsume_in NUMERIC_CHARACTER_REFERENCE_END
    of NUMERIC_CHARACTER_REFERENCE_END:
      tokenizer.numericCharacterReferenceEndState()
      reconsume_in tokenizer.rstate # we unnecessarily consumed once so reconsume

  #TODO it would be nice to have one yield only, but then we would have to
  # move the entire atEnd thing in the while loop...
  for tok in tokenizer.tokqueue:
    yield tok
