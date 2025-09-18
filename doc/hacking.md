# Hacking

Some notes on modifying Chawan's code.

## Style

Refer to the [NEP1](https://nim-lang.org/docs/nep1.html) for the
basics. Also, try to keep the style of existing code.

### Casing

Everything is camelCase. Enums are camelCase too, but the first part is
an abbreviation of the type name. e.g. members of `SomeEnum` start with
`se`.

Exceptions:

* Types/constants use PascalCase. enums in cssvalues use PascalCase too,
  to avoid name collisions.
* We keep style of external C libraries, which is often snake_case.
* Chame is stuck with `SCREAMING_SNAKE_CASE` for its enums. This is
  unfortunate, but does not warrant an API breakage.

Rationale: consistency.

### Wrapping

80 chars per line.

Exceptions: URL comments.

Rationale: makes it easier to edit in vi.

### Spacing

No blank lines inside procedures (and other code blocks). A single blank
line separates two procs, type defs, etc. If your proc doesn't fit on
two 24-line screens, split it up into more procs instead of inserting
blank lines.

Exceptions: none. Occasionally a proc will get larger than two screens,
and that's ok, but try to avoid it.

Rationale: makes it easier to edit in vi.

### Param separation

Semicolons, not commas. e.g.

```nim
# Good
proc foo(p1: int; p2, p3: string; p4 = true)
# Bad
proc bar(p1: int, p2, p3: string, p4 = true)
```

Rationale: makes it easier to edit in vi.

### Naming

Prefer short names. Don't copy verbose naming from the standard.

Rationale: we aren't a fruit company.

### Comments

Comment what is not obvious, don't comment what is obvious. Whether
something is obvious or not is left to your judgment.

Don't paste standard prose into the code unless you're making a
point. If you do, abridge the prose.

Rationale: common sense, copyright.

## General coding tips and guidelines

These are not hard rules, but please try to follow them unless the
situation demands otherwise.

### Features to avoid

List of Nim features/patterns that sound like a good idea but aren't,
for non-obvious reasons.

#### Exceptions

Avoid; use Result/Opt/Option instead.  Note that these kill RVO, so if
you're returning large objects, either make them `ref`, or use manual RVO
(return bool, set var param).

In new modules, always specify:

```nim
# This is an example module.
# After any header comments, but before imports:

{.push raises: [].}

import ...

# At the end of the file:
{.pop.} # raises: []
```

#### Implicit initialization

Avoid. The correct way to create an object:

```nim
let myObj = MyObject(
  param1: x,
  param2: y
  # if there's e.g. a param3 too, it's OK to leave it out and let it be
  # default initialized.
)
```

For arrays, use:

```nim
var buf1 = array[1234, char].default # when you need 0-initialization
var buf2 {.noinit.}: array[1234, char] # when you don't need 0-initialization
```

For primitive types, just set them to 0, "", etc.

#### `out` parameters

`out` parameters crash the 1.6.14 compiler.  Use `var` instead.

#### `seq` parameters

In general, `openArray` is more efficient and composes better, so prefer
that.

#### Copying operations

`substr` and `x[n..m]` copies. Try to use `toOpenArray` instead, which
is a non-copying slice.  (Obviously, you should use `substr` if you
*need* to copy.)

Note that `=` usually copies.  If you're copying a large object a lot,
you may want to set its type to `ref`.  Alternatively, you can try using
`move`, but be sure to check the generated code because often times it
doesn't work in `refc`.

Beware of `pairs` on sequences of objects; it copies.  Use `mypairs`
if you don't need mutation, `mpairs` if you do:

```nim
proc foo(objs: openArray[SomeObj]) =
  for i, obj in objs: # Bad. this copies. obj's type is "SomeObj".
    obj.bar(i)
  # import utils/twtstr to use mypairs.
  for i, obj in objs.mypairs: # OK, doesn't copy. obj's type is "lent "SomeObj".
    obj.bar(i)
  for i, obj in objs.mpairs: # OK, doesn't copy. obj's type is "var SomeObj".
    obj.i = i
```

#### `func`, `.noSideEffect`

These introduce function coloring for little to no benefit.

Just use `proc` without `.noSideEffect`.

### Fixing cyclic imports

In Nim, you can't have circular dependencies between modules. This gets
unwieldy as the HTML/DOM/etc. specs are a huge cyclic OOP mess.

The preferred workaround is global function pointer variables:

```nim
# Forward declaration hack
var forwardDeclImpl*: proc(window: Window; x, y: int) {.nimcall, raises: [].}
# in the other module:
forwardDeclImpl = proc(window: Window; x, y: int) =
  # [...]
```

Don't forget to make it `.nimcall`, and to comment "Forward declaration
hack" above. (Hopefully we can remove these once Nim supports cyclic
module dependencies.)

## Debugging

Note: following text assumes you are compiling in debug mode, i.e.
`make TARGET=debug`.

### The universal debugger

"eprint x, y" prints x, y to stderr, space separated.

Normally you can view what you printed through the M-c M-c (escape + c
twice) console. Except when you're printing from the pager, then do `cha
[...] 2>a` and check the "a" file.

Sometimes, printing to the console triggers a self-feeding loop of
printing to the console. To avoid this, disable the console buffer:
`cha [...] -o start.console-buffer=false 2>a`. Then check the "a" file.

You can also inspect open buffers from the console. Note that you must
run these *before* switching to the console buffer (i.e. before the
second M-c), or it will show info about the console buffer.

* `pager.process`: the current buffer's PID.
* `pager.cacheFile`: the current buffer's cache file.
* `pager.cacheId`: the cache ID of said file. Open the `cache:id` URL
  to view the file.

### gdb

gdb should work fine too. You can attach it to buffers by putting a long
sleep call in runBuffer, then retrieving the PID as described above.
Note that this will upset seccomp, so you should compile with
`make TARGET=debug DANGER_DISABLE_SANDBOX=1`.

### Debugging layout bugs

One possible workflow:

* Save page from your favorite graphical browser.
* Binary search the HTML by deleting half of the file at each step. Be
  careful to not remove any stylesheet LINK or STYLE tags.
* Binary search the CSS using the same method. You can format it using
  the graphical browser's developer tools.

The `-o start.console-buffer=false` trick (see above) is especially
useful when debugging a flow layout path that the console buffer also
needs.

Don't forget to add a test case after the fix:

```sh
$ cha -C test/layout/config.toml test/layout/my-test-case.html > test/layout/my-test-case.expected
```

Use `config.color.toml` and `my-test-case.color.expected` to preserve colors.

### Sandbox violations

You got a syscall number (assuming you're on Linux); look it up in the
Linux syscall table for your architecture.

To get more context on what happened, you can run
`strace -f ./cha -o start.console-buffer=false [...] 2>a`, trigger the
crash, then search for the last occurrence of "--- SIGSYS". Then search
backwards on the PID to see the last syscalls.

(Incidentally, strace also shows the syscall name, so it may be easier
to check like that than looking it up in the syscall table.)

## Resources

You may find these links useful.

### Chawan

Of particular interest in the documentation are:

* The [architecture](architecture.md) document.
* The Monoucha [manual](../lib/monoucha0/doc/manual.md), for
  JS-related documentation.

### WHATWG

* HTML: <https://html.spec.whatwg.org/multipage/>. Includes everything
  and then some more.
* DOM: <https://dom.spec.whatwg.org/>. Includes events, basic
  node-related stuff, etc.
* Encoding: <https://encoding.spec.whatwg.org/>. The core encoding
  algorithms are already implemented in Chagashi, so this is now mainly
  relevant for the TextEncoder JS interface (js/encoding).
* URL: <https://url.spec.whatwg.org/>. For some incomprehensible reason,
  it's defined as an equally incomprehensible state machine. types/url
  implements this.
* Fetch: <https://fetch.spec.whatwg.org/>. Networking stuff. Also see
  <https://xhr.spec.whatwg.org> for XMLHttpRequest.
* Web IDL: <https://webidl.spec.whatwg.org/>. Relevant for Monoucha/JS
  bindings.

Note that some of these are updated daily, such as the HTML standard.

### CSS standards

* CSS 2.1: <https://www.w3.org/TR/CSS2/>.  There's also an "Editor's
  Draft" 2.2 version: <https://drafts.csswg.org/css2/>, but so far I
  haven't encountered significant differences.

Good news is that unlike WHATWG specs, this doesn't change daily.  Bad
news is that CSS 2.1 was the last real CSS version, and newer features
are spread across a bunch of random documents with questionable status
of stability: <https://www.w3.org/Style/CSS/specs.en.html>.

### Other standards

It's unlikely that you will need these, but for completeness' sake:

* TOML: <https://toml.io/en/v1.0.0>. config.toml's base language.
* Mailcap: <https://www.rfc-editor.org/rfc/rfc1524>.
* Cookies: <https://www.rfc-editor.org/rfc/rfc6265>.
* EcmaScript: <https://tc39.es/ecma262/> is the latest draft.

### Nim docs

* Manual: <https://nim-lang.org/docs/manual.html>.  A detailed
  description of all language features.
* Standard library docs: <https://nim-lang.org/docs/lib.html>.
  Everything found in the "std/" namespace.

### MDN

<https://developer.mozilla.org/en-US/docs/Web>

MDN is useful if you don't quite understand how a certain feature is
supposed to work. It also has links to relevant standards in page
footers.
