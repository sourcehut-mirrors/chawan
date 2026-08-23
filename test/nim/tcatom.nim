import html/catom

proc testAtom() =
  initCAtomFactory()
  var atom1 = new(ref CAtom)
  atom1[] = "asdf".toAtom()
  assert atom1[] == "asdf".toAtom(), "toAtom does not roundtrip"

  # simulate collision
  let h = atom1[].hash()
  let atom2 = "asdf2".toAtom()
  atom2.testSetHash(cast[int](uint(h) + 1))
  var atom3 = new(ref CAtom)
  atom3[] = "asdf3".toAtom()
  atom3[].testSetHash(h)
  block:
    var tmp: seq[CAtom]
    for i in 0 ..< CAtomFactoryInitSize div 2:
      tmp.add(("test" & $i).toAtom())
    # tmp is freed
  # after robin-hood, should be in order: atom1, atom3, atom2
  let idx1 = testGetIdx(atom1[])
  let idx2 = testGetIdx(atom2)
  let idx3 = testGetIdx(atom3[])
  assert ((idx1 + 1) and 0xFFF) == idx3
  assert ((idx3 + 1) and 0xFFF) == idx2
  # backshift atom2
  atom3 = nil
  let idx2After = testGetIdx(atom2)
  assert idx2After == idx1 + 1
  # atom2 is already at home, do nothing
  atom1 = nil
  let idx2AfterAfter = testGetIdx(atom2)
  assert idx2AfterAfter == idx2After

testAtom()
