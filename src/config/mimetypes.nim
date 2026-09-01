{.push raises: [].}

import std/algorithm

import io/chafile
import types/opt
import utils/tabutil
import utils/twtstr

type
  MimeTypeTuple = tuple[ext, name: string]

const DefaultGuess* = [
  (ext: "ans", name: "text/x-ansi"),
  (ext: "asc", name: "text/x-ansi"),
  (ext: "bmp", name: "image/bmp"),
  (ext: "css", name: "text/css"),
  (ext: "gif", name: "image/gif"),
  (ext: "gmi", name: "text/gemini"),
  (ext: "htm", name: "text/html"),
  (ext: "html", name: "text/html"),
  (ext: "jfif", name: "image/jpeg"),
  (ext: "jpe", name: "image/jpeg"),
  (ext: "jpeg", name: "image/jpeg"),
  (ext: "jpg", name: "image/jpeg"),
  (ext: "md", name: "text/markdown"),
  (ext: "png", name: "image/png"),
  (ext: "svg", name: "image/svg+xml"),
  (ext: "txt", name: "text/plain"),
  (ext: "uri", name: "text/uri-list"),
  (ext: "webp", name: "image/webp"),
  (ext: "xht", name: "application/xhtml+xml"),
  (ext: "xhtm", name: "application/xhtml+xml"),
  (ext: "xhtml", name: "application/xhtml+xml"),
]

# Part after image/, *not* the file extension.
# (sorted by order of perceived frequency)
const DefaultImages = [
  "png", "jpeg", "webp", "svg+xml", "gif", "bmp"
]

# extension -> type
type
  MimeType = ref object of StrMapItem
    name: string # content type

  MimeTypesImageItem* = tuple[ext, subtype: string]

  MimeTypesImages* = seq[MimeTypesImageItem]

  MimeTypes* = object
    tab: StrMap # ext -> type
    image*: MimeTypesImages # ext -> image/(\w*)

proc cmpMimeTypesImageItem*(x: MimeTypesImageItem; ext: string): int =
  cmp(x.ext, ext)

proc parseMimeTypes*(mimeTypes: var MimeTypes; file: AChaFile): Opt[void] =
  var line: string
  while ?file.readLine(line):
    if line.len == 0 or line[0] == '#':
      continue
    let t = line.untilLower(AsciiWhitespace)
    var i = t.len
    while i < line.len:
      i = line.skipBlanks(i)
      let ext = line.untilLower(AsciiWhitespace, i)
      i += ext.len
      if ext.len > 0:
        let item = MimeType(s: ext, name: t)
        if not mimeTypes.tab.hasKeyOrPut(item) and
            item.name.startsWith("image/"):
          let t = item.name.substr("image/".len)
          # As a fingerprinting countermeasure: prevent additional
          # extensions for predefined inline image type detection.
          if t notin DefaultImages:
            mimeTypes.image.add((item.s, t))
  mimeTypes.image.sort(proc(a, b: MimeTypesImageItem): int {.nimcall.} =
    cmp(a.ext, b.ext)
  )
  ok()

proc cmpMimeType(item: MimeTypeTuple; s: string): int =
  item.ext.cmp(s)

# for DefaultGuess
proc guessContentType*(mimeTypes: openArray[MimeTypeTuple]; path: string;
    fallback = "application/octet-stream"): string =
  let ext = path.getFileExt()
  if ext.len > 0:
    let i = mimeTypes.binarySearch(ext, cmpMimeType)
    if i >= 0:
      return mimeTypes[i].name
  return fallback

proc guessContentType*(mimeTypes: MimeTypes; path: string;
    fallback = "application/octet-stream"): string =
  let ext = path.getFileExt()
  if ext.len > 0:
    let item = mimeTypes.tab.getOrDefault(ext)
    if item != nil:
      return MimeType(item).name
  return fallback

const JavaScriptTypes = [
  "application/ecmascript",
  "application/javascript",
  "application/x-ecmascript",
  "application/x-javascript",
  "text/ecmascript",
  "text/javascript",
  "text/javascript1.0",
  "text/javascript1.1",
  "text/javascript1.2",
  "text/javascript1.3",
  "text/javascript1.4",
  "text/javascript1.5",
  "text/jscript",
  "text/livescript",
  "text/x-ecmascript",
  "text/x-javascript"
]

proc isJavaScriptType*(s: string): bool =
  return JavaScriptTypes.binarySearch(s, cmpIgnoreCase) != -1

proc isTextType*(s: string): bool =
  return s.startsWithIgnoreCase("text/") or s.isJavaScriptType()

{.pop.} # raises: []
