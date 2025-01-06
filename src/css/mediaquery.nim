import std/options

import css/cssparser
import css/cssvalues
import html/script
import types/opt
import types/winattrs
import utils/twtstr

type
  MediaQueryParser = object
    at: int
    cvals: seq[CSSComponentValue]
    attrs: ptr WindowAttributes

  MediaType = enum
    mtAll = "all"
    mtPrint = "print"
    mtScreen = "screen"
    mtSpeech = "speech"
    mtTty = "tty"

  MediaConditionType = enum
    mctNot, mctAnd, mctOr, mctFeature, mctMedia

  MediaFeatureType = enum
    mftColor = "color"
    mftGrid = "grid"
    mftHover = "hover"
    mftPrefersColorScheme = "prefers-color-scheme"
    mftWidth = "width"
    mftHeight = "height"
    mftScripting = "scripting"

  LengthRange = object
    s: Slice[CSSLength]
    aeq: bool
    beq: bool

  MediaFeature = object
    case t: MediaFeatureType
    of mftColor:
      range: Slice[int]
    of mftGrid, mftHover, mftPrefersColorScheme, mftScripting:
      b: bool
    of mftWidth, mftHeight:
      lengthrange*: LengthRange

  MediaQuery* = ref object
    case t: MediaConditionType
    of mctMedia:
      media: MediaType
    of mctFeature:
      feature: MediaFeature
    of mctNot:
      n: MediaQuery
    of mctOr, mctAnd:
      left: MediaQuery
      right: MediaQuery

  MediaQueryComparison = enum
    mqcEq, mqcGt, mqcLt, mqcGe, mqcLe

# Forward declarations
proc parseMediaCondition(parser: var MediaQueryParser; non = false;
  noor = false): Opt[MediaQuery]

# Serializer.
# As usual, the spec is incomplete, so it's hard to say if it's
# compliant.  What can you do :/
func `$`(mf: MediaFeature): string =
  case mf.t
  of mftColor:
    return $mf.range.a & " <= " & $mf.t & " <= " & $mf.range.b
  of mftGrid:
    return "grid: " & $int(mf.b)
  of mftHover:
    return "hover: " & [false: "none", true: "hover"][mf.b]
  of mftPrefersColorScheme:
    return "prefers-color-scheme: " & [false: "light", true: "dark"][mf.b]
  of mftWidth, mftHeight:
    result = $mf.lengthrange.s.a & " <"
    if mf.lengthrange.aeq:
      result &= '='
    result &= ' ' & $mf.t & " <"
    if mf.lengthrange.beq:
      result &= '='
    result &= ' ' & $mf.lengthrange.s.b
  of mftScripting:
    return "scripting: " & [false: "none", true: "enabled"][mf.b]

func `$`(mq: MediaQuery): string =
  case mq.t
  of mctMedia: return $mq.media
  of mctFeature: return $mq.feature
  of mctNot: return "not (" & $mq.n
  of mctOr: return "(" & $mq.left & ") or (" & $mq.right & ")"
  of mctAnd: return "(" & $mq.left & ") or (" & $mq.right & ")"

func `$`*(mqlist: seq[MediaQuery]): string =
  result = ""
  for it in mqlist:
    if result.len > 0:
      result &= ", "
    result &= $it

const RangeFeatures = {mftColor, mftWidth, mftHeight}

proc has(parser: MediaQueryParser; i = 0): bool =
  return parser.cvals.len > parser.at + i

proc consume(parser: var MediaQueryParser): CSSComponentValue =
  result = parser.cvals[parser.at]
  inc parser.at

proc consumeSimpleBlock(parser: var MediaQueryParser): Opt[CSSSimpleBlock] =
  let res = parser.consume()
  if res of CSSSimpleBlock:
    return ok(CSSSimpleBlock(res))
  return err()

proc reconsume(parser: var MediaQueryParser) =
  dec parser.at

proc peek(parser: MediaQueryParser; i = 0): CSSComponentValue =
  return parser.cvals[parser.at + i]

proc skipBlanks(parser: var MediaQueryParser) =
  while parser.has():
    let cval = parser.peek()
    if cval of CSSToken and CSSToken(cval).t == cttWhitespace:
      inc parser.at
    else:
      break

proc getBoolFeature(feature: MediaFeatureType): Opt[MediaQuery] =
  case feature
  of mftGrid, mftHover, mftPrefersColorScheme:
    return ok(MediaQuery(
      t: mctFeature,
      feature: MediaFeature(t: feature, b: true)
    ))
  of mftColor:
    return ok(MediaQuery(
      t: mctFeature,
      feature: MediaFeature(t: feature, range: 1..high(int))
    ))
  else:
    return err()

proc skipBlanksCheckHas(parser: var MediaQueryParser): Err[void] =
  parser.skipBlanks()
  if parser.has():
    return ok()
  return err()

proc consumeToken(parser: var MediaQueryParser): Opt[CSSToken] =
  let cval = parser.consume()
  if not (cval of CSSToken):
    parser.reconsume()
    return err()
  return ok(CSSToken(cval))

proc consumeIdent(parser: var MediaQueryParser): Opt[CSSToken] =
  let tok = ?parser.consumeToken()
  if tok.t != cttIdent:
    parser.reconsume()
    return err()
  return ok(tok)

proc consumeInt(parser: var MediaQueryParser): Opt[int] =
  let tok = ?parser.consumeToken()
  if tok.t != cttNumber or tok.tflagb == tflagbInteger:
    parser.reconsume()
    return err()
  return ok(int(tok.nvalue))

proc parseMqInt(parser: var MediaQueryParser; ifalse, itrue: int): Opt[bool] =
  let i = ?parser.consumeInt()
  if i == ifalse:
    return ok(false)
  elif i == itrue:
    return ok(true)
  return err()

proc parseBool(parser: var MediaQueryParser; sfalse, strue: string): Opt[bool] =
  let tok = ?parser.consumeIdent()
  if tok.value.equalsIgnoreCase(strue):
    return ok(true)
  elif tok.value.equalsIgnoreCase(sfalse):
    return ok(false)
  else:
    return err()

proc parseBool(parser: var MediaQueryParser; sfalse, sfalse2, strue: string):
    Opt[bool] =
  let tok = ?parser.consumeIdent()
  if tok.value.equalsIgnoreCase(strue):
    return ok(true)
  elif tok.value.equalsIgnoreCase(sfalse) or
      tok.value.equalsIgnoreCase(sfalse2):
    return ok(false)
  else:
    return err()

proc parseComparison(parser: var MediaQueryParser): Opt[MediaQueryComparison] =
  let tok = ?parser.consumeToken()
  if tok != cttDelim or tok.cvalue notin {'=', '<', '>'}:
    return err()
  case tok.cvalue
  of '<':
    if parser.has():
      parser.skipBlanks()
      let tok = ?parser.consumeToken()
      if tok == cttDelim and tok.cvalue == '=':
        return ok(mqcLe)
      parser.reconsume()
    return ok(mqcLt)
  of '>':
    if parser.has():
      parser.skipBlanks()
      let tok = ?parser.consumeToken()
      if tok == cttDelim and tok.cvalue == '=':
        return ok(mqcGe)
      parser.reconsume()
    return ok(mqcGt)
  of '=': return ok(mqcEq)
  else: return err()

proc parseIntRange(parser: var MediaQueryParser; ismin, ismax: bool):
    Opt[Slice[int]] =
  if ismin:
    let a = ?parser.consumeInt()
    return ok(a .. int.high)
  if ismax:
    let b = ?parser.consumeInt()
    return ok(0 .. b)
  let comparison = ?parser.parseComparison()
  ?parser.skipBlanksCheckHas()
  let n = ?parser.consumeInt()
  case comparison
  of mqcEq: #TODO should be >= 0 (for color at least)
    return ok(n .. n)
  of mqcGt, mqcGe:
    return ok(n .. int.high)
  of mqcLt, mqcLe:
    return ok(0 .. n)

proc parseLength(parser: var MediaQueryParser): Opt[CSSLength] =
  let cval = parser.consume()
  let len = ?parseLength(cval, parser.attrs[])
  if len.u != clPx:
    return err()
  return ok(len)

proc parseLengthRange(parser: var MediaQueryParser; ismin, ismax: bool):
    Opt[LengthRange] =
  if ismin:
    let a = ?parser.parseLength()
    let b = cssLength(Inf)
    return ok(LengthRange(s: a .. b, aeq: true, beq: false))
  if ismax:
    let a = cssLength(0)
    let b = ?parser.parseLength()
    return ok(LengthRange(s: a .. b, aeq: false, beq: true))
  let comparison = ?parser.parseComparison()
  ?parser.skipBlanksCheckHas()
  let len = ?parser.parseLength()
  case comparison
  of mqcEq:
    return ok(LengthRange(s: len .. len, aeq: true, beq: true))
  of mqcGt, mqcGe:
    let b = cssLength(Inf)
    return ok(LengthRange(s: len .. b, aeq: comparison == mqcGe, beq: false))
  of mqcLt, mqcLe:
    let a = cssLength(0)
    return ok(LengthRange(s: a .. len, aeq: false, beq: comparison == mqcLe))

proc parseFeature0(parser: var MediaQueryParser; t: MediaFeatureType;
    ismin, ismax: bool): Opt[MediaFeature] =
  let feature = case t
  of mftGrid:
    let b = ?parser.parseMqInt(0, 1)
    MediaFeature(t: t, b: b)
  of mftHover:
    let b = ?parser.parseBool("none", "hover")
    MediaFeature(t: t, b: b)
  of mftPrefersColorScheme:
    let b = ?parser.parseBool("light", "dark")
    MediaFeature(t: t, b: b)
  of mftColor:
    let range = ?parser.parseIntRange(ismin, ismax)
    MediaFeature(t: t, range: range)
  of mftWidth, mftHeight:
    let range = ?parser.parseLengthRange(ismin, ismax)
    MediaFeature(t: t, lengthrange: range)
  of mftScripting:
    if ismin or ismax:
      return err()
    let b = ?parser.parseBool("none", "initial-only", "enabled")
    MediaFeature(t: t, b: b)
  return ok(feature)

proc parseFeature(parser: var MediaQueryParser; t: MediaFeatureType;
    ismin, ismax: bool): Opt[MediaQuery] =
  if not parser.has():
    return getBoolFeature(t)
  let tok = ?parser.consumeToken()
  if t notin RangeFeatures and (tok.t != cttColon or ismin or ismax):
    return err()
  if tok.t != cttColon:
    # for range parsing; e.g. we might have gotten a delim or similar
    parser.reconsume()
  ?parser.skipBlanksCheckHas()
  let feature = ?parser.parseFeature0(t, ismin, ismax)
  if parser.skipBlanksCheckHas().isSome:
    # die if there's still something left to parse
    return err()
  return ok(MediaQuery(t: mctFeature, feature: feature))

proc parseMediaInParens(parser: var MediaQueryParser): Opt[MediaQuery] =
  let sb = ?parser.consumeSimpleBlock()
  if sb.token.t != cttLparen:
    return err()
  var fparser = MediaQueryParser(cvals: sb.value, attrs: parser.attrs)
  fparser.skipBlanks()
  let tok = ?fparser.consumeIdent()
  fparser.skipBlanks()
  if tok.value.equalsIgnoreCase("not"):
    return fparser.parseMediaCondition(non = true)
  var tokval = tok.value
  let ismin = tokval.startsWithIgnoreCase("min-")
  let ismax = tokval.startsWithIgnoreCase("max-")
  if ismin or ismax:
    tokval = tokval.substr(4)
  let x = parseEnumNoCase[MediaFeatureType](tokval)
  if x.isNone:
    return err()
  return fparser.parseFeature(x.get, ismin, ismax)

proc parseMediaOr(parser: var MediaQueryParser; left: MediaQuery):
    Opt[MediaQuery] =
  let right = ?parser.parseMediaCondition()
  return ok(MediaQuery(t: mctOr, left: left, right: right))

proc parseMediaAnd(parser: var MediaQueryParser; left: MediaQuery):
    Opt[MediaQuery] =
  let right = ?parser.parseMediaCondition()
  return ok(MediaQuery(t: mctAnd, left: left, right: right))

func negateIf(mq: MediaQuery; non: bool): MediaQuery =
  if non:
    return MediaQuery(t: mctNot, n: mq)
  return mq

proc parseMediaCondition(parser: var MediaQueryParser; non = false;
    noor = false): Opt[MediaQuery] =
  var non = non
  if not non:
    let tokx = parser.consumeIdent()
    if tokx.isSome:
      if tokx.get.value.equalsIgnoreCase("not"):
        non = true
      else:
        parser.reconsume()
  ?parser.skipBlanksCheckHas()
  let res = (?parser.parseMediaInParens()).negateIf(non)
  if parser.skipBlanksCheckHas().isNone:
    return ok(res)
  let tok = ?parser.consumeIdent()
  parser.skipBlanks()
  if tok.value.equalsIgnoreCase("and"):
    return parser.parseMediaAnd(res)
  elif tok.value.equalsIgnoreCase("or"):
    if noor:
      return err()
    return parser.parseMediaOr(res)
  return ok(res)

proc parseMediaQuery(parser: var MediaQueryParser): Opt[MediaQuery] =
  ?parser.skipBlanksCheckHas()
  let tokx = parser.consumeIdent()
  if tokx.isNone:
    return parser.parseMediaCondition()
  let tok = tokx.get
  if (let non = tok.value.equalsIgnoreCase("not");
        non or tok.value.equalsIgnoreCase("only")):
    ?parser.skipBlanksCheckHas()
    if (let tokx = parser.consumeIdent(); tokx.isSome):
      if (let x = parseEnumNoCase[MediaType](tokx.get.value); x.isSome):
        let res = MediaQuery(t: mctMedia, media: x.get).negateIf(non)
        if parser.skipBlanksCheckHas().isNone:
          return ok(res)
        let tok = ?parser.consumeIdent()
        if tok.value.equalsIgnoreCase("and"):
          ?parser.skipBlanksCheckHas()
          return parser.parseMediaAnd(res)
      return err()
    return parser.parseMediaCondition(non)
  elif (let x = parseEnumNoCase[MediaType](tok.value); x.isSome):
    let res = MediaQuery(t: mctMedia, media: x.get)
    if parser.skipBlanksCheckHas().isNone:
      return ok(res)
    if (let tokx = parser.consumeIdent(); tokx.isSome):
      return parser.parseMediaAnd(res)
    return parser.parseMediaCondition()
  else:
    return err()

proc parseMediaQueryList*(cvals: seq[CSSComponentValue];
    attrs: ptr WindowAttributes): seq[MediaQuery] =
  result = @[]
  let cseplist = cvals.parseCommaSepComponentValues()
  for list in cseplist:
    var parser = MediaQueryParser(cvals: list, attrs: attrs)
    let query = parser.parseMediaQuery()
    if query.isSome:
      result.add(query.get)
    else:
      # sadly, the standard doesn't let us skip this :/
      let all = MediaQuery(t: mctMedia, media: mtAll)
      result.add(MediaQuery(t: mctNot, n: all))

type
  MediaApplyContext = object
    scripting: ScriptingMode
    attrsp: ptr WindowAttributes

func appliesLR(feature: MediaFeature; n: float64): bool =
  let a = feature.lengthrange.s.a.num
  let b = feature.lengthrange.s.b.num
  return (feature.lengthrange.aeq and a == n or a < n) and
    (feature.lengthrange.beq and b == n or n < b)

func applies(ctx: MediaApplyContext; feature: MediaFeature): bool =
  case feature.t
  of mftColor:
    return 8 in feature.range
  of mftGrid:
    return feature.b
  of mftHover:
    return feature.b
  of mftPrefersColorScheme:
    return feature.b == ctx.attrsp.prefersDark
  of mftWidth:
    return feature.appliesLR(float64(ctx.attrsp.widthPx))
  of mftHeight:
    return feature.appliesLR(float64(ctx.attrsp.heightPx))
  of mftScripting:
    return feature.b == (ctx.scripting != smFalse)

func applies(ctx: MediaApplyContext; mq: MediaQuery): bool =
  case mq.t
  of mctMedia:
    case mq.media
    of mtAll: return true
    of mtPrint: return false
    of mtScreen: return true
    of mtSpeech: return false
    of mtTty: return true
  of mctNot:
    return not ctx.applies(mq.n)
  of mctAnd:
    return ctx.applies(mq.left) and ctx.applies(mq.right)
  of mctOr:
    return ctx.applies(mq.left) or ctx.applies(mq.right)
  of mctFeature:
    return ctx.applies(mq.feature)

func applies(ctx: MediaApplyContext; mqlist: seq[MediaQuery]): bool =
  for mq in mqlist:
    if ctx.applies(mq):
      return true
  return false

func applies*(mqlist: seq[MediaQuery]; scripting: ScriptingMode;
    attrsp: ptr WindowAttributes): bool =
  let ctx = MediaApplyContext(scripting: scripting, attrsp: attrsp)
  return ctx.applies(mqlist)
