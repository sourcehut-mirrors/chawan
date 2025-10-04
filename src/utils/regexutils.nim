import std/options

import monoucha/jsregex
import monoucha/libregexp
import types/opt
import utils/twtstr

proc countBackslashes(buf: string; i: int): int =
  var j = 0
  for i in countdown(i, 0):
    if buf[i] != '\\':
      break
    inc j
  return j

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

proc compileSearchRegex*(str: string; ignoreCase: Option[bool]):
    Result[Regex, string] =
  # Emulate vim's \c/\C: override defaultFlags if one is found, then remove it
  # from str.
  # Also, replace \< and \> with \b as (a bit sloppy) vi emulation.
  var flags = {LRE_FLAG_UNICODE}
  if ignoreCase.isSome and ignoreCase.get:
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
  if not hasC and not hasUpper and ignoreCase.isNone:
    flags.incl(LRE_FLAG_IGNORECASE) # smart case
  flags.incl(LRE_FLAG_GLOBAL) # for easy backwards matching
  return compileRegex(s, flags)
