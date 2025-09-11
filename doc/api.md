<!-- MANON
% CHA-API 7
MANOFF -->

# Chawan's command API

As described in <!-- MANOFF -->the [config](config.md) documentation,<!-- MANON -->
<!-- MANON **cha-config**(5), MANOFF --> keypress combinations can be bound to
actions.

An action can be either a JavaScript expression, or a command defined in the
`[cmd]` section of config.toml.  For example, the following works:

```
gpn = 'n => pager.alert(n)' # e.g. 2gpn prints `2' to the status line
```

Note however, that JavaScript functions must be called with an appropriate
`this` value. Unfortunately, this also means that the following does not work:

```
gpn = 'pager.alert' # broken!!!
```

To work around this limitation, actions have to wrap the target function in a
closure, as above. However, this has very poor reusability; for more complex
actions, you would have to copy and paste the entire function every time you
re-bind it or call it from a different function.

To fix this, it is possible to define a command in the `[cmd]` section:

```toml
[cmd.my.namespace]
showNumber = 'n => pager.alert(n)'
```

`my.namespace` can be anything you want; it is to avoid collisions when
including multiple configs. Avoid setting it to `pager` or `line`, because these
are used by the default config.

Now you can call `cmd.my.namespace.showNumber()` from any other function, or
just include it in an action:

```toml
'gpn' = 'cmd.my.namespace.showNumber'
```

## Interfaces

### Client

The global object (`globalThis`) implements the `Client` interface. Documented
functions of this are:

<table>

<tr>
<th>Property</th>
<th>Description</th>
</tr>

<tr>
<td>`quit()`</td>
<td>Exit the browser.</td>
</tr>

<tr>
<td>`suspend()`</td>
<td>Temporarily suspend the browser, by delivering the client process a
SIGTSTP signal.
<p>
Note: this suspends the entire process group.</td>
</tr>

<tr>
<td>`readFile(path)`</td>
<td>Read a file at `path`.
<p>
Returns the file's content as a string, or null if the file does not
exist.
</td>
</tr>

<tr>
<td>`writeFile(path, content)`</td>
<td>Write `content` to the file at `path`.
<p>
Throws a TypeError if this failed for whatever reason.
</td>
</tr>

<tr>
<td>`getenv(name, fallback = null)`</td>
<td>Get an environment variable by `name`.
<p>
Returns `fallback` if the variable does not exist.
</td>
</tr>

<tr>
<td>`setenv(name, value)`</td>
<td>Set an environment variable by `name`.
<p>
Throws a type error if the operation failed (e.g. because the variable's
size exceeded an OS-specified limit.)
</td>
</tr>

<tr>
<td>`pager`</td>
<td>The pager object. Implements `Pager`, as described below.</td>
</tr>

<tr>
<td>`line`</td>
<td>The line editor. Implements `LineEdit`, as described below.</td>
</tr>

<tr>
<td>`config`</td>
<td>The config object.
<p>
A currently incomplete interface for retrieving and setting
configuration options. In general, names are the same as in config.toml,
except all `-` (ASCII hyphen) characters are stripped and the next
character is upper-cased. e.g. `external.cgi-dir` can be
queried as `config.external.cgiDir`, etc.
<p>
Setting individual options sometimes works, but sometimes they do not
get propagated as expected. Consider this an experimental API.
<p>
Currently, `siteconf`, `protocol` and `omnirule` values are not exposed
to JS.
<p>
The configuration directory itself can be queried as `config.dir`.</td>
</tr>

</table>

`Client` also implements various web standards normally available on the
`Window` object on websites, e.g. fetch().  Note however that it does *not* give
access to JS objects in buffers, so e.g. `globalThis.document` is not available.

### Pager

`Pager` is a separate interface from `Client` that gives access to the
pager (i.e. browser chrome).  It is accessible as `globalThis.pager`,
or simply `pager`.

Note that there is a quirk of questionable value, where accessing
properties that do not exist on the pager will dispatch those to the
current buffer (`pager.buffer`).  So if you see e.g. `pager.url`, that
is actually equivalent to `pager.buffer.url`, because `Pager` has no
`url` getter.

Following properties (functions/getters) are defined by `Pager`:

<table>

<tr>
<th>Property</th>
<th>Description</th>
</tr>

<tr>
<td>`load(url = pager.buffer.url)`</td>
<td>Put the specified address into the URL bar, and optionally load it.
<p>
Note that this performs auto-expansion of URLs, so Chawan will expand any
matching omni-rules (e.g. search), try to open schemeless URLs with the default
scheme/local files, etc.
<p>
Opens a prompt with the current URL when no parameters are specified; otherwise,
the string passed is displayed in the prompt.
<p>
**Deprecated quirk**: If this string ends with a newline
(e.g. `pager.load("about:chawan\n")`), the URL is loaded directly.
This usage isn't recommended; use loadSubmit instead.
</td>
</tr>

<tr>
<td>`loadSubmit(url)`</td>
<td>Act as if `url` had been entered to the URL bar.  `loadSubmit`
differs from `gotoURL` in that it also evaluates omni-rules, tries to
prepend a scheme, etc.
</td>
</tr>

<tr>
<td>`gotoURL(url, options = {replace: null, contentType: null, save: false})`</td>
<td>Go to the specified URL immediately (without a prompt). This differs from
`loadSubmit` in that it loads the exact URL as passed (no prepending https,
etc.)
<p>
When `replace` is set, the new buffer may replace the old one if it loads
successfully.
<p>
When `contentType` is set, the new buffer's content type is
forcefully set to that string.
<p>
When `save` is true, the user is prompted to save the resource instead
of displaying it in a buffer.
<p>
</td>
</tr>

<tr>
<td>`traverse(dir)`</td>
<td>Switch to the next buffer in direction `dir`, interpreted as in
`Buffer#find`.</td>
</tr>

<tr>
<td>`nextBuffer()`, `prevBuffer()`, `nextSiblingBuffer()`,
`prevSiblingBuffer()`, `parentBuffer()`</td>
<td>Same as `traverse("next")`, `traverse("prev")`,
`traverse("next-sibling")`, `traverse("prev-sibling")`, and
`traverse("parent")`.
</td>
</tr>

<tr>
<td>`dupeBuffer()`</td>
<td>Duplicate the current buffer by loading its source in a new
buffer.</td>
</tr>

<tr>
<td>`discardBuffer(buffer = pager.buffer, dir =
pager.navDirection)`</td>
<td>Discard `buffer`, then move back to the buffer opposite to `dir`
(interpreted as in `Buffer#find`).</td>
</tr>

<tr>
<td>`discardTree()`</td>
<td>Discard all child buffers of the current buffer.</td>
</tr>

<tr>
<td>`reload()`</td>
<td>Open a new buffer with the current buffer's URL, replacing the current
buffer.</td>
</tr>

<tr>
<td>`reshape()`</td>
<td>Reshape the current buffer (=render the current page anew.)</td>
</tr>

<tr>
<td>`redraw()`</td>
<td>Redraw screen contents. Useful if something messed up the display.</td>
</tr>

<tr>
<td>`toggleSource()`</td>
<td>If viewing an HTML buffer, open a new buffer with its source. Otherwise,
open the current buffer's contents as HTML.</td>
</tr>

<tr>
<td>`lineInfo()`</td>
<td>Display information about the current line.</td>
</tr>

<tr>
<td>`searchForward()`, `searchBackward()`</td>
<td>Search forward/backward for a string in the current buffer.</td>
</tr>

<tr>
<td>`isearchForward()`, `isearchBackward()`</td>
<td>Incremental-search forward/backward for a string, highlighting the
first result.</td>
</tr>

<tr>
<td>`gotoLine(n?)`</td>
<td>Go to the line passed as the first argument.
<p>
If no arguments were specified, an input window for entering a line is
shown.</td>
</tr>

<tr>
<td>`searchNext(n = 1)`, `searchPrev(n = 1)`</td>
<td>Jump to the nth next/previous search result.</td>
</tr>

<tr>
<td>`peek()`</td>
<td>Display an alert message of the current URL.</td>
</tr>

<tr>
<td>`peekCursor()`</td>
<td>Display an alert message of the URL or title under the cursor. Multiple
calls allow cycling through the two. (i.e. by default, press u once -> title,
press again -> URL)</td>
</tr>

<tr>
<td>`showFullAlert()`</td>
<td>Show the last alert inside the line editor.</td>
</tr>

<tr>
<td>`ask(prompt)`</td>
<td>Ask the user for confirmation. Returns a promise which resolves to a
boolean value indicating whether the user responded with yes.
<p>
Can be used to implement an exit prompt like this:
```
q = 'pager.ask("Do you want to exit Chawan?").then(x => x ? pager.quit() : void(0))'
```
</td>
</tr>

<tr>
<td>`askChar(prompt)`</td>
<td>Ask the user for any character.
<p>
Like `pager.ask`, but the return value is a character.</td>
</tr>

<tr>
<td>`clipboardWrite(s)`</td>
<td>Write `s` to the clipboard (copy).  By default, it tries using OSC
52; if that fails, it tries to run `external.copy-cmd` (defaults to
`xsel`).
<p>
Returns true if the copy succeeded, false otherwise.  (There may be
false positives in case OSC 52 is used and the terminal doesn't consume
the text.)
</td>
</tr>

<tr>
<td>`extern(cmd, options = {env: { ... }, suspend: true, wait: false})`
</td>
<td>Run an external command `cmd`.
<p>
By default, the `$CHA_URL` and `$CHA_CHARSET` variables are set; change
this using the `env` option.
<p>
`options.suspend` suspends the pager while the command is being
executed, and `options.wait` makes it so the user must press a key
before the pager is resumed.
<p>
Returns true if the command exited successfully, false otherwise.
<p>
Warning: this has a bug where the output is written to stdout even if suspend
is true. Redirect to /dev/null in the command if this is not desired. (This
will be fixed in the future.)</td>
</tr>

<tr>
<td>`externCapture(cmd)`</td>
<td>Like extern(), but redirect the command's stdout string into the
result. null is returned if the command wasn't executed successfully, or if
the command returned a non-zero exit value.</td>
</tr>

<tr>
<td>`externInto(cmd, ins)`</td>
<td>Like extern(), but redirect `ins` into the command's standard input stream.
`true` is returned if the command exits successfully, otherwise the return
value is `false`.</td>
</tr>

<tr>
<td>`externFilterSource(cmd, buffer = null, contentType = null)`</td>
<td>Redirects the specified (or if `buffer` is null, the current) buffer's
source into `cmd`.
<p>
Then, it pipes the output into a new buffer, with the content type `contentType`
(or, if `contentType` is null, the original buffer's content type).
<p>
Returns `undefined`. (It should return a promise; TODO.)</td>
</tr>

<tr>
<td>`buffer`</td>
<td>Getter for the currently displayed buffer.  Returns a `Buffer` object; see
below.</td>
</tr>

<tr>
<td>`navDirection`</td>
<td>The direction the user last moved in the buffer list using
`traverse`.  Possible values are `prev`, `next`, `prev-sibling`,
`next-sibling`, `parent`, `first-child`, `any`.</td>
</tr>

<tr>
<td>`revDirection`</td>
<td>Equivalent to `Pager.oppositeDir(pager.navDirection)`.</td>
</tr>

</table>

Also, the following static function is defined on `Pager` itself:

<table>

<tr>
<th>Property</th>
<th>Description</th>
</tr>

<tr>
<td>`Pager.oppositeDir(dir)`</td>
<td>Return a string representing the direction opposite to `dir`.
<p>
For "next", this is "prev"; for "parent", "first-child"; for
"prev-sibling", "next-sibling"; for "any", it is the same; for the rest,
vice versa.</td>
</tr>

</table>

### Buffer

Each buffer is exposed as an object that implements the `Buffer`
interface.  To get a reference to the currently displayed buffer, use
`pager.buffer`.

Note the quirk mentioned above where `Pager` dispatches unknown
properties onto the current buffer.

Following properties (functions/getters) are defined by `Buffer`:

<table>

<tr>
<th>Property</th>
<th>Description</th>
</tr>

<tr>
<td>`cursorUp(n = 1)`, `cursorDown(n = 1)`</td>
<td>Move the cursor upwards/downwards by n lines, or if n is unspecified, by
1.</td>
</tr>

<tr>
<td>`cursorLeft(n = 1)`, `cursorRight(n = 1)`</td>
<td>Move the cursor to the left/right by n cells, or if n is unspecified, by
1.
<p>
Note: `n` right now represents cells, but really it should represent characters.
(The difference is that right now numbered cursorLeft/cursorRight is broken for
double-width chars.)</td>
</tr>

<tr>
<td>`cursorLineBegin()`, `cursorLineEnd()`</td>
<td>Move the cursor to the first/last cell of the line.</td>
</tr>

<tr>
<td>`cursorLineTextStart()`</td>
<td>Move the cursor to the first non-blank character of the line.</td>
</tr>

<tr>
<td>`cursorNextWord()`, `cursorNextViWord()`, `cursorNextBigWord()`</td>
<td>Move the cursor to the beginning of the next [word](#word-types).</td>
</tr>

<tr>
<td>`cursorPrevWord()`, `cursorPrevViWord()`, `cursorPrevBigWord()`</td>
<td>Move the cursor to the end of the previous [word](#word-types).</td>
</tr>

<tr>
<td>`cursorWordEnd()`, `cursorViWordEnd()`, `cursorBigWordEnd()`</td>
<td>Move the cursor to the end of the current [word](#word-types), or if already
there, to the end of the next word.</td>
</tr>

<tr>
<td>`cursorWordBegin()`, `cursorViWordBegin()`, `cursorBigWordBegin()`</td>
<td>Move the cursor to the beginning of the current [word](#word-types), or if
already there, to the end of the previous word.</td>
</tr>

<tr>
<td>`cursorNextLink()`, `cursorPrevLink()`</td>
<td>Move the cursor to the beginning of the next/previous clickable
element.</td>
</tr>

<tr>
<td>`cursorLinkNavDown(n = 1)`, `cursorLinkNavUp(n = 1)`</td>
<td>Move the cursor to the beginning of the next/previous clickable element.
Buffer scrolls pagewise, wrap to beginning/end if content is less than one page
length.</td>
</tr>

<tr>
<td>`cursorNextParagraph(n = 1)`, `cursorPrevParagraph(n = 1)`</td>
<td>Move the cursor to the beginning/end of the nth next/previous
paragraph.</td>
</tr>

<tr>
<td>`cursorNthLink(n = 1)`</td>
<td>Move the cursor to the nth link of the document.</td>
</tr>

<tr>
<td>`cursorRevNthLink(n = 1)`</td>
<td>Move the cursor to the nth link of the document, counting backwards
from the document's last line.</td>
</tr>

<tr>
<td>`pageUp(n = 1)`, `pageDown(n = 1)`, `pageLeft(n = 1)`,
`pageRight(n = 1)`</td>
<td>Scroll up/down/left/right by n pages.</td>
</tr>

<tr>
<td>`halfPageUp(n = 1)`, `halfPageDown(n = 1)`, `halfPageLeft(n = 1)`,
`halfPageRight(n = 1)`</td>
<td>Scroll up/down/left/right by n half pages.</td>
</tr>

<tr>
<td>`scrollUp(n = 1)`, `scrollDown(n = 1)`, `scrollLeft(n = 1)`,
`scrollRight(n = 1)`</td>
<td>Scroll up/down/left/right by n lines.</td>
</tr>

<tr>
<td>`click()`</td>
<td>Click the HTML element currently under the cursor.</td>
</tr>

<tr>
<td>`cursorFirstLine()`, `cursorLastLine()`</td>
<td>Move to the first/last line in the buffer.</td>
</tr>

<tr>
<td>`cursorTop()`, `cursorMiddle()`, `cursorBottom()`</td>
<td>Move to the first/middle/bottom line on the screen. (Equivalent to H/M/L
in vi.)</td>
</tr>

<tr>
<td>`lowerPage(n = this.cursory)`</td>
<td>Move cursor to line n, then scroll up so that the cursor is on the
top line on the screen. (`zt` in vim.)</td>
</tr>

<tr>
<td>`lowerPageBegin(n = this.cursory)`</td>
<td>Move cursor to the first non-blank character of line n, then scroll up
so that the cursor is on the top line on the screen. (`z<CR>` in vi.)</td>
</tr>

<tr>
<td>`centerLine(n = this.cursory)`</td>
<td>Center screen around line n. (`zz` in vim.)</td>
</tr>

<tr>
<td>`centerLineBegin(n = this.cursory)`</td>
<td>Center screen around line n, and move the cursor to the line's first
non-blank character. (`z.` in vi.)</td>
</tr>

<tr>
<td>`raisePage(n = this.cursory)`</td>
<td>Move cursor to line n, then scroll down so that the cursor is on the
top line on the screen. (zb in vim.)</td>
</tr>

<tr>
<td>`lowerPageBegin(n = this.cursory)`</td>
<td>Move cursor to the first non-blank character of line n, then scroll up
so that the cursor is on the last line on the screen. (`z^` in vi.)</td>
</tr>

<tr>
<td>`nextPageBegin(n = this.cursory)`</td>
<td>If n was given, move to the screen before the nth line and raise the page.
Otherwise, go to the previous screen's last line and raise the page. (`z+`
in vi.)</td>
</tr>

<tr>
<td>`cursorLeftEdge()`, `cursorMiddleColumn()`, `cursorRightEdge()`</td>
<td>Move to the first/middle/last column on the screen.</td>
</tr>

<tr>
<td>`centerColumn()`</td>
<td>Center screen around the current column.</td>
</tr>

<tr>
<td>`findNextMark(x = this.cursorx, y = this.cursory)`,
`findPrevMark(x = this.cursorx, y = this.cursory)`</td>
<td>Find the next/previous mark after/before `x`, `y`, if any; and return its id
(or null if none were found.)</td>
</tr>

<tr>
<td>`setMark(id, x = this.cursorx, y = this.cursory)`</td>
<td>Set a mark at (x, y) using the name `id`.
<p>
Returns true if no other mark exists with `id`. If one already exists,
it will be overridden and the function returns false.</td>
</tr>

<tr>
<td>`clearMark(id)`</td>
<td>Clear the mark with the name `id`. Returns true if the mark existed,
false otherwise.</td>
</tr>

<tr>
<td>`gotoMark(id)`</td>
<td>If the mark `id` exists, jump to its position and return true. Otherwise,
do nothing and return false.</td>
</tr>

<tr>
<td>`gotoMarkY(id)`</td>
<td>If the mark `id` exists, jump to the beginning of the line at
its Y position and return true. Otherwise, do nothing and return false.</td>
</tr>

<tr>
<td>`getMarkPos(id)`</td>
<td>If the mark `id` exists, return its position as an array where the
first element is the X position and the second element is the Y position.
If the mark does not exist, return null.</td>
</tr>

<tr>
<td>`cursorToggleSelection(n = 1, opts = {selectionType: "normal"})`</td>
<td>Start a vim-style visual selection. The cursor is moved to the right
by `n` cells.
<p>
selectionType may be "normal" (regular selection), "line" (line-based
selection) and "column" (column-based selection).</td>
</tr>

<tr>
<td>`getSelectionText()`</td>
<td>Get the currently selected text.
<p>
Returns a promise, so consumers must `await` it to get the text.</td>
</tr>

<tr>
<td>`markURL()`</td>
<td>Convert URL-like strings to anchors on the current page.</td>
</tr>

<tr>
<td>`toggleImages()`</td>
<td>Toggle display of images in this buffer.</td>
</tr>

<tr>
<td>`saveLink()`</td>
<td>Save URL pointed to by the cursor.</td>
</tr>

<tr>
<td>`saveSource()`</td>
<td>Save the source of this buffer.</td>
</tr>

<tr>
<td>`setCursorX(x)`, `setCursorY(y)`, `setCursorXY(x, y)`,
`setCursorXCenter(x)`, `setCursorYCenter(y)`, `setCursorXYCenter(x, y)`</td>
<td>Set the cursor position to `x` and `y` respectively, scrolling the
view if necessary.
<p>
Variants that end with "Center" will also center the screen around the
position if it is outside the screen.</td>
</tr>

<tr>
<td>`find(dir)`</td>
<td>Find the next buffer in the list in a specific direction.
<p>
Possible values of `dir` are: `prev`, `next`, `prev-sibling`,
`next-sibling`, `parent`, `first-child`, `any`.
"next" and "prev" return the next/previous buffer respectively.
<p>
"prev-sibling", "parent" are deprecated aliases for "prev", while
"next-sibling" and "first-child" are deprecated aliases for "next".
<p>
Finally, "any" returns either "prev", or if it's null, "next".
</td>
</tr>

<tr>
<td>`url`</td>
<td>Getter for the buffer's URL. Note: this returns a `URL` object, not a
string.</td>
</tr>

<tr>
<td>`hoverTitle`, `hoverLink`, `hoverImage`</td>
<td>Getter for the string representation of the element title/link/image
currently under the cursor. Returns the empty string if no title is found.</td>
</tr>

<tr>
<td>`cursorx`, `cursory`</td>
<td>The x/y position of the cursor inside the buffer.
<p>
Note that although the status line is 1-based, these values are 0-based.</td>
</tr>

<tr>
<td>`fromx`, `fromy`</td>
<td>The x/y position of the first line displayed on the screen.</td>
</tr>

<tr>
<td>`numLines`</td>
<td>The number of lines currently loaded in the buffer.</td>
</tr>

<tr>
<td>`width`, `height`</td>
<td>The width and height of the buffer's window (i.e. the visible part
of the canvas).</td>
</tr>

<tr>
<td>`process`</td>
<td>The process ID of the buffer.</td>
</tr>

<tr>
<td>`title`</td>
<td>Text from the `title` element, or the buffer's URL if there is no
title.</td>
</tr>

<tr>
<td>`next`</td>
<td>Next buffer in the buffer list.  May be `null`.</td>
</tr>

<tr>
<td>`prev`</td>
<td>Previous buffer in the buffer list.  May be `null`.</td>
</tr>

<tr>
<td>`select`</td>
<td>Reference to the current `select` element's widget, or null if no
`select` element is open.
<p>
This object implements the `Select` interface, which is somewhat
compatible with the `Buffer` interface with some exceptions. (TODO:
elaborate)</td>
</tr>

</table>

### LineEdit

The line editor at the bottom of the screen is exposed to the JavaScript context
as `globalThis.line`, or simply `line`, and implements the `LineEdit` interface.

Note that there is no single `LineEdit` object; a new one is created every time
the line editor is opened, and when the line editor is closed, `globalThis.line`
simply returns `null`.

Following properties (functions/getters) are defined by `LineEdit`:

<table>

<tr>
<th>Property</th>
<th>Description</th>
</tr>

<tr>
<td>`submit()`</td>
<td>Submit line.</td>
</tr>

<tr>
<td>`cancel()`</td>
<td>Cancel operation.</td>
</tr>

<tr>
<td>`backspace()`</td>
<td>Delete character before cursor.</td>
</tr>

<tr>
<td>`delete()`</td>
<td>Delete character after cursor.</td>
</tr>

<tr>
<td>`clear()`</td>
<td>Clear text before cursor.</td>
</tr>

<tr>
<td>`kill()`</td>
<td>Clear text after cursor.</td>
</tr>

<tr>
<td>`clearWord()`</td>
<td>Delete word before cursor.</td>
</tr>

<tr>
<td>`killWord()`</td>
<td>Delete word after cursor.</td>
</tr>

<tr>
<td>`backward()`, `forward()`</td>
<td>Move cursor backward/forward by one character.</td>
</tr>

<tr>
<td>`nextWord()`, `prevWord()`</td>
<td>Move cursor to the next/previous word by one character.</td>
</tr>

<tr>
<td>`begin()`, `end()`</td>
<td>Move cursor to the beginning/end of the line.</td>
</tr>

<tr>
<td>`escape()`</td>
<td>Ignore keybindings for next character.</td>
</tr>

<tr>
<td>`nextHist()`, `prevHist()`</td>
<td>Jump to the previous/next history entry.</td>
</tr>

</table>

<!-- MANON

## See also

**cha**(1) **cha-config**(5)
MANOFF -->
