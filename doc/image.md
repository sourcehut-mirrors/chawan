<!-- MANON
% CHA-IMAGE 7
MANOFF -->

# Inline images

On terminals that support images, Chawan can display various image formats.

## Enabling images

There are actually two switches for images in the config:

* buffer.images: this enables downloading images, *even if they cannot be
  displayed*.
* display.image-mode: sets the inline image display method.  Defaults to
  "auto", but may also be set to "sixel" or "kitty" manually.

In most cases, all you need to do is to set "buffer.images" to true:

```toml
# in ~/.chawan/config.toml (or ~/.config/chawan/config.toml)
[buffer]
images = true
```

With the default image-mode, Chawan will find the best image display
method supported by your terminal. However, if your terminal fails
to tell Chawan that it can display sixels, you may also have to set
"display.image-mode" appropriately.  See below for further discussion of
sixel configuration.

## Output formats

Supported output formats are:

* The DEC Sixel format
* The Kitty terminal graphics protocol

The former is supported because it's ubiquitously adopted; the latter
because it is technically superior to all existing alternatives.

Support for other protocols (iTerm, MLTerm, etc.) is not planned. (To my
knowledge, all image-capable terminals support at least one of the
above two anyways.)

Support for hacks such as w3mimgdisplay, ueberzug, etc. is not planned.

### Sixel

Sixel is the most widely supported image format. See <https://arewesixelyet.com>
to find a terminal that supports it.

Known quirks and implementation details:

* XTerm needs extensive configuration for ideal sixel support.  In
  particular, you will want to set the decTerminalID, numColorRegisters, and
  maxGraphicSize attributes. See [`man xterm`](man:xterm(1)) for details.

* We assume private color registers are supported.  On terminals where they
  aren't (e.g. SyncTERM or hardware terminals), colors will get messed up with
  multiple images on screen.

* Zellij advertises Sixel support, but the feature is completely broken in
  the current version, so Chawan specifically disables images in Zellij
  by default.  In particular:

	- Zellij itself does no Sixel detection, emitting Sixel data even on
	  terminals that do not support it.  (A fairly puzzling bug, given
	  the developers seem to be aware of the DA1 feature.)

	- On terminals that support Sixel, it fails to position images
	  correctly, with the misplaced images completely messing up layout.
	  (I guess nothing more complex than `img2sixel` was ever tested.)

* We send XTSMGRAPHICS for retrieving the number of color registers; on
  failure, we fall back to 256. You can override color register count using
  the `display.sixel-colors` configuration value.

* Normally, Sixel encoding runs in two passes.  On slow computers, you can
  try setting `display.sixel-colors = 2`, which will skip the first pass
  (but will also display everything in monochrome).

* Transparency *is* supported, but looks weird because we approximate
  an 8-bit alpha channel with Sixel's 1-bit alpha channel.  Also, some
  terminals don't emulate it correctly - when in doubt, try XTerm (which
  does).

* Terminal scroll (both with LF/RI and SU/SD) is used extensively to avoid
  sending images several times.  Expect troubles on terminals that do not
  handle this correctly.  (For example, tmux is known to destroy images on
  scroll, so we avoid using scroll there.)

### Kitty

On terminals that support it, Kitty's protocol is preferred over Sixel.  Its
main benefit is that images do not have to be sent again every time a new
slice of the image moves into the screen, but the initial transfer should
also be faster (because PNG's compression tends to outperform Sixel's RLE).

Unlike Sixel, the Kitty protocol fully supports transparency.

## Input formats

Currently, the supported input formats are:

* BMP, PNG, JPEG, GIF (through stb_image)
* WebP (through JebP)
* SVG (through NanoSVG)

More formats may be added in the future, provided there exists a reasonably
small implementation, preferably in the public domain.  (I do not want to
depend on external image decoding libraries, but something like stbi is OK
to vendor.)

### Codec module system

All image codec implementations are specified by the URL scheme
"img-codec+name:", where "name" is the MIME subtype. e.g. for image/png,
it is "img-codec+png:".  (This indeed means that only "image" MIME types can
be used.)

Like all schemes, these are defined (and overridable) in the urimethodmap
file, and are implemented as local CGI programs.  These programs take an
encoded image on stdin, and dump the decoded RGBA data to stdout - when
encoding, vice versa.

This means that it is possible for users to define image decoders for their
preferred formats, or even override the built-in ones. (If you actually end
up doing this for some reason, please send me a mail so I can add it to the
bonus directory.)

A codec can have one of, or both, "decode" and "encode" instructions; these
are set in the path name.  So "img-codec+png:decode" is called for decoding
PNGs, and "img-codec+png:encode" for encoding them.

Headers are used for transferring metadata (like image dimensions), both
from the browser (input) and to the browser (output).  Detailed description
of the decoder & encoder interfaces follows.

#### decoding

When the path equals "decode", a codec CGI script must take a binary stream
of an encoded image on its standard input and print the equivalent binary
stream of big-endian 8-bit (per component) RGBA values to stdout.

Input headers:

* Cha-Image-Info-Only: 1

This tells the image decoder to only send image metadata (i.e. size).
Technically, the decoder is free to fully decode the image, but this is
a waste of resources; the browser will ignore any output received after
headers.

Output headers:

* Cha-Image-Dimensions: {width}x{height}

The size of the decoded image.  e.g. for 123x456, 123 is width and 456 is
height.

#### encoding

When the path equals "encode", a codec CGI script must take a binary stream
of big-endian 8-bit (per component) RGBA values on its standard input and
print the equivalent encoded image to its standard output.

Input headers:

* Cha-Image-Dimensions: {width}x{height}

Specifies the dimensions of the input RGBA image. This means that
{width} * {height} * 4 == {size of data received on stdin}.

The format is the same as above; in fact, the design is such that you could
directly pipe the output of decode to encode (and vice versa).

* Cha-Image-Quality: {number}

The requested encoding quality, ranging from 1 to 100 inclusive
(i.e. 1..100).  It is up to the encoder to interpret this number.

(The stb_image JPEG encoder uses this.)

Output headers:

Currently, no output headers are defined for encoders.

### Skipping copies with mmap

The naive implementation of the above system would have to copy the output
at least twice when an image is resized.  To skip these copies, stdin and/or
stdout is (currently) a file in the tmp directory for:

* decode stdin, when the image is already downloaded
* decode stdout, always
* encode stdin, always

This makes it possible to [mmap](man:mmap(3)) stdin/stdout instead of
streaming through them with [read](man:read(3)) and [write](man:write(3)).
When doing this, mind the following:

* When reading, you must check your initial position in the file with
  [lseek](man:lseek(3)).

* When writing, your headers are part of the output.  At the very least,
  you must place a newline at the file's beginning.

* mmapping for write is slower than streaming the data with `write`.
  The only reason to mmap for write is to save memory when you can't stream
  the output.

* This *is* an implementation detail, and might change at any time in
  the future (e.g. if we add a "no cache files" mode).  Always check
  for S_ISREG to ensure that you are actually dealing with a file.  (Use
  io/dynstream.nim's recvDataLoopOrMmap and maybeMmapForSend to deal with
  this automatically.)

<!-- MANON

## See also

**cha**(1)
MANOFF -->
