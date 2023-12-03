import streams
import tables
import options

import htmlparser
import htmltokenizer
import tags

import chakasu/charset

export charset
export tags

# Minimal DOMBuilder example. Implements the absolute minimum required
# for Chawan's HTML parser to work correctly.
# For an example of a complete implementation, see Chawan's chadombuilder.

# Node types
type
  Node* = ref object of RootObj
    nodeType*: NodeType
    childList*: seq[Node]
    parentNode* {.cursor.}: Node

  CharacterData* = ref object of Node
    data*: string

  Comment* = ref object of CharacterData

  Document* = ref object of Node

  Text* = ref object of CharacterData

  DocumentType* = ref object of Node
    name*: string
    publicId*: string
    systemId*: string

  Element* = ref object of Node
    tagType*: TagType
    localName*: string
    namespace*: Namespace
    attrs*: Table[string, string]

type
  MiniDOMBuilder = ref object of DOMBuilder[Node]

proc restart(builder: DOMBuilder[Node]) =
  builder.document = Document(nodeType: DOCUMENT_NODE)

proc getParentNode(builder: DOMBuilder[Node], handle: Node): Option[Node] =
  return option(handle.parentNode)

proc getTagType(builder: DOMBuilder[Node], handle: Node): TagType =
  return Element(handle).tagType

proc getLocalName(builder: DOMBuilder[Node], handle: Node): string =
  return Element(handle).localName

proc getNamespace(builder: DOMBuilder[Node], handle: Node): Namespace =
  return Element(handle).namespace

proc createElement(builder: DOMBuilder[Node], localName: string,
    namespace: Namespace, tagType: TagType,
    attrs: Table[string, string]): Node =
  let element = Element(
    nodeType: ELEMENT_NODE,
    localName: localName,
    namespace: namespace,
    tagType: tagType,
    attrs: attrs
  )
  return element

proc createComment(builder: DOMBuilder[Node], text: string): Node =
  return Comment(nodeType: COMMENT_NODE, data: text)

proc createDocumentType(builder: DOMBuilder[Node], name, publicId,
    systemId: string): Node =
  return DocumentType(nodeType: DOCUMENT_TYPE_NODE, name: name, publicId: publicId,
    systemId: systemId)

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

proc insertBefore(builder: DOMBuilder[Node], parent, child: Node,
    before: Option[Node]) =
  let before = before.get(nil)
  if parent.preInsertionValidity(child, before):
    assert child.parentNode == nil
    if before == nil:
      parent.childList.add(child)
    else:
      let i = parent.childList.find(before)
      parent.childList.insert(child, i)
    child.parentNode = parent

proc insertText(builder: DOMBuilder[Node], parent: Node, text: string,
    before: Node) =
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
    insertBefore(builder, parent, text, option(before))

proc remove(builder: DOMBuilder[Node], child: Node) =
  if child.parentNode != nil:
    let i = child.parentNode.childList.find(child)
    child.parentNode.childList.delete(i)
    child.parentNode = nil

proc moveChildren(builder: DOMBuilder[Node], fromNode, toNode: Node) =
  let tomove = @(fromNode.childList)
  fromNode.childList.setLen(0)
  for child in tomove:
    child.parentNode = nil
    insertBefore(builder, toNode, child, none(Node))

proc addAttrsIfMissing(builder: DOMBuilder[Node], element: Node,
    attrs: Table[string, string]) =
  let element = Element(element)
  for k, v in attrs:
    if k notin element.attrs:
      element.attrs[k] = v

proc newMiniDOMBuilder(): MiniDOMBuilder =
  let document = Document(nodeType: DOCUMENT_NODE)
  return MiniDOMBuilder(
    document: document,
    restart: restart,
    getTagType: getTagType,
    getParentNode: getParentNode,
    getLocalName: getLocalName,
    getNamespace: getNamespace,
    createElement: createElement,
    createComment: createComment,
    createDocumentType: createDocumentType,
    insertBefore: insertBefore,
    insertText: insertText,
    remove: remove,
    moveChildren: moveChildren,
    addAttrsIfMissing: addAttrsIfMissing,
  )

proc parseHTML*(inputStream: Stream, charsets: seq[Charset] = @[],
    canReinterpret = true): Document =
  ## Read, parse and return a HTML document from inputStream.
  ##
  ## `charsets` is a list of input character sets to try.
  ##
  ## `canReinterpret` signals to the parser whether the inputStream is seekable
  ## (e.g. if inputStream.setPosition(0) is valid).
  ##
  ## For more information on character set handling, please consult the
  ## documentation of chame/htmlparser.nim.
  let builder = newMiniDOMBuilder()
  let opts = HTML5ParserOpts[Node](
    isIframeSrcdoc: false,
    scripting: false,
    canReinterpret: canReinterpret,
    charsets: charsets
  )
  parseHTML(inputStream, builder, opts)
  return Document(builder.document)

proc parseHTML*(inputStream: Stream, opts: HTML5ParserOpts[Node]): Document =
  ## Read, parse and return a HTML document from `inputStream`, using
  ## parser options `opts`.
  ##
  ## For information on `opts` (a `HTML5ParserOpts` object), please consult
  ## the documentation of chame/htmlparser.nim.
  let builder = newMiniDOMBuilder()
  parseHTML(inputStream, builder, opts)
  return Document(builder.document)

proc parseHTMLFragment*(inputStream: Stream, element: Element,
    opts: HTML5ParserOpts[Node]): seq[Node] =
  ## Read, parse and return the children of a HTML fragment from `inputStream`,
  ## using context element `element` and parser options `opts`.
  ##
  ## For information on `opts` (a `HTML5ParserOpts` object), please consult
  ## the documentation of chame/htmlparser.nim.
  ##
  ## For details on the HTML fragment parsing algorithm, see
  ## https://html.spec.whatwg.org/multipage/parsing.html#parsing-html-fragments
  ##
  ## Note: the members `ctx`, `initialTokenizerState`, `openElementsInit` and
  ## `pushInTemplate` of `opts` are overridden (in accordance with the standard).
  let builder = newMiniDOMBuilder()
  let document = Document(builder.document)
  let state = case element.tagType
  of TAG_TITLE, TAG_TEXTAREA: RCDATA
  of TAG_STYLE, TAG_XMP, TAG_IFRAME, TAG_NOEMBED, TAG_NOFRAMES: RAWTEXT
  of TAG_SCRIPT: SCRIPT_DATA
  of TAG_NOSCRIPT: DATA # no scripting
  of TAG_PLAINTEXT: PLAINTEXT
  else: DATA
  let root = Element(nodeType: ELEMENT_NODE, tagType: TAG_HTML, namespace: HTML)
  document.childList = @[Node(root)]
  var opts = opts
  opts.ctx = some(Node(element))
  opts.initialTokenizerState = state
  opts.openElementsInit = @[Node(root)]
  opts.pushInTemplate = element.tagType == TAG_TEMPLATE
  parseHTML(inputStream, builder, opts)
  return root.childList

proc parseHTMLFragment*(s: string, element: Element): seq[Node] =
  ## Convenience wrapper around parseHTMLFragment with opts.
  ##
  ## Read, parse and return the children of a HTML fragment from the string `s`,
  ## using context element `element`.
  ##
  ## For details on the HTML fragment parsing algorithm, see
  ## https://html.spec.whatwg.org/multipage/parsing.html#parsing-html-fragments
  let inputStream = newStringStream(s)
  let opts = HTML5ParserOpts[Node](
    isIframeSrcdoc: false,
    scripting: false,
    canReinterpret: false,
    charsets: @[CHARSET_UTF_8],
    ctx: some(Node(element)),
    pushInTemplate: element.tagType == TAG_TEMPLATE
  )
  return parseHTMLFragment(inputStream, element, opts)
