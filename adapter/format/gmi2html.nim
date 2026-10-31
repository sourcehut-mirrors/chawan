{.push raises: [].}

import io/chafile
import utils/opt
import utils/twtstr

proc parse(): Opt[void] =
  # We use `display: block' for anchors because they are supposed to be
  # presented on separate lines per standard.
  # We use `white-space: pre-line' on the entire body so that we do not have
  # to emit a <br> character for each paragraph. ("Why not p?" Because gemini
  # does not allow collapsing newlines, so we would have to use <br> or empty
  # <p> tags for them. Neither make a lot more sense semantically than the
  # simplest and most efficient solution, which is just using newlines.)
  ?chaStdout.write("<!DOCTYPE html>")
  var inpre = false
  var inul = false
  var line = ""
  while ?chaStdin.readLine(line):
    if inpre and not line.startsWith("```"):
      ?chaStdout.write(line.htmlEscape() & '\n')
      continue
    if inul and not line.startsWith("* "):
      ?chaStdout.write("</ul>")
      inul = false
    if line.len == 0:
      ?chaStdout.write("\n")
      continue
    if line.startsWith("=>"): # link
      let i = line.skipBlanks(2)
      let url = line.until(AsciiWhitespace, i)
      let text = if i + url.len < line.len:
        let j = line.skipBlanks(i + url.len)
        line.toOpenArray(j, line.high).htmlEscape()
      else:
        url.htmlEscape()
      ?chaStdout.write("<a href='" & url.htmlEscape() & "'>" & text & "</a>")
    elif line.startsWith("```"): # preformatting toggle
      inpre = not inpre
      let title = line.toOpenArray(3, line.high).htmlEscape()
      if inpre:
        ?chaStdout.write("<pre title='" & title & "'>")
      else:
        ?chaStdout.write("</pre>")
    elif line.startsWith("#"): # heading line
      var i = 1
      while i < line.len and i < 3 and line[i] == '#':
        inc i
      let h = "h" & $i
      i = line.skipBlanks(i) # ignore whitespace after #
      ?chaStdout.write("<" & h & ">" &
        line.toOpenArray(i, line.high).htmlEscape() & "</" & h & ">")
    elif line.startsWith("* "): # unordered list item
      if not inul:
        inul = true
        ?chaStdout.write("<ul>")
      ?chaStdout.write("<li>" & line.toOpenArray(2, line.high).htmlEscape() &
        "</li>")
    elif line.startsWith(">"): # quote
      ?chaStdout.write("<blockquote>")
      ?chaStdout.write(line.toOpenArray(1, line.high).htmlEscape())
      ?chaStdout.write("</blockquote>")
    else:
      ?chaStdout.write(line.htmlEscape() & '\n')
  ok()

proc main*() =
  discard parse()

{.pop.} # raises: []
