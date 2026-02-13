# Tree building.
#
# This is currently a separate pass from layout, meaning at least two tree
# traversals are required.  (We should merge these at some point, but that
# will require some refactoring in layout as well as in the invalidation
# logic.)
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

{.push raises: [].}

import std/algorithm

import chame/tags
import css/box
import css/cascade
import css/cssparser
import css/cssvalues
import html/catom
import html/dom
import types/bitmap
import types/color
import types/refstring
import utils/twtstr

type
  StyledNodeType = enum
    stElement, stText, stBr, stCounter

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
    of stBr: # <br> element
      discard
    of stCounter: # counters
      counterName: CAtom
      counterStyle: CSSListStyleType
      counterSuffix: bool

  CSSCounter = object
    element: Element
    name: CAtom
    n: int32

  TreeContext = ref object
    markLinks: bool
    quoteLevel: int
    linkHintChars: ref seq[uint32]
    counters: seq[CSSCounter]
    stackItem: StackItem
    absoluteHead: CSSAbsolute
    absoluteTail: CSSAbsolute
    fixedHead: CSSAbsolute
    fixedTail: CSSAbsolute

  TreeFrame = object
    parent: Element
    computed: CSSValues
    pseudoComputed: CSSValues
    children: seq[StyledNode]
    lastChildWasInline: bool
    captionSeen: bool
    anonComputed: CSSValues
    anonInlineComputed: CSSValues
    ctx: TreeContext

# Forward declarations
proc build(ctx: TreeContext; cached: CSSBox; styledNode: StyledNode;
  forceZ, root: bool): CSSBox

when defined(debug):
  proc `$`*(node: StyledNode): string =
    case node.t
    of stText:
      return node.text.s
    of stElement:
      if node.pseudo != peNone:
        return $node.element.tagType & "::" & $node.pseudo
      return $node.element
    of stBr:
      return "#br"
    of stCounter:
      return "#counter"

iterator mritems(counters: var seq[CSSCounter]): var CSSCounter =
  for i in countdown(counters.high, 0):
    yield counters[i]

proc incCounter(ctx: TreeContext; name: CAtom; n: int32; element: Element) =
  var found = false
  for counter in ctx.counters.mritems:
    if counter.name == name:
      let n64 = clamp(int64(counter.n) + int64(n), int32.low, int32.high)
      counter.n = int32(n64)
      found = true
      break
  if not found: # instantiate a new counter
    ctx.counters.add(CSSCounter(name: name, n: n, element: element))

proc setCounter(ctx: TreeContext; name: CAtom; n: int32; element: Element) =
  var found = false
  for counter in ctx.counters.mritems:
    if counter.name == name:
      counter.n = n
      found = true
      break
  if not found: # instantiate a new counter
    ctx.counters.add(CSSCounter(name: name, n: n, element: element))

proc resetCounter(ctx: TreeContext; name: CAtom; n: int32;
    element: Element) =
  var found = false
  for counter in ctx.counters.mritems:
    if counter.name == name and counter.element.isPreviousSiblingOf(element):
      if name == satListItem:
        if counter.element != element:
          continue
      counter.element = element
      counter.n = n
      found = true
      break
  if not found:
    ctx.counters.add(CSSCounter(name: name, n: n, element: element))

proc counter(ctx: TreeContext; name: CAtom): int32 =
  for counter in ctx.counters.mritems:
    if counter.name == name:
      return counter.n
  return 0

proc inheritFor(frame: TreeFrame; display: CSSDisplay): CSSValues =
  result = frame.computed.inheritProperties()
  result{"display"} = display

proc initTreeFrame(ctx: TreeContext; parent: Element; computed: CSSValues):
    TreeFrame =
  result = TreeFrame(
    parent: parent,
    computed: computed,
    pseudoComputed: computed.next,
    ctx: ctx
  )

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
    not text.s.onlyWhitespace()

#TODO implement table columns
const DisplayNoneLike = {
  DisplayNone, DisplayTableColumn, DisplayTableColumnGroup
}

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
  if frame.anonComputed == nil:
    frame.anonComputed = frame.inheritFor(display)
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

proc madd(s: var seq[StyledNode]; node: StyledNode): var StyledNode =
  s.add(node)
  s[^1]

proc getParent(frame: var TreeFrame; display: CSSDisplay): var seq[StyledNode] =
  let parentDisplay = frame.computed{"display"}
  if display in DisplayInlineBlockLike and parentDisplay != DisplayInline:
    let computed = frame.getAnonInlineComputed()
    return frame.getParent(DisplayInline)
      .madd(initStyledAnon(frame.parent, computed)).anonChildren
  case parentDisplay
  of DisplayInnerFlex, DisplayInnerGrid:
    if display in DisplayOuterInline:
      if frame.anonComputed == nil:
        frame.anonComputed = frame.inheritFor(DisplayBlock)
      frame.children.add(initStyledAnon(frame.parent, frame.anonComputed))
      return frame.children[^1].anonChildren
  of DisplayTableRow:
    if display != DisplayTableCell:
      return frame.getInternalTableParent(DisplayTableCell)
    frame.anonComputed = nil
  of RowGroupBox:
    if display != DisplayTableRow:
      return frame.getInternalTableParent(DisplayTableRow)
    frame.anonComputed = nil
  of DisplayTableWrapper:
    if display notin RowGroupBox + {DisplayTableRow}:
      return frame.getInternalTableParent(DisplayTableRow)
    frame.anonComputed = nil
  of DisplayInnerTable:
    if frame.children.len > 0 and display != DisplayTableCaption:
      return frame.children[0].anonChildren
  of DisplayTableCell:
    if frame.anonComputed == nil:
      frame.anonComputed = frame.inheritFor(DisplayFlowRoot)
      frame.children.add(initStyledAnon(frame.parent, frame.anonComputed))
    return frame.children[^1].anonChildren
  elif display in DisplayInternalTable:
    return frame.addAnonTable(parentDisplay, display)
  else:
    frame.captionSeen = false
    frame.anonComputed = nil
  return frame.children

proc addListItem(frame: var TreeFrame; node: sink StyledNode) =
  var node = node
  # Generate a marker box.
  var markerComputed = node.element.getComputedStyle(peMarker)
  if markerComputed == nil:
    markerComputed = node.computed.inheritProperties()
    markerComputed{"display"} = DisplayMarker
  let textComputed = markerComputed.inheritProperties()
  textComputed{"white-space"} = WhiteSpacePre
  textComputed{"content"} = markerComputed{"content"}
  let markerText = if markerComputed{"content"}.len == 0:
    StyledNode(
      t: stCounter,
      element: node.element,
      computed: textComputed,
      counterName: satListItem.toAtom(),
      counterStyle: node.computed{"list-style-type"},
      counterSuffix: true
    )
  else:
    StyledNode(
      t: stElement,
      pseudo: peMarker,
      element: node.element,
      computed: textComputed
    )
  case node.computed{"list-style-position"}
  of ListStylePositionOutside:
    # Generate separate boxes for the content and marker.
    node.anonChildren.add(initStyledAnon(node.element, markerComputed,
      @[markerText]))
  of ListStylePositionInside:
    node.anonChildren.add(markerText)
  frame.getParent(node.computed{"display"}).add(node)

proc addTable(frame: var TreeFrame; node: sink StyledNode) =
  var node = node
  let (outer, inner) = node.computed.splitTable()
  node.computed = outer
  node.anonChildren.add(initStyledAnon(node.element, inner))
  frame.getParent(node.computed{"display"}).add(node)

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
  frame.getParent(display).add(node)
  frame.lastChildWasInline = display in DisplayOuterInline
  frame.captionSeen = frame.captionSeen or display == DisplayTableCaption

proc addAnon(frame: var TreeFrame; computed: CSSValues;
    children: sink seq[StyledNode]) =
  frame.add(initStyledAnon(frame.parent, computed, children))

proc addElement(frame: var TreeFrame; element: Element) =
  element.ensureStyle()
  if frame.displayed(element):
    frame.add(StyledNode(
      t: stElement,
      element: element,
      computed: element.computed
    ))

proc addPseudo(frame: var TreeFrame; pseudo: PseudoElement) =
  var computed = frame.pseudoComputed
  while computed != nil:
    if computed.pseudo == pseudo:
      frame.pseudoComputed = computed.next
      break
    computed = computed.next
  if computed != nil and computed{"display"} notin DisplayNoneLike and
      computed{"content"}.len > 0:
    frame.add(StyledNode(
      t: stElement,
      pseudo: pseudo,
      element: frame.parent,
      computed: computed
    ))

proc addText(frame: var TreeFrame; text: RefString) =
  if frame.displayed(text):
    frame.add(StyledNode(
      t: stText,
      element: frame.parent,
      text: text,
      computed: frame.getAnonInlineComputed()
    ))

proc addCounter(frame: var TreeFrame; name: CAtom; style: CSSListStyleType) =
  frame.add(StyledNode(
    t: stCounter,
    element: frame.parent,
    counterName: name,
    counterStyle: style,
    computed: frame.getAnonInlineComputed()
  ))

proc addText(frame: var TreeFrame; s: sink string) =
  #TODO should probably cache these...
  frame.addText(newRefString(s))

proc addImage(frame: var TreeFrame; bmp: NetworkBitmap) =
  if bmp == nil or bmp.cacheId == -1:
    # Add a placeholder text if we have no bmp.
    # (If we have bmp, render will take care of it automatically.)
    frame.addText("[img]")

proc addBr(frame: var TreeFrame) =
  frame.add(StyledNode(
    t: stBr,
    element: frame.parent,
    computed: frame.computed
  ))

proc addElementChildren(frame: var TreeFrame) =
  for it in frame.parent.shadowChildList:
    if it of Element:
      let element = Element(it)
      frame.addElement(element)
    elif it of Text:
      #TODO collapse subsequent text nodes into one StyledNode
      # (it isn't possible in HTML, only with JS DOM manipulation)
      let text = Text(it)
      frame.addText(text.data)

proc addInputChildren(frame: var TreeFrame; input: HTMLInputElement) =
  let cdata = input.inputString()
  if input.inputType in InputTypeWithSize:
    let computed = frame.computed.inheritProperties()
    let n = frame.computed{"-cha-input-intrinsic-size"}
    computed{"display"} = DisplayBlock
    computed{"width"} = cssLength(n)
    var aframe = frame.ctx.initTreeFrame(input, computed)
    if cdata != nil:
      aframe.addText(cdata)
    frame.addAnon(computed, move(aframe.children))
  else:
    if cdata != nil:
      frame.addText(cdata)

proc addOptionChildren(frame: var TreeFrame; option: HTMLOptionElement) =
  if option.select != nil and option.select.attrb(satMultiple):
    frame.addText("[")
    let cdata = newRefString(if option.selected: "*" else: " ")
    let computed = option.computed.inheritProperties()
    computed{"color"} = cssColor(ANSIColor(1)) # red
    computed{"white-space"} = WhiteSpacePre
    block anon:
      var aframe = frame.ctx.initTreeFrame(option, computed)
      aframe.addText(cdata)
      frame.addAnon(computed, move(aframe.children))
    frame.addText("]")
  frame.addElementChildren()

proc addAnchorChildren(frame: var TreeFrame; anchor: HTMLAnchorElement) =
  if frame.ctx.markLinks:
    frame.addPseudo(peLinkMarker)
  frame.addElementChildren()

proc addProgress(frame: var TreeFrame; element: Element) =
  if element.attr(satValue) != "":
    let computed = frame.computed.inheritProperties()
    computed{"display"} = DisplayBlock
    let n = frame.computed{"-cha-input-intrinsic-size"}
    computed{"width"} = cssLengthFrac(clamp(n, 0, 1))
    computed{"border-bottom-style"} = BorderStyleHash
    frame.addAnon(computed, @[])
  else:
    frame.addElementChildren()

proc addChildren(frame: var TreeFrame) =
  case frame.parent.tagType
  of TAG_INPUT: frame.addInputChildren(HTMLInputElement(frame.parent))
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
  of TAG_PROGRESS: frame.addProgress(frame.parent)
  of TAG_OPTION:
    let option = HTMLOptionElement(frame.parent)
    frame.addOptionChildren(option)
  of TAG_A:
    frame.addAnchorChildren(HTMLAnchorElement(frame.parent))
  elif frame.parent.tagType(satNamespaceSVG) == TAG_SVG:
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
    frame.addCounter(content.counter, content.counterStyle)

proc buildChildren(frame: var TreeFrame; styledNode: StyledNode) =
  for child in styledNode.anonChildren:
    frame.add(child)
  if not styledNode.skipChildren:
    if styledNode.pseudo == peNone:
      frame.addPseudo(peBefore)
      if frame.parent.hint:
        frame.addPseudo(peLinkHint)
      frame.addChildren()
      frame.addPseudo(peAfter)
    else:
      for content in frame.computed{"content"}:
        frame.addContent(content)

proc newBoxOrTakeCached(cached: CSSBox; display: CSSDisplay; node: StyledNode):
    CSSBox =
  let t = if node.skipChildren: cbtAnonymous else: cbtElement
  if cached != nil:
    cached.firstChild = nil
    return cached
  elif display == DisplayInline:
    return InlineBox(
      t: t,
      computed: node.computed,
      element: node.element,
      pseudo: node.pseudo
    )
  else:
    return BlockBox(
      t: t,
      computed: node.computed,
      element: node.element,
      pseudo: node.pseudo
    )

proc matchCache(node: StyledNode; box: CSSBox): bool =
  if box == nil or box.element != node.element:
    return false
  case box.t
  of cbtAnonymous:
    if node.skipChildren and
        node.computed{"display"} == box.computed{"display"}:
      box.computed = node.computed
      box.absolute = nil
      return true
    return false
  of cbtElement:
    # Do not reuse anon boxes as non-anon boxes, incorrect pseudo-elements,
    # or boxes of the wrong type for the display.  (Could be more granular
    # but it probably doesn't matter.)
    if node.t == stElement and not node.skipChildren and
        node.pseudo == box.pseudo and
        node.computed{"display"} == box.computed{"display"}:
      if node.computed.relayout:
        box.keepLayout = false
      box.computed = node.computed
      box.absolute = nil
      return true
    return false
  of cbtText:
    case node.t
    of stText:
      if box of InlineTextBox:
        let box = InlineTextBox(box)
        # We don't have to check computed here; it's always derived from the
        # parent so it would be pointless.
        # (That does bring up the question why we have a computed field for
        # text boxes at at all.  I really don't know...)
        box.keepLayout = box.len == node.text.len and
          (box.text == node.text or box.text.s == node.text.s)
        box.len = node.text.len
        box.computed = node.computed
        box.text = node.text
        return true
      return false
    of stBr:
      if box of InlineNewLineBox:
        # br only checks clear.  (And white-space, which is a bug.)
        if box.computed{"clear"} != node.computed{"clear"} or
            box.computed{"white-space"} != node.computed{"white-space"}:
          box.keepLayout = false
        box.computed = node.computed
        return true
      return false
    of stCounter:
      if box of InlineTextBox:
        box.computed = node.computed
        return true
      return false
    of stElement: return false

proc takeCache(node: StyledNode; box: CSSBox): CSSBox =
  if node.matchCache(box):
    box.parent = nil
    box.next = nil
    return box
  nil

proc buildInnerBox(ctx: TreeContext; frame: TreeFrame; cached: CSSBox;
    node: StyledNode): CSSBox =
  let display = frame.computed{"display"}
  var cachedIt = if cached != nil: cached.firstChild else: nil
  let box = newBoxOrTakeCached(cached, display, node)
  box.computed.relayout = false
  # Grid and flex items always respect z-index.  Other boxes only
  # respect it with position != static.
  let forceZ = display in DisplayInnerFlex + DisplayInnerGrid
  var last: CSSBox = nil
  var keepLayout = true
  for child in frame.children:
    let next = if cachedIt != nil: cachedIt.next else: nil
    let childBox = ctx.build(cachedIt, child, forceZ, root = false)
    childBox.parent = box
    if last != nil:
      last.next = childBox
    else:
      box.firstChild = childBox
    last = childBox
    keepLayout = keepLayout and childBox.keepLayout
    cachedIt = next
  box.keepLayout = box.keepLayout and keepLayout and cachedIt == nil
  box

proc applyCounters(ctx: TreeContext; styledNode: StyledNode;
    firstSetCounterIdx: var int) =
  for counter in styledNode.computed{"counter-reset"}:
    ctx.resetCounter(counter.name, counter.num, styledNode.element)
  firstSetCounterIdx = ctx.counters.len
  var liSeen = false
  for counter in styledNode.computed{"counter-increment"}:
    liSeen = liSeen or counter.name == satListItem
    ctx.incCounter(counter.name, counter.num, styledNode.element)
  if not liSeen and styledNode.computed{"display"} == DisplayListItem:
    ctx.incCounter(satListItem.toAtom(), 1, styledNode.element)
  for counter in styledNode.computed{"counter-set"}:
    ctx.setCounter(counter.name, counter.num, styledNode.element)

proc resetCounters(ctx: TreeContext; element: Element;
    countersLen, firstElementIdx, firstSetCounterIdx: int) =
  ctx.counters.setLen(countersLen)
  # Special case list-item, because the spec is broken.
  # In particular, we want list-item counters introduced by
  # counter-reset to be "narrow", i.e. delete them after the element
  # goes out of scope so that an OL nested in another OL does not shadow
  # the counter of the parent OL.
  # Note that this does not apply to list-items introduced by
  # counter-increment/counter-set, so we do not search those.
  for i in countdown(firstSetCounterIdx - 1, firstElementIdx):
    if ctx.counters[i].name == satListItem:
      ctx.counters.delete(i)
      break

proc pushStackItem(ctx: TreeContext; styledNode: StyledNode): StackItem =
  let index = styledNode.computed{"z-index"}
  let stack = StackItem(index: index.num)
  ctx.stackItem.children.add(stack)
  if not index.auto:
    ctx.stackItem = stack
  return stack

proc popStackItem(ctx: TreeContext; old: StackItem) =
  let stackItem = ctx.stackItem
  if stackItem != old:
    stackItem.children.sort(proc(x, y: StackItem): int = cmp(x.index, y.index))
  ctx.stackItem = old

proc addAbsolute(ctx: TreeContext; box: CSSBox) =
  let absolute = CSSAbsolute(box: BlockBox(box))
  if ctx.absoluteHead == nil:
    ctx.absoluteHead = absolute
  else:
    ctx.absoluteTail.next = absolute
  ctx.absoluteTail = absolute

proc addFixed(ctx: TreeContext; box: CSSBox) =
  let absolute = CSSAbsolute(box: BlockBox(box))
  if ctx.fixedHead == nil:
    ctx.fixedHead = absolute
  else:
    ctx.fixedTail.next = absolute
  ctx.fixedTail = absolute

proc buildOuterBox(ctx: TreeContext; cached: CSSBox; styledNode: StyledNode;
    forceZ, root: bool): CSSBox =
  let oldCountersLen = ctx.counters.len
  var firstSetCounterIdx: int
  ctx.applyCounters(styledNode, firstSetCounterIdx)
  let countersLen = ctx.counters.len
  var frame = ctx.initTreeFrame(styledNode.element, styledNode.computed)
  var stackItem: StackItem = nil
  let display = frame.computed{"display"}
  let position = frame.computed{"position"}
  let oldStackItem = ctx.stackItem
  let oldAbsoluteHead = ctx.absoluteHead
  let oldAbsoluteTail = ctx.absoluteTail
  if not root and
      (position != PositionStatic and display notin DisplayNeverHasStack or
      forceZ and not frame.computed{"z-index"}.auto):
    ctx.absoluteHead = nil
    ctx.absoluteTail = nil
    stackItem = ctx.pushStackItem(styledNode)
  frame.buildChildren(styledNode)
  let box = ctx.buildInnerBox(frame, cached, styledNode)
  if styledNode.t == stElement:
    box.element.box = box
  ctx.resetCounters(styledNode.element, countersLen, oldCountersLen,
    firstSetCounterIdx)
  box.positioned = stackItem != nil and position != PositionStatic
  if stackItem != nil:
    stackItem.box = box
    box.absolute = ctx.absoluteHead
    ctx.absoluteHead = oldAbsoluteHead
    ctx.absoluteTail = oldAbsoluteTail
    ctx.popStackItem(oldStackItem)
    case position
    of PositionAbsolute: ctx.addAbsolute(box)
    of PositionFixed: ctx.addFixed(box)
    else: discard
  return box

proc build(ctx: TreeContext; cached: CSSBox; styledNode: StyledNode;
    forceZ, root: bool): CSSBox =
  let cached = styledNode.takeCache(cached)
  case styledNode.t
  of stElement:
    return ctx.buildOuterBox(cached, styledNode, forceZ, root)
  of stText:
    if cached != nil:
      return cached
    return InlineTextBox(
      t: cbtText,
      computed: styledNode.computed,
      element: styledNode.element,
      text: styledNode.text,
      len: styledNode.text.len
    )
  of stBr:
    if cached != nil:
      return cached
    return InlineNewLineBox(
      t: cbtText,
      computed: styledNode.computed,
      element: styledNode.element
    )
  of stCounter:
    let counter = ctx.counter(styledNode.counterName)
    let addSuffix = styledNode.counterSuffix # only used for markers
    let text = styledNode.counterStyle.listMarker(counter, addSuffix,
      ctx.linkHintChars[])
    if cached != nil:
      let cached = InlineTextBox(cached)
      cached.keepLayout = cached.text.s == text.s
      cached.text = text
      return cached
    return InlineTextBox(
      t: cbtText,
      computed: styledNode.computed,
      element: styledNode.element,
      text: styledNode.counterStyle.listMarker(counter, addSuffix,
        ctx.linkHintChars[])
    )

# Root
proc buildTree*(element: Element; cached: CSSBox; markLinks: bool; nhints: int;
    linkHintChars: ref seq[uint32]):
    tuple[stack: StackItem, fixedHead: CSSAbsolute] =
  element.ensureStyle()
  let styledNode = StyledNode(
    t: stElement,
    element: element,
    computed: element.computed
  )
  let stack = StackItem()
  let ctx = TreeContext(
    markLinks: markLinks,
    stackItem: stack,
    linkHintChars: linkHintChars
  )
  ctx.resetCounter(satDashChaLinkCounter.toAtom(), 0, element)
  let hintHigh = max(linkHintChars[].high, 0)
  let hintOffset = if hintHigh > 0:
    min(int(int32.high), ((nhints + hintHigh - 1) div hintHigh) - 1)
  else:
    hintHigh
  ctx.resetCounter(satDashChaHintCounter.toAtom(), int32(hintOffset), element)
  let root = BlockBox(ctx.build(cached, styledNode, forceZ = false,
    root = true))
  stack.box = root
  root.absolute = ctx.absoluteHead
  ctx.popStackItem(nil)
  return (stack, ctx.fixedHead)

{.pop.} # raises: []
