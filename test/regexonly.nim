import std/unittest

import monoucha/jsregex
import monoucha/optshim

test "regex only":
  let re = compileRegex(".*").get
  check re.match("whatever")

test r"\b":
  let re = compileRegex"\bth\b".get
  check not re.match("Weather")
