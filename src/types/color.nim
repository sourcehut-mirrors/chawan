{.push raises: [].}

from std/strutils import cmpIgnoreCase

import std/algorithm

import types/opt
import utils/dtoawrap
import utils/twtstr

type
  RGBColor* = distinct uint32

  # ARGB color. machine-dependent format, so that bit shifts and arithmetic
  # works. (Alpha is MSB, then come R, G, B.)
  ARGBColor* = distinct uint32

  # RGBA format; machine-independent, always big-endian.
  RGBAColorBE* {.packed.} = object
    r*: uint8
    g*: uint8
    b*: uint8
    a*: uint8

  # Either a 3-bit ANSI color (0..7), a 3-bit bright ANSI color (8..15),
  # a color on the RGB cube (16..231), or a grayscale color (232..255).
  ANSIColor* = distinct uint8

  # ctNone: default color (intentionally 0), n is unused
  # ctANSI: ANSI color, as selected by SGR 38/48
  # ctRGB: RGB color
  ColorTag* = enum
    ctNone, ctANSI, ctRGB

  # Color that can be represented by a terminal cell.
  # Crucially, this does not include colors with an alpha channel.
  CellColor* = distinct uint32

  CSSColorType* = enum
    cctARGB, cctCell, cctCurrent

  # Color that can be represented in CSS.
  # As an extension, we also recognize ANSI colors, so ARGB does not suffice.
  # (Actually, it would, but then we'd have to copy over the ANSI color
  # table and then re-quantize on render. I'm fine with wasting a few
  # bytes instead.)
  CSSColor* = object
    t*: CSSColorType
    n: uint32

proc rgba*(r, g, b, a: uint8): ARGBColor

# bitmasked so nimvm doesn't choke on it
proc r*(c: ARGBColor): uint8 =
  return uint8((uint32(c) shr 16) and 0xFF)

proc g*(c: ARGBColor): uint8 =
  return uint8((uint32(c) shr 8) and 0xFF)

proc b*(c: ARGBColor): uint8 =
  return uint8((uint32(c) and 0xFF))

proc a*(c: ARGBColor): uint8 =
  return uint8(uint32(c) shr 24)

proc rgb*(c: ARGBColor): RGBColor =
  return RGBColor(uint32(c) and 0xFFFFFFu32)

proc argb*(c: RGBColor; a: uint8): ARGBColor =
  return ARGBColor((uint32(c) and 0x00FFFFFFu32) or (uint32(a) shl 24))

proc argb*(c: RGBColor): ARGBColor =
  return ARGBColor(uint32(c) or 0xFF000000u32)

proc argb*(c: RGBAColorBE): ARGBColor =
  return rgba(c.r, c.g, c.b, c.a)

proc `==`*(a, b: ARGBColor): bool {.borrow.}

proc `==`*(a, b: RGBColor): bool {.borrow.}

proc `==`*(a, b: ANSIColor): bool {.borrow.}

proc `==`*(a, b: CellColor): bool {.borrow.}

proc t*(color: CellColor): ColorTag =
  return cast[ColorTag]((uint32(color) shr 24) and 0x3)

proc toUint26*(color: CellColor): uint32 =
  return uint32(color) and 0x3FFFFFF

proc rgb*(color: CellColor): RGBColor =
  return RGBColor(uint32(color) and 0xFFFFFF)

proc ansi*(color: CellColor): ANSIColor =
  return ANSIColor(color)

proc cellColor(t: ColorTag; n: uint32): CellColor =
  return CellColor((uint32(t) shl 24) or (n and 0xFFFFFF))

proc cellColor*(rgb: RGBColor): CellColor =
  return cellColor(ctRGB, uint32(rgb))

proc cellColor*(c: ANSIColor): CellColor =
  return cellColor(ctANSI, uint32(c))

const defaultColor* = cellColor(ctNone, 0)

proc cssColor*(c: ARGBColor): CSSColor =
  return CSSColor(t: cctARGB, n: uint32(c))

proc cssColor*(c: RGBColor): CSSColor =
  return c.argb.cssColor()

proc cssColor*(c: CellColor): CSSColor =
  return CSSColor(t: cctCell, n: uint32(c))

proc cssColor*(c: ANSIColor): CSSColor =
  return c.cellColor().cssColor()

proc cssCurrentColor*(): CSSColor =
  return CSSColor(t: cctCurrent)

proc argb*(c: CSSColor): ARGBColor =
  return ARGBColor(c.n)

proc a*(c: CSSColor): uint8 =
  if c.t == cctCell:
    if CellColor(c.n).t == ctNone:
      return 0
    return 255
  return c.argb().a

proc rgbTransparent*(c: CSSColor): bool =
  return c.t == cctARGB and c.argb().a == 0

proc cellColor*(c: CSSColor): CellColor =
  if c.t == cctCell:
    return CellColor(c.n)
  if c.argb.a == 0:
    return defaultColor
  return cellColor(ctRGB, c.n)

const ColorsRGBMap = {
  "aliceblue": 0xF0F8FFu32,
  "antiquewhite": 0xFAEBD7u32,
  "aqua": 0x00FFFFu32,
  "aquamarine": 0x7FFFD4u32,
  "azure": 0xF0FFFFu32,
  "beige": 0xF5F5DCu32,
  "bisque": 0xFFE4C4u32,
  "black": 0x000000u32,
  "blanchedalmond": 0xFFEBCDu32,
  "blue": 0x0000FFu32,
  "blueviolet": 0x8A2BE2u32,
  "brown": 0xA52A2Au32,
  "burlywood": 0xDEB887u32,
  "cadetblue": 0x5F9EA0u32,
  "chartreuse": 0x7FFF00u32,
  "chocolate": 0xD2691Eu32,
  "coral": 0xFF7F50u32,
  "cornflowerblue": 0x6495EDu32,
  "cornsilk": 0xFFF8DCu32,
  "crimson": 0xDC143Cu32,
  "cyan": 0x00FFFFu32,
  "darkblue": 0x00008Bu32,
  "darkcyan": 0x008B8Bu32,
  "darkgoldenrod": 0xB8860Bu32,
  "darkgray": 0xA9A9A9u32,
  "darkgreen": 0x006400u32,
  "darkgrey": 0xA9A9A9u32,
  "darkkhaki": 0xBDB76Bu32,
  "darkmagenta": 0x8B008Bu32,
  "darkolivegreen": 0x556B2Fu32,
  "darkorange": 0xFF8C00u32,
  "darkorchid": 0x9932CCu32,
  "darkred": 0x8B0000u32,
  "darksalmon": 0xE9967Au32,
  "darkseagreen": 0x8FBC8Fu32,
  "darkslateblue": 0x483D8Bu32,
  "darkslategray": 0x2F4F4Fu32,
  "darkslategrey": 0x2F4F4Fu32,
  "darkturquoise": 0x00CED1u32,
  "darkviolet": 0x9400D3u32,
  "deeppink": 0xFF1493u32,
  "deepskyblue": 0x00BFFFu32,
  "dimgray": 0x696969u32,
  "dimgrey": 0x696969u32,
  "dodgerblue": 0x1E90FFu32,
  "firebrick": 0xB22222u32,
  "floralwhite": 0xFFFAF0u32,
  "forestgreen": 0x228B22u32,
  "fuchsia": 0xFF00FFu32,
  "gainsboro": 0xDCDCDCu32,
  "ghostwhite": 0xF8F8FFu32,
  "gold": 0xFFD700u32,
  "goldenrod": 0xDAA520u32,
  "gray": 0x808080u32,
  "green": 0x008000u32,
  "greenyellow": 0xADFF2Fu32,
  "grey": 0x808080u32,
  "honeydew": 0xF0FFF0u32,
  "hotpink": 0xFF69B4u32,
  "indianred": 0xCD5C5Cu32,
  "indigo": 0x4B0082u32,
  "ivory": 0xFFFFF0u32,
  "khaki": 0xF0E68Cu32,
  "lavender": 0xE6E6FAu32,
  "lavenderblush": 0xFFF0F5u32,
  "lawngreen": 0x7CFC00u32,
  "lemonchiffon": 0xFFFACDu32,
  "lightblue": 0xADD8E6u32,
  "lightcoral": 0xF08080u32,
  "lightcyan": 0xE0FFFFu32,
  "lightgoldenrodyellow": 0xFAFAD2u32,
  "lightgray": 0xD3D3D3u32,
  "lightgreen": 0x90EE90u32,
  "lightgrey": 0xD3D3D3u32,
  "lightpink": 0xFFB6C1u32,
  "lightsalmon": 0xFFA07Au32,
  "lightseagreen": 0x20B2AAu32,
  "lightskyblue": 0x87CEFAu32,
  "lightslategray": 0x778899u32,
  "lightslategrey": 0x778899u32,
  "lightsteelblue": 0xB0C4DEu32,
  "lightyellow": 0xFFFFE0u32,
  "lime": 0x00FF00u32,
  "limegreen": 0x32CD32u32,
  "linen": 0xFAF0E6u32,
  "magenta": 0xFF00FFu32,
  "maroon": 0x800000u32,
  "mediumaquamarine": 0x66CDAAu32,
  "mediumblue": 0x0000CDu32,
  "mediumorchid": 0xBA55D3u32,
  "mediumpurple": 0x9370DBu32,
  "mediumseagreen": 0x3CB371u32,
  "mediumslateblue": 0x7B68EEu32,
  "mediumspringgreen": 0x00FA9Au32,
  "mediumturquoise": 0x48D1CCu32,
  "mediumvioletred": 0xC71585u32,
  "midnightblue": 0x191970u32,
  "mintcream": 0xF5FFFAu32,
  "mistyrose": 0xFFE4E1u32,
  "moccasin": 0xFFE4B5u32,
  "navajowhite": 0xFFDEADu32,
  "navy": 0x000080u32,
  "oldlace": 0xFDF5E6u32,
  "olive": 0x808000u32,
  "olivedrab": 0x6B8E23u32,
  "orange": 0xFFA500u32,
  "orangered": 0xFF4500u32,
  "orchid": 0xDA70D6u32,
  "palegoldenrod": 0xEEE8AAu32,
  "palegreen": 0x98FB98u32,
  "paleturquoise": 0xAFEEEEu32,
  "palevioletred": 0xDB7093u32,
  "papayawhip": 0xFFEFD5u32,
  "peachpuff": 0xFFDAB9u32,
  "peru": 0xCD853Fu32,
  "pink": 0xFFC0CBu32,
  "plum": 0xDDA0DDu32,
  "powderblue": 0xB0E0E6u32,
  "purple": 0x800080u32,
  "rebeccapurple": 0x663399u32,
  "red": 0xFF0000u32,
  "rosybrown": 0xBC8F8Fu32,
  "royalblue": 0x4169E1u32,
  "saddlebrown": 0x8B4513u32,
  "salmon": 0xFA8072u32,
  "sandybrown": 0xF4A460u32,
  "seagreen": 0x2E8B57u32,
  "seashell": 0xFFF5EEu32,
  "sienna": 0xA0522Du32,
  "silver": 0xC0C0C0u32,
  "skyblue": 0x87CEEBu32,
  "slateblue": 0x6A5ACDu32,
  "slategray": 0x708090u32,
  "slategrey": 0x708090u32,
  "snow": 0xFFFAFAu32,
  "springgreen": 0x00FF7Fu32,
  "steelblue": 0x4682B4u32,
  "tan": 0xD2B48Cu32,
  "teal": 0x008080u32,
  "thistle": 0xD8BFD8u32,
  "tomato": 0xFF6347u32,
  "turquoise": 0x40E0D0u32,
  "violet": 0xEE82EEu32,
  "wheat": 0xF5DEB3u32,
  "white": 0xFFFFFFu32,
  "whitesmoke": 0xF5F5F5u32,
  "yellow": 0xFFFF00u32,
  "yellowgreen": 0x9ACD32u32,
}

proc namedRGBColor*(s: string): Opt[RGBColor] =
  let i = ColorsRGBMap.binarySearch(s,
    proc(x: (string, uint32); y: string): int =
      return x[0].cmpIgnoreCase(y)
  )
  if i != -1:
    return ok(RGBColor(ColorsRGBMap[i][1]))
  return err()

# https://html.spec.whatwg.org/#serialisation-of-a-color
proc serialize*(c: ARGBColor): string =
  if c.a == 255:
    var res = "#"
    res.pushHex(c.r)
    res.pushHex(c.g)
    res.pushHex(c.b)
    return move(res)
  let a = float64(c.a) / 255
  result = "rgba(" & $c.r & ", " & $c.g & ", " & $c.b & ", "
  result.addDouble(a)
  result &= ')'

proc `$`*(c: ARGBColor): string =
  return c.serialize()

proc `$`*(c: RGBColor): string =
  return c.argb().serialize()

proc `$`*(c: CSSColor): string =
  case c.t
  of cctCell: return "-cha-ansi(" & $c.n & ")"
  of cctCurrent: return "currentcolor"
  of cctARGB:
    let c = c.argb()
    if c.a != 255:
      return c.serialize()
    return "rgb(" & $c.r & ", " & $c.g & ", " & $c.b & ")"

proc `$`*(color: CellColor): string =
  case color.t
  of ctNone: "none"
  of ctRGB: $color.rgb
  of ctANSI: "-cha-ansi(" & $uint8(color.ansi()) & ")"

# Divide each component by 255, multiply them by n, and discard the fractions.
# See https://arxiv.org/pdf/2202.02864.pdf for details.
proc fastmul*(c: ARGBColor; n: uint32): ARGBColor =
  var c = (uint64(c) shl 24) or uint64(c)
  c = c and 0x00FF00FF00FF00FFu64
  c *= n
  c += 0x80008000800080u64
  c += (c shr 8) and 0x00FF00FF00FF00FFu64
  c = c and 0xFF00FF00FF00FF00u64
  c = (c shr 32) or (c shr 8)
  return ARGBColor(c)

proc premul(c: ARGBColor): ARGBColor =
  let a = uint32(c.a)
  let c = ARGBColor(uint32(c) or 0xFF000000u32)
  return c.fastmul(a)

# This is somewhat faster than floats or a lookup table, and is correct for
# all inputs.
proc straight(c: ARGBColor): ARGBColor =
  let a8 = c.a
  if a8 == 0:
    return ARGBColor(0)
  let a = uint32(a8)
  let r = ((uint32(c.r) * 0xFF00 div a + 0x80) shr 8) and 0xFF
  let g = ((uint32(c.g) * 0xFF00 div a + 0x80) shr 8) and 0xFF
  let b = ((uint32(c.b) * 0xFF00 div a + 0x80) shr 8) and 0xFF
  return ARGBColor((a shl 24) or (r shl 16) or (g shl 8) or b)

# Note: this is a very poor approximation, as the premultiplication
# already discards fractions...
proc blend*(c0, c1: ARGBColor): ARGBColor =
  let pc0 = c0.premul()
  let pc1 = c1.premul()
  let k = 255 - pc1.a
  let mc = pc0.fastmul(uint32(k))
  let rr = pc1.r + mc.r
  let rg = pc1.g + mc.g
  let rb = pc1.b + mc.b
  let ra = pc1.a + mc.a
  let pres = rgba(rr, rg, rb, ra)
  return straight(pres)

# Blending operation for cell colors.
# Normally, this should only happen with RGB color, so if either color is
# not one, we can just return fg.
# sbg is the bgcolor of the canvas; we fall back to it if the cell's bgcolor
# is empty, so that we hopefully get something meaningful back.
# If we still end up with cellColor, we just blend over white which is the
# canvas color on all mainstream browsers these days.
proc blend*(bg, sbg, fg: CellColor; a: uint8): CellColor =
  if fg.t != ctRGB:
    return fg
  let bg = if bg.t == ctRGB:
    bg.rgb.argb
  elif sbg.t == ctRGB:
    sbg.rgb.argb
  else:
    rgba(255, 255, 255, 255)
  let fg = fg.rgb.argb(a)
  return bg.blend(fg).rgb.cellColor()

proc rgb*(r, g, b: uint8): RGBColor =
  return RGBColor((uint32(r) shl 16) or (uint32(g) shl 8) or uint32(b))

proc r*(c: RGBColor): uint8 =
  return uint8(uint32(c) shr 16)

proc g*(c: RGBColor): uint8 =
  return uint8(uint32(c) shr 8)

proc b*(c: RGBColor): uint8 =
  return uint8(uint32(c))

# see https://learn.microsoft.com/en-us/previous-versions/windows/embedded/ms893078(v=msdn.10)
proc Y*(c: RGBColor): uint8 =
  let rmul = uint16(c.r) * 66u16
  let gmul = uint16(c.g) * 129u16
  let bmul = uint16(c.b) * 25u16
  return uint8(((rmul + gmul + bmul + 128) shr 8) + 16)

proc U*(c: RGBColor): uint8 =
  let rmul = uint16(c.r) * 38u16
  let gmul = uint16(c.g) * 74u16
  let bmul = uint16(c.b) * 112u16
  return uint8(((128 + bmul - rmul - gmul) shr 8) + 128)

proc V*(c: RGBColor): uint8 =
  let rmul = uint16(c.r) * 112u16
  let gmul = uint16(c.g) * 94u16
  let bmul = uint16(c.b) * 18u16
  return uint8(((128 + rmul - gmul - bmul) shr 8) + 128)

proc YUV*(Y, U, V: uint8): RGBColor =
  let C = int(Y) - 16
  let D = int(U) - 128
  let E = int(V) - 128
  let r = max(min((298 * C + 409 * E + 128) shr 8, 255), 0)
  let g = max(min((298 * C - 100 * D - 208 * E + 128) shr 8, 255), 0)
  let b = max(min((298 * C + 516 * D + 128) shr 8, 255), 0)
  return rgb(uint8(r), uint8(g), uint8(b))

proc rgba*(r, g, b, a: uint8): ARGBColor =
  return ARGBColor((uint32(a) shl 24) or (uint32(r) shl 16) or
    (uint32(g) shl 8) or uint32(b))

proc rgba_be*(r, g, b, a: uint8): RGBAColorBE =
  return RGBAColorBE(r: r, g: g, b: b, a: a)

proc rgba*(r, g, b, a: int): ARGBColor =
  return rgba(uint8(r), uint8(g), uint8(b), uint8(a))

proc gray*(n: uint8): RGBColor =
  return rgb(n, n, n)

# I found this algorithm in yaft, but as far as I can tell, it
# originates from Microsoft.
proc hue2rgb(n1, n2, h: uint32): uint32 =
  let h = if h > 360: h - 360 else: h
  if h < 60:
    return n1 + ((n2 - n1) * h + 30) div 60
  if h < 180:
    return n2
  if h < 240:
    return n1 + ((n2 - n1) * (240 - h) + 30) div 60
  return n1

proc hsla*(h: uint32; s, l, a: uint8): ARGBColor =
  let s = uint32(s)
  let l = uint32(l)
  let magic2 = if l <= 50:
    (l * (100 + s) + 50) div 100
  else:
    l + s - ((l * s) + 50) div 100
  let magic1 = l * 2 - magic2
  let r = uint8((hue2rgb(magic1, magic2, h + 120) * 255 + 50) div 100)
  let g = uint8((hue2rgb(magic1, magic2, h) * 255 + 50) div 100)
  let b = uint8((hue2rgb(magic1, magic2, h + 240) * 255 + 50) div 100)
  return rgba(r, g, b, a)

# Note: this assumes n notin 0..15 (which would be ANSI 4-bit)
proc toRGB*(param0: ANSIColor): RGBColor =
  let u = uint8(param0)
  assert u notin 0u8..15u8
  if u < 232:
    let n = u - 16
    var r = (n div 36) * 40
    var g = ((n mod 36) div 6) * 40
    var b = (n mod 6) * 40
    if r > 0:
      r += 55
    if g > 0:
      g += 55
    if b > 0:
      b += 55
    return rgb(r, g, b)
  # 232..255
  return gray((u - 232) * 10 + 8)

proc toEightBit*(c: RGBColor): ANSIColor =
  # XTerm's cube is components rotated as 0, 95, 135, 175, 215, 255.
  # Given that there are 6 indices (0..5), it is tempting to just multiply c by
  # 5, divide by 255, and choose the location on the cube with that.  However,
  # that's incorrect, since our indices aren't mapped uniformly over 0..255.
  # So instead, we approximate 0..95 by using two sevenths of the range.
  let cc = c.argb().fastmul(6)
  let r0 = max(cc.r, 1) - 1
  let g0 = max(cc.g, 1) - 1
  let b0 = max(cc.b, 1) - 1
  if r0 == g0 and g0 == b0:
    let mid = min(min(max(c.r, c.g), max(c.g, c.b)), max(c.r, c.b))
    # First check for mid < 5 and mid > 249, consider that black or white.
    # (Note: we cheat with wraparound.)
    # Then, check for an approximate match with the alternative grays on the
    # cube; if there is no match, go with the gradient.
    if mid - 5 < 245 and mid shr 2 notin [0x17u8, 0x21u8, 0x2Bu8, 0x35u8]:
      # Multiply by 25, then divide by 255.
      let x = uint8((uint32(mid) * 25 + 0x80) shr 8)
      # Gray values start at 232, but we index from 1 because we skip black.
      # (This is not a perfect approximation, but it's good enough in practice.)
      return ANSIColor(x + 231)
  return ANSIColor(uint8(16 + r0 * 36 + g0 * 6 + b0))

proc parseHexColor*(s: openArray[char]): Opt[ARGBColor] =
  for c in s:
    if c notin AsciiHexDigit:
      return err()
  case s.len
  of 6:
    let c = 0xFF000000 or
      (hexValue(s[0]) shl 20) or (hexValue(s[1]) shl 16) or
      (hexValue(s[2]) shl 12) or (hexValue(s[3]) shl 8) or
      (hexValue(s[4]) shl 4) or hexValue(s[5])
    return ok(ARGBColor(c))
  of 8:
    let c = (hexValue(s[6]) shl 28) or (hexValue(s[7]) shl 24) or
      (hexValue(s[0]) shl 20) or (hexValue(s[1]) shl 16) or
      (hexValue(s[2]) shl 12) or (hexValue(s[3]) shl 8) or
      (hexValue(s[4]) shl 4) or hexValue(s[5])
    return ok(ARGBColor(c))
  of 3:
    let c = 0xFF000000 or
      (hexValue(s[0]) shl 20) or (hexValue(s[0]) shl 16) or
      (hexValue(s[1]) shl 12) or (hexValue(s[1]) shl 8) or
      (hexValue(s[2]) shl 4) or hexValue(s[2])
    return ok(ARGBColor(c))
  of 4:
    let c = (hexValue(s[3]) shl 28) or (hexValue(s[3]) shl 24) or
      (hexValue(s[0]) shl 20) or (hexValue(s[0]) shl 16) or
      (hexValue(s[1]) shl 12) or (hexValue(s[1]) shl 8) or
      (hexValue(s[2]) shl 4) or hexValue(s[2])
    return ok(ARGBColor(c))
  else:
    return err()

proc parseARGBColor*(s: string): Opt[ARGBColor] =
  if x := namedRGBColor(s):
    return ok(x.argb)
  if (s.len == 3 or s.len == 4 or s.len == 6 or s.len == 8) and s[0] == '#':
    return parseHexColor(s.toOpenArray(1, s.high))
  if s.len > 2 and s[0] == '0' and s[1] == 'x':
    return parseHexColor(s.toOpenArray(2, s.high))
  return parseHexColor(s)

proc myHexValue(c: char): uint32 =
  let n = hexValue(c)
  if n != -1:
    return uint32(n)
  return 0

proc parseLegacyColor0*(s: string): RGBColor =
  if s.len <= 0:
    return rgb(0, 0, 0)
  if x := namedRGBColor(s):
    return x
  if s.len == 4 and s[0] == '#':
    let r = hexValue(s[1])
    let g = hexValue(s[2])
    let b = hexValue(s[3])
    if r != -1 and g != -1 and b != -1:
      return rgb(uint8(r * 17), uint8(g * 17), uint8(b * 17))
  # o_0
  var s2 = if s[0] == '#':
    s.substr(1)
  else:
    s
  while s2.len == 0 or s2.len mod 3 != 0:
    s2 &= '0'
  let l = s2.len div 3
  let c = if l == 1:
    (myHexValue(s2[0]) shl 20) or (myHexValue(s2[0]) shl 16) or
    (myHexValue(s2[1]) shl 12) or (myHexValue(s2[1]) shl 8) or
    (myHexValue(s2[2]) shl 4) or myHexValue(s2[2])
  else:
    (myHexValue(s2[0]) shl 20) or (myHexValue(s2[1]) shl 16) or
    (myHexValue(s2[l]) shl 12) or (myHexValue(s2[l + 1]) shl 8) or
    (myHexValue(s2[l * 2]) shl 4) or myHexValue(s2[l * 2 + 1])
  return RGBColor(c)

{.pop.} # raises: []
