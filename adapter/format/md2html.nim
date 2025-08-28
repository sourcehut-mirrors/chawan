{.push raises: [].}

import std/strutils

import io/chafile
import types/opt
import utils/twtstr

type BracketState = enum
  bsNone, bsInBracket

proc getId(line: openArray[char]): string =
  result = ""
  var i = 0
  var bs = bsNone
  while i < line.len:
    case (let c = line[i]; c)
    of AsciiAlphaNumeric, '-', '_', '.': result &= c.toLowerAscii()
    of ' ': result &= '-'
    of '[':
      bs = bsInBracket
    of ']':
      if bs == bsInBracket:
        if i + 1 < line.len and line[i + 1] == '(':
          inc i
          while i < line.len:
            let c = line[i]
            if c == '\\':
              inc i
            elif c == ')':
              break
            inc i
        bs = bsNone
    else: discard
    inc i

type InlineFlag = enum
  ifItalic, ifBold, ifDel

proc startsWithScheme(s: string): bool =
  for i, c in s:
    if i > 0 and c == ':':
      return true
    if c notin AsciiAlphaNumeric:
      break
  false

type ParseInlineContext = object
  i: int
  bracketChars: string
  bs: BracketState
  bracketRef: bool
  flags: set[InlineFlag]

const PreTags = ["pre", "script", "style", "textarea", "head"]

proc parseInTag(ctx: var ParseInlineContext; line: string): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  var buf = ""
  var i = ctx.i + 1
  while i < line.len:
    let c = line[i]
    if c == '>': # done
      if buf.startsWithScheme(): # link
        ?stdout.write("<A HREF='" & buf.htmlEscape() & "'>" & buf & "</A>")
      else: # tag
        let s = '<' & buf & '>'
        ?stdout.write(s)
        if PreTags.containsIgnoreCase(buf):
          let pi = i + 1
          i = line.find(s, i)
          if i == -1:
            i = line.high
          else:
            i += s.len
          if pi <= i:
            ?stdout.write(line.toOpenArray(pi, i))
      buf = ""
      break
    elif c == '<':
      ?stdout.write('<' & buf)
      buf = ""
      dec i
      break
    else:
      buf &= c
    inc i
  if buf != "":
    ?stdout.write('<')
  ?stdout.write(buf)
  ctx.i = i
  ok()

proc append(ctx: var ParseInlineContext; s: string): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  if ctx.bs == bsInBracket:
    ctx.bracketChars &= s
  else:
    ?stdout.write(s)
  ok()

proc append(ctx: var ParseInlineContext; c: char): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  if ctx.bs == bsInBracket:
    ctx.bracketChars &= c
  else:
    ?stdout.write(c)
  ok()

type CommentState = enum
  csNone, csDash, csDashDash

proc parseComment(ctx: var ParseInlineContext; line: openArray[char]):
    Opt[void] =
  var i = ctx.i
  var cs = csNone
  var buf = ""
  while i < line.len:
    let c = line[i]
    if cs in {csNone, csDash} and c == '-':
      inc cs
    elif cs == csDashDash and c == '>':
      buf &= '>'
      break
    else:
      cs = csNone
    buf &= c
    inc i
  ?ctx.append(buf)
  ctx.i = i
  ok()

proc parseCode(ctx: var ParseInlineContext; line: openArray[char]): Opt[void] =
  let i = ctx.i + 1
  let j = line.toOpenArray(i, line.high).find('`')
  if j != -1:
    ?ctx.append("<CODE>")
    ?ctx.append(line.toOpenArray(i, i + j - 1).htmlEscape())
    ?ctx.append("</CODE>")
    ctx.i = i + j
  else:
    ?ctx.append('`')
  ok()

proc parseLinkDestination(url: var string; line: openArray[char]; i: int): int =
  var i = i
  var quote = false
  var parens = 0
  let sc = line[i]
  if sc == '<':
    inc i
  while i < line.len:
    let c = line[i]
    if quote:
      quote = false
    elif sc == '<' and c == '>' or sc != '<' and c in AsciiWhitespace:
      break
    elif c in {'<', '\n'} or c in Controls and sc != '<':
      return -1
    elif c == '\\':
      quote = true
    elif c == '(':
      inc parens
      url &= c
    elif c == ')' and sc != '>':
      if parens == 0:
        break
      dec parens
      url &= c
    else:
      url &= c
    inc i
  if sc != '>' and parens != 0 or quote:
    return -1
  return line.skipBlanks(i)

proc parseTitle(title: var string; line: openArray[char]; i: int): int =
  let ec = line[i]
  var i = i + 1
  var quote = false
  while i < line.len:
    let c = line[i]
    if quote:
      quote = false
    elif c == '\\':
      quote = true
    elif c == ec:
      inc i
      break
    else:
      title &= c
    inc i
  return line.skipBlanks(i)

proc parseLink(ctx: var ParseInlineContext; line: openArray[char]): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  var i = ctx.i + 1
  if i >= line.len or line[i] != '(':
    #TODO reference links
    ?stdout.write('[' & ctx.bracketChars & ']')
    return ok()
  i = line.skipBlanks(i + 1)
  if i >= line.len:
    ?stdout.write('[' & ctx.bracketChars & ']')
    return ok()
  var url = ""
  var j = url.parseLinkDestination(line, i)
  var title = ""
  if j != -1 and j < line.len and line[j] in {'(', '"', '\''}:
    j = title.parseTitle(line, j)
  if j == -1 or j >= line.len or line[j] != ')':
    ?stdout.write('[' & ctx.bracketChars & ']')
  else:
    let url = url.htmlEscape()
    ?stdout.write("<A HREF='" & url)
    if title != "":
      ?stdout.write("' TITLE='" & title.htmlEscape())
    ?stdout.write("'>")
    ?stdout.write(ctx.bracketChars)
    ?stdout.write("</A>")
    ctx.i = j
  ok()

proc parseImageAlt(text: var string; line: openArray[char]; i: int): int =
  var i = i
  var brackets = 0
  while i < line.len:
    let c = line[i]
    if c == '\\':
      inc i
    elif c == '<':
      while i < line.len and line[i] != '>':
        text &= c
        inc i
    elif c == '[':
      inc brackets
      text &= c
    elif line[i] == ']':
      if brackets == 0:
        break
      dec brackets
      text &= c
    else:
      text &= c
    inc i
  return i

proc parseImage(ctx: var ParseInlineContext; line: openArray[char]): Opt[void] =
  var text = ""
  let i = text.parseImageAlt(line, ctx.i + 2)
  if i == -1 or i + 1 >= line.len or line[i] != ']' or line[i + 1] != '(':
    ?ctx.append("![")
    return ok()
  var url = ""
  var j = url.parseLinkDestination(line, line.skipBlanks(i + 2))
  var title = ""
  if j != -1 and j < line.len and line[j] in {'(', '"', '\''}:
    j = title.parseTitle(line, j)
  if j == -1 or j >= line.len or line[j] != ')':
    ?ctx.append("![")
  else:
    ?ctx.append("<IMG SRC='" & url.htmlEscape())
    if title != "":
      ?ctx.append("' TITLE='" & title.htmlEscape())
    if text != "":
      ?ctx.append("' ALT='" & text.htmlEscape())
    ?ctx.append("'>")
    ctx.i = j
  ok()

proc appendToggle(ctx: var ParseInlineContext; f: InlineFlag; s, e: string):
    Opt[void] =
  if f notin ctx.flags:
    ctx.flags.incl(f)
    ?ctx.append(s)
  else:
    ctx.flags.excl(f)
    ?ctx.append(e)
  ok()

proc parseInline(line: string): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  var ctx = ParseInlineContext()
  while ctx.i < line.len:
    let c = line[ctx.i]
    if c == '\\':
      inc ctx.i
      if ctx.i < line.len:
        ?ctx.append(line[ctx.i])
    elif (ctx.i > 0 and line[ctx.i - 1] notin AsciiWhitespace or
          ctx.i + 1 < line.len and line[ctx.i + 1] notin AsciiWhitespace) and
        (c == '*' or
          c == '_' and
            (ctx.i == 0 or line[ctx.i - 1] notin AsciiAlphaNumeric or
              ctx.i + 1 >= line.len or
              line[ctx.i + 1] notin AsciiAlphaNumeric + {'_'})):
      if ctx.i + 1 < line.len and line[ctx.i + 1] == c:
        ?ctx.appendToggle(ifBold, "<B>", "</B>")
        inc ctx.i
      else:
        ?ctx.appendToggle(ifItalic, "<I>", "</I>")
    elif c == '`':
      ?ctx.parseCode(line)
    elif c == '~' and ctx.i + 1 < line.len and line[ctx.i + 1] == '~':
      ?ctx.appendToggle(ifDel, "<DEL>", "</DEL>")
      inc ctx.i
    elif c == '!' and ctx.i + 1 < line.len and line[ctx.i + 1] == '[':
      ?ctx.parseImage(line)
    elif c == '[':
      if ctx.bs == bsInBracket:
        ?stdout.write('[' & ctx.bracketChars)
        ctx.bracketChars = ""
      ctx.bs = bsInBracket
      ctx.bracketRef = ctx.i + 1 < line.len and line[ctx.i + 1] == '^'
      if ctx.bracketRef:
        inc ctx.i
    elif c == ']' and ctx.bs == bsInBracket:
      if ctx.bracketRef:
        let id = ctx.bracketChars.getId()
        ?stdout.write("<A HREF='#" & id & "'>" & ctx.bracketChars & "</A>")
      else:
        ?ctx.parseLink(line)
      ctx.bracketChars = ""
      ctx.bracketRef = false
      ctx.bs = bsNone
    elif c == '<':
      ?ctx.parseInTag(line)
    elif ctx.i + 4 < line.len and line.toOpenArray(ctx.i, ctx.i + 3) == "<!--":
      ?ctx.append("<!--")
      ctx.i += 3
      ?ctx.parseComment(line)
    elif c == '\n' and ctx.i >= 2 and line[ctx.i - 1] == ' ' and
        line[ctx.i - 2] == ' ':
      ?ctx.append("<BR>")
    else:
      ?ctx.append(c)
    inc ctx.i
  if ctx.bs == bsInBracket:
    ?stdout.write("[")
  if ctx.bracketChars != "":
    ?stdout.write(ctx.bracketChars)
  if ifBold in ctx.flags:
    ?stdout.write("</B>")
  if ifItalic in ctx.flags:
    ?stdout.write("</I>")
  if ifDel in ctx.flags:
    ?stdout.write("</DEL>")
  ok()

type
  ListType = enum
    ltOl, ltUl, ltNoMark

  ListItemDesc = object
    t: ListType
    start: int32
    depth: int
    len: int

proc getListDepth(line: string): ListItemDesc =
  var depth = 0
  for i, c in line:
    if c == '\t':
      depth += 8
    elif c == ' ':
      inc depth
    elif c in {'*', '-', '+'}:
      inc depth
      if i + 1 < line.len and line[i + 1] in {' ', '\t'}:
        return ListItemDesc(t: ltUl, depth: depth, len: i + 1)
      break # fail
    elif c in AsciiDigit:
      let j = i
      var i = i + 1
      inc depth
      while i < line.len and line[i] in AsciiDigit:
        inc i
      let start = parseInt32(line.toOpenArray(j, i - 1)).get(-1)
      if i + 1 < line.len and line[i] == '.' and line[i + 1] in {' ', '\t'}:
        return ListItemDesc(t: ltOl, depth: depth, len: i + 1, start: start)
      break # fail
    else:
      return ListItemDesc(t: ltNoMark, depth: depth, len: i)
  return ListItemDesc(t: ltNoMark, depth: -1, len: -1)

proc matchHTMLPreStart(line: string): bool =
  var tagn = ""
  for c in line.toOpenArray(1, line.high):
    if c in {' ', '\t', '>'}:
      break
    if c notin AsciiAlpha:
      return false
    tagn &= c.toLowerAscii()
  return tagn in PreTags

proc matchHTMLPreEnd(line: string): bool =
  var tagn = ""
  for i, c in line:
    if i == 0:
      if c != '<':
        return false
      continue
    if i == 1:
      if c != '/':
        return false
      continue
    if c in {' ', '\t', '>'}:
      break
    if c notin AsciiAlpha:
      return false
    tagn &= c.toLowerAscii()
  return tagn in PreTags

type
  BlockType = enum
    btNone, btPar, btList, btPre, btTabPre, btSpacePre, btBlockquote, btHTML,
    btHTMLPre, btComment

  ListState = enum
    lsNormal, lsAfterBlank, lsLastLine

  List = object
    depth: int
    t: ListType
    par: bool

  ParseState = object
    blockType: BlockType
    blockData: string
    lists: seq[List]
    hasp: bool
    reprocess: bool
    listState: ListState
    numPreLines: int

proc pushList(state: var ParseState; desc: ListItemDesc): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  case desc.t
  of ltOl:
    if desc.start == 1:
      ?stdout.write("<OL>\n<LI>")
    else:
      ?stdout.write("<OL start=" & $desc.start & ">\n<LI>")
  of ltUl: ?stdout.write("<UL>\n<LI>")
  of ltNoMark: assert false
  state.lists.add(List(t: desc.t, depth: desc.depth))
  ok()

proc popList(state: var ParseState): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  case state.lists.pop().t
  of ltOl: ?stdout.write("</OL>\n")
  of ltUl: ?stdout.write("</UL>\n")
  of ltNoMark: assert false
  ok()

proc writeHeading(state: var ParseState; n: int; text: string): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  state.hasp = false
  let id = text.getId()
  ?stdout.write("<H" & $n & " id='" & id & "'><A HREF='#" & id &
    "' CLASS=heading>" & '#'.repeat(n) & "</A> ")
  ?text.parseInline()
  ?stdout.write("</H" & $n & ">\n")
  ok()

proc parseNone(state: var ParseState; line: string): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  if AllChars - {' ', '\t'} notin line:
    discard
  elif (let n = line.find(AllChars - {'#'}); n in 1..6 and line[n] == ' '):
    if state.hasp:
      state.hasp = false
      ?stdout.write("</P>")
    let L = n + 1
    var H = line.rfind(AllChars - {'#'})
    if H != -1 and line[H] == ' ':
      H = max(L - 1, H - 1)
    else:
      H = line.high
    ?state.writeHeading(n, line.substr(L, H))
  elif line.startsWith("<!--"):
    state.blockType = btComment
    state.reprocess = true
  elif line[0] == '<' and line.find('>') == line.high:
    state.blockType = if line.matchHTMLPreStart(): btHTMLPre else: btHTML
    state.reprocess = true
  elif line.startsWith("```") or line.startsWith("~~~"):
    state.blockType = btPre
    state.blockData = line.substr(0, 2)
    ?stdout.write("<PRE>")
  elif line[0] == '\t':
    state.blockType = btTabPre
    if state.hasp:
      state.hasp = false
      ?stdout.write("</P>\n")
    ?stdout.write("<PRE>")
    state.blockData = line.substr(1) & '\n'
  elif line.startsWith("    "):
    state.blockType = btSpacePre
    if state.hasp:
      state.hasp = false
      ?stdout.write("</P>\n")
    ?stdout.write("<PRE>")
    state.blockData = line.substr(4) & '\n'
  elif line[0] == '>':
    state.blockType = btBlockquote
    if state.hasp:
      state.hasp = false
      ?stdout.write("</P>\n")
    state.blockData = line.substr(1) & "<BR>"
    ?stdout.write("<BLOCKQUOTE>")
  elif (let desc = line.getListDepth(); desc.t != ltNoMark):
    state.blockType = btList
    state.listState = lsNormal
    state.hasp = false
    ?state.pushList(desc)
    state.blockData = line.substr(desc.len + 1) & '\n'
  else:
    state.blockType = btPar
    state.reprocess = true
  ok()

proc parsePre(state: var ParseState; line: string): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  if line.startsWith(state.blockData):
    state.blockType = btNone
    state.blockData = ""
    ?stdout.write("</PRE>\n")
  else:
    ?stdout.write(line.htmlEscape() & '\n')
  ok()

proc flushPar(state: var ParseState): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  if state.blockData != "":
    state.hasp = true
    ?stdout.write("<P>\n")
    ?state.blockData.parseInline()
    state.blockData = ""
  ok()

proc flushList(state: var ParseState): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  if state.lists[^1].par and state.blockData != "":
    ?stdout.write("<P>\n")
  ?state.blockData.parseInline()
  state.blockData = ""
  while state.lists.len > 0:
    ?state.popList()
  state.blockType = btNone
  ok()

proc parseList(state: var ParseState; line: string): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  if state.listState == lsLastLine:
    ?state.flushList()
  elif AllChars - {' ', '\t'} notin line:
    state.listState = lsAfterBlank
  else:
    let desc = line.getListDepth()
    if desc.t == ltNoMark:
      if state.lists[0].depth > desc.depth:
        if state.listState == lsAfterBlank:
          ?state.flushList()
          state.reprocess = true
        else:
          state.blockData &= line & '\n'
      else:
        if state.listState == lsAfterBlank:
          state.lists[^1].par = true
          ?stdout.write("<P>\n")
          ?state.blockData.parseInline()
          state.blockData = ""
          while desc.depth < state.lists[^1].depth:
            ?state.popList()
        state.blockData &= line.substr(desc.len) & '\n'
    else:
      if state.listState == lsAfterBlank and state.lists[^1].t == desc.t:
        state.lists[^1].par = true
      if state.lists[^1].par:
        ?stdout.write("<P>\n")
      ?state.blockData.parseInline()
      state.blockData = ""
      while state.lists.len > 1 and (desc.depth < state.lists[^1].depth or
          desc.depth == state.lists[^1].depth and desc.t != state.lists[^1].t):
        ?state.popList()
      if state.lists.len == 0 or state.lists[^1].depth < desc.depth:
        ?state.pushList(desc)
      elif state.lists[^1].t != desc.t:
        ?state.popList()
        ?state.pushList(desc)
      else:
        ?stdout.write("<LI>")
      state.blockData = line.substr(desc.len + 1) & '\n'
    state.listState = lsNormal
  ok()

proc parsePar(state: var ParseState; line: string): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  if line == "":
    ?state.flushPar()
    state.blockType = btNone
  elif line[0] == '<' and line.find('>') == line.high:
    ?state.flushPar()
    if line.matchHTMLPreStart():
      state.blockType = btHTMLPre
    else:
      state.blockType = btHTML
    state.reprocess = true
  elif line.startsWith("```") or line.startsWith("~~~"):
    ?state.flushPar()
    state.blockData = line.substr(0, 2)
    state.blockType = btPre
    state.hasp = false
    ?stdout.write("<PRE>")
  elif line[0] in {'-', '=', '*', '_', ' ', '\t'} and
      AllChars - {line[0]} notin line:
    if line[0] in {' ', '\t'}: # lines with space only also count as blank
      ?state.flushPar()
      state.blockType = btNone
    elif state.blockData == "" and line[0] in {'-', '*', '_'}: # thematic break
      state.blockData &= "<HR>\n"
    elif state.blockData != "" and line[0] in {'-', '='}: # setext heading
      let n = if line[0] == '=': 1 else: 2
      ?state.writeHeading(n, state.blockData)
      state.blockData = ""
    else:
      state.blockData = line & '\n'
  else:
    state.blockData &= line & '\n'
  ok()

proc parseHTML(state: var ParseState; line: string): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  if state.hasp:
    state.hasp = false
    ?stdout.write("</P>\n")
  if AllChars - {' ', '\t'} notin line:
    ?state.blockData.parseInline()
    state.blockData = ""
    state.blockType = btNone
  else:
    state.blockData &= line & '\n'
  ok()

proc parseHTMLPre(state: var ParseState; line: string): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  if state.hasp:
    state.hasp = false
    ?stdout.write("</P>\n")
  if line.matchHTMLPreEnd():
    ?stdout.write(state.blockData)
    ?stdout.write(line)
    state.blockData = ""
    state.blockType = btNone
  else:
    state.blockData &= line & '\n'
  ok()

proc parseTabPre(state: var ParseState; line: string): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  if line.len == 0:
    inc state.numPreLines
  elif line[0] != '\t':
    state.numPreLines = 0
    ?stdout.write(state.blockData)
    ?stdout.write("</PRE>")
    state.blockData = ""
    state.reprocess = true
    state.blockType = btNone
  else:
    while state.numPreLines > 0:
      state.blockData &= '\n'
      dec state.numPreLines
    state.blockData &= line.toOpenArray(1, line.high).htmlEscape() & '\n'
  ok()

proc parseSpacePre(state: var ParseState; line: string): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  if line.len == 0:
    inc state.numPreLines
  elif not line.startsWith("    "):
    state.numPreLines = 0
    ?stdout.write(state.blockData)
    ?stdout.write("</PRE>")
    state.blockData = ""
    state.reprocess = true
    state.blockType = btNone
  else:
    while state.numPreLines > 0:
      state.blockData &= '\n'
      dec state.numPreLines
    state.blockData &= line.toOpenArray(4, line.high).htmlEscape() & '\n'
  ok()

proc parseBlockquote(state: var ParseState; line: string): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  if line.len == 0 or line[0] != '>':
    ?stdout.write(state.blockData)
    ?stdout.write("</BLOCKQUOTE>")
    state.blockData = ""
    state.reprocess = true
    state.blockType = btNone
  else:
    state.blockData &= line.substr(1) & "<BR>"
  ok()

proc parseComment(state: var ParseState; line: string): Opt[void] =
  let stdout = cast[ChaFile](stdout)
  let i = line.find("-->")
  if i != -1:
    ?stdout.write(line.substr(0, i + 2))
    state.blockType = btNone
    ?line.substr(i + 3).parseInline()
  else:
    ?stdout.write(line & '\n')
  ok()

proc readLine(state: var ParseState; line: var string): Opt[bool] =
  let stdin = cast[ChaFile](stdin)
  let hadLine = line != "" or state.blockType == btList
  if ?stdin.readLine(line):
    return ok(true)
  line = ""
  state.listState = lsLastLine
  ok(hadLine) # add one last iteration with a blank after EOF

proc main(): Opt[void] =
  var line = ""
  var state = ParseState()
  while state.reprocess or ?state.readLine(line):
    state.reprocess = false
    case state.blockType
    of btNone: ?state.parseNone(line)
    of btPre: ?state.parsePre(line)
    of btTabPre: ?state.parseTabPre(line)
    of btSpacePre: ?state.parseSpacePre(line)
    of btBlockquote: ?state.parseBlockquote(line)
    of btList: ?state.parseList(line)
    of btPar: ?state.parsePar(line)
    of btHTML: ?state.parseHTML(line)
    of btHTMLPre: ?state.parseHTMLPre(line)
    of btComment: ?state.parseComment(line)
  ok()

discard main()

{.pop.} # raises: []
