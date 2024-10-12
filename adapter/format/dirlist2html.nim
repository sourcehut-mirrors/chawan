import std/algorithm
import std/options
import std/os
import std/strutils

import utils/strwidth
import utils/twtstr

type DirlistItemType = enum
  ditFile, ditLink, ditDir

type DirlistItem = object
  name: string
  modified: string
  case t: DirlistItemType
  of ditLink:
    linkto: string
  of ditFile:
    nsize: int
  of ditDir:
    discard

type NameWidthTuple = tuple[name: string, width: int, item: ptr DirlistItem]

func makeDirlist(items: seq[DirlistItem]): string =
  var names: seq[NameWidthTuple] = @[]
  var maxw = 20
  for item in items:
    var name = item.name
    if item.t == ditLink:
      name &= '@'
    elif item.t == ditDir:
      name &= '/'
    let w = name.width()
    maxw = max(w, maxw)
    names.add((name, w, unsafeAddr item))
  names.sort(proc(a, b: NameWidthTuple): int =
    if a.item.t == ditDir and b.item.t != ditDir:
      return -1
    if a.item.t != ditDir and b.item.t == ditDir:
      return 1
    return cmp(a.name, b.name)
  )
  var outs = "<A HREF=\"../\">[Upper Directory]</A>\n"
  for (name, width, itemp) in names.mitems:
    let item = itemp[]
    var path = percentEncode(item.name, PathPercentEncodeSet)
    if item.t == ditLink:
      if item.linkto.len > 0 and item.linkto[^1] == '/':
        # If the target is a directory, treat it as a directory. (For FTP.)
        path &= '/'
    elif item.t == ditDir:
      path &= '/'
    var line = "<A HREF=\"" & path & "\">" & htmlEscape(name) & "</A>"
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
    outs &= line & '\n'
  return outs

proc usage() =
  stderr.write("Usage: dirlist2html [-t title]\n")
  quit(1)

proc main() =
  # parse args
  let H = paramCount()
  var i = 1
  var title = ""
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
        title = paramStr(i).percentDecode()
      else:
        usage()
    inc i
  if title != "":
    stdout.write("""
<!DOCTYPE html>
<head>
<title>""" & title.htmlEscape() & """</title>
</head>
<body>
<h1>""" & title.htmlEscape() & """</h1>
<pre>""")
  var items: seq[DirlistItem] = @[]
  var line: string
  while stdin.readLine(line):
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
    var j = line.len
    if line[^1] == '\r':
      dec j
    let name = line.substr(i, j - 1)
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
  stdout.write("</pre></body>")

main()
