# This binary unifies all modules that must be linked to OpenSSL, so
# that it doesn't bloat the distribution's size in statically linked
# builds.

{.push raises: [].}

import std/os
import utils/twtstr

import gemini
import http
import lcgi
import sftp

proc main() =
  var scheme = paramStr(0)
  let i = scheme.rfind('/')
  if i >= 0:
    scheme.delete(0..i)
  if scheme == "gemini":
    gemini.main()
  elif scheme == "sftp":
    sftp.main()
  else:
    http.main(scheme)

main()

{.pop.} # raises: []
