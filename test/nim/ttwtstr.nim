import utils/twtstr

proc testFind() =
  assert "test".find("te") == 0
  assert "test".find("est") == 1
  assert "test".find("st") == 2
  assert "test".find("test") == 0
  assert "test".find("t") == 0
  assert "test".find("t", start = 5) == -1
  assert "test".find("t", start = 1) == 3
  assert "".find("t") == -1
  assert "".find("t", start = 1) == -1
  assert "".find("") == 0
  assert "".find("", start = 1) == -1
  assert "test".find("") == 0
  assert "test".find("", start = 1) == 1

  assert "test".rfind('t') == 3
  assert "test".rfind('t', 0, last = 3) == 3
  assert "test".rfind('t', 0, last = 2) == 0
  assert "test".rfind('t', start = 1, last = 2) == -1

  assert "test".startsWith("test")
  assert not "test".startsWith("testt")
  assert "test".startsWith("t")
  assert "test".startsWith("")

  assert "a\tb ".containsToken("a")
  assert "a\tb ".containsToken("")
  assert "\na\tb ".containsToken("")
  assert not "ab".containsToken("")

proc testStrip() =
  assert " ".strip() == ""
  assert "\f\t test \r\n".strip() == "test"
  assert " test ".strip(trailing = false) == "test "
  assert " test ".strip(leading = false) == " test"
  assert " \tes\t ".strip(chars = {' '}) == "\tes\t"

proc testDelete() =
  var x = "test"
  x.delete(1..4)
  assert x == "t"

proc testContentType() =
  var s = "text/html; a = b"
  assert s.getContentTypeAttr("a") == "b"
  s.setContentTypeAttr("a", "test")
  assert s == "text/html; a =test"
  assert s.getContentTypeAttr("a") == "test"
  s.setContentTypeAttr("b", "test2")
  assert s.getContentTypeAttr("b") == "test2"
  assert "text/html; a=b; c=d".getContentTypeAttr("c") == "d"
  assert "text/html;a=b".getContentTypeAttr("a") == "b"
  assert "text/html;aa=b;a=c".getContentTypeAttr("a") == "c"
  assert "text/html;a=\"b\"".getContentTypeAttr("a") == "b"

proc run() =
  testFind()
  testStrip()
  testDelete()
  testContentType()

static:
  run()

run()
