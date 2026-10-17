# See https://www.rfc-editor.org/rfc/rfc1524

{.push raises: [].}

when NimMajor >= 2:
  import std/assertions
import std/posix

import io/chafile
import io/dynstream
import js/jsref
import js/libregexp
import server/url
import utils/chaos
import utils/cowstr
import utils/lrewrap
import utils/opt
import utils/tabutil
import utils/twtstr

type
  MailcapParser* = object
    line: int
    lenient*: bool # accept extensions without x-?  (for browsecap)
    error*: Str

  MailcapFlag* = enum
    mfNeedsterminal = "needsterminal"
    mfCopiousoutput = "copiousoutput" # last standard flag
    mfHtmloutput = "htmloutput" # w3m extension
    mfAnsioutput = "ansioutput" # Chawan extension
    mfSaveoutput = "saveoutput" # Chawan extension
    mfNeedsstyle = "needsstyle" # Chawan extension
    mfNeedsimage = "needsimage" # Chawan extension
    mfResource = "resource" # Chawan extension
    mfType = "type" # w3mmee extension
    mfNetpath = "netpath" # w3mmee extension
    mfCgioutput = "cgioutput" # w3mmee extension
    mfUri = "uri" # w3mmee extension
    mfInternal = "internal" # w3mmee extension
    mfUrimethodmap = "internal-urimethodmap" # internal field, do not use

  NamedFieldType* = enum
    nfTest = "test"
    nfNametemplate = "nametemplate"
    nfEdit = "edit" # last standard field
    nfMatch = "match" # w3mmee extension
    nfNcMatch = "nc-match" # w3mmee extension

  NamedField = ref object
    t: NamedFieldType
    value*: Str
    next: NamedField

  MailcapEntry* = ref object
    cmd*: Str
    flags*: set[MailcapFlag]
    id*: uint32 # actual count in mailcap
    fieldsHead: NamedField

  MailcapList {.final.} = ref object of StrMapItem
    entries*: seq[MailcapEntry] # all entries (inc. for subtypes)
    resource*: seq[MailcapEntry] # x-resource entries only
    next: MailcapList # used for chaining lists with identical main types

  Mailcap* = object
    map: StrMap
    len: uint32 # number of entries

iterator fields(entry: MailcapEntry): NamedField =
  var field = entry.fieldsHead
  while field != nil:
    yield field
    field = field.next

proc getOrDefault*(mailcap: Mailcap; t: openArray[char]): MailcapList =
  MailcapList(mailcap.map.getOrDefault(t))

proc put(mailcap: var Mailcap; list: MailcapList) =
  mailcap.map.put(list)

proc put(mailcap: var Mailcap; t: Str): MailcapList =
  let list = MailcapList(s: t)
  mailcap.put(list)
  list

proc getList*(mailcap: Mailcap; t: Str): MailcapList =
  let list = mailcap.getOrDefault(t.toOpenArray())
  if list != nil:
    return list
  let i = t.findOrLen('/')
  mailcap.getOrDefault(t.toOpenArray(0, i - 1))

proc isHtmlOrText(s: Str): bool =
  s == "text/html" or s == "text/plain"

proc add(list: MailcapList; entry: MailcapEntry) =
  list.entries.add(entry)
  if mfResource in entry.flags:
    list.resource.add(entry)

proc getListOrAdd(mailcap: var Mailcap; t: Str): MailcapList =
  let list0 = mailcap.getOrDefault(t.toOpenArray())
  if list0 != nil:
    return list0
  let list = mailcap.put(t)
  let slash = t.find('/')
  if slash >= 0:
    var main = t.substr(0, slash - 1)
    var mainList = mailcap.getList(main)
    if mainList == nil:
      # ensure a wildcard type exists for all subtypes.  (if we were to add
      # main types after subtypes, then we'd have troubles linking them
      # together)
      mainList = MailcapList(s: move(main))
      mailcap.put(mainList)
    else: # add existing wildcard entries
      if t.isHtmlOrText():
        # these types only accept x-type
        for entry in mainList.entries:
          if mfType in entry.flags:
            list.entries.add(entry)
      else:
        list.entries.add(mainList.entries)
    # link together lists of the same main type so we can efficiently add
    # further wildcard entries
    list.next = mainList.next
    mainList.next = list
  list

proc add(mailcap: var Mailcap; entry: MailcapEntry; t: Str) =
  if t.isHtmlOrText() and mfType notin entry.flags:
    return
  var list = mailcap.getListOrAdd(t)
  let slash = t.find('/')
  if slash == -1: # wildcard; add to sub-entries too
    while list != nil:
      list.add(entry)
      list = list.next
  else: # add to this entry only
    list.add(entry)

proc find*(entry: MailcapEntry; t: NamedFieldType): NamedField =
  for field in entry.fields:
    if field.t == t:
      return field
  nil

proc toStr*(entry: MailcapEntry; t: Str): Str =
  var s = initGrowbufM(t, ';', entry.cmd)
  for flag in MailcapFlag:
    if flag in entry.flags:
      s.addM(';', flag.toStr())
  for field in entry.fields:
    # if value is regex, then the source is until the first NUL
    s.addM(';', field.t.toStr(), '=', field.value.toCString())
  s.toStr()

template err(state: MailcapParser; msg: Str): untyped =
  state.error = msg
  err()

proc consumeTypeField(state: var MailcapParser; line: openArray[char];
    outs: var Str): Opt[int] =
  var slash = -1
  var n = 0
  var buf = initGrowbuf()
  while n < line.len:
    let c = line[n]
    if c in AsciiWhitespace + {';'}:
      break
    if c == '/':
      if slash >= 0:
        return state.err(str("too many slash characters"))
      slash = buf.len
    elif c notin AsciiAlphaNumeric + {'-', '.', '*', '_', '+'}:
      return state.err(initStrM("invalid character in type field: ", c))
    buf &= c.toLowerAscii()
    inc n
  if slash >= 0 and slash + 2 == buf.len and buf[slash + 1] == '*':
    # normalize type/* to type without a subtype (implicit-wild)
    buf.setLen(slash)
  n = line.skipBlanks(n)
  if n >= line.len or line[n] != ';':
    return state.err(str("semicolon not found"))
  outs = buf.toStr()
  ok(n + 1)

proc consumeCommand(state: var MailcapParser; line: openArray[char];
    outs: var Str; n: int): Opt[int] =
  var cmd = initGrowbuf()
  var n = line.skipBlanks(n)
  var quoted = false
  while n < line.len:
    let c = line[n]
    if not quoted:
      if c == '\r':
        continue
      if c == ';':
        break
      if c == '\\':
        quoted = true
        # fall through; backslash will be parsed again in unquoteCommand
      elif c in Controls:
        return state.err(initStrM("invalid character in command: ", c))
    else:
      quoted = false
    cmd &= c
    inc n
  outs = cmd.toStr()
  ok(n)

proc addNamedField(entry: MailcapEntry; t: NamedFieldType;
    fieldsTail: var NamedField; cmd: var Str): Err[Str] =
  var s = move(cmd)
  if t in {nfMatch, nfNcMatch}:
    let flags = if t == nfNcMatch: {LRE_FLAG_IGNORECASE} else: {}
    var re: Regex
    if not compileRegex(s, flags, re):
      return err(re.bytecode)
    s &= "\0"
    s &= re.bytecode
  let field = entry.find(t)
  if field != nil:
    field.value = move(s)
  else:
    let field = NamedField(t: t, value: move(s))
    if fieldsTail == nil:
      entry.fieldsHead = field
    else:
      fieldsTail.next = field
    fieldsTail = field
  ok()

proc allowField(state: MailcapParser; standard: bool; i: int): bool =
  if i == 2: # x- prefix: only allowed for extensions
    return not standard
  # no x- prefix: allowed for all fields in browsecap, and standard fields
  # only in mailcap
  return standard or state.lenient

proc consumeField(state: var MailcapParser; line: openArray[char];
    entry: MailcapEntry; n: int; fieldsTail: var NamedField): Opt[int] =
  var n = line.skipBlanks(n)
  var s = initGrowbuf()
  while n < line.len:
    let c = line[n]
    inc n
    case c
    of ';':
      break
    of '\r':
      continue
    of '=':
      var cmd: Str
      n = ?state.consumeCommand(line, cmd, n)
      while s.len > 0 and s[^1] in AsciiWhitespace:
        s.setLen(s.high)
      let i = if s.toOpenArray().startsWith("x-"): 2 else: 0
      if t := parseEnumNoCase[NamedFieldType](s.toOpenArray(i, s.high)):
        if state.allowField(t <= nfEdit, i):
          let res = entry.addNamedField(t, fieldsTail, cmd)
          if res.isErr:
            return state.err(res.error)
      return ok(n)
    elif c in Controls:
      return state.err(initStrM("invalid character in field: ", c))
    else:
      s &= c
  while s.len > 0 and s[^1] in AsciiWhitespace:
    s.setLen(s.high)
  let i = if s.toOpenArray().startsWith("x-"): 2 else: 0
  if x := parseEnumNoCase[MailcapFlag](s.toOpenArray(i, s.high)):
    if state.allowField(x <= mfCopiousoutput, i):
      entry.flags.incl(x)
  return ok(n)

proc parseEntry*(state: var MailcapParser; line: openArray[char];
    entry: MailcapEntry; t: var Str): Opt[void] =
  var n = ?state.consumeTypeField(line, t)
  n = ?state.consumeCommand(line, entry.cmd, n)
  var fieldsTail: NamedField
  while n < line.len:
    n = ?state.consumeField(line, entry, n, fieldsTail)
  ok()

proc parseBuiltin*(mailcap: var Mailcap; buf: openArray[char]) =
  var state = MailcapParser(line: 1, lenient: true)
  for line in buf.split('\n'):
    if line.len <= 0:
      continue
    let entry = MailcapEntry(id: mailcap.len)
    inc mailcap.len
    var t: Str
    let res = state.parseEntry(line.toOpenArray(), entry, t)
    doAssert res.isOk, $state.error
    mailcap.add(entry, t)

proc parseMailcap(state: var MailcapParser; mailcap: var Mailcap;
    file: AChaFile): Opt[void] =
  var line: Growbuf
  while file.readLine(line).get(false):
    if line.len <= 0 or line[0] == '#':
      inc state.line
      continue
    while true:
      if line.len > 0 and line[^1] == '\r':
        line.setLen(line.high)
      if line.len == 0 or line[^1] != '\\':
        break
      line.setLen(line.high) # trim backslash
      if not ?file.readLineAppend(line):
        break
    let entry = MailcapEntry(id: mailcap.len)
    inc mailcap.len
    var t: Str
    ?state.parseEntry(line.toOpenArray(), entry, t)
    mailcap.add(entry, t)
    inc state.line
  return ok()

proc parseMailcap*(mailcap: var Mailcap; path: Str; lenient = false):
    Err[Str] =
  let file0 = chafile.afopen(path, "r")
  if file0.isErr:
    return ok()
  let file = file0.get
  var state = MailcapParser(line: 1, lenient: lenient)
  let res = state.parseMailcap(mailcap, file)
  if res.isErr:
    return err(initStrM(path, '(', state.line.toStr(), "): ", state.error))
  ok()

# Mostly based on w3m's mailcap quote/unquote
type UnquoteState = enum
  usNormal, usQuoted, usPerc, usAttr, usAttrQuoted, usDollar

proc unquoteCommand*(ecmd, contentType, outpath: Str; url: URL;
    canpipe: var bool; line = -1; uriparams = false; shellQuote = true): Str =
  var cmd = initGrowbuf()
  var attrname = initGrowbuf()
  var state = usNormal
  var qs = qsNormal # current quote state
  var qss: seq[QuoteState] = @[] # quote state stack
  for c in ecmd:
    case state
    of usQuoted:
      cmd &= c
      state = usNormal
    of usAttrQuoted:
      attrname &= c.toLowerAscii()
      state = usAttr
    of usNormal, usDollar:
      let prevDollar = state == usDollar
      state = usNormal
      case c
      of '%':
        state = usPerc
      of '\\':
        state = usQuoted
      of '\'':
        if qs == qsSingleQuoted:
          qs = qsNormal
        else:
          qs = qsSingleQuoted
        cmd &= c
      of '"':
        if qs == qsDoubleQuoted:
          qs = qsNormal
        else:
          qs = qsDoubleQuoted
        cmd &= c
      of '$':
        if qs != qsSingleQuoted:
          state = usDollar
        cmd &= c
      of '(':
        if prevDollar:
          qss.add(qs)
          qs = qsNormal
        cmd &= c
      of ')':
        if qs != qsSingleQuoted:
          if qss.len > 1:
            qs = qss.pop()
          else:
            # mismatched parens; probably an invalid shell command...
            qs = qsNormal
        cmd &= c
      else:
        cmd &= c
    of usPerc:
      case c
      of '%': cmd &= c
      of 's':
        if shellQuote:
          cmd &= quoteFile(outpath, qs)
        else:
          cmd &= outpath
        canpipe = false
      of 't':
        let shortType = contentType.untilLower(';')
        if shellQuote:
          cmd &= quoteFile(shortType, qs)
        else:
          cmd &= shortType
      of 'u': # Netscape extension
        if url != nil: # nil in getEditorCommand
          if shellQuote:
            cmd &= quoteFile(url.toStr(), qs)
          else:
            cmd &= url.toStr().toOpenArray()
      of 'h': # w3mmee extension
        if url != nil:
          if shellQuote:
            cmd &= quoteFile(url.hostname, qs)
          else:
            cmd &= url.hostname
      of 'H': # Chawan extension
        if url != nil:
          if shellQuote:
            cmd &= quoteFile(url.host, qs)
          else:
            cmd &= url.host
      of 'p': # w3mmee extension
        if url != nil:
          if shellQuote:
            cmd &= quoteFile(url.port, qs)
          else:
            cmd &= url.port
      of '?': # w3mmee(-ish) extension
        if url != nil:
          if shellQuote:
            cmd &= quoteFile(url.search, qs)
          else:
            cmd &= url.search
      of 'd': # Chawan extension
        if line != -1: # -1 in mailcap
          cmd &= line
      of '{':
        state = usAttr
        continue
      else: discard
      state = usNormal
    of usAttr:
      if c == '}':
        let s = if uriparams:
          url.getSearchParam(attrname.toOpenArray())
        else:
          contentType.getContentTypeAttr(attrname.toOpenArray())
        cmd &= quoteFile(s, qs)
        attrname.setLen(0)
        state = usNormal
      elif c == '\\':
        state = usAttrQuoted
      else:
        attrname &= c
  cmd.toStr()

proc unquoteCommand*(ecmd, contentType, outpath: Str; url: URL): Str =
  var canpipe: bool
  unquoteCommand(ecmd, contentType, outpath, url, canpipe)

type
  EnvVar* = tuple
    name: Str
    value: Str

  CGIParserState = enum
    cpsEnv, cpsArgv

  CGICommandParser = object
    cmd: Str
    name: Str
    argv: seq[Str]
    env: seq[EnvVar]
    quoteSeen: bool
    cps: CGIParserState

proc flush(cc: var CGICommandParser; buf: var Growbuf) =
  if not cc.quoteSeen and buf.len == 0:
    return
  cc.quoteSeen = false
  case cc.cps
  of cpsEnv:
    if cc.name.len > 0:
      cc.env.add((move(cc.name), move(buf).toStr()))
    else:
      cc.cmd = move(buf).toStr()
      # We handle query strings *after* parsing, because we want e.g.
      #  /cgi-bin/blah.cgi%?
      # to set the original URI's query string as blah.cgi's QUERY_STRING.
      let q = cc.cmd.find('?')
      if q >= 0:
        cc.env.add((str("QUERY_STRING"), cc.cmd.substr(q + 1)))
        cc.cmd.setLen(q)
      cc.cps = cpsArgv
  of cpsArgv:
    cc.argv.add(move(buf).toStr())

proc parseCGICommand*(ecmd, typeBuf: Str; url: URL; ocmd: var Str;
    oargv: var seq[Str]; oenv: var seq[EnvVar]): Err[cstring] =
  # like unquoteCommand, but for CGI
  var cc = CGICommandParser()
  var buf = initGrowbuf()
  var attrname = initGrowbuf()
  var state = usNormal
  var qs = qsNormal # current quote state
  for c in ecmd:
    case state
    of usQuoted:
      buf &= c
      state = usNormal
    of usAttrQuoted:
      attrname &= c.toLowerAscii()
      state = usAttr
    of usNormal, usDollar:
      state = usNormal
      case c
      of '%':
        state = usPerc
      of '\\':
        state = usQuoted
      of '\'':
        case qs
        of qsNormal: qs = qsSingleQuoted
        of qsDoubleQuoted: buf &= c
        of qsSingleQuoted: qs = qsNormal
        cc.quoteSeen = true
      of '"':
        case qs
        of qsNormal: qs = qsDoubleQuoted
        of qsSingleQuoted: buf &= c
        of qsDoubleQuoted: qs = qsNormal
        cc.quoteSeen = true
      of '$':
        if qs != qsSingleQuoted:
          #TODO support variables?
          return err("variable substitution is not supported")
        buf &= c
      of '(', ')', '`':
        if qs == qsNormal:
          return err("shell substitution is not supported")
        buf &= c
      of ';':
        if qs == qsNormal:
          return err("command lists are not supported")
        buf &= c
      of AsciiWhitespace: #TODO what does POSIX say about whitespace?
        cc.flush(buf)
      of '=':
        if cc.cps == cpsEnv and cc.name.len == 0:
          if buf.len == 0:
            return err("variable name is the empty string")
          cc.name = move(buf).toStr()
        else:
          buf &= c
      else:
        buf &= c
    of usPerc:
      cc.quoteSeen = true # always expand to a parameter
      case c
      of '%': buf &= c
      of 's': buf &= url.pathname
      of 't': buf &= typeBuf
      of 'u': buf &= url.toStr() # Netscape extension
      of 'h': buf &= url.hostname # w3mmee extension
      of 'H': buf &= url.host # Chawan extension
      of 'p': buf &= url.port # w3mmee extension
      of '?': buf &= url.search # w3mmee(-ish) extension
      of '{':
        state = usAttr
        continue
      else: discard
      state = usNormal
    of usAttr:
      if c == '}':
        buf &= url.getSearchParam(attrname.toOpenArray())
        attrname.setLen(0)
        state = usNormal
      elif c == '\\':
        state = usAttrQuoted
      else:
        attrname &= c
  cc.flush(buf)
  ocmd = move(cc.cmd)
  oenv = move(cc.env)
  oargv = move(cc.argv)
  ok()

proc checkEntry(entry: MailcapEntry; contentType: Str; url: URL;
    internal: bool): bool =
  if mfNetpath in entry.flags and not url.isNetPath() or
      mfInternal in entry.flags and not internal:
    return false
  for field in entry.fields:
    case field.t
    of nfTest:
      var canpipe = true
      let cmd = unquoteCommand(field.value, contentType, str(""), url, canpipe)
      if not canpipe:
        return false
      let pid = fork()
      case pid
      of -1: return false
      of 0:
        closeStdin()
        closeStdout()
        closeStderr()
        discard chaos.signal(SIGINT, chaos.SIG_IGN)
        discard execl("/bin/sh", "sh", "-c", cmd.toCString(), nil)
        exitnow(127)
      else:
        var wstatus: cint
        while waitpid(pid, wstatus, 0) == -1:
          if errno != EINTR:
            break
        if not WIFEXITED(wstatus) or WEXITSTATUS(wstatus) != 0:
          return false
    of nfMatch, nfNcMatch:
      let i = field.value.find('\0') + 1
      let surl = url.toStr()
      let p = addr field.value.toOpenArray()[i]
      let (si, ei) = cast[REBytecode](p).matchFirst(surl.toOpenArray())
      if si != 0 or ei != surl.len:
        return false
    else: discard
  true

proc findPrevMailcapEntry*(mailcap: Mailcap;
    shortContentType, contentType: Str; url: URL; last: int): int =
  let list = mailcap.getList(shortContentType)
  if list != nil:
    for i in countdown(last - 1, 0):
      if mfType in list.entries[i].flags:
        continue # only supported in auto-mailcap
      if checkEntry(list.entries[i], contentType, url, internal = false):
        return i
  return -1

proc findResourceMut*(mailcap: Mailcap; typeBuf: var Str; outUrl: var URL;
    netPathSeen, internalSeen, listSeen: var bool;
    resourceOnly, internal: bool): MailcapEntry =
  var url = outUrl
  var id = 0'u32
  var done = false
  while not done:
    let list = mailcap.getList(typeBuf)
    if list == nil:
      break
    done = true
    listSeen = true
    var i = 0
    let slen = if resourceOnly: list.resource.len else: list.entries.len
    while i < slen:
      let entry = if resourceOnly: list.resource[i] else: list.entries[i]
      inc i
      if entry.id < id:
        continue
      if not checkEntry(entry, url.scheme, url, internal):
        if mfInternal in entry.flags and not internal:
          internalSeen = true
        elif mfNetpath in entry.flags and not url.isNetPath():
          netPathSeen = true
        continue
      if resourceOnly and mfUri in entry.flags:
        var canpipe: bool
        let cmd = unquoteCommand(entry.cmd, typeBuf, url.pathname, url,
          canpipe, shellQuote = false, uriparams = true)
        url = parseURL0(cmd)
        if url == nil:
          return nil
        typeBuf = initStrM(url.scheme, '/', typeBuf.after('/'))
        id = entry.id
        done = false
        listSeen = false
        break
      outUrl = url
      return entry
  nil

proc findMailcapEntry*(mailcap: Mailcap; shortContentType, contentType: Str;
    url: URL; outIdx: var int): MailcapEntry =
  let list = mailcap.getList(shortContentType)
  if list != nil:
    let start = outIdx
    for i in start + 1 ..< list.entries.len:
      let entry = list.entries[i]
      if mfType in entry.flags:
        continue # only supported in auto-mailcap
      if checkEntry(entry, contentType, url, internal = false):
        outIdx = i
        return entry
  outIdx = -1
  nil

# called for auto-mailcap only; allows modifying the type
proc findMailcapEntryMut*(mailcap: Mailcap;
    shortContentType, contentType: var Str; url: URL):
    MailcapEntry =
  var id = 0'u32
  var done = false
  while not done:
    let list = mailcap.getList(shortContentType)
    if list == nil:
      break
    done = true
    for entry in list.entries:
      if entry.id < id:
        continue
      if not checkEntry(entry, contentType, url, internal = false):
        continue
      if mfType in entry.flags:
        var canpipe: bool
        contentType = unquoteCommand(entry.cmd, contentType, str(""), url,
          canpipe, shellQuote = false)
        shortContentType = contentType.untilLower(';')
        id = entry.id
        done = false
        break
      return entry
  nil

proc findMailcapEntry*(mailcap: Mailcap; shortContentType, contentType: Str;
    url: URL): MailcapEntry =
  var start = -1
  mailcap.findMailcapEntry(shortContentType, contentType, url, start)

proc saveEntry*(mailcap: var Mailcap; path, t: Str; entry: MailcapEntry):
    Opt[void] =
  var s = entry.toStr(t)
  s &= "\n"
  let pdir = path.parentDir()
  discard mkdir(pdir.toCString(), 0o700)
  let ps = newPosixStream(path, O_WRONLY or O_APPEND or O_CREAT, 0o644)
  if ps == nil:
    return err()
  let res = ps.writeLoop(s.toOpenArray())
  if res.isOk:
    mailcap.add(entry, t)
  ps.sclose()
  res

proc parseURIMethodMap*(this: var Mailcap; file: AChaFile): Opt[void] =
  var line: Growbuf
  while ?file.readLine(line):
    if line.len == 0 or line[0] == '#':
      continue # comments
    var k = initStr(line.toOpenArray()).untilLower(AsciiWhitespace + {':'})
    var i = k.len
    if i >= line.len or line[i] != ':':
      continue # invalid
    i = line.toOpenArray().skipBlanks(i + 1) # skip colon
    var v = initGrowbufSink(
      initStr(line.toOpenArray()).until(AsciiWhitespace, i), 0)
    # Basic w3m compatibility.
    var cgi = false
    if v.toOpenArray().startsWith("cgi-bin:"):
      v.delete(0..<"cgi-bin:".len)
      cgi = true
    elif v.toOpenArray().startsWith("file:/cgi-bin/"):
      v.delete(0..<"file:/cgi-bin/".len)
      cgi = true
    elif v.toOpenArray().startsWith("file:///cgi-bin/"):
      v.delete(0..<"file:///cgi-bin/".len)
      cgi = true
    elif v.toOpenArray().startsWith("/cgi-bin/"):
      v.delete(0..<"/cgi-bin/".len)
      cgi = true
    # %s -> %u
    var perc = false
    for c in v.mitems:
      if c == '%':
        perc = true
      elif perc:
        if c == 's':
          c = 'u'
        perc = false
    if this.getOrDefault(k.toOpenArray()) == nil:
      let entry = MailcapEntry(cmd: move(v).toStr(), flags: {mfResource})
      if cgi:
        entry.flags.incl(mfCgioutput)
        entry.flags.incl(mfUrimethodmap)
      else:
        entry.flags.incl(mfUri)
      let list = this.put(k)
      list.add(entry)
  ok()

iterator mainTypes*(mailcap: Mailcap): Str =
  for it in mailcap.map:
    let it = MailcapList(it)
    if it.next == nil: # only the last list in the chain
      yield it.s.until('/')

{.pop.} # raises: []
