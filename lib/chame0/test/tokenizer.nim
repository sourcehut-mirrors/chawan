when NimMajor >= 2:
  import std/assertions

import std/json
import std/unittest

import chame/htmltokenizer
import chame/tags
import html/catom
import utils/cowstr

proc hexValue*(c: char): int =
  if c in '0'..'9':
    return int(uint8(c) - uint8('0'))
  if c in 'a'..'f':
    return int(uint8(c) - uint8('a') + 0xA)
  if c in 'A'..'F':
    return int(uint8(c) - uint8('A') + 0xA)
  return -1

proc doubleEscape(input: Str): Str =
  var s = initGrowbuf()
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
        s.addUTF8(u)
        esc = 0
  s.toStr()

proc getAttrs(o: JsonNode; esc: bool): seq[AttrData] =
  result = @[]
  for k, v in o:
    let k = k.toAtom()
    var v = newStr(v.getStr())
    if esc:
      v = v.doubleEscape()
    result.add(AttrData(name: k, value: v))

proc getToken(a: seq[JsonNode]; esc: bool; name: var Str;
    otherAttrs: var seq[AttrData]; flags: var set[TokenFlag]): TokenType =
  case a[0].getStr()
  of "StartTag":
    otherAttrs = getAttrs(a[2], esc)
    if a.len > 3 and a[3].getBool():
      flags = {tfSelfClosing}
    name = newStr(a[1].getStr())
    return ttStartTag
  of "EndTag":
    name = newStr(a[1].getStr())
    return ttEndTag
  of "Character":
    name = if esc:
      doubleEscape(newStr(a[1].getStr()))
    else:
      newStr(a[1].getStr())
    return ttCharacter
  of "DOCTYPE":
    if not a[4].getBool(): # yes, this is reversed. don't ask
      flags.incl(tfQuirks)
    name = newStr(a[1].getStr())
    let pubid = a[2].getStr()
    let sysid = a[3].getStr()
    if pubid.len > 0 or sysid.len > 0:
      name &= initStrM('\0', newStr(pubid))
    if sysid.len > 0:
      name &= initStrM('\0', newStr(sysid))
    return ttDoctype
  of "Comment":
    name = if esc:
      doubleEscape(newStr(a[1].getStr()))
    else:
      newStr(a[1].getStr())
    return ttComment
  else:
    assert false
    return ttComment

proc checkEquals(otok: TokenType; tok: Tokenizer;
    charbuf, desc, otherName: Str; otherAttrs: seq[AttrData];
    flags: set[TokenFlag]) =
  check otok == tok.t
  var name = initStr(tok.tagNameBuf.toOpenArray())
  case tok.t
  of ttDoctype:
    while name.len > 0 and name[^1] == '\0':
      name.setLen(name.high)
    check name == otherName
    check tok.flags == flags
  of ttStartTag, ttEndTag:
    let tagname = name.toAtom()
    check tok.tagname == tagname
    if tok.t == ttStartTag: # otherwise a test incorrectly fails
      check tok.flags == flags
    if tok.t == ttStartTag:
      var attrs = initGrowbuf()
      var i = 0
      for attr in tok.attrs:
        if i > 0:
          attrs &= " "
        attrs.addM(attr.name.toStr(), "='", attr.value, "'")
        inc i
      var oattrs = initGrowbuf()
      i = 0
      for attr in otherAttrs:
        if i > 0:
          oattrs &= " "
        oattrs.addM(attr.name.toStr(), "='", attr.value, "'")
        inc i
      check tok.attrs == otherAttrs
  of ttCharacter, ttWhitespace:
    check charbuf == otherName
  of ttComment:
    check name == otherName
  of ttNull: discard

type TestContext = object
  charbuf: Growbuf
  output: seq[JsonNode]
  i: int
  desc: Str
  esc: bool

proc checkCharbuf(ctx: var TestContext; tok: var Tokenizer) =
  var otherName: Str
  var otherAttrs: seq[AttrData]
  var flags: set[TokenFlag]
  if ctx.charbuf.len > 0 and tok.t notin {ttCharacter, ttWhitespace, ttNull}:
    let otok = getToken(ctx.output[ctx.i].getElems(), ctx.esc, otherName,
      otherAttrs, flags)
    let tt = tok.t
    tok.t = ttCharacter
    checkEquals(otok, tok, move(ctx.charbuf).toStr(), ctx.desc, otherName,
      otherAttrs, flags)
    inc ctx.i
    tok.t = tt

proc checkTokens(ctx: var TestContext; tok: var Tokenizer) =
  ctx.checkCharbuf(tok)
  var otherName: Str
  var otherAttrs: seq[AttrData]
  var flags: set[TokenFlag]
  if tok.t in {ttCharacter, ttWhitespace}:
    ctx.charbuf &= tok.charbuf
  elif tok.t == ttNull:
    ctx.charbuf &= char(0)
  else:
    let otok = getToken(ctx.output[ctx.i].getElems(), ctx.esc, otherName,
      otherAttrs, flags)
    checkEquals(otok, tok, str(""), ctx.desc, otherName, otherAttrs, flags)
    inc ctx.i

proc runTest(desc: Str; output: seq[JsonNode]; startTag: CAtom; esc: bool;
    input: Str; state: TokenizerState) =
  var tok = initTokenizer()
  tok.state = state
  var ctx = TestContext(
    output: output,
    desc: desc,
    esc: esc
  )
  tok.startTag = startTag.toTagType()
  if tok.startTag == ttUnknown:
    # hack: the parser is guaranteed to set a specific set of start tags,
    # but some tokenizer tests don't set it.
    # setting it to script could still fail in some cases, but it doesn't
    # in practice.
    tok.startTag = ttScript
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
    let desc = newStr(t{"description"}.getStr())
    var input = newStr(t{"input"}.getStr())
    let esc = "doubleEscaped" in t and t{"doubleEscaped"}.getBool()
    if esc:
      input = doubleEscape(input)
    let output = t{"output"}.getElems()
    let startTag = t{"lastStartTag"}.getStr().toAtom()
    if "initialStates" notin t:
      runTest(desc, output, startTag, esc, input, tsData)
    else:
      for state in t{"initialStates"}:
        let state = getState(state.getStr())
        runTest(desc, output, startTag, esc, input, state)

initCAtomFactory()

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
