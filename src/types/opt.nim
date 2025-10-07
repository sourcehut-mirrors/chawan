# Inspired by nim-results.

type
  Result*[T, E] = object
    when E is void and T is void: # Opt[void]
      isOk*: bool
    elif E is void and T isnot void: # Opt[T]
      case isOk*: bool
      of true:
        value*: T
      else:
        discard
    elif E isnot void and T is void: # Err[T]
      case isOk*: bool
      of true:
        discard
      else:
        error*: E
    else: # Result[T, E]
      case isOk*: bool
      of true:
        value*: T
      else:
        error*: E

  Opt*[T] = Result[T, void]

  Err*[E] = Result[void, E]

template ok*[E](t: type Err[E]): Err[E] =
  Err[E](isOk: true)

template ok*[T, E](t: type Result[T, E]; x: T): Result[T, E] =
  Result[T, E](value: x, isOk: true)

template ok*[T](x: T): auto =
  ok(typeof(result), x)

template ok*(): auto =
  ok(typeof(result))

template err*[T, E](t: type Result[T, E]; e: E): Result[T, E] =
  Result[T, E](isOk: false, error: e)

template err*[T](t: type Result[T, ref object]): auto =
  t(isOk: false, error: nil)

template err*[T](t: type Result[T, void]): Result[T, void] =
  Result[T, void](isOk: false)

template err*(): auto =
  err(typeof(result))

template err*[E](e: E): auto =
  err(typeof(result), e)

template opt*[T](v: T): auto =
  ok(Opt[T], v)

template opt*(t: typedesc): auto =
  err(Result[t, void])

template isErr*(res: Result): bool = not res.isOk

template get*[T, E](res: Result[T, E]): T =
  res.value

proc get*[T, E](res: Result[T, E]; v: T): T =
  if res.isOk:
    result = res.value
  else:
    result = v

template `?`*[T, E](res: Result[T, E]): auto =
  var x = res # for when res is a funcall
  if not x.isOk:
    when typeof(result) is Result[T, E]:
      return move(x)
    elif E isnot void:
      {.push checks: off.}
      return err(move(x.error))
      {.pop.}
    else:
      return err()
  when T isnot void:
    move(x.get)

template `:=`*(a, res: untyped): bool =
  var x = res # for when res is a funcall
  var a: typeof(x).T
  let r = x.isOk
  if r:
    {.push checks: off.}
    a = move(x.get)
    {.pop.}
  r
