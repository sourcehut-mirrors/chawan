import std/os

import utils/twtstr

proc main() =
  if paramCount() != 2:
    stderr.writeLine("Usage: img2html [content-type] [title]")
    quit(1)
  stdout.write("<!DOCTYPE html><title>" & paramStr(2).htmlEscape() &
    "</title><img src='data:" & paramStr(1) & ";base64,")
  var buffer {.noinit.}: array[6144, uint8]
  var s = ""
  while true:
    let n = stdin.readBuffer(addr buffer[0], buffer.len)
    if n == 0:
      break
    s.btoa(buffer.toOpenArray(0, n - 1))
    stdout.write(s)
    s.setLen(0)
  stdout.write("'>")

main()
