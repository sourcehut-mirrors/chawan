import utils/twtstr

proc run() =
  assert "test".find("te") == 0
  assert "test".find("est") == 1
  assert "test".find("st") == 2
  assert "test".find("test") == 0
  assert "test".find("t") == 0
  assert "test".find("t", start = 5) == -1
  assert "test".find("t", start = 1) == 3

  assert "test".rfind("te") == 0
  assert "test".rfind("est") == 1
  assert "test".rfind("st") == 2
  assert "test".rfind("test") == 0
  assert "test".rfind("t") == 3
  assert "test".rfind("t", last = 3) == 3
  assert "test".rfind("t", last = 2) == 0
  assert "test".rfind("t", start = 1, last = 2) == -1

  assert "test".startsWith("test")
  assert not "test".startsWith("testt")
  assert "test".startsWith("t")
  assert "test".startsWith("")

static:
  run()

run()
