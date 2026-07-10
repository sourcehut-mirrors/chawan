type
  SetEncodingResult* = enum
    seContinue, seStop

  DOMBuilderBase* = ref object of RootObj

  DOMBuilder*[Handle, Atom] = ref object of DOMBuilderBase
