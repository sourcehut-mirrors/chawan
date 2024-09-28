import std/options
import std/os
import std/strutils

import curl
import curlerrors
import curlwrap
import dirlist

import utils/twtstr

type FtpHandle = ref object
  curl: CURL
  buffer: string
  dirmode: bool
  base: string
  path: string
  statusline: bool

proc printHeader(op: FtpHandle) =
    if op.dirmode:
      stdout.write("""Content-Type: text/html

<HTML>
<HEAD>
<BASE HREF=""" & op.base & """>
<TITLE>""" & op.path & """</TITLE>
</HEAD>
<BODY>
<H1>Index of """ & htmlEscape(op.path) & """</H1>
<PRE>
""")
    else:
      stdout.write('\n')

proc curlWriteHeader(p: cstring; size, nitems: csize_t; userdata: pointer):
    csize_t {.cdecl.} =
  var line = newString(nitems)
  if nitems > 0:
    copyMem(addr line[0], p, nitems)
  let op = cast[FtpHandle](userdata)
  if not op.statusline:
    if line.startsWith("150") or line.startsWith("125"):
      op.statusline = true
      var status: clong
      op.curl.getinfo(CURLINFO_RESPONSE_CODE, addr status)
      stdout.write("Status: " & $status & "\n")
      op.printHeader()
      return nitems
    elif line.startsWith("530"): # login incorrect
      op.statusline = true
      var status: clong
      op.curl.getinfo(CURLINFO_RESPONSE_CODE, addr status)
      # unauthorized (shim http)
      stdout.write("""
Status: 401
Content-Type: text/html

<HTML>
<HEAD>
<TITLE>Unauthorized</TITLE>
</HEAD>
<BODY>
<PRE>
""" & htmlEscape(line) & """
</PRE>
</BODY>
</HTML>
""")
  return nitems

# From the documentation: size is always 1.
proc curlWriteBody(p: cstring; size, nmemb: csize_t; userdata: pointer):
    csize_t {.cdecl.} =
  let op = cast[FtpHandle](userdata)
  if not op.statusline:
    op.statusline = true
    op.printHeader()
  if nmemb > 0:
    if op.dirmode:
      let i = op.buffer.len
      op.buffer.setLen(op.buffer.len + int(nmemb))
      copyMem(addr op.buffer[i], p, nmemb)
    else:
      return csize_t(stdout.writeBuffer(p, int(nmemb)))
  return nmemb

proc finish(op: FtpHandle) =
  let op = op
  var items: seq[DirlistItem] = @[]
  for line in op.buffer.split('\n'):
    if line.len == 0: continue
    var i = 10 # permission
    template skip_till_space =
      while i < line.len and line[i] != ' ':
        inc i
    # link count
    i = line.skipBlanks(i)
    while i < line.len and line[i] in AsciiDigit:
      inc i
    # owner
    i = line.skipBlanks(i)
    skip_till_space
    # group
    i = line.skipBlanks(i)
    while i < line.len and line[i] != ' ':
      inc i
    # size
    i = line.skipBlanks(i)
    var sizes = ""
    while i < line.len and line[i] in AsciiDigit:
      sizes &= line[i]
      inc i
    let nsize = parseInt64(sizes).get(-1)
    # date
    i = line.skipBlanks(i)
    let datestarti = i
    skip_till_space # m
    i = line.skipBlanks(i)
    skip_till_space # d
    i = line.skipBlanks(i)
    skip_till_space # y
    let dates = line.substr(datestarti, i)
    inc i
    let name = line.substr(i)
    if name == "." or name == "..": continue
    case line[0]
    of 'l': # link
      let linki = name.find(" -> ")
      let linkfrom = name.substr(0, linki - 1)
      let linkto = name.substr(linki + 4) # you?
      items.add(DirlistItem(
        t: ditLink,
        name: linkfrom,
        modified: dates,
        linkto: linkto
      ))
    of 'd': # directory
      items.add(DirlistItem(
        t: ditDir,
        name: name,
        modified: dates
      ))
    else: # file
      items.add(DirlistItem(
        t: ditFile,
        name: name,
        modified: dates,
        nsize: int(nsize)
      ))
  stdout.write(makeDirlist(items))
  stdout.write("\n</PRE>\n</BODY>\n</HTML>\n")

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

proc parseSSHConfig(f: File; curl: CURL; host: string; idSet: var bool) =
  var skipTillNext = false
  var line: string
  var certificateFile = ""
  var identityFile = ""
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
      identityFile = expandTilde(args[0])
    elif k == "CertificateFile":
      if args.len != 1:
        continue # error
      certificateFile = expandTilde(args[0])
  if identityFile != "":
    curl.setopt(CURLOPT_SSH_PRIVATE_KEYFILE, identityFile)
    idSet = true
  if certificateFile != "":
    curl.setopt(CURLOPT_SSH_PUBLIC_KEYFILE, certificateFile)
  f.close()

proc main() =
  let curl = curl_easy_init()
  doAssert curl != nil
  var opath = getEnv("MAPPED_URI_PATH")
  if opath == "":
    opath = "/"
  let path = percentDecode(opath)
  let op = FtpHandle(
    curl: curl,
    dirmode: path.len > 0 and path[^1] == '/'
  )
  let url = curl_url()
  const flags = cuint(CURLU_PATH_AS_IS)
  let scheme = getEnv("MAPPED_URI_SCHEME")
  url.set(CURLUPART_SCHEME, scheme, flags)
  let username = getEnv("MAPPED_URI_USERNAME")
  if username != "":
    url.set(CURLUPART_USER, username, flags)
  let host = getEnv("MAPPED_URI_HOST")
  let password = getEnv("MAPPED_URI_PASSWORD")
  var idSet = false
  # Parse SSH config for sftp.
  if scheme == "sftp":
    let systemConfig = "/etc/ssh/ssh_config"
    if fileExists(systemConfig):
      var f: File
      if f.open(systemConfig):
        parseSSHConfig(f, curl, host, idSet)
    let userConfig = expandTilde("~/.ssh/config")
    if fileExists(userConfig):
      var f: File
      if f.open(userConfig):
        parseSSHConfig(f, curl, host, idSet)
    if idSet:
      curl.setopt(CURLOPT_KEYPASSWD, password)
  url.set(CURLUPART_PASSWORD, password, flags)
  url.set(CURLUPART_HOST, host, flags)
  let port = getEnv("MAPPED_URI_PORT")
  if port != "":
    url.set(CURLUPART_PORT, port, flags)
  # By default, cURL CWD's into relative paths, and an extra slash is
  # necessary to specify absolute paths.
  # This is incredibly confusing, and probably not what the user wanted.
  # So we work around it by adding the extra slash ourselves.
  #
  # But before that, we take the serialized URL without the path for
  # setting the base URL:
  url.set(CURLUPART_PATH, opath, flags)
  if op.dirmode:
    let surl = url.get(CURLUPART_URL, cuint(CURLU_PUNY2IDN))
    if surl == nil:
      stdout.write("Cha-Control: ConnectionError InvalidURL\n")
      curl_url_cleanup(url)
      curl_easy_cleanup(curl)
      return
    op.base = $surl
    op.path = path
    curl_free(surl)
  # Now for the workaround:
  if scheme != "sftp" and (opath.len <= 1 or opath[1] != '~'):
    url.set(CURLUPART_PATH, '/' & opath, flags)
  # Another hack: if password was set for the identity file, then clear it from
  # the URL.
  if idSet:
    url.set(CURLUPART_PASSWORD, nil, flags)
  # Set opts for the request
  curl.setopt(CURLOPT_CURLU, url)
  curl.setopt(CURLOPT_HEADERDATA, op)
  curl.setopt(CURLOPT_HEADERFUNCTION, curlWriteHeader)
  curl.setopt(CURLOPT_WRITEDATA, op)
  curl.setopt(CURLOPT_WRITEFUNCTION, curlWriteBody)
  curl.setopt(CURLOPT_FTP_FILEMETHOD, CURLFTPMETHOD_SINGLECWD)
  let purl = getEnv("ALL_PROXY")
  if purl != "":
    curl.setopt(CURLOPT_PROXY, purl)
  if getEnv("REQUEST_METHOD") != "GET":
    # fail
    stdout.write("Cha-Control: ConnectionError InvalidMethod\n")
  else:
    let res = curl_easy_perform(curl)
    if res != CURLE_OK:
      if not op.statusline:
        if res == CURLE_LOGIN_DENIED:
          stdout.write("Status: 401\n")
        else:
          stdout.write(getCurlConnectionError(res))
    elif op.dirmode:
      op.finish()
  curl_url_cleanup(url)
  curl_easy_cleanup(curl)

main()
