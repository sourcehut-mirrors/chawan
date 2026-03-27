<!-- CHA-API 7 -->

# Chawan's command API

As described in [**cha-config**](config.md)(5), users can bind keypress
combinations to actions.  Such an action can be either a JavaScript
expression, or a command defined in the `[cmd]` section of config.toml.

For example, the following works:

```
'g p n' = 'n => pager.alert(n)' # e.g. 2gpn prints `2' to the status line
```

Note however, that JavaScript functions must be called with an appropriate
`this` value.  So e.g. the following does not work:

```
'g p n' = 'pager.alert' # broken!!!
```

To work around this limitation, actions have to wrap the target function in
a closure, as above.  However, this has poor reusability; for more complex
actions, you would have to copy and paste the entire function every time you
re-bind it or call it from a different function.

To fix this, it is possible to define a command in the `[cmd]` section:

```toml
[cmd.my.namespace]
showNumber = 'n => pager.alert(n)'
```

`my.namespace` can be anything you want; it is to avoid collisions when
including multiple configs.  The only restriction is that the first
component (in this case, "my") must not contain an upper-case letter.

Now you can call `cmd.my.namespace.showNumber()` from any other function, or
include it in a keybinding (in that case, `cmd.` is optional):

```toml
'g p n' = 'my.namespace.showNumber'
# same as
'g p n' = 'cmd.my.namespace.showNumber'
```

## Interfaces

Note that there are also many private functions not documented here.
Such functions have no stability guarantee and may disappear at any time,
so using them is not recommended.

### Client

The global object (`globalThis`) implements the `Client` interface.
Public functions of this are:

`quit()`
: Exit the browser.

`suspend()`
: Temporarily suspend the browser, by delivering the client process a
  SIGTSTP signal.

  Note: this suspends all processes, including buffers, the loader and CGI.

`readFile(path)`
: Read a file at `path`.

  Returns the file's content as a string, or null if the file does not
  exist.

`writeFile(path, content)`
: Write `content` to the file at `path`.

  Throws a TypeError if this failed for whatever reason.

`getenv(name, fallback = null)`
: Get an environment variable by `name`.

  Returns `fallback` if the variable does not exist.

`setenv(name, value)`
: Set an environment variable by `name`.

  Throws a `TypeError` if the operation failed (e.g. because the variable's
  size exceeded an OS-specified limit.)

`pager`
: The pager object.  Implements `Pager`, as described below.

`line`
: The line editor. Implements `LineEdit`, as described below.

`config`
: The config object.

  A currently incomplete interface for retrieving and setting
  configuration options.  In general, names are the same as in config.toml,
  except all `-` (ASCII hyphen) characters are stripped and the next
  character is upper-cased.  e.g. `external.cgi-dir` can be queried as
  `config.external.cgiDir`, etc.

  Setting individual options sometimes works, but sometimes they do not get
  propagated as expected.  Consider this an experimental API.

  Currently, `siteconf` and `omnirule` values are not exposed to JS.

  The configuration directory itself can be queried as `config.dir`.

`Client` also implements various web standards normally available on the
`Window` object on websites, e.g. fetch().  Note however that it does *not*
give access to JS objects in buffers, so e.g. `globalThis.document` is not
available.

### Pager

`Pager` is a separate interface from `Client` that gives access to the
pager (i.e. browser chrome).  It is accessible as `globalThis.pager`, or
simply `pager`.

Note that there is a quirk of questionable value, where accessing
properties that do not exist on the pager will dispatch those to the
current buffer (`pager.buffer`).  So if you see e.g. `pager.url`, that is
actually equivalent to `pager.buffer.url`, because `Pager` has no `url`
getter.

Following properties (functions/getters) are defined by `Pager`:

`load(url = pager.buffer.url)`
: Put the specified address into the URL bar, and optionally load it.

  Note that this performs auto-expansion of URLs, so Chawan will expand any
  matching omni-rules (e.g. search), try to open schemeless URLs with the
  default scheme/local files, etc.

  Opens a prompt with the current URL when no parameters are specified;
  otherwise, the string passed is displayed in the prompt.

`loadSubmit(url)`
: Act as if `url` had been entered to the URL bar.  `loadSubmit` differs
  from `gotoURL` in that it also evaluates omni-rules, tries to prepend a
  scheme, etc.

`gotoURL(url, options = {replace: null, contentType: null, save: false, charset: null})`
: Go to the specified URL immediately (without a prompt).  This differs
  from `loadSubmit` in that it loads the exact URL as passed (no prepending
  https, etc.)

  When `replace` is set, the new buffer may replace the old one if it loads
  successfully.

  When `contentType` is set, the new buffer's content type is forcefully
  set to that string.

  When `save` is true, the user is prompted to save the resource instead of
  displaying it in a buffer.

  When `charset` is not null, the specified charset label is forced instead
  of regular charset detection.

`traverse(dir)`
: Switch to the next buffer in direction `dir`, interpreted as in
  `Buffer#find`.

`nextBuffer()`, `prevBuffer()`
: Same as `traverse("next")` and `traverse("prev")`.

`dupeBuffer()`
: Duplicate the current buffer by loading its source in a new buffer.

`discardBuffer(buffer = pager.buffer, dir = pager.navDirection)`
: Discard `buffer`, then move back to the buffer opposite to `dir`
  (interpreted as in `Buffer#find`).

`discardTree()`
: Discard all subsequent siblings of the current buffer.  This function is
  deprecated, and may be removed in the future.

`addTab(target)`
: Open a new tab.

  If `target` is a buffer, it is removed from its current tab and added to
  the newly created tab.  Otherwise, `target` is interpreted as a URL to
  open with `gotoURL`.

`prevTab()`, `nextTab()`
: Switch to the previous/next tab in the tab list.

`discardTab()`
: Discard the current tab.

`reload()`
: Open a new buffer with the current buffer's URL, replacing the current
  buffer.

`reshape()`
: Reshape the current buffer (=render the current page anew.)

`redraw()`
: Redraw screen contents.  Useful if something messed up the display.

`toggleSource()`
: If viewing an HTML buffer, open a new buffer with its source.  Otherwise,
  open the current buffer's contents as HTML.

`lineInfo()`
: Display information about the current line.

`searchForward()`, `searchBackward()`
: Search forward/backward for a string in the current buffer.

`isearchForward()`, `isearchBackward()`
: Incremental-search forward/backward for a string, highlighting the first
  result.

`gotoLine(n?)`
: Go to the line passed as the first argument.

  If no arguments were specified, an input window for entering a line is
  shown.

`searchNext(n = 1)`, `searchPrev(n = 1)`
: Jump to the nth next/previous search result.

`peek()`
: Display an alert message of the current URL.

`peekCursor()`
: Display an alert message of the URL or title under the cursor.  Multiple
  calls allow cycling through the two. (i.e. by default, press u once ->
  title, press again -> URL)

`showFullAlert()`
: Show the last alert inside the line editor.

`ask(prompt)`
: Ask the user for confirmation.  Returns a promise which resolves to a
  boolean value indicating whether the user responded with yes.

  Can be used to implement an exit prompt like this:

  ```
  q = 'pager.ask("Do you want to exit Chawan?").then(x => x ? pager.quit() : void 0)'
  ```

`askChar(prompt)`
: Ask the user for any character.

  Like `pager.ask`, but the return value is a character.

`clipboardWrite(s)`
: Write `s` to the clipboard (copy).  By default, it tries using OSC 52;
  if that fails, it tries to run `external.copy-cmd` (defaults to `xsel`).

  Returns true if the copy succeeded, false otherwise.  (There may be
  false positives in case OSC 52 is used and the terminal doesn't consume
  the text, although Chawan will try its best to avoid this.)

`extern(cmd, options = {env: { ... }, suspend: true, wait: false})`
: Run an external command `cmd`.

  By default, the `$CHA_URL` and `$CHA_CHARSET` variables are set; change
  this using the `env` option.

  `options.suspend` suspends the pager while the command is being
  executed, and `options.wait` makes it so the user must press a key
  before the pager is resumed.

  Returns true if the command exited successfully, false otherwise.

`externCapture(cmd)`
: Like `extern()`, but redirect the command's stdout string into the
  result.  `null` is returned if the command wasn't executed successfully,
  or if the command returned a non-zero exit value.

`externInto(cmd, ins)`
: Like `extern()`, but redirect `ins` into the command's standard input
  stream.  `true` is returned if the command exits successfully, `false`
  otherwise.

`externFilterSource(cmd, buffer = null, contentType = null)`
: Redirects the specified (or if `buffer` is null, the current) buffer's
  source into `cmd`.

  Then, it pipes the output into a new buffer, with the content type
  `contentType` (or, if `contentType` is null, the original buffer's
  content type).

  Returns `undefined`.  (It should return a promise; TODO.)

`openEditor(text)`
: Open "text" in the command configured as `external.editor` (this is
  typically just `$EDITOR`.)

  If the editor signals an error (crash or non-zero exit code), `null` is
  returned.  Otherwise, the user's input is returned as a string.

`openMenu(x = pager.cursorx - pager.fromx, y = pager.cursory - pager.fromy)`
: Opens the context menu at the specified x/y positions.

`closeMenu()`
: Closes the menu if it is opened.

`buffer`
: Getter for the currently displayed buffer.  Returns a `Buffer` object;
  see below.

`menu`
: Getter for the currently displayed menu.  Returns a `Select` object.

`navDirection`
: The direction the user last moved in the buffer list using `traverse`.
  Possible values are `prev`, `next`, `any`.

`revDirection`
: Equivalent to `Pager.oppositeDir(pager.navDirection)`.

Also, the following static function is defined on `Pager` itself:

`Pager.oppositeDir(dir)`
: Return a string representing the direction opposite to `dir`.

  For "next", this is "prev"; for "prev", "next"; for "any", it's the same.

### Buffer

Each buffer is exposed as an object that implements the `Buffer`
interface.  To get a reference to the currently displayed buffer, use
`pager.buffer`.

Note the quirk mentioned above where `Pager` dispatches unknown
properties onto the current buffer.

Following properties (functions/getters) are defined by `Buffer`:

`cursorUp(n = 1)`, `cursorDown(n = 1)`
: Move the cursor upwards/downwards by `n` lines, or if `n` is unspecified,
  by 1.

`cursorLeft(n = 1)`, `cursorRight(n = 1)`
: Move the cursor to the left/right by `n` cells, or if `n` is unspecified,
  by 1.

  Note: `n` right now represents cells, but really it should
  represent characters.  (The difference is that numbered cursorLeft or
  cursorRight is currently broken for double-width chars.)

`cursorLineBegin()`, `cursorLineEnd()`
: Move the cursor to the first/last cell of the line.

`cursorLineTextStart()`
: Move the cursor to the first non-blank character of the line.

`cursorNextWord()`, `cursorNextViWord()`, `cursorNextBigWord()`
: Move the cursor to the beginning of the next [word](#word-types).

`cursorPrevWord()`, `cursorPrevViWord()`, `cursorPrevBigWord()`
: Move the cursor to the end of the previous [word](#word-types).

`cursorWordEnd()`, `cursorViWordEnd()`, `cursorBigWordEnd()`
: Move the cursor to the end of the current [word](#word-types), or if
  already there, to the end of the next word.

`cursorWordBegin()`, `cursorViWordBegin()`, `cursorBigWordBegin()`
: Move the cursor to the beginning of the current [word](#word-types),
  or if already there, to the end of the previous word.

`async getCurrentWord(x = this.cursorx, y = this.cursory)`
: Returns the word currently under the cursor as a string.

`cursorNextLink()`, `cursorPrevLink()`
: Move the cursor to the beginning of the next/previous clickable element.

`cursorLinkNavDown(n = 1)`, `cursorLinkNavUp(n = 1)`
: Move the cursor to the beginning of the `n`th next/previous clickable
  element.  Buffer scrolls pagewise, wrap to beginning/end if content is
  less than one page length.

`cursorNextParagraph(n = 1)`, `cursorPrevParagraph(n = 1)`
: Move the cursor to the beginning/end of the nth next/previous paragraph.

`cursorNthLink(n = 1)`
: Move the cursor to the nth link of the document.

`cursorRevNthLink(n = 1)`
: Move the cursor to the nth link of the document, counting backwards
  from the document's last line.

`pageUp(n = 1)`, `pageDown(n = 1)`, `pageLeft(n = 1)`, `pageRight(n = 1)`
: Scroll up/down/left/right by n pages.

`halfPageUp(n = 1)`, `halfPageDown(n = 1)`, `halfPageLeft(n = 1)`, `halfPageRight(n = 1)`
: Scroll up/down/left/right by n half pages.

`scrollUp(n = 1)`, `scrollDown(n = 1)`, `scrollLeft(n = 1)`, `scrollRight(n = 1)`
: Scroll up/down/left/right by n lines.

`click(n = 1)`
: Click the HTML element currently under the cursor.  `n` controls the
  number of clicks, e.g. `n = 2` is a double click.  (The number of clicks
  is only relevant in JS apps.)

`cursorFirstLine()`, `cursorLastLine()`
: Move to the first/last line in the buffer.

`cursorTop()`, `cursorMiddle()`, `cursorBottom()`
: Move to the first/middle/bottom line on the screen.  (Equivalent to H/M/L
  in vi.)

`lowerPage(n = this.cursory)`
: Move cursor to line n, then scroll up so that the cursor is on the
  top line on the screen.  (`zt` in vim.)

`lowerPageBegin(n = this.cursory)`
: Move cursor to the first non-blank character of line n, then scroll up
  so that the cursor is on the top line on the screen.  (`z<CR>` in vi.)

`centerLine(n = this.cursory)`
: Center screen around line n. (`zz` in vim.)

`centerLineBegin(n = this.cursory)`
: Center screen around line n, and move the cursor to the line's first
  non-blank character.  (`z.` in vi.)

`raisePage(n = this.cursory)`
: Move cursor to line n, then scroll down so that the cursor is on the
  top line on the screen.  (`zb` in vim.)

`raisePageBegin(n = this.cursory)`
: Move cursor to the first non-blank character of line n, then scroll up
  so that the cursor is on the last line on the screen.  (`z^` in vi.)

`nextPageBegin(n = this.cursory)`
: If n was given, move to the screen before the nth line and raise the
  page.  Otherwise, go to the previous screen's last line and raise the
  page.  (`z+` in vi.)

`cursorLeftEdge()`, `cursorMiddleColumn()`, `cursorRightEdge()`
: Move to the first/middle/last column on the screen.

`centerColumn()`
: Center screen around the current column.

`findPrevMatch(regex, x, y, wrap = false, n = 1)`, `findNextMatch(regex, x, y, wrap = false, n = 1)`
: Find the previous/next match for a regex.

  `regex` is a RegExp object (e.g. from `/this syntax/`).  `x` and `y` are
  the starting position in the buffer, `wrap` determines whether or not the
  search should wrap over the document, and `n` is the count of occurrences
  to be found.

  Returns an array of the elements `[x, y, w]` where `x` and `y` are the
  matched coordinates and `w` the width of the matched text.  If no match
  is found, the result is `[-1, -1, 0]`.

`findNextMark(x = this.cursorx, y = this.cursory)`, `findPrevMark(x = this.cursorx, y = this.cursory)`
: Find the next/previous mark after/before `x`, `y`, if any; and return its id
  (or null if none were found.)

`setMark(id, x = this.cursorx, y = this.cursory)`
: Set a mark at (x, y) using the name `id`.

  Returns true if no other mark exists with `id`. If one already exists,
  it will be overridden and the function returns false.

`clearMark(id)`
: Clear the mark with the name `id`.  Returns true if the mark existed,
  false otherwise.

`gotoMark(id)`
: If the mark `id` exists, jump to its position and return true.
  Otherwise, do nothing and return false.

`gotoMarkY(id)`
: If the mark `id` exists, jump to the beginning of the line at its Y
  position and return true.  Otherwise, do nothing and return false.

`getMarkPos(id)`
: If the mark `id` exists, this returns its position as an array where
  the first element is the X position and the second element is the Y
  position.  Otherwise it returns `null`.

`cursorToggleSelection(n = 1, opts = {selectionType: "normal"})`
: Start a vim-style visual selection. The cursor is moved to the right by
  `n` cells.

  selectionType may be "normal" (regular selection), "line" (line-based
  selection) and "column" (column-based selection).

`getSelectionText()`
: Get the currently selected text.

  Returns a promise, so consumers must `await` it to get the text.

`markURL()`
: Convert URL-like strings to anchors on the current page.

`showLinkHints()`
: Display link hints on the page.  Mainly intended for the built-in
  toggleLinkHints command.

  Returns an array of objects with `x` representing the x position, `y` the
  y position of a link.

`toggleImages()`
: Toggle display of images in this buffer.

`saveLink()`
: Save URL pointed to by the cursor.

`saveSource()`
: Save the source of this buffer.

`setCursorX(x)`, `setCursorY(y)`, `setCursorXY(x, y)`, `setCursorXCenter(x)`, `setCursorYCenter(y)`, `setCursorXYCenter(x, y)`
: Set the cursor position to `x` and `y` respectively, scrolling the view
  if necessary.

  Variants that end with "Center" will also center the screen around the
  position if it is outside the screen.

`setFromX(x)`, `setFromY(y)`, `setFromXY(x, y)`
: Set the starting position of the displayed area on the screen.

`find(dir)`
: Find the next buffer in the list in a specific direction.

  Possible values of `dir` are "prev", "next", and "any".  "next" and
  "prev" return the next/previous buffer respectively, while "any" returns
  either "prev", or if it's null, "next".

`url`
: Getter for the buffer's URL.  Note: this returns a `URL` object, not a
  string.

`hoverTitle`, `hoverLink`, `hoverImage`
: Getter for the string representation of the element title/link/image
  currently under the cursor.  Returns the empty string if no title is
  found.

`cursorx`, `cursory`
: The x/y position of the cursor inside the buffer.

  Note that while the status line display is 1-indexed, these values are
  0-indexed (i.e. `cursory = 0` is the first line).

`fromx`, `fromy`
: The x/y position of the first line displayed on the screen.

`numLines`
: The number of lines currently loaded in the buffer.

`width`, `height`
: The width and height of the buffer's window (i.e. the visible part of the
  canvas).

`process`
: The process ID of the buffer.

`title`
: Text from the `title` element, or the buffer's URL if there is no title.

`next`
: Next buffer in the buffer list.  May be `null`.

`prev`
: Previous buffer in the buffer list.  May be `null`.

`select`
: Reference to the current `select` element's widget, or null if no
  `select` element is open.

  This object implements the `Select` interface, which is somewhat
  compatible with the `Buffer` interface with some exceptions.  (TODO:
  elaborate)

</table>

### LineEdit

The line editor at the bottom of the screen is exposed to the JavaScript context
as `globalThis.line`, or simply `line`, and implements the `LineEdit` interface.

Note that there is no single `LineEdit` object; a new one is created every time
the line editor is opened, and when the line editor is closed, `globalThis.line`
simply returns `null`.

Following properties (functions/getters) are defined by `LineEdit`:

`submit()`
: Submit line.

`cancel()`
: Cancel operation.

`backspace()`
: Delete character before cursor.

`delete()`
: Delete character after cursor.

`clear()`
: Clear text before cursor.

`kill()`
: Clear text after cursor.

`clearWord()`
: Delete word before cursor.

`killWord()`
: Delete word after cursor.

`backward()`, `forward()`
: Move cursor backward/forward by one character.

`nextWord()`, `prevWord()`
: Move cursor to the next/previous word by one character.

`begin()`, `end()`
: Move cursor to the beginning/end of the line.

`escape()`
: Ignore keybindings for next character.

`nextHist()`, `prevHist()`
: Jump to the previous/next history entry.

`text`
: The currently entered text.

## See also

[**cha**](cha.md)(1) [**cha-config**](config.md)(5)
