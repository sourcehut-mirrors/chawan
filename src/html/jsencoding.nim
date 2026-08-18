{.push raises: [].}

import encoding/charset
import encoding/decoder
import monoucha/fromjs
import monoucha/jsbind
import monoucha/jsref
import monoucha/jstypes
import monoucha/quickjs
import monoucha/tojs
import types/jsopt
import types/opt
import utils/twtstr

type
  JSTextDecoderObj = object
    encoding: Charset
    ignoreBOM: bool
    errorMode: DecoderErrorMode
    stream: bool
    bomSeen: bool
    tdctx: TextDecoderContext

  JSTextDecoder = JSRef[JSTextDecoderObj]

# TextDecoder
jsClassNameDef(JSTextDecoder, "TextDecoder"):
  jsget JSTextDecoder, ignoreBOM

  type TextDecoderOptions = object of JSDict
    fatal {.jsdefault.}: bool
    ignoreBOM {.jsdefault.}: bool

  proc newJSTextDecoder(ctx: JSContext; ctor: JSValueConst; label = "utf-8";
      options = TextDecoderOptions()): JSValue {.jsctor2.} =
    let encoding = getCharset(label)
    if encoding in {csUnknown, csReplacement}:
      return JS_ThrowRangeError(ctx, "invalid encoding label")
    let errorMode = if options.fatal: demFatal else: demReplacement
    return ctx.toJSNew(jsNew JSTextDecoderObj(
      ignoreBOM: options.ignoreBOM,
      errorMode: errorMode,
      tdctx: initTextDecoderContext(encoding, errorMode),
      encoding: encoding
    ), ctor)

  proc encoding(this: JSTextDecoder): string {.jsfget.} =
    return ($this[].encoding).toLowerAscii()

  proc fatal(this: JSTextDecoder): bool {.jsfget.} =
    return this.errorMode == demFatal

  type TextDecodeOptions = object of JSDict
    stream {.jsdefault.}: bool

  #TODO AllowSharedBufferSource
  proc decode(ctx: JSContext; this: JSTextDecoder;
      jsInput: JSValueConst = JS_UNDEFINED;
      jsOptions: JSValueConst = JS_UNDEFINED): JSValue {.jsfunc.} =
    var input: JSArrayBufferView
    if not JS_IsUndefined(jsInput):
      ?ctx.fromJS(jsInput, input)
    var options: TextDecodeOptions
    if not JS_IsUndefined(jsOptions):
      ?ctx.fromJS(jsOptions, options)
    if not this.stream:
      this.tdctx = initTextDecoderContext(this[].encoding, this.errorMode)
      this.bomSeen = false
    this.stream = options.stream
    var oq = ""
    let stream = this.stream
    if not JS_IsUndefined(jsInput):
      for chunk in this.tdctx.decode(input.toOpenArray(), not stream):
        oq &= chunk
    else:
      for chunk in this.tdctx.decode([], not stream):
        oq &= chunk
    if this.tdctx.failed:
      this.tdctx.failed = false
      return JS_ThrowTypeError(ctx, "failed to decode string")
    return JS_NewStringLen(ctx, oq.toCStringConst, csize_t(oq.len))

# TextEncoder
proc deallocWrap(rt: JSRuntime; opaque, p: pointer) {.cdecl.} =
  if p != nil:
    dealloc(p)

jsClassRaw(TextEncoderDef, "TextEncoder"):
  type JSTextEncoder = distinct pointer

  proc newTextEncoder(ctx: JSContext; ctor: JSValueConst): JSValue
      {.jsctor2.} =
    return JS_NewObjectFromCtor(ctx, ctor, classDef.id)

  proc encoding(ctx: JSContext; this: JSTextEncoder): JSValue {.jsfget.} =
    return ctx.toJS("utf-8")

  proc encode(this: JSTextEncoder; input = ""): JSArrayBufferView {.jsfunc.} =
    let p = if input.len > 0:
      let buf = cast[ptr UncheckedArray[uint8]](alloc(input.len))
      copyMem(buf, unsafeAddr input[0], input.len)
      buf
    else:
      nil
    JSArrayBufferView(
      t: JS_TYPED_ARRAY_UINT8,
      abuf: JSArrayBuffer(p: p, len: input.len, dealloc: deallocWrap),
      offset: 0,
      len: input.len
    )

  #TODO encodeInto

proc addEncodingModule*(ctx: JSContext): FromJSResult =
  ?ctx.registerClass(JSTextDecoderDef)
  ctx.registerClass(TextEncoderDef)

{.pop.}
