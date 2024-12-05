import std/asyncdispatch
import std/asynchttpserver
import std/os
import std/posix

import utils/twtstr

proc cb(req: Request) {.async.} =
  const headers = {"Content-type": "text/html; charset=utf-8"}
  if req.url.path == "/stop":
    await req.respond(Http200, "", headers.newHttpHeaders())
    quit(0)
  let s = readFile(req.url.path.after('/'))
  #echo (req.reqMethod, req.url.path, req.headers)
  await req.respond(Http200, s, headers.newHttpHeaders())

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
