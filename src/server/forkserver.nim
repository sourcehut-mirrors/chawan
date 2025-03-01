import std/options
import std/os
import std/posix
import std/tables

import chagashi/charset
import config/config
import config/urimethodmap
import io/dynstream
import io/packetreader
import io/packetwriter
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
    stream: SocketStream
    estream*: PosixStream

  ForkServerContext = object
    stream: SocketStream
    children: seq[int]
    loaderPid: int
    loaderStream: SocketStream

proc loadConfig*(forkserver: ForkServer; config: Config): int =
  forkserver.stream.withPacketWriter w:
    w.swrite(fcLoadConfig)
    w.swrite(config.display.doubleWidthAmbiguous)
    w.swrite(LoaderConfig(
      urimethodmap: config.external.urimethodmap,
      w3mCGICompat: config.external.w3mCgiCompat,
      cgiDir: seq[string](config.external.cgiDir),
      tmpdir: config.external.tmpdir,
      configdir: config.dir,
      bookmark: config.external.bookmark
    ))
  var process: int
  forkserver.stream.withPacketReader r:
    r.sread(process)
  return process

proc removeChild*(forkserver: ForkServer; pid: int) =
  forkserver.stream.withPacketWriter w:
    w.swrite(fcRemoveChild)
    w.swrite(pid)

proc forkBuffer*(forkserver: ForkServer; config: BufferConfig; url: URL;
    attrs: WindowAttributes; ishtml: bool; charsetStack: seq[Charset]):
    tuple[pid: int; fd: cint] =
  var sv {.noinit.}: array[2, cint]
  #TODO fail gracefully
  if socketpair(AF_UNIX, SOCK_STREAM, IPPROTO_IP, sv) != 0:
    raise newException(Defect, "Failed to open socket pair")
  forkserver.stream.withPacketWriter w:
    w.swrite(fcForkBuffer)
    w.swrite(config)
    w.swrite(url)
    w.swrite(attrs)
    w.swrite(ishtml)
    w.swrite(charsetStack)
    w.sendFd(sv[1])
  discard close(sv[1])
  var bufferPid: int
  forkserver.stream.withPacketReader r:
    r.sread(bufferPid)
  return (bufferPid, sv[0])

proc trapSIGINT() =
  # trap SIGINT, so e.g. an external editor receiving an interrupt in the
  # same process group can't just kill the process
  # Note that the main process normally quits on interrupt (thus terminating
  # all child processes as well).
  setControlCHook(proc() {.noconv.} = discard)

proc forkLoader(ctx: var ForkServerContext; config: LoaderConfig): int =
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

proc forkBuffer(ctx: var ForkServerContext; r: var PacketReader): int =
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
  let fd = r.recvFd()
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
    zeroMem(addr ctx, sizeof(ctx))
    setBufferProcessTitle(url)
    let pid = getCurrentProcessId()
    let urandom = newPosixStream("/dev/urandom", O_RDONLY, 0)
    let pstream = newSocketStream(fd)
    var cacheId: int
    var loaderStream: SocketStream
    var istream: SocketStream
    pstream.withPacketReader r:
      r.sread(cacheId)
      loaderStream = newSocketStream(r.recvFd())
      istream = newSocketStream(r.recvFd())
    let loader = newFileLoader(loaderPid, pid, loaderStream)
    gpstream = pstream
    onSignal SIGTERM:
      discard sig
      if gpstream != nil:
        gpstream.sclose()
        gpstream = nil
      exitnow(1)
    signal(SIGPIPE, SIG_DFL)
    enterBufferSandbox()
    try:
      launchBuffer(config, url, attrs, ishtml, charsetStack, loader, pstream,
        istream, urandom, cacheId)
    except CatchableError:
      let e = getCurrentException()
      # taken from system/excpt.nim
      let msg = e.getStackTrace() & "Error: unhandled exception: " & e.msg &
        " [" & $e.name & "]\n"
      stderr.write(msg)
      quit(1)
    doAssert false
  discard close(fd)
  ctx.children.add(pid)
  return pid

proc runForkServer(controlStream, loaderStream: SocketStream) =
  setProcessTitle("cha forkserver")
  var ctx = ForkServerContext(
    stream: controlStream,
    loaderStream: loaderStream
  )
  signal(SIGCHLD, SIG_IGN)
  signal(SIGPIPE, SIG_IGN)
  while true:
    try:
      ctx.stream.withPacketReader r:
        var cmd: ForkCommand
        r.sread(cmd)
        case cmd
        of fcLoadConfig:
          assert ctx.loaderPid == 0
          var config: LoaderConfig
          r.sread(isCJKAmbiguous)
          r.sread(config)
          let pid = ctx.forkLoader(config)
          ctx.stream.withPacketWriter w:
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
          ctx.stream.withPacketWriter w:
            w.swrite(r)
    except EOFError:
      # EOF
      break
  ctx.stream.sclose()
  # Clean up when the main process crashed.
  #TODO this seems like a bad idea; children may be out of sync here...
  for child in ctx.children:
    discard kill(cint(child), cint(SIGTERM))
  quit(0)

proc newForkServer*(loaderSockVec: array[2, cint]): ForkServer =
  var sockVec {.noinit.}: array[2, cint] # stdin in forkserver
  var pipeFdErr {.noinit.}: array[2, cint] # stderr in forkserver
  if socketpair(AF_UNIX, SOCK_STREAM, IPPROTO_IP, sockVec) != 0:
    stderr.writeLine("Failed to open fork server i/o socket")
    quit(1)
  if pipe(pipeFdErr) == -1:
    stderr.writeLine("Failed to open fork server error pipe")
    quit(1)
  let pid = fork()
  if pid == -1:
    stderr.writeLine("Failed to fork fork the server process")
    quit(1)
  elif pid == 0:
    # child process
    trapSIGINT()
    closeStdin()
    closeStdout()
    newPosixStream(pipeFdErr[1]).moveFd(STDERR_FILENO)
    discard close(pipeFdErr[0]) # close read
    discard close(sockVec[0])
    discard close(loaderSockVec[0])
    let controlStream = newSocketStream(sockVec[1])
    let loaderStream = newSocketStream(loaderSockVec[1])
    runForkServer(controlStream, loaderStream)
    doAssert false
  else:
    discard close(pipeFdErr[1]) # close write
    discard close(sockVec[1])
    discard close(loaderSockVec[1])
    let stream = newSocketStream(sockVec[0])
    stream.setCloseOnExec()
    let estream = newPosixStream(pipeFdErr[0])
    estream.setCloseOnExec()
    estream.setBlocking(false)
    return ForkServer(stream: stream, estream: estream)
