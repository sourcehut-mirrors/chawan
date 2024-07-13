import std/options
import std/tables
import std/times

import types/opt
import utils/twtstr
import utils/twtuni

type
  TomlValueType* = enum
    tvtString = "string"
    tvtInteger = "integer"
    tvtFloat = "float"
    tvtBoolean = "boolean"
    tvtDateTime = "datetime"
    tvtTable = "table"
    tvtArray = "array"

  TomlError = string

  TomlResult = Result[TomlValue, TomlError]

  TomlParser = object
    filename: string
    at: int
    line: int
    buf: string
    root: TomlTable
    node: TomlNode
    currkey: seq[string]
    tarray: bool
    laxnames: bool

  TomlValue* = ref object
    case t*: TomlValueType
    of tvtString:
      s*: string
    of tvtInteger:
      i*: int64
    of tvtFloat:
      f*: float64
    of tvtBoolean:
      b*: bool
    of tvtTable:
      tab*: TomlTable
    of tvtDateTime:
      dt*: DateTime
    of tvtArray:
      a*: seq[TomlValue]
      ad*: bool

  TomlNode = ref object of RootObj
    comment: string

  TomlKVPair = ref object of TomlNode
    key*: seq[string]
    value*: TomlValue

  TomlTable* = ref object of TomlNode
    key: seq[string]
    nodes: seq[TomlNode]
    map: Table[string, TomlValue]

func `$`*(val: TomlValue): string

func `$`(tab: TomlTable): string

func `$`(kvpair: TomlKVPair): string =
  if kvpair.key.len > 0:
    #TODO escape
    result = kvpair.key[0]
    for i in 1 ..< kvpair.key.len:
      result &= '.'
      result &= kvpair.key[i]
  else:
    result = "\"\""
  result &= " = "
  result &= $kvpair.value
  result &= '\n'

func `$`(tab: TomlTable): string =
  if tab.comment != "":
    result &= "#" & tab.comment & '\n'
  for key, val in tab.map:
    result &= key & " = " & $val & '\n'
  result &= '\n'

func `$`*(val: TomlValue): string =
  case val.t
  of tvtString:
    result = "\""
    for c in val.s:
      if c == '"':
        result &= '\\'
      result &= c
    result &= '"'
  of tvtInteger:
    result = $val.i
  of tvtFloat:
    result = $val.f
  of tvtBoolean:
    result = $val.b
  of tvtTable:
    result = $val.t
  of tvtDateTime:
    result = $val.dt
  of tvtArray:
    #TODO if ad table array probably
    result = "["
    for it in val.a:
      result &= $it
      result &= ','
    result &= ']'

func `[]`*(val: TomlValue; key: string): TomlValue =
  return val.tab.map[key]

iterator pairs*(val: TomlValue): (string, TomlValue) {.inline.} =
  for k, v in val.tab.map:
    yield (k, v)

func contains*(val: TomlValue; key: string): bool =
  return key in val.tab.map

const ValidBare = AsciiAlphaNumeric + {'-', '_'}

func peek(state: TomlParser; i: int): char =
  return state.buf[state.at + i]

template err(state: TomlParser; msg: string): untyped =
  err(state.filename & "(" & $state.line & "):" & msg)

proc consume(state: var TomlParser): char =
  result = state.buf[state.at]
  inc state.at

proc seek(state: var TomlParser; n: int) =
  state.at += n

proc reconsume(state: var TomlParser) =
  dec state.at

proc has(state: var TomlParser; i: int = 0): bool =
  return state.at + i < state.buf.len

proc consumeEscape(state: var TomlParser; c: char): Result[uint32, TomlError] =
  var len = 4
  if c == 'U':
    len = 8
  let c = state.consume()
  var num = hexValue(c)
  if num != -1:
    var i = 0
    while state.has() and i < len:
      let c = state.peek(0)
      if hexValue(c) == -1:
        break
      discard state.consume()
      num *= 0x10
      num += hexValue(c)
      inc i
    if i != len - 1:
      return state.err("invalid escaped length (" & $i & ", needs " & $len &
        ")")
    if num > 0x10FFFF or num in 0xD800..0xDFFF:
      return state.err("invalid escaped codepoint: " & $num)
    else:
      return ok(uint32(num))
  else:
    return state.err("invalid escaped codepoint: " & $c)

proc consumeString(state: var TomlParser; first: char): Result[string, string] =
  var multiline = false
  if first == '"' and state.has(1) and state.peek(0) == '"' and
      state.peek(1) == '"':
    multiline = true
    state.seek(2)
  elif first == '\'' and state.has(1) and state.peek(0) == '\'' and
      state.peek(1) == '\'':
    multiline = true
    state.seek(2)
  if multiline and state.peek(0) == '\n':
    inc state.line
    discard state.consume()
  var escape = false
  var ml_trim = false
  var res = ""
  while state.has():
    let c = state.consume()
    if c == '\n' and not multiline:
      return state.err("newline in string")
    elif not escape and c == first:
      if multiline:
        if state.has(1):
          let c2 = state.peek(0)
          let c3 = state.peek(1)
          if c2 == first and c3 == first:
            discard state.consume()
            discard state.consume()
            break
        res &= c
      else:
        break
    elif first == '"' and c == '\\':
      escape = true
    elif escape:
      case c
      of 'b': res &= '\b'
      of 't': res &= '\t'
      of 'n': res &= '\n'
      of 'f': res &= '\f'
      of 'r': res &= '\r'
      of '"': res &= '"'
      of '\\': res &= '\\'
      of 'u', 'U': res.addUTF8(?state.consumeEscape(c))
      of '\n': ml_trim = true
      of '$': res &= "\\$" # special case for substitution in paths
      else: return state.err("invalid escape sequence \\" & c)
      escape = false
    elif ml_trim:
      if c notin {'\n', ' ', '\t'}:
        res &= c
        ml_trim = false
      if c == '\n':
        inc state.line
    else:
      if c == '\n':
        inc state.line
      res &= c
  return ok(res)

proc consumeBare(state: var TomlParser; c: char): Result[string, TomlError] =
  var res = $c
  while state.has():
    let c = state.consume()
    case c
    of ' ', '\t': break
    of '.', '=', ']', '\n':
      state.reconsume()
      break
    elif c in ValidBare:
      res &= c
    else:
      return state.err("invalid value in token: " & c)
  return ok(res)

proc flushLine(state: var TomlParser): Err[TomlError] =
  if state.node != nil:
    if state.node of TomlKVPair:
      var i = 0
      let keys = state.currkey & TomlKVPair(state.node).key
      var table = state.root
      while i < keys.len - 1:
        if keys[i] in table.map:
          let node = table.map[keys[i]]
          if node.t == tvtTable:
            table = node.tab
          elif node.t == tvtArray:
            assert state.tarray
            table = node.a[^1].tab
          else:
            let s = keys.join('.')
            return state.err("re-definition of node " & s)
        else:
          let node = TomlTable()
          table.map[keys[i]] = TomlValue(t: tvtTable, tab: node)
          table = node
        inc i
      if keys[i] in table.map:
        return state.err("re-definition of node " & keys.join('.'))
      table.map[keys[i]] = TomlKVPair(state.node).value
      table.nodes.add(state.node)
    state.node = nil
  inc state.line
  return ok()

proc consumeComment(state: var TomlParser) =
  if state.node == nil:
    state.node = TomlNode()
  while state.has():
    let c = state.consume()
    if c == '\n':
      state.reconsume()
      break
    else:
      state.node.comment &= c

proc consumeKey(state: var TomlParser): Result[seq[string], TomlError] =
  var res: seq[string]
  var str = ""
  while state.has():
    let c = state.consume()
    case c
    of '"', '\'':
      if str.len > 0:
        return state.err("multiple strings without dot")
      str = ?state.consumeString(c)
    of '=', ']':
      if str.len != 0:
        res.add(str)
        str = ""
      return ok(res)
    of '.':
      if str.len == 0: #TODO empty strings are allowed, only empty keys aren't
        return state.err("redundant dot")
      else:
        res.add(str)
        str = ""
    of ' ', '\t': discard
    of '\n':
      if state.node != nil:
        return state.err("newline without value")
      else:
        ?state.flushLine()
    elif c in ValidBare:
      if str.len > 0:
        return state.err("multiple strings without dot: " & str)
      str = ?state.consumeBare(c)
    else: return state.err("invalid character in key: " & c)
  return state.err("key without value")

proc consumeTable(state: var TomlParser): Result[TomlTable, TomlError] =
  let res = TomlTable()
  while state.has():
    let c = state.peek(0)
    case c
    of ' ', '\t': discard state.consume()
    of '\n': return ok(res)
    of ']':
      if state.tarray:
        discard state.consume()
        return ok(res)
      else:
        return state.err("redundant ] character after key")
    of '[':
      state.tarray = true
      discard state.consume()
    of '"', '\'':
      res.key = ?state.consumeKey()
    elif c in ValidBare:
      res.key = ?state.consumeKey()
    else: return state.err("invalid character before key: " & c)
  return state.err("unexpected end of file")

proc consumeNoState(state: var TomlParser): Result[bool, TomlError] =
  while state.has():
    let c = state.peek(0)
    case c
    of '#', '\n':
      return ok(false)
    of ' ', '\t': discard
    of '[':
      discard state.consume()
      state.tarray = false
      let table = ?state.consumeTable()
      if state.tarray:
        var node = state.root
        for i in 0 ..< table.key.high:
          if table.key[i] in node.map:
            node = node.map[table.key[i]].tab
          else:
            let t2 = TomlTable()
            node.map[table.key[i]] = TomlValue(t: tvtTable, tab: t2)
            node = t2
        if table.key[^1] in node.map:
          var last = node.map[table.key[^1]]
          if last.t != tvtArray:
            let key = table.key.join('.')
            return state.err("re-definition of node " & key &
              " as table array (was " & $last.t & ")")
          let val = TomlValue(t: tvtTable, tab: table)
          last.a.add(val)
        else:
          let val = TomlValue(t: tvtTable, tab: table)
          let last = TomlValue(t: tvtArray, a: @[val], ad: true)
          node.map[table.key[^1]] = last
      state.currkey = table.key
      state.node = table
      return ok(false)
    elif c == '"' or c == '\'' or c in ValidBare:
      let kvpair = TomlKVPair()
      kvpair.key = ?state.consumeKey()
      state.node = kvpair
      return ok(true)
    else: return state.err("invalid character before key: " & c)
  return state.err("unexpected end of file")

type ParsedNumberType = enum
  pntInteger, pntFloat, pntHex, pntOct

proc consumeNumber(state: var TomlParser; c: char): TomlResult =
  var repr = ""
  var numType = pntInteger
  if c == '0' and state.has():
    let c = state.consume()
    if c == 'x':
      numType = pntHex
    elif c == 'o':
      numType = pntOct
    else:
      state.reconsume()
      repr &= c
  else:
    if c in {'+', '-'} and (not state.has() or state.peek(0) notin AsciiDigit):
      return state.err("invalid number")
    repr &= c
  var was_num = repr.len > 0 and repr[0] in AsciiDigit
  while state.has():
    if state.peek(0) in AsciiDigit:
      repr &= state.consume()
      was_num = true
    elif was_num and state.peek(0) == '_':
      was_num = false
      repr &= '_'
    else:
      break
  if state.has(1) and state.peek(0) == '.' and state.peek(1) in AsciiDigit:
    repr &= state.consume()
    repr &= state.consume()
    if numType notin {pntInteger, pntFloat}:
      return state.err("invalid floating point number")
    numType = pntFloat
    while state.has() and state.peek(0) in AsciiDigit:
      repr &= state.consume()
  if state.has(1) and state.peek(0) in {'E', 'e'}:
    if numType notin {pntInteger, pntFloat}:
      return state.err("invalid floating point number")
    numType = pntFloat
    var j = 2
    if state.peek(1) == '-' or state.peek(1) == '+':
      inc j
    if state.has(j) and state.peek(j) in AsciiDigit:
      while j > 0:
        repr &= state.consume()
        dec j
      while state.has() and state.peek(0) in AsciiDigit:
        repr &= state.consume()
  case numType
  of pntInteger:
    let val = parseInt64(repr)
    if val.isNone:
      return state.err("invalid integer")
    return ok(TomlValue(t: tvtInteger, i: val.get))
  of pntHex:
    let val = parseHexInt64(repr)
    if val.isNone:
      return state.err("invalid hexadecimal number")
    return ok(TomlValue(t: tvtInteger, i: val.get))
  of pntOct:
    let val = parseOctInt64(repr)
    if val.isNone:
      return state.err("invalid octal number")
    return ok(TomlValue(t: tvtInteger, i: val.get))
  of pntFloat:
    let val = parseFloat64(repr)
    return ok(TomlValue(t: tvtFloat, f: val))

proc consumeValue(state: var TomlParser): TomlResult

proc consumeArray(state: var TomlParser): TomlResult =
  var res = TomlValue(t: tvtArray)
  var val: TomlValue
  while state.has():
    let c = state.consume()
    case c
    of ' ', '\t': discard
    of '\n': inc state.line
    of ']':
      if val != nil:
        res.a.add(val)
      return ok(res)
    of ',':
      if val == nil:
        return state.err("comma without element")
      res.a.add(val)
      val = nil
    else:
      if val != nil:
        return state.err("missing comma")
      state.reconsume()
      val = ?state.consumeValue()
  return err("unexpected end of file")

proc consumeInlineTable(state: var TomlParser): TomlResult =
  let res = TomlValue(t: tvtTable, tab: TomlTable())
  var key: seq[string]
  var haskey: bool
  var val: TomlValue
  while state.has():
    let c = state.consume()
    case c
    of ' ', '\t': discard
    of '\n': inc state.line
    of ',', '}':
      if c == '}' and key.len == 0 and val == nil:
        return ok(res) # empty, or trailing comma
      if key.len == 0:
        return state.err("missing key")
      if val == nil:
        return state.err("comma without element")
      var table = res.tab
      for i in 0 ..< key.high:
        let k = key[i]
        if k in table.map:
          return state.err("invalid re-definition of key " & k)
        else:
          let node = TomlTable()
          table.map[k] = TomlValue(t: tvtTable, tab: node)
          table = node
      let k = key[^1]
      if k in table.map:
        return state.err("invalid re-definition of key " & k)
      table.map[k] = val
      val = nil
      haskey = false
      if c == '}':
        return ok(res)
    else:
      if val != nil:
        return state.err("missing comma")
      if not haskey:
        state.reconsume()
        key = ?state.consumeKey()
        haskey = true
      else:
        state.reconsume()
        val = ?state.consumeValue()
  return state.err("unexpected end of file")

proc consumeValue(state: var TomlParser): TomlResult =
  while state.has():
    let c = state.consume()
    case c
    of '"', '\'':
      let s = ?state.consumeString(c)
      return ok(TomlValue(t: tvtString, s: s))
    of ' ', '\t': discard
    of '\n':
      return state.err("newline without value")
    of '#':
      return state.err("comment without value")
    of '+', '-', '0'..'9':
      return state.consumeNumber(c)
      #TODO date-time
    of '[':
      return state.consumeArray()
    of '{':
      return state.consumeInlineTable()
    elif c in ValidBare:
      let s = ?state.consumeBare(c)
      if s == "true":
        return ok(TomlValue(t: tvtBoolean, b: true))
      elif s == "false":
        return ok(TomlValue(t: tvtBoolean, b: false))
      elif state.laxnames:
        return ok(TomlValue(t: tvtString, s: s))
      else:
        return state.err("invalid token: " & s)
    else:
      return state.err("invalid character in value: " & c)
  if state.laxnames:
    return ok(TomlValue(t: tvtString, s: ""))
  return state.err("unexpected end of file")

proc parseToml*(buf: string; filename = "<input>"; laxnames = false):
    TomlResult =
  var state = TomlParser(
    buf: buf,
    line: 1,
    root: TomlTable(),
    filename: filename,
    laxnames: laxnames
  )
  while state.has():
    if ?state.consumeNoState():
      # state.node has been set to a KV pair, so now we parse its value.
      let kvpair = TomlKVPair(state.node)
      kvpair.value = ?state.consumeValue()
    while state.has():
      let c = state.consume()
      case c
      of '\n':
        ?state.flushLine()
        break
      of '#':
        state.consumeComment()
      of '\t', ' ': discard
      else: return state.err("invalid character after value: " & c)
  ?state.flushLine()
  return ok(TomlValue(t: tvtTable, tab: state.root))
