import std/os
import std/strutils
import std/times

import utils/twtstr

import lcgi

const libssh2 = staticExec("pkg-config --libs libssh2")

{.passl: libssh2.}

# libssh2 bindings

type
  LIBSSH2_SESSION {.importc, header: "<libssh2.h>", incompleteStruct.} = object
  LIBSSH2_SFTP {.importc, header: "<libssh2_sftp.h>", incompleteStruct.} =
    object
  LIBSSH2_SFTP_HANDLE {.importc, header: "<libssh2_sftp.h>",
    incompleteStruct.} = object

  LIBSSH2_SFTP_ATTRIBUTES {.importc, header: "<libssh2_sftp.h>".} = object
    flags: culong
    filesize: uint64
    uid: culong
    gid: culong
    permissions: culong
    atime: culong
    mtime: culong

{.push importc, cdecl, header: "<libssh2.h>".}

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
proc libssh2_session_free(session: ptr LIBSSH2_SESSION): cint
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

proc parseSSHConfig(f: File; host: string; pubKey, privKey: var string) =
  var skipTillNext = false
  var line = ""
  while f.readLine(line):
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
      privKey = expandTilde(args[0])
    elif k == "CertificateFile":
      if args.len != 1:
        continue # error
      pubKey = expandTilde(args[0])
  f.close()

proc unauthorized(os: PosixStream; session: ptr LIBSSH2_SESSION) =
  os.sendDataLoop("Status: 401\n")
  quit(0)

proc authenticate(os: PosixStream; session: ptr LIBSSH2_SESSION; host: string) =
  let user = getEnv("MAPPED_URI_USERNAME")
  let pass = getEnv("MAPPED_URI_PASSWORD")
  let configs = ["/etc/ssh/ssh_config", expandTilde("~/.ssh/config")]
  var pubKey = ""
  var privKey = ""
  for config in configs:
    var f: File
    if f.open(config):
      parseSSHConfig(f, host, pubKey, privKey)
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
  os.sendDataLoop("Content-Type: text/x-dirlist;title=" & title & "\n\n")
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
    os.sendDataLoop(buf)

proc readFile(os: PosixStream; sftpSession: ptr LIBSSH2_SFTP; path: string) =
  let handle = sftpSession.libssh2_sftp_open(cstring(path), LIBSSH2_FXF_READ, 0)
  var attrs: LIBSSH2_SFTP_ATTRIBUTES
  if handle == nil or libssh2_sftp_fstat(handle, attrs) != 0:
    os.sendDataLoop("Status: 404\nContent-Type: text/html\n\n<h1>Not found")
    quit(0)
  os.sendDataLoop("Content-Length: " & $attrs.filesize & "\n\n")
  # Apparently a huge buffer results in significant speed increases
  # compared to a small one.
  var buffer {.noinit.}: array[65536, char]
  while true:
    let n = handle.libssh2_sftp_read(addr buffer[0], csize_t(buffer.len))
    if n <= 0:
      break
    os.sendDataLoop(buffer.toOpenArray(0, n - 1))

proc main() =
  let os = newPosixStream(STDOUT_FILENO)
  if getEnv("REQUEST_METHOD") != "GET":
    os.die("InvalidMethod")
  let host = getEnv("MAPPED_URI_HOST")
  let port = getEnvEmpty("MAPPED_URI_PORT", "22")
  let ps = os.connectSocket(host, port)
  if libssh2_init(0) < 0:
    os.die("InternalError")
  let session = libssh2_session_init()
  if session.libssh2_session_handshake(ps.fd) < 0:
    os.die("InternalError", "handshake failed")
  #TODO check known hosts file...
  os.authenticate(session, host)
  enterNetworkSandbox()
  let sftpSession = libssh2_sftp_init(session)
  let path = percentDecode(getEnvEmpty("MAPPED_URI_PATH", "/"))
  let handle = sftpSession.libssh2_sftp_opendir(cstring(path))
  if handle != nil:
    if path[^1] != '/':
      os.sendDataLoop("Status: 301\nLocation: " & path & "/\n")
      quit(0)
    os.readDir(sftpSession, handle, path)
  else:
    os.readFile(sftpSession, path)
  discard sftpSession.libssh2_sftp_shutdown()
  discard session.libssh2_session_disconnect("")
  discard session.libssh2_session_free()
  libssh2_exit()

main()
