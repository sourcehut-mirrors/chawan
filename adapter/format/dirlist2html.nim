import std/algorithm
import std/options
import std/os
import std/posix
import std/strutils

import types/opt
import utils/twtstr

type DirlistItemType = enum
  ditFile, ditLink, ditDir

type DirlistItem = ref object
  name: string # real name
  dname: string # display name
  width: int # display name width
  modified: string # date last modified
  case t: DirlistItemType
  of ditLink:
    linkto: string
  of ditFile:
    nsize: int
  of ditDir:
    discard

proc printDirlist(f: File; items: seq[DirlistItem]; maxw: int) =
  f.writeLine("<a href=\"../\">[Upper Directory]</a>")
  for item in items:
    var path = percentEncode(item.name, PathPercentEncodeSet)
    if item.t == ditLink and item.linkto.len > 0 and item.linkto[^1] == '/':
      # If the target is a directory, treat it as a directory. (For FTP.)
      path &= '/'
    var line = "<a href=\"" & path & "\">" & htmlEscape(item.dname) & "</a>"
    var width = item.width
    while width <= maxw:
      if width mod 2 == 0:
        line &= ' '
      else:
        line &= '.'
      inc width
    if line[^1] != ' ':
      line &= ' '
    line &= htmlEscape(item.modified)
    if item.t == ditFile:
      line &= ' ' & convertSize(item.nsize)
    elif item.t == ditLink:
      line &= " -> " & htmlEscape(item.linkto)
    f.writeLine(line)

proc usage() =
  stderr.write("Usage: dirlist2html [-t title]\n")
  quit(1)

# I'll just assume that wchar_t is int32, as it should be on any sane
# system.

type wchar_t {.importc.} = int32

proc wcwidth(wc: wchar_t): cint {.importc, header: "<wchar.h>".}

proc width(s: string): int =
  var res: cint = 0
  for u in s.points:
    res += wcwidth(wchar_t(u))
  return int(res)

proc addItem(items: var seq[DirlistItem]; item: DirlistItem; maxw: var int) =
  if item.t == ditDir:
    item.name &= '/'
  item.dname = item.name
  if item.t == ditLink:
    item.dname &= '@'
  item.width = item.dname.width()
  maxw = max(item.width, maxw)
  items.add(item)

proc parseInput(f: File; items: var seq[DirlistItem]; maxw: var int) =
  # wcwidth wants a UTF-8 locale.
  # I don't know how portable this is, but the worst thing that can
  # happen is that too many dots are printed.
  let thisUTF8 = ($setlocale(LC_CTYPE, nil)).until('.') & ".UTF-8"
  discard setlocale(LC_CTYPE, cstring(thisUTF8))
  var line: string
  while f.readLine(line):
    if line.len == 0: continue
    var i = 10 # permission
    template skip_till_space =
      while i < line.len and line[i] != ' ':
        inc i
    # link count
    i = line.skipBlanks(i)
    skip_till_space
    # owner
    i = line.skipBlanks(i)
    skip_till_space
    # group
    i = line.skipBlanks(i)
    skip_till_space
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
      ), maxw)
    of 'd': # directory
      items.addItem(DirlistItem(
        t: ditDir,
        name: name,
        modified: dates
      ), maxw)
    else: # file
      items.addItem(DirlistItem(
        t: ditFile,
        name: name,
        modified: dates,
        nsize: int(nsize)
      ), maxw)

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

proc main() =
  var title = ""
  parseArgs(title)
  stdout.write("""
<!DOCTYPE html>
<head>
<title>""" & title.htmlEscape() & """</title>
</head>
<body>
<h1>""" & title.htmlEscape() & """</h1>
<pre>""")
  var items: seq[DirlistItem] = @[]
  var maxw = 20
  stdin.parseInput(items, maxw)
  items.sort(proc(a, b: DirlistItem): int =
    if a.t == ditDir and b.t != ditDir:
      return -1
    if a.t != ditDir and b.t == ditDir:
      return 1
    return cmp(a.dname, b.dname)
  )
  stdout.printDirlist(items, maxw)
  stdout.write("</pre></body>")

main()
