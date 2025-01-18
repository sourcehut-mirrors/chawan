include shared/tree_common

import std/streams
import chame/minidom_cs
import chagashi/charset

proc runTest(test: TCTest, factory: MAtomFactory, scripting: bool,
    labels: openArray[string]) =
  let ss = newStringStream(test.data)
  let opts = HTML5ParserOpts[Node, MAtom](scripting: scripting)
  assert test.fragment.isNone
  var charsets: seq[Charset] = @[]
  for s in labels:
    let cs = getCharset(s)
    assert cs != CHARSET_UNKNOWN
    charsets.add(cs)
  let pdoc = parseHTML(ss, opts, charsets, factory = factory)
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

proc runTests(filename: string, labels: openArray[string]) =
  let factory = newMAtomFactory()
  let tests = parseTests(readFile(rootpath & filename), factory)
  for test in tests:
    case test.script
    of SCRIPT_OFF:
      test.runTest(factory, scripting = false, labels)
    of SCRIPT_ON:
      test.runTest(factory, scripting = true, labels)
    of SCRIPT_BOTH:
      test.runTest(factory, scripting = false, labels)
      test.runTest(factory, scripting = true, labels)

test "sjis.dat":
  runTests("sjis.dat", ["utf8", "sjis", "latin1"])

test "latin1.dat":
  runTests("latin1.dat", ["utf8"])
