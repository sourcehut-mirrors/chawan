# Percent-encode or decode input received on stdin with a specified
# percent-encoding set.
#
# Note: the last newline is trimmed from the input. Add another one if
# you wish to keep it.

{.push raises: [].}

import io/chafile
import utils/myposix
import utils/opt
import utils/twtstr

proc usage() {.noreturn.} =
  let stderr = cast[ChaFile](stderr)
  discard stderr.write("""
Usage: urlenc [-s] [set]
The input to be decoded is read from stdin, with the last line feed removed.
[set] decides which characters are encoded, and defaults to "form".
    control: controls, non-ascii
    fragment: control + space, ", <, >, `
    query: control + space, ", <, >, #
    special-query: query + '
    path: query + ?, `, {, }
    userinfo: path + /, :, ;, =, @, [, \, ], ^, |
    component: userinfo + $, &, plus, comma
    form: component + !, ', (, ), ~
[-s] encodes spaces to plus signs (as application/x-www-form-urlencoded).
""")
  quit(1)

proc main(): Opt[void] =
  let isdec = basename(getArgvCString(0)) == "urldec"
  let npars = getArgvCount()
  if not isdec and npars > 3:
    usage()
  var set = ApplicationXWWWFormUrlEncodedSet
  var spacesAsPlus = false
  if not isdec:
    for i in 1 ..< npars:
      let arg = getArgvCString(i)
      if arg == "control":
        set = ControlPercentEncodeSet
      elif arg == "fragment":
        set = FragmentPercentEncodeSet
      elif arg == "query":
        set = QueryPercentEncodeSet
      elif arg == "special-query":
        set = SpecialQueryPercentEncodeSet
      elif arg == "path":
        set = PathPercentEncodeSet
      elif arg == "userinfo":
        set = UserInfoPercentEncodeSet
      elif arg == "component":
        set = ComponentPercentEncodeSet
      elif arg == "" or arg == "form" or
          arg == "application-x-www-form-urlencoded":
        set = ApplicationXWWWFormUrlEncodedSet
      elif arg == "-s":
        spacesAsPlus = true
      else:
        usage()
  let stdin = cast[ChaFile](stdin)
  var s: string
  ?stdin.readAll(s)
  if s.len > 0 and s[^1] == '\n':
    s.setLen(s.len - 1)
  let stdout = cast[ChaFile](stdout)
  if isdec:
    stdout.writeLine(s.percentDecode())
  else:
    stdout.writeLine(s.percentEncode(set, spacesAsPlus))

discard main()

{.pop.} # raises: []

