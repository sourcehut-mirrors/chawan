const monouchaUseOpt {.booldefine.} = false
when monouchaUseOpt:
  import types/opt
  export opt
else:
  import results
  export results

  type Err*[E] = Result[void, E]

  template isSome*[T: not void, E](res: Result[T, E]): bool = res.isOk
  template isNone*(res: Result): bool = res.isErr
  template opt*[T](v: T): auto = ok(Opt[T], v)
  template opt*(t: typedesc): auto = err(Result[t, void])
  template valType*[T, E](res: type Result[T, E]): auto = T
