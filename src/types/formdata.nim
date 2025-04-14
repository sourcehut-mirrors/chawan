import std/strutils

import io/dynstream
import io/packetreader
import io/packetwriter
import monoucha/javascript
import types/blob
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

  FormData* = ref object
    entries*: seq[FormDataEntry]
    boundary*: string

jsDestructor(FormData)

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

proc writeEntry*(stream: PosixStream; entry: FormDataEntry; boundary: string) =
  stream.write("--" & boundary & "\r\n")
  let name = percentEncode(entry.name, {'"', '\r', '\n'})
  if entry.isstr:
    stream.write("Content-Disposition: form-data; name=\"" & name &
      "\"\r\n\r\n")
    stream.write(entry.svalue)
    stream.write("\r\n")
  else:
    var buf = "Content-Disposition: form-data; name=\"" & name & "\";"
    let filename = percentEncode(entry.filename, {'"', '\r', '\n'})
    buf &= " filename=\"" & filename & "\"\r\n"
    let blob = entry.value
    let ctype = if blob.ctype == "":
      "application/octet-stream"
    else:
      blob.ctype
    buf &= "Content-Type: " & ctype & "\r\n\r\n"
    stream.write(buf)
    if blob of WebFile and WebFile(blob).fd.isSome:
      let ps = newPosixStream(WebFile(blob).fd.get)
      if ps != nil:
        var buf {.noinit.}: array[4096, uint8]
        while true:
          let n = ps.readData(buf)
          if n <= 0:
            break
          if not stream.writeDataLoop(buf.toOpenArray(0, n - 1)):
            break
    else:
      discard stream.writeDataLoop(blob.buffer, blob.size)
    stream.write("\r\n")

proc writeEnd*(stream: PosixStream; boundary: string) =
  stream.write("--" & boundary & "--\r\n")
