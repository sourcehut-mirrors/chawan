{.push raises: [].}

import std/posix

import io/chafile
import io/dynstream
import server/connectionerror
import types/opt
import utils/myposix
import utils/sandbox
import utils/twtstr

export chafile
export connectionerror
export dynstream
export myposix
export opt
export sandbox
export twtstr

export STDIN_FILENO, STDOUT_FILENO

type
  CGIError = object
    code*: ConnectionError
    s*: cstring

  CGIResult*[T] = Result[T, CGIError]

proc cgiDie*(code: ConnectionError; s: cstring = nil) {.noreturn.} =
  let stdout = cast[ChaFile](stdout)
  discard stdout.write("Cha-Control: ConnectionError " & $int(code))
  if s != nil and s[0] != '\0':
    discard stdout.write(' ')
    discard stdout.writecstr(s)
  discard stdout.writeLine()
  quit(1)

proc cgiDie*(code: ConnectionError; s: string) {.noreturn.} =
  let stdout = cast[ChaFile](stdout)
  discard stdout.write("Cha-Control: ConnectionError " & $int(code) & ' ')
  discard stdout.writeLine(s)
  quit(1)

proc cgiDie*(e: CGIError) {.noreturn.} =
  cgiDie(e.code, e.s)

proc orDie*(x: Opt[void]; name: ConnectionError; s: cstring = nil) =
  if x.isErr:
    cgiDie(name, s)

template orDie*[T](val: Opt[T]; name: ConnectionError; s: cstring = nil): T =
  var x = val
  if x.isErr:
    cgiDie(name, s)
  move(x.get)

template orDie*[T](val: CGIResult[T]): T =
  var x = val
  if x.isErr:
    cgiDie(x.error)
  move(x.get)

proc initCGIError*(code: ConnectionError; s: cstring = nil): CGIError =
  CGIError(code: code, s: s)

template errCGIError*(code: ConnectionError; s: cstring = nil): untyped =
  err(initCGIError(code, s))

proc openSocket(host, port: string; res: var ptr AddrInfo; nagle: bool):
    CGIResult[SocketHandle] =
  var err: cint
  for family in [AF_INET, AF_INET6, AF_UNSPEC]:
    var hints = AddrInfo(
      ai_family: family,
      ai_socktype: SOCK_STREAM,
      ai_protocol: IPPROTO_TCP
    )
    err = getaddrinfo(cstring(host), cstring(port), addr hints, res)
    if err == 0:
      break
  if err != 0:
    return err(initCGIError(ceFailedToResolveProxy, gai_strerror(err)))
  let sock = socket(res.ai_family, res.ai_socktype, res.ai_protocol)
  if cint(sock) < 0:
    return errCGIError(ceInternalError, "could not open socket")
  if not nagle:
    var value = cint(1)
    let valueLen = SockLen(sizeof(value))
    if setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, addr value, valueLen) < 0:
      return errCGIError(ceInternalError, "could not set TCP_NODELAY")
  ok(sock)

proc connectSimpleSocket(host, port: string; outIpv6: var bool; nagle: bool):
    CGIResult[PosixStream] =
  var res: ptr AddrInfo
  let sock = ?openSocket(host, port, res, nagle)
  let ps = newPosixStream(sock)
  if connect(sock, res.ai_addr, res.ai_addrlen) < 0:
    ps.sclose()
    return err(initCGIError(ceConnectionRefused))
  outIpv6 = res.ai_family == AF_INET6
  freeAddrInfo(res)
  ok(ps)

proc authenticateSocks5(ps: PosixStream; buf: array[2, uint8];
    user, pass: string): CGIResult[void] =
  if buf[0] != 5:
    return errCGIError(ceProxyInvalidResponse, "wrong socks version")
  case buf[1]
  of 0x00:
    discard # no auth
  of 0x02:
    if user.len > 255 or pass.len > 255:
      return errCGIError(ceInternalError, "username or password too long")
    let sbuf = "\x01" & char(user.len) & user & char(pass.len) & pass
    if ps.writeLoop(sbuf).isErr:
      return errCGIError(ceProxyAuthFail)
    var rbuf = array[2, uint8].default
    if ps.readLoop(rbuf).isErr:
      return errCGIError(ceProxyInvalidResponse,
        "failed to read proxy response")
    if rbuf[0] != 1:
      return errCGIError(ceProxyInvalidResponse, "wrong auth version")
    if rbuf[1] != 0:
      return errCGIError(ceProxyAuthFail)
  of 0xFF:
    return errCGIError(ceProxyAuthFail, "proxy doesn't support our auth")
  else:
    return errCGIError(ceProxyInvalidResponse, "received wrong auth method")
  ok()

proc sendSocks5Domain(ps: PosixStream; host, port: string; outIpv6: var bool):
    CGIResult[void] =
  if host.len > 255:
    return errCGIError(ceInternalError, "host too long to send to proxy")
  let dstaddr = "\x03" & char(host.len) & host
  let x = parseUInt16(port)
  if x.isErr:
    return errCGIError(ceInternalError, "wrong port")
  let port = x.get
  let sbuf = "\x05\x01\x00" & dstaddr & char(port shr 8) & char(port and 0xFF)
  if ps.writeLoop(sbuf).isErr:
    return errCGIError(ceProxyRefusedToConnect)
  var rbuf = array[4, uint8].default
  if ps.readLoop(rbuf).isErr or rbuf[0] != 5:
    return errCGIError(ceProxyInvalidResponse)
  if rbuf[1] != 0:
    return errCGIError(ceProxyRefusedToConnect)
  case rbuf[3]
  of 0x01:
    var ipv4 = array[4, uint8].default
    if ps.readLoop(ipv4).isErr:
      return errCGIError(ceProxyInvalidResponse)
    outIpv6 = false
  of 0x03:
    var len = [0u8]
    if ps.readLoop(len).isErr:
      return errCGIError(ceProxyInvalidResponse)
    var domain = newString(int(len[0]))
    if ps.readLoop(domain).isErr:
      return errCGIError(ceProxyInvalidResponse)
    # we don't really know, so just assume it's ipv4.
    outIpv6 = false
  of 0x04:
    var ipv6 = array[16, uint8].default
    if ps.readLoop(ipv6).isErr:
      return errCGIError(ceProxyInvalidResponse)
    outIpv6 = true
  else:
    return errCGIError(ceProxyInvalidResponse)
  var bndport = array[2, uint8].default
  if ps.readLoop(bndport).isErr:
    return errCGIError(ceProxyInvalidResponse)
  ok()

proc toProxyResult(res: CGIResult[PosixStream]): CGIResult[PosixStream] =
  if res.isErr:
    let e = res.error
    case e.code
    of ceFailedToResolveHost: return errCGIError(ceFailedToResolveProxy, e.s)
    of ceConnectionRefused: return errCGIError(ceProxyRefusedToConnect, e.s)
    else: discard
  res

proc connectSocks5Socket(host, port, proxyHost, proxyPort,
    proxyUser, proxyPass: string; outIpv6: var bool):
    CGIResult[PosixStream] =
  var dummy = false
  let ps = ?connectSimpleSocket(proxyHost, proxyPort, dummy, nagle = true)
    .toProxyResult()
  const NoAuth = "\x05\x01\x00"
  const WithAuth = "\x05\x02\x00\x02"
  if ps.writeLoop(if proxyUser == "": NoAuth else: WithAuth).isErr:
    return errCGIError(ceProxyRefusedToConnect)
  var buf = array[2, uint8].default
  if ps.readLoop(buf).isErr:
    return errCGIError(ceProxyInvalidResponse)
  ?ps.authenticateSocks5(buf, proxyUser, proxyPass)
  ?ps.sendSocks5Domain(host, port, outIpv6)
  ok(ps)

proc connectHTTPSocket(host, port, proxyHost, proxyPort,
    proxyUser, proxyPass: string): CGIResult[PosixStream] =
  var dummy = false
  let ps = ?connectSimpleSocket(proxyHost, proxyPort, dummy, nagle = true)
    .toProxyResult()
  var buf = "CONNECT " & host & ':' & port & " HTTP/1.1\r\n"
  buf &= "Host: " & host & ':' & port & "\r\n"
  if proxyUser != "" or proxyPass != "":
    let s = btoa(proxyUser & ':' & proxyPass)
    buf &= "Proxy-Authorization: Basic " & s & "\r\n"
  buf &= "\r\n"
  if ps.writeLoop(buf).isErr:
    return errCGIError(ceProxyRefusedToConnect)
  var res = ""
  var crlfState = 0
  while crlfState < 4:
    var buf = [char(0)]
    let n = ps.read(buf)
    if n <= 0:
      break
    let expected = ['\r', '\n'][crlfState mod 2]
    if buf[0] == expected:
      inc crlfState
    else:
      crlfState = 0
    res &= buf[0]
  if not res.startsWithIgnoreCase("HTTP/1.1 200") and
      not res.startsWithIgnoreCase("HTTP/1.0 200"):
    return errCGIError(ceProxyRefusedToConnect)
  ok(ps)

proc connectProxySocket(host, port, proxy: string; outIpv6: var bool):
    CGIResult[PosixStream] =
  let scheme = proxy.until(':')
  var i = scheme.len + 1
  while i < proxy.len and proxy[i] == '/':
    inc i
  let authi = proxy.find('@', i)
  var user = ""
  var pass = ""
  if authi != -1:
    let auth = proxy.substr(i, authi - 1)
    user = auth.until(':')
    pass = auth.after(':')
    i = authi + 1
  var proxyHost = ""
  if i < proxy.len and proxy[i] == '[':
    inc i
    while i < proxy.len and proxy[i] != ']':
      proxyHost &= proxy[i]
      inc i
    inc i
  else:
    while i < proxy.len and proxy[i] notin {':', '/'}:
      proxyHost &= proxy[i]
      inc i
  inc i
  var proxyPort = ""
  while i < proxy.len and proxy[i] in AsciiDigit:
    proxyPort &= proxy[i]
    inc i
  if scheme == "socks5" or scheme == "socks5h":
    # We always use socks5h, actually.
    return connectSocks5Socket(host, port, proxyHost, proxyPort, user, pass,
      outIpv6)
  elif scheme == "http":
    return connectHTTPSocket(host, port, proxyHost, proxyPort, user, pass)
  else:
    return errCGIError(ceInternalError,
      "only socks5 or http proxies are supported")

# Note: outIpv6 is not read; it just indicates whether the socket's
# address is IPv6.
# In case we connect to a proxy, only the target matters.
proc connectSocket*(host, port: string; outIpv6: var bool):
    CGIResult[PosixStream] =
  if host.len == 0:
    return errCGIError(ceInvalidURL, "missing hostname")
  var host = host
  if host.len > 0 and host[0] == '[' and host[^1] == ']':
    #TODO set outIpv6?
    host.delete(0..0)
    host.setLen(host.high)
  let proxy = getEnvEmpty("ALL_PROXY")
  if proxy != "":
    return connectProxySocket(host, port, proxy, outIpv6)
  return connectSimpleSocket(host, port, outIpv6, nagle = false)

proc connectSocket*(host, port: string): CGIResult[PosixStream] =
  var dummy = false
  return connectSocket(host, port, dummy)

{.pop.} # raises: []
