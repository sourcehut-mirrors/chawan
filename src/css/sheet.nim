import std/options
import std/strutils
import std/tables

import chame/tags
import css/cssparser
import css/cssvalues
import css/mediaquery
import css/selectorparser
import html/catom
import types/opt
import types/url
import types/winattrs
import utils/twtstr

type
  CSSRuleBase* = ref object of RootObj

  CSSRuleDef* = ref object of CSSRuleBase
    sels*: SelectorList
    specificity*: int
    normalVals*: seq[CSSComputedEntry]
    importantVals*: seq[CSSComputedEntry]
    normalVars*: seq[CSSVariable]
    importantVars*: seq[CSSVariable]
    # Absolute position in the stylesheet; used for sorting rules after
    # retrieval from the cache.
    idx*: int

  CSSMediaQueryDef* = ref object of CSSRuleBase
    children*: CSSStylesheet
    query*: seq[MediaQuery]

  CSSStylesheet* = ref object
    mqList*: seq[CSSMediaQueryDef]
    tagTable*: Table[CAtom, seq[CSSRuleDef]]
    idTable*: Table[CAtom, seq[CSSRuleDef]]
    classTable*: Table[CAtom, seq[CSSRuleDef]]
    attrTable*: Table[CAtom, seq[CSSRuleDef]]
    rootList*: seq[CSSRuleDef]
    generalList*: seq[CSSRuleDef]
    importList*: seq[URL]
    len: int
    attrs: ptr WindowAttributes

type SelectorHashes = object
  tags: seq[CAtom]
  id: CAtom
  class: CAtom
  attr: CAtom
  root: bool

func newStylesheet*(cap: int; attrs: ptr WindowAttributes): CSSStylesheet =
  let bucketsize = cap div 2
  return CSSStylesheet(
    tagTable: initTable[CAtom, seq[CSSRuleDef]](bucketsize),
    idTable: initTable[CAtom, seq[CSSRuleDef]](bucketsize),
    classTable: initTable[CAtom, seq[CSSRuleDef]](bucketsize),
    attrTable: initTable[CAtom, seq[CSSRuleDef]](bucketsize),
    generalList: newSeqOfCap[CSSRuleDef](bucketsize),
    attrs: attrs
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
    hashes.tags.add(sel.tag)
    return true
  of stClass:
    hashes.class = sel.class
    return true
  of stId:
    hashes.id = sel.id
    return true
  of stAttr:
    hashes.attr = sel.attr
    return true
  of stPseudoElement, stUniversal:
    return false
  of stPseudoClass:
    case sel.pseudo.t
    of pcRoot:
      hashes.root = true
      return true
    of pcLink, pcVisited:
      hashes.tags.add(TAG_A.toAtom())
      hashes.tags.add(TAG_AREA.toAtom())
      hashes.attr = satHref.toAtom()
      return true
    of pcIs, pcWhere:
      # Hash whatever the selectors have in common:
      # 1. get the hashable values of selector 1
      # 2. for each other selector x:
      # 3.   get hashable values of selector x
      # 4.   store hashable values of selector x that aren't stored yet
      # 5.   for each hashable value of selector 1 that doesn't match selector x
      # 6.     cancel hashable value
      var cancelId = false
      var cancelClass = false
      var cancelAttr = false
      var cancelRoot = false
      var i = 0
      if i < sel.pseudo.fsels.len:
        hashes.getSelectorIds(sel.pseudo.fsels[i])
        inc i
      while i < sel.pseudo.fsels.len:
        var nhashes = SelectorHashes()
        nhashes.getSelectorIds(sel.pseudo.fsels[i])
        hashes.tags.add(nhashes.tags)
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
        if hashes.root != nhashes.root:
          cancelRoot = true
        inc i
      if cancelId:
        hashes.id = CAtomNull
      if cancelClass:
        hashes.class = CAtomNull
      if cancelAttr:
        hashes.attr = CAtomNull
      if cancelRoot:
        hashes.root = false
      return hashes.tags.len > 0 or hashes.id != CAtomNull or
        hashes.class != CAtomNull or hashes.attr != CAtomNull or
        hashes.root
    else:
      return false

proc add(sheet: CSSStylesheet; rule: CSSRuleDef) =
  for cxsel in rule.sels:
    var hashes = SelectorHashes()
    hashes.getSelectorIds(cxsel)
    if hashes.tags.len > 0:
      for tag in hashes.tags:
        sheet.tagTable.withValue(tag, p):
          if p[][^1] != rule:
            p[].add(rule)
        do:
          sheet.tagTable[tag] = @[rule]
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
    elif hashes.attr != CAtomNull:
      sheet.attrTable.withValue(hashes.attr, p):
        p[].add(rule)
      do:
        sheet.attrTable[hashes.attr] = @[rule]
    elif hashes.root:
      sheet.rootList.add(rule)
    else:
      sheet.generalList.add(rule)

proc add*(sheet, sheet2: CSSStylesheet) =
  sheet.generalList.add(sheet2.generalList)
  sheet.rootList.add(sheet2.rootList)
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

proc addRule(sheet: CSSStylesheet; rule: CSSQualifiedRule) =
  var sels = parseSelectors(rule.prelude)
  if sels.len > 0:
    let ruleDef = CSSRuleDef(sels: move(sels), idx: sheet.len)
    for decl in rule.decls:
      if decl.name.startsWith("--"):
        let cvar = CSSVariable(
          name: decl.name.substr(2).toAtom(),
          cvals: decl.value
        )
        if decl.important:
          ruleDef.importantVars.add(cvar)
        else:
          ruleDef.normalVars.add(cvar)
      else:
        if decl.important:
          let olen = ruleDef.importantVals.len
          if ruleDef.importantVals.parseComputedValues(decl.name, decl.value,
              sheet.attrs[]).isNone:
            ruleDef.importantVals.setLen(olen)
        else:
          let olen = ruleDef.normalVals.len
          if ruleDef.normalVals.parseComputedValues(decl.name, decl.value,
              sheet.attrs[]).isNone:
            ruleDef.normalVals.setLen(olen)
    sheet.add(ruleDef)
    inc sheet.len

proc addAtRule(sheet: CSSStylesheet; atrule: CSSAtRule; base: URL) =
  if atrule.name.equalsIgnoreCase("import"):
    if sheet.len == 0 and base != nil:
      var i = atrule.prelude.skipBlanks(0)
      # Warning: this is a tracking vector minefield. If you implement
      # media query based imports, make sure to not filter here, but in
      # DOM after the sheet has been downloaded. (e.g. importList can
      # get a "media" field, etc.)
      if i < atrule.prelude.len:
        if (let url = cssURL(atrule.prelude[i]); url.isSome):
          if (let url = parseURL(url.get, some(base)); url.isSome):
            i = atrule.prelude.skipBlanks(i + 1)
            # check if there are really no media queries/layers/etc
            if i == atrule.prelude.len:
              sheet.importList.add(url.get)
  elif atrule.name.equalsIgnoreCase("media"):
    if atrule.oblock != nil:
      let query = parseMediaQueryList(atrule.prelude, sheet.attrs)
      let rules = atrule.oblock.value.parseListOfRules(topLevel = false)
      if rules.len > 0:
        var media = CSSMediaQueryDef()
        media.children = newStylesheet(rules.len, sheet.attrs)
        media.children.len = sheet.len
        media.query = query
        for rule in rules:
          if rule of CSSAtRule:
            media.children.addAtRule(CSSAtRule(rule), nil)
          else:
            media.children.addRule(CSSQualifiedRule(rule))
        sheet.mqList.add(media)
        sheet.len = media.children.len

proc parseStylesheet*(ibuf: string; base: URL; attrs: ptr WindowAttributes):
    CSSStylesheet =
  let rules = parseListOfRules(ibuf, topLevel = true)
  let sheet = newStylesheet(rules.len, attrs)
  for v in rules:
    if v of CSSAtRule:
      sheet.addAtRule(CSSAtRule(v), base)
    else:
      sheet.addRule(CSSQualifiedRule(v))
  return sheet
