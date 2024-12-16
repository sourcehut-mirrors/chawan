import std/algorithm
import std/math

import css/cssvalues
import css/lunit
import css/stylednode
import css/box
import types/bitmap
import types/winattrs
import utils/luwrap
import utils/strwidth
import utils/twtstr
import utils/widthconv

type
  # position: absolute is annoying in that its layout depends on its
  # containing box's size, which of course is rarely its parent box.
  # e.g. in
  # <div style="position: relative; display: inline-block">
  #   <div>
  #     <div style="position: absolute; width: 100%; color: red">
  #     blah
  #     </div>
  #   <div>
  # blah blah
  # </div>
  # the width of the absolute box is the same as "blah blah", but we
  # only know that after the outermost box has been layouted.
  #
  # So we must delay this layout until before the outermost box is
  # popped off the stack, and we do this by queuing up absolute boxes in
  # the initial pass.
  QueuedAbsolute = object
    offset: Offset
    child: BlockBox

  PositionedItem = ref object
    queue: seq[QueuedAbsolute]

  LayoutContext = ref object
    attrsp: ptr WindowAttributes
    cellSize: Size # size(w = attrsp.ppc, h = attrsp.ppl)
    positioned: seq[PositionedItem]
    myRootProperties: CSSValues
    # placeholder text data
    imgText: StyledNode
    audioText: StyledNode
    videoText: StyledNode

  # min-content: box width is longest word's width
  # max-content: box width is content width without wrapping
  # stretch: box width is n px wide
  # fit-content: also known as shrink-to-fit, box width is
  #   min(max-content, stretch(availableWidth))
  #   in other words, as wide as needed, but wrap if wider than allowed
  # (note: I write width here, but it can apply for any constraint)
  SizeConstraintType = enum
    scStretch, scFitContent, scMinContent, scMaxContent

  SizeConstraint = object
    t: SizeConstraintType
    u: LayoutUnit

  AvailableSpace = array[DimensionType, SizeConstraint]

  Bounds = object
    a: array[DimensionType, Span]
    minClamp: array[DimensionType, LayoutUnit]

  ResolvedSizes = object
    margin: RelativeRect
    padding: RelativeRect
    space: AvailableSpace
    bounds: Bounds

const DefaultSpan = Span(start: 0, send: LayoutUnit.high)

func minWidth(sizes: ResolvedSizes): LayoutUnit =
  return sizes.bounds.a[dtHorizontal].start

func maxWidth(sizes: ResolvedSizes): LayoutUnit =
  return sizes.bounds.a[dtHorizontal].send

func minHeight(sizes: ResolvedSizes): LayoutUnit =
  return sizes.bounds.a[dtVertical].start

func maxHeight(sizes: ResolvedSizes): LayoutUnit =
  return sizes.bounds.a[dtVertical].send

func sum(span: Span): LayoutUnit =
  return span.start + span.send

func opposite(dim: DimensionType): DimensionType =
  case dim
  of dtHorizontal: return dtVertical
  of dtVertical: return dtHorizontal

func availableSpace(w, h: SizeConstraint): AvailableSpace =
  return [dtHorizontal: w, dtVertical: h]

func w(space: AvailableSpace): SizeConstraint {.inline.} =
  return space[dtHorizontal]

func w(space: var AvailableSpace): var SizeConstraint {.inline.} =
  return space[dtHorizontal]

func `w=`(space: var AvailableSpace; w: SizeConstraint) {.inline.} =
  space[dtHorizontal] = w

func h(space: var AvailableSpace): var SizeConstraint {.inline.} =
  return space[dtVertical]

func h(space: AvailableSpace): SizeConstraint {.inline.} =
  return space[dtVertical]

func `h=`(space: var AvailableSpace; h: SizeConstraint) {.inline.} =
  space[dtVertical] = h

template attrs(state: LayoutContext): WindowAttributes =
  state.attrsp[]

func maxContent(): SizeConstraint =
  return SizeConstraint(t: scMaxContent)

func stretch(u: LayoutUnit): SizeConstraint =
  return SizeConstraint(t: scStretch, u: u)

func fitContent(u: LayoutUnit): SizeConstraint =
  return SizeConstraint(t: scFitContent, u: u)

func fitContent(sc: SizeConstraint): SizeConstraint =
  case sc.t
  of scMinContent, scMaxContent:
    return sc
  of scStretch, scFitContent:
    return SizeConstraint(t: scFitContent, u: sc.u)

func isDefinite(sc: SizeConstraint): bool =
  return sc.t in {scStretch, scFitContent}

# 2nd pass: layout
func canpx(l: CSSLength; sc: SizeConstraint): bool =
  return l.u != clAuto and (l.u != clPerc or sc.t == scStretch)

func px(l: CSSLength; p: LayoutUnit): LayoutUnit {.inline.} =
  if l.u != clPerc:
    return l.num.toLayoutUnit()
  return (p.toFloat64() * l.num / 100).toLayoutUnit()

func px(l: CSSLength; p: SizeConstraint): LayoutUnit {.inline.} =
  if l.u != clPerc:
    return l.num.toLayoutUnit()
  if p.t in {scStretch, scFitContent}:
    return (p.u.toFloat64() * l.num / 100).toLayoutUnit()
  return 0

func stretchOrMaxContent(l: CSSLength; sc: SizeConstraint): SizeConstraint =
  if l.canpx(sc):
    return stretch(l.px(sc))
  return maxContent()

func applySizeConstraint(u: LayoutUnit; availableSize: SizeConstraint):
    LayoutUnit =
  case availableSize.t
  of scStretch:
    return availableSize.u
  of scMinContent, scMaxContent:
    # must be calculated elsewhere...
    return u
  of scFitContent:
    return min(u, availableSize.u)

func outerSize(box: BlockBox; dim: DimensionType; sizes: ResolvedSizes):
    LayoutUnit =
  return sizes.margin[dim].sum() + box.state.size[dim]

func max(span: Span): LayoutUnit =
  return max(span.start, span.send)

# In CSS, "min" beats "max".
func minClamp(x: LayoutUnit; span: Span): LayoutUnit =
  return max(min(x, span.send), span.start)

#TODO implement sticky
const PositionStaticLike = {
  PositionStatic, PositionSticky
}

type
  BlockContext = object
    lctx: LayoutContext
    marginTodo: Strut
    # We use a linked list to set the correct BFC offset and relative offset
    # for every block with an unresolved y offset on margin resolution.
    # marginTarget is a pointer to the last unresolved ancestor.
    # ancestorsHead is a pointer to the last element of the ancestor list
    # (which may in fact be a pointer to the BPS of a previous sibling's
    # child).
    # parentBps is a pointer to the currently layouted parent block's BPS.
    marginTarget: BlockPositionState
    ancestorsHead: BlockPositionState
    parentBps: BlockPositionState
    exclusions: seq[Exclusion]
    unpositionedFloats: seq[UnpositionedFloat]
    maxFloatHeight: LayoutUnit
    clearOffset: LayoutUnit

  UnpositionedFloat = object
    parentBps: BlockPositionState
    space: AvailableSpace
    box: BlockBox
    marginOffset: Offset
    outerSize: Size
    # to propagate float overflow
    parentBox: BlockBox

  BlockPositionState = ref object
    next: BlockPositionState
    box: BlockBox
    offset: Offset # offset relative to the block formatting context
    resolved: bool # has the position been resolved yet?

  Exclusion = object
    offset: Offset
    size: Size
    t: CSSFloat

  Strut = object
    pos: LayoutUnit
    neg: LayoutUnit

type
  LineBoxState = object
    atomStates: seq[InlineAtomState]
    baseline: LayoutUnit
    hasExclusion: bool
    charwidth: int
    # Set at the end of layoutText. It helps determine the beginning of the
    # next inline fragment.
    widthAfterWhitespace: LayoutUnit
    # minimum height to fit all inline atoms
    minHeight: LayoutUnit
    paddingTodo: seq[tuple[fragment: InlineFragment; i: int]]
    atoms: seq[InlineAtom]
    size: Size
    availableWidth: LayoutUnit # actual place available after float exclusions
    offsety: LayoutUnit # offset of line in root fragment
    height: LayoutUnit # height used for painting; does not include padding

  InlineAtomState = object
    vertalign: CSSVerticalAlign
    baseline: LayoutUnit
    marginTop: LayoutUnit
    marginBottom: LayoutUnit
    fragment: InlineFragment

  InlineUnpositionedFloat = object
    parent: InlineFragment
    box: BlockBox
    outerSize: Size
    marginOffset: Offset
    space: AvailableSpace

  InlineContext = object
    state: BoxLayoutState
    computed: CSSValues
    bctx: ptr BlockContext
    bfcOffset: Offset
    lbstate: LineBoxState
    hasshy: bool
    lctx: LayoutContext
    space: AvailableSpace
    whitespacenum: int
    whitespaceIsLF: bool
    whitespaceFragment: InlineFragment
    word: InlineAtom
    wrappos: int # position of last wrapping opportunity, or -1
    textFragmentSeen: bool
    lastTextFragment: InlineFragment
    firstBaselineSet: bool
    unpositionedFloats: seq[InlineUnpositionedFloat]
    secondPass: bool
    padding: RelativeRect

  InlineState = object
    fragment: InlineFragment
    startOffsetTop: Offset
    # we do not want to collapse newlines over tag boundaries, so these are
    # in state
    lastrw: int # last rune width of the previous word
    firstrw: int # first rune width of the current word
    prevrw: int # last processed rune's width

func whitespacepre(computed: CSSValues): bool =
  computed{"white-space"} in {WhitespacePre, WhitespacePreLine,
    WhitespacePreWrap}

func nowrap(computed: CSSValues): bool =
  computed{"white-space"} in {WhitespaceNowrap, WhitespacePre}

func cellWidth(lctx: LayoutContext): int =
  lctx.attrs.ppc

func cellWidth(ictx: InlineContext): int =
  ictx.lctx.cellWidth

func cellHeight(ictx: InlineContext): int =
  ictx.lctx.attrs.ppl

func sum(rect: RelativeRect): Size =
  return [
    dtHorizontal: rect[dtHorizontal].sum(),
    dtVertical: rect[dtVertical].sum()
  ]

func startOffset(rect: RelativeRect): Offset =
  return offset(x = rect[dtHorizontal].start, y = rect[dtVertical].start)

# Whitespace between words
func computeShift(ictx: InlineContext; state: InlineState): LayoutUnit =
  if ictx.whitespacenum == 0:
    return 0
  if ictx.whitespaceIsLF and state.lastrw == 2 and state.firstrw == 2:
    # skip line feed between double-width characters
    return 0
  if not state.fragment.computed.whitespacepre:
    if ictx.lbstate.atoms.len == 0:
      return 0
    let atom = ictx.lbstate.atoms[^1]
    if atom.t == iatWord and atom.str[^1] == ' ':
      return 0
  return ictx.cellWidth * ictx.whitespacenum

proc newWord(ictx: var InlineContext) =
  ictx.word = InlineAtom(
    t: iatWord,
    size: size(w = 0, h = ictx.cellHeight)
  )
  ictx.wrappos = -1
  ictx.hasshy = false

func overflow(atom: InlineAtom; dim: DimensionType): Span =
  if atom.t == iatInlineBlock:
    let u = atom.offset[dim]
    return Span(
      start: u + atom.innerbox.state.overflow[dim].start,
      send: u + atom.innerbox.state.overflow[dim].send
    )
  return Span(
    start: atom.offset[dim],
    send: atom.offset[dim] + atom.size[dim]
  )

proc expand(a: var Span; b: Span) =
  a.start = min(a.start, b.start)
  a.send = max(a.send, b.send)

#TODO start & justify would be nice to have
const TextAlignNone = {
  TextAlignStart, TextAlignLeft, TextAlignChaLeft, TextAlignJustify
}

# Resize the line's height based on atoms' height and baseline.
# The line height should be at least as high as the highest baseline used by
# an atom plus that atom's height.
func resizeLine(lbstate: LineBoxState; lctx: LayoutContext): LayoutUnit =
  let baseline = lbstate.baseline
  var h = lbstate.size.h
  for i, atom in lbstate.atoms:
    let iastate = lbstate.atomStates[i]
    # In all cases, the line's height must at least equal the atom's height.
    # (Where the atom is actually placed is irrelevant here.)
    h = max(h, atom.size.h)
    case iastate.vertalign.keyword
    of VerticalAlignBaseline:
      # Line height must be at least as high as
      # (atom baseline) + (atom height) + (extra height) - (line baseline).
      h = max(atom.offset.y + atom.size.h - baseline, h)
    of VerticalAlignMiddle:
      # Line height must be at least
      # (line baseline) + (atom height / 2).
      h = max(baseline + atom.size.h div 2, h)
    of VerticalAlignTop, VerticalAlignBottom:
      # Line height must be at least atom height (already ensured above.)
      discard
    else:
      # See baseline (with len = 0).
      h = max(baseline - iastate.baseline + atom.size.h, h)
  return h

# returns marginTop
proc positionAtoms(lbstate: LineBoxState; lctx: LayoutContext): LayoutUnit =
  let baseline = lbstate.baseline
  var marginTop: LayoutUnit = 0
  for i, atom in lbstate.atoms:
    let iastate = lbstate.atomStates[i]
    case iastate.vertalign.keyword
    of VerticalAlignBaseline:
      # Atom is placed at (line baseline) - (atom baseline) - len
      atom.offset.y = baseline - atom.offset.y
    of VerticalAlignMiddle:
      # Atom is placed at (line baseline) - ((atom height) / 2)
      atom.offset.y = baseline - atom.size.h div 2
    of VerticalAlignTop:
      # Atom is placed at the top of the line.
      atom.offset.y = 0
    of VerticalAlignBottom:
      # Atom is placed at the bottom of the line.
      atom.offset.y = lbstate.size.h - atom.size.h
    else:
      # See baseline (with len = 0).
      atom.offset.y = baseline - iastate.baseline
    # Find the best top margin of all atoms.
    # We are looking for the lowest top edge of the line, so we have to do this
    # after we know where the atoms will be placed.
    # Note: we used to calculate the bottom edge based on margins too, but this
    # generated pointless empty lines so I removed it.
    marginTop = max(iastate.marginTop - atom.offset.y, marginTop)
  return marginTop

func getLineWidth(ictx: InlineContext): LayoutUnit =
  return case ictx.space.w.t
  of scMinContent, scMaxContent: ictx.state.size.w
  of scFitContent: ictx.space.w.u
  of scStretch: max(ictx.state.size.w, ictx.space.w.u)

func getLineXShift(ictx: InlineContext; width: LayoutUnit): LayoutUnit =
  return case ictx.computed{"text-align"}
  of TextAlignNone: LayoutUnit(0)
  of TextAlignEnd, TextAlignRight, TextAlignChaRight:
    let width = min(width, ictx.lbstate.availableWidth)
    max(width, ictx.lbstate.size.w) - ictx.lbstate.size.w
  of TextAlignCenter, TextAlignChaCenter:
    let width = min(width, ictx.lbstate.availableWidth)
    max((max(width, ictx.lbstate.size.w)) div 2 - ictx.lbstate.size.w div 2, 0)

proc shiftAtoms(ictx: var InlineContext; marginTop: LayoutUnit) =
  let offsety = ictx.lbstate.offsety
  let shiftTop = marginTop
  let cellHeight = ictx.cellHeight
  let width = ictx.getLineWidth()
  let xshift = ictx.getLineXShift(width)
  var totalWidth: LayoutUnit = 0
  var currentAreaOffsetX: LayoutUnit = 0
  var currentFragment: InlineFragment = nil
  let offsetyShifted = shiftTop + offsety
  var areaY: LayoutUnit = 0
  for i, atom in ictx.lbstate.atoms:
    atom.offset.y = atom.offset.y + offsetyShifted
    areaY = max(atom.offset.y, areaY)
    #TODO why not offsetyShifted here?
    let minHeight = atom.offset.y - offsety + atom.size.h
    ictx.lbstate.minHeight = max(ictx.lbstate.minHeight, minHeight)
    # Y is always final, so it is safe to calculate Y overflow
    ictx.state.overflow[dtVertical].expand(atom.overflow(dtVertical))
    # now position on the inline axis
    atom.offset.x += xshift
    totalWidth += atom.size.w
    ictx.state.overflow[dtHorizontal].expand(atom.overflow(dtHorizontal))
    let fragment = ictx.lbstate.atomStates[i].fragment
    if currentFragment != fragment:
      if currentFragment != nil:
        # flush area
        let lastAtom = ictx.lbstate.atoms[i - 1]
        let w = lastAtom.offset.x + lastAtom.size.w - currentAreaOffsetX
        if w != 0:
          currentFragment.state.areas.add(Area(
            offset: offset(x = currentAreaOffsetX, y = areaY),
            # it seems cellHeight is what other browsers use here too
            size: size(w = w, h = cellHeight)
          ))
      currentFragment = fragment
      # init new fragment
      currentAreaOffsetX = if fragment.state.areas.len == 0:
        fragment.state.atoms[0].offset.x
      else:
        ictx.lbstate.atoms[0].offset.x
  if currentFragment != nil:
    # flush area
    let atom = ictx.lbstate.atoms[^1]
    areaY = max(atom.offset.y, areaY)
    # it seems cellHeight is what other browsers use here too?
    let w = atom.offset.x + atom.size.w - currentAreaOffsetX
    let offset = offset(x = currentAreaOffsetX, y = areaY)
    template lastArea: untyped = currentFragment.state.areas[^1]
    if currentFragment.state.areas.len > 0 and
        lastArea.offset.x == offset.x and lastArea.size.w == w and
        lastArea.offset.y + lastArea.size.h == offset.y:
      # merge contiguous areas
      lastArea.size.h += cellHeight
    else:
      currentFragment.state.areas.add(Area(
        offset: offset,
        size: size(w = w, h = cellHeight)
      ))
  for (fragment, i) in ictx.lbstate.paddingTodo:
    fragment.state.areas[i].offset.x += xshift
    fragment.state.areas[i].offset.y = areaY
  if ictx.space.w.t == scFitContent:
    ictx.state.size.w = max(totalWidth, ictx.state.size.w)

# Align atoms (inline boxes, text, etc.) on both axes.
proc alignLine(ictx: var InlineContext) =
  # Start with cell height as the baseline and line height.
  let ch = ictx.cellHeight.toLayoutUnit()
  ictx.lbstate.size.h = ch
  # Baseline is what we computed in addAtom, or cell height if that's greater.
  ictx.lbstate.baseline = max(ictx.lbstate.baseline, ch)
  # Resize according to the baseline and atom sizes.
  ictx.lbstate.size.h = ictx.lbstate.resizeLine(ictx.lctx)
  # Now we can calculate the actual position of atoms inside the line.
  let marginTop = ictx.lbstate.positionAtoms(ictx.lctx)
  # Finally, offset all atoms' y position by the largest top margin and the
  # line box's top padding.
  ictx.shiftAtoms(marginTop)
  # Ensure that the line is exactly as high as its highest atom demands,
  # rounded up to the next line.
  ictx.lbstate.size.h = ictx.lbstate.minHeight.ceilTo(ictx.cellHeight)
  # Now, if we got a height that is lower than cell height, then set it
  # back to the cell height. (This is to avoid the situation where we
  # would swallow hard line breaks with <br>.)
  if ictx.lbstate.size.h < ch:
    ictx.lbstate.size.h = ch
  # Set the line height to size.h.
  ictx.lbstate.height = ictx.lbstate.size.h

proc putAtom(state: var LineBoxState; atom: InlineAtom;
    iastate: InlineAtomState; fragment: InlineFragment) =
  state.atomStates.add(iastate)
  state.atomStates[^1].fragment = fragment
  state.atoms.add(atom)
  fragment.state.atoms.add(atom)

proc addSpacing(ictx: var InlineContext; width: LayoutUnit; state: InlineState;
    hang = false) =
  let fragment = ictx.whitespaceFragment
  if fragment.state.atoms.len == 0 or ictx.lbstate.atoms.len == 0 or
      (let oatom = fragment.state.atoms[^1];
        oatom.t != iatWord or oatom != ictx.lbstate.atoms[^1]):
    let atom = InlineAtom(
      t: iatWord,
      size: size(w = 0, h = ictx.cellHeight),
      offset: offset(x = ictx.lbstate.size.w, y = ictx.cellHeight)
    )
    let iastate = InlineAtomState(baseline: atom.size.h)
    ictx.lbstate.putAtom(atom, iastate, fragment)
  let atom = fragment.state.atoms[^1]
  let n = (width div ictx.cellWidth).toInt #TODO
  for i in 0 ..< n:
    atom.str &= ' '
  atom.size.w += width
  if not hang:
    # In some cases, whitespace may "hang" at the end of the line. This means
    # it is written, but is not actually counted in the box's width.
    ictx.lbstate.size.w += width

proc flushWhitespace(ictx: var InlineContext; state: InlineState;
    hang = false) =
  let shift = ictx.computeShift(state)
  ictx.lbstate.charwidth += ictx.whitespacenum
  ictx.whitespacenum = 0
  if shift > 0:
    ictx.addSpacing(shift, state, hang)

proc clearFloats(offsety: var LayoutUnit; bctx: var BlockContext;
    bfcOffsety: LayoutUnit; clear: CSSClear) =
  var y = bfcOffsety + offsety
  case clear
  of ClearLeft, ClearInlineStart:
    for ex in bctx.exclusions:
      if ex.t == FloatLeft:
        y = max(ex.offset.y + ex.size.h, y)
  of ClearRight, ClearInlineEnd:
    for ex in bctx.exclusions:
      if ex.t == FloatRight:
        y = max(ex.offset.y + ex.size.h, y)
  of ClearBoth:
    for ex in bctx.exclusions:
      y = max(ex.offset.y + ex.size.h, y)
  of ClearNone: assert false
  bctx.clearOffset = y
  offsety = y - bfcOffsety

# Prepare the next line's initial width and available width.
# (If space on the left is excluded by floats, set the initial width to
# the end of that space. If space on the right is excluded, set the
# available width to that space.)
proc initLine(ictx: var InlineContext) =
  # we want to start from padding-left, but normally exclude padding
  # from space. so we must offset available width with padding-left too
  ictx.lbstate.availableWidth = ictx.space.w.u + ictx.padding.left
  ictx.lbstate.size.w = ictx.padding.left
  #TODO what if maxContent/minContent?
  if ictx.bctx.exclusions.len > 0:
    let bfcOffset = ictx.bfcOffset
    let y = ictx.lbstate.offsety + bfcOffset.y
    var left = bfcOffset.x + ictx.lbstate.size.w
    var right = bfcOffset.x + ictx.lbstate.availableWidth
    for ex in ictx.bctx.exclusions:
      if ex.offset.y <= y and y < ex.offset.y + ex.size.h:
        ictx.lbstate.hasExclusion = true
        if ex.t == FloatLeft:
          left = ex.offset.x + ex.size.w
        else:
          right = ex.offset.x
    ictx.lbstate.size.w = max(left - bfcOffset.x, ictx.lbstate.size.w)
    ictx.lbstate.availableWidth = min(right - bfcOffset.x,
      ictx.lbstate.availableWidth)

proc finishLine(ictx: var InlineContext; state: var InlineState; wrap: bool;
    force = false; clear = ClearNone) =
  if ictx.lbstate.atoms.len != 0 or force:
    let whitespace = state.fragment.computed{"white-space"}
    if whitespace == WhitespacePre:
      ictx.flushWhitespace(state)
      ictx.state.xminwidth = max(ictx.state.xminwidth, ictx.lbstate.size.w)
    elif whitespace == WhitespacePreWrap:
      ictx.flushWhitespace(state, hang = true)
    else:
      ictx.whitespacenum = 0
    # align atoms + calculate width for fit-content + place
    ictx.alignLine()
    # add line to ictx
    let y = ictx.lbstate.offsety
    if clear != ClearNone:
      ictx.lbstate.size.h.clearFloats(ictx.bctx[], ictx.bfcOffset.y + y, clear)
    # * set first baseline if this is the first line box
    # * always set last baseline (so the baseline of the last line box remains)
    ictx.state.baseline = y + ictx.lbstate.baseline
    if not ictx.firstBaselineSet:
      ictx.state.firstBaseline = ictx.lbstate.baseline
      ictx.firstBaselineSet = true
    ictx.state.size.h += ictx.lbstate.size.h
    let lineWidth = if wrap:
      ictx.lbstate.availableWidth
    else:
      ictx.lbstate.size.w
    ictx.state.size.w = max(ictx.state.size.w, lineWidth)
    ictx.lbstate = LineBoxState(offsety: y + ictx.lbstate.size.h)
    ictx.initLine()

func shouldWrap(ictx: InlineContext; w: LayoutUnit;
    pcomputed: CSSValues): bool =
  if pcomputed != nil and pcomputed.nowrap:
    return false
  if ictx.space.w.t == scMaxContent:
    return false # no wrap with max-content
  if ictx.space.w.t == scMinContent:
    return true # always wrap with min-content
  return ictx.lbstate.size.w + w > ictx.lbstate.availableWidth

func shouldWrap2(ictx: InlineContext; w: LayoutUnit): bool =
  if not ictx.lbstate.hasExclusion:
    return false
  return ictx.lbstate.size.w + w > ictx.lbstate.availableWidth

func getBaseline(ictx: InlineContext; iastate: InlineAtomState;
    atom: InlineAtom): LayoutUnit =
  return case iastate.vertalign.keyword
  of VerticalAlignBaseline:
    let length = CSSLength(u: iastate.vertalign.u, num: iastate.vertalign.num)
    let len = length.px(ictx.cellHeight)
    iastate.baseline + len
  of VerticalAlignTop, VerticalAlignBottom:
    atom.size.h
  of VerticalAlignMiddle:
    atom.size.h div 2
  else:
    iastate.baseline

# Add an inline atom atom, with state iastate.
# Returns true on newline.
proc addAtom(ictx: var InlineContext; state: var InlineState;
    iastate: InlineAtomState; atom: InlineAtom): bool =
  result = false
  var shift = ictx.computeShift(state)
  ictx.lbstate.charwidth += ictx.whitespacenum
  ictx.whitespacenum = 0
  # Line wrapping
  if ictx.shouldWrap(atom.size.w + shift, state.fragment.computed):
    ictx.finishLine(state, wrap = true)
    result = true
    # Recompute on newline
    shift = ictx.computeShift(state)
    # For floats: flush lines until we can place the atom.
    #TODO this is inefficient
    while ictx.shouldWrap2(atom.size.w + shift):
      ictx.finishLine(state, wrap = false, force = true)
      # Recompute on newline
      shift = ictx.computeShift(state)
  if atom.size.w > 0 and atom.size.h > 0 or atom.t == iatInlineBlock:
    if shift > 0:
      ictx.addSpacing(shift, state)
    case atom.t
    of iatWord:
      let wordBreak = state.fragment.computed{"word-break"}
      if ictx.wrappos != -1:
        # set xminwidth to the first wrapping opportunity
        ictx.state.xminwidth = max(ictx.state.xminwidth, ictx.wrappos)
      elif state.prevrw >= 2 and wordBreak != WordBreakKeepAll or
          wordBreak == WordBreakBreakAll:
        # last char was double width; we can wrap anywhere.
        # (I think this isn't quite right when double width + half width
        # are mixed, but whatever...)
        ictx.state.xminwidth = max(ictx.state.xminwidth, state.prevrw)
      else:
        ictx.state.xminwidth = max(ictx.state.xminwidth, atom.size.w)
      if ictx.lbstate.atoms.len > 0 and state.fragment.state.atoms.len > 0:
        let oatom = ictx.lbstate.atoms[^1]
        if oatom.t == iatWord and oatom == state.fragment.state.atoms[^1]:
          oatom.str &= atom.str
          oatom.size.w += atom.size.w
          ictx.lbstate.size.w += atom.size.w
          return
    of iatInlineBlock:
      ictx.state.xminwidth = max(ictx.state.xminwidth,
        atom.innerbox.state.xminwidth)
      ictx.lbstate.charwidth = 0
    of iatImage:
      # We calculate xminwidth in addInlineImage instead.
      ictx.lbstate.charwidth = 0
    ictx.lbstate.putAtom(atom, iastate, state.fragment)
    atom.offset.x += ictx.lbstate.size.w
    ictx.lbstate.size.w += atom.size.w
    # store for later use in resizeLine/shiftAtoms
    let baseline = ictx.getBaseline(iastate, atom)
    atom.offset.y = baseline
    ictx.lbstate.baseline = max(ictx.lbstate.baseline, baseline)

proc addWord(ictx: var InlineContext; state: var InlineState): bool =
  result = false
  if ictx.word.str != "":
    ictx.word.str.mnormalize() #TODO this may break on EOL.
    let iastate = InlineAtomState(
      vertalign: state.fragment.computed{"vertical-align"},
      baseline: ictx.word.size.h
    )
    result = ictx.addAtom(state, iastate, ictx.word)
    ictx.newWord()

proc addWordEOL(ictx: var InlineContext; state: var InlineState): bool =
  result = false
  if ictx.word.str != "":
    if ictx.wrappos != -1:
      let leftstr = ictx.word.str.substr(ictx.wrappos)
      ictx.word.str.setLen(ictx.wrappos)
      if ictx.hasshy:
        const shy = "\u00AD" # soft hyphen
        ictx.word.str &= shy
        ictx.hasshy = false
      result = ictx.addWord(state)
      ictx.word.str = leftstr
      ictx.word.size.w = leftstr.width() * ictx.cellWidth
    else:
      result = ictx.addWord(state)

proc checkWrap(ictx: var InlineContext; state: var InlineState; u: uint32;
    uw: int) =
  if state.fragment.computed.nowrap:
    return
  let shift = ictx.computeShift(state)
  state.prevrw = uw
  if ictx.word.str.len == 0:
    state.firstrw = uw
  if uw >= 2:
    # remove wrap opportunity, so we wrap properly on the last CJK char (instead
    # of any dash inside CJK sentences)
    ictx.wrappos = -1
  case state.fragment.computed{"word-break"}
  of WordBreakNormal:
    if uw == 2 or ictx.wrappos != -1: # break on cjk and wrap opportunities
      let plusWidth = ictx.word.size.w + shift + uw * ictx.cellWidth
      if ictx.shouldWrap(plusWidth, nil):
        if not ictx.addWordEOL(state): # no line wrapping occured in addAtom
          ictx.finishLine(state, wrap = true)
          ictx.whitespacenum = 0
  of WordBreakBreakAll:
    let plusWidth = ictx.word.size.w + shift + uw * ictx.cellWidth
    if ictx.shouldWrap(plusWidth, nil):
      if not ictx.addWordEOL(state): # no line wrapping occured in addAtom
        ictx.finishLine(state, wrap = true)
        ictx.whitespacenum = 0
  of WordBreakKeepAll:
    let plusWidth = ictx.word.size.w + shift + uw * ictx.cellWidth
    if ictx.shouldWrap(plusWidth, nil):
      ictx.finishLine(state, wrap = true)
      ictx.whitespacenum = 0

proc processWhitespace(ictx: var InlineContext; state: var InlineState;
    c: char) =
  discard ictx.addWord(state)
  case state.fragment.computed{"white-space"}
  of WhitespaceNormal, WhitespaceNowrap:
    if ictx.whitespacenum < 1:
      ictx.whitespacenum = 1
      ictx.whitespaceFragment = state.fragment
      ictx.whitespaceIsLF = c == '\n'
    if c != '\n':
      ictx.whitespaceIsLF = false
  of WhitespacePreLine:
    if c == '\n':
      ictx.finishLine(state, wrap = false, force = true)
    elif ictx.whitespacenum < 1:
      ictx.whitespaceIsLF = false
      ictx.whitespacenum = 1
      ictx.whitespaceFragment = state.fragment
  of WhitespacePre, WhitespacePreWrap:
    ictx.whitespaceIsLF = false
    if c == '\n':
      ictx.finishLine(state, wrap = false, force = true)
    elif c == '\t':
      let realWidth = ictx.lbstate.charwidth + ictx.whitespacenum
      # We must flush first, because addWord would otherwise try to wrap the
      # line. (I think.)
      ictx.flushWhitespace(state)
      let w = ((realWidth + 8) and not 7) - realWidth
      ictx.word.str.addUTF8(tabPUAPoint(w))
      ictx.word.size.w += w * ictx.cellWidth
      ictx.lbstate.charwidth += w
      # Ditto here - we don't want the tab stop to get merged into the next
      # word's atom.
      discard ictx.addWord(state)
    else:
      inc ictx.whitespacenum
      ictx.whitespaceFragment = state.fragment
  # set the "last word's last rune width" to the previous rune width
  state.lastrw = state.prevrw

func initInlineContext(bctx: var BlockContext; space: AvailableSpace;
    bfcOffset: Offset; padding: RelativeRect; computed: CSSValues):
    InlineContext =
  return InlineContext(
    bctx: addr bctx,
    lctx: bctx.lctx,
    bfcOffset: bfcOffset,
    space: space,
    computed: computed,
    padding: padding,
    lbstate: LineBoxState(offsety: padding.top)
  )

proc layoutTextLoop(ictx: var InlineContext; state: var InlineState;
    str: string) =
  var i = 0
  while i < str.len:
    let c = str[i]
    if c in Ascii:
      if c in AsciiWhitespace:
        ictx.processWhitespace(state, c)
      else:
        let w = uint32(c).width()
        ictx.checkWrap(state, uint32(c), w)
        ictx.word.str &= c
        ictx.word.size.w += w * ictx.cellWidth
        ictx.lbstate.charwidth += w
        if c == '-': # ascii dash
          ictx.wrappos = ictx.word.str.len
          ictx.hasshy = false
      inc i
    else:
      let pi = i
      let u = str.nextUTF8(i)
      let w = u.width()
      ictx.checkWrap(state, u, w)
      if u == 0xAD: # soft hyphen
        ictx.wrappos = ictx.word.str.len
        ictx.hasshy = true
      elif u in TabPUARange: # filter out chars placed in our PUA range
        ictx.word.str &= "\uFFFD"
        ictx.word.size.w += 0xFFFD.width() * ictx.cellWidth
      else:
        for j in pi ..< i:
          ictx.word.str &= str[j]
        ictx.word.size.w += w * ictx.cellWidth
        ictx.lbstate.charwidth += w
  discard ictx.addWord(state)
  let shift = ictx.computeShift(state)
  ictx.lbstate.widthAfterWhitespace = ictx.lbstate.size.w + shift

proc layoutText(ictx: var InlineContext; state: var InlineState; s: string) =
  ictx.flushWhitespace(state)
  ictx.newWord()
  let transform = state.fragment.computed{"text-transform"}
  if transform == TextTransformNone:
    ictx.layoutTextLoop(state, s)
  else:
    let s = case transform
    of TextTransformCapitalize: s.capitalizeLU()
    of TextTransformUppercase: s.toUpperLU()
    of TextTransformLowercase: s.toLowerLU()
    of TextTransformFullWidth: s.fullwidth()
    of TextTransformFullSizeKana: s.fullsize()
    of TextTransformChaHalfWidth: s.halfwidth()
    else: ""
    ictx.layoutTextLoop(state, s)

func spx(l: CSSLength; p: SizeConstraint; computed: CSSValues;
    padding: LayoutUnit): LayoutUnit =
  let u = l.px(p)
  if computed{"box-sizing"} == BoxSizingBorderBox:
    return max(u - padding, 0)
  return max(u, 0)

proc resolveContentWidth(sizes: var ResolvedSizes; widthpx: LayoutUnit;
    parentWidth: SizeConstraint; computed: CSSValues;
    isauto = false) =
  if not sizes.space.w.isDefinite() or parentWidth.t != scStretch:
    # width is indefinite, so no conflicts can be resolved here.
    return
  let total = widthpx + sizes.margin[dtHorizontal].sum() +
    sizes.padding[dtHorizontal].sum()
  let underflow = parentWidth.u - total
  if isauto:
    if underflow >= 0:
      sizes.space.w = SizeConstraint(t: sizes.space.w.t, u: underflow)
    else:
      sizes.margin[dtHorizontal].send += underflow
  elif underflow > 0:
    if computed{"margin-left"}.u != clAuto and
        computed{"margin-right"}.u != clAuto:
      sizes.margin[dtHorizontal].send += underflow
    elif computed{"margin-left"}.u != clAuto and
        computed{"margin-right"}.u == clAuto:
      sizes.margin[dtHorizontal].send = underflow
    elif computed{"margin-left"}.u == clAuto and
        computed{"margin-right"}.u != clAuto:
      sizes.margin[dtHorizontal].start = underflow
    else:
      sizes.margin[dtHorizontal].start = underflow div 2
      sizes.margin[dtHorizontal].send = underflow div 2

proc resolveMargins(lctx: LayoutContext; availableWidth: SizeConstraint;
    computed: CSSValues): RelativeRect =
  # Note: we use availableWidth for percentage resolution intentionally.
  return [
    dtHorizontal: Span(
      start: computed{"margin-left"}.px(availableWidth),
      send: computed{"margin-right"}.px(availableWidth),
    ),
    dtVertical: Span(
      start: computed{"margin-top"}.px(availableWidth),
      send: computed{"margin-bottom"}.px(availableWidth),
    )
  ]

proc resolvePadding(lctx: LayoutContext; availableWidth: SizeConstraint;
    computed: CSSValues): RelativeRect =
  # Note: we use availableWidth for percentage resolution intentionally.
  return [
    dtHorizontal: Span(
      start: computed{"padding-left"}.px(availableWidth),
      send: computed{"padding-right"}.px(availableWidth)
    ),
    dtVertical: Span(
      start: computed{"padding-top"}.px(availableWidth),
      send: computed{"padding-bottom"}.px(availableWidth),
    )
  ]

func resolvePositioned(lctx: LayoutContext; size: Size;
    computed: CSSValues): RelativeRect =
  # As per standard, vertical percentages refer to the *height*, not the width
  # (unlike with margin/padding)
  return [
    dtHorizontal: Span(
      start: computed{"left"}.px(size.w),
      send: computed{"right"}.px(size.w)
    ),
    dtVertical: Span(
      start: computed{"top"}.px(size.h),
      send: computed{"bottom"}.px(size.h),
    )
  ]

const DefaultBounds = Bounds(
  a: [DefaultSpan, DefaultSpan],
  minClamp: [LayoutUnit.high, LayoutUnit.high]
)

func resolveBounds(lctx: LayoutContext; space: AvailableSpace; padding: Size;
    computed: CSSValues): Bounds =
  var res = DefaultBounds
  block:
    let sc = space.w
    let padding = padding[dtHorizontal]
    if computed{"min-width"}.canpx(sc):
      let px = computed{"min-width"}.spx(sc, computed, padding)
      res.a[dtHorizontal].start = px
      res.minClamp[dtHorizontal] = px
    if computed{"max-width"}.canpx(sc):
      let px = computed{"max-width"}.spx(sc, computed, padding)
      res.a[dtHorizontal].send = px
  block:
    let sc = space.h
    let padding = padding[dtHorizontal]
    if computed{"min-height"}.canpx(sc):
      let px = computed{"min-height"}.spx(sc, computed, padding)
      res.a[dtVertical].start = px
      res.minClamp[dtVertical] = px
    if computed{"max-height"}.canpx(sc):
      let px = computed{"max-height"}.spx(sc, computed, padding)
      res.a[dtVertical].send = px
  return res

const CvalSizeMap = [dtHorizontal: cptWidth, dtVertical: cptHeight]

proc resolveAbsoluteWidth(sizes: var ResolvedSizes; size: Size;
    positioned: RelativeRect; computed: CSSValues;
    lctx: LayoutContext) =
  if computed{"width"}.u == clAuto:
    let u = max(size.w - positioned[dtHorizontal].sum(), 0)
    if computed{"left"}.u != clAuto and computed{"right"}.u != clAuto:
      # Both left and right are known, so we can calculate the width.
      sizes.space.w = stretch(u)
    else:
      # Return shrink to fit and solve for left/right.
      sizes.space.w = fitContent(u)
  else:
    let padding = sizes.padding[dtHorizontal].sum()
    let sizepx = computed{"width"}.spx(stretch(size.w), computed, padding)
    sizes.space.w = stretch(sizepx)

proc resolveAbsoluteHeight(sizes: var ResolvedSizes; size: Size;
    positioned: RelativeRect; computed: CSSValues;
    lctx: LayoutContext) =
  if computed{"height"}.u == clAuto:
    let u = max(size.w - positioned[dtVertical].sum(), 0)
    if computed{"top"}.u != clAuto and computed{"bottom"}.u != clAuto:
      # Both top and bottom are known, so we can calculate the height.
      sizes.space.h = stretch(u)
    else:
      # The height is based on the content.
      sizes.space.h = maxContent()
  else:
    let padding = sizes.padding[dtVertical].sum()
    let sizepx = computed{"height"}.spx(stretch(size.h), computed,
      padding)
    sizes.space.h = stretch(sizepx)

# Calculate and resolve available width & height for absolutely positioned
# boxes.
proc resolveAbsoluteSizes(lctx: LayoutContext; size: Size;
    positioned: var RelativeRect; computed: CSSValues): ResolvedSizes =
  positioned = lctx.resolvePositioned(size, computed)
  var sizes = ResolvedSizes(
    margin: lctx.resolveMargins(stretch(size.w), computed),
    padding: lctx.resolvePadding(stretch(size.w), computed),
    bounds: DefaultBounds
  )
  sizes.resolveAbsoluteWidth(size, positioned, computed, lctx)
  sizes.resolveAbsoluteHeight(size, positioned, computed, lctx)
  return sizes

# Calculate and resolve available width & height for floating boxes.
proc resolveFloatSizes(lctx: LayoutContext; space: AvailableSpace;
    computed: CSSValues): ResolvedSizes =
  let padding = lctx.resolvePadding(space.w, computed)
  let paddingSum = padding.sum()
  var sizes = ResolvedSizes(
    margin: lctx.resolveMargins(space.w, computed),
    padding: padding,
    space: space,
    bounds: lctx.resolveBounds(space, paddingSum, computed)
  )
  sizes.space.h = maxContent()
  for dim in DimensionType:
    let length = computed.objs[CvalSizeMap[dim]].length
    if length.canpx(space[dim]):
      let u = length.spx(space[dim], computed, paddingSum[dim])
      sizes.space[dim] = stretch(minClamp(u, sizes.bounds.a[dim]))
    elif sizes.space[dim].isDefinite():
      let u = sizes.space[dim].u - sizes.margin[dim].sum() - paddingSum[dim]
      sizes.space[dim] = fitContent(minClamp(u, sizes.bounds.a[dim]))
  return sizes

proc resolveFlexItemSizes(lctx: LayoutContext; space: AvailableSpace;
    dim: DimensionType; computed: CSSValues): ResolvedSizes =
  let padding = lctx.resolvePadding(space.w, computed)
  let paddingSum = padding.sum()
  var sizes = ResolvedSizes(
    margin: lctx.resolveMargins(space.w, computed),
    padding: padding,
    space: space,
    bounds: lctx.resolveBounds(space, paddingSum, computed)
  )
  if dim != dtHorizontal:
    sizes.space.h = maxContent()
  let length = computed.objs[CvalSizeMap[dim]].length
  if length.canpx(space[dim]):
    let u = length.spx(space[dim], computed, paddingSum[dim])
    sizes.space[dim] = SizeConstraint(
      t: sizes.space[dim].t,
      u: minClamp(u, sizes.bounds.a[dim])
    )
    sizes.bounds.minClamp[dim] = min(sizes.space[dim].u,
      sizes.bounds.minClamp[dim])
  elif sizes.bounds.a[dim].send < LayoutUnit.high:
    sizes.space[dim] = fitContent(sizes.bounds.a[dim].max())
  else:
    # Ensure that space is indefinite in the first pass if no width has
    # been specified.
    sizes.space[dim] = maxContent()
  let odim = dim.opposite()
  let olength = computed.objs[CvalSizeMap[odim]].length
  if olength.canpx(space[odim]):
    let u = olength.spx(space[odim], computed, paddingSum[odim])
    sizes.space[odim] = stretch(minClamp(u, sizes.bounds.a[odim]))
    sizes.bounds.minClamp[odim] = min(sizes.space[odim].u,
      sizes.bounds.minClamp[odim])
  elif sizes.space[odim].isDefinite():
    let u = sizes.space[odim].u - sizes.margin[odim].sum() - paddingSum[odim]
    sizes.space[odim] = SizeConstraint(
      t: sizes.space[odim].t,
      u: minClamp(u, sizes.bounds.a[odim])
    )
  elif sizes.bounds.a[odim].send < LayoutUnit.high:
    sizes.space[odim] = fitContent(sizes.bounds.a[odim].max())
  return sizes

proc resolveBlockWidth(sizes: var ResolvedSizes; parentWidth: SizeConstraint;
    inlinePadding: LayoutUnit; computed: CSSValues;
    lctx: LayoutContext) =
  let width = computed{"width"}
  var widthpx: LayoutUnit = 0
  if width.canpx(parentWidth):
    widthpx = width.spx(parentWidth, computed, inlinePadding)
    sizes.space.w = stretch(widthpx)
    sizes.bounds.minClamp[dtHorizontal] = widthpx
  sizes.resolveContentWidth(widthpx, parentWidth, computed, width.u == clAuto)
  if sizes.space.w.isDefinite() and sizes.maxWidth < sizes.space.w.u or
      sizes.maxWidth < LayoutUnit.high and sizes.space.w.t == scMaxContent:
    if sizes.space.w.t == scStretch:
      # available width would stretch over max-width
      sizes.space.w = stretch(sizes.maxWidth)
    else: # scFitContent
      # available width could be higher than max-width (but not necessarily)
      sizes.space.w = fitContent(sizes.maxWidth)
    sizes.resolveContentWidth(sizes.maxWidth, parentWidth, computed)
  if sizes.space.w.isDefinite() and sizes.minWidth > sizes.space.w.u or
      sizes.minWidth > 0 and sizes.space.w.t == scMinContent:
    # two cases:
    # * available width is stretched under min-width. in this case,
    #   stretch to min-width instead.
    # * available width is fit under min-width. in this case, stretch to
    #   min-width as well (as we must satisfy min-width >= width).
    sizes.space.w = stretch(sizes.minWidth)
    sizes.resolveContentWidth(sizes.minWidth, parentWidth, computed)

proc resolveBlockHeight(sizes: var ResolvedSizes; parentHeight: SizeConstraint;
    blockPadding: LayoutUnit; computed: CSSValues;
    lctx: LayoutContext) =
  let height = computed{"height"}
  if height.canpx(parentHeight):
    let heightpx = height.spx(parentHeight, computed, blockPadding)
    sizes.space.h = stretch(heightpx)
    sizes.bounds.minClamp[dtVertical] = heightpx
  if sizes.space.h.isDefinite() and sizes.maxHeight < sizes.space.h.u or
      sizes.maxHeight < LayoutUnit.high and sizes.space.h.t == scMaxContent:
    # same reasoning as for width.
    if sizes.space.h.t == scStretch:
      sizes.space.h = stretch(sizes.maxHeight)
    else: # scFitContent
      sizes.space.h = fitContent(sizes.maxHeight)
  if sizes.space.h.isDefinite() and sizes.minHeight > sizes.space.h.u or
      sizes.minHeight > 0 and sizes.space.h.t == scMinContent:
    # same reasoning as for width.
    sizes.space.h = stretch(sizes.minHeight)

proc resolveBlockSizes(lctx: LayoutContext; space: AvailableSpace;
    computed: CSSValues): ResolvedSizes =
  let padding = lctx.resolvePadding(space.w, computed)
  let paddingSum = padding.sum()
  var sizes = ResolvedSizes(
    margin: lctx.resolveMargins(space.w, computed),
    padding: padding,
    space: space,
    bounds: lctx.resolveBounds(space, paddingSum, computed)
  )
  # for tables, fit-content by default
  if computed{"display"} == DisplayTableWrapper:
    sizes.space.w = fitContent(sizes.space.w)
  # height is max-content normally, but fit-content for clip.
  sizes.space.h = if computed{"overflow"} != OverflowClip:
    maxContent()
  else:
    fitContent(sizes.space.h)
  # Finally, calculate available width and height.
  sizes.resolveBlockWidth(space.w, paddingSum[dtHorizontal], computed, lctx)
  #TODO parent height should be lctx height in quirks mode for percentage
  # resolution.
  sizes.resolveBlockHeight(space.h, paddingSum[dtVertical], computed, lctx)
  return sizes

proc append(a: var Strut; b: LayoutUnit) =
  if b < 0:
    a.neg = min(b, a.neg)
  else:
    a.pos = max(b, a.pos)

func sum(a: Strut): LayoutUnit =
  return a.pos + a.neg

# Forward declarations
proc layoutBlock(bctx: var BlockContext; box: BlockBox; sizes: ResolvedSizes)
proc layoutTableWrapper(bctx: BlockContext; box: BlockBox; sizes: ResolvedSizes)
proc layoutFlex(bctx: var BlockContext; box: BlockBox; sizes: ResolvedSizes)
proc layoutInline(ictx: var InlineContext; fragment: InlineFragment)
proc layoutRootBlock(lctx: LayoutContext; box: BlockBox; offset: Offset;
  sizes: ResolvedSizes): LayoutUnit

# Note: padding must still be applied after this.
proc applySize(box: BlockBox; sizes: ResolvedSizes;
    maxChildSize: LayoutUnit; space: AvailableSpace; dim: DimensionType) =
  # Make the box as small/large as the content's width or specified width.
  box.state.size[dim] = maxChildSize.applySizeConstraint(space[dim])
  # Then, clamp it to minWidth and maxWidth (if applicable).
  box.state.size[dim] = minClamp(box.state.size[dim], sizes.bounds.a[dim])

proc applyMinWidth(box: BlockBox; sizes: ResolvedSizes) =
  box.state.xminwidth = min(box.state.xminwidth,
    sizes.bounds.minClamp[dtHorizontal])

proc applyWidth(box: BlockBox; sizes: ResolvedSizes;
    maxChildWidth: LayoutUnit; space: AvailableSpace) =
  box.applySize(sizes, maxChildWidth, space, dtHorizontal)
  box.applyMinWidth(sizes)

proc applyWidth(box: BlockBox; sizes: ResolvedSizes;
    maxChildWidth: LayoutUnit) =
  box.applyWidth(sizes, maxChildWidth, sizes.space)

proc applyHeight(box: BlockBox; sizes: ResolvedSizes;
    maxChildHeight: LayoutUnit) =
  box.applySize(sizes, maxChildHeight, sizes.space, dtVertical)

proc applyPadding(box: BlockBox; padding: RelativeRect) =
  box.state.size.w += padding[dtHorizontal].sum()
  box.state.size.h += padding[dtVertical].sum()

proc applyBaseline(box: BlockBox) =
  if box.children.len > 0:
    let firstNested = box.children[0]
    let lastNested = box.children[^1]
    box.state.firstBaseline = firstNested.state.offset.y +
      firstNested.state.baseline
    box.state.baseline = lastNested.state.offset.y + lastNested.state.baseline

func bfcOffset(bctx: BlockContext): Offset =
  if bctx.parentBps != nil:
    return bctx.parentBps.offset
  return offset(x = 0, y = 0)

# expand to (0, size[dim].u)
func finalize(overflow: var Overflow; size: Size) =
  overflow[dtHorizontal].expand(Span(start: 0, send: size[dtHorizontal]))
  overflow[dtVertical].expand(Span(start: 0, send: size[dtVertical]))

const DisplayBlockLike = {DisplayBlock, DisplayListItem, DisplayInlineBlock}

# Return true if no more margin collapsing can occur for the current strut.
func canFlushMargins(box: BlockBox; sizes: ResolvedSizes): bool =
  if box.computed{"position"} in {PositionAbsolute, PositionFixed}:
    return false
  return sizes.padding.top != 0 or sizes.padding.bottom != 0 or
    box.inline != nil or box.computed{"display"} notin DisplayBlockLike or
    box.computed{"clear"} != ClearNone

proc flushMargins(bctx: var BlockContext; box: BlockBox) =
  # Apply uncommitted margins.
  let margin = bctx.marginTodo.sum()
  if bctx.marginTarget == nil:
    box.state.offset.y += margin
  else:
    if bctx.marginTarget.box != nil:
      bctx.marginTarget.box.state.offset.y += margin
    var p = bctx.marginTarget
    while true:
      p.offset.y += margin
      p.resolved = true
      p = p.next
      if p == nil: break
    bctx.marginTarget = nil
  bctx.marginTodo = Strut()

proc applyOverflowDimensions(parent: var Overflow; child: BlockBox) =
  var childOverflow = child.state.overflow
  for dim in DimensionType:
    childOverflow[dim] += child.state.offset[dim]
    parent[dim].expand(childOverflow[dim])

proc applyOverflowDimensions(box, child: BlockBox) =
  box.state.overflow.applyOverflowDimensions(child)

proc pushPositioned(lctx: LayoutContext) =
  lctx.positioned.add(PositionedItem())

# size is the parent's size
proc popPositioned(lctx: LayoutContext; overflow: var Overflow; size: Size) =
  let item = lctx.positioned.pop()
  for it in item.queue:
    let child = it.child
    lctx.pushPositioned()
    var positioned: RelativeRect
    var sizes = lctx.resolveAbsoluteSizes(size, positioned, child.computed)
    var marginBottom = lctx.layoutRootBlock(child, it.offset, sizes)
    if sizes.space.w.t == scFitContent and child.state.xminwidth > size.w:
      # In case the width is shrink-to-fit, and the available width is
      # less than the minimum width, then the minimum width overrides
      # the available width, and we must re-layout.
      sizes.space.w = stretch(child.state.xminwidth)
      marginBottom = lctx.layoutRootBlock(child, it.offset, sizes)
    if child.computed{"left"}.u != clAuto:
      child.state.offset.x = positioned.left + sizes.margin.left
    elif child.computed{"right"}.u != clAuto:
      child.state.offset.x = size.w - positioned.right - child.state.size.w -
        sizes.margin.right
    # margin.left is added in layoutRootBlock
    if child.computed{"top"}.u != clAuto:
      child.state.offset.y = positioned.top + sizes.margin.top
    elif child.computed{"bottom"}.u != clAuto:
      child.state.offset.y = size.h - positioned.bottom - child.state.size.h -
        sizes.margin.bottom
    else:
      child.state.offset.y += sizes.margin.top
    overflow.applyOverflowDimensions(child)
    #TODO this overflow looks wrong too
    lctx.popPositioned(overflow, child.state.size)

proc queueAbsolute(lctx: LayoutContext; box: BlockBox; offset: Offset) =
  case box.computed{"position"}
  of PositionAbsolute:
    lctx.positioned[^1].queue.add(QueuedAbsolute(child: box, offset: offset))
  of PositionFixed:
    lctx.positioned[0].queue.add(QueuedAbsolute(child: box, offset: offset))
  else: assert false

type
  BlockState = object
    offset: Offset
    maxChildWidth: LayoutUnit
    totalFloatWidth: LayoutUnit # used for re-layouts
    space: AvailableSpace
    xminwidth: LayoutUnit
    prevParentBps: BlockPositionState
    needsReLayout: bool
    # State kept for when a re-layout is necessary:
    oldMarginTodo: Strut
    oldExclusionsLen: int
    initialMarginTarget: BlockPositionState
    initialTargetOffset: Offset
    initialParentOffset: Offset
    relativeChildren: seq[BlockBox]

func findNextFloatOffset(bctx: BlockContext; offset: Offset; size: Size;
    space: AvailableSpace; float: CSSFloat; outw: var LayoutUnit): Offset =
  # Algorithm originally from QEmacs.
  var y = offset.y
  let leftStart = offset.x
  let rightStart = offset.x + max(size.w, space.w.u)
  while true:
    var left = leftStart
    var right = rightStart
    var miny = high(LayoutUnit)
    let cy2 = y + size.h
    for ex in bctx.exclusions:
      let ey2 = ex.offset.y + ex.size.h
      if cy2 >= ex.offset.y and y < ey2:
        let ex2 = ex.offset.x + ex.size.w
        if ex.t == FloatLeft and left < ex2:
          left = ex2
        if ex.t == FloatRight and right > ex.offset.x:
          right = ex.offset.x
        miny = min(ey2, miny)
    let w = right - left
    if w >= size.w or miny == high(LayoutUnit):
      # Enough space, or no other exclusions found at this y offset.
      outw = w
      if float == FloatLeft:
        return offset(x = left, y = y)
      else: # FloatRight
        return offset(x = right - size.w, y = y)
    # Move y to the bottom exclusion edge at the lowest y (where the exclusion
    # still intersects with the previous y).
    y = miny
  assert false

func findNextFloatOffset(bctx: BlockContext; offset: Offset; size: Size;
    space: AvailableSpace; float: CSSFloat): Offset =
  var dummy: LayoutUnit
  return bctx.findNextFloatOffset(offset, size, space, float, dummy)

func findNextBlockOffset(bctx: BlockContext; offset: Offset; size: Size;
    space: AvailableSpace; outw: var LayoutUnit): Offset =
  return bctx.findNextFloatOffset(offset, size, space, FloatLeft, outw)

proc positionFloat(bctx: var BlockContext; child: BlockBox;
    space: AvailableSpace; outerSize: Size; marginOffset, bfcOffset: Offset) =
  assert space.w.t != scFitContent
  let clear = child.computed{"clear"}
  if clear != ClearNone:
    child.state.offset.y.clearFloats(bctx, bctx.bfcOffset.y, clear)
  var childBfcOffset = bfcOffset + child.state.offset - marginOffset
  childBfcOffset.y = max(bctx.clearOffset, childBfcOffset.y)
  let ft = child.computed{"float"}
  assert ft != FloatNone
  let offset = bctx.findNextFloatOffset(childBfcOffset, outerSize, space, ft)
  child.state.offset = offset - bfcOffset + marginOffset
  bctx.exclusions.add(Exclusion(offset: offset, size: outerSize, t: ft))
  bctx.maxFloatHeight = max(bctx.maxFloatHeight, offset.y + outerSize.h)

proc positionFloats(bctx: var BlockContext) =
  for f in bctx.unpositionedFloats:
    bctx.positionFloat(f.box, f.space, f.outerSize, f.marginOffset,
      f.parentBps.offset)
    # Propagate overflow dimensions to the float's parent box.
    f.parentBox.applyOverflowDimensions(f.box)
  bctx.unpositionedFloats.setLen(0)

proc layoutInline(bctx: var BlockContext; box: BlockBox; sizes: ResolvedSizes) =
  if box.computed{"position"} notin PositionStaticLike:
    bctx.lctx.pushPositioned()
  let bfcOffset = if bctx.parentBps != nil:
    bctx.parentBps.offset + box.state.offset
  else: # this block establishes a new BFC.
    offset(0, 0)
  var ictx = bctx.initInlineContext(sizes.space, bfcOffset, sizes.padding,
    box.computed)
  ictx.initLine()
  ictx.layoutInline(box.inline)
  if ictx.lastTextFragment != nil:
    var state = InlineState(fragment: ictx.lastTextFragment)
    ictx.finishLine(state, wrap = false)
  if ictx.unpositionedFloats.len > 0 or
      ictx.space.w.t == scFitContent and
      ictx.computed{"text-align"} notin TextAlignNone and
      ictx.state.size.w != ictx.space.w.u:
    # fit-content initial guess didn't work out; re-layout, with width stretched
    # to the actual text width.
    #
    # Since we guess fit-content width to be the same width but stretched, this
    # should only run for cases where the text is shorter than the place it has,
    # or when some word overflows the place available.
    #
    # In the first case, we know that the text is relatively short, so it
    # affects performance little. As for the latter case... just pray it happens
    # rarely enough.
    let floats = move(ictx.unpositionedFloats)
    var space = sizes.space
    #TODO there is still a bug here: if the parent's size is
    # fit-content, then floats should trigger a re-layout in the
    # *parent*.
    if space.w.t != scStretch:
      space.w = stretch(ictx.state.size.w)
    ictx = bctx.initInlineContext(space, bfcOffset, sizes.padding, box.computed)
    for it in floats:
      bctx.positionFloat(it.box, space, it.outerSize, it.marginOffset,
        bfcOffset)
    ictx.initLine()
    ictx.secondPass = true
    ictx.layoutInline(box.inline)
    if ictx.lastTextFragment != nil:
      var state = InlineState(fragment: ictx.lastTextFragment)
      ictx.finishLine(state, wrap = false)
    for it in floats:
      it.parent.state.atoms.add(InlineAtom(
        t: iatInlineBlock,
        innerbox: it.box
      ))
  box.state.xminwidth = max(box.state.xminwidth, ictx.state.xminwidth)
  box.state.size.w = ictx.state.size.w + sizes.padding[dtHorizontal].sum()
  box.applyWidth(sizes, ictx.state.size.w)
  box.applyHeight(sizes, ictx.state.size.h)
  box.applyPadding(sizes.padding)
  box.state.baseline = ictx.state.baseline
  box.state.firstBaseline = ictx.state.firstBaseline
  box.state.overflow = ictx.state.overflow
  if box.computed{"position"} notin PositionStaticLike:
    bctx.lctx.popPositioned(box.state.overflow, box.state.size)
  box.state.overflow.finalize(box.state.size)

proc layoutFlow(bctx: var BlockContext; box: BlockBox; sizes: ResolvedSizes) =
  if box.canFlushMargins(sizes):
    bctx.flushMargins(box)
    bctx.positionFloats()
  if box.computed{"clear"} != ClearNone:
    box.state.offset.y.clearFloats(bctx, bctx.bfcOffset.y,
      box.computed{"clear"})
  if box.inline != nil:
    # Builder only contains inline boxes.
    bctx.layoutInline(box, sizes)
  else:
    # Builder only contains block boxes.
    bctx.layoutBlock(box, sizes)

proc layoutListItem(bctx: var BlockContext; box: BlockBox;
    sizes: ResolvedSizes) =
  case box.computed{"list-style-position"}
  of ListStylePositionOutside:
    let marker = box.children[0]
    let content = box.children[1]
    marker.state = BoxLayoutState()
    content.state = BoxLayoutState(offset: box.state.offset)
    bctx.layoutFlow(content, sizes)
    #TODO we should put markers right before the first atom of the parent
    # list item or something...
    var bctx = BlockContext(lctx: bctx.lctx)
    let markerSizes = ResolvedSizes(
      space: availableSpace(w = fitContent(sizes.space.w), h = sizes.space.h),
      bounds: DefaultBounds
    )
    bctx.layoutFlow(marker, markerSizes)
    marker.state.offset.x = -marker.state.size.w
    # take inner box min width etc.
    box.state = content.state
    content.state.offset = offset(x = 0, y = 0)
  of ListStylePositionInside:
    bctx.layoutFlow(box, sizes)

proc addInlineFloat(ictx: var InlineContext; state: var InlineState;
    box: BlockBox) =
  let lctx = ictx.lctx
  let sizes = lctx.resolveFloatSizes(ictx.space, box.computed)
  box.state = BoxLayoutState()
  let offset = offset(
    x = 0,
    y = ictx.lbstate.offsety + sizes.margin.top
  )
  let marginBottom = lctx.layoutRootBlock(box, offset, sizes)
  ictx.lbstate.size.w += box.state.size.w
  # Note that by now, the top y offset is always resolved.
  ictx.unpositionedFloats.add(InlineUnpositionedFloat(
    parent: state.fragment,
    box: box,
    space: sizes.space,
    outerSize: size(
      w = box.outerSize(dtHorizontal, sizes),
      h = box.outerSize(dtVertical, sizes) + marginBottom,
    ),
    marginOffset: sizes.margin.startOffset()
  ))

const DisplayOuterInline = {
  DisplayInlineBlock, DisplayInlineTableWrapper, DisplayInlineFlex
}

proc addInlineAbsolute(ictx: var InlineContext; state: var InlineState;
    box: BlockBox) =
  let lctx = ictx.lctx
  state.fragment.state.atoms.add(InlineAtom(
    t: iatInlineBlock,
    innerbox: box
  ))
  var offset = offset(x = 0, y = ictx.lbstate.offsety)
  if box.computed{"display"} in DisplayOuterInline:
    # inline-block or similar. put it on the current line.
    # (I don't add pending spacing because other browsers don't add
    # it either.)
    offset.x += ictx.lbstate.size.w
  elif ictx.lbstate.atoms.len > 0:
    # flush if there is already something on the line *and* our outer
    # display is block.
    offset.y += ictx.cellHeight
  lctx.queueAbsolute(box, offset)

proc addInlineBlock(ictx: var InlineContext; state: var InlineState;
    box: BlockBox) =
  let lctx = ictx.lctx
  var sizes = lctx.resolveFloatSizes(ictx.space, box.computed)
  for i, it in sizes.padding.mpairs:
    let cs = lctx.cellSize[i]
    it.start = (it.start div cs).toInt.toLayoutUnit * cs
    it.send = (it.send div cs).toInt.toLayoutUnit * cs
  box.state = BoxLayoutState()
  let marginBottom = lctx.layoutRootBlock(box, offset(x = 0, y = 0), sizes)
  # Apply the block box's properties to the atom itself.
  let iblock = InlineAtom(
    t: iatInlineBlock,
    innerbox: box,
    offset: offset(x = 0, y = 0),
    size: size(w = box.outerSize(dtHorizontal, sizes), h = box.state.size.h)
  )
  let iastate = InlineAtomState(
    baseline: box.state.baseline,
    vertalign: box.computed{"vertical-align"},
    marginTop: sizes.margin.top,
    marginBottom: marginBottom
  )
  discard ictx.addAtom(state, iastate, iblock)
  ictx.whitespacenum = 0

proc addBox(ictx: var InlineContext; state: var InlineState;
    box: BlockBox) =
  if box.computed{"position"} in {PositionAbsolute, PositionFixed}:
    # This doesn't really have to be an inline block. I just want to
    # handle its positioning here.
    ictx.addInlineAbsolute(state, box)
  elif box.computed{"float"} != FloatNone:
    # (Must check after `position: absolute', as that has higher precedence.)
    # This will trigger a re-layout for this inline root.
    if not ictx.secondPass:
      ictx.addInlineFloat(state, box)
  else:
    # This is an inline block.
    assert box.computed{"display"} in DisplayOuterInline
    ictx.addInlineBlock(state, box)

proc addInlineImage(ictx: var InlineContext; state: var InlineState;
    bmp: NetworkBitmap; padding: LayoutUnit) =
  let atom = InlineAtom(
    t: iatImage,
    bmp: bmp,
    size: size(w = bmp.width, h = bmp.height) #TODO overflow
  )
  let computed = state.fragment.computed
  let hasWidth = computed{"width"}.canpx(ictx.space.w)
  let hasHeight = computed{"height"}.canpx(ictx.space.h)
  let osize = atom.size
  if hasWidth:
    atom.size.w = computed{"width"}.spx(ictx.space.w, computed, padding)
  if hasHeight:
    atom.size.h = computed{"height"}.spx(ictx.space.h, computed, padding)
  if computed{"max-width"}.canpx(ictx.space.w):
    let w = computed{"max-width"}.spx(ictx.space.w, computed, padding)
    atom.size.w = min(atom.size.w, w)
  if computed{"min-width"}.canpx(ictx.space.w):
    let w = computed{"min-width"}.spx(ictx.space.w, computed, padding)
    atom.size.w = max(atom.size.w, w)
  if computed{"max-height"}.canpx(ictx.space.h):
    let h = computed{"max-height"}.spx(ictx.space.h, computed, padding)
    atom.size.h = min(atom.size.h, h)
  if computed{"min-height"}.canpx(ictx.space.h):
    let h = computed{"min-height"}.spx(ictx.space.h, computed, padding)
    atom.size.h = max(atom.size.h, h)
  if not hasWidth and ictx.space.w.isDefinite():
    atom.size.w = min(ictx.space.w.u, atom.size.w)
  if not hasHeight and ictx.space.h.isDefinite():
    atom.size.h = min(ictx.space.h.u, atom.size.h)
  if not hasHeight and not hasWidth:
    if osize.w >= osize.h:
      if osize.w > 0:
        atom.size.h = osize.h div osize.w * atom.size.w
    else:
      if osize.h > 0:
        atom.size.w = osize.w div osize.h * atom.size.h
  elif not hasHeight:
    atom.size.h = osize.h div osize.w * atom.size.w
  elif not hasWidth:
    atom.size.w = osize.w div osize.h * atom.size.h
  let iastate = InlineAtomState(
    vertalign: state.fragment.computed{"vertical-align"},
    baseline: atom.size.h
  )
  discard ictx.addAtom(state, iastate, atom)
  if atom.size.h > 0:
    # Setting the atom size as xminwidth might result in a circular dependency
    # between table cell sizing and image sizing when we don't have a definite
    # parent size yet. e.g. <img width=100% ...> with an indefinite containing
    # size (i.e. the first table cell pass) would resolve to an xminwidth of
    # image.width, stretching out the table to an uncomfortably large size.
    if ictx.space.w.isDefinite() or computed{"width"}.u != clPerc and
        computed{"min-width"}.u != clPerc:
      ictx.state.xminwidth = max(ictx.state.xminwidth, atom.size.w)

proc layoutInline(ictx: var InlineContext; fragment: InlineFragment) =
  let lctx = ictx.lctx
  let computed = fragment.computed
  var padding = Span()
  if stSplitStart in fragment.splitType:
    let w = computed{"margin-left"}.px(ictx.space.w)
    ictx.lbstate.size.w += w
    ictx.lbstate.widthAfterWhitespace += w
    padding = Span(
      start: computed{"padding-left"}.px(ictx.space.w),
      send: computed{"padding-right"}.px(ictx.space.w)
    )
  fragment.state = InlineFragmentState()
  if padding.start != 0:
    fragment.state.areas.add(Area(
      offset: offset(x = ictx.lbstate.widthAfterWhitespace, y = 0),
      size: size(w = padding.start, h = ictx.cellHeight)
    ))
    ictx.lbstate.paddingTodo.add((fragment, 0))
  fragment.state.startOffset = offset(
    x = ictx.lbstate.widthAfterWhitespace,
    y = ictx.lbstate.offsety
  )
  ictx.lbstate.size.w += padding.start
  var state = InlineState(fragment: fragment)
  if stSplitStart in fragment.splitType and
      computed{"position"} notin PositionStaticLike:
    lctx.pushPositioned()
  case fragment.t
  of iftNewline:
    ictx.finishLine(state, wrap = false, force = true,
      fragment.computed{"clear"})
  of iftBox: ictx.addBox(state, fragment.box)
  of iftBitmap: ictx.addInlineImage(state, fragment.bmp, padding.sum())
  of iftText: ictx.layoutText(state, fragment.text.textData)
  of iftParent:
    for child in fragment.children:
      ictx.layoutInline(child)
  if padding.send != 0:
    fragment.state.areas.add(Area(
      offset: offset(x = ictx.lbstate.size.w, y = 0),
      size: size(w = padding.send, h = ictx.cellHeight)
    ))
    ictx.lbstate.paddingTodo.add((fragment, fragment.state.areas.high))
  if stSplitEnd in fragment.splitType:
    ictx.lbstate.size.w += padding.send
    ictx.lbstate.size.w += computed{"margin-right"}.px(ictx.space.w)
  if fragment.t != iftParent:
    if not ictx.textFragmentSeen:
      ictx.textFragmentSeen = true
    ictx.lastTextFragment = fragment
  if stSplitEnd in fragment.splitType and
      computed{"position"} notin PositionStaticLike:
    # This is UB in CSS 2.1, I can't find a newer spec about it,
    # and Gecko can't even layout it consistently (???)
    #
    # So I'm trying to follow Blink, though it's still not quite right.
    # For one, space should really be the sum of all splits of this
    # inline box, but I've wasted enough time on this already so I'm
    # gonna stop here and say "good enough".
    #TODO this overflow calculation looks wrong
    lctx.popPositioned(ictx.state.overflow, size(w = 0, h = ictx.state.size.h))

proc positionRelative(lctx: LayoutContext; parent, box: BlockBox) =
  let positioned = lctx.resolvePositioned(parent.state.size, box.computed)
  if box.computed{"left"}.u != clAuto:
    box.state.offset.x += positioned.left
  elif box.computed{"right"}.u != clAuto:
    box.state.offset.x += parent.state.size.w - box.state.size.w -
      positioned.right
  if box.computed{"top"}.u != clAuto:
    box.state.offset.y += positioned.top
  elif box.computed{"bottom"}.u != clAuto:
    box.state.offset.y += parent.state.size.h - box.state.size.h -
      positioned.bottom

# Note: caption is not included here
const RowGroupBox = {
  DisplayTableRowGroup, DisplayTableHeaderGroup, DisplayTableFooterGroup
}
const ProperTableChild = RowGroupBox + {
  DisplayTableRow, DisplayTableColumn, DisplayTableColumnGroup
}
const ProperTableRowParent = RowGroupBox + {
  DisplayTable, DisplayInlineTable
}

type
  CellWrapper = ref object
    box: BlockBox
    coli: int
    colspan: int
    rowspan: int
    reflow: bool
    grown: int # number of remaining rows
    real: CellWrapper # for filler wrappers
    last: bool # is this the last filler?
    height: LayoutUnit
    baseline: LayoutUnit

  RowContext = object
    cells: seq[CellWrapper]
    reflow: seq[bool]
    width: LayoutUnit
    height: LayoutUnit
    box: BlockBox
    ncols: int

  ColumnContext = object
    minwidth: LayoutUnit
    width: LayoutUnit
    wspecified: bool
    reflow: bool
    weight: float64

  TableContext = object
    lctx: LayoutContext
    rows: seq[RowContext]
    cols: seq[ColumnContext]
    growing: seq[CellWrapper]
    maxwidth: LayoutUnit
    blockSpacing: LayoutUnit
    inlineSpacing: LayoutUnit
    space: AvailableSpace # space we got from parent

proc layoutTableCell(lctx: LayoutContext; box: BlockBox;
    space: AvailableSpace) =
  var sizes = ResolvedSizes(
    padding: lctx.resolvePadding(space.w, box.computed),
    space: availableSpace(w = space.w, h = maxContent()),
    bounds: DefaultBounds
  )
  if sizes.space.w.isDefinite():
    sizes.space.w.u -= sizes.padding[dtHorizontal].sum()
  box.state = BoxLayoutState()
  var bctx = BlockContext(lctx: lctx)
  bctx.layoutFlow(box, sizes)
  assert bctx.unpositionedFloats.len == 0
  # Table cells ignore margins.
  box.state.offset.y = 0
  # If the highest float edge is higher than the box itself, set that as
  # the box height.
  box.state.size.h = max(box.state.size.h, bctx.maxFloatHeight)
  if space.h.t == scStretch:
    box.state.size.h = max(box.state.size.h, space.h.u -
      sizes.padding[dtVertical].sum())
  # A table cell's minimum width overrides its width.
  box.state.size.w = max(box.state.size.w, box.state.xminwidth)

# Sort growing cells, and filter out cells that have grown to their intended
# rowspan.
proc sortGrowing(pctx: var TableContext) =
  var i = 0
  for j, cellw in pctx.growing:
    if pctx.growing[i].grown == 0:
      continue
    if j != i:
      pctx.growing[i] = cellw
    inc i
  pctx.growing.setLen(i)
  pctx.growing.sort(proc(a, b: CellWrapper): int = cmp(a.coli, b.coli))

# Grow cells with a rowspan > 1 (to occupy their place in a new row).
proc growRowspan(pctx: var TableContext; ctx: var RowContext;
    growi, i, n: var int; growlen: int) =
  while growi < growlen:
    let cellw = pctx.growing[growi]
    if cellw.coli > n:
      break
    dec cellw.grown
    let colspan = cellw.colspan - (n - cellw.coli)
    let rowspanFiller = CellWrapper(
      colspan: colspan,
      rowspan: cellw.rowspan,
      coli: n,
      real: cellw,
      last: cellw.grown == 0
    )
    ctx.cells.add(nil)
    ctx.cells[i] = rowspanFiller
    for i in n ..< n + colspan:
      ctx.width += pctx.cols[i].width
      ctx.width += pctx.inlineSpacing * 2
    n += cellw.colspan
    inc i
    inc growi

proc preLayoutTableRow(pctx: var TableContext; row, parent: BlockBox;
    rowi, numrows: int): RowContext =
  var ctx = RowContext(box: row, cells: newSeq[CellWrapper](row.children.len))
  var n = 0
  var i = 0
  var growi = 0
  # this increases in the loop, but we only want to check growing cells that
  # were added by previous rows.
  let growlen = pctx.growing.len
  for box in row.children:
    assert box.computed{"display"} == DisplayTableCell
    pctx.growRowspan(ctx, growi, i, n, growlen)
    let colspan = box.computed{"-cha-colspan"}
    let rowspan = min(box.computed{"-cha-rowspan"}, numrows - rowi)
    let cw = box.computed{"width"}
    let ch = box.computed{"height"}
    let space = availableSpace(
      w = cw.stretchOrMaxContent(pctx.space.w),
      h = ch.stretchOrMaxContent(pctx.space.h)
    )
    #TODO specified table height should be distributed among rows.
    # Allow the table cell to use its specified width.
    pctx.lctx.layoutTableCell(box, space)
    let wrapper = CellWrapper(
      box: box,
      colspan: colspan,
      rowspan: rowspan,
      coli: n
    )
    ctx.cells[i] = wrapper
    if rowspan > 1:
      pctx.growing.add(wrapper)
      wrapper.grown = rowspan - 1
    if pctx.cols.len < n + colspan:
      pctx.cols.setLen(n + colspan)
    if ctx.reflow.len < n + colspan:
      ctx.reflow.setLen(n + colspan)
    let minw = box.state.xminwidth div colspan
    let w = box.state.size.w div colspan
    for i in n ..< n + colspan:
      # Add spacing.
      ctx.width += pctx.inlineSpacing
      # Figure out this cell's effect on the column's width.
      # Four cases exist:
      # 1. colwidth already fixed, cell width is fixed: take maximum
      # 2. colwidth already fixed, cell width is auto: take colwidth
      # 3. colwidth is not fixed, cell width is fixed: take cell width
      # 4. neither of colwidth or cell width are fixed: take maximum
      if pctx.cols[i].wspecified:
        if space.w.isDefinite():
          # A specified column already exists; we take the larger width.
          if w > pctx.cols[i].width:
            pctx.cols[i].width = w
            ctx.reflow[i] = true
        if pctx.cols[i].width != w:
          wrapper.reflow = true
      elif space.w.isDefinite():
        # This is the first specified column. Replace colwidth with whatever
        # we have.
        ctx.reflow[i] = true
        pctx.cols[i].wspecified = true
        pctx.cols[i].width = w
      elif w > pctx.cols[i].width:
        pctx.cols[i].width = w
        ctx.reflow[i] = true
      else:
        wrapper.reflow = true
      if pctx.cols[i].minwidth < minw:
        pctx.cols[i].minwidth = minw
        if pctx.cols[i].width < minw:
          pctx.cols[i].width = minw
          ctx.reflow[i] = true
      ctx.width += pctx.cols[i].width
      # Add spacing to the right side.
      ctx.width += pctx.inlineSpacing
    n += colspan
    inc i
  pctx.growRowspan(ctx, growi, i, n, growlen)
  pctx.sortGrowing()
  when defined(debug):
    for cell in ctx.cells:
      assert cell != nil
  ctx.ncols = n
  return ctx

proc alignTableCell(cell: BlockBox; availableHeight, baseline: LayoutUnit) =
  case cell.computed{"vertical-align"}.keyword
  of VerticalAlignTop:
    cell.state.offset.y = 0
  of VerticalAlignMiddle:
    cell.state.offset.y = availableHeight div 2 - cell.state.size.h div 2
  of VerticalAlignBottom:
    cell.state.offset.y = availableHeight - cell.state.size.h
  else:
    cell.state.offset.y = baseline - cell.state.firstBaseline

proc layoutTableRow(tctx: TableContext; ctx: RowContext;
    parent, row: BlockBox) =
  row.state = BoxLayoutState()
  var x: LayoutUnit = 0
  var n = 0
  var baseline: LayoutUnit = 0
  # real cellwrappers of fillers
  var toAlign: seq[CellWrapper] = @[]
  # cells with rowspan > 1 that must store baseline
  var toBaseline: seq[CellWrapper] = @[]
  # cells that we must update row height of
  var toHeight: seq[CellWrapper] = @[]
  for cellw in ctx.cells:
    var w: LayoutUnit = 0
    for i in n ..< n + cellw.colspan:
      w += tctx.cols[i].width
    # Add inline spacing for merged columns.
    w += tctx.inlineSpacing * (cellw.colspan - 1) * 2
    if cellw.reflow and cellw.box != nil:
      # Do not allow the table cell to make use of its specified width.
      # e.g. in the following table
      # <TABLE>
      # <TR>
      # <TD style="width: 5ch" bgcolor=blue>5ch</TD>
      # </TR>
      # <TR>
      # <TD style="width: 9ch" bgcolor=red>9ch</TD>
      # </TR>
      # </TABLE>
      # the TD with a width of 5ch should be 9ch wide as well.
      let space = availableSpace(w = stretch(w), h = maxContent())
      tctx.lctx.layoutTableCell(cellw.box, space)
      w = max(w, cellw.box.state.size.w)
    let cell = cellw.box
    x += tctx.inlineSpacing
    if cell != nil:
      cell.state.offset.x += x
    x += tctx.inlineSpacing
    x += w
    n += cellw.colspan
    const HasNoBaseline = {
      VerticalAlignTop, VerticalAlignMiddle, VerticalAlignBottom
    }
    if cell != nil:
      if cell.computed{"vertical-align"}.keyword notin HasNoBaseline: # baseline
        baseline = max(cell.state.firstBaseline, baseline)
        if cellw.rowspan > 1:
          toBaseline.add(cellw)
      if cellw.rowspan > 1:
        toHeight.add(cellw)
      row.state.size.h = max(row.state.size.h,
        cell.state.size.h div cellw.rowspan)
    else:
      row.state.size.h = max(row.state.size.h,
        cellw.real.box.state.size.h div cellw.rowspan)
      toHeight.add(cellw.real)
      if cellw.last:
        toAlign.add(cellw.real)
  for cellw in toHeight:
    cellw.height += row.state.size.h
  for cellw in toBaseline:
    cellw.baseline = baseline
  for cellw in toAlign:
    alignTableCell(cellw.box, cellw.height, cellw.baseline)
  for cell in row.children:
    alignTableCell(cell, row.state.size.h, baseline)
    # cell position is final here; apply overflow dimensions
    row.applyOverflowDimensions(cell)
  row.state.size.w = x

proc preLayoutTableRows(tctx: var TableContext; rows: openArray[BlockBox];
    table: BlockBox) =
  for i, row in rows.mypairs:
    let rctx = tctx.preLayoutTableRow(row, table, i, rows.len)
    tctx.rows.add(rctx)
    tctx.maxwidth = max(rctx.width, tctx.maxwidth)

proc preLayoutTableRows(tctx: var TableContext; table: BlockBox) =
  # Use separate seqs for different row groups, so that e.g. this HTML:
  # echo '<TABLE><TBODY><TR><TD>world<THEAD><TR><TD>hello'|cha -T text/html
  # is rendered as:
  # hello
  # world
  var thead: seq[BlockBox] = @[]
  var tbody: seq[BlockBox] = @[]
  var tfoot: seq[BlockBox] = @[]
  for child in table.children:
    case child.computed{"display"}
    of DisplayTableRow: tbody.add(child)
    of DisplayTableHeaderGroup: thead.add(child.children)
    of DisplayTableRowGroup: tbody.add(child.children)
    of DisplayTableFooterGroup: tfoot.add(child.children)
    else: assert false
  tctx.preLayoutTableRows(thead, table)
  tctx.preLayoutTableRows(tbody, table)
  tctx.preLayoutTableRows(tfoot, table)

func calcSpecifiedRatio(tctx: TableContext; W: LayoutUnit): LayoutUnit =
  var totalSpecified: LayoutUnit = 0
  var hasUnspecified = false
  for col in tctx.cols:
    if col.wspecified:
      totalSpecified += col.width
    else:
      hasUnspecified = true
      totalSpecified += col.minwidth
  # Only grow specified columns if no unspecified column exists to take the
  # rest of the space.
  if totalSpecified == 0 or W > totalSpecified and hasUnspecified:
    return 1
  return W div totalSpecified

proc calcUnspecifiedColIndices(tctx: var TableContext; W: var LayoutUnit;
    weight: var float64): seq[int] =
  let specifiedRatio = tctx.calcSpecifiedRatio(W)
  # Spacing for each column:
  var avail = newSeqOfCap[int](tctx.cols.len)
  for i, col in tctx.cols.mpairs:
    if not col.wspecified:
      avail.add(i)
      let w = if col.width < W:
        toFloat64(col.width)
      else:
        toFloat64(W) * (ln(toFloat64(col.width) / toFloat64(W)) + 1)
      col.weight = w
      weight += w
    else:
      if specifiedRatio != 1:
        col.width *= specifiedRatio
        col.reflow = true
      W -= col.width
  return avail

func needsRedistribution(tctx: TableContext; computed: CSSValues):
    bool =
  case tctx.space.w.t
  of scMinContent, scMaxContent:
    return false
  of scStretch:
    return tctx.space.w.u != tctx.maxwidth
  of scFitContent:
    return tctx.space.w.u > tctx.maxwidth and computed{"width"}.u != clAuto or
        tctx.space.w.u < tctx.maxwidth

proc redistributeWidth(tctx: var TableContext) =
  # Remove inline spacing from distributable width.
  var W = tctx.space.w.u - tctx.cols.len * tctx.inlineSpacing * 2
  var weight = 0f64
  var avail = tctx.calcUnspecifiedColIndices(W, weight)
  var redo = true
  while redo and avail.len > 0 and weight != 0:
    if weight == 0: break # zero weight; nothing to distribute
    if W < 0:
      W = 0
    redo = false
    # divide delta width by sum of ln(width) for all elem in avail
    let unit = toFloat64(W) / weight
    weight = 0
    for i in countdown(avail.high, 0):
      let j = avail[i]
      let x = (unit * tctx.cols[j].weight).toLayoutUnit()
      let mw = tctx.cols[j].minwidth
      tctx.cols[j].width = x
      if mw > x:
        W -= mw
        tctx.cols[j].width = mw
        avail.del(i)
        redo = true
      else:
        weight += tctx.cols[j].weight
      tctx.cols[j].reflow = true

proc reflowTableCells(tctx: var TableContext) =
  for i in countdown(tctx.rows.high, 0):
    var row = addr tctx.rows[i]
    var n = tctx.cols.len - 1
    for j in countdown(row.cells.high, 0):
      let m = n - row.cells[j].colspan
      while n > m:
        if tctx.cols[n].reflow:
          row.cells[j].reflow = true
        if n < row.reflow.len and row.reflow[n]:
          tctx.cols[n].reflow = true
        dec n

proc layoutTableRows(tctx: TableContext; table: BlockBox;
    sizes: ResolvedSizes) =
  var y: LayoutUnit = 0
  for roww in tctx.rows:
    if roww.box.computed{"visibility"} == VisibilityCollapse:
      continue
    y += tctx.blockSpacing
    let row = roww.box
    tctx.layoutTableRow(roww, table, row)
    row.state.offset.y += y
    row.state.offset.x += sizes.padding.left
    row.state.size.w += sizes.padding[dtHorizontal].sum()
    # row size does not change from here on.
    row.state.overflow.finalize(row.state.size)
    y += tctx.blockSpacing
    y += row.state.size.h
    table.state.size.w = max(row.state.size.w, table.state.size.w)
  # Note: we can't use applySizeConstraint here; in CSS, "height" on tables just
  # sets the minimum height.
  case sizes.space.h.t
  of scStretch:
    table.state.size.h = max(sizes.space.h.u, y)
  of scMinContent, scMaxContent, scFitContent:
    # I don't think these are ever used here; not that they make much sense for
    # min-height...
    table.state.size.h = y

proc layoutCaption(tctx: TableContext; parent, box: BlockBox) =
  let lctx = tctx.lctx
  let space = availableSpace(w = stretch(parent.state.size.w), h = maxContent())
  let sizes = lctx.resolveBlockSizes(space, box.computed)
  let marginBottom = lctx.layoutRootBlock(box, offset(x = 0, y = 0), sizes)
  box.state.offset.x += sizes.margin.left
  box.state.offset.y += sizes.margin.top
  let outerHeight = box.outerSize(dtVertical, sizes) + marginBottom
  let outerWidth = box.outerSize(dtHorizontal, sizes)
  let table = parent.children[0]
  case box.computed{"caption-side"}
  of CaptionSideTop, CaptionSideBlockStart:
    table.state.offset.y += outerHeight
  of CaptionSideBottom, CaptionSideBlockEnd:
    box.state.offset.y += table.state.size.h
  parent.state.size.h += outerHeight
  parent.state.size.w = max(parent.state.size.w, outerWidth)
  parent.state.xminwidth = max(parent.state.xminwidth, box.state.xminwidth)

# Table layout. We try to emulate w3m's behavior here:
# 1. Calculate minimum and preferred width of each column
# 2. If column width is not auto, set width to max(min_col_width, specified)
# 3. Calculate the maximum preferred row width. If this is
# a) less than the specified table width, or
# b) greater than the table's content width:
#      Distribute the table's content width among cells with an unspecified
#      width. If this would give any cell a width < min_width, set that
#      cell's width to min_width, then re-do the distribution.
proc layoutTable(tctx: var TableContext; table: BlockBox;
    sizes: ResolvedSizes) =
  if tctx.space.w.t == scStretch:
    table.state.xminwidth = tctx.space.w.u
  if table.computed{"border-collapse"} != BorderCollapseCollapse:
    let spc = table.computed{"border-spacing"}
    if spc != nil:
      tctx.inlineSpacing = table.computed{"border-spacing"}.a.px(0)
      tctx.blockSpacing = table.computed{"border-spacing"}.b.px(0)
  tctx.preLayoutTableRows(table) # first pass
  if tctx.needsRedistribution(table.computed):
    tctx.redistributeWidth()
  for col in tctx.cols:
    table.state.size.w += col.width
  tctx.reflowTableCells()
  tctx.layoutTableRows(table, sizes) # second pass

# As per standard, we must put the caption outside the actual table, inside a
# block-level wrapper box.
proc layoutTableWrapper(bctx: BlockContext; box: BlockBox;
    sizes: ResolvedSizes) =
  let table = box.children[0]
  table.state = BoxLayoutState()
  var tctx = TableContext(lctx: bctx.lctx, space: sizes.space)
  tctx.layoutTable(table, sizes)
  box.state.size = table.state.size
  box.state.baseline = table.state.size.h
  box.state.firstBaseline = table.state.size.h
  box.state.xminwidth = table.state.xminwidth
  if box.children.len > 1:
    # do it here, so that caption's box can stretch to our width
    let caption = box.children[1]
    #TODO also count caption width in table width
    tctx.layoutCaption(box, caption)
  #TODO overflow

proc layout(bctx: var BlockContext; box: BlockBox; sizes: ResolvedSizes) =
  case box.computed{"display"}
  of DisplayBlock, DisplayFlowRoot, DisplayTableCaption, DisplayInlineBlock:
    bctx.layoutFlow(box, sizes)
  of DisplayListItem:
    bctx.layoutListItem(box, sizes)
  of DisplayTableWrapper, DisplayInlineTableWrapper:
    bctx.layoutTableWrapper(box, sizes)
  of DisplayFlex, DisplayInlineFlex:
    bctx.layoutFlex(box, sizes)
  else:
    assert false

proc layoutFlexChild(lctx: LayoutContext; box: BlockBox; sizes: ResolvedSizes) =
  var bctx = BlockContext(lctx: lctx)
  # note: we do not append margins here, since those belong to the flex item,
  # not its inner BFC.
  box.state = BoxLayoutState(offset: offset(x = sizes.margin.left, y = 0))
  bctx.layout(box, sizes)
  assert bctx.unpositionedFloats.len == 0
  # If the highest float edge is higher than the box itself, set that as
  # the box height.
  box.state.size.h = max(box.state.size.h, bctx.maxFloatHeight)

type
  FlexWeightType = enum
    fwtGrow, fwtShrink

  FlexPendingItem = object
    child: BlockBox
    weights: array[FlexWeightType, float64]
    sizes: ResolvedSizes

  FlexContext = object
    mains: seq[FlexMainContext]
    offset: Offset
    lctx: LayoutContext
    totalMaxSize: Size
    box: BlockBox
    relativeChildren: seq[BlockBox]
    redistSpace: SizeConstraint

  FlexMainContext = object
    totalSize: Size
    maxSize: Size
    shrinkSize: LayoutUnit
    maxMargin: RelativeRect
    totalWeight: array[FlexWeightType, float64]
    pending: seq[FlexPendingItem]

const FlexRow = {FlexDirectionRow, FlexDirectionRowReverse}

# This is practically the min-content size. For height, we just take the
# output height of the previous pass; for width, we take the shortest word's
# width (xminwidth).
func minFlexItemSize(state: BoxLayoutState; dim: DimensionType): LayoutUnit =
  case dim
  of dtHorizontal: return state.xminwidth
  of dtVertical: return state.size.h

proc updateMaxSizes(mctx: var FlexMainContext; child: BlockBox;
    sizes: ResolvedSizes) =
  for dim in DimensionType:
    mctx.maxSize[dim] = max(mctx.maxSize[dim], child.state.size[dim])
    mctx.maxMargin[dim].start = max(mctx.maxMargin[dim].start,
      sizes.margin[dim].start)
    mctx.maxMargin[dim].send = max(mctx.maxMargin[dim].send,
      sizes.margin[dim].send)

proc redistributeMainSize(mctx: var FlexMainContext; diff: LayoutUnit;
    wt: FlexWeightType; dim: DimensionType; lctx: LayoutContext) =
  var diff = diff
  var totalWeight = mctx.totalWeight[wt]
  let odim = dim.opposite
  while (wt == fwtGrow and diff > 0 or wt == fwtShrink and diff < 0) and
      totalWeight > 0:
    # redo maxSize calculation; we only need height here
    mctx.maxSize[odim] = 0
    var udiv = totalWeight
    if wt == fwtShrink:
      udiv *= mctx.shrinkSize.toFloat64() / totalWeight
    let unit = if udiv != 0:
      diff.toFloat64() / udiv
    else:
      0
    # reset total weight & available diff for the next iteration (if there is
    # one)
    totalWeight = 0
    diff = 0
    for it in mctx.pending.mitems:
      if it.weights[wt] == 0:
        mctx.updateMaxSizes(it.child, it.sizes)
        continue
      var uw = unit * it.weights[wt]
      if wt == fwtShrink:
        uw *= it.child.state.size[dim].toFloat64()
      var u = it.child.state.size[dim] + uw.toLayoutUnit()
      # check for min/max violation
      var minu = it.sizes.bounds.a[dim].start
      minu = max(it.child.state.minFlexItemSize(dim), minu)
      if minu > u:
        # min violation
        if wt == fwtShrink: # freeze
          diff += u - minu
          it.weights[wt] = 0
          mctx.shrinkSize -= it.child.state.size[dim]
        u = minu
      let maxu = it.sizes.bounds.a[dim].max()
      if maxu < u:
        # max violation
        if wt == fwtGrow: # freeze
          diff += u - maxu
          it.weights[wt] = 0
        u = maxu
      it.sizes.space[dim] = stretch(u - it.sizes.padding[dim].sum())
      totalWeight += it.weights[wt]
      #TODO we should call this only on freeze, and then put another loop to
      # the end for non-frozen items
      lctx.layoutFlexChild(it.child, it.sizes)
      mctx.updateMaxSizes(it.child, it.sizes)

proc flushMain(fctx: var FlexContext; mctx: var FlexMainContext;
    sizes: ResolvedSizes; dim: DimensionType) =
  let odim = dim.opposite
  let lctx = fctx.lctx
  if fctx.redistSpace.isDefinite:
    let diff = fctx.redistSpace.u - mctx.totalSize[dim]
    let wt = if diff > 0: fwtGrow else: fwtShrink
    # Do not grow shrink-to-fit sizes.
    if wt == fwtShrink or fctx.redistSpace.t == scStretch:
      mctx.redistributeMainSize(diff, wt, dim, lctx)
  elif sizes.bounds.a[dim].start > 0:
    # Override with min-width/min-height, but *only* if we are smaller
    # than the desired size. (Otherwise, we would incorrectly limit
    # max-content size when only a min-width is requested.)
    if sizes.bounds.a[dim].start > mctx.totalSize[dim]:
      let diff = sizes.bounds.a[dim].start - mctx.totalSize[dim]
      mctx.redistributeMainSize(diff, fwtGrow, dim, lctx)
  let h = mctx.maxSize[odim] + mctx.maxMargin[odim].sum()
  var offset = fctx.offset
  for it in mctx.pending.mitems:
    if it.child.state.size[odim] < h and not it.sizes.space[odim].isDefinite:
      # if the max height is greater than our height, then take max height
      # instead. (if the box's available height is definite, then this will
      # change nothing, so we skip it as an optimization.)
      it.sizes.space[odim] = stretch(h - it.sizes.margin[odim].sum())
      lctx.layoutFlexChild(it.child, it.sizes)
    it.child.state.offset[dim] += offset[dim]
    # margins are added here, since they belong to the flex item.
    it.child.state.offset[odim] += offset[odim] + it.sizes.margin[odim].start
    offset[dim] += it.child.state.size[dim]
    offset[dim] += it.sizes.margin[dim].send
    if it.child.computed{"position"} == PositionRelative:
      fctx.relativeChildren.add(it.child)
    else:
      fctx.box.applyOverflowDimensions(it.child)
  fctx.totalMaxSize[dim] = max(fctx.totalMaxSize[dim], offset[dim])
  fctx.mains.add(mctx)
  mctx = FlexMainContext()
  fctx.offset[odim] += h

proc layoutFlex(bctx: var BlockContext; box: BlockBox; sizes: ResolvedSizes) =
  assert box.inline == nil
  let lctx = bctx.lctx
  if box.computed{"position"} notin PositionStaticLike:
    lctx.pushPositioned()
  let flexDir = box.computed{"flex-direction"}
  let dim = if flexDir in FlexRow: dtHorizontal else: dtVertical
  let odim = dim.opposite()
  var fctx = FlexContext(
    lctx: lctx,
    box: box,
    offset: offset(x = sizes.padding.left, y = sizes.padding.top),
    redistSpace: sizes.space[dim]
  )
  if fctx.redistSpace.t == scFitContent and sizes.bounds.a[dim].start > 0:
    fctx.redistSpace = stretch(sizes.bounds.a[dim].start)
  if fctx.redistSpace.isDefinite:
    fctx.redistSpace.u = fctx.redistSpace.u.minClamp(sizes.bounds.a[dim])
  var mctx = FlexMainContext()
  let canWrap = box.computed{"flex-wrap"} != FlexWrapNowrap
  for child in box.children:
    var childSizes = lctx.resolveFlexItemSizes(sizes.space, dim, child.computed)
    let flexBasis = child.computed{"flex-basis"}
    lctx.layoutFlexChild(child, childSizes)
    if flexBasis.u != clAuto and sizes.space[dim].isDefinite:
      # we can't skip this pass; it is needed to calculate the minimum
      # height.
      let minu = child.state.minFlexItemSize(dim)
      childSizes.space[dim] = stretch(flexBasis.spx(sizes.space[dim],
        child.computed, childSizes.padding[dim].sum()))
      if minu > childSizes.space[dim].u:
        # First pass gave us a box that is thinner than the minimum
        # acceptable width for whatever reason; this may have happened
        # because the initial flex basis was e.g. 0. Try to resize it to
        # something more usable.
        childSizes.space[dim] = stretch(minu)
      lctx.layoutFlexChild(child, childSizes)
    if child.computed{"position"} in {PositionAbsolute, PositionFixed}:
      # Absolutely positioned flex children do not participate in flex layout.
      lctx.queueAbsolute(child, offset(x = 0, y = 0))
      continue
    if canWrap and (sizes.space[dim].t == scMinContent or
        sizes.space[dim].isDefinite and
        mctx.totalSize[dim] + child.state.size[dim] > sizes.space[dim].u):
      fctx.flushMain(mctx, sizes, dim)
    let outerSize = child.outerSize(dim, childSizes)
    mctx.updateMaxSizes(child, childSizes)
    let grow = child.computed{"flex-grow"}
    let shrink = child.computed{"flex-shrink"}
    mctx.totalWeight[fwtGrow] += grow
    mctx.totalWeight[fwtShrink] += shrink
    mctx.totalSize[dim] += outerSize
    if shrink != 0:
      mctx.shrinkSize += outerSize
    mctx.pending.add(FlexPendingItem(
      child: child,
      weights: [grow, shrink],
      sizes: childSizes
    ))
  if mctx.pending.len > 0:
    fctx.flushMain(mctx, sizes, dim)
  box.applyBaseline()
  box.applySize(sizes, fctx.totalMaxSize[dim], sizes.space, dim)
  box.applySize(sizes, fctx.offset[odim], sizes.space, odim)
  box.applyMinWidth(sizes)
  for child in fctx.relativeChildren:
    lctx.positionRelative(box, child)
    box.applyOverflowDimensions(child)
  box.state.overflow.finalize(box.state.size)
  if box.computed{"position"} notin PositionStaticLike:
    lctx.popPositioned(box.state.overflow, box.state.size)

# Inner layout for boxes that establish a new block formatting context.
# Returns the bottom margin for the box, collapsed with the appropriate
# margins from its descendants.
proc layoutRootBlock(lctx: LayoutContext; box: BlockBox; offset: Offset;
    sizes: ResolvedSizes): LayoutUnit =
  var bctx = BlockContext(lctx: lctx)
  box.state = BoxLayoutState(
    offset: offset(x = offset.x + sizes.margin.left, y = offset.y)
  )
  bctx.layout(box, sizes)
  assert bctx.unpositionedFloats.len == 0
  let marginBottom = bctx.marginTodo.sum()
  # If the highest float edge is higher than the box itself, set that as
  # the box height.
  box.state.size.h = max(box.state.size.h, bctx.maxFloatHeight - marginBottom)
  return marginBottom

proc initBlockPositionStates(state: var BlockState; bctx: var BlockContext;
    box: BlockBox) =
  let prevBps = bctx.ancestorsHead
  bctx.ancestorsHead = BlockPositionState(
    box: box,
    offset: state.offset,
    resolved: bctx.parentBps == nil
  )
  if prevBps != nil:
    prevBps.next = bctx.ancestorsHead
  if bctx.parentBps != nil:
    bctx.ancestorsHead.offset += bctx.parentBps.offset
    # If parentBps is not nil, then our starting position is not in a new
    # BFC -> we must add it to our BFC offset.
    bctx.ancestorsHead.offset += box.state.offset
  if bctx.marginTarget == nil:
    bctx.marginTarget = bctx.ancestorsHead
  state.initialMarginTarget = bctx.marginTarget
  state.initialTargetOffset = bctx.marginTarget.offset
  if bctx.parentBps == nil:
    # We have just established a new BFC. Resolve the margins instantly.
    bctx.marginTarget = nil
  state.prevParentBps = bctx.parentBps
  bctx.parentBps = bctx.ancestorsHead
  state.initialParentOffset = bctx.parentBps.offset

func isParentResolved(state: BlockState; bctx: BlockContext): bool =
  return bctx.marginTarget != state.initialMarginTarget or
    state.prevParentBps != nil and state.prevParentBps.resolved

# Layout a block-level child inside the same block formatting context as
# its parent.
# Returns the block's outer size.
# Stores its resolved size data in `sizes'.
proc layoutBlockChild(state: var BlockState; bctx: var BlockContext;
    child: BlockBox; sizes: var ResolvedSizes): Size =
  sizes = bctx.lctx.resolveBlockSizes(state.space, child.computed)
  bctx.marginTodo.append(sizes.margin.top)
  child.state = BoxLayoutState(offset: offset(x = sizes.margin.left, y = 0))
  child.state.offset += state.offset
  bctx.layout(child, sizes)
  bctx.marginTodo.append(sizes.margin.bottom)
  return size(
    w = child.outerSize(dtHorizontal, sizes),
    # delta y is difference between old and new offsets (margin-top),
    # plus height.
    h = child.state.offset.y - state.offset.y + child.state.size.h
  )

# Outer layout for block-level children that establish a BFC.
# Returns the block's outer size.
# Stores its resolved size data in `sizes'.
# For floats, the margin offset is returned in marginOffset.
proc layoutBlockChildBFC(state: var BlockState; bctx: var BlockContext;
    child: BlockBox; sizes: var ResolvedSizes; space: var AvailableSpace):
    Size =
  assert child.computed{"position"} != PositionAbsolute
  let lctx = bctx.lctx
  var outerHeight: LayoutUnit
  if child.computed{"float"} == FloatNone:
    sizes = lctx.resolveBlockSizes(state.space, child.computed)
    var marginBottom = bctx.lctx.layoutRootBlock(child, state.offset, sizes)
    bctx.marginTodo.append(sizes.margin.top)
    bctx.flushMargins(child)
    bctx.positionFloats()
    bctx.marginTodo.append(sizes.margin.bottom)
    if child.computed{"clear"} != ClearNone:
      state.offset.y.clearFloats(bctx, bctx.bfcOffset.y,
        child.computed{"clear"})
    if bctx.exclusions.len > 0:
      # From the standard (abridged):
      #
      # > The border box of an element that establishes a new BFC must
      # > not overlap the margin box of any floats in the same BFC. If
      # > necessary, implementations should clear the said element, but
      # > may place it adjacent to such floats if there is sufficient
      # > space. CSS2 does not define when a UA may put said element
      # > next to the float.
      #
      # ...thanks for nothing. So here's what we do:
      #
      # * run a normal pass
      # * place the longest word (i.e. xminwidth) somewhere
      # * run another pass with the placement we got
      #
      # Some browsers prefer to try again until they find enough
      # available space; I won't do that because it's unnecessarily
      # complex and slow. (Maybe one day, when layout is faster...)
      #
      # Note that this does not apply to absolutely positioned elements,
      # as those ignore floats.
      let pbfcOffset = bctx.bfcOffset
      let bfcOffset = offset(
        x = pbfcOffset.x + child.state.offset.x,
        y = max(pbfcOffset.y + child.state.offset.y, bctx.clearOffset)
      )
      let minSize = size(w = child.state.xminwidth, h = bctx.lctx.attrs.ppl)
      var outw: LayoutUnit
      let offset = bctx.findNextBlockOffset(bfcOffset, minSize, state.space,
        outw)
      space = availableSpace(w = stretch(outw), h = state.space.h)
      sizes = lctx.resolveBlockSizes(space, child.computed)
      marginBottom = lctx.layoutRootBlock(child, offset - pbfcOffset, sizes)
    # delta y is difference between old and new offsets (margin-top
    # plus any movement caused by floats), sum of margin todo in bctx
    # (margin-bottom) + height.
    outerHeight = child.state.offset.y - state.offset.y + child.state.size.h +
      marginBottom
  else:
    sizes = lctx.resolveFloatSizes(space, child.computed)
    let marginBottom = bctx.lctx.layoutRootBlock(child, state.offset, sizes)
    child.state.offset.y += sizes.margin.top
    if state.isParentResolved(bctx):
      # If parent offset has been resolved, use marginTodo in this
      # float's initial offset.
      child.state.offset.y += bctx.marginTodo.sum()
    outerHeight = child.outerSize(dtVertical, sizes) + marginBottom
  return size(
    w = child.outerSize(dtHorizontal, sizes),
    h = outerHeight
  )

# Note: this does not include display types that cannot appear as block
# children.
func establishesBFC(computed: CSSValues): bool =
  return computed{"float"} != FloatNone or
    computed{"display"} in {DisplayFlowRoot, DisplayTable, DisplayTableWrapper,
      DisplayFlex} or
    computed{"overflow"} notin {OverflowVisible, OverflowClip}
    #TODO contain, grid, multicol, column-span

# Layout and place all children in the block box.
# Box placement must occur during this pass, since child box layout in the
# same block formatting context depends on knowing where the box offset is
# (because of floats).
proc layoutBlockChildren(state: var BlockState; bctx: var BlockContext;
    parent: BlockBox) =
  var textAlign = parent.computed{"text-align"}
  if not state.space.w.isDefinite():
    # Aligning min-content or max-content is nonsensical.
    textAlign = TextAlignLeft
  for child in parent.children:
    if child.computed{"position"} in {PositionAbsolute, PositionFixed}:
      # Delay this block's layout until its parent's dimensions are
      # actually known.
      # We want to get the child to a Y position where it would have
      # been placed had it not been absolutely positioned.
      #
      # Like with floats, we must consider both the case where the
      # parent's position is resolved, and the case where it isn't.
      # Here our job is much easier in the unresolved case: subsequent
      # children's layout doesn't depend on our position; so we can just
      # defer margin resolution to the parent.
      var offset = state.offset
      if bctx.marginTarget != state.initialMarginTarget:
        offset.y += bctx.marginTodo.sum()
      bctx.lctx.queueAbsolute(child, offset)
      continue
    var sizes: ResolvedSizes
    var space = state.space
    let outerSize = if child.computed.establishesBFC():
      state.layoutBlockChildBFC(bctx, child, sizes, space)
    else:
      state.layoutBlockChild(bctx, child, sizes)
    state.xminwidth = max(state.xminwidth, child.state.xminwidth)
    if child.computed{"float"} == FloatNone:
      # Assume we will stretch to the maximum width, and re-layout if
      # this assumption turns out to be wrong.
      if parent.computed{"text-align"} == TextAlignChaCenter:
        child.state.offset.x += max(state.space.w.u div 2 -
          child.state.size.w div 2, 0)
      elif textAlign == TextAlignChaRight:
        child.state.offset.x += max(state.space.w.u - child.state.size.w -
          sizes.margin.right, 0)
      if child.computed{"position"} == PositionRelative:
        state.relativeChildren.add(child)
      state.maxChildWidth = max(state.maxChildWidth, outerSize.w)
      state.offset.y += outerSize.h
      parent.applyOverflowDimensions(child)
    elif state.space.w.t == scFitContent:
      # Float position depends on the available width, but in this case
      # the parent width is not known.
      #
      # Set the "re-layout" flag, and skip this box.
      # (If child boxes with fit-content have floats, those will be
      # re-layouted too first, so we do not have to consider those here.)
      state.needsReLayout = true
      # Since we emulate max-content here, the float will not contribute to
      # maxChildWidth in this iteration; instead, its outer width will be
      # summed up in totalFloatWidth and added to maxChildWidth in
      # initReLayout.
      state.totalFloatWidth += outerSize.w
    else:
      state.maxChildWidth = max(state.maxChildWidth, outerSize.w)
      # Two cases exist:
      # a) The float cannot be positioned, because `box' has not resolved
      #    its y offset yet. (e.g. if float comes before the first child,
      #    we do not know yet if said child will move our y offset with a
      #    margin-top value larger than ours.)
      #    In this case we put it in unpositionedFloats, and defer positioning
      #    until our y offset is resolved.
      # b) `box' has resolved its y offset, so the float can already
      #    be positioned.
      # We check whether our y offset has been positioned as follows:
      # * save marginTarget in BlockState at layoutBlock's start
      # * if our saved marginTarget and bctx's marginTarget no longer point
      #   to the same object, that means our (or an ancestor's) offset has
      #   been resolved, i.e. we can position floats already.
      let marginOffset = sizes.margin.startOffset()
      if bctx.marginTarget != state.initialMarginTarget:
        # y offset resolved
        bctx.positionFloat(child, state.space, outerSize, marginOffset,
          bctx.parentBps.offset)
      else:
        bctx.unpositionedFloats.add(UnpositionedFloat(
          space: state.space,
          parentBps: bctx.parentBps,
          box: child,
          marginOffset: marginOffset,
          outerSize: outerSize,
          parentBox: parent
        ))

# Unlucky path, where we have floating blocks and a fit-content width.
# Reset marginTodo & the starting offset, and stretch the box to the
# max child width.
proc initReLayout(state: var BlockState; bctx: var BlockContext;
    box: BlockBox; sizes: ResolvedSizes) =
  bctx.marginTodo = state.oldMarginTodo
  # Note: we do not reset our own BlockPositionState's offset; we assume it
  # has already been resolved in the previous pass.
  # (If not, it won't be resolved in this pass either, so the following code
  # does not really change anything.)
  bctx.parentBps.next = nil
  if state.initialMarginTarget != bctx.marginTarget:
    # Reset the initial margin target to its previous state, and then set
    # it as the marginTarget again.
    # Two solutions exist:
    # a) Store the initial margin target offset, then restore it here. Seems
    #    clean, but it would require a linked list traversal to update all
    #    child margin positions.
    # b) Re-use the previous margin target offsets; they are guaranteed
    #    to remain the same, because out-of-flow elements (like floats) do not
    #    participate in margin resolution. We do this by setting the margin
    #    target to a dummy object, which is a small price to pay compared
    #    to solution a).
    bctx.marginTarget = BlockPositionState(
      # Use initialTargetOffset to emulate the BFC positioning of the
      # previous pass.
      offset: state.initialTargetOffset
    )
    # Also set ancestorsHead as the dummy object, so next elements are
    # chained to that.
    bctx.ancestorsHead = bctx.marginTarget
  bctx.exclusions.setLen(state.oldExclusionsLen)
  state.offset = offset(x = sizes.padding.left, y = sizes.padding.top)
  box.applyWidth(sizes, state.maxChildWidth + state.totalFloatWidth)
  # Positioning of the children will differ now; reset the overflow offsets.
  for dim in DimensionType:
    box.state.overflow[dim] = Span()
  state.space.w = stretch(box.state.size.w)

proc layoutBlock(bctx: var BlockContext; box: BlockBox; sizes: ResolvedSizes) =
  let lctx = bctx.lctx
  if box.computed{"position"} notin PositionStaticLike:
    lctx.pushPositioned()
  var state = BlockState(
    offset: offset(x = sizes.padding.left, y = sizes.padding.top),
    space: sizes.space,
    oldMarginTodo: bctx.marginTodo,
    oldExclusionsLen: bctx.exclusions.len
  )
  state.initBlockPositionStates(bctx, box)
  state.layoutBlockChildren(bctx, box)
  if box.computed{"text-align"} in {TextAlignChaCenter, TextAlignChaRight} and
      state.space.w.t == scFitContent and
      state.space.w.u != state.maxChildWidth:
    # We *could* handle this in a separate pass for a marginal speed
    # improvement in this edge case, but this is prettier.
    state.needsReLayout = true
  if state.needsReLayout:
    state.initReLayout(bctx, box, sizes)
    state.layoutBlockChildren(bctx, box)
  box.applyBaseline()
  # Set xminwidth now, so that it can be clamped by minWidthClamp.
  box.state.xminwidth = state.xminwidth
  # Apply width, and height. For height, temporarily remove padding we have
  # applied before so that percentage resolution works correctly.
  box.applyWidth(sizes, state.maxChildWidth, state.space)
  box.applyHeight(sizes, state.offset.y - sizes.padding.top)
  # `position: relative' percentages can now be resolved.
  for child in state.relativeChildren:
    lctx.positionRelative(box, child)
  # Add padding; we cannot do this further up without influencing positioning.
  box.applyPadding(sizes.padding)
  if state.isParentResolved(bctx):
    # Our offset has already been resolved, ergo any margins in marginTodo will
    # be passed onto the next box. Set marginTarget to nil, so that if we (or
    # one of our ancestors) were still set as a marginTarget, we no longer are.
    bctx.positionFloats()
    bctx.marginTarget = nil
  # All children are positioned now; finalize our overflow dimensions.
  box.state.overflow.finalize(box.state.size)
  # Reset parentBps to the previous node.
  bctx.parentBps = state.prevParentBps
  if box.computed{"position"} notin PositionStaticLike:
    lctx.popPositioned(box.state.overflow, box.state.size)

# 1st pass: build tree

proc newMarkerBox(computed: CSSValues; listItemCounter: int):
    InlineFragment =
  let computed = computed.inheritProperties()
  computed{"display"} = DisplayInline
  # Use pre, so the space at the end of the default markers isn't ignored.
  computed{"white-space"} = WhitespacePre
  let s = computed{"list-style-type"}.listMarker(listItemCounter)
  return InlineFragment(
    t: iftText,
    computed: computed,
    text: newStyledText(s)
  )

type InnerBlockContext = object
  styledNode: StyledNode
  outer: BlockBox
  lctx: LayoutContext
  anonRow: BlockBox
  anonTableWrapper: BlockBox
  inlineAnonRow: BlockBox
  inlineAnonTableWrapper: BlockBox
  quoteLevel: int
  listItemCounter: int
  listItemReset: bool
  parent: ptr InnerBlockContext
  inlineStack: seq[StyledNode]
  inlineStackFragments: seq[InlineFragment]
  # if inline is not nil, then inline.children.len > 0
  inline: InlineFragment

proc flushTable(ctx: var InnerBlockContext)

proc flushInlineGroup(ctx: var InnerBlockContext) =
  if ctx.inline != nil:
    ctx.flushTable()
    let computed = ctx.outer.computed.inheritProperties()
    computed{"display"} = DisplayBlock
    let box = BlockBox(computed: computed, inline: ctx.inline)
    ctx.outer.children.add(box)
    ctx.inline = nil

# Don't build empty anonymous inline blocks between block boxes
func canBuildAnonInline(ctx: InnerBlockContext; computed: CSSValues;
    str: string): bool =
  return ctx.inline != nil and ctx.inline.children.len > 0 or
    computed.whitespacepre or not str.onlyWhitespace()

# Forward declarations
proc buildBlock(ctx: var InnerBlockContext)
proc buildTable(ctx: var InnerBlockContext)
proc buildFlex(ctx: var InnerBlockContext)
proc buildInlineBoxes(ctx: var InnerBlockContext; styledNode: StyledNode;
  computed: CSSValues)
proc buildTableRowGroup(parent: var InnerBlockContext; styledNode: StyledNode;
  computed: CSSValues): BlockBox
proc buildTableRow(parent: var InnerBlockContext; styledNode: StyledNode;
  computed: CSSValues): BlockBox
proc buildTableCell(parent: var InnerBlockContext; styledNode: StyledNode;
  computed: CSSValues): BlockBox
proc buildTableCaption(parent: var InnerBlockContext; styledNode: StyledNode;
  computed: CSSValues): BlockBox
proc newInnerBlockContext(styledNode: StyledNode; box: BlockBox;
  lctx: LayoutContext; parent: ptr InnerBlockContext): InnerBlockContext
proc pushInline(ctx: var InnerBlockContext; fragment: InlineFragment)
proc pushInlineBlock(ctx: var InnerBlockContext; styledNode: StyledNode;
  computed: CSSValues)

func toTableWrapper(display: CSSDisplay): CSSDisplay =
  if display == DisplayTable:
    return DisplayTableWrapper
  assert display == DisplayInlineTable
  return DisplayInlineTableWrapper

proc createAnonTable(ctx: var InnerBlockContext; computed: CSSValues):
    BlockBox =
  let inline = ctx.inlineStack.len > 0
  if not inline and ctx.anonTableWrapper == nil or
      inline and ctx.inlineAnonTableWrapper == nil:
    let inherited = computed.inheritProperties()
    let (outerComputed, innerComputed) = inherited.splitTable()
    outerComputed{"display"} = if inline:
      DisplayInlineTableWrapper
    else:
      DisplayTableWrapper
    let innerTable = BlockBox(computed: innerComputed)
    let box = BlockBox(
      computed: outerComputed,
      children: @[innerTable]
    )
    if inline:
      ctx.inlineAnonTableWrapper = box
    else:
      ctx.anonTableWrapper = box
    return box
  if inline:
    return ctx.inlineAnonTableWrapper
  return ctx.anonTableWrapper

proc createAnonRow(ctx: var InnerBlockContext): BlockBox =
  let inline = ctx.inlineStack.len > 0
  if not inline and ctx.anonRow == nil or
      inline and ctx.inlineAnonRow == nil:
    let wrapperVals = ctx.outer.computed.inheritProperties()
    wrapperVals{"display"} = DisplayTableRow
    let box = BlockBox(computed: wrapperVals)
    if inline:
      ctx.inlineAnonRow = box
    else:
      ctx.anonRow = box
    return box
  if inline:
    return ctx.inlineAnonRow
  return ctx.anonRow

proc flushTableRow(ctx: var InnerBlockContext) =
  if ctx.anonRow != nil:
    if ctx.outer.computed{"display"} in ProperTableRowParent:
      ctx.outer.children.add(ctx.anonRow)
    else:
      let anonTableWrapper = ctx.createAnonTable(ctx.outer.computed)
      anonTableWrapper.children[0].children.add(ctx.anonRow)
    ctx.anonRow = nil

proc flushTable(ctx: var InnerBlockContext) =
  ctx.flushTableRow()
  if ctx.anonTableWrapper != nil:
    ctx.outer.children.add(ctx.anonTableWrapper)
    ctx.anonTableWrapper = nil

proc flushInlineTableRow(ctx: var InnerBlockContext) =
  if ctx.inlineAnonRow != nil:
    # There is no way an inline anonymous row could be a child of an inline
    # table, since inline tables still act like blocks inside.
    let anonTableWrapper = ctx.createAnonTable(ctx.outer.computed)
    anonTableWrapper.children[0].children.add(ctx.inlineAnonRow)
    ctx.inlineAnonRow = nil

proc flushInlineTable(ctx: var InnerBlockContext) =
  ctx.flushInlineTableRow()
  if ctx.inlineAnonTableWrapper != nil:
    ctx.pushInline(InlineFragment(
      t: iftBox,
      computed: ctx.inlineAnonTableWrapper.computed.inheritProperties(),
      box: ctx.inlineAnonTableWrapper
    ))
    ctx.inlineAnonTableWrapper = nil

proc iflush(ctx: var InnerBlockContext) =
  ctx.inlineStackFragments.setLen(0)

proc flushInherit(ctx: var InnerBlockContext) =
  if ctx.parent != nil:
    if not ctx.listItemReset:
      ctx.parent.listItemCounter = ctx.listItemCounter
    ctx.parent.quoteLevel = ctx.quoteLevel

proc flush(ctx: var InnerBlockContext) =
  ctx.flushInlineGroup()
  ctx.flushTable()
  ctx.flushInherit()

proc addInlineRoot(ctx: var InnerBlockContext; box: InlineFragment) =
  if ctx.inline == nil:
    ctx.inline = InlineFragment(
      t: iftParent,
      computed: ctx.lctx.myRootProperties,
      children: @[box]
    )
  else:
    ctx.inline.children.add(box)

proc reconstructInlineParents(ctx: var InnerBlockContext) =
  if ctx.inlineStackFragments.len == 0:
    var parent = InlineFragment(
      t: iftParent,
      computed: ctx.inlineStack[0].computed,
      node: ctx.inlineStack[0]
    )
    ctx.inlineStackFragments.add(parent)
    ctx.addInlineRoot(parent)
    for i in 1 ..< ctx.inlineStack.len:
      let node = ctx.inlineStack[i]
      let child = InlineFragment(
        t: iftParent,
        computed: node.computed,
        node: node
      )
      parent.children.add(child)
      ctx.inlineStackFragments.add(child)
      parent = child

proc buildSomeBlock(ctx: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSValues): BlockBox =
  let box = BlockBox(computed: computed, node: styledNode)
  var childCtx = newInnerBlockContext(styledNode, box, ctx.lctx, addr ctx)
  case computed{"display"}
  of DisplayBlock, DisplayFlowRoot, DisplayInlineBlock: childCtx.buildBlock()
  of DisplayFlex, DisplayInlineFlex: childCtx.buildFlex()
  of DisplayTable, DisplayInlineTable: childCtx.buildTable()
  else: discard
  return box

# Note: these also pop
proc pushBlock(ctx: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSValues) =
  if (computed{"position"} == PositionAbsolute or
        computed{"float"} != FloatNone) and
      (ctx.inline != nil or ctx.inlineStack.len > 0):
    ctx.pushInlineBlock(styledNode, computed)
  else:
    ctx.iflush()
    ctx.flush()
    let box = ctx.buildSomeBlock(styledNode, computed)
    ctx.outer.children.add(box)

proc pushInline(ctx: var InnerBlockContext; fragment: InlineFragment) =
  if ctx.inlineStack.len == 0:
    ctx.addInlineRoot(fragment)
  else:
    ctx.reconstructInlineParents()
    ctx.inlineStackFragments[^1].children.add(fragment)

proc pushInlineText(ctx: var InnerBlockContext; computed: CSSValues;
    parent, node: StyledNode) =
  ctx.pushInline(InlineFragment(
    t: iftText,
    computed: computed,
    node: parent,
    text: node
  ))

proc pushInlineBlock(ctx: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSValues) =
  ctx.pushInline(InlineFragment(
    t: iftBox,
    computed: computed.inheritProperties(),
    node: styledNode,
    box: ctx.buildSomeBlock(styledNode, computed)
  ))

proc pushListItem(ctx: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSValues) =
  ctx.iflush()
  ctx.flush()
  inc ctx.listItemCounter
  let marker = newMarkerBox(computed, ctx.listItemCounter)
  let position = computed{"list-style-position"}
  let content = BlockBox(computed: computed, node: styledNode)
  var contentCtx = newInnerBlockContext(styledNode, content, ctx.lctx, addr ctx)
  case position
  of ListStylePositionOutside:
    contentCtx.buildBlock()
    content.computed = content.computed.copyProperties()
    content.computed{"display"} = DisplayBlock
    let markerComputed = marker.computed.copyProperties()
    markerComputed{"display"} = DisplayBlock
    let marker = BlockBox(
      computed: marker.computed,
      inline: marker
    )
    let wrapper = BlockBox(computed: computed, children: @[marker, content])
    ctx.outer.children.add(wrapper)
  of ListStylePositionInside:
    contentCtx.pushInline(marker)
    contentCtx.buildBlock()
    ctx.outer.children.add(content)

proc pushTableRow(ctx: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSValues) =
  let child = ctx.buildTableRow(styledNode, computed)
  if ctx.inlineStack.len == 0:
    ctx.iflush()
    ctx.flushInlineGroup()
    ctx.flushTableRow()
  else:
    ctx.flushInlineTableRow()
  if ctx.inlineStack.len == 0 and
      ctx.outer.computed{"display"} in ProperTableRowParent:
    ctx.outer.children.add(child)
  else:
    let anonTableWrapper = ctx.createAnonTable(ctx.outer.computed)
    anonTableWrapper.children[0].children.add(child)

proc pushTableRowGroup(ctx: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSValues) =
  let child = ctx.buildTableRowGroup(styledNode, computed)
  if ctx.inlineStack.len == 0:
    ctx.iflush()
    ctx.flushInlineGroup()
    ctx.flushTableRow()
  else:
    ctx.flushInlineTableRow()
  if ctx.inlineStack.len == 0 and
      ctx.outer.computed{"display"} in {DisplayTable, DisplayInlineTable}:
    ctx.outer.children.add(child)
  else:
    ctx.flushTableRow()
    let anonTableWrapper = ctx.createAnonTable(ctx.outer.computed)
    anonTableWrapper.children[0].children.add(child)

proc pushTableCell(ctx: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSValues) =
  let child = ctx.buildTableCell(styledNode, computed)
  if ctx.inlineStack.len == 0 and
      ctx.outer.computed{"display"} == DisplayTableRow:
    ctx.iflush()
    ctx.flushInlineGroup()
    ctx.outer.children.add(child)
  else:
    let anonRow = ctx.createAnonRow()
    anonRow.children.add(child)

proc pushTableCaption(ctx: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSValues) =
  ctx.iflush()
  ctx.flushInlineGroup()
  ctx.flushTableRow()
  let child = ctx.buildTableCaption(styledNode, computed)
  if ctx.outer.computed{"display"} in {DisplayTable, DisplayInlineTable}:
    ctx.outer.children.add(child)
  else:
    let anonTableWrapper = ctx.createAnonTable(ctx.outer.computed)
    # only add first caption
    if anonTableWrapper.children.len == 1:
      anonTableWrapper.children.add(child)

proc buildFromElem(ctx: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSValues) =
  case computed{"display"}
  of DisplayBlock, DisplayFlowRoot, DisplayFlex, DisplayTable:
    ctx.pushBlock(styledNode, computed)
  of DisplayInlineBlock, DisplayInlineTable, DisplayInlineFlex:
    ctx.pushInlineBlock(styledNode, computed)
  of DisplayListItem:
    ctx.pushListItem(styledNode, computed)
  of DisplayInline:
    ctx.buildInlineBoxes(styledNode, computed)
  of DisplayTableRow:
    ctx.pushTableRow(styledNode, computed)
  of DisplayTableRowGroup, DisplayTableHeaderGroup, DisplayTableFooterGroup:
    ctx.pushTableRowGroup(styledNode, computed)
  of DisplayTableCell:
    ctx.pushTableCell(styledNode, computed)
  of DisplayTableCaption:
    ctx.pushTableCaption(styledNode, computed)
  of DisplayTableColumn: discard #TODO
  of DisplayTableColumnGroup: discard #TODO
  of DisplayNone: discard
  of DisplayTableWrapper, DisplayInlineTableWrapper: assert false

proc buildReplacement(ctx: var InnerBlockContext; child, parent: StyledNode;
    computed: CSSValues) =
  case child.content.t
  of ContentNone: assert false # unreachable for `content'
  of ContentOpenQuote:
    let quotes = parent.computed{"quotes"}
    var text: string = ""
    if quotes.qs.len > 0:
      text = quotes.qs[min(ctx.quoteLevel, quotes.qs.high)].s
    elif quotes.auto:
      text = quoteStart(ctx.quoteLevel)
    else: return
    let node = newStyledText(text)
    ctx.pushInlineText(computed, parent, node)
    inc ctx.quoteLevel
  of ContentCloseQuote:
    if ctx.quoteLevel > 0: dec ctx.quoteLevel
    let quotes = parent.computed{"quotes"}
    let s = if quotes.qs.len > 0:
      quotes.qs[min(ctx.quoteLevel, quotes.qs.high)].e
    elif quotes.auto:
      quoteEnd(ctx.quoteLevel)
    else:
      return
    let text = newStyledText(s)
    ctx.pushInlineText(computed, parent, text)
  of ContentNoOpenQuote:
    inc ctx.quoteLevel
  of ContentNoCloseQuote:
    if ctx.quoteLevel > 0: dec ctx.quoteLevel
  of ContentString:
    let text = newStyledText(child.content.s)
    ctx.pushInlineText(computed, parent, text)
  of ContentImage:
    if child.content.bmp != nil:
      ctx.pushInline(InlineFragment(
        t: iftBitmap,
        computed: parent.computed,
        node: parent,
        bmp: child.content.bmp
      ))
    else:
      ctx.pushInlineText(computed, parent, ctx.lctx.imgText)
  of ContentVideo:
    ctx.pushInlineText(computed, parent, ctx.lctx.videoText)
  of ContentAudio:
    ctx.pushInlineText(computed, parent, ctx.lctx.audioText)
  of ContentNewline:
    ctx.pushInline(InlineFragment(
      t: iftNewline,
      computed: computed,
      node: child
    ))

proc buildInlineBoxes(ctx: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSValues) =
  let parent = InlineFragment(
    t: iftParent,
    computed: computed,
    splitType: {stSplitStart}
  )
  if ctx.inlineStack.len == 0:
    ctx.addInlineRoot(parent)
  else:
    ctx.reconstructInlineParents()
    ctx.inlineStackFragments[^1].children.add(parent)
  ctx.inlineStack.add(styledNode)
  ctx.inlineStackFragments.add(parent)
  for child in styledNode.children:
    case child.t
    of stElement:
      ctx.buildFromElem(child, child.computed)
    of stText:
      ctx.flushInlineTable()
      ctx.pushInlineText(computed, styledNode, child)
    of stReplacement:
      ctx.flushInlineTable()
      ctx.buildReplacement(child, styledNode, computed)
  ctx.reconstructInlineParents()
  ctx.flushInlineTable()
  let fragment = ctx.inlineStackFragments.pop()
  fragment.splitType.incl(stSplitEnd)
  ctx.inlineStack.setLen(ctx.inlineStack.high)

proc newInnerBlockContext(styledNode: StyledNode; box: BlockBox;
    lctx: LayoutContext; parent: ptr InnerBlockContext): InnerBlockContext =
  assert box.computed{"display"} != DisplayInline
  var ctx = InnerBlockContext(
    styledNode: styledNode,
    outer: box,
    lctx: lctx,
    parent: parent
  )
  if parent != nil:
    ctx.listItemCounter = parent[].listItemCounter
    ctx.quoteLevel = parent[].quoteLevel
  for reset in styledNode.computed{"counter-reset"}:
    if reset.name == "list-item":
      ctx.listItemCounter = reset.num
      ctx.listItemReset = true
  return ctx

proc buildInnerBlock(ctx: var InnerBlockContext) =
  let inlineComputed = ctx.outer.computed.inheritProperties()
  for child in ctx.styledNode.children:
    case child.t
    of stElement:
      ctx.buildFromElem(child, child.computed)
    of stText:
      if ctx.canBuildAnonInline(ctx.outer.computed, child.textData):
        ctx.pushInlineText(inlineComputed, ctx.styledNode, child)
    of stReplacement:
      ctx.buildReplacement(child, ctx.styledNode, inlineComputed)
  ctx.iflush()

proc buildBlock(ctx: var InnerBlockContext) =
  ctx.buildInnerBlock()
  # Flush anonymous tables here, to avoid setting inline layout with tables.
  ctx.flushTable()
  ctx.flushInherit() # (flush here, because why not)
  # Avoid unnecessary anonymous block boxes. This also helps set our layout to
  # inline even if no inner anonymous block was built.
  if ctx.outer.children.len == 0:
    ctx.outer.inline = if ctx.inline != nil:
      ctx.inline
    else:
      InlineFragment(
        t: iftParent,
        computed: ctx.lctx.myRootProperties
      )
    ctx.inline = nil
  ctx.flushInlineGroup()

proc buildInnerFlex(ctx: var InnerBlockContext) =
  let inlineComputed = ctx.outer.computed.inheritProperties()
  for child in ctx.styledNode.children:
    case child.t
    of stElement:
      let display = child.computed{"display"}.blockify()
      let computed = if display != child.computed{"display"}:
        let computed = child.computed.copyProperties()
        computed{"display"} = display
        computed
      else:
        child.computed
      ctx.buildFromElem(child, computed)
    of stText:
      if ctx.canBuildAnonInline(ctx.outer.computed, child.textData):
        ctx.pushInlineText(inlineComputed, ctx.styledNode, child)
    of stReplacement:
      ctx.buildReplacement(child, ctx.styledNode, inlineComputed)
  ctx.iflush()

proc buildFlex(ctx: var InnerBlockContext) =
  ctx.buildInnerFlex()
  # Flush anonymous tables here, to avoid setting inline layout with tables.
  ctx.flushTable()
  # (flush here, because why not)
  ctx.flushInherit()
  ctx.flushInlineGroup()
  assert ctx.outer.inline == nil
  const FlexReverse = {FlexDirectionRowReverse, FlexDirectionColumnReverse}
  if ctx.outer.computed{"flex-direction"} in FlexReverse:
    ctx.outer.children.reverse()

proc buildTableCell(parent: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSValues): BlockBox =
  let box = BlockBox(node: styledNode, computed: computed)
  var ctx = newInnerBlockContext(styledNode, box, parent.lctx, addr parent)
  ctx.buildInnerBlock()
  ctx.flush()
  return box

proc buildTableRowChildWrappers(box: BlockBox) =
  var wrapperVals: CSSValues = nil
  for child in box.children:
    if child.computed{"display"} != DisplayTableCell:
      wrapperVals = box.computed.inheritProperties()
      wrapperVals{"display"} = DisplayTableCell
      break
  if wrapperVals != nil:
    # fixup row: put wrappers around runs of misparented children
    var children = newSeqOfCap[BlockBox](box.children.len)
    var wrapper: BlockBox = nil
    for child in box.children:
      if child.computed{"display"} != DisplayTableCell:
        if wrapper == nil:
          wrapper = BlockBox(computed: wrapperVals)
          children.add(wrapper)
        wrapper.children.add(child)
      else:
        wrapper = nil
        children.add(child)
    box.children = children

proc buildTableRow(parent: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSValues): BlockBox =
  let box = BlockBox(node: styledNode, computed: computed)
  var ctx = newInnerBlockContext(styledNode, box, parent.lctx, addr parent)
  ctx.buildInnerBlock()
  ctx.flush()
  box.buildTableRowChildWrappers()
  return box

proc buildTableRowGroupChildWrappers(box: BlockBox) =
  var wrapperVals: CSSValues = nil
  for child in box.children:
    if child.computed{"display"} != DisplayTableRow:
      wrapperVals = box.computed.inheritProperties()
      wrapperVals{"display"} = DisplayTableRow
      break
  if wrapperVals != nil:
    # fixup row group: put wrappers around runs of misparented children
    var wrapper: BlockBox = nil
    var children = newSeqOfCap[BlockBox](box.children.len)
    for child in box.children:
      if child.computed{"display"} != DisplayTableRow:
        if wrapper == nil:
          wrapper = BlockBox(computed: wrapperVals, children: @[child])
          children.add(wrapper)
        wrapper.children.add(child)
      else:
        if wrapper != nil:
          wrapper.buildTableRowChildWrappers()
          wrapper = nil
        children.add(child)
    if wrapper != nil:
      wrapper.buildTableRowChildWrappers()
    box.children = children

proc buildTableRowGroup(parent: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSValues): BlockBox =
  let box = BlockBox(node: styledNode, computed: computed)
  var ctx = newInnerBlockContext(styledNode, box, parent.lctx, addr parent)
  ctx.buildInnerBlock()
  ctx.flush()
  box.buildTableRowGroupChildWrappers()
  return box

proc buildTableCaption(parent: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSValues): BlockBox =
  let box = BlockBox(node: styledNode, computed: computed)
  var ctx = newInnerBlockContext(styledNode, box, parent.lctx, addr parent)
  ctx.buildInnerBlock()
  ctx.flush()
  return box

proc buildTableChildWrappers(box: BlockBox; computed: CSSValues) =
  let innerTable = BlockBox(computed: computed, node: box.node)
  let wrapperVals = box.computed.inheritProperties()
  wrapperVals{"display"} = DisplayTableRow
  var caption: BlockBox = nil
  var wrapper: BlockBox = nil
  for child in box.children:
    if child.computed{"display"} in ProperTableChild:
      if wrapper != nil:
        wrapper.buildTableRowChildWrappers()
        wrapper = nil
      innerTable.children.add(child)
    elif child.computed{"display"} == DisplayTableCaption:
      if caption == nil:
        caption = child
    else:
      if wrapper == nil:
        wrapper = BlockBox(computed: wrapperVals)
        innerTable.children.add(wrapper)
      wrapper.children.add(child)
  if wrapper != nil:
    wrapper.buildTableRowChildWrappers()
  box.children = @[innerTable]
  if caption != nil:
    box.children.add(caption)

proc buildTable(ctx: var InnerBlockContext) =
  ctx.buildInnerBlock()
  ctx.flush()
  let (outerComputed, innerComputed) = ctx.outer.computed.splitTable()
  ctx.outer.computed = outerComputed
  outerComputed{"display"} = outerComputed{"display"}.toTableWrapper()
  ctx.outer.buildTableChildWrappers(innerComputed)

proc layout*(root: StyledNode; attrsp: ptr WindowAttributes): BlockBox =
  let space = availableSpace(
    w = stretch(attrsp[].widthPx),
    h = stretch(attrsp[].heightPx)
  )
  let lctx = LayoutContext(
    attrsp: attrsp,
    cellSize: size(w = attrsp.ppc, h = attrsp.ppl),
    positioned: @[PositionedItem(), PositionedItem()],
    myRootProperties: rootProperties(),
    imgText: newStyledText("[img]"),
    videoText: newStyledText("[video]"),
    audioText: newStyledText("[audio]")
  )
  let box = BlockBox(computed: root.computed, node: root)
  var ctx = newInnerBlockContext(root, box, lctx, nil)
  ctx.buildBlock()
  let sizes = lctx.resolveBlockSizes(space, box.computed)
  # the bottom margin is unused.
  discard lctx.layoutRootBlock(box, offset(x = 0, y = 0), sizes)
  var size = size(w = attrsp[].widthPx, h = attrsp[].heightPx)
  # Last absolute layer.
  lctx.popPositioned(box.state.overflow, size)
  # Fixed containing block.
  # The idea is to move fixed boxes to the real edges of the page,
  # so that they do not overlap with other boxes *and* we don't have
  # to move them on scroll. It's still not compatible with what desktop
  # browsers do, but the alternative would completely break search (and
  # slow down the renderer to a crawl.)
  size.w = max(size.w, box.state.size.w)
  size.h = max(size.h, box.state.size.h)
  lctx.popPositioned(box.state.overflow, size)
  return box
