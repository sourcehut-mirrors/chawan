## A demonstration of using the Chakasu encoding library in combination with
## the Chame HTML parser.
##
## For the most part, this is the same as minidom. However, it also has support
## for decoding documents with arbitrary character sets using DecoderStream +
## EncoderStream.
##
## Note: this is not implemented for the fragment parsing algorithm, because it
## is only defined for the UTF-8 character set.
##
## See also
## ========
## * `chame/minidom <minidom.html>`

import std/streams

import minidom
import htmlparser
import tags

import chakasu/charset
import chakasu/decoderstream
import chakasu/encoderstream

export minidom
export tags

type CharsetConfidence = enum
  CONFIDENCE_TENTATIVE, CONFIDENCE_CERTAIN, CONFIDENCE_IRRELEVANT

type CharsetMiniDOMBuilder = ref object of MiniDOMBuilder
  charset: Charset
  confidence: CharsetConfidence

method setEncodingImpl(builder: CharsetMiniDOMBuilder, encoding: string):
    SetEncodingResult =
  let charset = getCharset(encoding)
  if charset == CHARSET_UNKNOWN:
    return SET_ENCODING_CONTINUE
  if builder.charset in {CHARSET_UTF_16_LE, CHARSET_UTF_16_BE}:
    builder.confidence = CONFIDENCE_CERTAIN
    return SET_ENCODING_CONTINUE
  builder.confidence = CONFIDENCE_CERTAIN
  if charset == builder.charset:
    return SET_ENCODING_CONTINUE
  if charset == CHARSET_X_USER_DEFINED:
    builder.charset = CHARSET_WINDOWS_1252
  else:
    builder.charset = charset
  return SET_ENCODING_STOP

proc newCharsetMiniDOMBuilder(factory: MAtomFactory): CharsetMiniDOMBuilder =
  let document = Document(nodeType: DOCUMENT_NODE)
  let builder = CharsetMiniDOMBuilder(document: document, factory: factory)
  return builder

#TODO this should probably be in decoderstream
proc bomSniff(inputStream: var Stream): Charset =
  const u8bom = "\xEF\xBB\BF"
  const bebom = char(0xFE) & char(0xFF)
  const lebom = char(0xFF) & char(0xFE)
  var bom = inputStream.readStr(2)
  if bom == bebom:
    return CHARSET_UTF_16_BE
  elif bom == lebom:
    return CHARSET_UTF_16_LE
  else:
    bom &= inputStream.readChar()
    if bom == u8bom:
      return CHARSET_UTF_8
    else:
      inputStream.setPosition(0)

proc parseHTML*(inputStream: Stream, opts: HTML5ParserOpts[Node, MAtom],
    charsets: seq[Charset], seekable = true,
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
  var charsetStack: seq[Charset]
  for i in countdown(charsets.high, 0):
    charsetStack.add(charsets[i])
  var seekable = seekable
  var inputStream = inputStream
  if seekable:
    let scs = inputStream.bomSniff()
    if scs != CHARSET_UNKNOWN:
      charsetStack.add(scs)
      builder.confidence = CONFIDENCE_CERTAIN
      seekable = false
  if charsetStack.len == 0:
    charsetStack.add(DefaultCharset) # UTF-8
  while true:
    builder.charset = charsetStack.pop()
    if seekable:
      builder.confidence = CONFIDENCE_TENTATIVE # used in the next iteration
    else:
      builder.confidence = CONFIDENCE_CERTAIN
    let em = if charsetStack.len == 0 or not seekable:
      DECODER_ERROR_MODE_REPLACEMENT
    else:
      DECODER_ERROR_MODE_FATAL
    let decoder = newDecoderStream(inputStream, builder.charset, errormode = em)
    let encoder = newEncoderStream(decoder, CHARSET_UTF_8,
      errormode = ENCODER_ERROR_MODE_FATAL)
    parseHTML(encoder, builder, opts)
    if builder.confidence == CONFIDENCE_CERTAIN and seekable:
      # A meta tag describing the charset has been found; force use of this
      # charset.
      inputStream.setPosition(0)
      builder.document = Document(nodeType: DOCUMENT_NODE)
      charsetStack.add(builder.charset)
      seekable = false
      continue
    if decoder.failed and seekable:
      # Retry with another charset.
      inputStream.setPosition(0)
      builder.document = Document(nodeType: DOCUMENT_NODE)
      continue
    break
  return builder.document
