<!-- CHA-PROTOCOLS 7 -->

# Protocols

Chawan supports downloading resources from various protocols: HTTP, FTP,
SFTP, Gopher, Gemini, Spartan, and Finger.  Details on these protocols,
and information on how users can add support to their preferred
protocols is outlined in this document.

You can find network adapters in the source distribution's
`adapter/protocol` directory.  For protocol-specific file formats (like
gemtext or gopher directories) you will also find an appropriate HTML
converter in `adapter/format` - note that these are ultimately compiled
into a single `tohtml` program that dispatches based on its `argv[0]`.

<!-- MANOFF -->
**Table of contents**

* [OpenSSL-based adapters](#openssl-based-adapters)
	- [HTTP](#http)
	- [SFTP](#sftp)
	- [Gemini](#gemini)
* [FTP](#ftp)
* [Shell-based adapters](#shell-based-adapters)
	- [Gopher](#gopher)
	- [Finger](#finger)
	- [Spartan](#spartan)
* [Local schemes: file:, man:, cgi-bin:](#local-schemes-file-man-cgi-bin)
* [Internal schemes: stream:, cache:, data:, about:](#internal-schemes-stream-cache-data-about)
* [Custom protocols](#custom-protocols)

<!-- MANON -->

## OpenSSL-based adapters

The HTTP(S), SFTP, and Gemini modules all depend on OpenSSL.  This
is a huge library, and linking it separately with each adapter would
result in enormous code bloat in static builds.

Therefore, these modules are compiled into a single binary.  The entry
point can be found at `adapter/protocol/ssl.nim`.

### HTTP

The HTTP(S) adapter supports HTTP/1.1 with arbitrary headers and POST
data, is able to use passed userinfo data (Basic authentication), and
returns all headers and response body it receives without exception.

Deflate decompression with gzip and zlib headers is supported.
(Accept-Encoding: gzip, deflate.)  This is based on a modified version
of the public domain tinfl.h decompressor by Rich Geldreich.

Brotli decompression (Accept-Encoding: br) is supported using the
decoder provided by the reference implementation.

The `bonus` directory includes two alternative HTTP clients:

* curlhttp; this is the old HTTP client based on libcurl.  It can be
  built using curl-impersonate; see [README.md](../bonus/README.md) in
  the bonus/ directory for details.

* libfetch-http: based on FreeBSD libfetch.  It is mostly a proof of
  concept, as FreeBSD libfetch HTTP support is very limited; in
  particular, it does not support arbitrary HTTP headers, so e.g.
  cookies will not work.

### SFTP

The SFTP adapter wraps libssh2.  It works for me, but YMMV.

A slight usability issue is that if an IdentityFile declaration is found
in your ssh config, it will prompt for the identity file password, but
there is no way to tell whether it is really asking for that (or just
regular password auth).  Also, settings covered by the Match field are
ignored.

The adapter does not have a way to register new known hosts, so you have
to first connect to new hosts with the regular `sftp` command before
opening them in Chawan.

### Gemini

Currently, the Gemini adapter does not support sites that require
private key authentication.  Otherwise, it should work OK.

gmi2html is its companion program to convert the `text/gemini` file
format to HTML.

## FTP

Chawan supports FTP passive mode browsing and downloads.

Directory listings return the `text/x-dirlist` content type, which is
parsed by `dirlist2html` (and also used by the `file:` handler).
This assumes UNIX output style, and will probably break horribly on
receiving anything else.

## Shell-based adapters

Following protocols are simple enough to have adapters implemented as
shell scripts.  As such, they are good starting points for understanding
Chawan's protocol adapter system.

To open TCP connections in a portable manner, these scripts use a very
limited `nc` clone installed in `$CHA_LIBEXEC_DIR`.

### Gopher

Support for the Gopher protocol is implemented as a shell script, using
the `nc` tool in the libexec directory (a very limited netcat clone).
Gopher directories are returned with the `text/gopher` type, and
gopher2html takes care of converting this to HTML.

Gopher selector types are converted to MIME types when possible;
however, this is very limited, as most of them (like `s` sound, or `I`
image) cannot be unambiguously converted without some other sniffing
method.  Chawan will fall back to extension-based detection in these
cases, and in the worst case may end up with `application/octet-stream`.

### Finger

Finger is supported through the `finger` shell script, using the same
`nc` clone as Gopher.  It is probably the simplest protocol of all.

The URL scheme is a simplified imitation of the one accepted by Lynx.

### Spartan

Spartan is a protocol similar to Gemini, but without TLS.  It is
supported through the `spartan` shell script, and like Finger, it uses
Chawan's `nc` to make requests.

Spartan has the very strange property of extending gemtext with a
protocol-specific line type.  This is implemented as a sed filter for
gemtext outputs in the CGI script (in other words, no modification to
gmi2html was done to support this).

## Local schemes: file:, man:, cgi-bin:

While these are not necessarily *protocols*, they are implemented
similarly to the protocols listed above (and thus can also be replaced,
if the user wishes; see below).

`file:` loads a file from the local filesystem.  In case of directories,
it shows the directory listing using `dirlist2html` like FTP.

`man:`, `man-k:` and `man-l:` are wrappers around the commands `man`,
`man -k` and `man -l`.  These look up man pages using `/usr/bin/man`
and turn on-page references into links.  A wrapper command `mancha`
also exists; this has an interface similar to `man`.  (This used to be
based on w3mman2html.cgi, but it has been rewritten as a standalone Nim
program.)

`cgi-bin:` executes a local CGI script.  This protocol is useful in cases
where you want to wrap an external program (or a personal script), but do
not need a custom URI scheme for it.  In fact, it simply maps to the
browsecap entry

```
cgi-bin; %s%?; cgioutput
```

See [**cha-cgi**](cgi.md)(5) for details.

## Internal schemes: stream:, cache:, data:, about:

These protocols are implemented directly in Chawan.  Technically, it *is*
possible to replace them, but it is highly recommended that you don't.

`stream:` is used for streams returned by external programs.  It differs
from `cgi-bin:` in that it does not cooperate with the external process,
and that the loader does not keep track of where the stream originally
comes from.  Therefore it is suitable for reading in the output of
mailcap entries, or for turning stdin into a URL.

It is not possible to reload `stream:` URLs.  To support rewinding and
"view source", the output of `stream:`'s is stored in a cache file until
the buffer is discarded.

`cache:` is not something an end user would normally see; it's used for
rewinding or re-interpreting streams already downloaded.

Caching works differently than in most other browsers; files are
deterministically loaded from the cache upon certain actions, and from the
network upon others, but neither is used as a fallback to the other.

`data:` decodes a data URL as defined in RFC 2397.  This cannot be
implemented as CGI because data URLs can get so long that they no longer
fit into the environment.

`about:` is inside the loader because some pages it offers require
information about the browser's internal state (downloads in particular).
The following about pages are available: `about:chawan`, `about:blank`,
`about:license`, `about:downloads`.

## Custom protocols

The `cha` binary itself does not know much about the protocols
listed above; instead, it loads these by looking up built-in browsecap
definitions, converting them to HTML using mailcap when necessary.  See
[**cha-cgi**](cgi.md)(5) and [**cha-mailcap**](mailcap.md)(5) for details.

The default handlers for the protocols listed above can also be overridden
using browsecap.  This way, any library or program (in any programming
language) that can retrieve and output text through a certain protocol can
be combined with Chawan.

For example, consider the browsecap definition of `finger`:

```
finger/get;	/cgi-bin/finger %h %p %s;	cgioutput; netpath
```

This commands Chawan to load the `finger` CGI script, passing the hostname
as the first parameter, the port as the second (note: this is usually the
empty string), and the URI path as the third.  "cgioutput" means that this
is a CGI script; "netpath" means that the protocol should have a hostname
(so `finger:/blah` is not accepted, only `finger://example.org/blah`).

The script uses these arguments to construct an appropriate `nc`
command that fetches the specified `finger:` URL; it prints the header
'Content-Type: text/plain' to the output, then an empty line, then the
body of the retrieved resource.  If an error is encountered, it prints
a `Cha-Control` header with an error code and a specific error message
instead.

### Adding a new protocol

Here we will add a protocol called "cowsay", so that the URL cowsay:text
prints the output of `cowsay text` after a second of waiting.

Note: following assumes you put your `config.toml` in `~/.chawan`.
If you are using XDG base directories (i.e. your `config.toml` is
in `~/.config/chawan`), substitute `~/.chawan/cgi-bin` with
`~/.config/chawan/cgi-bin`.

`mkdir -p ~/.chawan/cgi-bin`, and create a CGI script in
`~/.chawan/cgi-bin/cowsay.cgi`:

```sh
#!/bin/sh
# Signal to the browser that the connection has succeeded.  After this,
# Chawan will now "Downloading" instead of "Connecting".
printf 'Cha-Control: Connected\n'

sleep 1 # simulate a delay

# Status is a special header that signals the equivalent HTTP status code.
printf 'Status: 200\n' # HTTP OK

# ControlDone is only useful if you want to send remotely received headers
# (i.e. in an HTTP adapter).  With ControlDone sent, subsequent Cha-Control
# headers are not interpreted specially.
printf 'Cha-Control: ControlDone\n'

# As in HTTP, send an empty line before the body.
printf '\n'

# Print the body.  We take the path passed to the URL, which browsecap
# sets as the first parameter (%s).  This is URI-encoded, so we also run
# the urldec utility on it.
printf '%s\n' "$1" | "$CHA_LIBEXEC_DIR"/urldec | cowsay
```

Don't forget to set the executable bit, e.g.

```sh
chmod +x ~/.config/chawan/cgi-bin/cowsay.cgi
```

Finally, create a ".chawan/browsecap" (or ~/.config/chawan/browsecap)
with the following content:

```
cowsay;	/cgi-bin/cowsay.cgi %s; cgioutput; resource
```

Now try `cha cowsay:Hello,%20world.`.  If you did everything correctly,
it should wait one second, then print a cow saying "Hello, world.".

## See also

[**cha**](cha.md)(1), [**cha-cgi**](cgi.md)(5),
[**cha-mailcap**](mailcap.md)(5)
