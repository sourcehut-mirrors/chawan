import std/algorithm
import std/os
import std/times

import dirlist

import utils/twtstr

proc loadDir(path, opath: string) =
  var path = path
  if path[^1] != '/': #TODO dos/windows
    path &= '/'
  var base = "file://" & opath
  if base[^1] != '/': #TODO dos/windows
    base &= '/'
  stdout.write("Content-Type: text/html\n\n")
  stdout.write("""
<HTML>
<HEAD>
<BASE HREF="""" & base & """">
<TITLE>Directory list of """ & path & """</TITLE>
</HEAD>
<BODY>
<H1>Directory list of """ & path & """</H1>
<PRE>
""")
  var fs: seq[(PathComponent, string)]
  for pc, file in walkDir(path, relative = true):
    fs.add((pc, file))
  fs.sort(cmp = proc(a, b: (PathComponent, string)): int = cmp(a[1], b[1]))
  var items: seq[DirlistItem]
  for (pc, file) in fs:
    let fullpath = path / file
    var info: FileInfo
    try:
      info = getFileInfo(fullpath, followSymlink = false)
    except OSError:
      continue
    let modified = $info.lastWriteTime.local().format("MMM/dd/yyyy HH:MM")
    case pc
    of pcDir:
      items.add(DirlistItem(
        t: ditDir,
        name: file,
        modified: modified
      ))
    of pcFile:
      items.add(DirlistItem(
        t: ditFile,
        name: file,
        modified: modified,
        nsize: int(info.size)
      ))
    of pcLinkToDir, pcLinkToFile:
      var target = expandSymlink(fullpath)
      if pc == pcLinkToDir:
        target &= '/'
      items.add(DirlistItem(
        t: ditLink,
        name: file,
        modified: modified,
        linkto: target
      ))
  stdout.write(makeDirlist(items))
  stdout.write("\n</PRE>\n</BODY>\n</HTML>\n")

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
    loadDir(path, opath)
  else:
    stdout.write("Cha-Control: ConnectionError FileNotFound")

main()
