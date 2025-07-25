{.push raises: [].}

import std/posix

import lcgi

proc my_strftime(s: cstring; slen: csize_t; format: cstring;
  tm: ptr Tm): csize_t {.importc: "strftime", header: "<time.h>".}

proc my_readlink(path: cstring; buf: cstring; buflen: csize_t):
  int {.importc: "readlink", header: "<unistd.h>".}

proc loadDir(path, opath: string): Opt[void] =
  let title = ("Directory list of " & path).mimeQuote()
  let stdout = cast[ChaFile](stdout)
  ?stdout.write("Content-Type: text/x-dirlist;title=" & title & "\n\n")
  let d = opendir(path)
  while (let x = readdir(d); x != nil):
    let file = $cast[cstring](addr x.d_name)
    let fullpath = path & file
    var stats: Stat
    if lstat(cstring(fullpath), stats) < 0:
      continue
    var line = ""
    if S_ISDIR(stats.st_mode):
      line &= 'd'
    elif S_ISLNK(stats.st_mode):
      line &= 'l'
    else:
      line &= '-'
    let PermMap = {
      cint(S_IRUSR): 'r',
      cint(S_IWUSR): 'w',
      cint(S_IXUSR): 'x',
      cint(S_IRGRP): 'r',
      cint(S_IWGRP): 'w',
      cint(S_IXGRP): 'x',
      cint(S_IROTH): 'r',
      cint(S_IWOTH): 'w',
      cint(S_IXOTH): 'x'
    }
    for (perm, c) in PermMap:
      if (cint(stats.st_mode) and cint(perm)) != 0:
        line &= c
      else:
        line &= '-'
    line &= ' ' & $stats.st_nlink & ' '
    line &= $stats.st_uid & ' ' # owner (currently unused in dirlist2html)
    line &= $stats.st_gid & ' ' # group (ditto)
    line &= $stats.st_size & ' '
    #TODO if new enough, send time instead of year
    var time = stats.st_mtime
    let modified = localtime(time)
    var s = newString(64)
    let n = my_strftime(cstring(s), csize_t(s.len), "%b %d %Y", modified)
    s.setLen(int(n))
    line &= s & ' '
    line &= file
    if S_ISLNK(stats.st_mode):
      let len = int(stats.st_size)
      var target = newString(len)
      let n = my_readlink(cstring(fullpath), cstring(target), csize_t(len))
      if n == len and stat(cstring(target), stats) == 0:
        if S_ISDIR(stats.st_mode) and (target.len == 0 or target[^1] != '/'):
          target &= '/'
      line &= " -> " & target
    ?stdout.writeLine(line)
  ok()

proc loadFile(os, ps: PosixStream; stats: Stat) =
  const BufferSize = 16384
  var buffer {.noinit.}: array[BufferSize, char]
  let s = "Content-Length: " & $stats.st_size & "\n"
  var start = 0
  for c in s:
    buffer[start] = c
    inc start
  buffer[start] = '\n'
  inc start
  while true:
    let n = ps.readData(buffer.toOpenArray(start, buffer.high))
    if n <= 0:
      break
    if not os.writeDataLoop(buffer.toOpenArray(0, start + n - 1)):
      break
    start = 0

proc main() =
  let opath = getEnvEmpty("MAPPED_URI_PATH", "/")
  let path = percentDecode(opath)
  let os = newPosixStream(STDOUT_FILENO)
  var stats: Stat
  let res = stat(cstring(path), stats)
  if res == 0 and S_ISDIR(stats.st_mode):
    if path[^1] != '/':
      os.write("Status: 301\nLocation: " & path.deleteChars({'\r', '\n'}) &
        "/\n")
    else:
      discard loadDir(path, opath)
  elif res == 0 and (let ps = newPosixStream(path); ps != nil):
    os.loadFile(ps, stats)
  else:
    os.write("Cha-Control: ConnectionError FileNotFound")

main()

{.pop.} # raises: []
