include shared/tree_common

import chame/minidom_cs
import encoding/charset
import std/streams

proc runTest(test: TCTest; scripting: bool; labels: openArray[string]) =
  let ss = newStringStream(test.data)
  let opts = HTML5ParserOpts[Node](scripting: scripting)
  assert test.fragment.isNone
  var charsets: seq[Charset] = @[]
  for s in labels:
    let cs = getCharset(s)
    assert cs != csUnknown
    charsets.add(cs)
  let pdoc = parseHTML(ss, opts, charsets)
  #[
  var ins = ""
  for x in test.document.childList:
    ins &= $x & '\n'
  var ps = ""
  for x in pdoc.childList:
    ps &= $x & '\n'
  echo "data ", test.data
  echo "indoc ", $ins
  echo "psdoc ", $ps
  ]#
  checkTest(test.document, pdoc)

const rootpath = "test/"

proc runTests(filename: string; labels: openArray[string]) =
  let tests = parseTests(readFile(rootpath & filename))
  for test in tests:
    case test.script
    of smOff:
      test.runTest(scripting = false, labels)
    of smOn:
      test.runTest(scripting = true, labels)
    of smBoth:
      test.runTest(scripting = false, labels)
      test.runTest(scripting = true, labels)

test "sjis.dat":
  runTests("sjis.dat", ["utf8", "sjis", "latin1"])

test "latin1.dat":
  runTests("latin1.dat", ["utf8"])
