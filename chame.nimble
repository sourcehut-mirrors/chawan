# Package

version       = "0.14.4"
author        = "bptato"
description   = "HTML5 parser for Chawan"
license       = "Unlicense"


# Dependencies

requires "nim >= 1.6.10"
when NimMajor >= 2:
  taskRequires "test", "https://git.sr.ht/~bptato/chakasu"
