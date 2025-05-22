import std/macros
import std/options
import std/strutils
import std/tables

import dombuilder
import htmltokenizer
import tags
import tokstate

# Generics break without exporting macros. Maybe a compiler bug?
export macros

# Export these so that htmlparseriface works seamlessly.
export dombuilder
export options
export tags

# Export tokstate too; it is needed for fragment parsing.
export tokstate

# Heavily inspired by html5ever's TreeSink design.
type
  HTML5ParserOpts*[Handle, Atom] = object
    isIframeSrcdoc*: bool ## Is the document an iframe srcdoc?
    scripting*: bool ## Is scripting enabled for this document?
    pushInTemplate*: bool
    ## When set to true, the "in template" insertion mode is pushed to
    ## the stack of template insertion modes on parser start.
    initialTokenizerState*: TokenizerState
    ## The initial tokenizer state; by default, this is DATA.
    ctx*: Option[OpenElementInit[Handle, Atom]]
    ## Context element for fragment parsing. When set to some Handle,
    ## the fragment case is used while parsing.
    ##
    ## `token` must be a valid starting token for this element.
    openElementsInit*: seq[OpenElementInit[Handle, Atom]] ## Initial
    ## state of the stack of open elements. By default, the stack starts
    ## out empty.
    ## Note: if this is initialized to a non-empty sequence, the parser will
    ## start by resetting the insertion mode appropriately.
    formInit*: Option[Handle] ## Initial state of the parser's form pointer.

  OpenElement*[Handle, Atom] = tuple
    element: Handle
    token: Token[Atom] ## the element's start tag token; must not be nil.

  OpenElementInit*[Handle, Atom] = tuple
    element: Handle
    startTagName: Atom ## the element's start tag token's name.

type
  QualifiedName[Atom] = tuple
    prefix: NamespacePrefix
    namespace: Namespace
    localName: Atom

  HTML5Parser*[Handle, Atom] = object
    dombuilder: DOMBuilder[Handle, Atom]
    opts: HTML5ParserOpts[Handle, Atom]
    ctx: Option[OpenElement[Handle, Atom]]
    openElements: seq[OpenElement[Handle, Atom]]
    templateModes: seq[InsertionMode]
    head: Option[OpenElement[Handle, Atom]]
    tokenizer: Tokenizer[Handle, Atom]
    form: Option[Handle]
    quirksMode: QuirksMode
    insertionMode: InsertionMode
    oldInsertionMode: InsertionMode
    fosterParenting: bool
    framesetOk: bool
    ignoreLF: bool
    pendingTableCharsWhitespace: bool
    # Handle is an element. nil => marker
    activeFormatting: seq[(Option[Handle], Token[Atom])]
    pendingTableChars: string
    caseTable: Table[Atom, Atom]
    adjustedTable: Table[Atom, Atom]
    foreignTable: Table[Atom, QualifiedName[Atom]]

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

type ParseResult* = enum
  ## Result of parsing the passed chunk.
  ## PRES_CONTINUE is returned when it is OK to continue parsing.
  ##
  ## PRES_STOP is returned when the parser has been stopped from
  ## setEncodingImpl.
  ##
  ## PRES_SCRIPT is returned when a script end tag is encountered. For
  ## implementations that do not support scripting, this can be treated
  ## equivalently to PRES_CONTINUE.
  ##
  ## Implementations that *do* support scripting and implement `document.write`
  ## can instead use PRES_SCRIPT to process string injected into the input
  ## stream by `document.write` before continuing with parsing from the
  ## network stream. In this case, script elements should be stored in e.g. the
  ## DOM builder from `elementPoppedImpl`, and processed accordingly after
  ## PRES_SCRIPT has been returned.
  PRES_CONTINUE
  PRES_STOP
  PRES_SCRIPT

# DOMBuilder interface functions
proc strToAtom[Handle, Atom](parser: HTML5Parser[Handle, Atom], s: string):
    Atom =
  mixin strToAtomImpl
  return parser.dombuilder.strToAtomImpl(s)

proc tagTypeToAtom[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    tagType: TagType): Atom =
  mixin tagTypeToAtomImpl
  return parser.dombuilder.tagTypeToAtomImpl(tagType)

# Declared as extern, because Nim 1.6.10 does not recognize it in macros
# otherwise.
proc atomToTagType*[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    atom: Atom): TagType =
  mixin atomToTagTypeImpl
  return parser.dombuilder.atomToTagTypeImpl(atom)

proc setQuirksMode[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    mode: QuirksMode) =
  mixin setQuirksModeImpl
  parser.quirksMode = mode
  when compiles(parser.dombuilder.setQuirksModeImpl(mode)):
    parser.dombuilder.setQuirksModeImpl(mode)

proc setEncoding(parser: var HTML5Parser, cs: string): SetEncodingResult =
  mixin setEncodingImpl
  when compiles(parser.dombuilder.setEncodingImpl(cs)):
    return parser.dombuilder.setEncodingImpl(cs)
  else:
    return SET_ENCODING_CONTINUE

proc getDocument[Handle, Atom](parser: HTML5Parser[Handle, Atom]): Handle =
  mixin getDocumentImpl
  return parser.dombuilder.getDocumentImpl()

proc getParentNode[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    handle: Handle): Option[Handle] =
  mixin getParentNodeImpl
  return parser.dombuilder.getParentNodeImpl(handle)

proc getLocalName[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    handle: Handle): Atom =
  mixin getLocalNameImpl
  return parser.dombuilder.getLocalNameImpl(handle)

proc getNamespace[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    handle: Handle): Namespace =
  mixin getNamespaceImpl
  return parser.dombuilder.getNamespaceImpl(handle)

proc getTemplateContent[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    handle: Handle): Handle =
  mixin getTemplateContentImpl
  return parser.dombuilder.getTemplateContentImpl(handle)

proc getTagType[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    handle: Handle): TagType =
  if parser.getNamespace(handle) != Namespace.HTML:
    return TAG_UNKNOWN
  return parser.atomToTagType(parser.getLocalName(handle))

proc createHTMLElement[Handle, Atom](parser: HTML5Parser[Handle, Atom]):
    Handle =
  mixin createHTMLElementImpl
  return parser.dombuilder.createHTMLElementImpl()

proc createComment[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    text: string): Handle =
  mixin createCommentImpl
  return parser.dombuilder.createCommentImpl(text)

proc createDocumentType[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    name, publicId, systemId: string): Handle =
  mixin createDocumentTypeImpl
  return parser.dombuilder.createDocumentTypeImpl(name, publicId, systemId)

proc insertBefore[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    parent, child: Handle, before: Option[Handle]) =
  mixin insertBeforeImpl
  parser.dombuilder.insertBeforeImpl(parent, child, before)

proc insertText[Handle, Atom](parser: HTML5Parser[Handle, Atom], parent: Handle,
    text: string, before: Option[Handle]) =
  mixin insertTextImpl
  parser.dombuilder.insertTextImpl(parent, text, before)

proc remove[Handle, Atom](parser: HTML5Parser[Handle, Atom], child: Handle) =
  mixin removeImpl
  parser.dombuilder.removeImpl(child)

proc moveChildren[Handle, Atom](parser: HTML5Parser[Handle, Atom], handleFrom,
    handleTo: Handle) =
  mixin moveChildrenImpl
  parser.dombuilder.moveChildrenImpl(handleFrom, handleTo)

proc addAttrsIfMissing[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    element: Handle, attrs: Table[Atom, string]) =
  mixin addAttrsIfMissingImpl
  parser.dombuilder.addAttrsIfMissingImpl(element, attrs)

proc setScriptAlreadyStarted[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    script: Handle) =
  mixin setScriptAlreadyStartedImpl
  when compiles(parser.dombuilder.setScriptAlreadyStartedImpl(script)):
    parser.dombuilder.setScriptAlreadyStartedImpl(script)

proc associateWithForm[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    element, form, intendedParent: Handle) =
  mixin associateWithFormImpl
  when compiles(parser.dombuilder.associateWithFormImpl(element, form,
      intendedParent)):
    parser.dombuilder.associateWithFormImpl(element, form, intendedParent)

# Parser
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
    return parser.ctx.get
  else:
    return parser.currentNodeToken

func adjustedCurrentNode[Handle, Atom](parser: HTML5Parser[Handle, Atom]):
    Handle =
  return parser.adjustedCurrentNodeToken.element

proc lastElementOfTag[Handle, Atom](parser: HTML5Parser[Handle, Atom],
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
proc appropriatePlaceForInsert[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: Handle): AdjustedInsertionLocation[Handle] =
  assert parser.getTagType(parser.openElements[0].element) == TAG_HTML
  let targetTagType = parser.getTagType(target)
  const FosterTagTypes = {TAG_TABLE, TAG_TBODY, TAG_TFOOT, TAG_THEAD, TAG_TR}
  if parser.fosterParenting and targetTagType in FosterTagTypes:
    let lastTemplate = parser.lastElementOfTag(TAG_TEMPLATE)
    let lastTable = parser.lastElementOfTag(TAG_TABLE)
    if lastTemplate.element.isSome and
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
  if parser.getTagType(result.inside) == TAG_TEMPLATE:
    result = (parser.getTemplateContent(result.inside), none(Handle))

proc appropriatePlaceForInsert[Handle, Atom](parser: HTML5Parser[Handle, Atom]):
    AdjustedInsertionLocation[Handle] =
  parser.appropriatePlaceForInsert(parser.currentNode)

proc hasElement[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    tags: set[TagType]): bool =
  for (element, _) in parser.openElements:
    if parser.getTagType(element) in tags:
      return true
  return false

proc hasElement[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    tag: TagType): bool =
  return parser.hasElement({tag})

const Scope = {
  TAG_APPLET, TAG_CAPTION, TAG_HTML, TAG_TABLE, TAG_TD, TAG_TH, TAG_MARQUEE,
  TAG_OBJECT, TAG_TEMPLATE # (+ SVG, MathML)
}

proc hasElementInScopeWithXML[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: Handle, list: set[TagType]): bool =
  for i in countdown(parser.openElements.high, 0):
    let element = parser.openElements[i].element
    if element == target:
      return true
    let localName = parser.getLocalName(element)
    let tagType = parser.atomToTagType(localName)
    case parser.getNamespace(element)
    of Namespace.HTML:
      {.linearScanEnd.}
      if tagType in list:
        return false
    of Namespace.MATHML:
      const elements = {
        TAG_MI, TAG_MO, TAG_MN, TAG_MS, TAG_MTEXT, TAG_ANNOTATION_XML
      }
      if tagType in elements:
        return false
    of Namespace.SVG:
      const elements = {TAG_FOREIGN_OBJECT, TAG_DESC, TAG_TITLE}
      if tagType in elements:
        return false
    else: discard
  return false

proc hasElementInScopeWithXML[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: set[TagType], list: set[TagType]): bool =
  for i in countdown(parser.openElements.high, 0):
    let element = parser.openElements[i].element
    let tagType = parser.atomToTagType(parser.getLocalName(element))
    case parser.getNamespace(element)
    of Namespace.HTML:
      if tagType in target:
        return true
      if tagType in list:
        return false
    of Namespace.MATHML:
      const elements = {
        TAG_MI, TAG_MO, TAG_MN, TAG_MS, TAG_MTEXT, TAG_ANNOTATION_XML
      }
      if tagType in elements:
        return false
    of Namespace.SVG:
      const elements = {TAG_FOREIGN_OBJECT, TAG_DESC, TAG_TITLE}
      if tagType in elements:
        return false
    else: discard
  return false

proc hasElementInScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: Handle): bool =
  return parser.hasElementInScopeWithXML(target, Scope)

proc hasElementInScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: set[TagType]): bool =
  return parser.hasElementInScopeWithXML(target, Scope)

proc hasElementInScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: TagType): bool =
  return parser.hasElementInScope({target})

proc hasElementInScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    localName: Atom): bool =
  let target = parser.atomToTagType(localName)
  return parser.hasElementInScope(target)

proc hasElementInListItemScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: TagType): bool =
  const ListItemScope = Scope + {TAG_OL, TAG_UL}
  return parser.hasElementInScopeWithXML({target}, ListItemScope)

proc hasElementInButtonScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: TagType): bool =
  const ButtonScope = Scope + {TAG_BUTTON}
  return parser.hasElementInScopeWithXML({target}, ButtonScope)

# Note: these do not include the "Scope" tags.
proc hasElementInSpecificScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: Handle, list: set[TagType]): bool =
  for i in countdown(parser.openElements.high, 0):
    let element = parser.openElements[i].element
    if element == target:
      return true
    if parser.getTagType(element) in list:
      return false
  assert false
  return false

proc hasElementInSpecificScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: set[TagType], list: set[TagType]): bool =
  for i in countdown(parser.openElements.high, 0):
    let tagType = parser.getTagType(parser.openElements[i].element)
    if tagType in target:
      return true
    if tagType in list:
      return false
  assert false
  return false

const TableScope = {TAG_HTML, TAG_TABLE, TAG_TEMPLATE}
proc hasElementInTableScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: TagType): bool =
  return parser.hasElementInSpecificScope({target}, TableScope)

proc hasElementInTableScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: set[TagType]): bool =
  return parser.hasElementInSpecificScope(target, TableScope)

proc hasElementInSelectScope[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    target: TagType): bool =
  for i in countdown(parser.openElements.high, 0):
    let tagType = parser.getTagType(parser.openElements[i].element)
    if tagType == target:
      return true
    if tagType notin {TAG_OPTION, TAG_OPTGROUP}:
      return false
  assert false
  return false

proc createElementForToken[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    localName: Atom, namespace: Namespace, intendedParent: Handle,
    htmlAttrs: Table[Atom, string], xmlAttrs: seq[ParsedAttr[Atom]]): Handle =
  mixin createElementForTokenImpl
  let element = parser.dombuilder.createElementForTokenImpl(
    localName, namespace, intendedParent, htmlAttrs, xmlAttrs
  )
  let tagType = parser.atomToTagType(localName)
  if namespace == Namespace.HTML and tagType in FormAssociatedElements and
      parser.form.isSome and not parser.hasElement(TAG_TEMPLATE) and
      (tagType notin ListedElements or
        parser.tagTypeToAtom(TAG_FORM) notin htmlAttrs):
    parser.associateWithForm(element, parser.form.get, intendedParent)
  return element

proc createElementForToken[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    token: Token, namespace: Namespace, intendedParent: Handle): Handle =
  # attrs not adjusted
  return parser.createElementForToken(token.tagname, namespace, intendedParent,
    token.attrs, @[])

proc createHTMLElementForToken[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    token: Token, intendedParent: Handle): Handle =
  # attrs not adjusted
  return parser.createElementForToken(
    token.tagname, Namespace.HTML, intendedParent, token.attrs, @[]
  )

proc pushElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    node: Handle, token: Token[Atom]) =
  parser.openElements.add((node, token))
  let node = parser.adjustedCurrentNode()
  parser.tokenizer.hasnonhtml = parser.getNamespace(node) != Namespace.HTML

proc popElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom]): Handle =
  mixin elementPoppedImpl
  result = parser.openElements.pop().element
  when compiles(parser.dombuilder.elementPoppedImpl(result)):
    parser.dombuilder.elementPoppedImpl(result)
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
    xmlAttrs: seq[ParsedAttr[Atom]]): Handle =
  let location = parser.appropriatePlaceForInsert()
  let parent = location.inside
  let element = parser.createElementForToken(localName, namespace, parent,
    token.attrs, xmlAttrs)
  if not stackOnly:
    parser.insert(location, element)
  parser.pushElement(element, token)
  return element

proc insertForeignElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    token: Token, namespace: Namespace, stackOnly: bool): Handle =
  parser.insertForeignElement(token, token.tagname, namespace, stackOnly, @[])

proc insertHTMLElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    token: Token): Handle =
  return parser.insertForeignElement(token, Namespace.HTML, false)

# Note: adjustMathMLAttributes and adjustSVGAttributes both include the "adjust
# foreign attributes" step as well.
proc adjustMathMLAttributes[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    htmlAttrs: var Table[Atom, string], xmlAttrs: var seq[ParsedAttr[Atom]]) =
  var deleted: seq[Atom] = @[]
  for k, v in htmlAttrs.mpairs:
    parser.foreignTable.withValue(k, p):
      xmlAttrs.add((p[].prefix, p[].namespace, p[].localName, v))
      deleted.add(k)
  var v: string = ""
  if htmlAttrs.pop(parser.tagTypeToAtom(TAG_DEFINITION_URL), v):
    htmlAttrs[parser.strToAtom("definitionURL")] = v
  for k in deleted:
    htmlAttrs.del(k)

proc adjustSVGAttributes[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    htmlAttrs: var Table[Atom, string], xmlAttrs: var seq[ParsedAttr[Atom]]) =
  var deleted: seq[Atom] = @[]
  for k, v in htmlAttrs:
    parser.foreignTable.withValue(k, p):
      xmlAttrs.add((p[].prefix, p[].namespace, p[].localName, v))
      deleted.add(k)
  for k, ak in parser.adjustedTable:
    var v: string = ""
    if htmlAttrs.pop(k, v):
      htmlAttrs[ak] = v
  for k in deleted:
    htmlAttrs.del(k)

proc insertCharacter(parser: var HTML5Parser, data: string) =
  let location = parser.appropriatePlaceForInsert()
  if location.inside == parser.getDocument():
    return
  parser.insertText(location.inside, data, location.before)

proc insertComment[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    token: Token, position: AdjustedInsertionLocation[Handle]) =
  let comment = parser.createComment(token.s)
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

func startsWithNoCase(str, prefix: string): bool =
  if str.len < prefix.len:
    return false
  # prefix.len is always lower
  var i = 0
  while i != prefix.len:
    if str[i].toLowerAscii() != prefix[i].toLowerAscii():
      return false
    inc i
  true

func equalsIgnoreCase(s1, s2: string): bool {.inline.} =
  return s1.cmpIgnoreCase(s2) == 0

func quirksConditions(token: Token): bool =
  if tfQuirks in token.flags:
    return true
  if token.name != "html":
    return true
  if token.sysid == "http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd":
    return true
  if tfPubid in token.flags:
    for id in PublicIdentifierEquals:
      if token.pubid.equalsIgnoreCase(id):
        return true
    for id in PublicIdentifierStartsWith:
      if token.pubid.startsWithNoCase(id):
        return true
    if tfSysid notin token.flags:
      for id in SystemIdentifierMissingAndPublicIdentifierStartsWith:
        if token.pubid.startsWithNoCase(id):
          return true
  return false

func limitedQuirksConditions(token: Token): bool =
  if tfPubid notin token.flags: return false
  for id in PublicIdentifierStartsWithLimited:
    if token.pubid.startsWithNoCase(id):
      return true
  if tfSysid notin token.flags: return false
  for id in SystemIdentifierNotMissingAndPublicIdentifierStartsWith:
    if token.pubid.startsWithNoCase(id):
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

proc isMathMLIntegrationPoint[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    element: Handle): bool =
  if parser.getNamespace(element) != Namespace.MATHML:
    return false
  let tagType = parser.atomToTagType(parser.getLocalName(element))
  return tagType in {TAG_MI, TAG_MO, TAG_MN, TAG_MS, TAG_MTEXT}

proc isHTMLIntegrationPoint[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    oe: OpenElement[Handle, Atom]): bool =
  let (element, token) = oe
  let localName = parser.getLocalName(element)
  let namespace = parser.getNamespace(element)
  let tagType = parser.atomToTagType(localName)
  if namespace == Namespace.MATHML:
    if tagType == TAG_ANNOTATION_XML:
      token.attrs.withValue(parser.tagTypeToAtom(TAG_ENCODING), p):
        return p[].equalsIgnoreCase("text/html") or
          p[].equalsIgnoreCase("application/xhtml+xml")
  elif namespace == Namespace.SVG:
    return tagType in {TAG_FOREIGN_OBJECT, TAG_DESC, TAG_TITLE}
  return false

const AsciiWhitespace = {' ', '\n', '\r', '\t', '\f'}

func until(s: string, c1, c2: char, starti: int): string =
  result = ""
  for i in starti ..< s.len:
    if s[i] == c1 or s[i] == c2:
      break
    result &= s[i]

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
    let s2 = s.until('"', '\'', i + 1)
    if s2.len == 0 or s2[^1] != s[i]:
      return ""
    return s2
  return s.until(';', ' ', i)

# Find a node in the list of active formatting elements, or return -1.
func findLastActiveFormatting[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    node: Handle): int =
  for i in countdown(parser.activeFormatting.high, 0):
    let it = parser.activeFormatting[i][0]
    if it.isSome and it.get == node:
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

proc findLastActiveFormattingAfterMarker(parser: var HTML5Parser,
    tagType: TagType): int =
  for i in countdown(parser.activeFormatting.high, 0):
    let it = parser.activeFormatting[i][0]
    if it.isNone:
      break
    if parser.getTagType(it.get) == tagType:
      return i
  return -1

#https://html.spec.whatwg.org/multipage/parsing.html#the-stack-of-open-elements
const SpecialElements = {
  TAG_ADDRESS, TAG_APPLET, TAG_AREA, TAG_ARTICLE, TAG_ASIDE, TAG_BASE,
  TAG_BASEFONT, TAG_BGSOUND, TAG_BLOCKQUOTE, TAG_BODY, TAG_BR, TAG_BUTTON,
  TAG_CAPTION, TAG_CENTER, TAG_COL, TAG_COLGROUP, TAG_DD, TAG_DETAILS, TAG_DIR,
  TAG_DIV, TAG_DL, TAG_DT, TAG_EMBED, TAG_FIELDSET, TAG_FIGCAPTION, TAG_FIGURE,
  TAG_FOOTER, TAG_FORM, TAG_FRAME, TAG_FRAMESET, TAG_H1, TAG_H2, TAG_H3, TAG_H4,
  TAG_H5, TAG_H6, TAG_HEAD, TAG_HEADER, TAG_HGROUP, TAG_HR, TAG_HTML,
  TAG_IFRAME, TAG_IMG, TAG_INPUT, TAG_KEYGEN, TAG_LI, TAG_LINK, TAG_LISTING,
  TAG_MAIN, TAG_MARQUEE, TAG_MENU, TAG_META, TAG_NAV, TAG_NOEMBED, TAG_NOFRAMES,
  TAG_NOSCRIPT, TAG_OBJECT, TAG_OL, TAG_P, TAG_PARAM, TAG_PLAINTEXT, TAG_PRE,
  TAG_SCRIPT, TAG_SEARCH, TAG_SECTION, TAG_SELECT, TAG_SOURCE, TAG_STYLE,
  TAG_SUMMARY, TAG_TABLE, TAG_TBODY, TAG_TD, TAG_TEMPLATE, TAG_TEXTAREA,
  TAG_TFOOT, TAG_TH, TAG_THEAD, TAG_TITLE, TAG_TR, TAG_TRACK, TAG_UL, TAG_WBR,
  TAG_XMP
}

proc isSpecialElement[Handle, Atom](parser: HTML5Parser[Handle, Atom],
    element: Handle): bool =
  let tagType = parser.atomToTagType(parser.getLocalName(element))
  case parser.getNamespace(element)
  of Namespace.HTML:
    {.linearScanEnd.}
    return tagType in SpecialElements
  of Namespace.MATHML:
    const elements = {
      TAG_MI, TAG_MO, TAG_MN, TAG_MS, TAG_MTEXT, TAG_ANNOTATION_XML
    }
    return tagType in elements
  of Namespace.SVG:
    return tagType in {TAG_FOREIGN_OBJECT, TAG_DESC, TAG_TITLE}
  else:
    return false

# > Let furthestBlock be the topmost node in the stack of open elements that
# > is lower in the stack than formattingElement, and is an element in the
# > special category. There might not be one.
proc findFurthestBlockAfter(parser: HTML5Parser, stackIndex: int): int =
  for i in stackIndex ..< parser.openElements.len:
    if parser.isSpecialElement(parser.openElements[i].element):
      return i
  return -1

proc findLastActiveFormatting[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    tagTypes: set[TagType]): int =
  for i in countdown(parser.activeFormatting.high, 0):
    let it = parser.activeFormatting[i][0]
    if it.isSome and parser.getTagType(it.get) in tagTypes:
      return i
  return -1

# If true is returned, call "any other end tag".
proc adoptionAgencyAlgorithm[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    token: Token): bool =
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
      parser.activeFormatting.delete(formattingIndex)
      return false
    if not parser.hasElementInScope(formatting):
      return false
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
      let element = parser.createHTMLElementForToken(tok, commonAncestor)
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
    let element = parser.createHTMLElementForToken(token, furthestBlock)
    parser.moveChildren(furthestBlock, element)
    parser.append(furthestBlock, element)
    parser.activeFormatting.insert((some(element), token), bookmark)
    if formattingIndex >= bookmark:
      inc formattingIndex # increment because of insert
    parser.activeFormatting.delete(formattingIndex)
    parser.openElements.insert((element, token), furthestBlockIndex + 1)
    parser.openElements.delete(stackIndex)
  return false

proc closeP(parser: var HTML5Parser, sure = false) =
  if sure or parser.hasElementInButtonScope(TAG_P):
    parser.generateImpliedEndTags(TAG_P)
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
#       case parser.atomToTagName(token.tagname)
#       of {TAG_P, TAG_A}:
#         echo "p, a or closing div"
#         break inside_not_else
#       of TAG_DIV: discard
#       else:
#         assert false
#         break inside_not_else
#     of TokenType.END_TAG:
#       case parser.atomToTagName(token.tagname)
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
type
  OfBranch = (seq[NimNode], NimNode)

  OfBranchStore = object
    ofBranches: seq[OfBranch]
    defaultBranch: NimNode
    painted: bool

  PatternType = enum
    ptTokenType, ptTagType, ptOther, ptCombined

  Pattern = object
    case t: PatternType
    of ptTokenType:
      tokt: TokenType
    of ptTagType:
      isend: bool
      tagt: TagType
    of ptCombined:
      children: seq[Pattern]
    of ptOther: discard

const TagTypeMap = block:
  var map: Table[string, TagType]
  for tt in TagType:
    map[$tt] = tt
  map

proc toPattern(s: string): Pattern =
  if s == "_":
    return Pattern(t: ptOther)
  assert s[0] == '<' and s[^1] == '>'
  let isend = s[1] == '/'
  let i = if not isend: 1 else: 2
  let tagType = TagTypeMap[s[i..^2]]
  assert tagType != TAG_UNKNOWN
  return Pattern(t: ptTagType, isend: isend, tagt: tagType)

proc toPattern(tt: TokenType): Pattern =
  return Pattern(t: ptTokenType, tokt: tt)

proc toPattern(s: tuple): Pattern =
  result = Pattern(t: ptCombined)
  for _, x in s.fieldPairs:
    result.children.add(toPattern(x))

macro toNimNode(p: untyped): NimNode =
  return p

type MatchBuilder = object
  # Stores 'of' branches
  ofBranches: array[TokenType, OfBranchStore]
  # Stores 'else', 'elif' branches
  defaultBranch: NimNode

func tokenBranchOn(tok: TokenType): NimNode =
  assert tok in {START_TAG, END_TAG}
  return quote do:
    (
      let tokenTagType {.inject.} = parser.atomToTagType(token.tagname);
      tokenTagType
    )

proc addToCase(tokenCase: NimNode, branch: OfBranch) =
  if branch[0].len == 1:
    tokenCase.add(newNimNode(nnkOfBranch).add(branch[0][0]).add(branch[1]))
  else:
    var curly = newNimNode(nnkCurly)
    for node in branch[0]:
      curly.add(node)
    tokenCase.add(newNimNode(nnkOfBranch).add(curly).add(branch[1]))

func findAction(ofBranches: seq[OfBranch], action: NimNode): int =
  for i, branch in ofBranches:
    if branch[1] == action:
      return i
  return -1

proc buildBranches(builder: var MatchBuilder, patterns: openArray[Pattern],
    lambdas: NimNode) =
  for i in 0 ..< patterns.len:
    let pattern = patterns[i]
    let lambda = lambdas[i]
    const noAction = {nnkSym, nnkEmpty, nnkFormalParams}
    let action = lambda.findChild(it.kind notin noAction)
    var patterns = @[pattern]
    while patterns.len > 0:
      let pattern = patterns.pop()
      case pattern.t
      of ptTokenType:
        builder.ofBranches[pattern.tokt].defaultBranch = action
        builder.ofBranches[pattern.tokt].painted = true
      of ptTagType:
        let tt = int(pattern.tagt)
        let tokt = if not pattern.isend: START_TAG else: END_TAG
        let i = builder.ofBranches[tokt].ofBranches.findAction(action)
        if i != -1:
          builder.ofBranches[tokt].ofBranches[i][0].add(quote do: TagType(`tt`))
        else:
          let tup = (@[(quote do: TagType(`tt`))], action)
          builder.ofBranches[tokt].ofBranches.add(tup)
        builder.ofBranches[tokt].painted = true
      of ptCombined:
        for child in pattern.children:
          patterns.add(child)
      of ptOther:
        builder.defaultBranch = action

proc generateCaseStmts(builder: MatchBuilder, token: NimNode): NimNode =
  let mainCase = newNimNode(nnkCaseStmt).add(quote do: `token`.t)
  for tt in TokenType:
    let ofBranch = newNimNode(nnkOfBranch).add(quote do: TokenType(`tt`))
    let tokenCase = newNimNode(nnkCaseStmt)
    if builder.ofBranches[tt].defaultBranch != nil:
      if builder.ofBranches[tt].ofBranches.len > 0:
        tokenCase.add(tokenBranchOn(tt))
        for branch in builder.ofBranches[tt].ofBranches:
          tokenCase.addToCase(branch)
        tokenCase.add(newNimNode(nnkElse)
          .add(builder.ofBranches[tt].defaultBranch))
        ofBranch.add(tokenCase)
        mainCase.add(ofBranch)
      else:
        ofBranch.add(builder.ofBranches[tt].defaultBranch)
        mainCase.add(ofBranch)
    elif builder.ofBranches[tt].ofBranches.len > 0:
      tokenCase.add(tokenBranchOn(tt))
      for branch in builder.ofBranches[tt].ofBranches:
        tokenCase.addToCase(branch)
      ofBranch.add(tokenCase)
      tokenCase.add(newNimNode(nnkElse).add(quote do: discard))
      mainCase.add(ofBranch)
  return mainCase

macro match0(token: Token, patterns: static openArray[Pattern],
    lambdas: seq[NimNode]) =
  var builder = MatchBuilder()
  builder.buildBranches(patterns, lambdas)
  let mainCase = builder.generateCaseStmts(token)
  for t in TokenType:
    if not builder.ofBranches[t].painted:
      mainCase.add(newNimNode(nnkElse).add(quote do: discard))
      break
  var stmts = newStmtList().add(mainCase)
  for stmt in builder.defaultBranch:
    stmts.add(stmt)
  result = newBlockStmt(ident("inside_not_else"), stmts)

macro match(token: Token, bodyIn: untyped): untyped =
  result = newStmtList()
  var patterns = newTree(nnkBracket)
  var lambdas: seq[NimNode] = @[]
  for child in bodyIn:
    if unlikely(child.kind != nnkInfix or child[0].strVal != "=>"):
      error("=> expected")
    let sel = child[1]
    let body = child[2]
    let pattern = quote do:
      toPattern(`sel`)
    let lambda0 = quote do:
      toNimNode:
        `body`
        break inside_not_else
    patterns.add(pattern)
    lambdas.add(lambda0)
  result = quote do:
    match0(`token`, `patterns`, `lambdas`)

proc processInHTMLContent[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    token: Token, insertionMode: InsertionMode): ParseResult =
  template other: string = "_"

  template reprocess(tok: Token) =
    return parser.processInHTMLContent(tok, parser.insertionMode)

  template reprocess(mode: InsertionMode): ParseResult =
    parser.processInHTMLContent(token, mode)

  case insertionMode
  of INITIAL:
    match token:
      TokenType.CHARACTER_WHITESPACE => (block: discard)
      TokenType.COMMENT => (block:
        parser.insertComment(token, last_child_of(parser.getDocument()))
      )
      TokenType.DOCTYPE => (block:
        let doctype = parser.createDocumentType(token.name, token.pubid,
          token.sysid)
        parser.append(parser.getDocument(), doctype)
        if not parser.opts.isIframeSrcdoc:
          if quirksConditions(token):
            parser.setQuirksMode(QUIRKS)
          elif limitedQuirksConditions(token):
            parser.setQuirksMode(LIMITED_QUIRKS)
        parser.insertionMode = BEFORE_HTML
      )
      other => (block:
        parser.setQuirksMode(QUIRKS)
        parser.insertionMode = BEFORE_HTML
        reprocess token
      )

  of BEFORE_HTML:
    match token:
      (TokenType.DOCTYPE, TokenType.END_TAG,
        TokenType.CHARACTER_WHITESPACE) => (block: discard)
      TokenType.COMMENT => (block:
        parser.insertComment(token, last_child_of(parser.getDocument()))
      )
      "<html>" => (block:
        let intendedParent = parser.getDocument()
        let element = parser.createHTMLElementForToken(token, intendedParent)
        parser.append(parser.getDocument(), element)
        parser.pushElement(element, token)
        parser.insertionMode = BEFORE_HEAD
      )
      ("</head>", "</body>", "</html>", "</br>", other) => (block:
        let element = parser.createHTMLElement()
        parser.append(parser.getDocument(), element)
        let html = parser.newStartTagToken(TAG_HTML)
        parser.pushElement(element, html)
        parser.insertionMode = BEFORE_HEAD
        reprocess token
      )

  of BEFORE_HEAD:
    match token:
      (TokenType.CHARACTER_WHITESPACE, TokenType.DOCTYPE,
        TokenType.END_TAG) => (block: discard)
      TokenType.COMMENT => (block: parser.insertComment(token))
      "<html>" => (block: return reprocess IN_BODY)
      "<head>" => (block:
        parser.head = some((parser.insertHTMLElement(token), token))
        parser.insertionMode = IN_HEAD
      )
      ("</head>", "</body>", "</html>", "</br>", other) => (block:
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
      TokenType.DOCTYPE => (block: discard)
      "<html>" => (block: return reprocess IN_BODY)
      ("<base>", "<basefont>", "<bgsound>", "<link>") => (block:
        discard parser.insertHTMLElement(token)
        pop_current_node
      )
      "<meta>" => (block:
        discard parser.insertHTMLElement(token)
        pop_current_node
        token.attrs.withValue(parser.tagTypeToAtom(TAG_CHARSET), p):
          case parser.setEncoding(p[])
          of SET_ENCODING_CONTINUE:
            discard
          of SET_ENCODING_STOP:
            return PRES_STOP
        do:
          token.attrs.withValue(parser.tagTypeToAtom(TAG_HTTP_EQUIV), p):
            if p[].equalsIgnoreCase("Content-Type"):
              token.attrs.withValue(parser.tagTypeToAtom(TAG_CONTENT), p2):
                let cs = extractEncFromMeta(p2[])
                if cs != "":
                  case parser.setEncoding(cs)
                  of SET_ENCODING_CONTINUE:
                    discard
                  of SET_ENCODING_STOP:
                    return PRES_STOP
      )
      "<title>" => (block: parser.genericRCDATAElementParsingAlgorithm(token))
      "<noscript>" => (block:
        if not parser.opts.scripting:
          discard parser.insertHTMLElement(token)
          parser.insertionMode = IN_HEAD_NOSCRIPT
        else:
          parser.genericRawtextElementParsingAlgorithm(token)
      )
      ("<noframes>", "<style>") => (block:
        parser.genericRawtextElementParsingAlgorithm(token)
      )
      "<script>" => (block:
        let location = parser.appropriatePlaceForInsert()
        let element = parser.createElementForToken(token, Namespace.HTML,
          location.inside)
        if parser.fragment:
          parser.setScriptAlreadyStarted(element)
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
      "<template>" => (block:
        discard parser.insertHTMLElement(token)
        parser.activeFormatting.add((none(Handle), nil))
        parser.framesetOk = false
        parser.insertionMode = IN_TEMPLATE
        parser.templateModes.add(IN_TEMPLATE)
      )
      "</template>" => (block:
        if parser.hasElement(TAG_TEMPLATE):
          parser.generateImpliedEndTagsThoroughly()
          parser.popElementsIncl(TAG_TEMPLATE)
          parser.clearActiveFormattingTillMarker()
          discard parser.templateModes.pop()
          parser.resetInsertionMode()
      )
      ("<head>", TokenType.END_TAG) => (block: discard)
      ("</body>", "</html>", "</br>", other) => (block:
        pop_current_node
        parser.insertionMode = AFTER_HEAD
        reprocess token
      )

  of IN_HEAD_NOSCRIPT:
    match token:
      (TokenType.DOCTYPE, "<head>", "<noscript>", TokenType.END_TAG) => (block:
        discard
      )
      "<html>" => (block: return reprocess IN_BODY)
      "</noscript>" => (block:
        pop_current_node
        parser.insertionMode = IN_HEAD
      )
      (TokenType.CHARACTER_WHITESPACE, TokenType.COMMENT,
         "<basefont>", "<bgsound>", "<link>", "<meta>", "<noframes>",
         "<style>") => (block:
        return reprocess IN_HEAD
      )
      ("</br>", other) => (block:
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
      (TokenType.DOCTYPE, "<head>", TokenType.END_TAG) => (block: discard)
      "<html>" => (block: return reprocess IN_BODY)
      "<body>" => (block:
        discard parser.insertHTMLElement(token)
        parser.framesetOk = false
        parser.insertionMode = IN_BODY
      )
      "<frameset>" => (block:
        discard parser.insertHTMLElement(token)
        parser.insertionMode = IN_FRAMESET
      )
      ("<base>", "<basefont>", "<bgsound>", "<link>", "<meta>", "<noframes>",
      "<script>", "<style>", "<template>", "<title>") => (block:
        let (head, headTok) = parser.head.get
        parser.pushElement(head, headTok)
        result = reprocess IN_HEAD
        if (let i = parser.findOpenElement(head); i != -1):
          parser.openElements.delete(i)
      )
      "</template>" => (block: return reprocess IN_HEAD)
      ("</body>", "</html>", "</br>", other) => (block:
        discard parser.insertHTMLElement(parser.newStartTagToken(TAG_BODY))
        parser.insertionMode = IN_BODY
        reprocess token
      )

  of IN_BODY:
    template any_other_start_tag() =
      parser.reconstructActiveFormatting()
      discard parser.insertHTMLElement(token)

    template any_other_end_tag(tokenTagType: TagType) =
      for i in countdown(parser.openElements.high, 0):
        let (node, itToken) = parser.openElements[i]
        if itToken.tagname == token.tagname:
          parser.generateImpliedEndTags(tokenTagType)
          parser.popElementsIncl(node)
          break
        elif parser.isSpecialElement(node):
          return

    match token:
      TokenType.CHARACTER_WHITESPACE => (block:
        parser.reconstructActiveFormatting()
        parser.insertCharacter(token.s)
      )
      (TokenType.CHARACTER_NULL, TokenType.DOCTYPE) => (block: discard)
      TokenType.CHARACTER => (block:
        parser.reconstructActiveFormatting()
        parser.insertCharacter(token.s)
        parser.framesetOk = false
      )
      TokenType.COMMENT => (block: parser.insertComment(token))
      "<html>" => (block:
        if not parser.hasElement(TAG_TEMPLATE):
          parser.addAttrsIfMissing(parser.openElements[0].element, token.attrs)
      )
      ("<base>", "<basefont>", "<bgsound>", "<link>", "<meta>", "<noframes>",
        "<script>", "<style>", "<template>", "<title>",
        "</template>") => (block:
          return reprocess IN_HEAD
      )
      "<body>" => (block:
        if parser.openElements.len == 1 or
            parser.getTagType(parser.openElements[1].element) != TAG_BODY or
            parser.hasElement(TAG_TEMPLATE):
          discard
        else:
          parser.framesetOk = false
          parser.addAttrsIfMissing(parser.openElements[1].element, token.attrs)
      )
      "<frameset>" => (block:
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
          return reprocess IN_TEMPLATE
        # stop
      )
      "</body>" => (block:
        if parser.hasElementInScope(TAG_BODY):
          parser.insertionMode = AFTER_BODY
      )
      "</html>" => (block:
        if parser.hasElementInScope(TAG_BODY):
          parser.insertionMode = AFTER_BODY
          reprocess token
      )
      ("<address>", "<article>", "<aside>", "<blockquote>", "<center>",
      "<details>", "<dialog>", "<dir>", "<div>", "<dl>", "<fieldset>",
      "<figcaption>", "<figure>", "<footer>", "<header>", "<hgroup>", "<main>",
      "<menu>", "<nav>", "<ol>", "<p>", "<search>", "<section>", "<summary>",
      "<ul>") => (block:
        parser.closeP()
        discard parser.insertHTMLElement(token)
      )
      ("<h1>", "<h2>", "<h3>", "<h4>", "<h5>", "<h6>") => (block:
        parser.closeP()
        if parser.getTagType(parser.currentNode) in HTagTypes:
          pop_current_node
        discard parser.insertHTMLElement(token)
      )
      ("<pre>", "<listing>") => (block:
        parser.closeP()
        discard parser.insertHTMLElement(token)
        parser.ignoreLF = true
        parser.framesetOk = false
      )
      "<form>" => (block:
        let hasTemplate = parser.hasElement(TAG_TEMPLATE)
        if parser.form.isNone or hasTemplate:
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
            parser.popElementsIncl(TAG_LI)
            break
          of TAG_ADDRESS, TAG_DIV, TAG_P:
            discard
          elif parser.isSpecialElement(node):
            break
          else: discard
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
            parser.popElementsIncl(TAG_DD)
            break
          of TAG_DT:
            parser.generateImpliedEndTags(TAG_DT)
            parser.popElementsIncl(TAG_DT)
            break
          of TAG_ADDRESS, TAG_DIV, TAG_P:
            discard
          elif parser.isSpecialElement(node):
            break
          else: discard
        parser.closeP()
        discard parser.insertHTMLElement(token)
      )
      "<plaintext>" => (block:
        parser.closeP()
        discard parser.insertHTMLElement(token)
        parser.tokenizer.state = PLAINTEXT
      )
      "<button>" => (block:
        if parser.hasElementInScope(TAG_BUTTON):
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
        if parser.hasElementInScope(token.tagname):
          parser.generateImpliedEndTags()
          parser.popElementsIncl(tokenTagType)
      )
      "</form>" => (block:
        if not parser.hasElement(TAG_TEMPLATE):
          let form = parser.form
          parser.form = none(Handle)
          if form.isNone or not parser.hasElementInScope(form.get):
            return
          let node = form.get
          parser.generateImpliedEndTags()
          let i = parser.findOpenElement(node)
          parser.openElements.delete(i)
        else:
          if parser.hasElementInScope(TAG_FORM):
            parser.generateImpliedEndTags()
            parser.popElementsIncl(TAG_FORM)
      )
      "</p>" => (block:
        if not parser.hasElementInButtonScope(TAG_P):
          discard parser.insertHTMLElement(parser.newStartTagToken(TAG_P))
        parser.closeP(sure = true)
      )
      "</li>" => (block:
        if parser.hasElementInListItemScope(TAG_LI):
          parser.generateImpliedEndTags(TAG_LI)
          parser.popElementsIncl(TAG_LI)
      )
      ("</dd>", "</dt>") => (block:
        if parser.hasElementInScope(tokenTagType):
          parser.generateImpliedEndTags(tokenTagType)
          parser.popElementsIncl(tokenTagType)
      )
      ("</h1>", "</h2>", "</h3>", "</h4>", "</h5>", "</h6>") => (block:
        if parser.hasElementInScope(HTagTypes):
          parser.generateImpliedEndTags()
          parser.popElementsIncl(HTagTypes)
      )
      "<a>" => (block:
        let i = parser.findLastActiveFormattingAfterMarker(TAG_A)
        if i != -1:
          let anchor = parser.activeFormatting[i][0].get
          if parser.adoptionAgencyAlgorithm(token):
            any_other_end_tag tokenTagType
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
          if parser.adoptionAgencyAlgorithm(token):
            any_other_end_tag tokenTagType
            return
          parser.reconstructActiveFormatting()
        let element = parser.insertHTMLElement(token)
        parser.pushOntoActiveFormatting(element, token)
      )
      ("</a>", "</b>", "</big>", "</code>", "</em>", "</font>", "</i>",
       "</nobr>", "</s>", "</small>", "</strike>", "</strong>", "</tt>",
       "</u>") => (block:
        if parser.adoptionAgencyAlgorithm(token):
          any_other_end_tag tokenTagType
          return
      )
      ("<applet>", "<marquee>", "<object>") => (block:
        parser.reconstructActiveFormatting()
        discard parser.insertHTMLElement(token)
        parser.activeFormatting.add((none(Handle), nil))
        parser.framesetOk = false
      )
      ("</applet>", "</marquee>", "</object>") => (block:
        if parser.hasElementInScope(tokenTagType):
          parser.generateImpliedEndTags()
          parser.popElementsIncl(tokenTagType)
          parser.clearActiveFormattingTillMarker()
      )
      "<table>" => (block:
        if parser.quirksMode != QUIRKS:
          parser.closeP()
        discard parser.insertHTMLElement(token)
        parser.framesetOk = false
        parser.insertionMode = IN_TABLE
      )
      "</br>" => (block: reprocess parser.newStartTagToken(TAG_BR))
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
        token.attrs.withValue(parser.tagTypeToAtom(TAG_TYP), p):
          if not p[].equalsIgnoreCase("hidden"):
            parser.framesetOk = false
        do:
          parser.framesetOk = false
      )
      ("<param>", "<source>", "<track>") => (block:
        discard parser.insertHTMLElement(token)
        pop_current_node
      )
      "<hr>" => (block:
        parser.closeP()
        discard parser.insertHTMLElement(token)
        pop_current_node
        parser.framesetOk = false
      )
      "<image>" => (block:
        token.tagname = parser.tagTypeToAtom(TAG_IMG)
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
        discard parser.insertHTMLElement(token)
      )
      ("<rp>", "<rt>") => (block:
        if parser.hasElementInScope(TAG_RUBY):
          parser.generateImpliedEndTags(TAG_RTC)
        discard parser.insertHTMLElement(token)
      )
      "<math>" => (block:
        parser.reconstructActiveFormatting()
        var xmlAttrs: seq[ParsedAttr[Atom]] = @[]
        parser.adjustMathMLAttributes(token.attrs, xmlAttrs)
        discard parser.insertForeignElement(token, token.tagname,
          Namespace.MATHML, false, xmlAttrs)
        if tfSelfClosing in token.flags:
          pop_current_node
      )
      "<svg>" => (block:
        parser.reconstructActiveFormatting()
        var xmlAttrs: seq[ParsedAttr[Atom]] = @[]
        parser.adjustSVGAttributes(token.attrs, xmlAttrs)
        discard parser.insertForeignElement(token, token.tagname, Namespace.SVG,
          false, xmlAttrs)
        if tfSelfClosing in token.flags:
          pop_current_node
      )
      ("<caption>", "<col>", "<colgroup>", "<frame>", "<head>", "<tbody>",
       "<td>", "<tfoot>", "<th>", "<thead>", "<tr>") => (block:
        discard
      )
      TokenType.START_TAG => (block: any_other_start_tag)
      TokenType.END_TAG => (block:
        let tokenTagType = parser.atomToTagType(token.tagname)
        any_other_end_tag tokenTagType
      )

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
        if parser.getTagType(parser.currentNode) == TAG_SCRIPT:
          parser.setScriptAlreadyStarted(parser.currentNode)
        pop_current_node
        parser.insertionMode = parser.oldInsertionMode
        reprocess token
      )
      TokenType.END_TAG => (block:
        pop_current_node
        parser.insertionMode = parser.oldInsertionMode
        if parser.opts.scripting:
          if parser.atomToTagType(token.tagname) == TAG_SCRIPT:
            return PRES_SCRIPT
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
          parser.fosterParenting = true
          result = reprocess IN_BODY
          parser.fosterParenting = false
      )
      TokenType.COMMENT => (block: parser.insertComment(token))
      TokenType.DOCTYPE => (block: discard)
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
        if parser.hasElementInTableScope(TAG_TABLE):
          parser.popElementsIncl(TAG_TABLE)
          parser.resetInsertionMode()
          reprocess token
      )
      "</table>" => (block:
        if parser.hasElementInTableScope(TAG_TABLE):
          parser.popElementsIncl(TAG_TABLE)
          parser.resetInsertionMode()
      )
      ("</body>", "</caption>", "</col>", "</colgroup>", "</html>", "</tbody>",
       "</td>", "</tfoot>", "</th>", "</thead>", "</tr>") => (block: discard)
      ("<style>", "<script>", "<template>", "</template>") => (block:
        return reprocess IN_HEAD
      )
      "<input>" => (block:
        token.attrs.withValue(parser.tagTypeToAtom(TAG_TYP), p):
          if not p[].equalsIgnoreCase("hidden"):
            # anything else
            parser.fosterParenting = true
            result = reprocess IN_BODY
            parser.fosterParenting = false
          else:
            discard parser.insertHTMLElement(token)
            pop_current_node
        do:
          # anything else
          parser.fosterParenting = true
          result = reprocess IN_BODY
          parser.fosterParenting = false
      )
      "<form>" => (block:
        if parser.form.isNone and not parser.hasElement(TAG_TEMPLATE):
          parser.form = some(parser.insertHTMLElement(token))
          pop_current_node
      )
      TokenType.EOF => (block: return reprocess IN_BODY)
      other => (block:
        parser.fosterParenting = true
        result = reprocess IN_BODY
        parser.fosterParenting = false
      )

  of IN_TABLE_TEXT:
    match token:
      TokenType.CHARACTER_NULL => (block: discard)
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
        if parser.hasElementInTableScope(TAG_CAPTION):
          parser.generateImpliedEndTags()
          parser.popElementsIncl(TAG_CAPTION)
          parser.clearActiveFormattingTillMarker()
          parser.insertionMode = IN_TABLE
      )
      ("<caption>", "<col>", "<colgroup>", "<tbody>", "<td>", "<tfoot>",
       "<th>", "<thead>", "<tr>", "</table>") => (block:
        if parser.hasElementInTableScope(TAG_CAPTION):
          parser.generateImpliedEndTags()
          parser.popElementsIncl(TAG_CAPTION)
          parser.clearActiveFormattingTillMarker()
          parser.insertionMode = IN_TABLE
          reprocess token
      )
      ("</body>", "</col>", "</colgroup>", "</html>", "</tbody>", "</td>",
       "</tfoot>", "</th>", "</thead>", "</tr>") => (block: discard)
      other => (block: return reprocess IN_BODY)

  of IN_COLUMN_GROUP:
    match token:
      TokenType.CHARACTER_WHITESPACE => (block:
        parser.insertCharacter(token.s)
      )
      TokenType.COMMENT => (block: parser.insertComment(token))
      (TokenType.DOCTYPE, "</col>") => (block: discard)
      "<html>" => (block: return reprocess IN_BODY)
      "<col>" => (block:
        discard parser.insertHTMLElement(token)
        pop_current_node
      )
      "</colgroup>" => (block:
        if parser.getTagType(parser.currentNode) == TAG_COLGROUP:
          pop_current_node
          parser.insertionMode = IN_TABLE
      )
      ("<template>", "</template>") => (block: return reprocess IN_HEAD)
      TokenType.EOF => (block: return reprocess IN_BODY)
      other => (block:
        if parser.getTagType(parser.currentNode) == TAG_COLGROUP:
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
        clear_the_stack_back_to_a_table_body_context
        discard parser.insertHTMLElement(parser.newStartTagToken(TAG_TR))
        parser.insertionMode = IN_ROW
        reprocess token
      )
      ("</tbody>", "</tfoot>", "</thead>") => (block:
        if parser.hasElementInTableScope(tokenTagType):
          clear_the_stack_back_to_a_table_body_context
          pop_current_node
          parser.insertionMode = IN_TABLE
      )
      ("<caption>", "<col>", "<colgroup>", "<tbody>", "<tfoot>", "<thead>",
       "</table>") => (block:
        if parser.hasElementInTableScope({TAG_TBODY, TAG_THEAD, TAG_TFOOT}):
          clear_the_stack_back_to_a_table_body_context
          pop_current_node
          parser.insertionMode = IN_TABLE
          reprocess token
      )
      ("</body>", "</caption>", "</col>", "</colgroup>", "</html>", "</td>",
       "</th>", "</tr>") => (block: discard)
      other => (block: return reprocess IN_TABLE)

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
        if parser.hasElementInTableScope(TAG_TR):
          clear_the_stack_back_to_a_table_row_context
          pop_current_node
          parser.insertionMode = IN_TABLE_BODY
      )
      ("<caption>", "<col>", "<colgroup>", "<tbody>", "<tfoot>", "<thead>",
       "<tr>", "</table>") => (block:
        if parser.hasElementInTableScope(TAG_TR):
          clear_the_stack_back_to_a_table_row_context
          pop_current_node
          parser.insertionMode = IN_TABLE_BODY
          reprocess token
      )
      ("</tbody>", "</tfoot>", "</thead>") => (block:
        if parser.hasElementInTableScope({tokenTagType, TAG_TR}):
          clear_the_stack_back_to_a_table_row_context
          pop_current_node
          parser.insertionMode = IN_TABLE_BODY
          reprocess token
      )
      ("</body>", "</caption>", "</col>", "</colgroup>", "</html>", "</td>",
       "</th>") => (block: discard)
      other => (block: return reprocess IN_TABLE)

  of IN_CELL:
    template close_cell() =
      parser.generateImpliedEndTags()
      parser.popElementsIncl({TAG_TD, TAG_TH})
      parser.clearActiveFormattingTillMarker()
      parser.insertionMode = IN_ROW

    match token:
      ("</td>", "</th>") => (block:
        if parser.hasElementInTableScope(tokenTagType):
          parser.generateImpliedEndTags()
          parser.popElementsIncl(tokenTagType)
          parser.clearActiveFormattingTillMarker()
          parser.insertionMode = IN_ROW
      )
      ("<caption>", "<col>", "<colgroup>", "<tbody>", "<td>", "<tfoot>",
       "<th>", "<thead>", "<tr>") => (block:
        if parser.hasElementInTableScope({TAG_TD, TAG_TH}):
          close_cell
          reprocess token
      )
      ("</body>", "</caption>", "</col>", "</colgroup>", "</html>") => (block:
        discard
      )
      ("</table>", "</tbody>", "</tfoot>", "</thead>", "</tr>") => (block:
        if parser.hasElementInTableScope(tokenTagType):
          close_cell
          reprocess token
      )
      other => (block: return reprocess IN_BODY)

  of IN_SELECT:
    match token:
      (TokenType.CHARACTER, TokenType.CHARACTER_WHITESPACE) => (block:
        parser.insertCharacter(token.s)
      )
      TokenType.COMMENT => (block: parser.insertComment(token))
      "<html>" => (block: return reprocess IN_BODY)
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
      )
      "</option>" => (block:
        if parser.getTagType(parser.currentNode) == TAG_OPTION:
          pop_current_node
      )
      "</select>" => (block:
        if parser.hasElementInSelectScope(TAG_SELECT):
          parser.popElementsIncl(TAG_SELECT)
          parser.resetInsertionMode()
      )
      "<select>" => (block:
        if parser.hasElementInSelectScope(TAG_SELECT):
          parser.popElementsIncl(TAG_SELECT)
          parser.resetInsertionMode()
      )
      ("<input>", "<keygen>", "<textarea>") => (block:
        if parser.hasElementInSelectScope(TAG_SELECT):
          parser.popElementsIncl(TAG_SELECT)
          parser.resetInsertionMode()
          reprocess token
      )
      ("<script>", "<template>", "</template>") => (block:
        return reprocess IN_HEAD
      )
      TokenType.EOF => (block: return reprocess IN_BODY)
      other => (block: discard)

  of IN_SELECT_IN_TABLE:
    match token:
      ("<caption>", "<table>", "<tbody>", "<tfoot>", "<thead>", "<tr>", "<td>",
       "<th>") => (block:
        parser.popElementsIncl(TAG_SELECT)
        parser.resetInsertionMode()
        reprocess token
      )
      ("</caption>", "</table>", "</tbody>", "</tfoot>", "</thead>", "</tr>",
       "</td>", "</th>") => (block:
        if parser.hasElementInTableScope(tokenTagType):
          parser.popElementsIncl(TAG_SELECT)
          parser.resetInsertionMode()
          reprocess token
      )
      other => (block: return reprocess IN_SELECT)

  of IN_TEMPLATE:
    match token:
      (TokenType.CHARACTER, TokenType.CHARACTER_WHITESPACE,
          TokenType.CHARACTER_NULL, TokenType.DOCTYPE) => (block:
        return reprocess IN_BODY
      )
      ("<base>", "<basefont>", "<bgsound>", "<link>", "<meta>", "<noframes>",
       "<script>", "<style>", "<template>", "<title>", "</template>") => (block:
        return reprocess IN_HEAD
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
      TokenType.END_TAG => (block: discard)
      TokenType.EOF => (block:
        if not parser.hasElement(TAG_TEMPLATE):
          discard # stop
        else:
          parser.popElementsIncl(TAG_TEMPLATE)
          parser.clearActiveFormattingTillMarker()
          discard parser.templateModes.pop()
          parser.resetInsertionMode()
          reprocess token
      )

  of AFTER_BODY:
    match token:
      TokenType.CHARACTER_WHITESPACE => (block:
        return reprocess IN_BODY
      )
      TokenType.COMMENT => (block:
        parser.insertComment(token, last_child_of(parser.openElements[0]))
      )
      TokenType.DOCTYPE => (block: discard)
      "<html>" => (block: return reprocess IN_BODY)
      "</html>" => (block:
        if not parser.fragment:
          parser.insertionMode = AFTER_AFTER_BODY
      )
      TokenType.EOF => (block: discard) # stop
      other => (block:
        parser.insertionMode = IN_BODY
        reprocess token
      )

  of IN_FRAMESET:
    match token:
      TokenType.CHARACTER_WHITESPACE => (block:
        parser.insertCharacter(token.s)
      )
      TokenType.COMMENT => (block: parser.insertComment(token))
      TokenType.DOCTYPE => (block: discard)
      "<html>" => (block: return reprocess IN_BODY)
      "<frameset>" => (block: discard parser.insertHTMLElement(token))
      "</frameset>" => (block:
        if parser.getTagType(parser.currentNode) != TAG_HTML:
          pop_current_node
        if not parser.fragment and
            parser.getTagType(parser.currentNode) != TAG_FRAMESET:
          parser.insertionMode = AFTER_FRAMESET
      )
      "<frame>" => (block:
        discard parser.insertHTMLElement(token)
        pop_current_node
      )
      "<noframes>" => (block: return reprocess IN_HEAD)
      TokenType.EOF => (block:
        # stop
      )
      other => (block: discard)

  of AFTER_FRAMESET:
    match token:
      TokenType.CHARACTER_WHITESPACE => (block:
        parser.insertCharacter(token.s)
      )
      TokenType.COMMENT => (block: parser.insertComment(token))
      "<html>" => (block: return reprocess IN_BODY)
      "</html>" => (block: parser.insertionMode = AFTER_AFTER_FRAMESET)
      "<noframes>" => (block: return reprocess IN_HEAD)
      other => (block: discard)

  of AFTER_AFTER_BODY:
    match token:
      TokenType.COMMENT => (block:
        parser.insertComment(token, last_child_of(parser.getDocument()))
      )
      (TokenType.DOCTYPE, TokenType.CHARACTER_WHITESPACE, "<html>") => (block:
        return reprocess IN_BODY
      )
      TokenType.EOF => (block: discard) # stop
      other => (block:
        parser.insertionMode = IN_BODY
        reprocess token
      )

  of AFTER_AFTER_FRAMESET:
    match token:
      TokenType.COMMENT => (block:
        parser.insertComment(token, last_child_of(parser.getDocument()))
      )
      (TokenType.DOCTYPE, TokenType.CHARACTER_WHITESPACE, "<html>") => (block:
        return reprocess IN_BODY
      )
      "<noframes>" => (block: return reprocess IN_HEAD)
      other => (block: discard)
  return PRES_CONTINUE

proc processInForeignContent[Handle, Atom](
    parser: var HTML5Parser[Handle, Atom], token: Token): ParseResult =
  template script_end_tag() =
    pop_current_node
    return PRES_SCRIPT

  template any_other_start_tag() =
    let namespace = parser.getNamespace(parser.adjustedCurrentNode)
    var tagname = token.tagname
    var xmlAttrs: seq[ParsedAttr[Atom]] = @[]
    if namespace == Namespace.SVG:
      parser.caseTable.withValue(tagname, p):
        tagname = p[]
      parser.adjustSVGAttributes(token.attrs, xmlAttrs)
    elif namespace == Namespace.MATHML:
      parser.adjustMathMLAttributes(token.attrs, xmlAttrs)
    discard parser.insertForeignElement(token, tagname, namespace, false,
      xmlAttrs)
    if tfSelfClosing in token.flags:
      if namespace == Namespace.SVG and
          parser.atomToTagType(token.tagname) == TAG_SCRIPT:
        script_end_tag
      else:
        pop_current_node

  template any_other_end_tag() =
    for i in countdown(parser.openElements.high, 0): # loop
      if i == 0: # fragment case
        assert parser.fragment
        break
      let (node, nodeToken) = parser.openElements[i]
      if i != parser.openElements.high and
          parser.getNamespace(node) == Namespace.HTML:
        return parser.processInHTMLContent(token, parser.insertionMode)
      if nodeToken.tagname == token.tagname:
        # Compare the start tag token, since it is guaranteed to be lower case.
        # (The local name might have been adjusted to a non-lower-case string.)
        parser.popElementsIncl(node)
        break

  match token:
    TokenType.CHARACTER_NULL => (block: parser.insertCharacter("\uFFFD"))
    TokenType.CHARACTER_WHITESPACE => (block: parser.insertCharacter(token.s))
    TokenType.CHARACTER => (block:
      parser.insertCharacter(token.s)
      parser.framesetOk = false
    )
    TokenType.COMMENT => (block: parser.insertComment(token))
    TokenType.DOCTYPE => (block: discard)
    ("<b>", "<big>", "<blockquote>", "<body>", "<br>", "<center>", "<code>",
     "<dd>", "<div>", "<dl>", "<dt>", "<em>", "<embed>", "<h1>", "<h2>",
     "<h3>", "<h4>", "<h5>", "<h6>", "<head>", "<hr>", "<i>", "<img>", "<li>",
     "<listing>", "<menu>", "<meta>", "<nobr>", "<ol>", "<p>", "<pre>",
     "<ruby>", "<s>", "<small>", "<span>", "<strong>", "<strike>", "<sub>",
     "<sup>", "<table>", "<tt>", "<u>", "<ul>", "<var>",
     "<font>", # only if has "color", "face", or "size"
     "</br>", "</p>") => (block:
      if parser.atomToTagType(token.tagname) == TAG_FONT:
        let atColor = parser.tagTypeToAtom(TAG_COLOR)
        let atFace = parser.tagTypeToAtom(TAG_FACE)
        let atSize = parser.tagTypeToAtom(TAG_SIZE)
        if atColor notin token.attrs and atFace notin token.attrs and
            atSize notin token.attrs:
          any_other_start_tag
          return
      while not parser.isMathMLIntegrationPoint(parser.currentNode) and
          not parser.isHTMLIntegrationPoint(parser.currentNodeToken) and
          parser.getNamespace(parser.currentNode) != Namespace.HTML:
        pop_current_node
      return parser.processInHTMLContent(token, parser.insertionMode)
    )
    TokenType.START_TAG => (block:
      any_other_start_tag
    )
    "</script>" => (block:
      let namespace = parser.getNamespace(parser.currentNode)
      let localName = parser.currentToken.tagname
      # Any atom corresponding to the string "script" must have the same
      # value as TAG_SCRIPT, so this is correct.
      if namespace == Namespace.SVG and
          parser.atomToTagType(localName) == TAG_SCRIPT:
        script_end_tag
      else:
        any_other_end_tag
    )
    TokenType.END_TAG => (block: any_other_end_tag)
  return PRES_CONTINUE

proc processToken[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    token: Token[Atom]): ParseResult =
  if parser.ignoreLF:
    parser.ignoreLF = false
    if token.t == CHARACTER_WHITESPACE:
      if token.s[0] == '\n':
        if token.s.len == 1:
          return PRES_CONTINUE
        else:
          token.s.delete(0..0)
  if parser.openElements.len == 0 or
      parser.getNamespace(parser.adjustedCurrentNode) == Namespace.HTML:
    return parser.processInHTMLContent(token, parser.insertionMode)
  let oe = parser.adjustedCurrentNodeToken
  let oeTagType = parser.atomToTagType(oe.token.tagname)
  let namespace = parser.getNamespace(oe.element)
  const CharacterToken = {CHARACTER, CHARACTER_WHITESPACE, CHARACTER_NULL}
  let mmlnoatoms = {TAG_MGLYPH, TAG_MALIGNMARK}
  let ismmlip = parser.isMathMLIntegrationPoint(oe.element)
  let ishtmlip = parser.isHTMLIntegrationPoint(oe)
  if token.t == START_TAG and (
        let tagType = parser.atomToTagType(token.tagname)
        ismmlip and tagType notin mmlnoatoms or ishtmlip or
        namespace == Namespace.MATHML and oeTagType == TAG_ANNOTATION_XML and
          tagType == TAG_SVG
      ) or token.t in CharacterToken and (ismmlip or ishtmlip):
    return parser.processInHTMLContent(token, parser.insertionMode)
  return parser.processInForeignContent(token)

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

proc initHTML5Parser*[Handle, Atom](dombuilder: DOMBuilder[Handle, Atom],
    opts: HTML5ParserOpts[Handle, Atom]): HTML5Parser[Handle, Atom] =
  ## Create and initialize a new HTML5Parser object from dombuilder `dombuilder`
  ## and parser options `opts`.
  ##
  ## The generic `Handle` must be the node handle type of the DOM builder. The
  ## generic `Atom` must be the interned string type of the DOM builder.
  var parser = HTML5Parser[Handle, Atom](
    dombuilder: dombuilder,
    opts: opts,
    form: opts.formInit,
    framesetOk: true
  )
  if opts.ctx.isSome:
    let ctxInit = opts.ctx.get
    let ctx: OpenElement[Handle, Atom] = (ctxInit.element, Token[Atom](
      t: START_TAG,
      tagname: ctxInit.startTagName
    ))
    parser.ctx = some(ctx)
  for (element, tagName) in opts.openElementsInit:
    let it = (element, Token[Atom](t: START_TAG, tagname: tagName))
    parser.openElements.add(it)
  parser.createCaseTable()
  parser.createAdjustedTable()
  parser.createForeignTable()
  if opts.pushInTemplate:
    parser.templateModes.add(IN_TEMPLATE)
  if opts.openElementsInit.len > 0:
    parser.resetInsertionMode()
  let tokstate = opts.initialTokenizerState
  parser.tokenizer = newTokenizer[Handle, Atom](dombuilder, tokstate)
  return parser

proc parseChunk*[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    inputBuf: openArray[char]): ParseResult =
  ## Parse a chunk of characters stored in `inputBuf` with `parser`.
  var running = true
  parser.tokenizer.inputBufIdx = 0
  while running:
    running = parser.tokenizer.tokenize(inputBuf) != trDone
    for i, token in parser.tokenizer.tokqueue:
      let pres = parser.processToken(token)
      if pres != PRES_CONTINUE:
        assert pres != PRES_SCRIPT or i == parser.tokenizer.tokqueue.high
        return pres
  return PRES_CONTINUE

func getInsertionPoint*(parser: HTML5Parser): int =
  return parser.tokenizer.inputBufIdx

proc finish*[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  ## Finish parsing the document associated with `parser`.
  ## This will process an EOF token, and pop all elements from the stack of
  ## open elements one by one.
  var running = true
  while running:
    running = parser.tokenizer.finish() != trDone
    for token in parser.tokenizer.tokqueue:
      let pres = parser.processToken(token)
      assert pres == PRES_CONTINUE
      # pres == PRES_SCRIPT: this is unreachable.
      # * Tokenizer's tokenizeEOF() can not emit end tag tokens, ergo no
      #   </script> will be processed here.
      # * In some cases, tokenize() is called before tokenizeEOF(), to flush
      #   characters stuck in the internal peekBuf. This can happen if:
      #   1. eatStr returns esrRetry in a previous pass. Here, peekBuf can
      #      contain any prefix of strings passed to eatStr/NoCase(), which
      #      crucially is never a potential </script> tag (or indeed,
      #      nothing that can start with </).
      #   2. The "named character reference" state is interrupted. In this
      #      case, peekBuf is a prefix of at least one named character reference;
      #      obviously these can not be </script> tags either, since they
      #      all match the regex `&[a-zA-Z]+'.
      # pres == PRES_STOP: unreachable for reasons almost identical to those
      # outlined in PRES_SCRIPT. PRES_STOP can only be returned after a <meta>
      # tag is processed; just like with end tags, the tokenizer cannot emit
      # start tags in finish().
  discard parser.processInHTMLContent(Token[Atom](t: EOF), parser.insertionMode)
  while parser.openElements.len > 0:
    pop_current_node
