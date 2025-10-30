# Interface for QuickJS libregexp.
{.push raises: [].}

import libregexp

export LREFlags

type
  Regex* = object
    bytecode*: string

  CompileRegexResult* = object
    regex*: Regex ## If regex.bytecode.len == 0, compilation failed.
    error*: string ## Contains the error message on failure.

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
  let bytecode = lre_compile(addr plen, cstring(errorMsg), cint(errorMsg.len),
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
  if start >= length:
    return RegexResult()
  let bytecode = cast[ptr uint8](unsafeAddr regex.bytecode[0])
  let captureCount = lre_get_capture_count(bytecode)
  var capture: ptr UncheckedArray[int] = nil
  if captureCount > 0:
    let size = sizeof(ptr uint8) * captureCount * 2
    capture = cast[ptr UncheckedArray[int]](alloc0(size))
  let base = cast[ptr uint8](unsafeAddr s[0])
  let flags = lre_get_flags(bytecode).toLREFlags
  var start = start
  result = RegexResult()
  while true:
    let ret = lre_exec(cast[ptr ptr uint8](capture), bytecode, base,
      cint(start), cint(length), cint(3), nil)
    if ret != 1: #TODO error handling? (-1)
      break
    result.success = true
    if captureCount == 0 or nocaps:
      break
    var caps: seq[RegexCapture] = @[]
    let cstrAddress = cast[int](base)
    let ps = start
    start = capture[1] - cstrAddress
    for i in 0 ..< captureCount:
      let s = capture[i * 2] - cstrAddress
      let e = capture[i * 2 + 1] - cstrAddress
      caps.add((s, e))
    result.captures.add(caps)
    if LRE_FLAG_GLOBAL notin flags:
      break
    if start >= s.len:
      break
    if ps == start: # avoid infinite loop: skip the first UTF-8 char.
      inc start
      while start < s.len and uint8(s[start]) in 0x80u8 .. 0xBFu8:
        inc start
  if captureCount > 0:
    dealloc(capture)

proc match*(regex: Regex; str: string; start = 0; length = str.len): bool =
  return regex.exec(str, start, length, nocaps = true).success

{.pop.} # raises
