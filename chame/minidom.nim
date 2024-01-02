## Minimal DOMBuilder example. Implements the absolute minimum required
## for Chawan's HTML parser to work correctly.
##
## For an example of a complete implementation, see Chawan's chadombuilder.
##
## WARNING: this assumes *valid* UTF-8 to be the input encoding; text tokens
## containing invalid UTF-8 are silently discarded.
##
## For a variant that can switch encodings when meta tags are encountered etc.
## see `chame/minidom_cs <minidom.html>`.

import std/algorithm
import std/hashes
import std/options
import std/sets
import std/streams
import std/tables

import htmlparser
import htmltokenizer
import tags

export tags

# Atom implementation
#TODO maybe we should use a better hash map.
const MAtomFactoryStrMapLength = 1024 # must be a power of 2
static:
  doAssert (MAtomFactoryStrMapLength and (MAtomFactoryStrMapLength - 1)) == 0

type
  MAtom* = distinct int

  MAtomFactory* = ref object of RootObj
    strMap: array[MAtomFactoryStrMapLength, seq[MAtom]]
    atomMap: seq[string]

# Mandatory Atom functions
func `==`*(a, b: MAtom): bool {.borrow.}
func hash*(atom: MAtom): Hash {.borrow.}

func strToAtom*(factory: MAtomFactory, s: string): MAtom

proc newMAtomFactory*(): MAtomFactory =
  const minCap = int(TagType.high) + 1
  let factory = MAtomFactory(
    atomMap: newSeqOfCap[string](minCap),
  )
  factory.atomMap.add("") # skip TAG_UNKNOWN
  for tagType in TagType(int(TAG_UNKNOWN) + 1) .. TagType.high:
    discard factory.strToAtom($tagType)
  return factory

func strToAtom*(factory: MAtomFactory, s: string): MAtom =
  let h = s.hash()
  let i = h and (factory.strMap.len - 1)
  for atom in factory.strMap[i]:
    if factory.atomMap[int(atom)] == s:
      # Found
      return atom
  # Not found
  let atom = MAtom(factory.atomMap.len)
  factory.atomMap.add(s)
  factory.strMap[i].add(atom)
  return atom

func tagTypeToAtom*(factory: MAtomFactory, tagType: TagType): MAtom =
  assert tagType != TAG_UNKNOWN
  return MAtom(tagType)

func atomToStr*(factory: MAtomFactory, atom: MAtom): string =
  return factory.atomMap[int(atom)]

# Node types
type
  Attribute* = ParsedAttr[MAtom]

  Node* = ref object of RootObj
    nodeType*: NodeType
    childList*: seq[Node]
    parentNode* {.cursor.}: Node

  CharacterData* = ref object of Node
    data*: string

  Comment* = ref object of CharacterData

  Document* = ref object of Node
    factory*: MAtomFactory

  Text* = ref object of CharacterData

  DocumentType* = ref object of Node
    name*: string
    publicId*: string
    systemId*: string

  Element* = ref object of Node
    localName*: MAtom
    namespace*: Namespace
    attrs*: seq[Attribute]
    document*: Document

  DocumentFragment* = ref object of Node

  HTMLTemplateElement* = ref object of Element
    content*: DocumentFragment

type
  MiniDOMBuilder* = ref object of DOMBuilder[Node, MAtom]
    document*: Document
    factory*: MAtomFactory
    stream*: Stream

type
  DOMBuilderImpl = MiniDOMBuilder
  AtomImpl = MAtom
  HandleImpl = Node

include htmlparseriface

func toTagType*(atom: MAtom): TagType {.inline.} =
  if int(atom) <= int(high(TagType)):
    return TagType(atom)
  return TAG_UNKNOWN

func tagType*(element: Element): TagType =
  return element.localName.toTagType()

func cmp*(a, b: MAtom): int {.inline.} =
  return cmp(int(a), int(b))

# We use this to validate input strings, since htmltokenizer/htmlparser does no
# input validation.
proc toValidUTF8(s: string): string =
  result = ""
  var i = 0
  while i < s.len:
    if int(s[i]) < 0x80:
      result &= s[i]
      inc i
    elif int(s[i]) shr 5 == 0x6:
      if i + 1 < s.len and int(s[i + 1]) shr 6 == 2:
        result &= s[i]
        result &= s[i + 1]
      else:
        result &= "\uFFFD"
      i += 2
    elif int(s[i]) shr 4 == 0xE:
      if i + 2 < s.len and int(s[i + 1]) shr 6 == 2 and
          int(s[i + 2]) shr 6 == 2:
        result &= s[i]
        result &= s[i + 1]
        result &= s[i + 2]
      else:
        result &= "\uFFFD"
      i += 3
    elif int(s[i]) shr 3 == 0x1E:
      if i + 3 < s.len and int(s[i + 1]) shr 6 == 2 and
          int(s[i + 2]) shr 6 == 2 and int(s[i + 3]) shr 6 == 2:
        result &= s[i]
        result &= s[i + 1]
        result &= s[i + 2]
        result &= s[i + 3]
      else:
        result &= "\uFFFD"
      i += 4
    else:
      result &= "\uFFFD"
      inc i

proc localNameStr*(element: Element): string =
  return element.document.factory.atomToStr(element.localName)

iterator attrsStr*(element: Element): tuple[name, value: string] =
  let factory = element.document.factory
  for attr in element.attrs:
    var name = ""
    if attr.prefix != NO_PREFIX:
      name &= $attr.prefix & ':'
    name &= factory.atomToStr(attr.name)
    yield (name, attr.value)

# htmlparseriface implementation
proc getCharImpl(builder: MiniDOMBuilder): char =
  return builder.stream.readChar()

proc atEndImpl(builder: MiniDOMBuilder): bool =
  return builder.stream.atEnd()

proc strToAtomImpl(builder: MiniDOMBuilder, s: string): MAtom =
  return builder.factory.strToAtom(s)

proc tagTypeToAtomImpl(builder: MiniDOMBuilder, tagType: TagType): MAtom =
  return builder.factory.tagTypeToAtom(tagType)

proc atomToTagTypeImpl(builder: MiniDOMBuilder, atom: MAtom): TagType =
  return atom.toTagType()

proc getDocumentImpl(builder: MiniDOMBuilder): Node =
  return builder.document

proc getParentNodeImpl(builder: MiniDOMBuilder, handle: Node): Option[Node] =
  return option(handle.parentNode)

proc createElementImpl(builder: MiniDOMBuilder, localName: MAtom,
    namespace: Namespace, htmlAttrs: Table[MAtom, string],
    xmlAttrs: seq[Attribute]): Node =
  let element = if localName.toTagType() == TAG_TEMPLATE and
      namespace == Namespace.HTML:
    HTMLTemplateElement(
      content: DocumentFragment()
    )
  else:
    Element()
  element.nodeType = ELEMENT_NODE
  element.localName = localName
  element.namespace = namespace
  element.document = builder.document
  element.attrs = xmlAttrs
  for k, v in htmlAttrs:
    element.attrs.add((NO_PREFIX, NO_NAMESPACE, k, v.toValidUTF8()))
  element.attrs.sort(func(a, b: Attribute): int = cmp(a.name, b.name))
  return element

proc getLocalNameImpl(builder: MiniDOMBuilder, handle: Node): MAtom =
  return Element(handle).localName

proc getNamespaceImpl(builder: MiniDOMBuilder, handle: Node): Namespace =
  return Element(handle).namespace

proc getTemplateContentImpl(builder: MiniDOMBuilder, handle: Node): Node =
  return HTMLTemplateElement(handle).content

proc createCommentImpl(builder: MiniDOMBuilder, text: string): Node =
  return Comment(nodeType: COMMENT_NODE, data: text.toValidUTF8())

proc createDocumentTypeImpl(builder: MiniDOMBuilder, name, publicId,
    systemId: string): Node =
  return DocumentType(
    nodeType: DOCUMENT_TYPE_NODE,
    name: name.toValidUTF8(),
    publicId: publicId.toValidUTF8(),
    systemId: systemId.toValidUTF8()
  )

func countChildren(node: Node, nodeType: NodeType): int =
  for child in node.childList:
    if child.nodeType == nodeType:
      inc result

func hasChild(node: Node, nodeType: NodeType): bool =
  for child in node.childList:
    if child.nodeType == nodeType:
      return true

func isHostIncludingInclusiveAncestor(a, b: Node): bool =
  var b = b
  while b != nil:
    if b == a:
      return true
    b = b.parentNode

func hasPreviousSibling(node: Node, nodeType: NodeType): bool =
  for n in node.parentNode.childList:
    if n == node:
      break
    if n.nodeType == nodeType:
      return true
  return false

func hasNextSibling(node: Node, nodeType: NodeType): bool =
  for i in countdown(node.parentNode.childList.len, 0):
    let n = node.parentNode.childList[i]
    if n == node:
      break
    if n.nodeType == nodeType:
      return true
  return false

# WARNING the ordering of the arguments in the standard is whack so this
# doesn't match that
func preInsertionValidity*(parent, node: Node, before: Node): bool =
  if parent.nodeType notin {DOCUMENT_NODE, DOCUMENT_FRAGMENT_NODE, ELEMENT_NODE}:
    return false
  if node.isHostIncludingInclusiveAncestor(parent):
    return false
  if before != nil and before.parentNode != parent:
    return false
  if node.nodeType notin {DOCUMENT_FRAGMENT_NODE, DOCUMENT_TYPE_NODE,
      ELEMENT_NODE} + CharacterDataNodes:
    return false
  if node.nodeType == TEXT_NODE and parent.nodeType == DOCUMENT_NODE:
    return false
  if node.nodeType == DOCUMENT_TYPE_NODE and parent.nodeType != DOCUMENT_NODE:
    return false
  if parent.nodeType == DOCUMENT_NODE:
    case node.nodeType
    of DOCUMENT_FRAGMENT_NODE:
      let elems = node.countChildren(ELEMENT_NODE)
      if elems > 1 or node.hasChild(TEXT_NODE):
        return false
      elif elems == 1 and (parent.hasChild(ELEMENT_NODE) or
          before != nil and (before.nodeType == DOCUMENT_TYPE_NODE or
          before.hasNextSibling(DOCUMENT_TYPE_NODE))):
        return false
    of ELEMENT_NODE:
      if parent.hasChild(ELEMENT_NODE):
        return false
      elif before != nil and (before.nodeType == DOCUMENT_TYPE_NODE or
            before.hasNextSibling(DOCUMENT_TYPE_NODE)):
        return false
    of DOCUMENT_TYPE_NODE:
      if parent.hasChild(DOCUMENT_TYPE_NODE) or
          before != nil and before.hasPreviousSibling(ELEMENT_NODE) or
          before == nil and parent.hasChild(ELEMENT_NODE):
        return false
    else: discard
  return true # no exception reached

proc insertBefore(parent, child: Node, before: Option[Node]) =
  let before = before.get(nil)
  if parent.preInsertionValidity(child, before):
    assert child.parentNode == nil
    if before == nil:
      parent.childList.add(child)
    else:
      let i = parent.childList.find(before)
      parent.childList.insert(child, i)
    child.parentNode = parent

proc insertBeforeImpl(builder: MiniDOMBuilder, parent, child: Node,
    before: Option[Node]) =
  parent.insertBefore(child, before)

proc insertTextImpl(builder: MiniDOMBuilder, parent: Node, text: string,
    before: Option[Node]) =
  let text = text.toValidUTF8()
  let before = before.get(nil)
  let prevSibling = if before != nil:
    let i = parent.childList.find(before)
    if i == 0:
      nil
    else:
      parent.childList[i - 1]
  elif parent.childList.len > 0:
    parent.childList[^1]
  else:
    nil
  if prevSibling != nil and prevSibling.nodeType == TEXT_NODE:
    Text(prevSibling).data &= text
  else:
    let text = Text(nodeType: TEXT_NODE, data: text)
    parent.insertBefore(text, option(before))

proc removeImpl(builder: MiniDOMBuilder, child: Node) =
  if child.parentNode != nil:
    let i = child.parentNode.childList.find(child)
    child.parentNode.childList.delete(i)
    child.parentNode = nil

proc moveChildrenImpl(builder: MiniDOMBuilder, fromNode, toNode: Node) =
  let tomove = @(fromNode.childList)
  fromNode.childList.setLen(0)
  for child in tomove:
    child.parentNode = nil
    toNode.insertBefore(child, none(Node))

proc addAttrsIfMissingImpl(builder: MiniDOMBuilder, handle: Node,
    attrs: Table[MAtom, string]) =
  let element = Element(handle)
  var oldNames: HashSet[MAtom]
  for attr in element.attrs:
    oldNames.incl(attr.name)
  for name, value in attrs:
    if name notin oldNames:
      let value = value.toValidUTF8()
      element.attrs.add((NO_PREFIX, NO_NAMESPACE, name, value))
  element.attrs.sort(func(a, b: Attribute): int = cmp(a.name, b.name))

method setEncodingImpl(builder: MiniDOMBuilder, encoding: string):
    SetEncodingResult {.base.} =
  # Provided as a method for minidom_cs to override.
  return SET_ENCODING_CONTINUE

proc newMiniDOMBuilder*(stream: Stream, factory: MAtomFactory): MiniDOMBuilder =
  let document = Document(nodeType: DOCUMENT_NODE, factory: factory)
  let builder = MiniDOMBuilder(
    document: document,
    factory: factory,
    stream: stream
  )
  return builder

proc parseHTML*(inputStream: Stream, opts = HTML5ParserOpts[Node, MAtom](),
    factory = newMAtomFactory()): Document =
  ## Read, parse and return an HTML document from `inputStream`, using
  ## parser options `opts` and MAtom factory `factory`.
  ##
  ## `inputStream` is not required to be seekable.
  ##
  ## For a description of `HTML5ParserOpts`, see the `htmlparser` module's
  ## documentation.
  let builder = newMiniDOMBuilder(inputStream, factory)
  parseHTML(builder, opts)
  return builder.document

proc parseHTMLFragment*(inputStream: Stream, element: Element,
    opts: HTML5ParserOpts[Node, MAtom], factory = newMAtomFactory()):
    seq[Node] =
  ## Read, parse and return the children of an HTML fragment from `inputStream`,
  ## using context element `element` and parser options `opts`.
  ##
  ## For information on `opts` (an `HTML5ParserOpts` object), please consult
  ## the documentation of chame/htmlparser.nim.
  ##
  ## For details on the HTML fragment parsing algorithm, see
  ## https://html.spec.whatwg.org/multipage/parsing.html#parsing-html-fragments
  ##
  ## Note: the members `ctx`, `initialTokenizerState`, `openElementsInit` and
  ## `pushInTemplate` of `opts` are overridden (in accordance with the standard).
  let builder = newMiniDOMBuilder(inputStream, factory)
  let document = builder.document
  let state = if element.namespace != Namespace.HTML:
    DATA
  else:
    case element.tagType
    of TAG_TITLE, TAG_TEXTAREA: RCDATA
    of TAG_STYLE, TAG_XMP, TAG_IFRAME, TAG_NOEMBED, TAG_NOFRAMES: RAWTEXT
    of TAG_SCRIPT: SCRIPT_DATA
    of TAG_NOSCRIPT: DATA # no scripting
    of TAG_PLAINTEXT: PLAINTEXT
    else: DATA
  let htmlAtom = builder.factory.tagTypeToAtom(TAG_HTML)
  let root = Element(
    nodeType: ELEMENT_NODE,
    localName: htmlAtom,
    namespace: HTML,
    document: document
  )
  let rootToken = Token[MAtom](t: START_TAG, tagname: htmlAtom)
  document.childList = @[Node(root)]
  var opts = opts
  let token = Token[MAtom](t: START_TAG, tagname: element.localName)
  opts.ctx = some((Node(element), token))
  opts.initialTokenizerState = state
  opts.openElementsInit = @[(Node(root), rootToken)]
  opts.pushInTemplate = element.tagType == TAG_TEMPLATE
  parseHTML(builder, opts)
  return root.childList

proc parseHTMLFragment*(s: string, element: Element): seq[Node] =
  ## Convenience wrapper around parseHTMLFragment with opts.
  ##
  ## Read, parse and return the children of an HTML fragment from the string `s`,
  ## using context element `element`.
  ##
  ## For details on the HTML fragment parsing algorithm, see
  ## https://html.spec.whatwg.org/multipage/parsing.html#parsing-html-fragments
  let inputStream = newStringStream(s)
  let opts = HTML5ParserOpts[Node, MAtom](
    isIframeSrcdoc: false,
    scripting: false,
    pushInTemplate: element.tagType == TAG_TEMPLATE
  )
  return parseHTMLFragment(inputStream, element, opts)
