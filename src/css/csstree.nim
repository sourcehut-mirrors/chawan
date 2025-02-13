# Tree building.
#
#TODO: this is currently a separate pass from layout, meaning at least
# two tree traversals are required.  Ideally, these should be collapsed
# into a single pass, reusing parts of previous layout passes when
# possible.
#
# ---
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
import css/box
import css/cascade
import css/cssvalues
import css/lunit
import css/selectorparser
import html/catom
import html/dom
import types/bitmap
import types/color
import types/refstring
import utils/twtstr

type
  StyledNodeType = enum
    stElement, stText, stMarker, stImage, stBr

  # Abstraction over the DOM to pretend that elements, text, replaced
  # and pseudo-elements are derived from the same type.
  StyledNode = object
    element: Element
    computed: CSSValues
    pseudo: PseudoElement
    skipChildren: bool
    case t: StyledNodeType
    of stText:
      text: RefString
    of stElement:
      anonChildren: seq[StyledNode]
    of stImage:
      bmp: NetworkBitmap
    of stBr: # <br> element
      discard
    of stMarker: # ::marker (not that it's implemented...)
      discard

  CSSCounter = object
    element: Element
    name: CAtom
    n: int32

  TreeContext = object
    quoteLevel: int
    counters: seq[CSSCounter]
    rootProperties: CSSValues

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

# Forward declarations
proc build(ctx: var TreeContext; cached: CSSBox; styledNode: StyledNode): CSSBox

template ctx(frame: TreeFrame): var TreeContext =
  frame.pctx[]

when defined(debug):
  func `$`*(node: StyledNode): string =
    case node.t
    of stText:
      return node.text
    of stElement:
      if node.pseudo != peNone:
        return $node.element.tagType & "::" & $node.pseudo
      return $node.element
    of stImage:
      return "#image"
    of stBr:
      return "#br"
    of stMarker:
      return "#marker"

iterator mritems(counters: var seq[CSSCounter]): var CSSCounter =
  for i in countdown(counters.high, 0):
    yield counters[i]

proc incCounter(ctx: var TreeContext; name: CAtom; n: int32; element: Element) =
  var found = false
  for counter in ctx.counters.mritems:
    if counter.name == name:
      let n64 = clamp(int64(counter.n) + int64(n), int32.low, int32.high)
      counter.n = int32(n64)
      found = true
      break
  if not found: # instantiate a new counter
    ctx.counters.add(CSSCounter(name: name, n: n, element: element))

proc setCounter(ctx: var TreeContext; name: CAtom; n: int32; element: Element) =
  var found = false
  for counter in ctx.counters.mritems:
    if counter.name == name:
      counter.n = n
      found = true
      break
  if not found: # instantiate a new counter
    ctx.counters.add(CSSCounter(name: name, n: n, element: element))

proc resetCounter(ctx: var TreeContext; name: CAtom; n: int32;
    element: Element) =
  var found = false
  for counter in ctx.counters.mritems:
    if counter.name == name and
        counter.element.parentNode == element.parentNode and
        counter.element.elIndex <= element.elIndex:
      counter.element = element
      counter.n = n
      found = true
      break
  if not found:
    ctx.counters.add(CSSCounter(name: name, n: n, element: element))

proc counter(ctx: var TreeContext; name: CAtom): int =
  for counter in ctx.counters.mritems:
    if counter.name == name:
      return counter.n
  return 0

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

proc displayed(frame: TreeFrame; text: RefString): bool =
  if text.len == 0:
    return false
  return frame.computed{"display"} == DisplayInline or
    frame.lastChildWasInline or
    frame.computed{"white-space"} in WhiteSpacePreserve or
    not text.onlyWhitespace()

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

proc initStyledAnon(element: Element; computed: CSSValues;
    children: sink seq[StyledNode] = @[]): StyledNode =
  result = StyledNode(
    t: stElement,
    element: element,
    anonChildren: children,
    computed: computed,
    skipChildren: true
  )

proc getInternalTableParent(frame: var TreeFrame; display: CSSDisplay):
    var seq[StyledNode] =
  if frame.anonTableDisplay != display:
    if frame.anonComputed == nil:
      frame.anonComputed = frame.inheritFor(display)
    frame.anonTableDisplay = display
    frame.children.add(initStyledAnon(frame.parent, frame.anonComputed))
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
    frame.children.add(initStyledAnon(frame.parent, outer, @[initStyledAnon(
      frame.parent,
      inner
    )]))
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
  frame.children[^1].anonChildren[0].anonChildren.add(initStyledAnon(
    frame.parent,
    frame.anonComputed
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
      frame.children.add(initStyledAnon(frame.parent, frame.anonComputed))
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
  let computed = node.computed.inheritProperties()
  computed{"white-space"} = WhitespacePre
  let markerText = StyledNode(
    t: stMarker,
    element: node.element,
    computed: computed
  )
  case node.computed{"list-style-position"}
  of ListStylePositionOutside:
    # Generate separate boxes for the content and marker.
    let computed = node.computed.inheritProperties()
    computed{"display"} = DisplayBlock
    node.anonChildren.add(initStyledAnon(node.element, computed, @[markerText]))
    node.anonChildren.add(initStyledAnon(node.element, computed))
  of ListStylePositionInside:
    node.anonChildren.add(markerText)
  frame.getParent(node.computed, node.computed{"display"}).add(node)

proc addTable(frame: var TreeFrame; node: sink StyledNode) =
  var node = node
  let (outer, inner) = node.computed.splitTable()
  node.computed = outer
  node.anonChildren.add(initStyledAnon(node.element, inner))
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

proc addAnon(frame: var TreeFrame; computed: CSSValues;
    children: sink seq[StyledNode]) =
  frame.add(initStyledAnon(frame.parent, computed, children))

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

proc addText(frame: var TreeFrame; text: RefString) =
  if frame.displayed(text):
    frame.add(StyledNode(
      t: stText,
      element: frame.parent,
      text: text,
      computed: frame.getAnonInlineComputed()
    ))

proc addText(frame: var TreeFrame; s: sink string) =
  #TODO should probably cache these...
  frame.addText(newRefString(s))

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
      frame.addText(text.data)

proc addOptionChildren(frame: var TreeFrame; option: HTMLOptionElement) =
  if option.select != nil and option.select.attrb(satMultiple):
    frame.addText("[")
    let cdata = newRefString(if option.selected: "*" else: " ")
    let computed = option.computed.inheritProperties()
    computed{"color"} = cssColor(ANSIColor(1)) # red
    computed{"white-space"} = WhitespacePre
    block anon:
      var aframe = frame.ctx.initTreeFrame(option, computed)
      aframe.addText(cdata)
      frame.addAnon(computed, move(aframe.children))
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

proc addContent(frame: var TreeFrame; content: CSSContent) =
  case content.t
  of ContentString:
    frame.addText(content.s)
  of ContentOpenQuote:
    let quotes = frame.computed{"quotes"}
    if quotes == nil:
      frame.addText(quoteStart(frame.ctx.quoteLevel))
    elif quotes.qs.len > 0:
      frame.addText(quotes.qs[min(frame.ctx.quoteLevel, quotes.qs.high)].s)
    else:
      return
    inc frame.ctx.quoteLevel
  of ContentCloseQuote:
    if frame.ctx.quoteLevel > 0:
      dec frame.ctx.quoteLevel
    let quotes = frame.computed{"quotes"}
    if quotes == nil:
      frame.addText(quoteEnd(frame.ctx.quoteLevel))
    elif quotes.qs.len > 0:
      frame.addText(quotes.qs[min(frame.ctx.quoteLevel, quotes.qs.high)].e)
  of ContentNoOpenQuote:
    inc frame.ctx.quoteLevel
  of ContentNoCloseQuote:
    if frame.ctx.quoteLevel > 0:
      dec frame.ctx.quoteLevel
  of ContentCounter:
    frame.addText($frame.ctx.counter(content.counter))

proc buildChildren(frame: var TreeFrame; styledNode: StyledNode) =
  for child in styledNode.anonChildren:
    frame.add(child)
  if not styledNode.skipChildren:
    if styledNode.pseudo == peNone:
      frame.addPseudo(peBefore)
      frame.addChildren()
      frame.addPseudo(peAfter)
    else:
      for content in frame.computed{"content"}:
        frame.addContent(content)

proc buildBox(ctx: var TreeContext; frame: TreeFrame; cached: CSSBox): CSSBox =
  var bbox: BlockBox = nil
  let display = frame.computed{"display"}
  let box = if display == DisplayInline:
    InlineBox(computed: frame.computed, element: frame.parent)
  else:
    assert display notin DisplayNoneLike
    bbox = BlockBox(computed: frame.computed, element: frame.parent)
    bbox
  for child in frame.children:
    box.children.add(ctx.build(nil, child))
  if display in DisplayInlineBlockLike:
    return InlineBlockBox(
      computed: ctx.rootProperties,
      element: frame.parent,
      box: bbox
    )
  return box

proc build(ctx: var TreeContext; cached: CSSBox; styledNode: StyledNode):
    CSSBox =
  case styledNode.t
  of stElement:
    for counter in styledNode.computed{"counter-reset"}:
      ctx.resetCounter(counter.name, counter.num, styledNode.element)
    var liSeen = false
    for counter in styledNode.computed{"counter-increment"}:
      liSeen = counter.name == satListItem.toAtom()
      ctx.incCounter(counter.name, counter.num, styledNode.element)
    if not liSeen and styledNode.computed{"display"} == DisplayListItem:
      ctx.incCounter(satListItem.toAtom(), 1, styledNode.element)
    for counter in styledNode.computed{"counter-set"}:
      ctx.setCounter(counter.name, counter.num, styledNode.element)
    let countersLen = ctx.counters.len
    var frame = ctx.initTreeFrame(styledNode.element, styledNode.computed)
    frame.buildChildren(styledNode)
    let box = ctx.buildBox(frame, cached)
    ctx.counters.setLen(countersLen)
    return box
  of stText:
    return InlineTextBox(
      computed: styledNode.computed,
      element: styledNode.element,
      text: styledNode.text
    )
  of stBr:
    return InlineNewLineBox(
      computed: styledNode.computed,
      element: styledNode.element
    )
  of stMarker:
    let counter = ctx.counter(satListItem.toAtom())
    return InlineTextBox(
      computed: styledNode.computed,
      element: styledNode.element,
      text: styledNode.computed{"list-style-type"}.listMarker(counter)
    )
  of stImage:
    return InlineImageBox(
      computed: styledNode.computed,
      element: styledNode.element,
      bmp: styledNode.bmp
    )

# Root
proc buildTree*(element: Element; cached: CSSBox): BlockBox =
  if element.computed == nil:
    element.applyStyle()
  let styledNode = StyledNode(
    t: stElement,
    element: element,
    computed: element.computed
  )
  var ctx = TreeContext(rootProperties: rootProperties())
  return BlockBox(ctx.build(cached, styledNode))
