# Bonus

Misc modules and configurations - mostly just personal scripts that I
don't want to copy around otherwise...

## Install

Run `make install-{filename}`. For example, to install git.cgi, you run
`make install-git.cgi`.

Warning: some of the installers will modify your ~/.urimethodmap file.
Because the entries are inserted to the file's start, you can usually
just remove these if you no longer want to use the script.

Also, the /cgi-bin/ directory is assumed to be configured as the default
(~/.chawan/cgi-bin or ~/.config/chawan/cgi-bin if you use XDG basedir).
Use `make CHA_CGI_DIR=...` to override this.

## Summary

Additional documentation is embedded at the beginning of each file.
Please read it. (Note that the Makefile automates the installation
instructions, so you can skip those.)

### [config.toml](config.toml)

A configuration file template, including the default options (commented out
so less users are affected if a breaking change happens).

### [curlhttp.nim](curlhttp.nim)

Old HTTP(S) handler based on libcurl.  This is mainly useful if you want
to use [curl-impersonate](https://github.com/lexiforest/curl-impersonate);
in this case, install it like
`make install-curlhttp CURLLIBNAME=libcurl-impersonate.so`.

Note: curlhttp handles the `proxy` configuration value differently than
the default (built-in) handlers; see [`man 1 curl`](man:curl(1)) for
details.  In particular, there is a difference between `socks5h` and
`socks5`; in the default HTTP(S) handler, the two are equivalent, but in
libcurl, the latter leaks DNS lookups.

### [filei.cgi](filei.cgi)

Album view of a directory. Requires `buffer.images = true`.

### [git.cgi](git.cgi)

Turns git command output into hypertext; quite useful, albeit a bit
slow.

It's also a demonstration of a combined CLI command and CGI script.

### [libfetch-http.c](libfetch-http.c)

CGI script to replace the default http handler with FreeBSD libfetch.

Just for fun; it's not very usable in practice, because libfetch is
designed to handle file downloads, not web browsing.

### [magnet.cgi](magnet.cgi)

A `magnet:` URL handler. It can forward magnet links to transmission.

### [nex](nex)

A `nex:` URL handler and directory parser.

Note: this does not have an installer.  Follow the instructions in the
file's header.

### [trans.cgi](trans.cgi)

Uses [translate-shell](https://github.com/soimort/translate-shell) to
translate words.

### [w3m.toml](w3m.toml)

A (somewhat) w3m-compatible keymap. Mainly for demonstration purposes.

Note: this does not have an installer. Copy/include it manually.
