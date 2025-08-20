{.push raises: [].}

import std/posix
import std/strutils

import io/chafile
import io/dynstream
import types/opt
import utils/myposix
import utils/sandbox
import utils/twtstr

export chafile
export dynstream
export myposix
export opt
export sandbox
export twtstr

export STDIN_FILENO, STDOUT_FILENO

proc die*(os: PosixStream; name: string; s = "") {.noreturn.} =
  var buf = "Cha-Control: ConnectionError " & name
  if s != "":
    buf &= ' ' & s
  buf &= '\n'
  discard os.writeDataLoop(buf)
  quit(1)

proc die*(name: string; s = "") {.noreturn.} =
  var buf = "Cha-Control: ConnectionError " & name
  if s != "":
    buf &= ' ' & s
  buf &= '\n'
  stdout.fwrite(buf)
  quit(1)

template orDie*(val: Opt[void]; os: PosixStream; name: string; s = "") =
  var x = val
  if x.isErr:
    os.die(name, s)

template orDie*[T](val: Opt[T]; os: PosixStream; name: string; s = ""): T =
  var x = val
  if x.isErr:
    os.die(name, s)
  move(x.get)

template orDie*(val: Opt[void]; name: string; s = "") =
  var x = val
  if x.isErr:
    die(name, s)

template orDie*[T](val: Opt[T]; name: string; s = ""): T =
  var x = val
  if x.isErr:
    die(name, s)
  move(x.get)

proc openSocket(os: PosixStream; host, port, resFail: string;
    res: var ptr AddrInfo): SocketHandle =
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
    os.die(resFail, $gai_strerror(err))
  let sock = socket(res.ai_family, res.ai_socktype, res.ai_protocol)
  if cint(sock) < 0:
    os.die("InternalError", "could not open socket")
  return sock

proc connectSocket(os: PosixStream; host, port, resFail, connFail: string;
    outIpv6: var bool): PosixStream =
  var res: ptr AddrInfo
  let sock = os.openSocket(host, port, resFail, res)
  let ps = newPosixStream(sock)
  if connect(sock, res.ai_addr, res.ai_addrlen) < 0:
    ps.sclose()
    os.die(connFail)
  outIpv6 = res.ai_family == AF_INET6
  freeAddrInfo(res)
  return ps

proc authenticateSocks5(os, ps: PosixStream; buf: array[2, uint8];
    user, pass: string) =
  if buf[0] != 5:
    os.die("ProxyInvalidResponse", "wrong socks version")
  case buf[1]
  of 0x00:
    discard # no auth
  of 0x02:
    if user.len > 255 or pass.len > 255:
      os.die("InternalError", "username or password too long")
    let sbuf = "\x01" & char(user.len) & user & char(pass.len) & pass
    if not ps.writeDataLoop(sbuf):
      os.die("ProxyAuthFail")
    var rbuf = array[2, uint8].default
    if not ps.readDataLoop(rbuf):
      os.die("ProxyInvalidResponse", "failed to read proxy response")
    if rbuf[0] != 1:
      os.die("ProxyInvalidResponse", "wrong auth version")
    if rbuf[1] != 0:
      os.die("ProxyAuthFail")
  of 0xFF:
    os.die("ProxyAuthFail proxy doesn't support our auth")
  else:
    os.die("ProxyInvalidResponse received wrong auth method " & $buf[1])

proc sendSocks5Domain(os, ps: PosixStream; host, port: string;
    outIpv6: var bool) =
  if host.len > 255:
    os.die("InternalError", "host too long to send to proxy")
  let dstaddr = "\x03" & char(host.len) & host
  let x = parseUInt16(port)
  if x.isErr:
    os.die("InternalError", "wrong port")
  let port = x.get
  let sbuf = "\x05\x01\x00" & dstaddr & char(port shr 8) & char(port and 0xFF)
  if not ps.writeDataLoop(sbuf):
    os.die("ProxyRefusedToConnect")
  var rbuf = array[4, uint8].default
  if not ps.readDataLoop(rbuf) or rbuf[0] != 5:
    os.die("ProxyInvalidResponse")
  if rbuf[1] != 0:
    os.die("ProxyRefusedToConnect")
  case rbuf[3]
  of 0x01:
    var ipv4 = array[4, uint8].default
    if not ps.readDataLoop(ipv4):
      os.die("ProxyInvalidResponse")
    outIpv6 = false
  of 0x03:
    var len = [0u8]
    if not ps.readDataLoop(len):
      os.die("ProxyInvalidResponse")
    var domain = newString(int(len[0]))
    if not ps.readDataLoop(domain):
      os.die("ProxyInvalidResponse")
    # we don't really know, so just assume it's ipv4.
    outIpv6 = false
  of 0x04:
    var ipv6 = array[16, uint8].default
    if not ps.readDataLoop(ipv6):
      os.die("ProxyInvalidResponse")
    outIpv6 = true
  else:
    os.die("ProxyInvalidResponse")
  var bndport = array[2, uint8].default
  if not ps.readDataLoop(bndport):
    os.die("ProxyInvalidResponse")

proc connectSocks5Socket(os: PosixStream; host, port, proxyHost, proxyPort,
    proxyUser, proxyPass: string; outIpv6: var bool): PosixStream =
  var dummy = false
  let ps = os.connectSocket(proxyHost, proxyPort, "FailedToResolveProxy",
    "ProxyRefusedToConnect", dummy)
  const NoAuth = "\x05\x01\x00"
  const WithAuth = "\x05\x02\x00\x02"
  if not ps.writeDataLoop(if proxyUser != "": NoAuth else: WithAuth):
    os.die("ProxyRefusedToConnect")
  var buf = array[2, uint8].default
  if not ps.readDataLoop(buf):
    os.die("ProxyInvalidResponse")
  os.authenticateSocks5(ps, buf, proxyUser, proxyPass)
  os.sendSocks5Domain(ps, host, port, outIpv6)
  return ps

proc connectHTTPSocket(os: PosixStream; host, port, proxyHost, proxyPort,
    proxyUser, proxyPass: string): PosixStream =
  var dummy = false
  let ps = os.connectSocket(proxyHost, proxyPort, "FailedToResolveProxy",
    "ProxyRefusedToConnect", dummy)
  var buf = "CONNECT " & host & ':' & port & " HTTP/1.1\r\n"
  buf &= "Host: " & host & ':' & port & "\r\n"
  if proxyUser != "" or proxyPass != "":
    let s = btoa(proxyUser & ' ' & proxyPass)
    buf &= "Proxy-Authorization: basic " & s & "\r\n"
  buf &= "\r\n"
  if not ps.writeDataLoop(buf):
    os.die("ProxyRefusedToConnect")
  var res = ""
  var crlfState = 0
  while crlfState < 4:
    var buf = [char(0)]
    let n = ps.readData(buf)
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
    os.die("ProxyRefusedToConnect")
  return ps

proc connectProxySocket(os: PosixStream; host, port, proxy: string;
    outIpv6: var bool): PosixStream =
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
    return os.connectSocks5Socket(host, port, proxyHost, proxyPort, user, pass,
      outIpv6)
  elif scheme == "http":
    return os.connectHTTPSocket(host, port, proxyHost, proxyPort, user, pass)
  os.die("InternalError", "only socks5 or http proxies are supported")

# Note: outIpv6 is not read; it just indicates whether the socket's
# address is IPv6.
# In case we connect to a proxy, only the target matters.
proc connectSocket*(os: PosixStream; host, port: string; outIpv6: var bool):
    PosixStream =
  if host.len == 0:
    os.die("InvalidURL", "missing hostname")
  var host = host
  if host.len > 0 and host[0] == '[' and host[^1] == ']':
    #TODO set outIpv6?
    host.delete(0..0)
    host.setLen(host.high)
  let proxy = getEnvEmpty("ALL_PROXY")
  if proxy != "":
    return os.connectProxySocket(host, port, proxy, outIpv6)
  return os.connectSocket(host, port, "FailedToResolveHost",
    "ConnectionRefused", outIpv6)

proc connectSocket*(os: PosixStream; host, port: string): PosixStream =
  var dummy = false
  return os.connectSocket(host, port, dummy)

{.pop.} # raises: []
