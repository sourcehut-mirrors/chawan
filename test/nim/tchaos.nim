import std/unittest

import utils/chaos
import utils/cowstr

proc testPath() =
  check str("a") / str("b") == str("a/b")
  check str("a") / str("../b") == str("b")
  check str("") / str("b") == str("b")
  check str("a") / str("") == str("a/")
  check str("") / str("../b") == str("../b")
  check str("/tmp") / str("cha-tmp-test") == str("/tmp/cha-tmp-test")

proc run() =
  testPath()

run()
