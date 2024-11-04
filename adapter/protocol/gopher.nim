import std/os
import std/posix
import std/strutils

import ../gophertypes
import lcgi

proc loadSearch(os: PosixStream; t: GopherType; surl: string) =
  os.sendDataLoop("""
Content-Type: text/html

<!DOCTYPE HTML>
<HTML>
<HEAD>
<BASE HREF="""" & surl & """">
</HEAD>
<BODY>
<H1>Search """ & htmlEscape(surl) & """</H1>
<FORM>
<INPUT TYPE=SEARCH NAME="NAME">
</FORM>
</BODY>
</HTML>
""")

proc loadRegular(os: PosixStream; t: GopherType; path: var string;
    host, port, query: string) =
  let ps = os.connectSocket(host, port)
  enterNetworkSandbox()
  if query != "":
    path &= '\t'
    path &= query
  path &= '\n'
  ps.sendDataLoop(percentDecode(path))
  let s = case t
  of gtDirectory, gtSearch: "Content-Type: text/gopher\n"
  of gtHTML: "Content-Type: text/html\n"
  of gtGif: "Content-Type: image/gif\n"
  of gtPng: "Content-Type: image/png\n"
  of gtTextFile, gtError: "Content-Type: text/plain\n"
  else: ""
  os.sendDataLoop(s & '\n')
  var buffer: array[4096, uint8]
  while true:
    let n = ps.recvData(buffer)
    if n == 0:
      break
    os.sendDataLoop(addr buffer[0], n)
  ps.sclose()

proc main() =
  let os = newPosixStream(STDOUT_FILENO)
  if getEnv("REQUEST_METHOD") != "GET":
    os.die("InvalidMethod")
  let scheme = getEnv("MAPPED_URI_SCHEME")
  let host = getEnv("MAPPED_URI_HOST")
  let port = getEnvEmpty("MAPPED_URI_PORT", "70")
  let query = getEnv("MAPPED_URI_QUERY").after('=')
  var path = getEnv("MAPPED_URI_PATH")
  var i = 0
  while i < path.len and path[i] == '/':
    inc i
  var t = gtDirectory
  if i < path.len:
    t = gopherType(path[i])
    if t != gtUnknown:
      path.delete(0 .. i)
    else:
      t = gtDirectory
  if t == gtSearch and query == "":
    os.loadSearch(t, scheme & "://" & host & ":" & port & '/')
  else:
    os.loadRegular(t, path, host, port, query)

main()
