import html/catom

proc testAtom() =
  initCAtomFactory()
  let atom1 = "asdf".toAtom()
  assert atom1 == "asdf".toAtom(), "toAtom does not roundtrip"

  # simulate collision
  let h = atom1.hash()
  let atom2 = "asdf2".toAtom()
  atom2.testSetHash(cast[int](uint(h) + 1))
  let atom3 = "asdf3".toAtom()
  atom3.testSetHash(h)
  var tmp: seq[CAtom]
  for i in 0 ..< CAtomFactoryInitSize div 2:
    tmp.add(("test" & $i).toAtom())
  for atom in tmp:
    freeAtom(atom)
  # after robin-hood, should be in order: atom1, atom3, atom2
  let idx1 = testGetIdx(atom1)
  let idx2 = testGetIdx(atom2)
  let idx3 = testGetIdx(atom3)
  assert ((idx1 + 1) and 0xFFF) == idx3
  assert ((idx3 + 1) and 0xFFF) == idx2
  # backshift atom2
  freeAtom(atom3)
  let idx2After = testGetIdx(atom2)
  assert idx2After == idx1 + 1
  # atom2 is already at home, do nothing
  freeAtom(atom1)
  let idx2AfterAfter = testGetIdx(atom2)
  assert idx2AfterAfter == idx2After

testAtom()
