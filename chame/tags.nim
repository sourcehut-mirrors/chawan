import std/tables

type
  NodeType* = enum
    ELEMENT_NODE = 1,
    ATTRIBUTE_NODE = 2,
    TEXT_NODE = 3,
    CDATA_SECTION_NODE = 4,
    ENTITY_REFERENCE_NODE = 5,
    ENTITY_NODE = 6
    PROCESSING_INSTRUCTION_NODE = 7,
    COMMENT_NODE = 8,
    DOCUMENT_NODE = 9,
    DOCUMENT_TYPE_NODE = 10,
    DOCUMENT_FRAGMENT_NODE = 11,
    NOTATION_NODE = 12

  TagType* = enum
    TAG_UNKNOWN = ""
    TAG_APPLET = "applet"
    TAG_BIG = "big"
    TAG_HTML = "html"
    TAG_BASE = "base"
    TAG_BASEFONT = "basefont"
    TAG_BGSOUND = "bgsound"
    TAG_HEAD = "head"
    TAG_LINK = "link"
    TAG_LISTING = "listing"
    TAG_META = "meta"
    TAG_STYLE = "style"
    TAG_TITLE = "title"
    TAG_BODY = "body"
    TAG_ADDRESS = "address"
    TAG_ARTICLE = "article"
    TAG_ASIDE = "aside"
    TAG_FOOTER = "footer"
    TAG_HEADER = "header"
    TAG_H1 = "h1"
    TAG_H2 = "h2"
    TAG_H3 = "h3"
    TAG_H4 = "h4"
    TAG_H5 = "h5"
    TAG_H6 = "h6"
    TAG_HGROUP = "hgroup"
    TAG_MAIN = "main"
    TAG_NAV = "nav"
    TAG_SEARCH = "search"
    TAG_SECTION = "section"
    TAG_BLOCKQUOTE = "blockquote"
    TAG_DD = "dd"
    TAG_DIV = "div"
    TAG_DL = "dl"
    TAG_DT = "dt"
    TAG_FIGCAPTION = "figcaption"
    TAG_FIGURE = "figure"
    TAG_HR = "hr"
    TAG_LI = "li"
    TAG_OL = "ol"
    TAG_P = "p"
    TAG_PRE = "pre"
    TAG_UL = "ul"
    TAG_A = "a"
    TAG_ABBR = "abbr"
    TAG_B = "b"
    TAG_BDI = "bdi"
    TAG_BDO = "bdo"
    TAG_BR = "br"
    TAG_NOBR = "nobr"
    TAG_CITE = "cite"
    TAG_CODE = "code"
    TAG_DATA = "data"
    TAG_DFN = "dfn"
    TAG_EM = "em"
    TAG_EMBED = "embed"
    TAG_I = "i"
    TAG_KBD = "kbd"
    TAG_MARK = "mark"
    TAG_MARQUEE = "marquee"
    TAG_Q = "q"
    TAG_RB = "rb"
    TAG_RP = "rp"
    TAG_RT = "rt"
    TAG_RTC = "rtc"
    TAG_RUBY = "ruby"
    TAG_S = "s"
    TAG_SAMP = "samp"
    TAG_SMALL = "small"
    TAG_SPAN = "span"
    TAG_STRONG = "strong"
    TAG_SUB = "sub"
    TAG_SUP = "sup"
    TAG_TIME = "time"
    TAG_U = "u"
    TAG_VAR = "var"
    TAG_WBR = "wbr"
    TAG_AREA = "area"
    TAG_AUDIO = "audio"
    TAG_IMG = "img"
    TAG_IMAGE = "image"
    TAG_MAP = "map"
    TAG_TRACK = "track"
    TAG_VIDEO = "video"
    TAG_IFRAME = "iframe"
    TAG_OBJECT = "object"
    TAG_PARAM = "param"
    TAG_PICTURE = "picture"
    TAG_PORTAL = "portal"
    TAG_SOURCE = "source"
    TAG_CANVAS = "canvas"
    TAG_NOSCRIPT = "noscript"
    TAG_NOEMBED = "noembed"
    TAG_PLAINTEXT = "plaintext"
    TAG_XMP = "xmp"
    TAG_SCRIPT = "script"
    TAG_DEL = "del"
    TAG_INS = "ins"
    TAG_CAPTION = "caption"
    TAG_COL = "col"
    TAG_COLGROUP = "colgroup"
    TAG_TABLE = "table"
    TAG_TBODY = "tbody"
    TAG_TD = "td"
    TAG_TFOOT = "tfoot"
    TAG_TH = "th"
    TAG_THEAD = "thead"
    TAG_TR = "tr"
    TAG_BUTTON = "button"
    TAG_DATALIST = "datalist"
    TAG_FIELDSET = "fieldset"
    TAG_FORM = "form"
    TAG_INPUT = "input"
    TAG_KEYGEN = "keygen"
    TAG_LABEL = "label"
    TAG_LEGEND = "legend"
    TAG_METER = "meter"
    TAG_OPTGROUP = "optgroup"
    TAG_OPTION = "option"
    TAG_OUTPUT = "output"
    TAG_PROGRESS = "progress"
    TAG_SELECT = "select"
    TAG_TEXTAREA = "textarea"
    TAG_DETAILS = "details"
    TAG_DIALOG = "dialog"
    TAG_MENU = "menu"
    TAG_SUMMARY = "summary"
    TAG_BLINK = "blink"
    TAG_CENTER = "center"
    TAG_CONTENT = "content"
    TAG_DIR = "dir"
    TAG_FONT = "font"
    TAG_FRAME = "frame"
    TAG_NOFRAMES = "noframes"
    TAG_FRAMESET = "frameset"
    TAG_STRIKE = "strike"
    TAG_TT = "tt"
    TAG_TEMPLATE = "template"
    TAG_SARCASM = "sarcasm"
    TAG_MATH = "math"
    TAG_SVG = "svg"

  QuirksMode* = enum
    NO_QUIRKS, QUIRKS, LIMITED_QUIRKS

  Namespace* = enum
    NO_NAMESPACE = "",
    HTML = "http://www.w3.org/1999/xhtml",
    MATHML = "http://www.w3.org/1998/Math/MathML",
    SVG = "http://www.w3.org/2000/svg",
    XLINK = "http://www.w3.org/1999/xlink",
    XML = "http://www.w3.org/XML/1998/namespace",
    XMLNS = "http://www.w3.org/2000/xmlns/"

  NamespacePrefix* = enum
    NO_PREFIX = ""
    PREFIX_XLINK = "xlink"
    PREFIX_XML = "xml"
    PREFIX_XMLNS = "xmlns"

func getTagTypeMap(): Table[string, TagType] =
  for i in TagType:
    result[$TagType(i)] = TagType(i)

const tagTypeMap = getTagTypeMap()

func tagType*(s: string): TagType =
  if s in tagTypeMap:
    return tagTypeMap[s]
  return TAG_UNKNOWN

const AllTagTypes* = (func(): set[TagType] =
  for tag in TagType:
    result.incl(tag)
)()

const HTagTypes* = {
  TAG_H1, TAG_H2, TAG_H3, TAG_H4, TAG_H5, TAG_H6
}

# 4.10.2 Categories
const FormAssociatedElements* = {
  TAG_BUTTON, TAG_FIELDSET, TAG_INPUT, TAG_OBJECT, TAG_OUTPUT, TAG_SELECT, TAG_TEXTAREA, TAG_IMG
}

const ListedElements* = {
  TAG_FIELDSET, TAG_INPUT, TAG_OBJECT, TAG_OUTPUT, TAG_SELECT, TAG_TEXTAREA
}

const CharacterDataNodes* = {
  TEXT_NODE, CDATA_SECTION_NODE, PROCESSING_INSTRUCTION_NODE, COMMENT_NODE
}

#https://html.spec.whatwg.org/multipage/parsing.html#the-stack-of-open-elements
#NOTE MathML not implemented
#TODO SVG foreignObject, SVG desc, SVG title
const SpecialElements* = {
 TAG_ADDRESS, TAG_APPLET, TAG_AREA, TAG_ARTICLE, TAG_ASIDE, TAG_BASE,
 TAG_BASEFONT, TAG_BGSOUND, TAG_BLOCKQUOTE, TAG_BODY, TAG_BR, TAG_BUTTON,
 TAG_CAPTION, TAG_CENTER, TAG_COL, TAG_COLGROUP, TAG_DD, TAG_DETAILS, TAG_DIR,
 TAG_DIV, TAG_DL, TAG_DT, TAG_EMBED, TAG_FIELDSET, TAG_FIGCAPTION, TAG_FIGURE,
 TAG_FOOTER, TAG_FORM, TAG_FRAME, TAG_FRAMESET, TAG_H1, TAG_H2, TAG_H3, TAG_H4,
 TAG_H5, TAG_H6, TAG_HEAD, TAG_HEADER, TAG_HGROUP, TAG_HR, TAG_HTML,
 TAG_IFRAME, TAG_IMG, TAG_INPUT, TAG_KEYGEN, TAG_LI, TAG_LINK, TAG_LISTING,
 TAG_MAIN, TAG_MARQUEE, TAG_MENU, TAG_META, TAG_NAV, TAG_NOEMBED, TAG_NOFRAMES,
 TAG_NOSCRIPT, TAG_OBJECT, TAG_OL, TAG_P, TAG_PARAM, TAG_PLAINTEXT, TAG_PRE,
 TAG_SCRIPT, TAG_SEARCH, TAG_SECTION, TAG_SELECT, TAG_SOURCE, TAG_STYLE,
 TAG_SUMMARY, TAG_TABLE, TAG_TBODY, TAG_TD, TAG_TEMPLATE, TAG_TEXTAREA,
 TAG_TFOOT, TAG_TH, TAG_THEAD, TAG_TITLE, TAG_TR, TAG_TRACK, TAG_UL, TAG_WBR,
 TAG_XMP
}
