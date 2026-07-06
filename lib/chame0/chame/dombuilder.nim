type
  SetEncodingResult* = enum
    SET_ENCODING_CONTINUE, SET_ENCODING_STOP

  DOMBuilderBase* = ref object of RootObj

  DOMBuilder*[Handle, Atom] = ref object of DOMBuilderBase
