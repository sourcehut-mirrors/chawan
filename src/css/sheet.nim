{.push raises: [].}

import std/tables

import chame/tags
import css/cssparser
import css/cssvalues
import css/mediaquery
import html/catom
import html/script
import types/opt
import types/url

type
  CSSRuleDef* = ref object
    sels*: SelectorList
    vals*: array[CSSImportantFlag, seq[CSSComputedEntry]]
    vars*: array[CSSImportantFlag, seq[CSSVariable]]
    # Absolute position in the stylesheet; used for sorting rules after
    # retrieval from the cache.
    # Top 32 bits: sheet id; bottom 32 bits: rule id.
    idx*: uint64
    origin*: CSSOrigin
    layerId*: uint16
    layer*: CAtom
    next: CSSRuleDef

  CSSImport* = object
    url*: URL
    layer*: CAtom

  StyleState = object
    importList*: seq[CSSImport]
    layers: seq[CAtom]
    defsHead: CSSRuleDef
    defsTail: CSSRuleDef
    len: uint32
    idx: uint32
    anonLayerCount: uint16

  CSSStylesheet* = ref object
    s*: StyleState
    settings: ptr EnvironmentSettings
    next*: CSSStylesheet
    media*: string # media attr
    toks: seq[CSSToken]
    baseLayer: CAtom
    origin: CSSOrigin
    disabled*: bool # whether or not we have disabled attr etc.
    applies*: bool # whether or not media attr/import applies

  CSSRuleMap* = ref object
    tagTable*: Table[CAtom, seq[CSSRuleDef]]
    idTable*: Table[CAtom, seq[CSSRuleDef]]
    classTable*: Table[CAtom, seq[CSSRuleDef]]
    attrTable*: Table[CAtom, seq[CSSRuleDef]]
    rootList*: seq[CSSRuleDef]
    generalList*: seq[CSSRuleDef]
    hintList*: seq[CSSRuleDef]
    sheetId: uint32
    layers: seq[CAtom]
    anonLayers: uint16

  SelectorHashType = enum
    shtGeneral, shtRoot, shtHint

  SelectorHashes = object
    tags: seq[CAtom]
    id: CAtom
    class: CAtom
    attr: CAtom
    t: SelectorHashType

# Forward declarations
proc getSelectorIds(hashes: var SelectorHashes; sel: Selector): bool
proc addRule(sheet: CSSStylesheet; rule: CSSQualifiedRule; layer: CAtom)
proc addAtRule(sheet: CSSStylesheet; atrule: CSSAtRule; base: URL;
  layer: CAtom): Opt[void]

proc getSelectorIds(hashes: var SelectorHashes; sels: CompoundSelector) =
  for sel in sels:
    if hashes.getSelectorIds(sel):
      break

proc getSelectorIds(hashes: var SelectorHashes; cxsel: ComplexSelector) =
  if cxsel.pseudo == peLinkHint:
    hashes.t = shtHint
  else:
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
  of stIs, stWhere:
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
    var cancelT = false
    var i = 0
    if i < sel.fsels.len:
      hashes.getSelectorIds(sel.fsels[i])
      inc i
    while i < sel.fsels.len:
      var nhashes = SelectorHashes()
      nhashes.getSelectorIds(sel.fsels[i])
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
      if hashes.t != nhashes.t:
        cancelT = true
      inc i
    if cancelId:
      hashes.id = CAtomNull
    if cancelClass:
      hashes.class = CAtomNull
    if cancelAttr:
      hashes.attr = CAtomNull
    if cancelT:
      hashes.t = shtGeneral
    return hashes.tags.len > 0 or hashes.id != CAtomNull or
      hashes.class != CAtomNull or hashes.attr != CAtomNull or
      hashes.t != shtGeneral
  of stPseudoClass:
    case sel.pc
    of pcRoot:
      hashes.t = shtRoot
      return true
    of pcLink, pcVisited:
      hashes.tags.add(TAG_A.toAtom())
      hashes.tags.add(TAG_AREA.toAtom())
      hashes.attr = satHref.toAtom()
      return true
    else:
      return false
  of stUniversal, stNot, stLang, stNthChild, stNthLastChild, stHost:
    return false

proc addIfNotLast(s: var seq[CSSRuleDef]; rule: CSSRuleDef) =
  if s.len == 0 or s[^1] != rule:
    s.add(rule)

proc add(sheet: CSSRuleMap; rule: CSSRuleDef) =
  for cxsel in rule.sels:
    var hashes = SelectorHashes()
    hashes.getSelectorIds(cxsel)
    if hashes.id != CAtomNull:
      sheet.idTable.mgetOrPut(hashes.id, @[]).add(rule)
    elif hashes.tags.len > 0:
      for tag in hashes.tags:
        sheet.tagTable.mgetOrPut(tag, @[]).addIfNotLast(rule)
    elif hashes.class != CAtomNull:
      sheet.classTable.mgetOrPut(hashes.class, @[]).add(rule)
    elif hashes.attr != CAtomNull:
      sheet.attrTable.mgetOrPut(hashes.attr, @[]).add(rule)
    else:
      case hashes.t
      of shtRoot: sheet.rootList.add(rule)
      of shtHint: sheet.hintList.add(rule)
      of shtGeneral: sheet.generalList.add(rule)

proc add*(map: CSSRuleMap; sheet: CSSStylesheet) =
  let sheetId = map.sheetId
  sheet.s.idx = sheetId
  inc map.sheetId
  # We don't have to dedupe, it won't make linear search much faster and
  # layer switches happen rarely enough anyway.
  map.layers.add(sheet.s.layers)
  var def = sheet.s.defsHead
  var prevLayer = CAtomNull
  var layerId = 0u16
  let sheetIdShifted = (uint64(sheetId) shl 32)
  while def != nil:
    def.idx = sheetIdShifted or uint32(def.idx)
    let layer = def.layer
    if layer != CAtomNull:
      if layer != prevLayer:
        if ($layer)[0] == '!':
          layerId = 20000 + map.anonLayers # ought to be enough for everyone
          inc map.anonLayers
        else:
          layerId = uint16(map.layers.find(layer)) + 1
        prevLayer = layer
      def.layerId = layerId
    map.add(def)
    def = def.next

proc addRules(sheet: CSSStylesheet; ctx: var CSSParser; topLevel: bool;
    base: URL; layer: CAtom) =
  for rule in ctx.parseListOfRules(topLevel):
    case rule.t
    of crtAt: discard sheet.addAtRule(rule.at, base, layer)
    of crtQualified: sheet.addRule(rule.qualified, layer)

proc addRule(sheet: CSSStylesheet; rule: CSSQualifiedRule; layer: CAtom) =
  if rule.sels.len > 0:
    let ruleDef = CSSRuleDef(
      sels: move(rule.sels),
      idx: sheet.s.len,
      origin: sheet.origin,
      layer: layer
    )
    for decl in rule.decls:
      let f = decl.f
      case decl.t
      of cdtVariable:
        ruleDef.vars[f].add(CSSVariable(
          name: decl.v,
          items: parseDeclWithVar0(decl.value)
        ))
      of cdtProperty:
        if decl.hasVar:
          if entry := parseDeclWithVar(decl.p, decl.value):
            ruleDef.vals[f].add(entry)
        else:
          ruleDef.vals[f].parseComputedValues(decl.p, decl.value,
            sheet.settings.attrsp[])
    if sheet.s.defsTail == nil:
      sheet.s.defsHead = ruleDef
    else:
      sheet.s.defsTail.next = ruleDef
    sheet.s.defsTail = ruleDef
    inc sheet.s.len

proc nextAnonLayer(sheet: CSSStylesheet): CAtom =
  let res = sheet.s.anonLayerCount
  inc sheet.s.anonLayerCount
  ('!' & $res).toAtom()

proc consumeLayerName(ctx: var CSSParser; parent: CAtom; anon: var bool):
    Opt[CAtom] =
  var name = ""
  if parent != CAtomNull:
    name &= $parent & '.'
  while ctx.has():
    case ctx.peekTokenType()
    of cttIdent:
      name &= ctx.consume().s
    of cttDot:
      if name.len <= 0 or name[^1] == '.':
        return err()
      name &= '.'
      ctx.seekToken()
    else:
      break
  if name.len <= 0 or name[^1] == '.':
    return err()
  anon = name[0] == '!'
  ok(name.toAtom())

proc parseImportLayer(ctx: var CSSParser; sheet: CSSStylesheet;
    oldLayer: CAtom): Opt[CAtom] =
  if ctx.skipBlanksCheckHas().isErr:
    return ok(oldLayer)
  if ctx.peekFunction(cftLayer):
    ctx.seekToken()
    if ctx.skipBlanksCheckDone().isOk:
      return ok(sheet.nextAnonLayer())
    var anon: bool
    let layer = ?ctx.consumeLayerName(oldLayer, anon)
    ?ctx.checkFunctionEnd()
    return ok(layer)
  if ctx.peekIdentNoCase("layer"):
    ctx.seekToken()
    return ok(sheet.nextAnonLayer())
  ok(oldLayer)

proc addAtRule(sheet: CSSStylesheet; atrule: CSSAtRule; base: URL;
    layer: CAtom): Opt[void] =
  case atrule.name
  of cartUnknown: discard
  of cartImport:
    if sheet.s.len == 0 and base != nil:
      var ctx = initCSSParser(atrule.prelude)
      ?ctx.skipBlanksCheckHas()
      let tok = ctx.consume()
      let urls = ?ctx.parseURL(tok)
      let url = ?parseURL(urls, base)
      let layer = ?ctx.parseImportLayer(sheet, layer)
      #TODO media queries
      # Warning: this is a tracking vector minefield.  If you implement
      # media query based imports, make sure to not filter here, but in
      # DOM after the sheet has been downloaded.  (e.g. importList can
      # get a "media" field, etc.)
      ?ctx.skipBlanksCheckDone()
      sheet.s.importList.add(CSSImport(url: url, layer: layer))
  of cartMedia:
    var ctx = initCSSParser(atrule.prelude)
    let query = ctx.parseMediaQueryList(sheet.settings.attrsp)
    if query.applies(sheet.settings):
      var ctx = initCSSParser(atrule.oblock)
      sheet.addRules(ctx, topLevel = false, base = nil, layer)
  of cartLayer:
    var ctx = initCSSParser(atrule.prelude)
    if atrule.hasBlock:
      let name = if ctx.skipBlanksCheckHas().isOk:
        var anon: bool
        let name = ?ctx.consumeLayerName(layer, anon)
        ?ctx.skipBlanksCheckDone()
        if anon:
          sheet.s.layers.add(name) # note: we intentionally don't dedupe
        name
      else:
        sheet.nextAnonLayer()
      var ctx = initCSSParser(atrule.oblock)
      sheet.addRules(ctx, topLevel = false, base = nil, name)
    else:
      var names: seq[CAtom] = @[]
      while ctx.skipBlanksCheckHas().isOk:
        var anon: bool
        let name = ?ctx.consumeLayerName(layer, anon)
        if ctx.skipBlanksCheckHas().isErr:
          break
        if ctx.consume().t != cttComma:
          return err()
        names.add(name)
      sheet.s.layers.add(names)
  ok()

proc parseStylesheet*(iq: string; base: URL; settings: ptr EnvironmentSettings;
    origin: CSSOrigin; layer: CAtom): CSSStylesheet =
  var ctx = initCSSParser(iq)
  let sheet = CSSStylesheet(
    settings: settings,
    origin: origin,
    baseLayer: layer,
    applies: true
  )
  sheet.addRules(ctx, topLevel = true, base, layer)
  sheet.toks = move(ctx.toks)
  return sheet

proc windowChange*(sheet: CSSStylesheet; base: URL) =
  var ctx = initCSSParserSink(sheet.toks)
  sheet.s = StyleState()
  sheet.addRules(ctx, topLevel = true, base, sheet.baseLayer)
  sheet.toks = move(ctx.toks)

{.pop.} # raises: []
