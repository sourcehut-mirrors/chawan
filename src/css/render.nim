import std/algorithm

import css/box
import css/cssvalues
import css/lunit
import css/stylednode
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
    node*: StyledNode

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

  ClipBox = object
    start: Offset
    send: Offset

  StackItem = ref object
    box: BlockBox
    offset: Offset
    apos: Offset
    clipBox: ClipBox
    index: int

  RenderState = object
    # Position of the absolute positioning containing block:
    # https://drafts.csswg.org/css-position/#absolute-positioning-containing-block
    absolutePos: seq[Offset]
    clipBoxes: seq[ClipBox]
    bgcolor: CellColor
    attrsp: ptr WindowAttributes
    images: seq[PosBitmap]
    nstack: seq[StackItem]

template attrs(state: RenderState): WindowAttributes =
  state.attrsp[]

template clipBox(state: RenderState): ClipBox =
  state.clipBoxes[^1]

func findFormatN*(line: FlexibleLine; pos: int): int =
  var i = 0
  while i < line.formats.len:
    if line.formats[i].pos > pos:
      break
    inc i
  return i

proc addLines(grid: var FlexibleGrid; n: int) =
  grid.setLen(grid.len + n)

proc insertFormat(line: var FlexibleLine; i: int; cell: FormatCell) =
  line.formats.insert(cell, i)

proc insertFormat(line: var FlexibleLine; pos, i: int; format: Format;
    node: StyledNode = nil) =
  line.insertFormat(i, FormatCell(format: format, node: node, pos: pos))

proc addFormat(line: var FlexibleLine; pos: int; format: Format;
    node: StyledNode = nil) =
  line.formats.add(FormatCell(format: format, node: node, pos: pos))

func toFormat(computed: CSSValues): Format =
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
  return Format(
    #TODO this ignores alpha; we should blend somewhere.
    fgcolor: computed{"color"}.cellColor(),
    flags: flags
  )

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

proc setTextFormat(line: var FlexibleLine; x, cx, nx: int; ostr: string;
    format: Format; node: StyledNode) =
  var fi = line.findFormatN(cx) - 1 # Skip unchanged formats before new string
  if x > cx:
    # Replace formats for padding
    var padformat = Format()
    if fi == -1:
      # No formats
      inc fi # insert after first format (meaning fi = 0)
      line.insertFormat(cx, fi, padformat)
    else:
      # First format's pos may be == cx here.
      if line.formats[fi].pos == cx:
        padformat.bgcolor = line.formats[fi].format.bgcolor
        let node = line.formats[fi].node
        line.formats.delete(fi)
        line.insertFormat(cx, fi, padformat, node)
      else:
        # First format < cx => split it up
        assert line.formats[fi].pos < cx
        padformat.bgcolor = line.formats[fi].format.bgcolor
        let node = line.formats[fi].node
        inc fi # insert after first format
        line.insertFormat(cx, fi, padformat, node)
    inc fi # skip last format
    while fi < line.formats.len and line.formats[fi].pos < x:
      # Other formats must be > cx => replace them
      padformat.bgcolor = line.formats[fi].format.bgcolor
      let node = line.formats[fi].node
      let px = line.formats[fi].pos
      line.formats.delete(fi)
      line.insertFormat(px, fi, padformat, node)
      inc fi
    dec fi # go back to previous format, so that pos <= x
    assert line.formats[fi].pos <= x
  # Now for the text's formats:
  var format = format
  var lformat: Format
  var lnode: StyledNode
  if fi == -1:
    # No formats => just insert a new format at 0
    inc fi
    line.insertFormat(x, fi, format, node)
    lformat = Format()
  else:
    # First format's pos may be == x here.
    lformat = line.formats[fi].format # save for later use
    lnode = line.formats[fi].node
    if line.formats[fi].pos == x:
      # Replace.
      # We must check if the old string's last x position is greater than
      # the new string's first x position. If not, we cannot inherit
      # its bgcolor (which is supposed to end before the new string started.)
      if nx > cx:
        format.bgcolor = line.formats[fi].format.bgcolor
      line.formats.delete(fi)
      line.insertFormat(x, fi, format, node)
    else:
      # First format's pos < x => split it up.
      assert line.formats[fi].pos < x
      if nx > cx: # see above
        format.bgcolor = line.formats[fi].format.bgcolor
      inc fi # insert after first format
      line.insertFormat(x, fi, format, node)
  inc fi # skip last format
  while fi < line.formats.len and line.formats[fi].pos < nx:
    # Other formats must be > x => replace them
    format.bgcolor = line.formats[fi].format.bgcolor
    let px = line.formats[fi].pos
    lformat = line.formats[fi].format # save for later use
    lnode = line.formats[fi].node
    line.formats.delete(fi)
    line.insertFormat(px, fi, format, node)
    inc fi
  if ostr.len > 0 and (fi >= line.formats.len or line.formats[fi].pos > nx):
    # nx < ostr.width, but we have removed all formatting in the range of our
    # string, and no formatting comes directly after it. So we insert the
    # continuation of the last format we replaced after our string.
    # (Default format when we haven't replaced anything.)
    line.insertFormat(nx, fi, lformat, lnode)
  dec fi # go back to previous format, so that pos <= nx
  assert line.formats[fi].pos <= nx
  # That's it!

proc setText0(line: var FlexibleLine; s: openArray[char]; x, targetX: int;
    format: Format; node: StyledNode) =
  assert x >= 0 and s.len != 0
  var i = 0
  let cx = line.findFirstX(x, i) # first x of new string (before padding)
  var j = i
  var nx = x # last x of new string
  while nx < targetX and j < line.str.len:
    nx += line.str.nextUTF8(j).width()
  let ostr = line.str.substr(j)
  line.setTextStr(s, ostr, i, x, cx, nx, targetX)
  line.setTextFormat(x, cx, nx, ostr, format, node)

proc setText(grid: var FlexibleGrid; state: var RenderState; s: string;
    offset: Offset; format: Format; node: StyledNode) =
  if offset.y notin state.clipBox.start.y ..< state.clipBox.send.y:
    return
  if offset.x > state.clipBox.send.x:
    return
  var x = (offset.x div state.attrs.ppc).toInt
  # Give room for rounding errors.
  #TODO I'm sure there is a better way to do this, but this seems OK for now.
  let sx = max((state.clipBox.start.x - state.attrs.ppc) div state.attrs.ppc, 0)
  var i = 0
  while x < sx and i < s.len:
    x += s.nextUTF8(i).width()
  if x < sx: # highest x is outside the clipping box, no need to draw
    return
  #TODO starting to think lunit should just clamp on overflow
  var ex = int.high
  if state.clipBox.send.x < LayoutUnit.high - state.attrs.ppc:
    let tmp = (state.clipBox.send.x + state.attrs.ppc) div state.attrs.ppc
    ex = tmp.toInt
  var j = i
  var targetX = x
  while targetX < ex and j < s.len:
    targetX += s.nextUTF8(j).width()
  if i < j:
    let y = (offset.y div state.attrs.ppl).toInt
    # make sure we have line y
    if grid.high < y:
      grid.addLines(y - grid.high)
    grid[y].setText0(s.toOpenArray(i, j - 1), x, targetX, format, node)

proc paintBackground(grid: var FlexibleGrid; state: var RenderState;
    color: CellColor; startx, starty, endx, endy: int; node: StyledNode;
    noPaint = false) =
  let clipBox = addr state.clipBox
  var startx = startx
  var starty = starty
  var endx = endx
  var endy = endy
  if starty > endy:
    swap(starty, endy)
  if startx > endx:
    swap(startx, endx)
  starty = max(starty, clipBox.start.y.toInt) div state.attrs.ppl
  endy = min(endy, clipBox.send.y.toInt) div state.attrs.ppl
  startx = max(startx, clipBox.start.x.toInt) div state.attrs.ppc
  endx = min(endx, clipBox.send.x.toInt) div state.attrs.ppc
  if starty >= endy or startx >= endx:
    return
  if grid.high < endy: # make sure we have line y
    grid.addLines(endy - grid.high)
  for y in starty ..< endy:
    # Make sure line.width() >= endx
    for i in grid[y].str.width() ..< endx:
      grid[y].str &= ' '
    # Process formatting around startx
    if grid[y].formats.len == 0:
      # No formats
      grid[y].addFormat(startx, Format())
    else:
      let fi = grid[y].findFormatN(startx) - 1
      if fi == -1:
        # No format <= startx
        grid[y].insertFormat(startx, 0, Format())
      elif grid[y].formats[fi].pos == startx:
        # Last format equals startx => next comes after, nothing to be done
        discard
      else:
        # Last format lower than startx => separate format from startx
        let copy = grid[y].formats[fi]
        grid[y].formats[fi].pos = startx
        grid[y].insertFormat(fi, copy)
    # Process formatting around endx
    assert grid[y].formats.len > 0
    let fi = grid[y].findFormatN(endx) - 1
    if fi == -1:
      # Last format > endx -> nothing to be done
      discard
    elif grid[y].formats[fi].pos != endx:
      let copy = grid[y].formats[fi]
      grid[y].formats[fi].pos = endx
      grid[y].insertFormat(fi, copy)
    # Paint format backgrounds between startx and endx
    for fi in 0 ..< grid[y].formats.len:
      if grid[y].formats[fi].pos >= endx:
        break
      if grid[y].formats[fi].pos >= startx:
        if not noPaint:
          grid[y].formats[fi].format.bgcolor = color
        grid[y].formats[fi].node = node

proc renderBlockBox(grid: var FlexibleGrid; state: var RenderState;
  box: BlockBox; offset: Offset; pass2 = false)

proc paintInlineBox(grid: var FlexibleGrid; state: var RenderState;
    box: InlineBox; offset: Offset; bgcolor: CellColor) =
  for area in box.state.areas:
    let x1 = toInt(offset.x + area.offset.x)
    let y1 = toInt(offset.y + area.offset.y)
    let x2 = toInt(offset.x + area.offset.x + area.size.w)
    let y2 = toInt(offset.y + area.offset.y + area.size.h)
    grid.paintBackground(state, bgcolor, x1, y1, x2, y2, box.node)

proc renderInlineBox(grid: var FlexibleGrid; state: var RenderState;
    box: InlineBox; offset: Offset; bgcolor0: ARGBColor;
    pass2 = false) =
  let position = box.computed{"position"}
  #TODO stacking contexts
  let bgcolor = box.computed{"background-color"}
  var bgcolor0 = bgcolor0
  if bgcolor.isCell:
    let bgcolor = bgcolor.cellColor()
    if bgcolor.t != ctNone:
      grid.paintInlineBox(state, box, offset, bgcolor)
  else:
    bgcolor0 = bgcolor0.blend(bgcolor.argb)
    if bgcolor0.a > 0:
      grid.paintInlineBox(state, box, offset,
        bgcolor0.rgb.cellColor())
  let startOffset = offset + box.state.startOffset
  box.render.offset = startOffset
  if position notin PositionStaticLike and stSplitStart in box.splitType:
    state.absolutePos.add(startOffset)
  if box.t == ibtParent:
    for child in box.children:
      grid.renderInlineBox(state, child, offset, bgcolor0)
  else:
    let format = box.computed.toFormat()
    for atom in box.state.atoms:
      let offset = offset + atom.offset
      case atom.t
      of iatInlineBlock:
        grid.renderBlockBox(state, atom.innerbox, offset)
      of iatWord:
        if box.computed{"visibility"} == VisibilityVisible:
          grid.setText(state, atom.str, offset, format, box.node)
      of iatImage:
        if box.computed{"visibility"} == VisibilityVisible:
          let x2p = offset.x + atom.size.w
          let y2p = offset.y + atom.size.h
          let clipBox = addr state.clipBoxes[^1]
          #TODO implement proper image clipping
          if offset.x < clipBox.send.x and offset.y < clipBox.send.y and
              x2p >= clipBox.start.x and y2p >= clipBox.start.y:
            let x1 = offset.x.toInt
            let y1 = offset.y.toInt
            let x2 = x2p.toInt
            let y2 = y2p.toInt
            # add StyledNode to background (but don't actually color it)
            grid.paintBackground(state, defaultColor, x1, y1, x2, y2,
              box.node, noPaint = true)
            let x = (offset.x div state.attrs.ppc).toInt
            let y = (offset.y div state.attrs.ppl).toInt
            let offx = (offset.x - x.toLayoutUnit * state.attrs.ppc).toInt
            let offy = (offset.y - y.toLayoutUnit * state.attrs.ppl).toInt
            state.images.add(PosBitmap(
              x: x,
              y: y,
              offx: offx,
              offy: offy,
              width: atom.size.w.toInt,
              height: atom.size.h.toInt,
              bmp: atom.bmp
            ))
  if position notin PositionStaticLike and stSplitEnd in box.splitType:
    discard state.absolutePos.pop()

proc renderBlockBox(grid: var FlexibleGrid; state: var RenderState;
    box: BlockBox; offset: Offset; pass2 = false) =
  let position = box.computed{"position"}
  #TODO handle negative z-index
  let zindex = box.computed{"z-index"}
  if position notin PositionStaticLike and not pass2 and zindex >= 0:
    state.nstack.add(StackItem(
      box: box,
      offset: offset,
      apos: state.absolutePos[^1],
      clipBox: state.clipBox,
      index: zindex
    ))
    return
  var offset = offset
  if position in {PositionAbsolute, PositionFixed}:
    if box.computed{"left"}.u != clAuto or box.computed{"right"}.u != clAuto:
      offset.x = state.absolutePos[^1].x
    if box.computed{"top"}.u != clAuto or box.computed{"bottom"}.u != clAuto:
      offset.y = state.absolutePos[^1].y
  offset += box.state.offset
  box.render.offset = offset
  if position notin PositionStaticLike:
    state.absolutePos.add(offset)
  let overflowX = box.computed{"overflow-x"}
  let overflowY = box.computed{"overflow-y"}
  let hasClipBox = overflowX != OverflowVisible or overflowY != OverflowVisible
  if hasClipBox:
    var clipBox = state.clipBox
    if overflowX in OverflowHiddenLike:
      clipBox.start.x = max(offset.x, clipBox.start.x)
      clipBox.send.x = min(offset.x + box.state.size.w, clipBox.send.x)
    else: # scroll like
      clipBox.start.x = min(offset.x, clipBox.start.x)
      clipBox.send.x = max(offset.x + box.state.size.w, clipBox.start.x)
    if overflowY in OverflowHiddenLike:
      clipBox.start.y = max(offset.y, clipBox.start.y)
      clipBox.send.y = min(offset.y + box.state.size.h, clipBox.send.y)
    state.clipBoxes.add(clipBox)
  if box.computed{"visibility"} == VisibilityVisible:
    #TODO maybe blend with the terminal background?
    let bgcolor = box.computed{"background-color"}.cellColor()
    if bgcolor != defaultColor:
      if box.computed{"-cha-bgcolor-is-canvas"} and
          state.bgcolor == defaultColor:
        #TODO bgimage
        # note: this eats the alpha
        state.bgcolor = bgcolor
      let ix = toInt(offset.x)
      let iy = toInt(offset.y)
      let e = offset + box.state.size
      let iex = toInt(e.x)
      let iey = toInt(e.y)
      grid.paintBackground(state, bgcolor, ix, iy, iex, iey, box.node)
    if box.computed{"background-image"}.t == ContentImage:
      # ugly hack for background-image display... TODO actually display images
      const s = "[img]"
      let w = s.len * state.attrs.ppc
      var offset = offset
      if box.state.size.w < w:
        # text is larger than image; center it to minimize error
        offset.x -= w div 2
        offset.x += box.state.size.w div 2
      grid.setText(state, s, offset, box.computed.toFormat(), box.node)
  if box.inline != nil:
    assert box.children.len == 0
    if box.computed{"visibility"} == VisibilityVisible and
        state.clipBox.start.x < state.clipBox.send.x and
        state.clipBox.start.y < state.clipBox.send.y:
      grid.renderInlineBox(state, box.inline, offset, rgba(0, 0, 0, 0))
  else:
    for child in box.children:
      grid.renderBlockBox(state, child, offset)
  if hasClipBox:
    discard state.clipBoxes.pop()
  if position notin PositionStaticLike:
    discard state.absolutePos.pop()

proc renderDocument*(grid: var FlexibleGrid; bgcolor: var CellColor;
    rootBox: BlockBox; attrsp: ptr WindowAttributes;
    images: var seq[PosBitmap]) =
  grid.setLen(0)
  if rootBox == nil:
    # no HTML element when we run cascade; just clear all lines.
    return
  var state = RenderState(
    absolutePos: @[offset(0, 0)],
    clipBoxes: @[ClipBox(send: offset(LayoutUnit.high, LayoutUnit.high))],
    attrsp: attrsp,
    bgcolor: defaultColor
  )
  var stack = @[StackItem(box: rootBox, clipBox: state.clipBox)]
  while stack.len > 0:
    for it in stack:
      state.absolutePos.add(it.apos)
      state.clipBoxes.add(it.clipBox)
      grid.renderBlockBox(state, it.box, it.offset, true)
      discard state.clipBoxes.pop()
      discard state.absolutePos.pop()
    stack = move(state.nstack)
    stack.sort(proc(x, y: StackItem): int = cmp(x.index, y.index))
    state.nstack = @[]
  if grid.len == 0:
    grid.addLines(1)
  bgcolor = state.bgcolor
  images = state.images
