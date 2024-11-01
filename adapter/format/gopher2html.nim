# This file is dedicated to the public domain.
# Gopher directory -> HTML converter for Chawan.

import std/os
import std/strutils

include ../gophertypes

import utils/twtstr

# returns URL
proc parseParams(): string =
  result = ""
  let params = commandLineParams()
  var was_u = false
  for param in params:
    if was_u:
      result = param
      was_u = false
    elif param == "-h" or param == "--help":
      stdout.write("Usage: gopher2html [-u URL]")
      quit(0)
    elif param == "-u":
      was_u = true
    else:
      stdout.write("Usage: gopher2html [-u URL]")
      quit(1)

proc main() =
  let url = parseParams()
  let escapedURL = htmlEscape(url)
  stdout.write("""
<!DOCTYPE HTML>
<HTML>
<HEAD>
<BASE HREF="""" & url & """">
<TITLE>Index of """ & escapedURL & """</TITLE>
</HEAD>
<BODY>
<H1>Index of """ & escapedURL & """</H1>""")
  var ispre = false
  while not stdin.endOfFile:
    let line = stdin.readLine()
    if line.len == 0:
      break # invalid
    let tc = line[0]
    if tc == '.':
      break # end
    var i = 1
    template get_field(): string =
      let s = line.until('\t', i)
      i += s.len
      if i >= line.len or line[i] != '\t':
        break # invalid
      inc i
      s
    let t = gopherType(tc)
    let name = get_field()
    var file = get_field()
    let host = get_field()
    let port = line.until('\t', i) # ignore anything after port
    var outs = ""
    if t == gtInfo:
      if not ispre:
        outs &= "<PRE>"
        ispre = true
      outs &= htmlEscape(name) & '\n'
    else:
      if ispre:
        outs &= "</PRE>"
        ispre = false
      let ts = $t
      var names = ""
      if ts != "":
        names &= '[' & ts & ']'
      names &= htmlEscape(name)
      let ourls = if not file.startsWith("URL:"):
        if file.len == 0 or file[0] != '/':
          file = '/' & file
        let pefile = file.percentEncode(PathPercentEncodeSet)
        "gopher://" & host & ":" & port & "/" & tc & pefile
      else:
        file.substr("URL:".len)
      outs &= "<A HREF=\"" & htmlEscape(ourls) & "\">" & names & "</A><BR>\n"
    stdout.write(outs)

main()
