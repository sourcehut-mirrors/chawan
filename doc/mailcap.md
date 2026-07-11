<!-- CHA-MAILCAP 5 -->

# Mailcap

By default, Chawan's buffers only handle HTML and plain text.
The *mailcap* file can be used to view other file formats using external
commands, or to convert them to HTML/plain text before displaying them
in Chawan.

In addition, the *browsecap* file fulfills a similar purpose for URI scheme
handling.  Browsecap can be used to override handling of any built-in
scheme, or to add custom handlers (e.g. [**mutt**](man:mutt(1))(1) for
*mailto*).  When combined with [**cha-cgi**](cgi.md)(5), *browsecap* also
enables extending Chawan with user-specified schemes.

(*browsecap* is a more capable replacement for
[**cha-urimethodmap**](urimethodmap.md)(5); the latter is deprecated.)

Note that Chawan's default mime.types file only recognizes a few file
extensions, which may result in your entries not being executed
if your system lacks an /etc/mime.types file.  Please consult
[**cha-mime.types**](mime.types.md)(5) for details.

For an exact description of the mailcap format, see
[RFC 1524](https://www.rfc-editor.org/rfc/rfc1524).

Browsecap is not standardized.  The semantics are derived from
[w3mmee](https://pub.ks-and-ks.ne.jp/prog/w3mmee/config.shtml.en#mailcap_enhancement),
but the two do not necessarily match in every aspect.

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

For browsecap, there is only an automatic variant so far.

## Format

Chawan adheres to the format described in RFC 1524, with a few extensions.

`text/html` and `text/plain` entries are ignored.

In browsecap, the MIME type field is treated as *protocol*/*method*.
For example, `http/get` dispatches to GET requests to an HTTP scheme,
`ftp/post` to POST requests to an FTP scheme, and `https/*` to all HTTPS
schemes.

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

  In browsecap, `%s` expands to the path segment of the URI instead.

* `%t` expands to the content type.  Named content type fields can also
  be specified with the syntax `%{charset}`.  For example, in

  ```
  text/html; charset=utf-8
  ```

  `%t` would expand to the above string, while `%{charset}` would expand
  to "utf-8".

  In browsecap, `%t` expands to *protocol*/*method*, where the *method*
  part is typically upper-cased.

* Non-standard templates for the resource's original URL: `%u` (from
  Netscape) expands to the original URL of the resource, `%h` (from w3mmee)
  expands to the hostname without the port, `%H` expands to the hostname
  including the port, and `%?` (from w3mmee) expands to the query string
  including the question mark.

  (w3mmee did not actually include the question mark in `%?`, but this
  was changed in Chawan because the other design could not express the
  difference between the empty query string and the null query string.)

### Fields

Following fields are recognized.

* Entries with the `test` named field are only used if the test command
  exits with 0.  For example, you can restrict entries that require X11 as
  follows:

  ```
  image; feh -; test=test -n "$DISPLAY"
  ```

  Note: entries with a `test` named field that include `%s` are skipped,
  and no data is piped into `test` commands.  (The RFC does not specify
  how this should work, but the alternative behavior cannot be efficiently
  implemented in a browser.)

* `copiousoutput` redirects the external command's output into a new
  buffer.  If either `x-htmloutput` or `x-ansioutput` is defined too, then
  `copiousoutput` is ignored.

* `needsterminal` hands over control of the terminal to the command
  while it is running.  It does nothing if one of `copiousoutput`,
  `x-ansioutput`, `x-saveoutput` or `x-htmloutput` is specified.

* `nametemplate` provides a specific template for the temporary file
  created when `%s` is specified.  See the RFC for details.
  This option has no effect in browsecap.

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
  part is interpreted as a MIME type after template expansion, which is
  used instead of the original type.  Such entries are only respected in
  `external.auto-mailcap`.

  `x-type` has a higher priority than other entries, and applies even to
  text/plain and text/html documents (which are normally excluded from
  mailcap).  However, `x-type` entries do not apply if the content type
  was forced (e.g. using the `-T` flag).

  (Note: `x-type` is experimental.  Future changes to its semantics are
  to be expected.)

* `x-match` (from w3mmee) restricts an entry's URI to the specified regex.
  `x-nc-match` is the same, but it is case-insensitive.  For example,
  `x-match=https?://example\.org/.*` restricts the entry to example.org
  (note the backslash).

  When one of these fields is present together with `test`, the result is
  ANDed together.

* `x-uri` (from w3mmee) substitutes matching URIs with the URI specified
  inside the command field after template expansion.  Like `x-type`, this
  does not execute a shell command.  `x-uri` entries are only accepted in
  `external.auto-browsecap`.

  Unlike in w3mmee, `x-uri` does not actually redirect to the other URL;
  instead, it transparently rewrites it in the background.

* `x-resource` must be used in combination with `x-uri` or `x-cgioutput`.
  Such entries also apply to requests initiated by a buffer,
  e.g. downloading CSS, IMG tags, etc.

* `x-netpath` (from w3mmee) restricts an entry to URIs which follow the
  `net_path` production of [RFC 2396](https://www.ietf.org/rfc/rfc2396.txt).

  In practice, this means that the URI must start with two slashes and
  then follow with an *authority* (user, pass, host, port).  For example,
  `x-netpath` matches `proto://example.org/path`, but not `proto:/path`.

  The `file` scheme is special-cased such that it is never matched as
  `net_path`, even though it looks like one for legacy reasons.

* `x-cgioutput` is only accepted in `external.auto-browsecap`, and applies
  to all network requests.  The command part is interpreted as a CGI script
  like in urimethodmap.

  TODO: we should allow passing parameters here.

## Mailcap examples

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

## Browsecap examples

Place these entries in `~/.chawan/browsecap` (or `~/.config/chawan/browsecap`
if you use XDG basedirs).

```
# Use the `magnet.cgi' script to pass magnet links to Transmission.
# (`magnet.cgi' can be found in the `bonus/' directory.  You can also
# modify it to pass the links to your BitTorrent client of choice.)
magnet/*;	/cgi-bin/magnet.cgi?%s; x-cgioutput

# Open mailto: URIs using mutt.
# (This is the same as mailto/*; the trailing `/*' can be freely omitted.)
mailto;		mutt -- %s; needsterminal

# Open YouTube URLs with mpv.  (GET method only.)
https/get;	mpv -- %u; needsterminal; x-nc-match=https://youtube\.com/watch?v=.*
```

## See also

[**cha**](cha.md)(1)
