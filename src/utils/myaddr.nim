# Before 2.0, `addr' only worked on mutable types, and `unsafeAddr'
# was needed to take the address of immutable ones.
#
# This was changed in 2.0 for some incomprehensible reason, so now to
# write code that compiles on both versions you have to take care that
# you use the right overload without compiler help.
#
# This module fixes the above problem; it is automatically included
# in every file by nim.cfg.

when NimMajor >= 2:
  const msg = "expression has no address; maybe use `unsafeAddr'"

  template addr(x: auto): auto {.used, error: msg.} =
    discard

  template addr(x: var auto): auto {.used.} =
    system.addr x
