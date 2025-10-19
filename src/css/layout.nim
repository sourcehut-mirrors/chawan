{.push raises: [].}

# Note: if you start (or stop) using a property in layout, don't forget to
# modify LayoutProperties in cssvalues.

import std/math

import css/box
import css/cssparser
import css/cssvalues
import css/lunit
import types/bitmap
import types/winattrs
import utils/luwrap
import utils/strwidth
import utils/twtstr
import utils/widthconv

type
  LayoutContext = ref object
    cellSize: Size # size(w = attrs.ppc, h = attrs.ppl)
    luctx: LUContext

const DefaultSpan = Span(start: 0'lu, send: LUnit.high)

proc minWidth(input: LayoutInput): LUnit =
  return input.bounds.a[dtHorizontal].start

proc maxWidth(input: LayoutInput): LUnit =
  return input.bounds.a[dtHorizontal].send

proc minHeight(input: LayoutInput): LUnit =
  return input.bounds.a[dtVertical].start

proc maxHeight(input: LayoutInput): LUnit =
  return input.bounds.a[dtVertical].send

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

proc initSpace(w, h: SizeConstraint): Space =
  return [dtHorizontal: w, dtVertical: h]

proc w(space: Space): SizeConstraint {.inline.} =
  return space[dtHorizontal]

proc w(space: var Space): var SizeConstraint {.inline.} =
  return space[dtHorizontal]

proc `w=`(space: var Space; w: SizeConstraint) {.inline.} =
  space[dtHorizontal] = w

proc h(space: var Space): var SizeConstraint {.inline.} =
  return space[dtVertical]

proc h(space: Space): SizeConstraint {.inline.} =
  return space[dtVertical]

proc `h=`(space: var Space; h: SizeConstraint) {.inline.} =
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
    return 0'lu
  return (p.toFloat32() * l.perc + l.npx).toLUnit()

proc px(l: CSSLength; p: SizeConstraint): LUnit {.inline.} =
  if l.perc == 0:
    return l.npx.toLUnit()
  if l.auto:
    return 0'lu
  if p.t == scStretch:
    return (p.u.toFloat32() * l.perc + l.npx).toLUnit()
  return 0'lu

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

proc borderTopLeft(input: LayoutInput; lctx: LayoutContext): Offset =
  input.borderTopLeft(lctx.cellSize)

proc borderSize(input: LayoutInput; dim: DimensionType; lctx: LayoutContext):
    Span =
  var span = Span()
  if input.border[dim].start notin BorderStyleNoneHidden:
    span.start = lctx.cellSize[dim]
  if input.border[dim].send notin BorderStyleNoneHidden and
      (dim == dtHorizontal or input.border[dim].send notin BorderStyleInput):
    span.send = lctx.cellSize[dim]
  return span

proc borderSum(input: LayoutInput; dim: DimensionType; lctx: LayoutContext):
    LUnit =
  input.borderSize(dim, lctx).sum()

proc borderTop(input: LayoutInput; lctx: LayoutContext): LUnit =
  if input.border[dtVertical].start notin BorderStyleNoneHidden:
    return lctx.cellSize[dtVertical]
  return 0'lu

proc borderBottom(input: LayoutInput; lctx: LayoutContext): LUnit =
  if input.border[dtVertical].send notin BorderStyleNoneHidden:
    return lctx.cellSize[dtVertical]
  return 0'lu

proc borderLeft(input: LayoutInput; lctx: LayoutContext): LUnit =
  if input.border[dtHorizontal].start notin BorderStyleNoneHidden:
    return lctx.cellSize[dtHorizontal]
  return 0'lu

proc borderRight(input: LayoutInput; lctx: LayoutContext): LUnit =
  if input.border[dtHorizontal].send notin BorderStyleNoneHidden:
    return lctx.cellSize[dtHorizontal]
  return 0'lu

proc outerSize(box: BlockBox; dim: DimensionType; input: LayoutInput;
    lctx: LayoutContext): LUnit =
  return input.margin[dim].sum() + box.state.size[dim] +
    input.borderSum(dim, lctx)

proc outerSize(box: BlockBox; input: LayoutInput; lctx: LayoutContext): Size =
  return size(
    w = box.outerSize(dtHorizontal, input, lctx),
    h = box.outerSize(dtVertical, input, lctx)
  )

proc max(span: Span): LUnit =
  return max(span.start, span.send)

# In CSS, "min" beats "max".
proc minClamp(x: LUnit; span: Span): LUnit =
  return max(min(x, span.send), span.start)

# Note: padding must still be applied after this.
proc applySize(box: BlockBox; bounds: Bounds; maxChildSize: LUnit; space: Space;
    dim: DimensionType) =
  # Make the box as small/large as the content's width or specified width.
  box.state.size[dim] = maxChildSize.applySizeConstraint(space[dim])
  # Then, clamp it to minWidth and maxWidth (if applicable).
  box.state.size[dim] = box.state.size[dim].minClamp(bounds.a[dim])

proc applySize(box: BlockBox; input: LayoutInput; maxChildSize: Size;
    space: Space) =
  for dim in DimensionType:
    box.applySize(input.bounds, maxChildSize[dim], space, dim)

proc applyIntr(box: BlockBox; input: LayoutInput; intr: Size) =
  for dim in DimensionType:
    const pt = [dtHorizontal: cptOverflowX, dtVertical: cptOverflowY]
    if box.computed.bits[pt[dim]].overflow notin OverflowScrollLike:
      box.state.intr[dim] = intr[dim].minClamp(input.bounds.mi[dim])
    else:
      # We do not have a scroll bar, so do the next best thing: expand the
      # box to the size its contents want.  (Or the specified size, if
      # it's greater.)
      #TODO intrinsic minimum size isn't really guaranteed to equal the
      # desired scroll size. Also, it's possible that a parent box clamps
      # the height of this box; in that case, the parent box's
      # width/height should be clamped to the inner scroll width/height
      # instead.
      box.state.intr[dim] = max(intr[dim], input.bounds.mi[dim].start)
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

proc spx(l: CSSLength; p: SizeConstraint; computed: CSSValues; padding: LUnit):
    LUnit =
  let u = l.px(p)
  if computed{"box-sizing"} == BoxSizingBorderBox:
    return max(u - padding, 0'lu)
  return max(u, 0'lu)

proc resolveUnderflow(input: var LayoutInput; parentSize: SizeConstraint;
    computed: CSSValues; lctx: LayoutContext) =
  let dim = dtHorizontal
  # width must be definite, so that conflicts can be resolved
  if input.space[dim].isDefinite() and parentSize.t == scStretch:
    let start = computed.getLength(MarginStartMap[dim])
    let send = computed.getLength(MarginEndMap[dim])
    let underflow = parentSize.u - input.space[dim].u -
      input.margin[dim].sum() - input.padding[dim].sum() -
      input.borderSum(dim, lctx)
    if underflow > 0'lu and start.auto:
      if not send.auto:
        input.margin[dim].start = underflow
      else:
        input.margin[dim].start = underflow div 2'lu

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
      start: max(computed{"padding-left"}.px(availableWidth), 0'lu),
      send: max(computed{"padding-right"}.px(availableWidth), 0'lu)
    ),
    dtVertical: Span(
      start: max(computed{"padding-top"}.px(availableWidth), 0'lu),
      send: max(computed{"padding-bottom"}.px(availableWidth), 0'lu)
    )
  ]

proc roundSmallMarginsAndPadding(lctx: LayoutContext;
    input: var LayoutInput) =
  for i, it in input.padding.mpairs:
    let cs = lctx.cellSize[i]
    it.start = (it.start div cs).toInt.toLUnit * cs
    it.send = (it.send div cs).toInt.toLUnit * cs
  for i, it in input.margin.mpairs:
    let cs = lctx.cellSize[i]
    it.start = (it.start div cs).toInt.toLUnit * cs
    it.send = (it.send div cs).toInt.toLUnit * cs

proc resolveBorder(computed: CSSValues; margin: var RelativeRect): CSSBorder =
  const Map = [
    dtHorizontal: {
      cptBorderLeftStyle: cptBorderLeftWidth,
      cptBorderRightStyle: cptBorderRightWidth
    },
    dtVertical: {
      cptBorderTopStyle: cptBorderTopWidth,
      cptBorderBottomStyle: cptBorderBottomWidth
    }
  ]
  result = CSSBorder.default
  for dim, it in Map:
    let styleStart = computed.getBorderStyle(it[0][0])
    if styleStart != BorderStyleNone:
      let w = computed.getLineWidth(it[0][1]).toLUnit()
      if w != 0'lu:
        let e = 1'lu - w
        if e > 0'lu and margin[dim].start <= e:
          margin[dim].start -= e # correct error
        result[dim].start = styleStart
    let styleEnd = computed.getBorderStyle(it[1][0])
    if styleEnd != BorderStyleNone:
      let w = computed.getLineWidth(it[1][1]).toLUnit()
      if w != 0'lu:
        let e = 1'lu - w
        if e > 0'lu and margin[dim].send <= e:
          margin[dim].send -= e # correct error
        result[dim].send = styleEnd

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

proc resolveBounds(lctx: LayoutContext; space: Space; padding: Size;
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
    positioned: RelativeRect; computed: CSSValues; input: var LayoutInput) =
  let paddingSum = input.padding[dtHorizontal].sum()
  if computed{"width"}.auto:
    let u = max(size.w - positioned[dtHorizontal].sum() - paddingSum -
      input.margin[dtHorizontal].sum() - input.borderSum(dtHorizontal, lctx),
      0'lu)
    if not computed{"left"}.auto and not computed{"right"}.auto:
      # Both left and right are known, so we can calculate the width.
      input.space.w = stretch(u)
    else:
      # Return shrink to fit and solve for left/right.
      input.space.w = fitContent(u)
  else:
    let sizepx = computed{"width"}.spx(stretch(size.w), computed, paddingSum)
    input.space.w = stretch(sizepx)

proc resolveAbsoluteHeight(lctx: LayoutContext; size: Size;
    positioned: RelativeRect; computed: CSSValues; input: var LayoutInput) =
  let paddingSum = input.padding[dtVertical].sum()
  if computed{"height"}.auto:
    if not computed{"top"}.auto and not computed{"bottom"}.auto:
      # Both top and bottom are known, so we can calculate the height.
      # Well, but subtract padding and margin first.
      let u = max(size.h - positioned[dtVertical].sum() - paddingSum -
        input.margin[dtVertical].sum() - input.borderSum(dtVertical, lctx),
        0'lu)
      input.space.h = stretch(u)
    else:
      # The height is based on the content.
      input.space.h = maxContent()
  else:
    let sizepx = computed{"height"}.spx(stretch(size.h), computed, paddingSum)
    input.space.h = stretch(sizepx)

# Calculate and resolve available width & height for absolutely positioned
# boxes.
proc resolveAbsoluteSizes(lctx: LayoutContext; size: Size;
    positioned: RelativeRect; computed: CSSValues): LayoutInput =
  var input = LayoutInput(
    margin: lctx.resolveMargins(stretch(size.w), computed),
    padding: lctx.resolvePadding(stretch(size.w), computed),
    bounds: DefaultBounds
  )
  input.border = computed.resolveBorder(input.margin)
  lctx.resolveAbsoluteWidth(size, positioned, computed, input)
  lctx.resolveAbsoluteHeight(size, positioned, computed, input)
  return input

# Calculate and resolve available width & height for floating boxes.
proc resolveFloatSizes(lctx: LayoutContext; space: Space; computed: CSSValues):
    LayoutInput =
  var input = LayoutInput(
    margin: lctx.resolveMargins(space.w, computed),
    padding: lctx.resolvePadding(space.w, computed),
    space: space
  )
  input.border = computed.resolveBorder(input.margin)
  if computed{"display"} in DisplayInlineBlockLike:
    lctx.roundSmallMarginsAndPadding(input)
  let paddingSum = input.padding.sum()
  input.bounds = lctx.resolveBounds(space, paddingSum, computed)
  input.space.h = maxContent()
  for dim in DimensionType:
    let length = computed.getLength(SizeMap[dim])
    if length.canpx(space[dim]):
      let u = length.spx(space[dim], computed, paddingSum[dim])
      input.space[dim] = stretch(minClamp(u, input.bounds.a[dim]))
    elif input.space[dim].isDefinite():
      let u = input.space[dim].u - input.margin[dim].sum() - paddingSum[dim]
      input.space[dim] = fitContent(minClamp(u, input.bounds.a[dim]))
  return input

proc resolveFlexItemSizes(lctx: LayoutContext; space: Space; dim: DimensionType;
    computed: CSSValues): LayoutInput =
  let padding = lctx.resolvePadding(space.w, computed)
  let paddingSum = padding.sum()
  var input = LayoutInput(
    margin: lctx.resolveMargins(space.w, computed),
    padding: padding,
    space: space,
    bounds: lctx.resolveBounds(space, paddingSum, computed, flexItem = true)
  )
  input.border = computed.resolveBorder(input.margin)
  if dim != dtHorizontal:
    input.space.h = maxContent()
  let length = computed.getLength(SizeMap[dim])
  if length.canpx(space[dim]):
    let u = length.spx(space[dim], computed, paddingSum[dim])
      .minClamp(input.bounds.a[dim])
    input.space[dim] = stretch(u)
    if computed{"flex-shrink"} == 0:
      input.bounds.mi[dim].start = max(u, input.bounds.mi[dim].start)
    if computed{"flex-grow"} == 0:
      input.bounds.mi[dim].send = min(u, input.bounds.mi[dim].send)
  elif space[dim].t == scStretch and input.bounds.a[dim].send < LUnit.high:
    input.space[dim] = stretch(input.bounds.a[dim].max())
  else:
    # Ensure that space is indefinite in the first pass if no width has
    # been specified.
    input.space[dim] = maxContent()
  let odim = dim.opposite()
  let olength = computed.getLength(SizeMap[odim])
  if olength.canpx(space[odim]):
    let u = olength.spx(space[odim], computed, paddingSum[odim])
      .minClamp(input.bounds.a[odim])
    input.space[odim] = stretch(u)
    if olength.isPx:
      input.bounds.mi[odim].start = max(u, input.bounds.mi[odim].start)
      input.bounds.mi[odim].send = min(u, input.bounds.mi[odim].send)
  elif input.space[odim].isDefinite():
    let u = input.space[odim].u - input.margin[odim].sum() - paddingSum[odim] -
      input.borderSum(odim, lctx)
    input.space[odim] = SizeConstraint(
      t: input.space[odim].t,
      u: minClamp(u, input.bounds.a[odim])
    )
    if computed.getLength(MarginStartMap[odim]).auto or
        computed.getLength(MarginEndMap[odim]).auto:
      input.space[odim].t = scFitContent
  elif input.bounds.a[odim].send < LUnit.high:
    input.space[odim] = stretch(input.bounds.a[odim].max())
  return input

proc resolveBlockWidth(input: var LayoutInput; parentWidth: SizeConstraint;
    inlinePadding: LUnit; computed: CSSValues;
    lctx: LayoutContext) =
  let dim = dtHorizontal
  let width = computed{"width"}
  if width.canpx(parentWidth):
    input.space.w = stretch(width.spx(parentWidth, computed, inlinePadding))
    input.resolveUnderflow(parentWidth, computed, lctx)
    if width.isPx:
      let px = input.space.w.u
      input.bounds.mi[dim].start = max(input.bounds.mi[dim].start, px)
      input.bounds.mi[dim].send = min(input.bounds.mi[dim].send, px)
  elif parentWidth.t == scStretch:
    let underflow = parentWidth.u - input.margin[dim].sum() -
      input.padding[dim].sum() - input.borderSum(dim, lctx)
    if underflow >= 0'lu:
      input.space.w = stretch(underflow)
    else:
      input.space.w = stretch(0'lu)
      input.margin[dtHorizontal].send += underflow
  if input.space.w.isDefinite() and input.maxWidth < input.space.w.u or
      input.maxWidth < LUnit.high and
      input.space.w.t in {scMaxContent, scMeasure}:
    if input.space.w.t == scStretch:
      # available width would stretch over max-width
      input.space.w = stretch(input.maxWidth)
    else: # scFitContent
      # available width could be higher than max-width (but not necessarily)
      input.space.w = fitContent(input.maxWidth)
    input.resolveUnderflow(parentWidth, computed, lctx)
    input.bounds.mi[dim].send = input.space.w.u
  if input.space.w.isDefinite() and input.minWidth > input.space.w.u or
      input.minWidth > 0'lu and input.space.w.t == scMinContent:
    # two cases:
    # * available width is stretched under min-width. in this case,
    #   stretch to min-width instead.
    # * available width is fit under min-width. in this case, stretch to
    #   min-width as well (as we must satisfy min-width >= width).
    input.space.w = stretch(input.minWidth)
    input.resolveUnderflow(parentWidth, computed, lctx)

proc resolveBlockHeight(input: var LayoutInput; parentHeight: SizeConstraint;
    blockPadding: LUnit; computed: CSSValues;
    lctx: LayoutContext) =
  let dim = dtVertical
  let height = computed{"height"}
  if height.canpx(parentHeight):
    let px = height.spx(parentHeight, computed, blockPadding)
    input.space.h = stretch(px)
    if height.isPx:
      input.bounds.mi[dim].start = max(input.bounds.mi[dim].start, px)
      input.bounds.mi[dim].send = min(input.bounds.mi[dim].send, px)
  if input.space.h.isDefinite() and input.maxHeight < input.space.h.u or
      input.maxHeight < LUnit.high and
      input.space.h.t in {scMaxContent, scMeasure}:
    # same reasoning as for width.
    if input.space.h.t == scStretch:
      input.space.h = stretch(input.maxHeight)
    else: # scFitContent
      input.space.h = fitContent(input.maxHeight)
  if input.space.h.isDefinite() and input.minHeight > input.space.h.u or
      input.minHeight > 0'lu and input.space.h.t == scMinContent:
    # same reasoning as for width.
    input.space.h = stretch(input.minHeight)

proc resolveBlockSizes(lctx: LayoutContext; space: Space; computed: CSSValues):
    LayoutInput =
  let padding = lctx.resolvePadding(space.w, computed)
  let paddingSum = padding.sum()
  var input = LayoutInput(
    margin: lctx.resolveMargins(space.w, computed),
    padding: padding,
    space: space,
    bounds: lctx.resolveBounds(space, paddingSum, computed),
  )
  input.border = computed.resolveBorder(input.margin)
  # height is max-content normally, but fit-content for clip.
  input.space.h = if computed{"overflow-y"} != OverflowClip:
    maxContent()
  else:
    fitContent(input.space.h)
  # Finally, calculate available width and height.
  input.resolveBlockWidth(space.w, paddingSum[dtHorizontal], computed, lctx)
  #TODO parent height should be lctx height in quirks mode for percentage
  # resolution.
  input.resolveBlockHeight(space.h, paddingSum[dtVertical], computed, lctx)
  if computed{"display"} == DisplayListItem:
    # Eliminate distracting margins and padding here, because
    # resolveBlockWidth may change them beforehand.
    lctx.roundSmallMarginsAndPadding(input)
  if input.space.h.isDefinite() and input.space.h.u == 0'lu and
      paddingSum[dtVertical] == 0'lu and
      input.border.bottom notin BorderStyleInput:
    # prevent ugly <hr> when set using border (not just border-style-bottom)
    input.border[dtHorizontal] = BorderStyleSpan()
    if input.border[dtVertical].send notin BorderStyleNoneHidden:
      input.border[dtVertical].start = BorderStyleHidden
  return input

# Flow layout.  Probably the most complex part of CSS.
#
# One would be excused for thinking that flow can be subdivided into
# "inline" and "block" layouts.  This approach isn't exactly wrong -
# indeed, it seems to be the most intuitive interpretation of CSS 2.1,
# and is how I first did it - but mainstream browsers behave otherwise,
# so it is more useful to recognize flow as a single layout type.
#
# Flow is rooted in any block box that establishes a Block Formatting
# Context (BFC)[1].  State associated with these is passed over to (and read
# from) children that do not establish a BFC.
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
#   pendingFloats in LineBoxState).
#
# * Consider this:
#   <div style="margin-top: 1em">
#   <div style="float: left">float</div>
#   <div style="margin-top: 2em"></div>
#   </div>
#   The float moves to 2em from the top, not 1em!
#   This means that floats can only be positioned once their parent's margin
#   is known; until then, they live in the pendingFloats list.
#
## Margin collapsing
#
# The algorithm looks something like:
# * track BFC position for each (non-root) flow block
# * look for the first child that resolves the margin (flushMargins)
# * position floats in said child, pretending that the parent's y position
#   is already flushed
# * once the child's layout is finished, move the ancestors' BFC position by
#   the margin the child has output (marginOutput)
# * finally, as the first ancestor box is reached for which the margin is
#   unresolved but the margin of its parent isn't, move said ancestor by
#   marginOutput, and then set it to 0.
#
# It gets a bit messy when floats are involved: unpositioned floats on the
# current line can just use the BFC position of the line's flow state, but
# BFC-level unpositioned floats must be shifted inside flushMargins, making
# sure that we don't leak state of an individual block box outside (i.e.
# using the temporary yshift variable instead of updating bfcOffset itself.)
type
  LineInitState = enum
    lisUninited, lisNoExclusions, lisExclusions

  LineBoxState = object
    atomsHead: InlineAtom
    atomsTail: InlineAtom
    charwidth: int
    paddingTodo: seq[tuple[box: InlineBox; i: int]]
    # absolutes that want to stick to the next atom
    pendingAbsolutes: seq[BlockBox]
    size: Size
    pendingFloatsHead: PendingFloat
    pendingFloatsTail: PendingFloat
    lastrw: int # last rune width of the previous word
    firstrw: int # first rune width of the current word
    prevrw: int # last processed rune's width
    whitespaceBox: InlineTextBox
    whitespaceNum: int
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
    # float values currently included in pendingFloats.
    floatsSeen: set[CSSFloat]
    whitespaceIsLF: bool

  WordState = object
    s: string
    ibox: InlineTextBox
    wrapPos: int # position of last wrapping opportunity, or -1
    width: LUnit
    intrWidth: LUnit # intrinsic size of currently processed word segment
    hasSoftHyphen: bool

  InlineAtom = ref object
    ibox: InlineBox
    box: BlockBox
    run: TextRun
    offset: Offset
    size: Size
    absolutes: seq[BlockBox]
    next: InlineAtom

  FlowState = object
    lctx: LayoutContext
    box: BlockBox
    bfcOffset: Offset
    offset: Offset
    maxChildWidth: LUnit
    totalFloatWidth: LUnit # used for re-layouts
    space: Space
    intr: Size
    marginResolved: bool
    textAlign: CSSTextAlign # text align of parent, for block-level alignment
    marginOutput: LUnit
    maxFloatHeight: LUnit
    clearOffset: LUnit
    marginTodo: Span
    pendingFloatsHead: PendingFloat
    pendingFloatsTail: PendingFloat
    exclusionsHead: Exclusion
    exclusionsTail: Exclusion
    # Inline context state:
    lbstate: LineBoxState

# Forward declarations
proc layout(lctx: LayoutContext; box: BlockBox; offset: Offset;
  input: LayoutInput; forceRoot = false)

iterator exclusions(fstate: FlowState): Exclusion {.inline.} =
  var ex = fstate.exclusionsHead
  while ex != nil:
    yield ex
    if ex == fstate.exclusionsTail:
      break
    ex = ex.next

proc nowrap(computed: CSSValues): bool =
  computed{"white-space"} in {WhitespaceNowrap, WhitespacePre}

template cellSize(fstate: FlowState): Size =
  fstate.lctx.cellSize

template computed(fstate: FlowState): CSSValues =
  fstate.box.computed

proc lastTextBox(fstate: FlowState): InlineBox =
  if fstate.lbstate.whitespaceBox != nil:
    return fstate.lbstate.whitespaceBox
  if fstate.lbstate.atomsTail != nil:
    return fstate.lbstate.atomsTail.ibox
  nil

proc addMargin(a: var Span; b: LUnit) =
  if b < 0'lu:
    a.start = min(b, a.start)
  else:
    a.send = max(b, a.send)

proc clearFloats(offsety: var LUnit; fstate: var FlowState; bfcOffsety: LUnit;
    clear: CSSClear; cleared: var bool) =
  let oy = bfcOffsety + offsety
  var y = oy
  let target = case clear
  of ClearLeft, ClearInlineStart: FloatLeft
  of ClearRight, ClearInlineEnd: FloatRight
  of ClearBoth, ClearNone: FloatNone
  var clearedTo = fstate.exclusionsHead
  for ex in fstate.exclusions:
    if ex.t == target or target == FloatNone:
      let iy = ex.offset.y + ex.size.h
      if iy > y:
        y = iy
      clearedTo = ex.next
  if clearedTo != fstate.exclusionsHead:
    cleared = y > max(fstate.clearOffset, oy)
  fstate.clearOffset = y
  if target == FloatNone:
    fstate.exclusionsHead = clearedTo
  offsety = y - bfcOffsety

proc clearFloats(offsety: var LUnit; fstate: var FlowState; bfcOffsety: LUnit;
    clear: CSSClear) =
  var dummy: bool
  offsety.clearFloats(fstate, bfcOffsety, clear, dummy)

proc findNextFloatOffset(fstate: FlowState; offset: Offset; size: Size;
    space: Space; float: CSSFloat; outw: var LUnit): Offset =
  # Algorithm originally from QEmacs.
  var y = offset.y
  let leftStart = offset.x
  let rightStart = offset.x + max(size.w, space.w.u)
  while true:
    var left = leftStart
    var right = rightStart
    var miny = high(LUnit)
    let cy2 = y + size.h
    for ex in fstate.exclusions:
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
  Offset0

proc findNextFloatOffset(fstate: FlowState; offset: Offset; size: Size;
    space: Space; float: CSSFloat): Offset =
  var dummy: LUnit
  return fstate.findNextFloatOffset(offset, size, space, float, dummy)

proc findNextBlockOffset(fstate: FlowState; offset: Offset; size: Size;
    outw: var LUnit): Offset =
  return fstate.findNextFloatOffset(offset, size, fstate.space, FloatLeft, outw)

proc positionFloat(fstate: var FlowState; child: BlockBox; space: Space;
    outerSize: Size; marginOffset, bfcOffset, offset: Offset) =
  assert space.w.t != scFitContent
  var offset = offset
  offset.y += fstate.marginTodo.sum()
  let clear = child.computed{"clear"}
  if clear != ClearNone:
    offset.y.clearFloats(fstate, fstate.bfcOffset.y, clear)
  var childBfcOffset = bfcOffset + offset - marginOffset
  childBfcOffset.y = max(fstate.clearOffset, childBfcOffset.y)
  let ft = child.computed{"float"}
  assert ft != FloatNone
  offset = fstate.findNextFloatOffset(childBfcOffset, outerSize, space, ft)
  child.state.offset = offset - bfcOffset + marginOffset
  let ex = Exclusion(offset: offset, size: outerSize, t: ft)
  if fstate.exclusionsHead == nil:
    fstate.exclusionsHead = ex
  else:
    fstate.exclusionsTail.next = ex
  fstate.exclusionsTail = ex
  fstate.maxFloatHeight = max(fstate.maxFloatHeight, offset.y + outerSize.h)

proc positionFloats(fstate: var FlowState; yshift = 0'lu) =
  var f = fstate.pendingFloatsHead
  while f != nil:
    var bfcOffset = f.bfcOffset
    bfcOffset.y += yshift
    fstate.positionFloat(f.box, f.space, f.outerSize, f.marginOffset, bfcOffset,
      f.offset)
    if f == fstate.pendingFloatsTail:
      break
    f = f.next
  fstate.pendingFloatsHead = nil
  fstate.pendingFloatsTail = nil

proc flushMargins(fstate: var FlowState; offsety: var LUnit) =
  # Apply uncommitted margins.
  let margin = fstate.marginTodo.sum()
  var yshift = 0'lu
  if fstate.marginResolved:
    offsety += margin
  else:
    fstate.marginOutput = margin
    fstate.bfcOffset.y += margin
    yshift = margin
    fstate.marginResolved = true
  fstate.marginTodo = Span()
  fstate.positionFloats(yshift)

# Prepare the next line's initial width and available width.
# (If space on the left is excluded by floats, set the initial width to
# the end of that space. If space on the right is excluded, set the
# available width to that space.)
type InitLineFlag = enum
  ilfRegular # set the line to inited, and flush floats.
  ilfFloat # set the line to inited, but do not flush floats.
  ilfAbsolute # set size, but allow further calls to override the state.

proc initLine(fstate: var FlowState; flag = ilfRegular) =
  if flag == ilfRegular:
    let poffsety = fstate.offset.y
    fstate.flushMargins(fstate.offset.y)
    # Don't forget to add it to intrinsic height...
    fstate.intr.h += fstate.offset.y - poffsety
  if fstate.lbstate.init != lisUninited:
    return
  # we want to start from padding-left, but normally exclude padding
  # from space. so we must offset available width with padding-left too
  let paddingLeft = fstate.box.input.padding.left
  fstate.lbstate.availableWidth = fstate.space.w.u + paddingLeft
  fstate.lbstate.size.w = paddingLeft
  fstate.lbstate.init = lisNoExclusions
  #TODO what if maxContent/minContent?
  if fstate.exclusionsTail != nil:
    let bfcOffset = fstate.bfcOffset
    let y = fstate.offset.y + bfcOffset.y
    var left = bfcOffset.x + fstate.lbstate.size.w
    var right = bfcOffset.x + fstate.lbstate.availableWidth
    for ex in fstate.exclusions:
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
proc computeShift(lbstate: LineBoxState; ibox: InlineBox): int =
  if lbstate.whitespaceNum == 0:
    return 0
  if lbstate.whitespaceIsLF and lbstate.lastrw == 2 and lbstate.firstrw == 2:
    # skip line feed between double-width characters
    return 0
  if ibox.computed{"white-space"} notin WhiteSpacePreserve:
    if lbstate.atomsTail == nil:
      return 0
    let ibox = lbstate.atomsTail.ibox
    if ibox of InlineTextBox:
      let ibox = InlineTextBox(ibox)
      if ibox.runs.len > 0 and ibox.runs[^1].s[^1] == ' ':
        return 0
  return lbstate.whitespaceNum

proc initWord(fstate: var FlowState; ibox: InlineTextBox): WordState =
  WordState(ibox: ibox, wrapPos: -1)

#TODO start & justify would be nice to have
const TextAlignNone = {
  TextAlignStart, TextAlignLeft, TextAlignChaLeft, TextAlignJustify
}

proc baseline(atom: InlineAtom; lctx: LayoutContext): LUnit =
  let box = atom.box
  if box != nil:
    let baseline = if box.state.baselineSet:
      box.state.baseline
    else:
      box.state.size.h
    return baseline + box.input.margin.top + box.input.borderTop(lctx)
  return atom.size.h

proc vertalign(atom: InlineAtom): CSSVerticalAlign =
  if atom.box != nil:
    return atom.box.computed{"vertical-align"}
  atom.ibox.computed{"vertical-align"}

proc positionAtom(lbstate: LineBoxState; atom: InlineAtom;
    lctx: LayoutContext) =
  case atom.vertalign
  of VerticalAlignBaseline:
    # Atom is placed at (line baseline) - (atom baseline) - len
    atom.offset.y = lbstate.baseline - atom.offset.y
  of VerticalAlignMiddle:
    # Atom is placed at (line baseline) - ((atom height) / 2)
    atom.offset.y = lbstate.baseline - atom.size.h div 2'lu
  of VerticalAlignTop:
    # Atom is placed at the top of the line.
    atom.offset.y = 0'lu
  of VerticalAlignBottom:
    # Atom is placed at the bottom of the line.
    atom.offset.y = lbstate.size.h - atom.size.h
  else:
    # See baseline (with len = 0).
    atom.offset.y = lbstate.baseline - atom.baseline(lctx)

proc getLineWidth(fstate: FlowState): LUnit =
  return case fstate.space.w.t
  of scMinContent, scMaxContent, scMeasure: fstate.maxChildWidth
  of scFitContent: fstate.space.w.u
  of scStretch: max(fstate.maxChildWidth, fstate.space.w.u)

proc getLineXShift(fstate: FlowState): LUnit =
  let width = fstate.getLineWidth()
  return case fstate.computed{"text-align"}
  of TextAlignNone: LUnit(0)
  of TextAlignEnd, TextAlignRight, TextAlignChaRight:
    let width = min(width, fstate.lbstate.availableWidth)
    max(width, fstate.lbstate.size.w) - fstate.lbstate.size.w
  of TextAlignCenter, TextAlignChaCenter:
    let w = min(width, fstate.lbstate.availableWidth)
    max(max(w, fstate.lbstate.size.w) div 2'lu -
      fstate.lbstate.size.w div 2'lu, 0'lu)

# Calculate the position of atoms and background areas inside the
# line.
proc alignLine(fstate: var FlowState) =
  let xshift = fstate.getLineXShift()
  var totalWidth = 0'lu
  var currentAreaOffsetX = 0'lu
  var currentBox: InlineBox = nil
  let areaY = fstate.offset.y + fstate.lbstate.baseline - fstate.cellSize.h
  var minHeight = fstate.cellSize.h
  for (box, i) in fstate.lbstate.paddingTodo:
    box.state.areas[i].offset.x += xshift
    box.state.areas[i].offset.y = areaY
  var atom = fstate.lbstate.atomsHead
  var lastAtom: InlineAtom = nil
  while atom != nil:
    fstate.lbstate.positionAtom(atom, fstate.lctx)
    atom.offset.y += fstate.offset.y
    minHeight = max(minHeight, atom.offset.y - fstate.offset.y + atom.size.h)
    # now position on the inline axis
    atom.offset.x += xshift
    # absolutes track the atom, except if they have a position themselves
    for absolute in atom.absolutes:
      if absolute.computed{"left"}.auto and absolute.computed{"right"}.auto:
        absolute.input.bfcOffset.x = atom.offset.x
        absolute.state.offset.x = atom.offset.x
      if absolute.computed{"top"}.auto and absolute.computed{"bottom"}.auto:
        absolute.input.bfcOffset.y = atom.offset.y
        absolute.state.offset.y = atom.offset.y
    totalWidth += atom.size.w
    let box = atom.ibox
    if currentBox != box:
      if currentBox != nil:
        # flush area
        let w = lastAtom.offset.x + lastAtom.size.w - currentAreaOffsetX
        if w != 0'lu:
          currentBox.state.areas.add(Area(
            offset: offset(x = currentAreaOffsetX, y = areaY),
            size: size(w = w, h = fstate.cellSize.h)
          ))
      # init new box
      currentBox = box
      currentAreaOffsetX = atom.offset.x
      var it = currentBox
      while it != nil:
        if not it.state.startOffsetSet:
          it.state.startOffset = atom.offset
          it.state.startOffsetSet = true
        if not (it.parent of InlineBox):
          break
        it = InlineBox(it.parent)
    if atom.ibox of InlineTextBox:
      atom.run.offset = atom.offset
    elif atom.box != nil:
      # Add the offset to avoid destroying margins (etc.) of the block.
      atom.box.state.offset += atom.offset
    elif atom.ibox of InlineImageBox:
      let ibox = InlineImageBox(atom.ibox)
      ibox.imgstate.offset = atom.offset
    else:
      assert false
    lastAtom = atom
    atom = atom.next
  if currentBox != nil:
    # flush area
    let atom = fstate.lbstate.atomsTail
    let w = atom.offset.x + atom.size.w - currentAreaOffsetX
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

proc getBaseline(atom: InlineAtom; lctx: LayoutContext): LUnit =
  return case atom.vertalign
  of VerticalAlignLength:
    let length = atom.ibox.computed{"-cha-vertical-align-length"}
    atom.baseline(lctx) + length.px(lctx.cellSize.h)
  of VerticalAlignTop:
    0'lu
  of VerticalAlignMiddle:
    atom.size.h div 2'lu
  of VerticalAlignBottom:
    atom.size.h
  else:
    atom.baseline(lctx)

proc putAtom(lbstate: var LineBoxState; atom: InlineAtom; lctx: LayoutContext;
    takeAbsolutes: bool) =
  if takeAbsolutes:
    atom.absolutes = move(lbstate.pendingAbsolutes)
  atom.offset = offset(x = lbstate.size.w, y = atom.getBaseline(lctx))
  lbstate.size.w += atom.size.w
  lbstate.baseline = max(lbstate.baseline, atom.offset.y)
  # In all cases, the line's height must at least equal the atom's height.
  lbstate.size.h = max(lbstate.size.h, atom.size.h)
  if lbstate.atomsTail == nil:
    lbstate.atomsHead = atom
  else:
    lbstate.atomsTail.next = atom
  lbstate.atomsTail = atom

proc putAtom(fstate: var FlowState; atom: InlineAtom; takeAbsolutes = true) =
  fstate.lbstate.putAtom(atom, fstate.lctx, takeAbsolutes)

proc addSpacing(fstate: var FlowState; ibox: InlineTextBox; shift: int;
    hang = false) =
  if ibox.runs.len == 0 or fstate.lbstate.atomsTail == nil or
      fstate.lbstate.atomsTail.run != ibox.runs[^1]:
    let cellHeight = fstate.cellSize.h
    let run = TextRun()
    ibox.runs.add(run)
    fstate.putAtom(InlineAtom(
      ibox: ibox,
      size: size(w = 0'lu, h = cellHeight),
      run: run
    ), takeAbsolutes = false)
  let run = ibox.runs[^1]
  for i in 0 ..< shift:
    run.s &= ' '
  let w = shift.toLUnit() * fstate.cellSize.w
  if not hang:
    # In some cases, whitespace may "hang" at the end of the line. This means
    # it is written, but is not actually counted in the box's width.
    fstate.lbstate.atomsTail.size.w += w
    fstate.lbstate.size.w += w

proc flushWhitespace(fstate: var FlowState; ibox: InlineBox; hang = false) =
  let shift = fstate.lbstate.computeShift(ibox)
  fstate.lbstate.charwidth += fstate.lbstate.whitespaceNum
  fstate.lbstate.whitespaceNum = 0
  let wbox = fstate.lbstate.whitespaceBox
  fstate.lbstate.whitespaceBox = nil
  if shift > 0:
    fstate.initLine()
    fstate.addSpacing(wbox, shift, hang)

proc initLineBoxState(fstate: var FlowState): LineBoxState =
  let cellHeight = fstate.cellSize.h
  # move over pendingAbsolutes
  # (I guess this means it doesn't quite belong in lbstate, but FlowState is
  # also way too overloaded so it still seems preferable)
  var pendingAbsolutes = move(fstate.lbstate.pendingAbsolutes)
  result = LineBoxState(
    intrh: cellHeight,
    baseline: cellHeight,
    size: size(w = 0'lu, h = cellHeight),
    pendingAbsolutes: move(pendingAbsolutes)
  )

proc finishLine(fstate: var FlowState; ibox: InlineBox; wrap: bool;
    force = false; clear = ClearNone) =
  if fstate.lbstate.atomsHead != nil or force or
      fstate.lbstate.whitespaceNum != 0 and ibox != nil and
      ibox.computed{"white-space"} in {WhitespacePre, WhitespacePreWrap}:
    fstate.initLine()
    let whitespace = ibox.computed{"white-space"}
    if whitespace == WhitespacePre:
      fstate.flushWhitespace(ibox)
      # see below on padding
      fstate.intr.w = max(fstate.intr.w, fstate.lbstate.size.w -
        fstate.box.input.padding.left)
    elif whitespace == WhitespacePreWrap:
      fstate.flushWhitespace(ibox, hang = true)
    else:
      # Note: per standard, we really should always flush with hang except
      # on pre, but a) w3m doesn't, b) I find hang annoying, so we don't.
      # (I'm leaving the hang code in so it's easy to add if I ever change
      # my mind (or add a graphical mode.))
      fstate.lbstate.whitespaceNum = 0
    # align atoms + calculate width for fit-content + place
    fstate.alignLine()
    var f = fstate.lbstate.pendingFloatsHead
    while f != nil:
      if whitespace != WhitespacePre and f.newLine:
        f.offset.y += fstate.lbstate.size.h
      fstate.positionFloat(f.box, f.space, f.outerSize, f.marginOffset,
        fstate.bfcOffset, f.offset)
      f = f.next
    # add line to fstate
    let y = fstate.offset.y
    if clear != ClearNone:
      fstate.lbstate.size.h.clearFloats(fstate, fstate.bfcOffset.y + y, clear)
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
      lineWidth - fstate.box.input.padding.left)
  else:
    # Two cases exist:
    # a) The float cannot be positioned, because `fstate.box' has not
    #    resolved its y offset yet. (e.g. if float comes before the
    #    first child, we do not know yet if said child will move our y
    #    offset with a margin-top value larger than ours.)
    #    In this case we put it in pendingFloats, and defer positioning
    #    until our y offset is resolved.
    # b) `box' has resolved its y offset, so the float can already be
    #    positioned.
    if fstate.marginResolved:
      # y offset resolved
      var f = fstate.lbstate.pendingFloatsHead
      while f != nil:
        fstate.positionFloat(f.box, f.space, f.outerSize, f.marginOffset,
          fstate.bfcOffset, f.offset)
        f = f.next
    elif fstate.lbstate.pendingFloatsHead != nil:
      if fstate.pendingFloatsHead != nil:
        fstate.pendingFloatsTail.next = fstate.lbstate.pendingFloatsHead
      else:
        fstate.pendingFloatsHead = fstate.lbstate.pendingFloatsHead
      fstate.pendingFloatsTail = fstate.lbstate.pendingFloatsTail
  # Reinit in both cases.
  fstate.totalFloatWidth = max(fstate.totalFloatWidth,
    fstate.lbstate.totalFloatWidth)
  fstate.lbstate = fstate.initLineBoxState()

proc shouldWrap(fstate: FlowState; w: LUnit; ibox: InlineBox): bool =
  if ibox != nil and ibox.computed.nowrap:
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

# Wrap assuming the next atom is "width" wide and associated with "ibox".
# Returns true if wrapped (i.e. on newline).
proc prepareSpace(fstate: var FlowState; ibox: InlineBox; width: LUnit): bool =
  fstate.initLine()
  var wrapped = false
  var shift = fstate.lbstate.computeShift(ibox)
  fstate.lbstate.charwidth += fstate.lbstate.whitespaceNum
  fstate.lbstate.whitespaceNum = 0
  let wbox = fstate.lbstate.whitespaceBox
  fstate.lbstate.whitespaceBox = nil
  # Line wrapping
  if fstate.shouldWrap(width + shift.toLUnit() * fstate.cellSize.w, ibox):
    fstate.finishLine(ibox, wrap = true)
    fstate.initLine()
    wrapped = true
    # Recompute on newline
    shift = fstate.lbstate.computeShift(ibox)
    # For floats: flush lines until we can place the atom.
    #TODO this is inefficient
    while fstate.shouldWrap2(width + shift.toLUnit() * fstate.cellSize.w):
      fstate.finishLine(ibox, wrap = false, force = true)
      fstate.initLine()
      # Recompute on newline
      shift = fstate.lbstate.computeShift(ibox)
  if shift > 0:
    fstate.addSpacing(wbox, shift)
  wrapped

proc flushIntrSize(fstate: var FlowState; word: var WordState) =
  fstate.intr.w = max(fstate.intr.w, word.intrWidth)
  word.intrWidth = 0'lu

# Returns true if wrapped.
proc addWord(fstate: var FlowState; word: var WordState): bool =
  if word.s == "" or word.width == 0'lu:
    return false
  word.s.mnormalize() #TODO this may break on EOL.
  if word.s == "":
    return false
  fstate.flushIntrSize(word)
  let ibox = word.ibox
  let wrapped = fstate.prepareSpace(ibox, word.width)
  let tail = fstate.lbstate.atomsTail
  if tail != nil and ibox.runs.len > 0 and tail.run == ibox.runs[^1]:
    tail.run.s &= word.s
    tail.size.w += word.width
    fstate.lbstate.size.w += word.width
  else:
    let size = size(w = word.width, h = fstate.cellSize.h)
    let run = TextRun(s: move(word.s))
    ibox.runs.add(run)
    fstate.putAtom(InlineAtom(ibox: ibox, run: run, size: size))
  word = fstate.initWord(ibox)
  return wrapped

proc addWordEOL(fstate: var FlowState; word: var WordState): bool =
  if word.s == "":
    return false
  let wrapPos = word.wrapPos
  if wrapPos != -1:
    var leftstr = word.s.substr(wrapPos)
    word.s.setLen(wrapPos)
    if word.hasSoftHyphen:
      const shy = "\u00AD" # soft hyphen
      word.s &= shy
      word.hasSoftHyphen = false
    let wrapped = fstate.addWord(word)
    word.width = leftstr.width().toLUnit() * fstate.cellSize.w
    word.s = move(leftstr)
    return wrapped
  return fstate.addWord(word)

proc checkWrap(fstate: var FlowState; word: var WordState; u: uint32;
    uw: int) =
  let ibox = word.ibox
  if ibox.computed.nowrap:
    return
  fstate.initLine()
  let shiftw = fstate.lbstate.computeShift(ibox).toLUnit() * fstate.cellSize.w
  fstate.lbstate.prevrw = uw
  if word.s.len == 0:
    fstate.lbstate.firstrw = uw
  let luw = uw.toLUnit()
  case ibox.computed{"word-break"}
  of WordBreakNormal:
    if uw == 2:
      # remove wrap opportunity, so we wrap properly on the last CJK char
      # (instead of any dash inside CJK sentences)
      word.wrapPos = -1
      fstate.flushIntrSize(word)
    if uw == 2 or word.wrapPos != -1:
      # break on cjk and wrap opportunities
      let plusWidth = word.width + shiftw + luw * fstate.cellSize.w
      if fstate.shouldWrap(plusWidth, nil):
        if not fstate.addWordEOL(word): # no line wrapping occurred in addWord
          fstate.finishLine(ibox, wrap = true)
  of WordBreakBreakAll:
    word.wrapPos = -1
    fstate.flushIntrSize(word)
    let plusWidth = word.width + shiftw + luw * fstate.cellSize.w
    if fstate.shouldWrap(plusWidth, nil):
      if not fstate.addWordEOL(word): # no line wrapping occurred in addWord
        fstate.finishLine(ibox, wrap = true)
  of WordBreakKeepAll:
    let plusWidth = word.width + shiftw + luw * fstate.cellSize.w
    if fstate.shouldWrap(plusWidth, nil):
      fstate.finishLine(ibox, wrap = true)

proc processWhitespace(fstate: var FlowState; word: var WordState; c: char) =
  let ibox = word.ibox
  discard fstate.addWord(word)
  case ibox.computed{"white-space"}
  of WhitespaceNormal, WhitespaceNowrap:
    if fstate.lbstate.whitespaceNum < 1 and fstate.lbstate.atomsHead != nil:
      fstate.lbstate.whitespaceNum = 1
      fstate.lbstate.whitespaceBox = ibox
      fstate.lbstate.whitespaceIsLF = c == '\n'
    if c != '\n':
      fstate.lbstate.whitespaceIsLF = false
  of WhitespacePreLine:
    if c == '\n':
      fstate.finishLine(ibox, wrap = false, force = true)
    elif fstate.lbstate.whitespaceNum < 1 and fstate.lbstate.atomsHead != nil:
      fstate.lbstate.whitespaceIsLF = false
      fstate.lbstate.whitespaceNum = 1
      fstate.lbstate.whitespaceBox = ibox
  of WhitespacePre, WhitespacePreWrap:
    fstate.lbstate.whitespaceIsLF = false
    if c == '\n':
      fstate.finishLine(ibox, wrap = false, force = true)
    elif c == '\t':
      let realWidth = fstate.lbstate.charwidth + fstate.lbstate.whitespaceNum
      # We must flush first, because addWord would otherwise try to wrap the
      # line. (I think.)
      fstate.flushWhitespace(ibox)
      let w = ((realWidth + 8) and not 7) - realWidth
      word.s.addUTF8(tabPUAPoint(w))
      word.width += w.toLUnit() * fstate.cellSize.w
      fstate.lbstate.charwidth += w
      # Ditto here - we don't want the tab stop to get merged into the next
      # word.
      discard fstate.addWord(word)
    else:
      inc fstate.lbstate.whitespaceNum
      fstate.lbstate.whitespaceBox = ibox
  # set the "last word's last rune width" to the previous rune width
  fstate.lbstate.lastrw = fstate.lbstate.prevrw

proc addWrapPos(fstate: var FlowState; word: var WordState) =
  # largest gap between wrapping opportunities is the intrinsic minimum
  # width
  fstate.flushIntrSize(word)
  word.wrapPos = word.s.len

proc layoutTextLoop(fstate: var FlowState; ibox: InlineTextBox; s: string) =
  var word = fstate.initWord(ibox)
  let luctx = fstate.lctx.luctx
  var i = 0
  while i < s.len:
    let pi = i
    var u = s.nextUTF8(i)
    if u < 0x80:
      let c = char(u)
      if c in AsciiWhitespace:
        fstate.processWhitespace(word, c)
      else:
        let w = u.width()
        fstate.checkWrap(word, u, w)
        word.s &= c
        let cw = w.toLUnit() * fstate.cellSize.w
        word.width += cw
        word.intrWidth += cw
        fstate.lbstate.charwidth += w
        if c == '-': # ascii dash
          fstate.addWrapPos(word)
          word.hasSoftHyphen = false # override soft hyphen
    elif luctx.isEnclosingMark(u) or luctx.isNonspacingMark(u) or
        luctx.isFormat(u):
      continue
    elif u == 0xAD: # soft hyphen
      fstate.addWrapPos(word)
      word.hasSoftHyphen = true
      continue
    else:
      if u in TabPUARange: # filter out chars placed in our PUA range
        u = 0xFFFD
      let w = u.width()
      fstate.checkWrap(word, u, w)
      for j in pi ..< i:
        word.s &= s[j]
      let cw = w.toLUnit() * fstate.cellSize.w
      word.width += cw
      word.intrWidth += cw
      fstate.lbstate.charwidth += w
  discard fstate.addWord(word)
  let shiftw = fstate.lbstate.computeShift(ibox).toLUnit() * fstate.cellSize.w
  fstate.lbstate.widthAfterWhitespace = fstate.lbstate.size.w + shiftw

proc layoutText(fstate: var FlowState; ibox: InlineTextBox; s: string) =
  let transform = ibox.computed{"text-transform"}
  if transform == TextTransformNone:
    fstate.layoutTextLoop(ibox, s)
  else:
    let s = case transform
    of TextTransformCapitalize: s.capitalizeLU()
    of TextTransformUppercase: s.toUpperLU()
    of TextTransformLowercase: s.toLowerLU()
    of TextTransformFullWidth: s.fullwidth()
    of TextTransformFullSizeKana: s.fullsize()
    of TextTransformChaHalfWidth: s.halfwidth()
    else: ""
    fstate.layoutTextLoop(ibox, s)

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
    var offset = child.input.bfcOffset
    size.w -= offset.x
    let positioned = lctx.resolvePositioned(size, child.computed)
    var input = lctx.resolveAbsoluteSizes(size, positioned, child.computed)
    input.bfcOffset = offset
    offset.x += input.margin.left
    lctx.layout(child, offset, input)
    if not child.computed{"left"}.auto:
      child.state.offset.x = positioned.left + input.margin.left +
        input.borderLeft(lctx)
    elif not child.computed{"right"}.auto:
      child.state.offset.x = size.w - positioned.right - child.state.size.w -
        input.margin.right + input.borderRight(lctx)
    # margin.left is added in layout
    if not child.computed{"top"}.auto:
      child.state.offset.y = positioned.top + input.margin.top +
        input.borderTop(lctx)
    elif not child.computed{"bottom"}.auto:
      child.state.offset.y = size.h - positioned.bottom - child.state.size.h -
        input.margin.bottom + input.borderBottom(lctx)
    else:
      child.state.offset.y += input.margin.top
    it = it.next

proc positionRelative(lctx: LayoutContext; space: Space; box: BlockBox) =
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
  let input = lctx.resolveFloatSizes(fstate.space, child.computed)
  lctx.layout(child, fstate.offset + input.margin.topLeft, input)
  let outerSize = child.outerSize(input, lctx)
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
        (fstate.lbstate.pendingFloatsTail == nil or
        not fstate.lbstate.pendingFloatsTail.newLine):
      # We can still cram floats into the line.
      if float == FloatLeft:
        fstate.lbstate.size.w += outerSize.w
        var atom = fstate.lbstate.atomsHead
        while atom != nil:
          atom.offset.x += outerSize.w
          atom = atom.next
      else:
        fstate.lbstate.availableWidth -= outerSize.w
      fstate.lbstate.floatsSeen.incl(float)
      newLine = false
    let f = PendingFloat(
      space: fstate.space,
      offset: child.state.offset,
      bfcOffset: fstate.bfcOffset,
      box: child,
      marginOffset: input.margin.startOffset() + input.borderTopLeft(lctx),
      outerSize: outerSize,
      newLine: newLine
    )
    if fstate.lbstate.pendingFloatsHead != nil:
      fstate.lbstate.pendingFloatsTail.next = f
    else:
      fstate.lbstate.pendingFloatsHead = f
    fstate.lbstate.pendingFloatsTail = f
  fstate.intr.w = max(fstate.intr.w, child.state.intr.w)

# Outer layout for block-level children.
proc layoutBlockChild(fstate: var FlowState; child: BlockBox) =
  fstate.finishLine(fstate.lastTextBox, wrap = false)
  let lctx = fstate.lctx
  var input = lctx.resolveBlockSizes(fstate.space, child.computed)
  var space = fstate.space # may be modified if child is a BFC
  var offset = fstate.offset
  offset.x += input.margin.left
  let clear = child.computed{"clear"}
  if clear != ClearNone:
    let target = case clear
    of ClearLeft, ClearInlineStart: FloatLeft
    of ClearRight, ClearInlineEnd: FloatRight
    of ClearBoth, ClearNone: FloatNone
    var f = fstate.pendingFloatsHead
    while f != nil:
      if target == FloatNone or f.box.computed{"float"} == target:
        fstate.flushMargins(offset.y)
        break
      f = f.next
    var cleared = false
    offset.y.clearFloats(fstate, fstate.bfcOffset.y, clear, cleared)
    if cleared:
      # subtract our own margin so that the top edge of this box touches
      # the bottom edge of the last cleared float
      # (margin must be collapsed with subsequent boxes as usual, so we
      # can't just skip addMargin)
      offset.y -= input.margin.top
  const DisplayWithBFC = {
    DisplayFlowRoot, DisplayTable, DisplayFlex, DisplayGrid
  }
  fstate.marginTodo.addMargin(input.margin.top)
  if child.computed{"display"} in DisplayWithBFC or
      child.computed{"overflow-x"} notin {OverflowVisible, OverflowClip}:
    # This box establishes a new BFC.
    input.marginResolved = fstate.marginResolved
    fstate.flushMargins(offset.y)
    lctx.layout(child, offset, input)
    if fstate.exclusionsTail != nil:
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
      #TODO other browsers just try again until they find enough available
      # space; we should do that too once we have proper layout caching.
      #
      # Note that this does not apply to absolutely positioned elements,
      # as those ignore floats.
      let pbfcOffset = fstate.bfcOffset
      let bfcOffset = offset(
        x = pbfcOffset.x + child.state.offset.x,
        y = max(pbfcOffset.y + child.state.offset.y, fstate.clearOffset)
      )
      let minSize = size(w = child.state.intr.w, h = lctx.cellSize.h)
      var outw: LUnit
      let offset = fstate.findNextBlockOffset(bfcOffset, minSize, outw)
      let roffset = offset - pbfcOffset
      # skip relayout if we can
      if outw != fstate.space.w.u or roffset != child.state.offset:
        space = initSpace(w = stretch(outw), h = fstate.space.h)
        input = lctx.resolveBlockSizes(space, child.computed)
        lctx.layout(child, roffset, input)
  else:
    offset += input.borderTopLeft(lctx)
    input.bfcOffset = fstate.bfcOffset + offset
    input.marginResolved = fstate.marginResolved
    input.marginTodo = fstate.marginTodo
    input.pendingFloatsHead = fstate.pendingFloatsHead
    input.pendingFloatsTail = fstate.pendingFloatsTail
    input.exclusionsHead = fstate.exclusionsHead
    input.exclusionsTail = fstate.exclusionsTail
    input.clearOffset = fstate.clearOffset
    fstate.lctx.layout(child, offset, input)
    fstate.pendingFloatsHead = child.state.pendingFloatsHead
    fstate.pendingFloatsTail = child.state.pendingFloatsTail
    fstate.marginTodo = child.state.marginTodo
    fstate.maxFloatHeight = max(fstate.maxFloatHeight,
      child.state.maxFloatHeight)
    fstate.clearOffset = child.state.clearOffset
    fstate.exclusionsHead = child.state.exclusionsHead
    fstate.exclusionsTail = child.state.exclusionsTail
    if not fstate.marginResolved and child.state.marginResolved:
      # We are "inheriting" the margin flushed by a descendant, so we must
      # move our BFC offset by said margin (as flushMargins only did it for
      # the descendant.)
      let marginOutput = child.state.marginOutput
      fstate.marginOutput = marginOutput
      fstate.bfcOffset.y += marginOutput
      fstate.marginResolved = true
  fstate.marginTodo.addMargin(input.margin.bottom)
  let outerSize = size(
    w = child.outerSize(dtHorizontal, input, lctx),
    # delta y is difference between old and new offsets (margin-top),
    # plus height, plus border size.
    h = child.state.offset.y - fstate.offset.y + child.state.size.h +
      input.borderBottom(lctx)
  )
  if child.state.baselineSet:
    if not fstate.box.state.baselineSet:
      fstate.box.state.firstBaseline = child.state.offset.y +
        child.state.firstBaseline
      fstate.box.state.baselineSet = true
    fstate.box.state.baseline = child.state.offset.y + child.state.baseline
  if fstate.space.w.t == scStretch:
    if fstate.textAlign == TextAlignChaCenter:
      child.state.offset.x += max(space.w.u div 2'lu -
        child.state.size.w div 2'lu, 0'lu)
    elif fstate.textAlign == TextAlignChaRight:
      child.state.offset.x += max(space.w.u - child.state.size.w -
        input.margin.right, 0'lu)
  if child.computed{"position"} == PositionRelative:
    fstate.lctx.positionRelative(fstate.space, child)
  fstate.maxChildWidth = max(fstate.maxChildWidth, outerSize.w)
  fstate.offset.y += outerSize.h
  fstate.intr.h += outerSize.h - child.state.size.h + child.state.intr.h
  fstate.lbstate.whitespaceNum = 0
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
    if fstate.marginResolved:
      offset.y += fstate.marginTodo.sum()
    if child.computed{"display"} in DisplayOuterInline:
      # inline-block or similar. put it on the current line.
      # our position will stick to the next atom's end, which may be moved
      # at alignLine.
      fstate.lbstate.pendingAbsolutes.add(child)
      # ...however, that is not guaraneteed to happen before we are actually
      # positioned, so we also have to set a sensible offset here.
      offset.x = fstate.lbstate.size.w + fstate.getLineXShift()
    elif fstate.lbstate.atomsHead != nil:
      # flush if there is already something on the line *and* our outer
      # display is block.
      offset.y += fstate.cellSize.h
    # This really has nothing to do with bfcOffset, but I don't want to
    # waste more bytes in LayoutInput.
    child.input.bfcOffset = offset
  elif child.computed{"float"} != FloatNone:
    fstate.layoutFloat(child)
  else:
    fstate.layoutBlockChild(child)

proc layoutInlineBlock(fstate: var FlowState; ibox: InlineBox; box: BlockBox) =
  let lctx = fstate.lctx
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
    var input = lctx.resolveFloatSizes(fstate.space, box.computed)
    fstate.initLine(flag = ilfAbsolute)
    lctx.layout(box, input.margin.topLeft, input)
    box.state.offset.x = fstate.lbstate.size.w - box.state.size.w
  else:
    # A real inline block.
    var input = lctx.resolveFloatSizes(fstate.space, box.computed)
    lctx.layout(box, input.margin.topLeft, input)
    # Apply the block box's properties to the atom itself.
    let atom = InlineAtom(
      ibox: ibox,
      box: box,
      size: box.outerSize(input, lctx)
    )
    discard fstate.prepareSpace(ibox, atom.size.w)
    fstate.putAtom(atom)
    fstate.intr.w = max(fstate.intr.w, box.state.intr.w)
    fstate.lbstate.intrh = max(fstate.lbstate.intrh, atom.size.h)
    fstate.lbstate.charwidth = 0
    fstate.lbstate.whitespaceNum = 0

proc layoutImage(fstate: var FlowState; ibox: InlineImageBox; padding: LUnit) =
  ibox.imgstate = InlineImageState(
    size: size(w = ibox.bmp.width.toLUnit(), h = ibox.bmp.height.toLUnit())
  )
  #TODO this is hopelessly broken.
  # The core problem is that we generate an inner and an outer box for
  # images, and achieving an acceptable image sizing algorithm with this
  # setup is practically impossible.
  # Accordingly, a correct solution would either handle block-level
  # images separately, or at least resolve the outer box's input with
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
      if osize.w > 0'lu:
        ibox.imgstate.size.h = osize.h div osize.w * ibox.imgstate.size.w
    else:
      if osize.h > 0'lu:
        ibox.imgstate.size.w = osize.w div osize.h * ibox.imgstate.size.h
  elif not hasHeight and osize.w != 0'lu:
    ibox.imgstate.size.h = osize.h div osize.w * ibox.imgstate.size.w
  elif not hasWidth and osize.h != 0'lu:
    ibox.imgstate.size.w = osize.w div osize.h * ibox.imgstate.size.h
  if ibox.imgstate.size.w > 0'lu and ibox.imgstate.size.h > 0'lu:
    let atom = InlineAtom(ibox: ibox, size: ibox.imgstate.size)
    discard fstate.prepareSpace(ibox, atom.size.w)
    fstate.putAtom(atom)
  fstate.lbstate.charwidth = 0
  if ibox.imgstate.size.h > 0'lu:
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
  ibox.keepLayout = true
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
    fstate.layoutText(ibox, ibox.text.s)
  elif ibox of InlineNewLineBox:
    let ibox = InlineNewLineBox(ibox)
    fstate.finishLine(ibox, wrap = false, force = true, ibox.computed{"clear"})
  elif ibox of InlineImageBox:
    let ibox = InlineImageBox(ibox)
    fstate.layoutImage(ibox, padding.sum())
  else:
    ibox.state.startOffset = offset(
      x = fstate.lbstate.widthAfterWhitespace,
      y = fstate.offset.y
    )
    let w = ibox.computed{"margin-left"}.px(fstate.space.w)
    if w != 0'lu:
      fstate.initLine()
      fstate.lbstate.size.w += w
      fstate.lbstate.widthAfterWhitespace += w
      ibox.state.startOffset.x += w
    if padding.start != 0'lu:
      ibox.state.areas.add(Area(
        offset: offset(x = fstate.lbstate.widthAfterWhitespace, y = 0'lu),
        size: size(w = padding.start, h = fstate.cellSize.h)
      ))
      fstate.lbstate.paddingTodo.add((ibox, 0))
      fstate.initLine()
      fstate.lbstate.size.w += padding.start
    for child in ibox.children:
      if child of InlineBox:
        fstate.layoutInline(InlineBox(child))
      else:
        let child = BlockBox(child)
        if child.computed{"display"} in DisplayInlineBlockLike:
          fstate.layoutInlineBlock(ibox, child)
        else:
          fstate.layoutOuterBlock(child)
    if padding.send != 0'lu:
      ibox.state.areas.add(Area(
        offset: offset(x = fstate.lbstate.size.w, y = 0'lu),
        size: size(w = padding.send, h = fstate.cellSize.h)
      ))
      fstate.lbstate.paddingTodo.add((ibox, ibox.state.areas.high))
      fstate.initLine()
      fstate.lbstate.size.w += padding.send
    let marginRight = ibox.computed{"margin-right"}.px(fstate.space.w)
    if marginRight != 0'lu:
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
        w = fstate.maxChildWidth,
        h = fstate.offset.y + fstate.cellSize.h - ibox.state.startOffset.y
      ))
  fstate.textAlign = oldTextAlign

proc layoutFlow0(fstate: var FlowState) =
  fstate.lbstate = fstate.initLineBoxState()
  let box = fstate.box
  for child in box.children:
    if child of InlineBox:
      fstate.layoutInline(InlineBox(child))
    else:
      fstate.layoutOuterBlock(BlockBox(child))
  fstate.finishLine(fstate.lastTextBox, wrap = false)
  fstate.totalFloatWidth = max(fstate.totalFloatWidth,
    fstate.lbstate.totalFloatWidth)

proc initFlowState(lctx: LayoutContext; box: BlockBox; input: LayoutInput;
    root: bool): FlowState =
  result = FlowState(
    lctx: lctx,
    box: box,
    offset: input.padding.topLeft,
    bfcOffset: input.bfcOffset,
    space: input.space,
    exclusionsHead: input.exclusionsHead,
    exclusionsTail: input.exclusionsTail,
    textAlign: box.computed{"text-align"},
    marginResolved: root,
    clearOffset: input.clearOffset,
    marginTodo: input.marginTodo,
    pendingFloatsHead: input.pendingFloatsHead,
    pendingFloatsTail: input.pendingFloatsTail
  )
  if box.computed{"position"} in PositionAbsoluteFixed:
    # absolute abuses bfcOffset as its own offset, so unset it
    result.bfcOffset = Offset0

# Second layout.  Reset the starting offset, and stretch the box to the
# max child width.
proc initReLayout(fstate: var FlowState; box: BlockBox; input: LayoutInput;
    root: bool) =
  if fstate.exclusionsTail != nil:
    fstate.exclusionsTail.next = nil
  var bounds = input.bounds
  bounds.a[dtHorizontal].start = max(bounds.a[dtHorizontal].start,
    fstate.intr.w)
  box.applySize(bounds, fstate.maxChildWidth + fstate.totalFloatWidth,
    input.space, dtHorizontal)
  let lctx = fstate.lctx
  fstate = lctx.initFlowState(box, input, root)
  fstate.space.w = stretch(box.state.size.w)

proc layoutFlow(lctx: LayoutContext; box: BlockBox; input: LayoutInput;
    root: bool) =
  var fstate = lctx.initFlowState(box, input, root)
  if box.computed{"position"} notin PositionAbsoluteFixed and
      (input.padding.top != 0'lu or input.borderTop(lctx) != 0'lu or
      input.space.h.isDefinite() and input.space.h.u != 0'lu):
    fstate.flushMargins(box.state.yshift)
  let spacew = fstate.space.w
  let indefinite = spacew.t in {scFitContent, scMaxContent}
  if indefinite:
    fstate.space.w = measure()
  fstate.layoutFlow0()
  if indefinite:
    fstate.space.w = spacew
    # shrink-to-fit size; layout again.
    let oldIntr = fstate.intr
    fstate.initReLayout(box, input, root)
    fstate.layoutFlow0()
    # Restore old intrinsic input, as the new ones are a function of the
    # current input and therefore wrong.
    fstate.intr = oldIntr
  elif fstate.space.w.t == scMeasure:
    fstate.maxChildWidth += fstate.totalFloatWidth
  # Apply width, and height. For height, temporarily remove padding we have
  # applied before so that percentage resolution works correctly.
  var childSize = size(
    w = fstate.maxChildWidth,
    h = fstate.offset.y - input.padding.top
  )
  if input.padding.bottom != 0'lu or input.borderBottom(lctx) != 0'lu:
    let oldHeight = childSize.h
    fstate.flushMargins(childSize.h)
    fstate.intr.h += childSize.h - oldHeight
  box.applySize(input, childSize, fstate.space)
  let paddingSum = input.padding.sum()
  # Intrinsic minimum size includes the sum of our padding.  (However,
  # this padding must also be clamped to the same bounds.)
  box.applyIntr(input, fstate.intr + paddingSum)
  # Add padding after applying space, since space applies to the content
  # box.
  box.state.size += paddingSum
  if not root and fstate.marginResolved and box.input.marginResolved:
    box.state.yshift += fstate.marginOutput
    fstate.marginOutput = 0'lu
  if fstate.marginResolved or input.marginResolved:
    # Our offset has already been resolved, ergo any margins in
    # marginTodo will be passed onto the next box.
    fstate.positionFloats()
    fstate.marginResolved = true
  box.state.maxFloatHeight = fstate.maxFloatHeight
  box.state.marginOutput = fstate.marginOutput
  box.state.marginResolved = fstate.marginResolved
  box.state.clearOffset = fstate.clearOffset
  box.state.marginTodo = fstate.marginTodo
  box.state.pendingFloatsHead = fstate.pendingFloatsHead
  box.state.pendingFloatsTail = fstate.pendingFloatsTail
  box.state.exclusionsHead = fstate.exclusionsHead
  box.state.exclusionsTail = fstate.exclusionsTail
  box.state.offset.y += box.state.yshift

proc layoutFlowDescendant(lctx: LayoutContext; box: BlockBox; offset: Offset;
    input: LayoutInput) =
  if box.keepLayout and box.input == input:
    box.state.offset = offset
    box.state.offset.y += box.state.yshift
    return
  box.input = input
  box.keepLayout = true
  box.resetState()
  box.state.offset = offset
  lctx.layoutFlow(box, input, root = false)

proc layoutFlowRootPre(lctx: LayoutContext; box: BlockBox; offset: Offset;
    input: LayoutInput): bool =
  let offset = offset + input.borderTopLeft(lctx)
  if box.keepLayout and box.input == input:
    box.state.offset = offset
    return false
  box.input = input
  box.keepLayout = true
  box.resetState()
  box.state.offset = offset
  true

proc layoutFlowRoot(lctx: LayoutContext; box: BlockBox; offset: Offset;
    input: LayoutInput) =
  if not lctx.layoutFlowRootPre(box, offset, input):
    return
  lctx.layoutFlow(box, input, root = true)
  assert box.state.pendingFloatsTail == nil
  let marginBottom = box.state.marginTodo.sum()
  # If the highest float edge is higher than the box itself, set that as
  # the box height.
  let maxFloatHeight = box.state.maxFloatHeight
  box.state.size.h = max(box.state.size.h + marginBottom, maxFloatHeight)
  box.state.intr.h = max(box.state.intr.h + marginBottom, maxFloatHeight)

# Table layout.  This imitates what mainstream browsers do:
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
# Percentage widths (width=n%):
# 1. for each column, assign the largest percentage width among its cells
#    as its weight (divided as appropriate by colspan).  at each step, keep
#    track of the remaining weight (1 - assigned), and clamp the column's
#    weight down if it exceeds this.
# 2. count sum of min width of all columns with weight=0, this is "unassigned"
# 3. if unassigned is 0, and the total assigned weight is < 1, then scale all
#    assigned weight such that the sum is 1 (i.e. divide each column's weight
#    by the total weight.)
# 4. for each assigned column, compute the total width implied by its weight:
#    (min width) / weight, as well as (unassigned) / (1 - weight).
# 5. set the table's max width to the largest value computed in the previous
#    step.
# 6. in the second pass, first fix the width of columns with an author weight,
#    *then* columns with an author width.
#
#TODO:
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
    widthSpecified: bool
    weight: float32
    reflow: int # last row index that need not be reflowed
    grown: int # number of remaining rows
    growing: CellWrapper

  TableContext = object
    lctx: LayoutContext
    rows: seq[RowContext]
    cols: seq[ColumnContext]
    hasAuthorWeight: bool
    maxwidth: LUnit
    blockSpacing: LUnit
    inlineSpacing: LUnit
    borderWidth: LUnit
    space: Space # space we got from parent

proc layoutTableCell(lctx: LayoutContext; box: BlockBox; space: Space;
    border: CSSBorder; merge: CSSBorderMerge) =
  box.input = LayoutInput(
    padding: lctx.resolvePadding(space.w, box.computed),
    space: initSpace(w = space.w, h = maxContent()),
    bounds: DefaultBounds,
    border: border
  )
  box.keepLayout = true
  box.resetState()
  box.state.merge = merge
  if box.input.space.w.isDefinite():
    box.input.space.w.u -= box.input.padding[dtHorizontal].sum()
  lctx.layout(box, Offset0, box.input)
  assert box.state.pendingFloatsTail == nil
  # If the highest float edge is higher than the box itself, set that as
  # the box height.
  box.state.size.h = max(box.state.size.h, box.state.maxFloatHeight)
  if space.h.t == scStretch:
    box.state.size.h = max(box.state.size.h, space.h.u -
      box.input.padding[dtVertical].sum())
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
      width += tctx.inlineSpacing * 2'lu
    n += colspan
    inc growi

proc resolveBorder(tctx: var TableContext; computed: CSSValues;
    firstRow, lastCell, lastRow: bool; inlineBorder, blockBorder: var Span):
    CSSBorder =
  let lctx = tctx.lctx
  var dummyMargin = RelativeRect.default # table cells have no margin
  var border = computed.resolveBorder(dummyMargin)
  if border.left notin BorderStyleNoneHidden:
    inlineBorder.start = max(lctx.cellSize.w div 2'lu, inlineBorder.start)
  if border.right notin BorderStyleNoneHidden:
    inlineBorder.send = max(lctx.cellSize.w div 2'lu, inlineBorder.send)
  if border.top notin BorderStyleNoneHidden:
    let d = if firstRow: 1'lu else: 2'lu
    blockBorder.start = max(blockBorder.start, lctx.cellSize.h div d)
  if border.bottom notin BorderStyleNoneHidden:
    let d = if lastRow: 1'lu else: 2'lu
    blockBorder.send = max(blockBorder.send, lctx.cellSize.h div d)
  if not lastCell:
    border[dtHorizontal].send = BorderStyleNone
  if not lastRow:
    border[dtVertical].send = BorderStyleNone
  border

proc preLayoutTableColspan(tctx: var TableContext; cellw: CellWrapper;
    space: Space; rowi, n, nextn: int; weight: float32): LUnit =
  var width = 0'lu
  let colspan = cellw.colspan
  let lcolspan = colspan.toLUnit()
  let minw = cellw.box.state.intr.w div lcolspan
  let weight = weight / float32(colspan)
  let w = cellw.box.state.size.w div lcolspan
  if tctx.cols.len < nextn:
    tctx.cols.setLen(nextn)
  for col in tctx.cols.toOpenArray(n, nextn - 1).mitems:
    if col.weight < weight:
      tctx.hasAuthorWeight = true
      col.weight = weight
      col.widthSpecified = false
    # Figure out this cell's effect on the column's width.
    # Four cases exist:
    # 1. colwidth already fixed, cell width is fixed: take maximum
    # 2. colwidth already fixed, cell width is auto: take colwidth
    # 3. colwidth is not fixed, cell width is fixed: take cell width
    # 4. neither of colwidth or cell width are fixed: take maximum
    if col.widthSpecified:
      if space.w.isDefinite() and col.weight == 0:
        # A specified column already exists; we take the larger width.
        if w > col.width:
          col.width = w
          col.reflow = rowi
      if col.width != w:
        cellw.reflow = true
    elif space.w.isDefinite() and col.weight == 0:
      # This is the first specified column. Replace colwidth with whatever
      # we have.
      col.reflow = rowi
      col.widthSpecified = true
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

proc cellWidthPx(l: CSSLength): SizeConstraint =
  if l.auto or l.perc != 0:
    return measure()
  return stretch(l.npx.toLUnit())

proc preLayoutTableRow(tctx: var TableContext; row, parent: BlockBox;
    rowi, numrows: int): RowContext =
  let lctx = tctx.lctx
  var cellHead: CellWrapper = nil
  var cellTail: CellWrapper = nil
  var blockBorder = Span(start: tctx.blockSpacing, send: tctx.blockSpacing)
  var n = 0
  var growi = 0
  var width = 0'lu
  var borderWidth = 0'lu
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
    let perc = if cw.auto: 0f32 else: cw.perc
    let space = initSpace(
      w = cw.cellWidthPx(),
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
    width += tctx.preLayoutTableColspan(cellw, space, rowi, n, nextn, perc)
    # add spacing for border inside colspan
    let spacing = tctx.inlineSpacing * ((colspan - 1) * 2).toLUnit()
    width += spacing
    borderWidth += spacing
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
    of VerticalAlignTop:
      0'lu
    of VerticalAlignMiddle:
      availableHeight div 2'lu - cell.state.size.h div 2'lu
    of VerticalAlignBottom:
      availableHeight - cell.state.size.h
    else:
      baseline - cell.state.firstBaseline)
  cell.state.size.h = availableHeight

proc layoutTableRow(tctx: TableContext; ctx: RowContext;
    parent, row: BlockBox; rowi: int) =
  row.keepLayout = true
  row.resetState()
  var x = 0'lu
  var n = 0
  var baseline = 0'lu
  var cellw = ctx.cellHead
  while cellw != nil:
    var w = 0'lu
    var reflow = cellw.reflow
    let colspan1 = cellw.colspan - 1
    if n < tctx.cols.len:
      for col in tctx.cols.toOpenArray(n, n + colspan1):
        w += col.width
        reflow = reflow or rowi < col.reflow
    # Add inline spacing for merged columns.
    w += tctx.inlineSpacing * colspan1.toLUnit() * 2'lu
    if reflow and cellw.box != nil:
      let space = initSpace(w = stretch(w), h = maxContent())
      let border = cellw.box.input.border
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
      row.state.size.h = max(row.state.size.h,
        cell.state.size.h div cellw.rowspan.toLUnit())
    else:
      row.state.size.h = max(row.state.size.h,
        cellw.real.box.state.size.h div cellw.rowspan.toLUnit())
    cellw = cellw.next
  cellw = ctx.cellHead
  while cellw != nil:
    if cellw.box != nil:
      if cellw.rowspan > 1:
        cellw.height += row.state.size.h
        cellw.baseline = baseline
      else:
        alignTableCell(cellw.box, row.state.size.h, baseline)
    else:
      let real = cellw.real
      real.height += row.state.size.h
      if cellw.last:
        alignTableCell(real.box, real.height, real.baseline)
    cellw = cellw.next
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
      child.keepLayout = true
      for it in child.children:
        case display
        of DisplayTableHeaderGroup: thead.add(BlockBox(it))
        of DisplayTableRowGroup: tbody.add(BlockBox(it))
        of DisplayTableFooterGroup: tfoot.add(BlockBox(it))
        else: assert false, $child.computed{"display"}
  tctx.preLayoutTableRows(thead, table)
  tctx.preLayoutTableRows(tbody, table)
  tctx.preLayoutTableRows(tfoot, table)

proc calcSpecifiedRatio(tctx: var TableContext;
    totalWidth, weightRatio: float32): float32 =
  var totalSpecified = 0'lu
  var hasUnspecified = false
  let hasWeightRatio = not almostEqual(weightRatio, 1)
  for col in tctx.cols.mitems:
    let minwidth = col.minwidth
    if col.weight > 0:
      let width = max((col.weight * totalWidth).toLUnit(), minwidth)
      totalSpecified += width
      col.width = width
    elif col.widthSpecified:
      if hasWeightRatio:
        let scaled = (col.width.toFloat32() * weightRatio).toLUnit()
        col.width = max(scaled, minwidth)
        col.reflow = tctx.rows.len
      totalSpecified += col.width
    else:
      hasUnspecified = true
      totalSpecified += minwidth
  # Only grow specified columns if no unspecified column exists to take the
  # rest of the space.
  if totalSpecified == 0'lu:
    return 1
  let ftotalSpecified = totalSpecified.toFloat32()
  if hasUnspecified and totalWidth > ftotalSpecified:
    return 1
  return totalWidth / ftotalSpecified

proc calcUnspecifiedColIndices(tctx: var TableContext; W: var LUnit;
    weight: var float32; weightRatio: float32): seq[int] =
  let totalWidth = W.toFloat32()
  let rtotalWidth = 1 / W.toFloat32()
  let specifiedRatio = tctx.calcSpecifiedRatio(totalWidth, weightRatio)
  let hasSpecifiedRatio = not almostEqual(specifiedRatio, 1)
  # Spacing for each column:
  var avail = newSeqOfCap[int](tctx.cols.len)
  for i, col in tctx.cols.mpairs:
    if col.weight != 0:
      W -= col.width
      col.width = (col.width.toFloat32() * specifiedRatio).toLUnit()
      col.reflow = tctx.rows.len
    elif col.widthSpecified:
      if hasSpecifiedRatio:
        col.width = (col.width.toFloat32() * specifiedRatio).toLUnit()
        col.reflow = tctx.rows.len
      W -= col.width
    else:
      avail.add(i)
      let width = col.width.toFloat32()
      let w = if width < totalWidth:
        width
      else:
        totalWidth * (ln(width * rtotalWidth) + 1)
      let colWeight = w * specifiedRatio
      col.weight = colWeight
      weight += colWeight
  move(avail)

proc needsRedistribution(tctx: TableContext; computed: CSSValues): bool =
  case tctx.space.w.t
  of scMinContent, scMaxContent, scMeasure:
    return false
  of scStretch:
    return tctx.hasAuthorWeight or tctx.space.w.u != tctx.maxwidth
  of scFitContent:
    return tctx.space.w.u > tctx.maxwidth and not computed{"width"}.auto or
        tctx.space.w.u < tctx.maxwidth

proc expandToWeight(tctx: var TableContext): float32 =
  var maxwidth = tctx.maxwidth
  var avail = 1f32
  var unassigned = 0'lu
  var specified = 0'lu
  var hasUnspecified = false
  for col in tctx.cols.mitems:
    let weight = min(col.weight, avail)
    if weight == 0:
      unassigned += col.width
      if col.widthSpecified:
        specified += col.width
      else:
        hasUnspecified = true
      continue
    let colTarget = (1 / weight).toLUnit() * col.minwidth
    maxwidth = max(maxwidth, colTarget)
    col.weight = weight
    avail -= weight
  let omaxwidth = maxwidth
  if avail > 0:
    let restTarget = (1 / avail).toLUnit() * unassigned
    maxwidth = max(maxwidth, restTarget) + tctx.borderWidth
  elif unassigned > 0'lu:
    maxwidth = tctx.space.w.u
  else:
    maxwidth += tctx.borderWidth
  if tctx.space.w.t == scFitContent:
    tctx.space.w = stretch(min(tctx.space.w.u, maxwidth))
  if hasUnspecified and tctx.space.w.u > omaxwidth + unassigned:
    # the unspecified column will take the rest of the width
    return 1
  let fspecified = unassigned.toFloat32()
  if fspecified == 0:
    return 1
  # either the total column width too small, and there are no unspecified
  # columns to take the rest, or columns overflow the table and must be
  # rescaled.
  return (tctx.space.w.u.toFloat32() * avail) / fspecified

proc redistributeWidth(tctx: var TableContext; weightRatio: float32) =
  # Remove inline spacing from distributable width.
  var W = max(tctx.space.w.u - tctx.borderWidth, 0'lu)
  var weight = 0f32
  var avail = tctx.calcUnspecifiedColIndices(W, weight, weightRatio)
  var redo = true
  while redo and avail.len > 0 and weight != 0:
    if weight == 0: break # zero weight; nothing to distribute
    W = max(W, 0'lu)
    redo = false
    # divide delta width by sum of ln(width) for all elem in avail
    let unit = W.toFloat32() / weight
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

proc layoutTableRows(tctx: TableContext; table: BlockBox; input: LayoutInput) =
  var y = 0'lu
  for i, roww in tctx.rows.mypairs:
    if roww.box.computed{"visibility"} == VisibilityCollapse:
      continue
    y += roww.blockBorder.start
    let row = roww.box
    tctx.layoutTableRow(roww, table, row, i)
    row.state.offset.y += y
    row.state.offset.x += input.padding.left
    row.state.size.w += input.padding[dtHorizontal].sum()
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

proc layoutCaption(lctx: LayoutContext; box: BlockBox; space: Space;
    input: var LayoutInput) =
  input = lctx.resolveBlockSizes(space, box.computed)
  lctx.layout(box, input.margin.topLeft, input)

proc layoutInnerTable(tctx: var TableContext; table, parent: BlockBox;
    input: LayoutInput) =
  # Switch the table's space to fit-content if its width is auto.  (Note
  # that we call canpx on space, which might have been changed by specified
  # width.  This isn't a problem however, because canpx will still return
  # true after that.) <-- TODO not sure if any of this still make sense (I
  # think it does?)
  if tctx.space.w.t == scStretch:
    let width = parent.computed{"width"}
    if width.isPx():
      table.state.intr.w = tctx.space.w.u
    elif not width.canpx(tctx.space.w):
      tctx.space.w = fitContent(tctx.space.w.u)
  if table.computed{"border-collapse"} != BorderCollapseCollapse:
    tctx.inlineSpacing = table.computed{"-cha-border-spacing-inline"}.px(0'lu)
    tctx.blockSpacing = table.computed{"-cha-border-spacing-block"}.px(0'lu)
  tctx.preLayoutTableRows(table) # first pass
  let weightRatio = if tctx.hasAuthorWeight and tctx.space.w.isDefinite():
    tctx.expandToWeight()
  else:
    1f32
  if tctx.needsRedistribution(table.computed):
    tctx.redistributeWidth(weightRatio)
  for col in tctx.cols:
    table.state.size.w += col.width
  tctx.layoutTableRows(table, input) # second pass
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
    input: LayoutInput) =
  if not lctx.layoutFlowRootPre(box, offset, input):
    return
  let table = BlockBox(box.firstChild)
  table.keepLayout = true
  table.resetState()
  var tctx = TableContext(lctx: lctx, space: input.space)
  let caption = BlockBox(table.next)
  var captionSpace = initSpace(
    w = fitContent(input.space.w),
    h = maxContent()
  )
  var captionSizes: LayoutInput
  if caption != nil:
    lctx.layoutCaption(caption, captionSpace, captionSizes)
    if captionSpace.w.isDefinite():
      if caption.state.intr.w != captionSpace.w.u:
        captionSpace.w.u = caption.state.intr.w
      if tctx.space.w.t == scStretch and tctx.space.w.u < captionSpace.w.u:
        tctx.space.w.u = captionSpace.w.u
  tctx.layoutInnerTable(table, box, input)
  box.state.size = table.state.size
  box.state.intr = table.state.intr
  var baseline = 0'lu
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
    input: LayoutInput

  FlexContext = object
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

proc layoutFlexItem(lctx: LayoutContext; box: BlockBox; input: LayoutInput) =
  lctx.layout(box, Offset0, input, forceRoot = true)

const FlexRow = {FlexDirectionRow, FlexDirectionRowReverse}

proc updateMaxSizes(mctx: var FlexMainContext; child: BlockBox;
    input: LayoutInput; lctx: LayoutContext) =
  for dim in DimensionType:
    mctx.maxSize[dim] = max(mctx.maxSize[dim], child.state.size[dim] +
      input.borderSum(dim, lctx))
    mctx.maxMargin[dim].start = max(mctx.maxMargin[dim].start,
      input.margin[dim].start)
    mctx.maxMargin[dim].send = max(mctx.maxMargin[dim].send,
      input.margin[dim].send)

proc redistributeMainSize(mctx: var FlexMainContext; diff: LUnit;
    wt: FlexWeightType; dim: DimensionType; lctx: LayoutContext) =
  var diff = diff
  var totalWeight = mctx.totalWeight[wt]
  let odim = dim.opposite
  var relayout: seq[int] = @[]
  while (wt == fwtGrow and diff > 0'lu or wt == fwtShrink and diff < 0'lu) and
      totalWeight > 0:
    # redo maxSize calculation; we only need height here
    mctx.maxSize[odim] = 0'lu
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
    diff = 0'lu
    relayout.setLen(0)
    for i, it in mctx.pending.mpairs:
      if it.weights[wt] == 0:
        mctx.updateMaxSizes(it.child, it.input, lctx)
        continue
      var uw = unit * it.weights[wt]
      if wt == fwtShrink:
        uw *= it.child.state.size[dim].toFloat32()
      var u = it.child.state.size[dim] + uw.toLUnit()
      # check for min/max violation
      let minu = max(it.child.state.intr[dim], it.input.bounds.a[dim].start)
      if minu > u:
        # min violation
        if wt == fwtShrink: # freeze
          diff += u - minu
          it.weights[wt] = 0
          mctx.shrinkSize -= it.child.state.size[dim]
        u = minu
        it.input.bounds.mi[dim].start = u
      let maxu = max(minu, it.input.bounds.a[dim].send)
      if maxu < u:
        # max violation
        if wt == fwtGrow: # freeze
          diff += u - maxu
          it.weights[wt] = 0
        u = maxu
        it.input.bounds.mi[dim].send = u
      u -= it.input.padding[dim].sum()
      it.input.space[dim] = stretch(u)
      # override minimum intrinsic size clamping too
      totalWeight += it.weights[wt]
      if it.weights[wt] == 0: # frozen, relayout immediately
        lctx.layoutFlexItem(it.child, it.input)
        mctx.updateMaxSizes(it.child, it.input, lctx)
      else: # delay relayout
        relayout.add(i)
    for i in relayout:
      let child = mctx.pending[i].child
      lctx.layoutFlexItem(child, mctx.pending[i].input)
      mctx.updateMaxSizes(child, mctx.pending[i].input, lctx)

proc flushMain(fctx: var FlexContext; mctx: var FlexMainContext;
    input: LayoutInput) =
  let dim = fctx.dim
  let odim = dim.opposite
  let lctx = fctx.lctx
  if fctx.redistSpace.isDefinite:
    let diff = fctx.redistSpace.u - mctx.totalSize[dim]
    let wt = if diff > 0'lu: fwtGrow else: fwtShrink
    # Do not grow shrink-to-fit input.
    if wt == fwtShrink or fctx.redistSpace.t == scStretch:
      mctx.redistributeMainSize(diff, wt, dim, lctx)
  elif input.bounds.a[dim].start > 0'lu:
    # Override with min-width/min-height, but *only* if we are smaller
    # than the desired size. (Otherwise, we would incorrectly limit
    # max-content size when only a min-width is requested.)
    if input.bounds.a[dim].start > mctx.totalSize[dim]:
      let diff = input.bounds.a[dim].start - mctx.totalSize[dim]
      mctx.redistributeMainSize(diff, fwtGrow, dim, lctx)
  let maxMarginSum = mctx.maxMargin[odim].sum()
  let h = mctx.maxSize[odim] + maxMarginSum
  var intr = size(w = 0'lu, h = 0'lu)
  var offset = fctx.offset
  for it in mctx.pending.mitems:
    let oborder = it.child.input.borderSum(odim, lctx)
    if it.child.state.size[odim] + oborder < h and
        not it.input.space[odim].isDefinite:
      # if the max height is greater than our height, then take max height
      # instead. (if the box's available height is definite, then this will
      # change nothing, so we skip it as an optimization.)
      it.input.space[odim] = stretch(h - it.input.margin[odim].sum() -
        it.input.padding[odim].sum() - oborder)
      if odim == dtVertical:
        # Exclude the bottom margin; space only applies to the actual
        # height.
        it.input.space[odim].u -= it.child.state.marginTodo.sum()
      lctx.layoutFlexItem(it.child, it.input)
    offset[dim] += it.input.margin[dim].start
    it.child.state.offset[dim] += offset[dim]
    # resolve auto cross margins for shrink-to-fit items
    if input.space[odim].t == scStretch:
      let start = it.child.computed.getLength(MarginStartMap[odim])
      let send = it.child.computed.getLength(MarginEndMap[odim])
      # We can get by without adding offset, because flex items are
      # always layouted at (0, 0).
      let underflow = input.space[odim].u - it.child.state.size[odim] -
        it.input.margin[odim].sum() - oborder
      if underflow > 0'lu and start.auto:
        # we don't really care about the end margin, because that is
        # already taken into account by Space
        if not send.auto:
          it.input.margin[odim].start = underflow
        else:
          it.input.margin[odim].start = underflow div 2'lu
    # margins are added here, since they belong to the flex item.
    it.child.state.offset[odim] += offset[odim] + it.input.margin[odim].start
    offset[dim] += it.child.state.size[dim]
    offset[dim] += it.input.margin[dim].send
    offset[dim] += it.input.borderSum(dim, lctx)
    let intru = it.child.state.intr[dim] + it.input.margin[dim].sum()
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
  fctx.intr[dim] = max(fctx.intr[dim], intr[dim])
  fctx.intr[odim] += intr[odim] + maxMarginSum
  mctx = FlexMainContext()
  fctx.offset[odim] += h

proc layoutFlexIter(fctx: var FlexContext; mctx: var FlexMainContext;
    child: BlockBox; input: LayoutInput) =
  let lctx = fctx.lctx
  let dim = fctx.dim
  var childSizes = lctx.resolveFlexItemSizes(input.space, dim, child.computed)
  let flexBasis = child.computed{"flex-basis"}
  let childMinBounds = childSizes.bounds.a[dim]
  let skipBounds = childSizes.space[dim].t == scMaxContent
  if skipBounds:
    childSizes.bounds.a[dim] = DefaultSpan
  lctx.layoutFlexItem(child, childSizes)
  if not flexBasis.auto and input.space[dim].isDefinite:
    # we can't skip this pass; it is needed to calculate the minimum
    # height.
    let minu = child.state.intr[dim]
    childSizes.space[dim] = stretch(flexBasis.spx(input.space[dim],
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
    child.input.bfcOffset = Offset0
  else:
    if fctx.canWrap and (input.space[dim].t == scMinContent or
        input.space[dim].isDefinite and
        mctx.totalSize[dim] + child.state.size[dim] > input.space[dim].u):
      fctx.flushMain(mctx, input)
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
      input: childSizes
    ))

proc layoutFlex(lctx: LayoutContext; box: BlockBox; offset: Offset;
    input: LayoutInput) =
  if not lctx.layoutFlowRootPre(box, offset, input):
    return
  let flexDir = box.computed{"flex-direction"}
  let dim = if flexDir in FlexRow: dtHorizontal else: dtVertical
  let odim = dim.opposite()
  var fctx = FlexContext(
    lctx: lctx,
    offset: input.padding.topLeft,
    redistSpace: input.space[dim],
    canWrap: box.computed{"flex-wrap"} != FlexWrapNowrap,
    reverse: box.computed{"flex-direction"} in FlexReverse,
    dim: dim
  )
  if fctx.redistSpace.t == scFitContent and input.bounds.a[dim].start > 0'lu:
    fctx.redistSpace = stretch(input.bounds.a[dim].start)
  if fctx.redistSpace.isDefinite:
    fctx.redistSpace.u = fctx.redistSpace.u.minClamp(input.bounds.a[dim])
  var mctx = FlexMainContext()
  for child in box.children:
    let child = BlockBox(child)
    fctx.layoutFlexIter(mctx, child, input)
  if mctx.pending.len > 0:
    fctx.flushMain(mctx, input)
  let paddingSum = input.padding.sum()
  var size = fctx.totalMaxSize
  size[odim] = fctx.offset[odim]
  size -= input.padding.topLeft
  box.applySize(input, size, input.space)
  box.state.size += paddingSum
  box.applyIntr(input, fctx.intr + paddingSum)
  box.state.baselineSet = fctx.baselineSet
  box.state.firstBaseline = fctx.firstBaseline
  box.state.baseline = fctx.baseline
  for child in fctx.relativeChildren:
    lctx.positionRelative(input.space, child)

proc layout(lctx: LayoutContext; box: BlockBox; offset: Offset;
    input: LayoutInput; forceRoot = false) =
  case box.computed{"display"}
  of DisplayFlowRoot, DisplayTableCaption, DisplayInlineBlock, DisplayInnerGrid,
      DisplayMarker:
    lctx.layoutFlowRoot(box, offset, input)
  of DisplayBlock, DisplayListItem:
    if forceRoot or box.computed{"position"} in PositionAbsoluteFixed or
        box.computed{"float"} != FloatNone or
        box.computed{"overflow-x"} notin {OverflowVisible, OverflowClip}:
      lctx.layoutFlowRoot(box, offset, input)
    else:
      lctx.layoutFlowDescendant(box, offset, input)
  of DisplayTableCell: lctx.layoutFlow(box, input, root = true)
  of DisplayInnerTable: lctx.layoutTable(box, offset, input)
  of DisplayInnerFlex: lctx.layoutFlex(box, offset, input)
  else: assert false
  if input.space.w.t != scMeasure:
    lctx.popPositioned(box.absolute, box.state.size)

proc layout*(box: BlockBox; attrs: WindowAttributes; fixedHead: CSSAbsolute;
    luctx: LUContext) =
  var size = size(w = attrs.widthPx.toLUnit(), h = attrs.heightPx.toLUnit())
  let space = initSpace(w = stretch(size.w), h = stretch(size.h))
  let cellSize = size(w = attrs.ppc.toLUnit(), h = attrs.ppl.toLUnit())
  let lctx = LayoutContext(cellSize: cellSize, luctx: luctx)
  let input = lctx.resolveBlockSizes(space, box.computed)
  # the bottom margin is unused.
  lctx.layout(box, input.margin.topLeft, input, forceRoot = true)
  # Fixed containing block.
  # The idea is to move fixed boxes to the real edges of the page,
  # so that they do not overlap with other boxes *and* we don't have
  # to move them on scroll. It's still not compatible with what desktop
  # browsers do, but the alternative would completely break search (and
  # slow down the renderer to a crawl.)
  size.w = max(size.w, box.state.size.w)
  size.h = max(size.h, box.state.size.h)
  lctx.popPositioned(fixedHead, size)

{.pop.} # raises: []
