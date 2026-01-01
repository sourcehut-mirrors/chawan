<!-- CHA-MIME.TYPES 5 -->

# mime.types

Chawan uses the mime.types file to map file extensions to MIME types (also
known as `Content-Type`).

MIME types in turn are used by mailcap to decide how to present a certain
file to the user (display as text, use external viewer, save, etc.)
See [**cha-mailcap**](mailcap.md)(5) for details of how that works.

## Search path

Chawan parses all mime.types files defined in `external.mime-types`.  When
no mime.types file is found, the built-in MIME type associations are used.

The default search path for mime.types files is:

```
$HOME/.mime.types:/etc/mime.types:/usr/etc/mime.types:/usr/local/etc/mime.types
```

## Format

The mime.types file is a list of whitespace-separated columns. The first
column represents the mime type, all following columns are file extensions.

Lines starting with a hash character (#) are recognized as comments, and
are ignored.

Example:

```
# comment
application/x-example	exmpl	ex
```

This mime.types file would register the file extensions "exmpl" and "ex"
to be recognized as the mime type `application/x-example`.

## Note

Chawan only uses mime.types files for finding mailcap entries; buffers use an
internal mime.types file for content type detection instead.

The default mime.types file only includes file formats that buffers can handle,
which is rather limited (at the time of writing, 7 file formats). Therefore it
is highly recommended to configure at least one external mime.types file if you
use mailcap.

## See also

[**cha**](cha.md)(1) [**cha-mailcap**](mailcap.md)(5)
