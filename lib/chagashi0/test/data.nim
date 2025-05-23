import std/os
import std/streams
import std/unittest

import chagashi/decoder
import chagashi/encoder
import chagashi/charset

let dir = getEnv("CGS_TESTDIR")

proc runTestIn(test_in, test_in_ref: FileStream, label: string) =
  let cs = getCharset(label)
  assert cs != CHARSET_UNKNOWN
  let s = test_in.readAll()
  let td = newTextDecoder(cs)
  let ours = td.decodeAll(s)
  let theirs = test_in_ref.readAll()
  if ours != theirs:
    echo "ours vs theirs len ", ours.len, " ", theirs.len
    let helpfile = newFileStream(dir / "fail_in_" & label, fmWrite)
    helpfile.write(ours)
    assert false, "Failed in test" & label

proc runTestOut(test_out, test_out_ref: FileStream, label: string) =
  let cs = getCharset(label)
  assert cs != CHARSET_UNKNOWN
  let s = test_out.readAll()
  let te = newTextEncoder(cs)
  let ours = te.encodeAll(s)
  let theirs = test_out_ref.readAll()
  let match = ours == theirs
  if not match:
    echo "ours vs theirs len ", ours.len, " ", theirs.len
    let helpfile = newFileStream(dir / "fail_out_" & label, fmWrite)
    helpfile.write(ours)
    assert false, "Failed out test " & label

proc runTest(name: string, label: string, no_out = false) =
  let test_in = newFileStream(dir / name & "_in.txt")
  let test_in_ref = newFileStream(dir / name & "_in_ref.txt")
  runTestIn(test_in, test_in_ref, label)
  if not no_out:
    let test_out = newFileStream(dir / name & "_out.txt")
    let test_out_ref = newFileStream(dir / name & "_out_ref.txt")
    runTestOut(test_out, test_out_ref, label)

test "big5":
  runTest("big5", "big5")

test "euc-kr":
  runTest("euc_kr", "euc-kr")

test "euc-jp":
  runTest("jis0208", "euc-jp")
  runTest("jis0212", "euc-jp", no_out = true)

test "gb18030":
  runTest("gb18030", "gb18030")

test "iso-2022-jp":
  runTest("iso_2022_jp", "iso-2022-jp")

test "shift_jis":
  runTest("shift_jis", "shift_jis")
