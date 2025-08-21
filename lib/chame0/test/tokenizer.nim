import std/json
import std/options
import std/tables
import std/unicode
import std/unittest

import chame/htmltokenizer
import chame/minidom

const hexCharMap = (func(): array[char, int] =
  for i in 0..255:
    case chr(i)
    of '0'..'9': result[char(i)] = i - ord('0')
    of 'a'..'f': result[char(i)] = i - ord('a') + 10
    of 'A'..'F': result[char(i)] = i - ord('A') + 10
    else: result[char(i)] = -1
)()

func hexValue(c: char): int =
  return hexCharMap[c]

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

proc getAttrs(factory: MAtomFactory, o: JsonNode, esc: bool):
    Table[MAtom, string] =
  result = Table[MAtom, string]()
  for k, v in o:
    let k = factory.strToAtom(k)
    if esc:
      result[k] = v.getStr().doubleEscape()
    else:
      result[k] = v.getStr()

proc getToken(factory: MAtomFactory, a: seq[JsonNode], esc: bool):
    Token[MAtom] =
  case a[0].getStr()
  of "StartTag":
    return Token[MAtom](
      t: ttStartTag,
      tagname: factory.strToAtom(a[1].getStr()),
      attrs: getAttrs(factory, a[2], esc),
      flags: if a.len > 3 and a[3].getBool(): {tfSelfClosing} else: {}
    )
  of "EndTag":
    return Token[MAtom](
      t: ttEndTag,
      tagname: factory.strToAtom(a[1].getStr())
    )
  of "Character":
    let s = if esc:
      doubleEscape(a[1].getStr())
    else:
      a[1].getStr()
    return Token[MAtom](
      t: ttCharacter,
      s: s
    )
  of "DOCTYPE":
    var flags: set[TokenFlag] = {}
    if a[2].kind != JNull:
      flags.incl(tfPubid)
    if a[3].kind != JNull:
      flags.incl(tfSysid)
    if not a[4].getBool(): # yes, this is reversed. don't ask
      flags.incl(tfQuirks)
    return Token[MAtom](
      t: ttDoctype,
      name: if a[1].kind == JNull: "" else: a[1].getStr(),
      pubid: if a[2].kind == JNull: "" else: a[2].getStr(),
      sysid: if a[3].kind == JNull: "" else: a[3].getStr(),
      flags: flags
    )
  of "Comment":
    let s = if esc:
      doubleEscape(a[1].getStr())
    else:
      a[1].getStr()
    return Token[MAtom](t: ttComment, s: s)
  else: discard

proc checkEquals(factory: MAtomFactory, tok, otok: Token, desc: string) =
  doAssert otok.t == tok.t, desc & " (tok t: " & $tok.t & " otok t: " &
    $otok.t & ")"
  case tok.t
  of ttDoctype:
    doAssert tok.name == otok.name, desc & " (" & "tok name: " & $tok.name &
      " otok name: " & $otok.name & ")"
    doAssert tok.pubid == otok.pubid, desc & " (" & "tok pubid: " &
      $tok.pubid & " otok pubid: " & $otok.pubid & ")"
    doAssert tok.sysid == otok.sysid, desc
    doAssert tok.flags == otok.flags, desc
  of ttStartTag, ttEndTag:
    doAssert tok.tagname == otok.tagname, desc & " (tok tagname: " &
      factory.atomToStr(tok.tagname) & " otok tagname " &
      factory.atomToStr(otok.tagname) & ")"
    if tok.t == ttStartTag: # otherwise a test incorrectly fails
      doAssert tok.flags == otok.flags, desc
    var attrs = ""
    var i = 0
    for name, value in tok.attrs:
      if i > 0:
        attrs &= " "
      attrs &= factory.atomToStr(name)
      attrs &= "="
      attrs &= "'" & value & "'"
      inc i
    var oattrs = ""
    i = 0
    for name, value in otok.attrs:
      if i > 0:
        oattrs &= " "
      oattrs &= factory.atomToStr(name)
      oattrs &= "="
      oattrs &= "'" & value & "'"
      inc i
    doAssert tok.attrs == otok.attrs, desc & " (tok attrs: " & attrs &
      " otok attrs (" & oattrs & ")"
  of ttCharacter, ttWhitespace, ttComment:
    doAssert tok.s == otok.s, desc & " (tok s: " & tok.s & " otok s: " &
      otok.s & ")"
  of ttNull: discard

proc runTest(builder: MiniDOMBuilder, desc: string,
    output: seq[JsonNode], laststart: MAtom, esc: bool,
    input: string, state = TokenizerState.DATA) =
  let factory = builder.factory
  var tokenizer = newTokenizer(builder, state)
  tokenizer.laststart = Token[MAtom](t: ttStartTag, tagname: laststart)
  var i = 0
  var chartok: Token[MAtom] = nil
  var toks = newSeq[Token[MAtom]]()
  while true:
    let res = tokenizer.tokenize(input.toOpenArray(0, input.high))
    toks.add(tokenizer.tokqueue)
    if res == trDone:
      break
  while true:
    let res = tokenizer.finish()
    toks.add(tokenizer.tokqueue)
    if res == trDone:
      break
  for tok in toks:
    check tok != nil
    if chartok != nil and tok.t notin {ttCharacter, ttWhitespace, ttNull}:
      let otok = getToken(factory, output[i].getElems(), esc)
      checkEquals(factory, chartok, otok, desc)
      inc i
      chartok = nil
    if tok.t in {ttCharacter, ttWhitespace}:
      if chartok == nil:
        chartok = Token[MAtom](t: ttCharacter)
      chartok.s &= tok.s
    elif tok.t == ttNull:
      if chartok == nil:
        chartok = Token[MAtom](t: ttCharacter)
      chartok.s &= char(0)
    else:
      let otok = getToken(factory, output[i].getElems(), esc)
      checkEquals(factory, tok, otok, desc)
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

const rootpath = "test/html5lib-tests/tokenizer/"

proc runTests(filename: string) =
  let tests = parseFile(rootpath & filename){"tests"}
  for t in tests:
    let desc = t{"description"}.getStr()
    var input = t{"input"}.getStr()
    let esc = "doubleEscaped" in t and t{"doubleEscaped"}.getBool()
    if esc:
      input = doubleEscape(input)
    let output = t{"output"}.getElems()
    let laststart0 = if "lastStartTag" in t:
      t{"lastStartTag"}.getStr()
    else:
      ""
    let factory = newMAtomFactory()
    let builder = newMiniDOMBuilder(factory)
    let laststart = builder.factory.strToAtom(laststart0)
    if "initialStates" notin t:
      runTest(builder, desc, output, laststart, esc, input)
    else:
      for state in t{"initialStates"}:
        let state = getState(state.getStr())
        runTest(builder, desc, output, laststart, esc, input, state)

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
