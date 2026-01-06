import monoucha/libregexp
import types/opt
import utils/twtstr

type
  Regex* = object
    bytecode*: string

  RegexCapture* = tuple # start, end, index
    s, e: int

proc compileRegex*(buf: string; flags: LREFlags; regex: var Regex): bool =
  ## Compile a regular expression using QuickJS's libregexp library.
  ## If the result is false, regex.bytecode stores the error message emitted
  ## by libregexp instead.
  ##
  ## Use `exec` to actually use the resulting bytecode on a string.
  var errorMsg = newString(64)
  var plen: cint
  let bytecode = lre_compile(plen, cstring(errorMsg), cint(errorMsg.len),
    cstring(buf), csize_t(buf.len), flags.toCInt, nil)
  if bytecode == nil: # Failed to compile.
    let i = errorMsg.find('\0')
    if i != -1:
      errorMsg.setLen(i)
    regex = Regex(bytecode: move(errorMsg))
    return false
  assert plen > 0
  var byteSeq = newString(plen)
  copyMem(addr byteSeq[0], bytecode, plen)
  dealloc(bytecode)
  regex = Regex(bytecode: move(byteSeq))
  true

type ExecContext* = object
  bytecode: ptr uint8
  tmp: seq[ptr uint8]
  base: uint

proc initContext*(regex: Regex): ExecContext =
  let bytecode = cast[ptr uint8](unsafeAddr regex.bytecode[0])
  let allocCount = lre_get_alloc_count(bytecode)
  ExecContext(
    bytecode: bytecode,
    tmp: newSeq[ptr uint8](int(allocCount))
  )

template ncaps(ctx: ExecContext): cint =
  lre_get_capture_count(ctx.bytecode)

proc cap*(ctx: ExecContext; i: int): tuple[s, e: int] =
  assert i < int(ctx.ncaps)
  let sp = ctx.tmp[i * 2]
  let ep = ctx.tmp[i * 2 + 1]
  if sp == nil or ep == nil:
    return (-1, -1)
  let s = cast[int](cast[uint](sp) - ctx.base)
  let e = cast[int](cast[uint](ep) - ctx.base)
  return (s, e)

iterator caps*(ctx: ExecContext): tuple[s, e: int] =
  for i in 0 ..< ctx.ncaps:
    yield ctx.cap(i)

iterator exec*(ctx: var ExecContext; s: openArray[char]; start = 0): cint =
  let L = cint(min(int(cint.high), s.len))
  let pcapture = if ctx.tmp.len > 0: addr ctx.tmp[0] else: nil
  let base = if s.len > 0: cast[ptr uint8](unsafeAddr s[0]) else: nil
  let flags = lre_get_flags(ctx.bytecode).toLREFlags()
  ctx.base = cast[uint](base)
  var start = cint(min(int(cint.high), start))
  while start < L:
    let ret = lre_exec(pcapture, ctx.bytecode, base, start, L, 3, nil)
    yield ret
    if ret != 1 or LRE_FLAG_GLOBAL notin flags:
      break
    let pstart = start
    start = cast[cint](ctx.cap(0).e)
    if pstart == start: # avoid infinite loop: skip the first UTF-8 char.
      inc start
      while start < s.len and uint8(s[start]) in 0x80u8 .. 0xBFu8:
        inc start

iterator matchCap*(regex: Regex; s: openArray[char]; cap: int; start = 0):
    tuple[s, e: int] =
  var ctx = initContext(regex)
  for ret in ctx.exec(s, start):
    if ret != 1:
      break
    yield ctx.cap(cap)

proc match*(regex: Regex; s: openArray[char]; start = 0): bool =
  var ctx = initContext(regex)
  for ret in ctx.exec(s, start):
    return ret == 1
  false

proc matchFirst*(regex: Regex; str: openArray[char]; start = 0):
    tuple[s, e: int] =
  var ctx = initContext(regex)
  for ret in ctx.exec(str, start):
    if ret != 1:
      break
    return ctx.cap(0)
  return (-1, -1)

proc matchLast*(regex: Regex; str: openArray[char]; start = 0):
    tuple[s, e: int] =
  var ctx = initContext(regex)
  var res = (-1, -1)
  for ret in ctx.exec(str, start):
    if ret != 1:
      break
    res = ctx.cap(0)
  res

proc countBackslashes(buf: string; i: int): int =
  var j = 0
  for i in countdown(i, 0):
    if buf[i] != '\\':
      break
    inc j
  return j

proc compileRegex(buf: string; flags: LREFlags = {}): Result[Regex, string] =
  var regex: Regex
  if not compileRegex(buf, flags, regex):
    return err(regex.bytecode)
  ok(move(regex))

# ^abcd -> ^abcd
# efgh$ -> efgh$
# ^ijkl$ -> ^ijkl$
# mnop -> ^mnop$
proc compileMatchRegex*(buf: string): Result[Regex, string] =
  if buf.len <= 0:
    return compileRegex(buf)
  if buf[0] == '^':
    return compileRegex(buf)
  if buf[^1] == '$':
    # Check whether the final dollar sign is escaped.
    if buf.len == 1 or buf[^2] != '\\':
      return compileRegex(buf)
    let j = buf.countBackslashes(buf.high - 2)
    if j mod 2 == 1: # odd, because we do not count the last backslash
      return compileRegex(buf)
    # escaped. proceed as if no dollar sign was at the end
  if buf[^1] == '\\':
    # Check if the regex contains an invalid trailing backslash.
    let j = buf.countBackslashes(buf.high - 1)
    if j mod 2 != 1: # odd, because we do not count the last backslash
      return err("unexpected end")
  var buf2 = "^"
  buf2 &= buf
  buf2 &= "$"
  return compileRegex(buf2)

type RegexCase* = enum
  rcStrict = ""
  rcIgnore = "ignore"
  rcSmart = "auto"

proc compileSearchRegex*(str: string; ignoreCase: RegexCase):
    Result[Regex, string] =
  # Emulate vim's \c/\C: override defaultFlags if one is found, then remove it
  # from str.
  # Also, replace \< and \> with \b as (a bit sloppy) vi emulation.
  var flags = {LRE_FLAG_UNICODE}
  if ignoreCase == rcIgnore:
    flags.incl(LRE_FLAG_IGNORECASE)
  var s = newStringOfCap(str.len)
  var quot = false
  var hasUpper = false
  var hasC = false
  for c in str:
    hasUpper = hasUpper or c in AsciiUpperAlpha
    if quot:
      quot = false
      case c
      of 'c':
        flags.incl(LRE_FLAG_IGNORECASE)
        hasC = true
      of 'C':
        flags.excl(LRE_FLAG_IGNORECASE)
        hasC = true
      of '<', '>': s &= "\\b"
      else: s &= '\\' & c
    elif c == '\\':
      quot = true
    else:
      s &= c
  if quot:
    s &= '\\'
  if not hasC and not hasUpper and ignoreCase == rcSmart:
    flags.incl(LRE_FLAG_IGNORECASE) # smart case
  flags.incl(LRE_FLAG_GLOBAL) # for easy backwards matching
  return compileRegex(s, flags)
