import types/color
import std/math

proc unlinear(x: float32): float32 =
  if x < 0:
    return 0
  if x >= 0.0031308:
    return 1.055 * pow(x, (1.0/2.4)) - 0.055
  return 12.92 * x

proc oklab2(L, a, b: float32; alpha: uint8): ARGBColor {.used.} =
  let lc = L + 0.3963377774'f32 * a + 0.2158037573'f32 * b
  let mc = L - 0.1055613458'f32 * a - 0.0638541728'f32 * b
  let sc = L - 0.0894841775'f32 * a - 1.2914855480'f32 * b
  let l = lc * lc * lc
  let m = mc * mc * mc
  let s = sc * sc * sc
  let rf = +4.0767416621'f32 * l - 3.3077115913'f32 * m + 0.2309699292'f32 * s
  let gf = -1.2684380046'f32 * l + 2.6097574011'f32 * m - 0.3413193965'f32 * s
  let bf = -0.0041960863'f32 * l - 0.7034186147'f32 * m + 1.7076147010'f32 * s
  let r = uint8(unlinear(rf) * 255 + 0.5'f32)
  let g = uint8(unlinear(gf) * 255 + 0.5'f32)
  let b = uint8(unlinear(bf) * 255 + 0.5'f32)
  return rgba(r, g, b, alpha)

proc main() =
  var diff = 0
  var maxl = 0'u16
  var mina = int32.high
  var maxa = int32.low
  var minb = int32.high
  var maxb = int32.low
  var avgdiff = 0
  var n = 0
  for c in 0 .. 0xFFFFFF:
    let c = RGBColor(c)
    let oc = c.oklab()
    let ocr = oc.rgb()
    #let l = float32(oc.l) / 65535'f32
    #let a = float32(oc.a) / 65535'f32
    #let b = float32(oc.b) / 65535'f32
    #let ocr = oklab2(l, a, b, 255).rgb()
    n += 3
    diff = max(diff, abs(int(c.r) - int(ocr.r)))
    diff = max(diff, abs(int(c.g) - int(ocr.g)))
    diff = max(diff, abs(int(c.b) - int(ocr.b)))
    avgdiff += abs(int(c.r) - int(ocr.r))
    avgdiff += abs(int(c.g) - int(ocr.g))
    avgdiff += abs(int(c.b) - int(ocr.b))
    assert oc.L >= 0
    maxl = max(oc.L, maxl)
    mina = min(oc.A, mina)
    maxa = max(oc.A, maxa)
    minb = min(oc.B, minb)
    maxb = max(oc.B, maxb)
  echo "max diff ", diff, " maxl ", maxl, " mina ", mina, " maxa ", maxa,
    " minb ", minb, " maxb ", maxb, " avg ", float32(avgdiff) / float32(n)

main()
