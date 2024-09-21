import std/algorithm
import std/macros
import std/options
import std/strutils
import std/tables

import css/cssparser
import css/selectorparser
import types/bitmap
import layout/layoutunit
import types/color
import types/opt
import types/winattrs
import utils/twtstr
import utils/twtuni

export selectorparser.PseudoElem

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

  CSSUnit* = enum
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

  CSSPropertyType* = enum
    cptNone = ""
    cptColor = "color"
    cptMarginTop = "margin-top"
    cptMarginLeft = "margin-left"
    cptMarginRight = "margin-right"
    cptMarginBottom = "margin-bottom"
    cptFontStyle = "font-style"
    cptDisplay = "display"
    cptContent = "content"
    cptWhiteSpace = "white-space"
    cptFontWeight = "font-weight"
    cptTextDecoration = "text-decoration"
    cptWordBreak = "word-break"
    cptWidth = "width"
    cptHeight = "height"
    cptListStyleType = "list-style-type"
    cptPaddingTop = "padding-top"
    cptPaddingLeft = "padding-left"
    cptPaddingRight = "padding-right"
    cptPaddingBottom = "padding-bottom"
    cptVerticalAlign = "vertical-align"
    cptTextAlign = "text-align"
    cptListStylePosition = "list-style-position"
    cptBackgroundColor = "background-color"
    cptPosition = "position"
    cptLeft = "left"
    cptRight = "right"
    cptTop = "top"
    cptBottom = "bottom"
    cptCaptionSide = "caption-side"
    cptBorderSpacing = "border-spacing"
    cptBorderCollapse = "border-collapse"
    cptQuotes = "quotes"
    cptCounterReset = "counter-reset"
    cptMaxWidth = "max-width"
    cptMaxHeight = "max-height"
    cptMinWidth = "min-width"
    cptMinHeight = "min-height"
    cptBackgroundImage = "background-image"
    cptChaColspan = "-cha-colspan"
    cptChaRowspan = "-cha-rowspan"
    cptFloat = "float"
    cptVisibility = "visibility"
    cptBoxSizing = "box-sizing"
    cptClear = "clear"
    cptTextTransform = "text-transform"
    cptBgcolorIsCanvas = "-cha-bgcolor-is-canvas"
    cptFlexDirection = "flex-direction"
    cptFlexWrap = "flex-wrap"
    cptFlexGrow = "flex-grow"
    cptFlexShrink = "flex-shrink"
    cptFlexBasis = "flex-basis"
    cptOverflow = "overflow"

  CSSValueType* = enum
    cvtNone = ""
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

  CSSGlobalType = enum
    cgtNoglobal = ""
    cgtInitial = "initial"
    cgtInherit = "inherit"
    cgtRevert = "revert"
    cgtUnset = "unset"

  CSSDisplay* = enum
    DisplayNone = "none"
    DisplayInline = "inline"
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
    ContentString, ContentOpenQuote, ContentCloseQuote,
    ContentNoOpenQuote, ContentNoCloseQuote, ContentImage,
    ContentVideo, ContentAudio, ContentNewline

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

type
  CSSLength* = object
    num*: float64
    unit*: CSSUnit
    auto*: bool

  CSSVerticalAlign* = object
    length*: CSSLength
    keyword*: CSSVerticalAlign2

  CSSContent* = object
    t*: CSSContentType
    s*: string
    bmp*: NetworkBitmap

  CSSQuotes* = object
    auto*: bool
    qs*: seq[tuple[s, e: string]]

  CSSCounterReset* = object
    name*: string
    num*: int

  CSSComputedValue* = ref object
    case v*: CSSValueType
    of cvtColor:
      color*: CellColor
    of cvtLength:
      length*: CSSLength
    of cvtFontStyle:
      fontStyle*: CSSFontStyle
    of cvtDisplay:
      display*: CSSDisplay
    of cvtContent:
      content*: seq[CSSContent]
    of cvtQuotes:
      quotes*: CSSQuotes
    of cvtWhiteSpace:
      whiteSpace*: CSSWhiteSpace
    of cvtInteger:
      integer*: int
    of cvtNumber:
      number*: float64
    of cvtTextDecoration:
      textDecoration*: set[CSSTextDecoration]
    of cvtWordBreak:
      wordBreak*: CSSWordBreak
    of cvtListStyleType:
      listStyleType*: CSSListStyleType
    of cvtVerticalAlign:
      verticalAlign*: CSSVerticalAlign
    of cvtTextAlign:
      textAlign*: CSSTextAlign
    of cvtListStylePosition:
      listStylePosition*: CSSListStylePosition
    of cvtPosition:
      position*: CSSPosition
    of cvtCaptionSide:
      captionSide*: CSSCaptionSide
    of cvtLength2:
      length2*: tuple[a, b: CSSLength]
    of cvtBorderCollapse:
      borderCollapse*: CSSBorderCollapse
    of cvtCounterReset:
      counterReset*: seq[CSSCounterReset]
    of cvtImage:
      image*: CSSContent
    of cvtFloat:
      float*: CSSFloat
    of cvtVisibility:
      visibility*: CSSVisibility
    of cvtBoxSizing:
      boxSizing*: CSSBoxSizing
    of cvtClear:
      clear*: CSSClear
    of cvtTextTransform:
      textTransform*: CSSTextTransform
    of cvtBgcolorIsCanvas:
      bgcolorIsCanvas*: bool
    of cvtFlexDirection:
      flexDirection*: CSSFlexDirection
    of cvtFlexWrap:
      flexWrap*: CSSFlexWrap
    of cvtOverflow:
      overflow*: CSSOverflow
    of cvtNone: discard

  CSSComputedValues* = ref array[CSSPropertyType, CSSComputedValue]

  CSSOrigin* = enum
    coUserAgent
    coUser
    coAuthor

  CSSComputedEntry* = tuple
    t: CSSPropertyType
    val: CSSComputedValue
    global: CSSGlobalType

const ValueTypes = [
  cptNone: cvtNone,
  cptColor: cvtColor,
  cptMarginTop: cvtLength,
  cptMarginLeft: cvtLength,
  cptMarginRight: cvtLength,
  cptMarginBottom: cvtLength,
  cptFontStyle: cvtFontStyle,
  cptDisplay: cvtDisplay,
  cptContent: cvtContent,
  cptWhiteSpace: cvtWhiteSpace,
  cptFontWeight: cvtInteger,
  cptTextDecoration: cvtTextDecoration,
  cptWordBreak: cvtWordBreak,
  cptWidth: cvtLength,
  cptHeight: cvtLength,
  cptListStyleType: cvtListStyleType,
  cptPaddingTop: cvtLength,
  cptPaddingLeft: cvtLength,
  cptPaddingRight: cvtLength,
  cptPaddingBottom: cvtLength,
  cptVerticalAlign: cvtVerticalAlign,
  cptTextAlign: cvtTextAlign,
  cptListStylePosition: cvtListStylePosition,
  cptBackgroundColor: cvtColor,
  cptPosition: cvtPosition,
  cptLeft: cvtLength,
  cptRight: cvtLength,
  cptTop: cvtLength,
  cptBottom: cvtLength,
  cptCaptionSide: cvtCaptionSide,
  cptBorderSpacing: cvtLength2,
  cptBorderCollapse: cvtBorderCollapse,
  cptQuotes: cvtQuotes,
  cptCounterReset: cvtCounterReset,
  cptMaxWidth: cvtLength,
  cptMaxHeight: cvtLength,
  cptMinWidth: cvtLength,
  cptMinHeight: cvtLength,
  cptBackgroundImage: cvtImage,
  cptChaColspan: cvtInteger,
  cptChaRowspan: cvtInteger,
  cptFloat: cvtFloat,
  cptVisibility: cvtVisibility,
  cptBoxSizing: cvtBoxSizing,
  cptClear: cvtClear,
  cptTextTransform: cvtTextTransform,
  cptBgcolorIsCanvas: cvtBgcolorIsCanvas,
  cptFlexDirection: cvtFlexDirection,
  cptFlexWrap: cvtFlexWrap,
  cptFlexGrow: cvtNumber,
  cptFlexShrink: cvtNumber,
  cptFlexBasis: cvtLength,
  cptOverflow: cvtOverflow
]

const InheritedProperties = {
  cptColor, cptFontStyle, cptWhiteSpace, cptFontWeight, cptTextDecoration,
  cptWordBreak, cptListStyleType, cptTextAlign, cptListStylePosition,
  cptCaptionSide, cptBorderSpacing, cptBorderCollapse, cptQuotes,
  cptVisibility, cptTextTransform
}

func shorthandType(s: string): CSSShorthandType =
  return parseEnumNoCase[CSSShorthandType](s).get(cstNone)

func propertyType(s: string): CSSPropertyType =
  return parseEnumNoCase[CSSPropertyType](s).get(cptNone)

func valueType(prop: CSSPropertyType): CSSValueType =
  return ValueTypes[prop]

func isSupportedProperty*(s: string): bool =
  return propertyType(s) != cptNone

func `$`*(length: CSSLength): string =
  if length.auto:
    return "auto"
  return $length.num & $length.unit

func `$`*(content: CSSContent): string =
  if content.s != "":
    return "url(" & content.s & ")"
  return "none"

func `$`(quotes: CSSQuotes): string =
  if quotes.auto:
    return "auto"
  return "auto" #TODO

func `$`(counterreset: seq[CSSCounterReset]): string =
  result = ""
  for it in counterreset:
    result &= $it.name
    result &= ' '
    result &= $it.num

func `$`*(val: CSSComputedValue): string =
  case val.v
  of cvtNone: return "none"
  of cvtColor: return $val.color
  of cvtImage: return $val.image
  of cvtLength: return $val.length
  of cvtDisplay: return $val.display
  of cvtFontStyle: return $val.fontStyle
  of cvtWhiteSpace: return $val.whiteSpace
  of cvtInteger: return $val.integer
  of cvtTextDecoration: return $val.textDecoration
  of cvtWordBreak: return $val.wordBreak
  of cvtListStyleType: return $val.listStyleType
  of cvtVerticalAlign: return $val.verticalAlign
  of cvtTextAlign: return $val.textAlign
  of cvtListStylePosition: return $val.listStylePosition
  of cvtPosition: return $val.position
  of cvtCaptionSide: return $val.captionSide
  of cvtLength2: return $val.length2.a & " " & $val.length2.b
  of cvtBorderCollapse: return $val.borderCollapse
  of cvtContent: return $val.content
  of cvtQuotes: return $val.quotes
  of cvtCounterReset: return $val.counterReset
  of cvtFloat: return $val.float
  of cvtVisibility: return $val.visibility
  of cvtBoxSizing: return $val.boxSizing
  of cvtClear: return $val.clear
  of cvtTextTransform: return $val.textTransform
  of cvtBgcolorIsCanvas: return $val.bgcolorIsCanvas
  of cvtFlexDirection: return $val.flexDirection
  of cvtFlexWrap: return $val.flexWrap
  of cvtOverflow: return $val.overflow
  of cvtNumber: return $val.number

macro `{}`*(vals: CSSComputedValues; s: static string): untyped =
  let t = propertyType(s)
  let vs = ident($valueType(t))
  return quote do:
    `vals`[CSSPropertyType(`t`)].`vs`

macro `{}=`*(vals: CSSComputedValues; s: static string, val: typed) =
  let t = propertyType(s)
  let v = valueType(t)
  let vs = ident($v)
  return quote do:
    `vals`[CSSPropertyType(`t`)] = CSSComputedValue(
      v: CSSValueType(`v`),
      `vs`: `val`
    )

func inherited*(t: CSSPropertyType): bool =
  return t in InheritedProperties

func em_to_px(em: float64; window: WindowAttributes): LayoutUnit =
  (em * float64(window.ppl)).toLayoutUnit()

func ch_to_px(ch: float64; window: WindowAttributes): LayoutUnit =
  (ch * float64(window.ppc)).toLayoutUnit()

# 水 width, we assume it's 2 chars
func ic_to_px(ic: float64; window: WindowAttributes): LayoutUnit =
  (ic * float64(window.ppc) * 2).toLayoutUnit()

# x-letter height, we assume it's em/2
func ex_to_px(ex: float64; window: WindowAttributes): LayoutUnit =
  (ex * float64(window.ppc) / 2).toLayoutUnit()

func px*(l: CSSLength; window: WindowAttributes; p: LayoutUnit): LayoutUnit =
  case l.unit
  of cuEm, cuRem: em_to_px(l.num, window)
  of cuCh: ch_to_px(l.num, window)
  of cuIc: ic_to_px(l.num, window)
  of cuEx: ex_to_px(l.num, window)
  of cuPerc: toLayoutUnit(toFloat64(p) * l.num / 100)
  of cuPx: toLayoutUnit(l.num)
  of cuCm: toLayoutUnit(l.num * 37.8)
  of cuMm: toLayoutUnit(l.num * 3.78)
  of cuIn: toLayoutUnit(l.num * 96)
  of cuPc: toLayoutUnit(l.num * 16)
  of cuPt: toLayoutUnit(l.num * 4 / 3)
  of cuVw: toLayoutUnit(float64(window.widthPx) * l.num / 100)
  of cuVh: toLayoutUnit(float64(window.heightPx) * l.num / 100)
  of cuVmin:
    toLayoutUnit(min(window.widthPx, window.heightPx) / 100 * l.num)
  of cuVmax:
    toLayoutUnit(max(window.widthPx, window.heightPx) / 100 * l.num)

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

#TODO this should change by language
func quoteStart*(level: int): string =
  if level == 0:
    return "“"
  return "‘"

func quoteEnd*(level: int): string =
  if level == 0:
    return "“"
  return "‘"

template isToken(cval: CSSComponentValue): bool =
  cval of CSSToken

template getToken(cval: CSSComponentValue): CSSToken =
  CSSToken(cval)

func parseIdent(map: openArray[IdentMapItem]; cval: CSSComponentValue): int =
  if isToken(cval):
    let tok = getToken(cval)
    if tok.tokenType == cttIdent:
      return map.parseEnumNoCase0(tok.value)
  return -1

func parseIdent[T: enum](cval: CSSComponentValue): Opt[T] =
  const IdentMap = getIdentMap(T)
  let i = IdentMap.parseIdent(cval)
  if i != -1:
    return ok(T(i))
  return err()

func cssLength(val: float64; unit: string): Opt[CSSLength] =
  let u = ?parseEnumNoCase[CSSUnit](unit)
  return ok(CSSLength(num: val, unit: u))

const CSSLengthAuto* = CSSLength(auto: true)

func parseDimensionValues*(s: string): Option[CSSLength] =
  var i = s.skipBlanks(0)
  if i >= s.len or s[i] notin AsciiDigit:
    return none(CSSLength)
  var n = 0f64
  while s[i] in AsciiDigit:
    n *= 10
    n += float64(decValue(s[i]))
    inc i
    if i >= s.len:
      return some(CSSLength(num: n, unit: cuPx))
  if s[i] == '.':
    inc i
    if i >= s.len:
      return some(CSSLength(num: n, unit: cuPx))
    var d = 1
    while i < s.len and s[i] in AsciiDigit:
      n += float64(decValue(s[i])) / float64(d)
      inc d
      inc i
  if i < s.len and s[i] == '%':
    return some(CSSLength(num: n, unit: cuPerc))
  return some(CSSLength(num: n, unit: cuPx))

func skipWhitespace(vals: openArray[CSSComponentValue]; i: var int) =
  while i < vals.len:
    if vals[i] != cttWhitespace:
      break
    inc i

func parseARGB(value: openArray[CSSComponentValue]): Opt[CellColor] =
  var i = 0
  var commaMode = false
  template check_err(slash: bool) =
    #TODO calc, percentages, etc (cssnumber function or something)
    if not slash and i >= value.len or i < value.len and
        value[i] != cttNumber:
      return err()
  template next_value(first = false, slash = false) =
    inc i
    value.skipWhitespace(i)
    if i < value.len:
      if value[i] == cttComma and (commaMode or first):
        # legacy compatibility
        inc i
        value.skipWhitespace(i)
        commaMode = true
      elif commaMode:
        return err()
      elif slash:
        let tok = value[i]
        if tok != cttDelim or CSSToken(tok).cvalue != '/':
          return err()
        inc i
        value.skipWhitespace(i)
    check_err slash
  value.skipWhitespace(i)
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
  value.skipWhitespace(i)
  if i < value.len:
    return err()
  return ok(rgba(int(r), int(g), int(b), int(a * 255)).cellColor())

# syntax: -cha-ansi( number | ident )
# where number is an ANSI color (0..255)
# and ident is in NameTable and may start with "bright-"
func parseANSI(value: openArray[CSSComponentValue]): Opt[CellColor] =
  var i = 0
  value.skipWhitespace(i)
  if i != value.high or not (value[i] of CSSToken): # only 1 param is valid
    #TODO numeric functions
    return err()
  let tok = CSSToken(value[i])
  if tok.tokenType == cttNumber:
    if tok.tflagb != tflagbInteger or int(tok.nvalue) notin 0..255:
      return err() # invalid numeric ANSI color
    return ok(ANSIColor(tok.nvalue).cellColor())
  elif tok.tokenType == cttIdent:
    var name = tok.value
    if name.equalsIgnoreCase("default"):
      return ok(defaultColor)
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
    for i, it in NameTable:
      if it.equalsIgnoreCase(name):
        var i = int(i)
        if bright:
          i += 8
        return ok(ANSIColor(i).cellColor())
  return err()

func cssColor*(val: CSSComponentValue): Opt[CellColor] =
  if val of CSSToken:
    let tok = CSSToken(val)
    case tok.tokenType
    of cttHash:
      let c = parseHexColor(tok.value)
      if c.isSome:
        return ok(c.get.cellColor())
    of cttIdent:
      if tok.value.equalsIgnoreCase("transparent"):
        return ok(rgba(0, 0, 0, 0).cellColor())
      let x = namedRGBColor(tok.value)
      if x.isSome:
        return ok(x.get.cellColor())
    else: discard
  elif val of CSSFunction:
    let f = CSSFunction(val)
    if f.name.equalsIgnoreCase("rgb") or f.name.equalsIgnoreCase("rgba"):
      return parseARGB(f.value)
    elif f.name.equalsIgnoreCase("-cha-ansi"):
      return parseANSI(f.value)
  return err()

func cssLength*(val: CSSComponentValue; has_auto = true; allow_negative = true):
    Opt[CSSLength] =
  if val of CSSToken:
    let tok = CSSToken(val)
    case tok.tokenType
    of cttNumber:
      if tok.nvalue == 0:
        return ok(CSSLength(num: 0, unit: cuPx))
    of cttPercentage:
      if not allow_negative:
        if tok.nvalue < 0:
          return err()
      return cssLength(tok.nvalue, "%")
    of cttDimension:
      if not allow_negative:
        if tok.nvalue < 0:
          return err()
      return cssLength(tok.nvalue, tok.unit)
    of cttIdent:
      if has_auto:
        if tok.value.equalsIgnoreCase("auto"):
          return ok(CSSLengthAuto)
    else: discard
  return err()

func cssAbsoluteLength(val: CSSComponentValue): Opt[CSSLength] =
  if val of CSSToken:
    let tok = CSSToken(val)
    case tok.tokenType
    of cttNumber:
      if tok.nvalue == 0:
        return ok(CSSLength(num: 0, unit: cuPx))
    of cttDimension:
      if tok.nvalue >= 0:
        return cssLength(tok.nvalue, tok.unit)
    else: discard
  return err()

func cssGlobal(cval: CSSComponentValue): CSSGlobalType =
  return parseIdent[CSSGlobalType](cval).get(cgtNoglobal)

func cssQuotes(cvals: openArray[CSSComponentValue]): Opt[CSSQuotes] =
  template die =
    return err()
  if cvals.len == 0:
    die
  var res: CSSQuotes
  var sa = false
  var pair: tuple[s, e: string]
  for cval in cvals:
    if res.auto: die
    if isToken(cval):
      let tok = getToken(cval)
      case tok.tokenType
      of cttIdent:
        if res.qs.len > 0: die
        if tok.value.equalsIgnoreCase("auto"):
          res.auto = true
        elif tok.value.equalsIgnoreCase("none"):
          if cvals.len != 1:
            die
        die
      of cttString:
        if sa:
          pair.e = tok.value
          res.qs.add(pair)
          sa = false
        else:
          pair.s = tok.value
          sa = true
      of cttWhitespace: discard
      else: die
  if sa:
    die
  return ok(res)

func cssContent(cvals: openArray[CSSComponentValue]): seq[CSSContent] =
  for cval in cvals:
    if isToken(cval):
      let tok = getToken(cval)
      case tok.tokenType
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

func cssFontWeight(cval: CSSComponentValue): Opt[int] =
  if isToken(cval):
    let tok = getToken(cval)
    if tok.tokenType == cttIdent:
      const FontWeightMap = {
        "normal": 400,
        "bold": 700,
        "lighter": 400,
        "bolder": 700
      }
      let i = FontWeightMap.parseIdent(cval)
      if i != -1:
        return ok(i)
    elif tok.tokenType == cttNumber:
      if tok.nvalue in 1f64..1000f64:
        return ok(int(tok.nvalue))
  return err()

func cssTextDecoration(cvals: openArray[CSSComponentValue]):
    Opt[set[CSSTextDecoration]] =
  var s: set[CSSTextDecoration] = {}
  for cval in cvals:
    if not isToken(cval):
      continue
    let tok = getToken(cval)
    if tok.tokenType == cttIdent:
      let td = ?parseIdent[CSSTextDecoration](tok)
      if td == TextDecorationNone:
        if cvals.len != 1:
          return err()
        return ok(s)
      s.incl(td)
  return ok(s)

func cssVerticalAlign(cval: CSSComponentValue): Opt[CSSVerticalAlign] =
  if isToken(cval):
    let tok = getToken(cval)
    if tok.tokenType == cttIdent:
      let va2 = ?parseIdent[CSSVerticalAlign2](cval)
      return ok(CSSVerticalAlign(keyword: va2))
    else:
      return ok(CSSVerticalAlign(
        keyword: VerticalAlignBaseline,
        length: ?cssLength(tok, has_auto = false)
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
    if isToken(cval):
      let tok = getToken(cval)
      case tok.tokenType
      of cttWhitespace: discard
      of cttIdent:
        if s:
          die
        r.name = tok.value
        s = true
      of cttNumber:
        if not s:
          die
        r.num = int(tok.nvalue)
        res.add(r)
        s = false
      else:
        die
  return ok(res)

func cssMaxMinSize(cval: CSSComponentValue): Opt[CSSLength] =
  if isToken(cval):
    let tok = getToken(cval)
    case tok.tokenType
    of cttIdent:
      if tok.value.equalsIgnoreCase("none"):
        return ok(CSSLengthAuto)
    of cttNumber, cttDimension, cttPercentage:
      return cssLength(tok, allow_negative = false)
    else: discard
  return err()

#TODO should be URL (parsed with baseurl of document...)
func cssURL(cval: CSSComponentValue): Option[string] =
  if isToken(cval):
    let tok = getToken(cval)
    if tok == cttUrl:
      return some(tok.value)
  elif cval of CSSFunction:
    let fun = CSSFunction(cval)
    if fun.name.equalsIgnoreCase("url") or fun.name.equalsIgnoreCase("src"):
      for x in fun.value:
        if not isToken(x):
          break
        let x = getToken(x)
        if x == cttWhitespace:
          discard
        elif x == cttString:
          return some(x.value)
        else:
          break

#TODO this should be bg-image, add gradient, etc etc
func cssImage(cval: CSSComponentValue): Opt[CSSContent] =
  if isToken(cval):
    #TODO bg-image only
    let tok = getToken(cval)
    if tok.tokenType == cttIdent and tok.value.equalsIgnoreCase("none"):
      return ok(CSSContent(t: ContentImage, s: ""))
  let url = cssURL(cval)
  if url.isSome:
    return ok(CSSContent(t: ContentImage, s: url.get))
  return err()

func cssInteger(cval: CSSComponentValue; range: Slice[int]): Opt[int] =
  if isToken(cval):
    let tok = getToken(cval)
    if tok.tokenType == cttNumber:
      if tok.nvalue in float64(range.a)..float64(range.b):
        return ok(int(tok.nvalue))
  return err()

func cssNumber(cval: CSSComponentValue; positive: bool): Opt[float64] =
  if isToken(cval):
    let tok = getToken(cval)
    if tok.tokenType == cttNumber:
      if not positive or tok.nvalue >= 0:
        return ok(tok.nvalue)
  return err()

proc parseValue(cvals: openArray[CSSComponentValue]; t: CSSPropertyType):
    Opt[CSSComputedValue] =
  var i = 0
  cvals.skipWhitespace(i)
  if i >= cvals.len:
    return err()
  let cval = cvals[i]
  inc i
  let v = valueType(t)
  template return_new(prop, val: untyped) =
    return ok(CSSComputedValue(v: v, prop: val))
  case v
  of cvtColor: return_new color, ?cssColor(cval)
  of cvtLength:
    case t
    of cptMaxWidth, cptMaxHeight, cptMinWidth, cptMinHeight:
      return_new length, ?cssMaxMinSize(cval)
    of cptPaddingLeft, cptPaddingRight, cptPaddingTop, cptPaddingBottom:
      return_new length, ?cssLength(cval, has_auto = false)
    #TODO content for flex-basis
    else:
      return_new length, ?cssLength(cval)
  of cvtFontStyle: return_new fontStyle, ?parseIdent[CSSFontStyle](cval)
  of cvtDisplay: return_new display, ?parseIdent[CSSDisplay](cval)
  of cvtContent: return_new content, cssContent(cvals)
  of cvtWhiteSpace: return_new whiteSpace, ?parseIdent[CSSWhiteSpace](cval)
  of cvtInteger:
    case t
    of cptFontWeight: return_new integer, ?cssFontWeight(cval)
    of cptChaColspan: return_new integer, ?cssInteger(cval, 1 .. 1000)
    of cptChaRowspan: return_new integer, ?cssInteger(cval, 0 .. 65534)
    else: assert false
  of cvtTextDecoration: return_new textdecoration, ?cssTextDecoration(cvals)
  of cvtWordBreak: return_new wordBreak, ?parseIdent[CSSWordBreak](cval)
  of cvtListStyleType:
    return_new liststyletype, ?parseIdent[CSSListStyleType](cval)
  of cvtVerticalAlign: return_new verticalAlign, ?cssVerticalAlign(cval)
  of cvtTextAlign: return_new textAlign, ?parseIdent[CSSTextAlign](cval)
  of cvtListStylePosition:
    return_new listStylePosition, ?parseIdent[CSSListStylePosition](cval)
  of cvtPosition: return_new position, ?parseIdent[CSSPosition](cval)
  of cvtCaptionSide: return_new captionSide, ?parseIdent[CSSCaptionSide](cval)
  of cvtBorderCollapse:
    return_new borderCollapse, ?parseIdent[CSSBorderCollapse](cval)
  of cvtLength2:
    let a = ?cssAbsoluteLength(cval)
    cvals.skipWhitespace(i)
    let b = if i >= cvals.len: a else: ?cssAbsoluteLength(cvals[i])
    return_new length2, (a, b)
  of cvtQuotes: return_new quotes, ?cssQuotes(cvals)
  of cvtCounterReset: return_new counterReset, ?cssCounterReset(cvals)
  of cvtImage: return_new image, ?cssImage(cval)
  of cvtFloat: return_new float, ?parseIdent[CSSFloat](cval)
  of cvtVisibility: return_new visibility, ?parseIdent[CSSVisibility](cval)
  of cvtBoxSizing: return_new boxSizing, ?parseIdent[CSSBoxSizing](cval)
  of cvtClear: return_new clear, ?parseIdent[CSSClear](cval)
  of cvtTextTransform:
    return_new textTransform, ?parseIdent[CSSTextTransform](cval)
  of cvtBgcolorIsCanvas: return err() # internal value
  of cvtFlexDirection:
    return_new flexDirection, ?parseIdent[CSSFlexDirection](cval)
  of cvtFlexWrap: return_new flexWrap, ?parseIdent[CSSFlexWrap](cval)
  of cvtNumber: return_new number, ?cssNumber(cval, t == cptFlexGrow)
  of cvtOverflow: return_new overflow, ?parseIdent[CSSOverflow](cval)
  of cvtNone: return err()

func getInitialColor(t: CSSPropertyType): CellColor =
  if t == cptBackgroundColor:
    return rgba(0, 0, 0, 0).cellColor()
  return defaultColor

func getInitialLength(t: CSSPropertyType): CSSLength =
  case t
  of cptWidth, cptHeight, cptLeft, cptRight, cptTop, cptBottom, cptMaxWidth,
      cptMaxHeight, cptMinWidth, cptMinHeight, cptFlexBasis:
    return CSSLengthAuto
  else:
    return CSSLength(auto: false, unit: cuPx, num: 0)

func getInitialInteger(t: CSSPropertyType): int =
  case t
  of cptChaColspan, cptChaRowspan:
    return 1
  of cptFontWeight:
    return 400 # normal
  else:
    return 0

func getInitialNumber(t: CSSPropertyType): float64 =
  if t == cptFlexShrink:
    return 1
  return 0

func calcInitial(t: CSSPropertyType): CSSComputedValue =
  let v = valueType(t)
  var nv: CSSComputedValue
  case v
  of cvtColor:
    nv = CSSComputedValue(v: v, color: getInitialColor(t))
  of cvtDisplay:
    nv = CSSComputedValue(v: v, display: DisplayInline)
  of cvtWordBreak:
    nv = CSSComputedValue(v: v, wordbreak: WordBreakNormal)
  of cvtLength:
    nv = CSSComputedValue(v: v, length: getInitialLength(t))
  of cvtInteger:
    nv = CSSComputedValue(v: v, integer: getInitialInteger(t))
  of cvtQuotes:
    nv = CSSComputedValue(v: v, quotes: CSSQuotes(auto: true))
  of cvtNumber:
    nv = CSSComputedValue(v: v, number: getInitialNumber(t))
  else:
    nv = CSSComputedValue(v: v)
  return nv

func getInitialTable(): array[CSSPropertyType, CSSComputedValue] =
  for t in CSSPropertyType:
    result[t] = calcInitial(t)

let defaultTable = getInitialTable()

template getDefault*(t: CSSPropertyType): CSSComputedValue =
  {.cast(noSideEffect).}:
    defaultTable[t]

func lengthShorthand(cvals: openArray[CSSComponentValue];
    props: array[4, CSSPropertyType]; global: CSSGlobalType; has_auto = true):
    Opt[seq[CSSComputedEntry]] =
  var res: seq[CSSComputedEntry] = @[]
  if global != cgtNoglobal:
    for t in props:
      res.add((t, nil, global))
    return ok(res)
  var lengths: seq[CSSComputedValue] = @[]
  var i = 0
  while i < cvals.len:
    cvals.skipWhitespace(i)
    let length = ?cssLength(cvals[i], has_auto = has_auto)
    let val = CSSComputedValue(v: cvtLength, length: length)
    lengths.add(val)
    inc i
  case lengths.len
  of 1: # top, bottom, left, right
    for i, t in props:
      res.add((t, lengths[0], cgtNoglobal))
  of 2: # top, bottom | left, right
    for i, t in props:
      res.add((t, lengths[i mod 2], cgtNoglobal))
  of 3: # top | left, right | bottom
    for i, t in props:
      let j = if i == 0:
        0 # top
      elif i == 3:
        2 # bottom
      else:
        1 # left, right
      res.add((t, lengths[j], cgtNoglobal))
  of 4: # top | right | bottom | left
    for i, t in props:
      res.add((t, lengths[i], cgtNoglobal))
  else:
    return err()
  return ok(res)

const PropertyMarginSpec = [
  cptMarginTop, cptMarginRight, cptMarginBottom, cptMarginLeft
]

const PropertyPaddingSpec = [
  cptPaddingTop, cptPaddingRight, cptPaddingBottom, cptPaddingLeft
]

proc parseComputedValues*(res: var seq[CSSComputedEntry]; name: string;
    cvals: openArray[CSSComponentValue]): Err[void] =
  var i = 0
  cvals.skipWhitespace(i)
  if i >= cvals.len:
    return err()
  let global = cssGlobal(cvals[i])
  case shorthandType(name)
  of cstNone:
    let t = propertyType(name)
    if global != cgtNoglobal:
      res.add((t, nil, global))
    else:
      res.add((t, ?cvals.parseValue(t), global))
  of cstAll:
    if global == cgtNoglobal:
      return err()
    for t in CSSPropertyType:
      res.add((t, nil, global))
  of cstMargin:
    res.add(?lengthShorthand(cvals, PropertyMarginSpec, global))
  of cstPadding:
    res.add(?lengthShorthand(cvals, PropertyPaddingSpec, global,
      has_auto = false))
  of cstBackground:
    var bgcolorval = getDefault(cptBackgroundColor)
    var bgimageval = getDefault(cptBackgroundImage)
    var valid = true
    if global == cgtNoglobal:
      for tok in cvals:
        if tok == cttWhitespace:
          continue
        if (let r = cssImage(tok); r.isSome):
          bgimageval = CSSComputedValue(v: cvtImage, image: r.get)
        elif (let r = cssColor(tok); r.isSome):
          bgcolorval = CSSComputedValue(v: cvtColor, color: r.get)
        else:
          #TODO when we implement the other shorthands too
          #valid = false
          discard
    if valid:
      res.add((cptBackgroundColor, bgcolorval, global))
      res.add((cptBackgroundImage, bgimageval, global))
  of cstListStyle:
    var positionVal = getDefault(cptListStylePosition)
    var typeVal = getDefault(cptListStyleType)
    var valid = true
    if global == cgtNoglobal:
      for tok in cvals:
        if tok == cttWhitespace:
          continue
        if (let r = parseIdent[CSSListStylePosition](tok); r.isSome):
          positionVal = CSSComputedValue(
            v: cvtListStylePosition,
            liststyleposition: r.get
          )
        elif (let r = parseIdent[CSSListStyleType](tok); r.isSome):
          typeVal = CSSComputedValue(
            v: cvtListStyleType,
            liststyletype: r.get
          )
        else:
          #TODO list-style-image
          #valid = false
          discard
    if valid:
      res.add((cptListStylePosition, positionVal, global))
      res.add((cptListStyleType, typeVal, global))
  of cstFlex:
    if global == cgtNoglobal:
      var i = 0
      cvals.skipWhitespace(i)
      if i >= cvals.len:
        return err()
      if (let r = cssNumber(cvals[i], positive = true); r.isSome):
        # flex-grow
        let val = CSSComputedValue(v: cvtNumber, number: r.get)
        res.add((cptFlexGrow, val, global))
        inc i
        cvals.skipWhitespace(i)
        if i < cvals.len:
          if not cvals[i].isToken:
            return err()
          if (let r = cssNumber(cvals[i], positive = true); r.isSome):
            # flex-shrink
            let val = CSSComputedValue(v: cvtNumber, number: r.get)
            res.add((cptFlexShrink, val, global))
            inc i
            cvals.skipWhitespace(i)
      if res.len < 1: # flex-grow omitted, default to 1
        let val = CSSComputedValue(v: cvtNumber, number: 1)
        res.add((cptFlexGrow, val, global))
      if res.len < 2: # flex-shrink omitted, default to 1
        let val = CSSComputedValue(v: cvtNumber, number: 1)
        res.add((cptFlexShrink, val, global))
      if i < cvals.len:
        # flex-basis
        let val = CSSComputedValue(v: cvtLength, length: ?cssLength(cvals[i]))
        res.add((cptFlexBasis, val, global))
      else: # omitted, default to 0px
        let val = CSSComputedValue(
          v: cvtLength,
          length: CSSLength(unit: cuPx, num: 0)
        )
        res.add((cptFlexBasis, val, global))
    else:
      res.add((cptFlexGrow, getDefault(cptFlexGrow), global))
      res.add((cptFlexShrink, getDefault(cptFlexShrink), global))
      res.add((cptFlexBasis, getDefault(cptFlexBasis), global))
  of cstFlexFlow:
    if global == cgtNoglobal:
      var i = 0
      cvals.skipWhitespace(i)
      if i >= cvals.len:
        return err()
      if (let dir = parseIdent[CSSFlexDirection](cvals[i]); dir.isSome):
        # flex-direction
        let val = CSSComputedValue(v: cvtFlexDirection, flexdirection: dir.get)
        res.add((cptFlexDirection, val, global))
        inc i
        cvals.skipWhitespace(i)
      if i < cvals.len:
        let wrap = ?parseIdent[CSSFlexWrap](cvals[i])
        let val = CSSComputedValue(v: cvtFlexWrap, flexwrap: wrap)
        res.add((cptFlexWrap, val, global))
    else:
      res.add((cptFlexDirection, getDefault(cptFlexDirection), global))
      res.add((cptFlexWrap, getDefault(cptFlexWrap), global))
  return ok()

proc parseComputedValues*(name: string; value: seq[CSSComponentValue]):
    seq[CSSComputedEntry] =
  var res: seq[CSSComputedEntry] = @[]
  if res.parseComputedValues(name, value).isSome:
    return res
  return @[]

proc applyValue*(vals: CSSComputedValues; entry: CSSComputedEntry;
    parent, previousOrigin: CSSComputedValues) =
  let parentVal = if parent != nil:
    parent[entry.t]
  else:
    nil
  case entry.global
  of cgtInherit:
    if parentVal != nil:
      vals[entry.t] = parentVal
    else:
      vals[entry.t] = getDefault(entry.t)
  of cgtInitial:
    vals[entry.t] = getDefault(entry.t)
  of cgtUnset:
    if inherited(entry.t):
      # inherit
      if parentVal != nil:
        vals[entry.t] = parentVal
      else:
        vals[entry.t] = getDefault(entry.t)
    else:
      # initial
      vals[entry.t] = getDefault(entry.t)
  of cgtRevert:
    if previousOrigin != nil:
      vals[entry.t] = previousOrigin[entry.t]
    else:
      vals[entry.t] = getDefault(entry.t)
  of cgtNoglobal:
    vals[entry.t] = entry.val

func inheritProperties*(parent: CSSComputedValues): CSSComputedValues =
  new(result)
  for prop in CSSPropertyType:
    if inherited(prop) and parent[prop] != nil:
      result[prop] = parent[prop]
    else:
      result[prop] = getDefault(prop)

func copyProperties*(props: CSSComputedValues): CSSComputedValues =
  new(result)
  result[] = props[]

func rootProperties*(): CSSComputedValues =
  new(result)
  for prop in CSSPropertyType:
    result[prop] = getDefault(prop)

# Separate CSSComputedValues of a table into those of the wrapper and the actual
# table.
func splitTable*(computed: CSSComputedValues):
    tuple[outerComputed, innnerComputed: CSSComputedValues] =
  var outerComputed, innerComputed: CSSComputedValues
  new(outerComputed)
  new(innerComputed)
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
  for prop in CSSPropertyType:
    if prop in props:
      outerComputed[prop] = computed[prop]
      innerComputed[prop] = getDefault(prop)
    else:
      outerComputed[prop] = getDefault(prop)
      innerComputed[prop] = computed[prop]
  outerComputed{"display"} = computed{"display"}
  return (outerComputed, innerComputed)
