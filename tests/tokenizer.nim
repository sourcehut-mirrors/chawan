import json
import options
import streams
import tables
import unittest

import chame/parseerror
import chame/htmltokenizer
import chame/tags

import chakasu/decoderstream

proc getAttrs(o: JsonNode): Table[string, string] =
  for k, v in o:
    result[k] = v.getStr()

proc getToken(a: seq[JsonNode]): Token =
  case a[0].getStr()
  of "StartTag":
    return Token(
      t: START_TAG,
      tagname: a[1].getStr(),
      tagtype: tagType(a[1].getStr()),
      attrs: getAttrs(a[2]),
      selfclosing: a.len > 3 and a[3].getBool()
    )
  of "EndTag":
    return Token(
      t: END_TAG,
      tagname: a[1].getStr(),
      tagtype: tagType(a[1].getStr()),
      attrs: getAttrs(a[2])
    )
  of "Character":
    return Token(
      t: CHARACTER,
      s: a[1].getStr()
    )
  of "DOCTYPE":
    return Token(
      t: DOCTYPE,
      quirks: a[4].getBool(),
      name: if a[1].kind == JNull: none(string) else: some(a[1].getStr()),
      pubid: if a[2].kind == JNull: none(string) else: some(a[1].getStr()),
      sysid: if a[3].kind == JNull: none(string) else: some(a[1].getStr())
    )
  of "Comment":
    return Token(
      t: COMMENT,
      data: a[1].getStr()
    )
  else: discard

proc checkEquals(tok, otok: Token, desc: string) =
  doAssert otok.t == tok.t, desc
  case tok.t
  of TokenType.DOCTYPE:
    doAssert tok.name == otok.name, desc
    doAssert tok.pubid == otok.pubid, desc
    doAssert tok.sysid == otok.sysid, desc
    doAssert tok.quirks == otok.quirks, desc
  of TokenType.START_TAG, TokenType.END_TAG:
    doAssert tok.tagname == otok.tagname, desc
    doAssert tok.tagtype == otok.tagtype, desc
    doAssert tok.selfclosing == otok.selfclosing, desc
    doAssert tok.attrs == otok.attrs, desc
  of TokenType.CHARACTER, TokenType.CHARACTER_WHITESPACE:
    doAssert tok.s == otok.s, desc & " (tok s: " & tok.s & " otok s: " &
      otok.s & ")"
  of TokenType.COMMENT:
    doAssert tok.data == otok.data, desc
  of EOF: discard

proc runTest(desc, input: string, output: seq[JsonNode], laststart: string,
    state: TokenizerState = DATA) =
  echo desc
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
      let otok = getToken(output[i].getElems())
      checkEquals(chartok, otok, desc)
      inc i
      chartok = nil
    elif tok.t == EOF:
      break # html5lib-tests has no EOF tokens
    elif tok.t in {CHARACTER, CHARACTER_WHITESPACE}:
      if chartok == nil:
        chartok = Token(t: CHARACTER)
      chartok.s &= tok.s
    else:
      let otok = getToken(output[i].getElems())
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
    let input = t{"input"}.getStr()
    let output = t{"output"}.getElems()
    let laststart = if "lastStartTag" in t:
      t{"lastStartTag"}.getStr()
    else:
      ""
    if "initialStates" notin t:
      runTest(desc, input, output, laststart)
    else:
      for state in t{"initialStates"}:
        let state = getState(state.getStr())
        runTest(desc, input, output, laststart, state)

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

test "xmlViolation":
  runTests("xmlViolation.test")
