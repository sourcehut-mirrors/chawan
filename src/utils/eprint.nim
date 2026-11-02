{.used.}

type
  CFile {.importc: "FILE", header: "<stdio.h>", incompleteStruct.} = object

let myStderr {.importc: "stderr", header: "<stdio.h>".}: ptr CFile
proc fwrite(p: pointer; size, nmemb: csize_t; f: ptr CFile): csize_t {.
  importc, header: "<stdio.h>".}

template eprint0(s: varargs[string]) =
  {.cast(noSideEffect), cast(tags: []), cast(raises: []).}:
    var o = ""
    for i in 0 ..< s.len:
      if i != 0:
        o &= ' '
      o &= s[i]
    when nimvm:
      echo o
    else:
      o &= '\n'
      fwrite(addr o[0], 1, csize_t(o.len), myStderr)

when defined(release):
  func eprint*(s: varargs[string, `$`])
      {.deprecated: "eprint is for debugging only".} =
    eprint0(s)
else:
  func eprint*(s: varargs[string, `$`]) =
    eprint0(s)
