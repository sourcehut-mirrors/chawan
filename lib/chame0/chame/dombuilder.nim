type
  SetEncodingResult* = enum
    seContinue, seStop

  DOMBuilderBase* = ref object of RootObj

  DOMBuilder*[Handle] = ref object of DOMBuilderBase
