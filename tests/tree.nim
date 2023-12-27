include shared/tree_common

import std/streams

proc runTest(test: TCTest, factory: MAtomFactory, scripting: bool) =
  let ss = newStringStream(test.data)
  let opts = HTML5ParserOpts[Node, MAtom](
    scripting: scripting
  )
  let pdoc = if test.fragment.isNone:
    parseHTML(ss, opts, factory)
  else:
    let ctx = Element()
    ctx[] = test.fragment.get.ctx[]
    let childList = parseHTMLFragment(ss, ctx, opts, factory)
    for child in childList:
      if ctx.preInsertionValidity(child, nil):
        ctx.childList.add(child)
    Document(nodeType: DOCUMENT_NODE, childList: ctx.childList)
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

const rootpath = "tests/html5lib-tests/tree-construction/"

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

test "tests1.dat":
  runTests("tests1.dat")

test "tests2.dat":
  runTests("tests2.dat")

test "tests3.dat":
  runTests("tests3.dat")

test "tests4.dat":
  runTests("tests4.dat")

test "tests5.dat":
  runTests("tests5.dat")

test "tests6.dat":
  runTests("tests6.dat")

test "tests7.dat":
  runTests("tests7.dat")

test "tests8.dat":
  runTests("tests8.dat")

test "tests9.dat":
  runTests("tests9.dat")
