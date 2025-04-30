# Interface for QuickJS libregexp.
{.push raises: [].}

import libregexp
import optshim

export LREFlags

type
  Regex* = object
    bytecode: seq[uint8]
    when defined(debug):
      buf: string

  RegexCapture* = tuple # start, end, index
    s, e: int

  RegexResult* = object
    success*: bool
    captures*: seq[seq[RegexCapture]]

when defined(debug):
  func `$`*(regex: Regex): string =
    regex.buf

proc compileRegex*(buf: string; flags: LREFlags = {}): Result[Regex, string] =
  ## Compile a regular expression using QuickJS's libregexp library.
  ## The result is either a regex, or the error message emitted by libregexp.
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
    return err(errorMsg)
  assert plen > 0
  var regex = Regex(bytecode: newSeq[uint8](plen))
  when defined(debug):
    regex.buf = buf
  copyMem(addr regex.bytecode[0], bytecode, plen)
  dealloc(bytecode)
  return ok(move(regex))

proc exec*(regex: Regex; str: string; start = 0; length = -1; nocaps = false):
    RegexResult =
  let length = if length == -1:
    str.len
  else:
    length
  assert start in 0 .. length
  let bytecode = unsafeAddr regex.bytecode[0]
  let captureCount = lre_get_capture_count(bytecode)
  var capture: ptr UncheckedArray[int] = nil
  if captureCount > 0:
    let size = sizeof(ptr uint8) * captureCount * 2
    capture = cast[ptr UncheckedArray[int]](alloc0(size))
  var cstr = cstring(str)
  let flags = lre_get_flags(bytecode).toLREFlags
  var start = start
  result = RegexResult()
  while true:
    let ret = lre_exec(cast[ptr ptr uint8](capture), bytecode,
      cast[ptr uint8](cstr), cint(start), cint(length), cint(3), nil)
    if ret != 1: #TODO error handling? (-1)
      break
    result.success = true
    if captureCount == 0 or nocaps:
      break
    var caps: seq[RegexCapture] = @[]
    let cstrAddress = cast[int](cstr)
    let ps = start
    start = capture[1] - cstrAddress
    for i in 0 ..< captureCount:
      let s = capture[i * 2] - cstrAddress
      let e = capture[i * 2 + 1] - cstrAddress
      caps.add((s, e))
    result.captures.add(caps)
    if LRE_FLAG_GLOBAL notin flags:
      break
    if start >= str.len:
      break
    if ps == start: # avoid infinite loop: skip the first UTF-8 char.
      inc start
      while start < str.len and uint8(str[start]) in 0x80u8 .. 0xBFu8:
        inc start
  if captureCount > 0:
    dealloc(capture)

proc match*(regex: Regex; str: string; start = 0; length = str.len): bool =
  return regex.exec(str, start, length, nocaps = true).success

{.pop.} # raises
