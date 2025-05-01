import std/envvars

import gemini
import http
import sftp

proc main() =
  let scheme = getEnv("MAPPED_URI_SCHEME")
  if scheme == "gemini":
    gemini.main()
  elif scheme == "sftp":
    sftp.main()
  else:
    http.main()

main()
