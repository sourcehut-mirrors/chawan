{.push raises: [].}

import io/dynstream
import io/packetreader
import io/packetwriter
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsref
import monoucha/quickjs
import monoucha/tojs
import types/blob
import types/jsopt
import types/opt
import utils/twtstr

type
  FormDataEntry* = object
    name*: string
    filename*: string
    case isstr*: bool
    of true:
      svalue*: string
    of false:
      value*: Blob

  FormDataObj* = object
    entries*: seq[FormDataEntry]
    boundary*: string

  FormData* = JSRef[FormDataObj]

# Forward declarations
proc getClassID*(t: typedesc[FormData]): JSClassID

# Forward declaration hack
proc newFormDataImpl(ctx: JSContext; argv: varargs[JSValueConst]):
  Opt[FormData] {.importc: "cha_$1".}

proc swrite*(w: var PacketWriter; part: FormDataEntry) =
  w.swrite(part.isstr)
  w.swrite(part.name)
  w.swrite(part.filename)
  if part.isstr:
    w.swrite(part.svalue)
  else:
    w.swrite(part.value)

proc sread*(r: var PacketReader; part: var FormDataEntry) =
  var isstr: bool
  r.sread(isstr)
  if isstr:
    part = FormDataEntry(isstr: true)
  else:
    part = FormDataEntry(isstr: false)
  r.sread(part.name)
  r.sread(part.filename)
  if part.isstr:
    r.sread(part.svalue)
  else:
    r.sread(part.value)

proc swrite*(w: var PacketWriter; formData: FormData) =
  w.swrite(formData != nil)
  if formData == nil:
    w.swrite(formData.entries)
    w.swrite(formData.boundary)

proc sread*(r: var PacketReader; formData: var FormData) =
  var has: bool
  r.sread(has)
  if has:
    var obj: FormDataObj
    r.sread(obj.entries)
    r.sread(obj.boundary)
    formData = jsNew obj
  else:
    formData = FormData(nil)

iterator items*(this: FormData): lent FormDataEntry {.inline.} =
  for entry in this.entries:
    yield entry

proc calcLength*(this: FormData): int =
  result = 0
  for entry in this.entries:
    result += "--\r\n".len + this.boundary.len # always have boundary
    #TODO maybe make CRLF for name first?
    result += entry.name.len # always have name
    # these must be percent-encoded, with 2 char overhead:
    result += entry.name.count({'\r', '\n', '"'}) * 2
    if entry.isstr:
      result += "Content-Disposition: form-data; name=\"\"\r\n".len
      result += entry.svalue.len
    else:
      result += "Content-Disposition: form-data; name=\"\";".len
      # file name
      result += " filename=\"\"\r\n".len
      result += entry.filename.len
      # dquot must be quoted with 2 char overhead
      result += entry.filename.count('"') * 2
      # content type
      result += "Content-Type: \r\n".len
      result += entry.value.ctype.len
      result += entry.value.getSize()
    result += "\r\n".len # header is always followed by \r\n
    result += "\r\n".len # value is always followed by \r\n
  result += "--".len + this.boundary.len + "--\r\n".len

proc getContentType*(this: FormData): string =
  return "multipart/form-data; boundary=" & this.boundary

proc writeEntry(stream: PosixStream; entry: FormDataEntry; boundary: string):
    Opt[void] =
  var buf = "--" & boundary & "\r\n"
  let name = percentEncode(entry.name, {'"', '\r', '\n'})
  if entry.isstr:
    buf &= "Content-Disposition: form-data; name=\"" & name & "\"\r\n\r\n"
    # try to merge the write call for small entries
    if entry.svalue.len < 4096:
      buf &= entry.svalue
      ?stream.writeLoop(buf)
    else:
      ?stream.writeLoop(buf)
      ?stream.writeLoop(entry.svalue)
  else:
    buf &= "Content-Disposition: form-data; name=\"" & name & "\";"
    let filename = percentEncode(entry.filename, {'"', '\r', '\n'})
    buf &= " filename=\"" & filename & "\"\r\n"
    let blob = entry.value
    let ctype = if blob.ctype == "":
      "application/octet-stream"
    else:
      blob.ctype
    buf &= "Content-Type: " & ctype & "\r\n\r\n"
    ?stream.writeLoop(buf)
    if (let file = blob as WebFile; file != nil and file.fd != -1):
      let ps = newPosixStream(file.fd)
      if ps != nil:
        var buf {.noinit.}: array[4096, uint8]
        while true:
          let n = ps.read(buf)
          if n <= 0:
            break
          ?stream.writeLoop(buf.toOpenArray(0, n - 1))
    else:
      ?stream.writeLoop(blob.buffer, blob.size)
  stream.writeLoop("\r\n")

proc write*(stream: PosixStream; formData: FormData): Opt[void] =
  for entry in formData.entries:
    ?stream.writeEntry(entry, formData.boundary)
  stream.writeLoop("--" & formData.boundary & "--\r\n")

proc generateBoundary(urandom: PosixStream): string =
  var s {.noinit.}: array[33, uint8]
  if urandom.readLoop(s).isErr:
    return ""
  # 33 * 4 / 3 = 44 + prefix string is 22 bytes = 66 bytes
  return "----WebKitFormBoundary" & btoa(s)

proc newFormData0*(urandom: PosixStream): FormData =
  var boundary = urandom.generateBoundary()
  if boundary.len == 0:
    return FormData(nil)
  return jsNew FormDataObj(boundary: move(boundary))

jsClassPublicDef(FormData):
  proc newFormData(ctx: JSContext; argv: varargs[JSValueConst]): Opt[FormData]
      {.jsctor.} =
    newFormDataImpl(ctx, argv)

  proc append*(ctx: JSContext; this: FormData; name: string; val: JSValueConst;
      rest: varargs[JSValueConst]): Opt[void] {.jsfunc.} =
    var blob: Blob
    if ctx.fromJS(val, blob).isOk:
      var filename = "blob"
      if rest.len > 0:
        ?ctx.fromJS(rest[0], filename)
      elif blob of WebFile:
        filename = WebFile(blob).name
      this.entries.add(FormDataEntry(
        name: name,
        isstr: false,
        value: blob,
        filename: filename
      ))
      ok()
    elif rest.len > 0:
      err()
    else:
      var s: string
      ?ctx.fromJS(val, s)
      this.entries.add(FormDataEntry(name: name, isstr: true, svalue: s))
      ok()

  proc delete(this: FormData; name: string) {.jsfunc.} =
    for i in countdown(this.entries.high, 0):
      if this.entries[i].name == name:
        this.entries.delete(i)

  proc get(ctx: JSContext; this: FormData; name: string): JSValue {.jsfunc.} =
    for entry in this.entries:
      if entry.name == name:
        if entry.isstr:
          return ctx.toJS(entry.svalue)
        else:
          return ctx.toJS(entry.value)
    return JS_NULL

  proc getAll(ctx: JSContext; this: FormData; name: string): seq[JSValue]
      {.jsfunc.} =
    result = newSeq[JSValue]()
    for entry in this.entries:
      if entry.name == name:
        if entry.isstr:
          result.add(ctx.toJS(entry.svalue))
        else:
          result.add(ctx.toJS(entry.value))

proc add*(list: var seq[FormDataEntry], entry: tuple[name, value: string]) =
  list.add(FormDataEntry(
    name: entry.name,
    isstr: true,
    svalue: entry.value
  ))

proc toNameValuePairs*(list: seq[FormDataEntry]):
    seq[tuple[name, value: string]] =
  result = @[]
  for entry in list:
    if entry.isstr:
      result.add((entry.name, entry.svalue))
    else:
      result.add((entry.name, entry.name))

proc addFormDataModule*(ctx: JSContext): FromJSResult =
  ctx.registerClass(FormDataDef)

{.pop.} # raises: []
