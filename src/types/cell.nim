import types/color
import utils/strwidth

type
  FormatFlag* = enum
    ffBold = "bold"
    ffItalic = "italic"
    ffUnderline = "underline"
    ffReverse = "reverse"
    ffStrike = "strike"
    ffOverline = "overline"
    ffBlink = "blink"

  Format* = object
    fgcolor*: CellColor
    bgcolor*: CellColor
    flags*: set[FormatFlag]

  SimpleFormatCell* = object
    format*: Format
    pos*: int

  SimpleFlexibleLine* = object
    str*: string
    formats*: seq[SimpleFormatCell]

  SimpleFlexibleGrid* = seq[SimpleFlexibleLine]

  FixedCell* = object
    str*: string
    format*: Format

  FixedGrid* = object
    width*, height*: int
    cells*: seq[FixedCell]

proc `[]=`*(grid: var FixedGrid; i: int; cell: FixedCell) = grid.cells[i] = cell
proc `[]=`*(grid: var FixedGrid; i: BackwardsIndex; cell: FixedCell) =
  grid.cells[i] = cell
proc `[]`*(grid: var FixedGrid; i: int): var FixedCell = grid.cells[i]
proc `[]`*(grid: var FixedGrid; i: BackwardsIndex): var FixedCell =
  grid.cells[i]
proc `[]`*(grid: FixedGrid; i: int): lent FixedCell = grid.cells[i]
proc `[]`*(grid: FixedGrid; i: BackwardsIndex): lent FixedCell =
  return grid.cells[grid.cells.len - int(i)]

proc len*(grid: FixedGrid): int = grid.cells.len
proc high*(grid: FixedGrid): int = grid.cells.high

iterator items*(grid: FixedGrid): lent FixedCell {.inline.} =
  for cell in grid.cells:
    yield cell

func newFixedGrid*(w: int; h: int = 1): FixedGrid =
  return FixedGrid(width: w, height: h, cells: newSeq[FixedCell](w * h))

func width*(cell: FixedCell): int =
  return cell.str.width()

# Get the first format cell after pos, if any.
func findFormatN*(line: SimpleFlexibleLine; pos: int): int =
  var i = 0
  while i < line.formats.len:
    if line.formats[i].pos > pos:
      break
    inc i
  return i

func findFormat*(line: SimpleFlexibleLine; pos: int): SimpleFormatCell =
  let i = line.findFormatN(pos) - 1
  if i != -1:
    return line.formats[i]
  return SimpleFormatCell(pos: -1)

func findNextFormat*(line: SimpleFlexibleLine; pos: int): SimpleFormatCell =
  let i = line.findFormatN(pos)
  if i < line.formats.len:
    return line.formats[i]
  return SimpleFormatCell(pos: -1)
