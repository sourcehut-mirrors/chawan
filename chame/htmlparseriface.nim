## Interface definitions for htmlparser.
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

proc getLocalNameImpl(builder: DOMBuilderImpl, handle: HandleImpl): AtomImpl
  ## Retrieve the local name (also known as the tag name) of the element
  ## represented by `handle`.

#TODO perhaps add a separate createElement for SVG/MathML?
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
  ## attrs is a seq of the new elements attributes. For HTML elements, it
  ## only contains attributes with prefix NO_PREFIX and namespace NO_NAMESPACE;
  ## for adjusted attributes of embedded SVG/MathML elements, it may contain
  ## any other prefix and/or namespace.

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

proc getParentNodeImpl[Handle, Atom](builder: DOMBuilder[Handle, Atom],
    handle: Handle): Option[Handle] =
  return toDBImpl(builder).getParentNodeImpl(handle)

proc getLocalNameImpl[Handle, Atom](builder: DOMBuilder[Handle, Atom],
    handle: Handle): Atom =
  return toDBImpl(builder).getLocalNameImpl(handle)

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
