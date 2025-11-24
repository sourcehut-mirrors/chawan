# Minimal, TCP-only nc clone. Intended for use in shell scripts in
# simple protocols (e.g. finger, spartan, gopher).
#
# If -m is passed, it also prints local CGI connection information
# to stdout on error, and the passed message on success.
#
# This program respects ALL_PROXY (if set).

{.push raises: [].}

import std/os
import std/posix

import ../protocol/lcgi
import io/chafile
import io/poll
import utils/sandbox

proc usage() {.noreturn.} =
  let stderr = cast[ChaFile](stderr)
  discard stderr.writeLine("Usage: " & paramStr(0) & " [host] [port] [-m msg]")
  quit(1)

proc main() =
  var host = ""
  var port = ""
  var msg = ""
  var i = 1
  while i <= paramCount():
    let s = paramStr(i)
    if s == "-m":
      if i + 1 > paramCount():
        usage()
      inc i
      msg = paramStr(i)
    elif s != "" and host == "":
      host = s
    elif s != "" and port == "":
      port = s
    else:
      usage()
    inc i
  var os = newPosixStream(STDOUT_FILENO)
  let ips = newPosixStream(STDIN_FILENO)
  let res = connectSocket(host, port)
  if res.isErr:
    if msg != "":
      cgiDie(res.error.code, res.error.s)
    else:
      quit(1)
  let ps = res.get
  if msg != "":
    if os.writeLoop(msg).isErr:
      quit(1)
  enterNetworkSandbox()
  var pollData = PollData()
  pollData.register(ips.fd, POLLIN)
  pollData.register(ps.fd, POLLIN)
  var buf {.noinit.}: array[4096, char]
  i = 0 # unregister counter
  while i < 2:
    pollData.poll(-1)
    for event in pollData.events:
      assert (event.revents and POLLOUT) == 0
      if (event.revents and POLLIN) != 0:
        if event.fd == ips.fd:
          let n = ips.read(buf)
          if n <= 0:
            pollData.unregister(ips.fd)
            inc i
            continue
          if ps.writeLoop(buf.toOpenArray(0, n - 1)).isErr:
            quit(1)
        else:
          assert event.fd == ps.fd
          let n = ps.read(buf)
          if n <= 0:
            pollData.unregister(ps.fd)
            inc i
            continue
          if os.writeLoop(buf.toOpenArray(0, n - 1)).isErr:
            quit(1)
      if (event.revents and (POLLERR or POLLHUP)) != 0:
        pollData.unregister(event.fd)
        inc i
  discard shutdown(SocketHandle(ps.fd), SHUT_RDWR)
  ps.sclose()

main()

{.pop.} # raises: []
