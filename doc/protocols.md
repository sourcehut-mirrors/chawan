<!-- MANON
% CHA-PROTOCOLS 7
MANOFF -->

# Protocols

Chawan supports downloading resources from various protocols: HTTP, FTP,
SFTP, Gopher, Gemini, Spartan, and Finger.  Details on these protocols,
and information on how users can add support to their preferred
protocols is outlined in this document.

You can find network adapters in the source distribution's
`adapter/protocol` directory.  For protocol-specific file formats (like
gemtext or gopher directories) you will also find an appropriate HTML
converter in `adapter/format`.

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
* [Local schemes: file:, man:](#local-schemes-file-man)
* [Internal schemes: cgi-bin:, stream:, cache:, data:, about:](#internal-schemes-cgi-bin-stream-cache-data-about)
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

The `bonus` directory contains two alternative HTTP clients:

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

## Local schemes: file:, man:

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

## Internal schemes: cgi-bin:, stream:, cache:, data:, about:

Five internal protocols exist: `cgi-bin:`, `stream:`, `cache:`,
`data:` and `about:`.  These are the basic building blocks for the
implementation of every protocol mentioned above; for this reason, these
can *not* be replaced, and are implemented in the main browser binary.

`cgi-bin:` executes a local CGI script.  This scheme is used for the
actual implementation of the non-internal protocols mentioned above.
Local CGI scripts can also be used to implement wrappers of other
programs inside Chawan (e.g. dictionaries).

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
deterministically loaded from the cache upon certain actions, and from
the network upon others, but neither is used as a fallback to the other.

`data:` decodes a data URL as defined in RFC 2397.  This used to be a
CGI module, but has been moved back into the loader process because
these URLs can get so long that they no longer fit into the environment.

`about:` is inside the loader to allow for an implementation of the
download list panel.  It should be turned into a CGI module once the
loader gets RPC capabilities.

The following about pages are available: `about:chawan`, `about:blank`,
`about:license`, `about:downloads`.

## Custom protocols

The `cha` binary itself does not know much about the protocols listed
above; instead, it loads these through a combination of [local
CGI](localcgi.md), [urimethodmap](urimethodmap.md), and if conversion to
HTML or plain text is necessary, [mailcap](mailcap.md) (using
x-htmloutput, x-ansioutput and copiousoutput).

urimethodmap can also be used to override default handlers for the
protocols listed above.  This is similar to how w3m allows you to
override the default directory listing display, but much more powerful;
this way, any library or program that can retrieve and output text
through a certain protocol can be combined with Chawan.

For example, consider the urimethodmap definition of `finger`:

```
finger:		cgi-bin:finger
```

This commands Chawan to load the `finger` CGI script, setting the
`$MAPPED_URI_*` variables to the target URL's parts in the process.

Then, finger uses these passed parts to construct an appropriate
curl command that will retrieve the specified `finger:` URL; it prints
the header 'Content-Type: text/plain' to the output, then an empty line,
then the body of the retrieved resource.  If an error is encountered,
it prints a `Cha-Control` header with an error code and a specific error
message instead.

### Adding a new protocol

Here we will add a protocol called "cowsay", so that the URL cowsay:text
prints the output of `cowsay text` after a second of waiting.

`mkdir -p ~/.chawan/cgi-bin`, and create a CGI script in
`~/.chawan/cgi-bin/cowsay.cgi`:

```sh
#!/bin/sh
# We are going to wait a second from now, but want Chawan to show
# "Downloading..." instead of "Connecting...". So signal to the browser
# that the connection has succeeded.
printf 'Cha-Control: Connected\n'
sleep 1 # sleep
# Status is a special header that signals the equivalent HTTP status code.
printf 'Status: 200' # HTTP OK
# Tell the browser that no more control headers are to be expected.
# This is only useful when you want to send remotely received headers;
# then, it would be an attack vector to simply send the headers without
# ControlDone, as nothing stops the website from sending a Cha-Control
# header.  With ControlDone sent, subsequent Cha-Control headers will be
# interpreted as regular headers.
printf 'Cha-Control: ControlDone\n'
# As in HTTP, you must send an empty line before the body.
printf '\n'
# Now, print the body. We take the path passed to the URL; urimethodmap
# sets this as MAPPED_URI_PATH. This is URI-encoded, so we also run the urldec
# utility on it.
cowsay "$(printf '%s\n' "$MAPPED_URI_PATH" | "$CHA_LIBEXEC_DIR"/urldec)"
```

Now, create a ".urimethodmap" file in your `$HOME` directory.

Then, enter into it the following:

```
cowsay:		/cgi-bin/cowsay.cgi
```

Now try `cha cowsay:Hello,%20world.`.  If you did everything correctly,
it should wait one second, then print a cow saying "Hello, world.".

<!-- MANON

## See also

**cha**(1), **cha-localcgi**(5), **cha-urimethodmap**(5), **cha-mailcap**(5)
MANOFF -->
