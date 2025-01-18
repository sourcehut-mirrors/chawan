# "simple" test to check if it compiles
# (actually, I just copy-pasted a throwaway test project here)

import std/unittest
import std/streams

import chame/tags
import chame/minidom

func escapeText(s: string, attribute_mode = false): string =
  result = ""
  var nbsp_mode = false
  var nbsp_prev = '\0'
  for c in s:
    if nbsp_mode:
      if c == char(0xA0):
        result &= "&nbsp;"
      else:
        result &= nbsp_prev & c
      nbsp_mode = false
    elif c == '&':
      result &= "&amp;"
    elif c == char(0xC2):
      nbsp_mode = true
      nbsp_prev = c
    elif attribute_mode and c == '"':
      result &= "&quot;"
    elif not attribute_mode and c == '<':
      result &= "&lt;"
    elif not attribute_mode and c == '>':
      result &= "&gt;"
    else:
      result &= c

func `$`*(node: Node): string =
  result = ""
  if node of Element:
    let element = Element(node)
    var x = ""
    if element.namespace == Namespace.SVG:
      x = "svg "
    elif element.namespace == Namespace.MATHML:
      x = "math "
    result = "<" & x & element.localNameStr
    for k, v in element.attrsStr:
      result &= ' ' & k & "=\"" & v.escapeText(true) & "\""
    result &= ">"
    for node in element.childList:
      result &= $node
    result &= "</" & x & element.localNameStr & ">"
  elif node of Text:
    let text = Text(node)
    result = text.data.escapeText()
  elif node of Comment:
    result = "<!-- " & Comment(node).data & "-->"
  elif node of DocumentType:
    result = "<!DOCTYPE" & ' ' & DocumentType(node).name & ">"
  elif node of Document:
    result = "Node of Document"
  else:
    assert false

# This is, in fact, standards-compliant behavior.
# Don't ask.
test "simple html serialization test":
  const inhtml = """
<!DOCTYPE html>
<html>
<head>
</head>
<body>
<main>
Hello, world!
</main>
</body>
</html>"""
  const outhtml = """
<!DOCTYPE html>
<html><head>
</head>
<body>
<main>
Hello, world!
</main>

</body></html>
"""
  let document = parseHTML(newStringStream(inhtml))
  var s = ""
  for x in document.childList:
    s &= $x & '\n'
  check s == outhtml
