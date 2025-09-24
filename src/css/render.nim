{.push raises: [].}

import css/box
import css/cssvalues
import css/lunit
import html/dom
import types/bitmap
import types/cell
import types/color
import types/winattrs
import utils/strwidth
import utils/twtstr

type
  # A FormatCell *starts* a new terminal formatting context.
  # If no FormatCell exists before a given cell, the default formatting is used.
  FormatCell* = object
    format*: Format
    pos*: int
    node*: Element

  # Following properties should hold for `formats':
  # * Position should be >= 0, <= str.width().
  # * The position of every FormatCell should be greater than the position
  #   of the previous FormatCell.
  FlexibleLine* = object
    str*: string
    formats*: seq[FormatCell]

  FlexibleGrid* = seq[FlexibleLine]

  PosBitmap* = ref object
    x*: int
    y*: int
    offx*: int
    offy*: int
    width*: int
    height*: int
    bmp*: NetworkBitmap

  RenderState = object
    bgcolor: CellColor
    attrsp: ptr WindowAttributes
    images: seq[PosBitmap]
    spaces: string # buffer filled with spaces for padding
    cellSize: Size # size(w = attrsp.ppc, h = attrsp.ppl)

# Forward declarations
proc renderBlock(grid: var FlexibleGrid; state: var RenderState;
  box: BlockBox; offset: Offset; pass2 = false)

template attrs(state: RenderState): WindowAttributes =
  state.attrsp[]

proc findFormatN*(line: FlexibleLine; pos: int; start = 0): int =
  var i = start
  while i < line.formats.len:
    if line.formats[i].pos > pos:
      break
    inc i
  return i

proc insertFormat(line: var FlexibleLine; i: int; cell: FormatCell) =
  line.formats.insert(cell, i)

proc insertFormat(line: var FlexibleLine; pos, i: int; format: Format;
    node: Element) =
  line.insertFormat(i, FormatCell(format: format, node: node, pos: pos))

proc toFormat(computed: CSSValues): Format =
  if computed == nil:
    return Format()
  var flags: set[FormatFlag] = {}
  if computed{"font-style"} in {FontStyleItalic, FontStyleOblique}:
    flags.incl(ffItalic)
  if computed{"font-weight"} > 500:
    flags.incl(ffBold)
  if TextDecorationUnderline in computed{"text-decoration"}:
    flags.incl(ffUnderline)
  if TextDecorationOverline in computed{"text-decoration"}:
    flags.incl(ffOverline)
  if TextDecorationLineThrough in computed{"text-decoration"}:
    flags.incl(ffStrike)
  if TextDecorationBlink in computed{"text-decoration"}:
    flags.incl(ffBlink)
  if TextDecorationReverse in computed{"text-decoration"}:
    flags.incl(ffReverse)
  #TODO this ignores alpha; we should blend somewhere.
  return initFormat(defaultColor, computed{"color"}.cellColor(), flags)

proc findFirstX(line: var FlexibleLine; x: int; outi: var int): int =
  var cx = 0
  var i = 0
  while cx < x and i < line.str.len:
    let pi = i
    let u = line.str.nextUTF8(i)
    let w = u.width()
    # we must ensure x is max(cx, x), otherwise our assumption of cx <= x
    # breaks down
    if cx + w > x:
      i = pi
      break
    cx += w
  outi = i
  return cx

proc setTextStr(line: var FlexibleLine; s, ostr: openArray[char];
    i, x, cx, nx, targetX: int) =
  var i = i
  let padlen = i + x - cx
  var widthError = max(nx - targetX, 0)
  let targeti = padlen + s.len
  line.str.setLen(targeti + widthError + ostr.len)
  while i < padlen: # place before new string
    line.str[i] = ' '
    inc i
  copyMem(addr line.str[i], unsafeAddr s[0], s.len)
  i = targeti
  while widthError > 0:
    # we ate half of a double width char; pad it out with spaces.
    line.str[i] = ' '
    dec widthError
    inc i
  if ostr.len > 0:
    copyMem(addr line.str[i], unsafeAddr ostr[0], ostr.len)

proc setTextFormat(line: var FlexibleLine; x, cx, targetX, nx: int;
    hadStr: bool; format: Format; node: Element) =
  var fi = line.findFormatN(cx) - 1 # Skip unchanged formats before new string
  var lformat = initFormat()
  var lnode: Element = nil
  if fi != -1:
    # Start by saving the old formatting before padding for later use.
    # This is important because the following code will gladly overwrite
    # said formatting.
    lformat = line.formats[fi].format # save for later use
    lnode = line.formats[fi].node
    if x > cx:
      # Amend formatting for padding.
      # Since we only generate padding in place of non-existent text, it
      # should be enough to just append a single format cell to erase the
      # last one's effect.
      # (This means that if fi is -1, we have nothing to erase ->
      # nothing to do.)
      let pos = line.formats[fi].pos
      if pos == cx:
        # This branch is only taken if we are overwriting a double-width
        # char.  Then it is possible to get a single blank cell of
        # padding affected by the old formatting.
        # In this case, we must copy the bgcolor as well; in the other
        # branch this isn't necessary because paintBackground adds
        # padding anyway.
        line.formats[fi] = FormatCell(
          format: initFormat(lformat.bgcolor, defaultColor, {}),
          pos: cx
        )
      else:
        # First format < cx => split it up
        assert pos < cx
        inc fi # insert after first format
        line.insertFormat(cx, fi, initFormat(), nil)
  # Now for the text's formats:
  var format = format
  if fi == -1:
    # No formats => just insert a new format at 0
    inc fi
    line.insertFormat(x, fi, format, node)
  else:
    # First format's pos may be == x here.
    if line.formats[fi].pos == x:
      # Replace.
      # We must check if the old string's last x position is greater than
      # the new string's first x position. If not, we cannot inherit
      # its bgcolor (which is supposed to end before the new string started.)
      if nx > x:
        format.bgcolor = lformat.bgcolor
      line.formats[fi] = FormatCell(format: format, node: node, pos: x)
    else:
      # First format's pos < x => split it up.
      assert line.formats[fi].pos < x
      if nx > x: # see above
        format.bgcolor = lformat.bgcolor
      inc fi # insert after first format
      line.insertFormat(x, fi, format, node)
    if nx > x and nx < targetX and fi == line.formats.high:
      # The old format's background is bleeding into ours.  If this was
      # the last format, we must preserve it.
      inc fi
      format.bgcolor = defaultColor
      line.insertFormat(nx, fi, format, node)
  inc fi # skip last format
  while fi < line.formats.len and line.formats[fi].pos < targetX:
    # Other formats must be > x => replace them
    format.bgcolor = line.formats[fi].format.bgcolor
    let px = line.formats[fi].pos
    lformat = line.formats[fi].format # save for later use
    lnode = line.formats[fi].node
    line.formats[fi] = FormatCell(format: format, node: node, pos: px)
    inc fi
  if hadStr:
    # If nx > targetX, we are overwriting a double-width character; then
    # we want the next formatting to apply from the end of said character.
    let ostrx = max(nx, targetX)
    if fi >= line.formats.len or line.formats[fi].pos > ostrx:
      # targetX < ostr.width, but we have removed all formatting in the
      # range of our string, and no formatting comes directly after it. So
      # we insert the continuation of the last format we replaced after
      # our string.  (Default format when we haven't replaced anything.)
      line.insertFormat(ostrx, fi, lformat, lnode)
  else:
    if fi == line.formats.len:
      # We have skipped all formats.  There are two cases:
      # a) Our text overwrites the old text, but ends at the same x position
      # as the old text.  Then, the last format's background is correct,
      # nothing to do.
      # b) The old text is shorter than ours.  We must add a new format to
      # restore the background of the chunk that was not covered.
      if nx < targetX and format.bgcolor != defaultColor:
        format.bgcolor = defaultColor
        line.insertFormat(nx, fi, format, node)
  dec fi # go back to previous format, so that pos <= targetX
  assert line.formats[fi].pos <= targetX
  # That's it!

proc setText0(line: var FlexibleLine; s: openArray[char]; x, targetX: int;
    ocx, onx: var int; hadStr: var bool) =
  var i = 0
  let cx = line.findFirstX(x, i) # first x of new string (before padding)
  var j = i
  var nx = cx # last x of new string *before the end of the old string*
  # (nx starts from cx, not x; we are still advancing in the old string)
  while nx < targetX and j < line.str.len:
    nx += line.str.nextUTF8(j).width()
  let ostr = line.str.substr(j)
  ocx = cx
  onx = nx
  hadStr = ostr.len > 0
  line.setTextStr(s, ostr, i, x, cx, nx, targetX)

proc setText1(line: var FlexibleLine; s: openArray[char]; x, targetX: int;
    format: Format; node: Element) =
  assert x >= 0 and s.len != 0
  var cx: int
  var nx: int
  var hadStr: bool
  line.setText0(s, x, targetX, cx, nx, hadStr)
  line.setTextFormat(x, cx, targetX, nx, hadStr, format, node)

proc setText(grid: var FlexibleGrid; state: var RenderState; s: string;
    offset: Offset; format: Format; node: Element; clipBox: ClipBox) =
  if offset.y notin clipBox.start.y ..< clipBox.send.y:
    return
  if offset.x > clipBox.send.x:
    return
  let rx = offset.x div state.attrs.ppc
  var x = rx.toInt
  # Give room for rounding errors.
  let sx = max((clipBox.start.x div state.attrs.ppc).toInt, 0)
  var i = 0
  while x < sx and i < s.len:
    x += s.nextUTF8(i).width()
  if x < sx: # highest x is outside the clipping box, no need to draw
    return
  let diff = rx - x.toLUnit()
  let ppc2 = state.attrs.ppc div 2
  let ex = ((clipBox.send.x + ppc2 - diff) div state.attrs.ppc).toInt
  var j = i
  var targetX = x
  while targetX < ex and j < s.len:
    targetX += s.nextUTF8(j).width()
  if i < j:
    let y = (offset.y div state.attrs.ppl).toInt
    # make sure we have line y
    if grid.len < y + 1:
      grid.setLen(y + 1)
    grid[y].setText1(s.toOpenArray(i, j - 1), x, targetX, format, node)

proc clip(clipBox: ClipBox; state: RenderState; start, send: Offset):
    tuple[start, send: Offset] =
  var startx = start.x
  var starty = start.y
  var endx = send.x
  var endy = send.y
  if starty > endy:
    swap(starty, endy)
  if startx > endx:
    swap(startx, endx)
  return (
    offset(x = max(startx, clipBox.start.x), y = max(starty, clipBox.start.y)),
    offset(x = min(endx, clipBox.send.x), y = min(endy, clipBox.send.y))
  )

proc paintBackground(grid: var FlexibleGrid; state: var RenderState;
    color: CellColor; start, send: Offset; node: Element; alpha: uint8;
    clipBox: ClipBox) =
  let (start, send) = clipBox.clip(state, start, send)
  let startx = (start.x div state.attrs.ppc).toInt()
  let starty = (start.y div state.attrs.ppl).toInt()
  let endx = (send.x div state.attrs.ppc).toInt()
  let endy = (send.y div state.attrs.ppl).toInt()
  if starty >= endy or startx >= endx:
    return
  if grid.len < endy: # make sure we have line y - 1
    grid.setLen(endy)
  var format = initFormat(color, defaultColor, {})
  for line in grid.toOpenArray(starty, endy - 1).mitems:
    # Make sure line.width() >= endx
    var hadStr: bool
    var cx: int
    if alpha < 255:
      # If the background is not fully opaque, then text under it is
      # preserved.
      let w = line.str.width()
      for i in w ..< endx:
        line.str &= ' '
      cx = min(w, startx)
      hadStr = w > endx
    else:
      # Otherwise, background overpaints old text.
      let w = endx - startx
      while state.spaces.len < w:
        state.spaces &= ' '
      var nx: int
      line.setText0(state.spaces.toOpenArray(0, w - 1), startx, endx,
        cx, nx, hadStr)
    # Process formatting around startx
    var sfi = line.findFormatN(startx) - 1
    if sfi == -1:
      # No format <= startx
      line.insertFormat(startx, 0, initFormat(), nil)
      inc sfi
    elif line.formats[sfi].pos == startx:
      # Last format equals startx => next comes after, nothing to be done
      discard
    else:
      # Last format lower than startx => separate format from startx
      if cx < startx and sfi == line.formats.high:
        inc sfi
        line.insertFormat(cx, sfi, initFormat(), nil)
      var copy = line.formats[sfi]
      inc sfi
      copy.pos = startx
      line.insertFormat(sfi, copy)
    # Paint format backgrounds between startx and endx
    var lformat = initFormat()
    var lnode: Element = nil
    var ifi = 0
    for fi, it in line.formats.toOpenArray(sfi, line.formats.high).mpairs:
      if it.pos >= endx:
        break
      lformat = it.format
      lnode = it.node
      if alpha == 0:
        discard
      elif alpha == 255:
        it.format = format
      else:
        it.format.bgcolor = it.format.bgcolor.blend(color, alpha)
      it.node = node
      ifi = fi
    # Process formatting around endx
    let efi = line.findFormatN(endx, ifi) - 1
    if efi != -1 and line.formats[efi].pos < endx and hadStr:
      assert line.formats[efi].pos < endx
      line.insertFormat(endx, efi + 1, lformat, lnode)

proc paintInlineBox(grid: var FlexibleGrid; state: var RenderState;
    box: InlineBox; offset: Offset; bgcolor: CellColor; alpha: uint8) =
  for area in box.state.areas:
    let offset = offset + area.offset
    grid.paintBackground(state, bgcolor, offset, offset + area.size,
      box.element, alpha, box.render.clipBox)

proc renderInline(grid: var FlexibleGrid; state: var RenderState;
    ibox: InlineBox; offset: Offset; bgcolor0 = rgba(0, 0, 0, 0);
    pass2 = false) =
  let clipBox = if ibox.parent != nil:
    ibox.parent.render.clipBox
  else:
    DefaultClipBox
  ibox.render = BoxRenderState(
    offset: offset + ibox.state.startOffset,
    clipBox: clipBox,
    positioned: true
  )
  let bgcolor = ibox.computed{"background-color"}
  var bgcolor0 = bgcolor0
  if bgcolor.isCell:
    let bgcolor = bgcolor.cellColor()
    if bgcolor.t != ctNone:
      grid.paintInlineBox(state, ibox, offset, bgcolor, 255)
  else:
    bgcolor0 = bgcolor0.blend(bgcolor.argb)
    if bgcolor0.a > 0:
      grid.paintInlineBox(state, ibox, offset, bgcolor0.rgb.cellColor(),
        bgcolor0.a)
  if ibox of InlineTextBox:
    let ibox = InlineTextBox(ibox)
    if ibox.computed{"visibility"} != VisibilityVisible:
      return
    let format = ibox.computed.toFormat()
    for run in ibox.runs:
      let offset = offset + run.offset
      grid.setText(state, run.s, offset, format, ibox.element, clipBox)
  elif ibox of InlineImageBox:
    let ibox = InlineImageBox(ibox)
    if ibox.computed{"visibility"} != VisibilityVisible:
      return
    let offset = offset + ibox.imgstate.offset
    let p2 = offset + ibox.imgstate.size
    #TODO implement proper image clipping
    if offset.x < clipBox.send.x and offset.y < clipBox.send.y and
        p2.x >= clipBox.start.x and p2.y >= clipBox.start.y:
      # add Element to background (but don't actually color it)
      grid.paintBackground(state, defaultColor, offset, p2, ibox.element, 0,
        ibox.render.clipBox)
      let x = (offset.x div state.attrs.ppc).toInt
      let y = (offset.y div state.attrs.ppl).toInt
      let offx = (offset.x - x.toLUnit * state.attrs.ppc).toInt
      let offy = (offset.y - y.toLUnit * state.attrs.ppl).toInt
      state.images.add(PosBitmap(
        x: x,
        y: y,
        offx: offx,
        offy: offy,
        width: ibox.imgstate.size.w.toInt,
        height: ibox.imgstate.size.h.toInt,
        bmp: ibox.bmp
      ))
  else: # InlineNewLineBox does not have children, so we handle it here
    # only check position here to avoid skipping leaves that use our
    # computed values
    if ibox.positioned and not pass2:
      return
    for child in ibox.children:
      if child of InlineBox:
        grid.renderInline(state, InlineBox(child), offset, bgcolor0)
      else:
        grid.renderBlock(state, BlockBox(child), offset)

proc inheritClipBox(box: BlockBox; parent: CSSBox; state: RenderState) =
  if parent == nil:
    box.render.clipBox = DefaultClipBox
    return
  assert parent.render.positioned
  var clipBox = parent.render.clipBox
  let overflowX = box.computed{"overflow-x"}
  let overflowY = box.computed{"overflow-y"}
  if overflowX != OverflowVisible or overflowY != OverflowVisible:
    var offset = box.render.offset
    var size = box.state.size
    let topLeft = box.sizes.borderTopLeft(state.cellSize)
    offset -= topLeft
    size += topLeft
    size += box.sizes.borderBottomRight(state.cellSize)
    if overflowX in OverflowHiddenLike:
      clipBox.start.x = max(offset.x, clipBox.start.x)
      clipBox.send.x = min(offset.x + size.w, clipBox.send.x)
    else: # scroll like
      clipBox.start.x = max(min(offset.x, clipBox.start.x), 0)
      clipBox.send.x = max(offset.x + size.w, clipBox.send.x)
    if overflowY in OverflowHiddenLike:
      clipBox.start.y = max(offset.y, clipBox.start.y)
      clipBox.send.y = min(offset.y + size.h, clipBox.send.y)
  box.render.clipBox = clipBox

proc paintBorder(grid: var FlexibleGrid; state: var RenderState;
    start, send: Offset; box: BlockBox) =
  let start = start - state.cellSize
  let send = send + state.cellSize
  let startx = (start.x div state.attrs.ppc).toInt()
  let starty = (start.y div state.attrs.ppl).toInt()
  let endx = (send.x div state.attrs.ppc).toInt()
  var endy = (send.y div state.attrs.ppl).toInt()
  var buf = ""
  var top = box.sizes.border.top
  var bottom = box.sizes.border.bottom
  var left = box.sizes.border.left
  var right = box.sizes.border.right
  if top notin BorderStyleNoneHidden:
    var offset = start
    if left notin BorderStyleNoneHidden:
      if box.state.merge[dtHorizontal]:
        if box.state.merge[dtVertical]:
          buf &= top.borderChar(bdcSideBarCross)
        else:
          buf &= top.borderChar(bdcSideBarTop)
      else:
        if box.state.merge[dtVertical]:
          buf &= left.borderChar(bdcSideBarLeft)
        else:
          buf &= left.borderChar(bdcCornerTopLeft)
    else:
      offset.x += state.attrs.ppc
    for i in startx + 1 ..< endx - 1:
      buf &= top.borderChar(bdcHorizontalBarTop)
    if right notin BorderStyleNoneHidden:
      if box.state.merge[dtVertical]:
        buf &= right.borderChar(bdcSideBarRight)
      else:
        buf &= top.borderChar(bdcCornerTopRight)
    let fgcolor = box.computed{"border-top-color"}.cellColor()
    let format = initFormat(defaultColor, fgcolor, {})
    grid.setText(state, buf, offset, format, box.element, box.render.clipBox)
    buf.setLen(0)
  let hasLeft = left notin BorderStyleNoneHidden
  let hasRight = right notin BorderStyleNoneHidden
  if hasLeft or hasRight:
    buf &= left.borderChar(bdcVerticalBarLeft)
    let rbuf = right.borderChar(bdcVerticalBarRight)
    var soff = start
    var eoff = send
    eoff.x -= state.cellSize.w
    let fgcolorLeft = box.computed{"border-left-color"}.cellColor()
    let formatLeft = initFormat(defaultColor, fgcolorLeft, {})
    let fgcolorRight = box.computed{"border-left-color"}.cellColor()
    let formatRight = initFormat(defaultColor, fgcolorRight, {})
    for y in starty + 1 ..< endy - 1:
      let sy = (y * state.attrs.ppl).toLUnit()
      if hasLeft:
        soff.y = sy
        grid.setText(state, buf, soff, formatLeft, nil, box.render.clipBox)
      if hasRight:
        eoff.y = sy
        grid.setText(state, rbuf, eoff, formatRight, nil, box.render.clipBox)
    buf.setLen(0)
  if bottom notin BorderStyleNoneHidden:
    let proprietary = bottom in {BorderStyleBracket, BorderStyleParen}
    var offset = offset(x = start.x, y = send.y - state.attrs.ppl)
    if left notin BorderStyleNoneHidden and not proprietary:
      if box.state.merge[dtHorizontal]:
        buf &= bottom.borderChar(bdcSideBarBottom)
      else:
        buf &= bottom.borderChar(bdcCornerBottomLeft)
    else:
      offset.x += state.attrs.ppc
    for i in startx + 1 ..< endx - 1:
      buf &= bottom.borderChar(bdcHorizontalBarBottom)
    if right notin BorderStyleNoneHidden and not proprietary:
      buf &= bottom.borderChar(bdcCornerBottomRight)
    var flags: set[FormatFlag] = {}
    if proprietary:
      offset.y -= state.attrs.ppl
      flags.incl(ffUnderline)
    let fgcolor = box.computed{"border-bottom-color"}.cellColor()
    let format = initFormat(defaultColor, fgcolor, flags)
    grid.setText(state, buf, offset, format, box.element, box.render.clipBox)

proc renderBlock(grid: var FlexibleGrid; state: var RenderState;
    box: BlockBox; offset: Offset; pass2 = false) =
  if box.positioned and not pass2:
    return
  let offset = offset + box.state.offset
  if not pass2:
    box.render.offset = offset
    box.render.positioned = true
    box.inheritClipBox(box.parent, state)
  let opacity = box.computed{"opacity"}
  if box.computed{"visibility"} == VisibilityVisible and opacity != 0:
    #TODO maybe blend with the terminal background?
    let bgcolor0 = box.computed{"background-color"}
    let bgcolor = bgcolor0.cellColor()
    let endOffset = offset + box.state.size
    if bgcolor != defaultColor:
      if box.computed{"-cha-bgcolor-is-canvas"} and
          state.bgcolor == defaultColor:
        #TODO bgimage
        # note: this eats the alpha
        state.bgcolor = bgcolor
      else:
        grid.paintBackground(state, bgcolor, offset, endOffset, box.element,
          bgcolor0.a, box.render.clipBox)
    grid.paintBorder(state, offset, endOffset, box)
    if box.computed{"background-image"} != nil:
      # ugly hack for background-image display... TODO actually display images
      const s = "[img]"
      let w = s.len * state.attrs.ppc
      var offset = offset
      if box.state.size.w < w:
        # text is larger than image; center it to minimize error
        offset.x -= w div 2
        offset.x += box.state.size.w div 2
      grid.setText(state, s, offset, box.computed.toFormat(), box.element,
        box.render.clipBox)
  if opacity != 0: #TODO this isn't right...
    if box.render.clipBox.start < box.render.clipBox.send:
      for child in box.children:
        if child of InlineBox:
          grid.renderInline(state, InlineBox(child), offset)
        else:
          grid.renderBlock(state, BlockBox(child), offset)

# This function exists to support another insane CSS construct: negative
# z-index.
# The issue here is that their position depends on their parent, but the
# parent box is very often not positioned yet.  So we brute-force our
# way out of the problem by resolving the parent box's position here.
# The algorithm itself is mildly confusing because we must skip
# InlineBox offsets in the process - this means that there may be inline
# boxes after this pass with an unresolved position which contain block
# boxes with a resolved position.
proc resolveBlockOffset(box: CSSBox; state: RenderState): Offset =
  var dims: set[DimensionType] = {}
  let absolute = box.positioned and box.computed{"position"} == PositionAbsolute
  let absoluteOrFixed = box.positioned and
    box.computed{"position"} in PositionAbsoluteFixed
  if absoluteOrFixed:
    if not box.computed{"left"}.auto or not box.computed{"right"}.auto:
      dims.incl(dtHorizontal)
    if not box.computed{"top"}.auto or not box.computed{"bottom"}.auto:
      dims.incl(dtVertical)
  var it {.cursor.} = box.parent
  while it != nil:
    if it of BlockBox:
      break
    it = it.parent
  var toPosition: seq[BlockBox] = @[]
  var it2 {.cursor.} = it
  var parent {.cursor.}: CSSBox = nil
  var abs {.cursor.}: CSSBox = nil
  while it2 != nil:
    if absolute and it2.positioned and abs == nil:
      abs = it2 # record first absolute ancestor
    if it2.render.positioned and (not absoluteOrFixed or abs != nil):
      break
    if it2 of BlockBox:
      toPosition.add(BlockBox(it2))
    it2 = it2.parent
  var offset = if it2 != nil: it2.render.offset else: offset(0, 0)
  for it in toPosition.ritems:
    offset += it.state.offset
    it.render = BoxRenderState(
      offset: offset,
      clipBox: DefaultClipBox,
      positioned: true
    )
    it.inheritClipBox(parent, state)
    parent = it
  let absOffset = if abs != nil: abs.render.offset else: offset(0, 0)
  for dim in DimensionType:
    if dim in dims:
      offset[dim] = absOffset[dim]
  if box of BlockBox:
    let box = BlockBox(box)
    box.render = BoxRenderState(
      positioned: true,
      offset: offset + box.state.offset,
      clipBox: DefaultClipBox
    )
    box.inheritClipBox(if absoluteOrFixed: it2 else: it, state)
  return offset

proc renderPositioned(grid: var FlexibleGrid; state: var RenderState;
    box: CSSBox) =
  let offset = box.resolveBlockOffset(state)
  if box of BlockBox:
    grid.renderBlock(state, BlockBox(box), offset, pass2 = true)
  else:
    grid.renderInline(state, InlineBox(box), offset, pass2 = true)

proc renderStack(grid: var FlexibleGrid; state: var RenderState;
    stack: StackItem) =
  var i = 0
  # negative z-index
  while i < stack.children.len:
    let it = stack.children[i]
    if it.index >= 0:
      break
    grid.renderStack(state, it)
    inc i
  grid.renderPositioned(state, stack.box)
  # z-index >= 0
  for it in stack.children.toOpenArray(i, stack.children.high):
    grid.renderStack(state, it)

proc render*(grid: var FlexibleGrid; bgcolor: var CellColor; stack: StackItem;
    attrsp: ptr WindowAttributes; images: var seq[PosBitmap]) =
  grid.setLen(0)
  var state = RenderState(
    attrsp: attrsp,
    bgcolor: defaultColor,
    cellSize: size(w = attrsp.ppc, h = attrsp.ppl),
  )
  grid.renderStack(state, stack)
  bgcolor = state.bgcolor
  images = move(state.images)

{.pop.} # raises: []
