import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsref
import monoucha/quickjs

type
  Test = JSRef[TestObj]

  TestObj = object
    other: Test

var count = 0

jsClassDef(Test):
  proc finalize(rt: JSRuntime; this: Test) {.jsfin.} =
    inc count

type TestSeq = object
  s: seq[Test]

proc `[]`(t: TestSeq; i: int): Test =
  t.s[i]

proc testHooks() =
  block:
    let test = jsNew TestObj()
    let other = jsNew TestObj()
    test.other = other
    other.other = test
  block:
    let test = jsNew TestObj()
    var other: array[1, Test]
    other[0] = jsNew TestObj()
    test.other = other[0]
    other[0].other = test
  block:
    let test = jsNew TestObj()
    var other = TestSeq(s: newSeq[Test](1))
    other.s[0] = jsNew TestObj()
    test.other = other[0].other

proc main() =
  let rt = newGlobalJSRuntime()
  let ctx = newJSContext(rt)
  assert ctx.registerClass(TestDef) == fjOk
  testHooks()
  ctx.free()
  rt.free()
  assert count == 6, $count

main()
