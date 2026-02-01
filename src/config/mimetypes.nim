{.push raises: [].}

from std/strutils import cmpIgnoreCase

import std/algorithm
import std/sets
import std/tables

import io/chafile
import types/opt
import utils/twtstr

# extension -> type
type MimeTypes* = object
  t: Table[string, string] # ext -> type
  image*: Table[string, string] # ext -> image/(\w*)

template getOrDefault*(mimeTypes: MimeTypes; k, fallback: string): string =
  mimeTypes.t.getOrDefault(k, fallback)

proc parseMimeTypesLine(mimeTypes: var MimeTypes; buf: openArray[char];
    defaultImages: HashSet[string]) =
  if buf.len == 0 or buf[0] == '#':
    return
  let t = buf.untilLower(AsciiWhitespace)
  var i = t.len
  while i < buf.len:
    i = buf.skipBlanks(i)
    let ext = buf.untilLower(AsciiWhitespace, i)
    i += ext.len
    if ext.len > 0 and not mimeTypes.t.hasKeyOrPut(ext, t) and
        t.startsWith("image/"):
      let t = t.after('/')
      # As a fingerprinting countermeasure: prevent additional
      # extensions for predefined inline image type detection.
      if t notin defaultImages:
        mimeTypes.image[ext] = t

proc parseMimeTypes*(mimeTypes: var MimeTypes; file: ChaFile;
    defaultImages: HashSet[string]): Opt[void] =
  var line: string
  while ?file.readLine(line):
    mimeTypes.parseMimeTypesLine(line, defaultImages)
  ok()

const DefaultGuess* = block:
  var mimeTypes = MimeTypes()
  let s = staticRead"res/mime.types"
  let dummy = initHashSet[string]()
  for (si, ei) in s.lineIndices:
    mimeTypes.parseMimeTypesLine(s.toOpenArray(si, ei), dummy)
  mimeTypes

const DefaultImages* = block:
  var s = initHashSet[string]()
  for _, v in DefaultGuess.image:
    s.incl(v)
  s

proc guessContentType*(mimeTypes: MimeTypes; path: string;
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
