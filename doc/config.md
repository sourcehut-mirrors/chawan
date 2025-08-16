<!-- MANON
% CHA-CONFIG 5
MANOFF -->

# Configuration of Chawan

Chawan supports configuration of various options like keybindings, user
stylesheets, site preferences, etc. The configuration format is similar
to toml, with the following exceptions:

* Inline tables may span across multiple lines.
* Regular tables (`[table]`) and inline tables (`table = {}`) have
  different semantics.  The first is additive, meaning old values are
  not removed.  The second is destructive, and clears all definitions in
  the table specified.
* `[[table-array]]` is sugar for `[table-array.n]`, where `n` is the
  number of declared table arrays.  For example, you can declare
  anonymous siteconfs using the syntax `[[siteconf]]`.

The canonical configuration file path is ~/.chawan/config.toml, but
the search path accommodates XDG basedirs as well:

1. config file specified through -C switch -> use that
2. `$CHA_DIR` is set -> use `$CHA_DIR`/config.toml
3. `$XDG_CONFIG_HOME` is set -> use `$XDG_CONFIG_HOME`/chawan/config.toml
4. ~/.config/chawan/config.toml exists -> use that
5. ~/.chawan/config.toml exists -> use that

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
* [Protocol](#protocol)
* [Omnirule](#omnirule)
* [Siteconf](#siteconf)
* [Keybindings](#keybindings)
   * [Pager actions](#pager-actions)
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

<table>
<col width=20%><col width=10%><col width=15%><col width=55%>

<tr>
<th>Name</th>
<th>Value</th>
<th>Default</th>
<th>Function</th>
</tr>

<tr>
<td>visual-home</td>
<td>url</td>
<td>"about:chawan"</td>
<td>Page opened when Chawan is called with the -V option and no other
pages are passed as arguments.</td>
</tr>

<tr>
<td>startup-script</td>
<td>JavaScript code</td>
<td>""</td>
<td>Script Chawan runs on start-up. Pages will not be loaded until this
function exits. (Note however that asynchronous functions like setTimeout
do not block loading.)</td>
</tr>

<tr>
<td>headless</td>
<td>boolean / "dump"</td>
<td>false</td>
<td>When set to true or "dump", the browser does not take input;
instead, it prints a rendered version of all buffers in order, then
exits.
<p>
The difference between `true` and "dump" is that `true` first waits
for all scripts and network requests to run to completion, while "dump"
does not.  This means that `true` may never exit when scripting is
enabled (e.g. if a script sets `setInterval`.)
<p>
Piping `cha` to an external program or passing the `-d` switch has the
same effect as setting this option to "dump".
</td>
</tr>

<tr>
<td>console-buffer</td>
<td>boolean</td>
<td>true</td>
<td>Whether Chawan should open a console buffer in non-headless mode.
<p>
Warning: this is only useful for debugging. Disabling this option without
manually redirecting standard error will result in error messages randomly
appearing on your screen.</td>
</tr>

</table>

## Buffer

Buffer options are to be placed in the `[buffer]` section.

These options are global to all buffers. For more granular filtering,
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

<table>
<col width=20%><col width=15%><col width=10%><col width=55%>

<tr>
<th>Name</th>
<th>Value</th>
<th>Default</th>
<th>Function</th>
</tr>

<tr>
<td>styling</td>
<td>boolean</td>
<td>true</td>
<td>Enable/disable author style sheets. Note that disabling this does
not affect user styles.</td>
</tr>

<tr>
<td>scripting</td>
<td>boolean / "app"</td>
<td>false</td>
<td>Enable/disable JavaScript in *all* buffers.
<p>
`"app"` also enables JavaScript APIs that can be used to fingerprint
users (e.g. querying the window's size.) This may achieve better
compatibility with websites that behave like applications, at the cost
of reduced privacy.
<p>
For security reasons, users are encouraged to selectively enable
JavaScript with `[[siteconf]]` instead of using this setting.</td>
</tr>

<tr>
<td>images</td>
<td>boolean</td>
<td>false</td>
<td>Enable/disable inline image display.</td>
</tr>

<tr>
<td>cookie</td>
<td>boolean / "save"</td>
<td>false</td>
<td>Enable/disable cookies on sites.
<p>
If the string "save" is specified, then cookies are also saved to
`external.cookie-file`. `true` still reads cookies.txt, but does not
modify it.
<p>
In Chawan, each website gets a separate cookie jar, so websites relying
on cross-site cookies may not work as expected. You may use the
`[[siteconf]]` `"share-cookie-jar"` setting to adjust this behavior for
specific sites.</td>
</tr>

<tr>
<td>referer-from</td>
<td>boolean</td>
<td>false</td>
<td>Enable/disable the "Referer" header.
<p>
Defaults to false. For privacy reasons, users are encouraged to leave this
option disabled, only enabling it for specific sites in `[[siteconf]]`.
</td>
</tr>

<tr>
<td>autofocus</td>
<td>boolean</td>
<td>false</td>
<td>When set to true, elements with an "autofocus" attribute are focused on
automatically after the buffer is loaded.
<p>
If scripting is enabled, this also allows scripts to focus on elements.</td>
</tr>

<tr>
<td>meta-refresh</td>
<td>"never" / "always" / "ask"</td>
<td>"ask"</td>
<td>Whether or not `http-equiv=refresh` meta tags should be respected. "never"
completely disables them, "always" automatically accepts all of them, "ask"
brings up a pop-up menu.</td>
</tr>

<tr>
<td>history</td>
<td>boolean</td>
<td>true</td>
<td>Whether or not browsing history should be saved to the disk.</td>
</tr>

<tr>
<td>mark-links</td>
<td>boolean</td>
<td>false</td>
<td>Add numeric markers before links.  In headless/dump mode, this also
prints a list of URLs after the page.</td>
</tr>

<tr>
<td>user-style</td>
<td>string</td>
<td>""</td>
<td>A user stylesheet applied to all buffers.
<p>
External stylesheets can be imported using the `@import 'file.css';`
syntax.  Paths are relative to the configuration directory.
<p>
Nested @import is not supported yet.
</td>
</tr>

</table>

## Search

Search options are to be placed in the `[search]` section.

Following is a list of search options:

<table>
<col width=20%><col width=15%><col width=10%><col width=55%>

<tr>
<th>Name</th>
<th>Value</th>
<th>Default</th>
<th>Function</th>
</tr>

<tr>
<td>wrap</td>
<td>boolean</td>
<td>true</td>
<td>Whether on-page searches should wrap around the document.</td>
</tr>

<tr>
<td>ignore-case</td>
<td>"auto" / boolean</td>
<td>"auto"</td>
<td>When set to true, document-wide searches are case-insensitive by
default. When set to "auto", searches are only case-sensitive when the search
term includes a capital letter.
<p>
Note: this can also be overridden inline in the search bar (vim-style),
with the escape sequences `\c` (ignore case) and `\C` (strict case). See
[search mode](#search-mode) for details.)</td>
</tr>

</table>

## Encoding

Encoding options are to be placed in the `[encoding]` section.

Following is a list of encoding options:

<table>
<col width=20%><col width=15%><col width=15%><col width=50%>

<tr>
<th>Name</th>
<th>Value</th>
<th>Default</th>
<th>Function</th>
</tr>

<tr>
<td>document-charset</td>
<td>array of charset label strings</td>
<td>["utf-8", "sjis", "euc-jp", "latin2"]</td>
<td>List of character sets for loading documents.
<p>
All listed character sets are enumerated until the document has been decoded
without errors. In HTML, meta tags and the BOM may override this with a
different charset, so long as the specified charset can decode the document
correctly.
</td>
</tr>

<tr>
<td>display-charset</td>
<td>string</td>
<td>"auto"</td>
<td>Character set for keyboard input and displaying documents.
<p>
Used in dump mode as well.
<p>
(This means that e.g. `cha -I EUC-JP -O UTF-8 a > b` is roughly equivalent to
`iconv -f EUC-JP -t UTF-8`.)</td>
</tr>

</table>

## External

External options are to be placed in the `[external]` section.

Following is a list of external options:

<table>
<col width=25%><col width=10%><col width=20%><col width=45%>

<tr>
<th>Name</th>
<th>Value</th>
<th>Default</th>
<th>Function</th>
</tr>

<tr>
<td>tmpdir</td>
<td>path</td>
<td>{usually /tmp/cha-tmp-user}</td>
<td>Directory used to save temporary files.</td>
</tr>

<tr>
<td>editor</td>
<td>shell command</td>
<td>{usually `$EDITOR`}</td>
<td>External editor command. %s is substituted for the file name, %d for
the line number.</td>
</tr>

<tr>
<td>mailcap</td>
<td>array of paths</td>
<td>{see mailcap docs}</td>
<td>Search path for <!-- MANOFF -->[mailcap](mailcap.md) files.<!-- MANON -->
<!-- MANON mailcap files. (See **cha-mailcap**(5) for details.) MANOFF -->
</td>
</tr>

<tr>
<td>mime-types</td>
<td>array of paths</td>
<td>{see mime.types docs}</td>
<td>Search path for <!-- MANOFF -->[mime.types](mime.types.md) files.<!-- MANON -->
<!-- MANON mime.types files. (See **cha-mime.types**(5) for details.) MANOFF -->
</td>
</tr>

<tr>
<td>auto-mailcap</td>
<td>path</td>
<td>"auto.mailcap"</td>
<td>Mailcap file for entries that are automatically executed.
<p>
The "Open as" prompt also saves entries in this file.</td>
</tr>

<tr>
<td>cgi-dir</td>
<td>array of paths</td>
<td>{see local CGI docs}</td>
<td>Search path for <!-- MANOFF -->[local CGI](localcgi.md) scripts.<!-- MANON -->
<!-- MANON local CGI scripts. (See **cha-localcgi**(5) for details.) MANOFF -->
</td>
</tr>

<tr>
<td>urimethodmap</td>
<td>array of paths</td>
<td>{see urimethodmap docs}</td>
<td>Search path for <!-- MANOFF -->[urimethodmap](urimethodmap.md) files.<!-- MANON -->
<!-- MANON urimethodmap files. (See **cha-urimethodmap**(5) for details.) MANOFF -->
</td>
</tr>

<tr>
<td>w3m-cgi-compat</td>
<td>boolean</td>
<td>false</td>
<td>Enable local CGI compatibility with w3m. In short, it redirects
`file:///cgi-bin/*` and `file:///$LIB/cgi-bin/*` to `cgi-bin:*`. For further
details, see <!-- MANOFF -->[localcgi.md](localcgi.md).<!-- MANON -->
<!-- MANON **cha-localcgi**(5). MANOFF -->
</td>
</tr>

<tr>
<td>download-dir</td>
<td>path</td>
<td>{same as tmpdir}</td>
<td>Path to pre-fill for "Save to:" prompts.</td>
</tr>

<tr>
<td>show-download-panel</td>
<td>boolean</td>
<td>true</td>
<td>Whether the `about:downloads` should be shown after starting a
download.</td>
</tr>

<tr>
<td>copy-cmd</td>
<td>shell command</td>
<td>"xsel -bi"</td>
<td>Command to use for "copy to clipboard" operations.</td>
</tr>

<tr>
<td>paste-cmd</td>
<td>shell command</td>
<td>"xsel -bo"</td>
<td>Command to use for "read from clipboard" operations.</td>
</tr>

<tr>
<td>bookmark</td>
<td>path</td>
<td>"bookmark.md"</td>
<td>Path to the bookmark.md file. (The file it points to should have a
.md extension, so that its type can be correctly deduced.)</td>
</tr>

<tr>
<td>history-file</td>
<td>path</td>
<td>"history.uri"</td>
<td>Path to the history file.</td>
</tr>

<tr>
<td>history-size</td>
<td>number</td>
<td>100</td>
<td>Maximum length of the history file.</td>
</tr>

<tr>
<td>cookie-file</td>
<td>path</td>
<td>"cookies.txt"</td>
<td>Path to the cookie file.
<p>
The format is equivalent to curl's "cookies.txt" format, except that a
"jar@" part is prepended for cookies that belong in a different jar
than the domain.
<p>
Cookies from this file are used if "buffer.cookie" (or its equivalent
siteconf override) is set to `true` or `"save"`. This means that `true`
sets the cookie-file to a "read-only" mode.</td>
</tr>

</table>

## Input

Input options are to be placed in the `[input]` section.

<table>
<col width=20%><col width=10%><col width=10%><col width=60%>

<tr>
<th>Name</th>
<th>Value</th>
<th>Function</th>
</tr>

<tr>
<td>vi-numeric-prefix</td>
<td>boolean</td>
<td>true</td>
<td>Whether vi-style numeric prefixes to commands should be accepted.
<p>
Only applies for keybindings defined in `[page]`.</td>
</tr>

<tr>
<td>use-mouse</td>
<td>boolean</td>
<td>true</td>
<td>Whether Chawan is allowed to intercept mouse clicks.
<p>
The current implementation imitates w3m.</td>
</tr>

<tr>
<td>bracketed-paste</td>
<td>boolean</td>
<td>true</td>
<td>Whether Chawan should ask for bracketed paste.
<p>
When true, the terminal will (hopefully) mark pasted text with escape
sequences, which a) ensures that pasting a newline character into the
line editor does not submit the editor, b) allows Chawan to intercept
text pasted into the pager, automatically loading it into the browser's
URL bar.
</td>
</tr>

<tr>
<td>wheel-scroll</td>
<td>number</td>
<td>5</td>
<td>Number of lines to scroll for a mouse wheel event.</td>
</tr>

<tr>
<td>side-wheel-scroll</td>
<td>number</td>
<td>5</td>
<td>Number of columns to scroll for a mouse side-wheel event.</td>
</tr>

</table>

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

<table>
<col width=25%><col width=12%><col width=13%><col width=50%>

<tr>
<th>Name</th>
<th>Value</th>
<th>Default</th>
<th>Function</th>
</tr>

<tr>
<td>max-redirect</td>
<td>number</td>
<td>10</td>
<td>Maximum number of redirections to follow.</td>
</tr>

<tr>
<td>max-net-connections</td>
<td>number</td>
<td>12</td>
<td>Maximum number of simultaneous network connections allowed in one
buffer.  Further connections are held back until the number returns
below the threshold.</td>
</tr>

<tr>
<td>prepend-scheme</td>
<td>string</td>
<td>"https://"</td>
<td>Prepend this to URLs passed to Chawan without a scheme.
<p>
Note that local files (`file:` scheme) will always be checked first; only
if this fails, Chawan will retry the request with `prepend-scheme` set as
the scheme.</td>
</tr>

<tr>
<td>proxy</td>
<td>URL</td>
<td>unset</td>
<td>Specify a proxy for all network requests Chawan makes.  Currently,
the formats `http://user:pass@domain` and `socks5://user:pass@domain`
are accepted.  (Unlike in curl, `socks5h` is an alias of `socks5`, and
DNS requests are always tunneled.)
<p>
Can be overridden by siteconf.</td>
</tr>

<tr>
<td>default-headers</td>
<td>table</td>
<td>{omitted}</td>
<td>Specify a list of default headers for all HTTP(S) network requests. Can be
overridden by siteconf.</td>
</tr>

<tr>
<td>allow-http-from-file</td>
<td>boolean</td>
<td>false</td>
<td>**WARNING: think twice before enabling this.**
<p>
Allows HTTP and HTTPS requests from the `file:` and `stream:` schemes.
This is a very bad idea in general, because it allows local files to
ping remote servers (a functionality commonly abused by HTML e-mails to
track your mailbox activity.)
<p>
On the other hand, it allows loading images in HTML e-mails if you
don't care about the privacy implications.</td>
</tr>

</table>

## Display

Display options are to be placed in the `[display]` section.

Following is a list of display options:

<table>
<col width=33%><col width=17%><col width=10%><col width=40%>

<tr>
<th>Name</th>
<th>Value</th>
<th>Default</th>
<th>Function</th>
</tr>

<tr>
<td>color-mode</td>
<td>"monochrome" / "ansi" / "eight-bit" / "true-color" / "auto"</td>
<td>"auto"</td>
<td>Set the color mode. "auto" for automatic detection, "monochrome"
for black on white, "ansi" for ansi colors, "eight-bit" for 256-color mode, and
"true-color" for true colors.</td>
</tr>

<tr>
<td>format-mode</td>
<td>"auto" / ["bold", "italic", "underline", "reverse", "strike", "overline",
"blink"]</td>
<td>"auto"</td>
<td>Specifies output formatting modes. Accepts the string "auto" or an array
of specific attributes. An empty array (`[]`) disables formatting
completely.</td>
</tr>

<tr>
<td>no-format-mode</td>
<td>["bold", "italic", "underline", "reverse", "strike", "overline", "blink"]</td>
<td>"overline"</td>
<td>Disable specific formatting modes.</td>
</tr>

<tr>
<td>image-mode</td>
<td>"auto" / "none" / "sixel" / "kitty"</td>
<td>"auto"</td>
<td>Specifies the image output mode. "sixel" uses sixels for output, "kitty"
uses the Kitty image display protocol, "none" disables image display
completely.
<p>
"auto" tries to detect sixel or kitty support, and falls back to "none" when
neither are available.  This is the default setting, but you must also
enable `buffer.images` for images to work.</td>
</tr>

<tr>
<td>sixel-colors</td>
<td>"auto" / 2..65535</td>
<td>"auto"</td>
<td>Only applies when `display.image-mode="sixel"`. Setting a number
overrides the number of sixel color registers reported by the terminal.
</td>
</tr>

<tr>
<td>alt-screen</td>
<td>"auto" / boolean</td>
<td>"auto"</td>
<td>Enable/disable the alternative screen.</td>
</tr>

<tr>
<td>highlight-color</td>
<td>color</td>
<td>"cyan"</td>
<td>Set the highlight color for incremental search and marks.  Both hex
values and CSS color names are accepted.
<p>
In monochrome mode, this setting is ignored; instead, reverse video is
used.</td>
</tr>

<tr>
<td>highlight-marks</td>
<td>boolean</td>
<td>true</td>
<td>Enable/disable highlighting of marks.</td>
</tr>

<tr>
<td>double-width-ambiguous</td>
<td>boolean</td>
<td>false</td>
<td>Assume the terminal displays characters in the East Asian Ambiguous
category as double-width characters. Useful when e.g. ○ occupies two
cells.</td>
</tr>

<tr>
<td>minimum-contrast</td>
<td>number</td>
<td>100</td>
<td>Specify the minimum difference between the luminance (Y) of the background
and the foreground. -1 disables this function (i.e. allows black letters on
black background, etc).</td>
</tr>

<tr>
<td>force-clear</td>
<td>boolean</td>
<td>false</td>
<td>Force the screen to be completely cleared every time it is redrawn.</td>
</tr>

<tr>
<td>set-title</td>
<td>boolean</td>
<td>true</td>
<td>Set the terminal emulator's window title to that of the current page.</td>
</tr>

<tr>
<td>default-background-color</td>
<td>"auto" / color</td>
<td>"auto"</td>
<td>Overrides the assumed background color of the terminal. "auto" leaves
background color detection to Chawan.</td>
</tr>

<tr>
<td>default-foreground-color</td>
<td>"auto" / color</td>
<td>"auto"</td>
<td>Sets the assumed foreground color of the terminal. "auto" leaves foreground
color detection to Chawan.</td>
</tr>

<tr>
<td>query-da1</td>
<td>bool</td>
<td>true</td>
<td>Enable/disable querying Primary Device Attributes, and with it, all
"dynamic" terminal querying.
<p>
Do not alter this value unless Chawan told you so; the output will look
awful.</td>
</tr>

<tr>
<td>columns, lines, pixels-per-column, pixels-per-line</td>
<td>number</td>
<td>80, 24, 9, 18</td>
<td>Fallback values for the number of columns, lines, pixels per
column, and pixels per line for the cases where it cannot be determined
automatically. (For example, these values are used in dump mode.)</td>
</tr>

<tr>
<td>force-columns, force-lines, force-pixels-per-column,
force-pixels-per-line</td>
<td>boolean</td>
<td>false</td>
<td>Force-set columns, lines, pixels per column, or pixels per line to the
fallback values provided above.</td>
</tr>

</table>

## Protocol

Protocol-related rules are to be placed in objects keyed as
`[protocol.{protocol-name}]`. e.g. FTP related rules are placed in in
`[protocol.ftp]`.

<table>
<col width=20%><col width=10%><col width=10%><col width=60%>

<tr>
<th>Name</th>
<th>Value</th>
<th>Default</th>
<th>Function</th>
</tr>

<tr>
<td>form-request</td>
<td>"http" / "ftp" / "data" / "mailto"</td>
<td>"http"</td>
<td>Specify which protocol to imitate when submitting forms to this
protocol.</td>
</tr>

</table>

## Omnirule

The omni-bar (by default opened with C-l) can be used to perform
searches using omni-rules.  These are to be specified as sub-keys
to table `[omnirule]`.  (The sub-key itself is ignored; you can use
anything as long it doesn't conflict with other keys.)

Examples:

```
# Search using DuckDuckGo Lite.
# (This rule is included in the default config, although C-k now invokes
# Google search.)
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
* `go:` - Google Search.
* `wk:` - English Wikipedia.
* `wd:` - English Wikitionary.
* `mo:` - Mojeek.

Omnirule options:

<table>
<col width=25%><col width=25%><col width=50%>

<tr>
<th>Name</th>
<th>Value</th>
<th>Function</th>
</tr>

<tr>
<td>match</td>
<td>regex</td>
<td>Regular expression used to match the input string. Note that websites
passed as arguments are matched as well.
<p>
Note: regexes are handled according to the [match mode](#match-mode) regex
handling rules.</td>
</tr>

<tr>
<td>substitute-url</td>
<td>JavaScript function</td>
<td>A JavaScript function Chawan will pass the input string to. If a new string is
returned, it will be parsed instead of the old one.</td>
</tr>

</table>

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

<table>
<col width=25%><col width=15%><col width=28%><col width=32%>

<tr>
<th>Name</th>
<th>Value</th>
<th>Overrides</th>
<th>Function</th>
</tr>

<tr>
<td>url</td>
<td>regex</td>
<td>n/a</td>
<td>Regular expression used to match the URL. Either this or the `host` option
must be specified.
<p>
Note: regexes are handled according to the [match mode](#match-mode) regex
handling rules.</td>
</tr>

<tr>
<td>host</td>
<td>regex</td>
<td>n/a</td>
<td>Regular expression used to match the host part of the URL (i.e. domain
name/ip address.) Either this or the `url` option must be specified.
<p>
Note: regexes are handled according to the [match mode](#match-mode) regex
handling rules.</td>
</tr>

<tr>
<td>rewrite-url</td>
<td>JavaScript function</td>
<td>n/a</td>
<td>A JavaScript function Chawan will pass the site's URL object to. If
a new URL is returned, or the URL object is modified in any way, Chawan
will transparently redirect the user to this new URL.</td>
</tr>

<tr>
<td>cookie</td>
<td>boolean / "save"</td>
<td>`buffer.cookie`</td>
<td>Whether loading (with "save", also saving) cookies should be allowed
for this URL.</td>
</tr>

<tr>
<td>share-cookie-jar</td>
<td>host</td>
<td>n/a</td>
<td>Cookie jar to use for this domain. Useful for e.g. sharing cookies with
subdomains.</td>
</tr>

<tr>
<td>referer-from</td>
<td>boolean</td>
<td>`buffer.referer-from`</td>
<td>Whether or not we should send a Referer header when opening requests
originating from this domain. Simplified example: if you click a link on a.com
that refers to b.com, and referer-from is true, b.com is sent "a.com" as the
Referer header.
</td>
</tr>

<tr>
<td>scripting</td>
<td>boolean / "app"</td>
<td>`buffer.scripting`</td>
<td>Enable/disable JavaScript execution on this site. See
`buffer.scripting` for details.</td>
</tr>

<tr>
<td>styling</td>
<td>boolean</td>
<td>`buffer.styling`</td>
<td>Enable/disable author styles (CSS) on this site.</td>
</tr>

<tr>
<td>images</td>
<td>boolean</td>
<td>`buffer.images`</td>
<td>Enable/disable image display on this site.</td>
</tr>

<tr>
<td>document-charset</td>
<td>charset label string</td>
<td>`encoding.document-charset`</td>
<td>Specify the default encoding for this site.</td>
</tr>

<tr>
<td>proxy</td>
<td>URL</td>
<td>`network.proxy`</td>
<td>Specify a proxy for network requests fetching contents of this
buffer.</td>
</tr>

<tr>
<td>default-headers</td>
<td>table</td>
<td>`network.default-headers`</td>
<td>Specify a list of default headers for HTTP(S) network requests
to this buffer.</td>
</tr>

<tr>
<td>insecure-ssl-no-verify</td>
<td>boolean</td>
<td>n/a</td>
<td>Defaults to false. When set to true, this disables peer and hostname
verification for SSL keys on this site, like `curl --insecure` would.
<p>
Please do not use this unless you are absolutely sure you know what you
are doing.</td>
</tr>

<tr>
<td>autofocus</td>
<td>boolean</td>
<td>`buffer.autofocus`</td>
<td>When set to true, elements with an "autofocus" attribute are focused
on automatically after the buffer is loaded.
<p>
If scripting is enabled, this also allows scripts to focus on
elements.</td>
</tr>

<tr>
<td>meta-refresh</td>
<td>"never" / "always" / "ask"</td>
<td>`buffer.meta-refresh`</td>
<td>Whether or not `http-equiv=refresh` meta tags should be respected. "never"
completely disables them, "always" automatically accepts all of them, "ask"
brings up a pop-up menu.
</td>
</tr>

<tr>
<td>history</td>
<td>boolean</td>
<td>`buffer.history`</td>
<td>Whether or not browsing history should be saved to the disk for this
URL.</td>
</tr>

<tr>
<td>mark-links</td>
<td>boolean</td>
<td>`buffer.mark-links`</td>
<td>Add numeric markers before links.</td>
</tr>

<tr>
<td>user-style</td>
<td>string</td>
<td>`buffer.user-style`</td>
<td>Specify a user style sheet specific to the site.
<p>
Please refer to `buffer.user-style` for details.</td>
</tr>

</table>

## Keybindings

Keybindings are to be placed in these sections:

* for pager interaction: `[page]`
* for line editing: `[line]`

Keybindings are configured using the syntax

```toml
'<keybinding>' = '<action>'
```

Where `<keybinding>` is a combination of unicode characters with or without
modifiers. Modifiers are the prefixes `C-` and `M-`, which add control or
escape to the keybinding respectively (essentially making `M-` the same as
`C-[`). Modifiers can be escaped with the `\` sign.

`<action>` is either a command defined in the `[cmd]` section, or a JavaScript
expression. Here we only describe the pre-defined actions in the default config;
for a description of the API, please see:

<!-- MANOFF -->
[The API documentation](api.md).
<!-- MANON -->
<!-- MANON
The API documentation at **cha-api**(5).
MANOFF -->

Examples:

```toml
# show change URL when Control, Escape and j are pressed
'C-M-j' = 'cmd.pager.load'

# go to the first line of the page when g is pressed twice without a preceding
# number, or to the line when a preceding number is given.
'gg' = 'cmd.buffer.gotoLineOrStart'

# JS functions and expressions are accepted too. Following replaces the
# default search engine with DuckDuckGo Lite.
# (See api.md for a list of available functions, and a discussion on how
# to add your own "namespaced" commands like above.)
'C-k' = '() => pager.load("ddg:")'
```

### Pager actions

<table>
<col width=20%><col width=30%><col width=50%>

<tr>
<th>Default key</th>
<th>Name</th>
<th>Function</th>
</tr>

<tr>
<td><kbd>q</kbd></td>
<td>`cmd.pager.quit`</td>
<td>Exit the browser.</td>
</tr>

<tr>
<td><kbd>C-z</kbd></td>
<td>`cmd.pager.suspend`</td>
<td>Temporarily suspend the browser
<p>
Note: this also suspends e.g. buffer processes or CGI scripts. So if you are
downloading something, that will be delayed until you restart the process.</td>
</tr>

<tr>
<td><kbd>C-l</kbd></td>
<td>`cmd.pager.load`</td>
<td>Open the current address in the URL bar.</td>
</tr>

<tr>
<td><kbd>M-l</kbd></td>
<td>`cmd.pager.loadCursor`</td>
<td>Open the address of the link or image being hovered in the URL
bar.
<p>
If no link/image is under the cursor, an empty URL bar is opened.</td>
</tr>

<tr>
<td><kbd>C-k</kbd></td>
<td>`cmd.pager.webSearch`</td>
<td>Open the URL bar with an arbitrary search engine. At the moment, this is
Google Search, but this may change in the future.</td>
</tr>

<tr>
<td><kbd>M-u</kbd></td>
<td>`cmd.pager.dupeBuffer`</td>
<td>Duplicate the current buffer by loading its source to a new buffer.</td>
</tr>

<tr>
<td><kbd>U</kbd></td>
<td>`cmd.pager.reloadBuffer`</td>
<td>Open a new buffer with the current buffer's URL, replacing the current
buffer.</td>
</tr>

<tr>
<td><kbd>C-g</kbd></td>
<td>`cmd.pager.lineInfo`</td>
<td>Display information about the current line on the status line.</td>
</tr>

<tr>
<td><kbd>&bsol;</kbd></td>
<td>`cmd.pager.toggleSource`</td>
<td>If viewing an HTML buffer, open a new buffer with its source. Otherwise,
open the current buffer's contents as HTML.</td>
</tr>

<tr>
<td><kbd>D</kbd></td>
<td>`cmd.pager.discardBuffer`</td>
<td>Discard the current buffer, and move back to the previous/next buffer
depending on what the previously viewed buffer was.</td>
</tr>

<tr>
<td><kbd>d,</kbd>, <kbd>d.</kbd></td>
<td>`cmd.pager.discardBufferPrev`, `cmd.pager.discardBufferNext`</td>
<td>Discard the current buffer, and move back to the previous/next buffer, or
open the link under the cursor.</td>
</tr>

<tr>
<td><kbd>M-d</kbd></td>
<td>`cmd.pager.discardTree`</td>
<td>Discard all child buffers of the current buffer.</td>
</tr>

<tr>
<td><kbd>.</kbd>, <kbd>,</kbd>, <kbd>M-,</kbd>, <kbd>M-.</kbd>,
<kbd>M-/</kbd></td>
<td>`cmd.pager.nextBuffer`, `cmd.pager.prevBuffer`,
`cmd.pager.prevSiblingBuffer`, `cmd.pager.nextSiblingBufer`,
`cmd.pager.parentBuffer`</td>
<td>Traverse the buffer tree.
<p>
`nextBuffer` and `prevBuffer` are the most intuitive, traversing the tree as if
it were a linked list.
<p>
`prevSiblingBuffer` and `nextSiblingBuffer` cycle through the buffers opened
from the same buffer.
<p>
Finally, `parentBuffer` always returns to the buffer the current buffer was
opened from, even if e.g. the user returns and opens another page "in between".
</td>
</tr>

<tr>
<td><kbd>M-c</kbd></td>
<td>`cmd.pager.enterCommand`</td>
<td>Directly enter a JavaScript command. Note that this interacts with
the pager, not the website being displayed.</td>
</tr>

<tr>
<td>None</td>
<td>`cmd.pager.searchForward`, `cmd.pager.searchBackward`</td>
<td>Search for a string in the current buffer, forwards or backwards.</td>
</tr>

<tr>
<td><kbd>/</kbd>, <kbd>?</kbd></td>
<td>`cmd.pager.isearchForward`, `cmd.pager.searchBackward`</td>
<td>Incremental-search for a string, highlighting the first result, forwards or
backwards.</td>
</tr>

<tr>
<td><kbd>n</kbd>, <kbd>N</kbd></td>
<td>`cmd.pager.searchNext`, `cmd.pager.searchPrev`</td>
<td>Jump to the nth (or if unspecified, first) next/previous search result.</td>
</tr>

<tr>
<td><kbd>c</kbd></td>
<td>`cmd.pager.peek`</td>
<td>Display a message of the current buffer's URL on the status line.</td>
</tr>

<tr>
<td><kbd>u</kbd></td>
<td>`cmd.pager.peekCursor`</td>
<td>Display a message of the URL or title under the cursor on the status line.
Multiple calls allow cycling through the two. (i.e. by default, press u once ->
title, press again -> URL)</td>
</tr>

<tr>
<td><kbd>su</kbd></td>
<td>`cmd.pager.showFullAlert`</td>
<td>Show the last alert inside the line editor. You can also view previous
ones using C-p or C-n.</td>
</tr>

<tr>
<td><kbd>M-y</kbd></td>
<td>`cmd.pager.copyURL`</td>
<td>Copy the current buffer's URL to the system clipboard.</td>
</tr>

<tr>
<td><kbd>yu</kbd></td>
<td>`cmd.pager.copyCursorLink`</td>
<td>Copy the link under the cursor to the system clipboard.</td>
</tr>

<tr>
<td><kbd>yI</kbd></td>
<td>`cmd.pager.copyCursorImage`</td>
<td>Copy the URL of the image under the cursor to the system clipboard.</td>
</tr>

<tr>
<td><kbd>M-p</kbd></td>
<td>`cmd.pager.gotoClipboardURL`</td>
<td>Go to the URL currently on the clipboard.</td>
</tr>

<tr>
<td><kbd>M-b</kbd></td>
<td>`cmd.pager.openBookmarks`</td>
<td>Open the bookmark file.</td>
</tr>

<tr>
<td><kbd>M-a</kbd></td>
<td>`cmd.pager.addBookmark`</td>
<td>Add the current page to your bookmarks.</td>
</tr>

</table>

### Buffer actions

Note: `n` in the following text refers to a number preceding the action.  e.g.
in `10gg`, n = 10.  If no preceding number is input, then it is left
unspecified.

<table>
<col width=20%><col width=35%><col width=45%>

<tr>
<th>Default key</th>
<th>Name</th>
<th>Function</th>
</tr>

<tr>
<td><kbd>j</kbd>, <kbd>k</kbd></td>
<td>`cmd.buffer.cursorUp`, `cmd.buffer.cursorDown`</td>
<td>Move the cursor upwards/downwards by n lines, or if n is unspecified, by
1.</td>
</tr>

<tr>
<td><kbd>h</kbd>, <kbd>l</kbd></td>
<td>`cmd.buffer.cursorLeft`, `cmd.buffer.cursorRight`</td>
<td>Move the cursor to the left/right by n cells, or if n is unspecified, by
1.</td>
</tr>

<tr>
<td><kbd>0</kbd>/<kbd>Home</kbd></td>
<td>`cmd.buffer.cursorLineBegin`</td>
<td>Move the cursor to the first cell of the line.</td>
</tr>

<tr>
<td><kbd>^</kbd></td>
<td>`cmd.buffer.cursorLineTextStart`</td>
<td>Move the cursor to the first non-blank character of the line.</td>
</tr>

<tr>
<td><kbd>&dollar;</kbd>/<kbd>End</kbd></td>
<td>`cmd.buffer.cursorLineEnd`</td>
<td>Move the cursor to the last cell of the line.</td>
</tr>

<tr>
<td><kbd>w</kbd>, <kbd>W</kbd></td>
<td>`cmd.buffer.cursorNextWord`, `cmd.buffer.cursorNextViWord`,
`cmd.buffer.cursorNextBigWord`</td>
<td>Move the cursor to the beginning of the next [word](#word-types).</td>
</tr>

<tr>
<td>None</td>
<td>`cmd.buffer.cursorPrevWord`, `cmd.buffer.cursorPrevViWord`,
`cmd.buffer.cursorPrevBigWord`</td>
<td>Move the cursor to the end of the previous [word](#word-types).</td>
</tr>

<tr>
<td><kbd>e</kbd>, <kbd>E</kbd></td>
<td>`cmd.buffer.cursorWordEnd`, `cmd.buffer.cursorViWordEnd`,
`cmd.buffer.cursorBigWordEnd`</td>
<td>Move the cursor to the end of the current [word](#word-types), or if already
there, to the end of the next word.</td>
</tr>

<tr>
<td><kbd>b</kbd>, <kbd>B</kbd></td>
<td>`cmd.buffer.cursorWordBegin`, `cmd.buffer.cursorViWordBegin`,
`cmd.buffer.cursorBigWordBegin`</td>
<td>Move the cursor to the beginning of the current [word](#word-types), or if
already there, to the end of the previous word.</td>
</tr>

<tr>
<td><kbd>[</kbd>, <kbd>]</kbd></td>
<td>`cmd.buffer.cursorPrevLink`, `cmd.buffer.cursorNextLink`</td>
<td>Move the cursor to the end/beginning of the previous/next clickable
element (e.g. link, input field, etc).</td>
</tr>

<tr>
<td><kbd>{</kbd>, <kbd>}</kbd></td>
<td>`cmd.buffer.cursorPrevParagraph`, `cmd.buffer.cursorNextParagraph`</td>
<td>Move the cursor to the end/beginning of the nth previous/next
paragraph.</td>
</tr>

<tr>
<td>None</td>
<td>`cmd.buffer.cursorRevNthLink`</td>
<td>Move the cursor to the nth link of the document, counting backwards
from the document's last line.</td>
</tr>

<tr>
<td>None</td>
<td>`cmd.buffer.cursorNthLink`</td>
<td>Move the cursor to the nth link of the document.</td>
</tr>

<tr>
<td><kbd>C-b</kbd>, <kbd>C-f</kbd>, <kbd>zH</kbd>, <kbd>zL</kbd></td>
<td>`cmd.buffer.pageUp`, `cmd.buffer.pageDown`, `cmd.buffer.pageLeft`,
`cmd.buffer.pageRight`</td>
<td>Scroll up/down/left/right by n pages, or if n is unspecified, by one
page.</td>
</tr>

<tr>
<td><kbd>C-u</kbd>, <kbd>C-d</kbd></td>
<td>`cmd.buffer.halfPageUp`, `cmd.buffer.halfPageDown`, `cmd.buffer.halfPageLeft`,
`cmd.buffer.halfPageUp`</td>
<td>Scroll up/down/left/right by n half pages, or if n is unspecified, by one
page.</td>
</tr>

<tr>
<td><kbd>K</kbd>/<kbd>C-y</kbd>, <kbd>J</kbd>/<kbd>C-e</kbd>,
<kbd>zh</kbd>, <kbd>zl</kbd></td>
<td>`cmd.buffer.scrollUp`, `cmd.buffer.scrollDown`, `cmd.buffer.scrollLeft`,
`cmd.buffer.scrollRight`</td>
<td>Scroll up/down/left/right by n lines, or if n is unspecified, by one
line.</td>
</tr>

<tr>
<td><kbd>Enter</kbd>/<kbd>Return</kbd></td>
<td>`cmd.buffer.click`</td>
<td>Click the HTML element currently under the cursor.</td>
</tr>

<tr>
<td><kbd>I</kbd></td>
<td>`cmd.buffer.viewImage`</td>
<td>View the image currently under the cursor in an external
viewer.</td>
</tr>

<tr>
<td><kbd>R</kbd></td>
<td>`cmd.buffer.reshape`</td>
<td>Reshape the current buffer (=render the current page anew.) Useful
if the layout is not updating even though it should have.</td>
</tr>

<tr>
<td><kbd>r</kbd></td>
<td>`cmd.buffer.redraw`</td>
<td>Redraw screen contents. Useful if something messed up the display.</td>
</tr>

<tr>
<td>None (see gotoLineOrStart/End instead)</td>
<td>`cmd.buffer.cursorFirstLine`, `cmd.buffer.cursorLastLine`</td>
<td>Move to the beginning/end in the buffer.</td>
</tr>

<tr>
<td><kbd>H</kbd></td>
<td>`cmd.buffer.cursorTop`</td>
<td>Move to the first line on the screen. (Equivalent to H in vi.)</td>
</tr>

<tr>
<td><kbd>M</kbd></td>
<td>`cmd.buffer.cursorMiddle`</td>
<td>Move to the line in the middle of the screen. (Equivalent to M in vi.)</td>
</tr>

<tr>
<td><kbd>L</kbd></td>
<td>`cmd.buffer.cursorBottom`</td>
<td>Move to the last line on the screen. (Equivalent to L in vi.)</td>
</tr>

<tr>
<td><kbd>zt</kbd>, <kbd>z Return</kbd>,
<kbd>zz</kbd>, <kbd>z.</kbd>,
<kbd>zb</kbd>, <kbd>z-</kbd></td>
<td>`cmd.buffer.raisePage`, `cmd.buffer.raisePageBegin`,
`cmd.buffer.centerLine`, `cmd.buffer.centerLineBegin`,
`cmd.buffer.lowerPage`, `cmd.buffer.lowerPageBegin`</td>
<td>If n is specified, move cursor to line n. Then,

* `raisePage` scrolls down so that the cursor is on the top line of the screen.
  (vi `z<CR>`, vim `zt`.)
* `centerLine` shifts the screen so that the cursor is in the middle of the
  screen. (vi `z.`, vim `zz`.)
* `lowerPage` scrolls up so that the cursor is on the bottom line of the screen.
  (vi `z-`, vim `zb`.)

The -`Begin` variants also move the cursor to the line's first non-blank
character, as the variants originating from vi do.
</td>
</tr>

<tr>
<td><kbd>z+</kbd></td>
<td>`cmd.buffer.nextPageBegin`</td>
<td>If n is specified, move to the screen before the nth line and raise the page.
Otherwise, go to the previous screen's last line and raise the page.</td>
</tr>

<tr>
<td><kbd>z^</kbd></td>
<td>`cmd.buffer.previousPageBegin`</td>
<td>If n is specified, move to the screen before the nth line and raise the
page.  Otherwise, go to the previous screen's last line and raise the page.</td>
</tr>

<tr>
<td><kbd>g0</kbd>, <kbd>gc</kbd>, <kbd>g$</kbd></td>
<td>`cmd.buffer.cursorLeftEdge`, `cmd.buffer.cursorMiddleColumn`,
`cmd.buffer.cursorRightEdge`</td>
<td>Move to the first/middle/last column on the screen.</td>
</tr>

<tr>
<td>None</td>
<td>`cmd.buffer.centerColumn`</td>
<td>Center screen around the current column. (w3m `Z`.)</td>
</tr>

<tr>
<td><kbd>gg</kbd>, <kbd>G</kbd></td>
<td>`cmd.buffer.gotoLineOrStart`, `cmd.buffer.gotoLineOrEnd`</td>
<td>If n is specified, jump to line n. Otherwise, jump to the start/end of the
page.</td>
</tr>

<tr>
<td><kbd>&vert;</kbd>, None</td>
<td>`cmd.buffer.gotoColumnOrBegin`, `cmd.buffer.gotoColumnOrEnd`</td>
<td>If n is specified, jump to column n of the current line.
Otherwise, jump to the first/last column.</td>
</tr>

<tr>
<td><kbd>m</kbd></td>
<td>`cmd.buffer.mark`</td>
<td>Wait for a character `x` and then set a mark with the ID `x`.</td>
</tr>

<tr>
<td><kbd>&grave;</kbd>, <kbd>'</kbd></td>
<td>`cmd.buffer.gotoMark`, `cmd.buffer.gotoMarkY`</td>
<td>Wait for a character `x` and then jump to the mark with the ID `x` (if it
exists on the page).
<p>
`gotoMark` sets both the X and Y positions; gotoMarkY only sets the Y
position.</td>
</tr>

<tr>
<td><kbd>:</kbd></td>
<td>`cmd.buffer.markURL`</td>
<td>Convert URL-like strings to anchors on the current page.</td>
</tr>

<tr>
<td><kbd>s Return</kbd></td>
<td>`cmd.buffer.saveLink`</td>
<td>Save resource from the URL pointed to by the cursor to the disk.</td>
</tr>

<tr>
<td><kbd>sS</kbd></td>
<td>`cmd.buffer.saveSource`</td>
<td>Save the source of the current buffer to the disk.</td>
</tr>

<tr>
<td><kbd>sI</kbd></td>
<td>`cmd.buffer.saveImage`</td>
<td>Save the image currently under the cursor.</td>
</tr>

<tr>
<td><kbd>M-i</kbd></td>
<td>`cmd.buffer.toggleImages`</td>
<td>Toggle display of images in the current buffer.</td>
</tr>

<tr>
<td><kbd>M-j</kbd></td>
<td>`cmd.buffer.toggleScripting`</td>
<td>Reload the current buffer with scripting enabled/disabled.</td>
</tr>

<tr>
<td><kbd>M-k</kbd></td>
<td>`cmd.buffer.toggleCookie`</td>
<td>Reload the current buffer with cookies enabled/disabled.</td>
</tr>

</table>


### Line-editing actions

<table>
<col width=20%><col width=30%><col width=50%>

<tr>
<th>Default key</th>
<th>Name</th>
<th>Function</th>
</tr>

<tr>
<td><kbd>Return</kbd></td>
<td>`cmd.line.submit`</td>
<td>Submit the line.</td>
</tr>

<tr>
<td><kbd>C-c</kbd></td>
<td>`cmd.line.cancel`</td>
<td>Cancel the current operation.</td>
</tr>

<tr>
<td><kbd>C-h</kbd>, <kbd>C-d</kbd></td>
<td>`cmd.line.backspace`, `cmd.line.delete`</td>
<td>Delete character before (backspace)/after (delete) the cursor.</td>
</tr>

<tr>
<td><kbd>C-u</kbd>, <kbd>C-k</kbd></td>
<td>`cmd.line.clear`, `cmd.line.kill`</td>
<td>Delete text before (clear)/after (kill) the cursor.</td>
</tr>

<tr>
<td><kbd>C-w</kbd>, <kbd>M-d</kbd></td>
<td>`cmd.line.clearWord`, `cmd.line.killWord`</td>
<td>Delete word before (clear)/after (kill) the cursor.</td>
</tr>

<tr>
<td><kbd>C-b</kbd>, <kbd>C-f</kbd></td>
<td>`cmd.line.backward`, `cmd.line.forward`</td>
<td>Move cursor backward/forward by one character.</td>
</tr>

<tr>
<td><kbd>M-b</kbd>, <kbd>M-f</kbd></td>
<td>`cmd.line.prevWord`, `cmd.line.nextWord`</td>
<td>Move cursor to the previous/next word by one character</td>
</tr>

<tr>
<td><kbd>C-a</kbd>/<kbd>Home</kbd>, <kbd>C-e</kbd>/<kbd>End</kbd></td>
<td>`cmd.line.begin`, `cmd.line.end`</td>
<td>Move cursor to the beginning/end of the line.</td>
</tr>

<tr>
<td><kbd>C-v</kbd></td>
<td>`cmd.line.escape`</td>
<td>Ignore keybindings for next character.</td>
</tr>

<tr>
<td><kbd>C-p</kbd>, <kbd>C-n</kbd></td>
<td>`cmd.line.prevHist`, `cmd.line.nextHist`</td>
<td>Jump to the previous/next history entry</td>
</tr>

</table>

Note: to facilitate URL editing, the line editor has a different definition
of what a word is than the pager. For the line editor, a word is either a
sequence of alphanumeric characters, or any single non-alphanumeric
character. (This means that e.g. `https://` consists of four words: `https`,
`:`, `/` and `/`.)

```Examples:
# Control+A moves the cursor to the beginning of the line.
'C-a' = 'cmd.line.begin'

# Escape+D deletes everything after the cursor until it reaches a word-breaking
# character.
'M-d' = 'cmd.line.killWord'
```

## Appendix

### Regex handling

Regular expressions are currently handled using the libregexp library
from QuickJS.  This means that all regular expressions work as in
JavaScript.

There are two different modes of regex preprocessing in Chawan: "search"
mode and "match" mode.  Match mode is used for configurations (meaning
in all values in this document described as "regex").  Search mode is
used for the on-page search function (using searchForward/isearchForward
etc.)

#### Match mode

Regular expressions are assumed to be exact matches, except when they
start with a caret (^) sign or end with an unescaped dollar ($) sign.

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
* `$CHA_LIBEXEC_DIR`: the directory for all executables Chawan uses
  for operation. By default, this is `$CHA_BIN_DIR/../libexec/chawan`.
* `$CHA_DIR`: the configuration directory.  (This can also be set
  by the user; see the top section for details.)

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

<!-- MANON

## See also

**cha**(1) **cha-api**(7)
MANOFF -->
