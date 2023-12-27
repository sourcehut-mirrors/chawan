import tags

type
  AtomFactory*[Atom] = ref object of RootObj
    strToAtomImpl*: AtomFactoryStrToAtom[Atom] ## Must never be nil.
    tagTypeToAtomImpl*: AtomFactoryTagTypeToAtom[Atom] ## Must never be nil.

  AtomFactoryStrToAtom*[Atom] =
    proc(factory: AtomFactory[Atom], s: string): Atom {.nimcall.}
      ## Turn a string `s` into an atom.

  AtomFactoryTagTypeToAtom*[Atom] =
    proc(factory: AtomFactory[Atom], t: TagType): Atom {.nimcall.}
      ## Turn a tagType `t` into an atom.
