<!-- MANON
% CHA-TERMINAL 7
MANOFF -->

# Chawan terminal compatibility

Chawan does not use termcap, terminfo, or ncurses; it relies solely
on built-in terminal handling routines, mostly inspired by notcurses.

## XTerm compatibility

In general, Chawan assumes an XTerm-compatible environment where XTerm
means the current XTerm version as developed and maintained by Thomas E.
Dickey.  This means that Chawan is compatible with any given terminal
if:

* the terminal is actually compatible with XTerm, OR
* the terminal isn't compatible with XTerm, but reports its capabilities
  via terminal queries correctly, OR
* the terminal isn't compatible with XTerm, but its `TERM` value is
  hardcoded in Chawan.

Terminals pretending to be XTerm (`TERM=xterm`) which are not actually
XTerm might malfunction.

(In practice, I have tested dozens of terminal emulators and haven't
encountered any major issues; in all likelihood, yours will work too.
Still, if it doesn't, please
[open a ticket](https://todo.sr.ht/~bptato/chawan).)

## Queries

Queries are preferred to hardcoded terminal descriptions because they
are forward-compatible.  On startup, Chawan queries:

* Whether the terminal has true color, with XTGETTCAP rgb.
* The default background, foreground, and 16 ANSI(-ish) colors with
  `OSC 1 0 ; ? ST`, `OSC 1 1 ; ? ST`, and `OSC 4 ; {0..15} ; ? ST`.
* Whether the terminal can use the Kitty image protocol, by sending an
  incorrectly encoded image and listening for an error.
* The number of Sixel color registers (`CSI ? 1 ; 1 ; 0 $`).
* Text area, cell, and window size using `CSI 1 4 t`, `CSI 1 6 t`,
  `CSI 1 8 t`.  (Cell size, `1 6`, beats the other two as it is more
  reliable.)
* Primary device attributes.

Primary device attributes (henceforth DA1) are queried last, and most
terminals respond to this, so Chawan should never hang on startup.
If it *isn't* implemented (as on the FreeBSD console), the user can hit
any key to break out of the state machine and set `display.query-da1 =
false` as instructed by the browser.  On known terminals with this issue
which set `TERM` correctly, DA1 is omitted.

Some terminals bleed the APC sequence used to recognize kitty image
support.  If the terminal also supports the alternate screen (ti/smcup),
the sequence may end up inside the shell prompt.  On known terminals
with this issue which set `TERM` correctly, the kitty query is omitted.

## Ancient terminals

Pre-ECMA-48 terminals are generally not expected to work.

There is some degree of ADM-3A support, tested in Kragen Javier
Sitaker's `admu` emulator.  However, a real ADM-3A would likely be
confused by non-ASCII characters.

Patches for other terminals (hardware or software alike) are welcome.

<!-- MANON

## See also

**cha**(1)
MANOFF -->
