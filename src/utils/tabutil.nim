{.push raises: [].}

import std/hashes

type
  StrMapItem* = ref object of RootObj
    hcache*: int
    name*: string

  StrMap* = object
    load*: int
    tab: seq[StrMapItem]

iterator items*(map: StrMap): StrMapItem =
  for it in map.tab:
    if it != nil:
      yield it

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

proc tabSwap*(ourHome: var int; theirHash: Hash; i, mask: int): bool =
  let theirHome = theirHash and mask
  let ourDist = (uint(i) - uint(ourHome)) and uint(mask)
  let theirDist = (uint(i) - uint(theirHome)) and uint(mask)
  let res = ourDist > theirDist
  if res:
    ourHome = theirHome
  res

proc getOrDefault*(map: StrMap; name: openArray[char]): StrMapItem =
  if map.tab.len <= 0:
    return nil
  let hcache = name.hash()
  let mask = map.tab.len - 1
  var h = hcache and mask
  while true:
    let it = map.tab[h]
    if it == nil:
      break
    if it.hcache == hcache and it.name == name:
      return it
    h = (h + 1) and mask
  return nil

proc put0(map: var StrMap; item: StrMapItem): bool =
  let mask = map.tab.len - 1
  var item = item
  var i = item.hcache and mask
  var home = item.hcache and mask
  while true:
    let it = map.tab[i]
    if it == nil:
      map.tab[i] = item
      break
    if it.hcache == item.hcache and it.name == item.name:
      map.tab[i] = item
      return false
    if tabSwap(home, it.hcache, i, mask): # displace
      swap(map.tab[i], item)
    i = (i + 1) and mask
  true

proc put*(map: var StrMap; item: StrMapItem) =
  item.hcache = item.name.hash()
  for it in map.tab.prepareTableAdd(map.load, init = 16):
    if it != nil:
      discard map.put0(it)
  if map.put0(item):
    inc map.load

proc del*(map: var StrMap; item: StrMapItem) =
  if map.tab.len == 0:
    return
  let mask = map.tab.len - 1
  var i = item.hcache and mask
  while true:
    let it = map.tab[i]
    if it == nil:
      # not found
      return
    if it == item:
      dec map.load
      map.tab[i] = nil
      break
    i = (i + 1) and mask
  var j = i
  while true:
    j = (j + 1) and mask
    let it = map.tab[j]
    if it == nil:
      break
    let k = it.hcache and mask
    if j == k: # already at home
      break
    # backwards shift
    map.tab[i] = move(map.tab[j])
    i = j

{.pop.} # raises: []
