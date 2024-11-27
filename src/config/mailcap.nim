# See https://www.rfc-editor.org/rfc/rfc1524

import std/osproc
import std/streams
import std/strutils

import types/url
import types/opt
import utils/twtstr

type
  MailcapParser = object
    stream: Stream
    hasbuf: bool
    buf: char
    line: int

  MailcapFlag* = enum
    mfNeedsterminal = "needsterminal"
    mfCopiousoutput = "copiousoutput"
    mfHtmloutput = "x-htmloutput" # from w3m
    mfAnsioutput = "x-ansioutput" # Chawan extension
    mfNeedsstyle = "x-needsstyle" # Chawan extension

  MailcapEntry* = object
    mt*: string
    subt*: string
    cmd*: string
    flags*: set[MailcapFlag]
    nametemplate*: string
    edit*: string
    test*: string

  Mailcap* = seq[MailcapEntry]

proc has(state: MailcapParser): bool {.inline.} =
  return not state.stream.atEnd

proc consume(state: var MailcapParser): char =
  if state.hasbuf:
    state.hasbuf = false
    return state.buf
  var c = state.stream.readChar()
  if c == '\\' and not state.stream.atEnd:
    let c2 = state.stream.readChar()
    if c2 == '\n' and not state.stream.atEnd:
      inc state.line
      c = state.stream.readChar()
  if c == '\n':
    inc state.line
  return c

proc reconsume(state: var MailcapParser; c: char) =
  state.buf = c
  state.hasbuf = true

proc skipBlanks(state: var MailcapParser; c: var char): bool =
  while state.has():
    c = state.consume()
    if c notin AsciiWhitespace - {'\n'}:
      return true

proc skipBlanks(state: var MailcapParser) =
  var c: char
  if state.skipBlanks(c):
    state.reconsume(c)

proc skipLine(state: var MailcapParser) =
  while state.has():
    let c = state.consume()
    if c == '\n':
      break

proc consumeTypeField(state: var MailcapParser): Result[string, string] =
  var s = ""
  # type
  while state.has():
    let c = state.consume()
    if c == '/':
      s &= c
      break
    if c notin AsciiAlphaNumeric + {'-', '*'}:
      return err("line " & $state.line & ": invalid character in type field: " &
        c)
    s &= c.toLowerAscii()
  if not state.has():
    return err("Missing subtype")
  # subtype
  while state.has():
    let c = state.consume()
    if c in AsciiWhitespace + {';'}:
      state.reconsume(c)
      break
    if c notin AsciiAlphaNumeric + {'-', '.', '*', '_', '+'}:
      return err("line " & $state.line &
        ": invalid character in subtype field: " & c)
    s &= c.toLowerAscii()
  var c: char
  if not state.skipBlanks(c) or c != ';':
    return err("Semicolon not found")
  return ok(s)

proc consumeCommand(state: var MailcapParser): Result[string, string] =
  state.skipBlanks()
  var quoted = false
  var s = ""
  while state.has():
    let c = state.consume()
    if not quoted:
      if c == '\r':
        continue
      if c == ';' or c == '\n':
        state.reconsume(c)
        return ok(s)
      if c == '\\':
        quoted = true
        continue
      if c notin Ascii - Controls:
        return err("line " & $state.line & ": invalid character in command: " &
          c)
    else:
      quoted = false
    s &= c
  return ok(s)

type NamedField = enum
  nmTest = "test"
  nmNametemplate = "nametemplate"
  nmEdit = "edit"

proc consumeField(state: var MailcapParser; entry: var MailcapEntry):
    Result[bool, string] =
  state.skipBlanks()
  var buf = ""
  var res = false
  while state.has():
    case (let c = state.consume(); c)
    of ';', '\n':
      res = c == ';'
      break
    of '\r':
      continue
    of '=':
      let cmd = ?state.consumeCommand()
      while buf.len > 0 and buf[^1] in AsciiWhitespace:
        buf.setLen(buf.len - 1)
      if (let x = parseEnumNoCase[NamedField](buf); x.isSome):
        case x.get
        of nmTest: entry.test = cmd
        of nmNametemplate: entry.nametemplate = cmd
        of nmEdit: entry.edit = cmd
      return ok(state.consume() == ';')
    elif c in Controls:
      return err("line " & $state.line & ": invalid character in field: " & c)
    else:
      buf &= c
  while buf.len > 0 and buf[^1] in AsciiWhitespace:
    buf.setLen(buf.len - 1)
  if (let x = parseEnumNoCase[MailcapFlag](buf); x.isSome):
    entry.flags.incl(x.get)
  return ok(res)

proc parseMailcap*(stream: Stream): Result[Mailcap, string] =
  var state = MailcapParser(stream: stream, line: 1)
  var mailcap: Mailcap
  while not stream.atEnd():
    let c = state.consume()
    if c == '#':
      state.skipLine()
      continue
    state.reconsume(c)
    state.skipBlanks()
    let c2 = state.consume()
    if c2 == '\n' or c2 == '\r':
      continue
    state.reconsume(c2)
    let t = ?state.consumeTypeField()
    let mt = t.until('/') #TODO this could be more efficient
    let subt = t[mt.len + 1 .. ^1]
    var entry = MailcapEntry(
      mt: mt,
      subt: subt,
      cmd: ?state.consumeCommand()
    )
    if state.consume() == ';':
      while ?state.consumeField(entry):
        discard
    mailcap.add(entry)
  return ok(mailcap)

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
  let mt = contentType.until('/')
  let st = contentType.until(AsciiWhitespace + {';'}, mt.len + 1)
  for i, entry in mailcap.mpairs:
    if entry.mt != "*" and not entry.mt.equalsIgnoreCase(mt):
      continue
    if entry.subt != "*" and not entry.subt.equalsIgnoreCase(st):
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
