# Security model with sandboxing:
#
# Buffer processes are the most security-sensitive, since they parse
# various resources retrieved from the network (CSS, HTML) and sometimes
# even execute untrusted code (JS, with an engine written in C). So the
# main goal is to give buffers as few permissions as possible.
#
# Aside from sandboxing in buffer processes, we also have a more
# restrictive "network" sandbox that is intended for CGI processes that
# just read/write from/to the network and stdin/stdout. At the moment this
# is used in the HTTP process and all image manipulation processes (codecs,
# resize).
#
# On FreeBSD, we create a file descriptor to the directory sockets
# reside in, and then use that for manipulating our sockets.
#
# Capsicum does not enable more fine-grained capability control, but
# in practice the things it does enable should not be enough to harm the
# user's system.
#
# On OpenBSD, we pledge the minimum amount of promises we need, and
# do not unveil anything. It seems to be roughly equivalent to the
# security we get with FreeBSD Capsicum, except connect(3) can connect
# to any UNIX domain socket on the file system.
#
# On Linux, we use chaseccomp which is a very dumb BPF assembler for
# seccomp-bpf. Like the OpenBSD filter, this does not prevent a
# connect(3) to UNIX domain sockets that we do not have access to.
#
# We do not have syscall sandboxing on other systems (yet).

const disableSandbox {.booldefine.} = false

type SandboxType* = enum
  stNone = "no sandbox"
  stCapsicum = "capsicum"
  stPledge = "pledge"
  stSeccomp = "seccomp-bpf"

const SandboxMode* = when disableSandbox:
  stNone
elif defined(freebsd):
  stCapsicum
elif defined(openbsd):
  stPledge
elif defined(linux):
  stSeccomp
else:
  stNone

when SandboxMode == stCapsicum:
  proc cap_enter(): cint {.importc, cdecl, header: "<sys/capsicum.h>".}

  proc enterBufferSandbox*(sockPath: string) =
    # per man:cap_enter(2), it may return ENOSYS if the kernel was compiled
    # without CAPABILITY_MODE. So it seems better not to panic in this case.
    # (But TODO: when we get enough sandboxing coverage it should print a
    # warning or something.)
    discard cap_enter()

  proc enterNetworkSandbox*() =
    # no difference between buffer; Capsicum is quite straightforward
    # to use in this regard.
    discard cap_enter()

elif SandboxMode == stPledge:
  proc pledge(promises, execpromises: cstring): cint {.importc, cdecl,
    header: "<unistd.h>".}

  proc enterBufferSandbox*(sockPath: string) =
    # take whatever we need to
    # * fork
    # * connect to UNIX domain sockets
    # * take FDs from the main process
    doAssert pledge("unix stdio sendfd recvfd proc", nil) == 0

  proc enterNetworkSandbox*() =
    # we don't need much to write out data from sockets to stdout.
    doAssert pledge("stdio", nil) == 0

elif SandboxMode == stSeccomp:
  proc sourceParent(): string =
    var s = currentSourcePath()
    while s.len > 0 and s[^1] != '/':
      s.setLen(s.len - 1)
    return s
  {.passl: sourceParent() & "../../lib/chaseccomp/chaseccomp.o".}

  import std/posix

  proc cha_enter_buffer_sandbox(): cint {.importc, cdecl.}
  proc cha_enter_network_sandbox(): cint {.importc, cdecl.}

  proc enterBufferSandbox*(sockPath: string) =
    doAssert cha_enter_buffer_sandbox() == 1

  proc enterNetworkSandbox*() =
    doAssert cha_enter_network_sandbox() == 1

else:
  {.warning: "Building without syscall sandboxing!".}
  proc enterBufferSandbox*(sockPath: string) =
    discard

  proc enterNetworkSandbox*() =
    discard
