import monoucha/libregexp
import types/opt
import utils/twtstr

type
  Regex* = object
    bytecode*: string

  RegexCapture* = tuple # start, end, index
    s, e: int

  RegexResult* = object
    success*: bool
    captures*: seq[seq[RegexCapture]]

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

proc exec*(regex: Regex; s: openArray[char]; start = 0; length = -1;
    nocaps = false): RegexResult =
  ## execute the regex found in `bytecode`.
  let length = if length == -1:
    s.len
  else:
    length
  assert start >= 0
  if start >= length or length > int(cint.high):
    return RegexResult()
  let L = cint(length)
  let bytecode = cast[ptr uint8](unsafeAddr regex.bytecode[0])
  let allocCount = lre_get_alloc_count(bytecode)
  var capture = newSeq[ptr uint8](allocCount)
  let captureCount = lre_get_capture_count(bytecode)
  let pcapture = if capture.len > 0: addr capture[0] else: nil
  let base = cast[ptr uint8](unsafeAddr s[0])
  let flags = lre_get_flags(bytecode).toLREFlags
  var start = cint(start)
  result = RegexResult()
  while true:
    let ret = lre_exec(pcapture, bytecode, base, start, L, 3, nil)
    if ret != 1: #TODO error handling? (-1)
      break
    result.success = true
    if captureCount == 0 or nocaps:
      break
    var caps: seq[RegexCapture] = @[]
    let cstrAddress = cast[int](base)
    let ps = start
    start = cast[cint](cast[int](capture[1]) - cstrAddress)
    for i in 0 ..< captureCount:
      let s = cast[int](capture[i * 2]) - cstrAddress
      let e = cast[int](capture[i * 2 + 1]) - cstrAddress
      caps.add((s, e))
    result.captures.add(caps)
    if LRE_FLAG_GLOBAL notin flags:
      break
    if ps == start: # avoid infinite loop: skip the first UTF-8 char.
      inc start
      while start < s.len and uint8(s[start]) in 0x80u8 .. 0xBFu8:
        inc start
    if start >= length:
      break

proc match*(regex: Regex; str: string; start = 0; length = str.len): bool =
  return regex.exec(str, start, length, nocaps = true).success

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
