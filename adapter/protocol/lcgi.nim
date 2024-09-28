import std/options
import std/os
import std/posix
import std/strutils

import io/dynstream
import utils/twtstr

export dynstream
export twtstr

proc die*(os: PosixStream; s: string) =
  os.sendDataLoop("Cha-Control: ConnectionError " & s)
  quit(1)

proc openSocket(os: PosixStream; host, port, resFail, connFail: string;
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
  if err < 0:
    os.die(resFail & ' ' & $gai_strerror(err))
  let sock = socket(res.ai_family, res.ai_socktype, res.ai_protocol)
  freeaddrinfo(res)
  if cint(sock) < 0:
    os.die("InternalError could not open socket")
  return sock

proc connectSocket(os: PosixStream; host, port, resFail, connFail: string):
    PosixStream =
  var res: ptr AddrInfo
  let sock = os.openSocket(host, port, resFail, connFail, res)
  let ps = newPosixStream(sock)
  if connect(sock, res.ai_addr, res.ai_addrlen) < 0:
    ps.sclose()
    os.die(connFail)
  return ps

proc authenticateSocks5(os, ps: PosixStream; buf: array[2, uint8];
    user, pass: string) =
  if buf[0] != 5:
    os.die("ProxyInvalidResponse wrong socks version")
  case buf[1]
  of 0x00:
    discard # no auth
  of 0x02:
    if user.len > 255 or pass.len > 255:
      os.die("InternalError username or password too long")
    let sbuf = "\x01" & char(user.len) & user & char(pass.len) & pass
    ps.sendDataLoop(sbuf)
    var rbuf = default(array[2, uint8])
    ps.recvDataLoop(rbuf)
    if rbuf[0] != 1:
      os.die("ProxyInvalidResponse wrong auth version")
    if rbuf[1] != 0:
      os.die("ProxyAuthFail")
  of 0xFF:
    os.die("ProxyAuthFail proxy doesn't support our auth")
  else:
    os.die("ProxyInvalidResponse received wrong auth method " & $buf[1])

proc sendSocks5Domain(os, ps: PosixStream; host, port: string) =
  if host.len > 255:
    os.die("InternalError host too long to send to proxy")
  let dstaddr = "\x03" & char(host.len) & host
  let x = parseUInt16(port)
  if x.isNone:
    os.die("InternalError wrong port")
  let port = x.get
  let sbuf = "\x05\x01\x00" & dstaddr & char(port shr 8) & char(port and 0xFF)
  ps.sendDataLoop(sbuf)
  var rbuf = default(array[4, uint8])
  ps.recvDataLoop(rbuf)
  if rbuf[0] != 5:
    os.die("ProxyInvalidResponse")
  if rbuf[1] != 0:
    os.die("ProxyRefusedToConnect")
  case rbuf[3]
  of 0x01:
    var ipv4 = default(array[4, uint8])
    ps.recvDataLoop(ipv4)
  of 0x03:
    var len = [0u8]
    ps.recvDataLoop(len)
    var domain = newString(int(len[0]))
    ps.recvDataLoop(domain)
  of 0x04:
    var ipv6 = default(array[16, uint8])
    ps.recvDataLoop(ipv6)
  else:
    os.die("ProxyInvalidResponse")
  var bndport = default(array[2, uint8])
  ps.recvDataLoop(bndport)

proc connectSocks5Socket(os: PosixStream; host, port, proxyHost, proxyPort,
    proxyUser, proxyPass: string): PosixStream =
  let ps = os.connectSocket(proxyHost, proxyPort, "FailedToResolveProxy",
    "ProxyRefusedToConnect")
  const NoAuth = "\x05\x01\x00"
  const WithAuth = "\x05\x02\x00\x02"
  ps.sendDataLoop(if proxyUser != "": NoAuth else: WithAuth)
  var buf = default(array[2, uint8])
  ps.recvDataLoop(buf)
  os.authenticateSocks5(ps, buf, proxyUser, proxyPass)
  os.sendSocks5Domain(ps, host, port)
  return ps

proc connectProxySocket(os: PosixStream; host, port, proxy: string):
    PosixStream =
  let scheme = proxy.until(':')
  # We always use socks5h, actually.
  if scheme != "socks5" and scheme != "socks5h":
    os.die("Only socks5 proxy is supported")
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
  while i < proxy.len:
    let c = proxy[i]
    if c == ':':
      inc i
      break
    if c != '/':
      proxyHost &= c
    inc i
  let proxyPort = proxy.substr(i)
  return os.connectSocks5Socket(host, port, proxyHost, proxyPort, user, pass)

proc connectSocket*(os: PosixStream; host, port: string): PosixStream =
  let proxy = getEnv("ALL_PROXY")
  if proxy != "":
    return os.connectProxySocket(host, port, proxy)
  return os.connectSocket(host, port, "FailedToResolveHost",
    "ConnectionRefused")
