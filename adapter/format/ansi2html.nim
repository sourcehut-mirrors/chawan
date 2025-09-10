{.push raises: [].}

import std/os
import std/posix

import io/chafile
import io/dynstream
import types/color
import types/opt
import utils/twtstr

type
  FormatFlag = enum
    ffBold = "bold"
    ffItalic = "italic"
    ffUnderline = "underline"
    ffReverse = "-cha-reverse"
    ffStrike = "line-through"
    ffOverline = "overline"
    ffBlink = "blink"

  Format = object
    fgcolor: CellColor
    bgcolor: CellColor
    flags: set[FormatFlag]

# https://www.ecma-international.org/wp-content/uploads/ECMA-48_5th_edition_june_1991.pdf
type
  AnsiCodeParseState = enum
    acpsDone, acpsStart, acpsParams, acpsInterm, acpsFinal, acpsBackspace,
    acpsInBackspaceTransition, acpsInBackspace, acpsOSC, acpsOSCEsc

  AnsiCodeParser = object
    state: AnsiCodeParseState
    params: string

proc getParam(parser: AnsiCodeParser; i: var int; colon = false): string =
  result = ""
  while i < parser.params.len and
      not (parser.params[i] == ';' or colon and parser.params[i] == ':'):
    result &= parser.params[i]
    inc i
  if i < parser.params.len:
    inc i

proc getParamU8(parser: AnsiCodeParser; i: var int; colon = false): Opt[uint8] =
  if i >= parser.params.len:
    return err()
  parseUInt8(parser.getParam(i), allowSign = false)

proc setColor(format: var Format; c: CellColor; isfg: bool) =
  if isfg:
    format.fgcolor = c
  else:
    format.bgcolor = c

proc parseSGRDefColor(parser: AnsiCodeParser; format: var Format;
    i: var int; isfg: bool): Opt[void] =
  let u = ?parser.getParamU8(i, colon = true)
  if u == 2:
    let param0 = ?parser.getParamU8(i, colon = true)
    if i < parser.params.len:
      let r = param0
      let g = ?parser.getParamU8(i, colon = true)
      let b = ?parser.getParamU8(i, colon = true)
      format.setColor(cellColor(rgb(r, g, b)), isfg)
    else:
      format.setColor(cellColor(gray(param0)), isfg)
  elif u == 5:
    let param0 = ?parser.getParamU8(i, colon = true)
    format.setColor(ANSIColor(param0).cellColor(), isfg)
  else:
    return err()
  ok()

proc parseSGRColor(parser: AnsiCodeParser; format: var Format;
    i: var int; u: uint8): Opt[void] =
  if u in 30u8..37u8:
    format.fgcolor = cellColor(ANSIColor(u - 30))
  elif u == 38:
    return parser.parseSGRDefColor(format, i, isfg = true)
  elif u == 39:
    format.fgcolor = defaultColor
  elif u in 40u8..47u8:
    format.bgcolor = cellColor(ANSIColor(u - 40))
  elif u == 48:
    return parser.parseSGRDefColor(format, i, isfg = false)
  elif u == 49:
    format.bgcolor = defaultColor
  elif u in 90u8..97u8:
    format.fgcolor = cellColor(ANSIColor(u - 82))
  elif u in 100u8..107u8:
    format.bgcolor = cellColor(ANSIColor(u - 92))
  else:
    return err()
  ok()

const FormatCodes: array[FormatFlag, tuple[s, e: uint8]] = [
  ffBold: (1u8, 22u8),
  ffItalic: (3u8, 23u8),
  ffUnderline: (4u8, 24u8),
  ffReverse: (7u8, 27u8),
  ffStrike: (9u8, 29u8),
  ffOverline: (53u8, 55u8),
  ffBlink: (5u8, 25u8),
]

proc parseSGRAspect(parser: AnsiCodeParser; format: var Format;
    i: var int): Opt[void] =
  let u = ?parser.getParamU8(i)
  for flag, (s, e) in FormatCodes:
    if u == s:
      format.flags.incl(flag)
      return ok()
    if u == e:
      format.flags.excl(flag)
      return ok()
  if u == 0:
    format = Format()
    return ok()
  else:
    return parser.parseSGRColor(format, i, u)

proc parseSGR(parser: AnsiCodeParser; format: var Format) =
  if parser.params.len == 0:
    format = Format()
  else:
    var i = 0
    while i < parser.params.len:
      if parser.parseSGRAspect(format, i).isErr:
        break

proc parseControlFunction(parser: var AnsiCodeParser; format: var Format;
    f: char) =
  if f == 'm':
    parser.parseSGR(format)
  else:
    discard # unknown

proc reset(parser: var AnsiCodeParser) =
  parser.state = acpsStart
  parser.params = ""

type State = object
  outbufIdx: int
  outbuf: array[4096, char]
  parser: AnsiCodeParser
  currentFmt: Format
  pendingFmt: Format
  tmpFlags: set[FormatFlag]
  af: bool
  spanOpen: bool
  hasPrintingBuf: bool
  backspaceDecay: int

proc flushOutbuf(state: var State) =
  if state.outbufIdx > 0:
    discard write(STDOUT_FILENO, addr state.outbuf[0], state.outbufIdx)
    state.outbufIdx = 0

proc putc(state: var State; c: char) {.inline.} =
  if state.outbufIdx + 4 >= state.outbuf.len: # max utf-8 char length
    state.flushOutbuf()
  state.outbuf[state.outbufIdx] = c
  inc state.outbufIdx

proc puts(state: var State; s: openArray[char]) {.inline.} =
  #TODO this is slower than it should be
  for c in s:
    state.putc(c)

proc flushFmt(state: var State) =
  if state.pendingFmt != state.currentFmt:
    if state.spanOpen:
      state.puts("</span>")
    if state.pendingFmt == Format():
      state.currentFmt = state.pendingFmt
      state.spanOpen = false
      return
    state.spanOpen = true
    state.puts("<span style='")
    let fmt = state.pendingFmt
    var buf = ""
    if fmt.fgcolor.t != ctNone:
      buf &= "color:"
      case fmt.fgcolor.t
      of ctNone: discard
      of ctANSI: buf &= "-cha-ansi(" & $uint8(fmt.fgcolor.ansi) & ")"
      of ctRGB: buf &= $fmt.fgcolor.rgb.argb
      buf &= ";"
    if fmt.bgcolor.t != ctNone:
      buf &= "background-color:"
      case fmt.bgcolor.t
      of ctNone: discard
      of ctANSI: buf &= "-cha-ansi(" & $uint8(fmt.bgcolor.ansi) & ")"
      of ctRGB: buf &= $fmt.bgcolor.rgb.argb
      buf &= ";"
    const Decoration = {ffOverline, ffUnderline, ffStrike, ffBlink, ffReverse}
    if Decoration * fmt.flags != {}:
      buf &= "text-decoration:"
      for flag in [ffOverline, ffUnderline, ffStrike, ffBlink, ffReverse]:
        if flag in fmt.flags:
          buf &= $flag & ' '
      if buf[^1] != ' ':
        buf.setLen(buf.high)
      buf &= ";"
    if ffBold in fmt.flags:
      buf &= "font-weight:bold;"
    if ffItalic in fmt.flags:
      buf &= "font-style:italic;"
    if buf.len > 0 and buf[^1] == ';':
      buf.setLen(buf.high)
    buf &= "'>"
    state.puts(buf)
    state.currentFmt = fmt
    state.hasPrintingBuf = false

proc parseOSC(state: var State) =
  let p1 = state.parser.params.until(';')
  let n = parseIntP(p1).get(-1)
  if n == 8: # hyperlink
    let p2start = p1.len + 1
    let id = state.parser.params.until(';', p2start)
    let url = state.parser.params.until(';', p2start + id.len + 1)
    # This isn't valid HTML, but the parser can deal with it.
    state.puts("</a>")
    if url != "":
      state.puts("<a href='" & url.htmlEscape() & "'>")

type ParseAnsiCodeResult = enum
  pacrProcess, pacrSkip

proc parseAnsiCode(state: var State; format: var Format; c: char):
    ParseAnsiCodeResult =
  case state.parser.state
  of acpsStart:
    if 0x40 <= int(c) and int(c) <= 0x5F:
      case c
      of '[':
        state.parser.state = acpsParams
      of ']':
        state.parser.state = acpsOSC
      else:
        #C1, TODO?
        state.parser.state = acpsDone
    else:
      state.parser.state = acpsDone
      return pacrProcess
  of acpsParams:
    if c in '0' .. '?':
      state.parser.params &= c
    else:
      state.parser.state = acpsInterm
      return state.parseAnsiCode(format, c)
  of acpsInterm:
    if c in ' ' .. '/':
      discard
    else:
      state.parser.state = acpsFinal
      return state.parseAnsiCode(format, c)
  of acpsFinal:
    state.parser.state = acpsDone
    if 0x40 <= int(c) and int(c) <= 0x7E:
      state.parser.parseControlFunction(format, c)
    else:
      return pacrProcess
  of acpsDone:
    discard
  of acpsBackspace:
    # We used to emulate less here, but it seems to yield dubious benefits
    # considering that
    # a) the only place backspace-based formatting is used in is manpages
    # b) we have w3mman now, which is superior in all respects, so this is
    # pretty much never used
    # c) if we drop generality, the output can be parsed much more efficiently
    # (without having to buffer the entire line first)
    #
    # So we buffer only the last non-formatted UTF-8 char, and override it when
    # necessary.
    if not state.hasPrintingBuf:
      state.parser.state = acpsDone
      return pacrProcess
    var i = state.outbufIdx - 1
    while true:
      if i < 0:
        state.parser.state = acpsDone
        return pacrProcess
      if (int(state.outbuf[i]) and 0xC0) != 0x80:
        break
      dec i
    if state.outbuf[i] == '_' or c == '_':
      # underline for underscore overstrike
      if ffUnderline notin state.pendingFmt.flags:
        state.tmpFlags.incl(ffUnderline)
        state.pendingFmt.flags.incl(ffUnderline)
      elif c == '_' and ffBold notin state.pendingFmt.flags:
        state.tmpFlags.incl(ffBold)
        state.pendingFmt.flags.incl(ffBold)
    else:
      # represent *any* non-underline overstrike with bold.
      # it is sloppy, but enough for our purposes.
      if ffBold notin state.pendingFmt.flags:
        state.tmpFlags.incl(ffBold)
        state.pendingFmt.flags.incl(ffBold)
    state.outbufIdx = i # move back output pointer
    state.parser.state = acpsInBackspaceTransition
    state.flushFmt()
    return pacrProcess
  of acpsInBackspaceTransition:
    if (int(c) and 0xC0) != 0x80:
      # backspace char end, next char begin
      state.parser.state = acpsInBackspace
    return pacrProcess
  of acpsInBackspace:
    if (int(c) and 0xC0) != 0x80:
      # second char after backspaced char begin
      if c == '\b':
        # got backspace again, overstriking previous char. here we don't have to
        # override anything
        state.parser.state = acpsBackspace
        return pacrProcess
      # welp. we have to fixup the previous char's formatting
      var i = state.outbufIdx - 1
      while true:
        assert i >= 0
        if (int(state.outbuf[i]) and 0xC0) != 0x80:
          break
        dec i
      let s = state.outbuf[i..<state.outbufIdx]
      state.outbufIdx = i
      for flag in FormatFlag:
        if flag in state.tmpFlags:
          state.pendingFmt.flags.excl(flag)
      state.tmpFlags = {}
      state.flushFmt()
      state.puts(s)
      state.parser.state = acpsDone
    return pacrProcess
  of acpsOSC:
    if c == '\a':
      state.parseOSC()
      state.parser.state = acpsDone
    elif c == '\e':
      state.parser.state = acpsOSCEsc
    else:
      state.parser.params &= c
  of acpsOSCEsc:
    if c == '\\':
      state.parseOSC()
      state.parser.state = acpsDone
    else:
      state.parser.params &= '\e'
      state.parser.params &= c
  state.flushFmt()
  pacrSkip

proc processData(state: var State; buf: openArray[char]) =
  for c in buf:
    if state.parser.state != acpsDone:
      case state.parseAnsiCode(state.pendingFmt, c)
      of pacrSkip: continue
      of pacrProcess: discard
    state.hasPrintingBuf = true
    case c
    of '<': state.puts("&lt;")
    of '>': state.puts("&gt;")
    of '\'': state.puts("&apos;")
    of '"': state.puts("&quot;")
    of '&': state.puts("&amp;")
    of '\t':
      let obgcolor = state.currentFmt.bgcolor
      state.pendingFmt = state.currentFmt
      state.pendingFmt.bgcolor = defaultColor
      state.flushFmt()
      state.putc('\t')
      state.pendingFmt.bgcolor = obgcolor
      state.flushFmt()
    of '\e': state.parser.reset()
    of '\b': state.parser.state = acpsBackspace
    of '\0': state.puts("\uFFFD") # HTML eats NUL, so replace it here
    else: state.putc(c)

proc usage() =
  let stderr = cast[ChaFile](stderr)
  discard stderr.writeLine("Usage: ansi2html [-s] [-t title]")
  quit(1)

proc main() =
  var state = State()
  # parse args
  let H = paramCount()
  var i = 1
  var standalone = false
  var title = ""
  while i <= H:
    let s = paramStr(i)
    if s == "":
      inc i
    if s[0] != '-':
      usage()
    for j in 1 ..< s.len:
      case s[j]
      of 's':
        standalone = true
      of 't':
        inc i
        if i > H: usage()
        title = paramStr(i).percentDecode()
      else:
        usage()
    inc i
  if standalone:
    state.puts("<!DOCTYPE html>\n")
  if title != "":
    state.puts("<title>" & title.htmlEscape() & "</title>\n")
  if standalone:
    state.puts("<body>\n")
  state.puts("<pre>\n")
  state.flushOutbuf()
  let ps = newPosixStream(STDIN_FILENO)
  var buffer {.noinit.}: array[4096, char]
  while true:
    let n = ps.readData(buffer)
    if n <= 0:
      break
    state.processData(buffer.toOpenArray(0, n - 1))
    state.flushOutbuf()
  if standalone:
    state.puts("</body>")
    state.flushOutbuf()

main()

{.pop.} # raises: []
