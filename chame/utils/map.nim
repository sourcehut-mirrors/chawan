import algorithm

func searchInMap*[U, T](a: openarray[(U, T)], u: U): int =
  when not (typeof(u) is U):
    if c > cast[typeof(c)](high(U)):
      return -1
  binarySearch(a, u, proc(x: (U, T), y: U): int = cmp(x[0], y))

func isInMap*[U, T](a: openarray[(U, T)], u: U): bool =
  a.searchInMap(u) != -1

func isInRange*[U](a: openarray[(U, U)], u: U): bool =
  let res = binarySearch(a, u, proc(x: (U, U), y: U): int =
    if x[0] < y:
      -1
    elif x[1] > y:
      1
    else:
      0
  )
  return res != -1
