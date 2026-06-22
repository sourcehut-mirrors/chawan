{.push raises: [].}

import std/hashes

iterator prepareTableAdd*[T](tab: var seq[T]; load, init: int): T {.inline.} =
  if load >= tab.len div 2:
    let nlen = if tab.len == 0: init else: tab.len * 2
    var oldTab = move(tab)
    tab = newSeq[T](nlen)
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
