{.push raises: [].}

import std/posix

import config/mimetypes
import encoding/charset
import encoding/decoder
import html/catom
import html/domexception
import html/event
import io/dynstream
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
import utils/opt
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

  FileReaderState = enum
    frsEmpty = (0u16, "EMPTY")
    frsLoading = (1u16, "LOADING")
    frsDone = (2u16, "DONE")

  PackageType = enum
    ptDataURL, ptText, ptArrayBuffer, ptBinaryString

  FileReaderObj = object of EventTargetObj
    error: JSObject # may be nil
    result: JSValueTraced # may be null
    blob: Blob # may be nil
    readyState: FileReaderState
    packageType: PackageType

  FileReader = JSRef[FileReaderObj]

  ProgressEventObj {.pure, final.} = object of EventObj
    lengthComputable: bool
    loaded: float64
    total: float64

  ProgressEvent = JSRef[ProgressEventObj]

  ProgressEventInit = object of EventInit
    lengthComputable {.jsdefault.}: bool
    loaded {.jsdefault.}: float64
    total {.jsdefault.}: float64

# Forward declarations
proc deallocBlob*(opaque, p: pointer)
proc getClassID(t: typedesc[Blob]): JSClassID
proc getClassID*(t: typedesc[WebFile]): JSClassID
proc getClassID(t: typedesc[FileList]): JSClassID
proc getClassID(t: typedesc[FileReader]): JSClassID

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
    bptString, bptBlob, bptBufferSource

  BlobPart = ref object
    case t: BlobPartType
    of bptString:
      s: string
    of bptBlob:
      blob: Blob
    of bptBufferSource:
      abuf: BufferSource

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
  of bptBufferSource:
    let view = ctx.getUnsafeView(part.abuf)
    p = view.base
    return view.len

proc fromJS(ctx: JSContext; val: JSValueConst; res: var BlobPart):
    JSCode =
  var blob: Blob
  var abuf: BufferSource
  if ctx.fromJS(val, blob).isOk:
    #TODO this doesn't work for File
    res = BlobPart(t: bptBlob, blob: blob)
  elif ctx.fromJS(val, abuf).isOk:
    res = BlobPart(t: bptBufferSource, abuf: abuf)
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
    if int64(u) < int64(this.files.len):
      return this.files[int(u)]
    return WebFile(nil)

  proc getter(ctx: JSContext; this: FileList; atom: JSAtom): JSValue
      {.jsgetownprop.} =
    var u: uint32
    return case ctx.fromIdx(atom, u)
    of fiIdx: ctx.toJS(this.item(u)).uninitIfNull()
    of fiStr: JS_UNINITIALIZED
    of fiErr: JS_EXCEPTION

# ProgressEvent
jsClassDef(ProgressEvent):
  jsextends EventDef

  jsget ProgressEvent, lengthComputable
  jsget ProgressEvent, loaded
  jsget ProgressEvent, total

  proc newProgressEvent(eventType: CAtom; init = ProgressEventInit()):
      ProgressEvent {.jsctor.} =
    let event = jsNew ProgressEventObj(
      eventType: eventType,
      lengthComputable: init.lengthComputable,
      loaded: init.loaded,
      total: init.total
    )
    if event != nil:
      event.asEvent.innerEventCreationSteps(EventInit(init))
    event

proc fireProgressEvent*(ctx: JSContext; target: EventTarget; name: StaticAtom;
    loaded, length: int64) =
  let event = newProgressEvent(name.view(), ProgressEventInit(
    loaded: float64(loaded),
    total: float64(length),
    lengthComputable: length != 0
  ))
  if event != nil:
    event.asEvent.setTrusted()
    discard ctx.dispatch(target, event.asEvent)

# FileReader
#TODO definitely not compliant, but I guess it's fine for now
proc package(ctx: JSContext; s: openArray[char]; contentType: string;
    packageType: PackageType; jsEncoding: JSValueConst): JSValueTraced =
  case packageType
  of ptDataURL:
    var res = "data:" & contentType & ";base64,"
    res.btoa(s.toOpenArrayByte(0, s.high))
    return trace(ctx.toJS(res))
  of ptArrayBuffer:
    let p = if s.len > 0:
      cast[ptr UncheckedArray[uint8]](unsafeAddr s[0])
    else:
      nil
    return trace(JS_NewArrayBufferCopy(ctx, p, csize_t(s.len)))
  of ptText:
    var charset = csUnknown
    if not JS_IsUndefined(jsEncoding):
      discard ctx.fromJS(jsEncoding, charset)
    if charset == csUnknown:
      charset = getCharset(contentType.getContentTypeAttr("charset"))
    if charset == csUnknown:
      charset = csUtf8
    return trace(ctx.toJS(s.decodeAll(charset)))
  of ptBinaryString:
    if s.len == 0:
      return trace(JS_NewString(ctx, ""))
    let res = JS_NewNarrowStringLen(ctx, cast[cstring](unsafeAddr s[0]),
      csize_t(s.len))
    return trace(res)

proc fulfillReadJob(ctx: JSContext; argc: cint; argv: JSValueConstArray):
    JSValue {.cdecl.} =
  assert argc == 2
  var this: FileReader
  ?ctx.fromJS(argv[0], this)
  #TODO queue a task
  ctx.fireProgressEvent(this.asEventTarget, satLoadstart, 0, 0)
  this.readyState = frsDone
  var len: int
  if this.blob of WebFile:
    let fd = WebFile(this.blob).fd
    let ps = newPosixStream(fd)
    let res = ps.readAll()
    discard ps.seek(0)
    this.result = ?ctx.package(res, this.blob.contentType, this.packageType,
      argv[1])
    len = res.len
  else:
    this.result = ?ctx.package(this.blob.toOpenArray(), this.blob.contentType,
      this.packageType, argv[1])
    len = this.blob.size
  ctx.fireProgressEvent(this.asEventTarget, satLoad, int64(len), int64(len))
  if this.readyState == frsDone:
    ctx.fireProgressEvent(this.asEventTarget, satLoadend, int64(len),
      int64(len))
  return JS_UNDEFINED

jsClassDef(FileReader):
  jsextends EventTargetDef

  jsget FileReader, result
  jsget FileReader, error

  proc newFileReader(): FileReader {.jsctor.} =
    jsNew FileReaderObj()

  proc read(ctx: JSContext; jsThis: JSValueConst; packageType: PackageType;
      blob: Blob; encoding: JSValueConst = JS_UNDEFINED): JSValue {.
      jsmfunc("readAsArrayBuffer", ptArrayBuffer),
      jsmfunc("readAsBinaryString", ptBinaryString),
      jsmfunc("readAsText", ptText), jsmfunc("readAsDataURL", ptDataURL).} =
    var this: ptr FileReaderObj
    ?ctx.fromJS(jsThis, this)
    if this.readyState == frsLoading:
      return JS_ThrowDOMException(ctx, "InvalidStateError",
        "a file is already being loaded")
    this.readyState = frsLoading
    this.result = trace(JS_NULL)
    this.error = JSObject(nil)
    this.blob = blob
    this.packageType = packageType
    var encoding2 = trace(JS_UNDEFINED)
    if packageType == ptText and not JS_IsUndefined(encoding):
      var ds: DOMString
      ?ctx.fromJS(encoding, ds)
      encoding2 = ?trace(ctx.toJS(ds))
    ?ctx.enqueueJob(fulfillReadJob, jsThis, encoding2.v)
    return JS_UNDEFINED

  #TODO abort

  proc readyState(this: FileReader): uint16 {.jsfget.} =
    uint16(this.readyState)

  proc addFileReaderEvents(ctx: JSContext): Opt[void] =
    ctx.addEventGetSet(classDef.id, satLoadstart, satProgress, satLoad,
      satAbort, satError, satLoadend)

proc addBlobModule*(ctx: JSContext): Opt[void] =
  ?ctx.registerClass(BlobDef)
  ?ctx.registerClass(WebFileDef)
  ?ctx.registerClass(FileListDef)
  ?ctx.registerClass(FileReaderDef)
  ?ctx.registerClass(ProgressEventDef)
  ?ctx.defineConsts(FileReaderDef.id, FileReaderState)
  ctx.addFileReaderEvents()

{.pop.} # raises: []
