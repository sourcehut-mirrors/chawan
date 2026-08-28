{.push raises: [].}

import std/os
import std/posix

import config/config
import config/mailcap
import encoding/charset
import io/chafile
import io/dynstream
import io/packetreader
import io/packetwriter
import io/poll
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsref
import monoucha/quickjs
import server/buffer
import server/bufferiface
import server/headers
import server/loader
import server/loaderiface
import types/opt
import types/url
import types/winattrs
import utils/myposix
import utils/proctitle
import utils/sandbox
import utils/strwidth
import utils/twtstr

type
  ForkServer* = object
    pid*: Pid
    stream*: PosixStream
    estream*: PosixStream
    westream*: PosixStream

  ForkServerContext = object
    stream: PosixStream
    loaderStream: PosixStream
    pollData: PollData
    linkHintChars: seq[uint32]
    schemes: seq[string]

proc loadConfig*(forkserver: ForkServer; config: Config;
    warnings: var seq[string]): int =
  forkserver.stream.withPacketWriter w:
    w.swrite(config{"doubleWidthAmbiguous"})
    w.swrite(config{"linkHintChars"})
    w.swrite(LoaderConfig(
      w3mCGICompat: config{"w3mCgiCompat"},
      cgiDir: config{"cgiDir"},
      tmpdir: config{"tmpdir"},
      configDir: config.dir,
      dataDir: config.dataDir,
      bookmark: config{"bookmark"},
      maxNetConnections: config{"maxNetConnections"},
    ))
    # client config for pager
    w.swrite(LoaderClientConfig(
      defaultHeaders: config{"defaultHeaders"},
      proxy: config{"proxy"},
      allowAllSchemes: true
    ))
    w.swrite(config{"urimethodmap"})
    w.swrite(config{"autoBrowsecap"})
  do:
    return -1
  var process = -1
  var fswarnings: seq[string]
  forkserver.stream.withPacketReaderFire r:
    r.sread(process)
    r.sread(fswarnings)
  warnings.add(fswarnings)
  return process

proc forkBuffer*(forkserver: ForkServer; config: BufferConfig; url: URL;
    attrs: WindowAttributes; ishtml: bool; charsetStack: seq[Charset];
    contentType: string): tuple[pid: int; cstream: PosixStream] =
  var sv {.noinit.}: array[2, cint]
  if socketpair(AF_UNIX, SOCK_STREAM, IPPROTO_IP, sv) != 0:
    return (-1, nil)
  var fail = false
  forkserver.stream.withPacketWriter w:
    w.swrite(config)
    w.swrite(url)
    w.swrite(attrs)
    w.swrite(ishtml)
    w.swrite(charsetStack)
    w.swrite(contentType)
    w.sendFd(sv[1])
  do:
    fail = true
  var bufferPid = -1
  if not fail:
    forkserver.stream.withPacketReaderFire r:
      r.sread(bufferPid)
  if bufferPid == -1:
    discard close(sv[0])
    return (-1, nil)
  return (bufferPid, newPosixStream(sv[0]))

when defined(nimUseStrictDefs):
  template myProveInit(x: untyped): untyped =
    {.warning[ProveInit]:off.}:
      x
else:
  template myProveInit(x: untyped): untyped =
    x

proc forkLoader(ctx: var ForkServerContext; rt: JSRuntime;
    config: LoaderConfig; loaderStream: PosixStream; pagerPid: int;
    pagerConfig: LoaderClientConfig; browsecap: Mailcap): (int, PosixStream)
    {.myProveInit.} =
  # loaderStream is a connection between main process <-> loader, but we
  # also need a connection between fork server <-> loader.
  # The naming here is very confusing, sorry about that.
  var sv {.noinit.}: array[2, cint]
  if socketpair(AF_UNIX, SOCK_STREAM, IPPROTO_IP, sv) != 0:
    loaderStream.sclose()
    return (-1, nil)
  stderr.flushFile()
  let pid = fork()
  if pid == 0:
    # child process
    ctx.stream.sclose()
    discard close(sv[0])
    let forkStream = newPosixStream(sv[1])
    setProcessTitle("cha loader")
    runFileLoader(rt, config, loaderStream, forkStream, pagerPid, pagerConfig,
      browsecap)
    exitnow(1)
  else:
    discard close(sv[1])
    loaderStream.sclose()
    return (int(pid), newPosixStream(sv[0]))

proc forkBuffer(ctx: var ForkServerContext; r: var PacketReader;
    rt: JSRuntime): int =
  var config: BufferConfig
  var url: URL
  var attrs: WindowAttributes
  var ishtml: bool
  var charsetStack: seq[Charset]
  var contentType: string
  r.sread(config)
  r.sread(url)
  r.sread(attrs)
  r.sread(ishtml)
  r.sread(charsetStack)
  r.sread(contentType)
  let fd = r.recvFd()
  stderr.flushFile()
  let pid = fork()
  if pid == 0:
    # child process
    ctx.stream.sclose()
    ctx.loaderStream.sclose()
    setBufferProcessTitle(url)
    let pid = getCurrentProcessId()
    let urandom = newPosixStream("/dev/urandom", O_RDONLY, 0)
    let pstream = newPosixStream(fd)
    var cacheId: int
    var loaderStream: PosixStream
    var istream: PosixStream
    pstream.withPacketReader r:
      r.sread(cacheId)
      loaderStream = newPosixStream(r.recvFd())
      istream = newPosixStream(r.recvFd())
    do: # EOF in pager; give up
      quit(1)
    let loader = newFileLoader(pid, loaderStream)
    let stdout = cast[ChaFile](stdout)
    discard stdout.flush()
    discard dup2(STDERR_FILENO, STDOUT_FILENO) # QJS logs errors to stdout
    setbuf(stdout, nil)
    # SIGPIPE remains ignored, because we don't want the buffer to signal
    # just because the pager unregistered it (this can also happen when a
    # buffer is cloned)
    enterBufferSandbox()
    launchBuffer(rt, config, url, attrs, ishtml, charsetStack, loader, pstream,
      istream, urandom, cacheId, contentType, move(ctx.linkHintChars),
      move(ctx.schemes))
    doAssert false
  discard close(fd)
  return pid

proc forkCGI(ctx: var ForkServerContext; r: var PacketReader): int {.noinit.} =
  var hasIstream: bool
  r.sread(hasIstream)
  let istream = if hasIstream: newPosixStream(r.recvFd()) else: nil
  let ostream = newPosixStream(r.recvFd())
  # hack to detect when the child died
  var hasOstreamOut2: bool
  r.sread(hasOstreamOut2)
  let ostreamOut2 = if hasOstreamOut2: newPosixStream(r.recvFd()) else: nil
  var env: seq[tuple[name, value: string]]
  var argv: seq[string]
  var cmd: string
  r.sread(env)
  r.sread(argv)
  r.sread(cmd)
  let pid = fork()
  if pid == 0: # child
    ctx.stream.sclose()
    ctx.loaderStream.sclose()
    # we leave stderr open, so it can be seen in the browser console
    if istream != nil:
      istream.moveFd(STDIN_FILENO)
    else:
      closeStdin()
    ostream.moveFd(STDOUT_FILENO)
    # reset SIGCHLD to the default handler. this is useful if the child
    # process expects SIGCHLD to be untouched.
    # (e.g. git dies a horrible death with SIGCHLD as SIG_IGN)
    discard myposix.signal(SIGCHLD, myposix.SIG_DFL)
    # let's also reset SIGPIPE, which we ignored on init
    discard myposix.signal(SIGPIPE, myposix.SIG_DFL)
    const ExecErrorMsg =
      "Cha-Control: ConnectionError InternalError failed to execute CGI script"
    let stdout = cast[ChaFile](stdout)
    env.add(("SCRIPT_FILENAME", cmd))
    for it in env:
      if twtstr.setEnv(it.name, it.value).isErr:
        discard stdout.writeLine(ExecErrorMsg & " failed to set env vars")
        exitnow(1)
    let i = cmd.rfind('/')
    cmd[i] = '\0'
    if chdir(cstring(cmd)) != 0:
      discard stdout.writeLine(ExecErrorMsg &
        " failed to set working directory")
      exitnow(1)
    cmd[i] = '/'
    var cargv = newSeq[cstring](argv.len + 2)
    cargv[0] = cast[cstring](addr cmd[i + 1])
    for i in 0 ..< argv.len:
      cargv[i + 1] = cstring(argv[i])
    discard execv(cstring(cmd), cast[cstringArray](addr cargv[0]))
    let es = $strerror(errno)
    discard stdout.writeLine(ExecErrorMsg & ' ' & es.deleteChars({'\n', '\r'}))
    exitnow(1)
  else: # parent or error
    if istream != nil:
      istream.sclose()
    ostream.sclose()
    if ostreamOut2 != nil:
      ostreamOut2.sclose()
    return pid

proc setupForkServerEnv(config: LoaderConfig): Opt[void] =
  ?twtstr.setEnv("SERVER_SOFTWARE", "Chawan")
  ?twtstr.setEnv("SERVER_PROTOCOL", "HTTP/1.0")
  ?twtstr.setEnv("SERVER_NAME", "localhost")
  ?twtstr.setEnv("SERVER_PORT", "80")
  ?twtstr.setEnv("REMOTE_HOST", "localhost")
  ?twtstr.setEnv("REMOTE_ADDR", "127.0.0.1")
  ?twtstr.setEnv("GATEWAY_INTERFACE", "CGI/1.1")
  ?twtstr.setEnv("CHA_INSECURE_SSL_NO_VERIFY", "0")
  ?twtstr.setEnv("CHA_TMP_DIR", config.tmpdir)
  ?twtstr.setEnv("CHA_DIR", config.configDir)
  ?twtstr.setEnv("CHA_DATA_DIR", config.dataDir)
  ?twtstr.setEnv("CHA_BOOKMARK", config.bookmark)
  ok()

const DefaultBrowsecap = """
http;			http %h %p %s %?;	cgioutput; resource; netpath
https;			https %h %p %s %?;	cgioutput; resource; netpath
finger/get;		finger %h %p %s;	cgioutput; resource; netpath
gemini;			gemini %h %p %s %?;	cgioutput; resource; netpath
file;			file %s;		cgioutput; resource
ftp/get;		ftp %h %p %s;		cgioutput; resource; netpath
sftp/get;		sftp %h %p %s;		cgioutput; resource; netpath
gopher/get;		gopher %h %p %s %?;	cgioutput; resource; netpath
spartan;		spartan %h %p %s %?;	cgioutput; resource; netpath
man/get;		man -r %s;		cgioutput; resource
man-k/get;		man -k %s;		cgioutput; resource
man-l/get;		man -l %s;		cgioutput; resource
cgi-bin;		%s%?;			cgioutput; resource
img-codec+png;		stbi png %s;		cgioutput; resource; internal
img-codec+jpeg;		stbi jpeg %s;		cgioutput; resource; internal
img-codec+gif;		stbi gif %s;		cgioutput; resource; internal
img-codec+bmp;		stbi bmp %s;		cgioutput; resource; internal
img-codec+x-unknown;	stbi x-unknown %s;	cgioutput; resource; internal
img-codec+webp;		jebp %s;		cgioutput; resource; internal
img-codec+x-sixel;	sixel %s;		cgioutput; resource; internal
img-codec+x-cha-canvas;	canvas %s;		cgioutput; resource; internal
img-codec+svg+xml;	nanosvg %s;		cgioutput; resource; internal
"""

proc runForkServer*(controlStream, loaderStream: PosixStream; pagerPid: int;
    rt: JSRuntime) =
  setProcessTitle("cha forkserver")
  let jsctx = rt.newDummyContext()
  if jsctx == nil:
    quit(2)
  # init JS classes needed in forkserver & loader
  if jsctx.addURLModule().isErr:
    quit(2)
  if jsctx.addHeadersModule().isErr:
    quit(2)
  JS_FreeContext(jsctx)
  var ctx = ForkServerContext(stream: controlStream)
  discard myposix.signal(SIGCHLD, myposix.SIG_IGN)
  discard myposix.signal(SIGPIPE, myposix.SIG_IGN)
  ctx.stream.withPacketReader r:
    var config: LoaderConfig
    var clientConfig: LoaderClientConfig
    var linkHintChars: string
    var urimethodmapPaths: seq[string]
    var autoBrowsecapPath: string
    r.sread(isCJKAmbiguous)
    r.sread(linkHintChars)
    r.sread(config)
    r.sread(clientConfig)
    r.sread(urimethodmapPaths)
    r.sread(autoBrowsecapPath)
    ctx.linkHintChars = linkHintChars.toPoints()
    # for CGI
    if setupForkServerEnv(config).isErr:
      quit(1)
    var warnings: seq[string]
    var browsecap: Mailcap
    block:
      let res = browsecap.parseMailcap(autoBrowsecapPath, lenient = true)
      if res.isErr:
        warnings.add(res.error)
    for path in urimethodmapPaths:
      if file := chafile.fopen(path, "r"):
        discard browsecap.parseURIMethodMap(file)
        discard file.close()
    browsecap.parseBuiltin(DefaultBrowsecap)
    for t in browsecap.mainTypes:
      ctx.schemes.add(t)
    # returns a new stream that connects fork server <-> loader and
    # gives away main process <-> loader
    var (pid, loaderStream) = ctx.forkLoader(rt, config, loaderStream,
      pagerPid, clientConfig, browsecap)
    ctx.stream.withPacketWriter w:
      w.swrite(pid)
      w.swrite(warnings)
    do:
      pid = -1
    if pid == -1:
      # Notified main process of failure; our job is done.
      quit(1)
    ctx.loaderStream = loaderStream
  do:
    quit(1)
  ctx.pollData.register(ctx.stream.fd, POLLIN)
  ctx.pollData.register(ctx.loaderStream.fd, POLLIN)
  block mainLoop:
    while true:
      ctx.pollData.poll(-1)
      for event in ctx.pollData.events:
        if (event.revents and POLLIN) != 0:
          if event.fd == ctx.stream.fd:
            ctx.stream.withPacketReader r:
              let pid = ctx.forkBuffer(r, rt)
              ctx.stream.withPacketWriter w:
                w.swrite(pid)
              do:
                break mainLoop # EOF
            do:
              break mainLoop # EOF
          elif event.fd == ctx.loaderStream.fd:
            ctx.loaderStream.withPacketReader r:
              let pid = ctx.forkCGI(r)
              ctx.loaderStream.withPacketWriter w:
                w.swrite(pid)
              do:
                break mainLoop # EOF
            do:
              break mainLoop # EOF
        if (event.revents and POLLERR) != 0 or (event.revents and POLLHUP) != 0:
          break mainLoop # EOF
  ctx.stream.sclose()
  # Clean up when the main process crashed.
  discard kill(0, cint(SIGTERM))
  quit(0)

{.pop.} # raises: []
