import validatorcore

export validatorcore

proc validateUTF8Surr*(s: string, start = 0): int =
  ## Analogous to std/unicode's validateUtf8, but also reports surrogates and
  ## has an optional `start` parameter.
  var tv = TextValidatorUTF8()
  # The initial value of `n' must be -1. (Though `validate' sets it to -1 too,
  # so this is not really needed.)
  var n = -1
  while true:
    case tv.validate(s.toOpenArrayByte(0, s.high), n)
    of tvrDone:
      if tv.finish() == tvrError:
        return n + 1
      break
    of tvrError:
      return n + 1
  return -1

proc toValidUTF8*(s: string): string =
  ## Convert `s` into a valid UTF-8 string.
  var buf = ""
  var tv = TextValidatorUTF8()
  var pi = 0
  # see above
  var n = -1
  while true:
    case tv.validate(s.toOpenArrayByte(0, s.high), n)
    of tvrDone:
      let r = tv.finish()
      if r == tvrError or buf.len > 0:
        buf &= s.substr(pi, n)
      if r == tvrError:
        buf &= "\uFFFD"
      if buf.len > 0:
        return buf
      break
    of tvrError:
      buf &= s.substr(pi, n)
      buf &= "\uFFFD"
      pi = tv.i
  return s # buf was empty; s is valid.
