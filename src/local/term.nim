{.push raises: [].}

import std/options
import std/os
import std/posix
import std/termios

import chagashi/charset
import chagashi/decoder
import chagashi/encoder
import config/config
import config/conftypes
import io/dynstream
import types/bitmap
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
    ttVertigo = "vertigo" # pretends to be XTerm
    ttVt100 = "vt100"
    ttVt100Nav = "vt100-nav" # VT100 without advanced video
    ttVt420 = "vt420"
    ttVt52 = "vt52"
    ttVte = "vte" # pretends to be XTerm
    ttWezterm = "wezterm"
    ttWterm = "wterm"
    ttXst = "xst"
    ttXterm = "xterm"
    ttYaft = "yaft"
    ttZellij = "zellij" # pretends to be its underlying terminal

  CanvasImageDimensions* = object
    # relative position on screen (in cells, may be negative)
    x: int
    y*: int
    # relative position on screen (in pixels, may be negative)
    xpx: int
    ypx: int
    # original dimensions (after resizing)
    width*: int
    height*: int
    # offset (crop start)
    offx*: int
    offy: int
    # kitty only: X/Y offset *inside* cell. (TODO implement for sixel too)
    # has nothing to do with offx/offy.
    offx2: int
    offy2: int
    # size cap (crop end)
    # Note: this 0-based, so the final display size is
    # (dispw - offx, disph - offy)
    dispw*: int
    disph: int
    # absolute x, y in container
    rx: int
    ry: int
    # Sixel only: erry is the y deviation from 6 lines.
    # erry2 is the same, but it's not affected by scroll.
    erry*: int
    erry2*: int

  CanvasImage* = ref object
    pid: int
    bmp*: NetworkBitmap
    dims*: CanvasImageDimensions
    damaged*: bool
    transparent: bool
    scrolled: bool # sixel only: set if screen was scrolled since printing
    preludeLen: int
    kittyId: uint
    data: Blob
    next: CanvasImage

  TerminalPage {.acyclic.} = ref object
    a: seq[char] # bytes to flush
    n: int # bytes of s already flushed
    next: TerminalPage

  TermdescFlag = enum # 16 bits, 1 free
    tfTitle # can set window title
    tfPreEcma48 # does not support ECMA-48/VT100-like queries (DA1 etc.)
    tfXtermQuery # supports XTerm-like queries (background color etc.)
    tfAltScreen # has alt screen
    tfBleedsAPC # cannot handle APC
    tfColor1 # tfColor1: ANSI
    tfColor2 # tfColor2: eight-bit; together with tfColor1: true-color
    tfSixel # known to support Sixel (and doesn't advertise it)
    tfSpecialGraphics # supports DEC special graphics
    tfMargin # needs a 1-char margin at the right edge
    tfMouse # supports SGR mouse
    tfPrimary # interprets primary correctly in OSC 52
    tfBracketedPaste # doesn't choke on bracketed paste (might not have it)
    tfFlowControl # uses XON/XOFF flow control (usually hardware terminals)
    tfScroll # supports VT100-style scroll (with scroll area)
    tfFastScroll # has SD/SU control sequences

  Termdesc = set[TermdescFlag]

  FrameType = enum
    ftCurrent # non-discardable
    ftNext # discardable

  Frame = object
    head: TerminalPage # output buffer queue
    tail: TerminalPage # last output buffer
    canvasImagesHead: CanvasImage
    canvas: seq[FixedCell]
    kittyImagesToClear: seq[uint] # Kitty only; vector of image ids
    lineDamage: seq[int]
    title: string # current title
    pos: tuple[pid, x, y: int]
    scrollTodo: int # lines to scroll (negative = up, positive = down)
    scrollBottom: int # last line of currently set scroll area (-1 if reset)
    format: Format # current formatting
    cursorx: uint32
    cursory: uint32
    cursorKnown: bool # set if we know the cursor's position
    fastScrollTodo: bool # flag to do fast scroll
    queueTitleFlag: bool # set title on next draw
    mouseEnabled: bool
    specialGraphics: bool # flag for special graphics processing
    cursorHidden: bool

  Terminal* = ref object
    termType: TerminalType
    cs*: Charset
    te: TextEncoder
    config: Config
    istream*: PosixStream
    ostream*: PosixStream
    tdctx: TextDecoderContext
    eparser: EventParser
    canvasImagesTmpHead: CanvasImage # temp list during rescan
    canvasImagesTmpTail: CanvasImage
    attrs*: WindowAttributes
    formatMode: set[FormatFlag]
    imageMode*: ImageMode
    cleared: bool
    asciiOnly: bool
    osc52Copy: bool
    osc52Primary*: bool
    ttyFlag: bool
    registeredFlag*: bool # kernel won't accept any more data right now
    desc: Termdesc
    origTermios: Termios
    newTermios: Termios
    defaultBackground: RGBColor
    defaultForeground: RGBColor
    ibuf: array[256, char] # buffer for chars when we can't process them
    ibufLen: int # len of ibuf
    ibufn: int # position in ibuf
    dynbuf: string # buffer for UTF-8 text input by the user, for areadChar
    dynbufn: int # position in dynbuf
    frames: array[FrameType, Frame]
    frameType: FrameType
    registerCb: proc(fd: int) {.raises: [].} # callback to register ostream
    sixelRegisterNum*: uint16
    kittyId: uint # counter for kitty image (*not* placement) ids.
    colorMap: array[16, RGBColor]

  QueryState = enum
    qsBackgroundColor, qsForegroundColor, qsXtermAllowedOps, qsXtermWindowOps,
    qsKitty, qsColorRegisters, qsTcapRGB, qsANSIColor, qsDA1, qsCellSize,
    qsWindowPixels, qsCPR, qsNone

  EventState = enum
    esNone = ""
    esEsc = "\e"
    esCSI = "\e["
    esCSIQMark = "\e[?"
    esCSIEquals = "\e[="
    esCSINum = "\e["
    esBracketed = ""
    esBracketedEsc = "\e"
    esBracketedCSI = "\e["
    esBracketedCSI2 = "\e[2"
    esBracketedCSI20 = "\e[20"
    esBracketedCSI201 = "\e[201"
    esCSILt = "\e[<"
    esOSC = "\e]"
    esOSC6 = "\e]6"
    esOSC60 = "\e]60"
    esOSC60Semi = "\e]60;"
    esOSC61 = "\e]61"
    esOSC61Semi = "\e]61;"
    esOSC4 = "\e]4"
    esOSC4Semi = "\e]4;"
    esOSC4SemiNum
    esOSC1 = "\e]1"
    esOSC10 = "\e]10"
    esOSC10Semi = "\e]10;"
    esOSC11 = "\e]11"
    esOSC11Semi = "\e]11;"
    esDCS = "\eP"
    esDCS0 = "\eP0"
    esDCS0Plus = "\eP0+"
    esDCS1 = "\eP1"
    esDCS1Plus = "\eP1+"
    esDCS1PlusR = "\eP1+r"
    esAPC = "\e_"
    esAPCG = "\e_G"
    esSTEsc = "\e"
    esSkipToST
    esBacktrack

  EventParser = object
    state: EventState
    # queryState signifies where we are in the query.  Escape sequences for
    # queries that we've a) already seen or b) come before queries we've
    # already seen are not detected.  e.g. queryState = qsCellSize implies
    # the next response must be a cell size response or anything that comes
    # after that.  DA1 is the last query as it seems to be universally
    # emulated.
    queryState: QueryState
    keyLen: int8
    flag: bool
    colorState: uint8
    num: uint32
    backtrackStack: seq[char]
    nums: seq[uint32] # buffer for numeric parameters
    # It is possible that we need to send a query before the previous one
    # ends; in that case, we just put the next desired query state on this
    # stack and restart as soon as we receive all responses to the previous
    # query.
    queryStateStack: seq[QueryState]
    buf: string # string buffer

  InputEventType* = enum
    ietKey = "key"
    ietKeyEnd = "keyEnd"
    ietPaste = "paste"
    ietMouse = "mouse"
    ietWindowChange = "windowChange"
    ietRedraw = "redraw"

  InputEvent* = object
    case t*: InputEventType
    of ietKey: # key press - UTF-8 bytes
      c*: char
    of ietKeyEnd: # key press done (if not in bracketed paste mode)
      discard
    of ietPaste: # bracketed paste done
      discard
    of ietWindowChange: # window changed through query
      discard
    of ietRedraw: # must redraw because of query (e.g. Sixel detected)
      discard
    of ietMouse:
      m*: MouseInput

  MouseInputType* = enum
    mitPress = "press", mitRelease = "release", mitMove = "move"

  MouseInputMod* = enum
    mimShift = "shift", mimCtrl = "ctrl", mimMeta = "meta"

  MouseButton* = enum
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

  MouseInputPosition* = tuple[x, y: int32]

  MouseInput* = object
    t*: MouseInputType
    button*: MouseButton
    mods*: set[MouseInputMod]
    pos*: MouseInputPosition

# Forward declarations
proc windowChange(term: Terminal)
proc updateCanvasImage(term: Terminal; image: CanvasImage;
  dims: CanvasImageDimensions; maxh: int): bool
proc clearImages*(term: Terminal; maxh: int)

# Built-in terminal capability database.
#
# In an ideal world, none of this would be necessary as we could just get
# capabilities from the terminal itself.  Alas, some insist on terminfo
# being the sole source of "reliable" information (it's not reliable...), so
# we must emulate it to some extent.
#
# In general, terminal attributes that we can detect with queries are
# omitted.  Some terminals only set COLORTERM, but do not respond to
# queries; this may not propagate through SSH, so we still check TERM for
# these.
#
# For terminals I cannot directly test, our data is based on TERMINALS.md in
# notcurses and terminfo.src in ncurses.
#
# XtermCompatible: probably not 1:1 compatible, but either a) compatible
# enough for our purposes or b) advertises incompatibilities correctly
# through queries.  Descriptions with XtermCompatible and no extra flags
# are redundant; I'm including them only to have a list of terminals already
# tested.
#
# Note: we intentionally do not include tfPrimary here, because some poorly
# written terminals choke on it despite advertising themselves as XTerm.
const XtermCompatible = {
  tfTitle, tfXtermQuery, tfAltScreen, tfSpecialGraphics, tfMouse,
  tfBracketedPaste, tfScroll, tfFastScroll
}

# This for hardware terminals, *not* VT100-compatible emulators.
# The primary difference is that no emulator uses flow control (XON/XOFF)
# so we just disable it on those.
const Vt100Compatible = {
  tfScroll, tfSpecialGraphics, tfFlowControl
}

const AnsiColorFlag = {tfColor1}
const EightBitColorFlag = {tfColor2}
const TrueColorFlag = {tfColor1, tfColor2}

const TermdescMap = [
  ttAdm3a: {tfMargin, tfPreEcma48},
  ttAlacritty: XtermCompatible + TrueColorFlag,
  ttContour: XtermCompatible,
  ttDvtm: {tfAltScreen, tfBleedsAPC, tfBracketedPaste} + AnsiColorFlag,
  ttEat: XtermCompatible + TrueColorFlag,
  # eterm bleeds titles.
  ttEterm: {tfXtermQuery, tfBracketedPaste, tfScroll} + AnsiColorFlag,
  ttFbterm: {tfXtermQuery, tfBracketedPaste} + AnsiColorFlag,
  ttFoot: XtermCompatible,
  # FreeBSD has code to respond to queries, but it's #if 0'd out :(
  # It has no bracketed paste (duh).
  ttFreebsd: {tfPreEcma48, tfScroll} + AnsiColorFlag,
  ttGhostty: XtermCompatible,
  ttIterm2: XtermCompatible,
  ttKitty: XtermCompatible + TrueColorFlag + {tfPrimary},
  ttKonsole: XtermCompatible,
  # Linux accepts true color or eight bit sequences, but as per the
  # man page they are "shoehorned into 16 colors".  This breaks color
  # correction, so we stick to ANSI.
  # It also fails to advertise ANSI color in DA1, so we set it here.
  # Linux has no alt screen, and no paste (let alone bracketed).
  ttLinux: {tfXtermQuery, tfScroll} + AnsiColorFlag,
  ttMintty: XtermCompatible + TrueColorFlag,
  ttMlterm: XtermCompatible + TrueColorFlag,
  ttMsTerminal: XtermCompatible + TrueColorFlag,
  ttPutty: XtermCompatible + TrueColorFlag,
  ttRio: XtermCompatible,
  ttRlogin: XtermCompatible + TrueColorFlag,
  ttRxvt: XtermCompatible + {tfBleedsAPC} + EightBitColorFlag,
  # screen does true color, but only if you explicitly enable it.
  # The alt screen is also opt-in.
  ttScreen: XtermCompatible - {tfAltScreen} + EightBitColorFlag,
  ttSt: XtermCompatible + TrueColorFlag,
  # SyncTERM supports Sixel, but it doesn't have private color registers
  # so we omit it.
  ttSyncterm: XtermCompatible + TrueColorFlag + {tfMargin},
  ttTerminology: XtermCompatible + {tfBleedsAPC},
  # Scrolling on tmux destroys images.
  ttTmux: XtermCompatible + TrueColorFlag - {tfScroll},
  # Direct color in urxvt is not really true color; apparently it
  # just takes the nearest color of the 256 registers and replaces it
  # with the direct color given.  I don't think this is much worse than
  # our basic quantization for 256 colors, so we use it anyway.
  ttUrxvt: XtermCompatible + {tfBleedsAPC} + TrueColorFlag,
  ttVertigo: XtermCompatible + TrueColorFlag,
  ttVt100: Vt100Compatible,
  ttVt100Nav: Vt100Compatible,
  ttVt420: Vt100Compatible + {tfFastScroll},
  ttVt52: {tfPreEcma48, tfFlowControl},
  ttVte: XtermCompatible + TrueColorFlag,
  ttWezterm: XtermCompatible,
  ttWterm: XtermCompatible + TrueColorFlag,
  ttXst: XtermCompatible + TrueColorFlag,
  ttXterm: XtermCompatible,
  # yaft supports Sixel, but can't tell us so in DA1.
  ttYaft: XtermCompatible + {tfSixel, tfBleedsAPC} -
    {tfAltScreen, tfFastScroll},
  # zellij advertises Sixel, but it's completely broken.
  ttZellij: XtermCompatible + TrueColorFlag,
]

# reverse index (cursor up)
const RI = "\eM"

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

# number of color registers
const QueryColorRegisters = CSI & "?1;1;0S"

# report active position
const QueryCursorPosition = CSI & "6n"

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

const QueryXtermAllowedOps = OSC & "60" & ST
const QueryXtermWindowOps = OSC & "61;allowWindowOps" & ST

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

const SetBracketedPaste = DECSET(2004)
const ResetBracketedPaste = DECRST(2004)
const BracketedPasteStart* = CSI & "200~"
const BracketedPasteEnd* = CSI & "201~"

# show/hide cursor
const ShowCursor = DECSET(25)
const HideCursor = DECRST(25)

# application program command
const APC = "\e_"

const KittyQuery = APC & "Gi=1,s=1,v=1,a=q;AAAAAA" & ST

iterator canvasImages(frame: Frame): CanvasImage =
  var image = frame.canvasImagesHead
  while image != nil:
    yield image
    image = image.next

template frame(term: Terminal): Frame =
  term.frames[term.frameType]

proc clone(image: CanvasImage): CanvasImage =
  let image2 = CanvasImage()
  image2[] = image[]
  image2.next = nil
  image2

# Frame skipping.
#
# Conceptually, we have a FIFO queue of frames coming in, with all
# frames that aren't partially flushed being discardable.  (Theoretically
# we could also discard partially flushed frames, but this sounds like a
# nightmare to implement with minimal benefits.)
#
# In practice, we don't need an actual queue, this can be implemented as
# a two-element array of frames:
# * ftCurrent is the frame currently being written; we only ever write data
#   from here.
# * ftNext is a buffered frame, which starts out with a copy of ftCurrent's
#   state when we start drawing despite ftCurrent not being fully flushed.
#   Then:
#   - If we start drawing again and ftCurrent is *still* not flushed,
#     we drop ftNext in favor of this new frame.
#   - Once ftCurrent is fully flushed, we "move" ftNext into ftCurrent's
#     place.
proc swapFrame(term: Terminal; frameType: FrameType) =
  let ot = if frameType == ftCurrent: ftNext else: ftCurrent
  term.frameType = frameType
  case frameType
  of ftCurrent:
    # Unbuffer.  It's fine to destructively read the old canvas here.
    term.frame.head = move(term.frames[ftNext].head)
    term.frame.tail = move(term.frames[ftNext].tail)
    swap(term.frame.canvas, term.frames[ot].canvas)
    swap(term.frame.lineDamage, term.frames[ot].lineDamage)
    swap(term.frame.kittyImagesToClear, term.frames[ot].kittyImagesToClear)
    # could swap this too, but that would keep data alive for longer than
    # desirable
    term.frame.canvasImagesHead = move(term.frames[ot].canvasImagesHead)
  of ftNext:
    # Buffer.  We keep the old canvas intact in ftCurrent for the case where
    # we get a new frame before this frame becomes active (and this frame
    # is dropped).
    term.frame.head = nil
    term.frame.tail = nil
    for i in 0 ..< term.frames[ot].canvas.len:
      term.frame.canvas[i] = term.frames[ot].canvas[i]
    chaArrayCopy(term.frame.lineDamage, term.frames[ot].lineDamage)
    #TODO we could avoid some allocations here by reusing CanvasImage
    # objects from the frame to be dropped
    var imagesHead: CanvasImage = nil
    var imagesTail: CanvasImage = nil
    for image in term.frames[ot].canvasImages:
      let image2 = image.clone()
      if imagesTail == nil:
        imagesHead = image2
      else:
        imagesTail.next = image2
      imagesTail = image2
    term.frame.kittyImagesToClear = term.frames[ot].kittyImagesToClear
    term.frame.canvasImagesHead = imagesHead
  term.frame.title = term.frames[ot].title
  term.frame.format = term.frames[ot].format
  term.frame.pos = term.frames[ot].pos
  term.frame.cursorx = term.frames[ot].cursorx
  term.frame.cursory = term.frames[ot].cursory
  term.frame.cursorKnown = term.frames[ot].cursorKnown
  term.frame.scrollTodo = term.frames[ot].scrollTodo
  term.frame.scrollBottom = term.frames[ot].scrollBottom
  term.frame.fastScrollTodo = term.frames[ot].fastScrollTodo
  term.frame.queueTitleFlag = term.frames[ot].queueTitleFlag
  term.frame.mouseEnabled = term.frames[ot].mouseEnabled
  term.frame.specialGraphics = term.frames[ot].specialGraphics
  term.frame.cursorHidden = term.frames[ot].cursorHidden

# Must be called at the start of draw().
proc initFrame*(term: Terminal) =
  if term.frame.tail != nil:
    # Started drawing while another frame is not done.
    # We copy ftCurrent to ftNext; this clones (buffers) the current frame,
    # dropping the previous buffered frame (if any).
    term.swapFrame(ftNext)
  term.frame.scrollTodo = 0
  term.frame.fastScrollTodo = false

proc flush*(term: Terminal): Opt[bool] =
  while true:
    var page = term.frames[ftCurrent].head
    if page == nil:
      assert term.frameType != ftNext
    while page != nil:
      var n = page.n
      let H = page.a.len - 1
      while n < page.a.len:
        let m = term.ostream.write(page.a.toOpenArray(n, H))
        if m < 0:
          let e = errno
          if e != EAGAIN and e != EWOULDBLOCK and e != EINTR:
            return err()
          break
        n += m
      if n < page.a.len:
        page.n = n
        break
      page = page.next
    term.frames[ftCurrent].head = page
    if page != nil: # not done
      return ok(false)
    term.frames[ftCurrent].tail = nil
    if term.frameType == ftCurrent:
      break # flushed all
    term.swapFrame(ftCurrent)
  ok(true)

proc startFlush(term: Terminal): Opt[void] =
  if term.registeredFlag:
    return ok()
  if not ?term.flush():
    term.registerCb(int(term.ostream.fd))
    term.registeredFlag = true
  ok()

# Arbitrary buffer size; data is flushed once we exceed it.
const BufferSize = 4096

proc write(term: Terminal; s: openArray[char]): Opt[void] =
  if s.len <= 0:
    return ok()
  if s.len <= BufferSize: # merge small writes
    let tail = term.frame.tail
    if tail != nil and tail.a.len + s.len > BufferSize:
      # The buffer is full, so we'll have to flush anyway; try to do it now,
      # maybe we can at least merge this write with a subsequent one.
      ?term.startFlush()
    let page = term.frame.tail
    if page == nil:
      let page = TerminalPage(a: @s)
      term.frame.head = page
      term.frame.tail = page
      return ok()
    let olen = page.a.len
    if olen + s.len <= BufferSize:
      page.a.setLen(olen + s.len)
      copyMem(addr page.a[olen], unsafeAddr s[0], s.len)
      return ok()
  # large write, or the buffer is full.
  ?term.startFlush()
  var n = 0
  if term.frames[ftCurrent].head == nil:
    while n < s.len:
      let m = term.ostream.write(s.toOpenArray(n, s.high))
      if m < 0:
        let e = errno
        if e != EAGAIN and e != EWOULDBLOCK and e != EINTR:
          return err()
        break
      n += m
  if n < s.len:
    let page = TerminalPage()
    if term.frame.tail == nil:
      term.frame.head = page
      term.frame.tail = page
      if term.frameType == ftCurrent: # no need to register next
        term.registerCb(int(term.ostream.fd))
        term.registeredFlag = true
    else:
      term.frame.tail.next = page
      term.frame.tail = page
    page.a = @(s.toOpenArray(n, s.high))
  ok()

proc write(term: Terminal; c: char): Opt[void] =
  term.write([c])

proc readChar(term: Terminal): Opt[char] =
  if term.ibufn == term.ibufLen:
    term.ibufn = 0
    term.ibufLen = term.istream.read(term.ibuf)
    if term.ibufLen == -1:
      return err()
  result = ok(term.ibuf[term.ibufn])
  inc term.ibufn

proc blockIO0(term: Terminal) =
  term.istream.setBlocking(true)
  term.ostream.setBlocking(true)

proc blockIO(term: Terminal): Opt[void] =
  term.istream.setBlocking(true)
  term.ostream.setBlocking(true)
  doAssert ?term.flush()
  ok()

proc unblockIO(term: Terminal) =
  term.istream.setBlocking(false)
  term.ostream.setBlocking(false)

proc ahandleRead*(term: Terminal): Opt[bool] =
  term.ibufn = 0
  term.ibufLen = term.istream.read(term.ibuf)
  if term.ibufLen < 0:
    let e = errno
    if e != EAGAIN and e != EWOULDBLOCK and e != EINTR:
      term.blockIO0()
      return err()
    term.ibufLen = 0
    return ok(false)
  ok(true)

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
  var s = $eparser.state
  for i, num in eparser.nums:
    if i != 0:
      s &= ';'
    s &= $num
  eparser.nums.setLen(0)
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

proc nextState(eparser: var EventParser; c, cc: char; state: EventState) =
  if c == cc:
    eparser.state = state
  else:
    eparser.backtrack(cc)

proc nextState(eparser: var EventParser; qs: QueryState; cc: char;
    state: EventState) =
  if eparser.queryState <= qs:
    eparser.state = state
    let qs = qs.succ
    eparser.queryState = qs
    if qs == qsNone and eparser.queryStateStack.len > 0:
      eparser.queryState = eparser.queryStateStack.pop()
  else:
    eparser.backtrack(cc)

proc nextStateScreenBug(term: Terminal; qs: QueryState; cc: char;
    state: EventState) =
  if term.eparser.queryState > qs and term.termType == ttScreen:
    # Work around a GNU screen 5.0.1 bug where we get foreground/background
    # color out of order.
    term.eparser.state = state
  else:
    term.eparser.nextState(qs, cc, state)

proc nextStateSameQuery(eparser: var EventParser; qs: QueryState; cc: char;
    state: EventState) =
  # like above, but here we can have more responses of the same query type
  # so we don't immediately jump to the next query state
  if eparser.queryState <= qs:
    eparser.state = state
    eparser.queryState = qs
  else:
    eparser.backtrack(cc)

proc parseNum(eparser: var EventParser; c: char): bool =
  let num = eparser.num
  if c in AsciiDigit:
    # this may overflow, but it's not really a problem
    eparser.num = (num * 10) + uint32(c) - uint32('0')
    return true
  eparser.nums.add(num)
  eparser.num = 0
  return c == ';'

proc parseST(eparser: var EventParser; c: char): bool =
  if c == '\a':
    # XTerm-specific response; although XTerm doesn't actually send it if
    # you didn't ask for it (and we don't), some other terminals do (st in
    # particular).
    eparser.state = esNone
    return true
  elif c == '\e':
    eparser.state = esSTEsc
    return true
  false

proc parseMouseInput(eparser: var EventParser; t: MouseInputType;
    input: var MouseInput): Opt[void] =
  if eparser.nums.len != 3:
    eparser.nums.setLen(0)
    return err()
  let btn = eparser.nums[0]
  let x = eparser.nums[1]
  let y = eparser.nums[2]
  eparser.nums.setLen(0)
  if btn > uint16.high or x > uint16.high or y > uint16.high:
    return err()
  input.t = t
  input.pos = (int32(x) - 1, int32(y) - 1)
  if (btn and 4) != 0:
    input.mods.incl(mimShift)
  if (btn and 8) != 0:
    input.mods.incl(mimMeta)
  if (btn and 16) != 0:
    input.mods.incl(mimCtrl)
  if (btn and 32) != 0:
    input.t = mitMove # override
  var button = (btn and 3) + 1
  if (btn and 64) != 0:
    button += 3
  if (btn and 128) != 0:
    button += 7
  if button notin uint32(MouseButton.low)..uint32(MouseButton.high):
    return err()
  input.button = MouseButton(button)
  ok()

proc parseColor(eparser: var EventParser; c: char): bool =
  var num = eparser.num
  eparser.num = 0
  let v0 = hexValue(c)
  if v0 == -1:
    eparser.colorState = 0
    eparser.nums.add(num)
    return c == '/'
  let v = uint8(v0)
  let i = eparser.colorState
  if i == 0: # 1st place - expand it for when we don't get a 2nd place
    num = (v shl 4) or v
    inc eparser.colorState
  elif i == 1: # 2nd place - clear expanded placeholder from 1st place
    num = (num and not 0xFu8) or v
    inc eparser.colorState
  eparser.num = num
  # all other places are irrelevant
  true

proc parseHexNum(eparser: var EventParser; c: char): bool =
  let num = eparser.num
  eparser.num = 0
  let v0 = hexValue(c)
  if v0 == -1:
    eparser.nums.add(num)
    return false
  eparser.num = num * 0x10 + uint32(v0)
  if eparser.num < num:
    eparser.num = uint32.high
  true

proc skipToST(eparser: var EventParser; c: char) =
  if eparser.parseST(c):
    discard
  else:
    eparser.state = esSkipToST

proc parseNone(term: Terminal; c: char): bool =
  if term.eparser.state != esBacktrack and c == '\e':
    inc term.eparser.state
    return false
  if term.eparser.keyLen > 0:
    dec term.eparser.keyLen
    return true
  let u = uint8(c)
  term.eparser.keyLen = if u <= 0x7F: 1i8
  elif u shr 5 == 0b110: 2i8
  elif u shr 4 == 0b1110: 3i8
  else: 4i8
  return true

proc parseEsc(eparser: var EventParser; c: char) =
  case c
  of '[': eparser.state = esCSI
  of ']': eparser.state = esOSC
  of 'P': eparser.nextState(qsTcapRGB, c, esDCS)
  of '_': eparser.nextState(qsKitty, c, esAPC)
  else: eparser.backtrack(c)

proc parseCSI(eparser: var EventParser; c: char) =
  case c
  of '<': eparser.state = esCSILt
  of '?':
    let state = if eparser.queryState <= qsColorRegisters:
      qsColorRegisters
    else:
      qsDA1
    eparser.nextState(state, c, esCSIQMark)
  of '=': eparser.nextState(qsDA1, c, esCSIEquals)
  of AsciiDigit:
    discard eparser.parseNum(c)
    eparser.state = esCSINum
  else: eparser.backtrack(c)

type EscParseResult = enum
  eprNone, eprWindowChange, eprRedraw

proc parseCSINum(term: Terminal; c: char): EscParseResult =
  if term.eparser.parseNum(c):
    return eprNone
  var changed = eprNone
  case c
  of '~': # bracketed paste
    if term.eparser.nums.len == 1 and term.eparser.nums[0] == 200:
      term.eparser.state = esBracketed
      term.eparser.nums.setLen(0)
      return eprNone
    # may be pageUp/pageDown; try to backtrack
    term.eparser.backtrack(c)
    return eprNone
  of 't': # XTWINOPS
    if term.eparser.nums.len == 3:
      let x = term.eparser.nums[2]
      let y = term.eparser.nums[1]
      if int64(x) <= int64(int.high) and int64(y) <= int64(int.high):
        let oattrs = term.attrs
        let x = int(x)
        let y = int(y)
        case term.eparser.nums[0]
        of 4:
          if not term.config.display.forcePixelsPerColumn and
              term.attrs.ppc == 0 and term.attrs.width != 0:
            term.attrs.ppc = x div term.attrs.width
            term.attrs.widthPx = term.attrs.ppc * term.attrs.width
          if not term.config.display.forcePixelsPerLine and
              term.attrs.ppl == 0 and term.attrs.height != 0:
            term.attrs.ppl = y div term.attrs.height
            term.attrs.heightPx = term.attrs.ppl * term.attrs.height
          term.eparser.queryState = qsWindowPixels.succ
        of 6:
          if not term.config.display.forcePixelsPerColumn:
            term.attrs.ppc = x
            term.attrs.widthPx = x * term.attrs.width
          if not term.config.display.forcePixelsPerLine:
            term.attrs.ppl = y
            term.attrs.heightPx = y * term.attrs.height
          term.eparser.queryState = qsCellSize.succ
        else: discard
        if term.attrs != oattrs:
          term.windowChange()
          changed = eprWindowChange
  of 'R': # CPR
    if term.eparser.nums.len == 2:
      let oattrs = term.attrs
      let x = term.eparser.nums[1]
      let y = term.eparser.nums[0]
      # if either value is 9999, we might just have a humongous terminal
      # (or CUP is implemented incorrectly)
      if x < 9999 and not term.config.display.forceColumns:
        term.attrs.width = max(int(x) - int(tfMargin in term.desc), 0)
        term.attrs.widthPx = term.attrs.width * term.attrs.ppc
      if y < 9999 and not term.config.display.forceLines:
        term.attrs.height = int(y)
        term.attrs.heightPx = term.attrs.height * term.attrs.ppl
      term.eparser.queryState = qsNone
      if term.attrs != oattrs:
        term.windowChange()
        changed = eprWindowChange
  else:
    term.eparser.backtrack(c)
    return eprNone
  term.eparser.nums.setLen(0)
  term.eparser.state = esNone
  changed

proc parseCSIQMark(term: Terminal; c: char): EscParseResult =
  if term.eparser.parseNum(c):
    return eprNone
  let colorMode = term.attrs.colorMode
  let imageMode = term.imageMode
  case c
  of 'c': # DA1
    for n in term.eparser.nums:
      case n
      of 4:
        if term.config.display.imageMode.isNone and term.imageMode == imNone and
            term.termType != ttZellij:
          # Zellij says it supports Sixel; however:
          # * on Sixel-capable terminals it somehow misplaces images.
          # * on non-Sixel-capable terminals it still emits image data (???)
          # So we blacklist it.
          term.imageMode = imSixel
      of 22:
        if term.config.display.colorMode.isNone:
          term.attrs.colorMode = max(term.attrs.colorMode, cmANSI)
      of 52:
        if term.config.input.osc52Copy.isNone:
          term.osc52Copy = true
        if tfPrimary in term.desc and term.config.input.osc52Primary.isNone:
          term.osc52Primary = true
      else: discard
  of 'S': # XTSMGRAPHICS
    if term.eparser.nums.len >= 3 and term.eparser.nums[0] == 1 and
        term.eparser.nums[1] == 0:
      let registers = term.eparser.nums[2]
      if term.config.display.sixelColors.isNone:
        term.sixelRegisterNum = uint16(clamp(registers, 2, uint16.high))
  else: discard
  term.eparser.nums.setLen(0)
  term.eparser.state = esNone
  if colorMode != term.attrs.colorMode: # windowChange implies redraw
    term.windowChange()
    return eprWindowChange
  if imageMode != term.imageMode:
    return eprRedraw
  eprNone

proc parseCSILt(eparser: var EventParser; c: char; mouse: var MouseInput):
    bool =
  # Parse a mouse event:
  # CSI < btn ; Px ; Py M (press)
  # CSI < btn ; Px ; Py m (release)
  if eparser.parseNum(c):
    return false
  eparser.state = esNone
  if c in {'m', 'M'}: # otherwise, just ignore
    let t = if c == 'M': mitPress else: mitRelease
    return eparser.parseMouseInput(t, mouse).isOk
  eparser.nums.setLen(0)
  return false

proc parseOSC(eparser: var EventParser; c: char) =
  case c
  of '6': eparser.state = esOSC6
  of '4': eparser.nextStateSameQuery(qsANSIColor, c, esOSC4)
  of '1': eparser.state = esOSC1
  else: eparser.backtrack(c)

proc parseOSC6(eparser: var EventParser; c: char) =
  case c
  of '0': eparser.nextState(qsXtermAllowedOps, c, esOSC60)
  of '1': eparser.nextState(qsXtermWindowOps, c, esOSC61)
  else: eparser.backtrack(c)

proc parseOSCNumSemi(term: Terminal; c: char): EscParseResult =
  if term.eparser.flag and term.eparser.parseColor(c):
    return eprNone
  term.eparser.flag = false
  case c
  of ':':
    let rgb = term.eparser.buf == "rgb"
    term.eparser.buf = ""
    if not rgb:
      term.eparser.state = esSkipToST
    else:
      term.eparser.flag = true
  of '\a', '\e':
    let state = term.eparser.state
    let i = if state == esOSC4SemiNum: 1 else: 0
    term.eparser.buf = ""
    discard term.eparser.parseST(c)
    if term.eparser.nums.len == i + 3:
      let n = term.eparser.nums[0]
      let r = term.eparser.nums[i]
      let g = term.eparser.nums[i + 1]
      let b = term.eparser.nums[i + 2]
      let c = rgb(uint8(r), uint8(g), uint8(b))
      term.eparser.nums.setLen(0)
      case state
      of esOSC4SemiNum:
        if n < 16:
          term.colorMap[uint8(n)] = c
      of esOSC10Semi:
        term.defaultForeground = c
      of esOSC11Semi:
        term.defaultBackground = c
        let prefersDark = term.defaultBackground.Y < 125
        if prefersDark != term.attrs.prefersDark:
          term.attrs.prefersDark = prefersDark
          term.windowChange()
          return eprWindowChange
      else: discard
      return eprRedraw
    term.eparser.nums.setLen(0)
  elif not term.eparser.flag: term.eparser.buf &= c
  else: term.eparser.skipToST(c)
  return eprNone

proc parseOSC60Semi(term: Terminal; c: char) =
  if c in {',', '\a', '\e'}:
    if term.eparser.buf.equalsIgnoreCase("allowWindowOps"):
      if term.config.input.osc52Copy.isNone:
        term.osc52Copy = true
      if term.config.input.osc52Primary.isNone:
        term.osc52Primary = true
    term.eparser.buf = ""
  case c
  of ',': term.eparser.buf = ""
  of '\a': term.eparser.state = esNone
  of '\e': term.eparser.state = esSTEsc
  else: term.eparser.buf &= c

proc parseOSC61Semi(term: Terminal; c: char) =
  if c in {',', '\a', '\e'}:
    term.eparser.flag = term.eparser.flag or
      term.eparser.buf.equalsIgnoreCase("SetSelection")
    term.eparser.buf = ""
    if term.eparser.parseST(c):
      if not term.eparser.flag:
        if term.config.input.osc52Copy.isNone:
          term.osc52Copy = true
        if term.config.input.osc52Primary.isNone:
          term.osc52Primary = true
      term.eparser.flag = false
  else:
    term.eparser.buf &= c

proc parseOSC1(term: Terminal; c: char) =
  case c
  of '0': term.nextStateScreenBug(qsForegroundColor, c, esOSC10)
  of '1': term.nextStateScreenBug(qsBackgroundColor, c, esOSC11)
  else: term.eparser.backtrack(c)

proc parseOSC4Semi(eparser: var EventParser; c: char) =
  if eparser.parseST(c):
    discard
  elif c == ';':
    eparser.nums.add(eparser.num)
    eparser.num = 0
    eparser.state = esOSC4SemiNum
  elif not eparser.parseNum(c):
    eparser.nums.setLen(0)
    eparser.state = esNone

proc parseDCS(eparser: var EventParser; c: char) =
  case c
  of '0': eparser.state = esDCS0
  of '1': eparser.state = esDCS1
  else: eparser.backtrack(c)

proc parseDCS1PlusR(term: Terminal; c: char): EscParseResult =
  if term.eparser.parseHexNum(c):
    return eprNone
  let nums = move(term.eparser.nums)
  term.eparser.nums = @[]
  term.eparser.skipToST(c)
  if c == '=' and nums.len == 1 and nums[0] == 0x524742 and # ASCII R G B
      term.config.display.colorMode.isNone and
      term.attrs.colorMode != cmTrueColor:
    term.attrs.colorMode = cmTrueColor
    return eprWindowChange
  eprNone

proc parseAPCG(term: Terminal; c: char): EscParseResult =
  let imageMode = term.imageMode
  if term.config.display.imageMode.isNone:
    term.imageMode = imKitty
  term.eparser.skipToST(c)
  if imageMode != term.imageMode:
    return eprRedraw
  eprNone

proc areadCharBacktrack(term: Terminal): Opt[char] =
  if term.eparser.state == esBacktrack:
    if term.eparser.backtrackStack.len > 0:
      return ok(term.eparser.backtrackStack.pop())
    term.eparser.state = esNone
  return term.areadChar()

proc areadEvent*(term: Terminal): Opt[InputEvent] =
  var epr = eprNone
  while epr == eprNone:
    if term.eparser.keyLen == 1:
      dec term.eparser.keyLen
      return ok(InputEvent(t: ietKeyEnd))
    let c = ?term.areadCharBacktrack()
    case term.eparser.state
    of esBacktrack, esNone:
      if term.parseNone(c):
        return ok(InputEvent(t: ietKey, c: c))
    of esBracketed:
      if c == '\e':
        term.eparser.state = esBracketedEsc
      else:
        return ok(InputEvent(t: ietKey, c: c))
    of esBracketedEsc: term.eparser.nextState('[', c, esBracketedCSI)
    of esEsc: term.eparser.parseEsc(c)
    of esCSI: term.eparser.parseCSI(c)
    of esCSIQMark: epr = term.parseCSIQMark(c)
    of esCSIEquals: # SyncTERM DA1 response; skip
      if c == 'c':
        term.eparser.state = esNone
    of esCSINum: epr = term.parseCSINum(c)
    of esBracketedCSI: term.eparser.nextState('2', c)
    of esBracketedCSI2: term.eparser.nextState('0', c)
    of esBracketedCSI20: term.eparser.nextState('1', c)
    of esBracketedCSI201:
      if c == '~':
        term.eparser.state = esNone
        return ok(InputEvent(t: ietPaste))
      term.eparser.backtrack(c)
    of esCSILt:
      var mouse: MouseInput
      if term.eparser.parseCSILt(c, mouse):
        return ok(InputEvent(t: ietMouse, m: mouse))
    of esOSC: term.eparser.parseOSC(c)
    of esOSC6: term.eparser.parseOSC6(c)
    of esOSC60, esOSC61, esOSC10, esOSC11, esOSC4:
      term.eparser.nextState(';', c)
    of esOSC60Semi: term.parseOSC60Semi(c)
    of esOSC61Semi: term.parseOSC61Semi(c)
    of esOSC1: term.parseOSC1(c)
    of esOSC4Semi: term.eparser.parseOSC4Semi(c)
    of esOSC4SemiNum, esOSC10Semi, esOSC11Semi: epr = term.parseOSCNumSemi(c)
    of esDCS: term.eparser.parseDCS(c)
    of esDCS0, esDCS1: term.eparser.nextState('+', c)
    of esDCS0Plus: term.eparser.nextState('r', c, esSkipToST)
    of esDCS1Plus: term.eparser.nextState('r', c, esDCS1PlusR)
    of esDCS1PlusR: epr = term.parseDCS1PlusR(c)
    of esAPC: term.eparser.nextState('G', c, esAPCG)
    of esAPCG: epr = term.parseAPCG(c)
    of esSTEsc: term.eparser.nextState('\\', c, esNone)
    of esSkipToST: discard term.eparser.parseST(c)
  case epr
  of eprNone: return err()
  of eprWindowChange: return ok(InputEvent(t: ietWindowChange))
  of eprRedraw: return ok(InputEvent(t: ietRedraw))

proc cursorNextLineBegin(term: Terminal): Opt[void] =
  let ocursory = term.frame.cursory
  if term.frame.scrollBottom < 0 and ocursory + 1 < uint32(term.attrs.width) or
      ocursory < uint32(term.frame.scrollBottom):
    inc term.frame.cursory
  term.frame.cursorx = 0
  term.write("\r\n")

proc cursorNextLine*(term: Terminal): Opt[void] =
  let ocursory = term.frame.cursory
  if term.frame.scrollBottom < 0 and ocursory + 1 < uint32(term.attrs.width) or
      ocursory < uint32(term.frame.scrollBottom):
    inc term.frame.cursory
  term.write('\n')

proc cursorPrevLineBegin(term: Terminal): Opt[void] =
  if term.frame.cursory > 0:
    dec term.frame.cursory
  term.frame.cursorx = 0
  term.write('\r' & RI)

proc cursorLineBegin(term: Terminal): Opt[void] =
  term.frame.cursorx = 0
  term.write('\r')

proc cursorGoto(term: Terminal; x, y: uint32): Opt[void] =
  if term.frame.cursorKnown and term.frame.cursorx == x and
      term.frame.cursory == y:
    return ok()
  if term.frame.cursorKnown and (x == 0 or x == term.frame.cursorx) and
      y - term.frame.cursory <= 6:
    # This is probably more efficient than setting the cursor by address.
    if x == 0:
      ?term.cursorLineBegin()
    for u in term.frame.cursory ..< y:
      ?term.cursorNextLine()
    return ok()
  term.frame.cursorx = x
  term.frame.cursory = y
  term.frame.cursorKnown = true
  return case term.termType
  of ttAdm3a: term.write("\e=" & char(uint8(y) + 0x20) & char(uint8(x) + 0x20))
  of ttVt52: term.write("\eY" & char(uint8(y) + 0x20) & char(uint8(x) + 0x20))
  else: term.write(CSI & $(y + 1) & ';' & $(x + 1) & 'H')

proc cursorGoto(term: Terminal; x, y: int): Opt[void] =
  term.cursorGoto(uint32(x), uint32(y))

proc cursorHome(term: Terminal): Opt[void] =
  if term.frame.cursorKnown and term.frame.cursorx == 0 and
      term.frame.cursory == 0:
    return ok()
  if tfPreEcma48 in term.desc:
    return term.cursorGoto(0, 0)
  term.frame.cursorx = 0
  term.frame.cursory = 0
  term.write(CSI & 'H')

proc unsetCursorPos(term: Terminal) =
  term.frame.cursorKnown = false

proc clearEnd(term: Terminal): Opt[void] =
  case term.termType
  of ttAdm3a:
    for x in term.frame.cursorx ..< uint32(term.attrs.width):
      ?term.write(' ')
    term.frame.cursorx = uint32(term.attrs.width) - 1
    return ok()
  of ttVt52: return term.write("\eK")
  else: return term.write(CSI & 'K')

proc clearDisplay(term: Terminal): Opt[void] =
  return case term.termType
  of ttAdm3a: term.write("\x1A")
  of ttVt52: term.write("\eJ")
  else: term.write(CSI & 'J')

proc isatty(term: Terminal): bool =
  term.ttyFlag

proc anyKey*(term: Terminal; msg = "[Hit any key]"; bottom = false): Opt[void] =
  if term.isatty():
    if bottom:
      ?term.cursorGoto(0, term.attrs.height - 1)
    ?term.clearEnd()
    ?term.write(msg)
    ?term.blockIO()
    discard term.readChar()
    term.unblockIO()
  ok()

proc resetFormat(term: Terminal): Opt[void] =
  # This resets the formatting *and* synchronizes it with the terminal.
  # processFormat(Format()) is usually more efficient.
  term.frame.format = Format()
  case term.termType
  of ttAdm3a, ttVt52: return ok()
  else: return term.write(CSI & 'm')

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
  if bgcolor.t == ctRGB and fgcolor.t == ctRGB:
    # Both foreground and background are RGB, so presumably it was set by
    # the website itself.  Correcting the foreground's contrast may be
    # counter-productive in this case, because many "spoiler text"
    # implementations just set the foreground and background to the same
    # color.
    # Of course, it's still a problem if we fail to parse only a certain
    # box's background color, but that should be rare enough (hopefully a
    # website would at least use a consistent color syntax...)
    return fgcolor
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
    case term.attrs.colorMode
    of cmTrueColor:
      return cellColor(newrgb)
    of cmANSI:
      return term.approximateANSIColor(newrgb, term.defaultForeground)
    of cmEightBit:
      return cellColor(newrgb.toEightBit())
    of cmMonochrome:
      assert false
  return cfgcolor

proc writeColorSGR(term: Terminal; c: CellColor; bgmod: uint8): Opt[void] =
  var res = CSI
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
  term.write(res)

# If needed, quantize colors based on the color mode, and correct their
# contrast.
proc reduceFormat*(term: Terminal; format: Format): Format =
  var bgcolor = format.bgcolor
  var fgcolor = format.fgcolor
  case term.attrs.colorMode
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
    fgcolor = defaultColor
    bgcolor = defaultColor
  let flags = format.flags * term.formatMode
  return initFormat(bgcolor, fgcolor, flags)

const FormatCodes: array[FormatFlag, tuple[s, e: string]] = [
  ffBold: ("1", "22"),
  ffItalic: ("3", "23"),
  ffUnderline: ("4", "24"),
  ffReverse: ("7", "27"),
  ffStrike: ("9", "29"),
  ffOverline: ("53", "55"),
  ffBlink: ("5", "25"),
]

proc processFormat*(term: Terminal; cellf: Format): Opt[void] =
  let fgcolor = cellf.fgcolor
  let bgcolor = cellf.bgcolor
  let flags = cellf.flags
  let oformat = term.frame.format
  let oldFgcolor = oformat.fgcolor
  let oldBgcolor = oformat.bgcolor
  let oldFlags = oformat.flags
  if oldFlags != flags:
    # if either
    # * both fgcolor and bgcolor are the default, or
    # * both are being changed,
    # then we can use a general reset when new flags are empty.
    if flags == {} and (fgcolor != oldFgcolor and bgcolor != oldBgcolor or
        fgcolor == defaultColor and bgcolor == defaultColor):
      ?term.resetFormat()
    else:
      let flagsUnset = oldFlags - flags
      let flagsSet = flags - oldFlags
      var first = true
      const DivMap = [false: ";", true: CSI]
      for flag in FormatFlag:
        if flag in flagsUnset:
          ?term.write(DivMap[first])
          ?term.write(FormatCodes[flag].e)
          first = false
        elif flag in flagsSet:
          ?term.write(DivMap[first])
          ?term.write(FormatCodes[flag].s)
          first = false
      ?term.write('m')
  if fgcolor != oldFgcolor:
    ?term.writeColorSGR(fgcolor, bgmod = 0)
  if bgcolor != oldBgcolor:
    ?term.writeColorSGR(bgcolor, bgmod = 10)
  term.frame.format = cellf
  ok()

proc hasTitle(term: Terminal): bool =
  term.config.display.setTitle.get(tfTitle in term.desc)

proc hasAltScreen(term: Terminal): bool =
  term.config.display.altScreen.get(tfAltScreen in term.desc)

proc hasBracketedPaste(term: Terminal): bool =
  term.config.input.bracketedPaste.get(tfBracketedPaste in term.desc)

proc hasMouse(term: Terminal): bool =
  term.config.input.useMouse.get(tfMouse in term.desc)

proc encodeAllQMark(res: var string; te: TextEncoder; iq: openArray[uint8]) =
  var n = 0
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

proc encodeAscii(res: var string; s: openArray[char]; specialGraphics: var bool;
    hasSpecialGraphics: bool) =
  var sg = specialGraphics
  for u in s.points:
    if u < 0x80:
      if sg and u in 0x5Fu32..0x7Eu32:
        res &= "\e(B"
        sg = false
      res &= char(u)
    else:
      if hasSpecialGraphics:
        block graph:
          let c = case u
          of 0x2500, 0x2501, 0x2504, 0x2505, 0x2508, 0x2509, 0x254C, 0x254D,
              0x2550:
            '\x71'
          of 0x2502, 0x2503, 0x2506, 0x2507, 0x250A, 0x250B, 0x254E, 0x254F,
              0x2551:
            '\x78'
          of 0x250Cu32..0x250Fu32, 0x2552u32..0x2554u32: '\x6C'
          of 0x2510u32..0x2513u32, 0x2555u32..0x2557u32: '\x6B'
          of 0x2514u32..0x2517u32, 0x2558u32..0x255Au32: '\x6D'
          of 0x2518u32..0x251Bu32, 0x255Bu32..0x255Du32: '\x6A'
          of 0x251Cu32..0x2523u32, 0x255Eu32..0x2560u32: '\x74'
          of 0x2524u32..0x252Bu32, 0x2561u32..0x2563u32: '\x75'
          of 0x252Cu32..0x2533u32, 0x2564u32..0x2566u32: '\x77'
          of 0x2534u32..0x253Bu32, 0x2567u32..0x2569u32: '\x76'
          of 0x253Cu32..0x254Bu32, 0x256Au32..0x256Cu32: '\x6E'
          of 0x2264: '\x79'
          of 0x2265: '\x7A'
          of 0x3C0: '\x7B'
          of 0x2260: '\x7C'
          of 0xA3: '\x7D'
          of 0xB7: '\x7E'
          of 0x202F: '\x5F'
          else: break graph
          if not sg:
            res &= "\e(0"
            sg = true
          res &= c
          continue
      # quotes; to be fair these shouldn't have been included, but it looks
      # very awkward when they don't exist
      case u
      of 0x2018, 0x201B: res &= '`'
      of 0x2019: res &= '\''
      of 0x201A: res &= ','
      of 0x201C, 0x201D: res &= '"'
      of 0x2022: res &= '*' # also bullet lists are pretty common
      else:
        for i in 0 ..< u.width():
          res &= '?'
  specialGraphics = sg

proc processOutputString*(term: Terminal; s: openArray[char];
    trackCursor = true): Opt[void] =
  if s.len <= 0:
    return ok()
  if not trackCursor:
    term.unsetCursorPos()
  if s.validateUTF8Surr() != -1:
    if trackCursor:
      inc term.frame.cursorx
    return term.write('?')
  if trackCursor:
    for u in s.points:
      assert u > 0x9F or u != 0x7F and u > 0x1F
      term.frame.cursorx += uint32(u.width())
  if term.te == nil:
    # The output encoding matches the internal representation.
    return term.write(s)
  var res = ""
  if term.asciiOnly:
    res.encodeAscii(s, term.frame.specialGraphics,
      tfSpecialGraphics in term.desc)
  else:
    # Output is not utf-8, so we must encode it first.
    res = newString(s.len) # guess length
    res.encodeAllQMark(term.te, s.toOpenArrayByte(0, s.high))
  term.write(res)

proc hideCursor(term: Terminal): Opt[void] =
  if not term.frame.cursorHidden:
    term.frame.cursorHidden = true
    case term.termType
    of ttAdm3a, ttVt52: discard
    else: return term.write(HideCursor)
  ok()

proc showCursor(term: Terminal): Opt[void] =
  if term.frame.cursorHidden:
    term.frame.cursorHidden = false
    case term.termType
    of ttAdm3a, ttVt52: discard
    else: return term.write(ShowCursor)
  ok()

# 1-indexed
proc setScrollArea(term: Terminal; top, bottom: int): Opt[void] =
  if term.frame.scrollBottom != bottom:
    term.frame.scrollBottom = bottom
    term.frame.cursorx = 0
    term.frame.cursory = 0
    return term.write(CSI & $top & ";" & $bottom & 'r')
  ok()

proc resetScrollArea(term: Terminal): Opt[void] =
  if term.frame.scrollBottom != -1:
    term.frame.scrollBottom = -1
    term.frame.cursorx = 0
    term.frame.cursory = 0
    return term.write(CSI & 'r')
  ok()

proc moveLinesUp(term: Terminal; n: int): Opt[void] =
  term.write(CSI & $n & 'S')

proc moveLinesDown(term: Terminal; n: int): Opt[void] =
  term.write(CSI & $n & 'T')

proc processCell(term: Terminal; cell: FixedCell; x: int): Opt[void] =
  if cell.str.len == 0:
    return ok()
  # if previous cell was empty, catch up with x
  let x = uint32(x)
  while term.frame.cursorx < x:
    ?term.write(' ')
    inc term.frame.cursorx
  ?term.processFormat(cell.format)
  term.processOutputString(cell.str)

proc drawLine(term: Terminal; sx, y: int): Opt[void] =
  for x in sx ..< term.attrs.width:
    ?term.processCell(term.frame.canvas[y * term.attrs.width + x], x)
  if term.frame.cursorx < uint32(term.attrs.width):
    ?term.processFormat(Format())
    ?term.clearEnd()
  term.frame.lineDamage[y] = term.attrs.width
  ok()

proc fullDraw(term: Terminal): Opt[void] =
  ?term.hideCursor()
  ?term.resetScrollArea()
  ?term.cursorHome()
  ?term.clearDisplay()
  ?term.resetFormat()
  for y in 0 ..< term.attrs.height:
    if y != 0:
      ?term.cursorNextLineBegin()
    ?term.drawLine(0, y)
  ok()

proc partialDrawScroll(term: Terminal; scroll, scrollBottom: int;
    bgcolor: CellColor): Opt[void] =
  ?term.setScrollArea(1, scrollBottom) # may move cursor to 0, 0
  # BCE to the buffer's background color to reduce visibility of tearing.
  ?term.processFormat(initFormat(bgcolor, defaultColor, {}))
  if term.imageMode == imSixel and term.frame.fastScrollTodo and
      tfFastScroll in term.desc:
    # Scrolling Sixel images line-by-line isn't very efficient (at least it
    # visibly slows down XTerm on my laptop), so use fast scroll for this.
    # (Also, XTerm has a bug that breaks slow scroll upwards, but TODO this
    # should be fixed in XTerm...)
    #
    # Note that "slow" scroll is more effective against tearing, because
    # it allows us to limit the number of unfilled lines to one.  Hence we
    # only want to do fast scroll if we have Sixel images on the screen.
    if scroll < 0:
      return term.moveLinesDown(-scroll)
    else:
      return term.moveLinesUp(scroll)
  if scroll < 0: # scroll up
    ?term.cursorHome()
    for i in countdown(0, scroll + 1):
      ?term.cursorPrevLineBegin()
      ?term.drawLine(0, i - scroll - 1)
    return term.cursorLineBegin()
  # scroll down
  ?term.cursorGoto(0, scrollBottom - 1)
  for i in 0 ..< scroll:
    ?term.cursorNextLineBegin()
    ?term.drawLine(0, scrollBottom - scroll + i)
  term.cursorHome()

proc partialDraw(term: Terminal; scrollBottom: int; bgcolor: CellColor):
    Opt[void] =
  let scroll = term.frame.scrollTodo
  if scroll != 0:
    ?term.hideCursor()
    ?term.partialDrawScroll(scroll, scrollBottom, bgcolor)
  for y in 0 ..< term.attrs.height:
    # set cx to x of the first change
    let cx = term.frame.lineDamage[y]
    # w will track the current position on screen
    if cx >= term.attrs.width:
      continue
    ?term.hideCursor()
    ?term.resetScrollArea()
    ?term.cursorGoto(cx, y)
    ?term.drawLine(cx, y)
  ok()

proc writeGrid*(term: Terminal; grid: FixedGrid; x = 0, y = 0) =
  for ly in y ..< y + grid.height:
    var lastx = 0
    for lx in x ..< x + grid.width:
      let i = ly * term.attrs.width + lx
      let cell = grid[(ly - y) * grid.width + (lx - x)]
      if term.frame.canvas[i].str != "":
        # if there is a change, we have to start from the last x with
        # a string (otherwise we might overwrite half of a double-width char)
        lastx = lx
      let format = term.reduceFormat(cell.format)
      if format != term.frame.canvas[i].format or
          cell.str != term.frame.canvas[i].str:
        term.frame.canvas[i].str = cell.str
        term.frame.canvas[i].format = format
        term.frame.lineDamage[ly] = min(term.frame.lineDamage[ly], lastx)

proc getCurrentBgcolor*(term: Terminal): CellColor =
  term.frame.format.bgcolor

# returns diff between current and old position (0 = cannot scroll)
proc updateScroll*(term: Terminal; pid, x, y: int): int =
  var diff = 0
  #TODO I think we always have to check against ftCurrent here...
  # with ftNext you get issues because we haven't dropped the frame at this
  # point yet?  or something
  # but I guess that also breaks canvas updates
  # so probably you have to do the frame dropping thing *before* the
  # printing even starts
  # and then this is fine eh?
  let pos = term.frame.pos
  if pid != -1 and pos.pid == pid and pos.x == x:
    diff = y - pos.y
  term.frame.pos = (pid, x, y)
  diff

proc unsetScroll*(term: Terminal) =
  # Called on winchange or when no container is on the screen.
  # This won't be replayed, so unset pid everywhere.
  for frame in term.frames.mitems:
    frame.pos.pid = -1

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
    term.attrs.colorMode = term.config.display.colorMode.get
  if term.config.display.formatMode.isSome:
    term.formatMode = term.config.display.formatMode.get
  for fm in FormatFlag:
    if fm in term.config.display.noFormatMode:
      term.formatMode.excl(fm)
  if term.config.display.imageMode.isSome:
    term.imageMode = term.config.display.imageMode.get
  if term.config.display.sixelColors.isSome:
    let n = term.config.display.sixelColors.get
    term.sixelRegisterNum = uint16(clamp(n, 2, 65535))
  if term.config.display.defaultBackgroundColor.isSome:
    term.defaultBackground = term.config.display.defaultBackgroundColor.get
  if term.config.display.defaultForegroundColor.isSome:
    term.defaultForeground = term.config.display.defaultForegroundColor.get
  term.attrs.prefersDark = term.defaultBackground.Y < 125
  if term.config.input.osc52Copy.isSome:
    term.osc52Copy = term.config.input.osc52Copy.get
  if term.config.input.osc52Primary.isSome:
    term.osc52Primary = term.config.input.osc52Primary.get
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
        if env == "C":
          term.asciiOnly = true
          term.cs = CHARSET_WINDOWS_1252
        else:
          term.cs = cs
        break
  if term.cs in {CHARSET_UTF_8, CHARSET_UTF_16_LE, CHARSET_UTF_16_BE,
      CHARSET_REPLACEMENT}:
    term.cs = CHARSET_UTF_8
  else:
    term.te = newTextEncoder(term.cs)
  term.tdctx = initTextDecoderContext(term.cs)
  term.applyConfigDimensions()

proc addImage*(term: Terminal; image: CanvasImage) =
  if term.canvasImagesTmpTail == nil:
    term.canvasImagesTmpHead = image
  else:
    term.canvasImagesTmpTail.next = image
  term.canvasImagesTmpTail = image

proc takeImage*(term: Terminal; pid, imageId, bufHeight: int;
    dims: CanvasImageDimensions): CanvasImage =
  # pass2 is set after finding a damaged scrolled image (usually because we
  # scrolled out some part and scrolled in another part).
  # In this case, we can't just reuse the CanvasImage we found because that
  # would result in displaying an image with the modified (scrolled) erry.
  # So we just search again.
  #TODO this is way too convoluted, I'm sure there's a better way...
  var pass2 = false
  var it = term.frame.canvasImagesHead
  var prev: CanvasImage = nil
  while it != nil:
    if it.pid == pid and it.bmp.imageId == imageId and
        it.dims.width == dims.width and it.dims.height == dims.height and
        it.dims.rx == dims.rx and it.dims.ry == dims.ry and
        (term.imageMode != imSixel or
          (not pass2 and it.dims.erry == dims.erry or
            pass2 and it.dims.erry2 == dims.erry) and
          it.dims.dispw == dims.dispw and it.dims.offx == dims.offx):
      if not pass2 and not term.updateCanvasImage(it, dims, bufHeight):
        # retry with the right y error
        pass2 = true
        it = term.frame.canvasImagesHead
        continue
      if prev != nil:
        prev.next = it.next
      else:
        term.frame.canvasImagesHead = it.next
      it.next = nil
      return it
    prev = it
    it = it.next
  return nil

proc positionImage*(term: Terminal; rx, ry, x, y, offx2, offy2, width, height,
    maxwpx, maxhpx: int): CanvasImageDimensions =
  let offx2 = if term.imageMode == imKitty: offx2 else: 0
  let offy2 = if term.imageMode == imKitty: offy2 else: 0
  let xpx = x * term.attrs.ppc + offx2
  let ypx = y * term.attrs.ppl + offy2
  # calculate offset inside image to start from
  let offx = -min(xpx, 0)
  let offy = -min(ypx, 0)
  let erry = -min(ypx, 0) mod 6
  CanvasImageDimensions(
    x: x,
    y: y,
    width: width,
    height: height,
    rx: rx,
    ry: ry,
    xpx: xpx,
    ypx: ypx,
    offx: offx,
    offy: offy,
    offx2: offx2,
    offy2: offy2,
    # maximum image size that fits on the screen relative to the image
    # origin (*not* offx/offy)
    dispw: min(width + xpx, maxwpx) - xpx,
    disph: min(height + ypx, maxhpx) - ypx,
    erry: erry,
    erry2: erry
  )

proc onScreen*(dims: CanvasImageDimensions): bool =
  dims.dispw > dims.offx and dims.disph > dims.offy

proc repositionImage(term: Terminal; image: CanvasImage;
    maxwpx, maxhpx: int): bool =
  let erry2 = image.dims.erry2
  let dims = term.positionImage(image.dims.rx, image.dims.ry, image.dims.x,
    image.dims.y, image.dims.offx2, image.dims.offy2, image.dims.width,
    image.dims.height, maxwpx, maxhpx)
  if dims.onScreen:
    image.dims = dims
    image.dims.erry2 = erry2
    return true
  false

proc clearImage(term: Terminal; image: CanvasImage; maxh: int) =
  case term.imageMode
  of imNone: discard
  of imSixel:
    # we must clear sixels the same way as we clear text.
    let h = (image.dims.height + term.attrs.ppl - 1) div term.attrs.ppl # ceil
    let ey = min(image.dims.y + h, maxh)
    let x = max(image.dims.x, 0)
    for y in max(image.dims.y, 0) ..< ey:
      term.frame.lineDamage[y] = min(term.frame.lineDamage[y], x)
  of imKitty:
    if image.kittyId != 0:
      term.frame.kittyImagesToClear.add(image.kittyId)

proc clearImages*(term: Terminal; maxh: int) =
  for image in term.frame.canvasImages:
    term.clearImage(image, maxh)
  term.frame.canvasImagesHead = nil

proc checkImageDamage(term: Terminal; image: CanvasImage; maxw, maxh: int) =
  # we're interested in the last x/y *on screen*.  if damage exceeds that,
  # then the image is unaffected and there's nothing to do.
  let lastx = maxw - 1
  let ppl = term.attrs.ppl
  let ppc = term.attrs.ppc
  # compute the bottom and right borders, rounded in both directions.
  # if the last column/line doesn't cover a cell, consider it
  # transparent.
  let ey0 = min(image.dims.y + (image.dims.height + ppl - 1) div ppl, maxh)
  let eypx = image.dims.ypx + image.dims.disph
  let x = max(image.dims.x, 0)
  let mx0 = min(image.dims.x + image.dims.dispw div ppc, lastx)
  let mx = min(image.dims.x + (image.dims.dispw + ppc - 1) div ppc, lastx)
  for y in max(image.dims.y, 0) ..< ey0:
    let od = term.frame.lineDamage[y]
    if od > mx0:
      continue
    image.damaged = true
    if od < x:
      continue
    # If eypx is less than y * ppl, that means it only partially covers
    # the last line on the screen which it is painted to.  Therefore we must
    # treat it as transparent here.
    # A similar situation arises when od is on the last covered column.
    if image.transparent or eypx < y * ppl or od in mx0 ..< mx:
      term.frame.lineDamage[y] = x
    else:
      var textFound = false
      # damage starts inside an opaque image; skip clear (but only if
      # the damage was not caused by a printing character)
      let si = y * term.attrs.width
      for i in si + od ..< si + term.attrs.width:
        if term.frame.canvas[i].str.len > 0 and
            term.frame.canvas[i].str[0] != ' ':
          textFound = true
          break
      if not textFound:
        term.frame.lineDamage[y] = mx

proc updateCanvasImage(term: Terminal; image: CanvasImage;
    dims: CanvasImageDimensions; maxh: int): bool =
  # reuse image on screen
  if image.dims.x != dims.x or image.dims.y != dims.y or
      image.dims.disph != dims.disph or image.dims.offy != dims.offy or
      image.dims.erry != dims.erry:
    if term.imageMode == imSixel and image.dims.erry != image.dims.erry2:
      # we have scrolled in more of this image onto the screen, but the Y
      # error is incorrect.  load the right one.
      return false
    image.damaged = true
    # only clear sixels; with kitty we just move the existing image
    if term.imageMode == imSixel:
      term.clearImage(image, maxh)
    image.dims = dims
  true

proc checkImageOverlap(term: Terminal; image: CanvasImage) =
  var it = term.frame.canvasImagesHead
  var prev: CanvasImage = nil
  let x1 = image.dims.xpx + image.dims.offx
  let y1 = image.dims.ypx + image.dims.offy
  let x2 = image.dims.xpx + image.dims.dispw
  let y2 = image.dims.ypx + image.dims.disph
  let opaque = not image.transparent
  while it != image:
    let ix1 = it.dims.xpx + it.dims.offx
    let iy1 = it.dims.ypx + it.dims.offy
    let ix2 = it.dims.xpx + it.dims.dispw
    let iy2 = it.dims.ypx + it.dims.disph
    if ix1 < x2 and x1 < ix2 and iy1 < y2 and y1 < iy2: # overlap
      if opaque and ix1 >= x1 and iy1 >= y1:
        # `it' is fully covered by `image'; remove `it'.
        let next = move(it.next)
        if prev != nil:
          prev.next = next
        else:
          term.frame.canvasImagesHead = next
        it = next
        continue
      if term.imageMode == imSixel and it.damaged:
        # an image we overlap with was damaged; we have to redraw too to
        # preserve Z order.
        image.damaged = true
    prev = it
    it = it.next

iterator updateImages*(term: Terminal; bufWidth, bufHeight: int): CanvasImage =
  term.clearImages(bufHeight)
  term.frame.canvasImagesHead = move(term.canvasImagesTmpHead)
  term.canvasImagesTmpTail = nil
  if term.imageMode == imSixel:
    var image = term.frame.canvasImagesHead
    var prev: CanvasImage = nil
    while image != nil:
      term.checkImageDamage(image, bufWidth, bufHeight)
      term.checkImageOverlap(image)
      if image.damaged and image.dims.erry != image.dims.erry2:
        yield image
        if not image.damaged: # ...yeah
          if prev == nil:
            term.frame.canvasImagesHead = image.next
          else:
            prev.next = image.next
      prev = image
      image = image.next

proc updateImage*(image: CanvasImage; data: Blob; preludeLen: int) =
  image.data = data
  image.preludeLen = preludeLen
  image.dims.erry2 = image.dims.erry

proc newCanvasImage*(data: Blob; pid, preludeLen: int; bmp: NetworkBitmap;
    dims: CanvasImageDimensions; transparent: bool): CanvasImage =
  CanvasImage(
    pid: pid,
    bmp: bmp,
    data: data,
    dims: dims,
    transparent: transparent,
    preludeLen: preludeLen,
    damaged: true
  )

proc getU32BE(data: openArray[char]; i: int): uint32 =
  return uint32(data[i + 3]) or
    (uint32(data[i + 2]) shl 8) or
    (uint32(data[i + 1]) shl 16) or
    (uint32(data[i]) shl 24)

proc writeSixelAttrs(term: Terminal; data: openArray[char];
    realw, realh: int): Opt[void] =
  var i = max(data.find('"'), 0) # set raster attrs
  ?term.write(data.toOpenArray(0, i))
  ?term.write("1;1;" & $realw & ';' & $realh)
  while i < data.len and data[i] != '#': # skip aspect ratio attrs
    inc i
  term.write(data.toOpenArray(i, data.high))

proc outputSixelImage(term: Terminal; x, y: int; image: CanvasImage;
    data: openArray[char]): Opt[void] =
  let offx = image.dims.offx
  let offy = image.dims.offy
  let dispw = image.dims.dispw
  let disph = image.dims.disph
  let realw = dispw - offx
  let realh = disph - offy
  let preludeLen = image.preludeLen
  if preludeLen > data.len or data.len < 4:
    return ok()
  let L = data.len - int(data.getU32BE(data.len - 4)) - 4
  if L < 0:
    return ok()
  ?term.hideCursor()
  ?term.cursorGoto(x, y)
  # From this point on we have no idea where the cursor is because pretty
  # much every terminal puts it somewhere else.
  term.unsetCursorPos()
  ?term.writeSixelAttrs(data.toOpenArray(0, preludeLen - 1), realw, realh)
  # Note: we only crop images when it is possible to do so in near constant
  # time. Otherwise, the image is re-coded in a cropped form.
  if realh == image.dims.height: # don't crop
    return term.write(data.toOpenArray(preludeLen, L - 1))
  let si = preludeLen + int(data.getU32BE(L + (offy div 6) * 4))
  if si >= data.len: # bounds check
    return term.write(ST)
  if disph == image.dims.height: # crop top only
    return term.write(data.toOpenArray(si, L - 1))
  # crop both top & bottom
  let ed6 = (disph - image.dims.erry2) div 6
  let ei = preludeLen + int(data.getU32BE(L + ed6 * 4)) - 1
  if ei <= data.len: # bounds check
    ?term.write(data.toOpenArray(si, ei - 1))
  # calculate difference between target Y & actual position in the map
  # note: it must be offset by image.erry2; that's where the map starts.
  let herry = disph - (ed6 * 6 + image.dims.erry2)
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
    ?term.write(s)
  term.write(ST)

proc outputSixelImage(term: Terminal; x, y: int; image: CanvasImage):
    Opt[void] =
  var p = cast[ptr UncheckedArray[char]](image.data.buffer)
  if image.data.size > 0:
    let H = image.data.size - 1
    ?term.outputSixelImage(x, y, image, p.toOpenArray(0, H))
  ok()

proc outputKittyImage(term: Terminal; x, y: int; image: CanvasImage):
    Opt[void] =
  ?term.cursorGoto(x, y)
  # ignore offx2/offy2 if the image starts outside the screen (and thus we
  # are painting a slice only)
  # note: this looks wrong, but it's correct
  let offx2 = if image.dims.offx > 0: 0 else: image.dims.offx2
  let offy2 = if image.dims.offy > 0: 0 else: image.dims.offy2
  var outs = APC & "GC=1,s=" & $image.dims.width & ",v=" & $image.dims.height &
    ",x=" & $image.dims.offx & ",y=" & $image.dims.offy &
    ",X=" & $offx2 & ",Y=" & $offy2 &
    ",w=" & $(image.dims.dispw - image.dims.offx) &
    ",h=" & $(image.dims.disph - image.dims.offy) &
    # for now, we always use placement id 1
    ",p=1,q=2"
  if image.kittyId != 0:
    outs &= ",i=" & $image.kittyId & ",a=p;" & ST
    return term.write(outs)
  inc term.kittyId # skip i=0
  if term.kittyId == 0: # unsigned wraparound
    inc term.kittyId
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
  ?term.write(outs)
  while i < L:
    let j = i
    i += MaxBytes
    let m = if i < L: '1' else: '0'
    var outs = APC & "Gm=" & m & ';'
    outs.btoa(p.toOpenArray(j, min(L, i) - 1))
    outs &= ST
    ?term.write(outs)
  ok()

proc outputImages(term: Terminal): Opt[void] =
  if term.imageMode == imKitty:
    # clean up unused kitty images
    var s = ""
    for id in term.frame.kittyImagesToClear:
      s &= APC & "Ga=d,d=I,i=" & $id & ",p=1,q=2;" & ST
    ?term.write(s)
    term.frame.kittyImagesToClear.setLen(0)
  for image in term.frame.canvasImages:
    if image.damaged:
      assert image.dims.dispw > 0 and image.dims.disph > 0
      ?term.resetScrollArea()
      let x = max(image.dims.x, 0)
      let y = max(image.dims.y, 0)
      case term.imageMode
      of imNone: assert false
      of imSixel: ?term.outputSixelImage(x, y, image)
      of imKitty: ?term.outputKittyImage(x, y, image)
      image.damaged = false
  ok()

proc clearCanvas*(term: Terminal) =
  term.cleared = false
  let maxwpx = term.attrs.widthPx
  let maxh = term.attrs.height - 1
  let maxhpx = maxh * term.attrs.ppl
  var imagesHead: CanvasImage = nil
  var imagesTail: CanvasImage = nil
  var image = term.frame.canvasImagesHead
  while image != nil:
    let next = image.next
    if not image.scrolled and term.repositionImage(image, maxwpx, maxhpx):
      image.damaged = true
      image.next = nil
      if imagesTail == nil:
        imagesHead = image
      else:
        imagesTail.next = image
      imagesTail = image
    image = next
  term.clearImages(maxh)
  term.frame.canvasImagesHead = imagesHead

proc queueTitle*(term: Terminal; title: string) =
  if term.frame.title != title:
    term.frame.queueTitleFlag = true
    term.frame.title = title

# Must be called directly before draw, otherwise the cursor will disappear.
proc scrollUp*(term: Terminal; n, scrollBottom: int) =
  if tfScroll notin term.desc:
    return
  for y in countdown(scrollBottom - n - 1, 0):
    for x in 0 ..< term.attrs.width:
      let i = y * term.attrs.width + x
      let j = (y + n) * term.attrs.width + x
      term.frame.canvas[j] = move(term.frame.canvas[i])
  for y in 0 ..< n:
    term.frame.lineDamage[y] = 0
  let maxwpx = term.attrs.widthPx
  let maxhpx = scrollBottom * term.attrs.ppl
  let scrolled = term.imageMode == imSixel
  var found = false
  var image = term.frame.canvasImagesHead
  var prev: CanvasImage = nil
  while image != nil:
    image.dims.y += n
    image.scrolled = scrolled
    found = true
    let erry = image.dims.erry
    let offy = image.dims.offy
    if not term.repositionImage(image, maxwpx, maxhpx): # no longer visible
      let next = move(image.next)
      if prev != nil:
        prev.next = next
      else:
        term.frame.canvasImagesHead = next
      if term.imageMode == imKitty: # see below
        term.frame.kittyImagesToClear.add(image.kittyId)
      image = next
      continue
    if term.imageMode == imKitty:
      # Kitty exhibits strange behavior on scroll up:
      # * if the image touches the scroll boundary on the bottom, and is
      #   cropped on the top, then the image fails to scroll.
      # * otherwise, the image is cropped, but the cropping code is
      #   apparently glitched.
      # So we just mark all images as damaged in this case; repainting Kitty
      # is cheap anyway.
      image.damaged = true
    # scroll up does not change offy or erry (the slice's start).
    image.dims.offy = offy
    image.dims.erry = erry
    prev = image
    image = image.next
  if found and (n > 1 or term.termType == ttXterm):
    # XTerm can't do single-line scroll-up correctly, see below.
    term.frame.fastScrollTodo = true
  term.frame.scrollTodo -= n

proc scrollDown*(term: Terminal; n, scrollBottom: int) =
  if tfScroll notin term.desc:
    return
  for y in n ..< scrollBottom:
    for x in 0 ..< term.attrs.width:
      let i = y * term.attrs.width + x
      let j = (y - n) * term.attrs.width + x
      term.frame.canvas[j] = move(term.frame.canvas[i])
  for y in scrollBottom - n ..< scrollBottom:
    term.frame.lineDamage[y] = 0
  let maxwpx = term.attrs.widthPx
  let maxhpx = scrollBottom * term.attrs.ppl
  let scrolled = term.imageMode == imSixel
  var found = false
  var image = term.frame.canvasImagesHead
  var prev: CanvasImage = nil
  while image != nil:
    found = true
    image.dims.y -= n
    image.scrolled = scrolled
    let disph = image.dims.disph
    if not term.repositionImage(image, maxwpx, maxhpx): # no longer visible
      let next = move(image.next)
      if prev != nil:
        prev.next = next
      else:
        term.frame.canvasImagesHead = next
      if term.imageMode == imKitty: # see below
        term.frame.kittyImagesToClear.add(image.kittyId)
      image = next
      continue
    if term.imageMode == imKitty:
      # scroll down seems to work in Kitty, but not in Ghostty :(
      # so we apply the same workaround.
      image.damaged = true
    # scroll down doesn't change disph (the slice's end).
    image.dims.disph = disph
    prev = image
    image = image.next
  if found and n > 1:
    term.frame.fastScrollTodo = true
  term.frame.scrollTodo += n

proc draw*(term: Terminal; redraw, mouse: bool;
    cursorx, cursory, scrollBottom: int; bgcolor: CellColor): Opt[void] =
  if redraw:
    if not term.cleared:
      ?term.fullDraw()
      term.cleared = true
    else:
      ?term.partialDraw(scrollBottom, bgcolor)
    if term.imageMode != imNone:
      ?term.outputImages()
  if cursory > term.frame.scrollBottom:
    ?term.resetScrollArea()
  ?term.cursorGoto(cursorx, cursory)
  ?term.showCursor()
  if term.frame.queueTitleFlag and term.hasTitle():
    ?term.write(OSC & "0;" & term.frame.title.replaceControls() & ST)
    term.frame.queueTitleFlag = false
  if term.hasMouse() and mouse != term.frame.mouseEnabled:
    if mouse:
      ?term.write(SetSGRMouse)
    else:
      ?term.write(ResetSGRMouse)
    term.frame.mouseEnabled = mouse
  term.startFlush()

proc sendOSC52*(term: Terminal; s: string; clipboard = true): Opt[bool] =
  if not term.osc52Copy:
    return ok(false)
  var buf = OSC & "52;"
  if clipboard:
    buf &= 'c'
  if term.osc52Primary:
    buf &= 'p'
  buf &= ';'
  buf.btoa(s.toOpenArrayByte(0, s.high))
  buf &= ST
  let ot = term.frameType
  term.frameType = ftCurrent
  ?term.write(buf)
  term.frameType = ot
  ok(true)

# see https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html
proc disableRawMode(term: Terminal): Opt[void] =
  if tcSetAttr(term.istream.fd, TCSAFLUSH, addr term.origTermios) < 0:
    return err()
  ok()

proc enableRawMode(term: Terminal): Opt[void] =
  if tcGetAttr(term.istream.fd, addr term.origTermios) < 0:
    return err()
  var raw = term.origTermios
  raw.c_iflag = raw.c_iflag and not (BRKINT or ICRNL or INPCK or ISTRIP)
  if tfFlowControl notin term.desc:
    # If the terminal actually uses flow control, just let the OS handle it.
    # Otherwise, disable it so that the user can bind C-s and C-q freely.
    raw.c_iflag = raw.c_iflag and not IXON
  raw.c_oflag = raw.c_oflag and not (OPOST)
  raw.c_cflag = raw.c_cflag or CS8
  raw.c_lflag = raw.c_lflag and not (ECHO or ICANON or ISIG or IEXTEN)
  raw.c_cc[VMIN] = char(1)
  raw.c_cc[VTIME] = char(0)
  term.newTermios = raw
  if tcSetAttr(term.istream.fd, TCSAFLUSH, addr raw) < 0:
    return err()
  ok()

# This is checked in the SIGINT handler, set in main.nim.
var sigintCaught* {.global.} = false
var acceptSigint* {.global.} = false

proc catchSigint*(term: Terminal) =
  term.newTermios.c_lflag = term.newTermios.c_lflag or ISIG
  acceptSigint = true
  discard tcSetAttr(term.istream.fd, TCSADRAIN, addr term.newTermios)

proc respectSigint*(term: Terminal) =
  sigintCaught = false
  acceptSigint = false
  term.newTermios.c_lflag = term.newTermios.c_lflag and not ISIG
  discard tcSetAttr(term.istream.fd, TCSADRAIN, addr term.newTermios)

proc quit*(term: Terminal): Opt[void] =
  if term.isatty():
    term.frameType = ftCurrent # drop buffered frames
    if term.hasMouse() and term.frame.mouseEnabled:
      ?term.write(ResetSGRMouse)
      term.frame.mouseEnabled = false
    if term.hasBracketedPaste():
      ?term.write(ResetBracketedPaste)
    ?term.resetScrollArea()
    if term.hasAltScreen():
      if term.imageMode == imSixel:
        # xterm seems to keep sixels in the alt screen; clear these so it
        # doesn't flash in the user's face the next time they do smcup
        ?term.clearDisplay()
      ?term.write(ResetAltScreen)
    else:
      ?term.cursorGoto(0, term.attrs.height - 1)
      ?term.resetFormat()
      # if cleared, we have something on the screen; print a newline to
      # avoid overprinting it
      if term.cleared:
        ?term.cursorNextLineBegin()
    if term.hasTitle():
      ?term.write(PopTitle)
    ?term.showCursor()
    ?term.blockIO()
    term.newTermios.c_lflag = term.newTermios.c_lflag or ISIG
    discard tcSetAttr(term.istream.fd, TCSANOW, addr term.newTermios)
    discard myposix.signal(SIGINT, myposix.SIG_DFL)
    while term.eparser.queryState != qsNone:
      if term.ahandleRead().isErr:
        break
      while true:
        if term.areadEvent().isErr:
          break
    ?term.disableRawMode()
    term.clearCanvas()
  ok()

proc setQueryState(term: Terminal; qs: QueryState) =
  if term.eparser.queryState == qsNone:
    term.eparser.queryState = qs
  else:
    # I think this leaks on poorly written terminals, but one byte per
    # window change shouldn't be a problem
    term.eparser.queryStateStack.add(qs)

proc queryAttrs(term: Terminal; windowOnly: bool): Opt[void] =
  if tfPreEcma48 in term.desc:
    term.eparser.queryState = qsNone
    return ok()
  let ot = term.frameType
  # query in the current frame
  term.frameType = ftCurrent
  if not windowOnly:
    term.setQueryState(qsBackgroundColor)
    if tfXtermQuery in term.desc:
      if term.config.display.defaultBackgroundColor.isNone:
        ?term.write(QueryBackgroundColor)
      if term.config.display.defaultForegroundColor.isNone:
        ?term.write(QueryForegroundColor)
      if term.config.input.osc52Copy.isNone or
          term.config.input.osc52Primary.isNone:
        ?term.write(QueryXtermAllowedOps)
        ?term.write(QueryXtermWindowOps)
      if term.config.display.imageMode.isNone:
        if tfBleedsAPC notin term.desc:
          ?term.write(KittyQuery)
        ?term.write(QueryColorRegisters)
      elif term.config.display.imageMode.get == imSixel:
        ?term.write(QueryColorRegisters)
      if term.attrs.colorMode < cmTrueColor and
          term.config.display.colorMode.isNone:
        ?term.write(QueryTcapRGB)
      ?term.write(QueryANSIColors)
    ?term.write(DA1)
  else:
    term.setQueryState(qsCellSize)
  # We send these unconditionally because the OpenSSH fork of M$ returns
  # fake garbage in TIOCGWINSZ and this way we have a chance of the terminal
  # sending back real data to override that.
  if tfXtermQuery in term.desc:
    ?term.write(static(QueryCellSize & QueryWindowPixels))
  # The resize hack.
  #
  # All vaguely VT100-compatible terminals must implement CPR, so sending
  # this last should ensure that the query state is set to qsNone and
  # thereby prevent any user input from being processed as a query response.
  #
  # We also prefer this to XTerm's (Sun's?) window size querying mechanism
  # because some old tmux versions output botched responses to that.
  ?term.cursorGoto(9998, 9998)
  ?term.write(QueryCursorPosition)
  term.unsetCursorPos()
  term.frameType = ot
  term.startFlush()

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
        term.attrs.colorMode = cmEightBit
      elif n >= 16:
        term.attrs.colorMode = cmANSI
      s.setLen(i)
  else:
    var i = s.high
    while i >= 0 and s[i] in AsciiDigit:
      dec i
    if s.substr(0, i).endsWith("-direct"):
      term.attrs.colorMode = cmTrueColor
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
  when defined(freebsd):
    # FreeBSD console says it's an XTerm, but it responds to *absolutely
    # nothing*.
    if res == ttXterm:
      let KDGETMODE {.global, importc, header: "<sys/consio.h>".}: culong
      var mode: cint
      if ioctl(term.istream.fd, KDGETMODE, addr mode) != -1:
        res = ttFreebsd
  # zellij says it's its underlying terminal, but it isn't.
  if getEnv("ZELLIJ") != "":
    return ttZellij
  return res

proc applyTermDesc(term: Terminal; desc: Termdesc) =
  if tfColor1 in desc:
    if tfColor2 in desc:
      term.attrs.colorMode = cmTrueColor
    else:
      term.attrs.colorMode = cmANSI
  elif tfColor2 in desc:
    term.attrs.colorMode = cmEightBit
  if tfSixel in desc:
    term.imageMode = imSixel
  term.desc = desc
  case term.termType
  of ttVt52, ttAdm3a: discard
  of ttVt100Nav: term.formatMode = {ffReverse}
  of ttVt100: term.formatMode = {ffReverse, ffBold, ffBlink, ffUnderline}
  else:
    # Unless a terminal can't process one of these, it's OK to enable
    # all of them.
    term.formatMode = {FormatFlag.low..FormatFlag.high}

# when windowOnly, only refresh window size.
proc detectTermAttributes(term: Terminal; windowOnly: bool): Opt[void] =
  if not term.isatty():
    return ok()
  if not windowOnly:
    term.termType = term.parseTERM()
    let colorterm = getEnv("COLORTERM")
    if colorterm in ["24bit", "truecolor"]:
      term.attrs.colorMode = cmTrueColor
    term.applyTermDesc(TermdescMap[term.termType])
  let margin = int(tfMargin in term.desc)
  var win: IOctl_WinSize
  if ioctl(term.istream.fd, TIOCGWINSZ, addr win) != -1:
    if win.ws_col > 0:
      term.attrs.width = int(win.ws_col) - margin
      term.attrs.ppc = int(win.ws_xpixel) div term.attrs.width
    if win.ws_row > 0:
      term.attrs.height = int(win.ws_row)
      term.attrs.ppl = int(win.ws_ypixel) div term.attrs.height
  if term.attrs.width == 0:
    term.attrs.width = parseIntP(getEnv("COLUMNS")).get(0) - margin
  if term.attrs.height == 0:
    term.attrs.height = parseIntP(getEnv("LINES")).get(0)
  ok()

proc initCanvas(term: Terminal) =
  for frame in term.frames.mitems:
    frame.lineDamage = newSeq[int](term.attrs.height)
    frame.canvas = newSeq[FixedCell](term.attrs.width * term.attrs.height)
    frame.scrollBottom = -1

proc windowChange(term: Terminal) =
  term.applyConfigDimensions()
  term.initCanvas()
  term.clearCanvas()

proc queryWindowSize*(term: Terminal): Opt[void] =
  ?term.detectTermAttributes(windowOnly = true)
  ?term.queryAttrs(windowOnly = true)
  term.windowChange()
  ok()

proc initScreen(term: Terminal): Opt[void] =
  # note: deinit happens in quit()
  term.unblockIO()
  term.unsetCursorPos()
  if term.hasTitle():
    ?term.write(PushTitle)
  if term.hasAltScreen():
    ?term.write(SetAltScreen)
  if term.hasBracketedPaste():
    ?term.write(SetBracketedPaste)
  if term.hasMouse():
    ?term.write(SetSGRMouse)
    term.frame.mouseEnabled = true
  term.startFlush()

proc start*(term: Terminal; istream: PosixStream;
    registerCb: (proc(fd: int) {.raises: [].})): Opt[void] =
  term.ttyFlag = istream != nil and istream.isatty() and term.ostream.isatty()
  term.istream = istream
  term.registerCb = registerCb
  if term.isatty():
    ?term.detectTermAttributes(windowOnly = false)
    ?term.enableRawMode()
  term.applyConfig()
  if term.isatty():
    ?term.initScreen()
    # only query attrs after initializing screen to avoid moving the cursor
    # outside of the alt screen
    ?term.queryAttrs(windowOnly = false)
  term.initCanvas()
  ok()

proc restart*(term: Terminal): Opt[void] =
  if term.isatty():
    ?term.enableRawMode()
    ?term.initScreen()
  ok()

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
    termType: ttXterm,
    sixelRegisterNum: 256
  )

{.pop.} # raises: []
