{.experimental: "overloadableEnums".}

import std/options
import std/strutils
import std/tables

import dombuilder
import entity_gen
import tokstate

export tokstate

type
  Tokenizer*[Handle, Atom] = object
    dombuilder: DOMBuilder[Handle, Atom]
    # temporary buffer (mentioned by the standard, but also used for attribute
    # names)
    tmp: string
    tok: Token[Atom] # current token to be emitted
    laststart*: Token[Atom] # last start tag token
    attrv: string # buffer for attribute values
    attrna: Atom # atom representing attrn after the attribute name is closed
    code: uint32 # codepoint of current numeric character reference
    state*: TokenizerState
    rstate: TokenizerState # return state
    attr: bool # is there already an attr in the previous values?
    hasnonhtml*: bool # does the stack of open elements have a non-HTML node?
    ignoreLF: bool # ignore the next consumed line feed (for CRLF normalization)
    isend: bool # if consume returns -1 and isend, we are at EOF
    isws: bool # is the current character token whitespace-only?
    quote: char # dedupe states that only differ in their quoting
    tokqueue*: seq[Token[Atom]] # queue of tokens to be emitted in this iteration
    charbuf: string # buffer for character tokens
    tagNameBuf: string # buffer for storing the tag name
    peekBuf: array[64, char] # a stack with the last element at peekBufLen - 1
    peekBufLen: int
    inputBufIdx*: int # last character consumed in input buf

  TokenType* = enum
    ttDoctype, ttStartTag, ttEndTag, ttComment, ttCharacter, ttWhitespace,
    ttNull

  TokenFlag* = enum
    tfQuirks, tfPubid, tfSysid, tfSelfClosing

  Token*[Atom] = ref object
    flags*: set[TokenFlag]
    case t*: TokenType
    of ttDoctype:
      name*: string
      pubid*: string
      sysid*: string
    of ttStartTag, ttEndTag:
      tagname*: Atom
      attrs*: Table[Atom, string]
    of ttCharacter, ttWhitespace, ttComment:
      s*: string
    of ttNull: discard

const AsciiUpperAlpha = {'A'..'Z'}
const AsciiLowerAlpha = {'a'..'z'}
const AsciiAlpha = (AsciiUpperAlpha + AsciiLowerAlpha)
const AsciiDigit = {'0'..'9'}
const AsciiAlphaNumeric = AsciiAlpha + AsciiDigit
const AsciiWhitespace = {' ', '\n', '\r', '\t', '\f'}

func `$`*(tok: Token): string =
  result = $tok.t
  case tok.t
  of ttDoctype:
    result &= ' ' & tok.name & ' ' & tok.pubid & ' ' & tok.sysid
    if tfQuirks in tok.flags:
      result &= " (quirks)"
  of ttStartTag, ttEndTag:
    result &= ' ' & tok.tagname & ' ' & $tok.attrs
    if tfSelfClosing in tok.flags:
      result &= " (self-closing)"
  of ttCharacter, ttWhitespace, ttComment: result &= ' ' & tok.s
  else: discard

proc strToAtom[Handle, Atom](tokenizer: Tokenizer[Handle, Atom];
    s: string): Atom =
  mixin strToAtomImpl
  return tokenizer.dombuilder.strToAtomImpl(s)

proc newTokenizer*[Handle, Atom](dombuilder: DOMBuilder[Handle, Atom];
    initialState = DATA): Tokenizer[Handle, Atom] =
  return Tokenizer[Handle, Atom](state: initialState, dombuilder: dombuilder)

proc reconsume(tokenizer: var Tokenizer; s: openArray[char]) =
  for i in countdown(s.high, 0):
    tokenizer.peekBuf[tokenizer.peekBufLen] = s[i]
    inc tokenizer.peekBufLen

proc reconsume(tokenizer: var Tokenizer; c: char) =
  tokenizer.peekBuf[tokenizer.peekBufLen] = c
  inc tokenizer.peekBufLen

proc consume(tokenizer: var Tokenizer; ibuf: openArray[char]): int =
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
    if tokenizer.isws:
      tokenizer.tokqueue.add(Token[Atom](
        t: ttWhitespace,
        s: move(tokenizer.charbuf)
      ))
    else:
      tokenizer.tokqueue.add(Token[Atom](
        t: ttCharacter,
        s: move(tokenizer.charbuf)
      ))
    tokenizer.isws = false
    tokenizer.charbuf.setLen(0)

const AttributeStates = {
  ATTRIBUTE_VALUE_QUOTED, ATTRIBUTE_VALUE_UNQUOTED
}

func consumedAsAttribute(tokenizer: Tokenizer): bool =
  return tokenizer.rstate in AttributeStates

proc appendToAttrValue(tokenizer: var Tokenizer; s: openArray[char]) =
  if tokenizer.attr:
    for c in s:
      tokenizer.attrv &= c

proc emit(tokenizer: var Tokenizer; c: char) =
  let isws = c in AsciiWhitespace
  if tokenizer.isws != isws:
    # Emit whitespace & non-whitespace separately.
    tokenizer.flushChars()
    tokenizer.isws = isws
  tokenizer.charbuf &= c

type CharRefResult = tuple[i, ci: int, entry: cstring]

proc findCharRef(tokenizer: var Tokenizer; c: char; ibuf: openArray[char]):
    CharRefResult =
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

proc appendAttrOrEmit(tokenizer: var Tokenizer; s: openArray[char]) =
  if tokenizer.consumedAsAttribute():
    tokenizer.appendToAttrValue(s)
  else:
    for c in s:
      tokenizer.emit(c)

proc numericCharacterReferenceEndState(tokenizer: var Tokenizer) =
  const ControlMap = [
    0x20ACu16, 0, 0x201A, 0x192, 0x201E, 0x2026, 0x2020, 0x2021,
    0x2C6, 0x2030, 0x160, 0x2039, 0x152, 0, 0x17D, 0,
    0, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x2DC, 0x2122, 0x161, 0x203A, 0x153, 0, 0x17E, 0x178
  ]
  var u = tokenizer.code
  let cc = u - 0x80
  if cc < ControlMap.len and ControlMap[cc] != 0:
    u = ControlMap[cc]
  elif u == 0x00 or u > 0x10FFFF or u in 0xD800u32..0xDFFFu32:
    u = 0xFFFD
  var s = ""
  if u < 0x80:
    s = $char(u)
  elif u < 0x800:
    s = char(u shr 6 or 0xC0) &
      char(u and 0x3F or 0x80)
  elif u < 0x10000:
    s = char(u shr 12 or 0xE0) &
      char(u shr 6 and 0x3F or 0x80) &
      char(u and 0x3F or 0x80)
  else:
    s = char(u shr 18 or 0xF0) &
      char(u shr 12 and 0x3F or 0x80) &
      char(u shr 6 and 0x3F or 0x80) &
      char(u and 0x3F or 0x80)
  tokenizer.appendAttrOrEmit(s)

proc flushAttr(tokenizer: var Tokenizer) =
  # This can also be called with tok.t == ttEndTag, in that case we do
  # not want to flush attributes.
  if tokenizer.tok.t == ttStartTag and tokenizer.attr:
    tokenizer.tok.attrs[tokenizer.attrna] = move(tokenizer.attrv)

proc startNewAttribute(tokenizer: var Tokenizer) =
  tokenizer.flushAttr()
  tokenizer.tmp = ""
  tokenizer.attrv = ""
  tokenizer.attr = true

type EatStrResult = enum
  esrFail, esrSuccess, esrRetry

proc eatStr(tokenizer: var Tokenizer, c: char, s, ibuf: openArray[char]):
    EatStrResult =
  var cs = $c
  for c in s:
    let n = tokenizer.consume(ibuf)
    if n != -1:
      cs &= cast[char](n)
    if n != int(c):
      tokenizer.reconsume(cs)
      if n == -1 and not tokenizer.isend:
        return esrRetry
      return esrFail
  return esrSuccess

proc eatStrNoCase(tokenizer: var Tokenizer; c: char; s, ibuf: openArray[char]):
    EatStrResult =
  var cs = $c
  for c in s:
    let n = tokenizer.consume(ibuf)
    if n != -1:
      cs &= cast[char](n)
    if n == -1 or cast[char](n).toLowerAscii() != c:
      tokenizer.reconsume(cs)
      if n == -1 and not tokenizer.isend:
        return esrRetry
      return esrFail
  return esrSuccess

proc flushTagName(tokenizer: var Tokenizer) =
  tokenizer.tok.tagname = tokenizer.strToAtom(tokenizer.tagNameBuf)

proc emitTmp(tokenizer: var Tokenizer) =
  if tokenizer.isws:
    tokenizer.flushChars()
  tokenizer.charbuf &= "</"
  tokenizer.charbuf &= tokenizer.tmp

# if true, redo
proc tokenizeEOF[Handle, Atom](tokenizer: var Tokenizer[Handle, Atom]): bool =
  tokenizer.tokqueue.setLen(0)
  if tokenizer.isws:
    tokenizer.flushChars()
  case tokenizer.state
  of TAG_OPEN, RCDATA_LESS_THAN_SIGN, RAWTEXT_LESS_THAN_SIGN,
      SCRIPT_DATA_LESS_THAN_SIGN, SCRIPT_DATA_ESCAPED_LESS_THAN_SIGN:
    tokenizer.charbuf &= '<'
  of END_TAG_OPEN, RCDATA_END_TAG_OPEN, RAWTEXT_END_TAG_OPEN,
      SCRIPT_DATA_END_TAG_OPEN, SCRIPT_DATA_ESCAPED_END_TAG_OPEN:
    tokenizer.charbuf &= "</"
  of RCDATA_END_TAG_NAME, RAWTEXT_END_TAG_NAME, SCRIPT_DATA_END_TAG_NAME,
      SCRIPT_DATA_ESCAPED_END_TAG_NAME:
    tokenizer.emitTmp()
  of BOGUS_COMMENT, BOGUS_DOCTYPE, COMMENT_END_DASH,
      COMMENT_END, COMMENT_END_BANG, COMMENT_LESS_THAN_SIGN_BANG_DASH,
      COMMENT_LESS_THAN_SIGN_BANG_DASH_DASH, COMMENT_START_DASH, COMMENT,
      COMMENT_START, COMMENT_LESS_THAN_SIGN, COMMENT_LESS_THAN_SIGN_BANG:
    tokenizer.flushChars()
    tokenizer.tokqueue.add(tokenizer.tok)
  of MARKUP_DECLARATION_OPEN:
    tokenizer.flushChars()
    tokenizer.tokqueue.add(Token[Atom](t: ttComment))
  of DOCTYPE, BEFORE_DOCTYPE_NAME:
    tokenizer.flushChars()
    tokenizer.tokqueue.add(Token[Atom](t: ttDoctype, flags: {tfQuirks}))
  of DOCTYPE_NAME, AFTER_DOCTYPE_NAME, AFTER_DOCTYPE_PUBLIC_KEYWORD,
      BEFORE_DOCTYPE_PUBLIC_IDENTIFIER, DOCTYPE_PUBLIC_IDENTIFIER_QUOTED,
      AFTER_DOCTYPE_PUBLIC_IDENTIFIER,
      BETWEEN_DOCTYPE_PUBLIC_AND_SYSTEM_IDENTIFIERS,
      AFTER_DOCTYPE_SYSTEM_KEYWORD, BEFORE_DOCTYPE_SYSTEM_IDENTIFIER,
      DOCTYPE_SYSTEM_IDENTIFIER_QUOTED, AFTER_DOCTYPE_SYSTEM_IDENTIFIER:
    tokenizer.tok.flags.incl(tfQuirks)
    tokenizer.flushChars()
    tokenizer.tokqueue.add(tokenizer.tok)
  of CDATA_SECTION_BRACKET:
    tokenizer.charbuf &= ']'
  of CDATA_SECTION_END:
    tokenizer.charbuf &= "]]"
  of CHARACTER_REFERENCE:
    tokenizer.appendAttrOrEmit("&")
    tokenizer.state = tokenizer.rstate
    return true
  of AMBIGUOUS_AMPERSAND_STATE:
    tokenizer.state = tokenizer.rstate
    return true
  of NAMED_CHARACTER_REFERENCE, HEXADECIMAL_CHARACTER_REFERENCE_START,
      NUMERIC_CHARACTER_REFERENCE:
    tokenizer.appendAttrOrEmit(tokenizer.tmp)
    tokenizer.state = tokenizer.rstate
    return true
  of HEXADECIMAL_CHARACTER_REFERENCE, DECIMAL_CHARACTER_REFERENCE:
    tokenizer.numericCharacterReferenceEndState()
    # we unnecessarily consumed once so reconsume
    tokenizer.state = tokenizer.rstate
    return true
  else: discard
  tokenizer.flushChars()
  false

type TokenizeResult* = enum
  trDone, trEmit

proc tokenize*[Handle, Atom](tokenizer: var Tokenizer[Handle, Atom];
    ibuf: openArray[char]): TokenizeResult =
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
    tokenizer.tokqueue.add(Token[Atom](t: ttNull))
  template emit_tok =
    tokenizer.flushChars()
    tokenizer.tokqueue.add(tokenizer.tok)
  template emit_replacement = emit "\uFFFD"
  template switch_state(s: TokenizerState) =
    tokenizer.state = s
  template switch_state_return(s: TokenizerState) =
    tokenizer.rstate = tokenizer.state
    tokenizer.state = s
  template is_appropriate_end_tag_token(): bool =
    tokenizer.laststart != nil and
      tokenizer.laststart.tagname == tokenizer.tok.tagname
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
        new_token Token[Atom](t: ttStartTag)
        tokenizer.laststart = tokenizer.tok
        tokenizer.tagNameBuf = $c.toLowerAscii()
        # note: was reconsume
        switch_state TAG_NAME
      of '?':
        new_token Token[Atom](t: ttComment, s: "?")
        # note: was reconsume
        switch_state BOGUS_COMMENT
      else:
        emit '<'
        reconsume_in DATA

    of END_TAG_OPEN:
      case c
      of AsciiAlpha:
        new_token Token[Atom](t: ttEndTag)
        tokenizer.tagNameBuf = $c.toLowerAscii()
        # note: was reconsume
        switch_state TAG_NAME
      of '>': switch_state DATA
      else:
        new_token Token[Atom](t: ttComment)
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
      of '\0': tokenizer.tagNameBuf &= "\uFFFD"
      else: tokenizer.tagNameBuf &= c.toLowerAscii()

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
        new_token Token[Atom](t: ttEndTag)
        tokenizer.tagNameBuf = $c.toLowerAscii()
        tokenizer.tmp &= c
        # note: was reconsume
        switch_state RCDATA_END_TAG_NAME
      else:
        emit "</"
        reconsume_in RCDATA

    of RCDATA_END_TAG_NAME:
      template anything_else =
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
        new_token Token[Atom](t: ttEndTag)
        tokenizer.tagNameBuf = $c.toLowerAscii()
        tokenizer.tmp &= c
        # note: was reconsume
        switch_state RAWTEXT_END_TAG_NAME
      else:
        emit "</"
        reconsume_in RAWTEXT

    of RAWTEXT_END_TAG_NAME:
      template anything_else =
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
        new_token Token[Atom](t: ttEndTag)
        tokenizer.tagNameBuf = $c.toLowerAscii()
        tokenizer.tmp &= c
        # note: was reconsume
        switch_state SCRIPT_DATA_END_TAG_NAME
      else:
        emit "</"
        reconsume_in SCRIPT_DATA

    of SCRIPT_DATA_END_TAG_NAME:
      template anything_else =
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
      if c in AsciiAlpha:
        new_token Token[Atom](t: ttEndTag)
        tokenizer.tagNameBuf = $c.toLowerAscii()
        tokenizer.tmp &= c
        # note: was reconsume
        switch_state SCRIPT_DATA_ESCAPED_END_TAG_NAME
      else:
        emit "</"
        reconsume_in SCRIPT_DATA_ESCAPED

    of SCRIPT_DATA_ESCAPED_END_TAG_NAME:
      template anything_else =
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
      of '/': switch_state SELF_CLOSING_START_TAG
      of '>': reconsume_in AFTER_ATTRIBUTE_NAME
      else:
        tokenizer.startNewAttribute()
        if c == '\0':
          tokenizer.tmp &= "\uFFFD"
        else:
          tokenizer.tmp &= c.toLowerAscii()
        switch_state ATTRIBUTE_NAME

    of ATTRIBUTE_NAME:
      template leave_attribute_name_state =
        tokenizer.attrna = tokenizer.strToAtom(tokenizer.tmp)
        if tokenizer.attrna in tokenizer.tok.attrs:
          tokenizer.attr = false
      case c
      of AsciiWhitespace, '/', '>':
        leave_attribute_name_state
        reconsume_in AFTER_ATTRIBUTE_NAME
      of '=':
        leave_attribute_name_state
        switch_state BEFORE_ATTRIBUTE_VALUE
      of '\0':
        tokenizer.tmp &= "\uFFFD"
      else:
        tokenizer.tmp &= c.toLowerAscii()

    of AFTER_ATTRIBUTE_NAME:
      case c
      of AsciiWhitespace: discard
      of '/': switch_state SELF_CLOSING_START_TAG
      of '=': switch_state BEFORE_ATTRIBUTE_VALUE
      of '>':
        switch_state DATA
        tokenizer.flushAttr()
        emit_tok
      else:
        tokenizer.startNewAttribute()
        if c == '\0':
          tokenizer.tmp &= "\uFFFD"
        else:
          tokenizer.tmp &= c.toLowerAscii()
        switch_state ATTRIBUTE_NAME

    of BEFORE_ATTRIBUTE_VALUE:
      case c
      of AsciiWhitespace: discard
      of '"', '\'':
        tokenizer.quote = c
        switch_state ATTRIBUTE_VALUE_QUOTED
      of '>':
        switch_state DATA
        tokenizer.flushAttr()
        emit_tok
      else: reconsume_in ATTRIBUTE_VALUE_UNQUOTED

    of ATTRIBUTE_VALUE_QUOTED:
      case c
      of '&': switch_state_return CHARACTER_REFERENCE
      of '\0': tokenizer.appendToAttrValue("\uFFFD")
      elif c == tokenizer.quote: switch_state AFTER_ATTRIBUTE_VALUE_QUOTED
      else: tokenizer.appendToAttrValue([c])

    of ATTRIBUTE_VALUE_UNQUOTED:
      case c
      of AsciiWhitespace: switch_state BEFORE_ATTRIBUTE_NAME
      of '&': switch_state_return CHARACTER_REFERENCE
      of '>':
        switch_state DATA
        tokenizer.flushAttr()
        emit_tok
      of '\0': tokenizer.appendToAttrValue("\uFFFD")
      else: tokenizer.appendToAttrValue([c])

    of AFTER_ATTRIBUTE_VALUE_QUOTED:
      case c
      of AsciiWhitespace:
        switch_state BEFORE_ATTRIBUTE_NAME
      of '/':
        switch_state SELF_CLOSING_START_TAG
      of '>':
        switch_state DATA
        tokenizer.flushAttr()
        emit_tok
      else: reconsume_in BEFORE_ATTRIBUTE_NAME

    of SELF_CLOSING_START_TAG:
      case c
      of '>':
        tokenizer.tok.flags.incl(tfSelfClosing)
        switch_state DATA
        tokenizer.flushAttr()
        emit_tok
      else: reconsume_in BEFORE_ATTRIBUTE_NAME

    of BOGUS_COMMENT:
      assert tokenizer.tok.t == ttComment
      case c
      of '>':
        switch_state DATA
        emit_tok
      of '\0': tokenizer.tok.s &= "\uFFFD"
      else: tokenizer.tok.s &= c

    of MARKUP_DECLARATION_OPEN: # note: rewritten to fit case model as we consume a char anyway
      template anything_else =
        new_token Token[Atom](t: ttComment)
        switch_state BOGUS_COMMENT
      case c
      of '-':
        case tokenizer.eatStr(c, "-", ibuf)
        of esrSuccess:
          new_token Token[Atom](t: ttComment)
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
            new_token Token[Atom](t: ttComment, s: "[CDATA[")
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
        tokenizer.tok.s &= '-'
        reconsume_in COMMENT

    of COMMENT:
      case c
      of '<':
        tokenizer.tok.s &= c
        switch_state COMMENT_LESS_THAN_SIGN
      of '-': switch_state COMMENT_END_DASH
      of '\0': tokenizer.tok.s &= "\uFFFD"
      else: tokenizer.tok.s &= c

    of COMMENT_LESS_THAN_SIGN:
      case c
      of '!':
        tokenizer.tok.s &= c
        switch_state COMMENT_LESS_THAN_SIGN_BANG
      of '<': tokenizer.tok.s &= c
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
        tokenizer.tok.s &= '-'
        reconsume_in COMMENT

    of COMMENT_END:
      case c
      of '>':
        switch_state DATA
        emit_tok
      of '!': switch_state COMMENT_END_BANG
      of '-': tokenizer.tok.s &= '-'
      else:
        tokenizer.tok.s &= "--"
        reconsume_in COMMENT

    of COMMENT_END_BANG:
      if c == '>':
        switch_state DATA
        emit_tok
      else:
        tokenizer.tok.s &= "--!"
        if c == '-':
          switch_state COMMENT_END_DASH
        else:
          reconsume_in COMMENT

    of DOCTYPE:
      if c notin AsciiWhitespace:
        tokenizer.reconsume(c)
      switch_state BEFORE_DOCTYPE_NAME

    of BEFORE_DOCTYPE_NAME:
      case c
      of AsciiWhitespace: discard
      of '\0':
        new_token Token[Atom](t: ttDoctype, name: "\uFFFD")
        switch_state DOCTYPE_NAME
      of '>':
        new_token Token[Atom](t: ttDoctype, flags: {tfQuirks})
        switch_state DATA
        emit_tok
      else:
        new_token Token[Atom](t: ttDoctype, name: $c.toLowerAscii())
        switch_state DOCTYPE_NAME

    of DOCTYPE_NAME:
      case c
      of AsciiWhitespace: switch_state AFTER_DOCTYPE_NAME
      of '>':
        switch_state DATA
        emit_tok
      of '\0': tokenizer.tok.name &= "\uFFFD"
      else: tokenizer.tok.name &= c.toLowerAscii()

    of AFTER_DOCTYPE_NAME: # note: rewritten to fit case model as we consume a char anyway
      template anything_else =
        tokenizer.tok.flags.incl(tfQuirks)
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
      of '"', '\'':
        tokenizer.tok.flags.incl(tfPubid)
        tokenizer.quote = c
        switch_state DOCTYPE_PUBLIC_IDENTIFIER_QUOTED
      of '>':
        tokenizer.tok.flags.incl(tfQuirks)
        switch_state DATA
        emit_tok
      else:
        tokenizer.tok.flags.incl(tfQuirks)
        reconsume_in BOGUS_DOCTYPE

    of BEFORE_DOCTYPE_PUBLIC_IDENTIFIER:
      case c
      of AsciiWhitespace: discard
      of '"', '\'':
        tokenizer.tok.flags.incl(tfPubid)
        tokenizer.quote = c
        switch_state DOCTYPE_PUBLIC_IDENTIFIER_QUOTED
      of '>':
        tokenizer.tok.flags.incl(tfQuirks)
        switch_state DATA
        emit_tok
      else:
        tokenizer.tok.flags.incl(tfQuirks)
        reconsume_in BOGUS_DOCTYPE

    of DOCTYPE_PUBLIC_IDENTIFIER_QUOTED:
      case c
      of '\0': tokenizer.tok.pubid &= "\uFFFD"
      of '>':
        tokenizer.tok.flags.incl(tfQuirks)
        switch_state DATA
        emit_tok
      elif c == tokenizer.quote: switch_state AFTER_DOCTYPE_PUBLIC_IDENTIFIER
      else: tokenizer.tok.pubid &= c

    of AFTER_DOCTYPE_PUBLIC_IDENTIFIER:
      case c
      of AsciiWhitespace:
        switch_state BETWEEN_DOCTYPE_PUBLIC_AND_SYSTEM_IDENTIFIERS
      of '>':
        switch_state DATA
        emit_tok
      of '"', '\'':
        tokenizer.tok.flags.incl(tfSysid)
        tokenizer.quote = c
        switch_state DOCTYPE_SYSTEM_IDENTIFIER_QUOTED
      else:
        tokenizer.tok.flags.incl(tfQuirks)
        reconsume_in BOGUS_DOCTYPE

    of BETWEEN_DOCTYPE_PUBLIC_AND_SYSTEM_IDENTIFIERS:
      case c
      of AsciiWhitespace: discard
      of '>':
        switch_state DATA
        emit_tok
      of '"', '\'':
        tokenizer.tok.flags.incl(tfSysid)
        tokenizer.quote = c
        switch_state DOCTYPE_SYSTEM_IDENTIFIER_QUOTED
      else:
        tokenizer.tok.flags.incl(tfQuirks)
        reconsume_in BOGUS_DOCTYPE

    of AFTER_DOCTYPE_SYSTEM_KEYWORD:
      case c
      of AsciiWhitespace: switch_state BEFORE_DOCTYPE_SYSTEM_IDENTIFIER
      of '"', '\'':
        tokenizer.tok.flags.incl(tfSysid)
        tokenizer.quote = c
        switch_state DOCTYPE_SYSTEM_IDENTIFIER_QUOTED
      of '>':
        tokenizer.tok.flags.incl(tfQuirks)
        switch_state DATA
        emit_tok
      else:
        tokenizer.tok.flags.incl(tfQuirks)
        reconsume_in BOGUS_DOCTYPE

    of BEFORE_DOCTYPE_SYSTEM_IDENTIFIER:
      case c
      of AsciiWhitespace: discard
      of '"', '\'':
        tokenizer.tok.flags.incl(tfSysid)
        tokenizer.quote = c
        switch_state DOCTYPE_SYSTEM_IDENTIFIER_QUOTED
      of '>':
        tokenizer.tok.flags.incl(tfQuirks)
        switch_state DATA
        emit_tok
      else:
        tokenizer.tok.flags.incl(tfQuirks)
        reconsume_in BOGUS_DOCTYPE

    of DOCTYPE_SYSTEM_IDENTIFIER_QUOTED:
      case c
      of '\0': tokenizer.tok.sysid &= "\uFFFD"
      of '>':
        tokenizer.tok.flags.incl(tfQuirks)
        switch_state DATA
        emit_tok
      elif c == tokenizer.quote: switch_state AFTER_DOCTYPE_SYSTEM_IDENTIFIER
      else: tokenizer.tok.sysid &= c

    of AFTER_DOCTYPE_SYSTEM_IDENTIFIER:
      case c
      of AsciiWhitespace: discard
      of '>':
        switch_state DATA
        emit_tok
      else:
        switch_state BOGUS_DOCTYPE

    of BOGUS_DOCTYPE:
      if c == '>':
        emit_tok
        switch_state DATA

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
      if c == ']':
        switch_state CDATA_SECTION_END
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
        tokenizer.appendAttrOrEmit("&")
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
        let sc = tokenizer.consumedAsAttribute() and tokenizer.tmp[^1] != ';'
        if sc and n != -1 and cast[char](n) in {'='} + AsciiAlphaNumeric:
          tokenizer.reconsume(cast[char](n))
          tokenizer.appendAttrOrEmit(tokenizer.tmp)
          switch_state tokenizer.rstate
        elif sc and n == -1 and not tokenizer.isend:
          # We have to redo the above check.
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
          tokenizer.appendAttrOrEmit(tokenizer.tmp)
          switch_state tokenizer.rstate
      else:
        tokenizer.appendAttrOrEmit(tokenizer.tmp)
        switch_state AMBIGUOUS_AMPERSAND_STATE

    of AMBIGUOUS_AMPERSAND_STATE:
      if c in AsciiAlpha:
        tokenizer.appendAttrOrEmit([c])
      else:
        reconsume_in tokenizer.rstate

    of NUMERIC_CHARACTER_REFERENCE:
      tokenizer.code = 0
      case c
      of 'x', 'X':
        tokenizer.tmp &= c
        switch_state HEXADECIMAL_CHARACTER_REFERENCE_START
      of AsciiDigit:
        tokenizer.code = uint32(c) - uint32('0')
        # note: was reconsume
        switch_state DECIMAL_CHARACTER_REFERENCE
      else:
        tokenizer.appendAttrOrEmit(tokenizer.tmp)
        reconsume_in tokenizer.rstate

    of HEXADECIMAL_CHARACTER_REFERENCE_START:
      let c2 = c.toLowerAscii()
      case c2
      of AsciiDigit:
        tokenizer.code = uint32(c2) - uint32('0')
        # note: was reconsume
        switch_state HEXADECIMAL_CHARACTER_REFERENCE
      of 'a'..'f':
        tokenizer.code = uint32(c2) - uint32('a') + 10
        # note: was reconsume
        switch_state HEXADECIMAL_CHARACTER_REFERENCE
      else:
        tokenizer.appendAttrOrEmit(tokenizer.tmp)
        reconsume_in tokenizer.rstate

    of HEXADECIMAL_CHARACTER_REFERENCE:
      let c2 = c.toLowerAscii()
      case c2
      of AsciiDigit:
        if tokenizer.code <= 0x10FFFF:
          tokenizer.code *= 0x10
          tokenizer.code += uint32(c2) - uint32('0')
      of 'a'..'f':
        if tokenizer.code <= 0x10FFFF:
          tokenizer.code *= 0x10
          tokenizer.code += uint32(c2) - uint32('a') + 10
      else:
        if c != ';':
          tokenizer.reconsume(c)
        tokenizer.numericCharacterReferenceEndState()
        switch_state tokenizer.rstate

    of DECIMAL_CHARACTER_REFERENCE:
      if c in AsciiDigit:
        if tokenizer.code <= 0x10FFFF:
          tokenizer.code *= 10
          tokenizer.code += uint32(c) - uint32('0')
      else:
        if c != ';':
          tokenizer.reconsume(c)
        tokenizer.numericCharacterReferenceEndState()
        switch_state tokenizer.rstate

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
