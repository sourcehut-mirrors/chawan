import std/strutils

import chame/tags
import css/cssparser
import css/selectorparser
import css/stylednode
import html/catom
import html/dom
import utils/twtstr

#TODO rfNone should match insensitively for certain properties
func attrSelectorMatches(element: Element; sel: Selector): bool =
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

func selectorsMatch*(element: Element; cxsel: ComplexSelector;
  depends: var DependencyInfo): bool

func selectorsMatch(element: Element; slist: SelectorList;
    depends: var DependencyInfo): bool =
  for cxsel in slist:
    if element.selectorsMatch(cxsel, depends):
      return true
  return false

func pseudoSelectorMatches(element: Element; sel: Selector;
    depends: var DependencyInfo): bool =
  case sel.pseudo.t
  of pcFirstChild: return element.parentNode.firstElementChild == element
  of pcLastChild: return element.parentNode.lastElementChild == element
  of pcFirstNode: return element.isFirstVisualNode()
  of pcLastNode: return element.isLastVisualNode()
  of pcOnlyChild:
    return element.parentNode.firstElementChild == element and
      element.parentNode.lastElementChild == element
  of pcHover:
    #TODO this is somewhat problematic.
    # e.g. if there is a rule like ".class :hover", then you set
    # dtHover for basically every element, even if most of them are not
    # a .class descendant.
    # Ideally we should try to match the rest of the selector before
    # attaching dependencies in general.
    depends.add(element, dtHover)
    return element.hover
  of pcRoot: return element == element.document.documentElement
  of pcNthChild:
    if sel.pseudo.ofsels.len != 0 and
        not element.selectorsMatch(sel.pseudo.ofsels, depends):
      return false
    let A = sel.pseudo.anb.A # step
    let B = sel.pseudo.anb.B # start
    var i = 1
    let parent = element.parentNode
    if parent == nil: return false
    for child in parent.elementList:
      if child == element:
        if A == 0:
          return i == B
        if A < 0:
          return (i - B) <= 0 and (i - B) mod A == 0
        return (i - B) >= 0 and (i - B) mod A == 0
      if sel.pseudo.ofsels.len == 0 or
          child.selectorsMatch(sel.pseudo.ofsels, depends):
        inc i
    return false
  of pcNthLastChild:
    if sel.pseudo.ofsels.len == 0 and
        not element.selectorsMatch(sel.pseudo.ofsels, depends):
      return false
    let A = sel.pseudo.anb.A # step
    let B = sel.pseudo.anb.B # start
    var i = 1
    let parent = element.parentNode
    if parent == nil:
      return false
    for child in parent.elementList_rev:
      if child == element:
        if A == 0:
          return i == B
        if A < 0:
          return (i - B) <= 0 and (i - B) mod A == 0
        return (i - B) >= 0 and (i - B) mod A == 0
      if sel.pseudo.ofsels.len != 0 or
          child.selectorsMatch(sel.pseudo.ofsels, depends):
        inc i
    return false
  of pcChecked:
    depends.add(element, dtChecked)
    if element.tagType == TAG_INPUT:
      return HTMLInputElement(element).checked
    elif element.tagType == TAG_OPTION:
      return HTMLOptionElement(element).selected
    return false
  of pcFocus:
    depends.add(element, dtFocus)
    return element.document.focus == element
  of pcNot:
    return not element.selectorsMatch(sel.pseudo.fsels, depends)
  of pcIs, pcWhere:
    return element.selectorsMatch(sel.pseudo.fsels, depends)
  of pcLang:
    return sel.pseudo.s == "en" #TODO languages?
  of pcLink:
    return element.tagType in {TAG_A, TAG_AREA} and element.attrb(satHref)
  of pcVisited:
    return false

func selectorMatches(element: Element; sel: Selector;
    depends: var DependencyInfo): bool =
  case sel.t
  of stType:
    return element.localName == sel.tag
  of stClass:
    return sel.class in element.classList
  of stId:
    return sel.id == element.id
  of stAttr:
    return element.attrSelectorMatches(sel)
  of stPseudoClass:
    return pseudoSelectorMatches(element, sel, depends)
  of stPseudoElement:
    return true
  of stUniversal:
    return true

func selectorsMatch(element: Element; sels: CompoundSelector;
    depends: var DependencyInfo): bool =
  for sel in sels:
    if not selectorMatches(element, sel, depends):
      return false
  return true

func complexSelectorMatches(element: Element; cxsel: ComplexSelector;
    depends: var DependencyInfo): bool =
  var e = element
  for i in countdown(cxsel.high, 0):
    let sels = cxsel[i]
    if e == nil:
      return false
    var match = false
    case sels.ct
    of ctNone:
      match = e.selectorsMatch(sels, depends)
    of ctDescendant:
      e = e.parentElement
      while e != nil:
        if e.selectorsMatch(sels, depends):
          match = true
          break
        e = e.parentElement
    of ctChild:
      e = e.parentElement
      if e != nil:
        match = e.selectorsMatch(sels, depends)
    of ctNextSibling:
      if e.parentElement == nil: return false
      var found = false
      for child in e.parentElement.elementList_rev:
        if e == child:
          found = true
          continue
        if found:
          e = child
          match = e.selectorsMatch(sels, depends)
          break
    of ctSubsequentSibling:
      var found = false
      if e.parentElement == nil: return false
      for child in e.parentElement.elementList_rev:
        if child == element:
          found = true
          continue
        if not found: continue
        if child.selectorsMatch(sels, depends):
          e = child
          match = true
          break
    if not match:
      return false
  return true

# Note: this modifies "depends".
func selectorsMatch*(element: Element; cxsel: ComplexSelector;
    depends: var DependencyInfo): bool =
  return element.complexSelectorMatches(cxsel, depends)

# Forward declaration hack
querySelectorAllImpl = proc(node: Node; q: string): seq[Element] =
  result = @[]
  let selectors = parseSelectors(q, node.document.factory)
  for element in node.elements:
    var dummy: DependencyInfo
    if element.selectorsMatch(selectors, dummy):
      result.add(element)

querySelectorImpl = proc(node: Node; q: string): Element =
  let selectors = parseSelectors(q, node.document.factory)
  for element in node.elements:
    var dummy: DependencyInfo
    if element.selectorsMatch(selectors, dummy):
      return element
  return nil
