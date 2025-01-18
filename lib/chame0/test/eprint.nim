{.used.}

template eprint0(s: varargs[string]) =
  {.cast(noSideEffect), cast(tags: []), cast(raises: []).}:
    var o = ""
    for i in 0 ..< s.len:
      if i != 0:
        o &= ' '
      o &= s[i]
    when not declared(stderr):
      echo o
    else:
      o &= '\n'
      stderr.write(o)

when defined(release):
  func eprint*(s: varargs[string, `$`])
      {.deprecated: "eprint is for debugging only".} =
    eprint0(s)
else:
  func eprint*(s: varargs[string, `$`]) =
    eprint0(s)
