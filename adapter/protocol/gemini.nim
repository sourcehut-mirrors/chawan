import std/options
import std/os
import std/posix
import std/strutils

import lcgi_ssl

proc sdie(s: string) =
  stdout.write("Cha-Control: ConnectionError 5 " & s & ": ")
  ERR_print_errors_fp(stdout)
  stdout.flushFile()
  quit(1)

proc fopen(filename, mode: cstring): pointer {.importc, nodecl.}
proc openKnownHosts(os: PosixStream): (File, string) =
  var path = getEnv("GMIFETCH_KNOWN_HOSTS")
  if path == "":
    let ourDir = getEnv("CHA_CONFIG_DIR")
    if ourDir == "":
      os.die("InternalError", "config dir missing")
    path = ourDir & '/' & "gemini_known_hosts"
  createDir(path.beforeLast('/'))
  let f = cast[File](fopen(cstring(path), "a+"))
  if f == nil:
    os.die("InternalError", "error opening open known hosts file")
  return (f, path)

proc readPost(os: PosixStream; query: var string; host, knownHostsPath: string;
    knownHosts: var File; tmpEntry: var string) =
  let s = newPosixStream(STDIN_FILENO).recvAll()
  if (var i = s.find("input="); i != -1):
    i += "input=".len
    query = s.toOpenArray(i, s.high).percentDecode()
  elif (var i = s.find("trust_cert="); i != -1):
    i += "trust_cert=".len
    let t = s.until('&', i)
    if t in ["always", "yes", "no", "once"]:
      i = s.find("entry=", i)
      if i == -1:
        os.die("InternalError", "missing entry field in POST")
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
        var knownHostsTmp: File
        let knownHostsTmpPath = knownHostsPath & '~'
        if not knownHostsTmp.open(knownHostsTmpPath, fmWrite):
          os.die("InternalError", "failed to open temp file")
        var line: string
        while knownHosts.readLine(line):
          let j = line.find(' ')
          if host.len == j and line.startsWith(host):
            continue # delete this entry
          knownHostsTmp.writeLine(line)
        knownHostsTmp.writeLine(buf)
        knownHostsTmp.close()
        knownHosts.close()
        try:
          moveFile(knownHostsTmpPath, knownHostsPath)
        except IOError:
          os.die("InternalError failed to move tmp file")
        if not knownHosts.open(knownHostsPath, fmRead):
          os.die("InternalError", "failed to reopen known_hosts")
    else:
      os.die("InternalError invalid POST: wrong trust_cert")
  else:
    os.die("InternalError invalid POST: no input or trust_cert")

type CheckCertResult = enum
  ccrNotFound, ccrNewExpiration, ccrFoundInvalid, ccrFoundValid

proc checkCert(os: PosixStream; theirDigest, host: string;
    storedDigest: var string; theirTime: var Time; knownHosts: File;
    tmpEntry: string): CheckCertResult =
  var line = tmpEntry
  var found = line.until(' ') == host
  while not found and knownHosts.readLine(line):
    found = line.until(' ') == host
  if not found:
    return ccrNotFound
  let ss = line.split(' ')
  if ss.len < 3:
    os.die("InternalError", "wrong line in known_hosts file")
  if ss[1] != "sha256":
    os.die("InternalError", "unsupported digest format in known_hosts file")
  storedDigest = ss[2]
  if storedDigest != theirDigest:
    return ccrFoundInvalid
  if ss.len > 3:
    if (let x = parseUInt64(ss[3], allowSign = false); x.isSome):
      if Time(x.get) == theirTime:
        return ccrFoundValid
    else:
      os.die("InternalError", "invalid time in known_hosts file")
  return ccrNewExpiration

proc hashBuf(ibuf: openArray[uint8]): string =
  const HexTable = "0123456789ABCDEF"
  var len2: cuint = 0
  var buf = newSeq[char](EVP_MAX_MD_SIZE)
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
    let u = uint8(buf[i])
    result &= HexTable[(u shr 4) and 0xF]
    result &= HexTable[u and 0xF]

proc connect(os: PosixStream; ssl: ptr SSL; host, port: string;
    knownHosts: File; storedDigest, theirDigest: var string;
    theirTime: var Time; tmpEntry: string): CheckCertResult =
  let hostname = host & ':' & port
  discard SSL_set1_host(ssl, cstring(hostname))
  if SSL_connect(ssl) <= 0:
    sdie("failed to connect")
  if SSL_do_handshake(ssl) <= 0:
    sdie("failed handshake")
  let cert = SSL_get_peer_certificate(ssl)
  if cert == nil:
    sdie("failed to get peer certificate")
  let pkey = X509_get0_pubkey(cert)
  if pkey == nil:
    sdie("failed to decode public key")
  var pubkeyBuf: array[16384, uint8]
  let len = i2d_PUBKEY(pkey, nil);
  if len * 3 > pubkeyBuf.len:
    os.die("InternalError", "pubkey too long")
  var r = addr pubkeyBuf[0]
  if i2d_PUBKEY(pkey, addr r) != len:
    os.die("InternalError", "wat")
  theirDigest = pubkeyBuf.toOpenArray(0, len - 1).hashBuf()
  let notAfter = X509_get0_notAfter(cert)
  var theirTm: Tm
  if ASN1_TIME_to_tm(notAfter, addr theirTm) == 0:
    sdie("Failed to parse time");
  if getEnv("CHA_INSECURE_SSL_NO_VERIFY") != "1":
    if X509_cmp_current_time(X509_get0_notBefore(cert)) >= 0 or
        X509_cmp_current_time(notAfter) <= 0:
      os.die("InvalidResponse", "received an expired certificate");
  theirTime = mktime(theirTm)
  X509_free(cert)
  return os.checkCert(theirDigest, host, storedDigest, theirTime, knownHosts,
    tmpEntry)

proc readResponse(os: PosixStream; ssl: ptr SSL; reqBuf: string) =
  var buffer = newString(4096)
  var n = 0
  while n < buffer.len:
    let m = SSL_read(ssl, addr buffer[n], cint(buffer.len - n))
    if m == 0:
      break
    n += m
  let status0 = buffer[0]
  let status1 = buffer[1]
  if status0 notin AsciiDigit or status1 notin AsciiDigit:
    os.die("InvalidResponse", "invalid status code")
  while n < 1024 + 3: # max meta len is 1024
    let m = SSL_read(ssl, addr buffer[n], cint(buffer.len - n))
    if m == 0:
      break
    n += m
  let i = buffer.find("\r\n")
  if i == -1:
    os.die("InvalidResponse", "invalid status line")
  var meta = buffer.substr(3, i - 1)
  if '\n' in meta:
    os.die("InvalidResponse", "invalid status line")
  case status0
  of '1': # input
    # META is the prompt.
    let it = if status1 == '1': "password" else: "search"
    os.sendDataLoop("""Content-Type: text/html

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
    os.sendDataLoop("Content-Type: " & meta & "\n\n")
    os.sendDataLoop(buffer.toOpenArray(i + 2, n - 1))
    while true:
      let n = SSL_read(ssl, addr buffer[0], cint(buffer.len))
      if n == 0:
        break
      os.sendDataLoop(buffer.toOpenArray(0, int(n) - 1))
  of '3': # redirect
    # META is the redirection URL.
    let c = if status1 == '0':
      '7' # temporary
    else:
      '1' # permanent
    os.sendDataLoop("Status: 30" & c & "\nLocation: " & meta & "\n\n")
  of '4': # temporary failure
    # META is additional information.
    let tmp = case status1
    of '1': "Server unavailable"
    of '2': "CGI error"
    of '3': "Proxy error"
    of '4': "Slow down!"
    else: "Temporary failure" # no additional information provided in the code
    os.sendDataLoop("""Content-Type: text/html

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
    os.sendDataLoop("""Content-Type: text/html

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
    os.sendDataLoop("""Content-Type: text/html

<!DOCTYPE html>
<title>Certificate failure</title>
<h1>""" & tmp & """</h1>
<p>
""" & meta.htmlEscape())
  else:
    os.die("InvalidResponse", "Wrong status code")

proc main() =
  let os = newPosixStream(STDOUT_FILENO)
  let host = getEnv("MAPPED_URI_HOST")
  var (knownHosts, knownHostsPath) = os.openKnownHosts()
  var port = getEnv("MAPPED_URI_PORT")
  if port == "":
    port = "1965"
  var path = getEnv("MAPPED_URI_PATH")
  if path == "":
    path = "/"
  var reqBuf = "gemini://" & host & path
  var query = getEnv("MAPPED_URI_QUERY")
  var tmpEntry = "" # for accepting a self signed cert "once"
  if getEnv("REQUEST_METHOD") == "POST":
    os.readPost(query, host, knownHostsPath, knownHosts, tmpEntry)
  if query != "":
    reqBuf &= '?' & query
  reqBuf &= "\r\n"
  let ssl = os.connectSSLSocket(host, port)
  var storedDigest: string
  var theirDigest: string
  var theirTime: Time
  case os.connect(ssl, host, port, knownHosts, storedDigest, theirDigest,
    theirTime, tmpEntry)
  of ccrFoundValid:
    discard SSL_write(ssl, cstring(reqBuf), cint(reqBuf.len))
    os.readResponse(ssl, reqBuf)
  of ccrFoundInvalid:
    os.sendDataLoop("""
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
    os.sendDataLoop("""
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
    os.sendDataLoop("""
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

main()
