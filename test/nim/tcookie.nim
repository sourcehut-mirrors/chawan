import std/unittest

import config/cookie
import utils/opt

proc main() =
  check parseCookieDate("Mon 0 Jan 1999 20:30:00 GMT").isErr
  check parseCookieDate("Mon 31 Feb 1999 20:30:00 GMT").isErr
  check parseCookieDate("Mon 20 Feb 1999 20:30:00 GMT").get == 919542600

main()
