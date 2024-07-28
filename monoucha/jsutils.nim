import quickjs

template toJSValueArray*(a: openArray[JSValue]): ptr UncheckedArray[JSValue] =
  if a.len > 0:
    cast[ptr UncheckedArray[JSValue]](unsafeAddr a[0])
  else:
    nil

# Warning: this must be a template, because we're taking the address of
# the passed value, and Nim is pass-by-value.
template toJSValueArray*(a: JSValue): ptr UncheckedArray[JSValue] =
  cast[ptr UncheckedArray[JSValue]](unsafeAddr a)
