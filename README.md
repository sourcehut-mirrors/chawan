# Chame: an HTML5 parser library in Nim

## WARNING

This library is still in beta stage. The API may undergo significant changes
before the 1.0 release.

## Usage

Include Chame in your project using either Nimble or as a git submodule.

```
requires "https://git.sr.ht/~bptato/chame"
```

Then, check the [documentation](https://bptato.srht.site/htmlparser.html) for
a description of the API.

## Features

* Almost full compliance with the WHATWG standard. (Except for the few missing
  features listed in the following section.)
* Supports all encodings specified in the WHATWG encoding standard.
* Includes a minimal DOM implementation.

## To-do

Some parts of the specification have not been implemented yet. These are:

* document.write
* MathML
* Custom elements

...and anything else we might have forgotten about. Support for these features
is planned, even if source code comments say otherwise.

Other, non-standard-related tasks (in no particular order):

* Allow disabling non-UTF-8 decoders.
* Document minidom.
* Integrate html5lib-tests.
* Optimize inefficient parts of the library.

## Bugs, feedback, etc.

Bug reports are accepted at SourceHut or the Nim forum thread.

## FAQ

### Does Chame include a DOM, JavaScript, CSS, ...?

Chame just parses HTML and calls the callbacks supplied to it. JavaScript,
DOM manipulation, etc. are technically outside the scope of this project.

However, Chame includes a minimal DOM interface (intuitively named minidom)
for demonstration & testing purposes. This only implements the very basics
needed for the parser to function, and does not have any convenience functions
(like querySelector, getElementById, etc.) Please refer to the
[Chawan](https://sr.ht/~bptato/chawan/) web browser for an example of a
complete DOM implementation that depends on Chame.

Please notify me if you implement a DOM library based on Chame, so that I
can redirect users to it in this section.

### How do you pronounce Chame?

It is an acronym of "*Cha*wan HTML (aitch-tee-e*m-e*l)." Accordingly, it is
pronounced as "cha-meh."

## Thanks

SerenityOS's HTML parser has been used as a reference when I found some
parts of the specification unclear.

Servo's HTML parser (html5ever) has been the main inspiration for Chame's API.

Finally, thanks to the standard writers for writing a very detailed
specification of the HTML5 parsing algorithm. The bulk of Chame is a direct
translation of this algorithm into Nim.

## License

Chame is dedicated to the public domain. See the UNLICENSE file for details.
