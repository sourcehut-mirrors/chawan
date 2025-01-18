import css/cssvalues
import css/selectorparser
import html/dom

# Container to hold a style and a node.
#TODO: maintaining a separate tree for styles is inefficient, and at
# this point, most of it has been moved to the DOM anyway.
#
# The only purpose it has left is to arrange text, element and
# pseudo-element nodes into a single seq, but this should be done
# with an iterator instead.

type
  StyledType* = enum
    stElement, stText, stReplacement

  StyledNode* = ref object
    element*: Element
    pseudo*: PseudoElement
    case t*: StyledType
    of stText:
      text*: CharacterData
    of stElement:
      children*: seq[StyledNode]
    of stReplacement:
      # replaced elements: quotes, or (TODO) markers, images
      content*: CSSContent

when defined(debug):
  func `$`*(node: StyledNode): string =
    if node == nil:
      return "nil"
    case node.t
    of stText:
      return "#text " & node.text.data
    of stElement:
      if node.pseudo != peNone:
        return $node.element.tagType & "::" & $node.pseudo
      return $node.element
    of stReplacement:
      return "#replacement"

template computed*(styledNode: StyledNode): CSSValues =
  styledNode.element.computedMap[styledNode.pseudo]

proc isValid*(styledNode: StyledNode; toReset: var seq[Element]): bool =
  if styledNode.t in {stText, stReplacement} or styledNode.pseudo != peNone:
    # pseudo elements do not have selector dependencies
    return true
  return styledNode.element.isValid(toReset)

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
