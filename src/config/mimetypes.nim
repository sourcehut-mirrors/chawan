import std/algorithm
import std/sets
import std/strutils
import std/tables

import utils/twtstr

# extension -> type
type MimeTypes* = object
  t: Table[string, string] # ext -> type
  image*: Table[string, string] # ext -> image/(\w*)

template getOrDefault*(mimeTypes: MimeTypes; k, fallback: string): string =
  mimeTypes.t.getOrDefault(k, fallback)

# No error handling for now.
proc parseMimeTypes*(mimeTypes: var MimeTypes; buf: openArray[char];
    defaultImages: HashSet[string]) =
  var i = 0
  while i < buf.len:
    if buf[i] == '#': # comment
      while i < buf.len and buf[i] != '\n':
        inc i
    else:
      let t = buf.untilLower(AsciiWhitespace, i)
      i += t.len
      while i < buf.len and buf[i] != '\n':
        i = buf.skipBlanksTillLF(i)
        let ext = buf.untilLower(AsciiWhitespace, i)
        i += ext.len
        if ext.len > 0 and not mimeTypes.t.hasKeyOrPut(ext, t) and
            t.startsWith("image/"):
          let t = t.after('/')
          # As a fingerprinting countermeasure: prevent additional
          # extensions for predefined inline image type detection.
          if t notin defaultImages:
            mimeTypes.image[ext] = t
    inc i

const DefaultGuess* = block:
  var mimeTypes = MimeTypes()
  mimeTypes.parseMimeTypes(staticRead"res/mime.types", initHashSet[string]())
  mimeTypes

const DefaultImages* = block:
  var s = initHashSet[string]()
  for _, v in DefaultGuess.image:
    s.incl(v)
  s

func guessContentType*(mimeTypes: MimeTypes; path: string;
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

func isJavaScriptType*(s: string): bool =
  return JavaScriptTypes.binarySearch(s, cmpIgnoreCase) != -1

func isTextType*(s: string): bool =
  return s.startsWithIgnoreCase("text/") or s.isJavaScriptType()
