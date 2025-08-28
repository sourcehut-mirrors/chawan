{.push raises: [].}

import quickjs

type
  JSPropertyEnumArray* = ptr UncheckedArray[JSPropertyEnum]

  JSPropertyEnumList* = object
    buffer*: JSPropertyEnumArray
    size: uint32
    len*: uint32
    ctx: JSContext

  JSPropertyEnumWrapper* = object
    is_enumerable: bool
    name: string

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

proc add*(this: var JSPropertyEnumList; val: uint32) =
  let i = this.len
  inc this.len
  if this.size < this.len:
    this.grow()
  this.buffer[i].atom = JS_NewAtomUInt32(this.ctx, val)

proc add*(this: var JSPropertyEnumList; val: string) =
  let i = this.len
  inc this.len
  if this.size < this.len:
    this.grow()
  this.buffer[i].atom = JS_NewAtomLen(this.ctx, cstring(val), csize_t(val.len))

{.pop.} # raises
