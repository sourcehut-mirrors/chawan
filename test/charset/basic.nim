import std/strutils

import encoding/charset
import encoding/decoder
import encoding/decodercore
import encoding/encoder

const iroha = "いろはにほへとちりぬるをわかよたれそつねならむうゐのおくやまけふこえてあさきゆめみしゑひもせす"
proc testCJK() =
  const css = [
    csShiftJIS, csIso2022JP, csEucJP, csEucKR, csGb18030, csGbk, csBig5, csUtf8
  ]
  let iroha100 = iroha.repeat(100)
  for cs in css:
    let sencoded = if cs != csUtf8:
      iroha.encodeAll(cs)
    else:
      iroha
    let sdecoded = sencoded.decodeAll(cs)
    assert sdecoded == iroha
    var ctx = initTextDecoderContext(cs)
    var dec2 = ""
    for i in 0 ..< 100:
      for slice in ctx.decode(sencoded.toOpenArrayByte(0, sencoded.high),
          finish = false):
        dec2 &= slice
      for slice in ctx.decode([], finish = true):
        dec2 &= slice
    assert dec2 == iroha100

proc testUTF8Parts() =
  # Validate "Hellö, world!".
  let ss0 = "Hell\xC3"
  var td = initTextDecoder(csUtf8)
  var n = 0
  var oq = newSeq[uint8](16)
  assert td.decode(ss0.toOpenArrayByte(0, ss0.high), oq, n) == tdrReadInput
  # read Hell (0xC3 is not consumed yet)
  assert td.decode(ss0.toOpenArrayByte(0, ss0.high), oq, n) == tdrDone
  # n is still 0, but 0xC3 is now buffered
  assert n == 0
  # read 0xB6 + , world! => Hellö world!
  let ss1 = "\xB6, world!\xC3"
  assert td.decode(ss1.toOpenArrayByte(0, ss1.high), oq, n) == tdrReadInput
  # 0xC3 got moved from the internal buffer to oq
  assert n == 1
  assert oq[0] == 0xC3
  assert td.decode(ss1.toOpenArrayByte(0, ss1.high), oq, n,
    finish = true) == tdrError

proc testUTF8Valid() =
  const utf8_valid = [
    "aiueo",
    "äöüß",
    "あいうえお",
    "あöあüあöあüあöあü",
    "asdf asdf asdfasd fasdfas dfあöあüa lksdjf alskdfj asalkdf kldfj asdあ aklsdjf asd",
    "\u1F972"
  ]
  for s in utf8_valid:
    assert s.toValidUTF8() == s
    assert s.toValidUTF8() & 'x' == s & 'x'
    var ctx = initTextDecoderContext(csUtf8, bufLen = 3)
    block:
      var res = ""
      for s in ctx.decode(s.toOpenArrayByte(0, s.high), finish = true):
        res &= s
      assert res == s
    for j in 2 .. 10:
      var res = ""
      var i = 0
      while i < s.len:
        for s in ctx.decode(s.toOpenArrayByte(i, min(i + j, s.len) - 1), finish = i + j >= s.len):
          res &= s
        i += j
      assert res == s

proc testUTF8Invalid() =
  const utf8_error = {
    "\xF8\x80\x80\x80\x80\x80": "\uFFFD\uFFFD\uFFFD\uFFFD\uFFFD\uFFFD",
    "\uD800": "\uFFFD\uFFFD\uFFFD", # lowest surrogate
    "\uD8FF": "\uFFFD\uFFFD\uFFFD", # highest surrogate
    "\uD83E\uDD72": "\uFFFD\uFFFD\uFFFD\uFFFD\uFFFD\uFFFD", # paired surrogates
    "\uD83C": "\uFFFD\uFFFD\uFFFD", # some unpaired surrogate
    "r\xC8sum\xC8s": "r\uFFFDsum\uFFFDs", # latin-1 mis-declared as UTF-8
    "\x41\xC0\xAF\x41\xF4\x80\x80\x41": "A\uFFFD\uFFFDA\uFFFDA",
  }
  for (s, t) in utf8_error:
    assert s.toValidUTF8() == t
    assert (s & 'x').toValidUTF8() == t & 'x'
    block:
      var ctx = initTextDecoderContext(csUtf8, bufLen = 2)
      var res = ""
      for i in 0 ..< s.len:
        for s in ctx.decode([uint8(s[i])], finish = i == s.high):
          res &= s
      assert res == t
    block:
      var ctx = initTextDecoderContext(csUtf8, bufLen = 2)
      var res = ""
      var i = 0
      while i < s.len:
        for s in ctx.decode(s.toOpenArrayByte(i, min(i + 2, s.len) - 1), finish = i + 2 >= s.len):
          res &= s
        i += 2
      assert res == t

proc testUTF16be() =
  const list = {
    "\0H\0e\0l\0l\0o\0,\0 \0w\0o\0r\0l\0d\0!": "Hello, world!",
    "\xD8\x00": "\uFFFD", # lowest surrogate (unpaired)
    "\xDB\xFF": "\uFFFD", # highest low surrogate (unpaired)
    "\xDC\x00": "\uFFFD", # lowest high surrogate (unpaired)
    "\xD8\xFF": "\uFFFD", # highest surrogate (unpaired)
    "\xD8\x3E\xDD\x72": "\u{1F972}", # paired surrogates
  }
  for (s, t) in list:
    assert s.decodeAll(csUtf16be) == t

proc testUTF16le() =
  const list = {
    "H\0e\0l\0l\0o\0,\0 \0w\0o\0r\0l\0d\0!\0": "Hello, world!",
    "\x00\xD8": "\uFFFD", # lowest surrogate (unpaired)
    "\xFF\xDB": "\uFFFD", # highest low surrogate (unpaired)
    "\x00\xDC": "\uFFFD", # lowest high surrogate (unpaired)
    "\xFF\xD8": "\uFFFD", # highest surrogate (unpaired)
    "\x3E\xD8\x72\xDD": "\u{1F972}", # paired surrogates
  }
  for (s, t) in list:
    assert s.decodeAll(csUtf16le) == t
  var s = ""
  var s8 = ""
  for i in 0 ..< 10:
    s &= "t\0e\0s\0t\0"
    s8 &= "test"
  var ctx = initTextDecoderContext(csUtf16le, bufLen = 32)
  var res = ""
  for s in ctx.decode(s.toOpenArrayByte(0, s.high), finish = true):
    res &= s
  assert res == s8

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

proc testWindows1250() =
  let sencoded = tisztaszivvel.encodeAll(csWindows1250)
  let sdecoded = sencoded.decodeAll(csWindows1250)
  assert sdecoded == tisztaszivvel

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

proc testWindows1252() =
  let sencoded = erlkoenig.encodeAll(csWindows1252)
  let sdecoded = sencoded.decodeAll(csWindows1252)
  assert sdecoded == erlkoenig

proc testIso8859_2() =
  let sencoded = tisztaszivvel.encodeAll(csIso8859_2)
  let sdecoded = sencoded.decodeAll(csIso8859_2)
  assert sdecoded == tisztaszivvel

proc testGetLocaleCharset() =
  assert getLocaleCharset("ja_JP.EUC_JP") == csEucJP
  assert getLocaleCharset("ja_JP.UTF-8") == csUtf8
  assert getLocaleCharset("") == csUtf8

proc testShiftJIS() =
  assert "\u2212".encodeAll(csShiftJIS) ==
    "\uFF0D".encodeAll(csShiftJIS)

proc testUTF8InvalidStream() =
  var ctx = initTextDecoderContext(csUtf8)
  var res = ""
  for slice in ctx.decode("\xc0a".toOpenArrayByte(0, 0), finish = false):
    res &= slice
  assert res == "\uFFFD"

proc testIso2022JP() =
  assert "\x1B\x24".decodeAll(csIso2022JP) == "\uFFFD$"
  assert "\x1B\x28".decodeAll(csIso2022JP) == "\uFFFD("
  assert "ｶﾀｶﾅ".encodeAll(csIso2022JP) == "\e$B%+%?%+%J\e(B"

proc testGb18030() =
  # surrogate
  let sencoded = "\uD800".encodeAll(csGb18030)
  let sdecoded = sencoded.decodeAll(csGb18030)
  assert sdecoded == "\uFFFD\uFFFD\uFFFD"
  # ranges
  let first = "\u0080".encodeAll(csGb18030)
  assert first == "\x81\x30\x81\x30"
  assert first.decodeAll(csGb18030) == "\u0080"
  let last = "\u{10000}".encodeAll(csGb18030)
  assert last == "\x90\x30\x81\x30"
  assert last.decodeAll(csGb18030) == "\u{10000}"
  assert "\xfe\x39\xfe\x40".decodeAll(csGb18030) == "\uFFFD9\uFA0C"
  # error with ASCII
  assert "\x81\x3a".decodeAll(csGb18030) == "\uFFFD:"

proc main() =
  testCJK()
  testUTF8Parts()
  testUTF8Valid()
  testUTF8Invalid()
  testUTF16be()
  testUTF16le()
  testWindows1250()
  testWindows1252()
  testIso8859_2()
  testGetLocaleCharset()
  testShiftJIS()
  testUTF8InvalidStream()
  testIso2022JP()
  testGb18030()

main()
