{.experimental: "overloadableEnums".}

import options
import strformat
import strutils
import macros
import tables
import unicode

import entity
import parseerror
import tags
import utils/radixtree
import utils/twtstr

import chakasu/decoderstream

# Tokenizer
type
  Tokenizer* = object
    state*: TokenizerState
    rstate: TokenizerState
    tmp: string
    code: int
    tok: Token
    laststart*: Token
    attrn: string
    attrv: string
    attr: bool
    hasnonhtml*: bool
    onParseError: proc(e: ParseError)

    decoder: DecoderStream
    sbuf: seq[Rune]
    sbuf_i: int
    eof_i: int

  TokenType* = enum
    DOCTYPE, START_TAG, END_TAG, COMMENT, CHARACTER, CHARACTER_WHITESPACE, EOF

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

  Token* = ref object
    case t*: TokenType
    of DOCTYPE:
      quirks*: bool
      name*: Option[string]
      pubid*: Option[string]
      sysid*: Option[string]
    of START_TAG, END_TAG:
      selfclosing*: bool
      tagname*: string
      tagtype*: TagType
      attrs*: Table[string, string]
    of CHARACTER, CHARACTER_WHITESPACE:
      s*: string
    of COMMENT:
      data*: string
    of EOF: discard

func `$`*(tok: Token): string =
  case tok.t
  of DOCTYPE: fmt"{tok.t} {tok.name} {tok.pubid} {tok.sysid} {tok.quirks}"
  of START_TAG, END_TAG: fmt"{tok.t} {tok.tagname} {tok.selfclosing} {tok.attrs}"
  of CHARACTER, CHARACTER_WHITESPACE: $tok.t & " " & tok.s
  of COMMENT: fmt"{tok.t} {tok.data}"
  of EOF: fmt"{tok.t}"

const bufLen = 1024 # * 4096 bytes
const copyBufLen = 16 # * 64 bytes

proc readn(t: var Tokenizer) =
  let l = t.sbuf.len
  t.sbuf.setLen(bufLen)
  let n = t.decoder.readData(addr t.sbuf[l], (bufLen - l) * sizeof(Rune))
  t.sbuf.setLen(l + n div sizeof(Rune))
  if t.decoder.atEnd:
    t.eof_i = t.sbuf.len

proc newTokenizer*(s: DecoderStream, onParseError: proc(e: ParseError)): Tokenizer =
  var t = Tokenizer(
    decoder: s,
    sbuf: newSeqOfCap[Rune](bufLen),
    eof_i: -1,
    sbuf_i: 0,
    onParseError: onParseError
  )
  t.readn()
  return t

proc newTokenizer*(s: string): Tokenizer =
  let rs = s.toRunes()
  var t = Tokenizer(
    sbuf: rs,
    eof_i: rs.len,
    sbuf_i: 0
  )
  return t

func atEof(t: Tokenizer): bool =
  t.eof_i != -1 and t.sbuf_i >= t.eof_i

proc checkBufLen(t: var Tokenizer) =
  if t.sbuf_i >= min(bufLen - copyBufLen, t.sbuf.len):
    for i in t.sbuf_i ..< t.sbuf.len:
      t.sbuf[i - t.sbuf_i] = t.sbuf[i]
    t.sbuf.setLen(t.sbuf.len - t.sbuf_i)
    t.sbuf_i = 0
    if t.sbuf.len < bufLen:
      t.readn()

proc consume(t: var Tokenizer): Rune =
  t.checkBufLen()
  ## Normalize newlines (\r\n -> \n, single \r -> \n)
  if t.sbuf[t.sbuf_i] == Rune('\r'):
    inc t.sbuf_i
    t.checkBufLen()
    if t.atEof or t.sbuf[t.sbuf_i] != Rune('\n'):
      # \r
      result = Rune('\n')
      return
    # else, \r\n so just return the \n
  result = t.sbuf[t.sbuf_i]
  inc t.sbuf_i

proc reconsume(t: var Tokenizer) =
  dec t.sbuf_i

iterator tokenize*(tokenizer: var Tokenizer): Token =
  var tokqueue: seq[Token]
  var running = true
  var charbuf = ""
  var isws = false

  template flush_chars =
    if charbuf.len > 0:
      let token = if not isws:
        Token(t: CHARACTER, s: charbuf)
      else:
        Token(t: CHARACTER_WHITESPACE, s: charbuf)
      tokqueue.add(token)
      isws = false
      charbuf.setLen(0)

  template emit(tok: Token) =
    flush_chars
    if tok.t == START_TAG:
      tokenizer.laststart = tok
    if tok.t in {START_TAG, END_TAG}:
      tok.tagtype = tagType(tok.tagname)
    tokqueue.add(tok)
  template emit(tok: TokenType) = emit Token(t: tok)
  template emit(s: static string) =
    static:
      for c in s:
        doAssert c notin AsciiWhitespace
    if isws:
      flush_chars
    charbuf &= s
  template emit(rn: Rune) =
    if isws:
      flush_chars
    charbuf &= $rn
  template emit(ch: char) =
    let chisws = ch in AsciiWhitespace
    if isws != chisws: # emit whitespace & non-whitespace separately.
      flush_chars
      isws = chisws
    charbuf &= ch
  template emit_eof =
    emit EOF
    running = false
  template emit_tok =
    if tokenizer.attr:
      tokenizer.tok.attrs[tokenizer.attrn] = tokenizer.attrv
    emit tokenizer.tok
  template emit_current =
    if is_eof:
      emit_eof
    elif c in Ascii:
      emit c
    else:
      emit r
  template emit_replacement = emit Rune(0xFFFD)
  template switch_state(s: TokenizerState) =
    tokenizer.state = s
  template switch_state_return(s: TokenizerState) =
    tokenizer.rstate = tokenizer.state
    tokenizer.state = s
  template reconsume_in(s: TokenizerState) =
    tokenizer.reconsume()
    switch_state s
  template parse_error(error: untyped) =
    if tokenizer.onParseError != nil:
      tokenizer.onParseError(error)
  template is_appropriate_end_tag_token(): bool =
    tokenizer.laststart != nil and
      tokenizer.laststart.tagname == tokenizer.tok.tagname
  template start_new_attribute =
    if tokenizer.attr:
      tokenizer.tok.attrs[tokenizer.attrn] = tokenizer.attrv
    tokenizer.attrn = ""
    tokenizer.attrv = ""
    tokenizer.attr = true
  template leave_attribute_name_state =
    if tokenizer.attrn in tokenizer.tok.attrs:
      tokenizer.attr = false
  template append_to_current_attr_value(c: typed) =
    if tokenizer.attr:
      tokenizer.attrv &= c
  template peek_str(s: string): bool =
    # WARNING: will break on strings with copyBufLen + 4 bytes
    # WARNING: only works with ascii
    assert s.len < copyBufLen - 4 and s.len > 0
    if tokenizer.eof_i != -1 and tokenizer.sbuf_i + s.len >= tokenizer.eof_i:
      false
    else:
      var b = true
      for i in 0 ..< s.len:
        let c = tokenizer.sbuf[tokenizer.sbuf_i + i]
        if not c.isAscii() or cast[char](c) != s[i]:
          b = false
          break
      b

  template peek_str_nocase(s: string): bool =
    # WARNING: will break on strings with copyBufLen + 4 bytes
    # WARNING: only works with UPPER CASE ascii
    assert s.len < copyBufLen - 4 and s.len > 0
    if tokenizer.eof_i != -1 and tokenizer.sbuf_i + s.len >= tokenizer.eof_i:
      false
    else:
      var b = true
      for i in 0 ..< s.len:
        let c = tokenizer.sbuf[tokenizer.sbuf_i + i]
        if not c.isAscii() or cast[char](c).toUpperAscii() != s[i]:
          b = false
          break
      b
  template peek_char(): char =
    let r = tokenizer.sbuf[tokenizer.sbuf_i]
    if r.isAscii():
      cast[char](r)
    else:
      char(128)
  template consume_and_discard(n: int) = #TODO optimize
    var i = 0
    while i < n:
      discard tokenizer.consume()
      inc i
  template consumed_as_an_attribute(): bool =
    tokenizer.rstate in {ATTRIBUTE_VALUE_DOUBLE_QUOTED, ATTRIBUTE_VALUE_SINGLE_QUOTED, ATTRIBUTE_VALUE_UNQUOTED}
  template emit_tmp() =
    for c in tokenizer.tmp:
      emit c
  template flush_code_points_consumed_as_a_character_reference() =
    if consumed_as_an_attribute:
      append_to_current_attr_value tokenizer.tmp
    else:
      emit_tmp
  template new_token(t: Token) =
    if tokenizer.attr:
      tokenizer.attr = false
    tokenizer.tok = t

  # Fake EOF as an actual character. Also replace anything_else with the else
  # branch.
  macro stateMachine(states: varargs[untyped]): untyped =
    var maincase = newNimNode(nnkCaseStmt).add(quote do: tokenizer.state)
    for state in states:
      if state.kind == nnkOfBranch:
        var mainstmtlist: NimNode
        var mainstmtlist_i = -1
        for i in 0 ..< state.len:
          if state[i].kind == nnkStmtList:
            mainstmtlist = state[i]
            mainstmtlist_i = i
            break
        if mainstmtlist[0].kind == nnkIdent and mainstmtlist[0].strVal == "ignore_eof":
          maincase.add(state)
          continue

        var hasanythingelse = false
        if mainstmtlist[0].kind == nnkIdent and mainstmtlist[0].strVal == "has_anything_else":
          hasanythingelse = true

        let childcase = findChild(mainstmtlist, it.kind == nnkCaseStmt)
        var haseof = false
        var eofstmts: NimNode
        var elsestmts: NimNode

        for i in countdown(childcase.len-1, 0):
          let childof = childcase[i]
          if childof.kind == nnkOfBranch:
            for j in countdown(childof.len-1, 0):
              if childof[j].kind == nnkIdent and childof[j].strVal == "eof":
                haseof = true
                eofstmts = childof.findChild(it.kind == nnkStmtList)
                if childof.findChild(it.kind == nnkIdent and it.strVal != "eof") != nil:
                  childof.del(j)
                else:
                  childcase.del(i)
          elif childof.kind == nnkElse:
            elsestmts = childof.findChild(it.kind == nnkStmtList)

        if not haseof:
          eofstmts = elsestmts
        if hasanythingelse:
          let fake_anything_else = quote do:
            template anything_else =
              `elsestmts`
          mainstmtlist.insert(0, fake_anything_else)
        let eofstmtlist = quote do:
          if is_eof:
            `eofstmts`
          else:
            `mainstmtlist`
        state[mainstmtlist_i] = eofstmtlist
      maincase.add(state)
    result = newNimNode(nnkStmtList)
    result.add(maincase)

  template ignore_eof = discard # does nothing
  template has_anything_else = discard # does nothing

  const null = char(0)

  while running:
    let is_eof = tokenizer.atEof # set eof here, otherwise we would exit at the last character
    let r = if not is_eof:
      tokenizer.consume()
    else:
      # avoid consuming eof...
      Rune(null)
    let c = if r.isAscii(): cast[char](r) else: char(128)
    stateMachine: # => case tokenizer.state
    of DATA:
      case c
      of '&': switch_state_return CHARACTER_REFERENCE
      of '<': switch_state TAG_OPEN
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        emit_current
      of eof: emit_eof
      else: emit_current

    of RCDATA:
      case c
      of '&': switch_state_return CHARACTER_REFERENCE
      of '<': switch_state RCDATA_LESS_THAN_SIGN
      of null: parse_error UNEXPECTED_NULL_CHARACTER
      of eof: emit_eof
      else: emit_current

    of RAWTEXT:
      case c
      of '<': switch_state RAWTEXT_LESS_THAN_SIGN
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        emit_replacement
      of eof: emit_eof
      else: emit_current

    of SCRIPT_DATA:
      case c
      of '<': switch_state SCRIPT_DATA_LESS_THAN_SIGN
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        emit_replacement
      of eof: emit_eof
      else: emit_current

    of PLAINTEXT:
      case c
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        emit_replacement
      of eof: emit_eof
      else: emit_current

    of TAG_OPEN:
      case c
      of '!': switch_state MARKUP_DECLARATION_OPEN
      of '/': switch_state END_TAG_OPEN
      of AsciiAlpha:
        new_token Token(t: START_TAG)
        reconsume_in TAG_NAME
      of '?':
        parse_error UNEXPECTED_QUESTION_MARK_INSTEAD_OF_TAG_NAME
        new_token Token(t: COMMENT)
        reconsume_in BOGUS_COMMENT
      of eof:
        parse_error EOF_BEFORE_TAG_NAME
        emit '<'
        emit_eof
      else:
        parse_error INVALID_FIRST_CHARACTER_OF_TAG_NAME
        emit '<'
        reconsume_in DATA

    of END_TAG_OPEN:
      case c
      of AsciiAlpha:
        new_token Token(t: END_TAG)
        reconsume_in TAG_NAME
      of '>':
        parse_error MISSING_END_TAG_NAME
        switch_state DATA
      of eof:
        parse_error EOF_BEFORE_TAG_NAME
        emit "</"
        emit_eof
      else:
        parse_error INVALID_FIRST_CHARACTER_OF_TAG_NAME
        new_token Token(t: COMMENT)
        reconsume_in BOGUS_COMMENT

    of TAG_NAME:
      case c
      of AsciiWhitespace: switch_state BEFORE_ATTRIBUTE_NAME
      of '/': switch_state SELF_CLOSING_START_TAG
      of '>':
        switch_state DATA
        emit_tok
      of AsciiUpperAlpha: tokenizer.tok.tagname &= c.tolower()
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.tok.tagname &= Rune(0xFFFD)
      of eof:
        parse_error EOF_IN_TAG
        emit_eof
      else: tokenizer.tok.tagname &= r

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
        new_token Token(t: END_TAG)
        reconsume_in RCDATA_END_TAG_NAME
      else:
        emit "</"
        reconsume_in RCDATA

    of RCDATA_END_TAG_NAME:
      has_anything_else
      case c
      of AsciiWhitespace:
        if is_appropriate_end_tag_token:
          switch_state BEFORE_ATTRIBUTE_NAME
        else:
          anything_else
      of '/':
        if is_appropriate_end_tag_token:
          switch_state SELF_CLOSING_START_TAG
        else:
          anything_else
      of '>':
        if is_appropriate_end_tag_token:
          switch_state DATA
          emit_tok
        else:
          anything_else
      of AsciiAlpha: # note: merged upper & lower
        tokenizer.tok.tagname &= c.tolower()
        tokenizer.tmp &= c
      else:
        new_token nil #TODO
        emit "</"
        emit_tmp
        reconsume_in RCDATA

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
        new_token Token(t: END_TAG)
        reconsume_in RAWTEXT_END_TAG_NAME
      else:
        emit "</"
        reconsume_in RAWTEXT

    of RAWTEXT_END_TAG_NAME:
      has_anything_else
      case c
      of AsciiWhitespace:
        if is_appropriate_end_tag_token:
          switch_state BEFORE_ATTRIBUTE_NAME
        else:
          anything_else
      of '/':
        if is_appropriate_end_tag_token:
          switch_state SELF_CLOSING_START_TAG
        else:
          anything_else
      of '>':
        if is_appropriate_end_tag_token:
          switch_state DATA
          emit_tok
        else:
          anything_else
      of AsciiAlpha: # note: merged upper & lower
        tokenizer.tok.tagname &= c.tolower()
        tokenizer.tmp &= c
      else:
        new_token nil #TODO
        emit "</"
        emit_tmp
        reconsume_in RAWTEXT

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
        new_token Token(t: END_TAG)
        reconsume_in SCRIPT_DATA_END_TAG_NAME
      else:
        emit "</"
        reconsume_in SCRIPT_DATA

    of SCRIPT_DATA_END_TAG_NAME:
      has_anything_else
      case c
      of AsciiWhitespace:
        if is_appropriate_end_tag_token:
          switch_state BEFORE_ATTRIBUTE_NAME
        else:
          anything_else
      of '/':
        if is_appropriate_end_tag_token:
          switch_state SELF_CLOSING_START_TAG
        else:
          anything_else
      of '>':
        if is_appropriate_end_tag_token:
          switch_state DATA
          emit_tok
        else:
          anything_else
      of AsciiAlpha: # note: merged upper & lower
        tokenizer.tok.tagname &= c.tolower()
        tokenizer.tmp &= c
      else:
        emit "</"
        emit_tmp
        reconsume_in SCRIPT_DATA

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
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        emit_replacement
      of eof:
        parse_error EOF_IN_SCRIPT_HTML_COMMENT_LIKE_TEXT
        emit_eof
      else:
        emit_current

    of SCRIPT_DATA_ESCAPED_DASH:
      case c
      of '-':
        switch_state SCRIPT_DATA_ESCAPED_DASH_DASH
        emit '-'
      of '<':
        switch_state SCRIPT_DATA_ESCAPED_LESS_THAN_SIGN
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        switch_state SCRIPT_DATA_ESCAPED
      of eof:
        parse_error EOF_IN_SCRIPT_HTML_COMMENT_LIKE_TEXT
        emit_eof
      else:
        switch_state SCRIPT_DATA_ESCAPED
        emit_current

    of SCRIPT_DATA_ESCAPED_DASH_DASH:
      case c
      of '-':
        emit '-'
      of '<':
        switch_state SCRIPT_DATA_ESCAPED_LESS_THAN_SIGN
      of '>':
        switch_state SCRIPT_DATA
        emit '>'
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        switch_state SCRIPT_DATA_ESCAPED
      of eof:
        parse_error EOF_IN_SCRIPT_HTML_COMMENT_LIKE_TEXT
        emit_eof
      else:
        switch_state SCRIPT_DATA_ESCAPED
        emit_current

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
        new_token Token(t: START_TAG)
        reconsume_in SCRIPT_DATA_ESCAPED_END_TAG_NAME
      else:
        emit "</"
        reconsume_in SCRIPT_DATA_ESCAPED

    of SCRIPT_DATA_ESCAPED_END_TAG_NAME:
      has_anything_else
      case c
      of AsciiWhitespace:
        if is_appropriate_end_tag_token:
          switch_state BEFORE_ATTRIBUTE_NAME
        else:
          anything_else
      of '/':
        if is_appropriate_end_tag_token:
          switch_state SELF_CLOSING_START_TAG
        else:
          anything_else
      of '>':
        if is_appropriate_end_tag_token:
          switch_state DATA
        else:
          anything_else
      of AsciiAlpha:
        tokenizer.tok.tagname &= c.tolower()
        tokenizer.tmp &= c
      else:
        emit "</"
        emit_tmp
        reconsume_in SCRIPT_DATA_ESCAPED

    of SCRIPT_DATA_DOUBLE_ESCAPE_START:
      case c
      of AsciiWhitespace, '/', '>':
        if tokenizer.tmp == "script":
          switch_state SCRIPT_DATA_DOUBLE_ESCAPED
        else:
          switch_state SCRIPT_DATA_ESCAPED
          emit_current
      of AsciiAlpha: # note: merged upper & lower
        tokenizer.tmp &= c.tolower()
        emit_current
      else: reconsume_in SCRIPT_DATA_ESCAPED

    of SCRIPT_DATA_DOUBLE_ESCAPED:
      case c
      of '-':
        switch_state SCRIPT_DATA_DOUBLE_ESCAPED_DASH
        emit '-'
      of '<':
        switch_state SCRIPT_DATA_DOUBLE_ESCAPED_LESS_THAN_SIGN
        emit '<'
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        emit_replacement
      of eof:
        parse_error EOF_IN_SCRIPT_HTML_COMMENT_LIKE_TEXT
        emit_eof
      else: emit_current

    of SCRIPT_DATA_DOUBLE_ESCAPED_DASH:
      case c
      of '-':
        switch_state SCRIPT_DATA_DOUBLE_ESCAPED_DASH_DASH
        emit '-'
      of '<':
        switch_state SCRIPT_DATA_DOUBLE_ESCAPED_LESS_THAN_SIGN
        emit '<'
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        switch_state SCRIPT_DATA_DOUBLE_ESCAPED
        emit_replacement
      of eof:
        parse_error EOF_IN_SCRIPT_HTML_COMMENT_LIKE_TEXT
        emit_eof
      else:
        switch_state SCRIPT_DATA_DOUBLE_ESCAPED
        emit_current

    of SCRIPT_DATA_DOUBLE_ESCAPED_DASH_DASH:
      case c
      of '-': emit '-'
      of '<':
        switch_state SCRIPT_DATA_DOUBLE_ESCAPED_LESS_THAN_SIGN
        emit '<'
      of '>':
        switch_state SCRIPT_DATA
        emit '>'
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        switch_state SCRIPT_DATA_DOUBLE_ESCAPED
        emit_replacement
      of eof:
        parse_error EOF_IN_SCRIPT_HTML_COMMENT_LIKE_TEXT
        emit_eof
      else: switch_state SCRIPT_DATA_DOUBLE_ESCAPED

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
          emit_current
      of AsciiAlpha: # note: merged upper & lower
        tokenizer.tmp &= c.tolower()
        emit_current
      else:
        reconsume_in SCRIPT_DATA_DOUBLE_ESCAPED

    of BEFORE_ATTRIBUTE_NAME:
      case c
      of AsciiWhitespace: discard
      of '/', '>', eof: reconsume_in AFTER_ATTRIBUTE_NAME
      of '=':
        parse_error UNEXPECTED_EQUALS_SIGN_BEFORE_ATTRIBUTE_NAME
        start_new_attribute
        switch_state ATTRIBUTE_NAME
      else:
        start_new_attribute
        reconsume_in ATTRIBUTE_NAME

    of ATTRIBUTE_NAME:
      has_anything_else
      case c
      of AsciiWhitespace, '/', '>', eof:
        leave_attribute_name_state
        reconsume_in AFTER_ATTRIBUTE_NAME
      of '=':
        leave_attribute_name_state
        switch_state BEFORE_ATTRIBUTE_VALUE
      of AsciiUpperAlpha:
        tokenizer.attrn &= c.tolower()
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.attrn &= Rune(0xFFFD)
      of '"', '\'', '<':
        parse_error UNEXPECTED_CHARACTER_IN_ATTRIBUTE_NAME
        anything_else
      else:
        tokenizer.attrn &= r

    of AFTER_ATTRIBUTE_NAME:
      case c
      of AsciiWhitespace: discard
      of '/': switch_state SELF_CLOSING_START_TAG
      of '=': switch_state BEFORE_ATTRIBUTE_VALUE
      of '>':
        switch_state DATA
        emit_tok
      of eof:
        parse_error EOF_IN_TAG
        emit_eof
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
        emit '>'
      else: reconsume_in ATTRIBUTE_VALUE_UNQUOTED

    of ATTRIBUTE_VALUE_DOUBLE_QUOTED:
      case c
      of '"': switch_state AFTER_ATTRIBUTE_VALUE_QUOTED
      of '&': switch_state_return CHARACTER_REFERENCE
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        append_to_current_attr_value Rune(0xFFFD)
      of eof:
        parse_error EOF_IN_TAG
        emit_eof
      else: append_to_current_attr_value r

    of ATTRIBUTE_VALUE_SINGLE_QUOTED:
      case c
      of '\'': switch_state AFTER_ATTRIBUTE_VALUE_QUOTED
      of '&': switch_state_return CHARACTER_REFERENCE
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        append_to_current_attr_value Rune(0xFFFD)
      of eof:
        parse_error EOF_IN_TAG
        emit_eof
      else: append_to_current_attr_value r

    of ATTRIBUTE_VALUE_UNQUOTED:
      case c
      of AsciiWhitespace: switch_state BEFORE_ATTRIBUTE_NAME
      of '&': switch_state_return CHARACTER_REFERENCE
      of '>':
        switch_state DATA
        emit_tok
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        append_to_current_attr_value Rune(0xFFFD)
      of '"', '\'', '<', '=', '`':
        parse_error UNEXPECTED_CHARACTER_IN_UNQUOTED_ATTRIBUTE_VALUE
        append_to_current_attr_value c
      of eof:
        parse_error EOF_IN_TAG
        emit_eof
      else: append_to_current_attr_value r

    of AFTER_ATTRIBUTE_VALUE_QUOTED:
      case c
      of AsciiWhitespace:
        switch_state BEFORE_ATTRIBUTE_NAME
      of '/':
        switch_state SELF_CLOSING_START_TAG
      of '>':
        switch_state DATA
        emit_tok
      of eof:
        parse_error EOF_IN_TAG
        emit_eof
      else:
        parse_error MISSING_WHITESPACE_BETWEEN_ATTRIBUTES
        reconsume_in BEFORE_ATTRIBUTE_NAME

    of SELF_CLOSING_START_TAG:
      case c
      of '>':
        tokenizer.tok.selfclosing = true
        switch_state DATA
        emit_tok
      of eof:
        parse_error EOF_IN_TAG
        emit_eof
      else:
        parse_error UNEXPECTED_SOLIDUS_IN_TAG
        reconsume_in BEFORE_ATTRIBUTE_NAME

    of BOGUS_COMMENT:
      assert tokenizer.tok.t == COMMENT
      case c
      of '>':
        switch_state DATA
        emit_tok
      of eof:
        emit_tok
        emit_eof
      of null: parse_error UNEXPECTED_NULL_CHARACTER
      else: tokenizer.tok.data &= r

    of MARKUP_DECLARATION_OPEN: # note: rewritten to fit case model as we consume a char anyway
      has_anything_else
      case c
      of '-':
        if peek_char == '-':
          new_token Token(t: COMMENT)
          tokenizer.state = COMMENT_START
          consume_and_discard 1
        else: anything_else
      of 'D', 'd':
        if peek_str_nocase("OCTYPE"):
          consume_and_discard "OCTYPE".len
          switch_state DOCTYPE
        else: anything_else
      of '[':
        if peek_str("CDATA["):
          consume_and_discard "CDATA[".len
          if tokenizer.hasnonhtml:
            switch_state CDATA_SECTION
          else:
            parse_error CDATA_IN_HTML_CONTENT
            new_token Token(t: COMMENT, data: "[CDATA[")
            switch_state BOGUS_COMMENT
        else: anything_else
      else:
        parse_error INCORRECTLY_OPENED_COMMENT
        new_token Token(t: COMMENT)
        reconsume_in BOGUS_COMMENT

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
      of eof:
        parse_error EOF_IN_COMMENT
        emit_tok
        emit_eof
      else:
        tokenizer.tok.data &= '-'
        reconsume_in COMMENT

    of COMMENT:
      case c
      of '<':
        tokenizer.tok.data &= c
        switch_state COMMENT_LESS_THAN_SIGN
      of '-': switch_state COMMENT_END_DASH
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.tok.data &= Rune(0xFFFD)
      of eof:
        parse_error EOF_IN_COMMENT
        emit_tok
        emit_eof
      else: tokenizer.tok.data &= r

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
      of '>', eof: reconsume_in COMMENT_END
      else:
        parse_error NESTED_COMMENT
        reconsume_in COMMENT_END

    of COMMENT_END_DASH:
      case c
      of '-': switch_state COMMENT_END
      of eof:
        parse_error EOF_IN_COMMENT
        emit_tok
        emit_eof
      else:
        tokenizer.tok.data &= '-'
        reconsume_in COMMENT

    of COMMENT_END:
      case c
      of '>': switch_state DATA
      of '!': switch_state COMMENT_END_BANG
      of '-': tokenizer.tok.data &= '-'
      of eof:
        parse_error EOF_IN_COMMENT
        emit_tok
        emit_eof
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
      of eof:
        parse_error EOF_IN_COMMENT
        emit_tok
        emit_eof
      else:
        tokenizer.tok.data &= "--!"
        reconsume_in COMMENT

    of DOCTYPE:
      case c
      of AsciiWhitespace: switch_state BEFORE_DOCTYPE_NAME
      of '>': reconsume_in BEFORE_DOCTYPE_NAME
      of eof:
        parse_error EOF_IN_DOCTYPE
        new_token Token(t: DOCTYPE, quirks: true)
        emit_tok
        emit_eof
      else:
        parse_error MISSING_WHITESPACE_BEFORE_DOCTYPE_NAME
        reconsume_in BEFORE_DOCTYPE_NAME

    of BEFORE_DOCTYPE_NAME:
      case c
      of AsciiWhitespace: discard
      of AsciiUpperAlpha:
        new_token Token(t: DOCTYPE, name: some($c.tolower()))
        switch_state DOCTYPE_NAME
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        new_token Token(t: DOCTYPE, name: some($Rune(0xFFFD)))
      of '>':
        parse_error MISSING_DOCTYPE_NAME
        new_token Token(t: DOCTYPE, quirks: true)
        switch_state DATA
        emit_tok
      of eof:
        parse_error EOF_IN_DOCTYPE
        new_token Token(t: DOCTYPE, quirks: true)
        emit_tok
        emit_eof
      else:
        new_token Token(t: DOCTYPE, name: some($r))
        switch_state DOCTYPE_NAME

    of DOCTYPE_NAME:
      case c
      of AsciiWhitespace: switch_state AFTER_DOCTYPE_NAME
      of '>':
        switch_state DATA
        emit_tok
      of AsciiUpperAlpha:
        tokenizer.tok.name.get &= c.tolower()
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.tok.name.get &= Rune(0xFFFD)
      of eof:
        parse_error EOF_IN_DOCTYPE
        tokenizer.tok.quirks = true
        emit_tok
        emit_eof
      else:
        tokenizer.tok.name.get &= r

    of AFTER_DOCTYPE_NAME: # note: rewritten to fit case model as we consume a char anyway
      has_anything_else
      case c
      of AsciiWhitespace: discard
      of '>':
        switch_state DATA
        emit_tok
      of eof:
        parse_error EOF_IN_DOCTYPE
        tokenizer.tok.quirks = true
        emit_tok
        emit_eof
      of 'p', 'P':
        if peek_str("UBLIC"):
          consume_and_discard "UBLIC".len
          switch_state AFTER_DOCTYPE_PUBLIC_KEYWORD
        else:
          anything_else
      of 's', 'S':
        if peek_str("YSTEM"):
          consume_and_discard "YSTEM".len
          switch_state AFTER_DOCTYPE_SYSTEM_KEYWORD
        else:
          anything_else
      else:
        parse_error INVALID_CHARACTER_SEQUENCE_AFTER_DOCTYPE_NAME
        tokenizer.tok.quirks = true
        reconsume_in BOGUS_DOCTYPE

    of AFTER_DOCTYPE_PUBLIC_KEYWORD:
      case c
      of AsciiWhitespace: switch_state BEFORE_DOCTYPE_PUBLIC_IDENTIFIER
      of '"':
        parse_error MISSING_WHITESPACE_AFTER_DOCTYPE_PUBLIC_KEYWORD
        tokenizer.tok.pubid = some("")
        switch_state DOCTYPE_PUBLIC_IDENTIFIER_DOUBLE_QUOTED
      of '>':
        parse_error MISSING_DOCTYPE_PUBLIC_IDENTIFIER
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      of eof:
        parse_error EOF_IN_DOCTYPE
        tokenizer.tok.quirks = true
        emit_tok
        emit_eof
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
      of eof:
        parse_error EOF_IN_DOCTYPE
        tokenizer.tok.quirks = true
        emit_tok
        emit_eof
      else:
        parse_error MISSING_QUOTE_BEFORE_DOCTYPE_PUBLIC_IDENTIFIER
        tokenizer.tok.quirks = true
        reconsume_in BOGUS_DOCTYPE

    of DOCTYPE_PUBLIC_IDENTIFIER_DOUBLE_QUOTED:
      case c
      of '"': switch_state AFTER_DOCTYPE_PUBLIC_IDENTIFIER
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.tok.pubid.get &= Rune(0xFFFD)
      of '>':
        parse_error ABRUPT_DOCTYPE_PUBLIC_IDENTIFIER
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      of eof:
        parse_error EOF_IN_DOCTYPE
        tokenizer.tok.quirks = true
        emit_tok
        emit_eof
      else:
        tokenizer.tok.pubid.get &= r

    of DOCTYPE_PUBLIC_IDENTIFIER_SINGLE_QUOTED:
      case c
      of '\'': switch_state AFTER_DOCTYPE_PUBLIC_IDENTIFIER
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.tok.pubid.get &= Rune(0xFFFD)
      of '>':
        parse_error ABRUPT_DOCTYPE_PUBLIC_IDENTIFIER
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      of eof:
        parse_error EOF_IN_DOCTYPE
        tokenizer.tok.quirks = true
        emit_tok
        emit_eof
      else:
        tokenizer.tok.pubid.get &= r

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
      of eof:
        parse_error EOF_IN_DOCTYPE
        tokenizer.tok.quirks = true
        emit_tok
        emit_eof
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
      of eof:
        parse_error EOF_IN_DOCTYPE
        tokenizer.tok.quirks = true
        emit_tok
        emit_eof
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
      of eof:
        parse_error EOF_IN_DOCTYPE
        tokenizer.tok.quirks = true
        emit_tok
        emit_eof
      else:
        parse_error MISSING_QUOTE_BEFORE_DOCTYPE_SYSTEM_IDENTIFIER
        tokenizer.tok.quirks = true
        reconsume_in BOGUS_DOCTYPE

    of BEFORE_DOCTYPE_SYSTEM_IDENTIFIER:
      case c
      of AsciiWhitespace: discard
      of '"':
        tokenizer.tok.pubid = some("")
        switch_state DOCTYPE_SYSTEM_IDENTIFIER_DOUBLE_QUOTED
      of '\'':
        tokenizer.tok.pubid = some("")
        switch_state DOCTYPE_SYSTEM_IDENTIFIER_SINGLE_QUOTED
      of '>':
        parse_error MISSING_DOCTYPE_SYSTEM_IDENTIFIER
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      of eof:
        parse_error EOF_IN_DOCTYPE
        tokenizer.tok.quirks = true
        emit_tok
        emit_eof
      else:
        parse_error MISSING_QUOTE_BEFORE_DOCTYPE_SYSTEM_IDENTIFIER
        tokenizer.tok.quirks = true
        reconsume_in BOGUS_DOCTYPE

    of DOCTYPE_SYSTEM_IDENTIFIER_DOUBLE_QUOTED:
      case c
      of '"': switch_state AFTER_DOCTYPE_SYSTEM_IDENTIFIER
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.tok.sysid.get &= Rune(0xFFFD)
      of '>':
        parse_error ABRUPT_DOCTYPE_SYSTEM_IDENTIFIER
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      of eof:
        parse_error EOF_IN_DOCTYPE
        tokenizer.tok.quirks = true
        emit_tok
        emit_eof
      else:
        tokenizer.tok.sysid.get &= r

    of DOCTYPE_SYSTEM_IDENTIFIER_SINGLE_QUOTED:
      case c
      of '\'': switch_state AFTER_DOCTYPE_SYSTEM_IDENTIFIER
      of null:
        parse_error UNEXPECTED_NULL_CHARACTER
        tokenizer.tok.sysid.get &= Rune(0xFFFD)
      of '>':
        parse_error ABRUPT_DOCTYPE_SYSTEM_IDENTIFIER
        tokenizer.tok.quirks = true
        switch_state DATA
        emit_tok
      of eof:
        parse_error EOF_IN_DOCTYPE
        tokenizer.tok.quirks = true
        emit_tok
        emit_eof
      else:
        tokenizer.tok.sysid.get &= r

    of AFTER_DOCTYPE_SYSTEM_IDENTIFIER:
      case c
      of AsciiWhitespace: discard
      of '>':
        switch_state DATA
        emit_tok
      of eof:
        parse_error EOF_IN_DOCTYPE
        tokenizer.tok.quirks = true
        emit_tok
        emit_eof
      else:
        parse_error UNEXPECTED_CHARACTER_AFTER_DOCTYPE_SYSTEM_IDENTIFIER
        reconsume_in BOGUS_DOCTYPE

    of BOGUS_DOCTYPE:
      case c
      of '>':
        switch_state DATA
        emit_tok
      of null: parse_error UNEXPECTED_NULL_CHARACTER
      of eof:
        emit_tok
        emit_eof
      else: discard

    of CDATA_SECTION:
      case c
      of ']': switch_state CDATA_SECTION_BRACKET
      of eof:
        parse_error EOF_IN_CDATA
        emit_eof
      else:
        emit_current

    of CDATA_SECTION_BRACKET:
      case c
      of ']': switch_state CDATA_SECTION_END
      of '>': switch_state DATA
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
      tokenizer.tmp = "&"
      case c
      of AsciiAlpha: reconsume_in NAMED_CHARACTER_REFERENCE
      of '#':
        tokenizer.tmp &= '#'
        switch_state NUMERIC_CHARACTER_REFERENCE
      else:
        flush_code_points_consumed_as_a_character_reference
        reconsume_in tokenizer.rstate

    of NAMED_CHARACTER_REFERENCE:
      ignore_eof # we check for eof ourselves
      tokenizer.reconsume()
      when nimvm:
        error "Cannot evaluate character references at compile time"
      else:
        var tokenizerp = addr tokenizer
        var lasti = 0
        let value = entityMap.find(proc(s: var string): bool =
          if tokenizerp[].atEof:
            return false
          let rs = $tokenizerp[].consume()
          lasti = tokenizerp[].tmp.len
          tokenizerp[].tmp &= rs
          s &= rs
          return true
        )
        tokenizer.reconsume()
        tokenizer.tmp.setLen(lasti)
        if value.isSome:
          if consumed_as_an_attribute and tokenizer.tmp[^1] != ';' and peek_char in {'='} + AsciiAlpha:
            flush_code_points_consumed_as_a_character_reference
            switch_state tokenizer.rstate
          else:
            if tokenizer.tmp[^1] != ';':
              parse_error MISSING_SEMICOLON_AFTER_CHARACTER_REFERENCE
            tokenizer.tmp = value.get
            flush_code_points_consumed_as_a_character_reference
            switch_state tokenizer.rstate
        else:
          flush_code_points_consumed_as_a_character_reference
          switch_state AMBIGUOUS_AMPERSAND_STATE

    of AMBIGUOUS_AMPERSAND_STATE:
      case c
      of AsciiAlpha:
        if consumed_as_an_attribute:
          append_to_current_attr_value c
        else:
          emit_current
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
        tokenizer.code *= 0x10
        tokenizer.code += hexValue(c)
      of ';': switch_state NUMERIC_CHARACTER_REFERENCE_END
      else:
        parse_error MISSING_SEMICOLON_AFTER_CHARACTER_REFERENCE
        reconsume_in NUMERIC_CHARACTER_REFERENCE_END

    of DECIMAL_CHARACTER_REFERENCE:
      case c
      of AsciiDigit:
        tokenizer.code *= 10
        tokenizer.code += decValue(c)
      of ';': switch_state NUMERIC_CHARACTER_REFERENCE_END
      else:
        parse_error MISSING_SEMICOLON_AFTER_CHARACTER_REFERENCE
        reconsume_in NUMERIC_CHARACTER_REFERENCE_END

    of NUMERIC_CHARACTER_REFERENCE_END:
      ignore_eof # we reconsume anyway
      case tokenizer.code
      of 0x00:
        parse_error NULL_CHARACTER_REFERENCE
        tokenizer.code = 0xFFFD
      elif tokenizer.code > 0x10FFFF:
        parse_error CHARACTER_REFERENCE_OUTSIDE_UNICODE_RANGE
        tokenizer.code = 0xFFFD
      elif Rune(tokenizer.code).isSurrogate():
        parse_error SURROGATE_CHARACTER_REFERENCE
        tokenizer.code = 0xFFFD
      elif Rune(tokenizer.code).isNonCharacter():
        parse_error NONCHARACTER_CHARACTER_REFERENCE
        # do nothing
      elif tokenizer.code in 0..255 and char(tokenizer.code) in ((Controls - AsciiWhitespace) + {chr(0x0D)}):
        const ControlMapTable = [
          (0x80, 0x20AC), (0x82, 0x201A), (0x83, 0x0192), (0x84, 0x201E),
          (0x85, 0x2026), (0x86, 0x2020), (0x87, 0x2021), (0x88, 0x02C6),
          (0x89, 0x2030), (0x8A, 0x0160), (0x8B, 0x2039), (0x8C, 0x0152),
          (0x8E, 0x017D), (0x91, 0x2018), (0x92, 0x2019), (0x93, 0x201C),
          (0x94, 0x201D), (0x95, 0x2022), (0x96, 0x2013), (0x97, 0x2014),
          (0x98, 0x02DC), (0x99, 0x2122), (0x9A, 0x0161), (0x9B, 0x203A),
          (0x9C, 0x0153), (0x9E, 0x017E), (0x9F, 0x0178),
        ].toTable()
        if ControlMapTable.hasKey(tokenizer.code):
          tokenizer.code = ControlMapTable[tokenizer.code]
      tokenizer.tmp = $Rune(tokenizer.code)
      flush_code_points_consumed_as_a_character_reference #TODO optimize so we flush directly
      reconsume_in tokenizer.rstate # we unnecessarily consumed once so reconsume

    for tok in tokqueue:
      yield tok
    tokqueue.setLen(0)
