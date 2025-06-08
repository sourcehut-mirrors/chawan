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
# is used in the HTTP, FTP, SFTP, Gemini handlers, and all image
# manipulation processes (codecs and resize).
#
# On FreeBSD, we enter capability mode with cap_enter.  Since buffers
# do not do anything that Capsicum does not allow (they receive their
# UNIX sockets from the fork server), this is enough to lock down the
# process.
#
# On OpenBSD, we pledge the minimum amount of promises we need, and
# do not unveil anything. It seems to be roughly equivalent to the
# security we get with FreeBSD Capsicum.
#
# On Linux, we use chaseccomp which is a very dumb BPF assembler for
# seccomp-bpf.  It only allows syscalls deemed to be safe; notably
# however, it also includes clone(2), which I'm not sure about...
#
# We do not have syscall sandboxing on other systems (yet).

{.push raises: [].}

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

  proc enterBufferSandbox*() =
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

  proc enterBufferSandbox*() =
    # take whatever we need to
    # * fork
    # * send/receive fds from/to the loader (and sometimes the pager)
    doAssert pledge("stdio sendfd recvfd proc", nil) == 0

  proc enterNetworkSandbox*() =
    # we don't need much to write out data from sockets to stdout.
    doAssert pledge("stdio", nil) == 0

elif SandboxMode == stSeccomp:
  proc sourceParent(): string =
    var s = currentSourcePath()
    while s.len > 0 and s[^1] != '/':
      s.setLen(s.len - 1)
    move(s)
  {.passl: sourceParent() & "../../lib/chaseccomp/chaseccomp.o".}

  proc cha_enter_buffer_sandbox(): cint {.importc, cdecl.}
  proc cha_enter_network_sandbox(): cint {.importc, cdecl.}

  proc enterBufferSandbox*() =
    doAssert cha_enter_buffer_sandbox() == 1

  proc enterNetworkSandbox*() =
    doAssert cha_enter_network_sandbox() == 1

else:
  {.warning: "Building without syscall sandboxing!".}
  proc enterBufferSandbox*() =
    discard

  proc enterNetworkSandbox*() =
    discard

{.pop.} # raises: []
