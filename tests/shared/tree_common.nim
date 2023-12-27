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

func has(ctx: TCTestParser): bool =
  return ctx.i < ctx.s.len

proc reconsumeLine(ctx: var TCTestParser) =
  ctx.i = ctx.pi

proc consumeLine(ctx: var TCTestParser): string =
  ctx.pi = ctx.i
  while ctx.has:
    if ctx.s[ctx.i] == '\n':
      inc ctx.i
      break
    result &= ctx.s[ctx.i]
    inc ctx.i

proc parseTestData(ctx: var TCTestParser): string =
  while ctx.has:
    let line = ctx.consumeLine()
    if line == "#errors":
      return
    if result.len > 0:
      result &= '\n'
    result &= line
  doAssert false, "errors expected"

proc parseTestNewErrors(ctx: var TCTestParser): seq[TCError] =
  while ctx.has:
    let line = ctx.consumeLine()
    case line
    of "#document-fragment", "#script-off", "#script-on", "#document":
      ctx.reconsumeLine()
      return
    result.add(TCError(s: line))

proc parseTestErrors(ctx: var TCTestParser): seq[TCError] =
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
  let line = ctx.consumeLine()
  let fragmentType = if line.startsWith("svg"):
    FT_SVG
  elif line.startsWith("math"):
    FT_MATHML
  else:
    FT_HTML
  let namespace = case fragmentType
  of FT_SVG: Namespace.SVG
  of FT_MATHML: Namespace.MATHML
  of FT_HTML: Namespace.HTML
  let element = Element(
    nodeType: ELEMENT_NODE,
    namespace: namespace,
    localName: ctx.factory.strToAtom(line)
  )
  return TCFragment(
    fragmentType: fragmentType,
    ctx: element
  )

proc parseDoctype(s: string): DocumentType =
  let doctype = DocumentType(nodeType: DOCUMENT_TYPE_NODE)
  var i = "<!DOCTYPE ".len
  while i < s.len and s[i] != ' ' and s[i] != '>':
    doctype.name &= s[i]
    inc i
  if s[i] == '>':
    return doctype
  assert s[i] == ' '
  inc i
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
  assert s[i] == '"'
  inc i
  assert s[i] == '>'
  return doctype

proc parseComment(s: string): Comment =
  assert s.startsWith("<!-- ") and s.endsWith(" -->")
  return Comment(
    nodeType: COMMENT_NODE,
    data: s["<!-- ".len .. ^(" -->".len + 1)]
  )

proc parseTestDocument(ctx: var TCTestParser): Document =
  result = Document(nodeType: DOCUMENT_NODE, factory: ctx.factory)
  var stack: seq[Node]
  stack.add(result)
  template top: auto = stack[^1]
  var thistext: Text
  var indent = 1
  while ctx.has:
    let line = ctx.consumeLine()
    if line == "":
      break
    if thistext != nil:
      if line[^1] == '"':
        thistext.data &= line.substr(0, line.high - 1)
        thistext = nil
      else:
        thistext.data &= line & "\n"
      continue
    assert line[0] == '|' and line[1] == ' '
    while indent >= line.len or not line.startsWith('|' & ' '.repeat(indent)):
      discard stack.pop()
      indent -= 2
    let str = line.substr(indent + 1)
    if str.startsWith("<!DOCTYPE "):
      let doctype = parseDoctype(str)
      top.childList.add(doctype)
    elif str.startsWith("<!--"):
      let comment = parseComment(str)
      top.childList.add(comment)
    elif str.startsWith("<?"):
      assert false, "todo"
    elif str.startsWith("<"):
      let tagName = ctx.factory.strToAtom(str.substr(1, str.high - 1))
      let element = Element(
        nodeType: ELEMENT_NODE,
        namespace: HTML,
        localName: tagName,
        document: result
      )
      top.childList.add(element)
      stack.add(element)
      indent += 2
    elif str == "content":
      assert false, "todo"
    elif str[0] == '"':
      let text = Text(nodeType: TEXT_NODE)
      top.childList.add(text)
      if str[^1] != '"' or str.len == 1:
        text.data = str.substr(1) & "\n"
        thistext = text
      else:
        text.data = str.substr(1, str.high - 1)
    else:
      check '=' in str
      let ss = str.split('=')
      let name = ctx.factory.strToAtom(ss[0])
      let value = ss[1][1..^2]
      Element(top).attrs.add((NO_PREFIX, NO_NAMESPACE, name, value))

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
  check nodein.nodeType == nodep.nodeType
  check nodein.childList.len == nodep.childList.len
  case nodein.nodeType
  of ELEMENT_NODE:
    let nodein = Element(nodein)
    let nodep = Element(nodep)
    check nodein.localName == nodep.localName
    check nodein.namespace == nodep.namespace
    check nodein.attrs == nodep.attrs
  of ATTRIBUTE_NODE, ENTITY_REFERENCE_NODE, ENTITY_NODE,
      DOCUMENT_FRAGMENT_NODE, NOTATION_NODE:
    assert false
  of TEXT_NODE, CDATA_SECTION_NODE, COMMENT_NODE:
    check CharacterData(nodein).data == CharacterData(nodep).data
  of PROCESSING_INSTRUCTION_NODE: assert false, "todo"
  of DOCUMENT_TYPE_NODE:
    let nodein = DocumentType(nodein)
    let nodep = DocumentType(nodep)
    check nodein.name == nodep.name
    check nodein.publicId == nodep.publicId
    check nodein.systemId == nodep.systemId
  of DOCUMENT_NODE: discard
  for i in 0 ..< nodein.childList.len:
    checkTest(nodein.childList[i], nodep.childList[i])

