## Interface definitions for htmlparser.
##
## This exists to make implementing the DOMBuilder interface less painful. Two
## categories of hooks exist:
## 1. Mandatory hooks: these must be implemented using static dispatch as procs.
##    Not implementing any of them will result in a compilation error.
## 2. Optional hooks: these may be omitted if your DOM does not need them. They
##    are implemented using dynamic dispatch as methods, so we can provide
##    a default implementation (that does nothing).
##
## Usage:
## 1. Put a type clause with your generic types in your DOM builder interface:
## ```nim
## type
##   DOMBuilderImpl = MyDOMBuilder
##   AtomImpl = MyAtom
##   HandleImpl = MyHandle
## ```
## 2. **Include** (**not** import) this file:
## ```nim
## include chame/htmlparseriface
## ```
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

import parseerror

# DOMBuilder
static:
  # DOMBuilderImpl must be an instance of DOMBuilder with the handle type
  # HandleImpl and atom type AtomImpl.
  doAssert DOMBuilderImpl is DOMBuilder[HandleImpl, AtomImpl]

proc strToAtomImpl(builder: DOMBuilderImpl, s: string): AtomImpl
  ## Turn a string `s` into an Atom.
  ##
  ## This must always convert *every* string with the same value into the
  ## same Atom. We recommend using a hash table-based approach for this
  ## (see e.g. MAtomFactory).

proc tagTypeToAtomImpl(builder: DOMBuilderImpl, tagType: TagType): AtomImpl
  ## Turn a TagType `tagType` into an Atom.
  ##
  ## Every TagType `tagType` must always be converted into the same atom as
  ## that represented by its stringifier. So an example implementation could be:
  ## ```nim
  ## proc tagTypeToAtomImpl(builder: DOMBuilderImpl, tt: TagType): AtomImpl =
  ##   assert tt != TAG_UNKNOWN # parser never calls this with TAG_UNKNOWN.
  ##   return builder.strToAtomImpl($tt)
  ## ```

proc atomToTagTypeImpl(builder: DOMBuilderImpl, atom: AtomImpl): TagType
  ## Turn an Atom `atom` into a TagType. This is the inverse function of
  ## `tagTypeToAtomImpl`.

proc getDocumentImpl(builder: DOMBuilderImpl): HandleImpl
  ## Get the root document node's handle.
  ## This must not return nil, not even in the fragment parsing case.

proc getParentNodeImpl(builder: DOMBuilderImpl, handle: HandleImpl):
    Option[HandleImpl]
  ## Retrieve a handle to the parent node.
  ## May return none(Handle) if no parent node exists.

#TODO use a separate "addAdjustedAttrs" for SVG/MathML
proc createElementImpl(builder: DOMBuilderImpl, localName: AtomImpl,
    namespace: Namespace, attrs: seq[ParsedAttr[AtomImpl]]): HandleImpl
  ## Create a new element node.
  ##
  ## `localName` is an Atom representing the tag name of the start token.
  ##
  ## `namespace` is the namespace of the new element. For HTML elements,
  ## it's HTML; for embedded SVG/MathML elements, it is Namespace.SVG or
  ## Namespace.MATHML. No other namespace is used currently.
  ##
  ## `attrs` is a seq of the new elements attributes. For HTML elements, it
  ## only contains attributes with prefix NO_PREFIX and namespace NO_NAMESPACE;
  ## for adjusted attributes of embedded SVG/MathML elements, it may contain
  ## any other prefix and/or namespace.
  ##
  ## Note that the parser determines the TagType of an element by its namespace
  ## and localName; for non-HTML elements it is always considered TAG_UNKNOWN.
  ##
  ## (This technically means that TAG_SVG and TAG_MATH are not valid element tag
  ## types by the parser. Practically, these tags are only used on tokens, which
  ## have no namespace.)

proc getLocalNameImpl(builder: DOMBuilderImpl, handle: HandleImpl): AtomImpl
  ## Retrieve the local name (also known as the tag name) of the element
  ## represented by `handle`.

proc getNamespaceImpl(builder: DOMBuilderImpl, handle: HandleImpl): Namespace
  ## Retrieve the namespace of element. For HTML elements, this should be
  ## `Namespace.HTML`. For embedded SVG or MathML elements, it should be
  ## `Namespace.SVG` or `Namespace.MathML`, respectively.
  ##
  ## (In general, you should just return the namespace that was passed to
  ## `createElement`.)

proc getTemplateContentImpl(builder: DOMBuilderImpl, handle: HandleImpl):
    HandleImpl
  ## Retrieve a handle to the template element's contents. Every element
  ## where `builder.atomToTagTypeImpl(element.localName)` equals TAG_TEMPLATE
  ## and `builder.getNamespaceImpl(element)` equals `Namespace.HTML` must have
  ## an associated "template contents" node which this function must return.

proc createCommentImpl(builder: DOMBuilderImpl, text: string): HandleImpl
  ## Create a new comment node. `text` is a string representing the new comment
  ## node's character data.

proc createDocumentTypeImpl(builder: DOMBuilderImpl, name, publicId,
    systemId: string): HandleImpl
  ## Create a new document type node.

proc insertBeforeImpl(builder: DOMBuilderImpl, parent, child: HandleImpl,
    before: Option[HandleImpl])
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
    before: Option[HandleImpl])
  ## Insert a text node at the specified location with contents `text`. If
  ## the specified location has a previous sibling that is a text node, no new
  ## text node should be created, but instead `text` should be appended to the
  ## previous sibling's character data (or if `before` is `none(Handle)`,
  ## to the last element).

proc removeImpl(builder: DOMBuilderImpl, child: HandleImpl)
  ## If `child` does not have a parent node, do nothing. Otherwise, remove
  ## `child` from its parent node.

proc moveChildrenImpl(builder: DOMBuilderImpl, fromNode, toNode: HandleImpl)
  ## Remove all children from the node `fromHandle`, then append them to
  ## `toHandle`.

# Optional hooks (implemented using dynamic dispatch)
#
# Generic methods are not supported, so we cheat.
# The idea is that we define a base method on a non-generic ancestor of
# DOMBuilderImpl. Then users interested in implementing the hook just override
# it with their own implementation on DOMBuilderImpl (which is also not
# generic).
#TODO but this cannot be statically detected... would be nice to figure out
# something for this...
method parseErrorImpl(builder: DOMBuilderBase, e: ParseError) {.base.} =
  ## Optional hook.
  ##
  ## Parse error. `message` is an error code either specified by the
  ## standard (in this case, `e` < `LAST_SPECIFIED_ERROR`) or named
  ## arbitrarily. (At the time of writing, only tokenizer errors have
  ## specified error codes.)
  discard

method setQuirksModeImpl(builder: DOMBuilderBase, quirksMode: QuirksMode)
    {.base.} =
  ## Optional hook.
  ##
  ## Set quirks mode to either `QUIRKS` or `LIMITED_QUIRKS`. `NO_QUIRKS` is the
  ## default and is therefore never passed here.
  discard

method setEncodingImpl(builder: DOMBuilderBase, encoding: string):
    SetEncodingResult {.base.} =
  ## Optional hook.
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
  return SET_ENCODING_CONTINUE

method elementPoppedImpl(builder: DOMBuilderBase, handle: HandleImpl) {.base.} =
  ## Optional hook.
  ##
  ## Called when an element is popped from the stack of open elements
  ## (i.e. when it has been closed.)
  discard

method addAttrsIfMissingImpl(builder: DOMBuilderBase, handle: HandleImpl,
    attrs: seq[TokenAttr[AtomImpl]]) {.base.} =
  ## Optional hook.
  ##
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
  discard

method setScriptAlreadyStartedImpl(builder: DOMBuilderBase, handle: HandleImpl)
    {.base.} =
  ## Set the "already started" flag for the script element.
  ##
  ## Note: this flag is not togglable, so implementations of this callback
  ## should just set the flag to true.
  discard

method associateWithFormImpl(builder: DOMBuilderBase, element, form,
    intendedParent: HandleImpl) {.base.} =
  ## Called after createElement. Attempts to set form for form-associated
  ## elements.
  ##
  ## Note: the DOM builder is responsible for checking whether the intended
  ## parent and the form element are in the same tree.
  discard

# Declarations for the parser. These casts are safe, as checked by the static
# assertion above.
template toDBImpl(builder: typed): DOMBuilderImpl =
  cast[DOMBuilderImpl](builder)

proc strToAtomImpl[Handle, Atom](builder: DOMBuilder[Handle, Atom],
    s: string): Atom =
  return toDBImpl(builder).strToAtomImpl(s)

proc tagTypeToAtomImpl[Handle, Atom](builder: DOMBuilder[Handle, Atom],
    tagType: TagType): Atom =
  return toDBImpl(builder).tagTypeToAtomImpl(tagType)

proc atomToTagTypeImpl[Handle, Atom](builder: DOMBuilder[Handle, Atom],
    atom: Atom): TagType =
  return toDBImpl(builder).atomToTagTypeImpl(atom)

proc getDocumentImpl[Handle, Atom](builder: DOMBuilder[Handle, Atom]): Handle =
  return toDBImpl(builder).getDocumentImpl()

proc getLocalNameImpl[Handle, Atom](builder: DOMBuilder[Handle, Atom],
    handle: Handle): Atom =
  return toDBImpl(builder).getLocalNameImpl(handle)

proc getNamespaceImpl[Handle, Atom](builder: DOMBuilder[Handle, Atom],
    handle: Handle): Namespace =
  return toDBImpl(builder).getNamespaceImpl(handle)

proc getTemplateContentImpl[Handle, Atom](builder: DOMBuilder[Handle, Atom],
    handle: Handle): Handle =
  return toDBImpl(builder).getTemplateContentImpl(handle)

proc getParentNodeImpl[Handle, Atom](builder: DOMBuilder[Handle, Atom],
    handle: Handle): Option[Handle] =
  return toDBImpl(builder).getParentNodeImpl(handle)

proc createElementImpl(builder: DOMBuilderImpl, localName: AtomImpl,
    namespace: Namespace, attrs: seq[ParsedAttr[AtomImpl]]): HandleImpl =
  return toDBImpl(builder).createElementImpl(localName, namespace, attrs)

proc createCommentImpl[Handle, Atom](builder: DOMBuilder[Handle, Atom],
    text: string): Handle =
  return toDBImpl(builder).createCommentImpl(text)

proc createDocumentTypeImpl[Handle, Atom](builder: DOMBuilder[Handle, Atom],
    name, publicId, systemId: string): Handle =
  return toDBImpl(builder).createDocumentTypeImpl(name, publicId, systemId)

proc insertBeforeImpl[Handle, Atom](builder: DOMBuilder[Handle, Atom],
    parent, node: Handle, before: Option[Handle]) =
  toDBImpl(builder).insertBeforeImpl(parent, node, before)

proc insertTextImpl[Handle, Atom](builder: DOMBuilder[Handle, Atom],
    parent: Handle, text: string, before: Option[Handle]) =
  toDBImpl(builder).insertTextImpl(parent, text, before)

proc removeImpl[Handle, Atom](builder: DOMBuilder[Handle, Atom],
    child: Handle) =
  toDBImpl(builder).removeImpl(child)

proc moveChildrenImpl[Handle, Atom](builder: DOMBuilder[Handle, Atom],
    fromNode, toNode: Handle) =
  toDBImpl(builder).moveChildrenImpl(fromNode, toNode)
