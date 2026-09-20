import std/unittest

import utils/chaos

proc testPath() =
  check "a" / "b" == "a/b"
  check "a" / "../b" == "b"
  check "" / "b" == "b"
  check "a" / "" == "a/"
  check "" / "../b" == "../b"
  check "/tmp" / "cha-tmp-test" == "/tmp/cha-tmp-test"

proc run() =
  testPath()

run()
