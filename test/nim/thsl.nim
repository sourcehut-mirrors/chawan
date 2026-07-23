import types/color
import std/math

proc main() =
  var diff = 0
  var avgdiff = 0
  var n = 0
  for c in 0 .. 0xFFFFFF:
    let c = RGBColor(c).argb(255)
    let oc = c.hsla()
    let ocr = oc.argb().rgb()
    n += 3
    diff = max(diff, abs(int(c.r) - int(ocr.r)))
    diff = max(diff, abs(int(c.g) - int(ocr.g)))
    diff = max(diff, abs(int(c.b) - int(ocr.b)))
    if diff > 8:
      eprint "diff", diff, "c", c, "oc", oc, "ocr", ocr
      quit(1)
    avgdiff += abs(int(c.r) - int(ocr.r))
    avgdiff += abs(int(c.g) - int(ocr.g))
    avgdiff += abs(int(c.b) - int(ocr.b))
  echo "max diff ", diff, " avg ", float32(avgdiff) / float32(n)

main()
