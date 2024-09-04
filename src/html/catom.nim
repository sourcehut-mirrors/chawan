import std/hashes
import std/macros
import std/sets
import std/strutils

import chame/tags
import monoucha/fromjs
import monoucha/javascript
import monoucha/tojs
import types/opt
import utils/twtstr

# create a static enum compatible with chame/tags

macro makeStaticAtom =
  # declare inside the macro to avoid confusion with StaticAtom0
  type
    StaticAtom0 = enum
      satAbort = "abort"
      satAcceptCharset = "accept-charset"
      satAction = "action"
      satAlign = "align"
      satAlt = "alt"
      satAsync = "async"
      satAutofocus = "autofocus"
      satBgcolor = "bgcolor"
      satBlocking = "blocking"
      satCharset = "charset"
      satChecked = "checked"
      satClass = "class"
      satClassList = "classList"
      satClick = "click"
      satColor = "color"
      satCols = "cols"
      satColspan = "colspan"
      satContent = "content"
      satCrossorigin = "crossorigin"
      satDOMContentLoaded = "DOMContentLoaded"
      satDefer = "defer"
      satDirname = "dirname"
      satDisabled = "disabled"
      satEnctype = "enctype"
      satError = "error"
      satEvent = "event"
      satFor = "for"
      satForm = "form"
      satFormaction = "formaction"
      satFormenctype = "formenctype"
      satFormmethod = "formmethod"
      satHeight = "height"
      satHref = "href"
      satId = "id"
      satIntegrity = "integrity"
      satIsmap = "ismap"
      satLanguage = "language"
      satLoad = "load"
      satLoadend = "loadend"
      satLoadstart = "loadstart"
      satMax = "max"
      satMedia = "media"
      satMethod = "method"
      satMin = "min"
      satMousewheel = "mousewheel"
      satMultiple = "multiple"
      satName = "name"
      satNomodule = "nomodule"
      satNovalidate = "novalidate"
      satOnclick = "onclick"
      satOnload = "onload"
      satProgress = "progress"
      satReadystatechange = "readystatechange"
      satReferrerpolicy = "referrerpolicy"
      satRel = "rel"
      satRequired = "required"
      satRows = "rows"
      satRowspan = "rowspan"
      satSelected = "selected"
      satSize = "size"
      satSizes = "sizes"
      satSlot = "slot"
      satSrc = "src"
      satSrcset = "srcset"
      satStyle = "style"
      satStylesheet = "stylesheet"
      satTarget = "target"
      satText = "text"
      satTimeout = "timeout"
      satTitle = "title"
      satTouchmove = "touchmove"
      satTouchstart = "touchstart"
      satType = "type"
      satUsemap = "usemap"
      satValign = "valign"
      satValue = "value"
      satWheel = "wheel"
      satWidth = "width"
  let decl = quote do:
    type StaticAtom* {.inject.} = enum
      atUnknown = ""
  let decl0 = decl[0][2]
  var seen: HashSet[string]
  for t in TagType:
    if t == TAG_UNKNOWN:
      continue
    let tn = $t
    let name = "sat" & tn[0].toUpperAscii() & tn.substr(1).kebabToCamelCase()
    seen.incl(tn)
    decl0.add(newNimNode(nnkEnumFieldDef).add(ident(name), newStrLitNode(tn)))
  for i, f in StaticAtom0.getType():
    if i == 0:
      continue
    let tn = $StaticAtom0(i - 1)
    if tn in seen:
      continue
    decl0.add(newNimNode(nnkEnumFieldDef).add(ident(f.strVal),
      newStrLitNode(tn)))
  decl

makeStaticAtom

#TODO use a better hash map
const CAtomFactoryStrMapLength = 1024 # must be a power of 2
static:
  doAssert (CAtomFactoryStrMapLength and (CAtomFactoryStrMapLength - 1)) == 0

type
  CAtom* = distinct int

  CAtomFactoryInit = object
    obj: CAtomFactoryObj

  CAtomFactoryObj = object
    strMap: array[CAtomFactoryStrMapLength, seq[CAtom]]
    atomMap: seq[string]

  #TODO could be a ptr probably
  CAtomFactory* = ref CAtomFactoryObj

const CAtomNull* = CAtom(0)

# Mandatory Atom functions
func `==`*(a, b: CAtom): bool {.borrow.}
func hash*(atom: CAtom): Hash {.borrow.}

func `$`*(a: CAtom): string {.borrow.}

func toAtom(factory: var CAtomFactoryObj; s: string): CAtom =
  let h = s.hash()
  let i = h and (factory.strMap.len - 1)
  for atom in factory.strMap[i]:
    if factory.atomMap[int(atom)] == s:
      # Found
      return atom
  # Not found
  let atom = CAtom(factory.atomMap.len)
  factory.atomMap.add(s)
  factory.strMap[i].add(atom)
  return atom

const factoryInit = (func(): CAtomFactoryInit =
  var init = CAtomFactoryInit()
  # Null atom
  init.obj.atomMap.add("")
  # StaticAtom includes TagType too.
  for sa in StaticAtom(1) .. StaticAtom.high:
    discard init.obj.toAtom($sa)
  return init
)()

proc newCAtomFactory*(): CAtomFactory =
  let factory = new(CAtomFactory)
  factory[] = factoryInit.obj
  return factory

func toAtom*(factory: CAtomFactory; s: string): CAtom =
  return factory[].toAtom(s)

func toAtom*(factory: CAtomFactory; tagType: TagType): CAtom =
  assert tagType != TAG_UNKNOWN
  return CAtom(tagType)

func toAtom*(factory: CAtomFactory; attrType: StaticAtom): CAtom =
  assert attrType != atUnknown
  return CAtom(attrType)

func toStr*(factory: CAtomFactory; atom: CAtom): string =
  return factory.atomMap[int(atom)]

func toTagType*(factory: CAtomFactory; atom: CAtom): TagType =
  let i = int(atom)
  if i <= int(TagType.high):
    return TagType(i)
  return TAG_UNKNOWN

func toStaticAtom*(factory: CAtomFactory; atom: CAtom): StaticAtom =
  let i = int(atom)
  if i <= int(StaticAtom.high):
    return StaticAtom(i)
  return atUnknown

var getFactory*: proc(ctx: JSContext): CAtomFactory {.nimcall, noSideEffect,
  raises: [].}

proc toAtom*(ctx: JSContext; atom: StaticAtom): CAtom =
  return ctx.getFactory().toAtom(atom)

proc toStaticAtom*(ctx: JSContext; atom: CAtom): StaticAtom =
  return ctx.getFactory().toStaticAtom(atom)

proc fromJS*(ctx: JSContext; val: JSValue; res: var CAtom): Opt[void] =
  var s: string
  ?ctx.fromJS(val, s)
  res = ctx.getFactory().toAtom(s)
  return ok()

proc fromJS*(ctx: JSContext; val: JSAtom; res: var CAtom): Opt[void] =
  var s: string
  ?ctx.fromJS(val, s)
  res = ctx.getFactory().toAtom(s)
  return ok()

proc toJS*(ctx: JSContext; atom: CAtom): JSValue =
  return ctx.toJS(ctx.getFactory().toStr(atom))

proc toJS*(ctx: JSContext; atom: StaticAtom): JSValue =
  return ctx.toJS($atom)
