type
  cstringConstImpl {.importc: "const char*".} = cstring
  cstringConst* = distinct cstringConstImpl

proc `[]`*(s: cstringConst; i: int): char = cstring(s)[i]
proc `$`*(s: cstringConst): string {.borrow.}
