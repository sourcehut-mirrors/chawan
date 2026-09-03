{.push raises: [].}

import std/posix

import config/mimetypes
import html/catom
import io/packetreader
import io/packetwriter
import io/timeout
import js/fromjs
import js/jsbind
import js/jsref
import js/jstypes
import js/jsutils
import js/quickjs
import js/tojs
import types/jsopt
import types/opt
import utils/twtstr

type
  DeallocFun = proc(opaque, p: pointer) {.nimcall, raises: [].}

  BlobObj {.pure.} = object of JSRootObj
    size*: int
    contentType*: string
    buffer*: pointer
    opaque*: pointer
    deallocFun*: DeallocFun

  Blob* = JSRef[BlobObj]

  WebFileObj {.pure, final.} = object of BlobObj
    webkitRelativePath: string
    name*: string
    lastModified*: int64
    fd*: cint

  WebFile* = JSRef[WebFileObj]

  FileListObj* = object
    files: seq[WebFile]

  FileList* = JSRef[FileListObj]

  EndingType = enum
    etTransparent = "transparent"
    etNative = "native"

# Forward declarations
proc deallocBlob*(opaque, p: pointer)
proc getClassID(t: typedesc[Blob]): JSClassID
proc getClassID*(t: typedesc[WebFile]): JSClassID
proc getClassID(t: typedesc[FileList]): JSClassID

# Iterators
iterator items*(this: FileList): lent WebFile =
  for it in this.files:
    yield it

# Blob
template asBlob*[T: BlobObj](x: JSRef[T]): Blob =
  Blob(x)

proc swrite*(w: var PacketWriter; blob: Blob) =
  w.swrite(blob of WebFile)
  if blob of WebFile:
    let file = WebFile(blob)
    let fd = dup(file.fd)
    w.swrite(fd != -1)
    if fd != -1:
      w.sendFd(fd)
    w.swrite(file.name)
  w.swrite(blob.contentType)
  w.swrite(blob.size)
  if blob.size > 0:
    w.writeData(blob.buffer, blob.size)

proc sread*(r: var PacketReader; blob: var Blob) =
  var isWebFile: bool
  r.sread(isWebFile)
  blob = if isWebFile: (jsNew WebFileObj()).asBlob else: jsNew BlobObj()
  assert blob != nil
  if isWebFile:
    let file = WebFile(blob)
    var hasFd: bool
    r.sread(hasFd)
    if hasFd:
      file.fd = r.recvFd()
    else:
      file.fd = -1
    r.sread(file.name)
  r.sread(blob.contentType)
  r.sread(blob.size)
  if blob.size > 0:
    let buffer = alloc(blob.size)
    r.readData(buffer, blob.size)
    blob.buffer = buffer
    blob.deallocFun = deallocBlob

type
  BlobPropertyBag = object of JSDict
    `type` {.jsdefault.}: DOMString
    endings {.jsdefault.}: EndingType

  BlobPartType = enum
    bptString, bptBlob, bptArrayBuffer, bptArrayBufferView

  BlobPart = ref object
    case t: BlobPartType
    of bptString:
      s: string
    of bptBlob:
      blob: Blob
    of bptArrayBuffer, bptArrayBufferView:
      obj: JSObject

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
    if ctx.fromJS(part.obj.value, abuf).isErr:
      p = nil
      return -1
    p = abuf.p
    return abuf.len
  of bptArrayBufferView:
    var view: JSArrayBufferView
    if ctx.fromJS(part.obj.value, view).isErr:
      p = nil
      return -1
    p = view.base
    return view.len

proc fromJS(ctx: JSContext; val: JSValueConst; res: var BlobPart):
    JSCode =
  var blob: Blob
  var abuf: JSArrayBuffer
  var view: JSArrayBufferView
  if ctx.fromJS(val, blob).isOk:
    #TODO this doesn't work for File
    res = BlobPart(t: bptBlob, blob: blob)
  elif ctx.fromJS(val, abuf).isOk:
    res = BlobPart(t: bptArrayBuffer, obj: ctx.dupTraceObj(val))
  elif ctx.fromJS(val, view).isOk:
    res = BlobPart(t: bptArrayBufferView, obj: ctx.dupTraceObj(val))
  else:
    res = BlobPart(t: bptString)
    ?ctx.fromJS(val, res.s)
  fjOk

proc init(ctx: JSContext; blob: Blob; parts: seq[BlobPart];
    blobType: DOMString): Opt[void] =
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
    i += n
  blob.size = len
  if AllChars - {char(0x20)..char(0x7E)} notin blobType.toOpenArray():
    blob.contentType = blobType.toOpenArray().toLowerAscii()
  ok()

proc init(ctx: JSContext; blob: Blob; parts: seq[BlobPart];
    blobType: DOMString; endings: EndingType): Opt[void] =
  if endings == etNative:
    for part in parts:
      if part.t == bptString:
        part.s = part.s.normalizeLF()
  ctx.init(blob, parts, blobType)

proc newBlob*(buffer: pointer; size: int; contentType: string;
    deallocFun: DeallocFun; opaque: pointer = nil): Blob =
  jsNew BlobObj(
    buffer: buffer,
    size: size,
    contentType: contentType,
    deallocFun: deallocFun,
    opaque: opaque
  )

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
  let p = cast[ptr UncheckedArray[char]](blob[].buffer)
  if p != nil:
    p.toOpenArray(0, blob[].size - 1)
  else:
    p.toOpenArray(0, -1)

jsClassDef(Blob):
  jsget Blob, size
  jsget Blob, contentType, "type"

  proc newBlob(ctx: JSContext; blobParts: seq[BlobPart] = @[];
      options = BlobPropertyBag()): Opt[Blob] {.jsctor.} =
    let blob = jsNew BlobObj()
    if blob != nil:
      ?ctx.init(blob, blobParts, options.`type`, options.endings)
    ok(blob)

  proc finalize(rt: JSRuntime; blob: Blob) {.jsfin.} =
    if blob.deallocFun != nil:
      blob[].deallocFun(blob.opaque, blob.buffer)
      blob.buffer = nil

# File
proc newWebFile*(name: string; fd: cint): WebFile =
  jsNew WebFileObj(
    name: name,
    fd: fd,
    contentType: DefaultGuess.guessContentType(name)
  )

type FilePropertyBag = object of BlobPropertyBag
  lastModified {.jsdefault: getUnixMillis().}: int64

jsClassPublicNameDef(WebFile, "File"):
  jsextends BlobDef

  jsget WebFile, webkitRelativePath
  jsget WebFile, name
  jsget WebFile, lastModified

  proc finalize(rt: JSRuntime; file: WebFile) {.jsfin.} =
    if file.fd != -1:
      discard close(file.fd)

  proc newWebFile(ctx: JSContext; fileBits: seq[BlobPart]; fileName: string;
      options = FilePropertyBag(lastModified: getUnixMillis())): Opt[WebFile]
      {.jsctor.} =
    let file = jsNew WebFileObj(
      name: fileName,
      fd: -1,
      lastModified: options.lastModified
    )
    if file != nil:
      ?ctx.init(cast[Blob](file), fileBits, options.`type`, options.endings)
    ok(file)

  proc size*(this: WebFile): int {.jsfget.} =
    return cast[Blob](this).getSize()

#TODO lastModified

# FileList
proc newFileList*(): FileList =
  return jsNew FileListObj()

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

jsClassDef(FileList):
  classDef.iterable = jitValue

  proc mark(rt: JSRuntime; this: FileList; markFunc: JS_MarkFunc) {.jsmark.} =
    for file in this.files:
      rt.markObj(file, markFunc)

  proc length(this: FileList): uint32 {.jsfget.} =
    uint32(this.files.len)

  proc item(this: FileList; u: uint32): WebFile {.jsfunc.} =
    if u >= 0 and int64(u) < int64(this.files.len):
      return this.files[int(u)]
    return WebFile(nil)

  proc getter(ctx: JSContext; this: FileList; atom: JSAtom): JSValue
      {.jsgetownprop.} =
    var u: uint32
    return case ctx.fromIdx(atom, u)
    of fiIdx: ctx.toJS(this.item(u)).uninitIfNull()
    of fiStr: JS_UNINITIALIZED
    of fiErr: JS_EXCEPTION

proc addBlobModule*(ctx: JSContext): Opt[void] =
  ?ctx.registerClass(BlobDef)
  ?ctx.registerClass(WebFileDef)
  ?ctx.registerClass(FileListDef)
  ok()

{.pop.} # raises: []
