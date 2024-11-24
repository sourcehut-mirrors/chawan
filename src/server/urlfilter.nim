import std/options

import monoucha/jsregex
import types/url

#TODO add denyhost/s for blocklists
type URLFilter* = object
  scheme: Option[string]
  allowschemes*: seq[string]
  allowhost*: Option[string]
  allowhosts: seq[Regex]
  default: bool

proc newURLFilter*(scheme = none(string); allowschemes: seq[string] = @[];
    allowhost = none(string); allowhosts: seq[Regex] = @[];
    default = false): URLFilter =
  doAssert scheme.isSome or allowschemes.len == 0,
    "allowschemes without scheme is not supported"
  return URLFilter(
    scheme: scheme,
    allowschemes: allowschemes,
    allowhost: allowhost,
    allowhosts: allowhosts,
    default: default
  )

# Filters as follows:
# If scheme/s are given, only URLs with the same scheme are matched.
# Then, allowhost and allowhosts are checked; if none of these match the host,
# the function returns the value of `default'.
proc match*(filter: URLFilter; url: URL): bool =
  block check_scheme:
    if filter.scheme.isSome and filter.scheme.get != url.scheme:
      for scheme in filter.allowschemes:
        if scheme == url.scheme:
          break check_scheme
      return false
  let host = url.host
  if filter.allowhost.isSome and filter.allowhost.get == host:
    return true
  for regex in filter.allowhosts:
    if regex.match(host):
      return true
  return filter.default
