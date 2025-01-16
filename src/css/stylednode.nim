import css/cssvalues
import css/selectorparser
import html/dom

# Container to hold a style and a node.
# Pseudo-elements are implemented using StyledNode objects without nodes. Input
# elements are implemented as internal "pseudo-elements."
#
# To avoid having to invalidate the entire tree on pseudo-class changes, each
# node holds a list of nodes their CSS values depend on. (This list may include
# the node itself.) In addition, nodes also store each value valid for
# dependency d. These are then used for checking the validity of StyledNodes.
#
# In other words - say we have to apply the author stylesheets of the following
# document:
#
# <style>
# div:hover { color: red; }
# :not(input:checked) + p { display: none; }
# </style>
# <div>This div turns red on hover.</div>
# <input type=checkbox>
# <p>This paragraph is only shown when the checkbox above is checked.
#
# That produces the following dependency graph (simplified):
# div -> div (hover)
# p -> input (checked)
#
# Then, to check if a node has been invalidated, we just iterate over all
# recorded dependencies of each StyledNode, and check if their registered value
# of the pseudo-class still matches that of its associated element.
#
# So in our example, for div we check if div's :hover pseudo-class has changed,
# for p we check whether input's :checked pseudo-class has changed.

type
  StyledType* = enum
    stElement, stText, stReplacement

  DependencyInfoItem = object
    t: DependencyType
    element: Element

  DependencyInfo* = object
    items: seq[DependencyInfoItem]

  StyledNode* = ref object
    element*: Element
    pseudo*: PseudoElement
    case t*: StyledType
    of stText:
      text*: CharacterData
    of stElement:
      computed*: CSSValues
      children*: seq[StyledNode]
      # All elements our style depends on, for each dependency type d.
      depends*: DependencyInfo
    of stReplacement:
      # replaced elements: quotes, or (TODO) markers, images
      content*: CSSContent

template textData*(styledNode: StyledNode): string =
  styledNode.text.data

when defined(debug):
  func `$`*(node: StyledNode): string =
    if node == nil:
      return "nil"
    case node.t
    of stText:
      return "#text " & node.textData
    of stElement:
      if node.pseudo != peNone:
        return "#" & $node.pseudo & "::" & $node.element
      return $node.element
    of stReplacement:
      return "#replacement"

proc isValid*(styledNode: StyledNode; toReset: var seq[Element]): bool =
  if styledNode.t in {stText, stReplacement}:
    return true
  # pseudo elements do not have selector dependencies
  if styledNode.pseudo == peNone:
    let element = styledNode.element
    if element.invalid:
      toReset.add(element)
      return false
    for it in styledNode.depends.items:
      if it.t in it.element.invalidDeps:
        toReset.add(it.element)
        return false
  return true

proc add*(depends: var DependencyInfo; element: Element; t: DependencyType) =
  depends.items.add(DependencyInfoItem(t: t, element: element))

proc merge*(a: var DependencyInfo; b: DependencyInfo) =
  for it in b.items:
    if it notin a.items:
      a.items.add(it)

func newStyledElement*(element: Element): StyledNode =
  return StyledNode(t: stElement, element: element)

func newStyledElement*(parent: StyledNode; pseudo: PseudoElement): StyledNode =
  return StyledNode(
    t: stElement,
    pseudo: pseudo,
    element: parent.element
  )

func newStyledText*(parent: StyledNode; text: Text): StyledNode =
  return StyledNode(t: stText, text: text, element: parent.element)

func newStyledReplacement*(parent: StyledNode; content: sink CSSContent;
    pseudo: PseudoElement): StyledNode =
  return StyledNode(
    t: stReplacement,
    element: parent.element,
    content: content,
    pseudo: pseudo
  )
