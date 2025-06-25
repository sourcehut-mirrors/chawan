import std/strutils

import monoucha/fromjs
import monoucha/javascript
import monoucha/jserror
import monoucha/jstypes
import monoucha/quickjs
import monoucha/tojs
import types/opt
import utils/twtstr

type
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
    part2: Option[NumberUnitPart]

  NumberFormat = ref object
    maximumFractionDigits: int32
    style: NumberStyle
    unit: NumberUnit

  PluralRules = ref object

  PRResolvedOptions = object of JSDict
    locale: string

jsDestructor(NumberFormat)
jsDestructor(PluralRules)

proc fromJS(ctx: JSContext; val: JSValueConst; unit: var NumberUnit):
    Opt[void] =
  var s: string
  ?ctx.fromJS(val, s)
  let i = s.find("-per-")
  if i != -1:
    let part1 = strictParseEnum[NumberUnitPart](s.substr(0, i - 1))
    let part2 = strictParseEnum[NumberUnitPart](s.substr(i + "-per-".len))
    if part1.isErr or part2.isErr:
      JS_ThrowRangeError(ctx, "wrong unit %s", cstring(s))
      return err()
    unit = NumberUnit(part1: part1.get, part2: some(part2.get))
  else:
    let part1 = parseEnumNoCase[NumberUnitPart](s)
    if part1.isErr:
      JS_ThrowRangeError(ctx, "wrong unit %s", cstring(s))
      return err()
    unit = NumberUnit(part1: part1.get)
  ok()

proc fromJSGetProp[T](ctx: JSContext; this: JSValueConst; name: cstring;
    res: var T): Opt[bool] =
  let prop = JS_GetPropertyStr(ctx, this, name)
  if JS_IsException(prop):
    return err()
  if JS_IsUndefined(prop):
    return ok(false)
  ?ctx.fromJS(prop, res)
  JS_FreeValue(ctx, prop)
  ok(true)

proc newNumberFormat(ctx: JSContext; name = "en-US";
    options: JSValueConst = JS_UNDEFINED): JSResult[NumberFormat] {.jsctor.} =
  let nf = NumberFormat()
  if JS_IsObject(options):
    discard ?ctx.fromJSGetProp(options, "maximumFractionDigits",
      nf.maximumFractionDigits)
    if nf.maximumFractionDigits notin 0..100:
      return errRangeError("invalid digits value: " &
        $nf.maximumFractionDigits)
    discard ?ctx.fromJSGetProp(options, "style", nf.style)
    if not ?ctx.fromJSGetProp(options, "unit", nf.unit) and nf.style == nsUnit:
      return errTypeError("undefined unit in NumberFormat() with unit style")
  return ok(nf)

proc newPluralRules(): PluralRules {.jsctor.} =
  return PluralRules()

proc resolvedOptions(this: PluralRules): PRResolvedOptions {.jsfunc.} =
  return PRResolvedOptions(locale: "en-US")

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

proc stringify(part: NumberUnitPart; s: string; part2 = false): string =
  let s = UnitTable[part]
  if s == nil:
    result = $part
  else:
    result = $s
  if part in {nupDay, nupMonth, nupWeek, nupYear} and s != "1":
    result &= 's' # plural
  if part2 and part in {nupSecond, nupDay, nupMonth, nupYear}:
    result.setLen(1)

proc stringifyUnit(unit: NumberUnit; s: string): string =
  result = ""
  if unit.part1 notin {nupCelsius, nupFahrenheit, nupPercent}:
    result &= ' '
  result &= unit.part1.stringify(s)
  if unit.part1 != nupPercent and unit.part2.isSome:
    result &= '/'
    result &= unit.part2.get.stringify(s, part2 = true)

proc format(nf: NumberFormat; s: string): string {.jsfunc.} =
  result = ""
  var i = 0
  var L = s.rfind('.')
  if L == -1:
    L = s.len
  if L mod 3 != 0:
    while i < L mod 3:
      result &= s[i]
      inc i
    if i < L:
      result &= ','
  let j = i
  while i < L:
    if j != i and i mod 3 == j:
      result &= ','
    result &= s[i]
    inc i
  if i + 1 < s.len and s[i] == '.' and (s[i + 1] != '0' or s.len != i + 2):
    if nf.maximumFractionDigits > 0:
      result &= '.'
      inc i
      var k = 0
      while i < s.len and k < nf.maximumFractionDigits:
        result &= s[i]
        inc k
        inc i
  case nf.style
  of nsDecimal: discard
  of nsUnit: result &= nf.unit.stringifyUnit(s)
  of nsPercent: result &= '%'
  of nsCurrency: discard #TODO?

proc select(this: PluralRules; num: float64): string {.jsfunc.} =
  if num == 1:
    return "one"
  return "many"

proc addIntlModule*(ctx: JSContext) =
  let global = JS_GetGlobalObject(ctx)
  let intl = JS_NewObject(ctx)
  ctx.registerType(NumberFormat, namespace = intl)
  ctx.registerType(PluralRules, namespace = intl)
  doAssert ctx.defineProperty(global, "Intl", intl) != dprException
  JS_FreeValue(ctx, global)
