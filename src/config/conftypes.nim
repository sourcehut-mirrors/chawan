type
  ColorMode* = enum
    cmMonochrome = "monochrome"
    cmANSI = "ansi"
    cmEightBit = "eight-bit"
    cmTrueColor = "true-color"

  HeadlessMode* = enum
    hmFalse = "false"
    hmTrue = "true"
    hmDump = "dump"

  ScriptingMode* = enum
    smFalse = "false"
    smTrue = "true"
    smApp = "app"

  CookieMode* = enum
    cmNone = "false"
    cmReadOnly = "true"
    cmSave = "save"

  MetaRefresh* = enum
    mrAsk = "ask"
    mrNever = "never"
    mrAlways = "always"

  ImageMode* = enum
    imNone = "none"
    imSixel = "sixel"
    imKitty = "kitty"

  WindowAttributes* = object
    width*: int
    height*: int
    ppc*: int # cell width (pixels per char)
    ppl*: int # cell height (pixels per line)
    widthPx*: int
    heightPx*: int
    prefersDark*: bool # prefers-color-scheme accepts "dark" (not "light")
    colorMode*: ColorMode

let dummyAttrs* {.global.} = WindowAttributes(
  width: 80,
  height: 24,
  ppc: 9,
  ppl: 18,
  widthPx: 80 * 9,
  heightPx: 24 * 18,
  prefersDark: true,
  colorMode: cmTrueColor
)
