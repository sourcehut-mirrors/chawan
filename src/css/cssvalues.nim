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

  CSSValueHWord* {.union.} = object
    dummy: uint32
    integer*: int32
    number*: float32

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

  # half-words
  cptChaColspan: cvtInteger,
  cptChaRowspan: cvtInteger,
  cptFlexGrow: cvtNumber,
  cptFlexShrink: cvtNumber,
  cptFontWeight: cvtInteger,
  cptOpacity: cvtNumber,

  # words
  cptBackgroundColor: cvtColor,
  cptBorderSpacingBlock: cvtLength,
  cptBorderSpacingInline: cvtLength,
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
const DisplayNeverHasStack* = DisplayInternalTable + DisplayInnerTable -
  {DisplayTableCell}
const PositionAbsoluteFixed* = {PositionAbsolute, PositionFixed}
const WhiteSpacePreserve* = {
  WhitespacePre, WhitespacePreLine, WhitespacePreWrap
}

# Forward declarations
proc parseValue(ctx: var CSSParser; t: CSSPropertyType;
  entry: var CSSComputedEntry; attrs: WindowAttributes): Opt[void]
proc parseLength*(ctx: var CSSParser; attrs: WindowAttributes;
  hasAuto = true; allowNegative = true): Opt[CSSLength]

proc newCSSVariableMap*(parent: CSSVariableMap): CSSVariableMap =
  return CSSVariableMap(parent: parent)

proc putIfAbsent*(map: CSSVariableMap; name: CAtom; cvar: CSSVariable) =
  discard map.table.hasKeyOrPut(name, cvar)

type CSSPropertyReprType* = enum
  cprtBit, cprtHWord, cprtWord, cprtObject

func reprType*(t: CSSPropertyType): CSSPropertyReprType =
  if t <= LastBitPropType:
    return cprtBit
  if t <= LastHWordPropType:
    return cprtHWord
  if t <= LastWordPropType:
    return cprtWord
  return cprtObject

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

func serialize(val: CSSValueHWord; t: CSSValueType): string =
  case t
  of cvtInteger: return $val.integer
  of cvtNumber: return $val.number
  else:
    assert false
    return ""

func serialize(val: CSSValueWord; t: CSSValueType): string =
  case t
  of cvtColor: return $val.color
  of cvtLength: return $val.length
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
  for u in tmp.ritems:
    res.addUTF8(u)
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

proc parseIdent[T: enum](ctx: var CSSParser): Opt[T] =
  return parseIdent[T](ctx.consume())

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

func parseDimensionValues*(s: string): Opt[CSSLength] =
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

func consumeColorToken(ctx: var CSSParser; legacy = false): Opt[CSSToken] =
  let tok = ctx.consume()
  if tok.t in {cttNumber, cttINumber, cttDimension, cttIDimension,
      cttPercentage}:
    return ok(tok)
  if not legacy and tok.t == cttIdent and tok.s.equalsIgnoreCase("none"):
    return ok(tok)
  return err()

# For rgb(), rgba(), hsl(), hsla().
proc parseLegacyColorFun(ctx: var CSSParser):
    Opt[tuple[v1, v2, v3: CSSToken; a: uint8; legacy: bool]] =
  ?ctx.skipBlanksCheckHas()
  let v1 = ?ctx.consumeColorToken()
  ?ctx.skipBlanksCheckHas()
  let legacy = ctx.peekTokenType() == cttComma
  if legacy:
    if v1.t == cttIdent:
      return err() # legacy doesn't accept "none"
    ctx.seekToken()
  ?ctx.skipBlanksCheckHas()
  let v2 = ?ctx.consumeColorToken(legacy)
  if legacy:
    ?ctx.skipBlanksCheckHas()
    if ctx.consume().t != cttComma:
      return err()
  ?ctx.skipBlanksCheckHas()
  let v3 = ?ctx.consumeColorToken(legacy)
  ctx.skipBlanks()
  if ctx.checkFunctionEnd().isOk:
    return ok((v1, v2, v3, 255u8, legacy))
  if ctx.peekTokenType() != (if legacy: cttComma else: cttSlash):
    return err()
  ctx.seekToken()
  ?ctx.skipBlanksCheckHas()
  let v4 = ctx.consume()
  if v4.t notin {cttPercentage, cttNumber, cttINumber}:
    return err()
  ?ctx.checkFunctionEnd()
  return ok((v1, v2, v3, uint8(clamp(v4.num, 0, 1) * 255), legacy))

# syntax: -cha-ansi( number | ident )
# where number is an ANSI color (0..255)
# and ident is in NameTable and may start with "bright-"
proc parseANSI(ctx: var CSSParser): Opt[CSSColor] =
  ?ctx.skipBlanksCheckHas()
  let tok = ctx.consume()
  if tok.t in {cttINumber, cttNumber}:
    #TODO calc
    let i = tok.toi
    if i notin 0i32..25532:
      return err() # invalid numeric ANSI color
    return ok(ANSIColor(i).cssColor())
  elif tok.t == cttIdent:
    var name = tok.s
    if name.equalsIgnoreCase("default"):
      ?ctx.checkFunctionEnd()
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
        ?ctx.checkFunctionEnd()
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

proc parseColor*(ctx: var CSSParser): Opt[CSSColor] =
  ?ctx.skipBlanksCheckHas()
  let tok = ctx.consume()
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
    case tok.ft
    of cftRgb, cftRgba:
      if x := ctx.parseLegacyColorFun():
        let (r, g, b, a, legacy) = x
        if r.t == g.t and g.t == b.t or not legacy:
          let r = parseRGBComponent(r)
          let g = parseRGBComponent(g)
          let b = parseRGBComponent(b)
          return ok(rgba(r, g, b, a).cssColor())
    of cftHsl, cftHsla:
      if x := ctx.parseLegacyColorFun():
        let (h, s, l, a, legacy) = x
        if h.t != cttIdent and s.t == cttPercentage and l.t == cttPercentage or
            not legacy:
          let h = ?parseHue(h)
          let s = ?parseSatOrLight(s)
          let l = ?parseSatOrLight(l)
          ?ctx.checkFunctionEnd()
          return ok(hsla(h, s, l, a).cssColor())
    of cftChaAnsi:
      let res = ctx.parseANSI()
      if res.isOk:
        ?ctx.checkFunctionEnd()
        return res
    else: discard
    ctx.skipFunction()
  else: discard
  return err()

proc parseCalc(ctx: var CSSParser; attrs: WindowAttributes;
    hasAuto, allowNegative: bool): Opt[CSSLength] =
  var ns = CSSLength()
  var nmulx = none(float32)
  var n = 0
  var delim = cttPlus
  ctx.skipBlanks()
  if not ctx.has() or ctx.peekTokenType() == cttRparen:
    return err()
  while ctx.has() and ctx.peekTokenType() != cttRparen:
    if n != 0:
      ?ctx.skipBlanksCheckHas()
      if ctx.peekTokenType() notin {cttPlus, cttMinus, cttStar}:
        ctx.skipFunction()
        return err()
      delim = ctx.consume().t
    ?ctx.skipBlanksCheckHas()
    if n <= 1 and ctx.peekTokenType() in {cttNumber, cttINumber}:
      let num = ctx.consume().num
      if n == 1:
        if delim != cttStar or nmulx.isSome:
          ctx.skipFunction()
          return err()
        ns.npx *= num
        ns.perc *= num
      else:
        nmulx = some(num)
      inc n
      continue
    if ctx.peekTokenType() == cttRparen:
      ctx.skipFunction()
      return err()
    let length = ?ctx.parseLength(attrs, hasAuto, allowNegative = true)
    if length.auto:
      ctx.skipFunction()
      return err()
    let sign = if delim == cttMinus: -1f32 else: 1f32
    ns.npx += length.npx * sign
    ns.perc += length.perc * sign
    if nmulx.isSome:
      let nmul = nmulx.get
      if n > 1 or delim != cttStar:
        return err() # invalid or needs recursive descent
      ns.perc *= nmul
      ns.npx *= nmul
      nmulx = none(float32)
    elif delim == cttStar:
      ctx.skipFunction()
      return err()
    inc n
  if ctx.has():
    assert ctx.consume().t == cttRparen
  if nmulx.isSome:
    return err()
  return ok(ns)

proc parseLength*(ctx: var CSSParser; attrs: WindowAttributes;
    hasAuto = true; allowNegative = true): Opt[CSSLength] =
  ?ctx.skipBlanksCheckHas()
  case (let tok = ctx.consume(); tok.t)
  of cttNumber, cttINumber:
    if tok.num == 0:
      return ok(CSSLengthZero)
  of cttPercentage:
    let n = tok.num
    if not allowNegative and n < 0:
      return err()
    return parseLength(n, "%", attrs)
  of cttDimension, cttIDimension:
    let n = tok.num
    if not allowNegative and n < 0:
      return err()
    return parseLength(n, tok.s, attrs)
  of cttIdent:
    if hasAuto and tok.s.equalsIgnoreCase("auto"):
      return ok(CSSLengthAuto)
  of cttFunction:
    if tok.ft != cftCalc:
      return err()
    return ctx.parseCalc(attrs, hasAuto, allowNegative)
  else: discard
  err()

proc parseLength*(toks: openArray[CSSToken]; attrs: WindowAttributes;
    hasAuto = true; allowNegative = true): Opt[CSSLength] =
  var ctx = initCSSParser(toks)
  return ctx.parseLength(attrs, hasAuto, allowNegative)

func parseAbsoluteLength(tok: CSSToken; attrs: WindowAttributes):
    Opt[CSSLength] =
  case tok.t
  of cttNumber, cttINumber:
    if tok.num == 0:
      return ok(CSSLengthZero)
  of cttDimension, cttIDimension:
    if (let n = tok.num; n >= 0):
      return parseLength(n, tok.s, attrs)
  else: discard
  err()

func parseQuotes(ctx: var CSSParser): Opt[CSSQuotes] =
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

func parseFontWeight(ctx: var CSSParser): Opt[int32] =
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
  elif tok.t in {cttNumber, cttINumber}:
    let i = tok.toi
    if i in 1i32..1000i32:
      return ok(i)
  return err()

func parseTextDecoration(ctx: var CSSParser): Opt[set[CSSTextDecoration]] =
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
    elif ctx.peekTokenType() in {cttNumber, cttINumber}:
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

func parseInteger(ctx: var CSSParser; range: Slice[int32]): Opt[int32] =
  let tok = ctx.consume()
  if tok.t in {cttNumber, cttINumber}:
    let i = tok.toi
    if i in range:
      return ok(i)
  return err()

func parseZIndex(ctx: var CSSParser): Opt[CSSZIndex] =
  if ctx.peekIdentNoCase("auto"):
    ctx.seekToken()
    return ok(CSSZIndex(auto: true))
  let n = ?ctx.parseInteger(-65534i32 .. 65534i32)
  return ok(CSSZIndex(num: n))

func parseNumber(ctx: var CSSParser; range: Slice[float32]): Opt[float32] =
  let tok = ctx.peekToken()
  if tok.t in {cttNumber, cttINumber}:
    if (let n = tok.num; n in range):
      ctx.seekToken()
      return ok(n)
  return err()

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

proc makeEntry(t: CSSPropertyType; number: float32): CSSComputedEntry =
  makeEntry(t, CSSValueHWord(number: number))

template makeEntry[T: enum|set](t: CSSPropertyType; val: T): CSSComputedEntry =
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
        allowNegative = true))
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
  ok()

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

proc getDefaultHWord(t: CSSPropertyType): CSSValueHWord =
  case valueType(t)
  of cvtInteger: return CSSValueHWord(integer: getInitialInteger(t))
  of cvtNumber: return CSSValueHWord(number: getInitialNumber(t))
  else: return CSSValueHWord(dummy: 0)

proc getDefaultWord(t: CSSPropertyType): CSSValueWord =
  case valueType(t)
  of cvtColor: return CSSValueWord(color: getInitialColor(t))
  of cvtLength: return CSSValueWord(length: getInitialLength(t))
  of cvtZIndex: return CSSValueWord(zIndex: CSSZIndex(auto: true))
  else: return CSSValueWord(dummy: 0)

proc parseLengthShorthand(ctx: var CSSParser; props: openArray[CSSPropertyType];
    attrs: WindowAttributes; hasAuto: bool; res: var seq[CSSComputedEntry]):
    Opt[void] =
  var lengths: seq[CSSLength] = @[]
  while ctx.skipBlanksCheckHas().isOk:
    lengths.add(?ctx.parseLength(attrs, hasAuto, allowNegative = true))
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

proc parseComputedValues0*(ctx: var CSSParser; p: CSSAnyPropertyType;
    attrs: WindowAttributes; res: var seq[CSSComputedEntry]): Err[void] =
  ?ctx.skipBlanksCheckHas()
  let tok = ctx.peekToken()
  if global := parseIdent[CSSGlobalType](tok):
    ctx.seekToken()
    ?ctx.skipBlanksCheckDone()
    case p.sh
    of cstNone: res.add(makeEntry(p.p, global))
    of cstAll:
      for t in CSSPropertyType:
        res.add(makeEntry(t, global))
    else:
      for t in ShorthandMap[p.sh]:
        res.add(makeEntry(t, global))
    return ok()
  case p.sh
  of cstNone:
    var entry = CSSComputedEntry()
    ?ctx.parseValue(p.p, entry, attrs)
    ?ctx.skipBlanksCheckDone()
    res.add(entry)
  of cstAll: return err()
  of cstMargin:
    ?ctx.parseLengthShorthand(ShorthandMap[p.sh], attrs, hasAuto = true, res)
  of cstPadding:
    ?ctx.parseLengthShorthand(ShorthandMap[p.sh], attrs, hasAuto = false, res)
  of cstBackground:
    var bgcolor = makeEntry(cptBackgroundColor,
      getDefaultWord(cptBackgroundColor))
    var bgimage = makeEntry(cptBackgroundImage, getDefault(cptBackgroundImage))
    while ctx.has():
      if color := ctx.parseColor():
        bgcolor = makeEntry(cptBackgroundColor, color)
      elif image := ctx.parseImage():
        let val = CSSValue(v: cvtImage, image: image)
        bgimage = makeEntry(cptBackgroundImage, val)
      else:
        #TODO when we implement the other shorthands too
        #return err()
        discard
      ctx.skipBlanks()
    res.add(bgcolor)
    res.add(bgimage)
  of cstListStyle:
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
  of cstFlex:
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
    ?ctx.skipBlanksCheckDone()
  of cstFlexFlow:
    if dir := parseIdent[CSSFlexDirection](tok):
      # flex-direction
      var val = CSSValueBit(flexDirection: dir)
      res.add(makeEntry(cptFlexDirection, val))
      ctx.skipBlanks()
    if ctx.has():
      let tok = ctx.consume()
      let wrap = ?parseIdent[CSSFlexWrap](tok)
      var val = CSSValueBit(flexWrap: wrap)
      res.add(makeEntry(cptFlexWrap, val))
  of cstOverflow:
    if overflow := parseIdent[CSSOverflow](tok):
      let x = CSSValueBit(overflow: overflow)
      var y = x
      if ctx.skipBlanksCheckHas().isOk:
        let tok = ctx.consume()
        y.overflow = ?parseIdent[CSSOverflow](tok)
      res.add(makeEntry(cptOverflowX, x))
      res.add(makeEntry(cptOverflowY, y))
  of cstVerticalAlign:
    if tok.t == cttIdent:
      var entry = CSSComputedEntry()
      ?ctx.parseValue(cptVerticalAlign, entry, attrs)
      res.add(entry)
    else:
      let length = ?ctx.parseLength(attrs, hasAuto = false)
      let val = CSSValueBit(verticalAlign: VerticalAlignLength)
      res.add(makeEntry(cptVerticalAlign, val))
      res.add(makeEntry(cptVerticalAlignLength, length))
    ?ctx.skipBlanksCheckDone()
  of cstBorderSpacing:
    let a = ?parseAbsoluteLength(tok, attrs)
    ctx.seekToken()
    ctx.skipBlanks()
    let b = if ctx.has(): ?parseAbsoluteLength(ctx.consume(), attrs) else: a
    ?ctx.skipBlanksCheckDone()
    res.add(makeEntry(cptBorderSpacingInline, a))
    res.add(makeEntry(cptBorderSpacingBlock, b))
  return ok()

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
