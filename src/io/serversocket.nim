import std/os
import std/posix

import io/dynstream

type ServerSocket* = ref object
  fd*: cint
  path*: string
  dfd: int #TODO should be cint

# The way stdlib does bindUnix is utterly broken at least on FreeBSD.
# It seems that just writing it in C is the easiest solution.
{.compile: "bind_unix.c".}
proc bind_unix_from_c(fd: cint; path: cstring; pathlen: cint): cint
  {.importc.}

when defined(freebsd):
  # capsicum stuff
  proc unlinkat(dfd: cint; path: cstring; flag: cint): cint
    {.importc, header: "<unistd.h>".}
  proc bindat_unix_from_c(dfd, sock: cint; path: cstring; pathlen: cint): cint
    {.importc.}

proc setBlocking*(ssock: ServerSocket; blocking: bool) =
  let ofl = fcntl(ssock.fd, F_GETFL, 0)
  if blocking:
    discard fcntl(ssock.fd, F_SETFL, ofl and not O_NONBLOCK)
  else:
    discard fcntl(ssock.fd, F_SETFL, ofl and O_NONBLOCK)

proc newServerSocket*(fd: cint; sockDir: string; pid, sockDirFd: int):
    ServerSocket =
  let path = getSocketPath(sockDir, pid)
  return ServerSocket(fd: cint(fd), path: path, dfd: sockDirFd)

proc newServerSocket*(sockDir: string; sockDirFd, pid: int): ServerSocket =
  let fd = cint(socket(AF_UNIX, SOCK_STREAM, IPPROTO_IP))
  let path = getSocketPath(sockDir, pid)
  let ssock = ServerSocket(fd: fd, path: path, dfd: sockDirFd)
  if sockDirFd == -1:
    discard tryRemoveFile(path)
    if bind_unix_from_c(fd, cstring(path), cint(path.len)) != 0:
      raiseOSError(osLastError())
  else:
    when defined(freebsd):
      let name = getSocketName(pid)
      discard unlinkat(cint(sockDirFd), cstring(name), 0)
      if bindat_unix_from_c(cint(sockDirFd), fd, cstring(name),
          cint(name.len)) != 0:
        raiseOSError(osLastError())
    else:
      # shouldn't have sockDirFd on other architectures
      doAssert false
  if listen(SocketHandle(fd), 128) != 0:
    raiseOSError(osLastError())
  return ssock

proc close*(ssock: ServerSocket; unlink = true) =
  discard close(ssock.fd)
  if unlink:
    when defined(freebsd):
      if ssock.dfd != -1:
        discard unlinkat(cint(ssock.dfd), cstring(ssock.path), 0)
        return
    discard tryRemoveFile(ssock.path)

proc acceptSocketStream*(ssock: ServerSocket; blocking = true): SocketStream =
  let fd = cint(accept(SocketHandle(ssock.fd), nil, nil))
  if fd == -1:
    return nil
  let ss = SocketStream(fd: fd, blocking: false)
  if not blocking:
    ss.setBlocking(false)
  return ss
