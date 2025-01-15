<!-- MANON
% cha-protocols(7) | Protocol support in Chawan
MANOFF -->

# Protocols

Chawan supports downloading resources from various protocols: HTTP, FTP,
Gopher, Gemini, and Finger. Details on these protocols, and information
on how users can add support to their preferred protocols is outlined in
this document.

In general, you can find network adapters in the `adapter/protocol` directory.
For protocol-specific file formats (like gemtext or gopher directories) you will
also find an appropriate HTML converter in `adapter/format`.

<!-- MANOFF -->
**Table of contents**

* [HTTP](#http)
* [FTP](#ftp)
* [SFTP](#sftp)
* [Gopher](#gopher)
* [Gemini](#gemini)
* [Finger](#finger)
* [Spartan](#spartan)
* [Local schemes: file:, about:, man:](#local-schemes-file-about-man-data)
* [Internal schemes: cgi-bin:, stream:, cache:, data:](#internal-schemes-cgi-bin-stream-cache-data)
* [Custom protocols](#custom-protocols)

<!-- MANON -->

## HTTP

HTTP/s support is based on libcurl; supported features largely depend on
your libcurl version.

The libcurl HTTP adapter can take arbitrary headers and POST data, is able
to use passed userinfo data (`https://username:password@example.org`), and
returns all headers and response body it receives from libcurl without
exception.

It is possible to build the HTTP adapter using
[curl-impersonate](https://github.com/lwthiker/curl-impersonate) by setting
the compile-time variable CURLLIBNAME to `libcurl-impersonate.so`. Note that
for curl-impersonate to work, you must set `network.default-headers = {}`
in the Chawan config. (Otherwise, the libcurl adapter will happily override
curl-impersonate headers, which is probably not what you want.)

The `bonus` directory contains an alternative HTTP client based on FreeBSD
libfetch. It is mostly a proof of concept, as FreeBSD libfetch HTTP support is
very limited; in particular, it does not support arbitrary HTTP headers, so e.g.
cookies will not work.

## FTP

Chawan supports FTP passive mode browsing and downloads.

For directory listings, it assumes UNIX output style, and will probably
break horribly on receiving anything else. Otherwise, the directory
listing view is identical to the file:// directory listing.

## SFTP

The sftp adapter (`adapter/protocol/sftp.nim`) wraps libcurl. It works for me,
but YMMV.

Note that if an IdentityFile declaration is found in your ssh config, then it
will prompt for the identity file password, but there is no way to tell whether
it is really asking for that (or just normal password auth). Also, settings
covered by the Match field are ignored.

## Gopher

Chawan supports the Gopher protocol through the gopher CGI program.
Gopher directories are passed as the `text/gopher` type, and gopher2html
takes care of converting this to HTML.

Gopher selector types are converted to MIME types when possible; note however,
that this is very limited, as most of them (like `s` sound, or `I` image)
cannot be unambiguously converted without some other sniffing method. Chawan
will fall back to extension-based detection in these cases, and in the worst
case may end up with `application/octet-stream`.

## Gemini

Chawan's Gemini adapter has been rewritten as a Nim program. It still requires
OpenSSL to work.

A limitation that remains is that the Gemini adapter does not support sites that
require private key authentication.

gmi2html is its companion program to convert the `text/gemini` file format to
HTML.

## Finger

Finger is supported through the `finger` shell script. It is implemented
as a shell script because of the protocol's simplicity.

For portability, `finger` uses Chawan's `nc` tool (a very limited netcat
clone) to make requests.

## Spartan

Spartan is a protocol similar to Gemini, but without TLS. It is supported
through the `spartan` shell script, and like Finger, it uses Chawan's `nc` to
make requests.

Spartan has the very strange property of extending gemtext with a
protocol-specific line type. This is sort of supported through a sed filter
for gemtext outputs in the CGI script (in other words, no modification to
gmi2html was done to support this).

## Local schemes: file:, about:, man:

While these are not necessarily *protocols*, they are implemented similarly
to the protocols listed above (and thus can also be replaced, if the user
wishes; see below).

`file:` loads a file from the local filesystem. In case of directories, it
shows the directory listing like the FTP protocol does.

`about:` contains informational pages about the browser. At the time of
writing, the following pages are available: `about:chawan`, `about:blank`
and `about:license`.

`man:`, `man-k:` and `man-l:` are wrappers around the commands `man`, `man -k`
and `man -l`. These look up man pages using `/usr/bin/man` and turn on-page
references into links. A wrapper command `mancha` also exists; this has an
interface similar to `man`. Note: this used to be based on w3mman2html.cgi, but
it has been rewritten in Nim (and therefore no longer depends on Perl either).

## Internal schemes: cgi-bin:, stream:, cache:, data:

Four internal protocols exist: `cgi-bin:`, `stream:`, `cache:` and `data:`.
These are the basic building blocks for the implementation of every protocol
mentioned above; for this reason, these can *not* be replaced, and are
implemented in the main browser binary.

`cgi-bin:` executes a local CGI script. This scheme is used for the actual
implementation of the non-internal protocols mentioned above. Local CGI scripts
can also be used to implement wrappers of other programs inside Chawan
(e.g. dictionaries).

`stream:` is used for reading in streams returned by external programs or passed
to Chawan via standard input. It differs from `cgi-bin:` in that it does not
cooperate with the external process, and that the loader does not keep track
of where the stream originally comes from. Therefore it is suitable for reading
in the output of mailcap entries, or for turning stdin into a URL.

Since Chawan does not keep track of the origin of `stream:` URLs, it is not
possible to reload them. (For that matter, reloading stdin does not make much
sense anyway.) To support rewinding and "view source", the output of `stream:`'s
is stored in a temporary file until the buffer is discarded.

`cache:` is not something an end user would normally see; it's used for
rewinding or re-interpreting streams already downloaded. Note that this is not a
real cache; files are deterministically loaded from the "cache" upon certain
actions, and from the network upon others, but neither is used as a fallback
to the other.

`data:` decodes a data URL as defined in RFC 2397. This used to be a CGI module,
but has been moved back into the loader process because these URLs can get
so long that they no longer fit into the environment.

## Custom protocols

Chawan is protocol-agnostic. This means that the `cha` binary itself does not
know much about the protocols listed above; instead, it loads these through a
combination of [local CGI](localcgi.md), [urimethodmap](urimethodmap.md), and if
conversion to HTML or plain text is necessary, [mailcap](mailcap.md) (using
x-htmloutput, x-ansioutput and copiousoutput).

urimethodmap can also be used to override default handlers for the protocols
listed above. This is similar to how w3m allows you to override the default
directory listing display, but much more powerful; this way, any library
or program that can retrieve and output text through a certain protocol can
be combined with Chawan.

For example, consider the urimethodmap definition of cha-finger:

```
finger:		cgi-bin:cha-finger
```

This commands Chawan to load the cha-finger CGI script, setting the
`$MAPPED_URI_*` variables to the target URL's parts in the process.

Then, cha-finger uses these passed parts to construct an appropriate curl
command that will retrieve the specified `finger:` URL; it prints the header
'Content-Type: text/plain' to the output, then an empty line, then the body
of the retrieved resource. If an error is encountered, it prints a
`Cha-Control` header with an error code and a specific error message instead.

### Adding a new protocol

Here we will add a protocol called "cowsay", so that the URL cowsay:text
prints the output of `cowsay text` after a second of waiting.

`mkdir -p ~/.chawan/cgi-bin`, and create a CGI script in
`~/.chawan/cgi-bin/cowsay.cgi`:

```sh
#!/bin/sh
# We are going to wait a second from now, but want Chawan to show
# "Downloading..." instead of "Connecting...". So signal to the browser that the
# connection has succeeded.
printf 'Cha-Control: Connected\n'
sleep 1 # sleep
# Status is a special header that signals the equivalent HTTP status code.
printf 'Status: 200' # HTTP OK
# Tell the browser that no more control headers are to be expected.
# This is useful when you want to send remotely received headers; then, it would
# be an attack vector to simply send the headers without ControlDone, as nothing
# stops the website from sending a Cha-Control header. With ControlDone sent,
# even Cha-Control headers will be interpreted as regular headers.
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

Now try `cha cowsay:Hello,%20world.`. If you did everything correctly, it should
wait one second, then print a cow saying "Hello, world.".

<!-- MANON

## See also

**cha**(1), **cha-localcgi**(5), **cha-urimethodmap**(5), **cha-mailcap**(5)
MANOFF -->
