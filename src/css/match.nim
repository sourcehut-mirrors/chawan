import std/strutils

import chame/tags
import css/cssparser
import css/selectorparser
import css/stylednode
import html/catom
import html/dom
import utils/twtstr

#TODO rfNone should match insensitively for certain properties
func matchesAttr(element: Element; sel: Selector): bool =
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

func matches*(element: Element; cxsel: ComplexSelector;
  depends: var DependencyInfo): bool

func matches(element: Element; slist: SelectorList;
    depends: var DependencyInfo): bool =
  for cxsel in slist:
    if element.matches(cxsel, depends):
      return true
  return false

func matches(element: Element; pseudo: PseudoData;
    depends: var DependencyInfo): bool =
  case pseudo.t
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
    let A = pseudo.anb.A # step
    let B = pseudo.anb.B # start
    if pseudo.ofsels.len == 0:
      let i = element.elIndex + 1
      if A == 0:
        return i == B
      let j = (i - B)
      if A < 0:
        return j <= 0 and j mod A == 0
      return j >= 0 and j mod A == 0
    if element.matches(pseudo.ofsels, depends):
      var i = 1
      for child in element.parentNode.elementList:
        if child == element:
          if A == 0:
            return i == B
          let j = (i - B)
          if A < 0:
            return j <= 0 and j mod A == 0
          return j >= 0 and j mod A == 0
        if child.matches(pseudo.ofsels, depends):
          inc i
    return false
  of pcNthLastChild:
    let A = pseudo.anb.A # step
    let B = pseudo.anb.B # start
    if pseudo.ofsels.len == 0:
      let last = element.parentNode.lastElementChild
      let i = last.elIndex + 1 - element.elIndex
      if A == 0:
        return i == B
      let j = (i - B)
      if A < 0:
        return j <= 0 and j mod A == 0
      return j >= 0 and j mod A == 0
    if element.matches(pseudo.ofsels, depends):
      var i = 1
      for child in element.parentNode.elementList_rev:
        if child == element:
          if A == 0:
            return i == B
          let j = (i - B)
          if A < 0:
            return j <= 0 and j mod A == 0
          return j >= 0 and j mod A == 0
        if child.matches(pseudo.ofsels, depends):
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
  of pcTarget:
    depends.add(element, dtTarget)
    return element.document.target == element
  of pcNot:
    return not element.matches(pseudo.fsels, depends)
  of pcIs, pcWhere:
    return element.matches(pseudo.fsels, depends)
  of pcLang:
    return pseudo.s == "en" #TODO languages?
  of pcLink:
    return element.tagType in {TAG_A, TAG_AREA} and element.attrb(satHref)
  of pcVisited:
    return false

func matches(element: Element; sel: Selector; depends: var DependencyInfo):
    bool =
  case sel.t
  of stType:
    return element.localName == sel.tag
  of stClass:
    let factory = element.document.factory
    for it in element.classList.toks:
      if sel.class == factory.toLowerAscii(it):
        return true
    return false
  of stId:
    return sel.id == element.document.factory.toLowerAscii(element.id)
  of stAttr:
    return element.matchesAttr(sel)
  of stPseudoClass:
    return element.matches(sel.pseudo, depends)
  of stPseudoElement:
    return true
  of stUniversal:
    return true

func matches(element: Element; sels: CompoundSelector;
    depends: var DependencyInfo): bool =
  for sel in sels:
    if not element.matches(sel, depends):
      return false
  return true

# Note: this modifies "depends".
func matches*(element: Element; cxsel: ComplexSelector;
    depends: var DependencyInfo): bool =
  var e = element
  for i in countdown(cxsel.high, 0):
    var match = false
    case cxsel[i].ct
    of ctNone:
      match = e.matches(cxsel[i], depends)
    of ctDescendant:
      e = e.parentElement
      while e != nil:
        if e.matches(cxsel[i], depends):
          match = true
          break
        e = e.parentElement
    of ctChild:
      e = e.parentElement
      if e != nil:
        match = e.matches(cxsel[i], depends)
    of ctNextSibling:
      let prev = e.previousElementSibling
      if prev != nil:
        e = prev
        match = e.matches(cxsel[i], depends)
    of ctSubsequentSibling:
      let parent = e.parentNode
      for j in countdown(e.index - 1, 0):
        let child = parent.childList[j]
        if child of Element:
          let child = Element(child)
          if child.matches(cxsel[i], depends):
            e = child
            match = true
            break
    if not match:
      return false
  return true

# Forward declaration hack
querySelectorAllImpl = proc(node: Node; q: string): seq[Element] =
  result = @[]
  let selectors = parseSelectors(q, node.document.factory)
  for element in node.elements:
    var dummy: DependencyInfo
    if element.matches(selectors, dummy):
      result.add(element)

querySelectorImpl = proc(node: Node; q: string): Element =
  let selectors = parseSelectors(q, node.document.factory)
  for element in node.elements:
    var dummy: DependencyInfo
    if element.matches(selectors, dummy):
      return element
  return nil
