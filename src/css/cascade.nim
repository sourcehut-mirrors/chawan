import std/algorithm
import std/options
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
import types/bitmap
import types/color
import types/jscolor
import types/opt
import types/winattrs

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

# Forward declarations
proc applyValue(vals: CSSValues; entry: CSSComputedEntry;
  parentComputed, previousOrigin: CSSValues; initMap: var InitMap;
  initType: InitType; nextInitType: set[InitType]; window: Window)
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
    sheet.idTable.withValue(sheet.factory.toLowerAscii(element.id), v):
      rules.add(v[])
  for class in element.classList:
    sheet.classTable.withValue(sheet.factory.toLowerAscii(class), v):
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

proc findVariable(computed: CSSValues; varName: CAtom): CSSVariable =
  var vars = computed.vars
  while vars != nil:
    let cvar = vars.table.getOrDefault(varName)
    if cvar != nil:
      return cvar
    vars = vars.parent
  return nil

proc applyVariable(vals: CSSValues; t: CSSPropertyType; varName: CAtom;
    fallback: ref CSSComputedEntry; parentComputed, previousOrigin: CSSValues;
    initMap: var InitMap; initType: InitType; nextInitType: set[InitType];
    window: Window) =
  let v = t.valueType
  let cvar = vals.findVariable(varName)
  if cvar == nil:
    if fallback != nil:
      vals.applyValue(fallback[], parentComputed, previousOrigin, initMap,
        initType, nextInitType, window)
    return
  for (iv, entry) in cvar.resolved.mitems:
    if iv == v:
      entry.t = t # must override, same var can be used for different props
      vals.applyValue(entry, parentComputed, previousOrigin, initMap, initType,
        nextInitType, window)
      return
  var entries: seq[CSSComputedEntry] = @[]
  assert window != nil
  if entries.parseComputedValues($t, cvar.cvals, window.attrsp[],
      window.factory).isSome:
    if entries[0].et != ceVar:
      cvar.resolved.add((v, entries[0]))
      vals.applyValue(entries[0], parentComputed, previousOrigin, initMap,
        initType, nextInitType, window)

proc applyGlobal(vals: CSSValues; t: CSSPropertyType; global: CSSGlobalType;
    parentComputed, previousOrigin: CSSValues; initMap: InitMap;
    initType: InitType) =
  case global
  of cgtInherit:
    vals.initialOrCopyFrom(parentComputed, t)
  of cgtInitial:
    vals.setInitial(t)
  of cgtUnset:
    vals.initialOrInheritFrom(parentComputed, t)
  of cgtRevert:
    if previousOrigin != nil and initType in initMap[t]:
      vals.copyFrom(previousOrigin, t)
    else:
      vals.initialOrInheritFrom(parentComputed, t)

proc applyValue(vals: CSSValues; entry: CSSComputedEntry;
    parentComputed, previousOrigin: CSSValues; initMap: var InitMap;
    initType: InitType; nextInitType: set[InitType]; window: Window) =
  case entry.et
  of ceBit: vals.bits[entry.t].dummy = entry.bit
  of ceWord: vals.words[entry.t] = entry.word
  of ceObject: vals.objs[entry.t] = entry.obj
  of ceGlobal:
    vals.applyGlobal(entry.t, entry.global, parentComputed, previousOrigin,
      initMap, initType)
  of ceVar:
    vals.applyVariable(entry.t, entry.cvar, entry.fallback, parentComputed,
      previousOrigin, initMap, initType, nextInitType, window)
    return # maybe it applies, maybe it doesn't...
  initMap[entry.t] = initMap[entry.t] + nextInitType

proc applyPresHints(computed: CSSValues; element: Element;
    attrs: WindowAttributes; initMap: var InitMap, window: Window) =
  template set_cv(t, x, b: untyped) =
    computed.applyValue(makeEntry(t, CSSValueWord(x: b)), nil, nil, initMap,
      itUserAgent, {itUser}, window)
  template set_cv_new(t, x, b: untyped) =
    const v = valueType(t)
    let val = CSSValue(v: v, x: b)
    computed.applyValue(makeEntry(t, val), nil, nil, initMap, itUserAgent,
      {itUser}, window)
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
      set_cv cptWidth, length, resolveLength(cuCh, float32(s.get), attrs)
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
    computed.applyValue(makeEntry(t, val), nil, nil, initMap, itUserAgent,
      {itUser}, window)
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
    set_cv cptWidth, length, resolveLength(cuCh, float32(cols), attrs)
    set_cv cptHeight, length, resolveLength(cuEm, float32(rows), attrs)
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
      set_cv cptHeight, length, resolveLength(cuEm, float32(size), attrs)
  else: discard

proc applyDeclarations(rules: RuleList; parent, element: Element;
    window: Window): CSSValues =
  result = CSSValues()
  var parentComputed: CSSValues = nil
  var parentVars: CSSVariableMap = nil
  if parent != nil:
    if parent.computed == nil:
      parent.applyStyle()
    parentComputed = parent.computed
    parentVars = parentComputed.vars
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
  var initMap = InitMap.default
  for entry in rules[coUserAgent].normal: # user agent
    result.applyValue(entry, parentComputed, nil, initMap, itOther,
      {itUserAgent, itUser}, window)
  let uaProperties = result.copyProperties()
  # Presentational hints override user agent style, but respect user/author
  # style.
  if element != nil:
    result.applyPresHints(element, window.attrsp[], initMap, window)
  for entry in rules[coUser].normal: # user
    result.applyValue(entry, parentComputed, uaProperties, initMap, itUserAgent,
      {itUser}, window)
  # save user properties so author can use them
  let userProperties = result.copyProperties()
  for entry in rules[coAuthor].normal: # author
    result.applyValue(entry, parentComputed, userProperties, initMap, itUser,
      {itOther}, window)
  for entry in rules[coAuthor].important: # author important
    result.applyValue(entry, parentComputed, userProperties, initMap, itUser,
      {itOther}, window)
  for entry in rules[coUser].important: # user important
    result.applyValue(entry, parentComputed, uaProperties, initMap, itUserAgent,
      {itOther}, window)
  for entry in rules[coUserAgent].important: # user agent important
    result.applyValue(entry, parentComputed, nil, initMap, itUserAgent,
      {itOther}, window)
  # set defaults
  for t in CSSPropertyType:
    if initMap[t] == {}:
      result.initialOrInheritFrom(parentComputed, t)
  # Quirk: it seems others aren't implementing what the spec says about
  # blockification.
  # Well, neither will I, because the spec breaks on actual websites.
  # Curse CSS.
  if result{"position"} in {PositionAbsolute, PositionFixed}:
    if result{"display"} == DisplayInline:
      result{"display"} = DisplayInlineBlock
  elif result{"float"} != FloatNone:
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
      let vals = parseComputedValues(decl.name, decl.value, window.attrsp[],
        window.factory)
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

# Abstraction over the DOM to pretend that elements, text, replaced and
# pseudo-elements are derived from the same type.
type
  StyledType* = enum
    stElement, stText, stReplacement

  StyledNode* = object
    element*: Element
    pseudo*: PseudoElement
    case t*: StyledType
    of stText:
      text*: CharacterData
    of stElement:
      discard
    of stReplacement:
      # replaced elements: quotes, images, or (TODO) markers
      content*: CSSContent

when defined(debug):
  func `$`*(node: StyledNode): string =
    case node.t
    of stText:
      return "#text " & node.text.data
    of stElement:
      if node.pseudo != peNone:
        return $node.element.tagType & "::" & $node.pseudo
      return $node.element
    of stReplacement:
      return "#replacement"

# Defined here so it isn't accidentally used in dom.
#TODO it may be better to do it in dom anyway, so we can cache it...
func newCharacterData*(data: sink string): CharacterData =
  return CharacterData(data: data)

template computed*(styledNode: StyledNode): CSSValues =
  styledNode.element.computedMap[styledNode.pseudo]

proc initStyledElement*(element: Element): StyledNode =
  if element.computed == nil:
    element.applyStyle()
  return StyledNode(t: stElement, element: element)

proc initStyledReplacement(parent: Element; content: sink CSSContent):
    StyledNode =
  return StyledNode(t: stReplacement, element: parent, content: content)

proc initStyledImage(parent: Element; bmp: NetworkBitmap): StyledNode =
  return initStyledReplacement(parent, CSSContent(t: ContentImage, bmp: bmp))

proc initStyledPseudo(parent: Element; pseudo: PseudoElement): StyledNode =
  return StyledNode(t: stElement, pseudo: pseudo, element: parent)

proc initStyledText(parent: Element; text: CharacterData): StyledNode =
  return StyledNode(t: stText, element: parent, text: text)

proc initStyledText(parent: Element; s: sink string): StyledNode =
  return initStyledText(parent, newCharacterData(s))

# Many yields; we use a closure iterator to avoid bloating the code.
iterator children*(styledNode: StyledNode): StyledNode {.closure.} =
  if styledNode.t != stElement:
    return
  if styledNode.pseudo == peNone:
    let parent = styledNode.element
    if parent.computedMap[peBefore] != nil and
        parent.computedMap[peBefore]{"content"}.len > 0:
      yield initStyledPseudo(parent, peBefore)
    case parent.tagType
    of TAG_INPUT:
      #TODO cache (just put value in a CharacterData)
      let s = HTMLInputElement(parent).inputString()
      if s.len > 0:
        yield initStyledText(parent, s)
    of TAG_TEXTAREA:
      #TODO cache (do the same as with input, and add borders in render)
      yield initStyledText(parent, HTMLTextAreaElement(parent).textAreaString())
    of TAG_IMG: yield initStyledImage(parent, HTMLImageElement(parent).bitmap)
    of TAG_CANVAS:
      yield initStyledImage(parent, HTMLImageElement(parent).bitmap)
    of TAG_VIDEO: yield initStyledText(parent, "[video]")
    of TAG_AUDIO: yield initStyledText(parent, "[audio]")
    of TAG_BR:
      yield initStyledReplacement(parent, CSSContent(t: ContentNewline))
    of TAG_IFRAME: yield initStyledText(parent, "[iframe]")
    elif parent.tagType(Namespace.SVG) == TAG_SVG:
      yield initStyledImage(parent, SVGSVGElement(parent).bitmap)
    else:
      for it in parent.childList:
        if it of Element:
          yield initStyledElement(Element(it))
        elif it of Text:
          yield initStyledText(parent, Text(it))
    if parent.computedMap[peAfter] != nil and
        parent.computedMap[peAfter]{"content"}.len > 0:
      yield initStyledPseudo(parent, peAfter)
  else:
    let parent = styledNode.element
    for content in parent.computedMap[styledNode.pseudo]{"content"}:
      yield parent.initStyledReplacement(content)
