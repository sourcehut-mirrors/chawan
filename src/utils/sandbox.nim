# Security model with sandboxing:
#
# Buffer processes are the most security-sensitive, since they parse
# various resources retrieved from the network (CSS, HTML) and sometimes
# even execute untrusted code (JS, with an engine written in C). So the
# main goal is to give buffers as few permissions as possible.
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
# security we get with FreeBSD Capsicum.
#
# On Linux, we use libseccomp so that I don't have to manually write
# BPF filters.
# Sandboxing on Linux is at the moment slightly less safe than on the
# two BSDs, because a rogue buffer could in theory connect to whatever
# open UNIX domain socket on the system that the user has access to.
#TODO look into integrating Landlock to fix this.
#
# We do not have OS-level sandboxing on other systems (yet).
#
# Aside from sandboxing in buffer processes, we also have a more
# restrictive "network" sandbox that is intended for CGI processes that
# just read/write from/to the network and stdin/stdout. At the moment this
# is only used in the HTTP process.
#TODO add it to more CGI scripts

const disableSandbox {.booldefine.} = false

type SandboxType* = enum
  stNone = "no sandbox"
  stCapsicum = "capsicum"
  stPledge = "pledge"
  stLibSeccomp = "libseccomp"

const SandboxMode* = when disableSandbox:
  stNone
elif defined(freebsd):
  stCapsicum
elif defined(openbsd):
  stPledge
elif defined(linux):
  stLibSeccomp
else:
  stNone

when SandboxMode == stCapsicum:
  import bindings/capsicum

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
  import bindings/pledge

  proc enterBufferSandbox*(sockPath: string) =
    # take whatever we need to
    # * fork
    # * connect to UNIX domain sockets
    # * take FDs from the main process
    doAssert pledge("unix stdio sendfd recvfd proc", nil) == 0

  proc enterNetworkSandbox*() =
    # we don't need much to write out data from sockets to stdout.
    doAssert pledge("stdio", nil) == 0
elif SandboxMode == stLibSeccomp:
  import std/posix
  import bindings/libseccomp

  when defined(android):
    let PR_SET_VMA {.importc, header: "<sys/prctl.h>", nodecl.}: cint
    let PR_SET_VMA_ANON_NAME {.importc, header: "<sys/prctl.h>", nodecl.}: cint

    proc allowBionic(ctx: scmp_filter_ctx) =
      # Things needed for bionic libc. Tested with Termux.
      const androidAllowList = [
        cstring"rt_sigprocmask",
        "madvise"
      ]
      for it in androidAllowList:
        let syscall = seccomp_syscall_resolve_name(it)
        doAssert seccomp_rule_add(ctx, SCMP_ACT_ALLOW, syscall, 0) == 0
      # bionic likes to set this very much. In fact, it was added to
      # the kernel by Android devs.
      block allowAnonVMAName:
        let syscall = seccomp_syscall_resolve_name("prctl")
        let arg0 = scmp_arg_cmp(
          arg: 0, # op
          op: SCMP_CMP_EQ, # equals
          datum_a: uint64(PR_SET_VMA)
        )
        let arg1 = scmp_arg_cmp(
          arg: 1, # attr
          op: SCMP_CMP_EQ, # equals
          datum_a: uint64(PR_SET_VMA_ANON_NAME)
        )
        doAssert seccomp_rule_add(ctx, SCMP_ACT_ALLOW, syscall, 2, arg0,
          arg1) == 0
      # We have to be careful with this one; PROT_EXEC will happily set
      # memory as executable, which is certainly not what we want.
      # Now, bionic seems to be calling this from mutate(), ergo we
      # should be fine just allowing PROT_READ and PROT_READ | PROT_WRITE.
      block allowMprotect:
        let syscall = seccomp_syscall_resolve_name("mprotect")
        let arg2 = scmp_arg_cmp(
          arg: 2, # attr
          op: SCMP_CMP_LE, # less than or equals
          datum_a: 3 # PROT_READ | PROT_WRITE
        )
        # Note that libseccomp can't really express multiple comparisons.
        # However, we are lucky, and we only have to "excessively" allow
        # PROT_WRITE (w/o PROT_READ) and PROT_NONE, which does no harm.
        doAssert seccomp_rule_add(ctx, SCMP_ACT_ALLOW, syscall, 1, arg2) == 0

  proc blockStat(ctx: scmp_filter_ctx) =
    # glibc calls fstat and its variants on fread, and it's quite hard
    # to ensure we never use it. Plus, in older glibc versions (< 2.39),
    # fstat is implemented as fstatat, and allowing that would imply
    # access to arbitrary paths. So for consistency, we make all of them
    # return an error.
    #
    # The offending function is _IO_file_doallocate; it doesn't actually
    # look at errno, so EPERM should work fine.
    const err = SCMP_ACT_ERRNO(1u16)
    const fstatList = [
      cstring"fstat",
      "fstat64",
      "fstatat64",
      "newfstatat",
      "statx"
    ]
    for it in fstatList:
      let syscall = seccomp_syscall_resolve_name(it)
      doAssert seccomp_rule_add(ctx, err, syscall, 0) == 0

  proc allowFcntl(ctx: scmp_filter_ctx) =
    # only allow F_DUPFD, F_GETFD, F_SETFD, F_GETFL, F_SETFL
    # (F_SETFL is 4, the other ones are 0-3)
    let syscall = seccomp_syscall_resolve_name("fcntl")
    let syscall2 = seccomp_syscall_resolve_name("fcntl64")
    let arg1 = scmp_arg_cmp(
      arg: 1, # cmd
      op: SCMP_CMP_LE, # less than or equals
      datum_a: 4 # F_SETFL (includes the above mentioned ones)
    )
    doAssert seccomp_rule_add(ctx, SCMP_ACT_ALLOW, syscall, 1, arg1) == 0
    doAssert seccomp_rule_add(ctx, SCMP_ACT_ALLOW, syscall2, 1, arg1) == 0

  proc enterBufferSandbox*(sockPath: string) =
    onSignal SIGSYS:
      discard sig
      raise newException(Defect, "Sandbox violation in buffer")
    let ctx = seccomp_init(SCMP_ACT_TRAP)
    doAssert pointer(ctx) != nil
    const allowList = [
      cstring"accept", # for incoming requests to our controlling socket
      "accept4", # for when accept is implemented as accept4
      "bind", # for outgoing requests to loader
      "brk", # memory allocation
      "clock_gettime", # used by QuickJS in atomics
      "clone", # for when fork is implemented as clone
      "close", # duh
      "connect", # for outgoing requests to loader
      "exit_group", # for quit
      "fork", # for when fork is really fork
      "futex", # bionic libc & WSL both need it
      "getpid", # for determining current PID after we fork
      "getsockname", # Nim needs it for connecting
      "gettimeofday", # used by QuickJS in Date.now()
      "lseek", # glibc calls lseek on open files at exit
      "mmap", # memory allocation
      "mmap2", # memory allocation
      "mremap", # memory allocation
      "munmap", # memory allocation
      "pipe", # for pipes to child process
      "pipe2", # for when pipe is implemented as pipe2
      "poll", "ppoll", # for polling (sometimes implemented as ppoll, see musl)
      "read", "recv", "recvfrom", "recvmsg", # for reading from sockets
      "restart_syscall", # for resuming poll on SIGCONT
      "rt_sigreturn", # for when sigreturn is implemented as rt_sigreturn
      "send", "sendmsg", "sendto", # for writing to sockets
      "set_robust_list", # glibc seems to need it for whatever reason
      "sigreturn", # called by signal trampoline
      "write" # for writing to sockets
    ]
    for it in allowList:
      let syscall = seccomp_syscall_resolve_name(it)
      doAssert seccomp_rule_add(ctx, SCMP_ACT_ALLOW, syscall, 0) == 0
    block allowUnixSockets:
      # only allow creation of UNIX domain sockets.
      let syscall = seccomp_syscall_resolve_name("socket")
      let arg0 = scmp_arg_cmp(
        arg: 0, # domain
        op: SCMP_CMP_EQ, # equals
        datum_a: 1 # PF_LOCAL == PF_UNIX == AF_UNIX
      )
      doAssert seccomp_rule_add(ctx, SCMP_ACT_ALLOW, syscall, 1, arg0) == 0
    ctx.allowFcntl()
    ctx.blockStat()
    when defined(android):
      ctx.allowBionic()
    doAssert seccomp_load(ctx) == 0
    seccomp_release(ctx)

  proc enterNetworkSandbox*() =
    onSignal SIGSYS:
      discard sig
      raise newException(Defect, "Sandbox violation in network process")
    let ctx = seccomp_init(SCMP_ACT_KILL_PROCESS)
    doAssert pointer(ctx) != nil
    const allowList = [
      cstring"close", "exit_group", # duh
      "read", "write", "recv", "send", "recvfrom", "sendto", # socket i/o
      "lseek", # glibc calls lseek on open files at exit
      "mmap", "mmap2", "mremap", "munmap", "brk", # memory allocation
      "poll", "ppoll", # curl, ansi2html needs poll
      "restart_syscall", # for resuming poll on SIGCONT
      "getpid", # used indirectly by OpenSSL EVP_RAND_CTX_new (through drbg)
      "futex", # bionic libc & WSL both need it
      # we either have to use CURLOPT_NOSIGNAL or allow signals.
      # do the latter, otherwise the default name resolver will never time out.
      "signal", "sigaction", "rt_sigaction",
    ]
    for it in allowList:
      doAssert seccomp_rule_add(ctx, SCMP_ACT_ALLOW,
        seccomp_syscall_resolve_name(it), 0) == 0
    ctx.allowFcntl()
    ctx.blockStat()
    when defined(android):
      ctx.allowBionic()
    doAssert seccomp_load(ctx) == 0
    seccomp_release(ctx)
else:
  {.warning: "Building without OS-level sandboxing!".}
  proc enterBufferSandbox*(sockPath: string) =
    discard

  proc enterNetworkSandbox*() =
    discard
