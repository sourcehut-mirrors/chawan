import js/domexception
import monoucha/javascript
import monoucha/jstypes
import monoucha/quickjs
import types/opt
import utils/twtstr

# atob and btoa convert Latin-1 to base64 and vice versa. (And throw on
# anything above latin-1.)

proc atob*(data: string): DOMResult[NarrowString] =
  # Note: the actual atob implementation (atob0) is in twtstr.
  let r = atob0(data)
  if r.isNone:
    return errDOMException($r.error, "InvalidCharacterError")
  return ok(NarrowString(r.get))

const AMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

func btoa*(s: var string; data: openArray[uint8]) =
  var i = 0
  let endw = data.len - 2
  while i < endw:
    let n = uint32(data[i]) shl 16 or
      uint32(data[i + 1]) shl 8 or
      uint32(data[i + 2])
    i += 3
    s &= AMap[n shr 18 and 0x3F]
    s &= AMap[n shr 12 and 0x3F]
    s &= AMap[n shr 6 and 0x3F]
    s &= AMap[n and 0x3F]
  if i < data.len:
    let b1 = uint32(data[i])
    inc i
    if i < data.len:
      let b2 = uint32(data[i])
      s &= AMap[b1 shr 2]                      # 6 bits of b1
      s &= AMap[b1 shl 4 and 0x3F or b2 shr 4] # 2 bits of b1 | 4 bits of b2
      s &= AMap[b2 shl 2 and 0x3F]             # 4 bits of b2
    else:
      s &= AMap[b1 shr 2]          # 6 bits of b1
      s &= AMap[b1 shl 4 and 0x3F] # 2 bits of b1
      s &= '='
    s &= '='

func btoa*(data: openArray[uint8]): string =
  if data.len == 0:
    return ""
  var L = data.len div 3 * 4
  if (let rem = data.len mod 3; rem) > 0:
    L += 3 - rem
  var s = newStringOfCap(L)
  s.btoa(data)
  return s

func btoa*(data: string): string =
  return btoa(data.toOpenArrayByte(0, data.len - 1))

proc btoa*(ctx: JSContext; data: JSValue): DOMResult[string] =
  let data = JS_ToString(ctx, data)
  if JS_IsException(data):
    return err()
  assert JS_IsString(data)
  if JS_IsStringWideChar(data):
    JS_FreeValue(ctx, data)
    return errDOMException("Invalid character in string",
      "InvalidCharacterError")
  let len = int(JS_GetStringLength(data))
  if len == 0:
    JS_FreeValue(ctx, data)
    return ok("")
  let buf = JS_GetNarrowStringBuffer(data)
  let res = btoa(buf.toOpenArray(0, len - 1))
  JS_FreeValue(ctx, data)
  return ok(res)
