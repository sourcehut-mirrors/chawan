import std/options
import std/posix
import std/strutils

import io/bufreader
import io/bufwriter
import monoucha/fromjs
import monoucha/javascript
import monoucha/jstypes
import utils/mimeguess

type
  DeallocFun = proc(opaque, p: pointer) {.nimcall, raises: [].}

  Blob* = ref object of RootObj
    size* {.jsget.}: int
    ctype* {.jsget: "type".}: string
    buffer*: pointer
    opaque*: pointer
    deallocFun*: DeallocFun
    fd*: Option[FileHandle]

  WebFile* = ref object of Blob
    webkitRelativePath {.jsget.}: string
    name* {.jsget.}: string

jsDestructor(Blob)
jsDestructor(WebFile)

# Forward declarations
proc deallocBlob*(opaque, p: pointer) {.raises: [].}

#TODO it would be nice if we had a separate fd type that does sendAux;
# this solution fails when blob isn't swritten by some module that does
# not import it (just as a transitive dependency).
proc swrite*(writer: var BufferedWriter; blob: Blob) =
  if blob.fd.isSome:
    writer.sendAux.add(blob.fd.get)
  writer.swrite(blob of WebFile)
  if blob of WebFile:
    writer.swrite(WebFile(blob).name)
  writer.swrite(blob.fd.isSome)
  writer.swrite(blob.ctype)
  writer.swrite(blob.size)
  if blob.size > 0:
    writer.writeData(blob.buffer, blob.size)

proc sread*(reader: var BufferedReader; blob: var Blob) =
  var isWebFile: bool
  reader.sread(isWebFile)
  blob = if isWebFile: WebFile() else: Blob()
  if isWebFile:
    reader.sread(WebFile(blob).name)
  var hasFd: bool
  reader.sread(hasFd)
  if hasFd:
    blob.fd = some(reader.recvAux.pop())
  reader.sread(blob.ctype)
  reader.sread(blob.size)
  if blob.size > 0:
    let buffer = alloc(blob.size)
    reader.readData(blob.buffer, blob.size)
    blob.buffer = buffer
    blob.deallocFun = deallocBlob

proc newBlob*(buffer: pointer; size: int; ctype: string;
    deallocFun: DeallocFun; opaque: pointer = nil): Blob =
  return Blob(
    buffer: buffer,
    size: size,
    ctype: ctype,
    deallocFun: deallocFun,
    opaque: opaque
  )

proc deallocBlob*(opaque, p: pointer) =
  if p != nil:
    dealloc(p)

proc finalize(blob: Blob) {.jsfin.} =
  if blob.fd.isSome:
    discard close(blob.fd.get)
  if blob.deallocFun != nil:
    blob.deallocFun(blob.opaque, blob.buffer)
    blob.buffer = nil

proc finalize(file: WebFile) {.jsfin.} =
  Blob(file).finalize()

proc newWebFile*(name: string; fd: FileHandle): WebFile =
  return WebFile(
    name: name,
    fd: some(fd),
    ctype: DefaultGuess.guessContentType(name)
  )

type
  BlobPropertyBag = object of JSDict
    `type` {.jsdefault.}: string
    #TODO endings

  FilePropertyBag = object of BlobPropertyBag
    #TODO lastModified: int64

proc newWebFile(ctx: JSContext; fileBits: seq[string]; fileName: string;
    options = FilePropertyBag()): WebFile {.jsctor.} =
  let file = WebFile(
    name: fileName
  )
  var len = 0
  for blobPart in fileBits:
    len += blobPart.len
  let buffer = alloc(len)
  file.buffer = buffer
  file.deallocFun = deallocBlob
  var buf = cast[ptr UncheckedArray[uint8]](file.buffer)
  var i = 0
  for blobPart in fileBits:
    if blobPart.len > 0:
      copyMem(addr buf[i], unsafeAddr blobPart[0], blobPart.len)
      i += blobPart.len
  file.size = len
  block ctype:
    for c in options.`type`:
      if c notin char(0x20)..char(0x7E):
        break ctype
      file.ctype &= c.toLowerAscii()
  return file

#TODO File, Blob constructors

proc getSize*(this: Blob): int =
  if this.fd.isSome:
    var statbuf: Stat
    if fstat(this.fd.get, statbuf) < 0:
      return 0
    return int(statbuf.st_size)
  return this.size

proc size*(this: WebFile): int {.jsfget.} =
  return this.getSize()

#TODO lastModified

proc addBlobModule*(ctx: JSContext) =
  let blobCID = ctx.registerType(Blob)
  ctx.registerType(WebFile, parent = blobCID, name = "File")
