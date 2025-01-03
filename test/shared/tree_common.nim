import std/algorithm
import std/options
import std/strutils
import std/tables
import std/unittest

import test1
import chame/htmlparser
import chame/minidom

type
  TCError = object
    s: string

  FragmentType = enum
    FT_HTML, FT_SVG, FT_MATHML

  TCFragment = object
    fragmentType: FragmentType
    ctx: Element

  ScriptMode = enum
    SCRIPT_BOTH, SCRIPT_OFF, SCRIPT_ON

  TCTest = object
    data: string
    errors: seq[TCError]
    newerrors: seq[TCError]
    fragment: Option[TCFragment]
    script: ScriptMode
    document: Document

  TCTestParser = object
    s: string
    i: int
    pi: int
    factory: MAtomFactory
    linei: int

func has(ctx: TCTestParser): bool =
  return ctx.i < ctx.s.len

proc reconsumeLine(ctx: var TCTestParser) =
  ctx.i = ctx.pi
  dec ctx.linei

proc consumeLine(ctx: var TCTestParser): string =
  result = ""
  ctx.pi = ctx.i
  inc ctx.linei
  while ctx.has:
    if ctx.s[ctx.i] == '\n':
      inc ctx.i
      break
    result &= ctx.s[ctx.i]
    inc ctx.i

proc parseTestData(ctx: var TCTestParser): string =
  result = ""
  while ctx.has:
    let line = ctx.consumeLine()
    if line == "#errors":
      return
    if result.len > 0:
      result &= '\n'
    result &= line
  doAssert false, "errors expected"

proc parseTestNewErrors(ctx: var TCTestParser): seq[TCError] =
  result = @[]
  while ctx.has:
    let line = ctx.consumeLine()
    case line
    of "#document-fragment", "#script-off", "#script-on", "#document":
      ctx.reconsumeLine()
      return
    result.add(TCError(s: line))

proc parseTestErrors(ctx: var TCTestParser): seq[TCError] =
  result = @[]
  while ctx.has:
    let line = ctx.consumeLine()
    case line
    of "#new-errors":
      ctx.reconsumeLine()
      result.add(ctx.parseTestNewErrors())
      return
    of "#document-fragment", "#script-off", "#script-on", "#document":
      ctx.reconsumeLine()
      return
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
  of FT_SVG: Namespace.SVG
  of FT_MATHML: Namespace.MATHML
  of FT_HTML: Namespace.HTML
  let element = Element(
    namespace: namespace,
    localName: ctx.factory.strToAtom(line)
  )
  return TCFragment(
    fragmentType: fragmentType,
    ctx: element
  )

proc parseDoctype(ctx: TCTestParser, s: string): DocumentType =
  let doctype = DocumentType()
  var i = "<!DOCTYPE ".len
  while i < s.len and s[i] != ' ' and s[i] != '>':
    doctype.name &= s[i]
    inc i
  while s[i] == ' ':
    inc i
  if s[i] == '>':
    return doctype
  assert s[i] == '"'
  inc i
  while i < s.len and s[i] != '"':
    doctype.publicId &= s[i]
    inc i
  assert s[i] == '"'
  inc i
  assert s[i] == ' '
  inc i
  assert s[i] == '"'
  inc i
  while i < s.len and s[i] != '"':
    doctype.systemId &= s[i]
    inc i
  while i + 1 < s.len and s[i + 1] == '"':
    doctype.systemId &= s[i]
    inc i
  assert s[i] == '"'
  inc i
  assert s[i] == '>'
  return doctype

func until(s: string, c: set[char]): string =
  result = ""
  var i = 0
  while i < s.len:
    if s[i] in c:
      break
    result.add(s[i])
    inc i

func until(s: string, c: char): string = s.until({c})

func after(s: string, c: set[char]): string =
  var i = 0
  while i < s.len:
    if s[i] in c:
      return s.substr(i + 1)
    inc i
  return ""

func after(s: string, c: char): string = s.after({c})

proc parseTestDocument(ctx: var TCTestParser): Document =
  result = Document(factory: ctx.factory)
  var stack = @[Node(result)]
  template top: auto = stack[^1]
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
        thistext.data &= line & "\n"
      continue
    if thiscomment != nil:
      if line.endsWith(" -->"):
        thiscomment.data &= line.substr(0, line.high - " -->".len)
        thiscomment = nil
      else:
        thiscomment.data &= line & "\n"
      continue
    if line == "":
      break
    assert line[0] == '|' and line[1] == ' '
    while indent >= line.len or not line.startsWith('|' & ' '.repeat(indent)):
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
        comment.data = str.substr("<!-- ".len) & "\n"
        thiscomment = comment
      else:
        comment.data = str.substr("<!-- ".len, str.high - " -->".len)
    elif str.startsWith("<?"):
      assert false, "todo"
    elif str.startsWith("<") and str.endsWith(">"):
      var nameStr = str.substr(1, str.high - 1)
      var namespace = Namespace.HTML
      if nameStr.startsWith("svg "):
        nameStr = nameStr.substr("svg ".len)
        namespace = Namespace.SVG
      elif nameStr.startsWith("math "):
        nameStr = nameStr.substr("math ".len)
        namespace = Namespace.MATHML
      let element = if nameStr == "template":
        HTMLTemplateElement()
      else:
        Element()
      element.localName = ctx.factory.strToAtom(nameStr)
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
        text.data = str.substr(1) & "\n"
        thistext = text
      else:
        text.data = str.substr(1, str.high - 1)
    else:
      assert '=' in str
      var name = str.until('=')
      var prefix = NO_PREFIX
      var ns = NO_NAMESPACE
      if name.startsWith("xml "):
        ns = Namespace.XML
        prefix = PREFIX_XML
        name = name.substr("xml ".len)
      elif name.startsWith("xmlns "):
        ns = Namespace.XMLNS
        prefix = PREFIX_XMLNS
        name = name.substr("xmlns ".len)
      elif name.startsWith("xlink "):
        ns = Namespace.XLINK
        prefix = PREFIX_XLINK
        name = name.substr("xlink ".len)
      let na = ctx.factory.strToAtom(name)
      let value = str.after('=')[1..^2]
      Element(top).attrs.add((prefix, ns, na, value))
  while indent > 1:
    pop_node

proc parseTest(ctx: var TCTestParser): TCTest =
  doAssert ctx.consumeLine() == "#data"
  var t = TCTest()
  t.data = ctx.parseTestData()
  t.errors = ctx.parseTestErrors()
  while ctx.has:
    let line = ctx.consumeLine()
    case line
    of "#document-fragment":
      t.fragment = some(ctx.parseTestFragment())
    of "#script-off":
      t.script = SCRIPT_OFF
    of "#script-on":
      t.script = SCRIPT_ON
    of "#document":
      assert t.document == nil
      t.document = ctx.parseTestDocument()
      break
    of "":
      break
  return t

proc parseTests*(s: string, factory: MAtomFactory): seq[TCTest] =
  result = @[]
  var parser = TCTestParser(s: s, factory: factory)
  while parser.i < s.len:
    let test = parser.parseTest()
    result.add(test)
    var s = ""
    for x in test.document.childList:
      s &= $x & '\n'

proc checkTest(nodein, nodep: Node) =
  check nodein.childList.len == nodep.childList.len
  if nodein.childList.len != nodep.childList.len:
    echo nodein
    echo nodep
  if nodein of Element:
    check nodep of Element
    let nodein = Element(nodein)
    let nodep = Element(nodep)
    check nodein.localName == nodep.localName
    check nodein.namespace == nodep.namespace
    if nodein.attrs != nodep.attrs:
      echo "NODEIN", $nodein
      echo "NODEP", $nodep
    check nodein.attrs == nodep.attrs
  elif nodein of DocumentFragment:
    assert false
  elif nodein of CharacterData:
    check nodep of CharacterData
    check CharacterData(nodein).data == CharacterData(nodep).data
  elif nodein of DocumentType:
    check nodep of DocumentType
    let nodein = DocumentType(nodein)
    let nodep = DocumentType(nodep)
    check nodein.name == nodep.name
    check nodein.publicId == nodep.publicId
    check nodein.systemId == nodep.systemId
  for i in 0 ..< nodein.childList.len:
    checkTest(nodein.childList[i], nodep.childList[i])

