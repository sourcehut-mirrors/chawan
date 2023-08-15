import macros
import options
import sequtils
import streams
import strutils
import tables
import unicode

import htmltokenizer
import parseerror
import tags
import utils/twtstr

import chakasu/charset
import chakasu/decoderstream

# Generics break without exporting macros. Maybe a compiler bug?
export macros

# Heavily inspired by html5ever's TreeSink design.
type
  DOMBuilder*[Handle] = ref object of RootObj
    document*: Handle
    ## Must never be nil.
    finish*: DOMBuilderFinish[Handle]
    ## May be nil.
    restart*: DOMBuilderRestart[Handle]
    ## May be nil.
    parseError*: DOMBuilderParseError[Handle]
    ## May be nil.
    setQuirksMode*: DOMBuilderSetQuirksMode[Handle]
    ## May be nil.
    setCharacterSet*: DOMBuilderSetCharacterSet[Handle]
    ## May be nil.
    elementPopped*: DOMBuilderElementPopped[Handle]
    ## May be nil.
    getTemplateContent*: DOMBuilderGetTemplateContent[Handle]
    ## May be nil. (If nil, templates are treated as regular elements.)
    getParentNode*: DOMBuilderGetParentNode[Handle]
    ## Must never be nil.
    getLocalName*: DOMBuilderGetLocalName[Handle]
    ## Must never be nil.
    getTagType*: DOMBuilderGetTagType[Handle]
    ## May be nil. (If nil, the parser falls back to getLocalName.)
    getNamespace*: DOMBuilderGetNamespace[Handle]
    ## May be nil. (If nil, the parser always uses the HTML namespace.)
    createElement*: DOMBuilderCreateElement[Handle]
    ## Must never be nil.
    createComment*: DOMBuilderCreateComment[Handle]
    ## Must never be nil.
    createDocumentType*: DOMBuilderCreateDocumentType[Handle]
    ## Must never be nil.
    insertBefore*: DOMBuilderInsertBefore[Handle]
    ## Must never be nil.
    insertText*: DOMBuilderInsertText[Handle]
    ## Must never be nil.
    remove*: DOMBuilderRemove[Handle]
    ## Must never be nil.
    addAttrsIfMissing*: DOMBuilderAddAttrsIfMissing[Handle]
    ## May be nil. (If nil, some attributes may not be added to the HTML or
    ## BODY element if more than one of their respecting opening tags exist.)
    setScriptAlreadyStarted*: DOMBuilderSetScriptAlreadyStarted[Handle]
    ## May be nil.
    associateWithForm*: DOMBuilderAssociateWithForm[Handle]
    ## May be nil.
    isSVGIntegrationPoint*: DOMBuilderIsSVGIntegrationPoint[Handle]
    ## May be nil. (If nil, the parser considers no Handle an SVG integration
    ## point.)

  HTML5ParserOpts*[Handle] = object
    isIframeSrcdoc*: bool
    ## Is the document an iframe srcdoc?
    scripting*: bool
    ## Is scripting enabled for this document?
    canReinterpret*: bool
    ## Can we try to parse the document again with a different character set?
    ##
    ## Note: this only works if inputStream is seekable, i.e.
    ## inputStream.setPosition(0) must work correctly.
    ##
    ## Note 2: when canReinterpret is false, confidence is set to certain,
    ## no BOM sniffing is performed and meta charset tags are
    ## disregarded.
    ## Expect this to change in the future. (In particular, this should not
    ## be necessary for ASCII-compatible decoders that have only seen ASCII
    ## characters, i.e. for most <meta charset=...> tags.)
    charsets*: seq[Charset]
    ## Fallback charsets. If empty, UTF-8 is used. In most cases, an empty
    ## sequence or a single-element sequence consisting of a character set
    ## chosen based on the user's locale will suffice.
    ##
    ## The parser goes through fallback charsets in the following order:
    ## * A charset stack is initialized to `charsets`, reversed. This
    ##   means that the first charset specified in `charsets` is on top of
    ##   the stack. (e.g. say `charsets = @[CHARSET_UTF_16_LE, CHARSET_UTF_8]`,
    ##   then utf-16-le is tried before utf-8.)
    ## * BOM sniffing is attempted. If successful, confidence is set to
    ##   certain and the resulting charset is used (i.e. other character
    ##   sets will not be tried for decoding this document.)
    ## * If the charset stack is empty, UTF-8 is pushed on top.
    ## * Attempt to parse the document with the first charset on top of
    ##   the stack.
    ## * If BOM sniffing was unsuccessful, and a <meta charset=...> tag
    ##   is encountered, parsing is restarted with the specified charset.
    ##   No further attempts are made to detect the encoding, and decoder
    ##   errors are signaled by U+FFFD replacement characters.
    ## * Otherwise, each charset on the charset stack is tried until either no
    ##   decoding errors are encountered, or only one charset is left. For
    ##   the last charset, decoder errors are signaled by U+FFFD replacement
    ##   characters.
    ctx*: Option[Handle]
    ## Context element for fragment parsing. When set to some Handle,
    ## the fragment case is used while parsing.

  DOMBuilderFinish*[Handle] =
    proc(builder: DOMBuilder[Handle]) {.nimcall.}
      ## Parsing has finished.

  DOMBuilderRestart*[Handle] =
    proc(builder: DOMBuilder[Handle]) {.nimcall.}
      ## Parsing has been restarted. This is required if charset switching
      ## is enabled; in this case, restart must reset all properties of the
      ## document handle, and remove all of its child nodes.

  DOMBuilderParseError*[Handle] =
    proc(builder: DOMBuilder[Handle], message: ParseError) {.nimcall.}
      ## Parse error. `message` is an error code either specified by the
      ## standard (in this case, message < LAST_SPECIFIED_ERROR) or named
      ## arbitrarily. (At the time of writing, only tokenizer errors have
      ## specified error codes.)

  DOMBuilderSetQuirksMode*[Handle] =
    proc(builder: DOMBuilder[Handle], quirksMode: QuirksMode) {.nimcall.}
      ## Set quirks mode to either QUIRKS or LIMITED_QUIRKS. NO_QUIRKS
      ## is the default and is therefore never used here.

  DOMBuilderSetCharacterSet*[Handle] =
    proc(builder: DOMBuilder[Handle], charset: Charset) {.nimcall.}
      ## Set the charset used in the current parsing attempt.
      ## Note that this is called even for all attempts, i.e. at least once
      ## for every parse.

  DOMBuilderElementPopped*[Handle] =
    proc(builder: DOMBuilder[Handle], element: Handle) {.nimcall.}
      ## Called when an element is popped from the stack of open elements
      ## (i.e. when it has been closed.)

  DOMBuilderGetTemplateContent*[Handle] =
    proc(builder: DOMBuilder[Handle], handle: Handle): Handle {.nimcall.}
      ## Retrieve a handle to the template element's contents.
      ## Note: this function must never return nil.

  DOMBuilderGetParentNode*[Handle] =
    proc(builder: DOMBuilder[Handle], handle: Handle): Option[Handle]
        {.nimcall.}
      ## Retrieve a handle to the parent node.
      ## May return none(Handle) if no parent node exists.

  DOMBuilderGetTagType*[Handle] =
    proc(builder: DOMBuilder[Handle], handle: Handle): TagType {.nimcall.}
      ## Retrieve the tag type of element.

  DOMBuilderGetLocalName*[Handle] =
    proc(builder: DOMBuilder[Handle], handle: Handle): string {.nimcall.}
      ## Retrieve the local name of element. (This is tagName(getTagType),
      ## unless the tag is unknown.

  DOMBuilderGetNamespace*[Handle] =
    proc(builder: DOMBuilder[Handle], handle: Handle): Namespace {.nimcall.}
      ## Retrieve the namespace of element.

  DOMBuilderCreateElement*[Handle] =
    proc(builder: DOMBuilder[Handle], localName: string, namespace: Namespace,
        tagType: TagType, attrs: Table[string, string]): Handle {.nimcall.}
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

  DOMBuilderCreateComment*[Handle] =
    proc(builder: DOMBuilder[Handle], text: string): Handle {.nimcall.}
      ## Create a new comment node.

  DOMBuilderInsertText*[Handle] =
    proc(builder: DOMBuilder[Handle], parent: Handle, text: string,
        before: Handle) {.nimcall.}
      ## Insert a text node at the specified location with contents
      ## `text`. If the specified location has a previous sibling that is
      ## a text node, no new text node should be created, but instead `text`
      ## should be appended to the previous sibling's character data.

  DOMBuilderCreateDocumentType*[Handle] =
    proc(builder: DOMBuilder[Handle], name, publicId, systemId: string): Handle
        {.nimcall.}
    ## Create a new document type node.

  DOMBuilderInsertBefore*[Handle] =
    proc(builder: DOMBuilder[Handle], parent, child, before: Handle)
        {.nimcall.}
      ## Insert node `child` before the node called `before`.
      ##
      ## If `before` is nil, `child` is expected to be appended to `parent`'s
      ## node list.
      ##
      ## If `child` is a text, and its previous sibling after insertion is a
      ## text as well, then they should be merged. `before` is never a
      ## text node (and thus never has to be merged).
      ##
      ## Note: parent may either be an Element or a Document node.

  DOMBuilderRemove*[Handle] =
    proc(builder: DOMBuilder[Handle], child: Handle) {.nimcall.}
      ## Remove `child` from its parent node, and do nothing if `child`
      ## has no parent node.

  DOMBuilderReparent*[Handle] =
    proc(builder: DOMBuilder[Handle], child, newParent: Handle) {.nimcall.}
      ## Remove `child` from its parent node, and append it to `newParent`.
      ## In terms of DOM operations, this should be equivalent to calling
      ## `child.remove()`, followed by `newParent.append(child)`.

  DOMBuilderAddAttrsIfMissing*[Handle] =
    proc(builder: DOMBuilder[Handle], element: Handle,
        attrs: Table[string, string]) {.nimcall.}
      ## Add the attributes in `attrs` to the element node `element`.
      ## At the time of writing, called for HTML and BODY only. (This may
      ## change in the future.)
      ## An example implementation:
      ## ```nim
      ## for k, v in attrs:
      ##   if k notin element.attrs:
      ##     element.attrs[k] = v
      ## ```

  DOMBuilderSetScriptAlreadyStarted*[Handle] =
    proc(builder: DOMBuilder[Handle], script: Handle) {.nimcall.}
      ## Set the "already started" flag for the script element.
      ##
      ## Note: this flag is not togglable, so this callback should just set it
      ## to true.

  DOMBuilderAssociateWithForm*[Handle] =
    proc(builder: DOMBuilder[Handle], element, form, intendedParent: Handle)
        {.nimcall.}
      ## Called after createElement. Attempts to set form for form-associated
      ## elements.
      ##
      ## Note: the DOM builder is responsible for checking whether the
      ## intended parent and the form element are in the same tree.

  DOMBuilderIsSVGIntegrationPoint*[Handle] =
    proc(builder: DOMBuilder[Handle], element: Handle): bool {.nimcall.}
      ## Check if element is an SVG integration point.

type
  CharsetConfidence = enum
    CONFIDENCE_TENTATIVE, CONFIDENCE_CERTAIN, CONFIDENCE_IRRELEVANT

  HTML5Parser[Handle] = object
    quirksMode: QuirksMode
    dombuilder: DOMBuilder[Handle]
    opts: HTML5ParserOpts[Handle]
    ctx: Option[Handle]
    needsreinterpret: bool
    charset: Charset
    confidence: CharsetConfidence
    openElements: seq[Handle]
    insertionMode: InsertionMode
    oldInsertionMode: InsertionMode
    templateModes: seq[InsertionMode]
    head: Option[Handle]
    tokenizer: Tokenizer
    form: Option[Handle]
    fosterParenting: bool
    # Handle is an element. nil => marker
    activeFormatting: seq[(Option[Handle], Token)]
    framesetok: bool
    ignoreLF: bool
    pendingTableChars: string
    pendingTableCharsWhitespace: bool

  AdjustedInsertionLocation[Handle] = tuple[inside, before: Handle]

# 13.2.4.1
  InsertionMode = enum
    INITIAL, BEFORE_HTML, BEFORE_HEAD, IN_HEAD, IN_HEAD_NOSCRIPT, AFTER_HEAD,
    IN_BODY, TEXT, IN_TABLE, IN_TABLE_TEXT, IN_CAPTION, IN_COLUMN_GROUP,
    IN_TABLE_BODY, IN_ROW, IN_CELL, IN_SELECT, IN_SELECT_IN_TABLE, IN_TEMPLATE,
    AFTER_BODY, IN_FRAMESET, AFTER_FRAMESET, AFTER_AFTER_BODY,
    AFTER_AFTER_FRAMESET

# DOMBuilder interface functions
proc finish[Handle](parser: HTML5Parser[Handle]) =
  if parser.dombuilder.finish != nil:
    parser.dombuilder.finish(parser.dombuilder)

proc restart[Handle](parser: HTML5Parser[Handle]) =
  if parser.dombuilder.restart != nil:
    parser.dombuilder.restart(parser.dombuilder)

proc parseError(parser: HTML5Parser, e: ParseError) =
  if parser.dombuilder.parseError != nil:
    parser.dombuilder.parseError(parser.dombuilder, e)

proc setQuirksMode[Handle](parser: var HTML5Parser[Handle], mode: QuirksMode) =
  parser.quirksMode = mode
  if parser.dombuilder.setQuirksMode != nil:
    parser.dombuilder.setQuirksMode(parser.dombuilder, mode)

proc setCharacterSet[Handle](parser: var HTML5Parser[Handle],
    charset: Charset) =
  if parser.dombuilder.setCharacterSet != nil:
    parser.dombuilder.setCharacterSet(parser.dombuilder, charset)

func document[Handle](parser: HTML5Parser[Handle]): Handle {.inline.} =
  return parser.dombuilder.document

func getTemplateContent[Handle](parser: HTML5Parser[Handle],
    handle: Handle): Handle =
  let dombuilder = parser.dombuilder
  return dombuilder.getTemplateContent(dombuilder, handle)

func getParentNode[Handle](parser: HTML5Parser[Handle],
    handle: Handle): Option[Handle] =
  let dombuilder = parser.dombuilder
  return dombuilder.getParentNode(dombuilder, handle)

func getLocalName[Handle](parser: HTML5Parser[Handle], handle: Handle):
    string =
  return parser.dombuilder.getLocalName(parser.dombuilder, handle)

func getTagType[Handle](parser: HTML5Parser[Handle], handle: Handle): TagType =
  if parser.dombuilder.getTagType != nil:
    return parser.dombuilder.getTagType(parser.dombuilder, handle)
  return tagType(parser.getLocalName(handle))

func getNamespace[Handle](parser: HTML5Parser[Handle], handle: Handle):
    Namespace =
  if parser.dombuilder.getNamespace != nil:
    return parser.dombuilder.getNamespace(parser.dombuilder, handle)
  return Namespace.HTML

func createElement[Handle](parser: HTML5Parser[Handle], localName: string,
    namespace: Namespace, tagType: TagType, attrs: Table[string, string]):
    Handle =
  return parser.dombuilder.createElement(parser.dombuilder, localName,
    namespace, tagType, attrs)

func createElement[Handle](parser: HTML5Parser[Handle], tagType: TagType,
    namespace: Namespace): Handle =
  return parser.createElement(tagName(tagType), namespace, tagType,
    Table[string, string]())

func createComment[Handle](parser: HTML5Parser[Handle], text: string): Handle =
  let dombuilder = parser.dombuilder
  return dombuilder.createComment(dombuilder, text)

proc createDocumentType[Handle](parser: HTML5Parser[Handle], name, publicId,
    systemId: string): Handle =
  let dombuilder = parser.dombuilder
  return dombuilder.createDocumentType(dombuilder, name, publicId, systemId)

proc insertBefore[Handle](parser: HTML5Parser[Handle],
    parent, node, before: Handle) =
  let dombuilder = parser.dombuilder
  dombuilder.insertBefore(dombuilder, parent, node, before)

proc insertText[Handle](parser: HTML5Parser[Handle], parent: Handle,
    text: string, before: Handle) =
  let dombuilder = parser.dombuilder
  dombuilder.insertText(dombuilder, parent, text, before)

proc remove[Handle](parser: HTML5Parser[Handle], child: Handle) =
  let dombuilder = parser.dombuilder
  dombuilder.remove(dombuilder, child)

proc addAttrsIfMissing[Handle](parser: HTML5Parser, element: Handle,
    attrs: Table[string, string]) =
  let dombuilder = parser.dombuilder
  if dombuilder.addAttrsIfMissing != nil:
    dombuilder.addAttrsIfMissing(dombuilder, element, attrs)

proc setScriptAlreadyStarted[Handle](parser: HTML5Parser, script: Handle) =
  let dombuilder = parser.dombuilder
  if dombuilder.setScriptAlreadyStarted != nil:
    dombuilder.setScriptAlreadyStarted(dombuilder, script)

proc associateWithForm[Handle](parser: HTML5Parser, element, form,
    intendedParent: Handle) =
  let dombuilder = parser.dombuilder
  if dombuilder.associateWithForm != nil:
    dombuilder.associateWithForm(dombuilder, element, form, intendedParent)

func isSVGIntegrationPoint[Handle](parser: HTML5Parser,
    element: Handle): bool =
  let dombuilder = parser.dombuilder
  if dombuilder.isSVGIntegrationPoint != nil:
    return dombuilder.isSVGIntegrationPoint(dombuilder, element)
  return false

# Parser
func hasParseError(parser: HTML5Parser): bool =
  return parser.dombuilder.parseError != nil

func tagNameEquals[Handle](parser: HTML5Parser, handle: Handle,
    token: Token): bool =
  let tagType = parser.getTagType(handle)
  if tagType != TAG_UNKNOWN:
    return tagType == token.tagtype
  let localName = parser.getLocalName(handle)
  return localName == token.tagname

func tagNameEquals[Handle](parser: HTML5Parser, a, b: Handle): bool =
  let tagType = parser.getTagType(a)
  if tagType != TAG_UNKNOWN:
    return tagType == parser.getTagType(b)
  return parser.getLocalName(a) == parser.getLocalName(b)

func fragment(parser: HTML5Parser): bool =
  return parser.ctx.isSome

# https://html.spec.whatwg.org/multipage/parsing.html#reset-the-insertion-mode-appropriately
proc resetInsertionMode(parser: var HTML5Parser) =
  template switch_insertion_mode_and_return(mode: InsertionMode) =
    parser.insertionMode = mode
    return
  for i in countdown(parser.openElements.high, 0):
    var node = parser.openElements[i]
    let last = i == 0
    if parser.fragment:
      node = parser.ctx.get
    let tagType = parser.getTagType(node)
    if tagType == TAG_SELECT:
      if not last:
        for j in countdown(parser.openElements.high, 1):
          let ancestor = parser.openElements[j]
          case parser.getTagType(ancestor)
          of TAG_TEMPLATE: break
          of TAG_TABLE: switch_insertion_mode_and_return IN_SELECT_IN_TABLE
          else: discard
      switch_insertion_mode_and_return IN_SELECT
    case tagType
    of TAG_TD, TAG_TH:
      if not last:
        switch_insertion_mode_and_return IN_CELL
    of TAG_TR: switch_insertion_mode_and_return IN_ROW
    of TAG_TBODY, TAG_THEAD, TAG_TFOOT:
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

func currentNode[Handle](parser: HTML5Parser[Handle]): Handle =
  return parser.openElements[^1]

func adjustedCurrentNode[Handle](parser: HTML5Parser[Handle]): Handle =
  if parser.fragment:
    parser.ctx.get
  else:
    parser.currentNode

func lastElementOfTag[Handle](parser: HTML5Parser[Handle],
    tagType: TagType): tuple[element: Option[Handle], pos: int] =
  for i in countdown(parser.openElements.high, 0):
    if parser.getTagType(parser.openElements[i]) == tagType:
      return (some(parser.openElements[i]), i)
  return (none(Handle), -1)

template last_child_of[Handle](n: Handle): AdjustedInsertionLocation[Handle] =
  (n, nil)

# https://html.spec.whatwg.org/multipage/#appropriate-place-for-inserting-a-node
func appropriatePlaceForInsert[Handle](parser: HTML5Parser[Handle],
    target: Handle): AdjustedInsertionLocation[Handle] =
  assert parser.getTagType(parser.openElements[0]) == TAG_HTML
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
      return last_child_of(parser.openElements[0])
    let parentNode = parser.getParentNode(lastTable.element.get)
    if parentNode.isSome:
      return (parentNode.get, lastTable.element.get)
    let previousElement = parser.openElements[lastTable.pos - 1]
    result = last_child_of(previousElement)
  else:
    result = last_child_of(target)
  if parser.getTagType(result.inside) == TAG_TEMPLATE and
      parser.dombuilder.getTemplateContent != nil:
    result = (parser.getTemplateContent(result.inside), nil)

func appropriatePlaceForInsert[Handle](parser: HTML5Parser[Handle]):
    AdjustedInsertionLocation[Handle] =
  parser.appropriatePlaceForInsert(parser.currentNode)

func hasElement[Handle](parser: HTML5Parser[Handle], tag: TagType): bool =
  for element in parser.openElements:
    if parser.getTagType(element) == tag:
      return true
  return false

func hasElement[Handle](parser: HTML5Parser[Handle], tags: set[TagType]): bool =
  for element in parser.openElements:
    if parser.getTagType(element) in tags:
      return true
  return false

func hasElementInSpecificScope[Handle](parser: HTML5Parser[Handle],
    target: Handle, list: set[TagType]): bool =
  for i in countdown(parser.openElements.high, 0):
    if parser.openElements[i] == target:
      return true
    if parser.getTagType(parser.openElements[i]) in list:
      return false
  assert false

func hasElementInSpecificScope[Handle](parser: HTML5Parser[Handle],
    target: TagType, list: set[TagType]): bool =
  for i in countdown(parser.openElements.high, 0):
    let tagType = parser.getTagType(parser.openElements[i])
    if tagType == target:
      return true
    if tagType in list:
      return false
  assert false

func hasElementInSpecificScope[Handle](parser: HTML5Parser[Handle],
    target: set[TagType], list: set[TagType]): bool =
  for i in countdown(parser.openElements.high, 0):
    let tagType = parser.getTagType(parser.openElements[i])
    if tagType in target:
      return true
    if tagType in list:
      return false
  assert false

const Scope = {
  TAG_APPLET, TAG_CAPTION, TAG_HTML, TAG_TABLE, TAG_TD, TAG_TH, TAG_MARQUEE,
  TAG_OBJECT, TAG_TEMPLATE #TODO SVG
  # Note: MathML is not implemented
}

func hasElementInScope[Handle](parser: HTML5Parser[Handle],
    target: TagType): bool =
  return parser.hasElementInSpecificScope(target, Scope)

func hasElementInScope[Handle](parser: HTML5Parser[Handle],
    target: set[TagType]): bool =
  return parser.hasElementInSpecificScope(target, Scope)

func hasElementInScope[Handle](parser: HTML5Parser[Handle],
    target: Handle): bool =
  return parser.hasElementInSpecificScope(target, Scope)

func hasElementInListItemScope[Handle](parser: HTML5Parser[Handle],
    target: TagType): bool =
  const ListItemScope = Scope + {TAG_OL, TAG_UL}
  return parser.hasElementInSpecificScope(target, ListItemScope)

func hasElementInButtonScope[Handle](parser: HTML5Parser[Handle],
    target: TagType): bool =
  const ButtonScope = Scope + {TAG_BUTTON}
  return parser.hasElementInSpecificScope(target, ButtonScope)

const TableScope = {TAG_HTML, TAG_TABLE, TAG_TEMPLATE}
func hasElementInTableScope[Handle](parser: HTML5Parser[Handle],
    target: TagType): bool =
  return parser.hasElementInSpecificScope(target, TableScope)

func hasElementInTableScope[Handle](parser: HTML5Parser[Handle],
    target: set[TagType]): bool =
  return parser.hasElementInSpecificScope(target, TableScope)

func hasElementInSelectScope[Handle](parser: HTML5Parser[Handle],
    target: TagType): bool =
  for i in countdown(parser.openElements.high, 0):
    let tagType = parser.getTagType(parser.openElements[i])
    if tagType == target:
      return true
    if tagType notin {TAG_OPTION, TAG_OPTGROUP}:
      return false
  assert false

func createElement[Handle](parser: HTML5Parser[Handle], token: Token,
    namespace: Namespace, intendedParent: Handle): Handle =
  #TODO custom elements
  let localName = token.tagname
  let element = parser.createElement(localName, namespace, token.tagtype,
    token.attrs)
  if token.tagtype in FormAssociatedElements and parser.form.isSome and
      not parser.hasElement(TAG_TEMPLATE) and
      (token.tagtype notin ListedElements or "form" notin token.attrs):
    parser.associateWithForm(element, parser.form.get, intendedParent)
  return element

proc pushElement[Handle](parser: var HTML5Parser[Handle], node: Handle) =
  parser.openElements.add(node)
  let node = parser.adjustedCurrentNode()
  parser.tokenizer.hasnonhtml = parser.getNamespace(node) != Namespace.HTML

proc popElement[Handle](parser: var HTML5Parser[Handle]): Handle =
  result = parser.openElements.pop()
  if parser.dombuilder.elementPopped != nil:
    parser.dombuilder.elementPopped(parser.dombuilder, result)
  if parser.openElements.len == 0:
    parser.tokenizer.hasnonhtml = false
  else:
    let node = parser.adjustedCurrentNode()
    parser.tokenizer.hasnonhtml = parser.getNamespace(node) != Namespace.HTML

template pop_current_node = discard parser.popElement()

proc insert[Handle](parser: HTML5Parser[Handle],
    location: AdjustedInsertionLocation[Handle], node: Handle) =
  parser.insertBefore(location.inside, node, location.before)

proc append[Handle](parser: HTML5Parser[Handle], parent, node: Handle) =
  parser.insertBefore(parent, node, nil)

proc insertForeignElement[Handle](parser: var HTML5Parser[Handle], token: Token,
    namespace: Namespace): Handle =
  let location = parser.appropriatePlaceForInsert()
  let element = parser.createElement(token, namespace, location.inside)
  #TODO custom elements
  parser.insert(location, element)
  parser.pushElement(element)
  return element

proc insertHTMLElement[Handle](parser: var HTML5Parser[Handle],
    token: Token): Handle =
  return parser.insertForeignElement(token, Namespace.HTML)

proc adjustSVGAttributes(token: Token) =
  const adjusted = {
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
  }.toTable()
  var todo: seq[string]
  for k in token.attrs.keys:
    if k in adjusted:
      todo.add(k)
  for s in todo:
    token.attrs[adjusted[s]] = token.attrs[s]

template insert_character_impl(parser: var HTML5Parser, data: typed) =
  let location = parser.appropriatePlaceForInsert()
  if location.inside.nodeType == DOCUMENT_NODE:
    return
  insertText(parser, location.inside, $data, location.before)

proc insertCharacter(parser: var HTML5Parser, data: string) =
  insert_character_impl(parser, data)

proc insertCharacter(parser: var HTML5Parser, data: char) =
  insert_character_impl(parser, data)

proc insertCharacter(parser: var HTML5Parser, data: Rune) =
  insert_character_impl(parser, data)

proc insertComment[Handle](parser: var HTML5Parser[Handle], token: Token,
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
  if token.quirks: return true
  if token.name.isnone or token.name.get != "html": return true
  if token.sysid.issome:
    if token.sysid.get == "http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd":
      return true
  if token.pubid.issome:
    if token.pubid.get in PublicIdentifierEquals:
      return true
    for id in PublicIdentifierStartsWith:
      if token.pubid.get.startsWithNoCase(id):
        return true
    if token.sysid.isnone:
      for id in SystemIdentifierMissingAndPublicIdentifierStartsWith:
        if token.pubid.get.startsWithNoCase(id):
          return true
  return false

func limitedQuirksConditions(token: Token): bool =
  if token.pubid.isnone: return false
  for id in PublicIdentifierStartsWithLimited:
    if token.pubid.get.startsWithNoCase(id):
      return true
  if token.sysid.isnone: return false
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
proc popElementsIncl(parser: var HTML5Parser, tag: TagType) =
  while parser.getTagType(parser.popElement()) != tag:
    discard

proc popElementsIncl(parser: var HTML5Parser, tags: set[TagType]) =
  while parser.getTagType(parser.popElement()) notin tags:
    discard

# https://html.spec.whatwg.org/multipage/parsing.html#closing-elements-that-have-implied-end-tags
proc generateImpliedEndTags(parser: var HTML5Parser) =
  const tags = {TAG_DD, TAG_DT, TAG_LI, TAG_OPTGROUP, TAG_OPTION, TAG_P,
                TAG_RB, TAG_RP, TAG_RT, TAG_RTC}
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
  const tags = {TAG_CAPTION, TAG_COLGROUP, TAG_DD, TAG_DT, TAG_LI,
                TAG_OPTGROUP, TAG_OPTION, TAG_P, TAG_RB, TAG_RP, TAG_RT,
                TAG_RTC, TAG_TBODY, TAG_TD, TAG_TFOOT, TAG_TH, TAG_THEAD,
                TAG_TR}
  while parser.getTagType(parser.currentNode) in tags:
    discard parser.popElement()

# https://html.spec.whatwg.org/multipage/parsing.html#push-onto-the-list-of-active-formatting-elements
proc pushOntoActiveFormatting[Handle](parser: var HTML5Parser[Handle],
    element: Handle, token: Token) =
  var count = 0
  for i in countdown(parser.activeFormatting.high, 0):
    let it = parser.activeFormatting[i]
    if it[0].isNone: break
    if not parser.tagNameEquals(it[0].get, element):
      continue
    if parser.getNamespace(it[0].get) != parser.getNamespace(element):
      continue
    var fail = false
    for k, v in it[1].attrs:
      if k notin token.attrs:
        fail = true
        break
      if v != token.attrs[k]:
        fail = true
        break
    if fail: continue
    for k, v in token.attrs:
      if k notin it[1].attrs:
        fail = true
        break
    if fail: continue
    inc count
    if count == 3:
      parser.activeFormatting.delete(i)
      break
  parser.activeFormatting.add((some(element), token))

proc reconstructActiveFormatting[Handle](parser: var HTML5Parser[Handle]) =
  type State = enum
    REWIND, ADVANCE, CREATE
  if parser.activeFormatting.len == 0:
    return
  if parser.activeFormatting[^1][0].isNone:
    return
  let tagType = parser.getTagType(parser.activeFormatting[^1][0].get)
  if parser.hasElement(tagType):
    return
  var i = parser.activeFormatting.high
  template entry: Option[Handle] = (parser.activeFormatting[i][0])
  var state = REWIND
  while true:
    {.computedGoto.}
    case state
    of REWIND:
      if i == 0:
        state = CREATE
        continue
      dec i
      if entry.isSome:
        let tagType = parser.getTagType(entry.get)
        if not parser.hasElement(tagType):
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

func isHTMLIntegrationPoint[Handle](parser: HTML5Parser[Handle],
    element: Handle): bool =
  return parser.isSVGIntegrationPoint(element) # (NOTE MathML not implemented)

func extractEncFromMeta(s: string): Charset =
  var i = 0
  while true: # Loop:
    var j = 0
    while i < s.len:
      template check(c: static char) =
        if s[i] in {c, c.toUpperAscii()}: inc j
        else: j = 0
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
    if j < 7: return CHARSET_UNKNOWN
    while i < s.len and s[i] in AsciiWhitespace: inc i
    if i >= s.len or s[i] != '=': continue
    while i < s.len and s[i] in AsciiWhitespace: inc i
    break
  inc i
  if i >= s.len: return CHARSET_UNKNOWN
  if s[i] in {'"', '\''}:
    let s2 = s.substr(i + 1).until(s[i])
    if s2.len == 0 or s2[^1] != s[i]:
      return CHARSET_UNKNOWN
    return getCharset(s2)
  return getCharset(s.substr(i).until({';', ' '}))

proc changeEncoding(parser: var HTML5Parser, cs: Charset) =
  if parser.charset in {CHARSET_UTF_16_LE, CHARSET_UTF_16_BE}:
    parser.confidence = CONFIDENCE_CERTAIN
    return
  parser.confidence = CONFIDENCE_CERTAIN
  if cs == parser.charset:
    return
  if cs == CHARSET_X_USER_DEFINED:
    parser.charset = CHARSET_WINDOWS_1252
  else:
    parser.charset = cs
  parser.needsreinterpret = true

proc parseErrorByTokenType(parser: var HTML5Parser, tokenType: TokenType) =
  case tokenType
  of START_TAG:
    parser.parseError UNEXPECTED_START_TAG
  of END_TAG:
    parser.parseError UNEXPECTED_END_TAG
  of EOF:
    parser.parseError UNEXPECTED_EOF
  else:
    doAssert false

proc adoptionAgencyAlgorithm[Handle](parser: var HTML5Parser[Handle],
    token: Token): bool =
  template parse_error(e: ParseError) =
    parser.parseError(e)
  if parser.tagNameEquals(parser.currentNode, token):
    var fail = true
    for it in parser.activeFormatting:
      if it[0].isSome and it[0].get == parser.currentNode:
        fail = false
    if fail:
      pop_current_node
      return false
  var i = 0
  while true:
    if i >= 8: return false
    inc i
    if parser.activeFormatting.len == 0: return true
    var formatting: Handle
    var formattingIndex: int
    for j in countdown(parser.activeFormatting.high, 0):
      let element = parser.activeFormatting[j][0]
      if element.isNone:
        return true
      if parser.tagNameEquals(parser.currentNode, token):
        formatting = element.get
        formattingIndex = j
        break
      if j == 0:
        return true
    let stackIndex = parser.openElements.find(formatting)
    if stackIndex < 0:
      parse_error ELEMENT_NOT_IN_OPEN_ELEMENTS
      parser.activeFormatting.delete(formattingIndex)
      return false
    if not parser.hasElementInScope(formatting):
      parse_error ELEMENT_NOT_IN_SCOPE
      return false
    if formatting != parser.currentNode:
      parse_error ELEMENT_NOT_CURRENT_NODE
    var furthestBlockIndex = -1
    for j in countdown(parser.openElements.high, 0):
      if parser.openElements[j] == formatting:
        break
      if parser.getTagType(parser.openElements[j]) in SpecialElements:
        furthestBlockIndex = j
        break
    if furthestBlockIndex == -1:
      while parser.popElement() != formatting: discard
      parser.activeFormatting.delete(formattingIndex)
      return false
    var furthestBlock = parser.openElements[furthestBlockIndex]
    let commonAncestor = parser.openElements[stackIndex - 1]
    var bookmark = formattingIndex
    var node = furthestBlock
    var aboveNode = parser.openElements[furthestBlockIndex - 1]
    var lastNode = furthestBlock
    var j = 0
    while true:
      inc j
      node = aboveNode
      let nodeStackIndex = parser.openElements.find(node)
      if node == formatting: break
      var nodeFormattingIndex = -1
      for i in countdown(parser.activeFormatting.high, 0):
        if parser.activeFormatting[i][0].isSome and
            parser.activeFormatting[i][0].get == node:
          nodeFormattingIndex = i
          break
      if j > 3 and nodeFormattingIndex >= 0:
        parser.activeFormatting.delete(nodeFormattingIndex)
        if nodeFormattingIndex < bookmark:
          dec bookmark # a previous node got deleted, so decrease bookmark by one
      if nodeFormattingIndex < 0:
        aboveNode = parser.openElements[nodeStackIndex - 1]
        parser.openElements.delete(nodeStackIndex)
        if nodeStackIndex < furthestBlockIndex:
          dec furthestBlockIndex
          furthestBlock = parser.openElements[furthestBlockIndex]
        continue
      let tok = parser.activeFormatting[nodeFormattingIndex][1]
      let element = parser.createElement(tok, Namespace.HTML, commonAncestor)
      parser.activeFormatting[nodeFormattingIndex] = (some(element), tok)
      parser.openElements[nodeStackIndex] = element
      aboveNode = parser.openElements[nodeStackIndex - 1]
      node = element
      if lastNode == furthestBlock:
        bookmark = nodeFormattingIndex + 1
      parser.append(node, lastNode)
      lastNode = node
    let location = parser.appropriatePlaceForInsert(commonAncestor)
    parser.insertBefore(location.inside, lastNode, location.before)
    let token = parser.activeFormatting[formattingIndex][1]
    let element = parser.createElement(token, Namespace.HTML, furthestBlock)
    var tomove: seq[Handle]
    j = furthestBlock.childList.high
    while j >= 0:
      let child = furthestBlock.childList[j]
      tomove.add(child)
      parser.remove(child)
      dec j
    for child in tomove:
      parser.append(element, child)
    parser.append(furthestBlock, element)
    parser.activeFormatting.insert((some(element), token), bookmark)
    parser.activeFormatting.delete(formattingIndex)
    parser.openElements.insert(element, furthestBlockIndex)
    parser.openElements.delete(stackIndex)

proc closeP(parser: var HTML5Parser) =
  parser.generateImpliedEndTags(TAG_P)
  if parser.getTagType(parser.currentNode) != TAG_P:
    parser.parseError(MISMATCHED_TAGS)
  while parser.getTagType(parser.popElement()) != TAG_P:
    discard

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
      of nnkCharLit:
        ofBranches[CHARACTER_ASCII].ofBranches.add((@[pattern], action))
        ofBranches[CHARACTER_ASCII].painted = true
      of nnkCurly:
        case pattern[0].kind
        of nnkCharLit:
          ofBranches[CHARACTER_ASCII].ofBranches.add((@[pattern], action))
          ofBranches[CHARACTER_ASCII].painted = true
        else: error "Unsupported curly of kind " & $pattern[0].kind
      of nnkStrLit:
        var tempTokenizer = newTokenizer(pattern.strVal)
        for token in tempTokenizer.tokenize:
          let tt = int(token.tagtype)
          case token.t
          of START_TAG, END_TAG:
            var found = false
            for i in 0..ofBranches[token.t].ofBranches.high:
              if ofBranches[token.t].ofBranches[i][1] == action:
                found = true
                ofBranches[token.t].ofBranches[i][0].add((quote do: TagType(`tt`)))
                ofBranches[token.t].painted = true
                break
            if not found:
              ofBranches[token.t].ofBranches.add((@[(quote do: TagType(`tt`))], action))
              ofBranches[token.t].painted = true
          else:
            error pattern.strVal & ": Unsupported token " & $token &
              " of kind " & $token.t
          break
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
    of CHARACTER:
      return quote do: token.r
    of CHARACTER_ASCII:
      return quote do: token.c
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

proc processInHTMLContent[Handle](parser: var HTML5Parser[Handle],
    token: Token, insertionMode: InsertionMode) =
  template pop_all_nodes =
    while parser.openElements.len > 1: pop_current_node

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
      AsciiWhitespace => (block: discard)
      TokenType.COMMENT => (block:
        parser.insertComment(token, last_child_of(parser.document))
      )
      TokenType.DOCTYPE => (block:
        if token.name.isNone or
            token.name.get != "html" or token.pubid.isSome or
            (token.sysid.isSome and token.sysid.get != "about:legacy-compat"):
          parse_error INVALID_DOCTYPE
        let doctype = parser.createDocumentType(token.name.get(""),
          token.pubid.get(""), token.sysid.get(""))
        parser.append(parser.document, doctype)
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
        parser.insertComment(token, last_child_of(parser.document))
      )
      AsciiWhitespace => (block: discard)
      "<html>" => (block:
        let element = parser.createElement(token, Namespace.HTML,
          parser.document)
        parser.append(parser.document, element)
        parser.pushElement(element)
        parser.insertionMode = BEFORE_HEAD
      )
      ("</head>", "</body>", "</html>", "</br>") => (block: anything_else)
      TokenType.END_TAG => (block: parse_error UNEXPECTED_END_TAG)
      other => (block:
        let element = parser.createElement(TAG_HTML, Namespace.HTML)
        parser.append(parser.document, element)
        parser.pushElement(element)
        parser.insertionMode = BEFORE_HEAD
        reprocess token
      )

  of BEFORE_HEAD:
    match token:
      AsciiWhitespace => (block: discard)
      TokenType.COMMENT => (block: parser.insertComment(token))
      TokenType.DOCTYPE => (block: parse_error UNEXPECTED_DOCTYPE)
      "<html>" => (block: parser.processInHTMLContent(token, IN_BODY))
      "<head>" => (block:
        parser.head = some(parser.insertHTMLElement(token))
        parser.insertionMode = IN_HEAD
      )
      ("</head>", "</body>", "</html>", "</br>") => (block: anything_else)
      TokenType.END_TAG => (block: parse_error UNEXPECTED_END_TAG)
      other => (block:
        let head = Token(t: START_TAG, tagtype: TAG_HEAD)
        parser.head = some(parser.insertHTMLElement(head))
        parser.insertionMode = IN_HEAD
        reprocess token
      )

  of IN_HEAD:
    match token:
      AsciiWhitespace => (block: parser.insertCharacter(token.c))
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
        if parser.confidence == CONFIDENCE_TENTATIVE:
          let cs = getCharset(token.attrs.getOrDefault("charset", ""))
          if cs != CHARSET_UNKNOWN:
            parser.changeEncoding(cs)
          elif "http-equiv" in token.attrs:
            if token.attrs["http-equiv"].equalsIgnoreCase("Content-Type") and
                "content" in token.attrs:
              let cs = extractEncFromMeta(token.attrs["content"])
              if cs != CHARSET_UNKNOWN:
                parser.changeEncoding(cs)
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
        parser.pushElement(element)
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
      (AsciiWhitespace,
         TokenType.COMMENT,
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
      AsciiWhitespace => (block: parser.insertCharacter(token.c))
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
        parser.pushElement(parser.head.get)
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
        discard parser.insertHTMLElement(Token(t: START_TAG, tagtype: TAG_BODY))
        parser.insertionMode = IN_BODY
        reprocess token
      )

  of IN_BODY:
    template any_other_start_tag() =
      parser.reconstructActiveFormatting()
      discard parser.insertHTMLElement(token)

    template any_other_end_tag() =
      for i in countdown(parser.openElements.high, 0):
        let node = parser.openElements[i]
        if parser.tagNameEquals(node, token):
          parser.generateImpliedEndTags(token.tagtype)
          if node != parser.currentNode:
            parse_error ELEMENT_NOT_CURRENT_NODE
          while parser.popElement() != node:
            discard
          break
        elif parser.getTagType(node) in SpecialElements:
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
      '\0' => (block: parse_error UNEXPECTED_NULL)
      AsciiWhitespace => (block:
        parser.reconstructActiveFormatting()
        parser.insertCharacter(token.c)
      )
      TokenType.CHARACTER_ASCII => (block:
        parser.reconstructActiveFormatting()
        parser.insertCharacter(token.c)
        parser.framesetOk = false
      )
      TokenType.CHARACTER => (block:
        parser.reconstructActiveFormatting()
        parser.insertCharacter(token.r)
        parser.framesetOk = false
      )
      TokenType.COMMENT => (block: parser.insertComment(token))
      TokenType.DOCTYPE => (block: parse_error UNEXPECTED_DOCTYPE)
      "<html>" => (block:
        parse_error UNEXPECTED_START_TAG
        if parser.hasElement(TAG_TEMPLATE):
          discard
        else:
          parser.addAttrsIfMissing(parser.openElements[0], token.attrs)
      )
      ("<base>", "<basefont>", "<bgsound>", "<link>", "<meta>", "<noframes>",
        "<script>", "<style>", "<template>", "<title>",
         "</template>") => (block: parser.processInHTMLContent(token, IN_HEAD))
      "<body>" => (block:
        parse_error UNEXPECTED_START_TAG
        if parser.openElements.len == 1 or
            parser.getTagType(parser.openElements[1]) != TAG_BODY or
            parser.hasElement(TAG_TEMPLATE):
          discard
        else:
          parser.framesetOk = false
          parser.addAttrsIfMissing(parser.openElements[1], token.attrs)
      )
      "<frameset>" => (block:
        parse_error UNEXPECTED_START_TAG
        if parser.openElements.len == 1 or
            parser.getTagType(parser.openElements[1]) != TAG_BODY or
            not parser.framesetOk:
          discard
        else:
          parser.remove(parser.openElements[1])
          pop_all_nodes
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
          let node = parser.openElements[i]
          let tagType = parser.getTagType(node)
          case tagType
          of TAG_LI:
            parser.generateImpliedEndTags(TAG_LI)
            parse_error_if_mismatch TAG_LI
            parser.popElementsIncl(TAG_LI)
            break
          of SpecialElements - {TAG_ADDRESS, TAG_DIV, TAG_P, TAG_LI}:
            break
          else: discard
        if parser.hasElementInButtonScope(TAG_P):
          parser.closeP()
        discard parser.insertHTMLElement(token)
      )
      ("<dd>", "<dt>") => (block:
        parser.framesetOk = false
        for i in countdown(parser.openElements.high, 0):
          let node = parser.openElements[i]
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
          of SpecialElements - {TAG_ADDRESS, TAG_DIV, TAG_P, TAG_DD, TAG_DT}:
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
          if form.isNone or
              not parser.hasElementInScope(parser.getTagType(form.get)):
            parse_error ELEMENT_NOT_IN_SCOPE
            return
          let node = form.get
          parser.generateImpliedEndTags()
          if parser.currentNode != node:
            parse_error ELEMENT_NOT_CURRENT_NODE
          parser.openElements.delete(parser.openElements.find(node))
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
          discard parser.insertHTMLElement(Token(t: START_TAG, tagtype: TAG_P))
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
        var anchor: Option[Handle]
        for i in countdown(parser.activeFormatting.high, 0):
          let format = parser.activeFormatting[i]
          if format[0].isNone:
            break
          if parser.getTagType(format[0].get) == TAG_A:
            anchor = format[0]
            break
        if anchor.isSome:
          parse_error NESTED_TAGS
          if parser.adoptionAgencyAlgorithm(token):
            any_other_end_tag
            return
          for i in 0..parser.activeFormatting.high:
            if parser.activeFormatting[i][0].isSome and
                parser.activeFormatting[i][0].get == anchor.get:
              parser.activeFormatting.delete(i)
              break
          for i in 0..parser.openElements.high:
            if parser.openElements[i] == anchor.get:
              parser.openElements.delete(i)
              break
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
        reprocess Token(t: START_TAG, tagtype: TAG_BR)
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
        if not token.attrs.getOrDefault("type").equalsIgnoreCase("hidden"):
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
        let token = Token(t: START_TAG, tagtype: TAG_IMG, tagname: "img", selfclosing: token.selfclosing, attrs: token.attrs)
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
        if parser.insertionMode in {IN_TABLE, IN_CAPTION, IN_TABLE_BODY, IN_CELL}:
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
      #NOTE <math> (not implemented)
      #TODO <svg> (SVG)
      ("<caption>", "<col>", "<colgroup>", "<frame>", "<head>", "<tbody>",
       "<td>", "<tfoot>", "<th>", "<thead>", "<tr>") => (block:
        parse_error UNEXPECTED_START_TAG
      )
      TokenType.START_TAG => (block: any_other_start_tag)
      TokenType.END_TAG => (block: any_other_end_tag)

  of TEXT:
    match token:
      TokenType.CHARACTER_ASCII => (block:
        assert token.c != '\0'
        parser.insertCharacter(token.c)
      )
      TokenType.CHARACTER => (block:
        parser.insertCharacter(token.r)
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
      while parser.getTagType(parser.currentNode) notin {TAG_TABLE, TAG_TEMPLATE, TAG_HTML}:
        pop_current_node

    match token:
      (TokenType.CHARACTER_ASCII, TokenType.CHARACTER) => (block:
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
        discard parser.insertHTMLElement(Token(t: START_TAG, tagtype: TAG_COLGROUP))
        parser.insertionMode = IN_COLUMN_GROUP
      )
      ("<tbody>", "<tfoot>", "<thead>") => (block:
        clear_the_stack_back_to_a_table_context
        discard parser.insertHTMLElement(token)
        parser.insertionMode = IN_TABLE_BODY
      )
      ("<td>", "<th>", "<tr>") => (block:
        clear_the_stack_back_to_a_table_context
        discard parser.insertHTMLElement(Token(t: START_TAG, tagtype: TAG_TBODY))
        parser.insertionMode = IN_TABLE_BODY
        reprocess token
      )
      "<table>" => (block:
        parse_error NESTED_TAGS
        if not parser.hasElementInScope(TAG_TABLE):
          discard
        else:
          while parser.getTagType(parser.popElement()) != TAG_TABLE: discard
          parser.resetInsertionMode()
          reprocess token
      )
      "</table>" => (block:
        if not parser.hasElementInScope(TAG_TABLE):
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
        if not token.attrs.getOrDefault("type").equalsIgnoreCase("hidden"):
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
      '\0' => (block: parse_error UNEXPECTED_NULL)
      TokenType.CHARACTER_ASCII => (block:
        if token.c notin AsciiWhitespace:
          parser.pendingTableCharsWhitespace = false
        parser.pendingTableChars &= token.c
      )
      TokenType.CHARACTER => (block:
        parser.pendingTableChars &= $token.r
        parser.pendingTableCharsWhitespace = false
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
      AsciiWhitespace => (block: parser.insertCharacter(token.c))
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
      while parser.getTagType(parser.currentNode) notin {TAG_TBODY, TAG_TFOOT, TAG_THEAD, TAG_TEMPLATE, TAG_HTML}:
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
        discard parser.insertHTMLElement(Token(t: START_TAG, tagtype: TAG_TR))
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
          parser.insertionMode = IN_BODY
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
      '\0' => (block: parse_error UNEXPECTED_NULL)
      TokenType.CHARACTER_ASCII => (block: parser.insertCharacter(token.c))
      TokenType.CHARACTER => (block: parser.insertCharacter(token.r))
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
      "</optgroup>" => (block:
        if parser.getTagType(parser.currentNode) == TAG_OPTION:
          if parser.openElements.len > 1 and parser.getTagType(parser.openElements[^2]) == TAG_OPTGROUP:
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
        while parser.getTagType(parser.popElement()) != TAG_SELECT: discard
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
      (TokenType.CHARACTER_ASCII, TokenType.CHARACTER, TokenType.DOCTYPE) => (block:
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
      AsciiWhitespace => (block: parser.processInHTMLContent(token, IN_BODY))
      TokenType.COMMENT => (block: parser.insertComment(token, last_child_of(parser.openElements[0])))
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
      AsciiWhitespace => (block: parser.insertCharacter(token.c))
      TokenType.COMMENT => (block: parser.insertComment(token))
      TokenType.DOCTYPE => (block: parse_error UNEXPECTED_DOCTYPE)
      "<html>" => (block: parser.processInHTMLContent(token, IN_BODY))
      "<frameset>" => (block:
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
      AsciiWhitespace => (block: parser.insertCharacter(token.c))
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
        parser.insertComment(token, last_child_of(parser.document))
      )
      (TokenType.DOCTYPE, AsciiWhitespace, "<html>") => (block:
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
        parser.insertComment(token, last_child_of(parser.document))
      )
      (TokenType.DOCTYPE, AsciiWhitespace, "<html>") => (block:
        parser.processInHTMLContent(token, IN_BODY)
      )
      TokenType.EOF => (block: discard) # stop
      "<noframes>" => (block: parser.processInHTMLContent(token, IN_HEAD))
      other => (block: parser.parseErrorByTokenType(token.t))

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
}.toTable()

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

  template any_other_end_tag() =
    if parser.getLocalName(parser.currentNode) != token.tagname:
      parse_error UNEXPECTED_END_TAG
    for i in countdown(parser.openElements.high, 1):
      let node = parser.openElements[i]
      if parser.getLocalName(parser.currentNode) == token.tagname:
        while parser.popElement() != node:
          discard
        break
      if parser.getNamespace(node) == Namespace.HTML:
        break
      parser.processInHTMLContent(token, parser.insertionMode)

  match token:
    '\0' => (block:
      parse_error UNEXPECTED_NULL
      parser.insertCharacter(Rune(0xFFFD))
    )
    AsciiWhitespace => (block: parser.insertCharacter(token.c))
    TokenType.CHARACTER_ASCII => (block: parser.insertCharacter(token.c))
    TokenType.CHARACTER => (block: parser.insertCharacter(token.r))
    TokenType.DOCTYPE => (block: parse_error UNEXPECTED_DOCTYPE)
    ("<b>", "<big>", "<blockquote>", "<body>", "<br>", "<center>", "<code>",
     "<dd>", "<div>", "<dl>", "<dt>", "<em>", "<embed>", "<h1>", "<h2>",
     "<h3>", "<h4>", "<h5>", "<h6>", "<head>", "<hr>", "<i>", "<img>", "<li>",
     "<listing>", "<menu>", "<meta>", "<nobr>", "<ol>", "<p>", "<pre>",
     "<ruby>", "<s>", "<small>", "<span>", "<strong>", "<strike>", "<sub>",
     "<sup>", "<table>", "<tt>", "<u>", "<ul>", "<var>") => (block:
      parse_error UNEXPECTED_START_TAG
      #NOTE MathML not implemented
      while not parser.isHTMLIntegrationPoint(parser.currentNode) and
          parser.getNamespace(parser.currentNode) != Namespace.HTML:
        pop_current_node
      parser.processInHTMLContent(token, parser.insertionMode)
    )
    TokenType.START_TAG => (block:
      #NOTE MathML not implemented
      let namespace = parser.getNamespace(parser.adjustedCurrentNode)
      if namespace == Namespace.SVG:
        if token.tagname in CaseTable:
          token.tagname = CaseTable[token.tagname]
        adjustSVGAttributes(token)
      #TODO adjust foreign attributes
      discard parser.insertForeignElement(token, namespace)
      if token.selfclosing and namespace == Namespace.SVG:
        script_end_tag
      else:
        pop_current_node
    )
    "</script>" => (block:
      let namespace = parser.getNamespace(parser.currentNode)
      let localName = parser.getLocalName(parser.currentNode)
      if namespace == Namespace.SVG and localName == "script": #TODO SVG
        script_end_tag
      else:
        any_other_end_tag
    )
    TokenType.END_TAG => (block: any_other_end_tag)

proc constructTree[Handle](parser: var HTML5Parser[Handle]) =
  for token in parser.tokenizer.tokenize:
    if parser.ignoreLF:
      parser.ignoreLF = false
      if token.t == CHARACTER_ASCII and token.c == '\n':
        continue
    let isTokenHTML = token.t in {START_TAG, CHARACTER, CHARACTER_ASCII}
    if parser.openElements.len == 0 or
       parser.getNamespace(parser.adjustedCurrentNode) == Namespace.HTML or
       parser.isHTMLIntegrationPoint(parser.adjustedCurrentNode) and
        isTokenHTML or
       token.t == EOF:
      #NOTE MathML not implemented
      parser.processInHTMLContent(token, parser.insertionMode)
    else:
      parser.processInForeignContent(token)
    if parser.needsreinterpret:
      break

proc finishParsing(parser: var HTML5Parser) =
  while parser.openElements.len > 0:
    pop_current_node
  if parser.dombuilder.finish != nil:
    parser.dombuilder.finish(parser.dombuilder)

proc bomSniff(inputStream: Stream): Charset =
  # bom sniff
  const u8bom = char(0xEF) & char(0xBB) & char(0xBF)
  const bebom = char(0xFE) & char(0xFF)
  const lebom = char(0xFF) & char(0xFE)
  var bom = inputStream.readStr(2)
  if bom == bebom:
    return CHARSET_UTF_16_BE
  elif bom == lebom:
    return CHARSET_UTF_16_LE
  else:
    bom &= inputStream.readChar()
    if bom == u8bom:
      return CHARSET_UTF_8
    else:
      inputStream.setPosition(0)

# Any of these pointers being nil would later result in a crash.
proc checkCallbacks(dombuilder: DOMBuilder) =
  doAssert dombuilder.getParentNode != nil
  doAssert dombuilder.getLocalName != nil
  doAssert dombuilder.createElement != nil
  doAssert dombuilder.createComment != nil
  doAssert dombuilder.createDocumentType != nil
  doAssert dombuilder.insertBefore != nil
  doAssert dombuilder.insertText != nil
  doAssert dombuilder.remove != nil

proc parseHTML*[Handle](inputStream: Stream, dombuilder: DOMBuilder[Handle],
    opts: HTML5ParserOpts[Handle]) =
  ## Parse an HTML document, using the DOMBuilder object `dombuilder`, and
  ## parser options `opts`.
  dombuilder.checkCallbacks()
  var charsetStack: seq[Charset]
  for i in countdown(opts.charsets.high, 0):
    charsetStack.add(opts.charsets[i])
  var canReinterpret = opts.canReinterpret
  var confidence: CharsetConfidence
  if canReinterpret:
    let scs = inputStream.bomSniff()
    if scs != CHARSET_UNKNOWN:
      charsetStack.add(scs)
      confidence = CONFIDENCE_CERTAIN
      canReinterpret = false
  if charsetStack.len == 0:
    charsetStack.add(DefaultCharset) # UTF-8
  var previousCharset = CHARSET_UNKNOWN
  var first = true
  while true:
    let charset = charsetStack.pop()
    var parser = HTML5Parser[Handle](
      dombuilder: dombuilder,
      confidence: confidence,
      charset: charset,
      opts: opts
    )
    if charset != previousCharset:
      parser.setCharacterSet(charset)
      previousCharset = charset
    if first:
      first = false
    else:
      parser.restart()
    confidence = CONFIDENCE_TENTATIVE # used in the next iteration
    if not canReinterpret:
      parser.confidence = CONFIDENCE_CERTAIN
    let em = if charsetStack.len == 0 or not canReinterpret:
      DECODER_ERROR_MODE_REPLACEMENT
    else:
      DECODER_ERROR_MODE_FATAL
    let decoder = newDecoderStream(inputStream, parser.charset, errormode = em)
    proc x(e: ParseError) =
      parser.parseError(e)
    let onParseError = if parser.hasParseError():
      x
    else:
      nil
    parser.tokenizer = newTokenizer(decoder, onParseError)
    parser.constructTree()
    if parser.needsreinterpret and canReinterpret:
      inputStream.setPosition(0)
      charsetStack.add(parser.charset)
      canReinterpret = false
      continue
    if decoder.failed and canReinterpret:
      inputStream.setPosition(0)
      continue
    parser.finishParsing()
    break
