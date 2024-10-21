# Chame: an HTML5 parser library in Nim

## Usage

Include Chame in your project using either Nimble or as a git submodule.

```
requires "chame"
# optional, if you want support for charsets other than UTF-8
requires "chagashi"
```

Then, check the [documentation](https://chawan.net/doc/chame/) for a
description of the API.

Note: only Nim 1.6.10+ is supported.

## Features

* Full compliance with the WHATWG HTML parsing standard
* Passes all tokenizer and tree builder tests in html5lib-tests (except for ones
  requiring JS)
* Includes a minimal DOM implementation
* No mandatory dependencies other than the Nim standard library
* Optional character encoding support (see [minidom_cs](chame/minidom_cs.nim))
* String interning support for tag and attribute names
* Support for chunked parsing
* document.write (no actual implementation here, but it's possible to implement
  it on top of Chame)

## Manual

There is a manual available at [doc/manual.md](doc/manual.md).

## To-do

At this point the library is complete. The only remaining tasks are
optimization-related.

Also, a small module for basic minidom utilities is planned.

## Bugs, feedback, etc.

Feedback, complaints, etc. are accepted at
[SourceHut](https://todo.sr.ht/~bptato/chawan) or the Nim forum
[thread](https://forum.nim-lang.org/t/10963).

## FAQ

### Does Chame include a DOM, JavaScript, CSS, ...?

Chame just parses HTML and calls the callbacks supplied to it. JavaScript,
DOM manipulation, etc. are technically outside the scope of this project.

However, Chame includes a minimal DOM interface (intuitively named minidom)
for demonstration and testing purposes. This only implements the very basics
needed for the parser to function (and for the tests to pass), and does not
have any convenience functions (like querySelector, getElementById, etc.)

Please refer to the [Chawan](https://sr.ht/~bptato/chawan/) web browser for
an example of a complete DOM implementation that depends on Chame.

Also see [CSS3Selectors](https://github.com/Niminem/CSS3Selectors/), a CSS
selector library for Chame's minidom which allows you to run querySelector
like you can in JS.

If you implement a DOM library based on Chame, please notify me, so that I
can redirect users to it in this section.

### I read the manual, but it's too complex, I don't understand anything, help

Just call minidom.parseHTML on an std/stream.Stream object and forget about
everything else. Chances are this is enough for whatever you want to do.

### How do I implement speculative parsing?

No idea. Let me know if you figure something out.

### How do you pronounce Chame?

It is an acronym of "**Cha**wan HT**M**L (aitch-tee-e**m-e**l)." Accordingly, it is
pronounced as "cha-meh."

## Thanks

[SerenityOS](https://serenityos.org/)'s HTML parser has been used as a
reference when I found some parts of the specification unclear.

Servo's HTML parser [html5ever](https://github.com/servo/html5ever) has been
the main inspiration for Chame's API.

Finally, thanks to the standard writers for writing a very detailed
specification of the HTML5 parsing algorithm. The bulk of Chame is a direct
translation of this algorithm into Nim.

## License

Chame is dedicated to the public domain. See the UNLICENSE file for details.
