{.push raises: [].}

import std/posix

import lcgi

import js/libregexp
import utils/cowstr
import utils/lrewrap

proc parseSection(query: Str): tuple[page, section: Str] =
  var section = str("")
  if query.len > 0 and query[^1] == ')':
    for i in countdown(query.high, 0):
      if query[i] == '(':
        section = query.substr(i + 1, query.high - 1)
        break
  if section != "":
    return (query.substr(0, query.high - 2 - section.len), section)
  return (query, str(""))

proc processBackspace(line: Str): Str =
  var s = initGrowbuf()
  var i = 0
  var thiscs = 0 .. -1
  var bspace = false
  var inU = false
  var inB = false
  var pendingInU = false
  var pendingInB = false
  while i < line.len:
    # this is the same "sometimes works" algorithm as in ansi2html
    if line[i] == '\b' and thiscs.len > 0:
      bspace = true
      inc i
      continue
    let n = line.toOpenArray().pointLenAt(i)
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
      if pendingInU != inU:
        s &= (if inU: "</u>" else: "<u>")
        inU = pendingInU
      if pendingInB != inB:
        s &= (if inB: "</b>" else: "<b>")
        inB = pendingInB
      if thiscs.len > 0:
        let cs = case line[thiscs.a]
        of '&': str("&amp;")
        of '<': str("&lt;")
        of '>': str("&gt;")
        else: line.substr(thiscs.a, thiscs.b)
        s &= cs
      thiscs = i ..< i + n
      pendingInU = false
      pendingInB = false
    i += n
  if pendingInU != inU:
    s &= (if inU: "</u>" else: "<u>")
    inU = pendingInU
  if pendingInB != inB:
    s &= (if inB: "</b>" else: "<b>")
    inB = pendingInB
  if thiscs.len > 0:
    let cs = case line[thiscs.a]
    of '&': str("&amp;")
    of '<': str("&lt;")
    of '>': str("&gt;")
    else: line.substr(thiscs.a, thiscs.b)
    s &= cs
  if inU: s &= "</u>"
  if inB: s &= "</b>"
  s.toStr()

proc isCommand(paths: seq[Str]; name, s: Str): bool =
  for p in paths:
    if initStrM(p, name) == s:
      return true
  false

proc readErrorMsg(efile: AChaFile; line: var Str): Str =
  var msg = initGrowbuf()
  while true:
    # try to get the error message into an acceptable format
    if line.startsWith("man: "):
      line.delete(0..4)
    line = line.toLowerAscii().strip().replaceControls()
    if line.len > 0 and line[^1] == '.':
      line.setLen(line.high)
    if msg != "":
      msg &= ' '
    msg &= line
    if not efile.readLine(line).get(false):
      break
  msg.toStr()

const RegexStr =
  r"((https?|ftp)://[\w/~.-]+)|" &              # link, 1
  r"((mailto:|)(\w[\w.-]*@[\w-]+\.[\w.-]*))|" & # mail, 3
  r"((file:)?[/~][\w/~.-]+[\w/])|" &            # file, 6
  r"(#include((</?[bu]>|\s)*)&lt;([\w./-]+))|" &  # include, 8-11
  r"((</?[bu]>)*(\w[\w.-]*)(</?[bu]>)*(\([0-9nlx]\w*\)))" # man, 12-16

proc processManpage(ofile, efile: AChaFile; header, keyword: Str): Opt[void] =
  var line: Str
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
      cgiDie(ceFileNotFound, $efile.readErrorMsg(line))
  # skip formatting of line 0, like w3mman does
  # this is useful because otherwise the header would get caught in the man
  # regex, and that makes navigation slightly more annoying
  ?chaStdout.write(header)
  ?chaStdout.writeLine(line.processBackspace())
  var wasBlank = false
  # regexes partially from w3mman2html
  var re: Regex
  if not str(RegexStr).compileRegex({LRE_FLAG_GLOBAL, LRE_FLAG_UNICODE}, re):
    discard cast[ChaFile](chaStderr).writeLine(re.bytecode)
    quit(1)
  var paths: seq[Str] = @[]
  var ignoreMan = keyword.toUpperAscii()
  if ignoreMan == keyword or keyword.len == 1:
    ignoreMan = str("")
  for p in getEnvEmpty("PATH").split(':'):
    var i = p.high
    while i > 0 and p[i] == '/':
      dec i
    paths.add(initStrM(p.substr(0, i), '/'))
  while ?ofile.readLine(line):
    if line == "":
      if wasBlank:
        continue
      wasBlank = true
    else:
      wasBlank = false
    let line = line.processBackspace()
    var oline = initGrowbuf()
    var offset = 0
    var ctx = initContext(re)
    for ret in ctx.exec(line.toOpenArray()):
      if ret != 1:
        oline &= line.toOpenArray(offset, line.high)
        break
      let cap = ctx.cap(0)
      oline &= line.toOpenArray(offset, cap.s - 1)
      offset = cap.e
      var s = line.substr(cap.s, cap.e - 1)
      if ctx.cap(1).s >= 0: # link
        oline.addM("<a href='", s, "'>", s, "</a>")
      elif ctx.cap(3).s >= 0: # mail
        oline.addM("<a href='mailto:", s, "'>", s, "</a>")
      elif ctx.cap(6).s >= 0: # file
        let target = expandPath(s)
        if not fileExists(target) and not symlinkExists(target) and
            not dirExists(target):
          oline &= s
          continue
        let name = target.afterLast('/')
        if paths.isCommand(name, target):
          oline.addM("<a href='man:", name, "'>", s, "</a>")
        else:
          oline.addM("<a href='file:", target, "'>", s, "</a>")
      elif ctx.cap(8).s >= 0: # include
        const includePaths = [
          str("/usr/include/"),
          str("/usr/local/include/"),
          str("/usr/X11R6/include/"),
          str("/usr/X11/include/"),
          str("/usr/X/include/"),
          str("/usr/include/X11/")
        ]
        block notFound:
          let fileCap = ctx.cap(11)
          let file = line.substr(fileCap.s, fileCap.e - 1)
          let paddingCap = ctx.cap(9)
          for dir in includePaths:
            let path = initStrM(dir, file)
            if fileExists(path):
              oline.addM("#include",
                line.substr(paddingCap.s, paddingCap.e - 1),
               "&lt;<a href='file:", path, "'>", file, "</a>")
              break notFound
          oline &= s
      elif ctx.cap(12).s >= 0:
        let manCap = ctx.cap(14)
        let sectionCap = ctx.cap(16)
        let man = line.substr(manCap.s, manCap.e - 1)
        # ignore footers like MYPAGE(1)
        # (just to be safe, we also check if it's in paths too)
        if man == ignoreMan and not paths.isCommand(man.afterLast('/'), man):
          oline &= s
          continue
        let section = line.substr(sectionCap.s, sectionCap.e - 1)
        let cat = initStrM(man, section)
        s.setLen(s.len - section.len)
        oline.addM("<a href='man:", cat, "'>", s, "</a>", section)
    ?chaStdout.writeLine(oline.toOpenArray())
  ok()

proc myOpen(cmd: Str): Opt[tuple[ofile, efile: AChaFile]] =
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
    discard dup2(opipe[1], STDOUT_FILENO)
    discard dup2(epipe[1], STDERR_FILENO)
    discard execl("/bin/sh", "sh", "-c", cmd.toCString(), nil)
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

proc doMan(man, keyword, section: Str) =
  let sectionOpt = if section == "":
    str("")
  else:
    initStrM(' ', quoteShellPosix(section))
  let cmd = initStrM("MANCOLOR=1 GROFF_NO_SGR=1 MAN_KEEP_FORMATTING=1 ", man,
    sectionOpt, ' ', quoteShellPosix(keyword))
  let (ofile, efile) = myOpen(cmd).orDie(ceInternalError, "failed to run man")
  var manword = initGrowbuf(keyword)
  if section != "":
    manword.addM('(', section, ')')
  let header = initStrM("Content-Type: text/html\n\n<title>man ", manword,
    "</title><pre>")
  discard ofile.processManpage(efile, header, keyword)

proc doLocal(man, path: Str) =
  # Note: we intentionally do not use -l, because it is not supported on
  # various systems (at the very least FreeBSD, NetBSD, macOS).
  var cmd = initGrowbufM("MANCOLOR=1 GROFF_NO_SGR=1 MAN_KEEP_FORMATTING=1 ",
    man, ' ')
  # ...and this worked fine until OpenBSD intentionally broke it in 7.8,
  # saying this provides "better consistency with POSIX and traditional UNIX
  # and BSD man(1)".
  #
  # Note that POSIX hardly specifies anything about man, and certainly
  # doesn't talk about whether this case should be supported.  And while
  # "traditional UNIX" might not have supported raw paths, this was the
  # *only* portable way to do it until OBSD finally ruined it.
  #
  # Anyway, we add a platform-specific ifdef and move on.
  when defined(openbsd):
    cmd &= "-l "
  cmd &= quoteShellPosix(path)
  let (ofile, efile) = myOpen(cmd.toStr())
    .orDie(ceInternalError, "failed to run man")
  let header = initStrM("Content-Type: text/html\n\n<title>man -l ", path,
    "</title><pre>")
  discard ofile.processManpage(efile, header,
    keyword = path.afterLast('/').until('.'))

proc doKeyword(man, keyword, section: Str): Opt[void] =
  let sectionOpt = if section == "":
    str("")
  else:
    initStrM(" -s ", quoteShellPosix(section))
  let cmd = initStrM(man, sectionOpt, " -k ", quoteShellPosix(keyword))
  let (ofile, efile) = myOpen(cmd).orDie(ceInternalError, "failed to run man")
  var line: Str
  if not ofile.readLine(line).get(false):
    var wstatus = cint(0)
    if wait(addr wstatus) >= 0 and not WIFEXITED(wstatus) or
        WEXITSTATUS(wstatus) != 0:
      cgiDie(ceFileNotFound, $efile.readErrorMsg(line))
  ?chaStdout.write("Content-Type: text/html\n\n")
  ?chaStdout.write(initStrM("<title>man", sectionOpt, " -k ", keyword,
    "</title>\n"))
  ?chaStdout.write(initStrM("<h1>man", sectionOpt, " -k <b>", keyword,
    "</b></h1>\n"))
  ?chaStdout.write("<ul>")
  while true:
    if line.len == 0:
      ?chaStdout.write("\n")
      if not ofile.readLine(line).get(false):
        break
      continue
    # collect titles
    var titles: seq[Str] = @[]
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
      discard cast[ChaFile](chaStderr).writeLine("Error parsing line! " &
        $line)
      quit(1)
    let sectionText = line.substr(i, line.find(')', i))
    i += sectionText.len
    # create line
    var section = sectionText.until(',') # for multiple sections, take first
    if section[^1] != ')':
      section &= ")"
    var s = initGrowbuf("<li>")
    for i, title in titles:
      let title = title.htmlEscape()
      s.addM("<a href='man:", title, section, "'>", title, "</a>")
      if i < titles.high:
        s &= ", "
    s.addM(sectionText, line.substr(i))
    ?chaStdout.writeLine(s.toOpenArray())
    if not ofile.readLine(line).get(false):
      break
  ok()

proc main() =
  var man = getEnvEmpty("MANCHA_MAN")
  if man == "":
    block notfound:
      for s in [str("/usr/bin/man"), str("/bin/man"),
          str("/usr/local/bin/man")]:
        if fileExists(s) or symlinkExists(s):
          man = s
          break notfound
      man = str("/usr/bin/env man")
  var apropos = getEnvEmpty("MANCHA_APROPOS")
  if apropos == "":
    # on most systems, man is compatible with apropos (using -s syntax for
    # specifying sections).
    # ...not on FreeBSD :( here we have -S and MANSECT for specifying man
    # sections, and both are silently ignored when searching with -k. hooray.
    when not defined(freebsd):
      apropos = man
    else:
      apropos = "/usr/bin/apropos" # this is where it should be.
  if getArgvCount() != 3:
    cgiDie(ceInternalError, "usage: man [-rkl] [path]")
  let t = getArgvCString(1)
  let path = getArgv(2)
  if t == "-r":
    let (keyword, section) = parseSection(path)
    doMan(man, keyword, section)
  elif t == "-k":
    let (keyword, section) = parseSection(path)
    discard doKeyword(apropos, keyword, section)
  elif t == "-l":
    doLocal(man, path)
  else:
    discard chaStdout.writeLine("Cha-Control: ConnectionError 1 invalid scheme")

main()

{.pop.} # raises: []
