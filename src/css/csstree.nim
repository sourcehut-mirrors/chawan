# Tree building.
#
# This wouldn't be nearly as complex as it is if not for CSS's asinine
# anonymous table box generation rules.  In particular:
# * Runs of misparented boxes inside a table/table row/table row group
#   must be placed in appropriate anonymous wrappers.  For example, if
#   we encounter two consecutive `display: block's inside a `display:
#   table-row', these must be wrapped around a single `display:
#   table-cell'.
# * Runs of misparented table row/table row group/table cell boxes must
#   be wrapped in an anonymous table, or in some cases an anonymous
#   table row and *then* an anonymous table.  e.g. a `display:
#   table-row', `display: table-cell', then a `display: table-row-group'
#   will all be wrapped in a single table.
# * If this weren't enough, we also have to *split up* the entire table
#   into an inner and an outer table.  The outer table wraps the inner
#   table and the caption.  The inner table (of DisplayTableWrapper)
#   includes the rows/row groups.
# Whatever your reason may be for looking at this: good luck.

import chame/tags
import css/cascade
import css/cssvalues
import css/selectorparser
import html/catom
import html/dom
import types/bitmap
import types/color
import utils/twtstr

type
  StyledType* = enum
    stElement, stText, stImage, stBr

  # Abstraction over the DOM to pretend that elements, text, replaced
  # and pseudo-elements are derived from the same type.
  StyledNode* = object
    element*: Element
    computed*: CSSValues
    pseudo*: PseudoElement
    skipChildren: bool
    case t*: StyledType
    of stText:
      text*: CharacterData
    of stElement:
      anonChildren: seq[StyledNode]
    of stImage:
      bmp*: NetworkBitmap
    of stBr: # <br> element
      discard

  TreeContext* = object
    quoteLevel: int
    listItemCounter: int

  TreeFrame = object
    parent: Element
    computed: CSSValues
    children: seq[StyledNode]
    lastChildWasInline: bool
    captionSeen: bool
    anonTableDisplay: CSSDisplay
    anonComputed: CSSValues
    anonInlineComputed: CSSValues
    pctx: ptr TreeContext

template ctx(frame: TreeFrame): var TreeContext =
  frame.pctx[]

when defined(debug):
  func `$`*(node: StyledNode): string =
    case node.t
    of stText:
      return node.text.data
    of stElement:
      if node.pseudo != peNone:
        return $node.element.tagType & "::" & $node.pseudo
      return $node.element
    of stImage:
      return "#image"
    of stBr:
      return "#br"

# Root
proc initStyledElement*(element: Element): StyledNode =
  if element.computed == nil:
    element.applyStyle()
  result = StyledNode(
    t: stElement,
    element: element,
    computed: element.computed
  )

func inheritFor(frame: TreeFrame; display: CSSDisplay): CSSValues =
  result = frame.computed.inheritProperties()
  result{"display"} = display

proc initTreeFrame(ctx: var TreeContext; parent: Element; computed: CSSValues):
    TreeFrame =
  result = TreeFrame(parent: parent, computed: computed, pctx: addr ctx)

proc getAnonInlineComputed(frame: var TreeFrame): CSSValues =
  if frame.anonInlineComputed == nil:
    if frame.computed{"display"} == DisplayInline:
      frame.anonInlineComputed = frame.computed
    else:
      frame.anonInlineComputed = frame.computed.inheritProperties()
  return frame.anonInlineComputed

proc displayed(frame: TreeFrame; text: CharacterData): bool =
  if text.data.len == 0:
    return false
  return frame.computed{"display"} == DisplayInline or
    frame.lastChildWasInline or
    frame.computed{"white-space"} in WhiteSpacePreserve or
    not text.data.onlyWhitespace()

#TODO implement table columns
const DisplayNoneLike = {
  DisplayNone, DisplayTableColumn, DisplayTableColumnGroup
}

proc displayed(frame: TreeFrame; pseudo: PseudoElement): bool =
  return frame.parent.computedMap[pseudo] != nil and
    frame.parent.computedMap[pseudo]{"content"}.len > 0 and
    frame.parent.computedMap[pseudo]{"display"} notin DisplayNoneLike

proc displayed(frame: TreeFrame; element: Element): bool =
  return element.computed{"display"} notin DisplayNoneLike

proc getInternalTableParent(frame: var TreeFrame; display: CSSDisplay):
    var seq[StyledNode] =
  if frame.anonTableDisplay != display:
    if frame.anonComputed == nil:
      frame.anonComputed = frame.inheritFor(display)
    frame.anonTableDisplay = display
    frame.children.add(StyledNode(
      t: stElement,
      element: frame.parent,
      computed: frame.anonComputed,
      skipChildren: true
    ))
  return frame.children[^1].anonChildren

# Add an anonymous table to children, and return based on display either
# * row, row group: the table children
# * cell: its last anonymous row (if there isn't one, create it)
# * caption: its outer box
proc addAnonTable(frame: var TreeFrame; parentDisplay, display: CSSDisplay):
    var seq[StyledNode] =
  if frame.anonComputed == nil or
      frame.anonComputed{"display"} notin DisplayInnerTable + {DisplayTableRow}:
    let anonDisplay = if parentDisplay == DisplayInline:
      DisplayInlineTable
    else:
      DisplayTable
    let (outer, inner) = frame.inheritFor(anonDisplay).splitTable()
    frame.anonComputed = outer
    frame.children.add(StyledNode(
      t: stElement,
      computed: outer,
      skipChildren: true,
      anonChildren: @[StyledNode(
        t: stElement,
        computed: inner,
        skipChildren: true
      )]
    ))
  if display == DisplayTableCaption:
    frame.anonComputed = frame.children[^1].computed
    return frame.children[^1].anonChildren
  if display in RowGroupBox + {DisplayTableRow}:
    frame.anonComputed = frame.children[^1].computed
    return frame.children[^1].anonChildren[0].anonChildren
  assert display == DisplayTableCell
  if frame.anonComputed{"display"} == DisplayTableRow:
    return frame.children[^1].anonChildren[0].anonChildren[^1].anonChildren
  frame.anonComputed = frame.inheritFor(DisplayTableRow)
  frame.children[^1].anonChildren[0].anonChildren.add(StyledNode(
    t: stElement,
    element: frame.parent,
    computed: frame.anonComputed,
    skipChildren: true
  ))
  return frame.children[^1].anonChildren[0].anonChildren[^1].anonChildren

proc getParent(frame: var TreeFrame; computed: CSSValues; display: CSSDisplay):
    var seq[StyledNode] =
  let parentDisplay = frame.computed{"display"}
  case parentDisplay
  of DisplayInnerFlex:
    if display in DisplayOuterInline:
      if frame.anonComputed == nil:
        frame.anonComputed = frame.inheritFor(DisplayBlock)
      frame.children.add(StyledNode(
        t: stElement,
        element: frame.parent,
        computed: frame.anonComputed,
        skipChildren: true
      ))
      return frame.children[^1].anonChildren
  of DisplayTableRow:
    if display != DisplayTableCell:
      return frame.getInternalTableParent(DisplayTableCell)
    frame.anonTableDisplay = DisplayNone
  of RowGroupBox:
    if display != DisplayTableRow:
      return frame.getInternalTableParent(DisplayTableRow)
    frame.anonTableDisplay = DisplayNone
  of DisplayTableWrapper:
    if display notin RowGroupBox + {DisplayTableRow}:
      return frame.getInternalTableParent(DisplayTableRow)
    frame.anonTableDisplay = DisplayNone
  of DisplayInnerTable:
    if frame.children.len > 0 and display != DisplayTableCaption:
      return frame.children[0].anonChildren
  of DisplayListItem:
    if frame.computed{"list-style-position"} == ListStylePositionOutside and
        frame.children.len >= 2:
      return frame.children[1].anonChildren
  elif display in DisplayInternalTable:
    return frame.addAnonTable(parentDisplay, display)
  else:
    frame.captionSeen = false
    frame.anonComputed = nil
  return frame.children

proc addListItem(frame: var TreeFrame; node: sink StyledNode) =
  var node = node
  # Generate a marker box.
  inc frame.ctx.listItemCounter
  let computed = node.computed.inheritProperties()
  computed{"display"} = DisplayBlock
  computed{"white-space"} = WhitespacePre
  let t = computed{"list-style-type"}
  let markerText = StyledNode(
    t: stText,
    element: node.element,
    text: newCharacterData(t.listMarker(frame.ctx.listItemCounter)),
    computed: computed.inheritProperties()
  )
  case node.computed{"list-style-position"}
  of ListStylePositionOutside:
    # Generate a separate box for the content and marker.
    node.anonChildren.add(StyledNode(
      t: stElement,
      element: node.element,
      computed: computed,
      skipChildren: true,
      anonChildren: @[markerText]
    ))
    let computed = node.computed.inheritProperties()
    computed{"display"} = DisplayBlock
    node.anonChildren.add(StyledNode(
      t: stElement,
      element: node.element,
      computed: computed,
      skipChildren: true
    ))
  of ListStylePositionInside:
    node.anonChildren.add(markerText)
  frame.getParent(node.computed, node.computed{"display"}).add(node)

proc addTable(frame: var TreeFrame; node: sink StyledNode) =
  var node = node
  let (outer, inner) = node.computed.splitTable()
  node.computed = outer
  node.anonChildren.add(StyledNode(
    t: stElement,
    element: node.element,
    computed: inner,
    skipChildren: true
  ))
  frame.getParent(node.computed, node.computed{"display"}).add(node)

proc add(frame: var TreeFrame; node: sink StyledNode) =
  let display = node.computed{"display"}
  if frame.captionSeen and display == DisplayTableCaption:
    return
  if node.t == stElement and node.anonChildren.len == 0:
    case display
    of DisplayListItem:
      frame.addListItem(node)
      frame.lastChildWasInline = false
      return # already added
    of DisplayInnerTable:
      frame.addTable(node)
      frame.lastChildWasInline = false
      return # already added
    else: discard
  frame.getParent(node.computed, display).add(node)
  frame.lastChildWasInline = display in DisplayOuterInline
  if display == DisplayTableCaption:
    frame.captionSeen = true

proc addAnon(frame: var TreeFrame; children: sink seq[StyledNode];
    computed: CSSValues) =
  frame.add(StyledNode(
    t: stElement,
    element: frame.parent,
    anonChildren: children,
    computed: computed,
    skipChildren: true
  ))

proc addElement(frame: var TreeFrame; element: Element) =
  if element.computed == nil:
    element.applyStyle()
  if frame.displayed(element):
    frame.add(StyledNode(
      t: stElement,
      element: element,
      computed: element.computed
    ))

proc addPseudo(frame: var TreeFrame; pseudo: PseudoElement) =
  if frame.displayed(pseudo):
    frame.add(StyledNode(
      t: stElement,
      pseudo: pseudo,
      element: frame.parent,
      computed: frame.parent.computedMap[pseudo]
    ))

proc addText(frame: var TreeFrame; text: CharacterData) =
  if frame.displayed(text):
    frame.add(StyledNode(
      t: stText,
      element: frame.parent,
      text: text,
      computed: frame.getAnonInlineComputed()
    ))

proc addText(frame: var TreeFrame; s: sink string) =
  #TODO should probably cache these...
  frame.addText(newCharacterData(s))

proc addImage(frame: var TreeFrame; bmp: NetworkBitmap) =
  if bmp != nil and bmp.cacheId != -1:
    frame.add(StyledNode(
      t: stImage,
      element: frame.parent,
      bmp: bmp,
      computed: frame.getAnonInlineComputed()
    ))
  else:
    frame.addText("[img]")

proc addBr(frame: var TreeFrame) =
  frame.add(StyledNode(
    t: stBr,
    element: frame.parent,
    computed: frame.computed
  ))

proc addElementChildren(frame: var TreeFrame) =
  for it in frame.parent.childList:
    if it of Element:
      let element = Element(it)
      frame.addElement(element)
    elif it of Text:
      #TODO collapse subsequent text nodes into one StyledNode
      # (it isn't possible in HTML, only with JS DOM manipulation)
      let text = Text(it)
      frame.addText(text)

proc addOptionChildren(frame: var TreeFrame; option: HTMLOptionElement) =
  if option.select != nil and option.select.attrb(satMultiple):
    frame.addText("[")
    let cdata = newCharacterData(if option.selected: "*" else: " ")
    let computed = option.computed.inheritProperties()
    computed{"color"} = cssColor(ANSIColor(1)) # red
    computed{"white-space"} = WhitespacePre
    block anon:
      var aframe = frame.ctx.initTreeFrame(option, computed)
      aframe.addText(cdata)
      frame.addAnon(move(aframe.children), computed)
    frame.addText("]")
  frame.addElementChildren()

proc addChildren(frame: var TreeFrame) =
  case frame.parent.tagType
  of TAG_INPUT:
    let cdata = HTMLInputElement(frame.parent).inputString()
    if cdata != nil:
      frame.addText(cdata)
  of TAG_TEXTAREA:
    #TODO cache (do the same as with input, and add borders in render)
    frame.addText(HTMLTextAreaElement(frame.parent).textAreaString())
  of TAG_IMG: frame.addImage(HTMLImageElement(frame.parent).bitmap)
  of TAG_CANVAS: frame.addImage(HTMLCanvasElement(frame.parent).bitmap)
  of TAG_VIDEO: frame.addText("[video]")
  of TAG_AUDIO: frame.addText("[audio]")
  of TAG_BR: frame.addBr()
  of TAG_IFRAME: frame.addText("[iframe]")
  of TAG_FRAME: frame.addText("[frame]")
  of TAG_OPTION:
    let option = HTMLOptionElement(frame.parent)
    frame.addOptionChildren(option)
  elif frame.parent.tagType(Namespace.SVG) == TAG_SVG:
    frame.addImage(SVGSVGElement(frame.parent).bitmap)
  else:
    frame.addElementChildren()

proc addContent(frame: var TreeFrame; content: CSSContent; ctx: var TreeContext;
    computed: CSSValues) =
  case content.t
  of ContentString:
    frame.addText(content.s)
  of ContentOpenQuote:
    let quotes = frame.computed{"quotes"}
    if quotes == nil:
      frame.addText(quoteStart(ctx.quoteLevel))
    elif quotes.qs.len > 0:
      frame.addText(quotes.qs[min(ctx.quoteLevel, quotes.qs.high)].s)
    else:
      return
    inc ctx.quoteLevel
  of ContentCloseQuote:
    if ctx.quoteLevel > 0:
      dec ctx.quoteLevel
    let quotes = computed{"quotes"}
    if quotes == nil:
      frame.addText(quoteEnd(ctx.quoteLevel))
    elif quotes.qs.len > 0:
      frame.addText(quotes.qs[min(ctx.quoteLevel, quotes.qs.high)].e)
  of ContentNoOpenQuote:
    inc ctx.quoteLevel
  of ContentNoCloseQuote:
    if ctx.quoteLevel > 0:
      dec ctx.quoteLevel

proc build(frame: var TreeFrame; styledNode: StyledNode;
    ctx: var TreeContext) =
  for child in styledNode.anonChildren:
    frame.add(child)
  if styledNode.skipChildren:
    return
  let parent = styledNode.element
  if styledNode.pseudo == peNone:
    frame.addPseudo(peBefore)
    frame.addChildren()
    frame.addPseudo(peAfter)
  else:
    let computed = parent.computedMap[styledNode.pseudo].inheritProperties()
    for content in parent.computedMap[styledNode.pseudo]{"content"}:
      frame.addContent(content, ctx, computed)

iterator children*(styledNode: StyledNode; ctx: var TreeContext): StyledNode
    {.inline.} =
  if styledNode.t == stElement:
    for reset in styledNode.computed{"counter-reset"}:
      if reset.name == "list-item":
        ctx.listItemCounter = reset.num
    let listItemCounter = ctx.listItemCounter
    let parent = styledNode.element
    var frame = ctx.initTreeFrame(parent, styledNode.computed)
    frame.build(styledNode, ctx)
    for child in frame.children:
      yield child
    ctx.listItemCounter = listItemCounter

when defined(debug):
  proc computedTree*(styledNode: StyledNode; ctx: var TreeContext): string =
    result = ""
    if styledNode.t != stElement:
      result &= $styledNode
    else:
      result &= "<"
      if styledNode.computed{"display"} != DisplayInline:
        result &= "div"
      else:
        result &= "span"
      let computed = styledNode.computed.copyProperties()
      if computed{"display"} == DisplayBlock:
        computed{"display"} = DisplayInline
      result &= " style='" & $computed.serializeEmpty() & "'>\n"
      for it in styledNode.children(ctx):
        result &= it.computedTree(ctx)
      result &= "\n</div>"

  proc computedTree*(styledNode: StyledNode): string =
    var ctx = TreeContext()
    return styledNode.computedTree(ctx)
