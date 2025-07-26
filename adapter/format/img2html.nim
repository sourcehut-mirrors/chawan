{.push raises: [].}

import std/os

import io/chafile
import types/opt
import utils/twtstr

proc main(): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  let stdin = cast[ChaFile](stdin)
  let stderr = cast[ChaFile](stderr)
  if paramCount() != 2:
    discard stderr.writeLine("Usage: img2html [content-type] [title]")
    quit(1)
  ?stdout.write("<!DOCTYPE html><title>" & paramStr(2).htmlEscape() &
    "</title><img src='data:" & paramStr(1) & ";base64,")
  var buffer {.noinit.}: array[6144, uint8]
  var s = ""
  while true:
    let n = stdin.read(buffer)
    if n <= 0:
      break
    s.btoa(buffer.toOpenArray(0, n - 1))
    ?stdout.write(s)
    s.setLen(0)
  ?stdout.write("'>")
  ok()

discard main()

{.pop.} # raises: []
