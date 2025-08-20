## A demonstration of using the Chagashi encoding library in combination
## with the Chame HTML parser.
##
## For the most part, this is the same as minidom, except it supports
## decoding documents with arbitrary character sets.
##
## Note: this is not implemented for the fragment parsing algorithm,
## because that is only defined for UTF-8 in the standard.
##
## For a version without the encoding library dependency, see
## [minidom](minidom.html).

import std/streams

import minidom
import htmlparser
import tags

import chagashi/charset
import chagashi/decoder

export minidom
export tags

type CharsetConfidence = enum
  ccTentative, ccCertain

type CharsetMiniDOMBuilder = ref object of MiniDOMBuilder
  charset: Charset
  confidence: CharsetConfidence

method setEncodingImpl(builder: CharsetMiniDOMBuilder; encoding: string):
    SetEncodingResult =
  let charset = getCharset(encoding)
  if charset == CHARSET_UNKNOWN:
    return SET_ENCODING_CONTINUE
  if builder.charset in {CHARSET_UTF_16_LE, CHARSET_UTF_16_BE}:
    builder.confidence = ccCertain
    return SET_ENCODING_CONTINUE
  builder.confidence = ccCertain
  if charset == builder.charset:
    return SET_ENCODING_CONTINUE
  if charset == CHARSET_X_USER_DEFINED:
    builder.charset = CHARSET_WINDOWS_1252
  else:
    builder.charset = charset
  return SET_ENCODING_STOP

proc newCharsetMiniDOMBuilder(factory: MAtomFactory): CharsetMiniDOMBuilder =
  let document = Document(factory: factory)
  let builder = CharsetMiniDOMBuilder(document: document, factory: factory)
  return builder

#TODO this should be handled by decoderstream
proc bomSniff(inputStream: Stream): Charset =
  let bom = inputStream.readStr(2)
  if bom == "\xFE\xFF":
    return CHARSET_UTF_16_BE
  if bom == "\xFF\xFE":
    return CHARSET_UTF_16_LE
  if bom == "\xEF\xBB":
    if inputStream.readChar() == '\xBF':
      return CHARSET_UTF_8
  inputStream.setPosition(0)
  return CHARSET_UNKNOWN

proc parseHTML*(inputStream: Stream; opts: HTML5ParserOpts[Node, MAtom];
    charsets: seq[Charset]; seekable = true;
    factory = newMAtomFactory()): Document =
  ## Read, parse and return an HTML document from `inputStream`.
  ##
  ## `charsets` is a list of input character sets to try. If empty, it will be
  ## initialized to `@[CHARSET_UTF_8]`.
  ##
  ## The list of fallback charsets is used as follows:
  ##
  ## * A charset stack is initialized to `charsets`, reversed. This
  ##   means that the first charset specified in `charsets` is on top of
  ##   the stack. (e.g. say `charsets = @[CHARSET_UTF_16_LE, CHARSET_UTF_8]`,
  ##   then utf-16-le is tried before utf-8.)
  ## * BOM sniffing is attempted. If successful, confidence is set to
  ##   certain and the resulting charset is used (i.e. other character
  ##   sets will not be tried for decoding this document.)
  ## * If the charset stack is empty, UTF-8 is pushed on top.
  ## * Attempt to parse the document with the first charset on top of
  ##   the stack.
  ## * If BOM sniffing was unsuccessful, and a <meta charset=...> tag
  ##   is encountered, parsing is restarted with the specified charset.
  ##   No further attempts are made to detect the encoding, and decoder
  ##   errors are signaled by U+FFFD replacement characters.
  ## * Otherwise, each charset on the charset stack is tried until either no
  ##   decoding errors are encountered, or only one charset is left. For
  ##   the last charset, decoder errors are signaled by U+FFFD replacement
  ##   characters.
  ##
  ## `seekable` must be true only if `inputStream` is seekable; if set to true,
  ## `inputStream.setPosition(0)` must work.
  ##
  ## Note that `seekable = false` disables automatic character set detection;
  ## even `<meta charset=...` tags will be disregarded.
  ## (TODO: this should be improved in the future; theoretically we could still
  ## switch between ASCII-compatible charsets before non-ASCII is encountered.)
  let builder = newCharsetMiniDOMBuilder(factory)
  var charsetStack: seq[Charset] = @[]
  for i in countdown(charsets.high, 0):
    charsetStack.add(charsets[i])
  var seekable = seekable
  var inputStream = inputStream
  if seekable:
    let scs = inputStream.bomSniff()
    if scs != CHARSET_UNKNOWN:
      charsetStack.add(scs)
      builder.confidence = ccCertain
      seekable = false
  if charsetStack.len == 0:
    charsetStack.add(DefaultCharset) # UTF-8
  while true:
    builder.charset = charsetStack.pop()
    if seekable and charsetStack.len > 0:
      builder.confidence = ccTentative # used in the next iteration
    else:
      builder.confidence = ccCertain
    var parser = initHTML5Parser(builder, opts)
    var iq {.noinit.}: array[4096, char]
    let decoder = newTextDecoder(builder.charset)
    let errorMode = [
      ccTentative: demFatal,
      ccCertain: demReplacement
    ][builder.confidence]
    var ctx = initTextDecoderContext(decoder, errorMode)
    while true:
      let n = inputStream.readData(addr iq[0], iq.len)
      var finish = n < iq.len
      for chunk in ctx.decode(iq.toOpenArrayByte(0, n - 1), finish = finish):
        # res can be PRES_SCRIPT, PRES_STOP or PRES_CONTINUE.
        var res = parser.parseChunk(chunk.toOpenArray())
        # For PRES_SCRIPT, we must re-feed the same chunk as in minidom, but
        # starting from the current insertion point.
        var ip = 0
        while res == PRES_SCRIPT and
            (ip += parser.getInsertionPoint(); ip != chunk.len):
          res = parser.parseChunk(chunk.toOpenArray(ip, chunk.high))
        # PRES_STOP is returned when we return SET_ENCODING_STOP from
        # setEncodingImpl. We immediately stop parsing in this case.
        if res == PRES_STOP:
          finish = true
          break
      if finish:
        break
    parser.finish()
    if builder.confidence == ccCertain and seekable:
      # A meta tag describing the charset has been found; force use of this
      # charset.
      inputStream.setPosition(0)
      builder.document = Document(factory: factory)
      charsetStack.add(builder.charset)
      seekable = false
      continue
    if ctx.failed and seekable:
      # Retry with another charset.
      inputStream.setPosition(0)
      builder.document = Document(factory: factory)
      continue
    break
  return builder.document
