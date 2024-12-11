# See https://www.rfc-editor.org/rfc/rfc1524

import std/os
import std/osproc
import std/posix
import std/strutils

import io/dynstream
import types/opt
import types/url
import utils/twtstr

type
  MailcapParser = object
    hasbuf: bool
    buf: char
    at: int
    line: int

  MailcapFlag* = enum
    mfNeedsterminal = "needsterminal"
    mfCopiousoutput = "copiousoutput"
    mfHtmloutput = "x-htmloutput" # from w3m
    mfAnsioutput = "x-ansioutput" # Chawan extension
    mfSaveoutput = "x-saveoutput" # Chawan extension
    mfNeedsstyle = "x-needsstyle" # Chawan extension

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

proc serializeCommand(s: var string; cmd: string) =
  for c in cmd:
    if c == ';':
      s &= '\\'
    s &= c

proc `$`*(entry: MailcapEntry): string =
  var s = ""
  s.serializeCommand(entry.t)
  s &= ';'
  s.serializeCommand(entry.cmd)
  for flag in MailcapFlag:
    if flag in entry.flags:
      s &= ';' & $flag
  if entry.nametemplate != "":
    s &= ";nametemplate="
    s.serializeCommand(entry.nametemplate)
  if entry.edit != "":
    s &= ";edit="
    s.serializeCommand(entry.edit)
  if entry.test != "":
    s &= ";test="
    s.serializeCommand(entry.test)
  s &= '\n'
  return s

proc has(state: MailcapParser; buf: openArray[char]): bool {.inline.} =
  return state.at < buf.len

proc consume(state: var MailcapParser; buf: openArray[char]): char =
  if state.hasbuf:
    state.hasbuf = false
    return state.buf
  var c = buf[state.at]
  inc state.at
  if c == '\\' and state.has(buf):
    let c2 = buf[state.at]
    inc state.at
    if c2 == '\n' and state.has(buf):
      inc state.line
      c = buf[state.at]
      inc state.at
  if c == '\n':
    inc state.line
  return c

proc reconsume(state: var MailcapParser; c: char) =
  state.buf = c
  state.hasbuf = true

proc skipBlanks(state: var MailcapParser; buf: openArray[char]; c: var char):
    bool =
  while state.has(buf):
    c = state.consume(buf)
    if c notin AsciiWhitespace - {'\n'}:
      return true
  return false

proc skipBlanks(state: var MailcapParser; buf: openArray[char]) =
  var c: char
  if state.skipBlanks(buf, c):
    state.reconsume(c)

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
      state.reconsume(c)
      break
    if c == '/':
      inc nslash
    elif c notin AsciiAlphaNumeric + {'-', '.', '*', '_', '+'}:
      return err("line " & $state.line &
        ": invalid character in type field: " & c)
    outs &= c.toLowerAscii()
  if nslash == 0:
    # Accept types without a subtype - RFC calls this "implicit-wild".
    outs &= "/*"
  if nslash > 1:
    return err("line " & $state.line & ": too many slash characters")
  var c: char
  if not state.skipBlanks(buf, c) or c != ';':
    return err("Semicolon not found")
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
      if c == ';' or c == '\n':
        state.reconsume(c)
        return ok()
      if c == '\\':
        quoted = true
        continue
      if c notin Ascii - Controls:
        return err("line " & $state.line & ": invalid character in command: " &
          c)
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
      if (let x = parseEnumNoCase[NamedField](s); x.isSome):
        case x.get
        of nmTest: entry.test = cmd
        of nmNametemplate: entry.nametemplate = cmd
        of nmEdit: entry.edit = cmd
      return ok(state.has(buf) and state.consume(buf) == ';')
    elif c in Controls:
      return err("line " & $state.line & ": invalid character in field: " & c)
    else:
      s &= c
  while s.len > 0 and s[^1] in AsciiWhitespace:
    s.setLen(s.len - 1)
  if (let x = parseEnumNoCase[MailcapFlag](s); x.isSome):
    entry.flags.incl(x.get)
  return ok(res)

proc parseMailcap*(omailcap: var Mailcap; buf: openArray[char]): Err[string] =
  var state = MailcapParser(line: 1)
  var mailcap = default(Mailcap)
  while state.has(buf):
    let c = state.consume(buf)
    if c == '#':
      state.skipLine(buf)
      continue
    state.reconsume(c)
    state.skipBlanks(buf)
    let c2 = state.consume(buf)
    if c2 == '\n' or c2 == '\r':
      continue
    state.reconsume(c2)
    var entry = MailcapEntry()
    ?state.consumeTypeField(buf, entry.t)
    ?state.consumeCommand(buf, entry.cmd)
    if state.has(buf) and state.consume(buf) == ';':
      while ?state.consumeField(buf, entry):
        discard
    mailcap.add(entry)
  omailcap.add(mailcap)
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
  return s

proc unquoteCommand*(ecmd, contentType, outpath: string; url: URL;
    canpipe: var bool; line = -1): string =
  var cmd = ""
  var attrname = ""
  var state: UnquoteState
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
      let prev_dollar = state == usDollar
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
        if prev_dollar:
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

proc findMailcapEntry*(mailcap: var Mailcap; contentType, outpath: string;
    url: URL): int =
  let mt = contentType.until('/') & '/'
  let st = contentType.until(AsciiWhitespace + {';'}, mt.len - 1)
  for i, entry in mailcap.mypairs:
    if not entry.t.startsWith("*/") and not entry.t.startsWithIgnoreCase(mt):
      continue
    if not entry.t.endsWith("/*") and not entry.t.endsWithIgnoreCase(st):
      continue
    if entry.test != "":
      var canpipe = true
      let cmd = unquoteCommand(entry.test, contentType, outpath, url, canpipe)
      if not canpipe:
        continue
      if execCmd(cmd) != 0:
        continue
    return i
  return -1

proc saveEntry*(mailcap: var AutoMailcap; entry: MailcapEntry): bool =
  let s = $entry
  try:
    let pdir = mailcap.path.parentDir()
    if not dirExists(pdir):
      createDir(pdir)
    let ps = newPosixStream(mailcap.path, O_WRONLY or O_APPEND or O_CREAT, 0o644)
    if ps == nil:
      return false
    ps.sendDataLoop(s)
    ps.sclose()
  except IOError, OSError:
    return false
  mailcap.entries.add(entry)
  return true
