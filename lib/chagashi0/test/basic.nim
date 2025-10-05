import std/strutils
import std/unittest

import chagashi/charset
import chagashi/decoder
import chagashi/decodercore
import chagashi/encoder

const iroha = "いろはにほへとちりぬるをわかよたれそつねならむうゐのおくやまけふこえてあさきゆめみしゑひもせす"
test "roundtrip iroha":
  const css = [
    CHARSET_SHIFT_JIS, CHARSET_ISO_2022_JP, CHARSET_EUC_JP, CHARSET_EUC_KR,
    CHARSET_GB18030, CHARSET_GBK, CHARSET_BIG5
  ]
  let iroha100 = iroha.repeat(100)
  for cs in css:
    let te = newTextEncoder(cs)
    let sencoded = te.encodeAll(iroha)
    let td = newTextDecoder(cs)
    let sdecoded = td.decodeAll(sencoded)
    check sdecoded == iroha
    var ctx = initTextDecoderContext(cs)
    var dec2 = ""
    for i in 0 ..< 100:
      for slice in ctx.decode(sencoded.toOpenArrayByte(0, sencoded.high),
          finish = false):
        dec2 &= slice
      for slice in ctx.decode([], finish = true):
        dec2 &= slice
    check dec2 == iroha100

test "validate UTF-8 in parts":
  # Validate "Hellö, world!".
  let ss0 = "Hell\xC3"
  var td = newTextDecoder(CHARSET_UTF_8)
  var n = 0
  var oq = newSeq[uint8](16)
  check td.decode(ss0.toOpenArrayByte(0, ss0.high), oq, n) == tdrReadInput
  # read Hell (0xC3 is not consumed yet)
  check td.decode(ss0.toOpenArrayByte(0, ss0.high), oq, n) == tdrDone
  # n is still 0, but 0xC3 is now buffered
  check n == 0
  # read 0xB6 + , world! => Hellö world!
  let ss1 = "\xB6, world!\xC3"
  check td.decode(ss1.toOpenArrayByte(0, ss1.high), oq, n) == tdrReadInput
  # 0xC3 got moved from the internal buffer to oq
  check n == 1
  check oq[0] == 0xC3
  check td.decode(ss1.toOpenArrayByte(0, ss1.high), oq, n) == tdrDone
  check td.finish() == tdfrError

test "validate valid UTF-8":
  const utf8_valid = [
    "aiueo",
    "äöüß",
    "あいうえお",
    "\u1F972"
  ]
  for s in utf8_valid:
    check s.toValidUTF8() == s
    check s.toValidUTF8() & 'x' == s & 'x'

test "validate invalid UTF-8":
  const utf8_error = {
    "\xF8\x80\x80\x80\x80\x80": "\uFFFD\uFFFD\uFFFD\uFFFD\uFFFD\uFFFD",
    "\uD800": "\uFFFD\uFFFD\uFFFD", # lowest surrogate
    "\uD8FF": "\uFFFD\uFFFD\uFFFD", # highest surrogate
    "\uD83E\uDD72": "\uFFFD\uFFFD\uFFFD\uFFFD\uFFFD\uFFFD", # paired surrogates
    "\uD83C": "\uFFFD\uFFFD\uFFFD", # some unpaired surrogate
    "r\xC8sum\xC8s": "r\uFFFDsum\uFFFDs", # latin-1 mis-declared as UTF-8
  }
  for (s, t) in utf8_error:
    check s.toValidUTF8() == t
    check (s & 'x').toValidUTF8() == t & 'x'

test "UTF-16-BE to UTF-8":
  const list = {
    "\0H\0e\0l\0l\0o\0,\0 \0w\0o\0r\0l\0d\0!": "Hello, world!",
    "\xD8\x00": "\uFFFD", # lowest surrogate (unpaired)
    "\xDB\xFF": "\uFFFD", # highest low surrogate (unpaired)
    "\xDC\x00": "\uFFFD", # lowest high surrogate (unpaired)
    "\xD8\xFF": "\uFFFD", # highest surrogate (unpaired)
    "\xD8\x3E\xDD\x72": "\u{1F972}", # paired surrogates
  }
  for (s, t) in list:
    let td = TextDecoderUTF16_BE()
    check td.decodeAll(s) == t

test "UTF-16-LE to UTF-8":
  const list = {
    "H\0e\0l\0l\0o\0,\0 \0w\0o\0r\0l\0d\0!\0": "Hello, world!",
    "\x00\xD8": "\uFFFD", # lowest surrogate (unpaired)
    "\xFF\xDB": "\uFFFD", # highest low surrogate (unpaired)
    "\x00\xDC": "\uFFFD", # lowest high surrogate (unpaired)
    "\xFF\xD8": "\uFFFD", # highest surrogate (unpaired)
    "\x3E\xD8\x72\xDD": "\u{1F972}", # paired surrogates
  }
  for (s, t) in list:
    let td = TextDecoderUTF16_LE()
    check td.decodeAll(s) == t
  var s = ""
  var s8 = ""
  for i in 0 ..< 10:
    s &= "t\0e\0s\0t\0"
    s8 &= "test"
  let td = TextDecoderUTF16_LE()
  var ctx = initTextDecoderContext(td, bufLen = 32)
  var res = ""
  for s in ctx.decode(s.toOpenArrayByte(0, s.high), finish = true):
    res &= s
  check res == s8

test "encode from surrogate to GB18030":
  let te = TextEncoderGB18030()
  let sencoded = te.encodeAll("\uD800")
  let td = TextDecoderGB18030()
  let sdecoded = td.decodeAll(sencoded)
  check sdecoded == "\uFFFD\uFFFD\uFFFD"

const tisztaszivvel = """
Nincsen apám, se anyám,
se istenem, se hazám,
se bölcsőm, se szemfedőm,
se csókom, se szeretőm.

Harmadnapja nem eszek,
se sokat, se keveset.
Húsz esztendőm hatalom;
húsz esztendőm eladom.

Hogyha nem kell senkinek,
hát az ördög veszi meg.
Tiszta szívvel betörök,
ha kell, embert is ölök.

Elfognak és felkötnek,
áldott földdel elfödnek,
s halált hozó fű terem
gyönyörűszép szívemen.
"""

test "roundtrip windows-1250":
  let te = TextEncoderWindows1250()
  let sencoded = te.encodeAll(tisztaszivvel)
  let td = TextDecoderWindows1250()
  let sdecoded = td.decodeAll(sencoded)
  check sdecoded == tisztaszivvel

const erlkoenig = """
Wer reitet so spät durch Nacht und Wind?
Es ist der Vater mit seinem Kind;
Er hat den Knaben wohl in dem Arm,
Er faßt ihn sicher, er hält ihn warm.

Mein Sohn, was birgst du so bang dein Gesicht?
Siehst, Vater, du den Erlkönig nicht?
Den Erlenkönig mit Kron' und Schweif?
Mein Sohn, es ist ein Nebelstreif.

"Du liebes Kind, komm, geh mit mir!
Gar schöne Spiele spiel' ich mit dir;
Manch' bunte Blumen sind an dem Strand,
Meine Mutter hat manch gülden Gewand."

Mein Vater, mein Vater, und hörest du nicht,
Was Erlenkönig mir leise verspricht?
Sei ruhig, bleibe ruhig, mein Kind;
In dürren Blättern säuselt der Wind.

"Willst, feiner Knabe, du mit mir gehn?
Meine Töchter sollen dich warten schön;
Meine Töchter führen den nächtlichen Reihn,
Und wiegen und tanzen und singen dich ein."

Mein Vater, mein Vater, und siehst du nicht dort
Erlkönigs Töchter am düstern Ort?
Mein Sohn, mein Sohn, ich seh' es genau:
Es scheinen die alten Weiden so grau.

"Ich liebe dich, mich reizt deine schöne Gestalt;
Und bist du nicht willig, so brauch' ich Gewalt."
Mein Vater, mein Vater, jetzt faßt er mich an!
Erlkönig hat mir ein Leids getan!

Dem Vater grauset's; er reitet geschwind,
Er hält in den Armen das ächzende Kind,
Erreicht den Hof mit Mühe und Not;
In seinen Armen, das Kind war tot.
"""

test "roundtrip windows-1252":
  let te = TextEncoderWindows1252()
  let sencoded = te.encodeAll(erlkoenig)
  let td = TextDecoderWindows1252()
  let sdecoded = td.decodeAll(sencoded)
  check sdecoded == erlkoenig

test "roundtrip ISO-8859-2":
  let te = TextEncoderISO8859_2()
  let sencoded = te.encodeAll(tisztaszivvel)
  let td = TextDecoderISO8859_2()
  let sdecoded = td.decodeAll(sencoded)
  check sdecoded == tisztaszivvel

test "getLocaleCharset":
  check getLocaleCharset("ja_JP.EUC_JP") == CHARSET_EUC_JP
  check getLocaleCharset("ja_JP.UTF-8") == CHARSET_UTF_8
  check getLocaleCharset("") == CHARSET_UTF_8

test "Shift_JIS U+2212":
  check "\u2212".encodeAll(CHARSET_SHIFT_JIS) ==
    "\uFF0D".encodeAll(CHARSET_SHIFT_JIS)

test "GB18030 ranges":
  let first = "\u0080".encodeAll(CHARSET_GB18030)
  check first == "\x81\x30\x81\x30"
  check first.decodeAll(CHARSET_GB18030) == "\u0080"
  let last = "\u{10000}".encodeAll(CHARSET_GB18030)
  check last == "\x90\x30\x81\x30"
  check last.decodeAll(CHARSET_GB18030) == "\u{10000}"
