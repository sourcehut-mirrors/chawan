import std/json
import std/options
import std/tables
import std/unicode
import std/unittest

import chame/htmltokenizer
import chame/minidom

proc hexValue*(c: char): int =
  if c in '0'..'9':
    return int(uint8(c) - uint8('0'))
  if c in 'a'..'f':
    return int(uint8(c) - uint8('a') + 0xA)
  if c in 'A'..'F':
    return int(uint8(c) - uint8('A') + 0xA)
  return -1

proc doubleEscape(input: string): string =
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

proc getToken(factory: MAtomFactory; a: seq[JsonNode]; esc: bool;
    name, pubid, sysid: var string; otherAttrs: var Table[MAtom, string]):
    Token[MAtom] =
  case a[0].getStr()
  of "StartTag":
    otherAttrs = getAttrs(factory, a[2], esc)
    return Token[MAtom](
      t: ttStartTag,
      tagname: factory.strToAtom(a[1].getStr()),
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
    name = a[1].getStr()
    pubid = a[2].getStr()
    sysid = a[3].getStr()
    return Token[MAtom](t: ttDoctype, flags: flags)
  of "Comment":
    let s = if esc:
      doubleEscape(a[1].getStr())
    else:
      a[1].getStr()
    return Token[MAtom](t: ttComment, s: s)
  else: return nil

proc checkEquals(factory: MAtomFactory; tok, otok: Token;
    tokenizer: Tokenizer[Node, MAtom];
    desc, otherName, otherPubid, otherSysid: string;
    otherAttrs: Table[MAtom, string]) =
  doAssert otok.t == tok.t, desc & " (tok t: " & $tok.t & " otok t: " &
    $otok.t & ")"
  case tok.t
  of ttDoctype:
    doAssert tokenizer.tagNameBuf == otherName, desc & " (" & "tok name: " &
      tokenizer.tagNameBuf & " otok name: " & otherName & ")"
    doAssert tokenizer.pubid == otherPubid, desc & " (" & "tok pubid: " &
      tokenizer.pubid & " otok pubid: " & otherPubid & ")"
    doAssert tokenizer.sysid == otherSysid, desc
    doAssert tok.flags == otok.flags, desc
  of ttStartTag, ttEndTag:
    doAssert tok.tagname == otok.tagname, desc & " (tok tagname: " &
      factory.atomToStr(tok.tagname) & " otok tagname " &
      factory.atomToStr(otok.tagname) & ")"
    if tok.t == ttStartTag: # otherwise a test incorrectly fails
      doAssert tok.flags == otok.flags, desc
    if tok.t == ttStartTag:
      var attrs = ""
      var i = 0
      for name, value in tokenizer.attrs:
        if i > 0:
          attrs &= " "
        attrs &= factory.atomToStr(name)
        attrs &= "="
        attrs &= "'" & value & "'"
        inc i
      var oattrs = ""
      i = 0
      for name, value in otherAttrs:
        if i > 0:
          oattrs &= " "
        oattrs &= factory.atomToStr(name)
        oattrs &= "="
        oattrs &= "'" & value & "'"
        inc i
      doAssert tokenizer.attrs == otherAttrs, desc & " (tok attrs: " & attrs &
        " otok attrs (" & oattrs & ")"
  of ttCharacter, ttWhitespace, ttComment:
    doAssert tok.s == otok.s, desc & " (tok s: " & tok.s & " otok s: " &
      otok.s & ")"
  of ttNull: discard

type TestContext = object
  chartok: Token[MAtom]
  output: seq[JsonNode]
  i: int
  factory: MAtomFactory
  desc: string
  esc: bool

proc checkTokens(ctx: var TestContext; tokenizer: var Tokenizer[Node, MAtom]) =
  for tok in tokenizer.tokqueue:
    var otherName, otherPubid, otherSysid: string
    var otherAttrs: Table[MAtom, string]
    check tok != nil
    if ctx.chartok != nil and tok.t notin {ttCharacter, ttWhitespace, ttNull}:
      let otok = getToken(ctx.factory, ctx.output[ctx.i].getElems(), ctx.esc,
        otherName, otherPubid, otherSysid, otherAttrs)
      checkEquals(ctx.factory, ctx.chartok, otok, tokenizer, ctx.desc,
        otherName, otherPubid, otherSysid, otherAttrs)
      inc ctx.i
      ctx.chartok = nil
    if tok.t in {ttCharacter, ttWhitespace}:
      if ctx.chartok == nil:
        ctx.chartok = Token[MAtom](t: ttCharacter)
      ctx.chartok.s &= tok.s
    elif tok.t == ttNull:
      if ctx.chartok == nil:
        ctx.chartok = Token[MAtom](t: ttCharacter)
      ctx.chartok.s &= char(0)
    else:
      let otok = getToken(ctx.factory, ctx.output[ctx.i].getElems(), ctx.esc,
        otherName, otherPubid, otherSysid, otherAttrs)
      checkEquals(ctx.factory, tok, otok, tokenizer, ctx.desc, otherName,
        otherPubid, otherSysid, otherAttrs)
      inc ctx.i

proc runTest(builder: MiniDOMBuilder; desc: string; output: seq[JsonNode];
    startTag: MAtom; esc: bool; input: string; state = tsData) =
  var tokenizer = newTokenizer(builder, state)
  var ctx = TestContext(
    factory: builder.factory,
    output: output,
    desc: desc,
    esc: esc
  )
  tokenizer.startTag = startTag
  while true:
    let res = tokenizer.tokenize(input.toOpenArray(0, input.high))
    ctx.checkTokens(tokenizer)
    if res == trDone:
      break
  while true:
    let res = tokenizer.finish()
    ctx.checkTokens(tokenizer)
    if res == trDone:
      break

proc getState(s: string): TokenizerState =
  case s
  of "Data state":
    return tsData
  of "PLAINTEXT state":
    return tsPlaintext
  of "RCDATA state":
    return tsRcdata
  of "RAWTEXT state":
    return tsRawtext
  of "Script data state":
    return tsScriptData
  of "CDATA section state":
    return tsCdataSection
  else:
    doAssert false, "Unknown state: " & s
    quit(1)

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
    let factory = newMAtomFactory()
    let builder = newMiniDOMBuilder(factory)
    let startTag = builder.factory.strToAtom(t{"lastStartTag"}.getStr())
    if "initialStates" notin t:
      runTest(builder, desc, output, startTag, esc, input)
    else:
      for state in t{"initialStates"}:
        let state = getState(state.getStr())
        runTest(builder, desc, output, startTag, esc, input, state)

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
