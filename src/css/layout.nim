{.push raises: [].}

import std/math

import css/box
import css/cssparser
import css/cssvalues
import css/lunit
import types/bitmap
import types/color
import types/winattrs
import utils/luwrap
import utils/strwidth
import utils/twtstr
import utils/widthconv

type
  LayoutContext = ref object
    cellSize: Size # size(w = attrs.ppc, h = attrs.ppl)
    luctx: LUContext

const DefaultSpan = Span(start: 0, send: LUnit.high)

proc minWidth(sizes: ResolvedSizes): LUnit =
  return sizes.bounds.a[dtHorizontal].start

proc maxWidth(sizes: ResolvedSizes): LUnit =
  return sizes.bounds.a[dtHorizontal].send

proc minHeight(sizes: ResolvedSizes): LUnit =
  return sizes.bounds.a[dtVertical].start

proc maxHeight(sizes: ResolvedSizes): LUnit =
  return sizes.bounds.a[dtVertical].send

proc sum(span: Span): LUnit =
  return span.start + span.send

proc sum(rect: RelativeRect): Size =
  return [
    dtHorizontal: rect[dtHorizontal].sum(),
    dtVertical: rect[dtVertical].sum()
  ]

proc startOffset(rect: RelativeRect): Offset =
  return offset(x = rect[dtHorizontal].start, y = rect[dtVertical].start)

proc opposite(dim: DimensionType): DimensionType =
  case dim
  of dtHorizontal: return dtVertical
  of dtVertical: return dtHorizontal

proc availableSpace(w, h: SizeConstraint): AvailableSpace =
  return [dtHorizontal: w, dtVertical: h]

proc w(space: AvailableSpace): SizeConstraint {.inline.} =
  return space[dtHorizontal]

proc w(space: var AvailableSpace): var SizeConstraint {.inline.} =
  return space[dtHorizontal]

proc `w=`(space: var AvailableSpace; w: SizeConstraint) {.inline.} =
  space[dtHorizontal] = w

proc h(space: var AvailableSpace): var SizeConstraint {.inline.} =
  return space[dtVertical]

proc h(space: AvailableSpace): SizeConstraint {.inline.} =
  return space[dtVertical]

proc `h=`(space: var AvailableSpace; h: SizeConstraint) {.inline.} =
  space[dtVertical] = h

proc measure(): SizeConstraint =
  return SizeConstraint(t: scMeasure)

proc maxContent(): SizeConstraint =
  return SizeConstraint(t: scMaxContent)

proc stretch(u: LUnit): SizeConstraint =
  return SizeConstraint(t: scStretch, u: u)

proc fitContent(u: LUnit): SizeConstraint =
  return SizeConstraint(t: scFitContent, u: u)

proc fitContent(sc: SizeConstraint): SizeConstraint =
  case sc.t
  of scMinContent, scMaxContent, scMeasure:
    return sc
  of scStretch, scFitContent:
    return SizeConstraint(t: scFitContent, u: sc.u)

proc isDefinite(sc: SizeConstraint): bool =
  return sc.t in {scStretch, scFitContent}

proc canpx(l: CSSLength; sc: SizeConstraint): bool =
  return not l.auto and (l.perc == 0 or sc.t == scStretch)

proc px(l: CSSLength; p: LUnit): LUnit {.inline.} =
  if l.auto:
    return 0
  return (p.toFloat32() * l.perc + l.npx).toLUnit()

proc px(l: CSSLength; p: SizeConstraint): LUnit {.inline.} =
  if l.perc == 0:
    return l.npx.toLUnit()
  if l.auto:
    return 0
  if p.t == scStretch:
    return (p.u.toFloat32() * l.perc + l.npx).toLUnit()
  return 0

proc stretchOrMeasure(l: CSSLength; sc: SizeConstraint): SizeConstraint =
  if l.canpx(sc):
    return stretch(l.px(sc))
  return measure()

proc stretchOrMaxContent(l: CSSLength; sc: SizeConstraint): SizeConstraint =
  if l.canpx(sc):
    return stretch(l.px(sc))
  return maxContent()

proc applySizeConstraint(u: LUnit; availableSize: SizeConstraint): LUnit =
  case availableSize.t
  of scStretch:
    return availableSize.u
  of scMinContent, scMaxContent, scMeasure:
    # must be calculated elsewhere...
    return u
  of scFitContent:
    return min(u, availableSize.u)

proc borderTopLeft(sizes: ResolvedSizes; lctx: LayoutContext): Offset =
  var o = offset(0, 0)
  if sizes.border.left notin BorderStyleNoneHidden:
    o.x += lctx.cellSize.w
  if sizes.border.top notin BorderStyleNoneHidden:
    o.y += lctx.cellSize.h
  o

proc borderSize(sizes: ResolvedSizes; dim: DimensionType; lctx: LayoutContext):
    Span =
  var span = Span()
  if sizes.border[dim].start notin BorderStyleNoneHidden:
    span.start = lctx.cellSize[dim]
  if sizes.border[dim].send notin BorderStyleNoneHidden and
      (dim == dtHorizontal or sizes.border[dim].send notin BorderStyleInput):
    span.send = lctx.cellSize[dim]
  return span

proc outerSize(box: BlockBox; dim: DimensionType; sizes: ResolvedSizes;
    lctx: LayoutContext): LUnit =
  return sizes.margin[dim].sum() + box.state.size[dim] +
    sizes.borderSize(dim, lctx).sum()

proc outerSize(box: BlockBox; sizes: ResolvedSizes; lctx: LayoutContext): Size =
  return size(
    w = box.outerSize(dtHorizontal, sizes, lctx),
    h = box.outerSize(dtVertical, sizes, lctx)
  )

proc max(span: Span): LUnit =
  return max(span.start, span.send)

# In CSS, "min" beats "max".
proc minClamp(x: LUnit; span: Span): LUnit =
  return max(min(x, span.send), span.start)

# Note: padding must still be applied after this.
proc applySize(box: BlockBox; bounds: Bounds; maxChildSize: LUnit;
    space: AvailableSpace; dim: DimensionType) =
  # Make the box as small/large as the content's width or specified width.
  box.state.size[dim] = maxChildSize.applySizeConstraint(space[dim])
  # Then, clamp it to minWidth and maxWidth (if applicable).
  box.state.size[dim] = box.state.size[dim].minClamp(bounds.a[dim])

proc applySize(box: BlockBox; sizes: ResolvedSizes; maxChildSize: Size;
    space: AvailableSpace) =
  for dim in DimensionType:
    box.applySize(sizes.bounds, maxChildSize[dim], space, dim)

proc applyIntr(box: BlockBox; sizes: ResolvedSizes; intr: Size) =
  for dim in DimensionType:
    const pt = [dtHorizontal: cptOverflowX, dtVertical: cptOverflowY]
    if box.computed.bits[pt[dim]].overflow notin OverflowScrollLike:
      box.state.intr[dim] = intr[dim].minClamp(sizes.bounds.mi[dim])
    else:
      # We do not have a scroll bar, so do the next best thing: expand the
      # box to the size its contents want.  (Or the specified size, if
      # it's greater.)
      #TODO intrinsic minimum size isn't really guaranteed to equal the
      # desired scroll size. Also, it's possible that a parent box clamps
      # the height of this box; in that case, the parent box's
      # width/height should be clamped to the inner scroll width/height
      # instead.
      box.state.intr[dim] = max(intr[dim], sizes.bounds.mi[dim].start)
      box.state.size[dim] = max(box.state.size[dim], intr[dim])

# Size resolution for all layouts.
const MarginStartMap = [
  dtHorizontal: cptMarginLeft,
  dtVertical: cptMarginTop
]

const MarginEndMap = [
  dtHorizontal: cptMarginRight,
  dtVertical: cptMarginBottom
]

proc spx(l: CSSLength; p: SizeConstraint; computed: CSSValues;
    padding: LUnit): LUnit =
  let u = l.px(p)
  if computed{"box-sizing"} == BoxSizingBorderBox:
    return max(u - padding, 0)
  return max(u, 0)

proc resolveUnderflow(sizes: var ResolvedSizes; parentSize: SizeConstraint;
    computed: CSSValues; lctx: LayoutContext) =
  let dim = dtHorizontal
  # width must be definite, so that conflicts can be resolved
  if sizes.space[dim].isDefinite() and parentSize.t == scStretch:
    let start = computed.getLength(MarginStartMap[dim])
    let send = computed.getLength(MarginEndMap[dim])
    let underflow = parentSize.u - sizes.space[dim].u -
      sizes.margin[dim].sum() - sizes.padding[dim].sum() -
      sizes.borderSize(dim, lctx).sum()
    if underflow > 0 and start.auto:
      if not send.auto:
        sizes.margin[dim].start = underflow
      else:
        sizes.margin[dim].start = underflow div 2

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

proc roundSmallMarginsAndPadding(lctx: LayoutContext;
    sizes: var ResolvedSizes) =
  for i, it in sizes.padding.mpairs:
    let cs = lctx.cellSize[i]
    it.start = (it.start div cs).toInt.toLUnit * cs
    it.send = (it.send div cs).toInt.toLUnit * cs
  for i, it in sizes.margin.mpairs:
    let cs = lctx.cellSize[i]
    it.start = (it.start div cs).toInt.toLUnit * cs
    it.send = (it.send div cs).toInt.toLUnit * cs

proc resolveBorder(computed: CSSValues): CSSBorder =
  var left = computed{"border-left-style"}
  var right = computed{"border-right-style"}
  var top = computed{"border-top-style"}
  var bottom = computed{"border-bottom-style"}
  if computed{"border-left-width"} == 0 or
      computed{"border-left-color"}.rgbTransparent:
    left = BorderStyleNone
  if computed{"border-right-width"} == 0 or
      computed{"border-right-color"}.rgbTransparent:
    right = BorderStyleNone
  if computed{"border-top-width"} == 0 or
      computed{"border-top-color"}.rgbTransparent:
    top = BorderStyleNone
  if computed{"border-bottom-width"} == 0 or
      computed{"border-bottom-color"}.rgbTransparent:
    bottom = BorderStyleNone
  return [
    dtHorizontal: BorderStyleSpan(start: left, send: right),
    dtVertical: BorderStyleSpan(start: top, send: bottom)
  ]

proc resolvePositioned(lctx: LayoutContext; size: Size;
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
  mi: [DefaultSpan, DefaultSpan]
)

const SizeMap = [dtHorizontal: cptWidth, dtVertical: cptHeight]
const MinSizeMap = [dtHorizontal: cptMinWidth, dtVertical: cptMinHeight]
const MaxSizeMap = [dtHorizontal: cptMaxWidth, dtVertical: cptMaxHeight]

proc resolveBounds(lctx: LayoutContext; space: AvailableSpace; padding: Size;
    computed: CSSValues; flexItem = false): Bounds =
  var res = DefaultBounds
  for dim in DimensionType:
    let sc = space[dim]
    let padding = padding[dim]
    if computed.getLength(MaxSizeMap[dim]).canpx(sc):
      let px = computed.getLength(MaxSizeMap[dim]).spx(sc, computed, padding)
      res.a[dim].send = px
      res.mi[dim].send = px
    if computed.getLength(MinSizeMap[dim]).canpx(sc):
      let px = computed.getLength(MinSizeMap[dim]).spx(sc, computed, padding)
      res.a[dim].start = px
      if computed.getLength(MinSizeMap[dim]).isPx:
        res.mi[dim].start = px
        if flexItem: # for flex items, min-width overrides the intrinsic size.
          res.mi[dim].send = px
  return res

proc resolveAbsoluteWidth(lctx: LayoutContext; size: Size;
    positioned: RelativeRect; computed: CSSValues; sizes: var ResolvedSizes) =
  let paddingSum = sizes.padding[dtHorizontal].sum()
  if computed{"width"}.auto:
    let u = max(size.w - positioned[dtHorizontal].sum() - paddingSum -
      sizes.margin[dtHorizontal].sum(), 0)
    if not computed{"left"}.auto and not computed{"right"}.auto:
      # Both left and right are known, so we can calculate the width.
      sizes.space.w = stretch(u)
    else:
      # Return shrink to fit and solve for left/right.
      sizes.space.w = fitContent(u)
  else:
    let sizepx = computed{"width"}.spx(stretch(size.w), computed, paddingSum)
    sizes.space.w = stretch(sizepx)

proc resolveAbsoluteHeight(lctx: LayoutContext; size: Size;
    positioned: RelativeRect; computed: CSSValues; sizes: var ResolvedSizes) =
  let paddingSum = sizes.padding[dtVertical].sum()
  if computed{"height"}.auto:
    if not computed{"top"}.auto and not computed{"bottom"}.auto:
      # Both top and bottom are known, so we can calculate the height.
      # Well, but subtract padding and margin first.
      let u = max(size.h - positioned[dtVertical].sum() - paddingSum -
        sizes.margin[dtVertical].sum(), 0)
      sizes.space.h = stretch(u)
    else:
      # The height is based on the content.
      sizes.space.h = maxContent()
  else:
    let sizepx = computed{"height"}.spx(stretch(size.h), computed, paddingSum)
    sizes.space.h = stretch(sizepx)

# Calculate and resolve available width & height for absolutely positioned
# boxes.
proc resolveAbsoluteSizes(lctx: LayoutContext; size: Size;
    positioned: RelativeRect; computed: CSSValues): ResolvedSizes =
  var sizes = ResolvedSizes(
    margin: lctx.resolveMargins(stretch(size.w), computed),
    padding: lctx.resolvePadding(stretch(size.w), computed),
    bounds: DefaultBounds,
    border: computed.resolveBorder()
  )
  lctx.resolveAbsoluteWidth(size, positioned, computed, sizes)
  lctx.resolveAbsoluteHeight(size, positioned, computed, sizes)
  return sizes

# Calculate and resolve available width & height for floating boxes.
proc resolveFloatSizes(lctx: LayoutContext; space: AvailableSpace;
    computed: CSSValues): ResolvedSizes =
  var sizes = ResolvedSizes(
    margin: lctx.resolveMargins(space.w, computed),
    padding: lctx.resolvePadding(space.w, computed),
    space: space,
    border: computed.resolveBorder()
  )
  if computed{"display"} in DisplayInlineBlockLike:
    lctx.roundSmallMarginsAndPadding(sizes)
  let paddingSum = sizes.padding.sum()
  sizes.bounds = lctx.resolveBounds(space, paddingSum, computed)
  sizes.space.h = maxContent()
  for dim in DimensionType:
    let length = computed.getLength(SizeMap[dim])
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
    bounds: lctx.resolveBounds(space, paddingSum, computed, flexItem = true),
    border: computed.resolveBorder()
  )
  if dim != dtHorizontal:
    sizes.space.h = maxContent()
  let length = computed.getLength(SizeMap[dim])
  if length.canpx(space[dim]):
    let u = length.spx(space[dim], computed, paddingSum[dim])
      .minClamp(sizes.bounds.a[dim])
    sizes.space[dim] = stretch(u)
    if computed{"flex-shrink"} == 0:
      sizes.bounds.mi[dim].start = max(u, sizes.bounds.mi[dim].start)
    if computed{"flex-grow"} == 0:
      sizes.bounds.mi[dim].send = min(u, sizes.bounds.mi[dim].send)
  elif space[dim].t == scStretch and sizes.bounds.a[dim].send < LUnit.high:
    sizes.space[dim] = stretch(sizes.bounds.a[dim].max())
  else:
    # Ensure that space is indefinite in the first pass if no width has
    # been specified.
    sizes.space[dim] = maxContent()
  let odim = dim.opposite()
  let olength = computed.getLength(SizeMap[odim])
  if olength.canpx(space[odim]):
    let u = olength.spx(space[odim], computed, paddingSum[odim])
      .minClamp(sizes.bounds.a[odim])
    sizes.space[odim] = stretch(u)
    if olength.isPx:
      sizes.bounds.mi[odim].start = max(u, sizes.bounds.mi[odim].start)
      sizes.bounds.mi[odim].send = min(u, sizes.bounds.mi[odim].send)
  elif sizes.space[odim].isDefinite():
    let u = sizes.space[odim].u - sizes.margin[odim].sum() - paddingSum[odim]
    sizes.space[odim] = SizeConstraint(
      t: sizes.space[odim].t,
      u: minClamp(u, sizes.bounds.a[odim])
    )
    if computed.getLength(MarginStartMap[odim]).auto or
        computed.getLength(MarginEndMap[odim]).auto:
      sizes.space[odim].t = scFitContent
  elif sizes.bounds.a[odim].send < LUnit.high:
    sizes.space[odim] = stretch(sizes.bounds.a[odim].max())
  return sizes

proc resolveBlockWidth(sizes: var ResolvedSizes; parentWidth: SizeConstraint;
    inlinePadding: LUnit; computed: CSSValues;
    lctx: LayoutContext) =
  let dim = dtHorizontal
  let width = computed{"width"}
  if width.canpx(parentWidth):
    sizes.space.w = stretch(width.spx(parentWidth, computed, inlinePadding))
    sizes.resolveUnderflow(parentWidth, computed, lctx)
    if width.isPx:
      let px = sizes.space.w.u
      sizes.bounds.mi[dim].start = max(sizes.bounds.mi[dim].start, px)
      sizes.bounds.mi[dim].send = min(sizes.bounds.mi[dim].send, px)
  elif parentWidth.t == scStretch:
    let underflow = parentWidth.u - sizes.margin[dim].sum() -
      sizes.padding[dim].sum() - sizes.borderSize(dim, lctx).sum()
    if underflow >= 0:
      sizes.space.w = stretch(underflow)
    else:
      sizes.space.w = stretch(0)
      sizes.margin[dtHorizontal].send += underflow
  if sizes.space.w.isDefinite() and sizes.maxWidth < sizes.space.w.u or
      sizes.maxWidth < LUnit.high and
      sizes.space.w.t in {scMaxContent, scMeasure}:
    if sizes.space.w.t == scStretch:
      # available width would stretch over max-width
      sizes.space.w = stretch(sizes.maxWidth)
    else: # scFitContent
      # available width could be higher than max-width (but not necessarily)
      sizes.space.w = fitContent(sizes.maxWidth)
    sizes.resolveUnderflow(parentWidth, computed, lctx)
    sizes.bounds.mi[dim].send = sizes.space.w.u
  if sizes.space.w.isDefinite() and sizes.minWidth > sizes.space.w.u or
      sizes.minWidth > 0 and sizes.space.w.t == scMinContent:
    # two cases:
    # * available width is stretched under min-width. in this case,
    #   stretch to min-width instead.
    # * available width is fit under min-width. in this case, stretch to
    #   min-width as well (as we must satisfy min-width >= width).
    sizes.space.w = stretch(sizes.minWidth)
    sizes.resolveUnderflow(parentWidth, computed, lctx)

proc resolveBlockHeight(sizes: var ResolvedSizes; parentHeight: SizeConstraint;
    blockPadding: LUnit; computed: CSSValues;
    lctx: LayoutContext) =
  let dim = dtVertical
  let height = computed{"height"}
  if height.canpx(parentHeight):
    let px = height.spx(parentHeight, computed, blockPadding)
    sizes.space.h = stretch(px)
    if height.isPx:
      sizes.bounds.mi[dim].start = max(sizes.bounds.mi[dim].start, px)
      sizes.bounds.mi[dim].send = min(sizes.bounds.mi[dim].send, px)
  if sizes.space.h.isDefinite() and sizes.maxHeight < sizes.space.h.u or
      sizes.maxHeight < LUnit.high and
      sizes.space.h.t in {scMaxContent, scMeasure}:
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
    bounds: lctx.resolveBounds(space, paddingSum, computed),
    border: computed.resolveBorder()
  )
  # height is max-content normally, but fit-content for clip.
  sizes.space.h = if computed{"overflow-y"} != OverflowClip:
    maxContent()
  else:
    fitContent(sizes.space.h)
  # Finally, calculate available width and height.
  sizes.resolveBlockWidth(space.w, paddingSum[dtHorizontal], computed, lctx)
  #TODO parent height should be lctx height in quirks mode for percentage
  # resolution.
  sizes.resolveBlockHeight(space.h, paddingSum[dtVertical], computed, lctx)
  if computed{"display"} == DisplayListItem:
    # Eliminate distracting margins and padding here, because
    # resolveBlockWidth may change them beforehand.
    lctx.roundSmallMarginsAndPadding(sizes)
  if sizes.space.h.isDefinite() and sizes.space.h.u == 0 and
      paddingSum[dtVertical] == 0 and
      sizes.border.bottom notin BorderStyleInput:
    # prevent ugly <hr> when set using border (not just border-style-bottom)
    sizes.border[dtHorizontal] = BorderStyleSpan()
    if sizes.border[dtVertical].send notin BorderStyleNoneHidden:
      sizes.border[dtVertical].start = BorderStyleHidden
  return sizes

# Flow layout.  Probably the most complex part of CSS.
#
# One would be excused for thinking that flow can be subdivided into
# "inline" and "block" layouts.  This approach isn't exactly wrong -
# indeed, it seems to be the most intuitive interpretation of CSS 2.1,
# and is how I first did it - but mainstream browsers behave otherwise,
# so it is more useful to recognize flow as a single layout type.
#
# Flow is rooted in any block box that establishes a Block Formatting
# Context (BFC)[1].  State associated with these is represented by the
# BlockContext object.
# Then, flow includes further child "boxes"[2] of the following types:
#
# * Inline.  These may contain further inline boxes, text, images,
#   or block boxes (!).
# * Block that does not establish a BFC.  Contents of these flow around
#   floats in the same BFC, for example.
# * Block that establishes a BFC.  There are two kinds of these:
#   floats, which grow the exclusion zone, and flow roots (e.g.
#   overflow: hidden), which try to fit into the exclusion zone while
#   maintaining a rectangular shape.
# * position: absolute.  This does not really affect flow, but has some
#   bizarre rules regarding its positioning that makes it particularly
#   tricky to implement.
#
# [1]: For example, the root box, boxes with `overflow: hidden', floated
# boxes or flex items all establish a new BFC.
#
# [2]: Thinking of these as "boxes" is somewhat misleading, since any
# box that doesn't establish a new BFC may fragment (e.g. text with a
# line break, or a block child.)
#
## Anonymous block boxes
#
# Blocks nested in inlines are tricky.  Consider this fragment:
# <div id=a><span id=b>1<div id=c>2</div>3</span></div>
#
# One interpretation of this (this is how Chawan used to behave):
#
# * div#a
#   * anonymous block
#     * span#b (split)
#       * anonymous inline
#         * 1
#   * div#c
#     * anonymous inline
#       * 2
#   * anonymous block
#     * span#b (split)
#       * anonymous inline
#         * 3
#
# This has several issues.  For one, out-of-flow boxes (e.g. if div#c is
# a float, or absolute) must still be placed inside the inline box.
# Also, it isn't how mainstream browsers implement this[3], so you end
# up chasing strange bugs that arise from this implementation detail
# (go figure.)
#
# Therefore, Chawan now generates this tree:
#
# * div#a
#   * span#b
#     * anonymous inline
#       * 1
#     * div#c
#       * anonymous inline
#         * 2
#     * anonymous inline
#       * 3
#
# and blocks that come after inlines simply flush the current line box.
#
# [3]: The spec itself does not even mention this case, but there is a
# resolution that agrees with our new implementation:
# https://github.com/w3c/csswg-drafts/issues/1477
#
## Floats
#
# Floats have three issues that make their implementation less than
# straightforward:
#
# * They aren't constrained to their parent block, but their parent
#   BFC.  So while they do not affect previously laid out blocks, they
#   do affect subsequent siblings of their parent/grandparent/etc.
#   (Solved by adding exclusions to a BFC, and offsetting blocks/inlines
#   by their relative position to the BFC when considering exclusions.)
#
# * They *do* affect previous inlines.  e.g. this puts the float to
#   the left of "second":
#   <span>second<div style="float: left">first</div></span>
#   So floats must be processed before flushing a line box (solved using
#   unpositionedFloats in LineBoxState).
#
# * Consider this:
#   <div style="margin-top: 1em">
#   <div style="float: left">float</div>
#   <div style="margin-top: 2em"></div>
#   </div>
#   The float moves to 2em from the top, not 1em!
#   This means that floats can only be positioned once their parent's
#   margin is known.  (Solved using unpositionedFloats in BlockContext.)
#
## Margin collapsing
#
# We use a linked list to store boxes with unresolved margins for some
# reason.  Then we call flushMargins occasionally and hope for the best.
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
    maxFloatHeight: LUnit
    clearOffset: LUnit
    # Index of the first uncleared float per float value.
    # The highest value of clear: both is stored in FloatNone.
    clearIndex: array[CSSFloat, int]

  UnpositionedFloat = object
    parentBps: BlockPositionState
    space: AvailableSpace
    box: BlockBox
    marginOffset: Offset
    outerSize: Size
    newLine: bool # relevant in inline only; "should we put this on a new line?"

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
    pos: LUnit
    neg: LUnit

  LineInitState = enum
    lisUninited, lisNoExclusions, lisExclusions

  LineBoxState = object
    iastates: seq[InlineAtomState]
    charwidth: int
    paddingTodo: seq[tuple[box: InlineBox; i: int]]
    size: Size
    unpositionedFloats: seq[UnpositionedFloat]
    # Set at the end of layoutText. It helps determine the beginning of the
    # next inline box.
    widthAfterWhitespace: LUnit
    availableWidth: LUnit # actual place available after float exclusions
    intrh: LUnit # intrinsic minimum height
    totalFloatWidth: LUnit
    baseline: LUnit
    # Line boxes start in an uninited state.  When something is placed
    # on the line box, we call initLine to
    # * flush margins and position floats
    # * check the relevant exclusions and resize the line appropriately
    init: LineInitState
    # float values currently included in unpositionedFloats.
    floatsSeen: set[CSSFloat]

  InlineAtomState = object
    vertalign: CSSVerticalAlign
    baseline: LUnit
    ibox: InlineBox
    run: TextRun
    offset: Offset
    size: Size
    baselineShift: CSSLength

  InlineState = object
    ibox: InlineBox
    # we do not want to collapse newlines over tag boundaries, so these are
    # in state
    lastrw: int # last rune width of the previous word
    firstrw: int # first rune width of the current word
    prevrw: int # last processed rune's width

  FlowState = object
    box: BlockBox
    pbctx: ptr BlockContext
    offset: Offset
    maxChildWidth: LUnit
    totalFloatWidth: LUnit # used for re-layouts
    space: AvailableSpace
    intr: Size
    prevParentBps: BlockPositionState
    # State kept for when a re-layout is necessary:
    oldMarginTodo: Strut
    oldExclusionsLen: int
    initialMarginTarget: BlockPositionState
    initialTargetOffset: Offset
    textAlign: CSSTextAlign # text align of parent, for block-level alignment
    # Inline context state:
    lbstate: LineBoxState
    whitespacenum: int
    whitespaceBox: InlineTextBox
    word: InlineAtomState
    wordIntrSize: LUnit # intrinsic size of currently processed word segment
    wrappos: int # position of last wrapping opportunity, or -1
    lastTextBox: InlineBox
    padding: RelativeRect
    hasshy: bool
    whitespaceIsLF: bool

# Forward declarations
proc layout(bctx: var BlockContext; box: BlockBox; offset: Offset;
  sizes: ResolvedSizes; forceRoot = false)

iterator relevantExclusions(bctx: BlockContext): lent Exclusion {.inline.} =
  for i in bctx.clearIndex[FloatNone] ..< bctx.exclusions.len:
    yield bctx.exclusions[i]

iterator relevantExclusionPairs(bctx: BlockContext):
    tuple[i: int; ex: lent Exclusion] {.inline.} =
  for i in bctx.clearIndex[FloatNone] ..< bctx.exclusions.len:
    yield (i, bctx.exclusions[i])

proc initBlockContext(lctx: LayoutContext): BlockContext =
  BlockContext(lctx: lctx)

template bctx(fstate: FlowState): BlockContext =
  fstate.pbctx[]

template lctx(fstate: FlowState): LayoutContext =
  fstate.bctx.lctx

proc whitespacepre(computed: CSSValues): bool =
  computed{"white-space"} in {WhitespacePre, WhitespacePreLine,
    WhitespacePreWrap}

proc nowrap(computed: CSSValues): bool =
  computed{"white-space"} in {WhitespaceNowrap, WhitespacePre}

template cellSize(fstate: FlowState): Size =
  fstate.lctx.cellSize

template computed(fstate: FlowState): CSSValues =
  fstate.box.computed

proc bfcOffset(bctx: BlockContext): Offset =
  if bctx.parentBps != nil:
    return bctx.parentBps.offset
  return offset(x = 0, y = 0)

template bfcOffset(fstate: FlowState): Offset =
  fstate.bctx.bfcOffset

proc append(a: var Strut; b: LUnit) =
  if b < 0:
    a.neg = min(b, a.neg)
  else:
    a.pos = max(b, a.pos)

proc sum(a: Strut): LUnit =
  return a.pos + a.neg

proc clearFloats(offsety: var LUnit; bctx: var BlockContext;
    bfcOffsety: LUnit; clear: CSSClear) =
  var y = bfcOffsety + offsety
  let target = case clear
  of ClearLeft, ClearInlineStart: FloatLeft
  of ClearRight, ClearInlineEnd: FloatRight
  of ClearBoth, ClearNone: FloatNone
  var j = bctx.clearIndex[target] - 1
  for i, ex in bctx.relevantExclusionPairs:
    if ex.t == target or target == FloatNone:
      let iy = ex.offset.y + ex.size.h
      if iy > y:
        y = iy
        j = i
  bctx.clearOffset = y
  bctx.clearIndex[target] = j + 1
  if target != FloatNone:
    let k = min(bctx.clearIndex[FloatLeft], bctx.clearIndex[FloatRight])
    bctx.clearIndex[FloatNone] = max(bctx.clearIndex[FloatNone], k)
  offsety = y - bfcOffsety

proc findNextFloatOffset(bctx: BlockContext; offset: Offset; size: Size;
    space: AvailableSpace; float: CSSFloat; outw: var LUnit): Offset =
  # Algorithm originally from QEmacs.
  var y = offset.y
  let leftStart = offset.x
  let rightStart = offset.x + max(size.w, space.w.u)
  while true:
    var left = leftStart
    var right = rightStart
    var miny = high(LUnit)
    let cy2 = y + size.h
    for ex in bctx.relevantExclusions:
      let ey2 = ex.offset.y + ex.size.h
      if cy2 >= ex.offset.y and y < ey2:
        let ex2 = ex.offset.x + ex.size.w
        if ex.t == FloatLeft and left < ex2:
          left = ex2
        if ex.t == FloatRight and right > ex.offset.x:
          right = ex.offset.x
        miny = min(ey2, miny)
    let w = right - left
    if w >= size.w or miny == high(LUnit):
      # Enough space, or no other exclusions found at this y offset.
      outw = min(w, space.w.u) # do not overflow the container.
      if float == FloatLeft:
        return offset(x = left, y = y)
      else: # FloatRight
        return offset(x = right - size.w, y = y)
    # Move y to the bottom exclusion edge at the lowest y (where the exclusion
    # still intersects with the previous y).
    y = miny
  assert false
  offset(-1, -1)

proc findNextFloatOffset(bctx: BlockContext; offset: Offset; size: Size;
    space: AvailableSpace; float: CSSFloat): Offset =
  var dummy: LUnit
  return bctx.findNextFloatOffset(offset, size, space, float, dummy)

proc findNextBlockOffset(bctx: BlockContext; offset: Offset; size: Size;
    space: AvailableSpace; outw: var LUnit): Offset =
  return bctx.findNextFloatOffset(offset, size, space, FloatLeft, outw)

proc positionFloat(bctx: var BlockContext; child: BlockBox;
    space: AvailableSpace; outerSize: Size; marginOffset, bfcOffset: Offset) =
  assert space.w.t != scFitContent
  child.state.offset.y += bctx.marginTodo.sum()
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
  bctx.unpositionedFloats.setLen(0)

proc flushMargins(bctx: var BlockContext; offsety: var LUnit) =
  # Apply uncommitted margins.
  let margin = bctx.marginTodo.sum()
  if bctx.marginTarget == nil:
    offsety += margin
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
  bctx.positionFloats()

# Prepare the next line's initial width and available width.
# (If space on the left is excluded by floats, set the initial width to
# the end of that space. If space on the right is excluded, set the
# available width to that space.)
type InitLineFlag = enum
  ilfRegular # set the line to inited, and flush floats.
  ilfFloat # set the line to inited, but do not flush floats.
  ilfAbsolute # set size, but allow further calls to override the state.

proc initLine(fstate: var FlowState; flag = ilfRegular) =
  if flag != ilfFloat:
    #TODO ^ this should really be ilfRegular, but that summons another,
    # much worse bug.
    # In fact, absolute handling in the presence of floats has always
    # been somewhat broken and should be fixed some time.
    if flag != ilfAbsolute:
      let poffsety = fstate.offset.y
      fstate.bctx.flushMargins(fstate.offset.y)
      # Don't forget to add it to intrinsic height...
      fstate.intr.h += fstate.offset.y - poffsety
    fstate.bctx.positionFloats()
  if fstate.lbstate.init != lisUninited:
    return
  # we want to start from padding-left, but normally exclude padding
  # from space. so we must offset available width with padding-left too
  fstate.lbstate.availableWidth = fstate.space.w.u + fstate.padding.left
  fstate.lbstate.size.w = fstate.padding.left
  fstate.lbstate.init = lisNoExclusions
  #TODO what if maxContent/minContent?
  if fstate.bctx.exclusions.len > 0:
    let bfcOffset = fstate.bfcOffset
    let y = fstate.offset.y + bfcOffset.y
    var left = bfcOffset.x + fstate.lbstate.size.w
    var right = bfcOffset.x + fstate.lbstate.availableWidth
    for ex in fstate.bctx.relevantExclusions:
      if ex.offset.y <= y and y < ex.offset.y + ex.size.h:
        fstate.lbstate.init = lisExclusions
        if ex.t == FloatLeft:
          left = ex.offset.x + ex.size.w
        else:
          right = ex.offset.x
    fstate.lbstate.size.w = max(left - bfcOffset.x, fstate.lbstate.size.w)
    fstate.lbstate.availableWidth = min(right - bfcOffset.x,
      fstate.lbstate.availableWidth)
  if flag == ilfAbsolute:
    fstate.lbstate.init = lisUninited

# Whitespace between words
proc computeShift(fstate: FlowState; istate: InlineState): LUnit =
  if fstate.whitespacenum == 0:
    return 0
  if fstate.whitespaceIsLF and istate.lastrw == 2 and istate.firstrw == 2:
    # skip line feed between double-width characters
    return 0
  if not istate.ibox.computed.whitespacepre:
    if fstate.lbstate.iastates.len == 0:
      return 0
    let ibox = fstate.lbstate.iastates[^1].ibox
    if ibox of InlineTextBox:
      let ibox = InlineTextBox(ibox)
      if ibox.runs.len > 0 and ibox.runs[^1].str[^1] == ' ':
        return 0
  return fstate.cellSize.w * fstate.whitespacenum

proc newWord(fstate: var FlowState; ibox: InlineBox) =
  let ch = fstate.cellSize.h
  fstate.word = InlineAtomState(
    ibox: ibox,
    run: TextRun(),
    size: size(w = 0, h = ch),
    vertalign: ibox.computed{"vertical-align"},
    baselineShift: ibox.computed{"-cha-vertical-align-length"},
    baseline: ch
  )
  fstate.wrappos = -1
  fstate.hasshy = false

#TODO start & justify would be nice to have
const TextAlignNone = {
  TextAlignStart, TextAlignLeft, TextAlignChaLeft, TextAlignJustify
}

proc positionAtom(lbstate: LineBoxState; iastate: var InlineAtomState) =
  case iastate.vertalign
  of VerticalAlignBaseline:
    # Atom is placed at (line baseline) - (atom baseline) - len
    iastate.offset.y = lbstate.baseline - iastate.offset.y
  of VerticalAlignMiddle:
    # Atom is placed at (line baseline) - ((atom height) / 2)
    iastate.offset.y = lbstate.baseline - iastate.size.h div 2
  of VerticalAlignTop:
    # Atom is placed at the top of the line.
    iastate.offset.y = 0
  of VerticalAlignBottom:
    # Atom is placed at the bottom of the line.
    iastate.offset.y = lbstate.size.h - iastate.size.h
  else:
    # See baseline (with len = 0).
    iastate.offset.y = lbstate.baseline - iastate.baseline

proc getLineWidth(fstate: FlowState): LUnit =
  return case fstate.space.w.t
  of scMinContent, scMaxContent, scMeasure: fstate.maxChildWidth
  of scFitContent: fstate.space.w.u
  of scStretch: max(fstate.maxChildWidth, fstate.space.w.u)

proc getLineXShift(fstate: FlowState; width: LUnit): LUnit =
  return case fstate.computed{"text-align"}
  of TextAlignNone: LUnit(0)
  of TextAlignEnd, TextAlignRight, TextAlignChaRight:
    let width = min(width, fstate.lbstate.availableWidth)
    max(width, fstate.lbstate.size.w) - fstate.lbstate.size.w
  of TextAlignCenter, TextAlignChaCenter:
    let w = min(width, fstate.lbstate.availableWidth)
    max(max(w, fstate.lbstate.size.w) div 2 - fstate.lbstate.size.w div 2, 0)

# Calculate the position of atoms and background areas inside the
# line.
proc alignLine(fstate: var FlowState) =
  let width = fstate.getLineWidth()
  let xshift = fstate.getLineXShift(width)
  var totalWidth: LUnit = 0
  var currentAreaOffsetX: LUnit = 0
  var currentBox: InlineBox = nil
  let areaY = fstate.offset.y + fstate.lbstate.baseline - fstate.cellSize.h
  var minHeight = fstate.cellSize.h
  for (box, i) in fstate.lbstate.paddingTodo:
    box.state.areas[i].offset.x += xshift
    box.state.areas[i].offset.y = areaY
  for i, iastate in fstate.lbstate.iastates.mpairs:
    fstate.lbstate.positionAtom(iastate)
    iastate.offset.y += fstate.offset.y
    minHeight = max(minHeight, iastate.offset.y - fstate.offset.y +
      iastate.size.h)
    # now position on the inline axis
    iastate.offset.x += xshift
    totalWidth += iastate.size.w
    let box = iastate.ibox
    if currentBox != box:
      if currentBox != nil:
        # flush area
        let lastAtom = addr fstate.lbstate.iastates[i - 1]
        let w = lastAtom.offset.x + lastAtom.size.w - currentAreaOffsetX
        if w != 0:
          currentBox.state.areas.add(Area(
            offset: offset(x = currentAreaOffsetX, y = areaY),
            size: size(w = w, h = fstate.cellSize.h)
          ))
      # init new box
      currentBox = box
      currentAreaOffsetX = iastate.offset.x
    if iastate.ibox of InlineTextBox:
      iastate.run.offset = iastate.offset
    elif iastate.ibox of InlineBlockBox:
      let ibox = InlineBlockBox(iastate.ibox)
      # Add the offset to avoid destroying margins (etc.) of the block.
      BlockBox(ibox.firstChild).state.offset += iastate.offset
    elif iastate.ibox of InlineImageBox:
      let ibox = InlineImageBox(iastate.ibox)
      ibox.imgstate.offset = iastate.offset
    else:
      assert false
  if currentBox != nil:
    # flush area
    let iastate = addr fstate.lbstate.iastates[^1]
    let w = iastate.offset.x + iastate[].size.w - currentAreaOffsetX
    let offset = offset(x = currentAreaOffsetX, y = areaY)
    template lastArea: Area = currentBox.state.areas[^1]
    if currentBox.state.areas.len > 0 and
        lastArea.offset.x == offset.x and lastArea.size.w == w and
        lastArea.offset.y + lastArea.size.h == offset.y:
      # merge contiguous areas
      lastArea.size.h += fstate.cellSize.h
    else:
      currentBox.state.areas.add(Area(
        offset: offset,
        size: size(w = w, h = fstate.cellSize.h)
      ))
  if fstate.space.w.t == scFitContent:
    fstate.maxChildWidth = max(totalWidth, fstate.maxChildWidth)
  # Ensure that the line is exactly as high as its highest atom demands,
  # rounded up to the next line.
  fstate.lbstate.size.h = minHeight.ceilTo(fstate.cellSize.h.toInt())

proc putAtom(lbstate: var LineBoxState; iastate: InlineAtomState) =
  lbstate.iastates.add(iastate)
  if iastate.ibox of InlineTextBox:
    let ibox = InlineTextBox(iastate.ibox)
    ibox.runs.add(iastate.run)

proc addSpacing(fstate: var FlowState; width: LUnit; hang = false) =
  let ibox = fstate.whitespaceBox
  if ibox.runs.len == 0 or fstate.lbstate.iastates.len == 0 or
      (let orun = ibox.runs[^1]; orun != fstate.lbstate.iastates[^1].run):
    let cellHeight = fstate.cellSize.h
    let iastate = InlineAtomState(
      ibox: ibox,
      baseline: cellHeight,
      run: TextRun(),
      offset: offset(x = fstate.lbstate.size.w, y = cellHeight),
      size: size(w = 0, h = cellHeight)
    )
    fstate.lbstate.putAtom(iastate)
  let iastate = addr fstate.lbstate.iastates[^1]
  let n = (width div fstate.cellSize.w).toInt #TODO
  for i in 0 ..< n:
    iastate.run.str &= ' '
  iastate.size.w += width
  if not hang:
    # In some cases, whitespace may "hang" at the end of the line. This means
    # it is written, but is not actually counted in the box's width.
    fstate.lbstate.size.w += width

proc flushWhitespace(fstate: var FlowState; istate: InlineState;
    hang = false) =
  let shift = fstate.computeShift(istate)
  fstate.lbstate.charwidth += fstate.whitespacenum
  fstate.whitespacenum = 0
  if shift > 0:
    fstate.initLine()
    fstate.addSpacing(shift, hang)

proc initLineBoxState(fstate: FlowState): LineBoxState =
  let cellHeight = fstate.cellSize.h
  result = LineBoxState(
    intrh: cellHeight,
    baseline: cellHeight,
    size: size(w = 0, h = cellHeight)
  )

proc finishLine(fstate: var FlowState; istate: var InlineState; wrap: bool;
    force = false; clear = ClearNone) =
  if fstate.lbstate.iastates.len != 0 or force or
      fstate.whitespacenum != 0 and istate.ibox != nil and
      istate.ibox.computed{"white-space"} in {WhitespacePre, WhitespacePreWrap}:
    fstate.initLine()
    let whitespace = istate.ibox.computed{"white-space"}
    if whitespace == WhitespacePre:
      fstate.flushWhitespace(istate)
      # see below on padding
      fstate.intr.w = max(fstate.intr.w, fstate.lbstate.size.w -
        fstate.padding.left)
    elif whitespace == WhitespacePreWrap:
      fstate.flushWhitespace(istate, hang = true)
    else:
      fstate.whitespacenum = 0
    # align atoms + calculate width for fit-content + place
    fstate.alignLine()
    for f in fstate.lbstate.unpositionedFloats:
      if whitespace != WhitespacePre and f.newLine:
        f.box.state.offset.y += fstate.lbstate.size.h
      fstate.bctx.positionFloat(f.box, f.space, f.outerSize,
        f.marginOffset, f.parentBps.offset)
    # add line to fstate
    let y = fstate.offset.y
    if clear != ClearNone:
      fstate.lbstate.size.h.clearFloats(fstate.bctx, fstate.bfcOffset.y + y,
        clear)
    # * set first baseline if this is the first line box
    # * always set last baseline (so the baseline of the last line box remains)
    fstate.box.state.baseline = y + fstate.lbstate.baseline
    if not fstate.box.state.baselineSet:
      fstate.box.state.firstBaseline = y + fstate.lbstate.baseline
      fstate.box.state.baselineSet = true
    fstate.offset.y += fstate.lbstate.size.h
    fstate.intr.h += fstate.lbstate.intrh
    let lineWidth = if wrap:
      fstate.lbstate.availableWidth
    else:
      fstate.lbstate.size.w
    # padding-left is added to the line to aid float exclusion; undo
    # this here to prevent double-padding later
    fstate.maxChildWidth = max(fstate.maxChildWidth,
      lineWidth - fstate.padding.left)
  else:
    # Two cases exist:
    # a) The float cannot be positioned, because `fstate.box' has not
    #    resolved its y offset yet. (e.g. if float comes before the
    #    first child, we do not know yet if said child will move our y
    #    offset with a margin-top value larger than ours.)
    #    In this case we put it in unpositionedFloats, and defer
    #    positioning until our y offset is resolved.
    # b) `box' has resolved its y offset, so the float can already
    #    be positioned.
    # We check whether our y offset has been positioned as follows:
    # * save marginTarget in FlowState at layoutFlow's start
    # * if our saved marginTarget and bctx's marginTarget no longer
    #   point to the same object, that means our (or an ancestor's)
    #   offset has been resolved, i.e. we can position floats already.
    if fstate.bctx.marginTarget != fstate.initialMarginTarget:
      # y offset resolved
      for f in fstate.lbstate.unpositionedFloats:
        fstate.bctx.positionFloat(f.box, f.space, f.outerSize, f.marginOffset,
          f.parentBps.offset)
    else:
      fstate.bctx.unpositionedFloats.add(fstate.lbstate.unpositionedFloats)
  # Reinit in both cases.
  fstate.totalFloatWidth = max(fstate.totalFloatWidth,
    fstate.lbstate.totalFloatWidth)
  fstate.lbstate = fstate.initLineBoxState()

proc shouldWrap(fstate: FlowState; w: LUnit;
    pcomputed: CSSValues): bool =
  if pcomputed != nil and pcomputed.nowrap:
    return false
  if fstate.space.w.t in {scMaxContent, scMeasure}:
    return false # no wrap with max-content
  if fstate.space.w.t == scMinContent:
    return true # always wrap with min-content
  return fstate.lbstate.size.w + w > fstate.lbstate.availableWidth

proc shouldWrap2(fstate: FlowState; w: LUnit): bool =
  assert fstate.lbstate.init != lisUninited
  if fstate.lbstate.init == lisNoExclusions:
    return false
  return fstate.lbstate.size.w + w > fstate.lbstate.availableWidth

proc getBaseline(fstate: FlowState; iastate: InlineAtomState): LUnit =
  return case iastate.vertalign
  of VerticalAlignBaseline:
    iastate.baseline
  of VerticalAlignLength:
    iastate.baseline + iastate.baselineShift.px(fstate.cellSize.h)
  of VerticalAlignTop:
    0
  of VerticalAlignMiddle:
    iastate.size.h div 2
  of VerticalAlignBottom:
    iastate.size.h
  else:
    iastate.baseline

# Add an inline atom atom, with state iastate.
# Returns true on newline.
proc addAtom(fstate: var FlowState; istate: var InlineState;
    iastate: InlineAtomState): bool =
  fstate.initLine()
  result = false
  var shift = fstate.computeShift(istate)
  fstate.lbstate.charwidth += fstate.whitespacenum
  fstate.whitespacenum = 0
  # Line wrapping
  if fstate.shouldWrap(iastate.size.w + shift, istate.ibox.computed):
    fstate.finishLine(istate, wrap = true)
    fstate.initLine()
    result = true
    # Recompute on newline
    shift = fstate.computeShift(istate)
    # For floats: flush lines until we can place the atom.
    #TODO this is inefficient
    while fstate.shouldWrap2(iastate.size.w + shift):
      fstate.finishLine(istate, wrap = false, force = true)
      fstate.initLine()
      # Recompute on newline
      shift = fstate.computeShift(istate)
  if iastate.size.w > 0 and iastate.size.h > 0 or
      iastate.ibox of InlineBlockBox:
    if shift > 0:
      fstate.addSpacing(shift)
    if iastate.run != nil and fstate.lbstate.iastates.len > 0 and
        istate.ibox of InlineTextBox:
      let ibox = InlineTextBox(istate.ibox)
      if ibox.runs.len > 0:
        let oiastate = addr fstate.lbstate.iastates[^1]
        let orun = oiastate.run
        if orun != nil and orun == ibox.runs[^1]:
          orun.str &= iastate.run.str
          oiastate.size.w += iastate.size.w
          fstate.lbstate.size.w += iastate.size.w
          return
    fstate.lbstate.putAtom(iastate)
    fstate.lbstate.iastates[^1].offset.x += fstate.lbstate.size.w
    fstate.lbstate.size.w += iastate.size.w
    # store for later use in alignLine
    let baseline = fstate.getBaseline(iastate)
    fstate.lbstate.iastates[^1].offset.y = baseline
    fstate.lbstate.baseline = max(fstate.lbstate.baseline, baseline)
    # In all cases, the line's height must at least equal the atom's height.
    fstate.lbstate.size.h = max(fstate.lbstate.size.h, iastate.size.h)

proc flushWordIntrSize(fstate: var FlowState) =
  fstate.intr.w = max(fstate.intr.w, fstate.wordIntrSize)
  fstate.wordIntrSize = 0

# Returns true if wrapped.
proc addWord(fstate: var FlowState; istate: var InlineState): bool =
  if fstate.word.run.str == "":
    return false
  fstate.word.run.str.mnormalize() #TODO this may break on EOL.
  if fstate.word.run.str == "":
    return false
  fstate.flushWordIntrSize()
  let wrapped = fstate.addAtom(istate, fstate.word)
  fstate.newWord(istate.ibox)
  return wrapped

proc addWordEOL(fstate: var FlowState; state: var InlineState): bool =
  if fstate.word.run.str == "":
    return false
  if fstate.wrappos != -1:
    var leftstr = fstate.word.run.str.substr(fstate.wrappos)
    fstate.word.run.str.setLen(fstate.wrappos)
    if fstate.hasshy:
      const shy = "\u00AD" # soft hyphen
      fstate.word.run.str &= shy
      fstate.hasshy = false
    let wrapped = fstate.addWord(state)
    fstate.word.size.w = leftstr.width() * fstate.cellSize.w
    fstate.word.run.str = move(leftstr)
    return wrapped
  else:
    return fstate.addWord(state)

proc checkWrap(fstate: var FlowState; state: var InlineState; u: uint32;
    uw: int) =
  if state.ibox.computed.nowrap:
    return
  fstate.initLine()
  let shift = fstate.computeShift(state)
  state.prevrw = uw
  if fstate.word.run.str.len == 0:
    state.firstrw = uw
  case state.ibox.computed{"word-break"}
  of WordBreakNormal:
    if uw == 2:
      # remove wrap opportunity, so we wrap properly on the last CJK char
      # (instead of any dash inside CJK sentences)
      fstate.wrappos = -1
      fstate.flushWordIntrSize()
    if uw == 2 or fstate.wrappos != -1: # break on cjk and wrap opportunities
      let plusWidth = fstate.word.size.w + shift + uw * fstate.cellSize.w
      if fstate.shouldWrap(plusWidth, nil):
        if not fstate.addWordEOL(state): # no line wrapping occured in addAtom
          fstate.finishLine(state, wrap = true)
          fstate.whitespacenum = 0
  of WordBreakBreakAll:
    fstate.wrappos = -1
    fstate.flushWordIntrSize()
    let plusWidth = fstate.word.size.w + shift + uw * fstate.cellSize.w
    if fstate.shouldWrap(plusWidth, nil):
      if not fstate.addWordEOL(state): # no line wrapping occured in addAtom
        fstate.finishLine(state, wrap = true)
        fstate.whitespacenum = 0
  of WordBreakKeepAll:
    let plusWidth = fstate.word.size.w + shift + uw * fstate.cellSize.w
    if fstate.shouldWrap(plusWidth, nil):
      fstate.finishLine(state, wrap = true)
      fstate.whitespacenum = 0

proc processWhitespace(fstate: var FlowState; istate: var InlineState;
    c: char) =
  let ibox = InlineTextBox(istate.ibox)
  discard fstate.addWord(istate)
  case ibox.computed{"white-space"}
  of WhitespaceNormal, WhitespaceNowrap:
    if fstate.whitespacenum < 1 and fstate.lbstate.iastates.len > 0:
      fstate.whitespacenum = 1
      fstate.whitespaceBox = ibox
      fstate.whitespaceIsLF = c == '\n'
    if c != '\n':
      fstate.whitespaceIsLF = false
  of WhitespacePreLine:
    if c == '\n':
      fstate.finishLine(istate, wrap = false, force = true)
    elif fstate.whitespacenum < 1:
      fstate.whitespaceIsLF = false
      fstate.whitespacenum = 1
      fstate.whitespaceBox = ibox
  of WhitespacePre, WhitespacePreWrap:
    fstate.whitespaceIsLF = false
    if c == '\n':
      fstate.finishLine(istate, wrap = false, force = true)
    elif c == '\t':
      let realWidth = fstate.lbstate.charwidth + fstate.whitespacenum
      # We must flush first, because addWord would otherwise try to wrap the
      # line. (I think.)
      fstate.flushWhitespace(istate)
      let w = ((realWidth + 8) and not 7) - realWidth
      fstate.word.run.str.addUTF8(tabPUAPoint(w))
      fstate.word.size.w += w * fstate.cellSize.w
      fstate.lbstate.charwidth += w
      # Ditto here - we don't want the tab stop to get merged into the next
      # word.
      discard fstate.addWord(istate)
    else:
      inc fstate.whitespacenum
      fstate.whitespaceBox = ibox
  # set the "last word's last rune width" to the previous rune width
  istate.lastrw = istate.prevrw

proc addWrapPos(fstate: var FlowState; shy: bool) =
  # largest gap between wrapping opportunities is the intrinsic minimum
  # width
  fstate.flushWordIntrSize()
  fstate.wrappos = fstate.word.run.str.len
  fstate.hasshy = shy

proc layoutTextLoop(fstate: var FlowState; state: var InlineState;
    str: string) =
  let luctx = fstate.lctx.luctx
  var i = 0
  while i < str.len:
    let c = str[i]
    if c in Ascii:
      if c in AsciiWhitespace:
        fstate.processWhitespace(state, c)
      else:
        let w = uint32(c).width()
        fstate.checkWrap(state, uint32(c), w)
        fstate.word.run.str &= c
        let cw = w * fstate.cellSize.w
        fstate.word.size.w += cw
        fstate.wordIntrSize += cw
        fstate.lbstate.charwidth += w
        if c == '-': # ascii dash
          fstate.addWrapPos(shy = false)
      inc i
    else:
      let pi = i
      var u = str.nextUTF8(i)
      if luctx.isEnclosingMark(u) or luctx.isNonspacingMark(u) or
          luctx.isFormat(u):
        continue
      if u == 0xAD: # soft hyphen
        fstate.addWrapPos(shy = true)
        continue
      if u in TabPUARange: # filter out chars placed in our PUA range
        u = 0xFFFD
      let w = u.width()
      fstate.checkWrap(state, u, w)
      for j in pi ..< i:
        fstate.word.run.str &= str[j]
      let cw = w * fstate.cellSize.w
      fstate.word.size.w += cw
      fstate.wordIntrSize += cw
      fstate.lbstate.charwidth += w
  discard fstate.addWord(state)
  let shift = fstate.computeShift(state)
  fstate.lbstate.widthAfterWhitespace = fstate.lbstate.size.w + shift

proc layoutText(fstate: var FlowState; istate: var InlineState; s: string) =
  fstate.flushWhitespace(istate)
  fstate.newWord(istate.ibox)
  let transform = istate.ibox.computed{"text-transform"}
  if transform == TextTransformNone:
    fstate.layoutTextLoop(istate, s)
  else:
    let s = case transform
    of TextTransformCapitalize: s.capitalizeLU()
    of TextTransformUppercase: s.toUpperLU()
    of TextTransformLowercase: s.toLowerLU()
    of TextTransformFullWidth: s.fullwidth()
    of TextTransformFullSizeKana: s.fullsize()
    of TextTransformChaHalfWidth: s.halfwidth()
    else: ""
    fstate.layoutTextLoop(istate, s)

# size is the parent's size.
proc popPositioned(lctx: LayoutContext; head: CSSAbsolute; size: Size) =
  var it = head
  while it != nil:
    let child = it.box
    var size = size
    #TODO this is very ugly.
    # I'm subtracting the X offset because it's normally equivalent to
    # the float-induced offset. But this isn't always true, e.g. it
    # definitely isn't in flex layout.
    var offset = child.state.offset
    size.w -= offset.x
    let positioned = lctx.resolvePositioned(size, child.computed)
    var sizes = lctx.resolveAbsoluteSizes(size, positioned, child.computed)
    offset.x += sizes.margin.left
    var bctx = initBlockContext(lctx)
    bctx.layout(child, offset, sizes)
    if not child.computed{"left"}.auto:
      child.state.offset.x = positioned.left + sizes.margin.left
    elif not child.computed{"right"}.auto:
      child.state.offset.x = size.w - positioned.right - child.state.size.w -
        sizes.margin.right
    # margin.left is added in layout
    if not child.computed{"top"}.auto:
      child.state.offset.y = positioned.top + sizes.margin.top
    elif not child.computed{"bottom"}.auto:
      child.state.offset.y = size.h - positioned.bottom - child.state.size.h -
        sizes.margin.bottom
    else:
      child.state.offset.y += sizes.margin.top
    it = it.next

proc positionRelative(lctx: LayoutContext; space: AvailableSpace;
    box: BlockBox) =
  # Interestingly, relative percentages don't actually work when the
  # parent's height is auto.
  if box.computed{"left"}.canpx(space.w):
    box.state.offset.x += box.computed{"left"}.px(space.w)
  elif box.computed{"right"}.canpx(space.w):
    box.state.offset.x -= box.computed{"right"}.px(space.w)
  if box.computed{"top"}.canpx(space.h):
    box.state.offset.y += box.computed{"top"}.px(space.h)
  elif box.computed{"bottom"}.canpx(space.h):
    box.state.offset.y -= box.computed{"bottom"}.px(space.h)

proc clearedBy(floats: set[CSSFloat]; clear: CSSClear): bool =
  return case clear
  of ClearNone: false
  of ClearBoth: floats != {}
  of ClearInlineStart, ClearLeft: FloatLeft in floats
  of ClearInlineEnd, ClearRight: FloatRight in floats

proc layoutFloat(fstate: var FlowState; child: BlockBox) =
  let lctx = fstate.lctx
  let sizes = lctx.resolveFloatSizes(fstate.space, child.computed)
  var bctx = initBlockContext(lctx)
  bctx.layout(child, fstate.offset + sizes.margin.topLeft, sizes)
  let outerSize = child.outerSize(sizes, lctx)
  if fstate.space.w.t == scMeasure:
    # Float position depends on the available width, but in this case
    # the parent width is not known.  Skip this box; we will position
    # it in the next pass.
    #
    # Since we emulate max-content here, the float will not contribute
    # to maxChildWidth in this iteration; instead, its outer width
    # will be summed up in totalFloatWidth and added to maxChildWidth
    # in initReLayout.
    fstate.lbstate.totalFloatWidth += outerSize.w
  else:
    assert fstate.space.w.t == scStretch
    fstate.maxChildWidth = max(fstate.maxChildWidth, outerSize.w)
    fstate.initLine(flag = ilfFloat)
    var newLine = true
    let float = child.computed{"float"}
    if not fstate.lbstate.floatsSeen.clearedBy(child.computed{"clear"}) and
        fstate.lbstate.size.w + outerSize.w <= fstate.lbstate.availableWidth and
        (fstate.lbstate.unpositionedFloats.len == 0 or
        not fstate.lbstate.unpositionedFloats[^1].newLine):
      # We can still cram floats into the line.
      if float == FloatLeft:
        fstate.lbstate.size.w += outerSize.w
        for iastate in fstate.lbstate.iastates.mitems:
          iastate.offset.x += outerSize.w
      else:
        fstate.lbstate.availableWidth -= outerSize.w
      fstate.lbstate.floatsSeen.incl(float)
      newLine = false
    fstate.lbstate.unpositionedFloats.add(UnpositionedFloat(
      space: fstate.space,
      parentBps: fstate.bctx.parentBps,
      box: child,
      marginOffset: sizes.margin.startOffset(),
      outerSize: outerSize,
      newLine: newLine
    ))
  fstate.intr.w = max(fstate.intr.w, child.state.intr.w)

# Outer layout for block-level children.
proc layoutBlockChild(fstate: var FlowState; child: BlockBox) =
  var istate = InlineState(ibox: fstate.lastTextBox)
  fstate.finishLine(istate, wrap = false)
  let lctx = fstate.lctx
  var sizes = lctx.resolveBlockSizes(fstate.space, child.computed)
  var space = fstate.space # may be modified if child is a BFC
  const DisplayWithBFC = {
    DisplayFlowRoot, DisplayTable, DisplayFlex, DisplayGrid
  }
  var offset = fstate.offset
  offset.x += sizes.margin.left
  fstate.bctx.marginTodo.append(sizes.margin.top)
  let clear = child.computed{"clear"}
  if child.computed{"display"} in DisplayWithBFC or
      child.computed{"overflow-x"} notin {OverflowVisible, OverflowClip}:
    # This box establishes a new BFC.
    var bctx = initBlockContext(lctx)
    bctx.layout(child, offset, sizes)
    fstate.bctx.flushMargins(child.state.offset.y)
    if clear != ClearNone:
      fstate.offset.y.clearFloats(fstate.bctx, fstate.bfcOffset.y, clear)
    if fstate.bctx.exclusions.len > 0:
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
      # * place the longest word (i.e. intr.w) somewhere
      # * run another pass with the placement we got
      #
      # Some browsers prefer to try again until they find enough
      # available space; I won't do that because it's unnecessarily
      # complex and slow. (Maybe one day, when layout is faster...)
      #
      # Note that this does not apply to absolutely positioned elements,
      # as those ignore floats.
      let pbfcOffset = fstate.bfcOffset
      let bfcOffset = offset(
        x = pbfcOffset.x + child.state.offset.x,
        y = max(pbfcOffset.y + child.state.offset.y, fstate.bctx.clearOffset)
      )
      let minSize = size(w = child.state.intr.w, h = lctx.cellSize.h)
      var outw: LUnit
      let offset = fstate.bctx.findNextBlockOffset(bfcOffset, minSize,
        fstate.space, outw)
      let roffset = offset - pbfcOffset
      # skip relayout if we can
      if outw != fstate.space.w.u or roffset != child.state.offset:
        space = availableSpace(w = stretch(outw), h = fstate.space.h)
        sizes = lctx.resolveBlockSizes(space, child.computed)
        var bctx = initBlockContext(lctx)
        bctx.layout(child, roffset, sizes)
  else:
    offset += sizes.borderTopLeft(lctx)
    if clear != ClearNone:
      fstate.bctx.flushMargins(offset.y)
      offset.y.clearFloats(fstate.bctx, fstate.bfcOffset.y, clear)
    fstate.bctx.layout(child, offset, sizes)
  fstate.bctx.marginTodo.append(sizes.margin.bottom)
  let outerSize = size(
    w = child.outerSize(dtHorizontal, sizes, lctx),
    # delta y is difference between old and new offsets (margin-top),
    # plus height, plus border size.
    h = child.state.offset.y - fstate.offset.y + child.state.size.h +
      sizes.borderSize(dtVertical, lctx).send
  )
  if child.state.baselineSet:
    if not fstate.box.state.baselineSet:
      fstate.box.state.firstBaseline = child.state.offset.y +
        child.state.firstBaseline
      fstate.box.state.baselineSet = true
    fstate.box.state.baseline = child.state.offset.y + child.state.baseline
  if fstate.space.w.t == scStretch:
    if fstate.textAlign == TextAlignChaCenter:
      child.state.offset.x += max(space.w.u div 2 -
        child.state.size.w div 2, 0)
    elif fstate.textAlign == TextAlignChaRight:
      child.state.offset.x += max(space.w.u - child.state.size.w -
        sizes.margin.right, 0)
  if child.computed{"position"} == PositionRelative:
    fstate.lctx.positionRelative(fstate.space, child)
  fstate.maxChildWidth = max(fstate.maxChildWidth, outerSize.w)
  fstate.offset.y += outerSize.h
  fstate.intr.h += outerSize.h - child.state.size.h + child.state.intr.h
  fstate.whitespacenum = 0
  fstate.intr.w = max(fstate.intr.w, child.state.intr.w)

proc layoutOuterBlock(fstate: var FlowState; child: BlockBox) =
  if child.computed{"position"} in PositionAbsoluteFixed:
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
    if fstate.space.w.t == scMeasure:
      # Do not queue in the first pass.
      return
    var offset = fstate.offset
    fstate.initLine(flag = ilfAbsolute)
    if fstate.bctx.marginTarget != fstate.initialMarginTarget:
      offset.y += fstate.bctx.marginTodo.sum()
    if child.computed{"display"} in DisplayOuterInline:
      # inline-block or similar. put it on the current line.
      # (I don't add pending spacing because other browsers don't add
      # it either.)
      offset.x += fstate.lbstate.size.w
    elif fstate.lbstate.iastates.len > 0:
      # flush if there is already something on the line *and* our outer
      # display is block.
      offset.y += fstate.cellSize.h
    child.state.offset = offset
  elif child.computed{"float"} != FloatNone:
    fstate.layoutFloat(child)
  else:
    fstate.layoutBlockChild(child)

proc layoutInlineBlock(fstate: var FlowState; ibox: InlineBlockBox) =
  let lctx = fstate.lctx
  let box = BlockBox(ibox.firstChild)
  if box.computed{"position"} in PositionAbsoluteFixed:
    # Absolute is a bit of a special case in inline: while the spec
    # *says* it should blockify, absolutely positioned inline-blocks are
    # placed in a different place than absolutely positioned blocks (and
    # websites depend on this).
    fstate.layoutOuterBlock(box)
  elif box.computed{"display"} == DisplayMarker:
    # Marker box. This is a mixture of absolute and inline-block
    # layout, where we don't care about the parent size but want to
    # place ourselves outside the left edge of our parent box.
    var sizes = lctx.resolveFloatSizes(fstate.space, box.computed)
    var bctx = initBlockContext(lctx)
    bctx.layout(box, sizes.margin.topLeft, sizes)
    fstate.initLine(flag = ilfAbsolute)
    box.state.offset.x = fstate.lbstate.size.w - box.state.size.w
  else:
    # A real inline block.
    var sizes = lctx.resolveFloatSizes(fstate.space, box.computed)
    var bctx = initBlockContext(lctx)
    bctx.layout(box, sizes.margin.topLeft, sizes)
    # Apply the block box's properties to the atom itself.
    var iastate = InlineAtomState(
      ibox: ibox,
      baseline: box.state.baseline + sizes.margin.top,
      vertalign: box.computed{"vertical-align"},
      baselineShift: ibox.computed{"-cha-vertical-align-length"},
      size: box.outerSize(sizes, lctx)
    )
    if not box.state.baselineSet:
      iastate.baseline += box.state.size.h
    var istate = InlineState(ibox: ibox)
    discard fstate.addAtom(istate, iastate)
    fstate.intr.w = max(fstate.intr.w, box.state.intr.w)
    fstate.lbstate.intrh = max(fstate.lbstate.intrh, iastate.size.h)
    fstate.lbstate.charwidth = 0
    fstate.whitespacenum = 0

proc layoutImage(fstate: var FlowState; ibox: InlineImageBox; padding: LUnit) =
  ibox.imgstate = InlineImageState(
    size: size(w = ibox.bmp.width, h = ibox.bmp.height)
  )
  #TODO this is hopelessly broken.
  # The core problem is that we generate an inner and an outer box for
  # images, and achieving an acceptable image sizing algorithm with this
  # setup is practically impossible.
  # Accordingly, a correct solution would either handle block-level
  # images separately, or at least resolve the outer box's sizes with
  # the knowledge that it is an image.
  let computed = ibox.computed
  let hasWidth = computed{"width"}.canpx(fstate.space.w)
  let hasHeight = computed{"height"}.canpx(fstate.space.h)
  let osize = ibox.imgstate.size
  if hasWidth:
    ibox.imgstate.size.w = computed{"width"}.spx(fstate.space.w, computed,
      padding)
  if hasHeight:
    ibox.imgstate.size.h = computed{"height"}.spx(fstate.space.h, computed,
      padding)
  if computed{"max-width"}.canpx(fstate.space.w):
    let w = computed{"max-width"}.spx(fstate.space.w, computed, padding)
    ibox.imgstate.size.w = min(ibox.imgstate.size.w, w)
  let hasMinWidth = computed{"min-width"}.canpx(fstate.space.w)
  if hasMinWidth:
    let w = computed{"min-width"}.spx(fstate.space.w, computed, padding)
    ibox.imgstate.size.w = max(ibox.imgstate.size.w, w)
  if computed{"max-height"}.canpx(fstate.space.h):
    let h = computed{"max-height"}.spx(fstate.space.h, computed, padding)
    ibox.imgstate.size.h = min(ibox.imgstate.size.h, h)
  let hasMinHeight = computed{"min-height"}.canpx(fstate.space.h)
  if hasMinHeight:
    let h = computed{"min-height"}.spx(fstate.space.h, computed, padding)
    ibox.imgstate.size.h = max(ibox.imgstate.size.h, h)
  if not hasWidth and fstate.space.w.isDefinite():
    ibox.imgstate.size.w = min(fstate.space.w.u, ibox.imgstate.size.w)
  if not hasHeight and fstate.space.h.isDefinite():
    ibox.imgstate.size.h = min(fstate.space.h.u, ibox.imgstate.size.h)
  if not hasHeight and not hasWidth:
    if osize.w >= osize.h or
        not fstate.space.h.isDefinite() and fstate.space.w.isDefinite():
      if osize.w > 0:
        ibox.imgstate.size.h = osize.h div osize.w * ibox.imgstate.size.w
    else:
      if osize.h > 0:
        ibox.imgstate.size.w = osize.w div osize.h * ibox.imgstate.size.h
  elif not hasHeight and osize.w != 0:
    ibox.imgstate.size.h = osize.h div osize.w * ibox.imgstate.size.w
  elif not hasWidth and osize.h != 0:
    ibox.imgstate.size.w = osize.w div osize.h * ibox.imgstate.size.h
  let iastate = InlineAtomState(
    ibox: ibox,
    vertalign: ibox.computed{"vertical-align"},
    baselineShift: ibox.computed{"-cha-vertical-align-length"},
    baseline: ibox.imgstate.size.h,
    size: ibox.imgstate.size
  )
  var istate = InlineState(ibox: ibox)
  discard fstate.addAtom(istate, iastate)
  fstate.lbstate.charwidth = 0
  if ibox.imgstate.size.h > 0:
    # Setting the atom size as intr.w might result in a circular dependency
    # between table cell sizing and image sizing when we don't have a definite
    # parent size yet. e.g. <img width=100% ...> with an indefinite containing
    # size (i.e. the first table cell pass) would resolve to an intr.w of
    # image.width, stretching out the table to an uncomfortably large size.
    # The issue is similar with intr.h, which is relevant in flex layout.
    #
    # So check if any dimension is fixed, and if yes, report the intrinsic
    # minimum dimension as that or the atom size (whichever is greater).
    if not computed{"width"}.isPerc or not computed{"min-width"}.isPerc:
      fstate.intr.w = max(fstate.intr.w, ibox.imgstate.size.w)
    if not computed{"height"}.isPerc or not computed{"min-height"}.isPerc:
      fstate.lbstate.intrh = max(fstate.lbstate.intrh, ibox.imgstate.size.h)

proc layoutInline(fstate: var FlowState; ibox: InlineBox) =
  let lctx = fstate.lctx
  ibox.resetState()
  let padding = Span(
    start: ibox.computed{"padding-left"}.px(fstate.space.w),
    send: ibox.computed{"padding-right"}.px(fstate.space.w)
  )
  let oldTextAlign = fstate.textAlign
  # -moz-center uses the inline parent too, which is nonsense if you
  # consider the CSS 2 anonymous box generation rules, but whatever.
  fstate.textAlign = ibox.computed{"text-align"}
  if ibox of InlineTextBox:
    let ibox = InlineTextBox(ibox)
    ibox.runs.setLen(0)
    var istate = InlineState(ibox: ibox)
    fstate.layoutText(istate, ibox.text)
    fstate.lastTextBox = ibox
  elif ibox of InlineNewLineBox:
    let ibox = InlineNewLineBox(ibox)
    var istate = InlineState(ibox: ibox)
    fstate.finishLine(istate, wrap = false, force = true,
      ibox.computed{"clear"})
    fstate.lastTextBox = ibox
  elif ibox of InlineBlockBox:
    let ibox = InlineBlockBox(ibox)
    fstate.layoutInlineBlock(ibox)
    fstate.lastTextBox = ibox
  elif ibox of InlineImageBox:
    let ibox = InlineImageBox(ibox)
    fstate.layoutImage(ibox, padding.sum())
    fstate.lastTextBox = ibox
  else:
    ibox.state.startOffset = offset(
      x = fstate.lbstate.widthAfterWhitespace,
      y = fstate.offset.y
    )
    let w = ibox.computed{"margin-left"}.px(fstate.space.w)
    if w != 0:
      fstate.initLine()
      fstate.lbstate.size.w += w
      fstate.lbstate.widthAfterWhitespace += w
      ibox.state.startOffset.x += w
    if padding.start != 0:
      ibox.state.areas.add(Area(
        offset: offset(x = fstate.lbstate.widthAfterWhitespace, y = 0),
        size: size(w = padding.start, h = fstate.cellSize.h)
      ))
      fstate.lbstate.paddingTodo.add((ibox, 0))
      fstate.initLine()
      fstate.lbstate.size.w += padding.start
    for child in ibox.children:
      if child of InlineBox:
        fstate.layoutInline(InlineBox(child))
      else:
        fstate.layoutOuterBlock(BlockBox(child))
    if padding.send != 0:
      ibox.state.areas.add(Area(
        offset: offset(x = fstate.lbstate.size.w, y = 0),
        size: size(w = padding.send, h = fstate.cellSize.h)
      ))
      fstate.lbstate.paddingTodo.add((ibox, ibox.state.areas.high))
      fstate.initLine()
      fstate.lbstate.size.w += padding.send
    let marginRight = ibox.computed{"margin-right"}.px(fstate.space.w)
    if marginRight != 0:
      fstate.initLine()
      fstate.lbstate.size.w += marginRight
    if fstate.space.w.t != scMeasure:
      # This is UB in CSS 2.1, I can't find a newer spec about it,
      # and Gecko can't even layout it consistently (???)
      #
      # So I'm trying to follow Blink, though it's still not quite right,
      # since this uses cellHeight instead of the actual line height
      # for the last line.
      # Well, it seems good enough.
      lctx.popPositioned(ibox.absolute, size(
        w = 0,
        h = fstate.offset.y + fstate.cellSize.h - ibox.state.startOffset.y
      ))
  fstate.textAlign = oldTextAlign

proc layoutFlow0(fstate: var FlowState) =
  fstate.lbstate = fstate.initLineBoxState()
  for child in fstate.box.children:
    if child of InlineBox:
      fstate.layoutInline(InlineBox(child))
    else:
      fstate.layoutOuterBlock(BlockBox(child))
  var istate = InlineState(ibox: fstate.lastTextBox)
  fstate.finishLine(istate, wrap = false)
  fstate.totalFloatWidth = max(fstate.totalFloatWidth,
    fstate.lbstate.totalFloatWidth)

proc initFlowState(bctx: var BlockContext; box: BlockBox;
    sizes: ResolvedSizes): FlowState =
  result = FlowState(
    box: box,
    pbctx: addr bctx,
    offset: sizes.padding.topLeft,
    padding: sizes.padding,
    space: sizes.space,
    oldMarginTodo: bctx.marginTodo,
    oldExclusionsLen: bctx.exclusions.len,
    textAlign: box.computed{"text-align"}
  )

proc initBlockPositionStates(fstate: var FlowState; box: BlockBox) =
  let bctx = fstate.pbctx
  let prevBps = bctx.ancestorsHead
  bctx.ancestorsHead = BlockPositionState(
    box: box,
    offset: fstate.offset,
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
  fstate.initialMarginTarget = bctx.marginTarget
  fstate.initialTargetOffset = bctx.marginTarget.offset
  if bctx.parentBps == nil:
    # We have just established a new BFC. Resolve the margins immediately.
    bctx.marginTarget = nil
  fstate.prevParentBps = bctx.parentBps
  bctx.parentBps = bctx.ancestorsHead

# Unlucky path, where we have a fit-content width.
# Reset marginTodo & the starting offset, and stretch the box to the
# max child width.
proc initReLayout(fstate: var FlowState; bctx: var BlockContext; box: BlockBox;
    sizes: ResolvedSizes) =
  bctx.marginTodo = fstate.oldMarginTodo
  # Note: we do not reset our own BlockPositionState's offset; we assume it
  # has already been resolved in the previous pass.
  # (If not, it won't be resolved in this pass either, so the following code
  # does not really change anything.)
  bctx.parentBps.next = nil
  if fstate.initialMarginTarget != bctx.marginTarget:
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
      offset: fstate.initialTargetOffset,
      resolved: fstate.initialMarginTarget.resolved
    )
    # Also set ancestorsHead as the dummy object, so next elements are
    # chained to that.
    bctx.ancestorsHead = bctx.marginTarget
    if fstate.prevParentBps == nil:
      # We have just established a new BFC. Resolve the margins immediately.
      bctx.marginTarget = nil
  bctx.exclusions.setLen(fstate.oldExclusionsLen)
  var bounds = sizes.bounds
  bounds.a[dtHorizontal].start = max(bounds.a[dtHorizontal].start,
    fstate.intr.w)
  box.applySize(bounds, fstate.maxChildWidth + fstate.totalFloatWidth,
    sizes.space, dtHorizontal)
  # Save prev bps & margin target; these are assumed to remain
  # identical.
  let prevParentBps = fstate.prevParentBps
  let initialMarginTarget = fstate.initialMarginTarget
  fstate = bctx.initFlowState(box, sizes)
  fstate.space.w = stretch(box.state.size.w)
  fstate.prevParentBps = prevParentBps
  fstate.initialMarginTarget = initialMarginTarget

proc layoutFlow(bctx: var BlockContext; box: BlockBox; sizes: ResolvedSizes) =
  var fstate = bctx.initFlowState(box, sizes)
  fstate.initBlockPositionStates(box)
  if box.computed{"position"} notin PositionAbsoluteFixed and
      (sizes.padding.top != 0 or
      sizes.space.h.isDefinite() and sizes.space.h.u != 0 or
      sizes.border[dtVertical].start notin BorderStyleNoneHidden):
    bctx.flushMargins(box.state.offset.y)
  let spacew = fstate.space.w
  let indefinite = spacew.t in {scFitContent, scMaxContent}
  if indefinite:
    fstate.space.w = measure()
  fstate.layoutFlow0()
  if indefinite:
    fstate.space.w = spacew
    # shrink-to-fit size; layout again.
    let oldIntr = fstate.intr
    fstate.initReLayout(bctx, box, sizes)
    fstate.layoutFlow0()
    # Restore old intrinsic sizes, as the new ones are a function of the
    # current input and therefore wrong.
    fstate.intr = oldIntr
  elif fstate.space.w.t == scMeasure:
    fstate.maxChildWidth += fstate.totalFloatWidth
  # Apply width, and height. For height, temporarily remove padding we have
  # applied before so that percentage resolution works correctly.
  var childSize = size(
    w = fstate.maxChildWidth,
    h = fstate.offset.y - sizes.padding.top
  )
  if sizes.padding.bottom != 0:
    let oldHeight = childSize.h
    bctx.flushMargins(childSize.h)
    fstate.intr.h += childSize.h - oldHeight
  box.applySize(sizes, childSize, fstate.space)
  let paddingSum = sizes.padding.sum()
  # Intrinsic minimum size includes the sum of our padding.  (However,
  # this padding must also be clamped to the same bounds.)
  box.applyIntr(sizes, fstate.intr + paddingSum)
  # Add padding; we cannot do this further up without influencing
  # relative positioning.
  box.state.size += paddingSum
  if bctx.marginTarget != fstate.initialMarginTarget or
      fstate.prevParentBps != nil and fstate.prevParentBps.resolved:
    # Our offset has already been resolved, ergo any margins in
    # marginTodo will be passed onto the next box. Set marginTarget to
    # nil, so that if we (or one of our ancestors) were still set as a
    # marginTarget, we no longer are.
    bctx.positionFloats()
    bctx.marginTarget = nil
  # Reset parentBps to the previous node.
  bctx.parentBps = fstate.prevParentBps

proc layoutFlowDescendant(bctx: var BlockContext; box: BlockBox; offset: Offset;
    sizes: ResolvedSizes) =
  box.resetState()
  box.sizes = sizes
  box.state.offset = offset
  bctx.layoutFlow(box, sizes)

proc layoutFlowRootPre(lctx: LayoutContext; box: BlockBox; offset: Offset;
    sizes: ResolvedSizes): bool =
  let offset = offset + sizes.borderTopLeft(lctx)
  if box.sizes == sizes:
    box.state.offset = offset
    return false
  box.sizes = sizes
  box.resetState()
  box.state.offset = offset
  true

proc layoutFlowRootPost(bctx: BlockContext; box: BlockBox) =
  assert bctx.unpositionedFloats.len == 0
  let marginBottom = bctx.marginTodo.sum()
  # If the highest float edge is higher than the box itself, set that as
  # the box height.
  box.state.size.h = max(box.state.size.h + marginBottom, bctx.maxFloatHeight)
  box.state.intr.h = max(box.state.intr.h + marginBottom, bctx.maxFloatHeight)
  box.state.marginBottom = marginBottom

proc layoutFlowRoot(bctx: var BlockContext; box: BlockBox; offset: Offset;
    sizes: ResolvedSizes) =
  if not bctx.lctx.layoutFlowRootPre(box, offset, sizes):
    return
  bctx.layoutFlow(box, sizes)
  bctx.layoutFlowRootPost(box)

# Table layout.  This imitates what mainstream browsers do, and that
# precludes a w3m-like single-pass algorithm.  Ours rather looks like:
# 1. Calculate minimum, maximum and preferred width of each column.
# 2. If column width is not auto, set width to max(min_width, specified).
# 3. Calculate the maximum preferred row width. If this is
# a) less than the specified table width, or
# b) greater than the table's content width:
#      Distribute the table's content width among cells proportionally to
#      their specified width.  If this would give any cell a width <
#      min_width, set that cell's width to min_width, then re-do the
#      distribution.
# 4. Relayout cells whose width changed since step 1.
# 5. Align cells based on their text-align.
#
# Rowspan/colspan handling: in general, overlapping rowspan & colspan is
# left to be.  However, if a column would *start* at a rowspan, then it is
# moved to the right by one column.  This means that a column only has one
# multi-row cell at a given time.
#
#TODO:
# * respect percentage width in redistribution - note this is a constraint,
#   not just a percentage of the table's parent width...
# * <col>, <colgroup>
# * distribute table height too
type
  CellWrapper = ref object
    box: BlockBox # may be nil
    coli: int
    colspan: int
    rowspan: int
    real: CellWrapper # for filler wrappers
    last: bool # is this the last filler?
    reflow: bool
    height: LUnit
    baseline: LUnit
    inlineBorder: Span
    next: CellWrapper

  RowContext = object
    cellHead: CellWrapper
    width: LUnit
    height: LUnit
    borderWidth: LUnit
    blockBorder: Span
    box: BlockBox
    ncols: int

  ColumnContext = object
    minwidth: LUnit
    width: LUnit
    wspecified: bool
    weight: float32
    reflow: int # last row index that need not be reflowed
    grown: int # number of remaining rows
    growing: CellWrapper

  TableContext = object
    lctx: LayoutContext
    rows: seq[RowContext]
    cols: seq[ColumnContext]
    maxwidth: LUnit
    blockSpacing: LUnit
    inlineSpacing: LUnit
    borderWidth: LUnit
    space: AvailableSpace # space we got from parent

proc layoutTableCell(lctx: LayoutContext; box: BlockBox;
    space: AvailableSpace; border: CSSBorder; merge: CSSBorderMerge) =
  box.sizes = ResolvedSizes(
    padding: lctx.resolvePadding(space.w, box.computed),
    space: availableSpace(w = space.w, h = maxContent()),
    bounds: DefaultBounds,
    border: border
  )
  box.resetState()
  box.state.merge = merge
  if box.sizes.space.w.isDefinite():
    box.sizes.space.w.u -= box.sizes.padding[dtHorizontal].sum()
  var bctx = initBlockContext(lctx)
  bctx.layout(box, offset(0, 0), box.sizes)
  assert bctx.unpositionedFloats.len == 0
  # If the highest float edge is higher than the box itself, set that as
  # the box height.
  box.state.size.h = max(box.state.size.h, bctx.maxFloatHeight)
  if space.h.t == scStretch:
    box.state.size.h = max(box.state.size.h, space.h.u -
      box.sizes.padding[dtVertical].sum())
  # A table cell's minimum width overrides its width.
  box.state.size.w = max(box.state.size.w, box.state.intr.w)
  # Ensure the cell has at least *some* baseline.
  if not box.state.baselineSet:
    box.state.firstBaseline = box.state.size.h
    box.state.baseline = box.state.size.h
    box.state.baselineSet = true

# Grow cells with a rowspan > 1 (to occupy their place in a new row).
proc growRowspan(tctx: var TableContext; growi, n: var int; ntill, growlen: int;
    width: var LUnit; cellHead, cellTail: var CellWrapper) =
  while growi < growlen:
    let cellw = tctx.cols[growi].growing
    if cellw == nil:
      inc growi
      continue
    if growi > ntill:
      break
    dec tctx.cols[growi].grown
    let grown = tctx.cols[growi].grown
    if grown == 0:
      tctx.cols[growi].growing = nil
    let colspan = cellw.colspan - (n - cellw.coli)
    let rowspanFiller = CellWrapper(
      colspan: colspan,
      rowspan: cellw.rowspan,
      coli: n,
      real: cellw,
      last: grown == 0,
      inlineBorder: cellw.inlineBorder
    )
    if cellTail != nil:
      cellTail.next = rowspanFiller
    else:
      cellHead = rowspanFiller
    cellTail = rowspanFiller
    for i in n ..< n + colspan:
      width += tctx.cols[i].width
      width += tctx.inlineSpacing * 2
    n += colspan
    inc growi

proc resolveBorder(tctx: var TableContext; computed: CSSValues;
    firstRow, lastCell, lastRow: bool; inlineBorder, blockBorder: var Span):
    CSSBorder =
  let lctx = tctx.lctx
  var border = computed.resolveBorder()
  if border.left notin BorderStyleNoneHidden:
    inlineBorder.start = max(lctx.cellSize.w div 2, inlineBorder.start)
  if border.right notin BorderStyleNoneHidden:
    inlineBorder.send = max(lctx.cellSize.w div 2, inlineBorder.send)
  if border.top notin BorderStyleNoneHidden:
    let d = if firstRow: 1 else: 2
    blockBorder.start = max(blockBorder.start, lctx.cellSize.h div d)
  if border.bottom notin BorderStyleNoneHidden:
    let d = if lastRow: 1 else: 2
    blockBorder.send = max(blockBorder.send, lctx.cellSize.h div d)
  if not lastCell:
    border[dtHorizontal].send = BorderStyleNone
  if not lastRow:
    border[dtVertical].send = BorderStyleNone
  border

proc preLayoutTableColspan(tctx: var TableContext; cellw: CellWrapper;
    space: AvailableSpace; rowi, n, nextn: int): LUnit =
  var width = 0.toLUnit()
  let colspan = cellw.colspan
  let minw = cellw.box.state.intr.w div colspan
  let w = cellw.box.state.size.w div colspan
  if tctx.cols.len < nextn:
    tctx.cols.setLen(nextn)
  for col in tctx.cols.toOpenArray(n, nextn - 1).mitems:
    # Figure out this cell's effect on the column's width.
    # Four cases exist:
    # 1. colwidth already fixed, cell width is fixed: take maximum
    # 2. colwidth already fixed, cell width is auto: take colwidth
    # 3. colwidth is not fixed, cell width is fixed: take cell width
    # 4. neither of colwidth or cell width are fixed: take maximum
    if col.wspecified:
      if space.w.isDefinite():
        # A specified column already exists; we take the larger width.
        if w > col.width:
          col.width = w
          col.reflow = rowi
      if col.width != w:
        cellw.reflow = true
    elif space.w.isDefinite():
      # This is the first specified column. Replace colwidth with whatever
      # we have.
      col.reflow = rowi
      col.wspecified = true
      col.width = w
    elif w > col.width:
      col.width = w
      col.reflow = rowi
    else:
      cellw.reflow = true
    if col.minwidth < minw:
      col.minwidth = minw
      if col.width < minw:
        col.width = minw
        col.reflow = rowi
    width += col.width
  let grown = cellw.rowspan - 1
  if grown > 0:
    tctx.cols[n].grown = grown
    tctx.cols[n].growing = cellw
  width

proc preLayoutTableRow(tctx: var TableContext; row, parent: BlockBox;
    rowi, numrows: int): RowContext =
  let lctx = tctx.lctx
  var cellHead: CellWrapper = nil
  var cellTail: CellWrapper = nil
  var blockBorder = Span(start: tctx.blockSpacing, send: tctx.blockSpacing)
  var n = 0
  var growi = 0
  var width = 0.toLUnit()
  var borderWidth = 0.toLUnit()
  var firstCell = true
  # this increases in the loop, but we only want to check growing cells that
  # were added by previous rows.
  let growlen = tctx.cols.len
  for box in row.children:
    let box = BlockBox(box)
    assert box.computed{"display"} == DisplayTableCell
    let firstRow = rowi == 0
    let colspan = box.computed{"-cha-colspan"}
    # grow until n, but not more
    tctx.growRowspan(growi, n, n, growlen, width, cellHead, cellTail)
    let rowspan = min(box.computed{"-cha-rowspan"}, numrows - rowi)
    let cw = box.computed{"width"}
    let ch = box.computed{"height"}
    let space = availableSpace(
      w = cw.stretchOrMeasure(tctx.space.w),
      h = ch.stretchOrMaxContent(tctx.space.h)
    )
    var inlineBorder = Span(start: tctx.inlineSpacing, send: tctx.inlineSpacing)
    var border = tctx.resolveBorder(box.computed, firstRow, box.next == nil,
      row.next == nil, inlineBorder, blockBorder)
    borderWidth += inlineBorder.sum()
    let merge = [dtHorizontal: not firstCell, dtVertical: not firstRow]
    lctx.layoutTableCell(box, space, border, merge)
    let cellw = CellWrapper(
      box: box,
      colspan: colspan,
      rowspan: rowspan,
      coli: n,
      inlineBorder: inlineBorder,
      reflow: space.w.t == scMeasure
    )
    if cellTail != nil:
      cellTail.next = cellw
    else:
      cellHead = cellw
    cellTail = cellw
    let nextn = n + colspan
    width += tctx.preLayoutTableColspan(cellw, space, rowi, n, nextn)
    # add spacing for border inside colspan
    width += tctx.inlineSpacing * (colspan - 1) * 2
    n = nextn
    firstCell = false
  tctx.growRowspan(growi, n, tctx.cols.len, growlen, width, cellHead, cellTail)
  RowContext(
    box: row,
    cellHead: cellHead,
    width: width + borderWidth,
    borderWidth: borderWidth,
    blockBorder: blockBorder,
    ncols: n
  )

proc alignTableCell(cell: BlockBox; availableHeight, baseline: LUnit) =
  let firstChild = BlockBox(cell.firstChild)
  if firstChild != nil:
    firstChild.state.offset.y += (case cell.computed{"vertical-align"}
    of VerticalAlignTop: 0.toLUnit()
    of VerticalAlignMiddle: availableHeight div 2 - cell.state.size.h div 2
    of VerticalAlignBottom: availableHeight - cell.state.size.h
    else: baseline - cell.state.firstBaseline)
  cell.state.size.h = availableHeight

proc layoutTableRow(tctx: TableContext; ctx: RowContext;
    parent, row: BlockBox; rowi: int) =
  row.resetState()
  var x: LUnit = 0
  var n = 0
  var baseline: LUnit = 0
  # real cellwrappers of fillers
  var toAlign: seq[CellWrapper] = @[]
  # cells with rowspan > 1 that must store baseline
  var toBaseline: seq[CellWrapper] = @[]
  # cells that we must update row height of
  var toHeight: seq[CellWrapper] = @[]
  var cellw = ctx.cellHead
  while cellw != nil:
    var w: LUnit = 0
    var reflow = cellw.reflow
    let colspan1 = cellw.colspan - 1
    for col in tctx.cols.toOpenArray(n, n + colspan1):
      w += col.width
      reflow = reflow or rowi < col.reflow
    # Add inline spacing for merged columns.
    w += tctx.inlineSpacing * colspan1 * 2
    if reflow and cellw.box != nil:
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
      let border = cellw.box.sizes.border
      let merge = cellw.box.state.merge
      tctx.lctx.layoutTableCell(cellw.box, space, border, merge)
      w = max(w, cellw.box.state.size.w)
      row.state.intr.w += cellw.box.state.intr.w
    let cell = cellw.box
    x += cellw.inlineBorder.start
    if cell != nil:
      cell.state.offset.x += x
    x += cellw.inlineBorder.send
    x += w
    row.state.intr.w += cellw.inlineBorder.sum()
    n += cellw.colspan
    const HasNoBaseline = {
      VerticalAlignTop, VerticalAlignMiddle, VerticalAlignBottom
    }
    if cell != nil:
      if cell.computed{"vertical-align"} notin HasNoBaseline:
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
    cellw = cellw.next
  for cellw in toHeight:
    cellw.height += row.state.size.h
  for cellw in toBaseline:
    cellw.baseline = baseline
  for cellw in toAlign:
    alignTableCell(cellw.box, cellw.height, cellw.baseline)
  for cell in row.children:
    let cell = BlockBox(cell)
    alignTableCell(cell, row.state.size.h, baseline)
  row.state.size.w = x

proc preLayoutTableRows(tctx: var TableContext; rows: openArray[BlockBox];
    table: BlockBox) =
  for i, row in rows.mypairs:
    let rctx = tctx.preLayoutTableRow(row, table, i, rows.len)
    tctx.maxwidth = max(rctx.width, tctx.maxwidth)
    tctx.borderWidth = max(rctx.borderWidth, tctx.borderWidth)
    tctx.rows.add(rctx)

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
    let child = BlockBox(child)
    let display = child.computed{"display"}
    if display == DisplayTableRow:
      tbody.add(child)
    else:
      for it in child.children:
        case display
        of DisplayTableHeaderGroup: thead.add(BlockBox(it))
        of DisplayTableRowGroup: tbody.add(BlockBox(it))
        of DisplayTableFooterGroup: tfoot.add(BlockBox(it))
        else: assert false, $child.computed{"display"}
  tctx.preLayoutTableRows(thead, table)
  tctx.preLayoutTableRows(tbody, table)
  tctx.preLayoutTableRows(tfoot, table)

proc calcSpecifiedRatio(tctx: TableContext; W: LUnit): LUnit =
  var totalSpecified: LUnit = 0
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

proc calcUnspecifiedColIndices(tctx: var TableContext; W: var LUnit;
    weight: var float32): seq[int] =
  let specifiedRatio = tctx.calcSpecifiedRatio(W)
  # Spacing for each column:
  var avail = newSeqOfCap[int](tctx.cols.len)
  for i, col in tctx.cols.mpairs:
    if not col.wspecified:
      avail.add(i)
      let w = if col.width < W:
        toFloat32(col.width)
      else:
        toFloat32(W) * (ln(toFloat32(col.width) / toFloat32(W)) + 1)
      col.weight = w
      weight += w
    else:
      if specifiedRatio != 1:
        col.width *= specifiedRatio
        col.reflow = tctx.rows.len
      W -= col.width
  move(avail)

proc needsRedistribution(tctx: TableContext; computed: CSSValues): bool =
  case tctx.space.w.t
  of scMinContent, scMaxContent, scMeasure:
    return false
  of scStretch:
    return tctx.space.w.u != tctx.maxwidth
  of scFitContent:
    return tctx.space.w.u > tctx.maxwidth and not computed{"width"}.auto or
        tctx.space.w.u < tctx.maxwidth

proc redistributeWidth(tctx: var TableContext) =
  # Remove inline spacing from distributable width.
  var W = max(tctx.space.w.u - tctx.borderWidth, 0)
  var weight = 0f32
  var avail = tctx.calcUnspecifiedColIndices(W, weight)
  var redo = true
  while redo and avail.len > 0 and weight != 0:
    if weight == 0: break # zero weight; nothing to distribute
    if W < 0:
      W = 0
    redo = false
    # divide delta width by sum of ln(width) for all elem in avail
    let unit = toFloat32(W) / weight
    weight = 0
    for i in countdown(avail.high, 0):
      let j = avail[i]
      let x = (unit * tctx.cols[j].weight).toLUnit()
      let mw = tctx.cols[j].minwidth
      tctx.cols[j].width = x
      if mw > x:
        W -= mw
        tctx.cols[j].width = mw
        avail.del(i)
        redo = true
      else:
        weight += tctx.cols[j].weight
      tctx.cols[j].reflow = tctx.rows.len

proc layoutTableRows(tctx: TableContext; table: BlockBox;
    sizes: ResolvedSizes) =
  var y: LUnit = 0
  for i, roww in tctx.rows.mypairs:
    if roww.box.computed{"visibility"} == VisibilityCollapse:
      continue
    y += roww.blockBorder.start
    let row = roww.box
    tctx.layoutTableRow(roww, table, row, i)
    row.state.offset.y += y
    row.state.offset.x += sizes.padding.left
    row.state.size.w += sizes.padding[dtHorizontal].sum()
    y += roww.blockBorder.send
    y += row.state.size.h
    table.state.size.w = max(row.state.size.w, table.state.size.w)
    table.state.intr.w = max(row.state.intr.w, table.state.intr.w)
  # Note: we can't use applySizeConstraint here; in CSS, "height" on tables just
  # sets the minimum height.
  case tctx.space.h.t
  of scStretch:
    table.state.size.h = max(tctx.space.h.u, y)
  of scMinContent, scMaxContent, scMeasure, scFitContent:
    # I don't think these are ever used here; not that they make much sense for
    # min-height...
    table.state.size.h = y

proc layoutCaption(lctx: LayoutContext; box: BlockBox; space: AvailableSpace;
    sizes: var ResolvedSizes) =
  sizes = lctx.resolveBlockSizes(space, box.computed)
  var bctx = initBlockContext(lctx)
  bctx.layout(box, sizes.margin.topLeft, sizes)

proc layoutInnerTable(tctx: var TableContext; table, parent: BlockBox;
    sizes: ResolvedSizes) =
  if table.computed{"border-collapse"} != BorderCollapseCollapse:
    tctx.inlineSpacing = table.computed{"-cha-border-spacing-inline"}.px(0)
    tctx.blockSpacing = table.computed{"-cha-border-spacing-block"}.px(0)
  tctx.preLayoutTableRows(table) # first pass
  # Percentage sizes have been resolved; switch the table's space to
  # fit-content if its width is auto.
  # (Note that we call canpx on space, which might have been changed by
  # specified width.  This isn't a problem however, because canpx will
  # still return true after that.)
  if tctx.space.w.t == scStretch:
    let width = parent.computed{"width"}
    if width.isPx():
      table.state.intr.w = tctx.space.w.u
    elif not width.canpx(tctx.space.w):
      tctx.space.w = fitContent(tctx.space.w.u)
  if tctx.needsRedistribution(table.computed):
    tctx.redistributeWidth()
  for col in tctx.cols:
    table.state.size.w += col.width
  tctx.layoutTableRows(table, sizes) # second pass
  # Table height is minimum by default, and non-negotiable when
  # specified, ergo it always equals the intrinisc minimum height.
  table.state.intr.h = table.state.size.h

# As per standard, we must put the caption outside the actual table,
# inside a block-level wrapper box.
#
# Note that computing the caption's width isn't as simple as it sounds.
# First, the caption's intrinsic minimum size overrides the available
# space (unlike what happens in flow, where available space wins).
# Second, table and caption width has a cyclic dependency, in that the
# larger of the two must be used for layouting both the cells and the
# caption.
#
# So conceptually we first layout caption, relayout with its intrinsic
# min size if needed, then layout table, then caption again if table's
# width exceeds caption's width.  (In practice, the second layout is
# skipped if there will be a third one, so we never layout more than
# twice.)
proc layoutTable(lctx: LayoutContext; box: BlockBox; offset: Offset;
    sizes: ResolvedSizes) =
  if not lctx.layoutFlowRootPre(box, offset, sizes):
    return
  let table = BlockBox(box.firstChild)
  table.resetState()
  var tctx = TableContext(lctx: lctx, space: sizes.space)
  let caption = BlockBox(table.next)
  var captionSpace = availableSpace(
    w = fitContent(sizes.space.w),
    h = maxContent()
  )
  var captionSizes: ResolvedSizes
  if caption != nil:
    lctx.layoutCaption(caption, captionSpace, captionSizes)
    if captionSpace.w.isDefinite():
      if caption.state.intr.w != captionSpace.w.u:
        captionSpace.w.u = caption.state.intr.w
      if tctx.space.w.t == scStretch and tctx.space.w.u < captionSpace.w.u:
        tctx.space.w.u = captionSpace.w.u
  tctx.layoutInnerTable(table, box, sizes)
  box.state.size = table.state.size
  box.state.intr = table.state.intr
  var baseline = 0.toLUnit()
  if caption != nil:
    if captionSpace.w.isDefinite():
      if table.state.size.w > captionSpace.w.u:
        captionSpace.w = stretch(table.state.size.w)
      if captionSpace.w.u != caption.state.size.w: # desired size changed; redo
        lctx.layoutCaption(caption, captionSpace, captionSizes)
    let outerSize = caption.outerSize(captionSizes, lctx)
    case caption.computed{"caption-side"}
    of CaptionSideTop, CaptionSideBlockStart:
      table.state.offset.y += outerSize.h
    of CaptionSideBottom, CaptionSideBlockEnd:
      caption.state.offset.y += table.state.size.h
    box.state.size.w = max(box.state.size.w, outerSize.w)
    box.state.intr.w = max(box.state.intr.w, caption.state.intr.w)
    box.state.size.h += outerSize.h
    box.state.intr.h += outerSize.h - caption.state.size.h +
      caption.state.intr.h
    if caption.state.baselineSet:
      baseline = max(baseline, caption.state.offset.y + caption.state.size.h)
  box.state.baseline = max(baseline, table.state.offset.y + table.state.size.h)
  box.state.firstBaseline = baseline
  box.state.baselineSet = true

# Flex layout.
type
  FlexWeightType = enum
    fwtGrow, fwtShrink

  FlexPendingItem = object
    child: BlockBox
    weights: array[FlexWeightType, float32]
    sizes: ResolvedSizes

  FlexContext = object
    mains: seq[FlexMainContext]
    offset: Offset
    lctx: LayoutContext
    totalMaxSize: Size
    intr: Size # intrinsic minimum size
    relativeChildren: seq[BlockBox]
    redistSpace: SizeConstraint
    firstBaseline: LUnit
    baseline: LUnit
    canWrap: bool
    reverse: bool
    dim: DimensionType # main dimension
    baselineSet: bool

  FlexMainContext = object
    totalSize: Size
    maxSize: Size
    shrinkSize: LUnit
    maxMargin: RelativeRect
    totalWeight: array[FlexWeightType, float32]
    pending: seq[FlexPendingItem]

proc layoutFlexItem(lctx: LayoutContext; box: BlockBox; sizes: ResolvedSizes) =
  var bctx = initBlockContext(lctx)
  bctx.layout(box, offset(x = 0, y = 0), sizes, forceRoot = true)

const FlexRow = {FlexDirectionRow, FlexDirectionRowReverse}

proc updateMaxSizes(mctx: var FlexMainContext; child: BlockBox;
    sizes: ResolvedSizes; lctx: LayoutContext) =
  for dim in DimensionType:
    mctx.maxSize[dim] = max(mctx.maxSize[dim], child.state.size[dim] +
      sizes.borderSize(dim, lctx).sum())
    mctx.maxMargin[dim].start = max(mctx.maxMargin[dim].start,
      sizes.margin[dim].start)
    mctx.maxMargin[dim].send = max(mctx.maxMargin[dim].send,
      sizes.margin[dim].send)

proc redistributeMainSize(mctx: var FlexMainContext; diff: LUnit;
    wt: FlexWeightType; dim: DimensionType; lctx: LayoutContext) =
  var diff = diff
  var totalWeight = mctx.totalWeight[wt]
  let odim = dim.opposite
  var relayout: seq[int] = @[]
  while (wt == fwtGrow and diff > 0 or wt == fwtShrink and diff < 0) and
      totalWeight > 0:
    # redo maxSize calculation; we only need height here
    mctx.maxSize[odim] = 0
    var udiv = totalWeight
    if wt == fwtShrink:
      udiv *= mctx.shrinkSize.toFloat32() / totalWeight
    let unit = if udiv != 0:
      diff.toFloat32() / udiv
    else:
      0
    # reset total weight & available diff for the next iteration (if there is
    # one)
    totalWeight = 0
    diff = 0
    relayout.setLen(0)
    for i, it in mctx.pending.mpairs:
      if it.weights[wt] == 0:
        mctx.updateMaxSizes(it.child, it.sizes, lctx)
        continue
      var uw = unit * it.weights[wt]
      if wt == fwtShrink:
        uw *= it.child.state.size[dim].toFloat32()
      var u = it.child.state.size[dim] + uw.toLUnit()
      # check for min/max violation
      let minu = max(it.child.state.intr[dim], it.sizes.bounds.a[dim].start)
      if minu > u:
        # min violation
        if wt == fwtShrink: # freeze
          diff += u - minu
          it.weights[wt] = 0
          mctx.shrinkSize -= it.child.state.size[dim]
        u = minu
        it.sizes.bounds.mi[dim].start = u
      let maxu = max(minu, it.sizes.bounds.a[dim].send)
      if maxu < u:
        # max violation
        if wt == fwtGrow: # freeze
          diff += u - maxu
          it.weights[wt] = 0
        u = maxu
        it.sizes.bounds.mi[dim].send = u
      u -= it.sizes.padding[dim].sum()
      it.sizes.space[dim] = stretch(u)
      # override minimum intrinsic size clamping too
      totalWeight += it.weights[wt]
      if it.weights[wt] == 0: # frozen, relayout immediately
        lctx.layoutFlexItem(it.child, it.sizes)
        mctx.updateMaxSizes(it.child, it.sizes, lctx)
      else: # delay relayout
        relayout.add(i)
    for i in relayout:
      let child = mctx.pending[i].child
      lctx.layoutFlexItem(child, mctx.pending[i].sizes)
      mctx.updateMaxSizes(child, mctx.pending[i].sizes, lctx)

proc flushMain(fctx: var FlexContext; mctx: var FlexMainContext;
    sizes: ResolvedSizes) =
  let dim = fctx.dim
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
  let maxMarginSum = mctx.maxMargin[odim].sum()
  let h = mctx.maxSize[odim] + maxMarginSum
  var intr = size(w = 0, h = 0)
  var offset = fctx.offset
  for it in mctx.pending.mitems:
    if it.child.state.size[odim] < h and not it.sizes.space[odim].isDefinite:
      # if the max height is greater than our height, then take max height
      # instead. (if the box's available height is definite, then this will
      # change nothing, so we skip it as an optimization.)
      it.sizes.space[odim] = stretch(h - it.sizes.margin[odim].sum() -
        it.sizes.borderSize(odim, lctx).sum())
      if odim == dtVertical:
        # Exclude the bottom margin; space only applies to the actual
        # height.
        it.sizes.space[odim].u -= it.child.state.marginBottom
      lctx.layoutFlexItem(it.child, it.sizes)
    offset[dim] += it.sizes.margin[dim].start
    it.child.state.offset[dim] += offset[dim]
    # resolve auto cross margins for shrink-to-fit items
    if sizes.space[odim].t == scStretch:
      let start = it.child.computed.getLength(MarginStartMap[odim])
      let send = it.child.computed.getLength(MarginEndMap[odim])
      # We can get by without adding offset, because flex items are
      # always layouted at (0, 0).
      let underflow = sizes.space[odim].u - it.child.state.size[odim] -
        it.sizes.margin[odim].sum() - it.sizes.borderSize(odim, lctx).sum()
      if underflow > 0 and start.auto:
        # we don't really care about the end margin, because that is
        # already taken into account by AvailableSpace
        if not send.auto:
          it.sizes.margin[odim].start = underflow
        else:
          it.sizes.margin[odim].start = underflow div 2
    # margins are added here, since they belong to the flex item.
    it.child.state.offset[odim] += offset[odim] + it.sizes.margin[odim].start
    offset[dim] += it.child.state.size[dim]
    offset[dim] += it.sizes.margin[dim].send
    offset[dim] += it.sizes.borderSize(dim, lctx).sum()
    let intru = it.child.state.intr[dim] + it.sizes.margin[dim].sum()
    if fctx.canWrap:
      intr[dim] = max(intr[dim], intru)
    else:
      intr[dim] += intru
    intr[odim] = max(it.child.state.intr[odim], intr[odim])
    if it.child.computed{"position"} == PositionRelative:
      fctx.relativeChildren.add(it.child)
    let baseline = it.child.state.offset.y + it.child.state.baseline
    if not fctx.baselineSet:
      fctx.baselineSet = true
      fctx.firstBaseline = baseline
    fctx.baseline = baseline
  if fctx.reverse:
    for it in mctx.pending:
      let child = it.child
      child.state.offset[dim] = offset[dim] - child.state.offset[dim] -
        child.state.size[dim]
  fctx.totalMaxSize[dim] = max(fctx.totalMaxSize[dim], offset[dim])
  fctx.mains.add(mctx)
  fctx.intr[dim] = max(fctx.intr[dim], intr[dim])
  fctx.intr[odim] += intr[odim] + maxMarginSum
  mctx = FlexMainContext()
  fctx.offset[odim] += h

proc layoutFlexIter(fctx: var FlexContext; mctx: var FlexMainContext;
    child: BlockBox; sizes: ResolvedSizes) =
  let lctx = fctx.lctx
  let dim = fctx.dim
  var childSizes = lctx.resolveFlexItemSizes(sizes.space, dim, child.computed)
  let flexBasis = child.computed{"flex-basis"}
  let childMinBounds = childSizes.bounds.a[dim]
  let skipBounds = childSizes.space[dim].t == scMaxContent
  if skipBounds:
    childSizes.bounds.a[dim] = DefaultSpan
  lctx.layoutFlexItem(child, childSizes)
  if not flexBasis.auto and sizes.space[dim].isDefinite:
    # we can't skip this pass; it is needed to calculate the minimum
    # height.
    let minu = child.state.intr[dim]
    childSizes.space[dim] = stretch(flexBasis.spx(sizes.space[dim],
      child.computed, childSizes.padding[dim].sum()))
    if minu > childSizes.space[dim].u:
      # First pass gave us a box that is thinner than the minimum
      # acceptable width for whatever reason; this may have happened
      # because the initial flex basis was e.g. 0. Try to resize it to
      # something more usable.
      childSizes.space[dim] = stretch(minu)
    lctx.layoutFlexItem(child, childSizes)
  if skipBounds:
    childSizes.bounds.a[dim] = childMinBounds
  if child.computed{"position"} in PositionAbsoluteFixed:
    # Absolutely positioned flex children do not participate in flex layout.
    child.state.offset = offset(0, 0)
  else:
    if fctx.canWrap and (sizes.space[dim].t == scMinContent or
        sizes.space[dim].isDefinite and
        mctx.totalSize[dim] + child.state.size[dim] > sizes.space[dim].u):
      fctx.flushMain(mctx, sizes)
    let outerSize = child.outerSize(dim, childSizes, lctx)
    mctx.updateMaxSizes(child, childSizes, lctx)
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

proc layoutFlex(lctx: LayoutContext; box: BlockBox; offset: Offset;
    sizes: ResolvedSizes) =
  if not lctx.layoutFlowRootPre(box, offset, sizes):
    return
  let flexDir = box.computed{"flex-direction"}
  let dim = if flexDir in FlexRow: dtHorizontal else: dtVertical
  let odim = dim.opposite()
  var fctx = FlexContext(
    lctx: lctx,
    offset: sizes.padding.topLeft,
    redistSpace: sizes.space[dim],
    canWrap: box.computed{"flex-wrap"} != FlexWrapNowrap,
    reverse: box.computed{"flex-direction"} in FlexReverse,
    dim: dim
  )
  if fctx.redistSpace.t == scFitContent and sizes.bounds.a[dim].start > 0:
    fctx.redistSpace = stretch(sizes.bounds.a[dim].start)
  if fctx.redistSpace.isDefinite:
    fctx.redistSpace.u = fctx.redistSpace.u.minClamp(sizes.bounds.a[dim])
  var mctx = FlexMainContext()
  for child in box.children:
    let child = BlockBox(child)
    fctx.layoutFlexIter(mctx, child, sizes)
  if mctx.pending.len > 0:
    fctx.flushMain(mctx, sizes)
  var size = fctx.totalMaxSize
  size[odim] = fctx.offset[odim]
  size += sizes.padding.bottomRight
  box.applySize(sizes, size, sizes.space)
  box.applyIntr(sizes, fctx.intr)
  box.state.baselineSet = fctx.baselineSet
  box.state.firstBaseline = fctx.firstBaseline
  box.state.baseline = fctx.baseline
  for child in fctx.relativeChildren:
    lctx.positionRelative(sizes.space, child)

proc layout(bctx: var BlockContext; box: BlockBox; offset: Offset;
    sizes: ResolvedSizes; forceRoot = false) =
  case box.computed{"display"}
  of DisplayFlowRoot, DisplayTableCaption, DisplayInlineBlock, DisplayInnerGrid,
      DisplayMarker:
    bctx.layoutFlowRoot(box, offset, sizes)
  of DisplayBlock, DisplayListItem:
    if forceRoot or box.computed{"position"} in PositionAbsoluteFixed or
        box.computed{"float"} != FloatNone or
        box.computed{"overflow-x"} notin {OverflowVisible, OverflowClip}:
      bctx.layoutFlowRoot(box, offset, sizes)
    else:
      bctx.layoutFlowDescendant(box, offset, sizes)
  of DisplayTableCell: bctx.layoutFlow(box, sizes)
  of DisplayInnerTable: bctx.lctx.layoutTable(box, offset, sizes)
  of DisplayInnerFlex: bctx.lctx.layoutFlex(box, offset, sizes)
  else: assert false
  if sizes.space.w.t != scMeasure:
    bctx.lctx.popPositioned(box.absolute, box.state.size)

proc layout*(box: BlockBox; attrs: WindowAttributes; fixedHead: CSSAbsolute;
    luctx: LUContext) =
  let space = availableSpace(
    w = stretch(attrs.widthPx),
    h = stretch(attrs.heightPx)
  )
  let cellSize = size(w = attrs.ppc, h = attrs.ppl)
  let lctx = LayoutContext(cellSize: cellSize, luctx: luctx)
  let sizes = lctx.resolveBlockSizes(space, box.computed)
  var bctx = initBlockContext(lctx)
  # the bottom margin is unused.
  bctx.layout(box, sizes.margin.topLeft, sizes, forceRoot = true)
  # Fixed containing block.
  # The idea is to move fixed boxes to the real edges of the page,
  # so that they do not overlap with other boxes *and* we don't have
  # to move them on scroll. It's still not compatible with what desktop
  # browsers do, but the alternative would completely break search (and
  # slow down the renderer to a crawl.)
  var size = size(w = attrs.widthPx, h = attrs.heightPx)
  size.w = max(size.w, box.state.size.w)
  size.h = max(size.h, box.state.size.h)
  lctx.popPositioned(fixedHead, size)

{.pop.} # raises: []
