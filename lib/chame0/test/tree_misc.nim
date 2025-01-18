include shared/tree_common

import std/streams

proc runTest(test: TCTest, factory: MAtomFactory, scripting: bool) =
  let ss = newStringStream(test.data)
  let opts = HTML5ParserOpts[Node, MAtom](scripting: scripting)
  assert test.fragment.isNone
  let pdoc = parseHTML(ss, opts, factory = factory)
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

proc runTests(filename: string) =
  let factory = newMAtomFactory()
  let tests = parseTests(readFile(rootpath & filename), factory)
  for test in tests:
    case test.script
    of SCRIPT_OFF:
      test.runTest(factory, scripting = false)
    of SCRIPT_ON:
      test.runTest(factory, scripting = true)
    of SCRIPT_BOTH:
      test.runTest(factory, scripting = false)
      test.runTest(factory, scripting = true)

test "gtrsim.dat":
  runTests("gtrsim.dat")
