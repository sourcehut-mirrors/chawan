<!-- CHA 1 -->

# NAME

cha - the Chawan text-mode browser

# SYNOPSIS

**cha** [**options**] [*URL(s)* or *file(s)*...]

# DESCRIPTION

Chawan is a text-mode browser.  It can be used as a pager, or as a
web/(S)FTP/gopher/gemini/file browser.  It understands HTML and CSS,
and when enabled by the user, can also execute JavaScript and display
images (on terminals supporting Sixel or the Kitty image protocol.)

Chawan can also be used as a general text-based document viewer as
described in **cha-mailcap**(5), or as a hyperlinked man page viewer
using **mancha**(1).

This document describes the invocation of Chawan.  For a list of default
keybindings, type *cha about:chawan*.  For a detailed description of
the configuration format, see **cha-config**(5).

# ARGUMENTS

On invocation, Chawan attempts to open all URL/file arguments supplied.
If no URLs could successfully be opened, Chawan exits automatically.

Chawan may also be started without specifying a file, if a file is
provided through a pipe.  In this case, you can specify the content type
using the **\-T** switch.

# OPTIONS

All command line options have short forms (e.g. **\-d**) and long
forms (e.g. **\-\-dump**).

Long forms must be introduced with two dashes; when only a single
dash is provided, each letter is parsed as a separate short form.

In short form, it is also valid to provide values to arguments without a
subsequent space.  For example, **\-obuffer.images=true** is valid.

**\-c**, **\-\-css** *stylesheet*

: Temporarily modify the user stylesheet.  If a user stylesheet is
  already being used, the stylesheet given is appended to that.

**\-d**, **\-\-dump**

: Start in headless mode, and sequentially print the opened files to
  stdout.  This option is implicitly enabled if stdout is not a tty
  (e.g. when piping *cha* output).

**\-h**, **\-\-help**

: Print a short version of this page, then exit.

**\-o**, **\-\-opt** *config*

: Pass temporary configuration options.  This accepts the configuration
  format described in **cha-config**(5), so the passed string must
  be valid TOML.

    To ease specifying string parameters, unrecognized bare keywords
    are converted to strings.  So this works:

    **\-\-opt** display.color-mode=*eight-bit*.

    However, symbols and words starting with a number must still be
    quoted, i.e. you have to quote them twice to bypass shell quoting.

**\-r**, **\-\-run** *script*/*file*

: Execute the string provided as a JS script, or execute the supplied JS
  file.  If the file ends in .mjs, it is executed as an ES module.

**\-v**, **\-\-version**

: Print information about the browser's version, then exit.

**\-C**, **\-\-config** *file*

: Override the default configuration search path.  Both absolute and
  relative paths are allowed.

**\-I**, **\-\-input-charset** *charset*

: Override the character set of all input files.  Useful when Chawan is
  incorrectly recognizing the input character set.

    (If this happens often, consider changing the default input charset
    recognition list *encoding.document-charset* in the configuration.)

**\-M**, **\-\-monochrome**

: Force monochrome output.  Formatting (bold/italic/etc.) is not
  affected.  This is a shortcut for **\-o**
  display.color\-mode=*monochrome*.

**\-O**, **\-\-output-charset** *charset*

: Override the output character set.  This is a shortcut for **\-o**
  encoding.display\-charset=*charset*.

**\-T**, **\-\-type** *content-type*

: Override the content type of all input files.  Useful when the content
  type cannot be guessed from the file extension, or when reading a
  non-plaintext file from stdin.

**\-V**, **\-\-visual**

: When no files/URLs are passed, open the page specified in
  *start.visual-home* instead of printing a help screen.

**\-\-**

: Interpret all following arguments as files.  For example, you can
  open a file named *\-o*, using *cha* **\-\-** *\-o*.

# ENVIRONMENT

Certain environment variables are read and used by Chawan.

**TMPDIR**

: When set, the default configuration stores temporary files inside this
  directory (and */tmp/cha-tmp-user* otherwise.)

**HTTP_HOME**, **WWW_HOME**

: When set, Chawan starts in visual mode by default and opens the page
  specified by one of these variables.  **HTTP_HOME** takes precedence
  over **WWW_HOME**.

**CHA_DIR**

: When set, it switches the configuration directory to the path specified.

**COLORTERM**

: When set to *24bit* or *truecolor*, and the *display.color-mode*
  configuration option is set to *auto*, Chawan sets the color mode to
  true color.

**TERM**

: Used by Chawan to adjust to terminal-specific quirks.  When not
  set, defaults to *xterm*.

**VISUAL**, **EDITOR**

: Used to determine the editor to use when the *external.editor*
  configuration option is not set.

**LINES**, **COLUMNS**

: Used as fallback values when window size detection fails.

# SEE ALSO

[**mancha**](mancha.md)(1), [**cha\-config**](config.md)(5),
[**cha\-mailcap**](mailcap.md)(5), [**cha\-mime.types**](mime.types.md)(5),
[**cha\-cgi**](cgi.md)(5), [**cha\-urimethodmap**](urimethodmap.md)(5),
[**cha\-protocols**](protocols.md)(7), [**cha\-image**](image.md)(7),
[**cha\-css**](css.md)(7), [**cha\-troubleshooting**](troubleshooting.md)(7),
[**cha\-terminal**](terminal.md)(7)
