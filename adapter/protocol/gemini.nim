# See ssl.nim for the entry point.

{.push raises: [].}

import std/posix
import std/strutils

import lcgi_ssl

proc sdie(s: string) =
  let stdout = cast[ChaFile](stdout)
  if stdout.write("Cha-Control: ConnectionError 5 " & s & ": ").isOk:
    ERR_print_errors_fp(stdout)
  quit(1)

proc openKnownHosts(os: PosixStream): (AChaFile, string) =
  var path = getEnvEmpty("GMIFETCH_KNOWN_HOSTS")
  if path == "":
    let ourDir = getEnvEmpty("CHA_DIR")
    if ourDir == "":
      cgiDie(ceInternalError, "config dir missing")
    path = ourDir & '/' & "gemini_known_hosts"
  discard mkdir(cstring(path.untilLast('/')), 0o700)
  let f = chafile.afopen(path, "a+")
    .orDie(ceInternalError, "error opening known hosts file")
  return (f, path)

proc readKnownHosts(f, tmp: AChaFile; buf, host: string): Opt[void] =
  var line: string
  while ?f.readLine(line):
    let j = line.find(' ')
    if host.len == j and line.startsWith(host):
      continue # delete this entry
    ?tmp.writeLine(line)
  ?tmp.writeLine(buf)
  ok()

proc readPost(os: PosixStream; query: var string; host, knownHostsPath: string;
    knownHosts: var AChaFile; tmpEntry: var string) =
  let s = newPosixStream(STDIN_FILENO).readAll()
  if (var i = s.find("input="); i != -1):
    i += "input=".len
    query = s.toOpenArray(i, s.high).percentDecode()
  elif (var i = s.find("trust_cert="); i != -1):
    i += "trust_cert=".len
    let t = s.until('&', i)
    if t in ["always", "yes", "no", "once"]:
      i = s.find("entry=", i)
      if i == -1:
        cgiDie(ceInternalError, "missing entry field in POST")
      i += "entry=".len
      var buf = ""
      for i in i ..< s.len:
        if s[i] == '+':
          buf &= ' '
        else:
          buf &= s[i]
      buf = buf.percentDecode()
      if t == "once" or t == "no":
        tmpEntry = buf
      else:
        let tmpPath = knownHostsPath & '~'
        let ps = newPosixStream(tmpPath, O_CREAT or O_WRONLY or O_TRUNC, 0o600)
        if ps == nil:
          cgiDie(ceInternalError, "failed to open temp file")
        let tmpFile = ps.afdopen("w")
          .orDie(ceInternalError, "failed to open temp file")
        knownHosts.readKnownHosts(tmpFile, buf, host)
          .orDie(ceInternalError, "failed to read known hosts")
        chafile.rename(tmpPath, knownHostsPath)
          .orDie(ceInternalError, "failed to move temporary file")
        knownHosts = chafile.afopen(knownHostsPath, "r")
          .orDie(ceInternalError, "failed to reopen known_hosts")
    else:
      cgiDie(ceInternalError, "invalid POST: wrong trust_cert")
  else:
    cgiDie(ceInternalError, "invalid POST: no input or trust_cert")

type CheckCertResult = enum
  ccrNotFound, ccrNewExpiration, ccrFoundInvalid, ccrFoundValid

proc findHost(f: AChaFile; host: string; line: var string): Opt[bool] =
  var found = false
  ?f.seek(0)
  while not found and ?f.readLine(line):
    found = line.until(' ') == host
  ok(found)

proc checkCert0(os: PosixStream; theirDigest, host: string;
    storedDigest: var string; theirTime: var Time; knownHosts: AChaFile;
    tmpEntry: string): CheckCertResult =
  var line = tmpEntry
  var found = line.until(' ') == host
  if not found:
    found = knownHosts.findHost(host, line)
      .orDie(ceInternalError, "failed to read known hosts")
  if not found:
    return ccrNotFound
  let ss = line.split(' ')
  if ss.len < 3:
    cgiDie(ceInternalError, "wrong line in known_hosts file")
  if ss[1] != "sha256":
    cgiDie(ceInternalError, "unsupported digest format in known_hosts file")
  storedDigest = ss[2]
  if storedDigest != theirDigest:
    return ccrFoundInvalid
  if ss.len > 3:
    if n := parseUInt64(ss[3], allowSign = false):
      if Time(n) == theirTime:
        return ccrFoundValid
    else:
      cgiDie(ceInternalError, "invalid time in known_hosts file")
  ccrNewExpiration

proc hashBuf(ibuf: openArray[uint8]): string =
  const HexTable = "0123456789ABCDEF"
  var len2: cuint = 0
  var buf = newSeq[uint8](EVP_MAX_MD_SIZE)
  let mdctx = EVP_MD_CTX_new()
  if mdctx == nil:
    sdie("failed to initialize MD_CTX")
  if EVP_DigestInit_ex(mdctx, EVP_sha256(), nil) == 0:
    sdie("failed to initialize sha256")
  if EVP_DigestUpdate(mdctx, unsafeAddr ibuf[0], cuint(ibuf.len)) == 0:
    sdie("failed to update digest")
  if EVP_DigestFinal_ex(mdctx, addr buf[0], len2) == 0:
    sdie("failed to finalize digest")
  EVP_MD_CTX_free(mdctx);
  # hex encode buf
  result = ""
  for i in 0 ..< int(len2):
    if i != 0:
      result &= ':'
    let u = buf[i]
    result &= HexTable[(u shr 4) and 0xF]
    result &= HexTable[u and 0xF]

proc checkCert(os: PosixStream; ssl: ptr SSL; host, port: string;
    knownHosts: AChaFile; storedDigest, theirDigest: var string;
    theirTime: var Time; tmpEntry: string): CheckCertResult =
  let cert = SSL_get_peer_certificate(ssl)
  if cert == nil:
    sdie("failed to get peer certificate")
  let pkey = X509_get0_pubkey(cert)
  if pkey == nil:
    sdie("failed to decode public key")
  var pubkeyBuf {.noinit.}: array[16384, uint8]
  let len = i2d_PUBKEY(pkey, nil);
  if len * 3 > pubkeyBuf.len:
    cgiDie(ceInternalError, "pubkey too long")
  var r = addr pubkeyBuf[0]
  if i2d_PUBKEY(pkey, addr r) != len:
    cgiDie(ceInternalError, "wat")
  theirDigest = pubkeyBuf.toOpenArray(0, len - 1).hashBuf()
  let notAfter = X509_get0_notAfter(cert)
  var theirTm: Tm
  if ASN1_TIME_to_tm(notAfter, addr theirTm) == 0:
    sdie("Failed to parse time");
  if getEnvEmpty("CHA_INSECURE_SSL_NO_VERIFY") != "1":
    if X509_cmp_current_time(X509_get0_notBefore(cert)) >= 0 or
        X509_cmp_current_time(notAfter) <= 0:
      cgiDie(ceInvalidResponse, "received an expired certificate");
  theirTime = mktime(theirTm)
  X509_free(cert)
  return os.checkCert0(theirDigest, host, storedDigest, theirTime, knownHosts,
    tmpEntry)

proc readResponse(os: PosixStream; ssl: ptr SSL; reqBuf: string) =
  var buffer = newString(4096)
  var n = 0
  while n < buffer.len:
    let m = SSL_read(ssl, addr buffer[n], cint(buffer.len - n))
    if m <= 0:
      break
    n += m
  let status0 = buffer[0]
  let status1 = buffer[1]
  if status0 notin AsciiDigit or status1 notin AsciiDigit:
    cgiDie(ceInvalidResponse, "invalid status code")
  while n < 1024 + 3: # max meta len is 1024
    let m = SSL_read(ssl, addr buffer[n], cint(buffer.len - n))
    if m <= 0:
      break
    n += m
  let i = buffer.find("\r\n")
  if i == -1:
    cgiDie(ceInvalidResponse, "invalid status line")
  var meta = buffer.substr(3, i - 1)
  if '\n' in meta:
    cgiDie(ceInvalidResponse, "invalid status line")
  case status0
  of '1': # input
    # META is the prompt.
    let it = if status1 == '1': "password" else: "search"
    discard os.writeDataLoop("""Content-Type: text/html

<!DOCTYPE html>
<title>Input required</title>
<base href='""" & reqBuf.htmlEscape() & """'>
<h1>Input required</h1>
<p>
""" & meta.htmlEscape() & """
<p>
<form method=POST><input type='""" & it & """' name='input'></form>
""")
  of '2': # success
    # META is the content type.
    if meta == "":
      meta = "text/gemini"
    discard os.writeDataLoop("Content-Type: " & meta & "\n\n")
    discard os.writeDataLoop(buffer.toOpenArray(i + 2, n - 1))
    while true:
      let n = SSL_read(ssl, addr buffer[0], cint(buffer.len))
      if n == 0:
        break
      if not os.writeDataLoop(buffer.toOpenArray(0, int(n) - 1)):
        break
  of '3': # redirect
    # META is the redirection URL.
    # Using an HTTP permanent redirect would send another POST and
    # break redirection after form submission (search), so we send
    # See Other.
    discard os.writeDataLoop("Status: 303\nLocation: " & meta & "\n\n")
  of '4': # temporary failure
    # META is additional information.
    let tmp = case status1
    of '1': "Server unavailable"
    of '2': "CGI error"
    of '3': "Proxy error"
    of '4': "Slow down!"
    else: "Temporary failure" # no additional information provided in the code
    discard os.writeDataLoop("""Content-Type: text/html

<!DOCTYPE html>
<title>Temporary failure</title>
<h1>""" & tmp & """</h1>
<p>
""" & meta.htmlEscape())
  of '5': # permanent failure
    # META is additional information.
    let tmp = case status1
    of '1': "Not found"
    of '2': "Gone"
    of '3': "Proxy request refused"
    of '4': "Bad request"
    else: "Permanent failure"
    discard os.writeDataLoop("""Content-Type: text/html

<!DOCTYPE html>
<title>Permanent failure</title>
<h1>""" & tmp & """</h1>
<p>
""" & meta.htmlEscape())
  of '6': # certificate failure
    # META is additional information.
    let tmp = case status1
    of '1': "Certificate not authorized"
    of '2': "Certificate not valid"
    else: "Certificate failure"
    discard os.writeDataLoop("""Content-Type: text/html

<!DOCTYPE html>
<title>Certificate failure</title>
<h1>""" & tmp & """</h1>
<p>
""" & meta.htmlEscape())
  else:
    cgiDie(ceInvalidResponse, "Wrong status code")

proc main*() =
  let os = newPosixStream(STDOUT_FILENO)
  let host = getEnvEmpty("MAPPED_URI_HOST")
  var (knownHosts, knownHostsPath) = os.openKnownHosts()
  let port = getEnvEmpty("MAPPED_URI_PORT", "1965")
  let path = getEnvEmpty("MAPPED_URI_PATH", "/")
  var reqBuf = "gemini://" & host & path
  var query = getEnvEmpty("MAPPED_URI_QUERY")
  var tmpEntry = "" # for accepting a self signed cert "once"
  if getEnvEmpty("REQUEST_METHOD") == "POST":
    os.readPost(query, host, knownHostsPath, knownHosts, tmpEntry)
  if query != "":
    reqBuf &= '?' & query
  reqBuf &= "\r\n"
  let ssl = connectSSLSocket(host, port, useDefaultCA = false).orDie()
  var storedDigest: string
  var theirDigest: string
  var theirTime: Time
  let res = os.checkCert(ssl, host, port, knownHosts, storedDigest, theirDigest,
    theirTime, tmpEntry)
  enterNetworkSandbox()
  case res
  of ccrFoundValid:
    discard SSL_write(ssl, cstring(reqBuf), cint(reqBuf.len))
    os.readResponse(ssl, reqBuf)
  of ccrFoundInvalid:
    discard os.writeDataLoop("""
Content-Type: text/html

<!DOCTYPE html>
<title>Invalid certificate</title>
<h1>Invalid certificate</h1>
<p>
The certificate received from the server does not match the
stored certificate (expected """ & storedDigest & """, but got
""" & theirDigest & """). Somebody may be tampering with your
connection.
<p>
If you are sure that this is not a man-in-the-middle attack,
please remove this host from """ & knownHostsPath & """.
""")
  of ccrNotFound:
    discard os.writeDataLoop("""
Content-Type: text/html

<!DOCTYPE html>
<title>Unknown certificate</title>
<h1>Unknown certificate</h1>
<p>
The hostname of the server you are visiting could not be found
in your list of known hosts (""" & knownHostsPath & """).
<p>
The server has sent us a certificate with the following
fingerprint:
<pre>""" & theirDigest & """</pre>
<p>
Trust it?
<form method=POST>
<input type=submit name=trust_cert value=always>
<input type=submit name=trust_cert value=once>
<input type=hidden name=entry value='""" &
    host & " sha256 " & theirDigest & " " & $uint64(theirTime) & """'>
</form>
""")
  of ccrNewExpiration:
    discard os.writeDataLoop("""
Content-Type: text/html

<!DOCTYPE html>
<title>Certificated date changed</title>
<h1>Certificated date changed</h1>
<p>
The received certificate's date did not match the date in your
list of known hosts (""" & knownHostsPath & """).
<p>
The new expiration date is: """ & ($ctime(theirTime)).strip() & """.
<p>
Update it?
<form method=POST>
<input type=submit name=trust_cert value=yes>
<input type=submit name=trust_cert value=no>
<input type=hidden name=entry value='""" &
    host & " sha256 " & theirDigest & " " & $uint64(theirTime) & """'>
</form>
""")
  closeSSLSocket(ssl)

{.pop.} # raises: []
