import std/unittest

import utils/cowstr
import utils/lrewrap
import utils/opt

proc match(re, str: Str): bool =
  let re = compileRegex(re, {}).get
  re.match(str.toOpenArray())

proc testRegexOnly() =
  check match(str(".*"), str("whatever"))
  check match(str(".*"), str(""))

proc testWordBoundaries() =
  check not str("\bth\b").match(str("Weather"))

proc main() =
  testRegexOnly()
  testWordBoundaries()

main()
