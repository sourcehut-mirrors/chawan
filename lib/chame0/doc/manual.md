# Using Chame

Chame is divided into two parts: a low-level API ([htmlparser](htmlparser.html))
and a high-level API ([minidom](minidom.html), [minidom_cs](minidom_cs.html)).
The high-level APIs build on top of htmlparser, and are easier to use. However,
they give consumers less control than htmlparser.

Here we describe both APIs.

## Table of Contents

* [Basic concepts](#basic-concepts)
	- [Standards](#standards)
	- [String interning](#string-interning)
	- [String validation](#string-validation)
* [High-level API (minidom, minidom_cs)](#high-level-api-minidom-minidom_cs)
* [Low-level API (htmlparser)](#low-level-api-htmlparser)
	- [Functions and procedures](#functions-and-procedures)
		* [initHTML5Parser](#inithtml5parser)
		* [parseChunk](#parsechunk)
		* [finish](#finish)
	- [Generic parameters](#generic-parameters)
* [Example](#example)

## Basic concepts

### Standards

Chame implements HTML5 parsing as described in the
[Parsing HTML documents](https://html.spec.whatwg.org/multipage/parsing.html)
section of WHATWG's living standard. Note that this document may change at
any time, and newer additions might take some time to implement in Chame.

Users of the low-level API are encouraged to consult the appropriate sections
of the standard while implementing hooks provided by htmlparser.

### String interning

To achieve O(1) comparisons of tag and attribute names and a lower
memory footprint, Chame uses
[string interning](https://en.wikipedia.org/wiki/String_interning).
While minidom users can simply call the appropriate conversion functions
on Document.factory, consumers of htmlparser must implement string
interning themselves, be that through MAtomFactory or a custom solution.

### String validation

Note that (as per standard) the tokenization stage strips out all NUL
characters, so strings from the parser can be safely converted to cstrings.

htmlparser itself does no UTF-8 validation; it is up to the DOM builder to
validate the input. Non-ASCII characters are treated as opaque characters,
so parsing of ASCII-compatible character sets should just work with the caveat
that the strings from htmlparser will not necessarily be valid UTF-8. This is
not a problem in minidom, since it abstracts over this difficulty.

## High-level API (minidom, minidom_cs)

minidom has two main entry points: `parseHTML` and `parseHTMLFragment`. For
parsing documents, `parseHTML` should be used; `parseHTMLFragment` is for parsing
incomplete document fragments.

e.g. in a browser, the `innerHTML` setter would use `parseHTMLFragment`, while
`DOMParser.parseFromString` would use `parseHTML`.

The input stream must be passed as a `Stream` object from `std/streams`. Both
`parseHTML` and `parseHTMLFragment` return only when the input stream has been
completely consumed from the stream. For chunked parsing, you must use the
low-level htmlparser API instead.

minidom (and minidom_cs) implements string interning using `MAtomFactory`, and
interned strings in minidom are represented using `MAtom`s. Every `MAtom` is
guaranteed to point to a valid UTF-8 string. To convert a Nim string into an
`MAtom`, use the `MAtomFactory.strToAtom` function. To convert an `MAtom` into a
Nim string, use the `MAtomFactory.atomToStr` function.

Note: it is always more efficient to convert strings to atoms (i.e. to use
`strToAtom`) than to do it the other way. `MAtom`s are just integers, so
storing, copying, and comparing them is a lot cheaper than the same operations
with strings.

The output is a DOM tree, with the root node being a `Document`. The root
Document node also contains a `MAtomFactory` instance, which can be used to
convert `MAtom`s back to strings (through `atomToStr`).

Strings returned from minidom are guaranteed to be valid UTF-8. Note however
that minidom only understands UTF-8 documents. For parsing documents with
character sets other than UTF-8, minidom_cs must be used. The `parseHTML`
function of minidom_cs is also able to BOM sniff, interpret meta charset
tags, and optionally retry parsing with a predefined list of character
sets (using the companion character decoding library Chagashi).

## Low-level API (htmlparser)

### Functions and procedures

htmlparser has three defined procedures: `initHTML5Parser`, `parseChunk`, and
`finish`. A `getInsertionPoint` function is available as well.

#### initHTML5Parser

```nim
# Signature
proc initHTML5Parser[Handle, Atom](dombuilder: DOMBuilder[Handle, Atom],
    opts: HTML5ParserOpts[Handle, Atom]): HTML5Parser[Handle, Atom]
```

The `initHTML5Parser` procedure requires a user-defined DOMBuilder object
derived from the `DOMBuilder[Handle, Atom]` generic object reference.

To implement all interfaces necessary for htmlparser, please include
[htmlparseriface](htmlparseriface.html) in your DOM builder module; it contains
forward-declarations for all procedures that `HTML5Parser` depends on. Feel
free to study/copy [minidom](minidom.html)'s implementations.

The return value is an `HTML5Parser[Handle, Atom]` object. Note that this is
a rather large object that is passed by value; if possible, avoid copying it
at all.

#### parseChunk

```nim
# Signature
proc parseChunk[Handle, Atom](parser: var HTML5Parser[Handle, Atom],
    inputBuf: openArray[char], reprocess = false): ParseResult
```

`parseChunk` consumes all data passed in `inputBuf`. During this, the
appropriate functions (`createElementImpl`, etc.) will be called by the parser.

`parseChunk` returns a `ParseResult`, which is one of the following values:

* `PRES_CONTINUE`: the caller should continue with parsing the next chunk of
  data when it is available. (It's also fine to do delay processing the next
  call by processing something different first.)
* `PRES_STOP`: parsing was stopped by your setEncodingImpl implementation. The
  caller is expected to restart parsing from the beginning using a **new**
  `HTML5Parser` object. WARNING: do *not* re-use the current HTML5Parser for
  this.
* `PRES_SCRIPT`: a `</script>` end tag has been encountered, which immediately
  suspended parsing. In the next `parseChunk` call, the caller is expected to
  pass the **same** buffer (`inputBuf`) as in the current one. For details,
  see below.

Special care is required when implementing programs with scripting support. The
HTML5 standard requires the parser to be re-entrant for supporting the
`document.write` JavaScript function; therefore the parser suspends itself upon
encountering a `</script>` end tag, returning a `PRES_SCRIPT` `ParseResult`.

At this point, implementations have two options.

##### Option 1: Continue parsing the current buffer

If either:

* your implementation does not support `document.write`, or
* no `document.write` call has been issued by the script, or
* parsing of all buffers passed by `document.write` calls has finished,

then you can simply resume parsing the current buffer by calling `parseChunk`
again with an openArray that uses the same backing buffer, except starting
from `parser.getInsertionPoint()`. `minidom`, which pretends to support
scripting in test cases, but does not actually execute scripts, has an example
of this:

```nim
var buffer: array[4096, char]
while true:
  let n = inputStream.readData(addr buffer[0], buffer.len)
  if n == 0: break
  # res can be PRES_CONTINUE or PRES_SCRIPTING. PRES_STOP is only returned
  # on charset switching, and minidom does not support that.
  var res = parser.parseChunk(buffer.toOpenArray(0, n - 1))
  # Important: we must repeat parseChunk with the same contents for the script
  # end tag result, with reprocess = true.
  #
  # (This is only relevant for calls where scripting = true; with scripting =
  # false, PRES_SCRIPT would never be returned.)
  var ip = 0
  while res == PRES_SCRIPT and (ip += parser.getInsertionPoint(); ip != n):
    res = parser.parseChunk(buffer.toOpenArray(ip, n - 1))
parser.finish()
```

Note the while loop; `parseChunk` will return `PRES_SCRIPT` multiple times
for a single chunk if it contains several scripts.

Also note that `minidom` does not handle `PRES_STOP`, since it does not support
legacy encodings. For an implementation that *does* handle `PRES_STOP`, see
`minidom_cs`.

##### Option 2: Parse buffers passed by `document.write`

Per standard, it is possible to insert buffers into the stream from scripts
using the `document.write` function.

It is possible to implement this, but it is somewhat too involved to give a
detailed explanation of it here. Please refer to Chawan's implementation in
html/chadombuilder and html/dom. (Good luck.)

#### finish

After having parsed all chunks of your document with `parseChunk`, you **must**
call the `finish` function. This is necessary because the parser may still have
some non-flushed characters in an internal buffer. e.g. when the parser receives
the string `&gt`, it is not clear whether the character reference refers to a
"greater than" sign, or a longer character reference like `&gtrsim;`; `finish`
confirms that the reference is indeed a `&gt` sign. Also, the parser has to
execute certain actions on encountering the `EOF` token, which only `finish` can
produce.

`finish` must never be called twice, and any `parseChunk` call after `finish`
is invalid.

### Generic parameters

`initHTML5Parser` takes two generic parameters: `Handle` and `Atom`.

`Handle` is conceptually a unique pointer to a node in the document. A naive
single-threaded implementation (like minidom) may simply implement this as
a Nim `ref` to an object. However, this is not mandatory; since `Handle` is
a generic parameter, any type is accepted. For example, multi-processing
implementations that use message passing might instead prefer to use an
integer ID that refers to an object owned by a different thread.

Similarly, `Atom` is a unique pointer to a string. This means that
`DOMBuilder.strToAtom` must always return the same Atom for every string whose
contents are equivalent. Additionally, `atomToTagType` and `tagTypeToAtom` must
operate as if `TagType` values were equivalent to the contents of its
stringifier. (i.e. `tagTypeToAtom(tagType) == strToAtom($tagType)` for all tag
types except `TAG_UNKNOWN`, which is never passed to `tagTypeToAtom`.)

Note that htmlparser does not *require* an `atomToStr` procedure, so it is not
even necessary to store interned strings in a format compatible with the Nim
string type. (Obviously, some way to stringify atoms is required for most use
cases, but it need not be exposed to Chame.)

## Example

A simple example with minidom: dumps all text on a page.

```Nim
# Compile with nim c -d:ssl
# List text found between HTML tags on the target website.
import std/httpclient
import std/os
import std/strutils
import chame/minidom

if paramCount() != 1:
  echo "Usage: " & paramStr(0) & " [URL]"
  quit(1)
let client = newHttpClient()
let res = client.get(paramStr(1))
let document = parseHTML(res.bodyStream)
var stack = @[Node(document)]
while stack.len > 0:
  let node = stack.pop()
  if node of Text:
    let s = Text(node).data.strip()
    if s != "":
      echo s
  for i in countdown(node.childList.high, 0):
    stack.add(node.childList[i])
```

For more advanced usage of minidom, please study tests/tree.nim and
tests/shared/tree_common.nim which together constitute a test runner of
html5lib-tests.

For an example implementation of [htmlparseriface](htmlparseriface.html), please
check the source code of [minidom](minidom.html) (and if you need legacy charset
support, [minidom_cs](minidom_cs.html)).
