## This module implements a stateful UTF-8 validator. Unlike std/unicode's
## validateUtf8, this can be used for UTF-8 validating subsequent chunks of an
## input streams.
##
## Note that `TextValidatorUTF8` does *not* accept surrogate codepoints (a
## behavior commonly referred to as "WTF-8").

type
  TextValidatorResult* = enum
    tvrDone, tvrError

  TextValidatorUTF8* = object
    i*: int
    seen: int
    needed: int
    bounds: Slice[uint8]

proc validate*(tv: var TextValidatorUTF8, iq: openArray[uint8], n: var int):
    TextValidatorResult =
  ## Validate the UTF-8 encoded input queue `iq`.
  ##
  ## On success, tvrDone is returned, `n` is set to the length of `iq` (i.e. the
  ## whole buffer is consumed), and `tv.i` is set to 0.
  ##
  ## On failure, tvrError is returned. In this case, `n` signifies the last
  ## valid input byte, while `tv.i` signifies the next byte to be consumed in
  ## `iq` after the consumer handles the error.
  ##
  ## If tvrError is returned, the caller is expected to either signal a failure
  ## (error mode "failure"), or (error mode "replacement"):
  ##
  ## 1. Before the call, save `tv.i`
  ## 2. Call `validate`, we assume the result is `tvrError`
  ## 3. Output all bytes between the previously saved `tv.i` value and `n - 1`
  ## 4. Output a U+FFFD replacement character
  ## 5. Go to 1 (call with the same `iq` until no `tvrError` is returned).
  if tv.bounds.a == 0: # unset
    tv.bounds = 0x80u8 .. 0xBFu8
  while (let i = tv.i; i < iq.len):
    let b = iq[i]
    if tv.needed == 0:
      case b
      of 0x00u8 .. 0x7Fu8: n = tv.i
      of 0xC2u8 .. 0xDFu8:
        tv.needed = 1
      of 0xE0u8 .. 0xEFu8:
        if b == 0xE0: tv.bounds.a = 0xA0
        if b == 0xED: tv.bounds.b = 0x9F
        tv.needed = 2
      of 0xF0u8 .. 0xF4u8:
        if b == 0xF0: tv.bounds.a = 0x90
        if b == 0xF4: tv.bounds.b = 0x8F
        tv.needed = 3
      else:
        inc tv.i
        return tvrError
        {.linearScanEnd.}
    else:
      if b notin tv.bounds:
        tv.needed = 0
        tv.seen = 0
        tv.bounds = 0x80u8 .. 0xBFu8
        # prepend (no inc i)
        return tvrError
      inc tv.seen
      if tv.seen == tv.needed:
        tv.needed = 0
        tv.seen = 0
        n = tv.i
      tv.bounds = 0x80u8 .. 0xBFu8
    inc tv.i
  n = tv.i
  tv.i = 0
  tvrDone

proc finish*(tv: var TextValidatorUTF8): TextValidatorResult =
  ## Returns `tvrDone` if the validator is not waiting for additional characters
  ## to complete the current sequence.
  ##
  ## This resets the object to its initial state, so that users can call it
  ## again on a different buffer. Note that it is *not* valid to call `finish`
  ## after receiving `tvrError` from `validate`.
  result = tvrDone
  if tv.needed != 0:
    result = tvrError
  tv.needed = 0
  tv.seen = 0
  tv.i = 0
  tv.bounds = 0x80u8 .. 0xBFu8
