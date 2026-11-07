{.push raises: [], gcsafe.}

when NimMajor >= 2:
  import std/assertions

import std/macros
import std/math

import js/constcharp
import utils/macroutil
import utils/opt
import utils/twtstr

# Str is a copy-on-write string type with a NUL-term that is either
# * a refcounted heap string
# * a string received from QuickJS
# * a string literal (may be nil)
#
# As an optimization, heap strings support append when the refcount is 1:
# * on creation, `icap' is set to (capacity | CowFlag)
# * on dup, `icap' is zeroed if CowFlag is set, otherwise it's incremented
# * on destroy, decrement *as uint*, then free if CowFlag is set
# * on append, if CowFlag is set and `icap' isn't int.low, it's treated as
#   a string
# The way this works is that `icap' is the ref count minus 1, so that zero
# ref count coincides with having CowFlag set (thanks to wraparound on 0).
# This way, we only have to test for a single flag (if we stored the ref
# count as is, we'd have to test for the flag *and* one).
#
# In contrast, Growbuf is a flexible character buffer *without* a NUL-term.
# The idea is that strings should be constructed like:
#   var buf = initGrowbuf()
#   buf &= ...
#   buf.toStr()
# so that there is no overhead for appending NUL-terms etc.
#
# ---
#
# We prefer CoW strings over std's string for several reasons.
#
# First and foremost, multiple ownership is just convenient in a lot of
# cases.  Besides layout invalidation (where you need fast comparison
# with the string stored in the box tree), parts of the DOM such as
# MutationObserver also imply CoW strings; in fact, before CoW strings we
# used an abomination called `RefString' that just added a ref count to
# std's string (which was rather inefficient I must note).
#
# Second, it is an easy way to optimize JS -> Nim string passing.
# Although it *is* possible to do this with a separate type, often times
# you have to keep a reference to the string, and then you either copy or
# make it impossible to pass Nim-allocated strings.
#
# Third, std likes to change string's implementation which has been a
# source of annoyance over the years.  For example, Nim 1.x had no string
# literal optimization, 2.x has it, and now 2.x is experimenting with some
# prefix cache nonsense that makes string use as a buffer even more
# inconvenient.
#
# Fourth, controlling the implementation lets us do things that std
# inexplicably lacks interfaces for, e.g. in-place operations on buffers
# without filling the buffer with zero first.
#
# Finally, it allows for an inline `null` value, matching JavaScript (and
# thereby making APIs easier to implement).
type
  HeapStr = object
    icap: int # either refc or cap (if refc, we're CoW)
    p: UncheckedArray[char]

  Str* = object
    ilen: int # at least 30 bits len, plus two bits tag
    p: cstring

  StrNil* = distinct Str # Str with a nil value

  Growbuf* {.exportc: "cha_$1".} = object
    ilen: csize_t
    p*: ptr UncheckedArray[char]

  CSSOMString* = Str

{.compile("cowstr.c", "").}

# Forward declarations
proc initGrowbuf*(): Growbuf
proc initGrowbuf*(c: char): Growbuf
proc initGrowbuf*(src: openArray[char]): Growbuf
proc initGrowbufSink*(src: sink Str; cap = 0): Growbuf
proc initGrowbufUninit*(len: int): Growbuf
proc addV*(buf: var Growbuf; fmt: cstring) {.varargs,
  importc: "cha_Growbuf_$1".}
proc `[]`*(buf: var Growbuf; n: int): var char {.inline.}
proc `[]=`*(buf: var Growbuf; n: int; c: char) {.inline.}
proc toStr*(buf: sink Growbuf): Str
proc initGrowbufOfCap*(len: int): Growbuf
proc add*(dst: var Growbuf; src: Str)
proc add*(dst: var Growbuf; src: openArray[char])
proc add*(dst: var Growbuf; src: Growbuf)
proc add*(dst: var Growbuf; c: char)
proc add*(dst: var Growbuf; n: int32)
proc add*(dst: var Growbuf; n: uint32)
proc add*(dst: var Growbuf; n: int64)
proc add*(dst: var Growbuf; n: uint64)
proc addUTF8*(res: var Growbuf; u: uint32)
proc addUTF8*(res: var Growbuf; us: openArray[uint32])
proc nextUTF8*(s: Str; i: var int): uint32
proc percentEncode*(append: var Growbuf; s: Str; set: set[char];
  spaceAsPlus = false)
proc insert*(buf: var Growbuf; s: Str; i = 0)
proc delete*(s: var Growbuf; slice: Slice[int])
proc setLen*(buf: var Growbuf; len: int)
proc setLenFill*(buf: var Growbuf; len: int; c: char)
proc addHex*(buf: var Growbuf; u: uint8)

# Memory management
const
  stLit = 0
  stHeap = 1
  stQjs = 2

const StrSize = sizeof(int) * 8
const StrTagShift = StrSize - 2
const StrLenMask = not (3 shl StrTagShift)
const MaxLen = (1 shl StrTagShift) - 1

const CowTagShift = StrSize - 1
const CowFlag = 1 shl CowTagShift

proc initStr(p: cstring; len: int): Str
proc initStr*(s: openArray[char]): Str
proc newStr*(s: string): Str

template len*(s: Str): int =
  s.ilen and StrLenMask

template len*(s: Growbuf): int =
  cast[int](s.ilen)

template tag(s: Str): int =
  cast[int](uint(s.ilen) shr StrTagShift)

template heapHdr(s: Str): ptr HeapStr =
  cast[ptr HeapStr](cast[uint](s.p) - uint(offsetOf(HeapStr, p)))

# We want cowstr to be usable without pulling in QJS, so instead of
# importing quickjs we use an extern symbol.
# (If the linker complains about cha_freeCString etc, it probably means you
# forgot to add/remove -d:chaCowWithJS to the compilation command)
when not defined(chaCowWithJS):
  # export so the linker cries if we actually pulled in jsopaque
  proc freeCString(p: cstring) {.exportc: "cha_$1".} =
    discard

  proc dupCString(p: cstring): cstring {.exportc: "cha_$1".} =
    cstring(nil)
else:
  proc freeCString(p: cstring) {.importc: "cha_$1".}
  proc dupCString(p: cstring): cstring {.importc: "cha_$1".}

proc freeStr(p: cstring; tag: int) {.noinline.} =
  if likely(tag == stHeap):
    let hdr = cast[ptr HeapStr](cast[uint](p) - uint(offsetOf(HeapStr, p)))
    dealloc(hdr)
  else:
    freeCString(cast[cstring](p))

proc `=destroy`(s: var Str) =
  let tag = s.tag
  if tag == stHeap:
    let hdr = s.heapHdr
    # if (ref count - 1) was zero, this underflows and sets the CoW flag.
    # on the other hand, if the CoW flag is already set, then the
    # capacity is guaranteed to be > 0, so the decrement does nothing.
    let icap = cast[int](uint(hdr.icap) - 1)
    if (icap and CowFlag) == 0:
      hdr.icap = icap
      return
  elif tag == stLit:
    return
  freeStr(s.p, tag)

template dupStr(s: var Str) =
  let tag = s.tag
  if tag == stHeap:
    let hdr = s.heapHdr
    let icap = hdr.icap
    if (icap and CowFlag) != 0:
      hdr.icap = 1
    else:
      {.push overflowChecks: off.}
      hdr.icap = icap + 1
      {.pop.}
  elif tag == stQjs:
    s.p = dupCString(s.p)

proc `=dup`(s: Str): Str {.noinit.} =
  result.ilen = s.ilen
  result.p = s.p
  dupStr(result)

proc `=copy`(dst: var Str; src: Str) =
  `=destroy`(dst)
  dst.ilen = src.ilen
  dst.p = src.p
  dupStr(dst)

proc `=sink`(dst: var Str; src: Str) =
  `=destroy`(dst)
  dst.ilen = src.ilen
  dst.p = src.p

template heapHdr(s: Growbuf): ptr HeapStr =
  cast[ptr HeapStr](cast[uint](s.p) - uint(offsetOf(HeapStr, p)))

proc `=destroy`*(buf: var Growbuf) =
  if buf.p != nil:
    let hdr = buf.heapHdr
    dealloc(hdr)

proc `=copy`*(dst: var Growbuf; src: Growbuf) {.error.} =
  discard

proc `=sink`*(dst: var Growbuf; src: Growbuf) =
  `=destroy`(dst)
  dst.p = src.p
  dst.ilen = src.ilen

proc createHeapStr(cap: int): ptr HeapStr =
  {.push rangeChecks: off.}
  let p = cast[ptr HeapStr](alloc(sizeof(HeapStr) + cap))
  {.pop.}
  p

# Str
iterator items*(s: Str): char =
  let slen = s.len
  for i in 0 ..< slen:
    yield s.p[i]

iterator pairs*(s: Str): tuple[key: int; c: char] =
  let slen = s.len
  for i in 0 ..< slen:
    yield (i, s.p[i])

iterator points*(s: Str): uint32 {.inline.} =
  var i = 0
  while i < s.len:
    let u = s.nextUTF8(i)
    yield u

proc initStrLit*(p: cstring; len: int): Str =
  const tag = stLit shl StrTagShift
  Str(p: p, ilen: len or tag)

proc initStr(p: cstring; len: int): Str =
  assert len >= 0
  if len == 0:
    return initStrLit(p, len)
  else:
    assert len <= MaxLen
    {.push overflowChecks: off.}
    let lenz = len + 1 # for NUL term
    {.pop.}
    let hdr = createHeapStr(lenz)
    hdr.icap = 0
    copyMem(addr hdr.p, p, lenz)
    let ilen = len or (stHeap shl StrTagShift)
    return Str(p: cast[cstring](addr hdr.p), ilen: ilen)

proc initQJSStr*(p: cstring; len: int): Str =
  Str(p: p, ilen: len or (stQjs shl StrTagShift))

proc newStr*(s: string): Str =
  initStr(cstring(s), s.len)

proc initStr*(s: openArray[char]): Str =
  initGrowbuf(s).toStr()

proc toStr*(s: cstring): Str =
  initStr(s, s.len)

proc str*(s: cstring): Str =
  initStrLit(s, s.len)

macro addM*(buf: var Growbuf; ss: varargs[typed]) =
  # fmt format: like printf, but uses DLE (data link escape) instead of %
  # str: DLE S
  # growbuf: DLE G
  # char: DLE c
  # int32: DLE i
  var args: seq[NimNode]
  var fmt = newStringOfCap(32)
  let stmts = newStmtList()
  for it in ss:
    case it.kind
    of nnkCharLit:
      fmt &= char(it.intVal)
    of nnkStrLit, nnkTripleStrLit:
      fmt &= it.strVal
    else:
      let typ = it.getTypeInst()
      case typ.typeKind
      of ntyObject:
        if typ.sameType(Str.getType()) or typ.sameType(Growbuf.getType()):
          fmt &= "\x10S"
          let node = if isLocal(it):
            it
          else:
            let igb = genSym(nskLet, "igb")
            stmts.add(quote do:
              let `igb` = `it`
            )
            igb
          args.add(quote do: csize_t(`node`.len))
          args.add(quote do: `node`.p)
        else:
          error("unsupported type " & repr(typ), typ)
      of ntyChar:
        fmt &= "\x10c"
        args.add(it)
      of ntyInt:
        if sizeof(int) < 8:
          fmt &= "\x10i"
        else:
          fmt &= "\x10I"
        args.add(it)
      of ntyInt64:
        fmt &= "\x10I"
        args.add(it)
      of ntyUInt64:
        fmt &= "\x10U"
        args.add(it)
      of ntyInt32:
        fmt &= "\x10i"
        args.add(it)
      of ntyUInt32:
        fmt &= "\x10u"
        args.add(it)
      of ntyUInt16:
        fmt &= "\x10u"
        args.add(quote do: uint32(`it`))
      of ntyUInt8:
        fmt &= "\x10u"
        args.add(quote do: uint32(`it`))
      of ntyUInt:
        if sizeof(int) < 8:
          fmt &= "\x10u"
        else:
          fmt &= "\x10U"
        args.add(it)
      of ntyCString:
        fmt &= "\x10s"
        args.add(it)
      of ntyEnum:
        fmt &= "\x10s"
        # depends on enums not including NUL + CoW NimString literals
        args.add(quote do: cstring($`it`))
      else:
        error("unsupported type " & repr(typ), typ)
  let call = newNimNode(nnkCall)
  call.add(ident("addV"))
  call.add(buf)
  call.add(newStrLitNode(fmt))
  call.add(args)
  stmts.add(call)
  stmts

template myMove(x: untyped): untyped =
  when (NimMajor, NimMinor, NimPatch) < (2, 2, 2):
    move(x)
  else:
    ensureMove(x)

template initGrowbufM*(ss: varargs[untyped]): Growbuf =
  var buf: Growbuf
  buf.addM(ss)
  myMove(buf)

template initStrM*(ss: varargs[untyped]): Str =
  initGrowbufM(ss).toStr()

proc high*(s: Str): int {.inline.} =
  {.push overflowChecks: off.}
  let H = s.len - 1
  {.pop.}
  H

macro toOpenArray*(s: Str): openArray[char] =
  if isLocal(s):
    quote do:
      `s`.p.toOpenArray(0, `s`.high)
  else:
    quote do:
      let s1 = `s`
      s1.p.toOpenArray(0, s1.high)

template toOpenArray*(s: Str; lo0, hi0: int): openArray[char] =
  s.toOpenArray().toOpenArray(lo0, hi0)

template toOpenArrayByte*(s: Str; lo0, hi0: int): openArray[uint8] =
  s.toOpenArray().toOpenArrayByte(lo0, hi0)

proc high*(buf: Growbuf): int {.inline.} =
  {.push overflowChecks: off.}
  let H = buf.len - 1
  {.pop.}
  H

macro toOpenArray*(buf: Growbuf): openArray[char] =
  if isLocal(buf):
    quote do:
      `buf`.p.toOpenArray(0, `buf`.high)
  else:
    quote do:
      let s1 = `buf`
      s1.p.toOpenArray(0, s1.high)

template toOpenArray*(buf: Growbuf; lo, hi: int): openArray[char] =
  buf.toOpenArray().toOpenArray(lo, hi)

template toOpenArrayByte*(buf: Growbuf; lo, hi: int): openArray[uint8] =
  buf.toOpenArray().toOpenArrayByte(lo, hi)

proc cmpStr(a, b: openArray[char]): int =
  let alen = a.len
  let blen = b.len
  let len = min(alen, blen)
  if len > 0:
    {.push rangeChecks: off.}
    let n = cmpMem(unsafeAddr a[0], unsafeAddr b[0], len)
    {.pop.}
    if n != 0:
      return n
  cmp(alen, blen)

proc eqStr(a, b: openArray[char]): bool {.inline.} =
  let alen = a.len
  let blen = b.len
  if alen != blen:
    return false
  if alen == 0:
    return true
  {.push boundChecks: off, rangeChecks: off.}
  let n = cmpMem(unsafeAddr a[0], unsafeAddr b[0], alen)
  {.pop.}
  n == 0

proc `==`*(a: Str; b: openArray[char]): bool =
  eqStr(a.toOpenArray(), b)

proc `==`*(a: openArray[char]; b: Str): bool =
  eqStr(a, b.toOpenArray())

proc `==`*(a, b: Str): bool =
  if cast[pointer](a.p) == cast[pointer](b.p):
    return true
  eqStr(a.toOpenArray(), b.toOpenArray())

proc cmp*(a, b: Str): int =
  if cast[pointer](a.p) == cast[pointer](b.p):
    return 0
  cmpStr(a.toOpenArray(), b.toOpenArray())

proc cmp*(a: openArray[char]; b: Str): int =
  cmpStr(a, b.toOpenArray())

proc `[]`*(s: Str; n: int): char {.inline.} =
  assert n >= 0 and n < s.len
  s.p[n]

proc `[]`*(s: Str; n: BackwardsIndex): char {.inline.} =
  s[s.len - int(n)]

proc nextUTF8*(s: Str; i: var int): uint32 =
  s.toOpenArray().nextUTF8(i)

proc prevUTF8*(s: Str; i: var int): uint32 =
  s.toOpenArray().prevUTF8(i)

proc toUTF8*(us: varargs[uint32]): Str =
  var buf = initGrowbufOfCap(us.len)
  buf.addUTF8(us)
  buf.toStr()

proc `$`*(s: Str): string =
  s.toOpenArray().substr()

proc equalsIgnoreCase*(a: Str; b: openArray[char]): bool =
  a.toOpenArray().equalsIgnoreCase(b)

proc equalsIgnoreCase*(a, b: Str): bool =
  if a.p == b.p:
    return true
  a.equalsIgnoreCase(b.toOpenArray())

proc startsWith*(a: Str; b: openArray[char]; starti = 0): bool =
  a.toOpenArray().startsWith(b, starti)

proc startsWith*(a, b: Str; starti = 0): bool =
  a.startsWith(b.toOpenArray(), starti)

proc startsWithIgnoreCase*(a: Str; b: openArray[char]): bool =
  a.toOpenArray().startsWithIgnoreCase(b)

proc startsWithIgnoreCase*(a, b: Str): bool =
  a.startsWithIgnoreCase(b.toOpenArray())

proc endsWith*(a: Str; b: openArray[char]): bool =
  a.toOpenArray().endsWith(b)

proc endsWith*(a, b: Str): bool =
  a.endsWith(b.toOpenArray())

proc endsWithIgnoreCase*(a: Str; b: openArray[char]): bool =
  a.toOpenArray().endsWithIgnoreCase(b)

proc endsWithIgnoreCase*(a, b: Str): bool =
  a.endsWithIgnoreCase(b.toOpenArray())

proc contains*(s: Str; c: char): bool =
  c in s.toOpenArray()

proc contains*(s: Str; cs: set[char]): bool =
  cs in s.toOpenArray()

proc contains*(a, b: Str): bool =
  b.toOpenArray() in a.toOpenArray()

iterator split*(s: openArray[char]; sep: char): Str =
  var buf = initGrowbuf()
  var i = 0
  while i <= s.len:
    if i == s.len or s[i] == sep:
      yield move(buf).toStr()
      buf.setLen(0)
    else:
      buf &= s[i]
    inc i

iterator split*(s: openArray[char]; sep: set[char]): Str =
  var buf = initGrowbuf()
  var i = 0
  while i <= s.len:
    if i == s.len or s[i] in sep:
      yield move(buf).toStr()
    else:
      buf &= s[i]
    inc i

iterator split*(s: Str; sep: char): Str =
  for it in s.toOpenArray().split(sep):
    yield it

iterator split*(s: Str; sep: set[char]): Str =
  for it in s.toOpenArray().split(sep):
    yield it

proc containsToken*(s: Str; tok: openArray[char]): bool =
  for it in s.split(AsciiWhitespace):
    if it == tok:
      return true
  return false

proc containsTokenIgnoreCase*(s: Str; tok: openArray[char]): bool =
  for it in s.split(AsciiWhitespace):
    if it.equalsIgnoreCase(tok):
      return true
  return false

proc containsIgnoreCase*(ss: openArray[Str]; s: Str): bool =
  for it in ss:
    if it.equalsIgnoreCase(s):
      return true
  false

proc substr*(s: Str; i, j: int): Str =
  let slen = s.len
  let i = max(i, 0)
  let len = min(slen, j + 1)
  if i >= len:
    return str("")
  {.push overflowChecks: off.}
  if len == slen:
    if i == 0:
      return s
    if s.tag == stLit:
      return initStrLit(cast[cstring](unsafeAddr s.p[i]), len - i)
  let hi = len - 1
  {.pop.} # overflowChecks: off
  return initStr(s.toOpenArray(i, hi))

proc substr*(s: Str; i: int): Str =
  s.substr(i, s.high)

proc skipBlanks*(s: Str; i: int): int =
  s.toOpenArray().skipBlanks(i)

proc strip*(s: Str; leading = true; trailing = true; chars = AsciiWhitespace):
    Str =
  let slen = s.len
  var i = 0
  if leading:
    while i < slen and s[i] in chars:
      inc i
  var j = s.high
  if trailing:
    while j >= 0 and s[j] in chars:
      dec j
  return s.substr(i, j)

proc stripAndCollapse*(s: Str): Str =
  let start = s.skipBlanks(0)
  if start == 0 and AsciiWhitespace notin s.toOpenArray():
    return s
  var res = initGrowbufOfCap(s.len)
  var space = false
  for c in s.toOpenArray(start, s.high):
    let cspace = c in AsciiWhitespace
    if not cspace:
      if space:
        res &= ' '
      res &= c
    space = cspace
  res.toStr()

proc toLowerAscii2*(s: Str): Str =
  let L = s.len
  var buf = initGrowbufUninit(L)
  for i in 0 ..< L:
    buf[i] = s[i].toLowerAscii()
  buf.toStr()

proc toLowerAscii*(s: Str): Str =
  if AsciiUpperAlpha in s:
    s.toLowerAscii2()
  else:
    s

proc toUpperAscii*(s: Str): Str =
  let L = s.len
  var buf = initGrowbufUninit(L)
  for i in 0 ..< L:
    buf[i] = s[i].toUpperAscii()
  buf.toStr()

proc find*(s: Str; c: char; start = 0): int =
  s.toOpenArray().find(c, start)

proc find*(s: Str; cs: set[char]; start = 0): int =
  s.toOpenArray().find(cs, start)

proc find*(s: Str; needle: openArray[char]; start = 0; last = -1): int =
  s.toOpenArray().find(needle, start, last)

proc rfind*(s: Str; c: char; start = 0; last = -1): int =
  s.toOpenArray().rfind(c, start, last)

proc rfind*(s: Str; cc: set[char]; start = 0; last = -1): int =
  s.toOpenArray().rfind(cc, start, last)

proc findOrLen*(s: Str; c: char; start = 0): int =
  s.toOpenArray().findOrLen(c, start)

proc findOrLen*(s: Str; cc: set[char]; start = 0): int =
  s.toOpenArray().findOrLen(cc, start)

proc until*(s: Str; cc: char; starti = 0): Str =
  let endi = s.findOrLen(cc, starti)
  s.substr(starti, endi - 1)

proc until*(s: Str; cc: set[char]; starti = 0): Str =
  let endi = s.findOrLen(cc, starti)
  s.substr(starti, endi - 1)

proc untilLower*(s: Str; cc: char; starti = 0): Str =
  let endi = s.findOrLen(cc, starti)
  if starti == 0 and endi == s.len and
      AsciiUpperAlpha notin s.toOpenArray(starti, s.len - 1):
    return s
  var buf = initGrowbufUninit(endi - starti)
  for i in starti ..< endi:
    buf[i - starti] = s[i].toLowerAscii()
  buf.toStr()

proc untilLower*(s: Str; cc: set[char]; starti = 0): Str =
  let endi = s.findOrLen(cc, starti)
  if starti == 0 and endi == s.len and
      AsciiUpperAlpha notin s.toOpenArray(starti, s.len - 1):
    return s
  var buf = initGrowbufUninit(endi - starti)
  for i in starti ..< endi:
    buf[i - starti] = s[i].toLowerAscii()
  buf.toStr()

proc untilLast*(s: Str; c: char): Str =
  let i = s.rfind(c)
  if i >= 0:
    return s.substr(0, i - 1)
  return s

proc parentDir*(s: Str): Str =
  s.untilLast('/')

proc after*(s: Str; cc: char): Str =
  let i = s.find(cc)
  if i >= 0:
    return s.substr(i + 1)
  return str("")

proc afterLast*(s: Str; c: char): Str =
  let i = s.rfind(c)
  s.substr(i + 1)

proc add*(dst: var Str; src: openArray[char]) =
  let cap = dst.len + src.len
  var buf = initGrowbufSink(move(dst), cap)
  buf &= src
  dst = buf.toStr()

proc add*(dst: var Str; src: Str) =
  if dst.len == 0:
    dst = src
  else:
    dst &= src.toOpenArray()

proc insert*(dst: var Str; src: Str; i = 0) =
  let dstLen = dst.len + src.len
  var buf = initGrowbufSink(move(dst), dstLen)
  buf.insert(src, i)
  dst = buf.toStr()

proc delete*(dst: var Str; s: Slice[int]) =
  let dstLen = dst.len - s.len
  var buf = initGrowbufSink(move(dst), dstLen)
  buf.delete(s)
  dst = buf.toStr()

proc setLen*(dst: var Str; len: int) =
  var buf = initGrowbufSink(move(dst), len)
  buf.setLen(len)
  dst = buf.toStr()

proc toStr*(n: int32): Str =
  var buf = initGrowbuf()
  buf &= n
  buf.toStr()

proc toStr*(n: uint32): Str =
  var buf = initGrowbuf()
  buf &= n
  buf.toStr()

proc toStr*(n: int64): Str =
  var buf = initGrowbuf()
  buf &= n
  buf.toStr()

proc toStr*(n: uint64): Str =
  var buf = initGrowbuf()
  buf &= n
  buf.toStr()

proc parseEnumNoCase*[T: enum](s: Str): Opt[T] =
  parseEnumNoCase[T](s.toOpenArray())

proc strictParseEnum*[T: enum](s: Str): Opt[T] =
  strictParseEnum[T](s.toOpenArray())

template toStr*[T: enum](e: T): Str =
  # assumes CoW NimString literals
  let s = $e
  initStrLit(cstring(s), s.len)

proc toStr*[T: enum](s: set[T]): Str =
  var buf = initGrowbuf("{")
  for e in s:
    buf.addM(e.toStr(), ',')
  if buf.len > 1:
    buf.setLen(buf.high)
  buf &= '}'
  buf.toStr()

proc toCString*(s: Str): cstring =
  if s.p != nil:
    s.p
  else:
    cstring("")

template toCStringConst*(s: Str): cstringConst =
  cstringConst(s.toCString())

proc kebabToCamelCase*(s: Str): Str =
  var buf = initGrowbufOfCap(s.len)
  var flip = false
  for c in s:
    if c == '-':
      flip = true
    else:
      if flip:
        buf &= c.toUpperAscii()
      else:
        buf &= c
      flip = false
  if flip:
    buf &= '-'
  buf.toStr()

proc camelToKebabCase*(s: Str; dashPrefix = false): Str =
  var buf = initGrowbufOfCap(s.len)
  if dashPrefix:
    buf &= '-'
  for c in s:
    if c in AsciiUpperAlpha:
      buf &= '-'
      buf &= c.toLowerAscii()
    else:
      buf &= c
  buf.toStr()

proc cmpIgnoreCase*(a, b: Str): int =
  a.toOpenArray().cmpIgnoreCase2(b.toOpenArray())

proc controlToVisual*(u: uint32): Str =
  if u <= 0x1F:
    return initStrM("^", char(u or 0x40))
  if u == 0x7F:
    return str("^?")
  var res = initGrowbuf("[")
  res.addHex(uint8(u))
  res &= ']'
  res.toStr()

proc replaceControls*(s: Str): Str =
  var i = 0
  block dup:
    while i < s.len:
      let pi = i
      let u = s.nextUTF8(i)
      if u.isControlChar():
        i = pi
        break dup
    return s
  var buf = initGrowbufOfCap(s.len)
  buf &= s.toOpenArray(0, i - 1)
  while i < s.len:
    let u = s.nextUTF8(i)
    if u.isControlChar():
      buf &= u.controlToVisual()
    else:
      buf.addUTF8(u)
  buf.toStr()

proc percentDecode*(s: Str; starti = 0): Str =
  var i = if starti == 0: s.find('%') else: starti
  if i < 0:
    return s
  var buf = initGrowbuf(s.toOpenArray(starti, i - 1))
  while i < s.len:
    let c = s[i]
    if c != '%' or i + 2 >= s.len:
      buf &= c
    else:
      let h1 = s[i + 1].hexValue
      let h2 = s[i + 2].hexValue
      if h1 == -1 or h2 == -1:
        buf &= c
      else:
        buf &= char((h1 shl 4) or h2)
        i += 2
    inc i
  buf.toStr()

# Normalize to Unix line endings.
proc normalizeLF*(s: Str): Str =
  if '\r' notin s:
    return s
  var buf = initGrowbufOfCap(s.len)
  for i, c in s:
    if c != '\r':
      buf &= c
    elif i >= s.high or s[i + 1] != '\n':
      buf &= '\n'
  buf.toStr()

proc percentEncode*(s: Str; set: set[char]; spaceAsPlus = false): Str =
  var buf = initGrowbuf()
  buf.percentEncode(s, set, spaceAsPlus)
  buf.toStr()

proc dqEscape*(s: Str): Str =
  if '"' notin s:
    return s
  var buf = initGrowbufOfCap(s.len + 1)
  for c in s:
    if c == '"':
      buf &= '\\'
    buf &= c
  buf.toStr()

proc cssEscape*(s: Str): Str =
  if '\'' notin s:
    return s
  var buf = initGrowbufOfCap(s.len + 1)
  for c in s:
    if c == '\'':
      buf &= '\\'
    buf &= c
  buf.toStr()

proc htmlEscape*(s: openArray[char]; mode = emAll): Str =
  var buf = initGrowbufOfCap(s.len)
  var nbspMode = false
  for c in s:
    if nbspMode:
      if c == '\xA0':
        buf &= "&nbsp;"
      else:
        buf &= '\xC2' & c
      nbspMode = false
      continue
    case c
    of '<': buf &= "&lt;"
    of '>': buf &= "&gt;"
    of '&': buf &= "&amp;"
    of '\xC2': nbspMode = true
    elif c == '"' and mode <= emAttribute: buf &= "&quot;"
    elif c == '\'' and mode == emAll: buf &= "&apos;"
    else: buf &= c
  buf.toStr()

proc htmlEscape*(s: Str; mode = emAll): Str =
  s.toOpenArray().htmlEscape(mode)

proc getFileExt*(path: Str): Str =
  let n = path.rfind({'/', '.'})
  if n < 0 or path[n] != '.':
    return str("")
  return path.substr(n + 1)

const tchar = AsciiAlphaNumeric +
  {'!', '#'..'\'', '*', '+', '-', '.', '^', '_', '`', '|', '~'}

# turn value into quoted-string
proc mimeQuote*(value: Str): Str =
  block fast:
    for c in value:
      if c notin tchar:
        break fast
    return value
  var s = initGrowbufOfCap(value.len)
  s &= '"'
  for c in value:
    if c in {'"', '\\'}:
      s &= '\\'
    s &= c
  s &= '"'
  s.toStr()

proc findContentTypeAttr(contentType: Str; attrname: openArray[char]): int =
  var i = contentType.findOrLen(';')
  while i < contentType.len:
    i = contentType.skipBlanks(i + 1)
    if contentType.startsWith(attrname, i):
      i = contentType.skipBlanks(i + attrname.len)
      if i >= contentType.len:
        break
      if contentType[i] == '=':
        return i + 1
    i = contentType.findOrLen(';', i)
  return -1

proc getContentTypeAttr*(contentType: Str; attrname: openArray[char]): Str =
  var i = contentType.findContentTypeAttr(attrname)
  if i < 0:
    return str("")
  i = contentType.skipBlanks(i)
  if i >= contentType.len:
    return str("")
  if contentType[i] != '"':
    return contentType.until(';', i)
  var q = false
  var s = initGrowbuf()
  for c in contentType.toOpenArray(i + 1, contentType.high):
    if q:
      s &= c
      q = false
    elif c == '"':
      break
    elif c == '\\':
      q = true
    else:
      s &= c
  s.toStr()

proc setContentTypeAttr*(contentType: var Str; attrname, value: Str) =
  var i = contentType.findContentTypeAttr(attrname.toOpenArray())
  if i != -1:
    let j = contentType.findOrLen(';', i)
    var buf = initGrowbuf()
    buf &= contentType.toOpenArray(0, i - 1)
    buf &= value.mimeQuote()
    buf &= contentType.toOpenArray(j, contentType.high)
    contentType = buf.toStr()
  else:
    var buf = initGrowbufSink(move(contentType), 0)
    buf.addM(';', attrname, '=', value)
    contentType = buf.toStr()

proc deleteChars*(s: openArray[char]; todel: set[char]): Str =
  var buf = initGrowbufOfCap(s.len)
  for c in s:
    if c notin todel:
      buf &= c
  buf.toStr()

proc deleteChars*(s: Str; todel: set[char]): Str =
  let i = s.find(todel)
  if i < 0:
    return s
  s.toOpenArray().deleteChars(todel)

proc atob(c: char): uint8 {.inline.} =
  # see RFC 4648 table
  if c in AsciiUpperAlpha:
    return uint8(c) - uint8('A')
  if c in AsciiLowerAlpha:
    return uint8(c) - uint8('a') + 26
  if c in AsciiDigit:
    return uint8(c) - uint8('0') + 52
  if c == '+':
    return 62
  if c == '/':
    return 63
  return uint8.high

# Warning: this overrides outs.
proc atob*(outs: var Str; data: openArray[char]): Err[cstring] =
  var s = initGrowbufOfCap(data.len div 4 * 3)
  var buf = array[4, uint8].default
  var i = 0
  var j = 0
  var pad = 0
  while true:
    i = data.skipBlanks(i)
    if i >= data.len:
      break
    if data[i] == '=':
      i = data.skipBlanks(i + 1)
      inc pad
      break
    buf[j] = atob(data[i])
    if buf[j] == uint8.high:
      return err("invalid character in encoded string")
    if j == 3:
      let ob1 = (buf[0] shl 2) or (buf[1] shr 4) # 6 bits of b0 | 2 bits of b1
      let ob2 = (buf[1] shl 4) or (buf[2] shr 2) # 4 bits of b1 | 4 bits of b2
      let ob3 = (buf[2] shl 6) or buf[3]         # 2 bits of b2 | 6 bits of b3
      s &= char(ob1)
      s &= char(ob2)
      s &= char(ob3)
      j = 0
    else:
      inc j
    inc i
  if i < data.len:
    if i < data.len and data[i] == '=':
      inc pad
      inc i
    i = data.skipBlanks(i)
  if pad > 0 and j + pad != 4:
    return err("too much padding")
  if i < data.len:
    return err("invalid character after encoded string")
  if j == 3:
    let ob1 = (buf[0] shl 2) or (buf[1] shr 4) # 6 bits of b0 | 2 bits of b1
    let ob2 = (buf[1] shl 4) or (buf[2] shr 2) # 4 bits of b1 | 4 bits of b2
    s &= char(ob1)
    s &= char(ob2)
  elif j == 2:
    let ob1 = (buf[0] shl 2) or (buf[1] shr 4) # 6 bits of b0 | 2 bits of b1
    s &= char(ob1)
  elif j != 0:
    return err("incorrect number of characters in encoded string")
  outs = s.toStr()
  return ok()

const AMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

proc btoa*(s: var Growbuf; data: openArray[uint8]) =
  var i = 0
  let endw = data.len - 2
  while i < endw:
    let n = uint32(data[i]) shl 16 or
      uint32(data[i + 1]) shl 8 or
      uint32(data[i + 2])
    i += 3
    s &= AMap[n shr 18 and 0x3F]
    s &= AMap[n shr 12 and 0x3F]
    s &= AMap[n shr 6 and 0x3F]
    s &= AMap[n and 0x3F]
  if i < data.len:
    let b1 = uint32(data[i])
    inc i
    if i < data.len:
      let b2 = uint32(data[i])
      s &= AMap[b1 shr 2]                      # 6 bits of b1
      s &= AMap[b1 shl 4 and 0x3F or b2 shr 4] # 2 bits of b1 | 4 bits of b2
      s &= AMap[b2 shl 2 and 0x3F]             # 4 bits of b2
    else:
      s &= AMap[b1 shr 2]          # 6 bits of b1
      s &= AMap[b1 shl 4 and 0x3F] # 2 bits of b1
      s &= '='
    s &= '='

proc btoa*(data: openArray[uint8]): Str =
  if data.len == 0:
    return str("")
  var L = data.len div 3 * 4
  if (let rem = data.len mod 3; rem) > 0:
    L += 3 - rem
  var buf = initGrowbufOfCap(L)
  buf.btoa(data)
  buf.toStr()

proc btoa*(data: openArray[char]): Str =
  btoa(data.toOpenArrayByte(0, data.len - 1))

proc parseDimensions*(s: Str): tuple[w, h: int] =
  let xi = s.find('x')
  if xi < 0:
    return (-1, -1)
  let w = parseIntP(s.toOpenArray(0, xi - 1)).get(-1)
  let h = parseIntP(s.toOpenArray(xi + 1, s.high)).get(-1)
  return (w, h)

proc repeat*(s: Str; n: int): Str =
  var buf = initGrowbufOfCap(s.len * n)
  for i in 0 ..< n:
    buf &= s
  buf.toStr()

proc repeat*(c: char; n: int): Str =
  var buf = initGrowbuf()
  buf.setLenFill(n, c)
  buf.toStr()

proc snprintf(str: cstring; size: csize_t; format: cstring): cint
  {.header: "<stdio.h>", importc, varargs}

# From w3m
const SizeUnit = [
  cstring"b", cstring"kb", cstring"Mb", cstring"Gb", cstring"Tb", cstring"Pb",
  cstring"Eb", cstring"Zb", cstring"Bb", cstring"Yb"
]
proc convertSize*(size: uint64): Str =
  var sizepos = 0
  var csize = float32(size)
  while csize >= 999.495 and sizepos < SizeUnit.len:
    csize = csize / 1024.0
    inc sizepos
  var res = initGrowbuf()
  res.setLen(10)
  let f = floor(csize * 100 + 0.5) / 100
  #TODO use dtoa
  discard snprintf(cast[cstring](addr res[0]), csize_t(res.len), "%.3g%s", f,
    SizeUnit[sizepos])
  let n = res.toOpenArray().find('\0')
  res.setLen(max(n, 0))
  res.toStr()

# StrNil
template asStr*(s: StrNil): Str =
  Str(s)

proc `==`*(s: StrNil; n: typeof(nil)): bool =
  ## Str can be "nil" in the sense that there is a separate value reserved
  ## for this.  However, there is no nil deref, calling `len` on a "nil"
  ## Str simply yields zero, so it only makes a difference with the StrNil
  ## type.
  s.asStr.ilen == 0 and s.asStr.p == nil

proc toStrNil*(s: sink Str): StrNil =
  if s.len == 0:
    wasMoved(s)
    StrNil(initStr("", 0))
  else:
    StrNil(s)

template str*(s: typeof(nil)): StrNil =
  StrNil(initStrLit(nil, 0))

# Growbuf
iterator items*(s: Growbuf): char =
  let slen = s.len
  for i in 0 ..< slen:
    yield s.p[i]

iterator mitems*(s: Growbuf): var char =
  let slen = s.len
  for i in 0 ..< slen:
    yield s.p[i]

iterator pairs*(s: Growbuf): tuple[key: int; c: char] =
  let slen = s.len
  for i in 0 ..< slen:
    yield (i, s.p[i])

iterator mpairs*(s: Growbuf): tuple[key: int; c: var char] =
  let slen = s.len
  for i in 0 ..< slen:
    yield (i, s.p[i])

proc reserveImpl(dst: var Growbuf; nlen: int) =
  # cap length incl. NUL-term to max string length
  assert (nlen or 3) <= MaxLen
  let nlen = (nlen or 3) + 1
  if dst.p == nil:
    let cap = nlen
    let hdr = createHeapStr(cap)
    hdr.icap = cap
    dst.p = addr hdr.p
  else:
    let hdr = dst.heapHdr
    var cap = hdr.icap
    {.push overflowChecks, rangeChecks: off.}
    if cap <= 0:
      cap = 4
    elif cap <= int16.high:
      cap *= 2
    else:
      cap += cap div 2
    if nlen > cap:
      cap = nlen
    elif cap > MaxLen:
      cap = nlen
    if cap != hdr.icap:
      let hdr = cast[ptr HeapStr](realloc(hdr, sizeof(HeapStr) + cap))
      dst.p = addr hdr.p
      hdr.icap = cap
    {.pop.} # overflowChecks: off, rangeChecks: off

template reserve(dst: var Growbuf; nlen: int) =
  if dst.p == nil and nlen > 0 or dst.p != nil and dst.heapHdr.icap <= nlen:
    dst.reserveImpl(nlen)

proc initGrowbuf*(): Growbuf =
  Growbuf()

proc initGrowbufOfCap*(len: int): Growbuf =
  assert len >= 0
  var buf = initGrowbuf()
  buf.reserve(len)
  move(buf)

proc initGrowbufUninit*(len: int): Growbuf =
  var buf = initGrowbufOfCap(len)
  buf.ilen = csize_t(len)
  move(buf)

proc initGrowbuf*(src: openArray[char]): Growbuf =
  var buf = initGrowbufOfCap(src.len)
  buf &= src
  move(buf)

proc initGrowbuf*(src: Str): Growbuf =
  var buf = initGrowbufOfCap(src.len)
  buf &= src
  move(buf)

proc initGrowbufSink*(src: sink Str; cap = 0): Growbuf =
  # If src is a CoW heap string that hasn't been shared, this turns it into
  # a growbuf without copy.  Otherwise, a new growbuf with capacity `cap`
  # is allocated.
  if src.tag == stHeap:
    let hdr = src.heapHdr
    if (hdr.icap and CowFlag) != 0:
      hdr.icap = hdr.icap and not CowFlag
      let ilen = csize_t(src.len)
      var buf = Growbuf(ilen: ilen, p: cast[ptr UncheckedArray[char]](src.p))
      wasMoved(src)
      return buf
  var buf = initGrowbufOfCap(cap)
  buf &= src
  move(buf)

proc initGrowbuf*(c: char): Growbuf =
  var buf = initGrowbuf()
  buf &= c
  move(buf)

proc initGrowbuf*(src: Growbuf): Growbuf =
  var buf = initGrowbufOfCap(src.len)
  buf &= src
  move(buf)

proc initGrowbufUTF8*(us: openArray[uint32]): Growbuf =
  var buf = initGrowbuf()
  buf.addUTF8(us)
  move(buf)

proc deallocGrowbuf*(opaque, p: pointer) =
  #TODO this shouldn't be needed
  if p != nil:
    let p2 = cast[pointer](cast[uint](p) - uint(offsetOf(HeapStr, p)))
    dealloc(p2)

proc add*(dst: var Growbuf; src: openArray[char]) =
  let srcLen = src.len
  if srcLen > 0:
    let oldLen = dst.len
    let dstLen = oldLen + srcLen
    dst.reserve(dstLen)
    {.push boundChecks: off.}
    # src is ensured to be > 0 (reserve can only grow it)
    copyMem(addr dst.p[oldLen], unsafeAddr src[0], srcLen)
    {.pop.}
    dst.ilen = csize_t(dstLen)

proc setLenUninit*(buf: var Growbuf; len: int) =
  assert len >= 0
  buf.reserve(len)
  buf.ilen = csize_t(len)

proc setLenFill*(buf: var Growbuf; len: int; c: char) =
  let olen = buf.len
  buf.setLenUninit(len)
  if len > olen:
    chaMemset(buf.toOpenArray(olen, len - 1), c)

proc setLen*(buf: var Growbuf; len: int) =
  # emulate std
  buf.setLenFill(len, '\0')

proc add*(dst: var Growbuf; src: Str) =
  dst &= src.toOpenArray()

proc addCString*(dst: var Growbuf; cs: cstring) =
  let len = cs.len
  dst.add(cs.toOpenArray(0, len - 1))

proc add*(dst: var Growbuf; src: Growbuf) =
  dst.add(src.toOpenArray())

proc add*(dst: var Growbuf; c: char) =
  let oldLen = dst.len
  {.push overflowChecks: off.} # already checked in reserve
  let dstLen = oldLen + 1
  {.pop.}
  dst.reserve(dstLen)
  dst.p[oldLen] = c
  dst.ilen = csize_t(dstLen)

proc add*(dst: var Growbuf; n: uint32) =
  var buf {.noinit.}: array[10, char] # max uint32 length
  var n = n
  var i = buf.high
  {.push boundChecks, overflowChecks: off.}
  while true:
    buf[i] = char(uint8(n mod 10) + uint8('0'))
    n = n div 10
    if n == 0:
      break
    dec i
  dst &= buf.toOpenArray(i, buf.high)
  {.pop.}

proc add*(dst: var Growbuf; n: int32) =
  if n < 0:
    dst &= '-'
    dst &= 0 - uint32(n)
  else:
    dst &= uint32(n)

proc add*(dst: var Growbuf; n: uint64) =
  var buf {.noinit.}: array[20, char] # max uint64 length
  var n = n
  var i = buf.high
  {.push boundChecks, overflowChecks: off.}
  while true:
    buf[i] = char(uint8(n mod 10) + uint8('0'))
    n = n div 10
    if n == 0:
      break
    dec i
  dst &= buf.toOpenArray(i, buf.high)
  {.pop.}

proc add*(dst: var Growbuf; n: int64) =
  if n < 0:
    dst &= '-'
    dst &= 0 - uint64(n)
  else:
    dst &= uint64(n)

proc add*(dst: var Growbuf; u: uint8) =
  dst &= uint32(u)

proc add*(dst: var Growbuf; u: uint16) =
  dst &= uint32(u)

proc addUTF8*(res: var Growbuf; u: uint32) =
  if u < 0x80:
    res &= char(u)
  elif u < 0x800:
    res &= char(u shr 6 or 0xC0)
    res &= char(u and 0x3F or 0x80)
  elif u < 0x10000:
    res &= char(u shr 12 or 0xE0)
    res &= char(u shr 6 and 0x3F or 0x80)
    res &= char(u and 0x3F or 0x80)
  else:
    res &= char(u shr 18 or 0xF0)
    res &= char(u shr 12 and 0x3F or 0x80)
    res &= char(u shr 6 and 0x3F or 0x80)
    res &= char(u and 0x3F or 0x80)

proc addUTF8*(res: var Growbuf; us: openArray[uint32]) =
  for u in us:
    res.addUTF8(u)

proc `[]`*(buf: var Growbuf; n: int): var char {.inline.} =
  assert n >= 0 and n < buf.len
  buf.p[n]

proc `[]`*(buf: Growbuf; n: int): char {.inline.} =
  assert n >= 0 and n < buf.len
  buf.p[n]

proc `[]`*(buf: var Growbuf; n: BackwardsIndex): var char {.inline.} =
  buf[buf.len - int(n)]

proc `[]=`*(buf: var Growbuf; n: int; c: char) {.inline.} =
  assert n >= 0 and n < buf.len
  buf.p[n] = c

proc `[]=`*(buf: var Growbuf; n: BackwardsIndex; c: char) {.inline.} =
  buf[buf.len - int(n)] = c

proc toStr*(buf: sink Growbuf): Str =
  let bufLen = buf.len
  var tag = stLit
  if buf.p != nil: # true if and only if icap > 0
    tag = stHeap
    # NUL term is already allocated inside reserveImpl
    buf.p[bufLen] = '\0'
    buf.heapHdr.icap = buf.heapHdr.icap or CowFlag
  let p = buf.p
  wasMoved(buf)
  Str(p: cast[cstring](p), ilen: bufLen or (tag shl StrTagShift))

proc `$`*(buf: Growbuf): string =
  buf.toOpenArray().substr()

proc `==`*(a: Growbuf; b: openArray[char]): bool =
  if a.len != b.len:
    return false
  cmpStr(a.toOpenArray(), b) == 0

proc cmp*(a: openArray[char]; b: Growbuf): int =
  cmpStr(a, b.toOpenArray())

proc cmpIgnoreCase3*(a: string; b: Growbuf): int =
  cmpIgnoreCase2(a, b.toOpenArray())

proc equalsIgnoreCase*(a: Growbuf; b: openArray[char]): bool =
  a.toOpenArray().equalsIgnoreCase(b)

proc startsWithIgnoreCase*(a: Growbuf; b: openArray[char]): bool =
  a.toOpenArray().startsWithIgnoreCase(b)

proc insert*(buf: var Growbuf; s: Str; i = 0) =
  let bufLen = buf.len
  let slen = s.len
  assert i >= 0 and i <= bufLen
  if slen > 0:
    buf.setLenUninit(bufLen + slen)
    moveMem(addr buf.p[i + slen], unsafeAddr buf[i], bufLen - i)
    copyMem(addr buf[i], s.p, slen)

proc delete*(s: var Growbuf; slice: Slice[int]) =
  let a = max(0, slice.a)
  let b = min(s.high, slice.b)
  if b >= a:
    var i = a
    var j = b + 1
    let moveLen = s.len - j
    let len = moveLen + i
    if moveLen > 0:
      moveMem(addr s[i], addr s[j], moveLen)
    s.setLenUninit(len)

proc find*(s: Growbuf; c: char): int =
  s.toOpenArray().find(c)

proc substr*(src: Growbuf; i, j: int): Str =
  let i = max(0, i)
  let j = min(j, src.high)
  if i > j:
    return str("")
  initStr(src.toOpenArray(i, j))

proc substr*(src: Growbuf; i: int): Str =
  src.substr(i, src.high)

proc scan*(buf: Growbuf; s: openArray[char]; i: var int): bool =
  # advance i by s.len if buf starts with `s`, otherwise return false
  if buf.toOpenArray().startsWith(s, i):
    i += s.len
    return true
  false

const HexCharsUpper = "0123456789ABCDEF"
const HexCharsLower* = "0123456789abcdef"

proc addHex*(buf: var Growbuf; u: uint8) =
  buf &= HexCharsUpper[u shr 4]
  buf &= HexCharsUpper[u and 0xF]

proc addHex*(buf: var Growbuf; c: char) =
  buf.addHex(uint8(c))

proc percentEncode*(append: var Growbuf; c: char; set: set[char];
    spaceAsPlus = false) =
  if spaceAsPlus and c == ' ':
    append &= '+'
  elif c notin set:
    append &= c
  else:
    append &= '%'
    append.addHex(c)

proc percentEncode*(append: var Growbuf; s: Str; set: set[char];
    spaceAsPlus = false) =
  for c in s:
    append.percentEncode(c, set, spaceAsPlus)

proc rfind*(buf: Growbuf; c: char; starti = 0): int =
  buf.toOpenArray().rfind(c, starti)

proc findOrLen*(buf: Growbuf; c: char; starti = 0): int =
  buf.toOpenArray().findOrLen(c, starti)

proc until*(buf: Growbuf; cc: char; starti = 0): Str =
  let endi = buf.findOrLen(cc, starti)
  buf.substr(starti, endi - 1)

# for addV
proc reserveAdd(buf: var Growbuf; len: csize_t) {.exportc: "cha_Growbuf_$1".} =
  reserve(buf, buf.len + cast[int](len))

proc addSpan(buf: var Growbuf; p: cstring; len: csize_t) {.
    exportc: "cha_Growbuf_$1".} =
  buf &= p.toOpenArray(0, int(len) - 1)

proc addC(buf: var Growbuf; c: char) {.exportc: "cha_Growbuf_$1".} =
  buf &= c

proc addU32(buf: var Growbuf; n: uint32) {.exportc: "cha_Growbuf_$1".} =
  buf &= n

proc addI32(buf: var Growbuf; n: int32) {.exportc: "cha_Growbuf_$1".} =
  buf &= n

proc addU64(buf: var Growbuf; n: uint32) {.exportc: "cha_Growbuf_$1".} =
  buf &= n

proc addI64(buf: var Growbuf; n: int32) {.exportc: "cha_Growbuf_$1".} =
  buf &= n

{.pop.} # raises: []
