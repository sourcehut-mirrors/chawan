<!-- MANON
% CHA-MAILCAP 5
MANOFF -->

# Mailcap

By default, Chawan's buffers only handle HTML and plain text. The
`mailcap` file can be used to view other file formats using external
commands, or to convert them to HTML/plain text before displaying them
in Chawan.

Note that Chawan's default mime.types file only recognizes a few file
extensions, which may result in your entries not being executed if your
system lacks an /etc/mime.types file.  Please consult
the <!-- MANOFF -->[mime.types](mime.types.md)<!-- MANON --> <!-- MANON **cha-mime.types**(5) MANOFF -->
documentation for details.

For an exact description of the mailcap format, see
[RFC 1524](https://www.rfc-editor.org/rfc/rfc1524).

## Search path

The search path for mailcap files is set by the configuration variable
`external.mailcap`. This matches the recommended path in the RFC:

```
$HOME/.mailcap:/etc/mailcap:/usr/etc/mailcap:/usr/local/etc/mailcap
```

By default, mailcap entries are only executed if the user types `r`
(run) after the prompt. Other options are to view the file with `t`
(text), or to save the file with `s`.

If a capital letter is typed (e.g. press shift and type `R`), then a
corresponding entry is appended to `external.auto-mailcap` (default:
`~/.chawan/auto.mailcap`, or `~/.config/chawan/auto.mailcap` with XDG
basedirs). `(T)ext` and `(S)ave` may also be used to append entries
corresponding to the other display options.

Entries in auto-mailcap are automatically executed, so it is recommended
to add your Chawan-specific entries there (or just set it to your
personal mailcap file).

## Format

Chawan adheres to the format described in RFC 1524, with a few
extensions.

Note that text/html and text/plain entries are ignored.

### Templating

`%s`, `%t`, and named content type fields like `%{charset}` work as
described in the standard.

If no quoting is applied, Chawan quotes the templates automatically.
(This works with $(command substitutions) as well.)  However, other software
may misbehave on such templates, so it may be better to assign them to
a variable first.

The non-standard template %u may be specified to get the original URL of
the resource.  This is a Netscape extension that may not be compatible
with other implementations.  As an alternative, the `$MAILCAP_URL`
environment variable is set to the same value.

### Fields

The `test`, `nametemplate`, `needsterminal` and `copiousoutput` fields
are recognized. The non-standard `x-htmloutput`, `x-ansioutput`,
`x-saveoutput` and `x-needsstyle` extension fields are also recognized.

* When the `test` named field is specified, the mailcap entry is only used
  if the test command returns 0.

  Warning: as of now, `%s` does not work with `test`; `test` named
  fields with a `%s` template are skipped, and no data is piped into
  `test` commands.

* `copiousoutput` makes Chawan redirect the output of the external
  command's output into a new buffer. If either x-htmloutput or
  x-ansioutput is defined too, then it is ignored.

* The `x-htmloutput` extension field behaves the same as
  `copiousoutput`, but makes Chawan interpret the command's output as
  HTML.

* `x-ansioutput` pipes the output through the "text/x-ansi" content
  type handler, so that ANSI colors, formatting, etc. are displayed
  correctly.

* `x-saveoutput` prompts the user to save the entry's output in a file.

* `x-needsstyle` forces CSS to be processed for the specific type, even
  if styling is disabled in the config. Only useful when combined with
  `x-htmloutput`.

* `x-needsimage` forces images to be displayed in `x-htmloutput`, even if
  images are disabled.

* `needsterminal` hands over control of the terminal to the command
  while it is running. Note: as of now, `needsterminal` does nothing if
  either `copiousoutput` or `x-htmloutput` is specified.

* For a description of `nametemplate`, see the RFC.

## Examples

I recommend placing entries in `~/.chawan/auto.mailcap` (or
`~/.config/chawan/auto.mailcap` if you use XDG basedirs).

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

# Following entry will be ignored, as text/html is supported natively by Chawan.
text/html; cha -dT text/html -I %{charset}; copiousoutput
```
<!-- MANON
## See also

**cha**(1)
MANOFF -->
