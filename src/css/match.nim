{.push raises: [].}

import std/strutils

import chame/tags
import css/cssparser
import html/catom
import html/dom
import utils/twtstr

# Matching is slightly complicated by dependency tracking.
# In general, dependencies must be added for any element whose state
# affects the selectors matched onto the element.  However, consider the
# following situation:
#
#   * to match: x > y:hover
#   * on elements: <z><y>test</y></z>
#
# A naive algorithm would mark a dependency of y on itself, since it
# y:hover depends on y's hover status.  But upon closer inspection, we
# can see that it is *not necessary*: y's parent is x, not z, so no
# matter if y is hovered, matching it again would be pointless.
#
# Hence it is more efficient for us to *continue matching* upon seeing
# y:hover, and discard the dependency once it is determined that the
# parent doesn't match z.
#
# A similar situation arises for compound selectors as well, and even
# selector lists (in case of pseudo-class functions).

proc matches(element: Element; cxsel: ComplexSelector;
  depends: var DependencyInfo; ohasDeps: var bool): bool

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

proc matches(element: Element; slist: SelectorList;
    depends: var DependencyInfo; ohasDeps: var bool): bool =
  var pmatch = false
  var rhasDeps = false
  for cxsel in slist:
    var hasDeps = false
    let match = element.matches(cxsel, depends, hasDeps)
    if not hasDeps:
      if match:
        return true
      if pmatch:
        # already seen a matching selector; merge depends and return
        # false.
        break
    else:
      rhasDeps = true
      pmatch = match
  ohasDeps = rhasDeps
  return pmatch

proc matches(element: Element; pc: PseudoClass; depends: var DependencyInfo;
    hasDeps: var bool): bool =
  case pc
  of pcFirstChild: return element.parentNode.firstElementChild == element
  of pcLastChild: return element.parentNode.lastElementChild == element
  of pcFirstNode: return element.isFirstVisualNode()
  of pcLastNode: return element.isLastVisualNode()
  of pcOnlyChild:
    return element.parentNode.firstElementChild == element and
      element.parentNode.lastElementChild == element
  of pcHover:
    hasDeps = true
    depends.add(element, dtHover)
    return element.hover
  of pcRoot: return element == element.document.documentElement
  of pcChecked:
    if element of HTMLInputElement:
      hasDeps = true
      depends.add(element, dtChecked)
      return HTMLInputElement(element).checked
    elif element of HTMLOptionElement:
      hasDeps = true
      depends.add(element, dtChecked)
      return HTMLOptionElement(element).selected
    return false
  of pcFocus:
    hasDeps = true
    depends.add(element, dtFocus)
    return element.document.focus == element
  of pcTarget:
    hasDeps = true
    depends.add(element, dtTarget)
    return element.document.target == element
  of pcLink:
    return element.tagType in {TAG_A, TAG_AREA} and element.attrb(satHref)
  of pcVisited:
    return false

proc matchesLang(element: Element; lang: string): bool =
  for element in element.branchElems:
    if element.attrb(satLang):
      return element.attr(satLang) == lang
  true

proc matchesNthChild(element: Element; nthChild: CSSNthChild;
    depends: var DependencyInfo; ohasDeps: var bool): bool =
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
  if element.matches(nthChild.ofsels, depends, ohasDeps):
    var i = 1
    for child in element.parentNode.elementList:
      if child == element:
        if A == 0:
          return i == B
        let j = (i - B)
        if A < 0:
          return j <= 0 and j mod A == 0
        return j >= 0 and j mod A == 0
      var hasDeps = false
      if child.matches(nthChild.ofsels, depends, hasDeps):
        inc i
      ohasDeps = ohasDeps or hasDeps
  false

proc matchesNthLastChild(element: Element; nthChild: CSSNthChild;
    depends: var DependencyInfo; ohasDeps: var bool): bool =
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
  if element.matches(nthChild.ofsels, depends, ohasDeps):
    var i = 1
    for child in element.parentNode.relementList:
      if child == element:
        if A == 0:
          return i == B
        let j = (i - B)
        if A < 0:
          return j <= 0 and j mod A == 0
        return j >= 0 and j mod A == 0
      var hasDeps: bool
      if child.matches(nthChild.ofsels, depends, hasDeps):
        inc i
      ohasDeps = ohasDeps or hasDeps
  false

proc matches(element: Element; sel: Selector; depends: var DependencyInfo;
    ohasDeps: var bool): bool =
  case sel.t
  of stType:
    return element.localName == sel.tag
  of stClass:
    for it in element.classList:
      if sel.class == it.toLowerAscii():
        return true
    return false
  of stId:
    return sel.id == element.id.toLowerAscii()
  of stAttr:
    return element.matchesAttr(sel)
  of stPseudoClass:
    return element.matches(sel.pc, depends, ohasDeps)
  of stPseudoElement:
    return true
  of stUniversal:
    return true
  of stNthChild:
    return element.matchesNthChild(sel.nthChild, depends, ohasDeps)
  of stNthLastChild:
    return element.matchesNthLastChild(sel.nthChild, depends, ohasDeps)
  of stNot:
    return not element.matches(sel.fsels, depends, ohasDeps)
  of stIs, stWhere:
    return element.matches(sel.fsels, depends, ohasDeps)
  of stLang:
    return element.matchesLang(sel.lang)

proc matches(element: Element; sels: CompoundSelector;
    depends: var DependencyInfo; ohasDeps: var bool): bool =
  var pmatch = true
  for sel in sels:
    var hasDeps = false
    let match = element.matches(sel, depends, hasDeps)
    if not hasDeps:
      if not match:
        return false
      if not pmatch:
        # already seen a matching selector; merge depends and return
        # false.
        break
    else:
      ohasDeps = true
      pmatch = match
  return pmatch

proc matches(element: Element; cxsel: ComplexSelector;
    depends: var DependencyInfo; ohasDeps: var bool): bool =
  var e = element
  var pmatch = true
  var mdepends = DependencyInfo.default
  for csel in cxsel.ritems:
    var match = false
    var hasDeps = false
    case csel.ct
    of ctNone:
      match = e.matches(csel, mdepends, hasDeps)
    of ctDescendant:
      e = e.parentElement
      while e != nil:
        if e.matches(csel, mdepends, hasDeps):
          match = true
          break
        e = e.parentElement
    of ctChild:
      e = e.parentElement
      match = e != nil and e.matches(csel, mdepends, hasDeps)
    of ctNextSibling:
      e = e.previousElementSibling
      match = e != nil and e.matches(csel, mdepends, hasDeps)
    of ctSubsequentSibling:
      var it = element.previousElementSibling
      while it != nil:
        if it.matches(csel, mdepends, hasDeps):
          e = it
          match = true
          break
        it = it.previousElementSibling
    if not hasDeps:
      if not match:
        return false # we can discard depends.
      if not pmatch:
        # already seen a non-matching selector; merge depends and return
        # false.
        break
    else:
      ohasDeps = true
      pmatch = match
    if e == nil:
      break
  depends.merge(mdepends)
  return pmatch

# Note: this modifies "depends".
proc matches*(element: Element; cxsel: ComplexSelector;
    depends: var DependencyInfo): bool =
  var dummy: bool
  return element.matches(cxsel, depends, dummy)

# Forward declaration hack
matchesImpl = proc(element: Element; slist: SelectorList): bool {.nimcall.} =
  var dummy = DependencyInfo.default
  var dummy2: bool
  return element.matches(slist, dummy, dummy2)

{.pop.} # raises: []
