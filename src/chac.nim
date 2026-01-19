{.push raises: [].}

import std/os

import io/chafile
import monoucha/jsutils
import monoucha/quickjs
import types/opt

proc die(s: string) {.noreturn.} =
  discard cast[ChaFile](stderr).writeLine("chac: " & s)
  quit(1)

proc usage() {.noreturn.} =
  die("usage: chac [-s] ifile ofile")

proc bindMalloc(s: JSMallocStateP; size: csize_t): pointer {.cdecl.} =
  return alloc(size)

proc bindFree(s: JSMallocStateP; p: pointer) {.cdecl.} =
  if p != nil:
    dealloc(p)

proc bindRealloc(s: JSMallocStateP; p: pointer; size: csize_t): pointer
    {.cdecl.} =
  return realloc(p, size)

proc main() =
  let params = commandLineParams()
  var strip = false
  var ifile = ""
  var ofile = ""
  for param in params:
    if param == "-s":
      strip = true
    elif ifile == "":
      ifile = param
    elif ofile == "":
      ofile = param
    else:
      usage()
  if ifile == "" or ofile == "":
    usage()
  var mf {.global.} = JSMallocFunctions(
    js_malloc: bindMalloc,
    js_free: bindFree,
    js_realloc: bindRealloc,
    js_malloc_usable_size: nil
  )
  let rt = JS_NewRuntime2(addr mf, nil)
  if rt == nil:
    die("failed to allocate JS runtime")
  if strip:
    JS_SetStripInfo(rt, JS_STRIP_SOURCE or JS_STRIP_DEBUG)
  let ctx = JS_NewContext(rt)
  if ctx == nil:
    die("failed to allocate JS context")
  var src: string
  if chafile.readFile(ifile, src).isErr:
    die("failed to read " & ifile)
  let obj = ctx.eval(src, ifile,
    JS_EVAL_TYPE_MODULE or JS_EVAL_FLAG_COMPILE_ONLY)
  if JS_IsException(obj):
    die(ctx.getExceptionMsg())
  var plen: csize_t
  let p = cast[ptr UncheckedArray[char]](
    JS_WriteObject(ctx, addr plen, obj, JS_WRITE_OBJ_BYTECODE))
  if chafile.writeFile(ofile, p.toOpenArray(0, int(plen) - 1), 0o600).isErr:
    die("failed to write " & ofile)
  js_free(ctx, p)
  JS_FreeValue(ctx, obj)
  JS_FreeContext(ctx)
  JS_FreeRuntime(rt)

main()

{.pop.}
