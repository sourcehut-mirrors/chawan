# See ssl.nim for the entry point.

{.push raises: [].}

import std/strutils
import std/times

import utils/twtstr

import lcgi

# libssh2 bindings

type
  LIBSSH2_SESSION {.importc, header: "<libssh2.h>", incompleteStruct.} = object
  LIBSSH2_KNOWNHOSTS {.importc, header: "<libssh2.h>", incompleteStruct.} =
    object
  LIBSSH2_SFTP {.importc, header: "<libssh2_sftp.h>", incompleteStruct.} =
    object
  LIBSSH2_SFTP_HANDLE {.importc, header: "<libssh2_sftp.h>",
    incompleteStruct.} = object
  libssh2_knownhost {.importc: "struct libssh2_knownhost",
    header: "<libssh2.h>".} = object
    magic: cuint
    node: pointer
    name: cstring
    key: cstring
    typemask: cint

  LIBSSH2_SFTP_ATTRIBUTES {.importc, header: "<libssh2_sftp.h>".} = object
    flags: culong
    filesize: uint64
    uid: culong
    gid: culong
    permissions: culong
    atime: culong
    mtime: culong

{.push importc, cdecl, header: "<libssh2.h>".}

let LIBSSH2_KNOWNHOST_FILE_OPENSSH {.importc.}: cint
let LIBSSH2_KNOWNHOST_TYPE_PLAIN {.importc.}: cint
let LIBSSH2_KNOWNHOST_KEYENC_RAW {.importc.}: cint
let LIBSSH2_KNOWNHOST_CHECK_MATCH {.importc.}: cint
let LIBSSH2_KNOWNHOST_CHECK_MISMATCH {.importc.}: cint
let LIBSSH2_KNOWNHOST_CHECK_NOTFOUND {.importc.}: cint
let LIBSSH2_KNOWNHOST_CHECK_FAILURE {.importc.}: cint
let LIBSSH2_HOSTKEY_TYPE_UNKNOWN {.importc.}: cint

const LIBSSH2_KNOWNHOST_KEY_MASK = 15 shl 18
const LIBSSH2_KNOWNHOST_KEY_SHIFT = 18
const LIBSSH2_KNOWNHOST_KEY_SSHRSA = 2 shl 18
const LIBSSH2_KNOWNHOST_KEY_SSHDSS = 3 shl 18
const LIBSSH2_KNOWNHOST_KEY_ECDSA_256 = 4 shl 18
const LIBSSH2_KNOWNHOST_KEY_ECDSA_384 = 5 shl 18
const LIBSSH2_KNOWNHOST_KEY_ECDSA_521 = 6 shl 18
const LIBSSH2_KNOWNHOST_KEY_ED25519 = 7 shl 18

let LIBSSH2_METHOD_HOSTKEY {.importc.}: cint

proc libssh2_init(flags: cint): cint
proc libssh2_session_init(): ptr LIBSSH2_SESSION {.nodecl.}
proc libssh2_session_handshake(session: ptr LIBSSH2_SESSION;
  socket: cint): cint
proc libssh2_userauth_password(session: ptr LIBSSH2_SESSION;
  username: cstring; password: cstring): cint {.nodecl.}
proc libssh2_userauth_publickey_fromfile(session: ptr LIBSSH2_SESSION;
  username, publickey, privatekey, passphrase: cstring): cint {.nodecl.}
proc libssh2_session_disconnect(session: ptr LIBSSH2_SESSION;
  description: cstring): cint {.nodecl.}
proc libssh2_session_hostkey(session: ptr LIBSSH2_SESSION; len: var csize_t;
  t: var cint): cstring
proc libssh2_session_method_pref(session: ptr LIBSSH2_SESSION; method_type: cint;
  prefs: cstring): cint
proc libssh2_session_free(session: ptr LIBSSH2_SESSION): cint
proc libssh2_knownhost_init(session: ptr LIBSSH2_SESSION):
  ptr LIBSSH2_KNOWNHOSTS
proc libssh2_knownhost_readfile(hosts: ptr LIBSSH2_KNOWNHOSTS,
  filename: cstring; t: cint): cint
proc libssh2_knownhost_checkp(hosts: ptr LIBSSH2_KNOWNHOSTS; host: cstring;
  port: cint; key: cstring; keylen: csize_t; typemask: cint;
  knownhost: var ptr libssh2_knownhost): cint
proc libssh2_knownhost_get(hosts: ptr LIBSSH2_KNOWNHOSTS;
  store: ptr ptr libssh2_knownhost; prev: ptr libssh2_knownhost): cint
proc libssh2_knownhost_free(hosts: ptr LIBSSH2_KNOWNHOSTS)
proc libssh2_exit()

{.push header: "<libssh2_sftp.h>".}
proc libssh2_sftp_init(session: ptr LIBSSH2_SESSION): ptr LIBSSH2_SFTP
proc libssh2_sftp_opendir(sftp: ptr LIBSSH2_SFTP; path: cstring):
  ptr LIBSSH2_SFTP_HANDLE {.nodecl.}
proc libssh2_sftp_readdir_ex(handle: ptr LIBSSH2_SFTP_HANDLE; buffer: ptr char;
  buffer_maxlen: csize_t; longentry: ptr char; longentry_maxlen: csize_t;
  attrs: var LIBSSH2_SFTP_ATTRIBUTES): cint
proc libssh2_sftp_fstat(handle: ptr LIBSSH2_SFTP_HANDLE;
  attrs: var LIBSSH2_SFTP_ATTRIBUTES): cint {.nodecl.}
proc libssh2_sftp_readlink(sftp: ptr LIBSSH2_SFTP; path: cstring;
  target: ptr char; target_len: cuint): cint
proc libssh2_sftp_open(sftp: ptr LIBSSH2_SFTP; path: cstring; flags: culong;
  mode: clong): ptr LIBSSH2_SFTP_HANDLE {.nodecl.}
proc libssh2_sftp_read(handle: ptr LIBSSH2_SFTP_HANDLE; buffer: ptr char;
  buffer_maxlen: csize_t): int
proc libssh2_sftp_shutdown(sftp: ptr LIBSSH2_SFTP): cint
{.pop.}

{.pop.}

proc matchesPattern(s, pat: openArray[char]): bool =
  var i = 0
  for j, c in pat:
    if c == '*':
      while i < s.len:
        if s.toOpenArray(i, s.high).matchesPattern(pat.toOpenArray(j + 1,
            pat.high)):
          return true
        inc i
      return false
    if i >= s.len or c != '?' and c != s[i]:
      return false
    inc i
  return true

proc matchesPattern(s: string; pats: openArray[string]): bool =
  for pat in pats:
    if s.matchesPattern(pat):
      return true
  return false

proc parseSSHConfig(f: AChaFile; host: string; pubKey, privKey: var string):
    Opt[void] =
  var skipTillNext = false
  var line = ""
  while ?f.readLine(line):
    var i = line.skipBlanks(0)
    if i == line.len or line[i] == '#':
      continue
    let k = line.until(AsciiWhitespace, i)
    i = line.skipBlanks(i + k.len)
    if i < line.len and line[i] == '=':
      i = line.skipBlanks(i + 1)
    if i == line.len or line[i] == '#':
      continue
    var args = newSeq[string]()
    while i < line.len:
      let isStr = line[i] in {'"', '\''}
      if isStr:
        inc i
      var quot = false
      var arg = ""
      while i < line.len:
        if not quot:
          if line[i] == '\\':
            quot = true
            continue
          elif line[i] == '"' and isStr or line[i] == ' ' and not isStr:
            inc i
            break
        quot = false
        arg &= line[i]
        inc i
      if arg.len > 0:
        args.add(arg)
    if k == "Match": #TODO support this
      skipTillNext = true
    elif k == "Host":
      skipTillNext = not host.matchesPattern(args)
    elif skipTillNext:
      continue
    elif k == "IdentityFile":
      if args.len != 1:
        continue # error
      if privKey == "":
        privKey = expandPath(args[0])
    elif k == "CertificateFile":
      if args.len != 1:
        continue # error
      if pubKey == "":
        pubKey = expandPath(args[0])
  ok()

proc unauthorized(os: PosixStream; session: ptr LIBSSH2_SESSION) =
  discard os.writeLoop("Status: 401\n")
  quit(0)

proc authenticate(os: PosixStream; session: ptr LIBSSH2_SESSION; host: string) =
  let user = getEnvEmpty("MAPPED_URI_USERNAME")
  let pass = getEnvEmpty("MAPPED_URI_PASSWORD")
  let configs = ["/etc/ssh/ssh_config", expandPath("~/.ssh/config")]
  var pubKey = ""
  var privKey = ""
  for config in configs:
    let f = chafile.afopen(config, "r")
    if f.isErr:
      continue
    parseSSHConfig(f.get, host, pubKey, privKey)
      .orDie(ceInternalError, "failed to read SSH config")
  if privKey == "":
    if session.libssh2_userauth_password(cstring(user), cstring(pass)) != 0:
      os.unauthorized(session)
  else:
    if pubKey == "":
      pubKey = privKey & ".pub"
    if session.libssh2_userauth_publickey_fromfile(cstring(user),
        cstring(pubKey), cstring(privKey), cstring(pass)) != 0:
      os.unauthorized(session)

const LIBSSH2_SFTP_ATTR_SIZE = 0x1
const LIBSSH2_SFTP_ATTR_PERMISSIONS = 0x4
const LIBSSH2_SFTP_ATTR_ACMODTIME = 0x8

const LIBSSH2_FXF_READ = 0x00000001

const LIBSSH2_SFTP_S_IFDIR = 0o040000
const LIBSSH2_SFTP_S_IFLNK = 0o120000

# The libssh2 documentation is horrid, so I'm mostly looking at the spec
# here... it seems the server can either send a structured data field
# ("status") or just a string? sshd seems to always do the latter,
# but I'm also getting attrs... the example handles both... guess I'll
# do the same, just to be sure.
proc readDir(os: PosixStream; sftpSession: ptr LIBSSH2_SFTP;
    handle: ptr LIBSSH2_SFTP_HANDLE; path: string) =
  let title = ("Index of " & path).mimeQuote()
  discard os.writeLoop("Content-Type: text/x-dirlist;title=" & title & "\n\n")
  var buffer {.noinit.}: array[512, char]
  var longentry {.noinit.}: array[512, char]
  while true:
    var attrs: LIBSSH2_SFTP_ATTRIBUTES
    let n = handle.libssh2_sftp_readdir_ex(addr buffer[0], csize_t(buffer.len),
      addr longentry[0], csize_t(longentry.len), attrs)
    if n <= 0:
      break
    var name = ""
    for c in buffer.toOpenArray(0, n - 1):
      name &= c
    var buf = ""
    for c in longentry:
      if c == '\0':
        break
      buf &= c
    if buf.len == 0:
      if (attrs.flags and LIBSSH2_SFTP_ATTR_PERMISSIONS) != 0:
        if (attrs.permissions and LIBSSH2_SFTP_S_IFDIR) != 0:
          buf &= 'd'
        elif (attrs.permissions and LIBSSH2_SFTP_S_IFLNK) != 0:
          buf &= 'l'
        else:
          buf &= '-'
        for i, c in "rwxrwxrwx":
          if ((attrs.permissions shr (8 - i)) and 1) != 0:
            buf &= c
          else:
            buf &= '-'
      else:
        buf &= "----------"
      buf &= " 0 0 0 "
      if (attrs.flags and LIBSSH2_SFTP_ATTR_SIZE) != 0:
        buf &= $attrs.filesize
      buf &= ' '
      if (attrs.flags and LIBSSH2_SFTP_ATTR_ACMODTIME) != 0:
        buf &= int64(attrs.mtime).fromUnix().local().format("MMM dd yyyy")
      buf &= ' '
      buf &= name
    if (attrs.flags and LIBSSH2_SFTP_ATTR_PERMISSIONS) != 0 and
        (attrs.permissions and LIBSSH2_SFTP_S_IFLNK) != 0 and
        buf.find(" -> ") == -1:
      let n = sftpSession.libssh2_sftp_readlink(cstring(path & name),
        addr buffer[0], cuint(buffer.len))
      if n > 0:
        buf &= " -> "
        for i in 0 ..< n:
          buf &= buffer[i]
    buf &= '\n'
    if os.writeLoop(buf).isErr:
      break

proc readFile(os: PosixStream; sftpSession: ptr LIBSSH2_SFTP; path: string) =
  let handle = sftpSession.libssh2_sftp_open(cstring(path), LIBSSH2_FXF_READ, 0)
  var attrs: LIBSSH2_SFTP_ATTRIBUTES
  if handle == nil or libssh2_sftp_fstat(handle, attrs) != 0:
    discard os.writeLoop("""Status: 404
Content-Type: text/html

<h1>Not found""")
    quit(0)
  discard os.writeLoop("Content-Length: " & $attrs.filesize & "\n\n")
  # Apparently a huge buffer results in significant speed increases
  # compared to a small one.
  var buffer {.noinit.}: array[65536, char]
  while true:
    let n = handle.libssh2_sftp_read(addr buffer[0], csize_t(buffer.len))
    if n <= 0:
      break
    if os.writeLoop(buffer.toOpenArray(0, n - 1)).isErr:
      break

# Fingerprint validation.
# Yes, this is actually how you're supposed to do this.
proc setMethod(os: PosixStream; session: ptr LIBSSH2_SESSION;
    host, port: string; hostsPath: var string): ptr LIBSSH2_KNOWNHOSTS =
  hostsPath = ""
  if getEnvEmpty("CHA_INSECURE_SSL_NO_VERIFY") == "1":
    return nil
  let hosts = libssh2_knownhost_init(session)
  if hosts == nil:
    cgiDie(ceInternalError, "failed to init knownhost")
  hostsPath = getEnvEmpty("CHA_SSH_KNOWN_HOSTS",
    expandPath("~/.ssh/known_hosts"))
  discard hosts.libssh2_knownhost_readfile(cstring(hostsPath),
    LIBSSH2_KNOWNHOST_FILE_OPENSSH)
  var store: ptr libssh2_knownhost = nil
  let name = if port == "22":
    host
  elif host[0] == '[':
    host & ':' & port
  else:
    '[' & host & "]:" & port
  var found = false
  while not found and libssh2_knownhost_get(hosts, addr store, store) == 0:
    if store == nil or store.name == nil:
      continue
    found = $store.name == name
  if found:
    let t = store.typemask and LIBSSH2_KNOWNHOST_KEY_MASK
    let meth = case t
    of LIBSSH2_KNOWNHOST_KEY_ED25519: cstring"ssh-ed25519"
    of LIBSSH2_KNOWNHOST_KEY_ECDSA_521: cstring"ecdsa-sha2-nistp521"
    of LIBSSH2_KNOWNHOST_KEY_ECDSA_384: cstring"ecdsa-sha2-nistp384"
    of LIBSSH2_KNOWNHOST_KEY_ECDSA_256: cstring"ecdsa-sha2-nistp256"
    of LIBSSH2_KNOWNHOST_KEY_SSHRSA: cstring"rsa-sha2-256,rsa-sha2-512,ssh-rsa"
    of LIBSSH2_KNOWNHOST_KEY_SSHDSS: cstring"ssh-dss"
    else: nil
    if meth != nil:
      if session.libssh2_session_method_pref(LIBSSH2_METHOD_HOSTKEY, meth) != 0:
        cgiDie(ceInternalError, "failed to set host key method")
  return hosts

proc checkFingerprint(os: PosixStream; session: ptr LIBSSH2_SESSION;
    hosts: ptr LIBSSH2_KNOWNHOSTS; host, port, hostsPath: string) =
  var len: csize_t
  var t: cint
  let fingerprint = session.libssh2_session_hostkey(len, t)
  if fingerprint == nil:
    cgiDie(ceInternalError, "missing fingerprint")
  if t == LIBSSH2_HOSTKEY_TYPE_UNKNOWN:
    cgiDie(ceInternalError, "unknown host key type")
  let port = cint(parseIntP(port).get(-1))
  var knownhost: ptr libssh2_knownhost
  let hostBit = (t + 1) shl LIBSSH2_KNOWNHOST_KEY_SHIFT # wtf?
  let check = hosts.libssh2_knownhost_checkp(cstring(host), port,
    fingerprint, len, LIBSSH2_KNOWNHOST_TYPE_PLAIN or
    LIBSSH2_KNOWNHOST_KEYENC_RAW or hostBit, knownhost)
  if check == LIBSSH2_KNOWNHOST_CHECK_FAILURE:
    cgiDie(ceInternalError, "failure in known hosts check")
  elif check == LIBSSH2_KNOWNHOST_CHECK_MATCH:
    discard
  elif check == LIBSSH2_KNOWNHOST_CHECK_NOTFOUND:
    discard os.writeLoop("""
Content-Type: text/html

<!DOCTYPE html>
<title>Unknown host</title>
<h1>Unknown host</h1>
<p>
Host not found in known_hosts at """ & hostsPath & """.
<p>
Please try to connect to the server once with SSH:
ssh """ & host & " -p " & $port)
    quit(1)
  else:
    assert check == LIBSSH2_KNOWNHOST_CHECK_MISMATCH
    discard os.writeLoop("""
Content-Type: text/html

<!DOCTYPE html>
<title>Invalid fingerprint</title>
<h1>Invalid fingerprint</h1>
<p>
The fingerprint received from the server does not match the stored
fingerprint.  Somebody may be tampering with your connection.
<p>
If you are sure that this is not a man-in-the-middle attack,
please remove this host from """ & hostsPath & ".")
    quit(1)
  hosts.libssh2_knownhost_free()

proc main*() =
  let os = newPosixStream(STDOUT_FILENO)
  if getEnvEmpty("REQUEST_METHOD") != "GET":
    cgiDie(ceInvalidMethod)
  let host = getEnvEmpty("MAPPED_URI_HOST")
  let port = getEnvEmpty("MAPPED_URI_PORT", "22")
  let ps = connectSocket(host, port).orDie()
  if libssh2_init(0) < 0:
    cgiDie(ceInternalError)
  let session = libssh2_session_init()
  var hostsPath: string
  let hosts = os.setMethod(session, host, port, hostsPath)
  if session.libssh2_session_handshake(ps.fd) < 0:
    cgiDie(ceInternalError, "handshake failed")
  if hosts != nil:
    os.checkFingerprint(session, hosts, host, port, hostsPath)
  os.authenticate(session, host)
  enterNetworkSandbox()
  let sftpSession = libssh2_sftp_init(session)
  let path = percentDecode(getEnvEmpty("MAPPED_URI_PATH", "/"))
  let handle = sftpSession.libssh2_sftp_opendir(cstring(path))
  if handle != nil:
    if path[^1] != '/':
      discard os.writeLoop("Status: 301\nLocation: " & path & "/\n")
      quit(0)
    os.readDir(sftpSession, handle, path)
  else:
    os.readFile(sftpSession, path)
  discard sftpSession.libssh2_sftp_shutdown()
  discard session.libssh2_session_disconnect("")
  discard session.libssh2_session_free()
  libssh2_exit()

{.pop.} # raises: []
