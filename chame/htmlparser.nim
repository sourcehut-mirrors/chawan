import std/macros
import std/options
import std/streams
import std/strutils
import std/tables

import atoms
import htmltokenizer
import parseerror
import tags
import utils/twtstr

# Generics break without exporting macros. Maybe a compiler bug?
export macros
export TokenAttr

# Heavily inspired by html5ever's TreeSink design.
type
  DOMBuilder*[Handle, Atom] = ref object of RootObj
    getDocument*: DOMBuilderGetDocument[Handle, Atom]
    ## Must never be nil.
    getAtomFactory*: DOMBuilderGetAtomFactory[Handle, Atom]
    ## Must never be nil.
    finish*: DOMBuilderFinish[Handle, Atom]
    ## May be nil.
    parseError*: DOMBuilderParseError[Handle, Atom]
    ## May be nil.
    setQuirksMode*: DOMBuilderSetQuirksMode[Handle, Atom]
    ## May be nil
    setEncoding*: DOMBuilderSetEncoding[Handle, Atom]
    ## May be nil.
    elementPopped*: DOMBuilderElementPopped[Handle, Atom]
    ## May be nil.
    getTemplateContent*: DOMBuilderGetTemplateContent[Handle, Atom]
    ## May be nil. (If nil, templates are treated as regular elements.)
    getParentNode*: DOMBuilderGetParentNode[Handle, Atom]
    ## Must never be nil.
    getLocalName*: DOMBuilderGetLocalName[Handle, Atom]
    ## Must never be nil.
    getNamespace*: DOMBuilderGetNamespace[Handle, Atom]
    ## May be nil. (If nil, the parser always uses the HTML namespace.)
    createElement*: DOMBuilderCreateElement[Handle, Atom]
    ## Must never be nil.
    createComment*: DOMBuilderCreateComment[Handle, Atom]
    ## Must never be nil.
    createDocumentType*: DOMBuilderCreateDocumentType[Handle, Atom]
    ## Must never be nil.
    insertBefore*: DOMBuilderInsertBefore[Handle, Atom]
    ## Must never be nil.
    insertText*: DOMBuilderInsertText[Handle, Atom]
    ## Must never be nil.
    remove*: DOMBuilderRemove[Handle, Atom]
    ## Must never be nil.
    moveChildren*: DOMBuilderMoveChildren[Handle, Atom]
    ## Must never be nil.
    addAttrsIfMissing*: DOMBuilderAddAttrsIfMissing[Handle, Atom]
    ## May be nil. (If nil, some attributes may not be added to the HTML or
    ## BODY element if more than one of their respective opening tags exist.)
    setScriptAlreadyStarted*: DOMBuilderSetScriptAlreadyStarted[Handle, Atom]
    ## May be nil.
    associateWithForm*: DOMBuilderAssociateWithForm[Handle, Atom]
    ## May be nil.

  ParsedAttr*[Atom] = tuple
    prefix: NamespacePrefix
    namespace: Namespace
    name: Atom
    value: string

  SetEncodingResult* = enum
    SET_ENCODING_STOP, SET_ENCODING_CONTINUE

  HTML5ParserOpts*[Handle, Atom] = object
    isIframeSrcdoc*: bool
    ## Is the document an iframe srcdoc?
    scripting*: bool
    ## Is scripting enabled for this document?
    ctx*: Option[OpenElement[Handle, Atom]]
    ## Context element for fragment parsing. When set to some Handle,
    ## the fragment case is used while parsing.
    ##
    ## `token` must be a valid starting token for this element.
    initialTokenizerState*: TokenizerState
    ## The initial tokenizer state; by default, this is DATA.
    openElementsInit*: seq[OpenElement[Handle, Atom]]
    ## Initial state of the stack of open elements. By default, the stack
    ## starts out empty.
    ## Note: if this is initialized to a non-empty sequence, the parser will
    ## start by resetting the insertion mode appropriately.
    formInit*: Option[Handle]
    ## Initial state of the parser's form pointer.
    pushInTemplate*: bool
    ## When set to true, the "in template" insertion mode is pushed to the
    ## stack of template insertion modes on parser start.

  OpenElement*[Handle, Atom] = tuple
    element: Handle
    token: Token[Atom] ## the element's start tag token; must not be nil.

  DOMBuilderGetDocument*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom]): Handle {.nimcall.}
      ## Get the root document node's handle.
      ## This must not return nil, not even in the fragment parsing case.

  DOMBuilderGetAtomFactory*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom]): AtomFactory[Atom] {.nimcall.}
      ## Get the root document node's handle.
      ## This must not return nil, not even in the fragment parsing case.

  DOMBuilderFinish*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom]) {.nimcall.}
      ## Parsing has finished.

  DOMBuilderParseError*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], message: ParseError) {.nimcall.}
      ## Parse error. `message` is an error code either specified by the
      ## standard (in this case, message < LAST_SPECIFIED_ERROR) or named
      ## arbitrarily. (At the time of writing, only tokenizer errors have
      ## specified error codes.)

  DOMBuilderSetQuirksMode*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], quirksMode: QuirksMode) {.nimcall.}
      ## Set quirks mode to either QUIRKS or LIMITED_QUIRKS. NO_QUIRKS
      ## is the default and is therefore never used here.

  DOMBuilderSetEncoding*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], encoding: string): SetEncodingResult
        {.nimcall.}
      ## Called whenever a <meta charset=... or a <meta http-equiv=... tag
      ## containing a non-empty character set is encountered. A
      ## SetEncodingResult is expected, which is either SET_ENCODING_STOP,
      ## stopping the parser, or SET_ENCODING_CONTINUE, allowing the parser to
      ## continue.
      ##
      ## Note that Chame no longer contains any encoding-related logic; this is
      ## left to the caller.

  DOMBuilderElementPopped*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], element: Handle) {.nimcall.}
      ## Called when an element is popped from the stack of open elements
      ## (i.e. when it has been closed.)

  DOMBuilderGetTemplateContent*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], handle: Handle): Handle {.nimcall.}
      ## Retrieve a handle to the template element's contents.
      ## Note: this function must never return nil.

  DOMBuilderGetParentNode*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], handle: Handle): Option[Handle]
        {.nimcall.}
      ## Retrieve a handle to the parent node.
      ## May return none(Handle) if no parent node exists.

  DOMBuilderGetTagType*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], handle: Handle): TagType {.nimcall.}
      ## Retrieve the tag type of element.

  DOMBuilderGetLocalName*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], handle: Handle): Atom {.nimcall.}
      ## Retrieve the local name of element. (This is tagName(getTagType),
      ## unless the tag is unknown.

  DOMBuilderGetNamespace*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], handle: Handle): Namespace {.nimcall.}
      ## Retrieve the namespace of element.

  DOMBuilderCreateElement*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], localName: Atom, namespace: Namespace,
        attrs: seq[ParsedAttr[Atom]]): Handle {.nimcall.}
      ## Create a new element node.
      ##
      ## localName is the tag name of the token.
      ##
      ## namespace is the namespace passed to the function. (For HTML elements,
      ## it's HTML.)
      ## tagType is set based on localName. (This saves the consumer from
      ## having to interpret localName again.)
      ##
      ## attrs is a table of the token's attributes.

  DOMBuilderCreateComment*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], text: string): Handle {.nimcall.}
      ## Create a new comment node.

  DOMBuilderInsertText*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], parent: Handle, text: string,
        before: Option[Handle]) {.nimcall.}
      ## Insert a text node at the specified location with contents
      ## `text`. If the specified location has a previous sibling that is
      ## a text node, no new text node should be created, but instead `text`
      ## should be appended to the previous sibling's character data.

  DOMBuilderCreateDocumentType*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], name, publicId,
        systemId: string): Handle {.nimcall.}
    ## Create a new document type node.

  DOMBuilderInsertBefore*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], parent, child: Handle,
        before: Option[Handle]) {.nimcall.}
      ## Insert node `child` before the node called `before`.
      ##
      ## If `before` is none(Handle), `child` is expected to be appended to
      ## `parent`'s node list.
      ##
      ## If `child` is a text, and its previous sibling after insertion is a
      ## text as well, then they should be merged. `before` is never a
      ## text node (and thus never has to be merged).
      ##
      ## Note: parent may either be an Element or a Document node.

  DOMBuilderRemove*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], child: Handle) {.nimcall.}
      ## Remove `child` from its parent node, and do nothing if `child`
      ## has no parent node.

  DOMBuilderMoveChildren*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], fromHandle, toHandle: Handle)
        {.nimcall.}
      ## Remove all children from the node `fromHandle`, then append them to
      ## `toHandle`.

  DOMBuilderAddAttrsIfMissing*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], element: Handle,
        attrs: seq[TokenAttr[Atom]]) {.nimcall.}
      ## Add the attributes in `attrs` to the element node `element`.
      ## This is called for HTML and BODY only.
      ##
      ## Pseudocode implementation:
      ## ```nim
      ## for attr in attrs:
      ##   if attr.name notin element.attrs:
      ##     element.attrs.add(attr)
      ## ```

  DOMBuilderSetScriptAlreadyStarted*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], script: Handle) {.nimcall.}
      ## Set the "already started" flag for the script element.
      ##
      ## Note: this flag is not togglable, so this callback should just set it
      ## to true.

  DOMBuilderAssociateWithForm*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], element, form, intendedParent: Handle)
        {.nimcall.}
      ## Called after createElement. Attempts to set form for form-associated
      ## elements.
      ##
      ## Note: the DOM builder is responsible for checking whether the
      ## intended parent and the form element are in the same tree.

type
  MappedAtom = enum
    ATOM_FORM = "form"
    ATOM_CHARSET = "charset"
    ATOM_HTTP_EQUIV = "http-equiv"
    ATOM_CONTENT = "content"
    ATOM_TYPE = "type"
    ATOM_DEFINITION_URL_LOWER = "definitionurl"
    ATOM_DEFINITION_URL_FIXED = "definitionURL"
    ATOM_ANNOTATION_XML = "annotation-xml"
    ATOM_FOREIGNOBJECT = "foreignObject"
    ATOM_DESC = "desc"
    ATOM_TITLE = "title"
    ATOM_ENCODING = "encoding"
    ATOM_MI = "mi"
    ATOM_MO = "mo"
    ATOM_MN = "mn"
    ATOM_MS = "ms"
    ATOM_MTEXT = "mtext"
    ATOM_MGLYPH = "mglyph"
    ATOM_MALIGNMARK = "malignmark"
    ATOM_COLOR = "color"
    ATOM_FACE = "face"
    ATOM_SIZE = "size"

  QualifiedName[Atom] = tuple
    prefix: NamespacePrefix
    namespace: Namespace
    localName: Atom

  HTML5Parser[Handle, Atom] = object
    quirksMode: QuirksMode
    dombuilder: DOMBuilder[Handle, Atom]
    factory: AtomFactory[Atom]
    opts: HTML5ParserOpts[Handle, Atom]
    stopped: bool
    openElements: seq[OpenElement[Handle, Atom]]
    insertionMode: InsertionMode
    oldInsertionMode: InsertionMode
    templateModes: seq[InsertionMode]
    head: Option[OpenElement[Handle, Atom]]
    tokenizer: Tokenizer[Atom]
    form: Option[Handle]
    fosterParenting: bool
    # Handle is an element. nil => marker
    activeFormatting: seq[(Option[Handle], Token[Atom])]
    framesetok: bool
    ignoreLF: bool
    pendingTableChars: string
    pendingTableCharsWhitespace: bool
    caseTable: Table[Atom, Atom]
    adjustedTable: Table[Atom, Atom]
    foreignTable: Table[Atom, QualifiedName[Atom]]
    atomMap: array[MappedAtom, Atom]

  AdjustedInsertionLocation[Handle] = tuple[
    inside: Handle,
    before: Option[Handle]
  ]

# 13.2.4.1
  InsertionMode = enum
    INITIAL, BEFORE_HTML, BEFORE_HEAD, IN_HEAD, IN_HEAD_NOSCRIPT, AFTER_HEAD,
    IN_BODY, TEXT, IN_TABLE, IN_TABLE_TEXT, IN_CAPTION, IN_COLUMN_GROUP,
    IN_TABLE_BODY, IN_ROW, IN_CELL, IN_SELECT, IN_SELECT_IN_TABLE, IN_TEMPLATE,
    AFTER_BODY, IN_FRAMESET, AFTER_FRAMESET, AFTER_AFTER_BODY,
    AFTER_AFTER_FRAMESET

# AtomFactory interface functions
proc strToAtom[Handle, Atom](parser: HTML5Parser[Handle, Atom], s: string):
    Atom =
  return parser.factory.strToAtomImpl(parser.factory, s)

proc tagTypeToAtom[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    tagType: TagType): Atom =
  return parser.factory.tagTypeToAtomImpl(parser.factory, tagType)

# DOMBuilder interface functions
proc finish[Handle, Atom](parser: HTML5Parser[Handle, Atom]) =
  if parser.dombuilder.finish != nil:
    parser.dombuilder.finish(parser.dombuilder)

proc parseError(parser: HTML5Parser, e: ParseError) =
  if parser.dombuilder.parseError != nil:
    parser.dombuilder.parseError(parser.dombuilder, e)

proc setQuirksMode[Handle, Atom](parser: var HTML5Parser[Handle, Atom], mode: QuirksMode) =
  parser.quirksMode = mode
  if parser.dombuilder.setQuirksMode != nil:
    parser.dombuilder.setQuirksMode(parser.dombuilder, mode)

proc setEncoding(parser: var HTML5Parser, cs: string): SetEncodingResult =
  let dombuilder = parser.dombuilder
  if dombuilder.setEncoding != nil:
    return dombuilder.setEncoding(dombuilder, cs)
  return SET_ENCODING_CONTINUE

func getDocument[Handle, Atom](parser: HTML5Parser[Handle, Atom]): Handle =
  let dombuilder = parser.dombuilder
  return dombuilder.getDocument(dombuilder)

func getTemplateContent[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    handle: Handle): Handle =
  let dombuilder = parser.dombuilder
  return dombuilder.getTemplateContent(dombuilder, handle)

func getParentNode[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    handle: Handle): Option[Handle] =
  let dombuilder = parser.dombuilder
  return dombuilder.getParentNode(dombuilder, handle)

func getLocalName[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    handle: Handle): Atom =
  return parser.dombuilder.getLocalName(parser.dombuilder, handle)

func getNamespace[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    handle: Handle): Namespace =
  if parser.dombuilder.getNamespace != nil:
    return parser.dombuilder.getNamespace(parser.dombuilder, handle)
  return Namespace.HTML

func getTagType[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    handle: Handle): TagType =
  if parser.getNamespace(handle) != Namespace.HTML:
    return TAG_UNKNOWN
  return parser.getLocalName(handle).toTagType()

func createElement[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    localName: Atom, namespace: Namespace, attrs: seq[ParsedAttr[Atom]]):
    Handle =
  return parser.dombuilder.createElement(parser.dombuilder, localName,
    namespace, attrs)

func createElement[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    tagType: TagType, namespace: Namespace): Handle =
  let atom = parser.tagTypeToAtom(tagType)
  return parser.createElement(atom, namespace, @[])

func createComment[Handle, Atom](parser: HTML5Parser[Handle, Atom], text: string): Handle =
  let dombuilder = parser.dombuilder
  return dombuilder.createComment(dombuilder, text)

proc createDocumentType[Handle, Atom](parser: HTML5Parser[Handle, Atom], name, publicId,
    systemId: string): Handle =
  let dombuilder = parser.dombuilder
  return dombuilder.createDocumentType(dombuilder, name, publicId, systemId)

proc insertBefore[Handle, Atom](parser: HTML5Parser[Handle, Atom], parent, node: Handle,
    before: Option[Handle]) =
  let dombuilder = parser.dombuilder
  dombuilder.insertBefore(dombuilder, parent, node, before)

proc insertText[Handle, Atom](parser: HTML5Parser[Handle, Atom], parent: Handle,
    text: string, before: Option[Handle]) =
  let dombuilder = parser.dombuilder
  dombuilder.insertText(dombuilder, parent, text, before)

proc remove[Handle, Atom](parser: HTML5Parser[Handle, Atom], child: Handle) =
  let dombuilder = parser.dombuilder
  dombuilder.remove(dombuilder, child)

proc moveChildren[Handle, Atom](parser: HTML5Parser[Handle, Atom], handleFrom,
    handleTo: Handle) =
  let dombuilder = parser.dombuilder
  dombuilder.moveChildren(dombuilder, handleFrom, handleTo)

proc addAttrsIfMissing[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    element: Handle, attrs: seq[TokenAttr[Atom]]) =
  let dombuilder = parser.dombuilder
  if dombuilder.addAttrsIfMissing != nil:
    dombuilder.addAttrsIfMissing(dombuilder, element, attrs)

proc setScriptAlreadyStarted[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    script: Handle) =
  let dombuilder = parser.dombuilder
  if dombuilder.setScriptAlreadyStarted != nil:
    dombuilder.setScriptAlreadyStarted(dombuilder, script)

proc associateWithForm[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    element, form, intendedParent: Handle) =
  let dombuilder = parser.dombuilder
  if dombuilder.associateWithForm != nil:
    dombuilder.associateWithForm(dombuilder, element, form, intendedParent)

# Parser
func hasParseError(parser: HTML5Parser): bool =
  return parser.dombuilder.parseError != nil

func fragment(parser: HTML5Parser): bool =
  return parser.opts.ctx.isSome

# https://html.spec.whatwg.org/multipage/parsing.html#reset-the-insertion-mode-appropriately
proc resetInsertionMode(parser: var HTML5Parser) =
  template switch_insertion_mode_and_return(mode: InsertionMode) =
    parser.insertionMode = mode
    return
  for i in countdown(parser.openElements.high, 0):
    var node = parser.openElements[i]
    let last = i == 0
    if parser.fragment:
      node = parser.opts.ctx.get
    let tagType = parser.getTagType(node.element)
    case tagType
    of TAG_SELECT:
      if not last:
        for j in countdown(parser.openElements.high, 1):
          let ancestor = parser.openElements[j].element
          case parser.getTagType(ancestor)
          of TAG_TEMPLATE: break
          of TAG_TABLE: switch_insertion_mode_and_return IN_SELECT_IN_TABLE
          else: discard
      switch_insertion_mode_and_return IN_SELECT
    of TAG_TD, TAG_TH:
      if not last:
        switch_insertion_mode_and_return IN_CELL
    of TAG_TR: switch_insertion_mode_and_return IN_ROW
    of TAG_TBODY, TAG_THEAD, TAG_TFOOT:
      switch_insertion_mode_and_return IN_TABLE_BODY
    of TAG_CAPTION:
      switch_insertion_mode_and_return IN_CAPTION
    of TAG_COLGROUP: switch_insertion_mode_and_return IN_COLUMN_GROUP
    of TAG_TABLE: switch_insertion_mode_and_return IN_TABLE
    of TAG_TEMPLATE: switch_insertion_mode_and_return parser.templateModes[^1]
    of TAG_HEAD:
      if not last:
        switch_insertion_mode_and_return IN_HEAD
    of TAG_BODY: switch_insertion_mode_and_return IN_BODY
    of TAG_FRAMESET: switch_insertion_mode_and_return IN_FRAMESET
    of TAG_HTML:
      if parser.head.isNone:
        switch_insertion_mode_and_return BEFORE_HEAD
      else:
        switch_insertion_mode_and_return AFTER_HEAD
    else: discard
    if last:
      switch_insertion_mode_and_return IN_BODY

func currentNodeToken[Handle, Atom](parser: HTML5Parser[Handle, Atom]):
    OpenElement[Handle, Atom] =
  return parser.openElements[^1]

func currentNode[Handle, Atom](parser: HTML5Parser[Handle, Atom]): Handle =
  return parser.currentNodeToken.element

func currentToken[Handle, Atom](parser: HTML5Parser[Handle, Atom]):
    Token[Atom] =
  return parser.currentNodeToken.token

func adjustedCurrentNodeToken[Handle, Atom](parser: HTML5Parser[Handle, Atom]):
    OpenElement[Handle, Atom] =
  if parser.fragment and parser.openElements.len == 1:
    return parser.opts.ctx.get
  else:
    return parser.currentNodeToken

func adjustedCurrentNode[Handle, Atom](parser: HTML5Parser[Handle, Atom]):
    Handle =
  return parser.adjustedCurrentNodeToken.element

func lastElementOfTag[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    tagType: TagType): tuple[element: Option[Handle], pos: int] =
  for i in countdown(parser.openElements.high, 0):
    let element = parser.openElements[i].element
    if parser.getTagType(element) == tagType:
      return (some(element), i)
  return (none(Handle), -1)

func last_child_of[Handle](n: Handle): AdjustedInsertionLocation[Handle] =
  (n, none(Handle))

func last_child_of[Handle, Atom](n: OpenElement[Handle, Atom]):
    AdjustedInsertionLocation[Handle] =
  last_child_of(n.element)

# https://html.spec.whatwg.org/multipage/#appropriate-place-for-inserting-a-node
func appropriatePlaceForInsert[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: Handle): AdjustedInsertionLocation[Handle] =
  assert parser.getTagType(parser.openElements[0].element) == TAG_HTML
  let targetTagType = parser.getTagType(target)
  const FosterTagTypes = {TAG_TABLE, TAG_TBODY, TAG_TFOOT, TAG_THEAD, TAG_TR}
  if parser.fosterParenting and targetTagType in FosterTagTypes:
    let lastTemplate = parser.lastElementOfTag(TAG_TEMPLATE)
    let lastTable = parser.lastElementOfTag(TAG_TABLE)
    if lastTemplate.element.isSome and
        parser.dombuilder.getTemplateContent != nil and
        (lastTable.element.isNone or lastTable.pos < lastTemplate.pos):
      let content = parser.getTemplateContent(lastTemplate.element.get)
      return last_child_of(content)
    if lastTable.element.isNone:
      return last_child_of(parser.openElements[0].element)
    let parentNode = parser.getParentNode(lastTable.element.get)
    if parentNode.isSome:
      return (parentNode.get, lastTable.element)
    let previousElement = parser.openElements[lastTable.pos - 1]
    result = last_child_of(previousElement.element)
  else:
    result = last_child_of(target)
  if parser.getTagType(result.inside) == TAG_TEMPLATE and
      parser.dombuilder.getTemplateContent != nil:
    result = (parser.getTemplateContent(result.inside), none(Handle))

func appropriatePlaceForInsert[Handle, Atom](parser: HTML5Parser[Handle, Atom]):
    AdjustedInsertionLocation[Handle] =
  parser.appropriatePlaceForInsert(parser.currentNode)

func hasElement[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    tags: set[TagType]): bool =
  for (element, _) in parser.openElements:
    if parser.getTagType(element) in tags:
      return true
  return false

func hasElement[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    tag: TagType): bool =
  return parser.hasElement({tag})

const Scope = {
  TAG_APPLET, TAG_CAPTION, TAG_HTML, TAG_TABLE, TAG_TD, TAG_TH, TAG_MARQUEE,
  TAG_OBJECT, TAG_TEMPLATE # (+ SVG, MathML)
}

func hasElementInScopeWithXML[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: Handle, list: set[TagType]): bool =
  for i in countdown(parser.openElements.high, 0):
    let element = parser.openElements[i].element
    if element == target:
      return true
    let localName = parser.getLocalName(element)
    case parser.getNamespace(element)
    of Namespace.HTML:
      {.linearScanEnd.}
      if localName.toTagType() in list:
        return false
    of Namespace.MATHML:
      let elements = [
        parser.atomMap[ATOM_MI], parser.atomMap[ATOM_MO],
        parser.atomMap[ATOM_MN], parser.atomMap[ATOM_MS],
        parser.atomMap[ATOM_MTEXT], parser.atomMap[ATOM_ANNOTATION_XML]
      ]
      if localName in elements:
        return false
    of Namespace.SVG:
      let elements = [
        parser.atomMap[ATOM_FOREIGNOBJECT], parser.atomMap[ATOM_DESC],
        parser.atomMap[ATOM_TITLE]
      ]
      if localName in elements:
        return false
    else: discard

func hasElementInScopeWithXML[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: set[TagType], list: set[TagType]): bool =
  for i in countdown(parser.openElements.high, 0):
    let element = parser.openElements[i].element
    let localName = parser.getLocalName(element)
    case parser.getNamespace(element)
    of Namespace.HTML:
      {.linearScanEnd.}
      let tagType = localName.toTagType()
      if tagType in target:
        return true
      if tagType in list:
        return false
    of Namespace.MATHML:
      let elements = [
        parser.atomMap[ATOM_MI], parser.atomMap[ATOM_MO],
        parser.atomMap[ATOM_MN], parser.atomMap[ATOM_MS],
        parser.atomMap[ATOM_MTEXT], parser.atomMap[ATOM_ANNOTATION_XML]
      ]
      if localName in elements:
        return false
    of Namespace.SVG:
      let elements = [
        parser.atomMap[ATOM_FOREIGNOBJECT], parser.atomMap[ATOM_DESC],
        parser.atomMap[ATOM_TITLE]
      ]
      if localName in elements:
        return false
    else: discard

func hasElementInScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: Handle): bool =
  return parser.hasElementInScopeWithXML(target, Scope)

func hasElementInScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: set[TagType]): bool =
  return parser.hasElementInScopeWithXML(target, Scope)

func hasElementInScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: TagType): bool =
  return parser.hasElementInScopeWithXML({target}, Scope)

func hasElementInListItemScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: TagType): bool =
  const ListItemScope = Scope + {TAG_OL, TAG_UL}
  return parser.hasElementInScopeWithXML({target}, ListItemScope)

func hasElementInButtonScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: TagType): bool =
  const ButtonScope = Scope + {TAG_BUTTON}
  return parser.hasElementInScopeWithXML({target}, ButtonScope)

# Note: these do not include the "Scope" tags.
func hasElementInSpecificScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: Handle, list: set[TagType]): bool =
  for i in countdown(parser.openElements.high, 0):
    let element = parser.openElements[i].element
    if element == target:
      return true
    if parser.getTagType(element) in list:
      return false
  assert false

func hasElementInSpecificScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: set[TagType], list: set[TagType]): bool =
  for i in countdown(parser.openElements.high, 0):
    let tagType = parser.getTagType(parser.openElements[i].element)
    if tagType in target:
      return true
    if tagType in list:
      return false
  assert false

func hasElementInSpecificScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: TagType, list: set[TagType]): bool =
  return parser.hasElementInSpecificScope({target}, list)

const TableScope = {TAG_HTML, TAG_TABLE, TAG_TEMPLATE}
func hasElementInTableScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: TagType): bool =
  return parser.hasElementInSpecificScope(target, TableScope)

func hasElementInTableScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: set[TagType]): bool =
  return parser.hasElementInSpecificScope(target, TableScope)

func hasElementInSelectScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: TagType): bool =
  for i in countdown(parser.openElements.high, 0):
    let tagType = parser.getTagType(parser.openElements[i].element)
    if tagType == target:
      return true
    if tagType notin {TAG_OPTION, TAG_OPTGROUP}:
      return false
  assert false

func findAttr[Atom](attrs: seq[TokenAttr[Atom]], atom: Atom): int =
  for i, attr in attrs:
    if attr.name == atom:
      return i
  return -1

func findAttr[Atom](token: Token[Atom], atom: Atom): int =
  return token.attrs.findAttr(atom)

func findAttr[Atom](attrs: seq[ParsedAttr[Atom]], atom: Atom): int =
  for i, attr in attrs:
    if attr.name == atom:
      return i
  return -1

func createElement[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    localName: Atom, namespace: Namespace, intendedParent: Handle,
    attrs: seq[ParsedAttr[Atom]]): Handle =
  #TODO custom elements
  let element = parser.createElement(localName, namespace, attrs)
  let tagType = localName.toTagType()
  if namespace == Namespace.HTML and tagType in FormAssociatedElements and
      parser.form.isSome and not parser.hasElement(TAG_TEMPLATE) and
      (tagType notin ListedElements or
        attrs.findAttr(parser.atomMap[ATOM_FORM]) == -1):
    parser.associateWithForm(element, parser.form.get, intendedParent)
  return element

func toParsedAttrs[Atom](attrs: seq[TokenAttr[Atom]]): seq[ParsedAttr[Atom]] =
  result = @[]
  for attr in attrs:
    #TODO is no namespace correct?
    result.add((NO_PREFIX, NO_NAMESPACE, attr.name, attr.value))

func createElement[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    token: Token, namespace: Namespace, intendedParent: Handle): Handle =
  # attrs not adjusted
  let attrs = token.attrs.toParsedAttrs()
  return parser.createElement(token.tagname, namespace, intendedParent, attrs)

proc pushElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    node: Handle, token: Token[Atom]) =
  parser.openElements.add((node, token))
  let node = parser.adjustedCurrentNode()
  parser.tokenizer.hasnonhtml = parser.getNamespace(node) != Namespace.HTML

proc popElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom]): Handle =
  result = parser.openElements.pop().element
  if parser.dombuilder.elementPopped != nil:
    parser.dombuilder.elementPopped(parser.dombuilder, result)
  if parser.openElements.len == 0:
    parser.tokenizer.hasnonhtml = false
  else:
    let node = parser.adjustedCurrentNode()
    parser.tokenizer.hasnonhtml = parser.getNamespace(node) != Namespace.HTML

template pop_current_node = discard parser.popElement()

proc insert[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    location: AdjustedInsertionLocation[Handle], node: Handle) =
  parser.insertBefore(location.inside, node, location.before)

proc append[Handle, Atom](parser: HTML5Parser[Handle, Atom], parent, node: Handle) =
  parser.insertBefore(parent, node, none(Handle))

proc insertForeignElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    token: Token, localName: Atom, namespace: Namespace, stackOnly: bool,
    attrs: seq[ParsedAttr[Atom]]): Handle =
  let location = parser.appropriatePlaceForInsert()
  let parent = location.inside
  let element = parser.createElement(localName, namespace, parent, attrs)
  #TODO custom elements
  if not stackOnly:
    parser.insert(location, element)
  parser.pushElement(element, token)
  return element

proc insertForeignElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    token: Token, namespace: Namespace, stackOnly: bool): Handle =
  let attrs = token.attrs.toParsedAttrs()
  let localName = token.tagname
  parser.insertForeignElement(token, localName, namespace, stackOnly, attrs)

proc insertHTMLElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    token: Token): Handle =
  return parser.insertForeignElement(token, Namespace.HTML, false)

proc adjustMathMLAttributes[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    attrs: var seq[ParsedAttr[Atom]]) =
  let i = attrs.findAttr(parser.atomMap[ATOM_DEFINITION_URL_LOWER])
  if i != -1:
    attrs[i].name = parser.atomMap[ATOM_DEFINITION_URL_FIXED]

proc adjustForeignAttributes[H, Atom](parser: var HTML5Parser[H, Atom],
    attrs: var seq[ParsedAttr[Atom]]) =
  for attr in attrs.mitems:
    parser.foreignTable.withValue(attr.name, p):
      attr.prefix = p[].prefix
      attr.namespace = p[].namespace
      attr.name = p[].localName

proc adjustSVGAttributes[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    attrs: var seq[ParsedAttr[Atom]]) =
  for attr in attrs.mitems:
    parser.adjustedTable.withValue(attr.name, p):
      attr.name = p[]

proc sortAttributes[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    attrs: var seq[ParsedAttr[Atom]]) =
  attrs.sort(func(a, b: ParsedAttr[Atom]): int = cmp(a.name, b.name))

proc insertCharacter(parser: var HTML5Parser, data: string) =
  let location = parser.appropriatePlaceForInsert()
  if location.inside == parser.getDocument():
    return
  insertText(parser, location.inside, $data, location.before)

proc insertComment[Handle, Atom](parser: var HTML5Parser[Handle, Atom], token: Token,
    position: AdjustedInsertionLocation[Handle]) =
  let comment = parser.createComment(token.data)
  parser.insert(position, comment)

proc insertComment(parser: var HTML5Parser, token: Token) =
  let position = parser.appropriatePlaceForInsert()
  parser.insertComment(token, position)

const PublicIdentifierEquals = [
  "-//W3O//DTD W3 HTML Strict 3.0//EN//",
  "-/W3C/DTD HTML 4.0 Transitional/EN",
  "HTML"
]

const PublicIdentifierStartsWith = [
  "+//Silmaril//dtd html Pro v0r11 19970101//",
  "-//AS//DTD HTML 3.0 asWedit + extensions//",
  "-//AdvaSoft Ltd//DTD HTML 3.0 asWedit + extensions//",
  "-//IETF//DTD HTML 2.0 Level 1//",
  "-//IETF//DTD HTML 2.0 Level 2//",
  "-//IETF//DTD HTML 2.0 Strict Level 1//",
  "-//IETF//DTD HTML 2.0 Strict Level 2//",
  "-//IETF//DTD HTML 2.0 Strict//",
  "-//IETF//DTD HTML 2.0//",
  "-//IETF//DTD HTML 2.1E//",
  "-//IETF//DTD HTML 3.0//",
  "-//IETF//DTD HTML 3.2 Final//",
  "-//IETF//DTD HTML 3.2//",
  "-//IETF//DTD HTML 3//",
  "-//IETF//DTD HTML Level 0//",
  "-//IETF//DTD HTML Level 1//",
  "-//IETF//DTD HTML Level 2//",
  "-//IETF//DTD HTML Level 3//",
  "-//IETF//DTD HTML Strict Level 0//",
  "-//IETF//DTD HTML Strict Level 1//",
  "-//IETF//DTD HTML Strict Level 2//",
  "-//IETF//DTD HTML Strict Level 3//",
  "-//IETF//DTD HTML Strict//",
  "-//IETF//DTD HTML//",
  "-//Metrius//DTD Metrius Presentational//",
  "-//Microsoft//DTD Internet Explorer 2.0 HTML Strict//",
  "-//Microsoft//DTD Internet Explorer 2.0 HTML//",
  "-//Microsoft//DTD Internet Explorer 2.0 Tables//",
  "-//Microsoft//DTD Internet Explorer 3.0 HTML Strict//",
  "-//Microsoft//DTD Internet Explorer 3.0 HTML//",
  "-//Microsoft//DTD Internet Explorer 3.0 Tables//",
  "-//Netscape Comm. Corp.//DTD HTML//",
  "-//Netscape Comm. Corp.//DTD Strict HTML//",
  "-//O'Reilly and Associates//DTD HTML 2.0//",
  "-//O'Reilly and Associates//DTD HTML Extended 1.0//",
  "-//O'Reilly and Associates//DTD HTML Extended Relaxed 1.0//",
  "-//SQ//DTD HTML 2.0 HoTMetaL + extensions//",
  "-//SoftQuad Software//DTD HoTMetaL PRO 6.0::19990601::extensions to HTML 4.0//",
  "-//SoftQuad//DTD HoTMetaL PRO 4.0::19971010::extensions to HTML 4.0//",
  "-//Spyglass//DTD HTML 2.0 Extended//",
  "-//Sun Microsystems Corp.//DTD HotJava HTML//",
  "-//Sun Microsystems Corp.//DTD HotJava Strict HTML//",
  "-//W3C//DTD HTML 3 1995-03-24//",
  "-//W3C//DTD HTML 3.2 Draft//",
  "-//W3C//DTD HTML 3.2 Final//",
  "-//W3C//DTD HTML 3.2//",
  "-//W3C//DTD HTML 3.2S Draft//",
  "-//W3C//DTD HTML 4.0 Frameset//",
  "-//W3C//DTD HTML 4.0 Transitional//",
  "-//W3C//DTD HTML Experimental 19960712//",
  "-//W3C//DTD HTML Experimental 970421//",
  "-//W3C//DTD W3 HTML//",
  "-//W3O//DTD W3 HTML 3.0//",
  "-//WebTechs//DTD Mozilla HTML 2.0//",
  "-//WebTechs//DTD Mozilla HTML//",
]

const SystemIdentifierMissingAndPublicIdentifierStartsWith = [
  "-//W3C//DTD HTML 4.01 Frameset//",
  "-//W3C//DTD HTML 4.01 Transitional//"
]

const PublicIdentifierStartsWithLimited = [
  "-//W3C//DTD XHTML 1.0 Frameset//",
  "-//W3C//DTD XHTML 1.0 Transitional//"
]

const SystemIdentifierNotMissingAndPublicIdentifierStartsWith = [
  "-//W3C//DTD HTML 4.01 Frameset//",
  "-//W3C//DTD HTML 4.01 Transitional//"
]

func quirksConditions(token: Token): bool =
  if token.quirks:
    return true
  if token.name.get("") != "html":
    return true
  if token.sysid.get("") == "http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd":
    return true
  if token.pubid.isSome:
    let pubid = token.pubid.get
    for id in PublicIdentifierEquals:
      if pubid.equalsIgnoreCase(id):
        return true
    for id in PublicIdentifierStartsWith:
      if pubid.startsWithNoCase(id):
        return true
    if token.sysid.isNone:
      for id in SystemIdentifierMissingAndPublicIdentifierStartsWith:
        if pubid.startsWithNoCase(id):
          return true
  return false

func limitedQuirksConditions(token: Token): bool =
  if token.pubid.isNone: return false
  for id in PublicIdentifierStartsWithLimited:
    if token.pubid.get.startsWithNoCase(id):
      return true
  if token.sysid.isNone: return false
  for id in SystemIdentifierNotMissingAndPublicIdentifierStartsWith:
    if token.pubid.get.startsWithNoCase(id):
      return true
  return false

# 13.2.6.2
proc genericRawtextElementParsingAlgorithm(parser: var HTML5Parser, token: Token) =
  discard parser.insertHTMLElement(token)
  parser.tokenizer.state = RAWTEXT
  parser.oldInsertionMode = parser.insertionMode
  parser.insertionMode = TEXT

proc genericRCDATAElementParsingAlgorithm(parser: var HTML5Parser, token: Token) =
  discard parser.insertHTMLElement(token)
  parser.tokenizer.state = RCDATA
  parser.oldInsertionMode = parser.insertionMode
  parser.insertionMode = TEXT

# Pop all elements, including the specified tag.
proc popElementsIncl(parser: var HTML5Parser, tags: set[TagType]) =
  while parser.getTagType(parser.popElement()) notin tags:
    discard

proc popElementsIncl(parser: var HTML5Parser, tag: TagType) =
  parser.popElementsIncl({tag})

# Pop all elements, including the specified element.
proc popElementsIncl[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    handle: Handle) =
  while parser.popElement() != handle:
    discard

# https://html.spec.whatwg.org/multipage/parsing.html#closing-elements-that-have-implied-end-tags
proc generateImpliedEndTags(parser: var HTML5Parser) =
  const tags = {
    TAG_DD, TAG_DT, TAG_LI, TAG_OPTGROUP, TAG_OPTION, TAG_P, TAG_RB, TAG_RP,
    TAG_RT, TAG_RTC
  }
  while parser.getTagType(parser.currentNode) in tags:
    discard parser.popElement()

proc generateImpliedEndTags(parser: var HTML5Parser, exclude: TagType) =
  let tags = {
    TAG_DD, TAG_DT, TAG_LI, TAG_OPTGROUP, TAG_OPTION, TAG_P, TAG_RB, TAG_RP,
    TAG_RT, TAG_RTC
  } - {exclude}
  while parser.getTagType(parser.currentNode) in tags:
    discard parser.popElement()

proc generateImpliedEndTagsThoroughly(parser: var HTML5Parser) =
  const tags = {
    TAG_CAPTION, TAG_COLGROUP, TAG_DD, TAG_DT, TAG_LI, TAG_OPTGROUP,
    TAG_OPTION, TAG_P, TAG_RB, TAG_RP, TAG_RT, TAG_RTC, TAG_TBODY, TAG_TD,
    TAG_TFOOT, TAG_TH, TAG_THEAD, TAG_TR
  }
  while parser.getTagType(parser.currentNode) in tags:
    discard parser.popElement()

# https://html.spec.whatwg.org/multipage/parsing.html#push-onto-the-list-of-active-formatting-elements
proc pushOntoActiveFormatting[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    element: Handle, token: Token) =
  var count = 0
  for i in countdown(parser.activeFormatting.high, 0):
    let it = parser.activeFormatting[i]
    if it[0].isNone: # marker
      break
    if it[1].tagname != token.tagname:
      continue
    if parser.getNamespace(it[0].get) != parser.getNamespace(element):
      continue
    if it[1].attrs != token.attrs:
      continue
    inc count
    if count == 3:
      parser.activeFormatting.delete(i)
      break
  parser.activeFormatting.add((some(element), token))

#[
proc tostr(ftype: enum): string =
  return ($ftype).split('_')[1..^1].join("-").toLowerAscii()

func handle2str[Handle, Atom](parser: HTML5Parser[Handle, Atom], node: Handle): string =
  case node.nodeType
  of ELEMENT_NODE:
    let tt = parser.getTagType(node)
    result = "<" & tt.tostr() & ">\n"
    for node in node.childList:
      let x = parser.handle2str(node)
      for l in x.split('\n'):
        result &= "  " & l & "\n"
    result &= "</" & tt.tostr() & ">"
  of TEXT_NODE:
    result = "X"
  else:
    result = "Node of " & $node.nodeType

proc dumpDocument[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  let document = parser.getDocument()
  var s = ""
  for x in document.childList:
    s &= parser.handle2str(x) & '\n'
  echo s
]#

proc findOpenElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    element: Handle): int =
  for i, it in parser.openElements:
    if it.element == element:
      return i
  return -1

proc reconstructActiveFormatting[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  type State = enum
    REWIND, ADVANCE, CREATE
  if parser.activeFormatting.len == 0 or
      parser.activeFormatting[^1][0].isNone or
      parser.findOpenElement(parser.activeFormatting[^1][0].get) != -1:
    return
  var i = parser.activeFormatting.high
  template entry: Option[Handle] = (parser.activeFormatting[i][0])
  var state = REWIND
  while true:
    case state
    of REWIND:
      if i == 0:
        state = CREATE
        continue
      dec i
      if entry.isSome and parser.findOpenElement(entry.get) == -1:
        continue
      state = ADVANCE
    of ADVANCE:
      inc i
      state = CREATE
    of CREATE:
      let element = parser.insertHTMLElement(parser.activeFormatting[i][1])
      parser.activeFormatting[i] = (
        some(element), parser.activeFormatting[i][1]
      )
      if i != parser.activeFormatting.high:
        state = ADVANCE
        continue
      break

proc clearActiveFormattingTillMarker(parser: var HTML5Parser) =
  while parser.activeFormatting.len > 0 and
      parser.activeFormatting.pop()[0].isSome:
    discard

func isMathMLIntegrationPoint[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    element: Handle): bool =
  if parser.getNamespace(element) != Namespace.MATHML:
    return false
  let elements = [
    parser.atomMap[ATOM_MI],
    parser.atomMap[ATOM_MO],
    parser.atomMap[ATOM_MN],
    parser.atomMap[ATOM_MS],
    parser.atomMap[ATOM_MTEXT]
  ]
  return parser.getLocalName(element) in elements

func isHTMLIntegrationPoint[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    oe: OpenElement[Handle, Atom]): bool =
  let (element, token) = oe
  let localName = parser.getLocalName(element)
  let namespace = parser.getNamespace(element)
  if namespace == Namespace.MATHML:
    if localName == parser.atomMap[ATOM_ANNOTATION_XML]:
      let i = token.findAttr(parser.atomMap[ATOM_ENCODING])
      if i != -1:
        let value = token.attrs[i].value
        return value.equalsIgnoreCase("text/html") or
          value.equalsIgnoreCase("application/xhtml+xml")
  elif namespace == Namespace.SVG:
    let elements = [
      parser.atomMap[ATOM_FOREIGNOBJECT],
      parser.atomMap[ATOM_DESC],
      parser.atomMap[ATOM_TITLE]
    ]
    return localName in elements
  return false

func extractEncFromMeta(s: string): string =
  var i = 0
  while true: # Loop:
    var j = 0
    while i < s.len:
      template check(c: static char) =
        if s[i].toLowerAscii() == c:
          inc j
        else:
          j = 0
      case j
      of 0: check 'c'
      of 1: check 'h'
      of 2: check 'a'
      of 3: check 'r'
      of 4: check 's'
      of 5: check 'e'
      of 6: check 't'
      of 7:
        inc j
        break
      else: discard
      inc i
    if j < 7: return ""
    while i < s.len and s[i] in AsciiWhitespace: inc i
    if i >= s.len or s[i] != '=': continue
    while i < s.len and s[i] in AsciiWhitespace: inc i
    break
  inc i
  if i >= s.len: return ""
  if s[i] in {'"', '\''}:
    let s2 = s.substr(i + 1).until(s[i])
    if s2.len == 0 or s2[^1] != s[i]:
      return ""
    return s2
  return s.substr(i).until({';', ' '})

proc parseErrorByTokenType(parser: var HTML5Parser, tokenType: TokenType) =
  case tokenType
  of START_TAG:
    parser.parseError UNEXPECTED_START_TAG
  of END_TAG:
    parser.parseError UNEXPECTED_END_TAG
  of EOF:
    parser.parseError UNEXPECTED_EOF
  of CHARACTER, CHARACTER_WHITESPACE:
    parser.parseError UNEXPECTED_CHARACTER
  of CHARACTER_NULL:
    parser.parseError UNEXPECTED_NULL
  of DOCTYPE, COMMENT:
    doAssert false

# Find a node in the list of active formatting elements, or return -1.
func findLastActiveFormatting[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    node: Handle): int =
  for i in countdown(parser.activeFormatting.high, 0):
    let it = parser.activeFormatting[i][0]
    if it.isSome and it.get == node:
      return i
  return -1

func findLastActiveFormatting(parser: var HTML5Parser, tagType: TagType): int =
  for i in countdown(parser.activeFormatting.high, 0):
    let it = parser.activeFormatting[i][0]
    if it.isSome and parser.getTagType(it.get) == tagType:
      return i
  return -1

# > the last element in the list of active formatting elements that:
# > is between the end of the list and the last marker in the list, if any,
# > or the start of the list otherwise, and has the tag name subject.
func findLastActiveFormattingAfterMarker(parser: var HTML5Parser,
    token: Token): int =
  for i in countdown(parser.activeFormatting.high, 0):
    let it = parser.activeFormatting[i][1]
    if it == nil:
      break # marker
    if it.tagname == token.tagname:
      return i
  return -1

func findLastActiveFormattingAfterMarker(parser: var HTML5Parser,
    tagType: TagType): int =
  for i in countdown(parser.activeFormatting.high, 0):
    let it = parser.activeFormatting[i][0]
    if it.isNone:
      break
    if parser.getTagType(it.get) == tagType:
      return i
  return -1

func isSpecialElement[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    element: Handle): bool =
  let localName = parser.getLocalName(element)
  let namespace = parser.getNamespace(element)
  case namespace
  of Namespace.HTML:
    {.linearScanEnd.}
    return localName.toTagType() in SpecialElements
  of Namespace.MATHML:
    let elements = [
      parser.atomMap[ATOM_MI],
      parser.atomMap[ATOM_MO],
      parser.atomMap[ATOM_MN],
      parser.atomMap[ATOM_MS],
      parser.atomMap[ATOM_MTEXT],
      parser.atomMap[ATOM_ANNOTATION_XML]
    ]
    return localName in elements
  of Namespace.SVG:
    let elements = [
      parser.atomMap[ATOM_FOREIGNOBJECT],
      parser.atomMap[ATOM_DESC],
      parser.atomMap[ATOM_TITLE]
    ]
    return localName in elements
  else:
    return false

# > Let furthestBlock be the topmost node in the stack of open elements that
# > is lower in the stack than formattingElement, and is an element in the
# > special category. There might not be one.
func findFurthestBlockAfter(parser: HTML5Parser, stackIndex: int): int =
  for i in stackIndex ..< parser.openElements.len:
    if parser.isSpecialElement(parser.openElements[i].element):
      return i
  return -1

func findLastActiveFormatting[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    tagTypes: set[TagType]): int =
  for i in countdown(parser.activeFormatting.high, 0):
    let it = parser.activeFormatting[i][0]
    if it.isSome and parser.getTagType(it.get) in tagTypes:
      return i
  return -1

# If true is returned, call "any other end tag".
proc adoptionAgencyAlgorithm[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    token: Token): bool =
  template parse_error(e: ParseError) =
    parser.parseError(e)
  if parser.currentToken.tagname == token.tagname and
      parser.findLastActiveFormatting(parser.currentNode) == -1:
    pop_current_node
    return false
  for i in 0 ..< 8: # outer loop
    var formattingIndex = parser.findLastActiveFormattingAfterMarker(token)
    if formattingIndex == -1:
      # no such element
      return true
    let formatting = parser.activeFormatting[formattingIndex][0].get
    let stackIndex = parser.findOpenElement(formatting)
    if stackIndex < 0:
      parse_error ELEMENT_NOT_IN_OPEN_ELEMENTS
      parser.activeFormatting.delete(formattingIndex)
      return false
    if not parser.hasElementInScope(formatting):
      parse_error ELEMENT_NOT_IN_SCOPE
      return false
    if formatting != parser.currentNode:
      parse_error ELEMENT_NOT_CURRENT_NODE
      # do not return
    var furthestBlockIndex = parser.findFurthestBlockAfter(stackIndex)
    if furthestBlockIndex == -1:
      parser.popElementsIncl(formatting)
      parser.activeFormatting.delete(formattingIndex)
      return false
    let furthestBlock = parser.openElements[furthestBlockIndex].element
    let commonAncestor = parser.openElements[stackIndex - 1].element
    var bookmark = formattingIndex
    var node = furthestBlock
    var aboveNode = parser.openElements[furthestBlockIndex - 1].element
    var lastNode = furthestBlock
    var j = 0
    while true:
      inc j
      node = aboveNode
      if node == formatting:
        break
      let nodeStackIndex = parser.findOpenElement(node)
      var nodeFormattingIndex = parser.findLastActiveFormatting(node)
      if j > 3 and nodeFormattingIndex >= 0:
        parser.activeFormatting.delete(nodeFormattingIndex)
        if nodeFormattingIndex < bookmark:
          dec bookmark # a previous node got deleted, so decrement bookmark
        nodeFormattingIndex = -1 # deleted, so set to -1
      if nodeFormattingIndex < 0:
        aboveNode = parser.openElements[nodeStackIndex - 1].element
        parser.openElements.delete(nodeStackIndex)
        if nodeStackIndex < furthestBlockIndex:
          dec furthestBlockIndex
          let element = parser.openElements[furthestBlockIndex].element
          assert furthestBlock == element
        continue
      let tok = parser.activeFormatting[nodeFormattingIndex][1]
      let element = parser.createElement(tok, Namespace.HTML, commonAncestor)
      parser.activeFormatting[nodeFormattingIndex] = (some(element), tok)
      parser.openElements[nodeStackIndex] = (element, tok)
      aboveNode = parser.openElements[nodeStackIndex - 1].element
      node = element
      if lastNode == furthestBlock:
        bookmark = nodeFormattingIndex + 1
      parser.remove(lastNode)
      parser.append(node, lastNode)
      lastNode = node
    parser.remove(lastNode)
    let location = parser.appropriatePlaceForInsert(commonAncestor)
    parser.insert(location, lastNode)
    let token = parser.activeFormatting[formattingIndex][1]
    let element = parser.createElement(token, Namespace.HTML, furthestBlock)
    parser.moveChildren(furthestBlock, element)
    parser.append(furthestBlock, element)
    parser.activeFormatting.insert((some(element), token), bookmark)
    if formattingIndex >= bookmark:
      inc formattingIndex # increment because of insert
    parser.activeFormatting.delete(formattingIndex)
    parser.openElements.insert((element, token), furthestBlockIndex + 1)
    parser.openElements.delete(stackIndex)
  return false

proc closeP(parser: var HTML5Parser) =
  parser.generateImpliedEndTags(TAG_P)
  if parser.getTagType(parser.currentNode) != TAG_P:
    parser.parseError(MISMATCHED_TAGS)
  parser.popElementsIncl(TAG_P)

proc newStartTagToken[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    t: TagType): Token[Atom] =
  return Token[Atom](t: START_TAG, tagname: parser.tagTypeToAtom(t))

# Following is an implementation of the state (?) machine defined in
# https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-inhtml
# It uses the ad-hoc pattern matching macro `match' to apply the following
# transformations:
# * First, pairs of patterns and actions are stored in tuples (and `discard'
#   statements...)
# * These pairs are then assigned to token types, later mapped to legs of the
#   first case statement.
# * Another case statement is constructed where needed, e.g. for switching on
#   characters/tags/etc.
# * Finally, the whole thing is wrapped in a named block, to implement a
#   pseudo-goto by breaking out only when the else statement needn't be
#   executed.
#
# For example, the following code:
#
#   match token:
#     TokenType.COMMENT => (block: echo "comment")
#     ("<p>", "<a>", "</div>") => (block: echo "p, a or closing div")
#     ("<div>", "</p>") => (block: anything_else)
#     (TokenType.START_TAG, TokenType.END_TAG) => (block: assert false, "invalid")
#     other => (block: echo "anything else")
#
# (effectively) generates this:
#
#   block inside_not_else:
#     case token.t
#     of TokenType.COMMENT:
#       echo "comment"
#       break inside_not_else
#     of TokenType.START_TAG:
#       case token.tagtype
#       of {TAG_P, TAG_A}:
#         echo "p, a or closing div"
#         break inside_not_else
#       of TAG_DIV: discard
#       else:
#         assert false
#         break inside_not_else
#     of TokenType.END_TAG:
#       case token.tagtype
#       of TAG_DIV:
#         echo "p, a or closing div"
#         break inside_not_else
#       of TAG_P: discard
#       else:
#         assert false
#         break inside_not_else
#     else: discard
#     echo "anything else"
#
# This duplicates any code that applies for several token types, except for the
# else branch.
macro match(token: Token, body: typed): untyped =
  type OfBranchStore = object
    ofBranches: seq[(seq[NimNode], NimNode)]
    defaultBranch: NimNode
    painted: bool

  # Stores 'of' branches
  var ofBranches: array[TokenType, OfBranchStore]
  # Stores 'else', 'elif' branches
  var defaultBranch: NimNode

  const tokenTypes = (func(): Table[string, TokenType] =
    for tt in TokenType:
      result[$tt] = tt)()

  for disc in body:
    let tup = disc[0] # access actual tuple
    let pattern = `tup`[0]
    let lambda = `tup`[1]
    var action = lambda.findChild(it.kind notin {nnkSym, nnkEmpty, nnkFormalParams})
    if pattern.kind != nnkDiscardStmt and not (action.len == 2 and action[1].kind == nnkDiscardStmt and action[1][0] == newStrLitNode("anything_else")):
      action = quote do:
        `action`
        #eprint token #debug
        break inside_not_else

    var patterns = @[pattern]
    while patterns.len > 0:
      let pattern = patterns.pop()
      case pattern.kind
      of nnkSym: # simple symbols; we assume these are the enums
        ofBranches[tokenTypes[pattern.strVal]].defaultBranch = action
        ofBranches[tokenTypes[pattern.strVal]].painted = true
      of nnkStrLit:
        let s = pattern.strVal
        assert s[0] == '<'
        var i = if s[1] == '/': 2 else: 1
        var tagName = ""
        while i < s.len:
          if s[i] == '>':
            assert i == s.high
            break
          assert s[i] in AsciiAlphaNumeric
          tagName &= s[i]
          inc i
        let tt = int(tagType(tagName))
        let tokt = if s[1] != '/': START_TAG else: END_TAG
        var found = false
        for i in 0..ofBranches[tokt].ofBranches.high:
          if ofBranches[tokt].ofBranches[i][1] == action:
            found = true
            ofBranches[tokt].ofBranches[i][0].add((quote do: TagType(`tt`)))
            ofBranches[tokt].painted = true
            break
        if not found:
          ofBranches[tokt].ofBranches.add((@[(quote do: TagType(`tt`))], action))
          ofBranches[tokt].painted = true
      of nnkDiscardStmt:
        defaultBranch = action
      of nnkTupleConstr:
        for child in pattern:
          patterns.add(child)
      else:
        error pattern.strVal & ": Unsupported pattern of kind " & $pattern.kind

  func tokenBranchOn(tok: TokenType): NimNode =
    case tok
    of START_TAG, END_TAG:
      return quote do: token.tagtype
    else:
      error "Unsupported branching of token " & $tok

  template add_to_case(branch: typed) =
    if branch[0].len == 1:
      tokenCase.add(newNimNode(nnkOfBranch).add(branch[0][0]).add(branch[1]))
    else:
      var curly = newNimNode(nnkCurly)
      for node in branch[0]:
        curly.add(node)
      tokenCase.add(newNimNode(nnkOfBranch).add(curly).add(branch[1]))

  # Build case statements
  var mainCase = newNimNode(nnkCaseStmt).add(quote do: `token`.t)
  for tt in TokenType:
    let ofBranch = newNimNode(nnkOfBranch).add(quote do: TokenType(`tt`))
    let tokenCase = newNimNode(nnkCaseStmt)
    if ofBranches[tt].defaultBranch != nil:
      if ofBranches[tt].ofBranches.len > 0:
        tokenCase.add(tokenBranchOn(tt))
        for branch in ofBranches[tt].ofBranches:
          add_to_case branch
        tokenCase.add(newNimNode(nnkElse).add(ofBranches[tt].defaultBranch))
        ofBranch.add(tokenCase)
        mainCase.add(ofBranch)
      else:
        ofBranch.add(ofBranches[tt].defaultBranch)
        mainCase.add(ofBranch)
    else:
      if ofBranches[tt].ofBranches.len > 0:
        tokenCase.add(tokenBranchOn(tt))
        for branch in ofBranches[tt].ofBranches:
          add_to_case branch
        ofBranch.add(tokenCase)
        tokenCase.add(newNimNode(nnkElse).add(quote do: discard))
        mainCase.add(ofBranch)
      else:
        discard

  for t in TokenType:
    if not ofBranches[t].painted:
      mainCase.add(newNimNode(nnkElse).add(quote do: discard))
      break

  var stmts = newStmtList().add(mainCase)
  for stmt in defaultBranch:
    stmts.add(stmt)
  result = newBlockStmt(ident("inside_not_else"), stmts)

proc processInHTMLContent[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    token: Token, insertionMode: InsertionMode) =
  template anything_else = discard "anything_else"

  macro `=>`(v: typed, body: untyped): untyped =
    quote do:
      discard (`v`, proc() = `body`)

  template other = discard

  template reprocess(tok: Token) =
    parser.processInHTMLContent(tok, parser.insertionMode)

  template parse_error(e: ParseError) =
    parser.parseError(e)

  template parse_error_if_mismatch(tagtype: TagType) =
    if parser.hasParseError():
      if parser.getTagType(parser.currentNode) != TAG_DD:
        parse_error MISMATCHED_TAGS

  template parse_error_if_mismatch(tagtypes: set[TagType]) =
    if parser.hasParseError():
      if parser.getTagType(parser.currentNode) notin tagtypes:
        parse_error MISMATCHED_TAGS

  case insertionMode
  of INITIAL:
    match token:
      TokenType.CHARACTER_WHITESPACE => (block: discard)
      TokenType.COMMENT => (block:
        parser.insertComment(token, last_child_of(parser.getDocument()))
      )
      TokenType.DOCTYPE => (block:
        if token.name.get("") != "html" or token.pubid.isSome or
            token.sysid.isSome and token.sysid.get != "about:legacy-compat":
          parse_error INVALID_DOCTYPE
        let doctype = parser.createDocumentType(token.name.get(""),
          token.pubid.get(""), token.sysid.get(""))
        parser.append(parser.getDocument(), doctype)
        if not parser.opts.isIframeSrcdoc:
          if quirksConditions(token):
            parser.setQuirksMode(QUIRKS)
          elif limitedQuirksConditions(token):
            parser.setQuirksMode(LIMITED_QUIRKS)
        parser.insertionMode = BEFORE_HTML
      )
      other => (block:
        if not parser.opts.isIframeSrcdoc:
          parse_error UNEXPECTED_INITIAL_TOKEN
        parser.setQuirksMode(QUIRKS)
        parser.insertionMode = BEFORE_HTML
        reprocess token
      )

  of BEFORE_HTML:
    match token:
      TokenType.DOCTYPE => (block: parse_error UNEXPECTED_DOCTYPE)
      TokenType.COMMENT => (block:
        parser.insertComment(token, last_child_of(parser.getDocument()))
      )
      TokenType.CHARACTER_WHITESPACE => (block: discard)
      "<html>" => (block:
        let element = parser.createElement(token, Namespace.HTML,
          parser.getDocument())
        parser.append(parser.getDocument(), element)
        parser.pushElement(element, token)
        parser.insertionMode = BEFORE_HEAD
      )
      ("</head>", "</body>", "</html>", "</br>") => (block: anything_else)
      TokenType.END_TAG => (block: parse_error UNEXPECTED_END_TAG)
      other => (block:
        let element = parser.createElement(TAG_HTML, Namespace.HTML)
        parser.append(parser.getDocument(), element)
        let html = parser.newStartTagToken(TAG_HTML)
        parser.pushElement(element, html)
        parser.insertionMode = BEFORE_HEAD
        reprocess token
      )

  of BEFORE_HEAD:
    match token:
      TokenType.CHARACTER_WHITESPACE => (block: discard)
      TokenType.COMMENT => (block: parser.insertComment(token))
      TokenType.DOCTYPE => (block: parse_error UNEXPECTED_DOCTYPE)
      "<html>" => (block: parser.processInHTMLContent(token, IN_BODY))
      "<head>" => (block:
        parser.head = some((parser.insertHTMLElement(token), token))
        parser.insertionMode = IN_HEAD
      )
      ("</head>", "</body>", "</html>", "</br>") => (block: anything_else)
      TokenType.END_TAG => (block: parse_error UNEXPECTED_END_TAG)
      other => (block:
        let head = parser.newStartTagToken(TAG_HEAD)
        parser.head = some((parser.insertHTMLElement(head), head))
        parser.insertionMode = IN_HEAD
        reprocess token
      )

  of IN_HEAD:
    match token:
      TokenType.CHARACTER_WHITESPACE => (block:
        parser.insertCharacter(token.s)
      )
      TokenType.COMMENT => (block: parser.insertComment(token))
      TokenType.DOCTYPE => (block: parse_error UNEXPECTED_DOCTYPE)
      "<html>" => (block: parser.processInHTMLContent(token, IN_BODY))
      ("<base>", "<basefont>", "<bgsound>", "<link>") => (block:
        discard parser.insertHTMLElement(token)
        pop_current_node
      )
      "<meta>" => (block:
        discard parser.insertHTMLElement(token)
        pop_current_node
        let i = token.findAttr(parser.atomMap[ATOM_CHARSET])
        if i != -1:
          case parser.setEncoding(token.attrs[i].value)
          of SET_ENCODING_CONTINUE:
            discard
          of SET_ENCODING_STOP:
            parser.stopped = true
        else:
          let i = token.findAttr(parser.atomMap[ATOM_HTTP_EQUIV])
          if i != -1 and token.attrs[i].value.equalsIgnoreCase("Content-Type"):
            let i = token.findAttr(parser.atomMap[ATOM_CONTENT])
            if i != -1:
              let cs = extractEncFromMeta(token.attrs[i].value)
              if cs != "":
                case parser.setEncoding(cs)
                of SET_ENCODING_CONTINUE:
                  discard
                of SET_ENCODING_STOP:
                  parser.stopped = true
      )
      "<title>" => (block: parser.genericRCDATAElementParsingAlgorithm(token))
      "<noscript>" => (block:
        if not parser.opts.scripting:
          discard parser.insertHTMLElement(token)
          parser.insertionMode = IN_HEAD_NOSCRIPT
        else:
          parser.genericRawtextElementParsingAlgorithm(token)
      )
      ("<noframes>", "<style>") => (block: parser.genericRawtextElementParsingAlgorithm(token))
      "<script>" => (block:
        let location = parser.appropriatePlaceForInsert()
        let element = parser.createElement(token, Namespace.HTML, location.inside)
        #TODO document.write (?)
        parser.insert(location, element)
        parser.pushElement(element, token)
        parser.tokenizer.state = SCRIPT_DATA
        parser.oldInsertionMode = parser.insertionMode
        parser.insertionMode = TEXT
      )
      "</head>" => (block:
        pop_current_node
        parser.insertionMode = AFTER_HEAD
      )
      ("</body>", "</html>", "</br>") => (block: anything_else)
      "<template>" => (block:
        discard parser.insertHTMLElement(token)
        parser.activeFormatting.add((none(Handle), nil))
        parser.framesetok = false
        parser.insertionMode = IN_TEMPLATE
        parser.templateModes.add(IN_TEMPLATE)
      )
      "</template>" => (block:
        if not parser.hasElement(TAG_TEMPLATE):
          parse_error ELEMENT_NOT_IN_OPEN_ELEMENTS
        else:
          parser.generateImpliedEndTagsThoroughly()
          if parser.getTagType(parser.currentNode) != TAG_TEMPLATE:
            parse_error MISMATCHED_TAGS
          parser.popElementsIncl(TAG_TEMPLATE)
          parser.clearActiveFormattingTillMarker()
          discard parser.templateModes.pop()
          parser.resetInsertionMode()
      )
      ("<head>", TokenType.END_TAG) => (block: parse_error UNEXPECTED_END_TAG)
      other => (block:
        pop_current_node
        parser.insertionMode = AFTER_HEAD
        reprocess token
      )

  of IN_HEAD_NOSCRIPT:
    match token:
      TokenType.DOCTYPE => (block: parse_error UNEXPECTED_DOCTYPE)
      "<html>" => (block: parser.processInHTMLContent(token, IN_BODY))
      "</noscript>" => (block:
        pop_current_node
        parser.insertionMode = IN_HEAD
      )
      (TokenType.CHARACTER_WHITESPACE, TokenType.COMMENT,
         "<basefont>", "<bgsound>", "<link>", "<meta>", "<noframes>",
         "<style>") => (block:
        parser.processInHTMLContent(token, IN_HEAD))
      "</br>" => (block: anything_else)
      ("<head>", "<noscript>") => (block: parse_error UNEXPECTED_START_TAG)
      TokenType.END_TAG => (block: parse_error UNEXPECTED_END_TAG)
      other => (block:
        pop_current_node
        parser.insertionMode = IN_HEAD
        reprocess token
      )

  of AFTER_HEAD:
    match token:
      TokenType.CHARACTER_WHITESPACE => (block:
        parser.insertCharacter(token.s)
      )
      TokenType.COMMENT => (block: parser.insertComment(token))
      TokenType.DOCTYPE => (block: parse_error UNEXPECTED_DOCTYPE)
      "<html>" => (block: parser.processInHTMLContent(token, IN_BODY))
      "<body>" => (block:
        discard parser.insertHTMLElement(token)
        parser.framesetok = false
        parser.insertionMode = IN_BODY
      )
      "<frameset>" => (block:
        discard parser.insertHTMLElement(token)
        parser.insertionMode = IN_FRAMESET
      )
      ("<base>", "<basefont>", "<bgsound>", "<link>", "<meta>", "<noframes>",
      "<script>", "<style>", "<template>", "<title>") => (block:
        parse_error UNEXPECTED_START_TAG
        let (head, headTok) = parser.head.get
        parser.pushElement(head, headTok)
        parser.processInHTMLContent(token, IN_HEAD)
        for i in countdown(parser.openElements.high, 0):
          if parser.openElements[i] == parser.head.get:
            parser.openElements.delete(i)
      )
      "</template>" => (block: parser.processInHTMLContent(token, IN_HEAD))
      ("</body>", "</html>", "</br>") => (block: anything_else)
      ("<head>") => (block: parse_error UNEXPECTED_START_TAG)
      (TokenType.END_TAG) => (block: parse_error UNEXPECTED_END_TAG)
      other => (block:
        discard parser.insertHTMLElement(parser.newStartTagToken(TAG_BODY))
        parser.insertionMode = IN_BODY
        reprocess token
      )

  of IN_BODY:
    template any_other_start_tag() =
      parser.reconstructActiveFormatting()
      discard parser.insertHTMLElement(token)

    template any_other_end_tag() =
      for i in countdown(parser.openElements.high, 0):
        let (node, itToken) = parser.openElements[i]
        if itToken.tagname == token.tagname:
          parser.generateImpliedEndTags(token.tagtype)
          if node != parser.currentNode:
            parse_error ELEMENT_NOT_CURRENT_NODE
          while parser.popElement() != node:
            discard
          break
        elif parser.isSpecialElement(node):
          parse_error UNEXPECTED_SPECIAL_ELEMENT
          return

    template parse_error_if_body_has_disallowed_open_elements =
      if parser.hasParseError():
        const Disallowed = AllTagTypes - {
          TAG_DD, TAG_DT, TAG_LI, TAG_OPTGROUP, TAG_OPTION, TAG_P, TAG_RB,
          TAG_RP, TAG_RT, TAG_RTC, TAG_TBODY, TAG_TD, TAG_TFOOT, TAG_TH,
          TAG_THEAD, TAG_TR, TAG_BODY, TAG_HTML
        }
        if parser.hasElement(Disallowed):
          parse_error MISMATCHED_TAGS

    match token:
      TokenType.CHARACTER_WHITESPACE => (block:
        parser.reconstructActiveFormatting()
        parser.insertCharacter(token.s)
      )
      TokenType.CHARACTER_NULL => (block: parse_error UNEXPECTED_NULL)
      TokenType.CHARACTER => (block:
        parser.reconstructActiveFormatting()
        parser.insertCharacter(token.s)
        parser.framesetOk = false
      )
      TokenType.COMMENT => (block: parser.insertComment(token))
      TokenType.DOCTYPE => (block: parse_error UNEXPECTED_DOCTYPE)
      "<html>" => (block:
        parse_error UNEXPECTED_START_TAG
        if parser.hasElement(TAG_TEMPLATE):
          discard
        else:
          parser.addAttrsIfMissing(parser.openElements[0].element, token.attrs)
      )
      ("<base>", "<basefont>", "<bgsound>", "<link>", "<meta>", "<noframes>",
        "<script>", "<style>", "<template>", "<title>",
         "</template>") => (block: parser.processInHTMLContent(token, IN_HEAD))
      "<body>" => (block:
        parse_error UNEXPECTED_START_TAG
        if parser.openElements.len == 1 or
            parser.getTagType(parser.openElements[1].element) != TAG_BODY or
            parser.hasElement(TAG_TEMPLATE):
          discard
        else:
          parser.framesetOk = false
          parser.addAttrsIfMissing(parser.openElements[1].element, token.attrs)
      )
      "<frameset>" => (block:
        parse_error UNEXPECTED_START_TAG
        if parser.openElements.len == 1 or
            parser.getTagType(parser.openElements[1].element) != TAG_BODY or
            not parser.framesetOk:
          discard
        else:
          parser.remove(parser.openElements[1].element)
          while parser.openElements.len > 1:
            pop_current_node
          discard parser.insertHTMLElement(token)
          parser.insertionMode = IN_FRAMESET
      )
      TokenType.EOF => (block:
        if parser.templateModes.len > 0:
          parser.processInHTMLContent(token, IN_TEMPLATE)
        else:
          parse_error_if_body_has_disallowed_open_elements
          # stop
      )
      "</body>" => (block:
        if not parser.hasElementInScope(TAG_BODY):
          parse_error UNEXPECTED_END_TAG
        else:
          parse_error_if_body_has_disallowed_open_elements
          parser.insertionMode = AFTER_BODY
      )
      "</html>" => (block:
        if not parser.hasElementInScope(TAG_BODY):
          parse_error UNEXPECTED_END_TAG
        else:
          parse_error_if_body_has_disallowed_open_elements
          parser.insertionMode = AFTER_BODY
          reprocess token
      )
      ("<address>", "<article>", "<aside>", "<blockquote>", "<center>",
      "<details>", "<dialog>", "<dir>", "<div>", "<dl>", "<fieldset>",
      "<figcaption>", "<figure>", "<footer>", "<header>", "<hgroup>", "<main>",
      "<menu>", "<nav>", "<ol>", "<p>", "<search>", "<section>", "<summary>",
      "<ul>") => (block:
        if parser.hasElementInButtonScope(TAG_P):
          parser.closeP()
        discard parser.insertHTMLElement(token)
      )
      ("<h1>", "<h2>", "<h3>", "<h4>", "<h5>", "<h6>") => (block:
        if parser.hasElementInButtonScope(TAG_P):
          parser.closeP()
        if parser.getTagType(parser.currentNode) in HTagTypes:
          parse_error NESTED_TAGS
          pop_current_node
        discard parser.insertHTMLElement(token)
      )
      ("<pre>", "<listing>") => (block:
        if parser.hasElementInButtonScope(TAG_P):
          parser.closeP()
        discard parser.insertHTMLElement(token)
        parser.ignoreLF = true
        parser.framesetOk = false
      )
      "<form>" => (block:
        let hasTemplate = parser.hasElement(TAG_TEMPLATE)
        if parser.form.isSome and not hasTemplate:
          parse_error NESTED_TAGS
        else:
          if parser.hasElementInButtonScope(TAG_P):
            parser.closeP()
          let element = parser.insertHTMLElement(token)
          if not hasTemplate:
            parser.form = some(element)
      )
      "<li>" => (block:
        parser.framesetOk = false
        for i in countdown(parser.openElements.high, 0):
          let node = parser.openElements[i].element
          let tagType = parser.getTagType(node)
          case tagType
          of TAG_LI:
            parser.generateImpliedEndTags(TAG_LI)
            parse_error_if_mismatch TAG_LI
            parser.popElementsIncl(TAG_LI)
            break
          of TAG_ADDRESS, TAG_DIV, TAG_P:
            discard
          elif parser.isSpecialElement(node):
            break
          else: discard
        if parser.hasElementInButtonScope(TAG_P):
          parser.closeP()
        discard parser.insertHTMLElement(token)
      )
      ("<dd>", "<dt>") => (block:
        parser.framesetOk = false
        for i in countdown(parser.openElements.high, 0):
          let node = parser.openElements[i].element
          let tagType = parser.getTagType(node)
          case tagType
          of TAG_DD:
            parser.generateImpliedEndTags(TAG_DD)
            parse_error_if_mismatch TAG_DD
            parser.popElementsIncl(TAG_DD)
            break
          of TAG_DT:
            parser.generateImpliedEndTags(TAG_DT)
            parse_error_if_mismatch TAG_DT
            parser.popElementsIncl(TAG_DT)
            break
          of TAG_ADDRESS, TAG_DIV, TAG_P:
            discard
          elif parser.isSpecialElement(node):
            break
          else: discard
        if parser.hasElementInButtonScope(TAG_P):
          parser.closeP()
        discard parser.insertHTMLElement(token)
      )
      "<plaintext>" => (block:
        if parser.hasElementInButtonScope(TAG_P):
          parser.closeP()
        discard parser.insertHTMLElement(token)
        parser.tokenizer.state = PLAINTEXT
      )
      "<button>" => (block:
        if parser.hasElementInScope(TAG_BUTTON):
          parse_error NESTED_TAGS
          parser.generateImpliedEndTags()
          parser.popElementsIncl(TAG_BUTTON)
        parser.reconstructActiveFormatting()
        discard parser.insertHTMLElement(token)
        parser.framesetOk = false
      )
      ("</address>", "</article>", "</aside>", "</blockquote>", "</button>",
       "</center>", "</details>", "</dialog>", "</dir>", "</div>", "</dl>",
       "</fieldset>", "</figcaption>", "</figure>", "</footer>", "</header>",
       "</hgroup>", "</listing>", "</main>", "</menu>", "</nav>", "</ol>",
       "</pre>", "</search>", "</section>", "</summary>", "</ul>") => (block:
        if not parser.hasElementInScope(token.tagtype):
          parse_error ELEMENT_NOT_IN_SCOPE
        else:
          parser.generateImpliedEndTags()
          parse_error_if_mismatch token.tagtype
          parser.popElementsIncl(token.tagtype)
      )
      "</form>" => (block:
        if not parser.hasElement(TAG_TEMPLATE):
          let form = parser.form
          parser.form = none(Handle)
          if form.isNone or not parser.hasElementInScope(form.get):
            parse_error ELEMENT_NOT_IN_SCOPE
            return
          let node = form.get
          parser.generateImpliedEndTags()
          if parser.currentNode != node:
            parse_error ELEMENT_NOT_CURRENT_NODE
          let i = parser.findOpenElement(node)
          parser.openElements.delete(i)
        else:
          if not parser.hasElementInScope(TAG_FORM):
            parse_error ELEMENT_NOT_IN_SCOPE
          else:
            parser.generateImpliedEndTags()
            parse_error_if_mismatch TAG_FORM
            parser.popElementsIncl(TAG_FORM)
      )
      "</p>" => (block:
        if not parser.hasElementInButtonScope(TAG_P):
          parse_error ELEMENT_NOT_IN_SCOPE
          discard parser.insertHTMLElement(parser.newStartTagToken(TAG_P))
        parser.closeP()
      )
      "</li>" => (block:
        if not parser.hasElementInListItemScope(TAG_LI):
          parse_error ELEMENT_NOT_IN_SCOPE
        else:
          parser.generateImpliedEndTags(TAG_LI)
          parse_error_if_mismatch TAG_LI
          parser.popElementsIncl(TAG_LI)
      )
      ("</dd>", "</dt>") => (block:
        if not parser.hasElementInScope(token.tagtype):
          parse_error ELEMENT_NOT_IN_SCOPE
        else:
          parser.generateImpliedEndTags(token.tagtype)
          parse_error_if_mismatch token.tagtype
          parser.popElementsIncl(token.tagtype)
      )
      ("</h1>", "</h2>", "</h3>", "</h4>", "</h5>", "</h6>") => (block:
        if not parser.hasElementInScope(HTagTypes):
          parse_error ELEMENT_NOT_IN_SCOPE
        else:
          parser.generateImpliedEndTags()
          parse_error_if_mismatch token.tagtype
          parser.popElementsIncl(HTagTypes)
      )
      "</sarcasm>" => (block:
        #*deep breath*
        anything_else
      )
      "<a>" => (block:
        let i = parser.findLastActiveFormattingAfterMarker(TAG_A)
        if i != -1:
          let anchor = parser.activeFormatting[i][0].get
          parse_error NESTED_TAGS
          if parser.adoptionAgencyAlgorithm(token):
            any_other_end_tag
            return
          let j = parser.findLastActiveFormatting(anchor)
          if j != -1:
            parser.activeFormatting.delete(j)
          let k = parser.findOpenElement(anchor)
          if k != -1:
            parser.openElements.delete(k)
        parser.reconstructActiveFormatting()
        let element = parser.insertHTMLElement(token)
        parser.pushOntoActiveFormatting(element, token)
      )
      ("<b>", "<big>", "<code>", "<em>", "<font>", "<i>", "<s>", "<small>",
       "<strike>", "<strong>", "<tt>", "<u>") => (block:
        parser.reconstructActiveFormatting()
        let element = parser.insertHTMLElement(token)
        parser.pushOntoActiveFormatting(element, token)
      )
      "<nobr>" => (block:
        parser.reconstructActiveFormatting()
        if parser.hasElementInScope(TAG_NOBR):
          parse_error NESTED_TAGS
          if parser.adoptionAgencyAlgorithm(token):
            any_other_end_tag
            return
          parser.reconstructActiveFormatting()
        let element = parser.insertHTMLElement(token)
        parser.pushOntoActiveFormatting(element, token)
      )
      ("</a>", "</b>", "</big>", "</code>", "</em>", "</font>", "</i>",
       "</nobr>", "</s>", "</small>", "</strike>", "</strong>", "</tt>",
       "</u>") => (block:
        if parser.adoptionAgencyAlgorithm(token):
          any_other_end_tag
          return
      )
      ("<applet>", "<marquee>", "<object>") => (block:
        parser.reconstructActiveFormatting()
        discard parser.insertHTMLElement(token)
        parser.activeFormatting.add((none(Handle), nil))
        parser.framesetOk = false
      )
      ("</applet>", "</marquee>", "</object>") => (block:
        if not parser.hasElementInScope(token.tagtype):
          parse_error ELEMENT_NOT_IN_SCOPE
        else:
          parser.generateImpliedEndTags()
          parse_error_if_mismatch token.tagtype
          while parser.getTagType(parser.popElement()) != token.tagtype: discard
          parser.clearActiveFormattingTillMarker()
      )
      "<table>" => (block:
        if parser.quirksMode != QUIRKS:
          if parser.hasElementInButtonScope(TAG_P):
            parser.closeP()
        discard parser.insertHTMLElement(token)
        parser.framesetOk = false
        parser.insertionMode = IN_TABLE
      )
      "</br>" => (block:
        parse_error UNEXPECTED_END_TAG
        reprocess parser.newStartTagToken(TAG_BR)
      )
      ("<area>", "<br>", "<embed>", "<img>", "<keygen>", "<wbr>") => (block:
        parser.reconstructActiveFormatting()
        discard parser.insertHTMLElement(token)
        pop_current_node
        parser.framesetOk = false
      )
      "<input>" => (block:
        parser.reconstructActiveFormatting()
        discard parser.insertHTMLElement(token)
        pop_current_node
        let i = token.findAttr(parser.atomMap[ATOM_TYPE])
        if i == -1 or not token.attrs[i].value.equalsIgnoreCase("hidden"):
          parser.framesetOk = false
      )
      ("<param>", "<source>", "<track>") => (block:
        discard parser.insertHTMLElement(token)
        pop_current_node
      )
      "<hr>" => (block:
        if parser.hasElementInButtonScope(TAG_P):
          parser.closeP()
        discard parser.insertHTMLElement(token)
        pop_current_node
        parser.framesetOk = false
      )
      "<image>" => (block:
        #TODO ew
        let token = Token(
          t: START_TAG,
          tagname: parser.tagTypeToAtom(TAG_IMG),
          selfclosing: token.selfclosing,
          attrs: token.attrs
        )
        reprocess token
      )
      "<textarea>" => (block:
        discard parser.insertHTMLElement(token)
        parser.ignoreLF = true
        parser.tokenizer.state = RCDATA
        parser.oldInsertionMode = parser.insertionMode
        parser.framesetOk = false
        parser.insertionMode = TEXT
      )
      "<xmp>" => (block:
        if parser.hasElementInButtonScope(TAG_P):
          parser.closeP()
        parser.reconstructActiveFormatting()
        parser.framesetOk = false
        parser.genericRawtextElementParsingAlgorithm(token)
      )
      "<iframe>" => (block:
        parser.framesetOk = false
        parser.genericRawtextElementParsingAlgorithm(token)
      )
      "<noembed>" => (block:
        parser.genericRawtextElementParsingAlgorithm(token)
      )
      "<noscript>" => (block:
        if parser.opts.scripting:
          parser.genericRawtextElementParsingAlgorithm(token)
        else:
          any_other_start_tag
      )
      "<select>" => (block:
        parser.reconstructActiveFormatting()
        discard parser.insertHTMLElement(token)
        parser.framesetOk = false
        const TableInsertionModes = {
          IN_TABLE, IN_CAPTION, IN_TABLE_BODY, IN_ROW, IN_CELL
        }
        if parser.insertionMode in TableInsertionModes:
          parser.insertionMode = IN_SELECT_IN_TABLE
        else:
          parser.insertionMode = IN_SELECT
      )
      ("<optgroup>", "<option>") => (block:
        if parser.getTagType(parser.currentNode) == TAG_OPTION:
          pop_current_node
        parser.reconstructActiveFormatting()
        discard parser.insertHTMLElement(token)
      )
      ("<rb>", "<rtc>") => (block:
        if parser.hasElementInScope(TAG_RUBY):
          parser.generateImpliedEndTags()
          parse_error_if_mismatch TAG_RUBY
        discard parser.insertHTMLElement(token)
      )
      ("<rp>", "<rt>") => (block:
        if parser.hasElementInScope(TAG_RUBY):
          parser.generateImpliedEndTags(TAG_RTC)
          parse_error_if_mismatch {TAG_RUBY, TAG_RTC}
        discard parser.insertHTMLElement(token)
      )
      "<math>" => (block:
        parser.reconstructActiveFormatting()
        var attrs = token.attrs.toParsedAttrs()
        parser.adjustMathMLAttributes(attrs)
        parser.adjustForeignAttributes(attrs)
        parser.sortAttributes(attrs)
        const ns = Namespace.MATHML
        let localName = token.tagname
        discard parser.insertForeignElement(token, localName, ns, false, attrs)
        if token.selfclosing:
          pop_current_node
      )
      "<svg>" => (block:
        parser.reconstructActiveFormatting()
        var attrs = token.attrs.toParsedAttrs()
        parser.adjustSVGAttributes(attrs)
        parser.adjustForeignAttributes(attrs)
        parser.sortAttributes(attrs)
        const ns = Namespace.SVG
        let localName = token.tagname
        discard parser.insertForeignElement(token, localName, ns, false, attrs)
        if token.selfclosing:
          pop_current_node
      )
      ("<caption>", "<col>", "<colgroup>", "<frame>", "<head>", "<tbody>",
       "<td>", "<tfoot>", "<th>", "<thead>", "<tr>") => (block:
        parse_error UNEXPECTED_START_TAG
      )
      TokenType.START_TAG => (block: any_other_start_tag)
      TokenType.END_TAG => (block: any_other_end_tag)

  of TEXT:
    match token:
      TokenType.CHARACTER_NULL => (block:
        # "This can never be a U+0000 NULL character; the tokenizer converts
        # those to U+FFFD REPLACEMENT CHARACTER characters."
        assert false
      )
      (TokenType.CHARACTER, TokenType.CHARACTER_WHITESPACE) => (block:
        parser.insertCharacter(token.s)
      )
      TokenType.EOF => (block:
        parse_error UNEXPECTED_EOF
        if parser.getTagType(parser.currentNode) == TAG_SCRIPT:
          parser.setScriptAlreadyStarted(parser.currentNode)
        pop_current_node
        parser.insertionMode = parser.oldInsertionMode
        reprocess token
      )
      "</script>" => (block:
        #TODO microtask (?)
        pop_current_node
        parser.insertionMode = parser.oldInsertionMode
      )
      TokenType.END_TAG => (block:
        pop_current_node
        parser.insertionMode = parser.oldInsertionMode
      )

  of IN_TABLE:
    template clear_the_stack_back_to_a_table_context() =
      const tags = {TAG_TABLE, TAG_TEMPLATE, TAG_HTML}
      while parser.getTagType(parser.currentNode) notin tags:
        pop_current_node

    match token:
      (TokenType.CHARACTER, TokenType.CHARACTER_WHITESPACE,
          TokenType.CHARACTER_NULL) => (block:
        const CanHaveText = {
          TAG_TABLE, TAG_TBODY, TAG_TFOOT, TAG_THEAD, TAG_TR
        }
        if parser.getTagType(parser.currentNode) in CanHaveText:
          parser.pendingTableChars = ""
          parser.pendingTableCharsWhitespace = true
          parser.oldInsertionMode = parser.insertionMode
          parser.insertionMode = IN_TABLE_TEXT
          reprocess token
        else: # anything else
          parse_error INVALID_TEXT_PARENT
          parser.fosterParenting = true
          parser.processInHTMLContent(token, IN_BODY)
          parser.fosterParenting = false
      )
      TokenType.COMMENT => (block: parser.insertComment(token))
      TokenType.DOCTYPE => (block: parse_error UNEXPECTED_DOCTYPE)
      "<caption>" => (block:
        clear_the_stack_back_to_a_table_context
        parser.activeFormatting.add((none(Handle), nil))
        discard parser.insertHTMLElement(token)
        parser.insertionMode = IN_CAPTION
      )
      "<colgroup>" => (block:
        clear_the_stack_back_to_a_table_context
        let colgroupTok = parser.newStartTagToken(TAG_COLGROUP)
        discard parser.insertHTMLElement(colgroupTok)
        parser.insertionMode = IN_COLUMN_GROUP
      )
      "<col>" => (block:
        clear_the_stack_back_to_a_table_context
        let colgroupTok = parser.newStartTagToken(TAG_COLGROUP)
        discard parser.insertHTMLElement(colgroupTok)
        parser.insertionMode = IN_COLUMN_GROUP
        reprocess token
      )
      ("<tbody>", "<tfoot>", "<thead>") => (block:
        clear_the_stack_back_to_a_table_context
        discard parser.insertHTMLElement(token)
        parser.insertionMode = IN_TABLE_BODY
      )
      ("<td>", "<th>", "<tr>") => (block:
        clear_the_stack_back_to_a_table_context
        discard parser.insertHTMLElement(parser.newStartTagToken(TAG_TBODY))
        parser.insertionMode = IN_TABLE_BODY
        reprocess token
      )
      "<table>" => (block:
        parse_error NESTED_TAGS
        if not parser.hasElementInTableScope(TAG_TABLE):
          discard
        else:
          while parser.getTagType(parser.popElement()) != TAG_TABLE: discard
          parser.resetInsertionMode()
          reprocess token
      )
      "</table>" => (block:
        if not parser.hasElementInTableScope(TAG_TABLE):
          parse_error ELEMENT_NOT_IN_SCOPE
        else:
          while parser.getTagType(parser.popElement()) != TAG_TABLE: discard
          parser.resetInsertionMode()
      )
      ("</body>", "</caption>", "</col>", "</colgroup>", "</html>", "</tbody>",
       "</td>", "</tfoot>", "</th>", "</thead>", "</tr>") => (block:
        parse_error UNEXPECTED_END_TAG
      )
      ("<style>", "<script>", "<template>", "</template>") => (block:
        parser.processInHTMLContent(token, IN_HEAD)
      )
      "<input>" => (block:
        parse_error UNEXPECTED_START_TAG
        let i = token.findAttr(parser.atomMap[ATOM_TYPE])
        if i == -1 or not token.attrs[i].value.equalsIgnoreCase("hidden"):
          # anything else
          parser.fosterParenting = true
          parser.processInHTMLContent(token, IN_BODY)
          parser.fosterParenting = false
        else:
          discard parser.insertHTMLElement(token)
          pop_current_node
      )
      "<form>" => (block:
        parse_error UNEXPECTED_START_TAG
        if parser.form.isSome or parser.hasElement(TAG_TEMPLATE):
          discard
        else:
          parser.form = some(parser.insertHTMLElement(token))
          pop_current_node
      )
      TokenType.EOF => (block:
        parser.processInHTMLContent(token, IN_BODY)
      )
      other => (block:
        parse_error UNEXPECTED_START_TAG
        parser.fosterParenting = true
        parser.processInHTMLContent(token, IN_BODY)
        parser.fosterParenting = false
      )

  of IN_TABLE_TEXT:
    match token:
      TokenType.CHARACTER_NULL => (block: parse_error UNEXPECTED_NULL)
      TokenType.CHARACTER_WHITESPACE => (block:
        parser.pendingTableChars &= token.s
      )
      TokenType.CHARACTER => (block:
        parser.pendingTableCharsWhitespace = false
        parser.pendingTableChars &= token.s
      )
      other => (block:
        if not parser.pendingTableCharsWhitespace:
          # I *think* this is effectively the same thing the specification
          # wants...
          parse_error NON_SPACE_TABLE_TEXT
          parser.fosterParenting = true
          parser.reconstructActiveFormatting()
          parser.insertCharacter(parser.pendingTableChars)
          parser.framesetOk = false
          parser.fosterParenting = false
        else:
          parser.insertCharacter(parser.pendingTableChars)
        parser.insertionMode = parser.oldInsertionMode
        reprocess token
      )

  of IN_CAPTION:
    match token:
      "</caption>" => (block:
        if not parser.hasElementInTableScope(TAG_CAPTION):
          parse_error ELEMENT_NOT_IN_SCOPE
        else:
          parser.generateImpliedEndTags()
          parse_error_if_mismatch TAG_CAPTION
          parser.popElementsIncl(TAG_CAPTION)
          parser.clearActiveFormattingTillMarker()
          parser.insertionMode = IN_TABLE
      )
      ("<caption>", "<col>", "<colgroup>", "<tbody>", "<td>", "<tfoot>",
       "<th>", "<thead>", "<tr>", "</table>") => (block:
        if not parser.hasElementInTableScope(TAG_CAPTION):
          parse_error ELEMENT_NOT_IN_SCOPE
        else:
          parser.generateImpliedEndTags()
          parse_error_if_mismatch TAG_CAPTION
          parser.popElementsIncl(TAG_CAPTION)
          parser.clearActiveFormattingTillMarker()
          parser.insertionMode = IN_TABLE
          reprocess token
      )
      ("</body>", "</col>", "</colgroup>", "</html>", "</tbody>", "</td>",
       "</tfoot>", "</th>", "</thead>", "</tr>") => (block:
        parse_error UNEXPECTED_END_TAG
      )
      other => (block: parser.processInHTMLContent(token, IN_BODY))

  of IN_COLUMN_GROUP:
    match token:
      TokenType.CHARACTER_WHITESPACE => (block:
        parser.insertCharacter(token.s)
      )
      TokenType.COMMENT => (block: parser.insertComment(token))
      TokenType.DOCTYPE => (block: parse_error UNEXPECTED_DOCTYPE)
      "<html>" => (block: parser.processInHTMLContent(token, IN_BODY))
      "<col>" => (block:
        discard parser.insertHTMLElement(token)
        pop_current_node
      )
      "</colgroup>" => (block:
        if parser.getTagType(parser.currentNode) != TAG_COLGROUP:
          parse_error MISMATCHED_TAGS
        else:
          pop_current_node
          parser.insertionMode = IN_TABLE
      )
      "</col>" => (block: parse_error UNEXPECTED_END_TAG)
      ("<template>", "</template>") => (block:
        parser.processInHTMLContent(token, IN_HEAD)
      )
      TokenType.EOF => (block: parser.processInHTMLContent(token, IN_BODY))
      other => (block:
        if parser.getTagType(parser.currentNode) != TAG_COLGROUP:
          parse_error MISMATCHED_TAGS
        else:
          pop_current_node
          parser.insertionMode = IN_TABLE
          reprocess token
      )

  of IN_TABLE_BODY:
    template clear_the_stack_back_to_a_table_body_context() =
      const tags = {TAG_TBODY, TAG_TFOOT, TAG_THEAD, TAG_TEMPLATE, TAG_HTML}
      while parser.getTagType(parser.currentNode) notin tags:
        pop_current_node

    match token:
      "<tr>" => (block:
        clear_the_stack_back_to_a_table_body_context
        discard parser.insertHTMLElement(token)
        parser.insertionMode = IN_ROW
      )
      ("<th>", "<td>") => (block:
        parse_error UNEXPECTED_START_TAG
        clear_the_stack_back_to_a_table_body_context
        discard parser.insertHTMLElement(parser.newStartTagToken(TAG_TR))
        parser.insertionMode = IN_ROW
        reprocess token
      )
      ("</tbody>", "</tfoot>", "</thead>") => (block:
        if not parser.hasElementInTableScope(token.tagtype):
          parse_error ELEMENT_NOT_IN_SCOPE
        else:
          clear_the_stack_back_to_a_table_body_context
          pop_current_node
          parser.insertionMode = IN_TABLE
      )
      ("<caption>", "<col>", "<colgroup>", "<tbody>", "<tfoot>", "<thead>",
       "</table>") => (block:
        if not parser.hasElementInTableScope({TAG_TBODY, TAG_THEAD, TAG_TFOOT}):
          parse_error ELEMENT_NOT_IN_SCOPE
        else:
          clear_the_stack_back_to_a_table_body_context
          pop_current_node
          parser.insertionMode = IN_TABLE
          reprocess token
      )
      ("</body>", "</caption>", "</col>", "</colgroup>", "</html>", "</td>",
       "</th>", "</tr>") => (block:
        parse_error ELEMENT_NOT_IN_SCOPE
      )
      other => (block: parser.processInHTMLContent(token, IN_TABLE))

  of IN_ROW:
    template clear_the_stack_back_to_a_table_row_context() =
      while parser.getTagType(parser.currentNode) notin {TAG_TR, TAG_TEMPLATE, TAG_HTML}:
        pop_current_node

    match token:
      ("<th>", "<td>") => (block:
        clear_the_stack_back_to_a_table_row_context
        discard parser.insertHTMLElement(token)
        parser.insertionMode = IN_CELL
        parser.activeFormatting.add((none(Handle), nil))
      )
      "</tr>" => (block:
        if not parser.hasElementInTableScope(TAG_TR):
          parse_error ELEMENT_NOT_IN_SCOPE
        else:
          clear_the_stack_back_to_a_table_row_context
          pop_current_node
          parser.insertionMode = IN_TABLE_BODY
      )
      ("<caption>", "<col>", "<colgroup>", "<tbody>", "<tfoot>", "<thead>",
       "<tr>", "</table>") => (block:
        if not parser.hasElementInTableScope(TAG_TR):
          parse_error ELEMENT_NOT_IN_SCOPE
        else:
          clear_the_stack_back_to_a_table_row_context
          pop_current_node
          parser.insertionMode = IN_TABLE_BODY
          reprocess token
      )
      ("</tbody>", "</tfoot>", "</thead>") => (block:
        if not parser.hasElementInTableScope(token.tagtype):
          parse_error ELEMENT_NOT_IN_SCOPE
        elif not parser.hasElementInTableScope(TAG_TR):
          discard
        else:
          clear_the_stack_back_to_a_table_row_context
          pop_current_node
          parser.insertionMode = IN_TABLE_BODY
          reprocess token
      )
      ("</body>", "</caption>", "</col>", "</colgroup>", "</html>", "</td>",
       "</th>") => (block: parse_error UNEXPECTED_END_TAG)
      other => (block: parser.processInHTMLContent(token, IN_TABLE))

  of IN_CELL:
    template close_cell() =
      parser.generateImpliedEndTags()
      parse_error_if_mismatch {TAG_TD, TAG_TH}
      parser.popElementsIncl({TAG_TD, TAG_TH})
      parser.clearActiveFormattingTillMarker()
      parser.insertionMode = IN_ROW

    match token:
      ("</td>", "</th>") => (block:
        if not parser.hasElementInTableScope(token.tagtype):
          parse_error ELEMENT_NOT_IN_SCOPE
        else:
          parser.generateImpliedEndTags()
          parse_error_if_mismatch token.tagtype
          parser.popElementsIncl(token.tagtype)
          parser.clearActiveFormattingTillMarker()
          parser.insertionMode = IN_ROW
      )
      ("<caption>", "<col>", "<colgroup>", "<tbody>", "<td>", "<tfoot>",
       "<th>", "<thead>", "<tr>") => (block:
        if not parser.hasElementInTableScope({TAG_TD, TAG_TH}):
          parse_error ELEMENT_NOT_IN_SCOPE
        else:
          close_cell
          reprocess token
      )
      ("</body>", "</caption>", "</col>", "</colgroup>", "</html>") => (block:
        parse_error UNEXPECTED_END_TAG
      )
      ("</table>", "</tbody>", "</tfoot>", "</thead>", "</tr>") => (block:
        if not parser.hasElementInTableScope(token.tagtype):
          parse_error ELEMENT_NOT_IN_SCOPE
        else:
          close_cell
          reprocess token
      )
      other => (block: parser.processInHTMLContent(token, IN_BODY))

  of IN_SELECT:
    match token:
      TokenType.CHARACTER_NULL => (block: parse_error UNEXPECTED_NULL)
      TokenType.CHARACTER => (block:
        parser.insertCharacter(token.s)
      )
      TokenType.CHARACTER_WHITESPACE => (block:
        parser.insertCharacter(token.s)
      )
      TokenType.COMMENT => (block: parser.insertComment(token))
      TokenType.DOCTYPE => (block: parse_error UNEXPECTED_DOCTYPE)
      "<html>" => (block: parser.processInHTMLContent(token, IN_BODY))
      "<option>" => (block:
        if parser.getTagType(parser.currentNode) == TAG_OPTION:
          pop_current_node
        discard parser.insertHTMLElement(token)
      )
      "<optgroup>" => (block:
        if parser.getTagType(parser.currentNode) == TAG_OPTION:
          pop_current_node
        if parser.getTagType(parser.currentNode) == TAG_OPTGROUP:
          pop_current_node
        discard parser.insertHTMLElement(token)
      )
      "<hr>" => (block:
        if parser.getTagType(parser.currentNode) == TAG_OPTION:
          pop_current_node
        if parser.getTagType(parser.currentNode) == TAG_OPTGROUP:
          pop_current_node
        discard parser.insertHTMLElement(token)
        pop_current_node
      )
      "</optgroup>" => (block:
        if parser.getTagType(parser.currentNode) == TAG_OPTION:
          if parser.openElements.len > 1:
            let tagType = parser.getTagType(parser.openElements[^2].element)
            if tagType == TAG_OPTGROUP:
              pop_current_node
        if parser.getTagType(parser.currentNode) == TAG_OPTGROUP:
          pop_current_node
        else:
          parse_error MISMATCHED_TAGS
      )
      "</option>" => (block:
        if parser.getTagType(parser.currentNode) == TAG_OPTION:
          pop_current_node
        else:
          parse_error MISMATCHED_TAGS
      )
      "</select>" => (block:
        if not parser.hasElementInSelectScope(TAG_SELECT):
          parse_error ELEMENT_NOT_IN_SCOPE
        else:
          while parser.getTagType(parser.popElement()) != TAG_SELECT: discard
          parser.resetInsertionMode()
      )
      "<select>" => (block:
        parse_error NESTED_TAGS
        if parser.hasElementInSelectScope(TAG_SELECT):
          while parser.getTagType(parser.popElement()) != TAG_SELECT: discard
          parser.resetInsertionMode()
      )
      ("<input>", "<keygen>", "<textarea>") => (block:
        parse_error UNEXPECTED_START_TAG
        if not parser.hasElementInSelectScope(TAG_SELECT):
          discard
        else:
          while parser.getTagType(parser.popElement()) != TAG_SELECT: discard
          parser.resetInsertionMode()
          reprocess token
      )
      ("<script>", "<template>", "</template>") => (block: parser.processInHTMLContent(token, IN_HEAD))
      TokenType.EOF => (block: parser.processInHTMLContent(token, IN_BODY))
      TokenType.START_TAG => (block: parse_error UNEXPECTED_START_TAG)
      TokenType.END_TAG => (block: parse_error UNEXPECTED_END_TAG)

  of IN_SELECT_IN_TABLE:
    match token:
      ("<caption>", "<table>", "<tbody>", "<tfoot>", "<thead>", "<tr>", "<td>",
       "<th>") => (block:
        parse_error UNEXPECTED_START_TAG
        parser.popElementsIncl(TAG_SELECT)
        parser.resetInsertionMode()
        reprocess token
      )
      ("</caption>", "</table>", "</tbody>", "</tfoot>", "</thead>", "</tr>",
       "</td>", "</th>") => (block:
        parse_error UNEXPECTED_END_TAG
        if not parser.hasElementInTableScope(token.tagtype):
          discard
        else:
          parser.popElementsIncl(TAG_SELECT)
          parser.resetInsertionMode()
          reprocess token
      )
      other => (block: parser.processInHTMLContent(token, IN_SELECT))

  of IN_TEMPLATE:
    match token:
      (TokenType.CHARACTER, TokenType.CHARACTER_WHITESPACE,
          TokenType.CHARACTER_NULL, TokenType.DOCTYPE) => (block:
        parser.processInHTMLContent(token, IN_BODY)
      )
      ("<base>", "<basefont>", "<bgsound>", "<link>", "<meta>", "<noframes>",
       "<script>", "<style>", "<template>", "<title>", "</template>") => (block:
        parser.processInHTMLContent(token, IN_HEAD)
      )
      ("<caption>", "<colgroup>", "<tbody>", "<tfoot>", "<thead>") => (block:
        discard parser.templateModes.pop()
        parser.templateModes.add(IN_TABLE)
        parser.insertionMode = IN_TABLE
        reprocess token
      )
      "<col>" => (block:
        discard parser.templateModes.pop()
        parser.templateModes.add(IN_COLUMN_GROUP)
        parser.insertionMode = IN_COLUMN_GROUP
        reprocess token
      )
      "<tr>" => (block:
        discard parser.templateModes.pop()
        parser.templateModes.add(IN_TABLE_BODY)
        parser.insertionMode = IN_TABLE_BODY
        reprocess token
      )
      ("<td>", "<th>") => (block:
        discard parser.templateModes.pop()
        parser.templateModes.add(IN_ROW)
        parser.insertionMode = IN_ROW
        reprocess token
      )
      TokenType.START_TAG => (block:
        discard parser.templateModes.pop()
        parser.templateModes.add(IN_BODY)
        parser.insertionMode = IN_BODY
        reprocess token
      )
      TokenType.END_TAG => (block: parse_error UNEXPECTED_END_TAG)
      TokenType.EOF => (block:
        if not parser.hasElement(TAG_TEMPLATE):
          discard # stop
        else:
          parse_error UNEXPECTED_EOF
          parser.popElementsIncl(TAG_TEMPLATE)
          parser.clearActiveFormattingTillMarker()
          discard parser.templateModes.pop()
          parser.resetInsertionMode()
          reprocess token
      )

  of AFTER_BODY:
    match token:
      TokenType.CHARACTER_WHITESPACE => (block:
        parser.processInHTMLContent(token, IN_BODY)
      )
      TokenType.COMMENT => (block:
        parser.insertComment(token, last_child_of(parser.openElements[0]))
      )
      TokenType.DOCTYPE => (block: parse_error UNEXPECTED_DOCTYPE)
      "<html>" => (block: parser.processInHTMLContent(token, IN_BODY))
      "</html>" => (block:
        if parser.fragment:
          parse_error UNEXPECTED_END_TAG
        else:
          parser.insertionMode = AFTER_AFTER_BODY
      )
      TokenType.EOF => (block: discard) # stop
      other => (block:
        parse_error UNEXPECTED_AFTER_BODY_TOKEN
        parser.insertionMode = IN_BODY
        reprocess token
      )

  of IN_FRAMESET:
    match token:
      TokenType.CHARACTER_WHITESPACE => (block:
        parser.insertCharacter(token.s)
      )
      TokenType.COMMENT => (block: parser.insertComment(token))
      TokenType.DOCTYPE => (block: parse_error UNEXPECTED_DOCTYPE)
      "<html>" => (block: parser.processInHTMLContent(token, IN_BODY))
      "<frameset>" => (block: discard parser.insertHTMLElement(token))
      "</frameset>" => (block:
        if parser.getTagType(parser.currentNode) == TAG_HTML:
          parse_error UNEXPECTED_START_TAG
        else:
          pop_current_node
        if not parser.fragment and
            parser.getTagType(parser.currentNode) != TAG_FRAMESET:
          parser.insertionMode = AFTER_FRAMESET
      )
      "<frame>" => (block:
        discard parser.insertHTMLElement(token)
        pop_current_node
      )
      "<noframes>" => (block: parser.processInHTMLContent(token, IN_HEAD))
      TokenType.EOF => (block:
        if parser.getTagType(parser.currentNode) != TAG_HTML:
          parse_error UNEXPECTED_EOF
        # stop
      )
      other => (block: parser.parseErrorByTokenType(token.t))

  of AFTER_FRAMESET:
    match token:
      TokenType.CHARACTER_WHITESPACE => (block:
        parser.insertCharacter(token.s)
      )
      TokenType.COMMENT => (block: parser.insertComment(token))
      TokenType.DOCTYPE => (block: parse_error UNEXPECTED_DOCTYPE)
      "<html>" => (block: parser.processInHTMLContent(token, IN_BODY))
      "</html>" => (block: parser.insertionMode = AFTER_AFTER_FRAMESET)
      "<noframes>" => (block: parser.processInHTMLContent(token, IN_HEAD))
      TokenType.EOF => (block: discard) # stop
      other => (block: parser.parseErrorByTokenType(token.t))

  of AFTER_AFTER_BODY:
    match token:
      TokenType.COMMENT => (block:
        parser.insertComment(token, last_child_of(parser.getDocument()))
      )
      (TokenType.DOCTYPE, TokenType.CHARACTER_WHITESPACE, "<html>") => (block:
        parser.processInHTMLContent(token, IN_BODY)
      )
      TokenType.EOF => (block: discard) # stop
      other => (block:
        parser.parseErrorByTokenType(token.t)
        parser.insertionMode = IN_BODY
        reprocess token
      )

  of AFTER_AFTER_FRAMESET:
    match token:
      TokenType.COMMENT => (block:
        parser.insertComment(token, last_child_of(parser.getDocument()))
      )
      (TokenType.DOCTYPE, TokenType.CHARACTER_WHITESPACE, "<html>") => (block:
        parser.processInHTMLContent(token, IN_BODY)
      )
      TokenType.EOF => (block: discard) # stop
      "<noframes>" => (block: parser.processInHTMLContent(token, IN_HEAD))
      other => (block: parser.parseErrorByTokenType(token.t))

proc processInForeignContent(parser: var HTML5Parser, token: Token) =
  macro `=>`(v: typed, body: untyped): untyped =
    quote do:
      discard (`v`, proc() = `body`)

  template script_end_tag() =
    pop_current_node
    #TODO document.write (?)
    #TODO SVG

  template parse_error(e: ParseError) =
    parser.parseError(e)

  template any_other_start_tag() =
    let namespace = parser.getNamespace(parser.adjustedCurrentNode)
    var attrs = token.attrs.toParsedAttrs()
    var tagname = token.tagname
    if namespace == Namespace.SVG:
      parser.caseTable.withValue(tagname, p):
        tagname = p[]
      parser.adjustSVGAttributes(attrs)
    elif namespace == Namespace.MATHML:
      parser.adjustMathMLAttributes(attrs)
    parser.adjustForeignAttributes(attrs)
    parser.sortAttributes(attrs)
    discard parser.insertForeignElement(token, tagname, namespace, false,
      attrs)
    if token.selfclosing:
      if namespace == Namespace.SVG:
        script_end_tag
      else:
        pop_current_node

  template any_other_end_tag() =
    if parser.currentToken.tagname != token.tagname:
      # Compare the start tag token, since it is guaranteed to be lower case.
      # (The local name might have been adjusted to a non-lower-case string.)
      parse_error UNEXPECTED_END_TAG
    for i in countdown(parser.openElements.high, 0): # loop
      if i == 0: # fragment case
        assert parser.fragment
        break
      let (node, nodeToken) = parser.openElements[i]
      if i != parser.openElements.high and
          parser.getNamespace(node) == Namespace.HTML:
        parser.processInHTMLContent(token, parser.insertionMode)
        break
      if nodeToken.tagname == token.tagname:
        # Compare the start tag token, since it is guaranteed to be lower case.
        # (The local name might have been adjusted to a non-lower-case string.)
        parser.popElementsIncl(node)
        break

  match token:
    TokenType.CHARACTER_NULL => (block:
      parse_error UNEXPECTED_NULL
      parser.insertCharacter("\uFFFD")
    )
    TokenType.CHARACTER_WHITESPACE => (block: parser.insertCharacter(token.s))
    TokenType.CHARACTER => (block:
      parser.insertCharacter(token.s)
      parser.framesetOk = false
    )
    TokenType.COMMENT => (block: parser.insertComment(token))
    TokenType.DOCTYPE => (block: parse_error UNEXPECTED_DOCTYPE)
    ("<b>", "<big>", "<blockquote>", "<body>", "<br>", "<center>", "<code>",
     "<dd>", "<div>", "<dl>", "<dt>", "<em>", "<embed>", "<h1>", "<h2>",
     "<h3>", "<h4>", "<h5>", "<h6>", "<head>", "<hr>", "<i>", "<img>", "<li>",
     "<listing>", "<menu>", "<meta>", "<nobr>", "<ol>", "<p>", "<pre>",
     "<ruby>", "<s>", "<small>", "<span>", "<strong>", "<strike>", "<sub>",
     "<sup>", "<table>", "<tt>", "<u>", "<ul>", "<var>",
     "<font>", # only if has "color", "face", or "size"
     "</br>", "</p>") => (block:
      if token.tagtype == TAG_FONT:
        const AttrsToCheck = [ATOM_COLOR, ATOM_FACE, ATOM_SIZE]
        block notfound:
          for attr in token.attrs:
            for x in AttrsToCheck:
              if attr.name == parser.atomMap[x]:
                break notfound
          any_other_start_tag
          return
      parse_error UNEXPECTED_START_TAG #TODO this makes no sense
      while not parser.isMathMLIntegrationPoint(parser.currentNode) and
          not parser.isHTMLIntegrationPoint(parser.currentNodeToken) and
          parser.getNamespace(parser.currentNode) != Namespace.HTML:
        pop_current_node
      parser.processInHTMLContent(token, parser.insertionMode)
    )
    TokenType.START_TAG => (block:
      any_other_start_tag
    )
    "</script>" => (block:
      let namespace = parser.getNamespace(parser.currentNode)
      let localName = parser.currentToken.tagname
      # Any atom corresponding to the string "script" must have the same
      # value as TAG_SCRIPT, so this is correct.
      if namespace == Namespace.SVG and localName.toTagType() == TAG_SCRIPT:
        script_end_tag
      else:
        any_other_end_tag
    )
    TokenType.END_TAG => (block: any_other_end_tag)

proc constructTree[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  for token in parser.tokenizer.tokenize:
    if parser.ignoreLF:
      parser.ignoreLF = false
      if token.t == CHARACTER_WHITESPACE:
        if token.s[0] == '\n':
          if token.s.len == 1:
            continue
          else:
            token.s.delete(0..0)
    if parser.openElements.len == 0 or
        parser.getNamespace(parser.adjustedCurrentNode) == Namespace.HTML:
      parser.processInHTMLContent(token, parser.insertionMode)
    else:
      let oe = parser.adjustedCurrentNodeToken
      let localName = oe.token.tagname
      let namespace = parser.getNamespace(oe.element)
      const CharacterToken = {CHARACTER, CHARACTER_WHITESPACE, CHARACTER_NULL}
      let mmlnoatoms = [
        parser.atomMap[ATOM_MGLYPH],
        parser.atomMap[ATOM_MALIGNMARK]
      ]
      let annotationXml = parser.atomMap[ATOM_ANNOTATION_XML]
      let ismmlip = parser.isMathMLIntegrationPoint(oe.element)
      let ishtmlip = parser.isHTMLIntegrationPoint(oe)
      if ismmlip and token.t == START_TAG and token.tagname notin mmlnoatoms or
          ismmlip and token.t in CharacterToken or
          namespace == Namespace.MATHML and localName == annotationXml and
            token.t == START_TAG and token.tagtype == TAG_SVG or
          ishtmlip and token.t == START_TAG or
          ishtmlip and token.t in CharacterToken:
        parser.processInHTMLContent(token, parser.insertionMode)
      else:
        parser.processInForeignContent(token)
    if parser.stopped:
      return
  parser.processInHTMLContent(Token[Atom](t: EOF), parser.insertionMode)

proc finishParsing(parser: var HTML5Parser) =
  while parser.openElements.len > 0:
    pop_current_node
  if parser.dombuilder.finish != nil:
    parser.dombuilder.finish(parser.dombuilder)

# Any of these pointers being nil would later result in a crash.
proc checkCallbacks(dombuilder: DOMBuilder) =
  doAssert dombuilder.getDocument != nil
  doAssert dombuilder.getAtomFactory != nil
  doAssert dombuilder.getParentNode != nil
  doAssert dombuilder.getLocalName != nil
  doAssert dombuilder.createElement != nil
  doAssert dombuilder.createComment != nil
  doAssert dombuilder.createDocumentType != nil
  doAssert dombuilder.insertBefore != nil
  doAssert dombuilder.insertText != nil
  doAssert dombuilder.remove != nil
  doAssert dombuilder.moveChildren != nil

proc checkCallbacks(factory: AtomFactory) =
  doAssert factory.strToAtomImpl != nil
  doAssert factory.tagTypeToAtomImpl != nil

const CaseTable = {
  "altglyph": "altGlyph",
  "altglyphdef": "altGlyphDef",
  "altglyphitem": "altGlyphItem",
  "animatecolor": "animateColor",
  "animatemotion": "animateMotion",
  "animatetransform": "animateTransform",
  "clippath": "clipPath",
  "feblend": "feBlend",
  "fecolormatrix": "feColorMatrix",
  "fecomponenttransfer": "feComponentTransfer",
  "fecomposite": "feComposite",
  "feconvolvematrix": "feConvolveMatrix",
  "fediffuselighting": "feDiffuseLighting",
  "fedisplacementmap": "feDisplacementMap",
  "fedistantlight": "feDistantLight",
  "fedropshadow": "feDropShadow",
  "feflood": "feFlood",
  "fefunca": "feFuncA",
  "fefuncb": "feFuncB",
  "fefuncg": "feFuncG",
  "fefuncr": "feFuncR",
  "fegaussianblur": "feGaussianBlur",
  "feimage": "feImage",
  "femerge": "feMerge",
  "femergenode": "feMergeNode",
  "femorphology": "feMorphology",
  "feoffset": "feOffset",
  "fepointlight": "fePointLight",
  "fespecularlighting": "feSpecularLighting",
  "fespotlight": "feSpotLight",
  "fetile": "feTile",
  "feturbulence": "feTurbulence",
  "foreignobject": "foreignObject",
  "glyphref": "glyphRef",
  "lineargradient": "linearGradient",
  "radialgradient": "radialGradient",
  "textpath": "textPath",
}

proc createCaseTable[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  for (k, v) in CaseTable:
    let ka = parser.strToAtom(k)
    let va = parser.strToAtom(v)
    parser.caseTable[ka] = va

const AdjustedTable = {
  "attributename": "attributeName",
  "attributetype": "attributeType",
  "basefrequency": "baseFrequency",
  "baseprofile": "baseProfile",
  "calcmode": "calcMode",
  "clippathunits": "clipPathUnits",
  "diffuseconstant": "diffuseConstant",
  "edgemode": "edgeMode",
  "filterunits": "filterUnits",
  "glyphref": "glyphRef",
  "gradienttransform": "gradientTransform",
  "gradientunits": "gradientUnits",
  "kernelmatrix": "kernelMatrix",
  "kernelunitlength": "kernelUnitLength",
  "keypoints": "keyPoints",
  "keysplines": "keySplines",
  "keytimes": "keyTimes",
  "lengthadjust": "lengthAdjust",
  "limitingconeangle": "limitingConeAngle",
  "markerheight": "markerHeight",
  "markerunits": "markerUnits",
  "markerwidth": "markerWidth",
  "maskcontentunits": "maskContentUnits",
  "maskunits": "maskUnits",
  "numoctaves": "numOctaves",
  "pathlength": "pathLength",
  "patterncontentunits": "patternContentUnits",
  "patterntransform": "patternTransform",
  "patternunits": "patternUnits",
  "pointsatx": "pointsAtX",
  "pointsaty": "pointsAtY",
  "pointsatz": "pointsAtZ",
  "preservealpha": "preserveAlpha",
  "preserveaspectratio": "preserveAspectRatio",
  "primitiveunits": "primitiveUnits",
  "refx": "refX",
  "refy": "refY",
  "repeatcount": "repeatCount",
  "repeatdur": "repeatDur",
  "requiredextensions": "requiredExtensions",
  "requiredfeatures": "requiredFeatures",
  "specularconstant": "specularConstant",
  "specularexponent": "specularExponent",
  "spreadmethod": "spreadMethod",
  "startoffset": "startOffset",
  "stddeviation": "stdDeviation",
  "stitchtiles": "stitchTiles",
  "surfacescale": "surfaceScale",
  "systemlanguage": "systemLanguage",
  "tablevalues": "tableValues",
  "targetx": "targetX",
  "targety": "targetY",
  "textlength": "textLength",
  "viewbox": "viewBox",
  "viewtarget": "viewTarget",
  "xchannelselector": "xChannelSelector",
  "ychannelselector": "yChannelSelector",
  "zoomandpan": "zoomAndPan",
}

proc createAdjustedTable[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  for (k, v) in AdjustedTable:
    let ka = parser.strToAtom(k)
    let va = parser.strToAtom(v)
    parser.adjustedTable[ka] = va

const ForeignTable = {
  "xlink:actuate": (PREFIX_XLINK, "actuate", Namespace.XLINK),
  "xlink:arcrole": (PREFIX_XLINK, "arcrole", Namespace.XLINK),
  "xlink:href": (PREFIX_XLINK, "href", Namespace.XLINK),
  "xlink:role": (PREFIX_XLINK, "role", Namespace.XLINK),
  "xlink:show": (PREFIX_XLINK, "show", Namespace.XLINK),
  "xlink:title": (PREFIX_XLINK, "title", Namespace.XLINK),
  "xlink:type": (PREFIX_XLINK, "type", Namespace.XLINK),
  "xml:lang": (PREFIX_XML, "lang", Namespace.XML),
  "xml:space": (PREFIX_XML, "space", Namespace.XML),
  "xmlns": (NO_PREFIX, "xmlns", Namespace.XMLNS),
  "xmlns:xlink": (PREFIX_XMLNS, "xlink", Namespace.XMLNS),
}

proc createForeignTable[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  for (oldName, qualName) in ForeignTable:
    let (prefix, newName, ns) = qualName
    let oldNameAtom = parser.strToAtom(oldName)
    let newNameAtom = parser.strToAtom(newName)
    parser.foreignTable[oldNameAtom] = (prefix, ns, newNameAtom)

proc parseHTML*[Handle, Atom](inputStream: Stream,
    dombuilder: DOMBuilder[Handle, Atom], opts: HTML5ParserOpts[Handle, Atom]) =
  ## Read and parse an HTML document from input stream `inputStream`, using
  ## the DOMBuilder object `dombuilder`, and parser options `opts`.
  ##
  ## The generic `Handle` must be the node handle type of the DOM builder. The
  ## generic `Atom` must be the interned string type of the DOM builder.
  ##
  ## The input stream does not have to be seekable for this function.
  dombuilder.checkCallbacks()
  let tokstate = opts.initialTokenizerState
  let factory = dombuilder.getAtomFactory(dombuilder)
  var parser = HTML5Parser[Handle, Atom](
    dombuilder: dombuilder,
    factory: factory,
    opts: opts,
    openElements: opts.openElementsInit,
    form: opts.formInit,
    framesetOk: true
  )
  parser.createCaseTable()
  parser.createAdjustedTable()
  parser.createForeignTable()
  for mapped in MappedAtom:
    parser.atomMap[mapped] = parser.strToAtom($mapped)
  if opts.pushInTemplate:
    parser.templateModes.add(IN_TEMPLATE)
  if opts.openElementsInit.len > 0:
    parser.resetInsertionMode()
  proc x(e: ParseError) =
    parser.parseError(e)
  let onParseError = if parser.hasParseError():
    x
  else:
    nil
  parser.tokenizer = newTokenizer[Atom](
    inputStream,
    onParseError,
    factory,
    tokstate
  )
  parser.constructTree()
  parser.finishParsing()
