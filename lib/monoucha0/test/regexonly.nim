import std/unittest

import monoucha/jsregex

test "regex only":
  var re: Regex
  doAssert compileRegex(".*", {}, re)
  check re.match("whatever")

test r"\b":
  var re: Regex
  doAssert compileRegex("\bth\b", {}, re)
  check not re.match("Weather")
