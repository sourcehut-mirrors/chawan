include entity_gen
import utils/radixtree

proc genEntityMap(data: openArray[tuple[a: cstring, b: cstring]]):
    RadixNode[cstring] =
  result = newRadixTree[cstring]()
  for pair in data:
    result[$pair.a] = pair.b

let entityMap* = genEntityMap(entityTable)
