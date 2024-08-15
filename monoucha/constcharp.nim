{.push raises: [].}

type
  cstringConstImpl {.importc: "const char*".} = cstring
  cstringConst* = distinct cstringConstImpl

proc `[]`*(s: cstringConst; i: int): char = cstring(s)[i]
proc `$`*(s: cstringConst): string {.borrow.}

converter toCstring*(s: cstringConst): cstring {.inline.} =
  return cstring(s)

converter toCstringConst*(s: cstring): cstringConst {.inline.} =
  return cstringConst(s)

{.pop.} # raises
