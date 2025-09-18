import std/os

import utils/twtstr

import ansi2html
import dirlist2html
import gmi2html
import gopher2html
import img2html
import md2html

proc main() =
  case paramStr(0).afterLast('/')
  of "ansi2html": ansi2html.main()
  of "dirlist2html": dirlist2html.main()
  of "gmi2html": gmi2html.main()
  of "gopher2html": gopher2html.main()
  of "img2html": img2html.main()
  else: md2html.main()

main()
