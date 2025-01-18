include shared/tree_common

import std/streams

proc runTest(test: TCTest, factory: MAtomFactory, scripting, print: bool) =
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
    Document(childList: ctx.childList)
  if print:
    var ins = ""
    for x in test.document.childList:
      ins &= $x & '\n'
    var ps = ""
    for x in pdoc.childList:
      ps &= $x & '\n'
    echo "data ", test.data
    echo "indoc ", $ins
    echo "psdoc ", $ps
  checkTest(test.document, pdoc)

const rootpath = "test/html5lib-tests/tree-construction/"

proc runTests(filename: string, print = false) =
  let factory = newMAtomFactory()
  let tests = parseTests(readFile(rootpath & filename), factory)
  for test in tests:
    case test.script
    of SCRIPT_OFF:
      test.runTest(factory, scripting = false, print = print)
    of SCRIPT_ON:
      test.runTest(factory, scripting = true, print = print)
    of SCRIPT_BOTH:
      test.runTest(factory, scripting = false, print = print)
      test.runTest(factory, scripting = true, print = print)

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

test "tests10.dat":
  runTests("tests10.dat")

test "tests11.dat":
  runTests("tests11.dat")

test "tests12.dat":
  runTests("tests12.dat")

# no tests13 in html5lib-tests :)

test "tests14.dat":
  runTests("tests14.dat")

test "tests15.dat":
  runTests("tests15.dat")

test "tests16.dat":
  runTests("tests16.dat")

test "tests17.dat":
  runTests("tests17.dat")

test "tests18.dat":
  runTests("tests18.dat")

test "tests19.dat":
  runTests("tests19.dat")

test "tests20.dat":
  runTests("tests20.dat")

test "tests21.dat":
  runTests("tests21.dat")

test "tests22.dat":
  runTests("tests22.dat")

test "tests23.dat":
  runTests("tests23.dat")

test "tests24.dat":
  runTests("tests24.dat")

test "tests25.dat":
  runTests("tests25.dat")

test "tests26.dat":
  runTests("tests26.dat")

test "adoption01.dat":
  runTests("adoption01.dat")

test "adoption02.dat":
  runTests("adoption02.dat")

test "blocks.dat":
  runTests("blocks.dat")

test "comments01.dat":
  runTests("comments01.dat")

test "doctype01.dat":
  runTests("doctype01.dat")

test "domjs-unsafe.dat":
  runTests("domjs-unsafe.dat")

test "entities01.dat":
  runTests("entities01.dat")

test "entities02.dat":
  runTests("entities02.dat")

test "foreign-fragment.dat":
  runTests("foreign-fragment.dat")

test "html5test-com.dat":
  runTests("html5test-com.dat")

test "inbody01.dat":
  runTests("inbody01.dat")

test "isindex.dat":
  runTests("isindex.dat")

test "main-element.dat":
  runTests("main-element.dat")

test "math.dat":
  runTests("math.dat")

test "menuitem-element.dat":
  runTests("menuitem-element.dat")

test "namespace-sensitivity.dat":
  runTests("namespace-sensitivity.dat")

test "noscript01.dat":
  runTests("noscript01.dat")

test "pending-spec-changes.dat":
  runTests("pending-spec-changes.dat")

test "pending-spec-changes-plain-text-unsafe.dat":
  runTests("pending-spec-changes-plain-text-unsafe.dat")

test "plain-text-unsafe.dat":
  runTests("plain-text-unsafe.dat")

test "quirks01.dat":
  runTests("quirks01.dat")

test "ruby.dat":
  runTests("ruby.dat")

test "scriptdata01.dat":
  runTests("scriptdata01.dat")

test "search-element.dat":
  runTests("search-element.dat")

test "svg.dat":
  runTests("svg.dat")

test "tables01.dat":
  runTests("tables01.dat")

test "template.dat":
  runTests("template.dat")

test "tests_innerHTML_1.dat":
  runTests("tests_innerHTML_1.dat")

test "tricky01.dat":
  runTests("tricky01.dat")

test "webkit01.dat":
  runTests("webkit01.dat")

test "webkit02.dat":
  runTests("webkit02.dat")
