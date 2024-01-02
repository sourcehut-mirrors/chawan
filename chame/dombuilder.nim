import tags

type
  SetEncodingResult* = enum
    SET_ENCODING_CONTINUE, SET_ENCODING_STOP

  ParsedAttr*[Atom] = tuple
    prefix: NamespacePrefix
    namespace: Namespace
    name: Atom
    value: string

  DOMBuilderBase* = ref object of RootObj

  DOMBuilder*[Handle, Atom] = ref object of DOMBuilderBase
