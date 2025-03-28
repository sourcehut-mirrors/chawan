# Chagashi: a Nim implementation of the WHATWG encoding standard

Chagashi is a Nim text encoding/decoding library in compliance with the WHATWG
standards for [Chawan](https://sr.ht/~bptato/chawan).

## Minimal example

First, include it in your nimble file:

```
requires "chagashi"
```

Note: following code uses the (very) high-level interface, which is rather
inefficient. Lower level interfaces are normally faster.

```Nim
# Makeshift iconv.
# Usage: nim r whatever.nim -f fromCharset -t toCharset <infile.txt >outfile.txt
import std/os, chagashi/[encoder, decoder, charset]

var fromCharset = CHARSET_UTF_8
var toCharset = CHARSET_UTF_8
for i in 1..paramCount():
  case paramStr(i)
  of "-f": fromCharset = getCharset(paramStr(i + 1))
  of "-t": toCharset = getCharset(paramStr(i + 1))
  else: assert false, "wrong parameter"
assert fromCharset != CHARSET_UNKNOWN and toCharset != CHARSET_UNKNOWN
let ins = stdin.readAll()
let insDecoded = ins.decodeAll(fromCharset)
if toCharset == CHARSET_UTF_8: # insDecoded is already UTF-8, nothing to do
  stdout.write(insDecoded)
else:
  stdout.write(insDecoded.encodeAll(toCharset))
```

## Q&A

Q: What encodings does Chagashi support?

A: All the ones you can find on
[https://encoding.spec.whatwg.org/](https://encoding.spec.whatwg.org/), no
more and no less.

Q: What is the intermediate format?

A: UTF-8, because it is the native encoding of Nim. In general, you can just
take whatever non-UTF-8 string you want to decode, pass it to the decoder, and
use the result immediately.

Q: What API should I use?

For decoding: the TextDecoderContext.decode() iterator provides a fairly
high-level API that does no unnecessary copying, and I recommend using that
where you can.

You may also use `decodeAll` when performance is less of a concern and/or you
need the output to be in a string, or reach to `decodercore` directly if you
really need the best performance. (In the latter case I recommend you study the
`decoder` module first, because it's very easy to get it wrong.)

For encoding: sorry, at the moment you need to use `encodercore` or stick with
the (non-optimal) `encodeAll`. I'll see if I can add an in-between API in the
future.

Q: Is it correct?

A: To my knowledge, yes. However, testing is still somewhat inadequate: many
single-byte encodings are not covered yet, and we do not have fuzzing either.

Q: Is it fast?

A: Not really, I have done very little optimization because it's not necessary
for my use case.

If you need better performance, feel free to complain in the
[tickets](https://todo.sr.ht/~bptato/chawan) with a specific input and I may
look into it. Patches are welcome, too.

Q: How do I decode UTF-8?

A: Like any other character set. Obviously, it won't be "decoded", just
validated, because the target charset is UTF-8 as well.

Previously, the API did not have a way to return views into the input data, so
we had a separate UTF-8 validator API. This turned out to be very annoying to
use, so the two APIs have been unified.

Q: How do I encode UTF-8?

A: You have to make sure that the UTF-8 you are passing to the encoder is at
least valid *WTF-8*. The encoder will convert surrogate codepoints to
replacement characters, but it *does not* validate the input byte stream.

To validate your input, you can run `validateUtf8()` from `std/unicode`, or
validateUTF8Surr from `chagashi/decoder`.

Q: Why no UTF-16 encoder?

A: It's not specified in the encoding standard, and I don't need one. Maybe try
std/encodings.

Q: Why replace your previous character decoding library?

A: Because it didn't work.

## Thanks

To the standard authors for writing a detailed, easy to implement specification.

Chagashi's multibyte test files (test/data.tar.xz) were borrowed from Henri
Sivonen's excellent [encoding_rs](https://github.com/hsivonen/encoding_rs)
library. His [writeup](https://hsivonen.fi/encoding_rs/) on compressing the
encoding data was also very helpful, and Chagashi applies similar
techniques.

## License

Chagashi is dedicated to the public domain. See the UNLICENSE file for details.
