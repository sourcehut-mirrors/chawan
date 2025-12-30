{.push raises: [].}

import std/algorithm
import std/sets
import std/tables

import chame/tags
import config/conftypes
import css/cssparser
import css/cssvalues
import css/match
import css/sheet
import html/catom
import html/dom
import html/script
import types/color
import types/jscolor
import types/opt
import utils/twtstr

type
  RuleListEntry = object
    vals: array[CSSImportantFlag, seq[CSSComputedEntry]]
    vars: array[CSSImportantFlag, seq[CSSVariable]]

  LayeredRuleList = object
    unlayered: RuleListEntry
    layers: seq[RuleListEntry]

  RuleList = object
    a: array[CSSOrigin, LayeredRuleList]
    hasValues: bool

  RuleListMap = array[PseudoElement, RuleList]

  RulePair = tuple
    specificity: uint
    rule: CSSRuleDef

  ToSorts = array[PseudoElement, seq[RulePair]]

  RevertType = enum
    rtUnset, rtUser, rtUserAgent, rtSet

  RevertMap = array[CSSPropertyType, RevertType]

  ApplyValueContext = object
    vals: CSSValues
    parentComputed: CSSValues
    window: Window
    old: CSSValues
    revertMap: RevertMap
    varsSeen: HashSet[CAtom]

# Forward declarations
proc ensureStyle*(element: Element)
proc applyValues(ctx: var ApplyValueContext;
  entries: openArray[CSSComputedEntry]; revertType: RevertType)

proc calcRules(tosorts: var ToSorts; element: Element;
    depends: var DependencyInfo; rules: openArray[CSSRuleDef]) =
  for rule in rules:
    var seen: set[PseudoElement] = {}
    for sel in rule.sels:
      if sel.pseudo in seen:
        continue
      if element.matches(sel, depends):
        tosorts[sel.pseudo].add((sel.specificity, rule))
        seen.incl(sel.pseudo)

proc add(entry: var RuleListEntry; rule: CSSRuleDef) =
  for f in CSSImportantFlag: # normal, important
    entry.vals[f].add(rule.vals[f])
    entry.vars[f].add(rule.vars[f])

proc calcRules(map: var RuleListMap; element: Element; sheet: CSSRuleMap;
    depends: var DependencyInfo) =
  var tosorts = ToSorts.default
  sheet.tagTable.withValue(element.localName, v):
    tosorts.calcRules(element, depends, v[])
  if element.id != CAtomNull:
    sheet.idTable.withValue(element.id.toLowerAscii(), v):
      tosorts.calcRules(element, depends, v[])
  for class in element.classList:
    sheet.classTable.withValue(class.toLowerAscii(), v):
      tosorts.calcRules(element, depends, v[])
  for attr in element.attrs:
    sheet.attrTable.withValue(attr.qualifiedName, v):
      tosorts.calcRules(element, depends, v[])
  if element.parentElement == nil:
    tosorts.calcRules(element, depends, sheet.rootList)
  if element.hint:
    tosorts.calcRules(element, depends, sheet.hintList)
  tosorts.calcRules(element, depends, sheet.generalList)
  for pseudo, it in tosorts.mpairs:
    it.sort(proc(x, y: RulePair): int =
      let n = cmp(x.specificity, y.specificity)
      if n != 0:
        return n
      return cmp(x.rule.idx, y.rule.idx), order = Ascending)
    for item in it:
      let rule = item.rule
      let origin = rule.origin
      let layerId = rule.layerId
      if rule.vals[cifNormal].len > 0 or rule.vals[cifImportant].len > 0:
        map[pseudo].hasValues = true
      if layerId == 0:
        map[pseudo].a[origin].unlayered.add(rule)
      else:
        let n = int(layerId)
        if n > map[pseudo].a[origin].layers.len:
          map[pseudo].a[origin].layers.setLen(n)
        map[pseudo].a[origin].layers[n - 1].add(rule)

proc addItems(ctx: var ApplyValueContext; toks: var seq[CSSToken];
    vars: CSSVariableMap; items: openArray[CSSVarItem]): Opt[void] =
  for item in items:
    let varName = item.name
    if varName != CAtomNull:
      if ctx.varsSeen.containsOrIncl(varName) or ctx.varsSeen.len > 20:
        ctx.varsSeen.clear()
        return err()
      var cv {.cursor.}: CSSVariable = nil
      var vars {.cursor.} = vars
      while vars != nil:
        cv = vars.table.getOrDefault(varName)
        if cv != nil:
          break
        vars = vars.parent
      if cv != nil:
        ?ctx.addItems(toks, vars, cv.items)
        continue
    if item.toks.len == 0:
      return err()
    toks.add(item.toks)
  ok()

proc resolveVariable(ctx: var ApplyValueContext; p: CSSWidePropertyType;
    cvar: CSSVarEntry; revertType: RevertType): Opt[void] =
  let vars = ctx.vals.vars
  for it in cvar.resolved:
    if it.vars == vars:
      ctx.applyValues(it.entries, revertType)
      return ok()
  var toks: seq[CSSToken] = @[]
  ?ctx.addItems(toks, vars, cvar.items)
  # fully resolved
  ctx.varsSeen.clear()
  var entries: seq[CSSComputedEntry] = @[]
  let window = ctx.window
  var parser = initCSSParserSink(toks)
  ?parser.parseComputedValues0(p, window.settings.attrsp[], entries)
  ctx.applyValues(entries, revertType)
  cvar.resolved.add((vars, move(entries)))
  ok()

# applyValues runs backwards on the available entries, so that an
# important revert can skip non-important entries until the previous
# layer is reached.
# e.g. if user important sets revert on property t, then the revertMap
# of t is set to rtUserAgent, and all entries that are not in the
# user-agent origin are skipped.  (Alternatively, if user-agent set an
# important value on t, then revertMap already has t set to rtSet, and
# the user important entry in question is skipped.)
proc applyValue(ctx: var ApplyValueContext; entry: CSSComputedEntry;
    revertType: RevertType) =
  if entry.et == ceVar:
    discard ctx.resolveVariable(entry.p, entry.cvar, revertType)
    return
  let t = entry.p.p
  if ctx.revertMap[t] > revertType.pred:
    # either already set, or reverted to a subsequent value.
    return
  case entry.et
  of ceBit: ctx.vals.bits[t].dummy = entry.bit
  of ceHWord: ctx.vals.hwords[t] = entry.hword
  of ceWord: ctx.vals.words[t] = entry.word
  of ceObject: ctx.vals.objs[t] = entry.obj
  of ceGlobal:
    case entry.global
    of cgtInherit: ctx.vals.initialOrCopyFrom(ctx.parentComputed, t)
    of cgtInitial: ctx.vals.setInitial(t)
    of cgtUnset: ctx.vals.initialOrInheritFrom(ctx.parentComputed, t)
    of cgtRevert:
      if revertType == rtSet: # user agent
        ctx.vals.initialOrInheritFrom(ctx.parentComputed, t)
      else:
        ctx.revertMap[t] = revertType
        return
  of ceVar: discard
  ctx.revertMap[t] = rtSet

proc applyValues(ctx: var ApplyValueContext;
    entries: openArray[CSSComputedEntry]; revertType: RevertType) =
  for entry in entries.ritems:
    ctx.applyValue(entry, revertType)

proc applyNormalValues(ctx: var ApplyValueContext;
    list: LayeredRuleList; revertType: RevertType) =
  ctx.applyValues(list.unlayered.vals[cifNormal], revertType)
  for layer in list.layers.ritems:
    ctx.applyValues(layer.vals[cifNormal], revertType)

proc applyImportantValues(ctx: var ApplyValueContext;
    list: LayeredRuleList; revertType: RevertType) =
  for layer in list.layers:
    ctx.applyValues(layer.vals[cifImportant], revertType)
  ctx.applyValues(list.unlayered.vals[cifImportant], revertType)

proc applyPresHint(ctx: var ApplyValueContext; entry: CSSComputedEntry) =
  # This is a bit awkward: presentational hints are below author and
  # user style in the cascade, but reverting either just skips the
  # presentational hint.
  # I guess this means that even with an attr() implementation, it's
  # impossible to move presentational hints to pure CSS.  Another
  # spectacular failure of the committee...
  ctx.applyValue(entry, rtUser)

proc applyDimensionHint(ctx: var ApplyValueContext; p: CSSPropertyType;
    s: string) =
  if dim := parseDimensionValues(s):
    ctx.applyPresHint(makeEntry(p, dim))

proc applyDimensionHintGz(ctx: var ApplyValueContext; p: CSSPropertyType;
    s: string) =
  let s = parseDimensionValues(s).get(CSSLengthZero)
  if not s.isZero:
    ctx.applyPresHint(makeEntry(p, s))

proc applyColorHint(ctx: var ApplyValueContext; p: CSSPropertyType; s: string) =
  let c = parseLegacyColor(s)
  if c.isOk:
    ctx.applyPresHint(makeEntry(p, c.get.cssColor()))

proc applyLengthHint(ctx: var ApplyValueContext; p: CSSPropertyType;
    unit: CSSUnit; u: uint32) =
  let length = resolveLength(unit, float32(u), ctx.window.settings.attrsp[])
  ctx.applyPresHint(makeEntry(p, length))

const InputTypeWithSize* = {
  itColor, itDate, itDatetimeLocal, itEmail, itFile, itImage, itMonth, itNumber,
  itPassword, itRange, itSearch, itTel, itText, itTime, itURL, itWeek
}

proc applyPresHints(ctx: var ApplyValueContext; element: Element) =
  case element.tagType
  of TAG_TABLE:
    ctx.applyDimensionHintGz(cptWidth, element.attr(satWidth))
    ctx.applyDimensionHintGz(cptHeight, element.attr(satHeight))
    ctx.applyColorHint(cptBackgroundColor, element.attr(satBgcolor))
    if s := element.attrul(satCellspacing):
      let n = cssLength(float32(s))
      ctx.applyPresHint(makeEntry(cptBorderSpacingInline, n))
      ctx.applyPresHint(makeEntry(cptBorderSpacingBlock, n))
  of TAG_TD, TAG_TH:
    ctx.applyDimensionHintGz(cptWidth, element.attr(satWidth))
    ctx.applyDimensionHintGz(cptHeight, element.attr(satHeight))
    ctx.applyColorHint(cptBackgroundColor, element.attr(satBgcolor))
    let colspan = element.attrulgz(satColspan).get(1001)
    if colspan < 1001:
      ctx.applyPresHint(makeEntry(cptChaColspan, int32(colspan)))
    let rowspan = element.attrul(satRowspan).get(65535)
    if rowspan < 65535:
      ctx.applyPresHint(makeEntry(cptChaRowspan, int32(rowspan)))
  of TAG_THEAD, TAG_TBODY, TAG_TFOOT, TAG_TR:
    ctx.applyDimensionHint(cptHeight, element.attr(satHeight))
    ctx.applyColorHint(cptBackgroundColor, element.attr(satBgcolor))
  of TAG_COL:
    ctx.applyDimensionHint(cptWidth, element.attr(satWidth))
  of TAG_IMG, TAG_CANVAS, TAG_SVG:
    ctx.applyDimensionHint(cptWidth, element.attr(satWidth))
    ctx.applyDimensionHint(cptHeight, element.attr(satHeight))
  of TAG_HTML:
    ctx.applyPresHint(makeEntry(cptBgcolorIsCanvas,
      CSSValueBit(bgcolorIsCanvas: true)))
  of TAG_BODY:
    ctx.applyPresHint(makeEntry(cptBgcolorIsCanvas,
      CSSValueBit(bgcolorIsCanvas: true)))
    ctx.applyColorHint(cptBackgroundColor, element.attr(satBgcolor))
    ctx.applyColorHint(cptColor, element.attr(satText))
  of TAG_TEXTAREA:
    let textarea = HTMLTextAreaElement(element)
    let cols = textarea.attrul(satCols).get(20)
    let rows = textarea.attrul(satRows).get(1)
    ctx.applyLengthHint(cptWidth, cuCh, cols)
    ctx.applyLengthHint(cptHeight, cuEm, rows)
  of TAG_FONT:
    ctx.applyColorHint(cptColor, element.attr(satColor))
  of TAG_INPUT:
    let input = HTMLInputElement(element)
    if input.inputType in InputTypeWithSize:
      let n = float32(element.attrulgz(satSize).get(20))
      let length = resolveLength(cuCh, n, ctx.window.settings.attrsp[])
      ctx.applyPresHint(makeEntry(cptInputIntrinsicSize, length.npx))
  of TAG_PROGRESS:
    let position = element.getProgressPosition()
    if position > 0:
      ctx.applyPresHint(makeEntry(cptInputIntrinsicSize, float32(position)))
  of TAG_SELECT:
    if element.attrb(satMultiple):
      let size = element.attrulgz(satSize).get(4)
      ctx.applyLengthHint(cptHeight, cuEm, size)
  of TAG_OL:
    if n := element.attrl(satStart):
      if n > int32.low:
        let n = n - 1
        let val = CSSValue(
          v: cvtCounterSet,
          counterSet: @[CSSCounterSet(name: satListItem.toAtom(), num: n)]
        )
        ctx.applyPresHint(makeEntry(cptCounterReset, val))
  of TAG_LI:
    if n := element.attrl(satValue):
      let val = CSSValue(
        v: cvtCounterSet,
        counterSet: @[CSSCounterSet(name: satListItem.toAtom(), num: n)]
      )
      ctx.applyPresHint(makeEntry(cptCounterSet, val))
  of TAG_HR:
    if dim := parseDimensionValues(element.attr(satWidth)):
      if dim.isPx:
        dim.npx = max(dim.npx, float32(ctx.window.settings.attrsp.ppc))
      ctx.applyPresHint(makeEntry(cptWidth, dim))
    ctx.applyColorHint(cptColor, element.attr(satColor))
  else: discard

proc applyVars(ctx: var ApplyValueContext; vars: seq[CSSVariable];
    parentVars: CSSVariableMap) =
  if vars.len > 0:
    if ctx.vals.vars == nil:
      ctx.vals.vars = newCSSVariableMap(parentVars)
    for cvar in vars.ritems:
      ctx.vals.vars.putIfAbsent(cvar.name, cvar)

proc applyDeclarations(rules: RuleList; parent, element: Element;
    window: Window; old: CSSValues): CSSValues =
  result = CSSValues()
  var parentVars: CSSVariableMap = nil
  var ctx = ApplyValueContext(window: window, vals: result, old: old)
  if parent != nil:
    parent.ensureStyle()
    ctx.parentComputed = parent.computed
    parentVars = ctx.parentComputed.vars
  for origin in CSSOrigin:
    for layer in rules.a[origin].layers:
      ctx.applyVars(layer.vars[cifImportant], parentVars)
    ctx.applyVars(rules.a[origin].unlayered.vars[cifImportant], parentVars)
  for origin in countdown(CSSOrigin.high, CSSOrigin.low):
    ctx.applyVars(rules.a[origin].unlayered.vars[cifNormal], parentVars)
    for layer in rules.a[origin].layers:
      ctx.applyVars(layer.vars[cifNormal], parentVars)
  if result.vars == nil:
    result.vars = parentVars # inherit parent
  ctx.applyImportantValues(rules.a[coUserAgent], rtSet)
  ctx.applyImportantValues(rules.a[coUser], rtUserAgent)
  ctx.applyImportantValues(rules.a[coAuthor], rtUser)
  ctx.applyNormalValues(rules.a[coAuthor], rtUser)
  ctx.applyNormalValues(rules.a[coUser], rtUserAgent)
  # Presentational hints override user agent style, but respect user/author
  # style.
  if element != nil:
    ctx.applyPresHints(element)
  ctx.applyNormalValues(rules.a[coUserAgent], rtSet)
  # fill in defaults
  if ctx.revertMap[cptColor] != rtSet or result{"color"}.t == cctCurrent:
    # do this first so currentcolor works
    result.initialOrInheritFrom(ctx.parentComputed, cptColor)
  var relayout = old != nil and old.relayout
  for t in CSSPropertyType:
    if ctx.revertMap[t] != rtSet:
      result.initialOrInheritFrom(ctx.parentComputed, t)
    if valueType(t) == cvtColor and result.words[t].color.t == cctCurrent:
      result.words[t].color = result{"color"}
    if old != nil and t in LayoutProperties:
      relayout = relayout or not result.equals(old, t)
  result.relayout = relayout
  # Quirk: it seems others aren't implementing what the spec says about
  # blockification.
  # Well, neither will I, because the spec breaks on actual websites.
  # Curse CSS.
  if result{"position"} in PositionAbsoluteFixed:
    if result{"display"} == DisplayInline:
      result{"display"} = DisplayInlineBlock
  elif result{"float"} != FloatNone or
      ctx.parentComputed != nil and
        ctx.parentComputed{"display"} in DisplayInnerFlex + DisplayInnerGrid:
    result{"display"} = result{"display"}.blockify()
  if (result{"overflow-x"} in {OverflowVisible, OverflowClip}) !=
      (result{"overflow-y"} in {OverflowVisible, OverflowClip}):
    result{"overflow-x"} = result{"overflow-x"}.bfcify()
    result{"overflow-y"} = result{"overflow-y"}.bfcify()
  if element != nil and element.getBitmap() != nil:
    result{"display"} = result{"display"}.imgify()

proc applyDeclarations(map: RuleListMap; pseudo: PseudoElement;
    parent, element: Element; window: Window; old: CSSValues): CSSValues =
  result = map[pseudo].applyDeclarations(parent, element, window, old)
  result.pseudo = pseudo

proc applyStyle(element: Element) =
  let document = element.document
  let window = document.window
  var depends = DependencyInfo.default
  var map = RuleListMap.default
  map.calcRules(element, document.getRuleMap(), depends)
  let style = element.cachedStyle
  if window.settings.styling and style != nil:
    for decl in style.decls:
      let f = decl.f
      case decl.t
      of cdtVariable:
        map[peNone].a[coAuthor].unlayered.vars[f].add(CSSVariable(
          name: decl.v,
          items: parseDeclWithVar0(decl.value)
        ))
      of cdtProperty:
        if decl.hasVar:
          if entry := parseDeclWithVar(decl.p, decl.value):
            map[peNone].a[coAuthor].unlayered.vals[f].add(entry)
        else:
          map[peNone].a[coAuthor].unlayered.vals[f].parseComputedValues(decl.p,
            decl.value, window.settings.attrsp[])
  element.applyStyleDependencies(depends)
  var computed = map.applyDeclarations(peNone, element.parentElement, element,
    window, element.computed)
  element.computed = computed
  for pseudo in peBefore .. PseudoElement.high:
    if map[pseudo].hasValues or window.settings.scripting == smApp:
      let next = computed.next
      let old = if next != nil and next.pseudo == pseudo: next else: nil
      let pcomputed = map.applyDeclarations(pseudo, element, nil, window, old)
      if pseudo == peMarker:
        pcomputed{"display"} = DisplayMarker
      computed.next = pcomputed
      computed = pcomputed

proc ensureStyle*(element: Element) =
  if element.computed == nil or element.computed.invalid:
    element.applyStyle()

# Forward declaration hack
applyStyleImpl = applyStyle

{.pop.} # raises: []
