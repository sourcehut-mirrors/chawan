import std/os
import std/times

import utils/twtstr

proc loadDir(path, opath: string) =
  let title = ("Directory list of " & path).mimeQuote()
  stdout.write("Content-Type: text/x-dirlist;title=" & title & "\n\n")
  for pc, file in walkDir(path, relative = true):
    let fullpath = path / file
    var info: FileInfo
    try:
      info = getFileInfo(fullpath, followSymlink = false)
    except OSError:
      continue
    const TypeMap = [
      pcFile: '-',
      pcLinkToFile: 'l',
      pcDir: 'd',
      pcLinkToDir: 'l'
    ]
    var line = $TypeMap[pc]
    const PermMap = {
      fpUserRead: 'r',
      fpUserWrite: 'w',
      fpUserExec: 'x',
      fpGroupRead: 'r',
      fpGroupWrite: 'w',
      fpGroupExec: 'x',
      fpOthersRead: 'r',
      fpOthersWrite: 'w',
      fpOthersExec: 'x'
    }
    for (perm, c) in PermMap:
      if perm in info.permissions:
        line &= c
      else:
        line &= '-'
    line &= ' ' & $info.linkCount & ' '
    line &= "0 " # owner, currently unused
    line &= "0 " # group, currently unused
    line &= $info.size & ' '
    #TODO if new enough, send time instead of year
    let modified = $info.lastWriteTime.local().format("MMM dd yyyy")
    line &= $modified & ' '
    if pc in {pcLinkToDir, pcLinkToFile}:
      var target = expandSymlink(fullpath)
      if pc == pcLinkToDir and target.len == 0 or target[^1] != '/':
        target &= '/'
      line &= file & " -> " & target
    else:
      line &= file
    stdout.writeLine(line)

proc loadFile(f: File) =
  # No headers, we'll let the browser figure out the file type.
  stdout.write("\n")
  const BufferSize = 16384
  var buffer {.noinit.}: array[BufferSize, char]
  while true:
    let n = f.readBuffer(addr buffer[0], BufferSize)
    if n == 0:
      break
    let n2 = stdout.writeBuffer(addr buffer[0], n)
    if n2 < n or n < BufferSize:
      break

proc main() =
  let opath = getEnv("MAPPED_URI_PATH")
  let path = percentDecode(opath)
  var f: File
  if f.open(path, fmRead):
    loadFile(f)
  elif dirExists(path):
    if path[^1] != '/':
      stdout.write("Status: 301\nLocation: " & path & "/\n")
    else:
      loadDir(path, opath)
  else:
    stdout.write("Cha-Control: ConnectionError FileNotFound")

main()
