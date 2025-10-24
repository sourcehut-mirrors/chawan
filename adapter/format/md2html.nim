{.push raises: [].}

import std/strutils
import std/tables

import io/chafile
import types/opt
import utils/twtstr

type
  BracketState = enum
    bsNone, bsInBracket

  BlockType = enum
    btNone, btPar, btList, btPre, btTabPre, btSpacePre, btBlockquote, btHTML,
    btHTMLPre, btComment, btLinkDef

  ListState = enum
    lsNormal, lsAfterBlank, lsLastLine

  ListType = enum
    ltOl, ltUl, ltNoMark

  ListItemDesc = object
    t: ListType
    start: int32
    depth: int
    len: int

  List = object
    depth: int
    t: ListType
    par: bool

  LinkDefState = enum
    ldsLink, ldsTitle

  ParseState = object
    ofile: ChaFile
    blockData: string
    lists: seq[List]
    numPreLines: int
    linkDefIdx: int
    linkDefName: string
    linkDefLink: string
    refMap: TableRef[string, tuple[link, title: string]]
    slurpBuf: string
    slurpIdx: int
    slurping: bool
    reprocess: bool
    hasp: bool
    skipp: bool
    listState: ListState
    blockType: BlockType
    linkDefState: LinkDefState

# Forward declarations
proc parse(state: var ParseState): Opt[void]

proc write(state: ParseState; c: char): Opt[void] =
  if state.ofile != nil:
    return state.ofile.write(c)
  ok()

proc write(state: ParseState; s: openArray[char]): Opt[void] =
  if state.ofile != nil:
    return state.ofile.write(s)
  ok()

proc writeLine(state: ParseState; s: openArray[char]): Opt[void] =
  if state.ofile != nil:
    return state.ofile.writeLine(s)
  ok()

proc slurp(state: var ParseState): Opt[void] =
  var state2 = ParseState(slurpIdx: -2, ofile: nil, refMap: state.refMap)
  ?state2.parse()
  state.slurpBuf = move(state2.slurpBuf)
  state.slurpIdx = 0
  return ok()

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
  flags: set[InlineFlag]

const PreTags = ["pre", "script", "style", "textarea", "head"]

proc parseInTag(ctx: var ParseInlineContext; line: string; state: ParseState):
    Opt[void] =
  var buf = ""
  var i = ctx.i + 1
  while i < line.len:
    let c = line[i]
    if c == '>': # done
      if buf.startsWithScheme(): # link
        ?state.write("<A HREF='" & buf.htmlEscape() & "'>" & buf & "</A>")
      else: # tag
        let s = '<' & buf & '>'
        ?state.write(s)
        if PreTags.containsIgnoreCase(buf):
          let pi = i + 1
          i = line.find(s, i)
          if i == -1:
            i = line.high
          else:
            i += s.len
          if pi <= i:
            ?state.write(line.toOpenArray(pi, i))
      ctx.i = i
      return ok()
    elif c == '<':
      dec i
      break
    else:
      buf &= c
    inc i
  ?state.write("&lt;")
  ?state.write(buf)
  ctx.i = i
  ok()

proc append(ctx: var ParseInlineContext; s: string; state: ParseState):
    Opt[void] =
  if ctx.bs == bsInBracket:
    ctx.bracketChars &= s
  else:
    ?state.write(s)
  ok()

proc append(ctx: var ParseInlineContext; c: char; state: ParseState):
    Opt[void] =
  if ctx.bs == bsInBracket:
    ctx.bracketChars &= c
  else:
    ?state.write(c)
  ok()

type CommentState = enum
  csNone, csDash, csDashDash

proc parseComment(ctx: var ParseInlineContext; line: openArray[char];
    state: ParseState): Opt[void] =
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
  ?ctx.append(buf, state)
  ctx.i = i
  ok()

proc parseCode(ctx: var ParseInlineContext; line: openArray[char];
    state: ParseState): Opt[void] =
  let i = ctx.i + 1
  let j = line.toOpenArray(i, line.high).find('`')
  if j != -1:
    ?ctx.append("<CODE>", state)
    ?ctx.append(line.toOpenArray(i, i + j - 1).htmlEscape(), state)
    ?ctx.append("</CODE>", state)
    ctx.i = i + j
  else:
    ?ctx.append('`', state)
  ok()

proc parseLinkDestination(link: var string; line: openArray[char];
    i: int): int =
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
    elif sc == '<' and c == '>':
      break
    elif sc == '<' and c in {'<', '\n'} or
        sc != '<' and c in Controls + AsciiWhitespace:
      return -1
    elif c == '\\':
      quote = true
    elif c == '(':
      inc parens
      link &= c
    elif c == ')' and sc != '>':
      if parens == 0:
        break
      dec parens
      link &= c
    else:
      link &= c
    inc i
  if sc != '<' and parens != 0 or quote:
    return -1
  return line.skipBlanks(i + int(sc == '<'))

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

proc parseLinkBail(ctx: var ParseInlineContext; i: int; state: ParseState):
    Opt[void] =
  ctx.i = i
  return state.write('[' & ctx.bracketChars & ']')

proc parseLinkWrite(ctx: ParseInlineContext; url, title: string;
    state: ParseState): Opt[void] =
  ?state.write("<A HREF='" & url.htmlEscape())
  if title != "":
    ?state.write("' TITLE='" & title.htmlEscape())
  return state.write("'>" & ctx.bracketChars & "</A>")

proc parseLink(ctx: var ParseInlineContext; line: string;
    state: var ParseState): Opt[void] =
  var i = ctx.i + 1
  if i >= line.len:
    return ctx.parseLinkBail(i, state)
  if (let c = line[i]; c != '('):
    if state.slurpIdx == -1:
      ?state.slurp()
    if c == '[':
      let j = line.find(']', i + 1)
      if j == -1:
        return ctx.parseLinkBail(i - 1, state)
      let s = line.substr(i + 1, j - 1).toLowerAscii()
      if s != "":
        let (link, title) = state.refMap.getOrDefault(s)
        if link == "":
          return ctx.parseLinkBail(i - 1, state)
        ctx.i = j
        return ctx.parseLinkWrite(link, title, state)
      else: # [link][]
        i += 2
    let s = ctx.bracketChars.toLowerAscii()
    let (link, title) = state.refMap.getOrDefault(s)
    if link == "":
      if c == '[':
        i -= 2
      return ctx.parseLinkBail(i - 1, state)
    ctx.i = i - 1
    return ctx.parseLinkWrite(link, title, state)
  let bi = i - 1
  i = line.skipBlanks(i + 1)
  if i >= line.len:
    return ctx.parseLinkBail(bi, state)
  var url = ""
  var j = url.parseLinkDestination(line, i)
  var title = ""
  if j != -1 and j < line.len and line[j] in {'(', '"', '\''}:
    j = title.parseTitle(line, j)
  if j == -1 or j >= line.len or line[j] != ')':
    return ctx.parseLinkBail(bi, state)
  ctx.i = j
  return ctx.parseLinkWrite(url, title, state)

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

proc parseImageWrite(ctx: var ParseInlineContext; link, title, alt: string;
    state: ParseState): Opt[void] =
  ?ctx.append("<IMG SRC='" & link.htmlEscape(), state)
  if title != "":
    ?ctx.append("' TITLE='" & title.htmlEscape(), state)
  if alt != "":
    ?ctx.append("' ALT='" & alt.htmlEscape(), state)
  return ctx.append("'>", state)

proc parseImage(ctx: var ParseInlineContext; line: string;
    state: var ParseState): Opt[void] =
  var alt = ""
  var i = alt.parseImageAlt(line, ctx.i + 2)
  if i == -1 or i + 1 >= line.len or line[i] != ']':
    return ctx.append("![", state)
  inc i
  let c = line[i]
  if c == '[':
    if state.slurpIdx == -1:
      ?state.slurp()
    let j = line.find(']', i + 1)
    if j == -1:
      return ctx.append("![", state)
    let s = line.substr(i + 1, j - 1).toLowerAscii()
    let (link, title) = state.refMap.getOrDefault(s)
    if link == "":
      return ctx.append("![", state)
    ctx.i = j
    return ctx.parseImageWrite(link, title, alt, state)
  if c != '(':
    return ctx.append("![", state)
  var link = ""
  var j = link.parseLinkDestination(line, line.skipBlanks(i + 1))
  var title = ""
  if j != -1 and j < line.len and line[j] in {'(', '"', '\''}:
    j = title.parseTitle(line, j)
  if j == -1 or j >= line.len or line[j] != ')':
    return ctx.append("![", state)
  ctx.i = j
  return ctx.parseImageWrite(link, title, alt, state)

proc appendToggle(ctx: var ParseInlineContext; f: InlineFlag; s, e: string;
    state: ParseState): Opt[void] =
  if f notin ctx.flags:
    ctx.flags.incl(f)
    ?ctx.append(s, state)
  else:
    ctx.flags.excl(f)
    ?ctx.append(e, state)
  ok()

proc parseInline(state: var ParseState; line: string): Opt[void] =
  var ctx = ParseInlineContext()
  while ctx.i < line.len:
    let c = line[ctx.i]
    if c == '\\':
      inc ctx.i
      if ctx.i < line.len:
        ?ctx.append(line[ctx.i], state)
    elif (ctx.i > 0 and line[ctx.i - 1] notin AsciiWhitespace or
          ctx.i + 1 < line.len and line[ctx.i + 1] notin AsciiWhitespace) and
        (c == '*' or
          c == '_' and
            (ctx.i == 0 or line[ctx.i - 1] notin AsciiAlphaNumeric or
              ctx.i + 1 >= line.len or
              line[ctx.i + 1] notin AsciiAlphaNumeric + {'_'})):
      if ctx.i + 1 < line.len and line[ctx.i + 1] == c:
        ?ctx.appendToggle(ifBold, "<B>", "</B>", state)
        inc ctx.i
      else:
        ?ctx.appendToggle(ifItalic, "<I>", "</I>", state)
    elif c == '`':
      ?ctx.parseCode(line, state)
    elif c == '~' and ctx.i + 1 < line.len and line[ctx.i + 1] == '~':
      ?ctx.appendToggle(ifDel, "<DEL>", "</DEL>", state)
      inc ctx.i
    elif c == '!' and ctx.i + 1 < line.len and line[ctx.i + 1] == '[':
      ?ctx.parseImage(line, state)
    elif c == '[':
      if ctx.bs == bsInBracket:
        ?state.write('[' & ctx.bracketChars)
        ctx.bracketChars = ""
      ctx.bs = bsInBracket
    elif c == ']' and ctx.bs == bsInBracket:
      ?ctx.parseLink(line, state)
      ctx.bracketChars = ""
      ctx.bs = bsNone
    elif c == '<':
      ?ctx.parseInTag(line, state)
    elif ctx.i + 4 < line.len and line.toOpenArray(ctx.i, ctx.i + 3) == "<!--":
      ?ctx.append("<!--", state)
      ctx.i += 3
      ?ctx.parseComment(line, state)
    elif c == '\n' and ctx.i >= 2 and line[ctx.i - 1] == ' ' and
        line[ctx.i - 2] == ' ':
      ?ctx.append("<BR>", state)
    else:
      ?ctx.append(c, state)
    inc ctx.i
  if ctx.bs == bsInBracket:
    ?state.write("[")
  if ctx.bracketChars != "":
    ?state.write(ctx.bracketChars)
  if ifBold in ctx.flags:
    ?state.write("</B>")
  if ifItalic in ctx.flags:
    ?state.write("</I>")
  if ifDel in ctx.flags:
    ?state.write("</DEL>")
  ok()

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

proc pushList(state: var ParseState; desc: ListItemDesc): Opt[void] =
  case desc.t
  of ltOl:
    if desc.start == 1:
      ?state.write("<OL>\n<LI>")
    else:
      ?state.write("<OL start=" & $desc.start & ">\n<LI>")
  of ltUl: ?state.write("<UL>\n<LI>")
  of ltNoMark: assert false
  state.lists.add(List(t: desc.t, depth: desc.depth))
  ok()

proc popList(state: var ParseState): Opt[void] =
  case state.lists.pop().t
  of ltOl: ?state.writeLine("</OL>")
  of ltUl: ?state.writeLine("</UL>")
  of ltNoMark: assert false
  ok()

proc writeHeading(state: var ParseState; n: int; text: string): Opt[void] =
  state.hasp = false
  let id = text.getId()
  ?state.write("<H" & $n & " id='" & id & "'><A HREF='#" & id &
    "' CLASS=heading>" & '#'.repeat(n) & "</A> ")
  ?state.parseInline(text)
  ?state.writeLine("</H" & $n & '>')
  ok()

const ThematicBreakChars = {'-', '*', '_'}

proc isThematicBreak(line: string): bool =
  if line.len < 3:
    return false
  let c0 = line[0]
  return c0 in ThematicBreakChars and AllChars - {c0} notin line

proc parseNone(state: var ParseState; line: string): Opt[void] =
  if AllChars - {' ', '\t'} notin line:
    return ok()
  let c0 = line[0]
  if (let n = line.find(AllChars - {'#'}); n in 1..6 and line[n] == ' '):
    if state.hasp:
      state.hasp = false
      ?state.write("</P>")
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
  elif c0 == '<' and line[^1] == '>':
    state.blockType = if line.matchHTMLPreStart(): btHTMLPre else: btHTML
    state.reprocess = true
  elif line.startsWith("```") or line.startsWith("~~~"):
    state.blockType = btPre
    state.blockData = line.substr(0, 2)
    ?state.write("<PRE>")
  elif c0 == '[' and (var i = line.find(']');
      i != -1 and i > 1 and i + 1 < line.len and line[i + 1] == ':'):
    state.blockType = btLinkDef
    state.linkDefState = ldsLink
    state.linkDefIdx = i + 2
    state.linkDefName = line.substr(1, i - 1).toLowerAscii()
    state.linkDefLink = ""
    state.reprocess = true
  elif c0 == '\t':
    state.blockType = btTabPre
    if state.hasp:
      state.hasp = false
      ?state.writeLine("</P>")
    ?state.write("<PRE>")
    state.blockData = line.substr(1) & '\n'
  elif line.startsWith("    "):
    state.blockType = btSpacePre
    if state.hasp:
      state.hasp = false
      ?state.writeLine("</P>")
    ?state.write("<PRE>")
    state.blockData = line.substr(4) & '\n'
  elif c0 == '>':
    state.blockType = btBlockquote
    if state.hasp:
      state.hasp = false
      ?state.writeLine("</P>")
    let i = if line.len < 2 or line[1] != ' ': 1 else: 2
    state.blockData = line.substr(i) & "\n"
    ?state.write("<BLOCKQUOTE>")
  elif (let desc = line.getListDepth(); desc.t != ltNoMark):
    state.blockType = btList
    state.listState = lsNormal
    state.hasp = false
    ?state.pushList(desc)
    state.blockData = line.substr(desc.len + 1) & '\n'
  elif line.isThematicBreak():
    # avoid entering par state so we don't get mistaken for setext heading
    ?state.write("<HR>\n")
    state.hasp = false
  else:
    state.blockType = btPar
    state.reprocess = true
  ok()

proc parsePre(state: var ParseState; line: string): Opt[void] =
  if line.startsWith(state.blockData):
    state.blockType = btNone
    state.blockData = ""
    ?state.writeLine("</PRE>")
  else:
    ?state.writeLine(line.htmlEscape())
  ok()

proc flushPar(state: var ParseState): Opt[void] =
  if state.blockData != "":
    state.hasp = true
    if not state.skipp:
      ?state.writeLine("<P>")
    state.skipp = false
    ?state.parseInline(state.blockData)
    state.blockData = ""
  ok()

proc flushList(state: var ParseState): Opt[void] =
  if state.lists[^1].par and state.blockData != "":
    ?state.writeLine("<P>")
  var state2 = ParseState(
    slurpIdx: 0,
    ofile: state.ofile,
    refMap: state.refMap,
    slurpBuf: move(state.blockData),
    skipp: true
  )
  ?state2.parse()
  while state.lists.len > 0:
    ?state.popList()
  state.blockType = btNone
  ok()

proc parseList(state: var ParseState; line: string): Opt[void] =
  if state.listState == lsLastLine:
    ?state.flushList()
  elif AllChars - {' ', '\t'} notin line:
    state.listState = lsAfterBlank
  elif line.isThematicBreak():
    ?state.flushList()
    state.reprocess = true
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
          var state2 = ParseState(
            slurpIdx: 0,
            ofile: state.ofile,
            refMap: state.refMap,
            slurpBuf: move(state.blockData)
          )
          ?state2.parse()
          while desc.depth < state.lists[^1].depth:
            ?state.popList()
        state.blockData &= line.substr(desc.len) & '\n'
    else:
      if state.listState == lsAfterBlank and state.lists[^1].t == desc.t:
        state.lists[^1].par = true
      if state.lists[^1].par:
        ?state.writeLine("<P>")
      var state2 = ParseState(
        slurpIdx: 0,
        ofile: state.ofile,
        refMap: state.refMap,
        slurpBuf: move(state.blockData),
        skipp: true
      )
      ?state2.parse()
      while state.lists.len > 1 and (desc.depth < state.lists[^1].depth or
          desc.depth == state.lists[^1].depth and desc.t != state.lists[^1].t):
        ?state.popList()
      if state.lists.len == 0 or state.lists[^1].depth < desc.depth:
        ?state.pushList(desc)
      elif state.lists[^1].t != desc.t:
        ?state.popList()
        ?state.pushList(desc)
      else:
        ?state.write("<LI>")
      state.blockData = line.substr(desc.len + 1) & '\n'
    state.listState = lsNormal
  ok()

proc parsePar(state: var ParseState; line: string): Opt[void] =
  if line == "":
    ?state.flushPar()
    state.blockType = btNone
    return ok()
  let c0 = line[0]
  if c0 == '<' and line[^1] == '>':
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
    ?state.write("<PRE>")
  elif (let desc = line.getListDepth(); desc.t != ltNoMark):
    ?state.flushPar()
    state.blockType = btList
    state.listState = lsNormal
    state.hasp = false
    ?state.pushList(desc)
    state.blockData = line.substr(desc.len + 1) & '\n'
  elif c0 in {'-', '=', '*', '_', ' ', '\t'} and AllChars - {c0} notin line:
    if c0 in {' ', '\t'}: # lines with space only also count as blank
      ?state.flushPar()
      state.blockType = btNone
    elif state.blockData != "" and c0 in {'-', '='}: # setext heading
      let n = if c0 == '=': 1 else: 2
      ?state.writeHeading(n, state.blockData)
      state.blockData = ""
    elif line.len >= 3 and c0 in ThematicBreakChars:
      # thematic break
      ?state.flushPar()
      ?state.write("<HR>\n")
      state.hasp = false
      state.blockType = btNone
    else:
      state.blockData = line & '\n'
  else:
    state.blockData &= line & '\n'
  ok()

proc parseHTML(state: var ParseState; line: string): Opt[void] =
  if state.hasp:
    state.hasp = false
    ?state.write("</P>\n")
  if AllChars - {' ', '\t'} notin line:
    ?state.parseInline(state.blockData)
    state.blockData = ""
    state.blockType = btNone
  else:
    state.blockData &= line & '\n'
  ok()

proc parseHTMLPre(state: var ParseState; line: string): Opt[void] =
  if state.hasp:
    state.hasp = false
    ?state.writeLine("</P>")
  if line.matchHTMLPreEnd():
    ?state.write(state.blockData)
    ?state.write(line)
    state.blockData = ""
    state.blockType = btNone
  else:
    state.blockData &= line & '\n'
  ok()

proc parseTabPre(state: var ParseState; line: string): Opt[void] =
  if line.len == 0:
    inc state.numPreLines
  elif line[0] != '\t':
    state.numPreLines = 0
    ?state.write(state.blockData)
    ?state.write("</PRE>")
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
  if line.len == 0:
    inc state.numPreLines
  elif not line.startsWith("    "):
    state.numPreLines = 0
    ?state.write(state.blockData)
    ?state.write("</PRE>")
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
  if line.len == 0 or line[0] != '>':
    var state2 = ParseState(
      slurpIdx: 0,
      ofile: state.ofile,
      refMap: state.refMap,
      slurpBuf: move(state.blockData),
      skipp: true
    )
    ?state2.parse()
    ?state.write("</BLOCKQUOTE>")
    state.reprocess = true
    state.blockType = btNone
  else:
    let i = if line.len < 2 or line[1] != ' ': 1 else: 2
    state.blockData &= line.substr(i) & '\n'
  ok()

proc parseComment(state: var ParseState; line: string): Opt[void] =
  let i = line.find("-->")
  if i != -1:
    ?state.write(line.substr(0, i + 2))
    state.blockType = btNone
    ?state.parseInline(line.substr(i + 3))
  else:
    ?state.writeLine(line)
  ok()

proc parseLinkDef(state: var ParseState; line: string): Opt[void] =
  let pi = state.linkDefIdx
  state.linkDefIdx = 0
  var i = line.skipBlanks(pi)
  if i >= line.len:
    if pi == 0:
      if state.linkDefLink != "":
        discard state.refMap.mgetOrPut(state.linkDefName,
          (move(state.linkDefLink), ""))
        state.blockData = ""
        state.blockType = btNone
      else:
        state.blockType = btPar
      state.reprocess = true
    else:
      state.blockData &= line
    return ok()
  if state.linkDefLink == "":
    i = state.linkDefLink.parseLinkDestination(line, i)
    if i == -1:
      state.blockType = btPar
      state.reprocess = true
      return ok()
    if i < line.len:
      i = line.skipBlanks(i)
    state.linkDefState = ldsTitle
  if i >= line.len: # next line
    state.blockData &= line
    return ok()
  var title = ""
  if line[i] in {'"', '\''}:
    i = title.parseTitle(line, i)
  if i == -1 or i < line.len:
    if pi == 0: # not the first line. put & reprocess
      discard state.refMap.mgetOrPut(state.linkDefName,
        (move(state.linkDefLink), move(title)))
      state.blockType = btNone
      state.blockData = ""
    else:
      state.blockType = btPar
    state.reprocess = true
    return ok()
  discard state.refMap.mgetOrPut(state.linkDefName,
    (move(state.linkDefLink), move(title)))
  state.blockData = ""
  state.blockType = btNone
  ok()

proc readLine(state: var ParseState; line: var string): Opt[bool] =
  let stdin = cast[ChaFile](stdin)
  let hadLine = line != "" or state.blockType == btList
  if state.slurpIdx < 0:
    if ?stdin.readLine(line):
      if state.slurpIdx == -2:
        state.slurpBuf &= line & '\n'
      return ok(true)
  else:
    if state.slurpIdx < state.slurpBuf.len:
      line = state.slurpBuf.until('\n', state.slurpIdx)
      state.slurpIdx += line.len + 1
      return ok(true)
  line = ""
  state.listState = lsLastLine
  ok(hadLine) # add one last iteration with a blank after EOF

proc parse(state: var ParseState): Opt[void] =
  var line = ""
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
    of btLinkDef: ?state.parseLinkDef(line)
  ok()

proc main*() =
  var state = ParseState(
    slurpIdx: -1,
    ofile: cast[ChaFile](stdout),
    refMap: newTable[string, tuple[link, title: string]]()
  )
  discard state.parse()

{.pop.} # raises: []
