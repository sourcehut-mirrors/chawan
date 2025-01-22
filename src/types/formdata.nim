import std/strutils

import io/bufreader
import io/bufwriter
import io/dynstream
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

proc swrite*(writer: var BufferedWriter; part: FormDataEntry) =
  writer.swrite(part.isstr)
  writer.swrite(part.name)
  writer.swrite(part.filename)
  if part.isstr:
    writer.swrite(part.svalue)
  else:
    writer.swrite(part.value)

proc sread*(reader: var BufferedReader; part: var FormDataEntry) =
  var isstr: bool
  reader.sread(isstr)
  if isstr:
    part = FormDataEntry(isstr: true)
  else:
    part = FormDataEntry(isstr: false)
  reader.sread(part.name)
  reader.sread(part.filename)
  if part.isstr:
    reader.sread(part.svalue)
  else:
    reader.sread(part.value)

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
      result += int(entry.value.getSize())
    result += "\r\n".len # header is always followed by \r\n
    result += "\r\n".len # value is always followed by \r\n
  result += "--".len + this.boundary.len + "--\r\n".len
  result += "\r\n".len

proc getContentType*(this: FormData): string =
  return "multipart/form-data; boundary=" & this.boundary

proc writeEntry*(stream: DynStream; entry: FormDataEntry; boundary: string) =
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
    if blob.fd.isSome:
      let ps = newPosixStream(blob.fd.get)
      if ps != nil:
        var buf {.noinit.}: array[4096, uint8]
        while true:
          let n = ps.recvData(buf)
          if n == 0:
            break
          stream.sendDataLoop(addr buf[0], n)
          if n < buf.len:
            break
    else:
      stream.sendDataLoop(blob.buffer, blob.size)
    stream.write("\r\n")

proc writeEnd*(stream: DynStream; boundary: string) =
  stream.write("--" & boundary & "--\r\n")
  stream.write("\r\n")
