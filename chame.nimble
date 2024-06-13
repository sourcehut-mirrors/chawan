# Package

version       = "0.14.5"
author        = "bptato"
description   = "HTML5 parser for Chawan"
license       = "Unlicense"


# Dependencies

requires "nim >= 1.6.10"
when declared(taskRequires):
  taskRequires "test", "chagashi >= 0.5.0"
