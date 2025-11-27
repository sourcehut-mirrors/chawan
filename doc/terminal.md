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
  `OSC 1 0 ; ? ST`, `OSC 1 1 ; ? ST`, and `OSC 4 ; {0..15} ; ? ST`.
* Whether the terminal can use the Kitty image protocol, by sending an
  incorrectly encoded image and listening for an error.
* The number of Sixel color registers (`CSI ? 1 ; 1 ; 0 $`).
* Primary device attributes (DA1).
* Text area and cell size using `CSI 1 4 t` and `CSI 1 6 t`.  (Cell size
  beats text area size as it is more reliable.)
* Window size in cells by sending a CUP to 9999;9999 and then asking for CPR
  (the same trick is used by `resize`).

In the past, Chawan relied on the terminal always responding to DA1, and
would hang on non-conforming terminals.  This is no longer the case as we
now allow user interaction before the state machine has finished.

Some terminals bleed the APC sequence used to recognize kitty image support.
If the terminal also supports the alternate screen (ti/smcup), the sequence
may end up inside the shell prompt.  On known terminals with this issue
which set `TERM` correctly, the kitty query is omitted.

## Ancient terminals

Pre-ECMA-48 terminals are generally not expected to work.

There is some degree of ADM-3A support, tested in Kragen Javier Sitaker's
[admu](https://gitlab.com/kragen/bubbleos) emulator.  The VT100 has also
been tested in Lars Brinkhoff's
[terminal-simulator](https://github.com/larsbrinkhoff/terminal-simulator).
Finally, the VT420 has been tested in Matt Mastracci's
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
