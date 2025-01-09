import std/options
import std/os
import std/posix
import std/tables

import chagashi/charset
import config/config
import config/urimethodmap
import io/bufreader
import io/bufwriter
import io/dynstream
import server/buffer
import server/loader
import server/loaderiface
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
    sockDirFd: cint
    sockDir: string
    loaderStream: SocketStream

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
      configdir: config.dir,
      bookmark: config.external.bookmark
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
  stdout.flushFile()
  stderr.flushFile()
  let pid = fork()
  if pid == 0:
    # child process
    trapSIGINT()
    let loaderStream = ctx.loaderStream
    for i in 0 ..< ctx.children.len: ctx.children[i] = 0
    ctx.children.setLen(0)
    zeroMem(addr ctx, sizeof(ctx))
    try:
      setProcessTitle("cha loader")
      runFileLoader(config, loaderStream)
    except CatchableError:
      let e = getCurrentException()
      # taken from system/excpt.nim
      let msg = e.getStackTrace() & "Error: unhandled exception: " & e.msg &
        " [" & $e.name & "]\n"
      stderr.write(msg)
      quit(1)
    doAssert false
  ctx.loaderStream.sclose()
  ctx.loaderStream = nil
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
  var pipefd {.noinit.}: array[2, cint]
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
    setBufferProcessTitle(url)
    let pid = getCurrentProcessId()
    let ssock = newServerSocket(sockDir, sockDirFd, pid)
    let ps = newPosixStream(pipefd[1])
    ps.write(char(0))
    ps.sclose()
    let urandom = newPosixStream("/dev/urandom", O_RDONLY, 0)
    let pstream = ssock.acceptSocketStream()
    var cacheId: int
    var loaderStream: SocketStream
    pstream.withPacketReader r:
      r.sread(cacheId)
      loaderStream = newSocketStream(r.recvAux.pop())
    let loader = newFileLoader(loaderPid, pid, sockDir, sockDirFd,
      loaderStream)
    gssock = ssock
    gpstream = pstream
    onSignal SIGTERM:
      discard sig
      if gpstream != nil:
        gpstream.sclose()
        gpstream = nil
      if gssock != nil:
        gssock.close()
        gssock = nil
      exitnow(1)
    signal(SIGPIPE, SIG_DFL)
    enterBufferSandbox(sockDir)
    try:
      launchBuffer(config, url, attrs, ishtml, charsetStack, loader,
        ssock, pstream, urandom, cacheId)
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
  assert c == '\0'
  ps.sclose()
  ctx.children.add(pid)
  return pid

proc runForkServer(ifd, ofd: cint; loaderStream: SocketStream) =
  setProcessTitle("cha forkserver")
  var ctx = ForkServerContext(
    istream: newPosixStream(ifd),
    ostream: newPosixStream(ofd),
    sockDirFd: -1,
    loaderStream: loaderStream
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
          ctx.sockDirFd = openSockDir(ctx.sockDir)
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
  #TODO this seems like a bad idea; children may be out of sync here...
  for child in ctx.children:
    discard kill(cint(child), cint(SIGTERM))
  quit(0)

proc newForkServer*(sy: array[2, cint]): ForkServer =
  var pipeFdIn {.noinit.}: array[2, cint] # stdin in forkserver
  var pipeFdOut {.noinit.}: array[2, cint] # stdout in forkserver
  var pipeFdErr {.noinit.}: array[2, cint] # stderr in forkserver
  if pipe(pipeFdIn) == -1:
    raise newException(Defect, "Failed to open input pipe.")
  if pipe(pipeFdOut) == -1:
    raise newException(Defect, "Failed to open output pipe.")
  if pipe(pipeFdErr) == -1:
    raise newException(Defect, "Failed to open error pipe.")
  stdout.flushFile()
  stderr.flushFile()
  let pid = fork()
  if pid == -1:
    raise newException(Defect, "Failed to fork the fork process.")
  elif pid == 0:
    # child process
    trapSIGINT()
    closeStdin()
    closeStdout()
    newPosixStream(pipeFdErr[1]).moveFd(STDERR_FILENO)
    discard close(pipeFdIn[1]) # close write
    discard close(pipeFdOut[0]) # close read
    discard close(pipeFdErr[0]) # close read
    discard close(sy[0])
    runForkServer(pipeFdIn[0], pipeFdOut[1], newSocketStream(sy[1]))
    doAssert false
  else:
    discard close(pipeFdIn[0]) # close read
    discard close(pipeFdOut[1]) # close write
    discard close(pipeFdErr[1]) # close write
    let ostream = newPosixStream(pipeFdIn[1])
    let istream = newPosixStream(pipeFdOut[0])
    let estream = newPosixStream(pipeFdErr[0])
    estream.setBlocking(false)
    for it in [ostream, istream, estream]:
      it.setCloseOnExec()
    return ForkServer(ostream: ostream, istream: istream, estream: estream)
