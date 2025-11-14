{.push raises: [].}

import std/algorithm
import std/os
import std/strutils

import io/chafile
import types/opt
import utils/twtstr

type DirlistItemType = enum
  ditFile, ditLink, ditDir

type DirlistItem = ref object
  name: string # real name
  dname: string # display name
  modified: string # date last modified
  case t: DirlistItemType
  of ditLink:
    linkto: string
  of ditFile:
    nsize: int64
  of ditDir:
    discard

proc printDirlist(f: ChaFile; items: openArray[DirlistItem]): Opt[void] =
  ?f.writeLine("<a href=\"../\">[Upper Directory]</a><table>")
  for item in items:
    var path = percentEncode(item.name, PathPercentEncodeSet)
    if item.t == ditLink and item.linkto.len > 0 and item.linkto[^1] == '/':
      # If the target is a directory, treat it as a directory. (For FTP.)
      path &= '/'
    # this depends on a CSS hack in ua.css where for dirlist, hr gets a
    # proprietary border style and anchors are moved upwards by -1em.
    var line = "<tr>"
    line &= "<td><hr>"
    line &= "<a href=\"" & path & "\">" & htmlEscape(item.dname) & "</a>"
    line &= "<td>"
    line &= htmlEscape(item.modified)
    if item.t == ditFile:
      line &= ' ' & convertSize(uint64(max(item.nsize, 0)))
    elif item.t == ditLink:
      line &= " -> " & htmlEscape(item.linkto)
    line &= "</tr>"
    ?f.write(line)
  ok()

proc usage() =
  let stderr = cast[ChaFile](stderr)
  discard stderr.writeLine("Usage: dirlist2html [-t title]")
  quit(1)

proc addItem(items: var seq[DirlistItem]; item: DirlistItem) =
  if item.t == ditDir:
    item.name &= '/'
  item.dname = item.name
  if item.t == ditLink:
    item.dname &= '@'
  items.add(item)

proc skipTillSpace(line: openArray[char]; i: int): int =
  var i = i
  while i < line.len and line[i] != ' ':
    inc i
  return i

proc parseInput(f: ChaFile; items: var seq[DirlistItem]): Opt[void] =
  var line: string
  while ?f.readLine(line):
    if line.len == 0: continue
    var i = 10 # permission
    # link count
    i = line.skipBlanks(i)
    i = line.skipTillSpace(i)
    # owner
    i = line.skipBlanks(i)
    i = line.skipTillSpace(i)
    # group
    i = line.skipBlanks(i)
    i = line.skipTillSpace(i)
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
    i = line.skipTillSpace(i) # m
    i = line.skipBlanks(i)
    i = line.skipTillSpace(i) # d
    i = line.skipBlanks(i)
    i = line.skipTillSpace(i) # y
    let dates = line.substr(datestarti, i)
    inc i
    var j = line.len
    if line[^1] == '\r':
      dec j
    let name = line.substr(i, j - 1)
    if name == "." or name == "..":
      continue
    case line[0]
    of 'l': # link
      var linki = name.find(" -> ")
      if linki == -1:
        linki = name.len
      let linkfrom = name.substr(0, linki - 1)
      let linkto = name.substr(linki + 4) # you?
      items.addItem(DirlistItem(
        t: ditLink,
        name: linkfrom,
        modified: dates,
        linkto: linkto
      ))
    of 'd': # directory
      items.addItem(DirlistItem(
        t: ditDir,
        name: name,
        modified: dates
      ))
    else: # file
      items.addItem(DirlistItem(
        t: ditFile,
        name: name,
        modified: dates,
        nsize: nsize
      ))
  ok()

proc parseArgs(title: var string) =
  let H = paramCount()
  var i = 1
  while i <= H:
    let s = paramStr(i)
    if s == "":
      inc i
    if s[0] != '-':
      usage()
    for j in 1 ..< s.len:
      case s[j]
      of 't':
        inc i
        if i > H: usage()
        title = paramStr(i)
      else:
        usage()
    inc i

proc parse(): Opt[void] =
  var title = ""
  parseArgs(title)
  let stdout = cast[ChaFile](stdout)
  ?stdout.write("""
<!DOCTYPE html>
<head>
<title>""" & title.htmlEscape() & """</title>
</head>
<body>
<pre><h1>""" & title.htmlEscape() & """</h1>
""")
  var items: seq[DirlistItem] = @[]
  let stdin = cast[ChaFile](stdin)
  ?stdin.parseInput(items)
  items.sort(proc(a, b: DirlistItem): int =
    if a.t == ditDir and b.t != ditDir:
      return -1
    if a.t != ditDir and b.t == ditDir:
      return 1
    return cmp(a.dname, b.dname)
  )
  ?stdout.printDirlist(items)
  ?stdout.write("</pre></body>")
  ok()

proc main*() =
  discard parse()

{.pop.} # raises: []
