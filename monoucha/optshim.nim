const monouchaUseOpt {.booldefine.} = false
when monouchaUseOpt:
  import types/opt
  export opt
else:
  import results
  export results

  template isSome*[T: not void, E](res: Result[T, E]): bool = res.isOk
