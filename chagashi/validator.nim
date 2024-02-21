import validatorcore

export validatorcore

proc validateUTF8Surr*(s: string, start = 0): int =
  ## Analogous to std/unicode's validateUtf8, but also reports surrogates and
  ## has an optional `start` parameter.
  var tv = TextValidatorUTF8()
  while true:
    var n: int
    case tv.validate(s.toOpenArrayByte(0, s.high), n)
    of tvrDone:
      if tv.finish() == tvrError:
        return n
      break
    of tvrError:
      return tv.i
  return -1

proc toValidUTF8*(s: string): string =
  ## Convert `s` into a valid UTF-8 string.
  var buf = ""
  var tv = TextValidatorUTF8()
  var pi = 0
  while true:
    var n: int
    case tv.validate(s.toOpenArrayByte(0, s.high), n)
    of tvrDone:
      let fr = tv.finish()
      if fr == tvrError or buf.len > 0:
        buf &= s.substr(pi, n - 1)
      if fr == tvrError:
        buf &= "\uFFFD"
      if buf.len > 0:
        return buf
      break
    of tvrError:
      buf &= s.substr(pi, n - 1)
      buf &= "\uFFFD"
      pi = tv.i
  return s # buf was empty; s is valid.
