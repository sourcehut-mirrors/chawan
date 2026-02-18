{.push raises: [].}

import std/posix

import config/mimetypes
import io/packetreader
import io/packetwriter
import io/timeout
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jstypes
import monoucha/quickjs
import monoucha/tojs
import types/jsopt
import types/opt
import utils/twtstr

type
  DeallocFun = proc(opaque, p: pointer) {.nimcall, raises: [].}

  Blob* = ref object of RootObj
    size* {.jsget.}: int
    ctype* {.jsget: "type".}: string
    buffer*: pointer
    opaque*: pointer
    deallocFun*: DeallocFun

  WebFile* = ref object of Blob
    webkitRelativePath {.jsget.}: string
    name* {.jsget.}: string
    lastModified* {.jsget.}: int64
    fd*: cint

jsDestructor(Blob)
jsDestructor(WebFile)

# Forward declarations
proc deallocBlob*(opaque, p: pointer)

proc swrite*(w: var PacketWriter; blob: Blob) =
  w.swrite(blob of WebFile)
  if blob of WebFile:
    let file = WebFile(blob)
    let fd = dup(file.fd)
    w.swrite(fd != -1)
    if fd != -1:
      w.sendFd(fd)
    w.swrite(file.name)
  w.swrite(blob.ctype)
  w.swrite(blob.size)
  if blob.size > 0:
    w.writeData(blob.buffer, blob.size)

proc sread*(r: var PacketReader; blob: var Blob) =
  var isWebFile: bool
  r.sread(isWebFile)
  blob = if isWebFile: WebFile() else: Blob()
  if isWebFile:
    let file = WebFile(blob)
    var hasFd: bool
    r.sread(hasFd)
    if hasFd:
      file.fd = r.recvFd()
    else:
      file.fd = -1
    r.sread(file.name)
  r.sread(blob.ctype)
  r.sread(blob.size)
  if blob.size > 0:
    let buffer = alloc(blob.size)
    r.readData(buffer, blob.size)
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

proc newEmptyBlob*(contentType = ""): Blob =
  return newBlob(nil, 0, contentType, nil)

proc deallocBlob*(opaque, p: pointer) =
  if p != nil:
    dealloc(p)

template toOpenArray*(blob: Blob): openArray[char] =
  let p = cast[ptr UncheckedArray[char]](blob.buffer)
  if p != nil:
    p.toOpenArray(0, blob.size - 1)
  else:
    []

proc finalize(blob: Blob) {.jsfin.} =
  if blob.deallocFun != nil:
    blob.deallocFun(blob.opaque, blob.buffer)
    blob.buffer = nil

proc finalize(file: WebFile) {.jsfin.} =
  if file.fd != -1:
    discard close(file.fd)

proc newWebFile*(name: string; fd: cint): WebFile =
  return WebFile(
    name: name,
    fd: fd,
    ctype: DefaultGuess.guessContentType(name)
  )

type
  BlobPropertyBag = object of JSDict
    `type` {.jsdefault.}: string
    #TODO endings

  FilePropertyBag = object of BlobPropertyBag
    lastModified {.jsdefault: getUnixMillis().}: int64

proc newWebFile(ctx: JSContext; fileBits: seq[string]; fileName: string;
    options = FilePropertyBag(lastModified: getUnixMillis())): WebFile
    {.jsctor.} =
  let file = WebFile(
    name: fileName,
    fd: -1,
    lastModified: options.lastModified
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

#TODO Blob constructor

proc getSize*(this: Blob): int =
  if this of WebFile:
    let file = WebFile(this)
    if file.fd != -1:
      var statbuf: Stat
      if fstat(file.fd, statbuf) < 0:
        return 0
      return int(statbuf.st_size)
  return this.size

proc size*(this: WebFile): int {.jsfget.} =
  return this.getSize()

#TODO lastModified

proc addBlobModule*(ctx: JSContext): Opt[void] =
  let blobCID = ctx.registerType(Blob)
  if blobCID == 0:
    return err()
  ?ctx.registerType(WebFile, parent = blobCID, name = "File")
  ok()

{.pop.} # raises: []
