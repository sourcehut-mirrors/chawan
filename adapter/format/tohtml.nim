{.push raises: [].}

import utils/chaos

import ansi2html
import dirlist2html
import gmi2html
import gopher2html
import img2html
import md2html

proc main() =
  let scheme = basename(getArgvCString(0))
  if scheme == "ansi2html":
    ansi2html.main()
  elif scheme == "dirlist2html":
    dirlist2html.main()
  elif scheme == "gmi2html":
    gmi2html.main()
  elif scheme == "gopher2html":
    gopher2html.main()
  elif scheme == "img2html":
    img2html.main()
  else:
    md2html.main()

main()

{.pop.}
