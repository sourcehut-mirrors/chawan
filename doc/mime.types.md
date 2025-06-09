<!-- MANON
% CHA-MIME.TYPES 5
MANOFF -->

# mime.types

Chawan uses the mime.types file to recognize certain file extensions for
matching mailcap entries. See the <!-- MANOFF -->[mailcap](mailcap.md)<!-- MANON --> <!-- MANON **cha-mailcap**(5) MANOFF -->
documentation for a description of mailcap.

## Search path

Chawan parses all mime.types files defined in `external.mime-types`. If no
mime.types file was found, the built-in mime type associations are used.

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

<!-- MANON
## See also

**cha**(1)
MANOFF -->
