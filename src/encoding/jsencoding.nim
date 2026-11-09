{.push raises: [].}

import encoding/charset
import encoding/decoder
import js/constcharp
import js/fromjs
import js/jsbind
import js/jsref
import js/jstypes
import js/jsutils
import js/quickjs
import js/tojs
import utils/cowstr
import utils/opt

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

  proc newJSTextDecoder(ctx: JSContext; ctor: JSValueConst;
      label = str("utf-8"); options = TextDecoderOptions()): JSValue {.jsctor2.} =
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

  proc encoding(this: JSTextDecoder): Str {.jsfget.} =
    return this[].encoding.toStr().toLowerAscii()

  proc fatal(this: JSTextDecoder): bool {.jsfget.} =
    return this.errorMode == demFatal

  type TextDecodeOptions = object of JSDict
    stream {.jsdefault.}: bool

  #TODO AllowSharedBufferSource
  proc decode(ctx: JSContext; this: JSTextDecoder; input = BufferSource(nil);
      options = TextDecodeOptions()): JSValue {.jsfunc.} =
    if not this.stream:
      this.tdctx = initTextDecoderContext(this[].encoding, this.errorMode)
      this.bomSeen = false
    this.stream = options.stream
    var oq = initGrowbuf()
    let stream = this.stream
    if input != nil:
      for chunk in this.tdctx.decode(input.toOpenArray(ctx), not stream):
        oq &= chunk
    else:
      for chunk in this.tdctx.decode([], not stream):
        oq &= chunk
    if this.tdctx.failed:
      this.tdctx.failed = false
      return JS_ThrowTypeError(ctx, "failed to decode string")
    return ctx.toJS(oq)

# TextEncoder
proc deallocCString(rt: JSRuntime; opaque, p: pointer) {.cdecl.} =
  if opaque != nil:
    JS_FreeCStringRT(rt, cast[cstringConst](p))

jsClassRaw(TextEncoderDef, "TextEncoder"):
  type JSTextEncoder = distinct pointer

  proc newTextEncoder(ctx: JSContext; ctor: JSValueConst): JSValue
      {.jsctor2.} =
    return JS_CreateFromConstructor(ctx, ctor, classDef.id)

  proc encoding(ctx: JSContext; this: JSTextEncoder): JSValue {.jsfget.} =
    return ctx.toJS("utf-8")

  proc encode(ctx: JSContext; this: JSTextEncoder; input = JS_UNDEFINED.vc):
      JSValue {.jsfunc.} =
    var p: ptr UncheckedArray[uint8]
    var len = 0
    if not JS_IsUndefined(input):
      var len2: csize_t
      p = cast[typeof(p)](JS_ToCStringUSVLen(ctx, len2, input))
      if p == nil:
        return JS_EXCEPTION
      len = cast[int](len2) # valid because of QJS string limit
    ctx.toJS(JSArrayBufferViewInit(
      t: JS_TYPED_ARRAY_UINT8,
      abuf: JSArrayBufferInit(p: p, len: len, dealloc: deallocCString),
      offset: 0,
      len: len
    ))

  #TODO encodeInto

proc addEncodingModule*(ctx: JSContext): JSCode =
  ?ctx.registerClass(JSTextDecoderDef)
  ctx.registerClass(TextEncoderDef)

{.pop.}
