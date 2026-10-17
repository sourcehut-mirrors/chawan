{.push raises: [].}

import io/chafile
import utils/chaos
import utils/cowstr
import utils/opt
import utils/twtstr

proc getField(line: Str; i: var int): Str =
  let s = line.until('\t', i)
  i += s.len
  if i < line.len and line[i] == '\t':
    inc i
  s

proc parse(): Opt[void] =
  if getArgvCount() != 3 or getArgvCString(1) != "-u":
    discard chaStdout.writeLine("Usage: gopher2html [-u URL]")
    quit(1)
  let url = htmlEscape(getArgv(2))
  ?chaStdout.write(initStrM("""<!DOCTYPE html>
<title>Index of """, url, """</title>
<h1>Index of """, url, """</h1>"""))
  var ispre = false
  var line: Str
  while ?chaStdin.readLine(line):
    if line.len == 0:
      continue
    let t = line[0]
    if t == '.':
      break # end
    var i = 1
    let name = line.getField(i)
    var file = line.getField(i)
    let host = line.getField(i)
    let port = line.until('\t', i) # ignore anything after port
    var outs = initGrowbuf()
    if t == 'i':
      if not ispre:
        outs &= "<pre>"
        ispre = true
      outs &= htmlEscape(name)
    else:
      if ispre:
        outs &= "</pre>"
        ispre = false
      let ourls = if not file.startsWith("URL:"):
        if file.len == 0 or file[0] != '/':
          file = initStrM('/', file)
        let pefile = file.percentEncode(PathPercentEncodeSet)
        initStrM("gopher://", host, ':', port, '/', t, pefile)
      else:
        file.substr("URL:".len)
      outs.addM("<a item-type=\"", htmlEscape([t]), "\" href=\"",
        htmlEscape(ourls), "\">", htmlEscape(name), "</a><br>")
    ?chaStdout.writeLine(outs.toOpenArray())
  ok()

proc main*() =
  discard parse()

{.pop.} # raises: []
