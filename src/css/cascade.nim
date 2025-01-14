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

  RuleList = array[CSSOrigin, RuleListEntry]

  RuleListMap = ref object
    rules: array[PseudoElement, RuleList]

  RulePair = tuple
    specificity: int
    rule: CSSRuleDef

  ToSorts = array[PseudoElement, seq[RulePair]]

proc calcRule(tosorts: var ToSorts; element: Element;
    depends: var DependencyInfo; rule: CSSRuleDef) =
  for sel in rule.sels:
    if element.matches(sel, depends):
      if tosorts[sel.pseudo].len > 0 and tosorts[sel.pseudo][^1].rule == rule:
        tosorts[sel.pseudo][^1].specificity =
          max(tosorts[sel.pseudo][^1].specificity, sel.specificity)
      else:
        tosorts[sel.pseudo].add((sel.specificity, rule))

func calcRules(map: RuleListMap; styledNode: StyledNode; sheet: CSSStylesheet;
    origin: CSSOrigin) =
  var tosorts = ToSorts.default
  let element = Element(styledNode.node)
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
  for rule in rules:
    tosorts.calcRule(element, styledNode.depends, rule)
  for pseudo, it in tosorts.mpairs:
    it.sort(proc(x, y: (int, CSSRuleDef)): int =
      let n = cmp(x[0], y[0])
      if n != 0:
        return n
      return cmp(x[1].idx, y[1].idx), order = Ascending)
    for item in it:
      map.rules[pseudo][origin].normal.add(item[1].normalVals)
      map.rules[pseudo][origin].important.add(item[1].importantVals)

proc applyPresHints(computed: CSSValues; element: Element;
    attrs: WindowAttributes; initMap: var InitMap) =
  template set_cv(t, x, b: untyped) =
    computed.applyValue(makeEntry(t, CSSValueWord(x: b)), nil, nil, nil,
      initMap, itUserAgent)
    initMap[t].incl(itUser)
  template set_cv_new(t, x, b: untyped) =
    const v = valueType(t)
    let val = CSSValue(v: v, x: b)
    computed.applyValue(makeEntry(t, val), nil, nil, nil, initMap, itUserAgent)
    initMap[t].incl(itUser)
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
    computed.applyValue(makeEntry(t, val), nil, nil, nil, initMap, itUserAgent)
    initMap[t].incl(itUser)
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

func applyDeclarations0(rules: RuleList; parent: CSSValues; element: Element;
    window: Window): CSSValues =
  result = CSSValues()
  var initMap = InitMap.default
  for entry in rules[coUserAgent].normal: # user agent
    result.applyValue(entry, nil, parent, nil, initMap, itOther)
    initMap[entry.t] = {itUserAgent, itUser}
  let uaProperties = result.copyProperties()
  # Presentational hints override user agent style, but respect user/author
  # style.
  if element != nil:
    result.applyPresHints(element, window.attrsp[], initMap)
  for entry in rules[coUser].normal: # user
    result.applyValue(entry, nil, parent, uaProperties, initMap, itUserAgent)
    initMap[entry.t].incl(itUser)
  # save user properties so author can use them
  let userProperties = result.copyProperties()
  for entry in rules[coAuthor].normal: # author
    result.applyValue(entry, nil, parent, userProperties, initMap, itUser)
    initMap[entry.t].incl(itOther)
  for entry in rules[coAuthor].important: # author important
    result.applyValue(entry, nil, parent, userProperties, initMap, itUser)
    initMap[entry.t].incl(itOther)
  for entry in rules[coUser].important: # user important
    result.applyValue(entry, nil, parent, uaProperties, initMap, itUserAgent)
    initMap[entry.t].incl(itOther)
  for entry in rules[coUserAgent].important: # user agent important
    result.applyValue(entry, nil, parent, nil, initMap, itUserAgent)
    initMap[entry.t].incl(itOther)
  # set defaults
  for t in CSSPropertyType:
    if initMap[t] == {}:
      result.initialOrInheritFrom(parent, t)
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

proc applyDeclarations(styledNode: StyledNode; parent: CSSValues;
    map: RuleListMap; window: Window; pseudo = peNone) =
  let element = Element(styledNode.node)
  styledNode.computed = map.rules[pseudo].applyDeclarations0(parent, element,
    window)
  if element != nil and window.settings.scripting == smApp:
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

func calcRules(styledNode: StyledNode; ua, user: CSSStylesheet;
    author: seq[CSSStylesheet]; window: Window): RuleListMap =
  let map = RuleListMap()
  map.calcRules(styledNode, ua, coUserAgent)
  if user != nil:
    map.calcRules(styledNode, user, coUser)
  for rule in author:
    map.calcRules(styledNode, rule, coAuthor)
  if styledNode.node != nil:
    let style = Element(styledNode.node).cachedStyle
    if window.styling and style != nil:
      for decl in style.decls:
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
  cachedChild.parent = styledParent
  if styledParent != nil:
    styledParent.children.add(cachedChild)
  return cachedChild

proc applyRulesFrameInvalid(frame: CascadeFrame; ua, user: CSSStylesheet;
    author: seq[CSSStylesheet]; map: var RuleListMap; window: Window):
    StyledNode =
  var styledChild: StyledNode = nil
  let pseudo = frame.pseudo
  let styledParent = frame.styledParent
  let child = frame.child
  if frame.pseudo != peNone:
    case pseudo
    of peBefore, peAfter:
      let map = frame.parentMap
      if map.rules[pseudo].hasValues():
        let styledPseudo = styledParent.newStyledElement(pseudo)
        styledPseudo.applyDeclarations(styledParent.computed, map, nil, pseudo)
        if styledPseudo.computed{"content"}.len > 0:
          for content in styledPseudo.computed{"content"}:
            let child = styledPseudo.newStyledReplacement(content, peNone)
            styledPseudo.children.add(child)
          styledParent.children.add(styledPseudo)
    of peInputText:
      let s = HTMLInputElement(styledParent.node).inputString()
      if s.len > 0:
        let content = styledParent.node.document.newText(s)
        let styledText = styledParent.newStyledText(content)
        # Note: some pseudo-elements (like input text) generate text nodes
        # directly, so we have to cache them like this.
        styledText.pseudo = pseudo
        styledParent.children.add(styledText)
    of peTextareaText:
      let s = HTMLTextAreaElement(styledParent.node).textAreaString()
      if s.len > 0:
        let content = styledParent.node.document.newText(s)
        let styledText = styledParent.newStyledText(content)
        styledText.pseudo = pseudo
        styledParent.children.add(styledText)
    of peImage:
      let content = CSSContent(
        t: ContentImage,
        bmp: HTMLImageElement(styledParent.node).bitmap
      )
      let styledText = styledParent.newStyledReplacement(content, pseudo)
      styledParent.children.add(styledText)
    of peSVG:
      let content = CSSContent(
        t: ContentImage,
        bmp: SVGSVGElement(styledParent.node).bitmap
      )
      let styledText = styledParent.newStyledReplacement(content, pseudo)
      styledParent.children.add(styledText)
    of peCanvas:
      let bmp = HTMLCanvasElement(styledParent.node).bitmap
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
    of peNone: assert false
  else:
    assert child != nil
    if styledParent != nil:
      if child of Element:
        let element = Element(child)
        styledChild = styledParent.newStyledElement(element)
        styledParent.children.add(styledChild)
        map = styledChild.calcRules(ua, user, author, window)
        styledChild.applyDeclarations(styledParent.computed, map, window)
      elif child of Text:
        let text = Text(child)
        styledChild = styledParent.newStyledText(text)
        styledParent.children.add(styledChild)
    else:
      # Root element
      let element = Element(child)
      styledChild = newStyledElement(element)
      map = styledChild.calcRules(ua, user, author, window)
      styledChild.applyDeclarations(rootProperties(), map, window)
  return styledChild

proc stackAppend(styledStack: var seq[CascadeFrame]; frame: CascadeFrame;
    styledParent: StyledNode; child: Node; i: var int) =
  var cached: StyledNode = nil
  if frame.cachedChildren.len > 0:
    for j in countdown(i, 0):
      let it = frame.cachedChildren[j]
      if it.node == child:
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
  let element = Element(styledChild.node)
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
      if child of Element or child of Text:
        styledStack.stackAppend(frame, styledChild, child, idx)
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
      if styledChild.t == stElement and styledChild.node != nil:
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
