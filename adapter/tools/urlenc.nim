# Percent-encode or decode input received on stdin with a specified
# percent-encoding set.
#
# Note: the last newline is trimmed from the input. Add another one if
# you wish to keep it.

{.push raises: [].}

import std/os

import io/chafile
import io/dynstream
import types/opt
import utils/twtstr

proc usage() {.noreturn.} =
  stderr.fwrite("""
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
  let isdec = paramStr(0).afterLast('/') == "urldec"
  let npars = paramCount()
  if not isdec and npars > 2:
    usage()
  var set = ApplicationXWWWFormUrlEncodedSet
  var spacesAsPlus = false
  if not isdec:
    for i in 1 .. npars:
      case paramStr(i)
      of "control": set = ControlPercentEncodeSet
      of "fragment": set = FragmentPercentEncodeSet
      of "query": set = QueryPercentEncodeSet
      of "special-query": set = SpecialQueryPercentEncodeSet
      of "path": set = PathPercentEncodeSet
      of "userinfo": set = UserInfoPercentEncodeSet
      of "component": set = ComponentPercentEncodeSet
      of "", "form", "application-x-www-form-urlencoded":
        set = ApplicationXWWWFormUrlEncodedSet
      of "-s": spacesAsPlus = true
      else: usage()
  let stdin = cast[ChaFile](stdin)
  var s: string
  ?stdin.readAll(s)
  if s.len > 0 and s[^1] == '\n':
    s.setLen(s.len - 1)
  let stdout = cast[ChaFile](stdout)
  if isdec:
    ?stdout.writeLine(s.percentDecode())
  else:
    ?stdout.writeLine(s.percentEncode(set, spacesAsPlus))
  ok()

discard main()

{.pop.} # raises: []

