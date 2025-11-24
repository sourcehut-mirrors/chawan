import std/strutils

import io/dynstream
import io/packetreader
import io/packetwriter
import monoucha/jsbind
import types/blob
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
    if blob of WebFile and WebFile(blob).fd != -1:
      let ps = newPosixStream(WebFile(blob).fd)
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
