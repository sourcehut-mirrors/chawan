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

type
  CSSPropertyType* = enum
    # primitive/enum properties: stored as byte
    # (when adding a new property, sort the individual lists, and update
    # LastBitPropType/LastWordPropType if needed.)
    cptBgcolorIsCanvas = "-cha-bgcolor-is-canvas"
    cptBorderCollapse = "border-collapse"
    cptBoxSizing = "box-sizing"
    cptCaptionSide = "caption-side"
    cptClear = "clear"
    cptDisplay = "display"
    cptFlexDirection = "flex-direction"
    cptFlexWrap = "flex-wrap"
    cptFloat = "float"
    cptFontStyle = "font-style"
    cptListStylePosition = "list-style-position"
    cptListStyleType = "list-style-type"
    cptOverflowX = "overflow-x"
    cptOverflowY = "overflow-y"
    cptPosition = "position"
    cptTextAlign = "text-align"
    cptTextDecoration = "text-decoration"
    cptTextTransform = "text-transform"
    cptVerticalAlign = "vertical-align"
    cptVisibility = "visibility"
    cptWhiteSpace = "white-space"
    cptWordBreak = "word-break"

    # word properties: stored as (64-bit) word
    cptBackgroundColor = "background-color"
    cptBorderSpacingBlock = "-cha-border-spacing-block"
    cptBorderSpacingInline = "-cha-border-spacing-inline"
    cptBottom = "bottom"
    cptChaColspan = "-cha-colspan"
    cptChaRowspan = "-cha-rowspan"
    cptColor = "color"
    cptFlexBasis = "flex-basis"
    cptFlexGrow = "flex-grow"
    cptFlexShrink = "flex-shrink"
    cptFontSize = "font-size"
    cptFontWeight = "font-weight"
    cptHeight = "height"
    cptLeft = "left"
    cptMarginBottom = "margin-bottom"
    cptMarginLeft = "margin-left"
    cptMarginRight = "margin-right"
    cptMarginTop = "margin-top"
    cptMaxHeight = "max-height"
    cptMaxWidth = "max-width"
    cptMinHeight = "min-height"
    cptMinWidth = "min-width"
    cptOpacity = "opacity"
    cptPaddingBottom = "padding-bottom"
    cptPaddingLeft = "padding-left"
    cptPaddingRight = "padding-right"
    cptPaddingTop = "padding-top"
    cptRight = "right"
    cptTop = "top"
    cptVerticalAlignLength = "-cha-vertical-align-length"
    cptWidth = "width"
    cptZIndex = "z-index"

    # object properties: stored as a tagged ref object
    cptBackgroundImage = "background-image"
    cptContent = "content"
    cptCounterReset = "counter-reset"
    cptCounterIncrement = "counter-increment"
    cptCounterSet = "counter-set"
    cptQuotes = "quotes"

const LastBitPropType = cptWordBreak
const FirstWordPropType = LastBitPropType.succ
const LastWordPropType = cptZIndex
const FirstObjPropType = LastWordPropType.succ

type
  CSSShorthandType = enum
    cstNone = ""
    cstAll = "all"
    cstMargin = "margin"
    cstPadding = "padding"
    cstBackground = "background"
    cstListStyle = "list-style"
    cstFlex = "flex"
    cstFlexFlow = "flex-flow"
    cstOverflow = "overflow"
    cstVerticalAlign = "vertical-align"
    cstBorderSpacing = "border-spacing"

  CSSUnit* = enum
    cuAuto = ""
    cuCap = "cap"
    cuCh = "ch"
    cuCm = "cm"
    cuDvmax = "dvmax"
    cuDvmin = "dvmin"
    cuEm = "em"
    cuEx = "ex"
    cuIc = "ic"
    cuIn = "in"
    cuLh = "lh"
    cuLvmax = "lvmax"
    cuLvmin = "lvmin"
    cuMm = "mm"
    cuPc = "pc"
    cuPerc = "%"
    cuPt = "pt"
    cuPx = "px"
    cuRcap = "rcap"
    cuRch = "rch"
    cuRem = "rem"
    cuRex = "rex"
    cuRic = "ric"
    cuRlh = "rlh"
    cuSvmax = "svmax"
    cuSvmin = "svmin"
    cuVb = "vb"
    cuVh = "vh"
    cuVi = "vi"
    cuVmax = "vmax"
    cuVmin = "vmin"
    cuVw = "vw"

  CSSValueType* = enum
    cvtLength = "length"
    cvtColor = "color"
    cvtContent = "content"
    cvtDisplay = "display"
    cvtFontStyle = "fontStyle"
    cvtWhiteSpace = "whiteSpace"
    cvtInteger = "integer"
    cvtTextDecoration = "textDecoration"
    cvtWordBreak = "wordBreak"
    cvtListStyleType = "listStyleType"
    cvtVerticalAlign = "verticalAlign"
    cvtTextAlign = "textAlign"
    cvtListStylePosition = "listStylePosition"
    cvtPosition = "position"
    cvtCaptionSide = "captionSide"
    cvtBorderCollapse = "borderCollapse"
    cvtQuotes = "quotes"
    cvtCounterSet = "counterSet"
    cvtImage = "image"
    cvtFloat = "float"
    cvtVisibility = "visibility"
    cvtBoxSizing = "boxSizing"
    cvtClear = "clear"
    cvtTextTransform = "textTransform"
    cvtBgcolorIsCanvas = "bgcolorIsCanvas"
    cvtFlexDirection = "flexDirection"
    cvtFlexWrap = "flexWrap"
    cvtNumber = "number"
    cvtOverflow = "overflow"
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

  CSSValueWord* {.union.} = object
    dummy: uint64
    color*: CSSColor
    integer*: int32
    length*: CSSLength
    number*: float32
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
    bits*: array[CSSPropertyType.low..LastBitPropType, CSSValueBit]
    words*: array[FirstWordPropType..LastWordPropType, CSSValueWord]
    objs*: array[FirstObjPropType..CSSPropertyType.high, CSSValue]
    vars*: CSSVariableMap

  CSSOrigin* = enum
    coUserAgent
    coUser
    coAuthor

  CSSEntryType* = enum
    ceBit, ceObject, ceWord, ceVar, ceGlobal

  CSSComputedEntry* = object
    cvar*: CAtom # put it here, so ComputedEntry remains 2 words wide
    t*: CSSPropertyType
    case et*: CSSEntryType
    of ceBit:
      bit*: uint8
    of ceWord:
      word*: CSSValueWord
    of ceObject:
      obj*: CSSValue
    of ceVar:
      fallback*: ref CSSComputedEntry
    of ceGlobal:
      global*: CSSGlobalType

  CSSVariable* = ref object
    name*: CAtom
    toks*: seq[CSSToken]
    resolved*: seq[tuple[v: CSSValueType; entry: CSSComputedEntry]]

static:
  doAssert sizeof(CSSValueBit) == 1
  doAssert sizeof(CSSValueWord) <= 8
  doAssert sizeof(CSSValue()[]) <= 16
  doAssert sizeof(CSSComputedEntry()) <= 16

const ValueTypes = [
  # bits
  cptBgcolorIsCanvas: cvtBgcolorIsCanvas,
  cptBorderCollapse: cvtBorderCollapse,
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

  # words
  cptBackgroundColor: cvtColor,
  cptBorderSpacingBlock: cvtLength,
  cptBorderSpacingInline: cvtLength,
  cptBottom: cvtLength,
  cptChaColspan: cvtInteger,
  cptChaRowspan: cvtInteger,
  cptColor: cvtColor,
  cptFlexBasis: cvtLength,
  cptFlexGrow: cvtNumber,
  cptFlexShrink: cvtNumber,
  cptFontSize: cvtLength,
  cptFontWeight: cvtInteger,
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
  cptOpacity: cvtNumber,
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
const DisplayNeverHasStack* = DisplayInternalTable + DisplayInnerTable -
  {DisplayTableCell}
const PositionAbsoluteFixed* = {PositionAbsolute, PositionFixed}
const WhiteSpacePreserve* = {
  WhitespacePre, WhitespacePreLine, WhitespacePreWrap
}

# Forward declarations
proc parseValue(toks: openArray[CSSToken]; t: CSSPropertyType;
  entry: var CSSComputedEntry; attrs: WindowAttributes): Opt[void]

proc newCSSVariableMap*(parent: CSSVariableMap): CSSVariableMap =
  return CSSVariableMap(parent: parent)

proc putIfAbsent*(map: CSSVariableMap; name: CAtom; cvar: CSSVariable) =
  discard map.table.hasKeyOrPut(name, cvar)

type CSSPropertyReprType* = enum
  cprtBit, cprtWord, cprtObject

func reprType*(t: CSSPropertyType): CSSPropertyReprType =
  if t <= LastBitPropType:
    return cprtBit
  if t <= LastWordPropType:
    return cprtWord
  return cprtObject

func shorthandType(s: string): CSSShorthandType =
  return parseEnumNoCase[CSSShorthandType](s).get(cstNone)

func propertyType(s: string): Opt[CSSPropertyType] =
  return parseEnumNoCase[CSSPropertyType](s)

func valueType*(prop: CSSPropertyType): CSSValueType =
  return ValueTypes[prop]

func isSupportedProperty*(s: string): bool =
  return propertyType(s).isOk

template auto*(length: CSSLength): bool =
  isNaN(length.npx)

template isPx*(length: CSSLength): bool =
  length.perc == 0

func isPerc*(length: CSSLength): bool {.inline.} =
  not isNaN(length.perc) and length.perc != 0

func isZero*(length: CSSLength): bool {.inline.} =
  length.npx == 0 and length.perc == 0

func `$`*(length: CSSLength): string =
  if length.auto:
    return "auto"
  result = ""
  if length.perc != 0:
    result &= $length.perc & "%"
  if length.npx != 0:
    if result.len > 0:
      result &= " + "
    result &= $length.npx & "px"

func `$`*(bmp: NetworkBitmap): string =
  return "" #TODO

func `$`*(content: CSSContent): string =
  case content.t
  of ContentString:
    return content.s
  of ContentCounter:
    return "counter(" & $content.counter & ", " & $content.counterStyle & ')'
  of ContentOpenQuote, ContentCloseQuote, ContentNoOpenQuote,
      ContentNoCloseQuote:
    return $content.t

func `$`(quotes: CSSQuotes): string =
  if quotes == nil:
    return "auto"
  result = ""
  for (s, e) in quotes.qs:
    result &= "'" & ($s).cssEscape() & "' '" & ($e).cssEscape() & "'"

func `$`(counterreset: seq[CSSCounterSet]): string =
  result = ""
  for it in counterreset:
    result &= $it.name
    result &= ' '
    result &= $it.num

func `$`(zIndex: CSSZIndex): string =
  if zIndex.auto:
    return "auto"
  return $zIndex.num

func serialize(val: CSSValue): string =
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

func serialize(val: CSSValueWord; t: CSSValueType): string =
  case t
  of cvtColor: return $val.color
  of cvtInteger: return $val.integer
  of cvtLength: return $val.length
  of cvtNumber: return $val.number
  of cvtZIndex: return $val.zIndex
  else:
    assert false
    return ""

func serialize(val: CSSValueBit; t: CSSValueType): string =
  case t
  of cvtBgcolorIsCanvas: return $val.bgcolorIsCanvas
  of cvtBorderCollapse: return $val.borderCollapse
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

func serialize*(computed: CSSValues; p: CSSPropertyType): string =
  case p.reprType
  of cprtBit: return computed.bits[p].serialize(valueType(p))
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
  func `$`*(val: CSSValue): string =
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
  of cprtWord:
    return quote do:
      `vals`.words[CSSPropertyType(`t`)] = CSSValueWord(`vs`: `val`)
  of cprtObject:
    return quote do:
      `vals`.objs[CSSPropertyType(`t`)] = CSSValue(
        v: CSSValueType(`v`),
        `vs`: `val`
      )

func inherited*(t: CSSPropertyType): bool =
  return t in InheritedProperties

func blockify*(display: CSSDisplay): CSSDisplay =
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

func bfcify*(overflow: CSSOverflow): CSSOverflow =
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

func numToBase(n: int; map: openArray[uint32]): string =
  if n <= 0:
    return $n
  var tmp: seq[uint32] = @[]
  var n = n
  while n != 0:
    n -= 1
    tmp &= map[n mod map.len]
    n = n div map.len
  var res = ""
  for i in countdown(tmp.high, 0):
    res.addUTF8(tmp[i])
  move(res)

func numToFixed(n: int32; map: openArray[uint32]): string =
  if n in 1 .. map.len:
    return map[n - 1].toUTF8()
  return $n

func numberAdditive(i: int32; range: Slice[int32];
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

const romanNumbers = [
  (1000i32, cstring"M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"),
  (90, "XC"), (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"),
  (1, "I")
]

func romanNumber(i: int32): string =
  return numberAdditive(i, 1i32..3999i32, romanNumbers)

func japaneseNumber(i: int32; formal: bool): string =
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

func listMarker0(t: CSSListStyleType; i: int32): string =
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

func listMarkerSuffix(t: CSSListStyleType): string =
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

func listMarker*(t: CSSListStyleType; i: int32; suffix: bool): RefString =
  let res = newRefString(listMarker0(t, i))
  if suffix:
    res.s &= listMarkerSuffix(t)
  return res

func quoteStart*(level: int): string =
  if level == 0:
    return "“"
  return "‘"

func quoteEnd*(level: int): string =
  if level == 0:
    return "“"
  return "‘"

func parseIdent(map: openArray[IdentMapItem]; tok: CSSToken): int =
  if tok.t == cttIdent:
    return map.parseEnumNoCase0(tok.s)
  return -1

func parseIdent[T: enum](tok: CSSToken): Opt[T] =
  const IdentMap = getIdentMap(T)
  let i = IdentMap.parseIdent(tok)
  if i != -1:
    return ok(T(i))
  return err()

template cssLength*(n: float32): CSSLength =
  CSSLength(npx: n)

template cssLengthPerc*(n: float32): CSSLength =
  CSSLength(perc: n / 100)

const CSSLengthAuto* = CSSLength(npx: NaN, perc: NaN)
const CSSLengthZero* = CSSLength(npx: 0, perc: 0)

func resolveLength*(u: CSSUnit; val: float32; attrs: WindowAttributes):
    CSSLength =
  return case u
  of cuAuto: CSSLengthAuto
  of cuEm, cuRem, cuCap, cuRcap, cuLh, cuRlh:
    cssLength(val * float32(attrs.ppl))
  of cuCh, cuRch: cssLength(val * float32(attrs.ppc))
  of cuIc, cuRic: cssLength(val * float32(attrs.ppc) * 2)
  of cuEx, cuRex: cssLength(val * float32(attrs.ppc) / 2)
  of cuPerc: cssLengthPerc(val)
  of cuPx: cssLength(val)
  of cuCm: cssLength(val * 37.8)
  of cuMm: cssLength(val * 3.78)
  of cuIn: cssLength(val * 96)
  of cuPc: cssLength(val * 16)
  of cuPt: cssLength(val * 4 / 3)
  of cuVw, cuVi: cssLength(float32(attrs.widthPx) * val / 100)
  of cuVh, cuVb: cssLength(float32(attrs.heightPx) * val / 100)
  of cuVmin, cuSvmin, cuLvmin, cuDvmin:
    cssLength(min(attrs.widthPx, attrs.heightPx) / 100 * val)
  of cuVmax, cuSvmax, cuLvmax, cuDvmax:
    cssLength(max(attrs.widthPx, attrs.heightPx) / 100 * val)

func parseLength(val: float32; u: string; attrs: WindowAttributes):
    Opt[CSSLength] =
  let u = ?parseEnumNoCase[CSSUnit](u)
  return ok(resolveLength(u, val, attrs))

func parseDimensionValues*(s: string): Option[CSSLength] =
  var i = s.skipBlanks(0)
  if i >= s.len or s[i] notin AsciiDigit:
    return none(CSSLength)
  var n = 0f64
  while s[i] in AsciiDigit:
    n *= 10
    n += float32(decValue(s[i]))
    inc i
    if i >= s.len:
      return some(cssLength(n))
  if s[i] == '.':
    inc i
    if i >= s.len:
      return some(cssLength(n))
    var d = 1
    while i < s.len and s[i] in AsciiDigit:
      n += float32(decValue(s[i])) / float32(d)
      inc d
      inc i
  if i < s.len and s[i] == '%':
    return some(cssLengthPerc(n))
  return some(cssLength(n))

func getColorToken(toks: openArray[CSSToken]; i: int; legacy = false):
    Opt[CSSToken] =
  let tok = toks[i]
  if tok.t in {cttNumber, cttINumber, cttDimension, cttIDimension,
      cttPercentage}:
    return ok(tok)
  if not legacy and tok.t == cttIdent and tok.s.equalsIgnoreCase("none"):
    return ok(tok)
  return err()

# For rgb(), rgba(), hsl(), hsla().
proc parseLegacyColorFun(value: openArray[CSSToken]):
    Opt[tuple[v1, v2, v3: CSSToken; a: uint8; legacy: bool]] =
  var i = ?value.skipBlanksCheckHas(0)
  let v1 = ?value.getColorToken(i)
  i = ?value.skipBlanksCheckHas(i + 1)
  let legacy = value[i].t == cttComma
  if legacy:
    if v1.t == cttIdent:
      return err() # legacy doesn't accept "none"
    inc i
  i = value.skipBlanks(i)
  let v2 = ?value.getColorToken(i, legacy)
  if legacy:
    i = ?value.skipBlanksCheckHas(i + 1)
    if value[i].t != cttComma:
      return err()
  i = ?value.skipBlanksCheckHas(i + 1)
  let v3 = ?value.getColorToken(i, legacy)
  i = value.skipBlanks(i + 1)
  if i == value.len:
    return ok((v1, v2, v3, 255u8, legacy))
  if legacy:
    if value[i].t != cttComma:
      return err()
  else:
    if not value[i].isDelim('/'):
      return err()
  i = ?value.skipBlanksCheckHas(i + 1)
  let v4 = value[i]
  if v4.t notin {cttPercentage, cttNumber, cttINumber} or
      value.skipBlanks(i + 1) < value.len:
    return err()
  return ok((v1, v2, v3, uint8(clamp(v4.num, 0, 1) * 255), legacy))

# syntax: -cha-ansi( number | ident )
# where number is an ANSI color (0..255)
# and ident is in NameTable and may start with "bright-"
func parseANSI(value: openArray[CSSToken]): Opt[CSSColor] =
  var i = ?value.skipBlanksCheckHas(0)
  let tok = value[i]
  ?value.skipBlanksCheckDone(i + 1) # only 1 param is valid
  if tok.t == cttINumber:
    #TODO calc
    if int(tok.num) notin 0..255:
      return err() # invalid numeric ANSI color
    return ok(ANSIColor(tok.num).cssColor())
  elif tok.t == cttIdent:
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
  return err()

proc parseRGBComponent(tok: CSSToken): uint8 =
  if tok.t == cttIdent: # none
    return 0u8
  var res = tok.num
  if tok.t == cttPercentage:
    res *= 2.55
  return uint8(clamp(res, 0, 255)) # number

type CSSAngleType = enum
  catDeg = "deg"
  catGrad = "grad"
  catRad = "rad"
  catTurn = "turn"

# The return value is in degrees.
proc parseAngle(tok: CSSToken): Opt[float32] =
  if tok.t in {cttDimension, cttIDimension}:
    case ?parseEnumNoCase[CSSAngleType](tok.s)
    of catDeg: return ok(tok.num)
    of catGrad: return ok(tok.num * 0.9f32)
    of catRad: return ok(radToDeg(tok.num))
    of catTurn: return ok(tok.num * 360f32)
  return err()

proc parseHue(tok: CSSToken): Opt[float32] =
  if tok.t in {cttNumber, cttINumber}:
    return ok(tok.num)
  if tok.t == cttIdent: # none
    return ok(0)
  return parseAngle(tok)

proc parseSatOrLight(tok: CSSToken): Opt[float32] =
  if tok.t in {cttNumber, cttINumber, cttPercentage}:
    return ok(clamp(tok.num, 0f32, 100f32))
  return err()

proc parseColor*(tok: CSSToken): Opt[CSSColor] =
  case tok.t
  of cttHash:
    let c = parseHexColor(tok.s)
    if c.isSome:
      return ok(c.get.cssColor())
  of cttIdent:
    if tok.s.equalsIgnoreCase("transparent"):
      return ok(rgba(0, 0, 0, 0).cssColor())
    let x = namedRGBColor(tok.s)
    if x.isSome:
      return ok(x.get.cssColor())
    elif tok.s.equalsIgnoreCase("canvas") or
        tok.s.equalsIgnoreCase("canvastext"):
      # Not really compliant, but if you're setting text color to
      # canvas you're doing it wrong anyway.
      return ok(defaultColor.cssColor())
  of cttFunction:
    let f = tok.fun
    case f.name
    of cftRgb, cftRgba:
      let (r, g, b, a, legacy) = ?parseLegacyColorFun(f.value)
      if r.t == g.t and g.t == b.t or not legacy:
        let r = parseRGBComponent(r)
        let g = parseRGBComponent(g)
        let b = parseRGBComponent(b)
        return ok(rgba(r, g, b, a).cssColor())
    of cftHsl, cftHsla:
      let (h, s, l, a, legacy) = ?parseLegacyColorFun(f.value)
      if h.t != cttIdent and s.t == cttPercentage and l.t == cttPercentage or
          not legacy:
        let h = ?parseHue(h)
        let s = ?parseSatOrLight(s)
        let l = ?parseSatOrLight(l)
        return ok(hsla(h, s, l, a).cssColor())
      return err()
    of cftChaAnsi:
      return parseANSI(f.value)
    else: discard
  else: discard
  return err()

func parseLength*(tok: CSSToken; attrs: WindowAttributes; hasAuto = true;
    allowNegative = true): Opt[CSSLength] =
  case tok.t
  of cttNumber, cttINumber:
    if tok.num == 0:
      return ok(CSSLengthZero)
  of cttPercentage:
    if not allowNegative and tok.num < 0:
      return err()
    return parseLength(tok.num, "%", attrs)
  of cttDimension, cttIDimension:
    if not allowNegative and tok.num < 0:
      return err()
    return parseLength(tok.num, tok.s, attrs)
  of cttIdent:
    if hasAuto and tok.s.equalsIgnoreCase("auto"):
      return ok(CSSLengthAuto)
  of cttFunction:
    #TODO obviously this is a horrible solution...
    let fun = tok.fun
    if fun.name == cftCalc:
      var i = 0
      var ns = CSSLength()
      var nmulx = none(float32)
      var n = 0
      var delim = '+'
      if i == fun.value.len:
        return err()
      while i < fun.value.len:
        if n != 0:
          i = ?fun.value.skipBlanksCheckHas(i)
          if fun.value[i].t != cttDelim:
            return err()
          delim = fun.value[i].c
          inc i
        i = ?fun.value.skipBlanksCheckHas(i)
        if n <= 1 and fun.value[i].t in {cttNumber, cttINumber}:
          let num = fun.value[i].num
          if n == 1:
            if delim != '*' or nmulx.isSome:
              return err()
            ns.npx *= num
            ns.perc *= num
          else:
            nmulx = some(num)
          inc i
          inc n
          continue
        let length = ?parseLength(fun.value[i], attrs, hasAuto)
        if length.auto or delim notin {'+', '-', '*'}:
          return err()
        let sign = if delim == '-': -1f32 else: 1f32
        ns.npx += length.npx * sign
        ns.perc += length.perc * sign
        if nmulx.isSome:
          let nmul = nmulx.get
          if n > 1 or delim != '*':
            return err() # invalid or needs recursive descent
          ns.perc *= nmul
          ns.npx *= nmul
          nmulx = none(float32)
        elif delim == '*':
          return err()
        inc i
        inc n
      if nmulx.isSome:
        return err()
      return ok(ns)
  else: discard
  err()

func cssAbsoluteLength(tok: CSSToken; attrs: WindowAttributes):
    Opt[CSSLength] =
  case tok.t
  of cttNumber, cttINumber:
    if tok.num == 0:
      return ok(CSSLengthZero)
  of cttDimension, cttIDimension:
    if tok.num >= 0:
      return parseLength(tok.num, tok.s, attrs)
  else: discard
  err()

func parseGlobal(tok: CSSToken): Opt[CSSGlobalType] =
  return parseIdent[CSSGlobalType](tok)

func parseQuotes(toks: openArray[CSSToken]): Opt[CSSQuotes] =
  var i = ?toks.skipBlanksCheckHas(0)
  let tok = toks[i]
  i = toks.skipBlanks(i + 1)
  case tok.t
  of cttIdent:
    if i < toks.len:
      return err()
    if tok.s.equalsIgnoreCase("auto"):
      return ok(nil)
    elif tok.s.equalsIgnoreCase("none"):
      return ok(CSSQuotes())
    return err()
  of cttString:
    var res = CSSQuotes()
    var prev = true
    var otok = tok
    while i < toks.len:
      let tok = toks[i]
      if tok.t != cttString:
        return err()
      if prev:
        res.qs.add((newRefString(otok.s), newRefString(tok.s)))
        prev = false
      else:
        otok = tok
        prev = true
      i = toks.skipBlanks(i + 1)
    if prev:
      return err()
    return ok(move(res))
  else:
    return err()

proc parseContent(toks: openArray[CSSToken]): Opt[seq[CSSContent]] =
  var res: seq[CSSContent] = @[]
  for tok in toks:
    case tok.t
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
      let fun = tok.fun
      if fun.name == cftCounter:
        var i = ?fun.value.skipBlanksCheckHas(0)
        let tok = fun.value[i]
        if tok.t != cttIdent:
          return err()
        var style = ListStyleTypeDecimal
        i = fun.value.skipBlanks(i + 1)
        if i < fun.value.len:
          if fun.value[i].t != cttComma:
            return err()
          i = fun.value.skipBlanks(i + 1)
          if i < fun.value.len:
            # stick with decimal if not found
            style = parseIdent[CSSListStyleType](fun.value[i]).get(style)
            if fun.value.skipBlanks(i + 1) < fun.value.len:
              return err()
        res.add(CSSContent(
          t: ContentCounter,
          counter: tok.s.toAtom(),
          counterStyle: style
        ))
    else:
      return err()
  ok(res)

func parseFontWeight(tok: CSSToken): Opt[int32] =
  if tok.t == cttIdent:
    const FontWeightMap = {
      "bold": 700,
      "bolder": 700,
      "lighter": 400,
      "normal": 400
    }
    let i = FontWeightMap.parseIdent(tok)
    if i != -1:
      return ok(int32(i))
  elif tok.t in {cttNumber, cttINumber}:
    if tok.num in 1f64..1000f64:
      return ok(int32(tok.num))
  return err()

func cssTextDecoration(toks: openArray[CSSToken]): Opt[set[CSSTextDecoration]] =
  var s: set[CSSTextDecoration] = {}
  for tok in toks:
    if tok.t == cttIdent:
      let td = ?parseIdent[CSSTextDecoration](tok)
      if td == TextDecorationNone:
        if toks.len != 1:
          return err()
        return ok(s)
      s.incl(td)
  return ok(s)

proc parseCounterSet(toks: openArray[CSSToken]; n: int32):
    Opt[seq[CSSCounterSet]] =
  var r = CSSCounterSet()
  var s = false
  var res: seq[CSSCounterSet] = @[]
  for tok in toks:
    case tok.t
    of cttWhitespace: discard
    of cttIdent:
      if s:
        return err()
      r.name = tok.s.toAtom()
      s = true
    of cttNumber, cttINumber:
      if not s:
        return err()
      r.num = int32(tok.num)
      res.add(r)
      s = false
    else:
      return err()
  if s:
    r.num = n
    res.add(r)
  return ok(res)

func cssMaxSize(tok: CSSToken; attrs: WindowAttributes):
    Opt[CSSLength] =
  if tok.t == cttIdent and tok.s.equalsIgnoreCase("none"):
    return ok(CSSLengthAuto)
  return parseLength(tok, attrs, allowNegative = false)

#TODO should be URL (parsed with baseurl of document...)
func cssURL*(tok: CSSToken; src = false): Option[string] =
  if tok.t == cttUrl:
    return some(tok.s)
  elif not src and tok.t == cttString:
    return some(tok.s)
  elif tok.t == cttFunction:
    let fun = tok.fun
    if fun.name == cftUrl or src and fun.name == cftSrc:
      for x in fun.value:
        if x.t == cttWhitespace:
          discard
        elif x.t == cttString:
          return some(x.s)
        else:
          break
  return none(string)

#TODO this should be bg-image, add gradient, etc etc
func parseImage(tok: CSSToken): Opt[NetworkBitmap] =
  #TODO bg-image only
  if tok.t == cttIdent and tok.s.equalsIgnoreCase("none"):
    return ok(nil)
  let url = cssURL(tok, src = true)
  if url.isSome:
    #TODO do something with the URL
    return ok(NetworkBitmap(cacheId: -1, imageId: -1))
  return err()

func parseInteger(tok: CSSToken; range: Slice[int32]): Opt[int32] =
  if tok.t in {cttNumber, cttINumber}:
    if tok.num in float32(range.a)..float32(range.b):
      return ok(int32(tok.num))
  return err()

func parseZIndex(tok: CSSToken): Opt[CSSZIndex] =
  if tok.t == cttIdent and tok.s.equalsIgnoreCase("auto"):
    return ok(CSSZIndex(auto: true))
  let n = ?parseInteger(tok, -65534i32 .. 65534i32)
  return ok(CSSZIndex(num: n))

func parseNumber(tok: CSSToken; range: Slice[float32]): Opt[float32] =
  if tok.t in {cttNumber, cttINumber}:
    if tok.num in range:
      return ok(tok.num)
  return err()

proc makeEntry*(t: CSSPropertyType; obj: CSSValue): CSSComputedEntry =
  return CSSComputedEntry(et: ceObject, t: t, obj: obj)

proc makeEntry(t: CSSPropertyType; word: CSSValueWord): CSSComputedEntry =
  return CSSComputedEntry(et: ceWord, t: t, word: word)

proc makeEntry*(t: CSSPropertyType; bit: CSSValueBit): CSSComputedEntry =
  return CSSComputedEntry(et: ceBit, t: t, bit: bit.dummy)

proc makeEntry(t: CSSPropertyType; global: CSSGlobalType): CSSComputedEntry =
  return CSSComputedEntry(et: ceGlobal, t: t, global: global)

proc makeEntry*(t: CSSPropertyType; length: CSSLength): CSSComputedEntry =
  makeEntry(t, CSSValueWord(length: length))

proc makeEntry*(t: CSSPropertyType; color: CSSColor): CSSComputedEntry =
  makeEntry(t, CSSValueWord(color: color))

proc makeEntry*(t: CSSPropertyType; integer: int32): CSSComputedEntry =
  makeEntry(t, CSSValueWord(integer: integer))

proc makeEntry(t: CSSPropertyType; number: float32): CSSComputedEntry =
  makeEntry(t, CSSValueWord(number: number))

proc parseVariable(fun: CSSFunction; t: CSSPropertyType;
    entry: var CSSComputedEntry; attrs: WindowAttributes): Opt[void] =
  var i = ?fun.value.skipBlanksCheckHas(0)
  let tok = fun.value[i]
  if tok.t != cttIdent:
    return err()
  entry = CSSComputedEntry(et: ceVar, t: t, cvar: tok.s.substr(2).toAtom())
  i = fun.value.skipBlanks(i + 1)
  if i < fun.value.len:
    if fun.value[i].t != cttComma:
      return err()
    i = fun.value.skipBlanks(i + 1)
    if i < fun.value.len:
      entry.fallback = (ref CSSComputedEntry)()
      if fun.value.toOpenArray(i, fun.value.high).parseValue(t,
          entry.fallback[], attrs).isErr:
        entry.fallback = nil
  return ok()

proc parseValue(toks: openArray[CSSToken]; t: CSSPropertyType;
    entry: var CSSComputedEntry; attrs: WindowAttributes): Opt[void] =
  var i = ?toks.skipBlanksCheckHas(0)
  let tok = toks[i]
  inc i
  if tok.t == cttFunction:
    let fun = tok.fun
    if fun.name == cftVar:
      ?toks.skipBlanksCheckDone(i)
      return fun.parseVariable(t, entry, attrs)
  let v = valueType(t)
  template set_new(prop, val: untyped) =
    entry = CSSComputedEntry(
      t: t,
      et: ceObject,
      obj: CSSValue(v: v, prop: val)
    )
  template set_word(prop, val: untyped) =
    entry = CSSComputedEntry(
      t: t,
      et: ceWord,
      word: CSSValueWord(prop: val)
    )
  template set_bit(prop, val: untyped) =
    entry = CSSComputedEntry(t: t, et: ceBit, bit: cast[uint8](val))
  case v
  of cvtDisplay: set_bit display, ?parseIdent[CSSDisplay](tok)
  of cvtWhiteSpace: set_bit whiteSpace, ?parseIdent[CSSWhiteSpace](tok)
  of cvtWordBreak: set_bit wordBreak, ?parseIdent[CSSWordBreak](tok)
  of cvtListStyleType:
    set_bit listStyleType, ?parseIdent[CSSListStyleType](tok)
  of cvtFontStyle: set_bit fontStyle, ?parseIdent[CSSFontStyle](tok)
  of cvtColor: set_word color, ?parseColor(tok)
  of cvtLength:
    case t
    of cptMinWidth, cptMinHeight:
      set_word length, ?parseLength(tok, attrs, allowNegative = false)
    of cptMaxWidth, cptMaxHeight:
      set_word length, ?cssMaxSize(tok, attrs)
    of cptPaddingLeft, cptPaddingRight, cptPaddingTop, cptPaddingBottom:
      set_word length, ?parseLength(tok, attrs, hasAuto = false)
    #TODO content for flex-basis
    else:
      set_word length, ?parseLength(tok, attrs)
  of cvtContent: set_new content, ?parseContent(toks)
  of cvtInteger:
    case t
    of cptFontWeight: set_word integer, ?parseFontWeight(tok)
    of cptChaColspan: set_word integer, ?parseInteger(tok, 1i32 .. 1000i32)
    of cptChaRowspan: set_word integer, ?parseInteger(tok, 0i32 .. 65534i32)
    else: assert false
  of cvtZIndex: set_word zIndex, ?parseZIndex(tok)
  of cvtTextDecoration: set_bit textDecoration, ?cssTextDecoration(toks)
  of cvtVerticalAlign:
    set_bit verticalAlign, ?parseIdent[CSSVerticalAlign](tok)
  of cvtTextAlign: set_bit textAlign, ?parseIdent[CSSTextAlign](tok)
  of cvtListStylePosition:
    set_bit listStylePosition, ?parseIdent[CSSListStylePosition](tok)
  of cvtPosition: set_bit position, ?parseIdent[CSSPosition](tok)
  of cvtCaptionSide: set_bit captionSide, ?parseIdent[CSSCaptionSide](tok)
  of cvtBorderCollapse:
    set_bit borderCollapse, ?parseIdent[CSSBorderCollapse](tok)
  of cvtQuotes: set_new quotes, ?parseQuotes(toks)
  of cvtCounterSet:
    let n = if t == cptCounterIncrement: 1i32 else: 0i32
    set_new counterSet, ?parseCounterSet(toks, n)
  of cvtImage: set_new image, ?parseImage(tok)
  of cvtFloat: set_bit float, ?parseIdent[CSSFloat](tok)
  of cvtVisibility: set_bit visibility, ?parseIdent[CSSVisibility](tok)
  of cvtBoxSizing: set_bit boxSizing, ?parseIdent[CSSBoxSizing](tok)
  of cvtClear: set_bit clear, ?parseIdent[CSSClear](tok)
  of cvtTextTransform:
    set_bit textTransform, ?parseIdent[CSSTextTransform](tok)
  of cvtBgcolorIsCanvas: return err() # internal value
  of cvtFlexDirection:
    set_bit flexDirection, ?parseIdent[CSSFlexDirection](tok)
  of cvtFlexWrap: set_bit flexWrap, ?parseIdent[CSSFlexWrap](tok)
  of cvtNumber:
    case t
    of cptFlexGrow, cptFlexShrink:
      set_word number, ?parseNumber(tok, 0f32..float32.high)
    of cptOpacity: set_word number, ?parseNumber(tok, 0f32..1f32)
    else: assert false
  of cvtOverflow: set_bit overflow, ?parseIdent[CSSOverflow](tok)
  return ok()

func getInitialColor(t: CSSPropertyType): CSSColor =
  if t == cptBackgroundColor:
    return rgba(0, 0, 0, 0).cssColor()
  return defaultColor.cssColor()

func getInitialLength(t: CSSPropertyType): CSSLength =
  case t
  of cptWidth, cptHeight, cptLeft, cptRight, cptTop, cptBottom, cptMaxWidth,
      cptMaxHeight, cptMinWidth, cptMinHeight, cptFlexBasis:
    return CSSLengthAuto
  of cptFontSize:
    return cssLength(16)
  else:
    return CSSLengthZero

func getInitialInteger(t: CSSPropertyType): int32 =
  case t
  of cptChaColspan, cptChaRowspan:
    return 1
  of cptFontWeight:
    return 400 # normal
  else:
    return 0

func getInitialNumber(t: CSSPropertyType): float32 =
  if t in {cptFlexShrink, cptOpacity}:
    return 1
  return 0

func getInitialTable(): array[CSSPropertyType, CSSValue] =
  result = array[CSSPropertyType, CSSValue].default
  for t in CSSPropertyType:
    result[t] = CSSValue(v: valueType(t))

let defaultTable = getInitialTable()

template getDefault*(t: CSSPropertyType): CSSValue =
  {.cast(noSideEffect).}:
    defaultTable[t]

proc getDefaultWord(t: CSSPropertyType): CSSValueWord =
  case valueType(t)
  of cvtColor: return CSSValueWord(color: getInitialColor(t))
  of cvtInteger: return CSSValueWord(integer: getInitialInteger(t))
  of cvtLength: return CSSValueWord(length: getInitialLength(t))
  of cvtNumber: return CSSValueWord(number: getInitialNumber(t))
  of cvtZIndex: return CSSValueWord(zIndex: CSSZIndex(auto: true))
  else: return CSSValueWord(dummy: 0)

func parseLengthShorthand(res: var seq[CSSComputedEntry];
    toks: openArray[CSSToken]; props: openArray[CSSPropertyType];
    attrs: WindowAttributes; hasAuto: bool): Opt[void] =
  var lengths: seq[CSSLength] = @[]
  var i = 0
  while i < toks.len:
    lengths.add(?parseLength(toks[i], attrs, hasAuto = hasAuto))
    i = toks.skipBlanks(i + 1)
  case lengths.len
  of 1: # top, bottom, left, right
    for t in props:
      res.add(makeEntry(t, lengths[0]))
  of 2: # top, bottom | left, right
    for i, t in props.mypairs:
      res.add(makeEntry(t, lengths[i mod 2]))
  of 3: # top | left, right | bottom
    for i, t in props.mypairs:
      let j = if i == 0:
        0 # top
      elif i == 2:
        2 # bottom
      else:
        1 # left, right
      res.add(makeEntry(t, lengths[j]))
  of 4: # top | right | bottom | left
    for i, t in props.mypairs:
      res.add(makeEntry(t, lengths[i]))
  else:
    return err()
  ok()

const ShorthandMap = [
  cstNone: @[],
  cstAll: @[],
  cstMargin: @[cptMarginTop, cptMarginRight, cptMarginBottom, cptMarginLeft],
  cstPadding: @[cptPaddingTop, cptPaddingRight, cptPaddingBottom,
    cptPaddingLeft],
  cstBackground: @[cptBackgroundColor, cptBackgroundImage],
  cstListStyle: @[cptListStylePosition, cptListStyleType],
  cstFlex: @[cptFlexGrow, cptFlexShrink, cptFlexBasis],
  cstFlexFlow: @[cptFlexDirection, cptFlexWrap],
  cstOverflow: @[cptOverflowX, cptOverflowY],
  cstVerticalAlign: @[cptVerticalAlign, cptVerticalAlignLength],
  cstBorderSpacing: @[cptBorderSpacingInline, cptBorderSpacingBlock]
]

proc parseComputedValues*(res: var seq[CSSComputedEntry]; name: string;
    toks: openArray[CSSToken]; attrs: WindowAttributes): Err[void] =
  var i = ?toks.skipBlanksCheckHas(0)
  let sh = shorthandType(name)
  let tok = toks[i]
  if global := parseGlobal(tok):
    ?toks.skipBlanksCheckDone(i + 1)
    case sh
    of cstNone: res.add(makeEntry(?propertyType(name), global))
    of cstAll:
      for t in CSSPropertyType:
        res.add(makeEntry(t, global))
    else:
      for t in ShorthandMap[sh]:
        res.add(makeEntry(t, global))
    return ok()
  case sh
  of cstNone:
    let t = ?propertyType(name)
    var entry = CSSComputedEntry()
    ?toks.parseValue(t, entry, attrs)
    res.add(entry)
  of cstAll: return err()
  of cstMargin:
    ?res.parseLengthShorthand(toks, ShorthandMap[sh], attrs, hasAuto = true)
  of cstPadding:
    ?res.parseLengthShorthand(toks, ShorthandMap[sh], attrs, hasAuto = false)
  of cstBackground:
    var bgcolor = makeEntry(cptBackgroundColor,
      getDefaultWord(cptBackgroundColor))
    var bgimage = makeEntry(cptBackgroundImage, getDefault(cptBackgroundImage))
    while i < toks.len:
      let j = toks.findBlank(i)
      let k = j - 1
      if toks.toOpenArray(i, k).parseValue(bgcolor.t, bgcolor, attrs).isOk:
        discard
      elif toks.toOpenArray(i, k).parseValue(bgimage.t, bgimage, attrs).isOk:
        discard
      else:
        #TODO when we implement the other shorthands too
        #return err()
        discard
      i = toks.skipBlanks(j)
    res.add(bgcolor)
    res.add(bgimage)
  of cstListStyle:
    var typeVal = CSSValueBit()
    var positionVal = CSSValueBit()
    for tok in toks:
      if tok.t == cttWhitespace:
        continue
      if r := parseIdent[CSSListStylePosition](tok):
        positionVal.listStylePosition = r
      elif r := parseIdent[CSSListStyleType](tok):
        typeVal.listStyleType = r
      else:
        #TODO list-style-image
        #return err()
        discard
    res.add(makeEntry(cptListStylePosition, positionVal))
    res.add(makeEntry(cptListStyleType, typeVal))
  of cstFlex:
    if r := parseNumber(tok, 0f32..float32.high):
      # flex-grow
      res.add(makeEntry(cptFlexGrow, r))
      i = toks.skipBlanks(i + 1)
      if i < toks.len:
        if r := parseNumber(toks[i], 0f32..float32.high):
          # flex-shrink
          res.add(makeEntry(cptFlexShrink, r))
          i = toks.skipBlanks(i + 1)
    if res.len < 1: # flex-grow omitted, default to 1
      res.add(makeEntry(cptFlexGrow, 1f32))
    if res.len < 2: # flex-shrink omitted, default to 1
      res.add(makeEntry(cptFlexShrink, 1f32))
    if i < toks.len:
      # flex-basis
      res.add(makeEntry(cptFlexBasis, ?parseLength(toks[i], attrs)))
    else: # omitted, default to 0px
      res.add(makeEntry(cptFlexBasis, CSSLengthZero))
  of cstFlexFlow:
    if dir := parseIdent[CSSFlexDirection](tok):
      # flex-direction
      var val = CSSValueBit(flexDirection: dir)
      res.add(makeEntry(cptFlexDirection, val))
      i = toks.skipBlanks(i + 1)
    if i < toks.len:
      let wrap = ?parseIdent[CSSFlexWrap](toks[i])
      var val = CSSValueBit(flexWrap: wrap)
      res.add(makeEntry(cptFlexWrap, val))
  of cstOverflow:
    if overflow := parseIdent[CSSOverflow](tok):
      let x = CSSValueBit(overflow: overflow)
      var y = x
      i = toks.skipBlanks(i + 1)
      if i < toks.len:
        y.overflow = ?parseIdent[CSSOverflow](toks[i])
      res.add(makeEntry(cptOverflowX, x))
      res.add(makeEntry(cptOverflowY, y))
  of cstVerticalAlign:
    ?toks.skipBlanksCheckDone(i + 1)
    if tok.t == cttIdent:
      var entry = CSSComputedEntry()
      ?toks.parseValue(cptVerticalAlign, entry, attrs)
      res.add(entry)
    else:
      let length = ?parseLength(tok, attrs, hasAuto = false)
      let val = CSSValueBit(verticalAlign: VerticalAlignLength)
      res.add(makeEntry(cptVerticalAlign, val))
      res.add(makeEntry(cptVerticalAlignLength, length))
  of cstBorderSpacing:
    let a = ?cssAbsoluteLength(tok, attrs)
    i = toks.skipBlanks(i + 1)
    let b = if i >= toks.len: a else: ?cssAbsoluteLength(toks[i], attrs)
    if toks.skipBlanks(i + 1) < toks.len:
      return err()
    res.add(makeEntry(cptBorderSpacingInline, a))
    res.add(makeEntry(cptBorderSpacingBlock, b))
  return ok()

proc parseComputedValues*(name: string; value: seq[CSSToken];
    attrs: WindowAttributes): seq[CSSComputedEntry] =
  var res: seq[CSSComputedEntry] = @[]
  if res.parseComputedValues(name, value, attrs).isOk:
    return move(res)
  @[]

proc copyFrom*(a, b: CSSValues; t: CSSPropertyType) =
  case t.reprType
  of cprtBit: a.bits[t] = b.bits[t]
  of cprtWord: a.words[t] = b.words[t]
  of cprtObject: a.objs[t] = b.objs[t]

proc setInitial*(a: CSSValues; t: CSSPropertyType) =
  case t.reprType
  of cprtBit: a.bits[t].dummy = 0
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

func inheritProperties*(parent: CSSValues): CSSValues =
  result = CSSValues()
  for t in CSSPropertyType:
    if t.inherited:
      result.copyFrom(parent, t)
    else:
      result.setInitial(t)

func copyProperties*(props: CSSValues): CSSValues =
  result = CSSValues()
  result[] = props[]

func rootProperties*(): CSSValues =
  result = CSSValues()
  for t in CSSPropertyType:
    result.setInitial(t)

# Separate CSSValues of a table into those of the wrapper and the actual
# table.
func splitTable*(computed: CSSValues): tuple[outer, innner: CSSValues] =
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
    cptClear, cptPosition
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

when defined(debug):
  func serializeEmpty*(computed: CSSValues): string =
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
