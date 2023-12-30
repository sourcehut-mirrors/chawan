import parseerror
import tags

type
  SetEncodingResult* = enum
    SET_ENCODING_STOP, SET_ENCODING_CONTINUE

  ParsedAttr*[Atom] = tuple
    prefix: NamespacePrefix
    namespace: Namespace
    name: Atom
    value: string

  TokenAttr*[Atom] = tuple
    name: Atom
    value: string

  DOMBuilder*[Handle, Atom] = ref object of RootObj
    finish*: DOMBuilderFinish[Handle, Atom]
    ## May be nil.
    parseError*: DOMBuilderParseError[Handle, Atom]
    ## May be nil.
    setQuirksMode*: DOMBuilderSetQuirksMode[Handle, Atom]
    ## May be nil
    setEncoding*: DOMBuilderSetEncoding[Handle, Atom]
    ## May be nil.
    elementPopped*: DOMBuilderElementPopped[Handle, Atom]
    ## May be nil.
    getTemplateContent*: DOMBuilderGetTemplateContent[Handle, Atom]
    ## May be nil. (If nil, templates are treated as regular elements.)
    getNamespace*: DOMBuilderGetNamespace[Handle, Atom]
    ## May be nil. (If nil, the parser always uses the HTML namespace.)
    addAttrsIfMissing*: DOMBuilderAddAttrsIfMissing[Handle, Atom]
    ## May be nil. (If nil, some attributes may not be added to the HTML or
    ## BODY element if more than one of their respective opening tags exist.)
    setScriptAlreadyStarted*: DOMBuilderSetScriptAlreadyStarted[Handle, Atom]
    ## May be nil.
    associateWithForm*: DOMBuilderAssociateWithForm[Handle, Atom]
    ## May be nil.

  DOMBuilderFinish*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom]) {.nimcall.}
      ## Parsing has finished.

  DOMBuilderParseError*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], message: ParseError) {.nimcall.}
      ## Parse error. `message` is an error code either specified by the
      ## standard (in this case, message < LAST_SPECIFIED_ERROR) or named
      ## arbitrarily. (At the time of writing, only tokenizer errors have
      ## specified error codes.)

  DOMBuilderSetQuirksMode*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], quirksMode: QuirksMode) {.nimcall.}
      ## Set quirks mode to either QUIRKS or LIMITED_QUIRKS. NO_QUIRKS
      ## is the default and is therefore never used here.

  DOMBuilderSetEncoding*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], encoding: string): SetEncodingResult
        {.nimcall.}
      ## Called whenever a <meta charset=... or a <meta http-equiv=... tag
      ## containing a non-empty character set is encountered. A
      ## SetEncodingResult is expected, which is either SET_ENCODING_STOP,
      ## stopping the parser, or SET_ENCODING_CONTINUE, allowing the parser to
      ## continue.
      ##
      ## Note that htmlparser no longer contains any encoding-related logic;
      ## implementing this is left to the caller. (e.g. minidom_cs does this.)

  DOMBuilderElementPopped*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], element: Handle) {.nimcall.}
      ## Called when an element is popped from the stack of open elements
      ## (i.e. when it has been closed.)

  DOMBuilderGetTemplateContent*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], handle: Handle): Handle {.nimcall.}
      ## Retrieve a handle to the template element's contents.
      ## Note: this function must never return nil.

  DOMBuilderGetNamespace*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], handle: Handle): Namespace {.nimcall.}
      ## Retrieve the namespace of element.

  DOMBuilderAddAttrsIfMissing*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], element: Handle,
        attrs: seq[TokenAttr[Atom]]) {.nimcall.}
      ## Add the attributes in `attrs` to the element node `element`.
      ## This is called for HTML and BODY only.
      ##
      ## Pseudocode implementation:
      ## ```nim
      ## for attr in attrs:
      ##   if attr.name notin element.attrs:
      ##     element.attrs.add(attr)
      ## ```

  DOMBuilderSetScriptAlreadyStarted*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], script: Handle) {.nimcall.}
      ## Set the "already started" flag for the script element.
      ##
      ## Note: this flag is not togglable, so this callback should just set it
      ## to true.

  DOMBuilderAssociateWithForm*[Handle, Atom] =
    proc(builder: DOMBuilder[Handle, Atom], element, form, intendedParent: Handle)
        {.nimcall.}
      ## Called after createElement. Attempts to set form for form-associated
      ## elements.
      ##
      ## Note: the DOM builder is responsible for checking whether the
      ## intended parent and the form element are in the same tree.
