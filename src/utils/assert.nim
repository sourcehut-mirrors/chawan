# like std/assertions, but accepts cstring so we can hook it to cowstr

{.push raises: [].}

import std/macros

type
  CFile {.importc: "FILE", header: "<stdio.h>", incompleteStruct.} = object

let chaStderr {.importc: "stderr", header: "<stdio.h>".}: ptr CFile

{.push importc, header: "<stdio.h>".}
proc fprintf(file: ptr CFile; msg: cstring): cint {.varargs.}
proc fflush(f: ptr CFile): cint
{.pop.}

proc chaFailedAssertImpl(line, column, len: int; file, expr, msg: cstring)
    {.noreturn.} =
  when nimvm:
    error("assertion failed: `" & $expr & "' " & $msg)
  else:
    writeStackTrace()
    discard fprintf(chaStderr, "Assertion failed: %s(%ld, %ld) `%s' %.*s",
      file, cast[clong](line), cast[clong](column), expr, cast[cint](len),
      msg)
    discard fflush(chaStderr)
  quit(1)

template chaAssertImpl(cond: bool; msg: cstring; len: int;
    expr: static string) =
  bind instantiationInfo
  mixin failedAssertImpl
  const loc = instantiationInfo()
  {.line: loc.}:
    mixin chaFailedAssertImpl
    chaFailedAssertImpl(loc.line, loc.column, len, cstring(loc.filename),
      cstring(expr), msg)

template chaAssert*(cond: untyped) =
  if unlikely(not cond):
    chaAssertImpl(cond, "", 0, astToStr(cond))

template chaAssert*(cond: untyped; msg: cstring; len: int) =
  ## Assert that `cond` evaluates to true, otherwise crash.
  ##
  ## It is valid for `cond` to have side effects.
  if not cond:
    chaAssertImpl(cond, msg, len, astToStr(cond))

template chaAssert*(cond: untyped; msg: cstring) =
  if unlikely(not cond):
    let cs = msg
    chaAssertImpl(cond, cs, cs.len, astToStr(cond))

template chaAssert*(cond: untyped; msg: static string) =
  if unlikely(not cond):
    chaAssertImpl(cond, cstring(msg), msg.len, astToStr(cond))

template chaDebugAssert*(cond: untyped; msg = cstring("")) =
  ## Like chaAssert, but only gets compiled in for debug builds, so `cond`
  ## must not have side effects.
  ##
  ## Use for assertions that are too expensive to make in release builds.
  when defined(debug):
    if unlikely(not cond):
      let cs = msg
      chaAssertImpl(cond, cs, cs.len, astToStr(cond))

template chaDebugAssert*(cond: untyped; msg: cstring; len: int) =
  when defined(debug):
    if unlikely(not cond):
      chaAssertImpl(cond, msg, len, astToStr(cond))

{.pop.} # raises: []
