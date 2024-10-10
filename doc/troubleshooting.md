<!-- MANON
% cha-troubleshooting(5) | Troubleshooting Chawan
MANOFF -->

# Troubleshooting Chawan

This document lists common problems you may run into when using Chawan.

## I can't select/copy text with my mouse?

Your options are:

* Press `v` (and copy with `y`). You can then expand the selection with the
  mouse.
* Hold down the shift key while selecting. Drawback: can only select text
  currently on the screen, and you can't select tabs.
* Disable mouse support (`input.use-mouse = false` in config.toml). Drawback:
  see above.

## Why do I get strange/incorrect/ugly colors?

Chawan's display capabilities depend on what your terminal reports. In
particular:

* if the `$COLORTERM` variable is not set, then it may fall back to 8-bit or
  ANSI colors. Make sure you export it as `COLORTERM=truecolor`.
* if it does not respond to querying the background color, then Chawan's color
  contrast correction will likely malfunction. you can correct this using the
  `display.default-background-color`/`display.default-foreground-color`
  variables.

See [config.md](config.md#display) for details.

## Can I view Markdown files using Chawan?

Yes; Chawan now has a built-in markdown converter. If you don't like it, you
can always [replace it](mailcap.md) with e.g. pandoc.

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

There is still one problem with this solution: some programs will try to call
`$PAGER` without shell expansion, breaking the `-T text/x-ansi` trick. To fix
this, put a script somewhere in your `PATH`:

```sh
#!/bin/sh
exec cha -T text/x-ansi "$@"
```

and `export PAGER=pcha`.

## Where are the keybindings?

Please run `cha about:chawan` for a list of default keybindings. Users familiar
with *vi*, *vim*, etc. should find these defaults familiar.

A w3m-like keymap also exists at [bonus/w3m.toml](bonus/w3m.toml). Note that not
every w3m feature is implemented yet, so it's not 100% compatible.

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
[user style](config.md#stylesheets):

```css
plaintext { white-space: pre-wrap }
```

To do the same for HTML and ANSI text, use `plaintext, pre`.

## Why does `$WEBSITE` look awful?

Usually, this is because it uses some CSS features that are not yet implemented
in Chawan. The most common offenders are grid and CSS variables.

There are three ways of dealing with this:

1. If the website's contents are mostly text, install
   [rdrview](https://github.com/eafer/rdrview). Then bind the following command
   to a key of your choice in the [config](config.md#keybindings)
   (e.g. `<space> r`):<br>
   `' r' = "pager.externFilterSource('rdrview -H -u \"$CHA_URL\"')"`<br>
   This does not fix the core problem, but will significantly improve your
   reading experience anyway.
2. Complain [here](https://todo.sr.ht/~bptato/chawan), and wait until the
   problem goes away.
3. Write a patch to fix the problem, and send it
   [here](https://lists.sr.ht/~bptato/chawan-devel).

## `$WEBSITE`'s interactive features don't work!

Some potential fixes:

* Logging in to websites requires cookies. Some websites also require cookie
  sharing across domains. For security reasons, Chawan does not allow any of
  this by default, so you will have to fiddle with siteconf to fix it. See
  [config.md#siteconf](config.md#siteconf) for details.
* Set the `referer-from` siteconf value to true; this will cause Chawan to send
  a `Referer` header when navigating to other URLs from the target URL.
* Enable JavaScript. If something broke, type M-c M-c to check the browser
  console, then follow step 3. of the previous answer.<br>
  Warning: remote JavaScript execution is inherently unsafe. Please only enable
  JavaScript on websites you trust.
