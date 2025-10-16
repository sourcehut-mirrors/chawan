# Architecture of Chawan

This document describes some aspects of how Chawan works.

**Table of contents**

* [Module organization](#module-organization)
* [Process model](#process-model)
	* [Main process](#main-process)
	* [Forkserver](#forkserver)
	* [Loader](#loader)
	* [Buffer](#buffer)
* [Opening buffers](#opening-buffers)
* [Parsing HTML](#parsing-html)
* [JavaScript](#javascript)
	* [General](#general)
	* [JS in the pager](#js-in-the-pager)
	* [JS in the buffer](#js-in-the-buffer)
* [CSS](#css)
	* [Parsing, cascading](#parsing-cascading)
	* [Layout](#layout)
	* [Rendering](#rendering)

## Module organization

Explanation for the separate directories found in `src/`:

* config: configuration-related code. Mainly parsers for config files.
* css: CSS parsing, cascading, layout, rendering.
* html: DOM building, the DOM itself, forms, misc. JS APIs, etc. (It
  does not include the [HTML parser](https://git.sr.ht/~bptato/chame).)
* io: code for IPC, interaction with the file system, etc.
* local: code for the main process (i.e. the pager).
* server: code for processes other than the main process: buffer,
  forkserver, loader.
* types: mainly definitions of data types and things I didn't know where
  to put.
* utils: things I didn't know where to put part 2

Additionally, "adapters" of various protocols and file formats can be found in
`adapter/`:

* protocol: includes support for every protocol supported by Chawan.
* format: HTML converters for various text-based file formats,
  e.g. Markdown.
* img: image decoders and encoders. In general, these just read and
  output RGBA data through standard I/O (which may actually be a cache
  file; see the [image docs](image.md) for details).

## Process model

Described as a tree:

* cha (main process)
	- forkserver (forked immediately at startup)
		* loader
		* buffer(s)
		* local CGI scripts
	- mailcap processes (e.g. md2html, feh, ...)
	- editor (e.g. vi)

### Main process

The main process runs code related to the pager. This includes processing
user input, printing buffer contents to the screen, and managing buffers in
general. The complete list of buffers is only known to the main process.

Mailcap commands are executed by the main process. This depends on knowing the
content type of the resource, so the main process also reads in all network
headers of navigation responses before launching a buffer process. More on this
in [Opening buffers](#opening-buffers).

### Forkserver

For forking the loader process, buffer processes and CGI processes, a
fork server process is launched at the very beginning of every 'cha'
invocation.

We use a fork server for two reasons:

1. It helps clean up child processes when the main process crashes.
   (We open a UNIX domain socket between the main process and the fork
   server, and kill all child processes from the fork server on EOF.)
2. It allows us to start new buffer processes without cloning the
   pager's entire address space.  This reduces the impact of memory bugs
   somewhat, and also our memory usage.

For convenience reasons, the fork server is not used for mailcap
processes.

### Loader

The loader process takes requests from the main process and the buffer
processes. Then, depending on the scheme, it performs one of the
following steps:

* `cgi-bin:` Start a CGI script, and read out its stdout into the
  response body. In certain cases it also streams the response into
  the cache.  
  This is also used for schemes like http/s, ftp, etc. by internally
  rewriting them into the appropriate `cgi-bin:` URL.
* `stream:` Do the same thing as above, but read from a file descriptor
  passed to the loader beforehand. This is used when stdin is a file,
  e.g. `echo test | cha`. It is also used for mailcap entries with an
  x-htmloutput field.
* `cache:` Read the file from the cache. This is used by the pager
  for the "view source" operation, and by buffers in the rare situation
  where their initial character encoding guess proves to be incorrect
  and they need to rewind the source.
* `data:` Decode a data URL. This is done directly in the loader process
  because very long data URLs wouldn't fit into the environment. (Plus,
  obviously, it's more efficient this way.)

The loader process distinguishes between clients (i.e processes) through
their control stream (one end of a socketpair created by loader).
This control stream is closed when the pager discards the buffer, so
discarded buffers are unable to make further requests even if their
process is still alive.

### Buffer

Buffer processes parse HTML, optionally query external resources from
loader, run styling, JS, and finally render the page to an internal
canvas.

Buffers are managed by the pager through Container objects. A UNIX
domain socket is established between each buffer and the pager for
IPC.

## Opening buffers

Scenario: the user attempts to navigate to <https://example.org>.

1. pager creates a new container for the target URL.
2. pager sends a request for "https://example.org" to the loader. Then,
   it registers the file descriptor in its selector, and does something
   else until poll() reports activity on the file descriptor.
3. loader rewrites "https://example.org" into "cgi-bin:http". It then
   runs the http CGI script with the appropriate environment variables
   set to parts of this URL and request headers.
4. The http CGI script opens a connection to example.org. When
   connected, it starts writing headers it receives to stdout.
5. loader parses these headers, and sends them to pager.
6. pager reads in the headers, and decides what to do based on the
   Content-Type:
	* If Content-Type is found in mailcap, then the response body
	  is piped into the command in that mailcap entry. If the
	  entry has x-htmloutput, then the command's stdout is taken
	  instead of the response body, and Content-Type is set to
	  text/html. Otherwise, the container is discarded.
	* If Content-Type is text/html, then a new buffer process is
	  created, which then parses the response body as HTML. If it
	  is any `text/*` subtype, then the response is simply inserted
	  into a `<plaintext>` tag.
	* If Content-Type is not a `text/*` subtype, and no mailcap
	  entry for it is found, then the user is prompted about where
	  they wish to save the file.

## Cache

Chawan's caching mechanism is largely inspired by that of w3m, which
does not have a network cache. Instead, it simply saves source files
to the disk before displaying them, and lets users view/edit the source
without another network request.

The only difference in Chawan is that it simultaneously streams files
to the cache *and* buffers:

1. Client (pager or buffer) initiates request by sending a message to
   loader.
2. Loader starts CGI script, reads headers, sends a response, and waits.
3. Client now may send an "addCacheFile" message, which prompts loader
   to add a cache file for this request.
4. Client sends "resume", now loader will stream the response both to
   the client and the cache.

Cached items may be shared between clients; this is how rewinding on
wrong charset guess is implemented. They are also manually reference
counted and are unlinked when their reference count drops to zero.

The cache is used in the following ways:

* For view source and edit source operations.
* For rewinding buffers on incorrect charset guess. (In practice,
  this is almost never used, because the first chunk we read tends to
  determine the charset unambiguously.)
* For reading images multiple times after download. (At least two reads
  are needed, because the first pass only parses the headers.)
* As a memory buffer for image coding processes to mmap. (For details,
  see [image.md](image.md).)

Crucially, the cache *does not* understand Cache-Control headers, and
will never skip a download when requested by a user. Similarly, loading
a "cache:" URL (e.g. view source) is guaranteed to never make a network
request.

Future directions: for non-JS buffers, we could kill idle processes and
reload them on-demand from the cache. This could solve the problem of
spawning too many processes that then do nothing.

## Parsing HTML

The character decoder and the HTML parser are implementations of the
WHATWG standards, and are available as
[separate](https://git.sr.ht/~bptato/chagashi)
[libraries](https://git.sr.ht/~bptato/chame).

Buffer processes decode and parse HTML documents asynchronously. When
bytes from the network are exhausted, the buffer will 1) partially
render the current document as-is, 2) return it to the pager so that the
user can interact with the document.

Character encoding detection is rather primitive; the list specified in
`encoding.document-charset` is enumerated until either no errors are
produced by the decoder, or no more charsets exist. In some extremely
rare edge cases, the document is re-downloaded from the cache, but this
pretty much never happens. (The most common case is that the UTF-8
validator just runs through the entire document without reporting
errors.)

The HTML parser then consumes the decoded (or validated) input buffer.
In some cases, a script calls document.write and then the parser is
called recursively. (Debugging this is not very fun.)

## JavaScript

QuickJS is used by both the pager as a scripting language, and by
buffers for running on-page scripts when JavaScript is enabled.

The core JS related functionality has been separated out into the
[Monoucha](https://git.sr.ht/~bptato/monoucha) library, so it can be
used outside of Chawan too.

### General

To avoid having to type out all the type conversion & error handling
code manually, we have JS pragmas to automagically turn Nim procedures
into JavaScript functions. (For details on the specific pragmas, see the
[manual](https://git.sr.ht/~bptato/monoucha/tree/master/doc/manual.md).)

Still, sometimes we have to deal with JSValues manually; in this case,
the fromJS and toJS functions are used.  fromJS in particular returns an
Opt[void], and uses a var parameter for overloading and efficient
returns.

### JS in the pager

Keybindings can be assigned JavaScript functions in the config, and
then the pager executes those when the keybindings are pressed.

Also, contents of the start.startup-script option are executed at
startup. This is used when `cha` is called with the `-r` flag.

There *is* an API, described at [api.md](api.md). Web APIs are exposed
to pager too, but you cannot operate on the DOMs themselves from the
pager, unless you create one yourself with DOMParser.parseFromString.

[config.md](config.md) describes all commands that are used in the
default config.

### JS in the buffer

The DOM is implemented through the same wrappers as those in pager,
except the pager modules are not exposed to buffer JS.

Aside from document.write, it is mostly straightforward, and usually
works OK, though too many things are missing to really make it useful.

As for document.write: don't ask. It works as far as I can tell, but
I wouldn't know why.

## CSS

css/ contains CSS parsing, cascading, layout, and rendering.

Note that CSS (at least 2.0 and onward) was designed for pixel-based
displays, not for character-based ones. So we have to round a lot,
and sometimes this goes wrong. (This is mostly solved by the omission of
certain problematic properties and some heuristics in the layout engine.)

Also, some (now) commonly used features like CSS grid are not
implemented yet, so websites using those look ugly.

### Parsing, cascading

The parser is not very interesting, it's just an implementation of the
CSS 3 parsing module. The latest iteration of the selector parser is
pretty good. The media query parser and the CSS value parser both work
OK, but are missing some commonly used features like variables.

Cascading works OK.  To speed up selector matching, various properties
are hashed to filter out irrelevant CSS rules.  However, no further
style optimization exists yet (such as Bloom filters or style
interning).

Style calculation is incremental, and results are cached until an
element's style is invalidated, so re-styles are quite fast.  (The
invalidation logic is primitive, but as far as I can tell, it's good
enough in most cases.)

### Layout

Layout runs whenever a page is loaded, or some action (e.g. hover, DOM
change by JS, etc.) invalidates the page currently visible to the user.

Our layout engine is a "simple" procedural implementation which consists of
two passes:

1. css/csstree.nim: build a layout tree, possibly reusing the tree from the
   previous layout.  Anonymous block and table boxes are generated here.
   After this pass, the tree is no longer mutated, only the `state` and
   `render` fields of the respective boxes.

2. css/layout.nim: position said boxes, always relative to their parent.
   This pass takes `input` and compares it with input previously taken; if
   they differ, it recurses through its children and then stores the box
   size and other output in `state`.

   But if `input` is the same as in the previous pass and `keepLayout`
   wasn't unset, it is assumed that layout for the subtree has not changed,
   and it is simply skipped (for the box itself as well as for all its
   children.)

In practice, step 2 is often repeated for subsections of the tree to resolve
cyclic dependencies in CSS layout (e.g. in table, flex).  However, this
rarely results in quadratic behavior thanks to the aforementioned caching
mechanism.

### Rendering

After layout is finished, the document is rendered onto a text-based
canvas, which is represented as a sequence of strings associated with
their formatting.  (Right now, "formatting" also includes a reference to
the respective DOM nodes; in the future, it won't.)

Additionally, boxes are assigned an offset in the `render` field here,
which is used when jumping to anchors.

The entire document is rendered, which is a performance bottleneck in some
cases.  (Styling is usually slower, as well as layout (usually), but those
are cached.  Rendering isn't, but all it really does is just copying around
a bunch of strings so it's not that bad.)

The positive side of this design is that search is very simple (and
fast), since we are just running regexes over a linear sequence of
strings.
