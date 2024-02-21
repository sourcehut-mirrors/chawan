# Chagashi: a Nim implementation of the WHATWG encoding standard

Chagashi is a Nim text encoding/decoding library in compliance with the WHATWG
standards for [Chawan](https://sr.ht/~bptato/chawan).

## Minimal example

Note that this uses the high-level interface, which is rather inefficient. For
most use-cases, encodercore, decodercore and validatorcore are preferable (and
much faster).

```Nim
# Makeshift iconv (without error handling for invalid parameters).
# Usage: nim r whatever.nim -f fromCharset -t toCharset <infile.txt >outfile.txt
import std/os, chagashi/[encoder, decoder, charset, validator]

var fromCharset = CHARSET_UTF_8
var toCharset = CHARSET_UTF_8
for i in 1..paramCount():
  if paramStr(i) == "-f": fromCharset = getCharset(paramStr(i + 1))
  elif paramStr(i) == "-t": toCharset = getCharset(paramStr(i + 1))
assert fromCharset != CHARSET_UNKNOWN and toCharset != CHARSET_UNKNOWN
let ins = stdin.readAll()
let insDecoded = if fromCharset == CHARSET_UTF_8:
  ins.toValidUTF8()
else:
  newTextDecoder(fromCharset).decodeAll(ins)
let insEncoded = if toCharset == CHARSET_UTF_8:
  insDecoded
else:
  newTextEncoder(toCharset).encodeAll(insDecoded)
stdout.write(insEncoded)
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

Q: Is it correct?

A: At the moment, Chagashi only uses memory-safe operations, so at the very
least it cannot have memory errors.

Testing is still somewhat inadequate: many single-byte encodings are not
tested yet, and we do not have fuzzing either. This will be improved over time.

Q: Is it fast?

A: Reduced code size and/or complexity is generally preferred to performance.
However, it is still reasonably fast in the most common cases.

To check whether it is fast enough for your needs, you can try something like

```
$ BENCH_FILE=my_test_file BENCH_CHARSET=SomeCharset BENCH_ITER=10000 make bench
```

If you need better performance, feel free to complain in the
[tickets](https://todo.sr.ht/~bptato/chawan) with a specific input and I may
look into it. Patches are welcome, too.

Q: How do I decode UTF-8?

A: Obviously you can't decode UTF-8 into UTF-8; therefore there is no
`TextDecoderUTF8` type either, and calling `newTextDecoder` with the UTF-8
charset will panic.

Instead, use the `TextValidatorUTF8` object (in chagashi/validatorcore &
chagashi/validator) and its `validate` function. This works almost exactly like
TextDecoder, except it does not copy anything; it just goes through the input
stream, reports the number of valid characters read in the `n` variable, and
returns tdrError on error.

Q: How do I encode UTF-8?

A: You have to make sure that the UTF-8 you are passing to the encoder is at
least valid *WTF-8*. The encoder will convert surrogate codepoints to
replacement characters, but it *does not* validate the input byte stream.

To validate your input, you can run `validateUtf8()` from `std/unicode`, or the
aforementioned `TextValidatorUTF8.validate()`.

Q: Why no UTF-16 encoder?

A: It's not specified in the encoding standard, and I don't need one. Maybe try
std/encodings.

Q: Why replace your previous character decoding library?

A: It suffered from lots of serious problems:

* Its intermediate format is UTF-32, which makes the common use-case (decoding
  from/to UTF-8) rather inefficient.
* It requires copying of the input buffer, another source of inefficiency. It
  does that with non-memory-safe operations, too.
* It's based on std/streams, which is a pull-based interface: you give it a data
  source, then take whatever data you need. This works so long as you don't mind
  blocking, but gets unusable for asynchronous text decoding. Chakasu did have
  somewhat of a non-blocking interface too, but it's a kludge and requires even
  more copying.

The readme did say "no stable API", but if I'm going to completely re-design
the interface, I might as well make it a new library.

Q: I don't believe you.

A: OK, here's the real reason: it annoyed me that its name was a verb.

## Thanks

To the standard authors for writing a detailed, easy to implement specification.

Chagashi's multibyte test files (test/data.tar.xz) were borrowed from Henri
Sivonen's excellent [encoding_rs](https://github.com/hsivonen/encoding_rs)
library.

## License

Chagashi is dedicated to the public domain. See the UNLICENSE file for details.
