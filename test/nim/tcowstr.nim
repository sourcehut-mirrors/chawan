import std/unittest

import utils/cowstr
import utils/twtstr

proc use(s: Str) =
  discard

proc refs() =
  var buf = initGrowbufOfCap(16)
  buf &= "test"
  buf &= '1'
  let p = cast[pointer](buf.p)
  block:
    var s = buf.toStr()
    check p == cast[pointer](s.toCStringConst())
    s &= "2" # CoW optimization makes it so this doesn't realloc
    check p == cast[pointer](s.toCStringConst())
    var s2 = s
    use(s2)
    s &= "3" # CoW flag is gone after dup
    check p != cast[pointer](s.toCStringConst())
    check s == "test123"
    check s2 == "test12"

proc testDelete() =
  block: # literal
    var x = str("test")
    x.delete(1..4)
    check x == "t"
  block: # heap
    var x = initGrowbuf()
    x &= str("test")
    x.delete(1..4)
    check x == "t"

proc testInsert() =
  block: # literal
    var x = str("test")
    x.insert(str("wo t"), 1)
    check x == "two test"
  block: # heap
    var x = initGrowbuf()
    x &= str("test")
    x.insert(str("wo t"), 1)
    check x == "two test"
  block: # heap, end
    var x = initGrowbuf()
    x &= str("test")
    x.insert(str(" test"), x.len)
    check x == "test test"

proc testContains() =
  check str("a\tb ").containsToken("a")
  check str("a\tb ").containsToken("")
  check str("\na\tb ").containsToken("")
  check not str("ab").containsToken("")

proc testContentType() =
  var s = str("text/html; a = b")
  check s.getContentTypeAttr("a") == "b"
  s.setContentTypeAttr(str("a"), str("test"))
  check s == "text/html; a =test"
  check s.getContentTypeAttr("a") == "test"
  s.setContentTypeAttr(str("b"), str("test2"))
  check s.getContentTypeAttr("b") == "test2"
  check str("text/html; a=b; c=d").getContentTypeAttr("c") == "d"
  check str("text/html;a=b").getContentTypeAttr("a") == "b"
  check str("text/html;aa=b;a=c").getContentTypeAttr("a") == "c"
  check str("text/html;a=\"b\"").getContentTypeAttr("a") == "b"

proc testInt() =
  check uint64.high.toStr() == "18446744073709551615"
  check int64.high.toStr() == "9223372036854775807"
  check int64.low.toStr() == "-9223372036854775808"
  check uint32.high.toStr() == "4294967295"
  check int32.high.toStr() == "2147483647"
  check int32.low.toStr() == "-2147483648"

proc testCString() =
  check str("blah blah").substr(0, 3).toCString() == "blah"
  check initStr("blah blah").substr(0, 3).toCString() == "blah"

proc testUntil() =
  check str("a b c/d").untilLast('/') == "a b c"
  check str("a b c/").untilLast('/') == "a b c"
  check str("a b c").untilLast('/') == "a b c"

proc testStrip() =
  check str(" ").strip() == ""
  check str("\f\t test \r\n").strip() == "test"
  check str(" test ").strip(trailing = false) == "test "
  check str(" test ").strip(leading = false) == " test"
  check str(" \tes\t ").strip(chars = {' '}) == "\tes\t"

proc testFind() =
  check "test".find("te") == 0
  check "test".find("est") == 1
  check "test".find("st") == 2
  check "test".find("test") == 0
  check "test".find("t") == 0
  check "test".find("t", start = 5) == -1
  check "test".find("t", start = 1) == 3
  check "".find("t") == -1
  check "".find("t", start = 1) == -1
  check "".find("") == 0
  check "".find("", start = 1) == -1
  check "test".find("") == 0
  check "test".find("", start = 1) == 1

  check "test".rfind('t') == 3
  check "test".rfind('t', 0, last = 3) == 3
  check "test".rfind('t', 0, last = 2) == 0
  check "test".rfind('t', start = 1, last = 2) == -1

  check "test".startsWith("test")
  check not "test".startsWith("testt")
  check "test".startsWith("t")
  check "test".startsWith("")

proc util() =
  testContains()
  testDelete()
  testInsert()
  testContentType()
  testInt()
  testCString()
  testDelete()
  testUntil()
  testStrip()
  testFind()

proc main() =
  refs()
  util()

main()
