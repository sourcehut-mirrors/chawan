import std/options
import std/strutils

import css/cssparser
import html/catom
import utils/twtstr

type
  SelectorType* = enum
    stType, stId, stAttr, stClass, stUniversal, stPseudoClass, stPseudoElement

  PseudoElement* = enum
    peNone = "-cha-none"
    peBefore = "before"
    peAfter = "after"

  PseudoClass* = enum
    pcFirstChild = "first-child"
    pcLastChild = "last-child"
    pcOnlyChild = "only-child"
    pcHover = "hover"
    pcRoot = "root"
    pcNthChild = "nth-child"
    pcNthLastChild = "nth-last-child"
    pcChecked = "checked"
    pcFocus = "focus"
    pcIs = "is"
    pcNot = "not"
    pcWhere = "where"
    pcLang = "lang"
    pcLink = "link"
    pcVisited = "visited"
    pcTarget = "target"
    pcFirstNode = "-cha-first-node"
    pcLastNode = "-cha-last-node"

  CombinatorType* = enum
    ctNone, ctDescendant, ctChild, ctNextSibling, ctSubsequentSibling

  SelectorParser = object
    selectors: seq[ComplexSelector]
    cvals: seq[CSSComponentValue]
    at: int
    failed: bool
    nested: bool

  RelationType* = enum
    rtExists, rtEquals, rtToken, rtBeginDash, rtStartsWith, rtEndsWith,
    rtContains

  RelationFlag* = enum
    rfNone, rfI, rfS

  SelectorRelation* = object
    t*: RelationType
    flag*: RelationFlag

  Selector* = ref object # Simple selector
    case t*: SelectorType
    of stType:
      tag*: CAtom
      when defined(debug):
        tags: string
    of stId:
      id*: CAtom
      when defined(debug):
        ids: string
    of stClass:
      class*: CAtom
      when defined(debug):
        classs: string
    of stAttr:
      attr*: CAtom
      rel*: SelectorRelation
      when defined(debug):
        attrs: string
      value*: string
    of stUniversal: #TODO namespaces?
      discard
    of stPseudoClass:
      pseudo*: PseudoData
    of stPseudoElement:
      elem*: PseudoElement

  PseudoData* = object
    case t*: PseudoClass
    of pcNthChild, pcNthLastChild:
      anb*: CSSAnB
      ofsels*: SelectorList
    of pcIs, pcWhere, pcNot:
      fsels*: SelectorList
    of pcLang:
      s*: string
    else: discard

  CompoundSelector* = object
    ct*: CombinatorType # relation to the next entry in a ComplexSelector.
    sels*: seq[Selector]

  ComplexSelector* = object
    specificity*: int
    pseudo*: PseudoElement
    csels: seq[CompoundSelector]

  SelectorList* = seq[ComplexSelector]

# Forward declarations
proc parseSelectorList(cvals: seq[CSSComponentValue]; nested, forgiving: bool):
  SelectorList
proc parseComplexSelector(state: var SelectorParser): ComplexSelector
func `$`*(cxsel: ComplexSelector): string

iterator items*(csel: CompoundSelector): lent Selector {.inline.} =
  for it in csel.sels:
    yield it

func `[]`*(csel: CompoundSelector; i: int): lent Selector {.inline.} =
  return csel.sels[i]

func `[]`*(csel: CompoundSelector; i: BackwardsIndex): lent Selector
    {.inline.} =
  return csel[csel.sels.len - int(i)]

func len*(csel: CompoundSelector): int {.inline.} =
  return csel.sels.len

proc add*(csel: var CompoundSelector; sel: sink Selector) {.inline.} =
  csel.sels.add(sel)

func `[]`*(cxsel: ComplexSelector; i: int): lent CompoundSelector {.inline.} =
  return cxsel.csels[i]

func `[]`*(cxsel: ComplexSelector; i: BackwardsIndex): lent CompoundSelector
    {.inline.} =
  return cxsel[cxsel.csels.len - int(i)]

func `[]`*(cxsel: var ComplexSelector; i: BackwardsIndex): var CompoundSelector
    {.inline.} =
  return cxsel.csels[i]

func len*(cxsel: ComplexSelector): int {.inline.} =
  return cxsel.csels.len

func high*(cxsel: ComplexSelector): int {.inline.} =
  return cxsel.csels.high

iterator items*(cxsel: ComplexSelector): lent CompoundSelector {.inline.} =
  for it in cxsel.csels:
    yield it

func `$`*(sel: Selector): string =
  case sel.t
  of stType:
    when defined(debug):
      return sel.tags
    else:
      return "ATOM" & $int(sel.tag)
  of stId:
    when defined(debug):
      return "#" & sel.ids
    else:
      return "#ATOM" & $int(sel.id)
  of stAttr:
    let rel = case sel.rel.t
    of rtExists: ""
    of rtEquals: "="
    of rtToken: "~="
    of rtBeginDash: "|="
    of rtStartsWith: "^="
    of rtEndsWith: "$="
    of rtContains: "*="
    let flag = case sel.rel.flag
    of rfNone: ""
    of rfI: " i"
    of rfS: " s"
    let attrs = when defined(debug):
      sel.attrs
    else:
      "ATOM" & $int(sel.attr)
    return '[' & attrs & rel & sel.value & flag & ']'
  of stClass:
    when defined(debug):
      return "." & sel.classs
    else:
      return ".ATOM" & $int(sel.id)
  of stUniversal:
    return "*"
  of stPseudoClass:
    result = ':' & $sel.pseudo.t
    case sel.pseudo.t
    of pcIs, pcNot, pcWhere:
      result &= '('
      for fsel in sel.pseudo.fsels:
        result &= $fsel
        if fsel != sel.pseudo.fsels[^1]:
          result &= ", "
      result &= ')'
    of pcNthChild, pcNthLastChild:
      result &= '(' & $sel.pseudo.anb.A & 'n' & $sel.pseudo.anb.B
      if sel.pseudo.ofsels.len != 0:
        result &= " of "
        for fsel in sel.pseudo.ofsels:
          result &= $fsel
          if fsel != sel.pseudo.ofsels[^1]:
            result &= ','
      result &= ')'
    else: discard
  of stPseudoElement:
    return "::" & $sel.elem

func `$`*(sels: CompoundSelector): string =
  result = ""
  for sel in sels:
    result &= $sel

func `$`*(cxsel: ComplexSelector): string =
  for sels in cxsel:
    result &= $sels
    case sels.ct
    of ctDescendant: result &= ' '
    of ctChild: result &= " > "
    of ctNextSibling: result &= " + "
    of ctSubsequentSibling: result &= " ~ "
    of ctNone: discard

func `$`*(slist: SelectorList): string =
  var s = false
  for cxsel in slist:
    if s:
      result &= ", "
    result &= $cxsel
    s = true

func getSpecificity(sel: Selector): int =
  case sel.t
  of stId:
    result += 1000000
  of stClass, stAttr:
    result += 1000
  of stPseudoClass:
    case sel.pseudo.t
    of pcIs, pcNot:
      var best = 0
      for child in sel.pseudo.fsels:
        let s = child.specificity
        if s > best:
          best = s
      result += best
    of pcNthChild, pcNthLastChild:
      if sel.pseudo.ofsels.len != 0:
        var best = 0
        for child in sel.pseudo.ofsels:
          let s = child.specificity
          if s > best:
            best = s
        result += best
      result += 1000
    of pcWhere: discard
    else: result += 1000
  of stType, stPseudoElement:
    result += 1
  of stUniversal:
    discard

func getSpecificity(sels: CompoundSelector): int =
  result= 0
  for sel in sels:
    result += getSpecificity(sel)

proc consume(state: var SelectorParser): CSSComponentValue =
  result = state.cvals[state.at]
  inc state.at

proc has(state: var SelectorParser; i = 0): bool =
  return not state.failed and state.at + i < state.cvals.len

proc peek(state: var SelectorParser; i = 0): CSSComponentValue =
  return state.cvals[state.at + i]

template fail() =
  state.failed = true
  return

template get_tok(cval: CSSComponentValue): CSSToken =
  let c = cval
  if not (c of CSSToken): fail
  CSSToken(c)

# Functions that may contain other selectors, functions, etc.
proc parseRecursiveSelectorFunction(state: var SelectorParser;
    class: PseudoClass; body: seq[CSSComponentValue]; forgiving: bool):
    Selector =
  var fun = Selector(
    t: stPseudoClass,
    pseudo: PseudoData(t: class),
  )
  fun.pseudo.fsels = parseSelectorList(body, nested = true, forgiving)
  if fun.pseudo.fsels.len == 0: fail
  return fun

proc parseNthChild(state: var SelectorParser; cssfunction: CSSFunction;
    data: PseudoData): Selector =
  var data = data
  var (anb, i) = parseAnB(cssfunction.value)
  if anb.isNone: fail
  data.anb = anb.get
  var nthchild = Selector(t: stPseudoClass, pseudo: data)
  while i < cssfunction.value.len and cssfunction.value[i] == cttWhitespace:
    inc i
  if i >= cssfunction.value.len:
    return nthchild
  let lasttok = get_tok cssfunction.value[i]
  if lasttok.t != cttIdent or not lasttok.value.equalsIgnoreCase("of"):
    fail
  inc i
  while i < cssfunction.value.len and cssfunction.value[i] == cttWhitespace:
    inc i
  if i == cssfunction.value.len: fail
  nthchild.pseudo.ofsels = cssfunction.value[i..^1]
    .parseSelectorList(nested = true, forgiving = false)
  if nthchild.pseudo.ofsels.len == 0: fail
  return nthchild

proc skipWhitespace(state: var SelectorParser) =
  while state.has() and state.peek() of CSSToken and
      CSSToken(state.peek()).t == cttWhitespace:
    inc state.at

proc parseLang(cvals: seq[CSSComponentValue]): Selector =
  var state = SelectorParser(cvals: cvals)
  state.skipWhitespace()
  if not state.has(): fail
  let tok = get_tok state.consume()
  if tok.t != cttIdent: fail
  return Selector(t: stPseudoClass, pseudo: PseudoData(t: pcLang, s: tok.value))

proc parseSelectorFunction(state: var SelectorParser; cssfunction: CSSFunction):
    Selector =
  return case cssfunction.name
  of cftNot:
    state.parseRecursiveSelectorFunction(pcNot, cssfunction.value,
      forgiving = false)
  of cftIs:
    state.parseRecursiveSelectorFunction(pcIs, cssfunction.value,
      forgiving = true)
  of cftWhere:
    state.parseRecursiveSelectorFunction(pcWhere, cssfunction.value,
      forgiving = true)
  of cftNthChild:
    state.parseNthChild(cssfunction, PseudoData(t: pcNthChild))
  of cftNthLastChild:
    state.parseNthChild(cssfunction, PseudoData(t: pcNthLastChild))
  of cftLang:
    parseLang(cssfunction.value)
  else: fail

proc parsePseudoSelector(state: var SelectorParser): Selector =
  if not state.has(): fail
  let cval = state.consume()
  if cval of CSSToken:
    template add_pseudo_element(element: PseudoElement) =
      state.skipWhitespace()
      if state.nested or state.has() and state.peek() != cttComma: fail
      return Selector(t: stPseudoElement, elem: element)
    let tok = CSSToken(cval)
    case tok.t
    of cttIdent:
      template add_pseudo_class(class: PseudoClass) =
        return Selector(t: stPseudoClass, pseudo: PseudoData(t: class))
      case tok.value.toLowerAscii()
      of "before": add_pseudo_element peBefore
      of "after": add_pseudo_element peAfter
      of "first-child": add_pseudo_class pcFirstChild
      of "last-child": add_pseudo_class pcLastChild
      of "only-child": add_pseudo_class pcOnlyChild
      of "hover": add_pseudo_class pcHover
      of "root": add_pseudo_class pcRoot
      of "checked": add_pseudo_class pcChecked
      of "focus": add_pseudo_class pcFocus
      of "link": add_pseudo_class pcLink
      of "visited": add_pseudo_class pcVisited
      of "target": add_pseudo_class pcTarget
      of "-cha-first-node": add_pseudo_class pcFirstNode
      of "-cha-last-node": add_pseudo_class pcLastNode
      else: fail
    of cttColon:
      if not state.has(): fail
      let tok = get_tok state.consume()
      if tok.t != cttIdent: fail
      case tok.value.toLowerAscii()
      of "before": add_pseudo_element peBefore
      of "after": add_pseudo_element peAfter
      else: fail
    else: fail
  elif cval of CSSFunction:
    return state.parseSelectorFunction(CSSFunction(cval))
  else: fail

proc parseAttributeSelector(state: var SelectorParser;
    cssblock: CSSSimpleBlock): Selector =
  if cssblock.token.t != cttLbracket: fail
  var state2 = SelectorParser(cvals: cssblock.value)
  state2.skipWhitespace()
  if not state2.has(): fail
  let attr = get_tok state2.consume()
  if attr.t != cttIdent: fail
  state2.skipWhitespace()
  if not state2.has():
    return Selector(
      t: stAttr,
      attr: attr.value.toAtomLower(),
      rel: SelectorRelation(t: rtExists)
    )
  let delim = get_tok state2.consume()
  if delim.t != cttDelim: fail
  let rel = case delim.cvalue
  of '~': rtToken
  of '|': rtBeginDash
  of '^': rtStartsWith
  of '$': rtEndsWith
  of '*': rtContains
  of '=': rtEquals
  else: fail
  if rel != rtEquals:
    let delim = get_tok state2.consume()
    if delim.t != cttDelim or delim.cvalue != '=': fail
  state2.skipWhitespace()
  if not state2.has(): fail
  let value = get_tok state2.consume()
  if value.t notin {cttIdent, cttString}: fail
  state2.skipWhitespace()
  var flag = rfNone
  if state2.has():
    let delim = get_tok state2.consume()
    if delim.t != cttIdent: fail
    if delim.value.equalsIgnoreCase("i"):
      flag = rfI
    elif delim.value.equalsIgnoreCase("s"):
      flag = rfS
  return Selector(
    t: stAttr,
    attr: attr.value.toAtomLower(),
    value: value.value,
    rel: SelectorRelation(t: rel, flag: flag)
  )

proc parseClassSelector(state: var SelectorParser): Selector =
  if not state.has(): fail
  let tok = get_tok state.consume()
  if tok.t != cttIdent: fail
  let class = tok.value.toAtomLower()
  result = Selector(t: stClass, class: class)
  when defined(debug):
    result.classs = tok.value

proc parseCompoundSelector(state: var SelectorParser): CompoundSelector =
  result = CompoundSelector()
  while state.has():
    let cval = state.peek()
    if cval of CSSToken:
      let tok = CSSToken(cval)
      case tok.t
      of cttIdent:
        inc state.at
        let tag = tok.value.toAtomLower()
        let sel = Selector(t: stType, tag: tag)
        when defined(debug):
          sel.tags = tok.value
        result.add(sel)
      of cttColon:
        inc state.at
        result.add(state.parsePseudoSelector())
      of cttHash:
        inc state.at
        let id = tok.value.toAtomLower()
        result.add(Selector(t: stId, id: id))
        when defined(debug):
          result[^1].ids = tok.value
      of cttComma: break
      of cttDelim:
        case tok.cvalue
        of '.':
          inc state.at
          result.add(state.parseClassSelector())
        of '*':
          inc state.at
          result.add(Selector(t: stUniversal))
        of '>', '+', '~': break
        else: fail
      of cttWhitespace:
        # skip trailing whitespace
        if not state.has(1) or state.peek(1) == cttComma:
          inc state.at
        elif state.peek(1) == cttDelim:
          let tok = CSSToken(state.peek(1))
          if tok.cvalue in {'>', '+', '~'}:
            inc state.at
        break
      else: fail
    elif cval of CSSSimpleBlock:
      inc state.at
      result.add(state.parseAttributeSelector(CSSSimpleBlock(cval)))
    else:
      fail

proc parseComplexSelector(state: var SelectorParser): ComplexSelector =
  result = ComplexSelector()
  while true:
    state.skipWhitespace()
    let sels = state.parseCompoundSelector()
    if state.failed:
      break
    #TODO propagate from parser
    result.specificity += sels.getSpecificity()
    result.csels.add(sels)
    if sels.len == 0: fail
    if not state.has():
      break # finish
    let tok = get_tok state.consume()
    case tok.t
    of cttDelim:
      case tok.cvalue
      of '>': result[^1].ct = ctChild
      of '+': result[^1].ct = ctNextSibling
      of '~': result[^1].ct = ctSubsequentSibling
      else: fail
    of cttWhitespace:
      result[^1].ct = ctDescendant
    of cttComma:
      break # finish
    else: fail
  if result.len == 0 or result[^1].ct != ctNone:
    fail
  if result[^1][^1].t == stPseudoElement:
    #TODO move pseudo check here?
    result.pseudo = result[^1][^1].elem

proc parseSelectorList(cvals: seq[CSSComponentValue]; nested, forgiving: bool):
    SelectorList =
  var state = SelectorParser(
    cvals: cvals,
    nested: nested
  )
  var res: SelectorList = @[]
  while state.has():
    let csel = state.parseComplexSelector()
    if state.failed:
      if not forgiving:
        return @[]
      state.failed = false
      while state.has() and state.consume() != cttComma:
        discard
    else:
      res.add(csel)
  return res

proc parseSelectors*(cvals: seq[CSSComponentValue]): seq[ComplexSelector] =
  return parseSelectorList(cvals, nested = false, forgiving = false)

proc parseSelectors*(ibuf: string): seq[ComplexSelector] =
  return parseSelectors(parseComponentValues(ibuf))
