<!-- CHA-MAILCAP 5 -->

# Mailcap

By default, Chawan's buffers only handle HTML and plain text.
The *mailcap* file can be used to view other file formats using external
commands, or to convert them to HTML/plain text before displaying them
in Chawan.

Note that Chawan's default mime.types file only recognizes a few file
extensions, which may result in your entries not being executed
if your system lacks an /etc/mime.types file.  Please consult
[**cha-mime.types**](mime.types.md)(5) for details.

For an exact description of the mailcap format, see
[RFC 1524](https://www.rfc-editor.org/rfc/rfc1524).

## Search path

The search path for mailcap files is set by the configuration variable
`external.mailcap`.  This matches the recommended path in the RFC:

```
$HOME/.mailcap:/etc/mailcap:/usr/etc/mailcap:/usr/local/etc/mailcap
```

By default, mailcap entries are only executed if the user types `r` (run)
after the prompt.  Other options are to view the file with `t` (text), or
to save the file with `s`.

If a capital letter is typed (e.g. shift + `R`), then a corresponding entry
is appended to `external.auto-mailcap` (default: `~/.chawan/mailcap`, or
`~/.config/chawan/mailcap` with XDG basedirs).  `(T)ext` and `(S)ave`
may also be used to append entries corresponding to the other display
options.

Entries in auto-mailcap are automatically executed, so it is recommended
to add your Chawan-specific entries there (or just set it to your
personal mailcap file).

## Format

Chawan adheres to the format described in RFC 1524, with a few extensions.

`text/html` and `text/plain` entries are ignored.

### Templating

The command part of entries may include template strings which are
substituted by the browser at execution.

Templates do not have to be quoted; Chawan quotes them automatically.
(This works with $(command substitutions) as well.)  However, other
software may misbehave on such templates, so it may be better to assign
them to a variable first, e.g.

```
text/x-example; s=%s cat "$s"; copiousoutput
```

Following templates are supported:

* `%s` expands to the path.  Specifying `%s` forces download of the
  external resource *before* the entry is executed.  If `%s` is not
  specified, the resource is instead piped to standard input.  (In this
  case, `needsterminal` does not apply.)

* `%t` expands to the content type.  Named content type fields can also
  be specified with the syntax `%{charset}`.  For example, in

  ```
  text/html; charset=utf-8
  ```

  `%t` would expand to the above string, while `%{charset}` would expand
  to "utf-8".

* Non-standard templates for the resource's original URL: `%u` (from
  Netscape) expands to the original URL of the resource, `%h` (from w3mmee)
  expands to the hostname without the port, `%H` expands to the hostname
  including the port, and `%?` (from w3mmee) expands to the query string
  including the question mark.

  (w3mmee did not actually include the question mark in `%?`.  However,
  that design could not express the difference between the empty query
  string and the null query string, so it has been changed in Chawan.)

### Fields

Following fields are recognized.

* When the `test` named field is specified, the mailcap entry is only used
  if the test command returns 0.  For example, you can restrict entries
  that require X11 as follows:

  ```
  image; feh -; test=test -n "$DISPLAY"
  ```

  Warning: `%s` does not work with `test`.  `test` named fields with a `%s`
  template are skipped, and no data is piped into `test` commands.

* `copiousoutput` makes Chawan redirect the output of the external
  command's output into a new buffer.  If either `x-htmloutput` or
  `x-ansioutput` is defined too, then `copiousoutput` is ignored.

* `needsterminal` hands over control of the terminal to the command
  while it is running.  It does nothing if one of `copiousoutput`,
  `x-ansioutput`, `x-saveoutput` or `x-htmloutput` is specified.

* `nametemplate` provides a specific template for the temporary file
  created when `%s` is specified.  See the RFC for details.

* `x-htmloutput` (from w3m) behaves the same as `copiousoutput`, but makes
  Chawan interpret the command's output as HTML.

* `x-ansioutput` pipes the output through the "text/x-ansi" content type
  handler, so that ANSI colors, formatting, etc. are displayed correctly.

* `x-saveoutput` prompts the user to save the entry's output in a file.

* `x-needsstyle` forces CSS to be processed for the specific type, even
  if styling is disabled in the config.  Only useful when combined with
  `x-htmloutput`.  (Also see the `-cha-content-type` media query in
  [**cha-css**](css.md)(7).)

* `x-needsimage` forces images to be displayed in `x-htmloutput`, even if
  images are disabled.

* `x-type` (from w3mmee) specifies a MIME type substitution.  The command
  part is interpreted as a MIME type (without template expansion) which is
  used instead of the original type.  Such entries are only respected in
  `external.auto-mailcap`.

  Entries with `x-type` also match text/plain and text/html documents
  (which are normally excluded from mailcap).  However, `x-type` does not
  apply if the content type was forced (e.g. using the `-T` flag).

  (Note: `x-type` is experimental.  Future changes to its semantics are
  to be expected.)

* `x-match` (from w3mmee) restricts the entry's URL to the specified regex.
  `x-nc-match` is the same, but it is case-insensitive.  For example,
  `x-match=https?://example\.org/.*` restricts the entry to example.org
  (note the backslash.)

  When one of these fields is present together with `test`, the result is
  ANDed together.

* `x-netpath` (from w3mmee) restricts the entry to URIs that match the
  `net_path` production of RFC 2396.  In other words, the URI must have an
  authority (hostname etc.), so e.g. `example://blah/path` is matched,
  while `example:/path` isn't.

  For schemes other than `file`, two slashes after the colon signify
  a `net_path`.  `file:///path` is a special case: it looks like a
  `net_path`, but it isn't one.  (This is inherited from the WHATWG URL
  standard.)

## Examples

To automatically execute these entries, place them in `~/.chawan/mailcap`
(or `~/.config/chawan/mailcap` if you use XDG basedirs).  Alternatively,
if you already have a mailcap file to share with other programs, you can
set `external.auto-mailcap` to `~/.mailcap`.

```
# Note: these examples require an entry in mime.types that sets e.g. md as
# the markdown content type.

# Handle markdown files using pandoc.
text/markdown; pandoc - -f markdown -t html -o -; x-htmloutput

# Show syntax highlighting for JavaScript source files using bat.
text/javascript; bat -f -l es6 --file-name %u -; x-ansioutput

# Play music using mpv, and hand over control of the terminal until mpv exits.
audio/*; mpv -; needsterminal

# Play videos using mpv in the background, redirecting its standard output
# and standard error to /dev/null.
video/*; mpv -

# Open docx files using LibreOffice Writer.
application/vnd.openxmlformats-officedocument.wordprocessingml.document; lowriter %s

# Display manpages using pandoc. (Make sure the mime type matches the one
# set in your mime.types file for extensions .1, .2, .3, ...)
application/x-troff-man; pandoc - -f man -t html -o -; x-htmloutput

# epub -> HTML using pandoc. (Again, don't forget to adjust mime.types.)
# We set http_proxy to keep it from downloading whatever through http/s.
application/epub+zip; http_proxy=localhost:0 pandoc - -f epub \
--embed-resources --standalone; x-htmloutput

# Hex viewer.  Usage: alias chadump='cha -Ttext/x-hexdump'
# (Uses GNU-specific flags, adjust as needed on other systems.)
text/x-hexdump; od -w12 -A x -t x1z -v; copiousoutput

# Following entry will be ignored, as text/html is supported natively by Chawan.
text/html; cha -dT text/html -I %{charset}; copiousoutput
```

## See also

[**cha**](cha.md)(1)
