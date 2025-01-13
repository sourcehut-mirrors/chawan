import std/asyncdispatch
import std/asynchttpserver
import std/httpcore
import std/os
import std/posix
import std/strutils

import utils/twtstr

proc cb(req: Request) {.async.} =
  if req.url.path == "/stop":
    await req.respond(Http200, "")
    quit(0)
  var res = ""
  var headers: seq[(string, string)] = @[]
  if req.url.path == "/headers":
    for k, v in req.headers:
      res &= k & ": " & v & '\n'
  else:
    try:
      res = readFile(req.url.path.after('/'))
    except IOError:
      await req.respond(Http404, "Not found")
      return
    if req.url.path.endsWith(".http"):
      var i = 0
      for line in res.split('\n'):
        i += line.len + 1
        if line == "":
          break
        let n = line.find(':')
        if n >= 0:
          headers.add((line.substr(0, n - 1), line.substr(n + 1)))
      res = res.substr(i)
    else:
      res = readFile(req.url.path.after('/'))
  #echo (req.reqMethod, req.url.path, req.headers)
  await req.respond(Http200, res, headers.newHttpHeaders())

proc runServer(server: AsyncHttpServer) {.async.} =
  while true:
    if server.shouldAcceptRequest():
      await server.acceptRequest(cb)
    else:
      # too many concurrent connections, `maxFDs` exceeded
      # wait 500ms for FDs to be closed
      await sleepAsync(500)

proc main() {.async.} =
  var server = newAsyncHttpServer()
  if paramCount() >= 1 and paramStr(1) == "-x":
    server.listen(Port(8000))
    await server.runServer()
    quit(0)
  server.listen(Port(0))
  let port = server.getPort()
  case fork()
  of 0:
    let cmd = getAppFilename().untilLast('/') & "/run.sh " & $uint16(port)
    discard execl("/bin/sh", "sh", "-c", cstring(cmd), nil)
    quit(1)
  of -1:
    stderr.write("Failed to start run.sh")
    quit(1)
  else:
    await server.runServer()
    var x: cint
    quit(WEXITSTATUS(wait(addr x)))

waitFor main()
