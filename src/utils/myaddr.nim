# Before 2.0, `addr' only worked on mutable types, and `unsafeAddr'
# was needed to take the address of immutable ones.
#
# This was changed in 2.0 for some incomprehensible reason, even though
# it's still a useful distinction (it catches bugs).
#
# This module fixes the above problem; it is automatically included
# in every file by nim.cfg.
#
# Additionally, this adds a backport of newSeqUninit which is exactly
# the same as newSeqUninitialized but with a different name.

const msg = "expression has no address; maybe use `unsafeAddr'"

template addr(x: auto): auto {.used, error: msg.} =
  discard

template addr(x: var auto): auto {.used.} =
  system.addr x

when not declared(newSeqUninit):
  template newSeqUninit[T](len: typed): seq[T] {.used.} =
    newSeqUninitialized[T](len)
