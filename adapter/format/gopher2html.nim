{.push raises: [].}

import std/os
import std/strutils

import io/chafile
import types/opt
import utils/twtstr

func gopherName(c: char): string =
  return case c
  of '0': "text file"
  of '1': "directory"
  of '3': "error"
  of '5': "DOS binary"
  of '7': "search"
  of 'm': "message"
  of 's', '<': "sound"
  of 'g': "gif"
  of 'h': "HTML"
  of 'I', ':': "image"
  of '9': "binary"
  of 'p': "png"
  of ';': "video"
  else: "unsupported"

proc getField(line: string; i: var int): string =
  var s = line.until('\t', i)
  i += s.len
  if i < line.len and line[i] == '\t':
    inc i
  move(s)

proc main(): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  let stdin = cast[ChaFile](stdin)
  if paramCount() != 2 or paramStr(1) != "-u":
    discard stdout.writeLine("Usage: gopher2html [-u URL]")
    quit(1)
  let url = htmlEscape(paramStr(2))
  ?stdout.write("""<!DOCTYPE html>
<title>Index of """ & url & """</title>
<h1>Index of """ & url & """</h1>""")
  var ispre = false
  var line = ""
  while ?stdin.readLine(line):
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
    var outs = ""
    if t == 'i':
      if not ispre:
        outs &= "<pre>"
        ispre = true
      outs &= htmlEscape(name) & '\n'
    else:
      if ispre:
        outs &= "</pre>"
        ispre = false
      let names = '[' & gopherName(t) & ']' & htmlEscape(name)
      let ourls = if not file.startsWith("URL:"):
        if file.len == 0 or file[0] != '/':
          file = '/' & file
        let pefile = file.percentEncode(PathPercentEncodeSet)
        "gopher://" & host & ":" & port & "/" & t & pefile
      else:
        file.substr("URL:".len)
      outs &= "<a href=\"" & htmlEscape(ourls) & "\">" & names & "</a><br>\n"
    ?stdout.write(outs)
  ok()

discard main()

{.pop.} # raises: []
