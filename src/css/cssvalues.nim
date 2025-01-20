import std/algorithm
import std/macros
import std/options
import std/strutils
import std/tables

import css/cssparser
import css/lunit
import css/selectorparser
import html/catom
import types/bitmap
import types/color
import types/opt
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
    cptVisibility = "visibility"
    cptWhiteSpace = "white-space"
    cptWordBreak = "word-break"

    # word properties: stored as (64-bit) word
    cptBackgroundColor = "background-color"
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
    cptVerticalAlign = "vertical-align"
    cptWidth = "width"
    cptZIndex = "z-index"

    # object properties: stored as a tagged ref object
    cptBackgroundImage = "background-image"
    cptBorderSpacing = "border-spacing"
    cptContent = "content"
    cptCounterReset = "counter-reset"
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

  CSSUnit* = enum
    cuAuto = ""
    cuCm = "cm"
    cuMm = "mm"
    cuIn = "in"
    cuPx = "px"
    cuPt = "pt"
    cuPc = "pc"
    cuEm = "em"
    cuEx = "ex"
    cuCh = "ch"
    cuRem = "rem"
    cuVw = "vw"
    cuVh = "vh"
    cuVmin = "vmin"
    cuVmax = "vmax"
    cuPerc = "%"
    cuIc = "ic"

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
    cvtLength2 = "length2"
    cvtBorderCollapse = "borderCollapse"
    cvtQuotes = "quotes"
    cvtCounterReset = "counterReset"
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
    # internal, for layout
    DisplayTableWrapper = ""
    DisplayInlineTableWrapper = ""

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
    ListStyleTypeNone = "none"
    ListStyleTypeDisc = "disc"
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

  CSSVerticalAlign2* = enum
    VerticalAlignBaseline = "baseline"
    VerticalAlignSub = "sub"
    VerticalAlignSuper = "super"
    VerticalAlignTextTop = "text-top"
    VerticalAlignTextBottom = "text-bottom"
    VerticalAlignMiddle = "middle"
    VerticalAlignTop = "top"
    VerticalAlignBottom = "bottom"

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
    ContentString, ContentOpenQuote, ContentCloseQuote, ContentNoOpenQuote,
    ContentNoCloseQuote, ContentImage, ContentNewline

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
  CSSLengthType* = enum
    clPx = "px"
    clAuto = "auto"
    clPerc = "%"

  CSSLength* = object
    u*: CSSLengthType
    num*: float32

  CSSVerticalAlign* = object
    keyword*: CSSVerticalAlign2
    # inlined CSSLength so that this object fits into 1 word
    u*: CSSLengthType
    num*: float32

  CSSContent* = object
    case t*: CSSContentType
    of ContentImage:
      bmp*: NetworkBitmap
    else:
      s*: string

  # nil -> auto
  CSSQuotes* = ref object
    qs*: seq[tuple[s, e: string]]

  CSSCounterReset* = object
    name*: string
    num*: int

  CSSLength2* = ref object
    a*: CSSLength
    b*: CSSLength

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
    visibility*: CSSVisibility
    whiteSpace*: CSSWhiteSpace
    wordBreak*: CSSWordBreak

  CSSValueWord* {.union.} = object
    dummy: uint64
    color*: CSSColor
    integer*: int32
    length*: CSSLength
    number*: float32
    verticalAlign*: CSSVerticalAlign

  CSSValue* = ref object
    case v*: CSSValueType
    of cvtContent:
      content*: seq[CSSContent]
    of cvtQuotes:
      quotes*: CSSQuotes
    of cvtLength2:
      length2*: CSSLength2
    of cvtCounterReset:
      counterReset*: seq[CSSCounterReset]
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
    # put it here, so ComputedEntry remains 2 words wide
    cvar*: CAtom
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
    important*: bool
    cvals*: seq[CSSComponentValue]
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
  cptVisibility: cvtVisibility,
  cptWhiteSpace: cvtWhiteSpace,
  cptWordBreak: cvtWordBreak,

  # words
  cptBackgroundColor: cvtColor,
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
  cptVerticalAlign: cvtVerticalAlign,
  cptWidth: cvtLength,
  cptZIndex: cvtInteger,

  # pointers
  cptBackgroundImage: cvtImage,
  cptBorderSpacing: cvtLength2,
  cptContent: cvtContent,
  cptCounterReset: cvtCounterReset,
  cptQuotes: cvtQuotes,
]

const InheritedProperties = {
  cptColor, cptFontStyle, cptWhiteSpace, cptFontWeight, cptTextDecoration,
  cptWordBreak, cptListStyleType, cptTextAlign, cptListStylePosition,
  cptCaptionSide, cptBorderSpacing, cptBorderCollapse, cptQuotes,
  cptVisibility, cptTextTransform
}

const OverflowScrollLike* = {OverflowScroll, OverflowAuto, OverflowOverlay}
const OverflowHiddenLike* = {OverflowHidden, OverflowClip}
const FlexReverse* = {FlexDirectionRowReverse, FlexDirectionColumnReverse}

# Forward declarations
proc parseValue(cvals: openArray[CSSComponentValue]; t: CSSPropertyType;
  entry: var CSSComputedEntry; attrs: WindowAttributes; factory: CAtomFactory):
  Opt[void]

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
  return propertyType(s).isSome

func `$`*(length: CSSLength): string =
  if length.u == clAuto:
    return "auto"
  return $length.num & $length.u

func `$`*(bmp: NetworkBitmap): string =
  return "" #TODO

func `$`*(content: CSSContent): string =
  if content.t == ContentImage:
    return $content.bmp
  if content.s != "":
    return "url(" & content.s & ")"
  return "none"

func `$`(quotes: CSSQuotes): string =
  if quotes == nil:
    return "auto"
  result = ""
  for (s, e) in quotes.qs:
    result &= "'" & s.cssEscape() & "' '" & e.cssEscape() & "'"

func `$`(counterreset: seq[CSSCounterReset]): string =
  result = ""
  for it in counterreset:
    result &= $it.name
    result &= ' '
    result &= $it.num

func serialize(val: CSSValue): string =
  case val.v
  of cvtImage: return $val.image
  of cvtLength2:
    if val.length2 == nil:
      return "0px 0px"
    return $val.length2.a & " " & $val.length2.b
  of cvtContent:
    result = ""
    for x in val.content:
      if result.len > 0:
        result &= ' '
      result &= $x
  of cvtQuotes: return $val.quotes
  of cvtCounterReset: return $val.counterReset
  else: assert false

func serialize(val: CSSValueWord; t: CSSValueType): string =
  case t
  of cvtColor: return $val.color
  of cvtInteger: return $val.integer
  of cvtLength: return $val.length
  of cvtNumber: return $val.number
  of cvtVerticalAlign: return $val.verticalAlign
  else: assert false

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
  of cvtVisibility: return $val.visibility
  of cvtWhiteSpace: return $val.whiteSpace
  of cvtWordBreak: return $val.wordBreak
  else: assert false

func serialize*(computed: CSSValues; p: CSSPropertyType): string =
  case p.reprType
  of cprtBit: return computed.bits[p].serialize(valueType(p))
  of cprtWord: return computed.words[p].serialize(valueType(p))
  of cprtObject: return computed.objs[p].serialize()

func `$`*(computed: CSSValues): string =
  result = ""
  for p in CSSPropertyType:
    result &= $p & ':'
    result &= computed.serialize(p)
    result &= ';'

when defined(debug):
  func `$`*(val: CSSValue): string =
    return val.serialize()

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
      `vals`.bits[CSSPropertyType(`t`)].dummy = uint8(`val`)
  of cprtWord:
    return quote do:
      `vals`.objs[CSSPropertyType(`t`)] = CSSValue(
        v: CSSValueType(`v`),
        `vs`: `val`
      )
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
      DisplayFlex, DisplayTableWrapper, DisplayInlineTableWrapper:
     #TODO grid
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

func bfcify*(overflow: CSSOverflow): CSSOverflow =
  if overflow == OverflowVisible:
    return OverflowAuto
  if overflow == OverflowClip:
    return OverflowHidden
  return overflow

const UpperAlphaMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".toPoints()
const LowerAlphaMap = "abcdefghijklmnopqrstuvwxyz".toPoints()
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
  return res

func numToFixed(n: int; map: openArray[uint32]): string =
  let n = n - 1
  if n notin 0 .. map.high:
    return $n
  return $map[n]

func numberAdditive(i: int; range: HSlice[int, int];
    symbols: openArray[(int, string)]): string =
  if i notin range:
    return $i
  var n = i
  var at = 0
  while n > 0:
    if n >= symbols[at][0]:
      n -= symbols[at][0]
      result &= symbols[at][1]
      continue
    inc at
  return result

const romanNumbers = [
  (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
  (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")
]

const romanNumbersLower = block:
  var res: seq[(int, string)] = @[]
  for (n, s) in romanNumbers:
    res.add((n, s.toLowerAscii()))
  res

func romanNumber(i: int): string =
  return numberAdditive(i, 1..3999, romanNumbers)

func romanNumberLower(i: int): string =
  return numberAdditive(i, 1..3999, romanNumbersLower)

func japaneseNumber(i: int): string =
  if i == 0:
    return "〇"
  var n = i
  var s = ""
  if i < 0:
    s &= "マイナス"
    n *= -1
  let o = n
  var ss: seq[string] = @[]
  var d = 0
  while n > 0:
    let m = n mod 10
    if m != 0:
      case d
      of 1: ss.add("十")
      of 2: ss.add("百")
      of 3: ss.add("千")
      of 4:
        ss.add("万")
        ss.add("一")
      of 5:
        ss.add("万")
        ss.add("十")
      of 6:
        ss.add("万")
        ss.add("百")
      of 7:
        ss.add("万")
        ss.add("千")
        ss.add("一")
      of 8:
        ss.add("億")
        ss.add("一")
      of 9:
        ss.add("億")
        ss.add("十")
      else: discard
    case m
    of 0:
      inc d
      n = n div 10
    of 1:
      if o == n:
        ss.add("一")
    of 2: ss.add("二")
    of 3: ss.add("三")
    of 4: ss.add("四")
    of 5: ss.add("五")
    of 6: ss.add("六")
    of 7: ss.add("七")
    of 8: ss.add("八")
    of 9: ss.add("九")
    else: discard
    n -= m
  for j in countdown(ss.high, 0):
    s &= ss[j]
  return s

func listMarker*(t: CSSListStyleType; i: int): string =
  case t
  of ListStyleTypeNone: return ""
  of ListStyleTypeDisc: return "• " # U+2022
  of ListStyleTypeCircle: return "○ " # U+25CB
  of ListStyleTypeSquare: return "□ " # U+25A1
  of ListStyleTypeDisclosureOpen: return "▶ " # U+25B6
  of ListStyleTypeDisclosureClosed: return "▼ " # U+25BC
  of ListStyleTypeDecimal: return $i & ". "
  of ListStyleTypeUpperRoman: return romanNumber(i) & ". "
  of ListStyleTypeLowerRoman: return romanNumberLower(i) & ". "
  of ListStyleTypeUpperAlpha: return numToBase(i, UpperAlphaMap) & ". "
  of ListStyleTypeLowerAlpha: return numToBase(i, LowerAlphaMap) & ". "
  of ListStyleTypeLowerGreek: return numToBase(i, LowerGreekMap) & ". "
  of ListStyleTypeHiragana: return numToBase(i, HiraganaMap) & "、"
  of ListStyleTypeHiraganaIroha: return numToBase(i, HiraganaIrohaMap) & "、"
  of ListStyleTypeKatakana: return numToBase(i, KatakanaMap) & "、"
  of ListStyleTypeKatakanaIroha: return numToBase(i, KatakanaIrohaMap) & "、"
  of ListStyleTypeCjkEarthlyBranch:
    return numToFixed(i, EarthlyBranchMap) & "、"
  of ListStyleTypeCjkHeavenlyStem: return numToFixed(i, HeavenlyStemMap) & "、"
  of ListStyleTypeJapaneseInformal: return japaneseNumber(i) & "、"

func quoteStart*(level: int): string =
  if level == 0:
    return "“"
  return "‘"

func quoteEnd*(level: int): string =
  if level == 0:
    return "“"
  return "‘"

func parseIdent(map: openArray[IdentMapItem]; cval: CSSComponentValue): int =
  if cval of CSSToken:
    let tok = CSSToken(cval)
    if tok.t == cttIdent:
      return map.parseEnumNoCase0(tok.value)
  return -1

func parseIdent[T: enum](cval: CSSComponentValue): Opt[T] =
  const IdentMap = getIdentMap(T)
  let i = IdentMap.parseIdent(cval)
  if i != -1:
    return ok(T(i))
  return err()

template cssLength*(n: float32): CSSLength =
  CSSLength(u: clPx, num: n)

func resolveLength*(u: CSSUnit; val: float32; attrs: WindowAttributes):
    CSSLength =
  return case u
  of cuAuto: CSSLength(u: clAuto)
  of cuEm, cuRem: cssLength(val * float32(attrs.ppl))
  of cuCh: cssLength(val * float32(attrs.ppc))
  of cuIc: cssLength(val * float32(attrs.ppc) * 2)
  of cuEx: cssLength(val * float32(attrs.ppc) / 2)
  of cuPerc: CSSLength(u: clPerc, num: val)
  of cuPx: cssLength(val)
  of cuCm: cssLength(val * 37.8)
  of cuMm: cssLength(val * 3.78)
  of cuIn: cssLength(val * 96)
  of cuPc: cssLength(val * 16)
  of cuPt: cssLength(val * 4 / 3)
  of cuVw: cssLength(float32(attrs.widthPx) * val / 100)
  of cuVh: cssLength(float32(attrs.heightPx) * val / 100)
  of cuVmin: cssLength(min(attrs.widthPx, attrs.heightPx) / 100 * val)
  of cuVmax: cssLength(max(attrs.widthPx, attrs.heightPx) / 100 * val)

func parseLength(val: float32; u: string; attrs: WindowAttributes):
    Opt[CSSLength] =
  let u = ?parseEnumNoCase[CSSUnit](u)
  return ok(resolveLength(u, val, attrs))

const CSSLengthAuto* = CSSLength(u: clAuto)

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
    return some(CSSLength(num: n, u: clPerc))
  return some(cssLength(n))

func skipBlanks*(vals: openArray[CSSComponentValue]; i: int): int =
  var i = i
  while i < vals.len:
    if vals[i] != cttWhitespace:
      break
    inc i
  return i

func findBlank(vals: openArray[CSSComponentValue]; i: int): int =
  var i = i
  while i < vals.len:
    if vals[i] == cttWhitespace:
      break
    inc i
  return i

func getToken(cvals: openArray[CSSComponentValue]; i: int): Opt[CSSToken] =
  if i < cvals.len:
    let cval = cvals[i]
    if cval of CSSToken:
      return ok(CSSToken(cval))
  return err()

func parseARGB(value: openArray[CSSComponentValue]): Opt[CSSColor] =
  var commaMode = false
  var i = value.skipBlanks(0)
  template check_err(slash: bool) =
    #TODO calc, percentages, etc (cssnumber function or something)
    if not slash and i >= value.len:
      return err()
    if i < value.len:
      let x = value[i]
      if not (x of CSSToken and CSSToken(x).t in {cttNumber, cttINumber}):
        return err()
  template next_value(first = false, slash = false) =
    i = value.skipBlanks(i + 1)
    if i < value.len:
      if value[i] == cttComma and (commaMode or first):
        # legacy compatibility
        i = value.skipBlanks(i + 1)
        commaMode = true
      elif commaMode:
        return err()
      elif slash:
        let tok = value[i]
        if tok != cttDelim or CSSToken(tok).cvalue != '/':
          return err()
        i = value.skipBlanks(i + 1)
    check_err slash
  check_err false
  let r = clamp(CSSToken(value[i]).nvalue, 0, 255)
  next_value true
  let g = clamp(CSSToken(value[i]).nvalue, 0, 255)
  next_value
  let b = clamp(CSSToken(value[i]).nvalue, 0, 255)
  next_value false, true
  let a = if i < value.len:
    clamp(CSSToken(value[i]).nvalue, 0, 1)
  else:
    1
  if value.skipBlanks(i) < value.len:
    return err()
  return ok(rgba(int(r), int(g), int(b), int(a * 255)).cssColor())

# syntax: -cha-ansi( number | ident )
# where number is an ANSI color (0..255)
# and ident is in NameTable and may start with "bright-"
func parseANSI(value: openArray[CSSComponentValue]): Opt[CSSColor] =
  var i = value.skipBlanks(0)
  if i != value.high or not (value[i] of CSSToken): # only 1 param is valid
    #TODO numeric functions
    return err()
  let tok = CSSToken(value[i])
  if tok.t == cttINumber:
    if int(tok.nvalue) notin 0..255:
      return err() # invalid numeric ANSI color
    return ok(ANSIColor(tok.nvalue).cssColor())
  elif tok.t == cttIdent:
    var name = tok.value
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

func cssColor*(val: CSSComponentValue): Opt[CSSColor] =
  if val of CSSToken:
    let tok = CSSToken(val)
    case tok.t
    of cttHash:
      let c = parseHexColor(tok.value)
      if c.isSome:
        return ok(c.get.cssColor())
    of cttIdent:
      if tok.value.equalsIgnoreCase("transparent"):
        return ok(rgba(0, 0, 0, 0).cssColor())
      let x = namedRGBColor(tok.value)
      if x.isSome:
        return ok(x.get.cssColor())
    else: discard
  elif val of CSSFunction:
    let f = CSSFunction(val)
    if f.name in {cftRgb, cftRgba}:
      return parseARGB(f.value)
    elif f.name == cftChaAnsi:
      return parseANSI(f.value)
  return err()

func parseLength*(val: CSSComponentValue; attrs: WindowAttributes;
    hasAuto = true; allowNegative = true): Opt[CSSLength] =
  if val of CSSToken:
    let tok = CSSToken(val)
    case tok.t
    of cttNumber, cttINumber:
      if tok.nvalue == 0:
        return ok(cssLength(0))
    of cttPercentage:
      if not allowNegative and tok.nvalue < 0:
        return err()
      return parseLength(tok.nvalue, "%", attrs)
    of cttDimension, cttIDimension:
      if not allowNegative and tok.nvalue < 0:
        return err()
      return parseLength(tok.nvalue, tok.unit, attrs)
    of cttIdent:
      if hasAuto and tok.value.equalsIgnoreCase("auto"):
        return ok(CSSLengthAuto)
    else: discard
  return err()

func cssAbsoluteLength(val: CSSComponentValue; attrs: WindowAttributes):
    Opt[CSSLength] =
  if val of CSSToken:
    let tok = CSSToken(val)
    case tok.t
    of cttNumber, cttINumber:
      if tok.nvalue == 0:
        return ok(cssLength(0))
    of cttDimension, cttIDimension:
      if tok.nvalue >= 0:
        return parseLength(tok.nvalue, tok.unit, attrs)
    else: discard
  return err()

func parseGlobal(cval: CSSComponentValue): Opt[CSSGlobalType] =
  return parseIdent[CSSGlobalType](cval)

func parseQuotes(cvals: openArray[CSSComponentValue]): Opt[CSSQuotes] =
  var i = cvals.skipBlanks(0)
  let tok = ?cvals.getToken(i)
  i = cvals.skipBlanks(i + 1)
  case tok.t
  of cttIdent:
    if i < cvals.len:
      return err()
    if tok.value.equalsIgnoreCase("auto"):
      return ok(nil)
    elif tok.value.equalsIgnoreCase("none"):
      return ok(CSSQuotes())
    return err()
  of cttString:
    var res = CSSQuotes()
    var otok = tok
    while i < cvals.len:
      let cval = cvals[i]
      if not (cval of CSSToken):
        return err()
      let tok = CSSToken(cval)
      if tok.t != cttString:
        return err()
      if otok != nil:
        res.qs.add((otok.value, tok.value))
        otok = nil
      else:
        otok = tok
      i = cvals.skipBlanks(i + 1)
    if otok != nil:
      return err()
    return ok(move(res))
  else:
    return err()

func cssContent(cvals: openArray[CSSComponentValue]): seq[CSSContent] =
  result = @[]
  for cval in cvals:
    if cval of CSSToken:
      let tok = CSSToken(cval)
      case tok.t
      of cttIdent:
        if tok.value == "/":
          break
        elif tok.value.equalsIgnoreCase("open-quote"):
          result.add(CSSContent(t: ContentOpenQuote))
        elif tok.value.equalsIgnoreCase("no-open-quote"):
          result.add(CSSContent(t: ContentNoOpenQuote))
        elif tok.value.equalsIgnoreCase("close-quote"):
          result.add(CSSContent(t: ContentCloseQuote))
        elif tok.value.equalsIgnoreCase("no-close-quote"):
          result.add(CSSContent(t: ContentNoCloseQuote))
      of cttString:
        result.add(CSSContent(t: ContentString, s: tok.value))
      else: return

func parseFontWeight(cval: CSSComponentValue): Opt[int32] =
  if cval of CSSToken:
    let tok = CSSToken(cval)
    if tok.t == cttIdent:
      const FontWeightMap = {
        "bold": 700,
        "bolder": 700,
        "lighter": 400,
        "normal": 400
      }
      let i = FontWeightMap.parseIdent(cval)
      if i != -1:
        return ok(int32(i))
    elif tok.t in {cttNumber, cttINumber}:
      if tok.nvalue in 1f64..1000f64:
        return ok(int32(tok.nvalue))
  return err()

func cssTextDecoration(cvals: openArray[CSSComponentValue]):
    Opt[set[CSSTextDecoration]] =
  var s: set[CSSTextDecoration] = {}
  for cval in cvals:
    if not (cval of CSSToken):
      continue
    let tok = CSSToken(cval)
    if tok.t == cttIdent:
      let td = ?parseIdent[CSSTextDecoration](tok)
      if td == TextDecorationNone:
        if cvals.len != 1:
          return err()
        return ok(s)
      s.incl(td)
  return ok(s)

func cssVerticalAlign(cval: CSSComponentValue; attrs: WindowAttributes):
    Opt[CSSVerticalAlign] =
  if cval of CSSToken:
    let tok = CSSToken(cval)
    if tok.t == cttIdent:
      let va2 = ?parseIdent[CSSVerticalAlign2](cval)
      return ok(CSSVerticalAlign(keyword: va2))
    else:
      let length = ?parseLength(tok, attrs, hasAuto = false)
      return ok(CSSVerticalAlign(
        keyword: VerticalAlignBaseline,
        u: length.u,
        num: length.num
      ))
  return err()

func cssCounterReset(cvals: openArray[CSSComponentValue]):
    Opt[seq[CSSCounterReset]] =
  template die =
    return err()
  var r = CSSCounterReset()
  var s = false
  var res: seq[CSSCounterReset] = @[]
  for cval in cvals:
    if cval of CSSToken:
      let tok = CSSToken(cval)
      case tok.t
      of cttWhitespace: discard
      of cttIdent:
        if s:
          die
        r.name = tok.value
        s = true
      of cttNumber, cttINumber:
        if not s:
          die
        r.num = int(tok.nvalue)
        res.add(r)
        s = false
      else:
        die
  return ok(res)

func cssMaxSize(cval: CSSComponentValue; attrs: WindowAttributes):
    Opt[CSSLength] =
  if cval of CSSToken:
    let tok = CSSToken(cval)
    case tok.t
    of cttIdent:
      if tok.value.equalsIgnoreCase("none"):
        return ok(CSSLengthAuto)
    of cttNumber, cttINumber, cttDimension, cttIDimension, cttPercentage:
      return parseLength(tok, attrs, allowNegative = false)
    else: discard
  return err()

#TODO should be URL (parsed with baseurl of document...)
func cssURL*(cval: CSSComponentValue; src = false): Option[string] =
  if cval of CSSToken:
    let tok = CSSToken(cval)
    if tok == cttUrl:
      return some(tok.value)
    elif not src and tok == cttString:
      return some(tok.value)
  elif cval of CSSFunction:
    let fun = CSSFunction(cval)
    if fun.name == cftUrl or src and fun.name == cftSrc:
      for x in fun.value:
        if not (x of CSSToken):
          break
        let x = CSSToken(x)
        if x == cttWhitespace:
          discard
        elif x == cttString:
          return some(x.value)
        else:
          break
  return none(string)

#TODO this should be bg-image, add gradient, etc etc
func parseImage(cval: CSSComponentValue): Opt[NetworkBitmap] =
  if cval of CSSToken:
    #TODO bg-image only
    let tok = CSSToken(cval)
    if tok.t == cttIdent and tok.value.equalsIgnoreCase("none"):
      return ok(nil)
  let url = cssURL(cval, src = true)
  if url.isSome:
    #TODO do something with the URL
    return ok(NetworkBitmap(cacheId: -1, imageId: -1))
  return err()

func parseInteger(cval: CSSComponentValue; range: Slice[int32]): Opt[int32] =
  if cval of CSSToken:
    let tok = CSSToken(cval)
    if tok.t in {cttNumber, cttINumber}:
      if tok.nvalue in float32(range.a)..float32(range.b):
        return ok(int32(tok.nvalue))
  return err()

func parseNumber(cval: CSSComponentValue; range: Slice[float32]): Opt[float32] =
  if cval of CSSToken:
    let tok = CSSToken(cval)
    if tok.t in {cttNumber, cttINumber}:
      if tok.nvalue in range:
        return ok(tok.nvalue)
  return err()

proc makeEntry*(t: CSSPropertyType; obj: CSSValue): CSSComputedEntry =
  return CSSComputedEntry(et: ceObject, t: t, obj: obj)

proc makeEntry*(t: CSSPropertyType; word: CSSValueWord): CSSComputedEntry =
  return CSSComputedEntry(et: ceWord, t: t, word: word)

proc makeEntry*(t: CSSPropertyType; bit: CSSValueBit): CSSComputedEntry =
  return CSSComputedEntry(et: ceBit, t: t, bit: bit.dummy)

proc makeEntry*(t: CSSPropertyType; global: CSSGlobalType): CSSComputedEntry =
  return CSSComputedEntry(et: ceGlobal, t: t, global: global)

proc parseVariable(fun: CSSFunction; t: CSSPropertyType;
    entry: var CSSComputedEntry; attrs: WindowAttributes;
    factory: CAtomFactory): Opt[void] =
  var i = fun.value.skipBlanks(0)
  if i >= fun.value.len:
    return err()
  let cval = fun.value[i]
  if not (cval of CSSToken):
    return err()
  let tok = CSSToken(fun.value[i])
  if tok.t != cttIdent:
    return err()
  entry = CSSComputedEntry(
    et: ceVar,
    t: t,
    cvar: factory.toAtom(tok.value.substr(2))
  )
  i = fun.value.skipBlanks(i + 1)
  if i < fun.value.len:
    if fun.value[i] != cttComma:
      return err()
    i = fun.value.skipBlanks(i + 1)
    if i < fun.value.len:
      entry.fallback = (ref CSSComputedEntry)()
      if fun.value.toOpenArray(i, fun.value.high).parseValue(t,
          entry.fallback[], attrs, factory).isNone:
        entry.fallback = nil
  return ok()

proc parseValue(cvals: openArray[CSSComponentValue]; t: CSSPropertyType;
    entry: var CSSComputedEntry; attrs: WindowAttributes;
    factory: CAtomFactory): Opt[void] =
  var i = cvals.skipBlanks(0)
  if i >= cvals.len:
    return err()
  let cval = cvals[i]
  inc i
  if cval of CSSFunction:
    let fun = CSSFunction(cval)
    if fun.name == cftVar:
      if cvals.skipBlanks(i) < cvals.len:
        return err()
      return fun.parseVariable(t, entry, attrs, factory)
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
  of cvtDisplay: set_bit display, ?parseIdent[CSSDisplay](cval)
  of cvtWhiteSpace: set_bit whiteSpace, ?parseIdent[CSSWhiteSpace](cval)
  of cvtWordBreak: set_bit wordBreak, ?parseIdent[CSSWordBreak](cval)
  of cvtListStyleType:
    set_bit listStyleType, ?parseIdent[CSSListStyleType](cval)
  of cvtFontStyle: set_bit fontStyle, ?parseIdent[CSSFontStyle](cval)
  of cvtColor: set_word color, ?cssColor(cval)
  of cvtLength:
    case t
    of cptMinWidth, cptMinHeight:
      set_word length, ?parseLength(cval, attrs, allowNegative = false)
    of cptMaxWidth, cptMaxHeight:
      set_word length, ?cssMaxSize(cval, attrs)
    of cptPaddingLeft, cptPaddingRight, cptPaddingTop, cptPaddingBottom:
      set_word length, ?parseLength(cval, attrs, hasAuto = false)
    #TODO content for flex-basis
    else:
      set_word length, ?parseLength(cval, attrs)
  of cvtContent: set_new content, cssContent(cvals)
  of cvtInteger:
    case t
    of cptFontWeight: set_word integer, ?parseFontWeight(cval)
    of cptChaColspan: set_word integer, ?parseInteger(cval, 1i32 .. 1000i32)
    of cptChaRowspan: set_word integer, ?parseInteger(cval, 0i32 .. 65534i32)
    of cptZIndex: set_word integer, ?parseInteger(cval, -65534i32 .. 65534i32)
    else: assert false
  of cvtTextDecoration: set_bit textDecoration, ?cssTextDecoration(cvals)
  of cvtVerticalAlign: set_word verticalAlign, ?cssVerticalAlign(cval, attrs)
  of cvtTextAlign: set_bit textAlign, ?parseIdent[CSSTextAlign](cval)
  of cvtListStylePosition:
    set_bit listStylePosition, ?parseIdent[CSSListStylePosition](cval)
  of cvtPosition: set_bit position, ?parseIdent[CSSPosition](cval)
  of cvtCaptionSide: set_bit captionSide, ?parseIdent[CSSCaptionSide](cval)
  of cvtBorderCollapse:
    set_bit borderCollapse, ?parseIdent[CSSBorderCollapse](cval)
  of cvtLength2:
    let a = ?cssAbsoluteLength(cval, attrs)
    i = cvals.skipBlanks(i)
    let b = if i >= cvals.len: a else: ?cssAbsoluteLength(cvals[i], attrs)
    set_new length2, CSSLength2(a: a, b: b)
  of cvtQuotes: set_new quotes, ?parseQuotes(cvals)
  of cvtCounterReset: set_new counterReset, ?cssCounterReset(cvals)
  of cvtImage: set_new image, ?parseImage(cval)
  of cvtFloat: set_bit float, ?parseIdent[CSSFloat](cval)
  of cvtVisibility: set_bit visibility, ?parseIdent[CSSVisibility](cval)
  of cvtBoxSizing: set_bit boxSizing, ?parseIdent[CSSBoxSizing](cval)
  of cvtClear: set_bit clear, ?parseIdent[CSSClear](cval)
  of cvtTextTransform:
    set_bit textTransform, ?parseIdent[CSSTextTransform](cval)
  of cvtBgcolorIsCanvas: return err() # internal value
  of cvtFlexDirection:
    set_bit flexDirection, ?parseIdent[CSSFlexDirection](cval)
  of cvtFlexWrap: set_bit flexWrap, ?parseIdent[CSSFlexWrap](cval)
  of cvtNumber:
    case t
    of cptFlexGrow, cptFlexShrink:
      set_word number, ?parseNumber(cval, 0f32..float32.high)
    of cptOpacity: set_word number, ?parseNumber(cval, 0f32..1f32)
    else: assert false
  of cvtOverflow: set_bit overflow, ?parseIdent[CSSOverflow](cval)
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
    return cssLength(0)

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
  else: return CSSValueWord(dummy: 0)

func lengthShorthand(cvals: openArray[CSSComponentValue];
    props: array[4, CSSPropertyType]; global: Opt[CSSGlobalType];
    attrs: WindowAttributes; hasAuto = true): Opt[seq[CSSComputedEntry]] =
  var res: seq[CSSComputedEntry] = @[]
  if global.isSome:
    let global = global.get
    for t in props:
      res.add(makeEntry(t, global))
    return ok(res)
  var lengths: seq[CSSValueWord] = @[]
  var i = 0
  while i < cvals.len:
    i = cvals.skipBlanks(i)
    let length = ?parseLength(cvals[i], attrs, hasAuto = hasAuto)
    let val = CSSValueWord(length: length)
    lengths.add(val)
    inc i
  case lengths.len
  of 1: # top, bottom, left, right
    for i, t in props.mypairs:
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
  return ok(res)

const PropertyMarginSpec = [
  cptMarginTop, cptMarginRight, cptMarginBottom, cptMarginLeft
]

const PropertyPaddingSpec = [
  cptPaddingTop, cptPaddingRight, cptPaddingBottom, cptPaddingLeft
]

proc addGlobals(res: var seq[CSSComputedEntry]; ps: openArray[CSSPropertyType];
    global: CSSGlobalType) =
  for p in ps:
    res.add(makeEntry(p, global))

proc parseComputedValues*(res: var seq[CSSComputedEntry]; name: string;
    cvals: openArray[CSSComponentValue]; attrs: WindowAttributes;
    factory: CAtomFactory): Err[void] =
  var i = cvals.skipBlanks(0)
  if i >= cvals.len:
    return err()
  let global = parseGlobal(cvals[i])
  case shorthandType(name)
  of cstNone:
    let t = propertyType(name)
    if t.isSome:
      let t = t.get
      if global.isSome:
        res.add(makeEntry(t, global.get))
      else:
        var entry = CSSComputedEntry()
        ?cvals.parseValue(t, entry, attrs, factory)
        res.add(entry)
  of cstAll:
    let global = ?global
    for t in CSSPropertyType:
      res.add(makeEntry(t, global))
  of cstMargin:
    res.add(?lengthShorthand(cvals, PropertyMarginSpec, global, attrs))
  of cstPadding:
    res.add(?lengthShorthand(cvals, PropertyPaddingSpec, global, attrs,
      hasAuto = false))
  of cstBackground:
    if global.isSome:
      res.addGlobals([cptBackgroundColor, cptBackgroundImage], global.get)
    else:
      var bgcolor = makeEntry(cptBackgroundColor,
        getDefaultWord(cptBackgroundColor))
      var bgimage = makeEntry(cptBackgroundImage,
        getDefault(cptBackgroundImage))
      var valid = true
      var i = cvals.skipBlanks(0)
      while i < cvals.len:
        let j = cvals.findBlank(i)
        if cvals.toOpenArray(i, j - 1).parseValue(bgcolor.t, bgcolor, attrs,
            factory).isSome:
          discard
        elif cvals.toOpenArray(i, j - 1).parseValue(bgimage.t, bgimage, attrs,
            factory).isSome:
          discard
        else:
          #TODO when we implement the other shorthands too
          #valid = false
          discard
        i = cvals.skipBlanks(j)
      if valid:
        res.add(bgcolor)
        res.add(bgimage)
  of cstListStyle:
    if global.isSome:
      res.addGlobals([cptListStylePosition, cptListStyleType], global.get)
    else:
      var valid = true
      var typeVal = CSSValueBit()
      var positionVal = CSSValueBit()
      for tok in cvals:
        if tok == cttWhitespace:
          continue
        if (let r = parseIdent[CSSListStylePosition](tok); r.isSome):
          positionVal.listStylePosition = r.get
        elif (let r = parseIdent[CSSListStyleType](tok); r.isSome):
          typeVal.listStyleType = r.get
        else:
          #TODO list-style-image
          #valid = false
          discard
      if valid:
        res.add(makeEntry(cptListStylePosition, positionVal))
        res.add(makeEntry(cptListStyleType, typeVal))
  of cstFlex:
    if global.isSome:
      res.addGlobals([cptFlexGrow, cptFlexShrink, cptFlexBasis], global.get)
    else:
      var i = cvals.skipBlanks(0)
      if i >= cvals.len:
        return err()
      if (let r = parseNumber(cvals[i], 0f32..float32.high); r.isSome):
        # flex-grow
        let val = CSSValueWord(number: r.get)
        res.add(makeEntry(cptFlexGrow, val))
        i = cvals.skipBlanks(i + 1)
        if i < cvals.len:
          if not (cvals[i] of CSSToken):
            return err()
          if (let r = parseNumber(cvals[i], 0f32..float32.high); r.isSome):
            # flex-shrink
            let val = CSSValueWord(number: r.get)
            res.add(makeEntry(cptFlexShrink, val))
            i = cvals.skipBlanks(i + 1)
      if res.len < 1: # flex-grow omitted, default to 1
        let val = CSSValueWord(number: 1)
        res.add(makeEntry(cptFlexGrow, val))
      if res.len < 2: # flex-shrink omitted, default to 1
        let val = CSSValueWord(number: 1)
        res.add(makeEntry(cptFlexShrink, val))
      if i < cvals.len:
        # flex-basis
        let val = CSSValueWord(length: ?parseLength(cvals[i], attrs))
        res.add(makeEntry(cptFlexBasis, val))
      else: # omitted, default to 0px
        let val = CSSValueWord(length: cssLength(0))
        res.add(makeEntry(cptFlexBasis, val))
  of cstFlexFlow:
    if global.isSome:
      res.addGlobals([cptFlexDirection, cptFlexWrap], global.get)
    else:
      var i = cvals.skipBlanks(0)
      if i >= cvals.len:
        return err()
      if (let dir = parseIdent[CSSFlexDirection](cvals[i]); dir.isSome):
        # flex-direction
        var val = CSSValueBit(flexDirection: dir.get)
        res.add(makeEntry(cptFlexDirection, val))
        i = cvals.skipBlanks(i + 1)
      if i < cvals.len:
        let wrap = ?parseIdent[CSSFlexWrap](cvals[i])
        var val = CSSValueBit(flexWrap: wrap)
        res.add(makeEntry(cptFlexWrap, val))
  of cstOverflow:
    if global.isSome:
      res.addGlobals([cptOverflowX, cptOverflowY], global.get)
    else:
      var i = cvals.skipBlanks(0)
      if i >= cvals.len:
        return err()
      if (let xx = parseIdent[CSSOverflow](cvals[i]); xx.isSome):
        var x = CSSValueBit(overflow: xx.get)
        var y = x
        i = cvals.skipBlanks(i + 1)
        if i < cvals.len:
          y.overflow = ?parseIdent[CSSOverflow](cvals[i])
        res.add(makeEntry(cptOverflowX, x))
        res.add(makeEntry(cptOverflowY, y))
  return ok()

proc parseComputedValues*(name: string; value: seq[CSSComponentValue];
    attrs: WindowAttributes; factory: CAtomFactory): seq[CSSComputedEntry] =
  var res: seq[CSSComputedEntry] = @[]
  if res.parseComputedValues(name, value, attrs, factory).isSome:
    return res
  return @[]

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
func splitTable*(computed: CSSValues):
    tuple[outerComputed, innnerComputed: CSSValues] =
  var outerComputed = CSSValues()
  var innerComputed = CSSValues()
  const props = {
    cptPosition, cptFloat, cptMarginLeft, cptMarginRight, cptMarginTop,
    cptMarginBottom, cptTop, cptRight, cptBottom, cptLeft,
    # Note: the standard does not ask us to include padding or sizing, but the
    # wrapper & actual table layouts share the same sizing from the wrapper,
    # so we must add them here.
    cptPaddingLeft, cptPaddingRight, cptPaddingTop, cptPaddingBottom,
    cptWidth, cptHeight, cptBoxSizing,
    # no clue why this isn't included in the standard
    cptClear
  }
  for t in CSSPropertyType:
    if t in props:
      outerComputed.copyFrom(computed, t)
      innerComputed.setInitial(t)
    else:
      innerComputed.copyFrom(computed, t)
      outerComputed.setInitial(t)
  outerComputed{"display"} = computed{"display"}
  return (outerComputed, innerComputed)
