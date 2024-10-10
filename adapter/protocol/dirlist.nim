import algorithm

import utils/strwidth
import utils/twtstr

type DirlistItemType* = enum
  ditFile, ditLink, ditDir

type DirlistItem* = object
  name*: string
  modified*: string
  case t*: DirlistItemType
  of ditLink:
    linkto*: string
  of ditFile:
    nsize*: int
  of ditDir:
    discard

type NameWidthTuple = tuple[name: string, width: int, item: ptr DirlistItem]

func makeDirlist*(items: seq[DirlistItem]): string =
  var names: seq[NameWidthTuple]
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
  names.sort(proc(a, b: NameWidthTuple): int = cmp(a.name, b.name))
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
