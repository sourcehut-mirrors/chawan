<!-- MANON
% CHA-TERMINAL 7
MANOFF -->

# Chawan terminal compatibility

Chawan does not use termcap, terminfo, or ncurses; it relies solely on
built-in terminal handling routines, mostly inspired by notcurses.

## XTerm compatibility

In general, Chawan assumes an XTerm-compatible environment where XTerm means
the current XTerm version as developed and maintained by Thomas E.\ Dickey.
This means that Chawan is compatible with any given terminal if:

* the terminal is actually compatible with XTerm, OR
* the terminal isn't compatible with XTerm, but reports its capabilities via
  terminal queries correctly, OR
* the terminal isn't compatible with XTerm, but its `TERM` value is
  hardcoded in Chawan.

Terminals pretending to be XTerm (`TERM=xterm`) which are not actually XTerm
might malfunction.

(In practice, I have tested dozens of terminal emulators and haven't
encountered any major issues; in all likelihood, yours will work too.
If it doesn't, please [open a ticket](https://todo.sr.ht/~bptato/chawan).)

## Queries

Queries are preferred to hardcoded terminal descriptions because they are
forward-compatible.  On startup, Chawan queries:

* Whether the terminal has true color, with XTGETTCAP rgb.
* The default background, foreground, and 16 ANSI(-ish) colors with
  `OSC 10 ; ? ST`, `OSC 11 ; ? ST`, and `OSC 4 ; {0..15} ; ? ST`.
* `OSC 60 ST` and `OSC 61 allowWindowOps ST` for detecting OSC 52 support
  (see the *[Clipboard](#clipboard)* section).
* Whether the terminal can use the Kitty image protocol, by sending a 1x1
  Kitty image and listening for a response.
* The number of Sixel color registers (`CSI ? 1 ; 1 ; 0 $`).
* Primary device attributes (DA1).
* Text area and cell size using `CSI 14 t` and `CSI 16 t`.  (Cell size beats
  text area size as it is more reliable.)
* Window size in cells by sending a CUP to 9999;9999 and then asking for CPR
  (the same trick is used by [**resize**](man:resize(1))(1)).

Chawan processes responses to the above query in the same state machine
as user input, so it works reasonably well on all terminals that at least
emulate the most basic VT100 function (CPR).  This unified state machine
also minimizes the chance of user input being mistaken for a query response
(or vice versa).

Terminals that do not respond to CPR will freeze on quit - in this case, you
must type `C-c` to forcibly kill the state machine.  In practice, FreeBSD's
**vt**(4) is the only one I've found that exhibits this behavior; to add
insult to injury, it claims to be an "xterm" in TERM.  Therefore we
discriminate between **vt**(4) and a real XTerm using an ioctl.  (Idea
shamelessly stolen from notcurses' Linux console detection.)

Some terminals bleed the APC sequence used to recognize kitty image support,
and this may result in strange artifacts when no alt screen is used.  On
terminals that set TERM correctly, the APC sequence is not sent.

## Clipboard

Some terminals support sequences to override the clipboard.  Chawan
differentiates between three tiers:

1. Supports clipboard *and* primary selection.  The latter is what allows
   you on X11 to select some text with the mouse and then middle-click
   paste it elsewhere.

   This applies to all terminals that respond to OSC 60/61 (XTerm) as well
   as a hardcoded list of terminals that respond with 52 in DA1 and have
   been confirmed to support the primary selection (Kitty).

2. Supports clipboard, but may choke on trying to set primary selection.

   This applies to terminals that include the number 52 in DA1.  This
   response guarantees nothing about support for the primary selection, and
   indeed, some terminals that return it (e.g. Contour) behave incorrectly
   when receiving primary.

3. Does not support clipboard.  In this case we shell out to
   `external.copy-cmd` (defaults to [**xsel**](man:xsel(1x))(1x)).

   This applies to all other terminals.  Notably, this includes terminals
   that support OSC 52 but do not have a reliable mechanism to detect
   whether it actually works, such as Alacritty.

It is possible to manually adjust OSC 52 use with the `input.osc52-copy` and
`input.osc52-primary` configuration options.

## Ancient terminals

Most pre-ECMA-48 (1979) terminals are not expected to work.

There is some degree of ADM-3A support, tested in Kragen Javier Sitaker's
[admu](https://gitlab.com/kragen/bubbleos) emulator.

Some DEC terminals have also been tested in simulators of the original
hardware running the actual ROM:

* The VT100 has been tested in Lars Brinkhoff's
  [terminal-simulator](https://github.com/larsbrinkhoff/terminal-simulator).
  Note: use TERM=vt100-nav if you don't have advanced video.
* The VT420 has been tested in Matt Mastracci's
  [Blaze](https://github.com/mmastrac/blaze).

Patches for other terminals (hardware or software alike) are welcome.

## Ancient character encodings

For ASCII-only terminals, don't forget to `export LC_ALL=C`.  For terminals
supporting other legacy encodings, you may also have some luck with
`language.charset`, such as `export LC_ALL=ja_JP.ISO-2022-JP`.

Note that Chawan uses its own encoding library instead of the notoriously
broken C locale facility, and the two sets of supported charsets may not
fully overlap.  You can test whether a charset is supported using
`cha -O {charset name} -V`.

<!-- MANON

## See also

**cha**(1)
MANOFF -->
