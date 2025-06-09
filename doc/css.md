<!-- MANON
% CHA-CSS 7
MANOFF -->

# CSS in Chawan

This document describes CSS features supported by Chawan, as well as
its proprietary extensions and deviations from standards.

If you discover a deviation that is not covered by this document, please
open a ticket at <https://todo.sr.ht/~bptato/chawan>.

## Standard properties

A list of supported standard properties, with notes on unimplemented
values:

* background-color (see color)
* background-image (displays placeholders only)
* border-collapse
* border-spacing
* bottom
* box-sizing
* caption-side
* clear
* color (hex values and functions `rgb`, `rgba`, `hsl`, `hsla`)
* content (string, (no-)open/close-quote, counter())
* counter-increment
* counter-reset
* counter-set
* display (`block`, `inline-block`, `list-item`, `table`, `table-*`,
  `flex`, `inline-flex`, `flow-root`)
* flex-basis (but `content` not supported)
* flex-direction
* flex-grow
* flex-shrink
* flex-wrap
* float
* font-size (ignored; only for JS compatibility)
* font-style (`oblique` interpreted as `italic`)
* font-weight (numeric properties > 500 interpreted as bold, others
  as regular)
* height
* left
* list-style-position
* list-style-type (but no custom list styles)
* margin-bottom
* margin-left
* margin-right
* margin-top
* max-height
* max-width
* min-height
* min-width
* opacity (hacky; only works with `opacity: 0`)
* overflow-x (see below on scrollbars)
* overflow-y (see below on scrollbars)
* padding-bottom
* padding-left
* padding-right
* padding-top
* position (see below for `sticky` and `fixed`)
* quotes
* right
* text-align
* text-decoration (`none`, `underline`, `overline`, `line-through`)
* text-transform
* top
* vertical-align
* visibility
* white-space
* width
* word-break
* z-index

Shorthands:

* all
* margin
* padding
* background (only color and url; other components are skipped)
* list-style (list-style-image is skipped)
* flex
* flex-flow
* overflow

Variables (the `var` function) are supported only for non-shorthand
properties and the `background` shorthand.

Values with a `<length>` type support very simple `calc()` expressions
that consist of one addition or subtraction and do not use the `var`
function.

## Selectors

All selector types from CSS 2.1 are supported, except for namespaces.

Following standard pseudo-classes are supported: `:first-child`,
`:last-child`, `:only-child`, `:hover`, `:root`, `:nth-child()`,
`:nth-last-child()`, `:checked`, `:focus`, `:is()`, `:not()`,
`:where()`, `:lang()` (only "en" is matched), `:link`, `:target`.

`:visited` is parsed, but for now it is not matched.

The standard pseudo-elements `::before`, `::after`, and `::marker` are
supported.

## Media queries

The `grid`, `hover`, `prefers-color-scheme`, `scripting`, `width`, and
`height` media features are fully supported.

The `color`, `color-index`, and `monochrome` features are supported, but
only consider the number of supported text colors (which can differ from
the number of colors in Sixel/Kitty images).

## Proprietary extensions

* `text-align` accepts the values `-cha-center`, `-cha-left`, and
  `-cha-right` to support the HTML `<center>`, `<div align=left>`
  and `<div align=right>` elements.  (Analogous to `-moz-center` etc.)

* Properties with a `<color>` value accept the function `-cha-ansi()`,
  which takes one parameter that is either:

	- An 8-bit integer, indicating a color value as set by XTerm's
	  indexed color feature.

	- One of the strings "black", "red", "green", "yellow", "blue",
	  "magenta", "cyan", "white" for an ANSI color, possibly
	  prefixed by the string "bright-" to indicate an aixterm
	  16-color value.

  The actual palette in use is specified by the user/terminal.

* `text-decoration` accepts the keyword `-cha-reverse`, which sets
  the *reverse video* parameter on the text.  (This is used by the UA
  style sheet to highlight text in `<code>` tags.)

* `text-transform` accepts the keyword `-cha-half-width`, which has the
  opposite effect as `full-width`.

  This can be used in user style sheets to compress distracting ruby
  text: `rt{text-transform: -cha-half-width}`.  Characters without
  half-width counterparts are left intact, except hiragana is treated as
  katakana.

* The `-cha-colspan` and `-cha-rowspan` properties have the same effect
  as the `colspan` and `rowspan` attributes on tables.

* The `:-cha-first-node` and `:-cha-last-node` pseudo-classes apply to
  elements that have no preceding/subsequent sibling node that is either
  an element node or a text node with non-whitespace contents.  (Modeled
  after `:-moz-first-node` and `:-moz-last-node`.)

* If `buffer.mark-links` is set, the `::-cha-link-marker` pseudo-element
  will be generated on all anchor elements.

## Rendering quirks

These are willful violations of the standard, usually made to better fit
the display model inherent to projecting the web to a cell-based screen.

### User agent style sheet

The user agent style sheet is a combination of the styles suggested by
the HTML standard and a CSS port of w3m's rendering.  In general,
faithfulness to w3m is preferred over the standard's suggestions, unless
w3m's rendering breaks on existing websites.

Link colors differ depending on the terminal's color scheme.

### Sizing and positioning

Layout is performed on a finite canvas of coordinates represented by a
32-bit fixed-point number with 6 bits of precision.  After layout, these
positions are divided by the cell width and/or height, with the
fractional part truncated.  (This is subject to change.)

In case of Kitty images, the fractional part is preserved, and is used
as an in-cell offset.

The lengths `1em` and `1ch` compute to the cell height and cell width
respectively.

In outer inline boxes (`inline-block`, `inline-flex`) and `list-item`
boxes, margins and padding that are smaller than one cell (on the
respective axis) are ignored.  This does not apply to blockified inline
boxes.

When calculating clip boxes (`overflow: hidden` or `clip`), the clip
box's offset is floored, and its size is ceiled to the nearest cell's
boundaries.  This means that "width: 1px; overflow: hidden" will still
display the first character of a text box.

### Scroll bars

Chawan does not have scroll bars, as they would complicate on-page
navigation and would not work in dump mode.  Instead, the "overflow-x/y"
properties are handled as follows.

1. If `overflow` is `auto` or `scroll`, and the intrinsic minimum size
   of the box is greater than its specified size, then the former
   overrides the latter.
2. Content that spills out of a scroll container on the X axis is
   displayed, while content that spills out of a scroll container on the
   Y axis is clipped.

### `position: fixed`, `position: sticky`

To keep the document model static, these do not change their position
based on the viewport's scroll status.  Instead:

* `position: sticky` is treated as `position: static`, except it also
  behaves as an absolute position container.
* `position: fixed` is placed at the bottom of the document.

Right now, `position: fixed` is always positioned at the bottom of the
root element's margin box.  This breaks on pages that overflow it (e.g.
by setting `height: 100%` on the root element), so it will be moved to
the bottom of its overflow box in the future.

### Color correction

Some authors only specify one of the foreground or the background color,
assuming a black-on-white canvas.  The `display.minimum-contrast` option
adjusts the foreground color so that text remains readable even if the
terminal background does not match this expectation.  (The exact
algorithm is unspecified and subject to change.)

This unfortunately breaks spoiler mechanisms that rely on "black on
black" text not being visible.  The issue disappears when `visibility:
hidden` is applied to the text as well.

<!-- MANON

## See also

**cha**(1)
MANOFF -->
