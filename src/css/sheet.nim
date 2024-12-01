import std/options
import std/tables

import css/cssparser
import css/cssvalues
import css/mediaquery
import css/selectorparser
import html/catom
import types/url
import utils/twtstr

type
  CSSRuleBase* = ref object of RootObj

  CSSRuleDef* = ref object of CSSRuleBase
    sels*: SelectorList
    normalVals*: seq[CSSComputedEntry]
    importantVals*: seq[CSSComputedEntry]
    # Absolute position in the stylesheet; used for sorting rules after
    # retrieval from the cache.
    idx: int

  CSSConditionalDef* = ref object of CSSRuleBase
    children*: CSSStylesheet

  CSSMediaQueryDef* = ref object of CSSConditionalDef
    query*: MediaQueryList

  CSSStylesheet* = ref object
    mqList*: seq[CSSMediaQueryDef]
    tagTable*: Table[CAtom, seq[CSSRuleDef]]
    idTable*: Table[CAtom, seq[CSSRuleDef]]
    classTable*: Table[CAtom, seq[CSSRuleDef]]
    attrTable*: Table[CAtom, seq[CSSRuleDef]]
    generalList*: seq[CSSRuleDef]
    importList*: seq[URL]
    len: int
    factory: CAtomFactory

type SelectorHashes = object
  tag: CAtom
  id: CAtom
  class: CAtom
  attr: CAtom

func newStylesheet*(cap: int; factory: CAtomFactory): CSSStylesheet =
  let bucketsize = cap div 2
  return CSSStylesheet(
    tagTable: initTable[CAtom, seq[CSSRuleDef]](bucketsize),
    idTable: initTable[CAtom, seq[CSSRuleDef]](bucketsize),
    classTable: initTable[CAtom, seq[CSSRuleDef]](bucketsize),
    attrTable: initTable[CAtom, seq[CSSRuleDef]](bucketsize),
    generalList: newSeqOfCap[CSSRuleDef](bucketsize),
    factory: factory
  )

proc getSelectorIds(hashes: var SelectorHashes; sel: Selector): bool

proc getSelectorIds(hashes: var SelectorHashes; sels: CompoundSelector) =
  for sel in sels:
    if hashes.getSelectorIds(sel):
      break

proc getSelectorIds(hashes: var SelectorHashes; cxsel: ComplexSelector) =
  hashes.getSelectorIds(cxsel[^1])

proc getSelectorIds(hashes: var SelectorHashes; sel: Selector): bool =
  case sel.t
  of stType:
    hashes.tag = sel.tag
    return true
  of stClass:
    hashes.class = sel.class
    return true
  of stId:
    hashes.id = sel.id
    return true
  of stAttr:
    hashes.attr = sel.attr
  of stPseudoElement, stUniversal:
    return false
  of stPseudoClass:
    if sel.pseudo.t notin {pcIs, pcWhere}:
      return false
    # Basically just hash whatever the selectors have in common:
    # 1. get the hashable values of selector 1
    # 2. for every other selector x:
    # 3.   get hashable values of selector x
    # 4.   store hashable values of selector x that aren't stored yet
    # 5.   for every hashable value of selector 1 that doesn't match selector x
    # 6.     cancel hashable value
    var cancelTag = false
    var cancelId = false
    var cancelClass = false
    var cancelAttr = false
    var i = 0
    if i < sel.pseudo.fsels.len:
      hashes.getSelectorIds(sel.pseudo.fsels[i])
      inc i
    while i < sel.pseudo.fsels.len:
      var nhashes = SelectorHashes()
      nhashes.getSelectorIds(sel.pseudo.fsels[i])
      if hashes.tag == CAtomNull:
        hashes.tag = nhashes.tag
      elif nhashes.tag != CAtomNull and nhashes.tag != hashes.tag:
        cancelTag = true
      if hashes.id == CAtomNull:
        hashes.id = nhashes.id
      elif nhashes.id != CAtomNull and nhashes.id != hashes.id:
        cancelId = true
      if hashes.class == CAtomNull:
        hashes.class = nhashes.class
      elif nhashes.class != CAtomNull and nhashes.class != hashes.class:
        cancelClass = true
      if hashes.attr == CAtomNull:
        hashes.attr = nhashes.attr
      elif nhashes.attr != CAtomNull and nhashes.attr != hashes.attr:
        cancelAttr = true
      inc i
    if cancelTag:
      hashes.tag = CAtomNull
    if cancelId:
      hashes.id = CAtomNull
    if cancelClass:
      hashes.class = CAtomNull
    if cancelAttr:
      hashes.attr = CAtomNull
    return hashes.tag != CAtomNull or hashes.id != CAtomNull or
      hashes.class != CAtomNull

proc ruleDefCmp*(a, b: CSSRuleDef): int =
  cmp(a.idx, b.idx)

proc add(sheet: CSSStylesheet; rule: CSSRuleDef) =
  var hashes = SelectorHashes()
  for cxsel in rule.sels:
    hashes.getSelectorIds(cxsel)
    if hashes.tag != CAtomNull:
      sheet.tagTable.withValue(hashes.tag, p):
        p[].add(rule)
      do:
        sheet.tagTable[hashes.tag] = @[rule]
    elif hashes.id != CAtomNull:
      sheet.idTable.withValue(hashes.id, p):
        p[].add(rule)
      do:
        sheet.idTable[hashes.id] = @[rule]
    elif hashes.class != CAtomNull:
      sheet.classTable.withValue(hashes.class, p):
        p[].add(rule)
      do:
        sheet.classTable[hashes.class] = @[rule]
    else:
      sheet.generalList.add(rule)

proc add*(sheet, sheet2: CSSStylesheet) =
  sheet.generalList.add(sheet2.generalList)
  for key, value in sheet2.tagTable.pairs:
    sheet.tagTable.withValue(key, p):
      p[].add(value)
    do:
      sheet.tagTable[key] = value
  for key, value in sheet2.idTable.pairs:
    sheet.idTable.withValue(key, p):
      p[].add(value)
    do:
      sheet.idTable[key] = value
  for key, value in sheet2.classTable.pairs:
    sheet.classTable.withValue(key, p):
      p[].add(value)
    do:
      sheet.classTable[key] = value
  for key, value in sheet2.attrTable.pairs:
    sheet.attrTable.withValue(key, p):
      p[].add(value)
    do:
      sheet.attrTable[key] = value

proc addRule(stylesheet: CSSStylesheet; rule: CSSQualifiedRule) =
  let sels = parseSelectors(rule.prelude, stylesheet.factory)
  if sels.len > 0:
    var normalVals: seq[CSSComputedEntry] = @[]
    var importantVals: seq[CSSComputedEntry] = @[]
    let decls = rule.oblock.value.parseDeclarations2()
    for decl in decls:
      let vals = parseComputedValues(decl.name, decl.value)
      if decl.important:
        importantVals.add(vals)
      else:
        normalVals.add(vals)
    stylesheet.add(CSSRuleDef(
      sels: sels,
      normalVals: normalVals,
      importantVals: importantVals,
      idx: stylesheet.len
    ))
    inc stylesheet.len

proc addAtRule(stylesheet: CSSStylesheet; atrule: CSSAtRule; base: URL) =
  if atrule.name.equalsIgnoreCase("import"):
    if stylesheet.len == 0 and base != nil:
      var i = 0
      atrule.prelude.skipWhitespace(i)
      # Warning: this is a tracking vector minefield. If you implement
      # media query based imports, make sure to not filter here, but in
      # DOM after the sheet has been downloaded. (e.g. importList can
      # get a "media" field, etc.)
      if i < atrule.prelude.len:
        if (let url = cssURL(atrule.prelude[i]); url.isSome):
          if (let url = parseURL(url.get, some(base)); url.isSome):
            inc i
            atrule.prelude.skipWhitespace(i)
            # check if there are really no media queries/layers/etc
            if i == atrule.prelude.len:
              stylesheet.importList.add(url.get)
  elif atrule.name.equalsIgnoreCase("media"):
    if atrule.oblock != nil:
      let query = parseMediaQueryList(atrule.prelude)
      let rules = atrule.oblock.value.parseListOfRules()
      if rules.len > 0:
        var media = CSSMediaQueryDef()
        media.children = newStylesheet(rules.len, stylesheet.factory)
        media.children.len = stylesheet.len
        media.query = query
        for rule in rules:
          if rule of CSSAtRule:
            media.children.addAtRule(CSSAtRule(rule), nil)
          else:
            media.children.addRule(CSSQualifiedRule(rule))
        stylesheet.mqList.add(media)
        stylesheet.len = media.children.len

proc parseStylesheet*(ibuf: string; factory: CAtomFactory; base: URL):
    CSSStylesheet =
  let raw = parseStylesheet(ibuf)
  let sheet = newStylesheet(raw.value.len, factory)
  for i, v in raw.value.mypairs:
    if v of CSSAtRule:
      sheet.addAtRule(CSSAtRule(v), base)
    else:
      sheet.addRule(CSSQualifiedRule(v))
  return sheet
