import css/cssvalues
import css/lunit
import html/dom
import types/bitmap

type
  DimensionType* = enum
    dtHorizontal, dtVertical

  Offset* = array[DimensionType, LUnit]

  Size* = array[DimensionType, LUnit]

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
    firstBaseline*: LUnit
    # baseline of the last line box of all descendants
    baseline*: LUnit
    # bottom margin result
    marginBottom*: LUnit

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
    node*: Element
    case t*: InlineBoxType
    of ibtParent:
      children*: seq[InlineBox]
    of ibtText:
      text*: CharacterData # note: this has no parent.
    of ibtNewline:
      discard
    of ibtBitmap:
      bmp*: NetworkBitmap
    of ibtBox:
      box*: BlockBox

  Span* = object
    start*: LUnit
    send*: LUnit

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
    u*: LUnit

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
    node*: Element
    inline*: InlineBox
    children*: seq[BlockBox]

func offset*(x, y: LUnit): Offset =
  return [dtHorizontal: x, dtVertical: y]

func x*(offset: Offset): LUnit {.inline.} =
  return offset[dtHorizontal]

func x*(offset: var Offset): var LUnit {.inline.} =
  return offset[dtHorizontal]

func `x=`*(offset: var Offset; x: LUnit) {.inline.} =
  offset[dtHorizontal] = x

func y*(offset: Offset): LUnit {.inline.} =
  return offset[dtVertical]

func y*(offset: var Offset): var LUnit {.inline.} =
  return offset[dtVertical]

func `y=`*(offset: var Offset; y: LUnit) {.inline.} =
  offset[dtVertical] = y

func size*(w, h: LUnit): Size =
  return [dtHorizontal: w, dtVertical: h]

func w*(size: Size): LUnit {.inline.} =
  return size[dtHorizontal]

func w*(size: var Size): var LUnit {.inline.} =
  return size[dtHorizontal]

func `w=`*(size: var Size; w: LUnit) {.inline.} =
  size[dtHorizontal] = w

func h*(size: Size): LUnit {.inline.} =
  return size[dtVertical]

func h*(size: var Size): var LUnit {.inline.} =
  return size[dtVertical]

func `h=`*(size: var Size; h: LUnit) {.inline.} =
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

func left*(s: RelativeRect): LUnit =
  return s[dtHorizontal].start

func right*(s: RelativeRect): LUnit =
  return s[dtHorizontal].send

func top*(s: RelativeRect): LUnit =
  return s[dtVertical].start

func bottom*(s: RelativeRect): LUnit =
  return s[dtVertical].send

func topLeft*(s: RelativeRect): Offset =
  return offset(x = s.left, y = s.top)

proc `+=`*(span: var Span; u: LUnit) =
  span.start += u
  span.send += u
