# Minimal, TCP-only nc clone. Intended for use in shell scripts in
# simple protocols (e.g. finger, spartan, gopher).
#
# If -m is passed, it also prints local CGI connection information
# to stdout on error, and the passed message on success.
#
# This program respects ALL_PROXY (if set).
import std/os
import std/posix

import ../protocol/lcgi
import io/poll
import utils/sandbox

proc usage() {.noreturn.} =
  stderr.write("Usage: " & paramStr(0) & " [host] [port] [-m msg]\n")
  quit(1)

proc writeOrDie(ps: PosixStream; buffer: openArray[uint8]) =
  let os = newPosixStream(STDOUT_FILENO)
  if not os.writeDataLoop(msg):
    os.die("InternalError", "failed to write to stream")

proc writeOrDie(ps: PosixStream; buffer: openArray[char]) =
  ps.writeOrDie(buffer.toOpenArrayByte(0, buffer.high))

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
  var df = cint(-1)
  if msg == "":
    df = dup(os.fd)
    os.sclose()
  let ps = os.connectSocket(host, port)
  if df != -1:
    os = newPosixStream(df)
  if msg != "":
    os.writeOrDie(msg)
  enterNetworkSandbox()
  var pollData = PollData()
  pollData.register(ips.fd, POLLIN)
  pollData.register(ps.fd, POLLIN)
  var buf {.noinit.}: array[4096, uint8]
  i = 0 # unregister counter
  while i < 2:
    pollData.poll(-1)
    for event in pollData.events:
      assert (event.revents and POLLOUT) == 0
      if (event.revents and POLLIN) != 0:
        if event.fd == ips.fd:
          let n = ips.readData(buf)
          if n <= 0:
            pollData.unregister(ips.fd)
            inc i
            continue
          ps.writeOrDie(buf.toOpenArray(0, n - 1))
        else:
          assert event.fd == ps.fd
          let n = ps.readData(buf)
          if n <= 0:
            pollData.unregister(ips.fd)
            inc i
            continue
          os.writeOrDie(buf.toOpenArray(0, n - 1))
      if (event.revents and (POLLERR or POLLHUP)) != 0:
        pollData.unregister(event.fd)
        inc i
  discard shutdown(SocketHandle(ps.fd), SHUT_RDWR)
  ps.sclose()

main()
