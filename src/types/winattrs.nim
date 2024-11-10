type WindowAttributes* = object
  width*: int
  height*: int
  ppc*: int # cell width (pixels per char)
  ppl*: int # cell height (pixels per line)
  widthPx*: int
  heightPx*: int
  prefersDark*: bool # prefers-color-scheme accepts "dark" (not "light")
