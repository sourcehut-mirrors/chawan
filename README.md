# Chawan - a web browser for your terminal

[Project page](https://sr.ht/~bptato/chawan)

![Screenshot of Chawan displaying its SourceHut page](doc/showcase.png)

## What is this?

A text-mode web browser. It displays websites in your terminal and allows
you to navigate on them.

It can also be used as a terminal pager.

## Compiling

Note: a POSIX-compliant operating system is required.

1. Clone the Chawan repository:  
   `git clone https://git.sr.ht/~bptato/chawan && cd chawan`
2. Install the Nim compiler: <https://nim-lang.org/install.html>
	* Please use 2.0.0 or newer, ideally 2.2.2. (Type `nim -v` to
	  check your Nim compiler's version.)
	* If you are using a 32-bit system: `export CFLAGS=-fpermissive`
	  before compiling, or (preferably) use a nightly build of the
	  Nim compiler.
3. Install the following dependencies:
	* [OpenSSL](https://www.openssl.org/) (or
	  [LibreSSL](https://www.libressl.org/))
	* [libssh2](https://libssh2.org/)
	* [brotli](https://github.com/google/brotli)
	* pkg-config, pkgconf, or similar (must be found as "pkg-config" in your
	  `$PATH`)
	* GNU make
	* TL;DR for Debian:
	  `apt install libssh2-1-dev libssl-dev libbrotli-dev pkg-config make`
4. Run `make` (without arguments).
5. Install using `make install` (e.g. `sudo make install`).

Then, try:

```bash
$ cha -V # open in visual mode for a list of default keybindings
$ cha example.org # open your favorite website directly from the shell
$ mancha cha # read the cha(1) man page using `mancha'
```

## Packages

Alternatively, you can install Chawan from packages maintained by
volunteers:

* AUR: <https://aur.archlinux.org/packages/chawan-git>
* NixOS: <https://search.nixos.org/packages?show=chawan>
* AppImage: <https://git.lerch.org/lobo/chawan-appimage/>

## Features

Currently implemented features are:

* multi-processing, incremental loading of documents
* multi-charset, double-width aware text display (but no bi-di yet)
* HTML5 support, forms, cookies
* [CSS](doc/css.md)-based layout engine: supports flow layout, table
  layout, flexbox layout
* user-programmable keybindings (defaults are vi(m)-like)
* basic JavaScript support in documents (disabled by default for security
  reasons)
* inline image support with sixel/kitty protocols (disabled by default;
  see [doc/image.md](doc/image.md) on how to enable)
* supports several [protocols](doc/protocols.md): HTTP(S), FTP, Gopher, Gemini,
  Finger, etc.
* [user-defined](doc/urimethodmap.md) protocols and
  [file formats](doc/mailcap.md)
* markdown viewer, man page viewer
* mouse support
* syscall filter based sandboxing on FreeBSD, OpenBSD and Linux (through
  capsicum, pledge and seccomp-bpf)
* bookmarks

...with a lot more [planned](todo).

## Documentation

Chawan's documentation is available as man pages (`man cha`) and as
Markdown files.

* build/compilation options: [doc/build.md](doc/build.md)
* manpage: [doc/cha.1](doc/cha.1)
* configuration options: [doc/config.md](doc/config.md)
* API description (for keybindings): [doc/api.md](doc/api.md)
* mailcap: [doc/mailcap.md](doc/mailcap.md)
* mime.types: [doc/mime.types.md](doc/mime.types.md)
* urimethodmap: [doc/urimethodmap.md](doc/urimethodmap.md)
* local CGI: [doc/localcgi.md](doc/localcgi.md)
* protocols: [doc/protocols.md](doc/protocols.md)
* inline images: [doc/image.md](doc/image.md)
* CSS: [doc/css.md](doc/css.md)
* terminal compatibility: [doc/terminal.md](doc/terminal.md)
* troubleshooting: [doc/troubleshooting.md](doc/troubleshooting.md)

If you're interested in modifying the code:

* architecture: [doc/architecture.md](doc/architecture.md)
* style guide, debugging tips, etc.: [doc/hacking.md](doc/hacking.md)

## FAQ

### I have encountered a bug/technical issue while using Chawan.

Please check our [troubleshooting](doc/troubleshooting.md) document. If this
does not help, please [open a ticket](https://todo.sr.ht/~bptato/chawan)
or post to the [mailing list](mailto:~bptato/chawan-devel@lists.sr.ht).

### I'm interested in the technical details of Chawan.

Here's some:

* The browser engine (HTML parsing, rendering, etc.) has been developed
  from scratch in the memory-safe Nim programming language. Some of these
  modules are now also available as separate libraries.
* Uses [QuickJS-NG](https://github.com/quickjs-ng/quickjs) for JavaScript
  execution and regex matching.
* Each buffer (page) is isolated in a separate process. File loading is done
  through dedicated loader processes.
* Uses terminal queries for terminal capability discovery.
* The default image decoder (PNG, JPEG, GIF, BMP) uses
  [stb_image](https://github.com/nothings/stb), WebP images are
  decoded using [JebP](https://github.com/matanui159/jebp), and SVG is
  decoded using [NanoSVG](https://github.com/memononen/nanosvg).  Image
  codecs are handled as protocols, so users can add their own codecs
  (with urimethodmap).

For further details, please refer to the [architecture](doc/architecture.md)
document.

### Why write another web browser?

w3m is close to my ideal browser, but its architecture leaves a lot to be
desired. So initially I just wanted a simple w3m clone with a more maintainable
code base.

The project has evolved a lot since then, even including things I had not
initially intended to (like CSS). Now it is mainly focused on:

* Simplicity, as much as "modern standards" permit. Chawan has very few external
  dependencies, and favors reduced code size over speed. This lowers the risk
  of supply chain attacks, and helps me understand what my browser is doing.
* Secure defaults over convenience. Like w3m, extra configuration is
  needed to enable dangerous features (JS, cookies, etc.) Unlike w3m, we
  also run buffers in separate, sandboxed processes.
* Adding the rest of missing w3m features, and improving upon those.
* Most importantly: having fun in the process :)

## Neighbors

Many other text-based web browsers exist. Here's some recommendations
(not meant to be an exhaustive list):

* [w3m](https://sr.ht/~rkta/w3m/) - A text-mode browser, extensible using
  local CGI. Also has inline image display and very good table support.
  Main source of inspiration for Chawan.
* [elinks](https://github.com/rkd77/elinks) - Has CSS and JavaScript support,
  and incremental rendering (it's pretty fast.)
* [links](http://links.twibright.com/) - Precursor of elinks, but it's still
  being developed. Has a graphical mode.
* [lynx](https://lynx.invisible-island.net/) - Doesn't need an introduction.
  The oldest web browser still in active development.
* [edbrowse](http://edbrowse.org/) - This one looks more like `ed` than
  `less` or `vi`. Originally designed for blind users.
* [telescope](https://github.com/telescope-browser/telescope) - A "small
  internet" (Gemini, Gopher, Finger) browser. Has a very cool UI.
* [offpunk](https://sr.ht/~lioploum/offpunk/) - An offline-first browser
  for Web, Gemini, Gopher, Spartan. Separates "downloading" from "browsing".
* [browsh](https://www.brow.sh/) - Firefox in your terminal.
* [Carbonyl](https://github.com/fathyb/carbonyl) - Chromium in your terminal.

## Relatives

[Ferus](https://github.com/ferus-web/ferus) is a separate graphical browser
engine written in Nim, which uses Chawan's HTML parser.

## License

Chawan is dedicated to the public domain. See the UNLICENSE file for details.

Chawan also includes and depends on several other libraries. For further
details, check the <about:license> page in Chawan, or read the same document
[here](res/license.md).
