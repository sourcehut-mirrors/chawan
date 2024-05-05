when defined(nimdocdummy):
  ## Interface definitions for htmlparser.
  ##
  ## This exists to make implementing the DOMBuilder interface less painful. Two
  ## categories of hooks exist:
  ## 1. Mandatory hooks: these must be implemented by all users, or Chame will
  ##    not compile.
  ## 2. Optional hooks: these may be omitted if your DOM does not need
  ##    them. (You do not have to do anything special for this, just don't
  ##    implement them.)
  ##
  ## Usage:
  ## 1. Put a type clause with your generic types in your DOM builder interface:
  ##    ```nim
  ##    type
  ##      DOMBuilderImpl = MyDOMBuilder
  ##      AtomImpl = MyAtom
  ##      HandleImpl = MyHandle
  ##    ```
  ## 2. **Include** (**not** import) this file:
  ##    ```nim
  ##    include chame/htmlparseriface
  ##    ```
  ## 3. Implement all `*Impl` functions until the compiler no longer complains.
  ##
  ## Then you can call `parseHTML` with your custom DOMBuilder.
  ##
  ## You can also just implement the required functions without including
  ## this interface, but then you will have to do the casting from
  ## `DOMBuilder[HandleImpl, AtomImpl]` -> `DOMBuilderImpl` manually and will
  ## get uglier error messages when a function is missing.
  ##
  ## Note that when using this interface you can't use procs with different side
  ## effects than declared, so e.g. `func getDocumentImpl(...` **will not work**.
  ## You must use `proc getDocumentImpl(...` instead.
  ##
  ## Also, make sure that parameter names match the ones defined here,
  ## otherwise you are likely to get strange compilation errors.
  ##
  ## ## Optional hooks
  ## Following procedures are optional hooks; implementations of this interface
  ## can choose to leave them out without getting compilation errors.
  ##
  ##
  ## ```nim
  ## proc setQuirksModeImpl(builder: DOMBuilderBase, quirksMode: QuirksMode)
  ## ```
  ##
  ## Set quirks mode to either `QUIRKS` or `LIMITED_QUIRKS`. `NO_QUIRKS` is the
  ## default and is therefore never passed here.
  ##
  ##
  ## ```nim
  ## proc setEncodingImpl(builder: DOMBuilderBase, encoding: string):
  ##    SetEncodingResult
  ## ```
  ##
  ## Called whenever a <meta charset=... or a <meta http-equiv=... tag
  ## containing a non-empty character set is encountered. A SetEncodingResult
  ## return value is expected, which is either `SET_ENCODING_STOP`, stopping
  ## the parser, or `SET_ENCODING_CONTINUE`, allowing the parser to continue.
  ##
  ## Note that htmlparser no longer contains any encoding-related logic, not
  ## even UTF-8 validation. Implementing this is left to the caller. (For an
  ## example, see minidom_cs which implements decoding of all character sets
  ## in the WHATWG recommendation.)
  ##
  ##
  ## ```nim
  ## proc elementPoppedImpl(builder: DOMBuilderBase, handle: HandleImpl)
  ## ```
  ##
  ## Called when an element is popped from the stack of open elements
  ## (i.e. when it has been closed.)
  ##
  ##
  ## ```nim
  ## proc setScriptAlreadyStartedImpl(builder: DOMBuilderBase, handle: HandleImpl)
  ## ```
  ##
  ## Set the "already started" flag for the script element.
  ##
  ## Note: this flag is not togglable, so implementations of this callback
  ## should just set the flag to true.
  ##
  ##
  ## ```nim
  ## proc associateWithFormImpl(builder: DOMBuilderBase, element, form,
  ##    intendedParent: HandleImpl)
  ## ```
  ##
  ## Called after createElement. Attempts to set form for form-associated
  ## elements.
  ##
  ## Note: the DOM builder is responsible for checking whether the intended
  ## parent and the form element are in the same tree.
  # Dummy definitions
  import std/tables
  import htmlparser
  type
    HandleImpl = int
    AtomImpl = int
    DOMBuilderImpl = DOMBuilder[HandleImpl, AtomImpl]

# DOMBuilder
static:
  # DOMBuilderImpl must be an instance of DOMBuilder with the handle type
  # HandleImpl and atom type AtomImpl.
  doAssert DOMBuilderImpl is DOMBuilder[HandleImpl, AtomImpl]

converter toDOMBuilderImpl(dombuilder: DOMBuilder[HandleImpl, AtomImpl]):
    DOMBuilderImpl =
  return DOMBuilderImpl(dombuilder)

when defined(nimdocdummy):
  import std/macros

  macro doc(f: untyped) =
    f[0] = newNimNode(nnkPostfix).add(ident("*")).add(f[0])
    f
else:
  macro doc(f: untyped) = f

proc strToAtomImpl(builder: DOMBuilderImpl, s: string): AtomImpl {.doc.}
  ## Turn a string `s` into an Atom.
  ##
  ## This must always convert *every* string with the same value into the
  ## same Atom. We recommend using a hash table-based approach for this
  ## (see e.g. MAtomFactory).

proc tagTypeToAtomImpl(builder: DOMBuilderImpl, tagType: TagType): AtomImpl
    {.doc.}
  ## Turn a TagType `tagType` into an Atom.
  ##
  ## Every TagType `tagType` must always be converted into the same atom as
  ## that represented by its stringifier. An implementation could be:
  ## ```nim
  ## proc tagTypeToAtomImpl(builder: DOMBuilderImpl, tt: TagType): AtomImpl =
  ##   assert tt != TAG_UNKNOWN # parser never calls this with TAG_UNKNOWN.
  ##   return builder.strToAtomImpl($tt)
  ## ```

proc atomToTagTypeImpl(builder: DOMBuilderImpl, atom: AtomImpl): TagType {.doc.}
  ## Turn an Atom `atom` into a TagType. This is the inverse function of
  ## `tagTypeToAtomImpl`.

proc getDocumentImpl(builder: DOMBuilderImpl): HandleImpl {.doc.}
  ## Get the root document node's handle.
  ## This must not return nil, not even in the fragment parsing case.

proc getParentNodeImpl(builder: DOMBuilderImpl, handle: HandleImpl):
    Option[HandleImpl] {.doc.}
  ## Retrieve a handle to the parent node.
  ## May return none(Handle) if no parent node exists.

proc createHTMLElementImpl(builder: DOMBuilderImpl): HandleImpl {.doc.}
  ## Create a new <html> element node. The tag type of the created element must
  ## be TAG_HTML, and its namespace must be Namespace.HTML.
  ##
  ## This should not be confused with the "create an element for a token"
  ## step, which is not executed here.

proc createElementForTokenImpl(builder: DOMBuilderImpl, localName: AtomImpl,
    namespace: Namespace, intendedParent: HandleImpl,
    htmlAttrs: Table[AtomImpl, string], xmlAttrs: seq[ParsedAttr[AtomImpl]]):
    HandleImpl {.doc.}
  ## Create a new element node.
  ##
  ## `localName` is an Atom representing the tag name of the start token.
  ##
  ## Note that the parser determines the TagType of an element by its namespace
  ## and localName; for non-HTML elements it is always considered TAG_UNKNOWN.
  ##
  ## (However, tokens have no namespace, so TAG_SVG and TAG_MATHML can still
  ## used on them.)
  ##
  ## `namespace` is the namespace of the new element. For HTML elements,
  ## it's HTML; for embedded SVG/MathML elements, it is Namespace.SVG or
  ## Namespace.MATHML. No other namespace is used currently.
  ##
  ## `htmlAttrs` is a seq of the new elements attributes. It only contains
  ## attributes with prefix NO_PREFIX and namespace NO_NAMESPACE; adjusted
  ## foreign of embedded SVG/MathML elements that *do* have namespaces are
  ## *not* included, these can be found in `xmlAttrs`. All attribute names in
  ## `htmlAttrs` are guaranteed to be unique, but the parser makes no guarantees
  ## about the order of the attributes. (TODO maybe attrs should be a hash
  ## table after all?)
  ##
  ## `xmlAttrs` is a list of (XML) adjusted attributes. They are only set
  ## for elements in the MathML or SVG namespace, for which there are
  ## pre-defined attributes in the standard with names whose casing, namespace,
  ## and namespace prefixes must be adjusted by the parser.
  ##
  ## `intendedParent` is the intended parent of the element, as passed to the
  ## "create an element for a token" step. This may be used for looking up
  ## custom element definitions.
  ##
  ## Implementers of this function are encouraged to consult the
  ## [create an element for a token](https://html.spec.whatwg.org/multipage/parsing.html#create-an-element-for-the-token)
  ## section of the standard. In particular, steps 3 (Let document be intended
  ## parent's node document.) to 13 (If element is a resettable element...)
  ## should be implemented.
  ##
  ## Note that step 14. (If element is a form-associated element...) should
  ## *not* be implemented here. In fact, it is impossible to do so without
  ## access to the parser internals, so for this step, the parser will call
  ## associateWithFormImpl if all conditions (except "the intended parent is
  ## in the same tree as the element pointed to by the form element pointer")
  ## are fulfilled.

proc getLocalNameImpl(builder: DOMBuilderImpl, handle: HandleImpl): AtomImpl
    {.doc.}
  ## Retrieve the local name (also known as the tag name) of the element
  ## represented by `handle`.

proc getNamespaceImpl(builder: DOMBuilderImpl, handle: HandleImpl): Namespace
    {.doc.}
  ## Retrieve the namespace of element. For HTML elements, this should be
  ## `Namespace.HTML`. For embedded SVG or MathML elements, it should be
  ## `Namespace.SVG` or `Namespace.MathML`, respectively.
  ##
  ## (In general, you should just return the namespace that was passed to
  ## `createElement`.)

proc getTemplateContentImpl(builder: DOMBuilderImpl, handle: HandleImpl):
    HandleImpl {.doc.}
  ## Retrieve a handle to the template element's contents. Every element
  ## where `builder.atomToTagTypeImpl(element.localName)` equals TAG_TEMPLATE
  ## and `builder.getNamespaceImpl(element)` equals `Namespace.HTML` must have
  ## an associated "template contents" node which this function must return.

proc addAttrsIfMissingImpl(builder: DOMBuilderImpl, handle: HandleImpl,
    attrs: Table[AtomImpl, string]) {.doc.}
  ## Add the attributes in `attrs` to the element node `element`.
  ## This is only called with the HTML and BODY tags, when more than one
  ## exists in a document.
  ##
  ## Pseudocode implementation:
  ## ```nim
  ## for attr in attrs:
  ##   if attr.name notin element.attrs:
  ##     element.attrs.add(attr)
  ## ```

proc createCommentImpl(builder: DOMBuilderImpl, text: string): HandleImpl
    {.doc.}
  ## Create a new comment node. `text` is a string representing the new comment
  ## node's character data.

proc createDocumentTypeImpl(builder: DOMBuilderImpl, name, publicId,
    systemId: string): HandleImpl {.doc.}
  ## Create a new document type node.

proc insertBeforeImpl(builder: DOMBuilderImpl, parent, child: HandleImpl,
    before: Option[HandleImpl]) {.doc.}
  ## Insert node `child` before the node called `before`.
  ##
  ## If `before` is `none(Handle)`, `child` is expected to be appended to
  ## `parent`'s node list.
  ##
  ## If `child` is a text, and its previous sibling after insertion is a
  ## text as well, then they should be merged. `before` is never a
  ## text node (and thus never has to be merged).
  ##
  ## Note: parent may be either an Element or a Document node.

proc insertTextImpl(builder: DOMBuilderImpl, parent: HandleImpl, text: string,
    before: Option[HandleImpl]) {.doc.}
  ## Insert a text node at the specified location with contents `text`. If
  ## the specified location has a previous sibling that is a text node, no new
  ## text node should be created, but instead `text` should be appended to the
  ## previous sibling's character data (or if `before` is `none(Handle)`,
  ## to the last element).

proc removeImpl(builder: DOMBuilderImpl, child: HandleImpl) {.doc.}
  ## If `child` does not have a parent node, do nothing. Otherwise, remove
  ## `child` from its parent node.

proc moveChildrenImpl(builder: DOMBuilderImpl, fromNode, toNode: HandleImpl)
    {.doc.}
  ## Remove all children from the node `fromHandle`, then append them to
  ## `toHandle`.

when defined(nimdocdummy):
  # Dummy definitions
  proc strToAtomImpl(builder: DOMBuilderImpl, s: string): AtomImpl =
    discard

  proc tagTypeToAtomImpl(builder: DOMBuilderImpl, tagType: TagType): AtomImpl =
    discard

  proc atomToTagTypeImpl(builder: DOMBuilderImpl, atom: AtomImpl): TagType =
    discard

  proc getDocumentImpl(builder: DOMBuilderImpl): HandleImpl =
    discard

  proc getParentNodeImpl(builder: DOMBuilderImpl, handle: HandleImpl):
      Option[HandleImpl] =
    discard

  proc createHTMLElementImpl(builder: DOMBuilderImpl): HandleImpl = discard

  proc createElementForTokenImpl(builder: DOMBuilderImpl, localName: AtomImpl,
      namespace: Namespace, intendedParent: HandleImpl,
      htmlAttrs: Table[AtomImpl, string], xmlAttrs: seq[ParsedAttr[AtomImpl]]):
      HandleImpl = discard

  proc getLocalNameImpl(builder: DOMBuilderImpl, handle: HandleImpl): AtomImpl =
    discard

  proc getNamespaceImpl(builder: DOMBuilderImpl, handle: HandleImpl):
      Namespace =
    discard

  proc getTemplateContentImpl(builder: DOMBuilderImpl, handle: HandleImpl):
      HandleImpl =
    discard

  proc addAttrsIfMissingImpl(builder: DOMBuilderImpl, handle: HandleImpl,
      attrs: Table[AtomImpl, string]) =
    discard

  proc createCommentImpl(builder: DOMBuilderImpl, text: string): HandleImpl =
    discard

  proc createDocumentTypeImpl(builder: DOMBuilderImpl, name, publicId,
      systemId: string): HandleImpl =
    discard

  proc insertBeforeImpl(builder: DOMBuilderImpl, parent, child: HandleImpl,
      before: Option[HandleImpl]) =
    discard

  proc insertTextImpl(builder: DOMBuilderImpl, parent: HandleImpl, text: string,
      before: Option[HandleImpl]) =
    discard

  proc removeImpl(builder: DOMBuilderImpl, child: HandleImpl) =
    discard

  proc moveChildrenImpl(builder: DOMBuilderImpl, fromNode, toNode: HandleImpl) =
    discard
