{.experimental: "overloadableEnums".}

import std/options
import std/strformat
import std/strutils
import std/tables
import std/unicode

import dombuilder
import entity_gen
import tokstate

export tokstate

type
  Tokenizer*[Handle, Atom] = object
    dombuilder: DOMBuilder[Handle, Atom]
    state*: TokenizerState
    rstate: TokenizerState # return state
    # temporary buffer (mentioned by the standard, but also used for attribute
    # names)
    tmp: string
    code: uint32 # codepoint of current numeric character reference
    tok: Token[Atom] # current token to be emitted
    laststart*: Token[Atom] # last start tag token
    attrna: Atom # atom representing attrn after the attribute name is closed
    attrv: string # buffer for attribute values
    attr: bool # is there already an attr in the previous values?
    hasnonhtml*: bool # does the stack of open elements have a non-HTML node?
    tokqueue*: seq[Token[Atom]] # queue of tokens to be emitted in this iteration
    charbuf: string # buffer for character tokens
    tagNameBuf: string # buffer for storing the tag name
    peekBuf: array[64, char] # a stack with the last element at peekBufLen - 1
    peekBufLen: int
    inputBufIdx*: int # last character consumed in input buf
    ignoreLF: bool # ignore the next consumed line feed (for CRLF normalization)
    isend: bool # if consume returns -1 and isend, we are at EOF
    isws: bool # is the current character token whitespace-only?

  TokenType* = enum
    DOCTYPE, START_TAG, END_TAG, COMMENT, CHARACTER, CHARACTER_WHITESPACE,
    CHARACTER_NULL, EOF

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

const C0Controls = {chr(0x00)..chr(0x1F)}
const Controls = (C0Controls + {chr(0x7F)})
const AsciiUpperAlpha = {'A'..'Z'}
const AsciiLowerAlpha = {'a'..'z'}
const AsciiAlpha = (AsciiUpperAlpha + AsciiLowerAlpha)
const AsciiDigit = {'0'..'9'}
const AsciiAlphaNumeric = AsciiAlpha + AsciiDigit
const AsciiWhitespace = {' ', '\n', '\r', '\t', '\f'}

func `$`*(tok: Token): string =
  case tok.t
  of DOCTYPE: fmt"{tok.t} {tok.name} {tok.pubid} {tok.sysid} {tok.quirks}"
  of START_TAG, END_TAG: fmt"{tok.t} {tok.tagname} {tok.selfclosing} {tok.attrs}"
  of CHARACTER, CHARACTER_WHITESPACE: $tok.t & " " & tok.s
  of CHARACTER_NULL: $tok.t
  of COMMENT: fmt"{tok.t} {tok.data}"
  of EOF: fmt"{tok.t}"

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

proc reconsume(tokenizer: var Tokenizer, s: openArray[char]) =
  for i in countdown(s.high, 0):
    tokenizer.peekBuf[tokenizer.peekBufLen] = s[i]
    inc tokenizer.peekBufLen

proc reconsume(tokenizer: var Tokenizer, c: char) =
  tokenizer.peekBuf[tokenizer.peekBufLen] = c
  inc tokenizer.peekBufLen

proc consume(tokenizer: var Tokenizer, ibuf: openArray[char]): int =
  if tokenizer.peekBufLen > 0:
    dec tokenizer.peekBufLen
    return int(tokenizer.peekBuf[tokenizer.peekBufLen])
  if tokenizer.inputBufIdx >= ibuf.len:
    return -1
  var c = ibuf[tokenizer.inputBufIdx]
  inc tokenizer.inputBufIdx
  if tokenizer.ignoreLF:
    if c == '\n':
      if tokenizer.inputBufIdx >= ibuf.len:
        return -1
      c = ibuf[tokenizer.inputBufIdx]
      inc tokenizer.inputBufIdx
    tokenizer.ignoreLF = false
  if c == '\r':
    tokenizer.ignoreLF = true
    c = '\n'
  return int(c)

proc flushChars[Handle, Atom](tokenizer: var Tokenizer[Handle, Atom]) =
  if tokenizer.charbuf.len > 0:
    let token = if not tokenizer.isws:
      Token[Atom](t: CHARACTER, s: tokenizer.charbuf)
    else:
      Token[Atom](t: CHARACTER_WHITESPACE, s: tokenizer.charbuf)
    tokenizer.tokqueue.add(token)
    tokenizer.isws = false
    tokenizer.charbuf.setLen(0)

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

type CharRefResult = tuple[i, ci: int, entry: cstring]

proc findCharRef(tokenizer: var Tokenizer, c: char,
    ibuf: openArray[char]): CharRefResult =
  var i = charMap[c]
  if i == -1:
    return (0, 0, nil)
  tokenizer.tmp &= c
  var entry = entityMap[i]
  var ci = 1
  let oc = c
  while entry != nil and entry[ci] != ':':
    let n = tokenizer.consume(ibuf)
    if n == -1 and not tokenizer.isend:
      # We must retry at the next iteration :/
      #TODO it would be nice to save state in this case
      return (-1, 0, nil)
    if n != int(entry[ci]):
      entry = nil
      # i is not the right entry.
      while entry == nil:
        if i == 0:
          # See below; we avoid flushing the last character consumed by
          # decrementing `ci'.
          dec ci
          break
        dec i
        entry = entityMap[i]
        if oc != entry[0]:
          # Out of entries that start with the character `oc'; give up.
          # We must not flush the last character consumed as a character
          # reference, since it is not a prefix of any entry (and can indeed be
          # markup; e.g. in the case of `&g<'), so decrement `ci' here.
          dec ci
          entry = nil
          break
        var j = 1
        while j < tokenizer.tmp.len - 1:
          if entry[j] == ':':
            # Full match: entry is a prefix of the previous entry we inspected.
            break
          if tokenizer.tmp[j + 1] != entry[j]:
            # Characters consumed until now are not a prefix of entry.
            # Try the next one instead.
            entry = nil
            break
          inc j
        if entry != nil:
          if entry[j] == ':':
            # Full match: make sure the outer loop exits.
            ci = j - 1
          elif int(entry[j]) == n:
            # Partial match, *including c*. (This is never reached with n == -1)
            ci = j
          else:
            # Continue with the loop.
            # If entry is set to non-nil after this iteration, then ci will
            # also be set appropriately.
            # Otherwise, if entry remains nil, ci will point to the first
            # non-matching character in tmp; this will be reconsumed.
            entry = nil
    if n != -1:
      tokenizer.tmp &= cast[char](n)
    inc ci
  return (i, ci, entry)

proc numericCharacterReferenceEndState(tokenizer: var Tokenizer) =
  var c = tokenizer.code
  if c == 0x00 or c > 0x10FFFF or c in 0xD800u32..0xDFFFu32:
    c = 0xFFFD
  elif c in 0xFDD0u32..0xFDEFu32 or (c and 0xFFFF) in 0xFFFEu32..0xFFFFu32:
    discard # noncharacter, do nothing
  elif c < 0x80 and char(c) in (Controls - AsciiWhitespace) + {char(0x0D)}:
    discard # control, do nothing
  elif c in 0x80u32 .. 0x9Fu32:
    const ControlMapTable = [
      0x80_00_20ACu32, 0x82_00_201Au32, 0x83_00_0192u32, 0x84_00_201Eu32,
      0x85_00_2026u32, 0x86_00_2020u32, 0x87_00_2021u32, 0x88_00_02C6u32,
      0x89_00_2030u32, 0x8A_00_0160u32, 0x8B_00_2039u32, 0x8C_00_0152u32,
      0x8E_00_017Du32, 0x91_00_2018u32, 0x92_00_2019u32, 0x93_00_201Cu32,
      0x94_00_201Du32, 0x95_00_2022u32, 0x96_00_2013u32, 0x97_00_2014u32,
      0x98_00_02DCu32, 0x99_00_2122u32, 0x9A_00_0161u32, 0x9B_00_203Au32,
      0x9C_00_0153u32, 0x9E_00_017Eu32, 0x9F_00_0178u32,
    ]
    for it in ControlMapTable:
      if it shr 24 == c:
        c = it and 0xFFFF
        break
  let s = $Rune(c)
  if tokenizer.consumedAsAnAttribute():
    tokenizer.appendToCurrentAttrValue(s)
  else:
    for c in s:
      tokenizer.emit(c)

proc flushAttr(tokenizer: var Tokenizer) =
  tokenizer.tok.attrs[tokenizer.attrna] = tokenizer.attrv

type EatStrResult = enum
  esrFail, esrSuccess, esrRetry

proc eatStr(tokenizer: var Tokenizer, c: char, s: string,
    ibuf: openArray[char]): EatStrResult =
  var cs = $c
  for i in 0 ..< s.len:
    let n = tokenizer.consume(ibuf)
    if n != -1:
      cs &= cast[char](n)
    if n != int(s[i]):
      tokenizer.reconsume(cs)
      if n == -1 and not tokenizer.isend:
        return esrRetry
      return esrFail
  return esrSuccess

proc eatStrNoCase0(tokenizer: var Tokenizer, c: char, s: string,
    ibuf: openArray[char]): EatStrResult =
  var cs = $c
  for i in 0 ..< s.len:
    let n = tokenizer.consume(ibuf)
    if n != -1:
      cs &= cast[char](n)
    if n == -1 or cast[char](n).toLowerAscii() != s[i]:
      tokenizer.reconsume(cs)
      if n == -1 and not tokenizer.isend:
        return esrRetry
      return esrFail
  return esrSuccess

# convenience template for eatStrNoCase0 (to make sure it's called correctly)
template eatStrNoCase(tokenizer: var Tokenizer, c: char, s: static string,
    ibuf: openArray[char]): EatStrResult =
  const s0 = s.toLowerAscii()
  tokenizer.eatStrNoCase0(c, s0, ibuf)

proc flushTagName(tokenizer: var Tokenizer) =
  tokenizer.tok.tagname = tokenizer.strToAtom(tokenizer.tagNameBuf)

proc emitTmp(tokenizer: var Tokenizer) =
  for c in tokenizer.tmp:
    tokenizer.emit(c)

proc flushCodePointsConsumedAsCharRef(tokenizer: var Tokenizer) =
  if tokenizer.consumedAsAnAttribute():
    tokenizer.appendToCurrentAttrValue(tokenizer.tmp)
  else:
    tokenizer.emitTmp()

# if true, redo
proc tokenizeEOF[Handle, Atom](tokenizer: var Tokenizer[Handle, Atom]): bool =
  template emit(tok: Token) =
    tokenizer.flushChars()
    tokenizer.tokqueue.add(tok)
  template reconsume_in(s: TokenizerState) =
    tokenizer.state = s
    return true
  template emit(ch: char) =
    tokenizer.emit(ch)
  template emit(s: static string) =
    static:
      doAssert AsciiWhitespace notin s
    if tokenizer.isws:
      tokenizer.flushChars()
    tokenizer.charbuf &= s

  tokenizer.tokqueue.setLen(0)

  case tokenizer.state
  of TAG_OPEN, RCDATA_LESS_THAN_SIGN, RAWTEXT_LESS_THAN_SIGN,
      SCRIPT_DATA_LESS_THAN_SIGN, SCRIPT_DATA_ESCAPED_LESS_THAN_SIGN:
    emit '<'
  of END_TAG_OPEN, RCDATA_END_TAG_OPEN, RAWTEXT_END_TAG_OPEN,
      SCRIPT_DATA_END_TAG_OPEN, SCRIPT_DATA_ESCAPED_END_TAG_OPEN:
    emit "</"
  of RCDATA_END_TAG_NAME, RAWTEXT_END_TAG_NAME, SCRIPT_DATA_END_TAG_NAME,
      SCRIPT_DATA_ESCAPED_END_TAG_NAME:
    emit "</"
    tokenizer.emitTmp()
  of BOGUS_COMMENT, BOGUS_DOCTYPE, COMMENT_END_DASH,
      COMMENT_END, COMMENT_END_BANG, COMMENT_LESS_THAN_SIGN_BANG_DASH,
      COMMENT_LESS_THAN_SIGN_BANG_DASH_DASH, COMMENT_START_DASH, COMMENT,
      COMMENT_START, COMMENT_LESS_THAN_SIGN, COMMENT_LESS_THAN_SIGN_BANG:
    emit tokenizer.tok
  of MARKUP_DECLARATION_OPEN:
    # note: was reconsume (bogus comment)
    emit Token[Atom](t: COMMENT)
  of DOCTYPE, BEFORE_DOCTYPE_NAME:
    emit Token[Atom](t: DOCTYPE, quirks: true)
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
    tokenizer.tok.quirks = true
    emit tokenizer.tok
  of CDATA_SECTION_BRACKET:
    emit ']'
    # note: was reconsume (CDATA section)
  of CDATA_SECTION_END:
    emit "]]"
    # note: was reconsume (CDATA section)
  of CHARACTER_REFERENCE:
    tokenizer.tmp = "&"
    tokenizer.flushCodePointsConsumedAsCharRef()
    reconsume_in tokenizer.rstate
  of NAMED_CHARACTER_REFERENCE:
    # No match for EOF
    tokenizer.flushCodePointsConsumedAsCharRef()
    # note: was switch state (ambiguous ampersand state)
    reconsume_in tokenizer.rstate
  of AMBIGUOUS_AMPERSAND_STATE:
    reconsume_in tokenizer.rstate
  of HEXADECIMAL_CHARACTER_REFERENCE_START, DECIMAL_CHARACTER_REFERENCE_START,
      NUMERIC_CHARACTER_REFERENCE:
    tokenizer.flushCodePointsConsumedAsCharRef()
    reconsume_in tokenizer.rstate
  of HEXADECIMAL_CHARACTER_REFERENCE, DECIMAL_CHARACTER_REFERENCE,
      NUMERIC_CHARACTER_REFERENCE_END:
    tokenizer.numericCharacterReferenceEndState()
    # we unnecessarily consumed once so reconsume
    reconsume_in tokenizer.rstate
  else: discard
  tokenizer.flushChars()
  false

type TokenizeResult* = enum
  trDone, trEmit

proc tokenize*[Handle, Atom](tokenizer: var Tokenizer[Handle, Atom],
    ibuf: openArray[char]): TokenizeResult =
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
  template prepare_attrs_if_start =
    if tokenizer.tok.t == START_TAG and tokenizer.attr and
        tokenizer.tmp != "":
      tokenizer.flushAttr()
  template emit_tok =
    emit tokenizer.tok
  template emit_replacement = emit "\uFFFD"
  template switch_state(s: TokenizerState) =
    tokenizer.state = s
  template switch_state_return(s: TokenizerState) =
    tokenizer.rstate = tokenizer.state
    tokenizer.state = s
  template is_appropriate_end_tag_token(): bool =
    tokenizer.laststart != nil and
      tokenizer.laststart.tagname == tokenizer.tok.tagname
  template start_new_attribute =
    if tokenizer.tok.t == START_TAG and tokenizer.attr:
      # This can also be called with tok.t == END_TAG, in that case we do
      # not want to flush attributes.
      tokenizer.flushAttr()
    tokenizer.tmp = ""
    tokenizer.attrv = ""
    tokenizer.attr = true
  template leave_attribute_name_state =
    tokenizer.attrna = tokenizer.strToAtom(tokenizer.tmp)
    if tokenizer.attrna in tokenizer.tok.attrs:
      tokenizer.attr = false
  template new_token(t: Token) =
    tokenizer.attr = false
    tokenizer.tok = t

  tokenizer.tokqueue.setLen(0)

  while true:
    if tokenizer.tokqueue.len > 0:
      return trEmit
    let n = tokenizer.consume(ibuf)
    if n == -1:
      break # trDone
    let c = cast[char](n)
    template reconsume_in(s: TokenizerState) =
      tokenizer.reconsume(c)
      switch_state s

    case tokenizer.state
    of DATA:
      case c
      of '&': switch_state_return CHARACTER_REFERENCE
      of '<': switch_state TAG_OPEN
      of '\0': emit_null
      else: emit c

    of RCDATA:
      case c
      of '&': switch_state_return CHARACTER_REFERENCE
      of '<': switch_state RCDATA_LESS_THAN_SIGN
      of '\0': emit_replacement
      else: emit c

    of RAWTEXT:
      case c
      of '<': switch_state RAWTEXT_LESS_THAN_SIGN
      of '\0': emit_replacement
      else: emit c

    of SCRIPT_DATA:
      case c
      of '<': switch_state SCRIPT_DATA_LESS_THAN_SIGN
      of '\0': emit_replacement
      else: emit c

    of PLAINTEXT:
      case c
      of '\0': emit_replacement
      else: emit c

    of TAG_OPEN:
      case c
      of '!': switch_state MARKUP_DECLARATION_OPEN
      of '/': switch_state END_TAG_OPEN
      of AsciiAlpha:
        new_token Token[Atom](t: START_TAG)
        tokenizer.tagNameBuf = $c.toLowerAscii()
        # note: was reconsume
        switch_state TAG_NAME
      of '?':
        new_token Token[Atom](t: COMMENT, data: "?")
        # note: was reconsume
        switch_state BOGUS_COMMENT
      else:
        emit '<'
        reconsume_in DATA

    of END_TAG_OPEN:
      case c
      of AsciiAlpha:
        new_token Token[Atom](t: END_TAG)
        tokenizer.tagNameBuf = $c.toLowerAscii()
        # note: was reconsume
        switch_state TAG_NAME
      of '>': switch_state DATA
      else:
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
      of '\0': tokenizer.tagNameBuf &= "\uFFFD"
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
        tokenizer.tagNameBuf = $c.toLowerAscii()
        tokenizer.tmp &= c
        # note: was reconsume
        switch_state RCDATA_END_TAG_NAME
      else:
        emit "</"
        reconsume_in RCDATA

    of RCDATA_END_TAG_NAME:
      template anything_else =
        emit "</"
        tokenizer.emitTmp()
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
        tokenizer.tagNameBuf = $c.toLowerAscii()
        tokenizer.tmp &= c
        # note: was reconsume
        switch_state RAWTEXT_END_TAG_NAME
      else:
        emit "</"
        reconsume_in RAWTEXT

    of RAWTEXT_END_TAG_NAME:
      template anything_else =
        emit "</"
        tokenizer.emitTmp()
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
        tokenizer.tagNameBuf = $c.toLowerAscii()
        tokenizer.tmp &= c
        # note: was reconsume
        switch_state SCRIPT_DATA_END_TAG_NAME
      else:
        emit "</"
        reconsume_in SCRIPT_DATA

    of SCRIPT_DATA_END_TAG_NAME:
      template anything_else =
        emit "</"
        tokenizer.emitTmp()
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
      of '<': switch_state SCRIPT_DATA_ESCAPED_LESS_THAN_SIGN
      of '\0': emit_replacement
      else: emit c

    of SCRIPT_DATA_ESCAPED_DASH:
      case c
      of '-':
        switch_state SCRIPT_DATA_ESCAPED_DASH_DASH
        emit '-'
      of '<':
        switch_state SCRIPT_DATA_ESCAPED_LESS_THAN_SIGN
      of '\0':
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
        tokenizer.tmp = $c.toLowerAscii()
        emit '<'
        emit c
        # note: was reconsume
        switch_state SCRIPT_DATA_DOUBLE_ESCAPE_START
      else:
        emit '<'
        reconsume_in SCRIPT_DATA_ESCAPED

    of SCRIPT_DATA_ESCAPED_END_TAG_OPEN:
      case c
      of AsciiAlpha:
        new_token Token[Atom](t: END_TAG)
        tokenizer.tagNameBuf = $c.toLowerAscii()
        tokenizer.tmp &= c
        # note: was reconsume
        switch_state SCRIPT_DATA_ESCAPED_END_TAG_NAME
      else:
        emit "</"
        reconsume_in SCRIPT_DATA_ESCAPED

    of SCRIPT_DATA_ESCAPED_END_TAG_NAME:
      template anything_else =
        emit "</"
        tokenizer.emitTmp()
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
      of '\0': emit_replacement
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
        start_new_attribute
        tokenizer.tmp &= c
        switch_state ATTRIBUTE_NAME
      else:
        start_new_attribute
        reconsume_in ATTRIBUTE_NAME

    of ATTRIBUTE_NAME:
      case c
      of AsciiWhitespace, '/', '>':
        leave_attribute_name_state
        reconsume_in AFTER_ATTRIBUTE_NAME
      of '=':
        leave_attribute_name_state
        switch_state BEFORE_ATTRIBUTE_VALUE
      of AsciiUpperAlpha:
        tokenizer.tmp &= c.toLowerAscii()
      of '\0':
        tokenizer.tmp &= "\uFFFD"
      else:
        tokenizer.tmp &= c

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
        switch_state DATA
        prepare_attrs_if_start
        emit_tok
      else: reconsume_in ATTRIBUTE_VALUE_UNQUOTED

    of ATTRIBUTE_VALUE_DOUBLE_QUOTED:
      case c
      of '"': switch_state AFTER_ATTRIBUTE_VALUE_QUOTED
      of '&': switch_state_return CHARACTER_REFERENCE
      of '\0': tokenizer.appendToCurrentAttrValue("\uFFFD")
      else: tokenizer.appendToCurrentAttrValue(c)

    of ATTRIBUTE_VALUE_SINGLE_QUOTED:
      case c
      of '\'': switch_state AFTER_ATTRIBUTE_VALUE_QUOTED
      of '&': switch_state_return CHARACTER_REFERENCE
      of '\0': tokenizer.appendToCurrentAttrValue("\uFFFD")
      else: tokenizer.appendToCurrentAttrValue(c)

    of ATTRIBUTE_VALUE_UNQUOTED:
      case c
      of AsciiWhitespace: switch_state BEFORE_ATTRIBUTE_NAME
      of '&': switch_state_return CHARACTER_REFERENCE
      of '>':
        switch_state DATA
        prepare_attrs_if_start
        emit_tok
      of '\0': tokenizer.appendToCurrentAttrValue("\uFFFD")
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
      else: reconsume_in BEFORE_ATTRIBUTE_NAME

    of SELF_CLOSING_START_TAG:
      case c
      of '>':
        tokenizer.tok.selfclosing = true
        switch_state DATA
        prepare_attrs_if_start
        emit_tok
      else: reconsume_in BEFORE_ATTRIBUTE_NAME

    of BOGUS_COMMENT:
      assert tokenizer.tok.t == COMMENT
      case c
      of '>':
        switch_state DATA
        emit_tok
      of '\0': tokenizer.tok.data &= "\uFFFD"
      else: tokenizer.tok.data &= c

    of MARKUP_DECLARATION_OPEN: # note: rewritten to fit case model as we consume a char anyway
      template anything_else =
        new_token Token[Atom](t: COMMENT)
        switch_state BOGUS_COMMENT
      case c
      of '-':
        case tokenizer.eatStr(c, "-", ibuf)
        of esrSuccess:
          new_token Token[Atom](t: COMMENT)
          tokenizer.state = COMMENT_START
        of esrRetry: break
        of esrFail: anything_else
      of 'D', 'd':
        case tokenizer.eatStrNoCase(c, "octype", ibuf)
        of esrSuccess: switch_state DOCTYPE
        of esrRetry: break
        of esrFail: anything_else
      of '[':
        case tokenizer.eatStr(c, "CDATA[", ibuf)
        of esrSuccess:
          if tokenizer.hasnonhtml:
            switch_state CDATA_SECTION
          else:
            new_token Token[Atom](t: COMMENT, data: "[CDATA[")
            switch_state BOGUS_COMMENT
        of esrRetry: break
        of esrFail: anything_else
      else:
        # eat didn't reconsume, do it ourselves
        tokenizer.reconsume(c)
        anything_else

    of COMMENT_START:
      case c
      of '-': switch_state COMMENT_START_DASH
      of '>':
        switch_state DATA
        emit_tok
      else: reconsume_in COMMENT

    of COMMENT_START_DASH:
      case c
      of '-': switch_state COMMENT_END
      of '>':
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
      of '\0': tokenizer.tok.data &= "\uFFFD"
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
      of '>':
        # note: was reconsume (comment end)
        switch_state DATA
        emit_tok
      else: reconsume_in COMMENT_END

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
        switch_state DATA
        emit_tok
      else:
        tokenizer.tok.data &= "--!"
        reconsume_in COMMENT

    of DOCTYPE:
      case c
      of AsciiWhitespace: switch_state BEFORE_DOCTYPE_NAME
      of '>': reconsume_in BEFORE_DOCTYPE_NAME
      else: reconsume_in BEFORE_DOCTYPE_NAME

    of BEFORE_DOCTYPE_NAME:
      case c
      of AsciiWhitespace: discard
      of AsciiUpperAlpha:
        new_token Token[Atom](t: DOCTYPE, name: some($c.toLowerAscii()))
        switch_state DOCTYPE_NAME
      of '\0':
        new_token Token[Atom](t: DOCTYPE, name: some($"\uFFFD"))
        switch_state DOCTYPE_NAME
      of '>':
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
      of AsciiUpperAlpha: tokenizer.tok.name.get &= c.toLowerAscii()
      of '\0': tokenizer.tok.name.get &= "\uFFFD"
      else: tokenizer.tok.name.get &= c

    of AFTER_DOCTYPE_NAME: # note: rewritten to fit case model as we consume a char anyway
      template anything_else =
        tokenizer.tok.quirks = true
        switch_state BOGUS_DOCTYPE
      case c
      of AsciiWhitespace: discard
      of '>':
        switch_state DATA
        emit_tok
      of 'p', 'P':
        case tokenizer.eatStrNoCase(c, "ublic", ibuf)
        of esrSuccess: switch_state AFTER_DOCTYPE_PUBLIC_KEYWORD
        of esrRetry: break
        of esrFail: anything_else
      of 's', 'S':
        case tokenizer.eatStrNoCase(c, "ystem", ibuf)
        of esrSuccess: switch_state AFTER_DOCTYPE_SYSTEM_KEYWORD
        of esrRetry: break
        of esrFail: anything_else
      else:
        # eat didn't reconsume, do it ourselves
        tokenizer.reconsume(c)
        anything_else

    of AFTER_DOCTYPE_PUBLIC_KEYWORD:
      case c
      of AsciiWhitespace: switch_state BEFORE_DOCTYPE_PUBLIC_IDENTIFIER
      of '"':
        tokenizer.tok.pubid = some("")
        switch_state DOCTYPE_PUBLIC_IDENTIFIER_DOUBLE_QUOTED
      of '\'':
        tokenizer.tok.pubid = some("")
        switch_state DOCTYPE_PUBLIC_IDENTIFIER_SINGLE_QUOTED
      of '>':
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      else:
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
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      else:
        tokenizer.tok.quirks = true
        reconsume_in BOGUS_DOCTYPE

    of DOCTYPE_PUBLIC_IDENTIFIER_DOUBLE_QUOTED:
      case c
      of '"': switch_state AFTER_DOCTYPE_PUBLIC_IDENTIFIER
      of '\0': tokenizer.tok.pubid.get &= "\uFFFD"
      of '>':
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      else: tokenizer.tok.pubid.get &= c

    of DOCTYPE_PUBLIC_IDENTIFIER_SINGLE_QUOTED:
      case c
      of '\'': switch_state AFTER_DOCTYPE_PUBLIC_IDENTIFIER
      of '\0': tokenizer.tok.pubid.get &= "\uFFFD"
      of '>':
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      else: tokenizer.tok.pubid.get &= c

    of AFTER_DOCTYPE_PUBLIC_IDENTIFIER:
      case c
      of AsciiWhitespace:
        switch_state BETWEEN_DOCTYPE_PUBLIC_AND_SYSTEM_IDENTIFIERS
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
        tokenizer.tok.quirks = true
        reconsume_in BOGUS_DOCTYPE

    of AFTER_DOCTYPE_SYSTEM_KEYWORD:
      case c
      of AsciiWhitespace: switch_state BEFORE_DOCTYPE_SYSTEM_IDENTIFIER
      of '"':
        tokenizer.tok.sysid = some("")
        switch_state DOCTYPE_SYSTEM_IDENTIFIER_DOUBLE_QUOTED
      of '\'':
        tokenizer.tok.sysid = some("")
        switch_state DOCTYPE_SYSTEM_IDENTIFIER_SINGLE_QUOTED
      of '>':
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      else:
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
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      else:
        tokenizer.tok.quirks = true
        reconsume_in BOGUS_DOCTYPE

    of DOCTYPE_SYSTEM_IDENTIFIER_DOUBLE_QUOTED:
      case c
      of '"': switch_state AFTER_DOCTYPE_SYSTEM_IDENTIFIER
      of '\0': tokenizer.tok.sysid.get &= "\uFFFD"
      of '>':
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      else: tokenizer.tok.sysid.get &= c

    of DOCTYPE_SYSTEM_IDENTIFIER_SINGLE_QUOTED:
      case c
      of '\'': switch_state AFTER_DOCTYPE_SYSTEM_IDENTIFIER
      of '\0': tokenizer.tok.sysid.get &= "\uFFFD"
      of '>':
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
      else: reconsume_in BOGUS_DOCTYPE

    of BOGUS_DOCTYPE:
      case c
      of '>':
        switch_state DATA
        emit_tok
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
        tokenizer.flushCodePointsConsumedAsCharRef()
        reconsume_in tokenizer.rstate

    of NAMED_CHARACTER_REFERENCE:
      let (i, ci, entry) = tokenizer.findCharRef(c, ibuf)
      if entry == nil and i == -1:
        # -1 encountered without isend
        tokenizer.reconsume(tokenizer.tmp.toOpenArray(1, tokenizer.tmp.high))
        tokenizer.tmp = "&"
        break
      # Move back the pointer & shorten the buffer to the last match.
      # (Add 1, because we do not store the starting & char in entityMap,
      # but tmp starts with an &.)
      tokenizer.reconsume(tokenizer.tmp.toOpenArray(ci + 1, tokenizer.tmp.high))
      tokenizer.tmp.setLen(ci + 1)
      if entry != nil and entry[ci] == ':':
        let n = tokenizer.consume(ibuf)
        let sc = tokenizer.consumedAsAnAttribute() and tokenizer.tmp[^1] != ';'
        if sc and n != -1 and cast[char](n) in {'='} + AsciiAlphaNumeric:
          tokenizer.reconsume(cast[char](n))
          tokenizer.flushCodePointsConsumedAsCharRef()
          switch_state tokenizer.rstate
        elif sc and n == -1 and not tokenizer.isend:
          # We have to redo the above check.
          #TODO it would be great to not completely lose our state here...
          tokenizer.reconsume(tokenizer.tmp.toOpenArray(1, tokenizer.tmp.high))
          tokenizer.tmp = "&"
          break
        else:
          if n != -1:
            tokenizer.reconsume(cast[char](n))
          tokenizer.tmp = ""
          var ci = ci + 1
          while (let c = entry[ci]; c != '\0'):
            tokenizer.tmp &= c
            inc ci
          tokenizer.flushCodePointsConsumedAsCharRef()
          switch_state tokenizer.rstate
      else:
        tokenizer.flushCodePointsConsumedAsCharRef()
        switch_state AMBIGUOUS_AMPERSAND_STATE

    of AMBIGUOUS_AMPERSAND_STATE:
      case c
      of AsciiAlpha:
        if tokenizer.consumedAsAnAttribute():
          tokenizer.appendToCurrentAttrValue(c)
        else:
          emit c
      of ';': reconsume_in tokenizer.rstate
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
      of AsciiDigit:
        tokenizer.code = uint32(c) - uint32('0')
        # note: was reconsume
        switch_state HEXADECIMAL_CHARACTER_REFERENCE
      of 'a'..'f':
        tokenizer.code = uint32(c) - uint32('a') + 10
        # note: was reconsume
        switch_state HEXADECIMAL_CHARACTER_REFERENCE
      of 'A'..'F':
        tokenizer.code = uint32(c) - uint32('A') + 10
        # note: was reconsume
        switch_state HEXADECIMAL_CHARACTER_REFERENCE
      else:
        tokenizer.flushCodePointsConsumedAsCharRef()
        reconsume_in tokenizer.rstate

    of DECIMAL_CHARACTER_REFERENCE_START:
      case c
      of AsciiDigit:
        tokenizer.code = uint32(c) - uint32('0')
        # note: was reconsume
        switch_state DECIMAL_CHARACTER_REFERENCE
      else:
        tokenizer.flushCodePointsConsumedAsCharRef()
        reconsume_in tokenizer.rstate

    of HEXADECIMAL_CHARACTER_REFERENCE:
      case c
      of AsciiDigit:
        if tokenizer.code < 0x10FFFF:
          tokenizer.code *= 0x10
          tokenizer.code += uint32(c) - uint32('0')
      of 'a'..'f':
        if tokenizer.code < 0x10FFFF:
          tokenizer.code *= 0x10
          tokenizer.code += uint32(c) - uint32('a') + 10
      of 'A'..'F':
        if tokenizer.code < 0x10FFFF:
          tokenizer.code *= 0x10
          tokenizer.code += uint32(c) - uint32('A') + 10
      of ';': switch_state NUMERIC_CHARACTER_REFERENCE_END
      else: reconsume_in NUMERIC_CHARACTER_REFERENCE_END

    of DECIMAL_CHARACTER_REFERENCE:
      case c
      of AsciiDigit:
        if tokenizer.code < 0x10FFFF:
          tokenizer.code *= 10
          tokenizer.code += uint32(c) - uint32('0')
      of ';': switch_state NUMERIC_CHARACTER_REFERENCE_END
      else: reconsume_in NUMERIC_CHARACTER_REFERENCE_END

    of NUMERIC_CHARACTER_REFERENCE_END:
      tokenizer.numericCharacterReferenceEndState()
      reconsume_in tokenizer.rstate # we unnecessarily consumed once so reconsume

  return trDone

proc finish*[Handle, Atom](tokenizer: var Tokenizer[Handle, Atom]):
    TokenizeResult =
  if tokenizer.peekBufLen > 0:
    tokenizer.isend = true
    if tokenizer.tokenize([]) != trDone:
      return trEmit
  if tokenizer.tokenizeEOF():
    let r = tokenizer.tokenizeEOF()
    assert not r
  return trDone
