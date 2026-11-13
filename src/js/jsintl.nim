{.push raises: [].}

import js/fromjs
import js/jsbind
import js/jsopaque
import js/jsref
import js/jstypes
import js/jsutils
import js/quickjs
import js/tojs
import utils/cowstr
import utils/opt
import utils/twtstr

type
  CollatorObj = object

  Collator = JSRef[CollatorObj]

  NumberStyle = enum
    nsDecimal = "decimal"
    nsPercent = "percent"
    nsCurrency = "currency"
    nsUnit = "unit"

  NumberUnitPart = enum
    nupAcre = "acre"
    nupBit = "bit"
    nupByte = "byte"
    nupCelsius = "celsius"
    nupCentimeter = "centimeter"
    nupDay = "day"
    nupDegree = "degree"
    nupFahrenheit = "fahrenheit"
    nupFluidOunce = "fluid-ounce"
    nupFoot = "foot"
    nupGallon = "gallon"
    nupGigabit = "gigabit"
    nupGigabyte = "gigabyte"
    nupGram = "gram"
    nupHectare = "hectare"
    nupHour = "hour"
    nupInch = "inch"
    nupKilobit = "kilobit"
    nupKilobyte = "kilobyte"
    nupKilogram = "kilogram"
    nupKilometer = "kilometer"
    nupLiter = "liter"
    nupMegabit = "megabit"
    nupMegabyte = "megabyte"
    nupMeter = "meter"
    nupMicrosecond = "microsecond"
    nupMile = "mile"
    nupMileScandinavian = "mile-scandinavian"
    nupMilliliter = "milliliter"
    nupMillimeter = "millimeter"
    nupMillisecond = "millisecond"
    nupMinute = "minute"
    nupMonth = "month"
    nupNanosecond = "nanosecond"
    nupOunce = "ounce"
    nupPercent = "percent"
    nupPetabyte = "petabyte"
    nupPound = "pound"
    nupSecond = "second"
    nupStone = "stone"
    nupTerabit = "terabit"
    nupTerabyte = "terabyte"
    nupWeek = "week"
    nupYard = "yard"
    nupYear = "year"

  NumberUnit = object
    part1: NumberUnitPart
    part2: Opt[NumberUnitPart]

  NumberFormatObj = object
    maximumFractionDigits: int32
    style: NumberStyle
    unit: NumberUnit

  NumberFormat = JSRef[NumberFormatObj]

  PluralRulesObj = object
    minimumFractionDigits: uint8

  PluralRules = JSRef[PluralRulesObj]

  DateTimeFormatObj = object

  DateTimeFormat = JSRef[DateTimeFormatObj]

  RelativeTimeFormatObj = object

  RelativeTimeFormat = JSRef[RelativeTimeFormatObj]

  ListFormatObj = object

  ListFormat = JSRef[ListFormatObj]

# Intl
proc canonicalizeLocales(ctx: JSContext; val: JSValueConst; filter: bool):
    JSValue =
  if JS_IsUndefined(val):
    return JS_NewArray(ctx)
  #TODO InitializedLocale, actually validate locales, dedup
  let lengthVal = ?ctx.getProperty(val, jstLength)
  let len = ctx.toIntIndex(lengthVal.toJSValue())
  if len < 0:
    return JS_EXCEPTION
  var tags: seq[Str]
  for k in 0 ..< len:
    let prop = ?JS_NewAtomUInt32(ctx, uint32(k))
    let has = JS_HasProperty(ctx, val, prop)
    if has < 0:
      return JS_EXCEPTION
    if has > 0:
      let locale = ?trace(JS_GetPropertyUint32(ctx, val, uint32(k)))
      if not JS_IsString(locale) and not JS_IsObject(locale):
        return JS_ThrowTypeError(ctx, "unexpected locale type")
      #TODO InitializedLocale
      var tag: Str
      ?ctx.fromJSFree(locale.toJSValue(), tag)
      #TODO validate
      if tag notin tags and
          (not filter or tag == "en" or tag.startsWith("en")):
        tags.add(tag)
  ctx.toJS(tags)

jsNamespaceDef(Intl):
  proc getCanonicalLocales(ctx: JSContext; val: JSValueConst): JSValue {.
      jsstfunc.} =
    ctx.canonicalizeLocales(val, filter = false)

# Collator
jsClassDef(Collator):
  proc newCollator(): Collator {.jsctor.} =
    jsNew CollatorObj()

  proc compare(this: Collator; a, b: DOMString): int {.jsfunc.} =
    clamp(cmp(a.asStr, b.asStr), -1, 1)

# NumberFormat
proc fromJS(ctx: JSContext; val: JSValueConst; unit: var NumberUnit):
    JSCode =
  var s: Str
  ?ctx.fromJS(val, s)
  let i = s.find("-per-")
  if i >= 0:
    let part1 = strictParseEnum[NumberUnitPart](s.toOpenArray(0, i - 1))
    let part2 = strictParseEnum[NumberUnitPart](
      s.toOpenArray(i + "-per-".len, s.high))
    if part1.isErr or part2.isErr:
      JS_ThrowRangeError(ctx, "wrong unit %s", s.toCString())
      return fjErr
    unit = NumberUnit(part1: part1.get, part2: part2)
  else:
    let part1 = parseEnumNoCase[NumberUnitPart](s)
    if part1.isErr:
      JS_ThrowRangeError(ctx, "wrong unit %s", s.toCString())
      return fjErr
    unit = NumberUnit(part1: part1.get)
  fjOk

const UnitTable = [
  nupAcre: cstring"ac",
  nupBit: nil,
  nupByte: nil,
  nupCelsius: cstring"°C",
  nupCentimeter: cstring"cm",
  nupDay: nil,
  nupDegree: cstring"deg",
  nupFahrenheit: cstring"°F",
  nupFluidOunce: cstring"fl oz",
  nupFoot: cstring"ft",
  nupGallon: cstring"gal",
  nupGigabit: cstring"Gb",
  nupGigabyte: cstring"GB",
  nupGram: cstring"g",
  nupHectare: cstring"ha",
  nupHour: cstring"hr",
  nupInch: cstring"in",
  nupKilobit: cstring"kb",
  nupKilobyte: cstring"kB",
  nupKilogram: cstring"kg",
  nupKilometer: cstring"km",
  nupLiter: cstring"L",
  nupMegabit: cstring"Mb",
  nupMegabyte: cstring"MB",
  nupMeter: cstring"m",
  nupMicrosecond: cstring"μs",
  nupMile: cstring"mi",
  nupMileScandinavian: cstring"smi",
  nupMilliliter: cstring"mL",
  nupMillimeter: cstring"mm",
  nupMillisecond: cstring"ms",
  nupMinute: cstring"min",
  nupMonth: cstring"mth",
  nupNanosecond: cstring"ns",
  nupOunce: cstring"oz",
  nupPercent: cstring"%",
  nupPetabyte: cstring"PB",
  nupPound: cstring"lb",
  nupSecond: cstring"sec",
  nupStone: cstring"st",
  nupTerabit: cstring"Tb",
  nupTerabyte: cstring"TB",
  nupWeek: cstring"wk",
  nupYard: cstring"yd",
  nupYear: cstring"yr"
]

proc addUnitPart(buf: var Growbuf; part: NumberUnitPart; s: Str;
    part2 = false) =
  let unit = UnitTable[part]
  var res = if unit == nil:
    part.toStr()
  else:
    unit.toStr()
  if part in {nupDay, nupMonth, nupWeek, nupYear} and s != "1":
    res &= "s" # plural
  if part2 and part in {nupSecond, nupDay, nupMonth, nupYear}:
    res.setLen(1)
  buf &= res

proc addUnit(buf: var Growbuf; unit: NumberUnit; s: Str) =
  if unit.part1 notin {nupCelsius, nupFahrenheit, nupPercent}:
    buf &= ' '
  buf.addUnitPart(unit.part1, s)
  if unit.part1 != nupPercent and unit.part2.isOk:
    buf &= '/'
    buf.addUnitPart(unit.part2.get, s, part2 = true)

jsClassDef(NumberFormat):
  proc newNumberFormat(ctx: JSContext; name = str("en-US");
      options = JS_UNDEFINED.vc): Opt[NumberFormat] {.jsfctor.} =
    let nf = jsNew NumberFormatObj()
    if nf != nil and JS_IsObject(options):
      discard ?ctx.fromJSGetProp(options, "maximumFractionDigits",
        nf.maximumFractionDigits)
      if nf.maximumFractionDigits notin 0..100:
        JS_ThrowRangeError(ctx, "invalid digits value: %d",
          cint(nf.maximumFractionDigits))
        return err()
      discard ?ctx.fromJSGetProp(options, "style", nf.style)
      if not ?ctx.fromJSGetProp(options, "unit", nf.unit) and
          nf.style == nsUnit:
        JS_ThrowTypeError(ctx,
          "undefined unit in NumberFormat() with unit style")
        return err()
    ok(nf)

  proc format(nf: NumberFormat; s: Str): Str {.jsfunc.} =
    var buf = initGrowbuf()
    var i = 0
    var L = s.rfind('.')
    if L == -1:
      L = s.len
    if L mod 3 != 0:
      while i < L mod 3:
        buf &= s[i]
        inc i
      if i < L:
        buf &= ','
    let j = i
    while i < L:
      if j != i and i mod 3 == j:
        buf &= ','
      buf &= s[i]
      inc i
    if i + 1 < s.len and s[i] == '.' and (s[i + 1] != '0' or s.len != i + 2):
      if nf.maximumFractionDigits > 0:
        buf &= '.'
        inc i
        var k = 0
        while i < s.len and k < nf.maximumFractionDigits:
          buf &= s[i]
          inc k
          inc i
    case nf.style
    of nsDecimal: discard
    of nsUnit: buf.addUnit(nf.unit, s)
    of nsPercent: buf &= '%'
    of nsCurrency: discard #TODO?
    buf.toStr()

  proc supportedLocalesOfNF(ctx: JSContext; locales = JS_UNDEFINED.vc;
      options = JS_UNDEFINED.vc): JSValue {.jsstfunc: "supportedLocalesOf".} =
    return ctx.canonicalizeLocales(locales, filter = true)

# DateTimeFormat
jsClassDef(DateTimeFormat):
  proc newDateTimeFormat(): DateTimeFormat {.jsfctor.} =
    jsNew DateTimeFormatObj()

  proc format(this: DateTimeFormat; s: DOMString): DOMString {.jsfunc.} =
    s #TODO

# PluralRules
jsClassDef(PluralRules):
  proc newPluralRules(ctx: JSContext; ctor: JSValueConst;
      label = str(""); options = JS_UNDEFINED.vc): JSValue {.jsctor2.} =
    #TODO
    let obj = jsNew PluralRulesObj()
    if obj != nil:
      var minimumFractionDigits: float64
      discard ?ctx.fromJSGetProp(options, "minimumFractionDigits",
        minimumFractionDigits)
      if minimumFractionDigits < 0 or not (minimumFractionDigits <= 100):
        return JS_ThrowRangeError(ctx, "invalid digits value")
      obj.minimumFractionDigits = uint8(minimumFractionDigits)
    ctx.toJSNew(obj, ctor)

  proc resolvedOptions(ctx: JSContext; this: PluralRules): JSValue {.jsfunc.} =
    let obj = ?ctx.newObject()
    ?ctx.definePropertyConvert(obj, jstLocale, "en-US")
    obj.toJSValue()

  proc select(this: PluralRules; num: float64): Str {.jsfunc.} =
    if this.minimumFractionDigits == 0 and num == 1:
      return str("one")
    return str("other")

  proc supportedLocalesOfPR(ctx: JSContext; locales = JS_UNDEFINED.vc;
      options = JS_UNDEFINED.vc): JSValue {.jsstfunc: "supportedLocalesOf".} =
    return ctx.canonicalizeLocales(locales, filter = true)

# RelativeTimeFormat
jsClassDef(RelativeTimeFormat):
  proc newRelativeTimeFormat(): RelativeTimeFormat {.jsctor.} =
    jsNew RelativeTimeFormatObj()

  proc format(this: RelativeTimeFormat; s: DOMString): DOMString {.jsfunc.} =
    s #TODO

# ListFormat
jsClassDef(ListFormat):
  proc newListFormat(): ListFormat {.jsctor.} =
    #TODO locales, options etc.
    jsNew ListFormatObj()

  proc format(this: ListFormat; s: DOMString): DOMString {.jsfunc.} =
    s #TODO

proc addIntlModule*(ctx: JSContext): JSCode =
  let intl = ?ctx.registerNamespace(IntlDef)
  ?ctx.registerClass(CollatorDef, intl)
  ?ctx.registerClass(NumberFormatDef, intl)
  ?ctx.registerClass(DateTimeFormatDef, intl)
  ?ctx.registerClass(PluralRulesDef, intl)
  ?ctx.registerClass(RelativeTimeFormatDef, intl)
  ctx.registerClass(ListFormatDef, intl)

{.pop.}
