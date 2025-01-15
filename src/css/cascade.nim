import std/algorithm
import std/options
import std/tables

import chame/tags
import css/cssparser
import css/cssvalues
import css/lunit
import css/match
import css/mediaquery
import css/selectorparser
import css/sheet
import css/stylednode
import html/catom
import html/dom
import html/enums
import html/script
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

  RuleListMap = ref object
    rules: array[PseudoElement, RuleList]

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

proc calcRules0(map: RuleListMap; styledNode: StyledNode; sheet: CSSStylesheet;
    origin: CSSOrigin) =
  let element = styledNode.element
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
    tosorts.calcRule(element, styledNode.depends, rule)
  for pseudo, it in tosorts.mpairs:
    it.sort(proc(x, y: RulePair): int =
      let n = cmp(x.specificity, y.specificity)
      if n != 0:
        return n
      return cmp(x.rule.idx, y.rule.idx), order = Ascending)
    for item in it:
      map.rules[pseudo][origin].add(item.rule)

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

proc applyDeclarations0(rules: RuleList; parent, element: Element;
    window: Window): CSSValues =
  result = CSSValues()
  var parentComputed: CSSValues = nil
  var parentVars: CSSVariableMap = nil
  if parent != nil:
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

proc applyDeclarations(styledNode: StyledNode; parent: Element;
    map: RuleListMap; window: Window; pseudo = peNone) =
  let element = if styledNode.pseudo == peNone: styledNode.element else: nil
  styledNode.computed = map.rules[pseudo].applyDeclarations0(parent, element,
    window)
  if element != nil:
    element.computed = styledNode.computed

func hasValues(rules: RuleList): bool =
  for x in rules:
    if x.normal.len > 0 or x.important.len > 0:
      return true
  return false

func applyMediaQuery(ss: CSSStylesheet; window: Window): CSSStylesheet =
  if ss == nil:
    return nil
  var res = CSSStylesheet()
  res[] = ss[]
  for mq in ss.mqList:
    if mq.query.applies(window.settings.scripting, window.attrsp):
      res.add(mq.children.applyMediaQuery(window))
  return res

proc calcRules(styledNode: StyledNode; ua, user: CSSStylesheet;
    author: seq[CSSStylesheet]; window: Window): RuleListMap =
  let map = RuleListMap()
  map.calcRules0(styledNode, ua, coUserAgent)
  if user != nil:
    map.calcRules0(styledNode, user, coUser)
  for rule in author:
    map.calcRules0(styledNode, rule, coAuthor)
  let style = styledNode.element.cachedStyle
  if window.styling and style != nil:
    for decl in style.decls:
      #TODO variables
      let vals = parseComputedValues(decl.name, decl.value, window.attrsp[],
        window.factory)
      if decl.important:
        map.rules[peNone][coAuthor].important.add(vals)
      else:
        map.rules[peNone][coAuthor].normal.add(vals)
  return map

type CascadeFrame = object
  styledParent: StyledNode
  child: Node
  pseudo: PseudoElement
  cachedChild: StyledNode
  cachedChildren: seq[StyledNode]
  parentMap: RuleListMap

proc getAuthorSheets(document: Document): seq[CSSStylesheet] =
  var author: seq[CSSStylesheet] = @[]
  for sheet in document.sheets():
    author.add(sheet.applyMediaQuery(document.window))
  return author

proc applyRulesFrameValid(frame: var CascadeFrame): StyledNode =
  let styledParent = frame.styledParent
  let cachedChild = frame.cachedChild
  # Pseudo elements can't have invalid children.
  if cachedChild.t == stElement and cachedChild.pseudo == peNone:
    # Refresh child nodes:
    # * move old seq to a temporary location in frame
    # * create new seq, assuming capacity == len of the previous pass
    frame.cachedChildren = move(cachedChild.children)
    cachedChild.children = newSeqOfCap[StyledNode](frame.cachedChildren.len)
  if styledParent != nil:
    styledParent.children.add(cachedChild)
  return cachedChild

proc applyRulesFrameInvalid(frame: CascadeFrame; ua, user: CSSStylesheet;
    author: seq[CSSStylesheet]; map: var RuleListMap; window: Window):
    StyledNode =
  let pseudo = frame.pseudo
  let styledParent = frame.styledParent
  let child = frame.child
  case pseudo
  of peNone: # not a pseudo-element, but a real one
    assert child != nil
    if child of Element:
      let element = Element(child)
      let styledChild = newStyledElement(element)
      map = styledChild.calcRules(ua, user, author, window)
      if styledParent == nil: # root element
        styledChild.applyDeclarations(nil, map, window)
      else:
        styledParent.children.add(styledChild)
        styledChild.applyDeclarations(styledParent.element, map, window)
      return styledChild
    elif child of Text:
      let text = Text(child)
      let styledChild = styledParent.newStyledText(text)
      styledParent.children.add(styledChild)
      return styledChild
  of peBefore, peAfter:
    let map = frame.parentMap
    if map.rules[pseudo].hasValues():
      let styledPseudo = styledParent.newStyledElement(pseudo)
      styledPseudo.applyDeclarations(styledParent.element, map, window, pseudo)
      if styledPseudo.computed{"content"}.len > 0:
        for content in styledPseudo.computed{"content"}:
          let child = styledPseudo.newStyledReplacement(content, peNone)
          styledPseudo.children.add(child)
        styledParent.children.add(styledPseudo)
  of peInputText:
    let s = HTMLInputElement(styledParent.element).inputString()
    if s.len > 0:
      let content = styledParent.element.document.newText(s)
      let styledText = styledParent.newStyledText(content)
      # Note: some pseudo-elements (like input text) generate text nodes
      # directly, so we have to cache them like this.
      styledText.pseudo = pseudo
      styledParent.children.add(styledText)
  of peTextareaText:
    let s = HTMLTextAreaElement(styledParent.element).textAreaString()
    if s.len > 0:
      let content = styledParent.element.document.newText(s)
      let styledText = styledParent.newStyledText(content)
      styledText.pseudo = pseudo
      styledParent.children.add(styledText)
  of peImage:
    let content = CSSContent(
      t: ContentImage,
      bmp: HTMLImageElement(styledParent.element).bitmap
    )
    let styledText = styledParent.newStyledReplacement(content, pseudo)
    styledParent.children.add(styledText)
  of peSVG:
    let content = CSSContent(
      t: ContentImage,
      bmp: SVGSVGElement(styledParent.element).bitmap
    )
    let styledText = styledParent.newStyledReplacement(content, pseudo)
    styledParent.children.add(styledText)
  of peCanvas:
    let bmp = HTMLCanvasElement(styledParent.element).bitmap
    if bmp != nil and bmp.cacheId != 0:
      let content = CSSContent(
        t: ContentImage,
        bmp: bmp
      )
      let styledText = styledParent.newStyledReplacement(content, pseudo)
      styledParent.children.add(styledText)
  of peVideo:
    let content = CSSContent(t: ContentVideo)
    let styledText = styledParent.newStyledReplacement(content, pseudo)
    styledParent.children.add(styledText)
  of peAudio:
    let content = CSSContent(t: ContentAudio)
    let styledText = styledParent.newStyledReplacement(content, pseudo)
    styledParent.children.add(styledText)
  of peIFrame:
    let content = CSSContent(t: ContentIFrame)
    let styledText = styledParent.newStyledReplacement(content, pseudo)
    styledParent.children.add(styledText)
  of peNewline:
    let content = CSSContent(t: ContentNewline)
    let styledText = styledParent.newStyledReplacement(content, pseudo)
    styledParent.children.add(styledText)
  return nil

proc stackAppend(styledStack: var seq[CascadeFrame]; frame: CascadeFrame;
    styledParent: StyledNode; child: Element; i: var int) =
  var cached: StyledNode = nil
  if frame.cachedChildren.len > 0:
    for j in countdown(i, 0):
      let it = frame.cachedChildren[j]
      if it.t == stElement and it.pseudo == peNone and it.element == child:
        i = j - 1
        cached = it
        break
  styledStack.add(CascadeFrame(
    styledParent: styledParent,
    child: child,
    pseudo: peNone,
    cachedChild: cached
  ))

proc stackAppend(styledStack: var seq[CascadeFrame]; frame: CascadeFrame;
    styledParent: StyledNode; child: Text; i: var int) =
  var cached: StyledNode = nil
  if frame.cachedChildren.len > 0:
    for j in countdown(i, 0):
      let it = frame.cachedChildren[j]
      if it.t == stText and it.text == child:
        i = j - 1
        cached = it
        break
  styledStack.add(CascadeFrame(
    styledParent: styledParent,
    child: child,
    pseudo: peNone,
    cachedChild: cached
  ))

proc stackAppend(styledStack: var seq[CascadeFrame]; frame: CascadeFrame;
    styledParent: StyledNode; pseudo: PseudoElement; i: var int;
    parentMap: RuleListMap = nil) =
  # Can't check for cachedChildren.len here, because we assume that we only have
  # cached pseudo elems when the parent is also cached.
  if frame.cachedChild != nil:
    var cached: StyledNode = nil
    for j in countdown(i, 0):
      let it = frame.cachedChildren[j]
      if it.pseudo == pseudo:
        cached = it
        i = j - 1
        break
    # When calculating pseudo-element rules, their dependencies are added
    # to their parent's dependency list; so invalidating a pseudo-element
    # invalidates its parent too, which in turn automatically rebuilds
    # the pseudo-element.
    # In other words, we can just do this:
    if cached != nil:
      styledStack.add(CascadeFrame(
        styledParent: styledParent,
        pseudo: pseudo,
        cachedChild: cached,
        parentMap: parentMap
      ))
  else:
    styledStack.add(CascadeFrame(
      styledParent: styledParent,
      pseudo: pseudo,
      cachedChild: nil,
      parentMap: parentMap
    ))

# Append children to styledChild.
proc appendChildren(styledStack: var seq[CascadeFrame]; frame: CascadeFrame;
    styledChild: StyledNode; parentMap: RuleListMap) =
  # i points to the child currently being inspected.
  var idx = frame.cachedChildren.len - 1
  let element = styledChild.element
  # reset invalid flag here to avoid a type conversion above
  element.invalid = false
  styledStack.stackAppend(frame, styledChild, peAfter, idx, parentMap)
  case element.tagType
  of TAG_TEXTAREA:
    styledStack.stackAppend(frame, styledChild, peTextareaText, idx)
  of TAG_IMG: styledStack.stackAppend(frame, styledChild, peImage, idx)
  of TAG_VIDEO: styledStack.stackAppend(frame, styledChild, peVideo, idx)
  of TAG_AUDIO: styledStack.stackAppend(frame, styledChild, peAudio, idx)
  of TAG_BR: styledStack.stackAppend(frame, styledChild, peNewline, idx)
  of TAG_CANVAS: styledStack.stackAppend(frame, styledChild, peCanvas, idx)
  of TAG_IFRAME: styledStack.stackAppend(frame, styledChild, peIFrame, idx)
  elif element.tagType(Namespace.SVG) == TAG_SVG:
    styledStack.stackAppend(frame, styledChild, peSVG, idx)
  else:
    for i in countdown(element.childList.high, 0):
      let child = element.childList[i]
      if child of Element:
        styledStack.stackAppend(frame, styledChild, Element(child), idx)
      elif child of Text:
        styledStack.stackAppend(frame, styledChild, Text(child), idx)
    if element.tagType == TAG_INPUT:
      styledStack.stackAppend(frame, styledChild, peInputText, idx)
  styledStack.stackAppend(frame, styledChild, peBefore, idx, parentMap)

# Builds a StyledNode tree, optionally based on a previously cached version.
proc applyRules(document: Document; ua, user: CSSStylesheet;
    cachedTree: StyledNode): StyledNode =
  let html = document.documentElement
  if html == nil:
    return
  let author = document.getAuthorSheets()
  var styledStack = @[CascadeFrame(
    child: html,
    pseudo: peNone,
    cachedChild: cachedTree
  )]
  var root: StyledNode = nil
  var toReset: seq[Element] = @[]
  while styledStack.len > 0:
    var frame = styledStack.pop()
    var map: RuleListMap = nil
    let styledParent = frame.styledParent
    let valid = frame.cachedChild != nil and frame.cachedChild.isValid(toReset)
    let styledChild = if valid:
      frame.applyRulesFrameValid()
    else:
      # From here on, computed values of this node's children are invalid
      # because of property inheritance.
      frame.cachedChild = nil
      frame.applyRulesFrameInvalid(ua, user, author, map, document.window)
    if styledChild != nil:
      if styledParent == nil:
        # Root element
        root = styledChild
      if styledChild.t == stElement and styledChild.pseudo == peNone:
        # note: following resets styledChild.node's invalid flag
        styledStack.appendChildren(frame, styledChild, map)
  for element in toReset:
    element.invalidDeps = {}
  return root

proc applyStylesheets*(document: Document; uass, userss: CSSStylesheet;
    previousStyled: StyledNode): StyledNode =
  let uass = uass.applyMediaQuery(document.window)
  let userss = userss.applyMediaQuery(document.window)
  return document.applyRules(uass, userss, previousStyled)
