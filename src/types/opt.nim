# Inspired by nim-results.

type
  Result*[T, E] = object
    when E is void and T is void: # weirdness
      has*: bool
    elif E is void and not (T is void): # opt
      case has*: bool
      of true:
        val*: T
      else:
        discard
    elif not (E is void) and T is void: # err
      case has*: bool
      of true:
        discard
      else:
        ex*: E
    else: # result
      case has*: bool
      of true:
        val*: T
      else:
        ex*: E

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
  Result[T, E](has: false, ex: e)

template err*[T](t: type Result[T, ref object]): auto =
  t(has: false, ex: nil)

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
  if r.isSome:
    Opt[T].ok(r.get)
  else:
    Opt[T].err()

template isSome*(res: Result): bool = res.has
template isNone*(res: Result): bool = not res.has
func get*[T, E](res: Result[T, E]): lent T {.inline.} = res.val
func get*[T, E](res: var Result[T, E]): var T = res.val
func get*[T, E](res: Result[T, E]; v: T): T =
  if res.has:
    res.val
  else:
    v
func error*[T, E](res: Result[T, E]): lent E {.inline.} = res.ex
template valType*[T, E](res: type Result[T, E]): auto = T
template errType*[T, E](res: type Result[T, E]): auto = E

template `?`*[T, E](res: Result[T, E]): auto =
  let x = res # for when res is a funcall
  if x.has:
    when not (T is void):
      x.get
    else:
      discard
  else:
    when typeof(result) is Result[T, E]:
      return x
    elif not (E is void) and typeof(result).errType is E:
      return err(x.error)
    else:
      return err()
