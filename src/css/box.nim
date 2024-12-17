import css/cssvalues
import css/lunit
import css/stylednode
import types/bitmap

type
  DimensionType* = enum
    dtHorizontal, dtVertical

  Offset* = array[DimensionType, LayoutUnit]

  Size* = array[DimensionType, LayoutUnit]

  Overflow* = array[DimensionType, Span]

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
    # overflow relative to offset
    overflow*: Overflow
    # intrinsic minimum size (e.g. longest word)
    intr*: Size
    # baseline of the first line box of all descendants
    firstBaseline*: LayoutUnit
    # baseline of the last line box of all descendants
    baseline*: LayoutUnit

  SplitType* = enum
    stSplitStart, stSplitEnd

  Area* = object
    offset*: Offset
    size*: Size

  InlineFragmentState* = object
    startOffset*: Offset # offset of the first word, for position: absolute
    areas*: seq[Area] # background that should be painted by fragment
    atoms*: seq[InlineAtom]

  InlineFragmentType* = enum
    iftParent, iftText, iftNewline, iftBitmap, iftBox

  InlineFragment* = ref object
    state*: InlineFragmentState
    render*: BoxRenderState
    computed*: CSSValues
    node*: StyledNode
    splitType*: set[SplitType]
    case t*: InlineFragmentType
    of iftParent:
      children*: seq[InlineFragment]
    of iftText:
      text*: StyledNode # note: this has no parent.
    of iftNewline:
      discard
    of iftBitmap:
      bmp*: NetworkBitmap
    of iftBox:
      box*: BlockBox

  Span* = object
    start*: LayoutUnit
    send*: LayoutUnit

  RelativeRect* = array[DimensionType, Span]

  BoxRenderState* = object
    offset*: Offset

  BlockBox* = ref object
    state*: BoxLayoutState
    render*: BoxRenderState
    computed*: CSSValues
    node*: StyledNode
    inline*: InlineFragment
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
