# See https://www.rfc-editor.org/rfc/rfc1524

{.push raises: [].}

import std/os
import std/posix
import std/strutils

import io/dynstream
import types/opt
import types/url
import utils/myposix
import utils/twtstr

type
  MailcapParser = object
    at: int
    line: int
    path: string

  MailcapFlag* = enum
    mfNeedsterminal = "needsterminal"
    mfCopiousoutput = "copiousoutput"
    mfHtmloutput = "x-htmloutput" # from w3m
    mfAnsioutput = "x-ansioutput" # Chawan extension
    mfSaveoutput = "x-saveoutput" # Chawan extension
    mfNeedsstyle = "x-needsstyle" # Chawan extension
    mfNeedsimage = "x-needsimage" # Chawan extension

  MailcapEntry* = object
    t*: string
    cmd*: string
    flags*: set[MailcapFlag]
    nametemplate*: string
    edit*: string
    test*: string

  Mailcap* = seq[MailcapEntry]

  AutoMailcap* = object
    path*: string
    entries*: Mailcap

proc `$`*(entry: MailcapEntry): string =
  var s = entry.t & ';' & entry.cmd
  for flag in MailcapFlag:
    if flag in entry.flags:
      s &= ';' & $flag
  if entry.nametemplate != "":
    s &= ";nametemplate=" & entry.nametemplate
  if entry.edit != "":
    s &= ";edit=" & entry.edit
  if entry.test != "":
    s &= ";test=" & entry.test
  s &= '\n'
  move(s)

proc has(state: MailcapParser; buf: openArray[char]): bool {.inline.} =
  return state.at < buf.len

template err(state: MailcapParser; msg: string): untyped =
  err(state.path & '(' & $state.line & "): " & msg)

proc reconsume(state: var MailcapParser; buf: openArray[char]) =
  dec state.at
  if buf[state.at] == '\n':
    dec state.line

proc consume(state: var MailcapParser; buf: openArray[char]): char =
  let c = buf[state.at]
  inc state.at
  if c == '\\' and state.at < buf.len:
    if buf[state.at] != '\n':
      return '\\'
    inc state.at
    inc state.line
    if state.at >= buf.len:
      return '\n'
    let c = buf[state.at]
    inc state.at
    if c == '\n':
      inc state.line
    return c
  if c == '\n':
    inc state.line
  return c

proc skipBlanks(state: var MailcapParser; buf: openArray[char]) =
  while state.has(buf):
    if state.consume(buf) notin AsciiWhitespace - {'\n'}:
      state.reconsume(buf)
      break

proc skipLine(state: var MailcapParser; buf: openArray[char]) =
  while state.has(buf):
    let c = state.consume(buf)
    if c == '\n':
      break

proc consumeTypeField(state: var MailcapParser; buf: openArray[char];
    outs: var string): Err[string] =
  var nslash = 0
  while state.has(buf):
    let c = state.consume(buf)
    if c in AsciiWhitespace + {';'}:
      state.reconsume(buf)
      break
    if c == '/':
      inc nslash
    elif c notin AsciiAlphaNumeric + {'-', '.', '*', '_', '+'}:
      return state.err("invalid character in type field: " & c)
    outs &= c.toLowerAscii()
  if nslash == 0:
    # Accept types without a subtype - RFC calls this "implicit-wild".
    outs &= "/*"
  if nslash > 1:
    return state.err("too many slash characters")
  state.skipBlanks(buf)
  if not state.has(buf) or state.consume(buf) != ';':
    return state.err("semicolon not found")
  return ok()

proc consumeCommand(state: var MailcapParser; buf: openArray[char];
    outs: var string): Err[string] =
  state.skipBlanks(buf)
  var quoted = false
  while state.has(buf):
    let c = state.consume(buf)
    if not quoted:
      if c == '\r':
        continue
      if c in {';', '\n'}:
        state.reconsume(buf)
        return ok()
      if c == '\\':
        quoted = true
        # fall through; backslash will be parsed again in unquoteCommand
      elif c in Controls:
        return state.err("invalid character in command: " & c)
    else:
      quoted = false
    outs &= c
  return ok()

type NamedField = enum
  nmTest = "test"
  nmNametemplate = "nametemplate"
  nmEdit = "edit"

proc consumeField(state: var MailcapParser; buf: openArray[char];
    entry: var MailcapEntry): Result[bool, string] =
  state.skipBlanks(buf)
  var s = ""
  var res = false
  while state.has(buf):
    case (let c = state.consume(buf); c)
    of ';', '\n':
      res = c == ';'
      break
    of '\r':
      continue
    of '=':
      var cmd = ""
      ?state.consumeCommand(buf, cmd)
      while s.len > 0 and s[^1] in AsciiWhitespace:
        s.setLen(s.len - 1)
      if x := parseEnumNoCase[NamedField](s):
        case x
        of nmTest: entry.test = cmd
        of nmNametemplate: entry.nametemplate = cmd
        of nmEdit: entry.edit = cmd
      return ok(state.has(buf) and state.consume(buf) == ';')
    elif c in Controls:
      return state.err("invalid character in field: " & c)
    else:
      s &= c
  while s.len > 0 and s[^1] in AsciiWhitespace:
    s.setLen(s.len - 1)
  if x := parseEnumNoCase[MailcapFlag](s):
    entry.flags.incl(x)
  return ok(res)

proc parseMailcap*(mailcap: var Mailcap; buf: openArray[char]; path: string):
    Err[string] =
  var state = MailcapParser(line: 1, path: path)
  while state.has(buf):
    if state.consume(buf) == '#':
      state.skipLine(buf)
      continue
    state.reconsume(buf)
    state.skipBlanks(buf)
    if state.consume(buf) in {'\n', '\r'}:
      continue
    state.reconsume(buf)
    var entry = MailcapEntry()
    ?state.consumeTypeField(buf, entry.t)
    ?state.consumeCommand(buf, entry.cmd)
    if state.has(buf) and state.consume(buf) == ';':
      while ?state.consumeField(buf, entry):
        discard
    mailcap.add(entry)
  return ok()

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
      of 'd': # line; not used in mailcap, only in getEditorCommand
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
  return cmd

proc unquoteCommand*(ecmd, contentType, outpath: string; url: URL): string =
  var canpipe: bool
  return unquoteCommand(ecmd, contentType, outpath, url, canpipe)

proc checkEntry(entry: MailcapEntry; contentType, outpath, mt, st: string;
    url: URL): bool =
  if not entry.t.startsWith("*/") and not entry.t.startsWithIgnoreCase(mt) or
      not entry.t.endsWith("/*") and not entry.t.endsWithIgnoreCase(st):
    return false
  if entry.test != "":
    var canpipe = true
    let cmd = unquoteCommand(entry.test, contentType, outpath, url, canpipe)
    return canpipe and myposix.system(cstring(cmd)) == 0
  true

proc findPrevMailcapEntry*(mailcap: Mailcap; contentType, outpath: string;
    url: URL; last: int): int =
  let mt = contentType.until('/') & '/'
  let st = contentType.until(AsciiWhitespace + {';'}, mt.len - 1)
  for i in countdown(last - 1, 0):
    if checkEntry(mailcap[i], contentType, outpath, mt, st, url):
      return i
  return -1

proc findMailcapEntry*(mailcap: Mailcap; contentType, outpath: string;
    url: URL; start = -1): int =
  let mt = contentType.until('/') & '/'
  let st = contentType.until(AsciiWhitespace + {';'}, mt.len - 1)
  for i in start + 1 ..< mailcap.len:
    if checkEntry(mailcap[i], contentType, outpath, mt, st, url):
      return i
  return -1

proc saveEntry*(mailcap: var AutoMailcap; entry: MailcapEntry): bool =
  let s = $entry
  let pdir = mailcap.path.parentDir()
  discard mkdir(cstring(pdir), 0o700)
  let ps = newPosixStream(mailcap.path, O_WRONLY or O_APPEND or O_CREAT, 0o644)
  if ps == nil:
    return false
  let res = ps.writeDataLoop(s)
  if res:
    mailcap.entries.add(entry)
  ps.sclose()
  return res

{.pop.} # raises: []
