# See https://www.rfc-editor.org/rfc/rfc1524

{.push raises: [].}

import std/os
import std/posix

import io/chafile
import io/dynstream
import monoucha/libregexp
import types/opt
import types/url
import utils/lrewrap
import utils/myposix
import utils/twtstr

type
  MailcapParser* = object
    line: int
    error*: string

  MailcapFlag* = enum
    mfNeedsterminal = "needsterminal"
    mfCopiousoutput = "copiousoutput"
    mfHtmloutput = "x-htmloutput" # w3m extension
    mfAnsioutput = "x-ansioutput" # Chawan extension
    mfSaveoutput = "x-saveoutput" # Chawan extension
    mfNeedsstyle = "x-needsstyle" # Chawan extension
    mfNeedsimage = "x-needsimage" # Chawan extension
    mfType = "x-type" # w3mmee extension

  NamedFieldType* = enum
    nfTest = "test"
    nfNametemplate = "nametemplate"
    nfEdit = "edit"
    nfMatch = "x-match" # w3mmee extension
    nfNcMatch = "x-nc-match" # w3mmee extension

  NamedField = ref object
    t: NamedFieldType
    value*: string
    next: NamedField

  MailcapEntry* = object #TODO merge t and cmd?
    t*: string
    cmd*: string
    flags*: set[MailcapFlag]
    fieldsHead: NamedField

  Mailcap* = seq[MailcapEntry]

iterator fields(entry: MailcapEntry): NamedField =
  var field = entry.fieldsHead
  while field != nil:
    yield field
    field = field.next

proc find*(entry: MailcapEntry; t: NamedFieldType): NamedField =
  for field in entry.fields:
    if field.t == t:
      return field
  nil

proc `$`*(entry: MailcapEntry): string =
  var s = entry.t & ';' & entry.cmd
  for flag in MailcapFlag:
    if flag in entry.flags:
      s &= ';' & $flag
  for field in entry.fields:
    # if value is regex, then the source is until the first NUL
    s &= ';' & $field.t & '=' & $cstring(field.value)
  s &= '\n'
  move(s)

template err(state: MailcapParser; msg: string): untyped =
  state.error = msg
  err()

proc consumeTypeField(state: var MailcapParser; line: openArray[char];
    outs: var string): Opt[int] =
  var nslash = 0
  var n = 0
  while n < line.len:
    let c = line[n]
    if c in AsciiWhitespace + {';'}:
      break
    if c == '/':
      inc nslash
    elif c notin AsciiAlphaNumeric + {'-', '.', '*', '_', '+'}:
      return state.err("invalid character in type field: " & c)
    outs &= c.toLowerAscii()
    inc n
  if nslash == 0:
    # Accept types without a subtype - RFC calls this "implicit-wild".
    outs &= "/*"
  if nslash > 1:
    return state.err("too many slash characters")
  n = line.skipBlanks(n)
  if n >= line.len or line[n] != ';':
    return state.err("semicolon not found")
  ok(n + 1)

proc consumeCommand(state: var MailcapParser; line: string;
    outs: var string; n: int): Opt[int] =
  var n = line.skipBlanks(n)
  var quoted = false
  while n < line.len:
    let c = line[n]
    if not quoted:
      if c == '\r':
        continue
      if c == ';':
        return ok(n)
      if c == '\\':
        quoted = true
        # fall through; backslash will be parsed again in unquoteCommand
      elif c in Controls:
        return state.err("invalid character in command: " & c)
    else:
      quoted = false
    outs &= c
    inc n
  ok(n)

proc addNamedField(entry: var MailcapEntry; t: NamedFieldType;
    fieldsTail: var NamedField; cmd: var string) =
  var s = move(cmd)
  if t in {nfMatch, nfNcMatch}:
    let flags = if t == nfNcMatch: {LRE_FLAG_IGNORECASE} else: {}
    var re: Regex
    if not compileRegex(s, flags, re):
      return
    s &= '\0' & re.bytecode
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

proc consumeField(state: var MailcapParser; line: string;
    entry: var MailcapEntry; n: int; fieldsTail: var NamedField): Opt[int] =
  var n = line.skipBlanks(n)
  var s = ""
  while n < line.len:
    let c = line[n]
    inc n
    case c
    of ';':
      break
    of '\r':
      continue
    of '=':
      var cmd = ""
      n = ?state.consumeCommand(line, cmd, n)
      while s.len > 0 and s[^1] in AsciiWhitespace:
        s.setLen(s.len - 1)
      if t := parseEnumNoCase[NamedFieldType](s):
        entry.addNamedField(t, fieldsTail, cmd)
      return ok(n)
    elif c in Controls:
      return state.err("invalid character in field: " & c)
    else:
      s &= c
  while s.len > 0 and s[^1] in AsciiWhitespace:
    s.setLen(s.len - 1)
  if x := parseEnumNoCase[MailcapFlag](s):
    entry.flags.incl(x)
  return ok(n)

proc parseEntry*(state: var MailcapParser; line: string;
    entry: var MailcapEntry): Opt[void] =
  var n = ?state.consumeTypeField(line, entry.t)
  n = ?state.consumeCommand(line, entry.cmd, n)
  var fieldsTail: NamedField
  while n < line.len:
    n = ?state.consumeField(line, entry, n, fieldsTail)
  ok()

proc parseBuiltin*(mailcap: var Mailcap; buf: openArray[char]) =
  var state = MailcapParser(line: 1)
  for line in buf.split('\n'):
    if line.len <= 0:
      continue
    var entry: MailcapEntry
    let res = state.parseEntry(line, entry)
    doAssert res.isOk, state.error
    mailcap.add(entry)

proc parseMailcap(state: var MailcapParser; mailcap, typeMailcap: var Mailcap;
    file: ChaFile): Opt[void] =
  var line: string
  while file.readLine(line).get(false):
    if line.len <= 0 or line[0] == '#':
      continue
    while true:
      if line.len > 0 and line[^1] == '\r':
        line.setLen(line.high)
      if line.len == 0 or line[^1] != '\\':
        break
      line.setLen(line.high) # trim backslash
      if not ?file.readLineAppend(line):
        break
    var entry: MailcapEntry
    ?state.parseEntry(line, entry)
    if mfType in entry.flags:
      typeMailcap.add(entry)
    else:
      mailcap.add(entry)
    inc state.line
  return ok()

proc parseMailcap*(mailcap, typeMailcap: var Mailcap; path: string):
    Err[string] =
  let file0 = chafile.fopen(path, "r")
  if file0.isErr:
    return ok()
  let file = file0.get
  var state = MailcapParser(line: 1)
  let res = state.parseMailcap(mailcap, typeMailcap, file)
  file.close()
  if res.isErr:
    return err(path & '(' & $state.line & "): " & msg)
  ok()

# Mostly based on w3m's mailcap quote/unquote
type UnquoteState = enum
  usNormal, usQuoted, usPerc, usAttr, usAttrQuoted, usDollar

type UnquoteResult* = object
  canpipe*: bool
  cmd*: string

type QuoteState* = enum
  qsNormal, qsDoubleQuoted, qsSingleQuoted

proc quoteFile*(file: string; qs: QuoteState): string =
  var s = ""
  for c in file:
    case c
    of '$', '`', '"', '\\':
      if qs != qsSingleQuoted:
        s &= '\\'
    of '\'':
      if qs == qsSingleQuoted:
        s &= "'\\'" # then re-open the quote by appending c
      elif qs == qsNormal:
        s &= '\\'
      # double-quoted: append normally
    of AsciiAlphaNumeric, '_', '.', ':', '/':
      discard # no need to quote
    elif qs == qsNormal:
      s &= '\\'
    s &= c
  move(s)

proc unquoteCommand*(ecmd, contentType, outpath: string; url: URL;
    canpipe: var bool; line = -1): string =
  var cmd = ""
  var attrname = ""
  var state = usNormal
  var qss = @[qsNormal] # quote state stack. len >1
  template qs: var QuoteState = qss[^1]
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
          qss.add(qsNormal)
        cmd &= c
      of ')':
        if qs != qsSingleQuoted:
          if qss.len > 1:
            qss.setLen(qss.len - 1)
          else:
            # mismatched parens; probably an invalid shell command...
            qss[0] = qsNormal
        cmd &= c
      else:
        cmd &= c
    of usPerc:
      case c
      of '%': cmd &= c
      of 's':
        cmd &= quoteFile(outpath, qs)
        canpipe = false
      of 't':
        cmd &= quoteFile(contentType.until(';'), qs)
      of 'u': # Netscape extension
        if url != nil: # nil in getEditorCommand
          cmd &= quoteFile($url, qs)
      of 'h': # w3mmee extension
        if url != nil:
          cmd &= quoteFile(url.hostname, qs)
      of 'H': # Chawan extension
        if url != nil:
          cmd &= quoteFile(url.host, qs)
      of 'p': # w3mmee extension
        if url != nil:
          cmd &= quoteFile(url.port, qs)
      of '?': # w3mmee(-ish) extension
        if url != nil:
          cmd &= quoteFile(url.search, qs)
      of 'd': # Chawan extension
        if line != -1: # -1 in mailcap
          cmd &= $line
      of '{':
        state = usAttr
        continue
      else: discard
      state = usNormal
    of usAttr:
      if c == '}':
        let s = contentType.getContentTypeAttr(attrname)
        cmd &= quoteFile(s, qs)
        attrname = ""
        state = usNormal
      elif c == '\\':
        state = usAttrQuoted
      else:
        attrname &= c
  move(cmd)

proc unquoteCommand*(ecmd, contentType, outpath: string; url: URL): string =
  var canpipe: bool
  return unquoteCommand(ecmd, contentType, outpath, url, canpipe)

proc checkEntry(entry: MailcapEntry; contentType, mt, st: string; url: URL):
    bool =
  if not entry.t.startsWith("*/") and not entry.t.startsWithIgnoreCase(mt) or
      not entry.t.endsWith("/*") and not entry.t.endsWithIgnoreCase(st):
    return false
  for field in entry.fields:
    case field.t
    of nfTest:
      var canpipe = true
      let cmd = unquoteCommand(field.value, contentType, "", url, canpipe)
      if canpipe and myposix.system(cstring(cmd)) == 0:
        return false
    of nfMatch, nfNcMatch:
      let i = field.value.find('\0') + 1
      let surl = $url
      let (si, ei) = cast[REBytecode](addr field.value[i]).matchFirst(surl)
      if si != 0 or ei != surl.len:
        return false
    else: discard
  true

proc findPrevMailcapEntry*(mailcap: Mailcap; contentType: string; url: URL;
    last: int): int =
  let si = last - 1
  if si >= 0:
    let mt = contentType.until('/') & '/'
    let st = contentType.until(AsciiWhitespace + {';'}, mt.len - 1)
    for i in countdown(last - 1, 0):
      if checkEntry(mailcap[i], contentType, mt, st, url):
        return i
  return -1

proc findMailcapEntry*(mailcap: Mailcap; contentType: string; url: URL;
    start = -1): int =
  let si = start + 1
  if si < mailcap.len:
    let mt = contentType.until('/') & '/'
    let st = contentType.until(AsciiWhitespace + {';'}, mt.len - 1)
    for i in si ..< mailcap.len:
      if checkEntry(mailcap[i], contentType, mt, st, url):
        return i
  return -1

proc saveEntry*(mailcap: var Mailcap; path: string; entry: MailcapEntry):
    Opt[void] =
  let s = $entry
  let pdir = path.parentDir()
  discard mkdir(cstring(pdir), 0o700)
  let ps = newPosixStream(path, O_WRONLY or O_APPEND or O_CREAT, 0o644)
  if ps == nil:
    return err()
  let res = ps.writeLoop(s)
  if res.isOk:
    mailcap.add(entry)
  ps.sclose()
  res

{.pop.} # raises: []
