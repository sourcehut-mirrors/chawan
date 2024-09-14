import std/options
import std/os
import std/posix
import std/strutils

import io/dynstream
import io/stdio
import loader/connecterror
import loader/headers
import loader/loaderhandle
import loader/request
import types/formdata
import types/url
import utils/twtstr

proc putMappedURL(url: URL) =
  putEnv("MAPPED_URI_SCHEME", url.scheme)
  putEnv("MAPPED_URI_USERNAME", url.username)
  putEnv("MAPPED_URI_PASSWORD", url.password)
  putEnv("MAPPED_URI_HOST", url.hostname)
  putEnv("MAPPED_URI_PORT", url.port)
  putEnv("MAPPED_URI_PATH", url.path.serialize())
  putEnv("MAPPED_URI_QUERY", url.query.get(""))

proc setupEnv(cmd, scriptName, pathInfo, requestURI, myDir: string;
    request: Request; contentLen: int; prevURL: URL;
    insecureSSLNoVerify: bool) =
  let url = request.url
  putEnv("SCRIPT_NAME", scriptName)
  putEnv("SCRIPT_FILENAME", cmd)
  putEnv("REQUEST_URI", requestURI)
  putEnv("REQUEST_METHOD", $request.httpMethod)
  var headers = ""
  for k, v in request.headers:
    headers &= k & ": " & v & "\r\n"
  putEnv("REQUEST_HEADERS", headers)
  if prevURL != nil:
    putMappedURL(prevURL)
  if pathInfo != "":
    putEnv("PATH_INFO", pathInfo)
  if url.query.isSome:
    putEnv("QUERY_STRING", url.query.get)
  if request.httpMethod == hmPost:
    if request.body.t == rbtMultipart:
      putEnv("CONTENT_TYPE", request.body.multipart.getContentType())
    else:
      putEnv("CONTENT_TYPE", request.headers.getOrDefault("Content-Type", ""))
    putEnv("CONTENT_LENGTH", $contentLen)
  if "Cookie" in request.headers:
    putEnv("HTTP_COOKIE", request.headers["Cookie"])
  if request.referrer != nil:
    putEnv("HTTP_REFERER", $request.referrer)
  if request.proxy != nil:
    putEnv("ALL_PROXY", $request.proxy)
  if insecureSSLNoVerify:
    putEnv("CHA_INSECURE_SSL_NO_VERIFY", "1")
  setCurrentDir(myDir)

type ControlResult = enum
  crDone, crContinue, crError

proc handleFirstLine(handle: InputHandle; line: string; headers: Headers;
    status: var uint16): ControlResult =
  let k = line.until(':')
  if k.len == line.len:
    # invalid
    handle.sendResult(ERROR_CGI_MALFORMED_HEADER)
    return crError
  let v = line.substr(k.len + 1).strip()
  if k.equalsIgnoreCase("Status"):
    handle.sendResult(0) # success
    status = parseUInt16(v, allowSign = false).get(0)
    return crContinue
  if k.equalsIgnoreCase("Cha-Control"):
    if v.startsWithIgnoreCase("Connected"):
      handle.sendResult(0) # success
      return crContinue
    elif v.startsWithIgnoreCase("ConnectionError"):
      let errs = v.split(' ')
      if errs.len <= 1:
        handle.sendResult(ERROR_CGI_INVALID_CHA_CONTROL)
      else:
        let fb = int32(ERROR_CGI_INVALID_CHA_CONTROL)
        let code = int(parseInt32(errs[1]).get(fb))
        var message = ""
        if errs.len > 2:
          message &= errs[2]
          for i in 3 ..< errs.len:
            message &= ' '
            message &= errs[i]
        handle.sendResult(code, message)
      return crError
    elif v.startsWithIgnoreCase("ControlDone"):
      return crDone
    handle.sendResult(ERROR_CGI_INVALID_CHA_CONTROL)
    return crError
  handle.sendResult(0) # success
  headers.add(k, v)
  return crDone

proc handleControlLine(handle: InputHandle; line: string; headers: Headers;
    status: var uint16): ControlResult =
  let k = line.until(':')
  if k.len == line.len:
    # invalid
    return crError
  let v = line.substr(k.len + 1).strip()
  if k.equalsIgnoreCase("Status"):
    status = parseUInt16(v, allowSign = false).get(0)
    return crContinue
  if k.equalsIgnoreCase("Cha-Control"):
    if v.startsWithIgnoreCase("ControlDone"):
      return crDone
    return crError
  headers.add(k, v)
  return crDone

# returns false if transfer was interrupted
proc handleLine(handle: InputHandle; line: string; headers: Headers) =
  let k = line.until(':')
  if k.len == line.len:
    # invalid
    return
  let v = line.substr(k.len + 1).strip()
  headers.add(k, v)

proc loadCGI*(handle: InputHandle; request: Request; cgiDir: seq[string];
    prevURL: URL; insecureSSLNoVerify: bool; handleMap: openArray[LoaderHandle];
    istream: PosixStream; ostream: var PosixStream) =
  if cgiDir.len == 0:
    handle.sendResult(ERROR_NO_CGI_DIR)
    return
  var path = percentDecode(request.url.pathname)
  if path.startsWith("/cgi-bin/"):
    path.delete(0 .. "/cgi-bin/".high)
  elif path.startsWith("/$LIB/"):
    path.delete(0 .. "/$LIB/".high)
  if path == "" or request.url.hostname != "":
    handle.sendResult(ERROR_INVALID_CGI_PATH)
    return
  var basename: string
  var pathInfo: string
  var cmd: string
  var scriptName: string
  var requestURI: string
  var myDir: string
  if path[0] == '/':
    for dir in cgiDir:
      if path.startsWith(dir):
        basename = path.substr(dir.len).until('/')
        pathInfo = path.substr(dir.len + basename.len)
        cmd = dir / basename
        if not fileExists(cmd):
          continue
        myDir = dir
        scriptName = path.substr(0, dir.len + basename.len)
        requestURI = cmd / pathInfo & request.url.search
        break
    if cmd == "":
      handle.sendResult(ERROR_INVALID_CGI_PATH)
      return
  else:
    basename = path.until('/')
    pathInfo = path.substr(basename.len)
    scriptName = "/cgi-bin/" & basename
    requestURI = "/cgi-bin/" & path & request.url.search
    for dir in cgiDir:
      cmd = dir / basename
      if fileExists(cmd):
        myDir = dir
        break
  if not fileExists(cmd):
    handle.sendResult(ERROR_CGI_FILE_NOT_FOUND)
    return
  if basename in ["", ".", ".."] or basename.startsWith("~"):
    handle.sendResult(ERROR_INVALID_CGI_PATH)
    return
  var pipefd: array[0..1, cint] # child -> parent
  if pipe(pipefd) == -1:
    handle.sendResult(ERROR_FAIL_SETUP_CGI)
    return
  # Pipe the request body as stdin for POST.
  var pipefd_read: array[0..1, cint] # parent -> child
  if request.body.t notin {rbtNone, rbtCache}:
    if pipe(pipefd_read) == -1:
      handle.sendResult(ERROR_FAIL_SETUP_CGI)
      return
  let contentLen = request.body.contentLength()
  stdout.flushFile()
  stderr.flushFile()
  let pid = fork()
  if pid == -1:
    handle.sendResult(ERROR_FAIL_SETUP_CGI)
  elif pid == 0:
    discard close(pipefd[0]) # close read
    discard dup2(pipefd[1], 1) # dup stdout
    discard close(pipefd[1])
    if istream != nil: # cached input (file)
      discard dup2(istream.fd, 0) # dup stdin
      istream.sclose()
    elif request.body.t notin {rbtNone, rbtCache}:
      discard close(pipefd_read[1]) # close write
      if pipefd_read[0] != 0:
        discard dup2(pipefd_read[0], 0) # dup stdin
        discard close(pipefd_read[0])
    else:
      closeStdin()
    # we leave stderr open, so it can be seen in the browser console
    setupEnv(cmd, scriptName, pathInfo, requestURI, myDir, request, contentLen,
      prevURL, insecureSSLNoVerify)
    # reset SIGCHLD to the default handler. this is useful if the child process
    # expects SIGCHLD to be untouched. (e.g. git dies a horrible death with
    # SIGCHLD as SIG_IGN)
    signal(SIGCHLD, SIG_DFL)
    # close the parent handles
    for i in 0 ..< handleMap.len:
      if handleMap[i] != nil:
        discard close(cint(i))
    discard execl(cstring(cmd), cstring(basename), nil)
    let code = int(ERROR_FAILED_TO_EXECUTE_CGI_SCRIPT)
    stdout.write("Cha-Control: ConnectionError " & $code & " " &
      ($strerror(errno)).deleteChars({'\n', '\r'}))
    quit(1)
  else:
    discard close(pipefd[1]) # close write
    var ps: PosixStream = nil
    if request.body.t notin {rbtNone, rbtCache}:
      discard close(pipefd_read[0]) # close read
      ps = newPosixStream(pipefd_read[1])
    case request.body.t
    of rbtString:
      ps.write(request.body.s)
      ps.sclose()
    of rbtMultipart:
      let boundary = request.body.multipart.boundary
      for entry in request.body.multipart.entries:
        ps.writeEntry(entry, boundary)
      ps.writeEnd(boundary)
      ps.sclose()
    of rbtOutput:
      ostream = ps
    of rbtCache:
      istream.sclose()
    of rbtNone: discard
    handle.parser = HeaderParser(headers: newHeaders())
    handle.stream = newPosixStream(pipefd[0])

proc parseHeaders0(handle: InputHandle; buffer: LoaderBuffer): int =
  let parser = handle.parser
  var s = parser.lineBuffer
  let L = if buffer == nil: 1 else: buffer.len
  for i in 0 ..< L:
    template die =
      handle.parser = nil
      return -1
    let c = if buffer != nil:
      char(buffer.page[i])
    else:
      '\n'
    if parser.crSeen and c != '\n':
      die
    parser.crSeen = false
    if c == '\r':
      parser.crSeen = true
    elif c == '\n':
      if s == "":
        if parser.state == hpsBeforeLines:
          # body comes immediately, so we haven't had a chance to send result
          # yet.
          handle.sendResult(0)
        handle.sendStatus(parser.status)
        handle.sendHeaders(parser.headers)
        handle.parser = nil
        return i + 1 # +1 to skip \n
      case parser.state
      of hpsBeforeLines:
        case handle.handleFirstLine(s, parser.headers, parser.status)
        of crDone: parser.state = hpsControlDone
        of crContinue: parser.state = hpsAfterFirstLine
        of crError: die
      of hpsAfterFirstLine:
        case handle.handleControlLine(s, parser.headers, parser.status)
        of crDone: parser.state = hpsControlDone
        of crContinue: discard
        of crError: die
      of hpsControlDone:
        handle.handleLine(s, parser.headers)
      s = ""
    else:
      s &= c
  if s != "":
    parser.lineBuffer = s
  return L

proc parseHeaders*(handle: InputHandle; buffer: LoaderBuffer): int =
  try:
    return handle.parseHeaders0(buffer)
  except ErrorBrokenPipe:
    handle.parser = nil
    return -1

proc finishParse*(handle: InputHandle) =
  discard handle.parseHeaders(nil)
