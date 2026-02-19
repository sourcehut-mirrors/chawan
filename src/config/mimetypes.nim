{.push raises: [].}

import std/algorithm
import std/tables

import io/chafile
import types/opt
import utils/twtstr

const DefaultGuess* = {
  "ans": "text/x-ansi",
  "asc": "text/x-ansi",
  "css": "text/css",
  "gmi": "text/gemini",
  "htm": "text/html",
  "html": "text/html",
  "md": "text/markdown",
  "txt": "text/plain",
  "uri": "text/uri-list",
  "xht": "application/xhtml+xml",
  "xhtm": "application/xhtml+xml",
  "xhtml": "application/xhtml+xml",
  "bmp": "image/bmp",
  "gif": "image/gif",
  "jfif": "image/jpg",
  "jpe": "image/jpg",
  "jpeg": "image/jpg",
  "jpg": "image/jpg",
  "png": "image/png",
  "svg": "image/svg+xml",
  "webp": "image/webp",
}.toTable()

# Part after image/, *not* the file extension.
const DefaultImages = [
  "png", "jpg", "webp", "svg+xml", "gif", "bmp"
]

# extension -> type
type
  MimeTypesTable* = Table[string, string] # ext -> type

  MimeTypes* = object
    t*: MimeTypesTable
    image*: Table[string, string] # ext -> image/(\w*)

proc parseMimeTypes*(mimeTypes: var MimeTypes; file: ChaFile): Opt[void] =
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
      if ext.len > 0 and not mimeTypes.t.hasKeyOrPut(ext, t) and
          t.startsWith("image/"):
        let t = t.after('/')
        # As a fingerprinting countermeasure: prevent additional
        # extensions for predefined inline image type detection.
        if t notin DefaultImages:
          mimeTypes.image[ext] = t
  ok()

proc guessContentType*(mimeTypes: MimeTypesTable; path: string;
    fallback = "application/octet-stream"): string =
  let ext = path.getFileExt()
  if ext.len > 0:
    return mimeTypes.getOrDefault(ext, fallback)
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
