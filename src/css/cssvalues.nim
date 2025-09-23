{.push raises: [].}

import std/algorithm
import std/macros
import std/math
import std/options
import std/strutils
import std/tables

import css/cssparser
import css/lunit
import html/catom
import types/bitmap
import types/color
import types/opt
import types/refstring
import types/winattrs
import utils/twtstr

export CSSPropertyType

type
  CSSValueType* = enum
    cvtBgcolorIsCanvas = "bgcolorIsCanvas"
    cvtBorderCollapse = "borderCollapse"
    cvtBorderStyle = "borderStyle"
    cvtBoxSizing = "boxSizing"
    cvtCaptionSide = "captionSide"
    cvtClear = "clear"
    cvtColor = "color"
    cvtContent = "content"
    cvtCounterSet = "counterSet"
    cvtDisplay = "display"
    cvtFlexDirection = "flexDirection"
    cvtFlexWrap = "flexWrap"
    cvtFloat = "float"
    cvtFontStyle = "fontStyle"
    cvtImage = "image"
    cvtInteger = "integer"
    cvtLength = "length"
    cvtLineWidth = "lineWidth"
    cvtListStylePosition = "listStylePosition"
    cvtListStyleType = "listStyleType"
    cvtNumber = "number"
    cvtOverflow = "overflow"
    cvtPosition = "position"
    cvtQuotes = "quotes"
    cvtTextAlign = "textAlign"
    cvtTextDecoration = "textDecoration"
    cvtTextTransform = "textTransform"
    cvtVerticalAlign = "verticalAlign"
    cvtVisibility = "visibility"
    cvtWhiteSpace = "whiteSpace"
    cvtWordBreak = "wordBreak"
    cvtZIndex = "zIndex"

  CSSGlobalType* = enum
    cgtInitial = "initial"
    cgtInherit = "inherit"
    cgtRevert = "revert"
    cgtUnset = "unset"

  CSSDisplay* = enum
    DisplayInline = "inline"
    DisplayNone = "none"
    DisplayBlock = "block"
    DisplayListItem = "list-item"
    DisplayInlineBlock = "inline-block"
    DisplayTable = "table"
    DisplayInlineTable = "inline-table"
    DisplayTableRowGroup = "table-row-group"
    DisplayTableHeaderGroup = "table-header-group"
    DisplayTableFooterGroup = "table-footer-group"
    DisplayTableColumnGroup = "table-column-group"
    DisplayTableRow = "table-row"
    DisplayTableColumn = "table-column"
    DisplayTableCell = "table-cell"
    DisplayTableCaption = "table-caption"
    DisplayFlowRoot = "flow-root"
    DisplayFlex = "flex"
    DisplayInlineFlex = "inline-flex"
    DisplayGrid = "grid"
    DisplayInlineGrid = "inline-grid"
    # internal, for layout
    DisplayTableWrapper = ""
    DisplayMarker = ""

  CSSWhiteSpace* = enum
    WhitespaceNormal = "normal"
    WhitespaceNowrap = "nowrap"
    WhitespacePre = "pre"
    WhitespacePreLine = "pre-line"
    WhitespacePreWrap = "pre-wrap"

  CSSFontStyle* = enum
    FontStyleNormal = "normal"
    FontStyleItalic = "italic"
    FontStyleOblique = "oblique"

  CSSPosition* = enum
    PositionStatic = "static"
    PositionRelative = "relative"
    PositionAbsolute = "absolute"
    PositionFixed = "fixed"
    PositionSticky = "sticky"

  CSSTextDecoration* = enum
    TextDecorationNone = "none"
    TextDecorationUnderline = "underline"
    TextDecorationOverline = "overline"
    TextDecorationLineThrough = "line-through"
    TextDecorationBlink = "blink"
    TextDecorationReverse = "-cha-reverse"

  CSSWordBreak* = enum
    WordBreakNormal = "normal"
    WordBreakBreakAll = "break-all"
    WordBreakKeepAll = "keep-all"

  CSSListStyleType* = enum
    ListStyleTypeDisc = "disc"
    ListStyleTypeNone = "none"
    ListStyleTypeCircle = "circle"
    ListStyleTypeSquare = "square"
    ListStyleTypeDecimal = "decimal"
    ListStyleTypeDisclosureClosed = "disclosure-closed"
    ListStyleTypeDisclosureOpen = "disclosure-open"
    ListStyleTypeCjkEarthlyBranch = "cjk-earthly-branch"
    ListStyleTypeCjkHeavenlyStem = "cjk-heavenly-stem"
    ListStyleTypeLowerRoman = "lower-roman"
    ListStyleTypeUpperRoman = "upper-roman"
    ListStyleTypeLowerAlpha = "lower-alpha"
    ListStyleTypeUpperAlpha = "upper-alpha"
    ListStyleTypeLowerGreek = "lower-greek"
    ListStyleTypeHiragana = "hiragana"
    ListStyleTypeHiraganaIroha = "hiragana-iroha"
    ListStyleTypeKatakana = "katakana"
    ListStyleTypeKatakanaIroha = "katakana-iroha"
    ListStyleTypeJapaneseInformal = "japanese-informal"
    ListStyleTypeJapaneseFormal = "japanese-formal"

  CSSVerticalAlign* = enum
    VerticalAlignBaseline = "baseline"
    VerticalAlignSub = "sub"
    VerticalAlignSuper = "super"
    VerticalAlignTextTop = "text-top"
    VerticalAlignTextBottom = "text-bottom"
    VerticalAlignMiddle = "middle"
    VerticalAlignTop = "top"
    VerticalAlignBottom = "bottom"
    VerticalAlignLength = "-cha-length"

  CSSTextAlign* = enum
    TextAlignStart = "start"
    TextAlignEnd = "end"
    TextAlignLeft = "left"
    TextAlignRight = "right"
    TextAlignCenter = "center"
    TextAlignJustify = "justify"
    TextAlignChaCenter = "-cha-center"
    TextAlignChaLeft = "-cha-left"
    TextAlignChaRight = "-cha-right"

  CSSListStylePosition* = enum
    ListStylePositionOutside = "outside"
    ListStylePositionInside = "inside"

  CSSCaptionSide* = enum
    CaptionSideTop = "top"
    CaptionSideBottom = "bottom"
    CaptionSideBlockStart = "block-start"
    CaptionSideBlockEnd = "block-end"

  CSSBorderCollapse* = enum
    BorderCollapseSeparate = "separate"
    BorderCollapseCollapse = "collapse"

  CSSContentType* = enum
    ContentString = "-cha-string"
    ContentCounter = "-cha-counter"
    ContentOpenQuote = "open-quote"
    ContentCloseQuote = "close-quote"
    ContentNoOpenQuote = "no-open-quote"
    ContentNoCloseQuote = "no-close-quote"

  CSSFloat* = enum
    FloatNone = "none"
    FloatLeft = "left"
    FloatRight = "right"

  CSSVisibility* = enum
    VisibilityVisible = "visible"
    VisibilityHidden = "hidden"
    VisibilityCollapse = "collapse"

  CSSBoxSizing* = enum
    BoxSizingContentBox = "content-box"
    BoxSizingBorderBox = "border-box"

  CSSClear* = enum
    ClearNone = "none"
    ClearLeft = "left"
    ClearRight = "right"
    ClearBoth = "both"
    ClearInlineStart = "inline-start"
    ClearInlineEnd = "inline-end"

  CSSTextTransform* = enum
    TextTransformNone = "none"
    TextTransformCapitalize = "capitalize"
    TextTransformUppercase = "uppercase"
    TextTransformLowercase = "lowercase"
    TextTransformFullWidth = "full-width"
    TextTransformFullSizeKana = "full-size-kana"
    TextTransformChaHalfWidth = "-cha-half-width"

  CSSFlexDirection* = enum
    FlexDirectionRow = "row"
    FlexDirectionRowReverse = "row-reverse"
    FlexDirectionColumn = "column"
    FlexDirectionColumnReverse = "column-reverse"

  CSSFlexWrap* = enum
    FlexWrapNowrap = "nowrap"
    FlexWrapWrap = "wrap"
    FlexWrapWrapReverse = "wrap-reverse"

  CSSOverflow* = enum
    OverflowVisible = "visible"
    OverflowHidden = "hidden"
    OverflowClip = "clip"
    OverflowScroll = "scroll"
    OverflowAuto = "auto"
    OverflowOverlay = "overlay"

  CSSBorderStyle* = enum
    BorderStyleNone = "none"
    BorderStyleHidden = "hidden"
    BorderStyleDotted = "dotted"
    BorderStyleDashed = "dashed"
    BorderStyleSolid = "solid"
    BorderStyleDouble = "double"
    BorderStyleGroove = "groove"
    BorderStyleRidge = "ridge"
    BorderStyleInset = "inset"
    BorderStyleOutset = "outset"
    BorderStyleBracket = "-cha-bracket"
    BorderStyleParen = "-cha-paren"

type
  # CSSLength may represent:
  # * if isNaN(px) and isNaN(perc), the ident "auto"
  # * if px == 0, {npx} pixels
  # * if perc == 0, {perc} * the parent dimensions (*not* a percentage)
  # * otherwise, {npx} pixels + {perc}%
  CSSLength* = object
    npx*: float32
    perc*: float32

  CSSContent* = object
    case t*: CSSContentType
    of ContentString:
      s*: RefString
    of ContentCounter:
      counter*: CAtom
      counterStyle*: CSSListStyleType
    else:
      discard

  # nil -> auto
  CSSQuotes* = ref object
    qs*: seq[tuple[s, e: RefString]]

  CSSCounterSet* = object
    name*: CAtom
    num*: int32

  CSSZIndex* = object
    `auto`*: bool
    num*: int32

  CSSValueBit* {.union.} = object
    dummy*: uint8
    bgcolorIsCanvas*: bool
    borderCollapse*: CSSBorderCollapse
    borderStyle*: CSSBorderStyle
    boxSizing*: CSSBoxSizing
    captionSide*: CSSCaptionSide
    clear*: CSSClear
    display*: CSSDisplay
    flexDirection*: CSSFlexDirection
    flexWrap*: CSSFlexWrap
    float*: CSSFloat
    fontStyle*: CSSFontStyle
    listStylePosition*: CSSListStylePosition
    listStyleType*: CSSListStyleType
    overflow*: CSSOverflow
    position*: CSSPosition
    textAlign*: CSSTextAlign
    textDecoration*: set[CSSTextDecoration]
    textTransform*: CSSTextTransform
    verticalAlign*: CSSVerticalAlign
    visibility*: CSSVisibility
    whiteSpace*: CSSWhiteSpace
    wordBreak*: CSSWordBreak

  CSSValueHWord* {.union.} = object
    dummy: uint32
    integer*: int32
    number*: float32
    lineWidth*: float32

  CSSValueWord* {.union.} = object
    dummy: uint64
    color*: CSSColor
    length*: CSSLength
    zIndex*: CSSZIndex

  CSSValue* = ref object
    case v*: CSSValueType
    of cvtContent:
      content*: seq[CSSContent]
    of cvtQuotes:
      quotes*: CSSQuotes
    of cvtCounterSet:
      counterSet*: seq[CSSCounterSet]
    of cvtImage:
      image*: NetworkBitmap
    else: discard

  # Linked list of variable maps, except empty maps are skipped.
  CSSVariableMap* = ref object
    parent*: CSSVariableMap
    table*: Table[CAtom, CSSVariable]

  CSSValues* = ref object
    pseudo*: PseudoElement
    bits*: array[CSSPropertyType.low..LastBitPropType, CSSValueBit]
    hwords*: array[FirstHWordPropType..LastHWordPropType, CSSValueHWord]
    words*: array[FirstWordPropType..LastWordPropType, CSSValueWord]
    objs*: array[FirstObjPropType..CSSPropertyType.high, CSSValue]
    vars*: CSSVariableMap
    next*: CSSValues

  CSSOrigin* = enum
    coUserAgent
    coUser
    coAuthor

  CSSEntryType* = enum
    ceBit, ceWord, ceHWord, ceObject, ceVar, ceGlobal

  CSSVarItem* = object
    name*: CAtom
    toks*: seq[CSSToken]

  CSSVarEntry* = ref object
    resolved*: seq[tuple[vars: CSSVariableMap; entries: seq[CSSComputedEntry]]]
    items*: seq[CSSVarItem]

  CSSComputedEntry* = object
    p*: CSSAnyPropertyType
    case et*: CSSEntryType
    of ceBit:
      bit*: uint8
    of ceHWord:
      hword*: CSSValueHWord
    of ceWord:
      word*: CSSValueWord
    of ceObject:
      obj*: CSSValue
    of ceVar:
      cvar*: CSSVarEntry
    of ceGlobal:
      global*: CSSGlobalType

  CSSVariable* = ref object
    name*: CAtom
    items*: seq[CSSVarItem]

static:
  doAssert sizeof(CSSValueBit) == 1
  doAssert sizeof(CSSValueHWord) <= 4
  doAssert sizeof(CSSValueWord) <= 8
  doAssert sizeof(CSSComputedEntry()) <= 16

const ValueTypes = [
  # bits
  cptBgcolorIsCanvas: cvtBgcolorIsCanvas,
  cptBorderBottomStyle: cvtBorderStyle,
  cptBorderCollapse: cvtBorderCollapse,
  cptBorderLeftStyle: cvtBorderStyle,
  cptBorderRightStyle: cvtBorderStyle,
  cptBorderTopStyle: cvtBorderStyle,
  cptBoxSizing: cvtBoxSizing,
  cptCaptionSide: cvtCaptionSide,
  cptClear: cvtClear,
  cptDisplay: cvtDisplay,
  cptFlexDirection: cvtFlexDirection,
  cptFlexWrap: cvtFlexWrap,
  cptFloat: cvtFloat,
  cptFontStyle: cvtFontStyle,
  cptListStylePosition: cvtListStylePosition,
  cptListStyleType: cvtListStyleType,
  cptOverflowX: cvtOverflow,
  cptOverflowY: cvtOverflow,
  cptPosition: cvtPosition,
  cptTextAlign: cvtTextAlign,
  cptTextDecoration: cvtTextDecoration,
  cptTextTransform: cvtTextTransform,
  cptVerticalAlign: cvtVerticalAlign,
  cptVisibility: cvtVisibility,
  cptWhiteSpace: cvtWhiteSpace,
  cptWordBreak: cvtWordBreak,

  # half-words
  cptBorderBottomWidth: cvtLineWidth,
  cptBorderLeftWidth: cvtLineWidth,
  cptBorderRightWidth: cvtLineWidth,
  cptBorderTopWidth: cvtLineWidth,
  cptChaColspan: cvtInteger,
  cptChaRowspan: cvtInteger,
  cptFlexGrow: cvtNumber,
  cptFlexShrink: cvtNumber,
  cptFontWeight: cvtInteger,
  cptInputIntrinsicSize: cvtNumber,
  cptOpacity: cvtNumber,

  # words
  cptBackgroundColor: cvtColor,
  cptBorderBottomColor: cvtColor,
  cptBorderLeftColor: cvtColor,
  cptBorderRightColor: cvtColor,
  cptBorderSpacingBlock: cvtLength,
  cptBorderSpacingInline: cvtLength,
  cptBorderTopColor: cvtColor,
  cptBottom: cvtLength,
  cptColor: cvtColor,
  cptFlexBasis: cvtLength,
  cptFontSize: cvtLength,
  cptHeight: cvtLength,
  cptLeft: cvtLength,
  cptMarginBottom: cvtLength,
  cptMarginLeft: cvtLength,
  cptMarginRight: cvtLength,
  cptMarginTop: cvtLength,
  cptMaxHeight: cvtLength,
  cptMaxWidth: cvtLength,
  cptMinHeight: cvtLength,
  cptMinWidth: cvtLength,
  cptPaddingBottom: cvtLength,
  cptPaddingLeft: cvtLength,
  cptPaddingRight: cvtLength,
  cptPaddingTop: cvtLength,
  cptRight: cvtLength,
  cptTop: cvtLength,
  cptVerticalAlignLength: cvtLength,
  cptWidth: cvtLength,
  cptZIndex: cvtZIndex,

  # pointers
  cptBackgroundImage: cvtImage,
  cptContent: cvtContent,
  cptCounterReset: cvtCounterSet,
  cptCounterIncrement: cvtCounterSet,
  cptCounterSet: cvtCounterSet,
  cptQuotes: cvtQuotes,
]

const InheritedProperties = {
  cptColor, cptFontStyle, cptWhiteSpace, cptFontWeight, cptTextDecoration,
  cptWordBreak, cptListStyleType, cptTextAlign, cptListStylePosition,
  cptCaptionSide, cptBorderSpacingInline, cptBorderSpacingBlock,
  cptBorderCollapse, cptQuotes, cptVisibility, cptTextTransform
}

const OverflowScrollLike* = {OverflowScroll, OverflowAuto, OverflowOverlay}
const OverflowHiddenLike* = {OverflowHidden, OverflowClip}
const FlexReverse* = {FlexDirectionRowReverse, FlexDirectionColumnReverse}
const DisplayInlineBlockLike* = {
  DisplayInlineTable, DisplayInlineBlock, DisplayInlineFlex, DisplayInlineGrid,
  DisplayMarker
}
const DisplayOuterInline* = DisplayInlineBlockLike + {DisplayInline}
const DisplayInnerBlock* = {
  DisplayBlock, DisplayFlowRoot, DisplayTableCaption, DisplayTableCell,
  DisplayInlineBlock, DisplayListItem, DisplayMarker
}
const DisplayInnerFlex* = {DisplayFlex, DisplayInlineFlex}
const DisplayInnerGrid* = {DisplayGrid, DisplayInlineGrid}
const RowGroupBox* = {
  # Note: caption is not included here
  DisplayTableRowGroup, DisplayTableHeaderGroup, DisplayTableFooterGroup
}
const DisplayInnerTable* = {DisplayTable, DisplayInlineTable}
const DisplayInternalTable* = {
  DisplayTableCell, DisplayTableRow, DisplayTableCaption
} + RowGroupBox
const DisplayNeverHasStack* = DisplayInternalTable - {DisplayTableCell}
const PositionAbsoluteFixed* = {PositionAbsolute, PositionFixed}
const WhiteSpacePreserve* = {
  WhitespacePre, WhitespacePreLine, WhitespacePreWrap
}
const BorderStyleNoneHidden* = {BorderStyleNone, BorderStyleHidden}
const BorderStyleInput* = {BorderStyleBracket, BorderStyleParen}

type
  CSSCalcSumType = enum
    ccstNumber, ccstLength, ccstDegree

  CSSCalcKeyword = enum
    ccskE = "e"
    ccskPi = "pi"
    ccskInfinity = "infinity"
    ccskMinusInfinity = "-infinity"
    ccskNaN = "NaN"

  CSSCalcSum = object
    case t: CSSCalcSumType
    of ccstNumber:
      n: float32
    of ccstLength:
      l: CSSLength
    of ccstDegree:
      deg: float32

# Forward declarations
proc parseValue(ctx: var CSSParser; t: CSSPropertyType;
  entry: var CSSComputedEntry; attrs: WindowAttributes): Opt[void]
proc parseCalcSum(ctx: var CSSParser; attrs: ptr WindowAttributes):
  Opt[CSSCalcSum]

proc newCSSVariableMap*(parent: CSSVariableMap): CSSVariableMap =
  return CSSVariableMap(parent: parent)

proc putIfAbsent*(map: CSSVariableMap; name: CAtom; cvar: CSSVariable) =
  discard map.table.hasKeyOrPut(name, cvar)

type CSSPropertyReprType* = enum
  cprtBit, cprtHWord, cprtWord, cprtObject

proc reprType*(t: CSSPropertyType): CSSPropertyReprType =
  if t <= LastBitPropType:
    return cprtBit
  if t <= LastHWordPropType:
    return cprtHWord
  if t <= LastWordPropType:
    return cprtWord
  return cprtObject

proc valueType*(prop: CSSPropertyType): CSSValueType =
  return ValueTypes[prop]

proc isSupportedProperty*(s: string): bool =
  return propertyType(s).isOk

template auto*(length: CSSLength): bool =
  isNaN(length.npx)

template isPx*(length: CSSLength): bool =
  length.perc == 0

proc isPerc*(length: CSSLength): bool {.inline.} =
  not isNaN(length.perc) and length.perc != 0

proc isZero*(length: CSSLength): bool {.inline.} =
  length.npx == 0 and length.perc == 0

proc `$`*(length: CSSLength): string =
  if length.auto:
    return "auto"
  result = ""
  if length.perc != 0:
    result &= $length.perc & "%"
  if length.npx != 0:
    if result.len > 0:
      result &= " + "
    result &= $length.npx & "px"

proc `$`*(bmp: NetworkBitmap): string =
  return "" #TODO

proc `$`*(content: CSSContent): string =
  case content.t
  of ContentString:
    return content.s
  of ContentCounter:
    return "counter(" & $content.counter & ", " & $content.counterStyle & ')'
  of ContentOpenQuote, ContentCloseQuote, ContentNoOpenQuote,
      ContentNoCloseQuote:
    return $content.t

proc `$`(quotes: CSSQuotes): string =
  if quotes == nil:
    return "auto"
  result = ""
  for (s, e) in quotes.qs:
    result &= "'" & ($s).cssEscape() & "' '" & ($e).cssEscape() & "'"

proc `$`(counterreset: seq[CSSCounterSet]): string =
  result = ""
  for it in counterreset:
    result &= $it.name
    result &= ' '
    result &= $it.num

proc `$`(zIndex: CSSZIndex): string =
  if zIndex.auto:
    return "auto"
  return $zIndex.num

proc serialize(val: CSSValue): string =
  result = ""
  case val.v
  of cvtImage: return $val.image
  of cvtContent:
    result = ""
    for x in val.content:
      if result.len > 0:
        result &= ' '
      result &= $x
  of cvtQuotes: return $val.quotes
  of cvtCounterSet: return $val.counterSet
  else: assert false

proc serialize(val: CSSValueHWord; t: CSSValueType): string =
  case t
  of cvtInteger: return $val.integer
  of cvtNumber: return $val.number
  of cvtLineWidth: return $val.lineWidth & "px"
  else:
    assert false
    return ""

proc serialize(val: CSSValueWord; t: CSSValueType): string =
  case t
  of cvtColor: return $val.color
  of cvtLength: return $val.length
  of cvtZIndex: return $val.zIndex
  else:
    assert false
    return ""

proc serialize(val: CSSValueBit; t: CSSValueType): string =
  case t
  of cvtBgcolorIsCanvas: return $val.bgcolorIsCanvas
  of cvtBorderCollapse: return $val.borderCollapse
  of cvtBorderStyle: return $val.borderStyle
  of cvtBoxSizing: return $val.boxSizing
  of cvtCaptionSide: return $val.captionSide
  of cvtClear: return $val.clear
  of cvtDisplay: return $val.display
  of cvtFlexDirection: return $val.flexDirection
  of cvtFlexWrap: return $val.flexWrap
  of cvtFloat: return $val.float
  of cvtFontStyle: return $val.fontStyle
  of cvtListStylePosition: return $val.listStylePosition
  of cvtListStyleType: return $val.listStyleType
  of cvtOverflow: return $val.overflow
  of cvtPosition: return $val.position
  of cvtTextAlign: return $val.textAlign
  of cvtTextDecoration: return $val.textDecoration
  of cvtTextTransform: return $val.textTransform
  of cvtVerticalAlign: return $val.verticalAlign
  of cvtVisibility: return $val.visibility
  of cvtWhiteSpace: return $val.whiteSpace
  of cvtWordBreak: return $val.wordBreak
  else:
    assert false
    return ""

proc serialize*(computed: CSSValues; p: CSSPropertyType): string =
  case p.reprType
  of cprtBit: return computed.bits[p].serialize(valueType(p))
  of cprtHWord: return computed.hwords[p].serialize(valueType(p))
  of cprtWord: return computed.words[p].serialize(valueType(p))
  of cprtObject: return computed.objs[p].serialize()

proc `$`*(computed: CSSValues): string =
  result = ""
  const skip = {
    cptVerticalAlignLength, cptBorderSpacingInline, cptBorderSpacingBlock
  }
  for p in CSSPropertyType:
    if p in skip:
      continue
    result &= $p & ':'
    if p == cptVerticalAlign:
      if computed.bits[p].verticalAlign == VerticalAlignLength:
        result &= computed.serialize(cptVerticalAlignLength)
        result &= ';'
        continue
    result &= computed.serialize(p)
    result &= ';'
  result &= "border-spacing: " &
    computed.serialize(cptBorderSpacingInline) & ' ' &
    computed.serialize(cptBorderSpacingBlock) & ';'

when defined(debug):
  proc `$`*(val: CSSValue): string =
    return val.serialize()

proc getLength*(vals: CSSValues; p: CSSPropertyType): CSSLength =
  return vals.words[p].length

macro `{}`*(vals: CSSValues; s: static string): untyped =
  let t = propertyType(s).get
  let vs = ident($valueType(t))
  case t.reprType
  of cprtBit:
    return quote do:
      `vals`.bits[CSSPropertyType(`t`)].`vs`
  of cprtHWord:
    return quote do:
      `vals`.hwords[CSSPropertyType(`t`)].`vs`
  of cprtWord:
    return quote do:
      `vals`.words[CSSPropertyType(`t`)].`vs`
  of cprtObject:
    return quote do:
      `vals`.objs[CSSPropertyType(`t`)].`vs`

macro `{}=`*(vals: CSSValues; s: static string, val: typed) =
  let t = propertyType(s).get
  let v = valueType(t)
  let vs = ident($v)
  case t.reprType
  of cprtBit:
    return quote do:
      `vals`.bits[CSSPropertyType(`t`)] = CSSValueBit(`vs`: `val`)
  of cprtHWord:
    return quote do:
      `vals`.words[CSSPropertyType(`t`)] = CSSValueHWord(`vs`: `val`)
  of cprtWord:
    return quote do:
      `vals`.words[CSSPropertyType(`t`)] = CSSValueWord(`vs`: `val`)
  of cprtObject:
    return quote do:
      `vals`.objs[CSSPropertyType(`t`)] = CSSValue(
        v: CSSValueType(`v`),
        `vs`: `val`
      )

proc inherited*(t: CSSPropertyType): bool =
  return t in InheritedProperties

proc blockify*(display: CSSDisplay): CSSDisplay =
  case display
  of DisplayBlock, DisplayTable, DisplayListItem, DisplayNone, DisplayFlowRoot,
      DisplayFlex, DisplayTableWrapper, DisplayGrid, DisplayMarker:
    return display
  of DisplayInline, DisplayInlineBlock, DisplayTableRow,
      DisplayTableRowGroup, DisplayTableColumn,
      DisplayTableColumnGroup, DisplayTableCell, DisplayTableCaption,
      DisplayTableHeaderGroup, DisplayTableFooterGroup:
    return DisplayBlock
  of DisplayInlineTable:
    return DisplayTable
  of DisplayInlineFlex:
    return DisplayFlex
  of DisplayInlineGrid:
    return DisplayGrid

proc bfcify*(overflow: CSSOverflow): CSSOverflow =
  if overflow == OverflowVisible:
    return OverflowAuto
  if overflow == OverflowClip:
    return OverflowHidden
  return overflow

const UpperAlphaMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".toPoints()
const LowerGreekMap = "αβγδεζηθικλμνξοπρστυφχψω".toPoints()
const HiraganaMap = ("あいうえおかきくけこさしすせそたちつてとなにぬねの" &
  "はひふへほまみむめもやゆよらりるれろわゐゑをん").toPoints()
const HiraganaIrohaMap = ("いろはにほへとちりぬるをわかよたれそつねならむ" &
  "うゐのおくやまけふこえてあさきゆめみしゑひもせす").toPoints()
const KatakanaMap = ("アイウエオカキクケコサシスセソタチツテトナニヌネノ" &
  "ハヒフヘホマミムメモヤユヨラリルレロワヰヱヲン").toPoints()
const KatakanaIrohaMap = ("イロハニホヘトチリヌルヲワカヨタレソツネナラム" &
  "ウヰノオクヤマケフコエテアサキユメミシヱヒモセス").toPoints()
const EarthlyBranchMap = "子丑寅卯辰巳午未申酉戌亥".toPoints()
const HeavenlyStemMap = "甲乙丙丁戊己庚辛壬癸".toPoints()

proc numToBase(n: int; map: openArray[uint32]): string =
  if n <= 0:
    return $n
  var tmp: seq[uint32] = @[]
  var n = n
  while n != 0:
    n -= 1
    tmp &= map[n mod map.len]
    n = n div map.len
  var res = ""
  for u in tmp.ritems:
    res.addUTF8(u)
  move(res)

proc numToFixed(n: int32; map: openArray[uint32]): string =
  if n in 1 .. map.len:
    return map[n - 1].toUTF8()
  return $n

proc numberAdditive(i: int32; range: Slice[int32];
    symbols: openArray[(int32, cstring)]): string =
  if i notin range:
    return $i
  var s = ""
  var n = i
  var at = 0
  while n > 0:
    if n >= symbols[at][0]:
      n -= symbols[at][0]
      s &= $symbols[at][1]
      continue
    inc at
  move(s)

type Z = cstring
const romanNumbers = [
  (1000i32, Z"M"), (900i32, Z"CM"), (500i32, Z"D"), (400i32, Z"CD"),
  (100i32, Z"C"), (90i32, Z"XC"), (50i32, Z"L"), (40i32, Z"XL"), (10i32, Z"X"),
  (9i32, Z"IX"), (5i32, Z"V"), (4i32, Z"IV"), (1i32, Z"I")
]

proc romanNumber(i: int32): string =
  return numberAdditive(i, 1i32..3999i32, romanNumbers)

proc japaneseNumber(i: int32; formal: bool): string =
  if i == 0:
    return if formal: "〇" else: "零"
  var n = i
  var s = ""
  if i < 0:
    s &= "マイナス"
    n *= -1
  let o = n
  var ss: seq[cstring] = @[]
  var d = 0
  while n > 0:
    let m = n mod 10
    if m != 0:
      case d
      of 1:
        ss.add(if formal: cstring"拾" else: "十")
        if formal:
          ss.add("壱")
      of 2:
        ss.add("百")
        if formal:
          ss.add("壱")
      of 3:
        ss.add(if formal: cstring"阡" else: "千")
        if formal:
          ss.add("壱")
      of 4:
        ss.add("万")
        ss.add(if formal: cstring"壱" else: "一")
      of 5:
        ss.add("万")
        ss.add(if formal: cstring"拾" else: "十")
      of 6:
        ss.add("万")
        ss.add("百")
      of 7:
        ss.add("万")
        ss.add(if formal: cstring"阡" else: "千")
        ss.add(if formal: cstring"壱" else: "一")
      of 8:
        ss.add("億")
        ss.add(if formal: cstring"壱" else: "一")
      of 9:
        ss.add("億")
        ss.add(if formal: cstring"拾" else: "十")
      else: discard
    case m
    of 0:
      inc d
      n = n div 10
    of 1:
      if o == n:
        ss.add(if formal: cstring"壱" else: "一")
    of 2: ss.add(if formal: cstring"弐" else: "二")
    of 3: ss.add(if formal: cstring"参" else: "三")
    of 4: ss.add("四")
    of 5: ss.add(if formal: cstring"伍" else: "五")
    of 6: ss.add("六")
    of 7: ss.add("七")
    of 8: ss.add("八")
    of 9: ss.add("九")
    else: discard
    n -= m
  for j in countdown(ss.high, 0):
    s &= $ss[j]
  move(s)

proc listMarker0(t: CSSListStyleType; i: int32): string =
  return case t
  of ListStyleTypeNone: ""
  of ListStyleTypeDisc: "•" # U+2022
  of ListStyleTypeCircle: "○" # U+25CB
  of ListStyleTypeSquare: "□" # U+25A1
  of ListStyleTypeDisclosureOpen: "▶" # U+25B6
  of ListStyleTypeDisclosureClosed: "▼" # U+25BC
  of ListStyleTypeDecimal: $i
  of ListStyleTypeUpperRoman: romanNumber(i)
  of ListStyleTypeLowerRoman: romanNumber(i).toLowerAscii()
  of ListStyleTypeUpperAlpha: numToBase(i, UpperAlphaMap)
  of ListStyleTypeLowerAlpha: numToBase(i, UpperAlphaMap).toLowerAscii()
  of ListStyleTypeLowerGreek: numToBase(i, LowerGreekMap)
  of ListStyleTypeHiragana: numToBase(i, HiraganaMap)
  of ListStyleTypeHiraganaIroha: numToBase(i, HiraganaIrohaMap)
  of ListStyleTypeKatakana: numToBase(i, KatakanaMap)
  of ListStyleTypeKatakanaIroha: numToBase(i, KatakanaIrohaMap)
  of ListStyleTypeCjkEarthlyBranch: numToFixed(i, EarthlyBranchMap)
  of ListStyleTypeCjkHeavenlyStem: numToFixed(i, HeavenlyStemMap)
  of ListStyleTypeJapaneseInformal: japaneseNumber(i, formal = false)
  of ListStyleTypeJapaneseFormal: japaneseNumber(i, formal = true)

proc listMarkerSuffix(t: CSSListStyleType): string =
  return case t
  of ListStyleTypeNone: ""
  of ListStyleTypeDisc, ListStyleTypeCircle, ListStyleTypeSquare,
      ListStyleTypeDisclosureOpen, ListStyleTypeDisclosureClosed:
    " "
  of ListStyleTypeDecimal, ListStyleTypeUpperRoman, ListStyleTypeLowerRoman,
      ListStyleTypeUpperAlpha, ListStyleTypeLowerAlpha, ListStyleTypeLowerGreek:
    ". "
  of ListStyleTypeHiragana, ListStyleTypeHiraganaIroha, ListStyleTypeKatakana,
      ListStyleTypeKatakanaIroha, ListStyleTypeCjkEarthlyBranch,
      ListStyleTypeCjkHeavenlyStem, ListStyleTypeJapaneseInformal,
      ListStyleTypeJapaneseFormal:
    "、"

proc listMarker*(t: CSSListStyleType; i: int32; suffix: bool): RefString =
  let res = newRefString(listMarker0(t, i))
  if suffix:
    res.s &= listMarkerSuffix(t)
  return res

proc quoteStart*(level: int): string =
  if level == 0:
    return "“"
  return "‘"

proc quoteEnd*(level: int): string =
  if level == 0:
    return "“"
  return "‘"

proc parseIdent(map: openArray[IdentMapItem]; tok: CSSToken): int =
  if tok.t == cttIdent:
    return map.parseEnumNoCase0(tok.s)
  return -1

proc parseIdent[T: enum](tok: CSSToken): Opt[T] =
  const IdentMap = getIdentMap(T)
  let i = IdentMap.parseIdent(tok)
  if i != -1:
    return ok(T(i))
  return err()

proc parseIdent[T: enum](ctx: var CSSParser): Opt[T] =
  return parseIdent[T](ctx.consume())

template cssLength*(n: float32): CSSLength =
  CSSLength(npx: n)

template cssLengthPerc*(n: float32): CSSLength =
  CSSLength(perc: n / 100)

const CSSLengthAuto* = CSSLength(npx: NaN, perc: NaN)
const CSSLengthZero* = CSSLength(npx: 0, perc: 0)

proc resolveLength*(u: CSSUnit; val: float32; attrs: WindowAttributes):
    CSSLength =
  return case u
  of cuAuto: CSSLengthAuto
  of cuEm, cuRem, cuCap, cuRcap, cuLh, cuRlh:
    cssLength(val * float32(attrs.ppl))
  of cuCh, cuRch: cssLength(val * float32(attrs.ppc))
  of cuIc, cuRic: cssLength(val * float32(attrs.ppc) * 2)
  of cuEx, cuRex: cssLength(val * float32(attrs.ppc) / 2)
  of cuPx: cssLength(val)
  of cuCm: cssLength(val * 37.8)
  of cuMm: cssLength(val * 3.78)
  of cuIn: cssLength(val * 96)
  of cuPc: cssLength(val * 16)
  of cuPt: cssLength(val * 4 / 3)
  of cuDvw, cuVw, cuDvi, cuVi: cssLength(float32(attrs.widthPx) * val / 100)
  of cuDvh, cuVh, cuDvb, cuVb: cssLength(float32(attrs.heightPx) * val / 100)
  of cuVmin, cuSvmin, cuLvmin, cuDvmin:
    cssLength(min(attrs.widthPx, attrs.heightPx) / 100 * val)
  of cuVmax, cuSvmax, cuLvmax, cuDvmax:
    cssLength(max(attrs.widthPx, attrs.heightPx) / 100 * val)

proc parseLength(tok: CSSToken; attrs: WindowAttributes): Opt[CSSLength] =
  if tok.dt in CSSDimensionType(CSSUnit.low)..CSSDimensionType(CSSUnit.high):
    return ok(resolveLength(tok.dt, tok.num, attrs))
  return err()

proc parseDimensionValues*(s: string): Opt[CSSLength] =
  var i = s.skipBlanks(0)
  if i >= s.len or s[i] notin AsciiDigit:
    return err()
  var n = 0f64
  while s[i] in AsciiDigit:
    n *= 10
    n += float32(decValue(s[i]))
    inc i
    if i >= s.len:
      return ok(cssLength(n))
  if s[i] == '.':
    inc i
    if i >= s.len:
      return ok(cssLength(n))
    var d = 1
    while i < s.len and s[i] in AsciiDigit:
      n += float32(decValue(s[i])) / float32(d)
      inc d
      inc i
  if i < s.len and s[i] == '%':
    return ok(cssLengthPerc(n))
  ok(cssLength(n))

# The return value is in degrees.
proc parseAngle(tok: CSSToken): Opt[float32] =
  case tok.dt
  of catDeg: return ok(tok.num)
  of catGrad: return ok(tok.num * 0.9f32)
  of catRad: return ok(radToDeg(tok.num))
  of catTurn: return ok(tok.num * 360f32)
  else: return err()

template calcSumNumber(num: float32): CSSCalcSum =
  CSSCalcSum(t: ccstNumber, n: num)

proc parseCalcValue(ctx: var CSSParser; attrs: ptr WindowAttributes):
    Opt[CSSCalcSum] =
  ?ctx.skipBlanksCheckHas()
  case (let t = ctx.peekTokenType(); t)
  of cttNumber:
    let tok = ctx.consume()
    return ok(calcSumNumber(tok.num))
  of cttIdent:
    let tok = ctx.consume()
    let keyword = ?parseEnumNoCase[CSSCalcKeyword](tok.s)
    case keyword
    of ccskE: return ok(calcSumNumber(E))
    of ccskPi: return ok(calcSumNumber(PI))
    of ccskInfinity: return ok(calcSumNumber(Inf))
    of ccskMinusInfinity: return ok(calcSumNumber(-Inf))
    of ccskNaN: return err() #TODO it seems nobody implements this yet?
  of cttLparen, cttFunction:
    if t == cttFunction and ctx.peekToken().ft != cftCalc:
      return err()
    ctx.seekToken()
    var res = ctx.parseCalcSum(attrs)
    if ctx.has() and ctx.peekTokenType() != cttRparen:
      res = Opt[CSSCalcSum].err()
    ctx.skipFunction()
    return res
  of cttPercentage:
    let tok = ctx.consume()
    let length = cssLengthPerc(tok.num)
    return ok(CSSCalcSum(t: ccstLength, l: length))
  of cttDimension:
    let tok = ctx.consume()
    if deg := parseAngle(tok):
      return ok(CSSCalcSum(t: ccstDegree, deg: deg))
    if attrs == nil:
      return err()
    let length = ?parseLength(tok, attrs[])
    return ok(CSSCalcSum(t: ccstLength, l: length))
  else:
    return err()

proc parseCalcProduct(ctx: var CSSParser; attrs: ptr WindowAttributes):
    Opt[CSSCalcSum] =
  var a = ?ctx.parseCalcValue(attrs)
  while ctx.skipBlanksCheckHas().isOk:
    let t = ctx.peekTokenType()
    if t notin {cttStar, cttSlash}:
      break
    let delim = ctx.consume().t
    var b = ?ctx.parseCalcProduct(attrs)
    var n = 0f32
    if delim == cttSlash: # division: b must be a number
      if b.t != ccstNumber or b.n == 0:
        return err()
      n = 1 / b.n
    else: # multiplication: either can be length, but not both
      if b.t != ccstNumber:
        swap(a, b)
      if b.t != ccstNumber:
        return err()
      n = b.n
    case a.t
    of ccstLength:
      a.l.npx *= n
      a.l.perc *= n
    of ccstNumber:
      a.n *= n
    of ccstDegree:
      a.deg *= n
  ok(a)

proc parseCalcSum(ctx: var CSSParser; attrs: ptr WindowAttributes):
    Opt[CSSCalcSum] =
  var a = ?ctx.parseCalcProduct(attrs)
  while ctx.skipBlanksCheckHas().isOk:
    let t = ctx.peekTokenType()
    if t notin {cttPlus, cttMinus}:
      break
    let mul = if ctx.consume().t == cttPlus: 1f32 else: -1f32
    var b = ?ctx.parseCalcProduct(attrs)
    if a.t != b.t:
      # cannot add length to number
      return err()
    case b.t
    of ccstLength:
      a.l.npx += mul * b.l.npx
      a.l.perc += mul * b.l.perc
    of ccstDegree:
      a.deg += mul * b.deg
    of ccstNumber:
      a.n += mul * b.n
  ok(a)

# Note: `attrs' may be nil, in that case only numbers are accepted.
proc parseCalc(ctx: var CSSParser; attrs: ptr WindowAttributes):
    Opt[CSSCalcSum] =
  var res = ctx.parseCalcSum(attrs)
  if ctx.has() and ctx.peekTokenType() != cttRparen:
    res = Opt[CSSCalcSum].err()
  ctx.skipFunction()
  res

proc parseColorComponent(ctx: var CSSParser): Opt[CSSToken] =
  ?ctx.skipBlanksCheckHas()
  case ctx.peekTokenType()
  of cttFunction:
    if ctx.peekToken().ft != cftCalc:
      ctx.seek()
      return err()
    ctx.seekToken()
    let res = ?ctx.parseCalc(nil)
    case res.t
    of ccstNumber: return ok(cssNumberToken(res.n))
    of ccstDegree: return ok(cssDimensionToken(res.deg, catDeg))
    of ccstLength: return ok(cssPercentageToken(res.l.perc))
  of cttNumber, cttPercentage, cttDimension:
    return ok(ctx.consume())
  of cttIdent:
    if not ctx.peekIdentNoCase("none"):
      return err()
    return ok(ctx.consume())
  else: return err()

proc parseRGBComponent(tok: CSSToken): Opt[uint8] =
  case tok.t
  of cttDimension:
    return err()
  of cttIdent: # none
    return ok(0u8)
  else:
    var res = tok.num
    if tok.t == cttPercentage:
      res *= 2.55
    res += 0.5
    ok(uint8(clamp(res, 0, 255))) # number

proc parseHue(tok: CSSToken): Opt[uint32] =
  var n = 0i32
  case tok.t
  of cttNumber:
    n = tok.toi
  of cttIdent: discard # none -> 0
  of cttDimension:
    n = int32(?parseAngle(tok))
  else: return err()
  n = n mod 360
  if n < 0:
    n = n + 360
  return ok(uint32(n))

proc parseSatOrLight(tok: CSSToken): Opt[uint8] =
  if tok.t in {cttNumber, cttPercentage}:
    return ok(uint8(clamp(tok.toi, 0i32, 100i32)))
  return err()

# For rgb(), rgba(), hsl(), hsla().
proc parseLegacyColorFun(ctx: var CSSParser; ft: CSSFunctionType):
    Opt[CSSColor] =
  let v1 = ?ctx.parseColorComponent()
  ?ctx.skipBlanksCheckHas()
  let legacy = ctx.peekTokenType() == cttComma
  if legacy:
    ctx.seekToken()
  let v2 = ?ctx.parseColorComponent()
  if legacy:
    ?ctx.skipBlanksCheckHas()
    if ctx.consume().t != cttComma:
      return err()
  let v3 = ?ctx.parseColorComponent()
  if legacy and (v1.t == cttIdent or v2.t == cttIdent or v3.t == cttIdent):
    return err() # legacy doesn't accept "none"
  var a = 255u8
  if ctx.skipBlanksCheckHas().isOk and ctx.peekTokenType() != cttRparen:
    if ctx.peekTokenType() != (if legacy: cttComma else: cttSlash):
      return err()
    ctx.seekToken()
    let v4 = ?ctx.parseColorComponent()
    if v4.t in {cttIdent, cttDimension}:
      return err()
    a = uint8(clamp(v4.num, 0, 1) * 255)
  case ft
  of cftRgb, cftRgba:
    if legacy and (v1.t != v2.t or v2.t != v3.t):
      return err()
    let r = ?parseRGBComponent(v1)
    let g = ?parseRGBComponent(v2)
    let b = ?parseRGBComponent(v3)
    return ok(rgba(r, g, b, a).cssColor())
  of cftHsl, cftHsla:
    if legacy and (v1.t == cttIdent or v2.t != cttPercentage or
        v3.t != cttPercentage):
      return err()
    let h = ?parseHue(v1)
    let s = ?parseSatOrLight(v2)
    let l = ?parseSatOrLight(v3)
    return ok(hsla(h, s, l, a).cssColor())
  else:
    return err()

proc ansiColorNumeric(n: int32): Opt[CSSColor] =
  if n < 0 or n > 255:
    return err()
  ok(ANSIColor(n).cssColor())

# syntax: -cha-ansi( number | ident )
# where number is an ANSI color (0..255)
# and ident is in NameTable and may start with "bright-"
proc parseANSI(ctx: var CSSParser): Opt[CSSColor] =
  ?ctx.skipBlanksCheckHas()
  let tok = ctx.consume()
  case tok.t
  of cttNumber:
    return ansiColorNumeric(tok.toi)
  of cttFunction:
    if tok.ft != cftCalc:
      ctx.skipFunction()
      return err()
    let res = ?ctx.parseCalc(nil)
    if res.t == ccstNumber:
      return ansiColorNumeric(int32(res.n))
  of cttIdent:
    var name = tok.s
    if name.equalsIgnoreCase("default"):
      return ok(defaultColor.cssColor())
    var bright = false
    if name.startsWithIgnoreCase("bright-"):
      bright = true
      name = name.substr("bright-".len)
    const NameTable = [
      "black",
      "red",
      "green",
      "yellow",
      "blue",
      "magenta",
      "cyan",
      "white"
    ]
    for i, it in NameTable.mypairs:
      if it.equalsIgnoreCase(name):
        var i = int(i)
        if bright:
          i += 8
        return ok(ANSIColor(i).cssColor())
  else: discard
  return err()

proc parseColor*(ctx: var CSSParser): Opt[CSSColor] =
  ?ctx.skipBlanksCheckHas()
  let tok = ctx.consume()
  case tok.t
  of cttHash:
    let c = ?parseHexColor(tok.s)
    return ok(c.cssColor())
  of cttIdent:
    if tok.s.equalsIgnoreCase("transparent"):
      return ok(rgba(0, 0, 0, 0).cssColor())
    if x := namedRGBColor(tok.s):
      return ok(x.cssColor())
    elif tok.s.equalsIgnoreCase("canvas") or
        tok.s.equalsIgnoreCase("canvastext"):
      # Not really compliant, but if you're setting text color to
      # canvas you're doing it wrong anyway.
      return ok(defaultColor.cssColor())
    else:
      return err()
  of cttFunction:
    var res = case tok.ft
    of cftRgb, cftRgba, cftHsl, cftHsla: ctx.parseLegacyColorFun(tok.ft)
    of cftChaAnsi: ctx.parseANSI()
    else: Opt[CSSColor].err()
    if ctx.has() and ctx.peekTokenType() != cttRparen:
      res = Opt[CSSColor].err()
    ctx.skipFunction()
    return res
  else:
    return err()

proc parseLength*(ctx: var CSSParser; attrs: WindowAttributes;
    hasAuto = true; allowNegative = true): Opt[CSSLength] =
  ?ctx.skipBlanksCheckHas()
  case (let tok = ctx.consume(); tok.t)
  of cttNumber:
    if tok.num == 0:
      return ok(CSSLengthZero)
  of cttPercentage:
    let n = tok.num
    if not allowNegative and n < 0:
      return err()
    return ok(cssLengthPerc(n))
  of cttDimension:
    if not allowNegative and tok.num < 0:
      return err()
    return parseLength(tok, attrs)
  of cttIdent:
    if hasAuto and tok.s.equalsIgnoreCase("auto"):
      return ok(CSSLengthAuto)
  of cttFunction:
    if tok.ft != cftCalc:
      ctx.skipFunction()
      return err()
    let res = ?ctx.parseCalc(unsafeAddr attrs)
    if res.t == ccstLength:
      return ok(res.l)
  else: discard
  err()

proc parseLength*(toks: openArray[CSSToken]; attrs: WindowAttributes;
    hasAuto = true; allowNegative = true): Opt[CSSLength] =
  var ctx = initCSSParser(toks)
  return ctx.parseLength(attrs, hasAuto, allowNegative)

proc parseAbsoluteLength(tok: CSSToken; attrs: WindowAttributes):
    Opt[CSSLength] =
  case tok.t
  of cttNumber:
    if tok.num == 0:
      return ok(CSSLengthZero)
  of cttDimension:
    if tok.num >= 0:
      return parseLength(tok, attrs)
  else: discard
  err()

proc parseQuotes(ctx: var CSSParser): Opt[CSSQuotes] =
  case ctx.peekTokenType()
  of cttIdent:
    let tok = ctx.consume()
    if tok.s.equalsIgnoreCase("auto"):
      return ok(nil)
    elif tok.s.equalsIgnoreCase("none"):
      return ok(CSSQuotes())
    return err()
  of cttString:
    var res = CSSQuotes()
    while ctx.has():
      ?ctx.skipBlanksCheckHas()
      if ctx.peekTokenType() != cttString:
        return err()
      let tok1 = ctx.consume()
      ?ctx.skipBlanksCheckHas()
      if ctx.peekTokenType() != cttString:
        return err()
      let tok2 = ctx.consume()
      res.qs.add((newRefString(tok1.s), newRefString(tok2.s)))
    return ok(move(res))
  else:
    return err()

proc parseContent(ctx: var CSSParser): Opt[seq[CSSContent]] =
  var res: seq[CSSContent] = @[]
  ctx.skipBlanks()
  while ctx.has():
    case (let tok = ctx.consume(); tok.t)
    of cttIdent:
      if tok.s == "/":
        break
      elif tok.s.equalsIgnoreCase("open-quote"):
        res.add(CSSContent(t: ContentOpenQuote))
      elif tok.s.equalsIgnoreCase("no-open-quote"):
        res.add(CSSContent(t: ContentNoOpenQuote))
      elif tok.s.equalsIgnoreCase("close-quote"):
        res.add(CSSContent(t: ContentCloseQuote))
      elif tok.s.equalsIgnoreCase("no-close-quote"):
        res.add(CSSContent(t: ContentNoCloseQuote))
    of cttString:
      res.add(CSSContent(t: ContentString, s: newRefString(tok.s)))
    of cttWhitespace:
      discard
    of cttFunction:
      if tok.ft == cftCounter:
        ctx.skipBlanks()
        if ctx.peekTokenType() != cttIdent:
          ctx.skipFunction()
          return err()
        let name = ctx.consume().s.toAtom()
        var style = ListStyleTypeDecimal
        ctx.skipBlanks()
        if ctx.has() and (let tok = ctx.consume(); tok.t != cttRparen):
          if tok.t != cttComma:
            ctx.skipFunction()
            return err()
          ctx.skipBlanks()
          if ctx.has() and (let tok = ctx.consume(); tok.t != cttRparen):
            # stick with decimal if not found
            style = parseIdent[CSSListStyleType](tok).get(style)
            ctx.skipBlanks()
            if ctx.consume().t != cttRparen:
              ctx.skipFunction()
              return err()
        res.add(CSSContent(
          t: ContentCounter,
          counter: name,
          counterStyle: style
        ))
    else:
      return err()
  ok(res)

proc parseFontWeight(ctx: var CSSParser): Opt[int32] =
  let tok = ctx.consume()
  case tok.t
  of cttIdent:
    const FontWeightMap = {
      "bold": 700,
      "bolder": 700,
      "lighter": 400,
      "normal": 400
    }
    let i = FontWeightMap.parseIdent(tok)
    if i != -1:
      return ok(int32(i))
  elif tok.t == cttNumber:
    let i = tok.toi
    if i in 1i32..1000i32:
      return ok(i)
  return err()

proc parseTextDecoration(ctx: var CSSParser): Opt[set[CSSTextDecoration]] =
  var s: set[CSSTextDecoration] = {}
  while ctx.has():
    let tok = ctx.consume()
    if tok.t == cttIdent:
      let td = ?parseIdent[CSSTextDecoration](tok)
      if td == TextDecorationNone:
        if s != {}:
          return err()
        return ok(s)
      s.incl(td)
  return ok(s)

proc parseCounterSet(ctx: var CSSParser; n: int32): Opt[seq[CSSCounterSet]] =
  var res: seq[CSSCounterSet] = @[]
  while ctx.has():
    if ctx.peekTokenType() != cttIdent:
      return err()
    let name = ctx.consume().s.toAtom()
    var r = CSSCounterSet(name: name)
    ctx.skipBlanks()
    if not ctx.has() or ctx.peekTokenType() == cttWhitespace:
      r.num = n
      res.add(r)
    elif ctx.peekTokenType() == cttNumber:
      r.num = ctx.consume().toi
      res.add(r)
    else:
      return err()
  return ok(move(res))

proc parseMaxSize(ctx: var CSSParser; attrs: WindowAttributes):
    Opt[CSSLength] =
  ?ctx.skipBlanksCheckHas()
  if ctx.peekTokenType() == cttIdent and
      ctx.consume().s.equalsIgnoreCase("none"):
    return ok(CSSLengthAuto)
  return ctx.parseLength(attrs, hasAuto = true, allowNegative = false)

#TODO should be URL (parsed with baseurl of document...)
proc parseURL*(ctx: var CSSParser; tok: CSSToken; src = false): Opt[string] =
  case tok.t
  of cttUrl: return ok(tok.s)
  of cttString:
    if src:
      return err()
    return ok(tok.s)
  of cttFunction:
    if tok.ft != cftUrl and (not src or tok.ft != cftSrc):
      return err()
    ?ctx.skipBlanksCheckHas()
    let tok = ctx.consume()
    if tok.t != cttString:
      return err()
    ctx.skipBlanks()
    if ctx.has() and ctx.consume().t != cttRparen:
      ctx.skipFunction()
      return err()
    return ok(tok.s)
  else: return err()

#TODO this should be bg-image, add gradient, etc etc
proc parseImage(ctx: var CSSParser): Opt[NetworkBitmap] =
  #TODO bg-image only
  ?ctx.skipBlanksCheckHas()
  let tok = ctx.consume()
  if tok.t == cttIdent and tok.s.equalsIgnoreCase("none"):
    return ok(nil)
  let url = ?ctx.parseURL(tok, src = true)
  #TODO do something with the URL
  discard url
  return ok(NetworkBitmap(cacheId: -1, imageId: -1))

proc parseInteger(ctx: var CSSParser; range: Slice[int32]): Opt[int32] =
  let i = ?ctx.consumeInt()
  if i in range:
    return ok(i)
  return err()

proc parseZIndex(ctx: var CSSParser): Opt[CSSZIndex] =
  if ctx.peekIdentNoCase("auto"):
    ctx.seekToken()
    return ok(CSSZIndex(auto: true))
  let n = ?ctx.parseInteger(-65534i32 .. 65534i32)
  return ok(CSSZIndex(num: n))

proc parseNumber(ctx: var CSSParser; range: Slice[float32]): Opt[float32] =
  let tok = ctx.peekToken()
  if tok.t == cttNumber:
    if (let n = tok.num; n in range):
      ctx.seekToken()
      return ok(n)
  return err()

type LineWidthKeyword = enum
  lwkThin = (1, "thin")
  lwkMedium = (2, "medium")
  lwkThick = (3, "thick")

proc parseLineWidth(ctx: var CSSParser; attrs: WindowAttributes): Opt[float32] =
  let tok = ctx.peekToken()
  if tok.t == cttIdent:
    ctx.seek()
    let s = ?parseEnumNoCase[LineWidthKeyword](tok.s)
    return ok(float32(s))
  let l = ?ctx.parseLength(attrs, hasAuto = false, allowNegative = false)
  if l.isPerc:
    return err()
  ok(l.npx)

proc makeEntry*(t: CSSPropertyType; obj: CSSValue): CSSComputedEntry =
  return CSSComputedEntry(et: ceObject, p: t, obj: obj)

proc makeEntry(t: CSSPropertyType; hword: CSSValueHWord): CSSComputedEntry =
  return CSSComputedEntry(et: ceHWord, p: t, hword: hword)

proc makeEntry(t: CSSPropertyType; word: CSSValueWord): CSSComputedEntry =
  return CSSComputedEntry(et: ceWord, p: t, word: word)

proc makeEntry*(t: CSSPropertyType; bit: CSSValueBit): CSSComputedEntry =
  return CSSComputedEntry(et: ceBit, p: t, bit: bit.dummy)

proc makeEntry(t: CSSPropertyType; global: CSSGlobalType): CSSComputedEntry =
  return CSSComputedEntry(et: ceGlobal, p: t, global: global)

proc makeEntry*(t: CSSPropertyType; length: CSSLength): CSSComputedEntry =
  makeEntry(t, CSSValueWord(length: length))

proc makeEntry*(t: CSSPropertyType; color: CSSColor): CSSComputedEntry =
  makeEntry(t, CSSValueWord(color: color))

proc makeEntry(t: CSSPropertyType; zIndex: CSSZIndex): CSSComputedEntry =
  makeEntry(t, CSSValueWord(zIndex: zIndex))

proc makeEntry*(t: CSSPropertyType; integer: int32): CSSComputedEntry =
  makeEntry(t, CSSValueHWord(integer: integer))

proc makeEntry*(t: CSSPropertyType; number: float32): CSSComputedEntry =
  makeEntry(t, CSSValueHWord(number: number))

proc makeEntry(t: CSSPropertyType; image: NetworkBitmap): CSSComputedEntry =
  makeEntry(t, CSSValue(v: cvtImage, image: image))

template makeEntry*[T: enum|set](t: CSSPropertyType; val: T): CSSComputedEntry =
  CSSComputedEntry(et: ceBit, p: t, bit: cast[uint8](val))

proc parseDeclWithVar0*(toks: openArray[CSSToken]): seq[CSSVarItem] =
  var ctx = initCSSParser(toks)
  ctx.skipBlanks()
  var items: seq[CSSVarItem] = @[]
  while ctx.has():
    let tok = ctx.consume()
    if tok.t == cttFunction and tok.ft == cftVar:
      if ctx.skipBlanksCheckHas().isErr:
        return @[]
      let tok = ctx.consume()
      if tok.t != cttIdent:
        return @[]
      let name = tok.s.substr(2).toAtom()
      items.add(CSSVarItem(name: name))
      ctx.skipBlanks()
      var toks: seq[CSSToken] = @[]
      if ctx.has() and (let tok = ctx.consume(); tok.t != cttRparen):
        if tok.t != cttComma:
          return @[]
        ctx.skipBlanks()
        while ctx.has() and (let tok = ctx.consume(); tok.t != cttRparen):
          toks.add(tok)
      items[^1].toks = move(toks)
    else:
      if items.len == 0 or items[^1].name != CAtomNull:
        items.add(CSSVarItem(name: CAtomNull))
      items[^1].toks.add(tok)
  move(items)

proc parseDeclWithVar*(p: CSSAnyPropertyType; value: openArray[CSSToken]):
    Opt[CSSComputedEntry] =
  var items = parseDeclWithVar0(value)
  if items.len == 0:
    return err()
  let cvar = CSSVarEntry(items: move(items))
  return ok(CSSComputedEntry(et: ceVar, p: p, cvar: cvar))

proc parseValue(ctx: var CSSParser; t: CSSPropertyType;
    entry: var CSSComputedEntry; attrs: WindowAttributes): Opt[void] =
  ?ctx.skipBlanksCheckHas()
  let v = valueType(t)
  entry = case v
  of cvtDisplay: makeEntry(t, ?parseIdent[CSSDisplay](ctx))
  of cvtWhiteSpace: makeEntry(t, ?parseIdent[CSSWhiteSpace](ctx))
  of cvtWordBreak: makeEntry(t, ?parseIdent[CSSWordBreak](ctx))
  of cvtListStyleType: makeEntry(t, ?parseIdent[CSSListStyleType](ctx))
  of cvtFontStyle: makeEntry(t, ?parseIdent[CSSFontStyle](ctx))
  of cvtColor: makeEntry(t, ?ctx.parseColor())
  of cvtLength:
    case t
    of cptMinWidth, cptMinHeight:
      makeEntry(t, ?ctx.parseLength(attrs, hasAuto = true,
        allowNegative = false))
    of cptMaxWidth, cptMaxHeight:
      makeEntry(t, ?ctx.parseMaxSize(attrs))
    of cptPaddingLeft, cptPaddingRight, cptPaddingTop, cptPaddingBottom:
      makeEntry(t, ?ctx.parseLength(attrs, hasAuto = false,
        allowNegative = false))
    #TODO content for flex-basis
    else:
      makeEntry(t, ?ctx.parseLength(attrs, hasAuto = true,
        allowNegative = true))
  of cvtContent: makeEntry(t, CSSValue(v: v, content: ?ctx.parseContent()))
  of cvtInteger:
    case t
    of cptFontWeight: makeEntry(t, ?ctx.parseFontWeight())
    of cptChaColspan: makeEntry(t, ?ctx.parseInteger(1i32 .. 1000i32))
    of cptChaRowspan: makeEntry(t, ?ctx.parseInteger(0i32 .. 65534i32))
    else: return err()
  of cvtZIndex: makeEntry(t, ?ctx.parseZIndex())
  of cvtTextDecoration: makeEntry(t, ?ctx.parseTextDecoration())
  of cvtVerticalAlign: makeEntry(t, ?parseIdent[CSSVerticalAlign](ctx))
  of cvtTextAlign: makeEntry(t, ?parseIdent[CSSTextAlign](ctx))
  of cvtListStylePosition: makeEntry(t, ?parseIdent[CSSListStylePosition](ctx))
  of cvtPosition: makeEntry(t, ?parseIdent[CSSPosition](ctx))
  of cvtCaptionSide: makeEntry(t, ?parseIdent[CSSCaptionSide](ctx))
  of cvtBorderCollapse: makeEntry(t, ?parseIdent[CSSBorderCollapse](ctx))
  of cvtBorderStyle: makeEntry(t, ?parseIdent[CSSBorderStyle](ctx))
  of cvtQuotes: makeEntry(t, CSSValue(v: v, quotes: ?ctx.parseQuotes()))
  of cvtCounterSet:
    let n = if t == cptCounterIncrement: 1i32 else: 0i32
    makeEntry(t, CSSValue(v: v, counterSet: ?ctx.parseCounterSet(n)))
  of cvtImage: makeEntry(t, CSSValue(v: v, image: ?ctx.parseImage()))
  of cvtFloat: makeEntry(t, ?parseIdent[CSSFloat](ctx))
  of cvtVisibility: makeEntry(t, ?parseIdent[CSSVisibility](ctx))
  of cvtBoxSizing: makeEntry(t, ?parseIdent[CSSBoxSizing](ctx))
  of cvtClear: makeEntry(t, ?parseIdent[CSSClear](ctx))
  of cvtTextTransform: makeEntry(t, ?parseIdent[CSSTextTransform](ctx))
  of cvtBgcolorIsCanvas: return err() # internal value
  of cvtFlexDirection: makeEntry(t, ?parseIdent[CSSFlexDirection](ctx))
  of cvtFlexWrap: makeEntry(t, ?parseIdent[CSSFlexWrap](ctx))
  of cvtNumber:
    if t == cptOpacity:
      makeEntry(t, ?ctx.parseNumber(0f32..1f32))
    else: # flex-grow, flex-shrink
      makeEntry(t, ?ctx.parseNumber(0f32..float32.high))
  of cvtOverflow: makeEntry(t, ?parseIdent[CSSOverflow](ctx))
  of cvtLineWidth: makeEntry(t, ?ctx.parseLineWidth(attrs))
  ok()

proc getInitialColor(t: CSSPropertyType): CSSColor =
  if t == cptBackgroundColor:
    return rgba(0, 0, 0, 0).cssColor()
  return defaultColor.cssColor()

proc getInitialLength(t: CSSPropertyType): CSSLength =
  case t
  of cptWidth, cptHeight, cptLeft, cptRight, cptTop, cptBottom, cptMaxWidth,
      cptMaxHeight, cptMinWidth, cptMinHeight, cptFlexBasis:
    return CSSLengthAuto
  of cptFontSize:
    return cssLength(16)
  else:
    return CSSLengthZero

proc getInitialInteger(t: CSSPropertyType): int32 =
  case t
  of cptChaColspan, cptChaRowspan:
    return 1
  of cptFontWeight:
    return 400 # normal
  else:
    return 0

proc getInitialNumber(t: CSSPropertyType): float32 =
  if t in {cptFlexShrink, cptOpacity}:
    return 1
  return 0

proc getInitialTable(): array[CSSPropertyType, CSSValue] =
  result = array[CSSPropertyType, CSSValue].default
  for t in CSSPropertyType:
    result[t] = CSSValue(v: valueType(t))

let defaultTable = getInitialTable()

template getDefault(t: CSSPropertyType): CSSValue =
  defaultTable[t]

proc getDefaultHWord(t: CSSPropertyType): CSSValueHWord =
  case valueType(t)
  of cvtInteger: return CSSValueHWord(integer: getInitialInteger(t))
  of cvtNumber: return CSSValueHWord(number: getInitialNumber(t))
  of cvtLineWidth: return CSSValueHWord(lineWidth: 1) # medium
  else: return CSSValueHWord(dummy: 0)

proc getDefaultWord(t: CSSPropertyType): CSSValueWord =
  case valueType(t)
  of cvtColor: return CSSValueWord(color: getInitialColor(t))
  of cvtLength: return CSSValueWord(length: getInitialLength(t))
  of cvtZIndex: return CSSValueWord(zIndex: CSSZIndex(auto: true))
  else: return CSSValueWord(dummy: 0)

proc makeDefaultEntry(t: CSSPropertyType): CSSComputedEntry =
  case t.reprType
  of cprtBit: return makeEntry(t, CSSValueBit(dummy: 0))
  of cprtHWord: return makeEntry(t, getDefaultHWord(t))
  of cprtWord: return makeEntry(t, getDefaultWord(t))
  of cprtObject: return makeEntry(t, getDefault(t))

const ShorthandMap = [
  cstNone: @[],
  cstAll: @[],
  cstMargin: @[cptMarginTop, cptMarginRight, cptMarginBottom, cptMarginLeft],
  cstPadding: @[cptPaddingTop, cptPaddingRight, cptPaddingBottom,
    cptPaddingLeft],
  cstBorderStyle: @[cptBorderTopStyle, cptBorderRightStyle,
    cptBorderBottomStyle, cptBorderLeftStyle],
  cstBorderColor: @[cptBorderTopColor, cptBorderRightColor,
    cptBorderBottomColor, cptBorderLeftColor],
  cstBorderWidth: @[cptBorderTopWidth, cptBorderRightWidth,
    cptBorderBottomWidth, cptBorderLeftWidth],
  cstBackground: @[cptBackgroundColor, cptBackgroundImage],
  cstListStyle: @[cptListStylePosition, cptListStyleType],
  cstFlex: @[cptFlexGrow, cptFlexShrink, cptFlexBasis],
  cstFlexFlow: @[cptFlexDirection, cptFlexWrap],
  cstOverflow: @[cptOverflowX, cptOverflowY],
  cstVerticalAlign: @[cptVerticalAlign, cptVerticalAlignLength],
  cstBorderSpacing: @[cptBorderSpacingInline, cptBorderSpacingBlock],
  cstBorderBottom: @[cptBorderBottomStyle, cptBorderBottomColor,
    cptBorderBottomWidth],
  cstBorderLeft: @[cptBorderLeftStyle, cptBorderLeftColor, cptBorderLeftWidth],
  cstBorderRight: @[cptBorderRightStyle, cptBorderRightColor,
    cptBorderRightWidth],
  cstBorderTop: @[cptBorderTopStyle, cptBorderTopColor, cptBorderTopWidth],
  cstBorder: @[cptBorderTopStyle, cptBorderRightStyle, cptBorderBottomStyle,
    cptBorderLeftStyle, cptBorderTopColor, cptBorderRightColor,
    cptBorderBottomColor, cptBorderLeftColor, cptBorderTopWidth,
    cptBorderRightWidth, cptBorderBottomWidth, cptBorderLeftWidth],
]

proc parseBorder(ctx: var CSSParser; sh: CSSShorthandType;
    attrs: WindowAttributes; res: var seq[CSSComputedEntry]): Opt[void] =
  var style = makeDefaultEntry(cptBorderLeftStyle)
  var color = makeDefaultEntry(cptBorderLeftColor)
  var width = makeDefaultEntry(cptBorderLeftWidth)
  var nstyle = 0u
  var ncolor = 0u
  var nwidth = 0u
  while ctx.has():
    case ctx.peekTokenType()
    of cttHash:
      color = makeEntry(cptBorderLeftColor, ?ctx.parseColor())
      inc ncolor
    of cttIdent:
      let s = ctx.peekToken().s
      if x := parseEnumNoCase[CSSBorderStyle](s):
        ctx.seek()
        style = makeEntry(cptBorderLeftStyle, x)
        inc nstyle
      elif x := parseEnumNoCase[LineWidthKeyword](s):
        ctx.seek()
        width = makeEntry(cptBorderLeftWidth, float32(x))
        inc nwidth
      else:
        color = makeEntry(cptBorderLeftColor, ?ctx.parseColor())
        inc ncolor
    of cttFunction:
      if ctx.peekToken().ft == cftCalc:
        width = makeEntry(cptBorderLeftWidth, ?ctx.parseLineWidth(attrs))
        inc nwidth
      else:
        color = makeEntry(cptBackgroundColor, ?ctx.parseColor())
        inc ncolor
    of cttDimension, cttNumber:
      width = makeEntry(cptBorderLeftWidth, ?ctx.parseLineWidth(attrs))
      inc nwidth
    else:
      return err()
    ctx.skipBlanks()
  if ncolor > 1 or nwidth > 1 or nstyle > 1:
    return err()
  for t in ShorthandMap[sh]:
    case valueType(t)
    of cvtBorderStyle:
      style.p = t
      res.add(style)
    of cvtColor:
      color.p = t
      res.add(color)
    of cvtLineWidth:
      width.p = t
      res.add(width)
    else: discard
  return ctx.skipBlanksCheckDone()

proc parseBoxShorthand(ctx: var CSSParser; props: openArray[CSSPropertyType];
    attrs: WindowAttributes; res: var seq[CSSComputedEntry]): Opt[void] =
  var entries: seq[CSSComputedEntry] = @[]
  for i, t in props:
    if ctx.skipBlanksCheckHas().isErr:
      break
    var entry: CSSComputedEntry
    ?ctx.parseValue(t, entry, attrs)
    entries.add(entry)
  case entries.len
  of 1: # top, bottom, left, right
    for t in props:
      entries[0].p = t
      res.add(entries[0])
  of 2: # top, bottom | left, right
    for i, t in props.mypairs:
      entries[i mod 2].p = t
      res.add(entries[i mod 2])
  of 3: # top | left, right | bottom
    for i, t in props.mypairs:
      let j = if i == 0:
        0 # top
      elif i == 2:
        2 # bottom
      else:
        1 # left, right
      entries[j].p = t
      res.add(entries[j])
  of 4: # top | right | bottom | left
    res.add(entries)
  else: discard
  return ctx.skipBlanksCheckDone()

proc parseBackground(ctx: var CSSParser; attrs: WindowAttributes;
    res: var seq[CSSComputedEntry]): Opt[void] =
  var color = makeDefaultEntry(cptBackgroundColor)
  var image = makeDefaultEntry(cptBackgroundImage)
  while ctx.has():
    case ctx.peekTokenType()
    of cttHash:
      color = makeEntry(cptBackgroundColor, ?ctx.parseColor())
    of cttString:
      image = makeEntry(cptBackgroundImage, ?ctx.parseImage())
    of cttIdent:
      if ctx.peekIdentNoCase("none"):
        image = makeEntry(cptBackgroundImage, ?ctx.parseImage())
      elif x := ctx.parseColor():
        color = makeEntry(cptBackgroundColor, x)
    of cttFunction:
      if ctx.peekToken().ft == cftUrl:
        image = makeEntry(cptBackgroundImage, ?ctx.parseImage())
      elif x := ctx.parseColor():
        color = makeEntry(cptBackgroundColor, x)
    else:
      #TODO when we implement the other shorthands too
      #return err()
      while ctx.has() and ctx.peekTokenType() != cttWhitespace:
        ctx.seek()
    ctx.skipBlanks()
  res.add(color)
  res.add(image)
  return ctx.skipBlanksCheckDone()

proc parseListStyle(ctx: var CSSParser; attrs: WindowAttributes;
    res: var seq[CSSComputedEntry]): Opt[void] =
  var typeVal = CSSValueBit()
  var positionVal = CSSValueBit()
  while ctx.skipBlanksCheckHas().isOk:
    let tok = ctx.consume()
    if r := parseIdent[CSSListStylePosition](tok):
      positionVal.listStylePosition = r
    elif r := parseIdent[CSSListStyleType](tok):
      typeVal.listStyleType = r
    else:
      while ctx.has() and ctx.peekTokenType() != cttWhitespace:
        ctx.seek()
      #TODO list-style-image
      #return err()
  res.add(makeEntry(cptListStylePosition, positionVal))
  res.add(makeEntry(cptListStyleType, typeVal))
  return ctx.skipBlanksCheckDone()

proc parseFlex(ctx: var CSSParser; attrs: WindowAttributes;
    res: var seq[CSSComputedEntry]): Opt[void] =
  if r := ctx.parseNumber(0f32..float32.high):
    # flex-grow
    res.add(makeEntry(cptFlexGrow, r))
    if ctx.skipBlanksCheckHas().isOk:
      if r := ctx.parseNumber(0f32..float32.high):
        # flex-shrink
        res.add(makeEntry(cptFlexShrink, r))
        ctx.skipBlanks()
  if res.len < 1: # flex-grow omitted, default to 1
    res.add(makeEntry(cptFlexGrow, 1f32))
  if res.len < 2: # flex-shrink omitted, default to 1
    res.add(makeEntry(cptFlexShrink, 1f32))
  if ctx.has():
    # flex-basis
    res.add(makeEntry(cptFlexBasis, ?ctx.parseLength(attrs)))
  else: # omitted, default to 0px
    res.add(makeEntry(cptFlexBasis, CSSLengthZero))
  return ctx.skipBlanksCheckDone()

proc parseFlexFlow(ctx: var CSSParser; attrs: WindowAttributes;
    tok0: CSSToken; res: var seq[CSSComputedEntry]): Opt[void] =
  if dir := parseIdent[CSSFlexDirection](tok0):
    # flex-direction
    ctx.seekToken()
    var val = CSSValueBit(flexDirection: dir)
    res.add(makeEntry(cptFlexDirection, val))
    ctx.skipBlanks()
  if ctx.has():
    let tok = ctx.consume()
    let wrap = ?parseIdent[CSSFlexWrap](tok)
    var val = CSSValueBit(flexWrap: wrap)
    res.add(makeEntry(cptFlexWrap, val))
  return ctx.skipBlanksCheckDone()

proc parseOverflow(ctx: var CSSParser; attrs: WindowAttributes;
    tok0: CSSToken; res: var seq[CSSComputedEntry]): Opt[void] =
  let overflow = ?parseIdent[CSSOverflow](tok0)
  ctx.seekToken()
  let x = CSSValueBit(overflow: overflow)
  var y = x
  if ctx.skipBlanksCheckHas().isOk:
    let tok = ctx.consume()
    y.overflow = ?parseIdent[CSSOverflow](tok)
  res.add(makeEntry(cptOverflowX, x))
  res.add(makeEntry(cptOverflowY, y))
  return ctx.skipBlanksCheckDone()

proc parseVerticalAlign(ctx: var CSSParser; attrs: WindowAttributes;
    res: var seq[CSSComputedEntry]): Opt[void] =
  if ctx.peekTokenType() == cttIdent:
    var entry = CSSComputedEntry()
    ?ctx.parseValue(cptVerticalAlign, entry, attrs)
    res.add(entry)
  else:
    let length = ?ctx.parseLength(attrs, hasAuto = false)
    let val = CSSValueBit(verticalAlign: VerticalAlignLength)
    res.add(makeEntry(cptVerticalAlign, val))
    res.add(makeEntry(cptVerticalAlignLength, length))
  return ctx.skipBlanksCheckDone()

proc parseBorderSpacing(ctx: var CSSParser; attrs: WindowAttributes;
    tok0: CSSToken; res: var seq[CSSComputedEntry]): Opt[void] =
  let a = ?parseAbsoluteLength(tok0, attrs)
  ctx.seekToken()
  ctx.skipBlanks()
  let b = if ctx.has(): ?parseAbsoluteLength(ctx.consume(), attrs) else: a
  res.add(makeEntry(cptBorderSpacingInline, a))
  res.add(makeEntry(cptBorderSpacingBlock, b))
  return ctx.skipBlanksCheckDone()

proc addGlobal(res: var seq[CSSComputedEntry]; p: CSSAnyPropertyType;
    global: CSSGlobalType) =
  case p.sh
  of cstNone: res.add(makeEntry(p.p, global))
  of cstAll:
    for t in CSSPropertyType:
      res.add(makeEntry(t, global))
  else:
    for t in ShorthandMap[p.sh]:
      res.add(makeEntry(t, global))

proc parseComputedValues0*(ctx: var CSSParser; p: CSSAnyPropertyType;
    attrs: WindowAttributes; res: var seq[CSSComputedEntry]): Opt[void] =
  ?ctx.skipBlanksCheckHas()
  let tok = ctx.peekToken()
  if global := parseIdent[CSSGlobalType](tok):
    ctx.seekToken()
    res.addGlobal(p, global)
    return ctx.skipBlanksCheckDone()
  case p.sh
  of cstNone:
    var entry = CSSComputedEntry()
    ?ctx.parseValue(p.p, entry, attrs)
    res.add(entry)
    return ctx.skipBlanksCheckDone()
  of cstAll: return err()
  of cstBorder, cstBorderBottom, cstBorderLeft, cstBorderRight, cstBorderTop:
    return ctx.parseBorder(p.sh, attrs, res)
  of cstMargin, cstPadding, cstBorderStyle, cstBorderColor, cstBorderWidth:
    return ctx.parseBoxShorthand(ShorthandMap[p.sh], attrs, res)
  of cstBackground: return ctx.parseBackground(attrs, res)
  of cstListStyle: return ctx.parseListStyle(attrs, res)
  of cstFlex: return ctx.parseFlex(attrs, res)
  of cstFlexFlow: return ctx.parseFlexFlow(attrs, tok, res)
  of cstOverflow: return ctx.parseOverflow(attrs, tok, res)
  of cstVerticalAlign: return ctx.parseVerticalAlign(attrs, res)
  of cstBorderSpacing: return ctx.parseBorderSpacing(attrs, tok, res)

proc parseComputedValues*(res: var seq[CSSComputedEntry]; p: CSSAnyPropertyType;
    toks: openArray[CSSToken]; attrs: WindowAttributes) =
  var ctx = initCSSParser(toks)
  let olen = res.len
  if ctx.parseComputedValues0(p, attrs, res).isErr:
    res.setLen(olen)

proc copyFrom*(a, b: CSSValues; t: CSSPropertyType) =
  case t.reprType
  of cprtBit: a.bits[t] = b.bits[t]
  of cprtHWord: a.hwords[t] = b.hwords[t]
  of cprtWord: a.words[t] = b.words[t]
  of cprtObject: a.objs[t] = b.objs[t]

proc setInitial*(a: CSSValues; t: CSSPropertyType) =
  case t.reprType
  of cprtBit: a.bits[t].dummy = 0
  of cprtHWord: a.hwords[t] = getDefaultHWord(t)
  of cprtWord: a.words[t] = getDefaultWord(t)
  of cprtObject: a.objs[t] = getDefault(t)

proc initialOrInheritFrom*(a, b: CSSValues; t: CSSPropertyType) =
  if t.inherited and b != nil:
    a.copyFrom(b, t)
  else:
    a.setInitial(t)

proc initialOrCopyFrom*(a, b: CSSValues; t: CSSPropertyType) =
  if b != nil:
    a.copyFrom(b, t)
  else:
    a.setInitial(t)

proc inheritProperties*(parent: CSSValues): CSSValues =
  result = CSSValues()
  for t in CSSPropertyType:
    if t.inherited:
      result.copyFrom(parent, t)
    else:
      result.setInitial(t)

proc copyProperties*(props: CSSValues): CSSValues =
  result = CSSValues()
  result[] = props[]

proc rootProperties*(): CSSValues =
  result = CSSValues()
  for t in CSSPropertyType:
    result.setInitial(t)

# Separate CSSValues of a table into those of the wrapper and the actual
# table.
proc splitTable*(computed: CSSValues): tuple[outer, innner: CSSValues] =
  var outer = CSSValues()
  var inner = CSSValues()
  const props = {
    cptPosition, cptFloat, cptMarginLeft, cptMarginRight, cptMarginTop,
    cptMarginBottom, cptTop, cptRight, cptBottom, cptLeft,
    # Note: the standard does not ask us to include padding or sizing, but the
    # wrapper & actual table layouts share the same sizing from the wrapper,
    # so we must add them here.
    cptPaddingLeft, cptPaddingRight, cptPaddingTop, cptPaddingBottom,
    cptWidth, cptHeight, cptBoxSizing,
    # no clue why this isn't included in the standard
    cptClear, cptZIndex
  }
  for t in CSSPropertyType:
    if t in props:
      outer.copyFrom(computed, t)
      inner.setInitial(t)
    else:
      inner.copyFrom(computed, t)
      outer.setInitial(t)
  outer{"display"} = computed{"display"}
  inner{"display"} = DisplayTableWrapper
  return (outer, inner)

proc borderChar*(style: CSSBorderStyle; c: BoxDrawingChar): string =
  return case style
  of BorderStyleNone, BorderStyleHidden: ""
  of BorderStyleDotted:
    case c
    of HorizontalBar: "\u2508"
    of VerticalBar: "\u250A"
    else: $c # no dotted corners in Unicode
  of BorderStyleDashed:
    case c
    of HorizontalBar: "\u254C"
    of VerticalBar: "\u254E"
    else: $c # likewise
  of BorderStyleSolid: # the default
    $c
  of BorderStyleOutset, BorderStyleGroove: # like solid, but thicker
    case c
    of HorizontalBar: "\u2501"
    of VerticalBar: "\u2503"
    of bdcCornerTopLeft: "\u250F"
    of bdcCornerTopRight: "\u2513"
    of bdcCornerBottomLeft: "\u2517"
    of bdcCornerBottomRight: "\u251B"
    of bdcSideBarLeft: "\u2523"
    of bdcSideBarRight: "\u252B"
    of bdcSideBarTop: "\u2533"
    of bdcSideBarBottom: "\u253B"
    of bdcSideBarCross: "\u254B"
  of BorderStyleDouble, BorderStyleInset, BorderStyleRidge:
    # interpret inset/ridge as double
    case c
    of HorizontalBar: "\u2550"
    of VerticalBar: "\u2551"
    of bdcCornerTopLeft: "\u2554"
    of bdcCornerTopRight: "\u2557"
    of bdcCornerBottomLeft: "\u255A"
    of bdcCornerBottomRight: "\u255D"
    of bdcSideBarLeft: "\u2560"
    of bdcSideBarRight: "\u2563"
    of bdcSideBarTop: "\u2566"
    of bdcSideBarBottom: "\u2569"
    of bdcSideBarCross: "\u256C"
  of BorderStyleBracket: # proprietary extension
    case c
    of bdcVerticalBarLeft: "["
    of bdcVerticalBarRight: "]"
    else: " "
  of BorderStyleParen: # likewise
    case c
    of bdcVerticalBarLeft: "("
    of bdcVerticalBarRight: ")"
    else: " "

when defined(debug):
  proc serializeEmpty*(computed: CSSValues): string =
    let default = rootProperties()
    result = ""
    for p in CSSPropertyType:
      let a = computed.serialize(p)
      let b = default.serialize(p)
      if a != b:
        result &= $p & ':'
        result &= a
        result &= ';'

{.pop.} # raises: []
