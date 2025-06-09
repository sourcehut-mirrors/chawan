<!-- MANON
% CHA-URIMETHODMAP 5
MANOFF -->

# URI method map support in Chawan

Chawan can be used to map unrecognized protocols to known protocols using the
`urimethodmap` format.

The main use case for this is implementing handlers to protocols unknown to
Chawan through a protocol that the browser *does* understand.

## Search path

The search path for urimethodmap files can be overridden using the
configuration variable `external.urimethodmap`.

The default search path for urimethodmap files is:

```
$HOME/.urimethodmap:$HOME/.w3m/urimethodmap:/etc/urimethodmap:/usr/local/etc/urimethodmap
```
## Format

The urimethodmap format is taken 1:1 from w3m, with only some modifications
to the interpretation of templates.

A rough attempt at the formal description of this:

```
URIMethodMap-File = *URIMethodMap-line

URIMethodMap-Line = Comment / URIMethodMap-Entry

URIMethodMap-Entry = Protocol *WHITESPACE Template *WHITESPACE CR

Protocol = 1*CHAR COLON

Template = [see below]

Comment = *WHITESPACE CR / "#" *CHAR CR
```

Note that an ASCII colon sign (:) must be present after the protocol
name. However, the whitespace may be omitted.

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

The redirection template is the target URL. If the string `%s` is contained
in the template, it will be replaced by the target URL.

Note: Chawan used to URL-encode the substituted URL in the past, but this is
no longer the case.

For compatibility with w3m, templates starting with `/cgi-bin/` and
`file:/cgi-bin/` are special-cased and the starting string is replaced with
`cgi-bin:`. So for example, the template `/cgi-bin/w3mdict.cgi` is the same as
`cgi-bin:w3mdict.cgi` (and so is `file:/cgi-bin/w3mdict.cgi`).

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

### In config.toml

```
# Following sets the urimethodmap search path to the path relative to the
# configuration file. So if your configuration file is in
# ~/.config/chawan/config.toml, Chawan will use ~/.config/chawan/urimethodmap.
# If it's in ~/.chawan/config.toml, then it uses ~/.chawan/urimethodmap.
[external]
urimethodmap = "urimethodmap"
```

### In urimethodmap

#### magnet.cgi

```
# Use the `magnet.cgi` CGI shell script to pass magnet links to Transmission.
magnet:		/cgi-bin/magnet.cgi?%s
```

`magnet.cgi` can be found in the `bonus/` directory. You can also write a
local CGI wrapper to pass the links to your BitTorrent client of choice.

#### dict

In w3m, urimethodmap is commonly (ab)used to define shorthands for CGI scripts.

This works in Chawan too; for an example, you could define a `tl:` shorthand
like this:

```
# (trans.cgi is a script you can find and study in the bonus/ directory.)
tl:		/cgi-bin/trans.cgi?%s
```

Then, you could open the translation of any word using `tl:word`.

Note however that Chawan has a more powerful facility for substitution
shorthands like this in the form of omni-rules. So if you want to redirect
to an on-line dictionary site with tl:word instead of providing a local
CGI interface, it is probably easier to just use omni-rules instead of
urimethodmap + local CGI redirection.

Rule of thumb: if you find yourself writing local CGI scripts that just
send a `Location:` header, maybe consider just using an omni-rule.

<!-- MANON

## See also

**cha**(1) **cha-localcgi**(5)
MANOFF -->
