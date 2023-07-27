import options
import tables

type
  RadixPair[T] = tuple[k: string, v: RadixNode[T]]

  RadixNode*[T] = ref object
    children*: seq[RadixPair[T]]
    value*: Option[T]

func newRadixTree*[T](): RadixNode[T] =
  new(result)

func toRadixTree*[T](table: Table[string, T]): RadixNode[T] =
  result = newRadixTree[T]()
  for k, v in table:
    result[k] = v

# getOrDefault: we have to compare the entire string but if it doesn't match
# exactly we can just return default.
func getOrDefault[T](node: RadixNode[T], k: string, default: RadixNode[T]): RadixNode[T] =
  var i = 0
  while i < node.children.len:
    if node.children[i].k[0] == k[0]:
      if k.len != node.children[i].k.len:
        return default
      var j = 1
      while j < k.len:
        if node.children[i].k[j] != k[j]:
          return default
        inc j
      return node.children[i].v
    inc i
  return default

iterator keys*[T](node: RadixNode[T]): string =
  var i = 0
  while i < node.children.len:
    yield node.children[i].k
    inc i

#func contains[T](node: RadixNode[T], k: string): bool =
#  var i = 0
#  while i < node.children.len:
#    if node.children[i].k[0] == k[0]:
#      if k.len != node.children[i].k.len:
#        return false
#      var j = 1
#      while j < k.len:
#        if node.children[i].k[j] != k[j]:
#          return false
#        inc j
#      return true
#    inc i
#  return false

# O(1) add procedures for insert
proc add[T](node: RadixNode[T], k: string, v: T) =
  node.children.add((k, RadixNode[T](value: option(v))))

proc add[T](node: RadixNode[T], k: string) =
  node.children.add((k, RadixNode[T]()))

proc add[T](node: RadixNode[T], k: string, v: RadixNode[T]) =
  node.children.add((k, v))

# insert
proc `[]=`*[T](tree: RadixNode[T], key: string, value: T) =
  var n = tree
  var p: RadixNode[T] = nil
  var i = 0
  var j = 0
  var k = 0
  var t = ""

  # find last matching node
  var conflict = false
  while i < key.len:
    let m = i
    var o = 0
    for pk in n.keys:
      if pk[0] == key[i]:
        var l = 0
        while l < pk.len and i + l < key.len:
          if pk[l] != key[i + l]:
            conflict = true
            #t = key.substr(0, i + l - 1) & pk.substr(l)
            break
          inc l
        p = n
        k = o
        n = n.children[k].v
        t &= pk
        i += l
        if not conflict and pk.len == l:
          j = i 
        #  t = key.substr(0, i - 1)
        #elif not conflict and pk.len > l:
        #  t = key & pk.substr(l)
        break
      inc o
    if i == m:
      break
    if conflict:
      break

  if n == tree:
    # first node, just add normally
    tree.add(key, value)
  elif conflict:
    # conflict somewhere, so:
    # * add new non-leaf to parent
    # * add old to non-leaf
    # * add new to non-leaf
    # * remove old from parent
    p.add(key.substr(j, i - 1))
    p.children[^1].v.add(t.substr(i), n)
    p.children[^1].v.add(key.substr(i), value)
    p.children.del(k)
  elif key.len == t.len:
    # new matches a node, so replace
    p.children[k].v = RadixNode[T](value: option(value), children: n.children)
  elif key.len > t.len:
    # new is longer than the old, so add child to old
    n.add(key.substr(i), value)
  else:
    # new is shorter than old, so:
    # * add new to parent
    # * add old to new
    # * remove old from parent
    p.add(key.substr(j, i - 1), value)
    p.children[^1].v.add(t.substr(i), n)
    p.children.del(k)

func `{}`*[T](node: RadixNode[T], key: string): RadixNode[T] =
  return node.getOrDefault(key, node)

func hasPrefix*[T](node: RadixNode[T], prefix: string): bool =
  var n = node
  var i = 0

  while i < prefix.len:
    let m = i
    var j = 0
    for pk in n.keys:
      if pk[0] == prefix[i]:
        var l = 0
        while l < pk.len and i + l < prefix.len:
          if pk[l] != prefix[i + l]:
            return false
          inc l
        n = n.children[j].v
        i += l
        break
      inc j
    if i == m:
      return false

  return true

proc find*[T](root: RadixNode[T], get: proc(s: var string): bool): Option[T] =
  var n = root
  var buf = ""
  var i = 0
  var nexti = -1
  var val = n.value
  while get(buf):
    if nexti == -1:
      for j in 0 ..< n.children.len:
        if n.children[j].k[0] == buf[0]:
          nexti = j
          break
    if nexti == -1:
      break # not found
    # check if newly added characters match the next node
    var k = i
    while k < buf.len:
      if n.children[nexti].k[k] != buf[k]:
        break
      inc k
    if k == n.children[nexti].k.len: # buf.len >= next.len
      n = n.children[nexti].v
      nexti = -1
      if n.value.isSome:
        val = n.value
      for l in k ..< buf.len:
        buf[l - k] = buf[l]
      buf.setLen(buf.len - k)
      i = 0
    elif k != buf.len:
      break
  return val
