{.push raises: [].}

import std/algorithm
import std/sets
import std/tables

import chame/tags
import config/conftypes
import css/cssparser
import css/cssvalues
import css/lunit
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

  RuleList = array[CSSOrigin, RuleListEntry]

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
    revertMap: RevertMap
    varsSeen: HashSet[CAtom]

# Forward declarations
proc applyStyle*(element: Element)
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

proc calcRules(map: var RuleListMap; element: Element;
    sheet: CSSStylesheet; origin: CSSOrigin; depends: var DependencyInfo) =
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
  tosorts.calcRules(element, depends, sheet.generalList)
  for pseudo, it in tosorts.mpairs:
    it.sort(proc(x, y: RulePair): int =
      let n = cmp(x.specificity, y.specificity)
      if n != 0:
        return n
      return cmp(x.rule.idx, y.rule.idx), order = Ascending)
    for item in it:
      map[pseudo][origin].add(item.rule)

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

proc resolveVariable(ctx: var ApplyValueContext; p: CSSAnyPropertyType;
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
    const InputTypeWithSize = {
      itSearch, itText, itEmail, itPassword, itURL, itTel
    }
    if input.inputType in InputTypeWithSize:
      if s := element.attrul(satSize):
        ctx.applyLengthHint(cptWidth, cuCh, s)
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
    if rules[origin].vars[cifImportant].len > 0:
      if result.vars == nil:
        result.vars = newCSSVariableMap(parentVars)
      for cvar in rules[origin].vars[cifImportant].ritems:
        result.vars.putIfAbsent(cvar.name, cvar)
  for origin in countdown(CSSOrigin.high, CSSOrigin.low):
    if rules[origin].vars[cifNormal].len > 0:
      if result.vars == nil:
        result.vars = newCSSVariableMap(parentVars)
      for cvar in rules[origin].vars[cifNormal].ritems:
        result.vars.putIfAbsent(cvar.name, cvar)
  if result.vars == nil:
    result.vars = parentVars # inherit parent
  ctx.applyValues(rules[coUserAgent].vals[cifImportant], rtSet)
  ctx.applyValues(rules[coUser].vals[cifImportant], rtUserAgent)
  ctx.applyValues(rules[coAuthor].vals[cifImportant], rtUser)
  ctx.applyValues(rules[coAuthor].vals[cifNormal], rtUser)
  ctx.applyValues(rules[coUser].vals[cifNormal], rtUserAgent)
  # Presentational hints override user agent style, but respect user/author
  # style.
  if element != nil:
    ctx.applyPresHints(element)
  ctx.applyValues(rules[coUserAgent].vals[cifNormal], rtSet)
  # fill in defaults
  for t in CSSPropertyType:
    if ctx.revertMap[t] != rtSet:
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
        ctx.parentComputed{"display"} in DisplayInnerFlex + DisplayInnerGrid:
    result{"display"} = result{"display"}.blockify()
  if (result{"overflow-x"} in {OverflowVisible, OverflowClip}) !=
      (result{"overflow-y"} in {OverflowVisible, OverflowClip}):
    result{"overflow-x"} = result{"overflow-x"}.bfcify()
    result{"overflow-y"} = result{"overflow-y"}.bfcify()

proc applyDeclarations(map: RuleListMap; pseudo: PseudoElement;
    parent, element: Element; window: Window): CSSValues =
  result = map[pseudo].applyDeclarations(parent, element, window)
  result.pseudo = pseudo

func hasValues(rules: RuleList): bool =
  for x in rules:
    for y in x.vals:
      if y.len > 0:
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
  if window.settings.styling and style != nil:
    for decl in style.decls:
      let f = decl.f
      case decl.t
      of cdtUnknown: discard
      of cdtVariable:
        map[peNone][coAuthor].vars[f].add(CSSVariable(
          name: decl.v,
          items: parseDeclWithVar0(decl.value)
        ))
      of cdtProperty:
        if decl.hasVar:
          if entry := parseDeclWithVar(decl.p, decl.value):
            map[peNone][coAuthor].vals[f].add(entry)
        else:
          map[peNone][coAuthor].vals[f].parseComputedValues(decl.p, decl.value,
            window.settings.attrsp[])
  element.applyStyleDependencies(depends)
  var computed = map.applyDeclarations(peNone, element.parentElement, element,
    window)
  element.computed = computed
  for pseudo in peBefore .. PseudoElement.high:
    if map[pseudo].hasValues() or window.settings.scripting == smApp:
      let pcomputed = map.applyDeclarations(pseudo, element, nil, window)
      if pseudo == peMarker:
        pcomputed{"display"} = DisplayMarker
      computed.next = pcomputed
      computed = pcomputed

# Forward declaration hack
applyStyleImpl = applyStyle

{.pop.} # raises: []
