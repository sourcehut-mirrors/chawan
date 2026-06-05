{.push raises: [].}

import std/posix

import config/mimetypes
import html/catom
import io/packetreader
import io/packetwriter
import io/timeout
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsopaque
import monoucha/jstypes
import monoucha/jsutils
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

  FileList* = ref object
    files: seq[WebFile]

  EndingType = enum
    etTransparent = "transparent"
    etNative = "native"

jsDestructor(Blob)
jsDestructor(WebFile)
jsDestructor(FileList)

# Forward declarations
proc deallocBlob*(opaque, p: pointer)

# Iterators
iterator items*(this: FileList): lent WebFile =
  for it in this.files:
    yield it

# Blob
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

type
  BlobPropertyBag = object of JSDict
    `type` {.jsdefault.}: string
    endings {.jsdefault.}: EndingType

  BlobPartType = enum
    bptString, bptBlob, bptArrayBuffer, bptArrayBufferView

  BlobPartObj = object
    case t: BlobPartType
    of bptString:
      s: string
    of bptBlob:
      blob: Blob
    of bptArrayBuffer, bptArrayBufferView:
      val: JSValue

  BlobPart = ref BlobPartObj

proc getBase(ctx: JSContext; part: BlobPart; p: var pointer): int =
  case part.t
  of bptString:
    if part.s.len > 0:
      p = addr part.s[0]
    else:
      p = nil
    return part.s.len
  of bptBlob:
    p = part.blob.buffer
    return part.blob.size
  of bptArrayBuffer:
    var abuf: JSArrayBuffer
    if ctx.fromJS(part.val, abuf).isErr:
      p = nil
      return -1
    p = abuf.p
    return abuf.len
  of bptArrayBufferView:
    var view: JSArrayBufferView
    if ctx.fromJS(part.val, view).isErr:
      p = nil
      return -1
    p = view.base
    return view.len

proc `=destroy`(obj: var BlobPartObj) =
  if obj.t in {bptArrayBuffer, bptArrayBufferView}:
    JS_FreeValueRT(globalRuntime, obj.val)

proc fromJS(ctx: JSContext; val: JSValueConst; res: var BlobPart):
    FromJSResult =
  var blob: Blob
  var abuf: JSArrayBuffer
  var view: JSArrayBufferView
  if ctx.fromJS(val, blob).isOk:
    #TODO this doesn't work for File
    res = BlobPart(t: bptBlob, blob: blob)
  elif ctx.fromJS(val, abuf).isOk:
    res = BlobPart(t: bptArrayBuffer, val: JS_DupValue(ctx, val))
  elif ctx.fromJS(val, view).isOk:
    res = BlobPart(t: bptArrayBufferView, val: JS_DupValue(ctx, val))
  else:
    res = BlobPart(t: bptString)
    ?ctx.fromJS(val, res.s)
  fjOk

proc init(ctx: JSContext; blob: Blob; parts: seq[BlobPart]; blobType: string):
    Opt[void] =
  var len = 0
  for part in parts:
    var p: pointer
    let n = ctx.getBase(part, p)
    if n < 0:
      return err()
    len += n
  blob.buffer = alloc(len)
  blob.deallocFun = deallocBlob
  let buffer = cast[ptr UncheckedArray[uint8]](blob.buffer)
  var i = 0
  for part in parts:
    var p: pointer
    let n = ctx.getBase(part, p)
    if n < 0:
      return err()
    assert i + n <= len
    copyMem(addr buffer[i], p, n)
    i += len
  blob.size = len
  if AllChars - {char(0x20)..char(0x7E)} notin blobType:
    blob.ctype = blobType.toLowerAscii()
  ok()

proc init(ctx: JSContext; blob: Blob; parts: seq[BlobPart]; blobType: string;
    endings: EndingType): Opt[void] =
  if endings == etNative:
    for part in parts:
      if part.t == bptString:
        part.s = part.s.normalizeLF()
  ctx.init(blob, parts, blobType)

proc newBlob(ctx: JSContext; blobParts: seq[BlobPart] = @[];
    options = BlobPropertyBag()): Opt[Blob] {.jsctor.} =
  let blob = Blob()
  ?ctx.init(blob, blobParts, options.`type`, options.endings)
  ok(blob)

proc newBlob*(buffer: pointer; size: int; ctype: string;
    deallocFun: DeallocFun; opaque: pointer = nil): Blob =
  return Blob(
    buffer: buffer,
    size: size,
    ctype: ctype,
    deallocFun: deallocFun,
    opaque: opaque
  )

proc finalize(blob: Blob) {.jsfin.} =
  if blob.deallocFun != nil:
    blob.deallocFun(blob.opaque, blob.buffer)
    blob.buffer = nil

proc newEmptyBlob*(contentType = ""): Blob =
  return newBlob(nil, 0, contentType, nil)

proc deallocBlob*(opaque, p: pointer) =
  if p != nil:
    dealloc(p)

proc getSize*(this: Blob): int =
  if this of WebFile:
    let file = WebFile(this)
    if file.fd != -1:
      var statbuf: Stat
      if fstat(file.fd, statbuf) < 0:
        return 0
      return int(statbuf.st_size)
  return this.size

template toOpenArray*(blob: Blob): openArray[char] =
  let p = cast[ptr UncheckedArray[char]](blob.buffer)
  if p != nil:
    p.toOpenArray(0, blob.size - 1)
  else:
    []

# File
proc newWebFile*(name: string; fd: cint): WebFile =
  return WebFile(
    name: name,
    fd: fd,
    ctype: DefaultGuess.guessContentType(name)
  )

proc finalize(file: WebFile) {.jsfin.} =
  if file.fd != -1:
    discard close(file.fd)

type FilePropertyBag = object of BlobPropertyBag
  lastModified {.jsdefault: getUnixMillis().}: int64

proc newWebFile(ctx: JSContext; fileBits: seq[BlobPart]; fileName: string;
    options = FilePropertyBag(lastModified: getUnixMillis())): Opt[WebFile]
    {.jsctor.} =
  let file = WebFile(
    name: fileName,
    fd: -1,
    lastModified: options.lastModified
  )
  ?ctx.init(file, fileBits, options.`type`, options.endings)
  ok(file)

proc size*(this: WebFile): int {.jsfget.} =
  return this.getSize()

#TODO lastModified

# FileList
proc newFileList*(): FileList =
  return FileList()

proc getName*(this: FileList): string =
  var res = ""
  for i in 0 ..< this.files.len:
    if i != 0:
      res &= ','
    res &= this.files[i].name
  move(res)

proc add*(this: FileList; file: WebFile) =
  this.files.add(file)

proc clear*(this: FileList) =
  this.files.setLen(0)

proc length(this: FileList): uint32 {.jsfget.} =
  uint32(this.files.len)

proc item(this: FileList; u: uint32): WebFile {.jsfunc.} =
  if u >= 0 and int64(u) < int64(this.files.len):
    return this.files[int(u)]
  return nil

proc getter(ctx: JSContext; this: FileList; atom: JSAtom): JSValue
    {.jsgetownprop.} =
  var u: uint32
  return case ctx.fromIdx(atom, u)
  of fiIdx: ctx.toJS(this.item(u)).uninitIfNull()
  of fiStr: JS_UNINITIALIZED
  of fiErr: JS_EXCEPTION

proc addBlobModule*(ctx: JSContext): Opt[void] =
  let blobCID = ctx.registerType(Blob)
  if blobCID == 0:
    return err()
  ?ctx.registerType(WebFile, parent = blobCID, name = "File")
  ?ctx.registerType(FileList, iterable = jitValue)
  ok()

{.pop.} # raises: []
