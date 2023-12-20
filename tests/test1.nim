# "simple" test to check if it compiles
# (actually, I just copy-pasted a throwaway test project here)

import unittest
import tables
import strutils
import streams

import chame/tags
import chame/minidom

func escapeText(s: string, attribute_mode = false): string =
  var nbsp_mode = false
  var nbsp_prev: char
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

proc tostr(ftype: enum): string =
  return ($ftype).split('_')[1..^1].join("-").toLowerAscii()

func `$`*(node: Node): string =
  case node.nodeType
  of ELEMENT_NODE:
    let element = Element(node)
    if element.tagType != TAG_UNKNOWN:
      result = "<" & $element.tagType.tostr()
    else:
      result = "<" & element.localName
    for k, v in element.attrs:
      result &= ' ' & k & "=\"" & v.escapeText(true) & "\""
    result &= ">"
    for node in element.childList:
      result &= $node
    if element.tagType != TAG_UNKNOWN:
      result &= "</" & $element.tagType.tostr() & ">"
    else:
      result &= "</" & $element.localName & ">"
  of TEXT_NODE:
    let text = Text(node)
    result = text.data.escapeText()
  of COMMENT_NODE:
    result = "<!-- " & Comment(node).data & "-->"
  of PROCESSING_INSTRUCTION_NODE:
    result = "" #TODO
  of DOCUMENT_TYPE_NODE:
    result = "<!DOCTYPE" & ' ' & DocumentType(node).name & ">"
  else:
    result = "Node of " & $node.nodeType

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
