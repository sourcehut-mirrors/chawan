{.push raises: [].}

import std/math

import html/event
import io/dynstream
import io/packetwriter
import monoucha/fromjs
import monoucha/javascript
import monoucha/quickjs
import monoucha/tojs
import server/headers
import server/loaderiface
import server/request
import server/response
import types/bitmap
import types/canvastypes
import types/color
import types/opt
import types/path
import utils/strwidth
import utils/twtstr

type
  DrawingState = object
    # CanvasTransform
    transformMatrix: Matrix
    # CanvasFillStrokeStyles
    fillStyle: ARGBColor
    strokeStyle: ARGBColor
    # CanvasPathDrawingStyles
    lineWidth: float64
    # CanvasTextDrawingStyles
    textAlign: CanvasTextAlign
    # CanvasPath
    path: Path

  TextMetrics = ref object
    # x-direction
    width {.jsget.}: float64
    actualBoundingBoxLeft {.jsget.}: float64
    actualBoundingBoxRight {.jsget.}: float64
    # y-direction
    fontBoundingBoxAscent {.jsget.}: float64
    fontBoundingBoxDescent {.jsget.}: float64
    actualBoundingBoxAscent {.jsget.}: float64
    actualBoundingBoxDescent {.jsget.}: float64
    emHeightAscent {.jsget.}: float64
    emHeightDescent {.jsget.}: float64
    hangingBaseline {.jsget.}: float64
    alphabeticBaseline {.jsget.}: float64
    ideographicBaseline {.jsget.}: float64

  CanvasRenderingContext2D* = ref object
    canvas {.jsget.}: EventTarget
    bitmap: NetworkBitmap
    state: DrawingState
    stateStack: seq[DrawingState]
    ps*: PosixStream

jsDestructor(CanvasRenderingContext2D)
jsDestructor(TextMetrics)

# Forward declaration hack
var parseColorImpl*: proc(target: EventTarget; s: string): Opt[ARGBColor]
  {.nimcall, raises: [].}

proc parseColor(target: EventTarget; s: string): Opt[ARGBColor] =
  return target.parseColorImpl(s)

proc resetTransform(state: var DrawingState) =
  state.transformMatrix = newIdentityMatrix(3)

proc reset*(state: var DrawingState) =
  state.resetTransform()
  state.fillStyle = rgba(0, 0, 0, 255)
  state.strokeStyle = rgba(0, 0, 0, 255)
  state.path = newPath()

proc create2DContext*(loader: FileLoader; target: EventTarget;
    bitmap: NetworkBitmap; options: JSValueConst = JS_UNDEFINED):
    CanvasRenderingContext2D =
  let imageId = bitmap.imageId
  let (ps, ctlres) = loader.doPipeRequest("canvas-ctl-" & $imageId)
  if ps == nil:
    return nil
  let cacheId = loader.addCacheFile(ctlres.outputId)
  bitmap.cacheId = cacheId
  let request = newRequest(
    "img-codec+x-cha-canvas:decode",
    httpMethod = hmPost,
    headers = newHeaders(hgRequest, {"Cha-Image-Info-Only": "1"}),
    body = RequestBody(t: rbtOutput, outputId: ctlres.outputId)
  )
  let response = loader.doRequest(request)
  if response.res != 0:
    # no canvas module; give up
    ps.sclose()
    ctlres.close()
    return nil
  ctlres.close()
  response.close()
  ps.withPacketWriterFire w:
    w.swrite(pcSetDimensions)
    w.swrite(bitmap.width)
    w.swrite(bitmap.height)
  let ctx2d = CanvasRenderingContext2D(bitmap: bitmap, canvas: target, ps: ps)
  ctx2d.state.reset()
  return ctx2d

proc fillRect(ctx: CanvasRenderingContext2D; x1, y1, x2, y2: int;
    color: ARGBColor) =
  if ctx.ps != nil:
    ctx.ps.withPacketWriterFire w:
      w.swrite(pcFillRect)
      w.swrite(x1)
      w.swrite(y1)
      w.swrite(x2)
      w.swrite(y2)
      w.swrite(color)

proc strokeRect(ctx: CanvasRenderingContext2D; x1, y1, x2, y2: int;
    color: ARGBColor) =
  if ctx.ps != nil:
    ctx.ps.withPacketWriterFire w:
      w.swrite(pcStrokeRect)
      w.swrite(x1)
      w.swrite(y1)
      w.swrite(x2)
      w.swrite(y2)
      w.swrite(color)

proc fillPath(ctx: CanvasRenderingContext2D; path: Path; color: ARGBColor;
    fillRule: CanvasFillRule) =
  if ctx.ps != nil:
    let lines = path.getLineSegments()
    ctx.ps.withPacketWriterFire w:
      w.swrite(pcFillPath)
      w.swrite(lines)
      w.swrite(color)
      w.swrite(fillRule)

proc strokePath(ctx: CanvasRenderingContext2D; path: Path; color: ARGBColor) =
  if ctx.ps != nil:
    let lines = path.getLines()
    ctx.ps.withPacketWriterFire w:
      w.swrite(pcStrokePath)
      w.swrite(lines)
      w.swrite(color)

proc fillText(ctx: CanvasRenderingContext2D; text: string; x, y: float64;
    color: ARGBColor; align: CanvasTextAlign) =
  if ctx.ps != nil:
    ctx.ps.withPacketWriterFire w:
      w.swrite(pcFillText)
      w.swrite(text)
      w.swrite(x)
      w.swrite(y)
      w.swrite(color)
      w.swrite(align)

proc strokeText(ctx: CanvasRenderingContext2D; text: string; x, y: float64;
    color: ARGBColor; align: CanvasTextAlign) =
  if ctx.ps != nil:
    ctx.ps.withPacketWriterFire w:
      w.swrite(pcStrokeText)
      w.swrite(text)
      w.swrite(x)
      w.swrite(y)
      w.swrite(color)
      w.swrite(align)

proc clearRect(ctx: CanvasRenderingContext2D; x1, y1, x2, y2: int) =
  ctx.fillRect(0, 0, ctx.bitmap.width, ctx.bitmap.height, rgba(0, 0, 0, 0))

proc clear(ctx: CanvasRenderingContext2D) =
  ctx.clearRect(0, 0, ctx.bitmap.width, ctx.bitmap.height)

proc save(ctx: CanvasRenderingContext2D) {.jsfunc.} =
  ctx.stateStack.add(ctx.state)

proc restore(ctx: CanvasRenderingContext2D) {.jsfunc.} =
  if ctx.stateStack.len > 0:
    ctx.state = ctx.stateStack.pop()

proc reset(ctx: CanvasRenderingContext2D) {.jsfunc.} =
  ctx.clear()
  ctx.stateStack.setLen(0)
  ctx.state.reset()

#TODO scale
proc rotate(ctx: CanvasRenderingContext2D; angle: float64) {.jsfunc.} =
  if classify(angle) in {fcInf, fcNegInf, fcNan}:
    return
  ctx.state.transformMatrix *= newMatrix(
    me = @[
      cos(angle), -sin(angle), 0,
      sin(angle), cos(angle), 0,
      0, 0, 1
    ],
    w = 3,
    h = 3
  )

proc translate(ctx: CanvasRenderingContext2D; x, y: float64) {.jsfunc.} =
  for v in [x, y]:
    if classify(v) in {fcInf, fcNegInf, fcNan}:
      return
  ctx.state.transformMatrix *= newMatrix(
    me = @[
      1f64, 0, x,
      0, 1, y,
      0, 0, 1
    ],
    w = 3,
    h = 3
  )

proc transform(ctx: CanvasRenderingContext2D; a, b, c, d, e, f: float64)
    {.jsfunc.} =
  for v in [a, b, c, d, e, f]:
    if classify(v) in {fcInf, fcNegInf, fcNan}:
      return
  ctx.state.transformMatrix *= newMatrix(
    me = @[
      a, c, e,
      b, d, f,
      0, 0, 1
    ],
    w = 3,
    h = 3
  )

#TODO getTransform, setTransform with DOMMatrix (i.e. we're missing DOMMatrix)
proc setTransform(ctx: CanvasRenderingContext2D; a, b, c, d, e, f: float64)
    {.jsfunc.} =
  for v in [a, b, c, d, e, f]:
    if classify(v) in {fcInf, fcNegInf, fcNan}:
      return
  ctx.state.resetTransform()
  ctx.transform(a, b, c, d, e, f)

proc resetTransform(ctx: CanvasRenderingContext2D) {.jsfunc.} =
  ctx.state.resetTransform()

proc transform(ctx: CanvasRenderingContext2D; v: Vector2D): Vector2D =
  let mul = ctx.state.transformMatrix * newMatrix(@[v.x, v.y, 1], 1, 3)
  return Vector2D(x: mul.me[0], y: mul.me[1])

proc fillStyle(ctx: CanvasRenderingContext2D): string {.jsfget.} =
  return ctx.state.fillStyle.serialize()

proc fillStyle(ctx: CanvasRenderingContext2D; s: string) {.jsfset.} =
  #TODO gradient, pattern
  if color := ctx.canvas.parseColor(s):
    ctx.state.fillStyle = color

proc strokeStyle(ctx: CanvasRenderingContext2D): string {.jsfget.} =
  return ctx.state.strokeStyle.serialize()

proc strokeStyle(ctx: CanvasRenderingContext2D; s: string) {.jsfset.} =
  #TODO gradient, pattern
  if color := ctx.canvas.parseColor(s):
    ctx.state.strokeStyle = color

proc clearRect(ctx: CanvasRenderingContext2D; x, y, w, h: float64) {.jsfunc.} =
  for v in [x, y, w, h]:
    if classify(v) in {fcInf, fcNegInf, fcNan}:
      return
  #TODO clipping regions (right now we just clip to default)
  let bw = float64(ctx.bitmap.width)
  let bh = float64(ctx.bitmap.height)
  let x1 = int(min(max(x, 0), bw))
  let y1 = int(min(max(y, 0), bh))
  let x2 = int(min(max(x + w, 0), bw))
  let y2 = int(min(max(y + h, 0), bh))
  ctx.clearRect(x1, y1, x2, y2)

proc fillRect(ctx: CanvasRenderingContext2D; x, y, w, h: float64) {.jsfunc.} =
  for v in [x, y, w, h]:
    if classify(v) in {fcInf, fcNegInf, fcNan}:
      return
  #TODO do we have to clip here?
  if w == 0 or h == 0:
    return
  let bw = float64(ctx.bitmap.width)
  let bh = float64(ctx.bitmap.height)
  let x1 = int(min(max(x, 0), bw))
  let y1 = int(min(max(y, 0), bh))
  let x2 = int(min(max(x + w, 0), bw))
  let y2 = int(min(max(y + h, 0), bh))
  ctx.fillRect(x1, y1, x2, y2, ctx.state.fillStyle)

proc strokeRect(ctx: CanvasRenderingContext2D; x, y, w, h: float64) {.jsfunc.} =
  for v in [x, y, w, h]:
    if classify(v) in {fcInf, fcNegInf, fcNan}:
      return
  #TODO do we have to clip here?
  if w == 0 or h == 0:
    return
  let bw = float64(ctx.bitmap.width)
  let bh = float64(ctx.bitmap.height)
  let x1 = int(min(max(x, 0), bw))
  let y1 = int(min(max(y, 0), bh))
  let x2 = int(min(max(x + w, 0), bw))
  let y2 = int(min(max(y + h, 0), bh))
  ctx.strokeRect(x1, y1, x2, y2, ctx.state.strokeStyle)

proc beginPath(ctx: CanvasRenderingContext2D) {.jsfunc.} =
  ctx.state.path.beginPath()

proc fill(ctx: CanvasRenderingContext2D; fillRule = cfrNonZero) {.jsfunc.} =
  #TODO path
  ctx.state.path.tempClosePath()
  ctx.fillPath(ctx.state.path, ctx.state.fillStyle, fillRule)
  ctx.state.path.tempOpenPath()

proc stroke(ctx: CanvasRenderingContext2D) {.jsfunc.} = #TODO path
  ctx.strokePath(ctx.state.path, ctx.state.strokeStyle)

proc clip(ctx: CanvasRenderingContext2D; fillRule = cfrNonZero) {.jsfunc.} =
  #TODO path
  discard #TODO implement

#TODO maxwidth
proc fillText(ctx: CanvasRenderingContext2D; text: string; x, y: float64)
    {.jsfunc.} =
  for v in [x, y]:
    if classify(v) in {fcInf, fcNegInf, fcNan}:
      return
  let vec = ctx.transform(Vector2D(x: x, y: y))
  ctx.fillText(text, vec.x, vec.y, ctx.state.fillStyle, ctx.state.textAlign)

#TODO maxwidth
proc strokeText(ctx: CanvasRenderingContext2D; text: string; x, y: float64)
    {.jsfunc.} =
  for v in [x, y]:
    if classify(v) in {fcInf, fcNegInf, fcNan}:
      return
  let vec = ctx.transform(Vector2D(x: x, y: y))
  ctx.strokeText(text, vec.x, vec.y, ctx.state.strokeStyle, ctx.state.textAlign)

proc measureText(ctx: CanvasRenderingContext2D; text: string): TextMetrics
    {.jsfunc.} =
  let tw = text.width()
  return TextMetrics(
    width: 8 * float64(tw),
    actualBoundingBoxLeft: 0,
    actualBoundingBoxRight: 8 * float64(tw),
    #TODO and the rest...
  )

proc lineWidth(ctx: CanvasRenderingContext2D): float64 {.jsfget.} =
  return ctx.state.lineWidth

proc lineWidth(ctx: CanvasRenderingContext2D; f: float64) {.jsfset.} =
  if classify(f) in {fcZero, fcNegZero, fcInf, fcNegInf, fcNan}:
    return
  ctx.state.lineWidth = f

proc setLineDash(ctx: CanvasRenderingContext2D; segments: seq[float64])
    {.jsfunc.} =
  discard #TODO implement

proc getLineDash(ctx: CanvasRenderingContext2D): seq[float64] {.jsfunc.} =
  discard #TODO implement
  newSeq[float64]()

proc textAlign(ctx: CanvasRenderingContext2D): string {.jsfget.} =
  return $ctx.state.textAlign

proc textAlign(ctx: CanvasRenderingContext2D; s: string) {.jsfset.} =
  if x := parseEnumNoCase[CanvasTextAlign](s):
    ctx.state.textAlign = x

proc closePath(ctx: CanvasRenderingContext2D) {.jsfunc.} =
  ctx.state.path.closePath()

proc moveTo(ctx: CanvasRenderingContext2D; x, y: float64) {.jsfunc.} =
  ctx.state.path.moveTo(x, y)

proc lineTo(ctx: CanvasRenderingContext2D; x, y: float64) {.jsfunc.} =
  ctx.state.path.lineTo(x, y)

proc quadraticCurveTo(ctx: CanvasRenderingContext2D; cpx, cpy, x,
    y: float64) {.jsfunc.} =
  ctx.state.path.quadraticCurveTo(cpx, cpy, x, y)

proc radiusThrow(ctx: JSContext): JSValue =
  return JS_ThrowDOMException(ctx, "IndexSizeError",
    "expected positive radius, but got negative")

proc arcTo(jsctx: JSContext; ctx: CanvasRenderingContext2D;
    x1, y1, x2, y2, radius: float64): JSValue {.jsfunc.} =
  if radius < 0:
    return jsctx.radiusThrow()
  ctx.state.path.arcTo(x1, y1, x2, y2, radius)
  return JS_UNDEFINED

proc arc(jsctx: JSContext; ctx: CanvasRenderingContext2D;
    x, y, radius, startAngle, endAngle: float64;
    counterclockwise = false): JSValue {.jsfunc.} =
  if radius < 0:
    return jsctx.radiusThrow()
  ctx.state.path.arc(x, y, radius, startAngle, endAngle, counterclockwise)
  return JS_UNDEFINED

proc ellipse(jsctx: JSContext; ctx: CanvasRenderingContext2D;
    x, y, radiusX, radiusY, rotation, startAngle, endAngle: float64;
    counterclockwise = false): JSValue {.jsfunc.} =
  if radiusX < 0 or radiusY < 0:
    return jsctx.radiusThrow()
  ctx.state.path.ellipse(x, y, radiusX, radiusY, rotation, startAngle, endAngle,
    counterclockwise)
  return JS_UNDEFINED

proc rect(ctx: CanvasRenderingContext2D; x, y, w, h: float64) {.jsfunc.} =
  ctx.state.path.rect(x, y, w, h)

proc roundRect(ctx: CanvasRenderingContext2D; x, y, w, h, radii: float64)
    {.jsfunc.} =
  ctx.state.path.roundRect(x, y, w, h, radii)

proc addCanvasModule*(ctx: JSContext) =
  ctx.registerType(CanvasRenderingContext2D)
  ctx.registerType(TextMetrics)

{.pop.} # raises: []
