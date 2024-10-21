import std/algorithm
import std/math

import css/cssvalues
import css/stylednode
import types/bitmap
import layout/box
import layout/layoutunit
import types/winattrs
import utils/luwrap
import utils/strwidth
import utils/twtstr
import utils/twtuni
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
    positioned: seq[PositionedItem]
    myRootProperties: CSSComputedValues
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

  ResolvedSizes = object
    margin: RelativeRect
    padding: RelativeRect
    positioned: RelativeRect
    space: AvailableSpace
    minMaxSizes: array[DimensionType, Span]

const DefaultSpan = Span(start: 0, send: LayoutUnit.high)

func minWidth(sizes: ResolvedSizes): LayoutUnit =
  return sizes.minMaxSizes[dtHorizontal].start

func maxWidth(sizes: ResolvedSizes): LayoutUnit =
  return sizes.minMaxSizes[dtHorizontal].send

func minHeight(sizes: ResolvedSizes): LayoutUnit =
  return sizes.minMaxSizes[dtVertical].start

func maxHeight(sizes: ResolvedSizes): LayoutUnit =
  return sizes.minMaxSizes[dtVertical].send

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
func px(l: CSSLength; lctx: LayoutContext; p: LayoutUnit = 0):
    LayoutUnit {.inline.} =
  return px(l, lctx.attrs, p)

func canpx(l: CSSLength; sc: SizeConstraint): bool =
  return not l.auto and (l.unit != cuPerc or sc.isDefinite())

# Note: for margins only
# For percentages, use 0 for indefinite, and containing box's size for
# definite.
func px(l: CSSLength; lctx: LayoutContext; p: SizeConstraint): LayoutUnit =
  if l.unit == cuPerc:
    case p.t
    of scMinContent, scMaxContent:
      return 0
    of scStretch, scFitContent:
      return l.px(lctx, p.u)
  return px(l, lctx.attrs, 0)

func stretchOrMaxContent(l: CSSLength; lctx: LayoutContext; sc: SizeConstraint):
    SizeConstraint =
  if l.canpx(sc):
    return stretch(l.px(lctx, sc))
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

func outerSize(box: BlockBox; dim: DimensionType): LayoutUnit =
  return box.state.margin[dim].sum() + box.state.size[dim]

# In CSS, "min" beats "max".
func minClamp(x: LayoutUnit; span: Span): LayoutUnit =
  return max(min(x, span.send), span.start)

#TODO these are not really static-like, just unimplemented
const PositionStaticLike = {
  PositionStatic, PositionFixed, PositionSticky
}

type
  BlockContext = object
    lctx: LayoutContext
    marginTodo: Strut
    # We use a linked list to set the correct BFC offset and relative offset
    # for every block with an unresolved y offset on margin resolution.
    # marginTarget is a pointer to the last un-resolved ancestor.
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
    paddingTop: LayoutUnit
    paddingBottom: LayoutUnit
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
    space: AvailableSpace

  InlineContext = object
    root: RootInlineFragment
    computed: CSSComputedValues
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

  InlineState = object
    fragment: InlineFragment
    startOffsetTop: Offset
    # we do not want to collapse newlines over tag boundaries, so these are
    # in state
    lastrw: int # last rune width of the previous word
    firstrw: int # first rune width of the current word
    prevrw: int # last processed rune's width

func whitespacepre(computed: CSSComputedValues): bool =
  computed{"white-space"} in {WhitespacePre, WhitespacePreLine,
    WhitespacePreWrap}

func nowrap(computed: CSSComputedValues): bool =
  computed{"white-space"} in {WhitespaceNowrap, WhitespacePre}

func cellWidth(lctx: LayoutContext): int =
  lctx.attrs.ppc

func cellWidth(ictx: InlineContext): int =
  ictx.lctx.cellWidth

func cellHeight(ictx: InlineContext): int =
  ictx.lctx.attrs.ppl

func size(ictx: InlineContext): Size =
  ictx.root.state.size

func size(ictx: var InlineContext): var Size =
  ictx.root.state.size

func sum(rect: RelativeRect): Size =
  return [
    dtHorizontal: rect[dtHorizontal].sum(),
    dtVertical: rect[dtVertical].sum()
  ]

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

proc applyLineHeight(ictx: InlineContext; state: var LineBoxState;
    computed: CSSComputedValues) =
  let lctx = ictx.lctx
  let paddingTop = computed{"padding-top"}.px(lctx, ictx.space.w)
  let paddingBottom = computed{"padding-bottom"}.px(lctx, ictx.space.w)
  state.paddingTop = max(paddingTop, state.paddingTop)
  state.paddingBottom = max(paddingBottom, state.paddingBottom)

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
  of scMinContent, scMaxContent: ictx.size.w
  of scFitContent: ictx.space.w.u
  of scStretch: max(ictx.size.w, ictx.space.w.u)

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
  let shiftTop = marginTop + ictx.lbstate.paddingTop
  let cellHeight = ictx.cellHeight
  let width = ictx.getLineWidth()
  let xshift = ictx.getLineXShift(width)
  var totalWidth: LayoutUnit = 0
  var currentAreaOffsetX: LayoutUnit = 0
  var currentFragment: InlineFragment = nil
  let offsetyShifted = shiftTop + offsety
  var areaY: LayoutUnit = 0
  for i, atom in ictx.lbstate.atoms:
    atom.offset.y = (atom.offset.y + offsetyShifted).round(cellHeight)
    areaY = max(atom.offset.y, areaY)
    #TODO why not offsetyShifted here?
    let minHeight = atom.offset.y - offsety + atom.size.h
    ictx.lbstate.minHeight = max(ictx.lbstate.minHeight, minHeight)
    # Y is always final, so it is safe to calculate Y overflow
    ictx.root.state.overflow[dtVertical].expand(atom.overflow(dtVertical))
    # now position on the inline axis
    atom.offset.x += xshift
    totalWidth += atom.size.w
    ictx.root.state.overflow[dtHorizontal].expand(atom.overflow(dtHorizontal))
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
    ictx.size.w = max(totalWidth, ictx.size.w)

# Align atoms (inline boxes, text, etc.) on both axes.
proc alignLine(ictx: var InlineContext) =
  # Start with cell height as the baseline and line height.
  let ch = ictx.cellHeight.toLayoutUnit()
  ictx.lbstate.size.h = ch
  # Baseline is what we computed in addAtom, or cell height if that's greater.
  ictx.lbstate.baseline = max(ictx.lbstate.baseline, ch).round(ictx.cellHeight)
  # Resize according to the baseline and atom sizes.
  ictx.lbstate.size.h = ictx.lbstate.resizeLine(ictx.lctx)
  # Now we can calculate the actual position of atoms inside the line.
  let marginTop = ictx.lbstate.positionAtoms(ictx.lctx)
  #TODO this does not really work with rounding :/
  ictx.lbstate.baseline += ictx.lbstate.paddingTop
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

# Prepare the next line's initial width and available width.
# (If space on the left is excluded by floats, set the initial width to
# the end of that space. If space on the right is excluded, set the available
# width to that space.)
proc initLine(ictx: var InlineContext) =
  ictx.lbstate.availableWidth = ictx.space.w.u
  let bctx = ictx.bctx
  #TODO what if maxContent/minContent?
  if bctx.exclusions.len != 0:
    let bfcOffset = ictx.bfcOffset
    let y = ictx.lbstate.offsety + bfcOffset.y
    var left = bfcOffset.x
    var right = bfcOffset.x + ictx.lbstate.availableWidth
    for ex in bctx.exclusions:
      if ex.offset.y <= y and y < ex.offset.y + ex.size.h:
        ictx.lbstate.hasExclusion = true
        if ex.t == FloatLeft:
          left = ex.offset.x + ex.size.w
        else:
          right = ex.offset.x
    ictx.lbstate.size.w = max(left - bfcOffset.x, 0)
    ictx.lbstate.availableWidth = min(right - bfcOffset.x,
      ictx.lbstate.availableWidth)

proc finishLine(ictx: var InlineContext; state: var InlineState; wrap: bool;
    force = false) =
  if ictx.lbstate.atoms.len != 0 or force:
    let whitespace = state.fragment.computed{"white-space"}
    if whitespace == WhitespacePre:
      ictx.flushWhitespace(state)
    elif whitespace == WhitespacePreWrap:
      ictx.flushWhitespace(state, hang = true)
    else:
      ictx.whitespacenum = 0
    # align atoms + calculate width for fit-content + place
    ictx.alignLine()
    # add line to ictx
    let y = ictx.lbstate.offsety
    # * set first baseline if this is the first line box
    # * always set last baseline (so the baseline of the last line box remains)
    if not ictx.firstBaselineSet:
      ictx.root.state.firstBaseline = y + ictx.lbstate.baseline
      ictx.firstBaselineSet = true
    ictx.root.state.baseline = y + ictx.lbstate.baseline
    ictx.size.h += ictx.lbstate.size.h
    let lineWidth = if wrap:
      ictx.lbstate.availableWidth
    else:
      ictx.lbstate.size.w
    ictx.size.w = max(ictx.size.w, lineWidth)
    ictx.lbstate = LineBoxState(offsety: y + ictx.lbstate.size.h)
    ictx.initLine()

func xminwidth(atom: InlineAtom): LayoutUnit =
  if atom.t == iatInlineBlock:
    return atom.innerbox.state.xminwidth
  elif atom.t == iatImage:
    # We calculate this in addInlineImage instead.
    return 0
  return atom.size.w

func shouldWrap(ictx: InlineContext; w: LayoutUnit;
    pcomputed: CSSComputedValues): bool =
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

# Start a new line, even if the previous one is empty
proc flushLine(ictx: var InlineContext; state: var InlineState) =
  ictx.applyLineHeight(ictx.lbstate, state.fragment.computed)
  ictx.finishLine(state, wrap = false, force = true)

func getBaseline(ictx: InlineContext; iastate: InlineAtomState;
    atom: InlineAtom): LayoutUnit =
  return case iastate.vertalign.keyword
  of VerticalAlignBaseline:
    let len = iastate.vertalign.length.px(ictx.lctx, ictx.cellHeight)
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
    ictx.finishLine(state, wrap = true, force = false)
    result = true
    # Recompute on newline
    shift = ictx.computeShift(state)
    # For floats: flush lines until we can place the atom.
    #TODO this is inefficient
    while ictx.shouldWrap2(atom.size.w + shift):
      ictx.applyLineHeight(ictx.lbstate, state.fragment.computed)
      ictx.finishLine(state, wrap = false, force = true)
      # Recompute on newline
      shift = ictx.computeShift(state)
  if atom.size.w > 0 and atom.size.h > 0 or atom.t == iatInlineBlock:
    if shift > 0:
      ictx.addSpacing(shift, state)
    ictx.root.state.xminwidth = max(ictx.root.state.xminwidth, atom.xminwidth)
    ictx.applyLineHeight(ictx.lbstate, state.fragment.computed)
    if atom.t == iatWord:
      if ictx.lbstate.atoms.len > 0 and state.fragment.state.atoms.len > 0:
        let oatom = ictx.lbstate.atoms[^1]
        if oatom.t == iatWord and oatom == state.fragment.state.atoms[^1]:
          oatom.str &= atom.str
          oatom.size.w += atom.size.w
          ictx.lbstate.size.w += atom.size.w
          return
    else:
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
      ictx.flushLine(state)
    elif ictx.whitespacenum < 1:
      ictx.whitespaceIsLF = false
      ictx.whitespacenum = 1
      ictx.whitespaceFragment = state.fragment
  of WhitespacePre, WhitespacePreWrap:
    ictx.whitespaceIsLF = false
    if c == '\n':
      ictx.flushLine(state)
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
    bfcOffset: Offset; root: RootInlineFragment;
    computed: CSSComputedValues): InlineContext =
  return InlineContext(
    bctx: addr bctx,
    lctx: bctx.lctx,
    bfcOffset: bfcOffset,
    space: space,
    root: root,
    computed: computed
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

func spx(l: CSSLength; lctx: LayoutContext; p: SizeConstraint;
    computed: CSSComputedValues; padding: LayoutUnit): LayoutUnit =
  let u = l.px(lctx, p)
  if computed{"box-sizing"} == BoxSizingBorderBox:
    return max(u - padding, 0)
  return max(u, 0)

proc resolveContentWidth(sizes: var ResolvedSizes; widthpx: LayoutUnit;
    parentWidth: SizeConstraint; computed: CSSComputedValues;
    isauto = false) =
  if not sizes.space.w.isDefinite() or not parentWidth.isDefinite():
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
    if not computed{"margin-left"}.auto and not computed{"margin-right"}.auto:
      sizes.margin[dtHorizontal].send += underflow
    elif not computed{"margin-left"}.auto and computed{"margin-right"}.auto:
      sizes.margin[dtHorizontal].send = underflow
    elif computed{"margin-left"}.auto and not computed{"margin-right"}.auto:
      sizes.margin[dtHorizontal].start = underflow
    else:
      sizes.margin[dtHorizontal].start = underflow div 2
      sizes.margin[dtHorizontal].send = underflow div 2

proc resolveMargins(availableWidth: SizeConstraint; lctx: LayoutContext;
    computed: CSSComputedValues): RelativeRect =
  # Note: we use availableWidth for percentage resolution intentionally.
  return [
    dtHorizontal: Span(
      start: computed{"margin-left"}.px(lctx, availableWidth),
      send: computed{"margin-right"}.px(lctx, availableWidth),
    ),
    dtVertical: Span(
      start: computed{"margin-top"}.px(lctx, availableWidth),
      send: computed{"margin-bottom"}.px(lctx, availableWidth),
    )
  ]

proc resolvePadding(availableWidth: SizeConstraint; lctx: LayoutContext;
    computed: CSSComputedValues): RelativeRect =
  # Note: we use availableWidth for percentage resolution intentionally.
  return [
    dtHorizontal: Span(
      start: computed{"padding-left"}.px(lctx, availableWidth),
      send: computed{"padding-right"}.px(lctx, availableWidth)
    ),
    dtVertical: Span(
      start: computed{"padding-top"}.px(lctx, availableWidth),
      send: computed{"padding-bottom"}.px(lctx, availableWidth),
    )
  ]

func resolvePositioned(space: AvailableSpace; lctx: LayoutContext;
    computed: CSSComputedValues): RelativeRect =
  # As per standard, vertical percentages refer to the *height*, not the width
  # (unlike with margin/padding)
  return [
    dtHorizontal: Span(
      start: computed{"left"}.px(lctx, space.w),
      send: computed{"right"}.px(lctx, space.w)
    ),
    dtVertical: Span(
      start: computed{"top"}.px(lctx, space.h),
      send: computed{"bottom"}.px(lctx, space.h),
    )
  ]

func resolveMinMaxSize(length: CSSLength; sc: SizeConstraint;
    fallback, padding: LayoutUnit; computed: CSSComputedValues;
    lctx: LayoutContext): LayoutUnit =
  if length.canpx(sc):
    return length.spx(lctx, sc, computed, padding)
  return fallback

func resolveMinMaxSizes(lctx: LayoutContext; space: AvailableSpace;
    paddingSum: Size; computed: CSSComputedValues): array[DimensionType, Span] =
  return [
    dtHorizontal: Span(
      start: computed{"min-width"}.resolveMinMaxSize(space.w, 0,
        paddingSum[dtHorizontal], computed, lctx),
      send: computed{"max-width"}.resolveMinMaxSize(space.w, LayoutUnit.high,
        paddingSum[dtHorizontal], computed, lctx)
    ),
    dtVertical: Span(
      start: computed{"min-height"}.resolveMinMaxSize(space.h, 0,
        paddingSum[dtVertical], computed, lctx),
      send: computed{"max-height"}.resolveMinMaxSize(space.h, LayoutUnit.high,
        paddingSum[dtVertical], computed, lctx)
    )
  ]

proc resolveBlockWidth(sizes: var ResolvedSizes; parentWidth: SizeConstraint;
    inlinePadding: LayoutUnit; computed: CSSComputedValues;
    lctx: LayoutContext) =
  let width = computed{"width"}
  var widthpx: LayoutUnit = 0
  if width.canpx(parentWidth):
    widthpx = width.spx(lctx, parentWidth, computed, inlinePadding)
    sizes.space.w = stretch(widthpx)
  sizes.resolveContentWidth(widthpx, parentWidth, computed, width.auto)
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
    blockPadding: LayoutUnit; computed: CSSComputedValues;
    lctx: LayoutContext) =
  let height = computed{"height"}
  if height.canpx(parentHeight):
    let heightpx = height.spx(lctx, parentHeight, computed, blockPadding)
    sizes.space.h = stretch(heightpx)
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

const CvalSizeMap = [dtHorizontal: cptWidth, dtVertical: cptHeight]
const CvalStartMap = [dtHorizontal: cptLeft, dtVertical: cptTop]
const CvalEndMap = [dtHorizontal: cptRight, dtVertical: cptBottom]

proc resolveAbsoluteSize(sizes: var ResolvedSizes; space: AvailableSpace;
    dim: DimensionType; computed: CSSComputedValues; lctx: LayoutContext) =
  let cvalSize = computed[CvalSizeMap[dim]].length
  if cvalSize.auto:
    # available space is always known here, because unlike regular
    # boxes, we layout absolute boxes in a bottom-up order.
    assert space[dim].isDefinite
    let u = max(space[dim].u - sizes.positioned[dim].sum(), 0)
    let cvalStart = computed[CvalStartMap[dim]].length
    let cvalEnd = computed[CvalEndMap[dim]].length
    if not cvalStart.auto and not cvalEnd.auto:
      # width is auto and left & right are not auto.
      # Solve for width.
      sizes.space[dim] = stretch(u)
    else:
      # Return shrink to fit and solve for left/right.
      sizes.space[dim] = fitContent(u)
  else:
    let padding = sizes.padding[dim].sum()
    let sizepx = cvalSize.spx(lctx, space[dim], computed, padding)
    # We could solve for left/right here, as available width is known.
    # Nevertheless, it is only needed for positioning, so we do not solve
    # them yet.
    sizes.space[dim] = stretch(sizepx)

proc resolveBlockSizes(lctx: LayoutContext; space: AvailableSpace;
    computed: CSSComputedValues): ResolvedSizes =
  let padding = resolvePadding(space.w, lctx, computed)
  let paddingSum = padding.sum()
  var sizes = ResolvedSizes(
    margin: resolveMargins(space.w, lctx, computed),
    padding: padding,
    space: space,
    minMaxSizes: lctx.resolveMinMaxSizes(space, paddingSum, computed)
  )
  # for tables, fit-content by default
  if computed{"display"} == DisplayTableWrapper:
    sizes.space.w = fitContent(sizes.space.w)
  # height is max-content normally, but fit-content for clip.
  sizes.space.h = if computed{"overflow"} != OverflowClip:
    maxContent()
  else:
    fitContent(sizes.space.h)
  if computed{"position"} == PositionRelative:
    # only compute this when needed
    sizes.positioned = resolvePositioned(space, lctx, computed)
  # Finally, calculate available width and height.
  sizes.resolveBlockWidth(space.w, paddingSum[dtHorizontal], computed, lctx)
  #TODO parent height should be lctx height in quirks mode for percentage
  # resolution.
  sizes.resolveBlockHeight(space.h, paddingSum[dtVertical], computed, lctx)
  return sizes

# Calculate and resolve available width & height for absolutely positioned
# boxes.
proc resolveAbsoluteSizes(lctx: LayoutContext; space: AvailableSpace;
    computed: CSSComputedValues): ResolvedSizes =
  var sizes = ResolvedSizes(
    margin: resolveMargins(space.w, lctx, computed),
    padding: resolvePadding(space.w, lctx, computed),
    positioned: resolvePositioned(space, lctx, computed),
    minMaxSizes: [dtHorizontal: DefaultSpan, dtVertical: DefaultSpan]
  )
  for dim in DimensionType:
    sizes.resolveAbsoluteSize(space, dim, computed, lctx)
  return sizes

# Calculate and resolve available width & height for floating boxes.
proc resolveFloatSizes(lctx: LayoutContext; space: AvailableSpace;
    computed: CSSComputedValues): ResolvedSizes =
  let padding = resolvePadding(space.w, lctx, computed)
  let paddingSum = padding.sum()
  var sizes = ResolvedSizes(
    margin: resolveMargins(space.w, lctx, computed),
    padding: padding,
    space: space,
    minMaxSizes: lctx.resolveMinMaxSizes(space, paddingSum, computed)
  )
  sizes.space.h = maxContent()
  for dim in DimensionType:
    let length = computed[CvalSizeMap[dim]].length
    if length.canpx(space[dim]):
      let u = length.spx(lctx, space[dim], computed, paddingSum[dim])
      sizes.space[dim] = stretch(minClamp(u, sizes.minMaxSizes[dim]))
    elif sizes.space[dim].isDefinite():
      let u = sizes.space[dim].u - sizes.margin[dim].sum() - paddingSum[dim]
      sizes.space[dim] = fitContent(minClamp(u, sizes.minMaxSizes[dim]))
  return sizes

proc resolveFlexItemSizes(lctx: LayoutContext; space: AvailableSpace;
    dim: DimensionType; computed: CSSComputedValues): ResolvedSizes =
  let padding = resolvePadding(space.w, lctx, computed)
  let paddingSum = padding.sum()
  var sizes = ResolvedSizes(
    margin: resolveMargins(space.w, lctx, computed),
    padding: padding,
    space: space,
    minMaxSizes: lctx.resolveMinMaxSizes(space, paddingSum, computed),
    positioned: resolvePositioned(space, lctx, computed)
  )
  if dim != dtHorizontal:
    sizes.space.h = maxContent()
  let length = computed[CvalSizeMap[dim]].length
  if length.canpx(space[dim]):
    let u = length.spx(lctx, space[dim], computed, paddingSum[dim])
    sizes.space[dim] = stretch(minClamp(u, sizes.minMaxSizes[dim]))
  elif sizes.space[dim].isDefinite():
    let u = sizes.space[dim].u - sizes.margin[dim].sum() - paddingSum[dim]
    sizes.space[dim] = fitContent(minClamp(u, sizes.minMaxSizes[dim]))
  let odim = dim.opposite()
  let olength = computed[CvalSizeMap[odim]].length
  if olength.canpx(space[odim]):
    let u = olength.spx(lctx, space[odim], computed, paddingSum[odim])
    sizes.space[odim] = stretch(minClamp(u, sizes.minMaxSizes[odim]))
  elif sizes.space[odim].isDefinite():
    let u = sizes.space[odim].u - sizes.margin[odim].sum() - paddingSum[odim]
    sizes.space[odim] = stretch(minClamp(u, sizes.minMaxSizes[odim]))
  return sizes

# Calculate and resolve available width, height, padding, margins, etc.
# space is the width/height of the containing box.
proc resolveSizes(lctx: LayoutContext; space: AvailableSpace;
    computed: CSSComputedValues): ResolvedSizes =
  if computed{"position"} == PositionAbsolute:
    return lctx.resolveAbsoluteSizes(space, computed)
  elif computed{"float"} != FloatNone:
    return lctx.resolveFloatSizes(space, computed)
  else:
    return lctx.resolveBlockSizes(space, computed)

proc append(a: var Strut; b: LayoutUnit) =
  if b < 0:
    a.neg = min(b, a.neg)
  else:
    a.pos = max(b, a.pos)

func sum(a: Strut): LayoutUnit =
  return a.pos + a.neg

# forward declarations
proc layoutRootInline(bctx: var BlockContext; root: RootInlineFragment;
  space: AvailableSpace; computed: CSSComputedValues; offset, bfcOffset: Offset)
proc layoutBlock(bctx: var BlockContext; box: BlockBox; sizes: ResolvedSizes)
proc layoutTableWrapper(bctx: BlockContext; box: BlockBox; sizes: ResolvedSizes)
proc layoutFlex(bctx: var BlockContext; box: BlockBox; sizes: ResolvedSizes)
proc layoutInline(ictx: var InlineContext; fragment: InlineFragment)
proc layoutRootBlock(lctx: LayoutContext; box: BlockBox;
    space: AvailableSpace; offset: Offset; marginBottomOut: var LayoutUnit)

# Note: padding must still be applied after this.
proc applySize(box: BlockBox; sizes: ResolvedSizes;
    maxChildSize: LayoutUnit; space: AvailableSpace; dim: DimensionType) =
  # Make the box as small/large as the content's width or specified width.
  box.state.size[dim] = maxChildSize.applySizeConstraint(space[dim])
  # Then, clamp it to minWidth and maxWidth (if applicable).
  box.state.size[dim] = minClamp(box.state.size[dim], sizes.minMaxSizes[dim])

proc applyWidth(box: BlockBox; sizes: ResolvedSizes;
    maxChildWidth: LayoutUnit; space: AvailableSpace) =
  box.applySize(sizes, maxChildWidth, space, dtHorizontal)

proc applyWidth(box: BlockBox; sizes: ResolvedSizes;
    maxChildWidth: LayoutUnit) =
  box.applyWidth(sizes, maxChildWidth, sizes.space)

proc applyHeight(box: BlockBox; sizes: ResolvedSizes;
    maxChildHeight: LayoutUnit) =
  box.applySize(sizes, maxChildHeight, sizes.space, dtVertical)

proc applyPadding(box: BlockBox; padding: RelativeRect) =
  box.state.size.w += padding[dtHorizontal].sum()
  box.state.size.h += padding[dtVertical].sum()

func bfcOffset(bctx: BlockContext): Offset =
  if bctx.parentBps != nil:
    return bctx.parentBps.offset
  return offset(x = 0, y = 0)

# expand to (0, size[dim].u)
func finalize(overflow: var Overflow; size: Size) =
  overflow[dtHorizontal].expand(Span(start: 0, send: size[dtHorizontal]))
  overflow[dtVertical].expand(Span(start: 0, send: size[dtVertical]))

proc layoutInline(bctx: var BlockContext; box: BlockBox; sizes: ResolvedSizes) =
  var bfcOffset = bctx.bfcOffset
  let offset = offset(x = sizes.padding.left, y = sizes.padding.top)
  bfcOffset.x += box.state.offset.x + offset.x
  bfcOffset.y += box.state.offset.y + offset.y
  bctx.layoutRootInline(box.inline, sizes.space, box.computed, offset,
    bfcOffset)
  box.state.xminwidth = max(box.state.xminwidth, box.inline.state.xminwidth)
  box.state.size.w = box.inline.state.size.w + sizes.padding[dtHorizontal].sum()
  box.applyWidth(sizes, box.inline.state.size.w)
  box.applyHeight(sizes, box.inline.state.size.h)
  box.applyPadding(sizes.padding)
  box.state.baseline = offset.y + box.inline.state.baseline
  box.state.firstBaseline = offset.y + box.inline.state.firstBaseline
  box.state.overflow = box.inline.state.overflow
  # shift overflow
  for dim in DimensionType:
    box.state.overflow[dim] += offset[dim]
  box.state.overflow.finalize(box.state.size)

const DisplayBlockLike = {DisplayBlock, DisplayListItem, DisplayInlineBlock}

# Return true if no more margin collapsing can occur for the current strut.
func canFlushMargins(box: BlockBox; sizes: ResolvedSizes): bool =
  if box.computed{"position"} == PositionAbsolute:
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

proc clearFloats(offset: var Offset; bctx: var BlockContext; clear: CSSClear) =
  var y = bctx.bfcOffset.y + offset.y
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
  offset.y = y - bctx.bfcOffset.y

proc applyOverflowDimensions(parent: var Overflow; child: BlockBox) =
  var childOverflow = child.state.overflow
  for dim in DimensionType:
    childOverflow[dim] += child.state.offset[dim]
    parent[dim].expand(childOverflow[dim])

proc applyOverflowDimensions(box, child: BlockBox) =
  box.state.overflow.applyOverflowDimensions(child)

proc pushPositioned(lctx: LayoutContext) =
  lctx.positioned.add(PositionedItem())

proc popPositioned(lctx: LayoutContext; overflow: var Overflow;
    space: AvailableSpace) =
  let item = lctx.positioned.pop()
  for it in item.queue:
    let child = it.child
    var marginBottomOut: LayoutUnit
    lctx.layoutRootBlock(child, space, it.offset, marginBottomOut)
    if not child.computed{"left"}.auto:
      child.state.offset.x = child.state.positioned.left +
        child.state.margin.left
    elif not child.computed{"right"}.auto:
      child.state.offset.x = -child.state.positioned.right -
        child.state.size.w - child.state.margin.right
    # margin.left is added in layoutRootBlock
    if not child.computed{"top"}.auto:
      child.state.offset.y = child.state.positioned.top +
        child.state.margin.top
    elif not child.computed{"bottom"}.auto:
      child.state.offset.y = -child.state.positioned.bottom -
        child.state.size.h - child.state.margin.bottom
    else:
      child.state.offset.y += child.state.margin.top
    overflow.applyOverflowDimensions(child)

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
    space: AvailableSpace; bfcOffset: Offset) =
  let clear = child.computed{"clear"}
  if clear != ClearNone:
    child.state.offset.clearFloats(bctx, clear)
  let size = size(
    w = child.outerSize(dtHorizontal),
    h = child.outerSize(dtVertical)
  )
  let childBfcOffset = offset(
    x = bfcOffset.x + child.state.offset.x - child.state.margin.left,
    y = max(bfcOffset.y + child.state.offset.y - child.state.margin.top,
      bctx.clearOffset)
  )
  assert space.w.t != scFitContent
  let ft = child.computed{"float"}
  assert ft != FloatNone
  let offset = bctx.findNextFloatOffset(childBfcOffset, size, space, ft)
  child.state.offset = offset(
    x = offset.x - bfcOffset.x + child.state.margin.left,
    y = offset.y - bfcOffset.y + child.state.margin.top
  )
  let ex = Exclusion(offset: offset, size: size, t: ft)
  bctx.exclusions.add(ex)
  bctx.maxFloatHeight = max(bctx.maxFloatHeight, ex.offset.y + ex.size.h)

proc positionFloats(bctx: var BlockContext) =
  for f in bctx.unpositionedFloats:
    bctx.positionFloat(f.box, f.space, f.parentBps.offset)
    # Propagate overflow dimensions to the float's parent box.
    f.parentBox.applyOverflowDimensions(f.box)
  bctx.unpositionedFloats.setLen(0)

proc layoutFlow(bctx: var BlockContext; box: BlockBox; sizes: ResolvedSizes) =
  if box.canFlushMargins(sizes):
    bctx.flushMargins(box)
    bctx.positionFloats()
  if box.computed{"clear"} != ClearNone:
    box.state.offset.clearFloats(bctx, box.computed{"clear"})
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
    let marker = box.nested[0]
    let content = box.nested[1]
    marker.state = BlockBoxLayoutState()
    content.state = BlockBoxLayoutState(
      offset: box.state.offset,
      positioned: sizes.positioned
    )
    bctx.layoutFlow(content, sizes)
    #TODO we should put markers right before the first atom of the parent
    # list item or something...
    var bctx = BlockContext(lctx: bctx.lctx)
    let markerSizes = ResolvedSizes(
      space: availableSpace(w = fitContent(sizes.space.w), h = sizes.space.h),
      minMaxSizes: [dtHorizontal: DefaultSpan, dtVertical: DefaultSpan]
    )
    bctx.layoutFlow(marker, markerSizes)
    marker.state.offset.x = -marker.state.size.w
    # take inner box min width etc.
    box.state = content.state
    content.state.offset = offset(x = 0, y = 0)
    content.state.margin = [Span(), Span()]
    content.state.positioned = [Span(), Span()]
  of ListStylePositionInside:
    bctx.layoutFlow(box, sizes)

proc addInlineFloat(ictx: var InlineContext; state: var InlineState;
    box: BlockBox) =
  let lctx = ictx.lctx
  let sizes = lctx.resolveFloatSizes(ictx.space, box.computed)
  box.state = BlockBoxLayoutState(
    margin: sizes.margin,
    positioned: sizes.positioned
  )
  var marginBottom: LayoutUnit = 0
  let offset = offset(
    x = 0,
    y = ictx.lbstate.offsety + sizes.margin.top
  )
  lctx.layoutRootBlock(box, sizes.space, offset, marginBottom)
  ictx.lbstate.size.w += box.state.size.w
  # Note that by now, the top y offset is always resolved.
  ictx.unpositionedFloats.add(InlineUnpositionedFloat(
    parent: state.fragment,
    box: box,
    space: sizes.space
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
  lctx.positioned[^1].queue.add(QueuedAbsolute(child: box, offset: offset))

proc addInlineBlock(ictx: var InlineContext; state: var InlineState;
    box: BlockBox) =
  let lctx = ictx.lctx
  let sizes = lctx.resolveFloatSizes(ictx.space, box.computed)
  box.state = BlockBoxLayoutState(
    margin: sizes.margin,
    positioned: sizes.positioned
  )
  var marginBottom: LayoutUnit = 0
  lctx.layoutRootBlock(box, sizes.space, offset(x = 0, y = 0), marginBottom)
  # Apply the block box's properties to the atom itself.
  let iblock = InlineAtom(
    t: iatInlineBlock,
    innerbox: box,
    offset: offset(x = 0, y = 0),
    size: size(w = box.outerSize(dtHorizontal), h = box.state.size.h)
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
  if box.computed{"position"} == PositionAbsolute:
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
    size: size(w = int(bmp.width), h = int(bmp.height)) #TODO overflow
  )
  let computed = state.fragment.computed
  let lctx = ictx.lctx
  var hasWidth = computed{"width"}.canpx(ictx.space.w)
  var hasHeight = computed{"height"}.canpx(ictx.space.h)
  let osize = atom.size
  if hasWidth:
    atom.size.w = computed{"width"}.spx(lctx, ictx.space.w, computed, padding)
  if hasHeight:
    atom.size.h = computed{"height"}.spx(lctx, ictx.space.h, computed, padding)
  if computed{"max-width"}.canpx(ictx.space.w):
    let w = computed{"max-width"}.spx(lctx, ictx.space.w, computed, padding)
    if atom.size.w > w:
      atom.size.w = w
      hasWidth = true
  if computed{"min-width"}.canpx(ictx.space.w):
    let w = computed{"min-width"}.spx(lctx, ictx.space.w, computed, padding)
    if atom.size.w < w:
      atom.size.w = w
      hasWidth = true
  if computed{"max-height"}.canpx(ictx.space.h):
    let h = computed{"max-height"}.spx(lctx, ictx.space.h, computed, padding)
    if atom.size.h > h:
      atom.size.h = h
      hasHeight = true
  if computed{"min-height"}.canpx(ictx.space.h):
    let h = computed{"min-height"}.spx(lctx, ictx.space.h, computed, padding)
    if atom.size.h < h:
      atom.size.h = h
      hasHeight = true
  if not hasWidth and not hasHeight:
    if ictx.space.w.isDefinite() and atom.size.w > ictx.space.w.u:
      atom.size.w = ictx.space.w.u
      if osize.w > 0:
        atom.size.h = osize.h div osize.w * atom.size.w
    if ictx.space.h.isDefinite() and atom.size.h > ictx.space.h.u:
      atom.size.h = ictx.space.h.u
      if osize.w > 0:
        atom.size.w = osize.w div osize.h * atom.size.h
  elif not hasHeight:
    if osize.w > 0:
      atom.size.h = osize.h div osize.w * atom.size.w
  elif not hasWidth:
    if osize.h > 0:
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
    if ictx.space.w.isDefinite() or computed{"width"}.unit != cuPerc and
        computed{"min-width"}.unit != cuPerc:
      ictx.root.state.xminwidth = max(ictx.root.state.xminwidth, atom.size.w)

proc layoutInline(ictx: var InlineContext; fragment: InlineFragment) =
  let lctx = ictx.lctx
  let computed = fragment.computed
  var padding = Span()
  if stSplitStart in fragment.splitType:
    let w = computed{"margin-left"}.px(lctx, ictx.space.w)
    ictx.lbstate.size.w += w
    ictx.lbstate.widthAfterWhitespace += w
    padding = Span(
      start: computed{"padding-left"}.px(lctx, ictx.space.w),
      send: computed{"padding-right"}.px(lctx, ictx.space.w)
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
  if ictx.lbstate.atoms.len > 0:
    fragment.state.startOffset.y += ictx.cellHeight
  ictx.lbstate.size.w += padding.start
  var state = InlineState(fragment: fragment)
  if stSplitStart in fragment.splitType and
      computed{"position"} notin PositionStaticLike:
    lctx.pushPositioned()
  ictx.applyLineHeight(ictx.lbstate, computed)
  case fragment.t
  of iftNewline: ictx.flushLine(state)
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
    ictx.lbstate.size.w += computed{"margin-right"}.px(lctx, ictx.space.w)
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
    let space = availableSpace(
      w = stretch(0),
      h = stretch(ictx.root.state.size.h)
    )
    #TODO this overflow calculation looks wrong
    lctx.popPositioned(ictx.root.state.overflow, space)

proc layoutRootInline0(bctx: var BlockContext; ictx: var InlineContext;
    root: RootInlineFragment; space: AvailableSpace;
    computed: CSSComputedValues; offset, bfcOffset: Offset) =
  root.state = RootInlineFragmentState(offset: offset)
  ictx.layoutInline(root.fragment)
  if ictx.lastTextFragment != nil:
    let fragment = ictx.lastTextFragment
    var state = InlineState(fragment: fragment)
    ictx.finishLine(state, wrap = false)

proc layoutRootInline(bctx: var BlockContext; root: RootInlineFragment;
    space: AvailableSpace; computed: CSSComputedValues;
    offset, bfcOffset: Offset) =
  var ictx = bctx.initInlineContext(space, bfcOffset, root, computed)
  ictx.initLine()
  bctx.layoutRootInline0(ictx, root, space, computed, offset, bfcOffset)
  if ictx.unpositionedFloats.len > 0 or
      ictx.space.w.t == scFitContent and
      ictx.computed{"text-align"} notin TextAlignNone and
      ictx.size.w != ictx.space.w.u:
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
    let space = availableSpace(w = stretch(ictx.size.w), h = space.h)
    ictx = bctx.initInlineContext(space, bfcOffset, root, computed)
    for it in floats:
      var offset = offset(x = 0, y = 0)
      if bctx.parentBps != nil:
        offset = bctx.parentBps.offset
      bctx.positionFloat(it.box, space, offset)
    ictx.initLine()
    ictx.secondPass = true
    bctx.layoutRootInline0(ictx, root, space, computed, offset, bfcOffset)
    for it in floats:
      it.parent.state.atoms.add(InlineAtom(
        t: iatInlineBlock,
        innerbox: it.box
      ))
  ictx.root.state.overflow.finalize(ictx.root.state.size)

proc positionRelative(lctx: LayoutContext; parent, box: BlockBox) =
  if not box.computed{"left"}.auto:
    box.state.offset.x += box.computed{"left"}.px(lctx, parent.state.size.w)
  elif not box.computed{"right"}.auto:
    box.state.offset.x += parent.state.size.w - box.state.size.w -
      box.computed{"right"}.px(lctx, parent.state.size.w)
  if not box.computed{"top"}.auto:
    box.state.offset.y += box.computed{"top"}.px(lctx, parent.state.size.h)
  elif not box.computed{"bottom"}.auto:
    box.state.offset.y += parent.state.size.h - box.state.size.h -
      box.computed{"bottom"}.px(lctx, parent.state.size.h)

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
    padding: resolvePadding(space.w, lctx, box.computed),
    space: space,
    minMaxSizes: [dtHorizontal: DefaultSpan, dtVertical: DefaultSpan]
  )
  if sizes.space.w.isDefinite():
    sizes.space.w.u -= sizes.padding.left
    sizes.space.w.u -= sizes.padding.right
  if sizes.space.h.isDefinite():
    sizes.space.h.u -= sizes.padding.top
    sizes.space.h.u -= sizes.padding.bottom
  box.state = BlockBoxLayoutState(positioned: sizes.positioned)
  var bctx = BlockContext(lctx: lctx)
  bctx.layoutFlow(box, sizes)
  assert bctx.unpositionedFloats.len == 0
  # Table cells ignore margins.
  box.state.offset.y = 0
  # If the highest float edge is higher than the box itself, set that as
  # the box height.
  box.state.size.h = max(box.state.size.h, bctx.maxFloatHeight)

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
    let rowspanFiller = CellWrapper(
      colspan: cellw.colspan,
      rowspan: cellw.rowspan,
      coli: n,
      real: cellw,
      last: cellw.grown == 0
    )
    ctx.cells.add(nil)
    ctx.cells[i] = rowspanFiller
    for i in n ..< n + cellw.colspan:
      ctx.width += pctx.cols[i].width
      ctx.width += pctx.inlineSpacing * 2
    n += cellw.colspan
    inc i
    inc growi

proc preLayoutTableRow(pctx: var TableContext; row, parent: BlockBox;
    rowi, numrows: int): RowContext =
  var ctx = RowContext(box: row, cells: newSeq[CellWrapper](row.nested.len))
  var n = 0
  var i = 0
  var growi = 0
  # this increases in the loop, but we only want to check growing cells that
  # were added by previous rows.
  let growlen = pctx.growing.len
  for box in row.nested:
    assert box.computed{"display"} == DisplayTableCell
    pctx.growRowspan(ctx, growi, i, n, growlen)
    let colspan = box.computed{"-cha-colspan"}
    let rowspan = min(box.computed{"-cha-rowspan"}, numrows - rowi)
    let cw = box.computed{"width"}
    let ch = box.computed{"height"}
    let space = availableSpace(
      w = cw.stretchOrMaxContent(pctx.lctx, pctx.space.w),
      h = ch.stretchOrMaxContent(pctx.lctx, pctx.space.h)
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
  row.state = BlockBoxLayoutState()
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
  for cell in row.nested:
    alignTableCell(cell, row.state.size.h, baseline)
    # cell position is final here; apply overflow dimensions
    row.applyOverflowDimensions(cell)
  row.state.size.w = x

proc preLayoutTableRows(tctx: var TableContext; rows: seq[BlockBox];
    table: BlockBox) =
  for i, row in rows:
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
  for child in table.nested:
    assert child.computed{"display"} in ProperTableChild
    case child.computed{"display"}
    of DisplayTableRow: tbody.add(child)
    of DisplayTableHeaderGroup: thead.add(child.nested)
    of DisplayTableRowGroup: tbody.add(child.nested)
    of DisplayTableFooterGroup: tfoot.add(child.nested)
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
  return W / totalSpecified

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

func needsRedistribution(tctx: TableContext; computed: CSSComputedValues):
    bool =
  case tctx.space.w.t
  of scMinContent, scMaxContent:
    return false
  of scStretch:
    return tctx.space.w.u != tctx.maxwidth
  of scFitContent:
    let u = tctx.space.w.u
    return u > tctx.maxwidth and not computed{"width"}.auto or u < tctx.maxwidth

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
  let space = availableSpace(w = stretch(parent.state.size.w), h = maxContent())
  var marginBottomOut: LayoutUnit
  tctx.lctx.layoutRootBlock(box, space, offset(x = 0, y = 0), marginBottomOut)
  box.state.offset.x += box.state.margin.left
  box.state.offset.y += box.state.margin.top
  let outerHeight = box.outerSize(dtVertical) + marginBottomOut
  let outerWidth = box.outerSize(dtHorizontal)
  let table = parent.nested[0]
  case box.computed{"caption-side"}
  of CaptionSideTop, CaptionSideBlockStart:
    table.state.offset.y += outerHeight
  of CaptionSideBottom, CaptionSideBlockEnd:
    box.state.offset.y += table.state.size.h
  parent.state.size.h += outerHeight
  parent.state.size.w = max(parent.state.size.w, outerWidth)

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
  let lctx = tctx.lctx
  if table.computed{"border-collapse"} != BorderCollapseCollapse:
    tctx.inlineSpacing = table.computed{"border-spacing"}.a.px(lctx)
    tctx.blockSpacing = table.computed{"border-spacing"}.b.px(lctx)
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
  let table = box.nested[0]
  table.state = BlockBoxLayoutState()
  var tctx = TableContext(lctx: bctx.lctx, space: sizes.space)
  tctx.layoutTable(table, sizes)
  box.state.size = table.state.size
  box.state.baseline = table.state.size.h
  box.state.firstBaseline = table.state.size.h
  if box.nested.len > 1:
    # do it here, so that caption's box can stretch to our width
    let caption = box.nested[1]
    #TODO also count caption width in table width
    tctx.layoutCaption(box, caption)
  #TODO overflow

proc postAlignChild(box, child: BlockBox; width: LayoutUnit) =
  case box.computed{"text-align"}
  of TextAlignChaCenter:
    child.state.offset.x += max(width div 2 - child.state.size.w div 2, 0)
  of TextAlignChaRight:
    child.state.offset.x += max(width - child.state.size.w -
      child.state.margin.right, 0)
  else: # TextAlignChaLeft or not block-aligned
    discard

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
  box.state = BlockBoxLayoutState(
    offset: offset(x = sizes.margin.left, y = 0),
    margin: sizes.margin,
    positioned: sizes.positioned
  )
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

  FlexMainContext = object
    totalSize: Size
    maxSize: Size
    maxMargin: RelativeRect
    totalWeight: array[FlexWeightType, float64]
    pending: seq[FlexPendingItem]

const FlexRow = {FlexDirectionRow, FlexDirectionRowReverse}

# This is practically the min-content size. For height, we just take the
# output height of the previous pass; for width, we take the shortest word's
# width (xminwidth).
func minFlexItemSize(state: BlockBoxLayoutState; dim: DimensionType):
    LayoutUnit =
  case dim
  of dtHorizontal: return state.xminwidth
  of dtVertical: return state.size.h

proc updateMaxSizes(mctx: var FlexMainContext; child: BlockBox) =
  for dim in DimensionType:
    mctx.maxSize[dim] = max(mctx.maxSize[dim], child.state.size[dim])
    mctx.maxMargin[dim].start = max(mctx.maxMargin[dim].start,
      child.state.margin[dim].start)
    mctx.maxMargin[dim].send = max(mctx.maxMargin[dim].send,
      child.state.margin[dim].send)

proc redistributeMainSize(mctx: var FlexMainContext; sizes: ResolvedSizes;
    dim: DimensionType; lctx: LayoutContext) =
  let odim = dim.opposite
  if sizes.space[dim].isDefinite:
    var diff = sizes.space[dim].u - mctx.totalSize[dim]
    let wt = if diff > 0: fwtGrow else: fwtShrink
    var totalWeight = mctx.totalWeight[wt]
    while (wt == fwtGrow and diff > 0 or wt == fwtShrink and diff < 0) and
        totalWeight > 0:
      # redo maxSize calculation; we only need height here
      mctx.maxSize[odim] = 0
      let unit = diff.toFloat64() / totalWeight
      # reset total weight & available diff for the next iteration (if there is
      # one)
      totalWeight = 0
      diff = 0
      for it in mctx.pending.mitems:
        if it.weights[wt] == 0:
          mctx.updateMaxSizes(it.child)
          continue
        var u = it.child.state.size[dim] +
          (unit * it.weights[wt]).toLayoutUnit()
        # check for min/max violation
        var minu = it.sizes.minMaxSizes[dim].start
        minu = max(it.child.state.minFlexItemSize(dim), minu)
        if minu > u:
          # min violation
          if wt == fwtShrink: # freeze
            diff += u - minu
            it.weights[wt] = 0
          u = minu
        let maxu = it.sizes.minMaxSizes[dim].send
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
        mctx.updateMaxSizes(it.child)

proc flushMain(fctx: var FlexContext; mctx: var FlexMainContext;
    sizes: ResolvedSizes; dim: DimensionType) =
  let odim = dim.opposite
  let lctx = fctx.lctx
  mctx.redistributeMainSize(sizes, dim, lctx)
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
    it.child.state.offset[odim] += offset[odim] +
      it.child.state.margin[odim].start
    offset[dim] += it.child.state.size[dim]
    offset[dim] += it.child.state.margin[dim].send
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
  var fctx = FlexContext(
    lctx: lctx,
    box: box,
    offset: offset(x = sizes.padding.left, y = sizes.padding.top)
  )
  var mctx = FlexMainContext()
  let flexDir = box.computed{"flex-direction"}
  let canWrap = box.computed{"flex-wrap"} != FlexWrapNowrap
  let dim = if flexDir in FlexRow: dtHorizontal else: dtVertical
  for child in box.nested:
    var childSizes = lctx.resolveFlexItemSizes(sizes.space, dim, child.computed)
    let flexBasis = child.computed{"flex-basis"}
    lctx.layoutFlexChild(child, childSizes)
    if not flexBasis.auto and childSizes.space[dim].isDefinite:
      # we can't skip this pass; the first pass is needed to calculate the
      # minimum height.
      let minu = child.state.minFlexItemSize(dim)
      childSizes.space[dim] = stretch(flexBasis.spx(lctx, sizes.space[dim],
        child.computed, childSizes.padding[dim].sum()))
      if minu > childSizes.space[dim].u:
        # First pass gave us a box that is smaller than the minimum acceptable
        # width whatever reason; this may have happened because the initial flex
        # basis was e.g. 0. Try to resize it to something more usable.
        childSizes.space[dim] = stretch(minu)
      lctx.layoutFlexChild(child, childSizes)
    if child.computed{"position"} == PositionAbsolute:
      # Absolutely positioned flex children do not participate in flex layout.
      lctx.positioned[^1].queue.add(QueuedAbsolute(
        child: child,
        offset: offset(x = 0, y = 0)
      ))
      continue
    if canWrap and (sizes.space[dim].t == scMinContent or
        sizes.space[dim].isDefinite and
        mctx.totalSize[dim] + child.state.size[dim] > sizes.space[dim].u):
      fctx.flushMain(mctx, sizes, dim)
    mctx.totalSize[dim] += child.outerSize(dim)
    mctx.updateMaxSizes(child)
    let grow = child.computed{"flex-grow"}
    let shrink = child.computed{"flex-shrink"}
    mctx.totalWeight[fwtGrow] += grow
    mctx.totalWeight[fwtShrink] += shrink
    mctx.pending.add(FlexPendingItem(
      child: child,
      weights: [grow, shrink],
      sizes: childSizes
    ))
  if mctx.pending.len > 0:
    fctx.flushMain(mctx, sizes, dim)
  box.applySize(sizes, fctx.totalMaxSize[dim], sizes.space, dim)
  box.applySize(sizes, fctx.offset[dim.opposite], sizes.space, dim.opposite)
  for child in fctx.relativeChildren:
    lctx.positionRelative(box, child)
    box.applyOverflowDimensions(child)
  box.state.overflow.finalize(box.state.size)
  if box.computed{"position"} notin PositionStaticLike:
    let space = availableSpace(
      w = stretch(box.state.size.w),
      h = stretch(box.state.size.h)
    )
    lctx.popPositioned(box.state.overflow, space)

# Build an outer block box inside an existing block formatting context.
proc layoutBlockChild(bctx: var BlockContext; box: BlockBox;
    space: AvailableSpace; offset: Offset; appendMargins: bool) =
  let sizes = bctx.lctx.resolveSizes(space, box.computed)
  if appendMargins:
    # for nested blocks that do not establish their own BFC, and thus take part
    # in margin collapsing.
    bctx.marginTodo.append(sizes.margin.top)
  box.state = BlockBoxLayoutState(
    offset: offset(x = offset.x + sizes.margin.left, y = offset.y),
    margin: sizes.margin,
    positioned: sizes.positioned
  )
  bctx.layout(box, sizes)
  if appendMargins:
    bctx.marginTodo.append(sizes.margin.bottom)

# Inner layout for boxes that establish a new block formatting context.
proc layoutRootBlock(lctx: LayoutContext; box: BlockBox;
    space: AvailableSpace; offset: Offset; marginBottomOut: var LayoutUnit) =
  var bctx = BlockContext(lctx: lctx)
  bctx.layoutBlockChild(box, space, offset, appendMargins = false)
  assert bctx.unpositionedFloats.len == 0
  marginBottomOut = bctx.marginTodo.sum()
  # If the highest float edge is higher than the box itself, set that as
  # the box height.
  box.state.size.h = max(box.state.size.h, bctx.maxFloatHeight -
    marginBottomOut)

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

# Outer layout for block-level children that establish a BFC.
# Returns the vertical size used (incl. margins).
proc layoutBlockChildBFC(state: var BlockState; bctx: var BlockContext;
    child: BlockBox): LayoutUnit =
  assert child.computed{"position"} != PositionAbsolute
  var marginBottomOut: LayoutUnit
  bctx.lctx.layoutRootBlock(child, state.space, state.offset,
    marginBottomOut)
  # Do not collapse margins of elements that do not participate in
  # the flow.
  if child.computed{"float"} == FloatNone:
    bctx.marginTodo.append(child.state.margin.top)
    bctx.flushMargins(child)
    bctx.positionFloats()
    bctx.marginTodo.append(child.state.margin.bottom)
    if child.computed{"clear"} != ClearNone:
      state.offset.clearFloats(bctx, child.computed{"clear"})
    if bctx.exclusions.len > 0:
      # Consulting the standard for an important edge case... (abridged)
      #
      # > The border box of an element that establishes a new BFC must not
      # > overlap the margin box of any floats in the same BFC as the
      # > element itself. If necessary, implementations should clear the
      # > said element, but may place it adjacent to such floats if there
      # > is sufficient space. CSS2 does not define when a UA may put said
      # > element next to the float.
      #
      # ...as expected. Thanks for nothing.
      #
      # OK here's what we do:
      # * run a normal pass
      # * place the longest word (i.e. xminwidth) somewhere
      # * run another pass with the placement we got
      #
      # I suspect this breaks horribly on some layouts, but I don't care
      # enough to make this convoluted garbage even more complex.
      #
      # Note that we do this only for elements in the flow. FF yanks
      # absolutely positioned elements on top of floats, and so do we.
      let pbfcOffset = bctx.bfcOffset
      let bfcOffset = offset(
        x = pbfcOffset.x + child.state.offset.x,
        y = max(pbfcOffset.y + child.state.offset.y, bctx.clearOffset)
      )
      let minSize = size(w = child.state.xminwidth, h = bctx.lctx.attrs.ppl)
      var outw: LayoutUnit
      let offset = bctx.findNextBlockOffset(bfcOffset, minSize,
        state.space, outw)
      let space = availableSpace(w = stretch(outw), h = state.space.h)
      bctx.lctx.layoutRootBlock(child, space, offset - pbfcOffset,
        marginBottomOut)
  else:
    child.state.offset.y += child.state.margin.top
    if state.isParentResolved(bctx):
      # If parent offset has been resolved, use marginTodo in this
      # float's initial offset.
      child.state.offset.y += bctx.marginTodo.sum()
  # delta y is difference between old and new offsets (margin-top), sum
  # of margin todo in bctx (margin-bottom) + height.
  return child.state.offset.y - state.offset.y + child.state.size.h +
    marginBottomOut

# Note: this does not include display types that cannot appear as block
# children.
func establishesBFC(computed: CSSComputedValues): bool =
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
  for child in parent.nested:
    var dy: LayoutUnit = 0 # delta
    if child.computed{"position"} == PositionAbsolute:
      # Delay this block's layout until its parent's dimensions are
      # actually known.
      var offset = state.offset
      # I *think* this is right, because we want to freeze the box at
      # the layout's current position. So even if a next child increased
      # the margin todo, that should not change the absolute block's
      # position.
      #TODO but I'm not sure if this is really what the standard says...
      offset.y += bctx.marginTodo.sum()
      bctx.lctx.positioned[^1].queue.add(QueuedAbsolute(
        child: child,
        offset: offset
      ))
      continue
    if child.computed.establishesBFC():
      dy = state.layoutBlockChildBFC(bctx, child)
    else:
      bctx.layoutBlockChild(child, state.space, state.offset,
        appendMargins = true)
      # delta y is difference between old and new offsets (margin-top),
      # plus height.
      dy = child.state.offset.y - state.offset.y + child.state.size.h
    let childWidth = child.outerSize(dtHorizontal)
    state.xminwidth = max(state.xminwidth, child.state.xminwidth)
    let isfloat = child.computed{"float"} != FloatNone
    if not isfloat:
      state.maxChildWidth = max(state.maxChildWidth, childWidth)
      state.offset.y += dy
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
      state.totalFloatWidth += childWidth
    else:
      state.maxChildWidth = max(state.maxChildWidth, childWidth)
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
      if bctx.marginTarget != state.initialMarginTarget:
        # y offset resolved
        bctx.positionFloat(child, state.space, bctx.parentBps.offset)
      else:
        bctx.unpositionedFloats.add(UnpositionedFloat(
          space: state.space,
          parentBps: bctx.parentBps,
          box: child,
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

# Re-position the children.
# The x offset with a fit-content width depends on the parent box's width,
# so we cannot do this in the first pass.
proc repositionChildren(state: BlockState; box: BlockBox; lctx: LayoutContext) =
  for child in box.nested:
    box.postAlignChild(child, box.state.size.w)
    if child.computed{"position"} == PositionRelative:
      lctx.positionRelative(box, child)
    # Set overflow here, after the child has been positioned.
    box.applyOverflowDimensions(child)

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
  if state.needsReLayout:
    state.initReLayout(bctx, box, sizes)
    state.layoutBlockChildren(bctx, box)
  if box.nested.len > 0:
    let lastNested = box.nested[^1]
    box.state.baseline = lastNested.state.offset.y + lastNested.state.baseline
  # Apply width, and height. For height, temporarily remove padding we have
  # applied before so that percentage resolution works correctly.
  # then move the inline offset of children that still need
  box.applyWidth(sizes, state.maxChildWidth, state.space)
  box.applyHeight(sizes, state.offset.y - sizes.padding.top)
  # Reposition here, as `position: relative' percentages can now be resolved.
  state.repositionChildren(box, lctx)
  # Add padding; we cannot do this further up without influencing positioning.
  box.applyPadding(sizes.padding)
  # Pass down relevant data from state.
  box.state.xminwidth = state.xminwidth
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
    let space = availableSpace(
      w = stretch(box.state.size.w),
      h = stretch(box.state.size.h)
    )
    lctx.popPositioned(box.state.overflow, space)

# 1st pass: build tree

proc newMarkerBox(computed: CSSComputedValues; listItemCounter: int):
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
  inline: RootInlineFragment

proc flushTable(ctx: var InnerBlockContext)

proc flushInlineGroup(ctx: var InnerBlockContext) =
  if ctx.inline != nil:
    ctx.flushTable()
    let computed = ctx.outer.computed.inheritProperties()
    computed{"display"} = DisplayBlock
    let box = BlockBox(computed: computed, inline: ctx.inline)
    ctx.outer.nested.add(box)
    ctx.inline = nil

# Don't build empty anonymous inline blocks between block boxes
func canBuildAnonInline(ctx: InnerBlockContext; computed: CSSComputedValues;
    str: string): bool =
  return ctx.inline != nil and ctx.inline.fragment.children.len > 0 or
    computed.whitespacepre or not str.onlyWhitespace()

proc buildBlock(ctx: var InnerBlockContext)
proc buildTable(ctx: var InnerBlockContext)
proc buildFlex(ctx: var InnerBlockContext)
proc buildInlineBoxes(ctx: var InnerBlockContext; styledNode: StyledNode;
  computed: CSSComputedValues)
proc buildTableRowGroup(parent: var InnerBlockContext; styledNode: StyledNode;
  computed: CSSComputedValues): BlockBox
proc buildTableRow(parent: var InnerBlockContext; styledNode: StyledNode;
  computed: CSSComputedValues): BlockBox
proc buildTableCell(parent: var InnerBlockContext; styledNode: StyledNode;
  computed: CSSComputedValues): BlockBox
proc buildTableCaption(parent: var InnerBlockContext; styledNode: StyledNode;
  computed: CSSComputedValues): BlockBox
proc newInnerBlockContext(styledNode: StyledNode; box: BlockBox;
  lctx: LayoutContext; parent: ptr InnerBlockContext): InnerBlockContext
proc pushInline(ctx: var InnerBlockContext; fragment: InlineFragment)
proc pushInlineBlock(ctx: var InnerBlockContext; styledNode: StyledNode;
  computed: CSSComputedValues)

func toTableWrapper(display: CSSDisplay): CSSDisplay =
  if display == DisplayTable:
    return DisplayTableWrapper
  assert display == DisplayInlineTable
  return DisplayInlineTableWrapper

proc createAnonTable(ctx: var InnerBlockContext; computed: CSSComputedValues):
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
      nested: @[innerTable]
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
      ctx.outer.nested.add(ctx.anonRow)
    else:
      let anonTableWrapper = ctx.createAnonTable(ctx.outer.computed)
      anonTableWrapper.nested[0].nested.add(ctx.anonRow)
    ctx.anonRow = nil

proc flushTable(ctx: var InnerBlockContext) =
  ctx.flushTableRow()
  if ctx.anonTableWrapper != nil:
    ctx.outer.nested.add(ctx.anonTableWrapper)
    ctx.anonTableWrapper = nil

proc flushInlineTableRow(ctx: var InnerBlockContext) =
  if ctx.inlineAnonRow != nil:
    # There is no way an inline anonymous row could be a child of an inline
    # table, since inline tables still act like blocks inside.
    let anonTableWrapper = ctx.createAnonTable(ctx.outer.computed)
    anonTableWrapper.nested[0].nested.add(ctx.inlineAnonRow)
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
    let fragment = InlineFragment(
      t: iftParent,
      computed: ctx.lctx.myRootProperties,
      children: @[box]
    )
    ctx.inline = RootInlineFragment(fragment: fragment)
  else:
    ctx.inline.fragment.children.add(box)

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
    computed: CSSComputedValues): BlockBox =
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
    computed: CSSComputedValues) =
  if (computed{"position"} == PositionAbsolute or
        computed{"float"} != FloatNone) and
      (ctx.inline != nil or ctx.inlineStack.len > 0):
    ctx.pushInlineBlock(styledNode, computed)
  else:
    ctx.iflush()
    ctx.flush()
    let box = ctx.buildSomeBlock(styledNode, computed)
    ctx.outer.nested.add(box)

proc pushInline(ctx: var InnerBlockContext; fragment: InlineFragment) =
  if ctx.inlineStack.len == 0:
    ctx.addInlineRoot(fragment)
  else:
    ctx.reconstructInlineParents()
    ctx.inlineStackFragments[^1].children.add(fragment)

proc pushInlineText(ctx: var InnerBlockContext; computed: CSSComputedValues;
    parent, node: StyledNode) =
  ctx.pushInline(InlineFragment(
    t: iftText,
    computed: computed,
    node: parent,
    text: node
  ))

proc pushInlineBlock(ctx: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSComputedValues) =
  ctx.pushInline(InlineFragment(
    t: iftBox,
    computed: computed.inheritProperties(),
    node: styledNode,
    box: ctx.buildSomeBlock(styledNode, computed)
  ))

proc pushListItem(ctx: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSComputedValues) =
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
      inline: RootInlineFragment(fragment: marker)
    )
    let wrapper = BlockBox(computed: computed, nested: @[marker, content])
    ctx.outer.nested.add(wrapper)
  of ListStylePositionInside:
    contentCtx.pushInline(marker)
    contentCtx.buildBlock()
    ctx.outer.nested.add(content)

proc pushTableRow(ctx: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSComputedValues) =
  let child = ctx.buildTableRow(styledNode, computed)
  if ctx.inlineStack.len == 0:
    ctx.iflush()
    ctx.flushInlineGroup()
    ctx.flushTableRow()
  else:
    ctx.flushInlineTableRow()
  if ctx.inlineStack.len == 0 and
      ctx.outer.computed{"display"} in ProperTableRowParent:
    ctx.outer.nested.add(child)
  else:
    let anonTableWrapper = ctx.createAnonTable(ctx.outer.computed)
    anonTableWrapper.nested[0].nested.add(child)

proc pushTableRowGroup(ctx: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSComputedValues) =
  let child = ctx.buildTableRowGroup(styledNode, computed)
  if ctx.inlineStack.len == 0:
    ctx.iflush()
    ctx.flushInlineGroup()
    ctx.flushTableRow()
  else:
    ctx.flushInlineTableRow()
  if ctx.inlineStack.len == 0 and
      ctx.outer.computed{"display"} in {DisplayTable, DisplayInlineTable}:
    ctx.outer.nested.add(child)
  else:
    ctx.flushTableRow()
    let anonTableWrapper = ctx.createAnonTable(ctx.outer.computed)
    anonTableWrapper.nested[0].nested.add(child)

proc pushTableCell(ctx: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSComputedValues) =
  let child = ctx.buildTableCell(styledNode, computed)
  if ctx.inlineStack.len == 0 and
      ctx.outer.computed{"display"} == DisplayTableRow:
    ctx.iflush()
    ctx.flushInlineGroup()
    ctx.outer.nested.add(child)
  else:
    let anonRow = ctx.createAnonRow()
    anonRow.nested.add(child)

proc pushTableCaption(ctx: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSComputedValues) =
  ctx.iflush()
  ctx.flushInlineGroup()
  ctx.flushTableRow()
  let child = ctx.buildTableCaption(styledNode, computed)
  if ctx.outer.computed{"display"} in {DisplayTable, DisplayInlineTable}:
    ctx.outer.nested.add(child)
  else:
    let anonTableWrapper = ctx.createAnonTable(ctx.outer.computed)
    # only add first caption
    if anonTableWrapper.nested.len == 1:
      anonTableWrapper.nested.add(child)

proc buildFromElem(ctx: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSComputedValues) =
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
    computed: CSSComputedValues) =
  case child.content.t
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
    computed: CSSComputedValues) =
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
  if ctx.outer.nested.len == 0:
    ctx.outer.inline = if ctx.inline != nil:
      ctx.inline
    else:
      RootInlineFragment(fragment: InlineFragment(
        t: iftParent,
        computed: ctx.lctx.myRootProperties
      ))
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
    ctx.outer.nested.reverse()

proc buildTableCell(parent: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSComputedValues): BlockBox =
  let box = BlockBox(node: styledNode, computed: computed)
  var ctx = newInnerBlockContext(styledNode, box, parent.lctx, addr parent)
  ctx.buildInnerBlock()
  ctx.flush()
  return box

proc buildTableRowChildWrappers(box: BlockBox) =
  var wrapperVals: CSSComputedValues = nil
  for child in box.nested:
    if child.computed{"display"} != DisplayTableCell:
      wrapperVals = box.computed.inheritProperties()
      wrapperVals{"display"} = DisplayTableCell
      break
  if wrapperVals != nil:
    # fixup row: put wrappers around runs of misparented children
    var nested = newSeqOfCap[BlockBox](box.nested.len)
    var wrapper: BlockBox = nil
    for child in box.nested:
      if child.computed{"display"} != DisplayTableCell:
        if wrapper == nil:
          wrapper = BlockBox(computed: wrapperVals)
          nested.add(wrapper)
        wrapper.nested.add(child)
      else:
        wrapper = nil
        nested.add(child)
    box.nested = nested

proc buildTableRow(parent: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSComputedValues): BlockBox =
  let box = BlockBox(node: styledNode, computed: computed)
  var ctx = newInnerBlockContext(styledNode, box, parent.lctx, addr parent)
  ctx.buildInnerBlock()
  ctx.flush()
  box.buildTableRowChildWrappers()
  return box

proc buildTableRowGroupChildWrappers(box: BlockBox) =
  var wrapperVals: CSSComputedValues = nil
  for child in box.nested:
    if child.computed{"display"} != DisplayTableRow:
      wrapperVals = box.computed.inheritProperties()
      wrapperVals{"display"} = DisplayTableRow
      break
  if wrapperVals != nil:
    # fixup row group: put wrappers around runs of misparented children
    var wrapper: BlockBox = nil
    var nested = newSeqOfCap[BlockBox](box.nested.len)
    for child in box.nested:
      if child.computed{"display"} != DisplayTableRow:
        if wrapper == nil:
          wrapper = BlockBox(computed: wrapperVals, nested: @[child])
        wrapper.nested.add(child)
        nested.add(wrapper)
      else:
        if wrapper != nil:
          wrapper.buildTableRowChildWrappers()
          wrapper = nil
        nested.add(child)
    if wrapper != nil:
      wrapper.buildTableRowChildWrappers()
    box.nested = nested

proc buildTableRowGroup(parent: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSComputedValues): BlockBox =
  let box = BlockBox(node: styledNode, computed: computed)
  var ctx = newInnerBlockContext(styledNode, box, parent.lctx, addr parent)
  ctx.buildInnerBlock()
  ctx.flush()
  box.buildTableRowGroupChildWrappers()
  return box

proc buildTableCaption(parent: var InnerBlockContext; styledNode: StyledNode;
    computed: CSSComputedValues): BlockBox =
  let box = BlockBox(node: styledNode, computed: computed)
  var ctx = newInnerBlockContext(styledNode, box, parent.lctx, addr parent)
  ctx.buildInnerBlock()
  ctx.flush()
  return box

proc buildTableChildWrappers(box: BlockBox; computed: CSSComputedValues) =
  let innerTable = BlockBox(computed: computed, node: box.node)
  let wrapperVals = box.computed.inheritProperties()
  wrapperVals{"display"} = DisplayTableRow
  var caption: BlockBox = nil
  var wrapper: BlockBox = nil
  for child in box.nested:
    if child.computed{"display"} in ProperTableChild:
      if wrapper != nil:
        wrapper.buildTableRowChildWrappers()
        wrapper = nil
      innerTable.nested.add(child)
    elif child.computed{"display"} == DisplayTableCaption:
      if caption == nil:
        caption = child
    else:
      if wrapper == nil:
        wrapper = BlockBox(computed: wrapperVals)
      wrapper.nested.add(child)
      innerTable.nested.add(wrapper)
  if wrapper != nil:
    wrapper.buildTableRowChildWrappers()
  box.nested = @[innerTable]
  if caption != nil:
    box.nested.add(caption)

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
    positioned: @[PositionedItem()],
    myRootProperties: rootProperties(),
    imgText: newStyledText("[img]"),
    videoText: newStyledText("[video]"),
    audioText: newStyledText("[audio]")
  )
  let box = BlockBox(computed: root.computed, node: root)
  var ctx = newInnerBlockContext(root, box, lctx, nil)
  ctx.buildBlock()
  var marginBottomOut: LayoutUnit
  lctx.layoutRootBlock(box, space, offset(x = 0, y = 0), marginBottomOut)
  lctx.popPositioned(box.state.overflow, space)
  return box
