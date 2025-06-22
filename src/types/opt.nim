# Inspired by nim-results.

type
  Result*[T, E] = object
    when E is void and T is void: # weirdness
      has*: bool
    elif E is void and T isnot void: # opt
      case has*: bool
      of true:
        val*: T
      else:
        discard
    elif E isnot void and T is void: # err
      case has*: bool
      of true:
        discard
      else:
        error*: E
    else: # result
      case has*: bool
      of true:
        val*: T
      else:
        error*: E

  Opt*[T] = Result[T, void]

  Err*[E] = Result[void, E]

template ok*[E](t: type Err[E]): Err[E] =
  Err[E](has: true)

template ok*[T, E](t: type Result[T, E]; x: T): Result[T, E] =
  Result[T, E](val: x, has: true)

template ok*[T](x: T): auto =
  ok(typeof(result), x)

template ok*(): auto =
  ok(typeof(result))

template err*[T, E](t: type Result[T, E]; e: E): Result[T, E] =
  Result[T, E](has: false, error: e)

template err*[T](t: type Result[T, ref object]): auto =
  t(has: false, error: nil)

template err*[T](t: type Result[T, void]): Result[T, void] =
  Result[T, void](has: false)

template err*(): auto =
  err(typeof(result))

template err*[E](e: E): auto =
  err(typeof(result), e)

template opt*[T](v: T): auto =
  ok(Opt[T], v)

template opt*(t: typedesc): auto =
  err(Result[t, void])

template opt*[T, E: not void](r: Result[T, E]): Opt[T] =
  if r.isOk:
    Opt[T].ok(r.get)
  else:
    Opt[T].err()

template isOk*(res: Result): bool = res.has

template isErr*(res: Result): bool = not res.has

func get*[T, E](res: Result[T, E]): lent T {.inline.} = res.val

func get*[T, E](res: var Result[T, E]): var T = res.val

func get*[T, E](res: Result[T, E]; v: T): T =
  if res.has:
    {.push checks: off.}
    result = res.val
    {.pop.}
  else:
    result = v

func uncheckedGet[T, E](res: var Result[T, E]): var T {.inline.} =
  {.push checks: off.}
  result = res.val
  {.pop.}

template valType*[T, E](res: type Result[T, E]): auto = T

template errType*[T, E](res: type Result[T, E]): auto = E

template `?`*[T, E](res: Result[T, E]): auto =
  var x = res # for when res is a funcall
  if not x.has:
    when typeof(result) is Result[T, E]:
      return move(x)
    elif E isnot void and typeof(result).errType is E:
      {.push checks: off.}
      return err(move(x.error))
      {.pop.}
    else:
      return err()
  when T isnot void:
    move(x.uncheckedGet)

template `:=`*[T, E](a: untyped; res: Result[T, E]): bool =
  var x = res # for when res is a funcall
  var a: T
  let r = x.has
  if r:
    {.push checks: off.}
    a = move(x.val)
    {.pop.}
  r
