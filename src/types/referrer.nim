{.push raises: [].}

import types/url

type ReferrerPolicy* = enum
  rpStrictOriginWhenCrossOrigin = "strict-origin-when-cross-origin"
  rpNoReferrer = "no-referrer"
  rpNoReferrerWhenDowngrade = "no-referrer-when-downgrade"
  rpStrictOrigin = "strict-origin"
  rpOrigin = "origin"
  rpSameOrigin = "same-origin"
  rpOriginWhenCrossOrigin = "origin-when-cross-origin"
  rpUnsafeURL = "unsafe-url"

const DefaultPolicy* = rpStrictOriginWhenCrossOrigin

proc getReferrer*(prev, target: URL; policy: ReferrerPolicy): string =
  let origin = prev.origin
  if origin.t == otOpaque:
    return ""
  if prev.schemeType notin {stHttp, stHttps} or
      target.schemeType notin {stHttp, stHttps}:
    return ""
  case policy
  of rpNoReferrer:
    return ""
  of rpNoReferrerWhenDowngrade:
    if prev.schemeType == stHttps and target.schemeType == stHttp:
      return ""
    return $origin & prev.pathname & prev.search
  of rpSameOrigin:
    if origin.isSameOrigin(target.origin):
      return $origin
    return ""
  of rpOrigin:
    return $origin
  of rpStrictOrigin:
    if prev.schemeType == stHttps and target.schemeType == stHttp:
      return ""
    return $origin
  of rpOriginWhenCrossOrigin:
    if not origin.isSameOrigin(target.origin):
      return $origin
    return $origin & prev.pathname & prev.search
  of rpStrictOriginWhenCrossOrigin:
    if prev.schemeType == stHttps and target.schemeType == stHttp:
      return $origin
    if not origin.isSameOrigin(target.origin):
      return $origin
    return $origin & prev.pathname & prev.search
  of rpUnsafeURL:
    return $origin & prev.pathname & prev.search

{.pop.} # raises: []
