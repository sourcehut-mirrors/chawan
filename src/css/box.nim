import css/cssvalues
import css/lunit
import html/dom
import types/bitmap
import types/refstring

type
  DimensionType* = enum
    dtHorizontal, dtVertical

  Offset* = array[DimensionType, LUnit]

  Size* = array[DimensionType, LUnit]

  InlineImageState* = object
    offset*: Offset
    size*: Size

  # Note: with some effort this could be turned into a non-ref object,
  # but that's slower (at least with refc).
  TextRun* = ref object
    offset*: Offset
    s*: string

  BorderStyleSpan* = object
    start*: CSSBorderStyle
    send*: CSSBorderStyle

  CSSBorder* = array[DimensionType, BorderStyleSpan]

  CSSBorderMerge* = array[DimensionType, bool]

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
    # Bottom margin of the box, collapsed with the margin of children.
    # This is already added to size, and only used by flex layout.
    marginBottom*: LUnit
    # Indicates which borders have been merged with an adjacent one.
    merge*: CSSBorderMerge
    # Whether or not a line box has set a baseline for us.
    baselineSet*: bool

  Area* = object
    offset*: Offset
    size*: Size

  InlineBoxState* = object
    startOffset*: Offset # offset of the first word, for position: absolute
    areas*: seq[Area] # background that should be painted by box

  Span* = object
    start*: LUnit
    send*: LUnit

  RelativeRect* = array[DimensionType, Span]

  StackItem* = ref object
    box*: CSSBox
    index*: int32
    children*: seq[StackItem]

  ClipBox* = object
    start*: Offset
    send*: Offset

  BoxRenderState* = object
    # Whether the following two variables have been initialized.
    #TODO find a better name that doesn't conflict with box.positioned
    positioned*: bool
    offset*: Offset
    clipBox*: ClipBox

  # min-content: box width is longest word's width
  # max-content: box width is content width without wrapping
  # stretch: box width is n px wide
  # fit-content: also known as shrink-to-fit, box width is
  #   min(max-content, stretch(availableWidth))
  #   in other words, as wide as needed, but wrap if wider than allowed
  # (note: I write width here, but it can apply for any constraint)
  SizeConstraintType* = enum
    scStretch, scFitContent, scMinContent, scMaxContent, scMeasure

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
    border*: CSSBorder

  CSSBox* = ref object of RootObj
    parent* {.cursor.}: CSSBox
    firstChild*: CSSBox
    next*: CSSBox
    absolute*: CSSAbsolute
    positioned*: bool # set if we participate in positioned layout
    render*: BoxRenderState # render output
    computed*: CSSValues
    element*: Element

  CSSAbsolute* {.acyclic.} = ref object
    box*: BlockBox
    next*: CSSAbsolute

  BlockBox* = ref object of CSSBox
    sizes*: ResolvedSizes # tree builder output -> layout input
    state*: BoxLayoutState # layout output -> render input

  InlineBox* = ref object of CSSBox
    state*: InlineBoxState

  InlineTextBox* = ref object of InlineBox
    runs*: seq[TextRun] # state
    text*: RefString

  InlineNewLineBox* = ref object of InlineBox

  InlineImageBox* = ref object of InlineBox
    imgstate*: InlineImageState
    bmp*: NetworkBitmap

  InlineBlockBox* = ref object of InlineBox
    # InlineBlockBox always has one block child.

proc offset*(x, y: LUnit): Offset =
  return [dtHorizontal: x, dtVertical: y]

proc x*(offset: Offset): LUnit {.inline.} =
  return offset[dtHorizontal]

proc x*(offset: var Offset): var LUnit {.inline.} =
  return offset[dtHorizontal]

proc `x=`*(offset: var Offset; x: LUnit) {.inline.} =
  offset[dtHorizontal] = x

proc y*(offset: Offset): LUnit {.inline.} =
  return offset[dtVertical]

proc y*(offset: var Offset): var LUnit {.inline.} =
  return offset[dtVertical]

proc `y=`*(offset: var Offset; y: LUnit) {.inline.} =
  offset[dtVertical] = y

proc size*(w, h: LUnit): Size =
  return [dtHorizontal: w, dtVertical: h]

proc w*(size: Size): LUnit {.inline.} =
  return size[dtHorizontal]

proc w*(size: var Size): var LUnit {.inline.} =
  return size[dtHorizontal]

proc `w=`*(size: var Size; w: LUnit) {.inline.} =
  size[dtHorizontal] = w

proc h*(size: Size): LUnit {.inline.} =
  return size[dtVertical]

proc h*(size: var Size): var LUnit {.inline.} =
  return size[dtVertical]

proc `h=`*(size: var Size; h: LUnit) {.inline.} =
  size[dtVertical] = h

proc `+`*(a, b: Offset): Offset =
  return offset(x = a.x + b.x, y = a.y + b.y)

proc `-`*(a, b: Offset): Offset =
  return offset(x = a.x - b.x, y = a.y - b.y)

proc `+=`*(a: var Offset; b: Offset) =
  a.x += b.x
  a.y += b.y

proc `-=`*(a: var Offset; b: Offset) =
  a.x -= b.x
  a.y -= b.y

proc left*(s: RelativeRect): LUnit =
  return s[dtHorizontal].start

proc right*(s: RelativeRect): LUnit =
  return s[dtHorizontal].send

proc top*(s: RelativeRect): LUnit =
  return s[dtVertical].start

proc bottom*(s: RelativeRect): LUnit =
  return s[dtVertical].send

proc left*(b: CSSBorder): CSSBorderStyle =
  return b[dtHorizontal].start

proc right*(b: CSSBorder): CSSBorderStyle =
  return b[dtHorizontal].send

proc top*(b: CSSBorder): CSSBorderStyle =
  return b[dtVertical].start

proc bottom*(b: CSSBorder): CSSBorderStyle =
  return b[dtVertical].send

proc topLeft*(s: RelativeRect): Offset =
  return offset(x = s.left, y = s.top)

proc bottomRight*(s: RelativeRect): Offset =
  return offset(x = s.right, y = s.bottom)

proc `+=`*(span: var Span; u: LUnit) =
  span.start += u
  span.send += u

proc `<`*(a, b: Offset): bool =
  return a.x < b.x and a.y < b.y

proc borderTopLeft*(sizes: ResolvedSizes; cellSize: Size): Offset =
  var o = offset(0, 0)
  if sizes.border.left notin BorderStyleNoneHidden:
    o.x += cellSize.w
  if sizes.border.top notin BorderStyleNoneHidden:
    o.y += cellSize.h
  o

proc borderBottomRight*(sizes: ResolvedSizes; cellSize: Size): Offset =
  var o = offset(0, 0)
  if sizes.border.right notin BorderStyleNoneHidden:
    o.x += cellSize.w
  if sizes.border.bottom notin BorderStyleNoneHidden:
    o.y += cellSize.h
  o

iterator children*(box: CSSBox): CSSBox =
  var it {.cursor.} = box.firstChild
  while it != nil:
    yield it
    it = it.next

proc resetState(box: CSSBox) =
  box.render = BoxRenderState()

proc resetState*(ibox: InlineBox) =
  CSSBox(ibox).resetState()
  ibox.state = InlineBoxState()

proc resetState*(box: BlockBox) =
  CSSBox(box).resetState()
  box.state = BoxLayoutState()

const DefaultClipBox* = ClipBox(send: offset(LUnit.high, LUnit.high))

when defined(debug):
  import chame/tags

  proc `$`*(box: CSSBox; pass2 = true): string =
    if box.positioned and not pass2:
      return ""
    result = "<"
    let name = if box.computed{"display"} != DisplayInline:
      if box.element.tagType in {TAG_HTML, TAG_BODY}:
        $box.element.tagType
      else:
        "div"
    elif box of InlineNewLineBox:
      "br"
    else:
      "span"
    result &= name
    let computed = box.computed.copyProperties()
    if computed{"display"} == DisplayBlock:
      computed{"display"} = DisplayInline
    var style = $computed.serializeEmpty()
    if style != "":
      if style[^1] == ';':
        style.setLen(style.high)
      result &= " style='" & style & "'"
    result &= ">"
    if box of InlineNewLineBox:
      return
    if box of BlockBox:
      result &= '\n'
    for it in box.children:
      result &= `$`(it, pass2 = false)
    if box of InlineTextBox:
      for run in InlineTextBox(box).runs:
        result &= run.s
    if box of BlockBox:
      result &= '\n'
    result &= "</" & name & ">"

  proc `$`*(stack: StackItem): string =
    result = "<STACK index=" & $stack.index & ">\n"
    result &= `$`(stack.box, pass2 = true)
    result &= "\n"
    for child in stack.children:
      result &= "<child>\n"
      result &= $child
      result &= "</child>\n"
    result &= "</STACK>\n"
