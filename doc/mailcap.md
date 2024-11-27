<!-- MANON
% cha-mailcap(5) | Mailcap support in Chawan
MANOFF -->

# Mailcap

Chawan's buffers can only handle HTML and plain text. To make Chawan recognize
other file formats, the mailcap file format can be used.

Note that Chawan's default mime.types file only recognizes a few file
extensions, which may result in your entries not being executed.
Please consult the <!-- MANOFF -->[mime.types](mime.types.md)<!-- MANON -->
<!-- MANON **cha-mime.types**(5) MANOFF --> documentation for details.

For an exact description of the mailcap format, see
[RFC 1524](https://www.rfc-editor.org/rfc/rfc1524).

## Search path

The search path for mailcap files can be overridden using the configuration
variable `external.mailcap`.

By default, the only file checked by Chawan is `$HOME/.mailcap`.

In the past, the full path from the specification was used. This was changed
because mailcap files shipped with various systems are usually incompatible
with the assumptions Chawan makes about mailcap file contents. You can restore
the old/standard-recommended behavior by adding this to your config.toml:

```toml
[external]
mailcap = [
	"~/.mailcap",
	"/etc/mailcap",
	"/usr/etc/mailcap",
	"/usr/local/etc/mailcap"
]
```

## Format

Chawan tries to adhere to the format described in RFC 1524, with a few
extensions.

### Templating

`%s`, `%t`, and named content type fields like `%{charset}` work as described in
the standard.

If no quoting is applied, Chawan will quote the templates automatically. (This
works with $(command substitutions) as well.)

DEPRECATED

The non-standard template %u may be specified to get the original URL of the
resource. (As far as I can tell, this is a Netscape extension that may or may
not be compatible with other implementations.)

Use of this is not recommended; instead, use the `$MAILCAP_URL` environment
variable which is set to the same value before the execution of every mailcap
command.

### Fields

The `test`, `nametemplate`, `needsterminal` and `copiousoutput` fields are
recognized. Additionally, the non-standard `x-htmloutput` and `x-ansioutput`
extension fields are recognized too.

* When the `test` named field is specified, the mailcap entry is only used
  if the test command returns 0.  
  Warning: as of now, `%s` does not work with `test`; `test` named fields with a
  `%s` template are skipped. Additionally, no data is piped into `test` either.
* `copiousoutput` makes Chawan redirect the output of the external command
  into a new buffer. If either x-htmloutput or x-ansioutput is defined too, then
  it is ignored.
* The `x-htmloutput` extension field behaves the same as `copiousoutput`,
  but makes Chawan interpret the command's output as HTML.
* `x-ansioutput` pipes the output through the "text/x-ansi" content type
  handler, so that ANSI colors, formatting, etc. are displayed correctly.
* `x-needsstyle` forces CSS to be processed for the specific type, even if
  styling is disabled in the config. Only useful when combined with
  `x-htmloutput`.
* `needsterminal` hands over control of the terminal to the command while
  it is running. Note: as of now, `needsterminal` does nothing if either
  `copiousoutput` or `x-htmloutput` is specified.
* For a description of `nametemplate`, see the RFC. Note however, that it does
  not work with test (since %s is not supported there).

### Environment variables

As noted above, the `$MAILCAP_URL` variable is set to the URL of the target
resource before the execution of the mailcap command. Backwards compatibility
with mailcap agents that do not support this variable can be achieved through
shell substitution, e.g. `${MAILCAP_URL:-string for when it is unsupported}`.

Note that it is not recommended to set `%s` as the fallback, because it
will force Chawan to download the entire file before displaying it even if
it could have been piped into the command.

## Note

Entries with a content type of text/html or text/plain are ignored.

Content types that do not appear in mailcap files are handled as text files in
case they start with `text/`. Otherwise, they prompt the user to save the file
to the disk.

## Examples

```
# Note: these examples require an entry in mime.types that sets e.g. md as
# the markdown content type.

# Handle markdown files using pandoc.
text/markdown; pandoc - -f markdown -t html -o -; x-htmloutput

# Show syntax highlighting for JavaScript source files using bat.
text/javascript; bat -f -l es6 --file-name ${MAILCAP_URL:-STDIN} -; x-ansioutput

# Play music using mpv, and hand over control of the terminal until mpv exits.
audio/*; mpv -; needsterminal

# Play videos using mpv in the background, redirecting its standard output
# and standard error to /dev/null.
video/*; mpv -

# Open docx files using LibreOffice Writer.
application/vnd.openxmlformats-officedocument.wordprocessingml.document; lowriter %s
# (Wow that was ugly.)

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
