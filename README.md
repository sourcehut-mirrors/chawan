# Chame: an HTML5 parser library in Nim

## WARNING

This library is still in beta stage. The API **will** undergo significant
changes before the 1.0 release.

## Usage

Include Chame in your project using either Nimble or as a git submodule.

```
requires "https://git.sr.ht/~bptato/chame"
```

Then, check the [documentation](https://chawan.net/doc/chame/) for a
description of the API.

Note: only Nim 1.6.10+ is supported.

## Features

* Almost full compliance with the WHATWG standard. (Except for the few missing
  features listed in the following section.)
* Passes all tokenizer and tree builder tests in html5lib-tests.[^1]
* Includes a minimal DOM implementation.
* No mandatory dependencies other than the Nim standard library.
* Optional character encoding support (see minidom_enc).
* String interning support for tag and attribute names.

[^1]: Except for tree builder tests requiring JavaScript and xmlViolation
tokenizer tests.

## To-do

Some parts of the specification have not been implemented yet. These are:

* document.write
* SVG script element

...and anything else we might have forgotten about. Support for these features
is planned, even if source code comments say otherwise.

Other, non-standard-related tasks (in no particular order):

* Document minidom/minidom_enc
* Document the new interface (also explain what `Atom` does etc.)
* Optimize inefficient parts of the library

## Bugs, feedback, etc.

Feedback, complaints, etc. are accepted at
[SourceHut](https://todo.sr.ht/~bptato/chawan) or the Nim forum
[thread](https://forum.nim-lang.org/t/10367#69029).

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

If you implement a DOM library based on Chame, please notify me, so that I
can redirect users to it in this section.

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
