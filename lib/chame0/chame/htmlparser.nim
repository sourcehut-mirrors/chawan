import std/options
import std/tables

import dombuilder
import htmltokenizer
import tags
import tokstate

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

  OpenElement[Handle, Atom] = tuple
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

  InsertionLocation[Handle] = object
    inside: Handle
    before: Option[Handle]

# 13.2.4.1
  InsertionMode = enum
    imInitial, imBeforeHtml, imBeforeHead, imInHead, imInHeadNoscript,
    imAfterHead, imInBody, imInText, imInTable, imInTableInText, imInCaption,
    imInColumnGroup, imInTableBody, imInRow, imInCell, imInSelect,
    imInSelectInTable, imInTemplate, imAfterBody, imInFrameset, imAfterFrameset,
    imAfterAfterBody, imAfterAfterFrameset

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
proc strToAtom[Handle, Atom](parser: HTML5Parser[Handle, Atom]; s: string):
    Atom =
  mixin strToAtomImpl
  return parser.dombuilder.strToAtomImpl(s)

proc toAtom[Handle, Atom](parser: HTML5Parser[Handle, Atom]; tagType: TagType):
    Atom =
  mixin tagTypeToAtomImpl
  return parser.dombuilder.tagTypeToAtomImpl(tagType)

proc toTagType[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    atom: Atom): TagType =
  mixin atomToTagTypeImpl
  return parser.dombuilder.atomToTagTypeImpl(atom)

proc setQuirksMode[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    mode: QuirksMode) =
  mixin setQuirksModeImpl
  parser.quirksMode = mode
  when compiles(parser.dombuilder.setQuirksModeImpl(mode)):
    parser.dombuilder.setQuirksModeImpl(mode)

proc setEncoding(parser: var HTML5Parser; cs: string): SetEncodingResult =
  mixin setEncodingImpl
  when compiles(parser.dombuilder.setEncodingImpl(cs)):
    return parser.dombuilder.setEncodingImpl(cs)
  else:
    return SET_ENCODING_CONTINUE

proc getDocument[Handle, Atom](parser: HTML5Parser[Handle, Atom]): Handle =
  mixin getDocumentImpl
  return parser.dombuilder.getDocumentImpl()

proc getParentNode[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    handle: Handle): Option[Handle] =
  mixin getParentNodeImpl
  return parser.dombuilder.getParentNodeImpl(handle)

proc getLocalName[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    handle: Handle): Atom =
  mixin getLocalNameImpl
  return parser.dombuilder.getLocalNameImpl(handle)

proc getNamespace[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    handle: Handle): Namespace =
  mixin getNamespaceImpl
  return parser.dombuilder.getNamespaceImpl(handle)

proc getTemplateContent[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    handle: Handle): Handle =
  mixin getTemplateContentImpl
  return parser.dombuilder.getTemplateContentImpl(handle)

proc getTagType[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    handle: Handle): TagType =
  if parser.getNamespace(handle) != Namespace.HTML:
    return TAG_UNKNOWN
  return parser.toTagType(parser.getLocalName(handle))

proc createHTMLElement[Handle, Atom](parser: HTML5Parser[Handle, Atom]):
    Handle =
  mixin createHTMLElementImpl
  return parser.dombuilder.createHTMLElementImpl()

proc createComment[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    text: string): Handle =
  mixin createCommentImpl
  return parser.dombuilder.createCommentImpl(text)

proc createDocumentType[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    name, publicId, systemId: string): Handle =
  mixin createDocumentTypeImpl
  return parser.dombuilder.createDocumentTypeImpl(name, publicId, systemId)

proc insertBefore[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    parent, child: Handle; before: Option[Handle]) =
  mixin insertBeforeImpl
  parser.dombuilder.insertBeforeImpl(parent, child, before)

proc insertText[Handle, Atom](parser: HTML5Parser[Handle, Atom]; parent: Handle;
    text: string; before: Option[Handle]) =
  mixin insertTextImpl
  parser.dombuilder.insertTextImpl(parent, text, before)

proc remove[Handle, Atom](parser: HTML5Parser[Handle, Atom]; child: Handle) =
  mixin removeImpl
  parser.dombuilder.removeImpl(child)

proc moveChildren[Handle, Atom](parser: HTML5Parser[Handle, Atom]; handleFrom,
    handleTo: Handle) =
  mixin moveChildrenImpl
  parser.dombuilder.moveChildrenImpl(handleFrom, handleTo)

proc addAttrsIfMissing[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    element: Handle; attrs: Table[Atom, string]) =
  mixin addAttrsIfMissingImpl
  parser.dombuilder.addAttrsIfMissingImpl(element, attrs)

proc setScriptAlreadyStarted[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    script: Handle) =
  mixin setScriptAlreadyStartedImpl
  when compiles(parser.dombuilder.setScriptAlreadyStartedImpl(script)):
    parser.dombuilder.setScriptAlreadyStartedImpl(script)

proc associateWithForm[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    element, form, intendedParent: Handle) =
  mixin associateWithFormImpl
  when compiles(parser.dombuilder.associateWithFormImpl(element, form,
      intendedParent)):
    parser.dombuilder.associateWithFormImpl(element, form, intendedParent)

# Parser
iterator ropenElements[Handle, Atom](parser: HTML5Parser[Handle, Atom]):
    lent Handle =
  var i = uint(parser.openElements.len)
  while i > 0:
    dec i
    yield parser.openElements[i].element

# https://html.spec.whatwg.org/multipage/parsing.html#reset-the-insertion-mode-appropriately
proc resetInsertionMode0(parser: var HTML5Parser): InsertionMode =
  for i in countdown(parser.openElements.high, 0):
    var node = parser.openElements[i]
    let last = i == 0
    if last and parser.ctx.isSome:
      node = parser.ctx.get
    let tagType = parser.getTagType(node.element)
    case tagType
    of TAG_SELECT:
      if not last:
        for j in countdown(parser.openElements.high, 1):
          let ancestor = parser.openElements[j].element
          case parser.getTagType(ancestor)
          of TAG_TEMPLATE: break
          of TAG_TABLE: return imInSelectInTable
          else: discard
      return imInSelect
    of TAG_TD, TAG_TH:
      if not last:
        return imInCell
    of TAG_TR: return imInRow
    of TAG_TBODY, TAG_THEAD, TAG_TFOOT: return imInTableBody
    of TAG_CAPTION: return imInCaption
    of TAG_COLGROUP: return imInColumnGroup
    of TAG_TABLE: return imInTable
    of TAG_TEMPLATE: return parser.templateModes[^1]
    of TAG_HEAD:
      if not last:
        return imInHead
    of TAG_BODY: return imInBody
    of TAG_FRAMESET: return imInFrameset
    of TAG_HTML:
      if parser.head.isNone:
        return imBeforeHead
      else:
        return imAfterHead
    else: discard
  return imInBody

proc resetInsertionMode(parser: var HTML5Parser) =
  parser.insertionMode = parser.resetInsertionMode0()

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
  if parser.ctx.isSome and parser.openElements.len == 1:
    return parser.ctx.get
  else:
    return parser.currentNodeToken

func adjustedCurrentNode[Handle, Atom](parser: HTML5Parser[Handle, Atom]):
    Handle =
  return parser.adjustedCurrentNodeToken.element

proc lastElementOfTag[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    tagType: TagType): tuple[element: Option[Handle], pos: int] =
  for i in countdown(parser.openElements.high, 0):
    let element = parser.openElements[i].element
    if parser.getTagType(element) == tagType:
      return (some(element), i)
  return (none(Handle), -1)

func lastChildOf[Handle](n: Handle): InsertionLocation[Handle] =
  InsertionLocation[Handle](inside: n, before: none(Handle))

func lastChildOf[Handle, Atom](n: OpenElement[Handle, Atom]):
    InsertionLocation[Handle] =
  lastChildOf(n.element)

# https://html.spec.whatwg.org/multipage/#appropriate-place-for-inserting-a-node
proc appropriatePlaceForInsert[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: Handle): InsertionLocation[Handle] =
  assert parser.getTagType(parser.openElements[0].element) == TAG_HTML
  let targetTagType = parser.getTagType(target)
  const FosterTagTypes = {TAG_TABLE, TAG_TBODY, TAG_TFOOT, TAG_THEAD, TAG_TR}
  if parser.fosterParenting and targetTagType in FosterTagTypes:
    let lastTemplate = parser.lastElementOfTag(TAG_TEMPLATE)
    let lastTable = parser.lastElementOfTag(TAG_TABLE)
    if lastTemplate.element.isSome and
        (lastTable.element.isNone or lastTable.pos < lastTemplate.pos):
      let content = parser.getTemplateContent(lastTemplate.element.get)
      return lastChildOf(content)
    if lastTable.element.isNone:
      return lastChildOf(parser.openElements[0].element)
    let parentNode = parser.getParentNode(lastTable.element.get)
    if parentNode.isSome:
      return InsertionLocation[Handle](
        inside: parentNode.get,
        before: lastTable.element
      )
    let previousElement = parser.openElements[lastTable.pos - 1]
    result = lastChildOf(previousElement.element)
  else:
    result = lastChildOf(target)
  if parser.getTagType(result.inside) == TAG_TEMPLATE:
    result = lastChildOf(parser.getTemplateContent(result.inside))

proc appropriatePlaceForInsert[Handle, Atom](parser: HTML5Parser[Handle, Atom]):
    InsertionLocation[Handle] =
  parser.appropriatePlaceForInsert(parser.currentNode)

proc hasElement[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    tag: TagType): bool =
  for it in parser.openElements:
    if parser.getTagType(it.element) == tag:
      return true
  return false

const Scope = {
  TAG_APPLET, TAG_CAPTION, TAG_HTML, TAG_TABLE, TAG_TD, TAG_TH, TAG_MARQUEE,
  TAG_OBJECT, TAG_TEMPLATE # (+ SVG, MathML)
}

proc hasElementInScopeWithXML[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: Handle; list: set[TagType]): bool =
  for element in parser.ropenElements:
    if element == target:
      return true
    let localName = parser.getLocalName(element)
    let tagType = parser.toTagType(localName)
    case parser.getNamespace(element)
    of Namespace.HTML:
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

proc hasElementInScopeWithXML[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: set[TagType]; list: set[TagType]): bool =
  for element in parser.ropenElements:
    let tagType = parser.toTagType(parser.getLocalName(element))
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

proc hasElementInScope[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: Handle): bool =
  return parser.hasElementInScopeWithXML(target, Scope)

proc hasElementInScope[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: set[TagType]): bool =
  return parser.hasElementInScopeWithXML(target, Scope)

proc hasElementInScope[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: TagType): bool =
  return parser.hasElementInScope({target})

proc hasElementInScope[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    localName: Atom): bool =
  let target = parser.toTagType(localName)
  return parser.hasElementInScope(target)

proc hasElementInListItemScope[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: TagType): bool =
  const ListItemScope = Scope + {TAG_OL, TAG_UL}
  return parser.hasElementInScopeWithXML({target}, ListItemScope)

proc hasElementInButtonScope[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: TagType): bool =
  const ButtonScope = Scope + {TAG_BUTTON}
  return parser.hasElementInScopeWithXML({target}, ButtonScope)

proc hasElementInTableScope[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: set[TagType]): bool =
  for element in parser.ropenElements:
    let tagType = parser.getTagType(element)
    if tagType in target:
      return true
    if tagType in {TAG_HTML, TAG_TABLE, TAG_TEMPLATE}:
      break
  return false

proc hasElementInTableScope[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: TagType): bool =
  return parser.hasElementInTableScope({target})

proc hasElementInSelectScope[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: TagType): bool =
  for element in parser.ropenElements:
    let tagType = parser.getTagType(element)
    if tagType == target:
      return true
    if tagType notin {TAG_OPTION, TAG_OPTGROUP}:
      return false
  assert false
  return false

proc createElementForToken[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    localName: Atom; namespace: Namespace; intendedParent: Handle;
    htmlAttrs: Table[Atom, string]; xmlAttrs: seq[ParsedAttr[Atom]]): Handle =
  mixin createElementForTokenImpl
  let element = parser.dombuilder.createElementForTokenImpl(
    localName, namespace, intendedParent, htmlAttrs, xmlAttrs
  )
  let tagType = parser.toTagType(localName)
  if namespace == Namespace.HTML and tagType in FormAssociatedElements and
      parser.form.isSome and not parser.hasElement(TAG_TEMPLATE) and
      (tagType notin ListedElements or parser.toAtom(TAG_FORM) notin htmlAttrs):
    parser.associateWithForm(element, parser.form.get, intendedParent)
  return element

proc createElementForToken[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    token: Token; namespace: Namespace; intendedParent: Handle): Handle =
  # attrs not adjusted
  return parser.createElementForToken(token.tagname, namespace, intendedParent,
    token.attrs, @[])

proc createHTMLElementForToken[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    token: Token; intendedParent: Handle): Handle =
  # attrs not adjusted
  return parser.createElementForToken(
    token.tagname, Namespace.HTML, intendedParent, token.attrs, @[]
  )

proc pushElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    node: Handle; token: Token[Atom]) =
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

proc insert[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    location: InsertionLocation[Handle]; node: Handle) =
  parser.insertBefore(location.inside, node, location.before)

proc append[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    parent, node: Handle) =
  parser.insertBefore(parent, node, none(Handle))

proc insertForeignElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    token: Token; localName: Atom; namespace: Namespace; stackOnly: bool;
    xmlAttrs: seq[ParsedAttr[Atom]]): Handle =
  let location = parser.appropriatePlaceForInsert()
  let parent = location.inside
  let element = parser.createElementForToken(localName, namespace, parent,
    token.attrs, xmlAttrs)
  if not stackOnly:
    parser.insert(location, element)
  parser.pushElement(element, token)
  return element

proc insertForeignElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    token: Token; namespace: Namespace; stackOnly: bool): Handle =
  parser.insertForeignElement(token, token.tagname, namespace, stackOnly, @[])

proc insertHTMLElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    token: Token): Handle =
  return parser.insertForeignElement(token, Namespace.HTML, false)

proc insertHTMLElementPop[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    token: Token) =
  discard parser.insertHTMLElement(token)
  discard parser.popElement()

# Note: adjustMathMLAttributes and adjustSVGAttributes both include the "adjust
# foreign attributes" step as well.
proc adjustMathMLAttributes[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    htmlAttrs: var Table[Atom, string]; xmlAttrs: var seq[ParsedAttr[Atom]]) =
  var deleted: seq[Atom] = @[]
  for k, v in htmlAttrs.mpairs:
    parser.foreignTable.withValue(k, p):
      xmlAttrs.add((p[].prefix, p[].namespace, p[].localName, v))
      deleted.add(k)
  var v: string = ""
  if htmlAttrs.pop(parser.toAtom(TAG_DEFINITION_URL), v):
    htmlAttrs[parser.strToAtom("definitionURL")] = v
  for k in deleted:
    htmlAttrs.del(k)

proc adjustSVGAttributes[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    htmlAttrs: var Table[Atom, string]; xmlAttrs: var seq[ParsedAttr[Atom]]) =
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

proc insertCharacter(parser: var HTML5Parser; data: string) =
  let location = parser.appropriatePlaceForInsert()
  if location.inside == parser.getDocument():
    return
  parser.insertText(location.inside, data, location.before)

proc insertComment[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    token: Token; position: InsertionLocation[Handle]) =
  let comment = parser.createComment(token.s)
  parser.insert(position, comment)

proc insertComment(parser: var HTML5Parser; token: Token) =
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

const AsciiUpperAlpha = {'A'..'Z'}

proc toLowerAscii(c: char): char {.inline.} =
  if c in AsciiUpperAlpha:
    result = char(uint8(c) xor 0x20'u8)
  else:
    result = c

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

func equalsIgnoreCase(s1, s2: string): bool =
  if s1.len != s2.len:
    return false
  var i = 0
  while i < s1.len:
    if s1[i].toLowerAscii() != s2[i].toLowerAscii():
      return false
    inc i
  true

func quirksConditions(name, pubid, sysid: string; flags: set[TokenFlag]): bool =
  if tfQuirks in flags:
    return true
  if name != "html":
    return true
  if sysid == "http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd":
    return true
  if tfPubid in flags:
    for id in PublicIdentifierEquals:
      if pubid.equalsIgnoreCase(id):
        return true
    for id in PublicIdentifierStartsWith:
      if pubid.startsWithNoCase(id):
        return true
    if tfSysid notin flags:
      for id in SystemIdentifierMissingAndPublicIdentifierStartsWith:
        if pubid.startsWithNoCase(id):
          return true
  return false

func limitedQuirksConditions(pubid: string; flags: set[TokenFlag]): bool =
  if tfPubid notin flags: return false
  for id in PublicIdentifierStartsWithLimited:
    if pubid.startsWithNoCase(id):
      return true
  if tfSysid notin flags: return false
  for id in SystemIdentifierNotMissingAndPublicIdentifierStartsWith:
    if pubid.startsWithNoCase(id):
      return true
  return false

# 13.2.6.2
proc genericRawtextElementParsingAlgorithm(parser: var HTML5Parser;
    token: Token) =
  discard parser.insertHTMLElement(token)
  parser.tokenizer.state = RAWTEXT
  parser.oldInsertionMode = parser.insertionMode
  parser.insertionMode = imInText

proc genericRCDATAElementParsingAlgorithm(parser: var HTML5Parser;
    token: Token) =
  discard parser.insertHTMLElement(token)
  parser.tokenizer.state = RCDATA
  parser.oldInsertionMode = parser.insertionMode
  parser.insertionMode = imInText

# Pop all elements, including the specified tag.
proc popElementsIncl(parser: var HTML5Parser; tags: set[TagType]) =
  while parser.getTagType(parser.popElement()) notin tags:
    discard

proc popElementsIncl(parser: var HTML5Parser; tag: TagType) =
  parser.popElementsIncl({tag})

# Pop all elements, including the specified element.
proc popElementsIncl[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    handle: Handle) =
  while parser.popElement() != handle:
    discard

# Pop all elements, excluding the specified tag.
proc popElementsExcl(parser: var HTML5Parser; tags: set[TagType]) =
  while parser.getTagType(parser.currentNode) notin tags:
    discard parser.popElement()

# https://html.spec.whatwg.org/multipage/parsing.html#closing-elements-that-have-implied-end-tags
proc generateImpliedEndTags(parser: var HTML5Parser) =
  const tags = {
    TAG_DD, TAG_DT, TAG_LI, TAG_OPTGROUP, TAG_OPTION, TAG_P, TAG_RB, TAG_RP,
    TAG_RT, TAG_RTC
  }
  while parser.getTagType(parser.currentNode) in tags:
    discard parser.popElement()

proc generateImpliedEndTags(parser: var HTML5Parser; exclude: TagType) =
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
proc pushActiveFormatting[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    element: Handle; token: Token[Atom]) =
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

proc findOpenElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    element: Handle): int =
  for i, it in parser.openElements:
    if it.element == element:
      return i
  return -1

proc reconstructActiveFormatting[Handle, Atom](
    parser: var HTML5Parser[Handle, Atom]) =
  type State = enum
    sRewind, sAdvance, sCreate
  if parser.activeFormatting.len == 0 or
      parser.activeFormatting[^1][0].isNone or
      parser.findOpenElement(parser.activeFormatting[^1][0].get) != -1:
    return
  var i = parser.activeFormatting.high
  template entry: Option[Handle] = (parser.activeFormatting[i][0])
  var state = sRewind
  while true:
    case state
    of sRewind:
      if i == 0:
        state = sCreate
        continue
      dec i
      if entry.isSome and parser.findOpenElement(entry.get) == -1:
        continue
      state = sAdvance
    of sAdvance:
      inc i
      state = sCreate
    of sCreate:
      let element = parser.insertHTMLElement(parser.activeFormatting[i][1])
      parser.activeFormatting[i] = (
        some(element), parser.activeFormatting[i][1]
      )
      if i != parser.activeFormatting.high:
        state = sAdvance
        continue
      break

proc clearActiveFormattingTillMarker(parser: var HTML5Parser) =
  while parser.activeFormatting.len > 0 and
      parser.activeFormatting.pop()[0].isSome:
    discard

proc isMathMLIntegrationPoint[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    element: Handle): bool =
  if parser.getNamespace(element) != Namespace.MATHML:
    return false
  let tagType = parser.toTagType(parser.getLocalName(element))
  return tagType in {TAG_MI, TAG_MO, TAG_MN, TAG_MS, TAG_MTEXT}

proc isHTMLIntegrationPoint[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    oe: OpenElement[Handle, Atom]): bool =
  let (element, token) = oe
  let localName = parser.getLocalName(element)
  let namespace = parser.getNamespace(element)
  let tagType = parser.toTagType(localName)
  if namespace == Namespace.MATHML:
    if tagType == TAG_ANNOTATION_XML:
      token.attrs.withValue(parser.toAtom(TAG_ENCODING), p):
        return p[].equalsIgnoreCase("text/html") or
          p[].equalsIgnoreCase("application/xhtml+xml")
  elif namespace == Namespace.SVG:
    return tagType in {TAG_FOREIGN_OBJECT, TAG_DESC, TAG_TITLE}
  return false

const AsciiWhitespace = {' ', '\n', '\r', '\t', '\f'}

func until(s: string; c1, c2: char; starti: int): string =
  result = ""
  for i in starti ..< s.len:
    let c = s[i]
    if c == c1 or c == c2:
      break
    result &= c

func extractEncFromMeta(s: string): string =
  var i = 0
  while true: # Loop:
    var j = 0
    while i < s.len:
      let cc = s[i].toLowerAscii()
      template check(cc: char; c: static char) =
        if cc == c:
          inc j
        else:
          j = 0
      case j
      of 0: check cc, 'c'
      of 1: check cc, 'h'
      of 2: check cc, 'a'
      of 3: check cc, 'r'
      of 4: check cc, 's'
      of 5: check cc, 'e'
      of 6: check cc, 't'
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
func findLastActiveFormatting[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
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

proc findLastActiveFormattingAfterMarker(parser: var HTML5Parser;
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

proc isSpecialElement[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    element: Handle): bool =
  let tagType = parser.toTagType(parser.getLocalName(element))
  case parser.getNamespace(element)
  of Namespace.HTML:
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
proc findFurthestBlockAfter(parser: HTML5Parser; stackIndex: int): int =
  for i in stackIndex ..< parser.openElements.len:
    if parser.isSpecialElement(parser.openElements[i].element):
      return i
  return -1

proc findLastActiveFormatting[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    tagTypes: set[TagType]): int =
  for i in countdown(parser.activeFormatting.high, 0):
    let it = parser.activeFormatting[i][0]
    if it.isSome and parser.getTagType(it.get) in tagTypes:
      return i
  return -1

# If true is returned, call "any other end tag".
proc adoptionAgencyAlgorithm[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    token: Token): bool =
  if parser.currentToken.tagname == token.tagname and
      parser.findLastActiveFormatting(parser.currentNode) == -1:
    discard parser.popElement()
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

proc closeP(parser: var HTML5Parser; sure = false) =
  if sure or parser.hasElementInButtonScope(TAG_P):
    parser.generateImpliedEndTags(TAG_P)
    parser.popElementsIncl(TAG_P)

proc newStartTagToken[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    t: TagType): Token[Atom] =
  return Token[Atom](t: ttStartTag, tagname: parser.toAtom(t))

proc otherBodyEndTag[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    tagname: Atom): ParseResult =
  for i in countdown(parser.openElements.high, 0):
    let (node, itToken) = parser.openElements[i]
    if itToken.tagname == tagname:
      parser.generateImpliedEndTags(parser.toTagType(tagname))
      parser.popElementsIncl(node)
      break
    elif parser.isSpecialElement(node):
      break
  return PRES_CONTINUE

proc popTableContext[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  parser.popElementsExcl({TAG_TABLE, TAG_TEMPLATE, TAG_HTML})

proc popTableBodyContext[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  const tags = {TAG_TBODY, TAG_TFOOT, TAG_THEAD, TAG_TEMPLATE, TAG_HTML}
  parser.popElementsExcl(tags)

proc popTableRowContext[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  parser.popElementsExcl({TAG_TR, TAG_TEMPLATE, TAG_HTML})

proc closeCell[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  parser.generateImpliedEndTags()
  parser.popElementsIncl({TAG_TD, TAG_TH})
  parser.clearActiveFormattingTillMarker()
  parser.insertionMode = imInRow

proc processInHTML[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    token: Token; insertionMode: InsertionMode): ParseResult =
  template reprocess(tok: Token): ParseResult =
    parser.processInHTML(tok, parser.insertionMode)

  template reprocess(mode: InsertionMode): ParseResult =
    parser.processInHTML(token, mode)

  var anythingElse = false

  case insertionMode
  of imInitial:
    case token.t
    of ttWhitespace: discard
    of ttComment: parser.insertComment(token, lastChildOf(parser.getDocument()))
    of ttDoctype:
      let doctype = parser.createDocumentType(token.name, token.pubid,
        token.sysid)
      parser.append(parser.getDocument(), doctype)
      if not parser.opts.isIframeSrcdoc:
        if quirksConditions(token.name, token.pubid, token.sysid, token.flags):
          parser.setQuirksMode(QUIRKS)
        elif limitedQuirksConditions(token.pubid, token.flags):
          parser.setQuirksMode(LIMITED_QUIRKS)
      parser.insertionMode = imBeforeHtml
    else:
      parser.setQuirksMode(QUIRKS)
      parser.insertionMode = imBeforeHtml
      return reprocess token

  of imBeforeHtml:
    case token.t
    of ttDoctype, ttWhitespace: discard
    of ttComment: parser.insertComment(token, lastChildOf(parser.getDocument()))
    of ttStartTag:
      if parser.toTagType(token.tagname) == TAG_HTML:
        let intendedParent = parser.getDocument()
        let element = parser.createHTMLElementForToken(token, intendedParent)
        parser.append(parser.getDocument(), element)
        parser.pushElement(element, token)
        parser.insertionMode = imBeforeHead
      else:
        anythingElse = true
    of ttEndTag:
      anythingElse = parser.toTagType(token.tagname) in
        {TAG_HEAD, TAG_BODY, TAG_HTML, TAG_BR}
    else: anythingElse = true
    if anythingElse:
      let element = parser.createHTMLElement()
      parser.append(parser.getDocument(), element)
      let html = parser.newStartTagToken(TAG_HTML)
      parser.pushElement(element, html)
      parser.insertionMode = imBeforeHead
      return reprocess token

  of imBeforeHead:
    case token.t
    of ttWhitespace, ttDoctype: discard
    of ttComment: parser.insertComment(token)
    of ttStartTag:
      case parser.toTagType(token.tagname)
      of TAG_HTML:
        return reprocess imInBody
      of TAG_HEAD:
        parser.head = some((parser.insertHTMLElement(token), token))
        parser.insertionMode = imInHead
      else: anythingElse = true
    of ttEndTag:
      anythingElse = parser.toTagType(token.tagname) in
        {TAG_HEAD, TAG_BODY, TAG_HTML, TAG_BR}
    else: anythingElse = true
    if anythingElse:
      let head = parser.newStartTagToken(TAG_HEAD)
      parser.head = some((parser.insertHTMLElement(head), head))
      parser.insertionMode = imInHead
      return reprocess token

  of imInHead:
    case token.t
    of ttWhitespace: parser.insertCharacter(token.s)
    of ttComment: parser.insertComment(token)
    of ttDoctype: discard
    of ttStartTag:
      case parser.toTagType(token.tagname)
      of TAG_HTML: return reprocess imInBody
      of TAG_BASE, TAG_BASEFONT, TAG_BGSOUND, TAG_LINK:
        parser.insertHTMLElementPop(token)
      of TAG_META:
        parser.insertHTMLElementPop(token)
        token.attrs.withValue(parser.toAtom(TAG_CHARSET), p):
          case parser.setEncoding(p[])
          of SET_ENCODING_CONTINUE:
            discard
          of SET_ENCODING_STOP:
            return PRES_STOP
        do:
          token.attrs.withValue(parser.toAtom(TAG_HTTP_EQUIV), p):
            if p[].equalsIgnoreCase("Content-Type"):
              token.attrs.withValue(parser.toAtom(TAG_CONTENT), p2):
                let cs = extractEncFromMeta(p2[])
                if cs != "":
                  case parser.setEncoding(cs)
                  of SET_ENCODING_CONTINUE:
                    discard
                  of SET_ENCODING_STOP:
                    return PRES_STOP
      of TAG_TITLE: parser.genericRCDATAElementParsingAlgorithm(token)
      of TAG_NOSCRIPT:
        if not parser.opts.scripting:
          discard parser.insertHTMLElement(token)
          parser.insertionMode = imInHeadNoscript
        else:
          parser.genericRawtextElementParsingAlgorithm(token)
      of TAG_NOFRAMES, TAG_STYLE:
        parser.genericRawtextElementParsingAlgorithm(token)
      of TAG_SCRIPT:
        let location = parser.appropriatePlaceForInsert()
        let element = parser.createElementForToken(token, Namespace.HTML,
          location.inside)
        if parser.ctx.isSome:
          parser.setScriptAlreadyStarted(element)
        parser.insert(location, element)
        parser.pushElement(element, token)
        parser.tokenizer.state = SCRIPT_DATA
        parser.oldInsertionMode = parser.insertionMode
        parser.insertionMode = imInText
      of TAG_TEMPLATE:
        discard parser.insertHTMLElement(token)
        parser.activeFormatting.add((none(Handle), nil))
        parser.framesetOk = false
        parser.insertionMode = imInTemplate
        parser.templateModes.add(imInTemplate)
      of TAG_HEAD: discard
      else: anythingElse = true
    of ttEndTag:
      case parser.toTagType(token.tagname)
      of TAG_HEAD:
        discard parser.popElement()
        parser.insertionMode = imAfterHead
      of TAG_TEMPLATE:
        if parser.hasElement(TAG_TEMPLATE):
          parser.generateImpliedEndTagsThoroughly()
          parser.popElementsIncl(TAG_TEMPLATE)
          parser.clearActiveFormattingTillMarker()
          discard parser.templateModes.pop()
          parser.resetInsertionMode()
      of TAG_BODY, TAG_HTML, TAG_BR: anythingElse = true
      else: discard
    else: anythingElse = true
    if anythingElse:
      discard parser.popElement()
      parser.insertionMode = imAfterHead
      return reprocess token

  of imInHeadNoscript:
    case token.t
    of ttDoctype: discard
    of ttStartTag:
      case parser.toTagType(token.tagname)
      of TAG_HEAD, TAG_NOSCRIPT: discard
      of TAG_HTML: return reprocess imInBody
      of TAG_BASEFONT, TAG_BGSOUND, TAG_LINK, TAG_META, TAG_NOFRAMES, TAG_STYLE:
        return reprocess imInHead
      else: anythingElse = true
    of ttEndTag:
      case parser.toTagType(token.tagname)
      of TAG_BR: anythingElse = true
      of TAG_NOSCRIPT:
        discard parser.popElement()
        parser.insertionMode = imInHead
      else: discard
    of ttWhitespace, ttComment: return reprocess imInHead
    else: anythingElse = true
    if anythingElse:
      discard parser.popElement()
      parser.insertionMode = imInHead
      return reprocess token

  of imAfterHead:
    case token.t
    of ttWhitespace: parser.insertCharacter(token.s)
    of ttComment: parser.insertComment(token)
    of ttDoctype: discard
    of ttStartTag:
      case parser.toTagType(token.tagname)
      of TAG_HEAD: discard
      of TAG_HTML: return reprocess imInBody
      of TAG_BODY:
        discard parser.insertHTMLElement(token)
        parser.framesetOk = false
        parser.insertionMode = imInBody
      of TAG_FRAMESET:
        discard parser.insertHTMLElement(token)
        parser.insertionMode = imInFrameset
      of TAG_BASE, TAG_BASEFONT, TAG_BGSOUND, TAG_LINK, TAG_META, TAG_NOFRAMES,
          TAG_SCRIPT, TAG_STYLE, TAG_TEMPLATE, TAG_TITLE:
        let (head, headTok) = parser.head.get
        parser.pushElement(head, headTok)
        result = reprocess imInHead
        if (let i = parser.findOpenElement(head); i != -1):
          parser.openElements.delete(i)
      else: anythingElse = true
    of ttEndTag:
      case parser.toTagType(token.tagname)
      of TAG_TEMPLATE: return reprocess imInHead
      of TAG_BODY, TAG_HTML, TAG_BR: anythingElse = true
      else: discard
    else: anythingElse = true
    if anythingElse:
      discard parser.insertHTMLElement(parser.newStartTagToken(TAG_BODY))
      parser.insertionMode = imInBody
      return reprocess token

  of imInBody:
    case token.t
    of ttWhitespace:
      parser.reconstructActiveFormatting()
      parser.insertCharacter(token.s)
    of ttNull, ttDoctype: discard
    of ttCharacter:
      parser.reconstructActiveFormatting()
      parser.insertCharacter(token.s)
      parser.framesetOk = false
    of ttComment: parser.insertComment(token)
    of ttStartTag:
      case parser.toTagType(token.tagname)
      of TAG_HTML:
        if not parser.hasElement(TAG_TEMPLATE):
          parser.addAttrsIfMissing(parser.openElements[0].element, token.attrs)
      of TAG_BASE, TAG_BASEFONT, TAG_BGSOUND, TAG_LINK, TAG_META, TAG_NOFRAMES,
          TAG_SCRIPT, TAG_STYLE, TAG_TEMPLATE, TAG_TITLE:
        return reprocess imInHead
      of TAG_BODY:
        if parser.openElements.len == 1 or
            parser.getTagType(parser.openElements[1].element) != TAG_BODY or
            parser.hasElement(TAG_TEMPLATE):
          discard
        else:
          parser.framesetOk = false
          parser.addAttrsIfMissing(parser.openElements[1].element, token.attrs)
      of TAG_FRAMESET:
        if parser.openElements.len == 1 or
            parser.getTagType(parser.openElements[1].element) != TAG_BODY or
            not parser.framesetOk:
          discard
        else:
          parser.remove(parser.openElements[1].element)
          while parser.openElements.len > 1:
            discard parser.popElement()
          discard parser.insertHTMLElement(token)
          parser.insertionMode = imInFrameset
      of TAG_ADDRESS, TAG_ARTICLE, TAG_ASIDE, TAG_BLOCKQUOTE, TAG_CENTER,
          TAG_DETAILS, TAG_DIALOG, TAG_DIR, TAG_DIV, TAG_DL, TAG_FIELDSET,
          TAG_FIGCAPTION, TAG_FIGURE, TAG_FOOTER, TAG_HEADER, TAG_HGROUP,
          TAG_MAIN, TAG_MENU, TAG_NAV, TAG_OL, TAG_P, TAG_SEARCH, TAG_SECTION,
          TAG_SUMMARY, TAG_UL:
        parser.closeP()
        discard parser.insertHTMLElement(token)
      of TAG_H1, TAG_H2, TAG_H3, TAG_H4, TAG_H5, TAG_H6:
        parser.closeP()
        if parser.getTagType(parser.currentNode) in HTagTypes:
          discard parser.popElement()
        discard parser.insertHTMLElement(token)
      of TAG_PRE, TAG_LISTING:
        parser.closeP()
        discard parser.insertHTMLElement(token)
        parser.ignoreLF = true
        parser.framesetOk = false
      of TAG_FORM:
        let hasTemplate = parser.hasElement(TAG_TEMPLATE)
        if parser.form.isNone or hasTemplate:
          parser.closeP()
          let element = parser.insertHTMLElement(token)
          if not hasTemplate:
            parser.form = some(element)
      of TAG_LI:
        parser.framesetOk = false
        for node in parser.ropenElements:
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
      of TAG_DD, TAG_DT:
        parser.framesetOk = false
        for node in parser.ropenElements:
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
      of TAG_PLAINTEXT:
        parser.closeP()
        discard parser.insertHTMLElement(token)
        parser.tokenizer.state = PLAINTEXT
      of TAG_BUTTON:
        if parser.hasElementInScope(TAG_BUTTON):
          parser.generateImpliedEndTags()
          parser.popElementsIncl(TAG_BUTTON)
        parser.reconstructActiveFormatting()
        discard parser.insertHTMLElement(token)
        parser.framesetOk = false
      of TAG_A:
        let i = parser.findLastActiveFormattingAfterMarker(TAG_A)
        if i != -1:
          let anchor = parser.activeFormatting[i][0].get
          if parser.adoptionAgencyAlgorithm(token):
            return parser.otherBodyEndTag(token.tagname)
          let j = parser.findLastActiveFormatting(anchor)
          if j != -1:
            parser.activeFormatting.delete(j)
          let k = parser.findOpenElement(anchor)
          if k != -1:
            parser.openElements.delete(k)
        parser.reconstructActiveFormatting()
        let element = parser.insertHTMLElement(token)
        parser.pushActiveFormatting(element, token)
      of TAG_B, TAG_BIG, TAG_CODE, TAG_EM, TAG_FONT, TAG_I, TAG_S, TAG_SMALL,
          TAG_STRIKE, TAG_STRONG, TAG_TT, TAG_U:
        parser.reconstructActiveFormatting()
        let element = parser.insertHTMLElement(token)
        parser.pushActiveFormatting(element, token)
      of TAG_NOBR:
        parser.reconstructActiveFormatting()
        if parser.hasElementInScope(TAG_NOBR):
          if parser.adoptionAgencyAlgorithm(token):
            return parser.otherBodyEndTag(token.tagname)
          parser.reconstructActiveFormatting()
        let element = parser.insertHTMLElement(token)
        parser.pushActiveFormatting(element, token)
      of TAG_APPLET, TAG_MARQUEE, TAG_OBJECT:
        parser.reconstructActiveFormatting()
        discard parser.insertHTMLElement(token)
        parser.activeFormatting.add((none(Handle), nil))
        parser.framesetOk = false
      of TAG_TABLE:
        if parser.quirksMode != QUIRKS:
          parser.closeP()
        discard parser.insertHTMLElement(token)
        parser.framesetOk = false
        parser.insertionMode = imInTable
      of TAG_AREA, TAG_BR, TAG_EMBED, TAG_IMG, TAG_KEYGEN, TAG_WBR:
        parser.reconstructActiveFormatting()
        parser.insertHTMLElementPop(token)
        parser.framesetOk = false
      of TAG_INPUT:
        parser.reconstructActiveFormatting()
        parser.insertHTMLElementPop(token)
        token.attrs.withValue(parser.toAtom(TAG_TYP), p):
          if not p[].equalsIgnoreCase("hidden"):
            parser.framesetOk = false
        do:
          parser.framesetOk = false
      of TAG_PARAM, TAG_SOURCE, TAG_TRACK: parser.insertHTMLElementPop(token)
      of TAG_HR:
        parser.closeP()
        parser.insertHTMLElementPop(token)
        parser.framesetOk = false
      of TAG_IMAGE:
        token.tagname = parser.toAtom(TAG_IMG)
        return reprocess token
      of TAG_TEXTAREA:
        discard parser.insertHTMLElement(token)
        parser.ignoreLF = true
        parser.tokenizer.state = RCDATA
        parser.oldInsertionMode = parser.insertionMode
        parser.framesetOk = false
        parser.insertionMode = imInText
      of TAG_XMP:
        parser.closeP()
        parser.reconstructActiveFormatting()
        parser.framesetOk = false
        parser.genericRawtextElementParsingAlgorithm(token)
      of TAG_IFRAME:
        parser.framesetOk = false
        parser.genericRawtextElementParsingAlgorithm(token)
      of TAG_NOEMBED: parser.genericRawtextElementParsingAlgorithm(token)
      of TAG_NOSCRIPT:
        if parser.opts.scripting:
          parser.genericRawtextElementParsingAlgorithm(token)
        else:
          parser.reconstructActiveFormatting()
          discard parser.insertHTMLElement(token)
      of TAG_SELECT:
        parser.reconstructActiveFormatting()
        discard parser.insertHTMLElement(token)
        parser.framesetOk = false
        const TableInsertionModes = {
          imInTable, imInCaption, imInTableBody, imInRow, imInCell
        }
        if parser.insertionMode in TableInsertionModes:
          parser.insertionMode = imInSelectInTable
        else:
          parser.insertionMode = imInSelect
      of TAG_OPTGROUP, TAG_OPTION:
        if parser.getTagType(parser.currentNode) == TAG_OPTION:
          discard parser.popElement()
        parser.reconstructActiveFormatting()
        discard parser.insertHTMLElement(token)
      of TAG_RB, TAG_RTC:
        if parser.hasElementInScope(TAG_RUBY):
          parser.generateImpliedEndTags()
        discard parser.insertHTMLElement(token)
      of TAG_RP, TAG_RT:
        if parser.hasElementInScope(TAG_RUBY):
          parser.generateImpliedEndTags(TAG_RTC)
        discard parser.insertHTMLElement(token)
      of TAG_MATH:
        parser.reconstructActiveFormatting()
        var xmlAttrs: seq[ParsedAttr[Atom]] = @[]
        parser.adjustMathMLAttributes(token.attrs, xmlAttrs)
        discard parser.insertForeignElement(token, token.tagname,
          Namespace.MATHML, false, xmlAttrs)
        if tfSelfClosing in token.flags:
          discard parser.popElement()
      of TAG_SVG:
        parser.reconstructActiveFormatting()
        var xmlAttrs: seq[ParsedAttr[Atom]] = @[]
        parser.adjustSVGAttributes(token.attrs, xmlAttrs)
        discard parser.insertForeignElement(token, token.tagname, Namespace.SVG,
          false, xmlAttrs)
        if tfSelfClosing in token.flags:
          discard parser.popElement()
      of TAG_CAPTION, TAG_COL, TAG_COLGROUP, TAG_FRAME, TAG_HEAD, TAG_TBODY,
          TAG_TD, TAG_TFOOT, TAG_TH, TAG_THEAD, TAG_TR:
        discard
      else:
        parser.reconstructActiveFormatting()
        discard parser.insertHTMLElement(token)
    of ttEndTag:
      case (let tokTagType = parser.toTagType(token.tagname); tokTagType)
      of TAG_TEMPLATE: return reprocess imInHead
      of TAG_BODY:
        if parser.hasElementInScope(TAG_BODY):
          parser.insertionMode = imAfterBody
      of TAG_HTML:
        if parser.hasElementInScope(TAG_BODY):
          parser.insertionMode = imAfterBody
          return reprocess token
      of TAG_ADDRESS, TAG_ARTICLE, TAG_ASIDE, TAG_BLOCKQUOTE, TAG_BUTTON,
          TAG_CENTER, TAG_DETAILS, TAG_DIALOG, TAG_DIR, TAG_DIV, TAG_DL,
          TAG_FIELDSET, TAG_FIGCAPTION, TAG_FIGURE, TAG_FOOTER, TAG_HEADER,
          TAG_HGROUP, TAG_LISTING, TAG_MAIN, TAG_MENU, TAG_NAV, TAG_OL,
          TAG_PRE, TAG_SEARCH, TAG_SECTION, TAG_SUMMARY, TAG_UL:
        if parser.hasElementInScope(token.tagname):
          parser.generateImpliedEndTags()
          parser.popElementsIncl(tokTagType)
      of TAG_FORM:
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
      of TAG_P:
        if not parser.hasElementInButtonScope(TAG_P):
          discard parser.insertHTMLElement(parser.newStartTagToken(TAG_P))
        parser.closeP(sure = true)
      of TAG_LI:
        if parser.hasElementInListItemScope(TAG_LI):
          parser.generateImpliedEndTags(TAG_LI)
          parser.popElementsIncl(TAG_LI)
      of TAG_DD, TAG_DT:
        if parser.hasElementInScope(tokTagType):
          parser.generateImpliedEndTags(tokTagType)
          parser.popElementsIncl(tokTagType)
      of TAG_H1, TAG_H2, TAG_H3, TAG_H4, TAG_H5, TAG_H6:
        if parser.hasElementInScope(HTagTypes):
          parser.generateImpliedEndTags()
          parser.popElementsIncl(HTagTypes)
      of TAG_A, TAG_B, TAG_BIG, TAG_CODE, TAG_EM, TAG_FONT, TAG_I,
          TAG_NOBR, TAG_S, TAG_SMALL, TAG_STRIKE, TAG_STRONG, TAG_TT,
          TAG_U:
        if parser.adoptionAgencyAlgorithm(token):
          return parser.otherBodyEndTag(token.tagname)
      of TAG_APPLET, TAG_MARQUEE, TAG_OBJECT:
        if parser.hasElementInScope(tokTagType):
          parser.generateImpliedEndTags()
          parser.popElementsIncl(tokTagType)
          parser.clearActiveFormattingTillMarker()
      of TAG_BR: return reprocess parser.newStartTagToken(TAG_BR)
      else: return parser.otherBodyEndTag(token.tagname)

  of imInText:
    case token.t
    of ttCharacter, ttWhitespace: parser.insertCharacter(token.s)
    of ttEndTag:
      discard parser.popElement()
      parser.insertionMode = parser.oldInsertionMode
      if parser.opts.scripting:
        if parser.toTagType(token.tagname) == TAG_SCRIPT:
          return PRES_SCRIPT
    else: assert false # unreachable

  of imInTable:
    case token.t
    of ttCharacter, ttWhitespace, ttNull:
      const CanHaveText = {
        TAG_TABLE, TAG_TBODY, TAG_TFOOT, TAG_THEAD, TAG_TR
      }
      if parser.getTagType(parser.currentNode) in CanHaveText:
        parser.pendingTableChars = ""
        parser.pendingTableCharsWhitespace = true
        parser.oldInsertionMode = parser.insertionMode
        parser.insertionMode = imInTableInText
        return reprocess token
      else: # anything else
        parser.fosterParenting = true
        result = reprocess imInBody
        parser.fosterParenting = false
    of ttComment: parser.insertComment(token)
    of ttDoctype: discard
    of ttStartTag:
      case parser.toTagType(token.tagname)
      of TAG_CAPTION:
        parser.popTableContext()
        parser.activeFormatting.add((none(Handle), nil))
        discard parser.insertHTMLElement(token)
        parser.insertionMode = imInCaption
      of TAG_COLGROUP:
        parser.popTableContext()
        let colgroupTok = parser.newStartTagToken(TAG_COLGROUP)
        discard parser.insertHTMLElement(colgroupTok)
        parser.insertionMode = imInColumnGroup
      of TAG_COL:
        parser.popTableContext()
        let colgroupTok = parser.newStartTagToken(TAG_COLGROUP)
        discard parser.insertHTMLElement(colgroupTok)
        parser.insertionMode = imInColumnGroup
        return reprocess token
      of TAG_TBODY, TAG_TFOOT, TAG_THEAD:
        parser.popTableContext()
        discard parser.insertHTMLElement(token)
        parser.insertionMode = imInTableBody
      of TAG_TD, TAG_TH, TAG_TR:
        parser.popTableContext()
        discard parser.insertHTMLElement(parser.newStartTagToken(TAG_TBODY))
        parser.insertionMode = imInTableBody
        return reprocess token
      of TAG_TABLE:
        if parser.hasElementInTableScope(TAG_TABLE):
          parser.popElementsIncl(TAG_TABLE)
          parser.resetInsertionMode()
          return reprocess token
      of TAG_INPUT:
        token.attrs.withValue(parser.toAtom(TAG_TYP), p):
          if not p[].equalsIgnoreCase("hidden"):
            # anything else
            parser.fosterParenting = true
            result = reprocess imInBody
            parser.fosterParenting = false
          else:
            parser.insertHTMLElementPop(token)
        do:
          anythingElse = true
      of TAG_STYLE, TAG_SCRIPT, TAG_TEMPLATE: return reprocess imInHead
      of TAG_FORM:
        if parser.form.isNone and not parser.hasElement(TAG_TEMPLATE):
          parser.form = some(parser.insertHTMLElement(token))
          discard parser.popElement()
      else: anythingElse = true
    of ttEndTag:
      case parser.toTagType(token.tagname)
      of TAG_TABLE:
        if parser.hasElementInTableScope(TAG_TABLE):
          parser.popElementsIncl(TAG_TABLE)
          parser.resetInsertionMode()
      of TAG_BODY, TAG_CAPTION, TAG_COL, TAG_COLGROUP, TAG_HTML, TAG_TBODY,
          TAG_TD, TAG_TFOOT, TAG_TH, TAG_THEAD, TAG_TR:
        discard
      of TAG_TEMPLATE: return reprocess imInHead
      else: anythingElse = true
    if anythingElse:
      parser.fosterParenting = true
      result = reprocess imInBody
      parser.fosterParenting = false

  of imInTableInText:
    case token.t
    of ttNull: discard
    of ttWhitespace: parser.pendingTableChars &= token.s
    of ttCharacter:
      parser.pendingTableCharsWhitespace = false
      parser.pendingTableChars &= token.s
    else:
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
      return reprocess token

  of imInCaption:
    case token.t
    of ttStartTag:
      case parser.toTagType(token.tagname)
      of TAG_CAPTION, TAG_COL, TAG_COLGROUP, TAG_TBODY, TAG_TD, TAG_TFOOT,
          TAG_TH, TAG_THEAD, TAG_TR:
        if parser.hasElementInTableScope(TAG_CAPTION):
          parser.generateImpliedEndTags()
          parser.popElementsIncl(TAG_CAPTION)
          parser.clearActiveFormattingTillMarker()
          parser.insertionMode = imInTable
          return reprocess token
      else: anythingElse = true
    of ttEndTag:
      case (let tokTagType = parser.toTagType(token.tagname); tokTagType)
      of TAG_CAPTION, TAG_TABLE:
        if parser.hasElementInTableScope(TAG_CAPTION):
          parser.generateImpliedEndTags()
          parser.popElementsIncl(TAG_CAPTION)
          parser.clearActiveFormattingTillMarker()
          parser.insertionMode = imInTable
          if tokTagType == TAG_TABLE:
            return reprocess token
      of TAG_BODY, TAG_COL, TAG_COLGROUP, TAG_HTML, TAG_TBODY, TAG_TD,
          TAG_TFOOT, TAG_TH, TAG_THEAD, TAG_TR:
        discard
      else: anythingElse = true
    else: anythingElse = true
    if anythingElse:
      return reprocess imInBody

  of imInColumnGroup:
    case token.t
    of ttWhitespace: parser.insertCharacter(token.s)
    of ttComment: parser.insertComment(token)
    of ttDoctype: discard
    of ttStartTag:
      case parser.toTagType(token.tagname)
      of TAG_HTML: return reprocess imInBody
      of TAG_COL: parser.insertHTMLElementPop(token)
      of TAG_TEMPLATE: return reprocess imInHead
      else: anythingElse = true
    of ttEndTag:
      case parser.toTagType(token.tagname)
      of TAG_COL: discard
      of TAG_COLGROUP:
        if parser.getTagType(parser.currentNode) == TAG_COLGROUP:
          discard parser.popElement()
          parser.insertionMode = imInTable
      of TAG_TEMPLATE: return reprocess imInHead
      else: anythingElse = true
    else: anythingElse = true
    if anythingElse:
      if parser.getTagType(parser.currentNode) == TAG_COLGROUP:
        discard parser.popElement()
        parser.insertionMode = imInTable
        return reprocess token

  of imInTableBody:
    case token.t
    of ttStartTag:
      case parser.toTagType(token.tagname)
      of TAG_TR:
        parser.popTableBodyContext()
        discard parser.insertHTMLElement(token)
        parser.insertionMode = imInRow
      of TAG_TH, TAG_TD:
        parser.popTableBodyContext()
        discard parser.insertHTMLElement(parser.newStartTagToken(TAG_TR))
        parser.insertionMode = imInRow
        return reprocess token
      of TAG_CAPTION, TAG_COL, TAG_COLGROUP, TAG_TBODY, TAG_TFOOT, TAG_THEAD:
        if parser.hasElementInTableScope({TAG_TBODY, TAG_THEAD, TAG_TFOOT}):
          parser.popTableBodyContext()
          discard parser.popElement()
          parser.insertionMode = imInTable
          return reprocess token
      else: return reprocess imInTable
    of ttEndTag:
      case (let tokTagType = parser.toTagType(token.tagname); tokTagType)
      of TAG_TBODY, TAG_TFOOT, TAG_THEAD, TAG_TABLE:
        if parser.hasElementInTableScope(tokTagType):
          parser.popTableBodyContext()
          discard parser.popElement()
          parser.insertionMode = imInTable
          if tokTagType == TAG_TABLE:
            return reprocess token
      of TAG_BODY, TAG_CAPTION, TAG_COL, TAG_COLGROUP, TAG_HTML, TAG_TD,
          TAG_TH, TAG_TR:
        discard
      else: return reprocess imInTable
    else: return reprocess imInTable

  of imInRow:
    case token.t
    of ttStartTag:
      case parser.toTagType(token.tagname)
      of TAG_TH, TAG_TD:
        parser.popTableRowContext()
        discard parser.insertHTMLElement(token)
        parser.insertionMode = imInCell
        parser.activeFormatting.add((none(Handle), nil))
      of TAG_CAPTION, TAG_COL, TAG_COLGROUP, TAG_TBODY, TAG_TFOOT, TAG_THEAD,
          TAG_TR:
        if parser.hasElementInTableScope(TAG_TR):
          parser.popTableRowContext()
          discard parser.popElement()
          parser.insertionMode = imInTableBody
          return reprocess token
      else: return reprocess imInTable
    of ttEndTag:
      case (let tokTagType = parser.toTagType(token.tagname); tokTagType)
      of TAG_TR:
        if parser.hasElementInTableScope(TAG_TR):
          parser.popTableRowContext()
          discard parser.popElement()
          parser.insertionMode = imInTableBody
      of TAG_TABLE:
        if parser.hasElementInTableScope(TAG_TR):
          parser.popTableRowContext()
          discard parser.popElement()
          parser.insertionMode = imInTableBody
          return reprocess token
      of TAG_TBODY, TAG_TFOOT, TAG_THEAD:
        if parser.hasElementInTableScope({tokTagType, TAG_TR}):
          parser.popTableRowContext()
          discard parser.popElement()
          parser.insertionMode = imInTableBody
          return reprocess token
      of TAG_BODY, TAG_CAPTION, TAG_COL, TAG_COLGROUP, TAG_HTML, TAG_TD,
          TAG_TH:
        discard
      else: return reprocess imInTable
    else: return reprocess imInTable

  of imInCell:
    case token.t
    of ttStartTag:
      case parser.toTagType(token.tagname)
      of TAG_CAPTION, TAG_COL, TAG_COLGROUP, TAG_TBODY, TAG_TD, TAG_TFOOT,
          TAG_TH, TAG_THEAD, TAG_TR:
        if parser.hasElementInTableScope({TAG_TD, TAG_TH}):
          parser.closeCell()
          return reprocess token
      else: return reprocess imInBody
    of ttEndTag:
      case (let tokTagType = parser.toTagType(token.tagname); tokTagType)
      of TAG_TD, TAG_TH:
        if parser.hasElementInTableScope(tokTagType):
          parser.generateImpliedEndTags()
          parser.popElementsIncl(tokTagType)
          parser.clearActiveFormattingTillMarker()
          parser.insertionMode = imInRow
      of TAG_BODY, TAG_CAPTION, TAG_COL, TAG_COLGROUP, TAG_HTML: discard
      of TAG_TABLE, TAG_TBODY, TAG_TFOOT, TAG_THEAD, TAG_TR:
        if parser.hasElementInTableScope(tokTagType):
          parser.closeCell()
          return reprocess token
      else: return reprocess imInBody
    else: return reprocess imInBody

  of imInSelect:
    case token.t
    of ttCharacter, ttWhitespace: parser.insertCharacter(token.s)
    of ttComment: parser.insertComment(token)
    of ttStartTag:
      case parser.toTagType(token.tagname)
      of TAG_HTML: return reprocess imInBody
      of TAG_OPTION:
        if parser.getTagType(parser.currentNode) == TAG_OPTION:
          discard parser.popElement()
        discard parser.insertHTMLElement(token)
      of TAG_OPTGROUP:
        if parser.getTagType(parser.currentNode) == TAG_OPTION:
          discard parser.popElement()
        if parser.getTagType(parser.currentNode) == TAG_OPTGROUP:
          discard parser.popElement()
        discard parser.insertHTMLElement(token)
      of TAG_HR:
        if parser.getTagType(parser.currentNode) == TAG_OPTION:
          discard parser.popElement()
        if parser.getTagType(parser.currentNode) == TAG_OPTGROUP:
          discard parser.popElement()
        parser.insertHTMLElementPop(token)
      of TAG_SELECT:
        if parser.hasElementInSelectScope(TAG_SELECT):
          parser.popElementsIncl(TAG_SELECT)
          parser.resetInsertionMode()
      of TAG_INPUT, TAG_KEYGEN, TAG_TEXTAREA:
        if parser.hasElementInSelectScope(TAG_SELECT):
          parser.popElementsIncl(TAG_SELECT)
          parser.resetInsertionMode()
          return reprocess token
      of TAG_SCRIPT, TAG_TEMPLATE: return reprocess imInHead
      else: discard
    of ttEndTag:
      case parser.toTagType(token.tagname)
      of TAG_OPTGROUP:
        if parser.getTagType(parser.currentNode) == TAG_OPTION:
          if parser.openElements.len > 1:
            let tagType = parser.getTagType(parser.openElements[^2].element)
            if tagType == TAG_OPTGROUP:
              discard parser.popElement()
        if parser.getTagType(parser.currentNode) == TAG_OPTGROUP:
          discard parser.popElement()
      of TAG_OPTION:
        if parser.getTagType(parser.currentNode) == TAG_OPTION:
          discard parser.popElement()
      of TAG_SELECT:
        if parser.hasElementInSelectScope(TAG_SELECT):
          parser.popElementsIncl(TAG_SELECT)
          parser.resetInsertionMode()
      of TAG_TEMPLATE: return reprocess imInHead
      else: discard
    else: discard

  of imInSelectInTable:
    case token.t
    of ttStartTag:
      case parser.toTagType(token.tagname)
      of TAG_CAPTION, TAG_TABLE, TAG_TBODY, TAG_TFOOT, TAG_THEAD, TAG_TR,
          TAG_TD, TAG_TH:
        parser.popElementsIncl(TAG_SELECT)
        parser.resetInsertionMode()
        return reprocess token
      else: discard
    of ttEndTag:
      case (let tokTagType = parser.toTagType(token.tagname); tokTagType)
      of TAG_CAPTION, TAG_TABLE, TAG_TBODY, TAG_TFOOT, TAG_THEAD, TAG_TR,
          TAG_TD, TAG_TH:
        if parser.hasElementInTableScope(tokTagType):
          parser.popElementsIncl(TAG_SELECT)
          parser.resetInsertionMode()
          return reprocess token
      else: discard
    else: discard
    return reprocess imInSelect

  of imInTemplate:
    case token.t
    of ttCharacter, ttWhitespace, ttNull, ttDoctype, ttComment:
      return reprocess imInBody
    of ttStartTag:
      case parser.toTagType(token.tagname)
      of TAG_BASE, TAG_BASEFONT, TAG_BGSOUND, TAG_LINK, TAG_META, TAG_NOFRAMES,
          TAG_SCRIPT, TAG_STYLE, TAG_TEMPLATE, TAG_TITLE:
        return reprocess imInHead
      of TAG_CAPTION, TAG_COLGROUP, TAG_TBODY, TAG_TFOOT, TAG_THEAD:
        discard parser.templateModes.pop()
        parser.templateModes.add(imInTable)
        parser.insertionMode = imInTable
        return reprocess token
      of TAG_COL:
        discard parser.templateModes.pop()
        parser.templateModes.add(imInColumnGroup)
        parser.insertionMode = imInColumnGroup
        return reprocess token
      of TAG_TR:
        discard parser.templateModes.pop()
        parser.templateModes.add(imInTableBody)
        parser.insertionMode = imInTableBody
        return reprocess token
      of TAG_TD, TAG_TH:
        discard parser.templateModes.pop()
        parser.templateModes.add(imInRow)
        parser.insertionMode = imInRow
        return reprocess token
      else:
        discard parser.templateModes.pop()
        parser.templateModes.add(imInBody)
        parser.insertionMode = imInBody
        return reprocess token
    of ttEndTag:
      if parser.toTagType(token.tagname) == TAG_TEMPLATE:
        return reprocess imInHead

  of imAfterBody:
    case token.t
    of ttWhitespace: return reprocess imInBody
    of ttComment:
      parser.insertComment(token, lastChildOf(parser.openElements[0]))
    of ttDoctype: discard
    of ttStartTag:
      if parser.toTagType(token.tagname) == TAG_HTML:
        return reprocess imInBody
      parser.insertionMode = imInBody
      return reprocess token
    of ttEndTag:
      if parser.toTagType(token.tagname) == TAG_HTML:
        if parser.ctx.isNone:
          parser.insertionMode = imAfterAfterBody
      else:
        parser.insertionMode = imInBody
        return reprocess token
    else:
      parser.insertionMode = imInBody
      return reprocess token

  of imInFrameset:
    case token.t
    of ttWhitespace: parser.insertCharacter(token.s)
    of ttComment: parser.insertComment(token)
    of ttDoctype: discard
    of ttStartTag:
      case parser.toTagType(token.tagname)
      of TAG_HTML: return reprocess imInBody
      of TAG_FRAMESET: discard parser.insertHTMLElement(token)
      of TAG_FRAME: parser.insertHTMLElementPop(token)
      of TAG_NOFRAMES: return reprocess imInHead
      else: discard
    of ttEndTag:
      if parser.toTagType(token.tagname) == TAG_FRAMESET:
        if parser.getTagType(parser.currentNode) != TAG_HTML:
          discard parser.popElement()
        if parser.ctx.isNone and
            parser.getTagType(parser.currentNode) != TAG_FRAMESET:
          parser.insertionMode = imAfterFrameset
    else: discard

  of imAfterFrameset:
    case token.t
    of ttWhitespace: parser.insertCharacter(token.s)
    of ttComment: parser.insertComment(token)
    of ttStartTag:
      case parser.toTagType(token.tagname)
      of TAG_HTML: return reprocess imInBody
      of TAG_NOFRAMES: return reprocess imInHead
      else: discard
    of ttEndTag:
      if parser.toTagType(token.tagname) == TAG_HTML:
        parser.insertionMode = imAfterAfterFrameset
    else: discard

  of imAfterAfterBody:
    case token.t
    of ttComment: parser.insertComment(token, lastChildOf(parser.getDocument()))
    of ttDoctype, ttWhitespace: return reprocess imInBody
    of ttStartTag:
      if parser.toTagType(token.tagname) == TAG_HTML:
        return reprocess imInBody
      parser.insertionMode = imInBody
      return reprocess token
    else:
      parser.insertionMode = imInBody
      return reprocess token

  of imAfterAfterFrameset:
    case token.t
    of ttComment: parser.insertComment(token, lastChildOf(parser.getDocument()))
    of ttDoctype, ttWhitespace: return reprocess imInBody
    of ttStartTag:
      case parser.toTagType(token.tagname)
      of TAG_HTML: return reprocess imInBody
      of TAG_NOFRAMES: return reprocess imInHead
      else: discard
    else: discard
  return PRES_CONTINUE

proc processEOF[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  var insertionMode = parser.insertionMode
  if insertionMode == imInitial:
    parser.setQuirksMode(QUIRKS)
    insertionMode = imBeforeHtml
  if insertionMode == imBeforeHtml:
    let element = parser.createHTMLElement()
    parser.append(parser.getDocument(), element)
    let html = parser.newStartTagToken(TAG_HTML)
    parser.pushElement(element, html)
    insertionMode = imBeforeHead
  if insertionMode == imBeforeHead:
    let head = parser.newStartTagToken(TAG_HEAD)
    parser.head = some((parser.insertHTMLElement(head), head))
    insertionMode = imInHead
  if insertionMode == imInHeadNoscript:
    discard parser.popElement()
    insertionMode = imInHead
  if insertionMode == imInHead:
    discard parser.popElement()
    insertionMode = imAfterHead
  if insertionMode == imAfterHead:
    discard parser.insertHTMLElement(parser.newStartTagToken(TAG_BODY))
    insertionMode = imInBody
  case insertionMode
  of imInBody, imInCaption, imInColumnGroup, imInCell, imInSelect,
      imInSelectInTable, imInTable, imInTableBody, imInRow, imInTemplate:
    if parser.templateModes.len > 0 and parser.hasElement(TAG_TEMPLATE):
      parser.popElementsIncl(TAG_TEMPLATE)
      parser.clearActiveFormattingTillMarker()
      discard parser.templateModes.pop()
      parser.resetInsertionMode()
      parser.processEOF()
  of imInText:
    if parser.getTagType(parser.currentNode) == TAG_SCRIPT:
      parser.setScriptAlreadyStarted(parser.currentNode)
    discard parser.popElement()
    parser.insertionMode = parser.oldInsertionMode
    parser.processEOF()
  of imInTableInText:
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
    parser.processEOF()
  else: discard

proc processHTMLForeignTag[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    token: Token): ParseResult =
  while not parser.isMathMLIntegrationPoint(parser.currentNode) and
      not parser.isHTMLIntegrationPoint(parser.currentNodeToken) and
      parser.getNamespace(parser.currentNode) != Namespace.HTML:
    discard parser.popElement()
  return parser.processInHTML(token, parser.insertionMode)

proc otherForeignStartTag[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    token: Token): ParseResult =
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
    discard parser.popElement()
    if namespace == Namespace.SVG and parser.toTagType(tagname) == TAG_SCRIPT:
      return PRES_SCRIPT
  return PRES_CONTINUE

proc otherForeignEndTag[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    token: Token): ParseResult =
  for i in countdown(parser.openElements.high, 0): # loop
    if i == 0: # fragment case
      assert parser.ctx.isSome
      break
    let (node, nodeToken) = parser.openElements[i]
    if i != parser.openElements.high and
        parser.getNamespace(node) == Namespace.HTML:
      return parser.processInHTML(token, parser.insertionMode)
    if nodeToken.tagname == token.tagname:
      # Compare the start tag token, since it is guaranteed to be lower case.
      # (The local name might have been adjusted to a non-lower-case string.)
      parser.popElementsIncl(node)
      break
  return PRES_CONTINUE

proc processInForeign[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    token: Token): ParseResult =
  case token.t
  of ttNull: parser.insertCharacter("\uFFFD")
  of ttWhitespace: parser.insertCharacter(token.s)
  of ttCharacter:
    parser.insertCharacter(token.s)
    parser.framesetOk = false
  of ttComment: parser.insertComment(token)
  of ttDoctype: discard
  of ttStartTag:
    case parser.toTagType(token.tagname)
    of TAG_B, TAG_BIG, TAG_BLOCKQUOTE, TAG_BODY, TAG_BR, TAG_CENTER, TAG_CODE,
        TAG_DD, TAG_DIV, TAG_DL, TAG_DT, TAG_EM, TAG_EMBED, TAG_H1, TAG_H2,
        TAG_H3, TAG_H4, TAG_H5, TAG_H6, TAG_HEAD, TAG_HR, TAG_I, TAG_IMG,
        TAG_LI, TAG_LISTING, TAG_MENU, TAG_META, TAG_NOBR, TAG_OL, TAG_P,
        TAG_PRE, TAG_RUBY, TAG_S, TAG_SMALL, TAG_SPAN, TAG_STRONG, TAG_STRIKE,
        TAG_SUB, TAG_SUP, TAG_TABLE, TAG_TT, TAG_U, TAG_UL, TAG_VAR:
      return parser.processHTMLForeignTag(token)
    of TAG_FONT:
      let atColor = parser.toAtom(TAG_COLOR)
      let atFace = parser.toAtom(TAG_FACE)
      let atSize = parser.toAtom(TAG_SIZE)
      if atColor in token.attrs or atFace in token.attrs or
          atSize in token.attrs:
        return parser.processHTMLForeignTag(token)
      # fall through
    else: discard
    return parser.otherForeignStartTag(token)
  of ttEndTag:
    case parser.toTagType(token.tagname)
    of TAG_BR, TAG_P: return parser.processHTMLForeignTag(token)
    of TAG_SCRIPT:
      let namespace = parser.getNamespace(parser.currentNode)
      let localName = parser.currentToken.tagname
      # Any atom corresponding to the string "script" must have the same
      # value as TAG_SCRIPT, so this is correct.
      if namespace == Namespace.SVG and
          parser.toTagType(localName) == TAG_SCRIPT:
        discard parser.popElement()
        return PRES_SCRIPT
      # fall through
    else: discard
    return parser.otherForeignEndTag(token)
  return PRES_CONTINUE

proc processToken[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    token: Token[Atom]): ParseResult =
  if parser.ignoreLF:
    parser.ignoreLF = false
    if token.t == ttWhitespace and token.s[0] == '\n':
      if token.s.len == 1:
        return PRES_CONTINUE
      else:
        for i in 1 ..< token.s.len:
          token.s[i - 1] = token.s[i]
        token.s.setLen(token.s.high)
  if parser.openElements.len == 0 or
      parser.getNamespace(parser.adjustedCurrentNode) == Namespace.HTML:
    return parser.processInHTML(token, parser.insertionMode)
  let oe = parser.adjustedCurrentNodeToken
  let oeTagType = parser.toTagType(oe.token.tagname)
  let namespace = parser.getNamespace(oe.element)
  const CharacterToken = {ttCharacter, ttWhitespace, ttNull}
  let mmlnoatoms = {TAG_MGLYPH, TAG_MALIGNMARK}
  let ismmlip = parser.isMathMLIntegrationPoint(oe.element)
  let ishtmlip = parser.isHTMLIntegrationPoint(oe)
  if token.t == ttStartTag and (
        let tagType = parser.toTagType(token.tagname)
        ismmlip and tagType notin mmlnoatoms or ishtmlip or
        namespace == Namespace.MATHML and oeTagType == TAG_ANNOTATION_XML and
          tagType == TAG_SVG
      ) or token.t in CharacterToken and (ismmlip or ishtmlip):
    return parser.processInHTML(token, parser.insertionMode)
  return parser.processInForeign(token)

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

proc initHTML5Parser*[Handle, Atom](dombuilder: DOMBuilder[Handle, Atom];
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
      t: ttStartTag,
      tagname: ctxInit.startTagName
    ))
    parser.ctx = some(ctx)
  for (element, tagName) in opts.openElementsInit:
    let it = (element, Token[Atom](t: ttStartTag, tagname: tagName))
    parser.openElements.add(it)
  parser.createCaseTable()
  parser.createAdjustedTable()
  parser.createForeignTable()
  if opts.pushInTemplate:
    parser.templateModes.add(imInTemplate)
  if opts.openElementsInit.len > 0:
    parser.resetInsertionMode()
  let tokstate = opts.initialTokenizerState
  parser.tokenizer = newTokenizer[Handle, Atom](dombuilder, tokstate)
  return parser

proc parseChunk*[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
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
      #      case, peekBuf is a prefix of at least one named character
      #      reference; obviously these can not be </script> tags either,
      #      since they all match the regex `&[a-zA-Z]+'.
      # pres == PRES_STOP: unreachable for reasons almost identical to those
      # outlined in PRES_SCRIPT. PRES_STOP can only be returned after a <meta>
      # tag is processed; just like with end tags, the tokenizer cannot emit
      # start tags in finish().
  parser.processEOF()
  while parser.openElements.len > 0:
    discard parser.popElement()
