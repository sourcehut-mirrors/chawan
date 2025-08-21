{.push raises: [].}

import std/strutils

import chame/tags
import css/cssparser
import html/catom
import html/dom
import utils/twtstr

# We use three match types.
# "mtTrue" and "mtFalse" are self-explanatory.
# "mtContinue" is like "mtFalse", but also modifies "depends".  This
# "depends" change is only propagated at the end if no selector before
# the pseudo element matches the element, and the last match was
# "mtContinue".
#
# Since style is only recomputed (e.g. when the hovered element changes)
# for elements that are included in "depends", this has the effect of
# minimizing such recomputations to cases where it's really necessary.
type MatchType = enum
  mtFalse, mtTrue, mtContinue

converter toMatchType(b: bool): MatchType =
  return MatchType(b)

#TODO rfNone should match insensitively for certain properties
proc matchesAttr(element: Element; sel: Selector): bool =
  case sel.rel.t
  of rtExists: return element.attrb(sel.attr)
  of rtEquals:
    case sel.rel.flag
    of rfNone: return element.attr(sel.attr) == sel.value
    of rfI: return element.attr(sel.attr).equalsIgnoreCase(sel.value)
    of rfS: return element.attr(sel.attr) == sel.value
  of rtToken:
    let val = element.attr(sel.attr)
    case sel.rel.flag
    of rfNone: return sel.value in val.split(AsciiWhitespace)
    of rfI:
      let val = val.toLowerAscii()
      let selval = sel.value.toLowerAscii()
      return selval in val.split(AsciiWhitespace)
    of rfS: return sel.value in val.split(AsciiWhitespace)
  of rtBeginDash:
    let val = element.attr(sel.attr)
    case sel.rel.flag
    of rfNone:
      return val == sel.value or sel.value.startsWith(val & '-')
    of rfI:
      return val.equalsIgnoreCase(sel.value) or
        sel.value.startsWithIgnoreCase(val & '-')
    of rfS:
      return val == sel.value or sel.value.startsWith(val & '-')
  of rtStartsWith:
    let val = element.attr(sel.attr)
    case sel.rel.flag
    of rfNone: return val.startsWith(sel.value)
    of rfI: return val.startsWithIgnoreCase(sel.value)
    of rfS: return val.startsWith(sel.value)
  of rtEndsWith:
    let val = element.attr(sel.attr)
    case sel.rel.flag
    of rfNone: return val.endsWith(sel.value)
    of rfI: return val.endsWithIgnoreCase(sel.value)
    of rfS: return val.endsWith(sel.value)
  of rtContains:
    let val = element.attr(sel.attr)
    case sel.rel.flag
    of rfNone: return val.contains(sel.value)
    of rfI:
      let val = val.toLowerAscii()
      let selval = sel.value.toLowerAscii()
      return val.contains(selval)
    of rfS: return val.contains(sel.value)

proc matches*(element: Element; cxsel: ComplexSelector;
  depends: var DependencyInfo): bool

proc matches(element: Element; slist: SelectorList;
    depends: var DependencyInfo): bool =
  for cxsel in slist:
    if element.matches(cxsel, depends):
      return true
  return false

proc matches(element: Element; pc: PseudoClass; depends: var DependencyInfo):
    MatchType =
  case pc
  of pcFirstChild: return element.parentNode.firstElementChild == element
  of pcLastChild: return element.parentNode.lastElementChild == element
  of pcFirstNode: return element.isFirstVisualNode()
  of pcLastNode: return element.isLastVisualNode()
  of pcOnlyChild:
    return element.parentNode.firstElementChild == element and
      element.parentNode.lastElementChild == element
  of pcHover:
    depends.add(element, dtHover)
    if element.hover:
      return mtTrue
    return mtContinue
  of pcRoot: return element == element.document.documentElement
  of pcChecked:
    if element.tagType == TAG_INPUT:
      depends.add(element, dtChecked)
      if HTMLInputElement(element).checked:
        return mtTrue
    elif element.tagType == TAG_OPTION:
      depends.add(element, dtChecked)
      if HTMLOptionElement(element).selected:
        return mtTrue
    return mtContinue
  of pcFocus:
    depends.add(element, dtFocus)
    if element.document.focus == element:
      return mtTrue
    return mtContinue
  of pcTarget:
    depends.add(element, dtTarget)
    if element.document.target == element:
      return mtTrue
    return mtContinue
  of pcLink:
    return element.tagType in {TAG_A, TAG_AREA} and element.attrb(satHref)
  of pcVisited:
    return mtFalse

proc matchesLang(element: Element; lang: string): bool =
  for element in element.branchElems:
    if element.attrb(satLang):
      return element.attr(satLang) == lang
  true

proc matchesNthChild(element: Element; nthChild: CSSNthChild;
    depends: var DependencyInfo): bool =
  let A = nthChild.anb.A # step
  let B = nthChild.anb.B # start
  if nthChild.ofsels.len == 0:
    let i = element.elIndex + 1
    if A == 0:
      return i == B
    let j = (i - B)
    if A < 0:
      return j <= 0 and j mod A == 0
    return j >= 0 and j mod A == 0
  if element.matches(nthChild.ofsels, depends):
    var i = 1
    for child in element.parentNode.elementList:
      if child == element:
        if A == 0:
          return i == B
        let j = (i - B)
        if A < 0:
          return j <= 0 and j mod A == 0
        return j >= 0 and j mod A == 0
      if child.matches(nthChild.ofsels, depends):
        inc i
  false

proc matchesNthLastChild(element: Element; nthChild: CSSNthChild;
    depends: var DependencyInfo): bool =
  let A = nthChild.anb.A # step
  let B = nthChild.anb.B # start
  if nthChild.ofsels.len == 0:
    let last = element.parentNode.lastElementChild
    let i = last.elIndex + 1 - element.elIndex
    if A == 0:
      return i == B
    let j = (i - B)
    if A < 0:
      return j <= 0 and j mod A == 0
    return j >= 0 and j mod A == 0
  if element.matches(nthChild.ofsels, depends):
    var i = 1
    for child in element.parentNode.relementList:
      if child == element:
        if A == 0:
          return i == B
        let j = (i - B)
        if A < 0:
          return j <= 0 and j mod A == 0
        return j >= 0 and j mod A == 0
      if child.matches(nthChild.ofsels, depends):
        inc i
  false

proc matches(element: Element; sel: Selector; depends: var DependencyInfo):
    MatchType =
  case sel.t
  of stType:
    return element.localName == sel.tag
  of stClass:
    for it in element.classList:
      if sel.class == it.toLowerAscii():
        return mtTrue
    return mtFalse
  of stId:
    return sel.id == element.id.toLowerAscii()
  of stAttr:
    return element.matchesAttr(sel)
  of stPseudoClass:
    return element.matches(sel.pc, depends)
  of stPseudoElement:
    return mtTrue
  of stUniversal:
    return mtTrue
  of stNthChild:
    return element.matchesNthChild(sel.nthChild, depends)
  of stNthLastChild:
    return element.matchesNthLastChild(sel.nthChild, depends)
  of stNot:
    return not element.matches(sel.fsels, depends)
  of stIs, stWhere:
    return element.matches(sel.fsels, depends)
  of stLang:
    return element.matchesLang(sel.lang)

proc matches(element: Element; sels: CompoundSelector;
    depends: var DependencyInfo): MatchType =
  var res = mtTrue
  for sel in sels:
    case element.matches(sel, depends)
    of mtFalse: return mtFalse
    of mtTrue: discard
    of mtContinue: res = mtContinue
  return res

# Note: this modifies "depends".
proc matches*(element: Element; cxsel: ComplexSelector;
    depends: var DependencyInfo): bool =
  var e = element
  var pmatch = mtTrue
  var mdepends = DependencyInfo.default
  for csel in cxsel.ritems:
    var match = mtFalse
    case csel.ct
    of ctNone:
      match = e.matches(csel, mdepends)
    of ctDescendant:
      e = e.parentElement
      while e != nil:
        case e.matches(csel, mdepends)
        of mtFalse: discard
        of mtTrue:
          match = mtTrue
          break
        of mtContinue: match = mtContinue # keep looking
        e = e.parentElement
    of ctChild:
      e = e.parentElement
      if e != nil:
        match = e.matches(csel, mdepends)
    of ctNextSibling:
      let prev = e.previousElementSibling
      if prev != nil:
        e = prev
        match = e.matches(csel, mdepends)
    of ctSubsequentSibling:
      var it = element.previousElementSibling
      while it != nil:
        case it.matches(csel, mdepends)
        of mtTrue:
          e = it
          match = mtTrue
          break
        of mtFalse: discard
        of mtContinue: match = mtContinue # keep looking
        it = it.previousElementSibling
    if match == mtFalse:
      return false # we can discard depends.
    if pmatch == mtContinue and match == mtTrue or e == nil:
      pmatch = mtContinue
      break # we must update depends.
    pmatch = match
  depends.merge(mdepends)
  if pmatch == mtContinue:
    return false
  return true

# Forward declaration hack
matchesImpl = proc(element: Element; cxsels: seq[ComplexSelector]): bool
    {.nimcall.} =
  var dummy = DependencyInfo.default
  return element.matches(cxsels, dummy)

{.pop.} # raises: []
