{.push raises: [].}

import std/options
import std/os

import monoucha/fromjs
import monoucha/javascript
import monoucha/tojs
import types/opt
import utils/myposix
import utils/twtstr

type ChaPath* = distinct string

proc `$`*(p: ChaPath): string =
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

  UnquoteState = enum
    usNormal, usTilde, usDollar, usIdent, usBslash, usCurly, usCurlyHash,
    usCurlyColon, usCurlyExpand

  ChaPathError = string

  ChaPathResult[T] = Result[T, ChaPathError]

proc unquote(p: string; starti: var int; terminal: Option[char]):
    ChaPathResult[string]
proc stateCurlyStart(ctx: var UnquoteContext; c: char): ChaPathResult[void]

proc stateNormal(ctx: var UnquoteContext; c: char) =
  case c
  of '$': ctx.state = usDollar
  of '\\': ctx.state = usBslash
  of '~':
    if ctx.i == 0:
      ctx.identStr = "~"
      ctx.state = usTilde
    else:
      ctx.s &= c
  else:
    ctx.s &= c

proc stateTilde(ctx: var UnquoteContext; c: char) =
  if c != '/':
    ctx.identStr &= c
  else:
    ctx.s &= expandPath(ctx.identStr) & '/'
    ctx.state = usNormal

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
    # Use getAppFilename so that any symbolic links are resolved.
    ctx.s &= myposix.getAppFilename()
    ctx.state = usNormal
  of AsciiAlpha:
    ctx.identStr = $c
    ctx.state = usIdent
  of '{':
    inc ctx.i
    if ctx.i >= ctx.p.len:
      return err("} expected")
    let c = ctx.p[ctx.i]
    return ctx.stateCurlyStart(c)
  else:
    return err("unrecognized dollar substitution $" & c)
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
  of '%': # backwards compat
    ctx.state = usCurly
  of BareChars - {'1'..'9'}:
    dec ctx.i
    ctx.state = usCurly
  else:
    return err("unexpected character in substitution: '" & c & "'")
  return ok()

proc stateCurly(ctx: var UnquoteContext; c: char): ChaPathResult[void] =
  # ${ident
  case c
  of '}':
    if ctx.identStr == "0":
      ctx.s &= myposix.getAppFilename()
    else:
      ctx.s &= getEnv(ctx.identStr)
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
    return err("parameter substitution is not supported")
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
      ctx.s &= getEnvEmpty(ctx.identStr, word)
    else:
      ctx.s &= getEnv(ctx.identStr, word)
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
  var ctx = UnquoteContext(p: p, i: starti)
  while ctx.i < p.len:
    let c = p[ctx.i]
    if ctx.state in {usNormal, usTilde, usDollar, usIdent} and
        terminal.isSome and terminal.get == c:
      break
    case ctx.state
    of usNormal: ctx.stateNormal(c)
    of usTilde: ctx.stateTilde(c)
    of usBslash: ctx.stateBSlash(c)
    of usDollar: ?ctx.stateDollar(c)
    of usIdent: ctx.stateIdent(c)
    of usCurly: ?ctx.stateCurly(c)
    of usCurlyHash: ?ctx.stateCurlyHash(c)
    of usCurlyColon: ?ctx.stateCurlyColon(c)
    of usCurlyExpand: ?ctx.stateCurlyExpand(c)
    inc ctx.i
  case ctx.state
  of usNormal: discard
  of usTilde: ctx.s &= expandPath(ctx.identStr)
  of usBslash: ctx.s &= '\\'
  of usDollar: ctx.s &= '$'
  of usIdent: ctx.flushIdent()
  of usCurly, usCurlyHash, usCurlyColon:
    return err("} expected")
  of usCurlyExpand: ?ctx.flushCurlyExpand("")
  starti = ctx.i
  return ok(ctx.s)

proc unquote(p: string): ChaPathResult[string] =
  var dummy = 0
  return unquote(p, dummy, none(char))

proc toJS*(ctx: JSContext; p: ChaPath): JSValue =
  toJS(ctx, $p)

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var ChaPath): Opt[void] =
  return ctx.fromJS(val, string(res))

proc unquote*(p: ChaPath; base: string): ChaPathResult[string] =
  var s = ?unquote(string(p))
  if s.len == 0:
    return ok(s)
  if base != "" and s[0] != '/':
    s.insert(base & '/', 0)
  return ok(normalizedPath(s))

proc unquoteGet*(p: ChaPath): string =
  return p.unquote("").get

{.pop.} # raises: []
