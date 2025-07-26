# This binary unifies all modules that must be linked to OpenSSL, so
# that it doesn't bloat the distribution's size in statically linked
# builds.

{.push raises: [].}

import utils/twtstr

import gemini
import http
import sftp

proc main() =
  let scheme = getEnvEmpty("MAPPED_URI_SCHEME")
  if scheme == "gemini":
    gemini.main()
  elif scheme == "sftp":
    sftp.main()
  else:
    http.main()

main()

{.pop.} # raises: []
