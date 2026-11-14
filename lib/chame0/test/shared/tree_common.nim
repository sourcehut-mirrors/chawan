when NimMajor >= 2:
  import std/assertions

import std/algorithm
import std/options
import std/unittest

import chame/htmlparser
import chame/minidom
import chame/tags
import html/catom
import utils/cowstr

type
  TCError = object
    s: Str

  FragmentType = enum
    FT_HTML, FT_SVG, FT_MATHML

  TCFragment = object
    fragmentType: FragmentType
    ctx: Element

  ScriptMode = enum
    smBoth, smOff, smOn

  TCTest = object
    data: Str
    errors: seq[TCError]
    newerrors: seq[TCError]
    fragment: Option[TCFragment]
    script: ScriptMode
    document: Document

  TCTestParser = object
    s: Str
    i: int
    pi: int
    linei: int

proc toStr(node: Node): Str =
  if node of Element:
    var buf = initGrowbuf()
    let element = Element(node)
    let x = if element.namespace == nsSVG:
      str("svg ")
    elif element.namespace == nsMathML:
      str("math ")
    else:
      str("")
    buf.addM('<', x, element.localName.toStr())
    for attr in element.attrs:
      buf.addM(' ', attr.name.toStr(), "=\"",
        attr.value.htmlEscape(emAttribute), "\"")
    buf &= ">"
    for node in element.childList:
      buf &= node.toStr()
    buf.addM("</", x, element.localName.toStr(), ">")
    return buf.toStr()
  elif node of Text:
    let text = Text(node)
    return text.data.htmlEscape(emText)
  elif node of Comment:
    return initStrM("<!-- ", Comment(node).data, "-->")
  elif node of DocumentType:
    return initStrM("<!DOCTYPE ", DocumentType(node).name, ">")
  elif node of Document:
    return initStrM("Node of Document")
  else:
    assert false
    return str("")

proc has(ctx: TCTestParser): bool =
  return ctx.i < ctx.s.len

proc reconsumeLine(ctx: var TCTestParser) =
  ctx.i = ctx.pi
  dec ctx.linei

proc consumeLine(ctx: var TCTestParser): Str =
  var buf = initGrowbuf()
  ctx.pi = ctx.i
  inc ctx.linei
  while ctx.has:
    if ctx.s[ctx.i] == '\n':
      inc ctx.i
      break
    buf &= ctx.s[ctx.i]
    inc ctx.i
  buf.toStr()

proc parseTestData(ctx: var TCTestParser): Str =
  var buf = initGrowbuf()
  while ctx.has:
    let line = ctx.consumeLine()
    if line == "#errors":
      return buf.toStr()
    if buf.len > 0:
      buf &= '\n'
    buf &= line
  doAssert false, "errors expected"
  buf.toStr()

proc parseTestNewErrors(ctx: var TCTestParser): seq[TCError] =
  result = @[]
  while ctx.has:
    let line = ctx.consumeLine()
    if line == "#document-fragment" or line == "#script-off" or
        line == "#script-on" or line == "#document":
      ctx.reconsumeLine()
      break
    else:
      result.add(TCError(s: line))

proc parseTestErrors(ctx: var TCTestParser): seq[TCError] =
  result = @[]
  while ctx.has:
    let line = ctx.consumeLine()
    if line == "#new-errors":
      ctx.reconsumeLine()
      result.add(ctx.parseTestNewErrors())
      break
    elif line == "#document-fragment" or line == "#script-off" or
        line == "#script-on" or line == "#document":
      ctx.reconsumeLine()
      break
    else:
      result.add(TCError(s: line))

proc parseTestFragment(ctx: var TCTestParser): TCFragment =
  var line = ctx.consumeLine()
  var fragmentType = FT_HTML
  if line.startsWith("svg "):
    fragmentType = FT_SVG
    line = line.substr("svg ".len)
  elif line.startsWith("math "):
    fragmentType = FT_MATHML
    line = line.substr("math ".len)
  let namespace = case fragmentType
  of FT_SVG: nsSVG
  of FT_MATHML: nsMathML
  of FT_HTML: nsHTML
  let element = Element(
    namespace: namespace,
    localName: line.toAtom()
  )
  return TCFragment(
    fragmentType: fragmentType,
    ctx: element
  )

proc parseDoctype(ctx: TCTestParser; s: Str): DocumentType =
  let doctype = DocumentType()
  var i = "<!DOCTYPE ".len
  var name = initGrowbuf()
  while i < s.len and s[i] != ' ' and s[i] != '>':
    name &= s[i]
    inc i
  doctype.name = name.toStr()
  while s[i] == ' ':
    inc i
  if s[i] == '>':
    return doctype
  assert s[i] == '"'
  inc i
  var publicId = initGrowbuf()
  while i < s.len and s[i] != '"':
    publicId &= s[i]
    inc i
  doctype.publicId = publicId.toStr()
  assert s[i] == '"'
  inc i
  assert s[i] == ' '
  inc i
  assert s[i] == '"'
  inc i
  var systemId = initGrowbuf()
  while i < s.len and s[i] != '"':
    systemId &= s[i]
    inc i
  while i + 1 < s.len and s[i + 1] == '"':
    systemId &= s[i]
    inc i
  doctype.systemId = systemId.toStr()
  assert s[i] == '"'
  inc i
  assert s[i] == '>'
  return doctype

proc parseTestDocument(ctx: var TCTestParser): Document =
  result = Document()
  var stack = @[Node(result)]
  template top: untyped = stack[^1]
  var thistext: Text = nil
  var thiscomment: Comment = nil
  var indent = 1
  template pop_node =
    let node = stack.pop()
    if node of Element:
      Element(node).attrs.sort(proc(a, b: Attribute): int = cmp(a.name, b.name))
    indent -= 2
  while ctx.has:
    let line = ctx.consumeLine()
    if thistext != nil:
      if line.endsWith("\""):
        thistext.data &= line.substr(0, line.high - 1)
        thistext = nil
      else:
        thistext.data &= line
        thistext.data &= "\n"
      continue
    if thiscomment != nil:
      if line.endsWith(" -->"):
        thiscomment.data &= line.substr(0, line.high - " -->".len)
        thiscomment = nil
      else:
        thiscomment.data &= line
        thiscomment.data &= "\n"
      continue
    if line == "":
      break
    assert line[0] == '|' and line[1] == ' '
    while true:
      let target = initStrM('|', ' '.repeat(indent))
      if indent < line.len and line.startsWith(target):
        break
      let node = stack.pop()
      if node of Element:
        Element(node).attrs.sort(proc(a, b: Attribute): int = cmp(a.name, b.name))
      indent -= 2
    let str = line.substr(indent + 1)
    if str.startsWith("<!DOCTYPE "):
      let doctype = ctx.parseDoctype(str)
      top.childList.add(doctype)
    elif str.startsWith("<!-- "):
      let comment = minidom.Comment()
      top.childList.add(comment)
      if not str.endsWith(" -->"):
        comment.data = initStrM(str.substr("<!-- ".len), "\n")
        thiscomment = comment
      else:
        comment.data = str.substr("<!-- ".len, str.high - " -->".len)
    elif str.startsWith("<?"):
      assert false, "todo"
    elif str.startsWith("<") and str.endsWith(">"):
      var nameStr = str.substr(1, str.high - 1)
      var namespace = nsHTML
      if nameStr.startsWith("svg "):
        nameStr = nameStr.substr("svg ".len)
        namespace = nsSVG
      elif nameStr.startsWith("math "):
        nameStr = nameStr.substr("math ".len)
        namespace = nsMathML
      let element = if nameStr == "template":
        HTMLTemplateElement()
      else:
        Element()
      element.localName = nameStr.toAtom()
      element.namespace = namespace
      element.document = result
      top.childList.add(element)
      stack.add(element)
      indent += 2
    elif str == "content":
      let fragment = DocumentFragment()
      HTMLTemplateElement(top).content = fragment
      stack.add(fragment)
      indent += 2
    elif str[0] == '"':
      let text = Text()
      top.childList.add(text)
      if str[^1] != '"' or str.len == 1:
        text.data = initStrM(str.substr(1), "\n")
        thistext = text
      else:
        text.data = str.substr(1, str.high - 1)
    else:
      assert '=' in str
      var name = str.until('=')
      var prefix = str("")
      var ns: CAtom
      if name.startsWith("xml "):
        ns = satNamespaceXML.view()
        prefix = str("xml:")
        name = name.substr("xml ".len)
      elif name.startsWith("xmlns "):
        ns = satNamespaceXMLNS.view()
        prefix = str("xmlns:")
        name = name.substr("xmlns ".len)
      elif name.startsWith("xlink "):
        ns = satNamespaceXLink.view()
        prefix = str("xlink:")
        name = name.substr("xlink ".len)
      let na = initStrM(prefix, name).toAtom()
      let value0 = str.after('=')
      let value = value0.substr(1, value0.len - 2)
      Element(top).attrs.add(Attribute(name: na, value: value, namespace: ns))
  while indent > 1:
    pop_node

proc parseTest(ctx: var TCTestParser): TCTest =
  doAssert ctx.consumeLine() == "#data"
  var t = TCTest()
  t.data = ctx.parseTestData()
  t.errors = ctx.parseTestErrors()
  while ctx.has:
    let line = ctx.consumeLine()
    if line == "#document-fragment":
      t.fragment = some(ctx.parseTestFragment())
    elif line == "#script-off":
      t.script = smOff
    elif line == "#script-on":
      t.script = smOn
    elif line == "#document":
      assert t.document == nil
      t.document = ctx.parseTestDocument()
      break
    elif line == "":
      break
  return t

proc parseTests*(s: Str): seq[TCTest] =
  result = @[]
  var parser = TCTestParser(s: s)
  while parser.i < s.len:
    let test = parser.parseTest()
    result.add(test)
    var s = initGrowbuf()
    for x in test.document.childList:
      s.addM(x.toStr(), '\n')

proc checkTest(testNode, parsedNode: Node) =
  check testNode.childList.len == parsedNode.childList.len
  if testNode.childList.len != parsedNode.childList.len:
    echo $testNode.toStr()
    echo $parsedNode.toStr()
  if testNode of Element:
    check parsedNode of Element
    let testNode = Element(testNode)
    let parsedNode = Element(parsedNode)
    check testNode.localName == parsedNode.localName
    check testNode.namespace == parsedNode.namespace
    if testNode.localName != parsedNode.localName or
        testNode.attrs != parsedNode.attrs:
      echo "EXPECTED", $testNode.toStr()
      echo "PARSED", $parsedNode.toStr()
    check testNode.attrs == parsedNode.attrs
  elif testNode of DocumentFragment:
    assert false
  elif testNode of CharacterData:
    check parsedNode of CharacterData
    check CharacterData(testNode).data == CharacterData(parsedNode).data
  elif testNode of DocumentType:
    check parsedNode of DocumentType
    let testNode = DocumentType(testNode)
    let parsedNode = DocumentType(parsedNode)
    check testNode.name == parsedNode.name
    check testNode.publicId == parsedNode.publicId
    check testNode.systemId == parsedNode.systemId
  if testNode.childList.len == parsedNode.childList.len:
    for i in 0 ..< testNode.childList.len:
      checkTest(testNode.childList[i], parsedNode.childList[i])

initCAtomFactory()
