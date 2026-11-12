{.push raises: [].}

import std/posix

import io/chafile
import io/dynstream
import server/connectionerror
import utils/chaos
import utils/cowstr
import utils/opt
import utils/sandbox
import utils/twtstr

export chafile
export chaos
export connectionerror
export cowstr
export dynstream
export opt
export sandbox
export twtstr

type
  CGIError = object
    code*: ConnectionError
    s*: cstring

  CGIResult*[T] = Result[T, CGIError]

proc cgiDie*(code: ConnectionError; s: cstring = nil) {.noreturn.} =
  discard chaStdout.write(initStrM("Cha-Control: ConnectionError ", int(code)))
  if s != nil and s[0] != '\0':
    discard chaStdout.write(' ')
    discard chaStdout.writecstr(s)
  discard chaStdout.writeLine()
  quit(1)

proc cgiDie*(code: ConnectionError; s: Str) {.noreturn.} =
  discard chaStdout.write(initStrM("Cha-Control: ConnectionError ", int(code),
    ' '))
  discard chaStdout.writeLine(s)
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

proc parseDimensions*(s: Str; allowZero: bool): tuple[w, h: int] =
  let xi = s.find('x')
  if xi < 0:
    cgiDie(ceInternalError, "wrong dimensions")
  let (w, h) = parseDimensions(s)
  if w < 0 or h < 0 or not allowZero and (w == 0 or h == 0):
    cgiDie(ceInternalError, "wrong dimensions")
  return (w, h)

proc parseDimensionsC*(s: Str; allowZero: bool): tuple[w, h: cint] =
  let res = parseDimensions(s, allowZero)
  if res.w > int(cint.high) or res.h > int(cint.high):
    cgiDie(ceInternalError, "wrong dimensions")
  return (cint(res.w), cint(res.h))

proc initCGIError*(code: ConnectionError; s: cstring = nil): CGIError =
  CGIError(code: code, s: s)

template errCGIError*(code: ConnectionError; s: cstring = nil): untyped =
  err(initCGIError(code, s))

proc openSocket(host, port: Str; res: var ptr AddrInfo; family: var cint;
    nagle: bool): CGIResult[SocketHandle] =
  var hints = AddrInfo(
    ai_family: family,
    ai_socktype: SOCK_STREAM,
    ai_protocol: IPPROTO_TCP
  )
  var code = getaddrinfo(host.toCString(), port.toCString(), addr hints, res)
  if code != 0 and family == AF_INET:
    family = AF_INET6
    hints.ai_family = family
    code = getaddrinfo(host.toCString(), port.toCString(), addr hints, res)
  if code != 0:
    return err(initCGIError(ceFailedToResolveProxy, gai_strerror(code)))
  let sock = socket(res.ai_family, res.ai_socktype, res.ai_protocol)
  if cint(sock) < 0:
    return errCGIError(ceInternalError, "could not open socket")
  if not nagle:
    var value = cint(1)
    let valueLen = SockLen(sizeof(value))
    if setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, addr value, valueLen) < 0:
      return errCGIError(ceInternalError, "could not set TCP_NODELAY")
  ok(sock)

proc connectSimpleSocket(host, port: Str; outIp: var Str; nagle: bool):
    CGIResult[PosixStream] =
  var res: ptr AddrInfo
  var family = AF_INET
  var ps: PosixStream
  while true:
    let sock = ?openSocket(host, port, res, family, nagle)
    ps = newPosixStream(sock)
    if connect(sock, res.ai_addr, res.ai_addrlen) < 0:
      ps.sclose()
      if family == AF_INET:
        family = AF_INET6
        continue # retry
      return err(initCGIError(ceConnectionRefused))
    break # success
  var ip = initGrowbuf()
  if res.ai_family == AF_INET:
    ip &= '4'
  elif res.ai_family == AF_INET6:
    ip &= '6'
  if ip.len > 0:
    var host {.noinit.}: array[1025, char]
    if getnameinfo(res.ai_addr, res.ai_addrlen, cast[cstring](addr host),
        SockLen(1025), nil, 0, NI_NUMERICHOST) < 0:
      return err(initCGIError(ceFailedToResolveHost))
    ip.addCString(cast[cstring](addr host))
  outIp = ip.toStr()
  freeAddrInfo(res)
  ok(ps)

proc authenticateSocks5(ps: PosixStream; buf: array[2, uint8];
    user, pass: Str): CGIResult[void] =
  if buf[0] != 5:
    return errCGIError(ceProxyInvalidResponse, "wrong socks version")
  case buf[1]
  of 0x00:
    discard # no auth
  of 0x02:
    if user.len > 255 or pass.len > 255:
      return errCGIError(ceInternalError, "username or password too long")
    let sbuf = initGrowbufM("\x01", char(user.len), user, char(pass.len), pass)
    if ps.writeLoop(sbuf.toOpenArray()).isErr:
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

proc sendSocks5Domain(ps: PosixStream; host, port: Str; outIp: var Str):
    CGIResult[void] =
  if host.len > 255:
    return errCGIError(ceInternalError, "host too long to send to proxy")
  let x = parseUInt16(port.toOpenArray())
  if x.isErr:
    return errCGIError(ceInternalError, "wrong port")
  let port = x.get
  block:
    let sbuf = initGrowbufM(str("\x05\x01\x00\x03"), char(host.len), host,
      char(port shr 8), char(port and 0xFF))
    if ps.writeLoop(sbuf.toOpenArray()).isErr:
      return errCGIError(ceProxyRefusedToConnect)
  var rbuf = array[4, uint8].default
  if ps.readLoop(rbuf).isErr or rbuf[0] != 5:
    return errCGIError(ceProxyInvalidResponse)
  if rbuf[1] != 0:
    return errCGIError(ceProxyRefusedToConnect)
  var ip = initGrowbuf()
  case rbuf[3]
  of 0x01:
    var ipv4 = array[4, uint8].default
    if ps.readLoop(ipv4).isErr:
      return errCGIError(ceProxyInvalidResponse)
    ip &= '4'
    for i, num in ipv4:
      if i > 0:
        ip &= '.'
      ip &= num
  of 0x03:
    var len = [0u8]
    if ps.readLoop(len).isErr:
      return errCGIError(ceProxyInvalidResponse)
    var domain = newString(int(len[0]))
    if ps.readLoop(domain).isErr:
      return errCGIError(ceProxyInvalidResponse)
  of 0x04:
    var ipv6 = array[16, uint8].default
    if ps.readLoop(ipv6).isErr:
      return errCGIError(ceProxyInvalidResponse)
    ip &= '6'
    for i in 0 ..< 8:
      if i > 0:
        ip &= ':'
      ip.addHex(char(ipv6[i * 2]))
      ip.addHex(char(ipv6[i * 2 + 1]))
  else:
    return errCGIError(ceProxyInvalidResponse)
  outIp = ip.toStr()
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

proc connectSocks5Socket(host, port, proxyHost, proxyPort, proxyUser,
    proxyPass: Str; outIp: var Str): CGIResult[PosixStream] =
  var dummy = str("")
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
  ?ps.sendSocks5Domain(host, port, outIp)
  ok(ps)

proc connectHTTPSocket(host, port, proxyHost, proxyPort,
    proxyUser, proxyPass: Str): CGIResult[PosixStream] =
  var dummy: Str
  let ps = ?connectSimpleSocket(proxyHost, proxyPort, dummy, nagle = true)
    .toProxyResult()
  var buf = initGrowbufM("CONNECT ", host, ':', port, " HTTP/1.1\r\n",
    "Host: ", host, ':', port, "\r\n")
  if proxyUser != "" or proxyPass != "":
    buf &= "Proxy-Authorization: Basic "
    buf.addBtoa(initGrowbufM(proxyUser, ':', proxyPass).toOpenArray())
    buf &= "\r\n"
  buf &= "\r\n"
  if ps.writeLoop(buf.toOpenArray()).isErr:
    return errCGIError(ceProxyRefusedToConnect)
  var res = initGrowbuf()
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

proc connectProxySocket(host, port, proxy: Str; outIp: var Str):
    CGIResult[PosixStream] =
  let scheme = proxy.until(':')
  var i = scheme.len + 1
  while i < proxy.len and proxy[i] == '/':
    inc i
  let authi = proxy.find('@', i)
  var user = str("")
  var pass = str("")
  if authi >= 0:
    let auth = proxy.substr(i, authi - 1)
    user = auth.until(':')
    pass = auth.after(':')
    i = authi + 1
  var proxyHost = initGrowbuf()
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
  var proxyPort = initGrowbuf()
  while i < proxy.len and proxy[i] in AsciiDigit:
    proxyPort &= proxy[i]
    inc i
  if scheme == "socks5" or scheme == "socks5h":
    # We always use socks5h, actually.
    return connectSocks5Socket(host, port, proxyHost.toStr(),
      proxyPort.toStr(), user, pass, outIp)
  elif scheme == "http":
    return connectHTTPSocket(host, port, proxyHost.toStr(), proxyPort.toStr(),
      user, pass)
  else:
    return errCGIError(ceInternalError,
      "only socks5 or http proxies are supported")

type IpClass* = enum
  icPublic, ic410, ic4172, ic4192, ic6fd, ic4Loopback, ic6Loopback

proc getIpClass*(ip: Str): IpClass =
  if ip.startsWith("4127.") or ip == "40.0.0.0":
    return ic4Loopback
  if ip.startsWith("410."):
    return ic410
  if ip.len > 7 and ip[7] == '.':
    # 172.1[6789].x.x or 172.2x.x.x or 172.3[01].x.x
    if ip.startsWith("4172.1") and ip[6] in '6'..'9' or
        ip.startsWith("4172.2") or
        ip.startsWith("4172.3") and ip[6] in '0'..'1':
      return ic4172
  if ip.startsWith("4192.168."):
    return ic4192
  if ip.startsWith("6fd"):
    return ic6fd
  if ip == "6::1" or ip == "60000:0000:0000:0000:0000:0000:0000:0001":
    return ic6Loopback
  icPublic

# Note: outIpv6 is not read; it just indicates whether the socket's
# address is IPv6.
# In case we connect to a proxy, only the target matters.
proc connectSocket*(host, port: Str; outIp: var Str): CGIResult[PosixStream] =
  if host.len == 0:
    return errCGIError(ceInvalidURL, "missing hostname")
  var host = host
  if host.len > 0 and host[0] == '[' and host[^1] == ']':
    host.delete(0..0)
    host.setLen(host.high)
  let proxy = getEnvEmpty("ALL_PROXY")
  var ip: Str
  let res0 = if proxy != "":
    connectProxySocket(host, port, proxy, ip)
  else:
    connectSimpleSocket(host, port, ip, nagle = false)
  let res = ?res0
  if ip.len > 0:
    let originAddr = getEnvEmpty("CHA_ORIGIN_ADDR")
    if originAddr.len > 0:
      let originClass = getIpClass(originAddr)
      let ourClass = getIpClass(ip)
      if originClass == icPublic and ourClass > icPublic or
          originClass < ic4Loopback and ourClass >= ic4Loopback:
        return errCGIError(ceDisallowedSubnet)
  outIp = move(ip)
  ok(res)

proc connectSocket*(host, port: Str): CGIResult[PosixStream] =
  var dummy: Str
  return connectSocket(host, port, dummy)

proc cgiAuthorization*(): tuple[user, pass: Str] =
  let auth = getEnvEmpty("HTTP_AUTHORIZATION")
  if auth.startsWithIgnoreCase("Basic "):
    var val: Str
    if val.atob(auth.toOpenArray("Basic ".len, auth.high)).isOk:
      return (val.until(':'), val.after(':'))
  return (str(""), str(""))

{.pop.} # raises: []
