import std/options
import std/os
import std/posix
import std/tables

import chagashi/charset
import config/config
import html/formdata
import io/bufreader
import io/bufwriter
import io/dynstream
import io/serversocket
import io/stdio
import loader/loader
import loader/loaderiface
import server/buffer
import types/urimethodmap
import types/url
import types/winattrs
import utils/proctitle
import utils/sandbox
import utils/strwidth

type
  ForkCommand = enum
    fcLoadConfig, fcForkBuffer, fcRemoveChild

  ForkServer* = ref object
    istream: PosixStream
    ostream: PosixStream
    estream*: PosixStream

  ForkServerContext = object
    istream: PosixStream
    ostream: PosixStream
    children: seq[int]
    loaderPid: int
    sockDirFd: int
    sockDir: string

proc loadConfig*(forkserver: ForkServer; config: Config): int =
  forkserver.ostream.withPacketWriter w:
    w.swrite(fcLoadConfig)
    w.swrite(config.display.double_width_ambiguous)
    w.swrite(LoaderConfig(
      urimethodmap: config.external.urimethodmap,
      w3mCGICompat: config.external.w3m_cgi_compat,
      cgiDir: seq[string](config.external.cgi_dir),
      tmpdir: config.external.tmpdir,
      sockdir: config.external.sockdir,
      configdir: config.configdir
    ))
  var r = forkserver.istream.initPacketReader()
  var process: int
  r.sread(process)
  return process

proc removeChild*(forkserver: ForkServer; pid: int) =
  forkserver.ostream.withPacketWriter w:
    w.swrite(fcRemoveChild)
    w.swrite(pid)

proc forkBuffer*(forkserver: ForkServer; config: BufferConfig; url: URL;
    attrs: WindowAttributes; ishtml: bool; charsetStack: seq[Charset]):
    int =
  forkserver.ostream.withPacketWriter w:
    w.swrite(fcForkBuffer)
    w.swrite(config)
    w.swrite(url)
    w.swrite(attrs)
    w.swrite(ishtml)
    w.swrite(charsetStack)
  var r = forkserver.istream.initPacketReader()
  var bufferPid: int
  r.sread(bufferPid)
  return bufferPid

proc trapSIGINT() =
  # trap SIGINT, so e.g. an external editor receiving an interrupt in the
  # same process group can't just kill the process
  # Note that the main process normally quits on interrupt (thus terminating
  # all child processes as well).
  setControlCHook(proc() {.noconv.} = discard)

proc forkLoader(ctx: var ForkServerContext; config: LoaderConfig): int =
  var pipefd: array[2, cint]
  if pipe(pipefd) == -1:
    raise newException(Defect, "Failed to open pipe.")
  stdout.flushFile()
  stderr.flushFile()
  let pid = fork()
  if pid == 0:
    # child process
    trapSIGINT()
    for i in 0 ..< ctx.children.len: ctx.children[i] = 0
    ctx.children.setLen(0)
    zeroMem(addr ctx, sizeof(ctx))
    discard close(pipefd[0]) # close read
    try:
      setProcessTitle("cha loader")
      runFileLoader(pipefd[1], config)
    except CatchableError:
      let e = getCurrentException()
      # taken from system/excpt.nim
      let msg = e.getStackTrace() & "Error: unhandled exception: " & e.msg &
        " [" & $e.name & "]\n"
      stderr.write(msg)
      quit(1)
    doAssert false
  let readfd = pipefd[0] # get read
  discard close(pipefd[1]) # close write
  var readf: File
  if not open(readf, FileHandle(readfd), fmRead):
    raise newException(Defect, "Failed to open output handle.")
  let c = readf.readChar()
  assert c == char(0u8)
  close(readf)
  discard close(pipefd[0])
  return pid

proc forkBuffer(ctx: var ForkServerContext; r: var BufferedReader): int =
  var config: BufferConfig
  var url: URL
  var attrs: WindowAttributes
  var ishtml: bool
  var charsetStack: seq[Charset]
  r.sread(config)
  r.sread(url)
  r.sread(attrs)
  r.sread(ishtml)
  r.sread(charsetStack)
  var pipefd: array[2, cint]
  if pipe(pipefd) == -1:
    raise newException(Defect, "Failed to open pipe.")
  stdout.flushFile()
  stderr.flushFile()
  let pid = fork()
  if pid == -1:
    raise newException(Defect, "Failed to fork process.")
  if pid == 0:
    # child process
    trapSIGINT()
    for i in 0 ..< ctx.children.len: ctx.children[i] = 0
    ctx.children.setLen(0)
    let loaderPid = ctx.loaderPid
    let sockDir = ctx.sockDir
    let sockDirFd = ctx.sockDirFd
    zeroMem(addr ctx, sizeof(ctx))
    discard close(pipefd[0]) # close read
    closeStdin()
    closeStdout()
    setBufferProcessTitle(url)
    let pid = getCurrentProcessId()
    let ssock = initServerSocket(sockDir, sockDirFd, pid)
    let ps = newPosixStream(pipefd[1])
    ps.write(char(0))
    ps.sclose()
    urandom = newPosixStream("/dev/urandom", O_RDONLY, 0)
    let pstream = ssock.acceptSocketStream()
    gssock = ssock
    gpstream = pstream
    onSignal SIGTERM:
      discard sig
      gpstream.sclose()
      gssock.close(unlink = false)
      exitnow(1)
    signal(SIGPIPE, SIG_DFL)
    enterBufferSandbox(sockDir)
    let loader = FileLoader(
      process: loaderPid,
      clientPid: pid,
      sockDir: sockDir,
      sockDirFd: sockDirFd
    )
    try:
      launchBuffer(config, url, attrs, ishtml, charsetStack, loader,
        ssock, pstream)
    except CatchableError:
      let e = getCurrentException()
      # taken from system/excpt.nim
      let msg = e.getStackTrace() & "Error: unhandled exception: " & e.msg &
        " [" & $e.name & "]\n"
      stderr.write(msg)
      quit(1)
    doAssert false
  discard close(pipefd[1]) # close write
  let ps = newPosixStream(pipefd[0])
  let c = ps.sreadChar()
  assert c == char(0)
  ps.sclose()
  ctx.children.add(pid)
  return pid

proc runForkServer() =
  setProcessTitle("cha forkserver")
  var ctx = ForkServerContext(
    istream: newPosixStream(stdin.getFileHandle()),
    ostream: newPosixStream(stdout.getFileHandle()),
    sockDirFd: -1
  )
  signal(SIGCHLD, SIG_IGN)
  signal(SIGPIPE, SIG_IGN)
  while true:
    try:
      ctx.istream.withPacketReader r:
        var cmd: ForkCommand
        r.sread(cmd)
        case cmd
        of fcLoadConfig:
          assert ctx.loaderPid == 0
          var config: LoaderConfig
          r.sread(isCJKAmbiguous)
          r.sread(config)
          ctx.sockDir = config.sockdir
          when defined(freebsd):
            ctx.sockDirFd = open(cstring(ctx.sockDir), O_DIRECTORY)
          let pid = ctx.forkLoader(config)
          ctx.ostream.withPacketWriter w:
            w.swrite(pid)
          ctx.loaderPid = pid
          ctx.children.add(pid)
        of fcRemoveChild:
          var pid: int
          r.sread(pid)
          let i = ctx.children.find(pid)
          if i != -1:
            ctx.children.del(i)
        of fcForkBuffer:
          let r = ctx.forkBuffer(r)
          ctx.ostream.withPacketWriter w:
            w.swrite(r)
    except EOFError, ErrorBrokenPipe:
      # EOF
      break
  ctx.istream.sclose()
  ctx.ostream.sclose()
  # Clean up when the main process crashed.
  for child in ctx.children:
    discard kill(cint(child), cint(SIGTERM))
  quit(0)

proc newForkServer*(): ForkServer =
  var pipefd_in: array[2, cint] # stdin in forkserver
  var pipefd_out: array[2, cint] # stdout in forkserver
  var pipefd_err: array[2, cint] # stderr in forkserver
  if pipe(pipefd_in) == -1:
    raise newException(Defect, "Failed to open input pipe.")
  if pipe(pipefd_out) == -1:
    raise newException(Defect, "Failed to open output pipe.")
  if pipe(pipefd_err) == -1:
    raise newException(Defect, "Failed to open error pipe.")
  stdout.flushFile()
  stderr.flushFile()
  let pid = fork()
  if pid == -1:
    raise newException(Defect, "Failed to fork the fork process.")
  elif pid == 0:
    # child process
    trapSIGINT()
    discard close(pipefd_in[1]) # close write
    discard close(pipefd_out[0]) # close read
    discard close(pipefd_err[0]) # close read
    let readfd = pipefd_in[0]
    let writefd = pipefd_out[1]
    let errfd = pipefd_err[1]
    discard dup2(readfd, stdin.getFileHandle())
    discard dup2(writefd, stdout.getFileHandle())
    discard dup2(errfd, stderr.getFileHandle())
    discard close(pipefd_in[0])
    discard close(pipefd_out[1])
    discard close(pipefd_err[1])
    runForkServer()
    doAssert false
  else:
    discard close(pipefd_in[0]) # close read
    discard close(pipefd_out[1]) # close write
    discard close(pipefd_err[1]) # close write
    let estream = newPosixStream(pipefd_err[0])
    estream.setBlocking(false)
    return ForkServer(
      ostream: newPosixStream(pipefd_in[1]),
      istream: newPosixStream(pipefd_out[0]),
      estream: estream
    )
