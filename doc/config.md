<!-- CHA-CONFIG 5 -->

# Configuration of Chawan

Chawan supports configuration of various options like keybindings, user
stylesheets, site preferences, etc.  The configuration format is similar to
toml, with the following exceptions:

* Regular tables (`[table]`) and inline tables (`table = {}`) have different
  semantics.  The first is additive, meaning default values are not removed.
  The second is destructive, and clears all default definitions in the table
  specified.
* `[[table-array]]` is sugar for `[table-array.n]`, where `n` is the
  number of declared table arrays.  For example, you can declare anonymous
  siteconfs using the syntax `[[siteconf]]`.

The canonical configuration file path is ~/.chawan/config.toml, but the
search path accommodates XDG basedirs as well:

1. config file specified through -C switch -> use that
2. `$CHA_DIR` is set -> use `$CHA_DIR/config.toml`
3. `${XDG_CONFIG_HOME:-~/.config}/chawan/config.toml` exists -> use that
4. `~/.chawan/config.toml` exists -> use that

See the [*Path handling*](#path-handling) section for details on how the
config directory can be accessed.

For a configuration template, see bonus/config.toml in the source
distribution.

<!-- MANOFF -->
**Table of contents**

* [Start](#start)
* [Search](#search)
* [Buffer](#buffer)
* [Encoding](#encoding)
* [External](#external)
* [Input](#input)
* [Network](#network)
* [Display](#display)
* [Status](#status)
* [Omnirule](#omnirule)
* [Siteconf](#siteconf)
* [Keybindings](#keybindings)
   * [Pager actions](#pager-actions)
   * [Buffer actions](#buffer-actions)
   * [Line-editing actions](#line-editing-actions)
* [Appendix](#appendix)
   * [Regex handling](#regex-handling)
     * [Match mode](#match-mode)
     * [Search mode](#search-mode)
   * [Path handling](#path-handling)
   * [Word types](#word-types)
     * [w3m word](#w3m-word)
     * [vi word](#vi-word)
     * [Big word](#big-word)

<!-- MANON -->

## Start

Start-up options are to be placed in the `[start]` section.

Following is a list of start-up options:

visual-home = "about:chawan"
: **URL**

: Page opened when Chawan is called with the -V option and no other pages
are passed as arguments.

startup-script = ""
: **JavaScript code**

: Script Chawan runs on start-up. Pages will not be loaded until this
function exits.  (Note however that asynchronous functions like setTimeout
do not block loading.)

headless = false
: **boolean** / **"dump"**

: When set to true or "dump", the browser does not take input; instead, it
prints a rendered version of all buffers in order, then exits.

  The difference between `true` and "dump" is that `true` first waits for
  all scripts and network requests to run to completion, while "dump" does
  not.  This means that `true` may never exit when scripting is enabled
  (e.g. if a script sets `setInterval`.)

  Piping `cha` to an external program or passing the `-d` switch has the same
  effect as setting this option to "dump".

console-buffer = true
: **boolean**

: Whether Chawan should open a console buffer in non-headless mode.

  Warning: this is only useful for debugging.  Disabling this option
  without manually redirecting standard error will result in error messages
  randomly appearing on your screen.

## Buffer

Buffer options are to be placed in the `[buffer]` section.

These options are global to all buffers.  For more granular filtering,
use `[[siteconf]]`.

Example:

```toml
[buffer]
# show images on all websites
images = true
# disable website CSS
styling = false
# Specify user styles.
user-style = '''
/* you can import external UA styles like this: */
@import 'user.css';
/* or just insert the style inline as follows. */
/* enforce the default text-decoration for links (i.e. underline). */
a[href] { text-decoration: revert !important }
@media (monochrome) { /* only in color-mode "monochrome" (or -M) */
	/* disable UA style of bold font (no need for important here) */
	a[href]:hover { font-weight: initial }
	/* ...and italicize the font on hover instead.
	 * here we use important because we don't want websites to
	 * override the value. */
	a[href]:hover { font-style: italic !important }
}
'''
# You *can* set scripting to true here, but I strongly recommend using
# [[siteconf]] to enable it on a per-site basis instead.
```

Following is a list of buffer options:

styling = true
: **boolean**

: Enable/disable author style sheets.  Note that disabling this does not
affect user styles.

scripting = false
: **boolean** / **"app"**

: Enable/disable JavaScript in *all* buffers.

  `"app"` also enables JavaScript APIs that can be used to fingerprint
  users (e.g. querying the window's size).  This may achieve better
  compatibility with websites that behave like applications, at the cost of
  reduced privacy.

  For security and performance reasons, users are encouraged to selectively
  enable JavaScript with `[[siteconf]]` instead of using this setting.

images = false
: **boolean**

: Enable/disable inline image display.

cookie = false
: **boolean** / **"save"**

: Enable/disable cookies on sites.

  If the string "save" is specified, then cookies are also saved to
  `external.cookie-file`. `true` still reads cookies.txt, but does not
  modify it.

  In Chawan, each website gets a separate cookie jar, so websites relying
  on cross-site cookies may not work as expected.  You may use the
  `[[siteconf]]` `"share-cookie-jar"` setting to adjust this behavior for
  specific sites.

referer-from = false
: **boolean**

: Enable/disable the "Referer" header.

  Defaults to false.  For privacy reasons, users are encouraged to
  leave this option disabled, only enabling it for specific sites in
  `[[siteconf]]`.

autofocus = false
: **boolean**

: When set to true, elements with an "autofocus" attribute are focused on
  automatically after the buffer is loaded.

  If scripting is enabled, this also allows scripts to focus on elements.

meta-refresh = "ask"
: **"never"** / **"always"** / **"ask"**

: Whether or not `http-equiv=refresh` meta tags should be respected.
"never" completely disables them, "always" automatically accepts all of
them, "ask" brings up a pop-up menu.

history = true
: **boolean**

: Whether or not browsing history should be saved to the disk.

mark-links = false
: **boolean**

: Add numeric markers before links.  In headless/dump mode, this also
  prints a list of URLs after the page.

user-style = ""
: **CSS stylesheet**

: A user stylesheet applied to all buffers.

  External stylesheets can be imported using the `@import 'file.css';`
  syntax.  Paths are relative to the configuration directory.

  Nested `@import` is not supported yet.

## Search

Search options are to be placed in the `[search]` section.

Following is a list of search options:

wrap = true
: **boolean**

: Whether on-page searches should wrap around the document.

ignore-case = "auto"
: **"auto"** / **boolean**

: When set to true, document-wide searches are case-insensitive by
  default.  When set to "auto", searches are only case-sensitive when the
  search term includes a capital letter.

  Note: this can also be overridden inline in the search bar (vim-style),
  with the escape sequences `\c` (ignore case) and `\C` (strict case).
  See [search mode](#search-mode) for details.)

## Encoding

Encoding options are to be placed in the `[encoding]` section.

Following is a list of encoding options:

document-charset = ["utf-8", "sjis", "euc-jp", "latin2"]
: **array of charset label strings**

: List of character sets for loading documents.

  All listed character sets are enumerated until the document has been
  decoded without errors. In HTML, meta tags and the BOM may override this
  with a different charset, so long as the specified charset can decode the
  document correctly.

display-charset = "auto"
: **charset label string** / **"auto"**

: Character set for keyboard input and displaying documents.

  Used in dump mode as well.

  (This means that e.g. `cha -I EUC-JP -O UTF-8 a > b` is roughly
  equivalent to `iconv -f EUC-JP -t UTF-8`.)

## External

External options are to be placed in the `[external]` section.

Following is a list of external options:

tmpdir = {usually "/tmp/cha-tmp-user"}
: **path**

: Directory used to save temporary files.

editor = "\${VISUAL:-\${EDITOR:-vi}}"
: **shell command**

: External editor command.  %s is substituted for the file name, %d for
  the line number.

mailcap = ["~/.mailcap", "/etc/mailcap", "/usr/etc/mailcap", "/usr/local/etc/mailcap"]
: **array of paths**

: Search path for mailcap files.  See [**cha-mailcap**](mailcap.md)(5)
for details.  Directories specified first have higher precedence.

mime-types = ["~/.mime.types", "/etc/mime.types", "/usr/etc/mime.types", "/usr/local/etc/mime.types"]
: **array of paths**

: Search path for mime.types files.  See [**cha-mime.types**](mime.types.md)(5)
  for details.

auto-mailcap = "\$CHA_DIR/mailcap"
: **path**

: Mailcap file for entries that are automatically executed.

  The "Open as" prompt also saves entries in this file.

  For backwards-compatibility, if this is "mailcap" and the file does not
  exist, Chawan will also check "auto.mailcap".

cgi-dir = ["\$CHA_DIR/cgi-bin", "\$CHA_LIBEXEC_DIR/cgi-bin"]
: **array of paths**

: Search path for local CGI scripts.  See [**cha-cgi**](cgi.md)(5) for
details.

urimethodmap = ["\$CHA_DIR/urimethodmap", "~/.urimethodmap", "/etc/urimethodmap"]
: **array of paths**

: Search path for urimethodmap files.  See
[**cha-urimethodmap**](urimethodmap.md)(5) for details.

w3m-cgi-compat = false
: **boolean**

: Enable local CGI compatibility with w3m.  In short, it redirects
`file:///cgi-bin/*` and `file:///$LIB/cgi-bin/*` to `cgi-bin:*`.
See [**cha-cgi**](cgi.md)(5) for details.

download-dir = "\${TMPDIR:-/tmp}/"
: **path**

: Path to pre-fill for "Save to:" prompts.

show-download-panel = true
: **boolean**

: Whether `about:downloads` should be opened after starting a download.

copy-cmd = "xsel -bi"
: **shell command**

: Command to use for "copy to clipboard" operations.  When
`input.osc52-copy` is set to "auto" (the default), `copy-cmd` is ignored if
support for OSC 52 is detected.

paste-cmd = "xsel -bo"
: **shell command**

: Command to use for "read from clipboard" operations.

bookmark = "\$CHA_DATA_DIR/bookmark.md"
: **path**

: Path to the bookmark.md file. (The file it points to should have a
.md extension, so that its type can be correctly deduced.)

history-file = "\$CHA_DATA_DIR/history.uri"
: **path**

: Path to the history file.

history-size = 100
: **number**

: Maximum length of the history file.

cookie-file = "\$CHA_DATA_DIR/cookies.txt"
: **path**

: Path to the cookie file.

  The format is equivalent to curl's "cookies.txt" format, except that a
  "jar@" part is prepended for cookies that belong in a different jar than
  the domain.

  Cookies from this file are used if "buffer.cookie" (or its equivalent
  siteconf override) is set to `true` or `"save"`. This means that `true`
  sets the cookie-file to a "read-only" mode.

## Input

Input options are to be placed in the `[input]` section.

vi-numeric-prefix = true
: **boolean**

: Whether vi-style numeric prefixes to commands should be accepted.

  Only applies for keybindings defined in `[page]`.

use-mouse = "auto"
: **boolean** / **"auto"**

: Whether Chawan is allowed to intercept mouse clicks.

  The current implementation imitates w3m.

  When set to "auto" (the default), Chawan tries to detect whether mouse
  support is available.

osc52-copy = "auto"
: **boolean** / **"auto"**

: Whether Chawan should use the OSC 52 escape sequence for copying to the
clipboard directly through the terminal.  When available, OSC 52 overrides
`external.copy-cmd`.

  When set to "auto" (the default), Chawan tries to detect whether OSC 52
  is available on launch.

osc52-primary = "auto"
: **boolean** / **"auto"**

: Whether Chawan should try to set the primary selection through OSC 52.
This happens automatically on mouse selection, and also on all clipboard
copies.

  When set to "auto" (the default), Chawan tries to detect whether the
  terminal is capable of setting the primary selection.  Note that very
  few terminals actually implement OSC 52 correctly (to my knowledge, only
  XTerm and Kitty), and on other terminals this might even break copying to
  the clipboard selection.

bracketed-paste = "auto"
: **boolean** / **"auto"**

: Whether Chawan should ask for bracketed paste.

  When true, the terminal will (hopefully) mark pasted text with escape
  sequences, which a) ensures that pasting a newline character into the
  line editor does not submit the editor, b) allows Chawan to intercept
  text pasted into the pager, automatically loading it into the browser's
  URL bar.

  When set to "auto" (the default), Chawan tries to only enable bracketed
  paste if the terminal is known not to misbehave when trying to do so.

wheel-scroll = 5
: **number**

: Number of lines to scroll for a mouse wheel event.

side-wheel-scroll = 5
: **number**

: Number of columns to scroll for a mouse side-wheel event.

link-hint-chars = "abcdefghijklmnoprstuvxyz"
: **string**

: A string of characters to use in `toggleLinkHints`.  Any Unicode
codepoint is accepted, and they are ordered as specified in this option.

Examples:

```
[input]
vi-numeric-prefix = true

[page]
# Here, the arrow function will be called with the vi numbered prefix if
# one was input, and with no argument otherwise.
# The numeric prefix can never be zero, so it is safe to test for undefined
# using the ternary operator.
G = 'n => n ? pager.gotoLine(n) : pager.cursorLastLine()'
```

## Network

Network options are to be placed in the `[network]` section.

max-redirect = 10
: **number**

: Maximum number of redirections to follow.

max-net-connections = 12
: **number**

: Maximum number of simultaneous network connections allowed in one buffer.
  Further connections are held back until the number returns below the
  threshold.

prepend-scheme = "https://"
: **string**

: Prepend this to URLs passed to Chawan (or typed into the URL bar) without
  a scheme.

  Note that local files (`file:` scheme) will always be checked first; only
  if this fails, Chawan will retry the request with `prepend-scheme` set as
  the scheme.

proxy = ""
: **URL**

: Specify a proxy for all network requests Chawan makes.  Currently, the
  formats `http://user:pass@domain` and `socks5://user:pass@domain` are
  accepted.  Unlike in curl, `socks5h` is an alias of `socks5`, and DNS
  requests are always tunneled.

  Can be overridden by siteconf.

default-headers = {see bonus/config.toml}
: **table**

: Specify a table of default headers for all HTTP(S) network requests.
  Can be overridden by siteconf.

allow-http-from-file = false
: **boolean**

: **WARNING: think twice before enabling this.**

  Allows HTTP and HTTPS requests from the `file:` and `stream:` schemes.
  This is a bad idea in general, because it allows local files to ping
  remote servers (a functionality commonly abused by HTML e-mails to track
  your mailbox activity).

  On the other hand, it allows loading images in HTML e-mails if you don't
  care about the privacy implications.

## Display

Display options are to be placed in the `[display]` section.

Following is a list of display options:

color-mode = "auto"
: **"monochrome"** / **"ansi"** / **"eight-bit"** / **"true-color"** /
**"auto"**

: Set the color mode.  "auto" for automatic detection, "monochrome"
  for black on white, "ansi" for eight ANSI plus eight aixterm colors,
  "eight-bit" for 256-color mode, and "true-color" for 24-bit colors.

format-mode = "auto"
: **"auto"** / **["bold", "italic", "underline", "reverse", "strike",
"overline", "blink"]**

: Specifies allowed output formatting modes.  Accepts the string "auto"
  or an array of specific attributes.  "auto" (the default) tries to
  detect supported formatting modes when launched visually, and omits all
  formatting modes in dump mode.  An empty array (`[]`) disables formatting
  even in visual mode.

no-format-mode = ["overline"]
: **["bold", "italic", "underline", "reverse", "strike", "overline",
  "blink"]**

: Disable specific formatting modes.

image-mode = "auto"
: **"auto"** / **"none"** / **"sixel"** / **"kitty"**

: Specifies the image output mode.  "sixel" uses sixels for output, "kitty"
  uses the Kitty image display protocol, "none" disables image display
  completely.

  "auto" (the default) detects sixel or kitty support automatically, and
  falls back to "none" when neither are available.  This is expected to
  work on all known terminals with functional image support.

  Note that `buffer.images` must be enabled for images to load at all.

sixel-colors = "auto"
: **"auto"** / **2..65535**

: Only applies when `display.image-mode="sixel"`.  Setting this to a number
  overrides the number of sixel color registers reported by the terminal.

alt-screen = "auto"
: **"auto"** / **boolean**

: Enable/disable the alternative screen.  "auto" (the default) tries to
  detect support for this feature.  (However, since Chawan does not link
  to terminfo, you should not expect hacks which remove the respective
  terminfo description to work.)

highlight-color = "-cha-ansi(bright-cyan)"
: **CSS color**

: Set the highlight color for incremental search and marks.  CSS color
  names, hex values, and color functions are all accepted.

  In monochrome mode, this setting is ignored; instead, reverse video is
  used.

highlight-marks = true
: **boolean**

: Enable/disable highlighting of marks.

double-width-ambiguous = false
: **boolean**

: Assume the terminal displays characters in the East Asian Ambiguous
  category as double-width characters.  Useful when e.g. ○ occupies two
  cells.

minimum-contrast = 100
: **0..235**

: Specify the minimum difference between the luminance (Y) of the default
  terminal background and the foreground as represented in YUV.  0 disables
  this function (i.e. allows black letters on black background, etc).

  Note: in the past, this option used to apply to all colors, but since
  v0.3 Chawan only performs color contrast correction when either the
  foreground or background color is the terminal default.

  Also, the contrast correction algorithm is still not perfect, so future
  changes are to be expected.

set-title = true
: **boolean**

: Set the terminal emulator's window title to that of the current page.

default-background-color = "auto"
: **"auto"** / **RGB color**

: Overrides the assumed background color of the terminal.  "auto" leaves
  background color detection to Chawan.

default-foreground-color = "auto"
: **"auto"** / **RGB color**

: Sets the assumed foreground color of the terminal.  "auto" leaves
  foreground color detection to Chawan.

columns = 80, lines = 24, pixels-per-column = 9, pixels-per-line = 18
: **number**

: Fallback values for the number of columns, lines, pixels per column,
  and pixels per line for the cases where it cannot be determined
  automatically.  (For example, these values are used in dump mode.)

force-columns = false, force-lines = false, force-pixels-per-column = false, force-pixels-per-line = false
: **boolean**

: Force-set columns, lines, pixels per column, or pixels per line to the
  fallback values provided above.

## Status

Options concerning the status bar (last line on the screen) are to be
placed in the `[status]` section.

Following is a list of status options:

show-cursor-position = true
: **boolean**

: Whether or not the current line number should be displayed.

show-hover-link = true
: **boolean**

: Whether or not the link under the cursor should be displayed.

format-mode = "reverse"
: **{see \[display\] section}**

: Formatting of the status bar.

## Omnirule

The omni-bar (by default opened with C-l) can be used to perform
searches using omni-rules.  These are to be specified as sub-keys
to table `[omnirule]`.  (The sub-key itself is ignored; you can use
anything as long it doesn't conflict with other keys.)

Examples:

```
# Search using DuckDuckGo Lite.
# (This rule is included in the default config, although C-k invokes
# Brave search.)
[omnirule.ddg]
match = '^ddg:'
substitute-url = '(x) => "https://lite.duckduckgo.com/lite/?kp=-1&kd=-1&q=" + encodeURIComponent(x.split(":").slice(1).join(":"))'

# To use the above rule, open the URL bar with C-k, clear it with
# C-u, and type ddg:keyword.
# Alternatively, you can also redefine C-k like:
[page]
'C-k' = '() => pager.load("ddg:")'

# Search using Wikipedia, Firefox-style.
# The [[omnirule]] syntax introduces an anonymous omnirule; it is
# equivalent to the named one.
[[omnirule]]
match = '^@wikipedia'
substitute-url = '(x) => "https://en.wikipedia.org/wiki/Special:Search?search=" + encodeURIComponent(x.replace(/@wikipedia/, ""))'
```

As noted above, the default config includes some built-in rules,
selected according to the maintainer's preference and the minimum
criterion that they must work without cookies and JavaScript.
Currently, these are:

* `ddg:` - DuckDuckGo Lite.
* `br:` - Brave Search.
* `wk:` - English Wikipedia.
* `wd:` - English Wikitionary.
* `mo:` - Mojeek.

Omnirule options:

match
: **regex**

: Regular expression used to match the input string.  Note that websites
  passed as arguments are matched as well.

  Note: regexes are handled according to the [match mode](#match-mode)
  regex handling rules.

substitute-url
: **JavaScript function**

: A JavaScript function Chawan will pass the input string to.  If a new
  string is returned, it will be parsed instead of the old one.

## Siteconf

Configuration options can be specified for individual sites.  Entries
are to be specified as sub-keys to table `[siteconf]`.  (The sub-key
itself is ignored; you can use anything as long it doesn't conflict with
other keys.)

Most siteconf options can also be specified globally; see the
"overrides" field.

Examples:
```
# Enable cookies on the orange website for log-in.
[siteconf.hn]
url = 'https://news\.ycombinator\.com/.*'
cookie = true

# Redirect npr.org to text.npr.org.
[siteconf.npr]
host = '(www\.)?npr\.org'
rewrite-url = '''
(x) => {
	x.host = "text.npr.org";
	const s = x.pathname.split('/');
	x.pathname = s.at(s.length > 2 ? -2 : 1);
	/* No need to return; URL objects are passed by reference. */
}
'''

# Allow cookie sharing on *sr.ht domains.
[siteconf.sr-ht]
host = '(.*\.)?sr\.ht' # either 'something.sr.ht' or 'sr.ht'
cookie = true # enable cookies (read-only; use "save" to persist them)
share-cookie-jar = 'sr.ht' # use the cookie jar of 'sr.ht' for all matched hosts

# Use the "vector" skin on Wikipedia.
# The [[siteconf]] syntax introduces an anonymous siteconf; it is
# equivalent to the above ones.
[[siteconf]]
url = '^https?://[a-z]+\.wikipedia\.org/wiki/(?!.*useskin=.*)'
rewrite-url = 'x => x.searchParams.append("useskin", "vector")'

# Make imgur send us images.
[siteconf.imgur]
host = '(i\.)?imgur\.com'
default-headers = {
	User-Agent = "Mozilla/5.0 chawan",
	Accept = "*/*",
	Accept-Encoding = "gzip, deflate",
	Accept-Language = "en;q=1.0",
	Pragma = "no-cache",
	Cache-Control = "no-cache"
}
```

Siteconf options:

url
: **regex**

: Regular expression used to match the URL.  Either this or the `host`
  option must be specified.

  Note: regexes are handled according to the [match mode](#match-mode)
  regex handling rules.

host
: **regex**

: Regular expression used to match the host part of the URL (i.e. domain
  name/ip address).  Either this or the `url` option (but not both) must be
  specified.

  Note: regexes are handled according to the [match mode](#match-mode) regex
  handling rules.

rewrite-url
: **JavaScript function**

: A JavaScript function Chawan will pass the site's URL object to.  If
  a new URL is returned, or the URL object is modified in any way, Chawan
  will transparently redirect the user to this new URL.

cookie = buffer.cookie
: **boolean** / **"save"**

: Whether loading (with "save", also saving) cookies should be allowed for
this URL.

share-cookie-jar
: **host string**

: Cookie jar to use for this domain.  Useful for e.g. sharing cookies with
  subdomains.

referer-from = buffer.referer-from
: **boolean**

: Whether or not Chawan should send a Referer header when opening requests
  originating from this domain.  Simplified example: if you click a link
  on a.com that refers to b.com, and referer-from is true, b.com is sent
  "a.com" as the Referer header.

scripting = buffer.scripting
: **boolean** / **"app"**

: Enable/disable JavaScript execution on this site.  See `buffer.scripting`
for details.

styling = buffer.styling
: **boolean**

: Enable/disable author styles (CSS) on this site.

images = buffer.images
: **boolean**

: Enable/disable loading of images on this site.

document-charset = encoding.document-charset
: **charset label string**

: Specify the default encoding for this site.

proxy = network.proxy
: **URL string**

: Specify a proxy for network requests fetching contents of this buffer.

default-headers = network.default-headers
: **table**

: Specify a list of default headers for HTTP(S) network requests to this
  buffer.

insecure-ssl-no-verify = false
: **boolean**

: When set to true, this disables peer and hostname verification for SSL
  keys on this site, like `curl --insecure` would.

  Please do not use this unless you are absolutely sure you know what you
  are doing.

autofocus = buffer.autofocus
: **boolean**

: When set to true, elements with an "autofocus" attribute are focused on
  automatically after the buffer is loaded.

  If scripting is enabled, this also allows scripts to focus on elements.

meta-refresh = buffer.meta-refresh
: **"never"** / **"always"** / **"ask"**

: Whether or not `http-equiv=refresh` meta tags and headers should be
  respected.  "never" completely disables them, "always" automatically
  accepts all of them, "ask" brings up a pop-up menu.

history = buffer.history
: **boolean**

: Whether or not browsing history should be saved to the disk for this URL.

mark-links = buffer.mark-links
: **boolean**

: Add numeric markers before links.

user-style = buffer.user-style
: **string**

: Specify a user style sheet specific to the site.

  Refer to `buffer.user-style` for details.

## Keybindings

Keybindings are to be placed in these sections:

* for pager interaction: `[page]`
* for line editing: `[line]`

Keybindings are configured using the syntax

```toml
'<keybinding>' = '<action>'
```

Where `<keybinding>` is a combination of unicode characters using the syntax
described below.

`<action>` is either a command defined in the `[cmd]` section, or a
JavaScript expression.  This document only describes the pre-defined
actions in the default config; for a description of the API, see
[**cha-api**](api.md)(7).

Examples:

```toml
# show change URL when Control, Escape and j are pressed
'C-M-j' = 'load'

# go to the first line of the page when g is pressed twice without a preceding
# number, or to the line when a preceding number is given.
'g g' = 'gotoLineOrStart'

# JS functions and expressions are accepted too. Following replaces the
# default search engine with DuckDuckGo Lite.
# (See api.md for a list of available functions, and a discussion on how
# to add your own "namespaced" commands like above.)
'C-k' = '() => pager.load("ddg:")'
```

### Keybinding format

A keybinding is a space-separated list of keys, optionally prefixed by
modifiers `S-` (shift), `C-` (control), or `M-` (meta).

In general, ASCII/Unicode keys can be written as-is.  The exception is
space, which is written as `SPC`.

Other supported named keys are: `TAB`, `ESC`, `RET` (return key), `LF`
(enter key/line feed), `Left`, `Up`, `Down`, `Right` (cursor keys),
`PageUp`, `PageDown` (page up/down), `Home`, `End`, and function keys `F1`
through `F20`.

For backwards-compatibility, spaces can be omitted from key sequences that
do not start with an upper-case letter.  For example, `'gg'` and `'g g'` are
equivalent.  However, components that start with an upper-case letter
(e.g. `'Gg'`) are reserved for key names, so those must be space-separated
(e.g. `'G g'`) to avoid ambiguous parsing.

Also, for backwards-compatibility, spaces at the beginning/end of the
keybinding are translated to `SPC`.

### Pager actions

Default keybindings are highlighted in **bold**.

quit
: **q**

: Exit the browser.

suspend
: **C-z**

: Temporarily suspend the browser

  Note: this also suspends e.g. buffer processes or CGI scripts.  So if
  you are downloading something, that will be delayed until you restart the
  process.

load
: **C-l**

: Open the current address in the URL bar.

loadCursor
: **M-l**

: Open the address of the link or image being hovered in the URL bar.

  If no link/image is under the cursor, an empty URL bar is opened.

loadEmpty

: Open an empty address bar.

webSearch
: **C-k**

: Open the URL bar with an arbitrary search engine.  At the moment, this is
  Brave Search, but this may change in the future.

dupeBuffer
: **M-u**

: Duplicate the current buffer.  This is a shallow clone, so modifications
  to one buffer will affect the other.

reloadBuffer
: **U**

: Open a new buffer with the current buffer's URL, replacing the current
  buffer.

lineInfo
: **C-g**

: Display information about the current line on the status line.

toggleSource
: **&bsol;**

: If viewing an HTML buffer, open a new buffer with its source.  Otherwise,
  open the current buffer's contents as HTML.

saveScreen
: **s s**

: Save the rendered buffer to a file.

saveSource
: **s S**

: Save the buffer's source to a file.

editScreen
: **s e**

: Open the rendered buffer in an editor.

editSource
: **s E**

: Open the buffer's source in an editor.

discardBuffer
: **D**

: Discard the current buffer, and move back to the previous/next buffer
  depending on what the previously viewed buffer was.

discardBufferPrev, discardBufferNext
: **d ,**, **d .**

: Discard the current buffer, and move back to the previous/next buffer,
  or open the link under the cursor.

discardTree
: **M-d**

: Discard all child buffers of the current buffer.

nextBuffer, prevBuffer
: **.**, **,**

: Switch to the next or previous buffer respectively.

enterCommand
: **M-c**

: Directly enter a JavaScript command.  Note that this interacts with
  the pager, not the website being displayed.

searchForward, searchBackward

: Search for a string in the current buffer, forwards or backwards.

isearchForward, searchBackward
: **/**, **?**
: Incremental-search for a string, highlighting the first result, forwards
  or backwards.

searchNext, searchPrev
: **n**, **N**

: Jump to the nth (or if unspecified, first) next/previous search result.

peek

: Display a message of the current buffer's URL on the status line.

peekCursor
: **u**

: Display a message of the URL or title under the cursor on the status
  line.  Multiple calls allow cycling through the two. (i.e. by default,
  press u once -> title, press again -> URL)

showFullAlert
: **s u**

: Show the last alert inside the line editor.  You can also view previous
  ones using C-p or C-n.

copyURL
: **M-y**

: Copy the current buffer's URL to the system clipboard.

copyCursorLink
: **y u**

: Copy the link under the cursor to the system clipboard.

copyCursorImage
: **y I**

: Copy the URL of the image under the cursor to the system clipboard.

gotoClipboardURL
: **M-p**

: Go to the URL currently on the clipboard.

openBookmarks
: **M-b**

: Open the bookmark file.

addBookmark
: **M-a**

: Add the current page to your bookmarks.

toggleLinkHints
: **f**

: Show hints before each link (or button).  After typing a hint, the cursor
  is placed on the respective link.

  The hint character set may be customized with `input.link-hint-chars`.

toggleLinkHintsAutoClick

: Same as `toggleLinkHints`, but also click the selected link.

### Buffer actions

`n` refers to a number preceding the action.  e.g. in `10gg`, `n` is 10.
If no preceding number is input, then it is left unspecified.

Default keybindings are highlighted in **bold**.

cursorUp, cursorDown
: **j**/**C-p**/**Up**,
**k**/**C-n**/**Down**

: Move the cursor upwards/downwards by `n` lines, or if `n` is unspecified,
  by 1.

cursorLeft, cursorRight
: **h**/**Left**, **l**/**Right**

: Move the cursor to the left/right by `n` cells, or if `n` is unspecified,
  by 1.

cursorLineBegin
: **0**/**Home**

: Move the cursor to the first cell of the line.

cursorLineTextStart
: **^**

: Move the cursor to the first non-blank character of the line.

cursorLineEnd
: **&dollar;**/**End**

: Move the cursor to the last cell of the line.

cursorNextWord, cursorNextViWord, cursorNextBigWord
: **w**, **W**

: Move the cursor to the beginning of the nth next [word](#word-types).

cursorPrevWord, cursorPrevViWord, cursorPrevBigWord

: Move the cursor to the end of the nth previous [word](#word-types).

cursorWordEnd, cursorViWordEnd, cursorBigWordEnd
: **e**, **E**

: Move the cursor to the end of the current [word](#word-types), or if
  already there, to the end of the nth next word.

cursorWordBegin, cursorViWordBegin, cursorBigWordBegin
: **b**, **B**

: Move the cursor to the beginning of the current [word](#word-types),
  or if already there, to the end of the nth previous word.

cursorPrevLink, cursorNextLink
: **[**, **]**

: Move the cursor to the end/beginning of the previous/next clickable
  element (e.g. link, input field, etc).

cursorPrevParagraph, cursorNextParagraph
: **{**, **}**

: Move the cursor to the end/beginning of the nth previous/next paragraph.

cursorRevNthLink

: Move the cursor to the nth link of the document, counting backwards from
the document's last line.

cursorNthLink

: Move the cursor to the nth link of the document.

pageUp, pageDown, pageLeft, pageRight
: **C-b**/**PageUp**, **C-f**/**PageDown**, **z H**, **z L**

: Scroll up/down/left/right by `n` pages, or if `n` is unspecified, by one
  page.

halfPageUp, halfPageDown, halfPageLeft, halfPageUp
: **C-u**, **C-d**

: Scroll up/down/left/right by `n` half pages, or if `n` is unspecified, by
  one page.

scrollUp, scrollDown, scrollLeft, scrollRight
: **K**/**C-y**, **J**/**C-e**, **z h**, **z l**

: Scroll up/down/left/right by `n` lines, or if `n` is unspecified, by one
  line.

click
: **RET**/**LF**

: Click the HTML element currently under the cursor.  `n` specifies the
  number of clicks in JS events.

rightClick
: **c**

: Send a right click to the buffer.  If it doesn't catch the event (i.e. no
  JS context menu is shown), toggle the menu instead.

toggleMenu
: **C**

: Toggle the menu.

viewImage
: **I**

: View the image currently under the cursor in an external viewer.

reshape
: **R**

: Reshape the current buffer (=render the current page anew).  Useful if
  the layout is not updating even though it should have.

redraw
: **r**

: Redraw screen contents.  Useful if something messed up the display.

cursorFirstLine, cursorLastLine

: Move to the beginning/end in the buffer.

cursorTop, cursorMiddle, cursorBottom
: **H**, **M**, **L**

: Move to the first line/line in the middle of/last line on the screen.
(Equivalent to `H`, `M`, `L` in vi.)

raisePage, raisePageBegin, centerLine, centerLineBegin, lowerPage, lowerPageBegin
: **z t**, **z RET**, **z z**, **z .**, **z b**, **z -**

: If `n` is specified, move cursor to line `n`. Then,

    * `raisePage` scrolls down so that the cursor is on the top line of
      the screen.  (vi `z RET`, vim `z t`.)
    * `centerLine` shifts the screen so that the cursor is in the middle
      of the screen. (vi `z .`, vim `z z`.)
    * `lowerPage` scrolls up so that the cursor is on the bottom line of
      the screen.  (vi `z -`, vim `z b`.)

    The -Begin variants also move the cursor to the line's first
    non-blank character, as the original keybindings in vi do.

nextPageBegin
: **z +**

: If `n` is specified, move to the screen before the nth line and raise the
  page.  Otherwise, go to the next screen's first line and raise the page.

previousPageBegin
: **z ^**

: If `n` is specified, move to the screen before the nth line and lower
  the page.  Otherwise, go to the previous screen's last line and lower
  the page.

cursorLeftEdge, cursorMiddleColumn, cursorRightEdge
: **g 0**, **g c**, **g $**

: Move to the first/middle/last column on the screen.

centerColumn

: Center screen around the current column.  (w3m `Z`.)

gotoLineOrStart, gotoLineOrEnd
: **g g**, **G**

: If `n` is specified, jump to line `n`.  Otherwise, jump to the first/last
  line of the buffer.

gotoColumnOrBegin, gotoColumnOrEnd
: **&vert;**

: If `n` is specified, jump to column `n` of the current line.  Otherwise,
  jump to the first/last column.

mark
: **m**

: Wait for a character `x` and then set a mark with the ID `x`.

gotoMark, gotoMarkY
: **&grave;**, **'**

: Wait for a character `x` and then jump to the mark with the ID `x` (if it
  exists on the page).

  `gotoMark` sets both the X and Y positions; gotoMarkY only sets the Y
  position.

markURL
: **:**

: Convert URL-like strings to anchors on the current page.

saveLink
: **s RET**

: Save resource from the URL pointed to by the cursor to the disk.

saveSource
: **s S**

: Save the source of the current buffer to the disk.

saveImage
: **s I**

: Save the image currently under the cursor.

toggleImages
: **M-i**

: Toggle display of images in the current buffer.

toggleScripting
: **M-j**

: Reload the current buffer with scripting enabled/disabled.

toggleCookie
: **M-k**

: Reload the current buffer with cookies enabled/disabled.

cursorSearchWordForward
: **C-a**, **\***

: Search for the word currently under the cursor.

cursorSearchWordBackward
: **#**

: Search for the word currently under the cursor, backwards.

### Line-editing actions

line.submit
: **RET**, **LF**

: Submit the line.

line.cancel
: **C-c**

: Cancel the current operation.

line.backspace, line.delete
: **C-h**, **C-d**

: Delete character before (backspace)/after (delete) the cursor.

line.clear, line.kill
: **C-u**/**C-x C-?**, **C-k**

: Delete text before (clear)/after (kill) the cursor.

line.openEditor
: **C-x C-e**

: Open the line editor's contents in $EDITOR.

line.clearWord, line.killWord
: **C-w**, **M-d**

: Delete word before (clear)/after (kill) the cursor.

line.backward, line.forward
: **C-b**, **C-f**

: Move cursor backward/forward by one character.

line.prevWord, line.nextWord
: **M-b**, **M-f**

: Move cursor to the previous/next word by one character

line.begin, line.end
: **C-a**/**Home**, **C-e**/**End**

: Move cursor to the beginning/end of the line.

line.escape
: **C-v**

: Ignore keybindings for next character.

line.prevHist, line.nextHist
: **C-p**, **C-n**

: Jump to the previous/next history entry

Note: to facilitate URL editing, the line editor has a different definition
of what a word is than the pager.  For the line editor, a word is either
a sequence of alphanumeric characters, or any single non-alphanumeric
character.  (This means that e.g. `https://` consists of four words:
`https`, `:`, `/` and `/`.)

```Examples:
# Control+A moves the cursor to the beginning of the line.
'C-a' = 'line.begin'

# Escape+D deletes everything after the cursor until it reaches a word-breaking
# character.
'M-d' = 'line.killWord'
```

## Appendix

### Regex handling

Regular expressions are currently handled using the libregexp library from
QuickJS.  This means that all regular expressions work as in JavaScript.

There are two different modes of regex preprocessing in Chawan: "search"
mode and "match" mode.  Match mode is used for configurations (meaning in
all values in this document described as "regex").  Search mode is used for
the on-page search function (using searchForward/isearchForward etc.)

#### Match mode

Regular expressions are assumed to be exact matches, except when they start
with a caret (^) sign or end with an unescaped dollar ($) sign.

In other words, the following transformations occur:

```
^abcd -> ^abcd (no change, only beginning is matched)
efgh$ -> efgh$ (no change, only end is matched)
^ijkl$ -> ^ijkl$ (no change, the entire line is matched)
mnop -> ^mnop$ (changed to exact match, the entire line is matched)
```

Match mode has no way to toggle JavaScript regex flags like `i`.

#### Search mode

For on-page search, the above transformations do not apply; the search
`/abcd` searches for the string `abcd` inside all lines.

Search mode also has some other convenience transformations (these do
not work in match mode):

* The string `\c` (backslash + lower-case c) inside a search-mode regex
  enables case-insensitive matching.
* Conversely, `\C` (backslash + capital C) disables case-insensitive
  matching.  (Useful if you have `ignore-case` set to true, which is
  the default.)
* `\<` and `\>` is converted to `\b` (as in vi, grep, etc.)

Like match mode, search mode operates on individual lines.  This means
that search patterns do not match text wrapped over multiple lines.

### Path handling

Rules for path handling are similar to how the shell handles strings.

* Tilde-expansion is used to determine the user's home directory. So
  e.g. `~/whatever` works.
* Environment variables can be used like `$ENV_VAR`.
* Relative paths are relative to the Chawan configuration directory
  (i.e. `$CHA_DIR`).

Some environment variables are also exported by Chawan:

* `$CHA_BIN_DIR`: the directory which the `cha` binary resides in.
  Symbolic links are automatically resolved to determine this path.
* `$CHA_LIBEXEC_DIR`: the directory for all executables Chawan uses for
  operation. By default, this is `$CHA_BIN_DIR/../libexec/chawan`.
* `$CHA_DIR`: the configuration directory.  (This can also be set by the
  user; see the top section for details.)
* `$CHA_DATA_DIR`: if the configuration file uses XDG base directories, this
  is `${XDG_DATA_HOME:-$HOME/.local/share}/chawan`.  Otherwise, it is the
  same as `$CHA_DIR`.
	- Exception: if `$CHA_DIR` is set before `cha` is invoked, then
	  `$CHA_DATA_DIR` is also read.  This is to make nested invocations
	  work in configurations with XDG basedirs.

### Word types

Word-based pager commands can operate with different definitions of
words. Currently, these are:

* w3m words
* vi words
* Big words

#### w3m word

A w3m word is a sequence of alphanumeric characters.  Symbols are
treated in the same way as whitespace.

#### vi word

A vi word is a sequence of characters in the same character category.
Currently, character categories are alphanumeric characters, symbols,
han letters, hiragana, katakana, and hangul.

vi words may be separated by whitespace; however, vi words from separate
categories do not have to be whitespace-separated.  e.g. the following
character sequence contains two words:

```
hello[]+{}@`!
```

#### Big word

A big word is a sequence of non-whitespace characters.

It is essentially the same as a w3m word, but with symbols being defined
as non-whitespace.

## See also

[**cha**](cha.md)(1) [**cha-api**](api.md)(7)
