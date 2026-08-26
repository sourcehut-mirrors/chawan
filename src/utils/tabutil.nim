{.push raises: [].}

import std/hashes

# Robin Hood hashing helpers
iterator prepareTableAdd*[T](tab: var seq[T]; load, init: int): T {.inline.} =
  if load >= tab.len div 2:
    let nlen = if tab.len == 0: init else: tab.len * 2
    # allocate new tab first, because some users depend on no destructors
    # being called while the table is in an inconsistent state
    var ntab = newSeq[T](nlen)
    var oldTab = move(tab)
    tab = move(ntab)
    for it in oldTab:
      yield it

iterator tabPairs*[T](tab: seq[T]; keyh: Hash): tuple[key: int; value: lent T]
    {.inline.} =
  if tab.len > 0:
    let mask = tab.len - 1
    var i = keyh and mask
    while true:
      yield (i, tab[i])
      i = (i + 1) and mask

iterator mtabPairs*[T](tab: var seq[T]; keyh: Hash):
    tuple[key: int; value: var T] {.inline.} =
  if tab.len > 0:
    let mask = tab.len - 1
    var i = keyh and mask
    while true:
      yield (i, tab[i])
      i = (i + 1) and mask

iterator tabGetAll*[K, V](tab: seq[V]; key: K): lent V {.inline.} =
  mixin tabKeyEq, tabIsEmpty
  if tab.len > 0:
    for i, it in tab.tabPairs(hash(key)):
      if tabIsEmpty(it):
        break
      if tabKeyEq(it, key):
        yield it

iterator tabPopAll*[K, V](tab: var seq[V]; item: K; keyh: Hash): V {.inline.} =
  ## Pop all items in the table.
  ## Warning: it is incorrect to break/return inside the loop.
  mixin tabHashFast, tabKeyEq, tabIsEmpty
  var j = -1
  for i, it in tab.mtabPairs(keyh):
    if tabIsEmpty(it):
      break # not found
    if tabKeyEq(it, item):
      yield move(it)
      j = i
    elif j >= 0:
      let k = tabHashFast(it) and (tab.len - 1)
      if i == k: # already at home
        break
      # backwards shift
      tab[j] = move(it)
      j = i

template tabDelImpl*[K, V](tab: var seq[V]; load: var int; item: K;
    keyh: Hash) =
  mixin tabHashFast, tabEqKey, tabIsEmpty
  for it in tab.tabPopAll(item, keyh):
    dec load

proc tabSwap*(ourHome: var int; theirHash: Hash; i, mask: int): bool =
  let theirHome = theirHash and mask
  let ourDist = (uint(i) - uint(ourHome)) and uint(mask)
  let theirDist = (uint(i) - uint(theirHome)) and uint(mask)
  let res = ourDist > theirDist
  if res:
    ourHome = theirHome
  res

# StrMap
type
  StrMapItem* = ref object of RootObj
    hcache*: int
    s*: string

  StrMap* = object
    load*: int
    tab: seq[StrMapItem]

proc tabHashFast(item: StrMapItem): Hash =
  item.hcache

proc tabIsEmpty(item: StrMapItem): bool =
  item == nil

proc tabKeyEq(a, b: StrMapItem): bool =
  a.hcache == b.hcache and a.s == b.s

iterator items*(map: StrMap): lent StrMapItem =
  ## Iterate over items in the table.
  for it in map.tab:
    if it != nil:
      yield it

proc getOrDefault*(map: StrMap; s: openArray[char]): StrMapItem =
  ## Get the first item keyed by `s`, or nil.
  if map.tab.len <= 0:
    return nil
  let hcache = s.hash()
  for i, it in map.tab.tabPairs(hcache):
    if it == nil:
      break
    if it.hcache == hcache and it.s == s:
      return it
  return nil

proc put0(map: var StrMap; item: StrMapItem; override: bool): bool =
  # returns true if a new item was inserted
  # if override, existing items are replaced by the new one
  let mask = map.tab.len - 1
  let hcache = item.hcache
  var item = item
  var home = hcache and mask
  for i, it in map.tab.mtabPairs(hcache):
    if it == nil:
      it = item
      break
    if it.hcache == item.hcache and it.s == item.s:
      if override:
        it = item
      return false
    if tabSwap(home, it.hcache, i, mask): # displace
      swap(it, item)
  true

proc putInit(map: var StrMap; item: StrMapItem) =
  item.hcache = item.s.hash()
  for it in map.tab.prepareTableAdd(map.load, init = 16):
    if it != nil:
      discard map.put0(it, override = false)

proc put*(map: var StrMap; item: StrMapItem) =
  ## Add an item, replacing any previous ones.
  map.putInit(item)
  if map.put0(item, override = true):
    inc map.load

proc hasKeyOrPut*(map: var StrMap; item: StrMapItem): bool =
  ## Returns true if a key already existed, otherwise item is added.
  map.putInit(item)
  if map.put0(item, override = false):
    inc map.load
    return false
  true

proc del*(map: var StrMap; item: StrMapItem) =
  ## Delete `item` from the table.
  tabDelImpl(map.tab, map.load, item, item.hcache)

proc clear*(map: var StrMap) =
  map.load = 0
  map.tab = @[]

# IntMap
type
  IntMapItem* = ref object of RootObj
    hcache*: Hash
    n*: int

  IntMap* = object
    tab: seq[IntMapItem]
    load: int

proc tabIsEmpty(item: IntMapItem): bool =
  item == nil

proc tabKeyEq(item: IntMapItem; n: int): bool =
  item.n == n

proc tabHashFast(item: IntMapItem): Hash =
  item.hcache

proc put0(map: var IntMap; item: IntMapItem): bool =
  # returns true if a new item was inserted
  # if override, existing items are replaced by the new one
  let mask = map.tab.len - 1
  let hcache = item.hcache
  var item = item
  var home = hcache and mask
  for i, it in map.tab.mtabPairs(hcache):
    if it == nil:
      it = item
      break
    if it.n == item.n:
      it = item
      return false
    if tabSwap(home, it.hcache, i, mask): # displace
      swap(it, item)
  true

proc put*(map: var IntMap; item: IntMapItem) =
  ## Add an item, replacing any previous ones.
  item.hcache = item.n.hash()
  for it in map.tab.prepareTableAdd(map.load, init = 16):
    if it != nil:
      discard map.put0(it)
  if map.put0(item):
    inc map.load

proc getOrDefault*(map: IntMap; n: int): IntMapItem =
  for it in map.tab.tabGetAll(n):
    if it == nil:
      break # not found
    if it.n == n:
      return it
  nil

proc pop*(map: var IntMap; n: int): IntMapItem =
  var res: IntMapItem = nil
  for it in map.tab.tabPopAll(n, hash(n)):
    res = it
  move(res)

{.pop.} # raises: []
