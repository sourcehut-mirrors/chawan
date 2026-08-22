{.push raises: [].}

#TODO handle OOM

import quickjs

type
  JSPropertyEnumArray* = ptr UncheckedArray[JSPropertyEnum]

  JSPropertyEnumList* = object
    buffer*: JSPropertyEnumArray
    size: uint32
    len*: uint32
    ctx*: JSContext

proc newJSPropertyEnumList*(ctx: JSContext; size: uint32): JSPropertyEnumList =
  let p = if size != 0:
    js_malloc(ctx, csize_t(sizeof(JSPropertyEnum)) * csize_t(size))
  else:
    nil
  return JSPropertyEnumList(
    ctx: ctx,
    buffer: cast[JSPropertyEnumArray](p),
    size: size
  )

proc grow(this: var JSPropertyEnumList) =
  if this.size == 0:
    this.size = 1
  this.size *= 2
  let p = js_realloc(this.ctx, this.buffer,
    csize_t(sizeof(JSPropertyEnum)) * csize_t(this.size))
  this.buffer = cast[JSPropertyEnumArray](p)

proc add(this: var JSPropertyEnumList; atom: JSAtom) =
  let i = this.len
  inc this.len
  if this.size < this.len:
    this.grow()
  this.buffer[i].atom = atom

proc contains(this: JSPropertyEnumList; atom: JSAtom): bool =
  for i in 0 ..< this.len:
    if this.buffer[i].atom == atom:
      return true
  false

proc incl(this: var JSPropertyEnumList; atom: JSAtom) =
  if atom notin this:
    this.add(atom)
  else:
    JS_FreeAtom(this.ctx, atom)

proc add*(this: var JSPropertyEnumList; val: uint32) =
  let atom = JS_NewAtomUint32(this.ctx, val)
  this.add(atom)

proc add*(this: var JSPropertyEnumList; val: string) =
  let atom = JS_NewAtomLen(this.ctx, val.toCStringConst, csize_t(val.len))
  this.add(atom)

proc incl*(this: var JSPropertyEnumList; val: uint32) =
  let atom = JS_NewAtomUint32(this.ctx, val)
  this.incl(atom)

proc incl*(this: var JSPropertyEnumList; val: string) =
  let atom = JS_NewAtomLen(this.ctx, val.toCStringConst, csize_t(val.len))
  this.incl(atom)

{.pop.} # raises
