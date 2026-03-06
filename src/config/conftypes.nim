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
