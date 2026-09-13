# ugh

{.push raises: [].}

import chame/tags
import html/dom
import io/console
import io/dynstream
import js/jsbind
import js/jsref
import js/jsutils
import js/quickjs
import js/tojs
import server/headers
import server/loaderiface
import server/request
import types/bitmap
import types/opt
import types/url
import utils/tabutil
import utils/twtstr

type
  CachedSVG* {.final.} = ref object of StrMapItem
    window*: Window #TODO weak?
    shared*: seq[SVGSVGElement] # elements that serialize to the same string
    bmp: NetworkBitmap
    cacheId: int
    imageId: int

  SVGElementObj {.pure.} = object of ElementObj

  SVGElement = JSRef[SVGElementObj]

  SVGSVGElementObj {.pure, final.} = object of SVGElementObj
    bitmap*: NetworkBitmap
    parserDocument*: Document
    fetchStarted: bool

  SVGSVGElement* = JSRef[SVGSVGElementObj]

# Forward declarations
proc loadSVG*(window: Window; svg: SVGSVGElement)

proc getClassID*(t: typedesc[SVGSVGElement]): JSClassID

# XMLSerializer
jsClassRaw(XMLSerializerDef, "XMLSerializer"):
  proc newXMLSerializer(ctx: JSContext; ctor: JSValueConst): JSValue
      {.jsctor2.} =
    return JS_NewObjectFromCtor(ctx, ctor, classDef.id)

  proc serializeToString(ctx: JSContext; this: JSValueConst; root: Node):
      JSValue {.jsfunc.} =
    #TODO ...yeah
    var res = ""
    res.serializeFragmentInner(root, ttUnknown, writeShadow = true)
    ctx.toJS(res)

# SVGAnimatedString
jsClassRaw(SVGAnimatedStringDef, "SVGAnimatedString"):
  discard #TODO

# SVGElement
proc insertionStepsSVG(element: Element) {.exportc: "cha_$1".} =
  #TODO this doesn't work if JS adds descendants to the SVG tag
  let svg = element as SVGSVGElement
  if svg != nil:
    let document = svg.asNode.document
    if svg.parserDocument != document:
      let window = document.window
      if window != nil:
        window.loadSVG(svg)

jsClassDef(SVGElement):
  jsextends ElementDef

# SVGSVGElement
jsClassPublicDef(SVGSVGElement):
  jsextends SVGElementDef

proc getBitmapSVG(element: Element): NetworkBitmap {.exportc: "cha_$1".} =
  (element as SVGSVGElement).bitmap

# Window extensions
proc loadSVGFinish(opaque: RootRef; response: Response) =
  let env = CachedSVG(opaque)
  let window = move(env.window)
  if response == nil: # no SVG module; give up
    window.imageLoaded()
    return
  let loader = window.loader
  # close immediately; all data we're interested in is in the headers.
  loader.close(response)
  let dims = response.headers.getFirst("Cha-Image-Dimensions")
  let width = parseIntP(dims.until('x')).get(-1)
  let height = parseIntP(dims.after('x')).get(-1)
  if width < 0 or height < 0:
    window.console.error("wrong Cha-Image-Dimensions in", $response.url)
    window.imageLoaded()
    return
  let bitmap = NetworkBitmap(
    width: width,
    height: height,
    cacheId: env.cacheId,
    imageId: env.imageId,
    contentType: "image/svg+xml",
    vector: true
  )
  for svg in env.shared:
    svg.bitmap = bitmap
    svg.asElement.invalidate()
  window.imageLoaded()

proc loadSVG*(window: Window; svg: SVGSVGElement) =
  if not window.settings.images:
    if svg.bitmap != nil:
      svg.asElement.invalidate()
      svg.bitmap = nil
    svg.fetchStarted = false
    return
  if svg.fetchStarted:
    return
  svg.fetchStarted = true
  var s = svg.asElement.outerHTML
  if s.len <= 4096: # try to dedupe if the SVG is small enough.
    let item = CachedSVG(window.svgCache.getOrDefault(s))
    if item != nil:
      svg.bitmap = item.bmp
      if svg.bitmap != nil: # already decoded
        svg.asElement.invalidate()
      else: # tell me when you're done
        item.shared.add(svg)
      return
  let imageId = window.getImageId()
  let loader = window.loader
  let (ps, svgres) = loader.doPipeRequest("svg-" & $imageId)
  if ps == nil:
    return
  let cacheId = loader.addCacheFile(svgres.outputId)
  let res = ps.writeLoop(s)
  ps.sclose()
  if res.isErr:
    return
  let request = newRequest(
    "img-codec+svg+xml:decode",
    httpMethod = hmPost,
    headers = newHeaders(hgRequest, {"Cha-Image-Info-Only": "1"}),
    body = RequestBody(t: rbtOutput, outputId: svgres.outputId),
    internal = true
  )
  let env = CachedSVG(
    window: window,
    shared: @[svg],
    cacheId: cacheId,
    imageId: imageId
  )
  if s.len <= 4096:
    env.s = move(s)
    window.svgCache.put(env)
  inc window.remoteImageNum
  loader.fetch(request, loadSVGFinish, env)
  loader.close(svgres)

# etc.
proc newSVGElementInternal(tagType: TagType): Element {.exportc: "cha_$1".} =
  if tagType == ttSvg:
    (jsNew SVGSVGElementObj()).asElement
  else:
    (jsNew SVGElementObj()).asElement

proc addXMLModule*(ctx: JSContext): JSCode =
  ?ctx.registerClass(SVGAnimatedStringDef)
  ?ctx.registerClass(SVGElementDef)
  ?ctx.registerClass(SVGSVGElementDef)
  ctx.registerClass(XMLSerializerDef)

{.pop.}
