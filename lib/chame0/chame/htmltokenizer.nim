{.experimental: "overloadableEnums".}

import std/tables

import dombuilder
import entity_gen
import tags

type TokenizerState* = enum
  tsData, tsCharacterReference, tsTagOpen, tsRcdata, tsRcdataLessThanSign,
  tsRawtext, tsRawtextLessThanSign, tsScriptData, tsScriptDataLessThanSign,
  tsPlaintext, tsMarkupDeclarationOpen, tsEndTagOpen, tsBogusComment,
  tsTagName, tsBeforeAttributeName, tsRcdataEndTagOpen, tsRcdataEndTagName,
  tsRawtextEndTagOpen, tsRawtextEndTagName, tsSelfClosingStartTag,
  tsScriptDataEndTagOpen, tsScriptDataEscapeStart, tsScriptDataEscapeStartDash,
  tsScriptDataEscapedDashDash, tsScriptDataEndTagName, tsScriptDataEscaped,
  tsScriptDataEscapedDash, tsScriptDataEscapedLessThanSign,
  tsScriptDataEscapedEndTagOpen, tsScriptDataDoubleEscapeStart,
  tsScriptDataEscapedEndTagName, tsScriptDataDoubleEscaped,
  tsScriptDataDoubleEscapedDash, tsScriptDataDoubleEscapedLessThanSign,
  tsScriptDataDoubleEscapedDashDash, tsScriptDataDoubleEscapeEnd,
  tsAfterAttributeName, tsAttributeName, tsBeforeAttributeValue,
  tsAttributeValueQuoted, tsAttributeValueUnquoted,
  tsAfterAttributeValueQuoted, tsCommentStart, tsCdataSection,
  tsCommentStartDash, tsComment, tsCommentEnd, tsCommentLessThanSign,
  tsCommentEndDash, tsCommentLessThanSignBang, tsCommentLessThanSignBangDash,
  tsCommentLessThanSignBangDashDash, tsCommentEndBang,
  tsDoctype, tsBeforeDoctypeName, tsDoctypeName, tsAfterDoctypeName,
  tsAfterDoctypePublicKeyword, tsAfterDoctypeSystemKeyword,
  tsBeforeDoctypeSystemIdentifier, tsBogusDoctype,
  tsBeforeDoctypePublicIdentifier, tsDoctypePublicIdentifierQuoted,
  tsAfterDoctypePublicIdentifier, tsBetweenDoctypePublicAndSystemIdentifiers,
  tsDoctypeSystemIdentifierQuoted, tsAfterDoctypeSystemIdentifier,
  tsCdataSectionBracket, tsCdataSectionEnd, tsNamedCharacterReference,
  tsNumericCharacterReference, tsAmbiguousAmpersand,
  tsHexadecimalCharacterReferenceStart, tsHexadecimalCharacterReference,
  tsDecimalCharacterReference

type
  Tokenizer*[Handle, Atom] = object
    dombuilder*: DOMBuilder[Handle, Atom]
    # temporary buffer (mentioned by the standard, but also used for attribute
    # names)
    tmp: string
    tok: Token[Atom] # current token to be emitted
    attrValue: string # buffer for attribute values
    startTag*: Atom # last start tag
    attrName: Atom # atom representing attrn after the attribute name is closed
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
    attrs*: seq[ParsedAttr[Atom]]
    charbuf: string # buffer for character tokens
    tagNameBuf*: string # buffer for storing the tag name & doctype name
    peekBuf: array[64, char] # a stack with the last element at peekBufLen - 1
    peekBufLen: int
    inputBufIdx*: int # last character consumed in input buf

  TokenType* = enum
    ttDoctype, ttStartTag, ttEndTag, ttComment, ttCharacter, ttWhitespace,
    ttNull

  TokenFlag* = enum
    tfQuirks, tfPubid, tfSysid, tfSelfClosing

  Token*[Atom] = ref object
    tagname*: Atom
    flags*: set[TokenFlag]
    case t*: TokenType
    of ttCharacter, ttWhitespace, ttComment:
      s*: string
    of ttNull, ttStartTag, ttEndTag, ttDoctype: discard

const AsciiUpperAlpha = {'A'..'Z'}
const AsciiLowerAlpha = {'a'..'z'}
const AsciiAlpha = (AsciiUpperAlpha + AsciiLowerAlpha)
const AsciiDigit = {'0'..'9'}
const AsciiAlphaNumeric = AsciiAlpha + AsciiDigit
const AsciiWhitespace = {' ', '\n', '\r', '\t', '\f'}

proc toLowerAscii(c: char): char {.inline.} =
  if c in AsciiUpperAlpha:
    result = char(uint8(c) xor 0x20'u8)
  else:
    result = c

proc strToAtom[Handle, Atom](tokenizer: Tokenizer[Handle, Atom];
    s: string): Atom =
  mixin strToAtomImpl
  return tokenizer.dombuilder.strToAtomImpl(s)

proc initTokenizer*[Handle, Atom](dombuilder: DOMBuilder[Handle, Atom]):
    Tokenizer[Handle, Atom] =
  Tokenizer[Handle, Atom](dombuilder: dombuilder)

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

const AttributeStates = {
  tsAttributeValueQuoted, tsAttributeValueUnquoted
}

proc consumedAsAttribute(tokenizer: Tokenizer): bool =
  return tokenizer.rstate in AttributeStates

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

proc appendAttrOrEmit(tokenizer: var Tokenizer; s: string) =
  if tokenizer.consumedAsAttribute():
    tokenizer.attrValue &= s
  else:
    for c in s:
      tokenizer.emit(c)

proc appendAttrOrEmit(tokenizer: var Tokenizer; c: char) =
  if tokenizer.consumedAsAttribute():
    tokenizer.attrValue &= c
  else:
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

proc flushAttr[Handle, Atom](tokenizer: var Tokenizer[Handle, Atom]) =
  # This can also be called with tok.t == ttEndTag, in that case we do
  # not want to flush attributes.
  if tokenizer.tok.t == ttStartTag and tokenizer.attr:
    tokenizer.attrs.add(ParsedAttr[Atom](name: tokenizer.attrName))
    tokenizer.attrs[^1].value = move(tokenizer.attrValue)

proc flushAttrs[Handle, Atom](tokenizer: var Tokenizer[Handle, Atom]) =
  mixin sortAttrsImpl
  tokenizer.flushAttr()
  if tokenizer.tok.t == ttStartTag and tokenizer.attr:
    tokenizer.dombuilder.sortAttrsImpl(tokenizer.attrs)

proc startNewAttribute(tokenizer: var Tokenizer) =
  tokenizer.flushAttr()
  tokenizer.tmp = ""
  tokenizer.attrValue = ""
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

proc flushStartTagName[Handle, Atom](tokenizer: var Tokenizer[Handle, Atom]) =
  let tagName = tokenizer.strToAtom(tokenizer.tagNameBuf)
  tokenizer.tok.tagname = tagName
  tokenizer.startTag = tagName

proc flushEndTagName(tokenizer: var Tokenizer) =
  tokenizer.tok.tagname = tokenizer.strToAtom(tokenizer.tagNameBuf)

proc emitTmp(tokenizer: var Tokenizer) =
  if tokenizer.isws:
    tokenizer.flushChars()
  tokenizer.charbuf &= "</"
  tokenizer.charbuf &= tokenizer.tmp

template startTagMatches(tokenizer: Tokenizer): bool =
  tokenizer.startTag == tokenizer.tok.tagname

# if true, redo
proc tokenizeEOF[Handle, Atom](tokenizer: var Tokenizer[Handle, Atom]): bool =
  tokenizer.tokqueue.setLen(0)
  if tokenizer.isws:
    tokenizer.flushChars()
  case tokenizer.state
  of tsTagOpen, tsRcdataLessThanSign, tsRawtextLessThanSign,
      tsScriptDataLessThanSign, tsScriptDataEscapedLessThanSign:
    tokenizer.charbuf &= '<'
  of tsEndTagOpen, tsRcdataEndTagOpen, tsRawtextEndTagOpen,
      tsScriptDataEndTagOpen, tsScriptDataEscapedEndTagOpen:
    tokenizer.charbuf &= "</"
  of tsRcdataEndTagName, tsRawtextEndTagName, tsScriptDataEndTagName,
      tsScriptDataEscapedEndTagName:
    tokenizer.emitTmp()
  of tsBogusComment, tsBogusDoctype, tsCommentEndDash, tsCommentEnd,
      tsCommentEndBang, tsCommentLessThanSignBangDash,
      tsCommentLessThanSignBangDashDash, tsCommentStartDash, tsComment,
      tsCommentStart, tsCommentLessThanSign, tsCommentLessThanSignBang:
    tokenizer.tokqueue.add(tokenizer.tok)
  of tsMarkupDeclarationOpen:
    tokenizer.tokqueue.add(Token[Atom](t: ttComment))
  of tsDoctype, tsBeforeDoctypeName:
    tokenizer.tagNameBuf = ""
    tokenizer.tokqueue.add(Token[Atom](t: ttDoctype, flags: {tfQuirks}))
  of tsDoctypeName, tsAfterDoctypeName, tsAfterDoctypePublicKeyword,
      tsBeforeDoctypePublicIdentifier, tsDoctypePublicIdentifierQuoted,
      tsAfterDoctypePublicIdentifier,
      tsBetweenDoctypePublicAndSystemIdentifiers,
      tsAfterDoctypeSystemKeyword, tsBeforeDoctypeSystemIdentifier,
      tsDoctypeSystemIdentifierQuoted, tsAfterDoctypeSystemIdentifier:
    tokenizer.tok.flags.incl(tfQuirks)
    tokenizer.tokqueue.add(tokenizer.tok)
  of tsCdataSectionBracket:
    tokenizer.charbuf &= ']'
  of tsCdataSectionEnd:
    tokenizer.charbuf &= "]]"
  of tsCharacterReference:
    tokenizer.appendAttrOrEmit('&')
    tokenizer.state = tokenizer.rstate
    return true
  of tsAmbiguousAmpersand:
    tokenizer.state = tokenizer.rstate
    return true
  of tsNamedCharacterReference, tsHexadecimalCharacterReferenceStart,
      tsNumericCharacterReference:
    tokenizer.appendAttrOrEmit(tokenizer.tmp)
    tokenizer.state = tokenizer.rstate
    return true
  of tsHexadecimalCharacterReference, tsDecimalCharacterReference:
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
    if tokenizer.isws:
      tokenizer.flushChars()
    tokenizer.charbuf &= s
  template emit(ch: char) =
    tokenizer.emit(ch)
  template emit_null =
    tokenizer.flushChars()
    tokenizer.tokqueue.add(Token[Atom](t: ttNull))
  template emit_tok =
    tokenizer.tokqueue.add(tokenizer.tok)
  template emit_replacement = emit "\uFFFD"
  template switch_state(s: TokenizerState) =
    tokenizer.state = s
  template switch_state_return(s: TokenizerState) =
    tokenizer.rstate = tokenizer.state
    tokenizer.state = s

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
    of tsData:
      case c
      of '&': switch_state_return tsCharacterReference
      of '<': switch_state tsTagOpen
      of '\0': emit_null
      else: emit c

    of tsRcdata:
      case c
      of '&': switch_state_return tsCharacterReference
      of '<': switch_state tsRcdataLessThanSign
      of '\0': emit_replacement
      else: emit c

    of tsRawtext:
      case c
      of '<': switch_state tsRawtextLessThanSign
      of '\0': emit_replacement
      else: emit c

    of tsScriptData:
      case c
      of '<': switch_state tsScriptDataLessThanSign
      of '\0': emit_replacement
      else: emit c

    of tsPlaintext:
      case c
      of '\0': emit_replacement
      else: emit c

    of tsTagOpen:
      case c
      of '!': switch_state tsMarkupDeclarationOpen
      of '/': switch_state tsEndTagOpen
      of AsciiAlpha:
        tokenizer.flushChars()
        tokenizer.tok = Token[Atom](t: ttStartTag)
        tokenizer.attrs.setLen(0)
        tokenizer.attr = false
        tokenizer.tagNameBuf = $c.toLowerAscii()
        # note: was reconsume
        switch_state tsTagName
      of '?':
        tokenizer.flushChars()
        tokenizer.tok = Token[Atom](t: ttComment, s: "?")
        # note: was reconsume
        switch_state tsBogusComment
      else:
        emit '<'
        reconsume_in tsData

    of tsEndTagOpen:
      case c
      of AsciiAlpha:
        tokenizer.flushChars()
        tokenizer.tok = Token[Atom](t: ttEndTag)
        tokenizer.tagNameBuf = $c.toLowerAscii()
        # note: was reconsume
        switch_state tsTagName
      of '>': switch_state tsData
      else:
        tokenizer.flushChars()
        tokenizer.tok = Token[Atom](t: ttComment)
        reconsume_in tsBogusComment

    of tsTagName:
      case c
      of AsciiWhitespace:
        tokenizer.flushStartTagName()
        switch_state tsBeforeAttributeName
      of '/':
        tokenizer.flushStartTagName()
        switch_state tsSelfClosingStartTag
      of '>':
        switch_state tsData
        tokenizer.flushStartTagName()
        emit_tok
      of '\0': tokenizer.tagNameBuf &= "\uFFFD"
      else: tokenizer.tagNameBuf &= c.toLowerAscii()

    of tsRcdataLessThanSign:
      case c
      of '/':
        tokenizer.tmp = ""
        switch_state tsRcdataEndTagOpen
      else:
        emit '<'
        reconsume_in tsRcdata

    of tsRcdataEndTagOpen:
      case c
      of AsciiAlpha:
        tokenizer.flushChars()
        tokenizer.tok = Token[Atom](t: ttEndTag)
        tokenizer.tagNameBuf = $c.toLowerAscii()
        tokenizer.tmp &= c
        # note: was reconsume
        switch_state tsRcdataEndTagName
      else:
        emit "</"
        reconsume_in tsRcdata

    of tsRcdataEndTagName:
      template anything_else =
        tokenizer.emitTmp()
        reconsume_in tsRcdata
      case c
      of AsciiWhitespace:
        tokenizer.flushEndTagName()
        if tokenizer.startTagMatches():
          switch_state tsBeforeAttributeName
        else:
          anything_else
      of '/':
        tokenizer.flushEndTagName()
        if tokenizer.startTagMatches():
          switch_state tsSelfClosingStartTag
        else:
          anything_else
      of '>':
        tokenizer.flushEndTagName()
        if tokenizer.startTagMatches():
          switch_state tsData
          emit_tok
        else:
          anything_else
      of AsciiAlpha: # note: merged upper & lower
        tokenizer.tagNameBuf &= c.toLowerAscii()
        tokenizer.tmp &= c
      else:
        anything_else

    of tsRawtextLessThanSign:
      case c
      of '/':
        tokenizer.tmp = ""
        switch_state tsRawtextEndTagOpen
      else:
        emit '<'
        reconsume_in tsRawtext

    of tsRawtextEndTagOpen:
      case c
      of AsciiAlpha:
        tokenizer.flushChars()
        tokenizer.tok = Token[Atom](t: ttEndTag)
        tokenizer.tagNameBuf = $c.toLowerAscii()
        tokenizer.tmp &= c
        # note: was reconsume
        switch_state tsRawtextEndTagName
      else:
        emit "</"
        reconsume_in tsRawtext

    of tsRawtextEndTagName:
      template anything_else =
        tokenizer.emitTmp()
        reconsume_in tsRawtext
      case c
      of AsciiWhitespace:
        tokenizer.flushEndTagName()
        if tokenizer.startTagMatches():
          switch_state tsBeforeAttributeName
        else:
          anything_else
      of '/':
        tokenizer.flushEndTagName()
        if tokenizer.startTagMatches():
          switch_state tsSelfClosingStartTag
        else:
          anything_else
      of '>':
        tokenizer.flushEndTagName()
        if tokenizer.startTagMatches():
          switch_state tsData
          emit_tok
        else:
          anything_else
      of AsciiAlpha: # note: merged upper & lower
        tokenizer.tagNameBuf &= c.toLowerAscii()
        tokenizer.tmp &= c
      else:
        anything_else

    of tsScriptDataLessThanSign:
      case c
      of '/':
        tokenizer.tmp = ""
        switch_state tsScriptDataEndTagOpen
      of '!':
        switch_state tsScriptDataEscapeStart
        emit "<!"
      else:
        emit '<'
        reconsume_in tsScriptData

    of tsScriptDataEndTagOpen:
      case c
      of AsciiAlpha:
        tokenizer.flushChars()
        tokenizer.tok = Token[Atom](t: ttEndTag)
        tokenizer.tagNameBuf = $c.toLowerAscii()
        tokenizer.tmp &= c
        # note: was reconsume
        switch_state tsScriptDataEndTagName
      else:
        emit "</"
        reconsume_in tsScriptData

    of tsScriptDataEndTagName:
      template anything_else =
        tokenizer.emitTmp()
        reconsume_in tsScriptData
      case c
      of AsciiWhitespace:
        tokenizer.flushEndTagName()
        if tokenizer.startTagMatches():
          switch_state tsBeforeAttributeName
        else:
          anything_else
      of '/':
        tokenizer.flushEndTagName()
        if tokenizer.startTagMatches():
          switch_state tsSelfClosingStartTag
        else:
          anything_else
      of '>':
        tokenizer.flushEndTagName()
        if tokenizer.startTagMatches():
          switch_state tsData
          emit_tok
        else:
          anything_else
      of AsciiAlpha: # note: merged upper & lower
        tokenizer.tagNameBuf &= c.toLowerAscii()
        tokenizer.tmp &= c
      else:
        anything_else

    of tsScriptDataEscapeStart, tsScriptDataEscapeStartDash:
      case c
      of '-':
        inc tokenizer.state
        emit '-'
      else:
        reconsume_in tsScriptData

    of tsScriptDataEscaped:
      case c
      of '-':
        switch_state tsScriptDataEscapedDash
        emit '-'
      of '<': switch_state tsScriptDataEscapedLessThanSign
      of '\0': emit_replacement
      else: emit c

    of tsScriptDataEscapedDash:
      case c
      of '-':
        switch_state tsScriptDataEscapedDashDash
        emit '-'
      of '<':
        switch_state tsScriptDataEscapedLessThanSign
      of '\0':
        switch_state tsScriptDataEscaped
        emit_replacement
      else:
        switch_state tsScriptDataEscaped
        emit c

    of tsScriptDataEscapedDashDash:
      case c
      of '-':
        emit '-'
      of '<':
        switch_state tsScriptDataEscapedLessThanSign
      of '>':
        switch_state tsScriptData
        emit '>'
      of '\0':
        switch_state tsScriptDataEscaped
        emit_replacement
      else:
        switch_state tsScriptDataEscaped
        emit c

    of tsScriptDataEscapedLessThanSign:
      case c
      of '/':
        tokenizer.tmp = ""
        switch_state tsScriptDataEscapedEndTagOpen
      of AsciiAlpha:
        tokenizer.tmp = $c.toLowerAscii()
        emit '<'
        emit c
        # note: was reconsume
        switch_state tsScriptDataDoubleEscapeStart
      else:
        emit '<'
        reconsume_in tsScriptDataEscaped

    of tsScriptDataEscapedEndTagOpen:
      if c in AsciiAlpha:
        tokenizer.flushChars()
        tokenizer.tok = Token[Atom](t: ttEndTag)
        tokenizer.tagNameBuf = $c.toLowerAscii()
        tokenizer.tmp &= c
        # note: was reconsume
        switch_state tsScriptDataEscapedEndTagName
      else:
        emit "</"
        reconsume_in tsScriptDataEscaped

    of tsScriptDataEscapedEndTagName:
      template anything_else =
        tokenizer.emitTmp()
        reconsume_in tsScriptDataEscaped
      case c
      of AsciiWhitespace:
        tokenizer.flushEndTagName()
        if tokenizer.startTagMatches():
          switch_state tsBeforeAttributeName
        else:
          anything_else
      of '/':
        tokenizer.flushEndTagName()
        if tokenizer.startTagMatches():
          switch_state tsSelfClosingStartTag
        else:
          anything_else
      of '>':
        tokenizer.flushEndTagName()
        if tokenizer.startTagMatches():
          switch_state tsData
          emit_tok
        else:
          anything_else
      of AsciiAlpha:
        tokenizer.tagNameBuf &= c.toLowerAscii()
        tokenizer.tmp &= c
      else:
        anything_else

    of tsScriptDataDoubleEscapeStart:
      case c
      of AsciiWhitespace, '/', '>':
        if tokenizer.tmp == "script":
          switch_state tsScriptDataDoubleEscaped
        else:
          switch_state tsScriptDataEscaped
        emit c
      of AsciiAlpha: # note: merged upper & lower
        tokenizer.tmp &= c.toLowerAscii()
        emit c
      else: reconsume_in tsScriptDataEscaped

    of tsScriptDataDoubleEscaped:
      case c
      of '-':
        switch_state tsScriptDataDoubleEscapedDash
        emit '-'
      of '<':
        switch_state tsScriptDataDoubleEscapedLessThanSign
        emit '<'
      of '\0': emit_replacement
      else: emit c

    of tsScriptDataDoubleEscapedDash:
      case c
      of '-':
        switch_state tsScriptDataDoubleEscapedDashDash
        emit '-'
      of '<':
        switch_state tsScriptDataDoubleEscapedLessThanSign
        emit '<'
      of '\0':
        switch_state tsScriptDataDoubleEscaped
        emit_replacement
      else:
        switch_state tsScriptDataDoubleEscaped
        emit c

    of tsScriptDataDoubleEscapedDashDash:
      case c
      of '-': emit '-'
      of '<':
        switch_state tsScriptDataDoubleEscapedLessThanSign
        emit '<'
      of '>':
        switch_state tsScriptData
        emit '>'
      of '\0':
        switch_state tsScriptDataDoubleEscaped
        emit_replacement
      else:
        switch_state tsScriptDataDoubleEscaped
        emit c

    of tsScriptDataDoubleEscapedLessThanSign:
      case c
      of '/':
        tokenizer.tmp = ""
        switch_state tsScriptDataDoubleEscapeEnd
        emit '/'
      else: reconsume_in tsScriptDataDoubleEscaped

    of tsScriptDataDoubleEscapeEnd:
      case c
      of AsciiWhitespace, '/', '>':
        if tokenizer.tmp == "script":
          switch_state tsScriptDataEscaped
        else:
          switch_state tsScriptDataDoubleEscaped
        emit c
      of AsciiAlpha: # note: merged upper & lower
        tokenizer.tmp &= c.toLowerAscii()
        emit c
      else:
        reconsume_in tsScriptDataDoubleEscaped

    of tsBeforeAttributeName:
      case c
      of AsciiWhitespace: discard
      of '/': switch_state tsSelfClosingStartTag
      of '>': reconsume_in tsAfterAttributeName
      else:
        tokenizer.startNewAttribute()
        if c == '\0':
          tokenizer.tmp &= "\uFFFD"
        else:
          tokenizer.tmp &= c.toLowerAscii()
        switch_state tsAttributeName

    of tsAttributeName:
      case c
      of AsciiWhitespace, '/', '>', '=':
        tokenizer.attrName = tokenizer.strToAtom(tokenizer.tmp)
        if c == '=':
          switch_state tsBeforeAttributeValue
        else:
          reconsume_in tsAfterAttributeName
      of '\0':
        tokenizer.tmp &= "\uFFFD"
      else:
        tokenizer.tmp &= c.toLowerAscii()

    of tsAfterAttributeName:
      case c
      of AsciiWhitespace: discard
      of '/': switch_state tsSelfClosingStartTag
      of '=': switch_state tsBeforeAttributeValue
      of '>':
        switch_state tsData
        tokenizer.flushAttrs()
        emit_tok
      else:
        tokenizer.startNewAttribute()
        if c == '\0':
          tokenizer.tmp &= "\uFFFD"
        else:
          tokenizer.tmp &= c.toLowerAscii()
        switch_state tsAttributeName

    of tsBeforeAttributeValue:
      case c
      of AsciiWhitespace: discard
      of '"', '\'':
        tokenizer.quote = c
        switch_state tsAttributeValueQuoted
      of '>':
        switch_state tsData
        tokenizer.flushAttrs()
        emit_tok
      else: reconsume_in tsAttributeValueUnquoted

    of tsAttributeValueQuoted:
      case c
      of '&': switch_state_return tsCharacterReference
      of '\0': tokenizer.attrValue &= "\uFFFD"
      elif c == tokenizer.quote: switch_state tsAfterAttributeValueQuoted
      else: tokenizer.attrValue &= c

    of tsAttributeValueUnquoted:
      case c
      of AsciiWhitespace: switch_state tsBeforeAttributeName
      of '&': switch_state_return tsCharacterReference
      of '>':
        switch_state tsData
        tokenizer.flushAttrs()
        emit_tok
      of '\0': tokenizer.attrValue &= "\uFFFD"
      else: tokenizer.attrValue &= c

    of tsAfterAttributeValueQuoted:
      case c
      of AsciiWhitespace:
        switch_state tsBeforeAttributeName
      of '/':
        switch_state tsSelfClosingStartTag
      of '>':
        switch_state tsData
        tokenizer.flushAttrs()
        emit_tok
      else: reconsume_in tsBeforeAttributeName

    of tsSelfClosingStartTag:
      case c
      of '>':
        tokenizer.tok.flags.incl(tfSelfClosing)
        switch_state tsData
        tokenizer.flushAttrs()
        emit_tok
      else: reconsume_in tsBeforeAttributeName

    of tsBogusComment:
      assert tokenizer.tok.t == ttComment
      case c
      of '>':
        switch_state tsData
        emit_tok
      of '\0': tokenizer.tok.s &= "\uFFFD"
      else: tokenizer.tok.s &= c

    of tsMarkupDeclarationOpen:
      # note: rewritten to fit case model as we consume a char anyway
      template anything_else =
        tokenizer.flushChars()
        tokenizer.tok = Token[Atom](t: ttComment)
        switch_state tsBogusComment
      case c
      of '-':
        case tokenizer.eatStr(c, "-", ibuf)
        of esrSuccess:
          tokenizer.flushChars()
          tokenizer.tok = Token[Atom](t: ttComment)
          tokenizer.state = tsCommentStart
        of esrRetry: break
        of esrFail: anything_else
      of 'D', 'd':
        case tokenizer.eatStrNoCase(c, "octype", ibuf)
        of esrSuccess: switch_state tsDoctype
        of esrRetry: break
        of esrFail: anything_else
      of '[':
        case tokenizer.eatStr(c, "CDATA[", ibuf)
        of esrSuccess:
          if tokenizer.hasnonhtml:
            switch_state tsCdataSection
          else:
            tokenizer.flushChars()
            tokenizer.tok = Token[Atom](t: ttComment, s: "[CDATA[")
            switch_state tsBogusComment
        of esrRetry: break
        of esrFail: anything_else
      else:
        # eat didn't reconsume, do it ourselves
        tokenizer.reconsume(c)
        anything_else

    of tsCommentStart:
      case c
      of '-': switch_state tsCommentStartDash
      of '>':
        switch_state tsData
        emit_tok
      else: reconsume_in tsComment

    of tsCommentStartDash:
      case c
      of '-': switch_state tsCommentEnd
      of '>':
        switch_state tsData
        emit_tok
      else:
        tokenizer.tok.s &= '-'
        reconsume_in tsComment

    of tsComment:
      case c
      of '<':
        tokenizer.tok.s &= c
        switch_state tsCommentLessThanSign
      of '-': switch_state tsCommentEndDash
      of '\0': tokenizer.tok.s &= "\uFFFD"
      else: tokenizer.tok.s &= c

    of tsCommentLessThanSign:
      case c
      of '!':
        tokenizer.tok.s &= c
        switch_state tsCommentLessThanSignBang
      of '<': tokenizer.tok.s &= c
      else: reconsume_in tsComment

    of tsCommentLessThanSignBang:
      case c
      of '-': switch_state tsCommentLessThanSignBangDash
      else: reconsume_in tsComment

    of tsCommentLessThanSignBangDash:
      case c
      of '-': switch_state tsCommentLessThanSignBangDashDash
      else: reconsume_in tsCommentEndDash

    of tsCommentLessThanSignBangDashDash:
      case c
      of '>':
        # note: was reconsume (comment end)
        switch_state tsData
        emit_tok
      else: reconsume_in tsCommentEnd

    of tsCommentEndDash:
      case c
      of '-': switch_state tsCommentEnd
      else:
        tokenizer.tok.s &= '-'
        reconsume_in tsComment

    of tsCommentEnd:
      case c
      of '>':
        switch_state tsData
        emit_tok
      of '!': switch_state tsCommentEndBang
      of '-': tokenizer.tok.s &= '-'
      else:
        tokenizer.tok.s &= "--"
        reconsume_in tsComment

    of tsCommentEndBang:
      if c == '>':
        switch_state tsData
        emit_tok
      else:
        tokenizer.tok.s &= "--!"
        if c == '-':
          switch_state tsCommentEndDash
        else:
          reconsume_in tsComment

    of tsDoctype:
      if c notin AsciiWhitespace:
        tokenizer.reconsume(c)
      switch_state tsBeforeDoctypeName

    of tsBeforeDoctypeName:
      case c
      of AsciiWhitespace: discard
      of '\0':
        tokenizer.tagNameBuf = "\uFFFD"
        tokenizer.flushChars()
        tokenizer.tok = Token[Atom](t: ttDoctype)
        switch_state tsDoctypeName
      of '>':
        tokenizer.tagNameBuf = ""
        tokenizer.flushChars()
        tokenizer.tok = Token[Atom](t: ttDoctype, flags: {tfQuirks})
        switch_state tsData
        emit_tok
      else:
        tokenizer.tagNameBuf = $c.toLowerAscii()
        tokenizer.flushChars()
        tokenizer.tok = Token[Atom](t: ttDoctype)
        switch_state tsDoctypeName

    of tsDoctypeName:
      case c
      of AsciiWhitespace: switch_state tsAfterDoctypeName
      of '>':
        switch_state tsData
        emit_tok
      of '\0': tokenizer.tagNameBuf &= "\uFFFD"
      else: tokenizer.tagNameBuf &= c.toLowerAscii()

    of tsAfterDoctypeName: # note: rewritten to fit case model as we consume a char anyway
      template anything_else =
        tokenizer.tok.flags.incl(tfQuirks)
        switch_state tsBogusDoctype
      case c
      of AsciiWhitespace: discard
      of '>':
        switch_state tsData
        emit_tok
      of 'p', 'P':
        case tokenizer.eatStrNoCase(c, "ublic", ibuf)
        of esrSuccess: switch_state tsAfterDoctypePublicKeyword
        of esrRetry: break
        of esrFail: anything_else
      of 's', 'S':
        case tokenizer.eatStrNoCase(c, "ystem", ibuf)
        of esrSuccess:
          tokenizer.tagNameBuf &= '\0' # pubid is empty
          switch_state tsAfterDoctypeSystemKeyword
        of esrRetry: break
        of esrFail: anything_else
      else:
        # eat didn't reconsume, do it ourselves
        tokenizer.reconsume(c)
        anything_else

    of tsAfterDoctypePublicKeyword:
      case c
      of AsciiWhitespace: switch_state tsBeforeDoctypePublicIdentifier
      of '"', '\'':
        tokenizer.tok.flags.incl(tfPubid)
        tokenizer.quote = c
        tokenizer.tagNameBuf &= '\0'
        switch_state tsDoctypePublicIdentifierQuoted
      of '>':
        tokenizer.tok.flags.incl(tfQuirks)
        switch_state tsData
        emit_tok
      else:
        tokenizer.tok.flags.incl(tfQuirks)
        reconsume_in tsBogusDoctype

    of tsBeforeDoctypePublicIdentifier:
      case c
      of AsciiWhitespace: discard
      of '"', '\'':
        tokenizer.tok.flags.incl(tfPubid)
        tokenizer.quote = c
        tokenizer.tagNameBuf &= '\0'
        switch_state tsDoctypePublicIdentifierQuoted
      of '>':
        tokenizer.tok.flags.incl(tfQuirks)
        switch_state tsData
        emit_tok
      else:
        tokenizer.tok.flags.incl(tfQuirks)
        reconsume_in tsBogusDoctype

    of tsDoctypePublicIdentifierQuoted:
      case c
      of '\0': tokenizer.tagNameBuf &= "\uFFFD"
      of '>':
        tokenizer.tok.flags.incl(tfQuirks)
        switch_state tsData
        emit_tok
      elif c == tokenizer.quote: switch_state tsAfterDoctypePublicIdentifier
      else: tokenizer.tagNameBuf &= c

    of tsAfterDoctypePublicIdentifier:
      case c
      of AsciiWhitespace:
        switch_state tsBetweenDoctypePublicAndSystemIdentifiers
      of '>':
        switch_state tsData
        emit_tok
      of '"', '\'':
        tokenizer.tok.flags.incl(tfSysid)
        tokenizer.quote = c
        tokenizer.tagNameBuf &= '\0'
        switch_state tsDoctypeSystemIdentifierQuoted
      else:
        tokenizer.tok.flags.incl(tfQuirks)
        reconsume_in tsBogusDoctype

    of tsBetweenDoctypePublicAndSystemIdentifiers, tsAfterDoctypeSystemKeyword,
        tsBeforeDoctypeSystemIdentifier:
      case c
      of AsciiWhitespace:
        if tokenizer.state == tsAfterDoctypeSystemKeyword:
          switch_state tsBeforeDoctypeSystemIdentifier
      of '>':
        if tokenizer.state != tsBetweenDoctypePublicAndSystemIdentifiers:
          tokenizer.tok.flags.incl(tfQuirks)
        switch_state tsData
        emit_tok
      of '"', '\'':
        tokenizer.tok.flags.incl(tfSysid)
        tokenizer.quote = c
        tokenizer.tagNameBuf &= '\0'
        switch_state tsDoctypeSystemIdentifierQuoted
      else:
        tokenizer.tok.flags.incl(tfQuirks)
        reconsume_in tsBogusDoctype

    of tsDoctypeSystemIdentifierQuoted:
      case c
      of '\0': tokenizer.tagNameBuf &= "\uFFFD"
      of '>':
        tokenizer.tok.flags.incl(tfQuirks)
        switch_state tsData
        emit_tok
      elif c == tokenizer.quote: switch_state tsAfterDoctypeSystemIdentifier
      else: tokenizer.tagNameBuf &= c

    of tsAfterDoctypeSystemIdentifier:
      case c
      of AsciiWhitespace: discard
      of '>':
        switch_state tsData
        emit_tok
      else:
        switch_state tsBogusDoctype

    of tsBogusDoctype:
      if c == '>':
        emit_tok
        switch_state tsData

    of tsCdataSection:
      case c
      of ']': switch_state tsCdataSectionBracket
      of '\0':
        # "U+0000 NULL characters are handled in the tree construction stage,
        # as part of the in foreign content insertion mode, which is the only
        # place where CDATA sections can appear."
        emit_null
      else:
        emit c

    of tsCdataSectionBracket:
      if c == ']':
        switch_state tsCdataSectionEnd
      else:
        emit ']'
        reconsume_in tsCdataSection

    of tsCdataSectionEnd:
      case c
      of ']': emit ']'
      of '>': switch_state tsData
      else:
        emit "]]"
        reconsume_in tsCdataSection

    of tsCharacterReference:
      case c
      of AsciiAlpha:
        tokenizer.tmp = "&"
        reconsume_in tsNamedCharacterReference
      of '#':
        tokenizer.tmp = "&#"
        switch_state tsNumericCharacterReference
      else:
        tokenizer.appendAttrOrEmit('&')
        reconsume_in tokenizer.rstate

    of tsNamedCharacterReference:
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
        switch_state tsAmbiguousAmpersand

    of tsAmbiguousAmpersand:
      if c in AsciiAlpha:
        tokenizer.appendAttrOrEmit(c)
      else:
        reconsume_in tokenizer.rstate

    of tsNumericCharacterReference:
      tokenizer.code = 0
      case c
      of 'x', 'X':
        tokenizer.tmp &= c
        switch_state tsHexadecimalCharacterReferenceStart
      of AsciiDigit:
        tokenizer.code = uint32(c) - uint32('0')
        # note: was reconsume
        switch_state tsDecimalCharacterReference
      else:
        tokenizer.appendAttrOrEmit(tokenizer.tmp)
        reconsume_in tokenizer.rstate

    of tsHexadecimalCharacterReferenceStart:
      let c2 = c.toLowerAscii()
      case c2
      of AsciiDigit:
        tokenizer.code = uint32(c2) - uint32('0')
        # note: was reconsume
        switch_state tsHexadecimalCharacterReference
      of 'a'..'f':
        tokenizer.code = uint32(c2) - uint32('a') + 10
        # note: was reconsume
        switch_state tsHexadecimalCharacterReference
      else:
        tokenizer.appendAttrOrEmit(tokenizer.tmp)
        reconsume_in tokenizer.rstate

    of tsHexadecimalCharacterReference:
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

    of tsDecimalCharacterReference:
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
