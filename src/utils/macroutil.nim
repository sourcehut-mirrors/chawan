{.push raises: [].}

import std/macros

proc isLent(t: NimNode): bool =
  let kind = t.kind
  # fast path
  if kind == nnkSym:
    return true
  if kind == nnkCall:
    return false
  # slow path
  var t = t
  while true:
    case t.kind
    of nnkCall, nnkCast, nnkInfix:
      # if it's a call, see below.
      # if it's a cast, preserve it.
      return false
    of nnkStmtList, nnkStmtListExpr:
      # check the last child
      t = t[^1]
    of nnkSym, nnkIdent, nnkConv, nnkDerefExpr, nnkDotExpr, nnkHiddenDeref,
        nnkBracketExpr, nnkCheckedFieldExpr:
      # if it's a symbol, see below.
      # if it's a deref, dot, or bracket expr, we don't need a decref.
      # if it's a bracket expr, that means we're accessing an array/seq,
      # which always produces lent, so we don't need decref.
      # if it's a conv, preserve it.
      break
    else:
      # might want to check if it doesn't leak...
      warning("handle kind " & $t.kind)
      break
  true

macro dotGet*(T, t: untyped): untyped =
  # Evil hack to work around compiler bugs:
  # * if t is a funcall, we have to use a cast so that we don't
  #   accidentally disarm the destroy hook.  e.g.,
  #     node.document = other.rootNode.document
  #     # if we desugar this to
  #     #   let tmp1 = (ptr NodeObj)(other)
  #     #   let tmp = (ptr NodeObj)(tmp1.rootNode)
  #     #   (ptr NodeObj)(node).document = tmp.document
  #     # then, since tmp is not considered a JSRef anymore, the
  #     # compiler won't bother unref'ing it.
  # * otherwise, t is derived from a symbol in the current scope.  in this
  #   case we we have to use a conversion to defeat move inference.  e.g.,
  #     document.window = window
  #     # if we only access window by casts from here on, it's not
  #     # accounted for in sink inference, and will get sink'ed in by the
  #     # previous assignment.
  #     window.document = document
  #   note that moves are inferred even based on object/array access
  #   so we have to be broader here.
  if isLent(t):
    quote do:
      `T`(`t`)
  else:
    quote do:
      cast[`T`](`t`)

proc isLocal*(t: NimNode): bool =
  # Check if a node is a local variable.
  let kind = t.kind
  # fast path
  if kind == nnkSym:
    return true
  if kind == nnkCall:
    return false
  # slow path
  var t = t
  while true:
    case t.kind
    of nnkCall, nnkInfix, nnkIfExpr, nnkObjConstr:
      return false
    of nnkSym, nnkIdent:
      break
    of nnkStmtList, nnkStmtListExpr, nnkConv:
      # check the last child
      t = t[^1]
    of nnkDerefExpr, nnkHiddenDeref, nnkDotExpr, nnkCheckedFieldExpr,
        nnkBracketExpr:
      # check the first child
      t = t[0]
    else:
      warning("handle kind " & $t.kind)
      return false
  true

{.pop.} # raises: []
