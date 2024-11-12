import std/options
import std/os
import std/posix

import monoucha/fromjs
import monoucha/javascript
import monoucha/tojs
import types/opt
import utils/twtstr

const libexecPath {.strdefine.} = "${%CHA_BIN_DIR}/../libexec/chawan"

type ChaPath* = distinct string

func `$`*(p: ChaPath): string =
  return string(p)

type
  UnquoteContext = object
    state: UnquoteState
    s: string
    p: string
    i: int
    identStr: string
    subChar: char
    hasColon: bool
    terminal: Option[char]

  UnquoteState = enum
    usNormal, usTilde, usDollar, usIdent, usBslash, usCurlyStart, usCurly,
    usCurlyHash, usCurlyPerc, usCurlyColon, usCurlyExpand

  ChaPathError = string

  ChaPathResult[T] = Result[T, ChaPathError]

proc unquote*(p: ChaPath): ChaPathResult[string]
proc unquote(p: string; starti: var int; terminal: Option[char]):
    ChaPathResult[string]

proc stateNormal(ctx: var UnquoteContext; c: char): bool =
  case c
  of '$': ctx.state = usDollar
  of '\\': ctx.state = usBslash
  of '~':
    if ctx.i == 0:
      ctx.state = usTilde
    else:
      ctx.s &= c
  elif ctx.terminal.isSome and ctx.terminal.get == c:
    return false
  else:
    ctx.s &= c
  return true

proc flushTilde(ctx: var UnquoteContext) =
  if ctx.identStr == "":
    ctx.s &= getHomeDir()
  else:
    let p = getpwnam(cstring(ctx.identStr))
    if p != nil:
      ctx.s &= $p.pw_dir
    ctx.identStr = ""
  ctx.state = usNormal

proc stateTilde(ctx: var UnquoteContext; c: char) =
  if c != '/':
    ctx.identStr &= c
  else:
    ctx.flushTilde()

# Kind of a hack. We special case `\$' (backslash-dollar) in TOML, so that
# it produces itself in dquote strings.
# Thus by applying stateBSlash we get '\$' -> "$", but also "\$" -> "$".
proc stateBSlash(ctx: var UnquoteContext; c: char) =
  if c != '$':
    ctx.s &= '\\'
  ctx.s &= c
  ctx.state = usNormal

proc stateDollar(ctx: var UnquoteContext; c: char): ChaPathResult[void] =
  # $
  case c
  of '$':
    ctx.s &= $getCurrentProcessId()
    ctx.state = usNormal
  of '0':
    # Note: we intentionally use getAppFileName so that any symbolic links
    # are resolved.
    ctx.s &= getAppFileName()
    ctx.state = usNormal
  of '1'..'9':
    return err("Parameter substitution is not supported")
  of AsciiAlpha:
    ctx.identStr = $c
    ctx.state = usIdent
  of '{':
    ctx.state = usCurlyStart
  else:
    # > If an unquoted '$' is followed by a character that is not one of
    # > the following: [...] the result is unspecified.
    # just error out here to be safe
    return err("Invalid dollar substitution")
  ok()

proc flushIdent(ctx: var UnquoteContext) =
  ctx.s &= getEnv(ctx.identStr)
  ctx.identStr = ""

const BareChars = AsciiAlphaNumeric + {'_'}

proc stateIdent(ctx: var UnquoteContext; c: char) =
  # $ident
  if c in BareChars:
    ctx.identStr &= c
  else:
    ctx.flushIdent()
    dec ctx.i
    ctx.state = usNormal

proc stateCurlyStart(ctx: var UnquoteContext; c: char): ChaPathResult[void] =
  # ${
  case c
  of '#':
    ctx.state = usCurlyHash
  of '%':
    ctx.state = usCurlyPerc
  of BareChars:
    ctx.state = usCurly
    dec ctx.i
  else:
    return err("unexpected character in substitution: '" & c & "'")
  return ok()

proc stateCurly(ctx: var UnquoteContext; c: char): ChaPathResult[void] =
  # ${ident
  case c
  of '}':
    ctx.s &= $getEnv(ctx.identStr)
    ctx.identStr = ""
    ctx.state = usNormal
    return ok()
  of '$': # allow $ as first char only
    if ctx.identStr.len > 0:
      return err("unexpected dollar sign in substitution")
    ctx.identStr &= c
    return ok()
  of ':', '-', '?', '+': # note: we don't support `=' (assign)
    if ctx.identStr.len == 0:
      return err("substitution without parameter name")
    if c == ':':
      ctx.state = usCurlyColon
    else:
      ctx.subChar = c
      ctx.state = usCurlyExpand
    return ok()
  of '1'..'9':
    return err("Parameter substitution is not supported")
  of BareChars - {'1'..'9'}:
    ctx.identStr &= c
    return ok()
  else:
    return err("unexpected character in substitution: '" & c & "'")

proc stateCurlyHash(ctx: var UnquoteContext; c: char): ChaPathResult[void] =
  # ${#ident
  if c == '}':
    let s = getEnv(ctx.identStr)
    ctx.s &= $s.len
    ctx.identStr = ""
    ctx.state = usNormal
    return ok()
  if c == '$': # allow $ as first char only
    if ctx.identStr.len > 0:
      return err("unexpected dollar sign in substitution")
    # fall through
  elif c notin BareChars:
    return err("unexpected character in substitution: '" & c & "'")
  ctx.identStr &= c
  return ok()

proc stateCurlyPerc(ctx: var UnquoteContext; c: char): ChaPathResult[void] =
  # ${%ident
  if c == '}':
    if ctx.identStr == "CHA_BIN_DIR":
      ctx.s &= getAppFileName().beforeLast('/')
    elif ctx.identStr == "CHA_LIBEXEC_DIR":
      ctx.s &= ?ChaPath(libexecPath).unquote()
    else:
      return err("Unknown internal variable " & ctx.identStr)
    ctx.identStr = ""
    ctx.state = usNormal
    return ok()
  if c notin BareChars:
    return err("unexpected character in substitution: '" & c & "'")
  ctx.identStr &= c
  return ok()

proc stateCurlyColon(ctx: var UnquoteContext; c: char): ChaPathResult[void] =
  # ${ident:
  if c notin {'-', '?', '+'}: # Note: we don't support `=' (assign)
    return err("unexpected character after colon: '" & c & "'")
  ctx.hasColon = true
  ctx.subChar = c
  ctx.state = usCurlyExpand
  return ok()

proc flushCurlyExpand(ctx: var UnquoteContext; word: string):
    ChaPathResult[void] =
  case ctx.subChar
  of '-':
    if ctx.hasColon:
      ctx.s &= getEnv(ctx.identStr, word)
    else:
      if existsEnv(ctx.identStr):
        ctx.s &= getEnv(ctx.identStr)
      else:
        ctx.s &= word
  of '?':
    if ctx.hasColon:
      let s = getEnv(ctx.identStr)
      if s.len == 0:
        return err(word)
      ctx.s &= s
    else:
      if not existsEnv(ctx.identStr):
        return err(word)
      ctx.s &= getEnv(ctx.identStr)
  of '+':
    if ctx.hasColon:
      if getEnv(ctx.identStr).len > 0:
        ctx.s &= word
    else:
      if existsEnv(ctx.identStr):
        ctx.s &= word
  else: assert false
  ctx.subChar = '\0'
  ctx.identStr = ""
  ctx.hasColon = false
  ctx.state = usNormal
  return ok()

proc stateCurlyExpand(ctx: var UnquoteContext; c: char): ChaPathResult[void] =
  # ${ident:-[word], ${ident:=[word], ${ident:?[word], ${ident:+[word]
  # word must be unquoted too.
  let word = ?unquote(ctx.p, ctx.i, some('}'))
  return ctx.flushCurlyExpand(word)

proc unquote(p: string; starti: var int; terminal: Option[char]):
    ChaPathResult[string] =
  var ctx = UnquoteContext(p: p, i: starti, terminal: terminal)
  while ctx.i < p.len:
    let c = p[ctx.i]
    case ctx.state
    of usNormal:
      if not ctx.stateNormal(c):
        break
    of usTilde: ctx.stateTilde(c)
    of usBslash: ctx.stateBSlash(c)
    of usDollar: ?ctx.stateDollar(c)
    of usIdent: ctx.stateIdent(c)
    of usCurlyStart: ?ctx.stateCurlyStart(c)
    of usCurly: ?ctx.stateCurly(c)
    of usCurlyHash: ?ctx.stateCurlyHash(c)
    of usCurlyPerc: ?ctx.stateCurlyPerc(c)
    of usCurlyColon: ?ctx.stateCurlyColon(c)
    of usCurlyExpand: ?ctx.stateCurlyExpand(c)
    inc ctx.i
  case ctx.state
  of usNormal: discard
  of usTilde: ctx.flushTilde()
  of usBslash: ctx.s &= '\\'
  of usDollar: ctx.s &= '$'
  of usIdent: ctx.flushIdent()
  of usCurlyStart, usCurly, usCurlyHash, usCurlyPerc, usCurlyColon:
    return err("} expected")
  of usCurlyExpand:
    ?ctx.flushCurlyExpand("")
  starti = ctx.i
  return ok(ctx.s)

proc unquote(p: string): ChaPathResult[string] =
  var dummy = 0
  return unquote(p, dummy, none(char))

proc toJS*(ctx: JSContext; p: ChaPath): JSValue =
  toJS(ctx, $p)

proc fromJS*(ctx: JSContext; val: JSValue; res: var ChaPath): Opt[void] =
  return ctx.fromJS(val, string(res))

proc unquote*(p: ChaPath): ChaPathResult[string] =
  let s = ?unquote(string(p))
  return ok(normalizedPath(s))

proc unquoteGet*(p: ChaPath): string =
  return p.unquote().get
