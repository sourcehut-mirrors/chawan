# Minimal, TCP-only nc clone. Intended for use in shell scripts in
# simple protocols (e.g. finger, spartan).
#
# This program respects ALL_PROXY (if set).
import std/os
import std/posix

import ../protocol/lcgi
import io/poll

proc usage() {.noreturn.} =
  stderr.write("Usage: " & paramStr(0) & " [host] [port]\n")
  quit(1)

proc main() =
  if paramCount() != 2:
    usage()
  let os = newPosixStream(STDOUT_FILENO)
  let ips = newPosixStream(STDIN_FILENO)
  let ps = os.connectSocket(paramStr(1), paramStr(2))
  var pollData = PollData()
  pollData.register(STDIN_FILENO, POLLIN)
  pollData.register(ps.fd, POLLIN)
  var buf {.noinit.}: array[4096, uint8]
  var i = 0 # unregister counter
  while i < 2:
    pollData.poll(-1)
    for event in pollData.events:
      assert (event.revents and POLLOUT) == 0
      if (event.revents and POLLIN) != 0:
        if event.fd == STDIN_FILENO:
          let n = ips.recvData(buf)
          if n == 0:
            pollData.unregister(ips.fd)
            inc i
            continue
          ps.sendDataLoop(buf.toOpenArray(0, n - 1))
        else:
          assert event.fd == ps.fd
          let n = ps.recvData(buf)
          if n == 0:
            pollData.unregister(ips.fd)
            inc i
            continue
          os.sendDataLoop(buf.toOpenArray(0, n - 1))
      if (event.revents and POLLERR) != 0 or (event.revents and POLLHUP) != 0:
        pollData.unregister(event.fd)
        inc i

main()
