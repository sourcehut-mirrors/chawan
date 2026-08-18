{.push raises: [].}

type
  cstringConstImpl {.importc: "const char*".} = cstring
  cstringConst* = distinct cstringConstImpl

proc `[]`*(s: cstringConst; i: int): char = cstring(s)[i]
proc `$`*(s: cstringConst): string {.borrow.}

template toCStringConst*(s: string): cstringConst =
  cstringConst(cstring(s))

proc toCString*(p: cstringConst): cstring =
  cstring(p)

template `==`*(s: cstringConst; n: typeof(nil)): bool =
  cstring(s) == n

{.pop.} # raises
