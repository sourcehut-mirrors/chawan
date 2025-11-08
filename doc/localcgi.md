<!-- MANON
% CHA-LOCALCGI 5
MANOFF -->

# Local CGI support in Chawan

Chawan supports the invocation of CGI scripts placed in a directory
specified in the `external.cgi-dir` configuration option.  By default,
this is set to `$CHA_DIR/cgi-bin` (i.e.  `~/.chawan/cgi-bin` or
`~/.config/chawan/cgi-bin`, depending on `config.toml`'s location) and
`/usr/local/libexec/chawan/cgi-bin`.

A CGI script in one of these directories can be executed by visiting the URL
`cgi-bin:script-name`.  `$PATH_INFO` and `$QUERY_STRING` are set as normal,
i.e. `cgi-bin:script-name/abcd?defgh=ijkl` will set `$PATH_INFO` to `/abcd`,
and `$QUERY_STRING` to `defgh=ijkl`.

Further notes on processing CGI paths:

* The URL must be opaque, so you must not add a double slash after the scheme.
  e.g. `cgi-bin://script-name` will NOT work, only `cgi-bin:script-name`.
* Paths beginning with `/cgi-bin/` or `/$LIB/` are stripped of this segment
  automatically. So e.g. `cgi-bin:/cgi-bin/script-name` becomes
  `cgi-bin:script-name`.
* If `external.w3m-cgi-compat` is true, file: URLs are converted to
  `cgi-bin:` URLs if the path name starts with `/cgi-bin/`, `/$LIB/`, or the
  path of a local CGI script.  Note: this is unsafe, please do not use it
  unless you must.
* Absolute paths are accepted as e.g. `cgi-bin:/path/to/cgi/dir/script-name`.
  Note however, that this only works if `/path/to/cgi/dir` has already been
  specified as a CGI directory in `external.cgi-dir`.

## Headers

Local CGI scripts may send some headers that Chawan will interpret specially
(and thus will not pass forward to e.g. the fetch API, etc):

* `Status`: interpreted as the HTTP status code.
* `Cha-Control`: special header, see below.

These headers **must** be sent before any regular headers.  Headers received
after a regular header or a `Cha-Control: ControlDone` header will be
treated as regular headers.

The `Cha-Control` header's value is parsed as follows:

```
Cha-Control-Value = Command *Parameter
Command = ALPHA *ALPHA
Parameter = SPACE *CHAR
```

In other words, it is `Command [Param1] [Param2] ...`.

Currently available commands are:

* `Connected`: Takes no parameters.  Must be the first reported header;
  it means that connection to the server has been successfully established,
  but no data has been received yet.  When any other header is sent first,
  Chawan will act as if a `Cha-Control: Connected` header had been implicitly
  sent before that.

* `ConnectionError`: Must be the first reported header.  Parameter 1 is the
  error code, see below.  If any following parameters are given, they are
  concatenated to form a custom error message.

  Note: short but descriptive error messages are preferred, messages that
  do not fit on the screen are currently truncated.

* `ControlDone`: Signals that no more special headers will be sent; this
  means that `Cha-Control` and `Status` headers sent after this must be
  interpreted as regular headers (and thus e.g. will be available for JS
  code calling the script using the fetch API).

  WARNING: this header must be sent before any non-hardcoded headers that
  take external input.  For example, an HTTP client would have to send
  `Cha-Control: ControlDone` before returning the retrieved headers.

Following is a list of error codes and their string counterparts. CGI scripts
may use either (but not both) in a ConnectionError header.

* `1 InternalError`: An internal error prevented the script from retrieving
  the requested resource. CGI scripts can also use this to signal that they
  have no information on what went wrong.
* `2 InvalidMethod`: The client requested data using a method not supported
  by this protocol.
* `3 InvalidURL`: The request URL could not be interpreted as a valid URL
  for this format.
* `4 FileNotFound`: No file was found at the requested address, so the
  request is meaningless.  Note: this should only be used by protocols that
  do not rely on a client-server architecture, e.g. local file access, local
  databases, or peer-to-peer file retrieval mechanisms. A server responding
  with "no file found" is NOT a connection error, and is better represented
  as a response with a 404 status code.
* `5 ConnectionRefused`: The server refused to establish a connection.
* `6 ProxyRefusedToConnect`: The proxy refused to establish a connection.
* `7 FailedToResolveHost`: The hostname could not be resolved.
* `8 FailedToResolveProxy`: The proxy could not be resolved.
* `9 ProxyAuthFail`: The proxy refused the provided username/password.
* `10 InvalidResponse`: The server's response deviates from the
  specification so badly that it cannot be meaningfully processed.
* `11 ProxyInvalidResponse`: The proxy's response deviates from the
  specification so badly that it cannot be meaningfully processed.

## Environment variables

Chawan sets the following environment variables:

* `SERVER_SOFTWARE="Chawan"`
* `SERVER_PROTOCOL="HTTP/1.0"`
* `SERVER_NAME="localhost"`
* `SERVER_PORT="80"`
* `REMOTE_HOST="localhost"`
* `REMOTE_ADDR="127.0.0.1"`
* `GATEWAY_INTERFACE="CGI/1.1"`
* `SCRIPT_NAME="/cgi-bin/script-name"` if called with a relative path, and
  `"/path/to/script/script-name"` if called with an absolute path.
* `SCRIPT_FILENAME="/path/to/script/script-name"`
* `QUERY_STRING=` the query string (i.e. `URL.search`).  This variable is
  percent-encoded.
* `PATH_INFO=` everything after the script's path name,
  e.g. for `cgi-bin:script-name/abcd/efgh` `"/abcd/efgh"`.  This variable is
  NOT percent-encoded.
* `REQUEST_URI="$SCRIPT_NAME/$PATH_INFO?$QUERY_STRING`
* `REQUEST_METHOD=` HTTP method used for making the request, e.g. GET or POST
* `REQUEST_HEADERS=` A newline-separated list of all headers for this request.
* `CHA_LIBEXEC_DIR=` The libexec directory Chawan was configured to use at
  compile time.  See the [tools](#tools) section below for details on why
  this is useful.
* `CONTENT_TYPE=` for POST requests, the Content-Type header.  Not set for
  other request types (e.g. GET).
* `CONTENT_LENGTH=` the content length, if $CONTENT_TYPE has been set.
* `ALL_PROXY=` if a proxy has been set, the proxy URL.  WARNING: for
  security reasons, this **must** be respected when making external
  connections.  If a CGI script does not support proxies, it must never make
  any external connections when the `ALL_PROXY` variable is set, but rather
  return an error message.
* `HTTP_COOKIE=` if set, the Cookie header.
* `HTTP_REFERER=` if set, the Referer header.
* `CHA_TMP_DIR=` directory used for storing temporary files.
* `CHA_DIR=` location of the config file.

For requests originating from a urimethodmap rewrite, Chawan will also set
the parsed URL's parts as environment variables.  Use of these is highly
encouraged, to avoid exploits originating from double-parsing of URLs.

If `example://username:password@example.org:1234/path/name.html?example`
is the original URL, then:

* `MAPPED_URI_SCHEME=` the scheme of the original URL, in this case `example`.
* `MAPPED_URI_USERNAME=` the username part, in this case `username`.  If no
  username was specified, the variable is set to the empty string.
* `MAPPED_URI_PASSWORD=` the password part, in this case `password`.  If no
  password was specified, the variable is set to the empty string.
* `MAPPED_URI_HOST=` the host part, in this case `host.org` If no host was
  specified, the variable is set to the empty string. (An example of a URL
  with no host: `about:blank`, here `blank` is the path name.)
* `MAPPED_URI_PORT=` the port, in this case `1234`.  If no port was specified,
  the variable is set to the empty string.  (In this case, the CGI script is
  expected to use the default port for the scheme, if any.)
* `MAPPED_URI_PATH=` the path name, in this case `/path/name.html?example`.
  If no path was specified, the variable is set to the empty string.
  The path name is percent-encoded.
* `MAPPED_URI_QUERY=` the query string, in this case `example`.  Unlike in
  JavaScript, no question mark is prepended to the string.  The query string
  is percent-encoded as well.

The fragment part is omitted intentionally.

## Request body

If the request body is not empty, it is streamed into the program through
the standard input.

Note that this may be both an application/x-www-form-urlencoded or a
multipart/form-data request; `CONTENT_TYPE` stores information about the
request type, and in case of a multipart request, the boundary as well.

## Tools

Chawan provides certain helper binaries that may be useful for CGI
scripts.  These can be portably accessed by executing
`"$CHA_LIBEXEC_DIR"/[program]`.

Currently, the following tools are available:

* `urldec`: percent-decode strings passed on standard input.
* `urlenc`: percent-encode strings passed on standard input, taking a
  percent-encode set as the first parameter.

## Troubleshooting

Note that standard error is redirected to the browser console (by default,
M-cM-c).  This makes it easy to debug a misbehaving CGI script, but may also
slow down the browser in case of excessive logging.  If this is not the
desired behavior, wrap your script into a shell script that redirects stderr
to /dev/null.

### My script is returning a "Failed to execute script" error message.

This means the `execl` call to the script failed. Make sure that your CGI
script's executable bit is set, i.e. run `chmod +x /path/to/cgi/script`.

### My script is returning an "invalid CGI path" error message.

Make sure that you did not include leading slashes. Reminder:
`cgi-bin://script-name` does not work, use `cgi-bin:script-name`.

### My script is returning a "CGI file not found" error message.

Double check that your CGI script is in the correct location. Also, make
sure that you are not accidentally calling the script with an absolute path via
`cgi-bin:/script-name` (instead of the correct `cgi-bin:script-name`).

It is also possible that `external.cgi-dir` is not really set to the directory
your script is in. Note that by default, this depends on the binary's path,
so e.g. if your binary is in `~/src/chawan/target/release/bin/cha`, but you
put your CGI script to `/usr/local/libexec/chawan/cgi-bin`, then it will
not work.

### My script is returning a "failed to set up CGI script" error message.

This means that either `pipe` or `fork` failed.  Maybe you are running out
of memory?

<!-- MANON
## See also

**cha**(1) **cha-urimethodmap**(5)
MANOFF -->
