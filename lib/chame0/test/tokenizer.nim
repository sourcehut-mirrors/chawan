import std/json
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
    ParsedAttrs[MAtom] =
  result = @[]
  for k, v in o:
    let k = factory.strToAtom(k)
    var v = v.getStr()
    if esc:
      v = v.doubleEscape()
    result.add(ParsedAttr[MAtom](name: k, value: v))

proc getToken(factory: MAtomFactory; a: seq[JsonNode]; esc: bool;
    name: var string; otherAttrs: var ParsedAttrs[MAtom];
    flags: var set[TokenFlag]): TokenType =
  case a[0].getStr()
  of "StartTag":
    otherAttrs = getAttrs(factory, a[2], esc)
    if a.len > 3 and a[3].getBool():
      flags = {tfSelfClosing}
    name = a[1].getStr()
    return ttStartTag
  of "EndTag":
    name = a[1].getStr()
    return ttEndTag
  of "Character":
    name = if esc:
      doubleEscape(a[1].getStr())
    else:
      a[1].getStr()
    return ttCharacter
  of "DOCTYPE":
    if a[2].kind != JNull:
      flags.incl(tfPubid)
    if a[3].kind != JNull:
      flags.incl(tfSysid)
    if not a[4].getBool(): # yes, this is reversed. don't ask
      flags.incl(tfQuirks)
    name = a[1].getStr()
    let pubid = a[2].getStr()
    let sysid = a[3].getStr()
    if pubid.len > 0 or sysid.len > 0:
      name &= '\0' & pubid
    if sysid.len > 0:
      name &= '\0' & sysid
    return ttDoctype
  of "Comment":
    name = if esc:
      doubleEscape(a[1].getStr())
    else:
      a[1].getStr()
    return ttComment
  else:
    assert false
    return ttComment

proc checkEquals(factory: MAtomFactory; otok: TokenType;
    tok: Tokenizer[Node, MAtom]; charbuf, desc, otherName: string;
    otherAttrs: ParsedAttrs[MAtom]; flags: set[TokenFlag]) =
  doAssert otok == tok.t, desc & " (tok t: " & $tok.t & " otok t: " &
    $otok & ")"
  var name = tok.tagNameBuf
  case tok.t
  of ttDoctype:
    while name.len > 0 and name[^1] == '\0':
      name.setLen(name.high)
    doAssert name == otherName, desc & " (" & "tok name: " & name &
      " otok name: " & otherName & ")"
    doAssert tok.flags == flags, desc
  of ttStartTag, ttEndTag:
    let tagname = factory.strToAtom(name)
    doAssert tok.tagname == tagname, desc & " (tok tagname: " &
      factory.atomToStr(tok.tagname) & " otok tagname " &
      factory.atomToStr(tagname) & ")"
    if tok.t == ttStartTag: # otherwise a test incorrectly fails
      doAssert tok.flags == flags, desc
    if tok.t == ttStartTag:
      var attrs = ""
      var i = 0
      for attr in tok.attrs:
        if i > 0:
          attrs &= " "
        attrs &= factory.atomToStr(attr.name)
        attrs &= "="
        attrs &= "'" & attr.value & "'"
        inc i
      var oattrs = ""
      i = 0
      for attr in otherAttrs:
        if i > 0:
          oattrs &= " "
        oattrs &= factory.atomToStr(attr.name)
        oattrs &= "="
        oattrs &= "'" & attr.value & "'"
        inc i
      doAssert tok.attrs == otherAttrs, desc & " (tok attrs: " & attrs &
        " otok attrs (" & oattrs & ")"
  of ttCharacter, ttWhitespace:
    doAssert charbuf == otherName, desc & " (tok s: " & " otok s: " &
      ")"
  of ttComment:
    doAssert name == otherName, desc & " (tok s: " & name & " otok s: " &
      otherName & ")"
  of ttNull: discard

type TestContext = object
  charbuf: string
  output: seq[JsonNode]
  i: int
  factory: MAtomFactory
  desc: string
  esc: bool

proc checkCharbuf(ctx: var TestContext; tok: var Tokenizer[Node, MAtom]) =
  var otherName: string
  var otherAttrs: ParsedAttrs[MAtom]
  var flags: set[TokenFlag]
  if ctx.charbuf.len > 0 and tok.t notin {ttCharacter, ttWhitespace, ttNull}:
    let otok = getToken(ctx.factory, ctx.output[ctx.i].getElems(), ctx.esc,
      otherName, otherAttrs, flags)
    let tt = tok.t
    tok.t = ttCharacter
    checkEquals(ctx.factory, otok, tok, ctx.charbuf, ctx.desc, otherName,
      otherAttrs, flags)
    inc ctx.i
    ctx.charbuf = ""
    tok.t = tt

proc checkTokens(ctx: var TestContext; tok: var Tokenizer[Node, MAtom]) =
  ctx.checkCharbuf(tok)
  var otherName: string
  var otherAttrs: ParsedAttrs[MAtom]
  var flags: set[TokenFlag]
  if tok.t in {ttCharacter, ttWhitespace}:
    ctx.charbuf &= tok.charbufOut
  elif tok.t == ttNull:
    ctx.charbuf &= char(0)
  else:
    let otok = getToken(ctx.factory, ctx.output[ctx.i].getElems(), ctx.esc,
      otherName, otherAttrs, flags)
    checkEquals(ctx.factory, otok, tok, "", ctx.desc, otherName,
      otherAttrs, flags)
    inc ctx.i

proc runTest(builder: MiniDOMBuilder; desc: string; output: seq[JsonNode];
    startTag: MAtom; esc: bool; input: string; state: TokenizerState) =
  var tok = initTokenizer(builder)
  tok.state = state
  var ctx = TestContext(
    factory: builder.factory,
    output: output,
    desc: desc,
    esc: esc
  )
  tok.startTag = startTag
  while tok.tokenize(input.toOpenArray(0, input.high)) != trDone:
    ctx.checkTokens(tok)
  while tok.finish() != trDone:
    ctx.checkTokens(tok)
  if ctx.i < ctx.output.len:
    tok.t = ttStartTag # hack so checkCharbuf actually does something
    ctx.checkCharbuf(tok)
  assert ctx.i == ctx.output.len

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
    return tsData

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
      runTest(builder, desc, output, startTag, esc, input, tsData)
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
