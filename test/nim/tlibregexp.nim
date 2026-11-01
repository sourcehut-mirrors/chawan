import std/unittest

import utils/lrewrap
import utils/opt

proc match(re, str: string): bool =
  let re = compileRegex(re, {}).get
  re.match(str)

proc testRegexOnly() =
  check match(".*", "whatever")
  check match(".*", "")

proc testWordBoundaries() =
  check not "\bth\b".match("Weather")

proc main() =
  testRegexOnly()
  testWordBoundaries()

main()
