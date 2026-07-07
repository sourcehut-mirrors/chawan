{.experimental: "overloadableEnums".}

import dombuilder
import entity_gen
import tags

type TokenizerState* = enum
  tsData, tsTagOpen, tsCharacterReference, tsRcdata, tsRcdataLessThanSign,
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
    startTag*: Atom # last start tag
    attrName: Atom # atom representing attrn after the attribute name is closed
    tagname*: Atom
    code: uint32 # codepoint of current numeric character reference
    entityEntryIdx: int16 # index in entityMap
    entityMatchIdx: int16 # last matching index in entityMap
    state*: TokenizerState
    rstate: TokenizerState # return state
    t*: TokenType # current token's type
    next: TokenType # next token to be emitted
    attr: bool # is there already an attr in the previous values?
    hasnonhtml*: bool # does the stack of open elements have a non-HTML node?
    ignoreLF: bool # ignore the next consumed line feed (for CRLF normalization)
    isend: bool # if consume returns -1 and isend, we are at EOF
    isws: bool # is the current character token whitespace-only?
    flags*: set[TokenFlag]
    quote: char # dedupe states that only differ in their quoting
    entityNameIdx: int8 # index in entity.name
    entityMatchLen: int8 # last matching entity name length
    attrs*: seq[ParsedAttr[Atom]]
    charbuf: string # buffer for character tokens and attribute values
    charbufOut*: string # flushed chars from charbuf
    tagNameBuf*: string # buffer for storing the tag name & doctype name
    inputBufIdx*: int # last character consumed in input buf

  TokenType* = enum
    ttDoctype, ttStartTag, ttEndTag, ttComment, ttCharacter, ttWhitespace,
    ttNull

  TokenFlag* = enum
    tfQuirks, tfPubid, tfSysid, tfSelfClosing

  TokenizeResult* = enum
    trDone, trEmit

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

proc strToAtom[Handle, Atom](tok: Tokenizer[Handle, Atom];
    s: string): Atom =
  mixin strToAtomImpl
  return tok.dombuilder.strToAtomImpl(s)

proc initTokenizer*[Handle, Atom](dombuilder: DOMBuilder[Handle, Atom]):
    Tokenizer[Handle, Atom] =
  Tokenizer[Handle, Atom](
    dombuilder: dombuilder,
    entityEntryIdx: -1,
    entityMatchIdx: -1,
  )

template reconsume(tok: var Tokenizer) =
  dec tok.inputBufIdx

proc flushChars[Handle, Atom](tok: var Tokenizer[Handle, Atom]):
    TokenizeResult =
  if tok.isws:
    tok.t = ttWhitespace
  else:
    tok.t = ttCharacter
  tok.charbufOut = move(tok.charbuf)
  tok.isws = false
  trEmit

const AttributeStates = {
  tsAttributeValueQuoted, tsAttributeValueUnquoted
}

proc consumedAsAttribute(tok: Tokenizer): bool =
  tok.rstate in AttributeStates

# returns true if the search is complete, false otherwise
proc findCharRef(tok: var Tokenizer; c: char; ibuf: openArray[char]):
    bool =
  if tok.entityEntryIdx < 0:
    tok.entityEntryIdx = charMap[c]
    tok.entityMatchIdx = -1
    tok.entityNameIdx = 1
  else:
    tok.reconsume()
  var entry = entityMap[tok.entityEntryIdx].name
  block outer:
    while true:
      if entry[tok.entityNameIdx] == '\0':
        # found match; save it for when there isn't anything better
        tok.entityMatchIdx = tok.entityEntryIdx
        tok.entityMatchLen = tok.entityNameIdx
      if tok.inputBufIdx >= ibuf.len:
        if not tok.isend:
          # consume at the next iteration
          return false
        break
      let c = ibuf[tok.inputBufIdx]
      if c notin AsciiAlphaNumeric + {';'}:
        # cannot match (also guards against matching NUL in cstring)
        break
      inc tok.inputBufIdx
      if entry[tok.entityNameIdx] == c:
        # current entry matches
        inc tok.entityNameIdx
        continue
      let prev = entry
      # cycle to the next entry that could match
      while true:
        inc tok.entityEntryIdx
        if tok.entityEntryIdx >= entityMap.len:
          dec tok.entityEntryIdx
          break outer
        entry = entityMap[tok.entityEntryIdx].name
        var eci = 0
        while entry[eci] != '\0':
          if entry[eci] != prev[eci]:
            break
          inc eci
        if eci >= tok.entityNameIdx:
          if entry[tok.entityNameIdx] == c:
            # prev didn't match c, but entry does, i.e. we found a better match
            break
          # prefix match only; try next
          continue
        # out of entries
        dec tok.entityEntryIdx
        tok.reconsume()
        break outer
      inc tok.entityNameIdx
  true

proc emit(tok: var Tokenizer; c: char) =
  if c in AsciiWhitespace and not tok.isws:
    tok.charbufOut = move(tok.charbuf)
    tok.isws = true
  tok.charbuf &= c

proc appendAttrOrEmit(tok: var Tokenizer; s: openArray[char]) =
  if tok.consumedAsAttribute():
    for c in s:
      tok.charbuf &= c
  else:
    for c in s:
      tok.emit(c)

proc appendAttrOrEmit(tok: var Tokenizer; c: char) =
  if tok.consumedAsAttribute():
    tok.charbuf &= c
  else:
    tok.emit(c)

proc flushNumericCharacterReference(tok: var Tokenizer) =
  const ControlMap = [
    0x20ACu16, 0, 0x201A, 0x192, 0x201E, 0x2026, 0x2020, 0x2021,
    0x2C6, 0x2030, 0x160, 0x2039, 0x152, 0, 0x17D, 0,
    0, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x2DC, 0x2122, 0x161, 0x203A, 0x153, 0, 0x17E, 0x178
  ]
  var u = tok.code
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
  tok.appendAttrOrEmit(s)

proc flushNamedCharacterReference(tok: var Tokenizer; ibuf: openArray[char]) =
  let prev = entityMap[tok.entityEntryIdx].name
  if tok.entityMatchIdx < 0:
    # No full match found.  Restore the ampersand and the last partial
    # match.  (We don't have to reconsume because partial matches are
    # guaranteed to be alphanumeric.)
    tok.appendAttrOrEmit('&')
    tok.appendAttrOrEmit(prev.toOpenArray(0, tok.entityNameIdx - 1))
    tok.state = tsAmbiguousAmpersand
  else:
    # There is a full match.
    let matchLen = tok.entityMatchLen
    let entry = entityMap[tok.entityMatchIdx].name
    var n = int(prev[matchLen])
    var consumed = false
    if tok.entityNameIdx == tok.entityMatchLen:
      # The last partial match is the same as the last full match.
      # We must check the next char.
      n = -1
      if tok.inputBufIdx < ibuf.len:
        n = int(ibuf[tok.inputBufIdx])
        inc tok.inputBufIdx
      consumed = true
    let sc = tok.consumedAsAttribute() and entry[matchLen - 1] != ';'
    if sc and n == -1:
      # findCharRef only ever flushes entities after buffering a char.
      # So this is guaranteed to be EOF in the singly/doubly quoted
      # attribute state, meaning we have nothing to do.
      assert tok.isend
    elif sc and cast[char](n) in {'='} + AsciiAlphaNumeric:
      # There is a full match, but we're in an attribute and the character
      # reference looks like a URI component.  Restore the full match,
      # and then the last partial match.
      tok.appendAttrOrEmit('&')
      tok.appendAttrOrEmit(entry.toOpenArray(0, matchLen - 1))
      tok.appendAttrOrEmit(prev.toOpenArray(matchLen, tok.entityNameIdx - 1))
      if consumed:
        tok.reconsume()
      tok.state = tok.rstate
    else:
      # There is a full match.
      let val = entityMap[tok.entityMatchIdx]
      var code = uint32(val.unit1)
      var surrogate = false
      if code in 0xD800'u16..0xDBFF'u16:
        code = 0x10000'u32 or ((code - 0xD800) shl 10) or (val.unit2 - 0xDC00)
        surrogate = true
      tok.code = code
      tok.flushNumericCharacterReference()
      if not surrogate and val.unit2 != 0:
        tok.code = val.unit2
        tok.flushNumericCharacterReference()
      tok.appendAttrOrEmit(prev.toOpenArray(matchLen, tok.entityNameIdx - 1))
      if consumed and n != -1 and
          (entry[matchLen - 1] == ';' or n != int(';')):
        tok.reconsume()
      tok.state = tok.rstate
  tok.entityEntryIdx = -1

proc flushAttr[Handle, Atom](tok: var Tokenizer[Handle, Atom]) =
  # This can also be called with tok == ttEndTag, in that case we do
  # not want to flush attributes.
  if tok.next == ttStartTag and tok.attr:
    tok.attrs.add(ParsedAttr[Atom](name: tok.attrName))
    tok.attrs[^1].value = move(tok.charbuf)
  else:
    tok.charbuf = ""

proc flushAttrs[Handle, Atom](tok: var Tokenizer[Handle, Atom]) =
  mixin sortAttrsImpl
  tok.flushAttr()
  if tok.next == ttStartTag and tok.attr:
    tok.dombuilder.sortAttrsImpl(tok.attrs)

proc startNewAttribute(tok: var Tokenizer) =
  tok.flushAttr()
  tok.tmp = ""
  tok.charbuf = ""
  tok.isws = false
  tok.attr = true

type EatStrResult = enum
  esrFail, esrNext, esrSuccess

proc eatStr(tok: var Tokenizer; c: char; s: string; ibuf: openArray[char]):
    EatStrResult =
  if tok.tmp.len >= s.len or c != s[tok.tmp.len]:
    return esrFail
  tok.tmp &= c
  if tok.tmp.len == s.len:
    return esrSuccess
  esrNext

proc eatStrNoCase(tok: var Tokenizer; c: char; s: string;
    ibuf: openArray[char]): EatStrResult =
  if c.toLowerAscii() != s[tok.tmp.len]:
    return esrFail
  tok.tmp &= c
  if tok.tmp.len == s.len:
    return esrSuccess
  esrNext

proc flushStartTagName[Handle, Atom](tok: var Tokenizer[Handle, Atom]) =
  let tagName = tok.strToAtom(tok.tagNameBuf)
  tok.tagname = tagName
  tok.startTag = tagName

proc flushEndTagName(tok: var Tokenizer) =
  tok.tagname = tok.strToAtom(tok.tagNameBuf)

proc emitTmp(tok: var Tokenizer) =
  tok.charbuf &= "</"
  tok.charbuf &= tok.tmp

template startTagMatches(tok: Tokenizer): bool =
  tok.startTag == tok.tagname

proc tokenize*[Handle, Atom](tok: var Tokenizer[Handle, Atom];
    ibuf: openArray[char]): TokenizeResult =
  var res = trDone
  var i = tok.inputBufIdx
  assert i >= 0 # helps the compiler

  template flush_chars =
    if tok.charbuf.len > 0:
      dec i
      res = tok.flushChars()
      break
  template emit(s: static string) =
    if tok.isws:
      flush_chars
    tok.charbuf &= s
  template emit(ch: char) =
    tok.charbuf &= ch
  template emit_tok =
    tok.t = tok.next
    res = trEmit
    break
  template emit_nws(c: char) =
    if tok.isws:
      flush_chars
      tok.isws = false
    tok.charbuf &= c
  template emit_ws(c: char) =
    if not tok.isws:
      flush_chars
      tok.isws = true
    tok.charbuf &= c
  template emit_null =
    flush_chars
    tok.t = ttNull
    res = trEmit
    break
  template emit_replacement = emit "\uFFFD"
  template switch_state(s: TokenizerState) =
    tok.state = s
  template switch_state_return(s: TokenizerState) =
    tok.rstate = tok.state
    tok.state = s

  while i < ibuf.len:
    let c = ibuf[i]
    inc i
    let ignoreLF = tok.ignoreLF
    tok.ignoreLF = false
    template reconsume_in(s: TokenizerState) =
      dec i
      switch_state s
    template emit_cr() =
      tok.ignoreLF = true
      emit_ws '\n'
    template emit_lf() =
      if not ignoreLF:
        emit_ws c

    case tok.state
    of tsData, tsRcdata, tsRawtext, tsScriptData:
      case c
      of '&':
        if tok.state == tsScriptData:
          emit_nws c
        else:
          switch_state_return tsCharacterReference
      of '<':
        if tok.isws:
          flush_chars
        inc tok.state
      of '\0':
        if tok.state == tsData:
          emit_null
        else:
          emit_replacement
      of '\r': emit_cr
      of '\n': emit_lf
      of AsciiWhitespace - {'\r', '\n'}: emit_ws c
      else: emit_nws c

    of tsPlaintext:
      case c
      of '\0': emit_replacement
      of '\r': emit_cr
      of '\n': emit_lf
      of AsciiWhitespace - {'\r', '\n'}: emit_ws c
      else: emit_nws c

    of tsTagOpen:
      case c
      of '!':
        flush_chars
        tok.tmp = ""
        switch_state tsMarkupDeclarationOpen
      of '/': switch_state tsEndTagOpen
      of AsciiAlpha:
        flush_chars
        tok.next = ttStartTag
        tok.flags = {}
        tok.attrs.setLen(0)
        tok.attr = false
        tok.tagNameBuf = $c.toLowerAscii()
        # note: was reconsume
        switch_state tsTagName
      of '?':
        flush_chars
        tok.next = ttComment
        tok.tagNameBuf = "?"
        # note: was reconsume
        switch_state tsBogusComment
      else:
        emit '<'
        reconsume_in tsData

    of tsEndTagOpen:
      case c
      of AsciiAlpha:
        flush_chars
        tok.next = ttEndTag
        tok.tagNameBuf = $c.toLowerAscii()
        # note: was reconsume
        switch_state tsTagName
      of '>': switch_state tsData
      else:
        flush_chars
        tok.next = ttComment
        tok.tagNameBuf = ""
        reconsume_in tsBogusComment

    of tsTagName:
      case c
      of AsciiWhitespace:
        tok.flushStartTagName()
        switch_state tsBeforeAttributeName
      of '/':
        tok.flushStartTagName()
        switch_state tsSelfClosingStartTag
      of '>':
        switch_state tsData
        tok.flushStartTagName()
        emit_tok
      of '\0': tok.tagNameBuf &= "\uFFFD"
      else: tok.tagNameBuf &= c.toLowerAscii()

    of tsRcdataLessThanSign:
      case c
      of '/':
        tok.tmp = ""
        switch_state tsRcdataEndTagOpen
      else:
        emit '<'
        reconsume_in tsRcdata

    of tsRcdataEndTagOpen:
      case c
      of AsciiAlpha:
        flush_chars
        tok.next = ttEndTag
        tok.tagNameBuf = $c.toLowerAscii()
        tok.tmp &= c
        # note: was reconsume
        switch_state tsRcdataEndTagName
      else:
        emit "</"
        reconsume_in tsRcdata

    of tsRcdataEndTagName:
      template anything_else =
        tok.emitTmp()
        reconsume_in tsRcdata
      case c
      of AsciiWhitespace:
        tok.flushEndTagName()
        if tok.startTagMatches():
          switch_state tsBeforeAttributeName
        else:
          anything_else
      of '/':
        tok.flushEndTagName()
        if tok.startTagMatches():
          switch_state tsSelfClosingStartTag
        else:
          anything_else
      of '>':
        tok.flushEndTagName()
        if tok.startTagMatches():
          switch_state tsData
          emit_tok
        else:
          anything_else
      of AsciiAlpha: # note: merged upper & lower
        tok.tagNameBuf &= c.toLowerAscii()
        tok.tmp &= c
      else:
        anything_else

    of tsRawtextLessThanSign:
      case c
      of '/':
        tok.tmp = ""
        switch_state tsRawtextEndTagOpen
      else:
        emit '<'
        reconsume_in tsRawtext

    of tsRawtextEndTagOpen:
      case c
      of AsciiAlpha:
        flush_chars
        tok.next = ttEndTag
        tok.tagNameBuf = $c.toLowerAscii()
        tok.tmp &= c
        # note: was reconsume
        switch_state tsRawtextEndTagName
      else:
        emit "</"
        reconsume_in tsRawtext

    of tsRawtextEndTagName:
      template anything_else =
        tok.emitTmp()
        reconsume_in tsRawtext
      case c
      of AsciiWhitespace:
        tok.flushEndTagName()
        if tok.startTagMatches():
          switch_state tsBeforeAttributeName
        else:
          anything_else
      of '/':
        tok.flushEndTagName()
        if tok.startTagMatches():
          switch_state tsSelfClosingStartTag
        else:
          anything_else
      of '>':
        tok.flushEndTagName()
        if tok.startTagMatches():
          switch_state tsData
          emit_tok
        else:
          anything_else
      of AsciiAlpha: # note: merged upper & lower
        tok.tagNameBuf &= c.toLowerAscii()
        tok.tmp &= c
      else:
        anything_else

    of tsScriptDataLessThanSign:
      case c
      of '/':
        tok.tmp = ""
        switch_state tsScriptDataEndTagOpen
      of '!':
        emit "<!"
        switch_state tsScriptDataEscapeStart
      else:
        emit '<'
        reconsume_in tsScriptData

    of tsScriptDataEndTagOpen:
      case c
      of AsciiAlpha:
        flush_chars
        tok.next = ttEndTag
        tok.tagNameBuf = $c.toLowerAscii()
        tok.tmp &= c
        # note: was reconsume
        switch_state tsScriptDataEndTagName
      else:
        emit "</"
        reconsume_in tsScriptData

    of tsScriptDataEndTagName:
      template anything_else =
        tok.emitTmp()
        reconsume_in tsScriptData
      case c
      of AsciiWhitespace:
        tok.flushEndTagName()
        if tok.startTagMatches():
          switch_state tsBeforeAttributeName
        else:
          anything_else
      of '/':
        tok.flushEndTagName()
        if tok.startTagMatches():
          switch_state tsSelfClosingStartTag
        else:
          anything_else
      of '>':
        tok.flushEndTagName()
        if tok.startTagMatches():
          switch_state tsData
          emit_tok
        else:
          anything_else
      of AsciiAlpha: # note: merged upper & lower
        tok.tagNameBuf &= c.toLowerAscii()
        tok.tmp &= c
      else:
        anything_else

    of tsScriptDataEscapeStart, tsScriptDataEscapeStartDash:
      case c
      of '-':
        inc tok.state
        emit '-'
      else:
        reconsume_in tsScriptData

    of tsScriptDataEscaped:
      case c
      of '-':
        emit_nws '-'
        switch_state tsScriptDataEscapedDash
      of '<': switch_state tsScriptDataEscapedLessThanSign
      of '\0': emit_replacement
      of '\r': emit_cr
      of '\n': emit_lf
      of AsciiWhitespace - {'\r', '\n'}: emit_ws c
      else: emit_nws c

    of tsScriptDataEscapedDash:
      if c == '-':
        switch_state tsScriptDataEscapedDashDash
        emit '-'
      elif c == '<':
        switch_state tsScriptDataEscapedLessThanSign
      else:
        reconsume_in tsScriptDataEscaped

    of tsScriptDataEscapedDashDash:
      case c
      of '-': emit '-'
      of '<': switch_state tsScriptDataEscapedLessThanSign
      of '>':
        switch_state tsScriptData
        emit '>'
      else: reconsume_in tsScriptDataEscaped

    of tsScriptDataEscapedLessThanSign:
      case c
      of '/':
        tok.tmp = ""
        switch_state tsScriptDataEscapedEndTagOpen
      of AsciiAlpha:
        tok.tmp = $c.toLowerAscii()
        emit '<'
        emit c
        # note: was reconsume
        switch_state tsScriptDataDoubleEscapeStart
      else:
        emit '<'
        reconsume_in tsScriptDataEscaped

    of tsScriptDataEscapedEndTagOpen:
      if c in AsciiAlpha:
        flush_chars
        tok.next = ttEndTag
        tok.tagNameBuf = $c.toLowerAscii()
        tok.tmp &= c
        # note: was reconsume
        switch_state tsScriptDataEscapedEndTagName
      else:
        emit "</"
        reconsume_in tsScriptDataEscaped

    of tsScriptDataEscapedEndTagName:
      template anything_else =
        tok.emitTmp()
        reconsume_in tsScriptDataEscaped
      case c
      of AsciiWhitespace:
        tok.flushEndTagName()
        if tok.startTagMatches():
          switch_state tsBeforeAttributeName
        else:
          anything_else
      of '/':
        tok.flushEndTagName()
        if tok.startTagMatches():
          switch_state tsSelfClosingStartTag
        else:
          anything_else
      of '>':
        tok.flushEndTagName()
        if tok.startTagMatches():
          switch_state tsData
          emit_tok
        else:
          anything_else
      of AsciiAlpha:
        tok.tagNameBuf &= c.toLowerAscii()
        tok.tmp &= c
      else:
        anything_else

    of tsScriptDataDoubleEscapeStart:
      case c
      of '/', '>':
        emit c
        if tok.tmp == "script":
          switch_state tsScriptDataDoubleEscaped
        else:
          switch_state tsScriptDataEscaped
      of AsciiWhitespace:
        emit_ws c
        if tok.tmp == "script":
          switch_state tsScriptDataDoubleEscaped
        else:
          switch_state tsScriptDataEscaped
      of AsciiAlpha: # note: merged upper & lower
        emit c
        tok.tmp &= c.toLowerAscii()
      else: reconsume_in tsScriptDataEscaped

    of tsScriptDataDoubleEscaped:
      case c
      of '-':
        emit_nws '-'
        switch_state tsScriptDataDoubleEscapedDash
      of '<':
        emit_nws '<'
        switch_state tsScriptDataDoubleEscapedLessThanSign
      of '\0': emit_replacement
      of '\r': emit_cr
      of '\n': emit_lf
      of AsciiWhitespace - {'\r', '\n'}: emit_ws c
      else: emit_nws c

    of tsScriptDataDoubleEscapedDash:
      case c
      of '-':
        switch_state tsScriptDataDoubleEscapedDashDash
        emit '-'
      of '<':
        switch_state tsScriptDataDoubleEscapedLessThanSign
        emit '<'
      else:
        reconsume_in tsScriptDataDoubleEscaped

    of tsScriptDataDoubleEscapedDashDash:
      case c
      of '-': emit '-'
      of '<':
        switch_state tsScriptDataDoubleEscapedLessThanSign
        emit '<'
      of '>':
        switch_state tsScriptData
        emit '>'
      else:
        reconsume_in tsScriptDataDoubleEscaped

    of tsScriptDataDoubleEscapedLessThanSign:
      case c
      of '/':
        emit '/'
        tok.tmp = ""
        switch_state tsScriptDataDoubleEscapeEnd
      else: reconsume_in tsScriptDataDoubleEscaped

    of tsScriptDataDoubleEscapeEnd:
      case c
      of AsciiWhitespace, '/', '>':
        if c in AsciiWhitespace:
          flush_chars
          tok.isws = true
        emit c
        if tok.tmp == "script":
          switch_state tsScriptDataEscaped
        else:
          switch_state tsScriptDataDoubleEscaped
      of AsciiAlpha: # note: merged upper & lower
        emit c
        tok.tmp &= c.toLowerAscii()
      else:
        reconsume_in tsScriptDataDoubleEscaped

    of tsBeforeAttributeName:
      case c
      of AsciiWhitespace: discard
      of '/': switch_state tsSelfClosingStartTag
      of '>': reconsume_in tsAfterAttributeName
      else:
        tok.startNewAttribute()
        if c == '\0':
          tok.tmp &= "\uFFFD"
        else:
          tok.tmp &= c.toLowerAscii()
        switch_state tsAttributeName

    of tsAttributeName:
      case c
      of AsciiWhitespace, '/', '>', '=':
        tok.attrName = tok.strToAtom(tok.tmp)
        if c == '=':
          switch_state tsBeforeAttributeValue
        else:
          reconsume_in tsAfterAttributeName
      of '\0':
        tok.tmp &= "\uFFFD"
      else:
        tok.tmp &= c.toLowerAscii()

    of tsAfterAttributeName:
      case c
      of AsciiWhitespace: discard
      of '/': switch_state tsSelfClosingStartTag
      of '=': switch_state tsBeforeAttributeValue
      of '>':
        switch_state tsData
        tok.flushAttrs()
        emit_tok
      else:
        tok.startNewAttribute()
        if c == '\0':
          tok.tmp &= "\uFFFD"
        else:
          tok.tmp &= c.toLowerAscii()
        switch_state tsAttributeName

    of tsBeforeAttributeValue:
      case c
      of AsciiWhitespace: discard
      of '"', '\'':
        tok.quote = c
        switch_state tsAttributeValueQuoted
      of '>':
        switch_state tsData
        tok.flushAttrs()
        emit_tok
      else: reconsume_in tsAttributeValueUnquoted

    of tsAttributeValueQuoted:
      case c
      of '&': switch_state_return tsCharacterReference
      of '\0': tok.charbuf &= "\uFFFD"
      of '\r':
        tok.ignoreLF = true
        tok.charbuf &= '\n'
      of '\n':
        if not ignoreLF:
          tok.charbuf &= '\n'
      elif c == tok.quote: switch_state tsAfterAttributeValueQuoted
      else: tok.charbuf &= c

    of tsAttributeValueUnquoted:
      case c
      of AsciiWhitespace: switch_state tsBeforeAttributeName
      of '&': switch_state_return tsCharacterReference
      of '>':
        switch_state tsData
        tok.flushAttrs()
        emit_tok
      of '\0': tok.charbuf &= "\uFFFD"
      else: tok.charbuf &= c

    of tsAfterAttributeValueQuoted:
      case c
      of AsciiWhitespace:
        switch_state tsBeforeAttributeName
      of '/':
        switch_state tsSelfClosingStartTag
      of '>':
        switch_state tsData
        tok.flushAttrs()
        emit_tok
      else: reconsume_in tsBeforeAttributeName

    of tsSelfClosingStartTag:
      case c
      of '>':
        tok.flags.incl(tfSelfClosing)
        switch_state tsData
        tok.flushAttrs()
        emit_tok
      else: reconsume_in tsBeforeAttributeName

    of tsBogusComment:
      assert tok.next == ttComment
      case c
      of '>':
        switch_state tsData
        emit_tok
      of '\0': tok.tagNameBuf &= "\uFFFD"
      of '\r':
        tok.ignoreLF = true
        tok.tagNameBuf &= '\n'
      of '\n':
        if not ignoreLF:
          tok.tagNameBuf &= '\n'
      else: tok.tagNameBuf &= c

    of tsMarkupDeclarationOpen:
      case tok.eatStr(c, "--", ibuf)
      of esrSuccess:
        tok.next = ttComment
        tok.tagNameBuf = ""
        tok.state = tsCommentStart
      of esrNext: discard
      of esrFail:
        case tok.eatStrNoCase(c, "doctype", ibuf)
        of esrSuccess:
          switch_state tsDoctype
        of esrNext: discard
        of esrFail:
          case tok.eatStr(c, "[CDATA[", ibuf)
          of esrSuccess:
            if tok.hasnonhtml:
              switch_state tsCdataSection
            else:
              tok.next = ttComment
              tok.tagNameBuf = "[CDATA["
              switch_state tsBogusComment
          of esrNext: discard
          of esrFail:
            tok.next = ttComment
            tok.tagNameBuf = move(tok.tmp)
            reconsume_in tsBogusComment

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
        tok.tagNameBuf &= '-'
        reconsume_in tsComment

    of tsComment:
      case c
      of '<':
        tok.tagNameBuf &= c
        switch_state tsCommentLessThanSign
      of '-': switch_state tsCommentEndDash
      of '\0': tok.tagNameBuf &= "\uFFFD"
      of '\r':
        tok.ignoreLF = true
        tok.tagNameBuf &= '\n'
      of '\n':
        if not ignoreLF:
          tok.tagNameBuf &= '\n'
      else: tok.tagNameBuf &= c

    of tsCommentLessThanSign:
      case c
      of '!':
        tok.tagNameBuf &= c
        switch_state tsCommentLessThanSignBang
      of '<': tok.tagNameBuf &= c
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
        tok.tagNameBuf &= '-'
        reconsume_in tsComment

    of tsCommentEnd:
      case c
      of '>':
        switch_state tsData
        emit_tok
      of '!': switch_state tsCommentEndBang
      of '-': tok.tagNameBuf &= '-'
      else:
        tok.tagNameBuf &= "--"
        reconsume_in tsComment

    of tsCommentEndBang:
      if c == '>':
        switch_state tsData
        emit_tok
      else:
        tok.tagNameBuf &= "--!"
        if c == '-':
          switch_state tsCommentEndDash
        else:
          reconsume_in tsComment

    of tsDoctype:
      if c notin AsciiWhitespace:
        reconsume_in tsBeforeDoctypeName
      else:
        switch_state tsBeforeDoctypeName

    of tsBeforeDoctypeName:
      case c
      of AsciiWhitespace: discard
      of '\0':
        tok.tagNameBuf = "\uFFFD"
        tok.next = ttDoctype
        tok.flags = {}
        switch_state tsDoctypeName
      of '>':
        tok.tagNameBuf = ""
        tok.next = ttDoctype
        tok.flags = {tfQuirks}
        switch_state tsData
        emit_tok
      else:
        tok.tagNameBuf = $c.toLowerAscii()
        tok.next = ttDoctype
        tok.flags = {}
        switch_state tsDoctypeName

    of tsDoctypeName:
      case c
      of AsciiWhitespace:
        tok.tmp = ""
        switch_state tsAfterDoctypeName
      of '>':
        switch_state tsData
        emit_tok
      of '\0': tok.tagNameBuf &= "\uFFFD"
      else: tok.tagNameBuf &= c.toLowerAscii()

    of tsAfterDoctypeName:
      case tok.eatStrNoCase(c, "public", ibuf)
      of esrSuccess: switch_state tsAfterDoctypePublicKeyword
      of esrNext: discard
      of esrFail:
        case tok.eatStrNoCase(c, "system", ibuf)
        of esrSuccess:
          tok.tagNameBuf &= '\0' # pubid is empty
          switch_state tsAfterDoctypeSystemKeyword
        of esrNext: discard
        of esrFail:
          case c
          of AsciiWhitespace: discard
          of '>':
            switch_state tsData
            emit_tok
          else:
            tok.flags.incl(tfQuirks)
            reconsume_in tsBogusDoctype

    of tsAfterDoctypePublicKeyword:
      case c
      of AsciiWhitespace: switch_state tsBeforeDoctypePublicIdentifier
      of '"', '\'':
        tok.flags.incl(tfPubid)
        tok.quote = c
        tok.tagNameBuf &= '\0'
        switch_state tsDoctypePublicIdentifierQuoted
      of '>':
        tok.flags.incl(tfQuirks)
        switch_state tsData
        emit_tok
      else:
        tok.flags.incl(tfQuirks)
        reconsume_in tsBogusDoctype

    of tsBeforeDoctypePublicIdentifier:
      case c
      of AsciiWhitespace: discard
      of '"', '\'':
        tok.flags.incl(tfPubid)
        tok.quote = c
        tok.tagNameBuf &= '\0'
        switch_state tsDoctypePublicIdentifierQuoted
      of '>':
        tok.flags.incl(tfQuirks)
        switch_state tsData
        emit_tok
      else:
        tok.flags.incl(tfQuirks)
        reconsume_in tsBogusDoctype

    of tsDoctypePublicIdentifierQuoted:
      case c
      of '\0': tok.tagNameBuf &= "\uFFFD"
      of '>':
        tok.flags.incl(tfQuirks)
        switch_state tsData
        emit_tok
      of '\r':
        tok.ignoreLF = true
        tok.tagNameBuf &= '\n'
      of '\n':
        if not ignoreLF:
          tok.tagNameBuf &= '\n'
      elif c == tok.quote: switch_state tsAfterDoctypePublicIdentifier
      else: tok.tagNameBuf &= c

    of tsAfterDoctypePublicIdentifier:
      case c
      of AsciiWhitespace:
        switch_state tsBetweenDoctypePublicAndSystemIdentifiers
      of '>':
        switch_state tsData
        emit_tok
      of '"', '\'':
        tok.flags.incl(tfSysid)
        tok.quote = c
        tok.tagNameBuf &= '\0'
        switch_state tsDoctypeSystemIdentifierQuoted
      else:
        tok.flags.incl(tfQuirks)
        reconsume_in tsBogusDoctype

    of tsBetweenDoctypePublicAndSystemIdentifiers, tsAfterDoctypeSystemKeyword,
        tsBeforeDoctypeSystemIdentifier:
      case c
      of AsciiWhitespace:
        if tok.state == tsAfterDoctypeSystemKeyword:
          switch_state tsBeforeDoctypeSystemIdentifier
      of '>':
        if tok.state != tsBetweenDoctypePublicAndSystemIdentifiers:
          tok.flags.incl(tfQuirks)
        switch_state tsData
        emit_tok
      of '"', '\'':
        tok.flags.incl(tfSysid)
        tok.quote = c
        tok.tagNameBuf &= '\0'
        switch_state tsDoctypeSystemIdentifierQuoted
      else:
        tok.flags.incl(tfQuirks)
        reconsume_in tsBogusDoctype

    of tsDoctypeSystemIdentifierQuoted:
      case c
      of '\0': tok.tagNameBuf &= "\uFFFD"
      of '>':
        tok.flags.incl(tfQuirks)
        switch_state tsData
        emit_tok
      of '\r':
        tok.ignoreLF = true
        tok.tagNameBuf &= '\n'
      of '\n':
        if not ignoreLF:
          tok.tagNameBuf &= '\n'
      elif c == tok.quote: switch_state tsAfterDoctypeSystemIdentifier
      else: tok.tagNameBuf &= c

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
        switch_state tsData
        emit_tok

    of tsCdataSection:
      case c
      of ']': switch_state tsCdataSectionBracket
      of '\0': emit_null
      of '\r': emit_cr
      of '\n': emit_lf
      of AsciiWhitespace - {'\r', '\n'}: emit_ws c
      else: emit_nws c

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
      if tok.isws:
        flush_chars
      case c
      of AsciiAlpha:
        tok.tmp = "&"
        reconsume_in tsNamedCharacterReference
      of '#':
        tok.tmp = "&#"
        switch_state tsNumericCharacterReference
      else:
        tok.appendAttrOrEmit('&')
        reconsume_in tok.rstate

    of tsNamedCharacterReference:
      let isws = tok.isws
      tok.inputBufIdx = i
      if tok.findCharRef(c, ibuf):
        tok.flushNamedCharacterReference(ibuf)
      i = tok.inputBufIdx
      assert i >= 0 # helps the compiler
      if isws != tok.isws:
        # we got a whitespace entity to emit
        res = trEmit
        break

    of tsAmbiguousAmpersand:
      if c in AsciiAlpha:
        tok.appendAttrOrEmit(c)
      else:
        reconsume_in tok.rstate

    of tsNumericCharacterReference:
      tok.code = 0
      case c
      of 'x', 'X':
        tok.tmp &= c
        switch_state tsHexadecimalCharacterReferenceStart
      of AsciiDigit:
        tok.code = uint32(c) - uint32('0')
        # note: was reconsume
        switch_state tsDecimalCharacterReference
      else:
        tok.appendAttrOrEmit(tok.tmp)
        reconsume_in tok.rstate

    of tsHexadecimalCharacterReferenceStart:
      let c2 = c.toLowerAscii()
      case c2
      of AsciiDigit:
        tok.code = uint32(c2) - uint32('0')
        # note: was reconsume
        switch_state tsHexadecimalCharacterReference
      of 'a'..'f':
        tok.code = uint32(c2) - uint32('a') + 10
        # note: was reconsume
        switch_state tsHexadecimalCharacterReference
      else:
        tok.appendAttrOrEmit(tok.tmp)
        reconsume_in tok.rstate

    of tsHexadecimalCharacterReference:
      let c2 = c.toLowerAscii()
      case c2
      of AsciiDigit:
        if tok.code <= 0x10FFFF:
          tok.code *= 0x10
          tok.code += uint32(c2) - uint32('0')
      of 'a'..'f':
        if tok.code <= 0x10FFFF:
          tok.code *= 0x10
          tok.code += uint32(c2) - uint32('a') + 10
      else:
        if tok.code < 0x100 and cast[char](tok.code) in AsciiWhitespace:
          # we always flush whitespace before entities, so isws is false here
          flush_chars
          tok.isws = true
        if c != ';':
          dec i
        tok.flushNumericCharacterReference()
        switch_state tok.rstate

    of tsDecimalCharacterReference:
      if c in AsciiDigit:
        if tok.code <= 0x10FFFF:
          tok.code *= 10
          tok.code += uint32(c) - uint32('0')
      else:
        if tok.code < 0x100 and cast[char](tok.code) in AsciiWhitespace:
          # see above
          flush_chars
          tok.isws = true
        if c != ';':
          dec i
        tok.flushNumericCharacterReference()
        switch_state tok.rstate

  tok.inputBufIdx = i
  res

proc finish*[Handle, Atom](tok: var Tokenizer[Handle, Atom]): TokenizeResult =
  if tok.isws and tok.charbuf.len > 0:
    return tok.flushChars()
  let state = tok.state
  tok.state = tsData
  case state
  of tsTagOpen, tsRcdataLessThanSign, tsRawtextLessThanSign,
      tsScriptDataLessThanSign, tsScriptDataEscapedLessThanSign:
    tok.charbuf &= '<'
  of tsEndTagOpen, tsRcdataEndTagOpen, tsRawtextEndTagOpen,
      tsScriptDataEndTagOpen, tsScriptDataEscapedEndTagOpen:
    tok.charbuf &= "</"
  of tsRcdataEndTagName, tsRawtextEndTagName, tsScriptDataEndTagName,
      tsScriptDataEscapedEndTagName:
    tok.emitTmp()
  of tsBogusComment, tsBogusDoctype, tsCommentEndDash, tsCommentEnd,
      tsCommentEndBang, tsCommentLessThanSignBangDash,
      tsCommentLessThanSignBangDashDash, tsCommentStartDash, tsComment,
      tsCommentStart, tsCommentLessThanSign, tsCommentLessThanSignBang:
    tok.t = tok.next
    return trEmit
  of tsMarkupDeclarationOpen:
    tok.t = ttComment
    tok.tagNameBuf = move(tok.tmp)
    return trEmit
  of tsDoctype, tsBeforeDoctypeName:
    tok.t = ttDoctype
    tok.flags = {tfQuirks}
    tok.tagNameBuf = ""
    return trEmit
  of tsDoctypeName, tsAfterDoctypeName, tsAfterDoctypePublicKeyword,
      tsBeforeDoctypePublicIdentifier, tsDoctypePublicIdentifierQuoted,
      tsAfterDoctypePublicIdentifier,
      tsBetweenDoctypePublicAndSystemIdentifiers,
      tsAfterDoctypeSystemKeyword, tsBeforeDoctypeSystemIdentifier,
      tsDoctypeSystemIdentifierQuoted, tsAfterDoctypeSystemIdentifier:
    tok.flags.incl(tfQuirks)
    tok.t = ttDoctype
    return trEmit
  of tsCdataSectionBracket:
    tok.charbuf &= ']'
  of tsCdataSectionEnd:
    tok.charbuf &= "]]"
  of tsCharacterReference:
    if not tok.consumedAsAttribute():
      tok.charbuf &= '&'
  of tsNamedCharacterReference:
    tok.flushNamedCharacterReference([])
  of tsHexadecimalCharacterReferenceStart, tsNumericCharacterReference:
    if not tok.consumedAsAttribute():
      tok.appendAttrOrEmit(tok.tmp)
  of tsHexadecimalCharacterReference, tsDecimalCharacterReference:
    if not tok.consumedAsAttribute():
      tok.flushNumericCharacterReference()
  of tsSelfClosingStartTag, tsAfterAttributeValueQuoted, tsBeforeAttributeName,
      tsAttributeValueQuoted, tsAttributeValueUnquoted, tsBeforeAttributeValue,
      tsAfterAttributeName:
    # we used charbuf as a buffer for attr values, so avoid flushing it
    # as data
    tok.charbuf = ""
  else: discard
  if tok.charbuf.len > 0:
    return tok.flushChars()
  trDone
