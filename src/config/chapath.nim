{.push raises: [].}

when NimMajor >= 2:
  import std/assertions
import std/posix

import js/fromjs
import js/jsutils
import js/quickjs
import js/tojs
import utils/chaos
import utils/cowstr
import utils/opt
import utils/twtstr

type ChaPath* = distinct Str

template `$`*(p: ChaPath): string =
  $Str(p)

type
  UnquoteContext = object
    state: UnquoteState
    s: Growbuf
    p: Str
    i: int
    identStr: Growbuf
    subChar: char
    hasColon: bool

  UnquoteState = enum
    usNormal, usTilde, usDollar, usIdent, usBslash, usCurly, usCurlyHash,
    usCurlyColon, usCurlyExpand

  ChaPathResult[T] = Result[T, Str]

proc unquote(p: Str; starti: var int; terminal: char): ChaPathResult[Str]
proc stateCurlyStart(ctx: var UnquoteContext; c: char): ChaPathResult[void]

proc stateNormal(ctx: var UnquoteContext; c: char) =
  case c
  of '$': ctx.state = usDollar
  of '\\': ctx.state = usBslash
  of '~':
    if ctx.i == 0:
      ctx.identStr = initGrowbuf("~")
      ctx.state = usTilde
    else:
      ctx.s &= c
  else:
    ctx.s &= c

proc stateTilde(ctx: var UnquoteContext; c: char) =
  if c != '/':
    ctx.identStr &= c
  else:
    ctx.s &= expandPath(move(ctx.identStr).toStr())
    ctx.s &= '/'
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
    ctx.s &= int(getpid())
    ctx.state = usNormal
  of '0':
    # Use getAppFilename so that any symbolic links are resolved.
    ctx.s &= chaos.getAppFilename()
    ctx.state = usNormal
  of AsciiAlpha:
    ctx.identStr = initGrowbuf(c)
    ctx.state = usIdent
  of '{':
    inc ctx.i
    if ctx.i >= ctx.p.len:
      return err(str("} expected"))
    let c = ctx.p[ctx.i]
    return ctx.stateCurlyStart(c)
  else:
    return err(initStrM("unrecognized dollar substitution $", c))
  ok()

proc flushIdent(ctx: var UnquoteContext) =
  ctx.s &= getEnvEmpty(move(ctx.identStr).toStr().toCString())

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
    return err(initStrM("unexpected character in substitution: '", c, '\''))
  return ok()

proc stateCurly(ctx: var UnquoteContext; c: char): ChaPathResult[void] =
  # ${ident
  case c
  of '}':
    if ctx.identStr == "0":
      ctx.s &= chaos.getAppFilename()
      ctx.identStr.setLen(0)
    else:
      ctx.s &= getEnvEmpty(move(ctx.identStr).toStr())
    ctx.state = usNormal
    return ok()
  of '$': # allow $ as first char only
    if ctx.identStr.len > 0:
      return err(str("unexpected dollar sign in substitution"))
    ctx.identStr &= c
    return ok()
  of ':', '-', '?', '+': # note: we don't support `=' (assign)
    if ctx.identStr.len == 0:
      return err(str("substitution without parameter name"))
    if c == ':':
      ctx.state = usCurlyColon
    else:
      ctx.subChar = c
      ctx.state = usCurlyExpand
    return ok()
  of '1'..'9':
    return err(str("parameter substitution is not supported"))
  of BareChars - {'1'..'9'}:
    ctx.identStr &= c
    return ok()
  else:
    return err(initStrM("unexpected character in substitution: '", c, '\''))

proc stateCurlyHash(ctx: var UnquoteContext; c: char): ChaPathResult[void] =
  # ${#ident
  if c == '}':
    let s = getEnvEmpty(move(ctx.identStr).toStr())
    ctx.s &= $s.len
    ctx.state = usNormal
    return ok()
  if c == '$': # allow $ as first char only
    if ctx.identStr.len > 0:
      return err(str("unexpected dollar sign in substitution"))
    # fall through
  elif c notin BareChars:
    return err(initStrM("unexpected character in substitution: '", c, '\''))
  ctx.identStr &= c
  return ok()

proc stateCurlyColon(ctx: var UnquoteContext; c: char): ChaPathResult[void] =
  # ${ident:
  if c notin {'-', '?', '+'}: # Note: we don't support `=' (assign)
    return err(initStrM("unexpected character after colon: '", c, '\''))
  ctx.hasColon = true
  ctx.subChar = c
  ctx.state = usCurlyExpand
  return ok()

proc flushCurlyExpand(ctx: var UnquoteContext; word: Str):
    ChaPathResult[void] =
  let ident = move(ctx.identStr).toStr()
  case ctx.subChar
  of '-':
    if ctx.hasColon:
      ctx.s &= getEnvEmpty(ident, word)
    else:
      let cs = getEnvCString(ident.toCString())
      if cs != nil:
        ctx.s.addCString(cs)
      else:
        ctx.s &= word
  of '?':
    if ctx.hasColon:
      let s = getEnvEmpty(ident)
      if s.len == 0:
        return err(word)
      ctx.s &= s
    else:
      let cs = getEnvCString(ident.toCString())
      if cs == nil:
        return err(word)
      ctx.s.addCString(cs)
  of '+':
    if ctx.hasColon:
      if getEnvEmpty(ident).len > 0:
        ctx.s &= word
    else:
      if getEnvCString(ident.toCString()) != nil:
        ctx.s &= word
  else: assert false
  ctx.subChar = '\0'
  ctx.hasColon = false
  ctx.state = usNormal
  return ok()

proc stateCurlyExpand(ctx: var UnquoteContext; c: char): ChaPathResult[void] =
  # ${ident:-[word], ${ident:=[word], ${ident:?[word], ${ident:+[word]
  # word must be unquoted too.
  let word = ?unquote(ctx.p, ctx.i, '}')
  return ctx.flushCurlyExpand(word)

proc unquote(p: Str; starti: var int; terminal: char): ChaPathResult[Str] =
  var ctx = UnquoteContext(p: p, i: starti)
  while ctx.i < p.len:
    let c = p[ctx.i]
    if ctx.state in {usNormal, usTilde, usDollar, usIdent} and
        terminal != '\0' and terminal == c:
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
  of usTilde: ctx.s &= expandPath(move(ctx.identStr).toStr())
  of usBslash: ctx.s &= '\\'
  of usDollar: ctx.s &= '$'
  of usIdent: ctx.flushIdent()
  of usCurly, usCurlyHash, usCurlyColon:
    return err(str("} expected"))
  of usCurlyExpand: ?ctx.flushCurlyExpand(str(""))
  starti = ctx.i
  ok(ctx.s.toStr())

proc unquote(p: Str): ChaPathResult[Str] =
  var dummy = 0
  return unquote(p, dummy, '\0')

proc toJS*(ctx: JSContext; p: ChaPath): JSValue =
  toJS(ctx, $p)

proc fromJS*(ctx: JSContext; val: JSValueConst; res: var ChaPath):
    JSCode =
  ctx.fromJS(val, Str(res))

proc unquote*(p: ChaPath; base: Str): ChaPathResult[Str] =
  var s = ?unquote(Str(p))
  if s.len <= 0:
    return ok(s)
  if base != "" and s[0] != '/':
    s.insert(initStrM(base, '/'), 0)
  return ok(normalizedPath(s))

proc unquoteGet*(p: ChaPath): Str =
  p.unquote(str("")).get

{.pop.} # raises: []
