import std/algorithm
import std/options
import std/tables

import dombuilder
import htmltokenizer
import tags

# Export these so that htmlparseriface works seamlessly.
export dombuilder
export options
export tags

# Heavily inspired by html5ever's TreeSink design.
type
  HTML5ParserOpts*[Handle, Atom] = object
    isIframeSrcdoc*: bool ## Is the document an iframe srcdoc?
    scripting*: bool ## Is scripting enabled for this document?
      ## Note: in the spec, this has four values, but Chame distills these
      ## to two.  "Inert"/"Fragment" are reflected by scripting when
      ## ctx.isSome, otherwise "Normal"/"Disabled" are assumed.
    ctxIsIntegrationPoint*: bool ## Must be set if ctx.isSome and ctx has
      ## an "encoding" attribute that case-insensitively matches
      ## either "text/html" or "application/xhtml+xml".
    ctx*: Option[Handle] ## Context element for fragment parsing.
      ## When set to some Handle, the fragment case is used while parsing.
    openElementsInit*: Option[Handle] ## Node to push to the stack of open
      ## elements.  This should be set to a new HTML element in fragment
      ## parsing mode, and left empty otherwise.
    formInit*: Option[Handle] ## Initial state of the parser's form pointer.

  OpenElement[Handle, Atom] = object
    element: Handle
    startTagName: Atom
    integrationPoint: bool

type
  Formatting[Handle, Atom] = ref object
    element: Handle
    startTagName: Atom
    attrs: ParsedAttrs[Atom]

  HTML5Parser*[Handle, Atom] = object
    ctx: Option[OpenElement[Handle, Atom]]
    openElements: seq[OpenElement[Handle, Atom]]
    templateModes: seq[InsertionMode]
    head: Option[Handle]
    tok: Tokenizer[Handle, Atom]
    form: Option[Handle]
    quirksMode: QuirksMode
    insertionMode: InsertionMode
    oldInsertionMode: InsertionMode
    fosterParenting: bool
    framesetOk: bool
    ignoreLF: bool
    pendingTableCharsWhitespace: bool
    scripting: bool
    isIframeSrcdoc: bool
    activeFormatting: seq[Formatting[Handle, Atom]] # nil => marker
    pendingTableChars: string
    caseTable: Table[Atom, Atom]
    adjustedTable: Table[Atom, Atom]
    foreignTable: Table[Atom, Namespace]

  InsertionLocation[Handle] = object
    inside: Handle
    before: Option[Handle]

# 13.2.4.1
  InsertionMode = enum
    imInitial, imBeforeHtml, imBeforeHead, imInHead, imInHeadNoscript,
    imAfterHead, imInBody, imText, imInTable, imInTableInText, imInCaption,
    imInColumnGroup, imInTableBody, imInRow, imInCell, imInTemplate,
    imAfterBody, imInFrameset, imAfterFrameset, imAfterAfterBody,
    imAfterAfterFrameset

type ParseChunkResult* = enum
  ## Result of parsing the passed chunk.
  ## pcrContinue is returned when it is OK to continue parsing.
  ##
  ## pcrStop is returned when the parser has been stopped from
  ## setEncodingImpl.
  ##
  ## pcrScript is returned when a script end tag is encountered.  For
  ## implementations that do not support scripting, this can be treated
  ## equivalently to pcrContinue.
  ##
  ## Implementations that *do* support scripting and implement `document.write`
  ## can instead use pcrScript to process string injected into the input
  ## stream by `document.write` before continuing with parsing from the
  ## network stream. In this case, script elements should be stored in e.g. the
  ## DOM builder from `elementPoppedImpl`, and processed accordingly after
  ## pcrScript has been returned.
  pcrContinue
  pcrStop
  pcrScript

# DOMBuilder interface functions
template dombuilder[Handle, Atom](parser: HTML5Parser[Handle, Atom]):
    DOMBuilder[Handle, Atom] =
  parser.tok.dombuilder

proc strToAtom[Handle, Atom](parser: HTML5Parser[Handle, Atom]; s: string):
    Atom =
  mixin strToAtomImpl
  return parser.dombuilder.strToAtomImpl(s)

proc namespaceToAtom[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    ns: Namespace): Atom =
  mixin namespaceToAtomImpl
  parser.dombuilder.namespaceToAtomImpl(ns)

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
    return seContinue

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
  if parser.getNamespace(handle) != nsHTML:
    return ttUnknown
  return parser.toTagType(parser.getLocalName(handle))

proc createHTMLElement[Handle, Atom](parser: HTML5Parser[Handle, Atom]):
    Handle =
  mixin createHTMLElementImpl
  return parser.dombuilder.createHTMLElementImpl()

proc insertCommentImpl[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    parent: Handle; before: Option[Handle]) =
  mixin insertCommentImpl
  parser.dombuilder.insertCommentImpl(parent, parser.tok.tagNameBuf, before)

proc appendDocumentType[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    name, publicId, systemId: string) =
  mixin appendDocumentTypeImpl
  parser.dombuilder.appendDocumentTypeImpl(name, publicId, systemId)

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
    element: Handle; attrs: ParsedAttrs[Atom]) =
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

const AsciiUpperAlpha = {'A'..'Z'}

proc toLowerAscii(c: char): char {.inline.} =
  if c in AsciiUpperAlpha:
    char(uint8(c) xor 0x20'u8)
  else:
    c

proc startsWithNoCase(str, prefix: string): bool =
  if str.len < prefix.len:
    return false
  # prefix.len is always lower
  var i = 0
  while i != prefix.len:
    if str[i].toLowerAscii() != prefix[i].toLowerAscii():
      return false
    inc i
  true

proc equalsIgnoreCase(s1, s2: string): bool =
  if s1.len != s2.len:
    return false
  var i = 0
  while i < s1.len:
    if s1[i].toLowerAscii() != s2[i].toLowerAscii():
      return false
    inc i
  true

# https://html.spec.whatwg.org/multipage/parsing.html#reset-the-insertion-mode-appropriately
proc resetInsertionMode0(parser: var HTML5Parser): InsertionMode =
  for i in countdown(parser.openElements.high, 0):
    var node = parser.openElements[i]
    let last = i == 0
    if last and parser.ctx.isSome:
      node = parser.ctx.get
    let tagType = parser.getTagType(node.element)
    case tagType
    of ttTd, ttTh:
      if not last:
        return imInCell
    of ttTr: return imInRow
    of ttTbody, ttThead, ttTfoot: return imInTableBody
    of ttCaption: return imInCaption
    of ttColgroup: return imInColumnGroup
    of ttTable: return imInTable
    of ttTemplate: return parser.templateModes[^1]
    of ttHead:
      if not last:
        return imInHead
    of ttBody: return imInBody
    of ttFrameset: return imInFrameset
    of ttHtml:
      if parser.head.isNone:
        return imBeforeHead
      else:
        return imAfterHead
    else: discard
  return imInBody

proc resetInsertionMode(parser: var HTML5Parser) =
  parser.insertionMode = parser.resetInsertionMode0()

proc currentNodeToken[Handle, Atom](parser: HTML5Parser[Handle, Atom]):
    OpenElement[Handle, Atom] =
  return parser.openElements[^1]

proc currentNode[Handle, Atom](parser: HTML5Parser[Handle, Atom]): Handle =
  return parser.currentNodeToken.element

proc currentTagName[Handle, Atom](parser: HTML5Parser[Handle, Atom]): Atom =
  return parser.currentNodeToken.startTagName

proc adjustedCurrentNodeToken[Handle, Atom](parser: HTML5Parser[Handle, Atom]):
    OpenElement[Handle, Atom] =
  if parser.ctx.isSome and parser.openElements.len == 1:
    return parser.ctx.get
  else:
    return parser.currentNodeToken

proc adjustedCurrentNode[Handle, Atom](parser: HTML5Parser[Handle, Atom]):
    Handle =
  return parser.adjustedCurrentNodeToken.element

proc lastElementOfTag[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    tagType: TagType): tuple[element: Option[Handle], pos: int] =
  for i in countdown(parser.openElements.high, 0):
    let element = parser.openElements[i].element
    if parser.getTagType(element) == tagType:
      return (some(element), i)
  return (none(Handle), -1)

proc lastChildOf[Handle](n: Handle): InsertionLocation[Handle] =
  InsertionLocation[Handle](inside: n, before: none(Handle))

proc lastChildOf[Handle, Atom](n: OpenElement[Handle, Atom]):
    InsertionLocation[Handle] =
  lastChildOf(n.element)

# https://html.spec.whatwg.org/multipage/#appropriate-place-for-inserting-a-node
proc appropriatePlaceForInsert[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: Handle): InsertionLocation[Handle] =
  assert parser.getTagType(parser.openElements[0].element) == ttHtml
  let targetTagType = parser.getTagType(target)
  const FosterTagTypes = {ttTable, ttTbody, ttTfoot, ttThead, ttTr}
  if parser.fosterParenting and targetTagType in FosterTagTypes:
    let lastTemplate = parser.lastElementOfTag(ttTemplate)
    let lastTable = parser.lastElementOfTag(ttTable)
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
  if parser.getTagType(result.inside) == ttTemplate:
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
  ttApplet, ttCaption, ttHtml, ttTable, ttTd, ttTh, ttMarquee,
  ttObject, ttSelect, ttTemplate # (+ SVG, MathML)
}

proc hasElementInScopeWithXML[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: Handle; list: set[TagType]): bool =
  for element in parser.ropenElements:
    if element == target:
      return true
    let localName = parser.getLocalName(element)
    let tagType = parser.toTagType(localName)
    case parser.getNamespace(element)
    of nsHTML:
      if tagType in list:
        return false
    of nsMathML:
      const elements = {ttMi, ttMo, ttMn, ttMs, ttMtext, ttAnnotationXml}
      if tagType in elements:
        return false
    of nsSVG:
      const elements = {ttForeignObject, ttDesc, ttTitle}
      if tagType in elements:
        return false
    else: discard
  return false

proc hasElementInScopeWithXML[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: TagType; list: set[TagType]): bool =
  for element in parser.ropenElements:
    let tagType = parser.toTagType(parser.getLocalName(element))
    case parser.getNamespace(element)
    of nsHTML:
      if tagType == target or target == ttH1 and tagType in ttH2 .. ttH6:
        return true
      if tagType in list:
        return false
    of nsMathML:
      const elements = {ttMi, ttMo, ttMn, ttMs, ttMtext, ttAnnotationXml}
      if tagType in elements:
        return false
    of nsSVG:
      const elements = {ttForeignObject, ttDesc, ttTitle}
      if tagType in elements:
        return false
    else: discard
  return false

proc hasElementInScope[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: Handle): bool =
  return parser.hasElementInScopeWithXML(target, Scope)

proc hasElementInScope[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: TagType): bool =
  return parser.hasElementInScopeWithXML(target, Scope)

proc hasElementInListItemScope[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: TagType): bool =
  const ListItemScope = Scope + {ttOl, ttUl}
  return parser.hasElementInScopeWithXML(target, ListItemScope)

proc hasElementInButtonScope[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: TagType): bool =
  const ButtonScope = Scope + {ttButton}
  return parser.hasElementInScopeWithXML(target, ButtonScope)

proc hasElementInTableScope[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: set[TagType]): bool =
  for element in parser.ropenElements:
    let tagType = parser.getTagType(element)
    if tagType in target:
      return true
    if tagType in {ttHtml, ttTable, ttTemplate}:
      break
  return false

proc hasElementInTableScope[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    target: TagType): bool =
  return parser.hasElementInTableScope({target})

proc find[Atom](attrs: ParsedAttrs[Atom]; atom: Atom): int =
  attrs.binarySearch(atom, proc(a: ParsedAttr[Atom]; b: Atom): int =
    cmp(a.name, b)
  )

proc findAttr[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    tagType: TagType): int =
  parser.tok.attrs.find(parser.toAtom(tagType))

proc contains[Atom](attrs: ParsedAttrs[Atom]; atom: Atom): bool =
  attrs.find(atom) >= 0

proc sortAttrs[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  mixin sortAttrsImpl
  parser.dombuilder.sortAttrsImpl(parser.tok.attrs)

proc createElement[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    localName: Atom; namespace: Namespace; intendedParent: Handle;
    attrs: sink ParsedAttrs[Atom]): Handle =
  mixin createElementForTokenImpl
  let tagType = parser.toTagType(localName)
  let shouldAssociate =
    namespace == nsHTML and tagType in FormAssociatedElements and
    parser.form.isSome and not parser.hasElement(ttTemplate) and
    (tagType notin ListedElements or parser.toAtom(ttForm) notin attrs)
  let element = parser.dombuilder.createElementForTokenImpl(localName,
    namespace, intendedParent, attrs)
  if shouldAssociate:
    parser.associateWithForm(element, parser.form.get, intendedParent)
  element

proc createHTMLElement[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    tagname: Atom; intendedParent: Handle; attrs: sink ParsedAttrs[Atom]):
    Handle =
  # attrs not adjusted
  parser.createElement(tagname, nsHTML, intendedParent, attrs)

proc pushElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    node: Handle; tagname: Atom; integrationPoint: bool) =
  parser.openElements.add(OpenElement[Handle, Atom](
    element: node,
    startTagName: tagname,
    integrationPoint: integrationPoint
  ))
  let node = parser.adjustedCurrentNode()
  parser.tok.hasnonhtml = parser.getNamespace(node) != nsHTML

proc pushHTMLElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    node: Handle) =
  parser.pushElement(node, parser.getLocalName(node), false)

proc popElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom]): Handle =
  mixin elementPoppedImpl
  result = parser.openElements.pop().element
  when compiles(parser.dombuilder.elementPoppedImpl(result)):
    parser.dombuilder.elementPoppedImpl(result)
  if parser.openElements.len == 0:
    parser.tok.hasnonhtml = false
  else:
    let node = parser.adjustedCurrentNode()
    parser.tok.hasnonhtml = parser.getNamespace(node) != nsHTML

proc insert[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    location: InsertionLocation[Handle]; node: Handle) =
  parser.insertBefore(location.inside, node, location.before)

proc append[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    parent, node: Handle) =
  parser.insertBefore(parent, node, none(Handle))

proc insertForeignElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    localName, tagname: Atom; namespace: Namespace; stackOnly: bool;
    attrs: sink ParsedAttrs[Atom]): Handle =
  var integrationPoint = false
  if namespace == nsMathML and localName == parser.toAtom(ttAnnotationXml):
    let i = attrs.find(parser.toAtom(ttEncoding))
    if i >= 0:
      let s = attrs[i].value
      integrationPoint = s.equalsIgnoreCase("text/html") or
        s.equalsIgnoreCase("application/xhtml+xml")
  let location = parser.appropriatePlaceForInsert()
  let parent = location.inside
  let element = parser.createElement(localName, namespace, parent, attrs)
  if not stackOnly:
    parser.insert(location, element)
  parser.pushElement(element, tagname, integrationPoint)
  return element

proc insertForeignElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    namespace: Namespace; stackOnly: bool): Handle =
  let tagname = parser.tok.tagname
  parser.insertForeignElement(tagname, tagname, namespace, stackOnly,
    move(parser.tok.attrs))

proc insertHTMLElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    tagname: Atom; attrs: ParsedAttrs[Atom]): Handle =
  parser.insertForeignElement(tagname, tagname, nsHTML, false, attrs)

proc insertHTMLElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom]):
    Handle =
  parser.insertForeignElement(nsHTML, false)

proc insertHTMLElement[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    tagType: TagType): Handle =
  let tagname = parser.toAtom(tagType)
  parser.insertForeignElement(tagname, tagname, nsHTML, false, @[])

proc insertHTMLElementPop[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  discard parser.insertHTMLElement()
  discard parser.popElement()

const ForeignTable = {
  "xlink:actuate": nsXLink,
  "xlink:arcrole": nsXLink,
  "xlink:href": nsXLink,
  "xlink:role": nsXLink,
  "xlink:show": nsXLink,
  "xlink:title": nsXLink,
  "xlink:type": nsXLink,
  "xml:lang": nsXml,
  "xml:space": nsXml,
  "xmlns": nsXmlns,
  "xmlns:xlink": nsXmlns,
}

proc createForeignTable[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  for (name, namespace) in ForeignTable:
    let nameAtom = parser.strToAtom(name)
    parser.foreignTable[nameAtom] = namespace

# Note: adjustMathMLAttributes and adjustSVGAttributes both include the "adjust
# foreign attributes" step as well.
proc adjustMathMLAttributes[Handle, Atom](
    parser: var HTML5Parser[Handle, Atom]) =
  if parser.foreignTable.len == 0:
    parser.createForeignTable()
  for it in parser.tok.attrs.mitems:
    parser.foreignTable.withValue(it.name, p):
      it.namespace = parser.namespaceToAtom(p[])
    do:
      if it.name == parser.toAtom(ttDefinitionurl):
        it.name = parser.strToAtom("definitionURL")
  parser.sortAttrs()

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

proc adjustSVGAttributes[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  if parser.foreignTable.len == 0:
    parser.createForeignTable()
  if parser.adjustedTable.len == 0:
    for (k, v) in AdjustedTable:
      let ka = parser.strToAtom(k)
      let va = parser.strToAtom(v)
      parser.adjustedTable[ka] = va
  for it in parser.tok.attrs.mitems:
    parser.foreignTable.withValue(it.name, p):
      it.namespace = parser.namespaceToAtom(p[])
    do:
      parser.adjustedTable.withValue(it.name, p):
        it.name = p[]
  parser.sortAttrs()

proc insertCharacter(parser: var HTML5Parser; data: string) =
  let location = parser.appropriatePlaceForInsert()
  if location.inside != parser.getDocument():
    parser.insertText(location.inside, data, location.before)

proc insertComment[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    position: InsertionLocation[Handle]) =
  parser.insertCommentImpl(position.inside, position.before)

proc insertComment(parser: var HTML5Parser) =
  let position = parser.appropriatePlaceForInsert()
  parser.insertComment(position)

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

proc quirksConditions(name, pubid, sysid: string; flags: set[TokenFlag]): bool =
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

proc limitedQuirksConditions(pubid: string; flags: set[TokenFlag]): bool =
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
proc genericRawtextElementParsingAlgorithm(parser: var HTML5Parser) =
  discard parser.insertHTMLElement()
  parser.tok.state = tsRawtext
  parser.oldInsertionMode = parser.insertionMode
  parser.insertionMode = imText

proc genericRCDATAElementParsingAlgorithm(parser: var HTML5Parser) =
  discard parser.insertHTMLElement()
  parser.tok.state = tsRcdata
  parser.oldInsertionMode = parser.insertionMode
  parser.insertionMode = imText

# Pop all elements, including the specified tag.
proc popElementsIncl(parser: var HTML5Parser; tag: TagType) =
  while parser.getTagType(parser.popElement()) != tag:
    discard

# Pop all elements, including the specified element.
proc popElementsIncl[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    handle: Handle) =
  while parser.popElement() != handle:
    discard

# Pop all elements, excluding the specified tag.
proc popElementsExcl(parser: var HTML5Parser; tags: set[TagType]) =
  while parser.getTagType(parser.currentNode) notin tags:
    discard parser.popElement()

proc hasElementInScopePop[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    target: TagType): bool =
  if parser.hasElementInScope(target):
    parser.popElementsIncl(target)
    return true
  false

# https://html.spec.whatwg.org/multipage/parsing.html#closing-elements-that-have-implied-end-tags
proc generateImpliedEndTags(parser: var HTML5Parser) =
  const tags = {
    ttDd, ttDt, ttLi, ttOptgroup, ttOption, ttP, ttRb, ttRp,
    ttRt, ttRtc
  }
  while parser.getTagType(parser.currentNode) in tags:
    discard parser.popElement()

proc generateImpliedEndTags(parser: var HTML5Parser; exclude: TagType) =
  let tags = {
    ttDd, ttDt, ttLi, ttOptgroup, ttOption, ttP, ttRb, ttRp,
    ttRt, ttRtc
  } - {exclude}
  while parser.getTagType(parser.currentNode) in tags:
    discard parser.popElement()

proc generateImpliedEndTagsThoroughly(parser: var HTML5Parser) =
  const tags = {
    ttCaption, ttColgroup, ttDd, ttDt, ttLi, ttOptgroup,
    ttOption, ttP, ttRb, ttRp, ttRt, ttRtc, ttTbody, ttTd,
    ttTfoot, ttTh, ttThead, ttTr
  }
  while parser.getTagType(parser.currentNode) in tags:
    discard parser.popElement()

# https://html.spec.whatwg.org/multipage/parsing.html#push-onto-the-list-of-active-formatting-elements
proc pushActiveFormatting[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    element: Handle; tagname: Atom) =
  var count = 0
  for i in countdown(parser.activeFormatting.high, 0):
    let it = parser.activeFormatting[i]
    if it == nil: # marker
      break
    let element = it.element
    if parser.getLocalName(it.element) != tagname:
      continue
    if parser.getNamespace(it.element) != parser.getNamespace(element):
      continue
    if it.attrs != parser.tok.attrs:
      continue
    inc count
    if count == 3:
      parser.activeFormatting.delete(i)
      break
  let fmt = Formatting[Handle, Atom](
    element: element,
    startTagName: tagname,
  )
  fmt.attrs = move(parser.tok.attrs)
  parser.activeFormatting.add(fmt)

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
      parser.activeFormatting[^1] == nil or
      parser.findOpenElement(parser.activeFormatting[^1].element) != -1:
    return
  var i = parser.activeFormatting.high
  var state = sRewind
  while true:
    case state
    of sRewind:
      if i == 0:
        state = sCreate
        continue
      dec i
      let entry = parser.activeFormatting[i]
      if entry != nil and parser.findOpenElement(entry.element) == -1:
        continue
      state = sAdvance
    of sAdvance:
      inc i
      state = sCreate
    of sCreate:
      let fmt = parser.activeFormatting[i]
      var attrs = fmt.attrs
      fmt.element = parser.insertHTMLElement(fmt.startTagName, move(attrs))
      if i != parser.activeFormatting.high:
        state = sAdvance
        continue
      break

proc clearActiveFormattingTillMarker(parser: var HTML5Parser) =
  while parser.activeFormatting.len > 0 and
      parser.activeFormatting.pop() != nil:
    discard

proc isMathMLIntegrationPoint[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    element: Handle): bool =
  if parser.getNamespace(element) != nsMathML:
    return false
  let tagType = parser.toTagType(parser.getLocalName(element))
  return tagType in {ttMi, ttMo, ttMn, ttMs, ttMtext}

proc isHTMLIntegrationPoint[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    oe: OpenElement[Handle, Atom]): bool =
  let localName = parser.getLocalName(oe.element)
  let namespace = parser.getNamespace(oe.element)
  let tagType = parser.toTagType(localName)
  if namespace == nsMathML:
    return oe.integrationPoint
  if namespace == nsSVG:
    return tagType in {ttForeignObject, ttDesc, ttTitle}
  return false

const AsciiWhitespace = {' ', '\n', '\r', '\t', '\f'}

proc until(s: string; c1, c2: char; starti: int): string =
  result = ""
  for i in starti ..< s.len:
    let c = s[i]
    if c == c1 or c == c2:
      break
    result &= c

proc extractEncFromMeta(s: string): string =
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
proc findLastActiveFormatting[Handle, Atom](
    parser: var HTML5Parser[Handle, Atom]; node: Handle): int =
  for i in countdown(parser.activeFormatting.high, 0):
    let it = parser.activeFormatting[i]
    if it != nil and it.element == node:
      return i
  return -1

# > the last element in the list of active formatting elements that:
# > is between the end of the list and the last marker in the list, if any,
# > or the start of the list otherwise, and has the tag name subject.
proc findLastActiveFormattingAfterMarker[Handle, Atom](
    parser: var HTML5Parser[Handle, Atom]; tagname: Atom): int =
  for i in countdown(parser.activeFormatting.high, 0):
    let it = parser.activeFormatting[i]
    if it == nil:
      break # marker
    if parser.getLocalName(it.element) == tagname:
      return i
  return -1

#https://html.spec.whatwg.org/multipage/parsing.html#the-stack-of-open-elements
const SpecialElements = {
  ttAddress, ttApplet, ttArea, ttArticle, ttAside, ttBase,
  ttBasefont, ttBgsound, ttBlockquote, ttBody, ttBr, ttButton,
  ttCaption, ttCenter, ttCol, ttColgroup, ttDd, ttDetails, ttDir,
  ttDiv, ttDl, ttDt, ttEmbed, ttFieldset, ttFigcaption, ttFigure,
  ttFooter, ttForm, ttFrame, ttFrameset, ttH1, ttH2, ttH3, ttH4,
  ttH5, ttH6, ttHead, ttHeader, ttHgroup, ttHr, ttHtml,
  ttIframe, ttImg, ttInput, ttKeygen, ttLi, ttLink, ttListing,
  ttMain, ttMarquee, ttMenu, ttMeta, ttNav, ttNoembed, ttNoframes,
  ttNoscript, ttObject, ttOl, ttP, ttParam, ttPlaintext, ttPre,
  ttScript, ttSearch, ttSection, ttSelect, ttSource, ttStyle,
  ttSummary, ttTable, ttTbody, ttTd, ttTemplate, ttTextarea,
  ttTfoot, ttTh, ttThead, ttTitle, ttTr, ttTrack, ttUl, ttWbr,
  ttXmp
}

proc isSpecialElement[Handle, Atom](parser: HTML5Parser[Handle, Atom];
    element: Handle): bool =
  let tagType = parser.toTagType(parser.getLocalName(element))
  case parser.getNamespace(element)
  of nsHTML:
    return tagType in SpecialElements
  of nsMathML:
    const elements = {ttMi, ttMo, ttMn, ttMs, ttMtext, ttAnnotationXml}
    return tagType in elements
  of nsSVG:
    return tagType in {ttForeignObject, ttDesc, ttTitle}
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
proc adoptionAgencyAlgorithm[Handle, Atom](
    parser: var HTML5Parser[Handle, Atom]): bool =
  if parser.currentTagName == parser.tok.tagname and
      parser.findLastActiveFormatting(parser.currentNode) == -1:
    discard parser.popElement()
    return false
  for i in 0 ..< 8: # outer loop
    var formattingIndex =
      parser.findLastActiveFormattingAfterMarker(parser.tok.tagname)
    if formattingIndex < 0:
      # no such element
      return true
    let formatting = parser.activeFormatting[formattingIndex].element
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
      let fmt = parser.activeFormatting[nodeFormattingIndex]
      var attrs = fmt.attrs
      let tagname = fmt.startTagName
      let element = parser.createHTMLElement(tagname, commonAncestor,
        move(attrs))
      parser.activeFormatting[nodeFormattingIndex].element = element
      parser.openElements[nodeStackIndex] = OpenElement[Handle, Atom](
        element: element,
        startTagName: tagname
      )
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
    let fmt = parser.activeFormatting[formattingIndex]
    var attrs = fmt.attrs
    let tagname = fmt.startTagName
    let element = parser.createHTMLElement(tagname, furthestBlock, move(attrs))
    parser.moveChildren(furthestBlock, element)
    parser.append(furthestBlock, element)
    parser.activeFormatting.insert(Formatting[Handle, Atom](
      element: element,
      startTagName: tagname
    ), bookmark)
    if formattingIndex >= bookmark:
      inc formattingIndex # increment because of insert
    parser.activeFormatting.delete(formattingIndex)
    parser.openElements.insert(OpenElement[Handle, Atom](
      element: element,
      startTagName: parser.tok.tagname
    ), furthestBlockIndex + 1)
    parser.openElements.delete(stackIndex)
  return false

proc closeP(parser: var HTML5Parser; sure = false) =
  if sure or parser.hasElementInButtonScope(ttP):
    parser.popElementsIncl(ttP)

proc otherBodyEndTag[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    tagname: Atom) =
  for i in countdown(parser.openElements.high, 0):
    let it = parser.openElements[i]
    if it.startTagName == tagname:
      parser.popElementsIncl(it.element)
      break
    elif parser.isSpecialElement(it.element):
      break

proc popTableContext[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  parser.popElementsExcl({ttTable, ttTemplate, ttHtml})

proc popTableBodyContext[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  const tags = {ttTbody, ttTfoot, ttThead, ttTemplate, ttHtml}
  parser.popElementsExcl(tags)

proc popTableRowContext[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  parser.popElementsExcl({ttTr, ttTemplate, ttHtml})

proc closeCell[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  while parser.getTagType(parser.popElement()) notin {ttTd, ttTh}:
    discard
  parser.clearActiveFormattingTillMarker()
  parser.insertionMode = imInRow

proc processInHTML[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    insertionMode: InsertionMode): ParseChunkResult =
  template reprocess(): ParseChunkResult =
    parser.processInHTML(parser.insertionMode)

  template reprocess(mode: InsertionMode): ParseChunkResult =
    parser.processInHTML(mode)

  var anythingElse = false

  case insertionMode
  of imInitial:
    case parser.tok.t
    of ttWhitespace: discard
    of ttComment: parser.insertComment(lastChildOf(parser.getDocument()))
    of ttDoctype:
      var name = move(parser.tok.tagNameBuf)
      var pubid = ""
      var sysid = ""
      if (let i = name.find('\0'); i >= 0):
        pubid = name.substr(i + 1)
        name.setLen(i)
      if (let i = pubid.find('\0'); i >= 0):
        sysid = pubid.substr(i + 1)
        pubid.setLen(i)
      parser.appendDocumentType(name, pubid, sysid)
      if not parser.isIframeSrcdoc:
        if quirksConditions(name, pubid, sysid, parser.tok.flags):
          parser.setQuirksMode(qmQuirks)
        elif limitedQuirksConditions(pubid, parser.tok.flags):
          parser.setQuirksMode(qmLimitedQuirks)
      parser.insertionMode = imBeforeHtml
    else:
      parser.setQuirksMode(qmQuirks)
      parser.insertionMode = imBeforeHtml
      return reprocess

  of imBeforeHtml:
    case parser.tok.t
    of ttDoctype, ttWhitespace: discard
    of ttComment: parser.insertComment(lastChildOf(parser.getDocument()))
    of ttStartTag:
      if parser.toTagType(parser.tok.tagname) == ttHtml:
        let intendedParent = parser.getDocument()
        let element = parser.createHTMLElement(parser.tok.tagname, intendedParent,
          move(parser.tok.attrs))
        parser.append(parser.getDocument(), element)
        parser.pushHTMLElement(element)
        parser.insertionMode = imBeforeHead
      else:
        anythingElse = true
    of ttEndTag:
      anythingElse = parser.toTagType(parser.tok.tagname) in
        {ttHead, ttBody, ttHtml, ttBr}
    else: anythingElse = true
    if anythingElse:
      let element = parser.createHTMLElement()
      parser.append(parser.getDocument(), element)
      parser.pushHTMLElement(element)
      parser.insertionMode = imBeforeHead
      return reprocess

  of imBeforeHead:
    case parser.tok.t
    of ttWhitespace, ttDoctype: discard
    of ttComment: parser.insertComment()
    of ttStartTag:
      case parser.toTagType(parser.tok.tagname)
      of ttHtml:
        return reprocess imInBody
      of ttHead:
        parser.head = some(parser.insertHTMLElement())
        parser.insertionMode = imInHead
      else: anythingElse = true
    of ttEndTag:
      anythingElse = parser.toTagType(parser.tok.tagname) in
        {ttHead, ttBody, ttHtml, ttBr}
    else: anythingElse = true
    if anythingElse:
      parser.head = some(parser.insertHTMLElement(ttHead))
      parser.insertionMode = imInHead
      return reprocess

  of imInHead:
    case parser.tok.t
    of ttWhitespace: parser.insertCharacter(parser.tok.charbufOut)
    of ttComment: parser.insertComment()
    of ttDoctype: discard
    of ttStartTag:
      case parser.toTagType(parser.tok.tagname)
      of ttHtml: return reprocess imInBody
      of ttBase, ttBasefont, ttBgsound, ttLink:
        parser.insertHTMLElementPop()
      of ttMeta:
        var res = seContinue
        if (let i = parser.findAttr(ttCharset); i >= 0):
          res = parser.setEncoding(parser.tok.attrs[i].value)
        elif (let i = parser.findAttr(ttHttpEquiv); i >= 0):
          if parser.tok.attrs[i].value.equalsIgnoreCase("Content-Type"):
            let i = parser.findAttr(ttContent)
            if i >= 0:
              let cs = extractEncFromMeta(parser.tok.attrs[i].value)
              if cs != "":
                res = parser.setEncoding(cs)
        parser.insertHTMLElementPop()
        if res == seStop:
          return pcrStop
      of ttTitle: parser.genericRCDATAElementParsingAlgorithm()
      of ttNoscript:
        if parser.scripting:
          parser.genericRawtextElementParsingAlgorithm()
        else:
          discard parser.insertHTMLElement()
          parser.insertionMode = imInHeadNoscript
      of ttNoframes, ttStyle:
        parser.genericRawtextElementParsingAlgorithm()
      of ttScript:
        let location = parser.appropriatePlaceForInsert()
        let element = parser.createHTMLElement(parser.tok.tagname, location.inside,
          move(parser.tok.attrs))
        if parser.ctx.isSome and not parser.scripting:
          parser.setScriptAlreadyStarted(element)
        parser.insert(location, element)
        parser.pushHTMLElement(element)
        parser.tok.state = tsScriptData
        parser.oldInsertionMode = parser.insertionMode
        parser.insertionMode = imText
      of ttTemplate:
        discard parser.insertHTMLElement()
        parser.activeFormatting.add(nil)
        parser.framesetOk = false
        parser.insertionMode = imInTemplate
        parser.templateModes.add(imInTemplate)
      of ttHead: discard
      else: anythingElse = true
    of ttEndTag:
      case parser.toTagType(parser.tok.tagname)
      of ttHead:
        discard parser.popElement()
        parser.insertionMode = imAfterHead
      of ttTemplate:
        if parser.hasElement(ttTemplate):
          parser.generateImpliedEndTagsThoroughly()
          parser.popElementsIncl(ttTemplate)
          parser.clearActiveFormattingTillMarker()
          discard parser.templateModes.pop()
          parser.resetInsertionMode()
      of ttBody, ttHtml, ttBr: anythingElse = true
      else: discard
    else: anythingElse = true
    if anythingElse:
      discard parser.popElement()
      parser.insertionMode = imAfterHead
      return reprocess

  of imInHeadNoscript:
    case parser.tok.t
    of ttDoctype: discard
    of ttStartTag:
      case parser.toTagType(parser.tok.tagname)
      of ttHead, ttNoscript: discard
      of ttHtml: return reprocess imInBody
      of ttBasefont, ttBgsound, ttLink, ttMeta, ttNoframes, ttStyle:
        return reprocess imInHead
      else: anythingElse = true
    of ttEndTag:
      case parser.toTagType(parser.tok.tagname)
      of ttBr: anythingElse = true
      of ttNoscript:
        discard parser.popElement()
        parser.insertionMode = imInHead
      else: discard
    of ttWhitespace, ttComment: return reprocess imInHead
    else: anythingElse = true
    if anythingElse:
      discard parser.popElement()
      parser.insertionMode = imInHead
      return reprocess

  of imAfterHead:
    case parser.tok.t
    of ttWhitespace: parser.insertCharacter(parser.tok.charbufOut)
    of ttComment: parser.insertComment()
    of ttDoctype: discard
    of ttStartTag:
      case parser.toTagType(parser.tok.tagname)
      of ttHead: discard
      of ttHtml: return reprocess imInBody
      of ttBody:
        discard parser.insertHTMLElement()
        parser.framesetOk = false
        parser.insertionMode = imInBody
      of ttFrameset:
        discard parser.insertHTMLElement()
        parser.insertionMode = imInFrameset
      of ttBase, ttBasefont, ttBgsound, ttLink, ttMeta, ttNoframes,
          ttScript, ttStyle, ttTemplate, ttTitle:
        let head = parser.head.get
        parser.pushHTMLElement(head)
        result = reprocess imInHead
        if (let i = parser.findOpenElement(head); i != -1):
          parser.openElements.delete(i)
      else: anythingElse = true
    of ttEndTag:
      case parser.toTagType(parser.tok.tagname)
      of ttTemplate: return reprocess imInHead
      of ttBody, ttHtml, ttBr: anythingElse = true
      else: discard
    else: anythingElse = true
    if anythingElse:
      discard parser.insertHTMLElement(ttBody)
      parser.insertionMode = imInBody
      return reprocess

  of imInBody:
    case parser.tok.t
    of ttWhitespace:
      parser.reconstructActiveFormatting()
      parser.insertCharacter(parser.tok.charbufOut)
    of ttNull, ttDoctype: discard
    of ttCharacter:
      parser.reconstructActiveFormatting()
      parser.insertCharacter(parser.tok.charbufOut)
      parser.framesetOk = false
    of ttComment: parser.insertComment()
    of ttStartTag:
      let tagType = parser.toTagType(parser.tok.tagname)
      case tagType
      of ttHtml:
        if not parser.hasElement(ttTemplate):
          parser.addAttrsIfMissing(parser.openElements[0].element,
            parser.tok.attrs)
      of ttBase, ttBasefont, ttBgsound, ttLink, ttMeta, ttNoframes,
          ttScript, ttStyle, ttTemplate, ttTitle:
        return reprocess imInHead
      of ttBody:
        if parser.openElements.len == 1 or
            parser.getTagType(parser.openElements[1].element) != ttBody or
            parser.hasElement(ttTemplate):
          discard
        else:
          parser.framesetOk = false
          parser.addAttrsIfMissing(parser.openElements[1].element,
            parser.tok.attrs)
      of ttFrameset:
        if parser.openElements.len == 1 or
            parser.getTagType(parser.openElements[1].element) != ttBody or
            not parser.framesetOk:
          discard
        else:
          parser.remove(parser.openElements[1].element)
          while parser.openElements.len > 1:
            discard parser.popElement()
          discard parser.insertHTMLElement()
          parser.insertionMode = imInFrameset
      of ttAddress, ttArticle, ttAside, ttBlockquote, ttCenter,
          ttDetails, ttDialog, ttDir, ttDiv, ttDl, ttFieldset,
          ttFigcaption, ttFigure, ttFooter, ttHeader, ttHgroup,
          ttMain, ttMenu, ttNav, ttOl, ttP, ttSearch, ttSection,
          ttSummary, ttUl:
        parser.closeP()
        discard parser.insertHTMLElement()
      of ttH1, ttH2, ttH3, ttH4, ttH5, ttH6:
        parser.closeP()
        if parser.getTagType(parser.currentNode) in HTagTypes:
          discard parser.popElement()
        discard parser.insertHTMLElement()
      of ttPre, ttListing:
        parser.closeP()
        discard parser.insertHTMLElement()
        parser.ignoreLF = true
        parser.framesetOk = false
      of ttForm:
        let hasTemplate = parser.hasElement(ttTemplate)
        if parser.form.isNone or hasTemplate:
          parser.closeP()
          let element = parser.insertHTMLElement()
          if not hasTemplate:
            parser.form = some(element)
      of ttLi:
        parser.framesetOk = false
        for node in parser.ropenElements:
          let tagType = parser.getTagType(node)
          case tagType
          of ttLi:
            parser.popElementsIncl(ttLi)
            break
          of ttAddress, ttDiv, ttP:
            discard
          elif parser.isSpecialElement(node):
            break
          else: discard
        parser.closeP()
        discard parser.insertHTMLElement()
      of ttDd, ttDt:
        parser.framesetOk = false
        for node in parser.ropenElements:
          let tagType = parser.getTagType(node)
          case tagType
          of ttDd:
            parser.popElementsIncl(ttDd)
            break
          of ttDt:
            parser.popElementsIncl(ttDt)
            break
          of ttAddress, ttDiv, ttP:
            discard
          elif parser.isSpecialElement(node):
            break
          else: discard
        parser.closeP()
        discard parser.insertHTMLElement()
      of ttPlaintext:
        parser.closeP()
        discard parser.insertHTMLElement()
        parser.tok.state = tsPlaintext
      of ttButton:
        discard parser.hasElementInScopePop(ttButton)
        parser.reconstructActiveFormatting()
        discard parser.insertHTMLElement()
        parser.framesetOk = false
      of ttA:
        let tagname = parser.toAtom(ttA)
        let i = parser.findLastActiveFormattingAfterMarker(tagname)
        if i != -1:
          let anchor = parser.activeFormatting[i].element
          if parser.adoptionAgencyAlgorithm():
            parser.otherBodyEndTag(parser.tok.tagname)
          let j = parser.findLastActiveFormatting(anchor)
          if j != -1:
            parser.activeFormatting.delete(j)
          let k = parser.findOpenElement(anchor)
          if k != -1:
            parser.openElements.delete(k)
        parser.reconstructActiveFormatting()
        var attrs = parser.tok.attrs
        let element = parser.insertHTMLElement()
        parser.tok.attrs = move(attrs)
        parser.pushActiveFormatting(element, parser.tok.tagname)
      of ttB, ttBig, ttCode, ttEm, ttFont, ttI, ttS, ttSmall,
          ttStrike, ttStrong, ttTt, ttU:
        parser.reconstructActiveFormatting()
        var attrs = parser.tok.attrs
        let element = parser.insertHTMLElement()
        parser.tok.attrs = move(attrs)
        parser.pushActiveFormatting(element, parser.tok.tagname)
      of ttNobr:
        parser.reconstructActiveFormatting()
        var attrs = parser.tok.attrs
        if parser.hasElementInScope(ttNobr):
          if parser.adoptionAgencyAlgorithm():
            parser.otherBodyEndTag(parser.tok.tagname)
          parser.reconstructActiveFormatting()
        let element = parser.insertHTMLElement()
        parser.tok.attrs = move(attrs)
        parser.pushActiveFormatting(element, parser.tok.tagname)
      of ttApplet, ttMarquee, ttObject:
        parser.reconstructActiveFormatting()
        discard parser.insertHTMLElement()
        parser.activeFormatting.add(nil)
        parser.framesetOk = false
      of ttTable:
        if parser.quirksMode != qmQuirks:
          parser.closeP()
        discard parser.insertHTMLElement()
        parser.framesetOk = false
        parser.insertionMode = imInTable
      of ttArea, ttBr, ttEmbed, ttImg, ttKeygen, ttWbr:
        parser.reconstructActiveFormatting()
        parser.insertHTMLElementPop()
        parser.framesetOk = false
      of ttInput:
        if parser.ctx.isNone or
            parser.getTagType(parser.ctx.get.element) != ttSelect:
          discard parser.hasElementInScopePop(ttSelect)
          parser.reconstructActiveFormatting()
          let i = parser.findAttr(ttTyp)
          if i < 0 or
              not parser.tok.attrs[i].value.equalsIgnoreCase("hidden"):
            parser.framesetOk = false
          parser.insertHTMLElementPop()
      of ttParam, ttSource, ttTrack: parser.insertHTMLElementPop()
      of ttHr:
        parser.closeP()
        if parser.hasElementInScope(ttSelect):
          parser.generateImpliedEndTags()
        parser.insertHTMLElementPop()
        parser.framesetOk = false
      of ttImage:
        parser.tok.tagname = parser.toAtom(ttImg)
        return reprocess
      of ttTextarea:
        discard parser.insertHTMLElement()
        parser.ignoreLF = true
        parser.tok.state = tsRcdata
        parser.oldInsertionMode = parser.insertionMode
        parser.framesetOk = false
        parser.insertionMode = imText
      of ttXmp:
        parser.closeP()
        parser.reconstructActiveFormatting()
        parser.framesetOk = false
        parser.genericRawtextElementParsingAlgorithm()
      of ttIframe:
        parser.framesetOk = false
        parser.genericRawtextElementParsingAlgorithm()
      of ttNoembed: parser.genericRawtextElementParsingAlgorithm()
      of ttNoscript:
        if parser.scripting:
          parser.genericRawtextElementParsingAlgorithm()
        else:
          parser.reconstructActiveFormatting()
          discard parser.insertHTMLElement()
      of ttSelect:
        if parser.ctx.isSome and
            parser.getTagType(parser.ctx.get.element) == ttSelect:
          discard
        elif not parser.hasElementInScopePop(ttSelect):
          parser.reconstructActiveFormatting()
          discard parser.insertHTMLElement()
          parser.framesetOk = false
      of ttOption, ttOptgroup:
        if parser.hasElementInScope(ttSelect):
          if tagType == ttOption:
            parser.generateImpliedEndTags(ttOptgroup)
          else:
            parser.generateImpliedEndTags()
        elif parser.getTagType(parser.currentNode) == ttOption:
          discard parser.popElement()
        parser.reconstructActiveFormatting()
        discard parser.insertHTMLElement()
      of ttRb, ttRtc:
        if parser.hasElementInScope(ttRuby):
          parser.generateImpliedEndTags()
        discard parser.insertHTMLElement()
      of ttRp, ttRt:
        if parser.hasElementInScope(ttRuby):
          parser.generateImpliedEndTags(ttRtc)
        discard parser.insertHTMLElement()
      of ttMath:
        parser.reconstructActiveFormatting()
        parser.adjustMathMLAttributes()
        discard parser.insertForeignElement(nsMathML, false)
        if tfSelfClosing in parser.tok.flags:
          discard parser.popElement()
      of ttSvg:
        parser.reconstructActiveFormatting()
        parser.adjustSVGAttributes()
        discard parser.insertForeignElement(nsSVG, false)
        if tfSelfClosing in parser.tok.flags:
          discard parser.popElement()
      of ttCaption, ttCol, ttColgroup, ttFrame, ttHead, ttTbody,
          ttTd, ttTfoot, ttTh, ttThead, ttTr:
        discard
      else:
        parser.reconstructActiveFormatting()
        discard parser.insertHTMLElement()
    of ttEndTag:
      case (let tokTagType = parser.toTagType(parser.tok.tagname); tokTagType)
      of ttTemplate: return reprocess imInHead
      of ttBody:
        if parser.hasElementInScope(ttBody):
          parser.insertionMode = imAfterBody
      of ttHtml:
        if parser.hasElementInScope(ttBody):
          parser.insertionMode = imAfterBody
          return reprocess
      of ttAddress, ttArticle, ttAside, ttBlockquote, ttButton,
          ttCenter, ttDetails, ttDialog, ttDir, ttDiv, ttDl,
          ttFieldset, ttFigcaption, ttFigure, ttFooter, ttHeader,
          ttHgroup, ttListing, ttMain, ttMenu, ttNav, ttOl,
          ttPre, ttSearch, ttSection, ttSelect, ttSummary, ttUl:
        discard parser.hasElementInScopePop(tokTagType)
      of ttForm:
        if not parser.hasElement(ttTemplate):
          let form = parser.form
          parser.form = none(Handle)
          if form.isNone or not parser.hasElementInScope(form.get):
            return
          let node = form.get
          parser.generateImpliedEndTags()
          let i = parser.findOpenElement(node)
          parser.openElements.delete(i)
        else:
          discard parser.hasElementInScopePop(ttForm)
      of ttP:
        if not parser.hasElementInButtonScope(ttP):
          discard parser.insertHTMLElement(ttP)
        parser.closeP(sure = true)
      of ttLi:
        if parser.hasElementInListItemScope(ttLi):
          parser.popElementsIncl(ttLi)
      of ttDd, ttDt:
        discard parser.hasElementInScopePop(tokTagType)
      of ttH1, ttH2, ttH3, ttH4, ttH5, ttH6:
        if parser.hasElementInScope(ttH1):
          while parser.getTagType(parser.popElement()) notin ttH1..ttH6:
            discard
      of ttA, ttB, ttBig, ttCode, ttEm, ttFont, ttI,
          ttNobr, ttS, ttSmall, ttStrike, ttStrong, ttTt,
          ttU:
        if parser.adoptionAgencyAlgorithm():
          parser.otherBodyEndTag(parser.tok.tagname)
      of ttApplet, ttMarquee, ttObject:
        if parser.hasElementInScopePop(tokTagType):
          parser.clearActiveFormattingTillMarker()
      of ttBr:
        parser.reconstructActiveFormatting()
        discard parser.insertHTMLElement(ttBr)
        discard parser.popElement()
        parser.framesetOk = false
      else: parser.otherBodyEndTag(parser.tok.tagname)

  of imText:
    case parser.tok.t
    of ttCharacter, ttWhitespace:
      parser.insertCharacter(parser.tok.charbufOut)
    of ttEndTag:
      discard parser.popElement()
      parser.insertionMode = parser.oldInsertionMode
      if parser.scripting and parser.toTagType(parser.tok.tagname) == ttScript:
        return pcrScript
    else: assert false # unreachable

  of imInTable:
    case parser.tok.t
    of ttCharacter, ttWhitespace, ttNull:
      const CanHaveText = {
        ttTable, ttTbody, ttTfoot, ttThead, ttTr
      }
      if parser.getTagType(parser.currentNode) in CanHaveText:
        parser.pendingTableChars = ""
        parser.pendingTableCharsWhitespace = true
        parser.oldInsertionMode = parser.insertionMode
        parser.insertionMode = imInTableInText
        return reprocess
      else: # anything else
        parser.fosterParenting = true
        result = reprocess imInBody
        parser.fosterParenting = false
    of ttComment: parser.insertComment()
    of ttDoctype: discard
    of ttStartTag:
      case parser.toTagType(parser.tok.tagname)
      of ttCaption:
        parser.popTableContext()
        parser.activeFormatting.add(nil)
        discard parser.insertHTMLElement()
        parser.insertionMode = imInCaption
      of ttColgroup:
        parser.popTableContext()
        discard parser.insertHTMLElement(ttColgroup)
        parser.insertionMode = imInColumnGroup
      of ttCol:
        parser.popTableContext()
        discard parser.insertHTMLElement(ttColgroup)
        parser.insertionMode = imInColumnGroup
        return reprocess
      of ttTbody, ttTfoot, ttThead:
        parser.popTableContext()
        discard parser.insertHTMLElement()
        parser.insertionMode = imInTableBody
      of ttTd, ttTh, ttTr:
        parser.popTableContext()
        discard parser.insertHTMLElement(ttTbody)
        parser.insertionMode = imInTableBody
        return reprocess
      of ttTable:
        if parser.hasElementInTableScope(ttTable):
          parser.popElementsIncl(ttTable)
          parser.resetInsertionMode()
          return reprocess
      of ttInput:
        let i = parser.findAttr(ttTyp)
        if i >= 0 and
            parser.tok.attrs[i].value.equalsIgnoreCase("hidden"):
          parser.insertHTMLElementPop()
        else:
          anythingElse = true
      of ttStyle, ttScript, ttTemplate: return reprocess imInHead
      of ttForm:
        if parser.form.isNone and not parser.hasElement(ttTemplate):
          parser.form = some(parser.insertHTMLElement())
          discard parser.popElement()
      else: anythingElse = true
    of ttEndTag:
      case parser.toTagType(parser.tok.tagname)
      of ttTable:
        if parser.hasElementInTableScope(ttTable):
          parser.popElementsIncl(ttTable)
          parser.resetInsertionMode()
      of ttBody, ttCaption, ttCol, ttColgroup, ttHtml, ttTbody,
          ttTd, ttTfoot, ttTh, ttThead, ttTr:
        discard
      of ttTemplate: return reprocess imInHead
      else: anythingElse = true
    if anythingElse:
      parser.fosterParenting = true
      result = reprocess imInBody
      parser.fosterParenting = false

  of imInTableInText:
    case parser.tok.t
    of ttNull: discard
    of ttWhitespace: parser.pendingTableChars &= parser.tok.charbufOut
    of ttCharacter:
      parser.pendingTableCharsWhitespace = false
      parser.pendingTableChars &= parser.tok.charbufOut
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
      return reprocess

  of imInCaption:
    case parser.tok.t
    of ttStartTag:
      case parser.toTagType(parser.tok.tagname)
      of ttCaption, ttCol, ttColgroup, ttTbody, ttTd, ttTfoot,
          ttTh, ttThead, ttTr:
        if parser.hasElementInTableScope(ttCaption):
          parser.popElementsIncl(ttCaption)
          parser.clearActiveFormattingTillMarker()
          parser.insertionMode = imInTable
          return reprocess
      else: anythingElse = true
    of ttEndTag:
      case (let tokTagType = parser.toTagType(parser.tok.tagname); tokTagType)
      of ttCaption, ttTable:
        if parser.hasElementInTableScope(ttCaption):
          parser.popElementsIncl(ttCaption)
          parser.clearActiveFormattingTillMarker()
          parser.insertionMode = imInTable
          if tokTagType == ttTable:
            return reprocess
      of ttBody, ttCol, ttColgroup, ttHtml, ttTbody, ttTd,
          ttTfoot, ttTh, ttThead, ttTr:
        discard
      else: anythingElse = true
    else: anythingElse = true
    if anythingElse:
      return reprocess imInBody

  of imInColumnGroup:
    case parser.tok.t
    of ttWhitespace: parser.insertCharacter(parser.tok.charbufOut)
    of ttComment: parser.insertComment()
    of ttDoctype: discard
    of ttStartTag:
      case parser.toTagType(parser.tok.tagname)
      of ttHtml: return reprocess imInBody
      of ttCol: parser.insertHTMLElementPop()
      of ttTemplate: return reprocess imInHead
      else: anythingElse = true
    of ttEndTag:
      case parser.toTagType(parser.tok.tagname)
      of ttCol: discard
      of ttColgroup:
        if parser.getTagType(parser.currentNode) == ttColgroup:
          discard parser.popElement()
          parser.insertionMode = imInTable
      of ttTemplate: return reprocess imInHead
      else: anythingElse = true
    else: anythingElse = true
    if anythingElse:
      if parser.getTagType(parser.currentNode) == ttColgroup:
        discard parser.popElement()
        parser.insertionMode = imInTable
        return reprocess

  of imInTableBody:
    case parser.tok.t
    of ttStartTag:
      case parser.toTagType(parser.tok.tagname)
      of ttTr:
        parser.popTableBodyContext()
        discard parser.insertHTMLElement()
        parser.insertionMode = imInRow
      of ttTh, ttTd:
        parser.popTableBodyContext()
        discard parser.insertHTMLElement(ttTr)
        parser.insertionMode = imInRow
        return reprocess
      of ttCaption, ttCol, ttColgroup, ttTbody, ttTfoot, ttThead:
        if parser.hasElementInTableScope({ttTbody, ttThead, ttTfoot}):
          parser.popTableBodyContext()
          discard parser.popElement()
          parser.insertionMode = imInTable
          return reprocess
      else: return reprocess imInTable
    of ttEndTag:
      case (let tokTagType = parser.toTagType(parser.tok.tagname); tokTagType)
      of ttTbody, ttTfoot, ttThead, ttTable:
        if parser.hasElementInTableScope(tokTagType):
          parser.popTableBodyContext()
          discard parser.popElement()
          parser.insertionMode = imInTable
          if tokTagType == ttTable:
            return reprocess
      of ttBody, ttCaption, ttCol, ttColgroup, ttHtml, ttTd,
          ttTh, ttTr:
        discard
      else: return reprocess imInTable
    else: return reprocess imInTable

  of imInRow:
    case parser.tok.t
    of ttStartTag:
      case parser.toTagType(parser.tok.tagname)
      of ttTh, ttTd:
        parser.popTableRowContext()
        discard parser.insertHTMLElement()
        parser.insertionMode = imInCell
        parser.activeFormatting.add(nil)
      of ttCaption, ttCol, ttColgroup, ttTbody, ttTfoot, ttThead,
          ttTr:
        if parser.hasElementInTableScope(ttTr):
          parser.popTableRowContext()
          discard parser.popElement()
          parser.insertionMode = imInTableBody
          return reprocess
      else: return reprocess imInTable
    of ttEndTag:
      case (let tokTagType = parser.toTagType(parser.tok.tagname); tokTagType)
      of ttTr:
        if parser.hasElementInTableScope(ttTr):
          parser.popTableRowContext()
          discard parser.popElement()
          parser.insertionMode = imInTableBody
      of ttTable:
        if parser.hasElementInTableScope(ttTr):
          parser.popTableRowContext()
          discard parser.popElement()
          parser.insertionMode = imInTableBody
          return reprocess
      of ttTbody, ttTfoot, ttThead:
        if parser.hasElementInTableScope({tokTagType, ttTr}):
          parser.popTableRowContext()
          discard parser.popElement()
          parser.insertionMode = imInTableBody
          return reprocess
      of ttBody, ttCaption, ttCol, ttColgroup, ttHtml, ttTd,
          ttTh:
        discard
      else: return reprocess imInTable
    else: return reprocess imInTable

  of imInCell:
    case parser.tok.t
    of ttStartTag:
      case parser.toTagType(parser.tok.tagname)
      of ttCaption, ttCol, ttColgroup, ttTbody, ttTd, ttTfoot,
          ttTh, ttThead, ttTr:
        if parser.hasElementInTableScope({ttTd, ttTh}):
          parser.closeCell()
          return reprocess
      else: return reprocess imInBody
    of ttEndTag:
      case (let tokTagType = parser.toTagType(parser.tok.tagname); tokTagType)
      of ttTd, ttTh:
        if parser.hasElementInTableScope(tokTagType):
          parser.popElementsIncl(tokTagType)
          parser.clearActiveFormattingTillMarker()
          parser.insertionMode = imInRow
      of ttBody, ttCaption, ttCol, ttColgroup, ttHtml: discard
      of ttTable, ttTbody, ttTfoot, ttThead, ttTr:
        if parser.hasElementInTableScope(tokTagType):
          parser.closeCell()
          return reprocess
      else: return reprocess imInBody
    else: return reprocess imInBody

  of imInTemplate:
    case parser.tok.t
    of ttCharacter, ttWhitespace, ttNull, ttDoctype, ttComment:
      return reprocess imInBody
    of ttStartTag:
      case parser.toTagType(parser.tok.tagname)
      of ttBase, ttBasefont, ttBgsound, ttLink, ttMeta, ttNoframes,
          ttScript, ttStyle, ttTemplate, ttTitle:
        return reprocess imInHead
      of ttCaption, ttColgroup, ttTbody, ttTfoot, ttThead:
        discard parser.templateModes.pop()
        parser.templateModes.add(imInTable)
        parser.insertionMode = imInTable
        return reprocess
      of ttCol:
        discard parser.templateModes.pop()
        parser.templateModes.add(imInColumnGroup)
        parser.insertionMode = imInColumnGroup
        return reprocess
      of ttTr:
        discard parser.templateModes.pop()
        parser.templateModes.add(imInTableBody)
        parser.insertionMode = imInTableBody
        return reprocess
      of ttTd, ttTh:
        discard parser.templateModes.pop()
        parser.templateModes.add(imInRow)
        parser.insertionMode = imInRow
        return reprocess
      else:
        discard parser.templateModes.pop()
        parser.templateModes.add(imInBody)
        parser.insertionMode = imInBody
        return reprocess
    of ttEndTag:
      if parser.toTagType(parser.tok.tagname) == ttTemplate:
        return reprocess imInHead

  of imAfterBody:
    case parser.tok.t
    of ttWhitespace: return reprocess imInBody
    of ttComment: parser.insertComment(lastChildOf(parser.openElements[0]))
    of ttDoctype: discard
    of ttStartTag:
      if parser.toTagType(parser.tok.tagname) == ttHtml:
        return reprocess imInBody
      parser.insertionMode = imInBody
      return reprocess
    of ttEndTag:
      if parser.toTagType(parser.tok.tagname) == ttHtml:
        if parser.ctx.isNone:
          parser.insertionMode = imAfterAfterBody
      else:
        parser.insertionMode = imInBody
        return reprocess
    else:
      parser.insertionMode = imInBody
      return reprocess

  of imInFrameset:
    case parser.tok.t
    of ttWhitespace: parser.insertCharacter(parser.tok.charbufOut)
    of ttComment: parser.insertComment()
    of ttDoctype: discard
    of ttStartTag:
      case parser.toTagType(parser.tok.tagname)
      of ttHtml: return reprocess imInBody
      of ttFrameset: discard parser.insertHTMLElement()
      of ttFrame: parser.insertHTMLElementPop()
      of ttNoframes: return reprocess imInHead
      else: discard
    of ttEndTag:
      if parser.toTagType(parser.tok.tagname) == ttFrameset:
        if parser.getTagType(parser.currentNode) != ttHtml:
          discard parser.popElement()
        if parser.ctx.isNone and
            parser.getTagType(parser.currentNode) != ttFrameset:
          parser.insertionMode = imAfterFrameset
    else: discard

  of imAfterFrameset:
    case parser.tok.t
    of ttWhitespace: parser.insertCharacter(parser.tok.charbufOut)
    of ttComment: parser.insertComment()
    of ttStartTag:
      case parser.toTagType(parser.tok.tagname)
      of ttHtml: return reprocess imInBody
      of ttNoframes: return reprocess imInHead
      else: discard
    of ttEndTag:
      if parser.toTagType(parser.tok.tagname) == ttHtml:
        parser.insertionMode = imAfterAfterFrameset
    else: discard

  of imAfterAfterBody:
    case parser.tok.t
    of ttComment: parser.insertComment(lastChildOf(parser.getDocument()))
    of ttDoctype, ttWhitespace: return reprocess imInBody
    of ttStartTag:
      if parser.toTagType(parser.tok.tagname) == ttHtml:
        return reprocess imInBody
      parser.insertionMode = imInBody
      return reprocess
    else:
      parser.insertionMode = imInBody
      return reprocess

  of imAfterAfterFrameset:
    case parser.tok.t
    of ttComment: parser.insertComment(lastChildOf(parser.getDocument()))
    of ttDoctype, ttWhitespace: return reprocess imInBody
    of ttStartTag:
      case parser.toTagType(parser.tok.tagname)
      of ttHtml: return reprocess imInBody
      of ttNoframes: return reprocess imInHead
      else: discard
    else: discard
  return pcrContinue

proc processEOF[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  var insertionMode = parser.insertionMode
  if insertionMode == imInitial:
    parser.setQuirksMode(qmQuirks)
    insertionMode = imBeforeHtml
  if insertionMode == imBeforeHtml:
    let element = parser.createHTMLElement()
    parser.append(parser.getDocument(), element)
    parser.pushHTMLElement(element)
    insertionMode = imBeforeHead
  if insertionMode == imBeforeHead:
    parser.head = some(parser.insertHTMLElement(ttHead))
    insertionMode = imInHead
  if insertionMode == imInHeadNoscript:
    discard parser.popElement()
    insertionMode = imInHead
  if insertionMode == imInHead:
    discard parser.popElement()
    insertionMode = imAfterHead
  if insertionMode == imAfterHead:
    discard parser.insertHTMLElement(ttBody)
    insertionMode = imInBody
  case insertionMode
  of imInBody, imInCaption, imInColumnGroup, imInCell, imInTable, imInTableBody,
      imInRow, imInTemplate:
    if parser.templateModes.len > 0 and parser.hasElement(ttTemplate):
      parser.popElementsIncl(ttTemplate)
      parser.clearActiveFormattingTillMarker()
      discard parser.templateModes.pop()
      parser.resetInsertionMode()
      parser.processEOF()
  of imText:
    if parser.getTagType(parser.currentNode) == ttScript:
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

proc processHTMLForeignTag[Handle, Atom](
    parser: var HTML5Parser[Handle, Atom]): ParseChunkResult =
  while not parser.isMathMLIntegrationPoint(parser.currentNode) and
      not parser.isHTMLIntegrationPoint(parser.currentNodeToken) and
      parser.getNamespace(parser.currentNode) != nsHTML:
    discard parser.popElement()
  return parser.processInHTML(parser.insertionMode)

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

proc otherForeignStartTag[Handle, Atom](parser: var HTML5Parser[Handle, Atom]):
    ParseChunkResult =
  let namespace = parser.getNamespace(parser.adjustedCurrentNode)
  var tagname = parser.tok.tagname
  if namespace == nsSVG:
    if parser.caseTable.len == 0:
      for (k, v) in CaseTable:
        let ka = parser.strToAtom(k)
        let va = parser.strToAtom(v)
        parser.caseTable[ka] = va
    parser.caseTable.withValue(tagname, p):
      tagname = p[]
    parser.adjustSVGAttributes()
  elif namespace == nsMathML:
    parser.adjustMathMLAttributes()
  discard parser.insertForeignElement(tagname, parser.tok.tagname, namespace, false,
    move(parser.tok.attrs))
  if tfSelfClosing in parser.tok.flags:
    discard parser.popElement()
    if namespace == nsSVG and parser.toTagType(tagname) == ttScript:
      return pcrScript
  return pcrContinue

proc otherForeignEndTag[Handle, Atom](parser: var HTML5Parser[Handle, Atom]):
    ParseChunkResult =
  for i in countdown(parser.openElements.high, 0): # loop
    if i == 0: # fragment case
      assert parser.ctx.isSome
      break
    let oe = parser.openElements[i]
    if i != parser.openElements.high and
        parser.getNamespace(oe.element) == nsHTML:
      return parser.processInHTML(parser.insertionMode)
    if oe.startTagName == parser.tok.tagname:
      # Compare the start tag token, since it is guaranteed to be lower case.
      # (The local name might have been adjusted to a non-lower-case string.)
      parser.popElementsIncl(oe.element)
      break
  return pcrContinue

proc processInForeign[Handle, Atom](parser: var HTML5Parser[Handle, Atom]):
    ParseChunkResult =
  case parser.tok.t
  of ttNull: parser.insertCharacter("\uFFFD")
  of ttWhitespace: parser.insertCharacter(parser.tok.charbufOut)
  of ttCharacter:
    parser.insertCharacter(parser.tok.charbufOut)
    parser.framesetOk = false
  of ttComment: parser.insertComment()
  of ttDoctype: discard
  of ttStartTag:
    case parser.toTagType(parser.tok.tagname)
    of ttB, ttBig, ttBlockquote, ttBody, ttBr, ttCenter, ttCode,
        ttDd, ttDiv, ttDl, ttDt, ttEm, ttEmbed, ttH1, ttH2,
        ttH3, ttH4, ttH5, ttH6, ttHead, ttHr, ttI, ttImg,
        ttLi, ttListing, ttMenu, ttMeta, ttNobr, ttOl, ttP,
        ttPre, ttRuby, ttS, ttSmall, ttSpan, ttStrong, ttStrike,
        ttSub, ttSup, ttTable, ttTt, ttU, ttUl, ttVar:
      return parser.processHTMLForeignTag()
    of ttFont:
      let atColor = parser.toAtom(ttColor)
      let atFace = parser.toAtom(ttFace)
      let atSize = parser.toAtom(ttSize)
      if atColor in parser.tok.attrs or
          atFace in parser.tok.attrs or
          atSize in parser.tok.attrs:
        return parser.processHTMLForeignTag()
      # fall through
    else: discard
    return parser.otherForeignStartTag()
  of ttEndTag:
    case parser.toTagType(parser.tok.tagname)
    of ttBr, ttP: return parser.processHTMLForeignTag()
    of ttScript:
      let namespace = parser.getNamespace(parser.currentNode)
      let localName = parser.currentTagName
      # Any atom corresponding to the string "script" must have the same
      # value as ttScript, so this is correct.
      if namespace == nsSVG and parser.toTagType(localName) == ttScript:
        discard parser.popElement()
        if parser.scripting:
          return pcrScript
      # fall through
    else: discard
    return parser.otherForeignEndTag()
  return pcrContinue

proc processToken[Handle, Atom](parser: var HTML5Parser[Handle, Atom]):
    ParseChunkResult =
  if parser.ignoreLF:
    parser.ignoreLF = false
    if parser.tok.t == ttWhitespace and parser.tok.charbufOut[0] == '\n':
      if parser.tok.charbufOut.len == 1:
        return pcrContinue
      else:
        for i in 1 ..< parser.tok.charbufOut.len:
          parser.tok.charbufOut[i - 1] = parser.tok.charbufOut[i]
        parser.tok.charbufOut.setLen(parser.tok.charbufOut.high)
  if parser.openElements.len == 0 or
      parser.getNamespace(parser.adjustedCurrentNode) == nsHTML:
    return parser.processInHTML(parser.insertionMode)
  let oe = parser.adjustedCurrentNodeToken
  let oeTagType = parser.toTagType(oe.startTagName)
  let namespace = parser.getNamespace(oe.element)
  const CharacterToken = {ttCharacter, ttWhitespace, ttNull}
  let mmlnoatoms = {ttMglyph, ttMalignmark}
  let ismmlip = parser.isMathMLIntegrationPoint(oe.element)
  let ishtmlip = parser.isHTMLIntegrationPoint(oe)
  if parser.tok.t == ttStartTag and (
        let tagType = parser.toTagType(parser.tok.tagname)
        ismmlip and tagType notin mmlnoatoms or ishtmlip or
        namespace == nsMathML and oeTagType == ttAnnotationXml and
          tagType == ttSvg
      ) or parser.tok.t in CharacterToken and (ismmlip or ishtmlip):
    return parser.processInHTML(parser.insertionMode)
  return parser.processInForeign()

proc initHTML5Parser*[Handle, Atom](dombuilder: DOMBuilder[Handle, Atom];
    opts: HTML5ParserOpts[Handle, Atom]): HTML5Parser[Handle, Atom] =
  ## Create and initialize a new HTML5Parser object from dombuilder `dombuilder`
  ## and parser options `opts`.
  ##
  ## The generic `Handle` must be the node handle type of the DOM builder. The
  ## generic `Atom` must be the interned string type of the DOM builder.
  var parser = HTML5Parser[Handle, Atom](
    scripting: opts.scripting,
    isIframeSrcdoc: opts.isIframeSrcdoc,
    form: opts.formInit,
    framesetOk: true,
    tok: initTokenizer[Handle, Atom](dombuilder)
  )
  if opts.ctx.isSome:
    let ctxInit = opts.ctx.get
    case parser.getTagType(ctxInit)
    of ttTitle, ttTextarea:
      parser.tok.state = tsRcdata
    of ttStyle, ttXmp, ttIframe, ttNoembed, ttNoframes, ttScript,
        ttPlaintext:
      parser.tok.state = tsPlaintext
    of ttNoscript:
      if opts.scripting:
        parser.tok.state = tsPlaintext
    of ttTemplate:
      parser.templateModes.add(imInTemplate)
    else: discard
    let ctx = OpenElement[Handle, Atom](
      element: ctxInit,
      startTagName: parser.getLocalName(ctxInit),
      integrationPoint: opts.ctxIsIntegrationPoint
    )
    parser.ctx = some(ctx)
  if opts.openElementsInit.isSome:
    parser.pushHTMLElement(opts.openElementsInit.get)
    parser.resetInsertionMode()
  return parser

proc parseChunk*[Handle, Atom](parser: var HTML5Parser[Handle, Atom];
    inputBuf: openArray[char]): ParseChunkResult =
  ## Parse a chunk of characters stored in `inputBuf` with `parser`.
  parser.tok.inputBufIdx = 0
  while parser.tok.tokenize(inputBuf) == trEmit:
    let pres = parser.processToken()
    if pres != pcrContinue:
      return pres
  return pcrContinue

proc getInsertionPoint*(parser: HTML5Parser): int =
  return parser.tok.inputBufIdx

proc finish*[Handle, Atom](parser: var HTML5Parser[Handle, Atom]) =
  ## Finish parsing the document associated with `parser`.
  ## This will process an EOF token, and pop all elements from the stack of
  ## open elements one by one.
  while parser.tok.finish() != trDone:
    let pres = parser.processToken()
    assert pres == pcrContinue
    # pres == pcrScript: this is unreachable.
    # * Tokenizer's finish() can not emit end tag tokens, ergo no
    #   </script> will be processed here.
    # * In some cases, tokenize() is called before finish(), to flush
    #   characters stuck in the internal peekBuf. This can happen if:
    #   1. eatStr returns esrRetry in a previous pass. Here, peekBuf can
    #      contain any prefix of strings passed to eatStr/NoCase(), which
    #      crucially is never a potential </script> tag (or indeed,
    #      nothing that can start with </).
    #   2. The "named character reference" state is interrupted. In this
    #      case, peekBuf is a prefix of at least one named character
    #      reference; obviously these can not be </script> tags either,
    #      since they all match the regex `&[a-zA-Z]+'.
    # pres == pcrStop: unreachable for reasons almost identical to those
    # outlined in pcrScript. pcrStop can only be returned after a <meta>
    # tag is processed; just like with end tags, the tokenizer cannot emit
    # start tags in finish().
  parser.processEOF()
  while parser.openElements.len > 0:
    discard parser.popElement()
