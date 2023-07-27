import json

import utils/radixtree

const entity = staticRead"res/entity.json"
proc genEntityMap(data: seq[tuple[a: cstring, b: cstring]]): RadixNode[string] =
  result = newRadixTree[string]()
  for pair in data:
    result[$pair.a] = $pair.b

proc genEntityTable(): seq[tuple[a: cstring, b: cstring]] =
  let entityJson = parseJson(entity)

  for k, v in entityJson:
    result.add((cstring(k.substr(1)), cstring(v{"characters"}.getStr())))
const entityTable = genEntityTable()
let entityMap* = genEntityMap(entityTable)
