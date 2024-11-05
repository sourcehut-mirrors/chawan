import utils/luwrap
import utils/strwidth
import utils/twtstr

type BreakCategory* = enum
  bcAlpha, bcSpace, bcSymbol, bcHan, bcHiragana, bcKatakana, bcHangul

func isDigitAscii(u: uint32): bool =
  return u < 128 and char(u) in AsciiDigit

proc breaksWord*(ctx: LUContext; u: uint32): bool =
  return not u.isDigitAscii() and u.width() != 0 and not ctx.isAlpha(u)

proc breaksViWordCat*(ctx: LUContext; u: uint32): BreakCategory =
  if u < 0x80: # ASCII
    let c = char(u)
    if c in AsciiAlphaNumeric + {'_'}:
      return bcAlpha
    elif c in AsciiWhitespace:
      return bcSpace
  elif ctx.isWhiteSpace(u):
    return bcSpace
  elif ctx.isAlpha(u):
    if ctx.isHiragana(u):
      return bcHiragana
    elif ctx.isKatakana(u):
      return bcKatakana
    elif ctx.isHangul(u):
      return bcHangul
    elif ctx.isHan(u):
      return bcHan
    return bcAlpha
  return bcSymbol

proc breaksWordCat*(ctx: LUContext; u: uint32): BreakCategory =
  if not ctx.breaksWord(u):
    return bcAlpha
  return bcSpace

proc breaksBigWordCat*(ctx: LUContext; u: uint32): BreakCategory =
  if not ctx.isWhiteSpace(u):
    return bcAlpha
  return bcSpace
