{.push raises: [].}

import std/os
import std/posix
import std/strutils

import lcgi

import monoucha/jsregex
import monoucha/libregexp

proc parseSection(query: string): tuple[page, section: string] =
  var section = ""
  if query.len > 0 and query[^1] == ')':
    for i in countdown(query.high, 0):
      if query[i] == '(':
        section = query.substr(i + 1, query.high - 1)
        break
  if section != "":
    return (query.substr(0, query.high - 2 - section.len), section)
  return (query, "")

func processBackspace(line: string): string =
  var s = ""
  var i = 0
  var thiscs = 0 .. -1
  var bspace = false
  var inU = false
  var inB = false
  var pendingInU = false
  var pendingInB = false
  template flushChar =
    if pendingInU != inU:
      s &= (if inU: "</u>" else: "<u>")
      inU = pendingInU
    if pendingInB != inB:
      s &= (if inB: "</b>" else: "<b>")
      inB = pendingInB
    if thiscs.len > 0:
      let cs = case line[thiscs.a]
      of '&': "&amp;"
      of '<': "&lt;"
      of '>': "&gt;"
      else: line.substr(thiscs.a, thiscs.b)
      s &= cs
    thiscs = i ..< i + n
    pendingInU = false
    pendingInB = false
  while i < line.len:
    # this is the same "sometimes works" algorithm as in ansi2html
    if line[i] == '\b' and thiscs.len > 0:
      bspace = true
      inc i
      continue
    let n = line.pointLenAt(i)
    if thiscs.len == 0:
      thiscs = i ..< i + n
      i += n
      continue
    if bspace and thiscs.len > 0:
      if line[i] == '_' and not pendingInU and line[thiscs.a] != '_':
        pendingInU = true
      elif line[thiscs.a] == '_' and not pendingInU and line[i] != '_':
        # underscore comes first; set thiscs to the current charseq
        thiscs = i ..< i + n
        pendingInU = true
      elif line[i] == '_' and line[thiscs.a] == '_':
        if inB and not pendingInB:
          pendingInB = true
        elif inU and not pendingInU:
          pendingInU = true
        elif not pendingInB:
          pendingInB = true
        else:
          pendingInU = true
      elif not pendingInB:
        pendingInB = true
      bspace = false
    else:
      flushChar
    i += n
  let n = 0
  flushChar
  if inU: s &= "</u>"
  if inB: s &= "</b>"
  move(s)

proc isCommand(paths: seq[string]; name, s: string): bool =
  for p in paths:
    if p & name == s:
      return true
  false

iterator myCaptures(res: var RegexResult; i: int): RegexCapture =
  for cap in res.captures.mitems:
    yield cap[i]

proc readErrorMsg(efile: AChaFile; line: var string): string =
  var msg = ""
  while true:
    # try to get the error message into an acceptable format
    if line.startsWith("man: "):
      line.delete(0..4)
    line = line.toLower().strip().replaceControls()
    if line.len > 0 and line[^1] == '.':
      line.setLen(line.high)
    if msg != "":
      msg &= ' '
    msg &= line
    if not efile.readLine(line).get(false):
      break
  move(msg)

type RegexType = enum
  rtLink = r"(https?|ftp)://[\w/~.-]+"
  rtMail = r"(mailto:|)(\w[\w.-]*@[\w-]+\.[\w.-]*)"
  rtFile = r"(file:)?[/~][\w/~.-]+[\w/]"
  rtInclude = r"#include(</?[bu]>|\s)*&lt;([\w./-]+)"
  rtMan = r"(</?[bu]>)*(\w[\w.-]*)(</?[bu]>)*(\([0-9nlx]\w*\))"

proc updateOffsets(map: var array[RegexType, RegexResult]; len: int;
    cap: RegexCapture; ourType: RegexType) =
  let offset = len - (cap.e - cap.s)
  var first = true
  for res in map.toOpenArray(ourType, RegexType.high).mitems:
    var toDel: seq[int] = @[]
    for i, icap in res.captures.mpairs:
      var overlap = false
      for it in icap.mitems:
        if not first and it.e > cap.s and it.s < cap.e:
          overlap = true
        elif it.s > cap.s:
          it.s += offset
          it.e += offset
      if overlap:
        toDel.add(i)
    for i in countdown(toDel.high, 0):
      res.captures.delete(toDel[i])
    first = false

proc processManpage(ofile, efile: AChaFile; header, keyword: string):
    Opt[void] =
  var line = ""
  # The "right thing" would be to check for the error code and output error
  # messages accordingly. Unfortunately that would prevent us from streaming
  # the output, so what we do instead is:
  # * read first line
  # * if EOF, probably an error; read all of stderr and print it
  # * if not EOF, probably not an error; print stdout as a document and ignore
  #   stderr
  # This may break in some edge cases, e.g. if man writes a long error
  # message to stdout. But it's much better (faster) than not streaming the
  # output.
  if not ofile.readLine(line).get(false):
    var wstatus: cint
    discard wait(addr wstatus)
    if not WIFEXITED(wstatus) or WEXITSTATUS(wstatus) != 0:
      stdout.fwrite("Cha-Control: ConnectionError 4 " &
        efile.readErrorMsg(line))
      quit(1)
  # skip formatting of line 0, like w3mman does
  # this is useful because otherwise the header would get caught in the man
  # regex, and that makes navigation slightly more annoying
  let stdout = cast[ChaFile](stdout)
  ?stdout.write(header)
  ?stdout.writeLine(line.processBackspace())
  var wasBlank = false
  # regexes partially from w3mman2html
  var reMap = array[RegexType, Regex].default
  for t, re in reMap.mpairs:
    let x = ($t).compileRegex({LRE_FLAG_GLOBAL, LRE_FLAG_UNICODE})
    if x.isErr:
      stderr.fwrite($t & ": " & x.error)
      quit(1)
    re = x.get
  var paths: seq[string] = @[]
  var ignoreMan = keyword.toUpperAscii()
  if ignoreMan == keyword or keyword.len == 1:
    ignoreMan = ""
  for p in getEnv("PATH").split(':'):
    var i = p.high
    while i > 0 and p[i] == '/':
      dec i
    paths.add(p.substr(0, i) & "/")
  while ?ofile.readLine(line):
    if line == "":
      if wasBlank:
        continue
      wasBlank = true
    else:
      wasBlank = false
    var line = line.processBackspace()
    var res = array[RegexType, RegexResult].default
    for t, re in reMap.mpairs:
      res[t] = re.exec(line)
    for cap in res[rtLink].myCaptures(0):
      let s = line[cap.s..<cap.e]
      let link = "<a href='" & s & "'>" & s & "</a>"
      line[cap.s..<cap.e] = link
      res.updateOffsets(link.len, cap, rtLink)
    for cap in res[rtMail].myCaptures(2):
      let s = line[cap.s..<cap.e]
      let link = "<a href='mailto:" & s & "'>" & s & "</a>"
      line[cap.s..<cap.e] = link
      res.updateOffsets(link.len, cap, rtMail)
    for cap in res[rtFile].myCaptures(0):
      let s = line[cap.s..<cap.e]
      let target = s.expandTilde()
      if not fileExists(target) and not symlinkExists(target) and
          not dirExists(target):
        continue
      let name = target.afterLast('/')
      let link = if paths.isCommand(name, target):
        "<a href='man:" & name & "'>" & s & "</a>"
      else:
        "<a href='file:" & target & "'>" & s & "</a>"
      line[cap.s..<cap.e] = link
      res.updateOffsets(link.len, cap, rtFile)
    for cap in res[rtInclude].myCaptures(2):
      let s = line[cap.s..<cap.e]
      const includePaths = [
        "/usr/include/",
        "/usr/local/include/",
        "/usr/X11R6/include/",
        "/usr/X11/include/",
        "/usr/X/include/",
        "/usr/include/X11/"
      ]
      for path in includePaths:
        let file = path & s
        if fileExists(file):
          let link = "<a href='file:" & file & "'>" & s & "</a>"
          line[cap.s..<cap.e] = link
          res.updateOffsets(link.len, cap, rtInclude)
          break
    var offset = 0
    for cap in res[rtMan].captures.mitems:
      cap[0].s += offset
      cap[0].e += offset
      var manCap = cap[2]
      manCap.s += offset
      manCap.e += offset
      var secCap = cap[4]
      secCap.s += offset
      secCap.e += offset
      let man = line[manCap.s..<manCap.e]
      # ignore footers like MYPAGE(1)
      # (just to be safe, we also check if it's in paths too)
      if man == ignoreMan and not paths.isCommand(man.afterLast('/'), man):
        continue
      let cat = man & line[secCap.s..<secCap.e]
      let link = "<a href='man:" & cat & "'>" & man & "</a>"
      line[manCap.s..<manCap.e] = link
      offset += link.len - (manCap.e - manCap.s)
    ?stdout.writeLine(line)
  ok()

proc myOpen(cmd: string): Opt[tuple[ofile, efile: AChaFile]] =
  var opipe = array[2, cint].default
  var epipe = array[2, cint].default
  if pipe(opipe) == -1 or pipe(epipe) == -1:
    return err()
  case fork()
  of -1: # fail
    return err()
  of 0: # child
    discard close(opipe[0])
    discard close(epipe[0])
    discard dup2(opipe[1], stdout.getFileHandle())
    discard dup2(epipe[1], stderr.getFileHandle())
    discard execl("/bin/sh", "sh", "-c", cstring(cmd), nil)
    exitnow(1)
  else: # parent
    discard close(opipe[1])
    discard close(epipe[1])
    if ofile := newPosixStream(opipe[0]).afdopen("r"):
      if efile := newPosixStream(epipe[0]).afdopen("r"):
        return ok((ofile, efile))
    discard close(opipe[0])
    discard close(epipe[0])
    return err()

proc doMan(man, keyword, section: string) =
  let sectionOpt = if section == "": "" else: ' ' & quoteShellPosix(section)
  let cmd = "MANCOLOR=1 GROFF_NO_SGR=1 MAN_KEEP_FORMATTING=1 " &
    man & sectionOpt & ' ' & quoteShellPosix(keyword)
  let (ofile, efile) = myOpen(cmd)
    .orDie("InternalError", "failed to run " & cmd)
  var manword = keyword
  if section != "":
    manword &= '(' & section & ')'
  discard ofile.processManpage(efile, header = """Content-Type: text/html

<title>man """ & manword & """</title>
<pre>""", keyword = keyword)

proc doLocal(man, path: string) =
  # Note: we intentionally do not use -l, because it is not supported on
  # various systems (at the very least FreeBSD, NetBSD).
  let cmd = "MANCOLOR=1 GROFF_NO_SGR=1 MAN_KEEP_FORMATTING=1 " &
    man & ' ' & quoteShellPosix(path)
  let (ofile, efile) = myOpen(cmd)
    .orDie("InternalError", "failed to run " & cmd)
  discard ofile.processManpage(efile, header = """Content-Type: text/html

<title>man -l """ & path & """</title>
<pre>""", keyword = path.afterLast('/').until('.'))

proc doKeyword(man, keyword, section: string): Opt[void] =
  let sectionOpt = if section == "": "" else: " -s " & quoteShellPosix(section)
  let cmd = man & sectionOpt & " -k " & quoteShellPosix(keyword)
  let (ofile, efile) = myOpen(cmd)
    .orDie("InternalError", "failed to run " & cmd)
  var line: string
  if not ofile.readLine(line).get(false):
    var wstatus = cint(0)
    if wait(addr wstatus) >= 0 and not WIFEXITED(wstatus) or
        WEXITSTATUS(wstatus) != 0:
      stdout.fwrite("Cha-Control: ConnectionError 4 " &
        efile.readErrorMsg(line))
      quit(1)
  let stdout = cast[ChaFile](stdout)
  ?stdout.write("Content-Type: text/html\n\n")
  ?stdout.write("<title>man" & sectionOpt & " -k " & keyword & "</title>\n")
  ?stdout.write("<h1>man" & sectionOpt & " -k <b>" & keyword & "</b></h1>\n")
  ?stdout.write("<ul>")
  while true:
    if line.len == 0:
      ?stdout.write("\n")
      if not ofile.readLine(line).get(false):
        break
      continue
    # collect titles
    var titles: seq[string] = @[]
    var i = 0
    while true:
      let title = line.until({'(', ','}, i)
      i += title.len
      titles.add(title)
      if i >= line.len or line[i] == '(':
        break
      i = line.skipBlanks(i + 1)
    # collect section
    if line[i] != '(':
      discard stdout.write("Error parsing line! " & line)
      quit(1)
    let sectionText = line.substr(i, line.find(')', i))
    i += sectionText.len
    # create line
    var section = sectionText.until(',') # for multiple sections, take first
    if section[^1] != ')':
      section &= ')'
    var s = "<li>"
    for i, title in titles:
      let title = title.htmlEscape()
      s &= "<a href='man:" & title & section & "'>" & title & "</a>"
      if i < titles.high:
        s &= ", "
    s &= sectionText
    s &= line.substr(i)
    ?stdout.writeLine(s)
    if not ofile.readLine(line).get(false):
      break
  ok()

proc main() =
  var man = getEnv("MANCHA_MAN")
  if man == "":
    block notfound:
      for s in ["/usr/bin/man", "/bin/man", "/usr/local/bin/man"]:
        if fileExists(s) or symlinkExists(s):
          man = s
          break notfound
      man = "/usr/bin/env man"
  var apropos = getEnv("MANCHA_APROPOS")
  if apropos == "":
    # on most systems, man is compatible with apropos (using -s syntax for
    # specifying sections).
    # ...not on FreeBSD :( here we have -S and MANSECT for specifying man
    # sections, and both are silently ignored when searching with -k. hooray.
    when not defined(freebsd):
      apropos = man
    else:
      apropos = "/usr/bin/apropos" # this is where it should be.
  let path = getEnv("MAPPED_URI_PATH")
  let scheme = getEnv("MAPPED_URI_SCHEME")
  if scheme == "man":
    let (keyword, section) = parseSection(path)
    doMan(man, keyword, section)
  elif scheme == "man-k":
    let (keyword, section) = parseSection(path)
    discard doKeyword(apropos, keyword, section)
  elif scheme == "man-l":
    doLocal(man, path)
  else:
    stdout.fwrite("Cha-Control: ConnectionError 1 invalid scheme")

main()

{.pop.} # raises: []
