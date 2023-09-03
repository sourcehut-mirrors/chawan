import json
import options
import streams
import tables
import unicode
import unittest

import chame/htmltokenizer
import chame/parseerror
import chame/tags
import chame/utils/twtstr

import chakasu/decoderstream

func doubleEscape(input: string): string =
  var s = ""
  var esc = 0
  var u: uint32 = 0
  for c in input:
    if esc == 0:
      if c == '\\':
        inc esc
      else:
        s &= c
    elif esc == 1:
      if c == 'u':
        inc esc
      else:
        s &= '\\'
        dec esc
        s &= c
    elif esc < 6: # 2 + 4
      inc esc
      if esc == 3:
        u = 0x00
      let n = hexValue(c)
      doAssert n != -1
      u *= 0x10
      u += uint32(n)
      if esc == 6:
        s &= $cast[Rune](u)
        esc = 0
  return s

proc getAttrs(o: JsonNode, esc: bool): Table[string, string] =
  for k, v in o:
    if esc:
      result[k] = doubleEscape(v.getStr())
    else:
      result[k] = v.getStr()

proc getToken(a: seq[JsonNode], esc: bool): Token =
  case a[0].getStr()
  of "StartTag":
    return Token(
      t: START_TAG,
      tagname: a[1].getStr(),
      tagtype: tagType(a[1].getStr()),
      attrs: getAttrs(a[2], esc),
      selfclosing: a.len > 3 and a[3].getBool()
    )
  of "EndTag":
    return Token(
      t: END_TAG,
      tagname: a[1].getStr(),
      tagtype: tagType(a[1].getStr()),
    )
  of "Character":
    let s = if esc:
      doubleEscape(a[1].getStr())
    else:
      a[1].getStr()
    return Token(
      t: CHARACTER,
      s: s
    )
  of "DOCTYPE":
    return Token(
      t: DOCTYPE,
      quirks: not a[4].getBool(), # yes, this is reversed. don't ask
      name: if a[1].kind == JNull: none(string) else: some(a[1].getStr()),
      pubid: if a[2].kind == JNull: none(string) else: some(a[2].getStr()),
      sysid: if a[3].kind == JNull: none(string) else: some(a[3].getStr())
    )
  of "Comment":
    let s = if esc:
      doubleEscape(a[1].getStr())
    else:
      a[1].getStr()
    return Token(
      t: COMMENT,
      data: s
    )
  else: discard

proc checkEquals(tok, otok: Token, desc: string) =
  doAssert otok.t == tok.t, desc & " (tok t: " & $tok.t & " otok t: " &
    $otok.t & ")"
  case tok.t
  of TokenType.DOCTYPE:
    doAssert tok.name == otok.name, desc & " (" & "tok name: " & $tok.name &
      " otok name: " & $otok.name & ")"
    doAssert tok.pubid == otok.pubid, desc & " (" & "tok pubid: " &
      $tok.pubid & " otok pubid: " & $otok.pubid & ")"
    doAssert tok.sysid == otok.sysid, desc
    doAssert tok.quirks == otok.quirks, desc
  of TokenType.START_TAG, TokenType.END_TAG:
    doAssert tok.tagname == otok.tagname, desc & " (tok tagname: " &
      tok.tagname & " otok tagname " & otok.tagname & ")"
    doAssert tok.tagtype == otok.tagtype, desc
    if tok.t == TokenType.START_TAG:
      #TODO not sure if this is the best solution. but end tags can't really
      # be self-closing...
      # Maybe use a separate "self-closing tag" token type?
      doAssert tok.selfclosing == otok.selfclosing, desc
    doAssert tok.attrs == otok.attrs, desc & " (tok attrs: " & $tok.attrs &
      " otok attrs (" & $otok.attrs & ")"
  of TokenType.CHARACTER, TokenType.CHARACTER_WHITESPACE:
    doAssert tok.s == otok.s, desc & " (tok s: " & tok.s & " otok s: " &
      otok.s & ")"
  of TokenType.COMMENT:
    doAssert tok.data == otok.data, desc & " (tok data: " & tok.data &
      "otok data: " & otok.data & ")"
  of EOF: discard

proc runTest(desc, input: string, output: seq[JsonNode], laststart: string,
    esc: bool, state: TokenizerState = DATA) =
  let ss = newStringStream(input)
  let ds = newDecoderStream(ss)
  proc onParseError(e: ParseError) =
    discard
  var tokenizer = newTokenizer(ds, onParseError)
  tokenizer.laststart = Token(t: START_TAG, tagname: laststart)
  tokenizer.state = state
  var i = 0
  var chartok: Token = nil
  for tok in tokenizer.tokenize:
    check tok != nil
    if chartok != nil and tok.t notin {CHARACTER, CHARACTER_WHITESPACE}:
      let otok = getToken(output[i].getElems(), esc)
      checkEquals(chartok, otok, desc)
      inc i
      chartok = nil
    if tok.t == EOF:
      break # html5lib-tests has no EOF tokens
    elif tok.t in {CHARACTER, CHARACTER_WHITESPACE}:
      if chartok == nil:
        chartok = Token(t: CHARACTER)
      chartok.s &= tok.s
    else:
      let otok = getToken(output[i].getElems(), esc)
      checkEquals(tok, otok, desc)
      inc i

func getState(s: string): TokenizerState =
  case s
  of "Data state":
    return DATA
  of "PLAINTEXT state":
    return PLAINTEXT
  of "RCDATA state":
    return RCDATA
  of "RAWTEXT state":
    return RAWTEXT
  of "Script data state":
    return SCRIPT_DATA
  of "CDATA section state":
    return CDATA_SECTION
  else:
    doAssert false, "Unknown state: " & s

const rootpath = "tests/html5lib-tests/tokenizer/"

proc runTests(filename: string) =
  let tests = parseFile(rootpath & filename){"tests"}
  for t in tests:
    let desc = t{"description"}.getStr()
    var input = t{"input"}.getStr()
    let esc = "doubleEscaped" in t and t{"doubleEscaped"}.getBool()
    if esc:
      input = doubleEscape(input)
    let output = t{"output"}.getElems()
    let laststart = if "lastStartTag" in t:
      t{"lastStartTag"}.getStr()
    else:
      ""
    if "initialStates" notin t:
      runTest(desc, input, output, laststart, esc)
    else:
      for state in t{"initialStates"}:
        let state = getState(state.getStr())
        runTest(desc, input, output, laststart, esc, state)

test "contentModelFlags":
  runTests("contentModelFlags.test")

test "domjs":
  runTests("domjs.test")

test "entities":
  runTests("entities.test")

test "escapeFlag":
  runTests("escapeFlag.test")

test "namedEntities":
  runTests("namedEntities.test")

test "numericEntities":
  runTests("numericEntities.test")

#test "pendingSpecChanges":
#  runTests("pendingSpecChanges.test")

test "test1":
  runTests("test1.test")

test "test2":
  runTests("test2.test")

test "test3":
  runTests("test3.test")

test "test4":
  runTests("test4.test")

test "unicodeChars":
  runTests("unicodeChars.test")

test "unicodeCharsProblematic":
  runTests("unicodeCharsProblematic.test")

#test "xmlViolation":
#  runTests("xmlViolation.test")
