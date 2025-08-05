{.push raises: [].}

import std/options

import config/conftypes
import css/cssparser
import css/cssvalues
import html/catom
import html/script
import types/opt
import types/winattrs
import utils/twtstr

type
  MediaQueryParser = object
    ctx: CSSParser
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
    mftColorIndex = "color-index"
    mftMonochrome = "monochrome"
    mftGrid = "grid"
    mftHover = "hover"
    mftPrefersColorScheme = "prefers-color-scheme"
    mftWidth = "width"
    mftHeight = "height"
    mftScripting = "scripting"
    mftContentType = "-cha-content-type"

  LengthRange = object
    s: Slice[float32]
    aeq: bool
    beq: bool

  MediaScripting = enum
    msNone = "none"
    msInitialOnly = "initial-only"
    msEnabled = "enabled"

  MediaFeature = object
    case t: MediaFeatureType
    of mftColor, mftColorIndex, mftMonochrome:
      range: Slice[int]
    of mftGrid, mftHover, mftPrefersColorScheme:
      b: bool
    of mftScripting:
      ms: MediaScripting
    of mftWidth, mftHeight:
      lengthrange: LengthRange
    of mftContentType:
      a: CAtom

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
  noor = false; nested = false): Opt[MediaQuery]

# Serializer.
# As usual, the spec is incomplete, so it's hard to say if it's
# compliant.  What can you do :/
func `$`(mf: MediaFeature): string =
  case mf.t
  of mftColor, mftColorIndex, mftMonochrome:
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
    return "scripting: " & $mf.ms
  of mftContentType:
    return $mf.t & ": \"" & ($mf.a).dqEscape() & '"'

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

const RangeFeatures = {
  mftColor, mftColorIndex, mftMonochrome, mftWidth, mftHeight
}

proc has(parser: var MediaQueryParser): bool =
  return parser.ctx.has()

proc consume(parser: var MediaQueryParser): CSSToken =
  return parser.ctx.consume()

proc peekTokenType(parser: var MediaQueryParser): CSSTokenType =
  return parser.ctx.peekTokenType()

proc seek(parser: var MediaQueryParser) =
  parser.ctx.seek()

proc skipBlanks(parser: var MediaQueryParser) =
  parser.ctx.skipBlanks()

proc getBoolFeature(feature: MediaFeatureType): Opt[MediaQuery] =
  case feature
  of mftGrid, mftHover, mftPrefersColorScheme:
    return ok(MediaQuery(
      t: mctFeature,
      feature: MediaFeature(t: feature, b: true)
    ))
  of mftColor, mftColorIndex, mftMonochrome:
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

proc consumeIdent(parser: var MediaQueryParser): Opt[CSSToken] =
  if parser.peekTokenType() != cttIdent:
    return err()
  return ok(parser.consume())

proc consumeString(parser: var MediaQueryParser): Opt[CSSToken] =
  if parser.peekTokenType() != cttString:
    return err()
  return ok(parser.consume())

proc consumeInt(parser: var MediaQueryParser): Opt[int] =
  if parser.peekTokenType() != cttINumber:
    return err()
  return ok(int(parser.consume().num))

proc parseMqInt(parser: var MediaQueryParser; ifalse, itrue: int): Opt[bool] =
  let i = ?parser.consumeInt()
  if i == ifalse:
    return ok(false)
  elif i == itrue:
    return ok(true)
  return err()

proc parseBool(parser: var MediaQueryParser; sfalse, strue: string): Opt[bool] =
  let tok = ?parser.consumeIdent()
  if tok.s.equalsIgnoreCase(strue):
    return ok(true)
  elif tok.s.equalsIgnoreCase(sfalse):
    return ok(false)
  else:
    return err()

proc parseComparison(parser: var MediaQueryParser): Opt[MediaQueryComparison] =
  let tok = parser.consume()
  case tok.t
  of cttLt:
    if parser.skipBlanksCheckHas().isOk:
      if parser.peekTokenType() == cttEquals:
        discard parser.consume()
        return ok(mqcLe)
    return ok(mqcLt)
  of cttGt:
    if parser.skipBlanksCheckHas().isOk:
      if parser.peekTokenType() == cttEquals:
        discard parser.consume()
        return ok(mqcGe)
    return ok(mqcGt)
  of cttEquals: return ok(mqcEq)
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

proc parseLength(parser: var MediaQueryParser): Opt[float32] =
  let len = ?parser.ctx.parseLength(parser.attrs[], hasAuto = false,
    allowNegative = true)
  if len.auto or len.perc != 0:
    return err()
  return ok(len.npx)

proc parseLengthRange(parser: var MediaQueryParser; ismin, ismax: bool):
    Opt[LengthRange] =
  if ismin:
    let a = ?parser.parseLength()
    return ok(LengthRange(s: a .. float32(Inf), aeq: true, beq: false))
  if ismax:
    let b = ?parser.parseLength()
    return ok(LengthRange(s: 0f32 .. b, aeq: false, beq: true))
  let comparison = ?parser.parseComparison()
  ?parser.skipBlanksCheckHas()
  let len = ?parser.parseLength()
  case comparison
  of mqcEq:
    return ok(LengthRange(s: len .. len, aeq: true, beq: true))
  of mqcGt, mqcGe:
    let b = float32(Inf)
    return ok(LengthRange(s: len .. b, aeq: comparison == mqcGe, beq: false))
  of mqcLt, mqcLe:
    return ok(LengthRange(s: 0f32 .. len, aeq: false, beq: comparison == mqcLe))

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
  of mftColor, mftColorIndex, mftMonochrome:
    let range = ?parser.parseIntRange(ismin, ismax)
    MediaFeature(t: t, range: range)
  of mftWidth, mftHeight:
    let range = ?parser.parseLengthRange(ismin, ismax)
    MediaFeature(t: t, lengthrange: range)
  of mftScripting:
    if ismin or ismax:
      return err()
    let tok = ?parser.consumeIdent()
    let ms = ?parseEnumNoCase[MediaScripting](tok.s)
    MediaFeature(t: t, ms: ms)
  of mftContentType:
    let tok = ?parser.consumeString()
    MediaFeature(t: t, a: tok.s.toAtom())
  return ok(feature)

proc parseFeature(parser: var MediaQueryParser; t: MediaFeatureType;
    ismin, ismax: bool): Opt[MediaQuery] =
  if not parser.has():
    return err()
  let nt = parser.peekTokenType()
  if nt == cttRparen:
    let res = ?getBoolFeature(t)
    parser.seek()
    return ok(res)
  if t notin RangeFeatures and (nt != cttColon or ismin or ismax):
    return err()
  if nt == cttColon:
    # for range parsing; e.g. we might have gotten a delim or similar
    discard parser.consume()
  ?parser.skipBlanksCheckHas()
  let feature = ?parser.parseFeature0(t, ismin, ismax)
  ?parser.skipBlanksCheckHas()
  if parser.consume().t != cttRparen:
    # die if there's still something left to parse
    return err()
  return ok(MediaQuery(t: mctFeature, feature: feature))

proc parseMediaInParens(parser: var MediaQueryParser): Opt[MediaQuery] =
  if parser.consume().t != cttLparen:
    return err()
  ?parser.skipBlanksCheckHas()
  let tok = ?parser.consumeIdent()
  parser.skipBlanks()
  if tok.s.equalsIgnoreCase("not"):
    return parser.parseMediaCondition(non = true, nested = true)
  var tokval = tok.s
  let ismin = tokval.startsWithIgnoreCase("min-")
  let ismax = tokval.startsWithIgnoreCase("max-")
  if ismin or ismax:
    tokval = tokval.substr(4)
  let t = ?parseEnumNoCase[MediaFeatureType](tokval)
  parser.parseFeature(t, ismin, ismax)

proc parseMediaOr(parser: var MediaQueryParser; left: MediaQuery):
    Opt[MediaQuery] =
  let right = ?parser.parseMediaCondition(nested = true)
  return ok(MediaQuery(t: mctOr, left: left, right: right))

proc parseMediaAnd(parser: var MediaQueryParser; left: MediaQuery;
    noor = false): Opt[MediaQuery] =
  let right = ?parser.parseMediaCondition(noor = noor, nested = true)
  return ok(MediaQuery(t: mctAnd, left: left, right: right))

func negateIf(mq: MediaQuery; non: bool): MediaQuery =
  if non:
    return MediaQuery(t: mctNot, n: mq)
  return mq

proc parseMediaCondition(parser: var MediaQueryParser; non = false;
    noor = false; nested = false): Opt[MediaQuery] =
  var non = non
  if not non:
    if parser.ctx.peekIdentNoCase("not"):
      discard parser.consume()
      non = true
  ?parser.skipBlanksCheckHas()
  let res = (?parser.parseMediaInParens()).negateIf(non)
  if parser.skipBlanksCheckHas().isErr:
    return ok(res)
  let tok = ?parser.consumeIdent()
  parser.skipBlanks()
  if tok.s.equalsIgnoreCase("and"):
    return parser.parseMediaAnd(res, noor)
  elif tok.s.equalsIgnoreCase("or"):
    if noor:
      return err()
    return parser.parseMediaOr(res)
  err()

proc parseMediaQuery(parser: var MediaQueryParser): Opt[MediaQuery] =
  ?parser.skipBlanksCheckHas()
  let tokx = parser.consumeIdent()
  if tokx.isErr:
    return parser.parseMediaCondition()
  let tok = tokx.get
  if (let non = tok.s.equalsIgnoreCase("not");
        non or tok.s.equalsIgnoreCase("only")):
    ?parser.skipBlanksCheckHas()
    if tok := parser.consumeIdent():
      if media := parseEnumNoCase[MediaType](tok.s):
        let res = MediaQuery(t: mctMedia, media: media).negateIf(non)
        if parser.skipBlanksCheckHas().isErr:
          return ok(res)
        let tok = ?parser.consumeIdent()
        if tok.s.equalsIgnoreCase("and"):
          ?parser.skipBlanksCheckHas()
          return parser.parseMediaAnd(res)
      return err()
    return parser.parseMediaCondition(non)
  elif media := parseEnumNoCase[MediaType](tok.s):
    let res = MediaQuery(t: mctMedia, media: media)
    if parser.skipBlanksCheckHas().isErr:
      return ok(res)
    let tok = ?parser.consumeIdent()
    if tok.s.equalsIgnoreCase("and"):
      return parser.parseMediaAnd(res, noor = true)
  return err()

proc parseMediaQueryList*(toks: seq[CSSToken]; attrs: ptr WindowAttributes):
    seq[MediaQuery] =
  result = @[]
  for list in toks.parseCommaSepComponentValues():
    var parser = MediaQueryParser(ctx: initCSSParser(list), attrs: attrs)
    if query := parser.parseMediaQuery():
      result.add(query)
    else:
      # sadly, the standard doesn't let us skip this :/
      let all = MediaQuery(t: mctMedia, media: mtAll)
      result.add(MediaQuery(t: mctNot, n: all))

type
  MediaApplyContext = ptr EnvironmentSettings

func appliesLR(feature: MediaFeature; n: float32): bool =
  let a = feature.lengthrange.s.a
  let b = feature.lengthrange.s.b
  return (feature.lengthrange.aeq and a == n or a < n) and
    (feature.lengthrange.beq and b == n or n < b)

func applies(ctx: MediaApplyContext; feature: MediaFeature): bool =
  case feature.t
  of mftColor:
    let bitDepth = if ctx.colorMode != cmMonochrome: 8 else: 0
    return bitDepth in feature.range
  of mftColorIndex:
    let mapSize = case ctx.colorMode
    of cmANSI: 16
    of cmEightBit: 256
    of cmMonochrome, cmTrueColor: 0
    return mapSize in feature.range
  of mftMonochrome:
    let bitDepth = if ctx.colorMode == cmMonochrome: 1 else: 0
    return bitDepth in feature.range
  of mftGrid:
    return feature.b
  of mftHover:
    return feature.b
  of mftPrefersColorScheme:
    return feature.b == ctx.attrsp.prefersDark
  of mftWidth:
    return feature.appliesLR(float32(ctx.attrsp.widthPx))
  of mftHeight:
    return feature.appliesLR(float32(ctx.attrsp.heightPx))
  of mftScripting:
    case feature.ms
    of msNone: return ctx.scripting == smFalse
    of msInitialOnly: return ctx.scripting != smFalse and ctx.headless == hmDump
    of msEnabled: return ctx.scripting != smFalse and ctx.headless != hmDump
  of mftContentType:
    return ctx.contentType.equalsIgnoreCase(feature.a)

func applies(ctx: MediaApplyContext; mq: MediaQuery): bool =
  case mq.t
  of mctMedia: return mq.media in {mtAll, mtScreen, mtTty}
  of mctNot: return not ctx.applies(mq.n)
  of mctAnd: return ctx.applies(mq.left) and ctx.applies(mq.right)
  of mctOr: return ctx.applies(mq.left) or ctx.applies(mq.right)
  of mctFeature: return ctx.applies(mq.feature)

func applies(ctx: MediaApplyContext; mqlist: seq[MediaQuery]): bool =
  for mq in mqlist:
    if ctx.applies(mq):
      return true
  return false

func applies*(mqlist: seq[MediaQuery]; ctx: MediaApplyContext): bool =
  return ctx.applies(mqlist)

{.pop.} # raises: []
