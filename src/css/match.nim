import std/options
import std/strutils
import std/tables

import chame/tags
import css/cssparser
import css/selectorparser
import css/stylednode
import html/catom
import html/dom
import utils/twtstr

#TODO rfNone should match insensitively for certain properties
func attrSelectorMatches(elem: Element; sel: Selector): bool =
  case sel.rel.t
  of rtExists: return elem.attrb(sel.attr)
  of rtEquals:
    case sel.rel.flag
    of rfNone: return elem.attr(sel.attr) == sel.value
    of rfI: return elem.attr(sel.attr).equalsIgnoreCase(sel.value)
    of rfS: return elem.attr(sel.attr) == sel.value
  of rtToken:
    let val = elem.attr(sel.attr)
    case sel.rel.flag
    of rfNone: return sel.value in val.split(AsciiWhitespace)
    of rfI:
      let val = val.toLowerAscii()
      let selval = sel.value.toLowerAscii()
      return selval in val.split(AsciiWhitespace)
    of rfS: return sel.value in val.split(AsciiWhitespace)
  of rtBeginDash:
    let val = elem.attr(sel.attr)
    case sel.rel.flag
    of rfNone:
      return val == sel.value or sel.value.startsWith(val & '-')
    of rfI:
      return val.equalsIgnoreCase(sel.value) or
        sel.value.startsWithIgnoreCase(val & '-')
    of rfS:
      return val == sel.value or sel.value.startsWith(val & '-')
  of rtStartsWith:
    let val = elem.attr(sel.attr)
    case sel.rel.flag
    of rfNone: return val.startsWith(sel.value)
    of rfI: return val.startsWithIgnoreCase(sel.value)
    of rfS: return val.startsWith(sel.value)
  of rtEndsWith:
    let val = elem.attr(sel.attr)
    case sel.rel.flag
    of rfNone: return val.endsWith(sel.value)
    of rfI: return val.endsWithIgnoreCase(sel.value)
    of rfS: return val.endsWith(sel.value)
  of rtContains:
    let val = elem.attr(sel.attr)
    case sel.rel.flag
    of rfNone: return val.contains(sel.value)
    of rfI:
      let val = val.toLowerAscii()
      let selval = sel.value.toLowerAscii()
      return val.contains(selval)
    of rfS: return val.contains(sel.value)

func selectorsMatch*[T: Element|StyledNode](elem: T; cxsel: ComplexSelector;
  felem: T = nil): bool

func selectorsMatch[T: Element|StyledNode](elem: T; slist: SelectorList;
    felem: T = nil): bool =
  for cxsel in slist:
    if elem.selectorsMatch(cxsel, felem):
      return true
  return false

func pseudoSelectorMatches[T: Element|StyledNode](elem: T; sel: Selector;
    felem: T): bool =
  let selem = elem
  when elem is StyledNode:
    let elem = Element(elem.node)
  case sel.pseudo.t
  of pcFirstChild: return elem.parentNode.firstElementChild == elem
  of pcLastChild: return elem.parentNode.lastElementChild == elem
  of pcOnlyChild:
    return elem.parentNode.firstElementChild == elem and
      elem.parentNode.lastElementChild == elem
  of pcHover:
    when selem is StyledNode: felem.addDependency(elem, dtHover)
    return elem.hover
  of pcRoot: return elem == elem.document.documentElement
  of pcNthChild:
    if sel.pseudo.ofsels.len != 0 and
        not selem.selectorsMatch(sel.pseudo.ofsels, felem):
      return false
    let A = sel.pseudo.anb.A # step
    let B = sel.pseudo.anb.B # start
    var i = 1
    let parent = when selem is StyledNode: selem.parent
    else: selem.parentNode
    if parent == nil: return false
    for child in parent.elementList:
      when selem is StyledNode:
        if not child.isDomElement: continue
      if child == selem:
        if A == 0:
          return i == B
        if A < 0:
          return (i - B) <= 0 and (i - B) mod A == 0
        return (i - B) >= 0 and (i - B) mod A == 0
      if sel.pseudo.ofsels.len == 0 or
          child.selectorsMatch(sel.pseudo.ofsels, felem):
        inc i
    return false
  of pcNthLastChild:
    if sel.pseudo.ofsels.len == 0 and
        not selem.selectorsMatch(sel.pseudo.ofsels, felem):
      return false
    let A = sel.pseudo.anb.A # step
    let B = sel.pseudo.anb.B # start
    var i = 1
    let parent = when selem is StyledNode: selem.parent
    else: selem.parentNode
    if parent == nil: return false
    for child in parent.elementList_rev:
      when selem is StyledNode:
        if not child.isDomElement: continue
      if child == selem:
        if A == 0:
          return i == B
        if A < 0:
          return (i - B) <= 0 and (i - B) mod A == 0
        return (i - B) >= 0 and (i - B) mod A == 0
      if sel.pseudo.ofsels.len != 0 or
          child.selectorsMatch(sel.pseudo.ofsels, felem):
        inc i
    return false
  of pcChecked:
    when selem is StyledNode: felem.addDependency(elem, dtChecked)
    if elem.tagType == TAG_INPUT:
      return HTMLInputElement(elem).checked
    elif elem.tagType == TAG_OPTION:
      return HTMLOptionElement(elem).selected
    return false
  of pcFocus:
    when selem is StyledNode: felem.addDependency(elem, dtFocus)
    return elem.document.focus == elem
  of pcNot:
    return not selem.selectorsMatch(sel.pseudo.fsels, felem)
  of pcIs, pcWhere:
    return selem.selectorsMatch(sel.pseudo.fsels, felem)
  of pcLang:
    return sel.pseudo.s == "en" #TODO languages?
  of pcLink:
    return elem.tagType in {TAG_A, TAG_AREA} and elem.attrb(satHref)
  of pcVisited:
    return false

func selectorMatches[T: Element|StyledNode](elem: T; sel: Selector;
    felem: T = nil): bool =
  let selem = elem
  when elem is StyledNode:
    let elem = Element(selem.node)
  case sel.t
  of stType:
    return elem.localName == sel.tag
  of stClass:
    return sel.class in elem.classList
  of stId:
    return sel.id == elem.id
  of stAttr:
    return elem.attrSelectorMatches(sel)
  of stPseudoClass:
    return pseudoSelectorMatches(selem, sel, felem)
  of stPseudoElement:
    return true
  of stUniversal:
    return true

func selectorsMatch[T: Element|StyledNode](elem: T; sels: CompoundSelector;
    felem: T): bool =
  for sel in sels:
    if not selectorMatches(elem, sel, felem):
      return false
  return true

func complexSelectorMatches[T: Element|StyledNode](elem: T;
    cxsel: ComplexSelector; felem: T = nil): bool =
  var e = elem
  for i in countdown(cxsel.high, 0):
    let sels = cxsel[i]
    if e == nil:
      return false
    var match = false
    case sels.ct
    of ctNone:
      match = e.selectorsMatch(sels, felem)
    of ctDescendant:
      e = e.parentElement
      while e != nil:
        if e.selectorsMatch(sels, felem):
          match = true
          break
        e = e.parentElement
    of ctChild:
      e = e.parentElement
      if e != nil:
        match = e.selectorsMatch(sels, felem)
    of ctNextSibling:
      if e.parentElement == nil: return false
      var found = false
      for child in e.parentElement.elementList_rev:
        when elem is StyledNode:
          if not child.isDomElement: continue
        if e == child:
          found = true
          continue
        if found:
          e = child
          match = e.selectorsMatch(sels, felem)
          break
    of ctSubsequentSibling:
      var found = false
      if e.parentElement == nil: return false
      for child in e.parentElement.elementList_rev:
        when elem is StyledNode:
          if not child.isDomElement: continue
        if child == elem:
          found = true
          continue
        if not found: continue
        if child.selectorsMatch(sels, felem):
          e = child
          match = true
          break
    if not match:
      return false
  return true

# WARNING for StyledNode, this has the side effect of modifying depends.
#TODO make that an explicit flag or something, also get rid of the Element case
func selectorsMatch*[T: Element|StyledNode](elem: T; cxsel: ComplexSelector;
    felem: T = nil): bool =
  let felem = if felem != nil:
    felem
  else:
    elem
  return elem.complexSelectorMatches(cxsel, felem)

# Forward declaration hack
querySelectorAllImpl = proc(node: Node; q: string): seq[Element] =
  result = @[]
  let selectors = parseSelectors(q, node.document.factory)
  for element in node.elements:
    if element.selectorsMatch(selectors):
      result.add(element)

querySelectorImpl = proc(node: Node; q: string): Element =
  let selectors = parseSelectors(q, node.document.factory)
  for element in node.elements:
    if element.selectorsMatch(selectors):
      return element
  return nil
