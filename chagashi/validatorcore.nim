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
  ## On success, tvrDone is returned, and `n` is set to the last valid consumed
  ## index of `iq`. BEWARE: this may be lower than the highest index of `iq`;
  ## for example, if the first byte is valid, `n` is set to -1.
  ##
  ## If `n` is less than `iq.high`, the following steps must be taken:
  ## * If no more bytes exist in the queue, output an error.
  ## * Store the bytes `n..iq.high` in a temporary buffer
  ## * If the next call to `validate` returns tvrDone, output these
  ##   bytes. Otherwise, discard the bytes and output U+FFFD as usual.
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
  n = -1
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
