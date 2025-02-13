import std/algorithm
import std/options
import std/sets
import std/tables

import chame/tags
import css/cssparser
import css/cssvalues
import css/lunit
import css/match
import css/selectorparser
import css/sheet
import html/catom
import html/dom
import html/enums
import html/script
import types/color
import types/jscolor
import types/opt

type
  RuleListEntry = object
    normal: seq[CSSComputedEntry]
    important: seq[CSSComputedEntry]
    normalVars: seq[CSSVariable]
    importantVars: seq[CSSVariable]

  RuleList = array[CSSOrigin, RuleListEntry]

  RuleListMap = array[PseudoElement, RuleList]

  RulePair = tuple
    specificity: int
    rule: CSSRuleDef

  ToSorts = array[PseudoElement, seq[RulePair]]

  InitType = enum
    itUserAgent, itUser, itOther

  InitMap = array[CSSPropertyType, set[InitType]]

  ApplyValueContext = object
    vals: CSSValues
    vars: CSSVariableMap
    parentComputed: CSSValues
    previousOrigin: CSSValues
    window: Window
    initMap: InitMap
    varsSeen: HashSet[CAtom]

# Forward declarations
proc applyValue0(ctx: var ApplyValueContext; entry: CSSComputedEntry;
  initType: InitType; nextInitType: set[InitType])
proc applyStyle*(element: Element)

proc calcRule(tosorts: var ToSorts; element: Element;
    depends: var DependencyInfo; rule: CSSRuleDef) =
  for sel in rule.sels:
    if element.matches(sel, depends):
      if tosorts[sel.pseudo].len > 0 and tosorts[sel.pseudo][^1].rule == rule:
        tosorts[sel.pseudo][^1].specificity =
          max(tosorts[sel.pseudo][^1].specificity, sel.specificity)
      else:
        tosorts[sel.pseudo].add((sel.specificity, rule))

proc add(entry: var RuleListEntry; rule: CSSRuleDef) =
  entry.normal.add(rule.normalVals)
  entry.important.add(rule.importantVals)
  entry.normalVars.add(rule.normalVars)
  entry.importantVars.add(rule.importantVars)

proc calcRules(map: var RuleListMap; element: Element;
    sheet: CSSStylesheet; origin: CSSOrigin; depends: var DependencyInfo) =
  var rules: seq[CSSRuleDef] = @[]
  sheet.tagTable.withValue(element.localName, v):
    rules.add(v[])
  if element.id != CAtomNull:
    sheet.idTable.withValue(element.id.toLowerAscii(), v):
      rules.add(v[])
  for class in element.classList:
    sheet.classTable.withValue(class.toLowerAscii(), v):
      rules.add(v[])
  for attr in element.attrs:
    sheet.attrTable.withValue(attr.qualifiedName, v):
      rules.add(v[])
  for rule in sheet.generalList:
    rules.add(rule)
  var tosorts = ToSorts.default
  for rule in rules:
    tosorts.calcRule(element, depends, rule)
  for pseudo, it in tosorts.mpairs:
    it.sort(proc(x, y: RulePair): int =
      let n = cmp(x.specificity, y.specificity)
      if n != 0:
        return n
      return cmp(x.rule.idx, y.rule.idx), order = Ascending)
    for item in it:
      map[pseudo][origin].add(item.rule)

proc findVariable(ctx: var ApplyValueContext; varName: CAtom): CSSVariable =
  while ctx.vars != nil:
    let cvar = ctx.vars.table.getOrDefault(varName)
    if cvar != nil:
      return cvar
    ctx.vars = ctx.vars.parent
  return nil

proc applyVariable(ctx: var ApplyValueContext; t: CSSPropertyType;
    varName: CAtom; fallback: ref CSSComputedEntry; initType: InitType;
    nextInitType: set[InitType]) =
  let v = t.valueType
  let cvar = ctx.findVariable(varName)
  if cvar == nil:
    if fallback != nil:
      ctx.applyValue0(fallback[], initType, nextInitType)
    return
  for (iv, entry) in cvar.resolved.mitems:
    if iv == v:
      entry.t = t # must override, same var can be used for different props
      ctx.applyValue0(entry, initType, nextInitType)
      return
  var entries: seq[CSSComputedEntry] = @[]
  if entries.parseComputedValues($t, cvar.cvals, ctx.window.attrsp[]).isSome:
    if entries[0].et == ceVar:
      if ctx.varsSeen.containsOrIncl(varName) or ctx.varsSeen.len > 20:
        ctx.varsSeen.clear()
        return
    else:
      ctx.varsSeen.clear()
      cvar.resolved.add((v, entries[0]))
    ctx.applyValue0(entries[0], initType, nextInitType)

proc applyGlobal(ctx: ApplyValueContext; t: CSSPropertyType;
    global: CSSGlobalType; initType: InitType) =
  case global
  of cgtInherit:
    ctx.vals.initialOrCopyFrom(ctx.parentComputed, t)
  of cgtInitial:
    ctx.vals.setInitial(t)
  of cgtUnset:
    ctx.vals.initialOrInheritFrom(ctx.parentComputed, t)
  of cgtRevert:
    if ctx.previousOrigin != nil and initType in ctx.initMap[t]:
      ctx.vals.copyFrom(ctx.previousOrigin, t)
    else:
      ctx.vals.initialOrInheritFrom(ctx.parentComputed, t)

proc applyValue0(ctx: var ApplyValueContext; entry: CSSComputedEntry;
    initType: InitType; nextInitType: set[InitType]) =
  case entry.et
  of ceBit: ctx.vals.bits[entry.t].dummy = entry.bit
  of ceWord: ctx.vals.words[entry.t] = entry.word
  of ceObject: ctx.vals.objs[entry.t] = entry.obj
  of ceGlobal:
    ctx.applyGlobal(entry.t, entry.global, initType)
  of ceVar:
    ctx.applyVariable(entry.t, entry.cvar, entry.fallback, initType,
      nextInitType)
    return # maybe it applies, maybe it doesn't...
  ctx.initMap[entry.t] = ctx.initMap[entry.t] + nextInitType

proc applyValue(ctx: var ApplyValueContext; entry: CSSComputedEntry;
    initType: InitType; nextInitType: set[InitType]) =
  ctx.vars = ctx.vals.vars
  ctx.applyValue0(entry, initType, nextInitType)

proc applyPresHints(ctx: var ApplyValueContext; element: Element) =
  template set_cv(t, x, b: untyped) =
    ctx.applyValue(makeEntry(t, CSSValueWord(x: b)), itUserAgent, {itUser})
  template set_cv_new(t, x, b: untyped) =
    const v = valueType(t)
    let val = CSSValue(v: v, x: b)
    ctx.applyValue(makeEntry(t, val), itUserAgent, {itUser})
  template map_width =
    let s = parseDimensionValues(element.attr(satWidth))
    if s.isSome:
      set_cv cptWidth, length, s.get
  template map_height =
    let s = parseDimensionValues(element.attr(satHeight))
    if s.isSome:
      set_cv cptHeight, length, s.get
  template map_width_nozero =
    let s = parseDimensionValues(element.attr(satWidth))
    if s.isSome and s.get.num != 0:
      set_cv cptWidth, length, s.get
  template map_height_nozero =
    let s = parseDimensionValues(element.attr(satHeight))
    if s.isSome and s.get.num != 0:
      set_cv cptHeight, length, s.get
  template map_bgcolor =
    let s = element.attr(satBgcolor)
    if s != "":
      let c = parseLegacyColor(s)
      if c.isSome:
        set_cv cptBackgroundColor, color, c.get.cssColor()
  template map_size =
    let s = element.attrul(satSize)
    if s.isSome:
      set_cv cptWidth, length, resolveLength(cuCh, float32(s.get),
        ctx.window.attrsp[])
  template map_text =
    let s = element.attr(satText)
    if s != "":
      let c = parseLegacyColor(s)
      if c.isSome:
        set_cv cptColor, color, c.get.cssColor()
  template map_color =
    let s = element.attr(satColor)
    if s != "":
      let c = parseLegacyColor(s)
      if c.isSome:
        set_cv cptColor, color, c.get.cssColor()
  template map_colspan =
    let colspan = element.attrulgz(satColspan)
    if colspan.isSome:
      let i = colspan.get
      if i <= 1000:
        set_cv cptChaColspan, integer, int32(i)
  template map_rowspan =
    let rowspan = element.attrul(satRowspan)
    if rowspan.isSome:
      let i = rowspan.get
      if i <= 65534:
        set_cv cptChaRowspan, integer, int32(i)
  template set_bgcolor_is_canvas =
    let t = cptBgcolorIsCanvas
    let val = CSSValueBit(bgcolorIsCanvas: true)
    ctx.applyValue(makeEntry(t, val), itUserAgent, {itUser})
  template map_cellspacing =
    let s = element.attrul(satCellspacing)
    if s.isSome:
      let n = float32(s.get)
      set_cv_new cptBorderSpacing, length2, CSSLength2(a: cssLength(n))

  case element.tagType
  of TAG_TABLE:
    map_height_nozero
    map_width_nozero
    map_bgcolor
    map_cellspacing
  of TAG_TD, TAG_TH:
    map_height_nozero
    map_width_nozero
    map_bgcolor
    map_colspan
    map_rowspan
  of TAG_THEAD, TAG_TBODY, TAG_TFOOT, TAG_TR:
    map_height
    map_bgcolor
  of TAG_COL:
    map_width
  of TAG_IMG:
    map_width
    map_height
  of TAG_CANVAS:
    map_width
    map_height
  of TAG_HTML:
    set_bgcolor_is_canvas
  of TAG_BODY:
    set_bgcolor_is_canvas
    map_bgcolor
    map_text
  of TAG_TEXTAREA:
    let textarea = HTMLTextAreaElement(element)
    let cols = textarea.attrul(satCols).get(20)
    let rows = textarea.attrul(satRows).get(1)
    set_cv cptWidth, length, resolveLength(cuCh, float32(cols),
      ctx.window.attrsp[])
    set_cv cptHeight, length, resolveLength(cuEm, float32(rows),
      ctx.window.attrsp[])
  of TAG_FONT:
    map_color
  of TAG_INPUT:
    let input = HTMLInputElement(element)
    if input.inputType in InputTypeWithSize:
      map_size
  of TAG_SELECT:
    let select = HTMLSelectElement(element)
    if select.attrb(satMultiple):
      let size = element.attrulgz(satSize).get(4)
      set_cv cptHeight, length, resolveLength(cuEm, float32(size),
        ctx.window.attrsp[])
  else: discard

proc applyDeclarations(rules: RuleList; parent, element: Element;
    window: Window): CSSValues =
  result = CSSValues()
  var parentVars: CSSVariableMap = nil
  var ctx = ApplyValueContext(window: window, vals: result)
  if parent != nil:
    if parent.computed == nil:
      parent.applyStyle()
    ctx.parentComputed = parent.computed
    parentVars = ctx.parentComputed.vars
  for origin in CSSOrigin:
    if rules[origin].importantVars.len > 0:
      if result.vars == nil:
        result.vars = newCSSVariableMap(parentVars)
      for i in countdown(rules[origin].importantVars.high, 0):
        let cvar = rules[origin].importantVars[i]
        result.vars.putIfAbsent(cvar.name, cvar)
  for origin in countdown(CSSOrigin.high, CSSOrigin.low):
    if rules[origin].normalVars.len > 0:
      if result.vars == nil:
        result.vars = newCSSVariableMap(parentVars)
      for i in countdown(rules[origin].normalVars.high, 0):
        let cvar = rules[origin].normalVars[i]
        result.vars.putIfAbsent(cvar.name, cvar)
  if result.vars == nil:
    result.vars = parentVars # inherit parent
  for entry in rules[coUserAgent].normal: # user agent
    ctx.applyValue(entry, itOther, {itUserAgent, itUser})
  let uaProperties = result.copyProperties()
  # Presentational hints override user agent style, but respect user/author
  # style.
  if element != nil:
    ctx.applyPresHints(element)
  ctx.previousOrigin = uaProperties
  for entry in rules[coUser].normal:
    ctx.applyValue(entry, itUserAgent, {itUser})
  # save user properties so author can use them
  ctx.previousOrigin = result.copyProperties() # use user for author revert
  for entry in rules[coAuthor].normal:
    ctx.applyValue(entry, itUser, {itOther})
  for entry in rules[coAuthor].important:
    ctx.applyValue(entry, itUser, {itOther})
  ctx.previousOrigin = uaProperties # use UA for user important revert
  for entry in rules[coUser].important:
    ctx.applyValue(entry, itUserAgent, {itOther})
  ctx.previousOrigin = nil # reset origin for UA
  for entry in rules[coUserAgent].important:
    ctx.applyValue(entry, itUserAgent, {itOther})
  # fill in defaults
  for t in CSSPropertyType:
    if ctx.initMap[t] == {}:
      result.initialOrInheritFrom(ctx.parentComputed, t)
  # Quirk: it seems others aren't implementing what the spec says about
  # blockification.
  # Well, neither will I, because the spec breaks on actual websites.
  # Curse CSS.
  if result{"position"} in PositionAbsoluteFixed:
    if result{"display"} == DisplayInline:
      result{"display"} = DisplayInlineBlock
  elif result{"float"} != FloatNone or
      ctx.parentComputed != nil and
        ctx.parentComputed{"display"} == DisplayFlex:
    result{"display"} = result{"display"}.blockify()
  if (result{"overflow-x"} in {OverflowVisible, OverflowClip}) !=
      (result{"overflow-y"} in {OverflowVisible, OverflowClip}):
    result{"overflow-x"} = result{"overflow-x"}.bfcify()
    result{"overflow-y"} = result{"overflow-y"}.bfcify()

func hasValues(rules: RuleList): bool =
  for x in rules:
    if x.normal.len > 0 or x.important.len > 0:
      return true
  return false

proc applyStyle*(element: Element) =
  let document = element.document
  let window = document.window
  var depends = DependencyInfo.default
  var map = RuleListMap.default
  for sheet in document.uaSheets:
    map.calcRules(element, sheet, coUserAgent, depends)
  map.calcRules(element, document.userSheet, coUser, depends)
  for sheet in document.authorSheets:
    map.calcRules(element, sheet, coAuthor, depends)
  let style = element.cachedStyle
  if window.styling and style != nil:
    for decl in style.decls:
      #TODO variables
      let vals = parseComputedValues(decl.name, decl.value, window.attrsp[])
      if decl.important:
        map[peNone][coAuthor].important.add(vals)
      else:
        map[peNone][coAuthor].normal.add(vals)
  element.applyStyleDependencies(depends)
  element.computedMap[peNone] =
    map[peNone].applyDeclarations(element.parentElement, element, window)
  for pseudo in peBefore..peAfter:
    if map[pseudo].hasValues() or window.settings.scripting == smApp:
      let computed = map[pseudo].applyDeclarations(element, nil, window)
      element.computedMap[pseudo] = computed
