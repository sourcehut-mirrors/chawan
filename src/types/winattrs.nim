type WindowAttributes* = object
  width*: int
  height*: int
  ppc*: int # cell width (pixels per char)
  ppl*: int # cell height (pixels per line)
  widthPx*: int
  heightPx*: int
  prefersDark*: bool # prefers-color-scheme accepts "dark" (not "light")

let dummyAttrs* {.global.} = WindowAttributes(
  width: 80,
  height: 24,
  ppc: 9,
  ppl: 18,
  widthPx: 80 * 9,
  heightPx: 24 * 18,
  prefersDark: true
)
