# w3m's URI method map format.

import std/tables

import types/opt
import types/url
import utils/twtstr

type URIMethodMap* = object
  map*: Table[string, string]
  imageProtos*: seq[string]

proc rewriteURL(pattern, surl: string): string =
  result = ""
  var wasPerc = false
  for c in pattern:
    if wasPerc:
      if c == '%':
        result &= '%'
      elif c == 's':
        result &= surl
      else:
        result &= '%'
        result &= c
      wasPerc = false
    elif c != '%':
      result &= c
    else:
      wasPerc = true
  if wasPerc:
    result &= '%'

type URIMethodMapResult* = enum
  ummrNotFound, ummrSuccess, ummrWrongURL

proc findAndRewrite*(this: URIMethodMap; url: var URL): URIMethodMapResult =
  let s = this.map.getOrDefault(url.protocol)
  if s != "":
    let surl = s.rewriteURL($url)
    if x := parseURL(surl):
      url = x
      return ummrSuccess
    return ummrWrongURL
  return ummrNotFound

proc insert(this: var URIMethodMap; k, v: string) =
  if not this.map.hasKeyOrPut(k, v) and k.startsWith("img-codec+"):
    this.imageProtos.add(k.until(':'))

proc parseURIMethodMap*(this: var URIMethodMap; s: string) =
  for line in s.split('\n'):
    if line.len == 0 or line[0] == '#':
      continue # comments
    var k = line.untilLower(AsciiWhitespace + {':'})
    var i = k.len
    if i >= line.len or line[i] != ':':
      continue # invalid
    k &= ':'
    i = line.skipBlanks(i + 1) # skip colon
    var v = line.until(AsciiWhitespace, i)
    # Basic w3m compatibility.
    # If needed, w3m-cgi-compat covers more cases.
    if v.startsWith("file:/cgi-bin/"):
      v = "cgi-bin:" & v.substr("file:/cgi-bin/".len)
    elif v.startsWith("file:///cgi-bin/"):
      v = "cgi-bin:" & v.substr("file:///cgi-bin/".len)
    elif v.startsWith("/cgi-bin/"):
      v = "cgi-bin:" & v.substr("/cgi-bin/".len)
    this.insert(k, v)

proc parseURIMethodMap*(s: string): URIMethodMap =
  result = URIMethodMap()
  result.parseURIMethodMap(s)

proc append*(this: var URIMethodMap; that: URIMethodMap) =
  for k, v in that.map:
    this.insert(k, v)
