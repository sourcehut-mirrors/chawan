const monouchaUseOpt {.booldefine.} = false
when monouchaUseOpt:
  import types/opt
  export opt
else:
  import results
  export results
