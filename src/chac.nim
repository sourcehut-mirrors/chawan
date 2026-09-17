{.push raises: [].}

import io/chafile
import js/constcharp
import js/jsutils
import js/quickjs
import utils/chaos
import utils/opt

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
  var strip = false
  var ifile: cstring = nil
  var ofile: cstring = nil
  for param in getArgvIter():
    if param == "-s":
      strip = true
    elif ifile == nil:
      ifile = param
    elif ofile == nil:
      ofile = param
    else:
      usage()
  if ifile == nil or ofile == nil:
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
    die("failed to read " & $ifile)
  let obj = JS_Eval(ctx, src.toCStringConst, csize_t(src.len),
    cstringConst(ifile), JS_EVAL_TYPE_MODULE or JS_EVAL_FLAG_COMPILE_ONLY)
  if JS_IsException(obj):
    die(ctx.getExceptionMsg())
  var plen: csize_t
  let p = cast[ptr UncheckedArray[char]](
    JS_WriteObject(ctx, addr plen, obj, JS_WRITE_OBJ_BYTECODE))
  if chafile.writeFile(ofile, p.toOpenArray(0, int(plen) - 1), 0o600).isErr:
    die("failed to write " & $ofile)
  js_free(ctx, p)
  JS_FreeValue(ctx, obj)
  JS_FreeContext(ctx)
  JS_FreeRuntime(rt)

main()

{.pop.}
