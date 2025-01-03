import css/cssvalues
import css/lunit
import css/stylednode
import types/bitmap

type
  DimensionType* = enum
    dtHorizontal, dtVertical

  Offset* = array[DimensionType, LayoutUnit]

  Size* = array[DimensionType, LayoutUnit]

  InlineAtomType* = enum
    iatWord, iatInlineBlock, iatImage

  InlineAtom* = ref object
    offset*: Offset
    size*: Size
    case t*: InlineAtomType
    of iatWord:
      str*: string
    of iatInlineBlock:
      innerbox*: BlockBox
    of iatImage:
      bmp*: NetworkBitmap

  BoxLayoutState* = object
    # offset relative to parent
    offset*: Offset
    # padding size
    size*: Size
    # intrinsic minimum size (e.g. longest word)
    intr*: Size
    # baseline of the first line box of all descendants
    firstBaseline*: LayoutUnit
    # baseline of the last line box of all descendants
    baseline*: LayoutUnit
    # bottom margin result
    marginBottom*: LayoutUnit

  SplitType* = enum
    stSplitStart, stSplitEnd

  Area* = object
    offset*: Offset
    size*: Size

  InlineBoxState* = object
    startOffset*: Offset # offset of the first word, for position: absolute
    areas*: seq[Area] # background that should be painted by box
    atoms*: seq[InlineAtom]

  InlineBoxType* = enum
    ibtParent, ibtText, ibtNewline, ibtBitmap, ibtBox

  InlineBox* = ref object
    state*: InlineBoxState
    render*: BoxRenderState
    computed*: CSSValues
    node*: StyledNode
    splitType*: set[SplitType]
    case t*: InlineBoxType
    of ibtParent:
      children*: seq[InlineBox]
    of ibtText:
      text*: StyledNode # note: this has no parent.
    of ibtNewline:
      discard
    of ibtBitmap:
      bmp*: NetworkBitmap
    of ibtBox:
      box*: BlockBox

  Span* = object
    start*: LayoutUnit
    send*: LayoutUnit

  RelativeRect* = array[DimensionType, Span]

  BoxRenderState* = object
    offset*: Offset

  # min-content: box width is longest word's width
  # max-content: box width is content width without wrapping
  # stretch: box width is n px wide
  # fit-content: also known as shrink-to-fit, box width is
  #   min(max-content, stretch(availableWidth))
  #   in other words, as wide as needed, but wrap if wider than allowed
  # (note: I write width here, but it can apply for any constraint)
  SizeConstraintType* = enum
    scStretch, scFitContent, scMinContent, scMaxContent

  SizeConstraint* = object
    t*: SizeConstraintType
    u*: LayoutUnit

  AvailableSpace* = array[DimensionType, SizeConstraint]

  Bounds* = object
    a*: array[DimensionType, Span] # width clamp
    mi*: array[DimensionType, Span] # intrinsic clamp

  ResolvedSizes* = object
    margin*: RelativeRect
    padding*: RelativeRect
    space*: AvailableSpace
    bounds*: Bounds

  BlockBox* = ref object
    sizes*: ResolvedSizes # tree builder output -> layout input
    state*: BoxLayoutState # layout output -> render input
    render*: BoxRenderState # render output
    computed*: CSSValues
    node*: StyledNode
    inline*: InlineBox
    children*: seq[BlockBox]

func offset*(x, y: LayoutUnit): Offset =
  return [dtHorizontal: x, dtVertical: y]

func x*(offset: Offset): LayoutUnit {.inline.} =
  return offset[dtHorizontal]

func x*(offset: var Offset): var LayoutUnit {.inline.} =
  return offset[dtHorizontal]

func `x=`*(offset: var Offset; x: LayoutUnit) {.inline.} =
  offset[dtHorizontal] = x

func y*(offset: Offset): LayoutUnit {.inline.} =
  return offset[dtVertical]

func y*(offset: var Offset): var LayoutUnit {.inline.} =
  return offset[dtVertical]

func `y=`*(offset: var Offset; y: LayoutUnit) {.inline.} =
  offset[dtVertical] = y

func size*(w, h: LayoutUnit): Size =
  return [dtHorizontal: w, dtVertical: h]

func w*(size: Size): LayoutUnit {.inline.} =
  return size[dtHorizontal]

func w*(size: var Size): var LayoutUnit {.inline.} =
  return size[dtHorizontal]

func `w=`*(size: var Size; w: LayoutUnit) {.inline.} =
  size[dtHorizontal] = w

func h*(size: Size): LayoutUnit {.inline.} =
  return size[dtVertical]

func h*(size: var Size): var LayoutUnit {.inline.} =
  return size[dtVertical]

func `h=`*(size: var Size; h: LayoutUnit) {.inline.} =
  size[dtVertical] = h

func `+`*(a, b: Offset): Offset =
  return offset(x = a.x + b.x, y = a.y + b.y)

func `-`*(a, b: Offset): Offset =
  return offset(x = a.x - b.x, y = a.y - b.y)

proc `+=`*(a: var Offset; b: Offset) =
  a.x += b.x
  a.y += b.y

proc `-=`*(a: var Offset; b: Offset) =
  a.x -= b.x
  a.y -= b.y

func left*(s: RelativeRect): LayoutUnit =
  return s[dtHorizontal].start

func right*(s: RelativeRect): LayoutUnit =
  return s[dtHorizontal].send

func top*(s: RelativeRect): LayoutUnit =
  return s[dtVertical].start

func bottom*(s: RelativeRect): LayoutUnit =
  return s[dtVertical].send

proc `+=`*(span: var Span; u: LayoutUnit) =
  span.start += u
  span.send += u
