{.push raises: [].}

import std/algorithm

import io/chafile
import utils/cowstr
import utils/opt
import utils/tabutil
import utils/twtstr

type
  MimeTypeTuple = tuple[ext: Str; name: cstring]

const DefaultGuess = [
  (ext: str("ans"), name: cstring"text/x-ansi"),
  (ext: str("asc"), name: cstring"text/x-ansi"),
  (ext: str("bmp"), name: cstring"image/bmp"),
  (ext: str("css"), name: cstring"text/css"),
  (ext: str("gif"), name: cstring"image/gif"),
  (ext: str("gmi"), name: cstring"text/gemini"),
  (ext: str("htm"), name: cstring"text/html"),
  (ext: str("html"), name: cstring"text/html"),
  (ext: str("jfif"), name: cstring"image/jpeg"),
  (ext: str("jpe"), name: cstring"image/jpeg"),
  (ext: str("jpeg"), name: cstring"image/jpeg"),
  (ext: str("jpg"), name: cstring"image/jpeg"),
  (ext: str("md"), name: cstring"text/markdown"),
  (ext: str("png"), name: cstring"image/png"),
  (ext: str("svg"), name: cstring"image/svg+xml"),
  (ext: str("txt"), name: cstring"text/plain"),
  (ext: str("uri"), name: cstring"text/uri-list"),
  (ext: str("webp"), name: cstring"image/webp"),
  (ext: str("xht"), name: cstring"application/xhtml+xml"),
  (ext: str("xhtm"), name: cstring"application/xhtml+xml"),
  (ext: str("xhtml"), name: cstring"application/xhtml+xml"),
]

# Part after image/, *not* the file extension.
# (sorted by order of perceived frequency)
const DefaultImages = [
  str("png"), str("jpeg"), str("webp"), str("svg+xml"), str("gif"), str("bmp")
]

# extension -> type
type
  MimeType = ref object of StrMapItem
    name: Str # content type

  MimeTypesImageItem* = tuple[ext, subtype: Str]

  MimeTypesImages* = seq[MimeTypesImageItem]

  MimeTypes* = object
    tab: StrMap # ext -> type
    image*: MimeTypesImages # ext -> image/(\w*)

proc cmpMimeTypesImageItem*(x: MimeTypesImageItem; ext: Str): int =
  cmp(x.ext, ext)

proc parseMimeTypes*(mimeTypes: var MimeTypes; file: AChaFile): Opt[void] =
  var line: Growbuf
  while ?file.readLine(line):
    if line.len == 0 or line[0] == '#':
      continue
    let line = move(line).toStr()
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

proc cmpMimeType(item: MimeTypeTuple; s: Str): int =
  item.ext.cmp(s)

# for DefaultGuess
proc guessDefaultContentType*(path: Str;
    fallback = str("application/octet-stream")): Str =
  let ext = path.getFileExt()
  if ext.len > 0:
    let i = DefaultGuess.binarySearch(ext, cmpMimeType)
    if i >= 0:
      return str(DefaultGuess[i].name)
  return fallback

proc guessContentType*(mimeTypes: MimeTypes; path: Str;
    fallback = str("application/octet-stream")): Str =
  let ext = path.getFileExt()
  if ext.len > 0:
    let item = mimeTypes.tab.getOrDefault(ext.toOpenArray())
    if item != nil:
      return MimeType(item).name
  return fallback

const JavaScriptTypes = [
  str("application/ecmascript"),
  str("application/javascript"),
  str("application/x-ecmascript"),
  str("application/x-javascript"),
  str("text/ecmascript"),
  str("text/javascript"),
  str("text/javascript1.0"),
  str("text/javascript1.1"),
  str("text/javascript1.2"),
  str("text/javascript1.3"),
  str("text/javascript1.4"),
  str("text/javascript1.5"),
  str("text/jscript"),
  str("text/livescript"),
  str("text/x-ecmascript"),
  str("text/x-javascript")
]

proc isJavaScriptType*(s: Str): bool =
  return JavaScriptTypes.binarySearch(s, cmpIgnoreCase) != -1

proc isTextType*(s: Str): bool =
  return s.startsWithIgnoreCase("text/") or s.isJavaScriptType()

{.pop.} # raises: []
