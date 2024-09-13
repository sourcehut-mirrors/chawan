<!-- MANON
% cha-image(5) | Image support in Chawan
MANOFF -->

# Inline images

On terminals that support images, Chawan can display various bit-mapped
image formats.

Warning: both this document and the implementation is very much WIP.
Anything described in this document may change in the near future.

## Enabling images

There are actually two switches for images in the config:

* buffer.images: this enables downloading images, *even if they cannot
  be displayed*.
* display.image-mode: sets the inline image display method. Defaults to
  "auto", but may also be set to "sixel" or "kitty" manually.

In most cases, all you need to do is to set "buffer.images" to true;
with the default image-mode, Chawan will find the best image display
method supported by your terminal.

If your terminal does not tell Chawan that it can display sixels, you may also
have to set "display.image-mode" appropriately.  See below for further
discussion of sixel configuration.

## Output formats

Supported output formats are:

* The DEC Sixel format
* The Kitty terminal graphics protocol

The former is supported because it's ubiquitiously adopted; the latter
because it is technically superior to all existing alternatives.

Support for other protocols (iTerm, MLTerm, etc.) is not planned. (To my
knowledge, all image-capable terminals support at least one of the
above two anyways.)

Support for hacks such as w3mimgdisplay, ueberzug, etc. is not planned.

### Sixel

Sixel is the most widely supported image format. See <https://arewesixelyet.com>
to find a terminal that supports it.

Known quirks and implementation details:

* XTerm needs extensive configuration for ideal sixel support. In particular,
  you will want to set the "decTerminalID", "numColorRegisters",
  and "maxGraphicSize" attributes. See `man xterm` for details.
* We assume private color registers are supported. On terminals where they
  aren't (e.g. SyncTERM or hardware terminals), colors will get messed up with
  multiple images on screen.
* We send XTSMGRAPHICS for retrieving the number of color registers; on failure,
  we fall back to 256. You can override color register count using the
  `display.sixel-colors` configuration value.
* For the most efficient sixel display, you will want a cell height that
  is a multiple of 6. Otherwise, the images will have to be re-coded several
  times on scroll.
* Normally, Sixel encoding runs in two passes. On slow computers, you can try
  setting `display.sixel-colors = 2`, which will skip the first pass.
* Transparency is currently not supported; you will get strange results with
  transparent images.

### Kitty

On terminals that support it, Kitty is preferred over Sixel. The Kitty
protocol has the benefit that it can reuse images we have sent at least once,
so it is normally more efficient than the former.

To minimize transfer size, we encode images to PNG before displaying them.

## Input formats

Currently, the supported input formats are:

* BMP, PNG, JPEG, GIF (through stb_image)
* WebP (through JebP)

More formats may be added in the future, provided there exists a
reasonably small implementation, preferably in the public domain. (I do
not want to depend on external image decoding libraries, but something
like stbi is OK to vendor.)

### Codec module system

All image codec implementations are specified by the URL scheme
"img-codec+name:", where "name" is the MIME subtype. e.g. for image/png,
it is "img-codec+png:". Like all schemes, these are defined (and
overridable) in the urimethodmap file, and are implemented as local CGI
programs. These programs take an encoded image on stdin, and dump the
decoded RGBA data to stdout - when encoding, vice versa.

This means that it is possible (although rarely practical) for users
to define image decoders for their preferred formats, or even override
the built-in ones. (If you actually end up doing this for some reason,
please shoot me a mail so I can add it to the bonus directory.)

A codec can have one of, or both, "decode" and "encode" instructions;
these are set in the path name. So "img-codec+png:decode" is called for
decoding PNGs, and "img-codec+png:encode" for encoding them.

Headers are used for transferring metadata (like image dimensions), both
from the browser (input) and to the browser (output). Detailed
description of the decoder & encoder interfaces follows.

#### decoding

When the path equals "decode", a codec CGI script must take a binary
stream of an encoded image on its standard input and print the
equivalent binary stream of big-endian 8-bit (per component) RGBA values
to stdout.

If specified, it also has to resize said image first.

Input headers:

* Cha-Image-Info-Only: 1

This tells the image decoder to only send image metadata (i.e. size).
Technically, the decoder is free to actually decode the image too, but
the browser will ignore any output after headers.

* Cha-Image-Target-Dimensions: {width}x{height}

Mutually exclusive with Cha-Image-Info-Only; this instructs the decoder
to also resize the output image. The dimension format is such that for
e.g. 123x456, 123 is width and 456 is height.

(Readers of good taste might consider this header to be a questionable
design decision, but remember that both the decoder and encoder
effectively require copying the output image (thru stdio). Combined with
the current file loader implementation, this means that in-browser image
resizing would require at least two unnecessary copies.

A future design might solve this problem better through shared memory.)

Output headers:

* Cha-Image-Dimensions: {width}x{height}

The final size of the decoded image. If the image was resized through
Cha-Image-Target-Dimensions, then this header's value will match the
value specified there.

Again, the dimension format is such that e.g. for 123x456, 123 is width
and 456 is height.

#### encoding

When the path equals "encode", a codec CGI script must take a binary
stream of big-endian 8-bit (per component) RGBA values on its standard
input and print the equivalent encoded image to its standard output.

Input headers:

* Cha-Image-Dimensions: {width}x{height}

Specifies the dimensions of the input RGBA image. This means that
{width} * {height} * 4 == {size of data received on stdin}.

The format is the same as above; in fact, the design is such that you
could directly pipe the output of decode to encode (and vice versa).

* Cha-Image-Quality: {number}

The requested encoding quality, ranging from 1 to 100 inclusive
(i.e. 1..100). It is up to the encoder to interpret this number.

(The stb_image JPEG encoder uses this.)

Output headers:

Currently, no output headers are defined for encoders.
