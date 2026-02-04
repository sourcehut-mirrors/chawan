import chagashi/charset
import chagashi/decoder
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jstypes
import monoucha/quickjs
import monoucha/tojs
import types/jsopt
import types/opt

type
  JSTextEncoder = ref object

  JSTextDecoder = ref object
    encoding {.jsget.}: Charset
    ignoreBOM {.jsget.}: bool
    errorMode: DecoderErrorMode
    stream: bool
    bomSeen: bool
    tdctx: TextDecoderContext

jsDestructor(JSTextDecoder)
jsDestructor(JSTextEncoder)

type TextDecoderOptions = object of JSDict
  fatal {.jsdefault.}: bool
  ignoreBOM {.jsdefault.}: bool

proc newJSTextDecoder(ctx: JSContext; label = "utf-8";
    options = TextDecoderOptions()): Opt[JSTextDecoder] {.jsctor.} =
  let encoding = getCharset(label)
  if encoding in {CHARSET_UNKNOWN, CHARSET_REPLACEMENT}:
    JS_ThrowRangeError(ctx, "invalid encoding label")
    return err()
  let errorMode = if options.fatal: demFatal else: demReplacement
  return ok(JSTextDecoder(
    ignoreBOM: options.ignoreBOM,
    errorMode: errorMode,
    tdctx: initTextDecoderContext(encoding, errorMode),
    encoding: encoding
  ))

proc fatal(this: JSTextDecoder): bool {.jsfget.} =
  return this.errorMode == demFatal

type TextDecodeOptions = object of JSDict
  stream {.jsdefault.}: bool

#TODO AllowSharedBufferSource
proc decode(ctx: JSContext; this: JSTextDecoder;
    jsInput: JSValueConst = JS_UNDEFINED; options = TextDecodeOptions()):
    JSValue {.jsfunc.} =
  var input: JSArrayBufferView
  if not JS_IsUndefined(jsInput):
    ?ctx.fromJS(jsInput, input)
  if not this.stream:
    this.tdctx = initTextDecoderContext(this.encoding, this.errorMode)
    this.bomSeen = false
  this.stream = options.stream
  if not JS_IsUndefined(jsInput):
    let H = int(input.abuf.len) - 1
    var oq = ""
    let stream = this.stream
    for chunk in this.tdctx.decode(input.abuf.p.toOpenArray(0, H), not stream):
      oq &= chunk
    if this.tdctx.failed:
      this.tdctx.failed = false
      return JS_ThrowTypeError(ctx, "failed to decode string")
    return JS_NewStringLen(ctx, cstring(oq), csize_t(oq.len))
  return JS_NewString(ctx, "")

proc newTextEncoder(): JSTextEncoder {.jsctor.} =
  return JSTextEncoder()

proc encoding(this: JSTextEncoder): string {.jsfget.} =
  return "utf-8"

proc deallocWrap(rt: JSRuntime; opaque, p: pointer) {.cdecl.} =
  if p != nil:
    dealloc(p)

proc encode(this: JSTextEncoder; input = ""): JSTypedArray {.jsfunc.} =
  # we have to validate input first :/
  #TODO it is possible to do less copies here...
  let input = input.toValidUTF8()
  let p = if input.len > 0:
    let buf = cast[ptr UncheckedArray[uint8]](alloc(input.len))
    copyMem(buf, unsafeAddr input[0], input.len)
    buf
  else:
    nil
  JSTypedArray(
    t: JS_TYPED_ARRAY_UINT8,
    abuf: JSArrayBuffer(p: p, len: csize_t(input.len), dealloc: deallocWrap)
  )

#TODO encodeInto

proc addEncodingModule*(ctx: JSContext): Opt[void] =
  ?ctx.registerType(JSTextDecoder, name = "TextDecoder")
  ?ctx.registerType(JSTextEncoder, name = "TextEncoder")
  ok()
