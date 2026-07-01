{.push raises: [].}

import std/hashes

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

{.pop.} # raises: []
