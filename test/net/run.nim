import std/asyncdispatch
import std/asynchttpserver
import std/httpcore
import std/os
import std/strutils

import io/chafile
import types/opt
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
    if chafile.readFile(req.url.path.after('/'), res).isErr:
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

proc main() =
  let server = newAsyncHttpServer()
  if paramCount() >= 1 and paramStr(1) == "-a":
    server.listen(Port(0), "localhost")
  else:
    server.listen(Port(8000), "localhost")
  echo $uint16(server.getPort())
  waitFor server.runServer()

main()
