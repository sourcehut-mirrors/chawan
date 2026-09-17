# This binary unifies all modules that must be linked to OpenSSL, so
# that it doesn't bloat the distribution's size in statically linked
# builds.

{.push raises: [].}

import gemini
import http
import lcgi
import sftp

proc main() =
  let scheme = basename(getArgvCString(0))
  if scheme == "gemini":
    gemini.main()
  elif scheme == "sftp":
    sftp.main()
  else:
    http.main(scheme)

main()

{.pop.} # raises: []
