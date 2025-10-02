<!-- MANON
% CHA-TROUBLESHOOTING 7
MANOFF -->

# Troubleshooting Chawan

This document lists common problems you may run into when using Chawan.

If you encounter a problem not described in this document, please open a
ticket at <https://todo.sr.ht/~bptato/chawan>.

## It doesn't compile?

Please open a ticket.  Don't forget to include the compilation error, and
your operating system (and its version).

## It crashes?

Please open a ticket that describes how to reproduce the crash.  Don't
forget to include a stack trace - that's the wall of text you see after
your buffer disappeared.

If you don't see a stack trace, try:
`cha example.org -o start.console-buffer=false 2>err.log`.  Then check the
contents of `err.log` after the crash.

If you *still* don't see a stack trace, no problem, just report that you
couldn't get a stack trace.

## I can't select/copy text with my mouse?

Right click -> select text, then right click -> copy selection.  (You can
also double click and drag the mouse to the left/right to select.)

If Chawan complains about xsel, either install it or edit
`external.copy-cmd` and `external.paste-cmd` to your liking.

## I was promised images but I see nothing?

The most common reason is that you didn't add following to `config.toml`:

```toml
[buffer]
images = true
```

The second most common reason is that your terminal supports neither Sixel
nor Kitty images.

Other reasons are enumerated <!-- MANOFF -->[here](image.md).<!-- MANON --> <!-- MANON here: **cha-image**(7) MANOFF -->

## Why do I get strange/incorrect/ugly colors?

By default, Chawan's display capabilities are limited to what your terminal
reports.  In particular:

* If the `$COLORTERM` environment variable is not set, it may fall back to
  8-bit or ANSI colors.  Make sure you export it as `COLORTERM=truecolor`.
* If it does not respond to querying the background color, then Chawan's
  color contrast correction will likely malfunction.  You can correct this
  using the `display.default-background-color` and
  `display.default-foreground-color` options.

See [config.md](config.md#display) for details.

## I set my `$PAGER` to `cha` and now man pages are unreadable.

Most `man` implementations print formatted manual pages by default, which
Chawan *can* parse if they are passed through standard input.

Unfortunately, mandoc passes us the formatted document as a *file*, which Chawan
reasonably interprets as plain text without formatting.

At this point, you have two options:

* `export PAGER='cha -T text/x-ansi'` and see that man suddenly works as
  expected.
* `alias man=mancha` and see that man suddenly works better than expected.

Ideally you should do both, to deal with cases like git help which shells out to
man directly.

There is still one problem with this solution: some programs will try
to call `$PAGER` without shell expansion, breaking the `-T text/x-ansi`
trick.  To fix this, put a script somewhere in your `PATH`:

```sh
#!/bin/sh
exec cha -T text/x-ansi "$@"
```

and `export PAGER=pcha` (or whatever you named the script).

## How do I view text files with wrapping?

By default, text files are not auto-wrapped, so viewing plain text files that
were not wrapped properly by the authors is somewhat annoying.

A workaround is to add this to your [config](config.md#keybindings)'s
`[page]` section:

```toml
' f' = "pager.externFilterSource('fmt')"
```

and then press `<space> f` to view a wrapped version of the current text
file. (This assumes your system has an `fmt` program - if not, `fold -s` may
be an alternative.)

To always automatically wrap, you can add this to your
[user style](config.md#buffer):

```css
plaintext { white-space: pre-wrap }
```

To do the same for HTML and ANSI text, use `plaintext, pre`.

## Why does `$WEBSITE` look awful?

Usually, this is because it uses some CSS features that are not yet implemented
in Chawan.  The most common offender is grid.

There are three ways of dealing with this:

1. If the website's contents are mostly text, install
   [rdrview](https://github.com/eafer/rdrview).  Then bind the following
   command to a key of your choice in the [config](config.md#keybindings)
   (e.g. `<space> r`):

   `' r' = "pager.externFilterSource('rdrview -Hu \"$CHA_URL\"')"`

   This does not fix the core problem, but will significantly improve your
   reading experience anyway.

2. Complain [here](https://todo.sr.ht/~bptato/chawan), and wait until the
   problem goes away.  It helps if you can reduce the issue to a minimal
   reproducible example (ideally a small HTML fragment.)

3. Write a patch to fix the problem, and send it
   [here](https://lists.sr.ht/~bptato/chawan-devel).

## `$WEBSITE`'s interactive features don't work!

Some potential fixes:

* Logging in to websites requires cookies.  Some websites also require
  cookie sharing across domains.  For security reasons, Chawan does not
  allow any of this by default, so you will have to fiddle with siteconf
  to fix it.  See [config.md#siteconf](config.md#siteconf) for details.

* Set the `referer-from` siteconf value to true; this will cause Chawan
  to send a `Referer` header when navigating to other URLs from the
  target URL.

* Enable JavaScript.  If something broke, type M-c M-c to check the
  browser console, then follow step 3. of the previous answer.

## Text areas discard my edits when I type C-c in my editor!

This is a bug in your shell:
<https://people.freebsd.org/~cracauer/homepage-mirror/sigint.html>

When Chawan runs an external text editor, it simply passes the `$EDITOR`
command to the shell, and then examines its *wait status* to determine
if your editor exited gracefully.  This works if either the editor never
receives a signal, or your shell implements WCE.

However, if the editor (e.g. nvi) catches SIGINT on C-c, and the shell
reports that the program was killed by a signal (WUE), then Chawan will
discard your changes (as it believes that the program has crashed).

The easiest workaround is to remove the shell from the equation using
`exec`:

```sh
[external]
editor = 'exec vi +%d'
```

## When I open Chawan from aerc, it prints garbage in the search field!

This should be fixed in the latest aerc version.  Please update aerc.

## mancha doesn't work on NixOS?

NixOS includes a broken patch in the package that results in mancha not
finding man pages in some configurations.  I suspect it's entirely
unnecessary, so if this bothers you then submit a PR to NixOS to remove
the patch.

<!-- MANON
## See also

**cha**(1)
MANOFF -->
