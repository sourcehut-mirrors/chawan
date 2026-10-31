{.push raises: [].}

import io/chafile
import utils/chaos
import utils/opt
import utils/twtstr

proc parse(): Opt[void] =
  if getArgvCount() != 3:
    discard chaStderr.writeLine("Usage: img2html [content-type] [title]")
    quit(1)
  ?chaStdout.write("<!DOCTYPE html><title>" & getArgv(2).htmlEscape() &
    "</title><img src='data:" & getArgv(1) & ";base64,")
  var buffer {.noinit.}: array[6144, uint8]
  var s = ""
  while true:
    let n = chaStdin.read(buffer)
    if n <= 0:
      break
    s.btoa(buffer.toOpenArray(0, n - 1))
    ?chaStdout.write(s)
    s.setLen(0)
  ?chaStdout.write("'>")
  ok()

proc main*() =
  discard parse()

{.pop.} # raises: []
