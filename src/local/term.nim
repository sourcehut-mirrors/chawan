{.push raises: [].}

import std/options
import std/os
import std/posix
import std/strutils
import std/tables
import std/termios

import chagashi/charset
import chagashi/decoder
import chagashi/encoder
import config/config
import config/conftypes
import io/dynstream
import types/blob
import types/cell
import types/color
import types/opt
import types/winattrs
import utils/myposix
import utils/strwidth
import utils/twtstr

type
  TerminalType = enum
    ttAdm3a = "adm3a"
    ttAlacritty = "alacritty"
    ttContour = "contour" # pretends to be XTerm
    ttDvtm = "dvtm"
    ttEat = "eat"
    ttEterm = "eterm"
    ttFbterm = "fbterm"
    ttFoot = "foot"
    ttFreebsd = "freebsd" # pretends to be XTerm
    ttGhostty = "ghostty"
    ttIterm2 = "iterm2"
    ttKitty = "xterm-kitty" # hardly XTerm
    ttKonsole = "konsole" # pretends to be XTerm
    ttLinux = "linux"
    ttMintty = "mintty"
    ttMlterm = "mlterm"
    ttMsTerminal = "ms-terminal"
    ttPutty = "putty"
    ttRio = "rio"
    ttRlogin = "rlogin"
    ttRxvt = "rxvt"
    ttScreen = "screen"
    ttSt = "st"
    ttSyncterm = "syncterm"
    ttTerminology = "terminology" # pretends to be XTerm
    ttTmux = "tmux"
    ttUrxvt = "rxvt-unicode"
    ttVt100 = "vt100"
    ttVt52 = "vt52"
    ttVte = "vte" # pretends to be XTerm
    ttWezterm = "wezterm"
    ttWterm = "wterm"
    ttXfce = "xfce" # pretends to be XTerm
    ttXst = "xst"
    ttXterm = "xterm"
    ttYaft = "yaft"
    ttZellij = "zellij" # pretends to be its underlying terminal

  CanvasImage* = ref object
    pid: int
    imageId: int
    # relative position on screen
    x: int
    y: int
    # original dimensions (after resizing)
    width: int
    height: int
    # offset (crop start)
    offx: int
    offy: int
    # kitty only: X/Y offset *inside* cell. (TODO implement for sixel too)
    # has nothing to do with offx/offy.
    offx2: int
    offy2: int
    # size cap (crop end)
    # Note: this 0-based, so the final display size is
    # (dispw - offx, disph - offy)
    dispw: int
    disph: int
    damaged: bool
    marked*: bool
    dead: bool
    transparent: bool
    preludeLen: int
    kittyId: int
    # 0 if kitty
    erry: int
    # absolute x, y in container
    rx: int
    ry: int
    data: Blob

  TerminalPage {.acyclic.} = ref object
    a: seq[uint8] # bytes to flush
    n: int # bytes of s already flushed
    next: TerminalPage

  Terminal* = ref object
    termType: TerminalType
    cs*: Charset
    te: TextEncoder
    config: Config
    istream*: PosixStream
    ostream*: PosixStream
    tdctx: TextDecoderContext
    eparser: EventParser
    canvas: seq[FixedCell]
    canvasImages*: seq[CanvasImage]
    imagesToClear*: seq[CanvasImage]
    lineDamage: seq[int]
    attrs*: WindowAttributes
    colorMode*: ColorMode
    formatMode: set[FormatFlag]
    imageMode*: ImageMode
    cleared: bool
    smcup: bool
    setTitle: bool
    queryDa1: bool
    bleedsAPC: bool
    margin: bool
    asciiOnly: bool
    origTermios: Termios
    newTermios: Termios
    defaultBackground: RGBColor
    defaultForeground: RGBColor
    ibuf: array[256, char] # buffer for chars when we can't process them
    ibufLen: int # len of ibuf
    ibufn: int # position in ibuf
    dynbuf: string # buffer for UTF-8 text input by the user, for areadChar
    dynbufn: int # position in dynbuf
    pageHead: TerminalPage # output buffer queue
    pageTail: TerminalPage # last output buffer
    registerCb: proc(fd: int) {.raises: [].} # callback to register ostream
    sixelRegisterNum*: int
    kittyId: int # counter for kitty image (*not* placement) ids.
    cursorx: int
    cursory: int
    colorMap: array[16, RGBColor]

  EventState = enum
    esNone = ""
    esEsc = "\e"
    esCSI = "\e["
    esCSI2 = "\e[2"
    esCSI20 = "\e[20"
    esCSI200 = "\e[200"
    esBracketed = ""
    esBracketedEsc = "\e"
    esBracketedCSI = "\e["
    esBracketedCSI2 = "\e[2"
    esBracketedCSI20 = "\e[20"
    esBracketedCSI201 = "\e[201"
    esMouseBtn
    esMousePx
    esMousePy
    esMouseSkip
    esBacktrack

  EventParser = object
    state: EventState
    keyLen: int8
    backtrackStack: seq[char]
    mouse: MouseInput
    mouseNum: uint32

  InputEventType* = enum
    ietKey, ietKeyEnd, ietPaste, ietMouse

  InputEvent* = object
    case t*: InputEventType
    of ietKey: # key press - UTF-8 bytes
      c*: char
    of ietKeyEnd: # key press done (if not in bracketed paste mode)
      discard
    of ietPaste: # bracketed paste done
      discard
    of ietMouse:
      m*: MouseInput

  MouseInputType* = enum
    mitPress = "press", mitRelease = "release", mitMove = "move"

  MouseInputMod* = enum
    mimShift = "shift", mimCtrl = "ctrl", mimMeta = "meta"

  MouseInputButton* = enum
    mibLeft = (1, "left")
    mibMiddle = (2, "middle")
    mibRight = (3, "right")
    mibWheelUp = (4, "wheelUp")
    mibWheelDown = (5, "wheelDown")
    mibWheelLeft = (6, "wheelLeft")
    mibWheelRight = (7, "wheelRight")
    mibThumbInner = (8, "thumbInner")
    mibThumbTip = (9, "thumbTip")
    mibButton10 = (10, "button10")
    mibButton11 = (11, "button11")

  MouseInput* = object
    t*: MouseInputType
    button*: MouseInputButton
    mods*: set[MouseInputMod]
    col*: int32
    row*: int32

# control sequence introducer
const CSI = "\e["

# primary device attributes
const DA1 = CSI & 'c'

# push/pop current title to/from the terminal's title stack
const PushTitle = CSI & "22t"
const PopTitle = CSI & "23t"

# report xterm text area size in pixels
const QueryWindowPixels = CSI & "14t"

# report cell size
const QueryCellSize = CSI & "16t"

# report window size in chars
const QueryWindowCells = CSI & "18t"

# allow shift-key to override mouse protocol
const SetShiftEscape = CSI & ">0s"

# number of color registers
const QueryColorRegisters = CSI & "?1;1;0S"

# horizontal & vertical position
template HVP(y, x: int): string =
  CSI & $y & ';' & $x & 'H'

# erase line
const EL = CSI & 'K'

# erase display
const ED = CSI & 'J'

# device control string
const DCS = "\eP"

# string terminator
const ST = "\e\\"

# xterm get terminal capability rgb
const QueryTcapRGB = DCS & "+q524742" & ST

# OS command
const OSC = "\e]"

const QueryForegroundColor = OSC & "10;?" & ST
const QueryBackgroundColor = OSC & "11;?" & ST
const QueryANSIColors = block:
  var s = ""
  for n in 0 ..< 16:
    s &= OSC & "4;" & $n & ";?" & ST
  s

# DEC set
template DECSET(s: varargs[string, `$`]): string =
  CSI & '?' & s.join(';') & 'h'

# DEC reset
template DECRST(s: varargs[string, `$`]): string =
  CSI & '?' & s.join(';') & 'l'

# alt screen
const SetAltScreen = DECSET(1049)
const ResetAltScreen = DECRST(1049)

# mouse tracking
const SetSGRMouse = DECSET(1002, 1006)
const ResetSGRMouse = DECRST(1002, 1006)

const SetBracketedPaste= DECSET(2004)
const ResetBracketedPaste = DECRST(2004)
const BracketedPasteStart* = CSI & "200~"
const BracketedPasteEnd* = CSI & "201~"

# show/hide cursor
const CNORM = DECSET(25)
const CIVIS = DECRST(25)

# application program command
const APC = "\e_"

const KittyQuery = APC & "Gi=1,a=q;" & ST

proc flush*(term: Terminal): bool =
  var page = term.pageHead
  while page != nil:
    var n = page.n
    let H = page.a.len - 1
    while n < page.a.len:
      let m = term.ostream.writeData(page.a.toOpenArray(n, H))
      if m < 0:
        let e = errno
        if e != EAGAIN and e != EWOULDBLOCK and e != EINTR:
          die("error writing to stdout: " & $strerror(e))
        break
      n += m
    if n < page.a.len:
      page.n = n
      break
    page = page.next
  term.pageHead = page
  if page == nil:
    term.pageTail = nil
    return true
  false

proc write(term: Terminal; s: openArray[char]) =
  if s.len > 0:
    var n = 0
    if term.pageHead == nil:
      while n < s.len:
        let m = term.ostream.writeData(s.toOpenArray(n, s.high))
        if m < 0:
          let e = errno
          if e != EAGAIN and e != EWOULDBLOCK and e != EINTR:
            die("error writing to stdout: " & $strerror(e))
          break
        n += m
    if n < s.len:
      let page = TerminalPage()
      if term.pageTail == nil:
        term.pageHead = page
        term.pageTail = page
        term.registerCb(int(term.ostream.fd))
      else:
        term.pageTail.next = page
        term.pageTail = page
      # I'd much rather just use @, but that introduces a ridiculous
      # copy function :(
      let len = s.len - n
      page.a = newSeqUninit[uint8](len)
      copyMem(addr page.a[0], unsafeAddr s[n], len)

proc readChar(term: Terminal): char =
  if term.ibufn == term.ibufLen:
    term.ibufn = 0
    term.ibufLen = term.istream.readData(term.ibuf)
    if term.ibufLen == -1:
      die("error reading from stdin")
  result = term.ibuf[term.ibufn]
  inc term.ibufn

proc ahandleRead*(term: Terminal): bool =
  term.ibufn = 0
  term.ibufLen = term.istream.readData(term.ibuf)
  if term.ibufLen < 0:
    let e = errno
    if e != EAGAIN and e != EWOULDBLOCK and e != EINTR:
      term.istream.setBlocking(true)
      term.ostream.setBlocking(true)
      die("error reading from stdin")
    term.ibufLen = 0
    return false
  true

# Note: in theory, we should run the escape parser state machine
# *before* parsing the input.
# In practice, it doesn't matter how you do it in UTF-8 as long as you
# stick to 7-bit chars.
proc areadChar(term: Terminal): Opt[char] =
  if term.dynbufn == term.dynbuf.len:
    term.dynbufn = 0
    term.dynbuf.setLen(0)
    let H = term.ibufLen - 1
    for it in term.tdctx.decode(term.ibuf.toOpenArrayByte(term.ibufn, H),
        finish = false):
      term.dynbuf &= it
    term.ibufn = term.ibufLen
  if term.dynbuf.len == term.dynbufn:
    return err()
  let c = term.dynbuf[term.dynbufn]
  inc term.dynbufn
  ok(c)

proc backtrack(eparser: var EventParser; s: string; c: char) =
  let s = $eparser.state
  eparser.state = esBacktrack
  eparser.backtrackStack = @[c]
  for i in countdown(s.high, 0):
    eparser.backtrackStack.add(s[i])

proc backtrack(eparser: var EventParser; c: char) =
  eparser.backtrack($eparser.state, c)

proc nextState(eparser: var EventParser; c, cc: char) =
  if c == cc:
    inc eparser.state
  else:
    eparser.backtrack(cc)

proc areadCharBacktrack(term: Terminal): Opt[char] =
  if term.eparser.state == esBacktrack:
    if term.eparser.backtrackStack.len > 0:
      return ok(term.eparser.backtrackStack.pop())
    term.eparser.state = esNone
  return term.areadChar()

proc areadEvent*(term: Terminal): Opt[InputEvent] =
  while true:
    if term.eparser.keyLen == 1:
      dec term.eparser.keyLen
      return ok(InputEvent(t: ietKeyEnd))
    let c = ?term.areadCharBacktrack()
    case term.eparser.state
    of esBacktrack, esNone:
      if term.eparser.state != esBacktrack and c == '\e':
        inc term.eparser.state
      elif term.eparser.keyLen > 0:
        dec term.eparser.keyLen
        return ok(InputEvent(t: ietKey, c: c))
      else:
        let u = uint8(c)
        term.eparser.keyLen = if u <= 0x7F: 1i8
        elif u shr 5 == 0b110: 2i8
        elif u shr 4 == 0b1110: 3i8
        else: 4i8
        return ok(InputEvent(t: ietKey, c: c))
    of esBracketed:
      if c == '\e':
        inc term.eparser.state
      else:
        return ok(InputEvent(t: ietKey, c: c))
    of esEsc, esBracketedEsc: term.eparser.nextState('[', c)
    of esCSI:
      case c
      of '<':
        term.eparser.mouse = MouseInput()
        term.eparser.mouseNum = 0
        term.eparser.state = esMouseBtn
      of '2': term.eparser.state = esCSI2
      else: term.eparser.backtrack(c)
    of esBracketedCSI: term.eparser.nextState('2', c)
    of esCSI2, esBracketedCSI2: term.eparser.nextState('0', c)
    of esCSI20: term.eparser.nextState('0', c)
    of esBracketedCSI20: term.eparser.nextState('1', c)
    of esCSI200: term.eparser.nextState('~', c)
    of esBracketedCSI201:
      if c == '~':
        term.eparser.state = esNone
        return ok(InputEvent(t: ietPaste))
      term.eparser.backtrack(c)
    of esMouseBtn, esMousePx, esMousePy:
      # CSI < btn ; Px ; Py M (press)
      # CSI < btn ; Px ; Py m (release)
      case c
      of '0'..'9':
        term.eparser.mouseNum *= 10
        term.eparser.mouseNum += uint32(c) - uint32('0')
        if term.eparser.mouseNum > uint16.high:
          term.eparser.state = esMouseSkip
      of 'm', 'M':
        if term.eparser.state == esMousePy:
          var mouse = term.eparser.mouse
          if mouse.t != mitMove:
            mouse.t = if c == 'M': mitPress else: mitRelease
          mouse.row = int32(term.eparser.mouseNum) - 1
          term.eparser.state = esNone
          return ok(InputEvent(t: ietMouse, m: mouse))
        else:
          term.eparser.state = esNone # welp
      of ';':
        case term.eparser.state
        of esMouseBtn:
          let btn = term.eparser.mouseNum
          if (btn and 4) != 0:
            term.eparser.mouse.mods.incl(mimShift)
          if (btn and 8) != 0:
            term.eparser.mouse.mods.incl(mimCtrl)
          if (btn and 16) != 0:
            term.eparser.mouse.mods.incl(mimMeta)
          if (btn and 32) != 0:
            term.eparser.mouse.t = mitMove
          var button = (btn and 3) + 1
          if (btn and 64) != 0:
            button += 3
          if (btn and 128) != 0:
            button += 7
          if button in
              uint32(MouseInputButton.low)..uint32(MouseInputButton.high):
            term.eparser.mouse.button = MouseInputButton(button)
            term.eparser.state = esMousePx
          else:
            term.eparser.state = esMouseSkip
        of esMousePx:
          term.eparser.mouse.col = int32(term.eparser.mouseNum) - 1
          term.eparser.state = esMousePy
        else: # esMousePy
          term.eparser.state = esMouseSkip
        term.eparser.mouseNum = 0
      else: # we got something unexpected; try not to get stuck...
        term.eparser.state = esNone
    of esMouseSkip:
      # backtracking mouse events is too much effort; just skip it.
      if c in {'m', 'M'}:
        term.eparser.state = esNone
  err()

proc cursorGoto(term: Terminal; x, y: int): string =
  case term.termType
  of ttAdm3a: return "\e=" & char(uint8(y) + 0x20) & char(uint8(x) + 0x20)
  of ttVt52: return "\eY" & char(uint8(y) + 0x20) & char(uint8(x) + 0x20)
  else: return HVP(y + 1, x + 1)

proc clearEnd(term: Terminal): string =
  case term.termType
  of ttAdm3a: return ""
  of ttVt52: return "\eK"
  else: return EL

proc clearDisplay(term: Terminal): string =
  case term.termType
  of ttAdm3a: return "\x1A"
  of ttVt52: return "\eJ"
  else: return ED

proc isatty*(term: Terminal): bool =
  return term.istream != nil and term.istream.isatty() and term.ostream.isatty()

proc anyKey*(term: Terminal; msg = "[Hit any key]") =
  if term.isatty():
    term.istream.setBlocking(true)
    term.ostream.setBlocking(true)
    doAssert term.flush()
    term.write(term.clearEnd() & msg)
    discard term.readChar()
    term.istream.setBlocking(false)
    term.ostream.setBlocking(false)

proc resetFormat(term: Terminal): string =
  case term.termType
  of ttAdm3a, ttVt52: return ""
  else: return CSI & 'm'

const FormatCodes: array[FormatFlag, tuple[s, e: uint8]] = [
  ffBold: (1u8, 22u8),
  ffItalic: (3u8, 23u8),
  ffUnderline: (4u8, 24u8),
  ffReverse: (7u8, 27u8),
  ffStrike: (9u8, 29u8),
  ffOverline: (53u8, 55u8),
  ffBlink: (5u8, 25u8),
]

proc startFormat(term: Terminal; flag: FormatFlag): string =
  return CSI & $FormatCodes[flag].s & 'm'

proc endFormat(term: Terminal; flag: FormatFlag): string =
  return CSI & $FormatCodes[flag].e & 'm'

proc setCursor*(term: Terminal; x, y: int) =
  assert x >= 0 and y >= 0
  if x != term.cursorx or y != term.cursory:
    term.write(term.cursorGoto(x, y))
    term.cursorx = x
    term.cursory = y

proc enableAltScreen(term: Terminal): string =
  return SetAltScreen

proc disableAltScreen(term: Terminal): string =
  return ResetAltScreen

proc getRGB(term: Terminal; a: CellColor; termDefault: RGBColor): RGBColor =
  case a.t
  of ctNone:
    return termDefault
  of ctANSI:
    let n = a.ansi
    if uint8(n) >= 16:
      return n.toRGB()
    return term.colorMap[uint8(n)]
  of ctRGB:
    return a.rgb

# Use euclidian distance to quantize RGB colors.
proc approximateANSIColor(term: Terminal; rgb, termDefault: RGBColor):
    CellColor =
  var a = 0
  var n = -1
  if rgb == termDefault:
    return defaultColor
  for i in -1 .. term.colorMap.high:
    let color = if i >= 0:
      term.colorMap[i]
    else:
      termDefault
    if color == rgb:
      return ANSIColor(i).cellColor()
    {.push overflowChecks:off.}
    let x = int(color.r) - int(rgb.r)
    let y = int(color.g) - int(rgb.g)
    let z = int(color.b) - int(rgb.b)
    let xx = x * x
    let yy = y * y
    let zz = z * z
    let b = xx + yy + zz
    {.pop.}
    if i == -1 or b < a:
      n = i
      a = b
  return if n == -1: defaultColor else: ANSIColor(n).cellColor()

# Return a fgcolor contrasted to the background by the minimum configured
# contrast.
proc correctContrast(term: Terminal; bgcolor, fgcolor: CellColor): CellColor =
  let contrast = term.config.display.minimumContrast
  let cfgcolor = fgcolor
  let bgcolor = term.getRGB(bgcolor, term.defaultBackground)
  let fgcolor = term.getRGB(fgcolor, term.defaultForeground)
  let bgY = int(bgcolor.Y)
  var fgY = int(fgcolor.Y)
  let diff = abs(bgY - fgY)
  if diff < contrast:
    if bgY > fgY:
      fgY = bgY - contrast
      if fgY < 0:
        fgY = bgY + contrast
        if fgY > 255:
          fgY = 0
    else:
      fgY = bgY + contrast
      if fgY > 255:
        fgY = bgY - contrast
        if fgY < 0:
          fgY = 255
    let newrgb = YUV(uint8(fgY), fgcolor.U, fgcolor.V)
    case term.colorMode
    of cmTrueColor:
      return cellColor(newrgb)
    of cmANSI:
      return term.approximateANSIColor(newrgb, term.defaultForeground)
    of cmEightBit:
      return cellColor(newrgb.toEightBit())
    of cmMonochrome:
      assert false
  return cfgcolor

proc addColorSGR(res: var string; c: CellColor; bgmod: uint8) =
  res &= CSI
  case c.t
  of ctNone:
    res &= 39 + bgmod
  of ctANSI:
    let n = uint8(c.ansi)
    if n < 16:
      if n < 8:
        res &= 30 + bgmod + n
      else:
        res &= 82 + bgmod + n
    else:
      res &= 38 + bgmod
      res &= ";5;"
      res &= n
  of ctRGB:
    let rgb = c.rgb
    res &= 38 + bgmod
    res &= ";2;"
    res &= rgb.r
    res &= ';'
    res &= rgb.g
    res &= ';'
    res &= rgb.b
  res &= 'm'

# If needed, quantize colors based on the color mode, and correct their
# contrast.
proc reduceColors(term: Terminal; fgcolor, bgcolor: var CellColor) =
  case term.colorMode
  of cmANSI:
    if bgcolor.t == ctANSI and uint8(bgcolor.ansi) > 15:
      bgcolor = fgcolor.ansi.toRGB().cellColor()
    if bgcolor.t == ctRGB:
      bgcolor = term.approximateANSIColor(bgcolor.rgb, term.defaultBackground)
    if fgcolor.t == ctANSI and uint8(fgcolor.ansi) > 15:
      fgcolor = fgcolor.ansi.toRGB().cellColor()
    if fgcolor.t == ctRGB:
      fgcolor = term.approximateANSIColor(fgcolor.rgb, term.defaultForeground)
    fgcolor = term.correctContrast(bgcolor, fgcolor)
  of cmEightBit:
    if bgcolor.t == ctRGB:
      bgcolor = bgcolor.rgb.toEightBit().cellColor()
    if fgcolor.t == ctRGB:
      fgcolor = fgcolor.rgb.toEightBit().cellColor()
    fgcolor = term.correctContrast(bgcolor, fgcolor)
  of cmTrueColor:
    fgcolor = term.correctContrast(bgcolor, fgcolor)
  of cmMonochrome:
    discard # nothing to do

proc processFormat*(res: var string; term: Terminal; format: var Format;
    cellf: Format) =
  var fgcolor = cellf.fgcolor
  var bgcolor = cellf.bgcolor
  term.reduceColors(fgcolor, bgcolor)
  if format.flags != cellf.flags:
    var oldFlags {.noinit.}: array[int(FormatFlag.high) + 1, FormatFlag]
    var i = 0
    for flag in term.formatMode:
      if flag in format.flags and flag notin cellf.flags:
        oldFlags[i] = flag
        inc i
      if flag notin format.flags and flag in cellf.flags:
        res &= term.startFormat(flag)
    if i > 0:
      # if either
      # * both fgcolor and bgcolor are the default, or
      # * both are being changed,
      # then we can use a general reset when new flags are empty.
      if cellf.flags == {} and
          (fgcolor != format.fgcolor and bgcolor != format.bgcolor or
          fgcolor == defaultColor and bgcolor == defaultColor):
        res &= term.resetFormat()
      else:
        for flag in oldFlags.toOpenArray(0, i - 1):
          res &= term.endFormat(flag)
    format.flags = cellf.flags
  if term.colorMode != cmMonochrome:
    if fgcolor != format.fgcolor:
      res.addColorSGR(fgcolor, bgmod = 0)
      format.fgcolor = fgcolor
    if bgcolor != format.bgcolor:
      res.addColorSGR(bgcolor, bgmod = 10)
      format.bgcolor = bgcolor

proc setTitle*(term: Terminal; title: string) =
  if term.setTitle:
    term.write(OSC & "0;" & title.replaceControls() & ST)

proc enableMouse*(term: Terminal) =
  case term.termType
  of ttAdm3a, ttVt52, ttVt100: discard
  else: term.write(SetShiftEscape & SetSGRMouse)

proc disableMouse*(term: Terminal) =
  case term.termType
  of ttAdm3a, ttVt52, ttVt100: discard
  else: term.write(ResetSGRMouse)

proc enableBracketedPaste(term: Terminal) =
  case term.termType
  of ttAdm3a, ttVt52, ttVt100: discard
  else: term.write(SetBracketedPaste)

proc disableBracketedPaste(term: Terminal) =
  case term.termType
  of ttAdm3a, ttVt52, ttVt100: discard
  else: term.write(ResetBracketedPaste)

proc encodeAllQMark(res: var string; start: int; te: TextEncoder;
    iq: openArray[uint8]) =
  var n = start
  while true:
    case te.encode(iq, res.toOpenArrayByte(0, res.high), n)
    of terDone:
      res.setLen(n)
      case te.finish()
      of tefrOutputISO2022JPSetAscii:
        res &= "\e(B"
      of tefrDone:
        discard
      break
    of terReqOutput:
      res.setLen(res.len * 2)
    of terError:
      res.setLen(n)
      # match width of replaced char
      for i in 0 ..< te.c.width():
        res &= '?'
      n = res.len

proc processOutputString*(res: var string; term: Terminal; s: openArray[char];
    w: var int) =
  if s.len == 0:
    return
  if s.validateUTF8Surr() != -1:
    res &= '?'
    if w != -1:
      inc w
    return
  if w != -1:
    for u in s.points:
      assert u > 0x9F or u != 0x7F and u > 0x1F
      w += u.width()
  let L = res.len
  if term.te == nil:
    # The output encoding matches the internal representation.
    res.setLen(L + s.len)
    copyMem(addr res[L], unsafeAddr s[0], s.len)
  elif term.asciiOnly:
    for u in s.points:
      if u < 0x80:
        res &= char(u)
      else:
        for i in 0 ..< u.width():
          res &= '?'
  else:
    # Output is not utf-8, so we must encode it first.
    res.setLen(L + s.len) # guess length
    res.encodeAllQMark(L, term.te, s.toOpenArrayByte(0, s.high))

proc generateFullOutput(term: Terminal): string =
  var format = Format()
  result = term.cursorGoto(0, 0)
  result &= term.resetFormat()
  result &= term.clearDisplay()
  for y in 0 ..< term.attrs.height:
    if y != 0:
      result &= "\r\n"
    var w = 0
    for x in 0 ..< term.attrs.width:
      while w < x:
        result &= " "
        inc w
      let cell = addr term.canvas[y * term.attrs.width + x]
      result.processFormat(term, format, cell.format)
      result.processOutputString(term, cell.str, w)
    term.lineDamage[y] = term.attrs.width

proc generateSwapOutput(term: Terminal): string =
  result = ""
  var vy = -1
  for y in 0 ..< term.attrs.height:
    # set cx to x of the first change
    let cx = term.lineDamage[y]
    # w will track the current position on screen
    var w = cx
    if cx < term.attrs.width:
      if cx == 0 and vy != -1:
        while vy < y:
          result &= "\r\n"
          inc vy
      else:
        result &= term.cursorGoto(cx, y)
        vy = y
      result &= term.resetFormat()
      var format = Format()
      for x in cx ..< term.attrs.width:
        while w < x: # if previous cell had no width, catch up with x
          result &= ' '
          inc w
        let cell = term.canvas[y * term.attrs.width + x]
        result.processFormat(term, format, cell.format)
        result.processOutputString(term, cell.str, w)
      if w < term.attrs.width:
        result &= term.clearEnd()
      # damage is gone
      term.lineDamage[y] = term.attrs.width

proc hideCursor*(term: Terminal) =
  case term.termType
  of ttAdm3a, ttVt52: discard
  else: term.write(CIVIS)

proc showCursor*(term: Terminal) =
  case term.termType
  of ttAdm3a, ttVt52: discard
  else: term.write(CNORM)

proc writeGrid*(term: Terminal; grid: FixedGrid; x = 0, y = 0) =
  for ly in y ..< y + grid.height:
    var lastx = 0
    for lx in x ..< x + grid.width:
      let i = ly * term.attrs.width + lx
      let cell = grid[(ly - y) * grid.width + (lx - x)]
      if term.canvas[i].str != "":
        # if there is a change, we have to start from the last x with
        # a string (otherwise we might overwrite half of a double-width char)
        lastx = lx
      if cell != term.canvas[i]:
        term.canvas[i] = cell
        term.lineDamage[ly] = min(term.lineDamage[ly], lastx)

proc applyConfigDimensions(term: Terminal) =
  # screen dimensions
  if term.attrs.width == 0 or term.config.display.forceColumns:
    term.attrs.width = int(term.config.display.columns)
  if term.attrs.height == 0 or term.config.display.forceLines:
    term.attrs.height = int(term.config.display.lines)
  if term.attrs.ppc == 0 or term.config.display.forcePixelsPerColumn:
    term.attrs.ppc = int(term.config.display.pixelsPerColumn)
  if term.attrs.ppl == 0 or term.config.display.forcePixelsPerLine:
    term.attrs.ppl = int(term.config.display.pixelsPerLine)
  term.attrs.widthPx = term.attrs.ppc * term.attrs.width
  term.attrs.heightPx = term.attrs.ppl * term.attrs.height

proc applyConfig(term: Terminal) =
  # colors, formatting
  if term.config.display.colorMode.isSome:
    term.colorMode = term.config.display.colorMode.get
  if term.config.display.formatMode.isSome:
    term.formatMode = term.config.display.formatMode.get
  for fm in FormatFlag:
    if fm in term.config.display.noFormatMode:
      term.formatMode.excl(fm)
  if term.config.display.imageMode.isSome:
    term.imageMode = term.config.display.imageMode.get
  if term.imageMode == imSixel and term.config.display.sixelColors.isSome:
    let n = term.config.display.sixelColors.get
    term.sixelRegisterNum = clamp(n, 2, 65535)
  if term.isatty():
    if term.config.display.altScreen.isSome:
      term.smcup = term.config.display.altScreen.get
    if term.config.display.setTitle.isSome:
      term.setTitle = term.config.display.setTitle.get
  if term.config.display.defaultBackgroundColor.isSome:
    term.defaultBackground = term.config.display.defaultBackgroundColor.get
  if term.config.display.defaultForegroundColor.isSome:
    term.defaultForeground = term.config.display.defaultForegroundColor.get
  term.attrs.prefersDark = term.defaultBackground.Y < 125
  # charsets
  if term.config.encoding.displayCharset.isSome:
    term.cs = term.config.encoding.displayCharset.get
  else:
    term.cs = DefaultCharset
    for s in ["LC_ALL", "LC_CTYPE", "LANG"]:
      let env = getEnv(s)
      if env == "":
        continue
      let cs = getLocaleCharset(env)
      if cs != CHARSET_UNKNOWN:
        if cs == CHARSET_WINDOWS_1252:
          term.asciiOnly = env.strip(chars =  AsciiWhitespace)
            .endsWithIgnoreCase(".ascii")
        term.cs = cs
        break
  if term.cs in {CHARSET_UTF_8, CHARSET_UTF_16_LE, CHARSET_UTF_16_BE,
      CHARSET_REPLACEMENT}:
    term.cs = CHARSET_UTF_8
  else:
    term.te = newTextEncoder(term.cs)
  term.tdctx = initTextDecoderContext(term.cs)
  term.applyConfigDimensions()

proc outputGrid*(term: Terminal) =
  term.write(term.resetFormat())
  if term.config.display.forceClear or not term.cleared:
    term.write(term.generateFullOutput())
    term.cleared = true
  else:
    term.write(term.generateSwapOutput())
  term.cursorx = -1
  term.cursory = -1

proc findImage(term: Terminal; pid, imageId: int; rx, ry, width, height,
    erry, offx, dispw: int): CanvasImage =
  for it in term.canvasImages:
    if not it.dead and it.pid == pid and it.imageId == imageId and
        it.width == width and it.height == height and
        it.rx == rx and it.ry == ry and
        (term.imageMode != imSixel or it.erry == erry and it.dispw == dispw and
          it.offx == offx):
      return it
  return nil

# x, y, maxw, maxh in cells
# x, y can be negative, then image starts outside the screen
proc positionImage(term: Terminal; image: CanvasImage;
    x, y, maxw, maxh, offx2, offy2: int): bool =
  image.x = x
  image.y = y
  image.offx2 = offx2
  image.offy2 = offy2
  var xpx = x * term.attrs.ppc
  var ypx = y * term.attrs.ppl
  if term.imageMode == imKitty:
    xpx += image.offx2
    ypx += image.offy2
  # calculate offset inside image to start from
  image.offx = -min(xpx, 0)
  image.offy = -min(ypx, 0)
  # clear offx2/offy2 if the image starts outside the screen
  if image.offx > 0:
    image.offx2 = 0
  if image.offy > 0:
    image.offy2 = 0
  # calculate maximum image size that fits on the screen relative to the image
  # origin (*not* offx/offy)
  let maxwpx = maxw * term.attrs.ppc
  let maxhpx = maxh * term.attrs.ppl
  image.dispw = min(image.width + xpx, maxwpx) - xpx
  image.disph = min(image.height + ypx, maxhpx) - ypx
  image.damaged = true
  return image.dispw > image.offx and image.disph > image.offy

proc clearImage(term: Terminal; image: CanvasImage; maxh: int) =
  case term.imageMode
  of imNone: discard
  of imSixel:
    # we must clear sixels the same way as we clear text.
    let h = (image.height + term.attrs.ppl - 1) div term.attrs.ppl # ceil
    let ey = min(image.y + h, maxh)
    let x = max(image.x, 0)
    for y in max(image.y, 0) ..< ey:
      term.lineDamage[y] = min(term.lineDamage[y], x)
  of imKitty:
    term.imagesToClear.add(image)

proc clearImages*(term: Terminal; maxh: int) =
  for image in term.canvasImages:
    if not image.marked:
      term.clearImage(image, maxh)
    image.marked = false
  term.canvasImages.setLen(0)

proc checkImageDamage*(term: Terminal; maxw, maxh: int) =
  if term.imageMode == imSixel:
    for image in term.canvasImages:
      # check if any line of our image is damaged
      let h = (image.height + term.attrs.ppl - 1) div term.attrs.ppl # ceil
      let ey0 = min(image.y + h, maxh)
      # here we floor, so that a last line with rounding error (which
      # will not fully cover text) is always cleared
      let ey1 = min(image.y + image.height div term.attrs.ppl, maxh)
      let x = max(image.x, 0)
      let mx = min(image.x + image.dispw div term.attrs.ppc, maxw)
      for y in max(image.y, 0) ..< ey0:
        let od = term.lineDamage[y]
        if image.transparent and od > x:
          image.damaged = true
          if od < mx:
            # damage starts inside this image; move it to its beginning.
            term.lineDamage[y] = x
        elif not image.transparent and od < mx:
          image.damaged = true
          if y >= ey1:
            break
          if od >= image.x:
            # damage starts inside this image; skip clear (but only if
            # the damage was not caused by a printing character)
            var textFound = false
            let si = y * term.attrs.width
            for i in si + od ..< si + term.attrs.width:
              if term.canvas[i].str.len > 0 and term.canvas[i].str[0] != ' ':
                textFound = true
                break
            if not textFound:
              term.lineDamage[y] = mx

proc loadImage*(term: Terminal; data: Blob; pid, imageId, x, y, width, height,
    rx, ry, maxw, maxh, erry, offx, dispw, offx2, offy2, preludeLen: int;
    transparent: bool; redrawNext: var bool): CanvasImage =
  if (let image = term.findImage(pid, imageId, rx, ry, width, height, erry,
        offx, dispw); image != nil):
    # reuse image on screen
    if image.x != x or image.y != y or redrawNext:
      # only clear sixels; with kitty we just move the existing image
      if term.imageMode == imSixel:
        term.clearImage(image, maxh)
      if not term.positionImage(image, x, y, maxw, maxh, offx2, offy2):
        # no longer on screen
        image.dead = true
        return nil
    # only mark old images; new images will not be checked until the next
    # initImages call.
    image.marked = true
    return image
  # new image
  let image = CanvasImage(
    pid: pid,
    imageId: imageId,
    data: data,
    rx: rx,
    ry: ry,
    offx2: offx2,
    offy2: offy2,
    width: width,
    height: height,
    erry: erry,
    transparent: transparent,
    preludeLen: preludeLen
  )
  if term.positionImage(image, x, y, maxw, maxh, offx2, offy2):
    redrawNext = true
    return image
  # no longer on screen
  return nil

proc getU32BE(data: openArray[char]; i: int): uint32 =
  return uint32(data[i + 3]) or
    (uint32(data[i + 2]) shl 8) or
    (uint32(data[i + 1]) shl 16) or
    (uint32(data[i]) shl 24)

proc appendSixelAttrs(outs: var string; data: openArray[char];
    realw, realh: int) =
  var i = 0
  while i < data.len:
    let c = data[i]
    outs &= c
    inc i
    if c == '"': # set raster attrs
      break
  while i < data.len and data[i] != '#': # skip aspect ratio attrs
    inc i
  outs &= "1;1;" & $realw & ';' & $realh
  if i < data.len:
    let ol = outs.len
    outs.setLen(ol + data.len - i)
    copyMem(addr outs[ol], unsafeAddr data[i], data.len - i)

proc outputSixelImage(term: Terminal; x, y: int; image: CanvasImage;
    data: openArray[char]) =
  let offx = image.offx
  let offy = image.offy
  let dispw = image.dispw
  let disph = image.disph
  let realw = dispw - offx
  let realh = disph - offy
  let preludeLen = image.preludeLen
  if preludeLen > data.len or data.len < 4:
    return
  let L = data.len - int(data.getU32BE(data.len - 4)) - 4
  if L < 0:
    return
  var outs = term.cursorGoto(x, y)
  outs.appendSixelAttrs(data.toOpenArray(0, preludeLen - 1), realw, realh)
  term.write(outs)
  # Note: we only crop images when it is possible to do so in near constant
  # time. Otherwise, the image is re-coded in a cropped form.
  if realh == image.height: # don't crop
    term.write(data.toOpenArray(preludeLen, L - 1))
  else:
    let si = preludeLen + int(data.getU32BE(L + (offy div 6) * 4))
    if si >= data.len: # bounds check
      term.write(ST)
    elif disph == image.height: # crop top only
      term.write(data.toOpenArray(si, L - 1))
    else: # crop both top & bottom
      let ed6 = (disph - image.erry) div 6
      let ei = preludeLen + int(data.getU32BE(L + ed6 * 4)) - 1
      if ei <= data.len: # bounds check
        term.write(data.toOpenArray(si, ei - 1))
      # calculate difference between target Y & actual position in the map
      # note: it must be offset by image.erry; that's where the map starts.
      let herry = disph - (ed6 * 6 + image.erry)
      if herry > 0:
        # can't write out the last row completely; mask off the bottom part.
        let mask = (1u8 shl herry) - 1
        var s = "-"
        var i = ei + 1
        while i < L and (let c = data[i]; c notin {'-', '\e'}): # newline or ST
          let u = uint8(c) - 0x3F # may underflow, but that's no problem
          if u < 0x40:
            s &= char((u and mask) + 0x3F)
          else:
            s &= c
          inc i
        term.write(s)
      term.write(ST)

proc outputSixelImage(term: Terminal; x, y: int; image: CanvasImage) =
  var p = cast[ptr UncheckedArray[char]](image.data.buffer)
  if image.data.size > 0:
    let H = image.data.size - 1
    term.outputSixelImage(x, y, image, p.toOpenArray(0, H))

proc outputKittyImage(term: Terminal; x, y: int; image: CanvasImage) =
  var outs = term.cursorGoto(x, y) &
    APC & "GC=1,s=" & $image.width & ",v=" & $image.height &
    ",x=" & $image.offx & ",y=" & $image.offy &
    ",X=" & $image.offx2 & ",Y=" & $image.offy2 &
    ",w=" & $(image.dispw - image.offx) &
    ",h=" & $(image.disph - image.offy) &
    # for now, we always use placement id 1
    ",p=1,q=2"
  if image.kittyId != 0:
    outs &= ",i=" & $image.kittyId & ",a=p;" & ST
    term.write(outs)
    return
  inc term.kittyId # skip i=0
  image.kittyId = term.kittyId
  outs &= ",i=" & $image.kittyId
  const MaxBytes = 4096 * 3 div 4
  var i = MaxBytes
  let p = cast[ptr UncheckedArray[uint8]](image.data.buffer)
  let L = image.data.size
  let m = if i < L: '1' else: '0'
  outs &= ",a=T,f=100,m=" & m & ';'
  outs.btoa(p.toOpenArray(0, min(L, i) - 1))
  outs &= ST
  term.write(outs)
  while i < L:
    let j = i
    i += MaxBytes
    let m = if i < L: '1' else: '0'
    var outs = APC & "Gm=" & m & ';'
    outs.btoa(p.toOpenArray(j, min(L, i) - 1))
    outs &= ST
    term.write(outs)

proc outputImages*(term: Terminal) =
  if term.imageMode == imKitty:
    # clean up unused kitty images
    var s = ""
    for image in term.imagesToClear:
      if image.kittyId == 0:
        continue # maybe it was never displayed...
      s &= APC & "Ga=d,d=I,i=" & $image.kittyId & ",p=1,q=2;" & ST
    term.write(s)
    term.imagesToClear.setLen(0)
  for image in term.canvasImages:
    if image.damaged:
      assert image.dispw > 0 and image.disph > 0
      let x = max(image.x, 0)
      let y = max(image.y, 0)
      case term.imageMode
      of imNone: assert false
      of imSixel: term.outputSixelImage(x, y, image)
      of imKitty: term.outputKittyImage(x, y, image)
      image.damaged = false

proc clearCanvas*(term: Terminal) =
  term.cleared = false
  let maxw = term.attrs.width
  let maxh = term.attrs.height - 1
  var newImages: seq[CanvasImage] = @[]
  for image in term.canvasImages:
    if term.positionImage(image, image.x, image.y, maxw, maxh, image.offx2,
        image.offy2):
      image.damaged = true
      image.marked = true
      newImages.add(image)
  term.clearImages(maxh)
  term.canvasImages = newImages

# see https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html
proc disableRawMode(term: Terminal) =
  discard tcSetAttr(term.istream.fd, TCSAFLUSH, addr term.origTermios)

proc enableRawMode(term: Terminal) =
  #TODO check errors
  discard tcGetAttr(term.istream.fd, addr term.origTermios)
  var raw = term.origTermios
  raw.c_iflag = raw.c_iflag and not (BRKINT or ICRNL or INPCK or ISTRIP or IXON)
  raw.c_oflag = raw.c_oflag and not (OPOST)
  raw.c_cflag = raw.c_cflag or CS8
  raw.c_lflag = raw.c_lflag and not (ECHO or ICANON or ISIG or IEXTEN)
  raw.c_cc[VMIN] = char(1)
  raw.c_cc[VTIME] = char(0)
  term.newTermios = raw
  discard tcSetAttr(term.istream.fd, TCSAFLUSH, addr raw)

# This is checked in the SIGINT handler, set in main.nim.
var sigintCaught* {.global.} = false
var acceptSigint* {.global.} = false

proc catchSigint*(term: Terminal) =
  term.newTermios.c_lflag = term.newTermios.c_lflag or ISIG
  acceptSigint = true
  discard tcSetAttr(term.istream.fd, TCSAFLUSH, addr term.newTermios)

proc respectSigint*(term: Terminal) =
  sigintCaught = false
  acceptSigint = false
  term.newTermios.c_lflag = term.newTermios.c_lflag and not ISIG
  discard tcSetAttr(term.istream.fd, TCSAFLUSH, addr term.newTermios)

proc quit*(term: Terminal) =
  if term.isatty():
    term.disableRawMode()
    if term.config.input.useMouse:
      term.disableMouse()
    if term.config.input.bracketedPaste:
      term.disableBracketedPaste()
    term.istream.setBlocking(true)
    term.ostream.setBlocking(true)
    if term.smcup:
      if term.imageMode == imSixel:
        # xterm seems to keep sixels in the alt screen; clear these so
        # it doesn't flash in the user's face the next time they do smcup
        term.write(term.clearDisplay())
      term.write(term.disableAltScreen())
    else:
      term.write(term.cursorGoto(0, term.attrs.height - 1) &
        term.resetFormat() & "\n")
    if term.setTitle:
      term.write(PopTitle)
    term.showCursor()
    term.clearCanvas()

type
  QueryAttrs = enum
    qaAnsiColor, qaRGB, qaSixel, qaKittyImage

  QueryResult = object
    success: bool
    attrs: set[QueryAttrs]
    fgcolor: Option[RGBColor]
    bgcolor: Option[RGBColor]
    colorMap: seq[tuple[n: int; rgb: RGBColor]]
    widthPx: int
    heightPx: int
    ppc: int
    ppl: int
    width: int
    height: int
    registers: int

proc consumeIntUntil(term: Terminal; sentinel: char): int =
  var n = 0
  while (let c = term.readChar(); c != sentinel):
    if (let x = decValue(c); x != -1):
      n *= 10
      n += x
    else:
      return -1
  return n

proc consumeIntGreedy(term: Terminal; lastc: var char): int =
  var n = 0
  while true:
    let c = term.readChar()
    if (let x = decValue(c); x != -1):
      n *= 10
      n += x
    else:
      lastc = c
      break
  return n

proc eatColor(term: Terminal; tc: char): uint8 =
  var val = 0u8
  var i = 0
  var c = char(0)
  while (c = term.readChar(); c != tc and c != '\a'):
    let v0 = hexValue(c)
    if i > 4 or v0 == -1:
      break # wat
    let v = uint8(v0)
    if i == 0: # 1st place - expand it for when we don't get a 2nd place
      val = (v shl 4) or v
    elif i == 1: # 2nd place - clear expanded placeholder from 1st place
      val = (val and not 0xFu8) or v
    # all other places are irrelevant
    inc i
  if tc == '\e' and c != '\a':
    if term.readChar() != '\\':
      return 0 # error
  if tc != '\e' and c == '\a':
    return 0 # error
  return val

proc skipUntil(term: Terminal; c: char) =
  while term.readChar() != c:
    discard

proc skipUntilST(term: Terminal) =
  while true:
    let c = term.readChar()
    # st returns BEL *despite* us sending ST. Ugh.
    if c == '\a' or c == '\e' and term.readChar() == '\\':
      break

proc queryAttrs(term: Terminal; windowOnly: bool): QueryResult =
  const tcapRGB = 0x524742 # RGB supported?
  var outs = ""
  if not windowOnly:
    if term.termType != ttScreen:
      # screen has a horrible bug where the responses to bg/fg queries
      # are printed out of order (presumably because it must ask the
      # terminal first).
      #
      # I can't work around this, because screen won't respond at all
      # from terminals that don't support this query.  So I'll do the
      # sole reasonable thing and skip default color queries.
      if term.config.display.defaultBackgroundColor.isNone:
        outs &= QueryBackgroundColor
      if term.config.display.defaultForegroundColor.isNone:
        outs &= QueryForegroundColor
    if term.config.display.imageMode.isNone:
      if not term.bleedsAPC:
        outs &= KittyQuery
      outs &= QueryColorRegisters
    elif term.config.display.imageMode.get == imSixel:
      outs &= QueryColorRegisters
    if term.config.display.colorMode.isNone:
      outs &= QueryTcapRGB
    outs &= QueryANSIColors
  outs &= QueryWindowPixels & QueryCellSize & QueryWindowCells & DA1
  term.write(outs)
  doAssert term.flush()
  result = QueryResult(success: false, attrs: {})
  while true:
    template fail =
      return
    template expect(term: Terminal; c: char) =
      if term.readChar() != c:
        fail
    term.expect '\e'
    case term.readChar()
    of '[': # CSI
      case (let c = term.readChar(); c)
      of '?': # DA1, XTSMGRAPHICS
        var params = newSeq[int]()
        var lastc = char(0)
        while lastc notin {'c', 'S'}:
          let n = term.consumeIntGreedy(lastc)
          if lastc notin {'c', 'S', ';'}:
            # skip entry
            break
          params.add(n)
        if lastc == 'c': # DA1
          for n in params:
            case n
            of 4: result.attrs.incl(qaSixel)
            of 22: result.attrs.incl(qaAnsiColor)
            else: discard
          result.success = true
          break
        else: # 'S' (XTSMGRAPHICS)
          if params.len >= 3:
            if params[0] == 1 and params[1] == 0:
              result.registers = params[2]
      of '=':
        # = is SyncTERM's response to DA1. Nothing useful will come after this.
        term.skipUntil('c')
        term.termType = ttSyncterm
        result.success = true
        break # we're done
      of '4', '6', '8':
        term.expect ';'
        let height = term.consumeIntUntil(';')
        let width = term.consumeIntUntil('t')
        if width == -1 or height == -1:
          discard
        elif c == '4':
          result.widthPx = width
          result.heightPx = height
        elif c == '6':
          result.ppc = width
          result.ppl = height
        elif c == '8':
          result.width = width
          result.height = height
      else: fail
    of ']': # OSC
      let c = term.consumeIntUntil(';')
      var n: int
      if c == 4:
        n = term.consumeIntUntil(';')
      if term.readChar() == 'r' and term.readChar() == 'g' and
          term.readChar() == 'b':
        term.expect ':'
        let r = term.eatColor('/')
        let g = term.eatColor('/')
        let b = term.eatColor('\e')
        let C = rgb(r, g, b)
        if c == 4:
          result.colorMap.add((n, C))
        elif c == 10:
          result.fgcolor = some(C)
        else: # 11
          result.bgcolor = some(C)
      else:
        # not RGB, give up
        term.skipUntilST()
    of 'P': # DCS
      let c = term.readChar()
      if c notin {'0', '1'}:
        fail
      term.expect '+'
      term.expect 'r'
      if c == '1':
        var id = 0
        while (let c = term.readChar(); c != '='):
          if c notin AsciiHexDigit:
            fail
          id *= 0x10
          id += hexValue(c)
        if id == tcapRGB:
          result.attrs.incl(qaRGB)
      term.skipUntilST()
    of '_': # APC
      term.expect 'G'
      result.attrs.incl(qaKittyImage)
      term.skipUntilST()
    else:
      fail

type TermStartResult* = enum
  tsrSuccess, tsrDA1Fail

# Built-in terminal capability database.
#
# In an ideal world, none of this would be necessary as we could just
# get capabilities from the terminal itself.  Alas, some insist on
# terminfo being the sole source of "reliable" information (it isn't),
# so we must emulate it to some extent.
#
# In general, terminal attributes that we can detect with queries are
# omitted.  Some terminals only set COLORTERM, but do not respond to
# queries; this may not propagate through SSH, so we still check TERM
# for these.
#
# For terminals I cannot directly test, our data is based on
# TERMINALS.md in notcurses and terminfo.src in ncurses.
type
  TermFlag = enum
    tfTitle, tfDa1, tfSmcup, tfBleedsAPC, tfAnsiColor, tfEightBitColor,
    tfTrueColor, tfSixel

  Termdesc = set[TermFlag]

# Probably not 1:1 compatible, but either a) compatible enough for our
# purposes or b) advertises incompatibilities correctly through queries.
# Descriptions with XtermCompatible (and no extra flags) are redundant;
# I'm including them only to have a list of terminals already tested.
const XtermCompatible = {tfTitle, tfDa1, tfSmcup}

const TermdescMap = [
  ttAdm3a: {},
  ttAlacritty: XtermCompatible + {tfTrueColor},
  ttContour: XtermCompatible,
  ttDvtm: {tfSmcup, tfBleedsAPC, tfAnsiColor},
  ttEat: XtermCompatible + {tfTrueColor},
  ttEterm: {tfTitle, tfDa1, tfAnsiColor},
  ttFbterm: {tfDa1, tfAnsiColor},
  ttFoot: XtermCompatible,
  ttFreebsd: {tfAnsiColor},
  ttGhostty: XtermCompatible,
  ttIterm2: XtermCompatible,
  ttKitty: XtermCompatible + {tfTrueColor},
  ttKonsole: XtermCompatible,
  # Linux accepts true color or eight bit sequences, but as per the
  # man page they are "shoehorned into 16 colors".  This breaks color
  # correction, so we stick to ANSI.
  # It also fails to advertise ANSI color in DA1, so we set it here.
  ttLinux: {tfDa1, tfSmcup, tfAnsiColor},
  ttMintty: XtermCompatible + {tfTrueColor},
  ttMlterm: XtermCompatible + {tfTrueColor},
  ttMsTerminal: XtermCompatible + {tfTrueColor},
  ttPutty: XtermCompatible + {tfTrueColor},
  ttRio: XtermCompatible,
  ttRlogin: XtermCompatible + {tfTrueColor},
  ttRxvt: XtermCompatible + {tfBleedsAPC, tfEightBitColor},
  # screen does true color, but only if you explicitly enable it.
  # smcup is also opt-in; however, it should be fine to send it even if
  # it's not used.
  ttScreen: XtermCompatible + {tfEightBitColor},
  ttSt: XtermCompatible + {tfTrueColor},
  # SyncTERM supports Sixel, but it doesn't have private color registers
  # so we omit it.
  ttSyncterm: XtermCompatible + {tfTrueColor},
  ttTerminology: XtermCompatible + {tfBleedsAPC},
  ttTmux: XtermCompatible + {tfTrueColor},
  # Direct color in urxvt is not really true color; apparently it
  # just takes the nearest color of the 256 registers and replaces it
  # with the direct color given.  I don't think this is much worse than
  # our basic quantization for 256 colors, so we use it anyway.
  ttUrxvt: XtermCompatible + {tfBleedsAPC, tfTrueColor},
  # The VT100 had DA1, but couldn't gracefully consume unknown sequences.
  ttVt100: {tfSmcup},
  ttVt52: {},
  ttVte: XtermCompatible + {tfTrueColor},
  ttWezterm: XtermCompatible,
  ttWterm: XtermCompatible + {tfTrueColor},
  ttXfce: XtermCompatible + {tfTrueColor},
  ttXst: XtermCompatible + {tfTrueColor},
  ttXterm: XtermCompatible,
  # yaft supports Sixel, but can't tell us so in DA1.
  ttYaft: XtermCompatible + {tfBleedsAPC, tfSixel},
  # zellij supports Sixel, but doesn't advertise it.
  # However, the feature barely works, so we don't force it here.
  ttZellij: XtermCompatible + {tfTrueColor},
]

# Parse TERM variable.  This may adjust color-mode.
proc parseTERM(term: Terminal): TerminalType =
  var s = getEnvEmpty("TERM", "xterm")
  # Sometimes, TERM variables contain:
  # -{n}color to denote the number of color registers
  # -direct[n] to denote direct colors (n is irrelevant here)
  # (in terminfo.src from ncurses at least...)
  if s.endsWith("color"):
    let i = s.rfind('-')
    if i != -1:
      let n = parseInt32(s.toOpenArray(i + 1, s.high - "color".len)).get(-1)
      if n == 256:
        term.colorMode = cmEightBit
      elif n >= 16:
        term.colorMode = cmANSI
      s.setLen(i)
  else:
    var i = s.high
    while i >= 0 and s[i] in AsciiDigit:
      dec i
    if s.substr(0, i).endsWith("-direct"):
      term.colorMode = cmTrueColor
      s.setLen(i + 1 - "-direct".len)
  # XTerm is the universal fallback.
  var res = strictParseEnum[TerminalType](s).get(ttXterm)
  # some screen versions use screen.{actual-terminal}, but we don't
  # really care about the actual terminal.
  if s.startsWith("screen."):
    res = ttScreen
  # tmux says it's screen, but it isn't.
  if res == ttScreen and getEnv("TMUX") != "":
    return ttTmux
  # zellij says it's its underlying terminal, but it isn't.
  if getEnv("ZELLIJ") != "":
    return ttZellij
  return res

proc applyTermDesc(term: Terminal; desc: Termdesc) =
  if tfAnsiColor in desc:
    term.colorMode = cmANSI
  elif tfEightBitColor in desc:
    term.colorMode = cmEightBit
  elif tfTrueColor in desc:
    term.colorMode = cmTrueColor
  if tfSixel in desc:
    term.imageMode = imSixel
  term.setTitle = tfTitle in desc
  term.smcup = tfSmcup in desc
  case term.termType
  of ttAdm3a: term.margin = true
  of ttVt52: discard
  of ttVt100: term.formatMode = {ffReverse}
  else:
    # Unless a terminal can't process one of these, it's OK to enable
    # all of them.
    term.formatMode = {FormatFlag.low..FormatFlag.high}
  term.queryDa1 = tfDa1 in desc
  term.bleedsAPC = tfBleedsAPC in desc

# when windowOnly, only refresh window size.
proc detectTermAttributes(term: Terminal; windowOnly: bool): TermStartResult =
  var res = tsrSuccess
  if not term.isatty():
    return res
  var win: IOctl_WinSize
  if ioctl(term.istream.fd, TIOCGWINSZ, addr win) != -1:
    if win.ws_col > 0:
      term.attrs.width = int(win.ws_col)
      term.attrs.ppc = int(win.ws_xpixel) div term.attrs.width
    if win.ws_row > 0:
      term.attrs.height = int(win.ws_row)
      term.attrs.ppl = int(win.ws_ypixel) div term.attrs.height
  if term.attrs.width == 0:
    term.attrs.width = parseIntP(getEnv("COLUMNS")).get(0)
  if term.attrs.height == 0:
    term.attrs.height = parseIntP(getEnv("LINES")).get(0)
  if not windowOnly:
    # set tname here because queryAttrs depends on it
    term.termType = term.parseTERM()
    term.applyTermDesc(TermdescMap[term.termType])
  if term.queryDa1 and term.config.display.queryDa1:
    let r = term.queryAttrs(windowOnly)
    if r.success: # DA1 success
      if r.width != 0:
        term.attrs.width = r.width
        if r.ppc != 0:
          term.attrs.ppc = r.ppc
        elif r.widthPx != 0:
          term.attrs.ppc = r.widthPx div r.width
      if r.height != 0:
        term.attrs.height = r.height
        if r.ppl != 0:
          term.attrs.ppl = r.ppl
        elif r.heightPx != 0:
          term.attrs.ppl = r.heightPx div r.height
      if not windowOnly: # we don't check for kitty, so don't override this
        if qaKittyImage in r.attrs:
          term.imageMode = imKitty
        elif qaSixel in r.attrs:
          term.imageMode = imSixel
      if term.imageMode == imSixel: # adjust after windowChange
        if r.registers != 0:
          # I need at least 2 registers, and can't do anything with more
          # than 101 ^ 3.
          # In practice, terminals I've seen have between 256 - 65535; for now,
          # I'll stick with 65535 as the upper limit, because I have no way
          # to test if encoding time explodes with more or something.
          term.sixelRegisterNum = clamp(r.registers, 2, 65535)
        if term.sixelRegisterNum == 0:
          # assume 256 - tell me if you have more.
          term.sixelRegisterNum = 256
      if windowOnly:
        return res
      if qaAnsiColor in r.attrs and term.colorMode < cmANSI:
        term.colorMode = cmANSI
      if qaRGB in r.attrs:
        term.colorMode = cmTrueColor
      if term.termType == ttSyncterm:
        # Ask SyncTERM to stop moving the cursor on EOL.
        term.write(static(CSI & "=5h"))
      if r.bgcolor.isSome:
        term.defaultBackground = r.bgcolor.get
      if r.fgcolor.isSome:
        term.defaultForeground = r.fgcolor.get
      for (n, rgb) in r.colorMap:
        term.colorMap[n] = rgb
    else:
      term.sixelRegisterNum = 256
      # something went horribly wrong. set result to DA1 fail, pager will
      # alert the user
      res = tsrDA1Fail
  if term.margin:
    dec term.attrs.width
  if windowOnly:
    return res
  if term.colorMode != cmTrueColor:
    let colorterm = getEnv("COLORTERM")
    if colorterm in ["24bit", "truecolor"]:
      term.colorMode = cmTrueColor
  return res

proc windowChange*(term: Terminal) =
  term.istream.setBlocking(true)
  term.ostream.setBlocking(true)
  discard term.detectTermAttributes(windowOnly = true)
  term.applyConfigDimensions()
  term.canvas = newSeq[FixedCell](term.attrs.width * term.attrs.height)
  term.lineDamage = newSeq[int](term.attrs.height)
  term.clearCanvas()
  term.istream.setBlocking(false)
  term.ostream.setBlocking(false)

proc initScreen(term: Terminal) =
  # note: deinit happens in quit()
  if term.setTitle:
    term.write(PushTitle)
  if term.smcup:
    term.write(term.enableAltScreen())
  if term.config.input.useMouse:
    term.enableMouse()
  if term.config.input.bracketedPaste:
    term.enableBracketedPaste()
  term.cursorx = -1
  term.cursory = -1
  term.istream.setBlocking(false)
  term.ostream.setBlocking(false)

proc start*(term: Terminal; istream: PosixStream;
    registerCb: (proc(fd: int) {.raises: [].})): TermStartResult =
  term.istream = istream
  term.registerCb = registerCb
  if term.isatty():
    term.enableRawMode()
  result = term.detectTermAttributes(windowOnly = false)
  if result == tsrDA1Fail:
    term.queryDa1 = false
  term.applyConfig()
  if term.isatty():
    term.initScreen()
  term.canvas = newSeq[FixedCell](term.attrs.width * term.attrs.height)
  term.lineDamage = newSeq[int](term.attrs.height)

proc restart*(term: Terminal) =
  if term.isatty():
    term.enableRawMode()
    term.initScreen()

const ANSIColorMap = [
  rgb(0, 0, 0),
  rgb(205, 0, 0),
  rgb(0, 205, 0),
  rgb(205, 205, 0),
  rgb(0, 0, 238),
  rgb(205, 0, 205),
  rgb(0, 205, 205),
  rgb(229, 229, 229),
  rgb(127, 127, 127),
  rgb(255, 0, 0),
  rgb(0, 255, 0),
  rgb(255, 255, 0),
  rgb(92, 92, 255),
  rgb(255, 0, 255),
  rgb(0, 255, 255),
  rgb(255, 255, 255)
]

proc newTerminal*(ostream: PosixStream; config: Config): Terminal =
  const DefaultBackground = namedRGBColor("black").get
  const DefaultForeground = namedRGBColor("white").get
  return Terminal(
    ostream: ostream,
    config: config,
    defaultBackground: DefaultBackground,
    defaultForeground: DefaultForeground,
    colorMap: ANSIColorMap,
    termType: ttXterm
  )

{.pop.} # raises: []
