<!-- CHA-URIMETHODMAP 5 -->

# URI method map support in Chawan

Chawan can map unrecognized protocols to known protocols using the
*urimethodmap* format.

## Deprecation notice

*urimethodmap* is deprecated in favor of browsecap, which is strictly
more expressive.  See [**cha-mailcap**](mailcap.md)(5) for details.

Translating existing urimethodmap entries is done using the `cgioutput`
field for CGI entries, and the `uri` field for non-CGI entries.
For example, following urimethodmap file:

```
scheme1: /cgi-bin/blah.cgi?%s
scheme2: https://example.org/?%s
scheme3: /cgi-bin/scheme3.cgi
```

would map to the following browsecap entry:

```
# If the script takes the URI as QUERY_STRING, use `%u'.
scheme1; /cgi-bin/blah.cgi?%u; cgioutput
# If you're transparently mapping to another scheme, use `uri' with `resource'.
scheme2; https://example.org/?%s; uri; resource
# browsecap does not set `MAPPED_URI_...' variables.  Instead, you can
# either update the script to pass templates as arguments, or set the
# environment variables yourself:
scheme3; MAPPED_URI_HOST=%h \
	MAPPED_URI_PORT=%p \
	MAPPED_URI_PATH=%s \
	/cgi-bin/scheme3.cgi; cgioutput
```

The only non-trivial part of the migration is auth data; urimethodmap has
`$MAPPED_URI_USERNAME` and `$MAPPED_URI_PASSWORD`, but browsecap expects
scripts to parse the data from the `$HTTP_AUTHORIZATION` environment
variable (also available as `Authorization` in `$REQUEST_HEADERS`).
Alternatively, if you only need a username, use `$REMOTE_USER`.

## Search path

The search path for urimethodmap files can be overridden using the
configuration variable `external.urimethodmap`.

The default search path for urimethodmap files is:

```
$CHA_DIR/urimethodmap:$HOME/.urimethodmap:/etc/urimethodmap
```
## Format

The urimethodmap format is taken 1:1 from w3m, with some modifications to
the interpretation of templates.

A rough attempt at the formal description of this:

```
URIMethodMap-File = *URIMethodMap-line

URIMethodMap-Line = Comment / URIMethodMap-Entry

URIMethodMap-Entry = Protocol *WHITESPACE Template *WHITESPACE CR

Protocol = 1*CHAR COLON

Template = [see below]

Comment = *WHITESPACE CR / "#" *CHAR CR
```

Note that an ASCII colon sign (:) must be present after the protocol name.
However, the whitespace may be omitted.

Examples:

```
# This is ok:
protocol:	/cgi-bin/interpret-protocol?%s
# This is ok too:
protocol:/cgi-bin/interpret-protocol?%s
# Spaces and tabs are both allowed, so this is also ok:
protocol:	/cgi-bin/interpret-protocol?%s
# However, this is incorrect, because the colon sign is missing:
protocol	/cgi-bin/interpret-protocol?%s
```

The redirection template is the target URL.  If the string `%s` is contained
in the template, it will be replaced by the target URL.

For compatibility with w3m, templates starting with `/cgi-bin/` and
`file:/cgi-bin/` are special-cased and the starting string is replaced with
`cgi-bin:`.  So for example, the template `/cgi-bin/w3mdict.cgi` is the same
as `cgi-bin:w3mdict.cgi` (and so is `file:/cgi-bin/w3mdict.cgi`).

Example:

```
# The following are the same in Chawan
protocol:	/cgi-bin/interpret-protocol?%s
protocol:	file:/cgi-bin/interpret-protocol?%s
# Note: this last entry does not work in w3m.
protocol:	cgi-bin:interpret-protocol?%s
```

Note however that absolute paths to cgi scripts are NOT special cased, so
e.g. `file:///usr/local/libexec/w3m/cgi-bin/w3mdict.cgi` will simply open
w3mdict.cgi in the file viewer. (Unlike in w3m, where it could run
`w3mdict.cgi` depending on the user's configuration.)

## Examples

Following lines should be specified in `$CHA_DIR/urimethodmap` (where
`$CHA_DIR` is either ~/.chawan or ~/.config/chawan depending on where your
config.toml is).

### magnet.cgi

```
# Use the `magnet.cgi` CGI shell script to pass magnet links to Transmission.
magnet:		/cgi-bin/magnet.cgi?%s
```

`magnet.cgi` can be found in the `bonus/` directory. You can also write a
local CGI wrapper to pass the links to your BitTorrent client of choice.

### dict

In w3m, urimethodmap is commonly (ab)used to define shorthands for CGI scripts.

This works in Chawan too; for an example, you could define a `tl:` shorthand
like this:

```
# (trans.cgi is a script you can find and study in the bonus/ directory.)
tl:		/cgi-bin/trans.cgi?%s
```

Then, you could open the translation of any word using `tl:word`.

Note however that Chawan has a more powerful facility for substitution
shorthands like this in the form of omni-rules.  So if you want to redirect
to an online dictionary site with tl:word instead of providing a local CGI
interface, it is easier to just use omni-rules instead of urimethodmap +
local CGI redirection.

## See also

[**cha**](cha.md)(1) [**cha-cgi**](cgi.md)(5)
